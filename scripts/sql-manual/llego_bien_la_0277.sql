-- ############################################################################
-- ####  ¿LLEGÓ BIEN LA 0277?  — SOLO LEE, NO ESCRIBE NADA                 ####
-- ############################################################################
--
-- Para qué. La 0277 ya se pegó. Esto comprueba que producción quedó con lo que
-- dice el repositorio, y de paso responde la pregunta que dejó abierta el
-- diagnóstico: quiénes son las 3 activas SIN NINGÚN TRAMO de régimen.
--
-- ⚠ NO lleva escritos los md5 esperados a propósito. Un dato de referencia
-- guardado caduca en horas y acusa en falso — esa lección está escrita en
-- docs/estado.md. Los devuelve, y se comparan contra los que se midieron en el
-- mismo minuto contra el Postgres local.
--
-- Lo que hay que ver:
--   · fn_set_regimen_pension       → 262 caracteres. Es el cuerpo que solo
--                                     levanta excepción. Si trae ~2.391, la
--                                     0277 NO reemplazó la función vieja.
--   · fn_cambiar_regimen_pension   → 4.848 caracteres, DEFINER.
--   · fn_regimen_pension_divergentes → 457 caracteres, y modo **invoker**.
--                                     Si dice DEFINER, se pegó una versión
--                                     anterior de la migración y hay una fuga:
--                                     cualquier sesión autenticada leería el
--                                     padrón entero saltándose la RLS.
--
-- Y en el bloque de personas:
--   · «sin régimen» = no hay nada que versionar. Correcto, no hace falta nada.
--   · con régimen   = les falta su tramo: la planilla las resuelve hoy por el
--                     respaldo, pero su régimen NO tiene historia, así que
--                     recalcular un periodo viejo usaría el valor de HOY. Eso
--                     es el defecto que la 0261 vino a cerrar, todavía abierto
--                     para ellas. Se arregla con un relleno como el de la 0261.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with funciones as (
  select p.proname                                        as nombre,
         md5(p.prosrc)                                     as md5,
         length(p.prosrc)::text                            as caracteres,
         case when p.prosecdef then 'DEFINER' else 'invoker' end as modo
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('fn_cambiar_regimen_pension',
                       'fn_set_regimen_pension',
                       'fn_regimen_pension_divergentes')
),
sin_tramo as (
  select (p.nombres || ' ' || p.apellidos)            as nombre,
         coalesce(p.regimen_pension, 'sin régimen')   as md5,
         p.fecha_ingreso::text                        as caracteres,
         case when p.regimen_pension is null
              then 'nada que versionar'
              else '⚠ le falta su tramo'
         end                                          as modo
    from personas p
   where p.estado = 'activo'
     and not exists (select 1 from asignaciones_regimen_pension a
                      where a.persona_id = p.id)
)
select 1 as orden, 'FUNCIONES (nombre · md5 · caracteres · modo)' as nombre,
       '' as md5, '' as caracteres, '' as modo
union all
select 2, nombre, md5, caracteres, modo from funciones
union all
select 3,
       case when (select count(*) from migraciones_aplicadas where numero = 277) = 1
            then '✓  La 0277 quedó anotada en migraciones_aplicadas.'
            else '⚠  La 0277 NO está anotada en migraciones_aplicadas.'
       end,
       '', '', ''
union all
select 4, 'ACTIVAS SIN TRAMO (nombre · régimen de la ficha · ingreso · qué hacer)',
       '', '', ''
union all
select 5, nombre, md5, caracteres, modo from sin_tramo
order by orden, nombre;
