-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 202_el_regimen_de_pension_recuerda_desde_cuando.test.sql
-- ============================================================================
-- La TASA de pensión estaba versionada por fecha desde la 0114/0115. La
-- PERTENENCIA de la persona a un régimen, no: `personas.regimen_pension` era un
-- único valor actual, y `fn_planilla_calcular` lo leía para cualquier periodo.
-- Así que cambiar de régimen hoy reescribía en silencio todos los meses
-- anteriores — emparejando el régimen de hoy con la tasa de entonces.
--
-- La prueba central es la primera: un periodo VIEJO, calculado ANTES y DESPUÉS
-- de un cambio de régimen, tiene que dar lo mismo. Sin la 0261 da 0 %.
--
-- Las demás cierran las puertas por las que el defecto podría volver: que el
-- cambio no se pueda fechar dentro de un periodo pagado, que no queden dos
-- filas cubriendo el mismo día, y que quien no tenga historial siga
-- comportándose exactamente como antes.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000002a0', 'ZZREG', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000002a1', 'RegAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000002a0', 'admin', 'x',
        '00000000-0000-0000-0000-0000000ffa01', '2024-01-01');
set session_replication_role = origin;

-- La protagonista: en ONP, y se va a jubilar más adelante.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      funcion, regimen_pension)
values ('00000000-0000-0000-0000-0000000002a2', 'RegOnp', 'Lab',
        '00000000-0000-0000-0000-0000000002a0', 'x', '2024-01-01',
        'taller_produccion', 'onp');

-- Y una segunda persona SIN régimen ni historial, para comprobar que el
-- respaldo deja el comportamiento anterior intacto.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion)
values ('00000000-0000-0000-0000-0000000002a3', 'RegSinNada', 'Lab',
        '00000000-0000-0000-0000-0000000002a0', 'x', '2024-01-01', 'taller_produccion');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000002a2', 'colibri', 1500, '2024-01-01'),
       ('00000000-0000-0000-0000-0000000002a3', 'colibri', 1500, '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values ('00000000-0000-0000-0000-0000000002a2', '2024-01-01', '09:00', '15:30', 0, 0,
        array[1,2,3,4,5,6], 39),
       ('00000000-0000-0000-0000-0000000002a3', '2024-01-01', '09:00', '15:30', 0, 0,
        array[1,2,3,4,5,6], 39);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ffa01', true);

-- Dos días trabajados en el periodo VIEJO, para que tenga base sobre la que
-- descontar. Sin base, la tasa daría igual y la prueba no probaría nada.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000002a2', '00000000-0000-0000-0000-0000000002a0', 'entrada',      '2026-03-03T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000002a2', '00000000-0000-0000-0000-0000000002a0', 'salida_final', '2026-03-03T15:30:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000002a2', '00000000-0000-0000-0000-0000000002a0', 'entrada',      '2026-03-04T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000002a2', '00000000-0000-0000-0000-0000000002a0', 'salida_final', '2026-03-04T15:30:00-05:00');

-- El relleno de la 0261 solo escribió a quien existía cuando se pegó. Esta
-- persona nace después, así que se le pone su fila como lo haría la pantalla.
insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde, nota)
values ('00000000-0000-0000-0000-0000000002a2', 'onp', '2024-01-01', 'alta de laboratorio');


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · LA PRUEBA CENTRAL: el pasado no se mueve
-- ════════════════════════════════════════════════════════════════════════════

-- Antes de jubilarse: marzo la ve en ONP.
select is(
  (select f->>'regimen_pension'
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000002a2'),
  'onp',
  'antes del cambio, marzo la ve en ONP'
);

select is(
  (select round((f->>'tasa_afp')::numeric, 4)
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000002a2'),
  0.1300,
  'y le aplica el 13 % de ONP'
);

-- Se jubila, con efecto desde agosto.
select lives_ok(
  $$select fn_cambiar_regimen_pension(
      '00000000-0000-0000-0000-0000000002a2', 'jubilada', '2026-08-01',
      'se jubiló y sigue trabajando')$$,
  'el cambio de régimen se registra'
);

-- ── AQUÍ ESTABA EL DEFECTO ──────────────────────────────────────────────────
-- Sin la 0261 estas dos daban 'jubilada' y 0.0000: marzo, un mes ya cerrado,
-- cambiaba de cifra por algo que pasó en agosto.
select is(
  (select f->>'regimen_pension'
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000002a2'),
  'onp',
  'DESPUÉS de jubilarse, marzo la SIGUE viendo en ONP'
);

select is(
  (select round((f->>'tasa_afp')::numeric, 4)
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000002a2'),
  0.1300,
  'y le sigue aplicando el 13 %, no el 0 % de jubilada'
);

-- Y el presente sí cambia, que es lo que se pidió.
select is(
  (select f->>'regimen_pension'
     from jsonb_array_elements(fn_planilla_calcular('2026-08-01','2026-08-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000002a2'),
  'jubilada',
  'agosto sí la ve jubilada — el cambio rige hacia adelante'
);


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · Quien no tiene historial se comporta como antes
-- ════════════════════════════════════════════════════════════════════════════
-- El `coalesce` de respaldo es lo que hace que la migración se pueda pegar sin
-- mover un céntimo. Si esto fallara, aplicarla cambiaría cifras el mismo día.

select is(
  (select f->>'regimen_pension'
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000002a3'),
  null,
  'sin régimen y sin historial, la planilla responde igual que antes'
);


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · Las puertas por las que el defecto podría volver
-- ════════════════════════════════════════════════════════════════════════════

-- La fila anterior quedó cerrada el día antes, sin solape ni hueco.
select is(
  (select vigente_hasta from asignaciones_regimen_pension
    where persona_id = '00000000-0000-0000-0000-0000000002a2' and regimen = 'onp'),
  date '2026-07-31',
  'la fila anterior se cierra el día antes: ni solape ni hueco'
);

-- La ficha sigue diciendo la verdad de hoy.
select is(
  (select regimen_pension from personas where id = '00000000-0000-0000-0000-0000000002a2'),
  'jubilada',
  'y la ficha de la persona queda en sintonía'
);

-- Dos filas cubriendo el mismo día no pueden existir: si pudieran, «¿en qué
-- régimen estaba?» tendría dos respuestas y el limit 1 elegiría una en silencio.
select throws_ok(
  $$insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde, vigente_hasta)
    values ('00000000-0000-0000-0000-0000000002a2', 'integra', '2026-05-01', '2026-06-01')$$,
  '23P01',
  null,
  'dos regímenes solapados quedan prohibidos por la base'
);

-- Y no se puede fechar un cambio dentro de un periodo YA PAGADO: eso movería
-- lo que ese mes calcula, que es justo lo que esta migración vino a impedir.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at)
values ('eeeeeeee-0000-0000-0000-0000000002a0', '2026-03-01', '2026-03-31', 'pagado', now());

select throws_ok(
  $$select fn_cambiar_regimen_pension(
      '00000000-0000-0000-0000-0000000002a3', 'integra', '2026-03-15', 'tarde')$$,
  null,
  null,
  'un cambio fechado dentro de un periodo pagado se rechaza'
);

select * from finish();
rollback;
