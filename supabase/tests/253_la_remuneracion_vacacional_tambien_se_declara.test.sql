-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 253_la_remuneracion_vacacional_tambien_se_declara.test.sql
-- ============================================================================
-- Fija la 0317, y con ella cierra una familia de tres.
--
-- La planilla paga tres cosas sin que haya marcaje: el descanso médico, la
-- licencia con goce (y el duelo directo), y las vacaciones. Las tres son
-- remuneración. Las tres tenían que entrar a `bri.base` —la remuneración afecta
-- a EsSalud y a pensión— y las tres se cayeron por el mismo sitio, una detrás de
-- otra: el monto iba a `pago_base` y no a `pb.basica`.
--
--     0263  lo arregló para el descanso médico
--     0316  para la licencia con goce y el duelo directo
--     0317  para las vacaciones          ← esta prueba
--
-- ── LA COMPROBACIÓN QUE MÁS DICE, Y POR QUÉ ────────────────────────────────
--
-- No es que la base suba. Es que **dos personas que faltan los mismos días y
-- cobran lo mismo declaren lo mismo**, sin importar cómo se llame su ausencia.
-- Antes de la 0317, con el mismo pago de S/483,87:
--
--     descanso médico   →  su base subía  519,89
--     licencia con goce →  su base subía  483,87
--     VACACIONES        →  su base subía   36,02
--
-- Por eso el montaje pone a las tres a faltar exactamente los mismos cinco días
-- y no compara importes escritos a mano: compara a unas con otras. Así la
-- prueba sobrevive a cualquier migración que cambie legítimamente cuánto se
-- paga, y solo se pone roja cuando la familia se vuelve a separar.
--
-- ── LO QUE MÁS CARO COSTARÍA ROMPER ────────────────────────────────────────
--
-- Que le nazca una base a quien la tiene en cero a propósito. `sueldo_fijo` no
-- declara básica, y la regla del CLAUDE.md desde la 0193 es que estos términos
-- COMPLETAN una base declarada, nunca CREAN una donde no la hay.
--
-- (A un RxH no se le puede probar aquí: la 0186 impide registrarle vacaciones,
-- y con razón — dárselas a quien cobra por recibo por honorarios es un indicio
-- de subordinación ante SUNAFIL. El caso es imposible por construcción.)
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000f01', 'ZZVD', 'Lab vacacional', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000f02', 'VdAdmin', 'Vac',
        '00000000-0000-0000-0000-000000000f01', 'admin', 'x',
        '00000000-0000-0000-0000-000000000fff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo) values
  ('00000000-0000-0000-0000-000000000f03', 'VdControl',    'Vac', '00000000-0000-0000-0000-000000000f01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-000000000f04', 'VdVacaciones', 'Vac', '00000000-0000-0000-0000-000000000f01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-000000000f05', 'VdDescMedico', 'Vac', '00000000-0000-0000-0000-000000000f01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-000000000f06', 'VdMaternidad', 'Vac', '00000000-0000-0000-0000-000000000f01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-000000000f07', 'VdMesEntero',  'Vac', '00000000-0000-0000-0000-000000000f01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  -- El que NO debe moverse, y su espejo sin ausencia para medir contra él.
  ('00000000-0000-0000-0000-000000000f08', 'VdFijoVac',    'Vac', '00000000-0000-0000-0000-000000000f01', 'x', '2024-01-01', 'taller_produccion', 'planilla', true),
  ('00000000-0000-0000-0000-000000000f09', 'VdFijoControl','Vac', '00000000-0000-0000-0000-000000000f01', 'x', '2024-01-01', 'taller_produccion', 'planilla', true);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 3000, '2024-01-01' from personas where apellidos = 'Vac' and rol is distinct from 'admin';

-- ⚠️ ESTO ESPEJA PRODUCCION, y no es un detalle. `sueldo_base_legal` tiene
-- DEFAULT 1130 (la RMV), pero en CAYLA se declara el sueldo INTEGRO: medido el
-- 2026-08-08, 22 de 22 personas con `sueldo_base_legal = salario`, o sea
-- complemento variable CERO.
--
-- Un fixture que se quede con el default mide otra empresa. Al escribir esta
-- prueba se midió primero con el default y las cifras salieron distintas —la
-- base caía al piso RMV donde en producción no cae— y una de las aserciones
-- decía lo contrario de lo que dice ahora. Se corrigió antes de entregarla.
update personas set sueldo_base_legal = 3000
 where apellidos = 'Vac' and rol is distinct from 'admin';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39
from personas where apellidos = 'Vac' and rol is distinct from 'admin';

-- ONP al 13 %: donde se ve que el aporte llega al fondo de la persona.
insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde)
select id, 'onp', '2024-01-01' from personas where apellidos = 'Vac' and rol is distinct from 'admin';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-000000000f01', '2026-07-29', '2026-08-28', 'abierto');

-- Los mismos cinco días para las tres. Solo cambia el TIPO.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at) values
  ('00000000-0000-0000-0000-000000000f04', 'vacaciones',      '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000f02', '00000000-0000-0000-0000-000000000f02', now()),
  ('00000000-0000-0000-0000-000000000f05', 'descanso_medico', '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000f02', '00000000-0000-0000-0000-000000000f02', now()),
  ('00000000-0000-0000-0000-000000000f08', 'vacaciones',      '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000f02', '00000000-0000-0000-0000-000000000f02', now()),
  ('00000000-0000-0000-0000-000000000f07', 'vacaciones',      '2026-07-29', '2026-08-28', 'lab', '00000000-0000-0000-0000-000000000f02', '00000000-0000-0000-0000-000000000f02', now());
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at, subsidio_diario) values
  ('00000000-0000-0000-0000-000000000f06', 'maternidad', '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000f02', '00000000-0000-0000-0000-000000000f02', now(), 200.00);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000fff', true);

-- Cada una marca todos sus días laborables MENOS los de su ausencia.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-000000000f01', m.tipo,
       (d.d::date::text || m.hora)::timestamptz
from personas p,
     generate_series('2026-07-29'::date, '2026-08-28'::date, '1 day') d,
     (values ('entrada'::tipo_marca, 'T09:00:00-05:00'),
             ('salida_final'::tipo_marca, 'T15:30:00-05:00')) m(tipo, hora)
where p.apellidos = 'Vac' and p.rol is distinct from 'admin'
  and extract(dow from d.d)::int between 1 and 6
  and not exists (select 1 from ausencias a
                   where a.persona_id = p.id
                     and d.d::date between a.fecha_inicio and a.fecha_fin);

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;
create or replace function pg_temp.num(p_nombre text, p_clave text) returns numeric
language sql as $f$
  select round(coalesce((pg_temp.fila(p_nombre) ->> p_clave)::numeric, 0), 2);
$f$;

-- ── 1 · La comprobación que más dice ───────────────────────────────────────

select is(pg_temp.num('VdVacaciones Vac','base_essalud'),
          pg_temp.num('VdDescMedico Vac','base_essalud'),
  'quien está de vacaciones y quien está de descanso médico los MISMOS días declaran lo MISMO');

select is(pg_temp.num('VdVacaciones Vac','pago_base'),
          pg_temp.num('VdDescMedico Vac','pago_base'),
  'montaje: y cobran lo mismo, que es lo que hace comparable lo de arriba');

-- ── 2 · Que entra, y por el monto exacto ───────────────────────────────────

select cmp_ok(pg_temp.num('VdVacaciones Vac','base_essalud'), '>',
              pg_temp.num('VdControl Vac','base_essalud') - pg_temp.num('VdVacaciones Vac','monto_vacaciones'),
  'la remuneración vacacional ya entra a la base: se paga Y se declara');

select cmp_ok(pg_temp.num('VdVacaciones Vac','monto_vacaciones'), '>', 0::numeric,
  'montaje: y de verdad se le pagan vacaciones (si no, lo demás no mide nada)');

-- ── 3 · El caso extremo: el periodo ENTERO de vacaciones ───────────────────
-- Antes de la 0317 su básica legal era S/0.00 y se le declaraba el piso RMV
-- de S/1 130 habiendo cobrado S/3 000.

select cmp_ok(pg_temp.num('VdMesEntero Vac','base_essalud'), '>', 1130::numeric,
  'quien pasa el periodo ENTERO de vacaciones ya no cae al piso RMV');

select cmp_ok(pg_temp.num('VdMesEntero Vac','descuento_afp'), '>', 300::numeric,
  'y su aporte de pensión llega a su fondo — antes eran S/29 de S/3 000 cobrados');

-- ── 4 · LO QUE NO DEBE MOVERSE ─────────────────────────────────────────────

-- A quien tiene sueldo fijo la 0317 NO le suma nada: la guarda
-- `sueldo_fijo is not true` lo excluye, igual que excluye a los otros tres
-- términos. Si el término se le colara, su base sería la de su espejo — y no lo
-- es. Eso es lo que comprueba este `<`.
--
-- ⚠️ Y OJO CON LEER ESTA DESIGUALDAD COMO UN ÉXITO: es un DEFECTO SEPARADO y
-- preexistente. Medido el 2026-08-26: quien tiene sueldo fijo cobra S/3.000
-- pase lo que pase, pero su base declarada se prorratea por HORAS MARCADAS, así
-- que faltar se la baja aunque cobre igual — y da lo mismo que la falta esté
-- justificada como vacaciones o no lo esté (las dos dan 2.129,03 contra los
-- 2.612,90 de quien trabajó el mes entero). Encima declara de menos incluso
-- trabajando todo el mes: cobra 3.000 y declara 2.612,90.
--
-- No lo arregla esta migración porque es otro defecto con otra lógica —la base
-- de un sueldo fijo debería salir de su sueldo, no de un prorrateo por horas— y
-- afecta a más casos que las vacaciones. Queda en docs/hallazgos-abiertos.md.
select cmp_ok(pg_temp.num('VdFijoVac Vac','base_essalud'), '<',
              pg_temp.num('VdFijoControl Vac','base_essalud'),
  'a quien tiene sueldo fijo la 0317 NO le suma nada: la guarda lo excluye');

-- Y LA QUE MÁS DICE DE TODAS: quien estuvo de vacaciones y quien trabajó el mes
-- entero declaran EXACTAMENTE LO MISMO. Es el enunciado del arreglo — se devenga
-- igual trabajando que gozando el descanso (RIT 30.8: gozarlo no puede reducir
-- ingresos). Antes de la 0317 la de vacaciones declaraba S/483,87 menos.
select is(pg_temp.num('VdVacaciones Vac','base_essalud'),
          pg_temp.num('VdControl Vac','base_essalud'),
  'quien estuvo de vacaciones declara lo MISMO que quien trabajó el mes entero');

select cmp_ok(pg_temp.num('VdMaternidad Vac','base_essalud'), '<=',
              pg_temp.num('VdControl Vac','base_essalud'),
  'la maternidad sigue fuera: es subsidio de EsSalud, no remuneración (0262)');

-- Con la configuración real (base legal = salario) el descanso médico y quien
-- trabajó declaran LO MISMO, que es justo lo que la 0263 vino a conseguir. Se
-- comprueba con `>=` y no con `=` para que siga valiendo el día que alguien
-- vuelva a poner complemento variable, donde el descanso médico declara MÁS.
select cmp_ok(pg_temp.num('VdDescMedico Vac','base_essalud'), '>=',
              pg_temp.num('VdControl Vac','base_essalud'),
  'el descanso médico no pierde base frente a quien trabajó: la 0263 sigue en pie');

-- ── 5 · La familia completa, que es lo que esta migración cierra ───────────

select ok(
  (select prosrc like '%pb.monto_descanso_medico, 0), 2)%'
      and prosrc like '%pb.monto_licencia_con_goce, 0), 2)%'
      and prosrc like '%pb.monto_vacaciones, 0), 2)%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'),
  'los TRES conceptos que se pagan sin marcaje entran a la base: 0263, 0316 y 0317');

-- Y los tres con la MISMA guarda. Si una se separa, a alguien le nace una base
-- que no debía o se le quita una que sí.
select is(
  (select (length(prosrc) - length(replace(prosrc,
            'case when pe.en_planilla is true and pe.sueldo_fijo is not true', '')))
          / length('case when pe.en_planilla is true and pe.sueldo_fijo is not true')
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'),
  4,
  'y los cuatro términos (maternidad incluida) llevan la MISMA guarda, palabra por palabra');

select * from finish();
rollback;
