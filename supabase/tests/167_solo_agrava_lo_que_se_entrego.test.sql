-- ============================================================================
-- 167_solo_agrava_lo_que_se_entrego.test.sql
-- ============================================================================
-- Lo que fija la 0213, y por qué importa que no se revierta.
--
-- El artículo 56 del Reglamento dice dos cosas que el sistema hacía al revés:
-- que un documento firmado y NO entregado «no está vigente, no agrava, no
-- habilita el escalón siguiente», y que los doce meses corren desde la ENTREGA
-- —«ni la fecha de emisión, ni la de creación del borrador, ni la de firma por
-- la Empresa inician ese plazo»—.
--
-- Los dos defectos caían del mismo lado, el que perjudica a la persona: un memo
-- guardado en un cajón empujaba al escalón siguiente, y el plazo empezaba a
-- correr antes de que la persona supiera que el documento existía.
--
-- POR QUÉ ESTA PRUEBA ES DIFÍCIL DE ESCRIBIR SIN TRAMPA
--   La tentación es comprobar el texto de la función. Eso no prueba nada: una
--   reescritura futura puede cambiar las palabras y conservar el defecto. Se
--   prueba el COMPORTAMIENTO — un documento firmado sin entregar, y el escalón
--   que devuelve el sistema con él delante.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000c100', 'ZZENT', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol,
                      tipo_vinculo, estado)
values ('00000000-0000-0000-0000-00000000c101', 'EntFirmante', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c100', 'x', 'admin', 'planilla', 'activo'),
       ('00000000-0000-0000-0000-00000000c102', 'EntPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c100', 'x', 'integrante', 'planilla', 'activo');

-- ── Una amonestación FIRMADA y NO entregada ────────────────────────────────
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta,
   hechos, correlativo, firmante_id, firmado_at, creado_por)
values ('00000000-0000-0000-0000-00000000c110',
        '00000000-0000-0000-0000-00000000c102', 'tardanza', 'amonestacion',
        'firmado', fn_hoy_lima() - 40, fn_hoy_lima() - 35, '[]'::jsonb,
        'T-ZZ/1-2026', '00000000-0000-0000-0000-00000000c101',
        now() - interval '20 days', '00000000-0000-0000-0000-00000000c101');
set session_replication_role = origin;

-- ── 1-2 · Firmada y no entregada: no agrava ────────────────────────────────
select is(
  (select doc_previo from fn_tardanza_escalon('00000000-0000-0000-0000-00000000c102')),
  null,
  'Una amonestación firmada y NO entregada no figura como antecedente');

select is(
  (select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-00000000c102')),
  'amonestacion',
  'Y el siguiente escalón sigue siendo la primera amonestación: quien no recibió nada no puede reincidir');

-- ── 3 · Entregada, sí agrava ───────────────────────────────────────────────
set session_replication_role = replica;
update expediente_disciplinario
   set estado = 'entregado', medio_entrega = 'fisico',
       entregado_at = now() - interval '10 days'
 where id = '00000000-0000-0000-0000-00000000c110';
set session_replication_role = origin;

select is(
  (select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-00000000c102')),
  'suspension',
  'Entregada hace diez días, la misma amonestación sí empuja al escalón siguiente');

-- ── 4 · Los doce meses corren desde la ENTREGA, no desde la firma ──────────
-- Se firma hace catorce meses y se entrega hace uno. Medido desde la firma
-- estaría caducada; medido desde la entrega, viva. El Reglamento dice viva.
set session_replication_role = replica;
update expediente_disciplinario
   set firmado_at   = now() - interval '14 months',
       entregado_at = now() - interval '1 month'
 where id = '00000000-0000-0000-0000-00000000c110';
set session_replication_role = origin;

select is(
  (select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-00000000c102')),
  'suspension',
  'Firmada hace catorce meses pero entregada hace uno: sigue vigente');

-- ── 5 · Y al revés ─────────────────────────────────────────────────────────
set session_replication_role = replica;
update expediente_disciplinario
   set firmado_at   = now() - interval '2 months',
       entregado_at = now() - interval '13 months'
 where id = '00000000-0000-0000-0000-00000000c110';
set session_replication_role = origin;

select is(
  (select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-00000000c102')),
  'amonestacion',
  'Entregada hace trece meses: caducada, aunque se firmara hace dos');

-- ── 6 · Lo mismo para las inasistencias ────────────────────────────────────
-- Un documento de falta firmado y sin entregar no puede ser el antecedente que
-- lleve a la suspensión.
set session_replication_role = replica;
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, hechos, correlativo,
   firmante_id, firmado_at, creado_por)
values ('00000000-0000-0000-0000-00000000c111',
        '00000000-0000-0000-0000-00000000c102', 'falta', 'amonestacion',
        'firmado', '[]'::jsonb, 'F-ZZ/1-2026',
        '00000000-0000-0000-0000-00000000c101', now() - interval '5 days',
        '00000000-0000-0000-0000-00000000c101');
set session_replication_role = origin;

select is(
  (select count(*)::int from expediente_disciplinario
    where persona_id = '00000000-0000-0000-0000-00000000c102'
      and tipo_causal = 'falta' and estado = 'entregado'),
  0,
  'El antecedente de falta está firmado y sin entregar, así que no cuenta');

select * from finish();
rollback;
