-- ============================================================================
-- 85_grati_cruza_el_ano.test.sql — La gratificación no se pierde en el cambio de año
-- ============================================================================
-- Dos periodos idénticos salvo el día de cierre. El mismo 15 de diciembre cae
-- dentro de los dos, así que los dos deben pagar la misma gratificación:
--
--     10-dic-2026 → 31-dic-2026   (no cruza el año)
--     10-dic-2026 → 08-ene-2027   (cruza el año)  ← antes no pagaba nada
--
-- Lo que hace peligroso este fallo es que no retrasa el pago, lo borra:
-- fn_crear_periodo solo admite un periodo por mes de cierre, así que si el
-- periodo que contiene el 15 de diciembre cierra en enero, ese periodo ES el de
-- enero y no queda ningún periodo de diciembre que pueda pagarla después.
--
-- Se prueban los dos lados: que el caso roto se arregle, y que el caso que ya
-- funcionaba siga dando exactamente lo mismo.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000fa', 'ZZGRA', 'Sede de laboratorio', true);

set session_replication_role = replica;
-- `en_planilla` es una columna GENERADA desde la 0085: sale de tipo_vinculo y no
-- se puede escribir directo. Se pone el vínculo, y en_planilla se deduce sola.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000000c1', 'PruebaGrati', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000fa', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000000c9', '2024-01-15', 'planilla');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c9', true);

-- ── El periodo que cruza el año: el caso que estaba roto ─────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('bbbbbbb1-0000-0000-0000-000000000001', '2026-12-10', '2027-01-08', 'abierto');

select is((fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000001')->>'grati_aplica')::boolean,
          true, 'CRUZA · un periodo que contiene el 15-dic paga su gratificación aunque cierre en enero');

select is(fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000001')->>'grati_concepto',
          'Bono Gratitud jul–dic 2026',
          'CRUZA · y es la de jul–dic 2026, no la del año del cierre');

select isnt(fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000001')->>'grati_concepto',
            'Bono Gratitud jul–dic 2027',
            'CRUZA · nunca la del año siguiente, que aún no ha ocurrido');

select is(jsonb_array_length(fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000001')->'personas') > 0,
          true, 'CRUZA · la respuesta sigue trayendo la lista de personas');

delete from periodos_planilla where id = 'bbbbbbb1-0000-0000-0000-000000000001';

-- ── El periodo que NO cruza: tiene que seguir igual que antes ────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('bbbbbbb1-0000-0000-0000-000000000002', '2026-12-10', '2026-12-31', 'abierto');

select is((fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000002')->>'grati_aplica')::boolean,
          true, 'NORMAL · el periodo de diciembre de siempre sigue pagando');
select is(fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000002')->>'grati_concepto',
          'Bono Gratitud jul–dic 2026', 'NORMAL · con el mismo concepto de antes');

delete from periodos_planilla where id = 'bbbbbbb1-0000-0000-0000-000000000002';

-- ── La de julio ─────────────────────────────────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('bbbbbbb1-0000-0000-0000-000000000003', '2026-07-01', '2026-07-25', 'abierto');

select is(fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000003')->>'grati_concepto',
          'Bono Gratitud ene–jun 2026', 'JULIO · el periodo que contiene el 15-jul paga la de ene–jun');

delete from periodos_planilla where id = 'bbbbbbb1-0000-0000-0000-000000000003';

-- ── Un periodo sin ninguna fecha de pago dentro no paga nada ────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('bbbbbbb1-0000-0000-0000-000000000004', '2026-08-01', '2026-08-31', 'abierto');

select is((fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000004')->>'grati_aplica')::boolean,
          false, 'AGOSTO · un periodo normal no paga gratificación');
select is((fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000004')->>'cts_aplica')::boolean,
          false, 'AGOSTO · ni CTS');

delete from periodos_planilla where id = 'bbbbbbb1-0000-0000-0000-000000000004';

-- ── El CTS de noviembre sigue detectándose ──────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('bbbbbbb1-0000-0000-0000-000000000005', '2026-11-01', '2026-11-30', 'abierto');

select is(fn_grati_cts_periodo('bbbbbbb1-0000-0000-0000-000000000005')->>'cts_concepto',
          'Bono Comprometidos may–oct 2026', 'NOVIEMBRE · el CTS de may–oct se sigue detectando igual');

select * from finish();
rollback;
