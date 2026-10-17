-- ============================================================================
-- 420_la_constancia_mensual_se_pide_desde_el_dia_1.test.sql
-- ============================================================================
-- Lo que promete la 0526: un apoyo educativo de frecuencia MENSUAL pide la
-- constancia de este mes desde el día 1, sin esperar al día del pago, y el
-- plazo sigue siendo el de siempre. Contado desde tres lados:
--   · lo que cambia: el mensual cuyo pago de este mes todavía no llega;
--   · lo que NO cambia: las otras frecuencias, el pago del mes siguiente, lo
--     vencido de siempre, lo pendiente, lo rechazado, lo que no empezó;
--   · el ciclo entero, con las funciones de verdad: la integrante envía, DO
--     aprueba, el calendario avanza y el mes siguiente se abre el día 1.
--
-- El reloj se fija en 2031 (una fecha real caduca el día que la pasa, y «el día
-- 1» no se puede probar con el calendario de hoy). `fn_hoy_lima()` se redefine
-- DENTRO de esta transacción, que termina en rollback: nadie más la ve. Los
-- periodos de planilla 29→28 también son de 2031, para no tocar los reales.
--
-- Los casos K09 y K08 son los de «ya hay una constancia aprobada este mes /
-- el mes pasado». El de pagar ANTES de la fecha declarada (K08) NO se prueba
-- más allá del día en que se sube: lo que pasa después es el hueco de
-- `fn_educacion_avanzar_calendario` que la 0526 deja anotado, y una prueba que
-- fijara ese comportamiento lo daría por bueno.
-- ============================================================================
begin;
select plan(45);

-- ── El reloj ────────────────────────────────────────────────────────────────
create or replace function fn_hoy_lima()
returns date language sql stable set search_path = public as $fn$
  select coalesce(nullif(current_setting('test.hoy', true), '')::date,
                  (now() at time zone 'America/Lima')::date);
$fn$;
select set_config('test.hoy', '2031-05-03', true);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000526a00', 'ZZ526', 'Sede de laboratorio 526', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000526d01', 'MesDO', 'Laboratorio',
   '00000000-0000-0000-0000-000000526a00', 'lider_do', 'test-hash',
   '00000000-0000-0000-0000-000000526f01', '2020-01-01'),
  ('00000000-0000-0000-0000-000000526d02', 'MesAna', 'Laboratorio',
   '00000000-0000-0000-0000-000000526a00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000526f02', '2025-01-02');
-- Una persona por estudio: así ningún caso comparte techo ni vigencia con otro.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso)
select ('00000000-0000-0000-0000-000000526e' || lpad(n::text, 2, '0'))::uuid,
       'MesK' || lpad(n::text, 2, '0'), 'Laboratorio',
       '00000000-0000-0000-0000-000000526a00', 'integrante', 'test-hash', '2025-01-02'
  from generate_series(1, 19) n;
set session_replication_role = origin;

-- Periodos 29→28 de 2031. Mayo de 2031 va del 29/04 al 28/05: su plazo es el 23.
insert into periodos_planilla (fecha_ini, fecha_fin, estado, pagado_at) values
  ('2031-03-29', '2031-04-28', 'pagado', now()),
  ('2031-04-29', '2031-05-28', 'pagado', now()),
  ('2031-05-29', '2031-06-28', 'pagado', now()),
  ('2031-06-29', '2031-07-28', 'pagado', now());

-- Los estudios. K01–K19 son uno por persona; L1 es el de Ana, para el ciclo real.
--   institucion, frecuencia, próximo pago, desde, hasta
create temp table _caso (n int, inst text, frec text, prox date, desde date, hasta date);
insert into _caso values
  ( 1, 'K01 mensual, pago el 15',                'mensual', '2031-05-15', '2031-01-01', '2031-12-31'),
  ( 2, 'K02 por ciclo',                          'ciclo',   '2031-05-15', '2031-01-01', '2031-12-31'),
  ( 3, 'K03 pago único',                         'unico',   '2031-05-15', '2031-01-01', '2031-12-31'),
  ( 4, 'K04 otra frecuencia',                    'otra',    '2031-05-15', '2031-01-01', '2031-12-31'),
  ( 5, 'K05 frecuencia sin decir',               null,      '2031-05-15', '2031-01-01', '2031-12-31'),
  ( 6, 'K06 mensual, pago el mes que viene',     'mensual', '2031-06-10', '2031-01-01', '2031-12-31'),
  ( 7, 'K07 mensual, sin próxima fecha',         'mensual', null,         '2031-01-01', '2031-12-31'),
  ( 8, 'K08 mensual, ya aprobada este mes',      'mensual', '2031-05-15', '2031-01-01', '2031-12-31'),
  ( 9, 'K09 mensual, aprobada solo el mes pasado','mensual','2031-05-15', '2031-01-01', '2031-12-31'),
  (10, 'K10 mensual, pendiente de revisión',     'mensual', '2031-05-15', '2031-01-01', '2031-12-31'),
  (11, 'K11 mensual, rechazada',                 'mensual', '2031-05-15', '2031-01-01', '2031-12-31'),
  (12, 'K12 mensual, retirada',                  'mensual', '2031-05-15', '2031-01-01', '2031-12-31'),
  (13, 'K13 mensual, termina antes del pago',    'mensual', '2031-05-15', '2031-01-01', '2031-05-10'),
  (14, 'K14 mensual, empieza el 20',             'mensual', '2031-05-25', '2031-05-20', '2031-12-31'),
  (15, 'K15 mensual, pago el 28',                'mensual', '2031-05-28', '2031-01-01', '2031-12-31'),
  (16, 'K16 mensual, pago hoy',                  'mensual', '2031-05-03', '2031-01-01', '2031-12-31'),
  (17, 'K17 mensual, pago de abril sin constancia','mensual','2031-04-10', '2031-01-01', '2031-12-31'),
  (18, 'K18 mensual, pago el 31',                'mensual', '2031-05-31', '2031-01-01', '2031-12-31'),
  (19, 'K19 mensual, pago el 20',                'mensual', '2031-05-20', '2031-01-01', '2031-12-31');

insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, registrado_por, frecuencia_pago, proxima_fecha_pago)
select ('00000000-0000-0000-0000-000000526b' || lpad(c.n::text, 2, '0'))::uuid,
       ('00000000-0000-0000-0000-000000526e' || lpad(c.n::text, 2, '0'))::uuid,
       90, c.inst, 120, 75, 'trabajador', c.desde, c.hasta,
       '00000000-0000-0000-0000-000000526d01', c.frec, c.prox
  from _caso c;
-- L1: el estudio de Ana, mensual, pago el 15.
insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, registrado_por, frecuencia_pago, proxima_fecha_pago)
values ('00000000-0000-0000-0000-000000526b20', '00000000-0000-0000-0000-000000526d02',
        90, 'L1 el estudio de Ana', 120, 75, 'trabajador', '2031-01-01', '2031-12-31',
        '00000000-0000-0000-0000-000000526d01', 'mensual', '2031-05-15');

-- Las constancias que ya existen, puestas directo (la tabla no tiene otra puerta
-- para fingir revisiones de otro día).
set session_replication_role = replica;
insert into educacion_entregas
  (id, asignacion_id, fecha_pago, tipo, proxima_fecha_pago, estado, origen, enviada_por,
   revisada_at, revisada_por, retirada_at, motivo_categoria, motivo_comentario) values
  ('00000000-0000-0000-0000-000000526c08', '00000000-0000-0000-0000-000000526b08', '2031-05-02', 'cuota_mensual', '2031-06-02',
   'aprobada',   'do', '00000000-0000-0000-0000-000000526d01', now(), '00000000-0000-0000-0000-000000526d01', null, null, null),
  ('00000000-0000-0000-0000-000000526c09', '00000000-0000-0000-0000-000000526b09', '2031-04-20', 'cuota_mensual', '2031-05-20',
   'aprobada',   'do', '00000000-0000-0000-0000-000000526d01', now(), '00000000-0000-0000-0000-000000526d01', null, null, null),
  ('00000000-0000-0000-0000-000000526c10', '00000000-0000-0000-0000-000000526b10', '2031-05-02', 'cuota_mensual', '2031-06-02',
   'pendiente',  'colaboradora', '00000000-0000-0000-0000-000000526e10', null, null, null, null, null),
  ('00000000-0000-0000-0000-000000526c11', '00000000-0000-0000-0000-000000526b11', '2031-05-02', 'cuota_mensual', '2031-06-02',
   'rechazada',  'do', '00000000-0000-0000-0000-000000526d01', now(), '00000000-0000-0000-0000-000000526d01', null, 'ilegible', 'No se lee'),
  ('00000000-0000-0000-0000-000000526c12', '00000000-0000-0000-0000-000000526b12', '2031-05-02', 'cuota_mensual', '2031-06-02',
   'retirada',   'colaboradora', '00000000-0000-0000-0000-000000526e12', null, null, now(), null, null);
set session_replication_role = origin;

-- La foto de lo que se ve, fase por fase. DO lo ve todo.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000526f01', true);
create temp table _r (fase text, inst text, estado text, fecha date, plazo date, dias int, prox date);
create or replace function pg_temp.foto(p_fase text) returns void language sql as $$
  insert into _r
  select p_fase, institucion, estado_constancia, fecha_pago_constancia, plazo, dias_para_plazo, proxima_fecha_pago
    from fn_educacion_situacion();
$$;
select pg_temp.foto('F1');   -- 2031-05-03

-- ── 1 · Lo que cambia: el mensual cuyo pago de este mes todavía no llega ────
select is((select estado from _r where fase = 'F1' and inst like 'K01%'), 'falta_enviar',
  'ABRE · un mensual con el pago el 15 pide la constancia el día 3, sin esperar al 15');
select is((select fecha from _r where fase = 'F1' and inst like 'K01%'), date '2031-05-15',
  'ABRE · la fecha que se pide es la del pago declarado, no una inventada');
select is((select plazo from _r where fase = 'F1' and inst like 'K01%'), date '2031-05-23',
  'PLAZO · sigue siendo el de siempre: cinco días antes del cierre del periodo');
select is((select dias from _r where fase = 'F1' and inst like 'K01%'), 20,
  'PLAZO · y los días que faltan se cuentan contra él');

-- ── 2 · Lo que NO cambia ────────────────────────────────────────────────────
select is((select estado from _r where fase = 'F1' and inst like 'K02%'), 'al_dia',
  'SOLO MENSUAL · el de ciclo sigue con su calendario');
select is((select estado from _r where fase = 'F1' and inst like 'K03%'), 'al_dia',
  'SOLO MENSUAL · el de pago único también');
select is((select estado from _r where fase = 'F1' and inst like 'K04%'), 'al_dia',
  'SOLO MENSUAL · y el de otra frecuencia');
select is((select estado from _r where fase = 'F1' and inst like 'K05%'), 'al_dia',
  'SOLO MENSUAL · y el que nunca dijo su frecuencia (un null no abre nada)');
select is((select estado from _r where fase = 'F1' and inst like 'K06%'), 'al_dia',
  'MES SIGUIENTE · si la institución no cobra este mes, no hay nada que pedir');
select is((select estado from _r where fase = 'F1' and inst like 'K07%'), 'sin_calendario',
  'SIN CALENDARIO · sin próxima fecha no se inventa un pedido');
select is((select estado from _r where fase = 'F1' and inst like 'K08%'), 'al_dia',
  'MES CUBIERTO · con una constancia aprobada este mes no se vuelve a pedir');
select is((select estado from _r where fase = 'F1' and inst like 'K09%'), 'falta_enviar',
  'MES CUBIERTO · la aprobada del mes pasado no cubre este');
select is((select estado from _r where fase = 'F1' and inst like 'K10%'), 'pendiente_revision',
  'PENDIENTE · lo que espera a DO sale como pendiente, no como falta');
select is((select estado from _r where fase = 'F1' and inst like 'K11%'), 'rechazada',
  'RECHAZADA · la rechazada sigue saliendo como rechazada');
select is((select estado from _r where fase = 'F1' and inst like 'K12%'), 'falta_enviar',
  'RETIRADA · una constancia retirada no cubre el mes');
select is((select estado from _r where fase = 'F1' and inst like 'K13%'), 'al_dia',
  'VIGENCIA · un estudio que termina antes de su pago no pide nada');
select is((select estado from _r where fase = 'F1' and inst like 'K14%'), 'al_dia',
  'PROGRAMADO · un estudio que todavía no empieza no pide nada');

-- ── 3 · El pago tardío no se vuelve vencido por adelantar la apertura ───────
select is((select estado from _r where fase = 'F1' and inst like 'K15%'), 'falta_enviar',
  'PAGO TARDÍO · el pago del 28 también abre el día 3');
select is((select plazo from _r where fase = 'F1' and inst like 'K15%'), date '2031-06-23',
  'PAGO TARDÍO · y su plazo es el que ya tenía (el 23 del mes que viene), no el 23 de este');
select is((select plazo from _r where fase = 'F1' and inst like 'K18%'), date '2031-06-23',
  'PAGO TARDÍO · el pago del 31 cae en el periodo siguiente: plazo el 23 de junio');

-- ── 4 · Lo de siempre, igual que antes ──────────────────────────────────────
select is((select estado from _r where fase = 'F1' and inst like 'K16%'), 'falta_enviar',
  'DE SIEMPRE · el pago de hoy se pide hoy, igual que antes');
select is((select estado from _r where fase = 'F1' and inst like 'K17%'), 'vencida',
  'DE SIEMPRE · el pago de abril sin constancia y con el plazo pasado sigue vencido');
select is((select fecha from _r where fase = 'F1' and inst like 'K17%'), date '2031-04-10',
  'DE SIEMPRE · y dice de qué pago es');

-- ── 5 · Avanza el mes: el aviso de la última semana ─────────────────────────
select set_config('test.hoy', '2031-05-17', true);
select pg_temp.foto('F2');
select is((select estado from _r where fase = 'F2' and inst like 'K19%'), 'por_vencer',
  'POR VENCER · el pago por venir también pasa a «por vencer» en la última semana del plazo');
select is((select estado from _r where fase = 'F2' and inst like 'K01%'), 'por_vencer',
  'POR VENCER · y el que ya pasó su fecha, igual que antes');

select set_config('test.hoy', '2031-05-24', true);
select pg_temp.foto('F3');
select is((select estado from _r where fase = 'F3' and inst like 'K01%'), 'vencida',
  'DE SIEMPRE · el 24 el plazo del 23 ya pasó: vencida');
select is((select estado from _r where fase = 'F3' and inst like 'K15%'), 'falta_enviar',
  'PAGO TARDÍO · el pago del 28 NO está vencido el 24: todavía no pagó y su plazo es en junio');
select is((select estado from _r where fase = 'F3' and inst like 'K14%'), 'falta_enviar',
  'EMPEZÓ · el estudio que empezó el 20 ya pide su constancia, con su plazo de junio');
select is((select plazo from _r where fase = 'F3' and inst like 'K14%'), date '2031-06-23',
  'EMPEZÓ · a los cuatro días de empezar no figura vencido');

-- ── 6 · El día 1 ────────────────────────────────────────────────────────────
select set_config('test.hoy', '2031-05-31', true);
select pg_temp.foto('F4');
select is((select estado from _r where fase = 'F4' and inst like 'K06%'), 'al_dia',
  'EL DÍA 1 · el 31 de mayo el pago del 10 de junio todavía no se pide');
select set_config('test.hoy', '2031-06-01', true);
select pg_temp.foto('F5');
select is((select estado from _r where fase = 'F5' and inst like 'K06%'), 'falta_enviar',
  'EL DÍA 1 · el 1.º de junio sí');
select is((select fecha from _r where fase = 'F5' and inst like 'K06%'), date '2031-06-10',
  'EL DÍA 1 · pidiendo el pago del 10 de junio');
select is((select plazo from _r where fase = 'F5' and inst like 'K06%'), date '2031-06-23',
  'EL DÍA 1 · con plazo el 23 de junio');

-- ── 7 · El ciclo entero, con las funciones de verdad ────────────────────────
-- Ana (integrante) ve solo lo suyo; DO envía... no: Ana envía, DO aprueba.
select set_config('test.hoy', '2031-05-20', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000526f02', true);
set local role authenticated;

select is((select count(*)::int from fn_educacion_situacion()), 1,
  'PERMISO · una integrante ve solo su propio estudio');
select is((select estado_constancia from fn_educacion_situacion()), 'por_vencer',
  'CICLO · el 20 de mayo Ana debe la del 15 y le quedan tres días');

reset role;
insert into storage.objects (bucket_id, name, metadata) values
  ('comprobantes',
   'educacion/00000000-0000-0000-0000-000000526d02/entregas/00000000-0000-0000-0000-000000526c20/p1.jpg',
   '{"mimetype":"image/jpeg","size":1000}');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000526f02', true);
set local role authenticated;

select lives_ok($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-000000526c20', '00000000-0000-0000-0000-000000526b20',
    date '2031-05-15', 'cuota_mensual', date '2031-06-15',
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000526d02/entregas/00000000-0000-0000-0000-000000526c20/p1.jpg","nombre":"Constancia.jpg"}]'::jsonb) $$,
  'CICLO · Ana envía la constancia del 15 de mayo y declara su próximo pago el 15 de junio');
select is((select estado_constancia from fn_educacion_situacion()), 'pendiente_revision',
  'CICLO · queda esperando a DO');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000526f01', true);
select lives_ok($$
  select fn_educacion_resolver_entrega('00000000-0000-0000-0000-000000526c20', true, null, null) $$,
  'CICLO · DO la aprueba');
select is((select proxima_fecha_pago from fn_educacion_situacion() where institucion like 'L1%'), date '2031-06-15',
  'CICLO · el calendario avanza al 15 de junio');
select is((select estado_constancia from fn_educacion_situacion() where institucion like 'L1%'), 'al_dia',
  'CICLO · y queda al día');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000526f01', true);
select set_config('test.hoy', '2031-05-31', true);
select is((select estado_constancia from fn_educacion_situacion() where institucion like 'L1%'), 'al_dia',
  'CICLO · el 31 de mayo sigue al día');
select set_config('test.hoy', '2031-06-01', true);
select is((select estado_constancia from fn_educacion_situacion() where institucion like 'L1%'), 'falta_enviar',
  'CICLO · el 1.º de junio se abre la del mes, 14 días antes de que llegue el pago');
select is((select fecha_pago_constancia from fn_educacion_situacion() where institucion like 'L1%'), date '2031-06-15',
  'CICLO · pidiendo el pago del 15 de junio');

-- ── 8 · Solo alerta ─────────────────────────────────────────────────────────
select is((select provolatile::text from pg_proc where proname = 'fn_educacion_situacion'), 's',
  'SOLO ALERTA · la función es de lectura (stable): no puede escribir nada');
select is((select count(*)::int from asignaciones_educacion
            where institucion like 'K%' and comprobante_url is not null), 0,
  'SOLO ALERTA · abrir el mes no enciende el pago de ningún estudio');

select * from finish();
rollback;
