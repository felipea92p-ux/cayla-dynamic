-- ============================================================================
-- 221_un_dia_fichado_no_se_paga_tambien_como_ausencia.test.sql
-- ============================================================================
-- Migración 0285. Un día en que la persona fichó no se paga además como día de
-- ausencia.
--
-- LA FORMA DE ESTE ARCHIVO ES CUATRO PERSONAS IDÉNTICAS, y es a propósito: con
-- el mismo sueldo, el mismo periodo y las mismas jornadas, cualquier diferencia
-- entre ellas solo puede venir de qué ausencia tienen registrada. No hace falta
-- cuadrar ningún número a mano — basta que cobren lo mismo.
--
-- LA ASERCIÓN 2 ES LA QUE VIGILA QUE NO SE ARREGLE DE MÁS. Quien se va de
-- vacaciones y NO ficha tiene que seguir cobrando lo mismo que quien trabaja:
-- la vacación se paga. Si alguien "endurece" esto excluyendo el día de
-- vacaciones sin mirar si hubo jornada, esa aserción se pone roja y le dice por
-- qué.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000285000', 'ZZ285', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000002850ad', 'NueveAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000285000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000002850ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000285001','NueveNormal',  'Laboratorio','00000000-0000-0000-0000-000000285000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000285002','NueveVacLimpia','Laboratorio','00000000-0000-0000-0000-000000285000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000285003','NueveVacFicha', 'Laboratorio','00000000-0000-0000-0000-000000285000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000285004','NueveDMFicha',  'Laboratorio','00000000-0000-0000-0000-000000285000','test-hash','2024-01-01','planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950.00, '2024-01-01'
from personas where apellidos = 'Laboratorio' and nombres like 'Nueve%' and nombres <> 'NueveAdmin';

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '15:30', array[1,2,3,4,5]
from personas where apellidos = 'Laboratorio' and nombres like 'Nueve%' and nombres <> 'NueveAdmin';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000285099', '2026-07-29', '2026-08-28', 'abierto');

-- Todas fichan los mismos días laborables. La única que NO ficha la semana del
-- 10 al 14 es NueveVacLimpia: es el caso correcto contra el que se compara.
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select p.id, d::date, p.sede_base_id, 6.5, 'cerrada'
from personas p
cross join generate_series('2026-07-29'::timestamp, '2026-08-28'::timestamp, interval '1 day') d
where p.apellidos = 'Laboratorio' and p.nombres like 'Nueve%' and p.nombres <> 'NueveAdmin'
  and extract(dow from d)::int between 1 and 5
  and not (p.nombres = 'NueveVacLimpia' and d::date between '2026-08-10' and '2026-08-14');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002850ff', true);

-- La MISMA semana de ausencia para tres. Lo que las separa es si ficharon.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-000000285002','vacaciones',     '2026-08-10','2026-08-14','no ficho','00000000-0000-0000-0000-0000002850ad'),
  ('00000000-0000-0000-0000-000000285003','vacaciones',     '2026-08-10','2026-08-14','ficho igual','00000000-0000-0000-0000-0000002850ad'),
  ('00000000-0000-0000-0000-000000285004','descanso_medico','2026-08-10','2026-08-14','ficho igual','00000000-0000-0000-0000-0000002850ad');

create temporary table _bol on commit drop as
select e->>'nombre' as quien,
       (e->>'total')::numeric          as total,
       (e->>'dias_solapados')::int     as solapados,
       (e->>'monto_vacaciones')::numeric as vacaciones
from jsonb_array_elements(
  fn_planilla_calcular('2026-07-29','2026-08-28','00000000-0000-0000-0000-000000285099') -> 'filas') e
where e->>'nombre' like 'Nueve%';

-- ── 1 · NO SE PAGA DOS VECES ────────────────────────────────────────────────
-- El corazón. Antes de la 0285 esto daba S/2.018,21 contra S/1.680,28.
select is(
  (select total from _bol where quien like 'NueveVacFicha%'),
  (select total from _bol where quien like 'NueveNormal%'),
  'UNA VEZ · quien fichó estando de vacaciones cobra lo mismo que quien trabajó');
select is(
  (select total from _bol where quien like 'NueveDMFicha%'),
  (select total from _bol where quien like 'NueveNormal%'),
  'UNA VEZ · y lo mismo con el descanso médico');

-- ── 2 · PERO LA VACACIÓN SE SIGUE PAGANDO ───────────────────────────────────
-- La mitad que impide arreglarlo de más. Quien se va de vacaciones de verdad
-- cobra igual que quien trabaja: para eso son las vacaciones.
select is(
  (select total from _bol where quien like 'NueveVacLimpia%'),
  (select total from _bol where quien like 'NueveNormal%'),
  'SE PAGA · quien se fue de vacaciones sin fichar cobra igual que quien trabajó');
select cmp_ok(
  (select vacaciones from _bol where quien like 'NueveVacLimpia%'), '>', 0::numeric,
  'SE PAGA · y su vacación aparece como tal en la boleta, no como sueldo');

-- ── 3 · EL AVISO ────────────────────────────────────────────────────────────
-- Que el pago quede bien no basta: alguien tiene que enterarse de que hubo un
-- solapamiento, porque significa que el parte se registró sobre días marcados o
-- que la persona vino a trabajar durante un descanso que la ley obliga a gozar.
select is((select solapados from _bol where quien like 'NueveVacFicha%'), 5,
  'AVISO · la boleta cuenta los 5 días en que fichó estando de ausencia');
select is((select solapados from _bol where quien like 'NueveDMFicha%'), 5,
  'AVISO · también los del descanso médico');
select is((select solapados from _bol where quien like 'NueveVacLimpia%'), 0,
  'AVISO · y no avisa de quien no se solapó con nada');

select * from finish();
rollback;
