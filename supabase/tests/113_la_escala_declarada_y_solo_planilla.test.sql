-- ============================================================================
-- 113_la_escala_declarada_y_solo_planilla.test.sql — fn_cuadro_categorias
-- (migración 0145)
-- ============================================================================
-- El cuadro de categorías es un documento LEGAL: la Ley 30709 obliga a tenerlo
-- y a informarlo, y una inspección lo lee para verificar que hay criterios
-- objetivos detrás de cada remuneración.
--
-- Hasta la 0145 ese documento se armaba con los sueldos reales de quien
-- estuviera en cada categoría, filtrando solo por `estado = 'activo'`. Un
-- locador está activo, así que su honorario entraba como si fuera remuneración
-- de planilla, y en producción el documento llegó a publicar:
--
--     Aurora S/1360 a S/1800  ·  Oráculo S/1800  ·  ArchiCayla S/1500
--
-- La categoría más alta, publicada por debajo de la anterior.
--
-- Lo que se blinda acá:
--   1 · la remuneración publicada es la DECLARADA, y no se mueve porque alguien
--       cobre distinto;
--   2 · el conteo de personas cuenta solo `tipo_vinculo = 'planilla'` — ni
--       locadores ni periodo de prueba;
--   3 · la brecha entre el sueldo más alto y el más bajo usa el mismo filtro;
--   4 · la escala declarada sube con la categoría, que es el criterio que
--       sostiene todo el documento.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ca', 'ZZCUAD', 'Sede de laboratorio', true);

-- Sesión con identidad: la función exige estar logueada (no exige rol, porque
-- la ley obliga a informar el cuadro a todo el equipo).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000ca00', 'CuadroAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ca', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000cad00');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000cad00', true);

-- Tres personas en 'oraculo', que es donde el error se veía:
--   A  planilla   S/1440 → cuenta
--   B  rxh        S/1800 → NO cuenta (es la que rompía la escala)
--   C  prueba     S/1440 → NO cuenta (decisión: solo planilla estricta)
insert into personas
  (id, nombres, apellidos, sede_base_id, pin_hash, tipo_vinculo, estado)
values
  ('00000000-0000-0000-0000-00000000ca01', 'CuadroA', 'Laboratorio', '00000000-0000-0000-0000-0000000000ca', 'test-hash', 'planilla', 'activo'),
  ('00000000-0000-0000-0000-00000000ca02', 'CuadroB', 'Laboratorio', '00000000-0000-0000-0000-0000000000ca', 'test-hash', 'rxh',      'activo'),
  ('00000000-0000-0000-0000-00000000ca03', 'CuadroC', 'Laboratorio', '00000000-0000-0000-0000-0000000000ca', 'test-hash', 'prueba',   'activo');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000000ca01', 'oraculo', 1440.00, '2026-01-01'),
  ('00000000-0000-0000-0000-00000000ca02', 'oraculo', 1800.00, '2026-01-01'),
  ('00000000-0000-0000-0000-00000000ca03', 'oraculo', 1440.00, '2026-01-01');

-- ── 1 · La remuneración publicada es la declarada ───────────────────────────
select is(
  (select (c->>'salario_declarado')::numeric
     from jsonb_array_elements(fn_cuadro_categorias()->'categorias') c
    where c->>'rango' = 'oraculo'),
  1440.00,
  'Oráculo publica su monto declarado (1440), no el honorario de 1800 de un locador');

-- ── 2 · Solo planilla estricta ──────────────────────────────────────────────
select is(
  (select (c->>'personas')::int
     from jsonb_array_elements(fn_cuadro_categorias()->'categorias') c
    where c->>'rango' = 'oraculo'),
  1,
  'Cuenta 1 persona: ni la locadora ni la que está en periodo de prueba suman');

select is(
  (select (c->>'salario_max')::numeric
     from jsonb_array_elements(fn_cuadro_categorias()->'categorias') c
    where c->>'rango' = 'oraculo'),
  1440.00,
  'El máximo interno tampoco toma el honorario del locador');

-- ── 3 · La brecha usa el mismo filtro ───────────────────────────────────────
-- Con el locador de 1800 dentro, la brecha sería mayor: el documento declararía
-- una desigualdad que no existe entre las remuneraciones de la empresa.
select ok(
  (select (fn_cuadro_categorias()->>'brecha')::numeric)
    <= (select round(max(a.salario_mensual_soles) / min(a.salario_mensual_soles), 2)
          from asignaciones_salario a
          join personas p on p.id = a.persona_id
         where a.vigente_hasta is null and p.estado = 'activo'),
  'La brecha publicada no supera a la que saldría contando a todo el mundo');

-- ── 4 · La escala sube con la categoría ─────────────────────────────────────
select is(
  (select count(*)::int
     from categorias_laborales a
     join categorias_laborales b on b.orden = a.orden + 1
    where a.salario_declarado is not null
      and b.salario_declarado is not null
      and b.salario_declarado <= a.salario_declarado),
  0,
  'Ninguna categoría vale igual o menos que la anterior');

select is(
  (select count(*)::int from categorias_laborales where salario_declarado is null),
  0,
  'Las seis categorías tienen su monto declarado cargado');

-- ── 5 · El monto declarado no se deduce de nadie ────────────────────────────
-- Cambiar el sueldo real de la única persona en planilla de la categoría no
-- mueve lo que el documento publica. Es la propiedad que hace que el papel
-- describa la política y no al revés.
update asignaciones_salario set salario_mensual_soles = 9999.00
 where persona_id = '00000000-0000-0000-0000-00000000ca01';

select is(
  (select (c->>'salario_declarado')::numeric
     from jsonb_array_elements(fn_cuadro_categorias()->'categorias') c
    where c->>'rango' = 'oraculo'),
  1440.00,
  'Un sueldo negociado por encima de su categoría NO reescribe la escala publicada');

select * from finish();
rollback;
