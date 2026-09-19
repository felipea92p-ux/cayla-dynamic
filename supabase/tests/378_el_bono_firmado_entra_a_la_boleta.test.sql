-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 378_el_bono_firmado_entra_a_la_boleta.test.sql — 0479
-- ============================================================================
-- Lo que defiende, en el orden del recorrido real:
--
--   1. SIN PERIODO, EL RESPALDO. Si al firmar no hay periodo de planilla, la
--      firma vale igual y el bono queda «pedido» para que DO lo transfiera
--      (el camino de la 0478). Nunca se bloquea a la persona.
--   2. LA BOLETA LO VE. Con un periodo abierto, firmar deja la línea
--      «Asignación por cumpleaños» y la persona, COMO ELLA MISMA, la ve en su
--      boleta y el total sube exactamente el monto.
--   3. LO QUE NO DEBE MOVERSE. Ni la pensión ni EsSalud cambian: el bono no es
--      remuneración computable (art. 19 g) del D.S. 001-97-TR).
--   4. NO SE PAGA DOS VECES. Con la línea en la boleta, DO no puede
--      «transferirlo» aparte, ni por la función ni por un update directo.
--   5. SI QUITAN LA LÍNEA, NO SE PIERDE. El vínculo se suelta y el bono vuelve
--      a la lista por transferir.
--   6. UN PERIODO PAGADO NO SE TOCA. Firmar con el último periodo ya pagado no
--      escribe en él. Y ya pagado, el bono figura como entregado por la boleta.
--   7. EL ESTADO IMPOSIBLE NO EXISTE. La base rechaza el vínculo que no debe.
--
-- QUÉ NO SE PRUEBA AQUÍ, Y POR QUÉ. La carrera «DO marca el periodo pagado en
-- el mismo segundo en que ella firma» se resuelve con `for share` contra el
-- `for update` de `fn_periodo_pagado`: dos sesiones a la vez, y pgTAP corre en
-- una. Está razonada en el encabezado de la 0479, no medida.
--
-- Supone una base sin periodos de planilla (la de CI, construida desde cero):
-- por eso empieza borrándolos. En una base de desarrollo con periodos reales,
-- corre siempre el control sin la migración antes de creer un rojo.
-- ============================================================================
begin;
select plan(38);

-- Base limpia de periodos: el escenario 1 lo exige (sin periodo, sin boleta).
delete from periodo_grupo_pago;
delete from periodos_planilla;

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000378000', 'ZZ378', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000378001', 'Prueba', 'EnBoleta',
   '00000000-0000-0000-0000-000000378000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000378011', '2020-01-01'),
  ('00000000-0000-0000-0000-000000378002', 'Prueba', 'SinPeriodo',
   '00000000-0000-0000-0000-000000378000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000378012', '2020-01-01'),
  ('00000000-0000-0000-0000-000000378003', 'Prueba', 'PeriodoPagado',
   '00000000-0000-0000-0000-000000378000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000378013', '2020-01-01'),
  ('00000000-0000-0000-0000-000000378004', 'Prueba', 'LaQuitan',
   '00000000-0000-0000-0000-000000378000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000378014', '2020-01-01'),
  ('00000000-0000-0000-0000-000000378005', 'Prueba', 'DoUno',
   '00000000-0000-0000-0000-000000378000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000378015', '2020-01-01'),
  ('00000000-0000-0000-0000-000000378006', 'Prueba', 'DoDos',
   '00000000-0000-0000-0000-000000378000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000378016', '2020-01-01'),
  ('00000000-0000-0000-0000-000000378007', 'Prueba', 'EnPapel',
   '00000000-0000-0000-0000-000000378000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000378017', '2020-01-01');
set session_replication_role = origin;

-- Cumpleaños este mes para las integrantes (las dos de DO no piden nada aquí).
insert into datos_personales (persona_id, fecha_nacimiento)
select id, make_date(1995, extract(month from fn_hoy_lima())::int, 10)
  from personas
 where id in ('00000000-0000-0000-0000-000000378001', '00000000-0000-0000-0000-000000378002',
              '00000000-0000-0000-0000-000000378003', '00000000-0000-0000-0000-000000378004',
              '00000000-0000-0000-0000-000000378007');

insert into firmas_escaneadas (persona_id, imagen, tipo)
select id, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen'
  from personas where id::text like '00000000-0000-0000-0000-00000037800%';

-- Solo la primera necesita sueldo y jornadas: es la única cuya boleta se mira.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000378001', 'cayla', 1800, '2025-01-01');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000378001', d::date, 8, 'cerrada'
  from generate_series(fn_hoy_lima() - 10, fn_hoy_lima(), interval '1 day') d
 where extract(dow from d) <> 0;

create function pg_temp.pudo_pedir() returns boolean language plpgsql as $$
begin
  perform fn_confirmar_mi_bono_cumpleanos();
  return true;
exception when others then
  return false;
end $$;

create function pg_temp.como(p_sub text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_sub, true);
end $$;


-- ── 1 · SIN PERIODO, EL RESPALDO ─────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000378012');
select is(pg_temp.pudo_pedir(), true,
  'RESPALDO · sin ningún periodo de planilla, firmar igual funciona');
select is((select estado from fn_mi_bono_cumpleanos()), 'pedido',
  'RESPALDO · queda «pedido»: nadie lo paga todavía');
select is((select via from fn_mi_bono_cumpleanos()), 'transferencia',
  'RESPALDO · y dice por dónde le va a llegar: transferencia de DO');
select is(
  (select movimiento_id from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000378002' and tipo = 'bono'),
  null::uuid,
  'RESPALDO · la constancia no queda atada a ninguna línea de boleta');
select is(
  (select count(*) from movimientos_planilla
    where persona_id = '00000000-0000-0000-0000-000000378002'),
  0::bigint,
  'RESPALDO · y no se escribió nada en ninguna planilla');

select pg_temp.como('00000000-0000-0000-0000-000000378015');
select is(
  (select count(*) from fn_bonos_por_transferir()
    where persona_id = '00000000-0000-0000-0000-000000378002'),
  1::bigint,
  'RESPALDO · DO lo ve por transferir, como en la 0478');


-- ── Ahora sí hay un periodo abierto, y la boleta de la primera, ANTES ────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000378a1', fn_hoy_lima() - 10, fn_hoy_lima() + 20, 'abierto');

select pg_temp.como('00000000-0000-0000-0000-000000378011');
create temp table _antes on commit drop as
select fn_planilla_calcular_persona('00000000-0000-0000-0000-000000378001',
                                    '00000000-0000-0000-0000-0000000378a1') as f;

select ok((select (f->>'total')::numeric from _antes) > 0,
  'CONTROL · su boleta de partida tiene un total real, no un cero vacío');
select is((select (f->>'bonos')::numeric from _antes), 0::numeric,
  'CONTROL · y todavía sin bonos');


-- ── 2 · LA BOLETA LO VE ──────────────────────────────────────────────────
select is(pg_temp.pudo_pedir(), true, 'PEDIDO · con periodo abierto, firmar funciona');
select is((select estado from fn_mi_bono_cumpleanos()), 'en_boleta',
  'ESTADO · queda «en_boleta», no «pedido»: no espera a DO');
select is((select via from fn_mi_bono_cumpleanos()), 'boleta', 'ESTADO · por la boleta');
select is((select periodo_fin from fn_mi_bono_cumpleanos()), fn_hoy_lima() + 20,
  'ESTADO · y dice qué periodo la lleva: el que cierra dentro de 20 días');
select is(
  (select count(*) from movimientos_planilla
    where persona_id = '00000000-0000-0000-0000-000000378001'
      and periodo_id = '00000000-0000-0000-0000-0000000378a1'
      and tipo = 'bono'
      and concepto = 'Asignación por cumpleaños'
      and monto = fn_bono_monto_vigente()),
  1::bigint,
  'LÍNEA · una sola, en el periodo que corre, con el monto vigente');
select is(
  (select movimiento_id from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000378001' and tipo = 'bono'),
  (select id from movimientos_planilla
    where persona_id = '00000000-0000-0000-0000-000000378001' and tipo = 'bono'),
  'VÍNCULO · la constancia queda atada a SU línea de boleta');

create temp table _despues on commit drop as
select fn_planilla_calcular_persona('00000000-0000-0000-0000-000000378001',
                                    '00000000-0000-0000-0000-0000000378a1') as f;

select is((select (f->>'bonos')::numeric from _despues), fn_bono_monto_vigente(),
  'BOLETA · ella, como ella misma, ve el bono en su propia boleta');
select is(
  (select count(*) from jsonb_array_elements((select f->'movimientos' from _despues)) m
    where m->>'concepto' = 'Asignación por cumpleaños'),
  1::bigint,
  'BOLETA · con su nombre, para que ella sepa de dónde viene');
select is(
  (select (f->>'total')::numeric from _despues),
  (select (f->>'total')::numeric from _antes) + fn_bono_monto_vigente(),
  'PAGO · el total sube EXACTAMENTE el monto del bono: se paga con la planilla');


-- ── 3 · LO QUE NO DEBE MOVERSE ───────────────────────────────────────────
select isnt((select f->>'descuento_afp' from _antes), null,
  'CONTROL · la pensión de partida es un número, no un vacío que iguala cualquier cosa');
select is((select f->>'descuento_afp' from _despues), (select f->>'descuento_afp' from _antes),
  'NO REMUNERATIVO · el descuento de pensión no cambia con el bono');
select is((select f->>'aporte_essalud' from _despues), (select f->>'aporte_essalud' from _antes),
  'NO REMUNERATIVO · el aporte a EsSalud no cambia con el bono');
select is((select f->>'base_essalud' from _despues), (select f->>'base_essalud' from _antes),
  'NO REMUNERATIVO · y su base tampoco');


-- ── 4 · NO SE PAGA DOS VECES ─────────────────────────────────────────────
select is(pg_temp.pudo_pedir(), false, 'PEDIDO · no se pide dos veces');

select pg_temp.como('00000000-0000-0000-0000-000000378015');
select is(
  (select count(*) from fn_bonos_por_transferir()
    where persona_id = '00000000-0000-0000-0000-000000378001'),
  0::bigint,
  'DO · lo que va en boleta NO aparece por transferir: ya lo paga la planilla');
select throws_ok(
  $$ select fn_confirmar_entrega_bono(
       (select id from documentos_firmados
         where persona_id = '00000000-0000-0000-0000-000000378001' and tipo = 'bono'),
       fn_hoy_lima()) $$,
  null, null,
  'DO · «ya se lo transferí» sobre un bono que va en boleta se rechaza');
select throws_ok(
  $$ update documentos_firmados
        set entrega_confirmada_el = fn_hoy_lima(),
            entrega_confirmada_por = '00000000-0000-0000-0000-000000378006',
            entrega_confirmada_at = now()
      where persona_id = '00000000-0000-0000-0000-000000378001' and tipo = 'bono' $$,
  '23514', null,
  'CONSTRAINT · ni por un update directo: boleta y transferencia se excluyen');


-- ── 5 · SI QUITAN LA LÍNEA, NO SE PIERDE ─────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000378014');
select is(pg_temp.pudo_pedir(), true, 'QUITAR · la cuarta también firma y queda en boleta');
select is((select estado from fn_mi_bono_cumpleanos()), 'en_boleta', 'QUITAR · de partida, en boleta');

select pg_temp.como('00000000-0000-0000-0000-000000378015');
select lives_ok(
  $$ select fn_quitar_movimiento(
       (select id from movimientos_planilla
         where persona_id = '00000000-0000-0000-0000-000000378004' and tipo = 'bono')) $$,
  'QUITAR · DO quita la línea desde Planilla, con el periodo abierto');

select pg_temp.como('00000000-0000-0000-0000-000000378014');
select is((select estado from fn_mi_bono_cumpleanos()), 'pedido',
  'QUITAR · el bono no se pierde: vuelve a «pedido»');
select is(
  (select movimiento_id from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000378004' and tipo = 'bono'),
  null::uuid,
  'QUITAR · el vínculo se soltó solo (on delete set null)');
select pg_temp.como('00000000-0000-0000-0000-000000378015');
select is(
  (select count(*) from fn_bonos_por_transferir()
    where persona_id = '00000000-0000-0000-0000-000000378004'),
  1::bigint,
  'QUITAR · y reaparece en la lista por transferir de DO');


-- ── 6 · UN PERIODO PAGADO NO SE TOCA ─────────────────────────────────────
update periodos_planilla set estado = 'pagado', pagado_at = now()
 where id = '00000000-0000-0000-0000-0000000378a1';

select pg_temp.como('00000000-0000-0000-0000-000000378011');
select is((select estado || ' ' || via from fn_mi_bono_cumpleanos()), 'entregado boleta',
  'PAGADO · con el periodo pagado, su bono figura entregado POR LA BOLETA');
select is((select entregado_el from fn_mi_bono_cumpleanos()), null::date,
  'PAGADO · sin inventar un día de pago que nadie guarda por persona');

select pg_temp.como('00000000-0000-0000-0000-000000378013');
select is(pg_temp.pudo_pedir(), true, 'PAGADO · firmar con el último periodo ya pagado funciona…');
select is(
  (select count(*) from movimientos_planilla
    where persona_id = '00000000-0000-0000-0000-000000378003'),
  0::bigint,
  '…pero no escribe en el periodo pagado: nunca se toca lo ya cerrado');
select is((select estado from fn_mi_bono_cumpleanos()), 'pedido',
  'PAGADO · queda «pedido» para que DO lo transfiera');


-- ── 7 · EL ESTADO IMPOSIBLE NO EXISTE ────────────────────────────────────
select throws_ok(
  $$ update documentos_firmados
        set movimiento_id = (select id from movimientos_planilla
                              where persona_id = '00000000-0000-0000-0000-000000378001' and tipo = 'bono')
      where persona_id = '00000000-0000-0000-0000-000000378003' and tipo = 'bono' $$,
  '23505', null,
  'ÍNDICE · una línea de boleta no puede pagar dos constancias');

select pg_temp.como('00000000-0000-0000-0000-000000378016');
select fn_documento_registrar('bono', fn_hoy_lima() - 1, '00000000-0000-0000-0000-000000378007',
                              null, 180.00, extract(year from fn_hoy_lima())::int,
                              false, null, 'documentos/bono-en-papel.pdf');
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
values ('00000000-0000-0000-0000-0000000378a1', '00000000-0000-0000-0000-000000378007',
        'bono', 'Bono suelto de laboratorio', 10.00, '00000000-0000-0000-0000-000000378016');
select throws_ok(
  $$ update documentos_firmados
        set movimiento_id = (select id from movimientos_planilla
                              where persona_id = '00000000-0000-0000-0000-000000378007' and tipo = 'bono')
      where persona_id = '00000000-0000-0000-0000-000000378007' and tipo = 'bono' $$,
  '23514', null,
  'CONSTRAINT · un cargo en papel no puede estar en una boleta');

select finish();
rollback;
