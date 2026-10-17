-- ============================================================================
-- 418_un_estudio_de_educacion_no_tapa_a_otro.test.sql
-- ============================================================================
-- La regla de la 0524: cada estudio tiene SU día de referencia. La 0233 usaba
-- uno solo por persona —el primer día del periodo con alguna asignación
-- vigente— y un estudio que se acaba justo ese día tapaba a todos los demás.
--
-- El caso que la obligó (2026-10-16, AQP, periodo 28/09–28/10): Duolingo
-- terminaba el 28/09, primer día del periodo, y Pop in colors (S/135) y el
-- Instituto Italo Peruano (S/30), que empezaban el 10/10, no cobraron: la boleta
-- sumó S/104.25 donde tocaban S/165. Acá se repite con fechas de 2027, lejos de
-- cualquier dato real, y con el MISMO periodo de 28/09 a 28/10.
--
-- Y lo que la 0524 NO puede mover, para que no se caiga de lado: la 176 ya fija
-- la renovación contigua con nombres distintos y las tres reglas de la 0150; acá
-- se repiten las que podrían romperse al agrupar por estudio (renovación con
-- hueco y otro nombre escrito, corrección dentro de una familia) y se agrega la
-- que la regla nueva cambia a propósito: dos hijos en el mismo colegio.
--
-- Todo en begin/rollback.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000ed900', 'ZZED9', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000ed901', 'AdminEdu9', 'Laboratorio',
        '00000000-0000-0000-0000-0000000ed900', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000ed909', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ed909', true);

-- Una persona por caso: n = 1..9
create temp table _p as
  select n, ('00000000-0000-0000-0000-0000000eb9' || lpad(n::text, 2, '0'))::uuid as id
  from generate_series(1, 9) n;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
select id, 'EduNueve' || n, 'Laboratorio', '00000000-0000-0000-0000-0000000ed900',
       'test-hash', '2020-01-01', 'planilla'
from _p;

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'aurora', 1500.00, '2020-01-01' from _p;

-- Se insertan directo y no por fn_educacion_registrar: acá se prueba cómo LEE la
-- planilla, no cómo escribe la pantalla (eso lo cubre la 114). Con los triggers
-- apagados, así que la familia se pone a mano: una fila sola es su propia familia.
set session_replication_role = replica;
create function pg_temp._a(
  n int, inst text, monto numeric, ben text, nom text, desde date, hasta date,
  papel boolean default true, fam uuid default gen_random_uuid())
returns void language sql as $$
  insert into asignaciones_educacion
    (persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
     beneficiario_nombre, vigente_desde, vigente_hasta, comprobante_url, familia_id)
  select id, monto, inst, round(monto / 0.75, 2), 75, ben, nom, desde, hasta,
         case when papel then 'educacion/x.pdf' end, fam
    from _p where _p.n = $1
$$;

-- 1 · el caso de AQP, con la fecha ya corregida (Duolingo termina el día ANTES)
select pg_temp._a(1, 'Duolingo',        104.25, 'trabajador', null, '2027-08-29', '2027-09-27');
select pg_temp._a(1, 'Pop in colors',   135.00, 'trabajador', null, '2027-10-10', '2028-03-31');
select pg_temp._a(1, 'Italo Peruano',    30.00, 'trabajador', null, '2027-10-10', '2028-03-31');
-- 2 · el mismo caso con Duolingo terminando el PRIMER día del periodo: lo que tapaba
select pg_temp._a(2, 'Duolingo',        104.25, 'trabajador', null, '2027-08-29', '2027-09-28');
select pg_temp._a(2, 'Pop in colors',   135.00, 'trabajador', null, '2027-10-10', '2028-03-31');
select pg_temp._a(2, 'Italo Peruano',    30.00, 'trabajador', null, '2027-10-10', '2028-03-31');
-- 3 · renovación contigua con nombres distintos (la forma que ya fija la 176)
select pg_temp._a(3, 'Ciclo I',          90.00, 'trabajador', null, '2027-09-01', '2027-10-20');
select pg_temp._a(3, 'Ciclo II',         90.00, 'trabajador', null, '2027-10-21', '2027-11-20');
-- 4 · renovación de la misma institución con hueco de días y el nombre escrito distinto
select pg_temp._a(4, 'Britanico',        90.00, 'trabajador', null, '2027-09-01', '2027-10-20');
select pg_temp._a(4, ' britanico ',      90.00, 'trabajador', null, '2027-10-24', '2027-11-20');
-- 5 · dos estudios de verdad simultáneos, de siempre
select pg_temp._a(5, 'Diplomado',        90.00, 'trabajador', null, '2027-01-01', '2027-12-31');
select pg_temp._a(5, 'Colegio',          60.00, 'hijo', 'Hija de Cinco', '2027-01-01', '2027-12-31');
-- 6 · ciclo que termina a los pocos días de empezar el periodo
select pg_temp._a(6, 'Ciclo corto',      90.00, 'trabajador', null, '2027-01-01', '2027-10-03');
-- 7 · sin comprobante
select pg_temp._a(7, 'Sin papel',        90.00, 'trabajador', null, '2027-08-01', '2027-12-31', false);
-- 8 · dos hijos en el mismo colegio: el segundo empieza a mitad de periodo
select pg_temp._a(8, 'Colegio',          60.00, 'hijo', 'Hijo uno', '2027-03-01', '2027-12-31');
select pg_temp._a(8, 'Colegio',          60.00, 'hijo', 'Hijo dos', '2027-10-10', '2027-12-31');
-- 9 · corrección dentro de la misma familia: la fila vieja se cierra el día
--     anterior y nace la nueva (otro nombre de institución, a propósito)
select pg_temp._a(9, 'Instituto',        90.00, 'trabajador', null, '2027-09-01', '2027-10-10', true,
                  '00000000-0000-0000-0000-0000000fa909');
select pg_temp._a(9, 'Instituto B',     104.25, 'trabajador', null, '2027-10-11', '2028-03-31', true,
                  '00000000-0000-0000-0000-0000000fa909');
set session_replication_role = origin;

-- El periodo REAL de octubre: del 28/09 al 28/10
create temp table _oct as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2027-09-28'::date, '2027-10-28'::date) -> 'filas');

create function pg_temp._m(n int) returns numeric language sql as $$
  select (fila->>'monto_educacion')::numeric from _oct
   where (fila->>'persona_id')::uuid = (select id from _p where _p.n = $1)
$$;


-- ── 1 y 2 · El caso que destapó todo ───────────────────────────────────────
select is(pg_temp._m(1), 165.00::numeric,
  'AQP · con Duolingo ya terminado el 27/09, Pop in colors e Italo cobran: S/165');

select is(pg_temp._m(2), 269.25::numeric,
  'AQP · si Duolingo termina el PRIMER día del periodo cobra su mes y NO tapa a los otros dos (antes: S/104.25)');

select ok(
  (select (fila->>'instituciones_educacion') like '%Pop in colors%'
      and (fila->>'instituciones_educacion') like '%Italo Peruano%'
     from _oct where (fila->>'persona_id')::uuid = (select id from _p where n = 2)),
  'AQP · y la boleta nombra de dónde sale cada sol, incluidos los dos que antes no salían');


-- ── 3, 4, 9 · Una renovación o una corrección no se cobra dos veces ───────
select is(pg_temp._m(3), 90.00::numeric,
  'RENOVACION contigua con otro nombre · ciclo I hasta el 20/10 y ciclo II desde el 21/10: S/90, no S/180');

select is(pg_temp._m(4), 90.00::numeric,
  'RENOVACION de la misma institución con hueco · aunque el nombre cambie de mayúsculas y espacios: S/90');

select is(pg_temp._m(9), 90.00::numeric,
  'CORRECCION dentro de la familia · la fila vieja cobra y la nueva espera al periodo siguiente: S/90');


-- ── 5, 6, 7 · Lo que la 0150 fijó y la 0524 no toca ────────────────────────
select is(pg_temp._m(5), 150.00::numeric,
  'SIMULTANEOS · dos estudios a la vez siguen sumando');

select is(pg_temp._m(6), 90.00::numeric,
  'CICLO CORTO · termina el 03/10 y cobra el mes completo');

select is(pg_temp._m(7), 0.00::numeric,
  'SIN PAPEL · solapa de sobra y aun así no paga');


-- ── 8 · Lo que la 0524 cambia A PROPÓSITO ──────────────────────────────────
select is(pg_temp._m(8), 120.00::numeric,
  'DOS HIJOS en el mismo colegio · el segundo cobra desde que empieza, no el mes siguiente (antes: S/60)');


-- ── Y el mes siguiente: cada uno cobra una sola vez ────────────────────────
create temp table _nov as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2027-10-29'::date, '2027-11-28'::date) -> 'filas');

select is(
  (select (fila->>'monto_educacion')::numeric from _nov
    where (fila->>'persona_id')::uuid = (select id from _p where n = 3)),
  90.00::numeric,
  'RENOVACION · en noviembre cobra solo el ciclo II');

select is(
  (select (fila->>'monto_educacion')::numeric from _nov
    where (fila->>'persona_id')::uuid = (select id from _p where n = 9)),
  104.25::numeric,
  'CORRECCION · en noviembre cobra la vigencia nueva, una sola vez');

select * from finish();
rollback;
