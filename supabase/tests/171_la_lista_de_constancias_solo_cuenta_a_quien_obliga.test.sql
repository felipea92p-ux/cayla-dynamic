-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 171_la_lista_de_constancias_solo_cuenta_a_quien_obliga.test.sql
-- ============================================================================
-- El artículo 2.1 del Reglamento: obliga a quien tiene CONTRATO DE TRABAJO.
--
-- El 12-08-2026 la lista devolvía 24 personas pendientes cuando las que faltan
-- son 20: metía a las tres locadoras de servicios y a quien no es trabajadora.
-- Cuatro nombres que nunca van a dejar constancia porque no tienen ninguna que
-- dejar — y una lista de pendientes que no puede llegar a cero se deja de mirar.
--
-- Lo que fija esta prueba:
--   · La lista cuenta solo a quien tiene contrato de trabajo.
--   · Una locadora no aparece, aunque no tenga constancia.
--   · Quien sí acusó tampoco aparece — el filtro nuevo no rompió el viejo.
--   · Y una integrante solo puede ver la lista si es admin o líder de DO: es
--     quién no ha firmado algo, y eso no se le enseña a cualquiera.
-- ============================================================================
-- `en_planilla` es una columna GENERADA a partir de `tipo_vinculo`
-- ('planilla' o 'prueba'), así que en las semillas se escribe el vínculo y la
-- columna se deriva sola. Intentar insertarla directamente falla con «cannot
-- insert a non-DEFAULT value into column», que es el freno correcto: una sola
-- fuente para el mismo dato.
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000b101', 'ZZ201', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000b102', 'DoLista', 'Lab',
        '00000000-0000-0000-0000-00000000b101', 'lider_do', 'x',
        '00000000-0000-0000-0000-000000b10002', '2020-01-01', 'activo', 'planilla');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000b106', 'IntegranteLista', 'Lab',
        '00000000-0000-0000-0000-00000000b101', 'integrante', 'x',
        '00000000-0000-0000-0000-000000b10006', '2020-01-01', 'activo', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000b103', 'ConContrato',  'Lab', '00000000-0000-0000-0000-00000000b101', 'x', '2020-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-00000000b104', 'LocadoraLab',  'Lab', '00000000-0000-0000-0000-00000000b101', 'x', '2020-01-01', 'activo', 'rxh'),
  ('00000000-0000-0000-0000-00000000b105', 'YaFirmoLab',   'Lab', '00000000-0000-0000-0000-00000000b101', 'x', '2020-01-01', 'activo', 'planilla');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000b10002', true);

-- Se publica el Reglamento y solo YaFirmoLab deja constancia.
select fn_publicar_documento('rit', 'Reglamento de laboratorio',
  'Texto del Reglamento de laboratorio para la prueba 171.', fn_hoy_lima(), null);

insert into documentos_acuses (documento_id, persona_id, via, nombre_declarado)
select id, '00000000-0000-0000-0000-00000000b105', 'sistema', 'YaFirmoLab Lab'
from documentos_institucionales where tipo = 'rit' order by version desc limit 1;

-- ── Quién sale en la lista ──────────────────────────────────────────────────
select is(
  (select count(*)::int from fn_sin_constancia_del_reglamento()
    where persona_id = '00000000-0000-0000-0000-00000000b103'),
  1, 'ART. 2.1 · quien tiene contrato de trabajo y no acusó, sí aparece');

select is(
  (select count(*)::int from fn_sin_constancia_del_reglamento()
    where persona_id = '00000000-0000-0000-0000-00000000b104'),
  0, 'ART. 2.1 · una locadora NO aparece: el Reglamento no la obliga, no tiene constancia que dejar');

select is(
  (select count(*)::int from fn_sin_constancia_del_reglamento()
    where persona_id = '00000000-0000-0000-0000-00000000b105'),
  0, 'ART. 2.1 · quien ya acusó tampoco aparece: el filtro nuevo no rompió el viejo');

select ok(
  (select count(*) from fn_sin_constancia_del_reglamento()) >= 1,
  'LISTA · hay al menos una persona pendiente, así que la lista no está vacía por accidente');

-- La lista tiene que traer el motivo, no solo el nombre: sin él, quien la mire
-- no sabe qué versión falta ni desde cuándo regía.
select isnt(
  (select motivo from fn_sin_constancia_del_reglamento()
    where persona_id = '00000000-0000-0000-0000-00000000b103'),
  null, 'LISTA · cada fila trae el motivo por escrito');

-- ── Y no la ve cualquiera ───────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000b10006', true);
select is(
  (select count(*)::int from fn_sin_constancia_del_reglamento()),
  0, 'RESERVA · una integrante no ve quién no ha firmado');

select * from finish();
rollback;
