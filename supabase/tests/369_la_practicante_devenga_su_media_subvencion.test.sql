-- ============================================================================
-- 369_la_practicante_devenga_su_media_subvencion.test.sql
-- ============================================================================
-- Migración 0465. Una practicante devenga los dos pagos que la Ley 28518
-- (art. 42) le da y que hasta hoy no existían en ninguna pantalla: media
-- subvención por cada 6 meses continuos, y 15 días de descanso al cumplir 12
-- meses — que se pagan aunque el convenio termine sin gozarlos.
--
-- LO QUE DEFIENDE, EN ESTE ORDEN:
--   1. la practicante SALE, con su media subvención prorrateada dentro del
--      semestre en curso y el próximo hito en la fecha correcta;
--   2. el descanso se acumula mes a mes y SATURA en media subvención: pasado
--      el año no sigue creciendo;
--   3. lo anotado en el libro se RESTA — es lo que evita pagar dos veces;
--   4. sin tramo de subvención cargado, todo en cero y `sin_subvencion` en
--      true: un cero que avisa, no un cero mudo (la lección de la 0365);
--   5. quien no es practicante NO sale de esta función, y —lo más importante—
--      una practicante SIGUE sin devengar gratificación, CTS ni vacaciones en
--      fn_provisiones. Esta migración no le abre la puerta a esos tres;
--   6. el libro acepta las dos ventanas nuevas y sigue rechazando una
--      inventada.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000369000', 'Z369', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000369001', 'SeisAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000369000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000369009', '2025-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  -- Ingresó el 01/01/2026. Al 01/04/2026 lleva 3 de los 6 meses del primer
  -- semestre: media subvención a mitad de camino.
  ('00000000-0000-0000-0000-000000369002', 'SeisPracticante', 'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', '2026-01-01', 'practicante'),
  -- Practicante sin ninguna asignación de subvención cargada.
  ('00000000-0000-0000-0000-000000369003', 'SeisSinTramo', 'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', '2026-01-01', 'practicante'),
  -- Planilla de siempre: no debe salir en esta función, y sus beneficios no
  -- se mueven.
  ('00000000-0000-0000-0000-000000369004', 'SeisPlanilla', 'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', '2025-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000369002', 'colibri', 1130, '2026-01-01'),
  ('00000000-0000-0000-0000-000000369004', 'colibri', 1300, '2025-01-01');

-- Quien lee es el admin del laboratorio (fn_es_admin_o_lider mira el JWT).
-- `request.jwt.claim.sub`, en singular: es la forma que usan la 291 y la 338,
-- y la que lee fn_persona_actual_id.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000369009', true);

-- ── 1 · La media subvención se acumula dentro del semestre en curso ─────────
-- Del 01/01 al 01/04 corrieron 90 de los 181 días del semestre 01/01→01/07.
-- 1130 × 0.5 × 90/181 = 280.94
select is(
  (select round((e ->> 'media_sub_saldo')::numeric, 2)
     from jsonb_array_elements(fn_subvenciones_practicante('2026-04-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369002'),
  280.94::numeric,
  'MEDIA SUBVENCION · a mitad del semestre lleva devengada la mitad, no cero ni todo');

select is(
  (select e ->> 'proximo_hito'
     from jsonb_array_elements(fn_subvenciones_practicante('2026-04-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369002'),
  '2026-07-01',
  'MEDIA SUBVENCION · el próximo hito son los 6 meses de su convenio, no el 15 de un mes fijo');

-- Al cumplirse el semestre está completa: 1130 × 0.5 = 565.00
select is(
  (select round((e ->> 'media_sub_saldo')::numeric, 2)
     from jsonb_array_elements(fn_subvenciones_practicante('2026-07-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369002'),
  565.00::numeric,
  'MEDIA SUBVENCION · al cumplir los 6 meses la reserva está completa (S/565 sobre S/1.130)');

-- ── 2 · El descanso se acumula y satura al año ──────────────────────────────
-- Al 01/07/2026 lleva 181 de 365 días: 1130 × 0.5 × 181/365 = 280.18
select is(
  (select round((e ->> 'descanso_saldo')::numeric, 2)
     from jsonb_array_elements(fn_subvenciones_practicante('2026-07-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369002'),
  280.18::numeric,
  'DESCANSO · se acumula mes a mes desde el ingreso, no aparece de golpe al año');

select is(
  (select round((e ->> 'descanso_saldo')::numeric, 2)
     from jsonb_array_elements(fn_subvenciones_practicante('2027-06-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369002'),
  565.00::numeric,
  'DESCANSO · satura en media subvención: pasado el año no sigue creciendo');

select is(
  (select (e ->> 'descanso_ganado')::boolean
     from jsonb_array_elements(fn_subvenciones_practicante('2026-07-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369002'),
  false,
  'DESCANSO · antes de los 12 meses está devengado pero NO ganado: si el convenio se corta, no se paga');

-- Y el hito que nadie pagó NO se borra al empezar el siguiente semestre: al
-- 01/10/2026 lleva un hito cumplido (S/565) más 92 de los 184 días del
-- segundo semestre (S/282.50) = S/847.50. Sin esto, el 01/07 la pantalla
-- habría mostrado cero el mismo día en que había que pagar — el defecto que
-- el laboratorio cazó en el primer intento de esta función.
select is(
  (select round((e ->> 'media_sub_saldo')::numeric, 2)
     from jsonb_array_elements(fn_subvenciones_practicante('2026-10-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369002'),
  847.50::numeric,
  'MEDIA SUBVENCION · un hito cumplido y sin pagar sigue sumando en el semestre siguiente');

-- ── 3 · Lo pagado se resta ──────────────────────────────────────────────────
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
values ('00000000-0000-0000-0000-000000369002', 'subvencion_semestral', 2026, 300.00,
        '2026-07-01', 'transferencia');

select is(
  (select round((e ->> 'media_sub_saldo')::numeric, 2)
     from jsonb_array_elements(fn_subvenciones_practicante('2026-07-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369002'),
  265.00::numeric,
  'LIBRO · un pago anotado baja el saldo (565 − 300), que es lo que evita pagar dos veces');

-- ── 4 · Sin tramo de subvención: cero que avisa ─────────────────────────────
select is(
  (select (e ->> 'sin_subvencion')::boolean
     from jsonb_array_elements(fn_subvenciones_practicante('2026-07-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369003'),
  true,
  'SIN TRAMO · la fila sale en cero pero lo DICE, en vez de un cero mudo');

-- ── 5 · No se le abre la puerta a los otros tres beneficios ─────────────────
select is(
  (select count(*)::int
     from jsonb_array_elements(fn_subvenciones_practicante('2026-07-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369004'),
  0,
  'ALCANCE · quien está en planilla no sale de esta función: es solo para modalidad formativa');

select is(
  (select round(((e ->> 'grati_total')::numeric + (e ->> 'cts_total')::numeric + (e ->> 'vac')::numeric), 2)
     from jsonb_array_elements(fn_provisiones('2026-07-01') -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000369002'),
  0.00::numeric,
  'LEY · la practicante SIGUE sin devengar gratificación, CTS ni vacaciones (art. 47)');

-- ── 6 · El libro acepta las dos nuevas y rechaza una inventada ──────────────
select throws_ok(
  $$ insert into desembolsos_beneficios
       (persona_id, ventana, anio, monto, fecha_pago, origen)
     values ('00000000-0000-0000-0000-000000369002', 'aguinaldo', 2026, 500,
             '2026-07-01', 'transferencia') $$,
  null, null,
  'LIBRO · una ventana inventada se sigue rechazando, aunque ahora sean siete');

select * from finish();
rollback;
