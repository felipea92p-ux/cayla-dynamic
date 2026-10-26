-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 409_do_se_entera_y_la_lider_tambien.test.sql
-- ============================================================================
-- La 0515 hace que la marca de «visto» de la Bandeja acepte los dos avisos de
-- conducta. La lista de tipos vive en DOS sitios —la restricción de la tabla y
-- la función—, y desde la 0436 se desincronizan en silencio: uno acepta lo que
-- el otro rechaza. Esta prueba fija que los dos dicen lo mismo.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000c1001', 'ZZBV1', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000c1011', 'LiderDO', 'Lab', '00000000-0000-0000-0000-0000000c1001', 'lider_do', 'x', '00000000-0000-0000-0000-0000000c10a1', '2020-01-01', 'activo', 'planilla');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000c10a1', true);

select lives_ok($$ select fn_bandeja_marcar_visto('conducta_registrada', '00000000-0000-0000-0000-0000000c10d1') $$,
  'LA FUNCIÓN · acepta el aviso de una falta registrada por una líder');
select lives_ok($$ select fn_bandeja_marcar_visto('caso_traspasado', '00000000-0000-0000-0000-0000000c10d2') $$,
  'LA FUNCIÓN · y el de un caso que DO tomó o devolvió');
select is((select count(*)::int from bandeja_vistos
            where persona_id = '00000000-0000-0000-0000-0000000c1011'
              and tipo_item in ('conducta_registrada', 'caso_traspasado')), 2,
  'LA TABLA · los dos quedan guardados: la restricción también los acepta');
select lives_ok($$ select fn_bandeja_marcar_visto('conducta_registrada', '00000000-0000-0000-0000-0000000c10d1') $$,
  'VER DOS VECES · volver a abrir el mismo caso no falla: actualiza la hora');
select is((select count(*)::int from bandeja_vistos
            where persona_id = '00000000-0000-0000-0000-0000000c1011' and tipo_item = 'conducta_registrada'), 1,
  'VER DOS VECES · y sigue siendo una sola fila');

select throws_like($$ select fn_bandeja_marcar_visto('conducta_inventada', '00000000-0000-0000-0000-0000000c10d3') $$,
  '%no reconocido%', 'LA FUNCIÓN · un tipo que nadie declaró sigue sin pasar');
select throws_ok($$ insert into bandeja_vistos (persona_id, tipo_item, item_id)
                    values ('00000000-0000-0000-0000-0000000c1011', 'conducta_inventada', '00000000-0000-0000-0000-0000000c10d3') $$,
  '23514', null, 'LA TABLA · ni la restricción');

-- Los tipos de antes de la 0515 siguen aceptados: no se rompió ninguno.
select lives_ok($$ select fn_bandeja_marcar_visto('solicitud_educacion', '00000000-0000-0000-0000-0000000c10d4') $$,
  'NO SE ROMPE NADA · los tipos de la 0473 siguen pasando');

select * from finish();
rollback;
