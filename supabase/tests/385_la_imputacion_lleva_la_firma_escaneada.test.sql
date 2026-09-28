-- ============================================================================
-- 385_la_imputacion_lleva_la_firma_escaneada.test.sql
-- ============================================================================
-- La imputación de cargos es el documento que abre la puerta a un despido, y
-- hasta la 0487 salía SIEMPRE con la raya en blanco: `fn_firma_de_memo` solo
-- entregaba la firma escaneada de verbal, amonestación y suspensión. Quien la
-- firma tenía que imprimirla, firmarla a mano y —si la quería en el sistema—
-- volver a escanearla, y al ver la raya vacía creía que el sistema había
-- fallado (2026-09-27: no era una falla, era una regla vieja que nadie le había
-- dicho).
--
-- La 0487 la deja pasar. Esta prueba fija las dos mitades: que la imputación
-- firmada ya sale con su rúbrica, y que NADA MÁS se abrió por el camino — ni el
-- borrador, ni la carta de despido, ni una persona sin derecho a verla.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000bd00', 'ZZIMP', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000bd01', 'ImputAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000bd00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000bd09');
set session_replication_role = origin;

-- La persona a la que van dirigidos los documentos.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-00000000bd02', 'ImputPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000bd00', 'test-hash');

-- Alguien ajeno: sin rol de gestión y sin ser la persona del documento.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000bd03', 'ImputAjena', 'Laboratorio',
        '00000000-0000-0000-0000-00000000bd00', 'test-hash',
        '00000000-0000-0000-0000-00000000bd08');
set session_replication_role = origin;

-- La firma escaneada de quien suscribe.
insert into firmas_escaneadas (persona_id, imagen)
values ('00000000-0000-0000-0000-00000000bd01',
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000bd09', true);

-- Cuatro documentos que difieren solo en lo que se prueba:
--   bd11 imputación firmada · bd12 imputación en borrador ·
--   bd13 despido firmado    · bd14 amonestación firmada (el control)
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, correlativo, firmante_id, firmado_at, creado_por) values
  ('00000000-0000-0000-0000-00000000bd11', '00000000-0000-0000-0000-00000000bd02',
   'tardanza', 'imputacion', 'firmado', 'ZZ-IMP-0001',
   '00000000-0000-0000-0000-00000000bd01', '2026-08-01T10:00:00-05:00',
   '00000000-0000-0000-0000-00000000bd01'),
  ('00000000-0000-0000-0000-00000000bd12', '00000000-0000-0000-0000-00000000bd02',
   'tardanza', 'imputacion', 'borrador', null,
   '00000000-0000-0000-0000-00000000bd01', null,
   '00000000-0000-0000-0000-00000000bd01'),
  ('00000000-0000-0000-0000-00000000bd13', '00000000-0000-0000-0000-00000000bd02',
   'tardanza', 'despido', 'firmado', 'ZZ-DES-0001',
   '00000000-0000-0000-0000-00000000bd01', '2026-08-02T10:00:00-05:00',
   '00000000-0000-0000-0000-00000000bd01'),
  ('00000000-0000-0000-0000-00000000bd14', '00000000-0000-0000-0000-00000000bd02',
   'tardanza', 'amonestacion', 'firmado', 'ZZ-AMO-0001',
   '00000000-0000-0000-0000-00000000bd01', '2026-08-03T10:00:00-05:00',
   '00000000-0000-0000-0000-00000000bd01');

-- ── Lo que cambia ───────────────────────────────────────────────────────────
select isnt(
  (select fn_firma_de_memo('00000000-0000-0000-0000-00000000bd11')),
  null::text,
  'IMPUTACIÓN firmada · sale con la firma escaneada de quien la suscribe');

select ok(
  (select fn_firma_de_memo('00000000-0000-0000-0000-00000000bd11')) like 'data:image/%',
  'IMPUTACIÓN firmada · y lo que entrega es la imagen de la firma, no otra cosa');

-- ── Lo que NO debe cambiar ──────────────────────────────────────────────────
select is(
  (select fn_firma_de_memo('00000000-0000-0000-0000-00000000bd12')),
  null::text,
  'IMPUTACIÓN en borrador · sigue sin rúbrica (la regla de la 0148 no se aflojó)');

select is(
  (select fn_firma_de_memo('00000000-0000-0000-0000-00000000bd13')),
  null::text,
  'DESPIDO firmado · la carta de despido sigue sin firma escaneada (la firma Gerencia a mano)');

select isnt(
  (select fn_firma_de_memo('00000000-0000-0000-0000-00000000bd14')),
  null::text,
  'AMONESTACIÓN firmada · el control: lo que ya funcionaba sigue funcionando');

-- Quien no gestiona ni es la persona del documento no se lleva la imagen de la
-- firma por más que el documento sea de un nivel que ahora la estampa.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000bd08', true);
select is(
  (select fn_firma_de_memo('00000000-0000-0000-0000-00000000bd11')),
  null::text,
  'IMPUTACIÓN firmada · una persona ajena al documento no puede pedir la firma');

select * from finish();
rollback;
