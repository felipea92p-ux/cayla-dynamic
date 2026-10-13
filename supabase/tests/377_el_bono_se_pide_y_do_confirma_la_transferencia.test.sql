-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 377_el_bono_se_pide_y_do_confirma_la_transferencia.test.sql — 0478
-- ============================================================================
-- Lo que defiende, en el orden del recorrido real:
--
--   1. QUÉ LE TOCA. `fn_mi_bono_cumpleanos` contesta igual que el tablero (desde
--      la 0519 también para la practicante: en planilla o practicante).
--   2. SOLO SE PIDE CUANDO TOCA. Sin fecha o antes de su mes: no pasa. En su
--      mes: pasa, y no dos veces. (La practicante pedía «no» hasta la 0519; el
--      locador sigue fuera, y eso lo defiende la prueba 414.)
--   3. EL PEDIDO LLEGA A DO Y NO SE APAGA SOLO. Firmar no lo borra de
--      `fn_bonos_por_transferir`; solo la confirmación lo saca.
--   4. LA CONFIRMACIÓN NO SE PUEDE FALSEAR. Sin fecha, futura, de otro año,
--      la propia, dos veces, o sobre un cargo en papel: no pasa.
--   5. EL ESTADO IMPOSIBLE NO EXISTE. Una entrega confirmada en algo que no es
--      un bono pedido desde el sistema la rechaza la base, no una pantalla.
-- ============================================================================
begin;
select plan(28);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000377000', 'ZZ377', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000377001', 'Prueba', 'CumpleEsteMes',
   '00000000-0000-0000-0000-000000377000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000377011', '2020-01-01'),
  ('00000000-0000-0000-0000-000000377002', 'Prueba', 'SinFecha',
   '00000000-0000-0000-0000-000000377000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000377012', '2020-01-01'),
  ('00000000-0000-0000-0000-000000377003', 'Prueba', 'Practicante',
   '00000000-0000-0000-0000-000000377000', 'integrante', 'test-hash', 'practicante',
   '00000000-0000-0000-0000-000000377013', '2020-01-01'),
  ('00000000-0000-0000-0000-000000377004', 'Prueba', 'OtroMes',
   '00000000-0000-0000-0000-000000377000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000377014', '2020-01-01'),
  ('00000000-0000-0000-0000-000000377005', 'Prueba', 'AdminCumpleanera',
   '00000000-0000-0000-0000-000000377000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000377015', '2020-01-01'),
  ('00000000-0000-0000-0000-000000377006', 'Prueba', 'OtraAdmin',
   '00000000-0000-0000-0000-000000377000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000377016', '2020-01-01'),
  ('00000000-0000-0000-0000-000000377007', 'Prueba', 'EnPapel',
   '00000000-0000-0000-0000-000000377000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000377017', '2020-01-01');
set session_replication_role = origin;

-- Cumpleaños: este mes para casi todas; «OtroMes» el siguiente (o noviembre si
-- hoy es diciembre, para que la prueba no dependa del día en que corre).
insert into datos_personales (persona_id, fecha_nacimiento)
select id, make_date(1995, extract(month from fn_hoy_lima())::int, 10)
  from personas
 where id in ('00000000-0000-0000-0000-000000377001', '00000000-0000-0000-0000-000000377003',
              '00000000-0000-0000-0000-000000377005', '00000000-0000-0000-0000-000000377006',
              '00000000-0000-0000-0000-000000377007');
insert into datos_personales (persona_id, fecha_nacimiento)
values ('00000000-0000-0000-0000-000000377004',
        make_date(1995, case when extract(month from fn_hoy_lima()) = 12 then 11
                             else extract(month from fn_hoy_lima())::int + 1 end, 10));

insert into firmas_escaneadas (persona_id, imagen, tipo)
select id, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen'
  from personas where id::text like '00000000-0000-0000-0000-00000037700%';

-- Un intento de pedir que no aborta la prueba: devuelve si pudo o no.
create function pg_temp.pudo_pedir() returns boolean language plpgsql as $$
begin
  perform fn_confirmar_mi_bono_cumpleanos();
  return true;
exception when others then
  return false;
end $$;

create function pg_temp.como(p_sub text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_sub, true);
end $$;


-- ── 1 · QUÉ LE TOCA ──────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000377011');
select is((select estado from fn_mi_bono_cumpleanos()), 'este_mes',
  'ESTADO · cumple este mes y está en planilla: puede pedirlo');
select ok((select monto from fn_mi_bono_cumpleanos()) > 0,
  'MONTO · se ve ANTES de pedir, aunque parametros_laborales solo lo lea DO');

select pg_temp.como('00000000-0000-0000-0000-000000377012');
select is((select estado from fn_mi_bono_cumpleanos()), 'sin_fecha',
  'ESTADO · sin fecha de nacimiento en la ficha');

select pg_temp.como('00000000-0000-0000-0000-000000377013');
select is((select bono_estado from fn_documentos_tablero(true)), 'este_mes',
  'CONTROL · el tablero (0424) sí le calcula el bono a la practicante…');
select is((select estado from fn_mi_bono_cumpleanos()), 'este_mes',
  '…y desde la 0519 fn_mi_bono_cumpleanos también se lo ofrece: el bono es de planilla o practicante');

select pg_temp.como('00000000-0000-0000-0000-000000377014');
select is((select estado from fn_mi_bono_cumpleanos()),
  case when extract(month from fn_hoy_lima()) = 12 then 'vencido' else 'proximo' end,
  'ESTADO · el cumpleaños de otro mes no se confunde con este');


-- ── 2 · SOLO SE PIDE CUANDO TOCA ─────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000377012');
select is(pg_temp.pudo_pedir(), false, 'PUERTA · sin fecha de nacimiento no se pide');

select pg_temp.como('00000000-0000-0000-0000-000000377013');
select is(pg_temp.pudo_pedir(), true, 'PUERTA · la practicante sí lo pide: el tablero y su pantalla coinciden (0519)');

select pg_temp.como('00000000-0000-0000-0000-000000377014');
select is(pg_temp.pudo_pedir(), extract(month from fn_hoy_lima()) = 12,
  'PUERTA · antes de su mes no se pide (si ya pasó, sí)');

select pg_temp.como('00000000-0000-0000-0000-000000377011');
select is(pg_temp.pudo_pedir(), true, 'PEDIDO · en su mes, con firma guardada, se pide');
select is((select estado from fn_mi_bono_cumpleanos()), 'pedido',
  'ESTADO · recién pedido: queda esperando a DO, no «entregado»');
select is((select pedido_el from fn_mi_bono_cumpleanos()), fn_hoy_lima(),
  'ESTADO · con la fecha en que lo pidió');
select is(pg_temp.pudo_pedir(), false, 'PEDIDO · no se pide dos veces');


-- ── 3 · EL PEDIDO LLEGA A DO Y NO SE APAGA SOLO ──────────────────────────
select throws_ok($$ select * from fn_bonos_por_transferir() $$, null, null,
  'DO · una integrante no ve los bonos del equipo');

select pg_temp.como('00000000-0000-0000-0000-000000377016');
select is(
  (select count(*) from fn_bonos_por_transferir() where persona_id = '00000000-0000-0000-0000-000000377001'),
  1::bigint,
  'DO · la firma NO borra el aviso: el pedido aparece por transferir');
select is(
  (select bono_estado from fn_documentos_tablero() where persona_id = '00000000-0000-0000-0000-000000377001'),
  'ok',
  'CONTROL · y es justo lo que hacía falta: el tablero ya lo da por firmado');


-- ── 4 · LA CONFIRMACIÓN NO SE PUEDE FALSEAR ──────────────────────────────
select throws_ok(
  $$ select fn_confirmar_entrega_bono(
       (select documento_id from fn_bonos_por_transferir() where persona_id = '00000000-0000-0000-0000-000000377001'),
       null) $$,
  null, null, 'CONFIRMAR · sin fecha no');
select throws_ok(
  $$ select fn_confirmar_entrega_bono(
       (select documento_id from fn_bonos_por_transferir() where persona_id = '00000000-0000-0000-0000-000000377001'),
       fn_hoy_lima() + 1) $$,
  null, null, 'CONFIRMAR · con fecha futura no');
select throws_ok(
  $$ select fn_confirmar_entrega_bono(
       (select documento_id from fn_bonos_por_transferir() where persona_id = '00000000-0000-0000-0000-000000377001'),
       make_date(extract(year from fn_hoy_lima())::int - 1, 12, 31)) $$,
  null, null, 'CONFIRMAR · con fecha de un año anterior al bono no');

-- La admin que cumple años pide el suyo…
select pg_temp.como('00000000-0000-0000-0000-000000377015');
select is(pg_temp.pudo_pedir(), true, 'PEDIDO · alguien de DO también pide el suyo');
-- …y no puede confirmarse a sí misma.
select throws_ok(
  $$ select fn_confirmar_entrega_bono(
       (select documento_id from fn_bonos_por_transferir() where persona_id = '00000000-0000-0000-0000-000000377005'),
       fn_hoy_lima()) $$,
  null, null, 'CONFIRMAR · nadie confirma la transferencia de su propio bono');

select pg_temp.como('00000000-0000-0000-0000-000000377016');
select lives_ok(
  $$ select fn_confirmar_entrega_bono(
       (select documento_id from fn_bonos_por_transferir() where persona_id = '00000000-0000-0000-0000-000000377001'),
       fn_hoy_lima()) $$,
  'CONFIRMAR · otra persona de DO, con la fecha de hoy');
select is(
  (select count(*) from fn_bonos_por_transferir() where persona_id = '00000000-0000-0000-0000-000000377001'),
  0::bigint,
  'DO · confirmada, sale de la lista');
select throws_ok(
  $$ select fn_confirmar_entrega_bono(
       (select id from documentos_firmados where persona_id = '00000000-0000-0000-0000-000000377001' and tipo = 'bono'),
       fn_hoy_lima()) $$,
  null, null, 'CONFIRMAR · no se confirma dos veces');

select pg_temp.como('00000000-0000-0000-0000-000000377011');
select is((select estado || ' ' || entregado_el::text from fn_mi_bono_cumpleanos()),
  'entregado ' || fn_hoy_lima()::text,
  'ESTADO · ella ve «entregado», con la fecha que confirmó DO');

-- El cargo en papel: DO lo registra por el camino de siempre.
select pg_temp.como('00000000-0000-0000-0000-000000377016');
select fn_documento_registrar('bono', fn_hoy_lima() - 1, '00000000-0000-0000-0000-000000377007',
                              null, 180.00, extract(year from fn_hoy_lima())::int,
                              false, null, 'documentos/bono-en-papel.pdf');
select throws_ok(
  $$ select fn_confirmar_entrega_bono(
       (select id from documentos_firmados where persona_id = '00000000-0000-0000-0000-000000377007' and tipo = 'bono'),
       fn_hoy_lima()) $$,
  null, null, 'CONFIRMAR · un cargo en papel no espera confirmación');

select pg_temp.como('00000000-0000-0000-0000-000000377017');
select is((select estado || ' ' || entregado_el::text from fn_mi_bono_cumpleanos()),
  'entregado ' || (fn_hoy_lima() - 1)::text,
  'ESTADO · en papel, «entregado» con la fecha escrita en el cargo');


-- ── 5 · EL ESTADO IMPOSIBLE NO EXISTE ────────────────────────────────────
select throws_ok(
  $$ update documentos_firmados
        set entrega_confirmada_el = fn_hoy_lima(),
            entrega_confirmada_por = '00000000-0000-0000-0000-000000377016',
            entrega_confirmada_at = now()
      where persona_id = '00000000-0000-0000-0000-000000377007' and tipo = 'bono' $$,
  '23514', null,
  'CONSTRAINT · la base rechaza una entrega confirmada sobre un cargo en papel');

select finish();
rollback;
