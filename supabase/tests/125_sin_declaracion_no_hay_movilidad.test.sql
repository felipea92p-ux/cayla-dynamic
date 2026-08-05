-- ============================================================================
-- 125_sin_declaracion_no_hay_movilidad.test.sql
-- ============================================================================
-- Dos mitades que tienen que ser ciertas a la vez, y que se contradicen si una
-- se rompe:
--
--   APAGADO · mientras el candado no se encienda, la planilla paga exactamente
--     igual que antes. Esto es lo más importante del archivo: la 0159 se aplica
--     hoy en producción y NO puede mover un céntimo. Si esta mitad cae, 22
--     personas dejan de cobrar movilidad sin que nadie lo haya decidido.
--
--   ENCENDIDO · con el candado puesto, quien no tiene su declaración de ruta
--     firmada no devenga movilidad — ni quien se negó a firmar, porque el acta
--     documenta que se ofreció pero no sustituye al pacto.
--
-- Y una tercera que protege lo ya pagado: encender el candado con fecha de hoy
-- NO puede cambiar lo que se calculó para un periodo anterior. Es el mismo
-- blindaje que la 0115 le puso a la pensión.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000dc00', 'ZZDCL', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000dc01', 'AdminDcl', 'Laboratorio',
        '00000000-0000-0000-0000-00000000dc00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000dc09', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dc09', true);

delete from feriados where fecha between '2026-06-01' and '2026-06-30';

-- Tarifa de S/10 para la sede de laboratorio, desde antes del periodo.
insert into parametros_laborales (clave, valor, vigente_desde, sustento, sede_codigo)
values ('movilidad_diaria', 10.00, '2026-01-01', 'laboratorio', 'ZZDCL');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000dca1', 'DclFirmo',  'Laboratorio', '00000000-0000-0000-0000-00000000dc00', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000000dca2', 'DclNoTiene','Laboratorio', '00000000-0000-0000-0000-00000000dc00', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000000dca3', 'DclSeNego', 'Laboratorio', '00000000-0000-0000-0000-00000000dc00', 'test-hash', '2020-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'cayla', 1500.00, '2020-01-01'
from unnest(array['00000000-0000-0000-0000-00000000dca1'::uuid,
                  '00000000-0000-0000-0000-00000000dca2'::uuid,
                  '00000000-0000-0000-0000-00000000dca3'::uuid]) p;

-- Diez días marcados cada una: la movilidad esperada es 10 × S/10 = S/100.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 6.5, 'cerrada'
from unnest(array['00000000-0000-0000-0000-00000000dca1'::uuid,
                  '00000000-0000-0000-0000-00000000dca2'::uuid,
                  '00000000-0000-0000-0000-00000000dca3'::uuid]) p,
     generate_series('2026-06-01'::date, '2026-06-10'::date, interval '1 day') d;

-- Una firmó, otra no, la tercera se negó.
insert into documentos_firmados (alcance, persona_id, tipo, fecha_firma, monto_declarado, registrado_por)
values ('individual', '00000000-0000-0000-0000-00000000dca1', 'ruta', '2026-06-05', 10.00,
        '00000000-0000-0000-0000-00000000dc01');
insert into documentos_firmados (alcance, persona_id, tipo, fecha_firma, es_negativa, registrado_por)
values ('individual', '00000000-0000-0000-0000-00000000dca3', 'ruta', '2026-06-05', true,
        '00000000-0000-0000-0000-00000000dc01');


-- ── APAGADO · nadie deja de cobrar ─────────────────────────────────────────
create temp table _off as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2026-06-01'::date, '2026-06-30'::date) -> 'filas');

select is((select (fila->>'monto_movilidad')::numeric from _off
            where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000dca1'),
          100.00::numeric, 'APAGADO · quien firmó cobra S/100');

select is((select (fila->>'monto_movilidad')::numeric from _off
            where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000dca2'),
          100.00::numeric,
          'APAGADO · quien NO firmó cobra igual: la 0159 no mueve un céntimo hasta encenderse');

select is((select (fila->>'monto_movilidad')::numeric from _off
            where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000dca3'),
          100.00::numeric, 'APAGADO · y quien se negó, también');

select is((select (fila->>'movilidad_sin_declaracion') from _off
            where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000dca2'),
          'false', 'APAGADO · y no se marca a nadie como «sin declaración»');


-- ── ENCENDIDO desde antes del periodo ──────────────────────────────────────
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('movilidad_exige_declaracion', 1, '2026-05-01', 'prueba de laboratorio');

create temp table _on as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2026-06-01'::date, '2026-06-30'::date) -> 'filas');

select is((select (fila->>'monto_movilidad')::numeric from _on
            where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000dca1'),
          100.00::numeric, 'ENCENDIDO · quien firmó sigue cobrando sus S/100');

select is((select (fila->>'monto_movilidad')::numeric from _on
            where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000dca2'),
          0.00::numeric, 'ENCENDIDO · quien no firmó deja de devengar movilidad');

-- El acta documenta que se ofreció, y eso protege a la empresa. Lo que no hace
-- es sustituir al pacto: pagar igual sería pagar con un papel que dice por
-- escrito que la persona se negó.
select is((select (fila->>'monto_movilidad')::numeric from _on
            where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000dca3'),
          0.00::numeric, 'ENCENDIDO · una negativa registrada NO habilita el pago');

select is((select (fila->>'movilidad_sin_declaracion') from _on
            where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000dca2'),
          'true',
          'ENCENDIDO · y el cero se explica: la fila dice que el motivo es el papel que falta');


-- ── Lo ya pagado no se toca ────────────────────────────────────────────────
-- El candado rige desde el 2026-05-01, así que un periodo ANTERIOR a esa fecha
-- se sigue calculando como se calculó. Encender no reescribe el pasado.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000dca2', d::date, 6.5, 'cerrada'
from generate_series('2026-03-02'::date, '2026-03-11'::date, interval '1 day') d;

select is(
  (select (value->>'monto_movilidad')::numeric
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01'::date, '2026-03-31'::date) -> 'filas') v(value)
    where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000dca2'),
  100.00::numeric,
  'PASADO · un periodo anterior a la vigencia del candado no cambia de monto');

select * from finish();
rollback;
