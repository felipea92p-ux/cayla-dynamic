-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 236_la_ausencia_pagada_se_devenga_por_dias_laborables.test.sql
-- ============================================================================
-- LO QUE CUIDA (0302): que la base de la que la pantalla de Provisiones reserva
-- gratificación sea LA MISMA que la boleta le apunta a esa persona ese mes.
--
-- Antes no lo era. `fn_provisiones` contaba cada día de CALENDARIO de una
-- ausencia pagada y la boleta cuenta los LABORABLES, así que los sábados y
-- domingos del tramo entraban dos veces: una dentro del sueldo mensual y otra
-- como día de ausencia. Y como `fn_grati_cts_periodo` autocompleta el depósito
-- desde esa base, el exceso salía del banco.
--
-- La forma de leer el defecto sin saber SQL era ésta: la reserva le daba MÁS
-- gratificación a quien estuvo de vacaciones que a quien trabajó el mes entero.
-- Por eso la primera comprobación de acá no es un número, es esa comparación.
--
-- SE USA EL MES CALENDARIO COMO PERIODO A PROPÓSITO. El periodo real de CAYLA
-- va del 29 al 28, y esa diferencia de divisor es una divergencia declarada y
-- abierta desde la 0276. Si la prueba usara el periodo real, mediría las dos
-- cosas a la vez y no distinguiría cuál se rompió.
--
-- TRUJILLO NO ES DECORACIÓN. Es la fila que separa este arreglo de «restarle
-- los domingos a la ausencia»: allá el domingo SÍ se trabaja, y el número tiene
-- que cuadrar igual. Un arreglo que reste domingos a ciegas pasa las otras
-- comprobaciones y falla ésta.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000023600', 'ZZPRV', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000236ad', 'PrvAdmin', 'Lab',
        '00000000-0000-0000-0000-000000023600', 'admin', 'x',
        '00000000-0000-0000-0000-0000000236ff', '2024-01-01');
set session_replication_role = origin;

-- Cuatro personas idénticas salvo por lo que les pasó en marzo.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000023601', 'PrvEntero',  'Lab', '00000000-0000-0000-0000-000000023600', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000023602', 'PrvVacas',   'Lab', '00000000-0000-0000-0000-000000023600', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000023603', 'PrvParte',   'Lab', '00000000-0000-0000-0000-000000023600', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000023604', 'PrvTruVacas','Lab', '00000000-0000-0000-0000-000000023600', 'x', '2024-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950, '2024-01-01'
from personas where apellidos = 'Lab' and nombres like 'Prv%' and nombres <> 'PrvAdmin';

-- Lima: lunes a viernes. Trujillo: seis días CON domingo (descansa el miércoles).
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '15:30',
       case when nombres = 'PrvTruVacas' then array[0,1,2,4,5,6] else array[1,2,3,4,5] end
from personas where apellidos = 'Lab' and nombres like 'Prv%' and nombres <> 'PrvAdmin';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000023699', '2026-03-01', '2026-03-31', 'abierto');

-- Todas marcan todos sus días laborables de marzo, menos los que estuvieron
-- ausentes del 02 al 20.
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select p.id, d::date, p.sede_base_id, 6.5, 'cerrada'
from personas p
join horarios_asignados h on h.persona_id = p.id
cross join generate_series('2026-03-01'::timestamp, '2026-03-31'::timestamp, interval '1 day') d
where p.apellidos = 'Lab' and p.nombres like 'Prv%' and p.nombres <> 'PrvAdmin'
  and extract(dow from d)::int = any(h.dias_laborables)
  and not (p.nombres <> 'PrvEntero' and d::date between '2026-03-02' and '2026-03-20');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000236ff', true);

-- El descanso médico entra por `ausencias`; las vacaciones por su propia tabla,
-- que tiene un trigger que crea la ausencia. Cada una por su puerta.
-- Aprobada por DO (0306): sin `aprobada_at` el descanso médico no paga.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at)
values ('00000000-0000-0000-0000-000000023603', 'descanso_medico', '2026-03-02', '2026-03-20',
        'prueba', '00000000-0000-0000-0000-0000000236ad', '00000000-0000-0000-0000-0000000236ad', now());

insert into vacaciones (persona_id, fecha_inicio, fecha_fin, creado_por) values
  ('00000000-0000-0000-0000-000000023602', '2026-03-02', '2026-03-20', '00000000-0000-0000-0000-0000000236ad'),
  ('00000000-0000-0000-0000-000000023604', '2026-03-02', '2026-03-20', '00000000-0000-0000-0000-0000000236ad');

create temporary table t_bol on commit drop as
select e->>'nombre' as persona,
       (e->>'pago_base')::numeric as base,
       (e->>'provision_gratificacion')::numeric as grati
from jsonb_array_elements(
       fn_planilla_calcular('2026-03-01', '2026-03-31',
                            '00000000-0000-0000-0000-000000023699') -> 'filas') e;

create temporary table t_res on commit drop as
select e->>'nombre' as persona, (e->>'grati_s1')::numeric as grati
from jsonb_array_elements(fn_provisiones('2026-03-31') -> 'personas') e;

-- ── 1 · El defecto tal como se leía sin saber SQL ──────────────────────────
select is(
  (select grati from t_res where persona = 'PrvVacas Lab'),
  (select grati from t_res where persona = 'PrvEntero Lab'),
  'la reserva NO le da mas gratificacion a quien estuvo de vacaciones que a quien trabajo el mes entero'
);

-- ── 2 y 3 · Vacaciones: boleta y reserva dicen lo mismo ────────────────────
select is(
  (select grati from t_res where persona = 'PrvVacas Lab'),
  (select grati from t_bol where persona = 'PrvVacas Lab'),
  'vacaciones: lo que reserva la pantalla es lo que apunta la boleta'
);
select is(
  (select base from t_bol where persona = 'PrvVacas Lab'),
  (select base from t_bol where persona = 'PrvEntero Lab'),
  'la boleta le paga el mes completo a quien estuvo de vacaciones (base 0135/0177)'
);

-- ── 4 · Descanso medico: misma rama, mismo resultado ───────────────────────
select is(
  (select grati from t_res where persona = 'PrvParte Lab'),
  (select grati from t_bol where persona = 'PrvParte Lab'),
  'descanso medico: lo que reserva la pantalla es lo que apunta la boleta'
);

-- ── 5 · Trujillo: el domingo SI se trabaja y tambien tiene que cuadrar ─────
select is(
  (select grati from t_res where persona = 'PrvTruVacas Lab'),
  (select grati from t_bol where persona = 'PrvTruVacas Lab'),
  'Trujillo (6 dias con domingo): lo que reserva la pantalla es lo que apunta la boleta'
);

-- ── 6 · Y la ausencia SIGUE contando: sin la rama 0135 esto seria menor ────
select cmp_ok(
  (select grati from t_res where persona = 'PrvVacas Lab'),
  '>',
  0::numeric,
  'la ausencia sigue devengando: tomarse vacaciones no baja la gratificacion a cero'
);

select * from finish();
rollback;
