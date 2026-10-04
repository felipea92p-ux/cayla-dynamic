-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 401_el_alta_de_una_persona_solo_entra_por_fn_crear_persona.test.sql
-- ============================================================================
-- Defiende la 0507. Hasta ella, un admin o un líder DO podía insertar filas
-- directo en `personas` (política `personas_insert_admin_lider` de la 0003 +
-- privilegio de INSERT de la 0004), saltándose el escalafón de la 0300 y todo
-- lo demás que valida `fn_crear_persona`. Medido antes de escribir esta
-- prueba: un lider_do pedía un admin por `fn_crear_persona` y recibía «No
-- puedes crear una persona con un rol igual o superior al tuyo.»; pedía el
-- mismo admin con un INSERT directo y pasaba.
--
-- Esta prueba NO depende de la firma de `fn_crear_persona` más allá de sus
-- siete primeros argumentos posicionales: la 0506 le agrega un octavo con valor
-- por defecto, y la prueba vale antes y después de que se fusione.
--
-- La última sección es un CONTROL, no una defensa: devuelve la política y el
-- privilegio a propósito y comprueba que el hueco vuelve. Sin él, un «todo
-- bloqueado» podría deberse a cualquier otra cosa. Y además demuestra la frase
-- de la cabecera de la 0507: hacen falta LAS DOS para reabrirlo; el privilegio
-- solo, sin política, lo sigue frenando RLS.
-- ============================================================================
begin;
select plan(17);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000040100', 'ZZ401', 'Sede de laboratorio 401', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000040101', 'LiderDO', 'Cuatrocientos', '00000000-0000-0000-0000-000000040100',
   'lider_do', 'x', '00000000-0000-0000-0000-00000004011a', '2024-01-01'),
  ('00000000-0000-0000-0000-000000040102', 'Admin',   'Cuatrocientos', '00000000-0000-0000-0000-000000040100',
   'admin',    'x', '00000000-0000-0000-0000-00000004011b', '2024-01-01');
set session_replication_role = origin;

-- ── 1-6 · EL ESTADO: no queda ni política ni privilegio ─────────────────────
select ok(not has_table_privilege('authenticated', 'public.personas', 'INSERT'),
  'ESTADO · authenticated no tiene INSERT sobre personas');

select ok(not has_table_privilege('anon', 'public.personas', 'INSERT'),
  'ESTADO · anon tampoco');

select is(
  (select count(*) from pg_policies
    where schemaname = 'public' and tablename = 'personas' and cmd in ('INSERT', 'ALL')),
  0::bigint,
  'ESTADO · personas no tiene ninguna política de INSERT ni de ALL');

select ok(not has_table_privilege('authenticated', 'retail.personas', 'INSERT'),
  'ESTADO · la vista retail.personas tampoco es una puerta de alta para authenticated');

select ok(has_table_privilege('service_role', 'public.personas', 'INSERT'),
  'ESTADO · service_role conserva su INSERT: los scripts de alta con llave de servicio siguen funcionando');

select ok(
  coalesce((select bool_and(prosecdef) from pg_proc
             where proname = 'fn_crear_persona' and pronamespace = 'public'::regnamespace), false),
  'ESTADO · fn_crear_persona es SECURITY DEFINER: su insert corre como su dueño, por eso el revoke no la rompe');

-- ── 7-9 · EL COMPORTAMIENTO: nadie inserta directo, ni aun pidiendo algo inocente ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004011a', true);
set role authenticated;

select throws_ok(
  $$ insert into personas (nombres, apellidos, sede_base_id, rol, funcion, pin_hash)
     values ('Cuenta', 'Contrabando', '00000000-0000-0000-0000-000000040100', 'admin', 'calidad_servicio', 'x') $$,
  '42501', 'permission denied for table personas',
  'BLOQUEADO · el ataque: un lider_do ya no puede insertar un admin directo en la tabla');

select throws_ok(
  $$ insert into personas (nombres, apellidos, sede_base_id, rol, funcion, pin_hash)
     values ('Alguien', 'Inocente', '00000000-0000-0000-0000-000000040100', 'integrante', 'calidad_servicio', 'x') $$,
  '42501', 'permission denied for table personas',
  'BLOQUEADO · tampoco un integrante inocente: la puerta se cerró entera, no solo para la escalada');

select throws_ok(
  $$ insert into retail.personas (sede_id, email)
     values ('00000000-0000-0000-0000-000000040100', 'x@x.test') $$,
  '42501', 'permission denied for view personas',
  'BLOQUEADO · ni por la vista retail.personas, que es la misma tabla por otro mango');

reset role;

-- ── 10 · Ni un admin: hasta ellos pasan por la función ─────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004011b', true);
set role authenticated;

select throws_ok(
  $$ insert into personas (nombres, apellidos, sede_base_id, rol, funcion, pin_hash)
     values ('Otro', 'Directo', '00000000-0000-0000-0000-000000040100', 'integrante', 'calidad_servicio', 'x') $$,
  '42501', 'permission denied for table personas',
  'BLOQUEADO · un admin tampoco inserta directo: el alta pasa por la función, siempre');

reset role;

-- ── 11-14 · LA PUERTA OFICIAL SIGUE VIVA ───────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004011a', true);
set role authenticated;

select lives_ok(
  $$ select fn_crear_persona('Alta401', 'Oficial', '00000000-0000-0000-0000-000000040100',
                             'integrante', 'calidad_servicio', null, 'x') $$,
  'PERMITIDO · un lider_do da de alta a un integrante por fn_crear_persona, como siempre');

reset role;

select is(
  (select count(*) from personas where nombres = 'Alta401' and apellidos = 'Oficial' and rol = 'integrante'),
  1::bigint,
  'PERMITIDO · y la fila existe: la función inserta aunque quien la llama no tenga INSERT');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004011a', true);
set role authenticated;

select throws_ok(
  $$ select fn_crear_persona('Zeta401', 'ComoAdmin', '00000000-0000-0000-0000-000000040100',
                             'admin', 'calidad_servicio', null, 'x') $$,
  'No puedes crear una persona con un rol igual o superior al tuyo.',
  'SIN ROMPER LO VIEJO · la puerta oficial sigue frenando la escalada (0300)');

reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004011b', true);
set role authenticated;

select lives_ok(
  $$ select fn_crear_persona('Beta401', 'PorAdmin', '00000000-0000-0000-0000-000000040100',
                             'lider_do', 'calidad_servicio', null, 'x') $$,
  'PERMITIDO · un admin da de alta a un lider_do por fn_crear_persona');

reset role;

-- ── 15-17 · EL CONTROL: se reabre a propósito para probar que ESTO era el hueco ──
-- Solo el privilegio, sin política: RLS lo sigue negando. Son dos cerrojos
-- independientes, y por eso reabrir exige deshacer los dos.
grant insert on personas to authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004011a', true);
set role authenticated;

select throws_ok(
  $$ insert into personas (nombres, apellidos, sede_base_id, rol, funcion, pin_hash)
     values ('Cuenta', 'Contrabando', '00000000-0000-0000-0000-000000040100', 'admin', 'calidad_servicio', 'x') $$,
  '42501', 'new row violates row-level security policy for table "personas"',
  'CONTROL · con solo el privilegio devuelto, RLS sigue frenando: son dos cerrojos');

reset role;

-- Privilegio y política devueltos: es el estado de la 0003 + 0004. El `drop` es
-- para que la prueba también corra SIN la 0507 (donde la política ya existe) y
-- falle con claridad en vez de abortar la transacción.
drop policy if exists personas_insert_admin_lider on personas;
create policy personas_insert_admin_lider on personas
  for insert to authenticated with check (fn_es_admin_o_lider());

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004011a', true);
set role authenticated;

select lives_ok(
  $$ insert into personas (nombres, apellidos, sede_base_id, rol, funcion, pin_hash)
     values ('Cuenta', 'Contrabando', '00000000-0000-0000-0000-000000040100', 'admin', 'calidad_servicio', 'x') $$,
  'CONTROL · con la política y el privilegio devueltos, el hueco vuelve: lo que lo cierra es la 0507');

reset role;

select is(
  (select count(*) from personas where apellidos = 'Contrabando' and rol = 'admin'),
  1::bigint,
  'CONTROL · y el admin de contrabando existe: el ataque funcionaba con cualquier lider_do');

select * from finish();
