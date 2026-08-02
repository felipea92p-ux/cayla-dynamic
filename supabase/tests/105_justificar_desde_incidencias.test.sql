-- ============================================================================
-- 105_justificar_desde_incidencias.test.sql — el botón Justificar, de verdad
-- ============================================================================
-- El 1-ago-2026 Felipe no pudo justificar una falta en producción. El error era
-- «there is no unique or exclusion constraint matching the ON CONFLICT
-- specification»: la 0101 convirtió `justificaciones_asistencia` en una VISTA y
-- `fn_set_justificacion` se quedó haciendo un upsert contra ella. Una vista no
-- tiene índices únicos, así que la operación entera se rechazaba.
--
-- Lo que hace grave a este fallo no es el error en sí, es a qué da de comer:
-- una falta que no se puede justificar sigue contando como INJUSTIFICADA, y las
-- faltas injustificadas alimentan el expediente disciplinario. El sistema
-- estaba acusando a gente por días que la empresa sí les había concedido, solo
-- porque el botón para decirlo estaba roto.
--
-- Existía `fn_justificar_falta` sana desde la 0101, pero la pantalla nunca dejó
-- de llamar a la vieja. Por eso esta prueba ataca `fn_set_justificacion`, que
-- es la que de verdad se usa, y no la que debería usarse.
--
-- Se prueba de punta a punta: que guarde, que el día deje de contar como falta,
-- que se pueda CAMBIAR el motivo (era un upsert, y eso no se puede perder), que
-- quitarla la devuelva al conteo, y que el descanso médico no se cuele sin
-- documento convirtiendo un día pagado en uno que no paga.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000b10b', 'ZZJUS', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000b20b', 'JusAdmin', 'Lab',
        '00000000-0000-0000-0000-00000000b10b', 'admin', 'x',
        '00000000-0000-0000-0000-00000000bb0b', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000b30b', 'JusFalta', 'Lab',
        '00000000-0000-0000-0000-00000000b10b', 'x', '2024-01-01');

-- Lunes a sábado, para que el 6-jul-2026 (lunes) sea día laborable
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-00000000b30b', '2024-01-01', '09:00', '18:00', 60, 60,
        array[1,2,3,4,5,6], 48,
        '{"1":{"e":"09:00","s":"18:00","r":60},"2":{"e":"09:00","s":"18:00","r":60},
          "3":{"e":"09:00","s":"18:00","r":60},"4":{"e":"09:00","s":"18:00","r":60},
          "5":{"e":"09:00","s":"18:00","r":60},"6":{"e":"09:00","s":"18:00","r":60}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000bb0b', true);

-- ── De partida: un día sin marcar es una falta injustificada ────────────────
select is((select count(*)::int from fn_faltas('2026-07-06', '2026-07-06') f
           where f.persona_id = '00000000-0000-0000-0000-00000000b30b' and f.justificada = false),
          1, 'DE PARTIDA · el lunes sin marcar cuenta como falta injustificada');

-- ── El fallo que trajo aquí ────────────────────────────────────────────────
-- Antes de la 0120 esta llamada moría con 42P10. Es LA prueba de regresión: si
-- alguien vuelve a apuntar esta función a la vista, esto se pone rojo.
select lives_ok(
  $$ select fn_set_justificacion('00000000-0000-0000-0000-00000000b30b',
       '2026-07-06', 'permiso_concedido', 'Permiso concedido por la encargada') $$,
  'JUSTIFICAR · el botón guarda sin reventar contra la vista (era el 42P10)');

select is((select count(*)::int from fn_faltas('2026-07-06', '2026-07-06') f
           where f.persona_id = '00000000-0000-0000-0000-00000000b30b' and f.justificada = false),
          0, 'JUSTIFICAR · y ese día deja de contar como falta injustificada');

-- Se guardó donde viven todas las ausencias, no en un rincón aparte
select is((select a.tipo from ausencias a
           where a.persona_id = '00000000-0000-0000-0000-00000000b30b' and a.anulada_at is null),
          'permiso_personal',
          'UN SOLO LUGAR · quedó en ausencias, con el nombre nuevo del motivo');

select is((select count(*)::int from justificaciones_asistencia j
           where j.persona_id = '00000000-0000-0000-0000-00000000b30b' and j.fecha = '2026-07-06'),
          1, 'UN SOLO LUGAR · y la vista de siempre lo sigue viendo');

-- ── Cambiar el motivo: era un upsert y no se puede perder ──────────────────
-- Sin esto, un motivo mal elegido sería imposible de corregir desde la pantalla:
-- `ausencias_sin_solape` rechazaría la segunda.
select lives_ok(
  $$ select fn_set_justificacion('00000000-0000-0000-0000-00000000b30b',
       '2026-07-06', 'cumpleanos', null) $$,
  'CORREGIR · volver a justificar el mismo día cambia el motivo, no falla');

select is((select count(*)::int from ausencias a
           where a.persona_id = '00000000-0000-0000-0000-00000000b30b' and a.anulada_at is null),
          1, 'CORREGIR · queda UNA sola ausencia viva, no dos superpuestas');

select is((select a.tipo from ausencias a
           where a.persona_id = '00000000-0000-0000-0000-00000000b30b' and a.anulada_at is null),
          'cumpleanos', 'CORREGIR · y es el motivo nuevo');

select is((select count(*)::int from fn_faltas('2026-07-06', '2026-07-06') f
           where f.persona_id = '00000000-0000-0000-0000-00000000b30b' and f.justificada = false),
          0, 'CORREGIR · el día sigue sin contar como falta');

-- ── Quitarla la devuelve al conteo ─────────────────────────────────────────
select lives_ok(
  $$ select fn_quitar_justificacion('00000000-0000-0000-0000-00000000b30b', '2026-07-06') $$,
  'QUITAR · se puede retirar la justificación');

select is((select count(*)::int from fn_faltas('2026-07-06', '2026-07-06') f
           where f.persona_id = '00000000-0000-0000-0000-00000000b30b' and f.justificada = false),
          1, 'QUITAR · y el día vuelve a contar como falta injustificada');

-- ── El descanso médico no se cuela sin documento ───────────────────────────
-- Paga, y desde la 0101 exige papel. Aceptarlo aquí en silencio (mapeándolo a
-- «salud») dejaría sin pagar el día a quien sí entregó su certificado.
select throws_ok(
  $$ select fn_set_justificacion('00000000-0000-0000-0000-00000000b30b',
       '2026-07-07', 'descanso_medico', null) $$,
  null, null,
  'MÉDICO · el diálogo rápido no acepta descanso médico: deriva a Ausencias, donde se adjunta el documento');

select * from finish();
rollback;
