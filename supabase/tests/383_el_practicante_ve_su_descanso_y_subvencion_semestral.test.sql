-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 383_el_practicante_ve_su_descanso_y_subvencion_semestral.test.sql — 0485
-- ============================================================================
-- fn_mis_subvenciones_practicante(): la misma fórmula que fn_subvenciones_
-- practicante (0467), pero para quien llama, sin admin/líder. Lo que defiende:
--
--   1. una practicante ve SU media subvención al completar un semestre;
--   2. y su descanso, saturado al año, sin admin/líder de por medio;
--   3. sin tramo cargado: cero que avisa (sin_subvencion), no un cero mudo;
--   4. quien no es practicante, o no está enlazada, recibe CERO FILAS —nunca
--      un error, porque esta función la llama una pantalla de autoservicio—;
--   5. lo anotado en el libro se resta, igual que en la de admin;
--   6. una practicante NUNCA ve el dato de otra: la función solo conoce a
--      quien llama.
--
-- Las fechas de ingreso se escriben relativas a fn_hoy_lima() —nunca una
-- fecha fija— porque esta función no acepta `p_as_of`: siempre corre sobre
-- HOY, igual que fn_mi_bono_cumpleanos (0478). Fijar el ingreso a exactamente
-- 6 y 13 meses atrás hace que el corte de semestre y el tope del año caigan
-- justo en un borde exacto, sin depender de cuántos días tiene cada mes.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000383000', 'Z383', 'Sede de laboratorio', true);

create function pg_temp.como(p_sub text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_sub, true);
end $$;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo) values
  -- Completó exactamente un semestre hoy: cumplidos=1, 0 días del siguiente.
  -- devengado = 1200 × 0.5 × 1 = 600.00, exacto.
  ('00000000-0000-0000-0000-000000383001', 'Semestral', 'Laboratorio',
   '00000000-0000-0000-0000-000000383000', 'test-hash',
   '00000000-0000-0000-0000-000000383011',
   (fn_hoy_lima() - interval '6 months')::date, 'practicante'),
  -- Superó los 12 meses: el descanso satura en 0.5 exacto y ya está ganado.
  ('00000000-0000-0000-0000-000000383002', 'Anual', 'Laboratorio',
   '00000000-0000-0000-0000-000000383000', 'test-hash',
   '00000000-0000-0000-0000-000000383012',
   (fn_hoy_lima() - interval '13 months')::date, 'practicante'),
  -- Sin ninguna asignación de subvención cargada.
  ('00000000-0000-0000-0000-000000383003', 'SinTramo', 'Laboratorio',
   '00000000-0000-0000-0000-000000383000', 'test-hash',
   '00000000-0000-0000-0000-000000383013',
   (fn_hoy_lima() - interval '2 months')::date, 'practicante'),
  -- Planilla de siempre: no debe salir nada al llamar como ella.
  ('00000000-0000-0000-0000-000000383004', 'Planilla', 'Laboratorio',
   '00000000-0000-0000-0000-000000383000', 'test-hash',
   '00000000-0000-0000-0000-000000383014',
   (fn_hoy_lima() - interval '2 years')::date, 'planilla');
set session_replication_role = origin;

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000383001', 'colibri', 1200, (fn_hoy_lima() - interval '2 years')::date),
  ('00000000-0000-0000-0000-000000383002', 'colibri', 1200, (fn_hoy_lima() - interval '2 years')::date);

-- ── 1 · Media subvención, exacta al cerrar un semestre ──────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000383011');
select is(
  (select round(media_sub_saldo, 2) from fn_mis_subvenciones_practicante()),
  600.00::numeric,
  'MEDIA SUBVENCION · al completar el semestre lleva la mitad de su subvención mensual');

select is(
  (select sin_subvencion from fn_mis_subvenciones_practicante()),
  false,
  'MEDIA SUBVENCION · con tramo cargado, sin_subvencion es false');

-- ── 2 · Descanso, saturado al año y ya ganado ────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000383012');
select is(
  (select round(descanso_saldo, 2) from fn_mis_subvenciones_practicante()),
  600.00::numeric,
  'DESCANSO · pasado el año, satura en media subvención (1200 × 0.5) y no sigue creciendo');

select is(
  (select descanso_ganado from fn_mis_subvenciones_practicante()),
  true,
  'DESCANSO · superados los 12 meses, el descanso ya está GANADO, no solo devengado');

-- ── 3 · Sin tramo cargado: cero que avisa ────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000383013');
select is(
  (select sin_subvencion from fn_mis_subvenciones_practicante()),
  true,
  'SIN TRAMO · la fila sale en cero pero lo DICE, en vez de un cero mudo');
select is(
  (select media_sub_saldo from fn_mis_subvenciones_practicante()),
  0.00::numeric,
  'SIN TRAMO · sin subvención mensual cargada no hay nada devengado');

-- ── 4 · Fuera de alcance: cero filas, nunca un error ────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000383014');
select is(
  (select count(*)::int from fn_mis_subvenciones_practicante()),
  0,
  'ALCANCE · quien está en planilla no recibe filas: esto es solo de modalidad formativa');

select pg_temp.como('00000000-0000-0000-0000-000000383099');
select is(
  (select count(*)::int from fn_mis_subvenciones_practicante()),
  0,
  'ALCANCE · una sesión sin persona enlazada no revienta: recibe cero filas');

-- ── 5 · Lo anotado en el libro se resta ─────────────────────────────────────
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
values ('00000000-0000-0000-0000-000000383002', 'descanso_practicante',
        extract(year from fn_hoy_lima())::int, 250.00, fn_hoy_lima(), 'transferencia');

select pg_temp.como('00000000-0000-0000-0000-000000383012');
select is(
  (select round(descanso_saldo, 2) from fn_mis_subvenciones_practicante()),
  350.00::numeric,
  'LIBRO · un pago anotado baja el saldo (600 − 250), evita pagar dos veces');

-- ── 6 · Una practicante nunca ve el dato de otra ────────────────────────────
select is(
  (select subvencion_mensual from fn_mis_subvenciones_practicante()),
  1200.00::numeric,
  'PRIVACIDAD · quien llama solo ve su propia subvención mensual, ninguna otra fila se filtra');

select * from finish();
