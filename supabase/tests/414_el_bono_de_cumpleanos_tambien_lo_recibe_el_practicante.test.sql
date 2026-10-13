-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 414_el_bono_de_cumpleanos_tambien_lo_recibe_el_practicante.test.sql — 0519
-- ============================================================================
-- Lo que defiende:
--
--   1. UNA SOLA PREGUNTA. `fn_persona_le_corresponde_bono` dice sí al de planilla
--      y al practicante, y no al locador (RxH) ni a quien no existe.
--   2. TRES PUERTAS, UNA RESPUESTA. El caso de Daniel Ruiz (2026-10-13): el
--      tablero decía «este_mes», `fn_mi_bono_cumpleanos` decía «no_aplica» y
--      el registro en papel lo rechazaba. Ahora las tres coinciden.
--   3. EL PRACTICANTE PIDE Y NUNCA VA A LA BOLETA. Firma, queda «pedido» por
--      transferencia, no se escribe NADA en la planilla, DO lo ve por
--      transferir y lo confirma.
--   4. LA PLANILLA SIGUE IGUAL. El de planilla, en las mismas condiciones, sí
--      va a su boleta (CONTROL: sin esto, el «no hay línea» del practicante
--      podría ser un periodo mal puesto).
--   5. EL LOCADOR SIGUE FUERA. No ve el bono, no puede pedirlo y DO no le
--      puede registrar una constancia.
--   6. EL PAPEL TAMBIÉN. DO registra la constancia en papel de un practicante.
--
-- QUÉ NO SE PRUEBA AQUÍ. Lo que `fn_planilla_calcular` haría con un bono de
-- practicante en boleta: no se prueba porque NO SE HACE — ese camino se cerró a
-- propósito (ver el encabezado de la 0519).
--
-- Supone una base sin periodos de planilla (la de CI, construida desde cero):
-- por eso empieza borrándolos. En una base de desarrollo con periodos reales,
-- corre siempre el control sin la migración antes de creer un rojo.
-- ============================================================================
begin;
select plan(27);

delete from periodo_grupo_pago;
delete from periodos_planilla;

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000414000', 'ZZ414', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000414001', 'Prueba', 'Practicante',
   '00000000-0000-0000-0000-000000414000', 'integrante', 'test-hash', 'practicante',
   '00000000-0000-0000-0000-000000414011', '2020-01-01'),
  ('00000000-0000-0000-0000-000000414002', 'Prueba', 'EnPlanilla',
   '00000000-0000-0000-0000-000000414000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000414012', '2020-01-01'),
  ('00000000-0000-0000-0000-000000414003', 'Prueba', 'Locador',
   '00000000-0000-0000-0000-000000414000', 'integrante', 'test-hash', 'rxh',
   '00000000-0000-0000-0000-000000414013', '2020-01-01'),
  ('00000000-0000-0000-0000-000000414005', 'Prueba', 'DoUno',
   '00000000-0000-0000-0000-000000414000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000414015', '2020-01-01'),
  ('00000000-0000-0000-0000-000000414006', 'Prueba', 'DoDos',
   '00000000-0000-0000-0000-000000414000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000414016', '2020-01-01'),
  ('00000000-0000-0000-0000-000000414007', 'Prueba', 'PracticanteEnPapel',
   '00000000-0000-0000-0000-000000414000', 'integrante', 'test-hash', 'practicante',
   '00000000-0000-0000-0000-000000414017', '2020-01-01');
set session_replication_role = origin;

-- Cumpleaños este mes para quienes piden o reciben.
insert into datos_personales (persona_id, fecha_nacimiento)
select id, make_date(1995, extract(month from fn_hoy_lima())::int, 10)
  from personas
 where id in ('00000000-0000-0000-0000-000000414001', '00000000-0000-0000-0000-000000414002',
              '00000000-0000-0000-0000-000000414003', '00000000-0000-0000-0000-000000414007');

insert into firmas_escaneadas (persona_id, imagen, tipo)
select id, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen'
  from personas where id::text like '00000000-0000-0000-0000-00000041400%';

-- Un periodo abierto: es la condición en que la 0479 SÍ mete el bono a la boleta.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000414a1', fn_hoy_lima() - 10, fn_hoy_lima() + 20, 'abierto');

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


-- ── 1 · UNA SOLA PREGUNTA ────────────────────────────────────────────────
select is(fn_persona_le_corresponde_bono('00000000-0000-0000-0000-000000414002'), true,
  'PREGUNTA · el de planilla: sí');
select is(fn_persona_le_corresponde_bono('00000000-0000-0000-0000-000000414001'), true,
  'PREGUNTA · el practicante: sí');
select is(fn_persona_le_corresponde_bono('00000000-0000-0000-0000-000000414003'), false,
  'PREGUNTA · el locador (RxH): no');
select is(fn_persona_le_corresponde_bono('00000000-0000-0000-0000-000000414999'), false,
  'PREGUNTA · quien no existe: no, y no un null que pase como autorizado');


-- ── 2 · TRES PUERTAS, UNA RESPUESTA (el caso de Daniel Ruiz) ─────────────
select pg_temp.como('00000000-0000-0000-0000-000000414011');
select is((select bono_estado from fn_documentos_tablero(true)), 'este_mes',
  'PUERTA 1 · el tablero lo da por «este_mes» (ya lo hacía desde la 0424)');
select is((select estado from fn_mi_bono_cumpleanos()), 'este_mes',
  'PUERTA 2 · y ahora su pantalla dice lo mismo, no «no_aplica»');
select is(
  (select count(*) from fn_documentos_tablero(true) where bono_estado = 'este_mes'),
  1::bigint,
  'PUERTA 2 · coinciden: una fila, un estado');


-- ── 3 · EL PRACTICANTE PIDE Y NUNCA VA A LA BOLETA ───────────────────────
select is(pg_temp.pudo_pedir(), true, 'PEDIDO · el practicante firma su constancia');
select is((select estado from fn_mi_bono_cumpleanos()), 'pedido',
  'ESTADO · queda «pedido»: lo transfiere DO');
select is((select via from fn_mi_bono_cumpleanos()), 'transferencia',
  'ESTADO · y la vía es la transferencia, no la boleta');
select is(
  (select movimiento_id from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000414001' and tipo = 'bono'),
  null::uuid,
  'BOLETA · la constancia no queda atada a ninguna línea');
select is(
  (select count(*) from movimientos_planilla
    where persona_id = '00000000-0000-0000-0000-000000414001'),
  0::bigint,
  'BOLETA · y no se escribió NADA en la planilla, con un periodo abierto de por medio');

select pg_temp.como('00000000-0000-0000-0000-000000414015');
select is(
  (select count(*) from fn_bonos_por_transferir()
    where persona_id = '00000000-0000-0000-0000-000000414001'),
  1::bigint,
  'DO · lo ve en «por transferir»');
select lives_ok(
  $$ select fn_confirmar_entrega_bono(
       (select id from documentos_firmados
         where persona_id = '00000000-0000-0000-0000-000000414001' and tipo = 'bono'),
       fn_hoy_lima()) $$,
  'DO · confirma «ya lo transferí»');

select pg_temp.como('00000000-0000-0000-0000-000000414011');
select is((select estado || ' ' || via from fn_mi_bono_cumpleanos()), 'entregado transferencia',
  'ENTREGADO · el practicante lo ve entregado, por transferencia');


-- ── 4 · LA PLANILLA SIGUE IGUAL (control) ────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000414012');
select is(pg_temp.pudo_pedir(), true, 'CONTROL · el de planilla firma, con el MISMO periodo abierto');
select is((select estado || ' ' || via from fn_mi_bono_cumpleanos()), 'en_boleta boleta',
  'CONTROL · y él SÍ va a su boleta: la 0479 sigue intacta');
select is(
  (select count(*) from movimientos_planilla
    where persona_id = '00000000-0000-0000-0000-000000414002' and tipo = 'bono'),
  1::bigint,
  'CONTROL · con su línea en el periodo: por eso la ausencia de línea del practicante significa algo');


-- ── 5 · EL LOCADOR SIGUE FUERA ───────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000414013');
select is((select estado from fn_mi_bono_cumpleanos()), 'no_aplica',
  'LOCADOR · no ve el bono');
select is(pg_temp.pudo_pedir(), false,
  'LOCADOR · y no puede pedirlo');

select pg_temp.como('00000000-0000-0000-0000-000000414015');
select throws_ok(
  $$ select fn_documento_registrar('bono', fn_hoy_lima(),
       p_persona_id => '00000000-0000-0000-0000-000000414003',
       p_monto_declarado => 180, p_anio => extract(year from fn_hoy_lima())::int) $$,
  null, 'Esa persona no está en planilla ni es practicante: no le corresponde ese documento.',
  'LOCADOR · DO no le puede registrar una constancia en papel');


-- ── 6 · EL PAPEL TAMBIÉN ─────────────────────────────────────────────────
select lives_ok(
  $$ select fn_documento_registrar('bono', fn_hoy_lima(),
       p_persona_id => '00000000-0000-0000-0000-000000414007',
       p_monto_declarado => 180, p_anio => extract(year from fn_hoy_lima())::int) $$,
  'PAPEL · DO registra la constancia en papel de un practicante');
select is(
  (select count(*) from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000414007' and tipo = 'bono' and anulado_at is null),
  1::bigint,
  'PAPEL · queda una constancia vigente');

select pg_temp.como('00000000-0000-0000-0000-000000414017');
select is((select estado from fn_mi_bono_cumpleanos()), 'entregado',
  'PAPEL · y el practicante ve su bono entregado');
select is((select via from fn_mi_bono_cumpleanos()), 'papel',
  'PAPEL · por el papel');


-- ── 7 · LA FIRMA QUEDÓ AUDITADA ──────────────────────────────────────────
select is(
  (select count(*) from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000414001'
      and campo_modificado = 'documento_firmado'),
  1::bigint,
  'AUDITORÍA · la firma del practicante deja su rastro');
select is(
  (select count(*) from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000414001'
      and campo_modificado = 'bono_en_boleta'),
  0::bigint,
  'AUDITORÍA · y NO deja rastro de «bono en boleta», porque no entró a ninguna');

select * from finish();
rollback;
