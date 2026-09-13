-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 314_las_faltas_dejan_de_contar_tras_el_fin_de_contrato.test.sql — defiende
-- la 0396
-- ============================================================================
-- QUÉ DEFIENDE
--
--   Que `fn_faltas`, `fn_faltas_resumen` y `fn_falta_contadores` dejen de
--   acusar de inasistencia injustificada cada día posterior a
--   `fecha_fin_contrato` de quien correctamente dejó de venir — y que sigan
--   contando normal a quien, pese a tener esa fecha vencida, siguió marcando
--   después (desnaturalizado de hecho, art. 77 LPCL): ahí no hay ninguna
--   fecha que corte, porque la relación sigue viva.
--
--   Reproduce, con fechas propias, el caso real que
--   `auditoria/CAYLA_CORP_RPT_202608_Auditoria.md` midió contra producción:
--   una persona con contrato vencido y sin marcajes después quedaba con
--   inasistencias injustificadas de verdad, listas para un memo real.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000031400', 'ZZ3140', 'Sede de laboratorio 314', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000031401', 'Admin314', 'Lab', '00000000-0000-0000-0000-000000031400',
        'admin', 'x', '00000000-0000-0000-0000-000000031499', '2024-01-01');
set session_replication_role = origin;

-- ── Fixtures: tres personas, mismo horario y misma fecha_fin_contrato ───────
--   · ConFin        — contrato hasta el 06-feb-2026, sin marcar después.
--   · Desnaturalizado — mismo fin, pero siguió marcando el 09 y el 10 y
--     dejó de venir recién el 11.
--   · MarcaAnulada  — mismo fin, y su ÚNICA marca posterior está ANULADA:
--     no debe contar como que "siguió viniendo".
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, fecha_fin_contrato)
values
  ('00000000-0000-0000-0000-000000031410', 'ConFin', 'Lab', '00000000-0000-0000-0000-000000031400',
   'x', '2026-01-05', '2026-02-06'),
  ('00000000-0000-0000-0000-000000031411', 'Desnaturalizado', 'Lab', '00000000-0000-0000-0000-000000031400',
   'x', '2026-01-05', '2026-02-06'),
  ('00000000-0000-0000-0000-000000031412', 'MarcaAnulada', 'Lab', '00000000-0000-0000-0000-000000031400',
   'x', '2026-01-05', '2026-02-06'),
  -- Sin fecha_fin_contrato en absoluto: el caso normal, indefinido.
  ('00000000-0000-0000-0000-000000031413', 'SinFin', 'Lab', '00000000-0000-0000-0000-000000031400',
   'x', '2026-01-05', null);

insert into horarios_asignados (persona_id, hora_entrada, hora_salida, dias_laborables, vigente_desde)
select id, '09:00', '18:00', array[1,2,3,4,5], '2026-01-05'
from personas where sede_base_id = '00000000-0000-0000-0000-000000031400' and rol is distinct from 'admin';

-- Las tres marcan puntual toda su última semana (02 al 06 de febrero).
-- El `order by` importa: el disparador que mantiene `jornadas` espera la
-- entrada de cada día antes que su salida, y un INSERT ... SELECT sin orden
-- explícito no garantiza esa secuencia.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-000000031400', m.tipo,
       (d::date + m.hora) at time zone 'America/Lima', 'terminal'
from (values
        ('00000000-0000-0000-0000-000000031410'::uuid),
        ('00000000-0000-0000-0000-000000031411'::uuid),
        ('00000000-0000-0000-0000-000000031412'::uuid)
      ) as p(id)
cross join generate_series(date '2026-02-02', date '2026-02-06', interval '1 day') d
cross join (values ('entrada'::tipo_marca, time '09:00'), ('salida_final'::tipo_marca, time '18:00')) as m(tipo, hora)
order by p.id, d::date + m.hora;

-- Desnaturalizado sigue marcando el lunes y martes siguientes (09 y 10-feb),
-- ya con el contrato vencido, y recién deja de venir el 11.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen)
select gen_random_uuid(), '00000000-0000-0000-0000-000000031411', '00000000-0000-0000-0000-000000031400', m.tipo,
       (d::date + m.hora) at time zone 'America/Lima', 'terminal'
from generate_series(date '2026-02-09', date '2026-02-10', interval '1 day') d
cross join (values ('entrada'::tipo_marca, time '09:00'), ('salida_final'::tipo_marca, time '18:00')) as m(tipo, hora)
order by d::date + m.hora;

-- MarcaAnulada tiene una marca el 09-feb, pero ANULADA: no cuenta como que
-- siguió viniendo. Si `fn_fecha_limite_asistencia` mirara marcajes anulados,
-- esta persona saldría con límite `infinity` en vez de su fecha de fin.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, anulada_at, anulada_por, anulada_motivo)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000031412', '00000000-0000-0000-0000-000000031400',
        'entrada', (date '2026-02-09' + time '09:00') at time zone 'America/Lima', 'terminal',
        now(), '00000000-0000-0000-0000-000000031401', 'marca de prueba, se anula a propósito');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000031499', true);

-- ── fn_fecha_limite_asistencia ───────────────────────────────────────────
select is(fn_fecha_limite_asistencia('00000000-0000-0000-0000-000000031410'), '2026-02-06'::date,
  'LÍMITE · ConFin se corta en su fecha_fin_contrato — no marcó después');
select is(fn_fecha_limite_asistencia('00000000-0000-0000-0000-000000031411'), 'infinity'::date,
  'LÍMITE · Desnaturalizado no tiene corte — siguió marcando después de vencido');
select is(fn_fecha_limite_asistencia('00000000-0000-0000-0000-000000031412'), '2026-02-06'::date,
  'LÍMITE · MarcaAnulada se corta igual — la única marca posterior está anulada, no cuenta');
select is(fn_fecha_limite_asistencia('00000000-0000-0000-0000-000000031413'), 'infinity'::date,
  'LÍMITE · SinFin (indefinido, sin fecha_fin_contrato) no tiene corte');

-- ── fn_faltas, ventana 09 al 13 de febrero (toda ella después del 06) ──────
select is((select count(*)::int from fn_faltas('2026-02-09', '2026-02-13')
            where persona_id = '00000000-0000-0000-0000-000000031410'),
          0, 'FALTAS · ConFin no aparece ni una vez — su ventana quedó vacía tras el corte');

select is((select array_agg(fecha order by fecha) from fn_faltas('2026-02-09', '2026-02-13')
            where persona_id = '00000000-0000-0000-0000-000000031411' and not justificada),
          array['2026-02-11'::date, '2026-02-12'::date, '2026-02-13'::date],
          'FALTAS · Desnaturalizado SÍ acumula del 11 al 13 — dejó de venir de verdad, y nada la corta');

select is((select count(*)::int from fn_faltas('2026-02-09', '2026-02-13')
            where persona_id = '00000000-0000-0000-0000-000000031412'),
          0, 'FALTAS · MarcaAnulada tampoco aparece — la marca anulada no le abre la ventana');

-- ── fn_falta_contadores — el mismo espejo que ve el documento disciplinario ─
select is((select en_180 from fn_falta_contadores('00000000-0000-0000-0000-000000031410', '2026-02-09')),
          0, 'MEMO · ConFin no tiene ni un hecho que imputar tras el fin de su contrato');

-- `fn_falta_contadores` no toma `p_hasta`: cuenta hasta HOY de verdad, así que
-- para Desnaturalizado (sin corte) la lista sigue después del 13-feb. Lo que
-- importa acá es que el 11, 12 y 13 SÍ estén — no que la lista termine ahí.
select is((select count(*)::int from fn_falta_contadores('00000000-0000-0000-0000-000000031411', '2026-02-09') c,
                unnest(c.fechas) as f
            where f between '2026-02-11'::date and '2026-02-13'::date),
          3, 'MEMO · Desnaturalizado sí tiene sus tres hechos reales, sin ningún corte artificial');

-- ── Que la 0396 no reabra el hallazgo de la 0292 ────────────────────────────
select ok(
  not has_function_privilege('authenticated', 'fn_falta_contadores(uuid,date)', 'execute'),
  'SEGURIDAD · fn_falta_contadores sigue sin poder llamarse por RPC directo (0292)');
select ok(
  not has_function_privilege('authenticated', 'fn_fecha_limite_asistencia(uuid)', 'execute'),
  'SEGURIDAD · fn_fecha_limite_asistencia es de uso interno, nunca RPC directo');

select * from finish();
rollback;
