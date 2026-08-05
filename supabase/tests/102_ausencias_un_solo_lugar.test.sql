-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 102_ausencias_un_solo_lugar.test.sql
-- ============================================================================
-- Lo que esta prueba vigila, por orden de importancia:
--
--   1. Que un día de permiso concedido DEJE de contar como falta injustificada.
--      Hasta la 0101, a quien se le moría un familiar el sistema le abría
--      expediente disciplinario por los días que la empresa le concedió.
--   2. Que las dos definiciones —la de la pantalla (fn_faltas) y la del papel
--      que se imprime y se entrega (fn_falta_contadores)— digan lo mismo. Es la
--      divergencia que ya costó la 0094.
--   3. Que el pago dependa del documento y no de la etiqueta: descanso médico
--      exige papel con colegiatura; descanso por salud no exige nada, no paga,
--      y tampoco acusa.
--   4. Que la mudanza sea invisible: `vacaciones` dejó de ser una tabla y
--      fn_vacaciones_resumen no se enteró.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000a10a', 'ZZAUS', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000a20a', 'AusAdmin', 'Lab', '00000000-0000-0000-0000-00000000a10a', 'admin', 'x', '00000000-0000-0000-0000-00000000aa0a', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000a30a', 'AusDuelo', 'Lab', '00000000-0000-0000-0000-00000000a10a', 'x', '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-00000000a30a', '2024-01-01', '09:00', '18:00', 60, 60,
        array[1,2,3,4,5,6], 48,
        '{"1":{"e":"09:00","s":"18:00","r":60},"2":{"e":"09:00","s":"18:00","r":60},
          "3":{"e":"09:00","s":"18:00","r":60},"4":{"e":"09:00","s":"18:00","r":60},
          "5":{"e":"09:00","s":"18:00","r":60},"6":{"e":"09:00","s":"18:00","r":60}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000aa0a', true);

-- ── El daño que venimos a cortar ────────────────────────────────────────────
-- 6, 7 y 8 de julio de 2026: lunes, martes y miércoles. Días laborables sin
-- marcar. Antes de registrar nada, son tres faltas injustificadas.
select is((select count(*)::int from fn_faltas('2026-07-06', '2026-07-08') f
           where f.persona_id = '00000000-0000-0000-0000-00000000a30a' and f.justificada = false),
          3, 'DE PARTIDA · tres días sin marcar son tres faltas injustificadas');

-- Se le murió un familiar y CAYLA le concedió esos tres días.
select lives_ok($$ select fn_registrar_ausencia(
    '00000000-0000-0000-0000-00000000a30a', 'duelo', '2026-07-06', '2026-07-08',
    'fallecimiento de familiar directo') $$,
  'DUELO · el permiso se puede registrar como un rango, no día por día');

select is((select count(*)::int from fn_faltas('2026-07-06', '2026-07-08') f
           where f.persona_id = '00000000-0000-0000-0000-00000000a30a' and f.justificada = false),
          0, 'DUELO · y esos tres días dejan de ser faltas injustificadas');

-- El papel que se imprime y se ENTREGA tiene que decir lo mismo que la pantalla.
select is((select count(*)::int
           from fn_falta_contadores('00000000-0000-0000-0000-00000000a30a', '2026-07-06') c,
                unnest(c.fechas) as f
           where f between '2026-07-06'::date and '2026-07-08'::date),
          0, 'ESPEJO · el documento disciplinario tampoco los lista como inasistencia');

-- ── El pago depende del documento, no de la etiqueta ────────────────────────
select throws_ok($$ select fn_registrar_ausencia(
    '00000000-0000-0000-0000-00000000a30a', 'descanso_medico', '2026-07-13', '2026-07-14') $$,
  null, null, 'MÉDICO · sin profesional, colegiatura y fecha, el descanso médico se rechaza');

select lives_ok($$ select fn_registrar_ausencia(
    '00000000-0000-0000-0000-00000000a30a', 'descanso_medico', '2026-07-13', '2026-07-14',
    'gripe', 'Dra. Lab', 'CMP 12345', '2026-07-13') $$,
  'MÉDICO · con el documento completo sí entra');

-- Y como paga, nace SIN aprobar: convertir días en plata es de DO.
select is((select aprobada_at is null from ausencias
           where persona_id = '00000000-0000-0000-0000-00000000a30a' and tipo = 'descanso_medico'),
          true, 'MÉDICO · nace sin aprobar: lo que paga lo aprueba Desarrollo Organizacional');

-- El resfriado de la vida real: sin papel, sin cola en EsSalud, sin pago —
-- y sin expediente disciplinario.
select lives_ok($$ select fn_registrar_ausencia(
    '00000000-0000-0000-0000-00000000a30a', 'salud', '2026-07-20', '2026-07-20', 'resfriado') $$,
  'SALUD · un descanso por salud no exige ningún documento');

select is((select t.paga from ausencias a join tipos_ausencia t on t.codigo = a.tipo
           where a.persona_id = '00000000-0000-0000-0000-00000000a30a' and a.tipo = 'salud'),
          false, 'SALUD · no paga…');

select is((select count(*)::int from fn_faltas('2026-07-20', '2026-07-20') f
           where f.persona_id = '00000000-0000-0000-0000-00000000a30a' and f.justificada = false),
          0, 'SALUD · …pero tampoco cuenta como falta injustificada');

-- ── Estados imposibles ──────────────────────────────────────────────────────
select throws_ok($$ select fn_registrar_ausencia(
    '00000000-0000-0000-0000-00000000a30a', 'permiso_personal', '2026-07-07', '2026-07-07') $$,
  null, null, 'SOLAPE · nadie puede estar de duelo y de permiso personal el mismo día');

-- ── El candado de la planilla pagada ────────────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('a0a0a0a0-0000-0000-0000-000000000101', '2026-08-01', '2026-08-31', 'pagado');

select throws_ok($$ select fn_registrar_ausencia(
    '00000000-0000-0000-0000-00000000a30a', 'permiso_personal', '2026-08-10', '2026-08-10') $$,
  null, null, 'PAGADO · no se registra una ausencia dentro de un periodo ya pagado');

-- ── La mudanza es invisible ─────────────────────────────────────────────────
-- `vacaciones` dejó de ser una tabla y pasó a ser una vista sobre `ausencias`.
-- Quien la lea no se puede enterar.
select fn_set_vacaciones('00000000-0000-0000-0000-00000000a30a', '2026-09-07', '2026-09-11', 'descanso anual');

select is((select count(*)::int from vacaciones
           where persona_id = '00000000-0000-0000-0000-00000000a30a'),
          1, 'MUDANZA · registrar por la puerta vieja sigue apareciendo en `vacaciones`');

select is((select tipo from ausencias
           where persona_id = '00000000-0000-0000-0000-00000000a30a' and fecha_inicio = '2026-09-07'),
          'vacaciones', 'MUDANZA · y la fila vive en `ausencias`, que es donde tiene que estar');

select * from finish();
rollback;
