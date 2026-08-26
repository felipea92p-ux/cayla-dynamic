-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 239_un_retroactivo_dice_de_que_mes_viene.test.sql
-- ============================================================================
-- Cuando algo se corrige después de pagar un mes, el mes cerrado no se toca: se
-- paga la diferencia en el siguiente, como un movimiento. Hasta la 0305 nada
-- decía de QUÉ mes venía esa corrección, así que no se podía comprobar que se
-- hubieran pagado todas ni explicarle a nadie por qué su neto subió.
--
-- Lo que esta prueba fija no es solo que el dato se guarde: es que un origen MAL
-- puesto se rechace. Un origen equivocado es peor que ninguno, porque haría
-- creer que una diferencia quedó saldada cuando vino de otro sitio.
--
-- Y fija que quede UNA sola firma de fn_agregar_movimiento. Antes había dos, y
-- agregar el parámetro con default sobre una de ellas habría hecho ambigua la
-- llamada de seis argumentos — el fallo que la 0301 tuvo que arreglar en
-- fn_vacaciones_por_vencer.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000023900', 'ZZRET', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000023901', 'RetAdmin', 'Lab',
        '00000000-0000-0000-0000-000000023900', 'admin', 'x',
        '00000000-0000-0000-0000-0000000239ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000023902', 'RetPersona', 'Lab',
        '00000000-0000-0000-0000-000000023900', 'x', '2024-01-01');

-- Tres periodos: uno viejo YA PAGADO, uno abierto donde se paga el retroactivo,
-- y otro abierto para probar que un origen sin pagar se rechaza.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at) values
  ('00000000-0000-0000-0000-0000002390a1', '2026-03-29', '2026-04-28', 'pagado', now()),
  ('00000000-0000-0000-0000-0000002390b1', '2026-04-29', '2026-05-28', 'abierto', null),
  ('00000000-0000-0000-0000-0000002390c1', '2026-05-29', '2026-06-28', 'abierto', null);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000239ff', true);


-- ── 1 · Una sola firma ──────────────────────────────────────────────────────

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_agregar_movimiento'),
  1,
  'Queda UNA sola fn_agregar_movimiento: dos firmas con default harían ambigua la llamada');


-- ── 2 y 3 · El caso normal sigue igual, sin decir origen ────────────────────

select lives_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-0000002390b1',
       '00000000-0000-0000-0000-000000023902', 'bono', 'Bono del mes', 50) $$,
  'Un movimiento normal se registra sin nombrar origen — la pantalla no cambia');

select is(
  (select periodo_origen_id from movimientos_planilla
    where persona_id = '00000000-0000-0000-0000-000000023902' and concepto = 'Bono del mes'),
  null,
  'Y su origen queda en NULL: no corrige nada, es de este mes');


-- ── 4 y 5 · El retroactivo de verdad ───────────────────────────────────────

select lives_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-0000002390b1',
       '00000000-0000-0000-0000-000000023902', 'bono',
       'Marca del 10/04 registrada tarde', 11.55, null,
       '00000000-0000-0000-0000-0000002390a1') $$,
  'Un retroactivo de un mes ya pagado se acepta');

select is(
  (select periodo_origen_id from movimientos_planilla
    where persona_id = '00000000-0000-0000-0000-000000023902'
      and concepto = 'Marca del 10/04 registrada tarde'),
  '00000000-0000-0000-0000-0000002390a1'::uuid,
  'Y queda escrito de qué mes viene, sin depender de lo que diga el concepto');


-- ── 6, 7 y 8 · Los tres orígenes que hay que rechazar ──────────────────────

select throws_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-0000002390b1',
       '00000000-0000-0000-0000-000000023902', 'bono', 'Origen igual', 10, null,
       '00000000-0000-0000-0000-0000002390b1') $$,
  null, null,
  'El origen no puede ser el mismo periodo: eso es un movimiento normal, no un retroactivo');

select throws_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-0000002390b1',
       '00000000-0000-0000-0000-000000023902', 'bono', 'Origen sin pagar', 10, null,
       '00000000-0000-0000-0000-0000002390c1') $$,
  null, null,
  'Un origen que todavía no se pagó se rechaza: si sigue abierto, se arregla en su mes');

-- El de junio es posterior al de mayo, así que además de estar abierto sería un
-- retroactivo del futuro. Se comprueba con uno pagado pero posterior.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at)
values ('00000000-0000-0000-0000-0000002390d1', '2026-06-29', '2026-07-28', 'pagado', now());

select throws_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-0000002390b1',
       '00000000-0000-0000-0000-000000023902', 'bono', 'Origen del futuro', 10, null,
       '00000000-0000-0000-0000-0000002390d1') $$,
  null, null,
  'Un origen POSTERIOR se rechaza aunque esté pagado: un retroactivo corrige el pasado');


select * from finish();
rollback;
