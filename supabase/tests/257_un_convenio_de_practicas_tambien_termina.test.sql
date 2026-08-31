-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 257_un_convenio_de_practicas_tambien_termina.test.sql — 0325
-- ============================================================================
-- La 0322 creó `tipo_vinculo = 'practicante'`, pero hasta la 0325 el CHECK
-- `personas_motivo_cese_valido` no tenía ninguna opción que le quedara bien a
-- su salida: las siete que había describían todas una relación LABORAL
-- ('fin_contrato', 'fin_periodo_prueba') o una locación de servicios
-- ('fin_servicio_rxh') — ver el razonamiento completo en el encabezado de la
-- 0325. Esta prueba cuida las dos mitades de esa promesa.
-- ============================================================================
begin;
select plan(4);

set local session_replication_role = replica;

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000257000', 'ZZ257', 'Sede de laboratorio 257', true);

-- La admin cuya sesión se simula: fn_cesar_persona la exige.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-000000257aa0', 'Jefa', 'Lab257',
        '00000000-0000-0000-0000-000000257000', 'admin', 'h',
        '00000000-0000-0000-0000-000000257aff', '2025-01-02', 'activo');

-- Una practicante, dada de alta bajo modalidad formativa (0322).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-000000257001', 'Nora', 'Practicante257',
        '00000000-0000-0000-0000-000000257000', 'h', '2026-06-01', 'activo', 'practicante');

set local session_replication_role = origin;

do $sesion$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000257aff', true);
end $sesion$;

-- ── 1 · fn_cesar_persona acepta 'fin_convenio_practicas' sin reventar ───────
select lives_ok(
  $$ select fn_cesar_persona('00000000-0000-0000-0000-000000257001'::uuid, '2026-08-15'::date, 'fin_convenio_practicas', null) $$,
  'cesar a una practicante con fin_convenio_practicas no revienta el CHECK que la 0325 reconstruyó');

-- ── 2 · Y queda escrito tal cual, no traducido a otra cosa ──────────────────
select is(
  (select motivo_cese from personas where id = '00000000-0000-0000-0000-000000257001'),
  'fin_convenio_practicas',
  'motivo_cese guarda fin_convenio_practicas — no fin_contrato, no fin_servicio_rxh');

-- ── 3 · El CHECK sigue siendo un CHECK: rechaza un motivo inventado ─────────
-- Sin esta mitad, una prueba que solo aceptara el valor nuevo pasaría igual de
-- verde si la 0325 hubiera reconstruido el constraint sin ninguna restricción.
select throws_ok(
  $$ update personas set motivo_cese = 'motivo_que_no_existe' where id = '00000000-0000-0000-0000-000000257001' $$,
  '23514',
  null,
  'un motivo_cese que no está en la lista sigue rebotando contra el CHECK');

-- ── 4 · Los siete motivos anteriores a la 0325 siguen vivos ─────────────────
-- Se mira la definición VIVA del CHECK, no un archivo del repositorio: un
-- archivo puede estar sin aplicar. Sin esta mitad, la 0325 podría haber
-- reconstruido el constraint dejando fuera 'fin_servicio_rxh' o cualquier otro
-- de los siete que ya existían, y la prueba 1-3 seguiría en verde igual.
select is(
  (select count(*) from unnest(array[
     'renuncia','despido','fin_contrato','fin_periodo_prueba',
     'fin_servicio_rxh','fin_convenio_practicas','mutuo_acuerdo','por_revisar'
   ]) v(motivo)
   where position(quote_literal(v.motivo) in
     pg_get_constraintdef(
       (select oid from pg_constraint
         where conrelid = 'personas'::regclass and conname = 'personas_motivo_cese_valido'))) > 0),
  8::bigint,
  'los ocho motivos válidos — los siete de antes más fin_convenio_practicas — están en el CHECK vigente');

select * from finish();
rollback;
