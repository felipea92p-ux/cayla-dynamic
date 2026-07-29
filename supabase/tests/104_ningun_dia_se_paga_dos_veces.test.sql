-- ============================================================================
-- 104_ningun_dia_se_paga_dos_veces.test.sql — El anti-solape de los periodos
-- ============================================================================
-- Un día que cae dentro de dos periodos de planilla se paga dos veces. No hay
-- aviso, no hay descuadre visible: las dos planillas salen "bien" por separado
-- y el dinero se va duplicado. Por eso el sistema tiene TRES candados, y hasta
-- la auditoría del 28-jul-2026 ninguno de los tres tenía prueba:
--
--   1) fn_crear_periodo encadena: el inicio es SIEMPRE el día siguiente al
--      último cierre. Ni hueco ni solape, y no se puede pedir otra cosa.
--   2) `periodos_sin_solape` — un EXCLUDE USING gist sobre el rango de fechas.
--      Es la red que atrapa cualquier escritura que no pase por la función.
--      El rango es INCLUSIVO ('[]'), así que compartir UN SOLO día ya lo viola:
--      ese detalle es justo el que un refactor descuidado rompería sin notarlo.
--   3) `periodos_etiqueta_unica` — un periodo por mes de cierre. El plus de
--      objetivos se etiqueta por el mes de fecha_fin: dos periodos que cierran
--      el mismo mes lo pagarían dos veces (fue el hallazgo que motivó la 0026).
--
-- Esta prueba verifica que los tres candados EXISTEN en el catálogo (si alguien
-- borra el constraint, la tabla sigue funcionando en silencio hasta el día del
-- doble pago) y que los tres MUERDEN de verdad.
--
-- Se prueba también el lado positivo —un periodo pegado al anterior entra sin
-- problema— para que la prueba no pueda pasar por un candado que rechaza todo.
--
-- Todo ocurre dentro de begin/rollback y en fechas de 2027, lejos de cualquier
-- dato real: al terminar no queda nada en la base.
-- ============================================================================
begin;
select plan(14);

-- ── Semilla: una sede y un admin de laboratorio ─────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000fb', 'ZZSOL', 'Sede de laboratorio', true);

-- session_replication_role = replica para saltar la FK contra auth.users:
-- el admin de laboratorio no tiene usuario real detrás.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000e1', 'AdminPeriodos', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000fb', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000000e9', '2020-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e9', true);


-- ── CANDADO 2 · el constraint está puesto ───────────────────────────────────
-- Si alguien lo borra, la tabla sigue aceptando escrituras y nadie se entera
-- hasta que dos planillas paguen el mismo día.

select is(
  (select count(*)::int from pg_constraint
   where conrelid = 'periodos_planilla'::regclass and conname = 'periodos_sin_solape'),
  1,
  'CATÁLOGO · el constraint periodos_sin_solape existe en la tabla');

select is(
  (select contype::text from pg_constraint
   where conrelid = 'periodos_planilla'::regclass and conname = 'periodos_sin_solape'),
  'x',
  'CATÁLOGO · y es de EXCLUSIÓN, no un check que se pueda esquivar');

-- El '[]' es lo que hace que compartir un solo día ya cuente como solape.
-- Con un rango '[)' el último día quedaría libre y ese día se pagaría dos veces.
select is(
  (select pg_get_constraintdef(oid) like '%''[]''%'
   from pg_constraint
   where conrelid = 'periodos_planilla'::regclass and conname = 'periodos_sin_solape'),
  true,
  'CATÁLOGO · el rango es inclusivo: compartir un solo día ya es solape');


-- ── CANDADO 3 · el índice de la etiqueta está puesto ────────────────────────

select is(
  (select count(*)::int from pg_index i join pg_class c on c.oid = i.indexrelid
   where i.indrelid = 'periodos_planilla'::regclass and c.relname = 'periodos_etiqueta_unica'),
  1,
  'CATÁLOGO · el índice periodos_etiqueta_unica existe en la tabla');

select is(
  (select i.indisunique from pg_index i join pg_class c on c.oid = i.indexrelid
   where i.indrelid = 'periodos_planilla'::regclass and c.relname = 'periodos_etiqueta_unica'),
  true,
  'CATÁLOGO · y es ÚNICO: un solo periodo por mes de cierre');


-- ── CANDADO 1 · fn_crear_periodo encadena y no admite otra cosa ─────────────

-- El primero elige su inicio (no hay nada antes de qué encadenarse)
select is(
  (fn_crear_periodo('2027-03-27', '2027-03-02')->>'fecha_ini')::date,
  '2027-03-02'::date,
  'PRIMERO · el primer periodo arranca donde se le indica');

-- El segundo NO lo elige: arranca el día siguiente al cierre anterior. Un día
-- después habría hueco (día sin pagar); un día antes, solape (día pagado dos veces).
select is(
  (fn_crear_periodo('2027-04-20')->>'fecha_ini')::date,
  '2027-03-28'::date,
  'ENCADENADO · el siguiente arranca justo al día siguiente del último cierre');

-- Pedir que arranque el mismo día en que cerró el anterior: ese día caería en
-- los dos periodos. Es el solape mínimo posible, y el más fácil de colar.
select throws_like(
  $$ select fn_crear_periodo('2027-05-14', '2027-04-20') $$,
  '%se encadena autom%',
  'SOLAPE DE UN DÍA · pedir que arranque el día del cierre anterior se rechaza');

-- Y el solape descarado tampoco pasa por otra puerta
select throws_like(
  $$ select fn_crear_periodo('2027-05-14', '2027-03-10') $$,
  '%se encadena autom%',
  'SOLAPE TOTAL · pedir un inicio metido dentro de los periodos ya creados se rechaza');


-- ── CANDADO 2 · la red por debajo, saltándose la función ────────────────────
-- Los periodos vivos son 02-mar→27-mar y 28-mar→20-abr. Las dos filas que
-- siguen cierran en mayo (etiqueta libre), así que lo único que pueden violar
-- es el anti-solape: si saltan, saltan por el motivo correcto.

select throws_ok(
  $$ insert into periodos_planilla (fecha_ini, fecha_fin)
     values ('2027-04-20', '2027-05-14') $$,
  '23P01',
  null,
  'INSERT DIRECTO · compartir un solo día (el 20-abr) lo frena el constraint');

select throws_ok(
  $$ insert into periodos_planilla (fecha_ini, fecha_fin)
     values ('2027-04-10', '2027-05-05') $$,
  '23P01',
  null,
  'INSERT DIRECTO · un solape por el medio también lo frena el constraint');

-- El lado positivo: pegado al anterior, sin compartir ningún día, entra. Sin
-- esto la prueba pasaría igual con un candado que rechazara absolutamente todo.
select lives_ok(
  $$ insert into periodos_planilla (fecha_ini, fecha_fin)
     values ('2027-04-21', '2027-05-16') $$,
  'CONTIGUO · el periodo que arranca al día siguiente entra sin problema');

-- La invariante que sostiene todo lo anterior, dicha de una vez
select is(
  (select count(*)::int
   from periodos_planilla a join periodos_planilla b on a.id < b.id
   where daterange(a.fecha_ini, a.fecha_fin, '[]') && daterange(b.fecha_ini, b.fecha_fin, '[]')),
  0,
  'INVARIANTE · no queda ni un día que pertenezca a dos periodos');


-- ── CANDADO 3 · dos cierres en el mismo mes duplicarían el plus ─────────────
-- Isla aparte (set-oct 2027) para que no haya solape de por medio: estas dos
-- filas no comparten ningún día, así que lo único que pueden violar es la
-- etiqueta única.
insert into periodos_planilla (fecha_ini, fecha_fin) values ('2027-09-10', '2027-10-05');

select throws_ok(
  $$ insert into periodos_planilla (fecha_ini, fecha_fin)
     values ('2027-10-06', '2027-10-31') $$,
  '23505',
  null,
  'ETIQUETA · dos periodos que cierran en oct-2027, sin solaparse, pagarían el plus dos veces');

select * from finish();
rollback;
