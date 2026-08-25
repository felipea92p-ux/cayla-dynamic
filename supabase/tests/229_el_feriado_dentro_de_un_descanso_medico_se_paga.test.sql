-- ============================================================================
-- 229_el_feriado_dentro_de_un_descanso_medico_se_paga.test.sql
-- ============================================================================
-- Migración 0293. Un feriado caído dentro de un descanso médico se paga, igual
-- que si cae dentro de unas vacaciones.
--
-- LA ASERCIÓN 1 ES TODO EL ARCHIVO, y es una igualdad y no un número: dos
-- personas idénticas, mismo tramo de cinco días ausente, mismo feriado dentro,
-- una con parte médico y otra de vacaciones. Tienen que cobrar LO MISMO. Antes
-- de la 0293 la del parte médico cobraba S/69,93 menos, y solo por estar
-- enferma.
--
-- LAS OTRAS TRES SON LOS TOPES, y están para que el arreglo no se pase:
--   · quien faltó SIN parte sigue cobrando bastante menos (2) — el parte médico
--     tiene que seguir valiendo algo;
--   · quien TRABAJÓ el feriado sigue cobrando más (3) — la sobretasa del art. 9
--     no se toca;
--   · y el prorrateo general del feriado sigue vivo (4): quien trabajó medio
--     mes cobra menos feriado que quien trabajó entero. Eso es decisión de
--     Felipe, confirmada en el anexo técnico, y esta migración NO lo discute.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000293000', 'ZZ293', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000002930ad', 'OnceAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000293000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000002930ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000293001','OnceTrabajoTodo','Laboratorio','00000000-0000-0000-0000-000000293000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000293002','OnceParteMedico','Laboratorio','00000000-0000-0000-0000-000000293000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000293003','OnceVacaciones', 'Laboratorio','00000000-0000-0000-0000-000000293000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-000000293004','OnceSinJustificar','Laboratorio','00000000-0000-0000-0000-000000293000','test-hash','2024-01-01','planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950.00, '2024-01-01'
from personas where apellidos = 'Laboratorio' and nombres like 'Once%' and nombres <> 'OnceAdmin';

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '15:30', array[1,2,3,4,5]
from personas where apellidos = 'Laboratorio' and nombres like 'Once%' and nombres <> 'OnceAdmin';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000293099', '2026-07-29', '2026-08-28', 'abierto');

-- El feriado que hace medible todo esto: miércoles 19, dentro de la semana
-- ausente de las tres.
insert into feriados (fecha, nombre) values ('2026-08-19', 'Feriado de laboratorio 293')
on conflict do nothing;

-- Todas fichan los mismos laborables. Las tres ausentes pierden la MISMA
-- semana: lo único que las separa es cómo está justificada.
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select p.id, d::date, p.sede_base_id, 6.5, 'cerrada'
from personas p
cross join generate_series('2026-07-29'::timestamp, '2026-08-28'::timestamp, interval '1 day') d
where p.apellidos = 'Laboratorio' and p.nombres like 'Once%' and p.nombres <> 'OnceAdmin'
  and extract(dow from d)::int between 1 and 5
  and not (p.nombres <> 'OnceTrabajoTodo' and d::date between '2026-08-17' and '2026-08-21');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002930ff', true);

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-000000293002','descanso_medico','2026-08-17','2026-08-21','parte medico','00000000-0000-0000-0000-0000002930ad'),
  ('00000000-0000-0000-0000-000000293003','vacaciones',     '2026-08-17','2026-08-21','vacaciones','00000000-0000-0000-0000-0000002930ad');
-- OnceSinJustificar se queda sin nada registrado, a propósito.

create temporary table _bol on commit drop as
select e->>'nombre' as quien, (e->>'total')::numeric as total,
       (e->>'monto_feriados')::numeric as feriados
from jsonb_array_elements(
  fn_planilla_calcular('2026-07-29','2026-08-28','00000000-0000-0000-0000-000000293099') -> 'filas') e
where e->>'nombre' like 'Once%';

-- ── 1 · EL CORAZÓN ──────────────────────────────────────────────────────────
-- Misma situación, mismo pago. Antes de la 0293: S/1.664,20 contra S/1.734,13.
select is(
  (select total from _bol where quien like 'OnceParteMedico%'),
  (select total from _bol where quien like 'OnceVacaciones%'),
  'IGUALDAD · el feriado dentro de un parte medico se paga igual que dentro de vacaciones');

-- ── 2 · EL PARTE MÉDICO SIGUE VALIENDO ──────────────────────────────────────
-- Si alguien "arregla" esto pagando a todos igual, esta se pone roja.
select cmp_ok(
  (select total from _bol where quien like 'OnceParteMedico%'), '>',
  (select total from _bol where quien like 'OnceSinJustificar%'),
  'TOPE · quien tiene parte medico sigue cobrando mas que quien falto sin justificar');

-- ── 3 · Y TRABAJAR EL FERIADO SIGUE VALIENDO MÁS ────────────────────────────
-- La sobretasa del art. 9 no se toca.
select cmp_ok(
  (select total from _bol where quien like 'OnceTrabajoTodo%'), '>',
  (select total from _bol where quien like 'OnceParteMedico%'),
  'TOPE · quien trabajo el feriado sigue cobrando mas que quien estuvo de baja');

-- ── 4 · EL PRORRATEO GENERAL NO SE DISCUTE ──────────────────────────────────
-- Decisión de Felipe, confirmada en docs/planilla-anexo-tecnico.md: «que un
-- part-time cobre menos feriado no es un bug». Esta migración corrige que un
-- día que la norma manda contar como trabajado no se contaba — no el prorrateo.
select cmp_ok(
  (select feriados from _bol where quien like 'OnceTrabajoTodo%'), '>',
  (select feriados from _bol where quien like 'OnceSinJustificar%'),
  'PRORRATEO · quien trabajo mas sigue cobrando mas feriado: eso no cambia');

select * from finish();
rollback;
