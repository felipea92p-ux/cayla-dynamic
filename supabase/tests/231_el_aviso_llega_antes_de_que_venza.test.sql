-- ============================================================================
-- 231_el_aviso_llega_antes_de_que_venza.test.sql
-- ============================================================================
-- Ana ingresó el 01/01/2024 y no se ha tomado un solo día. Su primer récord
-- cierra el 01/01/2025 y VENCE el 01/01/2026: hasta esa fecha no hay
-- indemnización que valga, y a partir de ella sí.
--
-- Estas son las seis fechas con que se midió el defecto de la 0283 —que contaba
-- récords completos sin gozar y los llamaba vencidos— y con las que se comprobó
-- la regla que lo reemplaza: vencidos = k − 1.
-- ============================================================================
begin;
select plan(23);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000d0', 'ZZVA1', 'Sede vacaciones 1', true),
  ('00000000-0000-0000-0000-0000000000d5', 'ZZVA2', 'Sede vacaciones 2', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000000d1', 'VacDO', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000d0', 'lider_do', 'x',
   '00000000-0000-0000-0000-0000000000d9', '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000d3', 'VacEncargada', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000d0', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000000d8', '2021-01-01'),
  ('00000000-0000-0000-0000-0000000000d4', 'VacOtraSede', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000d5', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000000d7', '2021-01-01'),
  ('00000000-0000-0000-0000-0000000000d2', 'VacAna', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000d0', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000000d6', '2024-01-01');
set session_replication_role = origin;

-- Dos casos más, heredados de la prueba 234 que escribió la otra sesión para la
-- 0299: cuando esa migración se retiró, sus casos se trajeron acá en vez de
-- perderse. Mismo ingreso que Ana, y lo único que cambia es cuánto gozaron.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000000da', 'VacAlDia', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000d0', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000000db', 'VacMitad', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000d0', 'x', '2024-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-0000000000d2', 'cayla', 1200, '2024-01-01'),
  ('00000000-0000-0000-0000-0000000000da', 'cayla', 1200, '2024-01-01'),
  ('00000000-0000-0000-0000-0000000000db', 'cayla', 1200, '2024-01-01');

-- VacAlDia gozó sus dos récords; VacMitad, solo el primero.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-0000000000da','vacaciones','2025-02-01','2025-02-15','récord 1','00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000da','vacaciones','2026-02-01','2026-02-15','récord 2','00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000db','vacaciones','2025-02-01','2025-02-15','récord 1','00000000-0000-0000-0000-0000000000d1');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d9', true);


-- ── 1 · Antes de cerrar el primer récord no hay nada que avisar ─────────────
select is(
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2024-12-20'::date)->>'records_sin_gozar')::int,
  0, 'ANTES · a los 11 meses no hay ningún récord completo');

select is(
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2024-12-20'::date)->>'vence_el'),
  null, 'ANTES · y por eso no hay fecha de vencimiento que dar');


-- ── 2 · Recién cerrado: sin gozar, pero NO vencido ──────────────────────────
-- Este es el caso que la 0283 contaba mal.
select is(
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2025-01-15'::date)->>'records_sin_gozar')::int,
  1, 'CERRADO · a los 14 días de cerrarlo hay un récord completo sin gozar');

select is(
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2025-01-15'::date)->>'records_vencidos')::int,
  0, 'CERRADO · pero NINGUNO vencido: le queda un año entero para tomárselo');

select is(
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2025-01-15'::date)->>'vence_el')::date,
  '2026-01-01'::date, 'CERRADO · y vence el 01/01/2026, un año después de cerrarse');

select is(
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2025-01-15'::date)->>'dias_para_vencer')::int,
  351, 'CERRADO · faltan 351 días, así que todavía no es asunto de nadie');


-- ── 3 · El aviso entra a los 60 días y ni un día antes ─────────────────────
select is(
  (select count(*)::int from fn_vacaciones_por_vencer(60, '2025-09-01')
    where persona_id = '00000000-0000-0000-0000-0000000000d2'),
  0, 'AVISO · a 122 días del vencimiento no aparece');

select is(
  (select count(*)::int from fn_vacaciones_por_vencer(60, '2025-11-05')
    where persona_id = '00000000-0000-0000-0000-0000000000d2'),
  1, 'AVISO · a 57 días sí aparece');

select is(
  (select dias_para_vencer from fn_vacaciones_por_vencer(60, '2025-11-05')
    where persona_id = '00000000-0000-0000-0000-0000000000d2'),
  57, 'AVISO · y dice cuántos días faltan, no solo que falta');


-- ── 4 · Pasado el año: uno vencido, y el siguiente ya tiene su fecha ───────
select is(
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2026-01-15'::date)->>'records_sin_gozar')::int,
  2, 'VENCIDO · con dos años sin gozar hay dos récords completos');

select is(
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2026-01-15'::date)->>'records_vencidos')::int,
  1, 'VENCIDO · pero solo UNO venció — la 0283 decía dos');

select is(
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2026-01-15'::date)->>'vence_el')::date,
  '2027-01-01'::date, 'VENCIDO · y el que sigue vence el 01/01/2027');


-- ── 5 · La liquidación dice lo mismo que el saldo ───────────────────────────
select is(
  (fn_vacaciones_truncas('00000000-0000-0000-0000-0000000000d2'::uuid, '2026-01-15'::date)->>'records_vencidos')::int,
  1, 'HOJA · la liquidación cuenta los vencidos igual que el saldo');

select is(
  (fn_vacaciones_truncas('00000000-0000-0000-0000-0000000000d2'::uuid, '2026-01-15'::date)->>'dias_pendientes')::numeric,
  (fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2026-01-15'::date)->>'dias_pendientes')::numeric,
  'HOJA · y los días pendientes salen de la misma cuenta, no de una copia');


-- ── 6 · Cada quien ve lo suyo ───────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d6', true);

select lives_ok(
  $$ select fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2026-01-15'::date) $$,
  'PERMISO · cada persona puede ver su propio saldo');

select throws_like(
  $$ select fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d1'::uuid, '2026-01-15'::date) $$,
  '%otra persona%',
  'PERMISO · pero no el de una compañera');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d7', true);

select throws_like(
  $$ select fn_vacaciones_saldo('00000000-0000-0000-0000-0000000000d2'::uuid, '2026-01-15'::date) $$,
  '%otra persona%',
  'PERMISO · y una encargada de OTRA sede tampoco');

-- ── 7 · Quien YA tiene un récord vencido no puede desaparecer de la lista ──
-- Se vuelve a la sesión de DO: la sección anterior la dejó en la encargada de
-- OTRA sede, que no ve a nadie — y una lista vacía por permisos parecería que la
-- regla falla cuando lo que falla es quién está preguntando.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d9', true);

-- Se descubrió mirando el panel con datos de prueba, no razonándolo: con solo el
-- filtro de los 60 días, alguien con dos récords vencidos y el siguiente a un
-- año de distancia no salía por ningún lado — justo la persona más urgente.
select is(
  (select count(*)::int from fn_vacaciones_por_vencer(60, '2027-08-25'::date)
    where persona_id = '00000000-0000-0000-0000-0000000000d2'),
  1,
  'VENCIDO · sigue en la lista aunque su próximo vencimiento esté a más de 60 días');

select is(
  (select records_vencidos from fn_vacaciones_por_vencer(60, '2027-08-25'::date)
    where persona_id = '00000000-0000-0000-0000-0000000000d2'),
  2,
  'VENCIDO · y con tres años sin gozar son DOS los vencidos, no tres');

-- ── 8 · Los tres casos de la prueba 234, que no se perdieron ───────────────
-- Los escribió la otra sesión para la 0299. Cuando esa migración se retiró por
-- duplicada, sus casos se trajeron acá: son los que esta prueba no cubría.
--
-- Se miden al 01/03/2026 y no antes: las vacaciones de VacAlDia son de febrero
-- de 2026, y preguntando en enero todavía no habían ocurrido — el saldo las
-- cuenta por la fecha en que se toman, así que habría salido en la lista por una
-- razón que no es la que se quiere probar.
select is(
  (select count(*)::int from fn_vacaciones_por_vencer(400, '2026-03-01'::date)
    where persona like 'VacAlDia%'),
  0,
  'SIN RUIDO · quien gozó sus dos récords no aparece en el aviso');

select is(
  (select vence_el from fn_vacaciones_por_vencer(400, '2026-03-01'::date)
    where persona like 'VacMitad%'),
  '2027-01-01'::date,
  'FIFO · quien gozó el primer récord tiene pendiente el segundo, que vence en 2027');

select is(
  (select records_vencidos from fn_vacaciones_por_vencer(400, '2026-03-01'::date)
    where persona like 'VacMitad%'),
  0,
  'FIFO · y no le ha vencido ninguno: el aviso llega con tiempo, que es su razón de ser');

select is(
  (select count(*)::int from fn_vacaciones_por_vencer(30, '2026-03-01'::date)
    where persona like 'VacMitad%'),
  0,
  'VENTANA · con 30 días de aviso, el que vence dentro de un año no aparece');

select * from finish();
rollback;
