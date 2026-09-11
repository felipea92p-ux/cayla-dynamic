-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 328_los_practicantes_cuentan_sus_faltas_reales.test.sql — defiende la 0414
-- ============================================================================
-- QUÉ DEFIENDE
--
--   Que `fn_faltas` cuente la falta real de un practicante (mismo horario,
--   mismo patrón de ausencia que un colaborador de planilla), y que un RxH
--   siga sin contar — el criterio es `tipo_vinculo = 'practicante'`
--   explícito, nunca `not en_planilla` a secas, que también atraparía a un
--   RxH por accidente.
--
--   Y, tan importante como lo anterior: que `fn_faltas_resumen` y
--   `fn_falta_contadores` — las que alimentan el escalón disciplinario
--   formal — SIGAN excluyendo al practicante después de la 0414. Si algún
--   día alguien intenta "completar" el criterio copiándolo a esas dos
--   funciones, esta prueba se pone roja y lo frena ahí.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000032800', 'ZZ3280', 'Sede de laboratorio 328', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000032801', 'Admin328', 'Lab', '00000000-0000-0000-0000-000000032800',
        'admin', 'x', '00000000-0000-0000-0000-000000032899', '2024-01-01');
set session_replication_role = origin;

-- ── Fixtures: mismo horario y mismo patrón de ausencia, distinto vínculo ────
--   · Practicante — tipo_vinculo = 'practicante' (en_planilla = false, derivado).
--   · Rxh         — tipo_vinculo = 'rxh' (en_planilla = false también: el
--                    control que prueba que el `or` no se coló de más).
--   · Planilla    — tipo_vinculo = 'planilla', el caso de siempre, sin cambios.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values
  ('00000000-0000-0000-0000-000000032810', 'Practicante', 'Lab', '00000000-0000-0000-0000-000000032800',
   'x', '2026-01-05', 'practicante'),
  ('00000000-0000-0000-0000-000000032811', 'Rxh', 'Lab', '00000000-0000-0000-0000-000000032800',
   'x', '2026-01-05', 'rxh'),
  ('00000000-0000-0000-0000-000000032812', 'Planilla', 'Lab', '00000000-0000-0000-0000-000000032800',
   'x', '2026-01-05', 'planilla');

insert into horarios_asignados (persona_id, hora_entrada, hora_salida, dias_laborables, vigente_desde)
select id, '09:00', '18:00', array[1,2,3,4,5], '2026-01-05'
from personas where sede_base_id = '00000000-0000-0000-0000-000000032800' and rol is distinct from 'admin';

-- Ninguna de las tres marca nada el lunes 2026-02-02: a las tres les tocaba
-- (horario lunes a viernes) y ninguna tiene ausencia, vacación ni feriado
-- que lo justifique.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000032899', true);

-- ── en_planilla queda derivada como se espera (documenta el fixture) ───────
select is((select en_planilla from personas where id = '00000000-0000-0000-0000-000000032810'), false,
  'FIXTURE · el practicante nace con en_planilla=false, como en producción');
select is((select en_planilla from personas where id = '00000000-0000-0000-0000-000000032811'), false,
  'FIXTURE · el RxH también nace con en_planilla=false — es el control');

-- ── fn_faltas, el 2026-02-02 (lunes, a todos les tocaba) ────────────────────
select is((select count(*)::int from fn_faltas('2026-02-02', '2026-02-02')
            where persona_id = '00000000-0000-0000-0000-000000032810'),
          1, 'FALTAS · el practicante SÍ cuenta su falta real — antes de la 0414 era 0');

select is((select justificada from fn_faltas('2026-02-02', '2026-02-02')
            where persona_id = '00000000-0000-0000-0000-000000032810'),
          false, 'FALTAS · la falta del practicante no sale marcada como justificada');

select is((select count(*)::int from fn_faltas('2026-02-02', '2026-02-02')
            where persona_id = '00000000-0000-0000-0000-000000032811'),
          0, 'FALTAS · el RxH sigue sin contar — el `or` es tipo_vinculo=practicante, no `not en_planilla`');

select is((select count(*)::int from fn_faltas('2026-02-02', '2026-02-02')
            where persona_id = '00000000-0000-0000-0000-000000032812'),
          1, 'FALTAS · Planilla, el caso de siempre, sigue contando igual que antes de la 0414');

-- ── El escalón disciplinario formal NO se toca ──────────────────────────────
select is((select count(*)::int from fn_faltas_resumen('2026-02-03')
            where persona_id = '00000000-0000-0000-0000-000000032810'),
          0, 'ESCALÓN · fn_faltas_resumen sigue sin ver al practicante — no alimenta ningún memo');

select * from finish();
rollback;
