-- ============================================================================
-- 224_la_gratificacion_ya_depositada_no_se_paga_dos_veces.test.sql
-- ============================================================================
-- Migración 0288. Quien cesa DESPUÉS de cobrar su gratificación no la vuelve a
-- cobrar en la liquidación.
--
-- CUATRO PERSONAS IDÉNTICAS y una sola variable: el día del cese. A las cuatro
-- se les depositó la gratificación de enero-junio el 15 de julio, registrada
-- como movimiento de planilla, y el periodo que la contiene sigue ABIERTO —que
-- es como está de verdad el día 20—.
--
-- LAS DOS MITADES QUE SE ROMPEN POR SEPARADO, y por eso están las cuatro:
--   · quien cesa DESPUÉS del 15 no la cobra otra vez (aserción 2);
--   · pero quien cesa ANTES del 15 SÍ la cobra, porque se la deben (aserción 1),
--     y quien cesa en septiembre NO da por cobrada la de diciembre, que
--     todavía no existe (aserción 4). Esas dos son lo que la línea vieja
--     protegía, y un arreglo a lo bruto las rompe sin que nada más se entere.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000288000', 'ZZ288', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000002880ad', 'DiezAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000288000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000002880ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000288001','DiezAntesDel15','Laboratorio','00000000-0000-0000-0000-000000288000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000288002','DiezDespuesDel15','Laboratorio','00000000-0000-0000-0000-000000288000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000288003','DiezEnAgosto','Laboratorio','00000000-0000-0000-0000-000000288000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000288004','DiezEnSetiembre','Laboratorio','00000000-0000-0000-0000-000000288000','test-hash','2024-01-01','planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950.00, '2024-01-01'
from personas where apellidos = 'Laboratorio' and nombres like 'Diez%' and nombres <> 'DiezAdmin';

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '15:30', array[1,2,3,4,5]
from personas where apellidos = 'Laboratorio' and nombres like 'Diez%' and nombres <> 'DiezAdmin';

-- ABIERTO a propósito: es como está el periodo el día 20, y es la mitad del
-- defecto. Si alguien lo pone en 'pagado' para que la prueba sea más cómoda,
-- deja de probar lo que dice probar.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000288097', '2026-06-29', '2026-07-28', 'abierto');

insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria)
select '00000000-0000-0000-0000-000000288097', p.id, 'bono', 'Gratificacion julio 2026', 975.00, 'gratificacion'
from personas p where p.apellidos = 'Laboratorio' and p.nombres like 'Diez%' and p.nombres <> 'DiezAdmin';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002880ff', true);

-- ── 1 · ANTES DEL 15 SE LA DEBEN ────────────────────────────────────────────
-- La mitad que impide arreglar esto de más. Ceso el 12: el deposito del 15
-- todavia no habia ocurrido, asi que la liquidacion tiene que pagarsela entera.
select cmp_ok(
  (fn_grati_trunca('00000000-0000-0000-0000-000000288001','2026-07-12')->>'monto')::numeric,
  '>', 1000::numeric,
  'ANTES DEL 15 · quien cesa el 12 cobra su gratificacion: aun no se la habian pagado');

-- ── 2 · DESPUES DEL 15 NO SE REPITE ─────────────────────────────────────────
-- El defecto. Antes de la 0288 esto daba S/1.062,75.
select is(
  (fn_grati_trunca('00000000-0000-0000-0000-000000288002','2026-07-20')->>'monto')::numeric,
  0::numeric,
  'DESPUES DEL 15 · quien cesa el 20 NO la cobra otra vez');

-- ── 3 · Y EL TRUNCO DEL SEMESTRE NUEVO SIGUE SALIENDO ───────────────────────
-- Que no repita la de enero-junio no puede llevarse por delante la de
-- julio-diciembre, que se esta devengando.
select cmp_ok(
  (fn_grati_trunca('00000000-0000-0000-0000-000000288003','2026-08-05')->>'monto')::numeric,
  '>', 0::numeric,
  'TRUNCO · quien cesa en agosto sigue cobrando el trunco de julio');

-- ── 4 · LA DE DICIEMBRE NO SE DA POR COBRADA ────────────────────────────────
-- Lo que la linea vieja protegia, y lo que un arreglo a lo bruto rompe: en
-- septiembre la gratificacion de diciembre no existe todavia, asi que los meses
-- de julio a septiembre tienen que contar.
select cmp_ok(
  (fn_grati_trunca('00000000-0000-0000-0000-000000288004','2026-09-20')->>'monto')::numeric,
  '>', 300::numeric,
  'SETIEMBRE · no da por cobrada la de diciembre: paga julio, agosto y setiembre');

-- ── 5 · Y NO PAGA MAS QUE EL SEMESTRE ENTERO ────────────────────────────────
-- El techo. Si el arreglo se pasara al otro lado, esto lo caza.
select cmp_ok(
  (fn_grati_trunca('00000000-0000-0000-0000-000000288004','2026-09-20')->>'monto')::numeric,
  '<', 1062.75::numeric,
  'TECHO · y nunca mas de lo que vale el semestre completo');

select * from finish();
rollback;
