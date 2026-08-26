-- ############################################################################
-- ####  ¿QUÉ PASÓ CON LA 0309?  — SOLO LEE, NO ESCRIBE NADA               ####
-- ############################################################################
--
-- Para qué. El 2026-08-26 la 0309 se pegó en el SQL Editor y murió a media
-- ejecución con «relation "_horario_antes" does not exist». La migración usaba
-- una tabla temporal para guardar el horario efectivo ANTES del arreglo y
-- compararlo DESPUÉS; el SQL Editor no la mantiene entre sentencias, así que el
-- bloque de comprobación no encontró nada que leer.
--
-- El problema no es el error en sí: es DÓNDE cayó. El orden de la migración era
--
--     1. crear la tabla temporal          (inofensivo)
--     2. el UPDATE que acorta los tramos  ← toca datos
--     3. el bloque de comprobación        ← aquí murió
--     4. el candado EXCLUDE
--     5. la fila en migraciones_aplicadas
--
-- Si el SQL Editor corrió cada sentencia por su cuenta, el paso 2 quedó
-- aplicado y los pasos 4 y 5 no. Eso deja producción a medias: los datos
-- arreglados, pero sin el candado que impide que vuelva a pasar — y sin la fila
-- que le diría a `que_falta_pegar.sql` que la 0309 se aplicó.
--
-- Si en cambio el editor lo envolvió todo en una transacción, no quedó nada.
--
-- Esta consulta distingue los dos casos. No propone nada: mide.
--
-- ── CÓMO SE LEE ─────────────────────────────────────────────────────────────
--
--   · candado = 1 y solapes = 0 → aplicó entero (o casi: mira la fila 4).
--   · candado = 0 y solapes = 0 → **quedó a medias**: el arreglo de datos entró
--     y el candado no. No es una avería —los datos están como deben— pero falta
--     cerrar la puerta.
--   · candado = 0 y solapes > 0 → no entró nada. Se puede reintentar limpio.
--
--   · «cambiarían» es la comprobación que no llegó a correr, hecha ahora desde
--     fuera: cuenta los días-persona en los que acortar un tramo le cambiaría
--     el horario efectivo a alguien. **Tiene que ser 0.** Si no lo es, hay un
--     solape que exige decidir cuál tramo vale, y esa decisión cambia si a
--     alguien se le contó tardanza o falta.
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
rastro as (
  select count(*) as n from migraciones_aplicadas where numero = 309
),
pegados as (
  select count(*) as n
    from horarios_asignados a
   where a.vigente_hasta is not null
     and exists (select 1 from horarios_asignados b
                  where b.persona_id = a.persona_id
                    and b.vigente_desde = a.vigente_hasta + 1)
),
-- La comprobación que no llegó a correr, escrita sin tabla temporal.
--
-- Un tramo A que se pisa con otros pierde los días que van desde el arranque
-- del más cercano hasta su propio cierre. Para cada uno de esos días se
-- pregunta: ¿hay algún tramo que empiece DESPUÉS de A y que cubra ese día? Si
-- lo hay, A ya estaba tapado ahí y perderlo no cambia nada. Si no lo hay, A era
-- quien mandaba y acortarlo SÍ le cambia el horario a esa persona ese día.
por_perder as (
  select a.id, a.persona_id, a.vigente_desde, a.vigente_hasta as cierre,
         (select min(b.vigente_desde)
            from horarios_asignados b
           where b.persona_id    = a.persona_id
             and b.vigente_desde > a.vigente_desde) as arranque_del_siguiente
    from horarios_asignados a
   where a.vigente_hasta is not null
),
cambiarian as (
  select count(*) as n
    from por_perder t
   cross join lateral generate_series(t.arranque_del_siguiente, t.cierre, interval '1 day') g
   where t.arranque_del_siguiente is not null
     and t.cierre >= t.arranque_del_siguiente
     and not exists (
       select 1
         from horarios_asignados c
        where c.persona_id     = t.persona_id
          and c.vigente_desde  > t.vigente_desde
          and c.vigente_desde <= g::date
          and (c.vigente_hasta is null or c.vigente_hasta >= g::date)
     )
)
select 1 as orden,
       case
         when (select n from candado) = 1 and (select n from solapes) = 0
           then '✓  APLICÓ ENTERO. El candado está puesto y no queda ningún solape.'
         when (select n from candado) = 0 and (select n from solapes) = 0
           then '◑  QUEDÓ A MEDIAS. Los datos ya están arreglados —no queda ningún solape— pero el candado NO se creó. No es una avería: falta cerrar la puerta.'
         when (select n from candado) = 0 and (select n from solapes) > 0
           then '○  NO ENTRÓ NADA. Siguen ' || (select n from solapes)::text || ' solape(s). Se puede reintentar limpio.'
         else '⚠  Estado raro: candado=' || (select n from candado)::text
              || ' y solapes=' || (select n from solapes)::text || '. Míralo antes de tocar nada.'
       end                                                       as estado,
       ''::text as dato
union all
select 2, 'candado horarios_sin_solape (0 = no está, 1 = puesto)',
       (select n from candado)::text
union all
select 3, 'pares de tramos que todavía se pisan (eran 10)',
       (select n from solapes)::text
union all
select 4, 'fila 309 en migraciones_aplicadas (0 = no llegó a escribirse)',
       (select n from rastro)::text
union all
select 5, 'días-persona a los que el arreglo LES CAMBIARÍA el horario (debe ser 0)',
       (select n from cambiarian)::text
union all
select 6, 'tramos que cierran la víspera del siguiente (huella del arreglo)',
       (select n from pegados)::text
union all
select 7, 'tramos de horario en total',
       (select count(*) from horarios_asignados)::text
order by orden;
