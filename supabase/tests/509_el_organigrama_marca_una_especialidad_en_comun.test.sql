-- ============================================================================
-- 509 — El organigrama marca una especialidad en común (0624)
-- ============================================================================
--   · el distintivo se guarda y se lee;
--   · guardar sin mandarlo lo conserva (la web anterior no lo conoce);
--   · mandarlo vacío lo borra; uno demasiado largo se rechaza;
--   · queda UNA sola firma de la función, y sin sesión no se ejecuta.
-- Datos inventados, dentro de begin … rollback.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000050901', 'ZZORG2', 'Sede de laboratorio ORG2', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000050911', 'DisDo',  'Lab', '00000000-0000-0000-0000-000000050901', 'lider_do',   'x', '00000000-0000-0000-0000-000000050981', '2024-01-15', 'planilla'),
  ('00000000-0000-0000-0000-000000050912', 'DisInt', 'Lab', '00000000-0000-0000-0000-000000050901', 'integrante', 'x', null,                                   '2024-01-15', 'planilla');
set session_replication_role = origin;

create function pg_temp.distintivo() returns text language sql as $$
  select x->>'distintivo' from jsonb_array_elements(fn_organigrama()->'personas') x where x->>'nombres' = 'DisInt';
$$;
grant execute on function pg_temp.distintivo() to authenticated;

select is((select count(*)::int from pg_proc where proname = 'fn_organigrama_guardar' and pronamespace = 'public'::regnamespace),
  1, 'queda una sola firma de guardar');
select ok(not has_function_privilege('anon', 'fn_organigrama_guardar(uuid,text,int,text,text,text,boolean,int,int,text)', 'execute'),
  'sin sesión no se escribe');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000050981","role":"authenticated"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000050981', true);

select fn_organigrama_guardar('00000000-0000-0000-0000-000000050912', 'trujillo', 1, 'Atención al cliente',
  p_distintivo => 'Negocios internacionales');
select is(pg_temp.distintivo(), 'Negocios internacionales', 'el distintivo se guarda y se lee');

select fn_organigrama_guardar('00000000-0000-0000-0000-000000050912', 'trujillo', 2, 'Atención al cliente');
select is(pg_temp.distintivo(), 'Negocios internacionales', 'guardar sin mandarlo lo conserva');

select throws_ok(
  $$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050912', 'trujillo', 2, 'Atención', p_distintivo => repeat('x', 41)) $$,
  'P0001', 'El distintivo va de 2 a 40 letras.', 'uno demasiado largo se rechaza');
select is(pg_temp.distintivo(), 'Negocios internacionales', 'el rechazo no cambió nada');

select fn_organigrama_guardar('00000000-0000-0000-0000-000000050912', 'trujillo', 2, 'Atención al cliente', p_distintivo => '');
select is(pg_temp.distintivo(), null, 'vacío lo borra');

select * from finish();
rollback;
