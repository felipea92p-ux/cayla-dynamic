-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 200_los_veinte_dias_de_descanso_medico_se_declaran.test.sql
-- ============================================================================
-- La 0254 conectó el descanso médico al pago metiéndolo en `pago_base`, pero
-- `bri.base` —la base imponible— se construye desde `pb.basica`, no desde
-- `pago_base`. Esos días se pagaban y NO se declaraban: fuera de la base de
-- EsSalud y fuera de la de pensión. Nadie cobraba de menos; se aportaba de menos.
--
-- La 0263 lo corrige, y esto lo fija. Lo que más fácil se rompe:
--
--   · que el descanso médico SÍ entre a las dos bases — porque los primeros 20
--     días son REMUNERACIÓN de CAYLA, no subsidio (el subsidio nace el día 21);
--   · que NO entre para quien cobra monto fijo, cuyo pago no depende de días;
--   · y que el subsidio por MATERNIDAD siga sin entrar a EsSalud, que es lo
--     contrario y vive en la función de al lado. Se parecen en la pantalla y son
--     opuestos en la ley: esta prueba existe para que nadie los unifique.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000007c1', 'ZZDB', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000007c2', 'DbAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000007c1', 'admin', 'x',
        '00000000-0000-0000-0000-0000000007cf', '2024-01-01');
set session_replication_role = origin;

-- `sueldo_base_legal` alto a propósito: con el DEFAULT de 1130 la básica queda
-- topada y el piso RMV de EsSalud tapa la diferencia, que es justo lo que hizo
-- invisible este defecto durante dos semanas.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, regimen_pension, sueldo_base_legal, sueldo_fijo) values
  ('00000000-0000-0000-0000-0000000007c3', 'DbEnferma', 'Lab', '00000000-0000-0000-0000-0000000007c1', 'x', '2024-01-01', 'taller_produccion', 'planilla', 'integra', 3000, false),
  ('00000000-0000-0000-0000-0000000007c4', 'DbControl', 'Lab', '00000000-0000-0000-0000-0000000007c1', 'x', '2024-01-01', 'taller_produccion', 'planilla', 'integra', 3000, false),
  ('00000000-0000-0000-0000-0000000007c5', 'DbFijo',    'Lab', '00000000-0000-0000-0000-0000000007c1', 'x', '2024-01-01', 'taller_produccion', 'planilla', 'integra', 3000, true),
  -- La de maternidad: el contraste que impide que alguien unifique las dos reglas.
  ('00000000-0000-0000-0000-0000000007c6', 'DbMadre',   'Lab', '00000000-0000-0000-0000-0000000007c1', 'x', '2024-01-01', 'taller_produccion', 'planilla', 'integra', 3000, false);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 3000, '2024-01-01' from personas where apellidos = 'Lab' and nombres like 'Db%';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39,
       '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
         "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
         "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb
from personas where apellidos = 'Lab' and nombres like 'Db%';

-- Descanso médico de diez días para la enferma y para la de monto fijo. Y una
-- licencia por maternidad con su subsidio, para el contraste de la prueba 6.
-- Aprobadas por DO (0306): desde esa migración una ausencia sin aprobar no
-- paga nada, y esta prueba fija el caso YA aprobado — el caso sin aprobar
-- vive en la 240.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, subsidio_diario, aprobada_por, aprobada_at) values
  ('00000000-0000-0000-0000-0000000007c3', 'descanso_medico', '2026-08-17', '2026-08-26', 'lab', '00000000-0000-0000-0000-0000000007c2', null, '00000000-0000-0000-0000-0000000007c2', now()),
  ('00000000-0000-0000-0000-0000000007c5', 'descanso_medico', '2026-08-17', '2026-08-26', 'lab', '00000000-0000-0000-0000-0000000007c2', null, '00000000-0000-0000-0000-0000000007c2', now()),
  ('00000000-0000-0000-0000-0000000007c6', 'maternidad',      '2026-08-17', '2026-08-26', 'lab', '00000000-0000-0000-0000-0000000007c2', 200.00, '00000000-0000-0000-0000-0000000007c2', now());

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-0000000007e1', '2026-07-29', '2026-08-28', 'abierto');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000007cf', true);

-- Las cuatro marcan EXACTAMENTE los mismos tres días, antes del descanso. Así la
-- única diferencia entre la enferma y la de control es tener el descanso médico.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-0000000007c1', m.tipo, m.ts
from personas p,
     (values ('entrada'::tipo_marca,      timestamptz '2026-08-12T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-12T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-13T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-13T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-14T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-14T15:30:00-05:00')) m(tipo, ts)
where p.apellidos = 'Lab' and p.nombres like 'Db%' and p.nombres <> 'DbAdmin';

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;

-- 1 · Se le paga el descanso médico. Es lo que trajo la 0254; si esto falla, el
--     resto de la prueba no significa nada.
select cmp_ok(
  (pg_temp.fila('DbEnferma Lab')->>'monto_descanso_medico')::numeric, '>', 0::numeric,
  'el descanso médico se paga — la 0254 sigue en pie');

-- 2 · Y AHORA SE DECLARA. Las dos marcan lo mismo; la única diferencia es el
--     descanso. Antes de la 0263 estas dos bases eran IDÉNTICAS: se pagaba y no
--     se declaraba.
select cmp_ok(
  (pg_temp.fila('DbEnferma Lab')->>'base_essalud')::numeric, '>',
  (pg_temp.fila('DbControl Lab')->>'base_essalud')::numeric,
  'los 20 días entran a la base de EsSalud: son remuneración, no subsidio');

-- 3 · Y a la de pensión, que es la que se le retiene a la persona. Retenerle de
--     menos no la beneficia: esos días no le sumaban para su pensión.
select cmp_ok(
  (pg_temp.fila('DbEnferma Lab')->>'descuento_afp')::numeric, '>',
  (pg_temp.fila('DbControl Lab')->>'descuento_afp')::numeric,
  'los 20 días entran también a la base de pensión');

-- 4 · PERO NO CAMBIA LO QUE COBRA. La 0263 mueve la base, no el pago. Si esto se
--     rompe, alguien metió el descanso médico dos veces en pago_base.
select is(
  (pg_temp.fila('DbEnferma Lab')->>'pago_base')::numeric,
  round( (pg_temp.fila('DbControl Lab')->>'pago_base')::numeric
       + (pg_temp.fila('DbEnferma Lab')->>'monto_descanso_medico')::numeric, 2),
  'el pago no se mueve: la 0263 cambia la base declarada, no lo que se cobra');

-- 5 · Quien cobra monto fijo queda fuera, como en el feriado (0193) y en el
--     sobretiempo (0185). Su pago no depende de días, así que no hay días que
--     declarar por esta vía.
select is(
  (pg_temp.fila('DbFijo Lab')->>'monto_descanso_medico')::numeric, 0.00,
  'a quien cobra monto fijo el descanso médico no le suma ni al pago ni a la base');

-- 6 · EL CONTRASTE QUE IMPIDE UNIFICARLAS. La de maternidad tiene la MISMA
--     ausencia, los mismos días y el mismo horario — y su subsidio NO entra a
--     EsSalud, porque no es remuneración. Si alguien «simplifica» tratando las
--     dos igual, esto se cae.
select cmp_ok(
  (pg_temp.fila('DbMadre Lab')->>'base_essalud')::numeric, '<',
  (pg_temp.fila('DbEnferma Lab')->>'base_essalud')::numeric,
  'el subsidio de maternidad NO entra a EsSalud y el descanso médico SÍ: son opuestos');

-- 7 · Y el cierre sigue pudiendo completarse.
select is(
  (pg_temp.fila('DbEnferma Lab')->>'total')::numeric,
  round( (pg_temp.fila('DbEnferma Lab')->>'pago_base')::numeric
       + (pg_temp.fila('DbEnferma Lab')->>'monto_feriados')::numeric
       + (pg_temp.fila('DbEnferma Lab')->>'monto_plus')::numeric
       + (pg_temp.fila('DbEnferma Lab')->>'asignacion_familiar')::numeric
       + (pg_temp.fila('DbEnferma Lab')->>'monto_movilidad')::numeric
       + (pg_temp.fila('DbEnferma Lab')->>'monto_educacion')::numeric
       - (pg_temp.fila('DbEnferma Lab')->>'descuento_afp')::numeric
       + (pg_temp.fila('DbEnferma Lab')->>'monto_sobretiempo')::numeric
       + (pg_temp.fila('DbEnferma Lab')->>'bonos')::numeric
       - (pg_temp.fila('DbEnferma Lab')->>'descuentos')::numeric
       - (pg_temp.fila('DbEnferma Lab')->>'retencion_4ta')::numeric, 2),
  'la fila cuadra con chk_foto_cuadra: el cierre puede completarse');

select * from finish();
rollback;
