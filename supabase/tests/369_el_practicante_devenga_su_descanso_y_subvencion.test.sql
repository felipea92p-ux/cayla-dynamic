-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 369_el_practicante_devenga_su_descanso_y_subvencion.test.sql
-- ============================================================================
-- Cubre la 0465. Un practicante bajo la Ley 28518 (modalidad formativa) tiene
-- dos beneficios propios que ni gratificación, ni CTS ni vacaciones de 30 días
-- le dan (art. 47): un descanso de 15 días subvencionados —UNA sola vez, al
-- superar los 12 meses continuos de convenio— y una subvención semestral
-- adicional —que se repite cada 6 meses, sin tope, mientras siga activo—.
-- Hasta la 0465 ninguno de los dos se calculaba en ningún lado del sistema.
--
-- LO QUE HAY QUE DEFENDER, EN ESTE ORDEN:
--   a. recién ingresado (0 días de convenio): los dos devengados en cero, y
--      `ley28518_descanso_completo` en false — no hay error, hay ceros reales;
--   b. a los 91 días (≈3 meses): el descanso y la subvención devengan a
--      RITMOS DISTINTOS —la subvención crece al doble de rápido, porque su
--      divisor es un semestre (182.5) y el del descanso es un año (365)—;
--   c. al llegar a los 365 días el descanso TOCA SU TOPE y ahí se queda para
--      siempre (365 y 400 días dan el mismo descanso), mientras la subvención
--      SIGUE CRECIENDO sin tope (400 días da más que 365);
--   d. lo que ya se depositó por `subvencion_practicante` se resta del bruto,
--      igual que ya hace `fn_beneficio_ya_depositado` con los otros cinco
--      beneficios — pero por la puerta de `fn_practicante_ya_depositado`;
--   e. sin ningún tramo vigente en `asignaciones_salario`, `ley28518_sin_tarifa`
--      se enciende y los dos montos salen en cero — nunca un error, nunca un
--      número inventado;
--   f. quien NO es practicante (planilla, rxh) sigue exactamente igual: las
--      seis claves nuevas en 0/false —`ley28518_dias_convenio` en CERO
--      también, no la resta real de fechas— y ni un céntimo de lo que ya
--      devengaba se mueve;
--   g. el libro de desembolsos admite las dos ventanas nuevas y
--      `fn_practicante_ya_depositado` sí sabe leerlas, sumando SIN filtrar
--      por año — a diferencia de `fn_beneficio_ya_depositado`, que filtra.
--
-- CÓMO ESTÁ ESCRITO. Un solo `p_as_of` fijo ('2026-09-15') y personas cuya
-- `fecha_ingreso` se calcula HACIA ATRÁS desde esa fecha (`'2026-09-15'::date
-- - N`), para que "91 días de convenio" o "400 días de convenio" sean un
-- hecho de la fecha de ingreso y no una cuenta hecha a mano que se pueda
-- desalinear del cálculo real. Los montos esperados también se escriben como
-- la misma fórmula del contrato, no como decimales tecleados a mano.
-- ============================================================================
begin;
select plan(34);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000369000', 'Z369', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000369001', 'TresAdmin369', 'Laboratorio',
        '00000000-0000-0000-0000-000000369000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000369099', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  -- a · recién ingresado: 0 días de convenio.
  ('00000000-0000-0000-0000-000000369002', 'TresCero',          'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', '2026-09-15'::date, 'practicante'),
  -- b · ≈3 meses (91 días).
  ('00000000-0000-0000-0000-000000369003', 'TresNoventaYUno',   'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', ('2026-09-15'::date - 91), 'practicante'),
  -- c · exactamente 365 días: el descanso toca su tope justo aquí.
  ('00000000-0000-0000-0000-000000369004', 'TresTope365',       'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', ('2026-09-15'::date - 365), 'practicante'),
  -- c · 400 días: pasado el tope. El descanso no se mueve; la subvención sí.
  ('00000000-0000-0000-0000-000000369005', 'TresTope400',       'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', ('2026-09-15'::date - 400), 'practicante'),
  -- d · 400 días también, pero con un depósito ya anotado en el libro.
  ('00000000-0000-0000-0000-000000369006', 'TresConDeposito',   'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', ('2026-09-15'::date - 400), 'practicante'),
  -- e · practicante sin NINGUNA fila en asignaciones_salario.
  ('00000000-0000-0000-0000-000000369007', 'TresSinTarifa',     'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', ('2026-09-15'::date - 200), 'practicante'),
  -- f · planilla de siempre, para comprobar que las seis claves nuevas no le
  --     tocan ni un céntimo de lo que ya devengaba.
  ('00000000-0000-0000-0000-000000369008', 'TresPlanillaOk',    'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', '2025-01-01', 'planilla'),
  -- f · rxh: la 0428 ya lo dejó FUERA de la lista por completo (prueba 338).
  --     Esta migración no tiene por qué abrirle una puerta nueva.
  ('00000000-0000-0000-0000-000000369009', 'TresRxhFuera',      'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', '2025-01-01', 'rxh'),
  -- g · solo para probar el libro y fn_practicante_ya_depositado directo, sin
  --     pasar por fn_provisiones.
  ('00000000-0000-0000-0000-000000369010', 'TresLibroDirecto',  'Laboratorio',
   '00000000-0000-0000-0000-000000369000', 'test-hash', ('2026-09-15'::date - 100), 'practicante');

-- Un tramo de salario vigente para todos los que SÍ deben tener tarifa.
-- 'TresSinTarifa' queda deliberadamente FUERA de este insert: es el caso (e).
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000369002', 'colibri', 1200.00, '2026-01-01'),
  ('00000000-0000-0000-0000-000000369003', 'colibri', 1200.00, '2026-01-01'),
  ('00000000-0000-0000-0000-000000369004', 'colibri', 1200.00, '2025-01-01'),
  ('00000000-0000-0000-0000-000000369005', 'colibri', 1200.00, '2025-01-01'),
  ('00000000-0000-0000-0000-000000369006', 'colibri', 1200.00, '2025-01-01'),
  ('00000000-0000-0000-0000-000000369008', 'colibri', 1300.00, '2025-01-01');

-- d · ya se le depositó parte de la subvención semestral, por transferencia.
-- El bruto devengado a los 400 días (salario 1200) es
-- round(1200 * 0.5 * 400 / 182.5, 2) = 1123.29 — se resta este monto de ahí.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
values ('00000000-0000-0000-0000-000000369006', 'subvencion_practicante', 2025, 300.00,
        '2025-12-01', 'transferencia');

-- f · jornadas de planilla de siempre, para que su gran_total sea > 0 y la
-- prueba pueda confirmar que la 0465 no le tocó nada.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000369008', d::date, 8, 'cerrada'
from generate_series('2026-01-05'::date, '2026-06-30'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000369099', true);

create temporary table _lista on commit drop as
select (e ->> 'persona_id')::uuid                       as persona_id,
       (e ->> 'nombre')                                 as nombre,
       (e ->> 'tipo_vinculo')                            as tipo_vinculo,
       (e ->> 'ley28518_dias_convenio')::int             as dias_convenio,
       (e ->> 'ley28518_descanso_dias')::numeric         as descanso_dias,
       (e ->> 'ley28518_descanso_devengado')::numeric    as descanso_devengado,
       (e ->> 'ley28518_descanso_completo')::boolean     as descanso_completo,
       (e ->> 'ley28518_subvencion_devengada')::numeric  as subvencion_devengada,
       (e ->> 'ley28518_sin_tarifa')::boolean            as sin_tarifa,
       (e ->> 'ley28518_subvencion_mensual')::numeric    as subvencion_mensual,
       (e ->> 'gran_total')::numeric                     as gran_total
from jsonb_array_elements(fn_provisiones('2026-09-15') -> 'personas') e;

-- ── a · Recién ingresado: 0 días, todo en cero, sin marcar el tope ──────────
select is((select dias_convenio from _lista where nombre like 'TresCero%'), 0,
  'a) CERO DÍAS · un practicante recién ingresado tiene ley28518_dias_convenio en 0');
select is((select descanso_devengado from _lista where nombre like 'TresCero%'), 0::numeric,
  'a) CERO DÍAS · el descanso devengado es 0.00, no un error');
select is((select subvencion_devengada from _lista where nombre like 'TresCero%'), 0::numeric,
  'a) CERO DÍAS · la subvención devengada es 0.00');
select is((select descanso_completo from _lista where nombre like 'TresCero%'), false,
  'a) CERO DÍAS · ley28518_descanso_completo es false');

-- ── b · 91 días: los dos beneficios crecen, y a RITMOS DISTINTOS ───────────
select is((select descanso_dias from _lista where nombre like 'TresNoventaYUno%'),
  round(15.0 * least(91, 365) / 365.0, 1),
  'b) 91 DÍAS · ley28518_descanso_dias es 15 × 91/365, redondeado a un decimal (≈3.7)');
select is((select descanso_devengado from _lista where nombre like 'TresNoventaYUno%'),
  round(1200.00 * 0.5 * least(91, 365) / 365.0, 2),
  'b) 91 DÍAS · el descanso devengado es exactamente subvención_mensual × 0.5 × 91/365');
select is((select subvencion_devengada from _lista where nombre like 'TresNoventaYUno%'),
  round(1200.00 * 0.5 * 91 / 182.5, 2),
  'b) 91 DÍAS · la subvención devengada es exactamente subvención_mensual × 0.5 × 91/182.5');
select isnt(
  (select descanso_devengado from _lista where nombre like 'TresNoventaYUno%'),
  (select subvencion_devengada from _lista where nombre like 'TresNoventaYUno%'),
  'b) RITMOS DISTINTOS · a los 91 días el descanso y la subvención NO valen lo mismo — crecen a velocidades distintas');
select is((select subvencion_mensual from _lista where nombre like 'TresNoventaYUno%'), 1200.00::numeric,
  'b) TRAZABILIDAD · ley28518_subvencion_mensual expone la tarifa real usada en los dos cálculos de arriba, sin adivinar');

-- ── c · 365 y 400 días: el descanso topa, la subvención no ─────────────────
select is((select descanso_completo from _lista where nombre like 'TresTope365%'), true,
  'c) TOPE · a los 365 días exactos, ley28518_descanso_completo ya es true');
select is((select descanso_completo from _lista where nombre like 'TresTope400%'), true,
  'c) TOPE · a los 400 días también, claro');
select is(
  (select descanso_devengado from _lista where nombre like 'TresTope365%'),
  (select descanso_devengado from _lista where nombre like 'TresTope400%'),
  'c) EL DESCANSO NO CRECE MÁS · 365 y 400 días dan EXACTAMENTE el mismo descanso devengado (una sola vez, tope a los 12 meses)');
select cmp_ok(
  (select subvencion_devengada from _lista where nombre like 'TresTope400%'), '>',
  (select subvencion_devengada from _lista where nombre like 'TresTope365%'),
  'c) LA SUBVENCIÓN SIGUE CRECIENDO · a los 400 días la subvención devengada es MAYOR que a los 365 — no tiene tope');

-- ── d · lo ya depositado se resta del bruto ─────────────────────────────────
select is(
  (select subvencion_devengada from _lista where nombre like 'TresConDeposito%'),
  round(round(1200.00 * 0.5 * 400 / 182.5, 2) - 300.00, 2),
  'd) SE DESCUENTA LO PAGADO · la subvención devengada es el bruto de 400 días MENOS los S/300 ya depositados en el libro');

-- ── e · sin ningún tramo vigente: se avisa, y los montos son cero (no error) ─
select is((select sin_tarifa from _lista where nombre like 'TresSinTarifa%'), true,
  'e) SIN TARIFA · sin ninguna fila vigente en asignaciones_salario, ley28518_sin_tarifa se enciende');
select is((select descanso_devengado from _lista where nombre like 'TresSinTarifa%'), 0::numeric,
  'e) SIN TARIFA · el descanso devengado es 0.00, no un error de división ni un null');
select is((select subvencion_devengada from _lista where nombre like 'TresSinTarifa%'), 0::numeric,
  'e) SIN TARIFA · la subvención devengada también es 0.00');

-- ── f · quien NO es practicante: las seis claves en 0/false, nada más se mueve
select is((select dias_convenio from _lista where nombre like 'TresPlanillaOk%'), 0,
  'f) NO PRACTICANTE · ley28518_dias_convenio es CERO (no la resta real de fechas, que sería > 600)');
select is((select descanso_devengado from _lista where nombre like 'TresPlanillaOk%'), 0::numeric,
  'f) NO PRACTICANTE · ley28518_descanso_devengado es 0.00');
select is((select descanso_dias from _lista where nombre like 'TresPlanillaOk%'), 0::numeric,
  'f) NO PRACTICANTE · ley28518_descanso_dias es 0.00');
select is((select descanso_completo from _lista where nombre like 'TresPlanillaOk%'), false,
  'f) NO PRACTICANTE · ley28518_descanso_completo es false');
select is((select subvencion_devengada from _lista where nombre like 'TresPlanillaOk%'), 0::numeric,
  'f) NO PRACTICANTE · ley28518_subvencion_devengada es 0.00');
select is((select sin_tarifa from _lista where nombre like 'TresPlanillaOk%'), false,
  'f) NO PRACTICANTE · ley28518_sin_tarifa es false (tiene tramo vigente y no le corresponde igual)');
select cmp_ok((select gran_total from _lista where nombre like 'TresPlanillaOk%'), '>', 0::numeric,
  'f) SIN REGRESIÓN · su gran_total de siempre (grati+CTS+vacaciones) sigue siendo > 0, la 0465 no se lo tocó');
select is((select count(*)::int from _lista where nombre like 'TresRxhFuera%'), 0,
  'f) SIGUE FUERA · un rxh sigue sin aparecer en Provisiones (0274/0428); la 0465 no le abrió una puerta nueva');

-- ── g · el libro admite las dos ventanas nuevas, y se suman sin año ─────────
select lives_ok(
  $$ insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
     values ('00000000-0000-0000-0000-000000369010', 'descanso_practicante', 2025, 100.00,
             '2025-06-01', 'transferencia') $$,
  'g) EL CHECK ADMITE · una fila con ventana = ''descanso_practicante'' se puede insertar');

select lives_ok(
  $$ insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
     values ('00000000-0000-0000-0000-000000369010', 'subvencion_practicante', 2025, 300.00,
             '2025-12-01', 'transferencia') $$,
  'g) EL CHECK ADMITE · una fila con ventana = ''subvencion_practicante'' también');

-- Un segundo depósito de la MISMA ventana, en OTRO año — la pregunta real de
-- este apartado: fn_practicante_ya_depositado no puede perderse este.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
values ('00000000-0000-0000-0000-000000369010', 'subvencion_practicante', 2026, 250.00,
        '2026-06-01', 'transferencia');

select is(
  fn_practicante_ya_depositado('00000000-0000-0000-0000-000000369010', 'subvencion_practicante'),
  550.00::numeric,
  'g) SIN FILTRAR POR AÑO · fn_practicante_ya_depositado suma los dos depósitos (2025 y 2026), a diferencia de fn_beneficio_ya_depositado');
select is(
  fn_practicante_ya_depositado('00000000-0000-0000-0000-000000369010', 'descanso_practicante'),
  100.00::numeric,
  'g) SIN MEZCLAR VENTANAS · el depósito de descanso_practicante no se contagia a la suma de subvencion_practicante');

select throws_ok(
  $$ insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
     values ('00000000-0000-0000-0000-000000369010', 'ventana_inventada', 2026, 50.00,
             '2026-06-01', 'transferencia') $$,
  '23514',
  null,
  'g) EL CHECK SIGUE CERRADO · una ventana inventada se sigue rechazando — ensanchar el CHECK no lo abrió del todo');

-- ── El cambio está, y es uno solo ───────────────────────────────────────────
select ok((select prosrc like '%CAMBIO 0465%' from pg_proc where proname = 'fn_provisiones'),
  'MARCADOR · fn_provisiones lleva el CAMBIO 0465');
select is((select count(*)::int from pg_proc where proname = 'fn_provisiones'), 1,
  'UNA SOLA · fn_provisiones no tiene una gemela con otra firma');
select is((select count(*)::int from pg_proc where proname = 'fn_practicante_ya_depositado'), 1,
  'UNA SOLA · fn_practicante_ya_depositado tampoco tiene una versión duplicada');

-- ── La pantalla puede llamar a la función nueva, anon no ────────────────────
select ok(
  has_function_privilege('authenticated', 'public.fn_practicante_ya_depositado(uuid, text)', 'execute')
  and not has_function_privilege('anon', 'public.fn_practicante_ya_depositado(uuid, text)', 'execute'),
  'PERMISO · authenticated puede ejecutar fn_practicante_ya_depositado y anon no');

select * from finish();
rollback;
