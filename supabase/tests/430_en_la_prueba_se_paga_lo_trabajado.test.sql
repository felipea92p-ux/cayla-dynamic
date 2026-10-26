-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 430_en_la_prueba_se_paga_lo_trabajado.test.sql — 0537
-- ============================================================================
-- La regla (Felipe, 2026-10-19), tal como la paga la planilla:
--   · «se retiró»            → HASTA LA 0554 no se le pagaba; desde la 0555 SÍ: se le paga
--                              lo trabajado, igual que a «no apto» (decidido 2026-10-26).
--   · «no apto»              → se le paga lo trabajado, SIN asignación familiar.
--   · prueba abierta         → lo trabajado, sin asignación familiar.
--   · contrato firmado       → asignación familiar como cualquiera.
--
-- Qué fija esta prueba, en orden de importancia:
--   · La mitad que no puede romperse: la gente de planilla y quien no tiene hijos
--     cobra EXACTAMENTE lo mismo que antes. Arreglar la prueba apagando de paso la
--     asignación de todos sería mucho peor que el defecto que se vino a arreglar.
--   · Quien se retiró aparece en la planilla (0555) y sus marcas siguen en su sitio.
--   · Si la reactivan, vuelve a pagarse: el defecto seguro es pagar.
--   · La 0537 copió el cuerpo de la 0524 y no se llevó por delante lo que se hizo
--     antes (0416, 0463, 0484, 0491, 0504): se vigilan sus marcas.
-- ============================================================================
begin;
select plan(21);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000430a01', 'ZZ430', 'Sede de laboratorio 430', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-000000430aa0', 'Admin', 'P430', '00000000-0000-0000-0000-000000430a01', 'admin', 'x',
        '00000000-0000-0000-0000-000000430aa1');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000430aa1', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, con_hijos,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000430b01', 'P', 'Retirado',  '00000000-0000-0000-0000-000000430a01', 'x', '2026-10-16', 'prueba',   true,  1130, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000430b02', 'P', 'NoApto',    '00000000-0000-0000-0000-000000430a01', 'x', '2026-10-14', 'prueba',   true,  1130, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000430b03', 'T', 'Testigo',   '00000000-0000-0000-0000-000000430a01', 'x', '2026-01-01', 'planilla', true,  1130, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000430b04', 'P', 'EnCurso',   '00000000-0000-0000-0000-000000430a01', 'x', '2026-10-15', 'prueba',   true,  1130, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000430b05', 'P', 'SinHijos',  '00000000-0000-0000-0000-000000430a01', 'x', '2026-10-15', 'prueba',   false, 1130, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000430b06', 'P', 'Contratada','00000000-0000-0000-0000-000000430a01', 'x', '2026-10-14', 'prueba',   true,  1130, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000430b07', 'P', 'Vuelve',    '00000000-0000-0000-0000-000000430a01', 'x', '2026-10-16', 'prueba',   true,  1130, 'activo', 'onp');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1230, '2026-01-01' from personas where id::text like '00000000-0000-0000-0000-000000430b%';

create function pg_temp.dia(p_persona uuid, p_fecha date) returns void language sql as $$
  insert into jornadas (persona_id, fecha, horas_trabajadas, estado, entrada_ts, salida_final_ts)
  values (p_persona, p_fecha, 6.5, 'cerrada', (p_fecha || ' 09:00-05')::timestamptz, (p_fecha || ' 15:30-05')::timestamptz);
$$;

-- Un día: el que se retira y el que vuelve. Tres días: no apto y contratada. Dos: en curso y sin hijos.
select pg_temp.dia('00000000-0000-0000-0000-000000430b01', '2026-10-16');
select pg_temp.dia('00000000-0000-0000-0000-000000430b07', '2026-10-16');
select pg_temp.dia(p, d::date)
  from (values ('00000000-0000-0000-0000-000000430b02'::uuid), ('00000000-0000-0000-0000-000000430b06'::uuid)) v(p),
       generate_series('2026-10-14'::date, '2026-10-16'::date, interval '1 day') d;
select pg_temp.dia(p, d::date)
  from (values ('00000000-0000-0000-0000-000000430b04'::uuid), ('00000000-0000-0000-0000-000000430b05'::uuid)) v(p),
       generate_series('2026-10-15'::date, '2026-10-16'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000430b03', d::date)
  from generate_series('2026-09-29'::date, '2026-10-16'::date, interval '1 day') d;

-- Se decide: se retira uno, no es apto otro, la tercera pasa a planilla (firmó contrato).
select fn_prueba_cerrar('00000000-0000-0000-0000-000000430b01', 'retirado', 'Dijo que no volvía');
select fn_prueba_cerrar('00000000-0000-0000-0000-000000430b02', 'no_apto', 'No llegó al nivel');
select fn_prueba_cerrar('00000000-0000-0000-0000-000000430b07', 'retirado', 'Se fue y después volvió');
select fn_set_tipo_vinculo('00000000-0000-0000-0000-000000430b06', 'planilla');

create temp table _f on commit drop as
select (e->>'persona_id')::uuid as pid, e
  from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-09-29', '2026-10-28') -> 'filas') e
 where (e->>'persona_id') like '00000000-0000-0000-0000-000000430b%';

-- ── 1 · «Se retiró»: desde la 0555 SÍ es una fila de la planilla ───────────
select is((select count(*)::int from _f where pid = '00000000-0000-0000-0000-000000430b01'), 1,
  'SE RETIRÓ · aparece en la planilla (0555): se le paga lo que trabajó');
select is((select (e->>'pago_base')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b01'), 41.00::numeric,
  'SE RETIRÓ · un día de 6,5 h: S/ 41,00, lo trabajado');
select is((select (e->>'asignacion_familiar')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b01'), 0::numeric,
  'SE RETIRÓ · y sin asignación familiar, como quien no fue apto');
select is((select count(*)::int from jornadas where persona_id = '00000000-0000-0000-0000-000000430b01'), 1,
  'SE RETIRÓ · pero su marca sigue en Horas: la jornada no se corrige por debajo');
select is((select resultado from pruebas where persona_id = '00000000-0000-0000-0000-000000430b01'), 'retirado',
  'SE RETIRÓ · y su cierre está registrado');

-- ── 2 · «No apto»: lo trabajado, sin asignación ─────────────────────────────
select is((select (e->>'pago_base')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b02'), 123.00::numeric,
  'NO APTO · se le paga lo trabajado: tres días de 6,5 h');
select is((select (e->>'asignacion_familiar')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b02'), 0::numeric,
  'NO APTO · y no cobra la asignación familiar');
select is((select e->>'con_hijos' from _f where pid = '00000000-0000-0000-0000-000000430b02'), 'true',
  'NO APTO · aunque tenga hijos: ese dato sigue diciendo la verdad');
select ok((select (e->>'descuento_afp')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b02')
          < (select (e->>'descuento_afp')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b03'),
  'NO APTO · y la pensión se descuenta solo de lo trabajado, no de una asignación que no se pagó');

-- ── 3 · Prueba abierta: lo trabajado, sin asignación ────────────────────────
select is((select (e->>'pago_base')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b04'), 82.00::numeric,
  'PRUEBA ABIERTA · se le paga lo trabajado: dos días');
select is((select (e->>'asignacion_familiar')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b04'), 0::numeric,
  'PRUEBA ABIERTA · y sin asignación hasta que firme el contrato');

-- ── 4 · Lo que NO puede moverse ─────────────────────────────────────────────
select ok((select (e->>'asignacion_familiar')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b03') > 0,
  'TESTIGO · la gente de planilla con hijos sigue cobrando la asignación');
select is((select (e->>'asignacion_familiar')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b06'),
          (select (e->>'asignacion_familiar')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b03'),
  'CONTRATO · quien firmó el contrato cobra la misma asignación que cualquiera');
select is((select (e->>'pago_base')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b06'), 123.00::numeric,
  'CONTRATO · y sus horas se pagan igual');
select is((select (e->>'pago_base')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b05'), 82.00::numeric,
  'SIN HIJOS · quien está de prueba y no tiene hijos cobra lo mismo que antes');
select is((select (e->>'aporte_essalud')::numeric from _f where pid = '00000000-0000-0000-0000-000000430b02'), 0::numeric,
  'ESSALUD · la prueba sigue sin generarlo (0484): esta migración no lo toca');

-- ── 5 · Si la reactivan, vuelve a pagarse ───────────────────────────────────
select is((select count(*)::int from _f where pid = '00000000-0000-0000-0000-000000430b07'), 1,
  'REACTIVAR · mientras sigue inactiva también aparece (0555): ya no hay nada que retener');
select lives_ok($$ select fn_reactivar_persona('00000000-0000-0000-0000-000000430b07') $$,
  'REACTIVAR · se la reactiva');
select is(
  (select (e->>'pago_base')::numeric
     from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-09-29', '2026-10-28') -> 'filas') e
    where (e->>'persona_id')::uuid = '00000000-0000-0000-0000-000000430b07'),
  41.00::numeric, 'REACTIVAR · y entonces se le paga lo marcado: el defecto seguro es pagar');

-- ── 6 · La 0537 no se llevó por delante lo anterior ─────────────────────────
select ok(
  (select bool_and(position(m in prosrc) > 0)
     from pg_proc, unnest(array['CAMBIO 0416', 'CAMBIO 0463', 'CAMBIO 0484', 'CAMBIO 0491', 'CAMBIO 0504', 'CAMBIO 0524', 'CAMBIO 0537', 'CAMBIO 0555']) m
    where proname = 'fn_planilla_calcular_nucleo'),
  'VERSIÓN · el núcleo conserva las marcas de la 0416, 0463, 0484, 0491, 0504 y 0524, y trae la 0537 y la 0555');
select is((select count(*)::int from pg_proc where proname = 'fn_planilla_calcular_nucleo'), 1,
  'VERSIÓN · una sola función, sin sobrecarga ambigua');

select * from finish();
rollback;
