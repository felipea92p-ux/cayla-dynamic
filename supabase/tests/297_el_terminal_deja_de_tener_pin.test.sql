-- ============================================================================
-- 297_el_terminal_deja_de_tener_pin.test.sql
-- ============================================================================
-- Marcar sin PIN era la decisión desde julio de 2026 («se prioriza que marcar
-- sea instantáneo; el control real es que la Mac mini está a la vista de todo
-- el equipo»), reafirmada por Felipe el 2026-09-04. Pero estaba APAGADA, no
-- retirada — y apuntando al revés de la decisión:
--
--   `terminales.requiere_pin` nació `not null default TRUE` (0012), y los
--   terminales se dan de alta a mano sin mencionar esa columna. La próxima Mac
--   mini vinculada habría nacido pidiendo un PIN de cuatro dígitos por persona.
--   No falla al pegar una migración ni al desplegar: falla el día que abre una
--   sede.
--
-- Esta prueba fija las dos mitades de la 0375, que se rompen por separado:
--   · el default y las filas en false — la trampa desactivada
--   · la vista sin `pin_hash` — el hash deja de viajar a las Mac mini
--
-- Y fija lo que el drop+create de la vista PUDO haberse llevado y no se llevó:
-- los grants, `security_invoker = false` y el filtro por sede. Es el mismo
-- descuido que la 0363 tuvo que reparar en `fn_provisiones`, y acá habría dejado
-- a las cuatro sedes sin poder fichar.
-- ============================================================================
begin;
select plan(8);

-- ── 1-2 · La trampa del default, desactivada ────────────────────────────────
select is(
  (select column_default from information_schema.columns
    where table_name = 'terminales' and column_name = 'requiere_pin'),
  'false',
  'EL DEFAULT · un terminal nuevo nace SIN pedir PIN');

select is(
  (select count(*)::int from terminales where requiere_pin),
  0,
  'NINGUNO PIDE · ningún terminal existente quedó exigiendo PIN');

-- ── 3-4 · El hash deja de viajar al navegador ───────────────────────────────
select is_empty(
  $$ select 1 from information_schema.columns
      where table_name = 'terminal_roster' and column_name = 'pin_hash' $$,
  'SIN EL HASH · terminal_roster ya no expone pin_hash');

select is(
  (select count(*)::int from information_schema.columns
    where table_name = 'terminal_roster'),
  5,
  'CINCO COLUMNAS · id, nombres, apellidos y las dos de la sede');

-- ── 5-7 · Lo que el drop+create pudo llevarse ───────────────────────────────
-- Estas tres son el motivo por el que esta prueba existe. Ninguna falla al
-- pegar la migración: fallan a la mañana siguiente, con la sede sin fichar.
select ok(
  (select reloptions::text like '%security_invoker=false%'
     from pg_class where relname = 'terminal_roster'),
  'SIGUE SIENDO DEL DUEÑO · sin security_invoker=false el kiosco no vería a nadie');

select ok(
  has_table_privilege('authenticated', 'terminal_roster', 'select'),
  'EL GRANT VOLVIÓ · el terminal puede leer su lista (lo que la 0363 tuvo que reparar en fn_provisiones)');

select ok(
  not has_table_privilege('anon', 'terminal_roster', 'select'),
  'Y ANON NO · quien no inició sesión sigue sin ver la lista');

-- ── 8 · La vista sigue haciendo su trabajo ──────────────────────────────────
-- El filtro por sede vive DENTRO de la vista desde que la 0291 borró la policy.
-- Si el create nuevo lo hubiera perdido, el kiosco vería a todo el mundo.
select ok(
  (select pg_get_viewdef('terminal_roster'::regclass)::text
     like '%fn_sede_actual_terminal%'),
  'EL FILTRO POR SEDE SIGUE DENTRO · la vista no perdió su autorización al recrearse');

select * from finish();
rollback;
