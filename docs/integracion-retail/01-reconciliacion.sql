-- ============================================================================
-- FASE 0 — RECONCILIACIÓN (diagnóstico) · SOLO LECTURA, cero riesgo
-- ----------------------------------------------------------------------------
-- Objetivo: medir el desajuste entre `personas`/`sedes` de Dynamic y de retail
-- ANTES de construir la ventanita. Nada de esto modifica datos: solo SELECT.
--
-- Cómo usarlo:
--   1) Corre la PARTE A completa en la base de DYNAMIC (proyecto cayla-dynamic).
--   2) Corre la PARTE B en la base de RETAIL (proyecto cayla-retail) — primero
--      la consulta B0 para ver las columnas reales y ajustar B1/B2 si hace falta.
--   3) Pégame las salidas de A y B → yo produzco el diff exacto (quién falta
--      dónde, DNIs que no coinciden, gente sin DNI).
-- ============================================================================


-- ############################################################################
-- PARTE A — En la base de DYNAMIC (cayla-dynamic)
-- ############################################################################

-- A1) Personas con su DNI, estado y sede (la lista maestra que Dynamic manda).
select
  p.documento                       as dni,
  p.nombres || ' ' || p.apellidos   as nombre,
  p.estado,
  s.codigo                          as sede
from personas p
left join sedes s on s.id = p.sede_base_id
order by p.documento nulls first;

-- A2) ¿Cuántas personas SIN DNI? (las que van a dar problema en el amarre.)
select count(*) as dynamic_personas_sin_dni
from personas
where documento is null or trim(documento) = '';

-- A3) Sedes de Dynamic.
select codigo, nombre, activa
from sedes
order by codigo;


-- ############################################################################
-- PARTE B — En la base de RETAIL (cayla-retail)
-- ############################################################################

-- B0) PRIMERO: ver las columnas reales de retail.personas, para ajustar B1.
--     (No sé de memoria cómo se llaman: dni? documento? nombre? nombres?)
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'personas'
order by ordinal_position;

-- B1) Personas de retail con su DNI. AJUSTA los nombres de columna según B0.
--     (Cambia `dni`, `nombre`, `activo` por los reales si difieren.)
select
  dni,
  nombre,
  activo
from personas
order by dni nulls first;

-- B2) Sedes de retail. AJUSTA columnas si difieren.
select *
from sedes
order by 1;

-- B3) (opcional) Si retail asocia sus ventas a un vendedor/persona, ver cómo:
--     lista las columnas de `ventas` para saber con qué campo apunta a la persona.
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'ventas'
order by ordinal_position;
