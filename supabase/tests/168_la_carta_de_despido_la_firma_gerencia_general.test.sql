-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 168_la_carta_de_despido_la_firma_gerencia_general.test.sql
-- ============================================================================
-- Artículo 54.4 del Reglamento Interno de Trabajo. Lo que hace cara esta regla
-- no es el 54.4 c) sino el d): una sanción impuesta por quien no era competente
-- «no produce efecto alguno». Un despido firmado por Desarrollo Organizacional
-- no es un despido con un defecto de forma — es un despido que no existe, con
-- una persona fuera de la empresa.
--
-- Lo que fija esta prueba:
--   · Desarrollo Organizacional NO puede suscribir un despido, ni apareciendo
--     en la lista de firmantes ni forzando la llamada.
--   · La Gerencia General sí, pero EN PERSONA: nadie estampa esa firma a nombre
--     de otra persona.
--   · Lo que ya funcionaba sigue igual: DO firma suspensiones e imputaciones, y
--     la encargada firma amonestaciones de su sede y solo de su sede.
--   · Instruir no es imponer: DO conserva el borrador del despido, que es lo
--     que el 54.4 c) le encarga.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000d1', 'ZZGG1', 'Sede de laboratorio', true),
  ('00000000-0000-0000-0000-0000000000d2', 'ZZGG2', 'Otra sede de laboratorio', true);

-- Tres personas con panel + la trabajadora sobre la que recae el documento.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000000e1', 'GerenciaPrueba', 'Lab', '00000000-0000-0000-0000-0000000000d1', 'admin',           'x', '00000000-0000-0000-0000-00000000ee01', '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000e2', 'DoPrueba',       'Lab', '00000000-0000-0000-0000-0000000000d1', 'lider_do',        'x', '00000000-0000-0000-0000-00000000ee02', '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000e3', 'EncargadaPrueba','Lab', '00000000-0000-0000-0000-0000000000d1', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000ee03', '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000e4', 'EncargadaOtra',  'Lab', '00000000-0000-0000-0000-0000000000d2', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000ee04', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000e9', 'TrabajadoraPrueba', 'Lab',
        '00000000-0000-0000-0000-0000000000d1', 'x', '2020-01-01');

-- ── La regla, sin sesión ni base de por medio ───────────────────────────────
select is(fn_expediente_puede_suscribir('lider_do', 'despido'), false,
          '54.4 c) · Desarrollo Organizacional NO suscribe un despido');
select is(fn_expediente_puede_suscribir('admin', 'despido'), true,
          '54.4 c) · la Gerencia General sí suscribe un despido');
select is(fn_expediente_puede_suscribir('lider_do', 'suspension'), true,
          '54.4 c) · Desarrollo Organizacional sigue suscribiendo suspensiones');
select is(fn_expediente_puede_suscribir('supervisor_sede', 'suspension'), false,
          '54.4 b) · la encargada de tienda no llega a la suspensión');
select is(fn_expediente_puede_suscribir(null, 'amonestacion'), false,
          'GUARD · un rol nulo no pasa por autorizado');

-- ── El despido, de punta a punta ────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ee02', true);

select lives_ok(
  $$ select fn_expediente_crear_borrador('00000000-0000-0000-0000-0000000000e9',
       'falta', 'despido', '[{"fecha":"2026-07-01","tipo":"falta"}]'::jsonb,
       '2026-07-01', '2026-07-05') $$,
  '54.4 c) · instruir no es imponer: DO sí puede preparar el borrador del despido');

create temp table _doc as
  select id from expediente_disciplinario
  where persona_id = '00000000-0000-0000-0000-0000000000e9' and nivel = 'despido';

-- DO no aparece ni siquiera como opción en la lista que dibuja la pantalla.
select is(
  (select count(*)::int from fn_expediente_firmantes((select id from _doc))
   where persona_id = '00000000-0000-0000-0000-0000000000e2'),
  0, 'LISTA · Desarrollo Organizacional no figura entre los firmantes de un despido');

select is(
  (select count(*)::int from fn_expediente_firmantes((select id from _doc))
   where persona_id = '00000000-0000-0000-0000-0000000000e1'),
  1, 'LISTA · la Gerencia General sí figura');

-- Y forzando la llamada, tampoco.
select throws_ok(
  format($$ select fn_expediente_firmar(%L, '00000000-0000-0000-0000-0000000000e2') $$,
         (select id from _doc)),
  null, null,
  'FIRMA · DO no puede firmarse a sí misma un despido aunque llame a la función directamente');

-- DO tampoco puede estampar la firma de la Gerencia General.
select throws_ok(
  format($$ select fn_expediente_firmar(%L, '00000000-0000-0000-0000-0000000000e1') $$,
         (select id from _doc)),
  null, null,
  'FIRMA · ni puede firmar a nombre de la Gerencia General: esa carta se suscribe en persona');

-- La Gerencia General, en persona, sí.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ee01', true);
select lives_ok(
  format($$ select fn_expediente_firmar(%L, '00000000-0000-0000-0000-0000000000e1') $$,
         (select id from _doc)),
  'FIRMA · la Gerencia General suscribe el despido en persona y el documento queda firmado');

select * from finish();
rollback;
