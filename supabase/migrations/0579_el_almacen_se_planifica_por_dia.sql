-- ============================================================================
-- 0579 — El almacén se planifica por día
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la líder de equipo (o DO) pueda dejar escrito, con anticipación o el
--   mismo día, que una persona trabaja en ALMACÉN en vez de en PISO: todo su
--   turno, o uno o varios tramos «desde–hasta» que no se cruzan. Sin fila, la
--   persona está en piso. Turnos y cobertura descuenta del piso a quien está en
--   almacén; «Lo mío · Mis turnos» le dice a cada una dónde le toca; el
--   terminal se lo dice al marcar su entrada.
--
--   Es un PLAN. Lo que pasó de verdad lo registra el terminal en otra tabla
--   (cambios_ubicacion, 0580, otra sesión). Este plan NO cambia horas, turnos,
--   jornadas ni pago: no llama a fn_recalcular_jornada ni toca la tabla turnos.
--
-- QUÉ ASUME
--   · El almacén está dentro de la sede (otro piso, la trastienda): no es otra
--     sede y no cambia dónde se marca.
--   · Quién cuenta en piso lo sigue decidiendo cuentaEnCobertura
--     (packages/shared/src/cobertura-equipo.ts). Esto solo resta, por hora, a
--     quien está planificada en almacén.
--   · btree_gist está instalada (ya la usan periodos_planilla y otras; ver
--     0574:40). La necesita el `exclude` de abajo.
--
-- DECIDÍ (con Felipe, 2026-11-02)
--   · Varios tramos por día, sin que se crucen, para aprovechar las dos horas
--     flojas del día (p. ej. 10:30–12:00 y 15:00–16:30).
--   · Solo de hoy en adelante. Planificar un día que ya pasó reescribiría la
--     historia sin aportar nada: lo que pasó lo dice el terminal.
--   · La líder de equipo planifica a TODA su sede, incluida ella misma. Es
--     distinto de los turnos (fn_verificar_corrector, 0010, no la deja tocarse
--     a sí misma) y es a propósito: el almacén no toca horas ni pago, que es
--     lo que esa regla protege. Admin y Líder DO, sobre cualquier sede. Nadie
--     planifica el almacén de un admin o de un Líder DO, salvo ellos mismos.
--   · Quien planifica tiene que estar ACTIVA. fn_verificar_corrector no lo
--     mira (lee personas.rol sin filtrar estado); para algo nuevo no se
--     hereda ese hueco.
--   · Una sola puerta de escritura, fn_set_almacen_del_dia, que REEMPLAZA el
--     plan completo de ese día de una vez (todo el turno, una lista de tramos,
--     o nada = piso). Así la pantalla no tiene que coordinar varias llamadas y
--     un plan no puede quedar a medias.
--
-- DESCARTÉ
--   · Un tipo de marca nuevo («salida_almacen»): la máquina de estados del
--     marcaje lo leería como una pausa y tocaría horas. El almacén no es una
--     ausencia.
--   · Columnas en la tabla turnos: un turno es el horario esperado, que decide
--     tardanzas, faltas y el auto-cierre. Mezclar ahí el puesto obligaba a
--     reescribir fn_set_turno, fn_set_descanso y fn_quitar_turno (y a pedir su
--     md5 a producción) para algo que no toca el pago.
--   · Limpiar el plan cuando ese día se marca descanso o se quita el turno: lo
--     mismo, obligaba a reescribir esas funciones. El plan de un día sin turno
--     se IGNORA al leer (la pantalla avisa), que es más barato y no pierde nada.
--   · Una política de escritura por RLS: la tabla solo se escribe por la
--     función. Se revocan todos los privilegios y se devuelve solo SELECT
--     (molde de la 0480:99-100), porque por defecto authenticated nace con
--     INSERT/UPDATE/DELETE/TRUNCATE sobre toda tabla nueva de public.
--
-- ESTADOS QUE NUNCA DEBEN EXISTIR (y quién lo impide)
--   · Un tramo con solo una de las dos horas → CHECK puesto_tramo_completo.
--   · Un tramo que termina antes de empezar → CHECK puesto_tramo_ordenado.
--   · Dos tramos del mismo día que se cruzan, o «todo el turno» junto con un
--     tramo → EXCLUDE puesto_sin_cruces (todo el turno ocupa 00:00–24:00).
--   · Un plan escrito por un cliente sin pasar por la función → no hay
--     privilegio de escritura (revoke all).
--
-- SE ROMPE SI
--   · Alguien escribe en puestos_planificados sin pasar por
--     fn_set_almacen_del_dia: se pierde el rastro en correcciones_auditoria.
--   · Se renombra la tabla o fn_puestos_del_dia: la leen la sesión de «Lo mío»
--     (rama claude/mis-turnos-tu-semana) y el terminal (0580, otra sesión).
--
-- CONTRATO DE LECTURA (para Lo mío, el terminal y Turnos)
--   · puestos_planificados(persona_id, fecha, desde, hasta): una fila por tramo
--     en almacén. desde y hasta null = todo el turno en almacén (y entonces es
--     la única fila de ese día). Sin filas = piso.
--   · La leen por RLS: admin y Líder DO (todo), la líder de equipo (personas de
--     su sede base), la propia persona (sus filas) y el terminal (las personas
--     de su roster).
--   · fn_puestos_del_dia(p_sede_id, p_fecha) → (persona_id, desde, hasta): el
--     plan de un día para las personas que marcan en esa sede. La llaman el
--     terminal de esa sede, admin, Líder DO y la líder de esa sede.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_puestos_del_dia(uuid, date);
--   drop function if exists fn_set_almacen_del_dia(uuid, date, boolean, jsonb);
--   drop function if exists fn_puesto_texto(uuid, date);
--   drop table if exists puestos_planificados;   -- solo si nadie lo usa ya
--   delete from migraciones_aplicadas where numero = 579;
--   (Las filas de correcciones_auditoria con campo 'turnos.puesto' se quedan:
--   son historia.)
--
-- CÓMO SE COMPRUEBA
--   La consulta del final debe devolver una fila con todo en true y
--   «579 · el_almacen_se_planifica_por_dia».
--
-- No reescribe ninguna función existente: no lleva md5 de partida.
-- ============================================================================

-- ── 1 · La tabla ─────────────────────────────────────────────────────────────

create table if not exists puestos_planificados (
  id          uuid primary key default gen_random_uuid(),
  persona_id  uuid not null references personas(id),
  fecha       date not null,
  desde       time,
  hasta       time,
  creado_por  uuid not null references personas(id),
  created_at  timestamptz not null default now(),
  constraint puesto_tramo_completo check ((desde is null) = (hasta is null)),
  constraint puesto_tramo_ordenado check (desde is null or hasta > desde)
);

comment on table puestos_planificados is
  'Lo PLANIFICADO de piso o almacén: una fila por tramo en almacén de una persona en un día. '
  'desde y hasta null = todo el turno en almacén. Sin filas = piso. No toca horas ni pago. '
  'Se escribe solo por fn_set_almacen_del_dia (0579).';

-- Dos tramos del mismo día no se cruzan, y «todo el turno» (00:00–24:00) no
-- convive con ningún tramo. En minutos desde la medianoche, con el fin abierto:
-- 10:30–12:00 y 12:00–13:00 se tocan pero no se cruzan.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'puesto_sin_cruces') then
    alter table puestos_planificados
      add constraint puesto_sin_cruces exclude using gist (
        persona_id with =,
        fecha with =,
        int4range(
          (extract(hour from coalesce(desde, time '00:00')) * 60 + extract(minute from coalesce(desde, time '00:00')))::int,
          case when hasta is null then 1440
               else (extract(hour from hasta) * 60 + extract(minute from hasta))::int end,
          '[)'
        ) with &&
      );
  end if;
end;
$$;

create index if not exists idx_puestos_planificados_fecha on puestos_planificados (fecha, persona_id);

-- ── 2 · Quién la lee (RLS) y quién la escribe (nadie, salvo la función) ──────

alter table puestos_planificados enable row level security;

drop policy if exists puestos_select_admin_lider on puestos_planificados;
create policy puestos_select_admin_lider on puestos_planificados
  for select to authenticated
  using (fn_es_admin_o_lider());

drop policy if exists puestos_select_supervisor on puestos_planificados;
create policy puestos_select_supervisor on puestos_planificados
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede'
         and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));

drop policy if exists puestos_select_propia on puestos_planificados;
create policy puestos_select_propia on puestos_planificados
  for select to authenticated
  using (persona_id = fn_persona_actual_id());

-- La forma de la 0409, no la de la 0013: un subselect sobre personas dentro de
-- la política nunca le devolvió filas al terminal.
drop policy if exists puestos_select_terminal on puestos_planificados;
create policy puestos_select_terminal on puestos_planificados
  for select to authenticated
  using (fn_persona_en_roster_terminal(persona_id));

revoke all on puestos_planificados from anon, authenticated, public;
grant select on puestos_planificados to authenticated;

-- ── 3 · El texto de un plan, para el rastro ──────────────────────────────────

create or replace function fn_puesto_texto(p_persona_id uuid, p_fecha date)
returns text
language sql
stable
set search_path = public
as $$
  select case
    when count(*) = 0 then 'Piso'
    when bool_or(desde is null) then 'Almacén todo el turno'
    else 'Almacén ' || string_agg(to_char(desde, 'HH24:MI') || '–' || to_char(hasta, 'HH24:MI'), ', ' order by desde)
  end
  from puestos_planificados
  where persona_id = p_persona_id and fecha = p_fecha;
$$;

revoke all on function fn_puesto_texto(uuid, date) from public, anon, authenticated;

-- ── 4 · La única puerta de escritura ─────────────────────────────────────────

create or replace function fn_set_almacen_del_dia(
  p_persona_id     uuid,
  p_fecha          date,
  p_todo_el_turno  boolean,
  p_tramos         jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_editor_id   uuid;
  v_editor_rol  rol_usuario;
  v_editor_sede uuid;
  v_obj_rol     rol_usuario;
  v_obj_sede    uuid;
  v_obj_activa  boolean;
  v_tramo       jsonb;
  v_desde       time;
  v_hasta       time;
  v_previo      time;
  v_txt_antes   text;
  v_txt_ahora   text;
begin
  -- Un solo plan a la vez por persona y día: dos líderes guardando el mismo día
  -- a la vez no se mezclan.
  perform pg_advisory_xact_lock(hashtext('fn_set_almacen_del_dia:' || p_persona_id::text || ':' || p_fecha::text));

  -- Quién planifica: activa, y con un rol que puede.
  select id, rol, sede_base_id into v_editor_id, v_editor_rol, v_editor_sede
    from personas where auth_user_id = auth.uid() and estado = 'activo';
  if v_editor_rol is null then
    raise exception 'No autorizado.';
  end if;

  select rol, sede_base_id, (estado = 'activo') into v_obj_rol, v_obj_sede, v_obj_activa
    from personas where id = p_persona_id;
  if v_obj_activa is not true then
    raise exception 'Esa persona no está activa: no se le puede planificar el almacén.';
  end if;

  if v_editor_rol in ('admin', 'lider_do') then
    null; -- cualquier sede
  elsif v_editor_rol = 'supervisor_sede' then
    if v_obj_sede is distinct from v_editor_sede then
      raise exception 'Solo puedes planificar el almacén de tu propia sede.';
    end if;
    if v_obj_rol in ('admin', 'lider_do') and p_persona_id is distinct from v_editor_id then
      raise exception 'No puedes planificar el almacén de un administrador.';
    end if;
  else
    raise exception 'Tu rol no permite planificar el almacén.';
  end if;

  -- Qué se puede planificar.
  if p_fecha is null or p_fecha < fn_hoy_lima() then
    raise exception 'El almacén se planifica de hoy en adelante: ese día ya pasó.';
  end if;
  if fn_fecha_en_periodo_pagado(p_fecha, p_persona_id) is true then
    raise exception 'Esa fecha cae en un periodo ya PAGADO. Reabre el periodo primero.';
  end if;
  if p_todo_el_turno is null then
    raise exception 'Falta decir si va todo el turno al almacén.';
  end if;
  if p_tramos is null or jsonb_typeof(p_tramos) <> 'array' then
    raise exception 'Los tramos tienen que venir como una lista.';
  end if;
  if p_todo_el_turno and jsonb_array_length(p_tramos) > 0 then
    raise exception 'Todo el turno en almacén no lleva tramos.';
  end if;
  if jsonb_array_length(p_tramos) > 6 then
    raise exception 'Son demasiados tramos para un día (máximo 6).';
  end if;

  -- Los tramos, en orden y sin cruzarse. El EXCLUDE de la tabla lo impide igual;
  -- esto es para decirlo con palabras antes de que lo diga la base.
  v_previo := null;
  for v_tramo in
    select t from jsonb_array_elements(p_tramos) t
    order by (t->>'desde')::time
  loop
    v_desde := (v_tramo->>'desde')::time;
    v_hasta := (v_tramo->>'hasta')::time;
    if v_desde is null or v_hasta is null then
      raise exception 'Cada tramo necesita su hora de ida y su hora de vuelta.';
    end if;
    if v_hasta <= v_desde then
      raise exception 'El tramo de % a % termina antes de empezar.', to_char(v_desde, 'HH24:MI'), to_char(v_hasta, 'HH24:MI');
    end if;
    if v_previo is not null and v_desde < v_previo then
      raise exception 'Dos tramos de almacén se cruzan a las %.', to_char(v_desde, 'HH24:MI');
    end if;
    v_previo := v_hasta;
  end loop;

  -- Lo de antes, para el rastro; después se reemplaza el plan entero del día.
  v_txt_antes := fn_puesto_texto(p_persona_id, p_fecha);

  delete from puestos_planificados where persona_id = p_persona_id and fecha = p_fecha;

  if p_todo_el_turno then
    insert into puestos_planificados (persona_id, fecha, desde, hasta, creado_por)
    values (p_persona_id, p_fecha, null, null, v_editor_id);
  else
    insert into puestos_planificados (persona_id, fecha, desde, hasta, creado_por)
    select p_persona_id, p_fecha, (t->>'desde')::time, (t->>'hasta')::time, v_editor_id
      from jsonb_array_elements(p_tramos) t;
  end if;

  v_txt_ahora := fn_puesto_texto(p_persona_id, p_fecha);

  if v_txt_antes is distinct from v_txt_ahora then
    insert into correcciones_auditoria
      (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (null, p_persona_id, 'turnos.puesto', v_txt_antes, v_txt_ahora, v_editor_id,
            'Puesto del ' || to_char(p_fecha, 'DD/MM/YYYY')
            || ' planificado desde la pantalla de Turnos. Dice si trabaja en piso o en almacén; '
            || 'no cambia sus horas, su turno ni su pago.');
  end if;
end;
$$;

comment on function fn_set_almacen_del_dia(uuid, date, boolean, jsonb) is
  'Reemplaza el plan de piso/almacén de una persona en un día: p_todo_el_turno, o p_tramos '
  '[{"desde":"10:30","hasta":"12:00"},…], o ninguno = piso. De hoy en adelante. Deja rastro en '
  'correcciones_auditoria (turnos.puesto). No toca turnos ni jornadas. 0579.';

grant execute on function fn_set_almacen_del_dia(uuid, date, boolean, jsonb) to authenticated;
revoke execute on function fn_set_almacen_del_dia(uuid, date, boolean, jsonb) from public, anon;

-- ── 5 · La lectura de un día para una sede ───────────────────────────────────

create or replace function fn_puestos_del_dia(p_sede_id uuid, p_fecha date)
returns table (persona_id uuid, desde time, hasta time)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if (fn_es_admin_o_lider()
      or (fn_rol_actual() = 'supervisor_sede' and fn_sede_actual_persona() = p_sede_id)
      or fn_sede_actual_terminal() = p_sede_id) is not true then
    raise exception 'No autorizado.';
  end if;

  return query
    select p.persona_id, p.desde, p.hasta
      from puestos_planificados p
     where p.fecha = p_fecha
       and fn_persona_marca_en_sede(p.persona_id, p_sede_id) is true
     order by p.persona_id, p.desde nulls first;
end;
$$;

comment on function fn_puestos_del_dia(uuid, date) is
  'El plan de piso/almacén de un día para las personas que marcan en esa sede. La llaman el terminal '
  'de esa sede, admin, Líder DO y la líder de equipo de esa sede. 0579.';

grant execute on function fn_puestos_del_dia(uuid, date) to authenticated;
revoke execute on function fn_puestos_del_dia(uuid, date) from public, anon;

-- ── 6 · Registro ─────────────────────────────────────────────────────────────

insert into migraciones_aplicadas (numero, nombre) values (579, 'el_almacen_se_planifica_por_dia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regclass('public.puestos_planificados') is not null                                  as la_tabla_existe,
  (select relrowsecurity from pg_class where oid = 'public.puestos_planificados'::regclass) as tiene_rls,
  (select count(*) = 4 from pg_policy where polrelid = 'public.puestos_planificados'::regclass) as cuatro_politicas,
  not has_table_privilege('authenticated', 'public.puestos_planificados', 'INSERT')          as nadie_escribe_directo,
  exists (select 1 from pg_constraint where conname = 'puesto_sin_cruces')                  as sin_cruces,
  to_regprocedure('fn_set_almacen_del_dia(uuid,date,boolean,jsonb)') is not null            as la_funcion_existe,
  to_regprocedure('fn_puestos_del_dia(uuid,date)') is not null                              as la_lectura_existe,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 579)          as registro;
