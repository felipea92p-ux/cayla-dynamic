-- 504 · La gratificación y la CTS se pagan con el sueldo del cierre (0619)
--
-- Lo que tiene que ser cierto de `fn_grati_cts_periodo`:
--   · a quien le BAJÓ el sueldo dentro del semestre se le paga con el del cierre,
--     no con la mayor de las dos cuentas (lo que hacía la 0338);
--   · a quien le SUBIÓ, también con el del cierre (eso no cambia);
--   · a quien no tiene tramo de salario al cierre no se le paga cero por falta de
--     dato: cae al día por día;
--   · un saldo en cero porque ya se depositó NO es falta de dato: no cae al día
--     por día.
-- Seis personas con las MISMAS jornadas; solo cambia su historia de sueldo.
begin;
select plan(13);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000504000', 'ZZ504', 'Sede de laboratorio 504', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000005040ad', 'CuatroAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000504000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000005040a9', '2020-01-01', 'no_trabajador');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000005040a9', true);

-- El periodo que contiene el 15/11 (CTS may–oct, cierre 31/10) y el que contiene
-- el 15/12 (gratificación jul–dic).
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000504c01', '2026-10-29', '2026-11-28', 'abierto'),
  ('00000000-0000-0000-0000-000000504c02', '2026-11-29', '2026-12-28', 'abierto');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000050400a', 'Bajo',     'Laboratorio', '00000000-0000-0000-0000-000000504000', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000050400b', 'Subio',    'Laboratorio', '00000000-0000-0000-0000-000000504000', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000050400c', 'Fijo1245', 'Laboratorio', '00000000-0000-0000-0000-000000504000', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000050400d', 'Fijo1230', 'Laboratorio', '00000000-0000-0000-0000-000000504000', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000050400e', 'SinCierre','Laboratorio', '00000000-0000-0000-0000-000000504000', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000050400f', 'YaPagada', 'Laboratorio', '00000000-0000-0000-0000-000000504000', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000504001', 'PagadaDeMas', 'Laboratorio', '00000000-0000-0000-0000-000000504000', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000504002', 'SinCierreConHijos', 'Laboratorio', '00000000-0000-0000-0000-000000504000', 'test-hash', '2025-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000504003', 'BajaEnDiciembre', 'Laboratorio', '00000000-0000-0000-0000-000000504000', 'test-hash', '2025-01-01', 'planilla');
update personas set con_hijos = true where id = '00000000-0000-0000-0000-000000504002';

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta) values
  ('00000000-0000-0000-0000-00000050400a', 'colibri', 1450, '2025-01-01', '2026-07-28'),
  ('00000000-0000-0000-0000-00000050400a', 'colibri', 1245, '2026-07-29', null),
  ('00000000-0000-0000-0000-00000050400b', 'colibri', 1130, '2025-01-01', '2026-09-30'),
  ('00000000-0000-0000-0000-00000050400b', 'colibri', 1230, '2026-10-01', null),
  ('00000000-0000-0000-0000-00000050400c', 'colibri', 1245, '2025-01-01', null),
  ('00000000-0000-0000-0000-00000050400d', 'colibri', 1230, '2025-01-01', null),
  ('00000000-0000-0000-0000-00000050400e', 'colibri', 1300, '2025-01-01', '2026-09-30'),
  ('00000000-0000-0000-0000-00000050400f', 'colibri', 1245, '2025-01-01', null),
  -- Misma historia que «Bajo», pero con un depósito mayor que todo lo devengado.
  ('00000000-0000-0000-0000-000000504001', 'colibri', 1450, '2025-01-01', '2026-07-28'),
  ('00000000-0000-0000-0000-000000504001', 'colibri', 1245, '2026-07-29', null),
  -- Como «SinCierre», pero con hijos: su asignación familiar devenga sin tramo.
  ('00000000-0000-0000-0000-000000504002', 'colibri', 1300, '2025-01-01', '2026-09-30'),
  -- Le bajan el sueldo el 1 de diciembre: no debe tocar la gratificación.
  ('00000000-0000-0000-0000-000000504003', 'colibri', 1245, '2025-01-01', '2026-11-30'),
  ('00000000-0000-0000-0000-000000504003', 'colibri', 1000, '2026-12-01', null);

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 6.5, 'cerrada'
from personas p,
     generate_series('2026-05-01'::date, '2026-10-31'::date, interval '1 day') d
where p.sede_base_id = '00000000-0000-0000-0000-000000504000' and p.tipo_vinculo = 'planilla'
  and extract(dow from d) <> 0;

insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen, nota)
values ('00000000-0000-0000-0000-00000050400f', 'cts_nov', 2026, 100, '2026-11-10', 'transferencia', 'Adelanto de laboratorio'),
       ('00000000-0000-0000-0000-000000504001', 'cts_nov', 2026, 5000, '2026-11-10', 'transferencia', 'Depósito de más de laboratorio');

create temporary table _pago on commit drop as
select (e->>'persona_id')::uuid as persona_id, (e->>'cts')::numeric as cts
from jsonb_array_elements(fn_grati_cts_periodo('00000000-0000-0000-0000-000000504c01')->'personas') e;

create temporary table _dia on commit drop as
select (e->>'persona_id')::uuid as persona_id, (e->>'cts_nov')::numeric as cts
from jsonb_array_elements(fn_provisiones('2026-10-31')->'personas') e;

create function pg_temp.pago(p text) returns numeric language sql as
$$ select cts from _pago where persona_id = ('00000000-0000-0000-0000-00000050400' || p)::uuid $$;
create function pg_temp.dia(p text) returns numeric language sql as
$$ select cts from _dia where persona_id = ('00000000-0000-0000-0000-00000050400' || p)::uuid $$;

select cmp_ok(pg_temp.pago('c'), '>', 0::numeric, 'CONTROL · con sueldo fijo todo el semestre hay CTS que pagar');

select is(pg_temp.pago('a'), pg_temp.pago('c'),
  'BAJÓ · se paga con el sueldo del cierre (1,245), igual que quien lo tuvo todo el semestre');
select cmp_ok(pg_temp.dia('a'), '>', pg_temp.pago('a'),
  'BAJÓ · y eso es MENOS que el día por día: ya no se paga la mayor de las dos cuentas');

select is(pg_temp.pago('b'), pg_temp.pago('d'),
  'SUBIÓ · se paga con el sueldo del cierre (1,230), como manda la ley');
select cmp_ok(pg_temp.pago('b'), '>', pg_temp.dia('b'),
  'SUBIÓ · que es MÁS que el día por día: el aumento vale para todo el semestre');

select cmp_ok(pg_temp.pago('e'), '>', 0::numeric,
  'SIN TRAMO AL CIERRE · no se le paga cero por falta de dato');
select is(pg_temp.pago('e'), pg_temp.dia('e'),
  'SIN TRAMO AL CIERRE · cae al día por día, que es lo único que se sabe de ella');

select is(pg_temp.pago('f'), pg_temp.pago('c') - 100,
  'YA DEPOSITADA EN PARTE · se paga lo del cierre menos lo depositado, sin caer al día por día');

select is(pg_temp.pago('1'), pg_temp.pago('a') - 5000,
  'DEPOSITADA DE MÁS · sale el saldo del cierre aunque sea negativo: no cae al día por día (con la 0346 salía el del día por día)');

select is(pg_temp.pago('2'), pg_temp.dia('2'),
  'SIN TRAMO AL CIERRE, CON HIJOS · cae al día por día aunque su asignación familiar devengue algo al cierre');
select cmp_ok(pg_temp.pago('2'), '>', pg_temp.pago('e'),
  'SIN TRAMO AL CIERRE, CON HIJOS · y cobra más que quien no tiene hijos: su asignación cuenta');

-- La gratificación sigue la misma regla, y su 9 % sale del mismo número.
select is(
  (select (e->>'grati')::numeric
     from jsonb_array_elements(fn_grati_cts_periodo('00000000-0000-0000-0000-000000504c02')->'personas') e
    where e->>'persona_id' = '00000000-0000-0000-0000-00000050400a'),
  (select (e->>'grati')::numeric
     from jsonb_array_elements(fn_grati_cts_periodo('00000000-0000-0000-0000-000000504c02')->'personas') e
    where e->>'persona_id' = '00000000-0000-0000-0000-00000050400c'),
  'GRATIFICACIÓN · a quien le bajó el sueldo en julio se le paga con el del cierre, igual que a quien lo tuvo siempre');

select is(
  (select (e->>'grati')::numeric
     from jsonb_array_elements(fn_grati_cts_periodo('00000000-0000-0000-0000-000000504c02')->'personas') e
    where e->>'persona_id' = '00000000-0000-0000-0000-000000504003'),
  (select (e->>'grati')::numeric
     from jsonb_array_elements(fn_grati_cts_periodo('00000000-0000-0000-0000-000000504c02')->'personas') e
    where e->>'persona_id' = '00000000-0000-0000-0000-00000050400c'),
  'GRATIFICACIÓN · un cambio de sueldo del 1 de diciembre no la toca: manda el sueldo del 30 de noviembre');

select * from finish();
rollback;
