-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 242_la_reserva_tampoco_devenga_sin_la_firma_de_do.test.sql
-- ============================================================================
-- LO QUE CUIDA (0308): que `fn_provisiones` exija la misma firma de DO que la
-- boleta exige desde la 0306.
--
-- La 0306 arregló media cosa. Hizo que `fn_planilla_calcular` dejara de pagar
-- el descanso médico y la maternidad sin aprobar — bien argumentado: la
-- aprobación es de DO, no de la sede. Pero `fn_provisiones` no se enteró, así
-- que un descanso médico registrado y sin firmar pagaba S/0 de sueldo y
-- reservaba como si se hubiera pagado el mes entero. Y de ahí sale el depósito:
-- `fn_grati_cts_periodo` es la única función que llama a `fn_provisiones`.
--
-- ── LA COMPROBACIÓN QUE IMPORTA MÁS ES LA DE LAS VACACIONES ─────────────────
--
-- No la de los casos que se arreglan. Las vacaciones entran a `ausencias` por
-- un trigger desde su propia tabla y llegan SIEMPRE con `aprobada_at` en null.
-- Un arreglo que exija la firma a ciegas —en vez de preguntarle a
-- `tipos_ausencia.requiere_aprobacion`, que dice que las vacaciones no la
-- necesitan— le pondría la reserva en cero a todo el que se toma vacaciones.
--
-- Eso sería un defecto mucho peor que el que se arregla, y en la dirección que
-- esta casa considera la más cara: contra la persona. La comprobación 1 existe
-- para que ese arreglo perezoso no pueda entrar.
--
-- ── Y LA MATERNIDAD FIRMADA NO TIENE QUE CUADRAR ────────────────────────────
--
-- Se comprueba a propósito que SIGA divergiendo. La boleta marca esos días
-- `dias_maternidad_sin_monto` porque el subsidio lo paga EsSalud y no CAYLA; la
-- reserva sí devenga, porque el art. 3.2 c) del D.S. 005-2002-TR cuenta como
-- tiempo efectivamente laborado los descansos que originan subsidio. Los dos
-- miden cosas distintas. Si algún día alguien los «arregla» para que coincidan,
-- esta prueba se lo va a decir.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000024200', 'ZZFIR', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000242ad', 'FirAdmin', 'Lab',
        '00000000-0000-0000-0000-000000024200', 'admin', 'x',
        '00000000-0000-0000-0000-0000000242ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000024201', 'FirEntero',   'Lab', '00000000-0000-0000-0000-000000024200', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000024202', 'FirVacas',    'Lab', '00000000-0000-0000-0000-000000024200', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000024203', 'FirParteSin', 'Lab', '00000000-0000-0000-0000-000000024200', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000024204', 'FirParteCon', 'Lab', '00000000-0000-0000-0000-000000024200', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000024205', 'FirMaterSin', 'Lab', '00000000-0000-0000-0000-000000024200', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000024206', 'FirMaterCon', 'Lab', '00000000-0000-0000-0000-000000024200', 'x', '2024-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950, '2024-01-01'
from personas where apellidos = 'Lab' and nombres like 'Fir%' and nombres <> 'FirAdmin';

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '15:30', array[1,2,3,4,5]
from personas where apellidos = 'Lab' and nombres like 'Fir%' and nombres <> 'FirAdmin';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000024299', '2026-03-01', '2026-03-31', 'abierto');

insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select p.id, d::date, p.sede_base_id, 6.5, 'cerrada'
from personas p
cross join generate_series('2026-03-01'::timestamp, '2026-03-31'::timestamp, interval '1 day') d
where p.apellidos = 'Lab' and p.nombres like 'Fir%' and p.nombres <> 'FirAdmin'
  and extract(dow from d)::int between 1 and 5
  and not (p.nombres <> 'FirEntero' and d::date between '2026-03-02' and '2026-03-20');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000242ff', true);

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-000000024203', 'descanso_medico', '2026-03-02', '2026-03-20', 'prueba', '00000000-0000-0000-0000-0000000242ad'),
  ('00000000-0000-0000-0000-000000024204', 'descanso_medico', '2026-03-02', '2026-03-20', 'prueba', '00000000-0000-0000-0000-0000000242ad'),
  ('00000000-0000-0000-0000-000000024205', 'maternidad',      '2026-03-02', '2026-03-20', 'prueba', '00000000-0000-0000-0000-0000000242ad'),
  ('00000000-0000-0000-0000-000000024206', 'maternidad',      '2026-03-02', '2026-03-20', 'prueba', '00000000-0000-0000-0000-0000000242ad');

-- La vacación entra por SU tabla, y el trigger la deja sin `aprobada_at`. Eso
-- no se toca a mano a propósito: es el estado real en el que llega.
insert into vacaciones (persona_id, fecha_inicio, fecha_fin, creado_por)
values ('00000000-0000-0000-0000-000000024202', '2026-03-02', '2026-03-20',
        '00000000-0000-0000-0000-0000000242ad');

-- Firman solo dos de las cuatro.
update ausencias set aprobada_at = now(), aprobada_por = '00000000-0000-0000-0000-0000000242ad'
where persona_id in ('00000000-0000-0000-0000-000000024204', '00000000-0000-0000-0000-000000024206');

create temporary table t_bol on commit drop as
select e->>'nombre' as persona,
       (e->>'provision_gratificacion')::numeric as grati
from jsonb_array_elements(
       fn_planilla_calcular('2026-03-01', '2026-03-31',
                            '00000000-0000-0000-0000-000000024299') -> 'filas') e;

create temporary table t_res on commit drop as
select e->>'nombre' as persona, (e->>'grati_s1')::numeric as grati
from jsonb_array_elements(fn_provisiones('2026-03-31') -> 'personas') e;

-- ── 1 · LA IMPORTANTE: la vacacion no necesita firma y no puede perderla ────
select is(
  (select grati from t_res where persona = 'FirVacas Lab'),
  (select grati from t_res where persona = 'FirEntero Lab'),
  'una vacacion sin aprobada_at —asi entran todas— sigue devengando igual que un mes trabajado'
);
select ok(
  (select requiere_aprobacion is not true from tipos_ausencia where codigo = 'vacaciones'),
  'el catalogo dice que las vacaciones NO requieren aprobacion, que es de donde 0308 saca la regla'
);

-- ── 2 · Descanso medico: sin firma no devenga; con firma, entero ────────────
select is(
  (select grati from t_res where persona = 'FirParteSin Lab'),
  (select grati from t_bol where persona = 'FirParteSin Lab'),
  'descanso medico SIN firmar: la reserva dice lo mismo que la boleta (o sea, no devenga)'
);
select is(
  (select grati from t_res where persona = 'FirParteCon Lab'),
  (select grati from t_bol where persona = 'FirParteCon Lab'),
  'descanso medico firmado: sigue devengando el mes entero, igual que la boleta'
);

-- ── 3 · Maternidad sin firmar: tampoco ─────────────────────────────────────
select is(
  (select grati from t_res where persona = 'FirMaterSin Lab'),
  (select grati from t_bol where persona = 'FirMaterSin Lab'),
  'maternidad SIN firmar: la reserva dice lo mismo que la boleta'
);

-- ── 4 · Y la maternidad FIRMADA tiene que SEGUIR divergiendo ───────────────
-- No es un defecto: la boleta no paga el subsidio porque lo paga EsSalud, y la
-- reserva sí devenga por el art. 3.2 c) del D.S. 005-2002-TR. Si algun dia
-- alguien los iguala, que sea a sabiendas.
select cmp_ok(
  (select grati from t_res where persona = 'FirMaterCon Lab'),
  '>',
  (select grati from t_bol where persona = 'FirMaterCon Lab'),
  'maternidad firmada: la reserva SIGUE devengando mas que la boleta, y es correcto'
);

select * from finish();
rollback;
