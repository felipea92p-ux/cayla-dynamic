-- ============================================================================
-- 425_la_politica_se_firma_con_la_firma_del_sistema.test.sql
-- ============================================================================
-- Defiende la 0531: la política de movilidad se puede firmar desde
-- Documentación con la firma guardada de quien firma por CAYLA, sin escanear.
--
-- Las dos mitades que importan:
--
--   · Que la firma estampada sea SIEMPRE la del firmante configurado, y nunca
--     otra. La función no recibe ni persona ni imagen; lo que se prueba aquí es
--     que tampoco se cuela por el HTML que manda la pantalla.
--   · Que la política firmada así sea una política como cualquier otra: la ve
--     `fn_documentos_estado_politica`, reemplaza a la anterior (0211) y la
--     reemplaza la siguiente, sea escaneo o firma.
--
-- Quien firma la llamada es una líder DO y el firmante es otra persona (la
-- admin): es el caso real —DO archiva la política, la firma es la de Felipe—.
-- ============================================================================
begin;
select plan(18);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000042500', 'ZZ425', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  -- Quien firma por CAYLA.
  ('00000000-0000-0000-0000-000000042501', 'PolFirmante', 'Laboratorio',
   '00000000-0000-0000-0000-000000042500', 'admin', 'test-hash',
   '00000000-0000-0000-0000-000000042511', '2020-01-01'),
  -- Quien archiva la política desde Documentación.
  ('00000000-0000-0000-0000-000000042502', 'PolDO', 'Laboratorio',
   '00000000-0000-0000-0000-000000042500', 'lider_do', 'test-hash',
   '00000000-0000-0000-0000-000000042512', '2020-01-01'),
  -- Una integrante cualquiera: no archiva documentos de la empresa.
  ('00000000-0000-0000-0000-000000042503', 'PolIntegrante', 'Laboratorio',
   '00000000-0000-0000-0000-000000042500', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000042513', '2020-01-01');
set session_replication_role = origin;

insert into configuracion (clave, valor)
values ('firmante_empresa',
        jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000042501',
                           'cargo', 'Gerencia General'))
on conflict (clave) do update set valor = excluded.valor;

-- La firma que el sistema tiene guardada para el firmante, y un HTML de
-- política que la lleva estampada — como lo arma la pantalla.
create temp table t425 as
select 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='::text as firma,
       'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=='::text as otra;

create or replace function pg_temp.html425(p_firma text, p_extra text default '')
returns text language sql as $$
  select '<div class="hoja"><h2>Política de movilidad supeditada a asistencia</h2>'
      || repeat('<p>Cláusula de laboratorio para que el documento tenga cuerpo.</p>', 10)
      || p_extra
      || '<img src="' || p_firma || '" alt="" aria-hidden="true">'
      || '<div>Laboratorio PolFirmante</div></div>'
$$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000042512', true);


-- ── 1 · Sin firma guardada no hay con qué firmar ───────────────────────────
select throws_like(
  $$ select fn_politica_firmar_con_firma_empresa('2026-07-29', pg_temp.html425((select firma from t425))) $$,
  '%todavía no tiene su firma guardada%',
  'SIN FIRMA · si el firmante no guardó su firma, se pide el papel');

insert into firmas_escaneadas (persona_id, imagen, tipo)
values ('00000000-0000-0000-0000-000000042501', (select firma from t425), 'imagen')
on conflict (persona_id) do update set imagen = excluded.imagen, tipo = excluded.tipo, estilo = null;


-- ── 2 · Lo que no entra ─────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000042513', true);
select throws_like(
  $$ select fn_politica_firmar_con_firma_empresa('2026-07-29', pg_temp.html425((select firma from t425))) $$,
  '%Solo Desarrollo Organizacional%',
  'GUARD · una integrante no archiva la política de la empresa');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000042512', true);

select throws_like(
  $$ select fn_politica_firmar_con_firma_empresa(fn_hoy_lima() + 1, pg_temp.html425((select firma from t425))) $$,
  '%no puede ser futura%',
  'FECHA · una política fechada mañana no entra');

select throws_like(
  $$ select fn_politica_firmar_con_firma_empresa('2026-07-29', pg_temp.html425((select otra from t425))) $$,
  '%no es la que el sistema tiene guardada%',
  'OTRA RÚBRICA · un HTML con una firma que no es la del firmante no entra');

select throws_like(
  $$ select fn_politica_firmar_con_firma_empresa('2026-07-29',
       replace(pg_temp.html425((select firma from t425)), 'Política de movilidad', 'Otro documento')) $$,
  '%no es la política de movilidad%',
  'OTRO PAPEL · un documento que no es la política no entra');

select throws_like(
  $$ select fn_politica_firmar_con_firma_empresa('2026-07-29',
       pg_temp.html425((select firma from t425), '<script>alert(1)</script>')) $$,
  '%no corresponde%',
  'EJECUTABLE · un <script> no se guarda para volver a pintarse');

select throws_like(
  $$ select fn_politica_firmar_con_firma_empresa('2026-07-29',
       pg_temp.html425((select firma from t425), '<img src="x" onerror="alert(1)">')) $$,
  '%no corresponde%',
  'EJECUTABLE · un atributo on…= tampoco');


-- ── 3 · Firmar ──────────────────────────────────────────────────────────────
-- Antes, un escaneo vigente: la firma desde el sistema tiene que reemplazarlo.
select fn_documento_registrar(p_tipo => 'politica', p_fecha_firma => '2026-07-29'::date,
                              p_storage_path => 'documentos/escaneo-425.pdf');

select lives_ok(
  $$ select fn_politica_firmar_con_firma_empresa('2026-07-29', pg_temp.html425((select firma from t425)), 'firmada en laboratorio') $$,
  'FIRMAR · DO firma la política con la firma de la empresa');

select is(
  (select cargada from fn_documentos_estado_politica()),
  true,
  'FIRMAR · la política cuenta como cargada');

select is(
  (select storage_path from fn_documentos_estado_politica()),
  null::text,
  'FIRMAR · y la vigente es la del sistema, sin archivo');

select is(
  (select firma_persona from documentos_firmados where tipo = 'politica' and anulado_at is null),
  (select firma from t425),
  'CONGELADO · la firma guardada es la del firmante');

select is(
  (select firmante_empresa_id from documentos_firmados where tipo = 'politica' and anulado_at is null),
  '00000000-0000-0000-0000-000000042501'::uuid,
  'CONGELADO · consta quién firmó por CAYLA, no quién archivó');

select is(
  (select registrado_por from documentos_firmados where tipo = 'politica' and anulado_at is null),
  '00000000-0000-0000-0000-000000042502'::uuid,
  'CONGELADO · y quién la archivó queda aparte');

select is(
  (select anulado_motivo from documentos_firmados where storage_path = 'documentos/escaneo-425.pdf'),
  'Reemplazada por la política firmada el 29/07/2026',
  'REEMPLAZO · el escaneo anterior queda anulado, con el motivo de siempre');


-- ── 4 · Y la siguiente la reemplaza a ella ─────────────────────────────────
select fn_documento_registrar(p_tipo => 'politica', p_fecha_firma => '2026-07-29'::date,
                              p_storage_path => 'documentos/escaneo-425-b.pdf');

select is(
  (select count(*)::int from documentos_firmados where tipo = 'politica' and anulado_at is null),
  1,
  'REEMPLAZO · un escaneo posterior deja una sola política viva');

select ok(
  (select anulado_at is not null and documento_html is not null
     from documentos_firmados where firmante_empresa_id = '00000000-0000-0000-0000-000000042501'),
  'REEMPLAZO · la firmada desde el sistema queda como historial, con su texto');


-- ── 5 · Lo que el esquema hace imposible ───────────────────────────────────
select throws_ok(
  $$ insert into documentos_firmados (alcance, persona_id, tipo, fecha_firma, registrado_por, documento_html)
     values ('individual', '00000000-0000-0000-0000-000000042503', 'ruta', '2026-08-01',
             '00000000-0000-0000-0000-000000042502', '<p>texto</p>') $$,
  '23514', null,
  'IMPOSIBLE · una declaración de ruta con texto de política no entra');

select throws_ok(
  $$ insert into documentos_firmados (alcance, tipo, fecha_firma, registrado_por, firmante_empresa_id, documento_html)
     values ('empresa', 'politica', '2026-08-01', '00000000-0000-0000-0000-000000042502',
             '00000000-0000-0000-0000-000000042501', '<p>texto</p>') $$,
  '23514', null,
  'IMPOSIBLE · una política «del sistema» sin la firma estampada no entra');

select * from finish();
rollback;
