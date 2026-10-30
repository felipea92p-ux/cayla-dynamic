-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 448_el_periodo_de_prueba_se_pacta_por_persona.test.sql — la 0556
-- ============================================================================
-- Acortar el periodo de prueba es renunciar a un derecho de CAYLA, así que la
-- puerta tiene que ser estrecha. Esta prueba fija:
--   1. QUIÉN: la dirección y DO pactan; la líder de equipo y la integrante, no.
--   2. QUÉ: de 0 a 89 días o «la ley» (NULL); con motivo; solo para planilla y
--      solo para quien sigue activa. Un valor fuera de rango no entra nunca.
--   3. EL RASTRO: cada cambio deja quién, de qué a qué y por qué; pedir lo que ya
--      rige no escribe nada.
--   4. EL CANDADO: ni un UPDATE ni un INSERT armados a mano desde el navegador
--      se saltan la puerta; el SQL Editor (dueño de la base) sí puede.
--   5. NADA CAMBIA SOLO: toda persona nace con «rige la ley» (NULL).
-- ============================================================================
begin;
select plan(23);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000448a01', 'ZZ448', 'Sede de laboratorio 448', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000004481a', 'integrante-448@local'),
  ('00000000-0000-0000-0000-00000004481b', 'lider-equipo-448@local'),
  ('00000000-0000-0000-0000-00000004481c', 'do-448@local'),
  ('00000000-0000-0000-0000-00000004481d', 'admin-448@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, fecha_cese, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000448011', 'Integrante', 'Comun',  '00000000-0000-0000-0000-000000448a01', 'integrante',      'activo', 'x', '00000000-0000-0000-0000-00000004481a', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000448012', 'Lider',      'Equipo', '00000000-0000-0000-0000-000000448a01', 'supervisor_sede', 'activo', 'x', '00000000-0000-0000-0000-00000004481b', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000448013', 'Lider',      'DO',     '00000000-0000-0000-0000-000000448a01', 'lider_do',        'activo', 'x', '00000000-0000-0000-0000-00000004481c', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000448014', 'Direccion',  'Admin',  '00000000-0000-0000-0000-000000448a01', 'admin',           'activo', 'x', '00000000-0000-0000-0000-00000004481d', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000448015', 'Nueva',      'Planilla','00000000-0000-0000-0000-000000448a01','integrante',      'activo', 'x', null, '2026-10-25', null, 'planilla'),
  ('00000000-0000-0000-0000-000000448016', 'Ya',         'Cesada', '00000000-0000-0000-0000-000000448a01', 'integrante',      'inactivo','x', null, '2026-10-01', '2026-10-05', 'planilla'),
  ('00000000-0000-0000-0000-000000448017', 'Una',        'Practicante','00000000-0000-0000-0000-000000448a01','integrante',   'activo', 'x', null, '2026-10-01', null, 'practicante');
set session_replication_role = origin;

-- ── 0 · Lo instalado ────────────────────────────────────────────────────────
select is((select count(*)::int from personas where prueba_pactada_dias is not null), 0,
  'NADA CAMBIA SOLO · toda persona nace con «rige la ley» (NULL)');

select throws_ok(
  $$ update personas set prueba_pactada_dias = 90 where id = '00000000-0000-0000-0000-000000448015' $$,
  '23514', null, 'La base no admite 90 días: de tres meses para arriba rige la ley');
select throws_ok(
  $$ update personas set prueba_pactada_dias = -1 where id = '00000000-0000-0000-0000-000000448015' $$,
  '23514', null, 'Ni un valor negativo');

-- ── 1 · Quién ───────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004481a', true);
set role authenticated;
select throws_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448015', 30, 'Pactado por escrito') $$,
  'Solo la dirección o Desarrollo Organizacional puede pactar el periodo de prueba.',
  'LA INTEGRANTE no pacta periodos de prueba');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004481b', true);
set role authenticated;
select throws_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448015', 30, 'Pactado por escrito') $$,
  'Solo la dirección o Desarrollo Organizacional puede pactar el periodo de prueba.',
  'LA LÍDER DE EQUIPO tampoco: acortar la prueba es renunciar a un derecho de CAYLA');
reset role;
select is((select count(*)::int from correcciones_auditoria where campo_modificado = 'personas.prueba_pactada_dias'), 0,
  'Los rechazos no dejan rastro');

-- ── 2 · Qué ─────────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004481c', true);
set role authenticated;

select lives_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448015', 30, 'Pactado por escrito en su contrato') $$,
  'DO pacta 30 días para la persona nueva');
reset role;
select is((select prueba_pactada_dias::int from personas where id = '00000000-0000-0000-0000-000000448015'), 30,
  'Quedó en 30 días');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004481d', true);
set role authenticated;
select lives_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448015', 0, 'Reingreso: ya cumplió su periodo de prueba') $$,
  'La dirección la deja sin periodo de prueba (0 días)');
reset role;
select is((select prueba_pactada_dias::int from personas where id = '00000000-0000-0000-0000-000000448015'), 0,
  'Quedó en 0: sin periodo de prueba');

set role authenticated;
select throws_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448015', 90, 'Casi tres meses') $$,
  'El periodo de prueba pactado va de 0 a 89 días (llegó 90). De tres meses para arriba rige la ley.',
  'Más de 89 días no entra: de tres meses para arriba rige la ley');
select throws_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448015', 15, 'ab') $$,
  'Escribe el motivo: es lo que explica un periodo de prueba distinto del de la ley.',
  'Sin motivo no hay pacto');
select throws_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448016', 15, 'Una cesada ya no cambia') $$,
  'No se puede cambiar el periodo de prueba de una persona ya cesada: su liquidación se calculó con el anterior.',
  'No se toca a quien ya cesó: su liquidación se calculó con lo que regía');
select throws_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448017', 15, 'No es una relación laboral') $$,
  'El periodo de prueba solo se pacta para quien está en planilla: es una cláusula del contrato de trabajo (art. 10, D.S. 003-97-TR).',
  'LA PRACTICANTE no tiene periodo de prueba: su convenio no es un contrato de trabajo');
select throws_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448999', 15, 'Nadie con ese id') $$,
  'Persona inválida.', 'Una persona que no existe se dice');

-- Volver a la ley: NULL.
select lives_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448015', null, 'Vuelve a regir la ley: no se firmó el pacto') $$,
  'Se puede volver a «rige la ley» (NULL)');
reset role;
select is((select prueba_pactada_dias from personas where id = '00000000-0000-0000-0000-000000448015'), null,
  'Volvió a NULL');

-- ── 3 · El rastro ───────────────────────────────────────────────────────────
-- OJO: `corregido_at` es `now()`, que vale lo mismo en toda la transacción de la prueba: tres cambios
-- seguidos empatan y su orden sale al azar. Se comprueba QUÉ cambios hay, no en qué orden (en
-- producción cada cambio va en su propia transacción y no empatan).
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000448015'
      and campo_modificado = 'personas.prueba_pactada_dias'
      and (valor_anterior, valor_nuevo) in (values ('la ley (3 meses)', '30 días'),
                                                   ('30 días', '0 días'),
                                                   ('0 días', 'la ley (3 meses)'))),
  3, 'RASTRO · los tres cambios, cada uno de qué a qué');
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000448015'
      and campo_modificado = 'personas.prueba_pactada_dias'
      and corregido_por = '00000000-0000-0000-0000-000000448013'
      and motivo = 'Pactado por escrito en su contrato'),
  1, 'RASTRO · el primero lo hizo DO, con su motivo');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004481d', true);
select lives_ok(
  $$ select fn_set_prueba_pactada('00000000-0000-0000-0000-000000448015', null, 'Lo mismo otra vez') $$,
  'Pedir lo que ya rige no falla');
reset role;
select is((select count(*)::int from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000448015' and campo_modificado = 'personas.prueba_pactada_dias'), 3,
  'RASTRO · y no suma una fila: un cambio vacío no deja huella');

-- ── 4 · El candado ──────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004481c', true);
set role authenticated;
select throws_ok(
  $$ update personas set prueba_pactada_dias = 10 where id = '00000000-0000-0000-0000-000000448015' $$,
  'El periodo de prueba pactado se cambia con fn_set_prueba_pactada, no con una escritura directa.',
  'BLOQUEADO · un UPDATE directo de DO (el PATCH armado a mano)');
reset role;

-- El dueño de la base (SQL Editor) sí puede: los límites valen igual.
update personas set prueba_pactada_dias = 10 where id = '00000000-0000-0000-0000-000000448015';
select is((select prueba_pactada_dias::int from personas where id = '00000000-0000-0000-0000-000000448015'), 10,
  'EL SQL EDITOR (dueño de la base) sí puede cambiarlo');

select * from finish();
rollback;
