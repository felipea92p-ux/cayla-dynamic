-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 487_quien_se_da_de_baja_ya_no_entra.test.sql
-- ============================================================================
-- La 0597: el acceso sigue a `personas.estado` por cualquier puerta. Lo que se
-- vigila es lo que GoTrue mira (`banned_until`, sesiones y refresh tokens), no
-- que exista un trigger: que GoTrue rechace a quien tiene esas filas así se midió
-- contra el GoTrue real al escribir la migración (ver su encabezado).
--
-- Las tres cuentas que NO se deben tocar importan tanto como la que sí: la
-- compañera con sesión abierta, la estación de retail y el terminal de la sede.
-- ============================================================================
begin;
select plan(19);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000597a01', 'ZZBAJ', 'Sede de laboratorio', true);

-- Cuentas de verdad en auth.users: la prueba es justo sobre esa tabla.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
select v.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       v.correo, 'x', now(), now(), now()
  from (values
    ('00000000-0000-0000-0000-000000597b01', 'admin-baja@example.test'),
    ('00000000-0000-0000-0000-000000597b02', 'se-va@example.test'),
    ('00000000-0000-0000-0000-000000597b03', 'se-queda@example.test'),
    ('00000000-0000-0000-0000-000000597b04', 'estacion@example.test'),
    ('00000000-0000-0000-0000-000000597b05', 'terminal@example.test'),
    ('00000000-0000-0000-0000-000000597b06', 'enlazada-tarde@example.test'),
    ('00000000-0000-0000-0000-000000597b07', 'enlazada-activa@example.test')
  ) as v(id, correo);

insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, funcion)
values
  ('00000000-0000-0000-0000-000000597c01', 'AdminBaja', 'Lab', '00000000-0000-0000-0000-000000597a01', 'integrante', 'x', '00000000-0000-0000-0000-000000597b01', '2024-01-01', 'taller_produccion'),
  ('00000000-0000-0000-0000-000000597c02', 'SeVa', 'Lab', '00000000-0000-0000-0000-000000597a01', 'integrante', 'x', '00000000-0000-0000-0000-000000597b02', '2024-01-01', 'taller_produccion'),
  ('00000000-0000-0000-0000-000000597c03', 'SeQueda', 'Lab', '00000000-0000-0000-0000-000000597a01', 'integrante', 'x', '00000000-0000-0000-0000-000000597b03', '2024-01-01', 'taller_produccion'),
  ('00000000-0000-0000-0000-000000597c04', 'Estacion', 'Lab', '00000000-0000-0000-0000-000000597a01', 'integrante', 'x', '00000000-0000-0000-0000-000000597b04', '2024-01-01', 'taller_produccion'),
  ('00000000-0000-0000-0000-000000597c05', 'CuentaTerminal', 'Lab', '00000000-0000-0000-0000-000000597a01', 'integrante', 'x', '00000000-0000-0000-0000-000000597b05', '2024-01-01', 'taller_produccion'),
  ('00000000-0000-0000-0000-000000597c06', 'SinCuenta', 'Lab', '00000000-0000-0000-0000-000000597a01', 'integrante', 'x', null, '2024-01-01', 'taller_produccion'),
  ('00000000-0000-0000-0000-000000597c07', 'ActivaSinCuenta', 'Lab', '00000000-0000-0000-0000-000000597a01', 'integrante', 'x', null, '2024-01-01', 'taller_produccion');

-- El rol y la marca de servicio tienen sus propias puertas; aquí solo son el
-- punto de partida, así que se ponen sin pasar por sus triggers.
set session_replication_role = replica;
update personas set rol = 'admin' where id = '00000000-0000-0000-0000-000000597c01';
update personas set cuenta_de_servicio = true where id = '00000000-0000-0000-0000-000000597c04';
set session_replication_role = origin;

insert into terminales (sede_id, nombre_dispositivo, auth_user_id)
values ('00000000-0000-0000-0000-000000597a01', 'Terminal de laboratorio', '00000000-0000-0000-0000-000000597b05');

-- Una sesión abierta con su refresh token, para cada cuenta que importa.
insert into auth.sessions (id, user_id, created_at, updated_at)
select gen_random_uuid(), u::uuid, now(), now()
  from unnest(array['00000000-0000-0000-0000-000000597b02', '00000000-0000-0000-0000-000000597b03',
                    '00000000-0000-0000-0000-000000597b05']) as u;
insert into auth.refresh_tokens (token, user_id, session_id, revoked, created_at, updated_at)
select 'tok-' || s.user_id, s.user_id::text, s.id, false, now(), now() from auth.sessions s
 where s.user_id in ('00000000-0000-0000-0000-000000597b02', '00000000-0000-0000-0000-000000597b03',
                     '00000000-0000-0000-0000-000000597b05');
-- Y un token viejo, de cuando no llevaban sesión.
insert into auth.refresh_tokens (token, user_id, session_id, revoked, created_at, updated_at)
values ('tok-viejo', '00000000-0000-0000-0000-000000597b02', null, false, now(), now());

create function pg_temp.baneada(p_id text) returns boolean language sql as
  $$ select banned_until > now() from auth.users where id = p_id::uuid $$;
create function pg_temp.sesiones(p_id text) returns bigint language sql as
  $$ select count(*) from auth.sessions where user_id = p_id::uuid $$;
create function pg_temp.tokens(p_id text) returns bigint language sql as
  $$ select count(*) from auth.refresh_tokens where user_id = p_id $$;

-- ── La baja por la puerta de la pantalla ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000597b01', true);
select lives_ok(
  $$ select fn_cesar_persona('00000000-0000-0000-0000-000000597c02', (now() at time zone 'America/Lima')::date, 'renuncia') $$,
  'fn_cesar_persona da de baja a una persona con sesión abierta'
);
select ok(pg_temp.baneada('00000000-0000-0000-0000-000000597b02'), 'la baja deja la cuenta sin poder iniciar sesión');
select is(pg_temp.sesiones('00000000-0000-0000-0000-000000597b02'), 0::bigint, 'la baja le cierra las sesiones');
select is(pg_temp.tokens('00000000-0000-0000-0000-000000597b02'), 0::bigint, 'la baja le borra los refresh tokens, también el que no tenía sesión');

-- La fecha importa: `infinity` tumba el login entero en GoTrue (encabezado de la 0597).
select ok(
  (select isfinite(banned_until) from auth.users where id = '00000000-0000-0000-0000-000000597b02'),
  'el ban es una fecha finita: GoTrue no sabe leer infinity'
);

-- ── A los demás no se les toca ──────────────────────────────────────────────
select ok(pg_temp.baneada('00000000-0000-0000-0000-000000597b03') is not true, 'la compañera sigue pudiendo entrar');
select is(pg_temp.sesiones('00000000-0000-0000-0000-000000597b03'), 1::bigint, 'la compañera conserva su sesión');

-- ── Reactivar devuelve el acceso ────────────────────────────────────────────
select lives_ok(
  $$ select fn_reactivar_persona('00000000-0000-0000-0000-000000597c02') $$,
  'fn_reactivar_persona la reactiva'
);
select ok(pg_temp.baneada('00000000-0000-0000-0000-000000597b02') is not true, 'reactivada vuelve a poder entrar');

-- ── Cualquier otro camino: el SQL Editor ────────────────────────────────────
update personas set estado = 'inactivo', fecha_cese = '2026-01-15', motivo_cese = 'renuncia' where id = '00000000-0000-0000-0000-000000597c02';
select ok(pg_temp.baneada('00000000-0000-0000-0000-000000597b02'), 'un cambio directo de estado también corta el acceso');
update personas set estado = 'activo', fecha_cese = null, motivo_cese = null where id = '00000000-0000-0000-0000-000000597c02';
select ok(pg_temp.baneada('00000000-0000-0000-0000-000000597b02') is not true, 'y al revés también lo devuelve');

-- ── Lo que queda fuera a propósito ──────────────────────────────────────────
update personas set estado = 'inactivo', fecha_cese = '2026-01-15', motivo_cese = 'renuncia' where id = '00000000-0000-0000-0000-000000597c04';
select ok(pg_temp.baneada('00000000-0000-0000-0000-000000597b04') is not true, 'una estación de retail no se banea');

update personas set estado = 'inactivo', fecha_cese = '2026-01-15', motivo_cese = 'renuncia' where id = '00000000-0000-0000-0000-000000597c05';
select ok(pg_temp.baneada('00000000-0000-0000-0000-000000597b05') is not true, 'una cuenta de terminal no se banea');
select is(pg_temp.sesiones('00000000-0000-0000-0000-000000597b05'), 1::bigint, 'y el terminal sigue con su sesión');

-- ── Enlazar una cuenta ──────────────────────────────────────────────────────
update personas set estado = 'inactivo', fecha_cese = '2026-01-15', motivo_cese = 'renuncia' where id = '00000000-0000-0000-0000-000000597c06';
update personas set auth_user_id = '00000000-0000-0000-0000-000000597b06' where id = '00000000-0000-0000-0000-000000597c06';
select ok(pg_temp.baneada('00000000-0000-0000-0000-000000597b06'), 'una cuenta que se enlaza a quien ya está de baja nace cortada');

-- Con un ban puesto a mano: solo volver de una baja lo quita, enlazar no.
update auth.users set banned_until = now() + interval '1 day' where id = '00000000-0000-0000-0000-000000597b07';
update personas set auth_user_id = '00000000-0000-0000-0000-000000597b07' where id = '00000000-0000-0000-0000-000000597c07';
select ok(pg_temp.baneada('00000000-0000-0000-0000-000000597b07'), 'enlazar una cuenta a alguien activo no le quita un ban que ya tenía');

-- ── Nadie lo puede llamar desde el navegador ────────────────────────────────
select ok(
  not has_function_privilege('authenticated', 'fn_cortar_acceso_de_cuenta(uuid)', 'execute'),
  'una sesión del navegador no puede cortarle el acceso a otra persona'
);
select ok(
  not has_function_privilege('anon', 'fn_cortar_acceso_de_cuenta(uuid)', 'execute'),
  'tampoco sin sesión'
);
select ok(
  not has_function_privilege('authenticated', 'fn_personas_acceso_sigue_al_estado()', 'execute'),
  'ni puede llamar a la función del trigger'
);

select * from finish();
rollback;
