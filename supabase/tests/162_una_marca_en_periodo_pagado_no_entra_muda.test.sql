-- ============================================================================
-- 162_una_marca_en_periodo_pagado_no_entra_muda.test.sql
-- ============================================================================
-- Lo que fija la 0207, y lo que NO — porque medirlo cambió el diagnóstico.
--
-- `docs/hallazgos-abiertos.md` decía que una marca dentro de un periodo pagado
-- hacía que «el número de una planilla ya pagada cambie solo». Se reprodujo el
-- 2026-08-10 contra el esquema completo y **es falso**: `fn_recalcular_jornada`
-- lleva el candado de la 0138 y aguanta. Las horas no se mueven.
--
-- Lo que sí pasaba: la marca entraba con `estado_revision = 'normal'`, o sea
-- **muda**. Desde ese momento los marcajes del día decían una cosa y la jornada
-- pagada otra, sin que nada lo señalara a nadie.
--
-- LAS TRES MITADES QUE DEFIENDE, y se contradicen si una se rompe:
--
--   · La marca ENTRA. Siempre. Rechazarla es lo único que no se puede hacer:
--     la terminal reintenta seis veces y acaba descartándola, y perder el
--     registro de alguien que sí estuvo es peor que un día que no cuadra.
--   · Entra SEÑALADA, para que aparezca en Correcciones.
--   · Y el pago NO se mueve. Si alguna vez esta prueba falla porque las horas
--     cambiaron, el defecto está en el candado de fn_recalcular_jornada, no acá.
--
-- POR QUÉ SE PRUEBAN LOS DOS CAMINOS
--   Una marca llega a existir por dos sitios: el `insert` normal y la
--   RECONCILIACIÓN, donde una salida_final real pisa el auto-cierre sintético
--   y **retorna antes** del insert. El segundo es el más delicado —cambia la
--   hora de una marca que ya estaba dentro del periodo pagado— y es el que se
--   olvida al leer la función de arriba abajo.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000f400', 'ZZPAG', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-00000000f401', 'PagPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000f400', 'test-hash');
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000000f40e', '00000000-0000-0000-0000-00000000f400',
        'Mac mini de laboratorio', true, '00000000-0000-0000-0000-00000000f40a');
set session_replication_role = origin;

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values ('00000000-0000-0000-0000-00000000f401', '2026-01-01', '09:00', '18:00', 60, 60,
        array[1,2,3,4,5], 45);

-- Un periodo CERRADO Y PAGADO, y otro día fuera de él como control.
insert into periodos_planilla (fecha_ini, fecha_fin, estado, pagado_at)
values (date '2026-06-29', date '2026-07-28', 'pagado', now());

-- La jornada tal como se pagó.
insert into jornadas (persona_id, fecha, sede_id, entrada_ts, salida_final_ts,
                      horas_trabajadas, minutos_tarde, estado)
values ('00000000-0000-0000-0000-00000000f401', date '2026-07-15',
        '00000000-0000-0000-0000-00000000f400',
        timestamptz '2026-07-15 09:00-05', timestamptz '2026-07-15 18:00-05',
        8.00, 0, 'cerrada');

-- ── 1-3 · El camino normal: entra, señalada, y sin tocar el pago ───────────
select is(
  (select estado_revision::text from fn_registrar_marcaje(
     '00000000-0000-0000-0000-00000000f401', 'entrada'::tipo_marca,
     timestamptz '2026-07-15 08:55-05', '00000000-0000-0000-0000-00000000fa01',
     'terminal'::origen_marca, '00000000-0000-0000-0000-00000000f40e')),
  'pendiente_revision',
  'Una marca dentro de un periodo pagado entra SEÑALADA, no muda');

select is(
  (select count(*)::int from marcajes
    where client_uuid = '00000000-0000-0000-0000-00000000fa01'),
  1,
  'Y entra: jamás se rechaza una marca real, la terminal la perdería tras seis reintentos');

select is(
  (select horas_trabajadas from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000f401' and fecha = date '2026-07-15'),
  8.00::numeric(6,2),
  'El pago NO se mueve: el candado de la 0138 en fn_recalcular_jornada aguanta');

-- ── 4-5 · Fuera del periodo pagado no hay falsa alarma ────────────────────
-- Es la otra mitad, y la que se rompe si alguien «simplifica» sellando siempre.
-- Un freno que chilla en cada marca se desactiva a la semana.
select is(
  (select estado_revision::text from fn_registrar_marcaje(
     '00000000-0000-0000-0000-00000000f401', 'entrada'::tipo_marca,
     timestamptz '2026-08-05 08:55-05', '00000000-0000-0000-0000-00000000fa02',
     'terminal'::origen_marca, '00000000-0000-0000-0000-00000000f40e')),
  'normal',
  'Fuera del periodo pagado la marca entra normal: sin falsa alarma');

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000f401'
      and estado_revision = 'pendiente_revision'),
  1,
  'Solo se señaló la que cayó dentro del pagado, no las dos');

-- ── 6-8 · La RECONCILIACIÓN, que es el camino que se olvida ───────────────
-- Una salida_final real que llega después del auto-cierre sintético lo PISA y
-- retorna antes del insert. Dentro de un periodo pagado eso cambia la hora de
-- una marca ya existente, y hasta la 0207 además le ponía 'normal' a secas.
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen, estado_revision)
values ('00000000-0000-0000-0000-00000000fa03', '00000000-0000-0000-0000-00000000f401',
        '00000000-0000-0000-0000-00000000f400', '00000000-0000-0000-0000-00000000f40e',
        'salida_final', timestamptz '2026-07-15 18:00-05', 'auto_cierre', 'pendiente_revision');

select is(
  (select estado_revision::text from fn_registrar_marcaje(
     '00000000-0000-0000-0000-00000000f401', 'salida_final'::tipo_marca,
     timestamptz '2026-07-15 19:30-05', '00000000-0000-0000-0000-00000000fa04',
     'terminal'::origen_marca, '00000000-0000-0000-0000-00000000f40e')),
  'pendiente_revision',
  'La reconciliación dentro de un periodo pagado también queda señalada');

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000f401'
      and tipo = 'salida_final'
      and (timestamp_marca at time zone 'America/Lima')::date = date '2026-07-15'),
  1,
  'Y sigue reconciliando, no duplicando: una sola salida final ese día');

select is(
  (select horas_trabajadas from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000f401' and fecha = date '2026-07-15'),
  8.00::numeric(6,2),
  'Tampoco por ese camino se mueve lo que ya se pagó');

select * from finish();
rollback;
