-- ============================================================================
-- 101_un_cero_no_explica_nada.test.sql
-- ============================================================================
-- Tres situaciones distintas salían idénticas en la planilla: S/0.00.
--
--   · De vacaciones todo el periodo → el cero es correcto.
--   · No marcó ningún día debiendo marcar → hay que mirarlo.
--   · Sin horario asignado → el sistema ni sabe qué días le tocaba venir.
--
-- Quien revisa antes de pagar no podía distinguirlas, y la primera —la
-- inofensiva— entrena el ojo para ignorar las otras dos.
--
-- La prueba más importante de este archivo es la última: que añadir estos dos
-- datos NO movió un centavo. Es una función de dinero y se tocó copiando su
-- texto, no reescribiéndolo.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000ce01', 'ZZCER', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ce02', 'CeroAdmin', 'Lab', '00000000-0000-0000-0000-00000000ce01', 'admin', 'x', '00000000-0000-0000-0000-00000000ce0a', '2024-01-01');
set session_replication_role = origin;

-- Tres personas, tres razones distintas para el mismo cero, y una cuarta que sí trabajó.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-00000000ce03', 'CeroVacaciones', 'Lab', '00000000-0000-0000-0000-00000000ce01', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-00000000ce04', 'CeroNoMarco',    'Lab', '00000000-0000-0000-0000-00000000ce01', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-00000000ce05', 'CeroSinHorario', 'Lab', '00000000-0000-0000-0000-00000000ce01', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-00000000ce06', 'CeroTrabaja',    'Lab', '00000000-0000-0000-0000-00000000ce01', 'x', '2024-01-01');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'colibri', 1950, '2024-01-01'
from unnest(array['00000000-0000-0000-0000-00000000ce03'::uuid,
                  '00000000-0000-0000-0000-00000000ce04'::uuid,
                  '00000000-0000-0000-0000-00000000ce05'::uuid,
                  '00000000-0000-0000-0000-00000000ce06'::uuid]) p;

-- Horario de lunes a sábado para tres. CeroSinHorario se queda sin ninguno.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select p, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39,
       '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
         "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
         "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb
from unnest(array['00000000-0000-0000-0000-00000000ce03'::uuid,
                  '00000000-0000-0000-0000-00000000ce04'::uuid,
                  '00000000-0000-0000-0000-00000000ce06'::uuid]) p;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ce0a', true);

-- Vacaciones que cubren el periodo entero (1 al 30 de junio de 2026).
insert into vacaciones (persona_id, fecha_inicio, fecha_fin, creado_por)
values ('00000000-0000-0000-0000-00000000ce03', '2026-06-01', '2026-06-30',
        '00000000-0000-0000-0000-00000000ce02');

-- La que sí trabajó: dos días completos.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000ce06', '00000000-0000-0000-0000-00000000ce01', 'entrada',      '2026-06-01T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000ce06', '00000000-0000-0000-0000-00000000ce01', 'salida_final', '2026-06-01T15:30:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000ce06', '00000000-0000-0000-0000-00000000ce01', 'entrada',      '2026-06-02T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000ce06', '00000000-0000-0000-0000-00000000ce01', 'salida_final', '2026-06-02T15:30:00-05:00');

create temp view _pl as
select f->>'nombre' as nombre,
       (f->>'dias_vacaciones')::int as dias_vac,
       (f->>'dias_laborables')::int as dias_lab,
       (f->>'horas_mes')::numeric   as horas,
       (f->>'pago_base')::numeric   as pago_base,
       (f->>'total')::numeric       as total
from jsonb_array_elements(fn_planilla_calcular('2026-06-01', '2026-06-30')->'filas') f;

-- ── De vacaciones: el cero es correcto y ahora se puede decir por qué ───────
select is((select dias_vac from _pl where nombre = 'CeroVacaciones Lab'),
          30, 'VACACIONES · el periodo entero cubierto se ve como 30 días de vacaciones');

select is((select total from _pl where nombre = 'CeroVacaciones Lab'),
          0::numeric, 'VACACIONES · y su total sigue siendo cero, como debe ser');

-- ── No marcó, pero le tocaba: hay que mirarlo ───────────────────────────────
select is((select dias_vac from _pl where nombre = 'CeroNoMarco Lab'),
          0, 'NO MARCÓ · no tiene ni un día de vacaciones que lo explique');

select cmp_ok((select dias_lab from _pl where nombre = 'CeroNoMarco Lab'),
              '>', 0, 'NO MARCÓ · y sí tenía días que trabajar: el cero no es inofensivo');

-- ── Sin horario: el sistema ni siquiera sabe qué días le tocaba venir ───────
select is((select dias_lab from _pl where nombre = 'CeroSinHorario Lab'),
          0, 'SIN HORARIO · cero días laborables: no es una ausencia, es un dato que falta');

-- Y las dos situaciones se distinguen entre sí, que es todo el punto.
select isnt((select dias_lab from _pl where nombre = 'CeroNoMarco Lab'),
            (select dias_lab from _pl where nombre = 'CeroSinHorario Lab'),
            'DISTINGUIR · «no marcó» y «sin horario» ya no se ven igual');

-- ── Y lo más importante: la plata no se movió ──────────────────────────────
-- El pago por horas, aislado: 2 días × 6.5 h = 13 h · 1950 / (6.5 × 30) = S/130.00.
-- Se comprueba `pago_base` y no `total` a propósito: junio trae el feriado de
-- San Pedro y San Pablo, y el premio de feriado es otro cálculo, ya fijado por
-- las pruebas 10 y 20. Lo que esta prueba vigila es que la 0100 no tocó el pago
-- por horas trabajadas.
select is((select pago_base from _pl where nombre = 'CeroTrabaja Lab'),
          130.00::numeric, 'DINERO · quien trabajó cobra exactamente lo mismo que antes de la 0100');

select is((select dias_vac from _pl where nombre = 'CeroTrabaja Lab'),
          0, 'DINERO · y los datos nuevos no le inventan vacaciones a quien no las tiene');

select * from finish();
rollback;
