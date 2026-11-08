-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 493 — Anular la constancia del bono de cumpleaños lo saca de la boleta (0606)
-- ============================================================================
-- Hasta la 0606, anular en Documentación la constancia de un bono que ya iba en
-- la boleta (0479) dejaba viva su línea de S/ 180: se pagaba un bono sin papel,
-- y si la persona volvía a firmar, aparecía una SEGUNDA línea en el mismo periodo.
--
-- Lo que se exige, en el orden del recorrido real:
--   1. Anular un bono en boleta de un periodo ABIERTO retira su línea, en el
--      mismo paso, y deja rastro de qué se quitó.
--   2. Volver a firmar después deja UNA sola línea, no dos.
--   3. Si el periodo ya está PAGADO, anular se rechaza (decisión de Felipe,
--      2026-11-08): la plata pagada y su papel no se separan sin una decisión.
--   4. Un bono sin línea (pedido o transferido) se anula igual que siempre.
--   5. Quitar un bono o descuento desde Planilla deja rastro (antes, ninguno).
--
-- Supone una base sin periodos de planilla (la de CI); por eso los borra al
-- empezar, como la 378.
-- ============================================================================
begin;
select plan(15);

delete from periodo_grupo_pago;
delete from periodos_planilla;

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000493000', 'ZZ493', 'Sede de laboratorio 493', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000493001', 'Prueba', 'Anulada',   '00000000-0000-0000-0000-000000493000', 'integrante', 'test-hash', 'planilla', '00000000-0000-0000-0000-000000493011', '2020-01-01'),
  ('00000000-0000-0000-0000-000000493002', 'Prueba', 'Pagada',    '00000000-0000-0000-0000-000000493000', 'integrante', 'test-hash', 'planilla', '00000000-0000-0000-0000-000000493012', '2020-01-01'),
  ('00000000-0000-0000-0000-000000493003', 'Prueba', 'SinLinea',  '00000000-0000-0000-0000-000000493000', 'integrante', 'test-hash', 'planilla', '00000000-0000-0000-0000-000000493013', '2020-01-01'),
  ('00000000-0000-0000-0000-000000493004', 'Prueba', 'Manual',    '00000000-0000-0000-0000-000000493000', 'integrante', 'test-hash', 'planilla', '00000000-0000-0000-0000-000000493014', '2020-01-01'),
  ('00000000-0000-0000-0000-000000493005', 'Prueba', 'DO',        '00000000-0000-0000-0000-000000493000', 'admin',      'test-hash', 'planilla', '00000000-0000-0000-0000-000000493015', '2020-01-01');
set session_replication_role = origin;

insert into datos_personales (persona_id, fecha_nacimiento)
select id, make_date(1995, extract(month from fn_hoy_lima())::int, 10)
  from personas
 where id in ('00000000-0000-0000-0000-000000493001', '00000000-0000-0000-0000-000000493002',
              '00000000-0000-0000-0000-000000493003');

insert into firmas_escaneadas (persona_id, imagen, tipo)
select id, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen'
  from personas where id::text like '00000000-0000-0000-0000-00000049300%';

create function pg_temp.como(p_sub text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_sub, true);
end $$;

create function pg_temp.bono_de(p uuid) returns uuid language sql as $$
  select id from documentos_firmados
   where persona_id = p and tipo = 'bono' and anulado_at is null
   order by created_at desc, id desc limit 1
$$;

create function pg_temp.lineas(p uuid) returns bigint language sql as $$
  select count(*) from movimientos_planilla where persona_id = p and tipo = 'bono'
$$;

-- ── 4 (primero, porque necesita no tener periodo) · Un bono SIN línea ─────────
select pg_temp.como('00000000-0000-0000-0000-000000493013');
select fn_confirmar_mi_bono_cumpleanos();
select pg_temp.como('00000000-0000-0000-0000-000000493015');

select lives_ok(format($$ select fn_documento_anular(%L, 'Firmado por error') $$,
                       pg_temp.bono_de('00000000-0000-0000-0000-000000493003')),
  'SIN LÍNEA · un bono pedido, sin línea en ninguna boleta, se anula como siempre');

select is((select count(*) from documentos_firmados
            where persona_id = '00000000-0000-0000-0000-000000493003' and anulado_at is not null),
  1::bigint, 'SIN LÍNEA · y queda anulado');

-- ── Ahora hay un periodo abierto ─────────────────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000493a1', fn_hoy_lima() - 10, fn_hoy_lima() + 20, 'abierto');

-- ── 1 · Anular un bono en boleta de un periodo abierto ──────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000493011');
select fn_confirmar_mi_bono_cumpleanos();

select is(pg_temp.lineas('00000000-0000-0000-0000-000000493001'), 1::bigint,
  'CONTROL · al firmar, el bono entra a su boleta (0479)');

select pg_temp.como('00000000-0000-0000-0000-000000493015');
select lives_ok(format($$ select fn_documento_anular(%L, 'Se firmó con la fecha de nacimiento equivocada') $$,
                       pg_temp.bono_de('00000000-0000-0000-0000-000000493001')),
  'ABIERTO · DO anula la constancia');

select is(pg_temp.lineas('00000000-0000-0000-0000-000000493001'), 0::bigint,
  'ABIERTO · la línea de S/ 180 sale de la boleta en el mismo paso');

select is((select count(*) from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000493001'
              and campo_modificado = 'movimiento_quitado'
              and valor_anterior like '%Asignación por cumpleaños%'),
  1::bigint, 'ABIERTO · y queda el rastro de qué línea se quitó');

select is((select corregido_por from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000493001'
              and campo_modificado = 'movimiento_quitado'),
  '00000000-0000-0000-0000-000000493005'::uuid, 'ABIERTO · con quién la quitó');

select is((select count(*) from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000493001'
              and campo_modificado = 'documento_anulado'),
  1::bigint, 'ABIERTO · la anulación de la constancia deja su rastro de siempre');

-- ── 2 · Vuelve a firmar: una sola línea ──────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000493011');
select lives_ok($$ select fn_confirmar_mi_bono_cumpleanos() $$,
  'REFIRMA · después de anular, la persona puede volver a firmar');

select is(pg_temp.lineas('00000000-0000-0000-0000-000000493001'), 1::bigint,
  'REFIRMA · y su boleta lleva UNA sola línea de cumpleaños, no dos');

-- ── 5 · Quitar un bono a mano desde Planilla deja rastro ─────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000493015');
select fn_agregar_movimiento('00000000-0000-0000-0000-0000000493a1', '00000000-0000-0000-0000-000000493004',
                             'bono', 'Bono por inventario', 75, null, null);

select lives_ok(format($$ select fn_quitar_movimiento(%L) $$,
                       (select id from movimientos_planilla where persona_id = '00000000-0000-0000-0000-000000493004')),
  'PLANILLA · quitar un bono puesto a mano sigue funcionando');

select is((select valor_anterior from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000493004'
              and campo_modificado = 'movimiento_quitado'),
  'bono · Bono por inventario · S/ 75.00', 'PLANILLA · y ahora queda qué se quitó, de qué tipo y por cuánto');

-- ── 3 · El periodo ya está pagado ────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000493012');
select fn_confirmar_mi_bono_cumpleanos();
update periodos_planilla set estado = 'pagado' where id = '00000000-0000-0000-0000-0000000493a1';

select pg_temp.como('00000000-0000-0000-0000-000000493015');
select throws_like(format($$ select fn_documento_anular(%L, 'Intento sobre un periodo pagado') $$,
                          pg_temp.bono_de('00000000-0000-0000-0000-000000493002')),
  '%ya se PAGÓ con la planilla del periodo que cerró el%', 'PAGADO · anular un bono que ya se pagó con la planilla se rechaza con un aviso');

select is(pg_temp.lineas('00000000-0000-0000-0000-000000493002'), 1::bigint,
  'PAGADO · la línea pagada sigue donde estaba');

select is((select count(*) from documentos_firmados
            where persona_id = '00000000-0000-0000-0000-000000493002' and anulado_at is not null),
  0::bigint, 'PAGADO · y la constancia NO queda anulada: plata y papel no se separan');

select * from finish();
rollback;
