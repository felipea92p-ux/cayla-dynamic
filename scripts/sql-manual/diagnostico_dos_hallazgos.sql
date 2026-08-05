-- ############################################################################
-- ####  SOLO LEE. No cambia absolutamente nada. Se puede correr las veces  ####
-- ####  que haga falta.                                                    ####
-- ############################################################################
--
-- diagnostico_dos_hallazgos.sql
--
-- El comparador del 2026-08-05 encontró dos cosas en producción:
--
--   1. Falta el candado `periodos_etiqueta_unica`, que impide que dos periodos
--      de planilla terminen en el mismo mes.
--   2. Existe una tabla entera, `desembolsos_beneficios`, que NO está en el
--      repositorio: cero coincidencias en el código, en las ramas y en toda la
--      historia de commits.
--
-- Antes de tocar nada hay que saber por qué. Esto lo averigua.
-- ############################################################################


-- ── 1 · ¿POR QUÉ FALTA EL CANDADO? ─────────────────────────────────────────
-- El candado es un índice único sobre (año, mes) de `fecha_fin`. La migración
-- 0026 lo crea con `if not exists`, así que si al aplicarla YA había dos
-- periodos terminando en el mismo mes, la creación falla y el resto sigue.
-- Esa es la hipótesis más probable: no es que se saltara la migración, es que
-- los datos no lo permitían.
select '1 · PERIODOS POR MES' as bloque;

select extract(year from fecha_fin)::int  as anio,
       extract(month from fecha_fin)::int as mes,
       count(*)                           as cuantos_periodos,
       string_agg(fecha_ini || ' a ' || fecha_fin || ' (' || estado || ')', '  |  '
                  order by fecha_ini)      as detalle
from periodos_planilla
group by 1, 2
having count(*) > 1
order by 1, 2;

-- Si el bloque de arriba sale VACÍO, no hay nada que impida crear el candado
-- ahora mismo. Si sale con filas, esas filas son el problema real y hay que
-- resolverlas antes.

select '1b · TODOS LOS PERIODOS, para tener el cuadro completo' as bloque;
select fecha_ini, fecha_fin, estado, pagado_at::date as pagado
from periodos_planilla order by fecha_ini;


-- ── 2 · ¿QUÉ ES `desembolsos_beneficios`? ──────────────────────────────────
select '2 · LA TABLA DESCONOCIDA — ¿existe y qué guarda?' as bloque;

select column_name as columna, data_type as tipo, is_nullable as acepta_nulo,
       coalesce(column_default, '—') as valor_por_defecto
from information_schema.columns
where table_schema = 'public' and table_name = 'desembolsos_beneficios'
order by ordinal_position;

select '2b · SUS REGLAS (lo que acepta y lo que rechaza)' as bloque;
select con.conname as candado, pg_get_constraintdef(con.oid) as regla
from pg_constraint con
join pg_class c on c.oid = con.conrelid
where c.relname = 'desembolsos_beneficios'
order by 1;

select '2c · ¿TIENE DATOS?' as bloque;
-- El conteo va por SQL DINÁMICO (`query_to_xml` recibe la consulta como texto)
-- y no como una consulta normal. Es la única forma de que este archivo no
-- reviente en una base donde la tabla no exista —la local, por ejemplo—:
-- Postgres valida las tablas al LEER la consulta, antes de mirar ningún `case`,
-- así que un `select ... from tabla_que_no_existe` falla aunque el `case` nunca
-- llegue a esa rama.
select case
         when to_regclass('public.desembolsos_beneficios') is null
           then 'la tabla no existe en esta base'
         else 'filas: ' || (xpath('/row/c/text()',
                query_to_xml('select count(*) as c from public.desembolsos_beneficios',
                             false, true, '')))[1]::text
       end as cuantas_filas;

select '2d · ¿ALGUIEN LA USA? funciones y vistas que la nombran' as bloque;
select p.proname as objeto, 'función' as tipo
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosrc ilike '%desembolsos_beneficios%'
union all
select c.relname, 'vista'
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('v','m')
   and pg_get_viewdef(c.oid) ilike '%desembolsos_beneficios%'
order by 1;

select '2e · ¿ESTÁ PROTEGIDA? RLS y permisos' as bloque;
select relrowsecurity as tiene_rls
  from pg_class where relname = 'desembolsos_beneficios';
select grantee as quien, string_agg(privilege_type, ', ' order by privilege_type) as puede
  from information_schema.role_table_grants
 where table_name = 'desembolsos_beneficios' and grantee in ('anon','authenticated')
 group by 1;
