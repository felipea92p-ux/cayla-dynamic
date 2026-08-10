-- ============================================================================
-- 110_un_periodo_pagado_no_cambia_de_horas.test.sql
-- ============================================================================
-- El caso real que esto cierra:
--
--   Una persona marcó su almuerzo el 16 de junio con la Mac mini sin internet.
--   Las marcas quedaron en la cola offline. El periodo de junio se pagó con lo
--   que había subido: entrada 09:00 y salida 18:00, nueve horas.
--   El 4 de agosto la Mac vuelve a tener red y sube el par del almuerzo.
--
-- Medido contra el Postgres local antes de la 0138: el día pasaba de 9.00 h a
-- 8.00 h. La foto del pago (0096) sostenía el monto, así que nadie cobraba de
-- menos — pero `jornadas` dejaba de coincidir con lo que se pagó, y no había
-- quien explicara la diferencia.
--
-- Las dos mitades que este archivo defiende, y que se contradicen si una se
-- rompe: la marca REAL nunca se pierde, y el número YA PAGADO nunca se mueve.
-- Si alguien "arregla" el candado lanzando una excepción, la mitad de arriba
-- cae: la terminal descarta la marca tras seis reintentos.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ad00', 'ZZPAG', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000ad01', 'PagAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ad00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ad09');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-00000000ad02', 'PagPagada',  'Laboratorio', '00000000-0000-0000-0000-00000000ad00', 'test-hash'),
  ('00000000-0000-0000-0000-00000000ad03', 'PagAbierta', 'Laboratorio', '00000000-0000-0000-0000-00000000ad00', 'test-hash');

-- El terminal necesita dueño desde la 0202: `terminal_activo_con_dueno` prohíbe
-- que uno ACTIVO tenga `auth_user_id` nulo, y este montaje se escribió cuando esa
-- regla no existía. El replica_role salta la FK contra auth.users, que en las
-- pruebas no existe; los CHECK no son triggers y siguen aplicando.
set session_replication_role = replica;
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000000ad0e', '00000000-0000-0000-0000-00000000ad00',
        'Mac mini de laboratorio', true, '00000000-0000-0000-0000-00000000ad0f');
set session_replication_role = origin;

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select p, '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6], 48,
       '{"0":{"e":"09:00","s":"18:00","r":60},"1":{"e":"09:00","s":"18:00","r":60},
         "2":{"e":"09:00","s":"18:00","r":60},"3":{"e":"09:00","s":"18:00","r":60},
         "4":{"e":"09:00","s":"18:00","r":60},"5":{"e":"09:00","s":"18:00","r":60},
         "6":{"e":"09:00","s":"18:00","r":60}}'::jsonb
from unnest(array['00000000-0000-0000-0000-00000000ad02'::uuid,
                  '00000000-0000-0000-0000-00000000ad03'::uuid]) p;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ad09', true);

-- ── El escenario: junio pagado, agosto abierto ──────────────────────────────
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000ad00', 'entrada',      '2026-06-16T09:00:00-05:00', 'terminal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000ad00', 'salida_final', '2026-06-16T18:00:00-05:00', 'terminal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-00000000ad00', 'entrada',      '2026-08-03T09:00:00-05:00', 'terminal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-00000000ad00', 'salida_final', '2026-08-03T18:00:00-05:00', 'terminal');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-00000000adaa', '2026-06-01', '2026-06-30', 'pagado'),
  ('00000000-0000-0000-0000-00000000adbb', '2026-08-01', '2026-08-31', 'abierto');

select is((select horas_trabajadas from jornadas
            where persona_id = '00000000-0000-0000-0000-00000000ad02' and fecha = '2026-06-16'),
          9.00::numeric,
          'DE PARTIDA · el 16 de junio se pagó con 9.00 h');

-- ── 1 · La cola offline sube el par de almuerzo de un día YA PAGADO ─────────
--
-- LA SESIÓN PASA A SER LA DEL TERMINAL, y esto no es ceremonia: desde que el
-- terminal tiene dueño (0202), fn_registrar_marcaje compara auth.uid() contra
-- `terminales.auth_user_id` y rechaza la marca si no coinciden. Es exactamente
-- lo que pasa en producción —la Mac mini marca con su propia cuenta, no con la
-- de una persona—, así que el montaje se parece más a la realidad que antes.
-- Más abajo se vuelve a la de admin, que es la que fn_dias_por_revisar exige.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ad0f', true);

select lives_ok(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-00000000ad02'::uuid, 'salida_almuerzo'::tipo_marca,
       '2026-06-16T13:00:00-05:00'::timestamptz, gen_random_uuid(),
       'terminal'::origen_marca, '00000000-0000-0000-0000-00000000ad0e'::uuid) $$,
  'PAGADO · la marca atrasada ENTRA: no se rechaza, no se pierde');

select lives_ok(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-00000000ad02'::uuid, 'retorno_almuerzo'::tipo_marca,
       '2026-06-16T14:00:00-05:00'::timestamptz, gen_random_uuid(),
       'terminal'::origen_marca, '00000000-0000-0000-0000-00000000ad0e'::uuid) $$,
  'PAGADO · y la segunda del par también entra');

select is((select count(*)::int from marcajes
            where persona_id = '00000000-0000-0000-0000-00000000ad02'
              and (timestamp_marca at time zone 'America/Lima')::date = '2026-06-16'
              and anulada_at is null),
          4,
          'PAGADO · las cuatro marcas del día están guardadas: la verdad no se perdió');

-- Ésta es la mitad que la 0138 agrega. Antes daba 8.00.
select is((select horas_trabajadas from jornadas
            where persona_id = '00000000-0000-0000-0000-00000000ad02' and fecha = '2026-06-16'),
          9.00::numeric,
          'PAGADO · pero el día sigue con las 9.00 h que se pagaron: no se movió solo');

-- ── 2 · Y el día no queda mudo ──────────────────────────────────────────────
-- Vuelve la sesión de admin: fn_dias_por_revisar filtra por fn_es_admin_o_lider()
-- y con la cuenta del terminal devolvería cero filas — el número correcto por el
-- motivo equivocado.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ad09', true);

select isnt((select count(*)::int from fn_dias_por_revisar(120)
              where persona_id = '00000000-0000-0000-0000-00000000ad02'),
            0,
            'PAGADO · el día aparece para revisión: se avisa, no se esconde');

-- ── 3 · Fuera de un periodo pagado, el recálculo sigue igual que siempre ────
-- Y otra vez la del terminal, porque vuelve a marcar.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ad0f', true);

select fn_registrar_marcaje(
  '00000000-0000-0000-0000-00000000ad03'::uuid, 'salida_almuerzo'::tipo_marca,
  '2026-08-03T13:00:00-05:00'::timestamptz, gen_random_uuid(),
  'terminal'::origen_marca, '00000000-0000-0000-0000-00000000ad0e'::uuid);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-00000000ad03'::uuid, 'retorno_almuerzo'::tipo_marca,
  '2026-08-03T14:00:00-05:00'::timestamptz, gen_random_uuid(),
  'terminal'::origen_marca, '00000000-0000-0000-0000-00000000ad0e'::uuid);

select is((select horas_trabajadas from jornadas
            where persona_id = '00000000-0000-0000-0000-00000000ad03' and fecha = '2026-08-03'),
          8.00::numeric,
          'ABIERTO · en un periodo abierto el almuerzo sí descuenta: el candado no apagó el cálculo');

select * from finish();
rollback;
