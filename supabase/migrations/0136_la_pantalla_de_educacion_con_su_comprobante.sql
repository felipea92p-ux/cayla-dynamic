-- ============================================================================
-- 0136 — La asignación por educación se carga desde una pantalla, con su papel
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE. Que Desarrollo Organizacional pueda registrar, corregir y cerrar
-- una asignación por educación desde /admin/educacion, y que el comprobante que
-- la sostiene quede guardado DENTRO del sistema — no en una carpeta que alguien
-- puede mover.
--
-- QUÉ ASUME. Que existen `asignaciones_educacion` (0120), su tope por rango
-- (0132), `fn_es_admin_o_lider()` y `fn_persona_actual_id()` (0078).
--
-- POR QUÉ AHORA. La 0120 dejó escrito «PENDIENTE: la pantalla para subir el
-- comprobante; mientras no exista, las filas se insertan por SQL». Nunca se
-- insertó ninguna: la tabla está vacía. Y esa tabla vacía es una de las tres
-- compensaciones que frenan la 0128 (bajar las bases declaradas por rango), así
-- que la pantalla que faltaba está en el camino crítico de lo que cobra la gente.
--
-- POR QUÉ UN BUCKET PROPIO Y NO «expedientes». La 0120 anticipó reusar el bucket
-- de los memos, pero sus políticas preguntan «¿este path es un documento
-- disciplinario ya firmado?» — un comprobante de matrícula jamás lo será. Meterlo
-- ahí obligaría a que esa función tuviera una rama por cada clase de papel. Un
-- bucket por clase de documento, cada uno con su regla legible, es más simple de
-- auditar el día que alguien pregunte quién puede ver qué.
--
-- POR QUÉ LA ESCRITURA VA POR FUNCIÓN Y NO POR POLÍTICA DE INSERT. Igual que el
-- resto del sistema (marcajes, expedientes, salarios): la tabla no acepta
-- escritura directa desde el cliente. Así el tope por rango, el candado del
-- comprobante y el registro de quién lo hizo no dependen de que la pantalla se
-- acuerde de mandarlos.
--
-- LO QUE NO HACE. No cambia el cálculo de la planilla — `fn_planilla_calcular`
-- ya lee esta tabla desde la 0122. Cargar una fila aquí SÍ cambia lo que cobra
-- esa persona en el siguiente periodo abierto; cargar cero filas no cambia nada.
--
-- CÓMO SE REVIERTE:
--   drop policy comprobantes_insert on storage.objects;
--   drop policy comprobantes_select on storage.objects;
--   drop policy comprobantes_delete on storage.objects;
--   drop function fn_educacion_registrar(uuid,numeric,text,numeric,numeric,text,date,text,text);
--   drop function fn_educacion_cerrar(uuid,date);
--   drop function fn_educacion_listar();
--   drop function fn_educacion_candidatos();
--   drop function fn_educacion_puede_ver(text);
--   delete from storage.buckets where id = 'comprobantes';  -- vacíalo antes
-- La tabla `asignaciones_educacion` y sus datos NO se tocan al revertir.
-- ============================================================================

-- ── A · El bucket ───────────────────────────────────────────────────────────
-- Privado. Un comprobante de matrícula lleva el nombre de la persona y, cuando
-- el beneficiario es un hijo, el de un menor. Se lee con URL firmada de vida
-- corta, nunca por enlace público.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'comprobantes', 'comprobantes', false,
  10485760,  -- 10 MB: una foto de un recibo o un PDF de matrícula entran de sobra
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp', 'application/pdf']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ── B · ¿Quién puede tocar este archivo? ─────────────────────────────────────
-- El path es "educacion/<persona_id>/<archivo>": la carpeta identifica de quién
-- es el comprobante. Se valida que sea un uuid ANTES de castear — un path con
-- basura debe negarse limpio, no reventar con un error de casteo (misma forma
-- que fn_expediente_puede_adjuntar en la 0074).
create or replace function fn_educacion_puede_ver(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_persona text;
begin
  if split_part(p_path, '/', 1) <> 'educacion' then return false; end if;
  v_persona := split_part(p_path, '/', 2);
  if v_persona !~ '^[0-9a-fA-F-]{36}$' then return false; end if;

  -- DO ve todos los comprobantes; cada quien ve el suyo. `is not true` y no
  -- `not (...)`: un null no debe pasar como autorizado.
  if fn_es_admin_o_lider() is true then return true; end if;
  return v_persona::uuid = fn_persona_actual_id();
end;
$$;

grant execute on function fn_educacion_puede_ver(text) to authenticated;

-- ── C · Permisos sobre los archivos ─────────────────────────────────────────
-- Subir y borrar es de DO: el comprobante sostiene un monto que se paga, así que
-- no lo cambia la propia interesada. Leer sí lo puede hacer cada quien sobre el
-- suyo, para que pueda comprobar qué papel quedó archivado a su nombre.
drop policy if exists comprobantes_insert on storage.objects;
create policy comprobantes_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'comprobantes'
    and split_part(name, '/', 1) = 'educacion'
    and fn_es_admin_o_lider() is true
  );

drop policy if exists comprobantes_select on storage.objects;
create policy comprobantes_select on storage.objects
  for select to authenticated
  using (bucket_id = 'comprobantes' and fn_educacion_puede_ver(name));

drop policy if exists comprobantes_delete on storage.objects;
create policy comprobantes_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'comprobantes'
    and split_part(name, '/', 1) = 'educacion'
    and fn_es_admin_o_lider() is true
  );

-- ── D · Registrar una asignación ────────────────────────────────────────────
-- Una sola puerta de escritura. Devuelve el id de la fila para que la pantalla
-- pueda subir el comprobante a "educacion/<persona>/<id>.<ext>" y luego
-- enlazarlo con la misma función (pasando p_id).
create or replace function fn_educacion_registrar(
  p_persona_id      uuid,
  p_monto           numeric,
  p_institucion     text,
  p_costo_declarado numeric,
  p_cobertura_pct   numeric,
  p_beneficiario    text,
  p_vigente_desde   date,
  p_comprobante_url text default null,
  p_nota            text default null,
  p_id              uuid default null   -- no nulo = corregir una fila existente
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
  v_yo  uuid := fn_persona_actual_id();
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra asignaciones por educación.';
  end if;

  if p_institucion is null or length(trim(p_institucion)) < 3 then
    raise exception 'Falta la institución que emite el comprobante.';
  end if;
  if p_beneficiario not in ('trabajador', 'hijo') then
    raise exception 'El beneficiario es «trabajador» o «hijo» (llegó «%»).', p_beneficiario;
  end if;

  -- Que la persona exista y esté activa. Cargarle una asignación a alguien que
  -- ya no está sería pagar por un estudio que la empresa dejó de sostener.
  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no existe o no está activa.';
  end if;

  if p_id is null then
    insert into asignaciones_educacion (
      persona_id, monto, institucion, costo_declarado, cobertura_pct,
      beneficiario, vigente_desde, comprobante_url, nota, registrado_por
    ) values (
      p_persona_id, p_monto, trim(p_institucion), p_costo_declarado, p_cobertura_pct,
      p_beneficiario, p_vigente_desde, p_comprobante_url, nullif(trim(coalesce(p_nota, '')), ''), v_yo
    )
    returning id into v_id;
  else
    update asignaciones_educacion set
      persona_id      = p_persona_id,
      monto           = p_monto,
      institucion     = trim(p_institucion),
      costo_declarado = p_costo_declarado,
      cobertura_pct   = p_cobertura_pct,
      beneficiario    = p_beneficiario,
      vigente_desde   = p_vigente_desde,
      -- null no borra el comprobante ya cargado: se enlaza en un segundo paso,
      -- después de que el archivo terminó de subir.
      comprobante_url = coalesce(p_comprobante_url, comprobante_url),
      nota            = nullif(trim(coalesce(p_nota, '')), '')
    where id = p_id
    returning id into v_id;

    if v_id is null then raise exception 'Esa asignación no existe.'; end if;
  end if;

  return v_id;
end;
$$;

grant execute on function fn_educacion_registrar(uuid,numeric,text,numeric,numeric,text,date,text,text,uuid) to authenticated;

-- ── E · Cerrar una asignación ───────────────────────────────────────────────
-- Terminó el ciclo, o la persona dejó de estudiar. No se borra: la fila sostiene
-- lo que ya se pagó en periodos cerrados, y borrarla dejaría esos pagos sin
-- sustento el día de una fiscalización.
create or replace function fn_educacion_cerrar(p_id uuid, p_hasta date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r asignaciones_educacion%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional cierra asignaciones por educación.';
  end if;

  select * into r from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_hasta < r.vigente_desde then
    raise exception 'La fecha de cierre (%) es anterior al inicio (%).', p_hasta, r.vigente_desde;
  end if;

  update asignaciones_educacion set vigente_hasta = p_hasta where id = p_id;
end;
$$;

grant execute on function fn_educacion_cerrar(uuid,date) to authenticated;

-- ── F · Leer la lista con los nombres ya puestos ────────────────────────────
-- La pantalla necesita el nombre y la sede junto a cada fila. Va por función y
-- no por vista para que el filtro de permiso viva en un solo sitio: quien no es
-- DO recibe únicamente lo suyo, sin depender de que la pantalla filtre bien.
create or replace function fn_educacion_listar()
returns table (
  id               uuid,
  persona_id       uuid,
  persona          text,
  sede             text,
  rango            text,
  monto            numeric,
  institucion      text,
  costo_declarado  numeric,
  cobertura_pct    numeric,
  beneficiario     text,
  comprobante_url  text,
  vigente_desde    date,
  vigente_hasta    date,
  nota             text,
  registrada_por   text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.id, a.persona_id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    a.monto, a.institucion, a.costo_declarado, a.cobertura_pct,
    a.beneficiario, a.comprobante_url, a.vigente_desde, a.vigente_hasta, a.nota,
    reg.nombres || ' ' || reg.apellidos
  from asignaciones_educacion a
  join personas p on p.id = a.persona_id
  left join sedes s on s.id = p.sede_base_id
  left join personas reg on reg.id = a.registrado_por
  left join lateral (
    select rango from asignaciones_salario x
    where x.persona_id = a.persona_id and x.vigente_hasta is null
    order by x.vigente_desde desc limit 1
  ) sal on true
  where fn_es_admin_o_lider() is true
     or a.persona_id = fn_persona_actual_id()
  order by (a.vigente_hasta is not null), p.apellidos, a.vigente_desde desc;
$$;

grant execute on function fn_educacion_listar() to authenticated;

-- ── G · A quién se le puede cargar, y hasta cuánto ──────────────────────────
-- La pantalla necesita saber el tope ANTES de guardar, no después. Si el tope
-- solo se conociera al recibir el error, la persona escribiría el monto, subiría
-- el comprobante y recién ahí se enteraría de que no cabía — con el archivo ya
-- subido. Que el formulario pueda avisar mientras se escribe es la diferencia
-- entre un sistema que corrige y uno que regaña.
create or replace function fn_educacion_candidatos()
returns table (
  persona_id uuid,
  persona    text,
  sede       text,
  rango      text,
  tope       numeric,
  ya_tiene   boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    t.tope_mensual,      -- null = rango sin techo cargado; la pantalla lo dice
    exists (
      select 1 from asignaciones_educacion a
      where a.persona_id = p.id and a.vigente_hasta is null
    )
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select rango from asignaciones_salario x
    where x.persona_id = p.id and x.vigente_hasta is null
    order by x.vigente_desde desc limit 1
  ) sal on true
  left join topes_educacion_rango t on t.rango = sal.rango
  where p.estado = 'activo'
    and fn_es_admin_o_lider() is true
  order by p.apellidos, p.nombres;
$$;

grant execute on function fn_educacion_candidatos() to authenticated;

-- El comentario de la 0120 anticipaba el bucket «expedientes»; quedó en
-- «comprobantes» por lo explicado arriba. Se corrige para que la columna no
-- mande a buscar el archivo donde no está.
comment on column asignaciones_educacion.comprobante_url is
  'Ruta en el bucket privado «comprobantes», con la forma educacion/<persona_id>/<archivo>. '
  'Se lee con URL firmada de vida corta. El día del requerimiento tiene que existir: el '
  'art. 148 del Código Tributario no admite en apelación la prueba que no se exhibió en '
  'fiscalización.';

insert into migraciones_aplicadas (numero, nombre)
values (136, 'la_pantalla_de_educacion_con_su_comprobante')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
