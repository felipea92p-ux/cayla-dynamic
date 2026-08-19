-- ============================================================================
-- 209_la_base_declarada_dice_desde_que_contrato_se_disparo.test.sql
-- fn_fijar_base_declarada, el parámetro p_nota_extra (migración 0271)
-- ============================================================================
-- La 111 ya blinda todo el comportamiento original de la 0128. Esto solo
-- prueba lo que agrega la 0271: que sigue funcionando con 4 argumentos
-- (compatibilidad) y que el 5º se anexa a la nota cuando se manda.
--
-- Y la razón de que exista esta prueba y no solo la comprobación manual: al
-- escribir la 0271, un `create or replace` con el parámetro nuevo al final NO
-- reemplazó la función de 4 argumentos — creó una SEGUNDA función sobrecargada
-- y dejó las dos a la vez, con la vieja sin el rastro. Se detectó recién al
-- correr `\df` contra Postgres local. Sin una prueba que fije este
-- comportamiento, un futuro `create or replace` sin el `drop` delante repite
-- exactamente el mismo error en silencio.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ce', 'ZZNOTA', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000ce00', 'NotaAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ce', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000ce9900');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000ce9900', true);

insert into personas
  (id, nombres, apellidos, sede_base_id, pin_hash, sueldo_base_legal, tipo_vinculo, estado)
values
  ('00000000-0000-0000-0000-00000000ce01', 'NotaA', 'Laboratorio', '00000000-0000-0000-0000-0000000000ce', 'test-hash', 1450.00, 'planilla', 'activo'),
  ('00000000-0000-0000-0000-00000000ce02', 'NotaB', 'Laboratorio', '00000000-0000-0000-0000-0000000000ce', 'test-hash', 1450.00, 'planilla', 'activo');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000000ce01', 'aurora', 1450.00, '2026-01-01'),
  ('00000000-0000-0000-0000-00000000ce02', 'aurora', 1450.00, '2026-01-01');

-- ── 1 · Sin p_nota_extra, 4 argumentos, exactamente como antes de la 0271 ───
select * from fn_fijar_base_declarada(
  'aurora', 1360.00, '2026-09-01',
  array['00000000-0000-0000-0000-00000000ce02']::uuid[]);

select ok(
  (select a.nota from asignaciones_salario a
    where a.persona_id = '00000000-0000-0000-0000-00000000ce01' and a.vigente_hasta is null)
  like 'Base declarada del rango aurora%',
  'Llamar con 4 argumentos sigue escribiendo la nota de siempre, sin cambio de comportamiento');

select isnt(
  (select a.nota from asignaciones_salario a
    where a.persona_id = '00000000-0000-0000-0000-00000000ce01' and a.vigente_hasta is null),
  null,
  'Y la nota no queda vacía ni trunca por el parámetro nuevo con default');

-- ── 2 · Con p_nota_extra, se anexa al final separado por " | " ─────────────
select * from fn_fijar_base_declarada(
  'aurora', 1200.00, '2026-10-01',
  array['00000000-0000-0000-0000-00000000ce02']::uuid[],
  'Aplicado desde /admin/contratos al registrar el contrato de NotaA, firmado el 2026-09-15.');

select ok(
  (select a.nota from asignaciones_salario a
    where a.persona_id = '00000000-0000-0000-0000-00000000ce01' and a.vigente_hasta is null)
  like '%| Aplicado desde /admin/contratos al registrar el contrato de NotaA, firmado el 2026-09-15.',
  'Con p_nota_extra, el rastro del contrato queda anexado al final de la nota de siempre');

-- ── 3 · Una nota extra en blanco no deja un separador colgando ─────────────
select * from fn_fijar_base_declarada(
  'aurora', 1150.00, '2026-11-01',
  array['00000000-0000-0000-0000-00000000ce02']::uuid[],
  '   ');

select ok(
  (select a.nota from asignaciones_salario a
    where a.persona_id = '00000000-0000-0000-0000-00000000ce01' and a.vigente_hasta is null)
  not like '%| %',
  'p_nota_extra en blanco (o solo espacios) no agrega un separador vacío');

select * from finish();
rollback;
