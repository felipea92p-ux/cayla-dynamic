-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 251_lo_que_se_paga_por_licencia_tambien_se_declara.test.sql
-- ============================================================================
-- Fija la 0316. La 0314 empezó a pagar la licencia con goce y el duelo de
-- familiar directo, pero sumó el monto a `pago_base` y no a `pb.basica`, así
-- que no llegaba a `bri.base`: se pagaba y NO SE DECLARABA a EsSalud ni a
-- pensión.
--
-- Es letra por letra el defecto que la 0263 arregló para el descanso médico, y
-- su comentario ya lo decía: «La 0254 los metió en `pago_base` pero no en
-- `pb.basica`, así que no llegaban aquí».
--
-- ── POR QUÉ NO HAY NI UN IMPORTE ESCRITO A MANO ────────────────────────────
--
-- Por la lección de la 244: una prueba con importes hay que reescribirla cada
-- vez que cambie legítimamente cuánto se paga, y una prueba que se reescribe
-- seguido deja de leerse. Aquí todo son RELACIONES entre dos personas que solo
-- se diferencian en la ausencia registrada.
--
-- El montaje aprovecha eso: `Control` y `Licencia` faltan exactamente los
-- mismos cinco días y marcan exactamente los mismos, pero solo una tiene la
-- ausencia registrada y aprobada. Así la única diferencia posible entre las dos
-- es lo que hace la 0316.
--
-- ── LO QUE MÁS CARO COSTARÍA ROMPER ────────────────────────────────────────
--
-- No es que la base suba: es que NO le nazca una base a quien la tiene en cero
-- a propósito. `sueldo_fijo` y RxH no declaran básica, y la regla de la casa
-- —escrita en el CLAUDE.md desde la 0193— es que las sobretasas COMPLETAN una
-- base declarada, nunca CREAN una donde no la hay. La vez que eso falló, a un
-- RxH le aparecieron S/41.39 de pensión de la nada.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000e01', 'ZZBI', 'Lab base imponible', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000e02', 'BiAdmin', 'Base',
        '00000000-0000-0000-0000-000000000e01', 'admin', 'x',
        '00000000-0000-0000-0000-000000000eff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo) values
  ('00000000-0000-0000-0000-000000000e03', 'BiLicencia',   'Base', '00000000-0000-0000-0000-000000000e01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-000000000e04', 'BiDuelo',      'Base', '00000000-0000-0000-0000-000000000e01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-000000000e05', 'BiDescMedico', 'Base', '00000000-0000-0000-0000-000000000e01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-000000000e06', 'BiMaternidad', 'Base', '00000000-0000-0000-0000-000000000e01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-000000000e07', 'BiControl',    'Base', '00000000-0000-0000-0000-000000000e01', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  -- Los dos que NO deben moverse: su base es cero a propósito.
  ('00000000-0000-0000-0000-000000000e08', 'BiSueldoFijo', 'Base', '00000000-0000-0000-0000-000000000e01', 'x', '2024-01-01', 'taller_produccion', 'planilla', true),
  ('00000000-0000-0000-0000-000000000e09', 'BiRxH',        'Base', '00000000-0000-0000-0000-000000000e01', 'x', '2024-01-01', 'taller_produccion', 'rxh',      false),
  -- El espejo de BiSueldoFijo y BiRxH, sin ausencia, para medir contra él.
  ('00000000-0000-0000-0000-000000000e0a', 'BiFijoControl','Base', '00000000-0000-0000-0000-000000000e01', 'x', '2024-01-01', 'taller_produccion', 'planilla', true),
  ('00000000-0000-0000-0000-000000000e0b', 'BiRxhControl', 'Base', '00000000-0000-0000-0000-000000000e01', 'x', '2024-01-01', 'taller_produccion', 'rxh',      false);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 3000, '2024-01-01' from personas where apellidos = 'Base' and rol is distinct from 'admin';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39
from personas where apellidos = 'Base' and rol is distinct from 'admin';

-- ONP al 13 %: es donde se ve el efecto en el NETO de la persona.
insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde)
select id, 'onp', '2024-01-01' from personas where apellidos = 'Base' and rol is distinct from 'admin';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-000000000e01', '2026-07-29', '2026-08-28', 'abierto');

-- TODAS faltan del lunes 10 al viernes 14 y marcan exactamente los mismos días.
-- Lo único que las distingue es si esa falta está registrada como ausencia.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-000000000e01', m.tipo,
       (d.d::date::text || m.hora)::timestamptz
from personas p,
     generate_series('2026-07-29'::date, '2026-08-28'::date, '1 day') d,
     (values ('entrada'::tipo_marca, 'T09:00:00-05:00'),
             ('salida_final'::tipo_marca, 'T15:30:00-05:00')) m(tipo, hora)
where p.apellidos = 'Base' and p.rol is distinct from 'admin'
  and extract(dow from d.d)::int between 1 and 6
  and d.d::date not between '2026-08-10' and '2026-08-14';

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at) values
  ('00000000-0000-0000-0000-000000000e03', 'licencia_con_goce',      '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000e02', '00000000-0000-0000-0000-000000000e02', now()),
  ('00000000-0000-0000-0000-000000000e04', 'duelo_familiar_directo', '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000e02', '00000000-0000-0000-0000-000000000e02', now()),
  ('00000000-0000-0000-0000-000000000e05', 'descanso_medico',        '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000e02', '00000000-0000-0000-0000-000000000e02', now()),
  ('00000000-0000-0000-0000-000000000e08', 'licencia_con_goce',      '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000e02', '00000000-0000-0000-0000-000000000e02', now()),
  ('00000000-0000-0000-0000-000000000e09', 'licencia_con_goce',      '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000e02', '00000000-0000-0000-0000-000000000e02', now());
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at, subsidio_diario) values
  ('00000000-0000-0000-0000-000000000e06', 'maternidad', '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000e02', '00000000-0000-0000-0000-000000000e02', now(), 200.00);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000eff', true);

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;
create or replace function pg_temp.num(p_nombre text, p_clave text) returns numeric
language sql as $f$
  select round(coalesce((pg_temp.fila(p_nombre) ->> p_clave)::numeric, 0), 2);
$f$;

-- ── 1 · Lo que la 0316 viene a arreglar ────────────────────────────────────

select cmp_ok(pg_temp.num('BiLicencia Base','base_essalud'), '>',
              pg_temp.num('BiControl Base','base_essalud'),
  'la licencia con goce ya entra a la base: se paga Y se declara');

-- Y entra por el monto EXACTO. Si entrara por otro, alguien estaría declarando
-- una cifra distinta de la que cobró.
select is(pg_temp.num('BiLicencia Base','base_essalud')
          - pg_temp.num('BiControl Base','base_essalud'),
          pg_temp.num('BiLicencia Base','monto_licencia_con_goce'),
  'y entra por el monto exacto que se pagó, ni un céntimo más');

select cmp_ok(pg_temp.num('BiDuelo Base','base_essalud'), '>',
              pg_temp.num('BiControl Base','base_essalud'),
  'el duelo de familiar directo también: lo paga CAYLA, es remuneración');

select is(pg_temp.num('BiDuelo Base','base_essalud'),
          pg_temp.num('BiLicencia Base','base_essalud'),
  'los dos por la misma puerta: mismo catálogo, misma base');

-- ── 2 · El efecto real, en las dos direcciones ─────────────────────────────

select cmp_ok(pg_temp.num('BiLicencia Base','aporte_essalud'), '>',
              pg_temp.num('BiControl Base','aporte_essalud'),
  'la empresa aporta más a EsSalud, que es lo que la ley le pide');

select cmp_ok(pg_temp.num('BiLicencia Base','descuento_afp'), '>',
              pg_temp.num('BiControl Base','descuento_afp'),
  'y a la persona se le descuenta pensión por esos días — va a SU fondo');

-- ── 3 · LO QUE NO DEBE MOVERSE. Es lo que más caro costaría romper ─────────

-- La regla del CLAUDE.md desde la 0193: las sobretasas COMPLETAN una base
-- declarada, nunca CREAN una donde no la hay.
select is(pg_temp.num('BiSueldoFijo Base','base_essalud'),
          pg_temp.num('BiFijoControl Base','base_essalud'),
  'a quien tiene sueldo fijo NO le nace una base: la suya es cero a propósito');
select is(pg_temp.num('BiRxH Base','base_essalud'),
          pg_temp.num('BiRxhControl Base','base_essalud'),
  'a un RxH tampoco: no tiene jornada ni básica que completar');
select is(pg_temp.num('BiRxH Base','descuento_afp'), 0::numeric,
  'y a un RxH no le aparece un descuento de pensión de la nada');

-- El descanso médico ya entraba desde la 0263. Que siga entrando.
select cmp_ok(pg_temp.num('BiDescMedico Base','base_essalud'), '>',
              pg_temp.num('BiControl Base','base_essalud'),
  'el descanso médico sigue entrando: la 0316 no revirtió la 0263');

-- La maternidad es el caso CONTRARIO y se parece en la pantalla.
select cmp_ok(pg_temp.num('BiMaternidad Base','base_essalud'), '<=',
              pg_temp.num('BiControl Base','base_essalud'),
  'la maternidad NO entra: es subsidio de EsSalud, no remuneración (0262)');

-- ── 4 · El tipo, con su tilde ──────────────────────────────────────────────

select is((select nombre from tipos_ausencia where codigo = 'duelo_familiar_directo'),
          'Duelo — familiar directo (cónyuge, padres, hijos, hermanos)',
  'y «cónyuge» lleva tilde, como el resto del catálogo');

-- ── 5 · LA DIVERGENCIA QUE ESTABA DECLARADA, Y QUE YA SE CERRÓ ─────────────
--
-- Aquí vivía una comprobación al estilo de la 244: afirmaba que la remuneración
-- vacacional NO entraba a la base, lo declaraba «defecto abierto a propósito» y
-- avisaba de que el día que alguien lo arreglara esta línea se caería y habría
-- que cambiarla por su contraria.
--
-- Se cayó el mismo día. La **0317** lo cerró, unas horas después de la 0316, en
-- cuanto se midió en producción que no había ni una persona con vacaciones en
-- el periodo abierto — o sea, que el arreglo no movía ninguna boleta.
--
-- Así que ahora dice lo contrario, y con ella la familia queda completa: los
-- TRES conceptos que la planilla paga sin marcaje entran a la base.
select is(pg_temp.num('BiLicencia Base','monto_vacaciones'), 0::numeric,
  'montaje: en este escenario nadie está de vacaciones (si no, lo de abajo no mide nada)');
select ok(
  (select prosrc like '%pb.monto_vacaciones, 0), 2)%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'),
  'y la remuneración vacacional también entra a la base (0317): la familia de tres, completa');

select * from finish();
rollback;
