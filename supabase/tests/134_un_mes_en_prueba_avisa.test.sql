-- ============================================================================
-- 134_un_mes_en_prueba_avisa.test.sql
-- ============================================================================
-- La decisión de que `prueba` no devengue beneficios (0085, 26/07/2026) se tomó
-- con un argumento que tiene fecha de caducidad exacta: «por los mínimos legales
-- casi siempre daría cero de todas formas». Es cierto — las tres funciones de
-- truncas exigen un mes de servicios por su cuenta.
--
-- Deja de ser cierto al día siguiente de cumplir el mes. Este archivo fija las
-- dos mitades:
--
--   · por debajo del mes, la etiqueta no le quita NADA a nadie: devengue o no,
--     las truncas dan cero. Eso es lo que hacía inocua la decisión;
--   · pasado el mes, el aviso aparece — porque desde ahí el sistema estaría
--     diciendo que no devenga algo que legalmente sí devenga.
--
-- Y una que protege la decisión de Felipe: esto AVISA, no cambia la regla. Si
-- alguien la revierte por su cuenta, la última aserción cae.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ab00', 'ZZPRU', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ab01', 'AdminPru', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ab00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ab09', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ab09', true);

-- Dos en prueba: una recién entrada, otra que ya pasó el mes. Las fechas se
-- construyen desde hoy para que la prueba no caduque con el calendario.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000aba1', 'PruRecien', 'Laboratorio',
   '00000000-0000-0000-0000-00000000ab00', 'test-hash', (fn_hoy_lima() - 10), 'prueba'),
  ('00000000-0000-0000-0000-00000000aba2', 'PruVieja',  'Laboratorio',
   '00000000-0000-0000-0000-00000000ab00', 'test-hash', (fn_hoy_lima() - 45), 'prueba');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'cayla', 1500.00, (fn_hoy_lima() - 45)
from unnest(array['00000000-0000-0000-0000-00000000aba1'::uuid,
                  '00000000-0000-0000-0000-00000000aba2'::uuid]) p;


-- ── Las dos aparecen, pero solo una avisa ──────────────────────────────────
select is(
  (select count(*)::int from fn_avisos_vinculo()),
  2,
  'LISTA · las dos personas en prueba aparecen: se ve desde cuándo lleva cada una');

select ok(
  not (select ya_devenga from fn_avisos_vinculo()
        where persona_id = '00000000-0000-0000-0000-00000000aba1'),
  'DIEZ DÍAS · la recién entrada no avisa: por debajo del mes la etiqueta no cuesta nada');

select ok(
  (select ya_devenga from fn_avisos_vinculo()
    where persona_id = '00000000-0000-0000-0000-00000000aba2'),
  'CUARENTA Y CINCO DÍAS · esta sí: pasó el mes y el sistema deja de decir la verdad');

select ok(
  (select aviso from fn_avisos_vinculo()
    where persona_id = '00000000-0000-0000-0000-00000000aba2') like '%Pásala a «planilla»%',
  'AVISO · dice qué hacer, no solo que algo pasa');

select is(
  (select cumple_el_mes from fn_avisos_vinculo()
    where persona_id = '00000000-0000-0000-0000-00000000aba1'),
  (fn_hoy_lima() - 10 + interval '1 month')::date,
  'FECHA · el mes se cuenta desde el ingreso, no desde el primer marcaje');


-- ── Por qué la decisión era inocua por debajo del mes ──────────────────────
-- Esto es lo que la sostenía: aunque `prueba` devengara, las truncas darían cero
-- igual. Si alguien lo pone en duda, acá está medido.
select is(
  (fn_cts_trunca('00000000-0000-0000-0000-00000000aba1', fn_hoy_lima())->>'monto')::numeric,
  0::numeric,
  'INOCUA · con diez días, la CTS trunca es cero de todas formas');

select is(
  (fn_vacaciones_truncas('00000000-0000-0000-0000-00000000aba1', fn_hoy_lima())->>'monto')::numeric,
  0::numeric,
  'INOCUA · y las vacaciones truncas también');


-- ── Y esto avisa, no revierte ──────────────────────────────────────────────
-- La decisión del 26/07 sigue en pie. Si alguien la cambia por su cuenta, acá
-- se entera — no porque cambiarla esté mal, sino porque tiene que ser explícito.
select ok(
  not fn_devenga_beneficios('prueba'),
  'NO REVIERTE · «prueba» sigue sin devengar: la 0169 hace visible la decisión, no la cambia');

select * from finish();
rollback;
