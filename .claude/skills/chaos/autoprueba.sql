-- Autoprueba de las invariantes: un detector ciego da calma falsa. Mete una fila que
-- rompe cada invariante, dentro de una transacción que SIEMPRE se revierte, y las
-- invariantes tienen que señalar las siete. Las restricciones siguen activas; lo que
-- `replica` apaga son los triggers y las llaves foráneas.
--
--   { cat .claude/skills/chaos/autoprueba.sql .claude/skills/chaos/invariantes.sql; echo rollback\;; } \
--     | psql -h 127.0.0.1 -p 55890 -U postgres -d postgres -At -F '|' | cut -d'|' -f1 | grep '^INV-' | sort -u
begin;
set local session_replication_role = replica;

-- Una persona y un periodo de mentira, con identificadores fijos para reconocerlos.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at) values
  ('c4a05000-0000-4000-8000-000000000001', '2031-01-29', '2031-02-28', 'pagado', null),
  ('c4a05000-0000-4000-8000-000000000002', '2031-03-01', '2031-03-28', 'pagado', '2031-03-28 12:00+00');

-- INV-01 (sin jornada) e INV-05 (dos iguales seguidas).
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), gen_random_uuid(), 'c4a05000-0000-4000-8000-00000000000a',
       'c4a05000-0000-4000-8000-00000000000b', 'entrada', '2031-03-10 13:00:00+00'::timestamptz + (i || ' seconds')::interval
  from generate_series(1, 2) i;

-- INV-02: salió antes de entrar.
insert into jornadas (persona_id, fecha, entrada_ts, salida_final_ts)
values ('c4a05000-0000-4000-8000-00000000000a', '2031-03-12', '2031-03-12 18:00+00', '2031-03-12 13:00+00');

-- INV-03 e INV-07: dos liquidaciones vigentes, y planilla pagada después del cese.
insert into liquidacion_pagada (persona_id, version, congelada_por, persona, fecha_cese, total, detalle)
select 'c4a05000-0000-4000-8000-00000000000a', v, 'c4a05000-0000-4000-8000-00000000000a', 'Prueba', '2031-01-15', 100, '{}'::jsonb
  from generate_series(1, 2) v;
insert into planilla_pagada_detalle (periodo_id, persona_id, version, origen, nombre, sede_codigo, pago_base, total, fila)
values ('c4a05000-0000-4000-8000-000000000002', 'c4a05000-0000-4000-8000-00000000000a', 1, 'pago', 'Prueba', 'TRU', 100, 100, '{}'::jsonb);

-- INV-06: movimiento posterior al pago.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, created_at)
values ('c4a05000-0000-4000-8000-000000000002', 'c4a05000-0000-4000-8000-00000000000a', 'bono', 'prueba', 1, '2031-03-29 12:00+00');
