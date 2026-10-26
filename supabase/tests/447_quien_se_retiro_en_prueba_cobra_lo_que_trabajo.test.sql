-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 447_quien_se_retiro_en_prueba_cobra_lo_que_trabajo.test.sql — la 0555
-- ============================================================================
-- El caso real que la motivó (producción, 2026-10-26): dos personas cerradas
-- como «se retiró» con el periodo abierto —una con varios días de prueba y otra
-- con uno— que no entraban a la planilla y por lo tanto no cobraban lo trabajado.
--
-- Qué fija, en orden de importancia:
--   · Las dos APARECEN en la planilla y se les paga EXACTAMENTE lo que marcaron.
--   · Se pagan igual que quien «no fue apto» con las mismas horas: la 0555 no
--     inventa un tercer trato. Se compara contra ese control y no contra un número.
--   · Sin asignación familiar y sin EsSalud: su vínculo sigue siendo «prueba» (0484,
--     0537) y la 0555 no lo cambia. Queda fijado a propósito: es lo que hay que
--     preguntarle al contador, no algo que esta migración decida.
--   · La gente de planilla cobra EXACTAMENTE igual: se fija con el testigo.
--   · Sus marcas siguen intactas y su cierre sigue registrado como «retirado».
--   · La función ya NO lee `pruebas` y conserva las marcas de todo lo anterior.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000447a01', 'ZZ447', 'Sede de laboratorio 447', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-000000447aa0', 'Admin', 'P447', '00000000-0000-0000-0000-000000447a01', 'admin', 'x',
        '00000000-0000-0000-0000-000000447aa1');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000447aa1', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, con_hijos,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000447b01', 'M', 'Retirada4Dias', '00000000-0000-0000-0000-000000447a01', 'x', '2026-10-16', 'prueba',   true, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000447b02', 'N', 'Retirada1Dia',  '00000000-0000-0000-0000-000000447a01', 'x', '2026-10-19', 'prueba',   true, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000447b03', 'C', 'NoAptoControl', '00000000-0000-0000-0000-000000447a01', 'x', '2026-10-16', 'prueba',   true, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000447b04', 'T', 'Testigo',       '00000000-0000-0000-0000-000000447a01', 'x', '2026-01-01', 'planilla', true, 1230, 'activo', 'onp');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1230, '2026-01-01' from personas where id::text like '00000000-0000-0000-0000-000000447b%';

create function pg_temp.dia(p_persona uuid, p_fecha date) returns void language sql as $$
  insert into jornadas (persona_id, fecha, horas_trabajadas, estado, entrada_ts, salida_final_ts)
  values (p_persona, p_fecha, 6.5, 'cerrada', (p_fecha || ' 09:00-05')::timestamptz, (p_fecha || ' 15:30-05')::timestamptz);
$$;

-- Cuatro días la primera, uno la segunda; el control trabaja los mismos cuatro que la primera.
select pg_temp.dia(p, d::date)
  from (values ('00000000-0000-0000-0000-000000447b01'::uuid), ('00000000-0000-0000-0000-000000447b03'::uuid)) v(p),
       generate_series('2026-10-16'::date, '2026-10-19'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000447b02', '2026-10-19');
select pg_temp.dia('00000000-0000-0000-0000-000000447b04', d::date)
  from generate_series('2026-09-29'::date, '2026-10-19'::date, interval '1 day') d;

select fn_prueba_cerrar('00000000-0000-0000-0000-000000447b01', 'retirado', 'Dijo que no volvía');
select fn_prueba_cerrar('00000000-0000-0000-0000-000000447b02', 'retirado', 'Se fue el mismo día');
select fn_prueba_cerrar('00000000-0000-0000-0000-000000447b03', 'no_apto',  'No llegó al nivel');

create temp table _f on commit drop as
select (e->>'persona_id')::uuid as pid, e
  from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-09-29', '2026-10-28') -> 'filas') e
 where (e->>'persona_id') like '00000000-0000-0000-0000-000000447b%';

-- ── 1 · Las dos aparecen y se les paga lo marcado ───────────────────────────
select is((select count(*)::int from _f where pid in ('00000000-0000-0000-0000-000000447b01', '00000000-0000-0000-0000-000000447b02')), 2,
  'APARECEN · las dos personas cerradas como «se retiró» entran a la planilla del periodo abierto');
select is((select (e->>'pago_base')::numeric from _f where pid = '00000000-0000-0000-0000-000000447b01'), 164.00::numeric,
  'PAGO · cuatro días de 6,5 h: S/ 164,00, todo lo que marcó');
select is((select (e->>'pago_base')::numeric from _f where pid = '00000000-0000-0000-0000-000000447b02'), 41.00::numeric,
  'PAGO · un día de 6,5 h: S/ 41,00');

-- ── 2 · Igual que quien «no fue apto», sin inventar un tercer trato ─────────
select is((select e - 'persona_id' - 'nombre' - 'fecha_ingreso' from _f where pid = '00000000-0000-0000-0000-000000447b01'),
          (select e - 'persona_id' - 'nombre' - 'fecha_ingreso' from _f where pid = '00000000-0000-0000-0000-000000447b03'),
  'IGUAL · a quien no fue apto con las mismas horas: ni un campo de su fila cambia');
select is((select (e->>'asignacion_familiar')::numeric from _f where pid = '00000000-0000-0000-0000-000000447b01'), 0::numeric,
  'SIN ASIGNACIÓN · aunque tenga hijos: su vínculo sigue siendo «prueba» (0537)');
select is((select (e->>'aporte_essalud')::numeric from _f where pid = '00000000-0000-0000-0000-000000447b01'), 0::numeric,
  'SIN ESSALUD · la prueba no lo genera (0484): la 0555 no cambia eso, es una pregunta para el contador');

-- ── 3 · Lo que NO puede moverse ─────────────────────────────────────────────
select ok((select (e->>'asignacion_familiar')::numeric from _f where pid = '00000000-0000-0000-0000-000000447b04') > 0,
  'TESTIGO · la gente de planilla con hijos sigue cobrando la asignación');
select is((select (e->>'pago_base')::numeric from _f where pid = '00000000-0000-0000-0000-000000447b04'), 861.00::numeric,
  'TESTIGO · y sus horas se pagan igual: 21 días de 6,5 h');
select is((select count(*)::int from jornadas where persona_id = '00000000-0000-0000-0000-000000447b01'), 4,
  'MARCAS · las cuatro jornadas de la retirada siguen en su sitio: nada se corrige por debajo');
select is((select resultado from pruebas where persona_id = '00000000-0000-0000-0000-000000447b01'), 'retirado',
  'CIERRE · y su cierre sigue registrado como «se retiró»: el hecho se conserva, ya no cambia el pago');

-- ── 4 · La función ───────────────────────────────────────────────────────────
select ok(position('CAMBIO 0555' in (select prosrc from pg_proc where proname = 'fn_planilla_calcular_nucleo')) > 0,
  'VERSIÓN · el núcleo trae la 0555');
select ok(position('pr.resultado' in (select prosrc from pg_proc where proname = 'fn_planilla_calcular_nucleo')) = 0,
  'VERSIÓN · y ya no mira si alguien se retiró');
select ok(
  (select bool_and(position(m in prosrc) > 0)
     from pg_proc, unnest(array['CAMBIO 0416', 'CAMBIO 0463', 'CAMBIO 0484', 'CAMBIO 0491', 'CAMBIO 0504', 'CAMBIO 0524', 'CAMBIO 0537']) m
    where proname = 'fn_planilla_calcular_nucleo'),
  'VERSIÓN · conserva las marcas de la 0416, 0463, 0484, 0491, 0504, 0524 y la asignación de la 0537');
select is((select count(*)::int from pg_proc where proname = 'fn_planilla_calcular_nucleo'), 1,
  'VERSIÓN · una sola función, sin sobrecarga ambigua');

select * from finish();
rollback;
