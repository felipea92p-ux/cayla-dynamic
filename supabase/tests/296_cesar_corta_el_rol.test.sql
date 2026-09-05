-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 296_cesar_corta_el_rol.test.sql
-- ============================================================================
-- La 0374 corta el poder de un rol en el momento del cese, sin tocar Auth:
-- fn_rol_actual() —el único paso por el que pasa todo permiso de admin, líder
-- o encargada de sede— deja de contestar apenas `estado <> 'activo'`.
--
-- Antes de esto: dar de baja a alguien con rol admin/lider_do/supervisor_sede
-- no le quitaba nada — su clave seguía siendo válida y las políticas de RLS le
-- seguían dando acceso a sueldos y datos de todo el equipo, indefinidamente.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-0000000000d0', 'ZZROL', 'Sede de laboratorio', true, 'tienda');

-- Dos personas con sesión real: una encargada de sede (a quien se va a cesar)
-- y un admin (que es quien tiene permiso de cesar a alguien). auth_user_id
-- apunta a un uuid que no existe en auth.users — no hace falta que exista para
-- probar fn_rol_actual(). `set local` (no `set`, y sin volver a 'origin'
-- después): el UPDATE de fn_cesar_persona más abajo también re-valida el FK de
-- auth_user_id, no solo el INSERT — mismo patrón que usa la 177 para poder
-- cesar a sus personas de laboratorio dentro de la misma transacción.
set local session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values
  ('00000000-0000-0000-0000-0000000000d1', 'RolEncargada', 'Lab', '00000000-0000-0000-0000-0000000000d0', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000000df', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000000d2', 'RolAdmin',     'Lab', '00000000-0000-0000-0000-0000000000d0', 'admin',           'x', '00000000-0000-0000-0000-0000000000de', '2024-01-01', 'planilla');

-- ── Antes del cese: activa, con su rol y su poder ───────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000df', true);
select is(
  fn_rol_actual()::text, 'supervisor_sede',
  'activa: fn_rol_actual() devuelve su rol real');

-- ── El cese, hecho por el admin ──────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000de', true);
select lives_ok($$
  select fn_cesar_persona('00000000-0000-0000-0000-0000000000d1'::uuid, '2026-07-10'::date, 'renuncia');
$$, 'el admin puede cesar a la encargada');

-- ── Después: LA MISMA sesión (mismo auth_user_id, misma clave viva) ya no
-- tiene rol ni poder — nadie tuvo que tocarle la clave ni cerrarle sesión ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000df', true);
select ok(
  fn_rol_actual() is null,
  'cesada: fn_rol_actual() ya no devuelve ningún rol, aunque la clave siga siendo válida');
select ok(
  fn_es_admin_o_lider() is not true,
  'cesada: fn_es_admin_o_lider() nunca queda en true (guard null-safe)');

-- Y su propio registro —lo que ve en "Lo mío"— sigue siendo suyo: esto corta
-- el PODER sobre datos ajenos, no borra su propio historial.
select is(
  fn_persona_actual_id(), '00000000-0000-0000-0000-0000000000d1'::uuid,
  'cesada: fn_persona_actual_id() sigue siendo la suya — su propio historial no desaparece');

select * from finish();
rollback;
