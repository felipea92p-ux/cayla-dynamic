-- ============================================================================
-- 0072 — Descanso sustitutorio: el acuerdo se registra ANTES, y una pantalla que lo opere
-- ----------------------------------------------------------------------------
-- NUMERACIÓN: se escribió y se APLICÓ a producción como 0071, pero la otra
-- máquina ya había usado ese número (0071_elegir_firmante). Se renumeró a 0072
-- al integrar las dos ramas. Su contenido YA ESTÁ VIVO en la base: no hay que
-- volver a aplicarla.
-- ----------------------------------------------------------------------------
-- CORRIGE UN ERROR DE 0069. Puse una validación que exige que el feriado YA
-- tenga horas marcadas para poder registrar el acuerdo. Suena prudente pero es
-- al revés de como funciona el negocio: el acuerdo con la persona se cierra
-- ANTES del feriado ("trabajas el 28, te doy libre el 30"). Con esa regla no se
-- podía registrar el caso de Taller LIM hasta la noche del miércoles 29.
--
-- LA REGLA CORREGIDA, por estado:
--   · PENDIENTE    → es un acuerdo sobre el futuro. NO exige horas marcadas.
--   · OTORGADO     → es la confirmación de que ocurrió. SÍ exige horas marcadas
--                    en el feriado (y acta, que ya estaba). Es el estado que
--                    mueve dinero, así que es el que se prueba contra la realidad.
--   · NO_OTORGADO  → no exige nada; solo deja el rastro de que no se dio.
--
-- Agrega además lo que la pantalla necesita: leer (fn_feriados_laborados) y
-- borrar (fn_quitar_descanso_sustitutorio) un registro.
--
-- Reversible: restaurar fn_otorgar_descanso_sustitutorio desde 0069 y soltar las
-- dos funciones nuevas.
-- ============================================================================

create or replace function fn_otorgar_descanso_sustitutorio(
  p_persona_id uuid,
  p_fecha_feriado date,
  p_fecha_descanso date,
  p_estado text default 'PENDIENTE',
  p_acta_ref text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un descanso sustitutorio.';
  end if;

  if p_estado not in ('PENDIENTE', 'OTORGADO', 'NO_OTORGADO') then
    raise exception 'Estado inválido: %. Debe ser PENDIENTE, OTORGADO o NO_OTORGADO.', p_estado;
  end if;

  if not exists (select 1 from feriados where fecha = p_fecha_feriado) then
    raise exception 'El % no está registrado como feriado.', to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  -- ⇩ CAMBIO 0071: la exigencia de horas marcadas aplica SOLO a OTORGADO.
  -- PENDIENTE es el acuerdo previo; exigirle horas haría imposible registrarlo
  -- antes del feriado, que es justo cuando se acuerda.
  if p_estado = 'OTORGADO' and not exists (
    select 1 from jornadas j
    where j.persona_id = p_persona_id and j.fecha = p_fecha_feriado
      and coalesce(j.horas_trabajadas, 0) > 0
  ) then
    raise exception 'No se puede dar por OTORGADO: esa persona no tiene horas marcadas el %. Déjalo en PENDIENTE hasta que el feriado se haya trabajado.',
      to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  insert into feriados_descanso_sustitutorio (
    persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado, acta_ref, otorgado_por
  )
  values (
    p_persona_id, p_fecha_feriado, p_fecha_descanso, p_estado, nullif(trim(p_acta_ref), ''), fn_persona_actual_id()
  )
  on conflict (persona_id, fecha_feriado) do update set
    fecha_descanso_sustitutorio = excluded.fecha_descanso_sustitutorio,
    estado = excluded.estado,
    acta_ref = excluded.acta_ref,
    otorgado_por = excluded.otorgado_por,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function fn_otorgar_descanso_sustitutorio(uuid, date, date, text, text) to authenticated;
revoke execute on function fn_otorgar_descanso_sustitutorio(uuid, date, date, text, text) from public, anon;

-- ── Quitar un registro ───────────────────────────────────────────────────────
create or replace function fn_quitar_descanso_sustitutorio(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar un descanso sustitutorio.';
  end if;
  delete from feriados_descanso_sustitutorio where id = p_id;
end;
$$;

grant execute on function fn_quitar_descanso_sustitutorio(uuid) to authenticated;
revoke execute on function fn_quitar_descanso_sustitutorio(uuid) from public, anon;

-- ── Lo que la pantalla lee ───────────────────────────────────────────────────
-- Por cada feriado del rango y cada persona que LO TRABAJÓ, su estado de
-- compensación. Es la lista de "a quién le debo decidir": si `estado` viene
-- null, ese feriado se está pagando con sobretasa.
-- `sobretasa` es lo que se paga de más HOY por ese día (horas × tarifa), para
-- que la decisión se tome viendo el monto, no a ciegas.
create or replace function fn_feriados_laborados(p_desde date, p_hasta date)
returns table (
  persona_id uuid, nombre text, sede text,
  fecha_feriado date, feriado_nombre text, horas numeric, sobretasa numeric,
  dcs_id uuid, fecha_descanso date, estado text, acta_ref text
)
language sql stable security definer set search_path = public
as $$
  with base as (
    select greatest(date_trunc('month', p_desde)::date, p_desde) as ini, p_hasta as fin
  ),
  -- La tarifa por hora sale de la misma base que usa la planilla: 6.5 h por día
  -- del periodo. Se calcula sobre el mes del feriado para que el número mostrado
  -- coincida con el que verá en Planilla.
  f as (
    select fe.fecha, fe.nombre,
           (6.5 * (extract(day from (date_trunc('month', fe.fecha) + interval '1 month - 1 day'))::numeric)) as base_horas
    from feriados fe, base b
    where fe.fecha between b.ini and b.fin
  )
  select
    pe.id, pe.nombres || ' ' || pe.apellidos, s.codigo,
    f.fecha, f.nombre,
    round(j.horas_trabajadas, 2),
    round(j.horas_trabajadas * a.salario_mensual_soles / nullif(f.base_horas, 0), 2),
    d.id, d.fecha_descanso_sustitutorio, d.estado, d.acta_ref
  from f
  join jornadas j on j.fecha = f.fecha and coalesce(j.horas_trabajadas, 0) > 0
  join personas pe on pe.id = j.persona_id and pe.en_planilla = true and pe.sueldo_fijo = false
  join sedes s on s.id = pe.sede_base_id
  left join asignaciones_salario a
    on a.persona_id = pe.id and a.vigente_desde <= f.fecha
   and (a.vigente_hasta is null or a.vigente_hasta >= f.fecha)
  left join feriados_descanso_sustitutorio d
    on d.persona_id = pe.id and d.fecha_feriado = f.fecha
  where fn_es_admin_o_lider()
  order by f.fecha desc, s.codigo, pe.nombres;
$$;

grant execute on function fn_feriados_laborados(date, date) to authenticated;

notify pgrst, 'reload schema';
