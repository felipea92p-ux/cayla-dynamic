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
select plan(13);

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
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1','Instituto',200,'trabajador','2026-08-01','2026-12-31') $$,
  'Solo Desarrollo Organizacional registra asignaciones por educación.',
  'La propia interesada no puede cargarse una asignación');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);

-- ── Los dos techos ──────────────────────────────────────────────────────────
select lives_ok(
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1','Instituto Sur',200,'trabajador','2026-06-01','2026-12-31') $$,
  'Un comprobante de S/200 entra sin que nadie escriba el monto');

-- ⇩ CAMBIO 0149 ⇩ Antes acá se probaba que un monto de más se RECHAZABA. Desde
-- la 0149 un monto de más es inexpresable: la función lo calcula y el parámetro
-- ya no existe. Un caso borde que deja de poder ocurrir vale más que un `raise`
-- que lo caza, así que la prueba pasa a afirmar la cifra en vez del rechazo.
select is(
  (select monto from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000b1'),
  150.00::numeric,
  'El monto guardado es el 75% del comprobante: 200 × 75% = 150, y nadie lo tecleó');

-- El rango cayla tiene tope S/180 (0132). Un comprobante de S/300 al 75%
-- sostendría S/225, así que lo que manda es el techo del rango.
--
-- ⇩ CAMBIO 0281 ⇩ La función pide las fechas: desde la 0281 el techo se reparte
-- entre las asignaciones que SE SOLAPAN, así que sin saber cuándo rige no se
-- puede decir cuánto queda. Se preguntan fechas de 2027 —fuera de la vigencia
-- que esta persona ya tiene cargada arriba— para seguir preguntando lo que esta
-- aserción siempre quiso preguntar: que el techo del rango manda sobre el 75 %.
select is(
  fn_educacion_monto('00000000-0000-0000-0000-0000000000b1', 300::numeric,
                     '2027-01-01'::date, '2027-06-30'::date),
  180.00::numeric,
  'Con un comprobante de S/300 manda el techo del rango cayla: S/180, no S/225');

-- ── Validaciones de forma ───────────────────────────────────────────────────
select throws_ok(
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1','Instituto',100,'primo','2026-08-01','2026-12-31') $$,
  'El beneficiario es «trabajador» o «hijo» (llegó «primo»).',
  'El beneficiario solo puede ser la trabajadora o su hijo');

select throws_ok(
  $$ select fn_educacion_registrar('00000000-0000-0000-0000-0000000000b1','  ',100,'trabajador','2026-08-01','2026-12-31') $$,
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
-- ⇩ CAMBIO 0150 ⇩ Sin comprobante no se paga, así que hay que cargarlo para que
-- esta afirmación siga midiendo lo que quería: que una asignación VIGENTE llega
-- al pago. Que una SIN papel no llegue lo cubre la prueba 115.
update asignaciones_educacion set comprobante_url = 'educacion/b1/1.pdf'
 where persona_id = '00000000-0000-0000-0000-0000000000b1';

select is(
  (select (x->>'monto_educacion')::numeric
     from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28')->'filas') x
    where x->>'persona_id' = '00000000-0000-0000-0000-0000000000b1'),
  150.00::numeric,
  'La asignación vigente entra en la planilla del periodo');

-- ⇩ CAMBIO 0150 ⇩ Esta afirmación cambió de sentido, y el cambio es el arreglo.
-- Antes, cerrar el 31/07 sacaba a la persona del periodo 29/07–28/08 entero: la
-- condición exigía seguir vigente el ÚLTIMO día. O sea que quien terminaba su
-- ciclo a los tres días de empezado el periodo perdía el mes completo, habiendo
-- estudiado y pagado esa pensión. Ahora basta con estar vigente al EMPEZAR.
select fn_educacion_cerrar(
  (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000b1'),
  '2026-07-31',
  'cierre de laboratorio');

select is(
  (select (x->>'monto_educacion')::numeric
     from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28')->'filas') x
    where x->>'persona_id' = '00000000-0000-0000-0000-0000000000b1'),
  150.00::numeric,
  'Cerrada el 31/07 y el periodo abre el 29/07: cobra el mes completo, ya lo pagó');

-- Y el periodo siguiente, con la vigencia ya terminada, no paga nada: el cierre
-- corta de verdad, sólo que un periodo después.
select is(
  (select (x->>'monto_educacion')::numeric
     from jsonb_array_elements(fn_planilla_calcular('2026-08-29','2026-09-28')->'filas') x
    where x->>'persona_id' = '00000000-0000-0000-0000-0000000000b1'),
  0.00::numeric,
  'En el periodo siguiente ya no se paga: el cierre corta, un periodo después');

select is(
  (select count(*) from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000b1'),
  1::bigint,
  'Pero la fila SIGUE: es el sustento de lo que ya se pagó en periodos cerrados');

select * from finish();
rollback;
