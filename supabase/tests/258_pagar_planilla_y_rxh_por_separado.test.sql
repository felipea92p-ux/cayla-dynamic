-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 258_pagar_planilla_y_rxh_por_separado.test.sql
-- ============================================================================
-- Fija las promesas de la 0323: "pagado" deja de ser un solo interruptor por
-- periodo y pasa a ser independiente por grupo (tipo_vinculo).
--
--   · Pagar planilla NO congela ni bloquea a RxH del mismo periodo, y
--     viceversa.
--   · Mientras falte un grupo por pagar, `periodos_planilla.estado` sigue
--     'abierto' — el candado de horas (entrega 2, sin tocar en esta) no se
--     activa hasta que el ÚLTIMO grupo con gente queda pagado.
--   · `fn_proyeccion_periodo` mezcla foto (grupo pagado) y cálculo en vivo
--     (grupo abierto) en la misma respuesta, y lo dice con `fuente = mixto`.
--   · `fn_costos_planilla` cuenta a planilla en cuanto planilla se paga, sin
--     esperar a RxH.
--   · Reabrir un grupo (`fn_revertir_pago`) nunca toca la foto de otro grupo
--     ya pagado.
--   · COMPATIBILIDAD: un periodo pagado a la vieja usanza (de antes de esta
--     migración, sin ninguna fila en periodo_grupo_pago) se sigue leyendo y
--     reabriendo igual que siempre.
-- ============================================================================
begin;
select plan(18);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000258', 'ZZ258', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000025801', 'Admin258', 'Lab', '00000000-0000-0000-0000-000000000258', 'admin', 'x', '00000000-0000-0000-0000-000000258001', '2024-01-01');
set session_replication_role = origin;

-- Los dos con sueldo_fijo, a propósito: cobran su salario del mes completo
-- sin necesitar horario ni marcajes, así el fixture se queda en lo que esta
-- prueba de verdad quiere comprobar — que el grupo de cada quien se paga y
-- se lee por separado — y no en reconstruir cuántas horas trabajó cada uno.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, sueldo_fijo)
values
  ('00000000-0000-0000-0000-000000025802', 'PlanillaLab', 'Ochoa', '00000000-0000-0000-0000-000000000258', 'x', '2024-01-01', 'planilla', true),
  ('00000000-0000-0000-0000-000000025803', 'RxhLab',      'Nueve', '00000000-0000-0000-0000-000000000258', 'x', '2024-01-01', 'rxh',      true);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values
  ('00000000-0000-0000-0000-000000025802', 'colibri', 1500, '2024-01-01'),
  ('00000000-0000-0000-0000-000000025803', 'colibri', 1500, '2024-01-01');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000258001', true);

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000258f0', '2026-06-01', '2026-06-30', 'abierto');

-- ── ANTES: nadie pagado ──────────────────────────────────────────────────────
select is((select count(*)::int from periodo_grupo_pago
           where periodo_id = '00000000-0000-0000-0000-0000000258f0'),
          0, 'ANTES · ningún grupo tiene fila todavía');

select is((select fn_proyeccion_periodo('00000000-0000-0000-0000-0000000258f0')->>'fuente'),
          'calculo', 'ANTES · todo en vivo, como cualquier periodo abierto');

-- ── Se paga SOLO planilla ────────────────────────────────────────────────────
select fn_periodo_pagado('00000000-0000-0000-0000-0000000258f0', true, 'planilla');

select is((select count(*)::int from planilla_pagada_detalle
           where periodo_id = '00000000-0000-0000-0000-0000000258f0'
             and persona_id = '00000000-0000-0000-0000-000000025802'),
          1, 'PLANILLA PAGADA · su foto queda congelada');

select is((select count(*)::int from planilla_pagada_detalle
           where periodo_id = '00000000-0000-0000-0000-0000000258f0'
             and persona_id = '00000000-0000-0000-0000-000000025803'),
          0, 'PLANILLA PAGADA · RxH NO se congeló — pagar un grupo no toca al otro');

select is((select estado from periodos_planilla
           where id = '00000000-0000-0000-0000-0000000258f0'),
          'abierto', 'PLANILLA PAGADA · el periodo entero sigue abierto: falta RxH');

-- Un bono agregado a RxH AHORA (su grupo sigue abierto) tiene que verse en
-- vivo — es justo lo que demuestra que RxH no quedó atrapado por el pago de
-- planilla.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto)
values ('00000000-0000-0000-0000-0000000258f0', '00000000-0000-0000-0000-000000025803',
        'bono', 'bono de laboratorio RxH', 77);

select is((
  select (f->>'bonos')::numeric
  from jsonb_array_elements(fn_proyeccion_periodo('00000000-0000-0000-0000-0000000258f0')->'filas') f
  where f->>'persona_id' = '00000000-0000-0000-0000-000000025803'
), 77::numeric, 'MEZCLA · el bono de RxH (grupo abierto) se ve en vivo en la misma respuesta');

select is((select fn_proyeccion_periodo('00000000-0000-0000-0000-0000000258f0')->>'fuente'),
          'mixto', 'MEZCLA · fn_proyeccion_periodo lo marca como mixto: un grupo pagado, otro no');

-- Costos ya cuenta a planilla, sin esperar a que RxH también se pague.
select cmp_ok(
  (select coalesce((fn_costos_planilla('2026-06-01','2026-06-30')->'totales'->>'personas')::int, 0)),
  '>', 0,
  'COSTOS · planilla ya sale en Costos aunque RxH siga pendiente');

-- ── Se paga RxH también ──────────────────────────────────────────────────────
select fn_periodo_pagado('00000000-0000-0000-0000-0000000258f0', true, 'rxh');

select is((select estado from periodos_planilla
           where id = '00000000-0000-0000-0000-0000000258f0'),
          'pagado', 'AMBOS PAGADOS · ahora sí, el periodo entero queda pagado — el último grupo lo completó');

select is((select fn_proyeccion_periodo('00000000-0000-0000-0000-0000000258f0')->>'fuente'),
          'foto', 'AMBOS PAGADOS · ya no hay nada en vivo: todo sale de la foto');

select is((
  select (f->>'bonos')::numeric
  from jsonb_array_elements(fn_proyeccion_periodo('00000000-0000-0000-0000-0000000258f0')->'filas') f
  where f->>'persona_id' = '00000000-0000-0000-0000-000000025803'
), 77::numeric, 'AMBOS PAGADOS · el bono de RxH quedó dentro de SU foto al congelarla');

-- ── Reabrir SOLO planilla no toca la foto de RxH ─────────────────────────────
select fn_revertir_pago('00000000-0000-0000-0000-0000000258f0', 'corrección de prueba', 'planilla');

select is((select estado from periodos_planilla
           where id = '00000000-0000-0000-0000-0000000258f0'),
          'abierto', 'REABRIR PLANILLA · el periodo vuelve a abierto: ya no está completo');

select is((select estado from periodo_grupo_pago
           where periodo_id = '00000000-0000-0000-0000-0000000258f0' and grupo = 'planilla'),
          'abierto', 'REABRIR PLANILLA · su propio grupo queda abierto');

select is((select estado from periodo_grupo_pago
           where periodo_id = '00000000-0000-0000-0000-0000000258f0' and grupo = 'rxh'),
          'pagado', 'REABRIR PLANILLA · RxH sigue pagado — reabrir un grupo no reabre al otro');

select is((select count(*)::int from planilla_pagada_detalle
           where periodo_id = '00000000-0000-0000-0000-0000000258f0'
             and persona_id = '00000000-0000-0000-0000-000000025803'),
          1, 'REABRIR PLANILLA · la foto de RxH sigue intacta (append-only, nunca se tocó)');

-- ── Permisos: la lectura por grupo es solo para admin/líder ──────────────────
-- Un UUID que no es de nadie: fn_persona_actual_id() no encuentra auth_user_id
-- y fn_es_admin_o_lider() cae en el guard null-safe (0078) — no true.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
select throws_ok(
  $$ select fn_periodo_grupos_estado('00000000-0000-0000-0000-0000000258f0') $$,
  null, null, 'PERMISOS · sin sesión de admin/líder, fn_periodo_grupos_estado se niega');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000258001', true);

-- ── COMPATIBILIDAD: un periodo pagado a la vieja usanza ──────────────────────
-- Nunca pasó por fn_periodo_pagado con grupo: se marca pagado a mano, como se
-- hacía antes de la 0323. periodo_grupo_pago se queda vacío para él a
-- propósito — es exactamente el estado en el que queda un periodo histórico
-- que el backfill del bloque 4 de la 0323 no alcanzó a tocar.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at)
values ('00000000-0000-0000-0000-0000000258f1', '2026-05-01', '2026-05-31', 'pagado', now());

-- Las DOS personas, planilla y RxH — `grupo` puesto a mano con el tipo_vinculo
-- real de cada quien, tal como lo dejaría el backfill de la 0323 sobre una
-- foto vieja (bloque 2 de esa migración, que lo saca de `fila->>'tipo_vinculo'`).
-- periodo_grupo_pago se queda vacío para los dos a propósito — es la parte
-- que representa "de antes de que existiera esa tabla".
insert into planilla_pagada_detalle (periodo_id, persona_id, version, origen, nombre, sede_codigo, pago_base, total, fila, grupo)
values ('00000000-0000-0000-0000-0000000258f1', '00000000-0000-0000-0000-000000025802', 1, 'pago',
        'PlanillaLab Ochoa', 'ZZ258', 1500, 1500, '{"total": 1500}'::jsonb, 'planilla'),
       ('00000000-0000-0000-0000-0000000258f1', '00000000-0000-0000-0000-000000025803', 1, 'pago',
        'RxhLab Nueve', 'ZZ258', 1500, 1500, '{"total": 1500}'::jsonb, 'rxh');

select is((select fn_proyeccion_periodo('00000000-0000-0000-0000-0000000258f1')->>'fuente'),
          'foto', 'COMPATIBILIDAD · un periodo pagado a la vieja usanza se sigue leyendo de su foto');

select lives_ok(
  $$ select fn_revertir_pago('00000000-0000-0000-0000-0000000258f1', 'corrección de un periodo viejo') $$,
  'COMPATIBILIDAD · y se puede reabrir sin declarar grupo — cae en planilla por defecto');

select * from finish();
rollback;
