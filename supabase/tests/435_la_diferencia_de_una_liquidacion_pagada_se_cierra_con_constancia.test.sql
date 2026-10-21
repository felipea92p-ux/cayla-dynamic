-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 435_la_diferencia_de_una_liquidacion_pagada_se_cierra_con_constancia.test.sql — 0542
-- ============================================================================
-- QUÉ DEFIENDE ESTE ARCHIVO
--
--   (A) El SENTIDO de la diferencia lo calcula el servidor, y la decisión
--       depende de él: a favor de la persona → «lo pagado era lo correcto» con
--       apoyo; a favor de CAYLA → «no se reclama» / «devolución acordada»; una
--       diferencia mixta no se puede constatar (queda abierta: el error caro
--       es cerrar un aviso real).
--
--   (B) El guardián rechaza todo lo que no debe pasar: motivo corto, decisión
--       fuera de catálogo o contraria al sentido, sin apoyo, versión o huella
--       vieja (el cálculo cambió mientras se miraba), cese que ya no es el
--       actual, y quien no es admin o líder DO.
--
--   (C) Una sola constancia vigente por diferencia: doble clic y dos
--       revisores se rechazan con un mensaje; corregir y retirar son una
--       cadena, nunca un UPDATE; retirar reabre el aviso.
--
--   (D) «Vuelve si el cálculo cambia» — y vuelve a valer si el cálculo vuelve a
--       lo que era.
--
--   (E) El descuento del cierre de mes NO caduca una constancia (la huella no
--       lleva la fila TOTAL). Y el CASO CONOCIDO: si la diferencia real está en
--       el propio «Sueldo del periodo» y después se registra el descuento, la
--       diferencia de esa fila cambia en −D y la constancia caduca UNA vez.
--
--   (F) Una constancia sobre una versión superada o anulada es inerte.
--
--   (G) Los estados imposibles se rechazan por el esquema, saltándose la
--       función (insert directo como dueño): CHECK, FK compuesta, índices
--       únicos y el trigger de inmutabilidad.
--
--   (H) La tabla está CERRADA para escribir (revoke, no ausencia de grant), con
--       un control que reabre el hueco a propósito para probar que la
--       aserción puede fallar. Lectura solo para admin y líder DO.
--
--   (I) La huella no depende del orden de entrada ni de la forma del numeric.
--
-- MONTAJE. El freno del cierre mira el periodo entero, así que los casos que
-- cierran un mes (F, G) van cada uno en su propio periodo, solos; el resto
-- comparte un periodo que nunca se cierra. La diferencia real se fabrica
-- congelando la liquidación con un `pagado` desplazado respecto del `ahora`
-- calculado (`pg_temp.congelar`): así el sentido y el monto son exactos.
-- ============================================================================
begin;
select plan(118);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000435000', 'ZZ435', 'Sede de laboratorio 435', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000435099', 'Admin435', 'Laboratorio',
   '00000000-0000-0000-0000-000000435000', 'admin', 'test-hash',
   '00000000-0000-0000-0000-000000435098', '2020-01-01'),
  ('00000000-0000-0000-0000-000000435097', 'Integrante435', 'Laboratorio',
   '00000000-0000-0000-0000-000000435000', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000435096', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435098', true);

-- Sin feriados de fábrica de por medio (mismo criterio que la 359).
delete from feriados where fecha between '2020-05-01' and '2020-08-31';
-- Y sin periodos de planilla de esos meses: la base donde corre puede traer alguno
-- (fixtures de otra sesión) y `periodos_sin_solape` haría fallar el montaje entero.
delete from periodos_planilla where daterange(fecha_ini, fecha_fin, '[]') && daterange('2020-06-01', '2020-08-31', '[]');

-- Doce personas. 1..5, 8, 9, 10, 11 y 12 cesan el 2020-06-10 (periodo de junio, que no se
-- cierra); 6 (F) cesa en julio y 7 (G) en agosto, cada una en su propio periodo.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
select ('00000000-0000-0000-0000-0000004350' || lpad(n::text, 2, '0'))::uuid, 'P' || n, 'Laboratorio',
       '00000000-0000-0000-0000-000000435000', 'test-hash', '2018-01-02', 'planilla'
from generate_series(1, 12) n;

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select ('00000000-0000-0000-0000-0000004350' || lpad(n::text, 2, '0'))::uuid, 'cayla', 1500.00, '2018-01-02'
from generate_series(1, 12) n;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000435101', '2020-08-01', '2020-08-30', 'abierto'),
  ('00000000-0000-0000-0000-000000435102', '2020-07-01', '2020-07-30', 'abierto'),
  ('00000000-0000-0000-0000-000000435103', '2020-06-01', '2020-06-30', 'abierto');

-- Diez días de 6.5 h, terminando en el cese de cada quien.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select ('00000000-0000-0000-0000-0000004350' || lpad(n::text, 2, '0'))::uuid, d::date, 6.5, 'cerrada'
from generate_series(1, 12) n,
     generate_series(
       case when n = 6 then '2020-07-01'::date when n = 7 then '2020-08-01'::date else '2020-06-01'::date end,
       case when n = 6 then '2020-07-10'::date when n = 7 then '2020-08-10'::date else '2020-06-10'::date end,
       interval '1 day') d;

update personas set estado = 'inactivo', fecha_cese = '2020-06-10'
 where id in (select ('00000000-0000-0000-0000-0000004350' || lpad(n::text, 2, '0'))::uuid from generate_series(1, 12) n where n not in (6, 7));
update personas set estado = 'inactivo', fecha_cese = '2020-07-10' where id = '00000000-0000-0000-0000-000000435006';
update personas set estado = 'inactivo', fecha_cese = '2020-08-10' where id = '00000000-0000-0000-0000-000000435007';

-- Congela la liquidación de hoy con el `pagado` desplazado: la diferencia
-- (ahora − pagado) de cada concepto queda EXACTAMENTE en lo que se pide.
create function pg_temp.congelar(
  p_persona uuid, p_dif_periodo numeric default 0, p_dif_vac numeric default 0,
  p_dif_grati numeric default 0, p_dif_cts numeric default 0
) returns void language plpgsql as $$
declare
  v_l jsonb := fn_liquidacion(p_persona, null);
begin
  insert into liquidacion_pagada (
    persona_id, version, congelada_por, nota, persona, fecha_ingreso, fecha_cese,
    monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle)
  values (
    p_persona,
    coalesce((select max(lp.version) from liquidacion_pagada lp where lp.persona_id = p_persona), 0) + 1,
    '00000000-0000-0000-0000-000000435099', 'prueba 435',
    v_l->>'persona', (v_l->>'fecha_ingreso')::date, (v_l->>'fecha_cese')::date,
    coalesce((v_l->'periodo'->>'monto')::numeric, 0)             - p_dif_periodo,
    coalesce((v_l->'vacaciones_truncas'->>'monto')::numeric, 0)  - p_dif_vac,
    coalesce((v_l->'gratificacion_trunca'->>'monto')::numeric, 0) - p_dif_grati,
    coalesce((v_l->'cts_trunca'->>'monto')::numeric, 0)          - p_dif_cts,
    (v_l->>'total')::numeric - p_dif_periodo - p_dif_vac - p_dif_grati - p_dif_cts,
    v_l);
end $$;


-- ── § 1 · Lectura: sentido, filas y huella ─────────────────────────────────
select is(
  (select count(*)::int from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  0,
  '1 · una persona que nunca se pagó no tiene estado: no hay nada que constatar');

select pg_temp.congelar('00000000-0000-0000-0000-000000435001', 0,  50,  0,   0);   -- A: a favor de la persona
select pg_temp.congelar('00000000-0000-0000-0000-000000435002', 0,   0,  0,  -30);   -- B: a favor de CAYLA
select pg_temp.congelar('00000000-0000-0000-0000-000000435003', 0,  50,  0,  -30);   -- C: mixta
select fn_liquidacion_pagar('00000000-0000-0000-0000-000000435004', 'sin diferencia');  -- D: cuadra
select pg_temp.congelar('00000000-0000-0000-0000-000000435005', 0,  50,  0,   0);   -- E: como A, luego cambia el cese

select is(
  (select sentido from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  'a_favor_persona',
  '2 · A: hoy se le daría más (ahora > pagado): el servidor lo llama a favor de la persona');

select is(
  (select jsonb_array_length(filas) from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  1,
  '3 · A: una sola fila real');

select is(
  (select (filas->0->>'concepto') || ' ' || (filas->0->>'centavos')
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  'Vacaciones truncas 5000',
  '4 · A: la fila es Vacaciones truncas, en centavos enteros (S/50.00 = 5000)');

select ok(
  (select huella ~ '^[0-9a-f]{32}$' and puede_constatar and hay_real
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '5 · A: hay huella de 32 hex, hay diferencia real y se puede constatar');

select ok(
  not exists (select 1 from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001') e,
                     jsonb_array_elements(e.filas) f where f->>'concepto' = 'TOTAL'),
  '6 · la fila TOTAL nunca entra en las filas de la huella');

select is(
  (select sentido || ' ' || (filas->0->>'centavos') from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
  'a_favor_cayla -3000',
  '7 · B: se le pagó de más (ahora < pagado): a favor de CAYLA, en negativo');

select ok(
  (select sentido = 'mixto' and puede_constatar is false and motivo_no like '%sentidos opuestos%'
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435003')),
  '8 · C: diferencias de sentido opuesto → mixta, no se puede constatar, y dice por qué');

select ok(
  (select hay_real is false and puede_constatar is false and motivo_no like 'No hay una diferencia real%'
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435004')),
  '9 · D: la liquidación cuadra → no hay diferencia real que constatar');

update personas set fecha_cese = '2020-06-11' where id = '00000000-0000-0000-0000-000000435005';
select ok(
  (select puede_constatar is false and motivo_no like '%cese actual%'
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435005')),
  '10 · E: la fecha de cese cambió → la liquidación ya no describe el cese actual (0499): no se constata');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435096', true);
select throws_like(
  $$ select * from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001') $$,
  '%ver la constancia de una liquidación%',
  '11 · quien no es admin ni líder DO no puede ni ver el estado (el mensaje es el de ESTA función, no el de fn_liquidacion_diferencias que llama por dentro)');
select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', 1, repeat('a', 32),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla cambió después del pago') $$,
  '%dejar constancia de una diferencia en una liquidación%',
  '12 · ni escribir una constancia (el mensaje es el del guardián: sin su propia guardia, la de fn_liquidacion_diferencias taparía el hueco)');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435098', true);


-- ── § 2 · El guardián rechaza lo que no debe pasar ─────────────────────────
-- Todas sobre A (a favor de la persona), salvo donde se dice.
create temp table _a as
  select version as v, huella as h from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'regla_cambio_despues', 'corto') $$,
  '%al menos 10 caracteres%',
  '13 · un motivo de menos de 10 caracteres se rechaza');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'ya_se_pago_por_fuera', null, 'una decisión que no existe en el catálogo') $$,
  '%decisión no es válida%',
  '14 · una decisión fuera del catálogo se rechaza (sin «pagada por fuera»: ese camino es «Volver a marcarla»)');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', null, 'sin decir en qué se apoya la decisión') $$,
  '%en qué te apoyas%',
  '15 · «Lo pagado era lo correcto» exige un apoyo');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'no_se_reclama', null, 'no se reclama pero la diferencia es a favor de ella') $$,
  '%a favor de la persona%',
  '16 · una diferencia a favor de la persona no se cierra con «no se reclama»');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', 99, (select h from _a),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla cambió después del pago') $$,
  '%versión nueva%',
  '17 · una versión que ya no es la última se rechaza: ábrela de nuevo');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), repeat('0', 32),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla cambió después del pago') $$,
  '%cálculo cambió mientras mirabas%',
  '18 · una huella que no es la de hoy se rechaza: lo que se vio ya no es lo que da el cálculo');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435002', 1, repeat('0', 32),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla cambió después del pago') $$,
  '%cálculo cambió mientras mirabas%',
  '19 · B: con una huella ajena se rechaza antes de mirar el sentido');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435002', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
       'pagado_es_correcto', 'regla_cambio_despues', 'a favor de CAYLA no puede ser lo pagado correcto') $$,
  '%a favor de CAYLA%',
  '20 · B (se pagó de más): «Lo pagado era lo correcto» no corresponde');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435003', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435003')),
       'pagado_es_correcto', 'regla_cambio_despues', 'una diferencia mixta no se puede cerrar') $$,
  '%sentidos opuestos%',
  '21 · C (mixta): el guardián se niega, el aviso queda abierto');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435004', 1, repeat('0', 32),
       'pagado_es_correcto', 'regla_cambio_despues', 'no hay diferencia que constatar aquí') $$,
  '%Ya no hay una diferencia real%',
  '22 · D (cuadra): no hay nada que constatar');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435005', 1, repeat('0', 32),
       'pagado_es_correcto', 'regla_cambio_despues', 'el cese cambió, esto no se constata') $$,
  '%cese actual%',
  '23 · E (cese distinto): se manda a anular y liquidar de nuevo, no a constatar');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla cambió después del pago',
       '99999999-9999-9999-9999-999999999999') $$,
  '%Otra persona ya registró%',
  '24 · mandar un «reemplaza» que no es la cabeza de la cadena se rechaza (compare-and-swap)');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'retirada', null, 'retirar sin que haya nada que retirar') $$,
  '%No hay una constancia vigente que retirar%',
  '25 · no se puede retirar lo que no existe');


-- ── § 3 · Constatar, corregir, retirar ─────────────────────────────────────
select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones truncas cambió después del pago') $$,
  '26 · A: se deja constancia de que lo pagado era lo correcto');

select ok(
  (select vigente->>'decision' = 'pagado_es_correcto' and vigente->>'por' = 'Admin435 Laboratorio'
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '27 · el estado la muestra vigente, con quién la hizo (lo pone el servidor)');

select ok(
  (select count(*) = 1 and bool_and(valor_nuevo like 'pagado_es_correcto · versión 1 · huella %')
     from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000435001'
      and campo_modificado = 'liquidacion_diferencia_constatada')
  and not exists (select 1 from correcciones_auditoria
                   where campo_modificado = 'liquidacion_diferencia_constatada'
                     and (motivo like '%vacaciones truncas cambió%' or valor_nuevo like '%vacaciones truncas cambió%')),
  '28 · quedó UN rastro en la auditoría, con decisión y huella corta — y sin el texto libre del motivo');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones truncas cambió después del pago') $$,
  '%Otra persona ya registró%',
  '29 · el doble clic (o un segundo revisor) se rechaza con un mensaje, sin duplicar');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'confirmado_por_contador_o_laboralista', 'lo confirmó el contador por escrito el mismo día',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001'))) $$,
  '30 · corregir = escribir otra encima, apuntando a la que se vio');

select is(
  (select count(*)::int from liquidacion_constancias c
    where c.persona_id = '00000000-0000-0000-0000-000000435001'
      and not exists (select 1 from liquidacion_constancias r where r.reemplaza_id = c.id)),
  1,
  '31 · aunque ya hay dos filas, hay UNA sola vigente (la cabeza de la cadena)');

select is(
  (select vigente->>'apoyo' from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  'confirmado_por_contador_o_laboralista',
  '32 · la vigente es la corrección, no la primera');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'retirada', null, 'se dejó por error: falta confirmarlo con el laboralista',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001'))) $$,
  '33 · retirar una constancia puesta por error');

select ok(
  (select vigente is null and puede_constatar and cabeza_id is not null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '34 · retirar REABRE el aviso: ya no hay vigente y se puede volver a constatar');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'regla_cambio_despues', 'ya confirmado: la regla de vacaciones cambió después del pago',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001'))) $$,
  '35 · después de retirar se puede constatar de nuevo, continuando la cadena');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435002', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
       'no_se_reclama', null, 'se le pagó de más y CAYLA decide no reclamarlo') $$,
  '36 · B (a favor de CAYLA): «no se reclama» sí corresponde');

select ok(
  (select vigente->>'decision' = 'no_se_reclama' and vigente->>'apoyo' is null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
  '37 · y no lleva apoyo: el apoyo es solo de «lo pagado era lo correcto»');


-- ── § 4 · «Vuelve si el cálculo cambia» (y vuelve a valer si el cálculo vuelve) ──
create temp table _h as
  select huella as h from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001');

update jornadas set horas_trabajadas = 8.0
 where persona_id = '00000000-0000-0000-0000-000000435001' and fecha = '2020-06-05';

select ok(
  (select vigente is null and anterior is not null and huella <> (select h from _h)
          and jsonb_array_length(filas) = 2
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '38 · el cálculo cambió (un marcaje corregido): la constancia ya no vale, la huella es otra y aparece la anterior');

select ok(
  (select anterior->>'decision' = 'pagado_es_correcto'
          and jsonb_array_length(anterior->'diferencias') = 1
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '39 · la constancia anterior trae lo que se vio entonces (una fila), para mostrar las dos cifras lado a lado');

select ok(
  (select anterior ?& array['id','decision','apoyo','motivo','por','cuando','diferencias']
          and anterior->>'cuando' is not null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '40 · «anterior» trae las mismas llaves que «vigente», para pintar las dos cifras lado a lado');

update jornadas set horas_trabajadas = 6.5
 where persona_id = '00000000-0000-0000-0000-000000435001' and fecha = '2020-06-05';

select ok(
  (select vigente is not null and huella = (select h from _h) and anterior is null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '41 · el cálculo VOLVIÓ a lo que era: la constancia vuelve a valer (es la misma situación que se miró) y ya no se muestra «anterior»');


-- ── § 5 · El cierre de mes: no caduca la constancia; y el caso conocido ────
-- G: la diferencia real está en Vacaciones; el descuento del cierre mueve
-- «Sueldo del periodo» (que pasa a esperada_por_cierre) y el TOTAL, pero no la
-- diferencia real. La constancia tiene que seguir valiendo.
select pg_temp.congelar('00000000-0000-0000-0000-000000435007', 0, 50, 0, 0);

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435007', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435007')),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones cambió después del pago') $$,
  '42 · G: se deja constancia de la diferencia en Vacaciones');

select lives_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-000000435101',
       '00000000-0000-0000-0000-000000435007', 'descuento', 'Ya le pague aparte (liquidacion)',
       (select monto_periodo from liquidacion_pagada
         where persona_id = '00000000-0000-0000-0000-000000435007' order by version desc limit 1)) $$,
  '43 · G: se registra el descuento que el freno del cierre exige');

select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000435101', true) $$,
  '44 · G: el mes se cierra');

select is(
  (select origen from fn_liquidacion_diferencias('00000000-0000-0000-0000-000000435007')
    where concepto = 'Sueldo del periodo'),
  'esperada_por_cierre',
  '45 · G: la diferencia del sueldo del periodo ya es la esperada por el cierre (no entra en la huella)');

select ok(
  (select vigente is not null and vigente->>'decision' = 'pagado_es_correcto'
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435007')),
  '46 · G: la constancia SIGUE VIGENTE después del cierre de mes — sin la fila TOTAL en la huella no caduca cada fin de mes');

-- F: el caso conocido. La diferencia real está en el propio «Sueldo del periodo».
select fn_liquidacion_pagar('00000000-0000-0000-0000-000000435006', 'pago normal');
update jornadas set horas_trabajadas = 8.0
 where persona_id = '00000000-0000-0000-0000-000000435006' and fecha = '2020-07-05';

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435006', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435006')),
       'pagado_es_correcto', 'dato_de_hoy_mal_cargado', 'el marcaje corregido de ese día no estaba cargado al pagar') $$,
  '47 · F: se deja constancia de una diferencia real en el propio Sueldo del periodo');

select lives_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-000000435102',
       '00000000-0000-0000-0000-000000435006', 'descuento', 'Ya le pague aparte (liquidacion)',
       (select monto_periodo from liquidacion_pagada
         where persona_id = '00000000-0000-0000-0000-000000435006' order by version desc limit 1)) $$,
  '48 · F: se registra el descuento del cierre');

-- La ventana: el descuento ya está registrado y el mes sigue abierto. La fila del
-- sueldo es Δ − D y puede cambiar de signo: no mide la diferencia real.
select ok(
  (select hay_real and puede_constatar is false and motivo_no like '%descuento de cierre%' and vigente is null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435006')),
  '49 · F: con el descuento registrado y el mes todavía abierto la fila del sueldo no mide la diferencia real: no se puede constatar, y el estado dice por qué');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435006', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435006')),
       'no_se_reclama', null, 'devolución sobre una cifra que nunca existió') $$,
  '%descuento de cierre%',
  '50 · F: y el guardián tampoco deja registrar «devolución» sobre esa cifra (sería −488 «a favor de CAYLA» cuando lo real era a favor de la persona)');

select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000435102', true) $$,
  '51 · F: el mes se cierra');

select ok(
  (select hay_real is false and vigente is null and anterior is null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435006')),
  '52 · F: al cerrar el mes la fila del sueldo pasa a «esperada por el cierre» y el aviso desaparece solo (la planilla la paga como devengado)');

select is(
  (select count(*)::int from liquidacion_constancias where persona_id = '00000000-0000-0000-0000-000000435006'),
  1,
  '53 · F: la constancia que se había puesto antes del descuento sigue guardada, como historial');


-- ── § 6 · Una versión superada o anulada es inerte ─────────────────────────
select pg_temp.congelar('00000000-0000-0000-0000-000000435008', 0, 50, 0, 0);
select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435008', 1,
  (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
  'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones cambió después del pago');
select fn_liquidacion_pagar('00000000-0000-0000-0000-000000435008', 'vuelvo a marcarla con el cálculo de hoy');

select ok(
  (select version = 2 and hay_real is false and vigente is null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
  '54 · H: al volver a marcarla pagada (versión 2) el estado habla de la versión nueva: nada vigente, sin diferencia');

select is(
  (select count(*)::int from liquidacion_constancias where persona_id = '00000000-0000-0000-0000-000000435008'),
  1,
  '55 · H: la constancia de la versión 1 sigue guardada, intacta e inerte');

select pg_temp.congelar('00000000-0000-0000-0000-000000435009', 0, 50, 0, 0);
select fn_liquidacion_anular('00000000-0000-0000-0000-000000435009', 'marcada por error en la prueba');

select is(
  (select count(*)::int from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435009')),
  0,
  '56 · I: con la última versión anulada no hay estado');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435009', 1, repeat('0', 32),
       'pagado_es_correcto', 'regla_cambio_despues', 'sobre una liquidación anulada no se constata') $$,
  '%no tiene una liquidación pagada vigente%',
  '57 · I: tampoco se puede constatar sobre una liquidación anulada');


-- ── § 7 · Estados imposibles: insert directo, saltándose la función ────────
-- Como dueño de la tabla. Si la función fuera la única defensa, esto pasaría.
create temp table _base as
  select c.persona_id, c.version, c.huella, c.id
    from liquidacion_constancias c
   where c.persona_id = '00000000-0000-0000-0000-000000435002' limit 1;

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435003', 1, repeat('1', 32), 'a_favor_cayla', 'no_se_reclama', null,
             'corto', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23514', null,
  '58 · un motivo corto no entra ni saltándose la función (CHECK)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435003', 1, repeat('1', 32), 'a_favor_cayla', 'pagado_es_correcto',
             'regla_cambio_despues', 'un motivo largo y razonable', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23514', null,
  '59 · una decisión contraria al sentido no entra (CHECK)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435003', 1, repeat('1', 32), 'a_favor_persona', 'pagado_es_correcto',
             null, 'un motivo largo y razonable', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23514', null,
  '60 · «Lo pagado era lo correcto» sin apoyo no entra (CHECK)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435003', 1, repeat('1', 32), 'a_favor_persona', 'retirada',
             null, 'un motivo largo y razonable', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23514', null,
  '61 · una retirada sin nada que reemplazar no entra (CHECK)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435003', 99, repeat('1', 32), 'a_favor_cayla', 'no_se_reclama',
             null, 'un motivo largo y razonable', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23503', null,
  '62 · una constancia sobre una versión que no existe no entra (FK compuesta)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     select persona_id, version, huella, 'a_favor_cayla', 'no_se_reclama', null,
            'una segunda raíz de la misma diferencia', '[{"x":1}]', '00000000-0000-0000-0000-000000435099' from _base $$,
  '23505', null,
  '63 · dos raíces para la misma (persona, versión, huella) no caben: una sola vigente (índice único)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, reemplaza_id, constatada_por)
     select persona_id, version, repeat('2', 32), 'a_favor_cayla', 'no_se_reclama', null,
            'una cadena que mezcla otra huella', '[{"x":1}]', id, '00000000-0000-0000-0000-000000435099' from _base $$,
  '23503', null,
  '64 · una cadena no puede mezclar huellas distintas (FK compuesta autorreferida)');

select throws_ok(
  $$ update liquidacion_constancias set motivo = 'reescribiendo la historia a escondidas'
      where persona_id = '00000000-0000-0000-0000-000000435002' $$,
  'P0001', null,
  '65 · una constancia no se edita (trigger)');

select throws_ok(
  $$ delete from liquidacion_constancias where persona_id = '00000000-0000-0000-0000-000000435002' $$,
  'P0001', null,
  '66 · ni se borra (trigger)');


-- ── § 8 · La tabla está cerrada para escribir; leer, solo admin y líder DO ─
select ok(
  not has_table_privilege('authenticated', 'liquidacion_constancias', 'insert')
  and not has_table_privilege('authenticated', 'liquidacion_constancias', 'update')
  and not has_table_privilege('authenticated', 'liquidacion_constancias', 'delete')
  and not has_table_privilege('authenticated', 'liquidacion_constancias', 'truncate')
  and has_table_privilege('authenticated', 'liquidacion_constancias', 'select')
  and not has_table_privilege('anon', 'liquidacion_constancias', 'select'),
  '67 · authenticated solo lee (ni insert, ni update, ni delete, ni truncate) y anon ni eso: cerrada por revoke, no por ausencia de grant');

grant insert on liquidacion_constancias to authenticated;
select is(
  (not has_table_privilege('authenticated', 'liquidacion_constancias', 'insert')
   and not has_table_privilege('authenticated', 'liquidacion_constancias', 'update')
   and not has_table_privilege('authenticated', 'liquidacion_constancias', 'delete')
   and not has_table_privilege('authenticated', 'liquidacion_constancias', 'truncate')
   and has_table_privilege('authenticated', 'liquidacion_constancias', 'select')
   and not has_table_privilege('anon', 'liquidacion_constancias', 'select')),
  false,
  '68 · CONTROL: reabriendo el hueco a propósito, la MISMA expresión de la aserción anterior da false (la prueba puede ponerse en rojo)');
revoke insert on liquidacion_constancias from authenticated;

select ok(
  not has_function_privilege('anon', 'fn_liquidacion_constancia_estado(uuid)', 'execute')
  and has_function_privilege('authenticated', 'fn_liquidacion_constancia_estado(uuid)', 'execute')
  and not has_function_privilege('anon', 'fn_liquidacion_constatar(uuid,int,text,text,text,text,uuid)', 'execute')
  and has_function_privilege('authenticated', 'fn_liquidacion_constatar(uuid,int,text,text,text,text,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'fn_liquidacion_huella(jsonb)', 'execute'),
  '69 · las dos funciones se ejecutan solo con sesión; la de la huella ni eso (la llaman las otras, que son definer)');


-- Lectura por RLS: la ve quien es admin o líder DO, y nadie más. Se mide con el
-- rol `authenticated` de verdad (la prueba corre como dueño y se saltaría RLS).
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435098', true);
create temp table _rls_admin as select count(*)::int as n from liquidacion_constancias;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435096', true);
create temp table _rls_integrante as select count(*)::int as n from liquidacion_constancias;
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435098', true);

select ok(
  (select n from _rls_admin) > 0,
  '70 · un admin lee las constancias (RLS con el rol authenticated de verdad)');

select is(
  (select n from _rls_integrante),
  0,
  '71 · un integrante no ve ninguna: ni las constancias ni lo que decidió DO sobre un pago');


-- ── § 9 · La huella: canónica ──────────────────────────────────────────────
select is(
  fn_liquidacion_huella('[{"concepto":"CTS trunca","centavos":-3000},{"concepto":"Vacaciones truncas","centavos":5000}]'),
  fn_liquidacion_huella('[{"concepto":"Vacaciones truncas","centavos":5000},{"concepto":"CTS trunca","centavos":-3000}]'),
  '72 · el orden en que llegan las filas no cambia la huella (se ordena por concepto, en collation C)');

select isnt(
  fn_liquidacion_huella('[{"concepto":"CTS trunca","centavos":-3000}]'),
  fn_liquidacion_huella('[{"concepto":"CTS trunca","centavos":-3001}]'),
  '73 · un solo centavo de diferencia cambia la huella');

-- ── § 10 · Lo que encontró la revisión independiente (cobertura que faltaba) ──
-- Escrito por un revisor que ejecutó 35 mutaciones nuevas de la migración: la prueba de
-- entonces cazaba 6 y dejaba pasar 29. Con estas, las 29 caen.
-- X1a · la constancia de la v1 no aparece ni como vigente ni como «anterior» una vez que existe la v2
select ok(
  (select version = 2 and vigente is null and anterior is null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
  '74 · X1a · tras volver a marcarla pagada (v2) la constancia de la v1 no sale ni como vigente ni como «anterior»');
-- X1 · la constancia de una version NO vale para otra version aunque la huella sea identica
select pg_temp.congelar('00000000-0000-0000-0000-000000435008', 0, 50, 0, 0);   -- v3: MISMA diferencia (+50 vacaciones) que la constancia de v1
select ok(
  (select version = 3 and hay_real and vigente is null from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
  '75 · X1 · v3 con la misma diferencia que v1: la constancia de v1 NO la cierra (vigente nulo)');
select ok(
  (select anterior is null from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
  '76 · X1 · y la constancia de v1 tampoco aparece como «anterior» de v3');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435008', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
       'pagado_es_correcto', 'regla_cambio_despues', 'pantalla abierta sobre la version 1 cuando ya hay la 3') $$,
  '%versión nueva%',
  '77 · X16 · la pantalla miraba la v1 y ya hay v3 (el caso real de «Volver a marcarla»): se rechaza aunque la huella coincida');

-- X3/X4/X5 · rechazos que hoy no se prueban (sobre H en v3, todavia sin constancia)
select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435008', 3,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
       'devolucion_acordada', null, 'devolucion sobre una diferencia a favor de ella') $$,
  '%no se puede cerrar con una decisión%',
  '78 · X3 · «devolucion_acordada» sobre una diferencia a favor de la persona se rechaza');
select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435008', 3,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
       'pagado_es_correcto', 'otra_cosa', 'apoyo inventado que no esta en el catalogo') $$,
  '%en qué te apoyas%',
  '79 · X4 · un apoyo fuera del catálogo se rechaza con el mensaje amable (no con el CHECK crudo)');
select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435008', 3,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
       'pagado_es_correcto', 'regla_cambio_despues', '  corto   ') $$,
  '%al menos 10 caracteres%',
  '80 · X5 · diez caracteres de los cuales cinco son espacios: se rechaza con el mensaje amable');
select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435008', 3,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
       'pagado_es_correcto', 'regla_cambio_despues', 'nueve car') $$,
  '%al menos 10 caracteres%',
  '81 · X5 · nueve caracteres exactos: se rechaza con el mensaje amable (frontera inferior)');

-- X2 · el guardian invocado con el rol authenticated DE VERDAD (no como dueño)
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435098', true);
create temp table _x2 (res text);
do $x$ declare r jsonb; begin
  r := fn_liquidacion_constatar('00000000-0000-0000-0000-000000435008', 3,
    (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
    'pagado_es_correcto', 'regla_cambio_despues', 'diez chars');
  insert into _x2 values (case when r->>'decision' = 'pagado_es_correcto' and (r->>'version')::int = 3
       and (r->>'id') ~ '^[0-9a-f-]{36}$' and r->>'constatada_at' is not null then 'ok'
       else 'resultado inesperado: ' || r::text end);
exception when others then insert into _x2 values (sqlerrm);
end $x$;
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435098', true);
select is((select res from _x2), 'ok',
  '82 · X2 · un admin con el rol authenticated de verdad puede constatar, diez caracteres exactos bastan y devuelve {id, decision, version, constatada_at}');

-- X3 · «devolucion_acordada» (la cuarta decision, hoy sin ninguna cobertura)
select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435002', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
       'devolucion_acordada', null, 'se acordo por escrito la devolucion en cuotas',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002'))) $$,
  '83 · X3 · B (a favor de CAYLA): «devolución acordada» se puede dejar');
select is(
  (select vigente->>'decision' from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
  'devolucion_acordada',
  '84 · X3 · y queda como la vigente');

-- X6 · retirar dos veces seguidas
select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435002', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
       'retirada', null, 'se dejo por error en la prueba',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002'))) $$,
  '85 · X6 · B: se retira');
select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435002', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
       'retirada', null, 'retirar lo que ya esta retirado',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002'))) $$,
  '%No hay una constancia vigente que retirar%',
  '86 · X6 · retirar lo que ya está retirado se rechaza (no encadena retiradas)');

-- X9 · una retirada no es «la ultima cifra que valio»
update jornadas set horas_trabajadas = 8.0
 where persona_id = '00000000-0000-0000-0000-000000435002' and fecha = '2020-06-05';
select ok(
  (select vigente is null and anterior is null and hay_real
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
  '87 · X9 · B retirada y luego el cálculo cambia: «anterior» no muestra una retirada');

-- X10 · si la constancia vigente es la unica, no hay «anterior»
select ok(
  (select vigente is not null and anterior is null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435007')),
  '88 · X10 · G tiene su constancia vigente y ningún «anterior» (la vigente no es su propia sombra)');

-- X7 · la huella con valor de oro: cambiarla en silencio reabre TODAS las constancias en produccion
select is(
  fn_liquidacion_huella('[{"concepto":"Vacaciones truncas","centavos":5000}]'),
  md5('Vacaciones truncas=5000'),
  '89 · X7 · valor de oro: md5 de «concepto=centavos» (cambiar la fórmula reabriría todas las constancias)');
select is(
  fn_liquidacion_huella('[{"concepto":"a","centavos":2},{"concepto":"B","centavos":1}]'),
  md5('B=1|a=2'),
  '90 · X7 · valor de oro: orden en collation C (mayúsculas antes que minúsculas), separador «|»');

-- X8 · la auditoria dice QUIEN y desde QUE decision
select ok(
  (select count(*) = 4 and bool_and(corregido_por = '00000000-0000-0000-0000-000000435099')
          and count(*) filter (where valor_anterior is not null) = 3
     from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000435001'
      and campo_modificado = 'liquidacion_diferencia_constatada'),
  '91 · X8 · el rastro de A: 4 filas, todas a nombre de quien constató, 3 con la decisión anterior');

-- X11 · el cerrojo de turnos esta tomado (pg_locks, misma transaccion)
select ok(
  (select count(*) from pg_locks where locktype = 'advisory' and pid = pg_backend_pid() and objsubid = 1) >= 1,
  '92 · X11 · el guardián tomó el cerrojo advisory de la persona (dos revisores a la vez se turnan)');

-- X12/X13 · la cadena no puede mezclar PERSONAS ni VERSIONES (hoy solo se prueba mezclar huellas)
select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, reemplaza_id, constatada_por)
     select '00000000-0000-0000-0000-000000435008', 1, c7.huella, 'a_favor_persona', 'pagado_es_correcto', 'regla_cambio_despues',
            'una cadena que mezcla otra persona', '[{"x":1}]', c7.id, '00000000-0000-0000-0000-000000435099'
       from liquidacion_constancias c7
      where c7.persona_id = '00000000-0000-0000-0000-000000435007' and c7.version = 1 and c7.reemplaza_id is null $$,
  '23503', null,
  '93 · X12 · una cadena no puede mezclar personas distintas aunque la huella coincida (FK compuesta)');
select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, reemplaza_id, constatada_por)
     select c8.persona_id, 3, c8.huella, 'a_favor_persona', 'pagado_es_correcto', 'regla_cambio_despues',
            'una cadena que mezcla otra version', '[{"x":1}]', c8.id, '00000000-0000-0000-0000-000000435099'
       from liquidacion_constancias c8
      where c8.persona_id = '00000000-0000-0000-0000-000000435008' and c8.version = 1 $$,
  '23503', null,
  '94 · X13 · una cadena no puede mezclar versiones distintas aunque la huella coincida (FK compuesta)');

-- X14 · las dos funciones definer y la de la huella fijan search_path; las dos definer son definer
select ok(
  (select bool_and(proconfig is not null and 'search_path=public' = any(proconfig)) and count(*) filter (where prosecdef) = 2
     from pg_proc
    where oid in ('fn_liquidacion_huella(jsonb)'::regprocedure, 'fn_liquidacion_constancia_estado(uuid)'::regprocedure,
                  'fn_liquidacion_constatar(uuid,int,text,text,text,text,uuid)'::regprocedure)),
  '95 · X14 · estado y constatar son SECURITY DEFINER y las tres fijan search_path');

-- X15 · una constancia se reemplaza como mucho UNA vez (el otro de los dos indices unicos)
select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, reemplaza_id, constatada_por)
     select c.persona_id, c.version, c.huella, 'a_favor_persona', 'pagado_es_correcto', 'regla_cambio_despues',
            'una segunda correccion de la misma constancia', '[{"x":1}]', c.id, '00000000-0000-0000-0000-000000435099'
       from liquidacion_constancias c
      where c.persona_id = '00000000-0000-0000-0000-000000435001' and c.version = 1 and c.reemplaza_id is null $$,
  '23505', null,
  '96 · X15 · dos constancias no pueden reemplazar a la misma: la cadena no se bifurca (índice único)');

-- X17 · huella nula: «lo que viste» no puede ser NADA (el guardian es null-safe en la huella)
select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435008', 3, NULL,
       'pagado_es_correcto', 'regla_cambio_despues', 'huella nula no debe pasar') $$,
  '%cálculo cambió%',
  '97 · X17 · una huella NULL se rechaza (con <> en vez de IS DISTINCT FROM el NULL pasaría como «coincide»)');

-- X18 · los dos roles de verdad: líder DO puede (lee por RLS y constata); líder de equipo (supervisor_sede) no
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000435a01', 'LiderDO435', 'Laboratorio', '00000000-0000-0000-0000-000000435000', 'lider_do',
   'test-hash', '00000000-0000-0000-0000-000000435a11', '2020-01-01'),
  ('00000000-0000-0000-0000-000000435a02', 'LiderEquipo435', 'Laboratorio', '00000000-0000-0000-0000-000000435000', 'supervisor_sede',
   'test-hash', '00000000-0000-0000-0000-000000435a12', '2020-01-01');
set session_replication_role = origin;
select pg_temp.congelar('00000000-0000-0000-0000-000000435009', 0, 80, 0, 0);   -- v3: otra diferencia (+80) para que haya algo que constatar
create temp table _x18 (quien text, filas_rls int, res text);
grant all on _x18 to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435a11', true);
do $x$ declare r jsonb; n int; begin
  select count(*) into n from liquidacion_constancias;
  begin
    r := fn_liquidacion_constatar('00000000-0000-0000-0000-000000435009', 3,
      (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435009')),
      'pagado_es_correcto', 'confirmado_por_contador_o_laboralista', 'lo confirmó la laboralista');
    insert into _x18 values ('lider_do', n, case when r->>'decision' = 'pagado_es_correcto' then 'ok' else 'raro' end);
  exception when others then insert into _x18 values ('lider_do', n, sqlerrm); end;
end $x$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435a12', true);
do $x$ declare n int; begin
  select count(*) into n from liquidacion_constancias;
  begin
    perform fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435009');
    insert into _x18 values ('supervisor_estado', n, 'pudo ver el estado');
  exception when others then insert into _x18 values ('supervisor_estado', n, sqlerrm); end;
  begin
    perform fn_liquidacion_constatar('00000000-0000-0000-0000-000000435009', 3, repeat('0', 32),
      'pagado_es_correcto', 'regla_cambio_despues', 'un líder de equipo no puede constatar');
    insert into _x18 values ('supervisor_guardian', n, 'pudo constatar');
  exception when others then insert into _x18 values ('supervisor_guardian', n, sqlerrm); end;
end $x$;
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000435098', true);
select ok(
  (select filas_rls > 0 and res = 'ok' from _x18 where quien = 'lider_do'),
  '98 · X18 · un líder DO lee las constancias por RLS y puede constatar (con el rol authenticated de verdad)');
select ok(
  (select filas_rls = 0 and res like '%ver la constancia de una liquidación%' from _x18 where quien = 'supervisor_estado'),
  '99 · X18 · un líder de equipo (supervisor_sede) no ve ninguna constancia ni puede abrir el estado (mensaje del estado, no el de fn_liquidacion_diferencias)');
select ok(
  (select res like '%dejar constancia de una diferencia en una liquidación%' from _x18 where quien = 'supervisor_guardian'),
  '100 · X18 · y tampoco puede constatar (mensaje del guardián, no el del estado que llama por dentro)');

-- X19 · el contrato JSON que la pantalla va a leer: llaves de «vigente» y de «anterior»
select ok(
  (select vigente ?& array['id','decision','apoyo','motivo','por','cuando','diferencias']
          and vigente->>'cuando' is not null and vigente->>'por' = 'Admin435 Laboratorio'
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435007')),
  '101 · X19 · «vigente» trae id, decision, apoyo, motivo, por, cuando y diferencias (con quién y cuándo)');
-- X20 · las filas: pagado y ahora no pueden ir intercambiados (la pantalla pinta pagado | ahora | diferencia)
select ok(
  (select (filas->0->>'pagado')::numeric + 50 = (filas->0->>'ahora')::numeric and (filas->0->>'diferencia')::numeric = 50
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '102 · X20 · A: ahora − pagado = diferencia = +50.00 (las columnas no están cruzadas)');


-- ── § 11 · Los arreglos de esta ronda ──────────────────────────────────────
select pg_temp.congelar('00000000-0000-0000-0000-000000435010', 0, 50, 0, 0);   -- 10: se reactiva
select pg_temp.congelar('00000000-0000-0000-0000-000000435011', 0, 50, 0, 0);   -- 11: una constancia de otra fórmula de huella
-- 12: A → B → A (más abajo)

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435010', NULL, (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435010')),
       'pagado_es_correcto', 'regla_cambio_despues', 'una versión que no se manda no es la que se vio') $$,
  '%versión nueva%',
  '103 · una versión NULL se rechaza (con <> el NULL pasaba como «coincide»)');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435010', 1, (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435010')),
       'pagado_es_correcto', 'regla_cambio_despues', E'\n\n\n\n\n\n\n\n\n\n') $$,
  '%al menos 10 caracteres%',
  '104 · diez saltos de línea no son diez caracteres de motivo (la función)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435010', 1, repeat('7', 32), 'a_favor_persona', 'pagado_es_correcto', 'regla_cambio_despues',
             E'\t\t\t\t\t\t\t\t\t\t', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23514', null,
  '105 · ni diez tabuladores (el CHECK de la tabla, saltándose la función)');

-- La persona se reactiva con una constancia vigente: no se puede registrar otra,
-- pero quien se equivocó SÍ puede retirar la que puso.
select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435010', 1, (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435010')),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones cambió después del pago') $$,
  '106 · P10: se deja constancia');

update personas set estado = 'activo', fecha_cese = null where id = '00000000-0000-0000-0000-000000435010';

select ok(
  (select vigente is not null and puede_constatar is false and motivo_no like '%ya no figura como cesada%'
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435010')),
  '107 · P10 reactivada: la constancia sigue valiendo (las cifras no cambiaron) pero no se puede registrar otra, y el motivo dice «se reactivó», no «cambió la fecha»');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435010', 1, (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435010')),
       'pagado_es_correcto', 'confirmado_por_contador_o_laboralista', 'corregir cuando ya no figura como cesada',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435010'))) $$,
  '%ya no figura como cesada%',
  '108 · P10: registrar otra se rechaza');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435010', 1, (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435010')),
       'retirada', null, 'se puso por error: la persona ya se había reactivado',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435010'))) $$,
  '109 · P10: pero RETIRAR sí se puede (quien se equivocó tiene que poder reabrir el aviso)');

-- A → B → A: con una constancia vigente NO se devuelve «anterior», porque podría ser
-- más nueva que ella y las dos se contradirían en pantalla.
select pg_temp.congelar('00000000-0000-0000-0000-000000435012', 0, 50, 0, 0);
select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435012', 1, (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435012')),
  'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones cambió después del pago');
update jornadas set horas_trabajadas = 8.0 where persona_id = '00000000-0000-0000-0000-000000435012' and fecha = '2020-06-05';
select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435012', 1, (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435012')),
  'pagado_es_correcto', 'dato_de_hoy_mal_cargado', 'con el marcaje corregido el dato de hoy era otro');
update jornadas set horas_trabajadas = 6.5 where persona_id = '00000000-0000-0000-0000-000000435012' and fecha = '2020-06-05';

select ok(
  (select vigente->>'apoyo' = 'regla_cambio_despues' from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435012')),
  '110 · P12 (A→B→A): el cálculo volvió a lo de la primera constancia, y esa es la vigente');

select ok(
  (select anterior is null from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435012')),
  '111 · P12 (A→B→A): y NO se muestra «anterior» (la del medio es más nueva y se contradiría con la vigente)');

-- La fórmula de la huella.
select is(
  (select huella_formula from liquidacion_constancias where persona_id = '00000000-0000-0000-0000-000000435010' limit 1),
  1::smallint,
  '112 · la constancia guarda con qué fórmula se calculó su huella (hoy 1)');

insert into liquidacion_constancias (persona_id, version, huella, huella_formula, sentido, decision, apoyo, motivo, diferencias, constatada_por)
select '00000000-0000-0000-0000-000000435011', 1, e.huella, 2, 'a_favor_persona', 'pagado_es_correcto', 'regla_cambio_despues',
       'constancia calculada con una fórmula futura', e.filas, '00000000-0000-0000-0000-000000435099'
  from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435011') e;

select ok(
  (select vigente is null and cabeza_id is null and puede_constatar from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435011')),
  '113 · una constancia de OTRA fórmula de huella no cierra el aviso: queda inerte aunque el md5 coincida');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435011', 1, (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435011')),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones cambió después del pago') $$,
  '114 · y se puede constatar con la fórmula vigente, al lado de la inerte');

select is(
  (select count(*)::int from liquidacion_constancias where persona_id = '00000000-0000-0000-0000-000000435011'),
  2,
  '115 · P11: las dos conviven (el índice de raíz única incluye la fórmula)');

-- La secuencia de `orden` y el TRUNCATE.
select ok(
  not has_sequence_privilege('authenticated', 'liquidacion_constancias_orden_seq', 'usage')
  and not has_sequence_privilege('authenticated', 'liquidacion_constancias_orden_seq', 'update')
  and not has_sequence_privilege('anon', 'liquidacion_constancias_orden_seq', 'usage'),
  '116 · ninguna sesión de usuario puede mover la secuencia de orden');

grant usage on sequence liquidacion_constancias_orden_seq to authenticated;
select ok(
  has_sequence_privilege('authenticated', 'liquidacion_constancias_orden_seq', 'usage'),
  '117 · CONTROL: reabriendo el hueco a propósito, la aserción anterior habría fallado');
revoke usage on sequence liquidacion_constancias_orden_seq from authenticated;

select throws_like(
  $$ truncate liquidacion_constancias $$,
  '%ni se vacía%',
  '118 · ni el dueño puede vaciar el libro (trigger de TRUNCATE)');

select * from finish();
rollback;
