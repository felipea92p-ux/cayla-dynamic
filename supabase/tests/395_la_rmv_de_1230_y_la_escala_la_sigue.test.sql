-- ============================================================================
-- 395_la_rmv_de_1230_y_la_escala_la_sigue.test.sql — migración 0501
-- ============================================================================
-- El 2026-10-01 la RMV pasa de S/ 1,130 a S/ 1,230 (D.S. 015-2026-TR) y CAYLA
-- decidió mover con ella la escala y la asignación familiar. Esta prueba mide lo
-- que esa migración PROMETE, en tres bloques:
--
--   A · LO QUE LA MIGRACIÓN DEJA EN LA BASE (leído de la cadena de migraciones,
--       sin sembrar nada): la RMV y la asignación versionadas por fecha —lo
--       anterior al 1-oct sigue leyendo lo viejo—, la asignación en sus DOS
--       sitios, el DEFAULT de la base legal y lo que publica la Política.
--
--   B · LA PLANILLA LEE ESO BIEN. El 29 y el 30 de septiembre caen dentro del
--       periodo 29-sep → 28-oct y se pagan al sueldo VIEJO: un colibrí con
--       asistencia completa cobra 2/30 × 1,130 + 28/30 × 1,230 = S/ 1,223.33,
--       NO 1,230. Eso puede leerse como «menos que la RMV» y no lo es; esta
--       prueba lo fija para que nadie lo «corrija» sin saber por qué. El
--       septiembre ya pagado no se mueve ni un céntimo.
--
--   C · EL REAJUSTE SOLO SUBE. Se llama a `fn_fijar_base_declarada` como lo hace
--       la migración (colibrí y cayla, con `p_omitir` para quien ya cobra un
--       monto propio por encima): quien estaba más arriba no baja, support no se
--       toca, y repetirlo no abre tramos nuevos.
--
-- NOTA HONESTA SOBRE QUÉ NO PUEDE VER: el bloque que sube los sueldos en la
-- migración es un `do $$` anónimo y esta prueba no puede ejecutarlo (pgTAP no
-- lee archivos del servidor). Lo que sí comprueba es cada pieza sobre la que se
-- apoya —la función, la lectura por tramos, el piso de EsSalud— y el ESTADO
-- FINAL que la migración deja. El ensayo del bloque completo (casos que lo
-- detienen, idempotencia, «nadie baja») se hizo contra la cadena completa en una
-- base desechable y está descrito en docs/estado.md.
--
-- Cuando salga el segundo tramo de la RMV (S/ 1,300, primer semestre de 2027) las
-- aserciones de los bloques A y B se actualizan A PROPÓSITO: este archivo es parte
-- del recordatorio de que colibrí, cayla Y support vuelven a quedar bajo el piso.
-- ============================================================================
begin;
select plan(31);

-- ── El laboratorio ──────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre)
values ('11111111-1111-1111-1111-111111111395', 'Z395', 'Sede de prueba 395')
on conflict do nothing;

-- Sesión de admin: `replica` salta la clave foránea contra auth.users, que acá no existe.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('d0395000-0000-0000-0000-0000000000aa', 'Admin', 'Prueba', '11111111-1111-1111-1111-111111111395',
        'admin', 'x', 'aaaaaaaa-3950-0000-0000-00000000aaaa');
set session_replication_role = origin;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('22222222-3950-0000-0000-000000000001', date '2026-08-29', date '2026-09-28', 'abierto'),
  ('22222222-3950-0000-0000-000000000002', date '2026-09-29', date '2026-10-28', 'abierto');

-- Seis integrantes que cubren cada rama:
--   P1 colibrí con hijos    · asistencia completa en los dos periodos
--   P2 cayla con hijos      · asistencia completa en los dos periodos
--   P3 colibrí con monto propio de 1,500 (por encima: NO baja)
--   P4 support 1,260        · no se toca
--   P5 colibrí que casi no trabaja (para ver el piso de EsSalud)
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, estado, tipo_vinculo,
                      sueldo_fijo, personal_direccion, fecha_ingreso, rol, sueldo_base_legal, con_hijos)
values
 ('d0395000-0000-0000-0000-000000000001','Colibri','Uno',    '11111111-1111-1111-1111-111111111395','x','activo','planilla',false,false,date '2025-01-01','integrante',1130,true),
 ('d0395000-0000-0000-0000-000000000002','Cayla','Dos',      '11111111-1111-1111-1111-111111111395','x','activo','planilla',false,false,date '2025-01-01','integrante',1185,true),
 ('d0395000-0000-0000-0000-000000000003','Colibri','Propio', '11111111-1111-1111-1111-111111111395','x','activo','planilla',false,false,date '2025-01-01','integrante',1500,false),
 ('d0395000-0000-0000-0000-000000000004','Support','Cuatro', '11111111-1111-1111-1111-111111111395','x','activo','planilla',false,false,date '2025-01-01','integrante',1260,false),
 ('d0395000-0000-0000-0000-000000000005','Colibri','Cinco',  '11111111-1111-1111-1111-111111111395','x','activo','planilla',false,false,date '2025-01-01','integrante',1130,false);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
 ('d0395000-0000-0000-0000-000000000001', 'colibri', 1130, date '2025-01-01'),
 ('d0395000-0000-0000-0000-000000000002', 'cayla',   1185, date '2025-01-01'),
 ('d0395000-0000-0000-0000-000000000003', 'colibri', 1500, date '2025-01-01'),
 ('d0395000-0000-0000-0000-000000000004', 'support', 1260, date '2025-01-01'),
 ('d0395000-0000-0000-0000-000000000005', 'colibri', 1130, date '2025-01-01');

-- 6.5 h por día, todos los días de los dos periodos (61 días): con la base del
-- periodo (6.5 h × días) eso es asistencia completa.
insert into jornadas (persona_id, fecha, horas_trabajadas)
select p, d::date, 6.5
  from unnest(array['d0395000-0000-0000-0000-000000000001',
                    'd0395000-0000-0000-0000-000000000002']::uuid[]) p
 cross join generate_series(date '2026-08-29', date '2026-10-28', interval '1 day') d;

-- P5: un solo día por periodo.
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0395000-0000-0000-0000-000000000005', d, 6.5
  from unnest(array[date '2026-09-10', date '2026-10-10']) d;

select set_config('request.jwt.claim.sub', 'aaaaaaaa-3950-0000-0000-00000000aaaa', true);

-- Septiembre tal como está ANTES de tocar ningún sueldo.
create temporary table sep_antes on commit drop as
select f->>'nombre' as quien, (f->>'pago_base')::numeric as pago_base
  from jsonb_array_elements(
         fn_planilla_calcular(date '2026-08-29', date '2026-09-28')->'filas') f;

-- ── A · Lo que la migración deja en la base ─────────────────────────────────
select is(
  (select pl.valor from parametros_laborales pl
    where pl.clave = 'rmv' and pl.sede_codigo is null
      and pl.vigente_desde <= date '2026-10-15'
      and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-15')
    order by pl.vigente_desde desc limit 1),
  1230::numeric(12,5),
  'la RMV vigente el 2026-10-15 es S/ 1,230');

select is(
  (select pl.valor from parametros_laborales pl
    where pl.clave = 'rmv' and pl.sede_codigo is null
      and pl.vigente_desde <= date '2026-09-30'
      and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-30')
    order by pl.vigente_desde desc limit 1),
  1130::numeric(12,5),
  'la RMV vigente el 2026-09-30 sigue siendo S/ 1,130: la nueva no se adelanta ni un día');

select is(
  (select pl.valor from parametros_laborales pl
    where pl.clave = 'rmv' and pl.sede_codigo is null
      and pl.vigente_desde <= date '2026-09-28'
      and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-28')
    order by pl.vigente_desde desc limit 1),
  1130::numeric(12,5),
  'el periodo que cierra el 2026-09-28 lee la RMV vieja: lo ya pagado no se reescribe');

select is(
  (select pl.valor from parametros_laborales pl
    where pl.clave = 'rmv' and pl.sede_codigo is null
      and pl.vigente_desde <= date '2026-10-28'
      and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-28')
    order by pl.vigente_desde desc limit 1),
  1230::numeric(12,5),
  'el periodo que cierra el 2026-10-28 lee la RMV nueva completa (así lo manda el piso de EsSalud)');

select is(
  (select array_agg(pl.valor::text || ':' || pl.vigente_desde::text || ':'
                    || coalesce(pl.vigente_hasta::text, 'abierta') order by pl.vigente_desde)
     from parametros_laborales pl
    where pl.clave = 'rmv' and pl.sede_codigo is null and pl.vigente_desde <= date '2026-12-31'),
  array['1130.00000:2025-01-01:2026-09-30', '1230.00000:2026-10-01:abierta'],
  'la RMV quedó como dos filas seguidas y sin solape: la vieja cerrada el 30-sep, la nueva abierta el 1-oct');

select is(
  (select pl.valor from parametros_laborales pl
    where pl.clave = 'asignacion_familiar' and pl.sede_codigo is null
      and pl.vigente_desde <= date '2026-10-15'
      and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-15')
    order by pl.vigente_desde desc limit 1),
  123::numeric(12,5),
  'la asignación familiar vigente el 2026-10-15 es S/ 123 (10 % de la RMV nueva)');

select is(
  (select pl.valor from parametros_laborales pl
    where pl.clave = 'asignacion_familiar' and pl.sede_codigo is null
      and pl.vigente_desde <= date '2026-09-30'
      and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-30')
    order by pl.vigente_desde desc limit 1),
  113::numeric(12,5),
  'la asignación familiar del 2026-09-30 sigue en S/ 113');

select is(
  (select (valor ->> 'monto')::numeric from configuracion where clave = 'asignacion_familiar'),
  123.00,
  'la SEGUNDA verdad de la asignación (configuracion, la que lee la liquidación) también quedó en S/ 123');

select is(
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'personas' and column_name = 'sueldo_base_legal'),
  '1230.00',
  'quien se cree desde hoy sin fijar su base nace en la RMV nueva y no por debajo de ella');

select is(
  (select array_agg(c.salario_declarado order by c.orden) from categorias_laborales c),
  array[1230, 1245, 1260, 1360, 1440, 1500]::numeric(10,2)[],
  'la Política publica la escala nueva: colibrí 1,230 · cayla 1,245 · support 1,260 (sin cambio) y las tres de arriba iguales');

select is(
  (select nombre from migraciones_aplicadas where numero = 501),
  'la_rmv_sube_a_1230_y_la_escala_la_sigue',
  'la 0501 dejó su fila en el registro con su nombre (no solo con su número)');

-- ── A2 · El techo de movilidad (4 % de la RMV de la fecha de la tarifa) ─────
select lives_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 49.20, 'Z395A', '2026-10-01', 'Laboratorio 395: el 4 % clavado de S/ 1,230')
$$, 'BORDE · S/ 49.20 entra desde el 1-oct: es el 4 % de la RMV nueva');

select throws_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 49.21, 'Z395B', '2026-10-01', 'Laboratorio 395: un céntimo de más')
$$, '23514', null,
  'BORDE · S/ 49.21 se rechaza desde el 1-oct: un céntimo por encima del techo nuevo');

select throws_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 45.21, 'Z395C', '2026-09-30', 'Laboratorio 395: el techo viejo sigue el 30-sep')
$$, '23514', null,
  'el techo viejo sigue rigiendo el 30-sep: S/ 45.21 se rechaza (4 % de 1,130 es 45.20)');

-- ── B · La planilla lee todo eso bien (antes de tocar ningún sueldo) ────────
select is(
  (select fn_planilla_calcular(date '2026-08-29', date '2026-09-28')->>'asignacion_monto')::numeric,
  113.00,
  'el periodo que cierra el 28-sep paga la asignación de S/ 113');

select is(
  (select fn_planilla_calcular(date '2026-09-29', date '2026-10-28')->>'asignacion_monto')::numeric,
  123.00,
  'el periodo que cierra el 28-oct paga la asignación de S/ 123');

select is(
  (select (f->>'aporte_essalud')::numeric
     from jsonb_array_elements(
            fn_planilla_calcular(date '2026-08-29', date '2026-09-28')->'filas') f
    where f->>'nombre' = 'Colibri Cinco'),
  101.70,
  'septiembre: quien devenga menos que la RMV aporta el piso viejo, 9 % de S/ 1,130');

select is(
  (select (f->>'aporte_essalud')::numeric
     from jsonb_array_elements(
            fn_planilla_calcular(date '2026-09-29', date '2026-10-28')->'filas') f
    where f->>'nombre' = 'Colibri Cinco'),
  110.70,
  'el periodo que cierra el 28-oct aporta el piso nuevo, 9 % de S/ 1,230');

-- ── C · El reajuste, como lo hace la migración: solo sube ───────────────────
select lives_ok(
  $$select * from fn_fijar_base_declarada('colibri', 1230.00, date '2026-10-01',
        array['d0395000-0000-0000-0000-000000000003']::uuid[])$$,
  'subir colibrí a 1,230 desde el 1-oct pasa el candado de periodo pagado');

select lives_ok(
  $$select * from fn_fijar_base_declarada('cayla', 1245.00, date '2026-10-01', '{}')$$,
  'subir cayla a 1,245 desde el 1-oct también');

select is(
  (select array_agg(salario_mensual_soles::text || ':' || vigente_desde::text
                    || ':' || coalesce(vigente_hasta::text, 'abierto') order by vigente_desde)
     from asignaciones_salario
    where persona_id = 'd0395000-0000-0000-0000-000000000001'),
  array['1130.00:2025-01-01:2026-09-30', '1230.00:2026-10-01:abierto'],
  'el tramo viejo de colibrí se cierra el 30-sep y el nuevo abre el 1-oct: el sueldo de septiembre se conserva');

select is(
  (select sueldo_base_legal from personas where id = 'd0395000-0000-0000-0000-000000000001'),
  1230.00,
  'colibrí sube también el segundo campo, la base declarada: el pago y la declaración no se separan');

select is(
  (select array_agg(salario_mensual_soles::text order by vigente_desde)
     from asignaciones_salario
    where persona_id = 'd0395000-0000-0000-0000-000000000002')
  || (select array[sueldo_base_legal::text] from personas
       where id = 'd0395000-0000-0000-0000-000000000002'),
  array['1185.00', '1245.00', '1245.00'],
  'cayla pasa de 1,185 a 1,245 en el sueldo y en la base declarada, a la vez');

-- 2 días × 6.5 h a 1,130 + 28 días × 6.5 h a 1,230, sobre 195 h de base = 1,223.33
select is(
  (select (f->>'pago_base')::numeric
     from jsonb_array_elements(
            fn_planilla_calcular(date '2026-09-29', date '2026-10-28')->'filas') f
    where f->>'nombre' = 'Colibri Uno'),
  1223.33,
  'colibrí con asistencia completa cobra 2/30 × 1,130 + 28/30 × 1,230 = 1,223.33: el 29 y 30 de septiembre se pagan al sueldo de septiembre');

-- 2 días a 1,185 + 28 días a 1,245 = 79.00 + 1,162.00
select is(
  (select (f->>'pago_base')::numeric
     from jsonb_array_elements(
            fn_planilla_calcular(date '2026-09-29', date '2026-10-28')->'filas') f
    where f->>'nombre' = 'Cayla Dos'),
  1241.00,
  'cayla con asistencia completa cobra 2/30 × 1,185 + 28/30 × 1,245 = 1,241.00');

select is(
  (select (f->>'pago_base')::numeric
     from jsonb_array_elements(
            fn_planilla_calcular(date '2026-08-29', date '2026-09-28')->'filas') f
    where f->>'nombre' = 'Colibri Uno'),
  (select pago_base from sep_antes where quien = 'Colibri Uno'),
  'septiembre da exactamente lo mismo antes y después del reajuste: no se reescribe lo pagado');

-- Los que NO deben moverse ---------------------------------------------------
select is(
  (select array_agg(salario_mensual_soles::text order by vigente_desde)
     from asignaciones_salario
    where persona_id = 'd0395000-0000-0000-0000-000000000003'),
  array['1500.00'],
  'quien ya cobraba un monto propio por encima (1,500) NO baja y no gana un tramo nuevo');

select is(
  (select array_agg(salario_mensual_soles::text order by vigente_desde)
     from asignaciones_salario
    where persona_id = 'd0395000-0000-0000-0000-000000000004'),
  array['1260.00'],
  'support (1,260) ya cumplía la RMV: no se toca ni se le abre un tramo');

-- Idempotencia --------------------------------------------------------------
create temporary table tramos_antes on commit drop as
select count(*)::int as n from asignaciones_salario;

select lives_ok(
  $$select * from fn_fijar_base_declarada('colibri', 1230.00, date '2026-10-01',
        array['d0395000-0000-0000-0000-000000000003']::uuid[]);
    select * from fn_fijar_base_declarada('cayla', 1245.00, date '2026-10-01', '{}')$$,
  'repetir el reajuste no falla');

select is(
  (select count(*)::int from asignaciones_salario),
  (select n from tramos_antes),
  'y no abre ningún tramo nuevo: pegar dos veces la migración no ensucia el historial');

-- ── Las dos verdades de la asignación coinciden ─────────────────────────────
select is(
  (select fn_remuneracion_computable('d0395000-0000-0000-0000-000000000001', date '2026-10-15', 'grati')
            ->> 'asignacion_familiar')::numeric,
  (select fn_planilla_calcular(date '2026-09-29', date '2026-10-28')->>'asignacion_monto')::numeric,
  'la liquidación (fn_remuneracion_computable) y la boleta del mes dicen la MISMA asignación para quien tiene hijos');

select * from finish();
rollback;
