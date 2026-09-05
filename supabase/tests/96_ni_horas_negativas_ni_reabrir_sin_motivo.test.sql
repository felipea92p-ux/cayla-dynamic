-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 96_ni_horas_negativas_ni_reabrir_sin_motivo.test.sql
-- ============================================================================
-- Dos agujeros que llegaban los dos a la planilla:
--
--   · El auto-cierre estampaba la salida en la hora PROGRAMADA sin mirar las
--     marcas reales. Quien entraba después de su hora de salida —turno cambiado,
--     evento nocturno, cierre de inventario— y olvidaba marcar acababa con la
--     salida ANTES de la entrada: horas negativas, que la planilla suma tal cual.
--     El día trabajado le restaba horas del mes.
--
--   · fn_periodo_pagado(id, false) reabría un periodo pagado sin pedir motivo y
--     sin escribir una línea de auditoría, aunque la 0066 creó fn_revertir_pago
--     precisamente para que eso no pasara. Y reabrir levanta todos los candados
--     que protegen los marcajes de ese periodo.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000009a', 'ZZNEG', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000009b', 'NegAdmin', 'Lab', '00000000-0000-0000-0000-00000000009a', 'admin', 'x', '00000000-0000-0000-0000-0000000099b0', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000009c', 'NegNocturna', 'Lab', '00000000-0000-0000-0000-00000000009a', 'x', '2024-01-01');

-- Horario de mañana: sale a las 15:30. Pero ese día vino por la tarde.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-00000000009c', '2024-01-01', '09:00', '15:30', 0, 0,
        array[1,2,3,4,5,6], 39,
        '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
          "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
          "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000099b0', true);

-- ── Entró a las 18:00 para un cierre de inventario y no marcó su salida ──────
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
values (gen_random_uuid(), '00000000-0000-0000-0000-00000000009c', '00000000-0000-0000-0000-00000000009a',
        'entrada', '2026-07-20T18:00:00-05:00');

select fn_auto_cierre();

select is((select (salida_final_ts >= entrada_ts) from jornadas
           where persona_id='00000000-0000-0000-0000-00000000009c' and fecha='2026-07-20'),
          true, 'AUTO-CIERRE · la salida inventada nunca queda antes que la entrada real');

select is((select horas_trabajadas >= 0 from jornadas
           where persona_id='00000000-0000-0000-0000-00000000009c' and fecha='2026-07-20'),
          true, 'AUTO-CIERRE · y por tanto las horas del día no son negativas');

-- ── El esquema hace imposible el estado, no solo el código ───────────────────
select throws_ok($$ update jornadas set horas_trabajadas = -3.00
                     where persona_id='00000000-0000-0000-0000-00000000009c' $$,
                 null, null, 'ESQUEMA · un número negativo de horas no se puede guardar ni a mano');

-- ── Reabrir un pago exige la puerta que pide motivo ──────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('dddddddd-0000-0000-0000-000000000001', '2026-07-01', '2026-07-31', 'abierto');

-- CAMBIO 0284 — Desde la 0284 un periodo no se cierra mientras tenga días con la
-- salida puesta por el sistema y sin confirmar, y la primera mitad de esta misma
-- prueba crea uno justo dentro de este periodo (20/07). No es un estorbo del
-- freno: es el freno funcionando. Se confirma por la puerta real —la que usa
-- Correcciones— y de paso queda probado que el freno tiene salida.
select fn_confirmar_auto_cierre(
  (select id from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000009c'
      and origen = 'auto_cierre' and anulada_at is null
    order by timestamp_marca desc limit 1),
  'Confirmada en el laboratorio para poder cerrar el periodo');

select lives_ok($$ select fn_periodo_pagado('dddddddd-0000-0000-0000-000000000001', true) $$,
                'PAGO · marcar como pagado sigue funcionando igual');

select throws_ok($$ select fn_periodo_pagado('dddddddd-0000-0000-0000-000000000001', false) $$,
                 null, null, 'PAGO · reabrir por la puerta vieja se rechaza: tiene que quedar el motivo');

select is((select estado from periodos_planilla where id='dddddddd-0000-0000-0000-000000000001'),
          'pagado', 'PAGO · y el periodo sigue pagado: el intento no dejó nada a medias');

select * from finish();
rollback;
