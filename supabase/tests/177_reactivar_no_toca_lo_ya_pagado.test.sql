-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 177_reactivar_no_toca_lo_ya_pagado.test.sql
-- (renumerada del 173 al 177: el 173 ya lo había tomado
--  marcar_despues_del_contrato, y dos archivos con el mismo número frenan
--  el push de todos.)
-- ============================================================================
-- QUÉ DEFIENDE, Y POR QUÉ ESTE ARCHIVO ES LA MITAD QUE FALTABA
--
--   La 0209 devuelve salario y horario a quien se reactiva. El primer diseño
--   —reabrir el tramo que el cese cerró, poniéndole `vigente_hasta = null`— se
--   descartó porque al medirlo movía **S/3,390.00 en planillas YA PAGADAS**,
--   sobrepagaba S/1,130.00 del periodo en curso, devengaba +S/719.52 de grati,
--   CTS y vacaciones del hueco, y fabricaba 89 faltas.
--
--   La razón es que `vigente_hasta = null` no significa «vigente desde que
--   volvió»: significa «vigente desde su vigente_desde HASTA EL INFINITO».
--
--   El diseño que quedó crea un tramo NUEVO desde el día de la reactivación,
--   así que el pasado no se puede tocar. **La aserción 1 es esa promesa**, y es
--   la razón de ser del archivo: si alguien mañana «simplifica» la función
--   volviendo a reabrir el tramo viejo, la 1 se pone roja.
--
-- LAS DOS MITADES, que es la forma que este repositorio exige
--   Se prueba que devuelve lo que debe (2, 3, 4) y que NO devuelve lo que no
--   debe (1, 5). Y que el candado se niega cuando toca (8) y **deja pasar
--   cuando no toca** (9) — sin la 9, un candado que cerrara siempre pasaría
--   igual de verde, y ese es justo el que alguien quita en la primera urgencia.
--
-- POR QUÉ SE MIDE EL TOTAL DE LA PLANILLA Y NO LAS FILAS DE LA TABLA
--   Comprobar que `asignaciones_salario` quedó como se espera es comprobar la
--   forma. Lo que le importa a una persona es cuánto cobra, y eso lo dice
--   `fn_planilla_calcular`. La 1 llama a la función de verdad, con el periodo
--   marcado como pagado, antes y después de reactivar.
-- ============================================================================
begin;
select plan(12);

set local session_replication_role = replica;

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000173000', 'ZZ173', 'Sede de laboratorio 173', true);

-- La admin cuya sesión se simula: las funciones de cese y de planilla la exigen.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-0000001730aa', 'Jefa', 'Lab173',
        '00000000-0000-0000-0000-000000173000', 'admin', 'h',
        '00000000-0000-0000-0000-0000001730ff', '2025-01-02', 'activo');

-- ── Los sujetos ─────────────────────────────────────────────────────────────
-- A · el caso normal: trabaja, cesa a mitad del periodo, se reactiva después.
-- B · vuelve teniendo YA un tramo abierto (se lo cargaron estando inactiva).
-- C · arrastra un tramo cerrado con `vigente_hasta` en el FUTURO.
-- D · su cese no cerró ningún tramo: no hay nada que devolver.
-- E · tiene hijos y un periodo pagado detrás: el candado estrecho.
-- F · igual que E pero SIN hijos: el candado NO debe cerrarse.
-- G · la cesan HOY y la reactivan acto seguido. Es el caso MÁS probable —un
--     cese por error se nota el mismo día— y el que la revisión adversaria
--     encontró roto: el tramo que el cese acaba de cerrar lleva
--     `vigente_hasta = hoy`, así que un guard que pregunte «¿le llega algo
--     hasta hoy?» lo ve y se salta la restitución entera. S/1,003.76 perdidos
--     por 130 horas realmente trabajadas.
-- H · sueldo fijo: reactivarla a mitad de periodo le pagaría el mes completo.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, con_hijos)
values
  ('00000000-0000-0000-0000-0000001730a1','Ana','Normal',  '00000000-0000-0000-0000-000000173000','integrante','h','2026-01-05','activo', false),
  ('00000000-0000-0000-0000-000000173071','Gina','CeseHoy','00000000-0000-0000-0000-000000173000','integrante','h','2026-01-05','activo', false),
  ('00000000-0000-0000-0000-0000001730b1','Bea','YaTiene', '00000000-0000-0000-0000-000000173000','integrante','h','2026-01-05','activo', false),
  ('00000000-0000-0000-0000-0000001730c1','Ceci','Futuro', '00000000-0000-0000-0000-000000173000','integrante','h','2026-01-05','activo', false),
  ('00000000-0000-0000-0000-0000001730d1','Dora','Nada',   '00000000-0000-0000-0000-000000173000','integrante','h','2026-01-05','activo', false),
  ('00000000-0000-0000-0000-0000001730e1','Eva','ConHijos','00000000-0000-0000-0000-000000173000','integrante','h','2026-01-05','activo', true),
  ('00000000-0000-0000-0000-0000001730f1','Fina','SinHijos','00000000-0000-0000-0000-000000173000','integrante','h','2026-01-05','activo', false);

insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, sueldo_fijo)
values ('00000000-0000-0000-0000-000000173081','Hilda','Fija','00000000-0000-0000-0000-000000173000','integrante','h','2026-01-05','activo', true);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values
  ('00000000-0000-0000-0000-0000001730a1','cayla', 1500.00, '2026-01-05'),
  ('00000000-0000-0000-0000-0000001730b1','cayla', 1500.00, '2026-01-05'),
  ('00000000-0000-0000-0000-0000001730c1','cayla', 1500.00, '2026-01-05'),
  ('00000000-0000-0000-0000-0000001730d1','cayla', 1500.00, '2026-01-05'),
  ('00000000-0000-0000-0000-0000001730e1','cayla', 1500.00, '2026-01-05'),
  ('00000000-0000-0000-0000-0000001730f1','cayla', 1500.00, '2026-01-05'),
  ('00000000-0000-0000-0000-000000173071','cayla', 1500.00, '2026-01-05'),
  ('00000000-0000-0000-0000-000000173081','cayla', 1130.00, '2026-01-05');

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida)
values
  ('00000000-0000-0000-0000-0000001730a1','2026-01-05','09:00','16:30'),
  ('00000000-0000-0000-0000-0000001730d1','2026-01-05','09:00','16:30'),
  ('00000000-0000-0000-0000-000000173071','2026-01-05','09:00','16:30');

-- Ana trabajó del 29/06 al 10/07, dentro del periodo que después se paga.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000001730a1', d::date, 6.5, 'cerrada'
from generate_series('2026-06-29'::date, '2026-07-10'::date, '1 day') d
where extract(dow from d) between 1 and 5;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000173999', '2026-06-29', '2026-07-28', 'abierto');

-- Cuánto cobra alguien en ese periodo, según la función de verdad.
create or replace function _total_173(p_persona uuid) returns numeric
language sql as $$
  select coalesce((
    select (f->>'total')::numeric
      from jsonb_array_elements(
             fn_planilla_calcular('2026-06-29'::date, '2026-07-28'::date, null) -> 'filas') f
     where (f->>'persona_id')::uuid = p_persona), 0);
$$;

do $sesion$ begin
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000001730ff', true);
end $sesion$;

-- Se cesa ANTES de marcar el periodo como pagado: fn_cesar_persona se niega a
-- cesar dentro de un periodo ya pagado, y con razón.
do $cesar$ begin
  perform fn_cesar_persona('00000000-0000-0000-0000-0000001730a1'::uuid,'2026-07-10'::date,'renuncia',null);
  perform fn_cesar_persona('00000000-0000-0000-0000-0000001730b1'::uuid,'2026-07-10'::date,'renuncia',null);
  perform fn_cesar_persona('00000000-0000-0000-0000-0000001730c1'::uuid,'2026-07-10'::date,'renuncia',null);
  perform fn_cesar_persona('00000000-0000-0000-0000-0000001730e1'::uuid,'2026-07-10'::date,'renuncia',null);
  perform fn_cesar_persona('00000000-0000-0000-0000-0000001730f1'::uuid,'2026-07-10'::date,'renuncia',null);
  perform fn_cesar_persona('00000000-0000-0000-0000-000000173081'::uuid,'2026-07-10'::date,'renuncia',null);
  -- G se cesa con la fecha de HOY: el tramo queda `vigente_hasta = hoy`.
  perform fn_cesar_persona('00000000-0000-0000-0000-000000173071'::uuid,
                           (now() at time zone 'America/Lima')::date,'renuncia',null);
end $cesar$;

-- Dora: su cese no cierra nada porque ya no tenía tramo abierto.
update asignaciones_salario set vigente_hasta = '2026-05-31'
 where persona_id = '00000000-0000-0000-0000-0000001730d1';
update horarios_asignados set vigente_hasta = '2026-05-31'
 where persona_id = '00000000-0000-0000-0000-0000001730d1';
do $cesar_d$ begin
  perform fn_cesar_persona('00000000-0000-0000-0000-0000001730d1'::uuid,'2026-07-10'::date,'renuncia',null);
end $cesar_d$;

-- Bea: le cargan salario estando inactiva (fn_set_salario no mira `estado`).
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000001730b1','aurora', 1900.00, '2026-08-01');

-- Ceci: arrastra un tramo cerrado con vigencia en el futuro.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-0000001730c1','aurora', 1900.00, '2026-07-11', '2099-12-31');

-- Y AHORA el periodo se paga. A partir de aquí, su total no se puede mover.
update periodos_planilla set estado = 'pagado', pagado_at = now()
 where id = '00000000-0000-0000-0000-000000173999';

-- El total de Ana en el periodo pagado, ANTES de reactivarla.
create temporary table _antes_173 as select _total_173('00000000-0000-0000-0000-0000001730a1'::uuid) as total;

do $react$ begin
  perform fn_reactivar_persona('00000000-0000-0000-0000-0000001730a1'::uuid);
  perform fn_reactivar_persona('00000000-0000-0000-0000-0000001730b1'::uuid);
  perform fn_reactivar_persona('00000000-0000-0000-0000-0000001730c1'::uuid);
  perform fn_reactivar_persona('00000000-0000-0000-0000-0000001730d1'::uuid);
  perform fn_reactivar_persona('00000000-0000-0000-0000-0000001730f1'::uuid);
  perform fn_reactivar_persona('00000000-0000-0000-0000-000000173071'::uuid);
end $react$;

-- ── 1 · LA PROMESA: un periodo PAGADO no cambia de total ────────────────────
select is(
  _total_173('00000000-0000-0000-0000-0000001730a1'::uuid),
  (select total from _antes_173),
  'reactivar NO mueve el total de un periodo ya pagado — el tramo nuevo empieza hoy, no en el cese');

-- ── 2 · El salario vuelve, y vuelve DESDE HOY ───────────────────────────────
select is(
  (select vigente_desde from asignaciones_salario
    where persona_id = '00000000-0000-0000-0000-0000001730a1' and vigente_hasta is null),
  (now() at time zone 'America/Lima')::date,
  'el tramo de salario nuevo arranca el día de la reactivación, no el del cese');

-- ── 3 · El tramo viejo se queda donde estaba ────────────────────────────────
select is(
  (select count(*)::int from asignaciones_salario
    where persona_id = '00000000-0000-0000-0000-0000001730a1' and vigente_hasta = '2026-07-10'),
  1,
  'el tramo que cerró el cese sigue cerrado el 10/07: el pasado no se toca');

-- ── 4 · El horario también vuelve, desde hoy ────────────────────────────────
select is(
  (select vigente_desde from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-0000001730a1' and vigente_hasta is null),
  (now() at time zone 'America/Lima')::date,
  'el horario nuevo arranca el día de la reactivación');

-- ── 5 · Si ya tenía un tramo abierto, el suyo manda ─────────────────────────
select is(
  (select salario_mensual_soles from asignaciones_salario
    where persona_id = '00000000-0000-0000-0000-0000001730b1' and vigente_hasta is null),
  1900.00::numeric,
  'a quien ya tenía salario vigente no se le pisa con el viejo');

-- ── 6 · Un tramo cerrado con fecha futura no revienta el antisolape ─────────
select is(
  (select count(*)::int from asignaciones_salario
    where persona_id = '00000000-0000-0000-0000-0000001730c1' and vigente_hasta is null),
  0,
  'con un tramo cerrado hasta 2099 no se inventa otro encima: no revienta el EXCLUDE');

-- ── 7 · Cero filas deja rastro, en vez de callarse ──────────────────────────
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-0000001730d1'
      and campo_modificado = 'reactivacion_sin_salario_que_devolver'),
  1,
  'cuando no hay nada que devolver, queda escrito — callarse apagaría la sospecha');

-- ── 8 · El candado se cierra donde el daño está medido ──────────────────────
select throws_like($$
  select fn_reactivar_persona('00000000-0000-0000-0000-0000001730e1'::uuid)
$$, '%PAGADA%',
  'con hijos y un periodo pagado detrás, reactivar se niega: movería ese total');

-- ── 9 · Y NO se cierra donde no hay daño ────────────────────────────────────
-- La otra mitad. Sin esto, un candado que cerrara siempre pasaría igual de
-- verde — y de las 8 personas inactivas de producción, SEIS tienen un periodo
-- pagado detrás y para las seis el daño es cero.
select is(
  (select estado from personas where id = '00000000-0000-0000-0000-0000001730f1'),
  'activo',
  'sin hijos, el mismo periodo pagado NO impide reactivar: el candado no prohíbe de más');

-- ── 10 · EL CESE DE HOY, que es el caso más probable ───────────────────────
-- Aquí murió la primera versión: el guard veía el tramo recién cerrado con
-- `vigente_hasta = hoy`, creía que ya tenía salario y no devolvía nada.
select is(
  (select count(*)::int from asignaciones_salario
    where persona_id = '00000000-0000-0000-0000-000000173071' and vigente_hasta is null),
  1,
  'cesada y reactivada el MISMO día: sí se le devuelve el salario (aquí se perdían S/1,003.76)');

-- ── 11 · Y arranca MAÑANA, no hoy ──────────────────────────────────────────
-- El día del cese lo cubre el tramo viejo —ese día sí trabajó— y arrancar hoy
-- chocaría contra el EXCLUDE, que usa un daterange con los dos extremos cerrados.
select is(
  (select vigente_desde from asignaciones_salario
    where persona_id = '00000000-0000-0000-0000-000000173071' and vigente_hasta is null),
  (now() at time zone 'America/Lima')::date + 1,
  'el tramo nuevo arranca al día siguiente del cese, sin solaparse con el viejo');

-- ── 12 · El sueldo fijo se para, porque cobraría el periodo entero ─────────
select throws_like($$
  select fn_reactivar_persona('00000000-0000-0000-0000-000000173081'::uuid)
$$, '%sueldo fijo%',
  'con sueldo fijo, reactivar a mitad de periodo se niega: le pagaría el mes completo');

select * from finish();
rollback;
