-- ============================================================================
-- 0419 · los feriados de la pantalla usan el periodo de planilla, no el mes
-- calendario
-- ============================================================================
-- QUÉ PROMETE
--
--   Que la sobretasa que muestra `fn_feriados_laborados` (la pantalla de
--   Feriados) se calcule con la MISMA base que usa `fn_feriado_devengado_nucleo`
--   (0397, lo que de verdad paga la planilla): el periodo 29→28 que contiene
--   el feriado, no el mes calendario.
--
--   Hoy `f.base_horas` sale de `extract(day from ... date_trunc('month', ...))`
--   — los días del MES CALENDARIO del feriado. La planilla real, en cambio,
--   busca el periodo en `periodos_planilla` y si no lo encuentra reconstruye
--   el bloque 29→28 a mano (`fer_bloque`/`can` en `fn_feriado_devengado_nucleo`).
--   Las dos cuentan distinto casi siempre, porque un periodo 29→28 casi nunca
--   tiene el mismo largo que el mes calendario que lo contiene.
--
--   Medido en Postgres local (BEGIN…ROLLBACK) antes de escribir esta migración:
--   persona con sueldo S/3.000, feriado del 28/07/2026 (Fiestas Patrias),
--   8 h trabajadas. Pantalla (mes calendario, 31 días): S/119,11. Planilla real
--   (periodo 29/06→28/07, 30 días): S/123,08. Diferencia: S/3,97 — 3,3 % de esa
--   sobretasa, dentro del rango 3,33–10,7 % que mide
--   `docs/hallazgos-abiertos.md` («Confirmado y pendiente · mueve plata en el
--   pago mensual», hallazgo #5).
--
-- QUÉ ASUME
--
--   · `fn_feriados_laborados`, tal como quedó en la 0238 (confirmado con
--     `donde-vive.sh` antes de escribir esta migración: es la vigente). El
--     cuerpo que sigue es la 0238 completa, con el único diff marcado
--     «CAMBIO 0419» dentro del CTE `f`.
--   · El bloque 29→28 se copia LITERAL del `can` de `fn_feriado_devengado_nucleo`
--     (0397) — no se inventa un criterio nuevo para la misma pregunta que la
--     función hermana ya resuelve. Cuando `periodos_planilla` tiene una fila
--     que cubre el feriado, se usa esa (es el dato real); si no la tiene
--     —una fecha futura, por ejemplo, para la que aún no se abrió periodo—
--     se cae al mismo cálculo de respaldo que ya usa la planilla real.
--   · `fn_feriados_laborados` devuelve `TABLE`, así que no se le puede hacer
--     `create or replace` con las mismas columnas — sí se puede, de hecho,
--     porque esta migración NO agrega ni quita columnas (a diferencia de la
--     0238, que sí lo hizo y por eso necesitó `drop` + `create`). Aun así se
--     mantiene el mismo `drop function if exists` + `create function` de la
--     0238 para no depender de que el motor decida que la firma no cambió.
--
-- QUÉ NO HACE
--
--   · No cambia ni un céntimo de lo que la planilla real paga —
--     `fn_feriado_devengado_nucleo` no se toca—. Esto es exclusivamente la
--     pantalla que el admin mira para revisar feriados trabajados.
--   · No cambia el criterio de qué feriados entran al listado (`p_desde`/
--     `p_hasta`, el CTE `base`) ni a quién se le muestra.
--   · Cuando el mes calendario del feriado coincide en largo con el periodo
--     que lo contiene, el número no se mueve — verificado con el feriado de
--     Año Nuevo (enero, mes y periodo de 31 días en el caso probado).
--
-- CÓMO SE REVIERTE
--
--   Repegar el `create function` de la 0238 (líneas 244-289 de esa migración)
--   tal cual — ningún dato se escribió, es una función `stable`.
--
-- AUDITADO CONTRA POSTGRES LOCAL (BEGIN … ROLLBACK, nunca `db reset`): se
-- reprodujo el caso de arriba con datos sintéticos (persona, horario, salario,
-- jornada y periodo de planilla insertados solo dentro de la transacción) en
-- tres escenarios — con fila en `periodos_planilla`, sin ella (respaldo
-- canónico) y un feriado de control donde mes y periodo coinciden — y los
-- tres dieron el resultado esperado antes de escribir esta línea.
-- ============================================================================

drop function if exists fn_feriados_laborados(date, date);

create function fn_feriados_laborados(p_desde date, p_hasta date)
returns table (
  persona_id uuid, nombre text, sede text,
  fecha_feriado date, feriado_nombre text, horas numeric, sobretasa numeric,
  dcs_id uuid, fecha_descanso date, estado text, acta_ref text,
  no_compensa_porque text,
  motivo_fuera_de_plazo text
)
language sql stable security definer set search_path = public
as $$
  with base as (
    select greatest(date_trunc('month', p_desde)::date, p_desde) as ini, p_hasta as fin
  ),
  -- ⇩⇩⇩ CAMBIO 0419 ⇩⇩⇩ la base ya no es el mes calendario del feriado: es el
  -- periodo de planilla (29→28) que lo contiene — el mismo bloque que ya
  -- calcula `fn_feriado_devengado_nucleo` (0397) para lo que de verdad paga.
  -- Copiado de ahí, función hermana respondiendo la misma pregunta.
  f as (
    select fe.fecha, fe.nombre,
           6.5 * coalesce(
             (select (pp.fecha_fin - pp.fecha_ini) + 1
                from periodos_planilla pp
               where fe.fecha between pp.fecha_ini and pp.fecha_fin
               limit 1),
             (can.fin - can.ini) + 1
           ) as base_horas
    from feriados fe, base b
    cross join lateral (
      select (q.m + make_interval(days =>
                least(29, extract(day from (date_trunc('month', q.m) + interval '1 month - 1 day'))::int) - 1))::date as ini,
             (date_trunc('month', q.m + interval '1 month') + interval '27 days')::date as fin
      from (select case when extract(day from fe.fecha) >= 29
                        then date_trunc('month', fe.fecha::timestamp)
                        else date_trunc('month', fe.fecha::timestamp) - interval '1 month' end as m) q
    ) can
    where fe.fecha between b.ini and b.fin
  )
  -- ⇧⇧⇧ CAMBIO 0419 ⇧⇧⇧
  select
    pe.id, pe.nombres || ' ' || pe.apellidos, s.codigo,
    f.fecha, f.nombre,
    round(j.horas_trabajadas, 2),
    round(j.horas_trabajadas * a.salario_mensual_soles / nullif(f.base_horas, 0), 2),
    d.id, d.fecha_descanso_sustitutorio, d.estado, d.acta_ref,
    fn_dcs_por_que_no_compensa(pe.id, f.fecha, d.fecha_descanso_sustitutorio),
    d.motivo_fuera_de_plazo
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
revoke execute on function fn_feriados_laborados(date, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (419, 'los_feriados_de_la_pantalla_usan_el_periodo_no_el_mes_calendario')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
