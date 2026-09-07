-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 307_el_tablero_de_documentos_desempata_la_ruta.test.sql — 0387
-- ============================================================================
-- Mismo defecto que la 0386 arregló en `fn_contratos_tablero`, y en la misma
-- familia de consultas: un `distinct on` cuyo último criterio de orden es una
-- columna `default now()`. Dentro de una transacción `now()` vale lo mismo para
-- todas las filas, así que empatan — y sin desempate gana la que el motor
-- devuelva primero, que es el orden físico de la tabla.
--
-- Acá el empate importa más que allá: la fila que gana decide `estado`, y ese
-- estado distingue «firmó el pacto de movilidad» de «se negó a firmarlo». No es
-- cosmética — sin pacto individual firmado el monto NO es no remunerativo, y
-- pagarlo igual es lo que la RTF 05449-4-2007 sanciona (ver el comentario de
-- `documentos_firmados.es_negativa`, migración 0157).
--
-- Las dos personas de abajo son idénticas salvo en el ORDEN en que se guardaron
-- sus dos documentos. Sin el desempate, una de las dos contesta al revés que la
-- otra; con él, las dos contestan lo mismo.
--
-- La cuarta aserción es la que explica por qué el CTE `bono` de esa misma
-- función NUNCA empató, aunque su `order by` sea todavía más corto: el índice
-- parcial único `idx_documentos_bono_uno_por_anio` hace imposible que haya dos
-- candidatos. Se prueba acá para que ese índice no se pueda quitar sin que algo
-- se ponga rojo — hoy es él, y no el `order by`, quien sostiene esa rama.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000307000', 'ZZ307', 'Sede de laboratorio 307', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000307aa0', 'Jefa', 'Lab307',
        '00000000-0000-0000-0000-000000307000', 'admin', 'h',
        '00000000-0000-0000-0000-000000307aff', '2025-01-02');
set session_replication_role = origin;

do $sesion$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000307aff', true);
end $sesion$;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000307001', 'Dora', 'PrimeroLaFirmada307',
        '00000000-0000-0000-0000-000000307000', 'h', '2026-01-05'),
       ('00000000-0000-0000-0000-000000307002', 'Elsa', 'PrimeroLaNegativa307',
        '00000000-0000-0000-0000-000000307000', 'h', '2026-01-05');

-- Los cuatro documentos llevan la MISMA `fecha_firma` y nacen en esta misma
-- transacción, así que su `created_at` también empata: es exactamente lo que
-- produce `now()` acá dentro. Lo único que los distingue es el `id`, que es el
-- ancla determinista que agrega la 0387 — y en las dos personas el id mayor es
-- el de la NEGATIVA, así que la respuesta correcta es la misma para ambas.
--
-- Dora: primero la firmada, después la negativa.
insert into documentos_firmados
  (id, alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
   es_negativa, registrado_por)
values
  ('00000000-0000-0000-0000-0000003070d1', 'individual',
   '00000000-0000-0000-0000-000000307001', 'ruta', '2026-03-02',
   'Casa - tienda', 12.00, false, '00000000-0000-0000-0000-000000307aa0'),
  ('00000000-0000-0000-0000-0000003070d2', 'individual',
   '00000000-0000-0000-0000-000000307001', 'ruta', '2026-03-02',
   null, null, true, '00000000-0000-0000-0000-000000307aa0');

-- Elsa: al revés — primero la negativa, después la firmada.
insert into documentos_firmados
  (id, alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
   es_negativa, registrado_por)
values
  ('00000000-0000-0000-0000-0000003070e2', 'individual',
   '00000000-0000-0000-0000-000000307002', 'ruta', '2026-03-02',
   null, null, true, '00000000-0000-0000-0000-000000307aa0'),
  ('00000000-0000-0000-0000-0000003070e1', 'individual',
   '00000000-0000-0000-0000-000000307002', 'ruta', '2026-03-02',
   'Casa - tienda', 12.00, false, '00000000-0000-0000-0000-000000307aa0');

-- ── 1 y 2 · La misma respuesta, guardadas en el orden que sea ──────────────
select is(
  (select estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-000000307001'),
  'se_nego',
  'dos documentos de ruta del mismo día: el estado no lo decide el orden físico de la tabla');

select is(
  (select estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-000000307002'),
  'se_nego',
  'y la persona con los mismos dos documentos guardados al revés contesta igual');

-- ── 3 · Y la fila que gana viene entera de un solo documento ───────────────
select ok(
  (select ruta_monto from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-000000307001') is null,
  'gana la negativa, y una negativa no lleva monto: no se cuela el monto del otro papel');

-- ── 4 · Por qué el CTE `bono` nunca empató: el índice, no el `order by` ────
insert into documentos_firmados
  (alcance, persona_id, tipo, fecha_firma, anio, es_negativa, registrado_por)
values
  ('individual', '00000000-0000-0000-0000-000000307001', 'bono', '2026-03-02',
   2026, false, '00000000-0000-0000-0000-000000307aa0');

select throws_ok(
  $$ insert into documentos_firmados
       (alcance, persona_id, tipo, fecha_firma, anio, es_negativa, registrado_por)
     values ('individual', '00000000-0000-0000-0000-000000307001', 'bono',
             '2026-03-02', 2026, false, '00000000-0000-0000-0000-000000307aa0') $$,
  '23505', null,
  'un segundo bono vigente del mismo año rebota contra idx_documentos_bono_uno_por_anio: por eso ESA rama no puede empatar');

select * from finish();
rollback;
