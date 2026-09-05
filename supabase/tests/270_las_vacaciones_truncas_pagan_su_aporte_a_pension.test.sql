-- ============================================================================
-- 270_las_vacaciones_truncas_pagan_su_aporte_a_pension.test.sql
-- ============================================================================
-- Migración 0341. `fn_vacaciones_truncas` descuenta AFP/ONP del monto, con la
-- misma tasa y el mismo criterio de vigencia que `fn_planilla_calcular`.
--
-- Tres personas, mismo ingreso, mismo salario, mismo cese — la única diferencia
-- es su régimen de pensión:
--   · NoveMixta   → 'integra_mixta' (tasa de prueba: 11.37 %)
--   · NoveFlujo   → 'integra'       (tasa de prueba: 12.92 %, la vieja de flujo)
--   · NoveSinReg  → sin régimen asignado (cae a configuracion.tasa_afp, que es
--                    0 en una base recién creada) — así se comprueba que a
--                    quien no tiene régimen NO se le rompe nada.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000270000', 'ZZ270', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000002700ad', 'NoveAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000270000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000002700ff', '2024-01-01');
set session_replication_role = origin;

-- No se insertan tasas propias: `idx_tasas_pension_vigente_unica` permite una
-- sola fila vigente por régimen, y 'integra'/'integra_mixta' ya tienen la suya
-- desde la 0114/0328 — las mismas que corren en producción. Probar contra esas
-- es mejor que inventar una tasa de prueba: si alguien las actualiza mal, esta
-- prueba lo nota.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, regimen_pension) values
  ('00000000-0000-0000-0000-000000270001','NoveMixta', 'Laboratorio','00000000-0000-0000-0000-000000270000','test-hash','2024-03-01','planilla','integra_mixta'),
  ('00000000-0000-0000-0000-000000270002','NoveFlujo', 'Laboratorio','00000000-0000-0000-0000-000000270000','test-hash','2024-03-01','planilla','integra'),
  ('00000000-0000-0000-0000-000000270003','NoveSinReg','Laboratorio','00000000-0000-0000-0000-000000270000','test-hash','2024-03-01','planilla',null);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950.00, '2024-03-01'
from personas where apellidos = 'Laboratorio' and nombres like 'Nove%' and nombres <> 'NoveAdmin';

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-03-01', '09:00', '18:00', array[1,2,3,4,5]
from personas where apellidos = 'Laboratorio' and nombres like 'Nove%' and nombres <> 'NoveAdmin';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002700ff', true);

create temporary table _liq on commit drop as
select p.nombres as quien,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'monto_bruto')::numeric   as bruto,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'descuento_afp')::numeric as descuento,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'tasa_afp')::numeric      as tasa,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'monto')::numeric         as neto
from personas p
where p.apellidos = 'Laboratorio' and p.nombres like 'Nove%' and p.nombres <> 'NoveAdmin';

-- ── 1 · ANTES NO DESCONTABA NADA, AHORA SÍ ──────────────────────────────────
select cmp_ok((select descuento from _liq where quien = 'NoveMixta'), '>', 0::numeric,
  'AFP · las vacaciones truncas ya descuentan pensión, ya no salen enteras');

-- ── 2 · LA TASA ES LA DEL RÉGIMEN, NO UNA FIJA ──────────────────────────────
select is((select tasa from _liq where quien = 'NoveMixta'), 0.11370::numeric,
  'TASA · a quien está en integra_mixta se le aplica 11.37 %, no otra cosa');
select is((select tasa from _liq where quien = 'NoveFlujo'), 0.12920::numeric,
  'TASA · a quien sigue en integra (flujo) se le aplica su 12.92 %');

-- ── 3 · EL DESCUENTO ES EXACTAMENTE bruto × tasa ────────────────────────────
select is(
  (select descuento from _liq where quien = 'NoveMixta'),
  (select round(bruto * tasa, 2) from _liq where quien = 'NoveMixta'),
  'CÁLCULO · descuento_afp = monto_bruto × tasa_afp, exacto');

-- ── 4 · LA ADITIVIDAD: bruto − descuento = neto, SIEMPRE ────────────────────
select is(
  (select bruto - descuento from _liq where quien = 'NoveFlujo'),
  (select neto from _liq where quien = 'NoveFlujo'),
  'ADITIVIDAD · monto_bruto - descuento_afp = monto, para que la hoja pueda desglosarlo');

-- ── 5 · QUIEN ESTÁ EN FLUJO PAGA MÁS DESCUENTO QUE QUIEN ESTÁ EN MIXTA ──────
-- Mismo sueldo, mismo cese: la única diferencia es el régimen, y tiene que
-- notarse en la plata exactamente como se nota en el sueldo regular.
select cmp_ok(
  (select descuento from _liq where quien = 'NoveFlujo'), '>',
  (select descuento from _liq where quien = 'NoveMixta'),
  'MIXTA VS FLUJO · a igual sueldo, flujo (12.92%) descuenta más que mixta (11.37%)');

-- ── 6 · SIN RÉGIMEN ASIGNADO, NO SE ROMPE NADA (cae a la tasa global = 0) ───
-- Ninguna prueba anterior de esta función tenía régimen asignado, así que esto
-- es lo que las protege: si la tasa global cambiara de 0 esta aserción lo
-- diría, pero hoy confirma que el comportamiento de antes de la 0341 sigue
-- intacto para quien no está clasificado.
select is((select descuento from _liq where quien = 'NoveSinReg'), 0::numeric,
  'SIN RÉGIMEN · nadie con régimen NULL pierde plata por un dato que no tiene');
select is(
  (select bruto from _liq where quien = 'NoveSinReg'),
  (select neto from _liq where quien = 'NoveSinReg'),
  'SIN RÉGIMEN · monto_bruto y monto coinciden, exactamente como antes de la 0341');

select * from finish();
rollback;
