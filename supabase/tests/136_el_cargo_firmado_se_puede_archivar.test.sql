-- ============================================================================
-- 136_el_cargo_firmado_se_puede_archivar.test.sql
-- ============================================================================
-- Subir el cargo firmado de un memo disciplinario NUNCA funcionó, desde que el
-- módulo existe (mig. 0074) hasta el 2026-08-06. Los tres memos entregados de
-- producción llevaban semanas con «sin el papel archivado» al lado, y no era
-- descuido de nadie: la base rechazaba el archivo con «new row violates
-- row-level security policy».
--
-- LA CAUSA, que ninguna prueba podía ver. Supabase Storage escribe el objeto
-- con `INSERT … ON CONFLICT DO UPDATE … RETURNING *`, no con un INSERT a secas.
-- Esa forma necesita tres permisos: INSERT por la fila nueva, SELECT por el
-- RETURNING, y UPDATE por el ON CONFLICT. Faltaban dos:
--
--   · No había política de UPDATE en ningún bucket.
--   · La política de SELECT de `expedientes` exigía que el adjunto YA estuviera
--     registrado en `expediente_adjuntos`… y ese registro se crea DESPUÉS de
--     subir el archivo. Un círculo cerrado.
--
-- POR QUÉ ESTA PRUEBA. El fallo era invisible desde el código: la función de
-- permiso (`fn_expediente_puede_adjuntar`) devolvía `true` mientras la fila se
-- rechazaba, así que leer las políticas no bastaba para verlo — hubo que
-- ejecutar la sentencia real. Esta prueba ejecuta esa misma sentencia. Si
-- alguien vuelve a tocar las políticas de `storage.objects`, se entera acá y no
-- el día que haga falta el papel para defenderse en una inspección.
--
-- Las cuatro afirmaciones cubren el ciclo entero y sus dos bordes:
--   1. subir el papel por primera vez
--   2. reemplazarlo (escaneo corregido)
--   3. volver a leerlo una vez registrado
--   4. y que nada de esto lo pueda hacer quien no tiene mando sobre el memo
-- ============================================================================
begin;
select plan(4);

-- ── Montaje ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo)
values ('cc000000-0000-0000-0000-0000000000cc', 'ZZT', 'Sede de prueba', true, 'tienda');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('aa000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'admin-136@prueba.local', 'x', now(), now(), now()),
       ('bb000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'integrante-136@prueba.local', 'x', now(), now(), now());

insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id)
values ('a1000000-0000-0000-0000-00000000001a', 'Ada', 'Admin',
        'cc000000-0000-0000-0000-0000000000cc', 'admin', 'activo', 'x',
        'aa000000-0000-0000-0000-0000000000aa'),
       ('b1000000-0000-0000-0000-00000000001b', 'Rosa', 'Integrante',
        'cc000000-0000-0000-0000-0000000000cc', 'integrante', 'activo', 'x',
        'bb000000-0000-0000-0000-0000000000bb');

-- Un memo ya entregado al que le falta el papel: el caso exacto de producción.
insert into expediente_disciplinario (
  id, persona_id, tipo_causal, nivel, estado, creado_por,
  firmado_at, firmante_id, correlativo, entregado_at, medio_entrega)
values ('d1000000-0000-0000-0000-00000000001d', 'b1000000-0000-0000-0000-00000000001b',
        'tardanza', 'amonestacion', 'entregado', 'a1000000-0000-0000-0000-00000000001a',
        now() - interval '2 days', 'a1000000-0000-0000-0000-00000000001a',
        'T-01/9999-2026-CAYLA', now() - interval '2 days', 'fisico');

-- Las sentencias de abajo son la que Storage 1.65.1 ejecuta de verdad, copiada
-- de su log: `INSERT … ON CONFLICT DO UPDATE … RETURNING`. Se prueba esa forma
-- exacta y no un INSERT simple porque el INSERT simple pasaba mientras el
-- sistema no funcionaba — la diferencia entre ambos ES el bug.

-- ── Como la admin, que sí tiene mando sobre el memo ─────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"aa000000-0000-0000-0000-0000000000aa","role":"authenticated"}';

select lives_ok(
  $$ insert into storage.objects (name, owner, owner_id, bucket_id, metadata)
     values ('d1000000-0000-0000-0000-00000000001d/cargo-1.heic',
             auth.uid(), auth.uid()::text, 'expedientes', '{}'::jsonb)
     on conflict (name, bucket_id)
     do update set metadata = excluded.metadata, owner = excluded.owner,
                   owner_id = excluded.owner_id
     returning name $$,
  'SUBIR · el cargo de un memo entregado entra al almacén');

-- Reemplazar: el escaneo salió movido y se vuelve a subir sobre la misma ruta.
-- Sin política de UPDATE esto se rechaza y corregir un papel sería imposible.
select lives_ok(
  $$ insert into storage.objects (name, owner, owner_id, bucket_id, metadata)
     values ('d1000000-0000-0000-0000-00000000001d/cargo-1.heic',
             auth.uid(), auth.uid()::text, 'expedientes', '{}'::jsonb)
     on conflict (name, bucket_id)
     do update set metadata = excluded.metadata, owner = excluded.owner,
                   owner_id = excluded.owner_id
     returning name $$,
  'REEMPLAZAR · volver a subir sobre la misma ruta corrige el escaneo');

reset role;
reset request.jwt.claims;

-- Registrado el adjunto (lo que hace fn_expediente_adjuntar), el papel tiene
-- que seguir siendo legible: de nada sirve archivarlo si después no se abre.
insert into expediente_adjuntos (documento_id, storage_path, tipo, subido_por)
values ('d1000000-0000-0000-0000-00000000001d',
        'd1000000-0000-0000-0000-00000000001d/cargo-1.heic', 'cargo_firmado',
        'a1000000-0000-0000-0000-00000000001a');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aa000000-0000-0000-0000-0000000000aa","role":"authenticated"}';

select isnt_empty(
  $$ select name from storage.objects
      where name = 'd1000000-0000-0000-0000-00000000001d/cargo-1.heic' $$,
  'LEER · el cargo archivado se puede volver a abrir');

reset role;
reset request.jwt.claims;

-- ── Y el borde que importa: nadie sube papeles a un expediente ajeno ────────
-- Sin esto, "arreglar" el círculo abriendo la política de más pasaría la prueba
-- igual. La integrante del memo no puede colgarle nada a su propio expediente.
set local role authenticated;
set local request.jwt.claims = '{"sub":"bb000000-0000-0000-0000-0000000000bb","role":"authenticated"}';

select throws_ok(
  $$ insert into storage.objects (name, owner, owner_id, bucket_id, metadata)
     values ('d1000000-0000-0000-0000-00000000001d/falsificado.heic',
             auth.uid(), auth.uid()::text, 'expedientes', '{}'::jsonb)
     on conflict (name, bucket_id)
     do update set metadata = excluded.metadata, owner = excluded.owner,
                   owner_id = excluded.owner_id
     returning name $$,
  null, null,
  'BORDE · quien no tiene mando sobre el memo no puede colgarle un papel');

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
