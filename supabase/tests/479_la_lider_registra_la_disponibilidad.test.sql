-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 479_la_lider_registra_la_disponibilidad.test.sql
-- ============================================================================
-- La 0589. Lo que importa: que la líder registre la de una integrante de SU
-- sede y entre aprobada; que no registre la propia, ni la de otra líder, ni la
-- de otra sede; que una integrante no registre la de una compañera; que el
-- motivo del registro sea obligatorio y «Otro» exija texto; y que quede una
-- sola versión de la función (sin sobrecarga).
-- ============================================================================
begin;
select plan(15);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000047900', 'ZZRGA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000047901', 'ZZRGB', 'Sede de laboratorio B', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-000000047910', 'RegDO', 'Lab', '00000000-0000-0000-0000-000000047900', 'lider_do', 'x',
   '00000000-0000-0000-0000-0000000479a0', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047911', 'RegLiderA', 'Lab', '00000000-0000-0000-0000-000000047900', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000479a1', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047912', 'RegLiderB', 'Lab', '00000000-0000-0000-0000-000000047901', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000479a2', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047913', 'RegX', 'Lab', '00000000-0000-0000-0000-000000047900', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000479a3', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047914', 'RegY', 'Lab', '00000000-0000-0000-0000-000000047900', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000479a4', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047917', 'RegLiderA2', 'Lab', '00000000-0000-0000-0000-000000047900', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000479a7', '2024-01-01', 'activo');
set session_replication_role = origin;

create temporary table _ids (clave text primary key, id uuid);
grant all on _ids to authenticated;

-- Una llamada armada: quién registra a quién, con qué motivo del registro.
create temporary table _q as select
  $q$select fn_disponibilidad_registrar(%L, 'parcial', 'estudios', fn_hoy_lima(), null,
       '[{"dia_semana":2,"desde":"08:30","hasta":"14:00","estado":"no_puede"}]', false, null, %L, %L)$q$ as sql;
grant select on _q to authenticated;

-- ── 1-4 · La líder A registra a X (de su sede) ───────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000479a1', true);
select lives_ok(format('insert into _ids select ''x1'', (%s)',
  format((select sql from _q), '00000000-0000-0000-0000-000000047913', 'por_mensaje', null)),
  'la líder registra la disponibilidad de una integrante de su sede');
select ok((select estado = 'aprobada' and registrada_por = '00000000-0000-0000-0000-000000047911'
                  and resuelta_por = '00000000-0000-0000-0000-000000047911'
             from disponibilidades where id = (select id from _ids where clave = 'x1')),
  'entra aprobada, y dice que la registró y aprobó la líder');
select is((select registro_motivo from disponibilidades where id = (select id from _ids where clave = 'x1')),
  'por_mensaje', 'guarda el motivo del registro');
select is((select motivo from disponibilidades where id = (select id from _ids where clave = 'x1')),
  'estudios', 'y el motivo de la disponibilidad sigue siendo el suyo');

-- ── 5-8 · Lo que la líder no puede ───────────────────────────────────────────
select throws_ok(format((select sql from _q), '00000000-0000-0000-0000-000000047911', 'en_persona', null),
  'P0001', null, 'la propia, no');
select throws_ok(format((select sql from _q), '00000000-0000-0000-0000-000000047917', 'en_persona', null),
  'P0001', null, 'la de otra líder de su misma sede, no: esa la registra DO');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000479a2', true);
select throws_ok(format((select sql from _q), '00000000-0000-0000-0000-000000047914', 'en_persona', null),
  'P0001', null, 'la de una integrante de otra sede, no');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000479a3', true);
select throws_ok(format((select sql from _q), '00000000-0000-0000-0000-000000047914', 'en_persona', null),
  'P0001', null, 'una integrante no registra la de una compañera');

-- ── 9-11 · El motivo del registro ────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000479a1', true);
select throws_ok(format((select sql from _q), '00000000-0000-0000-0000-000000047914', null, null),
  'P0001', 'Elige por qué la registras tú y no ella.', 'sin motivo del registro, no');
select throws_ok(format((select sql from _q), '00000000-0000-0000-0000-000000047914', 'otro', 'eh'),
  'P0001', null, '«Otro» exige escribir por qué');
select lives_ok(format('insert into _ids select ''y1'', (%s)',
  format((select sql from _q), '00000000-0000-0000-0000-000000047914', 'otro', '  Lo dejó escrito en el cuaderno de la tienda  ')),
  '«Otro» con su texto, sí');
select is((select registro_detalle from disponibilidades where id = (select id from _ids where clave = 'y1')),
  'Lo dejó escrito en el cuaderno de la tienda', 'el texto se guarda sin espacios de más');

-- ── 12 · DO registra la de una líder ─────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000479a0', true);
select lives_ok(format((select sql from _q), '00000000-0000-0000-0000-000000047911', 'conversacion_horario', null),
  'DO registra la de una líder de equipo');

-- ── 13-14 · Sin sobrecarga, y nadie escribe el motivo directo ────────────────
select is((select count(*)::int from pg_proc where proname = 'fn_disponibilidad_registrar'), 1,
  'queda una sola versión de la función: sin sobrecarga ambigua');
set local role authenticated;
select throws_ok($$update disponibilidades set registro_motivo = 'otro' where persona_id = '00000000-0000-0000-0000-000000047913'$$,
  '42501', null, 'nadie cambia el motivo del registro sin la función');
reset role;

select * from finish();
rollback;
