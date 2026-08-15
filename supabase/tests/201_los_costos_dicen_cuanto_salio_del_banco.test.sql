-- ============================================================================
-- 201_los_costos_dicen_cuanto_salio_del_banco.test.sql — migración 0260
-- ============================================================================
-- La pantalla de Costos respondía dos preguntas —cuánto recibió la gente y
-- cuánto se devengó— y le faltaba la tercera: cuánta plata salió de la cuenta.
-- Faltaban tres pagos que CAYLA hace POR la persona y que no estaban sumados en
-- ninguna pantalla: la pensión que va a la AFP (0110), el 9 % de EsSalud que es
-- de cargo del empleador (0116) y la retención de renta de 4ta (0245).
--
-- LA MITAD DEL VALOR DE ESTA PRUEBA ES QUE LAS OTRAS TRES CIFRAS NO SE MUEVAN.
-- La 0260 reescribe `fn_costos_planilla` entera, y esa función alimenta la única
-- pantalla desde la que se mira lo que cuesta el equipo. Si al agregar una cifra
-- se moviera `costo`, nadie lo notaría hasta usarla para decidir algo.
--
-- El montaje: un periodo cerrado con dos personas que se descuentan cosas
-- distintas —una locadora con retención de 4ta y sin aportes, y una trabajadora
-- de planilla con pensión y EsSalud y sin retención—, para que ninguna de las
-- dos pueda tapar el error de la otra.
--
-- Honorario y sueldo 652.17 los dos, periodo del 29-jul al 28-ago.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000201', 'ZZ201', 'Sede de laboratorio 201', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000020199', 'Adm201', 'Laboratorio',
        '00000000-0000-0000-0000-000000000201', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000020198', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000020198', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      tipo_vinculo, sueldo_fijo, retencion_4ta, regimen_pension) values
  ('00000000-0000-0000-0000-000000020101', 'Loc', 'ConRetencion',
   '00000000-0000-0000-0000-000000000201', 'th', '2025-01-01', 'rxh', true, 'siempre', null),
  ('00000000-0000-0000-0000-000000020102', 'Test', 'DePlanilla',
   '00000000-0000-0000-0000-000000000201', 'th', '2025-01-01', 'planilla', false, null, 'integra');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla', 652.17, '2025-01-01'
from personas where sede_base_id = '00000000-0000-0000-0000-000000000201'
  and id <> '00000000-0000-0000-0000-000000020199';

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000020102', d::date, 8, 'cerrada'
from generate_series('2026-07-29'::date, '2026-08-28'::date, interval '1 day') d
where extract(dow from d) <> 0;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000000207', '2026-07-29', '2026-08-28', 'abierto');
select fn_planilla_congelar('00000000-0000-0000-0000-000000000207', 'pago',
                            '00000000-0000-0000-0000-000000020199');
update periodos_planilla set estado = 'pagado', pagado_at = now()
 where id = '00000000-0000-0000-0000-000000000207';

create temp table _c on commit drop as
select fn_costos_planilla('2026-01-01', '2026-12-31') as j;

create temp table _f on commit drop as
select d.persona_id,
       d.total, d.retencion_4ta, d.descuento_pension, d.aporte_essalud
from planilla_pagada_detalle d
where d.periodo_id = '00000000-0000-0000-0000-000000000207';

-- ── 1 · La cifra nueva existe y NO es el neto ──────────────────────────────
select isnt(
  (select (j->'totales'->>'salio_del_banco')::numeric from _c),
  (select (j->'totales'->>'neto')::numeric from _c),
  'Lo que salio del banco no es lo mismo que lo que se transfirio');

-- ── 2 · Y es exactamente el neto mas lo que se remite por la persona ───────
-- Contra la foto, no contra un numero escrito a mano: si manana cambia una
-- tasa, esta prueba sigue diciendo la verdad.
select is(
  (select (j->'totales'->>'salio_del_banco')::numeric from _c),
  (select round(sum(total + retencion_4ta + descuento_pension + aporte_essalud), 2) from _f),
  'Es el neto mas la pension, el EsSalud y la retencion de 4ta, al centimo');

-- ── 3 · NO lleva provisiones, y es a proposito ────────────────────────────
-- Se devengan ahora y se pagan despues. Sumarlas volveria esta cifra un hibrido
-- de caja y devengado, que es justo lo que hace ilegible al «costo real».
select cmp_ok(
  (select (j->'totales'->>'salio_del_banco')::numeric from _c),
  '<',
  (select ((j->'totales'->>'neto')::numeric + (j->'totales'->>'provisiones')::numeric
           + (select sum(retencion_4ta + descuento_pension + aporte_essalud) from _f)) from _c),
  'No incluye provisiones: son devengo, no caja');

-- ── 4 · LAS OTRAS TRES CIFRAS NO SE MUEVEN ────────────────────────────────
select is(
  (select (j->'totales'->>'neto')::numeric from _c),
  (select round(sum(total), 2) from _f),
  'El neto sigue siendo la suma de los totales de la foto');

select is(
  (select (j->'totales'->>'costo')::numeric from _c),
  (select round(sum(d.costo_total), 2) from planilla_pagada_detalle d
    where d.periodo_id = '00000000-0000-0000-0000-000000000207'),
  'Y el costo real sigue siendo neto + provisiones: la 0260 no lo toco');

-- ── 5 · La cifra baja tambien a los cortes, no solo al total ──────────────
-- Son seis agregados y es facil dejarse uno: una tabla con la columna vacia se
-- lee como «esta sede no remite nada», que es peor que no tener la columna.
select is(
  (select count(*) from jsonb_array_elements((select j->'por_sede' from _c)) s
    where s->>'salio_del_banco' is null),
  0::bigint,
  'Cada sede trae su propia cifra: ningun corte se quedo sin ella');

select * from finish();
rollback;
