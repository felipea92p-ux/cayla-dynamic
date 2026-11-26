-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- ============================================================================
-- 506 — La gratificación y la CTS no se llaman «bono» (0621)
-- ============================================================================
-- El 2026-07-28 se decidió volver a los nombres legales, pero la función que
-- escribe el concepto autocompletado siguió diciendo «Bono Gratitud» y «Bono
-- Comprometidos» durante cuatro reescrituras, porque cada una copió el cuerpo
-- de la anterior. Esta prueba no fija la redacción exacta (eso lo hace la 88):
-- fija la REGLA, en las cuatro fechas de pago del año y en el concepto del 9 %,
-- para que la próxima copia de un cuerpo viejo no pase callada.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000005fa', 'ZZ506', 'Sede de laboratorio 506', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000005c1', 'Prueba506', 'Laboratorio',
        '00000000-0000-0000-0000-0000000005fa', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000005c9', '2024-01-15', 'planilla');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000005c9', true);

-- ── Julio: gratificación ene–jun + su 9 % ───────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('50600000-0000-0000-0000-000000000001', '2026-06-29', '2026-07-28', 'abierto');

select ok(fn_grati_cts_periodo('50600000-0000-0000-0000-000000000001')->>'grati_concepto' !~* 'bono',
          'JULIO · el concepto de la gratificación no dice «bono»');
select ok(fn_grati_cts_periodo('50600000-0000-0000-0000-000000000001')->>'grati_concepto' ~* '^Gratificación ',
          'JULIO · empieza por su nombre legal');
select ok(fn_grati_cts_periodo('50600000-0000-0000-0000-000000000001')->>'be_concepto' !~* 'bono',
          'JULIO · el concepto del 9 % tampoco (lleva dentro el de la gratificación)');
delete from periodos_planilla where id = '50600000-0000-0000-0000-000000000001';

-- ── Diciembre: gratificación jul–dic ────────────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('50600000-0000-0000-0000-000000000002', '2026-11-29', '2026-12-28', 'abierto');

select ok(fn_grati_cts_periodo('50600000-0000-0000-0000-000000000002')->>'grati_concepto' !~* 'bono',
          'DICIEMBRE · el concepto de la gratificación no dice «bono»');
select ok(fn_grati_cts_periodo('50600000-0000-0000-0000-000000000002')->>'be_concepto' !~* 'bono',
          'DICIEMBRE · ni el del 9 %');
delete from periodos_planilla where id = '50600000-0000-0000-0000-000000000002';

-- ── Mayo: CTS nov–abr ──────────────────────────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('50600000-0000-0000-0000-000000000003', '2026-04-29', '2026-05-28', 'abierto');

select ok(fn_grati_cts_periodo('50600000-0000-0000-0000-000000000003')->>'cts_concepto' !~* 'bono',
          'MAYO · el concepto de la CTS no dice «bono»');
select is(fn_grati_cts_periodo('50600000-0000-0000-0000-000000000003')->>'cts_concepto',
          'CTS nov 2025–abr 2026', 'MAYO · y nombra el semestre que paga');
delete from periodos_planilla where id = '50600000-0000-0000-0000-000000000003';

-- ── Noviembre: CTS may–oct ─────────────────────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('50600000-0000-0000-0000-000000000004', '2026-10-29', '2026-11-28', 'abierto');

select ok(fn_grati_cts_periodo('50600000-0000-0000-0000-000000000004')->>'cts_concepto' !~* 'bono',
          'NOVIEMBRE · el concepto de la CTS no dice «bono»');
select ok(fn_grati_cts_periodo('50600000-0000-0000-0000-000000000004')->>'cts_concepto' ~* '^CTS ',
          'NOVIEMBRE · empieza por su nombre legal');
delete from periodos_planilla where id = '50600000-0000-0000-0000-000000000004';

-- ── Y ningún movimiento guardado conserva el nombre viejo (parte 2) ────────
select is((select count(*) from movimientos_planilla
            where concepto ~* 'Bono\s+(Gratitud|Comprometidos)')::int, 0,
          'DATOS · ningún movimiento conserva «Bono Gratitud» ni «Bono Comprometidos»');

select * from finish();
rollback;
