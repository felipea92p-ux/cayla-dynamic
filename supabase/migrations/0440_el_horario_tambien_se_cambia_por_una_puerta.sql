-- ============================================================================
-- 0440 · EL HORARIO TAMBIÉN SE CAMBIA POR UNA PUERTA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cambiar el horario base de una persona deje rastro en
--   `correcciones_auditoria` —quién lo hizo, cuándo, qué regía antes, qué
--   rige ahora y POR QUÉ, con un motivo que quien edita escribe cada vez— y
--   que ese motivo sea obligatorio. Auditoría UX/funcional de "Horarios base"
--   del 2026-09-14, decidido con Felipe: un texto fijo (el molde que ya usan
--   `fn_set_rol` y `fn_set_sede_base`) no sirve acá, porque el motivo real de
--   un cambio de horario varía caso a caso y es justo lo que hace falta para
--   responder una disputa de tardanza.
--
-- EL DEFECTO, EN UNA LÍNEA
--   `fn_set_horario_semanal` es, desde la 0184, la única puerta de escritura
--   de `horarios_asignados` — pero no pide motivo ni registra quién la usó.
--   Es el único campo sensible del sistema que no sigue el patrón de función
--   guardián que ya exigen el régimen de pensión (0261), el rol (0295/0296)
--   y la sede base (0342): los tres escriben en `correcciones_auditoria`, el
--   horario no escribe en ningún lado. Verificado antes de escribir esto:
--     select count(*) from information_schema.columns
--      where table_name = 'horarios_asignados' and column_name in ('motivo','creado_por');
--   da 0 — no hay ni un lugar preparado para eso, ni en la tabla ni en ningún
--   trigger.
--
-- Y HAY UNA PUERTA TRASERA REAL, NO SOLO TEÓRICA
--   `horarios_asignados` tiene una policy `horarios_write_admin_lider` sin
--   `FOR`, es decir, para INSERT/UPDATE/DELETE completos: cualquier admin o
--   líder de DO puede escribir la tabla directo por PostgREST, saltándose el
--   candado de periodo pagado, el recorte del tramo retroactivo, el
--   recálculo de jornadas y —de aquí en más— el motivo obligatorio. No es
--   hipotético: es la misma puerta trasera que cerraron `fn_bloquear_rol_directo`
--   (0296) y `fn_bloquear_sede_directa` (0342) para sus columnas.
--
-- POR QUÉ CAMBIA LA FIRMA Y NO SOLO EL CUERPO
--   `p_motivo` se agrega como cuarto parámetro, sin default. Un default
--   (ej. `default null`) dejaría pasar cualquier llamada vieja sin motivo,
--   que es exactamente lo que esta migración viene a cerrar — un guardián
--   que acepta quedarse callado enseña que no hace falta hablar. Como
--   `CREATE OR REPLACE FUNCTION` con una lista de parámetros distinta NO
--   reemplaza la función existente sino que crea una SEGUNDA función
--   sobrecargada (el mismo incidente que la 0297/0299: "dos puertas para la
--   misma pregunta conviviendo en silencio"), esta migración hace
--   `DROP FUNCTION` de la firma de 3 argumentos ANTES de crear la de 4 —
--   verificado que sigue siendo la única versión con `donde-vive.sh` y con
--   `pg_get_function_identity_arguments` (ver más abajo).
--
--   Todo caller existente se actualiza en la misma tanda, para no dejar la
--   firma vieja "casi sin usar" en ningún lado (grep hecho ANTES de escribir
--   esto, no después):
--     apps/web/app/(admin)/admin/horarios/page.tsx       (el modal — motivo libre)
--     apps/web/app/(admin)/admin/turnos/page.tsx  × 2     (motivo fijo, ver abajo)
--     supabase/tests/141_las_seis_puertas_a_una_planilla_pagada.test.sql
--     supabase/tests/243_dos_horarios_no_pueden_cubrir_el_mismo_dia.test.sql
--     supabase/tests/286_un_horario_retroactivo_recorta_el_tramo_que_pisa.test.sql
--     supabase/tests/300_fn_set_horario_semanal_gana_el_mismo_candado_que_objetivos.test.sql
--
-- POR QUÉ TURNOS.PAGE.TSX NO GANA UN CAMPO DE TEXTO LIBRE
--   Los dos llamadores de Turnos ("Hacer permanente" en Revisión de Turnos,
--   "De aquí en adelante" en la Vista Día) no son una persona explicando por
--   qué cambia un horario: son una acción de UN CLIC que promueve un turno
--   puntual ya escrito a regla base. El motivo ES el contexto de la acción,
--   no algo nuevo que inventar — pedirle a la encargada que lo escriba a
--   mano en dos pantallas más, para una frase que siempre diría lo mismo,
--   sería fricción sin información nueva. Mismo criterio que ya usan
--   `fn_set_rol`/`fn_set_sede_base` para SU único llamador: motivo fijo,
--   descriptivo, con la fecha del cambio. Solo el modal de "Horarios base"
--   —la única pantalla donde alguien decide y explica un cambio de
--   horario— pide el motivo libre.
--
-- LA PUERTA: MISMO MOLDE QUE fn_bloquear_sede_directa (0342), NO UNO NUEVO
--   `fn_bloquear_horario_directo` bloquea INSERT, UPDATE *y* DELETE —a
--   diferencia de 0296/0342, que solo blindan un UPDATE de columna, acá
--   hace falta blindar los tres verbos porque `fn_set_horario_semanal` usa
--   los tres (borra tramos futuros, cierra el que pisa, inserta el nuevo).
--   Mientras se ejecuta una función `security definer` de este repo,
--   `current_user` es su dueño (`postgres`), nunca la sesión que la llamó
--   (`authenticated` por PostgREST) — verificado antes de escribir esto que
--   las 13 funciones que tocan `horarios_asignados` son `security definer`
--   de `postgres` salvo `fn_recalcular_jornada`, que no escribe la tabla
--   (sólo la lee para calcular jornadas):
--     select p.proname, p.prosecdef, r.rolname
--       from pg_proc p join pg_roles r on r.oid = p.proowner
--      where p.prosrc ilike '%horarios_asignados%' and p.prokind = 'f';
--   Por eso el candado no rompe `fn_cesar_persona` ni `fn_reactivar_persona`
--   (0209), que también tocan la tabla desde su propio flujo: siguen
--   corriendo como `postgres`.
--
-- QUÉ NO CAMBIA
--   El candado de periodo pagado, el advisory lock (0380), el recorte del
--   tramo retroactivo (0360) y el recálculo de jornadas siguen exactamente
--   igual. La policy `horarios_write_admin_lider` NO se toca —igual que
--   0342 no tocó la de `personas`—: lo que de verdad cierra el camino
--   directo es el trigger, no la policy; achicar la policy es un cambio más
--   grande que se deja fuera a propósito.
--
-- MD5 DE PARTIDA — medido en esta Mac (Postgres local), ANTES de escribir
-- este cambio. Como manda la casa, esto NO reemplaza pedirlo a producción:
-- se vuelve a pedir en el mensaje en que se entregue este SQL, no en este.
--
--   fn_set_horario_semanal(uuid, date, jsonb)
--     tal_cual = eb4af9aafe78a7dd7bd58f39894909f2
--     sin_comentarios = 309cb1b1e12bccb649e98dc444f520f7
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
-- CÓMO SE REVIERTE
--   drop trigger trg_horarios_solo_por_rpc on horarios_asignados;
--   drop function fn_bloquear_horario_directo();
--   drop function fn_set_horario_semanal(uuid, date, jsonb, text);
--   -- y recrear la de 3 argumentos con el cuerpo de la 0380 (arriba) —
--   -- pero entonces hay que revertir también los tres callers y las 4
--   -- pruebas listadas arriba, o dejan de compilar contra la firma vieja.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final.
-- ============================================================================

-- La firma vieja se retira explícitamente — ver "POR QUÉ CAMBIA LA FIRMA" arriba.
drop function if exists fn_set_horario_semanal(uuid, date, jsonb);

create or replace function fn_set_horario_semanal(
  p_persona_id uuid, p_vigente_desde date, p_horario jsonb, p_motivo text
)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_editor uuid; r record;
  k text; v jsonb;
  v_dias int[]; v_min_entrada time; v_max_salida time;
  v_refri_min int; v_refri_max int;
  v_anterior record;
  v_valor_anterior text; v_valor_nuevo text;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción; v_editor = quien edita

  if p_motivo is null or length(btrim(p_motivo)) < 3 then
    raise exception 'Escribe el motivo del cambio de horario (mínimo 3 caracteres).';
  end if;

  perform pg_advisory_xact_lock(hashtext('horario_semanal:' || p_persona_id::text));

  if exists (
    select 1 from periodos_planilla pp
    where pp.fecha_fin >= p_vigente_desde
      and (
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
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
  for k, v in select * from jsonb_each(p_horario) loop
    if k !~ '^[0-6]$' then raise exception 'Día de la semana inválido: %', k; end if;
    if coalesce(v->>'e', '') = '' then raise exception 'Falta la hora de entrada del día %.', k; end if;
  end loop;

  select array_agg((t.k)::int order by (t.k)::int),
         min((t.v->>'e')::time),
         max(coalesce(nullif(t.v->>'s', '')::time, (t.v->>'e')::time)),
         min(coalesce((t.v->>'r')::int, 0)),
         max(coalesce((t.v->>'r')::int, 0))
    into v_dias, v_min_entrada, v_max_salida, v_refri_min, v_refri_max
  from jsonb_each(p_horario) as t(k, v);

  -- Estado anterior, para el rastro — capturado ANTES de tocar la tabla.
  select vigente_desde, horario_por_dia, dias_laborables, hora_entrada, hora_salida
    into v_anterior
    from horarios_asignados
   where persona_id = p_persona_id and vigente_hasta is null;

  v_valor_anterior := case
    when v_anterior is null then 'sin horario previo'
    else 'vigente desde ' || v_anterior.vigente_desde::text || ': ' ||
         coalesce(v_anterior.horario_por_dia::text,
                   'días ' || v_anterior.dias_laborables::text || ' ' ||
                   v_anterior.hora_entrada::text || '–' || v_anterior.hora_salida::text)
  end;
  v_valor_nuevo := 'vigente desde ' || p_vigente_desde::text || ': ' || p_horario::text;

  delete from horarios_asignados where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;

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

  for r in select fecha from jornadas where persona_id = p_persona_id and fecha >= p_vigente_desde loop
    perform fn_recalcular_jornada(p_persona_id, r.fecha);
  end loop;

  -- Rastro obligatorio (0440): quién, cuándo, qué regía, qué rige y por qué.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'horarios_asignados', v_valor_anterior, v_valor_nuevo, btrim(p_motivo), v_editor);
end;
$function$;

comment on function fn_set_horario_semanal(uuid, date, jsonb, text) is
  'Única puerta de escritura de horarios_asignados desde la 0184. Exige motivo '
  '(mínimo 3 caracteres) y deja rastro en correcciones_auditoria — quién, cuándo, '
  'qué regía y qué rige ahora. 0440.';

revoke all on function fn_set_horario_semanal(uuid, date, jsonb, text) from public, anon;
grant execute on function fn_set_horario_semanal(uuid, date, jsonb, text) to authenticated;

-- ── El candado: ni un insert/update/delete armado a mano se salta la puerta ──
-- Mismo mecanismo que fn_bloquear_rol_directo (0296) y fn_bloquear_sede_directa
-- (0342), extendido a los tres verbos porque fn_set_horario_semanal usa los tres.
create or replace function fn_bloquear_horario_directo()
returns trigger
language plpgsql as $function$
begin
  if current_user <> 'postgres' then
    raise exception 'Los horarios se cambian con fn_set_horario_semanal, no con un insert/update/delete directo.';
  end if;
  return coalesce(new, old);
end;
$function$;

drop trigger if exists trg_horarios_solo_por_rpc on horarios_asignados;
create trigger trg_horarios_solo_por_rpc
  before insert or update or delete on horarios_asignados
  for each row
  execute function fn_bloquear_horario_directo();

insert into migraciones_aplicadas (numero, nombre)
values (440, 'el_horario_tambien_se_cambia_por_una_puerta')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_set_horario_semanal') as cuantas_versiones_quedan,
  pg_get_function_identity_arguments(
    (select oid from pg_proc where proname = 'fn_set_horario_semanal')
  ) as firma_vigente,
  (select count(*) from pg_trigger where tgname = 'trg_horarios_solo_por_rpc'
     and tgrelid = 'horarios_asignados'::regclass) as el_trigger_existe;
