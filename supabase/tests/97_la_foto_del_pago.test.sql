-- ============================================================================
-- 97_la_foto_del_pago.test.sql
-- ============================================================================
-- La planilla no se guardaba: se calculaba en vivo cada vez. Marcar «pagado»
-- solo cambiaba una palabra de estado, así que el total de un periodo ya pagado
-- podía cambiar después — y nadie se enteraba, porque no había contra qué
-- comparar. Un costo que cambia solo no sirve para contabilidad.
--
-- Estas pruebas fijan las cuatro promesas de la 0096:
--   · al pagar se congela el desglose,
--   · lo congelado no se edita ni se borra,
--   · si la realidad se mueve, el sistema lo DICE en vez de cambiar la cifra,
--   · reabrir y volver a pagar crea una versión nueva sin borrar la anterior.
-- ============================================================================
begin;
select plan(13);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000f5', 'ZZFOT', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000f6', 'FotoAdmin', 'Lab', '00000000-0000-0000-0000-0000000000f5', 'admin', 'x', '00000000-0000-0000-0000-00000000ff06', '2024-01-01'),
       ('00000000-0000-0000-0000-0000000000f9', 'FotoIntegrante', 'Lab', '00000000-0000-0000-0000-0000000000f5', 'integrante', 'x', '00000000-0000-0000-0000-00000000ff09', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion)
values ('00000000-0000-0000-0000-0000000000f7', 'FotoTrabaja', 'Lab', '00000000-0000-0000-0000-0000000000f5', 'x', '2024-01-01', 'taller_produccion');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000f7', 'colibri', 1950, '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-0000000000f7', '2024-01-01', '09:00', '15:30', 0, 0,
        array[1,2,3,4,5,6], 39,
        '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
          "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
          "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ff06', true);

-- Cuatro días trabajados dentro del periodo.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000f7', '00000000-0000-0000-0000-0000000000f5', 'entrada',      '2026-05-04T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000f7', '00000000-0000-0000-0000-0000000000f5', 'salida_final', '2026-05-04T15:30:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000f7', '00000000-0000-0000-0000-0000000000f5', 'entrada',      '2026-05-05T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000f7', '00000000-0000-0000-0000-0000000000f5', 'salida_final', '2026-05-05T15:30:00-05:00');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-000000000001', '2026-05-01', '2026-05-31', 'abierto');

-- ── Al pagar se congela ─────────────────────────────────────────────────────
select is((select count(*)::int from planilla_pagada_detalle
           where periodo_id='eeeeeeee-0000-0000-0000-000000000001'),
          0, 'ANTES · un periodo abierto no tiene foto');

select fn_periodo_pagado('eeeeeeee-0000-0000-0000-000000000001', true);

select cmp_ok((select count(*)::int from planilla_pagada_detalle
               where periodo_id='eeeeeeee-0000-0000-0000-000000000001'),
              '>', 0, 'PAGAR · al marcar como pagado queda la foto del desglose');

select is((select origen from planilla_pagada_detalle
           where periodo_id='eeeeeeee-0000-0000-0000-000000000001'
             and persona_id='00000000-0000-0000-0000-0000000000f7'),
          'pago', 'PAGAR · la foto nace marcada como tomada en el pago, no reconstruida');

-- El costo para CAYLA no es lo que recibe la persona: incluye las provisiones.
select is((select costo_total = total + provision_total from planilla_pagada_detalle
           where persona_id='00000000-0000-0000-0000-0000000000f7'),
          true, 'PAGAR · el costo para CAYLA suma las provisiones, no solo lo que recibe la persona');

-- Dónde estaba la persona ESE mes, no dónde esté mañana.
select is((select area_codigo from planilla_pagada_detalle
           where persona_id='00000000-0000-0000-0000-0000000000f7'),
          'taller_produccion', 'PAGAR · la foto guarda el área de esa persona en ese periodo');

-- ── Lo congelado no se toca ─────────────────────────────────────────────────
select throws_ok($$ update planilla_pagada_detalle set total = 1
                     where persona_id='00000000-0000-0000-0000-0000000000f7' $$,
                 null, null, 'INMUTABLE · una foto pagada no se puede editar');

select throws_ok($$ delete from planilla_pagada_detalle
                     where persona_id='00000000-0000-0000-0000-0000000000f7' $$,
                 null, null, 'INMUTABLE · ni borrar');

select throws_ok($$ select fn_periodo_pagado('eeeeeeee-0000-0000-0000-000000000001', true) $$,
                 null, null, 'INMUTABLE · pagar dos veces el mismo periodo se rechaza');

-- ── Si la realidad se mueve, el sistema lo dice ─────────────────────────────
-- Un bono agregado después del pago cambia el cálculo en vivo. La foto no.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto)
values ('eeeeeeee-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f7',
        'bono', 'bono de laboratorio', 200);

select is((select bonos from v_planilla_pagada
           where persona_id='00000000-0000-0000-0000-0000000000f7'),
          0::numeric, 'DESVÍO · la foto no se movió cuando cambió el dato de origen');

select is((select diferencia from fn_planilla_foto_diferencias('eeeeeeee-0000-0000-0000-000000000001')
           where persona_id='00000000-0000-0000-0000-0000000000f7'),
          200::numeric, 'DESVÍO · y el sistema dice exactamente cuánto se desvió');

-- ── Reabrir y volver a pagar: versión nueva, la anterior se queda ───────────
select fn_revertir_pago('eeeeeeee-0000-0000-0000-000000000001', 'faltaba el bono de laboratorio');
select fn_periodo_pagado('eeeeeeee-0000-0000-0000-000000000001', true);

select is((select count(distinct version)::int from planilla_pagada_detalle
           where periodo_id='eeeeeeee-0000-0000-0000-000000000001'),
          2, 'VERSIONES · la foto anterior se conserva: queda el histórico de las dos');

select is((select bonos from v_planilla_pagada
           where persona_id='00000000-0000-0000-0000-0000000000f7'),
          200::numeric, 'VERSIONES · y la vigente es la nueva, con el bono dentro');

-- ── Quién la puede leer ─────────────────────────────────────────────────────
-- Una integrante no ve la planilla de otra persona (misma regla que la 0090).
-- La RLS de tabla solo actúa si además se cambia de ROL: set_config sola no
-- basta (eso mueve auth.uid(), que es lo que miran las funciones definer).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ff09', true);
set role authenticated;
create temp table _rls_foto as
  select count(*)::int as n from planilla_pagada_detalle
   where persona_id = '00000000-0000-0000-0000-0000000000f7';
reset role;

select is((select n from _rls_foto),
          0, 'PERMISOS · una integrante no ve la foto del sueldo de otra persona');
select * from finish();
rollback;
