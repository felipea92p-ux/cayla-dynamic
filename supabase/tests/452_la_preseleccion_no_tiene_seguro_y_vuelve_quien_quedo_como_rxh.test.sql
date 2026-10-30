-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 452_la_preseleccion_no_tiene_seguro_y_vuelve_quien_quedo_como_rxh.test.sql — la 0561
-- ============================================================================
-- La 0561 MUEVE PLATA (cambia el vínculo, y la planilla lo lee) y toca Seguros. Fija:
--   · Seguros: la preselección (`prueba`) no cae en ningún seguro, como los honorarios.
--   · Mueve a quien la 0554 pasó a planilla y después quedó como RxH (y a quien sigue
--     en planilla), con su preselección abierta desde el INGRESO.
--   · NO toca a quien firmó contrato, a quien se cerró otro día, a una cesada, a una
--     cuenta de servicio, ni a un RxH que nunca estuvo de prueba.
--   · RxH → preselección no deja cambio de seguro (los dos son «sin seguro»); planilla
--     → preselección deja el cambio «EsSalud → ninguno».
--   · La plata, con las mismas horas: lo trabajado no cambia, se SUMA la movilidad
--     asistida (S/ 10 por día asistido) y se descuenta pensión, el EsSalud y la
--     asignación siguen en cero; quien siempre fue planilla cobra exactamente igual.
--   · Repegar es seguro, y la guardia de «a lo sumo dos» frena todo: si salta, ni Seguros ni
--     las personas cambian (un solo bloque: o pasa todo, o no pasa nada).
--
-- La sentencia de abajo es la misma de la 0561; si una cambia, cambia la otra.
-- ============================================================================
begin;
select plan(24);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000452a01', 'ZZ452', 'Sede de laboratorio 452', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-000000452aa0', 'Admin', 'P452', '00000000-0000-0000-0000-000000452a01', 'admin', 'x',
        '00000000-0000-0000-0000-000000452aa1');
-- La cesada y la cuenta de servicio se insertan con los triggers apagados: tienen sus propias puertas (0535, 0544).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, fecha_cese, tipo_vinculo,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000452b05', 'E', 'Cesada', '00000000-0000-0000-0000-000000452a01', 'x', '2026-10-12', '2026-10-27',
   'rxh', 1230, 'inactivo', 'onp');
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo,
                      sueldo_base_legal, estado, regimen_pension, cuenta_de_servicio) values
  ('00000000-0000-0000-0000-000000452b06', 'F', 'Servicio', '00000000-0000-0000-0000-000000452a01', 'x', '2026-10-12',
   'rxh', 1230, 'activo', 'onp', true);
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000452aa1', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, con_hijos,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000452b01', 'R', 'ComoRxh',    '00000000-0000-0000-0000-000000452a01', 'x', '2026-10-19', 'rxh',      true,  1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000452b02', 'P', 'EnPlanilla', '00000000-0000-0000-0000-000000452a01', 'x', '2026-10-21', 'planilla', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000452b03', 'C', 'ConContrato','00000000-0000-0000-0000-000000452a01', 'x', '2026-10-13', 'rxh',      false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000452b04', 'D', 'OtroDia',    '00000000-0000-0000-0000-000000452a01', 'x', '2026-10-10', 'rxh',      false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000452b07', 'G', 'RxhDeSiempre','00000000-0000-0000-0000-000000452a01', 'x', '2026-03-01', 'rxh',     false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000452b08', 'H', 'Testigo',    '00000000-0000-0000-0000-000000452a01', 'x', '2026-01-01', 'planilla', false, 1230, 'activo', 'onp');

-- Las preselecciones que la 0554 cerró como `contratada` el 26/10 (hora de Lima), y una que se cerró el 25/10.
insert into pruebas (persona_id, inicio, resultado, cerrada_at) values
  ('00000000-0000-0000-0000-000000452b01', '2026-10-19', 'contratada', timestamptz '2026-10-26 17:53:41-05'),
  ('00000000-0000-0000-0000-000000452b02', '2026-10-21', 'contratada', timestamptz '2026-10-26 17:53:41-05'),
  ('00000000-0000-0000-0000-000000452b03', '2026-10-13', 'contratada', timestamptz '2026-10-26 17:53:41-05'),
  ('00000000-0000-0000-0000-000000452b04', '2026-10-10', 'contratada', timestamptz '2026-10-25 12:00:00-05'),
  ('00000000-0000-0000-0000-000000452b05', '2026-10-12', 'contratada', timestamptz '2026-10-26 17:53:41-05'),
  ('00000000-0000-0000-0000-000000452b06', '2026-10-12', 'contratada', timestamptz '2026-10-26 17:53:41-05');

-- C firmó un contrato de verdad.
insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, documento_html,
                                 generado_por, fecha_firma, registrado_por) values
  ('00000000-0000-0000-0000-000000452b03', 'indefinido', 'Colibrí', '00000000-0000-0000-0000-000000452a01', 1230, '2026-10-13', '<p>x</p>',
   '00000000-0000-0000-0000-000000452aa0', '2026-10-26', '00000000-0000-0000-0000-000000452aa0');

-- ── Lo trabajado, para medir la plata antes y después ────────────────────────
-- La tarifa de movilidad de esta sede de laboratorio: S/ 10 por día asistido.
insert into parametros_laborales (clave, valor, vigente_desde, sede_codigo, sustento)
values ('movilidad_diaria', 10, '2026-01-01', 'ZZ452', 'laboratorio 452');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1230, '2026-01-01'
  from personas where id in ('00000000-0000-0000-0000-000000452b01', '00000000-0000-0000-0000-000000452b02',
                             '00000000-0000-0000-0000-000000452b08');

create function pg_temp.dia(p_persona uuid, p_fecha date) returns void language sql as $$
  insert into jornadas (persona_id, fecha, horas_trabajadas, estado, entrada_ts, salida_final_ts)
  values (p_persona, p_fecha, 6.5, 'cerrada', (p_fecha || ' 09:00-05')::timestamptz, (p_fecha || ' 15:30-05')::timestamptz);
$$;
select pg_temp.dia('00000000-0000-0000-0000-000000452b01', d::date) from generate_series('2026-10-19'::date, '2026-10-24'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000452b02', d::date) from generate_series('2026-10-21'::date, '2026-10-24'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000452b08', d::date) from generate_series('2026-09-29'::date, '2026-10-24'::date, interval '1 day') d;

create temp table _antes on commit drop as
select (e->>'persona_id')::uuid as pid, e
  from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-09-29', '2026-10-28') -> 'filas') e
 where (e->>'persona_id') like '00000000-0000-0000-0000-000000452b%';

-- ── La sentencia de la 0561 (si una cambia, cambia la otra) ──────────────────
create function pg_temp.sentencia_0561() returns void language plpgsql as $f$
declare
  v_ids uuid[];
  v_n   integer;
begin
  select coalesce(array_agg(p.id), '{}'::uuid[]) into v_ids
    from personas p
   where p.estado = 'activo'
     and p.tipo_vinculo in ('planilla', 'rxh')
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
    raise exception 'PARA. Esta migración devuelve a preselección a lo sumo a las 2 personas que movió la 0554, y la consulta encontró %. No se toca nada (ni Seguros).', v_n;
  end if;

  update seguros_tipos
     set aplica_a_vinculos = array_remove(aplica_a_vinculos, 'prueba')
   where clave = 'essalud'
     and 'prueba' = any(aplica_a_vinculos);

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

select pg_temp.sentencia_0561();

create temp table _despues on commit drop as
select (e->>'persona_id')::uuid as pid, e
  from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-09-29', '2026-10-28') -> 'filas') e
 where (e->>'persona_id') like '00000000-0000-0000-0000-000000452b%';

-- ── Seguros: la preselección no tiene nada ───────────────────────────────────
select is((select aplica_a_vinculos from seguros_tipos where clave = 'essalud'), array['planilla']::text[],
  'EsSalud queda solo para planilla');
select is(fn_seguro_tipo_por_vinculo('prueba'), null,
  'la preselección no cae en ningún seguro: como los honorarios');

-- ── Quién se mueve ───────────────────────────────────────────────────────────
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000452b01'), 'prueba',
  'R, que quedó como RxH tras la 0554, vuelve a «prueba» (preselección)');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000452b02'), 'prueba',
  'P, que seguía en planilla, también');
select is(
  (select count(*)::int from pruebas
    where persona_id in ('00000000-0000-0000-0000-000000452b01', '00000000-0000-0000-0000-000000452b02')
      and resultado = 'en_curso'),
  2, 'Cada una tiene su preselección abierta, una sola');
select is(
  (select count(*)::int from pruebas pr join personas p on p.id = pr.persona_id
    where pr.persona_id in ('00000000-0000-0000-0000-000000452b01', '00000000-0000-0000-0000-000000452b02')
      and pr.resultado = 'en_curso' and pr.inicio = p.fecha_ingreso),
  2, 'La preselección cuenta desde el día de ingreso, no desde hoy');

-- ── Quién NO se mueve ────────────────────────────────────────────────────────
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000452b03'), 'rxh',
  'C firmó su contrato: NO se toca');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000452b04'), 'rxh',
  'D se cerró el 25/10, no el 26: NO se toca');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000452b05'), 'rxh',
  'Una cesada no se toca');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000452b06'), 'rxh',
  'Una cuenta de servicio no se toca (0544)');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000452b07'), 'rxh',
  'Un RxH que nunca estuvo de prueba sigue igual');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000452b08'), 'planilla',
  'Quien siempre fue planilla sigue igual: el testigo');

-- ── El rastro de Seguros ─────────────────────────────────────────────────────
select is((select count(*)::int from seguros_cambios where persona_id = '00000000-0000-0000-0000-000000452b01'), 0,
  'RxH → preselección no mueve el seguro (los dos son «sin seguro»): no deja cambio ni «alta en EsSalud»');
select is(
  (select row(de_tipo, a_tipo, origen)::text from seguros_cambios where persona_id = '00000000-0000-0000-0000-000000452b02'),
  row('essalud', null::text, 'vinculo')::text,
  'planilla → preselección saca a P de EsSalud: deja el cambio «EsSalud → ninguno»');

-- ── La plata: lo trabajado no cambia; lo que se suma, no existe ──────────────
select is((select (e->>'pago_base')::numeric from _despues where pid = '00000000-0000-0000-0000-000000452b01'),
          (select (e->>'pago_base')::numeric from _antes   where pid = '00000000-0000-0000-0000-000000452b01'),
  'HORAS · lo que se paga por lo trabajado es EXACTAMENTE lo mismo antes y después');
select is((select e - 'movimientos' from _despues where pid = '00000000-0000-0000-0000-000000452b08'),
          (select e - 'movimientos' from _antes   where pid = '00000000-0000-0000-0000-000000452b08'),
  'TESTIGO · quien siempre fue planilla cobra EXACTAMENTE igual: ni un campo de su fila cambia');
select is((select coalesce((e->>'aporte_essalud')::numeric, 0) + coalesce((e->>'asignacion_familiar')::numeric, 0)
             from _despues where pid = '00000000-0000-0000-0000-000000452b01'), 0::numeric,
  'DESPUÉS · en preselección no hay EsSalud ni asignación familiar (aunque tenga hijos): como antes de la 0554');
select is((select (e->>'monto_movilidad')::numeric from _antes where pid = '00000000-0000-0000-0000-000000452b01'), 0::numeric,
  'ANTES · como RxH no recibía movilidad');
select is((select (e->>'monto_movilidad')::numeric from _despues where pid = '00000000-0000-0000-0000-000000452b01'), 60::numeric,
  'DESPUÉS · en preselección SE SUMA la movilidad asistida: 6 días asistidos × S/ 10');
select ok((select coalesce((e->>'descuento_afp')::numeric, 0) from _antes where pid = '00000000-0000-0000-0000-000000452b01') = 0
          and (select (e->>'descuento_afp')::numeric from _despues where pid = '00000000-0000-0000-0000-000000452b01') > 0,
  'Y SE DESCUENTA PENSIÓN · como RxH no; en preselección, sí (es lo que la preselección siempre llevó)');

-- ── Repegar es seguro ────────────────────────────────────────────────────────
select pg_temp.sentencia_0561();
select is(
  (select count(*)::int from pruebas
    where persona_id in ('00000000-0000-0000-0000-000000452b01', '00000000-0000-0000-0000-000000452b02')
      and resultado = 'en_curso'),
  2, 'Repegar no duplica la preselección ni mueve a nadie más');

-- ── La guardia frena todo: tampoco se toca Seguros ───────────────────────────
update seguros_tipos set aplica_a_vinculos = array['planilla', 'prueba'] where clave = 'essalud';
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, con_hijos,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000452c01', 'H', 'Uno',  '00000000-0000-0000-0000-000000452a01', 'x', '2026-10-16', 'rxh', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000452c02', 'H', 'Dos',  '00000000-0000-0000-0000-000000452a01', 'x', '2026-10-17', 'rxh', false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000452c03', 'H', 'Tres', '00000000-0000-0000-0000-000000452a01', 'x', '2026-10-18', 'rxh', false, 1230, 'activo', 'onp');
insert into pruebas (persona_id, inicio, resultado, cerrada_at)
select id, fecha_ingreso, 'contratada', timestamptz '2026-10-26 17:53:41-05'
  from personas where id::text like '00000000-0000-0000-0000-000000452c%';

select throws_like(
  $$ select pg_temp.sentencia_0561() $$,
  'PARA. Esta migración devuelve a preselección a lo sumo%',
  'Con tres candidatas la guardia frena y lo dice');
select is((select aplica_a_vinculos from seguros_tipos where clave = 'essalud'), array['planilla', 'prueba']::text[],
  'Y Seguros queda intacto: o pasa todo, o no pasa nada (todo va en un solo bloque)');
select is(
  (select count(*)::int from personas
    where id::text like '00000000-0000-0000-0000-000000452c%' and tipo_vinculo = 'rxh'),
  3, 'Ni movió a ninguna de las tres: ni siquiera a las dos primeras de la lista');

select * from finish();
rollback;
