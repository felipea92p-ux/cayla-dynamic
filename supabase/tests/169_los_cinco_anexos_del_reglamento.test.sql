-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 169_los_cinco_anexos_del_reglamento.test.sql
-- ============================================================================
-- El catálogo de documentos institucionales y quién puede tocarlo.
--
-- Lo que fija esta prueba:
--   · Están los seis documentos, y el Reglamento conserva el primer lugar.
--   · Piden constancia los tres que le imponen algo al equipo, y NO la piden
--     los tres que no. El cargo de recepción es el caso que lo explica: es el
--     papel CON EL QUE se acusa el Reglamento, así que pedir su acuse sería
--     pedir el acuse del acuse.
--   · Desarrollo Organizacional puede añadir un documento nuevo desde la
--     pantalla — que es lo que la 0208 prometió y la 0215 hizo posible.
--   · Una integrante NO puede, aunque la tabla se lea desde cualquier sesión.
--   · Nadie puede BORRAR un tipo: un tipo borrado se lleva por delante las
--     constancias que el equipo ya firmó. Para retirarlo está `activo`.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000f1', 'ZZDOC', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000000f2', 'DoDocs', 'Lab', '00000000-0000-0000-0000-0000000000f1', 'lider_do',   'x', '00000000-0000-0000-0000-00000000ff02', '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000f3', 'IntDocs', 'Lab', '00000000-0000-0000-0000-0000000000f1', 'integrante', 'x', '00000000-0000-0000-0000-00000000ff03', '2020-01-01');
set session_replication_role = origin;

-- ── El catálogo ─────────────────────────────────────────────────────────────
select is((select count(*)::int from documentos_tipos where activo), 6,
          'CATÁLOGO · están los seis documentos del expediente');

select is((select codigo from documentos_tipos where activo order by orden limit 1), 'rit',
          'CATÁLOGO · el Reglamento va primero, y ningún anexo lo desplaza');

select is((select count(*)::int from documentos_tipos where activo and requiere_acuse), 3,
          'CONSTANCIA · la piden tres: el Reglamento, la política de hostigamiento y la resolución');

select is((select requiere_acuse from documentos_tipos where codigo = 'cargo_recepcion'), false,
          'CONSTANCIA · el cargo de recepción no se acusa a sí mismo');

select is((select requiere_acuse from documentos_tipos where codigo = 'manual_disciplinario'), false,
          'CONSTANCIA · el Manual no le impone nada a la colaboradora: no se le pide constancia');

-- ── Quién puede administrarlo ───────────────────────────────────────────────
set local role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ff02', true);
select lives_ok(
  $$ insert into documentos_tipos (codigo, nombre, orden, requiere_acuse)
     values ('zz_prueba_do', 'Documento de laboratorio', 900, false) $$,
  'ALTA · Desarrollo Organizacional puede añadir un documento sin una migración');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ff03', true);
select throws_ok(
  $$ insert into documentos_tipos (codigo, nombre, orden, requiere_acuse)
     values ('zz_prueba_integrante', 'No debería entrar', 901, false) $$,
  null, null,
  'ALTA · una integrante no puede añadir documentos al catálogo');

-- Leer sí puede: el catálogo no es secreto, y la pantalla lo necesita.
select ok((select count(*) from documentos_tipos) > 0,
          'LECTURA · una integrante sí puede leer el catálogo');

-- ── Y nadie borra ───────────────────────────────────────────────────────────
-- Sin política de DELETE, la orden no falla: RLS le esconde todas las filas y
-- borra cero. Por eso se comprueba el resultado y no una excepción — esperar un
-- error aquí daría una prueba en verde por el motivo equivocado.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ff02', true);
delete from documentos_tipos where codigo = 'zz_prueba_do';
select is((select count(*)::int from documentos_tipos where codigo = 'zz_prueba_do'), 1,
          'BORRADO · ni Desarrollo Organizacional borra un tipo: para retirarlo está `activo`');

reset role;
select * from finish();
rollback;
