-- ============================================================================
-- 457 — La líder propone la suspensión y DO la impone (migración 0567)
-- ============================================================================
--
-- Lo que se prueba es la COMPETENCIA del art. 54.4 c) del RIT, que es lo que el
-- 54.4 d) castiga con la nulidad de la sanción: «Ninguna sanción impuesta por
-- quien no es competente conforme a este numeral produce efecto alguno, no se
-- incorpora al legajo y no sirve de escalón para ninguna sanción posterior».
--
-- Seis de las ocho aserciones son casos que DEBEN bloquear. Un freno que no se
-- prueba contra un caso que tiene que frenar no está probado.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000a0001', 'ZZSP', 'Sede de laboratorio SP', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('ee000000-0000-0000-0000-0000000a00a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'do.sp@laboratorio.local', '', now(), now()),
       ('ee000000-0000-0000-0000-0000000a00a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lider.sp@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado) values
 ('00000000-0000-0000-0000-0000000a0002', 'SpDo',    'Lab', '00000000-0000-0000-0000-0000000a0001', 'admin',           'x', 'ee000000-0000-0000-0000-0000000a00a1', '2024-01-01', 'activo'),
 ('00000000-0000-0000-0000-0000000a0003', 'SpLider', 'Lab', '00000000-0000-0000-0000-0000000a0001', 'supervisor_sede', 'x', 'ee000000-0000-0000-0000-0000000a00a2', '2024-01-01', 'activo'),
 ('00000000-0000-0000-0000-0000000a0004', 'SpIntegrante', 'Lab', '00000000-0000-0000-0000-0000000a0001', 'integrante', 'x', null, '2024-01-01', 'activo'),
 ('00000000-0000-0000-0000-0000000a0005', 'SpSinAntecedente', 'Lab', '00000000-0000-0000-0000-0000000a0001', 'integrante', 'x', null, '2024-01-01', 'activo');

-- Horario vigente: sin él no hay días laborables donde poner la suspensión, y
-- `fn_expediente_set_suspension` se niega con razón — una suspensión no puede
-- caer sobre días de descanso (art. 54.5).
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida)
values ('00000000-0000-0000-0000-0000000a0004', date '2024-01-01', time '09:00', time '18:00'),
       ('00000000-0000-0000-0000-0000000a0005', date '2024-01-01', time '09:00', time '18:00');

-- El ANTECEDENTE de SpIntegrante: amonestación por 53.2 h) entregada el
-- 15-06-2025, tres meses antes del hecho nuevo. Entregada, que es lo único que agrava (56.2).
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
   falta_rit_version, falta_numeral, falta_literal, conocido_el, creado_por,
   correlativo, firmante_id, firmado_at, medio_entrega, entregado_at)
values ('00000000-0000-0000-0000-0000000ab001', '00000000-0000-0000-0000-0000000a0004',
        'conducta', 'amonestacion', 'entregado', date '2025-06-10', date '2025-06-10',
        '[{"fecha":"2025-06-10","relato":"Trato descortes a una clienta en caja, delante de otras dos personas."}]'::jsonb,
        4.0, '53.2', 'h', date '2025-06-10', '00000000-0000-0000-0000-0000000a0002',
        -- Fechas FIJAS y anteriores al hecho nuevo: el antecedente del art. 56.1
        -- corre desde que se ENTREGA, y tiene que haberse entregado antes del
        -- hecho que ahora se sanciona. Con `now()` el antecedente quedaba
        -- fechado después del hecho y fn_conducta_antecedentes lo descartaba,
        -- con razón.
        'ZZ-SP-0001', '00000000-0000-0000-0000-0000000a0002',
        timestamptz '2025-06-15 10:00-05', 'fisico', timestamptz '2025-06-15 10:00-05');

-- Cuatro borradores del hecho NUEVO.
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
   falta_rit_version, falta_numeral, falta_literal, conocido_el, creado_por)
values
 -- significativo, con antecedente: el camino normal
 ('00000000-0000-0000-0000-0000000ac001', '00000000-0000-0000-0000-0000000a0004', 'conducta', 'amonestacion', 'borrador',
  date '2025-09-01', date '2025-09-01', '[{"fecha":"2025-09-01","relato":"Volvio a tratar mal a una clienta, esta vez por telefono."}]'::jsonb,
  4.0, '53.2', 'h', date '2025-09-01', '00000000-0000-0000-0000-0000000a0003'),
 -- otro igual, para probar el tope de días
 ('00000000-0000-0000-0000-0000000ac002', '00000000-0000-0000-0000-0000000a0004', 'conducta', 'amonestacion', 'borrador',
  date '2025-09-02', date '2025-09-02', '[{"fecha":"2025-09-02","relato":"Tercer episodio de trato descortes con una clienta en la tienda."}]'::jsonb,
  4.0, '53.2', 'h', date '2025-09-02', '00000000-0000-0000-0000-0000000a0003'),
 -- LEVE: presentación personal (el ejemplo del propio 56.5)
 ('00000000-0000-0000-0000-0000000ac003', '00000000-0000-0000-0000-0000000a0004', 'conducta', 'amonestacion', 'borrador',
  date '2025-09-03', date '2025-09-03', '[{"fecha":"2025-09-03","relato":"Se presento sin el estandar de presentacion personal acordado."}]'::jsonb,
  4.0, '53.1', 'c', date '2025-09-03', '00000000-0000-0000-0000-0000000a0003'),
 -- significativo pero SIN antecedente: aquí saltar peldaño exige motivo (54.7)
 ('00000000-0000-0000-0000-0000000ac004', '00000000-0000-0000-0000-0000000a0005', 'conducta', 'amonestacion', 'borrador',
  date '2025-09-04', date '2025-09-04', '[{"fecha":"2025-09-04","relato":"Se aparto del procedimiento de manejo de caja sin autorizacion."}]'::jsonb,
  4.0, '53.2', 'g', date '2025-09-04', '00000000-0000-0000-0000-0000000a0003');
set session_replication_role = origin;

-- ── Como la LÍDER ───────────────────────────────────────────────────────────
set local request.jwt.claims = '{"sub":"ee000000-0000-0000-0000-0000000a00a2","role":"authenticated"}';

-- 1 · Puede PEDIR que se suspenda.
select lives_ok(
  $$ select fn_conducta_proponer_suspension('00000000-0000-0000-0000-0000000ac001',
       'La clienta volvio a quejarse por escrito y es el segundo episodio en tres meses: una amonestacion mas no cambia nada.') $$,
  'la líder puede proponer la suspensión, con su motivo escrito');

-- 2 · Y NO puede imponerla. El caso que el art. 54.4 d) castiga con nulidad.
select throws_like(
  $$ select * from fn_expediente_elevar_a_suspension('00000000-0000-0000-0000-0000000ac001', 2, date '2025-09-15', null) $$,
  '%54.4 c%',
  'la líder NO puede imponer la suspensión: la competencia es de DO o Gerencia');

-- 3 · Ni pedirla por una falta leve (54.8).
select throws_like(
  $$ select fn_conducta_proponer_suspension('00000000-0000-0000-0000-0000000ac003',
       'Es la cuarta vez este mes que viene sin el estandar de presentacion personal acordado.') $$,
  '%LEVE%',
  'una falta leve se topa en amonestación escrita, y se avisa al proponer');

-- ── Como DO ─────────────────────────────────────────────────────────────────
set local request.jwt.claims = '{"sub":"ee000000-0000-0000-0000-0000000a00a1","role":"authenticated"}';

-- 4 · DO tampoco puede subir una falta leve.
select throws_like(
  $$ select * from fn_expediente_elevar_a_suspension('00000000-0000-0000-0000-0000000ac003', 1, date '2025-09-15', 'Reiteracion sostenida durante todo el mes de setiembre.') $$,
  '%LEVE%',
  'ni DO sube una falta leve a suspensión: el 54.8 no lo permite a nadie');

-- 5 · Sin antecedente vigente, saltar peldaño exige motivo escrito (54.7).
select throws_like(
  $$ select * from fn_expediente_elevar_a_suspension('00000000-0000-0000-0000-0000000ac004', 1, date '2025-09-15', null) $$,
  '%54.7%',
  'sin antecedente entregado y vigente, suspender sin motivo escrito no pasa');

-- 6 · El tope del 54.5, que no se duplica aquí: lo pone set_suspension.
select throws_like(
  $$ select * from fn_expediente_elevar_a_suspension('00000000-0000-0000-0000-0000000ac002', 5, date '2025-09-16', null) $$,
  '%TRES días%',
  'cinco días no caben: el numeral 54.5 topa toda suspensión en tres');

-- 7 · El camino normal: sube, y queda atada a su antecedente.
select lives_ok(
  $$ select * from fn_expediente_elevar_a_suspension('00000000-0000-0000-0000-0000000ac001', 2, date '2025-09-15', null) $$,
  'con falta significativa y antecedente vigente, DO impone la suspensión');

select is(
  (select nivel || ' / ' || coalesce(doc_previo_id::text, 'sin cadena')
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000ac001'),
  'suspension / 00000000-0000-0000-0000-0000000ab001',
  'el documento subió de nivel y quedó atado al antecedente que habilitó el escalón');

-- ── 9 · Y el candado, no solo la función guardián ───────────────────────────
-- Medido al escribir esta prueba: `expediente_disciplinario` tiene RLS activa y
-- solo tres políticas, las TRES de SELECT. No hay ninguna de UPDATE, así que un
-- cliente `authenticated` que intente escribir directo no recibe un error —
-- simplemente no alcanza ninguna fila. Por eso el candado se prueba con
-- `service_role`, que lleva `bypassrls`: es quien de verdad podría escribir
-- salteando la función, y es la clave de servicio en producción.
--
-- Esa es también la razón de que el trigger no sea redundante: el día que
-- alguien agregue una política de UPDATE a esta tabla, el candado ya está.
set local role service_role;
select throws_like(
  $$ update expediente_disciplinario set suspension_propuesta_motivo = 'escrito a mano por la puerta de atras'
      where id = '00000000-0000-0000-0000-0000000ac002' $$,
  '%no con una escritura directa%',
  'ni con la clave de servicio se escribe la propuesta salteando la función guardián');

select * from finish();
rollback;
