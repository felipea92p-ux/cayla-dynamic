-- ############################################################################
-- ####  ¿CADA CUÁNTO CIERRA EL DÍA UN PROCESO Y NO UNA PERSONA?  — SOLO LEE ##
-- ############################################################################
--
-- Para qué. `cuanto_paga_la_hora_inventada.sql` mira `jornadas.estado`, que es
-- el estado de HOY: en cuanto alguien confirma un día auto-cerrado, pasa a
-- `revisada` y desaparece de esa cuenta. Un cero ahí significa «no hay ninguno
-- pendiente ahora mismo», y no dice nada sobre cuántas veces ha pasado.
--
-- Esta lo responde por el otro lado, que sí es un historial: cada auto-cierre
-- deja un MARCAJE con `origen = 'auto_cierre'`, y los marcajes son append-only
-- —se anulan, no se borran (0081)—, así que la cuenta no se puede perder.
--
-- ⚠ La primera versión de esta consulta agrupaba por `fecha_jornada` y devolvió
-- todas las fechas en NULL: esa columna nació con la 0240 y los marcajes
-- anteriores no la tienen. Se agrupa por `timestamp_marca`, que es NOT NULL
-- desde el principio, con `fecha_jornada` como preferencia cuando existe.
--
-- ── Y LA SEGUNDA PREGUNTA, QUE APARECIÓ AL VER EL PRIMER RESULTADO ──────────
--
-- Hay marcajes de auto-cierre en `pendiente_revision` mientras que ninguna
-- jornada figura en `auto_cerrada_pendiente`. Los dos estados viven en tablas
-- distintas y pueden discrepar.
--
-- Importa mucho: el freno que se está evaluando para el cierre de mes leería
-- `dias_pendientes`, que se calcula desde **jornadas**. Si un marcaje puede
-- quedar sin revisar mientras su jornada ya no lo dice, ese freno no lo vería.
-- El cruce de abajo dice si eso pasa y en cuántos casos.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with cierres as (
  select m.id,
         coalesce(m.fecha_jornada,
                  (m.timestamp_marca at time zone 'America/Lima')::date) as dia,
         m.estado_revision::text                    as estado_marca,
         (m.anulada_at is not null)                 as anulada,
         j.estado::text                             as estado_jornada
    from marcajes m
    left join jornadas j
      on j.persona_id = m.persona_id
     and j.fecha = coalesce(m.fecha_jornada,
                            (m.timestamp_marca at time zone 'America/Lima')::date)
   where m.origen = 'auto_cierre'
),
total as (
  select count(*) as n, min(dia) as primero, max(dia) as ultimo,
         count(*) filter (where estado_marca = 'pendiente_revision' and not anulada) as sin_revisar,
         count(*) filter (where anulada) as anulados
    from cierres
),
descuadre as (
  select count(*) as n
    from cierres
   where estado_marca = 'pendiente_revision'
     and not anulada
     and coalesce(estado_jornada, '(sin jornada)') <> 'auto_cerrada_pendiente'
)
select 1 as orden,
       case when (select n from total) = 0
            then '✓  El cron nunca ha cerrado un día. El defecto es teórico.'
            else 'El cron ha cerrado ' || (select n from total)::text || ' día(s), del '
                 || coalesce((select primero from total)::text, '?') || ' al '
                 || coalesce((select ultimo from total)::text, '?')
                 || '. Sin revisar hoy: ' || (select sin_revisar from total)::text
                 || ' · anulados: ' || (select anulados from total)::text || '.'
       end                                          as concepto,
       ''::text as mes, ''::text as dias, ''::text as estados
union all
select 2,
       case when (select n from descuadre) = 0
            then '✓  Marcaje y jornada coinciden: todo marcaje sin revisar tiene su jornada en auto_cerrada_pendiente. Un freno que mire la jornada los ve todos.'
            else '⚠  ' || (select n from descuadre)::text
                 || ' marcaje(s) sin revisar cuya jornada NO dice auto_cerrada_pendiente. '
                 || 'Un freno que mire solo la jornada NO los vería. Detalle en el cruce de abajo.'
       end,
       '', '', ''
union all
select 3, 'Por mes', to_char(dia, 'YYYY-MM'), count(*)::text,
       string_agg(distinct estado_marca, ' · ' order by estado_marca)
  from cierres group by to_char(dia, 'YYYY-MM')
union all
select 4, 'Cruce marcaje × jornada',
       'marcaje: ' || estado_marca,
       count(*)::text,
       'jornada: ' || coalesce(estado_jornada, '(sin jornada)')
  from cierres
 where not anulada
 group by estado_marca, coalesce(estado_jornada, '(sin jornada)')
order by orden, mes, estados;
