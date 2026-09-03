-- ============================================================================
-- 272_un_adelanto_de_beneficio_no_se_vuelve_a_calcular_solo.test.sql
-- ============================================================================
-- Migración 0343. Dos mitades:
--
--   A · fn_registrar_desembolso es la puerta nueva a desembolsos_beneficios:
--       valida cada CHECK con su propio mensaje, y solo admin/líder puede
--       usarla.
--   B · fn_grati_trunca_bruta reconoce un adelanto de mitad de semestre
--       cargado como bono categoria='gratificacion' en movimientos_planilla
--       — pero SOLO si el periodo del bono EMPIEZA dentro del semestre que se
--       evalúa. El caso de Paola Cahuana (cese 28/08, adelanto de S/102 en
--       agosto) es justo lo que esto arregla: sin el fix, fn_grati_trunca la
--       vuelve a calcular entera.
--
-- LA ASERCIÓN QUE MÁS IMPORTA NO ES LA QUE PRUEBA EL ARREGLO — es la que
-- prueba que el arreglo no reabre el defecto que la 0289 ya había cerrado
-- (aserción 5): el pago normal de enero-junio, depositado el 15 de julio en
-- un periodo que EMPIEZA el 29 de junio, no se puede colar como si fuera
-- también un adelanto de julio-diciembre.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000272000', 'ZZ272', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000002720ad', 'OnceAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000272000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000002720ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000272001','OnceConAdelanto','Laboratorio','00000000-0000-0000-0000-000000272000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000272002','OnceSinAdelanto','Laboratorio','00000000-0000-0000-0000-000000272000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000272003','OnceTraslape',   'Laboratorio','00000000-0000-0000-0000-000000272000','test-hash','2024-01-01','planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950.00, '2024-01-01'
from personas where apellidos = 'Laboratorio' and nombres like 'Once%' and nombres <> 'OnceAdmin';

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '15:30', array[1,2,3,4,5]
from personas where apellidos = 'Laboratorio' and nombres like 'Once%' and nombres <> 'OnceAdmin';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002720ff', true);

-- ── A · LA PUERTA ────────────────────────────────────────────────────────────

-- 1 · Guard: sin sesión de admin/líder, se niega.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
select throws_ok(
  $$ select fn_registrar_desembolso('00000000-0000-0000-0000-000000272001','grati_s2',2026,100,'2026-08-15','transferencia',null) $$,
  'Solo un administrador o líder puede registrar un desembolso.',
  'GUARD · sin sesión de admin/líder, fn_registrar_desembolso se niega');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002720ff', true);

-- 2 · Cada CHECK de la tabla, con su propio mensaje.
select throws_like(
  $$ select fn_registrar_desembolso('00000000-0000-0000-0000-000000272001','no_existe',2026,100,'2026-08-15','transferencia',null) $$,
  'Ventana inválida%',
  'VALIDA · una ventana que no es ninguna de las cinco, mensaje propio');
select throws_like(
  $$ select fn_registrar_desembolso('00000000-0000-0000-0000-000000272001','grati_s2',2026,-5,'2026-08-15','transferencia',null) $$,
  'El monto tiene que ser mayor a 0%',
  'VALIDA · un monto en cero o negativo, mensaje propio');

-- 3 · Con datos válidos, inserta y devuelve el id.
select isnt(
  (select fn_registrar_desembolso('00000000-0000-0000-0000-000000272001','grati_s2',2026,102.63,'2026-08-29','transferencia','adelanto por cese')),
  null,
  'INSERTA · con datos válidos, fn_registrar_desembolso devuelve el id de la fila');

-- ── B · fn_grati_trunca_bruta RECONOCE EL ADELANTO DE MITAD DE SEMESTRE ─────

-- Movimiento correctamente etiquetado ('gratificacion'), en un periodo que
-- EMPIEZA dentro del semestre julio-diciembre (29/07), para quien cesa antes
-- de la fecha legal de pago (28/08, mucho antes del 15/12).
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000272097', '2026-07-29', '2026-08-28', 'abierto');

insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria)
values ('00000000-0000-0000-0000-000000272097', '00000000-0000-0000-0000-000000272001',
        'bono', 'Gratificacion truncada de agosto', 102.63, 'gratificacion');

-- 4 · Con el adelanto correctamente etiquetado, la liquidación NO la vuelve a calcular.
select is(
  (fn_grati_trunca('00000000-0000-0000-0000-000000272001','2026-08-28')->>'monto')::numeric,
  0::numeric,
  'ADELANTO · con categoria=gratificacion dentro del semestre, no se recalcula (era el caso de Paola)');

-- 5 · Y quien NO tiene ningún adelanto sigue cobrando su trunco, como siempre.
select cmp_ok(
  (fn_grati_trunca('00000000-0000-0000-0000-000000272002','2026-08-28')->>'monto')::numeric,
  '>', 0::numeric,
  'SIN ADELANTO · quien no tiene nada cargado sigue cobrando su trunco de julio-agosto');

-- ── EL TRASLAPE QUE NO SE PUEDE COLAR ───────────────────────────────────────
-- OnceTraslape: se le paga su gratificación de enero-junio DE VERDAD, el
-- 15/07, en un periodo 29/06→28/07 —EMPIEZA antes del semestre julio-
-- diciembre—. Si el fix no exigiera fecha_ini >= v_sem, este mismo movimiento
-- se leería también como "adelanto de julio-diciembre" y le robaría su
-- trunco de julio al cesar en agosto: el defecto que la 0289 ya había
-- cerrado, reabierto por otra puerta.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000272098', '2026-06-29', '2026-07-28', 'pagado');

insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria)
values ('00000000-0000-0000-0000-000000272098', '00000000-0000-0000-0000-000000272003',
        'bono', 'Gratificacion enero-junio 2026', 975.00, 'gratificacion');

-- 6 · La de enero-junio, correctamente reconocida como ya cobrada (no se repite).
select cmp_ok(
  (fn_grati_trunca_bruta('00000000-0000-0000-0000-000000272003','2026-08-20')->>'semestres_no_cobrados')::jsonb ? '01/2026',
  '=', false,
  'SIN TRASLAPE · enero-junio queda marcada como cobrada, no aparece en semestres_no_cobrados');

-- 7 · Y julio-diciembre SIGUE sin marcar como cobrada — el trunco de julio y agosto se debe.
select is(
  (fn_grati_trunca_bruta('00000000-0000-0000-0000-000000272003','2026-08-20')->>'semestres_no_cobrados')::jsonb ? '07/2026',
  true,
  'SIN TRASLAPE · julio-diciembre SÍ sigue en semestres_no_cobrados: el pago de enero no la cubre');

-- 8 · Y el monto de esa persona es positivo — el trunco de julio-agosto no desapareció.
select cmp_ok(
  (fn_grati_trunca('00000000-0000-0000-0000-000000272003','2026-08-20')->>'monto')::numeric,
  '>', 0::numeric,
  'SIN TRASLAPE · el pago de enero no le roba su trunco de julio-agosto');

select * from finish();
rollback;
