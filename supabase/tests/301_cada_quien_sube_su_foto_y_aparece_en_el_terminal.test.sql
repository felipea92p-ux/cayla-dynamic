-- ============================================================================
-- 301_cada_quien_sube_su_foto_y_aparece_en_el_terminal.test.sql
-- ============================================================================
-- Defiende la 0381. Dos superficies distintas que tienen que estar de acuerdo:
-- storage.objects (quién puede SUBIR el archivo) y fn_actualizar_foto_perfil
-- (quién puede ENLAZARLO a una fila de `personas`) — y el terminal, que solo
-- debe poder LEER lo que ya está enlazado.
--
-- Las pruebas de storage.objects usan la forma real que Supabase Storage
-- ejecuta al subir/reemplazar (`insert … on conflict … do update … returning`,
-- ver la 136): un INSERT simple habría pasado con solo la política de INSERT y
-- escondido un rechazo real al reemplazar la foto.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000030100', 'ZZ301', 'Sede de prueba 301', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000301aa', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ana-301@prueba.local', 'x', now(), now(), now()),
  ('00000000-0000-0000-0000-0000000301bb', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ivo-301@prueba.local', 'x', now(), now(), now()),
  ('00000000-0000-0000-0000-0000000301cc', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin-301@prueba.local', 'x', now(), now(), now());

insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id)
values
  ('00000000-0000-0000-0000-000000030101', 'Ana', 'Prueba301',
   '00000000-0000-0000-0000-000000030100', 'integrante', 'activo', 'x',
   '00000000-0000-0000-0000-0000000301aa'),
  ('00000000-0000-0000-0000-000000030102', 'Ivo', 'Prueba301',
   '00000000-0000-0000-0000-000000030100', 'integrante', 'activo', 'x',
   '00000000-0000-0000-0000-0000000301bb'),
  ('00000000-0000-0000-0000-000000030103', 'Ada', 'Admin301',
   '00000000-0000-0000-0000-000000030100', 'admin', 'activo', 'x',
   '00000000-0000-0000-0000-0000000301cc');

set session_replication_role = replica;
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000003010e', '00000000-0000-0000-0000-000000030100',
        'Mac mini 301', true, '00000000-0000-0000-0000-00000003010f');
set session_replication_role = origin;

-- ── 1-3 · storage.objects: la subida real (insert … on conflict … do update) ─
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000301aa","role":"authenticated"}';

select lives_ok(
  $$ insert into storage.objects (name, owner, owner_id, bucket_id, metadata)
     values ('perfil/00000000-0000-0000-0000-000000030101/1.jpg',
             auth.uid(), auth.uid()::text, 'fotos-perfil', '{}'::jsonb)
     on conflict (name, bucket_id)
     do update set metadata = excluded.metadata, owner = excluded.owner,
                   owner_id = excluded.owner_id
     returning name $$,
  'SUBIR · Ana sube su propia foto');

select lives_ok(
  $$ insert into storage.objects (name, owner, owner_id, bucket_id, metadata)
     values ('perfil/00000000-0000-0000-0000-000000030101/1.jpg',
             auth.uid(), auth.uid()::text, 'fotos-perfil', '{}'::jsonb)
     on conflict (name, bucket_id)
     do update set metadata = excluded.metadata, owner = excluded.owner,
                   owner_id = excluded.owner_id
     returning name $$,
  'REEMPLAZAR · Ana vuelve a subir sobre la misma ruta (la salió movida)');

select throws_ok(
  $$ insert into storage.objects (name, owner, owner_id, bucket_id, metadata)
     values ('perfil/00000000-0000-0000-0000-000000030102/falsa.jpg',
             auth.uid(), auth.uid()::text, 'fotos-perfil', '{}'::jsonb)
     on conflict (name, bucket_id)
     do update set metadata = excluded.metadata, owner = excluded.owner,
                   owner_id = excluded.owner_id
     returning name $$,
  null, null,
  'BORDE · Ana no puede subir una foto a la carpeta de Ivo');

reset role;
reset request.jwt.claims;

-- ── 4 · Admin sí puede subir a la carpeta de cualquiera ─────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000301cc","role":"authenticated"}';

select lives_ok(
  $$ insert into storage.objects (name, owner, owner_id, bucket_id, metadata)
     values ('perfil/00000000-0000-0000-0000-000000030102/1.jpg',
             auth.uid(), auth.uid()::text, 'fotos-perfil', '{}'::jsonb)
     on conflict (name, bucket_id)
     do update set metadata = excluded.metadata, owner = excluded.owner,
                   owner_id = excluded.owner_id
     returning name $$,
  'ADMIN · Ada puede subirle la foto a Ivo, que nunca entró a Lo mío');

reset role;
reset request.jwt.claims;

-- ── 5-8 · fn_actualizar_foto_perfil: quién puede ENLAZAR la foto a la fila ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000301aa', true);
set role authenticated;

select lives_ok(
  $$ select fn_actualizar_foto_perfil('00000000-0000-0000-0000-000000030101',
                                       'perfil/00000000-0000-0000-0000-000000030101/1.jpg') $$,
  'ENLAZAR · Ana enlaza su propia foto');

reset role;

select is(
  (select foto_url from personas where id = '00000000-0000-0000-0000-000000030101'),
  'perfil/00000000-0000-0000-0000-000000030101/1.jpg',
  'GUARDADA · la ruta quedó en personas.foto_url');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000301aa', true);
set role authenticated;

select throws_ok(
  $$ select fn_actualizar_foto_perfil('00000000-0000-0000-0000-000000030102',
                                       'perfil/00000000-0000-0000-0000-000000030102/1.jpg') $$,
  'Solo puedes actualizar tu propia foto.',
  'BORDE · Ana no puede enlazar la foto de Ivo, aunque adivine la ruta exacta');

reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000301cc', true);
set role authenticated;

select lives_ok(
  $$ select fn_actualizar_foto_perfil('00000000-0000-0000-0000-000000030102',
                                       'perfil/00000000-0000-0000-0000-000000030102/1.jpg') $$,
  'ADMIN · Ada enlaza la foto que le subió a Ivo');

reset role;

-- ── 9 · Quitar la foto (null es un valor válido, no un error) ───────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000301aa', true);
set role authenticated;

select lives_ok(
  $$ select fn_actualizar_foto_perfil('00000000-0000-0000-0000-000000030101', null) $$,
  'QUITAR · Ana puede volver a dejar su foto en null');

reset role;

-- ── 10 · Defensa en profundidad: una ruta fuera del bucket nunca se guarda ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000301cc', true);
set role authenticated;

select throws_ok(
  $$ select fn_actualizar_foto_perfil('00000000-0000-0000-0000-000000030101',
                                       'comprobantes/otra-cosa.jpg') $$,
  'La ruta de la foto no pertenece al bucket de perfiles.',
  'DEFENSA · ni la propia admin puede enlazar una ruta de otro bucket');

reset role;

-- ── 11 · El terminal ve la foto de Ivo junto a su nombre ────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003010f', true);
set role authenticated;

select is(
  (select foto_url from terminal_roster where nombres = 'Ivo' limit 1),
  'perfil/00000000-0000-0000-0000-000000030102/1.jpg',
  'TERMINAL · la grilla de marcaje recibe la foto enlazada de Ivo');

reset role;
select * from finish();
rollback;
