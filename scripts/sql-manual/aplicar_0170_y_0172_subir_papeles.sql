-- ============================================================================
-- PEGAR EN EL SQL EDITOR DE SUPABASE (producción) — migraciones 0170 y 0172
-- ============================================================================
--
-- QUÉ ARREGLA
--   Que se pueda archivar un papel escaneado. Hoy, en producción:
--     · el cargo firmado de un memo disciplinario NO se puede subir — nunca se
--       pudo, desde que el módulo existe;
--     · un comprobante de educación o un documento firmado mal escaneado NO se
--       puede corregir (la primera subida sí entra, reemplazarla no);
--     · el acta de un descanso sustitutorio NO acepta una foto de iPhone.
--
-- Van las dos juntas y en este orden porque así están numeradas. Ninguna
-- depende de la otra: si una fallara, la otra sigue siendo válida.
--
-- ES SEGURO PEGARLO DOS VECES. Todo es `create or replace` o `drop … create`.
--
-- QUÉ NO HACE
--   No toca ni un dato. No cambia ningún cálculo de planilla. No le da permiso
--   a nadie que no lo tuviera: cada política nueva repite la condición que ya
--   existía en la política de INSERT de su bucket.
--
-- CÓMO COMPROBAR QUE QUEDÓ (pegar después, debe devolver 4 filas):
--
--     select policyname, cmd from pg_policies
--      where schemaname='storage' and tablename='objects'
--        and policyname in ('expedientes_select','expedientes_update',
--                           'comprobantes_update','documentos_update');
--
--   Y en la pantalla: Disciplina → Entregados → "Subir cargo" en cualquiera de
--   los tres memos. Debe dejar elegir el archivo y guardarlo.
--
-- Generado el 2026-08-06. Fuente:
--   supabase/migrations/0170_el_acta_acepta_la_foto_del_iphone.sql
--   supabase/migrations/0172_los_papeles_firmados_por_fin_se_pueden_subir.sql
-- El porqué largo de cada decisión está en las cabeceras de esos dos archivos.
-- ============================================================================

begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 0170 · El acta de descanso acepta la foto tal como sale del teléfono
-- ════════════════════════════════════════════════════════════════════════════
-- Sin esto, en Feriados las fotos .HEIC salían en gris en el diálogo de
-- archivos: no se podían ni seleccionar, y la pantalla no daba ningún error.

create or replace function fn_subir_acta_descanso(
  p_referencia text,
  p_dataurl text,
  p_nombre text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_ref text := trim(p_referencia);
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede subir un acta.';
  end if;
  if v_ref is null or length(v_ref) < 3 then
    raise exception 'La referencia del acta es obligatoria.';
  end if;
  -- PDF o imagen: es un papel escaneado o fotografiado, nada más. HEIC/HEIF
  -- entran porque son lo que produce la cámara de un iPhone sin tocar nada.
  if p_dataurl is not null
     and p_dataurl !~ '^data:(application/pdf|image/(png|jpeg|webp|heic|heif));base64,' then
    raise exception 'Formato inválido: el acta debe ser un PDF o una imagen (PNG, JPEG, WEBP o HEIC).';
  end if;
  if p_dataurl is not null and length(p_dataurl) > 4194304 then
    raise exception 'El archivo pesa demasiado (máximo ~3 MB). Escanéalo en menor resolución o súbelo como PDF.';
  end if;

  insert into actas_descanso_sustitutorio (referencia, archivo_base64, archivo_nombre, subida_por)
  values (v_ref, p_dataurl, nullif(trim(p_nombre), ''), fn_persona_actual_id())
  on conflict (referencia) do update set
    archivo_base64 = excluded.archivo_base64,
    archivo_nombre = excluded.archivo_nombre,
    subida_por = excluded.subida_por,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

insert into migraciones_aplicadas (numero, nombre)
values (170, 'el_acta_acepta_la_foto_del_iphone')
on conflict (numero) do nothing;


-- ════════════════════════════════════════════════════════════════════════════
-- 0172 · Los papeles firmados por fin se pueden subir
-- ════════════════════════════════════════════════════════════════════════════
-- Storage escribe el objeto con `INSERT … ON CONFLICT DO UPDATE … RETURNING *`.
-- Esa forma necesita permiso de INSERT, de SELECT (por el RETURNING) y de
-- UPDATE (por el ON CONFLICT). Faltaban los dos últimos.

-- ── 1 · El círculo de los expedientes ───────────────────────────────────────
-- La política de SELECT exigía que el adjunto YA estuviera registrado, y ese
-- registro se crea DESPUÉS de subir el archivo. `owner_id` es TEXT: sin el cast
-- la política ni se crea.
drop policy if exists expedientes_select on storage.objects;
create policy expedientes_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'expedientes'
    and fn_expediente_puede_adjuntar(name)
    and (
      exists (select 1 from expediente_adjuntos a where a.storage_path = storage.objects.name)
      or owner_id = auth.uid()::text
    )
  );

-- ── 2 · Reemplazar un papel ya subido, en los tres buckets ──────────────────
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
drop policy if exists expedientes_delete on storage.objects;
create policy expedientes_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'expedientes' and fn_es_admin_o_lider() is true);

insert into migraciones_aplicadas (numero, nombre)
values (172, 'los_papeles_firmados_por_fin_se_pueden_subir')
on conflict (numero) do nothing;

commit;

notify pgrst, 'reload schema';
