-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 214_cambiar_el_regimen_mueve_el_descuento.test.sql
-- ============================================================================
-- La 0261 versionó a qué régimen de pensión pertenece cada persona, y
-- `fn_planilla_calcular` pasó a leer el TRAMO vigente. Pero la pantalla de datos
-- personales siguió llamando a `fn_set_regimen_pension`, que escribe solo
-- `personas.regimen_pension` — la columna que ya no manda cuando hay tramo.
--
-- Resultado: a quien ya tenía régimen cuando se pegó la 0261, cambiárselo desde
-- la pantalla NO le movía el descuento. Y la pantalla decía «se aplicará desde
-- el próximo cálculo». A quien no tenía tramo, sí funcionaba. La misma acción,
-- dos resultados, sin nada que dijera cuál te tocaba.
--
-- Esta prueba ataca `fn_cambiar_regimen_pension`, que es la que la pantalla debe
-- llamar a partir de la 0277, y comprueba las tres cosas que le faltaban para
-- poder reemplazar a la vieja: que deje rastro, que acepte «todavía no se sabe»,
-- y que valide contra `tasas_pension` en vez de contra una lista escrita a mano.
-- Y comprueba que la puerta vieja ya no deja pasar.
-- ============================================================================
begin;
select plan(17);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000027700', 'ZZREG', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000027701', 'RegAdmin', 'Lab',
        '00000000-0000-0000-0000-000000027700', 'admin', 'x',
        '00000000-0000-0000-0000-0000000277aa', '2024-01-01');
set session_replication_role = origin;

-- GRUPO A: la tenía cuando se pegó la 0261, así que tiene tramo abierto.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, regimen_pension)
values ('00000000-0000-0000-0000-000000027702', 'RegConTramo', 'Lab',
        '00000000-0000-0000-0000-000000027700', 'x', '2024-01-01', 'integra');
insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde, nota)
values ('00000000-0000-0000-0000-000000027702', 'integra', '2024-01-01', 'Relleno simulado 0261');

-- GRUPO B: ingresó después de la 0261, así que nadie le escribió tramo.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, regimen_pension)
values ('00000000-0000-0000-0000-000000027703', 'RegSinTramo', 'Lab',
        '00000000-0000-0000-0000-000000027700', 'x', '2026-08-01', 'onp');

-- Un periodo ya pagado, para comprobar que el freno de la 0203 sigue frenando.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at)
values ('00000000-0000-0000-0000-0000000277ee', '2026-06-29', '2026-07-28', 'pagado', now());

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000277aa', true);


-- ── 1 a 5 · Grupo A: el cambio llega al tramo, y deja rastro ────────────────

select lives_ok(
  $$ select fn_cambiar_regimen_pension(
       '00000000-0000-0000-0000-000000027702'::uuid, 'onp', '2026-08-29'::date, 'Se cambió de AFP') $$,
  'Cambiar el régimen de quien tiene tramo abierto no revienta');

select is(
  (select regimen from asignaciones_regimen_pension
    where persona_id = '00000000-0000-0000-0000-000000027702' and vigente_hasta is null),
  'onp',
  'El tramo VIGENTE dice el régimen nuevo — que es lo que lee la planilla');

select is(
  (select vigente_hasta from asignaciones_regimen_pension
    where persona_id = '00000000-0000-0000-0000-000000027702' and regimen = 'integra'),
  '2026-08-28'::date,
  'El tramo anterior queda cerrado la víspera, sin hueco ni solape');

select is(
  (select regimen_pension from personas where id = '00000000-0000-0000-0000-000000027702'),
  'onp',
  'La ficha queda en sintonía con el tramo: no vuelve a divergir');

select ok(
  exists (select 1 from correcciones_auditoria
           where persona_id = '00000000-0000-0000-0000-000000027702'
             and campo_modificado = 'asignaciones_regimen_pension.regimen'
             and valor_anterior = 'integra' and valor_nuevo = 'onp'
             and motivo like '%13.00 por ciento%'),
  'Deja fila de auditoría, y el motivo nombra la tasa que va a regir — no solo el nombre del régimen');


-- ── 6 · Un guardado que no cambia nada no ensucia la auditoría ──────────────

select fn_cambiar_regimen_pension(
  '00000000-0000-0000-0000-000000027702'::uuid, 'onp', '2026-09-29'::date, null);

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000027702'
      and campo_modificado = 'asignaciones_regimen_pension.regimen'),
  1,
  'Volver a guardar el MISMO régimen no abre tramo ni escribe otra fila de auditoría');


-- ── 7 y 8 · «Todavía no se sabe» sigue siendo un estado posible ─────────────

select lives_ok(
  $$ select fn_cambiar_regimen_pension(
       '00000000-0000-0000-0000-000000027702'::uuid, null, '2026-10-29'::date, null) $$,
  'Quitar el régimen es legal: alguien puede ingresar sin declarar su AFP');

select ok(
  not exists (select 1 from asignaciones_regimen_pension
               where persona_id = '00000000-0000-0000-0000-000000027702' and vigente_hasta is null)
  and (select regimen_pension from personas where id = '00000000-0000-0000-0000-000000027702') is null,
  'Sin régimen: cierra el tramo y NO abre otro, así que el cálculo cae a la tasa genérica');


-- ── 9 · Grupo B: quien no tenía tramo ahora lo estrena ──────────────────────

select fn_cambiar_regimen_pension(
  '00000000-0000-0000-0000-000000027703'::uuid, 'prima', '2026-08-29'::date, null);

select is(
  (select count(*)::int from asignaciones_regimen_pension
    where persona_id = '00000000-0000-0000-0000-000000027703' and vigente_hasta is null),
  1,
  'A quien ingresó después de la 0261 se le escribe su primer tramo: deja de depender del respaldo');


-- ── 10 a 12 · Lo que tiene que negarse ──────────────────────────────────────

select throws_ok(
  $$ select fn_cambiar_regimen_pension(
       '00000000-0000-0000-0000-000000027703'::uuid, 'afp_inventada', '2026-11-29'::date, null) $$,
  null,
  null,
  'Un régimen que no está en `tasas_pension` se rechaza — la lista verdadera vive en la tabla');

select throws_ok(
  $$ select fn_cambiar_regimen_pension(
       '00000000-0000-0000-0000-000000027703'::uuid, 'onp', null, null) $$,
  null,
  null,
  'Sin fecha no hay cambio: un tramo sin principio no se puede leer a una fecha');

select throws_ok(
  $$ select fn_cambiar_regimen_pension(
       '00000000-0000-0000-0000-000000027703'::uuid, 'onp', '2026-07-15'::date, null) $$,
  null,
  null,
  'Una fecha dentro de un periodo YA PAGADO se niega: movería lo que ese mes calculó');


-- ── 13 · La puerta vieja ya no deja pasar ───────────────────────────────────

select throws_ok(
  $$ select fn_set_regimen_pension(
       '00000000-0000-0000-0000-000000027703'::uuid, 'habitat') $$,
  null,
  null,
  'fn_set_regimen_pension falla RUIDOSO en vez de escribir la columna que ya no manda');


-- ── 14 · El detector encuentra a quien quedó divergente ─────────────────────
-- Se simula el daño de la puerta vieja: la columna se mueve, el tramo no.

update personas set regimen_pension = 'habitat'
 where id = '00000000-0000-0000-0000-000000027703';

select is(
  (select count(*)::int from fn_regimen_pension_divergentes()
    where persona_id = '00000000-0000-0000-0000-000000027703'),
  1,
  'fn_regimen_pension_divergentes() caza a quien tiene la ficha diciendo una cosa y el descuento haciendo otra');


-- ── LA RLS DE ESTA TABLA NO LA COMPROBABA NADIE ────────────────────────────
-- `asignaciones_regimen_pension` dice a qué régimen pertenece cada persona y
-- desde cuándo — el dato del que sale su descuento. Tiene policy desde la 0261
-- y hasta hoy ninguna prueba cambiaba de usuario: las catorce de arriba corren
-- enteras como admin, así que si la policy se rompiera no se enteraría ninguna.
--
-- ⚠ `set local role authenticated` NO es decorativo — la misma advertencia del
-- test 198. pgTAP corre como `postgres`, superusuario, y SE SALTA LA RLS.
--
-- OJO CON LO QUE FIJA LA PRIMERA: aquí la regla es «DO y nadie más», ni siquiera
-- la propia persona ve su tramo. Es distinto de `contratos_generados` y de
-- `educacion_comprobantes`, que sí dejan a cada quien ver lo suyo. Si algún día
-- se decide que aquí también, esta prueba es la que hay que cambiar — a
-- propósito y no por accidente, que es de lo que se trata.
set session_replication_role = replica;
update personas set rol = 'integrante', auth_user_id = '00000000-0000-0000-0000-0000000277bb'
 where id = '00000000-0000-0000-0000-000000027702';
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000277bb', true);

set local role authenticated;

select is(
  (select count(*)::int from asignaciones_regimen_pension),
  0,
  'RLS · una integrante no ve ningún tramo de régimen, ni siquiera el suyo');

-- `authenticated` TIENE el grant de INSERT sobre esta tabla (viene por defecto
-- en Supabase). Lo único que lo frena es que la policy sea `for select` y no
-- exista ninguna otra. La fila va COMPLETA a propósito: si le faltara una
-- columna not-null reventaría por 23502 y la prueba «pasaría» sin que la policy
-- hiciera nada.
select throws_ok(
  $$ insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde)
     values ('00000000-0000-0000-0000-000000027702', 'onp', '2027-01-01') $$,
  '42501', NULL,
  'RLS · y no puede escribirse un régimen a sí misma, aunque el grant se lo permita');

-- La otra mitad: la policy protege, no tapa. DO sí los ve, y preguntando con el
-- mismo rol de base con el que preguntaría el navegador.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000277aa', true);
select ok(
  (select count(*) from asignaciones_regimen_pension) > 0,
  'RLS · pero DO sí los ve: la policy protege, no tapa');

reset role;


select * from finish();
rollback;
