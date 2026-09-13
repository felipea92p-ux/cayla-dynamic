-- ============================================================================
-- 338_los_practicantes_ya_ocupan_una_fila_en_provisiones.test.sql
-- ============================================================================
-- Migración 0428. Un practicante activo pasa a salir en /admin/provisiones,
-- con su fila en S/ 0.00 —igual de visible que la de alguien recién
-- ingresado a planilla—, en vez de desaparecer como hacía hasta hoy.
--
-- LO QUE HAY QUE DEFENDER, EN ESTE ORDEN:
--   1. el practicante SALE, con las cinco columnas y el gran total en cero
--      (sigue sin devengar nada: solo cambia que la fila se imprime);
--   2. su fila trae `tipo_vinculo = 'practicante'`, para que la pantalla
--      pueda avisar por qué es cero y no confundirlo con «aún no devengó»;
--   3. NO se enciende el aviso de «sin tramo de salario vigente» aunque el
--      practicante no tenga ninguna asignación de salario cargada —avisarle
--      eso sería mentir: su reserva jamás depende del salario—;
--   4. quien ya salía sigue saliendo igual (planilla, con su plata intacta);
--   5. quien seguía sin salir sigue sin salir: locadora, días de prueba y
--      quien no es trabajadora. La excepción es SOLO para practicante.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000338000', 'Z338', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000338001', 'TresAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000338000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000338009', '2025-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  -- Practicante activo, SIN ninguna asignación de salario cargada: el caso
  -- real que reportó Felipe (personas recién ingresadas sin tramo aún).
  ('00000000-0000-0000-0000-000000338002', 'TresPracticante', 'Laboratorio',
   '00000000-0000-0000-0000-000000338000', 'test-hash', '2026-09-05', 'practicante'),
  -- Planilla de siempre, para comprobar que no se movió nada de lo que ya
  -- devengaba.
  ('00000000-0000-0000-0000-000000338003', 'TresPlanilla', 'Laboratorio',
   '00000000-0000-0000-0000-000000338000', 'test-hash', '2025-01-01', 'planilla'),
  -- Las tres categorías que la 0274 dejó fuera y que esta migración NO debe
  -- volver a mostrar: la excepción es solo para 'practicante'.
  ('00000000-0000-0000-0000-000000338004', 'TresLocadora', 'Laboratorio',
   '00000000-0000-0000-0000-000000338000', 'test-hash', '2025-01-01', 'rxh'),
  ('00000000-0000-0000-0000-000000338005', 'TresPrueba', 'Laboratorio',
   '00000000-0000-0000-0000-000000338000', 'test-hash', '2025-01-01', 'prueba'),
  ('00000000-0000-0000-0000-000000338006', 'TresSocia', 'Laboratorio',
   '00000000-0000-0000-0000-000000338000', 'test-hash', '2025-01-01', 'no_trabajador');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000338003', 'colibri', 1300, '2025-01-01'),
       ('00000000-0000-0000-0000-000000338004', 'colibri', 1300, '2025-01-01'),
       ('00000000-0000-0000-0000-000000338005', 'colibri', 1300, '2025-01-01'),
       ('00000000-0000-0000-0000-000000338006', 'colibri', 1300, '2025-01-01');
-- 'TresPracticante' NO recibe ninguna fila en asignaciones_salario: es el
-- caso que tiene que probar que la 0428 no prende una alarma falsa.

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 8, 'cerrada'
from unnest(array['00000000-0000-0000-0000-000000338003'::uuid,
                  '00000000-0000-0000-0000-000000338004'::uuid,
                  '00000000-0000-0000-0000-000000338005'::uuid,
                  '00000000-0000-0000-0000-000000338006'::uuid]) p,
     generate_series('2026-01-05'::date, '2026-06-30'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000338009', true);

create temporary table _lista on commit drop as
select (e ->> 'persona_id')::uuid          as persona_id,
       (e ->> 'nombre')                    as nombre,
       (e ->> 'tipo_vinculo')              as tipo_vinculo,
       (e -> 'gran_total')::numeric        as gran_total,
       (e ->> 'sin_salario_vigente')::bool as sin_salario_vigente
from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e;

-- ── 1 · El practicante ya ocupa una fila ────────────────────────────────────
select is((select count(*)::int from _lista where nombre like 'TresPracticante%'), 1,
  'SALE · el practicante ya aparece en la lista');

-- ── 2 · Con las cinco columnas y el gran total en cero: sigue sin devengar ──
select is((select gran_total from _lista where nombre like 'TresPracticante%'), 0::numeric,
  'CERO DE VERDAD · el practicante sigue sin devengar un céntimo');

-- ── 3 · La pantalla puede distinguir por qué es cero ────────────────────────
select is((select tipo_vinculo from _lista where nombre like 'TresPracticante%'), 'practicante',
  'ETIQUETADO · la fila trae su tipo_vinculo para no confundirse con "aún no devengó"');

-- ── 4 · Sin salario cargado, pero SIN alarma: su reserva no depende de eso ──
select is((select sin_salario_vigente from _lista where nombre like 'TresPracticante%'), false,
  'SIN ALARMA FALSA · no avisa "asígnale el salario" a quien nunca va a reservar por eso');

-- ── 5 · Quien ya salía sigue saliendo, con su plata intacta ─────────────────
select cmp_ok((select gran_total from _lista where nombre like 'TresPlanilla%'), '>', 0::numeric,
  'SIN REGRESIÓN · planilla sigue reservando lo mismo de siempre');

-- ── 6 · La excepción es SOLO para practicante ───────────────────────────────
select is((select count(*)::int from _lista where nombre like 'TresLocadora%'), 0,
  'SIGUE FUERA · la locadora no vuelve a aparecer');
select is((select count(*)::int from _lista where nombre like 'TresPrueba%'), 0,
  'SIGUE FUERA · quien está en días de prueba tampoco');
select is((select count(*)::int from _lista where nombre like 'TresSocia%'), 0,
  'SIGUE FUERA · ni quien no es trabajadora');

select * from finish();
rollback;
