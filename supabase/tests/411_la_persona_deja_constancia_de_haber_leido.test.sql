-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 411_la_persona_deja_constancia_de_haber_leido.test.sql
-- ============================================================================
-- La 0516: quien recibió un documento en papel deja constancia de haberlo
-- abierto y leído. Lo que fija esta prueba, en orden de importancia:
--   · «Lo leí» sin haber abierto nada NO se puede dar: la constancia que no
--     prueba que se abrió no prueba nada.
--   · Recibir por Info ya es la constancia: no se pide otra, ni se deja dar.
--   · Una constancia dada no se edita ni se borra, y la primera apertura no
--     se mueve.
--   · Nadie deja constancia sobre el documento de otra persona.
--   · La lista de la persona trae lo suyo —y solo lo suyo—, sin el relato.
--   · La lista dice cuándo algo pesa, cuándo ya no, y qué pide leer.
-- ============================================================================
begin;
select plan(38);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000c1601', 'ZZLE1', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000c1611', 'Gerencia',  'Lab', '00000000-0000-0000-0000-0000000c1601', 'admin',           'x', '00000000-0000-0000-0000-0000000c16a1', '2020-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-0000000c1612', 'Lider',     'Lab', '00000000-0000-0000-0000-0000000c1601', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000c16a2', '2021-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-0000000c1613', 'PersonaA',  'Lab', '00000000-0000-0000-0000-0000000c1601', 'integrante',      'x', '00000000-0000-0000-0000-0000000c16a3', '2023-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-0000000c1614', 'PersonaB',  'Lab', '00000000-0000-0000-0000-0000000c1601', 'integrante',      'x', '00000000-0000-0000-0000-0000000c16a4', '2023-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-0000000c1615', 'PersonaC',  'Lab', '00000000-0000-0000-0000-0000000c1601', 'integrante',      'x', '00000000-0000-0000-0000-0000000c16a5', '2023-01-01', 'activo', 'planilla');
set session_replication_role = origin;

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true);
$$;

-- Documentos de la persona A. El firmante y el correlativo los exige el esquema.
create function pg_temp.doc(
  p_id uuid, p_persona uuid, p_corr text, p_nivel text, p_estado text, p_medio text, p_entregado timestamptz,
  p_causal text default 'tardanza'
) returns void language sql as $$
  insert into expediente_disciplinario
    (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
     firmante_id, firmado_at, correlativo, medio_entrega, entregado_at, enviado_a_info_at, enviado_a_info_por,
     sancionado_rechazo_firma_at, creado_por)
  values (p_id, p_persona, p_causal, p_nivel, p_estado, fn_hoy_lima() - 40, fn_hoy_lima() - 40, '[]'::jsonb,
          '00000000-0000-0000-0000-0000000c1611', now() - interval '20 days', p_corr, p_medio, p_entregado,
          case when p_medio = 'digital' or p_estado = 'firmado' then now() - interval '5 days' end,
          -- quien lo envió: el esquema pide los dos o ninguno (chk_envio_info_completo)
          case when p_medio = 'digital' or p_estado = 'firmado' then '00000000-0000-0000-0000-0000000c1611'::uuid end,
          -- una entrega por Info siempre lleva su respuesta (chk_entrega_digital_con_respuesta)
          case when p_medio = 'digital' then now() - interval '4 days' end,
          '00000000-0000-0000-0000-0000000c1611');
$$;

-- 1 · en papel, hace 2 días (pide leer)  ·  2 · verbal en papel  ·  3 · enviado a su Info, sin recibir
-- 4 · recibido por Info  ·  5 · de hace 13 meses (ya no pesa)  ·  6 · imputación (nivel 4)
select pg_temp.doc('00000000-0000-0000-0000-0000000c16d1', '00000000-0000-0000-0000-0000000c1613', 'LAB/L-1', 'amonestacion', 'entregado', 'fisico',  now() - interval '2 days');
select pg_temp.doc('00000000-0000-0000-0000-0000000c16d2', '00000000-0000-0000-0000-0000000c1613', 'LAB/L-2', 'verbal',       'entregado', 'fisico',  now() - interval '3 days');
select pg_temp.doc('00000000-0000-0000-0000-0000000c16d3', '00000000-0000-0000-0000-0000000c1613', 'LAB/L-3', 'amonestacion', 'firmado',   null,      null);
update expediente_disciplinario set enviado_a_info_at = now() - interval '1 day', enviado_a_info_por = '00000000-0000-0000-0000-0000000c1611' where id = '00000000-0000-0000-0000-0000000c16d3';
select pg_temp.doc('00000000-0000-0000-0000-0000000c16d4', '00000000-0000-0000-0000-0000000c1613', 'LAB/L-4', 'amonestacion', 'entregado', 'digital', now() - interval '4 days');
select pg_temp.doc('00000000-0000-0000-0000-0000000c16d5', '00000000-0000-0000-0000-0000000c1613', 'LAB/L-5', 'amonestacion', 'entregado', 'fisico',  now() - interval '13 months');
select pg_temp.doc('00000000-0000-0000-0000-0000000c16d6', '00000000-0000-0000-0000-0000000c1613', 'LAB/L-6', 'imputacion',   'entregado', 'fisico',  now() - interval '6 days');
-- Los que NO deben aparecer: un borrador, uno anulado y el de otra persona.
insert into expediente_disciplinario (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, creado_por) values
  ('00000000-0000-0000-0000-0000000c16d7', '00000000-0000-0000-0000-0000000c1613', 'tardanza', 'amonestacion', 'borrador', fn_hoy_lima() - 9, fn_hoy_lima() - 9, '[]', '00000000-0000-0000-0000-0000000c1611');
select pg_temp.doc('00000000-0000-0000-0000-0000000c16d8', '00000000-0000-0000-0000-0000000c1613', 'LAB/L-8', 'amonestacion', 'anulado', 'fisico', now() - interval '8 days');
select pg_temp.doc('00000000-0000-0000-0000-0000000c16d9', '00000000-0000-0000-0000-0000000c1614', 'LAB/L-9', 'amonestacion', 'entregado', 'fisico', now() - interval '2 days');
-- Uno de conducta, con su falta citada y su relato: la lista debe nombrar la falta y callar el relato.
insert into expediente_disciplinario (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
  falta_rit_version, falta_numeral, falta_literal, conocido_el,
  firmante_id, firmado_at, correlativo, medio_entrega, entregado_at, creado_por) values
  ('00000000-0000-0000-0000-0000000c16da', '00000000-0000-0000-0000-0000000c1615', 'conducta', 'amonestacion', 'entregado',
   fn_hoy_lima() - 9, fn_hoy_lima() - 9, jsonb_build_array(jsonb_build_object('fecha', to_char(fn_hoy_lima() - 9, 'YYYY-MM-DD'), 'relato', 'RELATO-SECRETO-QUE-NO-VA-EN-LA-LISTA para una persona que mire de reojo.')),
   4.0, '53.2', 'h', fn_hoy_lima() - 8,
   '00000000-0000-0000-0000-0000000c1611', now() - interval '5 days', 'LAB/L-10', 'fisico', now() - interval '2 days',
   '00000000-0000-0000-0000-0000000c1611');
-- Y uno que la persona ya firmó digitalmente sobre su copia en papel: firmar es un acto con su propia fecha.
select pg_temp.doc('00000000-0000-0000-0000-0000000c16db', '00000000-0000-0000-0000-0000000c1615', 'LAB/L-11', 'amonestacion', 'entregado', 'fisico', now() - interval '3 days');
update expediente_disciplinario set firma_sancionado = 'data:image/png;base64,AAAA', firma_sancionado_confirmada_at = now() - interval '2 days'
 where id = '00000000-0000-0000-0000-0000000c16db';

-- ── LA LISTA DE LA PERSONA ──────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c16a3');   -- PersonaA
create temp table _l as select jsonb_array_elements((fn_mi_disciplina())->'documentos') as d;

select is((select count(*)::int from _l), 6,
  'LISTA · seis documentos: ni el borrador, ni el anulado, ni el de otra persona');
select is((select count(*)::int from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d9'), 0,
  'LISTA · el documento de otra persona no aparece');
select is((select d->>'estado' from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d3'), 'por_recibir',
  'LISTA · lo enviado a su Info y sin recibir sale «por recibir»');
select is((select d->>'estado' from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d1'), 'entregado',
  'LISTA · lo entregado, «entregado»');
select is((select (d->>'requiere_lectura')::boolean from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d1'), true,
  'LECTURA · lo entregado en papel pide «Lo leí»');
select is((select (d->>'requiere_lectura')::boolean from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d2'), true,
  'LECTURA · también el acta de una llamada verbal');
select is((select (d->>'requiere_lectura')::boolean from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d4'), false,
  'LECTURA · lo recibido por Info NO la pide: recibir ya es la constancia');
select is((select (d->>'requiere_lectura')::boolean from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d5'), false,
  'LECTURA · lo de hace trece meses ya no pesa: no se le pide leer');
select is((select (d->>'requiere_lectura')::boolean from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d6'), false,
  'LECTURA · una imputación (nivel 4) se entrega en físico y no se abre en pantalla');
select is((select (d->>'cancelado')::boolean from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d5'), true,
  'VIGENCIA · cumplidos los doce meses, «ya no pesa» (56.7)');
select is((select (d->>'cancelado')::boolean from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d1'), false,
  'VIGENCIA · lo reciente sigue pesando');
select is((select d->>'vigente_hasta' from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d1'),
  (((select entregado_at from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000c16d1') at time zone 'America/Lima')::date + interval '12 months')::date::text,
  'VIGENCIA · hasta doce meses de calendario después de la entrega, en el día de Lima (56.1)');
select is((select d->'vigente_hasta' from _l where d->>'id' = '00000000-0000-0000-0000-0000000c16d2'), 'null'::jsonb,
  'VIGENCIA · una llamada verbal no es antecedente: no tiene vigencia que mostrar (54.2)');

select pg_temp.como('00000000-0000-0000-0000-0000000c16a5');   -- PersonaC
create temp table _c as select jsonb_array_elements((fn_mi_disciplina())->'documentos') as d;
select is((select d->'falta'->>'rotulo' from _c where d->>'id' = '00000000-0000-0000-0000-0000000c16da'), 'Trato descortés',
  'FALTA · la lista nombra la falta de conducta con su nombre corto');
select ok(position('RELATO-SECRETO' in (fn_mi_disciplina())::text) = 0,
  'RELATO · la lista NO lo trae: se lee al abrir el documento, no de reojo');
select is((select (d->>'requiere_lectura')::boolean from _c where d->>'id' = '00000000-0000-0000-0000-0000000c16db'), false,
  'LECTURA · quien ya firmó su copia no necesita además «Lo leí»: firmar es un acto deliberado');

select pg_temp.como('00000000-0000-0000-0000-0000000c16a2');   -- la líder: no tiene documentos propios
select is((fn_mi_disciplina())->'documentos', '[]'::jsonb,
  'LISTA · quien no tiene documentos recibe una lista vacía, no un error');

-- ── LA CONSTANCIA ───────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c16a3');   -- PersonaA
select throws_like($$ select fn_marcar_memo_leido('00000000-0000-0000-0000-0000000c16d1') $$,
  '%Ábrelo primero%', 'CONSTANCIA · «Lo leí» sin haber abierto nada no se puede dar');

select lives_ok($$ select fn_registrar_apertura_memo('00000000-0000-0000-0000-0000000c16d1') $$,
  'CONSTANCIA · abrir el documento deja registrada la apertura');
create temp table _ap as select abierto_at from lecturas_memo where expediente_id = '00000000-0000-0000-0000-0000000c16d1';
select pg_sleep(0.05);
select lives_ok($$ select fn_registrar_apertura_memo('00000000-0000-0000-0000-0000000c16d1') $$,
  'CONSTANCIA · abrirlo otra vez no falla');
select is((select abierto_at from lecturas_memo where expediente_id = '00000000-0000-0000-0000-0000000c16d1'),
  (select abierto_at from _ap), 'CONSTANCIA · y la PRIMERA apertura es la que cuenta: no se mueve');

select lives_ok($$ select fn_marcar_memo_leido('00000000-0000-0000-0000-0000000c16d1') $$,
  'CONSTANCIA · ya abierto, «Lo leí» se da');
create temp table _le as select leido_at from lecturas_memo where expediente_id = '00000000-0000-0000-0000-0000000c16d1';
select ok((select leido_at >= abierto_at from lecturas_memo where expediente_id = '00000000-0000-0000-0000-0000000c16d1'),
  'CONSTANCIA · la lectura es posterior a la apertura');
select is((fn_marcar_memo_leido('00000000-0000-0000-0000-0000000c16d1')), (select leido_at from _le),
  'CONSTANCIA · darla dos veces devuelve la misma hora: el doble clic no la mueve');

select throws_like($$ update lecturas_memo set leido_at = null where expediente_id = '00000000-0000-0000-0000-0000000c16d1' $$,
  '%ya está dada%', 'INALTERABLE · una constancia dada no se edita');
select throws_like($$ delete from lecturas_memo where expediente_id = '00000000-0000-0000-0000-0000000c16d1' $$,
  '%no se borra%', 'INALTERABLE · ni se borra');
select throws_ok($$ insert into lecturas_memo (expediente_id, abierto_at, leido_at)
                    values ('00000000-0000-0000-0000-0000000c16d2', now(), now() - interval '1 hour') $$,
  '23514', null, 'ESQUEMA · una lectura anterior a la apertura no puede existir');

-- Lo que no admite constancia
select throws_like($$ select fn_marcar_memo_leido('00000000-0000-0000-0000-0000000c16d4') $$,
  '%ya es tu constancia%', 'NO APLICA · lo recibido por Info: ese clic ya es la constancia');
select throws_like($$ select fn_marcar_memo_leido('00000000-0000-0000-0000-0000000c16d3') $$,
  '%Todavía no te lo entregaron%', 'NO APLICA · lo enviado y sin recibir: primero se recibe');
select throws_like($$ select fn_marcar_memo_leido('00000000-0000-0000-0000-0000000c16d6') $$,
  '%físico o por vía notarial%', 'NO APLICA · la imputación no se lee en pantalla');
select lives_ok($$ select fn_registrar_apertura_memo('00000000-0000-0000-0000-0000000c16d7') $$,
  'NO APLICA · abrir un borrador no falla: la pantalla la llama siempre');
select is((select count(*)::int from lecturas_memo where expediente_id = '00000000-0000-0000-0000-0000000c16d7'), 0,
  'NO APLICA · y no deja constancia de algo que no se le entregó');

-- ── DE QUIÉN ES ─────────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c16a4');   -- PersonaB, sobre el documento de A
select throws_like($$ select fn_registrar_apertura_memo('00000000-0000-0000-0000-0000000c16d1') $$,
  '%No se encontró ese documento%', 'AJENO · nadie abre el documento de otra persona');
select throws_like($$ select fn_marcar_memo_leido('00000000-0000-0000-0000-0000000c16d1') $$,
  '%No se encontró ese documento%', 'AJENO · ni deja constancia por ella');

-- ── QUIÉN VE LAS CONSTANCIAS ────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c16a3');
set local role authenticated;
select is((select count(*)::int from lecturas_memo), 1, 'RLS · la persona ve su propia constancia');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000c16a4');
set local role authenticated;
select is((select count(*)::int from lecturas_memo), 0, 'RLS · otra persona no ve la de ella');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000c16a2');
set local role authenticated;
select is((select count(*)::int from lecturas_memo), 1, 'RLS · la líder ve la de las integrantes de su sede: sabe a quién recordarle');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000c16a1');
set local role authenticated;
select is((select count(*)::int from lecturas_memo), 1, 'RLS · y DO y Gerencia ven todas');
reset role;

select * from finish();
rollback;
