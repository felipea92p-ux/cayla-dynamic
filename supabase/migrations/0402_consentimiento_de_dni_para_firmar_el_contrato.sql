-- ============================================================================
-- 0402 — Consentimiento de datos personales al subir el DNI, antes de firmar
-- ============================================================================
--
-- QUÉ PROMETE
--   Antes de poder firmar su propio contrato desde /mio/contrato, la
--   colaboradora/practicante debe subir una copia de su DNI y marcar un
--   checkbox de consentimiento de tratamiento de datos personales (Ley N.°
--   29733) — sin las dos cosas, la pantalla no muestra el editor de firma.
--   `fn_registrar_mi_dni` deja constancia de CUÁNDO se aceptó y CON QUÉ
--   archivo, una fila por persona (igual que `firmas_escaneadas`): si vuelve
--   a subir un DNI más adelante, la fila se actualiza, no se duplica.
--
-- QUÉ ASUME
--   Que el consentimiento es POR PERSONA, no por contrato: el texto que
--   acepta ("autorizo a CAYLA S.A.C. a tratar este documento y mis demás
--   datos personales con la finalidad de verificar mi identidad y dejar
--   constancia de mi aceptación de los términos del contrato") no nombra un
--   contrato en particular, así que una vez dado no hace falta repetirlo en
--   cada renovación — el mismo criterio que ya usa la firma guardada
--   (`firmas_escaneadas`, reutilizada en cualquier documento que la lleve).
--
-- QUÉ NO HACE
--   No bloquea `fn_set_mi_firma` en la base: esa función guarda LA firma de
--   la persona, reutilizada también en memos disciplinarios y en política
--   salarial (ver 0398) — no es exclusiva del contrato, así que condicionarla
--   al DNI bloquearía firmar un memo. La restricción "sin DNI no hay botón de
--   firma" vive en la pantalla (/mio/contrato), que es el único lugar donde
--   esa regla aplica.
--
-- POR QUÉ ASÍ
--   Mismo molde que `solicitudes-perfil` (0399, punto D): bucket privado +
--   función `puede_escribir` que valida que la carpeta del archivo sea la
--   propia persona (o admin/líder) + cuatro políticas sobre storage.objects,
--   porque Supabase Storage necesita INSERT+UPDATE+SELECT para el upsert que
--   hace `subirArchivoConProgreso` (x-upsert: true).
--
-- CÓMO SE REVIERTE
--   drop policy if exists dni_consentimiento_insert, dni_consentimiento_update,
--     dni_consentimiento_select, dni_consentimiento_delete on storage.objects;
--   drop function if exists fn_dni_consentimiento_puede_escribir(text);
--   delete from storage.buckets where id = 'dni-consentimiento'; -- vacíalo antes
--   drop function if exists fn_mi_consentimiento_dni();
--   drop function if exists fn_registrar_mi_dni(text);
--   drop table if exists consentimientos_dni;
-- ============================================================================


-- ── A · La constancia: una fila por persona ─────────────────────────────────
create table if not exists consentimientos_dni (
  persona_id   uuid primary key references personas(id),
  storage_path text not null,
  aceptado_at  timestamptz not null default now()
);

comment on table consentimientos_dni is
  'Constancia de que la persona subió su DNI y aceptó el tratamiento de sus '
  'datos personales (Ley N.° 29733) antes de firmar su contrato. Una fila por '
  'persona — se actualiza si vuelve a subir, no se duplica. Escritura solo vía '
  'fn_registrar_mi_dni.';

alter table consentimientos_dni enable row level security;

drop policy if exists consentimientos_dni_select_propia on consentimientos_dni;
create policy consentimientos_dni_select_propia on consentimientos_dni
  for select to authenticated using (persona_id = fn_persona_actual_id());

drop policy if exists consentimientos_dni_select_admin_lider on consentimientos_dni;
create policy consentimientos_dni_select_admin_lider on consentimientos_dni
  for select to authenticated using (fn_es_admin_o_lider() is true);

grant select on consentimientos_dni to authenticated;
revoke all on consentimientos_dni from anon, public;
-- Sin policies de insert/update/delete: toda escritura pasa por fn_registrar_mi_dni.


-- ── B · Guardar MI consentimiento ────────────────────────────────────────────
create or replace function fn_registrar_mi_dni(p_storage_path text)
returns void language plpgsql security definer set search_path = public as $$
declare v_yo uuid;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;
  if p_storage_path is null or trim(p_storage_path) = '' then
    raise exception 'Falta la ruta del archivo subido.';
  end if;
  if split_part(p_storage_path, '/', 1) <> v_yo::text then
    raise exception 'La ruta del archivo no corresponde a tu persona.';
  end if;

  insert into consentimientos_dni (persona_id, storage_path, aceptado_at)
  values (v_yo, p_storage_path, now())
  on conflict (persona_id) do update
    set storage_path = excluded.storage_path, aceptado_at = now();
end;
$$;
grant execute on function fn_registrar_mi_dni(text) to authenticated;
revoke execute on function fn_registrar_mi_dni(text) from public, anon;

-- ── C · Ver MI consentimiento (para saber si ya puede firmar) ───────────────
create or replace function fn_mi_consentimiento_dni()
returns table(storage_path text, aceptado_at timestamptz)
language sql stable security definer set search_path = public as $$
  select storage_path, aceptado_at from consentimientos_dni where persona_id = fn_persona_actual_id();
$$;
grant execute on function fn_mi_consentimiento_dni() to authenticated;
revoke execute on function fn_mi_consentimiento_dni() from public, anon;


-- ── D · El bucket: privado, una carpeta por persona ─────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'dni-consentimiento', 'dni-consentimiento', false,
  8388608, -- 8 MB: de sobra para una foto del DNI o un PDF escaneado
  array['image/jpeg','image/png','application/pdf']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Path: <persona_id>/<epoch_ms>-<random>.<ext> — el bucket entero es de DNI,
-- así que no hace falta un prefijo fijo como "solicitud/" (comparar con
-- fn_solicitud_perfil_puede_escribir, 0399).
create or replace function fn_dni_consentimiento_puede_escribir(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_persona text;
begin
  v_persona := split_part(p_path, '/', 1);
  if v_persona !~ '^[0-9a-fA-F-]{36}$' then return false; end if;

  if fn_es_admin_o_lider() is true then return true; end if;
  return v_persona::uuid = fn_persona_actual_id();
end;
$$;

grant execute on function fn_dni_consentimiento_puede_escribir(text) to authenticated;

-- Las CUATRO políticas — Supabase Storage sube con
-- insert ... on conflict ... do update ... returning *, que exige INSERT,
-- UPDATE y SELECT sobre storage.objects (lección ya pagada en 0136/0381).
drop policy if exists dni_consentimiento_insert on storage.objects;
create policy dni_consentimiento_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'dni-consentimiento' and fn_dni_consentimiento_puede_escribir(name));

drop policy if exists dni_consentimiento_update on storage.objects;
create policy dni_consentimiento_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'dni-consentimiento' and fn_dni_consentimiento_puede_escribir(name))
  with check (bucket_id = 'dni-consentimiento' and fn_dni_consentimiento_puede_escribir(name));

drop policy if exists dni_consentimiento_select on storage.objects;
create policy dni_consentimiento_select on storage.objects
  for select to authenticated
  using (bucket_id = 'dni-consentimiento' and fn_dni_consentimiento_puede_escribir(name));

drop policy if exists dni_consentimiento_delete on storage.objects;
create policy dni_consentimiento_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'dni-consentimiento' and fn_dni_consentimiento_puede_escribir(name));


insert into migraciones_aplicadas (numero, nombre) values (402, 'consentimiento_de_dni_para_firmar_el_contrato')
on conflict (numero) do nothing;
