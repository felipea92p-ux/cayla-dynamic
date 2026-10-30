-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 454_la_liquidacion_lista_lo_que_se_debe_de_periodos_anteriores.test.sql — la 0564
-- ============================================================================
-- El caso real (producción, 2026-10-29): Emily Rico y Milagritos Zarate cesaron el
-- 29/10, que es el periodo NUEVO; su liquidación calcula un día y el sueldo del
-- periodo anterior —todavía abierto— no aparecía en ninguna parte de la pantalla.
--
-- Qué fija, en orden de importancia:
--   · Lista el periodo anterior sin pagar, con EXACTAMENTE lo que la planilla le
--     calcula a esa persona en él (se compara contra el núcleo, no contra un número).
--   · NO lo suma a la liquidación: el periodo de `fn_liquidacion` sigue siendo solo
--     el del cese. Sumarlo lo pagaría dos veces.
--   · No lista nada si el cese cae en el primer periodo, si no trabajó en el
--     anterior, o si ese periodo ya está pagado.
--   · Solo admin y líder; sin fecha de cese se niega, como `fn_liquidacion`.
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000454a01', 'ZZ454', 'Sede de laboratorio 454', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-000000454aa0', 'Admin', 'P454', '00000000-0000-0000-0000-000000454a01', 'admin', 'x',
        '00000000-0000-0000-0000-000000454aa1'),
       ('00000000-0000-0000-0000-000000454aa2', 'Integrante', 'P454', '00000000-0000-0000-0000-000000454a01', 'integrante', 'x',
        '00000000-0000-0000-0000-000000454aa3');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000454aa1', true);

-- Dos periodos consecutivos, lejos de los reales para no pisarlos.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000454e01', '2031-01-01', '2031-01-31', 'abierto'),
  ('00000000-0000-0000-0000-000000454e02', '2031-02-01', '2031-02-28', 'abierto');

-- A: trabajó en los dos periodos y cesó el 3/2 (como Emily). B: cesó dentro del
-- primero. C: nunca trabajó en el primero. E: sigue activa (para la fecha explícita).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, con_hijos,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000454b01', 'A', 'DosPeriodos',  '00000000-0000-0000-0000-000000454a01', 'x', '2031-01-05', 'planilla', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000454b02', 'B', 'SoloUnPeriodo','00000000-0000-0000-0000-000000454a01', 'x', '2031-01-05', 'planilla', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000454b03', 'C', 'SoloElSegundo','00000000-0000-0000-0000-000000454a01', 'x', '2031-01-05', 'planilla', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000454b04', 'E', 'SigueActiva',  '00000000-0000-0000-0000-000000454a01', 'x', '2031-01-05', 'planilla', false, 1230, 'activo', 'onp');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1230, '2030-12-01' from personas where id::text like '00000000-0000-0000-0000-000000454b%';

create function pg_temp.dia(p_persona uuid, p_fecha date) returns void language sql as $$
  insert into jornadas (persona_id, fecha, horas_trabajadas, estado, entrada_ts, salida_final_ts)
  values (p_persona, p_fecha, 6.5, 'cerrada', (p_fecha || ' 09:00-05')::timestamptz, (p_fecha || ' 15:30-05')::timestamptz);
$$;
select pg_temp.dia('00000000-0000-0000-0000-000000454b01', d::date) from generate_series('2031-01-05'::date, '2031-01-09'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000454b01', d::date) from generate_series('2031-02-01'::date, '2031-02-03'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000454b02', d::date) from generate_series('2031-01-05'::date, '2031-01-07'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000454b03', d::date) from generate_series('2031-02-01'::date, '2031-02-03'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000454b04', d::date) from generate_series('2031-01-05'::date, '2031-01-09'::date, interval '1 day') d;

set session_replication_role = replica;
update personas set estado = 'inactivo', fecha_cese = '2031-02-03', motivo_cese = 'fin_periodo_prueba'
 where id in ('00000000-0000-0000-0000-000000454b01', '00000000-0000-0000-0000-000000454b03');
update personas set estado = 'inactivo', fecha_cese = '2031-01-07', motivo_cese = 'fin_periodo_prueba'
 where id = '00000000-0000-0000-0000-000000454b02';
set session_replication_role = origin;

-- ── 1 · El caso de Emily: el periodo anterior sin pagar aparece ─────────────
select is((select count(*)::int from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b01')), 1,
  'EMILY · el periodo anterior sin pagar aparece, uno solo');
select is((select fecha_ini || ' → ' || fecha_fin from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b01')),
  '2031-01-01 → 2031-01-31', 'EMILY · es el periodo anterior al del cese, entero');
select is((select estado from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b01')), 'abierto',
  'EMILY · y dice en qué estado está');
select is(
  (select total from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b01')),
  (select round((e->>'total')::numeric, 2)
     from jsonb_array_elements(fn_planilla_calcular_nucleo('2031-01-01', '2031-01-31') -> 'filas') e
    where (e->>'persona_id')::uuid = '00000000-0000-0000-0000-000000454b01'),
  'MONTO · es EXACTAMENTE lo que la planilla le calcula en ese periodo');
select ok((select total from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b01')) > 0,
  'MONTO · y es plata de verdad, no un cero');

-- ── 2 · NO se suma a la liquidación ─────────────────────────────────────────
select is((fn_liquidacion('00000000-0000-0000-0000-000000454b01') -> 'periodo' ->> 'desde'), '2031-02-01',
  'NO SE SUMA · el sueldo del periodo de la liquidación sigue siendo solo el del cese');

-- ── 3 · Lo que NO lista ─────────────────────────────────────────────────────
select is((select count(*)::int from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b02')), 0,
  'SIN ANTERIOR · quien cesó dentro del primer periodo no tiene nada anterior');
select is((select count(*)::int from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b03')), 0,
  'SIN TRABAJO · quien no trabajó en el periodo anterior no lo ve en cero');

update periodos_planilla set estado = 'pagado' where id = '00000000-0000-0000-0000-000000454e01';
select is((select count(*)::int from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b01')), 0,
  'PAGADO · si ese periodo ya se pagó, deja de listarse');
update periodos_planilla set estado = 'abierto' where id = '00000000-0000-0000-0000-000000454e01';
select is((select count(*)::int from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b01')), 1,
  'REABIERTO · y si se reabre, vuelve');

-- ── 4 · La fecha de cese explícita (la pantalla puede pedirla) ──────────────
select is((select count(*)::int from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b04', '2031-02-03')), 1,
  'FECHA · con una fecha de cese explícita funciona aunque la persona siga activa');

-- ── 5 · Quién puede y cuándo se niega ───────────────────────────────────────
select throws_ok($$ select * from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b04') $$,
  'P0001', 'Esa persona no tiene fecha de cese. Regístrala en Equipo antes de liquidar.',
  'SIN CESE · sin fecha de cese se niega, igual que fn_liquidacion');
select throws_ok($$ select * from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454fff') $$,
  'P0001', 'La persona no existe.', 'INEXISTENTE · una persona que no existe se niega');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000454aa3', true);
select throws_ok($$ select * from fn_liquidacion_periodos_anteriores('00000000-0000-0000-0000-000000454b01') $$,
  'P0001', 'Solo un administrador o líder puede ver la liquidación de una persona.',
  'PERMISO · un integrante no puede verla');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000454aa1', true);
select ok(has_function_privilege('authenticated', 'fn_liquidacion_periodos_anteriores(uuid, date)', 'execute'),
  'PERMISO · el panel (authenticated) la puede llamar');
select ok(not has_function_privilege('anon', 'fn_liquidacion_periodos_anteriores(uuid, date)', 'execute'),
  'PERMISO · y anon no');

select * from finish();
rollback;
