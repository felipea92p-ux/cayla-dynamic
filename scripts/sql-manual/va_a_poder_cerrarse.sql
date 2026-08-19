-- ############################################################################
-- ####  ¿VA A PODER CERRARSE EL PERIODO?  — SOLO LEE, NO ESCRIBE NADA     ####
-- ############################################################################
--
-- Se corre JUSTO ANTES de pulsar «Marcar como PAGADO», y otra vez el mismo día
-- del cierre. Responde una sola pregunta: ¿`fn_planilla_congelar` va a poder
-- terminar, o va a abortar dejando el mes entero sin cerrar?
--
-- POR QUÉ IMPORTA TANTO. `fn_planilla_congelar` inserta las ~30 filas en UNA
-- sola sentencia. Si algo la frena, no se congela NINGUNA: el mes entero no se
-- puede marcar como pagado. No es plata mal pagada — es el cierre que no se
-- completa, y se descubre en el peor momento.
--
-- HAY DOS FRENOS DISTINTOS, Y ESTE SCRIPT NACIÓ MIRANDO SOLO UNO. La auditoría
-- del 2026-08-19 lo reprodujo: con una persona cesada dentro del periodo y su
-- liquidación ya cobrada, este script imprimía «✓ TODOS CUADRAN» y la función
-- abortaba igual. Un guardián que da luz verde antes de un freno real es peor
-- que no tenerlo: enseña a confiar en él justo el día que no hay que hacerlo.
--
--   FRENO 1 · `chk_foto_cuadra` — el CHECK de `planilla_pagada_detalle`. El
--   total de la fila tiene que ser la suma exacta de sus once partidas. Si una
--   sola no cuadra, el insert entero viola el CHECK.
--
--   FRENO 2 · el `raise exception` de la 0243/0244 — alguien que cesó DENTRO
--   de este periodo, ya cobró su liquidación con `monto_periodo > 0`, tiene
--   total > 0 en la planilla y todavía no tiene registrado el descuento
--   «💸 Ya le pagué aparte» por ese importe. La condición se copia del cuerpo
--   vivo de `fn_planilla_congelar` (0244), no de memoria.
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
filas as (
  select f
  from per, lateral jsonb_array_elements(
         fn_planilla_calcular(per.fecha_ini, per.fecha_fin, per.id) -> 'filas') f
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
  from filas
),
malas as (select * from calc where round(total - suma, 2) <> 0),
-- FRENO 2 · copiado del cuerpo vivo de fn_planilla_congelar (0244).
frenadas as (
  select lq.persona,
         lq.monto_periodo,
         coalesce((f->>'descuentos')::numeric, 0) as descuento_ya_puesto
  from filas, per
  join lateral (
    select distinct on (lp.persona_id) lp.*
    from liquidacion_pagada lp
    where lp.persona_id = (f->>'persona_id')::uuid
    order by lp.persona_id, lp.version desc
  ) lq on true
  where lq.fecha_cese between per.fecha_ini and per.fecha_fin
    and lq.monto_periodo > 0
    and coalesce((f->>'total')::numeric, 0) > 0
    and coalesce((f->>'descuentos')::numeric, 0) < lq.monto_periodo
)
select
  case when (select count(*) from calc) = 0
         then '⚠  LA CONSULTA NO DEVOLVIÓ NADA — no hay periodo abierto, o la sesión de admin no se aplicó'
       when (select count(*) from malas) > 0
         then '🚫 ' || (select count(*) from malas)::text || ' DESCUADRAN de ' || (select count(*) from calc)::text
              || ' — el cierre abortará PARA TODOS (chk_foto_cuadra)'
       when (select count(*) from frenadas) > 0
         then '🚫 ' || (select count(*) from frenadas)::text || ' con liquidación ya cobrada de este periodo'
              || ' — el cierre abortará PARA TODOS (freno 0243/0244)'
       else '✓  TODOS CUADRAN (' || (select count(*) from calc)::text || ' personas) — el cierre puede completarse'
  end                                                                            as veredicto,
  coalesce((select string_agg(persona || ': ' || round(total - suma,2)::text, ' · '
                              order by abs(total-suma) desc) from malas), '—')   as no_cuadran,
  coalesce((select string_agg(persona || ': su liquidación incluye S/'
                              || to_char(monto_periodo, 'FM999999990.00')
                              || ' de este periodo y solo tiene S/'
                              || to_char(descuento_ya_puesto, 'FM999999990.00')
                              || ' de descuento — usa «💸 Ya le pagué aparte»', ' · '
                              order by monto_periodo desc) from frenadas), '—')  as ya_cobraron_su_liquidacion,
  (select coalesce(round(sum(total),2),0) from calc)::text                        as total_del_periodo;
