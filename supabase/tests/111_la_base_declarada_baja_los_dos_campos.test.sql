-- ============================================================================
-- 111_la_base_declarada_baja_los_dos_campos.test.sql — fn_fijar_base_declarada
-- (migración 0128)
-- ============================================================================
-- Esta es la función que le baja el sueldo declarado a todo un rango de una
-- sola llamada. Estaba escrita, revisada a ojo y SIN UNA SOLA PRUEBA, que es
-- exactamente lo que el CLAUDE.md prohíbe para cualquier cosa que toque plata.
--
-- Lo que se blinda acá, en el orden en que puede hacer daño:
--
--   1 · BAJA LOS DOS CAMPOS. El pago sale de
--       `asignaciones_salario.salario_mensual_soles`, no de
--       `personas.sueldo_base_legal`. Bajar solo el segundo cambia el desglose
--       de la boleta y no mueve un céntimo de lo que se transfiere: sumarle
--       encima movilidad, educación y bono sobrepagaría por el monto entero de
--       esos conceptos. Si alguna vez alguien "simplifica" esta función a un
--       solo update, esta prueba es lo único que lo detiene.
--
--   2 · A QUIÉN NO ALCANZA. Tres exclusiones, y las tres protegen a una persona
--       real de un recorte que no le corresponde: quien está en otro rango,
--       quien ya cesó (su historial sostiene los reportes de los periodos en
--       que sí trabajó) y quien no está en planilla — un locador no tiene
--       remuneración que declarar (0117).
--
--   3 · `p_omitir`. La educación es POR PERSONA y contra comprobante. A quien
--       no estudia, bajarle la base le recorta el sueldo sin nada que lo
--       reponga. La lista de omitidos es la única puerta de escape, y si deja
--       de funcionar el recorte cae sobre quien no debía.
--
--   4 · QUE SE PUEDA DESHACER. La función devuelve los montos anteriores. Sin
--       esa fila no hay forma de volver atrás: el tramo viejo ya se cerró.
--
--   5 · IDEMPOTENCIA. Se pega a mano en el SQL Editor, y una mano repite. La
--       segunda llamada no debe abrir otro tramo ni ensuciar la auditoría.
--
-- Nota sobre las fechas: la vigencia va al 2026-09-01 a propósito. El candado
-- de periodo pagado (0037) rechaza una vigencia que caiga dentro de un periodo
-- ya pagado, así que la prueba usa una fecha futura y limpia.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000bd', 'ZZBASE', 'Sede de laboratorio', true);

-- Sesión de admin: la función exige fn_es_admin_o_lider(). `replica` desactiva
-- la verificación de la clave foránea contra auth.users, que en la prueba no
-- existe.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000bd00', 'BaseAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000bd', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000bdd00');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000bdd00', true);

-- Cinco personas que cubren cada rama de la selección:
--   A  cayla   · activa · planilla         → SÍ le baja
--   B  cayla   · activa · planilla         → se pasa en p_omitir, NO le baja
--   C  cayla   · INACTIVA                  → NO le baja
--   D  cayla   · activa · rxh (locadora)   → NO le baja
--   E  support · activa · planilla         → otro rango, NO le baja
insert into personas
  (id, nombres, apellidos, sede_base_id, pin_hash, sueldo_base_legal, tipo_vinculo, estado, fecha_cese)
values
  ('00000000-0000-0000-0000-00000000bd01', 'BaseA', 'Laboratorio', '00000000-0000-0000-0000-0000000000bd', 'test-hash', 1450.00, 'planilla', 'activo',   null),
  ('00000000-0000-0000-0000-00000000bd02', 'BaseB', 'Laboratorio', '00000000-0000-0000-0000-0000000000bd', 'test-hash', 1450.00, 'planilla', 'activo',   null),
  ('00000000-0000-0000-0000-00000000bd03', 'BaseC', 'Laboratorio', '00000000-0000-0000-0000-0000000000bd', 'test-hash', 1450.00, 'planilla', 'inactivo', '2026-06-30'),
  ('00000000-0000-0000-0000-00000000bd04', 'BaseD', 'Laboratorio', '00000000-0000-0000-0000-0000000000bd', 'test-hash', 1450.00, 'rxh',      'activo',   null),
  ('00000000-0000-0000-0000-00000000bd05', 'BaseE', 'Laboratorio', '00000000-0000-0000-0000-0000000000bd', 'test-hash', 1650.00, 'planilla', 'activo',   null);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000000bd01', 'cayla',   1450.00, '2026-01-01'),
  ('00000000-0000-0000-0000-00000000bd02', 'cayla',   1450.00, '2026-01-01'),
  ('00000000-0000-0000-0000-00000000bd03', 'cayla',   1450.00, '2026-01-01'),
  ('00000000-0000-0000-0000-00000000bd04', 'cayla',   1450.00, '2026-01-01'),
  ('00000000-0000-0000-0000-00000000bd05', 'support', 1650.00, '2026-01-01');

-- La llamada bajo prueba, guardando lo que devuelve para poder revisarlo.
create temp table resultado_0128 on commit drop as
  select * from fn_fijar_base_declarada(
    'cayla', 1130.00, '2026-09-01',
    array['00000000-0000-0000-0000-00000000bd02']::uuid[]);

-- ── 1 · Los dos campos, al mismo monto ──────────────────────────────────────
-- El corazón de la 0128. Si esta falla, la baja de sueldos se aplicó a medias.
select is(
  (select a.salario_mensual_soles
     from asignaciones_salario a
    where a.persona_id = '00000000-0000-0000-0000-00000000bd01'
      and a.vigente_hasta is null),
  1130.00,
  'El salario vigente —el campo del que sale el pago— baja al monto declarado');

select is(
  (select p.sueldo_base_legal from personas p
    where p.id = '00000000-0000-0000-0000-00000000bd01'),
  1130.00,
  'La básica legal baja al MISMO monto: bajar uno solo no cambia lo que se paga');

-- ── 2 · A quién no alcanza ──────────────────────────────────────────────────
select is(
  (select p.sueldo_base_legal from personas p
    where p.id = '00000000-0000-0000-0000-00000000bd03'),
  1450.00,
  'A quien ya cesó no se le reescribe el salario: su historial sostiene los reportes');

select is(
  (select p.sueldo_base_legal from personas p
    where p.id = '00000000-0000-0000-0000-00000000bd04'),
  1450.00,
  'Una locadora no tiene remuneración que declarar: queda intacta');

select is(
  (select a.salario_mensual_soles
     from asignaciones_salario a
    where a.persona_id = '00000000-0000-0000-0000-00000000bd05'
      and a.vigente_hasta is null),
  1650.00,
  'Fijar la base de un rango no toca a quien está en otro rango');

-- ── 3 · p_omitir ────────────────────────────────────────────────────────────
select is(
  (select a.salario_mensual_soles
     from asignaciones_salario a
    where a.persona_id = '00000000-0000-0000-0000-00000000bd02'
      and a.vigente_hasta is null),
  1450.00,
  'A quien se pasa en p_omitir no se le baja la base, aunque tenga el rango');

-- ── 4 · Que se pueda deshacer ───────────────────────────────────────────────
select is(
  (select count(*)::int from resultado_0128),
  1,
  'Devuelve una fila por persona modificada, y solo A quedó alcanzada');

select results_eq(
  $$ select persona_id, salario_anterior, base_anterior from resultado_0128 $$,
  $$ values ('00000000-0000-0000-0000-00000000bd01'::uuid, 1450.00::numeric, 1450.00::numeric) $$,
  'Devuelve los montos anteriores de cada persona, que es lo único que permite deshacer');

-- ── 5 · El versionado ───────────────────────────────────────────────────────
-- fn_set_salario cierra el tramo anterior el día PREVIO a la nueva vigencia.
-- Si quedaran solapados, un cálculo de un periodo viejo podría tomar el monto
-- nuevo y recalcular hacia abajo un pago ya hecho.
select is(
  (select a.vigente_hasta
     from asignaciones_salario a
    where a.persona_id = '00000000-0000-0000-0000-00000000bd01'
      and a.vigente_desde = '2026-01-01'),
  '2026-08-31'::date,
  'El tramo anterior se cierra el día previo a la vigencia, sin solaparse');

-- ── 6 · Idempotencia ────────────────────────────────────────────────────────
select is(
  (select count(*)::int from fn_fijar_base_declarada(
     'cayla', 1130.00, '2026-09-01',
     array['00000000-0000-0000-0000-00000000bd02']::uuid[])),
  0,
  'Repetir la llamada con el mismo monto no mueve nada ni ensucia la auditoría');

-- ── 7 · El guard ────────────────────────────────────────────────────────────
-- Va al final porque deja la sesión sin identidad de admin.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000bdd99', true);

select throws_like(
  $$ select * from fn_fijar_base_declarada('support', 1290.00, '2026-09-01') $$,
  '%administrador o líder%',
  'Sin sesión de admin la función se niega: nadie más baja sueldos');

select * from finish();
rollback;
