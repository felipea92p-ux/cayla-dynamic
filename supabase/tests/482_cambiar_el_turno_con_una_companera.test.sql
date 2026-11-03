-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 482_cambiar_el_turno_con_una_companera.test.sql
-- ============================================================================
-- La 0592. Lo que importa: que solo se cambie con una compañera de la misma
-- sede, el mismo día y un turno del mismo largo; que nada se mueva hasta que
-- la compañera acepte y la líder apruebe; que al aprobar se intercambien los
-- DOS turnos con su rastro; que si un turno cambió en el medio no se aplique
-- nada; que desde «Este día no me calza» baste con que la compañera acepte y
-- el pedido quede resuelto; y que nadie escriba la tabla sin las funciones.
-- ============================================================================
begin;
select plan(30);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000048200', 'ZZCMA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000048201', 'ZZCMB', 'Sede de laboratorio B', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-000000048210', 'CamDO', 'Lab', '00000000-0000-0000-0000-000000048200', 'lider_do', 'x',
   '00000000-0000-0000-0000-0000000482a0', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000048211', 'CamLiderA', 'Lab', '00000000-0000-0000-0000-000000048200', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000482a1', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000048212', 'CamLiderB', 'Lab', '00000000-0000-0000-0000-000000048201', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000482a2', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000048213', 'CamX', 'Lab', '00000000-0000-0000-0000-000000048200', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000482a3', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000048214', 'CamY', 'Lab', '00000000-0000-0000-0000-000000048200', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000482a4', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000048215', 'CamZ', 'Lab', '00000000-0000-0000-0000-000000048200', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000482a5', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000048216', 'CamW', 'Lab', '00000000-0000-0000-0000-000000048201', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000482a6', '2024-01-01', 'activo');
set session_replication_role = origin;

create temporary table _ids (clave text primary key, id uuid);
grant all on _ids to authenticated;
create temporary table _f as select fn_hoy_lima() + 3 as d1, fn_hoy_lima() + 4 as d2, fn_hoy_lima() + 5 as d3;
grant select on _f to authenticated;

-- X mañana, Y tarde (mismo largo: 6 h), Z de 8 h, W en otra sede.
insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen)
select p, f, e, s, false, 'panel'
  from (values ('00000000-0000-0000-0000-000000048213'::uuid, '08:30'::time, '14:30'::time),
               ('00000000-0000-0000-0000-000000048214'::uuid, '14:00'::time, '20:00'::time),
               ('00000000-0000-0000-0000-000000048215'::uuid, '10:00'::time, '18:00'::time),
               ('00000000-0000-0000-0000-000000048216'::uuid, '14:00'::time, '20:00'::time)) v(p, e, s),
       (select d1 as f from _f union all select d2 from _f union all select d3 from _f) fs;

-- ── 1-5 · Con quién y cuándo ─────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a3', true);
select is((select array_agg(persona_id) from fn_turno_cambio_candidatas((select d1 from _f))),
  array['00000000-0000-0000-0000-000000048214'::uuid],
  'con quién se puede: solo la de su sede con un turno distinto del mismo largo');
select throws_ok(format('select fn_turno_cambio_proponer(%L, %L)', (select d1 from _f), '00000000-0000-0000-0000-000000048215'),
  'P0001', null, 'con un turno de otro largo, no');
select throws_ok(format('select fn_turno_cambio_proponer(%L, %L)', (select d1 from _f), '00000000-0000-0000-0000-000000048216'),
  'P0001', null, 'con alguien de otra sede, no');
select throws_ok(format('select fn_turno_cambio_proponer(%L, %L)', fn_hoy_lima() - 1, '00000000-0000-0000-0000-000000048214'),
  'P0001', 'Ese día ya pasó.', 'un día que ya pasó, no');
select throws_ok(format('select fn_turno_cambio_proponer(%L, %L)', fn_hoy_lima() + 22, '00000000-0000-0000-0000-000000048214'),
  'P0001', 'Solo se cambian turnos de las próximas tres semanas.', 'más allá de tres semanas, no');

-- ── 6-10 · Ella propone; nada se mueve todavía ───────────────────────────────
insert into _ids select 'c1', fn_turno_cambio_proponer((select d1 from _f), '00000000-0000-0000-0000-000000048214', 'Tengo clase en la mañana');
select is((select estado from turno_cambios where id = (select id from _ids where clave = 'c1')), 'propuesto', 'queda propuesto');
select throws_ok(format('select fn_turno_cambio_proponer(%L, %L)', (select d1 from _f), '00000000-0000-0000-0000-000000048214'),
  'P0001', null, 'no hay dos propuestas vivas para el mismo día');
select throws_ok(format('select fn_turno_cambio_contestar(%L, true)', (select id from _ids where clave = 'c1')),
  'P0001', null, 'quien lo propuso no lo contesta por la compañera');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a1', true);
select throws_ok(format('select fn_turno_cambio_resolver(%L, true)', (select id from _ids where clave = 'c1')),
  'P0001', null, 'la líder no lo aprueba antes de que la compañera acepte');
select is((select hora_entrada from turnos where persona_id = '00000000-0000-0000-0000-000000048213' and fecha = (select d1 from _f)),
  '08:30'::time, 'mientras tanto, su turno sigue igual');

-- ── 11-14 · La compañera acepta; la líder aprueba ────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a4', true);
select lives_ok(format('select fn_turno_cambio_contestar(%L, true, ''Sí, sin problema'')', (select id from _ids where clave = 'c1')),
  'la compañera acepta');
select is((select hora_entrada from turnos where persona_id = '00000000-0000-0000-0000-000000048214' and fecha = (select d1 from _f)),
  '14:00'::time, 'aceptar no lo aplica: falta la líder');
select throws_ok(format('select fn_turno_cambio_resolver(%L, true)', (select id from _ids where clave = 'c1')),
  'P0001', null, 'una integrante no lo aprueba');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a2', true);
select throws_ok(format('select fn_turno_cambio_resolver(%L, true)', (select id from _ids where clave = 'c1')),
  'P0001', null, 'ni una líder de otra sede');

-- ── 15-19 · Aprobado: se intercambian los dos, con rastro ───────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a1', true);
select throws_ok(format('select fn_turno_cambio_resolver(%L, false, ''no'')', (select id from _ids where clave = 'c1')),
  'P0001', null, 'no aprobar exige explicar por qué');
select lives_ok(format('select fn_turno_cambio_resolver(%L, true)', (select id from _ids where clave = 'c1')),
  'su líder lo aprueba');
select ok((select bool_and(case persona_id when '00000000-0000-0000-0000-000000048213'::uuid
                                    then hora_entrada = '14:00' and hora_salida = '20:00'
                                    else hora_entrada = '08:30' and hora_salida = '14:30' end)
             from turnos where fecha = (select d1 from _f)
              and persona_id in ('00000000-0000-0000-0000-000000048213', '00000000-0000-0000-0000-000000048214')),
  'los dos turnos quedaron intercambiados');
select is((select count(*)::int from correcciones_auditoria
            where campo_modificado = 'turnos.horario'
              and persona_id in ('00000000-0000-0000-0000-000000048213', '00000000-0000-0000-0000-000000048214')
              and corregido_por = '00000000-0000-0000-0000-000000048211'
              and motivo like 'Turno del ' || to_char((select d1 from _f), 'DD/MM/YYYY') || ' cambiado con una compañera%'),
  2, 'deja un rastro por cada una, firmado por la líder, con el día al principio');
select is((select estado from turno_cambios where id = (select id from _ids where clave = 'c1')), 'aprobado', 'queda aprobado');

-- ── 20-22 · Si un turno cambió en el medio, no se aplica nada ───────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a3', true);
insert into _ids select 'c2', fn_turno_cambio_proponer((select d2 from _f), '00000000-0000-0000-0000-000000048214');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a4', true);
select fn_turno_cambio_contestar((select id from _ids where clave = 'c2'), true);
update turnos set hora_salida = '20:30', hora_entrada = '14:30'
 where persona_id = '00000000-0000-0000-0000-000000048214' and fecha = (select d2 from _f);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a1', true);
select throws_ok(format('select fn_turno_cambio_resolver(%L, true)', (select id from _ids where clave = 'c2')),
  'P0001', 'Uno de los dos turnos cambió desde que se propuso el cambio. Hay que proponerlo de nuevo.',
  'si un turno cambió desde la propuesta, se niega');
select is((select hora_entrada from turnos where persona_id = '00000000-0000-0000-0000-000000048213' and fecha = (select d2 from _f)),
  '08:30'::time, 'y no mueve el otro: los dos o ninguno');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a4', true);
select throws_ok(format('select fn_turno_cambio_retirar(%L)', (select id from _ids where clave = 'c2')),
  'P0001', null, 'la compañera no retira lo que propuso otra');

-- ── 23-26 · Desde «Este día no me calza»: lo propone la líder ────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a3', true);
select fn_turno_cambio_retirar((select id from _ids where clave = 'c2'));
insert into _ids select 'p1', fn_turno_pedido_crear((select d3 from _f), 'estudios', 'tarde');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a2', true);
select throws_ok(format('select fn_turno_cambio_proponer_por_pedido(%L, %L)', (select id from _ids where clave = 'p1'),
  '00000000-0000-0000-0000-000000048214'), 'P0001', null, 'una líder de otra sede no lo propone');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a1', true);
insert into _ids select 'c3', fn_turno_cambio_proponer_por_pedido((select id from _ids where clave = 'p1'),
  '00000000-0000-0000-0000-000000048214');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a4', true);
select lives_ok(format('select fn_turno_cambio_contestar(%L, true)', (select id from _ids where clave = 'c3')),
  'la compañera acepta lo que propuso la líder');
select is((select hora_entrada from turnos where persona_id = '00000000-0000-0000-0000-000000048213' and fecha = (select d3 from _f)),
  '14:00'::time, 'y se aplica en el acto: la líder ya lo había aprobado al proponerlo');
select ok((select estado = 'resuelto' and resolucion = 'cambio_companera' and resuelto_por = '00000000-0000-0000-0000-000000048211'
             from turno_pedidos where id = (select id from _ids where clave = 'p1')),
  'el pedido de «Este día no me calza» queda resuelto como cambio con una compañera');

-- ── 27-30 · Lo que ve cada una, y nadie escribe directo ──────────────────────
select is((select count(*)::int from fn_turno_cambios_mios() where otra_nombre = 'CamX Lab' and soy = 'companera'),
  3, 'la compañera ve sus cambios con el nombre de la otra');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000482a5', true);
select is((select count(*)::int from turno_cambios), 0, 'otra compañera no ve los cambios de las demás');
select throws_ok(format('select * from fn_turno_cambio_candidatas(%L, %L)', (select d1 from _f), '00000000-0000-0000-0000-000000048213'),
  'P0001', 'No autorizado.', 'ni puede pedir con quién cambiaría otra');
select throws_ok($$insert into turno_cambios (fecha, solicitante_id, companera_id, propuesto_por, sol_entrada, sol_salida, comp_entrada, comp_salida)
                   values (current_date + 2, '00000000-0000-0000-0000-000000048215', '00000000-0000-0000-0000-000000048213',
                           '00000000-0000-0000-0000-000000048215', '08:00', '14:00', '14:00', '20:00')$$,
  '42501', null, 'nadie escribe la tabla sin las funciones');
reset role;

select * from finish();
rollback;
