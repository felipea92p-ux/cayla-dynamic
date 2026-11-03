-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 481_prefiero_trabajar_en_la_disponibilidad.test.sql
-- ============================================================================
-- La 0591: «prefiero trabajar» es un estado más de un bloque de disponibilidad,
-- y 'preferencia' es el motivo de quien solo marcó eso. Lo que importa: que el
-- estado nuevo se guarde y salga por el contrato de lectura de Turnos; que un
-- estado o un motivo inventado se rechacen; que el motivo siga siendo
-- obligatorio en una parcial; que un cruce se rechace sea cual sea el estado; y
-- que los CHECK viejos hayan quedado reemplazados por uno solo cada uno.
-- ============================================================================
begin;
select plan(13);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000048100', 'ZZPTA', 'Sede de laboratorio PT', true, 'tienda');

-- Con cuenta (auth_user_id) que no existe en auth.users: con los disparadores
-- apagados, como en la 474.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, fecha_cese)
values
  ('00000000-0000-0000-0000-000000048111', 'PtLider', 'Lab', '00000000-0000-0000-0000-000000048100', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000481a1', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000048113', 'PtX', 'Lab', '00000000-0000-0000-0000-000000048100', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000481a3', '2024-01-01', 'activo', null);
set session_replication_role = origin;

-- El lunes de la semana que viene: para que todo caiga «de hoy en adelante».
create temporary table _f as
  select (fn_hoy_lima() + (8 - extract(isodow from fn_hoy_lima())::int))::date as lunes;
grant select on _f to authenticated;

-- ── 1-6 · Quien solo prefiere trabajar: se guarda, se aprueba y Turnos lo lee ─
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000481a3', true);

select lives_ok(
  format($q$select fn_disponibilidad_enviar('parcial', 'preferencia', %L, null,
    jsonb_build_array(
      jsonb_build_object('dia_semana', 2, 'estado', 'prefiere_trabajar'),
      jsonb_build_object('fecha', %L::date, 'desde', '16:00', 'hasta', '20:00', 'estado', 'prefiere_trabajar')
    ))$q$, (select lunes from _f), (select lunes + 3 from _f)),
  'una parcial con solo «prefiero trabajar» y motivo «preferencia» se envía');

select is((select count(*)::int from disponibilidad_bloques b join disponibilidades d on d.id = b.disponibilidad_id
            where d.persona_id = '00000000-0000-0000-0000-000000048113' and b.estado = 'prefiere_trabajar'),
  2, 'con sus dos bloques: un día de la semana entero y una fecha con horas');

select is((select motivo from disponibilidades where persona_id = '00000000-0000-0000-0000-000000048113'
            and estado = 'enviada'),
  'preferencia', 'y queda con el motivo «preferencia»');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000481a1', true);
select lives_ok(
  format('select fn_disponibilidad_resolver(%L, ''aprobar'')',
         (select id from disponibilidades where persona_id = '00000000-0000-0000-0000-000000048113' and estado = 'enviada')),
  'su líder de equipo la aprueba');

create temporary table _v as
  select * from fn_disponibilidad_vigente((select lunes from _f), (select lunes + 6 from _f),
                                          '00000000-0000-0000-0000-000000048100');

select is((select count(*)::int from _v where estado = 'prefiere_trabajar'),
  2, 'el contrato de lectura devuelve «prefiere_trabajar»: el martes y la fecha puntual');
select is((select to_char(desde, 'HH24:MI') || '-' || to_char(hasta, 'HH24:MI') from _v
            where estado = 'prefiere_trabajar' and fecha = (select lunes + 3 from _f)),
  '16:00-20:00', 'la fecha puntual sale con sus horas exactas');

-- ── 7-10 · Lo inventado y lo que sigue siendo obligatorio ────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000481a3', true);

select throws_ok(
  format($q$select fn_disponibilidad_enviar('parcial', 'salud', %L, null,
    jsonb_build_array(jsonb_build_object('dia_semana', 5, 'estado', 'siempre')))$q$, (select lunes from _f)),
  'P0001', null, 'un estado inventado se rechaza');

select throws_ok(
  format($q$select fn_disponibilidad_enviar('parcial', 'capricho', %L, null,
    jsonb_build_array(jsonb_build_object('dia_semana', 5, 'estado', 'prefiere_trabajar')))$q$, (select lunes from _f)),
  '23514', null, 'un motivo inventado se rechaza');

select throws_ok(
  format($q$select fn_disponibilidad_enviar('parcial', null, %L, null,
    jsonb_build_array(jsonb_build_object('dia_semana', 5, 'estado', 'prefiere_trabajar')))$q$, (select lunes from _f)),
  'P0001', null, 'una parcial sigue exigiendo motivo, también si solo prefiere trabajar');

select throws_ok(
  format($q$select fn_disponibilidad_enviar('parcial', 'salud', %L, null,
    jsonb_build_array(
      jsonb_build_object('dia_semana', 4, 'desde', '14:00', 'hasta', '18:00', 'estado', 'prefiere_trabajar'),
      jsonb_build_object('dia_semana', 4, 'desde', '16:00', 'hasta', '19:00', 'estado', 'no_puede')))$q$, (select lunes from _f)),
  'P0001', null, '«prefiero trabajar» y «no puedo» en la misma hora son un cruce: se rechaza');

-- ── 11-13 · Los CHECK viejos quedaron reemplazados ───────────────────────────
select is((select count(*)::int from pg_constraint
            where conrelid in ('disponibilidad_bloques'::regclass, 'disponibilidades'::regclass)
              and conname in ('disponibilidad_bloques_estado_check', 'disponibilidades_motivo_check')),
  0, 'los CHECK automáticos de dos y cinco valores ya no están');
select is((select count(*)::int from pg_constraint
            where conrelid = 'disponibilidad_bloques'::regclass and conname = 'disponibilidad_bloque_estado_valido'),
  1, 'hay uno solo para el estado del bloque, con nombre propio');
select is((select count(*)::int from pg_constraint
            where conrelid = 'disponibilidades'::regclass and conname = 'disponibilidad_motivo_valido'),
  1, 'y uno solo para el motivo');

select * from finish();
rollback;
