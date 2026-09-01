-- ============================================================================
-- FASE 0 — RECONCILIACIÓN (diagnóstico) · SOLO LECTURA, cero riesgo
-- ----------------------------------------------------------------------------
-- Objetivo: medir el desajuste entre `personas`/`sedes` de Dynamic y de retail
-- ANTES de construir la ventanita. Nada de esto modifica datos: solo SELECT.
--
-- Son TRES bloques, y cada bloque es UNA sola consulta a propósito: el SQL
-- Editor de Supabase muestra el resultado de la ÚLTIMA sentencia, así que un
-- bloque con tres SELECT enseña uno y esconde dos. Se pega un bloque, se lee,
-- se pasa al siguiente.
--
--   BLOQUE A  → en la base de DYNAMIC   · qué tan limpio está el DNI de este lado
--   BLOQUE B  → en la base de RETAIL    · la lista de retail, ya lista para pegar
--   BLOQUE C  → en la base de DYNAMIC   · el diff exacto entre las dos listas
--
-- El diff lo hace SQL, no el ojo. Por eso el bloque B no devuelve una tabla
-- para mirar: devuelve el texto que se pega dentro del bloque C.
--
-- ⚠️ La salida lleva DNI y nombres reales. No se commitea, no se pega en una
-- issue: es exactamente lo que CLAUDE.md manda dejar fuera de git.
-- ============================================================================


-- ############################################################################
-- BLOQUE A — En la base de DYNAMIC (cayla-dynamic). Una sola consulta.
-- ----------------------------------------------------------------------------
-- Responde: ¿el DNI de Dynamic aguanta ser la llave del amarre?
-- El amarre de todo el puente es el documento. Si acá está sucio, la ventanita
-- no reconoce a la persona y retail la duplica — es la Fase 1 del plan, y es
-- la tarea de verdad.
-- ############################################################################

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
  -- Sin DNI no hay amarre posible: son las primeras de la lista de la Fase 1.
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
  -- Un DNI repetido rompe el amarre en los dos sentidos: retail no sabe a quién
  -- atribuir la venta, y Dynamic no sabe a quién le llegó.
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
  -- El cero adelante es la trampa clásica: retail suele guardar el DNI como
  -- número y 08817189 le llega como 8817189. Si acá hay de estos, el amarre
  -- tiene que normalizar, no comparar texto contra texto.
  select 7, 'DNI', 'empiezan con cero (se pierde si retail lo guarda como número)',
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
  -- Quién vende, según Dynamic: activa en un local tipo 'tienda'. Es la lista
  -- que retail espera encontrar; el taller y Central no atienden clientas.
  select 10, 'Retail', 'activas en sede tipo tienda (las que retail espera)',
         coalesce((select string_agg(nombre || ' (' || sede_base || ')', ', ' order by sede_base, nombre)
                   from activas where sede_base_tipo = 'tienda'),
                  '— ninguna')

  union all
  -- sede_fisica_id hoy solo decide la movilidad (0166). Si alguien de esta
  -- lista vende en una tienda distinta a su sede base, hay que decidir con qué
  -- sede la ve retail ANTES de escribir la vista — no después.
  select 11, 'Retail', 'trabajan en una sede distinta a su sede base',
         coalesce((select string_agg(nombre || ': base ' || sede_base || ' → física ' || sede_fisica,
                                     ', ' order by nombre)
                   from activas where sede_fisica is not null and sede_fisica <> sede_base),
                  '— ninguna (sede base alcanza)')
) t order by orden;


-- ############################################################################
-- BLOQUE B — En la base de RETAIL (cayla-retail).
-- ----------------------------------------------------------------------------
-- Dos pasos: B0 descubre cómo se llaman las columnas (no lo sabemos), B1
-- devuelve UNA celda de texto con la lista entera, ya con la forma que el
-- bloque C espera. Se copia esa celda y se pega dentro del bloque C.
-- ############################################################################

-- B0) PRIMERO: ver qué tablas y columnas existen de verdad en retail.
--     Corre esto solo, mira la salida, y recién ahí ajusta B1.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('personas', 'vendedores', 'vendedoras', 'usuarios', 'empleados', 'sedes', 'tiendas', 'ventas')
order by table_name, ordinal_position;

-- B1) La lista de retail, empaquetada para pegar. AJUSTA los tres nombres de
--     columna (dni / nombre / activo) y el nombre de la tabla según B0.
--     Devuelve una sola celda; cópiala entera.
--
--     Si en retail el DNI es numérico, `::text` ya lo convierte — y el bloque C
--     se encarga del cero que se perdió por el camino.
select coalesce(string_agg(
         '(' || quote_literal(coalesce(dni::text, ''))    || ',' ||
                quote_literal(coalesce(nombre::text, '')) || ',' ||
                coalesce(activo::text, 'null') || ')',
         E',\n' order by nombre), '')
from personas;   -- ← ajusta el nombre de la tabla si B0 dice otro


-- ############################################################################
-- BLOQUE C — En la base de DYNAMIC otra vez. El diff, hecho por SQL.
-- ----------------------------------------------------------------------------
-- Pega la celda del bloque B1 donde dice PEGAR ACÁ (reemplazando la línea de
-- ejemplo) y corre todo el bloque de una vez.
--
-- El amarre NO compara texto contra texto: normaliza (mayúsculas, sin espacios
-- ni guiones) y, para los DNI de solo dígitos, rellena con ceros a la izquierda
-- hasta 8. Así 8817189 y 08817189 se reconocen como la misma persona en vez de
-- aparecer como dos filas huérfanas — que es exactamente el falso positivo que
-- convertiría la Fase 1 en una cacería inventada.
-- ############################################################################

with retail_crudo (dni, nombre, activo) as (
  values
    -- ▼▼▼ PEGAR ACÁ la celda del bloque B1 (borra esta línea de ejemplo) ▼▼▼
    ('00000000', 'EJEMPLO — borrar esta fila', true)
    -- ▲▲▲ PEGAR ACÁ ▲▲▲
),
norm as (
  select 'retail' as lado, nombre, activo::boolean as activo,
         dni as doc_original,
         upper(regexp_replace(coalesce(dni, ''), '[^0-9A-Za-z]', '', 'g')) as doc_limpio
  from retail_crudo
  union all
  select 'dynamic', p.nombres || ' ' || p.apellidos, (p.estado = 'activo'),
         p.documento,
         upper(regexp_replace(coalesce(p.documento, ''), '[^0-9A-Za-z]', '', 'g'))
  from personas p
),
llave as (
  select *,
         case when doc_limpio ~ '^[0-9]+$' and length(doc_limpio) < 8
              then lpad(doc_limpio, 8, '0')
              else doc_limpio end as k
  from norm
),
d as (select * from llave where lado = 'dynamic'),
r as (select * from llave where lado = 'retail')
select * from (
  -- Coinciden por DNI: el caso bueno. Se listan igual los que tienen el nombre
  -- muy distinto, porque un DNI compartido por dos personas distintas es peor
  -- que un DNI que falta.
  select 1 as orden,
         case when lower(d.nombre) = lower(r.nombre) then 'coincide'
              else '⚠ mismo DNI, nombre distinto' end as caso,
         coalesce(d.doc_original, d.k) as dni,
         d.nombre  as en_dynamic,
         r.nombre  as en_retail,
         case when d.activo = r.activo then ''
              else '⚠ estado distinto: dynamic ' ||
                   case when d.activo then 'activa' else 'inactiva' end ||
                   ' / retail ' ||
                   case when r.activo then 'activo' else 'inactivo' end end as nota
  from d join r on r.k = d.k and d.k <> ''

  union all
  -- Está en Dynamic y retail no la conoce. Si está activa y trabaja en tienda,
  -- es alguien a quien retail no le puede atribuir una venta.
  select 2, 'solo en Dynamic', coalesce(nullif(btrim(d.doc_original), ''), '(sin DNI)'),
         d.nombre, '—',
         case when d.activo then 'activa' else 'inactiva' end
  from d where d.k = '' or not exists (select 1 from r where r.k = d.k)

  union all
  -- Está en retail y Dynamic no la conoce: o falta darla de alta acá, o su DNI
  -- está escrito distinto en uno de los dos lados.
  select 3, 'solo en retail', coalesce(nullif(btrim(r.doc_original), ''), '(sin DNI)'),
         '—', r.nombre,
         case when r.activo then 'activo' else 'inactivo' end
  from r where r.k = '' or not exists (select 1 from d where d.k = r.k)
) t
order by orden, dni;
