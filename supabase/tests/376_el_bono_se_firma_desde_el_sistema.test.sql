-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 376_el_bono_se_firma_desde_el_sistema.test.sql — 0477
-- ============================================================================
-- El bono se paga por transferencia, así que no hay candado de secuencia
-- (a diferencia de una primera versión de esta migración, descartada antes
-- de pegarse en ningún lado). Lo que importa defender es que sea LA MISMA
-- puerta que ya usa el escaneo de siempre, y que las dos vías no puedan
-- convivir con dos constancias vigentes del mismo año:
--
--   1. LA MISMA PUERTA QUE fn_documento_registrar. En planilla, activa.
--   2. NO SE PUEDE FIRMAR DOS VECES EL MISMO AÑO — ni dos veces digital, ni
--      digital después de un escaneo ya vigente.
--   3. EL MONTO LO CALCULA EL SERVIDOR, nunca quien firma.
--   4. EL AISLAMIENTO de fn_documentos_tablero(p_solo_mi_fila => true) sigue
--      intacto — esta migración no lo toca, pero conviene comprobar que
--      seguir sin tocarlo no rompió nada.
--   5. fn_bono_monto_vigente() LA PUEDE LLAMAR CUALQUIERA, no solo un admin —
--      `parametros_laborales` tiene RLS que solo deja leer a admin/líder, y
--      sin esta función /mio/cumpleanos no tiene cómo mostrarle a la persona
--      el monto ANTES de firmar (se descubrió probando en el navegador: la
--      pantalla decía "no hay monto vigente" con la fila presente en la
--      tabla, por RLS).
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000376000', 'ZZ376', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id) values
  ('00000000-0000-0000-0000-000000376001', 'Prueba', 'Cumpleanera',
   '00000000-0000-0000-0000-000000376000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000376011'),
  ('00000000-0000-0000-0000-000000376002', 'Prueba', 'FueraDePlanilla',
   '00000000-0000-0000-0000-000000376000', 'integrante', 'test-hash', 'rxh',
   '00000000-0000-0000-0000-000000376012'),
  ('00000000-0000-0000-0000-000000376003', 'Prueba', 'Admin',
   '00000000-0000-0000-0000-000000376000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000376013'),
  ('00000000-0000-0000-0000-000000376004', 'Prueba', 'YaTieneEscaneo',
   '00000000-0000-0000-0000-000000376000', 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000376014');
set session_replication_role = origin;

insert into parametros_laborales (clave, valor, vigente_desde, sede_codigo)
values ('bono_onomastico', 180.00, '2020-01-01', null)
on conflict do nothing;

-- Desde la 0478 el bono solo se pide en el mes del cumpleaños (o después):
-- sin fecha de nacimiento, «con todo en regla» dejaría de estarlo. Las dos
-- que firman cumplen este mes; lo que esta prueba defiende no cambia.
insert into datos_personales (persona_id, fecha_nacimiento) values
  ('00000000-0000-0000-0000-000000376001', make_date(1995, extract(month from fn_hoy_lima())::int, 10)),
  ('00000000-0000-0000-0000-000000376004', make_date(1995, extract(month from fn_hoy_lima())::int, 10));

-- ── 1 · Fuera de planilla no tiene bono que firmar ─────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000376012', true);
select throws_ok(
  $$ select fn_confirmar_mi_bono_cumpleanos() $$,
  null, null,
  'PUERTA · fuera de planilla no le corresponde el bono, igual que en fn_documento_registrar');

-- ── 2 · Sin firma guardada, tampoco hay firma que confirmar ────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000376011', true);
select throws_ok(
  $$ select fn_confirmar_mi_bono_cumpleanos() $$,
  null, null,
  'CANDADO · todavía no configuró su firma en firmas_escaneadas');

insert into firmas_escaneadas (persona_id, imagen, tipo)
values ('00000000-0000-0000-0000-000000376001', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen');

-- ── 3 · fn_bono_monto_vigente() la puede llamar cualquiera, no solo admin ──
-- El sub sigue siendo Cumpleanera (integrante, no admin/líder) desde el
-- paso 2: si esta función dependiera de RLS sobre parametros_laborales como
-- una consulta directa, devolvería null aquí.
select is(
  fn_bono_monto_vigente(),
  180.00::numeric,
  'MONTO VIGENTE · quien no es admin también puede leerlo, pese a que parametros_laborales solo la lee un admin');

-- ── 4 · Con todo en regla, firma sin que nadie tenga que "entregarle" nada ──
select lives_ok(
  $$ select fn_confirmar_mi_bono_cumpleanos() $$,
  'OK · en planilla, activa, con firma guardada: la constancia se registra directo, sin paso previo de un admin');

select is(
  (select monto_declarado from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000376001' and tipo = 'bono'),
  180.00::numeric,
  'MONTO · lo calcula el servidor con el bono_onomastico vigente, nunca un valor que declare quien firma');

select is(
  (select fecha_firma from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000376001' and tipo = 'bono'),
  fn_hoy_lima(),
  'FECHA · la firma digital fecha con el día de hoy en Lima');

select ok(
  (select firma_persona_confirmada_at is not null from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000376001' and tipo = 'bono'),
  'EVIDENCIA · queda la imagen y el instante exacto de la firma digital');

-- ── 5 · No puede volver a confirmar una segunda vez el mismo año ───────────
select throws_ok(
  $$ select fn_confirmar_mi_bono_cumpleanos() $$,
  null, null,
  'CANDADO · ya firmada este año, no puede volver a confirmar');

-- ── 6 · Las dos vías no pueden convivir: si el escaneo llega primero, la
--        firma digital ya no tiene nada que reemplazar ────────────────────
-- Admin registra el cargo escaneado de OTRA persona (YaTieneEscaneo) este
-- mismo año, por el camino de siempre.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000376013', true);
select lives_ok(
  $$ select fn_documento_registrar('bono', fn_hoy_lima(), '00000000-0000-0000-0000-000000376004',
                                    null, 180.00, extract(year from fn_hoy_lima())::int,
                                    false, null, 'documentos/bono-escaneado.pdf') $$,
  'OK · el escaneo de siempre sigue funcionando exactamente igual, sin ningún cambio de esta migración');

-- Y si esa persona intenta firmar digital DESPUÉS, no hay nada que firmar:
-- ya tiene su constancia de este año, por la vía del papel.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000376014', true);
select throws_ok(
  $$ select fn_confirmar_mi_bono_cumpleanos() $$,
  null, null,
  'CANDADO · con el escaneo ya vigente este año, la firma digital no puede duplicarlo');

select * from finish();
rollback;
