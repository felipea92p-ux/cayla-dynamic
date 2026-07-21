-- ============================================================================
-- 0057_tardanzas_resumen.sql — Semáforo de TARDANZAS (umbral b del RIT art. 7)
-- ============================================================================
-- PROMETE: por persona, cuántas tardanzas lleva en el MES CALENDARIO en curso, y
--   si cruzó el umbral b del art. 7 del RIT (3 o más → corresponde amonestación).
--   Solo lectura. NO sanciona; alimenta el semáforo. Devuelve solo a quienes van
--   en 2+ (los que importan): 2 = aviso, 3+ = amonestación.
-- ASUME: jornadas.minutos_tarde ya viene SIN tolerancia (desde el minuto 1, igual
--   que exige el RIT art. 6); una tardanza levantada por fuerza mayor (mig 0053,
--   tabla tardanzas_justificadas) NO cuenta.
--
-- Los umbrales c) suspensión y d) despido dependen de si hay una amonestación /
-- suspensión VIGENTE en el legajo (expediente_disciplinario) — esa lógica va en
-- 0058 (generación de borradores), no aquí. Este archivo es el contador del mes.
--
-- Excluye, igual que fn_faltas: inactivos, no-planilla y sueldo_fijo (a Catherine
-- y a quien cobra fijo no se le mide asistencia).

create or replace function fn_tardanzas_resumen()
returns table (persona_id uuid, nombre text, sede text, tardanzas_mes int, umbral text)
language sql stable security definer set search_path = public
as $$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  conteo as (
    -- count(distinct fecha): una tardanza es un DÍA, no una fila. Robusto ante
    -- cualquier jornada duplicada por día.
    select m.id as pid, count(distinct j.fecha) as n
    from medibles m
    join jornadas j on j.persona_id = m.id
      and j.fecha >= date_trunc('month', current_date)::date
      and j.fecha <= current_date
      and j.minutos_tarde is not null and j.minutos_tarde > 0
      and not exists (
        select 1 from tardanzas_justificadas tj
        where tj.persona_id = m.id and tj.fecha = j.fecha)
    group by m.id
  )
  select m.id, m.nombre, m.sede, c.n::int,
    case when c.n >= 3 then 'amonestacion' else 'aviso' end as umbral
  from medibles m join conteo c on c.pid = m.id
  where c.n >= 2
  order by c.n desc, m.nombre;
$$;

grant execute on function fn_tardanzas_resumen() to authenticated;

-- ⚠️ NO validar con `select * from fn_tardanzas_resumen();` en el SQL Editor:
-- la función filtra por TU rol vía auth.uid(), que en el editor es NULL → devuelve
-- VACÍO aunque haya tardanzas. La validación va con el diagnóstico sin filtro de
-- rol de docs/disciplina-tardanzas-faltas/07-validacion-queries.sql.
