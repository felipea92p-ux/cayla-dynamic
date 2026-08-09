-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 153_el_correo_de_quien_ya_entra_no_se_toca.test.sql
-- ============================================================================
-- `personas.email` parece un dato de contacto y no lo es: es el USUARIO con el
-- que la persona entra al sistema. Cambiarlo en `personas` NO cambia su cuenta
-- de Supabase Auth, así que quedaría un correo en la ficha y otro en el login.
--
-- Nadie se enteraría. No hay error, no hay pantalla roja: la persona intenta
-- entrar con el correo que ve en su ficha, no puede, y llama preguntando qué
-- pasó. Es la clase de defecto que solo aparece semanas después y del lado de
-- quien no puede arreglarlo.
--
-- Por eso la 0198 lo hace IMPOSIBLE en vez de advertirlo (decisión de Felipe,
-- 2026-08-08). Estas pruebas fijan las dos mitades de esa regla, que son
-- igual de importantes:
--
--   · con cuenta creada, el cambio se RECHAZA;
--   · sin cuenta, el correo se edita libremente — que es cuando de verdad hace
--     falta, para completar a quien todavía no tiene.
--
-- La segunda mitad importa tanto como la primera: un candado que también cierra
-- el caso legítimo termina desactivado.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000d0', 'ZZMAI', 'Sede de laboratorio MAIL', true);

set session_replication_role = replica;
-- El correo va en el INSERT y no en un UPDATE posterior: con auth_user_id
-- puesto, cualquier UPDATE sobre esa fila revalida la clave foránea contra
-- auth.users —que en las pruebas no existe— y aborta el archivo entero.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, email)
values
  -- Quien administra.
  ('00000000-0000-0000-0000-0000000000d1', 'MailAdmin', 'Lab', '00000000-0000-0000-0000-0000000000d0', 'admin', 'x', '00000000-0000-0000-0000-00000000dd01', '2024-01-01', null),
  -- Una encargada de sede: puede editar la ficha de su equipo, NO la identidad.
  ('00000000-0000-0000-0000-0000000000d2', 'MailEncargada', 'Lab', '00000000-0000-0000-0000-0000000000d0', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000dd02', '2024-01-01', null),
  -- CON cuenta de acceso: su correo es su login.
  ('00000000-0000-0000-0000-0000000000d3', 'MailConCuenta', 'Lab', '00000000-0000-0000-0000-0000000000d0', 'integrante', 'x', '00000000-0000-0000-0000-00000000dd03', '2024-01-01', 'con.cuenta@ejemplo.pe');
set session_replication_role = origin;

-- SIN cuenta de acceso y SIN correo: el caso de quien todavía no fue invitada.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion)
values ('00000000-0000-0000-0000-0000000000d4', 'MailSinCuenta', 'Lab', '00000000-0000-0000-0000-0000000000d0', 'x', '2024-01-01', 'taller_produccion');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dd01', true);

-- ── 1 · Sin cuenta, el correo se edita ──────────────────────────────────────
select lives_ok(
  $$ select fn_set_email('00000000-0000-0000-0000-0000000000d4', 'nueva@ejemplo.pe') $$,
  'a quien no tiene cuenta se le puede cargar el correo — es justo para eso'
);

select is(
  (select email from personas where id = '00000000-0000-0000-0000-0000000000d4'),
  'nueva@ejemplo.pe',
  'y queda guardado'
);

select lives_ok(
  $$ select fn_set_email('00000000-0000-0000-0000-0000000000d4', '  OTRA@Ejemplo.PE  ') $$,
  'se puede corregir las veces que haga falta mientras no tenga acceso'
);

select is(
  (select email from personas where id = '00000000-0000-0000-0000-0000000000d4'),
  'otra@ejemplo.pe',
  'y se normaliza: sin espacios y en minúsculas, porque el login no distingue mayúsculas'
);

-- ── 2 · Con cuenta, el cambio se rechaza ────────────────────────────────────
select throws_ok(
  $$ select fn_set_email('00000000-0000-0000-0000-0000000000d3', 'otro.correo@ejemplo.pe') $$,
  null,
  null,
  'a quien YA tiene cuenta no se le cambia el correo desde la ficha: sería su login'
);

select is(
  (select email from personas where id = '00000000-0000-0000-0000-0000000000d3'),
  'con.cuenta@ejemplo.pe',
  'y el correo original no se movió — el rechazo no dejó nada a medias'
);

-- Guardar la ficha entera sin tocar el correo NO puede fallar: el formulario
-- manda todos los campos juntos, y si el mismo valor se leyera como "cambio",
-- nadie con cuenta podría volver a guardar su dirección.
select lives_ok(
  $$ select fn_set_email('00000000-0000-0000-0000-0000000000d3', 'con.cuenta@ejemplo.pe') $$,
  'mandar el MISMO correo no es un cambio: guardar la ficha sigue funcionando'
);

-- ── 3 · El permiso es el de identidad, no el de la ficha ────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dd02', true);

select throws_ok(
  $$ select fn_set_email('00000000-0000-0000-0000-0000000000d4', 'encargada@ejemplo.pe') $$,
  null,
  null,
  'la encargada de sede edita celular y dirección de su equipo, pero no el correo de acceso'
);

select is(
  (select email from personas where id = '00000000-0000-0000-0000-0000000000d4'),
  'otra@ejemplo.pe',
  'y no alcanzó a escribir nada'
);

select * from finish();
rollback;
