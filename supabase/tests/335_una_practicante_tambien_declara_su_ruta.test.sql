-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 335_una_practicante_tambien_declara_su_ruta.test.sql — 0424
-- ============================================================================
-- Dos cosas se defienden, y la segunda es la que de verdad importa:
--
--   1. Que una practicante pueda registrar y firmar su declaración de ruta —
--      por las dos puertas (admin con fn_documento_registrar, y ella misma
--      con fn_confirmar_mi_declaracion_ruta) — y aparecer en el tablero,
--      tanto para admin como para su propia autoconsulta.
--
--   2. Que NADA MÁS se haya abierto de paso. `fn_persona_le_corresponde_movilidad`
--      toca tres puertas a la vez; si el criterio se hubiera escrito mal
--      (por ejemplo, invirtiendo la condición, o dejando pasar a cualquiera
--      con tipo_vinculo distinto de 'planilla'), un RxH —que por diseño NO
--      cobra movilidad (0117)— empezaría a aparecer en el tablero de
--      Documentación, exactamente el falso positivo que el sistema entero
--      está armado para evitar. Y el bono de cumpleaños, que esta migración
--      deja fuera a propósito, tiene que seguir rechazando a la practicante.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000335000', 'ZZ335', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id) values
  ('00000000-0000-0000-0000-000000335001', 'Prueba', 'Practicante',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'practicante',
   '00000000-0000-0000-0000-000000335011'),
  ('00000000-0000-0000-0000-000000335002', 'Prueba', 'Locadora',
   '00000000-0000-0000-0000-000000335000', 'integrante', 'test-hash', 'rxh',
   '00000000-0000-0000-0000-000000335012'),
  ('00000000-0000-0000-0000-000000335003', 'Prueba', 'AdminTest335',
   '00000000-0000-0000-0000-000000335000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000335013'),
  -- Distinta de la 335001 A PROPÓSITO (0425): con el candado de
  -- fn_confirmar_mi_declaracion_ruta, una vez que CUALQUIER puerta deja una
  -- declaración vigente y al día, la otra puerta ya no puede firmar sola. Si
  -- las dos puertas se probaran sobre la misma persona en secuencia, la
  -- segunda fallaría por el candado — y eso no sería un defecto del candado,
  -- sino de esta prueba mezclando dos preguntas independientes.
  ('00000000-0000-0000-0000-000000335005', 'Prueba', 'PracticanteDos',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'practicante',
   '00000000-0000-0000-0000-000000335015');
set session_replication_role = origin;

-- ── 1 · El criterio compartido, para las dos categorías que importan ───────
select is(
  fn_persona_le_corresponde_movilidad('00000000-0000-0000-0000-000000335001'),
  true,
  'CRITERIO · una practicante SÍ le corresponde movilidad, aunque en_planilla sea false');

select is(
  fn_persona_le_corresponde_movilidad('00000000-0000-0000-0000-000000335002'),
  false,
  'CRITERIO · un RxH sigue sin corresponderle — no se abrió de más');

-- ── 2 · Puerta admin: fn_documento_registrar ───────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000335013', true);

-- fn_hoy_lima(), no current_date: el servidor de CI corre en UTC, y entre
-- las 19:00 y la medianoche de Lima current_date ya vale "mañana" — la misma
-- trampa que el test 92 vigila en las funciones de public, pero que no
-- alcanza a un archivo de prueba. Ver 92_nadie_usa_current_date.test.sql.
select lives_ok(
  $$ select fn_documento_registrar('ruta', fn_hoy_lima(),
       '00000000-0000-0000-0000-000000335005', 'ruta de prueba', 10.00,
       null, false, null, 'documentos/prueba-335.jpg', null) $$,
  'REGISTRAR · admin sí puede registrar la ruta escaneada de una practicante');

select throws_ok(
  $$ select fn_documento_registrar('bono', fn_hoy_lima(),
       '00000000-0000-0000-0000-000000335005', null, null,
       2026, false, null, 'documentos/prueba-335-bono.jpg', null) $$,
  null, null,
  'BONO INTACTO · el bono de cumpleaños sigue exigiendo en_planilla — no se abrió de paso');

-- ── 3 · Puerta propia: fn_confirmar_mi_declaracion_ruta ────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000335011', true);

select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Los Olivos','Lima',1,1) $$,
  null, null,
  'RECHAZADO · todavía sin firma configurada, aunque ya le corresponda el trámite');

insert into firmas_escaneadas (persona_id, imagen, tipo)
values ('00000000-0000-0000-0000-000000335001', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen');

select lives_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Los Olivos','Lima',1,1) $$,
  'OK · con firma configurada, la practicante firma su propia declaración de ruta (sin costo propio, 0425/0426)');

-- ── 4 · Aparece donde tiene que aparecer ───────────────────────────────────
select is(
  (select estado from fn_documentos_tablero(true)),
  'ok',
  'AUTOCONSULTA · su propia fila pasa a ok, con la firma digital que acaba de dar');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000335013', true);
select is(
  (select estado from fn_documentos_tablero() where persona_id = '00000000-0000-0000-0000-000000335001'),
  'ok',
  'TABLERO ADMIN · ahora sí ve a la practicante, y en ok');

select is(
  (select count(*)::int from fn_documentos_tablero() where persona_id = '00000000-0000-0000-0000-000000335002'),
  0,
  'TABLERO ADMIN · el RxH sigue sin aparecer — el tablero no se abrió de más');

select * from finish();
rollback;
