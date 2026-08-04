-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 100_la_educacion_se_carga_con_su_papel.test.sql — Las puertas de la 0136
-- ============================================================================
-- La asignación por educación entra en lo que cobra una persona, así que las
-- reglas que la limitan no pueden vivir solo en la pantalla. Lo que se blinda:
--   · solo Desarrollo Organizacional la registra;
--   · nunca se paga más de lo que el comprobante sostiene (CHECK de la 0120);
--   · nunca se pasa del tope del rango (trigger de la 0132);
--   · cerrarla la saca del pago SIN borrar la fila — el sustento de lo ya
--     pagado tiene que sobrevivir a una fiscalización;
--   · el permiso sobre los archivos niega limpio ante un path con basura, en vez
--     de reventar con un error de casteo.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000e1', 'ZZEDU', 'Sede de laboratorio', true);

-- Un admin y una integrante, ambos con sesión simulable (replica salta la FK a auth.users).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id, estado, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000000a1','AdminEdu','Laboratorio','00000000-0000-0000-0000-0000000000e1','h','admin','00000000-0000-0000-0000-0000000000a2','activo','2025-01-01','planilla'),
       ('00000000-0000-0000-0000-0000000000b1','Estudiante','Laboratorio','00000000-0000-0000-0000-0000000000e1','h','integrante','00000000-0000-0000-0000-0000000000b2','activo','2025-01-01','planilla');
set session_replication_role = origin;

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000b1', 'cayla', 1450, '2025-01-01');

-- ── Quién puede registrar ───────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);

select throws_ok(
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1',100,'Instituto',200,75,'trabajador','2026-08-01') $$,
  'Solo Desarrollo Organizacional registra asignaciones por educación.',
  'La propia interesada no puede cargarse una asignación');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);

-- ── Los dos techos ──────────────────────────────────────────────────────────
select lives_ok(
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1',150,'Instituto Sur',200,75,'trabajador','2026-06-01') $$,
  'S/150 con un comprobante de S/200 al 75% sí entra (150 = 200 × 75%)');

select throws_ok(
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1',151,'Instituto Sur',200,75,'trabajador','2026-09-01') $$,
  '23514',
  null,
  'S/151 sobre un comprobante que solo sostiene S/150 lo bloquea el CHECK');

-- El rango cayla tiene tope S/180 (0132). El comprobante de S/300 al 75% sostiene
-- S/225, así que lo único que puede frenar los S/190 es el tope del rango.
select throws_ok(
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1',190,'Instituto Sur',300,75,'trabajador','2026-10-01') $$,
  'P0001',
  null,
  'S/190 pasa el comprobante pero lo frena el tope del rango cayla (S/180)');

-- ── Validaciones de forma ───────────────────────────────────────────────────
select throws_ok(
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1',50,'Instituto',100,75,'primo','2026-08-01') $$,
  'El beneficiario es «trabajador» o «hijo» (llegó «primo»).',
  'El beneficiario solo puede ser la trabajadora o su hijo');

select throws_ok(
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1',50,'  ',100,75,'trabajador','2026-08-01') $$,
  'Falta la institución que emite el comprobante.',
  'Sin institución no hay comprobante que valga');

-- ── El permiso sobre los archivos niega limpio ──────────────────────────────
select ok(fn_educacion_puede_ver('educacion/no-es-un-uuid/x.pdf') = false,
  'Un path con basura en vez de uuid se niega, no revienta');
select ok(fn_educacion_puede_ver('otracarpeta/00000000-0000-0000-0000-0000000000b1/x.pdf') = false,
  'Un path fuera de la carpeta educacion se niega');
select ok(fn_educacion_puede_ver('') = false,
  'Un path vacío se niega');

-- ── Lo que llega al pago ────────────────────────────────────────────────────
select is(
  (select (x->>'monto_educacion')::numeric
     from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28')->'filas') x
    where x->>'persona_id' = '00000000-0000-0000-0000-0000000000b1'),
  150.00::numeric,
  'La asignación vigente entra en la planilla del periodo');

-- Cerrarla el 31/07 la saca del periodo 29/07–28/08.
select fn_educacion_cerrar(
  (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000b1'),
  '2026-07-31');

select is(
  (select (x->>'monto_educacion')::numeric
     from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28')->'filas') x
    where x->>'persona_id' = '00000000-0000-0000-0000-0000000000b1'),
  0.00::numeric,
  'Cerrada antes del periodo, ya no se paga');

select is(
  (select count(*) from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000b1'),
  1::bigint,
  'Pero la fila SIGUE: es el sustento de lo que ya se pagó en periodos cerrados');

select * from finish();
rollback;
