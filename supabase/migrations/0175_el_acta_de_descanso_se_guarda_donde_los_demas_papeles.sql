-- ============================================================================
-- 0175 · El acta de descanso se guarda donde los demás papeles
-- ============================================================================
--
-- QUÉ PROMETE
--   Que un acta firmada se pueda subir hasta 50 MB, como el cargo de un memo o
--   un contrato, en vez de los ~3 MB de hoy. Y que las actas que ya están
--   subidas se sigan viendo exactamente igual, sin mover ni un dato.
--
-- QUÉ ASUME
--   Que quien puede subir un acta es admin o líder de DO — la misma condición
--   que ya exigía `fn_subir_acta_descanso`. No se abre ningún permiso nuevo.
--
-- ── POR QUÉ ─────────────────────────────────────────────────────────────────
--
-- El sistema guardaba papeles firmados de DOS maneras distintas. El cargo de un
-- memo y el contrato de una persona van al almacén de archivos, con 50 MB de
-- tope. El acta de un descanso sustitutorio —que es el mismo tipo de cosa: un
-- papel escaneado que respalda un acuerdo— iba como TEXTO dentro de una columna
-- de la base, y por eso tenía que caber en ~3 MB.
--
-- Ese tope no era una decisión sobre las actas: era la consecuencia de dónde se
-- guardaban. Un escaneo normal de varias hojas lo pasa sin esfuerzo, y la
-- persona se encontraba con «el máximo es 3 MB» sin ninguna forma razonable de
-- cumplirlo salvo degradar el escaneo del papel que justamente hay que poder
-- leer después.
--
-- Guardar archivos en una columna tiene un costo que no se ve hasta que duele:
-- cada respaldo de la base carga con los PDFs, y cualquier consulta que traiga
-- esa columna se lleva megabytes por la red de la sede.
--
-- ── POR QUÉ SE ELIGIÓ ASÍ ───────────────────────────────────────────────────
--
-- Se descartó subir el tope y dejarlas en la base: habría desbloqueado el caso
-- de hoy consolidando la causa, y el sistema seguiría con dos formas de guardar
-- lo mismo — que es justo lo que hace que un cambio futuro haya que pensarlo
-- dos veces, una por cada camino.
--
-- Se descartó meterlas en el bucket `documentos`: sus políticas y su
-- `fn_documento_puede_ver` están atadas al prefijo 'documentos/' y a buscar la
-- fila en `documentos_firmados` por id. Un acta no vive ahí, así que habría
-- que aflojar esa función para un caso que no le corresponde. Un bucket propio
-- con la condición de permiso escrita entera es más fácil de leer y no toca
-- nada que hoy funciona.
--
-- Se descartó mover las actas ya subidas. `archivo_base64` se queda y se sigue
-- leyendo: las dos actas que hay en producción siguen abriéndose el lunes igual
-- que el viernes, sin script de migración de datos que pueda salir a medias.
-- Lo nuevo va al almacén; lo viejo se lee donde está. La columna se podrá
-- borrar el día que no quede ninguna, y esa es una decisión de otro día.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   La pantalla vuelve a `fn_subir_acta_descanso` y nada se rompe: esa función
--   sigue existiendo y funcionando. Para deshacerlo del todo:
--     drop function if exists fn_registrar_acta_descanso(text, text, text);
--     drop policy if exists actas_insert on storage.objects;   -- y select/update/delete
--     alter table actas_descanso_sustitutorio drop column storage_path;
--   Las actas subidas al almacén dejarían de verse; las de base64, no.
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================

-- ── 1 · Dónde vive ahora el archivo ─────────────────────────────────────────
alter table actas_descanso_sustitutorio
  add column if not exists storage_path text;

comment on column actas_descanso_sustitutorio.storage_path is
  'Ruta en el bucket «actas». Las actas subidas antes de la 0175 tienen esto en null y su archivo en archivo_base64; se leen de ahí.';

-- Estado imposible: un acta con el papel en los dos sitios a la vez. Cuál de
-- los dos es el bueno no lo sabría nadie, y el que se muestre dependería del
-- orden de un `coalesce` — una decisión de negocio escondida en un detalle.
alter table actas_descanso_sustitutorio
  drop constraint if exists chk_acta_un_solo_archivo;
alter table actas_descanso_sustitutorio
  add constraint chk_acta_un_solo_archivo
  check (archivo_base64 is null or storage_path is null);

-- ── 2 · El bucket ───────────────────────────────────────────────────────────
-- Privado y con la misma lista de formatos y el mismo tope que los otros tres.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('actas', 'actas', false, 52428800,
        array['image/jpeg','image/png','image/heic','image/webp','application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Las cuatro políticas, con la MISMA condición: quien puede subir un acta puede
-- verla, reemplazarla y borrarla. Van las cuatro porque el almacén escribe con
-- `INSERT … ON CONFLICT DO UPDATE … RETURNING *`, que necesita INSERT, SELECT y
-- UPDATE a la vez (ver 0172 — sin eso no entra ni el primer archivo).
drop policy if exists actas_insert on storage.objects;
create policy actas_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'actas' and fn_es_admin_o_lider() is true);

drop policy if exists actas_select on storage.objects;
create policy actas_select on storage.objects
  for select to authenticated
  using (bucket_id = 'actas' and fn_es_admin_o_lider() is true);

drop policy if exists actas_update on storage.objects;
create policy actas_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'actas' and fn_es_admin_o_lider() is true)
  with check (bucket_id = 'actas' and fn_es_admin_o_lider() is true);

drop policy if exists actas_delete on storage.objects;
create policy actas_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'actas' and fn_es_admin_o_lider() is true);

-- ── 3 · Anotar el acta subida al almacén ────────────────────────────────────
-- El archivo ya está arriba cuando esto corre; acá solo se registra dónde. Si
-- el acta tenía su papel en base64, se limpia esa columna: el nuevo reemplaza
-- al viejo, y el constraint de arriba no admite los dos.
create or replace function fn_registrar_acta_descanso(
  p_referencia text,
  p_path text,
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
  if p_path is null or length(trim(p_path)) = 0 then
    raise exception 'Falta la ruta del archivo subido.';
  end if;

  insert into actas_descanso_sustitutorio
         (referencia, storage_path, archivo_base64, archivo_nombre, subida_por)
  values (v_ref, trim(p_path), null, nullif(trim(p_nombre), ''), fn_persona_actual_id())
  on conflict (referencia) do update set
    storage_path   = excluded.storage_path,
    archivo_base64 = null,
    archivo_nombre = excluded.archivo_nombre,
    subida_por     = excluded.subida_por,
    updated_at     = now()
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function fn_registrar_acta_descanso(text, text, text) to authenticated;

-- ── 4 · Las dos consultas de lectura, ahora con los dos orígenes ────────────
-- `tiene_archivo` y el peso dejan de mirar solo el base64. El peso de lo que
-- vive en el almacén se lee de ahí: si se dejara en 0, la lista diría «0 KB»
-- para un PDF de 8 MB y parecería que la subida no guardó nada.
create or replace function fn_actas_descanso()
returns table (
  referencia text, archivo_nombre text, tiene_archivo boolean,
  peso_kb int, actualizado timestamptz, registros int
)
language sql stable security definer set search_path = public
as $$
  select a.referencia, a.archivo_nombre,
         (a.archivo_base64 is not null or a.storage_path is not null),
         coalesce(
           (length(a.archivo_base64) / 1024)::int,
           (select (o.metadata->>'size')::int / 1024
              from storage.objects o
             where o.bucket_id = 'actas' and o.name = a.storage_path),
           0),
         a.updated_at,
         (select count(*)::int from feriados_descanso_sustitutorio d where d.acta_ref = a.referencia)
  from actas_descanso_sustitutorio a
  where fn_es_admin_o_lider()
  order by a.updated_at desc;
$$;
grant execute on function fn_actas_descanso() to authenticated;

-- Dónde está el papel de UN acta. Devuelve la ruta del almacén si la tiene, y
-- si no el data URL de siempre; la pantalla decide cómo abrirlo según cuál sea.
-- Se agrega una función en vez de cambiar `fn_acta_descanso`, que devuelve
-- `text` y seguiría sirviendo el base64 sin enterarse de que ahora hay dos
-- sitios posibles.
create or replace function fn_acta_descanso_ubicacion(p_referencia text)
returns table (storage_path text, dataurl text)
language sql stable security definer set search_path = public
as $$
  select a.storage_path, a.archivo_base64
  from actas_descanso_sustitutorio a
  where a.referencia = trim(p_referencia) and fn_es_admin_o_lider();
$$;
grant execute on function fn_acta_descanso_ubicacion(text) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (175, 'el_acta_de_descanso_se_guarda_donde_los_demas_papeles')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
