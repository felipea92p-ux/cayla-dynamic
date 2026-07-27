-- ============================================================================
-- ⛔ NO PEGAR ESTE ARCHIVO — quedo DESFASADO de su migracion
-- ----------------------------------------------------------------------------
-- Fuente: supabase/migrations/0019_salarios.sql
--
-- Este script lleva  if not fn_es_admin_o_lider()  donde la migracion tiene\nif fn_es_admin_o_lider() is not true. Pegarlo revierte el guard null-safe que\narreglo la 0078: un null volveria a pasar como autorizado.
--
-- Se conserva por historia. Si de verdad hace falta reconstruir esta parte, la
-- version buena es la migracion, no este archivo.
--
-- El bloque de abajo aborta el script entero si alguien lo pega por error.
-- Para ejecutarlo a proposito (no deberia hacer falta): borrar ese bloque.
-- ============================================================================
do $$
begin
  raise exception E'Este script esta desfasado de supabase/migrations/0019_salarios.sql y no debe pegarse. Lee el encabezado del archivo.';
end $$;

-- ============================================================================
-- Salarios asignados por persona (rango + salario mensual), versionado
-- ----------------------------------------------------------------------------
-- Modelo de planilla de CAYLA (confirmado 2026-07-13 con Felipe):
--     pago = salario_mensual × (horas_trabajadas_del_mes ÷ base_del_mes)
--     base_del_mes = 6.5 × días del mes  (30d→195, 31d→201.5, feb 28→182)
-- Aquí se guarda el PRIMITIVO: rango + salario_mensual, versionado por vigencia
-- (igual que horarios_asignados). La tarifa/hora se DERIVA en la pantalla de
-- planilla, NO se guarda, porque la base varía según los días del mes.
-- Es distinto de `tarifas_hora` (legacy, guardaba tarifa POR HORA — se deja intacta).
--
-- Rangos (salario mensual sugerido, full-time 45 h/sem; el salario es editable):
--   colibri 1320 · cayla 1450 · caylo 1450 · support 1650 · aurora 1890
--   · oraculo 2250 · archicaylo 3000
--
-- Dato SENSIBLE: solo admin/lider_do lo ven o editan (mismo criterio que tarifas_hora).
-- Toda escritura pasa por fn_set_salario (security definer, con chequeo de rol y
-- registro de quién lo asignó).
-- ============================================================================

create table if not exists asignaciones_salario (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  rango text not null check (rango in ('colibri','cayla','caylo','support','aurora','oraculo','archicaylo')),
  salario_mensual_soles numeric(10,2) not null check (salario_mensual_soles > 0),
  vigente_desde date not null,
  vigente_hasta date,
  asignado_por uuid references personas(id),
  nota text,
  created_at timestamptz not null default now(),
  check (vigente_hasta is null or vigente_hasta >= vigente_desde)
);

-- Un solo tramo "vigente" (sin fecha de cierre) por persona.
create unique index if not exists idx_salario_vigente_unico
  on asignaciones_salario(persona_id) where vigente_hasta is null;
create index if not exists idx_salario_persona
  on asignaciones_salario(persona_id, vigente_desde);

alter table asignaciones_salario enable row level security;

drop policy if exists salario_admin_lider on asignaciones_salario;
create policy salario_admin_lider on asignaciones_salario
  for all to authenticated
  using (fn_es_admin_o_lider())
  with check (fn_es_admin_o_lider());

-- ---------------------------------------------------------------------------
-- fn_set_salario: asigna/cambia el salario de una persona, versionado.
-- Cierra el tramo anterior el día previo a la vigencia y abre uno nuevo, sin
-- tocar los meses ya pasados (para no re-pagar meses viejos con salarios nuevos).
-- ---------------------------------------------------------------------------
create or replace function fn_set_salario(
  p_persona_id uuid,
  p_rango text,
  p_salario numeric,
  p_vigente_desde date,
  p_nota text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_yo uuid;
begin
  if not fn_es_admin_o_lider() then
    raise exception 'Solo un administrador o líder puede asignar salarios.';
  end if;
  v_yo := fn_persona_actual_id();

  if p_persona_id is null or not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;
  if p_rango is null or p_rango not in ('colibri','cayla','caylo','support','aurora','oraculo','archicaylo') then
    raise exception 'Rango inválido: %', coalesce(p_rango, '(vacío)');
  end if;
  if p_salario is null or p_salario <= 0 then
    raise exception 'El salario debe ser mayor a 0.';
  end if;
  if p_vigente_desde is null then
    raise exception 'La fecha de vigencia es obligatoria.';
  end if;

  -- serializar cambios concurrentes por persona: dos llamadas simultáneas chocarían
  -- contra el índice único de tramo abierto (unique_violation); con el lock, la
  -- segunda espera y aplica limpio.
  perform pg_advisory_xact_lock(hashtext('salario:' || p_persona_id::text));

  -- versionado: borra tramos que arrancan en/después de la fecha y recorta CUALQUIER
  -- tramo previo (abierto o cerrado) que se extienda hasta la nueva vigencia — así un
  -- cambio retro-fechado dentro de un tramo ya cerrado no deja tramos solapados.
  delete from asignaciones_salario
    where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;
  update asignaciones_salario set vigente_hasta = p_vigente_desde - 1
    where persona_id = p_persona_id
      and vigente_desde < p_vigente_desde
      and (vigente_hasta is null or vigente_hasta >= p_vigente_desde);

  insert into asignaciones_salario
    (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta, asignado_por, nota)
  values
    (p_persona_id, p_rango, p_salario, p_vigente_desde, null, v_yo, nullif(trim(p_nota), ''));
end;
$$;

grant execute on function fn_set_salario(uuid, text, numeric, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- fn_salarios_vigentes: salario vigente (tramo abierto) de cada persona.
-- Solo devuelve filas si quien llama es admin/lider_do (dato sensible).
-- ---------------------------------------------------------------------------
create or replace function fn_salarios_vigentes()
returns table (persona_id uuid, rango text, salario_mensual_soles numeric, vigente_desde date)
language sql stable security definer set search_path = public
as $$
  select a.persona_id, a.rango, a.salario_mensual_soles, a.vigente_desde
  from asignaciones_salario a
  where a.vigente_hasta is null and fn_es_admin_o_lider();
$$;

grant execute on function fn_salarios_vigentes() to authenticated;

-- ---------------------------------------------------------------------------
-- fn_historial_salario: todos los tramos de una persona (más reciente primero).
-- ---------------------------------------------------------------------------
create or replace function fn_historial_salario(p_persona_id uuid)
returns table (
  rango text,
  salario_mensual_soles numeric,
  vigente_desde date,
  vigente_hasta date,
  asignado_por text,
  nota text,
  created_at timestamptz
)
language sql stable security definer set search_path = public
as $$
  select a.rango, a.salario_mensual_soles, a.vigente_desde, a.vigente_hasta,
         (ap.nombres || ' ' || ap.apellidos), a.nota, a.created_at
  from asignaciones_salario a
  left join personas ap on ap.id = a.asignado_por
  where a.persona_id = p_persona_id and fn_es_admin_o_lider()
  order by a.vigente_desde desc;
$$;

grant execute on function fn_historial_salario(uuid) to authenticated;

notify pgrst, 'reload schema';
