-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 99_volver_a_pagar_sin_abrir_la_puerta.test.sql
-- ============================================================================
-- Arreglar un periodo pagado que dejó de cuadrar tenía una sola ruta: reabrir y
-- volver a marcar. Entre las dos operaciones el periodo queda `abierto`, y
-- estar abierto levanta TODOS los candados que protegen sus marcajes. Una
-- pestaña cerrada a medias deja el periodo abierto, desprotegido y fuera de
-- Costos, sin que nadie se entere.
--
-- Estas pruebas fijan que `fn_repagar_periodo` no abre esa ventana ni un
-- instante, que deja rastro distinguible del de una reapertura de verdad, y que
-- dice cuánto se movió en vez de decir «listo».
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000d1', 'ZZRPG', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000d2', 'RepagoAdmin', 'Lab', '00000000-0000-0000-0000-0000000000d1', 'admin', 'x', '00000000-0000-0000-0000-0000000000dd', '2024-01-01'),
       ('00000000-0000-0000-0000-0000000000d4', 'RepagoIntegrante', 'Lab', '00000000-0000-0000-0000-0000000000d1', 'integrante', 'x', '00000000-0000-0000-0000-0000000000de', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion)
values ('00000000-0000-0000-0000-0000000000d3', 'RepagoTrabaja', 'Lab', '00000000-0000-0000-0000-0000000000d1', 'x', '2024-01-01', 'taller_produccion');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000d3', 'colibri', 1950, '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-0000000000d3', '2024-01-01', '09:00', '15:30', 0, 0,
        array[1,2,3,4,5,6], 39,
        '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
          "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
          "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000dd', true);

insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000d1', 'entrada',      '2026-02-02T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000d1', 'salida_final', '2026-02-02T15:30:00-05:00');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('bbbbbbbb-0000-0000-0000-000000000098', '2026-02-01', '2026-02-28', 'abierto');

-- ── Repagar solo aplica a lo que ya está pagado ─────────────────────────────
select throws_ok($$ select fn_repagar_periodo('bbbbbbbb-0000-0000-0000-000000000098', 'un motivo válido') $$,
                 null, null, 'ABIERTO · un periodo sin pagar no se «vuelve a pagar»: se paga, y es otro botón');

select fn_periodo_pagado('bbbbbbbb-0000-0000-0000-000000000098', true);

-- ── El motivo no es opcional ────────────────────────────────────────────────
select throws_ok($$ select fn_repagar_periodo('bbbbbbbb-0000-0000-0000-000000000098', 'ok') $$,
                 null, null, 'MOTIVO · sin un motivo de verdad no se puede: cambia una cifra ya entregada');

-- ── Se movió el dato de origen después del pago ─────────────────────────────
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto)
values ('bbbbbbbb-0000-0000-0000-000000000098', '00000000-0000-0000-0000-0000000000d3',
        'descuento', 'adelanto de laboratorio', 150);

select is((select count(*)::int from fn_planilla_foto_diferencias('bbbbbbbb-0000-0000-0000-000000000098')),
          1, 'DESVÍO · el sistema ve que el periodo pagado dejó de cuadrar');

-- ── Volver a pagar: dice cuánto se movió ────────────────────────────────────
select is((fn_repagar_periodo('bbbbbbbb-0000-0000-0000-000000000098', 'faltaba el adelanto de enero')->>'diferencia')::numeric,
          -150::numeric, 'REPAGO · dice exactamente cuánto se movió, no solo «listo»');

select is((select count(*)::int from fn_planilla_foto_diferencias('bbbbbbbb-0000-0000-0000-000000000098')),
          0, 'REPAGO · y después la foto vuelve a cuadrar con la realidad');

-- ── El periodo nunca pasó por abierto ───────────────────────────────────────
select is((select estado from periodos_planilla where id='bbbbbbbb-0000-0000-0000-000000000098'),
          'pagado', 'CANDADO · el periodo sigue pagado: los candados de sus marcajes no se levantaron');

-- Y se comprueba de verdad: con el periodo pagado, tocar una marca suya frena.
select throws_ok($$ select fn_otorgar_descanso_sustitutorio(
    '00000000-0000-0000-0000-0000000000d3', '2026-02-02', '2026-03-02', 'OTORGADO', 'acta-lab-99') $$,
  null, null, 'CANDADO · y siguen puestos: no se puede tocar un dato de ese periodo');

-- ── El rastro distingue las dos cosas ───────────────────────────────────────
select is((select tipo from reversas_pago where periodo_id='bbbbbbbb-0000-0000-0000-000000000098'),
          'repago', 'RASTRO · queda registrado como repago, no como reapertura');

select is((select motivo from reversas_pago where periodo_id='bbbbbbbb-0000-0000-0000-000000000098'),
          'faltaba el adelanto de enero', 'RASTRO · con el motivo que escribió la persona');

-- ── Y la copia anterior no se pierde ────────────────────────────────────────
select is((select count(distinct version)::int from planilla_pagada_detalle
           where periodo_id='bbbbbbbb-0000-0000-0000-000000000098'),
          2, 'HISTÓRICO · la foto anterior se conserva junto a la nueva');

select * from finish();
rollback;
