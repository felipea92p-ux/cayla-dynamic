-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 346_una_correccion_no_pisa_un_expediente_ya_formal.test.sql — 0437
-- ============================================================================
-- expediente_disciplinario no tiene marcaje_id ni jornada_id: solo persona_id
-- + hechos jsonb. Por eso fn_dia_con_expediente_formal compara por FECHA, y
-- por eso cada escenario de abajo usa una fecha distinta para el mismo
-- integrante — mezclar fechas en un solo expediente haría que un escenario
-- contaminara al siguiente.
--
-- § 1 prueba el helper solo. § 2 prueba que las cinco puertas de verdad
-- bloquean cuando hay un firmado/entregado. § 3 es la trampa: un borrador o un
-- expediente de OTRA fecha no deben frenar nada — un falso positivo aquí le
-- impide a alguien corregir un día legítimo, y eso cuesta más que el hueco que
-- esta migración cierra.
-- ============================================================================
begin;
select plan(14);

-- ── El laboratorio ──────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre)
values ('aaaaaaaa-0437-0000-0000-000000000001','T37','Sede de la prueba 346');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('bbbbbbbb-0437-0000-0000-000000000001','00000000-0000-0000-0000-000000000000',
        'authenticated','authenticated','prueba344@cayla.local','x', now(), now(), now());

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id) values
 ('cccccccc-0437-0000-0000-00000000000a','Ada','Admin',
  'aaaaaaaa-0437-0000-0000-000000000001','x','admin','bbbbbbbb-0437-0000-0000-000000000001'),
 ('cccccccc-0437-0000-0000-00000000000b','Rosa','Trujillo',
  'aaaaaaaa-0437-0000-0000-000000000001','x','integrante', null);

-- Un mes cualquiera, lejos de cualquier periodo real (esta prueba corre
-- contra el Postgres LOCAL compartido, que ya tiene un periodo real de
-- 2026 — 2019 no choca con nada). Abierto porque nada de esto es sobre el
-- candado de periodo pagado.
insert into periodos_planilla (fecha_ini, fecha_fin, estado) values
 ('2019-01-01','2019-01-31','abierto');

set local request.jwt.claims = '{"sub":"bbbbbbbb-0437-0000-0000-000000000001","role":"authenticated"}';

-- ── Los expedientes: uno por escenario, cada uno en su propia fecha ─────────
insert into expediente_disciplinario
  (persona_id, tipo_causal, nivel, estado, hechos, correlativo, firmante_id, firmado_at, creado_por)
values
 ('cccccccc-0437-0000-0000-00000000000b','tardanza','amonestacion','firmado',
  '[{"fecha":"2019-01-10","minutos":15}]'::jsonb,
  'T-0437/0001-2026-CAYLA','cccccccc-0437-0000-0000-00000000000a', now(),
  'cccccccc-0437-0000-0000-00000000000a');

insert into expediente_disciplinario
  (persona_id, tipo_causal, nivel, estado, hechos, correlativo, firmante_id, firmado_at,
   medio_entrega, entregado_at, creado_por)
values
 ('cccccccc-0437-0000-0000-00000000000b','falta','amonestacion','entregado',
  '[{"fecha":"2019-01-05"}]'::jsonb,
  'T-0437/0002-2026-CAYLA','cccccccc-0437-0000-0000-00000000000a', now(),
  'fisico', now(), 'cccccccc-0437-0000-0000-00000000000a');

insert into expediente_disciplinario
  (persona_id, tipo_causal, nivel, estado, hechos, creado_por)
values
 ('cccccccc-0437-0000-0000-00000000000b','tardanza','verbal','borrador',
  '[{"fecha":"2019-01-02","minutos":5}]'::jsonb,
  'cccccccc-0437-0000-0000-00000000000a');

insert into expediente_disciplinario
  (persona_id, tipo_causal, nivel, estado, hechos, creado_por)
values
 ('cccccccc-0437-0000-0000-00000000000b','falta','verbal','anulado',
  '[{"fecha":"2019-01-03"}]'::jsonb,
  'cccccccc-0437-0000-0000-00000000000a');

-- ── § 1 · El helper, aislado ─────────────────────────────────────────────────
select ok(
  fn_dia_con_expediente_formal('cccccccc-0437-0000-0000-00000000000b','2019-01-10'),
  'firmado: el helper dice que sí');

select ok(
  fn_dia_con_expediente_formal('cccccccc-0437-0000-0000-00000000000b','2019-01-05'),
  'entregado: el helper dice que sí');

select ok(
  not fn_dia_con_expediente_formal('cccccccc-0437-0000-0000-00000000000b','2019-01-02'),
  'borrador: NO bloquea — todavía no se le entregó a nadie');

select ok(
  not fn_dia_con_expediente_formal('cccccccc-0437-0000-0000-00000000000b','2019-01-03'),
  'anulado: NO bloquea — ya está inerte');

select ok(
  not fn_dia_con_expediente_formal('cccccccc-0437-0000-0000-00000000000b','2019-01-11'),
  'LA TRAMPA: el firmado es del 10, no del 11 — un día vecino no se contagia');

select ok(
  not fn_dia_con_expediente_formal('cccccccc-0437-0000-0000-00000000000b','2019-01-15'),
  'sin ningún expediente para esa fecha: no bloquea');

-- ── § 2 · Las cinco puertas de verdad frenan ────────────────────────────────
create or replace function _m346(p_ts timestamptz, p_anulada bool default false,
                                  p_origen origen_marca default 'admin_correccion',
                                  p_estado_rev estado_revision default 'revisada')
returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca,
                        origen, estado_revision, anulada_at, anulada_motivo, anulada_por)
  values (gen_random_uuid(),'cccccccc-0437-0000-0000-00000000000b',
          'aaaaaaaa-0437-0000-0000-000000000001','salida_final', p_ts,
          p_origen, p_estado_rev,
          case when p_anulada then now() end,
          case when p_anulada then 'anulada para la prueba' end,
          case when p_anulada then 'cccccccc-0437-0000-0000-00000000000a'::uuid end)
  returning id into v;
  return v;
end $f$;

select throws_ok(
  format('select fn_anular_marcaje(%L, ''prueba 346'')', _m346('2019-01-10 09:00-05')),
  null,
  'anular una marca del día 10 (firmado) se frena');

select throws_ok(
  format('select fn_reactivar_marcaje(%L, ''prueba 346'')', _m346('2019-01-05 09:00-05', true)),
  null,
  'reactivar una marca del día 05 (entregado) se frena');

select throws_ok(
  format('select fn_corregir_marca(%L, null, %L, ''prueba 346'')',
         _m346('2019-01-10 09:00-05'), '2019-01-10 09:05-05'),
  null,
  'corregir la hora de una marca del día 10 (firmado) se frena');

select throws_ok(
  format('select fn_confirmar_auto_cierre(%L, ''prueba 346'')',
         _m346('2019-01-05 18:00-05', false, 'auto_cierre', 'pendiente_revision')),
  null,
  'confirmar un auto-cierre del día 05 (entregado) se frena');

select throws_ok(
  format('select fn_agregar_marcaje(''cccccccc-0437-0000-0000-00000000000b'', ''entrada'', %L, ''prueba 346'')',
         '2019-01-10 08:00-05'),
  null,
  'agregar un marcaje en el día 10 (firmado) se frena');

-- ── § 3 · Lo que NO puede empezar a frenar ──────────────────────────────────
select lives_ok(
  format('select fn_corregir_marca(%L, null, %L, ''prueba 346'')',
         _m346('2019-01-02 09:00-05'), '2019-01-02 09:05-05'),
  'corregir un día con solo un BORRADOR se sigue pudiendo — no está formalizado');

select lives_ok(
  format('select fn_agregar_marcaje(''cccccccc-0437-0000-0000-00000000000b'', ''entrada'', %L, ''prueba 346'')',
         '2019-01-02 08:00-05'),
  'agregar un marcaje en un día con solo un BORRADOR se sigue pudiendo');

select lives_ok(
  format('select fn_agregar_marcaje(''cccccccc-0437-0000-0000-00000000000b'', ''entrada'', %L, ''prueba 346'')',
         '2019-01-20 08:00-05'),
  'un día sin ningún expediente se sigue pudiendo tocar, como siempre');

select * from finish();
rollback;
