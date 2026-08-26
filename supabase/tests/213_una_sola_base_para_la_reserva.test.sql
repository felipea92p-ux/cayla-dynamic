-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 213_una_sola_base_para_la_reserva.test.sql
-- ============================================================================
-- EL FRENO QUE PIDE LA 0276. Su promesa no es un monto: es que la boleta y la
-- reserva sigan calculando la MISMA base. Hasta el 2026-08-20 no lo hacían, y
-- de dos maneras distintas a la vez:
--
--   · el feriado estaba escrito dentro de `fn_planilla_calcular` y la palabra
--     no aparecía ni una vez en las 610 líneas de `fn_provisiones`;
--   · el factor de la 0111 (`base_provision / salario`) se aplicaba diez veces
--     en la boleta y CERO en las provisiones.
--
-- Las dos mitades tienen plata dentro: `fn_grati_cts_periodo` AUTOCOMPLETA con
-- lo que dice `fn_provisiones` el monto que se deposita el 15/05, 15/07, 15/11
-- y 15/12. Mientras las dos bases fueran distintas, se depositaba corto.
--
-- POR QUÉ ESTA PRUEBA EXISTE Y NO SOLO LA MIGRACIÓN. Unificar una regla no dura
-- solo: dura mientras alguien no vuelva a escribirla en uno de los dos sitios.
-- La 154 ya dejó dicho por qué —«mientras dos sitios calculen la misma cosa, la
-- próxima corrección volverá a aplicarse a uno solo»— y esa vez nadie se enteró
-- hasta ver una boleta impresa. Las aserciones 1 a 4 son ese freno: comparan
-- MONTOS, no señales de vida.
--
-- ── POR QUÉ EL PERIODO DE LABORATORIO ES UN MES CALENDARIO ──────────────────
-- El periodo de CAYLA va del 29 al 28, y aquí se usa mayo entero (01→31) A
-- PROPÓSITO. La 0276 unifica la base del FERIADO y el factor de la 0111; NO
-- unifica el divisor del sueldo, que en la boleta son los días del PERIODO y en
-- la reserva los días del MES CALENDARIO. Mientras esa tercera diferencia siga
-- abierta, las dos bases solo coinciden al céntimo cuando el periodo y el mes
-- son el mismo tramo — y por eso el laboratorio los hace coincidir. La
-- aserción 3, que compara el feriado persona por persona, no depende de eso y
-- vale para cualquier periodo.
-- ============================================================================
begin;
select plan(26);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000276000', 'ZZ276', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000002760ad', 'SeisAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000276000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000002760a9', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002760a9', true);

-- Mayo de 2026 como periodo de planilla (ver la cabecera). Su único feriado es
-- el 01/05, Día del Trabajo, que además cae en viernes: día laborable de todas.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000276099', '2026-05-01', '2026-05-31', 'abierto');

-- Siete personas que solo se diferencian en lo que cada aserción necesita.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      sueldo_fijo, tipo_vinculo) values
  -- La de referencia: cobra por horas y trabajó el feriado.
  ('00000000-0000-0000-0000-00000027600a','SeisBase',      'Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-05-01',false,'planilla'),
  -- Su gemela exacta —mismas jornadas, mismas horas— con el feriado compensado
  -- por descanso sustitutorio OTORGADO. La única diferencia posible es la
  -- sobretasa del art. 9.
  ('00000000-0000-0000-0000-00000027600b','SeisCompensada','Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-05-01',false,'planilla'),
  -- Igual, pero con el descanso PENDIENTE: eso no compensa nada todavía.
  ('00000000-0000-0000-0000-00000027600c','SeisPendiente', 'Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-05-01',false,'planilla'),
  ('00000000-0000-0000-0000-00000027600d','SeisLocadora',  'Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-05-01',false,'rxh'),
  ('00000000-0000-0000-0000-00000027600e','SeisFija',      'Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-05-01',true ,'planilla'),
  ('00000000-0000-0000-0000-00000027600f','SeisMaternidad','Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-05-01',false,'planilla'),
  -- Entró el 15/05: el feriado del 01/05 es anterior a su ingreso.
  ('00000000-0000-0000-0000-000000276010','SeisTardia',    'Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-05-15',false,'planilla'),
  -- La del bloque de ventanas: entró el 01/04 y se la mira al 31/08, así que
  -- tiene una ventana ene-jun y una jul-dic, las dos con feriados dentro.
  ('00000000-0000-0000-0000-000000276011','SeisVentanas',  'Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-04-01',false,'planilla'),
  -- ⇩ Las dos gemelas del feriado dentro del descanso médico (aserciones 25-26).
  -- Idénticas en todo —mismo sueldo, mismo horario, MISMAS horas marcadas—
  -- salvo en que una tiene el parte médico registrado y la otra no. Esa es la
  -- única variable, y por eso la diferencia entre las dos solo puede venir de
  -- cómo se cuenta el día de ausencia pagada.
  ('00000000-0000-0000-0000-000000276012','SeisMedica',    'Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-05-01',false,'planilla'),
  ('00000000-0000-0000-0000-000000276013','SeisSinParte',  'Laboratorio','00000000-0000-0000-0000-000000276000','test-hash','2026-05-01',false,'planilla');

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, fecha_ingreso, '09:00', '18:00', array[1,2,3,4,5]
from personas where apellidos = 'Laboratorio' and nombres <> 'SeisAdmin';

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950.00, fecha_ingreso
from personas where apellidos = 'Laboratorio' and nombres <> 'SeisAdmin';

-- Todas marcan 6.5 h los días laborables, feriado incluido. La de maternidad no
-- marca nada: su licencia la cubre el subsidio.
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select p.id, d::date, p.sede_base_id, 6.5, 'cerrada'
from personas p
cross join lateral generate_series(greatest(p.fecha_ingreso, date '2026-04-01')::timestamp,
                                   date '2026-08-31'::timestamp, interval '1 day') d
where p.apellidos = 'Laboratorio' and p.nombres <> 'SeisAdmin'
  and p.nombres <> 'SeisMaternidad'
  and extract(dow from d)::int between 1 and 5;

-- El día compensatorio tiene que ser un día LABORABLE que de verdad descansó:
-- el trigger `trg_dcs_validar_dia` rechaza un sábado —«ese día cae en su
-- descanso semanal»— y tiene razón, porque descansar el día que ya le tocaba
-- descansar no compensa nada. Así que se les quita la jornada del jueves 07/05.
--
-- SE LA QUITA A LAS TRES, incluida la que no tiene descanso sustitutorio: las
-- tres tienen que quedar con EXACTAMENTE las mismas horas para que la
-- aserción 5 signifique lo que dice. Si solo se la quitáramos a las
-- compensadas, «reserva más» podría ser simplemente «trabajó un día más».
delete from jornadas
 where persona_id in ('00000000-0000-0000-0000-00000027600a',
                      '00000000-0000-0000-0000-00000027600b',
                      '00000000-0000-0000-0000-00000027600c')
   and fecha = '2026-05-07';

-- ── EL FERIADO DENTRO DE UN DESCANSO MÉDICO ─────────────────────────────────
-- A LAS DOS se les quita la misma semana de jornadas (17 al 21 de agosto, que
-- contiene el miércoles 19 donde más abajo se crea un feriado). Con las horas
-- igualadas, lo único que las separa es el parte médico.
delete from jornadas
 where persona_id in ('00000000-0000-0000-0000-000000276012',
                      '00000000-0000-0000-0000-000000276013')
   and fecha between '2026-08-17' and '2026-08-21';

-- Y solo UNA tiene el parte. Sus cinco días entran a la base por la rama de
-- «los días que la ley manda contar aunque nadie marque»; los de su gemela no
-- entran por ningún lado.
-- Aprobada por DO (0306): sin `aprobada_at` el descanso médico no paga.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por, aprobada_por, aprobada_at)
values ('00000000-0000-0000-0000-000000276012','descanso_medico','2026-08-17','2026-08-21',
        '00000000-0000-0000-0000-0000002760ad', '00000000-0000-0000-0000-0000002760ad', now());

insert into feriados_descanso_sustitutorio (persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado, acta_ref)
values ('00000000-0000-0000-0000-00000027600b','2026-05-01','2026-05-07','OTORGADO','ACTA-276');
insert into feriados_descanso_sustitutorio (persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado)
values ('00000000-0000-0000-0000-00000027600c','2026-05-01','2026-05-07','PENDIENTE');

-- Aprobada por DO (0306): sin `aprobada_at` la maternidad no paga el subsidio,
-- y el feriado que cubre dejaría de excluirse acá.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por, subsidio_diario, aprobada_por, aprobada_at)
values ('00000000-0000-0000-0000-00000027600f','maternidad','2026-04-20','2026-06-30',
        '00000000-0000-0000-0000-0000002760ad', 45.00, '00000000-0000-0000-0000-0000002760ad', now());

create temporary table _bol on commit drop as
select (e ->> 'persona_id')::uuid as persona_id, e as fila
from jsonb_array_elements(
       fn_planilla_calcular('2026-05-01','2026-05-31',
                            '00000000-0000-0000-0000-000000276099') -> 'filas') e;

create temporary table _prov on commit drop as
select (e ->> 'persona_id')::uuid as persona_id, e as fila
from jsonb_array_elements(fn_provisiones('2026-05-31') -> 'personas') e;

-- ════════════════════════════════════════════════════════════════════════════
-- 1 a 4 · EL FRENO: LA MISMA PERSONA, LA MISMA VENTANA, EL MISMO NÚMERO
-- ════════════════════════════════════════════════════════════════════════════
-- SeisBase entró el 01/05 y se la mira al 31/05, así que la ventana de
-- gratificación de `fn_provisiones` —greatest(01/01, ingreso) → least(hoy,
-- 30/06)— es exactamente mayo, el mismo tramo que la boleta. Las dos calculan
-- la misma cosa por caminos distintos: si una de las dos vuelve a mover la base
-- por su cuenta, estas dos líneas se ponen rojas y dicen en cuánto.
select is(
  (select (fila ->> 'provision_gratificacion')::numeric from _bol  where persona_id = '00000000-0000-0000-0000-00000027600a'),
  (select (fila ->> 'grati_s1')::numeric                from _prov where persona_id = '00000000-0000-0000-0000-00000027600a'),
  'UNA SOLA BASE · la gratificación que imprime la boleta es la que reserva la pantalla, al céntimo');

select is(
  (select (fila ->> 'provision_vacaciones')::numeric from _bol  where persona_id = '00000000-0000-0000-0000-00000027600a'),
  (select (fila ->> 'vac')::numeric                  from _prov where persona_id = '00000000-0000-0000-0000-00000027600a'),
  'UNA SOLA BASE · y las vacaciones también');

-- Y el feriado, persona por persona, contra la única función que lo sabe
-- calcular. Esta no depende de que el periodo sea un mes: vale siempre.
select is(
  (select count(*)::int
     from _bol b
    where (b.fila ->> 'monto_feriados')::numeric
          <> round((fn_feriado_devengado(b.persona_id, '2026-05-01', '2026-05-31', 31) ->> 'monto')::numeric, 2)),
  0,
  'UNA SOLA BASE · la boleta dice de feriados exactamente lo que responde fn_feriado_devengado');

-- De partida: si el feriado valiera cero, las tres de arriba no probarían nada.
select cmp_ok(
  (select (fila ->> 'monto_feriados')::numeric from _bol where persona_id = '00000000-0000-0000-0000-00000027600a'),
  '>', 0::numeric,
  'DE PARTIDA · el periodo tiene un feriado que de verdad se paga');

-- ════════════════════════════════════════════════════════════════════════════
-- 5 · EL FERIADO ENTRA EN LA RESERVA, Y SE NOTA
-- ════════════════════════════════════════════════════════════════════════════
-- SeisBase y SeisCompensada tienen las MISMAS jornadas y las mismas horas: lo
-- único que las separa es que a la segunda se le compensó el feriado con un día
-- de descanso. Si la reserva no supiera qué es un feriado —como hasta la
-- 0276— reservarían lo mismo.
select cmp_ok(
  (select (fila ->> 'grati_s1')::numeric from _prov where persona_id = '00000000-0000-0000-0000-00000027600a'),
  '>',
  (select (fila ->> 'grati_s1')::numeric from _prov where persona_id = '00000000-0000-0000-0000-00000027600b'),
  'ENTRA · quien trabajó el feriado reserva MÁS que su gemela a la que se lo compensaron');

-- ════════════════════════════════════════════════════════════════════════════
-- 6 a 8 · CADA FERIADO CUENTA EN LA VENTANA DONDE CAE
-- ════════════════════════════════════════════════════════════════════════════
-- SeisVentanas entró el 01/04 y se la mira al 31/08: su ventana de gratificación
-- del primer semestre es abril-junio y la del segundo es julio-agosto. Se le
-- agrega un feriado NUEVO el 19/08 —miércoles, que trabajó— y se vuelve a
-- preguntar. La reserva del segundo semestre tiene que subir; la del primero no
-- puede moverse ni un céntimo.
create temporary table _antes on commit drop as
select (e ->> 'grati_s1')::numeric as g1, (e ->> 'grati_s2')::numeric as g2
from jsonb_array_elements(fn_provisiones('2026-08-31') -> 'personas') e
where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-000000276011';

-- Las dos gemelas del descanso médico, antes de que exista el feriado.
create temporary table _gem_antes on commit drop as
select (e ->> 'persona_id')::uuid as pid, (e -> 'grati_s2')::numeric as g2
from jsonb_array_elements(fn_provisiones('2026-08-31') -> 'personas') e
where (e ->> 'persona_id')::uuid in ('00000000-0000-0000-0000-000000276012',
                                     '00000000-0000-0000-0000-000000276013');

insert into feriados (fecha, nombre) values ('2026-08-19', 'Feriado de laboratorio 276');

create temporary table _despues on commit drop as
select (e ->> 'grati_s1')::numeric as g1, (e ->> 'grati_s2')::numeric as g2
from jsonb_array_elements(fn_provisiones('2026-08-31') -> 'personas') e
where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-000000276011';

create temporary table _gem_despues on commit drop as
select (e ->> 'persona_id')::uuid as pid, (e -> 'grati_s2')::numeric as g2
from jsonb_array_elements(fn_provisiones('2026-08-31') -> 'personas') e
where (e ->> 'persona_id')::uuid in ('00000000-0000-0000-0000-000000276012',
                                     '00000000-0000-0000-0000-000000276013');

select cmp_ok((select g2 from _despues), '>', (select g2 from _antes),
  'SU VENTANA · un feriado nuevo de agosto sube la reserva del semestre jul-dic');
select is((select g1 from _despues), (select g1 from _antes),
  'SU VENTANA · y no toca la del semestre ene-jun, donde ese feriado no cayó');
select cmp_ok((select g1 from _antes), '>', 0::numeric,
  'SU VENTANA · de partida, la ventana ene-jun tenía algo reservado que se pudiera mover');

-- ════════════════════════════════════════════════════════════════════════════
-- 9 a 17 · LA CASUÍSTICA SOBREVIVE AL TRASLADO
-- ════════════════════════════════════════════════════════════════════════════
-- Son los casos que el lateral `fer` acumuló durante un año dentro de la boleta.
-- Mudarlos de sitio es exactamente el momento en que se pierden.

-- 0199 · un locador no cobra feriados, y tampoco ocupa una fila reservando.
select is(
  (fn_feriado_devengado('00000000-0000-0000-0000-00000027600d','2026-05-01','2026-05-31',31) ->> 'monto')::numeric,
  0::numeric, 'LOCADORA · no devenga feriados: no tiene descanso remunerado que respetar');
select is(
  (select count(*)::int from _prov where persona_id = '00000000-0000-0000-0000-00000027600d'),
  0, 'LOCADORA · ni aparece en la reserva (0274)');

-- 0173 · sueldo fijo: el día ya está dentro de su sueldo, la sobretasa no.
select is(
  (fn_feriado_devengado('00000000-0000-0000-0000-00000027600e','2026-05-01','2026-05-31',31) ->> 'prorrateo')::numeric,
  0::numeric, 'SUELDO FIJO · no cobra el día prorrateado: ya está dentro de su sueldo');
select cmp_ok(
  (fn_feriado_devengado('00000000-0000-0000-0000-00000027600e','2026-05-01','2026-05-31',31) ->> 'sobretasa')::numeric,
  '>', 0::numeric, 'SUELDO FIJO · pero SÍ la sobretasa por haberlo trabajado');

-- 0069 · el descanso sustitutorio OTORGADO anula la sobretasa; PENDIENTE no.
select cmp_ok(
  (fn_feriado_devengado('00000000-0000-0000-0000-00000027600b','2026-05-01','2026-05-31',31) ->> 'sobretasa')::numeric,
  '<',
  (fn_feriado_devengado('00000000-0000-0000-0000-00000027600c','2026-05-01','2026-05-31',31) ->> 'sobretasa')::numeric,
  'SUSTITUTORIO · OTORGADO anula la sobretasa; PENDIENTE la paga');
select cmp_ok(
  (fn_feriado_devengado('00000000-0000-0000-0000-00000027600b','2026-05-01','2026-05-31',31) ->> 'prorrateo')::numeric,
  '>', 0::numeric,
  'SUSTITUTORIO · y compensar la sobretasa NO le quita el día prorrateado (art. 8)');
select is(
  (fn_feriado_devengado('00000000-0000-0000-0000-00000027600b','2026-05-01','2026-05-31',31) ->> 'compensados')::int,
  1, 'SUSTITUTORIO · el feriado compensado se cuenta y se dice cuántos son');

-- 0262 · un feriado dentro de una licencia de maternidad subsidiada no se
-- devenga acá. Si además se le quitara al lateral `mat`, el día no lo pagaría
-- nadie: fue el primer intento de esa migración, medido y descartado.
select is(
  jsonb_array_length(
    fn_feriado_devengado('00000000-0000-0000-0000-00000027600f','2026-05-01','2026-05-31',31) -> 'detalle'),
  0, 'MATERNIDAD · el feriado dentro de la licencia subsidiada no se devenga acá: lo cubre `mat`');

-- 0024 · un feriado anterior a la fecha de ingreso no cuenta, y se dice.
select is(
  (fn_feriado_devengado('00000000-0000-0000-0000-000000276010','2026-05-01','2026-05-31',31) ->> 'no_corresponde')::int,
  1, 'ANTES DEL INGRESO · el feriado previo a la fecha de ingreso no cuenta, y se dice');

-- ════════════════════════════════════════════════════════════════════════════
-- 18 · EL BLOQUE NO ES DECORATIVO
-- ════════════════════════════════════════════════════════════════════════════
-- El prorrateo de un feriado es 7.5 × horas del bloque / (6.5 × días del
-- bloque), y eso NO es invariante de escala: preguntar por un tramo largo como
-- UN bloque da un número mucho más chico. Si algún día los dos coincidieran, es
-- que `p_dias` dejó de hacer algo — y quien reserve por tramos largos empezaría
-- a reservar corto sin que nada falle.
select cmp_ok(
  (fn_feriado_devengado('00000000-0000-0000-0000-000000276011','2026-04-01','2026-08-31',153) ->> 'monto')::numeric,
  '<',
  (fn_feriado_devengado('00000000-0000-0000-0000-000000276011','2026-04-01','2026-08-31',null) ->> 'monto')::numeric,
  'BLOQUE · un divisor de cinco meses achica el feriado; sin p_dias cada uno cobra con su periodo');

-- ════════════════════════════════════════════════════════════════════════════
-- 19 a 21 · EL FACTOR DE LA 0111 TAMBIÉN ES UNA SOLA BASE
-- ════════════════════════════════════════════════════════════════════════════
-- La segunda mitad del encargo. `base_provision` existe para que bajar el rango
-- a la básica legal no le recorte a nadie la gratificación, la CTS ni las
-- vacaciones. La boleta lo aplicaba; la reserva no. Se enciende para SeisBase y
-- las dos tienen que moverse igual.
update asignaciones_salario set base_provision = 2340.00
 where persona_id = '00000000-0000-0000-0000-00000027600a';

create temporary table _bol_f on commit drop as
select (e ->> 'persona_id')::uuid as persona_id, e as fila
from jsonb_array_elements(
       fn_planilla_calcular('2026-05-01','2026-05-31',
                            '00000000-0000-0000-0000-000000276099') -> 'filas') e;
create temporary table _prov_f on commit drop as
select (e ->> 'persona_id')::uuid as persona_id, e as fila
from jsonb_array_elements(fn_provisiones('2026-05-31') -> 'personas') e;

select cmp_ok(
  (select (fila ->> 'grati_s1')::numeric from _prov_f where persona_id = '00000000-0000-0000-0000-00000027600a'),
  '>',
  (select (fila ->> 'grati_s1')::numeric from _prov  where persona_id = '00000000-0000-0000-0000-00000027600a'),
  'FACTOR 0111 · encender base_provision sube la RESERVA, que antes no lo miraba');
select is(
  (select (fila ->> 'provision_gratificacion')::numeric from _bol_f  where persona_id = '00000000-0000-0000-0000-00000027600a'),
  (select (fila ->> 'grati_s1')::numeric                from _prov_f where persona_id = '00000000-0000-0000-0000-00000027600a'),
  'FACTOR 0111 · y la sube EXACTAMENTE lo mismo que a la boleta');
-- Y no se le movió a nadie más: el factor es por persona y por tramo.
select is(
  (select (fila ->> 'grati_s1')::numeric from _prov_f where persona_id = '00000000-0000-0000-0000-00000027600c'),
  (select (fila ->> 'grati_s1')::numeric from _prov   where persona_id = '00000000-0000-0000-0000-00000027600c'),
  'FACTOR 0111 · a quien no lo tiene encendido no se le movió ni un céntimo');

-- ════════════════════════════════════════════════════════════════════════════
-- 22 a 24 · QUE NO VUELVA A HABER DOS COPIAS
-- ════════════════════════════════════════════════════════════════════════════
-- Las de arriba comparan números y son las que valen. Estas tres miran el
-- código, y están para el caso en que alguien "arregle" una de las dos
-- funciones copiando la regla de vuelta: los números podrían seguir cuadrando
-- el día que se pegue el cambio, y volverían a separarse en el siguiente.
select ok(
  (select prosrc like '%fn_feriado_devengado%' from pg_proc where proname = 'fn_provisiones'),
  'SIN SEGUNDA COPIA · fn_provisiones pregunta el feriado, no lo calcula');
select ok(
  (select prosrc like '%base_provision%' from pg_proc where proname = 'fn_provisiones'),
  'SIN SEGUNDA COPIA · y también conoce el factor de la 0111');
select ok(
  (select prosrc not like '%7.5 * (h.horas_mes%' from pg_proc where proname = 'fn_planilla_calcular'),
  'SIN SEGUNDA COPIA · la boleta ya no calcula el prorrateo del feriado por su cuenta');

-- ── 9 · UN FERIADO DENTRO DE UN DESCANSO MÉDICO NO SE PIERDE ───────────────
--
-- ⇩⇩⇩ REESCRITA POR LA 0310 ⇩⇩⇩ La de antes decía «SE CUENTA UNA VEZ» y estaba
-- bien escrita. Vale la pena contar por qué caducó, porque el modo en que
-- caducó es el que se repite en esta casa.
--
-- Nació para defender un defecto que la 0276 introdujo y luego arregló: su
-- primera versión sumaba el feriado a la base sin quitarlo de la rama de
-- ausencias, así que un feriado dentro de un parte médico entraba DOS veces —
-- S/169,33 donde correspondían S/102,48.
--
-- Lo medía así: dos gemelas a las que se les quitó la misma semana, solo una
-- con parte médico; se crea el feriado y la del parte tiene que subir MENOS,
-- «porque ese día ya se lo contaba la rama de ausencias». Cierto mientras
-- `fn_provisiones` excluyera el feriado de esa rama, que es lo que la 0276 puso.
--
-- La **0293** quitó la exclusión gemela de la boleta —«el feriado dentro de un
-- descanso médico se paga»— y dejó la de la reserva en pie. Con la exclusión en
-- un solo lado, ese día **no lo contaba nadie**: S/5,24 por feriado, contra la
-- persona. La **0310** la retiró, y con las dos alineadas la del parte sube MÁS,
-- no menos: `fn_feriado_devengado` prorratea el feriado por lo devengado en el
-- bloque (art. 8 del D. Leg. 713) y ese bloque incluye `horas_descanso_medico`.
-- Medido en los dos lados a la vez: 4,10 en la boleta contra 3,12 de su gemela.
--
-- POR QUÉ ESTA ASERCIÓN NO COMPARA CONTRA LA BOLETA, que sería lo natural.
-- Se intentó y no vale: acá `grati_s2` acumula el SEMESTRE y la boleta mide UN
-- MES, así que los dos números se separan S/146,78 —idéntico en las dos
-- gemelas— por el tamaño de la ventana y no por ningún defecto. Este
-- laboratorio no está construido para eso.
--
-- **El guardián del par vive en la prueba 244**, cuyo laboratorio sí está hecho
-- para compararlos (mes calendario, y el sueldo empieza dentro del mes para que
-- nada devengue antes). Ahí es donde se cazaría hoy el defecto original de la
-- 0276. Lo que queda acá es la otra mitad, la que la 0310 arregló: que el día
-- no se pierda.
select cmp_ok(
  (select d.g2 - a.g2 from _gem_despues d join _gem_antes a on a.pid = d.pid
    where d.pid = '00000000-0000-0000-0000-000000276012'),
  '>',
  0::numeric,
  'NO SE PIERDE · el feriado dentro de un parte médico le sube la reserva a quien lo tiene');

-- Y el control que impide que la de arriba pase por el motivo equivocado. Si
-- alguien "arreglara" esto quitándole el día de ausencia a la rama entera, la
-- comparación de arriba seguiría en verde y habríamos roto la 0135 —tomarse un
-- descanso médico volvería a bajar la gratificación—. Antes del feriado, la
-- del parte tiene que reservar MÁS que su gemela sin parte: son los cinco días
-- que la ley manda contar aunque nadie marque.
select cmp_ok(
  (select g2 from _gem_antes where pid = '00000000-0000-0000-0000-000000276012'),
  '>',
  (select g2 from _gem_antes where pid = '00000000-0000-0000-0000-000000276013'),
  'UNA VEZ · pero el parte médico sigue sumando: sin él reservaría menos');

select * from finish();
rollback;
