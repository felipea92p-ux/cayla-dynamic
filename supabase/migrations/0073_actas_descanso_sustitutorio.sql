-- ============================================================================
-- 0073 — Actas firmadas del descanso sustitutorio
-- ----------------------------------------------------------------------------
-- Hasta ahora `acta_ref` era solo un texto: decía que el acta existía, pero el
-- documento vivía fuera del sistema. Ante una fiscalización eso no sirve — hay
-- que poder mostrar el papel firmado.
--
-- EL ACTA ES UNA, LOS REGISTROS SON MUCHOS. El acuerdo de Taller LIM cubre 4
-- personas × 2 feriados = 8 filas en feriados_descanso_sustitutorio, pero es UN
-- solo documento firmado. Por eso el archivo NO va como columna en esa tabla:
-- serían 8 copias del mismo PDF que además hay que mantener sincronizadas.
-- Va en su propia tabla, identificada por la referencia que ya se escribe.
--
-- SE GUARDA COMO DATA-URL EN LA BASE, no en Storage. Es el mismo patrón que
-- 0065 usa para la firma escaneada: una sola forma de guardar documentos en el
-- sistema vale más que la óptima-pero-distinta. Se topa en 4 MB de base64
-- (~3 MB de archivo) para que la tabla no se vuelva impagable.
--
-- EL VÍNCULO ES POR TEXTO (actas.referencia = dcs.acta_ref), no por id. Se eligió
-- así para no migrar las filas ya cargadas ni obligar a crear el acta antes del
-- acuerdo: se registra el acuerdo hoy y se sube el papel cuando vuelva firmado.
-- El riesgo de esa decisión son las referencias mal tipeadas; se contiene en la
-- pantalla, que ofrece las referencias existentes en una lista en vez de texto libre.
--
-- Reversible: soltar la tabla y las tres funciones.
-- ============================================================================

create table if not exists actas_descanso_sustitutorio (
  id uuid primary key default gen_random_uuid(),
  referencia text not null unique check (length(trim(referencia)) >= 3),
  archivo_base64 text,
  archivo_nombre text,
  subida_por uuid references personas(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table actas_descanso_sustitutorio is
  'Documento firmado que respalda un acuerdo de descanso sustitutorio. Un acta cubre muchos registros de feriados_descanso_sustitutorio; el vínculo es actas.referencia = dcs.acta_ref.';

alter table actas_descanso_sustitutorio enable row level security;
drop policy if exists actas_select_admin_lider on actas_descanso_sustitutorio;
create policy actas_select_admin_lider on actas_descanso_sustitutorio
  for select using (fn_es_admin_o_lider());

-- ── Subir / reemplazar el archivo de un acta ────────────────────────────────
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
  -- PDF o imagen: es un papel escaneado o fotografiado, nada más.
  if p_dataurl is not null and p_dataurl !~ '^data:(application/pdf|image/(png|jpeg|webp));base64,' then
    raise exception 'Formato inválido: el acta debe ser un PDF o una imagen (PNG, JPEG o WEBP).';
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
grant execute on function fn_subir_acta_descanso(text, text, text) to authenticated;
revoke execute on function fn_subir_acta_descanso(text, text, text) from public, anon;

-- ── Listado SIN el archivo ──────────────────────────────────────────────────
-- La pantalla carga esto al entrar. Devolver el base64 aquí significaría bajar
-- megabytes en cada visita para no mostrarlos: el archivo se pide solo al abrirlo.
create or replace function fn_actas_descanso()
returns table (
  referencia text, archivo_nombre text, tiene_archivo boolean,
  peso_kb int, actualizado timestamptz, registros int
)
language sql stable security definer set search_path = public
as $$
  select a.referencia, a.archivo_nombre,
         (a.archivo_base64 is not null),
         (length(coalesce(a.archivo_base64, '')) / 1024)::int,
         a.updated_at,
         (select count(*)::int from feriados_descanso_sustitutorio d where d.acta_ref = a.referencia)
  from actas_descanso_sustitutorio a
  where fn_es_admin_o_lider()
  order by a.updated_at desc;
$$;
grant execute on function fn_actas_descanso() to authenticated;

-- ── Traer el archivo de UN acta (al abrirla) ────────────────────────────────
create or replace function fn_acta_descanso(p_referencia text)
returns text
language sql stable security definer set search_path = public
as $$
  select archivo_base64 from actas_descanso_sustitutorio
  where referencia = trim(p_referencia) and fn_es_admin_o_lider();
$$;
grant execute on function fn_acta_descanso(text) to authenticated;

notify pgrst, 'reload schema';
