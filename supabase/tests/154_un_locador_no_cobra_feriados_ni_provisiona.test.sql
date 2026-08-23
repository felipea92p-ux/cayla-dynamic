-- ============================================================================
-- 154_un_locador_no_cobra_feriados_ni_provisiona.test.sql
-- ============================================================================
-- La boleta interna de un locador —cobra por hora, sin horario, sin
-- subordinación— del periodo 29/07–28/08 de 2026 decía, con estas palabras:
--
--     Feriados                                              S/ 18.29
--     Gratificación — la parte de este mes                   S/ 21.99
--     Bonificación extraordinaria — la parte de este mes     S/  1.98
--     CTS — la parte de este mes                             S/ 11.92
--     Vacaciones — la parte de este mes                      S/ 11.00
--
-- Ninguna le corresponde. Y la de vacaciones seguía saliendo DESPUÉS de que la
-- 0196 apagara su devengo — ese es el dato que explica todo:
--
--   LA BOLETA NO LEE `fn_provisiones`. `fn_planilla_calcular` calcula sus
--   propias provisiones, con los mismos factores. La 0196 conectó el interruptor
--   por persona en una de las dos y dejó la otra intacta.
--
-- POR QUÉ ESTE ARCHIVO EXISTE Y NO SOLO LA MIGRACIÓN
--   La última aserción es la que de verdad importa: exige que las DOS funciones
--   digan lo mismo para la misma persona. Mientras dos sitios calculen la misma
--   cosa, la próxima corrección volverá a aplicarse a uno solo — y nadie se
--   enterará hasta ver una boleta impresa, que es como se enteró esta vez.
--
-- LAS DOS MITADES, que se rompen por separado:
--   · a quien presta un servicio no se le imprime ningún concepto laboral;
--   · a quien cumple una jornada NO le cambia nada, ni un céntimo.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ad10', 'ZZLOC', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ad11', 'LocAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ad10', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ad19', '2025-01-01');
set session_replication_role = origin;

-- Las dos idénticas salvo en el vínculo. Es lo que hace la prueba concluyente:
-- mismas horas, mismo salario, mismo feriado trabajado.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000ad12', 'Uno',  'Planilla',   '00000000-0000-0000-0000-00000000ad10', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000000ad13', 'Dos',  'Honorarios', '00000000-0000-0000-0000-00000000ad10', 'test-hash', '2025-01-01', 'rxh');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'aurora', 1800, '2025-01-01'
from unnest(array['00000000-0000-0000-0000-00000000ad12'::uuid,
                  '00000000-0000-0000-0000-00000000ad13'::uuid]) p;

-- El feriado del periodo NO se inserta: el 06/08/2026 ya existe, sembrado por la
-- 0080. Insertarlo reventaba con `duplicate key` y la prueba entera moría antes
-- de la primera aserción — «Bad plan: you planned 9 tests but ran 0», que es
-- justo el fallo silencioso que CLAUDE.md advierte que se lee como un descuido y
-- no lo es. Se comprueba que está, que es lo que la aserción necesita.
select ok(
  exists (select 1 from feriados where fecha between '2026-07-29' and '2026-08-28'),
  'DE PARTIDA · el periodo tiene al menos un feriado, si no la primera aserción no probaría nada');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 8, 'cerrada'
from unnest(array['00000000-0000-0000-0000-00000000ad12'::uuid,
                  '00000000-0000-0000-0000-00000000ad13'::uuid]) p,
     generate_series('2026-07-29'::date, '2026-08-28'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ad19', true);

create or replace function _bol(p_id uuid, p_campo text) returns numeric
language sql stable as $$
  select (e ->> p_campo)::numeric
  from jsonb_array_elements(
         fn_planilla_calcular('2026-07-29', '2026-08-28') -> 'filas') e
  where (e ->> 'persona_id')::uuid = p_id;
$$;

-- ── 1 · A quien cumple una jornada NO le cambia nada ────────────────────────
select cmp_ok(_bol('00000000-0000-0000-0000-00000000ad12', 'monto_feriados'), '>', 0::numeric,
  'PLANILLA · el feriado se le sigue pagando');
select cmp_ok(_bol('00000000-0000-0000-0000-00000000ad12', 'provision_gratificacion'), '>', 0::numeric,
  'PLANILLA · y su boleta sigue mostrando la parte de gratificación del mes');
select cmp_ok(_bol('00000000-0000-0000-0000-00000000ad12', 'provision_cts'), '>', 0::numeric,
  'PLANILLA · y la de CTS');

-- ── 2 · A quien presta un servicio, ninguna ─────────────────────────────────
select is(_bol('00000000-0000-0000-0000-00000000ad13', 'monto_feriados'), 0::numeric,
  'LOCADOR · el feriado NO se le paga: no tiene descanso remunerado que respetar');
select is(_bol('00000000-0000-0000-0000-00000000ad13', 'provision_gratificacion'), 0::numeric,
  'LOCADOR · su boleta no imprime gratificación');
select is(_bol('00000000-0000-0000-0000-00000000ad13', 'provision_bonif_extraordinaria'), 0::numeric,
  'LOCADOR · ni la bonificación extraordinaria, que cuelga de la gratificación');
select is(_bol('00000000-0000-0000-0000-00000000ad13', 'provision_cts'), 0::numeric,
  'LOCADOR · ni CTS');
select is(_bol('00000000-0000-0000-0000-00000000ad13', 'provision_vacaciones'), 0::numeric,
  'LOCADOR · ni vacaciones');

-- ── 3 · Y las DOS funciones dicen lo mismo ──────────────────────────────────
-- La aserción que de verdad importa. `fn_planilla_calcular` y `fn_provisiones`
-- calculan la misma cosa por caminos distintos, y ese es el defecto de raíz: la
-- 0196 arregló uno y dejó el otro, y nadie se enteró hasta ver una boleta.
-- Mientras las dos existan, esto es lo que las mantiene sincronizadas.
-- El `coalesce` es del CAMBIO 0274: desde entonces quien no devenga nada ni
-- siquiera ocupa una fila en las provisiones, así que «no está» cuenta como
-- «no provisiona gratificación». La aserción sigue diciendo lo mismo — las dos
-- funciones de acuerdo — y sigue rompiéndose igual si una de las dos empieza a
-- darle plata al locador.
select is(
  coalesce((select ((e -> 'grati_total')::numeric > 0)
              from jsonb_array_elements(fn_provisiones('2026-08-28') -> 'personas') e
             where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000ad13'), false),
  (_bol('00000000-0000-0000-0000-00000000ad13', 'provision_gratificacion') > 0),
  'LAS DOS DE ACUERDO · provisiones y boleta dicen lo mismo del mismo locador');

select * from finish();
rollback;
