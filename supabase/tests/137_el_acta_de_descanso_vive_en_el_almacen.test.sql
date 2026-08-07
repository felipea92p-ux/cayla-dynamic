-- ============================================================================
-- 137_el_acta_de_descanso_vive_en_el_almacen.test.sql
-- ============================================================================
-- Hasta la 0175 el acta firmada de un descanso sustitutorio se guardaba como
-- TEXTO dentro de una columna, y por eso tenía que caber en ~3 MB. Ese tope no
-- era una decisión sobre las actas: era la consecuencia de dónde vivían. Un
-- escaneo de varias hojas no cabía, y la única salida era degradar el papel
-- que justamente hay que poder leer después.
--
-- Ahora va al almacén, con los mismos 50 MB que el cargo de un memo o un
-- contrato. Lo que esta prueba sostiene:
--
--   1. Las actas que YA estaban subidas se siguen leyendo. No se migró ningún
--      dato a propósito — un script de migración de archivos puede quedarse a
--      medias, y lo que estaba guardado el viernes tiene que abrirse el lunes.
--   2. Un acta nunca tiene el papel en los dos sitios. Si lo tuviera, cuál es
--      el bueno dependería del orden de un `coalesce`: una decisión de negocio
--      escondida en un detalle de implementación.
--   3. La lista dice la verdad sobre si hay archivo, venga de donde venga. Si
--      mirara solo la columna vieja, un acta recién subida al almacén saldría
--      como «sin acta» y alguien la subiría dos veces.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('cc000000-0000-0000-0000-0000000000c7', 'ZZA', 'Sede de prueba', true, 'tienda');
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('aa000000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'admin-137@prueba.local', 'x', now(), now(), now());
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id)
values ('a1000000-0000-0000-0000-00000000001c', 'Ada', 'Admin',
        'cc000000-0000-0000-0000-0000000000c7', 'admin', 'activo', 'x',
        'aa000000-0000-0000-0000-0000000000a7');

-- ── 1 · Un acta no puede tener el papel en los dos sitios ───────────────────
select throws_ok(
  $$ insert into actas_descanso_sustitutorio (referencia, archivo_base64, storage_path)
     values ('Acta imposible 137', 'data:application/pdf;base64,QUJD', 'x/y.pdf') $$,
  null, null,
  'ESTADO IMPOSIBLE · el papel no puede estar en la base y en el almacén a la vez');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aa000000-0000-0000-0000-0000000000a7","role":"authenticated"}';

-- ── 2 y 3 · Un acta nueva: va al almacén y la lista la ve ───────────────────
select lives_ok(
  $$ select fn_registrar_acta_descanso('Acta nueva 137', 'acta-nueva-137/1.pdf', 'escaneo.pdf') $$,
  'SUBIR · un acta nueva se anota contra su ruta del almacén');

select is(
  (select storage_path from actas_descanso_sustitutorio where referencia = 'Acta nueva 137'),
  'acta-nueva-137/1.pdf',
  'DÓNDE ESTÁ · fn_acta_descanso_ubicacion sabe buscarla en el almacén');

select is(
  (select tiene_archivo from fn_actas_descanso() where referencia = 'Acta nueva 137'),
  true,
  'LA LISTA · un acta del almacén NO sale como «sin acta subida»');

-- ── 4 · Reemplazarla deja una sola ruta, no dos filas ───────────────────────
select is(
  (select count(*)::int from (
     select fn_registrar_acta_descanso('Acta nueva 137', 'acta-nueva-137/2.pdf', 'corregido.pdf')
   ) x, actas_descanso_sustitutorio a where a.referencia = 'Acta nueva 137'),
  1,
  'REEMPLAZAR · volver a subirla actualiza el acta, no crea otra');

reset role;
reset request.jwt.claims;

-- ── 5 · Y las que ya estaban, se siguen leyendo donde están ─────────────────
-- Se inserta como lo hacía `fn_subir_acta_descanso` antes de la 0175.
insert into actas_descanso_sustitutorio (referencia, archivo_base64, archivo_nombre, subida_por)
values ('Acta vieja 137', 'data:application/pdf;base64,QUJDREVG', 'vieja.pdf',
        'a1000000-0000-0000-0000-00000000001c');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aa000000-0000-0000-0000-0000000000a7","role":"authenticated"}';

select is(
  (select tiene_archivo from fn_actas_descanso() where referencia = 'Acta vieja 137'),
  true,
  'LO YA SUBIDO · un acta guardada antes de la 0175 se sigue viendo');

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
