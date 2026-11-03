-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 477_este_dia_no_me_calza.test.sql
-- ============================================================================
-- La 0587. Lo que importa: que ella pida solo lo suyo, de hoy a 21 días, sin
-- dos abiertos el mismo día; que le responda su líder de su sede, DO o admin —
-- nunca ella misma ni una líder de otra sede—; que «se mantiene» exija decir
-- por qué; que lo resuelto no se vuelva a resolver; que las 48 h se cuenten
-- igual para todos; que una compañera no vea lo de otra; que nadie escriba la
-- tabla sin las funciones; y que la Bandeja recuerde 'pedido_turno'.
-- ============================================================================
begin;
select plan(26);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000047700', 'ZZPDA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000047701', 'ZZPDB', 'Sede de laboratorio B', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, fecha_cese)
values
  ('00000000-0000-0000-0000-000000047710', 'PedAdmin', 'Lab', '00000000-0000-0000-0000-000000047700', 'admin', 'x',
   '00000000-0000-0000-0000-0000000477a0', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047711', 'PedLiderA', 'Lab', '00000000-0000-0000-0000-000000047700', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000477a1', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047712', 'PedLiderB', 'Lab', '00000000-0000-0000-0000-000000047701', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000477a2', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047713', 'PedX', 'Lab', '00000000-0000-0000-0000-000000047700', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000477a3', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047714', 'PedY', 'Lab', '00000000-0000-0000-0000-000000047700', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000477a4', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047715', 'PedCesada', 'Lab', '00000000-0000-0000-0000-000000047700', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000477a5', '2024-01-01', 'inactivo', '2026-01-31');
set session_replication_role = origin;

create temporary table _ids (clave text primary key, id uuid);
grant all on _ids to authenticated;

-- ── 1-7 · Ella pide ──────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a3', true);

insert into _ids select 'x1', fn_turno_pedido_crear(fn_hoy_lima() + 3, 'estudios', 'tarde', '  Tengo examen  ');

select is((select estado from turno_pedidos where id = (select id from _ids where clave = 'x1')),
  'abierto', 'lo que pide queda abierto');
select is((select comentario from turno_pedidos where id = (select id from _ids where clave = 'x1')),
  'Tengo examen', 'el comentario se guarda sin espacios de más');
select is((select persona_id from turno_pedidos where id = (select id from _ids where clave = 'x1')),
  '00000000-0000-0000-0000-000000047713'::uuid, 'el pedido es de quien lo hace, no de quien ella diga');

select throws_ok(format('select fn_turno_pedido_crear(%L, ''hijos'', ''manana'')', fn_hoy_lima() + 3),
  'P0001', 'Ya pediste ese día y tu líder todavía no te responde.', 'no hay dos abiertos para el mismo día');
select throws_ok(format('select fn_turno_pedido_crear(%L, ''hijos'', ''manana'')', fn_hoy_lima() - 1),
  'P0001', null, 'un día que ya pasó no se pide');
select throws_ok(format('select fn_turno_pedido_crear(%L, ''hijos'', ''manana'')', fn_hoy_lima() + 22),
  'P0001', null, 'más allá de 21 días, no');
select throws_ok(format('select fn_turno_pedido_crear(%L, ''viaje'', ''manana'')', fn_hoy_lima() + 4),
  'P0001', 'Elige el motivo.', 'el motivo es uno de los del catálogo');

-- 8 · el día 21 sí entra (el borde)
select lives_ok(format('insert into _ids select ''x21'', fn_turno_pedido_crear(%L, ''otro'', ''no_puede'')', fn_hoy_lima() + 21),
  'el día 21 todavía se puede pedir');

-- 9 · quien ya no está activa no pide
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a5', true);
select throws_ok(format('select fn_turno_pedido_crear(%L, ''otro'', ''tarde'')', fn_hoy_lima() + 2),
  'P0001', 'No autorizado.', 'quien ya no está activa no pide');

-- ── 10-11 · Retirar: solo ella y solo lo abierto ─────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a4', true);
select throws_ok(format('select fn_turno_pedido_retirar(%L)', (select id from _ids where clave = 'x21')),
  'P0001', null, 'una compañera no retira el pedido de otra');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a3', true);
select lives_ok(format('select fn_turno_pedido_retirar(%L)', (select id from _ids where clave = 'x21')),
  'ella retira el suyo');

-- ── 12-18 · Responder ────────────────────────────────────────────────────────
select throws_ok(format('select fn_turno_pedido_responder(%L, ''acepta'')', (select id from _ids where clave = 'x1')),
  'P0001', null, 'ella no se responde a sí misma');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a2', true);
select throws_ok(format('select fn_turno_pedido_responder(%L, ''acepta'')', (select id from _ids where clave = 'x1')),
  'P0001', null, 'una líder de otra sede no responde');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a1', true);
select throws_ok(format('select fn_turno_pedido_responder(%L, ''se_mantiene'', ''no'')', (select id from _ids where clave = 'x1')),
  'P0001', null, 'si el turno se mantiene, hay que decir por qué');
select throws_ok(format('select fn_turno_pedido_responder(%L, ''cambio_companera'', ''lo vemos'')', (select id from _ids where clave = 'x1')),
  'P0001', null, 'cambiar con una compañera queda para la entrega 4');
select throws_ok(format('select fn_turno_pedido_responder(%L, ''acepta'')', (select id from _ids where clave = 'x21')),
  'P0001', null, 'lo retirado ya no se responde');

select lives_ok(format('select fn_turno_pedido_responder(%L, ''se_mantiene'', ''Ese día hay inventario; lo vemos el lunes'')',
  (select id from _ids where clave = 'x1')), 'su líder de su sede responde');
select ok((select estado = 'resuelto' and resolucion = 'se_mantiene'
                  and resuelto_por = '00000000-0000-0000-0000-000000047711' and resuelto_at is not null
             from turno_pedidos where id = (select id from _ids where clave = 'x1')),
  'queda resuelto con quién, cuándo y qué');

-- 19 · lo resuelto no se vuelve a resolver (tampoco DO)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a0', true);
select throws_ok(format('select fn_turno_pedido_responder(%L, ''acepta'')', (select id from _ids where clave = 'x1')),
  'P0001', null, 'lo resuelto no se vuelve a resolver');

-- 20 · y se puede volver a pedir el mismo día una vez resuelto
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a3', true);
select lives_ok(format('insert into _ids select ''x2'', fn_turno_pedido_crear(%L, ''hijos'', ''manana'')', fn_hoy_lima() + 3),
  'resuelto el primero, el mismo día se puede volver a pedir');

-- 21 · admin (o DO) responde aunque no sea su sede, y «acepta» no exige texto
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a0', true);
select lives_ok(format('select fn_turno_pedido_responder(%L, ''acepta'')', (select id from _ids where clave = 'x2')),
  'admin responde; «acepta» no exige texto');

-- ── 22-23 · Las 48 horas ─────────────────────────────────────────────────────
select is(fn_turno_pedido_con_do(now() - interval '47 hours 59 minutes', 'abierto'), false, 'a las 47:59 sigue con su líder');
select is(fn_turno_pedido_con_do(now() - interval '48 hours', 'abierto') and not fn_turno_pedido_con_do(now() - interval '72 hours', 'resuelto'),
  true, 'a las 48 h pasa a DO; lo resuelto no pasa a nadie');

-- ── 24-25 · RLS y escritura directa ──────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a4', true);
select is((select count(*)::int from turno_pedidos where persona_id = '00000000-0000-0000-0000-000000047713'),
  0, 'una compañera no ve los pedidos de otra');
select throws_ok($$insert into turno_pedidos (persona_id, fecha, motivo, propuesta)
                   values ('00000000-0000-0000-0000-000000047714', current_date + 2, 'otro', 'tarde')$$,
  '42501', null, 'nadie escribe la tabla sin las funciones');
reset role;

-- ── 26 · La Bandeja recuerda 'pedido_turno' ──────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000477a3', true);
select lives_ok(format('select fn_bandeja_marcar_visto(''pedido_turno'', %L)', (select id from _ids where clave = 'x1')),
  'la Bandeja acepta marcar visto un pedido respondido');

select * from finish();
rollback;
