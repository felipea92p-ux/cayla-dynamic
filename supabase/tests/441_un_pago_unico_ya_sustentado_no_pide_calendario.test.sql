-- ============================================================================
-- 441_un_pago_unico_ya_sustentado_no_pide_calendario.test.sql
-- ============================================================================
-- Lo que promete la 0549: un estudio de frecuencia 'unico' con una constancia
-- APROBADA figura 'al_dia' (sin fecha ni plazo de constancia, sin «pago
-- próximo», fuera del número rojo), en vez de pedir otra vez un calendario.
-- Contado desde cinco lados:
--   · lo que cambia: pago único aprobado con la próxima fecha vacía (U1), el caso
--     de la captura —próxima fecha = hoy, constancia entrada como comprobante
--     inicial— (U2), y que el número rojo del menú baje en uno (U1);
--   · lo que NO cambia: pago único SIN constancia aprobada sigue la escalera de
--     siempre (U3 sin fecha, U4 con fecha futura, U5 con el plazo vencido);
--   · que se deriva en vivo: revertida la aprobación (0525), deja de estar al
--     día (U6);
--   · lo que NO se arregla, fijado a propósito: mensual, por ciclo, otra y
--     frecuencia sin decir, con una aprobada y la próxima fecha vacía, siguen
--     'sin_calendario' (M7–M10);
--   · la vigencia: una RENOVACIÓN (familia nueva) no queda callada por la
--     constancia de la anterior (U8), y una CORRECCIÓN (misma familia, vigencia
--     nueva) comparte las constancias, como promete la 0450 (U9);
--   · el orden de la escalera: rechazada y pendiente de revisión mandan sobre la
--     rama nueva (U10, U11), y también sobre el aviso «pago en camino» a DO: un
--     pago único con una constancia por revisar o rechazada, y su fecha dentro de
--     la ventana de aviso, CONSERVA pago_proximo (U12, U13).
--
-- El reloj se fija en 2031-10-25 (una fecha real caduca el día que la pasa).
-- `fn_hoy_lima()` se redefine DENTRO de esta transacción, que termina en
-- rollback: nadie más la ve. Los periodos de planilla también son de 2031.
-- ============================================================================
begin;
select plan(29);

-- ── El reloj ────────────────────────────────────────────────────────────────
create or replace function fn_hoy_lima()
returns date language sql stable set search_path = public as $fn$
  select coalesce(nullif(current_setting('test.hoy', true), '')::date,
                  (now() at time zone 'America/Lima')::date);
$fn$;
select set_config('test.hoy', '2031-10-25', true);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000441a00', 'ZZ441', 'Sede de laboratorio 441', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000441d01', 'PuDO', 'Laboratorio',
   '00000000-0000-0000-0000-000000441a00', 'lider_do', 'test-hash',
   '00000000-0000-0000-0000-000000441f01', '2020-01-01');
-- Una persona por estudio: así ningún caso comparte techo ni vigencia con otro.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso)
select ('00000000-0000-0000-0000-000000441e' || lpad(n::text, 2, '0'))::uuid,
       'PuK' || lpad(n::text, 2, '0'), 'Laboratorio',
       '00000000-0000-0000-0000-000000441a00', 'integrante', 'test-hash', '2025-01-02'
  from generate_series(1, 18) n;
set session_replication_role = origin;

-- Periodos 29→28 de 2031. El de octubre va del 29/09 al 28/10 (plazo el 23/10);
-- el de noviembre, del 29/10 al 28/11 (plazo el 23/11).
insert into periodos_planilla (fecha_ini, fecha_fin, estado, pagado_at) values
  ('2031-02-28', '2031-03-28', 'pagado', now()),
  ('2031-09-29', '2031-10-28', 'pagado', now()),
  ('2031-10-29', '2031-11-28', 'pagado', now()),
  ('2031-11-29', '2031-12-28', 'pagado', now());

-- Los estudios. n = número del caso; p = la persona; fam = la familia (el número
-- de la asignación que la abrió).
create temp table _a (n int, p int, fam int, inst text, desde date, hasta date, frec text, prox date);
insert into _a values
  ( 1,  1,  1, 'U01 pago único aprobado, sin próxima fecha',   '2031-10-10', '2031-10-31', 'unico',   null),
  ( 2,  2,  2, 'U02 el caso de la captura: próxima = hoy',     '2031-10-10', '2031-10-31', 'unico',   '2031-10-25'),
  ( 3,  3,  3, 'U03 pago único sin constancia ni fecha',       '2031-10-10', '2031-10-31', 'unico',   null),
  ( 4,  4,  4, 'U04 pago único sin constancia, fecha futura',  '2031-10-10', '2031-12-31', 'unico',   '2031-11-14'),
  ( 5,  5,  5, 'U05 pago único sin constancia, plazo vencido', '2031-10-01', '2031-12-31', 'unico',   '2031-10-05'),
  ( 6,  6,  6, 'U06 pago único aprobado y luego revertido',    '2031-10-10', '2031-10-31', 'unico',   null),
  ( 7,  7,  7, 'M07 mensual con una aprobada',                 '2031-10-10', '2031-10-31', 'mensual', null),
  ( 8,  8,  8, 'M08 por ciclo con una aprobada',               '2031-10-10', '2031-10-31', 'ciclo',   null),
  ( 9,  9,  9, 'M09 otra con una aprobada',                    '2031-10-10', '2031-10-31', 'otra',    null),
  (10, 10, 10, 'M10 frecuencia sin decir con una aprobada',    '2031-10-10', '2031-10-31', null,      null),
  (11, 11, 11, 'U08 renovación: el ciclo I, ya sustentado',    '2031-03-01', '2031-07-31', 'unico',   null),
  (12, 11, 12, 'U08 renovación: el ciclo II, sin constancia',  '2031-10-10', '2031-12-31', 'unico',   null),
  (13, 13, 13, 'U09 corrección: vigencia anterior, sustentada','2031-03-01', '2031-10-28', 'unico',   null),
  (14, 13, 13, 'U09 corrección: vigencia nueva, misma familia','2031-10-29', '2031-12-31', 'unico',   null),
  (15, 15, 15, 'U10 aprobada y una rechazada más reciente',    '2031-10-10', '2031-10-31', 'unico',   null),
  (16, 16, 16, 'U11 aprobada y una pendiente de revisión',     '2031-10-10', '2031-10-31', 'unico',   null),
  (17, 17, 17, 'U12 aprobada, pendiente y pago en 3 días',     '2031-10-10', '2031-12-31', 'unico',   '2031-10-28'),
  (18, 18, 18, 'U13 aprobada, rechazada y pago en 3 días',     '2031-10-10', '2031-12-31', 'unico',   '2031-10-28');

-- familia_id explícito: con session_replication_role = replica el trigger que lo
-- completa no corre.
set session_replication_role = replica;
insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, registrado_por, frecuencia_pago, proxima_fecha_pago, familia_id)
select ('00000000-0000-0000-0000-000000441b' || lpad(a.n::text, 2, '0'))::uuid,
       ('00000000-0000-0000-0000-000000441e' || lpad(a.p::text, 2, '0'))::uuid,
       90, a.inst, 120, 75, 'trabajador', a.desde, a.hasta,
       '00000000-0000-0000-0000-000000441d01', a.frec, a.prox,
       ('00000000-0000-0000-0000-000000441b' || lpad(a.fam::text, 2, '0'))::uuid
  from _a a;

-- Las constancias, puestas directo (la tabla no tiene otra puerta para fingir
-- revisiones de otro día). k = número de la constancia.
create temp table _e (k int, n int, fecha date, estado text);
insert into _e values
  ( 6,  6, '2031-10-01', 'aprobada'),
  ( 7,  7, '2031-10-01', 'aprobada'),
  ( 8,  8, '2031-10-01', 'aprobada'),
  ( 9,  9, '2031-10-01', 'aprobada'),
  (10, 10, '2031-10-01', 'aprobada'),
  (11, 11, '2031-03-05', 'aprobada'),
  (13, 13, '2031-03-05', 'aprobada'),
  (15, 15, '2031-10-01', 'aprobada'),
  (25, 15, '2031-10-20', 'rechazada'),
  (16, 16, '2031-10-01', 'aprobada'),
  (26, 16, '2031-10-22', 'pendiente'),
  (17, 17, '2031-10-01', 'aprobada'),
  (27, 17, '2031-10-22', 'pendiente'),
  (18, 18, '2031-10-01', 'aprobada'),
  (28, 18, '2031-10-20', 'rechazada');

insert into educacion_entregas
  (id, asignacion_id, fecha_pago, tipo, proxima_fecha_pago, estado, origen, enviada_por,
   revisada_at, revisada_por, motivo_categoria, motivo_comentario)
select ('00000000-0000-0000-0000-000000441c' || lpad(e.k::text, 2, '0'))::uuid,
       ('00000000-0000-0000-0000-000000441b' || lpad(e.n::text, 2, '0'))::uuid,
       e.fecha, 'otro', null, e.estado,
       case when e.estado = 'aprobada' then 'do' else 'colaboradora' end,
       case when e.estado = 'aprobada' then '00000000-0000-0000-0000-000000441d01'::uuid
            else ('00000000-0000-0000-0000-000000441e' || lpad(e.n::text, 2, '0'))::uuid end,
       case when e.estado in ('aprobada', 'rechazada') then now() end,
       case when e.estado in ('aprobada', 'rechazada') then '00000000-0000-0000-0000-000000441d01'::uuid end,
       case when e.estado = 'rechazada' then 'ilegible' end,
       case when e.estado = 'rechazada' then 'La foto salió borrosa' end
  from _e e;
set session_replication_role = origin;

-- Cómo se ve cada estudio. El estudio de la familia n se busca por su familia.
create function pg_temp.sit(p_n int) returns jsonb language sql as $$
  select to_jsonb(s) from fn_educacion_situacion() s
   where s.familia_id = ('00000000-0000-0000-0000-000000441b' || lpad(p_n::text, 2, '0'))::uuid;
$$;

-- Quien mira es DO.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000441f01', true);

-- El número rojo, ANTES de que U1 y la captura tengan su constancia.
select set_config('prueba.base', fn_educacion_por_atender()::text, true);


-- ── 1 · U1 · pago único, aprobado, sin próxima fecha ────────────────────────
-- La constancia entra por donde entra el comprobante inicial de un alta: la
-- puerta de la 0290, que el trigger de la 0450 refleja como entrega aprobada.
-- Su fecha de pago es el primer día del mes de la vigencia, no la del voucher.
insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
values ('00000000-0000-0000-0000-000000441b01',
        'educacion/00000000-0000-0000-0000-000000441e01/comprobantes/u1.pdf', '2031-10-01',
        '00000000-0000-0000-0000-000000441d01');

select is(pg_temp.sit(1)->>'estado_constancia', 'al_dia',
  'U1 · pago único con su constancia aprobada y la próxima fecha vacía: al día (antes: sin calendario)');

select is(
  coalesce(pg_temp.sit(1)->>'fecha_pago_constancia', 'vacío') || '|' || coalesce(pg_temp.sit(1)->>'plazo', 'vacío'),
  'vacío|vacío',
  'U1 · al día sin fecha ni plazo de constancia (nada que entregar)');

select is(fn_educacion_por_atender(), current_setting('prueba.base')::int - 1,
  'U1 · EL CONTADOR · el estudio sale del número rojo del menú (baja en uno)');

select is(
  (select count(*)::int from fn_educacion_situacion() s
    where s.familia_id = '00000000-0000-0000-0000-000000441b01'
      and (s.estado_constancia = 'vencida'
           or (s.estado_constancia = 'sin_calendario' and s.vigencia in ('vigente', 'por_terminar')))),
  0, 'U1 · ya no cumple la condición con la que el contador y la Bandeja lo cuentan');


-- ── 2 · U2 · el caso de la captura ──────────────────────────────────────────
-- Pago único con la próxima fecha en HOY (el formulario mostraba «Pago único» +
-- 25/10 sin guardar) y su constancia del 01/10 ya aprobada. Guardar esa fecha
-- tal cual lo hacía pasar a «falta enviar» y pedir una constancia de un pago ya
-- sustentado.
insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
values ('00000000-0000-0000-0000-000000441b02',
        'educacion/00000000-0000-0000-0000-000000441e02/comprobantes/u2.pdf', '2031-10-01',
        '00000000-0000-0000-0000-000000441d01');

select is(pg_temp.sit(2)->>'estado_constancia', 'al_dia',
  'U2 · LA CAPTURA · pago único aprobado con la próxima fecha en hoy: al día, no «falta enviar»');

select is(pg_temp.sit(2)->>'pago_proximo', 'false',
  'U2 · sin aviso de «pago próximo» a DO por un pago ya sustentado');

select is(pg_temp.sit(2)->>'proxima_fecha_pago', '2031-10-25',
  'U2 · la fecha guardada se devuelve tal cual: la función es de lectura y no reescribe nada');


-- ── 3 · Pago único SIN constancia aprobada: la escalera de siempre ──────────
select is(pg_temp.sit(3)->>'estado_constancia', 'sin_calendario',
  'U3 · pago único sin constancia y sin fecha: sigue pidiendo (sin calendario)');

select is(
  (pg_temp.sit(4)->>'estado_constancia') || '|' || (pg_temp.sit(4)->>'fecha_pago_constancia'),
  'al_dia|2031-11-14',
  'U4 · pago único sin constancia con fecha futura: al día, con su fecha');

select is(
  (pg_temp.sit(5)->>'estado_constancia') || '|' || (pg_temp.sit(5)->>'plazo'),
  'vencida|2031-10-23',
  'U5 · pago único sin constancia, fecha pasada y plazo vencido: vencida');


-- ── 4 · Se deriva en vivo: revertida la aprobación, deja de estar al día ────
select is(pg_temp.sit(6)->>'estado_constancia', 'al_dia',
  'U6 · antes de revertir: pago único con su constancia aprobada, al día');

select lives_ok($$
  select fn_educacion_revertir_aprobacion(
    '00000000-0000-0000-0000-000000441c06', 'ilegible', 'La foto no se lee') $$,
  'U6 · DO revierte la aprobación (0525)');

select is(pg_temp.sit(6)->>'estado_constancia', 'rechazada',
  'U6 · revertida la aprobación deja de estar al día: figura rechazada, sin que nadie guarde una marca');


-- ── 5 · Lo que NO se arregla: el NULL de las otras frecuencias sigue ambiguo ─
select is(pg_temp.sit(7)->>'estado_constancia', 'sin_calendario',
  'M7 · MENSUAL con una aprobada y la próxima vacía: sigue sin calendario (decisión abierta)');
select is(pg_temp.sit(8)->>'estado_constancia', 'sin_calendario',
  'M8 · por CICLO con una aprobada y la próxima vacía: sigue sin calendario');
select is(pg_temp.sit(9)->>'estado_constancia', 'sin_calendario',
  'M9 · OTRA con una aprobada y la próxima vacía: sigue sin calendario');
select is(pg_temp.sit(10)->>'estado_constancia', 'sin_calendario',
  'M10 · frecuencia sin decir con una aprobada y la próxima vacía: sigue sin calendario');


-- ── 6 · La vigencia ─────────────────────────────────────────────────────────
-- U8 · una RENOVACIÓN es una familia nueva: la constancia del ciclo anterior no
-- la calla.
select is(pg_temp.sit(12)->>'estado_constancia', 'sin_calendario',
  'U8 · RENOVACIÓN · el pago único de la vigencia nueva (familia nueva) sin constancia sigue pidiendo');
select is(pg_temp.sit(11)->>'estado_constancia', 'al_dia',
  'U8 · y el ciclo anterior, que sí tiene su constancia, está al día');
select is(
  (select count(*)::int from fn_educacion_situacion() s
    where s.persona_id = '00000000-0000-0000-0000-000000441e11'),
  2, 'U8 · la misma persona figura con dos estudios, uno por familia');

-- U9 · una CORRECCIÓN abre vigencia nueva con la MISMA familia: las constancias
-- se comparten (0450), así que no nace sin sustento.
select is(
  (pg_temp.sit(13)->>'estado_constancia') || '|' ||
  (pg_temp.sit(13)->>'asignacion_id' = '00000000-0000-0000-0000-000000441b14')::text,
  'al_dia|true',
  'U9 · CORRECCIÓN · la vigencia nueva de la misma familia hereda la constancia aprobada (el estudio es el mismo)');


-- ── 7 · El orden de la escalera ─────────────────────────────────────────────
select is(pg_temp.sit(15)->>'estado_constancia', 'rechazada',
  'U10 · una constancia rechazada más reciente manda sobre la rama nueva');
select is(pg_temp.sit(16)->>'estado_constancia', 'pendiente_revision',
  'U11 · una constancia pendiente de revisión manda sobre la rama nueva');

-- U12 y U13 · el aviso «Pago de estudios en camino» a DO. La rama nueva apaga
-- pago_proximo SOLO cuando el estado queda en al_dia por ella; con una constancia
-- pendiente o rechazada el pago sigue en camino y DO lo sigue viendo, como hoy.
-- Fecha de pago: 2031-10-28 = hoy + 3, dentro de la ventana de 7 días de DO.
select is(
  (pg_temp.sit(17)->>'estado_constancia') || '|' || (pg_temp.sit(17)->>'pago_proximo'),
  'pendiente_revision|true',
  'U12 · pago único con una constancia pendiente y el pago en 3 días: conserva «pago en camino»');
select is(
  (pg_temp.sit(18)->>'estado_constancia') || '|' || (pg_temp.sit(18)->>'pago_proximo'),
  'rechazada|true',
  'U13 · pago único con una constancia rechazada y el pago en 3 días: conserva «pago en camino»');


-- ── 8 · Lo que no cambia de forma ───────────────────────────────────────────
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_educacion_situacion'),
  1, 'FIRMA · una sola fn_educacion_situacion (create or replace, sin sobrecarga)');

select ok(has_function_privilege('authenticated', 'fn_educacion_situacion()', 'execute'),
  'PERMISO · sigue ejecutable por authenticated');

select is(
  (select count(*)::int from jsonb_object_keys(pg_temp.sit(1))),
  31, 'COLUMNAS · devuelve las mismas 31 columnas que la 0450');

select is((select nombre from migraciones_aplicadas where numero = 549),
  'un_pago_unico_ya_sustentado_no_pide_calendario',
  'REGISTRO · la 0549 quedó anotada con su nombre');

select * from finish();
rollback;
