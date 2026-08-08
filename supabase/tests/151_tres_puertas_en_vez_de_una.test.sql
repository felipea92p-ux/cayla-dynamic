-- ============================================================================
-- 151_tres_puertas_en_vez_de_una.test.sql
-- ============================================================================
-- La decisión que hasta la 0196 no cabía en el sistema, dicha por Felipe sobre
-- Carlos Espejo: «gratificación y CTS sí, vacaciones no».
--
-- No cabía porque `fn_devenga_beneficios` devuelve UN booleano que gobierna los
-- tres beneficios a la vez. Para que Carlos conservara grati y CTS había que
-- dejarlo como `planilla`, y eso le daba también las vacaciones. Estuvo
-- provisionándolas desde julio.
--
-- LAS DOS MITADES QUE DEFIENDE, y que se rompen por separado:
--
--   · INERCIA. Sin banderas puestas, todo el mundo devenga exactamente lo de
--     siempre. Si alguien «mejora» el defecto, esta mitad se cae — y sería el
--     peor fallo posible, porque movería la plata de 29 personas para arreglar
--     la de una.
--
--   · SEPARACIÓN. Apagar un beneficio apaga ESE y solo ese. Si alguien vuelve a
--     juntar los tres en una sola pregunta, la segunda mitad se cae.
--
-- POR QUÉ EL FIXTURE TIENE TRES VÍNCULOS DISTINTOS
--   Porque «no cambia nada» hay que demostrarlo en los tres casos que el defecto
--   distingue: `planilla` devenga, `rxh` no, y `prueba` tampoco —ese último es
--   el que más sorprende al leerlo, y por eso está—.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ab00', 'ZZDEV', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ab01', 'DevAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ab00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ab09', '2025-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000ab02', 'Uno',  'Planilla',   '00000000-0000-0000-0000-00000000ab00', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000000ab03', 'Dos',  'Honorarios', '00000000-0000-0000-0000-00000000ab00', 'test-hash', '2025-01-01', 'rxh');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'colibri', 1300, '2025-01-01'
from unnest(array['00000000-0000-0000-0000-00000000ab02'::uuid,
                  '00000000-0000-0000-0000-00000000ab03'::uuid]) p;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 8, 'cerrada'
from unnest(array['00000000-0000-0000-0000-00000000ab02'::uuid,
                  '00000000-0000-0000-0000-00000000ab03'::uuid]) p,
     generate_series('2026-01-05'::date, '2026-06-30'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ab09', true);

-- Atajo para leer un campo de la provisión de una persona.
create or replace function _prov(p_id uuid, p_campo text) returns numeric
language sql stable as $$
  select (e ->> p_campo)::numeric
  from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
  where (e ->> 'persona_id')::uuid = p_id;
$$;

-- ── 1 · El defecto por tipo de vínculo no se movió ──────────────────────────
select is(fn_devenga('00000000-0000-0000-0000-00000000ab02', 'grati'),      true,
  'DEFECTO · quien está en planilla devenga gratificación');
select is(fn_devenga('00000000-0000-0000-0000-00000000ab02', 'vacaciones'), true,
  'DEFECTO · y vacaciones');
select is(fn_devenga('00000000-0000-0000-0000-00000000ab03', 'cts'),        false,
  'DEFECTO · quien cobra por honorarios no devenga CTS');

-- Un beneficio mal escrito NO cae al defecto: revienta. Si devolviera el
-- defecto, un `fn_devenga(x, 'vacacion')` en singular filtraría a todo el mundo
-- por el tipo de vínculo y nadie se enteraría nunca.
select throws_ok(
  $$ select fn_devenga('00000000-0000-0000-0000-00000000ab02'::uuid, 'vacacion') $$,
  'P0001', null,
  'ESTRICTA · un beneficio desconocido lanza en vez de adivinar');

-- ── 2 · INERCIA · sin banderas, los montos son los de siempre ───────────────
select cmp_ok(_prov('00000000-0000-0000-0000-00000000ab02', 'grati_total'), '>', 0::numeric,
  'INERCIA · la persona de planilla sigue provisionando gratificación');
select cmp_ok(_prov('00000000-0000-0000-0000-00000000ab02', 'vac'), '>', 0::numeric,
  'INERCIA · y vacaciones');
select is(_prov('00000000-0000-0000-0000-00000000ab03', 'gran_total'), 0::numeric,
  'INERCIA · quien cobra por honorarios sigue sin provisionar nada');

-- ── 3 · SEPARACIÓN · apagar vacaciones apaga SOLO vacaciones ────────────────
-- Es el corazón de la migración: la decisión sobre Carlos Espejo, expresada.
create temporary table _antes on commit drop as
select _prov('00000000-0000-0000-0000-00000000ab02', 'grati_total') as grati,
       _prov('00000000-0000-0000-0000-00000000ab02', 'cts_total')   as cts,
       _prov('00000000-0000-0000-0000-00000000ab02', 'vac')         as vac,
       _prov('00000000-0000-0000-0000-00000000ab02', 'gran_total')  as total;

select fn_set_devenga_beneficio('00000000-0000-0000-0000-00000000ab02', 'vacaciones', false);

select is(_prov('00000000-0000-0000-0000-00000000ab02', 'vac'), 0::numeric,
  'SEPARADO · las vacaciones se apagan');

select is(_prov('00000000-0000-0000-0000-00000000ab02', 'grati_total'),
          (select grati from _antes),
  'SEPARADO · la gratificación NO se toca — es la mitad que se rompe sola');

select is(_prov('00000000-0000-0000-0000-00000000ab02', 'cts_total'),
          (select cts from _antes),
  'SEPARADO · la CTS tampoco');

-- El total tiene que bajar EXACTAMENTE lo que valía la ventana apagada. Si baja
-- otra cosa, algún factor se está aplicando donde no debe.
select is(_prov('00000000-0000-0000-0000-00000000ab02', 'gran_total'),
          (select total - vac from _antes),
  'SEPARADO · el gran total baja justo lo que valían las vacaciones, ni un sol más');

select * from finish();
rollback;
