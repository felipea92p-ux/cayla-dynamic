-- ============================================================================
-- 175_el_calendario_de_pago_lo_ve_cualquiera_el_dinero_no.test.sql
-- ============================================================================
-- Defiende la 0234, que abre la LECTURA de `periodos_planilla` a cualquiera con
-- sesión para que la pantalla «Lo mío» sepa en qué periodo está.
--
-- LAS DOS MITADES, y aquí la segunda es la que importa de verdad:
--
--   · que una integrante SÍ pueda leer el calendario de pago —fechas y estado—,
--   · y que eso NO le haya abierto ninguna puerta al dinero.
--
-- Una política de RLS mal escrita no falla: deja pasar. Por eso la mitad de
-- abajo repite, desde esta migración, lo que la prueba 91 ya exigía desde julio:
-- ni una fila de salarios, ni la planilla por la puerta de atrás.
--
-- NOTA DE ENTORNO
--   `set_config('request.jwt.claim.sub', …)` sola NO activa la RLS de tabla: eso
--   mueve `auth.uid()`, que es lo que miran las funciones SECURITY DEFINER. Para
--   que la política actúe hay que cambiar además de ROL. Es el mismo montaje de
--   la prueba 91, de donde está copiado.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000017500', 'ZZ175', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000017501', 'IntegranteLab', 'Laboratorio',
        '00000000-0000-0000-0000-000000017500', 'integrante', 'test-hash',
        '00000000-0000-0000-0000-000000017509', '2025-01-02');
set session_replication_role = origin;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000175aa', '2026-06-29', '2026-07-28', 'pagado'),
  ('00000000-0000-0000-0000-0000000175bb', '2026-07-29', '2026-08-28', 'abierto');

-- Un salario, para que la mitad de abajo tenga algo que NO ver.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000017501', 'colibri', 1200, '2025-01-02');

-- ── Es una integrante: ni admin, ni líder, ni encargada ─────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000017509', true);

-- ── 1-3 · Lo que SÍ puede: saber en qué periodo está ────────────────────────
set role authenticated;
create temp table _periodos as select count(*)::int as n from periodos_planilla;
create temp table _abierto as
  select fecha_ini, fecha_fin from periodos_planilla where estado = 'abierto';
create temp table _salarios as select count(*)::int as n from asignaciones_salario;
reset role;

select is((select n from _periodos), 2,
  'INTEGRANTE · ve el calendario de pago (antes de la 0234 veía cero)');

select is((select fecha_ini::text from _abierto), '2026-07-29',
  'INTEGRANTE · y ve dónde EMPIEZA el periodo abierto — el 29, que es lo que su pantalla necesita');

select is((select fecha_fin::text from _abierto), '2026-08-28',
  'INTEGRANTE · y dónde termina: el 28, no el fin de mes');

-- ── 4-5 · Lo que NO: el dinero sigue cerrado ────────────────────────────────
-- Si esto se cayera, la 0234 habría abierto algo que no venía a abrir.
select is((select n from _salarios), 0,
  'INTEGRANTE · sigue sin ver ni una fila de salarios: el calendario no es el dinero');

select throws_ok(
  $$ select fn_planilla_calcular('2026-07-29','2026-08-28') $$,
  null, null,
  'INTEGRANTE · y la planilla sigue negándose, que es la misma información por otra puerta');

select * from finish();
rollback;
