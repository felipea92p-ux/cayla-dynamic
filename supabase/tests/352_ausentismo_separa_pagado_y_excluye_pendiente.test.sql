-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 352_ausentismo_separa_pagado_y_excluye_pendiente.test.sql
-- ============================================================================
-- Lo que esta prueba vigila:
--
--   1. dias_pagados suma lo que paga (vacaciones + descanso médico aprobado).
--   2. dias_no_pagados suma lo que no paga (permiso personal).
--   3. Un descanso médico TODAVÍA PENDIENTE de aprobar no suma en ninguna de
--      las tres cifras — ni siquiera en dias_total.
--   4. dias_total sigue siendo la suma de las dos partes.
--   5. registros no cuenta el pendiente ni el anulado.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000d10a', 'ZZRES', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d20a', 'ResAdmin', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'admin', 'x', '00000000-0000-0000-0000-00000000da0a', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d30a', 'ResPersona', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'x', '2024-01-01');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000da0a', true);

-- 1 día de vacaciones — paga, nace aprobada sola.
select fn_registrar_ausencia('00000000-0000-0000-0000-00000000d30a', 'vacaciones', '2026-11-02', '2026-11-02');

-- 1 día de permiso personal — no paga.
select fn_registrar_ausencia('00000000-0000-0000-0000-00000000d30a', 'permiso_personal', '2026-11-05', '2026-11-05');

-- 1 día de descanso médico, aprobado por DO — paga.
select fn_registrar_ausencia('00000000-0000-0000-0000-00000000d30a', 'descanso_medico', '2026-11-08', '2026-11-08',
  'gripe', 'Dra. Lab', 'CMP 90002', '2026-11-08');
select fn_aprobar_ausencia((select id from ausencias
  where persona_id = '00000000-0000-0000-0000-00000000d30a' and fecha_inicio = '2026-11-08'));

-- 1 día de descanso médico SIN aprobar — no debe contar en nada.
select fn_registrar_ausencia('00000000-0000-0000-0000-00000000d30a', 'descanso_medico', '2026-11-11', '2026-11-11',
  'gripe', 'Dra. Lab', 'CMP 90002', '2026-11-11');

-- 1 día de "otro", registrado y anulado — no debe contar en nada.
select fn_registrar_ausencia('00000000-0000-0000-0000-00000000d30a', 'otro', '2026-11-14', '2026-11-14', 'trámite');
select fn_anular_ausencia((select id from ausencias
  where persona_id = '00000000-0000-0000-0000-00000000d30a' and fecha_inicio = '2026-11-14'), 'se registró de más');

select is(
  (select dias_pagados from fn_ausencias_resumen('2026-11-01', '2026-11-30')
   where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  2, 'PAGADOS · vacaciones + descanso médico aprobado suman 2 días');

select is(
  (select dias_no_pagados from fn_ausencias_resumen('2026-11-01', '2026-11-30')
   where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  1, 'NO PAGADOS · el permiso personal suma 1 día');

select is(
  (select registros from fn_ausencias_resumen('2026-11-01', '2026-11-30')
   where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  3, 'REGISTROS · tres cuentan (vacaciones, permiso, médico aprobado) — ni el pendiente ni el anulado');

select is(
  (select dias_total from fn_ausencias_resumen('2026-11-01', '2026-11-30')
   where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  3, 'TOTAL · sigue siendo la suma de pagados y no pagados');

-- El pendiente no aparece en `por_tipo` porque su fila entera queda fuera del
-- agregado — comprobado mirando que la clave de su tipo no está en el jsonb.
select is(
  (select por_tipo ? 'Descanso médico (con documento)'
   from fn_ausencias_resumen('2026-11-01', '2026-11-30')
   where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  true, 'DESGLOSE · el tipo sigue apareciendo (por el aprobado), con solo su día aprobado adentro');

select * from finish();
rollback;
