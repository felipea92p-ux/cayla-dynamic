-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 384_el_memo_se_entrega_por_info.test.sql
-- ============================================================================
-- La 0486 agrega un segundo camino para entregar un memo: quien lo emite lo
-- envía a la Info de la persona, y ella lo RECIBE con un acto explícito —
-- firmándolo o recibiéndolo sin firmar—. Ese acto es la entrega.
--
-- Lo que fija esta prueba, en orden de importancia:
--   · Enviar NO entrega: el documento sigue firmado y no agrava. Solo recibir
--     entrega, y solo lo puede hacer la propia persona.
--   · «Digital» no se puede escribir en nombre de otro: ni por
--     `fn_expediente_entregar`, ni por un UPDATE directo sin respuesta suya.
--   · Recibir y responder son una sola operación: no hay entrega sin respuesta.
--   · Ella lee su documento con QUIÉN LO FIRMÓ ya nombrado (la RLS le esconde
--     la ficha de su líder), y jamás uno sin enviar ni de otra persona.
--   · El envío se puede retirar mientras no se reciba, y ese envío no rompe
--     ni la anulación ni la entrega en físico.
--   · Los estados imposibles lo son por esquema, no por validación.
-- ============================================================================
begin;
select plan(49);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000e8601', 'ZZINF', 'Sede de laboratorio', true);

-- Con cuenta (auth_user_id): quien emite, la sancionada y otra persona cualquiera.
-- `session_replication_role = replica` para no chocar con la FK a auth.users,
-- igual que en la 238.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000e8610', 'Emisora',  'Lab', '00000000-0000-0000-0000-0000000e8601', 'admin',      'x', '00000000-0000-0000-0000-0000000e86a0', '2020-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-0000000e8611', 'Sancionada', 'Lab', '00000000-0000-0000-0000-0000000e8601', 'integrante', 'x', '00000000-0000-0000-0000-0000000e86a1', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-0000000e8612', 'Otra',     'Lab', '00000000-0000-0000-0000-0000000e8601', 'integrante', 'x', '00000000-0000-0000-0000-0000000e86a2', '2024-01-01', 'activo', 'planilla');
set session_replication_role = origin;

-- Sin cuenta, y una que ya cesó.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000e8613', 'SinCuenta', 'Lab', '00000000-0000-0000-0000-0000000e8601', 'x', '2024-01-01', 'activo', 'planilla');
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, fecha_cese, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000e8614', 'Cesada', 'Lab', '00000000-0000-0000-0000-0000000e8601', 'x', '2024-01-01', 'inactivo', fn_hoy_lima() - 3, 'planilla');

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true);
$$;

-- Un documento firmado, para cualquier persona y nivel.
create function pg_temp.firmada(p_persona uuid, p_corr text, p_nivel text default 'amonestacion') returns uuid language sql as $$
  insert into expediente_disciplinario
    (persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
     firmante_id, firmado_at, correlativo, creado_por)
  values (p_persona, 'tardanza', p_nivel, 'firmado', fn_hoy_lima() - 5, fn_hoy_lima() - 5, '[]'::jsonb,
          '00000000-0000-0000-0000-0000000e8610', now(), p_corr,
          '00000000-0000-0000-0000-0000000e8610')
  returning id;
$$;

select pg_temp.como('00000000-0000-0000-0000-0000000e86a0');   -- quien emite

create temp table _d  as select pg_temp.firmada('00000000-0000-0000-0000-0000000e8611', 'INF/001') as id;
create temp table _s  as select pg_temp.firmada('00000000-0000-0000-0000-0000000e8611', 'INF/002') as id;  -- sin enviar
create temp table _d3 as select pg_temp.firmada('00000000-0000-0000-0000-0000000e8611', 'INF/003') as id;  -- se retira
create temp table _d4 as select pg_temp.firmada('00000000-0000-0000-0000-0000000e8611', 'INF/004') as id;  -- con firma

-- ── ENVIAR ──────────────────────────────────────────────────────────────────
select lives_ok(format($$ select fn_expediente_enviar_a_info(%L) $$, (select id from _d)),
  'Quien emite envía a Info un memo firmado');

select is((select enviado_a_info_por from expediente_disciplinario where id = (select id from _d)),
  '00000000-0000-0000-0000-0000000e8610'::uuid,
  'Consta quién lo envió');

select is((select estado from expediente_disciplinario where id = (select id from _d)), 'firmado',
  'ENVIAR NO ENTREGA: el documento sigue firmado');

-- ART. 56.2: mientras no se entrega, no agrava. Enviarlo no cambia eso.
select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-0000000e8611')),
  'amonestacion',
  '56.2 · enviado a Info pero sin recibir, todavía no agrava');

select throws_like(format($$ select fn_expediente_enviar_a_info(%L) $$, (select id from _d)),
  '%ya está enviado%', 'No se envía dos veces');

select pg_temp.como('00000000-0000-0000-0000-0000000e86a1');   -- la sancionada
select throws_like(format($$ select fn_expediente_enviar_a_info(%L) $$, (select id from _s)),
  '%Sin permiso%', 'La propia persona no se envía su documento');
select pg_temp.como('00000000-0000-0000-0000-0000000e86a0');

-- Lo que no se puede enviar
create temp table _b as
  select fn_expediente_crear_borrador(
            '00000000-0000-0000-0000-0000000e8611', 'tardanza', 'amonestacion',
            '[]'::jsonb, fn_hoy_lima() - 20, fn_hoy_lima() - 20) as id;
select throws_like(format($$ select fn_expediente_enviar_a_info(%L) $$, (select id from _b)),
  '%firmado%', 'Un borrador no se envía');

create temp table _n4 as select pg_temp.firmada('00000000-0000-0000-0000-0000000e8611', 'INF/N4', 'imputacion') as id;
select throws_like(format($$ select fn_expediente_enviar_a_info(%L) $$, (select id from _n4)),
  '%no admite entrega digital%', 'Nivel 4 no se entrega por Info: se firma en físico o vía notarial');

create temp table _sc as select pg_temp.firmada('00000000-0000-0000-0000-0000000e8613', 'INF/SC') as id;
select throws_like(format($$ select fn_expediente_enviar_a_info(%L) $$, (select id from _sc)),
  '%todavía no tiene cuenta%', 'Sin cuenta no hay Info: no se envía a una pantalla que no puede abrir');

create temp table _ce as select pg_temp.firmada('00000000-0000-0000-0000-0000000e8614', 'INF/CE') as id;
select throws_like(format($$ select fn_expediente_enviar_a_info(%L) $$, (select id from _ce)),
  '%ya no está activa%', 'A quien ya cesó tampoco');

-- ── LO QUE ELLA VE ──────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000e86a1');
select is((select count(*)::int from fn_mis_memos_por_recibir()), 1,
  'Ella tiene UN documento por recibir: el enviado, no el firmado sin enviar');

select pg_temp.como('00000000-0000-0000-0000-0000000e86a2');   -- otra persona
select is((select count(*)::int from fn_mis_memos_por_recibir()), 0,
  'Otra persona no ve nada por recibir');
select is(fn_mi_memo((select id from _d)), null,
  'Y el documento de otra persona le devuelve null: no se distingue «no existe» de «no es tuyo»');

select pg_temp.como('00000000-0000-0000-0000-0000000e86a1');
select is(fn_mi_memo((select id from _d))->'firmante'->>'nombre', 'Emisora Lab',
  'Ella lee el memo con QUIÉN LO FIRMÓ nombrado, aunque su RLS no le deje ver esa ficha');
select is(fn_mi_memo((select id from _d))->>'estado', 'firmado',
  'Lo puede leer antes de recibirlo: para decidir hace falta leerlo');
select is(fn_mi_memo((select id from _s)), null,
  'Un firmado que nadie envió es invisible para ella');
select is(fn_mi_memo((select id from _b)), null,
  'Un borrador también');
select is(fn_mi_memo((select id from _n4)), null,
  'Y uno de Nivel 4, aunque sea suyo');

-- ── RECIBIR ─────────────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000e86a2');
select throws_like(format($$ select fn_recibir_memo_digital(%L, false) $$, (select id from _d)),
  '%No se encontró ese documento%', 'Otra persona no puede recibir el documento de ella');

select pg_temp.como('00000000-0000-0000-0000-0000000e86a1');
select throws_like(format($$ select fn_recibir_memo_digital(%L, null) $$, (select id from _d)),
  '%Indica si firmas%', 'Sin decir si firma o no, no hay recibo');

select throws_like(format($$ select fn_recibir_memo_digital(%L, true) $$, (select id from _d)),
  '%Todavía no configuraste tu firma%', 'Para firmar hace falta tener firma guardada');
select is((select estado from expediente_disciplinario where id = (select id from _d)), 'firmado',
  'Y el intento fallido no deja el documento a medias');

select throws_like(format($$ select fn_recibir_memo_digital(%L, false) $$, (select id from _s)),
  '%no está disponible%', 'Un firmado que nadie envió no se puede recibir');

select lives_ok(format($$ select fn_recibir_memo_digital(%L, false) $$, (select id from _d)),
  'Ella lo recibe sin firmar');

select is(
  (select estado || '/' || medio_entrega from expediente_disciplinario where id = (select id from _d)),
  'entregado/digital', 'Queda ENTREGADO por medio digital');
select is((select entregado_por from expediente_disciplinario where id = (select id from _d)),
  '00000000-0000-0000-0000-0000000e8610'::uuid,
  'Quien entrega es quien lo envió, no ella (el 55.4 pide saber quién entregó)');
select ok((select sancionado_rechazo_firma_at is not null and firma_sancionado is null
             from expediente_disciplinario where id = (select id from _d)),
  'Recibir sin firmar deja anotado que prefirió no firmarlo, con su fecha');
select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-0000000e8611')),
  'suspension', '56.1 · recibido, AHORA SÍ agrava: la entrega digital produce los mismos efectos');

select throws_like(format($$ select fn_recibir_memo_digital(%L, false) $$, (select id from _d)),
  '%ya quedó recibido%', 'Recibirlo dos veces (dos pestañas) falla la segunda, no lo duplica');

select is((select count(*)::int from fn_mis_memos_por_recibir()), 0,
  'Recibido, sale de «por recibir»…');
select is((select count(*)::int from fn_mis_memos() where id = (select id from _d)), 1,
  '…y entra en «mis memos» (0408), donde se ve como entregado');

-- ── RECIBIR FIRMANDO ────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000e86a0');
select fn_expediente_enviar_a_info((select id from _d4));
insert into firmas_escaneadas (persona_id, imagen)
values ('00000000-0000-0000-0000-0000000e8611', 'data:image/png;base64,iVBORw0KGgo=');

select pg_temp.como('00000000-0000-0000-0000-0000000e86a1');
select lives_ok(format($$ select fn_recibir_memo_digital(%L, true) $$, (select id from _d4)),
  'Con su firma guardada, «Firmar y recibir»');
select ok((select medio_entrega = 'digital' and firma_sancionado is not null
                  and firma_sancionado_confirmada_at is not null and sancionado_rechazo_firma_at is null
             from expediente_disciplinario where id = (select id from _d4)),
  'Queda entregado por Info CON su firma copiada y sin rechazo: firmar y negarse no conviven');

-- ── RETIRAR ─────────────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000e86a0');
select fn_expediente_enviar_a_info((select id from _d3));
select pg_temp.como('00000000-0000-0000-0000-0000000e86a1');
select throws_like(format($$ select fn_expediente_retirar_de_info(%L) $$, (select id from _d3)),
  '%Sin permiso%', 'Ella no puede retirar el envío');
select pg_temp.como('00000000-0000-0000-0000-0000000e86a0');
select lives_ok(format($$ select fn_expediente_retirar_de_info(%L) $$, (select id from _d3)),
  'Quien emite retira el envío mientras ella no lo recibió');
select pg_temp.como('00000000-0000-0000-0000-0000000e86a1');
select throws_like(format($$ select fn_recibir_memo_digital(%L, false) $$, (select id from _d3)),
  '%no está disponible%', 'Retirado, ella ya no puede recibirlo');
select pg_temp.como('00000000-0000-0000-0000-0000000e86a0');
select throws_like(format($$ select fn_expediente_retirar_de_info(%L) $$, (select id from _d)),
  '%ya fue recibido%', 'Uno ya recibido no se retira: se anula');

-- ── NADIE ENTREGA «DIGITAL» EN NOMBRE DE OTRO ───────────────────────────────
select throws_like(format($$ select fn_expediente_entregar(%L, 'digital') $$, (select id from _d3)),
  '%Medio de entrega inválido%', 'fn_expediente_entregar no acepta el medio digital: solo ella lo escribe');

-- ── ESTADOS IMPOSIBLES: los hace imposibles el esquema ──────────────────────
select fn_expediente_enviar_a_info((select id from _d3));
select throws_ok(
  format($$ update expediente_disciplinario set estado = 'entregado', medio_entrega = 'digital', entregado_at = now() where id = %L $$, (select id from _d3)),
  '23514', null,
  'Una entrega digital sin respuesta de la persona no puede existir, ni por UPDATE directo');

select throws_ok(
  format($$ select fn_expediente_reabrir(%L) $$, (select id from _d3)),
  '23514', null,
  'Un documento enviado no vuelve a borrador sin retirar el envío antes');

select throws_ok(
  format($$ update expediente_disciplinario set enviado_a_info_at = now() where id = %L $$, (select id from _n4)),
  '23514', null,
  'Un envío sin quien lo envió no existe (y menos uno de Nivel 4)');

select throws_ok(
  format($$ update expediente_disciplinario set medio_entrega = 'digital', estado = 'entregado', entregado_at = now(),
              sancionado_rechazo_firma_at = now() where id = %L $$, (select id from _s)),
  '23514', null,
  'Una entrega digital sin envío previo no puede existir');

-- ── EL ENVÍO NO ESTORBA A LOS OTROS CAMINOS ─────────────────────────────────
select lives_ok(format($$ select fn_expediente_anular(%L, 'Error de emisión') $$, (select id from _d3)),
  'Un documento enviado se puede anular');
select is((select count(*)::int from fn_mis_memos_por_recibir()), 0,
  'Anulado, deja de aparecer en «por recibir»');

select pg_temp.como('00000000-0000-0000-0000-0000000e86a0');
create temp table _f as select pg_temp.firmada('00000000-0000-0000-0000-0000000e8611', 'INF/005') as id;
select fn_expediente_enviar_a_info((select id from _f));
select lives_ok(format($$ select fn_expediente_entregar(%L, 'fisico') $$, (select id from _f)),
  'Si al final se le entrega el papel, la entrega en físico sigue funcionando sobre un envío pendiente');
select pg_temp.como('00000000-0000-0000-0000-0000000e86a1');
select is((select count(*)::int from fn_mis_memos_por_recibir()), 0,
  'Y ya no le queda nada por recibir: no hay que recibir dos veces lo que ya se entregó');

-- ── QUIÉN PUEDE LLAMARLAS ───────────────────────────────────────────────────
-- Esta prueba corre como superusuario y no vería un `grant` mal puesto. Se
-- pregunta por rol: sin sesión no se ejecuta ninguna; con sesión, las cinco.
select is(
  (select count(*)::int from pg_proc
    where proname in ('fn_expediente_enviar_a_info', 'fn_expediente_retirar_de_info',
                      'fn_mis_memos_por_recibir', 'fn_mi_memo', 'fn_recibir_memo_digital')
      and has_function_privilege('anon', oid, 'execute')),
  0, 'Sin sesión (anon), ninguna de las cinco funciones se puede ejecutar');
select is(
  (select count(*)::int from pg_proc
    where proname in ('fn_expediente_enviar_a_info', 'fn_expediente_retirar_de_info',
                      'fn_mis_memos_por_recibir', 'fn_mi_memo', 'fn_recibir_memo_digital')
      and has_function_privilege('authenticated', oid, 'execute')),
  5, 'Con sesión (authenticated), las cinco');
select is(
  (select count(*)::int from pg_proc
    where proname in ('fn_expediente_enviar_a_info', 'fn_expediente_retirar_de_info',
                      'fn_mis_memos_por_recibir', 'fn_mi_memo', 'fn_recibir_memo_digital')
      and prosecdef),
  5, 'Las cinco son SECURITY DEFINER: el filtro por estado lo impone el servidor, no el cliente');

select * from finish();
rollback;
