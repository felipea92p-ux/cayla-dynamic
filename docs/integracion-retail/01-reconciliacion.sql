-- ============================================================================
-- HIGIENE DE DNI EN DYNAMIC · SOLO LECTURA, cero riesgo
-- ----------------------------------------------------------------------------
-- Esto era el "Bloque A" de la reconciliación Dynamic↔retail. Los bloques B y
-- C (comparar contra "la base de retail") se retiraron el 2026-09-04: desde
-- el 2026-07-23 retail vive en el MISMO Postgres que Dynamic, como schema
-- `retail.personas` — una vista `security_invoker` sobre esta misma tabla, no
-- una copia. No hay nada que reconciliar por DNI entre "dos bases" porque no
-- hay dos bases. Ver `00-plan.md`.
--
-- Lo que queda es útil por su cuenta, sin relación con retail: mide qué tan
-- confiable es el DNI de `public.personas` como llave — formato, duplicados,
-- gente sin documento. Correr en el SQL Editor de Supabase (el único que hay).
--
-- ⚠️ La salida lleva DNI y nombres reales: no se commitea ni se pega en una
-- issue.
-- ============================================================================

with base as (
  select
    p.id,
    p.nombres || ' ' || p.apellidos            as nombre,
    p.estado,
    nullif(btrim(coalesce(p.documento, '')), '') as doc,
    sb.codigo                                  as sede_base,
    sb.tipo                                    as sede_base_tipo,
    sf.codigo                                  as sede_fisica
  from personas p
  join      sedes sb on sb.id = p.sede_base_id
  left join sedes sf on sf.id = p.sede_fisica_id
),
activas as (select * from base where estado = 'activo')
select * from (
  select 1 as orden, 'Personas' as bloque,
         'activas / inactivas' as chequeo,
         (select count(*) from base where estado = 'activo')::text || ' activas · ' ||
         (select count(*) from base where estado <> 'activo')::text || ' inactivas' as resultado

  union all
  select 2, 'DNI', 'ACTIVAS sin documento',
         coalesce((select string_agg(nombre, ', ' order by nombre) from activas where doc is null),
                  '— ninguna (bien)')

  union all
  select 3, 'DNI', 'inactivas sin documento',
         coalesce((select string_agg(nombre, ', ' order by nombre) from base
                   where estado <> 'activo' and doc is null),
                  '— ninguna')

  union all
  -- El formato que exige fn_set_documento desde la 0125: 8 a 12 alfanuméricos,
  -- sin espacios ni guiones. Lo cargado ANTES de esa migración no pasó por ahí.
  select 4, 'DNI', 'formato raro (espacios, guiones, largo)',
         coalesce((select string_agg(nombre || ' → «' || doc || '»', ', ' order by nombre)
                   from base where doc is not null and doc !~ '^[0-9A-Za-z]{8,12}$'),
                  '— ninguno (bien)')

  union all
  select 5, 'DNI', 'documentos repetidos',
         coalesce((select string_agg(doc || ' (' || n || ')', ', ')
                   from (select doc, count(*) as n from base
                         where doc is not null group by doc having count(*) > 1) d),
                  '— ninguno (bien)')

  union all
  -- Si el índice NO existe, la 0125 se encontró duplicados el día que corrió y
  -- se negó a crearlo. Es la forma barata de saber si esto ya pasó antes.
  select 6, 'DNI', 'índice único idx_personas_documento_unico',
         case when exists (select 1 from pg_indexes
                           where schemaname = 'public'
                             and indexname = 'idx_personas_documento_unico')
              then 'existe (no hubo repetidos)'
              else '⚠ NO existe — la 0125 lo abortó por duplicados' end

  union all
  select 7, 'DNI', 'empiezan con cero',
         coalesce((select string_agg(nombre || ' → ' || doc, ', ' order by nombre)
                   from base where doc like '0%'),
                  '— ninguno')

  union all
  select 8, 'Sedes', 'catálogo de Dynamic',
         (select string_agg(codigo || ' · ' || nombre || ' · ' || tipo ||
                            case when activa then '' else ' (INACTIVA)' end,
                            '  |  ' order by codigo)
          from sedes)

  union all
  select 9, 'Sedes', 'activas por sede base',
         (select string_agg(sede_base || ': ' || n, '  |  ' order by sede_base)
          from (select sede_base, count(*) as n from activas group by sede_base) x)

  union all
  -- Quién vende, según Dynamic: activa en un local tipo 'tienda'. retail.personas
  -- (vista sobre esta misma tabla) va a mostrar exactamente esta lista.
  select 10, 'Retail', 'activas en sede tipo tienda (las que retail ve)',
         coalesce((select string_agg(nombre || ' (' || sede_base || ')', ', ' order by sede_base, nombre)
                   from activas where sede_base_tipo = 'tienda'),
                  '— ninguna')

  union all
  select 11, 'Retail', 'trabajan en una sede distinta a su sede base',
         coalesce((select string_agg(nombre || ': base ' || sede_base || ' → física ' || sede_fisica,
                                     ', ' order by nombre)
                   from activas where sede_fisica is not null and sede_fisica <> sede_base),
                  '— ninguna (sede base alcanza)')
) t order by orden;
