-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 408_las_faltas_se_eligen_por_nombre_corto.test.sql
-- ============================================================================
-- La 0514: cada falta del catálogo tiene un nombre corto para elegirla, y el
-- memo de conducta llega a la Info de la persona con la falta que cita.
-- Lo que fija esta prueba:
--   · Ninguna falta queda sin nombre corto, y dos no comparten el mismo.
--   · El nombre corto se puede corregir; el texto legal sigue sin poder tocarse.
--   · `fn_mi_memo` le dice a la persona QUÉ falta cometió, con el texto de la
--     versión del RIT que su documento cita, y cuándo se supo. A un memo de
--     tardanzas no le inventa ninguna.
--   · Y no le abre a nadie el memo de otra persona.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000c0f01', 'ZZNC1', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000c0f11', 'Gerencia',   'Lab', '00000000-0000-0000-0000-0000000c0f01', 'admin',      'x', '00000000-0000-0000-0000-0000000c0fa1', '2020-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-0000000c0f17', 'Integrante', 'Lab', '00000000-0000-0000-0000-0000000c0f01', 'integrante', 'x', '00000000-0000-0000-0000-0000000c0fa7', '2023-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-0000000c0f18', 'Otra',       'Lab', '00000000-0000-0000-0000-0000000c0f01', 'integrante', 'x', '00000000-0000-0000-0000-0000000c0fa8', '2023-01-01', 'activo', 'planilla');
set session_replication_role = origin;

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true);
$$;

-- ── LOS NOMBRES CORTOS ──────────────────────────────────────────────────────
select is((select count(*)::int from faltas_catalogo c
            where not exists (select 1 from faltas_rotulos r
                               where (r.rit_version, r.numeral, r.literal) = (c.rit_version, c.numeral, c.literal))), 0,
  'NOMBRES · ninguna falta del catálogo queda sin nombre corto');
select is((select rotulo from faltas_rotulos where rit_version = 4.0 and numeral = '53.2' and literal = 'h'), 'Trato descortés',
  'NOMBRES · el 53.2 h) se elige como «Trato descortés»');
select throws_ok($$ update faltas_rotulos set rotulo = 'Trato descortés' where numeral = '53.2' and literal = 'g' $$,
  '23505', null, 'NOMBRES · dos faltas de la misma versión no comparten nombre: al elegir no se distinguirían');
select throws_ok($$ insert into faltas_rotulos values (4.0, '53.1', 'z', 'Algo que no existe') $$,
  '23503', null, 'NOMBRES · no se nombra una falta que el Reglamento no tiene');
select lives_ok($$ update faltas_rotulos set rotulo = 'Maltrato a una clienta' where numeral = '53.2' and literal = 'h' $$,
  'NOMBRES · el nombre corto SÍ se corrige: es cómo se elige, no qué se cita');
select throws_like($$ update faltas_catalogo set texto = 'otra cosa' where numeral = '53.2' and literal = 'h' $$,
  '%no se edita%', 'NOMBRES · y el texto legal sigue cerrado');

-- ── EL MEMO EN SU INFO ──────────────────────────────────────────────────────
-- Un documento de conducta y uno de tardanzas, los dos entregados.
insert into expediente_disciplinario (id, persona_id, tipo_causal, nivel, estado, hechos, periodo_desde, periodo_hasta,
  falta_rit_version, falta_numeral, falta_literal, conocido_el,
  firmante_id, firmado_at, correlativo, medio_entrega, entregado_at, creado_por) values
  ('00000000-0000-0000-0000-0000000c0fd1', '00000000-0000-0000-0000-0000000c0f17', 'conducta', 'amonestacion', 'entregado',
   '[{"fecha":"2026-09-20","relato":"Le respondió de mala manera a una clienta delante de otras dos."}]', '2026-09-20', '2026-09-20',
   4.0, '53.2', 'h', '2026-09-21',
   '00000000-0000-0000-0000-0000000c0f11', now(), 'LAB/NC-1', 'fisico', now(), '00000000-0000-0000-0000-0000000c0f11');
insert into expediente_disciplinario (id, persona_id, tipo_causal, nivel, estado, hechos, periodo_desde, periodo_hasta,
  firmante_id, firmado_at, correlativo, medio_entrega, entregado_at, creado_por) values
  ('00000000-0000-0000-0000-0000000c0fd2', '00000000-0000-0000-0000-0000000c0f17', 'tardanza', 'amonestacion', 'entregado',
   '[{"fecha":"2026-09-02","minutos":12},{"fecha":"2026-09-09","minutos":8},{"fecha":"2026-09-16","minutos":20}]', '2026-09-01', '2026-09-30',
   '00000000-0000-0000-0000-0000000c0f11', now(), 'LAB/NC-2', 'fisico', now(), '00000000-0000-0000-0000-0000000c0f11');

select pg_temp.como('00000000-0000-0000-0000-0000000c0fa7');   -- la persona
select is(fn_mi_memo('00000000-0000-0000-0000-0000000c0fd1')->'falta'->>'literal', 'h',
  'INFO · la persona lee qué falta cometió, no «la que consta en su expediente»');
select is(fn_mi_memo('00000000-0000-0000-0000-0000000c0fd1')->'falta'->>'texto',
  (select texto from faltas_catalogo where rit_version = 4.0 and numeral = '53.2' and literal = 'h'),
  'INFO · con el texto del RIT que su documento cita');
select is(fn_mi_memo('00000000-0000-0000-0000-0000000c0fd1')->>'conocido_el', '2026-09-21',
  'INFO · y cuándo supo la empresa del hecho (52.6)');
select is(fn_mi_memo('00000000-0000-0000-0000-0000000c0fd2')->'falta', 'null'::jsonb,
  'INFO · a un memo de tardanzas no se le inventa una falta de conducta');

select pg_temp.como('00000000-0000-0000-0000-0000000c0fa8');   -- otra persona
select is(fn_mi_memo('00000000-0000-0000-0000-0000000c0fd1'), null,
  'INFO · y nadie más abre el memo de ella');

select * from finish();
rollback;
