-- ============================================================================
-- 0399 — Cambiar el perfil pasa por una solicitud
-- ============================================================================
--
-- QUÉ PROMETE
--   El colaborador propone un cambio a su propio perfil desde "Lo mío";
--   Administración/DO lo aprueba o rechaza; el valor real de la ficha NO
--   cambia hasta que se aprueba. Para 8 de los 11 campos posibles, la
--   propuesta exige al menos un documento de sustento adjunto. Ver
--   docs/adr/0001-solicitudes-cambio-perfil-colaborador.md para el diseño
--   completo y sus alternativas descartadas.
--
-- QUÉ ASUME
--   personas, datos_personales, correcciones_auditoria, migraciones_aplicadas,
--   fn_es_admin_o_lider(), fn_persona_actual_id(), fn_set_documento (0344),
--   fn_set_derechohabiente y fn_cerrar_derechohabiente (existen HOY en la base
--   compartida, pero — hallazgo de esta misma sesión — NINGUNA migración en
--   ningún branch local ni remoto las crea. `derechohabientes` es una tabla
--   real, con frontend ya construido y comiteado en datos-personales/page.tsx,
--   cuya migración de origen se perdió (mismo patrón que el incidente 0177).
--   Esta migración NO reconstruye esa migración perdida — eso se decidió
--   aparte, fuera de esta feature — solo modifica dos de sus funciones
--   (ver punto E).
--
-- QUÉ NO HACE
--   - No toca el régimen de pensión (AFP/ONP): fn_cambiar_regimen_pension
--     sigue siendo el único mecanismo para eso. "cuspp" en este catálogo es
--     solo el número, no el régimen.
--   - No agrega notificación por correo todavía: tocar
--     fn_alertas_email_pendientes exige el md5 de PRODUCCIÓN antes de
--     escribir (regla no negociable de este repo, ya lleva dos reescrituras
--     superpuestas — 0358 sobre 0354, 0359 sobre 0358) y esta sesión no tiene
--     acceso a producción. Queda para una migración aparte, después de correr
--     donde-vive.sh contra el SQL Editor. Mientras tanto, "Solicitudes de
--     perfil" vive en /admin/bandeja igual que Vacaciones/Revisiones — el
--     aviso in-app no depende de esto.
--   - No reconstruye la migración perdida de `derechohabientes` — reportado
--     al usuario, decisión pendiente y ajena a esta feature.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_personas_documento_solo_por_rpc_perfil on personas; -- si se agregara
--   drop function if exists fn_resolver_seguimiento_planilla(uuid, text);
--   drop function if exists fn_resolver_solicitud_perfil(uuid, boolean, text);
--   drop function if exists fn_aplicar_cambio_perfil(uuid);
--   drop function if exists fn_solicitudes_perfil_pendientes();
--   drop function if exists fn_mis_solicitudes_perfil();
--   drop function if exists fn_crear_solicitud_perfil(text, jsonb, text[]);
--   drop function if exists fn_validar_valor_propuesto(text, jsonb);
--   drop function if exists fn_snapshot_valor_actual(uuid, text);
--   drop policy solicitud_perfil_insert, solicitud_perfil_update,
--     solicitud_perfil_select, solicitud_perfil_delete on storage.objects;
--   drop function if exists fn_solicitud_perfil_puede_escribir(text);
--   delete from storage.buckets where id = 'solicitudes-perfil'; -- vacíalo antes
--   drop table if exists seguimiento_planilla_por_solicitud;
--   drop table if exists solicitudes_cambio_perfil;
--   drop table if exists catalogo_campos_perfil;
--   -- Para fn_set_datos_personales / fn_set_derechohabiente / fn_cerrar_derechohabiente
--   -- (punto E): restaurar la rama "p_persona_id = fn_persona_actual_id()" que
--   -- esta migración les quita. Sus cuerpos completos ANTES de este cambio
--   -- quedan en el historial de git de este mismo archivo (sección E de abajo,
--   -- comentada) — no hay una migración anterior de la que copiarlos porque,
--   -- como se explica arriba, esa migración nunca se comiteó.
-- ============================================================================


-- ── A · Catálogo de campos: qué se puede pedir y si exige documento ────────
-- Regla #3 de este repo: nunca una lista escrita a mano de algo que vive en
-- una tabla. El frontend y las RPC de abajo leen esto, no hardcodean 11 filas.
create table if not exists catalogo_campos_perfil (
  campo              text primary key,
  etiqueta           text not null,
  requiere_documento boolean not null default false,
  documento_sugerido text,
  columnas           text[] not null
);

alter table catalogo_campos_perfil enable row level security;
drop policy if exists catalogo_campos_perfil_select on catalogo_campos_perfil;
create policy catalogo_campos_perfil_select on catalogo_campos_perfil
  for select to authenticated using (true);
grant select on catalogo_campos_perfil to authenticated;
revoke all on catalogo_campos_perfil from anon, public;

insert into catalogo_campos_perfil (campo, etiqueta, requiere_documento, documento_sugerido, columnas) values
  ('celular', 'Celular', false, null, array['celular']),
  ('direccion', 'Dirección', false, null, array['direccion']),
  ('contacto_emergencia', 'Contacto de emergencia', false, null,
    array['emergencia_nombre','emergencia_vinculo','emergencia_telefono']),
  ('estado_civil', 'Estado civil', true, 'Acta de matrimonio o sentencia de divorcio',
    array['estado_civil']),
  ('hijos_menores', 'Hijos menores a cargo', true, 'Partida de nacimiento del menor',
    array['hijos_menores']),
  ('grado_instruccion', 'Grado de instrucción', true, 'Título, grado de bachiller o certificado',
    array['grado_instruccion']),
  ('discapacidad', 'Discapacidad', true, 'Certificado CONADIS',
    array['discapacidad','discapacidad_conadis']),
  ('cuenta_bancaria', 'Cuenta bancaria', true,
    'Carátula de cuenta o captura del app, a nombre del colaborador',
    array['entidad_bancaria','numero_cuenta']),
  ('cuspp', 'Sistema de pensiones (CUSPP)', true, 'Constancia de la AFP o estado de cuenta',
    array['cuspp']),
  -- Documento (DNI), nombre completo (nombre_dni — NO personas.nombres/apellidos,
  -- ver comentario en fn_snapshot_valor_actual), fecha de nacimiento y género:
  -- se piden juntos porque un error de captura casi siempre aparece junto.
  -- Cualquier subconjunto no vacío es válido — no hace falta corregir los 4 a la vez.
  ('correccion_identidad', 'Corrección de DNI, nombre, fecha de nacimiento o género', true,
    'Copia del DNI vigente',
    array['documento','nombre_dni','fecha_nacimiento','genero']),
  -- No crea una tabla nueva: al aprobarse, llama a fn_set_derechohabiente
  -- (existente) sobre la tabla `derechohabientes` (existente). Ver la nota en
  -- QUÉ ASUME sobre por qué esa tabla no tiene migración propia.
  ('familiar_nuevo', 'Agregar familiar', true,
    'Partida de nacimiento o matrimonio, según vínculo',
    array['nombres','apellidos','vinculo'])
on conflict (campo) do update set
  etiqueta = excluded.etiqueta,
  requiere_documento = excluded.requiere_documento,
  documento_sugerido = excluded.documento_sugerido,
  columnas = excluded.columnas;


-- ── B · La solicitud ─────────────────────────────────────────────────────
create table if not exists solicitudes_cambio_perfil (
  id               uuid primary key default gen_random_uuid(),
  persona_id       uuid not null references personas(id),
  campo            text not null references catalogo_campos_perfil(campo),
  valor_anterior   jsonb not null,
  valor_propuesto  jsonb not null,
  rutas_adjuntas   text[] not null default '{}',
  estado           text not null default 'pendiente'
                     check (estado in ('pendiente','aprobado','rechazado','reemplazada')),
  creada_at        timestamptz not null default now(),
  resuelta_at      timestamptz,
  resuelta_por     uuid references personas(id),
  motivo           text,
  constraint chk_solicitud_perfil_resuelta_completa check (
    estado = 'pendiente' or (resuelta_at is not null and resuelta_por is not null)
  ),
  constraint chk_solicitud_perfil_rechazo_con_motivo check (
    estado <> 'rechazado' or coalesce(trim(motivo), '') <> ''
  )
);

comment on table solicitudes_cambio_perfil is
  'Una persona propone un cambio a su propio perfil; DO aprueba o rechaza. El '
  'valor real (en personas/datos_personales/derechohabientes) no cambia hasta '
  'aprobar — ver fn_aplicar_cambio_perfil. `reemplazada` no es un rechazo: es '
  'la etiqueta que se pone sola cuando la persona edita el mismo campo antes '
  'de que se resuelva la anterior (nunca se borra, ver CLAUDE.md).';

create index if not exists idx_solicitudes_perfil_persona
  on solicitudes_cambio_perfil (persona_id, creada_at desc);
create index if not exists idx_solicitudes_perfil_pendientes
  on solicitudes_cambio_perfil (creada_at) where estado = 'pendiente';

-- Como máximo una solicitud PENDIENTE por persona+campo — salvo familiar_nuevo,
-- que admite varias en paralelo (agregar dos hijos distintos son dos altas
-- legítimas, no la misma pregunta repetida). Esta es la red de seguridad real
-- contra dos envíos casi simultáneos, no el UPDATE...INSERT de
-- fn_crear_solicitud_perfil por sí solo — mismo mecanismo que
-- solicitudes_vacaciones_pendientes_sin_solape (0330).
drop index if exists uq_solicitud_perfil_pendiente;
create unique index uq_solicitud_perfil_pendiente
  on solicitudes_cambio_perfil (persona_id, campo)
  where estado = 'pendiente' and campo <> 'familiar_nuevo';

alter table solicitudes_cambio_perfil enable row level security;

drop policy if exists solicitudes_perfil_select_propia on solicitudes_cambio_perfil;
create policy solicitudes_perfil_select_propia on solicitudes_cambio_perfil
  for select to authenticated using (persona_id = fn_persona_actual_id());

drop policy if exists solicitudes_perfil_select_admin_lider on solicitudes_cambio_perfil;
create policy solicitudes_perfil_select_admin_lider on solicitudes_cambio_perfil
  for select to authenticated using (fn_es_admin_o_lider() is true);

grant select on solicitudes_cambio_perfil to authenticated;
revoke all on solicitudes_cambio_perfil from anon, public;
-- Sin policies de insert/update/delete: toda escritura pasa por las RPC de abajo.


-- ── C · La tarea de seguimiento a planilla (estado_civil / hijos_menores) ──
create table if not exists seguimiento_planilla_por_solicitud (
  id            uuid primary key default gen_random_uuid(),
  solicitud_id  uuid not null unique references solicitudes_cambio_perfil(id),
  persona_id    uuid not null references personas(id),
  campo         text not null,
  descripcion   text not null,
  estado        text not null default 'pendiente' check (estado in ('pendiente','resuelta')),
  creada_at     timestamptz not null default now(),
  resuelta_por  uuid references personas(id),
  resuelta_at   timestamptz,
  nota          text
);

comment on table seguimiento_planilla_por_solicitud is
  'Aviso manual para DO: "revisa la asignación familiar / el seguro con SUNAT '
  'o EsSalud" tras aprobar un cambio de estado civil o de hijos menores. Nadie '
  'la autocierra — es un trámite externo que el sistema no puede confirmar solo.';

create index if not exists idx_seguimiento_planilla_pendiente
  on seguimiento_planilla_por_solicitud (creada_at) where estado = 'pendiente';

alter table seguimiento_planilla_por_solicitud enable row level security;

drop policy if exists seguimiento_planilla_select on seguimiento_planilla_por_solicitud;
create policy seguimiento_planilla_select on seguimiento_planilla_por_solicitud
  for select to authenticated using (fn_es_admin_o_lider() is true);

grant select on seguimiento_planilla_por_solicitud to authenticated;
revoke all on seguimiento_planilla_por_solicitud from anon, public;


-- ── D · Documentos: bucket privado + URL firmada (como comprobantes/expedientes,
--       NO como fotos-perfil — estos SÍ tienen un dato que nadie ve por su
--       cuenta: DNI, certificado CONADIS, partida de nacimiento) ───────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'solicitudes-perfil', 'solicitudes-perfil', false,
  8388608, -- 8 MB: de sobra para una foto de documento o un PDF escaneado
  array['image/jpeg','image/png','application/pdf']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Path: solicitud/<persona_id>/<epoch_ms>-<random>.<ext> — sin id de solicitud
-- en la ruta a propósito: el archivo se sube ANTES de crear la fila (ver
-- fn_crear_solicitud_perfil), así que todavía no existe un id que usar. Las
-- rutas ya subidas se pasan como argumento a fn_crear_solicitud_perfil, que
-- las valida y las guarda en `rutas_adjuntas`.
create or replace function fn_solicitud_perfil_puede_escribir(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_persona text;
begin
  if split_part(p_path, '/', 1) <> 'solicitud' then return false; end if;
  v_persona := split_part(p_path, '/', 2);
  if v_persona !~ '^[0-9a-fA-F-]{36}$' then return false; end if;

  if fn_es_admin_o_lider() is true then return true; end if;
  return v_persona::uuid = fn_persona_actual_id();
end;
$$;

grant execute on function fn_solicitud_perfil_puede_escribir(text) to authenticated;

-- Las CUATRO políticas — Supabase Storage sube con
-- insert ... on conflict ... do update ... returning *, que exige INSERT,
-- UPDATE y SELECT sobre storage.objects (lección ya pagada en 0136/0381).
drop policy if exists solicitud_perfil_insert on storage.objects;
create policy solicitud_perfil_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_escribir(name));

drop policy if exists solicitud_perfil_update on storage.objects;
create policy solicitud_perfil_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_escribir(name))
  with check (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_escribir(name));

drop policy if exists solicitud_perfil_select on storage.objects;
create policy solicitud_perfil_select on storage.objects
  for select to authenticated
  using (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_escribir(name));

drop policy if exists solicitud_perfil_delete on storage.objects;
create policy solicitud_perfil_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_escribir(name));


-- ── E · Cerrar el auto-escritura directa en las funciones existentes ───────
-- fn_set_datos_personales y fn_set_derechohabiente (y fn_cerrar_derechohabiente)
-- permiten hoy que "la propia persona" escriba directo, sin pasar por ninguna
-- solicitud ni documento — un colaborador con sesión en /mio podría llamar
-- supabase.rpc('fn_set_datos_personales', {...}) desde la consola del
-- navegador y cambiar su propio celular, estado civil o cuenta bancaria al
-- instante. Ninguna pantalla de este repo usa hoy esa rama (ni /mio ni
-- ninguna otra llaman a estas dos funciones para autoedición), así que
-- cerrarla no rompe nada existente. Sin esto, la promesa central de esta
-- feature ("el valor no cambia hasta que se aprueba") sería solo de interfaz,
-- no de base de datos.
--
-- md5 de partida — POSTGRES LOCAL, no producción (2026-09-07):
--   fn_set_datos_personales: 84d6e0ead1408e53b293381a44d297bd (2446 caracteres)
--   fn_set_derechohabiente:  593ecdb3ee09f78c6c6cf2cf140997eb (1927 caracteres)
--   fn_cerrar_derechohabiente: ec87470ce6be61477c712a0f23bb1589 (966 caracteres)
-- Para estas dos últimas no hay una migración previa contra la cual declarar
-- "md5 de partida" en el sentido habitual: como se explica en QUÉ ASUME,
-- ninguna migración las creó nunca. Antes de pegar esto en producción,
-- confirmar con el SQL Editor que los tres md5 de ARRIBA (LOCAL) coinciden
-- con los de PRODUCCIÓN — si no coinciden, alguien más cambió estas
-- funciones entre que se escribió esto y que se pega, y hay que releer antes
-- de continuar (regla no negociable de este repo).

create or replace function public.fn_set_datos_personales(p_persona_id uuid, p_nombre_dni text DEFAULT NULL::text, p_fecha_nacimiento date DEFAULT NULL::date, p_estado_civil text DEFAULT NULL::text, p_direccion text DEFAULT NULL::text, p_celular text DEFAULT NULL::text, p_entidad_bancaria text DEFAULT NULL::text, p_numero_cuenta text DEFAULT NULL::text, p_grado_instruccion text DEFAULT NULL::text, p_hijos_menores boolean DEFAULT NULL::boolean, p_foto_dni_url text DEFAULT NULL::text, p_foto_personal_url text DEFAULT NULL::text, p_foto_profesional_url text DEFAULT NULL::text, p_emergencia_nombre text DEFAULT NULL::text, p_emergencia_vinculo text DEFAULT NULL::text, p_emergencia_telefono text DEFAULT NULL::text, p_discapacidad boolean DEFAULT NULL::boolean, p_discapacidad_conadis text DEFAULT NULL::text, p_cuspp text DEFAULT NULL::text, p_genero text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- CAMBIO 0399: se quita "or p_persona_id = fn_persona_actual_id()" — la
  -- propia persona ya no edita su ficha directo, pasa por
  -- fn_crear_solicitud_perfil / fn_aplicar_cambio_perfil.
  if (fn_es_admin_o_lider()
          or (fn_rol_actual() = 'supervisor_sede'
              and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona())) is not true then
    raise exception 'Sin permiso para editar los datos personales de esta persona.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;
  insert into datos_personales as dp (
    persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular,
    entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores,
    foto_dni_url, foto_personal_url, foto_profesional_url,
    emergencia_nombre, emergencia_vinculo, emergencia_telefono,
    discapacidad, discapacidad_conadis,
    cuspp,
    genero,
    actualizado_por, actualizado_at)
  values (
    p_persona_id, p_nombre_dni, p_fecha_nacimiento, p_estado_civil, p_direccion, p_celular,
    p_entidad_bancaria, p_numero_cuenta, p_grado_instruccion, p_hijos_menores,
    p_foto_dni_url, p_foto_personal_url, p_foto_profesional_url,
    p_emergencia_nombre, p_emergencia_vinculo, p_emergencia_telefono,
    p_discapacidad, p_discapacidad_conadis,
    nullif(upper(trim(p_cuspp)), ''),
    nullif(lower(trim(p_genero)), ''),
    fn_persona_actual_id(), now())
  on conflict (persona_id) do update set
    nombre_dni = excluded.nombre_dni, fecha_nacimiento = excluded.fecha_nacimiento,
    estado_civil = excluded.estado_civil, direccion = excluded.direccion, celular = excluded.celular,
    entidad_bancaria = excluded.entidad_bancaria, numero_cuenta = excluded.numero_cuenta,
    grado_instruccion = excluded.grado_instruccion, hijos_menores = excluded.hijos_menores,
    foto_dni_url = excluded.foto_dni_url, foto_personal_url = excluded.foto_personal_url,
    foto_profesional_url = excluded.foto_profesional_url,
    emergencia_nombre = excluded.emergencia_nombre,
    emergencia_vinculo = excluded.emergencia_vinculo,
    emergencia_telefono = excluded.emergencia_telefono,
    discapacidad = excluded.discapacidad,
    discapacidad_conadis = excluded.discapacidad_conadis,
    cuspp = excluded.cuspp,
    genero = excluded.genero,
    actualizado_por = fn_persona_actual_id(), actualizado_at = now();
end;
$function$;

grant execute on function fn_set_datos_personales(
  uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,
  text,text,text,boolean,text,text,text) to authenticated;
revoke execute on function fn_set_datos_personales(
  uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,
  text,text,text,boolean,text,text,text) from public, anon;


create or replace function public.fn_set_derechohabiente(p_id uuid, p_persona_id uuid, p_nombres text, p_apellidos text, p_vinculo text, p_documento text DEFAULT NULL::text, p_fecha_nacimiento date DEFAULT NULL::date, p_essalud boolean DEFAULT false, p_vida_ley boolean DEFAULT false, p_nota text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_id    uuid;
  v_sede  uuid;
begin
  select sede_base_id into v_sede from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe.';
  end if;

  -- CAMBIO 0399: se quita "or p_persona_id = fn_persona_actual_id()".
  if (fn_es_admin_o_lider()
          or (fn_rol_actual() = 'supervisor_sede' and v_sede = fn_sede_actual_persona())) is not true then
    raise exception 'Sin permiso para editar los familiares de esta persona.';
  end if;

  if nullif(btrim(coalesce(p_nombres, '')), '') is null
     or nullif(btrim(coalesce(p_apellidos, '')), '') is null then
    raise exception 'El nombre y el apellido del familiar son obligatorios.';
  end if;

  if p_id is null then
    insert into derechohabientes
      (persona_id, nombres, apellidos, documento, fecha_nacimiento, vinculo,
       essalud, vida_ley, nota, registrado_por)
    values
      (p_persona_id, btrim(p_nombres), btrim(p_apellidos),
       nullif(btrim(coalesce(p_documento, '')), ''), p_fecha_nacimiento, p_vinculo,
       coalesce(p_essalud, false), coalesce(p_vida_ley, false),
       nullif(btrim(coalesce(p_nota, '')), ''), fn_persona_actual_id())
    returning id into v_id;
  else
    update derechohabientes set
      nombres = btrim(p_nombres), apellidos = btrim(p_apellidos),
      documento = nullif(btrim(coalesce(p_documento, '')), ''),
      fecha_nacimiento = p_fecha_nacimiento, vinculo = p_vinculo,
      essalud = coalesce(p_essalud, false), vida_ley = coalesce(p_vida_ley, false),
      nota = nullif(btrim(coalesce(p_nota, '')), '')
    where id = p_id and persona_id = p_persona_id
    returning id into v_id;

    if v_id is null then
      raise exception 'No encontré ese familiar en la ficha de esta persona.';
    end if;
  end if;

  return v_id;
end;
$function$;

grant execute on function fn_set_derechohabiente(uuid,uuid,text,text,text,text,date,boolean,boolean,text) to authenticated;
revoke execute on function fn_set_derechohabiente(uuid,uuid,text,text,text,text,date,boolean,boolean,text) from public, anon;


create or replace function public.fn_cerrar_derechohabiente(p_id uuid, p_hasta date DEFAULT NULL::date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare v_persona uuid; v_sede uuid;
begin
  select d.persona_id, p.sede_base_id into v_persona, v_sede
  from derechohabientes d join personas p on p.id = d.persona_id
  where d.id = p_id;

  if not found then
    raise exception 'Ese familiar no existe.';
  end if;

  -- CAMBIO 0399: se quita "or v_persona = fn_persona_actual_id()".
  if (fn_es_admin_o_lider()
          or (fn_rol_actual() = 'supervisor_sede' and v_sede = fn_sede_actual_persona())) is not true then
    raise exception 'Sin permiso para editar los familiares de esta persona.';
  end if;

  update derechohabientes
     set vigente_hasta = coalesce(p_hasta, fn_hoy_lima())
   where id = p_id;
end;
$function$;

grant execute on function fn_cerrar_derechohabiente(uuid, date) to authenticated;
revoke execute on function fn_cerrar_derechohabiente(uuid, date) from public, anon;


-- ── F · Snapshot del valor actual, para valor_anterior ──────────────────────
create or replace function fn_snapshot_valor_actual(p_persona_id uuid, p_campo text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_p personas%rowtype;
  v_d datos_personales%rowtype;
begin
  select * into v_p from personas where id = p_persona_id;
  select * into v_d from datos_personales where persona_id = p_persona_id;
  -- v_d puede no existir todavía (fila nunca creada) — sus campos quedan null,
  -- que es el valor real: "no tiene nada guardado ahí".

  return case p_campo
    when 'celular' then jsonb_build_object('celular', v_d.celular)
    when 'direccion' then jsonb_build_object('direccion', v_d.direccion)
    when 'contacto_emergencia' then jsonb_build_object(
      'emergencia_nombre', v_d.emergencia_nombre,
      'emergencia_vinculo', v_d.emergencia_vinculo,
      'emergencia_telefono', v_d.emergencia_telefono)
    when 'estado_civil' then jsonb_build_object('estado_civil', v_d.estado_civil)
    when 'hijos_menores' then jsonb_build_object('hijos_menores', v_d.hijos_menores)
    when 'grado_instruccion' then jsonb_build_object('grado_instruccion', v_d.grado_instruccion)
    when 'discapacidad' then jsonb_build_object(
      'discapacidad', v_d.discapacidad, 'discapacidad_conadis', v_d.discapacidad_conadis)
    when 'cuenta_bancaria' then jsonb_build_object(
      'entidad_bancaria', v_d.entidad_bancaria, 'numero_cuenta', v_d.numero_cuenta)
    when 'cuspp' then jsonb_build_object('cuspp', v_d.cuspp)
    -- 'nombre_dni' (datos_personales) — el nombre "como aparece en el DNI"
    -- para el T-Registro. NO es personas.nombres/apellidos, que es el nombre
    -- de sistema y esta feature nunca lo toca.
    when 'correccion_identidad' then jsonb_build_object(
      'documento', v_p.documento, 'nombre_dni', v_d.nombre_dni,
      'fecha_nacimiento', v_d.fecha_nacimiento, 'genero', v_d.genero)
    when 'familiar_nuevo' then '{}'::jsonb  -- siempre es un alta, no hay "antes"
    else '{}'::jsonb
  end;
end;
$fn$;

revoke all on function fn_snapshot_valor_actual(uuid, text) from public, anon, authenticated;


-- ── G · Validar lo que se propone, antes de aceptarlo ──────────────────────
create or replace function fn_validar_valor_propuesto(p_campo text, p_valor jsonb)
returns void
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_columnas text[];
  v_col text;
  v_alguna boolean := false;
begin
  select columnas into v_columnas from catalogo_campos_perfil where campo = p_campo;
  if v_columnas is null then
    raise exception 'Campo de perfil desconocido: %', p_campo;
  end if;

  if p_campo = 'familiar_nuevo' then
    if nullif(trim(coalesce(p_valor->>'nombres', '')), '') is null then
      raise exception 'El nombre del familiar no puede quedar vacío.';
    end if;
    if nullif(trim(coalesce(p_valor->>'apellidos', '')), '') is null then
      raise exception 'El apellido del familiar no puede quedar vacío.';
    end if;
    -- Mismo catálogo que derechohabientes_vinculo_check (tabla existente,
    -- ver docs/adr/0001-... sobre por qué no tiene migración propia).
    if coalesce(p_valor->>'vinculo', '') not in
       ('conyuge','conviviente','hijo','madre','padre','hermano','otro') then
      raise exception 'Vínculo inválido: %', p_valor->>'vinculo';
    end if;
    -- Mismo requisito que derechohabientes_check: un "hijo" siempre declara
    -- su fecha de nacimiento (afecta cuándo deja de ser derechohabiente).
    if p_valor->>'vinculo' = 'hijo' and nullif(p_valor->>'fecha_nacimiento', '') is null then
      raise exception 'La fecha de nacimiento es obligatoria para un hijo o hija a cargo.';
    end if;
    return;
  end if;

  if p_campo = 'correccion_identidad' then
    foreach v_col in array v_columnas loop
      if p_valor ? v_col and nullif(trim(coalesce(p_valor->>v_col, '')), '') is not null then
        v_alguna := true;
      end if;
    end loop;
    if not v_alguna then
      raise exception 'La corrección debe incluir al menos un dato a corregir, y no puede quedar vacío.';
    end if;
    return;
  end if;

  -- Los demás campos exigen que estén presentes todas sus columnas declaradas.
  foreach v_col in array v_columnas loop
    if not (p_valor ? v_col) then
      raise exception 'Falta el dato «%» para este campo.', v_col;
    end if;
  end loop;

  if p_campo = 'hijos_menores' and jsonb_typeof(p_valor->'hijos_menores') <> 'boolean' then
    raise exception 'Hijos menores a cargo debe ser verdadero o falso.';
  end if;
  if p_campo = 'discapacidad' and jsonb_typeof(p_valor->'discapacidad') <> 'boolean' then
    raise exception 'Discapacidad debe ser verdadero o falso.';
  end if;
end;
$fn$;

revoke all on function fn_validar_valor_propuesto(text, jsonb) from public, anon, authenticated;


-- ── H · Crear la solicitud ──────────────────────────────────────────────────
create or replace function fn_crear_solicitud_perfil(
  p_campo           text,
  p_valor_propuesto jsonb,
  p_rutas_adjuntas  text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_persona uuid := fn_persona_actual_id();
  v_requiere_doc boolean;
  v_ruta text;
  v_id uuid;
begin
  if v_persona is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.';
  end if;

  select requiere_documento into v_requiere_doc from catalogo_campos_perfil where campo = p_campo;
  if v_requiere_doc is null then
    raise exception 'Campo de perfil desconocido: %', p_campo;
  end if;

  perform fn_validar_valor_propuesto(p_campo, p_valor_propuesto);

  if v_requiere_doc and coalesce(array_length(p_rutas_adjuntas, 1), 0) = 0 then
    raise exception 'Este cambio exige adjuntar al menos un documento de sustento.';
  end if;

  foreach v_ruta in array p_rutas_adjuntas loop
    if v_ruta !~ ('^solicitud/' || v_persona::text || '/') then
      raise exception 'Uno de los archivos adjuntos no pertenece a tu carpeta.';
    end if;
  end loop;

  -- Reemplaza cualquier pendiente anterior sobre el mismo campo — nunca para
  -- familiar_nuevo (ver el índice único parcial, admite varias en paralelo).
  if p_campo <> 'familiar_nuevo' then
    update solicitudes_cambio_perfil
    set estado = 'reemplazada', resuelta_at = now(), resuelta_por = v_persona
    where persona_id = v_persona and campo = p_campo and estado = 'pendiente';
  end if;

  insert into solicitudes_cambio_perfil
    (persona_id, campo, valor_anterior, valor_propuesto, rutas_adjuntas)
  values
    (v_persona, p_campo, fn_snapshot_valor_actual(v_persona, p_campo), p_valor_propuesto, p_rutas_adjuntas)
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Ya tienes una solicitud pendiente sobre ese campo. Espera a que se resuelva.';
end;
$fn$;

grant execute on function fn_crear_solicitud_perfil(text, jsonb, text[]) to authenticated;
revoke execute on function fn_crear_solicitud_perfil(text, jsonb, text[]) from public, anon;


-- ── I · Leer ─────────────────────────────────────────────────────────────
create or replace function fn_mis_solicitudes_perfil()
returns table (
  id uuid, campo text, etiqueta text, valor_anterior jsonb, valor_propuesto jsonb,
  estado text, creada_at timestamptz, resuelta_at timestamptz, motivo text
)
language sql stable security definer set search_path = public as $fn$
  select s.id, s.campo, c.etiqueta, s.valor_anterior, s.valor_propuesto,
         s.estado, s.creada_at, s.resuelta_at, s.motivo
  from solicitudes_cambio_perfil s
  join catalogo_campos_perfil c on c.campo = s.campo
  where s.persona_id = fn_persona_actual_id()
  order by s.creada_at desc;
$fn$;
grant execute on function fn_mis_solicitudes_perfil() to authenticated;
revoke execute on function fn_mis_solicitudes_perfil() from public, anon;

create or replace function fn_solicitudes_perfil_pendientes()
returns table (
  id uuid, persona_id uuid, nombre text, sede text, campo text, etiqueta text,
  valor_anterior jsonb, valor_propuesto jsonb, rutas_adjuntas text[], creada_at timestamptz
)
language sql stable security definer set search_path = public as $fn$
  select s.id, s.persona_id, pe.nombres || ' ' || pe.apellidos, sd.codigo,
         s.campo, c.etiqueta, s.valor_anterior, s.valor_propuesto, s.rutas_adjuntas, s.creada_at
  from solicitudes_cambio_perfil s
  join personas pe on pe.id = s.persona_id
  join sedes sd on sd.id = pe.sede_base_id
  join catalogo_campos_perfil c on c.campo = s.campo
  where s.estado = 'pendiente' and fn_es_admin_o_lider() is true
  order by s.creada_at asc;
$fn$;
grant execute on function fn_solicitudes_perfil_pendientes() to authenticated;
revoke execute on function fn_solicitudes_perfil_pendientes() from public, anon;


-- ── J · Aplicar el cambio real (llamada solo desde fn_resolver_solicitud_perfil) ─
create or replace function fn_aplicar_cambio_perfil(p_solicitud_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_s solicitudes_cambio_perfil%rowtype;
  v_quien uuid := fn_persona_actual_id();
  v_motivo text;
begin
  select * into v_s from solicitudes_cambio_perfil where id = p_solicitud_id;
  if not found then
    raise exception 'Esa solicitud no existe.';
  end if;

  v_motivo := 'Aprobado por solicitud de perfil — ver solicitudes_cambio_perfil.id=' || v_s.id;

  case v_s.campo
    when 'celular' then
      insert into datos_personales (persona_id, celular) values (v_s.persona_id, v_s.valor_propuesto->>'celular')
      on conflict (persona_id) do update set celular = excluded.celular;

    when 'direccion' then
      insert into datos_personales (persona_id, direccion) values (v_s.persona_id, v_s.valor_propuesto->>'direccion')
      on conflict (persona_id) do update set direccion = excluded.direccion;

    when 'contacto_emergencia' then
      insert into datos_personales (persona_id, emergencia_nombre, emergencia_vinculo, emergencia_telefono)
      values (v_s.persona_id, v_s.valor_propuesto->>'emergencia_nombre',
              v_s.valor_propuesto->>'emergencia_vinculo', v_s.valor_propuesto->>'emergencia_telefono')
      on conflict (persona_id) do update set
        emergencia_nombre = excluded.emergencia_nombre,
        emergencia_vinculo = excluded.emergencia_vinculo,
        emergencia_telefono = excluded.emergencia_telefono;

    when 'estado_civil' then
      insert into datos_personales (persona_id, estado_civil) values (v_s.persona_id, v_s.valor_propuesto->>'estado_civil')
      on conflict (persona_id) do update set estado_civil = excluded.estado_civil;

    when 'hijos_menores' then
      insert into datos_personales (persona_id, hijos_menores)
      values (v_s.persona_id, (v_s.valor_propuesto->>'hijos_menores')::boolean)
      on conflict (persona_id) do update set hijos_menores = excluded.hijos_menores;

    when 'grado_instruccion' then
      insert into datos_personales (persona_id, grado_instruccion)
      values (v_s.persona_id, v_s.valor_propuesto->>'grado_instruccion')
      on conflict (persona_id) do update set grado_instruccion = excluded.grado_instruccion;

    when 'discapacidad' then
      insert into datos_personales (persona_id, discapacidad, discapacidad_conadis)
      values (v_s.persona_id, (v_s.valor_propuesto->>'discapacidad')::boolean, v_s.valor_propuesto->>'discapacidad_conadis')
      on conflict (persona_id) do update set
        discapacidad = excluded.discapacidad, discapacidad_conadis = excluded.discapacidad_conadis;

    when 'cuenta_bancaria' then
      insert into datos_personales (persona_id, entidad_bancaria, numero_cuenta)
      values (v_s.persona_id, v_s.valor_propuesto->>'entidad_bancaria', v_s.valor_propuesto->>'numero_cuenta')
      on conflict (persona_id) do update set
        entidad_bancaria = excluded.entidad_bancaria, numero_cuenta = excluded.numero_cuenta;

    when 'cuspp' then
      insert into datos_personales (persona_id, cuspp)
      values (v_s.persona_id, nullif(upper(trim(v_s.valor_propuesto->>'cuspp')), ''))
      on conflict (persona_id) do update set cuspp = excluded.cuspp;

    when 'correccion_identidad' then
      if v_s.valor_propuesto ? 'documento' then
        perform fn_set_documento(v_s.persona_id, v_s.valor_propuesto->>'documento', v_motivo);
      end if;
      if (v_s.valor_propuesto ? 'nombre_dni') or (v_s.valor_propuesto ? 'fecha_nacimiento') or (v_s.valor_propuesto ? 'genero') then
        insert into datos_personales (persona_id, nombre_dni, fecha_nacimiento, genero)
        values (v_s.persona_id,
                coalesce(v_s.valor_propuesto->>'nombre_dni', (select nombre_dni from datos_personales where persona_id = v_s.persona_id)),
                coalesce((v_s.valor_propuesto->>'fecha_nacimiento')::date, (select fecha_nacimiento from datos_personales where persona_id = v_s.persona_id)),
                coalesce(v_s.valor_propuesto->>'genero', (select genero from datos_personales where persona_id = v_s.persona_id)))
        on conflict (persona_id) do update set
          nombre_dni = excluded.nombre_dni, fecha_nacimiento = excluded.fecha_nacimiento, genero = excluded.genero;

        insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
        values (v_s.persona_id, 'datos_personales.correccion_identidad',
                v_s.valor_anterior::text, v_s.valor_propuesto::text, v_motivo, v_quien);
      end if;

    when 'familiar_nuevo' then
      perform fn_set_derechohabiente(
        null, v_s.persona_id,
        v_s.valor_propuesto->>'nombres', v_s.valor_propuesto->>'apellidos', v_s.valor_propuesto->>'vinculo',
        v_s.valor_propuesto->>'documento', (v_s.valor_propuesto->>'fecha_nacimiento')::date,
        false, false, v_motivo);

    else
      raise exception 'No sé cómo aplicar el campo: %', v_s.campo;
  end case;

  -- Tarea de seguimiento a planilla — solo para estos dos, y solo aquí (al
  -- aprobar), nunca al crear la solicitud.
  if v_s.campo in ('estado_civil', 'hijos_menores') then
    insert into seguimiento_planilla_por_solicitud (solicitud_id, persona_id, campo, descripcion)
    select v_s.id, v_s.persona_id, v_s.campo,
           'Revisar planilla — ' || pe.nombres || ' ' || pe.apellidos || ' — ' || c.etiqueta
    from personas pe, catalogo_campos_perfil c
    where pe.id = v_s.persona_id and c.campo = v_s.campo
    on conflict (solicitud_id) do nothing;
  end if;
end;
$fn$;

revoke all on function fn_aplicar_cambio_perfil(uuid) from public, anon, authenticated;


-- ── K · Resolver (aprobar/rechazar) — solo DO ──────────────────────────────
create or replace function fn_resolver_solicitud_perfil(
  p_id      uuid,
  p_aprobar boolean,
  p_motivo  text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_s solicitudes_cambio_perfil%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede resolver una solicitud de perfil.';
  end if;

  select * into v_s from solicitudes_cambio_perfil where id = p_id;
  if not found then
    raise exception 'Esa solicitud ya no existe.';
  end if;
  if v_s.estado <> 'pendiente' then
    raise exception 'Esa solicitud ya fue % — no se puede resolver dos veces.', v_s.estado;
  end if;

  if p_aprobar then
    perform fn_aplicar_cambio_perfil(p_id);
    update solicitudes_cambio_perfil
    set estado = 'aprobado', resuelta_at = now(), resuelta_por = fn_persona_actual_id(),
        motivo = nullif(trim(coalesce(p_motivo, '')), '')
    where id = p_id;
  else
    if coalesce(trim(p_motivo), '') = '' then
      raise exception 'Para rechazar hace falta decir por qué, aunque sea en una línea.';
    end if;
    update solicitudes_cambio_perfil
    set estado = 'rechazado', resuelta_at = now(), resuelta_por = fn_persona_actual_id(),
        motivo = trim(p_motivo)
    where id = p_id;
  end if;
end;
$fn$;

grant execute on function fn_resolver_solicitud_perfil(uuid, boolean, text) to authenticated;
revoke execute on function fn_resolver_solicitud_perfil(uuid, boolean, text) from public, anon;


-- ── L · Resolver la tarea de seguimiento a planilla ────────────────────────
create or replace function fn_resolver_seguimiento_planilla(p_id uuid, p_nota text default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede marcar esto como resuelto.';
  end if;

  update seguimiento_planilla_por_solicitud
  set estado = 'resuelta', resuelta_por = fn_persona_actual_id(), resuelta_at = now(),
      nota = nullif(trim(coalesce(p_nota, '')), '')
  where id = p_id and estado = 'pendiente';

  if not found then
    raise exception 'Esa tarea no existe o ya estaba resuelta.';
  end if;
end;
$fn$;

grant execute on function fn_resolver_seguimiento_planilla(uuid, text) to authenticated;
revoke execute on function fn_resolver_seguimiento_planilla(uuid, text) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (399, 'el_colaborador_propone_do_aprueba')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) from information_schema.tables where table_name = 'catalogo_campos_perfil') as tabla_catalogo,
  (select count(*) from catalogo_campos_perfil) as filas_catalogo,
  (select count(*) from information_schema.tables where table_name = 'solicitudes_cambio_perfil') as tabla_solicitudes,
  (select count(*) from information_schema.tables where table_name = 'seguimiento_planilla_por_solicitud') as tabla_seguimiento,
  (select public from storage.buckets where id = 'solicitudes-perfil') is false as el_bucket_es_privado,
  (select count(*) from pg_policies where tablename = 'objects' and schemaname = 'storage'
     and policyname like 'solicitud_perfil_%') = 4 as las_cuatro_politicas_existen,
  (select count(*) from pg_proc where proname = 'fn_crear_solicitud_perfil') as fn_crear,
  (select count(*) from pg_proc where proname = 'fn_resolver_solicitud_perfil') as fn_resolver,
  (select prosrc not like '%fn_persona_actual_id() then%' from pg_proc where proname='fn_set_datos_personales') as ojo_manual;
