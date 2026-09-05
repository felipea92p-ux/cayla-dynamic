-- ############################################################################
-- ####  ¿LLEGÓ BIEN LA 0305?  — SOLO LEE, NO ESCRIBE NADA                 ####
-- ############################################################################
--
-- Para qué. `que_falta_pegar.sql` ya confirma que la fila de la 0305 está en
-- `migraciones_aplicadas`. Eso dice que la migración CORRIÓ, no que haya dejado
-- las cosas como debía.
--
-- Y esta migración es de las que conviene mirar de cerca, porque **borra dos
-- funciones antes de crear la buena**. Si el `create` no hubiera llegado a
-- correr, `fn_agregar_movimiento` no existiría y el botón de agregar un bono
-- dejaría de funcionar — sin que nada más lo delatara hasta que alguien lo
-- pulsara.
--
-- ── QUÉ MIRAR ───────────────────────────────────────────────────────────────
--
--   · firmas = **1**. Ni 0 (el create no corrió: hay que volver a pegarla) ni 2
--     o 3 (quedó una sobrecarga viva, y entonces una llamada de seis argumentos
--     encaja en dos a la vez → «function ... is not unique», que es el fallo que
--     tuvo el CI en rojo con fn_vacaciones_por_vencer y arregló la 0301).
--   · la columna `periodo_origen_id` presente en `movimientos_planilla`.
--   · el permiso: `authenticated` tiene que poder ejecutarla, o la pantalla de
--     Planilla no puede agregar movimientos.
--
-- El md5 se devuelve para comparar contra el medido en el mismo minuto contra
-- el Postgres local. No va escrito acá: un dato de referencia guardado caduca.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with f as (
  select count(*)                                        as firmas,
         md5(string_agg(p.prosrc, '' order by p.oid))    as md5,
         bool_or(p.prosrc like '%periodo_origen_id%')    as usa_origen
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_agregar_movimiento'
),
c as (
  select count(*) as n
    from information_schema.columns
   where table_name = 'movimientos_planilla' and column_name = 'periodo_origen_id'
),
g as (
  -- Por OID y no por firma escrita: la forma con texto REVIENTA si la función no
  -- existe, y ese es justamente el caso que hay que poder reportar. Sin filas,
  -- bool_or da null y el coalesce lo deja en false.
  select coalesce(bool_or(has_function_privilege('authenticated', p.oid, 'execute')), false) as puede
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_agregar_movimiento'
)
select 1 as orden,
       case when (select firmas from f) = 1
             and (select usa_origen from f)
             and (select n from c) = 1
             and (select puede from g)
            then '✓  La 0305 quedó bien: una sola firma, la columna existe, y la pantalla puede seguir agregando movimientos.'
            else '⚠  Revisa: firmas=' || (select firmas from f)::text
                 || ' (debe ser 1) · usa_origen=' || coalesce((select usa_origen from f)::text, 'null')
                 || ' · columna=' || (select n from c)::text || '/1'
                 || ' · permiso=' || (select puede from g)::text
       end                                               as comprobacion,
       ''::text as md5
union all
select 2, 'md5 de fn_agregar_movimiento', (select md5 from f)
order by orden;
