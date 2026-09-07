-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 309_las_cuatro_consultas_que_quedaban_desempatan.test.sql — 0389
-- ============================================================================
-- Las cuatro últimas de la familia que abrieron la 0386, la 0387 y la 0388:
-- una consulta que pregunta «¿cuál es el último?» ordenando por una columna que
-- puede valer lo mismo en dos filas. Sin desempate gana la que devuelva el orden
-- físico de la tabla, que cambia solo.
--
-- Las cuatro son del tipo INERTE: la columna que las desempata hoy —`now()`, que
-- el sistema escribe con la hora exacta— solo empata entre filas nacidas en una
-- misma transacción, y en producción cada escritura entra por su propia llamada.
-- Por eso esta prueba tiene que crear las filas de a pares en un solo `insert`:
-- es la única forma de reproducir el empate, y es exactamente lo que hace una
-- prueba pgTAP sin querer, porque corre entera dentro de `begin … rollback`.
--
-- En cada caso el par se guarda en el orden que hace fallar la aserción sin la
-- migración. Una prueba que acierta por casualidad no guarda nada.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000309000', 'ZZ309', 'Sede de laboratorio 309', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000309aa0', 'Jefa', 'Lab309',
        '00000000-0000-0000-0000-000000309000', 'admin', 'h',
        '00000000-0000-0000-0000-000000309aff', '2025-01-02');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000309001', 'Julia', 'Lab309',
        '00000000-0000-0000-0000-000000309000', 'h', '2026-01-05');

do $sesion$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000309aff', true);
end $sesion$;

-- ── 1 · fn_contratos_listar · cuál contrato sale marcado como vigente ──────
-- Los dos nacen en el mismo `insert`, así que su `generado_at` es idéntico. El
-- que manda es el que EMPIEZA después — el mismo criterio que la 0386 le puso a
-- `fn_contratos_tablero`, que se dibuja en esta misma pantalla. Se guarda
-- primero el viejo para que el orden físico apunte al equivocado.
insert into contratos_generados
  (id, persona_id, tipo, cargo, sede_id, remuneracion_mensual,
   fecha_inicio, fecha_fin, documento_html, generado_por)
values
  ('00000000-0000-0000-0000-0000003090c1', '00000000-0000-0000-0000-000000309001',
   'nuevo', 'Asesora', '00000000-0000-0000-0000-000000309000', 1130,
   '2026-01-05', '2026-07-05', '<p>el viejo</p>', '00000000-0000-0000-0000-000000309aa0'),
  ('00000000-0000-0000-0000-0000003090c2', '00000000-0000-0000-0000-000000309001',
   'renovacion', 'Asesora', '00000000-0000-0000-0000-000000309000', 1500,
   '2026-07-06', '2027-07-05', '<p>el nuevo</p>', '00000000-0000-0000-0000-000000309aa0');

select is(
  (select id from fn_contratos_listar('00000000-0000-0000-0000-000000309001') where vigente),
  '00000000-0000-0000-0000-0000003090c2'::uuid,
  'fn_contratos_listar · vigente es el contrato que empieza después, no el que quedó primero en la tabla');

-- ── 2 · fn_documentos_listar · cuál documento de ruta sale como vigente ────
-- Misma fecha de firma y mismo `created_at`: solo los separa el `id`. El que
-- debe ganar es el de id mayor, y se guarda SEGUNDO para que el orden físico
-- apunte al otro.
insert into documentos_firmados
  (id, alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
   es_negativa, registrado_por)
values
  ('00000000-0000-0000-0000-0000003090d1', 'individual',
   '00000000-0000-0000-0000-000000309001', 'ruta', '2026-03-02',
   'La otra', 10.00, false, '00000000-0000-0000-0000-000000309aa0'),
  ('00000000-0000-0000-0000-0000003090d2', 'individual',
   '00000000-0000-0000-0000-000000309001', 'ruta', '2026-03-02',
   'La que vale', 12.00, false, '00000000-0000-0000-0000-000000309aa0');

select is(
  (select id from fn_documentos_listar('00000000-0000-0000-0000-000000309001')
    where tipo = 'ruta' and vigente),
  '00000000-0000-0000-0000-0000003090d2'::uuid,
  'fn_documentos_listar · un solo documento de ruta sale vigente, y es siempre el mismo');

-- ── 3 · fn_documentos_estado_politica · cuál política rige ─────────────────
-- La política conserva la fecha del papel, así que dos versiones con la misma
-- `fecha_firma` son el caso NORMAL — lo dejó escrito la 0211 al agregar su
-- desempate por `created_at`. Aquí empatan también en `created_at`, que es lo
-- que la 0211 no podía prever.
insert into documentos_firmados
  (id, alcance, persona_id, tipo, fecha_firma, registrado_por)
values
  ('00000000-0000-0000-0000-0000003090e1', 'empresa', null, 'politica',
   '2026-04-01', '00000000-0000-0000-0000-000000309aa0'),
  ('00000000-0000-0000-0000-0000003090e2', 'empresa', null, 'politica',
   '2026-04-01', '00000000-0000-0000-0000-000000309aa0');

select is(
  (select id from fn_documentos_estado_politica()),
  '00000000-0000-0000-0000-0000003090e2'::uuid,
  'fn_documentos_estado_politica · la política que rige no la decide el orden físico de la tabla');

-- ── 4 · fn_educacion_espejo_comprobante · qué papel se refleja en la ficha ─
-- El índice único de esta tabla es sobre (asignacion_id, storage_path), NO
-- sobre el mes: dos comprobantes del mismo mes son legales, y empatan en
-- `mes_cubierto`. Es un trigger, así que la comprobación es sobre la columna
-- espejo que deja escrita.
--
-- Y acá el orden de inserción NO alcanza para hacer fallar el control: con el
-- índice `(asignacion_id, mes_cubierto)` puesto, el plan sale como `Index Scan
-- Backward` y devuelve el empate en un orden que, por casualidad, coincide con
-- el correcto. Eso es suerte del plan, no una garantía — y es justo lo que esta
-- migración viene a dejar de necesitar.
--
-- Así que se prueba lo que de verdad está en juego: que la respuesta no dependa
-- de CÓMO Postgres decida leer la tabla. `set local` solo dura esta transacción.
set local enable_indexscan = off;
set local enable_bitmapscan = off;
insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, vigente_desde, vigente_hasta,
   registrado_por)
values ('00000000-0000-0000-0000-0000003090f0', '00000000-0000-0000-0000-000000309001',
        300, 'Instituto 309', 600, '2026-03-01', '2026-12-31',
        '00000000-0000-0000-0000-000000309aa0');

insert into educacion_comprobantes
  (id, asignacion_id, storage_path, mes_cubierto, subido_por)
values
  ('00000000-0000-0000-0000-0000003090f1', '00000000-0000-0000-0000-0000003090f0',
   'educacion/el-otro.pdf', '2026-03-01', '00000000-0000-0000-0000-000000309aa0'),
  ('00000000-0000-0000-0000-0000003090f2', '00000000-0000-0000-0000-0000003090f0',
   'educacion/el-que-vale.pdf', '2026-03-01', '00000000-0000-0000-0000-000000309aa0');

select is(
  (select comprobante_url from asignaciones_educacion
    where id = '00000000-0000-0000-0000-0000003090f0'),
  'educacion/el-que-vale.pdf',
  'fn_educacion_espejo_comprobante · la ficha refleja siempre el mismo papel de los dos del mes');

select * from finish();
rollback;
