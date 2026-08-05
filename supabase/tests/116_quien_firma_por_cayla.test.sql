-- ============================================================================
-- 116_quien_firma_por_cayla.test.sql
-- ============================================================================
-- Lo que este archivo defiende: que no exista forma de dejar `firmante_empresa`
-- apuntando a alguien que no puede firmar.
--
-- Importa porque el síntoma de un firmante mal puesto NO es un error: es un
-- documento impreso con el nombre de quien no corresponde, encima de la firma
-- de otra persona. Eso no lo detecta nadie mirando la pantalla — se detecta en
-- una inspección, con el papel en la mano.
--
-- Los tres estados que el trigger tiene que hacer imposibles:
--   · una persona que no existe
--   · una persona que ya cesó (las personas no se borran, se marcan inactivas)
--   · una cuenta sin permiso para firmar por la empresa
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000af00', 'ZZFIR', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-00000000af01', 'FirmaAdmin', 'Laboratorio',
   '00000000-0000-0000-0000-00000000af00', 'admin', 'test-hash',
   '00000000-0000-0000-0000-00000000af09');
set session_replication_role = origin;

-- Con fecha de cese porque el esquema no admite una persona inactiva sin ella
-- (`personas_cese_coherente`, de la 0086): «inactiva» y «cesó tal día» son la
-- misma cosa dicha dos veces, y no pueden contradecirse.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, estado, fecha_cese) values
  ('00000000-0000-0000-0000-00000000af02', 'FirmaCesada', 'Laboratorio',
   '00000000-0000-0000-0000-00000000af00', 'admin', 'test-hash', 'inactivo', '2026-06-30'),
  -- Una encargada de sede: firma las amonestaciones de SU tienda, y aun así no
  -- puede quedar como quien firma los documentos de toda la empresa. Es el caso
  -- que de verdad se puede confundir; una integrante nadie la pondría ahí.
  ('00000000-0000-0000-0000-00000000af03', 'FirmaEncargada', 'Laboratorio',
   '00000000-0000-0000-0000-00000000af00', 'supervisor_sede', 'test-hash', 'activo', null);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000af09', true);

-- ── 1 · Lo que SÍ se puede guardar ──────────────────────────────────────────
select lives_ok(
  $$ insert into configuracion (clave, valor)
     values ('firmante_empresa',
             jsonb_build_object('persona_id', '00000000-0000-0000-0000-00000000af01',
                                'cargo', 'Gerencia General')) $$,
  'VÁLIDO · una admin activa sí puede quedar como firmante');

select is(
  (select valor ->> 'cargo' from configuracion where clave = 'firmante_empresa'),
  'Gerencia General',
  'VÁLIDO · el cargo se guarda junto a la persona, en la misma fila');

-- ── 2 · Los tres estados imposibles ─────────────────────────────────────────
select throws_ok(
  $$ update configuracion
        set valor = jsonb_build_object('persona_id', '00000000-0000-0000-0000-0000000000ff',
                                       'cargo', 'Gerencia General')
      where clave = 'firmante_empresa' $$,
  null, null,
  'IMPOSIBLE · no se puede apuntar a una persona que no existe');

select throws_ok(
  $$ update configuracion
        set valor = jsonb_build_object('persona_id', '00000000-0000-0000-0000-00000000af02',
                                       'cargo', 'Gerencia General')
      where clave = 'firmante_empresa' $$,
  null, null,
  'IMPOSIBLE · no se puede apuntar a alguien que ya cesó');

select throws_ok(
  $$ update configuracion
        set valor = jsonb_build_object('persona_id', '00000000-0000-0000-0000-00000000af03',
                                       'cargo', 'Gerencia General')
      where clave = 'firmante_empresa' $$,
  null, null,
  'IMPOSIBLE · no se puede apuntar a una cuenta sin permiso para firmar');

select throws_ok(
  $$ update configuracion
        set valor = jsonb_build_object('cargo', 'Gerencia General')
      where clave = 'firmante_empresa' $$,
  null, null,
  'IMPOSIBLE · no se puede guardar un firmante sin persona');

-- Y tras los cuatro rechazos, la fila buena sigue intacta: un intento fallido
-- no puede dejar el sistema a medias.
select is(
  (select valor ->> 'persona_id' from configuracion where clave = 'firmante_empresa'),
  '00000000-0000-0000-0000-00000000af01',
  'INTACTA · ningún intento rechazado alcanzó a cambiar quién firma');

-- ── 3 · El trigger no estorba al resto de la configuración ──────────────────
-- Vive sobre `configuracion` entera, que guarda decenas de claves de negocio.
-- Si tocara alguna otra, esta migración habría roto media aplicación.
select lives_ok(
  $$ insert into configuracion (clave, valor)
     values ('clave_cualquiera_de_laboratorio', '{"lo que sea": 1}'::jsonb) $$,
  'AJENA · cualquier otra clave de configuración se guarda como siempre');

select * from finish();
rollback;
