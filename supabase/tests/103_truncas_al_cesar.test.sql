-- ============================================================================
-- 103_truncas_al_cesar.test.sql
-- ============================================================================
-- La 0087 calcula lo que se le debe a quien se va: gratificación, CTS y
-- vacaciones truncas. Hasta hoy no tenía NI UNA prueba — ni las tres funciones
-- ni la aritmética que las sostiene. Es la matemática con la que se le dice a
-- una persona cuánto se le debe el día que se va, y la ley da 48 horas desde el
-- cese para pagarlo (art. 4 D.S. 001-97-TR).
--
-- CÓMO SE ESCRIBIERON LOS NÚMEROS ESPERADOS
--
-- A mano, desde la norma, ANTES de correr nada. No se leyó el código para ver
-- qué devuelve y escribir eso: así una prueba solo certifica que la función
-- hace lo que hace, no que hace lo correcto.
--
-- El riesgo real que vigilan estas pruebas es UNO, y es caro: **el régimen MYPE
-- pequeña empresa paga la MITAD que el régimen general en los tres conceptos.**
-- Las fórmulas del régimen general son las que salen en la primera página de
-- cualquier búsqueda. Copiarlas paga exactamente el doble, y en una liquidación
-- eso son cientos de soles por persona que nadie devuelve.
--
--   gratificación  media remuneración por semestre  (general: una completa)
--   CTS            15 remuneraciones diarias al año (general: 30)
--   vacaciones     15 días al año                   (general: 30)
--
-- Persona de laboratorio: sueldo S/2 400, sin hijos (asignación 0), sin bonos
-- (variables 0), ingreso el 01/01/2024. Remuneración computable = S/2 400.
-- Números redondos a propósito: una prueba cuyo resultado esperado no se puede
-- comprobar mentalmente no prueba nada.
-- ============================================================================
begin;
select plan(19);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-0000000000c0', 'ZZTRU', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000000c1', 'TruncoAdmin', 'Lab', '00000000-0000-0000-0000-0000000000c0', 'admin', 'x', '00000000-0000-0000-0000-0000000000cf', '2024-01-01', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000000c2', 'TruncoCesa',   'Lab', '00000000-0000-0000-0000-0000000000c0', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000000c3', 'TruncoCobro',  'Lab', '00000000-0000-0000-0000-0000000000c0', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000000c4', 'TruncoPrueba', 'Lab', '00000000-0000-0000-0000-0000000000c0', 'x', '2024-01-01', 'prueba'),
  ('00000000-0000-0000-0000-0000000000c5', 'TruncoNueva',  'Lab', '00000000-0000-0000-0000-0000000000c0', 'x', '2026-06-20', 'planilla'),
  ('00000000-0000-0000-0000-0000000000c6', 'TruncoGozo',   'Lab', '00000000-0000-0000-0000-0000000000c0', 'x', '2024-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'colibri', 2400, '2024-01-01'
from unnest(array['00000000-0000-0000-0000-0000000000c2'::uuid,
                  '00000000-0000-0000-0000-0000000000c3'::uuid,
                  '00000000-0000-0000-0000-0000000000c4'::uuid,
                  '00000000-0000-0000-0000-0000000000c6'::uuid]) p;
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000c5', 'colibri', 2400, '2026-06-20');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000cf', true);


-- ════════════════════════════════════════════════════════════════════════════
-- La aritmética de la que dependen las tres fórmulas
-- ════════════════════════════════════════════════════════════════════════════
-- Un mes cuenta solo si está completo, del 1 al último día. Si las tres
-- fórmulas contaran distinto, la misma liquidación daría tres antigüedades.

-- Del 01/05 al 30/06: mayo y junio completos, ningún día suelto.
select is((select meses from fn_meses_y_dias('2026-05-01', '2026-06-30')),
          2, 'MESES · dos meses calendario completos cuentan dos');
select is((select dias from fn_meses_y_dias('2026-05-01', '2026-06-30')),
          0, 'MESES · y no dejan días sueltos');

-- Del 10/05 al 30/06: mayo NO cuenta como mes completo porque arranca el 10;
-- junio sí. Los 22 días del 10 al 31 de mayo no se pierden: van como días
-- sueltos, que en CTS se pagan a razón de base/720 cada uno.
select is((select meses from fn_meses_y_dias('2026-05-10', '2026-06-30')),
          1, 'MESES · empezar a mitad de mes hace que ese mes no cuente como completo');
select is((select dias from fn_meses_y_dias('2026-05-10', '2026-06-30')),
          22, 'MESES · y los días de arranque quedan contados aparte, no perdidos');


-- ════════════════════════════════════════════════════════════════════════════
-- Gratificación trunca — media remuneración por semestre
-- ════════════════════════════════════════════════════════════════════════════
-- Cese el 30/06/2026 sin haber cobrado ninguna gratificación. Se le deben los
-- DOS semestres pendientes: julio–diciembre 2025 (6 meses) y enero–junio 2026
-- (6 meses) = 12 meses completos.
--
--   grati = (2400 / 2) / 6 × 12 = 200 × 12 = S/2 400.00
--   bonificación extraordinaria 9 % (Ley 30334) = S/216.00
--   total = S/2 616.00
--
-- Si alguien copiara la fórmula del régimen GENERAL —una remuneración completa
-- por semestre— saldrían S/4 800 + 9 %. El doble.

select is((fn_grati_trunca('00000000-0000-0000-0000-0000000000c2', '2026-06-30')->>'meses_completos')::int,
          12, 'GRATI · dos semestres sin cobrar son doce meses, no seis');

select is((fn_grati_trunca('00000000-0000-0000-0000-0000000000c2', '2026-06-30')->>'gratificacion')::numeric,
          2400.00::numeric, 'GRATI · media remuneración por semestre — el doble sería el régimen general');

select is((fn_grati_trunca('00000000-0000-0000-0000-0000000000c2', '2026-06-30')->>'bonificacion_extraordinaria_9pct')::numeric,
          216.00::numeric, 'GRATI · más el 9 % de bonificación extraordinaria (Ley 30334)');

select is((fn_grati_trunca('00000000-0000-0000-0000-0000000000c2', '2026-06-30')->>'monto')::numeric,
          2616.00::numeric, 'GRATI · el total que se le debe');

-- El error que la 0087 dice haber encontrado y corregido: si ya cobró la
-- gratificación de julio–diciembre 2025 (pagada en diciembre), ese semestre NO
-- se vuelve a pagar. Solo quedan los 6 meses de enero–junio 2026.
--   grati = 200 × 6 = S/1 200.00 · 9 % = S/108.00 · total = S/1 308.00
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at)
values ('cc000000-0000-0000-0000-000000000103', '2025-12-01', '2025-12-31', 'pagado', '2025-12-31');
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria)
values ('cc000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-0000000000c3',
        'bono', 'Gratificacion julio-diciembre 2025', 1200, 'gratificacion');

select is((fn_grati_trunca('00000000-0000-0000-0000-0000000000c3', '2026-06-30')->>'meses_completos')::int,
          6, 'GRATI · un semestre ya cobrado no se vuelve a contar');

select is((fn_grati_trunca('00000000-0000-0000-0000-0000000000c3', '2026-06-30')->>'monto')::numeric,
          1308.00::numeric, 'GRATI · y solo se paga el semestre pendiente');


-- ════════════════════════════════════════════════════════════════════════════
-- CTS trunca — 15 remuneraciones diarias por año
-- ════════════════════════════════════════════════════════════════════════════
-- Cese el 30/06/2026. El periodo de CTS en curso arrancó el 01/05/2026
-- (depósito de noviembre), así que son 2 meses completos y 0 días.
--
--   base = RC 2 400 + sexto de gratificación
--   El sexto de una grati de MEDIA remuneración es sueldo/12 = S/200.00
--   (usar sueldo/6, que es el del régimen general, pagaría de más).
--   base = 2 600
--   CTS = 2 600 / 24 × 2 = S/216.67

select is((fn_cts_trunca('00000000-0000-0000-0000-0000000000c2', '2026-06-30')->>'sexto_de_gratificacion')::numeric,
          200.00::numeric, 'CTS · el sexto sale de una grati de media remuneración: sueldo/12, no sueldo/6');

select is((fn_cts_trunca('00000000-0000-0000-0000-0000000000c2', '2026-06-30')->>'base_de_calculo')::numeric,
          2600.00::numeric, 'CTS · la base es la remuneración computable más ese sexto');

select is((fn_cts_trunca('00000000-0000-0000-0000-0000000000c2', '2026-06-30')->>'monto')::numeric,
          216.67::numeric, 'CTS · dos meses del periodo en curso, a 15 remuneraciones diarias por año');

-- El espejo del régimen. La CTS no se acumula por año: se deposita dos veces al
-- año y cada periodo es de seis meses (noviembre–abril y mayo–octubre). Un cese
-- el 30/04/2026 cierra el periodo que arrancó el 01/11/2025: seis meses justos.
--
--   2 600 / 24 × 6 = S/650.00, que es base / 4 = 7.5 remuneraciones diarias.
--   Los dos periodos del año suman 1 300 = base / 2 = 15 remuneraciones diarias,
--   que es exactamente lo que manda el régimen de pequeña empresa. En régimen
--   general serían 30 y el resultado sería el doble.
--
-- (Esta aserción nació esperando 1 300 porque quien la escribió dio por hecho
-- que el periodo de CTS era anual. La función tenía razón y la expectativa no.
-- Queda escrito para que nadie vuelva a «corregir» la función hacia el error.)
select is((fn_cts_trunca('00000000-0000-0000-0000-0000000000c2', '2026-04-30')->>'monto')::numeric,
          650.00::numeric, 'CTS · un periodo completo son seis meses y vale base/4 — dos al año hacen los 15 días');


-- ════════════════════════════════════════════════════════════════════════════
-- Vacaciones truncas — 15 días por año
-- ════════════════════════════════════════════════════════════════════════════
-- Ingreso 01/01/2024, cese 30/06/2026. El último aniversario es el 01/01/2026,
-- así que el récord trunco va del 01/01/2026 al 30/06/2026: 6 meses completos.
--
--   días ganados = 15 × 6 / 12 = 7.5 días
--   monto = (2 400 / 2) × 7.5 / 15 = 1 200 × 0.5 = S/600.00
--
-- En régimen general serían 30 días al año: 15 días ganados y S/1 200. El doble.

select is((fn_vacaciones_truncas('00000000-0000-0000-0000-0000000000c2', '2026-06-30')->>'dias_ganados')::numeric,
          7.50::numeric, 'VACACIONES · medio año son 7.5 días — en régimen general serían 15');

select is((fn_vacaciones_truncas('00000000-0000-0000-0000-0000000000c2', '2026-06-30')->>'monto')::numeric,
          600.00::numeric, 'VACACIONES · y su valor a media remuneración por 15 días');

-- Lo ya gozado se descuenta: 5 días tomados dentro del récord dejan 2.5
-- pendientes → 1 200 × 2.5 / 15 = S/200.00
select fn_set_vacaciones('00000000-0000-0000-0000-0000000000c6', '2026-03-02', '2026-03-06', 'descanso');

select is((fn_vacaciones_truncas('00000000-0000-0000-0000-0000000000c6', '2026-06-30')->>'monto')::numeric,
          200.00::numeric, 'VACACIONES · los días ya gozados se descuentan de lo que se le debe');


-- ════════════════════════════════════════════════════════════════════════════
-- A quién NO le corresponde
-- ════════════════════════════════════════════════════════════════════════════
-- Quien está a prueba no devenga beneficios: pagarle una liquidación de
-- planilla sería inventarle un vínculo que no tiene.
select is((fn_grati_trunca('00000000-0000-0000-0000-0000000000c4', '2026-06-30')->>'aplica')::boolean,
          false, 'VÍNCULO · quien está a prueba no devenga gratificación trunca');

-- Menos de un mes íntegro de servicios: no hay derecho (art. 5.1 D.S. 005-2002-TR).
select is((fn_cts_trunca('00000000-0000-0000-0000-0000000000c5', '2026-06-30')->>'aplica')::boolean,
          false, 'MÍNIMO · con menos de un mes de servicios no corresponde CTS');

select * from finish();
rollback;
