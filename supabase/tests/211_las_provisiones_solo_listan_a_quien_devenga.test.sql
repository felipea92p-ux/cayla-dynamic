-- ============================================================================
-- 211_las_provisiones_solo_listan_a_quien_devenga.test.sql
-- ============================================================================
-- Migración 0274. La pantalla de Provisiones lista SOLO a quien tiene algo que
-- reservar: quien no devenga ninguno de los tres beneficios deja de aparecer.
--
-- LO QUE DE VERDAD HAY QUE DEFENDER NO ES QUE DESAPAREZCAN. Es que no
-- desaparezca nadie más. Un filtro en la pantalla de reservas es la clase de
-- cambio que se rompe hacia el lado silencioso: si se pasa de listo, alguien
-- deja de aparecer y CAYLA deja de reservar su plata — y no hay ninguna señal,
-- porque una fila que falta no se ve. El día que haya que pagarle, el dinero no
-- está. Por eso las cuatro mitades de abajo, y en este orden:
--
--   1. quien devenga SIGUE saliendo, con sus montos intactos;
--   2. quien devenga y hoy suma cero —entró esta semana— TAMBIÉN sale: ese
--      cero significa «aún no», no «nunca», y es el que hay que poder leer;
--   3. quien no devenga nada sale de la lista, y lo que se fue valía cero en
--      las cinco columnas (o sea: la suma de la tabla no se movió);
--   4. el filtro pregunta por el DEVENGO, no por el tipo de vínculo. Una
--      locadora con un beneficio encendido a mano —el caso que la 0196 existe
--      para poder expresar— sigue apareciendo, con su plata. Esta es la
--      aserción que impide "simplificar" el filtro a `tipo_vinculo='planilla'`.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ba00', 'ZZ274', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ba01', 'DosAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ba00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ba09', '2025-01-01');
set session_replication_role = origin;

-- Seis personas idénticas salvo en su vínculo (y una en su fecha de ingreso).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000ba02', 'DosPlanilla',  'Laboratorio',
   '00000000-0000-0000-0000-00000000ba00', 'test-hash', '2025-01-01', 'planilla'),
  -- Entró anteayer: devenga, pero todavía no acumuló nada.
  ('00000000-0000-0000-0000-00000000ba03', 'DosRecien',    'Laboratorio',
   '00000000-0000-0000-0000-00000000ba00', 'test-hash', '2026-08-17', 'planilla'),
  ('00000000-0000-0000-0000-00000000ba04', 'DosLocadora',  'Laboratorio',
   '00000000-0000-0000-0000-00000000ba00', 'test-hash', '2025-01-01', 'rxh'),
  ('00000000-0000-0000-0000-00000000ba05', 'DosPrueba',    'Laboratorio',
   '00000000-0000-0000-0000-00000000ba00', 'test-hash', '2025-01-01', 'prueba'),
  ('00000000-0000-0000-0000-00000000ba06', 'DosSocia',     'Laboratorio',
   '00000000-0000-0000-0000-00000000ba00', 'test-hash', '2025-01-01', 'no_trabajador'),
  -- La excepción de la 0196: cobra por honorarios, pero se le reconoce la
  -- gratificación por decisión expresa. Tiene plata que reservar.
  ('00000000-0000-0000-0000-00000000ba07', 'DosExcepcion', 'Laboratorio',
   '00000000-0000-0000-0000-00000000ba00', 'test-hash', '2025-01-01', 'rxh');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'colibri', 1300, '2025-01-01'
from unnest(array['00000000-0000-0000-0000-00000000ba02'::uuid,
                  '00000000-0000-0000-0000-00000000ba03'::uuid,
                  '00000000-0000-0000-0000-00000000ba04'::uuid,
                  '00000000-0000-0000-0000-00000000ba05'::uuid,
                  '00000000-0000-0000-0000-00000000ba06'::uuid,
                  '00000000-0000-0000-0000-00000000ba07'::uuid]) p;

-- Las mismas jornadas para todas menos la recién ingresada, que no tiene
-- ninguna: su cero tiene que venir de no haber devengado todavía.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 8, 'cerrada'
from unnest(array['00000000-0000-0000-0000-00000000ba02'::uuid,
                  '00000000-0000-0000-0000-00000000ba04'::uuid,
                  '00000000-0000-0000-0000-00000000ba05'::uuid,
                  '00000000-0000-0000-0000-00000000ba06'::uuid,
                  '00000000-0000-0000-0000-00000000ba07'::uuid]) p,
     generate_series('2026-01-05'::date, '2026-06-30'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ba09', true);

select fn_set_devenga_beneficio('00000000-0000-0000-0000-00000000ba07', 'grati', true);

create temporary table _lista on commit drop as
select (e ->> 'persona_id')::uuid    as persona_id,
       (e ->> 'nombre')              as nombre,
       (e -> 'gran_total')::numeric  as gran_total
from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e;

-- ── 1 · Quien devenga sigue saliendo, con su plata ──────────────────────────
select cmp_ok((select gran_total from _lista where nombre like 'DosPlanilla%'), '>', 0::numeric,
  'SE QUEDA · quien está en planilla sigue en la lista y sigue reservando');

-- ── 2 · Y quien devenga pero aún no acumuló, también ────────────────────────
-- La mitad que más fácil se rompe "de más": es una fila en cero, igual de
-- vacía a la vista que la de una locadora, y significa lo contrario.
select is((select count(*)::int from _lista where nombre like 'DosRecien%'), 1,
  'SE QUEDA · la que entró esta semana sale, aunque hoy sume cero');
select is((select gran_total from _lista where nombre like 'DosRecien%'), 0::numeric,
  'SE QUEDA · y su cero es un cero de verdad: aún no devengó nada');

-- ── 3 · Quien no devenga nada, fuera ────────────────────────────────────────
select is((select count(*)::int from _lista where nombre like 'DosLocadora%'), 0,
  'FUERA · la locadora no ocupa una fila para decir cero');
select is((select count(*)::int from _lista where nombre like 'DosPrueba%'), 0,
  'FUERA · quien está en días de prueba tampoco');
select is((select count(*)::int from _lista where nombre like 'DosSocia%'), 0,
  'FUERA · ni quien no es trabajadora');

-- ── 4 · Y nadie con algo que reservar se quedó fuera ────────────────────────
-- Dicho de la forma que no depende de acordarse de quién es quién, y que por
-- eso sigue valiendo el día que este archivo tenga otra gente dentro: de todas
-- las personas activas, las que devengan algo tienen que estar TODAS. Cero
-- ausentes. Es la mitad silenciosa —la fila que falta no se ve— y es la que
-- convierte un filtro de pantalla en plata que no se guardó.
select is(
  (select count(*)::int
     from personas p
    where p.estado = 'activo'
      and fn_devenga_algo(p.id)
      and not exists (select 1 from _lista l where l.persona_id = p.id)),
  0,
  'SIN PÉRDIDA · ni una sola persona que devengue algo se quedó fuera de la lista');

-- ── 5 · El filtro pregunta por el devengo, no por el tipo de vínculo ────────
-- Si alguien "simplifica" el filtro a `tipo_vinculo = 'planilla'`, estas dos
-- líneas son las que se ponen rojas — y son las que evitan que CAYLA deje de
-- reservar la gratificación que sí le reconoció a esta persona.
select is((select count(*)::int from _lista where nombre like 'DosExcepcion%'), 1,
  'EXCEPCIÓN · la locadora con la gratificación encendida a mano SIGUE en la lista');
select cmp_ok((select gran_total from _lista where nombre like 'DosExcepcion%'), '>', 0::numeric,
  'EXCEPCIÓN · y con su monto, que es plata que hay que tener guardada');

select * from finish();
rollback;
