-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 334_la_declaracion_de_ruta_se_firma_sin_escaneo.test.sql — 0423
-- ============================================================================
-- Dos cosas se defienden acá, y las dos importan más que "la función inserta
-- una fila":
--
--   1. QUE SIGA SIENDO EL MISMO PORTERO. `fn_confirmar_mi_declaracion_ruta`
--      exige lo mismo que ya exigía `fn_documento_registrar` (0211) para una
--      ruta individual: en planilla, activa. Alguien fuera de planilla (un
--      RxH) no cobra movilidad y no tiene nada que declarar — si esta función
--      lo dejara pasar, sería una segunda puerta con un criterio distinto al
--      de la puerta de siempre.
--
--   2. QUE NADIE VEA LA FILA DE OTRA. `fn_documentos_tablero(p_solo_mi_fila =>
--      true)` es la pieza más delicada de la 0423: relaja un `where` que antes
--      solo dejaba pasar a admin/líder. Si el aislamiento fallara, alguien
--      abriendo /mio/movilidad vería el estado de una compañera, o —peor— un
--      admin abriendo SU PROPIA pantalla seguiría viendo a todo el equipo en
--      vez de solo la suya.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000334000', 'ZZ334', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id) values
  -- En planilla, en la sede REAL de Trujillo (no la de laboratorio): así el
  -- cálculo de la tarifa pasa por parametros_laborales de verdad (S/10.00),
  -- no por una sede sin ninguna fila que dejaría el monto en 0.
  ('00000000-0000-0000-0000-000000334001', 'Prueba', 'Firmante',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000334011'),
  ('00000000-0000-0000-0000-000000334002', 'Prueba', 'OtraPersona',
   (select id from sedes where codigo = 'AQP'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000334012'),
  ('00000000-0000-0000-0000-000000334003', 'Prueba', 'FueraDePlanilla',
   '00000000-0000-0000-0000-000000334000', 'integrante', 'test-hash', 'rxh',
   '00000000-0000-0000-0000-000000334013'),
  ('00000000-0000-0000-0000-000000334004', 'Prueba', 'Admin',
   '00000000-0000-0000-0000-000000334000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000334014');
set session_replication_role = origin;

-- ── 1 · La misma puerta que ya exigía fn_documento_registrar ───────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000334013', true);
select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Los Olivos','Lima',2,2,2.50,false,null,null) $$,
  null, null,
  'RECHAZADO · fuera de planilla no tiene declaración que firmar, igual que en fn_documento_registrar');

-- ── 2 · Sin firma guardada, tampoco hay firma que confirmar ────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000334011', true);
select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Los Olivos','Lima',2,2,2.50,false,null,null) $$,
  null, null,
  'RECHAZADO · todavía no configuró su firma en firmas_escaneadas');

insert into firmas_escaneadas (persona_id, imagen, tipo)
values ('00000000-0000-0000-0000-000000334001', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen');

-- ── 3 · Dice que usa taxi pero no dice cuánto le cuesta ────────────────────
select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Los Olivos','Lima',2,2,2.50,true,null,null) $$,
  null, null,
  'RECHAZADO · usa_taxi en true exige su costo y su frecuencia');

-- ── 4 · Firma su declaración, con todo en regla ─────────────────────────────
select lives_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Los Olivos','Lima',2,2,2.50,true,8.00,3) $$,
  'OK · en planilla, activa, con firma guardada: la declaración se registra');

select is(
  (select monto_declarado from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000334001' and tipo = 'ruta'),
  10.00::numeric,
  'MONTO · lo calcula el servidor con la tarifa de TRU (0142), nunca lo que mande quien firma');

select is(
  (select fecha_firma from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000334001' and tipo = 'ruta'),
  fn_hoy_lima(),
  'FECHA · la firma digital fecha con el día de hoy en Lima');

select ok(
  (select firma_persona_confirmada_at is not null from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000334001' and tipo = 'ruta'),
  'EVIDENCIA · queda la imagen y el instante exacto de la firma digital');

select is(
  (select ruta_declarada like '%Los Olivos%' from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000334001' and tipo = 'ruta'),
  true,
  'TEXTO · compone el mismo tipo de declaración que hoy se escribe a mano en el papel');

-- ── 5 · Su propio estado, vía fn_documentos_tablero(p_solo_mi_fila => true) ─
select is(
  (select estado from fn_documentos_tablero(true)),
  'ok',
  'AUTOCONSULTA · su propia fila pasa de sin_ruta a ok');

select ok(
  (select ruta_firma_persona_confirmada_at is not null from fn_documentos_tablero(true)),
  'AUTOCONSULTA · el tablero distingue que fue firma digital, no escaneo');

-- ── 6 · El aislamiento — la parte más delicada de esta migración ──────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000334012', true);
select is(
  (select count(*)::int from fn_documentos_tablero(true)),
  1,
  'AISLADA · OtraPersona ve exactamente UNA fila con p_solo_mi_fila => true: la suya, nunca la de Firmante');
select is(
  (select estado from fn_documentos_tablero(true)),
  'sin_ruta',
  'AISLADA · y esa fila es la suya propia (sin_ruta), no el ok de Firmante');

-- ── 7 · Un admin en SU PROPIA pantalla también ve solo la suya ─────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000334014', true);
select is(
  (select count(*)::int from fn_documentos_tablero(true)),
  1,
  'ADMIN AUTOCONSULTA · con p_solo_mi_fila => true, un admin ve solo SU fila — no todo el equipo');

-- ── 8 · Y sin el argumento, admin sigue viendo a todo el mundo, como siempre ─
select cmp_ok(
  (select count(*)::int from fn_documentos_tablero()),
  '>=', 2,
  'ADMIN TABLERO · sin p_solo_mi_fila, sigue viendo a todo el equipo en planilla, exactamente como antes de la 0423');

select * from finish();
rollback;
