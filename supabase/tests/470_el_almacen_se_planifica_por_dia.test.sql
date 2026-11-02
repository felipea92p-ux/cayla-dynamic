-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 470_el_almacen_se_planifica_por_dia.test.sql
-- ============================================================================
-- fn_set_almacen_del_dia (0579) deja escrito que una persona trabaja en
-- almacén un día: todo el turno o tramos que no se cruzan. Lo que importa:
-- quién puede (la líder de equipo de su sede, incluida ella misma; admin y
-- Líder DO sobre cualquiera), que solo sea de hoy en adelante, que los tramos
-- no se crucen ni en la función ni en la tabla, que deje rastro, que nadie
-- escriba la tabla a mano y que NO toque turnos ni jornadas.
-- ============================================================================
begin;
select plan(24);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000047000', 'ZZALA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000047001', 'ZZALB', 'Sede de laboratorio B', true, 'tienda');

-- Quienes planifican tienen cuenta (auth_user_id) que no existe en auth.users:
-- se insertan con los disparadores apagados, como en la 348.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-000000047010', 'AlmAdmin', 'Lab', '00000000-0000-0000-0000-000000047000', 'admin', 'x',
   '00000000-0000-0000-0000-0000000470ff', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047011', 'AlmLiderA', 'Lab', '00000000-0000-0000-0000-000000047000', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000470fe', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047012', 'AlmLiderB', 'Lab', '00000000-0000-0000-0000-000000047001', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000470fd', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047013', 'AlmIntegrante', 'Lab', '00000000-0000-0000-0000-000000047000', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000470fc', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047014', 'AlmLiderCesada', 'Lab', '00000000-0000-0000-0000-000000047000', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000470fb', '2024-01-01', 'inactivo');
set session_replication_role = origin;

-- A quienes se les planifica: dos de la sede A (una inactiva) y una de la B.
-- La inactiva también va con los disparadores apagados: su cese no es lo que se prueba.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-000000047020', 'AlmPiso', 'Lab', '00000000-0000-0000-0000-000000047000', 'x', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000047022', 'AlmOtraSede', 'Lab', '00000000-0000-0000-0000-000000047001', 'x', '2024-01-01', 'activo');
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-000000047021', 'AlmInactiva', 'Lab', '00000000-0000-0000-0000-000000047000', 'x', '2024-01-01', 'inactivo');
set session_replication_role = origin;

create temporary table _turnos_antes as select count(*)::int n from turnos;
create temporary table _jornadas_antes as select count(*)::int n from jornadas;

-- ── 1-3 · Admin: todo el turno, después dos tramos, después piso ─────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000470ff', true);

select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 1, true, '[]'::jsonb);
select is(
  (select count(*)::int from puestos_planificados
    where persona_id = '00000000-0000-0000-0000-000000047020' and fecha = fn_hoy_lima() + 1 and desde is null),
  1, 'todo el turno en almacén es UNA fila sin horas');

select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 1, false,
  '[{"desde":"15:00","hasta":"16:30"},{"desde":"10:30","hasta":"12:00"}]'::jsonb);
select is(
  (select string_agg(to_char(desde, 'HH24:MI') || '-' || to_char(hasta, 'HH24:MI'), ' ' order by desde)
     from puestos_planificados
    where persona_id = '00000000-0000-0000-0000-000000047020' and fecha = fn_hoy_lima() + 1),
  '10:30-12:00 15:00-16:30', 'dos tramos reemplazan el plan entero del día (y ya no queda «todo el turno»)');

-- Las dos filas del rastro empatan en corregido_at (todo corre en una sola
-- transacción): se busca por su valor de antes, nunca «la más reciente».
select is(
  (select string_agg(valor_anterior || ' → ' || valor_nuevo, ' | ' order by valor_anterior desc)
     from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000047020' and campo_modificado = 'turnos.puesto'),
  'Piso → Almacén todo el turno | Almacén todo el turno → Almacén 10:30–12:00, 15:00–16:30',
  'cada cambio deja rastro en correcciones_auditoria, con el texto de antes y el de ahora');

-- ── 4-7 · Lo que no se puede planificar ─────────────────────────────────────
select throws_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 2, false,
       '[{"desde":"10:00","hasta":"12:00"},{"desde":"11:30","hasta":"13:00"}]'::jsonb) $$,
  null, null, 'dos tramos que se cruzan se rechazan con palabras');

select throws_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 2, false,
       '[{"desde":"12:00","hasta":"11:00"}]'::jsonb) $$,
  null, null, 'un tramo que termina antes de empezar se rechaza');

select throws_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() - 1, true, '[]'::jsonb) $$,
  null, null, 'un día que ya pasó no se planifica');

select throws_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047021', fn_hoy_lima() + 1, true, '[]'::jsonb) $$,
  null, null, 'a una persona inactiva no se le planifica');

select lives_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 3, false,
       '[{"desde":"10:00","hasta":"11:00"},{"desde":"11:00","hasta":"12:00"}]'::jsonb) $$,
  'dos tramos que se tocan (uno termina cuando empieza el otro) no se cruzan');

-- ── 8 · La tabla tampoco deja que se crucen, aunque se salte la función ──────
select throws_ok(
  $$ insert into puestos_planificados (persona_id, fecha, desde, hasta, creado_por)
     values ('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 1, time '11:00', time '11:30',
             '00000000-0000-0000-0000-000000047010') $$,
  '23P01', null, 'EXCLUDE puesto_sin_cruces: un tramo dentro de otro no entra ni por debajo');

select throws_ok(
  $$ insert into puestos_planificados (persona_id, fecha, desde, hasta, creado_por)
     values ('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 1, null, null,
             '00000000-0000-0000-0000-000000047010') $$,
  '23P01', null, '«todo el turno» no convive con un tramo del mismo día');

-- ── 9-10 · Volver a piso, y que nada de esto tocó turnos ni jornadas ─────────
select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 3, false, '[]'::jsonb);
select is(
  (select count(*)::int from puestos_planificados
    where persona_id = '00000000-0000-0000-0000-000000047020' and fecha = fn_hoy_lima() + 3),
  0, 'sin tramos y sin «todo el turno» = piso: el día queda sin filas');

select is(
  (select n from _turnos_antes) || '/' || (select n from _jornadas_antes),
  (select count(*)::int from turnos) || '/' || (select count(*)::int from jornadas),
  'planificar el almacén no toca turnos ni jornadas');

-- ── 11-15 · Quién puede ──────────────────────────────────────────────────────
-- La líder de la sede A: a su equipo, y también a sí misma (decisión 2026-11-02).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000470fe', true);

select lives_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 4, true, '[]'::jsonb) $$,
  'la líder de equipo planifica a alguien de su sede');

select lives_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047011', fn_hoy_lima() + 4, false,
       '[{"desde":"09:00","hasta":"10:00"}]'::jsonb) $$,
  'la líder de equipo se planifica a sí misma (el almacén no toca horas ni pago)');

select throws_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047022', fn_hoy_lima() + 4, true, '[]'::jsonb) $$,
  null, null, 'la líder de la sede A no planifica a alguien de la sede B');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000470fc', true);
select throws_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 4, false, '[]'::jsonb) $$,
  null, null, 'una integrante no planifica el almacén');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000470fb', true);
select throws_ok(
  $$ select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 4, false, '[]'::jsonb) $$,
  null, null, 'una líder inactiva con la sesión viva ya no planifica');

-- ── 16-17 · La lectura de un día ─────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000470ff', true);
select is(
  (select count(*)::int from fn_puestos_del_dia('00000000-0000-0000-0000-000000047000', fn_hoy_lima() + 1)),
  2, 'admin lee el plan del día de la sede A (los dos tramos)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000470fd', true);
select throws_ok(
  $$ select * from fn_puestos_del_dia('00000000-0000-0000-0000-000000047000', fn_hoy_lima() + 1) $$,
  null, null, 'la líder de la sede B no lee el plan de la sede A');

-- ── 18-22 · Nadie escribe la tabla a mano, y cada quien lee lo suyo ──────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000470fe', true);
set local role authenticated;

select is(
  (select count(*)::int from puestos_planificados where fecha = fn_hoy_lima() + 1),
  2, 'la líder de la sede A ve por RLS el plan de su equipo');

select throws_ok(
  $$ insert into puestos_planificados (persona_id, fecha, creado_por)
     values ('00000000-0000-0000-0000-000000047020', fn_hoy_lima() + 5, '00000000-0000-0000-0000-000000047011') $$,
  '42501', null, 'no se escribe por insert directo: solo por la función');

select throws_ok(
  $$ update puestos_planificados set desde = time '08:00' $$,
  '42501', null, 'no se actualiza a mano');

select throws_ok(
  $$ delete from puestos_planificados $$,
  '42501', null, 'no se borra a mano');

select throws_ok(
  $$ truncate puestos_planificados $$,
  '42501', null, 'nadie vacía la tabla: truncate no pasa por RLS, solo lo detiene el permiso');

reset role;

select * from finish();
rollback;
