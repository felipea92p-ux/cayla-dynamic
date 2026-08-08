-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 145_direccion_no_es_sueldo_fijo_ni_es_admin.test.sql
-- ============================================================================
-- La 0187 saca al personal de dirección del sobretiempo (art. 5, D.S. 007-2002-TR)
-- con una columna propia. Lo tentador —y lo que estas pruebas impiden— es
-- ahorrársela deduciéndola de algo que ya existe:
--
--   · De `rol = 'admin'`. Es un permiso INFORMÁTICO. El día que se le dé admin a
--     alguien de DO para que administre pantallas, se le quitaría sin querer su
--     derecho a horas extras, y nadie lo notaría hasta que reclame.
--   · De `sueldo_fijo`. Es una condición de PAGO. Hoy coinciden en varias
--     personas y por eso parece lo mismo; no lo es, y el caso que lo prueba está
--     abajo: dirección que cobra por horas.
--
-- La otra mitad —que la columna no apague el cálculo para todo el mundo— la
-- cubre la 143, que corre con la misma base y verifica que quien no está
-- marcado sigue cobrando su recargo.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000c1', 'ZZDIR', 'Sede de laboratorio DIR', true);

-- La admin que calcula. Tiene rol admin y NO es dirección: existe justamente
-- para probar que las dos cosas no se confunden.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000c0', 'DirAdminDO', 'Lab', '00000000-0000-0000-0000-0000000000c1', 'admin', 'x', '00000000-0000-0000-0000-00000000cc00', '2024-01-01');
set session_replication_role = origin;

-- Dos personas con la MISMA jornada y el MISMO salario. Lo único distinto es la
-- marca de dirección.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo)
values ('00000000-0000-0000-0000-0000000000c2', 'DirComun',    'Lab', '00000000-0000-0000-0000-0000000000c1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
       ('00000000-0000-0000-0000-0000000000c3', 'DirDireccion','Lab', '00000000-0000-0000-0000-0000000000c1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false);

update personas set personal_direccion = true
where id = '00000000-0000-0000-0000-0000000000c3';

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1130, '2024-01-01'
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000c1';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables)
select id, '2024-01-01', '09:00', '17:00', 0, 0, array[1,2,3,4,5,6]
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000c1';

-- Las tres, la misma semana de 51 h (6 días de 8.5). Se pasan por 3.
-- La admin también marca: si el filtro se hiciera por rol, ella caería.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 8.5, 'cerrada'
from unnest(array['00000000-0000-0000-0000-0000000000c0',
                  '00000000-0000-0000-0000-0000000000c2',
                  '00000000-0000-0000-0000-0000000000c3']::uuid[]) p,
     generate_series('2026-08-03'::date, '2026-08-08'::date, '1 day') d;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000cc00', true);

create temp table dir as
select f->>'nombre' as nombre, (f->>'monto_sobretiempo')::numeric as monto
from (select jsonb_array_elements(
        fn_planilla_calcular('2026-07-29', '2026-08-28')->'filas') f) x
where f->>'nombre' like 'Dir%';

-- ── La columna existe y nace apagada ────────────────────────────────────────
select has_column('personas', 'personal_direccion',
  'personas.personal_direccion existe: la exclusión del art. 5 tiene dónde vivir');

select col_not_null('personas', 'personal_direccion',
  'y no admite null — un null en un permiso se lee como «quizá» y no hay quizá acá');

select col_default_is('personas', 'personal_direccion', 'false',
  'nace en false: marcar a alguien le quita un derecho, tiene que ser deliberado');

-- ── Lo que la columna hace ──────────────────────────────────────────────────
select is(
  (select monto from dir where nombre = 'DirDireccion Lab'), 0::numeric,
  'marcada como dirección: 51 h en la semana y cero sobretiempo (art. 5)'
);

select isnt(
  (select monto from dir where nombre = 'DirComun Lab'), 0::numeric,
  'la misma jornada sin marcar SÍ cobra — la exclusión distingue, no apaga el cálculo'
);

select is(
  (select monto from dir where nombre = 'DirComun Lab'), 4.77::numeric,
  'y cobra lo de siempre: 2 h al 25 % + 1 h al 35 % sobre S/1130 en 201.5 h'
);

-- ── Lo que la columna NO es ─────────────────────────────────────────────────
select isnt(
  (select monto from dir where nombre = 'DirAdminDO Lab'), 0::numeric,
  'tener rol admin NO excluye: es un permiso del sistema, no una categoría laboral'
);

select is(
  (select sueldo_fijo from personas where id = '00000000-0000-0000-0000-0000000000c3'),
  false,
  'dirección puede cobrar por horas: no implica sueldo fijo'
);

select is(
  (select array_agg(rol::text order by rol::text)
     from personas where personal_direccion is true),
  array['integrante'],
  'y no implica ningún rol: quien está marcada acá es una integrante más en el sistema'
);

select * from finish();
rollback;
