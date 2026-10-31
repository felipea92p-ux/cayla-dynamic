-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 450_quien_paso_a_planilla_sin_contrato_vuelve_a_preseleccion.test.sql — la 0558
-- ============================================================================
-- La 0558 MUEVE PLATA (cambia el vínculo, y la planilla lee el vínculo), así que
-- esta prueba fija a quién mueve y, más importante, a quién NO:
--   · Mueve a quien la 0554 pasó a planilla sin contrato (prueba `contratada`
--     el 26/10) y su preselección queda abierta desde su INGRESO, no desde hoy.
--   · NO toca a quien pasó a planilla firmando su contrato ese mismo día, ni a
--     quien se cerró otro día, ni a una cesada, ni a una cuenta de servicio, ni
--     a quien nunca estuvo de prueba.
--   · Repegar es seguro: la segunda vez no encuentra a nadie y no duplica nada.
--   · La guardia se niega a mover a más de dos y no deja a medias a nadie.
--
-- La sentencia de abajo es la misma de la 0558; si una cambia, cambia la otra.
-- ============================================================================
begin;
select plan(18);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000450a01', 'ZZ450', 'Sede de laboratorio 450', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-000000450aa0', 'Admin', 'P450', '00000000-0000-0000-0000-000000450a01', 'admin', 'x',
        '00000000-0000-0000-0000-000000450aa1');
-- La cesada y la cuenta de servicio se insertan con los triggers apagados: tienen sus propias puertas (0535, 0544).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, fecha_cese, tipo_vinculo,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000450b05', 'I', 'Cesada', '00000000-0000-0000-0000-000000450a01', 'x', '2026-10-12', '2026-10-27',
   'planilla', 1230, 'inactivo', 'onp');
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo,
                      sueldo_base_legal, estado, regimen_pension, cuenta_de_servicio) values
  ('00000000-0000-0000-0000-000000450b06', 'S', 'Servicio', '00000000-0000-0000-0000-000000450a01', 'x', '2026-10-12',
   'planilla', 1230, 'activo', 'onp', true);
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450aa1', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, con_hijos,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000450b01', 'A', 'Movida',     '00000000-0000-0000-0000-000000450a01', 'x', '2026-10-14', 'planilla', true,  1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000450b02', 'B', 'Movida',     '00000000-0000-0000-0000-000000450a01', 'x', '2026-10-15', 'planilla', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000450b03', 'C', 'ConContrato','00000000-0000-0000-0000-000000450a01', 'x', '2026-10-13', 'planilla', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000450b04', 'D', 'OtroDia',    '00000000-0000-0000-0000-000000450a01', 'x', '2026-10-10', 'planilla', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000450b07', 'G', 'Siempre',    '00000000-0000-0000-0000-000000450a01', 'x', '2026-01-01', 'planilla', true,  1230, 'activo', 'onp');

-- Las preselecciones que la 0554 cerró como `contratada` el 26/10 (hora de Lima), y una que se cerró el 25/10.
insert into pruebas (persona_id, inicio, resultado, cerrada_at) values
  ('00000000-0000-0000-0000-000000450b01', '2026-10-14', 'contratada', timestamptz '2026-10-26 12:00:00-05'),
  ('00000000-0000-0000-0000-000000450b02', '2026-10-15', 'contratada', timestamptz '2026-10-26 12:00:00-05'),
  ('00000000-0000-0000-0000-000000450b03', '2026-10-13', 'contratada', timestamptz '2026-10-26 12:00:00-05'),
  ('00000000-0000-0000-0000-000000450b04', '2026-10-10', 'contratada', timestamptz '2026-10-25 12:00:00-05'),
  ('00000000-0000-0000-0000-000000450b05', '2026-10-12', 'contratada', timestamptz '2026-10-26 12:00:00-05'),
  ('00000000-0000-0000-0000-000000450b06', '2026-10-12', 'contratada', timestamptz '2026-10-26 12:00:00-05');

-- C pasó a planilla de verdad: firmó su contrato.
insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, documento_html,
                                 generado_por, fecha_firma, registrado_por) values
  ('00000000-0000-0000-0000-000000450b03', 'indefinido', 'Colibrí', '00000000-0000-0000-0000-000000450a01', 1230, '2026-10-13', '<p>x</p>',
   '00000000-0000-0000-0000-000000450aa0', '2026-10-26', '00000000-0000-0000-0000-000000450aa0');

-- ── Lo trabajado, para medir la plata antes y después ────────────────────────
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1230, '2026-01-01'
  from personas where id in ('00000000-0000-0000-0000-000000450b01', '00000000-0000-0000-0000-000000450b02',
                             '00000000-0000-0000-0000-000000450b07');

create function pg_temp.dia(p_persona uuid, p_fecha date) returns void language sql as $$
  insert into jornadas (persona_id, fecha, horas_trabajadas, estado, entrada_ts, salida_final_ts)
  values (p_persona, p_fecha, 6.5, 'cerrada', (p_fecha || ' 09:00-05')::timestamptz, (p_fecha || ' 15:30-05')::timestamptz);
$$;
select pg_temp.dia('00000000-0000-0000-0000-000000450b01', d::date) from generate_series('2026-10-14'::date, '2026-10-16'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000450b02', d::date) from generate_series('2026-10-15'::date, '2026-10-16'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000450b07', d::date) from generate_series('2026-09-29'::date, '2026-10-16'::date, interval '1 day') d;

create temp table _antes on commit drop as
select (e->>'persona_id')::uuid as pid, e
  from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-09-29', '2026-10-28') -> 'filas') e
 where (e->>'persona_id') like '00000000-0000-0000-0000-000000450b%';

-- ── La sentencia de la 0558 (si una cambia, cambia la otra) ──────────────────
create function pg_temp.sentencia_0558() returns void language plpgsql as $f$
declare
  v_ids uuid[];
  v_n   integer;
begin
  select coalesce(array_agg(p.id), '{}'::uuid[]) into v_ids
    from personas p
   where p.estado = 'activo'
     and p.tipo_vinculo = 'planilla'
     and not coalesce(p.cuenta_de_servicio, false)
     and exists (select 1 from pruebas pr
                  where pr.persona_id = p.id
                    and pr.resultado = 'contratada'
                    and pr.cerrada_at >= timestamptz '2026-10-26 00:00:00-05'
                    and pr.cerrada_at <  timestamptz '2026-10-27 00:00:00-05')
     and not exists (select 1 from contratos_generados c
                      where c.persona_id = p.id
                        and c.fecha_firma is not null
                        and c.anulado_at is null);

  v_n := coalesce(cardinality(v_ids), 0);

  if v_n > 2 then
    raise exception 'PARA. Esta migración devuelve a preselección a lo sumo a las 2 personas que movió la 0554, y la consulta encontró %. No se mueve a nadie.', v_n;
  end if;

  if v_n > 0 then
    update personas set tipo_vinculo = 'prueba' where id = any(v_ids);
    update pruebas pr
       set inicio = coalesce(p.fecha_ingreso, pr.inicio)
      from personas p
     where pr.persona_id = p.id
       and pr.persona_id = any(v_ids)
       and pr.resultado = 'en_curso';
  end if;
end
$f$;

select pg_temp.sentencia_0558();

create temp table _despues on commit drop as
select (e->>'persona_id')::uuid as pid, e
  from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-09-29', '2026-10-28') -> 'filas') e
 where (e->>'persona_id') like '00000000-0000-0000-0000-000000450b%';

-- ── Quién se mueve ───────────────────────────────────────────────────────────
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000450b01'), 'prueba',
  'A, pasada a planilla por la 0554 sin contrato, vuelve a «prueba» (preselección)');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000450b02'), 'prueba',
  'B, igual');
select is(
  (select count(*)::int from pruebas
    where persona_id in ('00000000-0000-0000-0000-000000450b01', '00000000-0000-0000-0000-000000450b02')
      and resultado = 'en_curso'),
  2, 'Cada una tiene su preselección abierta, una sola');
select is(
  (select count(*)::int from pruebas pr join personas p on p.id = pr.persona_id
    where pr.persona_id in ('00000000-0000-0000-0000-000000450b01', '00000000-0000-0000-0000-000000450b02')
      and pr.resultado = 'en_curso' and pr.inicio = p.fecha_ingreso),
  2, 'La preselección cuenta desde el día de ingreso, no desde hoy');

-- ── Quién NO se mueve ────────────────────────────────────────────────────────
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000450b03'), 'planilla',
  'C firmó su contrato: pasó a planilla de verdad y NO se toca');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000450b04'), 'planilla',
  'D se cerró el 25/10, no el 26: NO se toca');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000450b05'), 'planilla',
  'Una cesada no se toca: su historia ya está en la fecha de cese');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000450b06'), 'planilla',
  'Una cuenta de servicio no se toca (0544)');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000450b07'), 'planilla',
  'Quien nunca estuvo de prueba sigue igual: el testigo');

-- ── La plata: lo trabajado no cambia; lo que se suma, sí ─────────────────────
select is((select (e->>'pago_base')::numeric from _despues where pid = '00000000-0000-0000-0000-000000450b01'),
          (select (e->>'pago_base')::numeric from _antes   where pid = '00000000-0000-0000-0000-000000450b01'),
  'HORAS · lo que se paga por lo trabajado es EXACTAMENTE lo mismo antes y después (A)');
select is((select (e->>'pago_base')::numeric from _despues where pid = '00000000-0000-0000-0000-000000450b02'),
          (select (e->>'pago_base')::numeric from _antes   where pid = '00000000-0000-0000-0000-000000450b02'),
  'HORAS · y para B');
select is((select e - 'movimientos' from _despues where pid = '00000000-0000-0000-0000-000000450b07'),
          (select e - 'movimientos' from _antes   where pid = '00000000-0000-0000-0000-000000450b07'),
  'TESTIGO · quien siempre fue planilla cobra EXACTAMENTE igual: ni un campo de su fila cambia');
select ok((select (e->>'aporte_essalud')::numeric from _antes where pid = '00000000-0000-0000-0000-000000450b01') > 0,
  'ANTES · en planilla genera EsSalud (el piso de la RMV aunque trabajara tres días)');
select is((select (e->>'aporte_essalud')::numeric from _despues where pid = '00000000-0000-0000-0000-000000450b01'), 0::numeric,
  'DESPUÉS · en preselección ya no genera EsSalud (0484): vuelve a como era antes de la 0554');
select is((select (e->>'asignacion_familiar')::numeric from _despues where pid = '00000000-0000-0000-0000-000000450b01'), 0::numeric,
  'DESPUÉS · y quien tiene hijos no cobra asignación familiar, como antes de la 0554');

-- ── Repegar es seguro ────────────────────────────────────────────────────────
select pg_temp.sentencia_0558();
select is(
  (select count(*)::int from pruebas
    where persona_id in ('00000000-0000-0000-0000-000000450b01', '00000000-0000-0000-0000-000000450b02')
      and resultado = 'en_curso'),
  2, 'Repegar no duplica la preselección ni mueve a nadie más');

-- ── La guardia: más de dos y no se mueve a nadie ─────────────────────────────
-- Dos movidas ya son «prueba»; se agregan tres candidatas nuevas (3 > 2).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, con_hijos,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000450c01', 'H', 'Uno',  '00000000-0000-0000-0000-000000450a01', 'x', '2026-10-16', 'planilla', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000450c02', 'H', 'Dos',  '00000000-0000-0000-0000-000000450a01', 'x', '2026-10-17', 'planilla', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000450c03', 'H', 'Tres', '00000000-0000-0000-0000-000000450a01', 'x', '2026-10-18', 'planilla', false, 1230, 'activo', 'onp');
insert into pruebas (persona_id, inicio, resultado, cerrada_at)
select id, fecha_ingreso, 'contratada', timestamptz '2026-10-26 12:00:00-05'
  from personas where id::text like '00000000-0000-0000-0000-000000450c%';

select throws_like(
  $$ select pg_temp.sentencia_0558() $$,
  'PARA. Esta migración devuelve a preselección a lo sumo%',
  'Con tres candidatas la guardia frena y lo dice');
select is(
  (select count(*)::int from personas
    where id::text like '00000000-0000-0000-0000-000000450c%' and tipo_vinculo = 'planilla'),
  3, 'Y no mueve a ninguna: ni siquiera a las dos primeras de la lista');

select * from finish();
rollback;
