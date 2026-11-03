-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- ============================================================================
-- 471_los_cargos_llegan_a_su_info.test.sql — migración 0581
-- ============================================================================
-- La 0581 hace que la comunicación de cargos del RIT 55.2 llegue a la Info de
-- la persona: la ve, confirma que la recibió y, si quiere, escribe su descargo.
-- Y reabre una sola vez el plazo de los borradores que se «comunicaron» antes
-- de que eso existiera.
--
-- Lo que fija esta prueba, en orden de importancia:
--   · Ella ve sus cargos SOLO desde que se comunican, y nadie más que quien
--     tramita ve los suyos.
--   · «Recibí» exige haberlos abierto, y una constancia dada no se mueve.
--   · El descargo solo entra dentro del plazo, después de confirmar, y nunca
--     se edita.
--   · Los antecedentes que la comunicación cita son los que la base cuenta:
--     ni una llamada verbal, ni uno viejo, ni otra falta de conducta.
--   · El reinicio único alcanza a lo comunicado antes del corte y sin valorar,
--     deja rastro, y repetirlo no hace nada.
-- ============================================================================
begin;
select plan(30);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000047101', 'ZZCAR', 'Sede de laboratorio cargos', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000047110', 'Emisora',    'Lab', '00000000-0000-0000-0000-000000047101', 'admin',      'x', '00000000-0000-0000-0000-0000000471a0', '2020-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000047111', 'Sancionada', 'Lab', '00000000-0000-0000-0000-000000047101', 'integrante', 'x', '00000000-0000-0000-0000-0000000471a1', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000047112', 'Otra',       'Lab', '00000000-0000-0000-0000-000000047101', 'integrante', 'x', '00000000-0000-0000-0000-0000000471a2', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000047113', 'Reinicio',   'Lab', '00000000-0000-0000-0000-000000047101', 'integrante', 'x', null,                                     '2024-01-01', 'activo', 'planilla');

-- Borradores de tardanza de la sancionada. Hechos de 2025 para que el freno del
-- numeral 60.5 no se meta en medio (igual que la 456).
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, creado_por)
values
  ('00000000-0000-0000-0000-0000000471b1', '00000000-0000-0000-0000-000000047111', 'tardanza', 'amonestacion', 'borrador',
   date '2025-02-03', date '2025-02-08', '[{"fecha":"2025-02-05","minutos":17}]', '00000000-0000-0000-0000-000000047110'),
  ('00000000-0000-0000-0000-0000000471b2', '00000000-0000-0000-0000-000000047111', 'tardanza', 'amonestacion', 'borrador',
   date '2025-02-03', date '2025-02-08', '[{"fecha":"2025-02-06","minutos":12}]', '00000000-0000-0000-0000-000000047110'),
  ('00000000-0000-0000-0000-0000000471b3', '00000000-0000-0000-0000-000000047111', 'tardanza', 'amonestacion', 'borrador',
   date '2025-02-03', date '2025-02-08', '[{"fecha":"2025-02-07","minutos":9}]', '00000000-0000-0000-0000-000000047110');

-- Antecedentes posibles de b2 (hecho del 08-02-2025): solo el primero cuenta.
insert into expediente_disciplinario
  (persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
   firmante_id, firmado_at, correlativo, entregado_at, medio_entrega, creado_por)
values
  ('00000000-0000-0000-0000-000000047111', 'tardanza', 'amonestacion', 'entregado', date '2024-09-02', date '2024-09-20', '[]',
   '00000000-0000-0000-0000-000000047110', timestamptz '2024-09-30 10:00-05', 'T-OK',      timestamptz '2024-10-01 10:00-05', 'fisico', '00000000-0000-0000-0000-000000047110'),
  ('00000000-0000-0000-0000-000000047111', 'tardanza', 'verbal',       'entregado', date '2024-10-02', date '2024-10-20', '[]',
   '00000000-0000-0000-0000-000000047110', timestamptz '2024-10-30 10:00-05', 'T-VERBAL',  timestamptz '2024-11-01 10:00-05', 'fisico', '00000000-0000-0000-0000-000000047110'),
  ('00000000-0000-0000-0000-000000047111', 'tardanza', 'amonestacion', 'entregado', date '2023-05-02', date '2023-05-20', '[]',
   '00000000-0000-0000-0000-000000047110', timestamptz '2023-05-30 10:00-05', 'T-VIEJO',   timestamptz '2023-06-01 10:00-05', 'fisico', '00000000-0000-0000-0000-000000047110'),
  ('00000000-0000-0000-0000-000000047111', 'tardanza', 'amonestacion', 'entregado', date '2025-05-02', date '2025-05-20', '[]',
   '00000000-0000-0000-0000-000000047110', timestamptz '2025-05-30 10:00-05', 'T-DESPUES', timestamptz '2025-06-01 10:00-05', 'fisico', '00000000-0000-0000-0000-000000047110');

-- Conducta: un borrador del literal e) y dos antecedentes entregados, uno del
-- mismo literal (cuenta, 56.5) y uno de otro (no cuenta).
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
   falta_rit_version, falta_numeral, falta_literal, conocido_el,
   firmante_id, firmado_at, correlativo, entregado_at, medio_entrega, creado_por)
select v.id, '00000000-0000-0000-0000-000000047111', 'conducta', 'amonestacion', v.estado, v.dia, v.dia,
       jsonb_build_array(jsonb_build_object('fecha', v.dia, 'relato', 'Un relato de laboratorio de más de veinte letras.')),
       (select max(rit_version) from faltas_catalogo where numeral = '53.2' and literal = v.literal), '53.2', v.literal, v.dia,
       v.firmante, v.firmado, v.corr, v.entregado, v.medio, '00000000-0000-0000-0000-000000047110'
from (values
  ('00000000-0000-0000-0000-0000000471c1'::uuid, 'borrador',  date '2025-03-01', 'e', null::uuid, null::timestamptz, null, null::timestamptz, null),
  ('00000000-0000-0000-0000-0000000471c2'::uuid, 'entregado', date '2024-12-01', 'e', '00000000-0000-0000-0000-000000047110'::uuid,
   timestamptz '2025-01-09 10:00-05', 'C-MISMO', timestamptz '2025-01-10 10:00-05', 'fisico'),
  ('00000000-0000-0000-0000-0000000471c3'::uuid, 'entregado', date '2024-12-15', 'i', '00000000-0000-0000-0000-000000047110'::uuid,
   timestamptz '2025-01-14 10:00-05', 'C-OTRO',  timestamptz '2025-01-15 10:00-05', 'fisico')
) as v(id, estado, dia, literal, firmante, firmado, corr, entregado, medio);

-- Los del reinicio, de otra persona para no mezclar las cuentas de arriba:
-- r1 comunicado antes del corte y sin valorar (SE reinicia), r2 ya valorado
-- (no), r3 comunicado después del corte (no).
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, creado_por,
   cargos_comunicados_at, descargo_vence_at, descargo_acogido, observacion)
values
  ('00000000-0000-0000-0000-0000000471d1', '00000000-0000-0000-0000-000000047113', 'tardanza', 'amonestacion', 'borrador',
   date '2025-02-03', date '2025-02-08', '[{"fecha":"2025-02-05","minutos":17}]', '00000000-0000-0000-0000-000000047110',
   now() - interval '1 day', now() + interval '1 day', null, 'Cargos comunicados el 02/11/2026 18:14'),
  ('00000000-0000-0000-0000-0000000471d2', '00000000-0000-0000-0000-000000047113', 'tardanza', 'amonestacion', 'borrador',
   date '2025-03-03', date '2025-03-08', '[{"fecha":"2025-03-05","minutos":17}]', '00000000-0000-0000-0000-000000047110',
   now() - interval '5 days', now() - interval '2 days', 'sin_descargo', null),
  ('00000000-0000-0000-0000-0000000471d3', '00000000-0000-0000-0000-000000047113', 'tardanza', 'amonestacion', 'borrador',
   date '2025-04-03', date '2025-04-08', '[{"fecha":"2025-04-05","minutos":17}]', '00000000-0000-0000-0000-000000047110',
   now() - interval '10 minutes', now() + interval '2 days', null, null);
set session_replication_role = origin;

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true);
$$;

-- ── El escenario de la sancionada ───────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000471a0');   -- quien tramita
select fn_expediente_comunicar_cargos('00000000-0000-0000-0000-0000000471b2', 2, null);

set session_replication_role = replica;
update expediente_disciplinario   -- b3: comunicado hace diez días, plazo vencido
   set cargos_comunicados_at = now() - interval '10 days', descargo_vence_at = now() - interval '1 day'
 where id = '00000000-0000-0000-0000-0000000471b3';
update expediente_disciplinario   -- c1: comunicado ahora, plazo vivo
   set cargos_comunicados_at = now(), descargo_vence_at = now() + interval '2 days'
 where id = '00000000-0000-0000-0000-0000000471c1';
set session_replication_role = origin;


-- ── 1 · Qué ve ella, y qué no ───────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000471a1');   -- la sancionada

select is(
  (select array_agg(c ->> 'id' order by c ->> 'id') from jsonb_array_elements(fn_mis_cargos() -> 'cargos') c),
  array['00000000-0000-0000-0000-0000000471b2', '00000000-0000-0000-0000-0000000471b3', '00000000-0000-0000-0000-0000000471c1'],
  've en su Info los tres borradores con cargos comunicados, y no el que todavía no se le comunica');

select throws_like(
  $$ select fn_cargos_detalle('00000000-0000-0000-0000-0000000471b1') $$,
  '%No se encontró%',
  'un borrador sin cargos comunicados no existe para ella');

select throws_like(
  $$ select fn_recibir_cargos('00000000-0000-0000-0000-0000000471b2') $$,
  '%Ábrelos primero%',
  'no puede confirmar que recibió algo que no abrió');

select is(
  (fn_cargos_detalle('00000000-0000-0000-0000-0000000471b2') ->> 'plazo_vigente')::boolean, true,
  'al abrirlos ve su plazo vigente');

select isnt(
  (select abierto_at from recepciones_cargos where expediente_id = '00000000-0000-0000-0000-0000000471b2'), null,
  'abrirlos deja la apertura registrada');

select throws_like(
  $$ select fn_presentar_descargo('00000000-0000-0000-0000-0000000471b2', 'Ese día el bus se malogró en la carretera.') $$,
  '%Primero confirma%',
  'el descargo va después de confirmar que los recibió');


-- ── 2 · Confirmar que los recibió ───────────────────────────────────────────
select lives_ok(
  $$ select fn_recibir_cargos('00000000-0000-0000-0000-0000000471b2') $$,
  'confirma que recibió los cargos');

select is(
  fn_recibir_cargos('00000000-0000-0000-0000-0000000471b2'),
  (select recibido_at from recepciones_cargos where expediente_id = '00000000-0000-0000-0000-0000000471b2'),
  'confirmar otra vez no mueve la fecha: la constancia dada se queda');


-- ── 3 · Su descargo ─────────────────────────────────────────────────────────
select throws_like(
  $$ select fn_presentar_descargo('00000000-0000-0000-0000-0000000471b2', 'corto') $$,
  '%más de detalle%',
  'un descargo de cinco letras no se guarda');

select lives_ok(
  $$ select fn_presentar_descargo('00000000-0000-0000-0000-0000000471b2', 'Ese día el bus se malogró en la carretera y avisé por WhatsApp.') $$,
  'presenta su descargo dentro del plazo');

select is(
  (select count(*)::int from descargos_presentados where expediente_id = '00000000-0000-0000-0000-0000000471b2'), 1,
  'el descargo queda guardado');

select fn_cargos_detalle('00000000-0000-0000-0000-0000000471b3');
select fn_recibir_cargos('00000000-0000-0000-0000-0000000471b3');
select throws_like(
  $$ select fn_presentar_descargo('00000000-0000-0000-0000-0000000471b3', 'Llego tarde con el descargo, pero quería decirlo.') $$,
  '%venció%',
  'con el plazo vencido el descargo ya no entra (aunque la recepción sí se registra)');


-- ── 4 · Los antecedentes que cita son los que la base cuenta ────────────────
select is(
  (select array_agg(p ->> 'correlativo') from jsonb_array_elements(fn_cargos_detalle('00000000-0000-0000-0000-0000000471b2') -> 'previas') p),
  array['T-OK'],
  'tardanza: cita la amonestación entregada en los doce meses previos, no la verbal, ni la vieja, ni la posterior al hecho');

select is(
  (fn_cargos_detalle('00000000-0000-0000-0000-0000000471b2') ->> 'corte')::date, date '2024-09-20',
  'el corte del cómputo (56.6) sale del último entregado ANTES del hecho, sin la verbal ni lo entregado después');

select is(
  (select array_agg(p ->> 'correlativo') from jsonb_array_elements(fn_cargos_detalle('00000000-0000-0000-0000-0000000471c1') -> 'previas') p),
  array['C-MISMO'],
  'conducta: solo cita el antecedente de la MISMA falta (56.5)');


-- ── 5 · Otra persona no ve nada ─────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000471a2');   -- otra integrante

select is(jsonb_array_length(fn_mis_cargos() -> 'cargos'), 0, 'otra persona no tiene cargos de nadie en su Info');

select throws_like(
  $$ select fn_cargos_detalle('00000000-0000-0000-0000-0000000471b2') $$,
  '%Sin permiso%',
  'ni puede abrir los cargos de otra');

select throws_like(
  $$ select fn_recibir_cargos('00000000-0000-0000-0000-0000000471b3') $$,
  '%No se encontró%',
  'ni confirmar en nombre de otra');


-- ── 6 · Quien tramita ve lo mismo, sin dejar huella de apertura ─────────────
select pg_temp.como('00000000-0000-0000-0000-0000000471a0');

select is(
  (fn_cargos_detalle('00000000-0000-0000-0000-0000000471b2') -> 'descargos' -> 0 ->> 'texto'),
  'Ese día el bus se malogró en la carretera y avisé por WhatsApp.',
  'quien tramita lee el descargo que ella escribió');

select lives_ok(
  $$ select fn_cargos_detalle('00000000-0000-0000-0000-0000000471b1') $$,
  'quien tramita puede ver los cargos antes de comunicarlos');

select is(
  (select count(*)::int from recepciones_cargos where expediente_id = '00000000-0000-0000-0000-0000000471b1'), 0,
  'y eso no cuenta como que ella los abrió');


-- ── 7 · Lo dado, dado ───────────────────────────────────────────────────────
select throws_like(
  $$ update descargos_presentados set texto = 'Otra cosa distinta de la que dije.' where expediente_id = '00000000-0000-0000-0000-0000000471b2' $$,
  '%no se modifica%',
  'un descargo presentado no se edita');

select throws_like(
  $$ update recepciones_cargos set recibido_at = now() + interval '1 day' where expediente_id = '00000000-0000-0000-0000-0000000471b2' $$,
  '%no se modifica%',
  'una recepción confirmada no se mueve');


-- ── 8 · El reinicio único ───────────────────────────────────────────────────
select is(
  fn_cargos_reabrir_plazo_sin_info(now() - interval '1 hour'), 1,
  'reinicia solo lo comunicado antes del corte y sin valorar: ni el valorado, ni el comunicado después, ni los ya abiertos por ella');

select is(
  (select array[(cargos_comunicados_at = now())::text, (descargo_vence_at = fn_sumar_dias_habiles(now(), 2))::text,
                (observacion like '%[RECOMUNICADO%Antes: comunicados el%')::text]
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000471d1'),
  array['true', 'true', 'true'],
  'el plazo vuelve a empezar ahora, con dos días hábiles, y la observación dice qué había antes');

select is(
  (select antes_vence_at from cargos_recomunicados where expediente_id = '00000000-0000-0000-0000-0000000471d1'),
  now() + interval '1 day',
  'el rastro guarda el vencimiento que tenía');

-- Una repegada usa el MISMO corte (el momento del primer reinicio): no hace nada.
select is(
  fn_cargos_reabrir_plazo_sin_info(now() - interval '1 hour'), 0,
  'repegar no hace nada: el corte es el de la primera pegada');

-- Y aunque el corte fuera posterior, lo ya reiniciado no se vuelve a tocar:
-- solo entra r3, que esta vez sí queda antes del corte.
select is(
  fn_cargos_reabrir_plazo_sin_info(now() + interval '1 hour'), 1,
  'con un corte posterior entra solo el que faltaba, no el ya reiniciado');

select is(
  (select antes_vence_at from cargos_recomunicados where expediente_id = '00000000-0000-0000-0000-0000000471d1'),
  now() + interval '1 day',
  'el rastro de lo ya reiniciado no se mueve');

select is(
  (select descargo_acogido from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000471d2'), 'sin_descargo',
  'el que ya estaba valorado se queda como estaba');

select * from finish();
rollback;
