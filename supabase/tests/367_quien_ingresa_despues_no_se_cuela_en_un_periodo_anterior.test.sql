-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 367_quien_ingresa_despues_no_se_cuela_en_un_periodo_anterior.test.sql — 0463
-- ============================================================================
-- Antes de la 0463, `fn_planilla_calcular_nucleo` metía en CUALQUIER periodo a
-- cualquier persona `activo`, sin mirar si para esas fechas ya había
-- ingresado. Una practicante que ingresó en septiembre aparecía con fila
-- propia en el periodo de julio: «Sin salario», 0 horas, como si ya hubiera
-- estado en la empresa. Esta prueba fija que ya no aparece ANTES de su
-- ingreso, que sigue apareciendo con normalidad DESDE su ingreso, y que a
-- nadie más se le movió una fila (control con una persona antigua).
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000367', 'ZZ367', 'Sede prueba 367', true);

set session_replication_role = replica;
insert into personas
  (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, funcion)
values
  -- La practicante: ingresó a mitad de septiembre.
  ('00000000-0000-0000-0000-000000003671', 'P367Practicante', 'Lab',
   '00000000-0000-0000-0000-000000000367', 'integrante', 'x',
   '00000000-0000-0000-0000-000000003671', '2026-09-08', 'practicante', 'taller_produccion'),
  -- Control: alguien activo desde hace años, en la misma sede.
  ('00000000-0000-0000-0000-000000003672', 'P367Antigua', 'Lab',
   '00000000-0000-0000-0000-000000000367', 'integrante', 'x',
   '00000000-0000-0000-0000-000000003672', '2020-01-01', 'planilla', 'taller_produccion');
set session_replication_role = origin;

create or replace function pg_temp.tiene_fila(p_ini date, p_fin date, p_id uuid) returns boolean
language sql as $f$
  select exists (
    select 1
    from jsonb_array_elements(fn_planilla_calcular_nucleo(p_ini, p_fin) -> 'filas') f
    where (f->>'persona_id')::uuid = p_id
  );
$f$;

-- 1 · CAMBIO 0463 · el periodo de julio termina ANTES de que ingresara: sin fila.
select is(
  pg_temp.tiene_fila('2026-06-29', '2026-07-28', '00000000-0000-0000-0000-000000003671'),
  false,
  'CAMBIO 0463 · una practicante que ingresó en septiembre no aparece en el periodo de julio');

-- 2 · CONTROL · en ese MISMO periodo viejo, quien ya estaba sigue apareciendo.
select is(
  pg_temp.tiene_fila('2026-06-29', '2026-07-28', '00000000-0000-0000-0000-000000003672'),
  true,
  'CONTROL · una persona activa desde 2020 sigue con fila en el mismo periodo de julio');

-- 3 · CAMBIO 0463 · en SU PROPIO periodo (el que sí la contiene) sigue saliendo.
select is(
  pg_temp.tiene_fila('2026-08-29', '2026-09-28', '00000000-0000-0000-0000-000000003671'),
  true,
  'CAMBIO 0463 · la misma practicante sigue apareciendo con normalidad en el periodo que sí la contiene');

-- 4 · CONTROL · el día exacto de ingreso es el borde: un periodo que TERMINA
-- ese mismo día ya la incluye (`fecha_ingreso <= p_fin`, no `<`).
select is(
  pg_temp.tiene_fila('2026-09-01', '2026-09-08', '00000000-0000-0000-0000-000000003671'),
  true,
  'CONTROL · el borde es inclusivo: un periodo que termina el día exacto de su ingreso ya la incluye');

select * from finish();
rollback;
