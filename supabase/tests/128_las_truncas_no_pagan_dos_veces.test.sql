-- ============================================================================
-- 128_las_truncas_no_pagan_dos_veces.test.sql
-- ============================================================================
-- El caso que esto cierra, con su cifra:
--
--   El 15 de mayo se depositó CTS por PLAME a cinco personas. Si una de ellas
--   cesa en agosto, `fn_cts_trunca` calculaba la ventana de mayo a octubre
--   entera y la pagaba — sin mirar si ya había salido algo del banco. La 0158
--   arregló ese doble conteo del lado de las PROVISIONES; del lado de la
--   LIQUIDACIÓN seguía abierto, y ahí no se infla un pronóstico: se paga.
--
-- Y la trampa que este archivo fija para que nadie la vuelva a pisar: la ventana
-- se nombra por el mes del DEPÓSITO, no por el inicio del devengo.
--
--     cts_may  · devenga nov (Y-1) – abr (Y) · se paga el 15 may (Y)
--     cts_nov  · devenga may (Y) – oct (Y)   · se paga el 15 nov (Y)
--
--   Un cese en agosto cae en la ventana que arranca el 1 de mayo, o sea `cts_nov`
--   del mismo año. Descontarle el depósito de `cts_may` sería restarle plata que
--   corresponde a otro periodo — el error simétrico, y peor: se paga de MENOS a
--   quien ya se fue y no va a reclamar.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000bc00', 'ZZTRU', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000bc01', 'AdminTru', 'Laboratorio',
        '00000000-0000-0000-0000-00000000bc00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000bc09', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000bc09', true);

-- Dos personas idénticas: a una se le depositó CTS, a la otra no.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000bca1', 'TruSinDeposito', 'Laboratorio', '00000000-0000-0000-0000-00000000bc00', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-00000000bca2', 'TruConDeposito', 'Laboratorio', '00000000-0000-0000-0000-00000000bc00', 'test-hash', '2024-01-02', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'cayla', 1500.00, '2024-01-02'
from unnest(array['00000000-0000-0000-0000-00000000bca1'::uuid,
                  '00000000-0000-0000-0000-00000000bca2'::uuid]) p;


-- ── El mapa de ventanas, que es donde se paga doble por adivinar ───────────
select is(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca1', '2026-08-20')->>'ventana'),
  'cts_nov',
  'VENTANA · un cese en agosto cae en la que se deposita en NOVIEMBRE, no en la de mayo');

select is(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca1', '2026-08-20')->>'anio_ventana')::int,
  2026,
  'VENTANA · y es la del mismo año');

select is(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca1', '2026-12-20')->>'ventana'),
  'cts_may',
  'VENTANA · un cese en diciembre cae en la que se deposita en mayo…');

select is(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca1', '2026-12-20')->>'anio_ventana')::int,
  2027,
  'VENTANA · …del año SIGUIENTE, que es el error simétrico y el más fácil de cometer');


-- ── Sin depósito, todo sigue como antes ───────────────────────────────────
select ok(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca1', '2026-08-20')->>'monto')::numeric > 0,
  'SIN DEPÓSITO · la CTS trunca se paga completa: la 0163 no rompió lo que funcionaba');

select is(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca1', '2026-08-20')->>'ya_depositado')::numeric,
  0.00::numeric,
  'SIN DEPÓSITO · y el descuento es cero');


-- ── Con depósito, se resta ────────────────────────────────────────────────
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
values ('00000000-0000-0000-0000-00000000bca2', 'cts_nov', 2026, 200.00, '2026-08-01', 'transferencia');

select is(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca2', '2026-08-20')->>'ya_depositado')::numeric,
  200.00::numeric,
  'CON DEPÓSITO · la función ve los S/200 que ya salieron del banco');

select is(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca2', '2026-08-20')->>'monto')::numeric,
  round((fn_cts_trunca('00000000-0000-0000-0000-00000000bca1', '2026-08-20')->>'monto')::numeric - 200.00, 2),
  'CON DEPÓSITO · y paga exactamente S/200 menos que su gemela sin depósito');


-- ── El depósito de OTRA ventana no se toca ────────────────────────────────
-- Restarle a un cese de agosto el depósito de mayo sería quitarle plata de un
-- periodo que ya se cerró. Se paga de menos a quien ya se fue, y no va a reclamar.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
values ('00000000-0000-0000-0000-00000000bca2', 'cts_may', 2026, 900.00, '2026-05-15', 'plame');

select is(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca2', '2026-08-20')->>'ya_depositado')::numeric,
  200.00::numeric,
  'OTRA VENTANA · el depósito de mayo NO se resta de la ventana de noviembre');


-- ── Y si se depositó de más, el negativo se ve ────────────────────────────
-- Decisión de Felipe en la 0158, heredada acá: preferir que se vea a que se
-- disimule. En una liquidación un negativo significa que hay algo que descontar,
-- así que esconderlo en un cero sería pagar de más una segunda vez.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
values ('00000000-0000-0000-0000-00000000bca2', 'cts_nov', 2026, 5000.00, '2026-08-02', 'otro');

select ok(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000bca2', '2026-08-20')->>'monto')::numeric < 0,
  'DE MÁS · si se depositó por encima de lo devengado, el monto sale en negativo');

select * from finish();
rollback;
