-- ============================================================================
-- 179_un_dia_compensatorio_tiene_que_compensar.test.sql
-- ============================================================================
-- Defiende la 0238. El descanso sustitutorio es la alternativa a pagar la
-- sobretasa del 100 % de un feriado trabajado: con el estado en OTORGADO,
-- fn_planilla_calcular la anula. Medido en producción, un feriado baja de
-- S/206.83 a S/104.89.
--
-- Así que un día compensatorio que no compensa le cuesta a esa persona unos cien
-- soles Y su descanso: pierde por los dos lados, y el papel dice que se le dio.
--
-- LAS DOS MITADES. Se prueba que los cinco días que NO compensan se rechacen, y
-- —la que se olvida— que un día bueno siga entrando sin fricción. Un candado que
-- cierra siempre no es un candado: es una pantalla rota, y alguien lo quita en la
-- primera urgencia.
--
-- Y LA SEXTA, QUE ES LA QUE MÁS ME IMPORTA: que un día compensatorio FUTURO se
-- pueda registrar hoy —no hay nada que objetar— y que EMPIECE A DELATARSE SOLO
-- cuando llegue esa fecha y esa persona haya trabajado. No hay cron ni alerta
-- nueva: el motivo se calcula al LEER, así que la misma pregunta hecha más tarde
-- da otra respuesta. Es la prueba 8.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000017900', 'ZZ179', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000017901', 'DcsAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000017900', 'admin', 'x',
        '00000000-0000-0000-0000-000000017909', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, sueldo_fijo)
values ('00000000-0000-0000-0000-000000017902', 'DcsPersona', 'Laboratorio',
        '00000000-0000-0000-0000-000000017900', 'x', '2024-01-01', false);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000017909', true);

-- Lunes a sábado laborables; domingo descansa. Fechas de 2026 elegidas a mano:
-- el 2026-07-28 es MARTES y el 2026-08-02 es DOMINGO.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-000000017902', '2024-01-01', '09:00', '18:00', 60, 60,
        array[1,2,3,4,5,6], 45,
        '{"1":{"e":"09:00","s":"18:00","r":60},"2":{"e":"09:00","s":"18:00","r":60},
          "3":{"e":"09:00","s":"18:00","r":60},"4":{"e":"09:00","s":"18:00","r":60},
          "5":{"e":"09:00","s":"18:00","r":60},"6":{"e":"09:00","s":"18:00","r":60}}'::jsonb);

-- Dos feriados, y el del 28 de julio TRABAJADO (requisito de la 0069).
-- `on conflict` porque los feriados reales del Perú ya vienen cargados por
-- migración: lo que importa es que existan, no quién los puso.
insert into feriados (fecha, nombre) values
  ('2026-07-28', 'Fiestas Patrias'),
  ('2026-08-30', 'Santa Rosa')
on conflict (fecha) do nothing;

insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000017902', '00000000-0000-0000-0000-000000017900', 'entrada',      '2026-07-28T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000017902', '00000000-0000-0000-0000-000000017900', 'salida_final', '2026-07-28T18:00:00-05:00');

-- Y un día que SÍ trabajó después: el 5 de agosto (miércoles).
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000017902', '00000000-0000-0000-0000-000000017900', 'entrada',      '2026-08-05T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000017902', '00000000-0000-0000-0000-000000017900', 'salida_final', '2026-08-05T18:00:00-05:00');

-- Vacaciones aprobadas del 10 al 14 de agosto.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, aprobada_por, aprobada_at, registrada_por)
values ('00000000-0000-0000-0000-000000017902', 'vacaciones', '2026-08-10', '2026-08-14',
        '00000000-0000-0000-0000-000000017901', now(), '00000000-0000-0000-0000-000000017901');


-- ── 1-5 · Los cinco días que NO compensan ───────────────────────────────────
select throws_ok(
  $$ select fn_otorgar_descanso_sustitutorio('00000000-0000-0000-0000-000000017902'::uuid,
       '2026-07-28'::date, '2026-07-20'::date) $$,
  'P0001', null,
  'ANTES · un día libre anterior al feriado no compensa nada');

select throws_ok(
  $$ select fn_otorgar_descanso_sustitutorio('00000000-0000-0000-0000-000000017902'::uuid,
       '2026-07-28'::date, '2026-08-30'::date) $$,
  'P0001', null,
  'OTRO FERIADO · ese día ya iba a estar libre');

select throws_ok(
  $$ select fn_otorgar_descanso_sustitutorio('00000000-0000-0000-0000-000000017902'::uuid,
       '2026-07-28'::date, '2026-08-12'::date) $$,
  'P0001', null,
  'VACACIONES · un día dentro de sus vacaciones aprobadas tampoco compensa');

select throws_ok(
  $$ select fn_otorgar_descanso_sustitutorio('00000000-0000-0000-0000-000000017902'::uuid,
       '2026-07-28'::date, '2026-08-02'::date) $$,
  'P0001', null,
  'DESCANSO SEMANAL · el domingo ya era suyo (esto ya lo hacía la 0069)');

select throws_ok(
  $$ select fn_otorgar_descanso_sustitutorio('00000000-0000-0000-0000-000000017902'::uuid,
       '2026-07-28'::date, '2026-08-05'::date) $$,
  'P0001', null,
  'TRABAJÓ · ese día tiene horas marcadas: no llegó a descansarlo');


-- ── 6 · El plazo avisa y deja pasar con motivo ──────────────────────────────
select throws_ok(
  $$ select fn_otorgar_descanso_sustitutorio('00000000-0000-0000-0000-000000017902'::uuid,
       '2026-07-28'::date, '2026-09-15'::date) $$,
  'P0001', null,
  'PLAZO · a más de 30 días no entra sin decir por qué');

select lives_ok(
  $$ select fn_otorgar_descanso_sustitutorio('00000000-0000-0000-0000-000000017902'::uuid,
       '2026-07-28'::date, '2026-09-15'::date, 'PENDIENTE', null,
       'estuvo con descanso médico las tres semanas siguientes') $$,
  'PLAZO · y con el motivo escrito sí entra: la decisión es de una persona');


-- ── 7 · La otra mitad: un día bueno entra sin fricción ──────────────────────
-- 2026-08-04 es martes, laborable, después del feriado, sin vacaciones, sin
-- marcajes y dentro de los 30 días.
select lives_ok(
  $$ select fn_otorgar_descanso_sustitutorio('00000000-0000-0000-0000-000000017902'::uuid,
       '2026-07-28'::date, '2026-08-04'::date) $$,
  'BUENO · un día laborable, posterior y libre de verdad entra sin problema');


-- ── 8 · El día futuro se delata solo cuando llega ───────────────────────────
-- La fila del 4 de agosto acaba de entrar limpia: `no_compensa_porque` es null.
-- Ahora esa persona trabaja ese día — y la MISMA pregunta, hecha después, cambia
-- de respuesta. Sin cron y sin alertas: el motivo se calcula al leer.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000017902', '00000000-0000-0000-0000-000000017900', 'entrada',      '2026-08-04T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000017902', '00000000-0000-0000-0000-000000017900', 'salida_final', '2026-08-04T17:00:00-05:00');

select is(
  fn_dcs_por_que_no_compensa('00000000-0000-0000-0000-000000017902'::uuid,
    '2026-07-28'::date, '2026-08-04'::date),
  'ese día trabajó: no llegó a descansarlo',
  'FUTURO · el día que se registró bien se delata solo en cuanto ella trabaja esa fecha');


-- ── 9 · Y la pantalla recibe ese mismo motivo, no otro ──────────────────────
-- Si el candado y la pantalla tuvieran cada uno su copia de la regla, dirían
-- cosas distintas sobre la misma fila. Esto exige que sea la misma frase.
select is(
  (select no_compensa_porque from fn_feriados_laborados('2026-07-01'::date, '2026-07-31'::date)
    where persona_id = '00000000-0000-0000-0000-000000017902' and fecha_feriado = '2026-07-28'),
  'ese día trabajó: no llegó a descansarlo',
  'PANTALLA · Feriados muestra exactamente el motivo con el que se bloquea');

select * from finish();
rollback;
