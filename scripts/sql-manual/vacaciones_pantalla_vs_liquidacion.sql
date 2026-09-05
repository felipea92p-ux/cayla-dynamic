-- ############################################################################
-- ####  VACACIONES: LO QUE DICE LA PANTALLA VS LO QUE PAGARÍA — SOLO LEE   ####
-- ############################################################################
--
-- `fn_vacaciones_resumen` (lo que ve la pantalla de Vacaciones) y
-- `fn_vacaciones_truncas` (lo que la liquidación pagaría al cesar) son dos
-- cuentas distintas, y la auditoría del 14/08 midió que el que paga es el
-- pequeño: la trunca REINICIA el conteo en el último aniversario y descuenta de
-- esa cuenta los días de un récord ANTERIOR que la persona sí se tomó.
--
-- Penaliza al revés de lo que debería: quien se tomó sus vacaciones a tiempo
-- cobra MENOS trunca que quien nunca las tomó.
--
-- No hace falta que nadie cese para que importe: si alguien pregunta hoy cuántos
-- días tiene, la pantalla le responde un número que el sistema no pagaría.
-- ############################################################################

with sesion as (
  select set_config('request.jwt.claim.sub',
           (select auth_user_id::text from personas
             where rol='admin' and auth_user_id is not null
             order by (nombres ilike '%Felipe%') desc limit 1), true) as jwt
),
hoy as (select (now() at time zone 'America/Lima')::date as d from sesion),
pantalla as (
  select (r->>'persona_id')::uuid              as pid,
         r->>'nombre'                          as nombre,
         (r->>'dias_saldo')::numeric           as dias_pantalla,
         (r->>'monto_estimado')::numeric       as monto_pantalla,
         (r->>'dias_tomados')::numeric         as dias_tomados
  from hoy, lateral jsonb_array_elements(fn_vacaciones_resumen(hoy.d)) r
),
liq as (
  select p.pid,
         (fn_vacaciones_truncas(p.pid, (select d from hoy)) ->> 'dias_pendientes')::numeric as dias_liq,
         (fn_vacaciones_truncas(p.pid, (select d from hoy)) ->> 'monto')::numeric           as monto_liq
  from pantalla p
)
select pa.nombre,
       pa.dias_tomados                                   as ya_tomo,
       pa.dias_pantalla                                  as dias_segun_pantalla,
       li.dias_liq                                       as dias_que_pagaria,
       pa.monto_pantalla                                 as monto_segun_pantalla,
       li.monto_liq                                      as monto_que_pagaria,
       round(coalesce(pa.monto_pantalla,0) - coalesce(li.monto_liq,0), 2) as diferencia,
       -- Un null NO es «coinciden». Si cualquiera de los dos lados no se pudo
       -- calcular hay que decirlo, no restar ceros y dar el visto bueno: ese es
       -- el falso negativo mudo que este repositorio ya pagó caro varias veces.
       case when pa.monto_pantalla is null or li.monto_liq is null
              then '⚠  NO SE PUDO CALCULAR uno de los dos lados — no es «coinciden»'
            when round(pa.monto_pantalla - li.monto_liq, 2) = 0
              then '✓  coinciden'
            when pa.monto_pantalla > li.monto_liq
              then '⚠  la pantalla promete MÁS de lo que se pagaría'
            else 'ℹ  la liquidación paga más que lo que muestra la pantalla' end as veredicto
from pantalla pa join liq li on li.pid = pa.pid
order by abs(coalesce(pa.monto_pantalla,0) - coalesce(li.monto_liq,0)) desc;
