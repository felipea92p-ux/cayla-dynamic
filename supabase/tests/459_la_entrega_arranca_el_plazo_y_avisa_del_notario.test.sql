-- ============================================================================
-- 459 — La entrega arranca el plazo y avisa del notario (migración 0569)
-- ============================================================================
--
-- Lo que esta prueba fija, y no es obvio: que la entrega haga DOS cosas que la
-- ley hace depender de ese momento, y que no haga ninguna de las dos cuando no
-- corresponde.
--
-- El caso que más importa de los nueve es el 6: que la imputación de un motor
-- de asistencia —que no trae plazo concedido— se entregue igual que siempre,
-- sin que esta migración le invente un vencimiento. Esas son casi todas las
-- imputaciones que existen hoy, y romperlas sería romper la escalera que sí
-- funciona.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000007a1', 'ZZEN', 'Sede de laboratorio EN', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('ee000000-0000-0000-0000-0000000007af',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'gerencia.en@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-0000000007a2', 'EnGerencia', 'Lab',
        '00000000-0000-0000-0000-0000000007a1', 'admin', 'x',
        'ee000000-0000-0000-0000-0000000007af', '2024-01-01', 'activo'),
       ('00000000-0000-0000-0000-0000000007a3', 'EnImputada', 'Lab',
        '00000000-0000-0000-0000-0000000007a1', 'integrante', 'x', null, '2024-01-01', 'activo');

-- Cuatro documentos FIRMADOS, listos para entregar. Se montan a mano porque lo
-- que se mide es la entrega, no el camino hasta ella.
--
--   d1 · imputación por conducta CON plazo de 6 días (la puerta de la 0568)
--   d2 · imputación por conducta CON plazo, que se entregará con acta interna
--   d3 · imputación por TARDANZA sin plazo (la de los motores: no debe cambiar)
--   d4 · amonestación por conducta, que se entregará con acta interna (el acta
--        sí produce los efectos del cargo firmado acá: numeral 55.4)
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
   falta_rit_version, falta_numeral, falta_literal, conocido_el, plazo_descargo_dias,
   correlativo, firmante_id, firmado_at, creado_por)
values
  ('00000000-0000-0000-0000-0000000007b1', '00000000-0000-0000-0000-0000000007a3',
   'conducta', 'imputacion', 'firmado', date '2025-03-10', date '2025-03-10',
   '[{"fecha":"2025-03-10","relato":"Registró la asistencia de otra integrante en el terminal."}]'::jsonb,
   4.0, '53.3', 'a', date '2025-03-10', 6,
   'LAB-IMP-459-1', '00000000-0000-0000-0000-0000000007a2', now(), '00000000-0000-0000-0000-0000000007a2'),
  ('00000000-0000-0000-0000-0000000007b2', '00000000-0000-0000-0000-0000000007a3',
   'conducta', 'imputacion', 'firmado', date '2025-04-10', date '2025-04-10',
   '[{"fecha":"2025-04-10","relato":"Entregó a un tercero la lista de clientas de la tienda."}]'::jsonb,
   4.0, '53.3', 'c', date '2025-04-10', 6,
   'LAB-IMP-459-2', '00000000-0000-0000-0000-0000000007a2', now(), '00000000-0000-0000-0000-0000000007a2'),
  ('00000000-0000-0000-0000-0000000007b3', '00000000-0000-0000-0000-0000000007a3',
   'tardanza', 'imputacion', 'firmado', date '2025-05-01', date '2025-05-28',
   '[{"fecha":"2025-05-05","minutos":22},{"fecha":"2025-05-12","minutos":31}]'::jsonb,
   null, null, null, null, null,
   'LAB-IMP-459-3', '00000000-0000-0000-0000-0000000007a2', now(), '00000000-0000-0000-0000-0000000007a2'),
  ('00000000-0000-0000-0000-0000000007b4', '00000000-0000-0000-0000-0000000007a3',
   'conducta', 'amonestacion', 'firmado', date '2025-06-10', date '2025-06-10',
   '[{"fecha":"2025-06-10","relato":"No atendió la instrucción sobre el cierre de caja de la tienda."}]'::jsonb,
   4.0, '53.2', 'e', date '2025-06-10', null,
   'LAB-AMO-459-4', '00000000-0000-0000-0000-0000000007a2', now(), '00000000-0000-0000-0000-0000000007a2');
set session_replication_role = origin;

set local request.jwt.claims = '{"sub":"ee000000-0000-0000-0000-0000000007af","role":"authenticated"}';


-- ── 1 · Antes de entregar, la imputación no tiene reloj ────────────────────
-- Es la mitad del punto: el plazo del art. 31 corre desde la RECEPCIÓN, no
-- desde que se redacta o se firma la carta.
select is(
  (select num_nulls(cargos_comunicados_at, descargo_vence_at)::int
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000007b1'),
  2,
  'una imputación firmada y sin entregar no tiene plazo corriendo');


-- ── 2 · Entregarla lo arranca, en días NATURALES ──────────────────────────
-- Seis naturales desde la recepción. Si se contaran hábiles —el reloj del art.
-- 55.2— el vencimiento caería dos días después y el plazo concedido por
-- escrito no sería el que corre.
select fn_expediente_entregar(
  '00000000-0000-0000-0000-0000000007b1', 'fisico', timestamptz '2026-10-05 10:00-05');

select is(
  (select to_char(descargo_vence_at at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
     || ' / ' || to_char(cargos_comunicados_at at time zone 'America/Lima', 'YYYY-MM-DD')
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000007b1'),
  '2026-10-11 10:00 / 2026-10-05',
  'la entrega arranca el plazo: seis días naturales desde la recepción');

-- ── 3 · Y la fecha que manda es la de la entrega, no la de hoy ────────────
-- Una entrega se registra días después de ocurrida. El plazo corrió desde que
-- ella recibió la carta.
select is(
  (select (cargos_comunicados_at = entregado_at)
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000007b1'),
  true,
  'los cargos constan comunicados el día de la entrega, no el del registro');

-- ── 4 · Y una entrega normal no anota nada del art. 57.8 ──────────────────
-- Un aviso que sale siempre se aprende a ignorar. Este sale solo cuando el
-- defecto de verdad ocurrió, como la anotación de la 0267.
select is(
  (select coalesce(observacion, '(vacía)')
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000007b1'),
  '(vacía)',
  'entregada en forma personal, el expediente no tiene nada que explicar');


-- ── 5 · Con acta interna, el expediente lo dice ───────────────────────────
-- Decisión de Felipe del 2026-10-29: avisar, no bloquear. Así que la entrega
-- OCURRE —el documento queda entregado— y queda diciendo lo que le falta.
select fn_expediente_entregar(
  '00000000-0000-0000-0000-0000000007b2', 'acta_negativa', timestamptz '2026-10-06 16:30-05',
  'Rosa Quispe Ramírez');

select is(
  (select estado || ' / ' || (observacion ilike '%57.8%')::text
          || ' / ' || (observacion ilike '%notario%')::text
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000007b2'),
  'entregado / true / true',
  'la entrega con acta interna no se frena, y queda anotada con su artículo');

-- ── 6 · Pero el reloj sí arranca igual ────────────────────────────────────
-- El defecto es de notificación, no de plazo: la carta se entregó, y el art. 31
-- corre. Confundir las dos cosas dejaría el procedimiento sin empezar además
-- de mal notificado.
select is(
  (select to_char(descargo_vence_at at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000007b2'),
  '2026-10-12 16:30',
  'un defecto de notificación no impide que el plazo de descargo corra');


-- ── 7 · La imputación de los motores NO cambia ────────────────────────────
-- EL CASO QUE MÁS IMPORTA. `fn_expediente_generar_tardanza` y
-- `fn_expediente_generar_falta` crean sus imputaciones sin plazo concedido:
-- son casi todas las que existen. Inventarles un vencimiento sería inventar un
-- plazo que nadie concedió por escrito (art. 57.2).
select fn_expediente_entregar(
  '00000000-0000-0000-0000-0000000007b3', 'fisico', timestamptz '2026-10-07 09:00-05');

select is(
  (select estado || ' / ' || num_nulls(cargos_comunicados_at, descargo_vence_at)::text
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000007b3'),
  'entregado / 2',
  'una imputación sin plazo concedido se entrega igual que siempre, sin reloj inventado');


-- ── 8 · Y el acta interna en una amonestación sigue sin tener nada de malo ─
-- Numeral 55.4: ahí el acta «produce los mismos efectos que el cargo firmado».
-- El art. 57.8 solo habla de la carta de imputación y de la de despido. Un
-- aviso que también saliera acá sería falso.
select fn_expediente_entregar(
  '00000000-0000-0000-0000-0000000007b4', 'acta_negativa', timestamptz '2026-10-08 11:00-05',
  'Rosa Quispe Ramírez');

select is(
  (select estado || ' / ' || coalesce(observacion, '(vacía)')
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000007b4'),
  'entregado / (vacía)',
  'el acta de negativa en una amonestación no arrastra el aviso del art. 57.8');


-- ── 9 · El freno del numeral 55.4 sigue en pie ────────────────────────────
-- El caso que DEBE bloquear, y que esta reescritura no podía perder: sin
-- testigo no hay acta, y sin acta no hay entrega.
set session_replication_role = replica;
update expediente_disciplinario set estado = 'firmado', medio_entrega = null, entregado_at = null
 where id = '00000000-0000-0000-0000-0000000007b4';
set session_replication_role = origin;

select throws_like(
  $$ select fn_expediente_entregar(
       '00000000-0000-0000-0000-0000000007b4', 'acta_negativa', now(), '  ') $$,
  '%55.4%',
  'un acta de negativa sin testigo no entrega nada');

select * from finish();
rollback;
