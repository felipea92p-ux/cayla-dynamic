-- ############################################################################
-- ####  ¿LLEGÓ BIEN LA 0309?  — SOLO LEE, NO ESCRIBE NADA                 ####
-- ############################################################################
--
-- Para qué. `que_falta_pegar.sql` confirma que la fila de la 0309 está en
-- `migraciones_aplicadas`. Eso dice que la migración CORRIÓ, no que haya dejado
-- las cosas como debía.
--
-- Y esta conviene mirarla de cerca por dos motivos. Primero, porque **toca
-- datos**: acorta tramos de horario que ya existían. Segundo, porque su prueba
-- de invarianza viaja en un `raise notice`, y el SQL Editor no muestra los
-- notices — así que al pegarla no se ve nada. El silencio ES la buena noticia
-- (si algo no cuadraba, la migración aborta con un error bien visible y no
-- aplica nada), pero conviene comprobarlo con datos y no con una ausencia.
--
-- ── QUÉ MIRAR ───────────────────────────────────────────────────────────────
--
--   · candado = **1**. Si es 0, el EXCLUDE no llegó a crearse: la migración se
--     cortó antes del final y hay que volver a pegarla.
--   · solapes = **0**. Con el candado puesto no puede haber otro número, pero se
--     mide igual: es lo que el candado promete, y una promesa se comprueba.
--   · pegados = cuántos tramos cierran justo la víspera del siguiente. Es la
--     huella del arreglo. No hay un número «correcto» esperado — se mira para
--     saber cuántos se tocaron, y debería andar por los diez de la medición.
--   · la pantalla = que `fn_set_horario_semanal` siga existiendo y que
--     `authenticated` pueda ejecutarla. El candado no la toca, pero es lo que
--     dejaría de funcionar si algo saliera mal, y no se notaría hasta que
--     alguien intentara asignar un horario.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with candado as (
  select count(*) as n
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
   where t.relname = 'horarios_asignados'
     and c.conname = 'horarios_sin_solape'
     and c.contype = 'x'
),
solapes as (
  select count(*) as n
    from horarios_asignados a
    join horarios_asignados b
      on b.persona_id = a.persona_id
     and b.id > a.id
     and daterange(a.vigente_desde, coalesce(a.vigente_hasta, 'infinity'::date), '[]')
      && daterange(b.vigente_desde, coalesce(b.vigente_hasta, 'infinity'::date), '[]')
),
pegados as (
  select count(*) as n
    from horarios_asignados a
   where a.vigente_hasta is not null
     and exists (select 1 from horarios_asignados b
                  where b.persona_id = a.persona_id
                    and b.vigente_desde = a.vigente_hasta + 1)
),
pantalla as (
  -- Por OID y no por firma escrita: la forma con texto REVIENTA si la función no
  -- existe, y ese es justamente el caso que hay que poder reportar.
  select count(*) as firmas,
         coalesce(bool_or(has_function_privilege('authenticated', p.oid, 'execute')), false) as puede
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_set_horario_semanal'
)
select 1 as orden,
       case when (select n from candado) = 1
             and (select n from solapes) = 0
             and (select firmas from pantalla) >= 1
             and (select puede from pantalla)
            then '✓  La 0309 quedó bien: el candado está puesto, no queda ni un solape, y la pantalla de Horarios sigue pudiendo asignar.'
            else '⚠  Revisa: candado=' || (select n from candado)::text || '/1'
                 || ' · solapes=' || (select n from solapes)::text || ' (debe ser 0)'
                 || ' · fn_set_horario_semanal firmas=' || (select firmas from pantalla)::text
                 || ' permiso=' || (select puede from pantalla)::text
       end                                                     as comprobacion,
       ''::text as dato
union all
select 2, 'tramos que cierran la víspera del siguiente (huella del arreglo)',
       (select n from pegados)::text
union all
select 3, 'tramos de horario en total',
       (select count(*) from horarios_asignados)::text
order by orden;
