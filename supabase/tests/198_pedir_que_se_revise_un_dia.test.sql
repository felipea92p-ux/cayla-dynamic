-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 198_pedir_que_se_revise_un_dia.test.sql — la 0257 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que se pueda pedir una revisión: eso es un
-- insert. Es que UNA PERSONA NO PUEDA HABLAR POR OTRA, que reabrir borre la
-- respuesta vieja —si no, quedaría contestada una pregunta que ya cambió—, y
-- que nadie pueda cerrar la petición de una sede que no es la suya.
--
-- Y una que parece de forma y no lo es: que no se pueda pedir revisión de un día
-- futuro. Sin ese freno, cualquiera podría llenar la lista de su encargada de
-- días que todavía no han pasado.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000d9701', 'ZZR01', 'Sede propia', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000d9702', 'ZZR02', 'Sede ajena', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000da001', 'RevAdmin', 'Lab',
   '00000000-0000-0000-0000-0000000d9701', 'admin', 'x',
   '00000000-0000-0000-0000-0000000db001', '2024-01-01'),
  ('00000000-0000-0000-0000-0000000da002', 'RevEncargada', 'Lab',
   '00000000-0000-0000-0000-0000000d9701', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000db002', '2024-01-01'),
  ('00000000-0000-0000-0000-0000000da003', 'RevPropia', 'Lab',
   '00000000-0000-0000-0000-0000000d9701', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000db003', '2024-01-01'),
  ('00000000-0000-0000-0000-0000000da004', 'RevAjena', 'Lab',
   '00000000-0000-0000-0000-0000000d9702', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000db004', '2024-01-01'),
  -- Encargada de la OTRA sede: la que no debe poder cerrar lo que no es suyo.
  ('00000000-0000-0000-0000-0000000da005', 'RevEncargadaAjena', 'Lab',
   '00000000-0000-0000-0000-0000000d9702', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000db005', '2024-01-01');
set session_replication_role = origin;

-- ── Ella pide que se revise un día suyo ─────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000db003', true);

select lives_ok(
  $$ select fn_pedir_revision(fn_hoy_lima() - 2, 'Ese día sí vine, marqué la entrada y la salida no me tomó.') $$,
  'una integrante puede pedir que se revise un día suyo'
);

select is(
  (select count(*)::int from revisiones_pedidas
   where persona_id = '00000000-0000-0000-0000-0000000da003'),
  1,
  'y queda una fila, a su nombre'
);

-- La fecha futura. No es una validación de formulario: sin esto se puede llenar
-- la lista de la encargada con días que no han pasado.
select throws_ok(
  $$ select fn_pedir_revision(fn_hoy_lima() + 1, 'Mañana seguro me sale mal.') $$,
  'No se puede pedir revisión de un día que todavía no pasó.',
  'no se puede pedir revisión de un día futuro'
);

select throws_ok(
  $$ select fn_pedir_revision(fn_hoy_lima() - 1, 'ups') $$,
  'Cuéntanos qué pasó ese día, aunque sea en una línea.',
  'sin comentario de verdad no se registra nada'
);

-- ── Nadie habla por nadie ───────────────────────────────────────────────────
-- No hay forma de pedir revisión «para otra persona»: la función no acepta un
-- persona_id. Lo que sí hay que probar es que la de la otra sede no VEA esto.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000db004', true);

-- ⚠ `set role authenticated` NO es decorativo. pgTAP corre como `postgres`, que
-- es superusuario y SE SALTA LA RLS: sin esta línea la consulta devuelve la fila
-- de la compañera y la prueba «pasa» por el motivo equivocado — o falla por el
-- motivo equivocado, que fue lo que pasó al escribirla. La policy solo existe
-- para `authenticated`, así que hay que preguntar siendo `authenticated`.
set local role authenticated;
select is(
  (select count(*)::int from revisiones_pedidas),
  0,
  'otra integrante no ve la petición de su compañera'
);
reset role;

select is(
  (select jsonb_array_length(fn_revisiones_pedidas(true))),
  0,
  'ni a través de la función que lee el panel'
);

-- ── La encargada de OTRA sede no puede cerrarla ─────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000db005', true);

select throws_ok(
  format($$ select fn_atender_revision(%L, 'Ya lo vi.') $$,
         (select id from revisiones_pedidas
          where persona_id = '00000000-0000-0000-0000-0000000da003')),
  'Solo un administrador, un líder o la encargada de esa sede puede atender una revisión.',
  'la encargada de otra sede no puede atender una revisión que no es de su gente'
);

-- ── La encargada de SU sede sí ──────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000db002', true);

select is(
  (select jsonb_array_length(fn_revisiones_pedidas(true))),
  1,
  'la encargada de su sede sí la ve pendiente'
);

select lives_ok(
  format($$ select fn_atender_revision(%L, 'Corregido: te puse la salida real.') $$,
         (select id from revisiones_pedidas
          where persona_id = '00000000-0000-0000-0000-0000000da003')),
  'y puede atenderla'
);

select is(
  (select jsonb_array_length(fn_revisiones_pedidas(true))),
  0,
  'atendida, deja de estar pendiente'
);

-- ── Reabrir borra la respuesta vieja ────────────────────────────────────────
-- Si no, quedaría contestada una pregunta que ya cambió: quien la lea vería una
-- respuesta que no responde a lo que ahora dice el comentario.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000db003', true);
select fn_pedir_revision(fn_hoy_lima() - 2, 'Sigue mal: la salida que pusieron no es la mía.');

select is(
  (select respuesta from revisiones_pedidas
   where persona_id = '00000000-0000-0000-0000-0000000da003'),
  null,
  'volver a pedirla borra la respuesta anterior y la deja pendiente otra vez'
);

select * from finish();
rollback;
