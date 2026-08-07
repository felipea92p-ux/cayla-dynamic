-- ============================================================================
-- 0172 · Los papeles firmados por fin se pueden subir
-- ============================================================================
--
-- QUÉ PROMETE
--   Que archivar un papel escaneado funcione. Concretamente:
--     · el cargo firmado de un memo disciplinario (bucket `expedientes`) —
--       hasta hoy NUNCA se pudo subir ninguno;
--     · reemplazar un comprobante de educación o un documento firmado que se
--       escaneó mal (buckets `comprobantes` y `documentos`) — la primera
--       subida sí funcionaba, corregirla no.
--
-- QUÉ ASUME
--   Que quien puede crear un archivo es exactamente quien puede reemplazarlo y
--   quien puede leerlo. Todas las políticas de acá repiten la condición de
--   permiso que ya existía en su bucket. No se abre ningún permiso nuevo a
--   nadie.
--
-- ── POR QUÉ FALLABA (medido, no deducido) ───────────────────────────────────
--
-- Supabase Storage (1.65.1) no escribe el objeto con un INSERT a secas. Escribe
-- esto, copiado del log del contenedor:
--
--     INSERT INTO storage.objects (name, owner, owner_id, bucket_id, metadata, version)
--     VALUES ($1,…,$6)
--     ON CONFLICT (name, bucket_id) DO UPDATE SET metadata = EXCLUDED.metadata, …
--     RETURNING *
--
-- Esa sentencia necesita TRES permisos, no uno:
--   · INSERT      — por la fila nueva.
--   · SELECT      — por el `RETURNING *`: Postgres aplica las políticas de
--                   lectura a las filas que devuelve.
--   · UPDATE      — por el `ON CONFLICT DO UPDATE`, cuando la ruta ya existe.
--
-- Los tres buckets tenían INSERT, SELECT y DELETE. De UPDATE, ninguna. Y la
-- política de SELECT de `expedientes` (mig. 0074) exigía además esto:
--
--     exists (select 1 from expediente_adjuntos a where a.storage_path = name)
--
-- o sea: para leer el objeto, el adjunto ya tiene que estar registrado. Pero el
-- adjunto se registra DESPUÉS de subir el archivo (`fn_expediente_adjuntar`).
-- Un círculo cerrado: no se podía escribir sin poder leer, no se podía leer sin
-- haber registrado, y no se podía registrar sin haber escrito. Por eso los
-- memos entregados llevaban semanas sin su cargo archivado — no era descuido de
-- nadie, era que el sistema no lo permitía.
--
-- Medido contra el Postgres local el 2026-08-06, misma sesión de admin, misma
-- ruta, `fn_expediente_puede_adjuntar` devolviendo true todo el tiempo:
--
--     INSERT simple, sin RETURNING                        → ACEPTADO
--     INSERT … RETURNING *                                → RECHAZADO
--     INSERT … ON CONFLICT DO NOTHING                     → RECHAZADO
--     INSERT … ON CONFLICT DO UPDATE  (lo que hace Storage) → RECHAZADO
--     el mismo, con el adjunto ya registrado a mano       → ACEPTADO
--
-- Y después del arreglo de la SELECT, con y sin política de UPDATE:
--
--     objeto nuevo,  sin política UPDATE                  → ACEPTADO
--     objeto existente, sin política UPDATE               → RECHAZADO
--     objeto existente, con política UPDATE               → ACEPTADO
--
-- Lo que más costó del diagnóstico: el mensaje de Postgres nombra la tabla pero
-- no dice cuál de las políticas faltó, así que el fallo se leía como un problema
-- de permisos de la persona. No lo era.
--
-- ── POR QUÉ SE ELIGIÓ ASÍ ───────────────────────────────────────────────────
--
-- Para el círculo de `expedientes` se descartó quitar el `exists`: dejaría
-- legible cualquier archivo suelto en una carpeta válida. En su lugar se agrega
-- una segunda vía —`owner_id = auth.uid()`— que cubre exactamente el hueco real:
-- el instante entre que alguien sube un papel y lo registra. Quien lo subió
-- puede ver lo suyo; todos los demás siguen necesitando que el adjunto exista.
-- La condición de fondo (`fn_expediente_puede_adjuntar`) se mantiene delante y
-- se aplica a las dos vías: sin mando sobre ese documento no se ve nada, aunque
-- el archivo lo haya subido uno mismo.
--
-- Para el upsert se descartó quitarlo desde la pantalla: en Educación y
-- Documentación la ruta se deriva del id de la fila, así que corregir un
-- escaneo cae siempre sobre la misma ruta. Sin upsert habría que borrar antes,
-- y entre el borrado y la nueva subida el legajo se queda sin papel.
--
-- USING y WITH CHECK llevan la misma condición a propósito: USING decide qué
-- fila se puede tocar, WITH CHECK en qué se puede convertir. Con solo la
-- primera se podría mover un archivo a una ruta sobre la que no hay permiso.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Se vuelven a aplicar los bloques de políticas de la 0074 (expedientes),
--   la 0136 (comprobantes) y la 0157 (documentos), y se borran las tres nuevas:
--     drop policy if exists expedientes_update  on storage.objects;
--     drop policy if exists comprobantes_update on storage.objects;
--     drop policy if exists documentos_update   on storage.objects;
--   Revertir deja el sistema otra vez sin poder archivar ningún cargo.
--
-- Idempotente: cada política se borra antes de crearse.
-- ============================================================================

-- ── 1 · El círculo de los expedientes ───────────────────────────────────────
-- `owner_id` es TEXT en storage.objects, de ahí el cast: sin él la política ni
-- siquiera se crea («operator does not exist: text = uuid»).
drop policy if exists expedientes_select on storage.objects;
create policy expedientes_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'expedientes'
    and fn_expediente_puede_adjuntar(name)
    and (
      exists (select 1 from expediente_adjuntos a where a.storage_path = storage.objects.name)
      -- El hueco entre subir el papel y registrarlo: sin esta línea la subida
      -- no puede ni completarse, porque Storage lee lo que acaba de escribir.
      or owner_id = auth.uid()::text
    )
  );

-- ── 2 · Reemplazar un papel ya subido, en los tres buckets ──────────────────
-- Misma condición que la política de INSERT de cada uno.
drop policy if exists expedientes_update on storage.objects;
create policy expedientes_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'expedientes' and fn_expediente_puede_adjuntar(name))
  with check (bucket_id = 'expedientes' and fn_expediente_puede_adjuntar(name));

drop policy if exists comprobantes_update on storage.objects;
create policy comprobantes_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'comprobantes'
    and split_part(name, '/', 1) = 'educacion'
    and fn_es_admin_o_lider() is true
  )
  with check (
    bucket_id = 'comprobantes'
    and split_part(name, '/', 1) = 'educacion'
    and fn_es_admin_o_lider() is true
  );

drop policy if exists documentos_update on storage.objects;
create policy documentos_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'documentos'
    and split_part(name, '/', 1) = 'documentos'
    and fn_es_admin_o_lider() is true
  )
  with check (
    bucket_id = 'documentos'
    and split_part(name, '/', 1) = 'documentos'
    and fn_es_admin_o_lider() is true
  );

-- ── 3 · De paso: el borrado de expedientes, null-safe ───────────────────────
-- `expedientes_delete` era el único guard escrito `and fn_es_admin_o_lider()`
-- en vez de `is true`. Hoy esa función ya no devuelve null (mig. 0078), así que
-- no había agujero abierto; se corrige igual porque la forma es la regla, y una
-- excepción suelta es la que se copia el día que sí importe.
drop policy if exists expedientes_delete on storage.objects;
create policy expedientes_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'expedientes' and fn_es_admin_o_lider() is true);

insert into migraciones_aplicadas (numero, nombre)
values (172, 'los_papeles_firmados_por_fin_se_pueden_subir')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
