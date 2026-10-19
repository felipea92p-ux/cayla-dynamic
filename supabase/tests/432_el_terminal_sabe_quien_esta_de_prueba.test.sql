-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 432_el_terminal_sabe_quien_esta_de_prueba.test.sql — 0539
-- ============================================================================
-- Qué fija esta prueba, en orden de importancia:
--   · El terminal ve en qué día de prueba va quien está de prueba EN SU SEDE, y NULL
--     para todos los demás. Nada más: ni quién se retiró, ni de otra sede.
--   · El roster NO cambió de a quién ofrece: la 0539 solo agregó dos columnas.
--   · El terminal obtiene esos números SIN poder contar jornadas de cualquiera: la
--     función que las cuenta sigue cerrada para él.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000432a01', 'ZZTP1', 'Sede de laboratorio 1', true),
  ('00000000-0000-0000-0000-000000432a02', 'ZZTP2', 'Sede de laboratorio 2', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000432d01', 'EnPrueba',   'Lab', '00000000-0000-0000-0000-000000432a01', 'integrante', 'x', '2026-10-01', 'activo',   'prueba'),
  ('00000000-0000-0000-0000-000000432d02', 'DePlanilla', 'Lab', '00000000-0000-0000-0000-000000432a01', 'integrante', 'x', '2024-01-01', 'activo',   'planilla'),
  ('00000000-0000-0000-0000-000000432d03', 'OtraSede',   'Lab', '00000000-0000-0000-0000-000000432a02', 'integrante', 'x', '2026-10-01', 'activo',   'prueba'),
  ('00000000-0000-0000-0000-000000432d05', 'SinFila',    'Lab', '00000000-0000-0000-0000-000000432a01', 'integrante', 'x', '2026-10-05', 'activo',   'prueba');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, tipo_vinculo, fecha_cese, motivo_cese)
values ('00000000-0000-0000-0000-000000432d04', 'YaSeFue', 'Lab', '00000000-0000-0000-0000-000000432a01', 'integrante', 'x',
        '2026-10-01', 'inactivo', 'prueba', '2026-10-02', 'fin_periodo_prueba');
-- `replica` no dispara el trigger: SinFila es una persona de prueba a la que no se le pudo abrir su fila.
-- EnPrueba sí la tiene, a mano:
insert into pruebas (persona_id, inicio) values ('00000000-0000-0000-0000-000000432d01', '2026-10-01');

insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado, entrada_ts, salida_final_ts)
select p, d::date, '00000000-0000-0000-0000-000000432a01', 6, 'cerrada', (d::date || ' 09:00-05')::timestamptz, (d::date || ' 15:00-05')::timestamptz
  from (values ('00000000-0000-0000-0000-000000432d01'::uuid), ('00000000-0000-0000-0000-000000432d02'::uuid)) v(p),
       generate_series('2026-10-02'::date, '2026-10-03'::date, interval '1 day') d;
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado, entrada_ts, salida_final_ts) values
  ('00000000-0000-0000-0000-000000432d05', '2026-10-06', '00000000-0000-0000-0000-000000432a01', 6, 'cerrada', '2026-10-06 09:00-05', '2026-10-06 15:00-05');

insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-000000432e01', '00000000-0000-0000-0000-000000432a01', 'Mac mini 432', true,
        '00000000-0000-0000-0000-000000432f01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000432f01', true);
set role authenticated;

select is((select prueba_dias from terminal_roster where nombres = 'EnPrueba'), 2,
  'ETIQUETA · quien está de prueba en esta sede trae los días que lleva (2)');
select is((select prueba_plazo from terminal_roster where nombres = 'EnPrueba'), 3,
  'ETIQUETA · y cuánto dura la prueba, del mismo sitio que todo (fn_prueba_dias_plazo)');
select is((select prueba_dias from terminal_roster where nombres = 'SinFila'), 1,
  'SIN FILA · si la prueba no tiene su fila, cuenta desde su ingreso: el terminal no se queda sin etiqueta');
select is((select prueba_dias || '/' || prueba_plazo from terminal_roster where nombres = 'DePlanilla') is null, true,
  'NULL · quien no está de prueba trae NULL en las dos columnas');
select is_empty($$ select 1 from terminal_roster where nombres = 'OtraSede' $$,
  'AISLAMIENTO · quien está de prueba en otra sede no aparece');
select is_empty($$ select 1 from terminal_roster where nombres = 'YaSeFue' $$,
  'NADA DE MÁS · quien ya no está activo no aparece: el terminal no se entera de quién se fue');
select is((select count(*)::int from terminal_roster where id::text like '00000000-0000-0000-0000-000000432d%'), 3,
  'ROSTER · exactamente las tres personas activas de la sede, ni una más (la 0539 no cambió a quién se ofrece)');

-- El terminal obtiene los números SIN poder contar jornadas por su cuenta.
select ok(not has_function_privilege('authenticated', 'fn_prueba_dias_trabajados(uuid, date, date)', 'execute'),
  'SEGURIDAD · el terminal sigue sin poder ejecutar la función que cuenta jornadas de cualquiera');
select throws_like($$ select fn_prueba_dias_trabajados('00000000-0000-0000-0000-000000432d01', '2026-10-01') $$,
  '%permission denied%', 'SEGURIDAD · y si lo intenta, se le niega');
select is(fn_terminal_prueba_dias('00000000-0000-0000-0000-000000432d01'), 2,
  'PREGUNTA · lo único que sí puede preguntar: los días de quien su sede ofrece');
select is(fn_terminal_prueba_dias('00000000-0000-0000-0000-000000432d03'), null,
  'PREGUNTA · por alguien de prueba en OTRA sede, NULL: no puede usarla para contar jornadas ajenas');
select is(fn_terminal_prueba_dias('00000000-0000-0000-0000-000000432d02'), null,
  'PREGUNTA · y por quien no está de prueba, NULL');

reset role;
select ok(not has_table_privilege('anon', 'terminal_roster', 'select'), 'SEGURIDAD · sin sesión no se lee el roster');
select is((select string_agg(attname, ',' order by attnum) from pg_attribute
            where attrelid = 'public.terminal_roster'::regclass and attnum > 0 and not attisdropped),
  'id,nombres,apellidos,foto_url,sede_codigo,sede_nombre,prueba_dias,prueba_plazo',
  'COLUMNAS · las seis de siempre, y las dos nuevas al final');

select * from finish();
rollback;
