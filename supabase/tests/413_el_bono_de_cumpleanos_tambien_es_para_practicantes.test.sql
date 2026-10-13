-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 413_el_bono_de_cumpleanos_tambien_es_para_practicantes.test.sql — 0518
-- ============================================================================
-- El caso real: Daniel Ruiz, practicante, cumple en octubre, y el 2026-10-13
-- no veía nada en su Info mientras DO lo veía pendiente. Lo que defiende:
--
--   1. LO QUE VE DO Y LO QUE VE ELLA SON LO MISMO. El tablero y
--      `fn_mi_bono_cumpleanos` contestan `este_mes`, con el monto a la vista.
--   2. LO PIDE Y ENTRA A SU BOLETA. La firma crea la constancia y la línea
--      `bono` del periodo abierto; la planilla de la practicante la suma.
--   3. NO SE COBRA DOS VECES. Una segunda firma no pasa.
--   4. EL CARGO EN PAPEL CONTESTA IGUAL. DO puede registrárselo a otra
--      practicante.
--   5. LO QUE NO SE ABRIÓ SIGUE CERRADO. Un locador por RxH sigue sin bono.
-- ============================================================================
begin;
select plan(11);

-- Un periodo que contiene hoy, y ningún otro que se le cruce.
delete from periodo_grupo_pago;
delete from periodos_planilla;
insert into periodos_planilla (id, fecha_ini, fecha_fin)
values ('00000000-0000-0000-0000-000000413900', fn_hoy_lima() - 10, fn_hoy_lima() + 20);

insert into parametros_laborales (clave, valor, vigente_desde, vigente_hasta)
select 'bono_onomastico', 180.00, '2020-01-01', null
 where not exists (select 1 from parametros_laborales where clave = 'bono_onomastico');

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000413000', 'ZZ413', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000413001', 'Prueba', 'Practicante',
   '00000000-0000-0000-0000-000000413000', 'integrante', 'test-hash', 'practicante',
   '00000000-0000-0000-0000-000000413011', '2020-01-01'),
  ('00000000-0000-0000-0000-000000413002', 'Prueba', 'OtraPracticante',
   '00000000-0000-0000-0000-000000413000', 'integrante', 'test-hash', 'practicante',
   '00000000-0000-0000-0000-000000413012', '2020-01-01'),
  ('00000000-0000-0000-0000-000000413003', 'Prueba', 'Locador',
   '00000000-0000-0000-0000-000000413000', 'integrante', 'test-hash', 'rxh',
   '00000000-0000-0000-0000-000000413013', '2020-01-01'),
  ('00000000-0000-0000-0000-000000413004', 'Prueba', 'DO',
   '00000000-0000-0000-0000-000000413000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000413014', '2020-01-01');
set session_replication_role = origin;

insert into datos_personales (persona_id, fecha_nacimiento)
select id, make_date(2003, extract(month from fn_hoy_lima())::int, 10)
  from personas where id::text like '00000000-0000-0000-0000-00000041300%';

insert into firmas_escaneadas (persona_id, imagen, tipo)
select id, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen'
  from personas where id::text like '00000000-0000-0000-0000-00000041300%';

create function pg_temp.como(p_sub text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_sub, true);
end $$;


-- ── 1 · Lo que ve DO y lo que ve ella son lo mismo ────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000413011');
select is((select bono_estado from fn_documentos_tablero(true)), 'este_mes',
  'TABLERO · DO la ve con el bono de este mes');
select is((select estado from fn_mi_bono_cumpleanos()), 'este_mes',
  'INFO · y ella también: el caso de Daniel Ruiz deja de quedar en silencio');
select ok((select monto from fn_mi_bono_cumpleanos()) > 0,
  'INFO · con el monto a la vista ANTES de firmar');


-- ── 2 · Lo pide y entra a su boleta ──────────────────────────────────────
select lives_ok($$ select fn_confirmar_mi_bono_cumpleanos() $$,
  'FIRMA · la practicante firma su constancia');
select is((select estado from fn_mi_bono_cumpleanos()), 'en_boleta',
  'FIRMA · y su bono queda en su boleta, como a quien está en planilla');
select is(
  (select count(*)::int from movimientos_planilla
    where persona_id = '00000000-0000-0000-0000-000000413001'
      and periodo_id = '00000000-0000-0000-0000-000000413900' and tipo = 'bono'),
  1, 'BOLETA · una sola línea «Asignación por cumpleaños» en el periodo abierto');
select is(
  (fn_planilla_calcular_persona('00000000-0000-0000-0000-000000413001',
                                '00000000-0000-0000-0000-000000413900') ->> 'bonos')::numeric,
  (select monto_declarado from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000413001' and tipo = 'bono'),
  'PLANILLA · la planilla de la practicante suma exactamente el monto firmado');


-- ── 3 · No se cobra dos veces ────────────────────────────────────────────
select throws_ok($$ select fn_confirmar_mi_bono_cumpleanos() $$, null, null,
  'DOBLE · una segunda firma no pasa');


-- ── 4 · El cargo en papel contesta igual ─────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000413014');
select lives_ok(
  $$ select fn_documento_registrar('bono', fn_hoy_lima(),
       '00000000-0000-0000-0000-000000413002', null, null,
       extract(year from fn_hoy_lima())::int, false, null, 'documentos/prueba-413.jpg', null) $$,
  'PAPEL · DO registra el cargo de otra practicante');


-- ── 5 · Lo que no se abrió sigue cerrado ─────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000413013');
select is((select estado from fn_mi_bono_cumpleanos()), 'no_aplica',
  'RXH · un locador sigue sin bono: la 0518 abre practicantes, nada más');
select throws_ok($$ select fn_confirmar_mi_bono_cumpleanos() $$, null, null,
  'RXH · y no lo puede firmar');

select * from finish();
rollback;
