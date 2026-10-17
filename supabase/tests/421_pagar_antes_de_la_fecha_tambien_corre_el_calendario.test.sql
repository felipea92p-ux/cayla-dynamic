-- ============================================================================
-- 421_pagar_antes_de_la_fecha_tambien_corre_el_calendario.test.sql
-- ============================================================================
-- Lo que promete la 0527: cuando una constancia aprobada es de un pago hecho
-- ANTES del día declarado pero dentro del mes de esa fecha, el calendario de la
-- familia avanza a la próxima fecha que ella declaró, en vez de quedarse pidiendo
-- un pago que ya sustentó. Contado desde cuatro lados:
--   · lo que cambia: pagar antes dentro del mes de la fecha vigente (K03–K07,
--     K14, K16, K17), con cualquier frecuencia, y el «último pago» que pone null;
--   · lo que NO cambia: pagar a tiempo o tarde, la constancia vieja aprobada
--     tarde (con el calendario ya adelantado o fijado por DO), pagar un mes
--     ANTERIOR al de la fecha vigente (el residuo del criterio A, fijado a
--     propósito), una próxima que no es posterior, lo que no está aprobado;
--   · que repetir la aprobación no corra el calendario dos veces;
--   · el caso de la vida real, con las funciones de verdad: la integrante envía,
--     DO aprueba, y el 24 de mayo ya no figura «vencida» por un mes pagado. Y que
--     DO sigue mandando: fija una fecha anterior y se queda.
--
-- Esta prueba NO fija el comportamiento de la 0526 (pedir la constancia desde el
-- día 1): el caso de la vida real mira hasta el 31 de mayo y el 4 de junio, donde
-- la 0450 y la 0526 dicen lo mismo.
--
-- El reloj se fija en 2031 (una fecha real caduca el día que la pasa).
-- `fn_hoy_lima()` se redefine DENTRO de esta transacción, que termina en
-- rollback: nadie más la ve. Los periodos de planilla también son de 2031.
-- ============================================================================
begin;
select plan(34);

-- ── El reloj ────────────────────────────────────────────────────────────────
create or replace function fn_hoy_lima()
returns date language sql stable set search_path = public as $fn$
  select coalesce(nullif(current_setting('test.hoy', true), '')::date,
                  (now() at time zone 'America/Lima')::date);
$fn$;
select set_config('test.hoy', '2031-05-03', true);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000527a00', 'ZZ527', 'Sede de laboratorio 527', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000527d01', 'AntDO', 'Laboratorio',
   '00000000-0000-0000-0000-000000527a00', 'lider_do', 'test-hash',
   '00000000-0000-0000-0000-000000527f01', '2020-01-01'),
  ('00000000-0000-0000-0000-000000527d02', 'AntAna', 'Laboratorio',
   '00000000-0000-0000-0000-000000527a00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000527f02', '2025-01-02');
-- Una persona por estudio: así ningún caso comparte techo ni vigencia con otro.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso)
select ('00000000-0000-0000-0000-000000527e' || lpad(n::text, 2, '0'))::uuid,
       'AntK' || lpad(n::text, 2, '0'), 'Laboratorio',
       '00000000-0000-0000-0000-000000527a00', 'integrante', 'test-hash', '2025-01-02'
  from generate_series(1, 17) n;
set session_replication_role = origin;

-- Periodos 29→28 de 2031. Mayo va del 29/04 al 28/05 (plazo el 23); junio, del
-- 29/05 al 28/06 (plazo el 23/06).
insert into periodos_planilla (fecha_ini, fecha_fin, estado, pagado_at) values
  ('2031-03-29', '2031-04-28', 'pagado', now()),
  ('2031-04-29', '2031-05-28', 'pagado', now()),
  ('2031-05-29', '2031-06-28', 'pagado', now()),
  ('2031-06-29', '2031-07-28', 'pagado', now());

-- Los casos. p = la próxima fecha vigente de la familia ANTES de aprobar,
-- f = la fecha de pago de la constancia, nx = la próxima que ella declaró.
create temp table _caso (n int, inst text, frec text, p date, f date, nx date, estado text);
insert into _caso values
  ( 1, 'K01 paga el día que vence',                    'mensual', '2031-10-15', '2031-10-15', '2031-11-15', 'aprobada'),
  ( 2, 'K02 paga tarde (vencía el 15)',                'mensual', '2031-10-15', '2031-10-20', '2031-11-20', 'aprobada'),
  ( 3, 'K03 paga antes, mismo mes, declara el 3',      'mensual', '2031-10-15', '2031-10-03', '2031-11-03', 'aprobada'),
  ( 4, 'K04 paga antes, mismo mes, declara el 15',     'mensual', '2031-10-15', '2031-10-03', '2031-11-15', 'aprobada'),
  ( 5, 'K05 paga antes, mismo mes, último pago',       'mensual', '2031-10-15', '2031-10-03', null,         'aprobada'),
  ( 6, 'K06 paga antes, por ciclo',                    'ciclo',   '2031-10-15', '2031-10-03', '2032-02-03', 'aprobada'),
  ( 7, 'K07 paga antes, el día 1 del mes',             'mensual', '2031-10-15', '2031-10-01', '2031-11-01', 'aprobada'),
  ( 8, 'K08 paga en un mes ANTERIOR al de la fecha',   'mensual', '2031-11-03', '2031-10-28', '2031-11-28', 'aprobada'),
  ( 9, 'K09 vieja aprobada tarde, calendario adelante','mensual', '2031-11-15', '2031-10-15', '2031-11-15', 'aprobada'),
  (10, 'K10 vieja aprobada tarde, calendario de DO',   'mensual', '2031-10-15', '2031-09-20', '2031-10-20', 'aprobada'),
  (11, 'K11 paga antes pero declara una próxima antes','mensual', '2031-10-15', '2031-10-03', '2031-10-10', 'aprobada'),
  (12, 'K12 sin calendario todavía',                   'mensual', null,         '2031-10-03', '2031-11-03', 'aprobada'),
  (13, 'K13 último pago, a tiempo',                    'mensual', '2031-10-15', '2031-10-15', null,         'aprobada'),
  (14, 'K14 paga antes, la fecha vigente es el 31',    'mensual', '2031-10-31', '2031-10-05', '2031-11-05', 'aprobada'),
  (15, 'K15 paga antes, pero está pendiente',          'mensual', '2031-10-15', '2031-10-03', '2031-11-03', 'pendiente'),
  (16, 'K16 paga antes, pago único',                   'unico',   '2031-10-15', '2031-10-03', null,         'aprobada'),
  (17, 'K17 paga antes, frecuencia sin decir',         null,      '2031-10-15', '2031-10-03', '2031-11-03', 'aprobada');

insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, registrado_por, frecuencia_pago, proxima_fecha_pago)
select ('00000000-0000-0000-0000-000000527b' || lpad(c.n::text, 2, '0'))::uuid,
       ('00000000-0000-0000-0000-000000527e' || lpad(c.n::text, 2, '0'))::uuid,
       90, c.inst, 120, 75, 'trabajador', date '2031-01-01', date '2031-12-31',
       '00000000-0000-0000-0000-000000527d01', c.frec, c.p
  from _caso c;
-- L1: el estudio de Ana, mensual, vence el 15 de mayo.
insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, registrado_por, frecuencia_pago, proxima_fecha_pago)
values ('00000000-0000-0000-0000-000000527b20', '00000000-0000-0000-0000-000000527d02',
        90, 'L1 el estudio de Ana', 120, 75, 'trabajador', '2031-01-01', '2031-12-31',
        '00000000-0000-0000-0000-000000527d01', 'mensual', '2031-05-15');

-- Las constancias de cada caso, puestas directo (la tabla no tiene otra puerta
-- para fingir revisiones de otro día).
set session_replication_role = replica;
insert into educacion_entregas
  (id, asignacion_id, fecha_pago, tipo, proxima_fecha_pago, estado, origen, enviada_por,
   revisada_at, revisada_por)
select ('00000000-0000-0000-0000-000000527c' || lpad(c.n::text, 2, '0'))::uuid,
       ('00000000-0000-0000-0000-000000527b' || lpad(c.n::text, 2, '0'))::uuid,
       c.f, 'cuota_mensual', c.nx, c.estado,
       case when c.estado = 'aprobada' then 'do' else 'colaboradora' end,
       case when c.estado = 'aprobada' then '00000000-0000-0000-0000-000000527d01'::uuid
            else ('00000000-0000-0000-0000-000000527e' || lpad(c.n::text, 2, '0'))::uuid end,
       case when c.estado = 'aprobada' then now() end,
       case when c.estado = 'aprobada' then '00000000-0000-0000-0000-000000527d01'::uuid end
  from _caso c;
set session_replication_role = origin;

create function pg_temp.cal(p_n int) returns date language sql as $$
  select proxima_fecha_pago from asignaciones_educacion
   where id = ('00000000-0000-0000-0000-000000527b' || lpad(p_n::text, 2, '0'))::uuid;
$$;

-- ── Se aprueba cada una, como lo hace el sistema ────────────────────────────
select fn_educacion_avanzar_calendario(id)
  from educacion_entregas
 where id::text like '00000000-0000-0000-0000-000000527c%';

-- ── 1 · Lo que cambia: pagar antes, dentro del mes de la fecha vigente ──────
select is(pg_temp.cal(3), date '2031-11-03',
  'ANTES · pagó el 3 de octubre lo que vencía el 15 y declaró el 3 de noviembre: el calendario pasa al 3 de noviembre');
select is(pg_temp.cal(4), date '2031-11-15',
  'ANTES · pagó el 3 y declaró el 15 siguiente: el calendario pasa al 15 de noviembre');
select is(pg_temp.cal(5), null::date,
  'ANTES · pagó el 3 y dijo que es su último pago: el calendario queda en null, como ya pasaba al pagar a tiempo');
select is(pg_temp.cal(6), date '2032-02-03',
  'ANTES · un estudio por ciclo que paga antes dentro del mes también avanza');
select is(pg_temp.cal(7), date '2031-11-01',
  'ANTES · pagar el día 1 del mes de la fecha vigente cuenta (el borde del mes entra)');
select is(pg_temp.cal(14), date '2031-11-05',
  'ANTES · con la fecha vigente el día 31, pagar el 5 del mismo mes avanza');
select is(pg_temp.cal(16), null::date,
  'ANTES · un pago único hecho antes y sin próxima fecha deja el calendario en null');
select is(pg_temp.cal(17), date '2031-11-03',
  'ANTES · una frecuencia sin decir no cambia la regla: el pago de este mes avanza');

-- ── 2 · Lo que NO cambia ────────────────────────────────────────────────────
select is(pg_temp.cal(1), date '2031-11-15',
  'IGUAL · pagar el día que vence avanza al 15 de noviembre, como siempre');
select is(pg_temp.cal(2), date '2031-11-20',
  'IGUAL · pagar tarde avanza a lo que declaró, como siempre');
select is(pg_temp.cal(13), null::date,
  'IGUAL · un último pago a tiempo sigue poniendo null');
select is(pg_temp.cal(12), date '2031-11-03',
  'IGUAL · una familia sin calendario toma el de su primera constancia aprobada');
select is(pg_temp.cal(8), date '2031-11-03',
  'RESIDUO · pagar en un mes ANTERIOR al de la fecha vigente (28/oct para el 3/nov) no mueve el calendario: lo fija DO a mano');
select is(pg_temp.cal(9), date '2031-11-15',
  'SOLO ADELANTE · una constancia vieja aprobada tarde no mueve un calendario que ya está adelante');
select is(pg_temp.cal(10), date '2031-10-15',
  'DO MANDA · una constancia vieja aprobada tarde no pisa la fecha que DO fijó (su pago es de septiembre)');
select is(pg_temp.cal(11), date '2031-10-15',
  'SOLO ADELANTE · si la próxima que declara no es posterior a la vigente, no se mueve');
select is(pg_temp.cal(15), date '2031-10-15',
  'NO APROBADA · una constancia pendiente no mueve el calendario');

-- ── 3 · Repetir la aprobación no corre el calendario dos veces ──────────────
create temp table _foto as
  select id, proxima_fecha_pago as prox from asignaciones_educacion where institucion like 'K%';
select fn_educacion_avanzar_calendario(id)
  from educacion_entregas
 where id::text like '00000000-0000-0000-0000-000000527c%';
select is((select count(*)::int from asignaciones_educacion a join _foto f using (id)
            where a.proxima_fecha_pago is distinct from f.prox), 0,
  'IDEMPOTENTE · volver a llamar con las mismas constancias no cambia ningún calendario');

-- ── 4 · La función sigue siendo la misma puerta cerrada ─────────────────────
select is((select count(*)::int from pg_proc where proname = 'fn_educacion_avanzar_calendario'), 1,
  'FIRMA · hay una sola fn_educacion_avanzar_calendario: no se creó una sobrecarga al lado');
select is((select prosecdef from pg_proc where proname = 'fn_educacion_avanzar_calendario'), true,
  'PERMISOS · sigue siendo security definer');
select is(has_function_privilege('authenticated', 'fn_educacion_avanzar_calendario(uuid)', 'execute'), false,
  'PERMISOS · un cliente autenticado sigue sin poder llamarla: solo la llaman las funciones de envío y de revisión');

-- ── 5 · El caso de la vida real, con las funciones de verdad ────────────────
-- Ana vence el 15 de mayo y paga el 3. Envía, DO aprueba.
select set_config('test.hoy', '2031-05-03', true);
insert into storage.objects (bucket_id, name, metadata) values
  ('comprobantes',
   'educacion/00000000-0000-0000-0000-000000527d02/entregas/00000000-0000-0000-0000-000000527c20/p1.jpg',
   '{"mimetype":"image/jpeg","size":1000}');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000527f02', true);
set local role authenticated;

select lives_ok($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-000000527c20', '00000000-0000-0000-0000-000000527b20',
    date '2031-05-03', 'cuota_mensual', date '2031-06-03',
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000527d02/entregas/00000000-0000-0000-0000-000000527c20/p1.jpg","nombre":"Constancia.jpg"}]'::jsonb) $$,
  'VIDA REAL · Ana envía el pago del 3 de mayo y declara su próximo pago el 3 de junio');
select is((select estado_constancia from fn_educacion_situacion()), 'pendiente_revision',
  'VIDA REAL · mientras DO no la mira, queda pendiente de revisión');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000527f01', true);
select lives_ok($$
  select fn_educacion_resolver_entrega('00000000-0000-0000-0000-000000527c20', true, null, null) $$,
  'VIDA REAL · DO la aprueba');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000527f01', true);

select is((select proxima_fecha_pago from fn_educacion_situacion() where institucion like 'L1%'), date '2031-06-03',
  'VIDA REAL · el calendario avanza al 3 de junio aunque venciera el 15 de mayo');
select is((select estado_constancia from fn_educacion_situacion() where institucion like 'L1%'), 'al_dia',
  'VIDA REAL · el 3 de mayo queda al día');

select set_config('test.hoy', '2031-05-20', true);
select is((select estado_constancia from fn_educacion_situacion() where institucion like 'L1%'), 'al_dia',
  'VIDA REAL · el 20 de mayo NO figura por vencer: el mes ya está pagado y aprobado');
select set_config('test.hoy', '2031-05-24', true);
select is((select estado_constancia from fn_educacion_situacion() where institucion like 'L1%'), 'al_dia',
  'VIDA REAL · el 24 de mayo NO figura vencida (antes sí: el plazo de la fecha atrasada era el 23)');
select set_config('test.hoy', '2031-05-31', true);
select is((select estado_constancia from fn_educacion_situacion() where institucion like 'L1%'), 'al_dia',
  'VIDA REAL · el 31 de mayo sigue al día');

select set_config('test.hoy', '2031-06-04', true);
select is((select estado_constancia from fn_educacion_situacion() where institucion like 'L1%'), 'falta_enviar',
  'VIDA REAL · el 4 de junio, ya pasado el 3, se pide la constancia del mes nuevo');
select is((select fecha_pago_constancia from fn_educacion_situacion() where institucion like 'L1%'), date '2031-06-03',
  'VIDA REAL · y se pide el pago del 3 de junio');
select is((select plazo from fn_educacion_situacion() where institucion like 'L1%'), date '2031-06-23',
  'VIDA REAL · con el plazo de siempre: 23 de junio');

-- ── 6 · DO sigue mandando ───────────────────────────────────────────────────
-- Fija una fecha ANTERIOR a la que el sistema calculó, y se queda: la función
-- de DO no se tocó.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000527f01', true);
set local role authenticated;
select lives_ok($$
  select fn_educacion_fijar_calendario('00000000-0000-0000-0000-000000527b20', 'mensual', date '2031-05-10') $$,
  'DO MANDA · DO fija el calendario de Ana en el 10 de mayo, una fecha anterior a la que el sistema había calculado');
reset role;
select is((select proxima_fecha_pago from asignaciones_educacion where id = '00000000-0000-0000-0000-000000527b20'),
  date '2031-05-10',
  'DO MANDA · y se queda exactamente donde DO lo puso');

select * from finish();
rollback;
