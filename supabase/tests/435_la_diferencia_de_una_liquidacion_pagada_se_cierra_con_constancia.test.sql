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
select plan(70);

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

-- Nueve personas. 1..5, 8 y 9 cesan el 2020-06-10 (periodo de junio, que no se
-- cierra); 6 (F) cesa en julio y 7 (G) en agosto, cada una en su propio periodo.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
select ('00000000-0000-0000-0000-00000043500' || n)::uuid, 'P' || n, 'Laboratorio',
       '00000000-0000-0000-0000-000000435000', 'test-hash', '2018-01-02', 'planilla'
from generate_series(1, 9) n;

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select ('00000000-0000-0000-0000-00000043500' || n)::uuid, 'cayla', 1500.00, '2018-01-02'
from generate_series(1, 9) n;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000435101', '2020-08-01', '2020-08-30', 'abierto'),
  ('00000000-0000-0000-0000-000000435102', '2020-07-01', '2020-07-30', 'abierto'),
  ('00000000-0000-0000-0000-000000435103', '2020-06-01', '2020-06-30', 'abierto');

-- Diez días de 6.5 h, terminando en el cese de cada quien.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select ('00000000-0000-0000-0000-00000043500' || n)::uuid, d::date, 6.5, 'cerrada'
from generate_series(1, 9) n,
     generate_series(
       case when n = 6 then '2020-07-01'::date when n = 7 then '2020-08-01'::date else '2020-06-01'::date end,
       case when n = 6 then '2020-07-10'::date when n = 7 then '2020-08-10'::date else '2020-06-10'::date end,
       interval '1 day') d;

update personas set estado = 'inactivo', fecha_cese = '2020-06-10'
 where id in (select ('00000000-0000-0000-0000-00000043500' || n)::uuid from generate_series(1, 9) n where n not in (6, 7));
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

select is(
  (select count(*)::int from liquidacion_constancias where persona_id = '00000000-0000-0000-0000-000000435001'),
  0,
  '26 · ninguno de esos rechazos dejó una fila');


-- ── § 3 · Constatar, corregir, retirar ─────────────────────────────────────
select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones truncas cambió después del pago') $$,
  '27 · A: se deja constancia de que lo pagado era lo correcto');

select ok(
  (select vigente->>'decision' = 'pagado_es_correcto' and vigente->>'por' = 'Admin435 Laboratorio'
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '28 · el estado la muestra vigente, con quién la hizo (lo pone el servidor)');

select ok(
  (select count(*) = 1 and bool_and(valor_nuevo like 'pagado_es_correcto · versión 1 · huella %')
     from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000435001'
      and campo_modificado = 'liquidacion_diferencia_constatada')
  and not exists (select 1 from correcciones_auditoria
                   where campo_modificado = 'liquidacion_diferencia_constatada'
                     and (motivo like '%vacaciones truncas cambió%' or valor_nuevo like '%vacaciones truncas cambió%')),
  '29 · quedó UN rastro en la auditoría, con decisión y huella corta — y sin el texto libre del motivo');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones truncas cambió después del pago') $$,
  '%Otra persona ya registró%',
  '30 · el doble clic (o un segundo revisor) se rechaza con un mensaje, sin duplicar');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'confirmado_por_contador_o_laboralista', 'lo confirmó el contador por escrito el mismo día',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001'))) $$,
  '31 · corregir = escribir otra encima, apuntando a la que se vio');

select is(
  (select count(*)::int from liquidacion_constancias c
    where c.persona_id = '00000000-0000-0000-0000-000000435001'
      and not exists (select 1 from liquidacion_constancias r where r.reemplaza_id = c.id)),
  1,
  '32 · aunque ya hay dos filas, hay UNA sola vigente (la cabeza de la cadena)');

select is(
  (select vigente->>'apoyo' from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  'confirmado_por_contador_o_laboralista',
  '33 · la vigente es la corrección, no la primera');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'retirada', null, 'se dejó por error: falta confirmarlo con el laboralista',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001'))) $$,
  '34 · retirar una constancia puesta por error');

select ok(
  (select vigente is null and puede_constatar and cabeza_id is not null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '35 · retirar REABRE el aviso: ya no hay vigente y se puede volver a constatar');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435001', (select v from _a), (select h from _a),
       'pagado_es_correcto', 'regla_cambio_despues', 'ya confirmado: la regla de vacaciones cambió después del pago',
       (select cabeza_id from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001'))) $$,
  '36 · después de retirar se puede constatar de nuevo, continuando la cadena');

select lives_ok(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435002', 1,
       (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
       'no_se_reclama', null, 'se le pagó de más y CAYLA decide no reclamarlo') $$,
  '37 · B (a favor de CAYLA): «no se reclama» sí corresponde');

select ok(
  (select vigente->>'decision' = 'no_se_reclama' and vigente->>'apoyo' is null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435002')),
  '38 · y no lleva apoyo: el apoyo es solo de «lo pagado era lo correcto»');


-- ── § 4 · «Vuelve si el cálculo cambia» (y vuelve a valer si el cálculo vuelve) ──
create temp table _h as
  select huella as h from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001');

update jornadas set horas_trabajadas = 8.0
 where persona_id = '00000000-0000-0000-0000-000000435001' and fecha = '2020-06-05';

select ok(
  (select vigente is null and anterior is not null and huella <> (select h from _h)
          and jsonb_array_length(filas) = 2
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '39 · el cálculo cambió (un marcaje corregido): la constancia ya no vale, la huella es otra y aparece la anterior');

select ok(
  (select anterior->>'decision' = 'pagado_es_correcto'
          and jsonb_array_length(anterior->'diferencias') = 1
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '40 · la constancia anterior trae lo que se vio entonces (una fila), para mostrar las dos cifras lado a lado');

update jornadas set horas_trabajadas = 6.5
 where persona_id = '00000000-0000-0000-0000-000000435001' and fecha = '2020-06-05';

select ok(
  (select vigente is not null and huella = (select h from _h)
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435001')),
  '41 · el cálculo VOLVIÓ a lo que era: la constancia vuelve a valer (es la misma situación que se miró)');


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

select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000435102', true) $$,
  '49 · F: el mes se cierra');

select ok(
  (select vigente is null and anterior is not null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435006')),
  '50 · F (CASO CONOCIDO): la diferencia de «Sueldo del periodo» cambió en −D, así que la constancia caduca UNA vez y el aviso vuelve con las dos cifras');


-- ── § 6 · Una versión superada o anulada es inerte ─────────────────────────
select pg_temp.congelar('00000000-0000-0000-0000-000000435008', 0, 50, 0, 0);
select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435008', 1,
  (select huella from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
  'pagado_es_correcto', 'regla_cambio_despues', 'la regla de vacaciones cambió después del pago');
select fn_liquidacion_pagar('00000000-0000-0000-0000-000000435008', 'vuelvo a marcarla con el cálculo de hoy');

select ok(
  (select version = 2 and hay_real is false and vigente is null
     from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435008')),
  '51 · H: al volver a marcarla pagada (versión 2) el estado habla de la versión nueva: nada vigente, sin diferencia');

select is(
  (select count(*)::int from liquidacion_constancias where persona_id = '00000000-0000-0000-0000-000000435008'),
  1,
  '52 · H: la constancia de la versión 1 sigue guardada, intacta e inerte');

select pg_temp.congelar('00000000-0000-0000-0000-000000435009', 0, 50, 0, 0);
select fn_liquidacion_anular('00000000-0000-0000-0000-000000435009', 'marcada por error en la prueba');

select is(
  (select count(*)::int from fn_liquidacion_constancia_estado('00000000-0000-0000-0000-000000435009')),
  0,
  '53 · I: con la última versión anulada no hay estado');

select throws_like(
  $$ select fn_liquidacion_constatar('00000000-0000-0000-0000-000000435009', 1, repeat('0', 32),
       'pagado_es_correcto', 'regla_cambio_despues', 'sobre una liquidación anulada no se constata') $$,
  '%no tiene una liquidación pagada vigente%',
  '54 · I: tampoco se puede constatar sobre una liquidación anulada');


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
  '55 · un motivo corto no entra ni saltándose la función (CHECK)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435003', 1, repeat('1', 32), 'a_favor_cayla', 'pagado_es_correcto',
             'regla_cambio_despues', 'un motivo largo y razonable', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23514', null,
  '56 · una decisión contraria al sentido no entra (CHECK)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435003', 1, repeat('1', 32), 'a_favor_persona', 'pagado_es_correcto',
             null, 'un motivo largo y razonable', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23514', null,
  '57 · «Lo pagado era lo correcto» sin apoyo no entra (CHECK)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435003', 1, repeat('1', 32), 'a_favor_persona', 'retirada',
             null, 'un motivo largo y razonable', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23514', null,
  '58 · una retirada sin nada que reemplazar no entra (CHECK)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     values ('00000000-0000-0000-0000-000000435003', 99, repeat('1', 32), 'a_favor_cayla', 'no_se_reclama',
             null, 'un motivo largo y razonable', '[{"x":1}]', '00000000-0000-0000-0000-000000435099') $$,
  '23503', null,
  '59 · una constancia sobre una versión que no existe no entra (FK compuesta)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, constatada_por)
     select persona_id, version, huella, 'a_favor_cayla', 'no_se_reclama', null,
            'una segunda raíz de la misma diferencia', '[{"x":1}]', '00000000-0000-0000-0000-000000435099' from _base $$,
  '23505', null,
  '60 · dos raíces para la misma (persona, versión, huella) no caben: una sola vigente (índice único)');

select throws_ok(
  $$ insert into liquidacion_constancias (persona_id, version, huella, sentido, decision, apoyo, motivo, diferencias, reemplaza_id, constatada_por)
     select persona_id, version, repeat('2', 32), 'a_favor_cayla', 'no_se_reclama', null,
            'una cadena que mezcla otra huella', '[{"x":1}]', id, '00000000-0000-0000-0000-000000435099' from _base $$,
  '23503', null,
  '61 · una cadena no puede mezclar huellas distintas (FK compuesta autorreferida)');

select throws_ok(
  $$ update liquidacion_constancias set motivo = 'reescribiendo la historia a escondidas'
      where persona_id = '00000000-0000-0000-0000-000000435002' $$,
  'P0001', null,
  '62 · una constancia no se edita (trigger)');

select throws_ok(
  $$ delete from liquidacion_constancias where persona_id = '00000000-0000-0000-0000-000000435002' $$,
  'P0001', null,
  '63 · ni se borra (trigger)');


-- ── § 8 · La tabla está cerrada para escribir; leer, solo admin y líder DO ─
select ok(
  not has_table_privilege('authenticated', 'liquidacion_constancias', 'insert')
  and not has_table_privilege('authenticated', 'liquidacion_constancias', 'update')
  and not has_table_privilege('authenticated', 'liquidacion_constancias', 'delete')
  and not has_table_privilege('authenticated', 'liquidacion_constancias', 'truncate')
  and has_table_privilege('authenticated', 'liquidacion_constancias', 'select')
  and not has_table_privilege('anon', 'liquidacion_constancias', 'select'),
  '64 · authenticated solo lee (ni insert, ni update, ni delete, ni truncate) y anon ni eso: cerrada por revoke, no por ausencia de grant');

grant insert on liquidacion_constancias to authenticated;
select ok(
  has_table_privilege('authenticated', 'liquidacion_constancias', 'insert'),
  '65 · CONTROL: reabriendo el hueco a propósito la aserción anterior habría fallado (la prueba puede ponerse en rojo)');
revoke insert on liquidacion_constancias from authenticated;

select ok(
  not has_function_privilege('anon', 'fn_liquidacion_constancia_estado(uuid)', 'execute')
  and has_function_privilege('authenticated', 'fn_liquidacion_constancia_estado(uuid)', 'execute')
  and not has_function_privilege('anon', 'fn_liquidacion_constatar(uuid,int,text,text,text,text,uuid)', 'execute')
  and has_function_privilege('authenticated', 'fn_liquidacion_constatar(uuid,int,text,text,text,text,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'fn_liquidacion_huella(jsonb)', 'execute'),
  '66 · las dos funciones se ejecutan solo con sesión; la de la huella ni eso (la llaman las otras, que son definer)');


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
  '67 · un admin lee las constancias (RLS con el rol authenticated de verdad)');

select is(
  (select n from _rls_integrante),
  0,
  '68 · un integrante no ve ninguna: ni las constancias ni lo que decidió DO sobre un pago');


-- ── § 9 · La huella: canónica ──────────────────────────────────────────────
select is(
  fn_liquidacion_huella('[{"concepto":"CTS trunca","centavos":-3000},{"concepto":"Vacaciones truncas","centavos":5000}]'),
  fn_liquidacion_huella('[{"concepto":"Vacaciones truncas","centavos":5000},{"concepto":"CTS trunca","centavos":-3000}]'),
  '69 · el orden en que llegan las filas no cambia la huella (se ordena por concepto, en collation C)');

select isnt(
  fn_liquidacion_huella('[{"concepto":"CTS trunca","centavos":-3000}]'),
  fn_liquidacion_huella('[{"concepto":"CTS trunca","centavos":-3001}]'),
  '70 · un solo centavo de diferencia cambia la huella');

select * from finish();
rollback;
