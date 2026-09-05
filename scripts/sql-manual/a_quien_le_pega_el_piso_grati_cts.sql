-- ############################################################################
-- ####  ¿A QUIÉN LE PEGA EL PISO DE GRATI/CTS SIN CORREGIR?  — SOLO LEE     ####
-- ############################################################################
--
-- Crítico 7 de la auditoría 2026-09-03/04: «El piso legal de gratificación/CTS
-- (0338) nunca corrige una ventana que ya se pagó».
--
-- EL MECANISMO EXACTO (visto en 0338, lateral `cobrado`, líneas 860-866):
--
--   cobrado.g1 := greatest(case when pag.g1 then devengado.g1 else 0 end,
--                          lib.grati_s1)
--
-- `pag.g1` solo dice SI existe un movimiento de planilla en esa ventana — no
-- CUÁNTO se pagó. Así que cuando `pag.g1` es verdadero, `cobrado.g1` se define
-- como el `devengado.g1` de esa MISMA llamada — el día a día si la llamada es
-- la normal, o el piso si la llamada es la del piso (p_salario_asof = fecha de
-- corte). Cualquiera de las dos formas, la resta `devengado - cobrado` da CERO
-- en cuanto existe el movimiento, así que la comparación «el piso corrige
-- hacia arriba cuando fue mayor» nunca llega a compararse contra nada para una
-- ventana ya pagada por planilla. Es la misma decisión de la 0158 («se toma la
-- mayor, nunca la suma», prueba 124) — no reabrir ventanas ya asentadas para
-- no arriesgar un descuento doble — pero tiene este efecto colateral: una
-- ventana cerrada ANTES de que la 0338 existiera (2026-09-01) nunca tuvo la
-- oportunidad de compararse contra el piso al momento de pagarse, y hoy ya no
-- se puede, porque `fn_provisiones` no puede verse a sí misma.
--
-- POR QUÉ ESTA CONSULTA NO INTENTA RECALCULAR EL MONTO. Reimplementar el
-- cálculo día-a-día completo (jornadas, feriados vía fn_feriado_devengado,
-- ausencias pagadas, sueldo fijo, el factor base_provision) fuera de
-- fn_provisiones es exactamente la duplicación de ~300 líneas que la propia
-- cabecera de la 0338 rechazó por el riesgo de que un arreglo futuro solo
-- toque una de las dos copias. Antes de correr ESE riesgo hace falta saber si
-- hay alguien a quien preguntarle — la misma regla que ya usa
-- `a_quien_le_pega.sql`: un hallazgo sin población es una hipótesis.
--
-- QUÉ HACE ESTA CONSULTA: encuentra la POBLACIÓN. Para cada ventana de
-- gratificación/CTS con fecha de pago ANTES del 2026-09-01 (antes de que la
-- 0338 pudiera aplicar el piso al cerrarse) que YA tiene un movimiento de
-- planilla registrado (cerrada), busca a quien tuvo un CAMBIO DE SUELDO
-- dentro de esa ventana — no en el borde, adentro — porque solo ahí el día a
-- día puede quedar por debajo de lo que exige tomar el sueldo del cierre.
--
-- SI DEVUELVE CERO FILAS: el defecto es real (el mecanismo existe, lo prueba
-- el código) pero no cuesta nada HOY — igual que otros hallazgos «latentes» ya
-- catalogados en hallazgos-abiertos.md. Se anota y no se toca.
--
-- SI DEVUELVE ALGUNA FILA: recién ahí vale la pena, para esas personas
-- puntuales, calcular a mano en el Postgres LOCAL (BEGIN … ROLLBACK, con su
-- caso real) cuánto exige el piso y compararlo contra `monto_pagado_planilla`
-- de esta misma fila — que si sale menor, es el faltante real, exacto, para
-- ajustar con `fn_registrar_desembolso` (nunca reabriendo el periodo pagado).
--
-- ES UN SOLO SELECT A PROPÓSITO: el SQL Editor de Supabase ejecuta solo la
-- última sentencia.
-- ############################################################################

with anios as (
  select generate_series(2020, extract(year from now())::int) as y
),
ventanas as (
  select y, 'gratificacion'::text as categoria, 'grati_s1'::text as ref,
         make_date(y,1,1) as ini, make_date(y,6,30) as fin, make_date(y,7,15) as pago
  from anios
  union all
  select y, 'gratificacion', 'grati_s2',
         make_date(y,7,1), make_date(y,12,31), make_date(y,12,15)
  from anios
  union all
  select y, 'cts', 'cts_may',
         make_date(y-1,11,1), make_date(y,4,30), make_date(y,5,15)
  from anios
  union all
  select y, 'cts', 'cts_nov',
         make_date(y,5,1), make_date(y,10,31), make_date(y,11,15)
  from anios
),
ventanas_cerradas as (
  select v.*
  from ventanas v
  where v.pago < '2026-09-01'
),
movimiento_de_la_ventana as (
  select vc.*, p.id as persona_id, p.nombres, p.apellidos,
         m.monto as monto_pagado_planilla, m.id as movimiento_id
  from ventanas_cerradas vc
  join personas p on true
  join periodos_planilla pp on vc.pago between pp.fecha_ini and pp.fecha_fin
  join movimientos_planilla m
    on m.periodo_id = pp.id and m.persona_id = p.id and m.categoria = vc.categoria
),
cambio_de_sueldo_adentro as (
  select mv.*,
         a.salario_mensual_soles as sueldo_nuevo,
         a.vigente_desde as sueldo_nuevo_desde,
         (select a2.salario_mensual_soles
            from asignaciones_salario a2
           where a2.persona_id = mv.persona_id
             and a2.vigente_desde < a.vigente_desde
           order by a2.vigente_desde desc limit 1) as sueldo_anterior
  from movimiento_de_la_ventana mv
  join asignaciones_salario a
    on a.persona_id = mv.persona_id
   and a.vigente_desde > mv.ini    -- el cambio cae DENTRO, no en el borde de inicio
   and a.vigente_desde <= mv.fin
)
select
  (nombres || ' ' || apellidos) as persona,
  categoria, ref as ventana, ini as ventana_ini, fin as ventana_fin, pago as fecha_pago,
  sueldo_anterior, sueldo_nuevo, sueldo_nuevo_desde,
  monto_pagado_planilla,
  movimiento_id
from cambio_de_sueldo_adentro
where sueldo_anterior is not null            -- hubo un sueldo antes: es un AUMENTO/cambio real, no el primero de su historia
  and sueldo_anterior <> sueldo_nuevo         -- descarta reasignaciones sin cambio de monto (ej. solo cambia base_provision en otra fila)
order by fecha_pago, persona;
