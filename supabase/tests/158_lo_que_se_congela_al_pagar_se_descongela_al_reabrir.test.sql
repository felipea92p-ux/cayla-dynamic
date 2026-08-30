-- ============================================================================
-- 158_lo_que_se_congela_al_pagar_se_descongela_al_reabrir.test.sql
-- ============================================================================
-- EL CASO, medido el 2026-08-10:
--
--   Una planilla pagada está bien protegida: fn_recalcular_jornada sale en
--   silencio si la fecha cae en un periodo pagado (candado de la 0138, hoy en
--   la 0191), fn_planilla_calcular suma `jornadas` y no `marcajes`, y la 0096
--   guarda una foto inmutable. Las tres capas funcionan.
--
--   Lo que no existía era la operación contraria. Mientras el periodo está
--   pagado entran marcas reales —la cola offline del terminal que sincroniza
--   tarde— y su jornada no se recalcula, a propósito. Después alguien reabre el
--   periodo para corregir algo y fn_revertir_pago no recalculaba nada: se
--   corregía sobre las cifras viejas.
--
--   Y sin ninguna señal. fn_planilla_foto_diferencias compara la foto contra un
--   recálculo que lee esas mismas jornadas congeladas: los dos coinciden y la
--   pantalla dice «sin diferencias». Es el único punto del sistema donde un
--   número equivocado tiene toda la apariencia de estar verificado.
--
-- QUÉ DEFIENDE ESTE ARCHIVO
--
--   Las dos mitades, que es la lección de la 141: que dentro de lo pagado nada
--   se mueva, Y que al reabrir todo vuelva a moverse. Un descongelador que no
--   descongela y un candado que cierra siempre se leen igual de verdes.
--
--   Y una tercera cosa, que es la que de verdad puede hacer daño: que un día
--   SIN NINGÚN MARCAJE sobreviva a la reapertura. fn_recalcular_jornada borra
--   la jornada de un día que se quedó sin marcas —es lo que promete— y la 0045
--   cargó 1.427 jornadas de 2025 sin un solo marcaje: la historia diaria de
--   siete personas, la que sostiene sus gratificaciones y su CTS. Reabrir un
--   periodo de 2025 las habría borrado dentro de la misma transacción que dice
--   estar arreglando algo. Es la prueba 8.
--
-- POR QUÉ CADA DÍA DEL MONTAJE ES UN DÍA DISTINTO
--   El 10 de junio prueba el auto-cierre y el 15 el descongelador, y no se
--   comparten. Si el auto-cierre se probara sobre el 15 —que ya tiene una
--   salida_final viva— la prueba pasaría por el candado equivocado: el de «no
--   pongas una segunda salida donde ya hay una», que existe desde la 0095. El
--   error habría dicho justo lo que queremos oír sin que el candado nuevo
--   existiera.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000200', 'ZZ200', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000201', 'DosciAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000000200', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000000209', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000202', 'DosciPersona', 'Laboratorio',
        '00000000-0000-0000-0000-000000000200', 'test-hash', '2024-01-01');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000209', true);

-- ── El montaje: junio y julio, los dos ABIERTOS todavía ─────────────────────
-- Junio se marca pagado más abajo, DESPUÉS de que existan sus jornadas. Tiene
-- que ser en este orden: con el periodo ya pagado, el candado de la 0191 impide
-- que la jornada llegue a crearse y no habría nada que congelar.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000020aa', '2026-06-01', '2026-06-30', 'abierto'),
  ('00000000-0000-0000-0000-0000000020bb', '2026-07-01', '2026-07-31', 'abierto');

-- 10 de junio: entró y nunca marcó salida. Es la candidata del auto-cierre.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000000202',
        '00000000-0000-0000-0000-000000000200', 'entrada', '2026-06-10T09:00:00-05:00');

-- 15 de junio: entró. Su salida llegará tarde, con el periodo ya pagado.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000000202',
        '00000000-0000-0000-0000-000000000200', 'entrada', '2026-06-15T09:00:00-05:00');

-- 15 de julio: la otra mitad. Mismo caso que el 10 de junio pero en un periodo
-- abierto, para exigir que el auto-cierre SIGA funcionando donde debe.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000000202',
        '00000000-0000-0000-0000-000000000200', 'entrada', '2026-07-15T09:00:00-05:00');

-- 20 de junio: una jornada cargada a mano, SIN NINGÚN MARCAJE. Es la forma
-- exacta de las 1.427 filas que la 0045 importó de 2025.
insert into jornadas (persona_id, fecha, sede_id, entrada_ts, salida_final_ts, horas_trabajadas, estado)
values ('00000000-0000-0000-0000-000000000202', '2026-06-20',
        '00000000-0000-0000-0000-000000000200',
        '2026-06-20T09:00:00-05:00', '2026-06-20T18:00:00-05:00', 9.00, 'cerrada');

-- ── Y ahora junio se paga ───────────────────────────────────────────────────
update periodos_planilla set estado = 'pagado', pagado_at = now()
where id = '00000000-0000-0000-0000-0000000020aa';

-- La salida del 15 sincroniza tarde, con el periodo ya cerrado. Entra —los
-- marcajes son append-only— pero no debe mover la jornada.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000000202',
        '00000000-0000-0000-0000-000000000200', 'salida_final', '2026-06-15T18:00:00-05:00');


-- ── 1-2 · La pregunta, dicha una sola vez ───────────────────────────────────
-- CAMBIO ENTREGA 2 (0327): fn_fecha_en_periodo_pagado gana un segundo
-- argumento, el persona_id — mira el grupo (tipo_vinculo) de ESA persona en
-- vez del periodo entero. DosciPersona es 'planilla' por defecto y el
-- periodo de junio no tiene ninguna fila en periodo_grupo_pago todavía
-- (nunca se congeló por grupo en este montaje), así que cae en la
-- compatibilidad hacia atrás de la 0327: se lee por el agregado del
-- periodo, igual que antes de esta migración.
select ok(fn_fecha_en_periodo_pagado('2026-06-15'::date, '00000000-0000-0000-0000-000000000202'::uuid),
  'HELPER · una fecha de junio cae dentro de un periodo pagado');

select ok(fn_fecha_en_periodo_pagado('2026-07-15'::date, '00000000-0000-0000-0000-000000000202'::uuid) is not true,
  'HELPER · una fecha de julio, con su periodo abierto, no');


-- ── 3-4 · El auto-cierre: las dos mitades ───────────────────────────────────
select fn_auto_cierre();

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-000000000202'
      and origen = 'auto_cierre'
      and (timestamp_marca at time zone 'America/Lima')::date = '2026-06-10'),
  0,
  'PAGADO · el cron no le inventa una salida a un día de un mes ya pagado');

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-000000000202'
      and origen = 'auto_cierre'
      and (timestamp_marca at time zone 'America/Lima')::date = '2026-07-15'),
  1,
  'ABIERTO · y sigue cerrando el día olvidado de un periodo abierto');


-- ── 5 · Congelado: la premisa sobre la que todo esto se apoya ───────────────
-- Si esto fallara, el candado de la 0191 se habría perdido y el resto de la
-- prueba estaría midiendo otra cosa.
select ok(
  (select salida_final_ts is null and horas_trabajadas is null
     from jornadas
    where persona_id = '00000000-0000-0000-0000-000000000202'
      and fecha = '2026-06-15'),
  'CONGELADO · la salida que llegó tarde no movió la jornada de un mes pagado');


-- ── 6-7 · Se reabre, y se descongela ────────────────────────────────────────
select fn_revertir_pago('00000000-0000-0000-0000-0000000020aa'::uuid,
                        'Prueba: reabrir para corregir el 15 de junio');

select ok(
  (select salida_final_ts is not null
     from jornadas
    where persona_id = '00000000-0000-0000-0000-000000000202'
      and fecha = '2026-06-15'),
  'DESCONGELA · al reabrir, la jornada ya refleja la salida que había llegado tarde');

select ok(
  (select horas_trabajadas is not null
     from jornadas
    where persona_id = '00000000-0000-0000-0000-000000000202'
      and fecha = '2026-06-15'),
  'DESCONGELA · y las horas, que es lo que la planilla suma, existen otra vez');


-- ── 8 · La historia cargada a mano sobrevive ────────────────────────────────
select is(
  (select count(*)::int from jornadas
    where persona_id = '00000000-0000-0000-0000-000000000202'
      and fecha = '2026-06-20'),
  1,
  'HISTORIA · un día sin ningún marcaje sigue ahí después de reabrir (las 1.427 de la 0045)');

select * from finish();
rollback;
