-- ============================================================================
-- 160_una_imputacion_se_cierra_y_el_descargo_se_guarda.test.sql
-- ============================================================================
-- Los dos huecos que cierra la 0206, vistos el 2026-08-10 al preparar el paso
-- siguiente de la primera imputación de cargos que emitió este sistema:
--
--   · El DESCARGO de la persona no tenía dónde archivarse. Y es la pieza que
--     prueba que se respetó el art. 31 de la LPCL: sin ella el legajo demuestra
--     que se imputó, no que se dejó defenderse.
--
--   · Una imputación no se podía CERRAR. Como `fn_tardanza_escalon` bloquea
--     mientras haya una sin resolver, la pantalla habría pedido «decide
--     Gerencia» durante doce meses después de que Gerencia decidiera. Y la
--     única salida era anular — borrar un documento que sí se entregó.
--
-- LO QUE ESTA PRUEBA DEFIENDE, y es lo que se rompe si alguien simplifica:
--
--   Resolver NO es anular. El documento sigue entregado, sigue siendo
--   antecedente vigente y sigue tapando sus propios hechos por el corte. Lo
--   único que cambia es que deja de exigir una decisión.
--
--   Y resolver NO baja de la escalera: tras una imputación resuelta, un solo
--   hecho nuevo vuelve a corresponder imputación. De ahí arriba no se baja.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000f300', 'ZZRES', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000f301', 'ResAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000f300', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000f309');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000f3a1', 'ResPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000f300', 'test-hash', 'planilla');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f309', true);

-- Una imputación ENTREGADA, como la que se emitió de verdad.
insert into expediente_disciplinario
  (id, correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta,
   firmante_id, firmado_at, entregado_at, medio_entrega, creado_por)
values ('00000000-0000-0000-0000-00000000f3d1', 'T-ZZ/0301',
        '00000000-0000-0000-0000-00000000f3a1', 'tardanza', 'imputacion', 'entregado',
        date_trunc('month', fn_hoy_lima())::date, date_trunc('month', fn_hoy_lima())::date,
        '00000000-0000-0000-0000-00000000f301', now() - interval '2 days',
        now() - interval '2 days', 'fisico', '00000000-0000-0000-0000-00000000f301');

-- Y una amonestación entregada, para comprobar que resolver no se le aplica.
insert into expediente_disciplinario
  (id, correlativo, persona_id, tipo_causal, nivel, estado,
   firmante_id, firmado_at, entregado_at, medio_entrega, creado_por)
values ('00000000-0000-0000-0000-00000000f3d2', 'T-ZZ/0302',
        '00000000-0000-0000-0000-00000000f3a1', 'tardanza', 'amonestacion', 'entregado',
        '00000000-0000-0000-0000-00000000f301', now() - interval '40 days',
        now() - interval '40 days', 'fisico', '00000000-0000-0000-0000-00000000f301');

-- ── 1-2 · Sin resolver, la escala bloquea ──────────────────────────────────
select ok(
  (select bloqueado from fn_tardanza_escalon('00000000-0000-0000-0000-00000000f3a1')),
  'Con la imputación sin resolver, la escala bloquea: decide Gerencia, no el sistema');

select is(
  (select minimo from fn_tardanza_escalon('00000000-0000-0000-0000-00000000f3a1')),
  null,
  'Y no hay número de tardanzas que valga mientras esté abierta');

-- ── 3-5 · El descargo se archiva contra la imputación, y solo contra ella ──
select lives_ok(
  $$ select fn_expediente_adjuntar(
       '00000000-0000-0000-0000-00000000f3d1',
       '00000000-0000-0000-0000-00000000f3d1/descargo-1.pdf',
       'descargo', null, 'entregado en mesa de partes') $$,
  'El descargo se archiva contra la imputación entregada');

select is(
  (select tipo from expediente_adjuntos
    where documento_id = '00000000-0000-0000-0000-00000000f3d1'),
  'descargo',
  'Y queda guardado como descargo, no como cargo firmado');

-- ⚠️ CAMBIÓ CON LA 0212, y el motivo importa. Cuando se escribió esta prueba,
-- una amonestación no admitía descargo porque «ahí no hay plazo del art. 31 que
-- responder». Seguía siendo verdad del art. 31 — pero el artículo 55.2 del
-- Reglamento v4.0 creó OTRO plazo, previo y propio de la amonestación, cuya
-- omisión invalida la sanción. Desde entonces una amonestación SÍ admite
-- descargo, pero solo después de comunicar los cargos.
--
-- Lo que esta prueba defiende sigue en pie: un borrador al que nadie comunicó
-- los cargos no admite descargo. Lo que cambia es por qué.
select throws_like(
  $$ select fn_expediente_adjuntar(
       '00000000-0000-0000-0000-00000000f3d2',
       '00000000-0000-0000-0000-00000000f3d2/descargo-1.pdf',
       'descargo', null, null) $$,
  '%cargos ya comunicados%',
  'Un descargo no se cuelga de una amonestación cuyos cargos aún no se comunicaron');

-- ── 6-8 · Resolver exige decir qué y por qué ───────────────────────────────
select throws_like(
  $$ select fn_expediente_resolver('00000000-0000-0000-0000-00000000f3d1', 'archivado', 'ok') $$,
  '%motivo es obligatorio%',
  'No se cierra un procedimiento sin explicar la decisión');

select throws_like(
  $$ select fn_expediente_resolver('00000000-0000-0000-0000-00000000f3d1', 'suspender', 'Se evaluaron los descargos presentados.') $$,
  '%Resultado inválido%',
  'El resultado solo puede ser archivado o despido: no hay sanción intermedia tras imputar');

select throws_like(
  $$ select fn_expediente_resolver('00000000-0000-0000-0000-00000000f3d2', 'archivado', 'Se evaluaron los descargos presentados.') $$,
  '%Solo se resuelve una imputación%',
  'Una amonestación no se resuelve: no abrió ningún plazo');

-- ── 9-11 · Resuelta: deja de bloquear, y NO baja de la escalera ────────────
select lives_ok(
  $$ select fn_expediente_resolver('00000000-0000-0000-0000-00000000f3d1', 'archivado',
       'Evaluados los descargos, se acredita la causa alegada y no se sanciona.') $$,
  'Se resuelve archivando, con su motivo');

select ok(
  not (select bloqueado from fn_tardanza_escalon('00000000-0000-0000-0000-00000000f3a1')),
  'Resuelta, la escala deja de pedir una decisión ya tomada');

select is(
  (select nivel_siguiente || '/' || minimo::text
     from fn_tardanza_escalon('00000000-0000-0000-0000-00000000f3a1')),
  'imputacion/1',
  'Y sigue arriba de la escalera: un solo hecho nuevo vuelve a corresponder imputación');

-- ── 12 · Resolver NO es anular: el documento sigue entregado ───────────────
-- Es la confusión que haría daño. Un procedimiento resuelto es un antecedente
-- que existió; anularlo sería decir que nunca pasó.
select is(
  (select estado from expediente_disciplinario where id = '00000000-0000-0000-0000-00000000f3d1'),
  'entregado',
  'Resolver no anula: el documento sigue entregado y sigue contando como antecedente');

select * from finish();
rollback;
