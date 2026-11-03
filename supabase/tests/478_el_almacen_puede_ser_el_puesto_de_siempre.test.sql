-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 478_el_almacen_puede_ser_el_puesto_de_siempre.test.sql
-- ============================================================================
-- El puesto base (0588): «siempre en almacén desde el día D» vale para todos sus
-- días, el plan de un día manda sobre la base («solo este día en piso», «solo
-- unas horas»), y la regla se lee en un solo sitio (fn_puestos_resueltos), que
-- es también lo que lee el terminal (fn_puestos_del_dia). Quién puede, solo
-- tiendas, de hoy en adelante, que deje rastro y que nadie escriba la tabla.
-- ============================================================================
begin;
select plan(22);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000478000', 'ZZPBA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000478001', 'ZZPBB', 'Sede de laboratorio B', true, 'tienda'),
  ('00000000-0000-0000-0000-000000478002', 'ZZPBT', 'Taller de laboratorio', true, 'taller');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-000000478010', 'PbAdmin', 'Lab', '00000000-0000-0000-0000-000000478000', 'admin', 'x',
   '00000000-0000-0000-0000-0000004780ff', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000478011', 'PbLiderA', 'Lab', '00000000-0000-0000-0000-000000478000', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004780fe', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000478012', 'PbLiderB', 'Lab', '00000000-0000-0000-0000-000000478001', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004780fd', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000478013', 'PbIntegrante', 'Lab', '00000000-0000-0000-0000-000000478000', 'integrante', 'x',
   '00000000-0000-0000-0000-0000004780fc', '2024-01-01', 'activo');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-000000478020', 'PbAlmacen', 'Lab', '00000000-0000-0000-0000-000000478000', 'x', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000478021', 'PbTaller', 'Lab', '00000000-0000-0000-0000-000000478002', 'x', '2024-01-01', 'activo');

create temporary table _turnos_antes as select count(*)::int n from turnos;

-- Un atajo: el plan resuelto de PbAlmacen en un día, como texto.
create function pg_temp.puesto_de(p_dia integer) returns text language sql as $f$
  select coalesce(string_agg(
           case when r.desde is null then 'todo' else to_char(r.desde, 'HH24:MI') || '-' || to_char(r.hasta, 'HH24:MI') end
           || '/' || r.origen, ' ' order by r.desde nulls first), 'piso')
    from fn_puestos_resueltos(fn_hoy_lima() + p_dia, fn_hoy_lima() + p_dia) r
   where r.persona_id = '00000000-0000-0000-0000-000000478020'
$f$;

-- ── 1-4 · La líder pone el almacén de base desde mañana ─────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004780fe', true);
select is(pg_temp.puesto_de(2), 'piso', 'sin base ni plan del día, piso (como siempre)');

select lives_ok(
  $$ select fn_set_puesto_base('00000000-0000-0000-0000-000000478020', fn_hoy_lima() + 1, 'almacen', 'Ordena el depósito') $$,
  'la líder de su sede le pone el almacén de base');
select is(pg_temp.puesto_de(2) || ' · ' || pg_temp.puesto_de(30) || ' · ' || pg_temp.puesto_de(0),
  'todo/base · todo/base · piso', 'la base vale para todos sus días desde mañana, y hoy sigue en piso');
select is(
  (select valor_anterior || ' → ' || valor_nuevo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000478020' and campo_modificado = 'horarios.puesto_base'),
  'Piso → Almacén', 'deja su rastro');

-- ── 5-9 · El plan de un día manda sobre la base ─────────────────────────────
select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000478020', fn_hoy_lima() + 3, false, '[]'::jsonb);
select is(pg_temp.puesto_de(3), 'piso', '«solo este día en piso» gana sobre la base');
select is(
  (select puesto from puestos_planificados
    where persona_id = '00000000-0000-0000-0000-000000478020' and fecha = fn_hoy_lima() + 3),
  'piso', 'y queda anotado como fila «piso» (sin ella mandaría la base)');

select fn_set_almacen_del_dia('00000000-0000-0000-0000-000000478020', fn_hoy_lima() + 4, false,
  '[{"desde":"10:00","hasta":"12:00"}]'::jsonb);
select is(pg_temp.puesto_de(4), '10:00-12:00/dia', 'unas horas en almacén ese día: solo esas horas, no todo el turno');

select is(
  (select valor_anterior || ' → ' || valor_nuevo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000478020' and campo_modificado = 'turnos.puesto'
      and motivo like 'Puesto del ' || to_char(fn_hoy_lima() + 3, 'DD/MM/YYYY') || '%'),
  'Almacén todo el turno (su puesto base) → Piso', 'el rastro del día dice que venía de su base');

select throws_ok(
  $$ insert into puestos_planificados (persona_id, fecha, desde, hasta, puesto, creado_por)
     values ('00000000-0000-0000-0000-000000478020', fn_hoy_lima() + 9, '10:00', '11:00', 'piso',
             '00000000-0000-0000-0000-000000478011') $$,
  '23514', null, 'una fila «piso» con horas no existe');

-- ── 10-12 · La lectura del terminal (fn_puestos_del_dia) ya ve la base ──────
select is(
  (select count(*)::int from fn_puestos_del_dia('00000000-0000-0000-0000-000000478000', fn_hoy_lima() + 2)
    where persona_id = '00000000-0000-0000-0000-000000478020' and desde is null),
  1, 'el plan del día de la sede incluye su base');
select is(
  (select count(*)::int from fn_puestos_del_dia('00000000-0000-0000-0000-000000478000', fn_hoy_lima() + 3)
    where persona_id = '00000000-0000-0000-0000-000000478020'),
  0, 'y el día que va a piso no trae nada');

-- ── 12-14 · Volver a piso desde una fecha ───────────────────────────────────
select fn_set_puesto_base('00000000-0000-0000-0000-000000478020', fn_hoy_lima() + 10, 'piso');
select is(pg_temp.puesto_de(9) || ' · ' || pg_temp.puesto_de(10) || ' · ' || pg_temp.puesto_de(40),
  'todo/base · piso · piso', 'desde el día 10 vuelve a piso; hasta el 9 sigue en almacén');
select is(
  (select count(*)::int from puestos_base where persona_id = '00000000-0000-0000-0000-000000478020'),
  1, 'la base vigente se cierra, no se apila otra');
select is(
  (select vigente_hasta from puestos_base where persona_id = '00000000-0000-0000-0000-000000478020'),
  fn_hoy_lima() + 9, 'cerrada el día anterior');

-- ── 15 · Lo mismo otra vez no deja rastro nuevo ─────────────────────────────
select fn_set_puesto_base('00000000-0000-0000-0000-000000478020', fn_hoy_lima() + 12, 'piso');
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000478020' and campo_modificado = 'horarios.puesto_base'),
  2, 'poner piso a quien ya está en piso no cambia nada');

-- ── 16-19 · Quién no puede, y dónde no hay almacén ──────────────────────────
select throws_ok(
  $$ select fn_set_puesto_base('00000000-0000-0000-0000-000000478020', fn_hoy_lima() - 1, 'almacen') $$,
  null, null, 'no se cambia la base de un día que ya pasó');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004780fd', true);
select throws_ok(
  $$ select fn_set_puesto_base('00000000-0000-0000-0000-000000478020', fn_hoy_lima() + 1, 'almacen') $$,
  null, null, 'la líder de otra sede no la cambia');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004780fc', true);
select throws_ok(
  $$ select fn_set_puesto_base('00000000-0000-0000-0000-000000478020', fn_hoy_lima() + 1, 'almacen') $$,
  null, null, 'una integrante no la cambia');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004780ff', true);
select throws_ok(
  $$ select fn_set_puesto_base('00000000-0000-0000-0000-000000478021', fn_hoy_lima() + 1, 'almacen') $$,
  null, null, 'en el taller no hay almacén de base (solo tiendas)');

-- ── 20-22 · Nadie escribe la tabla, nada toca turnos, anon fuera ────────────
select ok(
  not has_table_privilege('authenticated', 'public.puestos_base', 'INSERT'),
  'nadie escribe puestos_base directo');
select is((select count(*)::int from turnos), (select n from _turnos_antes), 'no tocó la tabla de turnos');
select ok(
  not has_function_privilege('anon', 'fn_puestos_resueltos(date,date)', 'EXECUTE')
  and not has_function_privilege('anon', 'fn_set_puesto_base(uuid,date,text,text)', 'EXECUTE'),
  'anon no lee ni cambia el puesto base');

select * from finish();
rollback;
