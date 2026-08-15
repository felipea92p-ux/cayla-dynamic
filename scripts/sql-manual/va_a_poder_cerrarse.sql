-- ############################################################################
-- ####  ¿VA A PODER CERRARSE EL PERIODO?  — SOLO LEE, NO ESCRIBE NADA     ####
-- ############################################################################
--
-- Se corre JUSTO ANTES de pulsar «Marcar como PAGADO», y otra vez el mismo día
-- del cierre. Responde una sola pregunta: ¿el total de cada persona cuadra con
-- la suma de columnas que exige `chk_foto_cuadra`?
--
-- POR QUÉ IMPORTA TANTO. `fn_planilla_congelar` inserta las ~30 filas en UNA
-- sola sentencia. Si una viola el CHECK, no se congela NINGUNA: el mes entero
-- no se puede marcar como pagado. No es plata mal pagada — es el cierre que no
-- se completa, y se descubre en el peor momento.
--
-- DEVUELVE SIEMPRE UNA FILA, incluso cuando todo está bien. Es deliberado: una
-- tabla vacía se lee exactamente igual que «no corrió», y este repositorio ya
-- perdió dos días por un falso negativo mudo.
--
-- LA SESIÓN DE ADMIN VA DENTRO. `fn_planilla_calcular` la exige, y en el SQL
-- Editor la sesión es `postgres`, que no tiene fila en `personas`. El CTE `per`
-- depende de `sesion`, así que Postgres tiene que evaluarla primero.
--
-- OJO CON LOS NOMBRES, que costó una falsa alarma de veinte personas: la
-- COLUMNA de la foto se llama `descuento_pension`, pero la CLAVE del JSON es
-- `descuento_afp`. El mapeo autoritativo está en el `insert` de
-- `fn_planilla_congelar`; no se escribe de memoria.
-- ############################################################################

with sesion as (
  select set_config('request.jwt.claim.sub',
           (select auth_user_id::text from personas
             where rol = 'admin' and auth_user_id is not null
             order by (nombres ilike '%Felipe%') desc limit 1), true) as jwt
),
per as (
  select p.id, p.fecha_ini, p.fecha_fin
  from periodos_planilla p, sesion
  where (now() at time zone 'America/Lima')::date between p.fecha_ini and p.fecha_fin
  order by p.fecha_ini desc limit 1
),
calc as (
  select f->>'nombre' as persona,
         coalesce((f->>'total')::numeric,0) as total,
         round( coalesce((f->>'pago_base')::numeric,0)
              + coalesce((f->>'monto_feriados')::numeric,0)
              + coalesce((f->>'monto_plus')::numeric,0)
              + coalesce((f->>'asignacion_familiar')::numeric,0)
              + coalesce((f->>'monto_movilidad')::numeric,0)
              + coalesce((f->>'monto_educacion')::numeric,0)
              - coalesce((f->>'descuento_afp')::numeric,0)
              + coalesce((f->>'monto_sobretiempo')::numeric,0)
              + coalesce((f->>'bonos')::numeric,0)
              - coalesce((f->>'descuentos')::numeric,0)
              - coalesce((f->>'retencion_4ta')::numeric,0), 2) as suma
  from per, lateral jsonb_array_elements(
         fn_planilla_calcular(per.fecha_ini, per.fecha_fin, per.id) -> 'filas') f
),
malas as (select * from calc where round(total - suma, 2) <> 0)
select
  case when (select count(*) from calc) = 0
         then '⚠  LA CONSULTA NO DEVOLVIÓ NADA — no hay periodo abierto, o la sesión de admin no se aplicó'
       when (select count(*) from malas) = 0
         then '✓  TODOS CUADRAN (' || (select count(*) from calc)::text || ' personas) — el cierre puede completarse'
       else '🚫 ' || (select count(*) from malas)::text || ' DESCUADRAN de ' || (select count(*) from calc)::text
              || ' — el cierre abortará PARA TODOS' end                            as veredicto,
  coalesce((select string_agg(persona || ': ' || round(total - suma,2)::text, ' · '
                              order by abs(total-suma) desc) from malas), '—')     as quienes,
  (select coalesce(round(sum(total),2),0) from calc)::text                          as total_del_periodo;
