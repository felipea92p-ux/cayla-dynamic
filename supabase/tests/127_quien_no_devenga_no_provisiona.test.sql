-- ============================================================================
-- 127_quien_no_devenga_no_provisiona.test.sql
-- ============================================================================
-- Medido en producción el 2026-08-05: Catherine Pereyra, que trabaja por
-- recibos por honorarios, figuraba con S/2.841,70 de beneficios acumulados —
-- el monto más alto de la empresa. No los devenga y nunca los devengó.
--
-- La causa era una incoherencia, no un cálculo:
--   fn_cts_trunca · fn_grati_trunca · fn_vacaciones_truncas → consultan
--       fn_devenga_beneficios desde la 0085
--   fn_provisiones                                          → no consultaba nada
--
-- Y es la peor forma del error: la provisión decía que CAYLA debía ese dinero
-- mientras la liquidación, el día que esa persona cesara, no le habría pagado ni
-- un sol. Se guarda plata para algo que jamás va a salir.
--
-- LAS DOS MITADES QUE ESTE ARCHIVO DEFIENDE, y que se rompen por separado:
--   1. Un locador no provisiona nada — ninguno de los once campos con monto.
--   2. Quien SÍ está en planilla sigue provisionando igual que siempre. Si
--      alguien "arregla" esto filtrando de más, la mitad de arriba pasa y el
--      sistema deja de provisionar para todo el mundo, en silencio.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000db00', 'ZZDEV', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000db01', 'DevAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000db00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000db09', '2025-01-01');
set session_replication_role = origin;

-- Tres personas idénticas en todo salvo en su vínculo. Cualquier diferencia en
-- lo que acumulen viene del vínculo y de nada más.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000db02', 'DevPlanilla', 'Laboratorio',
   '00000000-0000-0000-0000-00000000db00', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000000db03', 'DevLocador',  'Laboratorio',
   '00000000-0000-0000-0000-00000000db00', 'test-hash', '2025-01-01', 'rxh'),
  ('00000000-0000-0000-0000-00000000db04', 'DevSocio',    'Laboratorio',
   '00000000-0000-0000-0000-00000000db00', 'test-hash', '2025-01-01', 'no_trabajador');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'colibri', 1300, '2025-01-01'
from unnest(array['00000000-0000-0000-0000-00000000db02'::uuid,
                  '00000000-0000-0000-0000-00000000db03'::uuid,
                  '00000000-0000-0000-0000-00000000db04'::uuid]) p;

-- Las mismas jornadas para las tres.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 8, 'cerrada'
from unnest(array['00000000-0000-0000-0000-00000000db02'::uuid,
                  '00000000-0000-0000-0000-00000000db03'::uuid,
                  '00000000-0000-0000-0000-00000000db04'::uuid]) p,
     generate_series('2026-01-05'::date, '2026-01-30'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000db09', true);

create temporary table _prov on commit drop as
select (e ->> 'nombre')          as nombre,
       (e -> 'cts_may')::numeric as cts_may,
       (e -> 'cts_nov')::numeric as cts_nov,
       (e -> 'grati_s2')::numeric as grati_s2,
       (e -> 'be_s2')::numeric    as be_s2,
       (e -> 'vac')::numeric      as vac,
       (e -> 'gran_total')::numeric as gran_total
from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e;

-- ── 1 · Quien está en planilla sigue igual que siempre ──────────────────────
select cmp_ok((select gran_total from _prov where nombre like 'DevPlanilla%'), '>', 0::numeric,
  'PLANILLA · sigue provisionando: el filtro no apagó el cálculo');

-- ── 2 · El locador no provisiona NADA. Los cinco campos, uno por uno ────────
-- Se comprueban por separado a propósito: el gran total podría dar cero con
-- alguno de los campos distinto de cero y compensándose.
--
-- POR QUÉ EL `coalesce` (0274). Desde la 0274 el locador ya no sale en la lista
-- —ver la sección 4—, así que la subconsulta no devuelve cero: no devuelve
-- fila. «No está» y «está en cero» son las dos formas de no provisionar, y las
-- dos valen. Lo que estas seis líneas siguen cazando es la única forma de
-- fallar: que vuelva a salir CON monto, que es exactamente lo que se vio en
-- producción el 2026-08-05 y por lo que existe este archivo.
select is(coalesce((select cts_may    from _prov where nombre like 'DevLocador%'), 0), 0::numeric,
  'LOCADOR · no provisiona CTS de mayo');
select is(coalesce((select cts_nov    from _prov where nombre like 'DevLocador%'), 0), 0::numeric,
  'LOCADOR · ni CTS de noviembre');
select is(coalesce((select grati_s2   from _prov where nombre like 'DevLocador%'), 0), 0::numeric,
  'LOCADOR · ni gratificación');
select is(coalesce((select be_s2      from _prov where nombre like 'DevLocador%'), 0), 0::numeric,
  'LOCADOR · ni la bonificación del 9%');
select is(coalesce((select vac        from _prov where nombre like 'DevLocador%'), 0), 0::numeric,
  'LOCADOR · ni vacaciones');
select is(coalesce((select gran_total from _prov where nombre like 'DevLocador%'), 0), 0::numeric,
  'LOCADOR · y su gran total es cero');

-- ── 3 · Un no trabajador, igual ─────────────────────────────────────────────
select is(coalesce((select gran_total from _prov where nombre like 'DevSocio%'), 0), 0::numeric,
  'NO TRABAJADOR · tampoco provisiona nada');

-- ── 4 · Y NO aparece en la lista ────────────────────────────────────────────
-- CAMBIO 0274, Y ES LA VUELTA ATRÁS DE UNA DECISIÓN QUE ESTUVO ESCRITA AQUÍ.
--
-- Hasta hoy esta misma línea exigía lo contrario —que el locador saliera, en
-- cero— con este argumento: «verlo en cero es una respuesta, que falte obliga a
-- preguntarse si se perdió por error». Se queda escrito porque era un buen
-- argumento; lo que lo tumbó fue la pantalla real, el 2026-08-19: con la mitad
-- de las filas en cero, el cero dejó de ser una respuesta y pasó a ser ruido —
-- y el cero de quien SÍ devenga y aún no acumuló (alguien que entró esta
-- semana) quedaba indistinguible del de quien no devengará nunca.
--
-- La preocupación de entonces sigue siendo válida y se contesta en otro sitio:
-- una fila solo desaparece cuando `fn_devenga_algo` dice que no devenga nada, o
-- sea cuando sus cinco columnas ya valen cero. Nunca se cae una fila con plata
-- dentro. Eso lo defiende la prueba 211.
select is((select count(*)::int from _prov where nombre like 'DevLocador%'), 0,
  'FUERA · el locador ya no ocupa una fila para decir cero');

select * from finish();
rollback;
