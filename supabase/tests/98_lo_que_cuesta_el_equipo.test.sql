-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 98_lo_que_cuesta_el_equipo.test.sql
-- ============================================================================
-- El apartado de costos solo puede sumar números que no se muevan. Estas
-- pruebas fijan de dónde salen:
--
--   · solo de la foto de los pagos congelados — un periodo abierto no cuenta,
--   · «costo» incluye las provisiones; «neto» no. Confundirlos subestima lo que
--     cuesta el equipo en un ~16,7 % (8,33 grati + 4,17 CTS + 4,17 vacaciones),
--   · la sede y el área son las de ESE periodo, no las de hoy,
--   · y quien no es admin ni líder no ve nada de esto.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000c1', 'ZZCS1', 'Sede costo uno', true),
  ('00000000-0000-0000-0000-0000000000c2', 'ZZCS2', 'Sede costo dos', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000c3', 'CostoAdmin', 'Lab', '00000000-0000-0000-0000-0000000000c1', 'admin', 'x', '00000000-0000-0000-0000-0000000000cc', '2024-01-01'),
       ('00000000-0000-0000-0000-0000000000c4', 'CostoIntegrante', 'Lab', '00000000-0000-0000-0000-0000000000c1', 'integrante', 'x', '00000000-0000-0000-0000-0000000000cd', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion)
values ('00000000-0000-0000-0000-0000000000c5', 'CostoTrabaja', 'Lab', '00000000-0000-0000-0000-0000000000c2', 'x', '2024-01-01', 'taller_produccion');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000c5', 'colibri', 1950, '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-0000000000c5', '2024-01-01', '09:00', '15:30', 0, 0,
        array[1,2,3,4,5,6], 39,
        '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
          "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
          "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000cc', true);

insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000c2', 'entrada',      '2026-03-02T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000c2', 'salida_final', '2026-03-02T15:30:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000c2', 'entrada',      '2026-03-03T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000c2', 'salida_final', '2026-03-03T15:30:00-05:00');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('aaaaaaaa-0000-0000-0000-000000000097', '2026-03-01', '2026-03-31', 'abierto');

-- ── Un periodo abierto no es un costo: todavía se mueve ─────────────────────
select is((fn_costos_planilla('2026-01-01', '2026-12-31')->'totales'->>'periodos')::int,
          0, 'ABIERTO · un periodo sin pagar no entra en los costos');

select is((fn_costos_planilla('2026-01-01', '2026-12-31')->'totales'->>'costo')::numeric,
          0::numeric, 'ABIERTO · y el costo del rango es cero, no una estimación');

-- ── Al pagar, entra ─────────────────────────────────────────────────────────
select fn_periodo_pagado('aaaaaaaa-0000-0000-0000-000000000097', true);

select is((fn_costos_planilla('2026-01-01', '2026-12-31')->'totales'->>'periodos')::int,
          1, 'PAGADO · el periodo congelado ya suma');

-- El costo NO es lo que se transfiere: lleva las provisiones dentro.
select is((fn_costos_planilla('2026-01-01', '2026-12-31')->'totales'->>'costo')::numeric,
          (select round(sum(total + provision_total), 2) from v_planilla_pagada),
          'PAGADO · el costo para CAYLA es el neto MÁS las provisiones');

select cmp_ok((fn_costos_planilla('2026-01-01', '2026-12-31')->'totales'->>'costo')::numeric,
              '>',
              (fn_costos_planilla('2026-01-01', '2026-12-31')->'totales'->>'neto')::numeric,
              'PAGADO · y por eso el costo siempre es mayor que lo que se transfiere');

-- ── Cada periodo pertenece a un solo rango ──────────────────────────────────
-- Se corta por fecha_fin, no por solape: si se cortara por solape, un periodo
-- que cruza el cambio de mes se contaría dos veces al pedir mes a mes.
select is((fn_costos_planilla('2026-01-01', '2026-03-30')->'totales'->>'periodos')::int,
          0, 'RANGO · un periodo que cierra fuera del rango no se cuela a medias');

-- ── Dónde estaba la persona ese periodo ─────────────────────────────────────
select is((select x->>'sede' from jsonb_array_elements(
             fn_costos_planilla('2026-01-01','2026-12-31')->'por_sede') x
           where (x->>'personas')::int > 0 and x->>'sede' = 'ZZCS2' limit 1),
          'ZZCS2', 'SEDE · el costo se agrupa por la sede que tenía la persona en ese periodo');

-- Y sigue siendo la de entonces aunque hoy la trasladen a otra.
update personas set sede_base_id = '00000000-0000-0000-0000-0000000000c1'
where id = '00000000-0000-0000-0000-0000000000c5';

select is((select count(*)::int from jsonb_array_elements(
             fn_costos_planilla('2026-01-01','2026-12-31')->'por_sede') x
           where x->>'sede' = 'ZZCS2'),
          1, 'SEDE · trasladar a la persona hoy no muda el costo de marzo a la sede nueva');

-- ── Quién lo puede ver ──────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000cd', true);
select throws_ok($$ select fn_costos_planilla('2026-01-01','2026-12-31') $$,
                 null, null, 'PERMISOS · una integrante no puede pedir los costos del equipo');

select * from finish();
rollback;
