-- ============================================================================
-- aplicar_0132_bases.sql — Mover a todo el equipo a la escala del 2026-08-04
-- ----------------------------------------------------------------------------
-- ⚠️ ESTE SCRIPT MUEVE DINERO REAL. La migración 0132 solo puso los topes de
-- educación; esto es lo que cambia la base declarada de cada persona.
--
-- QUÉ HACE. Por cada rango, abre un tramo salarial nuevo a la base de la escala
-- nueva, para todo el que tenga ese rango vigente, esté activo y en planilla.
-- Es idempotente: quien ya esté en el monto pedido no se toca.
--
-- LA ESCALA (anterior → nueva):
--   colibri     1130 → 1130   (sin cambio, es la RMV)
--   cayla       1130 → 1185   ▲ +55
--   caylo       1130 → 1185   ▲ +55
--   support     1290 → 1260   ▼ −30
--   aurora      1500 → 1360   ▼ −140
--   oraculo     1810 → 1440   ▼ −370
--   archicaylo  2670 → 1500   ▼ −1170
--
-- ⚠️ LAS BAJADAS REDUCEN CTS, GRATIFICACIÓN, VACACIONES Y PENSIÓN de quien ya
-- estaba en esos rangos, porque las cuatro se calculan sobre lo declarado.
-- Decisión tomada por Felipe el 2026-08-04, con el efecto entendido.
--
-- ── ANTES DE CORRER ─────────────────────────────────────────────────────────
--   1. Reemplaza AAAA-MM-DD por la fecha desde la que rige la escala nueva.
--      No uses una fecha dentro de un periodo ya pagado.
--   2. Corre primero el bloque "FOTO ANTES" y guarda el resultado.
--   3. Corre el bloque de cambios DENTRO de la transacción, revisa lo que
--      devuelve, y recién entonces cambia ROLLBACK por COMMIT.
-- ============================================================================

-- ── FOTO ANTES (correr solo esto primero, y guardar la salida) ──────────────
select a.rango,
       count(*)                              as personas,
       min(a.salario_mensual_soles)          as salario_min,
       max(a.salario_mensual_soles)          as salario_max
  from personas p
  join asignaciones_salario a
    on a.persona_id = p.id and a.vigente_hasta is null
 where p.estado = 'activo' and p.en_planilla is true
 group by a.rango
 order by a.rango;


-- ── LOS CAMBIOS ─────────────────────────────────────────────────────────────
-- Arranca en ROLLBACK a propósito: se corre, se revisa la salida, y solo
-- entonces se cambia la última línea a COMMIT y se vuelve a correr.
begin;

select 'colibri'    as rango, * from fn_fijar_base_declarada('colibri',    1130, 'AAAA-MM-DD');
select 'cayla'      as rango, * from fn_fijar_base_declarada('cayla',      1185, 'AAAA-MM-DD');
select 'caylo'      as rango, * from fn_fijar_base_declarada('caylo',      1185, 'AAAA-MM-DD');
select 'support'    as rango, * from fn_fijar_base_declarada('support',    1260, 'AAAA-MM-DD');
select 'aurora'     as rango, * from fn_fijar_base_declarada('aurora',     1360, 'AAAA-MM-DD');
select 'oraculo'    as rango, * from fn_fijar_base_declarada('oraculo',    1440, 'AAAA-MM-DD');
select 'archicaylo' as rango, * from fn_fijar_base_declarada('archicaylo', 1500, 'AAAA-MM-DD');

-- FOTO DESPUÉS: tiene que coincidir con la escala de la cabecera.
select a.rango, count(*) as personas, min(a.salario_mensual_soles) as base
  from personas p
  join asignaciones_salario a
    on a.persona_id = p.id and a.vigente_hasta is null
 where p.estado = 'activo' and p.en_planilla is true
 group by a.rango
 order by a.rango;

rollback;  -- ← cambiar a COMMIT cuando la foto de arriba sea la correcta
