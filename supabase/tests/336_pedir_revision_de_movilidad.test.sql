-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 336_pedir_revision_de_movilidad.test.sql — 0425
-- ============================================================================
-- Defiende el ciclo completo que reemplaza a "Declarar de nuevo": una vez
-- vigente, la única puerta que le queda a la persona es pedir revisión, y esa
-- revisión tiene que llegarle a admin/líder (no a cualquiera) sin que se
-- dupliquen filas por pedir dos veces antes de que la atiendan.
--
-- Copia el molde de `revisiones_pedidas` (0257) a propósito: mismos tres
-- verbos (pedir, listar, atender), mismo criterio de visibilidad
-- (`fn_es_admin_o_lider()`, sin dirigir el aviso a una persona puntual — ver
-- el encabezado de la 0425 sobre por qué no se inventa un mecanismo nuevo).
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000336000', 'ZZ336', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id) values
  ('00000000-0000-0000-0000-000000336001', 'Prueba', 'Firmante336',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000336011'),
  ('00000000-0000-0000-0000-000000336002', 'Prueba', 'OtraPersona336',
   (select id from sedes where codigo = 'AQP'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000336012'),
  ('00000000-0000-0000-0000-000000336003', 'Prueba', 'Admin336',
   '00000000-0000-0000-0000-000000336000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000336013');
set session_replication_role = origin;

insert into firmas_escaneadas (persona_id, imagen, tipo)
values ('00000000-0000-0000-0000-000000336001', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000336011', true);
select fn_confirmar_mi_declaracion_ruta('Los Olivos','Lima',1,1,2.50);

-- ── 1 · El candado: vigente y al día, ya no se firma sola ──────────────────
select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Otro Distrito','Lima',1,1,2.50) $$,
  null, null,
  'CANDADO · con declaración vigente y al día, la única puerta que queda es pedir revisión');

-- ── 2 · Pedir revisión: valida el motivo ────────────────────────────────────
select throws_ok(
  $$ select fn_pedir_revision_movilidad('mm') $$,
  null, null,
  'RECHAZADO · el motivo necesita al menos 5 caracteres, igual que revisiones_pedidas (0257)');

select lives_ok(
  $$ select fn_pedir_revision_movilidad('Me mudé de distrito la semana pasada') $$,
  'OK · con un motivo real, queda pedida');

-- ── 3 · Un no-admin no puede atender, aunque conozca el id ─────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000336012', true);
select throws_ok(
  $$ select fn_atender_revision_movilidad(
       (select id from movilidad_revisiones_pedidas
         where persona_id = '00000000-0000-0000-0000-000000336001' limit 1),
       'me la adjudico') $$,
  null, null,
  'RECHAZADO · solo admin/líder puede atender una revisión de movilidad');

-- ── 4 · Ese no-admin tampoco ve la solicitud ajena en el listado ───────────
select is(
  (select fn_movilidad_revisiones_pedidas(true)),
  '[]'::jsonb,
  'AISLADA · quien no es admin ni es la dueña de la solicitud no ve nada');

-- ── 5 · Admin sí la ve, con nombre y sede ya resueltos ─────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000336013', true);
select is(
  (select jsonb_array_length(fn_movilidad_revisiones_pedidas(true))),
  1,
  'ADMIN · ve exactamente una solicitud pendiente');

select is(
  (select fn_movilidad_revisiones_pedidas(true)->0->>'nombre'),
  'Prueba Firmante336',
  'ADMIN · el nombre viene resuelto, no un uuid a secas');

select is(
  (select fn_movilidad_revisiones_pedidas(true)->0->>'sede'),
  'TRU',
  'ADMIN · la sede también viene resuelta');

-- ── 6 · Pedir de nuevo ANTES de que la atiendan reabre la misma fila ───────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000336011', true);
select fn_pedir_revision_movilidad('En realidad fue hace dos semanas');
select is(
  (select count(*)::int from movilidad_revisiones_pedidas
    where persona_id = '00000000-0000-0000-0000-000000336001'),
  1,
  'REABRE · pedir dos veces sin respuesta todavía es UNA sola fila, no dos');

-- ── 7 · Admin atiende, con una respuesta ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000336013', true);
select lives_ok(
  $$ select fn_atender_revision_movilidad(
       (select id from movilidad_revisiones_pedidas
         where persona_id = '00000000-0000-0000-0000-000000336001' limit 1),
       'Anotado, gracias por avisar') $$,
  'OK · admin atiende sin problema');

select is(
  (select fn_movilidad_revisiones_pedidas(true)),
  '[]'::jsonb,
  'ATENDIDA · ya no aparece entre las pendientes');

-- ── 8 · Y pedir OTRA vez, ya atendida la anterior, crea una fila NUEVA ─────
-- (no se pierde el historial de la que ya se resolvió).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000336011', true);
select fn_pedir_revision_movilidad('Ahora cambié de ruta otra vez');
select is(
  (select count(*)::int from movilidad_revisiones_pedidas
    where persona_id = '00000000-0000-0000-0000-000000336001'),
  2,
  'HISTORIAL · una solicitud nueva tras la anterior atendida no borra la que ya se resolvió');

select * from finish();
rollback;
