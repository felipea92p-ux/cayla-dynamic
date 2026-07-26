-- ============================================================================
-- 0074 — Quién firma el memo, y la prueba de que lo recibieron
-- (Escrita como "0070" en la copia de iCloud y aplicada en producción DESPUÉS
-- de la 0071-0073 de main; se renumera a 0074 para que una base reconstruida
-- desde cero termine idéntica a producción. Ver commit 8cfedac.)
-- ----------------------------------------------------------------------------
-- DOS HUECOS del módulo disciplinario (hallados el 25/07/2026):
--
--   A · No se podía ELEGIR el firmante. fn_expediente_firmar (mig. 0058) ponía
--     firmante_id = quien hacía clic, sin más. Pero el flujo real delega: el
--     memo lo prepara admin y lo suscribe la encargada que lo entrega — es lo
--     que la propia plantilla T-01 llama "firma delegada"
--     (docs/disciplina-tardanzas-faltas/03-plantillas-tardanzas.md).
--
--     Peor: el documento impreso llevaba el cargo QUEMADO en el archivo
--     ("Gerencia General", memo/[id]/page.tsx). Como fn_expediente_puede_actuar
--     sí deja firmar a una supervisora de sede, un memo suyo salía impreso
--     diciendo que lo suscribió Gerencia General. Un papel que miente sobre
--     quién lo firmó es un papel que se cae si alguien lo discute.
--
--   B · No había dónde guardar el CARGO firmado. El memo se imprime, la persona
--     lo firma de recibido… y ese papel no volvía al sistema. La prueba de la
--     entrega vivía en un cajón. Ahora se sube la foto o el escaneo y queda
--     pegada al documento que le corresponde.
--
-- DECISIONES (Felipe, 25/07/2026):
--   · El escaneo va a Supabase Storage, no a una columna: es una foto de varios
--     MB y meterla en la fila engordaría cada consulta del expediente.
--   · Puede estampar la firma de otro cualquiera que pueda firmar ESE memo —
--     misma regla que ya gobierna el resto del módulo, sin inventar una nueva.
--   · El cargo sale del rol, no de un campo libre: una cosa menos que mantener
--     al día, y no se puede escribir mal.
--   · Subir el cargo firmado MARCA el documento como entregado, con la fecha
--     real en que la persona lo firmó (se pide, no se asume hoy): el papel en
--     la mano es la prueba de la entrega, no hacen falta dos pasos.
--   · Se distingue el cargo firmado del acta de negativa a firmar. Un legajo
--     con adjuntos tiene que decir si la persona aceptó el documento o lo
--     rechazó — es justo lo que se discute cuando hay conflicto.
--
-- Reversible: soltar el bucket y las 4 funciones nuevas, y restaurar
-- fn_expediente_firmar de 0058.
-- ============================================================================

-- ── A · El cargo que se imprime, derivado del rol ────────────────────────────
-- Una sola fuente de verdad, en la base y no en el JSX, para que el panel y
-- cualquier otro consumidor impriman exactamente lo mismo.
-- 'lider_do' se queda como nombre del ROL (renombrarlo tocaría RLS en media
-- base sin ganar nada), pero el cargo que se IMPRIME dice "Líder de Equipo":
-- el rol nació para Desarrollo Organizacional y hoy lo ocupan líderes de
-- otras áreas — el papel no debe atarlos a un área que no es la suya.
create or replace function fn_cargo_de_rol(p_rol rol_usuario)
returns text
language sql
immutable
as $$
  select case p_rol
    when 'admin'           then 'Gerencia General'
    when 'lider_do'        then 'Líder de Equipo'
    when 'supervisor_sede' then 'Encargada de Tienda'
    else null
  end;
$$;

grant execute on function fn_cargo_de_rol(rol_usuario) to authenticated;

-- ── A · Quiénes pueden firmar ESTE documento ─────────────────────────────────
-- Alimenta el selector del panel. Devuelve solo a quien de verdad puede
-- suscribirlo, y avisa si ya subió su firma escaneada: sin ella el memo sale
-- con la línea en blanco para firmar a mano, que también es válido.
create or replace function fn_expediente_firmantes(p_id uuid)
returns table (persona_id uuid, nombre text, cargo text, tiene_firma boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso sobre este documento.';
  end if;

  return query
  select p.id,
         (p.nombres || ' ' || p.apellidos)::text,
         fn_cargo_de_rol(p.rol),
         (p.firma_base64 is not null)
  from personas p
  where p.estado = 'activo'
    and fn_cargo_de_rol(p.rol) is not null
    -- Mismo criterio que gobierna el módulo: admin y líder pueden con todo;
    -- una encargada solo con verbal/amonestación de su propia sede.
    and (
      p.rol in ('admin', 'lider_do')
      or (p.rol = 'supervisor_sede'
          and r.nivel in ('verbal', 'amonestacion')
          and p.sede_base_id = (select sede_base_id from personas where id = r.persona_id))
    )
  order by 2;
end;
$$;

grant execute on function fn_expediente_firmantes(uuid) to authenticated;

-- ── A · Firmar eligiendo quién suscribe ──────────────────────────────────────
-- p_firmante_id opcional: sin él se comporta igual que antes (firma quien
-- llama), así que el panel viejo sigue funcionando mientras se despliega.
--
-- Hay que SOLTAR la de un solo parámetro: si convivieran, una llamada con un
-- argumento encajaría en las dos (la nueva por defecto) y Postgres la rechaza
-- por ambigua — el panel actual dejaría de poder firmar.
drop function if exists fn_expediente_firmar(uuid);

create or replace function fn_expediente_firmar(p_id uuid, p_firmante_id uuid default null)
returns text language plpgsql security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype; v_corr text; v_firmante uuid; v_f personas%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede firmar un borrador (estado actual: %).', r.estado;
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso para firmar un documento de nivel %.', r.nivel;
  end if;

  v_firmante := coalesce(p_firmante_id, fn_persona_actual_id());

  -- El firmante elegido tiene que poder suscribir ESTE documento por derecho
  -- propio. Sin esto, quien puede firmar podría estampar a cualquiera —
  -- incluida gente sin autoridad para el nivel que se está firmando.
  select * into v_f from personas where id = v_firmante;
  if not found then raise exception 'El firmante elegido no existe.'; end if;
  if v_f.estado <> 'activo' then raise exception 'El firmante elegido no está activo.'; end if;
  if fn_cargo_de_rol(v_f.rol) is null then
    raise exception 'El firmante elegido no tiene un cargo que pueda suscribir documentos.';
  end if;
  if v_f.rol = 'supervisor_sede' then
    if r.nivel not in ('verbal', 'amonestacion') then
      raise exception 'Una encargada de tienda no puede suscribir un documento de nivel %.', r.nivel;
    end if;
    if v_f.sede_base_id is distinct from (select sede_base_id from personas where id = r.persona_id) then
      raise exception 'El firmante elegido no pertenece a la sede de esta persona.';
    end if;
  end if;

  v_corr := fn_expediente_correlativo(fn_expediente_doc_code(r.tipo_causal, r.nivel));
  update expediente_disciplinario
    set estado = 'firmado', firmante_id = v_firmante, firmado_at = now(), correlativo = v_corr
    where id = p_id;
  return v_corr;
end;
$$;

grant execute on function fn_expediente_firmar(uuid, uuid) to authenticated;

-- ── B · El cargo firmado: dónde vive el escaneo ──────────────────────────────
-- Tabla y no columna: un memo puede volver en varias hojas (anverso, reverso,
-- la hoja de testigos), y una columna sola obligaría a elegir cuál se guarda.
create table if not exists expediente_adjuntos (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null references expediente_disciplinario(id) on delete cascade,
  storage_path text not null unique,
  -- Dos cosas MUY distintas que hay que poder separar después:
  --   cargo_firmado — el papel que firmó la persona: prueba de que lo recibió.
  --   acta_negativa — se negó a firmar, y firman los dos testigos. El memo ya
  --                   imprime esa constancia al pie; esta es la hoja devuelta.
  -- Sin este campo, un legajo con adjuntos no diría si la persona aceptó el
  -- documento o lo rechazó — que es justo lo que se discute si hay conflicto.
  tipo text not null default 'cargo_firmado' check (tipo in ('cargo_firmado', 'acta_negativa')),
  nota text,
  subido_por uuid not null references personas(id),
  subido_at timestamptz not null default now()
);

create index if not exists idx_expediente_adjuntos_doc on expediente_adjuntos(documento_id, subido_at);

alter table expediente_adjuntos enable row level security;

-- Lectura: el mismo alcance que ya tiene el expediente (mig. 0056).
-- El drop primero: 'create policy' no tiene "or replace", así que sin esto la
-- migración solo se puede correr una vez — y una migración que no se puede
-- reintentar es una trampa el día que falle a la mitad.
drop policy if exists expediente_adjuntos_select on expediente_adjuntos;

create policy expediente_adjuntos_select on expediente_adjuntos
  for select to authenticated
  using (
    exists (
      select 1 from expediente_disciplinario d
      join personas p on p.id = d.persona_id
      where d.id = expediente_adjuntos.documento_id
        and (
          fn_es_admin_o_lider()
          or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona())
          or d.persona_id = fn_persona_actual_id()
        )
    )
  );

-- Escritura solo por la función de abajo (security definer), como el resto del módulo.

-- ── B · El bucket ────────────────────────────────────────────────────────────
-- Privado: son documentos disciplinarios con nombre propio. Se leen con URL
-- firmada de vida corta, nunca por enlace público.
insert into storage.buckets (id, name, public)
values ('expedientes', 'expedientes', false)
on conflict (id) do nothing;

-- ── B · ¿Puede esta persona tocar los adjuntos de este documento? ────────────
-- El path del archivo es "<documento_id>/<lo-que-sea>", así que la carpeta
-- identifica el memo. Se valida que sea un uuid antes de castear: un path con
-- basura debe negarse limpio, no reventar con un error de casteo.
create or replace function fn_expediente_puede_adjuntar(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_carpeta text; v_doc expediente_disciplinario%rowtype;
begin
  v_carpeta := split_part(p_path, '/', 1);
  if v_carpeta !~ '^[0-9a-fA-F-]{36}$' then return false; end if;
  select * into v_doc from expediente_disciplinario where id = v_carpeta::uuid;
  if not found then return false; end if;
  -- Solo se adjunta el cargo de un documento ya firmado: antes de firmar no
  -- hay nada que la persona haya podido recibir.
  if v_doc.estado not in ('firmado', 'entregado') then return false; end if;
  return fn_expediente_puede_actuar(v_doc.persona_id, v_doc.nivel);
end;
$$;

grant execute on function fn_expediente_puede_adjuntar(text) to authenticated;

-- ── B · Permisos sobre los archivos del bucket ───────────────────────────────
drop policy if exists expedientes_insert on storage.objects;
create policy expedientes_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'expedientes' and fn_expediente_puede_adjuntar(name));

drop policy if exists expedientes_select on storage.objects;
create policy expedientes_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'expedientes'
    and exists (
      select 1 from expediente_adjuntos a
      where a.storage_path = storage.objects.name
    )
    and fn_expediente_puede_adjuntar(name)
  );

drop policy if exists expedientes_delete on storage.objects;
create policy expedientes_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'expedientes' and fn_es_admin_o_lider());

-- ── B · Registrar el adjunto ─────────────────────────────────────────────────
-- Tener el papel firmado ES la prueba de la entrega, así que subirlo también la
-- registra: un paso en vez de dos, y sin que se pueda quedar a medias (subido el
-- cargo pero el documento aún "por entregar").
--
-- La fecha se PIDE, no se asume hoy: el escaneo suele subirse días después de la
-- entrega real, y de esa fecha cuelgan los 6 días de descargo de una imputación.
-- Ponerla mal no es un detalle cosmético.
drop function if exists fn_expediente_adjuntar(uuid, text, text);

create or replace function fn_expediente_adjuntar(
  p_documento_id uuid,
  p_path text,
  p_tipo text default 'cargo_firmado',
  p_fecha_entrega timestamptz default null,
  p_nota text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_doc expediente_disciplinario%rowtype;
begin
  select * into v_doc from expediente_disciplinario where id = p_documento_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if split_part(p_path, '/', 1) <> p_documento_id::text then
    raise exception 'El archivo no corresponde a este documento.';
  end if;
  if not fn_expediente_puede_adjuntar(p_path) then
    raise exception 'Sin permiso para adjuntar el cargo de este documento.';
  end if;
  if p_tipo not in ('cargo_firmado', 'acta_negativa') then
    raise exception 'Tipo de adjunto inválido: %', p_tipo;
  end if;

  if p_fecha_entrega is not null then
    if p_fecha_entrega > now() then
      raise exception 'La fecha de entrega no puede ser futura.';
    end if;
    if v_doc.firmado_at is not null and p_fecha_entrega < v_doc.firmado_at then
      raise exception 'La entrega no puede ser anterior a la firma del documento.';
    end if;
  end if;

  insert into expediente_adjuntos (documento_id, storage_path, tipo, nota, subido_por)
  values (p_documento_id, p_path, p_tipo, nullif(trim(p_nota), ''), fn_persona_actual_id())
  returning id into v_id;

  -- Solo si sigue "firmado": si ya se marcó entregado por otra vía, esa fecha
  -- es la buena y no se pisa. fn_expediente_entregar mantiene su blindaje de
  -- Nivel 4 — el medio es 'fisico', que es lo que un papel firmado significa.
  if p_fecha_entrega is not null and v_doc.estado = 'firmado' then
    perform fn_expediente_entregar(p_documento_id, 'fisico', p_fecha_entrega);
  end if;

  return v_id;
end;
$$;

grant execute on function fn_expediente_adjuntar(uuid, text, text, timestamptz, text) to authenticated;

notify pgrst, 'reload schema';
