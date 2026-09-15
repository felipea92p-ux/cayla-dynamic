-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 368_la_planilla_deja_de_contar_a_quien_todavia_no_existia.test.sql
-- ============================================================================
-- Defiende la 0464. Un periodo de planilla ya pasado no puede incluir a
-- alguien que, en ese periodo, todavía no había ingresado — aunque hoy esté
-- activo. Antes de la 0464, `fn_planilla_calcular_nucleo` solo miraba
-- `p.estado = 'activo'` para esa rama, sin comprobar la fecha de ingreso
-- contra el periodo que se está recalculando.
--
-- § 1-3 · el filtro en sí, llamando directo a fn_planilla_calcular_nucleo.
-- § 4-5 · lo que NO cambia: quien ya existía sigue apareciendo, y quien entró
--   después pero tiene una jornada real en el rango sigue apareciendo IGUAL
--   (por la otra rama del `or`, que esta migración no toca).
-- § 6-7 · el efecto de punta a punta que motivó la migración: un periodo con
--   un solo grupo real, ya pagado, y un "grupo fantasma" de alguien que
--   ingresó después, terminaba de pagarse y quedaba abierto para siempre.
--   Con la 0464, ese grupo fantasma deja de existir y el periodo sí cierra.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('aaaaaaaa-0464-0000-0000-000000000001', 'T68', 'Sede de la prueba 368', true);

set session_replication_role = replica;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('bbbbbbbb-0464-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'admin367@cayla.local', 'x', now(), now(), now());
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso)
values ('cccccccc-0464-0000-0000-000000000001', 'Ada', 'Admin367',
        'aaaaaaaa-0464-0000-0000-000000000001', 'admin', 'activo', 'x',
        'bbbbbbbb-0464-0000-0000-000000000001', '2020-01-01');
set session_replication_role = origin;

-- Un periodo ya pasado, de 30 días, relativo a hoy — nunca una fecha fija.
create temporary table _datos as
select
  (fn_hoy_lima() - 90) as p_ini,
  (fn_hoy_lima() - 61) as p_fin,
  (fn_hoy_lima() - 90) as vieja_ingreso,   -- ya existía antes del periodo
  (fn_hoy_lima() - 30) as nueva_ingreso;   -- ingresó DESPUÉS de que el periodo terminara

-- ── Las tres personas del escenario ─────────────────────────────────────────
insert into personas (id, nombres, apellidos, sede_base_id, estado, pin_hash, fecha_ingreso, tipo_vinculo, sueldo_fijo)
select 'cccccccc-0464-0000-0000-000000000002', 'Vieja', 'DeAntes',
       'aaaaaaaa-0464-0000-0000-000000000001', 'activo', 'x', d.vieja_ingreso, 'planilla', true
  from _datos d;

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('cccccccc-0464-0000-0000-000000000002', 'colibri', 1950, '2020-01-01');

insert into personas (id, nombres, apellidos, sede_base_id, estado, pin_hash, fecha_ingreso, tipo_vinculo, sueldo_fijo)
select 'cccccccc-0464-0000-0000-000000000003', 'NuevaFantasma', 'DeDespues',
       'aaaaaaaa-0464-0000-0000-000000000001', 'activo', 'x', d.nueva_ingreso, 'practicante', false
  from _datos d;

-- Ingresó después del periodo TAMBIÉN, pero tiene una jornada real marcada
-- dentro del rango (un dato anómalo, a propósito): tiene que seguir
-- apareciendo, porque esa rama del `or` no depende de la fecha de ingreso.
insert into personas (id, nombres, apellidos, sede_base_id, estado, pin_hash, fecha_ingreso, tipo_vinculo, sueldo_fijo)
select 'cccccccc-0464-0000-0000-000000000004', 'FantasmaConJornada', 'Anomalo',
       'aaaaaaaa-0464-0000-0000-000000000001', 'activo', 'x', d.nueva_ingreso, 'rxh', false
  from _datos d;

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('cccccccc-0464-0000-0000-000000000004', 'colibri', 1950, '2020-01-01');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select 'cccccccc-0464-0000-0000-000000000004', d.p_ini + 2, 6.5, 'cerrada'
  from _datos d;

-- ── § 1 · la función corre sin error para el periodo viejo ──────────────────
select lives_ok(
  $$ select fn_planilla_calcular_nucleo(
       (select p_ini from _datos), (select p_fin from _datos)) $$,
  '0464: fn_planilla_calcular_nucleo sigue funcionando para un periodo pasado');

-- ── § 2 · quien ingresó después del periodo NO aparece ──────────────────────
select is(
  (select count(*)::int from _datos d,
     jsonb_array_elements(fn_planilla_calcular_nucleo(d.p_ini, d.p_fin) -> 'filas') f
   where f ->> 'nombre' = 'NuevaFantasma DeDespues'),
  0,
  '0464: quien ingresó después de que el periodo terminara ya no aparece en ese periodo');

-- ── § 3 · el mensaje de la cabecera: cero jornadas/movimientos en conflicto ─
-- (documentado arriba, medido contra producción — acá solo se deja la
-- aserción de que sigue dando cero en este escenario también)
select is(
  (select count(*)::int from jornadas where persona_id = 'cccccccc-0464-0000-0000-000000000003'),
  0,
  '0464: NuevaFantasma no tiene ninguna jornada real que la otra rama pudiera rescatar');

-- ── § 4 · quien ya existía sigue apareciendo, sin cambios ───────────────────
select is(
  (select count(*)::int from _datos d,
     jsonb_array_elements(fn_planilla_calcular_nucleo(d.p_ini, d.p_fin) -> 'filas') f
   where f ->> 'nombre' = 'Vieja DeAntes'),
  1,
  '0464: quien ya existía antes del periodo sigue apareciendo igual que siempre');

-- ── § 5 · quien ingresó después PERO tiene jornada real, sigue apareciendo ──
-- Prueba directamente lo que dice la cabecera: esta migración angosta SOLO
-- la rama "está activo", no las otras tres del `or`.
select is(
  (select count(*)::int from _datos d,
     jsonb_array_elements(fn_planilla_calcular_nucleo(d.p_ini, d.p_fin) -> 'filas') f
   where f ->> 'nombre' = 'FantasmaConJornada Anomalo'),
  1,
  '0464: una jornada real en el rango sigue incluyendo a la persona, ingrese cuando ingrese');

-- ── § 6-7 · de punta a punta: el periodo cierra cuando su único grupo real ──
-- queda pagado, ya sin el grupo fantasma bloqueándolo para siempre.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
select 'dddddddd-0464-0000-0000-000000000001', d.p_ini, d.p_fin, 'abierto'
  from _datos d;

select set_config('request.jwt.claim.sub', 'bbbbbbbb-0464-0000-0000-000000000001', true);
set role authenticated;

-- El único grupo con gente real en este periodo (sin el fantasma) es
-- 'planilla' (Vieja) — 'rxh' también tiene gente real (FantasmaConJornada, la
-- que sí marcó), así que hacen falta los dos para completar el periodo.
select fn_periodo_pagado('dddddddd-0464-0000-0000-000000000001', true, 'planilla');

select is(
  (select estado from periodos_planilla where id = 'dddddddd-0464-0000-0000-000000000001'),
  'abierto',
  '0464: con un grupo real (rxh) todavía sin pagar, el periodo sigue abierto — nada se cierra de más');

select fn_periodo_pagado('dddddddd-0464-0000-0000-000000000001', true, 'rxh');
reset role;

select is(
  (select estado from periodos_planilla where id = 'dddddddd-0464-0000-0000-000000000001'),
  'pagado',
  '0464: pagados los DOS grupos reales, el periodo cierra — el fantasma ya no lo bloquea para siempre');

select * from finish();
rollback;
