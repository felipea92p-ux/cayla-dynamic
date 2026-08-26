-- ############################################################################
-- ####  ¿LLEGARON BIEN LA 0288 Y LA 0298?  — SOLO LEE, NO ESCRIBE NADA    ####
-- ############################################################################
--
-- Para qué. Las dos ya se pegaron. Esto comprueba que producción quedó con lo
-- que dice el repositorio, en una sola consulta.
--
-- ⚠ Los md5 esperados NO van escritos acá. Un dato de referencia guardado
-- caduca y acusa en falso — la lección está en docs/estado.md. La consulta los
-- devuelve y se comparan contra los que se midieron en el mismo minuto contra
-- el Postgres local.
--
-- ── QUÉ MIRAR ───────────────────────────────────────────────────────────────
--
-- 0288 · La puerta de borrar marcajes
--   · borrar_authenticated = **false** → cerrada. Si dice true, la migración no
--     entró o alguien devolvió el grant.
--   · anular_authenticated = **true** → la puerta BUENA sigue abierta. Si dice
--     false, la pantalla de Correcciones dejó de poder anular y hay que
--     arreglarlo ya.
--
-- 0298 · Los turnos dejan rastro
--   · Las tres funciones con `anota = true`. Un false ahí significa que esa
--     función quedó en su versión vieja y sigue sobrescribiendo en silencio.
--   · `fn_turno_texto` presente, con `anota = false` — correcto: solo formatea,
--     no escribe.
--   · `turnos` con las columnas `created_at` y `creado_por`.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with fn as (
  select p.proname,
         md5(p.prosrc)                                    as md5,
         length(p.prosrc)::text                           as caracteres,
         (p.prosrc like '%correcciones_auditoria%')       as anota
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('fn_set_turno', 'fn_set_descanso',
                       'fn_quitar_turno', 'fn_turno_texto')
),
cols as (
  select count(*) as n
    from information_schema.columns
   where table_name = 'turnos' and column_name in ('created_at', 'creado_por')
),
perm as (
  select has_function_privilege('authenticated', 'fn_eliminar_marcaje(uuid, text)', 'execute') as borrar,
         has_function_privilege('authenticated', 'fn_anular_marcaje(uuid, text)',   'execute') as anular
)
select 1 as orden,
       case when (select not borrar and anular from perm)
            then '✓  0288 · borrar marcajes CERRADO para el navegador, y anular sigue abierto.'
            else '⚠  0288 · revisa: borrar_authenticated=' || (select borrar from perm)::text
                 || ' (debe ser false) · anular_authenticated=' || (select anular from perm)::text
                 || ' (debe ser true).'
       end                                                as comprobacion,
       ''::text as md5, ''::text as caracteres, ''::text as anota
union all
select 2,
       case when (select count(*) from fn where anota) = 3
             and (select count(*) from fn) = 4
             and (select n from cols) = 2
            then '✓  0298 · las tres funciones de turnos anotan, fn_turno_texto existe, y turnos tiene sus dos columnas.'
            else '⚠  0298 · faltan piezas: ' || (select count(*) from fn where anota)::text
                 || '/3 anotan · ' || (select count(*) from fn)::text
                 || '/4 funciones · ' || (select n from cols)::text || '/2 columnas.'
       end,
       '', '', ''
union all
select 3,
       'migraciones anotadas',
       coalesce((select string_agg(numero::text, ' · ' order by numero)
                   from migraciones_aplicadas where numero in (288, 298)), 'ninguna'),
       '', ''
union all
select 4, proname, md5, caracteres, anota::text
  from fn
order by orden, comprobacion;
