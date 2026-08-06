-- ============================================================================
-- 0176 — Quien ya se fue deja de tener sueldo vigente
-- ----------------------------------------------------------------------------
-- PROMETE:
--   1. Que nadie inactivo aparezca con un salario o un horario VIGENTE. Hoy hay
--      cuatro personas que se fueron en julio y siguen saliendo en la pantalla
--      de Equipo con «Colibrí · S/ 1 130.00» como si cobraran.
--   2. Que ningún tramo de salario u horario se extienda más allá del último día
--      que esa persona trabajó.
--   3. Que `motivo_cese` diga por qué se fue cada quien, en vez del marcador
--      `por_revisar` que la 0086 dejó a propósito para que se corrigiera a mano.
--   4. Que `fn_cesar_persona` explique en español lo que hoy responde con un
--      error de constraint de Postgres.
-- ASUME: la 0086 (fecha_cese, motivo_cese, fn_cesar_persona) y la 0174 (su
--   candado de fila, que esta migración conserva íntegro).
--
-- ── DE DÓNDE SALE ESTO ──────────────────────────────────────────────────────
--
-- Nadie hizo nada mal, y conviene decirlo antes de tocar datos de personas
-- reales. El 29/07/2026 hubo un ajuste de salarios que alcanzó a todo el equipo.
-- `fn_set_salario` comprueba que la persona esté activa, y ESE DÍA estas
-- personas figuraban activas: el ajuste era correcto cuando se hizo.
--
-- Lo que las volvió incoherentes fue el backfill de la 0086, seis días después:
-- dedujo la fecha de cese de cada una como «el último día que marcó» y la
-- escribió RETROACTIVAMENTE, por debajo de tramos de salario que ya existían.
-- Así quedó gente con fecha de cese el 16/07 y un salario que empieza el 29/07.
-- La 0086 no se equivocó al hacerlo: marcó las siete filas con `por_revisar`
-- precisamente porque sabía que esa fecha había que confirmarla a mano.
--
-- CONFIRMADO POR FELIPE EL 2026-08-06: se fueron el último día que laboraron y
-- no volvieron. O sea, las fechas de cese que hay son las correctas, y lo que
-- sobra son los tramos posteriores a ellas.
--
-- ── POR QUÉ UNOS SE BORRAN Y OTROS SE ACORTAN ───────────────────────────────
--
-- Son dos hechos distintos y no se pueden tratar igual:
--
--   · Un tramo que EMPIEZA después del cese no describe ningún hecho: esa
--     persona no trabajó un solo día bajo él. No se puede «cerrar» —el
--     constraint `vigente_hasta >= vigente_desde` lo impide, comprobado— así
--     que la única reparación honesta es borrarlo.
--   · Un tramo que empieza ANTES y se extiende más allá del cese sí describe un
--     hecho real: esa persona cobró bajo ese salario. Ese no se borra, se
--     ACORTA hasta su último día.
--
-- Todo lo que se borra o se acorta deja su fila en `correcciones_auditoria` con
-- el valor anterior completo. Un dato corregido sin rastro es indistinguible de
-- un dato que siempre estuvo así, y en un mes habría que volver a deducir todo
-- esto desde cero.
--
-- ── LO QUE ESTA MIGRACIÓN *NO* HACE ─────────────────────────────────────────
--
-- No borra a ninguna persona, y no es por prudencia abstracta: la planilla de
-- julio ya las contó y los reportes de ese periodo se apoyan en sus filas.
-- Borrarlas dejaría julio sin cuadrar. Se quedan inactivas, que es como este
-- sistema representa a quien ya no está.
--
-- Tampoco toca ni una fecha de cese ni un solo marcaje. Y no mueve plata:
-- medido contra el Postgres local con los datos reales de producción, la
-- liquidación de estas personas es S/ 0.00 antes y después —son RxH con 0 a 3
-- días trabajados—, así que esto es coherencia de datos, no dinero.
--
-- ── REVERTIR ────────────────────────────────────────────────────────────────
-- Los tramos borrados y los acortados están enteros en `correcciones_auditoria`
-- (busca `campo_modificado like 'tramo_%'`), con su valor anterior en texto: se
-- pueden volver a insertar a mano. El cambio de `motivo_cese` se revierte
-- poniendo 'por_revisar'. Y `fn_cesar_persona` vuelve corriendo su bloque tal
-- como está en la 0174 — esta migración solo le AGREGA dos avisos y conserva el
-- `for update` intacto.
-- ============================================================================

do $mig$
declare
  v_admin uuid;
  v_borrados_salario int := 0;
  v_borrados_horario int := 0;
  v_acortados_salario int := 0;
  v_acortados_horario int := 0;
  v_motivos int := 0;
  v_quedan int;
begin
  -- ¿Hay algo que corregir? Se pregunta ANTES de exigir un firmante. Sobre una
  -- base recién reconstruida con `supabase db reset` la tabla `personas` está
  -- vacía: no hay nada que arreglar y tampoco hay admin, y exigirlo ahí abortaría
  -- el reset entero y con él las pruebas. Comprobado el 2026-08-06.
  select count(*) into v_quedan
    from personas p
   where p.estado = 'inactivo' and p.fecha_cese is not null
     and (exists (select 1 from asignaciones_salario a where a.persona_id = p.id
                   and (a.vigente_hasta is null or a.vigente_hasta > p.fecha_cese
                        or a.vigente_desde > p.fecha_cese))
       or exists (select 1 from horarios_asignados h where h.persona_id = p.id
                   and (h.vigente_hasta is null or h.vigente_hasta > p.fecha_cese
                        or h.vigente_desde > p.fecha_cese))
       or (p.motivo_cese = 'por_revisar' and p.tipo_vinculo in ('rxh','prueba')));

  if v_quedan = 0 then
    raise notice '0176 · no hay nada que corregir: ninguna persona inactiva tiene tramos incoherentes.';
    return;
  end if;

  -- El rastro necesita un autor: `correcciones_auditoria.corregido_por` es NOT
  -- NULL. Se toma el admin más antiguo. Si hay datos que tocar y nadie que
  -- firme, la migración se detiene: corregir datos de personas sin poder decir
  -- quién lo hizo es exactamente lo que esa tabla existe para impedir.
  select id into v_admin from personas
   where rol = 'admin' and estado = 'activo' order by fecha_ingreso limit 1;
  if v_admin is null then
    raise exception '0176 · hay % persona(s) por corregir pero ningun admin activo que firme. No se toca nada.', v_quedan;
  end if;

  raise notice '0176 · personas por corregir: %', v_quedan;

  -- ── 1 · Tramos que empiezan DESPUÉS del cese: se guardan y se borran ───────
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  select a.persona_id, 'tramo_salario_borrado',
         'rango ' || a.rango || ' · S/ ' || a.salario_mensual_soles ||
         ' · del ' || to_char(a.vigente_desde, 'DD/MM/YYYY') ||
         ' al ' || coalesce(to_char(a.vigente_hasta, 'DD/MM/YYYY'), 'sin cerrar'),
         null, v_admin,
         'Migracion 0176: el tramo empieza despues del cese (' ||
         to_char(p.fecha_cese, 'DD/MM/YYYY') || '), no describe ningun dia trabajado'
    from asignaciones_salario a
    join personas p on p.id = a.persona_id
   where p.estado = 'inactivo' and p.fecha_cese is not null
     and a.vigente_desde > p.fecha_cese;

  delete from asignaciones_salario a
   using personas p
   where p.id = a.persona_id
     and p.estado = 'inactivo' and p.fecha_cese is not null
     and a.vigente_desde > p.fecha_cese;
  get diagnostics v_borrados_salario = row_count;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  select h.persona_id, 'tramo_horario_borrado',
         to_char(h.hora_entrada, 'HH24:MI') || '-' || to_char(h.hora_salida, 'HH24:MI') ||
         ' · del ' || to_char(h.vigente_desde, 'DD/MM/YYYY') ||
         ' al ' || coalesce(to_char(h.vigente_hasta, 'DD/MM/YYYY'), 'sin cerrar'),
         null, v_admin,
         'Migracion 0176: el horario empieza despues del cese (' ||
         to_char(p.fecha_cese, 'DD/MM/YYYY') || ')'
    from horarios_asignados h
    join personas p on p.id = h.persona_id
   where p.estado = 'inactivo' and p.fecha_cese is not null
     and h.vigente_desde > p.fecha_cese;

  delete from horarios_asignados h
   using personas p
   where p.id = h.persona_id
     and p.estado = 'inactivo' and p.fecha_cese is not null
     and h.vigente_desde > p.fecha_cese;
  get diagnostics v_borrados_horario = row_count;

  -- ── 2 · Tramos que se extienden más allá del cese: se acortan ─────────────
  -- Incluye los que quedaron abiertos (`vigente_hasta is null`), que es el caso
  -- que hace que la pantalla de Equipo muestre un sueldo vigente.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  select a.persona_id, 'tramo_salario_acortado',
         'terminaba el ' || coalesce(to_char(a.vigente_hasta, 'DD/MM/YYYY'), 'sin cerrar'),
         'termina el ' || to_char(p.fecha_cese, 'DD/MM/YYYY'), v_admin,
         'Migracion 0176: el salario no puede seguir vigente despues del ultimo dia trabajado'
    from asignaciones_salario a
    join personas p on p.id = a.persona_id
   where p.estado = 'inactivo' and p.fecha_cese is not null
     and a.vigente_desde <= p.fecha_cese
     and (a.vigente_hasta is null or a.vigente_hasta > p.fecha_cese);

  update asignaciones_salario a
     set vigente_hasta = p.fecha_cese
    from personas p
   where p.id = a.persona_id
     and p.estado = 'inactivo' and p.fecha_cese is not null
     and a.vigente_desde <= p.fecha_cese
     and (a.vigente_hasta is null or a.vigente_hasta > p.fecha_cese);
  get diagnostics v_acortados_salario = row_count;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  select h.persona_id, 'tramo_horario_acortado',
         'terminaba el ' || coalesce(to_char(h.vigente_hasta, 'DD/MM/YYYY'), 'sin cerrar'),
         'termina el ' || to_char(p.fecha_cese, 'DD/MM/YYYY'), v_admin,
         'Migracion 0176: el horario no puede seguir vigente despues del ultimo dia trabajado'
    from horarios_asignados h
    join personas p on p.id = h.persona_id
   where p.estado = 'inactivo' and p.fecha_cese is not null
     and h.vigente_desde <= p.fecha_cese
     and (h.vigente_hasta is null or h.vigente_hasta > p.fecha_cese);

  update horarios_asignados h
     set vigente_hasta = p.fecha_cese
    from personas p
   where p.id = h.persona_id
     and p.estado = 'inactivo' and p.fecha_cese is not null
     and h.vigente_desde <= p.fecha_cese
     and (h.vigente_hasta is null or h.vigente_hasta > p.fecha_cese);
  get diagnostics v_acortados_horario = row_count;

  -- ── 3 · El motivo real en vez de `por_revisar` ────────────────────────────
  -- Solo donde el vínculo lo dice sin ambigüedad. A quien esté en planilla no se
  -- le inventa un motivo: renuncia, despido y mutuo acuerdo no se deducen de
  -- ningún dato, y poner uno por otro cambia lo que un inspector lee.
  update personas
     set motivo_cese = case tipo_vinculo
                         when 'rxh'    then 'fin_servicio_rxh'
                         when 'prueba' then 'fin_periodo_prueba'
                       end
   where estado = 'inactivo'
     and motivo_cese = 'por_revisar'
     and tipo_vinculo in ('rxh', 'prueba');
  get diagnostics v_motivos = row_count;

  raise notice '0176 · tramos borrados por empezar despues del cese: % salario, % horario',
    v_borrados_salario, v_borrados_horario;
  raise notice '0176 · tramos acortados hasta el ultimo dia trabajado: % salario, % horario',
    v_acortados_salario, v_acortados_horario;
  raise notice '0176 · motivos de cese deducidos del vinculo: %', v_motivos;

  -- Comprobación, no confianza: un `update 0` se lee igual de discreto que un
  -- trabajo bien hecho.
  select count(*) into v_quedan
    from asignaciones_salario a join personas p on p.id = a.persona_id
   where p.estado = 'inactivo' and p.fecha_cese is not null
     and (a.vigente_hasta is null or a.vigente_hasta > p.fecha_cese
          or a.vigente_desde > p.fecha_cese);
  if v_quedan > 0 then
    raise exception '0176 · quedaron % tramos de salario incoherentes. La migracion no cumplio lo que promete.', v_quedan;
  end if;

  select count(*) into v_quedan
    from horarios_asignados h join personas p on p.id = h.persona_id
   where p.estado = 'inactivo' and p.fecha_cese is not null
     and (h.vigente_hasta is null or h.vigente_hasta > p.fecha_cese
          or h.vigente_desde > p.fecha_cese);
  if v_quedan > 0 then
    raise exception '0176 · quedaron % tramos de horario incoherentes.', v_quedan;
  end if;

  raise notice '0176 · verificado: ninguna persona inactiva tiene salario ni horario vigente.';
end $mig$;

-- ── 4 · Que la próxima vez lo diga en español ───────────────────────────────
-- Comprobado contra el Postgres local: cesar a alguien que tiene un tramo que
-- empieza DESPUÉS de la fecha de cese devuelve hoy
--   «new row for relation "asignaciones_salario" violates check constraint
--    "asignaciones_salario_check"»
-- que no le dice nada a quien está en la pantalla de Equipo ni le sugiere qué
-- hacer. El cuerpo es el de la 0174 —candado incluido, sin tocar— más dos
-- comprobaciones que se adelantan al constraint.
create or replace function fn_cesar_persona(
  p_persona_id uuid,
  p_fecha_cese date,
  p_motivo text,
  p_tipo_vinculo text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare v_p personas%rowtype; v_hoy date := (now() at time zone 'America/Lima')::date;
        v_desde date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un cese.';
  end if;

  -- 0174: toma el candado de la fila ANTES de mirar el estado, para que un
  -- segundo cese simultáneo espere aquí, relea la fila ya cesada y rebote.
  select * into v_p from personas where id = p_persona_id for update;
  if not found then raise exception 'La persona no existe.'; end if;
  if v_p.estado <> 'activo' then
    raise exception 'Esa persona ya está inactiva (cesó el %).', to_char(v_p.fecha_cese, 'DD/MM/YYYY');
  end if;

  -- La fecha tiene que ser posible.
  if p_fecha_cese > v_hoy then
    raise exception 'El último día trabajado no puede ser futuro (pusiste %).', to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;
  if p_fecha_cese < v_p.fecha_ingreso then
    raise exception 'El último día trabajado (%) no puede ser anterior a su ingreso (%).',
      to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_p.fecha_ingreso, 'DD/MM/YYYY');
  end if;

  -- No se cesa dentro de un periodo ya pagado: eso cambiaría el cálculo de una
  -- planilla cerrada. Mismo criterio que fn_set_fecha_ingreso (0037), acotado a
  -- esta persona para no congelar al equipo entero.
  if exists (select 1 from periodos_planilla pp
              where pp.estado = 'pagado'
                and p_fecha_cese between pp.fecha_ini and pp.fecha_fin) then
    raise exception 'El % cae dentro de un periodo de planilla ya PAGADO. Reabre ese periodo primero (queda rastro) o corrige la fecha.',
      to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;

  -- 0176: no se puede cerrar un tramo que todavía no empezó. Se avisa acá, con
  -- la fecha concreta y qué hacer, en vez de dejar que reviente el constraint.
  select min(vigente_desde) into v_desde from asignaciones_salario
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un salario que empieza el %, después del último día que pusiste (%). Corrige ese salario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;

  select min(vigente_desde) into v_desde from horarios_asignados
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un horario que empieza el %, después del último día que pusiste (%). Corrige ese horario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;

  -- Sus tramos se cierran. Hoy quedan abiertos para siempre y eso hace que un
  -- salario "vigente" siga apareciendo años después de que la persona se fue.
  update asignaciones_salario set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;
  update horarios_asignados  set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;

  update personas
     set estado = 'inactivo',
         fecha_cese = p_fecha_cese,
         motivo_cese = p_motivo,
         tipo_vinculo = coalesce(p_tipo_vinculo, tipo_vinculo),
         fecha_estado_cambio = now()
   where id = p_persona_id;
end;
$$;

grant  execute on function fn_cesar_persona(uuid, date, text, text) to authenticated;
revoke execute on function fn_cesar_persona(uuid, date, text, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (176, 'quien_ya_se_fue_deja_de_tener_sueldo_vigente')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_ok boolean;
begin
  select bool_or(prosrc like '%for update%') into v_ok
    from pg_proc where proname = 'fn_cesar_persona';
  if v_ok is not true then
    raise exception '0176 · se perdio el candado de la 0174 al reescribir fn_cesar_persona. NO des esto por aplicado.';
  end if;
  raise notice '0176 · el candado de la 0174 sigue puesto.';
end $mig$;
