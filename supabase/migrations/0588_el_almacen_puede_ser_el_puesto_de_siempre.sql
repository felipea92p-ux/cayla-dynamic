-- ============================================================================
-- 0588 · EL ALMACÉN PUEDE SER EL PUESTO DE SIEMPRE
-- ============================================================================
--
-- QUÉ PROMETE
--   Que en una tienda se pueda dejar escrito que el puesto BASE de una persona
--   es el almacén —todo su turno, todos los días que trabaja, desde una fecha y
--   hasta que se cambie— y no solo día por día como desde la 0579. Y que el plan
--   de un día siga mandando sobre esa base: «solo este día en piso», «solo este
--   día unas horas en almacén».
--
--   La regla, de una sola vez y en un solo sitio (`fn_puestos_resueltos`):
--     1. Si ese día tiene un plan propio (puestos_planificados), manda ese plan.
--        Una fila nueva, `puesto = 'piso'`, dice «este día en piso» aunque su
--        base sea el almacén.
--     2. Si no, manda su puesto base (puestos_base) de esa fecha.
--     3. Si no hay base, piso, como siempre.
--
--   Es un PLAN, igual que la 0579: no toca horas, turnos, jornadas ni pago.
--
-- DE DÓNDE SALE (Felipe, 2026-11-03)
--   · «Plasmar desde Horarios quién tiene de base ir a tienda o almacén.»
--   · «Si ese día te vas a tienda o almacén, ponerlo si solo es por ese día
--     (completo o solo por tramo), o si se queda ahí siempre en almacén en todo
--     su horario predeterminado.» → «Siempre» es el turno entero; los tramos son
--     de un día.
--
-- QUÉ ASUME
--   · La 0579 pegada (puestos_planificados, fn_set_almacen_del_dia,
--     fn_puestos_del_dia, fn_puesto_texto) — la guardia lo exige.
--   · El almacén es solo de las tiendas (0583): la base se niega fuera de una
--     sede de tipo tienda.
--
-- MD5 DE PARTIDA (pedidos a PRODUCCIÓN el 2026-11-03, antes de escribir; los
-- tres coinciden con la 0579 tal cual, sin `\r`):
--   · fn_set_almacen_del_dia   edb1fa7dcda4a72ba00606124d074cfa · 4 538
--   · fn_puestos_del_dia       d59154849c76a1f056afaf911fd989a0 ·   480
--   · fn_puesto_texto          177f07025d13fdc615f8f81b5ae1ba3a ·   317
--   Los cambios van marcados «CAMBIO 0588» dentro de cada cuerpo.
--
-- POR QUÉ ASÍ
--   · Una tabla propia (`puestos_base`) y no una columna en
--     `horarios_asignados`: el horario base se escribe por
--     `fn_set_horario_semanal`, que decide tardanzas y faltas; reescribirla para
--     algo que no toca el pago es el riesgo equivocado. El puesto base tiene su
--     propia vigencia y su propia puerta (`fn_set_puesto_base`).
--   · Una fila de `puestos_base` = un periodo en que su base es el almacén.
--     Fuera de esos periodos, piso. No hay filas de «piso»: no hacen falta.
--   · El plan de un día gana siempre, para que «solo este día» signifique eso
--     aunque la base cambie después. Y por eso «en piso» se anota como fila
--     SOLO si ese día su base es el almacén: si la base es piso, no hay nada que
--     anotar, igual que antes. Así, mientras el código viejo siga en el aire
--     (entre pegar esto y fusionar el PR), nadie escribe una fila «piso» que él
--     leería como «todo el turno en almacén»: para eso haría falta una base, y
--     la base solo la escribe la pantalla nueva.
--   · `fn_puestos_resueltos` es SECURITY INVOKER: lee las dos tablas con las
--     políticas de cada quien, así que ve exactamente lo que ya veía en
--     puestos_planificados (admin y Líder DO todo, la líder su sede, cada una lo
--     suyo, el terminal su roster). Las mismas cuatro políticas se copian a
--     puestos_base.
--   · «Siempre, desde el día D» reemplaza lo programado desde D (borra las
--     bases que empezaban en D o después: son futuro, no historia) y cierra la
--     vigente el día D − 1. Los días con un plan propio desde D lo conservan.
--
-- ESTADOS QUE NUNCA
--   · Dos bases de la misma persona que se cruzan → EXCLUDE puesto_base_sin_cruces.
--   · Una base que termina antes de empezar → CHECK puesto_base_ordenado.
--   · Una fila «piso» con horas, o junto a otra fila del mismo día → CHECK
--     puesto_piso_entero + el EXCLUDE puesto_sin_cruces de la 0579 (sin horas =
--     00:00–24:00, que choca con cualquier otra).
--   · Una base escrita sin pasar por la función → no hay privilegio de escritura.
--   · Un almacén de base fuera de una tienda → fn_set_puesto_base se niega.
--
-- SE ROMPE SI
--   · Alguien lee puestos_planificados directo en vez de fn_puestos_resueltos:
--     no ve la base, y una fila «piso» le parece «todo el turno en almacén».
--     Este PR pasa a la función los tres que leían directo (Turnos, «Mis
--     turnos» y el terminal).
--
-- CÓMO SE REVIERTE
--   Repegar los cuerpos de la 0579 de las tres funciones, y:
--   drop function if exists fn_puestos_resueltos(date, date);
--   drop function if exists fn_set_puesto_base(uuid, date, text, text);
--   drop function if exists fn_puesto_base_es_almacen(uuid, date);
--   delete from puestos_planificados where puesto = 'piso';
--   alter table puestos_planificados drop column if exists puesto;
--   drop table if exists puestos_base;          -- solo si nadie la usa ya
--   (Las filas de correcciones_auditoria con campo 'horarios.puesto_base' se
--   quedan: son historia.)
--
-- CÓMO SE COMPRUEBA
--   La consulta del final: todo en true y «588 · el_almacen_puede_ser_el_puesto_de_siempre».
-- ============================================================================

-- ── 0 · Guardia ─────────────────────────────────────────────────────────────
do $guardia$
begin
  if to_regclass('public.puestos_planificados') is null
     or to_regprocedure('fn_set_almacen_del_dia(uuid,date,boolean,jsonb)') is null
     or to_regprocedure('fn_puestos_del_dia(uuid,date)') is null then
    raise exception 'Falta la 0579 (el almacén se planifica por día): esta migración no entra sin ella.';
  end if;
end
$guardia$;

-- ── 1 · El puesto base ──────────────────────────────────────────────────────
create table if not exists puestos_base (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references personas(id),
  vigente_desde  date not null,
  vigente_hasta  date,
  creado_por     uuid not null references personas(id),
  created_at     timestamptz not null default now(),
  constraint puesto_base_ordenado check (vigente_hasta is null or vigente_hasta >= vigente_desde)
);

comment on table puestos_base is
  'Periodos en que el puesto BASE de una persona es el almacén (todo su turno, todos los días que trabaja). '
  'Fuera de ellos, piso. El plan de un día (puestos_planificados) manda sobre esto. No toca horas ni pago. '
  'Se escribe solo por fn_set_puesto_base y se lee por fn_puestos_resueltos (0588).';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'puesto_base_sin_cruces') then
    alter table puestos_base
      add constraint puesto_base_sin_cruces exclude using gist (
        persona_id with =,
        daterange(vigente_desde, coalesce(vigente_hasta, 'infinity'::date), '[]') with &&
      );
  end if;
end;
$$;

create index if not exists idx_puestos_base_persona on puestos_base (persona_id, vigente_desde);

alter table puestos_base enable row level security;

-- Las mismas cuatro de puestos_planificados (0579): quien veía el plan de un día ve también la base.
drop policy if exists puestos_base_select_admin_lider on puestos_base;
create policy puestos_base_select_admin_lider on puestos_base
  for select to authenticated
  using (fn_es_admin_o_lider());

drop policy if exists puestos_base_select_supervisor on puestos_base;
create policy puestos_base_select_supervisor on puestos_base
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede'
         and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));

drop policy if exists puestos_base_select_propia on puestos_base;
create policy puestos_base_select_propia on puestos_base
  for select to authenticated
  using (persona_id = fn_persona_actual_id());

drop policy if exists puestos_base_select_terminal on puestos_base;
create policy puestos_base_select_terminal on puestos_base
  for select to authenticated
  using (fn_persona_en_roster_terminal(persona_id));

revoke all on puestos_base from anon, authenticated, public;
grant select on puestos_base to authenticated;

-- ── 2 · «Este día en piso» aunque su base sea el almacén ────────────────────
alter table puestos_planificados add column if not exists puesto text not null default 'almacen';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'puesto_valido') then
    alter table puestos_planificados
      add constraint puesto_valido check (puesto in ('almacen', 'piso'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'puesto_piso_entero') then
    -- «Piso» es el día entero: sin horas. Así ocupa 00:00–24:00 en el EXCLUDE de la 0579 y no convive con un tramo.
    alter table puestos_planificados
      add constraint puesto_piso_entero check (puesto = 'almacen' or (desde is null and hasta is null));
  end if;
end;
$$;

comment on column puestos_planificados.puesto is
  '''almacen'' (el tramo, o todo el turno si no tiene horas) o ''piso'' (todo el día en piso aunque su puesto base '
  'sea el almacén; solo se anota en ese caso). 0588.';

-- ── 3 · ¿Su base es el almacén esa fecha? ───────────────────────────────────
create or replace function fn_puesto_base_es_almacen(p_persona_id uuid, p_fecha date)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1 from puestos_base b
     where b.persona_id = p_persona_id
       and b.vigente_desde <= p_fecha
       and (b.vigente_hasta is null or b.vigente_hasta >= p_fecha)
  );
$$;

revoke all on function fn_puesto_base_es_almacen(uuid, date) from public, anon, authenticated;

-- ── 4 · La regla, en un solo sitio ──────────────────────────────────────────
-- Devuelve los tramos EN ALMACÉN ya resueltos: lo del día si lo hay (sin las
-- filas «piso», que justamente dicen que no va), y si no, la base. Misma forma
-- que puestos_planificados + `origen` ('dia' o 'base'). Sin filas = piso.
create or replace function fn_puestos_resueltos(p_desde date, p_hasta date)
returns table (persona_id uuid, fecha date, desde time, hasta time, origen text)
language plpgsql
stable
security invoker
set search_path = public
as $fn$
#variable_conflict use_column
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'El rango de fechas no es válido.';
  end if;
  if p_hasta - p_desde > 62 then
    raise exception 'Se pueden pedir hasta 62 días de puestos a la vez.';
  end if;

  return query
  with del_dia as (
    select p.persona_id, p.fecha, p.desde, p.hasta, p.puesto
      from puestos_planificados p
     where p.fecha between p_desde and p_hasta
  ),
  de_base as (
    select b.persona_id, d.d::date as fecha
      from puestos_base b
      join generate_series(p_desde, p_hasta, interval '1 day') d(d)
        on d.d::date >= b.vigente_desde and (b.vigente_hasta is null or d.d::date <= b.vigente_hasta)
     where not exists (select 1 from del_dia x where x.persona_id = b.persona_id and x.fecha = d.d::date)
  )
  select x.persona_id, x.fecha, x.desde, x.hasta, 'dia'::text
    from del_dia x
   where x.puesto = 'almacen'
  union all
  select y.persona_id, y.fecha, null::time, null::time, 'base'::text
    from de_base y
  order by 1, 2, 3 nulls first;
end
$fn$;

comment on function fn_puestos_resueltos(date, date) is
  'Los tramos en almacén de cada persona y día, ya resueltos: el plan del día manda; si no hay, su puesto base; '
  'si no, piso (sin filas). desde/hasta null = todo el turno. origen = dia | base. Lee con las políticas de cada '
  'quien (SECURITY INVOKER). Hasta 62 días. 0588.';

revoke all on function fn_puestos_resueltos(date, date) from public, anon;
grant execute on function fn_puestos_resueltos(date, date) to authenticated;

-- ── 5 · El texto de un plan, para el rastro (reescribe la 0579) ─────────────
create or replace function fn_puesto_texto(p_persona_id uuid, p_fecha date)
returns text
language sql
stable
set search_path = public
as $$
  -- CAMBIO 0588: «piso» explícito, y la base cuando el día no tiene plan propio.
  select case
    when bool_or(puesto = 'piso') then 'Piso'
    when bool_or(desde is null) then 'Almacén todo el turno'
    when count(*) > 0 then 'Almacén ' || string_agg(to_char(desde, 'HH24:MI') || '–' || to_char(hasta, 'HH24:MI'), ', ' order by desde)
    when fn_puesto_base_es_almacen(p_persona_id, p_fecha) then 'Almacén todo el turno (su puesto base)'
    else 'Piso'
  end
  from puestos_planificados
  where persona_id = p_persona_id and fecha = p_fecha;
$$;

revoke all on function fn_puesto_texto(uuid, date) from public, anon, authenticated;

-- ── 6 · La puerta del plan de un día (reescribe la 0579) ────────────────────
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
  elsif jsonb_array_length(p_tramos) > 0 then
    insert into puestos_planificados (persona_id, fecha, desde, hasta, creado_por)
    select p_persona_id, p_fecha, (t->>'desde')::time, (t->>'hasta')::time, v_editor_id
      from jsonb_array_elements(p_tramos) t;
  elsif fn_puesto_base_es_almacen(p_persona_id, p_fecha) then
    -- CAMBIO 0588: su puesto base es el almacén y este día va a piso: se anota, porque
    -- sin fila mandaría la base. Si la base es piso, no hay nada que anotar (como antes).
    insert into puestos_planificados (persona_id, fecha, desde, hasta, puesto, creado_por)
    values (p_persona_id, p_fecha, null, null, 'piso', v_editor_id);
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
  '[{"desde":"10:30","hasta":"12:00"},…], o ninguno = piso (si su puesto base es el almacén, se anota «piso» '
  'para ese día). De hoy en adelante. Deja rastro en correcciones_auditoria (turnos.puesto). No toca turnos ni '
  'jornadas. 0579, 0588.';

grant execute on function fn_set_almacen_del_dia(uuid, date, boolean, jsonb) to authenticated;
revoke execute on function fn_set_almacen_del_dia(uuid, date, boolean, jsonb) from public, anon;

-- ── 7 · La puerta del puesto base ───────────────────────────────────────────
create or replace function fn_set_puesto_base(
  p_persona_id uuid,
  p_desde      date,
  p_puesto     text,
  p_motivo     text default null
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
  v_antes       boolean;
  v_ya_igual    boolean;
begin
  perform pg_advisory_xact_lock(hashtext('fn_set_puesto_base:' || p_persona_id::text));

  -- Quién: las mismas reglas que el plan de un día (fn_set_almacen_del_dia, 0579).
  select id, rol, sede_base_id into v_editor_id, v_editor_rol, v_editor_sede
    from personas where auth_user_id = auth.uid() and estado = 'activo';
  if v_editor_rol is null then
    raise exception 'No autorizado.';
  end if;

  select rol, sede_base_id, (estado = 'activo') into v_obj_rol, v_obj_sede, v_obj_activa
    from personas where id = p_persona_id;
  if v_obj_activa is not true then
    raise exception 'Esa persona no está activa: no se le puede cambiar el puesto base.';
  end if;

  if v_editor_rol in ('admin', 'lider_do') then
    null;
  elsif v_editor_rol = 'supervisor_sede' then
    if v_obj_sede is distinct from v_editor_sede then
      raise exception 'Solo puedes cambiar el puesto base de las personas de tu propia sede.';
    end if;
    if v_obj_rol in ('admin', 'lider_do') and p_persona_id is distinct from v_editor_id then
      raise exception 'No puedes cambiar el puesto base de un administrador.';
    end if;
  else
    raise exception 'Tu rol no permite cambiar el puesto base.';
  end if;

  -- Qué.
  if p_puesto is null or p_puesto not in ('almacen', 'piso') then
    raise exception 'El puesto base es «piso» o «almacen».';
  end if;
  if p_desde is null or p_desde < fn_hoy_lima() then
    raise exception 'El puesto base se cambia de hoy en adelante.';
  end if;
  if fn_fecha_en_periodo_pagado(p_desde, p_persona_id) is true then
    raise exception 'Esa fecha cae en un periodo ya PAGADO. Reabre el periodo primero.';
  end if;
  if p_puesto = 'almacen'
     and not exists (select 1 from sedes s where s.id = v_obj_sede and s.tipo = 'tienda') then
    raise exception 'El almacén es solo de las tiendas: esa persona no tiene almacén en su sede.';
  end if;

  v_antes := fn_puesto_base_es_almacen(p_persona_id, p_desde);

  -- Ya es así desde antes y sin nada programado después: no hay nada que cambiar.
  v_ya_igual := (p_puesto = 'almacen') = v_antes
    and not exists (select 1 from puestos_base b where b.persona_id = p_persona_id and b.vigente_desde > p_desde)
    and (p_puesto = 'piso' or exists (select 1 from puestos_base b where b.persona_id = p_persona_id
                                        and b.vigente_desde <= p_desde and b.vigente_hasta is null));
  if v_ya_igual then
    return;
  end if;

  -- «Desde D, siempre así»: lo programado desde D se reemplaza (es futuro, no historia)
  -- y lo vigente se cierra el día anterior.
  delete from puestos_base where persona_id = p_persona_id and vigente_desde >= p_desde;
  update puestos_base set vigente_hasta = p_desde - 1
   where persona_id = p_persona_id
     and vigente_desde < p_desde
     and (vigente_hasta is null or vigente_hasta >= p_desde);

  if p_puesto = 'almacen' then
    insert into puestos_base (persona_id, vigente_desde, vigente_hasta, creado_por)
    values (p_persona_id, p_desde, null, v_editor_id);
  end if;

  insert into correcciones_auditoria
    (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (null, p_persona_id, 'horarios.puesto_base',
          case when v_antes then 'Almacén' else 'Piso' end,
          case when p_puesto = 'almacen' then 'Almacén' else 'Piso' end,
          v_editor_id,
          'Puesto base desde el ' || to_char(p_desde, 'DD/MM/YYYY') || ': '
          || case when p_puesto = 'almacen' then 'todo su turno en almacén, todos los días que trabaja'
                  else 'en piso' end
          || ', hasta que se cambie. Los días con un plan propio lo conservan. No cambia sus horas, su turno ni su pago.'
          || coalesce(' ' || nullif(btrim(p_motivo), ''), ''));
end;
$$;

comment on function fn_set_puesto_base(uuid, date, text, text) is
  'Cambia el puesto base (piso o almacén, todo el turno) de una persona desde una fecha y hasta que se cambie. '
  'Solo tiendas para el almacén. Las mismas reglas de quién que fn_set_almacen_del_dia. Rastro en '
  'correcciones_auditoria (horarios.puesto_base). No toca turnos, jornadas ni pago. 0588.';

revoke all on function fn_set_puesto_base(uuid, date, text, text) from public, anon;
grant execute on function fn_set_puesto_base(uuid, date, text, text) to authenticated;

-- ── 8 · La lectura de un día para una sede (reescribe la 0579) ──────────────
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

  -- CAMBIO 0588: el plan ya resuelto (el del día, o su puesto base), no la tabla directa.
  return query
    select r.persona_id, r.desde, r.hasta
      from fn_puestos_resueltos(p_fecha, p_fecha) r
     where fn_persona_marca_en_sede(r.persona_id, p_sede_id) is true
     order by r.persona_id, r.desde nulls first;
end;
$$;

comment on function fn_puestos_del_dia(uuid, date) is
  'El plan de piso/almacén de un día para las personas que marcan en esa sede, ya resuelto con su puesto base '
  '(fn_puestos_resueltos). La llaman el terminal de esa sede, admin, Líder DO y la líder de equipo de esa sede. '
  '0579, 0588.';

grant execute on function fn_puestos_del_dia(uuid, date) to authenticated;
revoke execute on function fn_puestos_del_dia(uuid, date) from public, anon;

-- ── 9 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (588, 'el_almacen_puede_ser_el_puesto_de_siempre')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regclass('public.puestos_base') is not null                                              as la_tabla_existe,
  (select relrowsecurity from pg_class where oid = 'public.puestos_base'::regclass)           as tiene_rls,
  (select count(*) = 4 from pg_policy where polrelid = 'public.puestos_base'::regclass)       as cuatro_politicas,
  not has_table_privilege('authenticated', 'public.puestos_base', 'INSERT')                   as nadie_escribe_directo,
  exists (select 1 from information_schema.columns
           where table_name = 'puestos_planificados' and column_name = 'puesto')              as el_dia_dice_piso,
  to_regprocedure('fn_set_puesto_base(uuid,date,text,text)') is not null                     as la_puerta_existe,
  to_regprocedure('fn_puestos_resueltos(date,date)') is not null                             as la_regla_existe,
  position('CAMBIO 0588' in (select prosrc from pg_proc where oid = 'fn_set_almacen_del_dia(uuid,date,boolean,jsonb)'::regprocedure)) > 0 as el_dia_reescrito,
  position('CAMBIO 0588' in (select prosrc from pg_proc where oid = 'fn_puestos_del_dia(uuid,date)'::regprocedure)) > 0                    as la_lectura_reescrita,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 588)            as registro;
