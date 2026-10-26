-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 446_quien_figuraba_de_prueba_pasa_a_planilla.test.sql — la 0554
-- ============================================================================
-- La 0554 MUEVE PLATA, así que esta prueba fija lo que cambia y, más importante,
-- lo que NO puede cambiar:
--   · Las horas que se pagan son EXACTAMENTE las mismas antes y después.
--   · Quien ya estaba en planilla cobra IGUAL (el testigo): arreglar a la gente
--     de prueba tocando a todos sería peor que el defecto.
--   · Cambia lo que se quiso cambiar: la asignación familiar de quien tiene hijos
--     y el aporte de EsSalud. Se compara contra el testigo y no contra un número,
--     para que subir la RMV no ponga roja esta prueba.
--   · Las inactivas y las cuentas de servicio NO se tocan.
--   · El cierre de la prueba queda registrado: es el rastro de cuándo ocurrió.
--
-- ⚠ LO QUE ESTA PRUEBA DOCUMENTA Y NO ARREGLA: el piso de EsSalud (la RMV entera,
-- sin prorratear por días) hace que dos o tres días de trabajo generen el aporte
-- completo. Es la ley según docs/planilla-anexo-tecnico.md, y es exactamente lo
-- que la 0484 evitaba para «prueba» con un riesgo legal que Felipe aceptó el
-- 2026-09-27. Aquí queda fijado a propósito: el costo de registrar a quien
-- trabaja unos días es ese piso, y la defensa es no dejar trabajar a nadie que
-- no se vaya a quedar (la evaluación de selección, sin vínculo).
--
-- Y la parte que NO arreglaba la 0554: quien ya quedó cerrado como «se retiró»
-- (0537) seguía sin entrar a la planilla. Lo arregla la 0555, que reescribe
-- fn_planilla_calcular_nucleo; esta prueba la ejecuta ya con las dos puestas.
--
-- La sentencia de abajo es la misma de la 0554; si una cambia, cambia la otra.
-- ============================================================================
begin;
select plan(17);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000446a01', 'ZZ446', 'Sede de laboratorio 446', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-000000446aa0', 'Admin', 'P446', '00000000-0000-0000-0000-000000446a01', 'admin', 'x',
        '00000000-0000-0000-0000-000000446aa1');
-- La inactiva se inserta con los triggers apagados: un cese real tiene su propia puerta (0535).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, fecha_cese, tipo_vinculo, con_hijos,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000446b05', 'I', 'Inactiva', '00000000-0000-0000-0000-000000446a01', 'x', '2026-10-12', '2026-10-13',
   'prueba', true, 1230, 'inactivo', 'onp');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000446aa1', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, con_hijos,
                      sueldo_base_legal, estado, regimen_pension) values
  ('00000000-0000-0000-0000-000000446b01', 'P', 'ConHijos', '00000000-0000-0000-0000-000000446a01', 'x', '2026-10-14', 'prueba',   true,  1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000446b02', 'P', 'SinHijos', '00000000-0000-0000-0000-000000446a01', 'x', '2026-10-15', 'prueba',   false, 1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000446b03', 'T', 'Testigo',  '00000000-0000-0000-0000-000000446a01', 'x', '2026-01-01', 'planilla', true,  1230, 'activo', 'onp'),
  ('00000000-0000-0000-0000-000000446b04', 'P', 'Retirada', '00000000-0000-0000-0000-000000446a01', 'x', '2026-10-16', 'prueba',   true,  1230, 'activo', 'onp');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1230, '2026-01-01' from personas where id::text like '00000000-0000-0000-0000-000000446b%';

create function pg_temp.dia(p_persona uuid, p_fecha date) returns void language sql as $$
  insert into jornadas (persona_id, fecha, horas_trabajadas, estado, entrada_ts, salida_final_ts)
  values (p_persona, p_fecha, 6.5, 'cerrada', (p_fecha || ' 09:00-05')::timestamptz, (p_fecha || ' 15:30-05')::timestamptz);
$$;
select pg_temp.dia('00000000-0000-0000-0000-000000446b01', d::date) from generate_series('2026-10-14'::date, '2026-10-16'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000446b02', d::date) from generate_series('2026-10-15'::date, '2026-10-16'::date, interval '1 day') d;
select pg_temp.dia('00000000-0000-0000-0000-000000446b04', '2026-10-16');
select pg_temp.dia('00000000-0000-0000-0000-000000446b03', d::date) from generate_series('2026-09-29'::date, '2026-10-16'::date, interval '1 day') d;

-- La retirada: se cierra como «se retiró» por la puerta de la 0536 (queda inactiva).
select fn_prueba_cerrar('00000000-0000-0000-0000-000000446b04', 'retirado', 'Dijo que no volvía');

create temp table _antes on commit drop as
select (e->>'persona_id')::uuid as pid, e
  from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-09-29', '2026-10-28') -> 'filas') e
 where (e->>'persona_id') like '00000000-0000-0000-0000-000000446b%';

-- ── LA SENTENCIA DE LA 0554 ─────────────────────────────────────────────────
update personas
   set tipo_vinculo = 'planilla'
 where tipo_vinculo = 'prueba'
   and estado = 'activo'
   and not coalesce(cuenta_de_servicio, false);
-- ────────────────────────────────────────────────────────────────────────────

create temp table _despues on commit drop as
select (e->>'persona_id')::uuid as pid, e
  from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-09-29', '2026-10-28') -> 'filas') e
 where (e->>'persona_id') like '00000000-0000-0000-0000-000000446b%';

-- ── 1 · Quién se mueve y quién no ───────────────────────────────────────────
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000446b01'), 'planilla',
  'MUEVE · la de prueba con hijos pasa a planilla');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000446b02'), 'planilla',
  'MUEVE · la de prueba sin hijos pasa a planilla');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000446b05'), 'prueba',
  'NO TOCA · la inactiva conserva su vínculo: su liquidación se calculó con él');
select is((select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000446b03'), 'planilla',
  'NO TOCA · quien ya estaba en planilla');
select is((select count(*)::int from personas where tipo_vinculo = 'prueba' and estado = 'activo'
            and id::text like '00000000-0000-0000-0000-000000446b%'), 0,
  'Ninguna persona activa queda con el vínculo «prueba»');

-- ── 2 · El rastro: la prueba se cierra como contratada ──────────────────────
select is((select resultado from pruebas where persona_id = '00000000-0000-0000-0000-000000446b01'), 'contratada',
  'RASTRO · su prueba queda cerrada como «contratada», con la hora en que pasó');
select ok((select cerrada_at is not null from pruebas where persona_id = '00000000-0000-0000-0000-000000446b01'),
  'RASTRO · y con cuándo');

-- ── 3 · Lo que NO puede cambiar: las horas y el testigo ─────────────────────
select is((select (e->>'pago_base')::numeric from _despues where pid = '00000000-0000-0000-0000-000000446b01'),
          (select (e->>'pago_base')::numeric from _antes   where pid = '00000000-0000-0000-0000-000000446b01'),
  'HORAS · lo que se paga por lo trabajado es EXACTAMENTE lo mismo antes y después (con hijos)');
select is((select (e->>'pago_base')::numeric from _despues where pid = '00000000-0000-0000-0000-000000446b02'),
          (select (e->>'pago_base')::numeric from _antes   where pid = '00000000-0000-0000-0000-000000446b02'),
  'HORAS · y sin hijos');
select is((select e - 'movimientos' from _despues where pid = '00000000-0000-0000-0000-000000446b03'),
          (select e - 'movimientos' from _antes   where pid = '00000000-0000-0000-0000-000000446b03'),
  'TESTIGO · quien ya estaba en planilla cobra EXACTAMENTE igual: ni un campo de su fila cambia');

-- ── 4 · Lo que SÍ cambia ────────────────────────────────────────────────────
select is((select (e->>'asignacion_familiar')::numeric from _antes where pid = '00000000-0000-0000-0000-000000446b01'), 0::numeric,
  'ANTES · la de prueba con hijos no cobraba asignación familiar');
select is((select (e->>'asignacion_familiar')::numeric from _despues where pid = '00000000-0000-0000-0000-000000446b01'),
          (select (e->>'asignacion_familiar')::numeric from _despues where pid = '00000000-0000-0000-0000-000000446b03'),
  'DESPUÉS · cobra la misma asignación familiar que cualquiera de planilla');
select is((select (e->>'asignacion_familiar')::numeric from _despues where pid = '00000000-0000-0000-0000-000000446b02'), 0::numeric,
  'SIN HIJOS · no aparece una asignación de la nada');
select is((select (e->>'aporte_essalud')::numeric from _antes where pid = '00000000-0000-0000-0000-000000446b01'), 0::numeric,
  'ANTES · «prueba» no generaba EsSalud (0484)');
select is((select (e->>'aporte_essalud')::numeric from _despues where pid = '00000000-0000-0000-0000-000000446b01'),
          (select (e->>'aporte_essalud')::numeric from _despues where pid = '00000000-0000-0000-0000-000000446b03'),
  'DESPUÉS · genera el MISMO EsSalud que el testigo: el piso entero, aunque haya trabajado tres días');
select ok((select (e->>'aporte_essalud')::numeric from _despues where pid = '00000000-0000-0000-0000-000000446b02')
          > (select (e->>'pago_base')::numeric from _despues where pid = '00000000-0000-0000-0000-000000446b02'),
  'COSTO · con dos días de trabajo el aporte de EsSalud es MAYOR que lo pagado por sus horas: es el costo de registrar a quien se va a ir');

-- ── 5 · Lo que la 0554 sola NO arreglaba, y la 0555 sí ──────────────────────
select is((select count(*)::int from _despues where pid = '00000000-0000-0000-0000-000000446b04'), 1,
  'SE RETIRÓ · desde la 0555 entra a la planilla: se le paga lo que trabajó');

select * from finish();
rollback;
