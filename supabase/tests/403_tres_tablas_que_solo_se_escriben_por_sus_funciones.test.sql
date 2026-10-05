-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 403_tres_tablas_que_solo_se_escriben_por_sus_funciones.test.sql
-- ============================================================================
-- Defiende la 0509. `rendimiento_mensual`, `terminales` y `tarifas_hora` tenían
-- una política `FOR ALL … fn_es_admin_o_lider()` y el INSERT/UPDATE/DELETE de la
-- 0004. Medido antes de escribir esta prueba, con un lider_do:
--   · `fn_set_rendimiento` en un mes PAGADO → «La planilla de ese mes ya está
--     PAGADA»; el INSERT directo en el mismo mes → pasaba.
--   · un INSERT directo en `terminales`, atado a su propia cuenta, le permitía
--     registrar la entrada de OTRA persona como si fuera un kiosco, sin PIN y sin
--     rastro de corrección.
--
-- La última sección es un CONTROL, no una defensa: devuelve el privilegio y la
-- política a propósito y comprueba que el hueco vuelve. Sin él, un «todo
-- bloqueado» podría deberse a cualquier otra cosa. Y demuestra la frase de la
-- cabecera de la 0509: hacen falta LAS DOS cosas para reabrirlo.
-- ============================================================================
begin;
select plan(27);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000040300', 'ZZ403', 'Sede de laboratorio 403', true);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000004031a', 'liderdo-403@local'),
  ('00000000-0000-0000-0000-00000004031c', 'terminal-403@local');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000040301', 'LiderDO',    'Cuatrocientos', '00000000-0000-0000-0000-000000040300',
   'lider_do', 'x', '00000000-0000-0000-0000-00000004031a', '2024-01-01'),
  ('00000000-0000-0000-0000-000000040302', 'Integrante', 'Cuatrocientos', '00000000-0000-0000-0000-000000040300',
   'integrante', 'x', null, '2024-01-01');
set session_replication_role = origin;

-- Un kiosco real, una tarifa y una puntuación de julio (PAGADO) ya existentes.
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id) values
  ('00000000-0000-0000-0000-000000040310', '00000000-0000-0000-0000-000000040300', 'kiosco-403', true,
   '00000000-0000-0000-0000-00000004031c');
insert into tarifas_hora (persona_id, vigente_desde, tarifa_hora_soles) values
  ('00000000-0000-0000-0000-000000040302', '2026-01-01', 10);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000040320', '2026-06-29', '2026-07-28', 'pagado');
insert into rendimiento_mensual (persona_id, anio, mes, porcentaje, puesto_por) values
  ('00000000-0000-0000-0000-000000040302', 2026, 7, 90, '00000000-0000-0000-0000-000000040301');

-- ── 1-8 · EL ESTADO ─────────────────────────────────────────────────────────
select ok(not (has_table_privilege('authenticated', 'public.rendimiento_mensual', 'INSERT')
            or has_table_privilege('authenticated', 'public.rendimiento_mensual', 'UPDATE')
            or has_table_privilege('authenticated', 'public.rendimiento_mensual', 'DELETE')),
  'ESTADO · authenticated no escribe en rendimiento_mensual');

select ok(not (has_table_privilege('authenticated', 'public.terminales', 'INSERT')
            or has_table_privilege('authenticated', 'public.terminales', 'UPDATE')
            or has_table_privilege('authenticated', 'public.terminales', 'DELETE')),
  'ESTADO · authenticated no escribe en terminales');

select ok(not (has_table_privilege('authenticated', 'public.tarifas_hora', 'INSERT')
            or has_table_privilege('authenticated', 'public.tarifas_hora', 'UPDATE')
            or has_table_privilege('authenticated', 'public.tarifas_hora', 'DELETE')),
  'ESTADO · authenticated no escribe en tarifas_hora');

select is(
  (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relnamespace = 'public'::regnamespace
      and c.relname in ('rendimiento_mensual', 'terminales', 'tarifas_hora')
      and p.polcmd in ('a', 'w', 'd', '*')),
  0::bigint,
  'ESTADO · ninguna de las tres tiene política de INSERT, UPDATE, DELETE ni ALL');

select ok(has_table_privilege('authenticated', 'public.rendimiento_mensual', 'SELECT')
      and has_table_privilege('authenticated', 'public.terminales', 'SELECT')
      and has_table_privilege('authenticated', 'public.tarifas_hora', 'SELECT'),
  'LECTURA · authenticated conserva el SELECT en las tres');

select ok(
  (select count(*) filter (where c.relname = 'rendimiento_mensual') >= 1
      and count(*) filter (where c.relname = 'terminales') >= 2
      and count(*) filter (where c.relname = 'tarifas_hora') >= 1
     from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relnamespace = 'public'::regnamespace and p.polcmd = 'r'),
  'LECTURA · y las políticas de lectura siguen: 1 en rendimiento, 2 en terminales (admin/líder y «propio»), 1 en tarifas');

select ok(has_table_privilege('service_role', 'public.terminales', 'INSERT')
      and has_table_privilege('service_role', 'public.tarifas_hora', 'INSERT')
      and has_table_privilege('service_role', 'public.rendimiento_mensual', 'INSERT'),
  'ESTADO · service_role conserva su escritura: los scripts de alta de terminales siguen funcionando');

select ok(
  coalesce((select bool_and(prosecdef) from pg_proc
             where proname in ('fn_set_rendimiento', 'fn_quitar_rendimiento')
               and pronamespace = 'public'::regnamespace), false),
  'ESTADO · las dos funciones guardián son SECURITY DEFINER: su escritura corre como su dueño, por eso el revoke no las rompe');

-- ── 9-13 · EL COMPORTAMIENTO: un lider_do ya no escribe directo ────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004031a', true);
set role authenticated;

select throws_ok(
  $$ insert into terminales (sede_id, nombre_dispositivo, auth_user_id, activo)
     values ('00000000-0000-0000-0000-000000040300', 'Dispositivo inventado',
             '00000000-0000-0000-0000-00000004031a', true) $$,
  '42501', 'permission denied for table terminales',
  'BLOQUEADO · el ataque: un lider_do ya no se registra a sí mismo como terminal');

select throws_ok(
  $$ insert into rendimiento_mensual (persona_id, anio, mes, porcentaje, puesto_por)
     values ('00000000-0000-0000-0000-000000040302', 2026, 6, 80, '00000000-0000-0000-0000-000000040301') $$,
  '42501', 'permission denied for table rendimiento_mensual',
  'BLOQUEADO · ni inserta una puntuación directo en rendimiento_mensual');

select throws_ok(
  $$ update rendimiento_mensual set porcentaje = 0
      where persona_id = '00000000-0000-0000-0000-000000040302' and anio = 2026 and mes = 7 $$,
  '42501', 'permission denied for table rendimiento_mensual',
  'BLOQUEADO · ni cambia la de un mes ya PAGADO por update directo');

select throws_ok(
  $$ delete from rendimiento_mensual
      where persona_id = '00000000-0000-0000-0000-000000040302' and anio = 2026 and mes = 7 $$,
  '42501', 'permission denied for table rendimiento_mensual',
  'BLOQUEADO · ni la borra de un mes pagado (borrar SUBE el pago: sin fila vale 100)');

select throws_ok(
  $$ insert into tarifas_hora (persona_id, vigente_desde, tarifa_hora_soles)
     values ('00000000-0000-0000-0000-000000040302', '2026-02-01', 50) $$,
  '42501', 'permission denied for table tarifas_hora',
  'BLOQUEADO · ni inserta una tarifa directo en tarifas_hora');

-- ── 14-16 · LA LECTURA NO CAMBIÓ ───────────────────────────────────────────
select is((select count(*) from terminales where id = '00000000-0000-0000-0000-000000040310'), 1::bigint,
  'LECTURA · el lider_do sigue viendo las terminales');
select is((select count(*) from rendimiento_mensual where mes = 7 and anio = 2026), 1::bigint,
  'LECTURA · y las puntuaciones');
select is((select count(*) from tarifas_hora), 1::bigint,
  'LECTURA · y las tarifas');

reset role;

-- ── 17-18 · EL KIOSCO: se lee a sí mismo, y no escribe ─────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004031c', true);
set role authenticated;

select is((select count(*) from terminales where auth_user_id = auth.uid()), 1::bigint,
  'LECTURA · el kiosco sigue leyéndose a sí mismo (terminales_select_propio)');

select throws_ok(
  $$ update terminales set nombre_dispositivo = 'otro' where auth_user_id = auth.uid() $$,
  '42501', 'permission denied for table terminales',
  'BLOQUEADO · y el kiosco no se reescribe a sí mismo');

reset role;

-- ── 19-23 · LAS PUERTAS OFICIALES SIGUEN VIVAS ──────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004031a', true);
set role authenticated;

select lives_ok(
  $$ select fn_set_rendimiento('00000000-0000-0000-0000-000000040302', 2026, 9, 85, null) $$,
  'PERMITIDO · fn_set_rendimiento en un mes ABIERTO sigue funcionando');

reset role;

select is(
  (select porcentaje from rendimiento_mensual
    where persona_id = '00000000-0000-0000-0000-000000040302' and anio = 2026 and mes = 9),
  85::numeric,
  'PERMITIDO · y la fila quedó escrita: la función inserta aunque quien la llama no tenga INSERT');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004031a', true);
set role authenticated;

select throws_ok(
  $$ select fn_set_rendimiento('00000000-0000-0000-0000-000000040302', 2026, 7, 60, null) $$,
  'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.',
  'SIN ROMPER LO VIEJO · fn_set_rendimiento sigue frenando un mes pagado (0111)');

select lives_ok(
  $$ select fn_quitar_rendimiento('00000000-0000-0000-0000-000000040302', 2026, 9) $$,
  'PERMITIDO · fn_quitar_rendimiento en un mes abierto sigue funcionando');

select throws_ok(
  $$ select fn_quitar_rendimiento('00000000-0000-0000-0000-000000040302', 2026, 7) $$,
  'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.',
  'SIN ROMPER LO VIEJO · y fn_quitar_rendimiento sigue frenando un mes pagado');

reset role;

-- ── 24-27 · EL CONTROL: se reabre a propósito para probar que ESTO era el hueco ──
-- Solo el privilegio, sin política: RLS lo sigue negando. Dos cerrojos
-- independientes; reabrir exige deshacer los dos.
grant insert, update, delete on terminales to authenticated;
grant insert, update, delete on rendimiento_mensual to authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004031a', true);
set role authenticated;

select throws_ok(
  $$ insert into terminales (sede_id, nombre_dispositivo, auth_user_id, activo)
     values ('00000000-0000-0000-0000-000000040300', 'Dispositivo inventado',
             '00000000-0000-0000-0000-00000004031a', true) $$,
  '42501', 'new row violates row-level security policy for table "terminales"',
  'CONTROL · con solo el privilegio devuelto, RLS sigue frenando terminales: son dos cerrojos');

reset role;

-- Privilegio y política devueltos: es el estado anterior a la 0509.
drop policy if exists terminales_write_admin_lider on terminales;
create policy terminales_write_admin_lider on terminales
  for all to authenticated using (fn_es_admin_o_lider()) with check (fn_es_admin_o_lider());
drop policy if exists rendimiento_mensual_write on rendimiento_mensual;
create policy rendimiento_mensual_write on rendimiento_mensual
  for all to authenticated using (fn_es_admin_o_lider()) with check (fn_es_admin_o_lider());

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004031a', true);
set role authenticated;

select lives_ok(
  $$ insert into terminales (sede_id, nombre_dispositivo, auth_user_id, activo)
     values ('00000000-0000-0000-0000-000000040300', 'Dispositivo inventado',
             '00000000-0000-0000-0000-00000004031a', true) $$,
  'CONTROL · con política y privilegio devueltos, el lider_do vuelve a registrarse como terminal: lo cierra la 0509');

select lives_ok(
  $$ update rendimiento_mensual set porcentaje = 0
      where persona_id = '00000000-0000-0000-0000-000000040302' and anio = 2026 and mes = 7 $$,
  'CONTROL · y vuelve a poder reescribir una puntuación de un mes pagado');

reset role;

select is(
  (select porcentaje from rendimiento_mensual
    where persona_id = '00000000-0000-0000-0000-000000040302' and anio = 2026 and mes = 7),
  0::numeric,
  'CONTROL · y la puntuación pagada cambió: el ataque funcionaba con cualquier lider_do');

select * from finish();
