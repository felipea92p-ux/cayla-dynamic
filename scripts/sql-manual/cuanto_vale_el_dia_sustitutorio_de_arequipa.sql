-- ============================================================================
-- ¿CUÁNTO VALE EL DÍA SUSTITUTORIO, PERSONA A PERSONA? — solo LEE.
-- ============================================================================
--
-- ⚠️ El resultado lleva nombres y montos. Míralo y decide; no lo pegues entero.
--
-- ── EL CASO ─────────────────────────────────────────────────────────────────
--
-- El 15/08/2026 es «día cívico no laborable» en la provincia de Arequipa —art. 8
-- de la Ley 24875, aplicado conforme al art. 7 del D. Leg. 713—. NO es un feriado
-- nacional: no genera pago triple. La tienda AQP abre ese día (sábado) y se
-- otorga descanso sustitutorio el 31/08 (lunes).
--
-- Felipe decide reconocerlo igual, pagando el día al ritmo real de trabajo de
-- cada persona. Esa es exactamente la fórmula que el sistema ya usa para el día
-- de feriado prorrateado cuando SÍ hay descanso sustitutorio (migración 0069):
--
--     monto = 7.5 * horas_mes / base * salario / base       con base = 6.5 * días
--
-- Quien cumple jornada completa cobra alrededor de un día; quien hace medio
-- tiempo cobra la mitad. No hace falta clasificar a nadie como «full time» o
-- «medio tiempo»: sale solo de sus horas.
--
-- ── POR QUÉ ESTO Y NO LA PANTALLA DE FERIADOS ───────────────────────────────
--
-- La tabla `feriados` son dos columnas —fecha y nombre— y NO TIENE SEDE. Meter
-- ahí el 15/08 le pagaría el día prorrateado también a Trujillo, Lima y Central,
-- y como cae sábado —que en Trujillo se trabaja— quien marcara ese día en TRU
-- cobraría además el 100 % de recargo. Por un feriado que solo existe en
-- Arequipa.
--
-- Mientras no haya feriados por sede, la vía correcta es un movimiento por
-- persona en la planilla, con el concepto escrito. Esta consulta calcula el
-- monto exacto de cada una para que se registre sin inventar cifras.
--
-- ── CÓMO SE USA ─────────────────────────────────────────────────────────────
--
-- Cambia `:periodo` abajo por el periodo en el que lo vayas a pagar. Lo natural
-- es el de SEPTIEMBRE (29/08–28/09), porque es donde cae el descanso del 31/08
-- y por tanto donde esa persona trabaja un día menos. Pagarlo ahí deja la
-- compensación y su costo en el mismo mes.
-- ============================================================================

select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and nombres ilike '%Felipe%' and auth_user_id is not null limit 1),
  true);

with periodo as (
  -- El periodo donde cae el descanso sustitutorio del 31/08.
  select id, fecha_ini, fecha_fin, (fecha_fin - fecha_ini) + 1 as dias
  from periodos_planilla
  where '2026-08-31'::date between fecha_ini and fecha_fin
  order by fecha_ini desc
  limit 1
),
calc as (
  select p.*, 6.5 * p.dias as base,
         jsonb_array_elements(fn_planilla_calcular(p.fecha_ini, p.fecha_fin, p.id) -> 'filas') as f
  from periodo p
)
select
  f->>'nombre'                                    as persona,
  f->>'sede'                                      as sede,
  round((f->>'horas_mes')::numeric, 2)            as horas_del_periodo,
  round((f->>'salario_ref')::numeric, 2)          as salario,
  -- La fórmula de la 0069, tal cual. Escala con las horas: quien hace media
  -- jornada cobra la mitad, sin que nadie tenga que clasificarla.
  round(
    7.5 * (f->>'horas_mes')::numeric / base
        * (f->>'salario_ref')::numeric / base
  , 2)                                            as dia_sustitutorio,
  fecha_ini || ' a ' || fecha_fin                  as periodo_donde_pagarlo
from calc
where f->>'sede' = 'AQP'
  and (f->>'en_planilla')::boolean is not false   -- un locador no cobra feriados
order by (f->>'nombre');
