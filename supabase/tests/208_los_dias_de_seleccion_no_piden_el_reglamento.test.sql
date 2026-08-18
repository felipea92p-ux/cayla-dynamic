-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 208_los_dias_de_seleccion_no_piden_el_reglamento.test.sql
-- ============================================================================
-- Defiende la 0270: quien está en días de selección pagados (tipo_vinculo =
-- 'prueba') deja de contar en la población obligada del RIT/RISST/política
-- salarial/hostigamiento y de aparecer en la alerta de Disciplina — en las
-- CUATRO funciones que responden esa pregunta, no en una sola.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000cc0001', 'ZZSEL', 'Sede de laboratorio selección', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values ('cc000000-0000-0000-0000-0000000000c1',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'do.seleccion@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash,
                      auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-000000cc0002', 'DoSel', 'Lab',
        '00000000-0000-0000-0000-000000cc0001', 'lider_do', 'x',
        'cc000000-0000-0000-0000-0000000000c1', '2020-01-01', 'activo', 'planilla');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, estado, tipo_vinculo)
values
  ('00000000-0000-0000-0000-000000cc0003', 'ConContratoSel', 'Lab',
   '00000000-0000-0000-0000-000000cc0001', 'x', '2020-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000cc0004', 'EnSeleccion', 'Lab',
   '00000000-0000-0000-0000-000000cc0001', 'x', fn_hoy_lima(), 'activo', 'prueba');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'cc000000-0000-0000-0000-0000000000c1', true);

-- ── 1 · fn_poblacion_obligada ────────────────────────────────────────────────
select is(
  (select count(*)::int from fn_poblacion_obligada()
    where fn_poblacion_obligada = '00000000-0000-0000-0000-000000cc0004'),
  0, 'POBLACION · quien esta en dias de seleccion no cuenta como obligada');

select is(
  (select count(*)::int from fn_poblacion_obligada()
    where fn_poblacion_obligada = '00000000-0000-0000-0000-000000cc0003'),
  1, 'POBLACION · quien tiene contrato de trabajo si cuenta');

-- ── 2 · fn_acuses_documento — la hoja de Normas ─────────────────────────────
select fn_publicar_documento('rit', 'Reglamento de laboratorio selección',
  'Texto del Reglamento para la prueba 208.', fn_hoy_lima(), null);

select is(
  (select count(*)::int from fn_acuses_documento(
    (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1))
   where persona_id = '00000000-0000-0000-0000-000000cc0004'),
  0, 'NORMAS · quien esta en dias de seleccion no sale en la hoja de constancias del RIT');

-- ── 3 · fn_acuses_politica_salarial — la hoja de Política salarial ──────────
insert into politica_salarial (version, documento, huella_cuadro)
values (1, 'Politica de laboratorio para la prueba 208', 'huella-208');

select ok(
  not exists (
    select 1 from jsonb_array_elements(
      (select fn_acuses_politica_salarial()) -> 'personas'
    ) el
    where (el ->> 'persona_id') = '00000000-0000-0000-0000-000000cc0004'
  ),
  'SALARIAL · quien esta en dias de seleccion no sale en la hoja de constancias de la politica salarial');

-- ── 4 · fn_sin_constancia_del_reglamento — la alerta de Disciplina ─────────
select is(
  (select count(*)::int from fn_sin_constancia_del_reglamento()
    where persona_id = '00000000-0000-0000-0000-000000cc0004'),
  0, 'DISCIPLINA · quien esta en dias de seleccion no aparece en la alerta del numeral 60.5');

select is(
  (select count(*)::int from fn_sin_constancia_del_reglamento()
    where persona_id = '00000000-0000-0000-0000-000000cc0003'),
  1, 'DISCIPLINA · quien tiene contrato de trabajo y no acuso si aparece');

select * from finish();
rollback;
