-- ============================================================================
-- 0342 · LA SEDE TAMBIÉN SE CAMBIA POR UNA PUERTA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cambiar `personas.sede_base_id` deje rastro en `correcciones_auditoria`
--   y solo lo haga quien ya podía hacerlo (admin o líder de DO) — ni más ni
--   menos permiso que hoy, pero con puerta y con rastro. Antes de esta
--   migración, `apps/web/.../admin/equipo/page.tsx` la escribía con un
--   `UPDATE` directo desde el navegador, sin auditoría y sin que ningún
--   trigger la capturara.
--
-- QUÉ ASUME
--   Que hoy nadie más que `equipo/page.tsx` escribe `sede_base_id` (verificado:
--   `select proname from pg_proc where prosrc ~ 'set\s+.*sede_base_id\s*='`
--   da cero filas — todo el repo la escribe por REST directo, nunca por RPC).
--
-- POR QUÉ IMPORTA — no es solo prolijidad de auditoría
--   `fn_planilla_calcular` computa la movilidad de TODO el periodo como
--   `días_trabajados × tarifa de la sede ACTUAL` (0166/0261), leyendo
--   `sede_base_id` (o `sede_fisica_id` si existe) en el momento del cálculo —
--   no la sede en la que la persona trabajó cada día. Es la misma familia de
--   defecto que tenía `regimen_pension` antes de la 0261 (un valor sin fecha
--   ni rastro, leído por planilla): cambiar la sede de alguien y luego
--   congelar o repagar su periodo movería el pago de movilidad de días ya
--   trabajados a la tarifa de la sede nueva, en silencio. Esta migración NO
--   resuelve ese cálculo (eso exigiría versionar `sede_base_id` con tramos,
--   al estilo `asignaciones_regimen_pension`, y auditarlo contra producción
--   antes de tocar `fn_planilla_calcular`) — solo cierra la puerta de entrada
--   para que, de aquí en más, todo cambio de sede quede escrito y explicado,
--   que es el primer paso que también dio la 0261 con `fn_cambiar_regimen_pension`.
--
-- POR QUÉ UN TRIGGER APARTE Y NO REESCRIBIR `fn_bloquear_rol_directo` (0296)
--   Se podría generalizar un solo trigger que bloquee varias columnas
--   protegidas de `personas`. Se descartó a propósito: `fn_bloquear_rol_directo`
--   ya está en producción, y tocarla exige primero el md5 de PRODUCCIÓN por la
--   regla de la casa para todo `CREATE OR REPLACE` sobre una función existente
--   — fricción real para un beneficio angosto. La 0296 ya eligió este mismo
--   camino (un trigger nuevo y angosto por columna protegida, en vez de tocar
--   los grants de la tabla) por la misma razón: mantener acotado el blast
--   radius sobre la tabla más usada del sistema. Esta migración repite ese
--   molde para `sede_base_id`, no lo reinventa.
--
-- CÓMO SE REVIERTE
--   drop trigger trg_personas_sede_solo_por_rpc on personas;
--   drop function fn_bloquear_sede_directa();
--   drop function fn_set_sede_base(uuid, uuid);
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final.
-- ============================================================================

create or replace function fn_set_sede_base(p_persona_id uuid, p_sede_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  uuid;
  v_estado text;
  v_quien  uuid;
  v_sede_nueva  text;
  v_sede_antes  text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la sede.';
  end if;

  if p_sede_id is null or not exists (select 1 from sedes where id = p_sede_id and activa) then
    raise exception 'Sede inválida o inactiva.';
  end if;

  select sede_base_id, estado into v_antes, v_estado
  from personas where id = p_persona_id;

  if not found then
    raise exception 'Persona inválida.';
  end if;

  if v_estado = 'inactivo' then
    raise exception 'No se puede cambiar la sede de una persona ya cesada: su liquidación se calculó con la sede anterior.';
  end if;

  if v_antes = p_sede_id then
    return;
  end if;

  update personas set sede_base_id = p_sede_id where id = p_persona_id;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  select codigo into v_sede_antes from sedes where id = v_antes;
  select codigo into v_sede_nueva from sedes where id = p_sede_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.sede_base_id', v_sede_antes, v_sede_nueva,
          'Cambio de sede base — puede mover la tarifa de movilidad del periodo abierto.',
          v_quien);
end;
$$;

comment on function fn_set_sede_base(uuid, uuid) is
  'Cambia la sede base de una persona. Solo admin o líder, y solo sobre sedes '
  'activas. Deja rastro en correcciones_auditoria porque la sede base decide la '
  'tarifa de movilidad que `fn_planilla_calcular` aplica a todo el periodo en '
  'curso (0166). No se permite sobre personas cesadas. 0342.';

revoke all on function fn_set_sede_base(uuid, uuid) from public, anon;
grant execute on function fn_set_sede_base(uuid, uuid) to authenticated;

-- ── El candado: ni siquiera un PATCH armado a mano se salta la puerta ──────
-- Mismo mecanismo que `fn_bloquear_rol_directo` (0296): `fn_set_sede_base`
-- corre `security definer`, así que mientras ejecuta `current_user` es el
-- dueño de la función, no la sesión que la llamó. Un UPDATE directo desde
-- PostgREST corre como `authenticated` — el trigger distingue exactamente eso.
create or replace function fn_bloquear_sede_directa()
returns trigger
language plpgsql as $function$
begin
  if new.sede_base_id is distinct from old.sede_base_id and current_user <> 'postgres' then
    raise exception 'La sede se cambia con fn_set_sede_base, no con un update directo.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_personas_sede_solo_por_rpc on personas;
create trigger trg_personas_sede_solo_por_rpc
  before update on personas
  for each row
  execute function fn_bloquear_sede_directa();

insert into migraciones_aplicadas (numero, nombre)
values (342, '0342_la_sede_tambien_se_cambia_por_una_puerta')
on conflict (numero) do nothing;

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_set_sede_base') as la_funcion_existe,
  (select count(*) from pg_trigger where tgname = 'trg_personas_sede_solo_por_rpc'
     and tgrelid = 'personas'::regclass) as el_trigger_existe;
