-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/0406_....sql.
-- ============================================================================
-- 323_confirmar_la_firma_dos_veces_no_borra_la_primera.test.sql
-- ============================================================================
-- Lo que esta prueba vigila:
--
--   1. Confirmar deja constancia Y deja la firma vigente en el contrato: las
--      dos cosas, porque el contrato se sigue leyendo de la segunda.
--   2. Reconfirmar con OTRA firma agrega una fila y no pisa la anterior — el
--      defecto que este arreglo cierra. La primera imagen tiene que seguir ahí.
--   3. La vigente del contrato sí es la última: el historial no reemplaza al
--      atajo, lo respalda.
--   4. RLS: cada quien ve sus confirmaciones y no las ajenas — con
--      `set local role authenticated`, sin el cual pgTAP corre como dueña de la
--      tabla y se salta RLS entera.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-0000000ff10a', 'ZZFIR', 'Sede laboratorio firma', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000ff20a', 'FirColab', 'Lab', '00000000-0000-0000-0000-0000000ff10a', 'integrante', 'x', '00000000-0000-0000-0000-0000000ffaaa', '2024-01-01'),
  ('00000000-0000-0000-0000-0000000ff30a', 'FirOtra', 'Lab', '00000000-0000-0000-0000-0000000ff10a', 'integrante', 'x', '00000000-0000-0000-0000-0000000ffbbb', '2024-01-01');

insert into contratos_generados
  (id, persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, documento_html, generado_por)
values
  ('00000000-0000-0000-0000-0000000ff40a', '00000000-0000-0000-0000-0000000ff20a', 'nuevo',
   'Asesora', '00000000-0000-0000-0000-0000000ff10a', 1130, '2026-01-01', '<p>contrato</p>',
   '00000000-0000-0000-0000-0000000ff20a');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ffaaa', true);

-- Su firma, primera versión.
select fn_set_mi_firma('data:image/png;base64,UFJJTUVSQQ==');

-- ── 1 · Confirmar deja constancia y deja la vigente ─────────────────────────
select lives_ok($$ select fn_confirmar_mi_firma_contrato('00000000-0000-0000-0000-0000000ff40a') $$,
  'CONFIRMA · la primera confirmación entra sin problema');

select is((select count(*)::int from confirmaciones_firma_contrato
           where contrato_id = '00000000-0000-0000-0000-0000000ff40a'),
  1, 'CONFIRMA · queda una fila de constancia');

select is((select firma_persona from contratos_generados where id = '00000000-0000-0000-0000-0000000ff40a'),
  'data:image/png;base64,UFJJTUVSQQ==',
  'CONFIRMA · y el contrato queda con esa firma como vigente');

-- ── 2 · Cambia su firma y vuelve a confirmar ────────────────────────────────
select fn_set_mi_firma('data:image/png;base64,U0VHVU5EQQ==');
select fn_confirmar_mi_firma_contrato('00000000-0000-0000-0000-0000000ff40a');

select is((select count(*)::int from confirmaciones_firma_contrato
           where contrato_id = '00000000-0000-0000-0000-0000000ff40a'),
  2, 'RECONFIRMA · son DOS filas, no una actualizada');

select is((select count(*)::int from confirmaciones_firma_contrato
           where contrato_id = '00000000-0000-0000-0000-0000000ff40a'
             and imagen = 'data:image/png;base64,UFJJTUVSQQ=='),
  1, 'RECONFIRMA · la PRIMERA imagen sigue guardada — el defecto que se cierra');

-- ── 3 · La vigente es la última ─────────────────────────────────────────────
select is((select firma_persona from contratos_generados where id = '00000000-0000-0000-0000-0000000ff40a'),
  'data:image/png;base64,U0VHVU5EQQ==',
  'RECONFIRMA · el contrato queda con la última, que es la que se imprime');

-- ── 4 · RLS de verdad, con el rol puesto ────────────────────────────────────
set local role authenticated;
select is((select count(*)::int from confirmaciones_firma_contrato
           where contrato_id = '00000000-0000-0000-0000-0000000ff40a'),
  2, 'RLS · la propia persona ve sus dos confirmaciones');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ffbbb', true);
set local role authenticated;
select is((select count(*)::int from confirmaciones_firma_contrato
           where contrato_id = '00000000-0000-0000-0000-0000000ff40a'),
  0, 'RLS · una compañera cualquiera no ve las confirmaciones ajenas');
reset role;

select * from finish();
rollback;
