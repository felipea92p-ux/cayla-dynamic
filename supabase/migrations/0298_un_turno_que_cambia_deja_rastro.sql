-- ============================================================================
-- 0298 — Un turno que cambia deja rastro
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cambiar, marcar como descanso o quitar el turno de un día quede
--   registrado: quién lo hizo, cuándo, y qué decía antes.
--
-- QUÉ ASUME
--   · Que `fn_set_turno` es la de la **0180**, y que `fn_quitar_turno` y
--     `fn_set_descanso` son las que están vivas hoy. Los tres cuerpos se
--     extrajeron de la base con `pg_get_functiondef()`; son cortos y se
--     reescriben enteros, así que no hay md5 de partida que declarar — lo que
--     importa es que ninguno de los tres tenía rastro y ahora los tres lo
--     tienen.
--   · Que `correcciones_auditoria` sigue siendo el libro transversal (0001) y
--     que `marcaje_id` admite null, como ya lo usan la 0125 y la 0277.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- `CLAUDE.md` lo dice sin matices: **toda edición manual deja rastro en
-- `correcciones_auditoria` con motivo obligatorio.** Los marcajes lo cumplen,
-- los salarios lo cumplen, el régimen de pensión lo cumple desde la 0277.
--
-- Los turnos no. La tabla no tiene ni `created_at` ni `creado_por`, y las tres
-- funciones que la escriben —`fn_set_turno`, `fn_set_descanso` y
-- `fn_quitar_turno`— hacen su `on conflict do update` o su `delete` sin
-- anotar nada. Las tres calculan `v_editor := fn_verificar_corrector(...)` para
-- validar el permiso… y **descartan el valor**. El dato que hace falta ya estaba
-- ahí, sin usarse.
--
-- Y esto no es un detalle de higiene, porque el turno del día **manda sobre el
-- horario base**: `apps/web/lib/admin/jornada-esperada.ts` consulta primero el
-- turno y solo después cae al horario semanal. O sea que el turno decide qué se
-- esperaba de esa persona ese día, y de ahí sale si llegó tarde, si salió antes
-- o si faltó.
--
-- Reescribir un turno puede hacer desaparecer una falta, y hoy no queda nada.
-- `fn_quitar_turno` es peor todavía: **borra la fila**, así que ni siquiera
-- queda el valor anterior.
--
-- El candado de periodo pagado sí está en las tres desde la 0037, así que nada
-- de esto alcanza a un mes ya cerrado. Lo que queda sin rastro es el periodo
-- abierto — que es justo donde todavía se decide lo que se va a pagar.
--
-- ── QUÉ CAMBIA ──────────────────────────────────────────────────────────────
--
-- 1 · `turnos` gana `created_at` y `creado_por`.
--
--     `created_at` va **nullable y sin backfill**, a propósito. Ponerle
--     `not null default now()` sellaría todas las filas viejas con la fecha de
--     hoy, que es falsa. Un null dice «no se sabe», que es verdad. Las filas
--     nuevas sí lo traen.
--
-- 2 · `fn_turno_texto` dice cómo se lee un turno en una línea. Existe para que
--     el formato se escriba UNA vez y las tres funciones no puedan divergir.
--
-- 3 · Las tres funciones anotan en `correcciones_auditoria` cuando de verdad
--     cambian algo, y guardan `creado_por`. No anotan cuando el turno nuevo es
--     idéntico al que había: un guardado que no cambia nada ensuciaría el libro
--     sin decir nada, que es el criterio que ya usan la 0125 y la 0277.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE, A PROPÓSITO ──────────────────────────────
--
-- No pide un motivo escrito por una persona. El rastro que deja es automático:
-- dice qué cambió y quién, no POR QUÉ. Pedirlo obligaría a cambiar la firma de
-- las tres funciones y el modal de la pantalla de Turnos, y eso es un cambio de
-- interfaz que merece decidirse aparte.
--
-- Queda anotado como el paso natural siguiente. Entre no tener rastro y tener
-- uno automático, el automático ya permite responder «quién movió este turno y
-- qué decía antes», que hoy no se puede responder de ninguna forma.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   Pegar los cuerpos de `fn_set_turno` (0180), `fn_quitar_turno` y
--   `fn_set_descanso` tal como estaban, y `drop function fn_turno_texto`. Las
--   dos columnas pueden quedarse: no molestan a nadie y guardan lo ya anotado.
--
-- ============================================================================


-- ── 1 · Las dos columnas que faltaban ───────────────────────────────────────

alter table turnos add column if not exists created_at timestamptz;
alter table turnos add column if not exists creado_por uuid references personas(id);

comment on column turnos.created_at is
  'Cuándo se escribió esta fila. NULL en las filas anteriores a la 0298, y eso '
  'es a propósito: sellarlas con la fecha de la migración habría sido inventar.';
comment on column turnos.creado_por is
  'Quién lo puso, vía fn_verificar_corrector. NULL en lo anterior a la 0298.';


-- ── 2 · Cómo se lee un turno, dicho una sola vez ────────────────────────────

create or replace function fn_turno_texto(
  p_es_descanso boolean,
  p_entrada     time,
  p_salida      time
) returns text
language sql
immutable
set search_path = public
as $$
  select case
           when p_es_descanso then 'descanso'
           when p_entrada is null then '(sin turno)'
           else to_char(p_entrada, 'HH24:MI')
                || '–' || coalesce(to_char(p_salida, 'HH24:MI'), '?')
         end;
$$;

comment on function fn_turno_texto(boolean, time, time) is
  'Un turno en una línea, para el libro de auditoría. Existe para que el formato '
  'se escriba una sola vez: las tres funciones que tocan turnos lo usan (0298).';


-- ── 3 · Las tres funciones, con rastro ──────────────────────────────────────

create or replace function fn_set_turno(
  p_persona_id uuid, p_fecha date,
  p_hora_entrada time without time zone, p_hora_salida time without time zone
) returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_editor uuid;
  v_antes  turnos;
  v_txt_antes text;
  v_txt_ahora text;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción
  if p_hora_entrada is null then
    raise exception 'La hora de entrada del turno es obligatoria.';
  end if;
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: cambiar el turno alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- CAMBIO 0298 — se guarda lo que había ANTES de pisarlo.
  select * into v_antes from turnos where persona_id = p_persona_id and fecha = p_fecha;

  insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen,
                      created_at, creado_por)
  values (p_persona_id, p_fecha, p_hora_entrada, p_hora_salida, false, 'panel',
          now(), v_editor)
  on conflict (persona_id, fecha) do update set
    hora_entrada = excluded.hora_entrada,
    hora_salida  = excluded.hora_salida,
    es_descanso  = false,
    origen       = 'panel',
    created_at   = now(),
    creado_por   = v_editor;

  v_txt_antes := case when v_antes.persona_id is null then '(sin turno)'
                      else fn_turno_texto(v_antes.es_descanso, v_antes.hora_entrada, v_antes.hora_salida) end;
  v_txt_ahora := fn_turno_texto(false, p_hora_entrada, p_hora_salida);

  if v_txt_antes is distinct from v_txt_ahora then
    insert into correcciones_auditoria
      (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (null, p_persona_id, 'turnos.horario', v_txt_antes, v_txt_ahora, v_editor,
            'Turno del ' || to_char(p_fecha, 'DD/MM/YYYY')
            || ' cambiado desde la pantalla de Turnos. El turno del día manda sobre el horario base, '
            || 'así que esto cambia lo que se esperaba de esa persona ese día.');
  end if;

  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$function$;


create or replace function fn_set_descanso(p_persona_id uuid, p_fecha date)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_editor uuid;
  v_antes  turnos;
  v_txt_antes text;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: marcar descanso ahí alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  select * into v_antes from turnos where persona_id = p_persona_id and fecha = p_fecha;

  insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen,
                      created_at, creado_por)
  values (p_persona_id, p_fecha, null, null, true, 'panel', now(), v_editor)
  on conflict (persona_id, fecha) do update set
    hora_entrada = null,
    hora_salida  = null,
    es_descanso  = true,
    origen       = 'panel',
    created_at   = now(),
    creado_por   = v_editor;

  v_txt_antes := case when v_antes.persona_id is null then '(sin turno)'
                      else fn_turno_texto(v_antes.es_descanso, v_antes.hora_entrada, v_antes.hora_salida) end;

  if v_txt_antes is distinct from 'descanso' then
    insert into correcciones_auditoria
      (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (null, p_persona_id, 'turnos.horario', v_txt_antes, 'descanso', v_editor,
            'El ' || to_char(p_fecha, 'DD/MM/YYYY') || ' pasa a descanso desde la pantalla de Turnos. '
            || 'Ese día deja de esperarse trabajo, así que deja de poder contarse como falta.');
  end if;

  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$function$;


create or replace function fn_quitar_turno(p_persona_id uuid, p_fecha date)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_editor uuid;
  v_antes  turnos;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: quitar el turno alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- CAMBIO 0298 — Esta es la que más lo necesitaba: BORRA la fila, así que sin
  -- esto no quedaba ni el valor anterior en ningún sitio.
  select * into v_antes from turnos where persona_id = p_persona_id and fecha = p_fecha;

  if v_antes.persona_id is not null then
    insert into correcciones_auditoria
      (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (null, p_persona_id, 'turnos.horario',
            fn_turno_texto(v_antes.es_descanso, v_antes.hora_entrada, v_antes.hora_salida),
            '(sin turno)', v_editor,
            'Turno del ' || to_char(p_fecha, 'DD/MM/YYYY') || ' quitado desde la pantalla de Turnos. '
            || 'Ese día vuelve a medirse contra el horario base de la persona.');
  end if;

  delete from turnos where persona_id = p_persona_id and fecha = p_fecha;
  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$function$;


insert into migraciones_aplicadas (numero, nombre)
values (298, 'un_turno_que_cambia_deja_rastro')
on conflict (numero) do nothing;
