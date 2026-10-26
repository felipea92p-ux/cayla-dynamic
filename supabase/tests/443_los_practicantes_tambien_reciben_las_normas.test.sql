-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 443_los_practicantes_tambien_reciben_las_normas.test.sql
-- ============================================================================
-- Defiende la 0551: el practicante activo cuenta en la población que recibe las
-- Normas, en los tres estados en que puede estar su acceso —con cuenta y ya
-- entró, invitado que todavía no abrió el correo, sin cuenta— y en las TRES
-- funciones que cuelgan de `fn_poblacion_obligada()`: la lista de Constancias
-- y sus contadores, la hoja imprimible, y la alerta de Disciplina.
--
-- Y defiende lo que NO debe moverse:
--   · 'prueba', 'rxh', el inactivo y la cuenta de servicio siguen fuera;
--   · la hoja de Política salarial sigue SIN practicantes (Ley 30709 no les
--     alcanza, decidido el 2026-08-31), aunque ahora comparta población.
-- ============================================================================
begin;
select plan(20);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000dd0001', 'ZZPRA', 'Sede de laboratorio practicantes', true);

-- Tres cuentas: la de DO (que mira), la de una practicante que ya entró y la de
-- una practicante INVITADA. `invitar` enlaza `auth_user_id` apenas GoTrue acepta
-- el envío, así que desde la ficha una invitada que nunca abrió el correo es
-- indistinguible de la que sí entró: las dos «tienen cuenta».
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values
  ('dd000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'do.practicantes@laboratorio.local', '', now(), now()),
  ('dd000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'practicante.entro@laboratorio.local', '', now(), now()),
  ('dd000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'practicante.invitada@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash,
                      auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-000000dd0002', 'DoPra', 'Lab',
        '00000000-0000-0000-0000-000000dd0001', 'lider_do', 'x',
        'dd000000-0000-0000-0000-0000000000c1', '2020-01-01', 'activo', 'planilla');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      auth_user_id, fecha_ingreso, estado, tipo_vinculo, cuenta_de_servicio)
values
  -- el equipo de siempre
  ('00000000-0000-0000-0000-000000dd0003', 'Planilla',   'Lab', '00000000-0000-0000-0000-000000dd0001', 'x',
   null, '2020-01-01', 'activo',   'planilla',    false),
  -- los tres practicantes activos: con cuenta que ya entró · invitada · sin cuenta
  ('00000000-0000-0000-0000-000000dd0004', 'PracEntro',  'Lab', '00000000-0000-0000-0000-000000dd0001', 'x',
   'dd000000-0000-0000-0000-0000000000c2', '2026-03-01', 'activo',   'practicante', false),
  ('00000000-0000-0000-0000-000000dd0005', 'PracInvit',  'Lab', '00000000-0000-0000-0000-000000dd0001', 'x',
   'dd000000-0000-0000-0000-0000000000c3', '2026-03-01', 'activo',   'practicante', false),
  ('00000000-0000-0000-0000-000000dd0006', 'PracSinCta', 'Lab', '00000000-0000-0000-0000-000000dd0001', 'x',
   null, '2026-03-01', 'activo',   'practicante', false),
  -- lo que NO debe entrar (el practicante inactivo va aparte: la restricción
  -- `personas_cese_coherente` exige que quien está inactivo traiga su fecha de cese)
  ('00000000-0000-0000-0000-000000dd0008', 'PracServ',  'Lab', '00000000-0000-0000-0000-000000dd0001', 'x',
   null, '2026-03-01', 'activo',   'practicante', true),
  ('00000000-0000-0000-0000-000000dd0009', 'EnSeleccion','Lab', '00000000-0000-0000-0000-000000dd0001', 'x',
   null, '2026-03-01', 'activo',   'prueba',      false),
  ('00000000-0000-0000-0000-000000dd000a', 'Locadora',   'Lab', '00000000-0000-0000-0000-000000dd0001', 'x',
   null, '2026-03-01', 'activo',   'rxh',         false);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, fecha_cese, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-000000dd0007', 'PracInact', 'Lab',
        '00000000-0000-0000-0000-000000dd0001', 'x',
        '2025-03-01', '2025-12-31', 'inactivo', 'practicante');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'dd000000-0000-0000-0000-0000000000c1', true);

-- ── 1 · La población: quién cuenta ──────────────────────────────────────────
select is(
  (select count(*)::int from fn_poblacion_obligada()
    where fn_poblacion_obligada = '00000000-0000-0000-0000-000000dd0004'),
  1, 'POBLACION · el practicante con cuenta que ya entró cuenta');

select is(
  (select count(*)::int from fn_poblacion_obligada()
    where fn_poblacion_obligada = '00000000-0000-0000-0000-000000dd0005'),
  1, 'POBLACION · el practicante invitado que no abrió el correo cuenta');

select is(
  (select count(*)::int from fn_poblacion_obligada()
    where fn_poblacion_obligada = '00000000-0000-0000-0000-000000dd0006'),
  1, 'POBLACION · el practicante sin cuenta cuenta (su constancia va en papel)');

select is(
  (select count(*)::int from fn_poblacion_obligada()
    where fn_poblacion_obligada = '00000000-0000-0000-0000-000000dd0003'),
  1, 'POBLACION · quien tiene contrato de trabajo sigue contando');

select is(
  (select count(*)::int from fn_poblacion_obligada()
    where fn_poblacion_obligada in (
      '00000000-0000-0000-0000-000000dd0007',    -- practicante inactivo
      '00000000-0000-0000-0000-000000dd0008',    -- practicante marcado como cuenta de servicio
      '00000000-0000-0000-0000-000000dd0009',    -- dias de seleccion
      '00000000-0000-0000-0000-000000dd000a')),  -- locadora
  0, 'POBLACION · el inactivo, la cuenta de servicio, la seleccion y la locadora siguen fuera');

-- ── 2 · La lista de Constancias de Normas ───────────────────────────────────
select fn_publicar_documento('rit', 'Reglamento de laboratorio practicantes',
  'Texto del Reglamento para la prueba 443.', fn_hoy_lima(), null);

select is(
  (select count(*)::int from fn_acuses_documento(
    (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1))
   where persona_id in ('00000000-0000-0000-0000-000000dd0004',
                        '00000000-0000-0000-0000-000000dd0005',
                        '00000000-0000-0000-0000-000000dd0006')),
  3, 'NORMAS · los tres practicantes salen en la hoja de constancias del RIT');

select is(
  (select array_agg(tiene_cuenta order by persona_id) from fn_acuses_documento(
    (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1))
   where persona_id in ('00000000-0000-0000-0000-000000dd0004',
                        '00000000-0000-0000-0000-000000dd0005',
                        '00000000-0000-0000-0000-000000dd0006')),
  array[true, true, false],
  'NORMAS · con cuenta e invitado salen con cuenta; solo el que no tiene sale «sin cuenta»');

select is(
  (select count(*)::int from fn_acuses_documento(
    (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1))
   where persona_id in ('00000000-0000-0000-0000-000000dd0004',
                        '00000000-0000-0000-0000-000000dd0005',
                        '00000000-0000-0000-0000-000000dd0006')
     and acusado_at is null),
  3, 'NORMAS · sin constancia, los tres salen como pendientes');

select is(
  (select count(*)::int from fn_acuses_documento(
    (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1))
   where persona_id in ('00000000-0000-0000-0000-000000dd0007',
                        '00000000-0000-0000-0000-000000dd0008',
                        '00000000-0000-0000-0000-000000dd0009',
                        '00000000-0000-0000-0000-000000dd000a')),
  0, 'NORMAS · el inactivo, la cuenta de servicio, la seleccion y la locadora no salen');

-- ── 3 · El contador «N de M» ────────────────────────────────────────────────
select is(
  (select poblacion from fn_documentos_vigentes()
    where documento_id = (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1)),
  5, 'CONTADOR · la poblacion es DO + planilla + los tres practicantes');

-- ── 4 · El flujo completo: la practicante firma y DO lo ve ──────────────────
-- Entra la practicante que ya tenía cuenta y deja su constancia por el camino
-- de siempre (`fn_acusar_documento`, el mismo que usa «Lo mío»).
select set_config('request.jwt.claim.sub', 'dd000000-0000-0000-0000-0000000000c2', true);
select fn_acusar_documento(
  (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1),
  'PracEntro Lab');

-- Y vuelve DO a mirar.
select set_config('request.jwt.claim.sub', 'dd000000-0000-0000-0000-0000000000c1', true);

select is(
  (select via from fn_acuses_documento(
    (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1))
   where persona_id = '00000000-0000-0000-0000-000000dd0004'),
  'sistema', 'FLUJO · DO ve la constancia que la practicante dejo desde el sistema');

select is(
  (select total_acuses from fn_documentos_vigentes()
    where documento_id = (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1)),
  1, 'FLUJO · y el contador la suma: 1 de 5');

-- La practicante sin cuenta no puede firmar sola: DO registra su cargo escaneado.
select fn_registrar_acuse_papel(
  (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1),
  '00000000-0000-0000-0000-000000dd0006', 'cargos/prueba-443.pdf', null, null);

select is(
  (select via from fn_acuses_documento(
    (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1))
   where persona_id = '00000000-0000-0000-0000-000000dd0006'),
  'papel', 'FLUJO · el cargo en papel de la practicante sin cuenta queda registrado');

select is(
  (select total_acuses from fn_documentos_vigentes()
    where documento_id = (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1)),
  2, 'FLUJO · el contador sube a 2 de 5');

select ok(
  (select total_acuses <= poblacion from fn_documentos_vigentes()
    where documento_id = (select id from documentos_institucionales where tipo = 'rit' order by version desc limit 1)),
  'FLUJO · el numerador nunca pasa al denominador (el «24 de 23» de la 0265)');

-- ── 5 · La alerta de Disciplina (numeral 60.5) ──────────────────────────────
select is(
  (select count(*)::int from fn_sin_constancia_del_reglamento()
    where persona_id = '00000000-0000-0000-0000-000000dd0005'),
  1, 'DISCIPLINA · la practicante invitada, sin constancia, sale en la alerta');

select is(
  (select count(*)::int from fn_sin_constancia_del_reglamento()
    where persona_id in ('00000000-0000-0000-0000-000000dd0004',
                         '00000000-0000-0000-0000-000000dd0006')),
  0, 'DISCIPLINA · quien ya dejo su constancia —por sistema o en papel— no sale');

-- ── 6 · La Política salarial NO cambia ──────────────────────────────────────
insert into politica_salarial (version, documento, huella_cuadro)
values (1, 'Politica de laboratorio para la prueba 443', 'huella-443');

select ok(
  not exists (
    select 1 from jsonb_array_elements(
      (select fn_acuses_politica_salarial()) -> 'personas'
    ) el
    where (el ->> 'persona_id') in ('00000000-0000-0000-0000-000000dd0004',
                                    '00000000-0000-0000-0000-000000dd0005',
                                    '00000000-0000-0000-0000-000000dd0006')
  ),
  'SALARIAL · la hoja de Politica salarial sigue SIN los practicantes');

select ok(
  not exists (
    select 1 from jsonb_array_elements(
      (select fn_acuses_politica_salarial(1)) -> 'personas'
    ) el
    where (el ->> 'persona_id') in ('00000000-0000-0000-0000-000000dd0004',
                                    '00000000-0000-0000-0000-000000dd0005',
                                    '00000000-0000-0000-0000-000000dd0006')
  ),
  'SALARIAL · tampoco al pedir una version concreta');

select ok(
  exists (
    select 1 from jsonb_array_elements(
      (select fn_acuses_politica_salarial()) -> 'personas'
    ) el
    where (el ->> 'persona_id') = '00000000-0000-0000-0000-000000dd0003'
  ),
  'SALARIAL · y quien tiene contrato de trabajo sigue en la hoja');

select * from finish();
rollback;
