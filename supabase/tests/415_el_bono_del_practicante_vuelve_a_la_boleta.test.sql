-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 415_el_bono_del_practicante_vuelve_a_la_boleta.test.sql — 0521
-- ============================================================================
-- Lo que defiende, en el orden del recorrido real:
--
--   1. LA BOLETA DE UN PRACTICANTE CON BONO. Con las mismas condiciones que un
--      integrante de planilla (mismo sueldo, mismas jornadas, mismo periodo), el
--      bono sube el total EXACTAMENTE su monto y no mueve nada más: ni EsSalud,
--      ni AFP, ni la RETENCIÓN de 4.ª (que sigue en 0 porque su guarda es `rxh`).
--      Es la medición que la 0520 temía y no había hecho bien: `retencion_4ta_base`
--      sube —es un campo informativo, y sube igual en el de planilla— pero lo que
--      se descuenta no cambia.
--   2. LA REPARACIÓN. `fn_bono_pasar_pedidos_de_practicantes_a_boleta` pasa a la
--      boleta lo que la 0520 dejó «por transferir» (el caso de Daniel Ruiz,
--      2026-10-13) y SOLO eso: no toca a quien ya se transfirió (sería pagarlo
--      dos veces), no toca a un integrante de planilla (su respaldo es legítimo),
--      no escribe en un periodo pagado, y pegarla dos veces no duplica nada.
--   3. NO LA CORRE CUALQUIERA. Es plata: un usuario autenticado no puede llamarla.
--
-- Supone una base sin periodos de planilla (la de CI, construida desde cero):
-- por eso empieza borrándolos.
-- ============================================================================
begin;
select plan(26);

delete from periodo_grupo_pago;
delete from periodos_planilla;

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000415000', 'ZZ415', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id, fecha_ingreso, estado) values
  -- 1 · las dos boletas que se comparan
  ('00000000-0000-0000-0000-000000415001', 'Prueba', 'Practicante',
   '00000000-0000-0000-0000-000000415000', 'integrante', 'x', 'practicante',
   '00000000-0000-0000-0000-000000415011', '2020-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000415002', 'Prueba', 'EnPlanilla',
   '00000000-0000-0000-0000-000000415000', 'integrante', 'x', 'planilla',
   '00000000-0000-0000-0000-000000415012', '2020-01-01', 'activo'),
  -- 2 · los pedidos que la reparación mira
  ('00000000-0000-0000-0000-000000415003', 'Prueba', 'PedidoPracticante',
   '00000000-0000-0000-0000-000000415000', 'integrante', 'x', 'practicante',
   '00000000-0000-0000-0000-000000415013', '2020-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000415004', 'Prueba', 'YaTransferido',
   '00000000-0000-0000-0000-000000415000', 'integrante', 'x', 'practicante',
   '00000000-0000-0000-0000-000000415014', '2020-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000415006', 'Prueba', 'PedidoPlanilla',
   '00000000-0000-0000-0000-000000415000', 'integrante', 'x', 'planilla',
   '00000000-0000-0000-0000-000000415016', '2020-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000415007', 'Prueba', 'PedidoInactivo',
   '00000000-0000-0000-0000-000000415000', 'integrante', 'x', 'practicante',
   '00000000-0000-0000-0000-000000415017', '2020-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000415008', 'Prueba', 'PedidoPeriodoPagado',
   '00000000-0000-0000-0000-000000415000', 'integrante', 'x', 'practicante',
   '00000000-0000-0000-0000-000000415018', '2020-01-01', 'activo'),
  -- DO
  ('00000000-0000-0000-0000-000000415005', 'Prueba', 'Do',
   '00000000-0000-0000-0000-000000415000', 'admin', 'x', 'planilla',
   '00000000-0000-0000-0000-000000415015', '2020-01-01', 'activo');
-- Inactivo y con su fecha de cese a la vez: lo exige `personas_cese_coherente`.
update personas set estado = 'inactivo', fecha_cese = '2026-01-31'
 where id = '00000000-0000-0000-0000-000000415007';
set session_replication_role = origin;

-- Cumpleaños este mes y firma configurada para quienes piden desde el sistema.
insert into datos_personales (persona_id, fecha_nacimiento)
select id, make_date(1995, extract(month from fn_hoy_lima())::int, 10)
  from personas where id in ('00000000-0000-0000-0000-000000415001', '00000000-0000-0000-0000-000000415002');
insert into firmas_escaneadas (persona_id, imagen, tipo)
select id, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen'
  from personas where id::text like '00000000-0000-0000-0000-00000041500%';

-- Mismo sueldo y mismas jornadas para los dos que se comparan.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla', 1800, '2025-01-01' from personas
 where id in ('00000000-0000-0000-0000-000000415001', '00000000-0000-0000-0000-000000415002');
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 8, 'cerrada'
  from personas p, generate_series(fn_hoy_lima() - 10, fn_hoy_lima(), interval '1 day') d
 where p.id in ('00000000-0000-0000-0000-000000415001', '00000000-0000-0000-0000-000000415002')
   and extract(dow from d) <> 0;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000415a1', fn_hoy_lima() - 10, fn_hoy_lima() + 20, 'abierto');

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

-- Un pedido tal como lo dejó la 0520: firmado desde el sistema, sin línea.
create function pg_temp.pedido(p_persona uuid) returns uuid language sql as $$
  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, monto_declarado, anio,
    registrado_por, firma_persona, firma_persona_confirmada_at)
  values ('individual', p_persona, 'bono', fn_hoy_lima(), 180,
          extract(year from fn_hoy_lima())::int, p_persona,
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', now())
  returning id;
$$;


-- ── 1 · LA BOLETA DE UN PRACTICANTE CON BONO ─────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000415011');
create temp table _antes_pra on commit drop as
select fn_planilla_calcular_persona('00000000-0000-0000-0000-000000415001',
                                    '00000000-0000-0000-0000-0000000415a1') as f;
select pg_temp.como('00000000-0000-0000-0000-000000415012');
create temp table _antes_pla on commit drop as
select fn_planilla_calcular_persona('00000000-0000-0000-0000-000000415002',
                                    '00000000-0000-0000-0000-0000000415a1') as f;

select ok((select (f->>'total')::numeric from _antes_pra) > 0,
  'CONTROL · la boleta de partida del practicante tiene un total real, no un cero vacío');
select is((select (f->>'retencion_4ta')::numeric from _antes_pra), 0::numeric,
  'CONTROL · y su retención de 4.ª de partida es 0');

select pg_temp.como('00000000-0000-0000-0000-000000415011');
select is(pg_temp.pudo_pedir(), true, 'PEDIDO · el practicante firma con el periodo abierto');
select pg_temp.como('00000000-0000-0000-0000-000000415012');
select is(pg_temp.pudo_pedir(), true, 'PEDIDO · el de planilla también');

select pg_temp.como('00000000-0000-0000-0000-000000415011');
create temp table _desp_pra on commit drop as
select fn_planilla_calcular_persona('00000000-0000-0000-0000-000000415001',
                                    '00000000-0000-0000-0000-0000000415a1') as f;
select pg_temp.como('00000000-0000-0000-0000-000000415012');
create temp table _desp_pla on commit drop as
select fn_planilla_calcular_persona('00000000-0000-0000-0000-000000415002',
                                    '00000000-0000-0000-0000-0000000415a1') as f;

select is((select (f->>'bonos')::numeric from _desp_pra), fn_bono_monto_vigente(),
  'BOLETA · el practicante ve el bono en su boleta');
select is(
  (select (f->>'total')::numeric from _desp_pra) - (select (f->>'total')::numeric from _antes_pra),
  fn_bono_monto_vigente(),
  'PAGO · su total sube EXACTAMENTE el monto del bono');
select is(
  (select (f->>'total')::numeric from _desp_pra) - (select (f->>'total')::numeric from _antes_pra),
  (select (f->>'total')::numeric from _desp_pla) - (select (f->>'total')::numeric from _antes_pla),
  'IGUAL · el bono mueve el total del practicante lo mismo que el del integrante de planilla');
select is((select f->>'aporte_essalud' from _desp_pra), (select f->>'aporte_essalud' from _antes_pra),
  'NO MUEVE · el aporte a EsSalud del practicante no cambia con el bono');
select is((select f->>'base_essalud' from _desp_pra), (select f->>'base_essalud' from _antes_pra),
  'NO MUEVE · ni su base');
select is((select f->>'descuento_afp' from _desp_pra), (select f->>'descuento_afp' from _antes_pra),
  'NO MUEVE · ni el descuento de pensión');
select is((select (f->>'retencion_4ta')::numeric from _desp_pra), 0::numeric,
  'NO MUEVE · la RETENCIÓN de 4.ª del practicante sigue en 0: no se le descuenta nada por el bono');
select is(
  (select (f->>'retencion_4ta_base')::numeric from _desp_pra) - (select (f->>'retencion_4ta_base')::numeric from _antes_pra),
  (select (f->>'retencion_4ta_base')::numeric from _desp_pla) - (select (f->>'retencion_4ta_base')::numeric from _antes_pla),
  'CAMPO INFORMATIVO · la base de 4.ª sube, y sube IGUAL que en planilla: es un número que se muestra, no un descuento');


-- ── 2 · LA REPARACIÓN DE LO QUE LA 0520 DEJÓ «POR TRANSFERIR» ────────────
create temp table _docs on commit drop as
select
  pg_temp.pedido('00000000-0000-0000-0000-000000415003') as practicante,
  pg_temp.pedido('00000000-0000-0000-0000-000000415004') as transferido,
  pg_temp.pedido('00000000-0000-0000-0000-000000415006') as planilla,
  pg_temp.pedido('00000000-0000-0000-0000-000000415007') as inactivo;

-- El ya transferido: DO confirmó la transferencia (pagarlo en boleta sería pagarlo dos veces).
update documentos_firmados
   set entrega_confirmada_el = fn_hoy_lima(),
       entrega_confirmada_por = '00000000-0000-0000-0000-000000415005',
       entrega_confirmada_at = now()
 where id = (select transferido from _docs);

select is(fn_bono_pasar_pedidos_de_practicantes_a_boleta(), 1,
  'REPARACIÓN · mueve exactamente UN bono: el del practicante activo que quedó por transferir');
select isnt((select movimiento_id from documentos_firmados where id = (select practicante from _docs)), null::uuid,
  'REPARACIÓN · ese bono queda atado a una línea de boleta');
select is(
  (select count(*) from movimientos_planilla m
    where m.persona_id = '00000000-0000-0000-0000-000000415003' and m.tipo = 'bono'
      and m.concepto = 'Asignación por cumpleaños' and m.monto = 180
      and m.periodo_id = '00000000-0000-0000-0000-0000000415a1'),
  1::bigint,
  'REPARACIÓN · la línea es «Asignación por cumpleaños», por el monto que firmó, en el periodo abierto');
select is((select movimiento_id from documentos_firmados where id = (select transferido from _docs)), null::uuid,
  'NO TOCA · al que ya se le transfirió: pagarlo otra vez sería pagarlo dos veces');
select is((select movimiento_id from documentos_firmados where id = (select planilla from _docs)), null::uuid,
  'NO TOCA · al integrante de planilla: su «por transferir» es el respaldo legítimo de la 0478');
select is((select movimiento_id from documentos_firmados where id = (select inactivo from _docs)), null::uuid,
  'NO TOCA · a quien ya no está activo');
select is(fn_bono_pasar_pedidos_de_practicantes_a_boleta(), 0,
  'IDEMPOTENTE · pegarla de nuevo no mueve nada');
select is(
  (select count(*) from movimientos_planilla where persona_id = '00000000-0000-0000-0000-000000415003' and tipo = 'bono'),
  1::bigint,
  'IDEMPOTENTE · y no duplica la línea');
select is(
  (select count(*) from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000415003' and campo_modificado = 'bono_en_boleta'),
  1::bigint,
  'AUDITORÍA · queda el rastro de que el sistema lo pasó a la boleta');

select pg_temp.como('00000000-0000-0000-0000-000000415015');
select is(
  (select count(*) from fn_bonos_por_transferir()
    where persona_id = '00000000-0000-0000-0000-000000415003'),
  0::bigint,
  'DO · lo que pasó a la boleta sale de «por transferir»');
select is(
  (select count(*) from fn_bonos_por_transferir()
    where persona_id = '00000000-0000-0000-0000-000000415006'),
  1::bigint,
  'DO · y el de planilla sigue ahí: eso lo resuelve DO');

-- Un periodo ya pagado no se toca.
select pg_temp.pedido('00000000-0000-0000-0000-000000415008');
update periodos_planilla set estado = 'pagado', pagado_at = now()
 where id = '00000000-0000-0000-0000-0000000415a1';
select is(fn_bono_pasar_pedidos_de_practicantes_a_boleta(), 0,
  'PERIODO PAGADO · no escribe en una boleta cerrada');
select is(
  (select movimiento_id from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000415008' and tipo = 'bono'),
  null::uuid,
  'PERIODO PAGADO · y ese bono se queda «por transferir» para que DO lo vea');


-- ── 3 · NO LA CORRE CUALQUIERA ───────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000415011');
set local role authenticated;
select throws_ok(
  $$ select fn_bono_pasar_pedidos_de_practicantes_a_boleta() $$,
  '42501', null,
  'PERMISO · un usuario autenticado no puede correr la reparación: es plata');
reset role;

select * from finish();
rollback;
