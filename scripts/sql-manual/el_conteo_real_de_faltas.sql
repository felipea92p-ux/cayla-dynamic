-- ============================================================================
-- EL CONTEO REAL DE FALTAS, Y SI SE PUEDE CREER — solo LEE. SQL Editor.
-- ============================================================================
--
-- ⚠️ ESTE RESULTADO LLEVA NOMBRES. Míralo y decide; si hace falta compartirlo,
--    comparte el bloque RESUMEN, que no nombra a nadie.
--
-- ── QUÉ RESPONDE ────────────────────────────────────────────────────────────
--
-- El artículo 21.5 del Reglamento —que copia el inciso h) del art. 25 de la
-- LPCL— fija tres umbrales de inasistencia injustificada:
--
--     · más de 3 días CONSECUTIVOS          ⇒ causal desde el 4.º
--     · más de 5 en 30 días calendario      ⇒ causal desde la 6.ª
--     · más de 15 en 180 días calendario    ⇒ causal desde la 16.ª
--
-- `fn_faltas_resumen()` los calcula y pinta un semáforo. Esta consulta los
-- muestra y —lo que importa— deja ver de qué están hechos.
--
-- ── POR QUÉ NO BASTA CON LEER EL SEMÁFORO ───────────────────────────────────
--
-- Porque el riesgo número uno de este sistema no es dejar pasar una falta: es
-- ACUSAR DE FALTA A QUIEN NO DEBÍA. Un número en rojo que nadie audita puede
-- acabar en una amonestación injusta a una persona real, y si llega a un
-- despido, lo vuelve arbitrario.
--
-- Por eso el bloque RESUMEN trae la materia prima: cuántas faltas se detectaron
-- en total, cuántas están justificadas y cuántas no. Si el número de faltas
-- detectadas es enorme comparado con el equipo, casi siempre significa que
-- alguien no tiene horario cargado o que un turno quedó mal — no que la gente
-- haya dejado de venir.
--
-- ── LO QUE NO MIDE ──────────────────────────────────────────────────────────
--
-- No dice si procede sancionar. Los umbrales son condición necesaria y no
-- suficiente: hacen falta además el procedimiento del art. 21.6 —carta de
-- imputación con no menos de SEIS días naturales para el descargo— y la
-- inmediatez. Una falta vieja sin reproche a tiempo se entiende condonada, y la
-- carga de probar que se actuó a tiempo es de la empresa.
--
-- El sistema avisa; nunca dice «despide».
-- ============================================================================

with resumen as (
  select * from fn_faltas_resumen()
),
detalle as (
  -- La materia prima de los últimos 180 días, que es la ventana más larga que
  -- miran los umbrales.
  select * from fn_faltas(current_date - 180, current_date - 1)
),
lineas as (

  -- ── RESUMEN — sin nombres, se puede compartir ─────────────────────────────
  -- ⚠️ `fn_faltas_resumen` NO devuelve al equipo entero: devuelve a quien tiene
  -- algo que contar. Comprobado el 2026-08-15 con tres personas sembradas —una
  -- con cuatro faltas, otra con esas cuatro justificadas, y un admin sin
  -- turnos—: devolvió UNA fila. Llamar a esto «personas en el conteo» hacía
  -- pensar que el semáforo solo vigila a esa, que es lo contrario de lo que
  -- pasa.
  select 0 as orden, 'RESUMEN' as bloque,
         'Personas con algo que contar' as dato,
         count(*)::text as valor,
         'Quien no aparece aquí es porque no tiene ninguna falta' as lectura
  from resumen

  union all
  select 1, 'RESUMEN', 'En verde (ningún umbral cerca)',
         count(*) filter (where nivel = 'verde')::text, ''
  from resumen

  union all
  select 2, 'RESUMEN',
         case when count(*) filter (where nivel = 'ambar') = 0
              then 'En ámbar (acercándose)' else '⚠ En ámbar (acercándose)' end,
         count(*) filter (where nivel = 'ambar')::text,
         '3 consecutivas, o 4 en 30 días, o 12 en 180'
  from resumen

  union all
  select 3, 'RESUMEN',
         case when count(*) filter (where nivel = 'rojo') = 0
              then 'En rojo (umbral legal cruzado)' else '⚠ En rojo (umbral legal cruzado)' end,
         count(*) filter (where nivel = 'rojo')::text,
         'Art. 21.5 del RIT · art. 25-h LPCL'
  from resumen

  -- ── LA MATERIA PRIMA — para poder desconfiar del número ───────────────────
  union all
  select 10, 'DE QUÉ ESTÁ HECHO', 'Días detectados como falta (últimos 180)',
         count(*)::text,
         'Si esto es enorme para el tamaño del equipo, sospecha de un horario mal cargado'
  from detalle

  union all
  select 11, 'DE QUÉ ESTÁ HECHO', 'De ellos, JUSTIFICADOS',
         count(*) filter (where justificada)::text,
         'No cuentan para ningún umbral'
  from detalle

  union all
  select 12, 'DE QUÉ ESTÁ HECHO', 'De ellos, INJUSTIFICADOS',
         count(*) filter (where not justificada)::text,
         'Son los únicos que suman'
  from detalle

  union all
  select 13, 'DE QUÉ ESTÁ HECHO', 'Personas con al menos una falta injustificada',
         count(distinct persona_id) filter (where not justificada)::text, ''
  from detalle

  -- ── PERSONA A PERSONA — lleva nombres ────────────────────────────────────
  union all
  select 20, 'PERSONA A PERSONA',
         nombre || ' · ' || sede,
         'consec ' || consecutivas || ' · 30d ' || en_30 || ' · 180d ' || en_180,
         case nivel
           when 'rojo'  then '⚠ ROJO — ' ||
                case when consecutivas > 3 then 'abandono: más de 3 consecutivas'
                     when en_30 > 5        then 'más de 5 en 30 días'
                     when en_180 > 15      then 'más de 15 en 180 días'
                     else 'umbral cruzado' end
           when 'ambar' then 'ámbar — se está acercando'
           else 'verde'
         end
  from resumen
  where consecutivas > 0 or en_30 > 0 or en_180 > 0
)
select bloque, dato, valor, lectura
from lineas
order by orden,
         -- Dentro de «persona a persona», primero quien está peor.
         case when bloque = 'PERSONA A PERSONA' then dato end;
