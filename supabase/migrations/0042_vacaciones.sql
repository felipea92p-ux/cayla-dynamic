-- ============================================================================
-- 0042_vacaciones.sql — Registro de periodos de vacaciones por persona
-- ============================================================================
-- POR QUÉ EXISTE: hasta ahora las vacaciones solo vivían como PROVISIÓN contable
-- (un % del sueldo en planilla), nunca como DÍAS concretos. Sin esta tabla:
--   1) quien se va de vacaciones no marca ningún día, así que el sistema la
--      contaría como FALTA — y con la normativa peruana las faltas escalan a
--      causal de despido (art. 25-h D.S. 003-97-TR). Sería el peor falso positivo.
--   2) la planilla paga por horas marcadas, así que le pagaría de MENOS, cuando
--      las vacaciones son descanso REMUNERADO.
--
-- ALCANCE DE ESTA MIGRACIÓN: solo REGISTRAR los periodos. El pago de esos días y
-- la exclusión de faltas se conectan después, ya con esta tabla como fuente de
-- verdad. Régimen: Pequeña Empresa (MYPE) ⇒ 15 días por año de servicios.

create extension if not exists btree_gist;

create table if not exists vacaciones (
  id            uuid primary key default gen_random_uuid(),
  persona_id    uuid not null references personas(id),
  fecha_inicio  date not null,
  fecha_fin     date not null,
  observacion   text,
  creado_por    uuid not null references personas(id),
  creado_at     timestamptz not null default now(),
  constraint vacaciones_rango_valido check (fecha_fin >= fecha_inicio)
);

create index if not exists idx_vacaciones_persona on vacaciones (persona_id, fecha_inicio);

-- Estado imposible, hecho imposible por el esquema: una misma persona no puede
-- tener dos periodos de vacaciones solapados. Un constraint de base vale más que
-- diez validaciones en el frontend (que se pueden saltar o quedar desfasadas).
alter table vacaciones drop constraint if exists vacaciones_sin_solape;
alter table vacaciones add constraint vacaciones_sin_solape
  exclude using gist (
    persona_id with =,
    daterange(fecha_inicio, fecha_fin, '[]') with &&
  );

-- ── RLS: mismo criterio que correcciones_auditoria ───────────────────────────
-- admin/líder ven todo · la encargada ve su sede · cada persona ve lo suyo.
-- Las ESCRITURAS no tienen policy a propósito: solo entran por las funciones
-- security definer de abajo, que son las que aplican el candado de planilla.
alter table vacaciones enable row level security;

drop policy if exists vacaciones_select_admin_lider on vacaciones;
create policy vacaciones_select_admin_lider on vacaciones
  for select to authenticated
  using (fn_es_admin_o_lider());

drop policy if exists vacaciones_select_supervisor on vacaciones;
create policy vacaciones_select_supervisor on vacaciones
  for select to authenticated
  using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona())
  );

drop policy if exists vacaciones_select_propia on vacaciones;
create policy vacaciones_select_propia on vacaciones
  for select to authenticated
  using (persona_id = fn_persona_actual_id());

-- ── Registrar un periodo ─────────────────────────────────────────────────────
-- Promete: deja registrado el rango o lanza excepción con motivo entendible.
-- Asume: quien llama es admin/líder y el rango no toca una planilla ya pagada.
create or replace function fn_set_vacaciones(
  p_persona_id  uuid,
  p_fecha_inicio date,
  p_fecha_fin   date,
  p_observacion text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_editor uuid;
  v_id uuid;
begin
  if not fn_es_admin_o_lider() then
    raise exception 'Solo un administrador o líder puede registrar vacaciones.';
  end if;
  v_editor := fn_persona_actual_id();

  if p_fecha_fin < p_fecha_inicio then
    raise exception 'La fecha de fin no puede ser anterior a la de inicio.';
  end if;

  -- Candado: registrar vacaciones dentro de un periodo PAGADO cambiaría el pago
  -- de una planilla ya cerrada (esos días pasan a ser remunerados sin marcar).
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and daterange(fecha_ini, fecha_fin, '[]') && daterange(p_fecha_inicio, p_fecha_fin, '[]')
  ) then
    raise exception 'Ese rango toca un periodo de planilla ya PAGADO. Reabre el periodo primero.';
  end if;

  insert into vacaciones (persona_id, fecha_inicio, fecha_fin, observacion, creado_por)
  values (p_persona_id, p_fecha_inicio, p_fecha_fin, nullif(trim(p_observacion), ''), v_editor)
  returning id into v_id;

  return v_id;
exception
  when exclusion_violation then
    raise exception 'Esa persona ya tiene vacaciones registradas que se cruzan con esas fechas.';
end;
$$;

-- ── Quitar un periodo ────────────────────────────────────────────────────────
create or replace function fn_quitar_vacaciones(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_vac vacaciones%rowtype;
begin
  if not fn_es_admin_o_lider() then
    raise exception 'Solo un administrador o líder puede quitar vacaciones.';
  end if;

  select * into v_vac from vacaciones where id = p_id;
  if not found then
    raise exception 'Ese periodo de vacaciones ya no existe.';
  end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and daterange(fecha_ini, fecha_fin, '[]') && daterange(v_vac.fecha_inicio, v_vac.fecha_fin, '[]')
  ) then
    raise exception 'Ese rango toca un periodo de planilla ya PAGADO. Reabre el periodo primero.';
  end if;

  delete from vacaciones where id = p_id;
end;
$$;

grant execute on function fn_set_vacaciones(uuid, date, date, text) to authenticated;
grant execute on function fn_quitar_vacaciones(uuid) to authenticated;
