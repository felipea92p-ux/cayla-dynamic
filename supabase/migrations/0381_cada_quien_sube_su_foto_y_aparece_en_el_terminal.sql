-- ============================================================================
-- 0381 — Cada quien sube su foto desde «Lo mío», y aparece junto a su nombre
-- en el terminal de marcaje
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE
--   Que cada colaboradora pueda subir su propia foto desde `/mio`, y que esa
--   foto aparezca junto a su nombre en la grilla del terminal — para reducir el
--   error de tocar a la persona equivocada por apuro, sobre todo entre nombres
--   parecidos. Quien no tenga foto sigue viéndose exactamente igual que hoy
--   (solo el nombre): esto es aditivo, nunca un requisito para marcar.
--
-- QUÉ ASUME
--   `fn_persona_actual_id()` y `fn_es_admin_o_lider()` (0078), la vista
--   `terminal_roster` (0285, ya sin `pin_hash` desde la 0375).
--
-- POR QUÉ AHORA
--   Salió de la comparación contra BambooHR/Rippling/UKG del 2026-09-03
--   («Selector por nombre + foto en el terminal» — de esa misma comparación
--   solo se había construido el tablón de anuncios, 0351). Quedó sin hacer
--   hasta hoy, a pedido de Felipe.
--
-- POR QUÉ BUCKET PÚBLICO Y NO PRIVADO CON URL FIRMADA (como `comprobantes` o
-- `expedientes`)
--   El terminal necesita pintar TODAS las fotos de su sede sin depender de
--   volver a preguntarle al servidor, porque su diseño entero asume que puede
--   pasar horas o días sin red y seguir marcando con lo que ya tiene cacheado
--   en IndexedDB. Una URL firmada vence; forzar su renovación periódica solo
--   para que la foto no se rompa sería complejidad sin ninguna ganancia real
--   de seguridad, porque el dato que protege (un rostro) ya es visible a
--   simple vista en la propia tienda, sin login, en la misma Mac mini — la
--   misma razón por la que `terminal_roster` expone nombre y apellido sin
--   pedir sesión individual. Ya existe precedente de esta forma en este mismo
--   repositorio: el buzón `fotos-productos` (0225) también es público.
--   `comprobantes`/`expedientes` sí necesitan URL firmada porque ahí SÍ hay un
--   dato que nadie ve por su cuenta (un DNI, un diagnóstico médico).
--
-- POR QUÉ EL PATH LLEVA UN SUFIJO DE TIEMPO, Y NO UN NOMBRE FIJO
--   `perfil/<persona_id>/<epoch_ms>.jpg`. Con un nombre fijo, reemplazar la
--   foto reutilizaría la misma URL y el navegador (o un CDN de por medio)
--   podría seguir sirviendo la versión vieja desde caché. El costo es un
--   archivo huérfano por cada reemplazo — insignificante en tamaño y en
--   frecuencia (~30 personas, unas pocas fotos en la vida del sistema) — así
--   que no se limpia solo: no vale la complejidad de borrar el archivo
--   anterior antes de confirmar que el nuevo quedó enlazado.
--
-- POR QUÉ LA COLUMNA SE LLAMA `foto_url` Y GUARDA UNA RUTA, NO UNA URL
--   Misma convención que `comprobante_url` (0136): una ruta relativa dentro
--   del bucket. El cliente arma la URL pública con
--   `storage.from('fotos-perfil').getPublicUrl(ruta)`. Así la fila no depende
--   del dominio del proyecto de Supabase.
--
-- QUÉ NO HACE
--   No pide foto para marcar, no bloquea nada, no cambia `fn_registrar_marcaje`.
--   Quien nunca suba una foto sigue marcando exactamente igual que hoy.
--
-- CÓMO SE REVIERTE
--   drop policy fotos_perfil_insert, fotos_perfil_update, fotos_perfil_select,
--     fotos_perfil_delete on storage.objects;
--   drop function fn_actualizar_foto_perfil(uuid, text);
--   drop function fn_foto_perfil_puede_escribir(text);
--   alter table personas drop column foto_url;
--   delete from storage.buckets where id = 'fotos-perfil';  -- vacíalo antes
--   (y volver a pegar el `create or replace view terminal_roster` de la 0375
--   para quitarle la columna)
-- ============================================================================

-- ── A · La columna ───────────────────────────────────────────────────────────
alter table personas add column if not exists foto_url text;

comment on column personas.foto_url is
  'Ruta dentro del bucket PÚBLICO «fotos-perfil», con la forma '
  'perfil/<persona_id>/<archivo>.jpg. Se resuelve con getPublicUrl, nunca con '
  'URL firmada — ver 0381 para por qué este bucket es público a propósito. '
  'Se actualiza únicamente vía fn_actualizar_foto_perfil.';

-- ── B · El bucket ────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'fotos-perfil', 'fotos-perfil', true,
  3145728,  -- 3 MB: de sobra para un retrato ya comprimido a JPEG en el navegador
  array['image/jpeg']
)
on conflict (id) do update
  set public             = true,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ── C · ¿Quién puede subir, reemplazar o quitar SU foto? ────────────────────
-- El path es "perfil/<persona_id>/<archivo>": la carpeta identifica de quién
-- es. Se valida que el segundo segmento sea un uuid ANTES de castear — un path
-- con basura debe negarse limpio (misma forma que fn_educacion_puede_ver, 0136).
create or replace function fn_foto_perfil_puede_escribir(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_persona text;
begin
  if split_part(p_path, '/', 1) <> 'perfil' then return false; end if;
  v_persona := split_part(p_path, '/', 2);
  if v_persona !~ '^[0-9a-fA-F-]{36}$' then return false; end if;

  -- DO/admin puede cargarle la foto a cualquiera (por si alguien nunca entra a
  -- «Lo mío»); cada quien puede cargar únicamente la suya.
  if fn_es_admin_o_lider() is true then return true; end if;
  return v_persona::uuid = fn_persona_actual_id();
end;
$$;

grant execute on function fn_foto_perfil_puede_escribir(text) to authenticated;

-- Las CUATRO políticas, no solo INSERT: Supabase Storage sube (y reemplaza)
-- con `insert … on conflict … do update … returning *`, que exige INSERT,
-- UPDATE **y** SELECT sobre storage.objects — sin las tres, la subida falla
-- con «row-level security policy» aunque INSERT por sí solo esté bien (lección
-- ya pagada una vez con el cargo firmado del memo disciplinario, 0136/prueba
-- 136). DELETE se agrega por paridad, para quien quiera quitar su foto sin
-- reemplazarla.
drop policy if exists fotos_perfil_insert on storage.objects;
create policy fotos_perfil_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'fotos-perfil' and fn_foto_perfil_puede_escribir(name));

drop policy if exists fotos_perfil_update on storage.objects;
create policy fotos_perfil_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'fotos-perfil' and fn_foto_perfil_puede_escribir(name))
  with check (bucket_id = 'fotos-perfil' and fn_foto_perfil_puede_escribir(name));

drop policy if exists fotos_perfil_select on storage.objects;
create policy fotos_perfil_select on storage.objects
  for select to authenticated
  using (bucket_id = 'fotos-perfil' and fn_foto_perfil_puede_escribir(name));

drop policy if exists fotos_perfil_delete on storage.objects;
create policy fotos_perfil_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'fotos-perfil' and fn_foto_perfil_puede_escribir(name));

-- ── D · Enlazar el archivo subido con la fila de `personas` ─────────────────
-- Única puerta de escritura sobre `personas.foto_url` — igual que el resto del
-- sistema, la tabla no acepta UPDATE directo desde el cliente sobre este campo.
create or replace function fn_actualizar_foto_perfil(p_persona_id uuid, p_foto_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true and p_persona_id <> fn_persona_actual_id() then
    raise exception 'Solo puedes actualizar tu propia foto.';
  end if;

  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no existe o no está activa.';
  end if;

  -- Null es válido: es la forma de "quitar mi foto" sin subir una nueva.
  if p_foto_url is not null and split_part(p_foto_url, '/', 1) <> 'perfil' then
    raise exception 'La ruta de la foto no pertenece al bucket de perfiles.';
  end if;

  update personas set foto_url = p_foto_url where id = p_persona_id;
end;
$$;

grant execute on function fn_actualizar_foto_perfil(uuid, text) to authenticated;

-- ── E · El terminal también la ve ────────────────────────────────────────────
-- Misma vista de siempre (0285/0375), una columna más. `terminal_roster` sigue
-- siendo la única superficie que una sesión de terminal puede leer de
-- `personas` — agregar la columna acá y no abrir `personas` es lo que mantiene
-- esa garantía (0291: RLS filtra filas, no columnas).
drop view if exists terminal_roster;

create view terminal_roster
with (security_invoker = false)
as
select
  p.id,
  p.nombres,
  p.apellidos,
  p.foto_url,
  s.codigo as sede_codigo,
  s.nombre  as sede_nombre
from personas p
join sedes s on s.id = p.sede_base_id
where p.estado = 'activo'
  and fn_sede_actual_terminal() is not null
  and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true);

comment on view terminal_roster is
  'Lo único que el kiosco de marcaje necesita ver de una persona: cómo se '
  'llama, de qué sede es y su foto (0381). Existe porque RLS filtra filas y no '
  'columnas (0285).';

revoke all on terminal_roster from public, anon;
grant select on terminal_roster to authenticated;

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (381, 'cada_quien_sube_su_foto_y_aparece_en_el_terminal')
on conflict (numero) do nothing;

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) from information_schema.columns
    where table_name = 'personas' and column_name = 'foto_url') = 1
    as tiene_la_columna,
  (select public from storage.buckets where id = 'fotos-perfil') is true
    as el_bucket_es_publico,
  (select count(*) from pg_policies
    where tablename = 'objects' and schemaname = 'storage'
      and policyname like 'fotos_perfil_%') = 4
    as las_cuatro_politicas_existen,
  (select count(*) from information_schema.columns
    where table_name = 'terminal_roster' and column_name = 'foto_url') = 1
    as el_terminal_ve_la_foto,
  (select count(*) from information_schema.columns
    where table_name = 'terminal_roster'
      and column_name in ('documento', 'sueldo_base_legal', 'email', 'pin_hash')) = 0
    as sigue_sin_exponer_nada_sensible;
