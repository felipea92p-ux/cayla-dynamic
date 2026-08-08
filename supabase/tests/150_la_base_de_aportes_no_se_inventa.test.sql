-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 150_la_base_de_aportes_no_se_inventa.test.sql
-- ============================================================================
-- La 0193 suma el feriado y el sobretiempo a la base de EsSalud y de pensión
-- (SUNAT, tabla 22 PLAME: códigos 0105, 0106 y 0107). Al escribirla se descubrió
-- midiendo que la primera versión estaba mal de una forma que NADA delataba:
--
--   · a un RxH le aparecían S/41.39 de descuento de pensión que hoy no tiene,
--   · y a alguien con sueldo fijo, S/46.45.
--
-- Los dos tienen la básica en 0 a propósito —un locador no aporta, y lo de
-- socios y dirección no se declara por esta vía—, así que su base era 0 y su
-- descuento también. Sumarles el feriado se lo INVENTABA. Ninguna prueba
-- existente cayó: los montos que se movían eran de personas que antes no
-- aparecían en ningún cálculo de pensión.
--
-- La regla que estas pruebas fijan, en una línea: **las sobretasas completan
-- una base declarada; no crean una donde no la hay.**
--
-- Y fijan también lo que la 0192 prometió: que la base se dice UNA sola vez.
-- Si alguien vuelve a escribirla a mano en `descuento_afp` o en `base_essalud`,
-- las dos dejarán de coincidir y esto cae.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000a1', 'ZZBAS', 'Sede de laboratorio BAS', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000a0', 'BasAdmin', 'Lab', '00000000-0000-0000-0000-0000000000a1', 'admin', 'x', '00000000-0000-0000-0000-00000000aa00', '2024-01-01');
set session_replication_role = origin;

-- Un feriado dentro del periodo, para que haya `monto_feriados` que sumar.
insert into feriados (fecha, nombre)
values ('2026-08-06', 'Feriado de laboratorio BAS') on conflict do nothing;

-- Cuatro personas. Las dos primeras SÍ tienen base declarada; las dos últimas
-- la tienen en 0 a propósito y son las que la primera versión rompía.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion,
                      tipo_vinculo, sueldo_fijo, con_hijos, sueldo_base_legal, regimen_pension)
values
  ('00000000-0000-0000-0000-0000000000a2', 'BasNormal', 'Lab', '00000000-0000-0000-0000-0000000000a1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false, false, 1130.00, 'onp'),
  ('00000000-0000-0000-0000-0000000000a3', 'BasHijos',  'Lab', '00000000-0000-0000-0000-0000000000a1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false, true,  1130.00, 'onp'),
  ('00000000-0000-0000-0000-0000000000a4', 'BasFijo',   'Lab', '00000000-0000-0000-0000-0000000000a1', 'x', '2024-01-01', 'taller_produccion', 'planilla', true,  false, null,     'onp'),
  ('00000000-0000-0000-0000-0000000000a5', 'BasRxh',    'Lab', '00000000-0000-0000-0000-0000000000a1', 'x', '2024-01-01', 'taller_produccion', 'rxh',      false, false, null,     'onp');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1650, '2024-01-01'
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000a1' and nombres <> 'BasAdmin';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables)
select id, '2024-01-01', '09:00', '17:00', 0, 0, array[1,2,3,4,5,6]
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000a1' and nombres <> 'BasAdmin';

-- Todas trabajan lunes a sábado, 9 h — se pasan de 48 h y generan sobretiempo,
-- así que la prueba cubre los dos conceptos a la vez.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 9.0, 'cerrada'
from personas p, generate_series('2026-07-29'::date, '2026-08-28'::date, '1 day') d
where p.sede_base_id = '00000000-0000-0000-0000-0000000000a1' and p.nombres <> 'BasAdmin'
  and extract(dow from d)::int between 1 and 6;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000aa00', true);

create temp table b as
select f->>'nombre'                        as nombre,
       (f->>'base_essalud')::numeric       as base_es,
       (f->>'aporte_essalud')::numeric     as aporte_es,
       (f->>'descuento_afp')::numeric      as afp,
       (f->>'tasa_afp')::numeric           as tasa,
       (f->>'monto_feriados')::numeric     as feriados,
       coalesce((f->>'monto_sobretiempo')::numeric, 0) as sobret,
       coalesce((f->>'basica_legal_prop')::numeric, 0) as basica,
       (f->>'asignacion_familiar')::numeric as asig,
       (f->>'essalud_es_piso')::boolean    as es_piso
from (select jsonb_array_elements(
        fn_planilla_calcular('2026-07-29', '2026-08-28')->'filas') f) x
where f->>'nombre' like 'Bas%' and f->>'nombre' not like '%Admin%';

-- ── 1 · Las sobretasas COMPLETAN una base, no la crean ──────────────────────
select is(
  (select afp from b where nombre = 'BasRxh Lab'), 0::numeric,
  'un RxH no cobra descuento de pensión: su básica es 0 y el feriado no se la inventa'
);

select is(
  (select afp from b where nombre = 'BasFijo Lab'), 0::numeric,
  'sueldo fijo tampoco: su básica es 0 a propósito, lo suyo no se declara por esta vía'
);

select is(
  (select aporte_es from b where nombre = 'BasRxh Lab'), 0::numeric,
  'y un RxH tampoco genera EsSalud, por más feriados que tenga en la fila'
);

-- Que tengan feriado es lo que hace la prueba válida: si no lo tuvieran, el
-- cero de arriba no probaría nada.
select cmp_ok(
  (select feriados from b where nombre = 'BasRxh Lab'), '>', 0::numeric,
  'el RxH SÍ tiene monto de feriados en su fila — por eso el cero de arriba dice algo'
);

-- ── 2 · Y a quien sí tiene base, se la completan ────────────────────────────
select cmp_ok(
  (select base_es from b where nombre = 'BasNormal Lab'), '>',
  (select basica + asig from b where nombre = 'BasNormal Lab'),
  'a quien tiene base declarada, el feriado y el sobretiempo se la suben'
);

select is(
  (select round(base_es, 2) from b where nombre = 'BasNormal Lab'),
  (select round(basica + asig + feriados + sobret, 2) from b where nombre = 'BasNormal Lab'),
  'y la base es exactamente básica + asignación + feriados + sobretiempo'
);

select cmp_ok(
  (select sobret from b where nombre = 'BasNormal Lab'), '>', 0::numeric,
  '6 días de 9 h son 54 h: hay sobretiempo, así que el término no es decorativo'
);

-- ── 3 · La base se dice UNA sola vez (lo que prometió la 0192) ──────────────
-- Si alguien vuelve a escribir la expresión a mano en descuento_afp, estas dos
-- dejan de cuadrar. Es el candado del refactor.
select is(
  (select round(afp, 2) from b where nombre = 'BasNormal Lab'),
  (select round(base_es * tasa, 2) from b where nombre = 'BasNormal Lab'),
  'el descuento de pensión sale de la MISMA base que EsSalud, no de otra escrita aparte'
);

select is(
  (select round(afp, 2) from b where nombre = 'BasHijos Lab'),
  (select round(base_es * tasa, 2) from b where nombre = 'BasHijos Lab'),
  'también con asignación familiar de por medio — la base es una sola'
);

-- ── 4 · El piso de la RMV sigue siendo de EsSalud y de nadie más ────────────
-- La pensión NO tiene piso (Ley 26790 art. 6 lo pone solo para EsSalud). Si
-- alguien se lo copiara, quien gana poco pagaría pensión sobre una RMV que no
-- ganó.
select ok(
  (select afp from b where nombre = 'BasNormal Lab')
    < (select round(1130 * tasa, 2) from b where nombre = 'BasNormal Lab')
  or (select basica + asig + feriados + sobret from b where nombre = 'BasNormal Lab') >= 1130,
  'la pensión no tiene piso RMV: solo EsSalud lo tiene'
);

select is(
  (select aporte_es from b where nombre = 'BasHijos Lab'),
  (select round(greatest(base_es, 1130) * 0.09, 2) from b where nombre = 'BasHijos Lab'),
  'y el aporte de EsSalud sí lo respeta: 9 % sobre la base o sobre la RMV, la mayor'
);

select * from finish();
rollback;
