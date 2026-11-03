-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 474_cada_quien_dice_cuando_puede_trabajar.test.sql
-- ============================================================================
-- La 0584: la jornada que fija DO y la disponibilidad de cada quien. Lo que
-- importa: que lo enviado no se use hasta aprobarse; quién puede aprobar (su
-- líder de equipo, DO o admin, nunca la propia, y una líder de otra sede no);
-- que una aprobada nueva recorte a la anterior; que los bloques no se crucen
-- ni salgan de la media hora; que el contrato de lectura diga exactamente
-- no_puede / prefiere_no / horario_fijo por fecha; que la RLS no le muestre
-- a una compañera lo de otra; y que nadie escriba nada sin las funciones.
-- ============================================================================
begin;
select plan(42);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000047400', 'ZZDIA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000047401', 'ZZDIB', 'Sede de laboratorio B', true, 'tienda');

-- Todas con cuenta (auth_user_id) que no existe en auth.users: con los
-- disparadores apagados, como en la 470.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, fecha_cese)
values
  ('00000000-0000-0000-0000-000000047410', 'DispAdmin', 'Lab', '00000000-0000-0000-0000-000000047400', 'admin', 'x',
   '00000000-0000-0000-0000-0000000474a0', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047411', 'DispLiderA', 'Lab', '00000000-0000-0000-0000-000000047400', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000474a1', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047412', 'DispLiderB', 'Lab', '00000000-0000-0000-0000-000000047401', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000474a2', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047413', 'DispX', 'Lab', '00000000-0000-0000-0000-000000047400', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000474a3', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047414', 'DispY', 'Lab', '00000000-0000-0000-0000-000000047400', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000474a4', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047417', 'DispLiderA2', 'Lab', '00000000-0000-0000-0000-000000047400', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000474a7', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000047415', 'DispCesada', 'Lab', '00000000-0000-0000-0000-000000047400', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000474a5', '2024-01-01', 'inactivo', '2026-01-31');

-- La ventana de la sede A sale de estos dos horarios: lunes 08:30–14:30 y
-- 13:00–20:15, y el domingo solo uno.
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables, horario_por_dia)
values
  ('00000000-0000-0000-0000-000000047413', '2024-01-01', '08:30', '14:30', '{1,0}',
   '{"1": {"e": "08:30", "s": "14:30"}, "0": {"e": "10:00", "s": "16:00"}}'),
  ('00000000-0000-0000-0000-000000047414', '2024-01-01', '13:00', '20:15', '{1}',
   '{"1": {"e": "13:00", "s": "20:15"}}');
set session_replication_role = origin;

-- Sin cuenta: a ella se le fija la jornada (un update sobre una fila creada en
-- esta misma transacción vuelve a revisar la clave de auth_user_id).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-000000047416', 'DispZ', 'Lab', '00000000-0000-0000-0000-000000047400', 'x', '2024-01-01', 'activo');

create temporary table _ids (clave text primary key, id uuid);
grant all on _ids to authenticated;

-- El lunes de la semana que viene: para que todo caiga «de hoy en adelante».
create temporary table _f as
  select (fn_hoy_lima() + (8 - extract(isodow from fn_hoy_lima())::int))::date as lunes;
grant select on _f to authenticated;

-- ── 1-4 · X envía; lo enviado no se usa ──────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a3', true);

insert into _ids
select 'x1', fn_disponibilidad_enviar('parcial', 'estudios', (select lunes from _f), null,
  jsonb_build_array(
    jsonb_build_object('dia_semana', 2, 'desde', '08:30', 'hasta', '14:00', 'estado', 'no_puede'),
    jsonb_build_object('dia_semana', 0, 'estado', 'prefiere_no'),
    jsonb_build_object('fecha', (select lunes + 3 from _f), 'desde', '16:00', 'hasta', '20:00', 'estado', 'no_puede')
  ));

select is((select estado from disponibilidades where id = (select id from _ids where clave = 'x1')),
  'enviada', 'lo que manda la colaboradora queda enviada');
select is((select count(*)::int from disponibilidad_bloques where disponibilidad_id = (select id from _ids where clave = 'x1')),
  3, 'con sus tres bloques: un día de la semana con horas, uno entero y una fecha');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a0', true);
select is((select count(*)::int from fn_disponibilidad_vigente((select lunes from _f), (select lunes + 6 from _f),
             '00000000-0000-0000-0000-000000047400')),
  0, 'lo enviado NO se usa hasta que se aprueba');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a3', true);
select throws_ok(
  format('select fn_disponibilidad_resolver(%L, ''aprobar'')', (select id from _ids where clave = 'x1')),
  'P0001', null, 'nadie aprueba su propia disponibilidad');

-- ── 5-8 · Quién resuelve ─────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a2', true);
select throws_ok(
  format('select fn_disponibilidad_resolver(%L, ''aprobar'')', (select id from _ids where clave = 'x1')),
  'P0001', null, 'la líder de OTRA sede no la resuelve');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a1', true);
select throws_ok(
  format('select fn_disponibilidad_resolver(%L, ''conversar'', '''')', (select id from _ids where clave = 'x1')),
  'P0001', null, '«conversar» exige escribir qué se quiere conversar');

select lives_ok(
  format('select fn_disponibilidad_resolver(%L, ''aprobar'', ''Ok, lo vemos en la sugerencia'', true)',
         (select id from _ids where clave = 'x1')),
  'su líder de equipo la aprueba y marca horario fijo');
select ok((select estado = 'aprobada' and horario_fijo and resuelta_por = '00000000-0000-0000-0000-000000047411'
             from disponibilidades where id = (select id from _ids where clave = 'x1')),
  'queda aprobada, con horario fijo y con quién la resolvió');

-- ── 9-16 · El contrato de lectura ────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a0', true);
create temporary table _v as
  select * from fn_disponibilidad_vigente((select lunes from _f), (select lunes + 6 from _f),
                                          '00000000-0000-0000-0000-000000047400');

select is((select count(*)::int from _v where estado = 'horario_fijo'),
  7, 'horario fijo: una fila por cada día del rango, sin horas');
select is((select to_char(desde, 'HH24:MI') || '-' || to_char(hasta, 'HH24:MI') from _v
            where estado = 'no_puede' and fecha = (select lunes + 1 from _f)),
  '08:30-14:00', 'el martes de la semana tipo sale con sus horas exactas');
select ok((select desde is null and hasta is null from _v
            where estado = 'prefiere_no' and fecha = (select lunes + 6 from _f)),
  'el domingo entero sale como prefiere_no sin horas (= todo el día)');
select is((select to_char(desde, 'HH24:MI') from _v
            where estado = 'no_puede' and fecha = (select lunes + 3 from _f)),
  '16:00', 'la fecha puntual sale solo ese día');
select is((select count(*)::int from _v where estado <> 'horario_fijo'),
  3, 'y nada más: los otros días puede todo');
select is((select count(*)::int from fn_disponibilidad_vigente((select lunes from _f), (select lunes + 6 from _f),
             '00000000-0000-0000-0000-000000047400', now() - interval '1 minute')),
  0, 'el corte semanal (p_aprobada_antes) deja fuera lo aprobado después');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a2', true);
select throws_ok(
  format('select * from fn_disponibilidad_vigente(%L, %L, %L)', (select lunes from _f), (select lunes + 6 from _f),
         '00000000-0000-0000-0000-000000047400'),
  'P0001', null, 'la líder de otra sede no lee el contrato de la sede A');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a4', true);
select throws_ok(
  format('select * from fn_disponibilidad_vigente(%L, %L, %L)', (select lunes from _f), (select lunes + 6 from _f),
         '00000000-0000-0000-0000-000000047400'),
  'P0001', null, 'una integrante no lee el contrato');

-- ── 17-21 · Validaciones al enviar ───────────────────────────────────────────
select throws_ok(
  format('select fn_disponibilidad_enviar(''parcial'', ''hijos'', %L, null, %L)', fn_hoy_lima() - 1,
         '[{"dia_semana":1,"estado":"no_puede"}]'),
  'P0001', null, 'no se cambia un día que ya pasó');
select throws_ok(
  format('select fn_disponibilidad_enviar(''total'', null, %L, null, %L)', fn_hoy_lima(),
         '[{"dia_semana":1,"estado":"no_puede"}]'),
  'P0001', null, '«Cualquier día y hora» no lleva bloques');
select throws_ok(
  format('select fn_disponibilidad_enviar(''parcial'', null, %L, null, %L)', fn_hoy_lima(),
         '[{"dia_semana":1,"estado":"no_puede"}]'),
  'P0001', null, 'si hay días que no puede, va el motivo');
select throws_ok(
  format('select fn_disponibilidad_enviar(''parcial'', ''hijos'', %L, null, %L)', fn_hoy_lima(),
         '[{"dia_semana":1,"desde":"08:30","hasta":"12:00","estado":"no_puede"},{"dia_semana":1,"desde":"11:00","hasta":"13:00","estado":"prefiere_no"}]'),
  'P0001', 'Dos tramos del mismo día se cruzan. Júntalos en uno.', 'dos tramos del mismo día no se cruzan');
select throws_ok(
  format('select fn_disponibilidad_enviar(''parcial'', ''hijos'', %L, null, %L)', fn_hoy_lima(),
         '[{"dia_semana":1,"desde":"08:15","hasta":"12:00","estado":"no_puede"}]'),
  'P0001', null, 'las horas van de media en media hora');

-- ── 22-25 · Una nueva reemplaza; una aprobada recorta a la anterior ──────────
insert into _ids select 'y1', fn_disponibilidad_enviar('parcial', 'salud', fn_hoy_lima(), null,
  '[{"dia_semana":3,"estado":"no_puede"}]');
insert into _ids select 'y2', fn_disponibilidad_enviar('parcial', 'salud', fn_hoy_lima(), null,
  '[{"dia_semana":4,"estado":"no_puede"}]');
select is((select string_agg(estado, ',' order by creada_at, id) from disponibilidades
            where persona_id = '00000000-0000-0000-0000-000000047414'),
  (select case when (select id from _ids where clave = 'y1') < (select id from _ids where clave = 'y2')
               then 'reemplazada,enviada' else 'enviada,reemplazada' end),
  'mandar otra deja UNA sola enviada: la anterior queda reemplazada');

select lives_ok(
  format('select fn_disponibilidad_retirar(%L)', (select id from _ids where clave = 'y2')),
  'puede retirar la suya mientras espera');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a3', true);
insert into _ids select 'x2', fn_disponibilidad_enviar('total', null, (select lunes + 3 from _f), null, '[]');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a0', true);
select fn_disponibilidad_resolver((select id from _ids where clave = 'x2'), 'aprobar');
select is((select vigente_hasta from disponibilidades where id = (select id from _ids where clave = 'x1')),
  (select lunes + 2 from _f), 'la aprobada anterior se recorta al día antes de la nueva');
select is((select count(*)::int from fn_disponibilidad_vigente((select lunes + 3 from _f), (select lunes + 6 from _f),
             '00000000-0000-0000-0000-000000047400')),
  0, 'desde la nueva («cualquier día y hora», sin horario fijo) ya no hay restricciones');

-- ── 26-29 · La disponibilidad de una líder de equipo, y registrar por otra ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a1', true);
insert into _ids select 'l1', fn_disponibilidad_enviar('parcial', 'hijos', fn_hoy_lima(), null,
  '[{"dia_semana":5,"estado":"no_puede"}]');
select throws_ok(
  format('select fn_disponibilidad_resolver(%L, ''aprobar'')', (select id from _ids where clave = 'l1')),
  'P0001', null, 'la líder no aprueba la suya');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a2', true);
select throws_ok(
  format('select fn_disponibilidad_resolver(%L, ''aprobar'')', (select id from _ids where clave = 'l1')),
  'P0001', null, 'ni otra líder de equipo: la de una líder la resuelve DO');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a7', true);
select throws_ok(
  format('select fn_disponibilidad_resolver(%L, ''aprobar'')', (select id from _ids where clave = 'l1')),
  'P0001', null, 'ni otra líder de la MISMA sede: entre líderes no se aprueban');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a0', true);
insert into _ids select 'a1', fn_disponibilidad_enviar('parcial', 'otro', fn_hoy_lima(), null,
  '[{"dia_semana":2,"estado":"prefiere_no"}]');
select throws_ok(
  format('select fn_disponibilidad_resolver(%L, ''aprobar'')', (select id from _ids where clave = 'a1')),
  'P0001', null, 'ni un admin se aprueba a sí mismo');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a2', true);
select throws_ok(
  format('select fn_disponibilidad_registrar(%L, ''total'', null, %L, null, ''[]'')',
         '00000000-0000-0000-0000-000000047414', fn_hoy_lima()),
  'P0001', null, 'una líder de equipo no registra por otra persona');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a0', true);
insert into _ids select 'y3', fn_disponibilidad_registrar('00000000-0000-0000-0000-000000047414', 'parcial', 'otro_trabajo',
  fn_hoy_lima(), null, '[{"dia_semana":6,"desde":"14:00","hasta":"20:30","estado":"no_puede"}]', false, 'Registrada por DO');
select ok((select estado = 'aprobada' and registrada_por = '00000000-0000-0000-0000-000000047410'
             from disponibilidades where id = (select id from _ids where clave = 'y3')),
  'lo que registra DO entra aprobado y dice quién lo registró');

-- ── 30-33 · RLS ──────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a4', true);
set local role authenticated;
select ok((select bool_and(persona_id = '00000000-0000-0000-0000-000000047414') and count(*) > 0 from disponibilidades),
  'una integrante solo ve las suyas');
select is((select count(*)::int from disponibilidad_bloques b
            join disponibilidades d on d.id = b.disponibilidad_id
           where d.persona_id = '00000000-0000-0000-0000-000000047413'),
  0, 'ni los bloques de su compañera');
select throws_ok(
  format('insert into disponibilidades (persona_id, tipo, vigente_desde, registrada_por) values (%L, ''total'', %L, %L)',
         '00000000-0000-0000-0000-000000047414', fn_hoy_lima(), '00000000-0000-0000-0000-000000047414'),
  '42501', null, 'nadie escribe la tabla sin la función');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a1', true);
set local role authenticated;
select is((select count(distinct persona_id)::int from disponibilidades),
  4, 'la líder de equipo ve las de su sede (X, Y, la suya y la del admin de esa sede)');
reset role;

-- ── 34-37 · La jornada ───────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a1', true);
select throws_ok(
  format('select fn_set_jornada(%L, 45, ''Contrato completo'')', '00000000-0000-0000-0000-000000047416'),
  'P0001', null, 'la líder de equipo no fija la jornada');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a0', true);
select fn_set_jornada('00000000-0000-0000-0000-000000047416', 30, 'Contrato a tiempo parcial');
select is((select jornada_semanal_horas from personas where id = '00000000-0000-0000-0000-000000047416'),
  30.00::numeric, 'DO fija la jornada');
select is((select valor_nuevo from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000047416' and campo_modificado = 'personas.jornada_semanal_horas'),
  '30', 'y deja rastro');

set local role authenticated;
select throws_ok(
  format('update personas set jornada_semanal_horas = 48 where id = %L', '00000000-0000-0000-0000-000000047416'),
  null, null, 'la jornada no se cambia con un update directo');
reset role;

-- ── 38-40 · La ventana de la sede y quien ya no está ─────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a3', true);
select is((select to_char(abre, 'HH24:MI') || '-' || to_char(cierra, 'HH24:MI') from fn_sede_ventana_semanal(
             '00000000-0000-0000-0000-000000047400') where dia = 1),
  '08:30-20:15', 'la ventana del lunes: la entrada más temprana y la salida más tarde del equipo');
select is((select count(*)::int from fn_sede_ventana_semanal('00000000-0000-0000-0000-000000047400')),
  2, 'solo los días en que alguien trabaja (lunes y domingo)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000474a5', true);
select throws_ok(
  format('select fn_disponibilidad_enviar(''total'', null, %L, null, ''[]'')', fn_hoy_lima()),
  'P0001', null, 'quien ya no está activa no envía nada');

select * from finish();
rollback;
