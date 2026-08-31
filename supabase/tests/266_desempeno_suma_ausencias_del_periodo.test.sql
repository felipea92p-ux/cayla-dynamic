-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 266_desempeno_suma_ausencias_del_periodo.test.sql — la 0334 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que sume: es que RECORTE al rango pedido
-- (una ausencia que empieza antes de "desde" no debe contar los días de
-- afuera), que una ausencia ANULADA no sume nada, y que la visibilidad sea
-- EXACTAMENTE la misma que ya tiene fn_ausencias — ni un pelo más ancha.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000f9701', 'ZZA01', 'Sede A ausencias', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000f9702', 'ZZA02', 'Sede B ausencias', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000fa001', 'AusResAdmin', 'Lab',
   '00000000-0000-0000-0000-0000000f9701', 'admin', 'x',
   '00000000-0000-0000-0000-0000000fb001', '2023-01-01'),
  ('00000000-0000-0000-0000-0000000fa002', 'AusResEncargada', 'Lab',
   '00000000-0000-0000-0000-0000000f9701', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000fb002', '2023-01-01'),
  ('00000000-0000-0000-0000-0000000fa003', 'AusResEncargadaAjena', 'Lab',
   '00000000-0000-0000-0000-0000000f9702', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000fb003', '2023-01-01'),
  ('00000000-0000-0000-0000-0000000fa004', 'AusResPropia', 'Lab',
   '00000000-0000-0000-0000-0000000f9701', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000fb004', '2023-01-01'),
  ('00000000-0000-0000-0000-0000000fa005', 'AusResAjena', 'Lab',
   '00000000-0000-0000-0000-0000000f9702', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000fb005', '2023-01-01');

-- Vacaciones, entera dentro del rango 2026-06-01..2026-06-30: 3 días.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por, registrada_at, aprobada_por, aprobada_at)
values ('00000000-0000-0000-0000-0000000fa004', 'vacaciones', '2026-06-10', '2026-06-12',
        '00000000-0000-0000-0000-0000000fa001', now(), '00000000-0000-0000-0000-0000000fa001', now());

-- Descanso médico que EMPIEZA ANTES del rango: solo deben contar los dos días
-- que caen dentro (06-01 y 06-02), no los cuatro que tiene en total.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, doc_profesional, doc_colegiatura, doc_fecha, registrada_por, registrada_at, aprobada_por, aprobada_at)
values ('00000000-0000-0000-0000-0000000fa004', 'descanso_medico', '2026-05-28', '2026-06-02',
        'Dr. Prueba', 'CMP1', '2026-05-28',
        '00000000-0000-0000-0000-0000000fa001', now(), '00000000-0000-0000-0000-0000000fa001', now());

-- Una tercera, ANULADA, en fechas que se cruzarían con la primera si contara
-- (para que quede claro que ni pesa en la suma ni rompe el exclusion).
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por, registrada_at, aprobada_por, aprobada_at,
                        anulada_at, anulada_por, anulada_motivo)
values ('00000000-0000-0000-0000-0000000fa004', 'vacaciones', '2026-06-11', '2026-06-11',
        '00000000-0000-0000-0000-0000000fa001', now(), '00000000-0000-0000-0000-0000000fa001', now(),
        now(), '00000000-0000-0000-0000-0000000fa001', 'anulada para la prueba');
set session_replication_role = origin;

-- ── La suma, el recorte y el desglose ────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb001', true);

select is(
  (select dias_total from fn_ausencias_resumen('2026-06-01', '2026-06-30')
   where persona_id = '00000000-0000-0000-0000-0000000fa004'),
  5,
  'suma 3 (vacaciones) + 2 (descanso médico recortado) = 5, sin contar la anulada'
);

select is(
  (select registros from fn_ausencias_resumen('2026-06-01', '2026-06-30')
   where persona_id = '00000000-0000-0000-0000-0000000fa004'),
  2,
  'dos registros cuentan, la anulada no es un tercero'
);

select is(
  (select por_tipo from fn_ausencias_resumen('2026-06-01', '2026-06-30')
   where persona_id = '00000000-0000-0000-0000-0000000fa004'),
  '{"Vacaciones": 3, "Descanso médico (con documento)": 2}'::jsonb,
  'el desglose por tipo trae el NOMBRE del tipo, ya recortado'
);

-- Fuera del rango de la médica: si se pregunta solo por mayo, el recorte debe
-- ir por el otro lado (fecha_fin tope en el 31, no en el 02).
select is(
  (select dias_total from fn_ausencias_resumen('2026-05-01', '2026-05-31')
   where persona_id = '00000000-0000-0000-0000-0000000fa004'),
  4,
  'mirando solo mayo, la médica recorta por el otro borde: 28,29,30,31 = 4 días'
);

-- Quien no tiene ninguna ausencia en el rango no aparece con una fila en cero.
select is(
  (select count(*)::int from fn_ausencias_resumen('2026-01-01', '2026-01-31')
   where persona_id = '00000000-0000-0000-0000-0000000fa004'),
  0,
  'sin ausencias en el rango, no hay fila (no una fila con 0)'
);

-- ── Visibilidad, calcada de fn_ausencias ─────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb004', true);
select is(
  (select dias_total from fn_ausencias_resumen('2026-06-01', '2026-06-30')
   where persona_id = '00000000-0000-0000-0000-0000000fa004'),
  5,
  'ella misma ve su propio resumen'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb005', true);
set local role authenticated;
select is(
  (select count(*)::int from fn_ausencias_resumen('2026-06-01', '2026-06-30')
   where persona_id = '00000000-0000-0000-0000-0000000fa004'),
  0,
  'otra integrante, de otra sede, no ve su resumen'
);
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb003', true);
select is(
  (select count(*)::int from fn_ausencias_resumen('2026-06-01', '2026-06-30')
   where persona_id = '00000000-0000-0000-0000-0000000fa004'),
  0,
  'la encargada de OTRA sede no la ve'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb002', true);
select is(
  (select dias_total from fn_ausencias_resumen('2026-06-01', '2026-06-30')
   where persona_id = '00000000-0000-0000-0000-0000000fa004'),
  5,
  'la encargada de SU sede sí la ve'
);

select * from finish();
rollback;
