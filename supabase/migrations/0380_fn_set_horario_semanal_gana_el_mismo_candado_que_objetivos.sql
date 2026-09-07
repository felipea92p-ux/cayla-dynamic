-- ============================================================================
-- 0380_fn_set_horario_semanal_gana_el_mismo_candado_que_objetivos.sql
-- ============================================================================
-- QUÉ ARREGLA. fn_set_horario_semanal no tiene ningún candado contra dos
-- llamadas casi simultáneas para la misma persona — un doble clic antes de
-- que React deshabilite el botón, o dos pestañas abiertas por la misma
-- encargada. La 0360 corrigió el recorte del tramo retroactivo, pero no le
-- dio el mismo tratamiento que la 0361 sí le dio a fn_objetivos_copiar_mes_anterior:
-- un pg_advisory_xact_lock por persona.
--
-- QUÉ PASABA SIN EL CANDADO. Dos llamadas casi simultáneas para la misma
-- persona corren su `delete`/`update` de recorte en paralelo, y la segunda
-- puede chocar contra la restricción de exclusión `horarios_sin_solape`
-- (0309) — con el primer INSERT de la primera llamada ya confirmado. El
-- mensaje traducido en pantalla («ese rango ya tiene otro horario asignado»)
-- sugiere un conflicto con OTRO horario, cuando en realidad el primer clic
-- de la MISMA persona ya guardó exactamente lo pedido. La encargada, leyendo
-- ese mensaje, puede creer que falló y reintentar con una fecha distinta —
-- dejando un horario incorrecto que alimenta jornadas y pago.
--
-- POR QUÉ UN ADVISORY LOCK Y NO OTRA COSA. Mismo criterio que la 0361: es la
-- forma más barata de serializar sin bloquear a nadie más que a la misma
-- persona, y se libera solo al terminar la transacción (xact_lock), sin
-- necesitar un UNLOCK explícito ni arriesgar dejarlo tomado si la función
-- lanza una excepción a mitad de camino.
--
-- QUÉ NO CAMBIA. Ni un carácter del cuerpo salvo la línea del candado,
-- agregada como primera instrucción tras validar el permiso — antes de
-- cualquier lectura o escritura sobre horarios_asignados. El resto del
-- cuerpo es el vigente de la 0360.
--
-- MD5 DE PARTIDA — medido en esta Mac (Postgres local), ANTES de escribir
-- este cambio. Como manda la casa, esto NO reemplaza pedirlo a producción:
-- se vuelve a pedir en el mensaje en que se entregue este SQL, no en este.
--
--   fn_set_horario_semanal   tal_cual = 8c386384054fe06e2bc011208cc46355
--                    sin_comentarios = a24bc09d90b4ac4ad66b78ca51a2ddb7
--
--   select md5(p.prosrc) as tal_cual,
--          md5(array_to_string(array(
--            select regexp_replace(l, '[[:space:]]*--.*$', '')
--            from unnest(string_to_array(p.prosrc, chr(10))) as l
--            where btrim(l) not like '--%'
--          ), chr(10)))                 as sin_comentarios
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'fn_set_horario_semanal';
--
-- CÓMO SE REVIERTE. Restaurar el cuerpo de la 0360 tal cual — pero no se
-- debería: eso reabre la carrera entre llamadas simultáneas.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_set_horario_semanal(p_persona_id uuid, p_vigente_desde date, p_horario jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_editor uuid; r record;
  k text; v jsonb;
  v_dias int[]; v_min_entrada time; v_max_salida time;
  v_refri_min int; v_refri_max int;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción

  -- CAMBIO 0380 — mismo candado que la 0361 le dio a Objetivos: serializa
  -- dos llamadas casi simultáneas para la MISMA persona, en vez de dejarlas
  -- chocar contra horarios_sin_solape con un mensaje que confunde.
  perform pg_advisory_xact_lock(hashtext('horario_semanal:' || p_persona_id::text));

  if exists (
    select 1 from periodos_planilla pp
    where pp.fecha_fin >= p_vigente_desde
      and (
        -- Compatibilidad: un periodo con estado='pagado' pero SIN ninguna fila
        -- en periodo_grupo_pago es de antes de la 0323 (el bucket único de
        -- siempre) — se sigue leyendo por el agregado.
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
        -- El caso normal desde la 0323: el GRUPO de esta persona, no el
        -- periodo entero.
        exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = p_persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
  ) then
    raise exception 'Ese horario tocaría un periodo ya PAGADO (recalcula las jornadas desde esa fecha en adelante). Reabre el periodo primero.';
  end if;

  if p_horario is null or jsonb_typeof(p_horario) <> 'object'
     or (select count(*) from jsonb_object_keys(p_horario)) = 0 then
    raise exception 'Debe trabajar al menos un día a la semana.';
  end if;
  -- validar claves (0-6) y que cada día tenga hora de entrada
  for k, v in select * from jsonb_each(p_horario) loop
    if k !~ '^[0-6]$' then raise exception 'Día de la semana inválido: %', k; end if;
    if coalesce(v->>'e', '') = '' then raise exception 'Falta la hora de entrada del día %.', k; end if;
  end loop;

  -- resumen para columnas legacy: min entrada / max salida / días / refrigerio (min-max por día).
  -- nullif protege el casteo si 's' llegara vacío (cae a la hora de entrada).
  select array_agg((t.k)::int order by (t.k)::int),
         min((t.v->>'e')::time),
         max(coalesce(nullif(t.v->>'s', '')::time, (t.v->>'e')::time)),
         min(coalesce((t.v->>'r')::int, 0)),
         max(coalesce((t.v->>'r')::int, 0))
    into v_dias, v_min_entrada, v_max_salida, v_refri_min, v_refri_max
  from jsonb_each(p_horario) as t(k, v);

  -- reemplazar tramos que empiezan en/después de la fecha, cerrar el anterior
  delete from horarios_asignados where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;

  -- SE RECORTA EL TRAMO QUE PISA, NO SOLO EL ABIERTO (0360). Un tramo que ya
  -- terminó antes de la fecha no se toca: no pisa nada.
  update horarios_asignados set vigente_hasta = p_vigente_desde - 1
    where persona_id = p_persona_id
      and vigente_desde < p_vigente_desde
      and (vigente_hasta is null or vigente_hasta >= p_vigente_desde);

  insert into horarios_asignados (
    persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
    almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia
  )
  values (
    p_persona_id, p_vigente_desde, null, v_min_entrada, coalesce(v_max_salida, v_min_entrada),
    v_refri_min, v_refri_max, v_dias, p_horario
  );

  -- recalcular tardanzas desde la fecha de vigencia
  for r in select fecha from jornadas where persona_id = p_persona_id and fecha >= p_vigente_desde loop
    perform fn_recalcular_jornada(p_persona_id, r.fecha);
  end loop;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (380, 'fn_set_horario_semanal_gana_el_mismo_candado_que_objetivos')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  position('advisory_xact_lock' in pg_get_functiondef('fn_set_horario_semanal'::regproc)) > 0 as tiene_el_candado;
