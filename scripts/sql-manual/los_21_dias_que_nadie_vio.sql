-- ############################################################################
-- ####  SOLO LEE. No cambia nada. Es para que la leas TÚ, no para mandarla. ####
-- ############################################################################
--
-- los_21_dias_que_nadie_vio.sql — reconstruir lo que la 0189 ya no destruye
--
-- QUÉ RESPONDE
--   Quién llegó más de tres horas tarde entre el 2026-07-11 y hoy, en qué día, y
--   cuántos minutos fueron. Son los días que la comprobación de la 0189 contó
--   como `sin_medir_historicos` — 21 el 2026-08-08.
--
-- POR QUÉ SE PUEDE RECONSTRUIR, SI EL NÚMERO SE DESTRUYÓ
--   Porque lo que se destruyó fue el RESUMEN, no el hecho. `jornadas` es un
--   derivado que mantiene un trigger; `marcajes` es la fuente de verdad y es
--   append-only. La hora real de entrada sigue ahí, intacta, y el horario
--   programado también. Esta consulta vuelve a restar una de la otra, igual que
--   `fn_recalcular_jornada`, sin escribir nada.
--
--   Es exactamente el principio del sistema pagando: «los marcajes son la fuente
--   de verdad». Si la tardanza se hubiera guardado y punto, esta consulta no
--   existiría y esos 21 días serían irrecuperables.
--
-- ⚠️ LLEVA NOMBRES DE PERSONAS. Córrela y léela tú. No hace falta mandársela a
--    nadie: lo único que importa afuera es cuántos casos hay, y eso ya se sabe.
--
-- CÓMO SE LEE, y esto es lo que decide qué hacer con cada fila
--   Un número de más de tres horas casi nunca es «llegó tardísimo». Casi siempre
--   es que ESE DÍA la persona tenía otro turno y el sistema comparó contra el
--   equivocado. Por eso la consulta trae la hora programada AL LADO de la real:
--
--     · si la hora programada no tiene sentido para ese día  → el turno estaba
--       mal cargado. No hay tardanza; hay un horario que corregir.
--     · si la hora programada es la correcta                 → sí llegó tarde de
--       verdad, y es una conversación que no se tuvo.
--
--   El sistema no puede distinguirlas: por eso la 0189 las muestra en vez de
--   decidir por su cuenta que no existen.
-- ############################################################################

with dias_sin_medir as (
  select j.persona_id, j.fecha, j.horas_trabajadas
  from jornadas j
  where j.minutos_tarde is null
    and coalesce(j.horas_trabajadas, 0) > 0
),
con_horario as (
  select d.*,
         -- El mismo camino que usa fn_recalcular_jornada: primero el turno
         -- puntual de ese día, y si no hay, el horario semanal por día de la
         -- semana (0 = domingo). `h.hora_entrada` es el respaldo antiguo.
         coalesce(
           (select t.hora_entrada from turnos t
             where t.persona_id = d.persona_id and t.fecha = d.fecha
               and not t.es_descanso),
           (select coalesce(
                     (h.horario_por_dia -> extract(dow from d.fecha)::int::text ->> 'e')::time,
                     h.hora_entrada)
              from horarios_asignados h
             where h.persona_id = d.persona_id
               and h.vigente_desde <= d.fecha
               and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
             order by h.vigente_desde desc limit 1)
         ) as hora_programada
  from dias_sin_medir d
),
con_entrada as (
  select c.*,
         (select min(m.timestamp_marca) from marcajes m
           where m.persona_id = c.persona_id
             and m.tipo = 'entrada'
             and m.anulada_at is null
             and (m.timestamp_marca at time zone 'America/Lima')::date = c.fecha
         ) as entrada_real
  from con_horario c
  where c.hora_programada is not null
)
select p.nombres || ' ' || p.apellidos                        as persona,
       s.codigo                                               as sede,
       to_char(c.fecha, 'DD/MM/YYYY')                         as dia,
       to_char(c.fecha, 'Dy')                                 as que_dia,
       c.hora_programada                                      as debia_entrar,
       (c.entrada_real at time zone 'America/Lima')::time      as entro,
       floor(extract(epoch from (
         c.entrada_real - ((c.fecha + c.hora_programada) at time zone 'America/Lima')
       )) / 60)::int                                          as minutos_tarde_reales,
       round(c.horas_trabajadas, 2)                           as horas_del_dia
from con_entrada c
join personas p on p.id = c.persona_id
join sedes   s on s.id = p.sede_base_id
where c.entrada_real is not null
  -- Solo lo que la regla vieja borraba. Por debajo de 180 el número está bien
  -- guardado y esta consulta no tiene nada que decir.
  and floor(extract(epoch from (
        c.entrada_real - ((c.fecha + c.hora_programada) at time zone 'America/Lima')
      )) / 60)::int > 180
order by minutos_tarde_reales desc, c.fecha desc;
