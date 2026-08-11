-- ============================================================================
-- 0208_el_reglamento_se_entrega_y_queda_constancia.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el Reglamento Interno de Trabajo —y cualquier otro documento que la
--   empresa tenga que hacer conocer— viva DENTRO del sistema, versionado, y que
--   de cada entrega quede constancia de quién la recibió y DE QUÉ VERSIÓN.
--
-- QUÉ ASUME
--   Nada nuevo. Tablas nuevas, funciones nuevas, un almacén nuevo. No toca
--   ninguna función existente ni mueve un solo dato.
--
-- ── POR QUÉ HACE FALTA ──────────────────────────────────────────────────────
--
-- El RIT promete en su propio articulado que se entrega «dejando constancia
-- escrita de su recepción», y el D.S. 039-91-TR da cinco días naturales para
-- esa entrega. Hoy el reglamento vive en un enlace de Drive —que además se
-- cayó— y no hay forma de probar quién recibió qué.
--
-- Y hay algo que esta pantalla hace y el papel no puede: **un cargo firmado a
-- mano dice que recibiste UN reglamento; no dice cuál versión.** Cuando el v4.0
-- sustituya al v3.0, esa diferencia es exactamente la que importa.
--
-- ── POR QUÉ GENÉRICO Y NO UNA TABLA PARA EL RIT ─────────────────────────────
--
-- Porque el RIT no va a estar solo. El propio reglamento declara documentos
-- complementarios, y el día que se publique cualquiera de ellos, una tabla
-- llamada `reglamento_interno` obligaría a una migración nueva para algo que es
-- un dato. Regla 3 del CLAUDE.md: nunca una lista escrita a mano de algo que
-- vive en una tabla. `documentos_tipos` es esa tabla, y se administra desde la
-- pantalla.
--
-- ── POR QUÉ EL TEXTO SE CONGELA, Y NO SE REGENERA ───────────────────────────
--
-- Es la lección de la 0141, y aquí pesa igual. Si el documento se regenerara
-- cada vez que alguien lo abre, el día que cambie una coma **todos los acuses
-- previos pasarían a apuntar a un texto que nadie firmó**. La prueba de haber
-- informado se evaporaría en silencio, sin que ningún error saltara.
--
-- Congelado, un acuse de agosto sigue apuntando al documento de agosto.
--
-- ── POR QUÉ DOS VÍAS DE CONSTANCIA, Y NO SOLO LA PANTALLA ───────────────────
--
-- Medido en producción el 2026-08-10: de **24 personas activas, 17 tienen
-- cuenta y 7 no**. Casi un tercio del equipo no puede entrar al panel a dejar
-- constancia. Una pantalla que solo admitiera el acuse propio dejaría fuera a
-- esas siete y la prueba estaría incompleta justo donde más se mira.
--
--   via = 'sistema'  la deja la propia persona, y escribe su nombre. No es un
--                    requisito legal: es lo que convierte un clic en un acto
--                    deliberado (misma decisión que la 0141).
--   via = 'papel'    la registra Desarrollo Organizacional POR alguien, y exige
--                    el escaneo del cargo firmado. Sin el papel no se registra:
--                    aquí la constancia ES la prueba, y una fila sin respaldo
--                    solo sería la afirmación de quien la escribió.
--
-- ── EL ALMACÉN, Y LA TRAMPA QUE YA COSTÓ UN MÓDULO ──────────────────────────
--
-- Supabase Storage no escribe el objeto con un INSERT: escribe
-- `INSERT … ON CONFLICT DO UPDATE … RETURNING *`, y esa forma necesita TRES
-- permisos, no uno — INSERT por la fila, SELECT por el RETURNING y UPDATE por
-- el ON CONFLICT. Es lo que la 0172 tuvo que reparar cuando se descubrió que
-- ningún cargo firmado de un memo se había podido subir NUNCA desde que el
-- módulo existía. Las tres políticas van puestas desde el primer día.
--
-- Se aceptan HEIC/HEIF porque es el formato en que un iPhone guarda sus fotos
-- (lección de la 0170: sin eso, salían en gris en el diálogo de archivos y la
-- pantalla no daba ningún error).
--
-- ── EL PERMISO, QUE ESTE REPOSITORIO YA PERDIÓ UNA VEZ ──────────────────────
--
-- Desde la 0076 este proyecto revoca el EXECUTE que Postgres da a PUBLIC por
-- defecto, así que toda función nueva nace SIN permiso para `authenticated` y
-- hay que concedérselo a mano. Olvidarlo no da error al aplicar: da una
-- pantalla vacía. Es lo que la 0204 tuvo que reponer. Cada función de aquí
-- lleva su grant al lado.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   drop function if exists fn_acuses_documento(uuid);
--   drop function if exists fn_documentos_vigentes();
--   drop function if exists fn_registrar_acuse_papel(uuid, uuid, text, timestamptz, text);
--   drop function if exists fn_acusar_documento(uuid, text);
--   drop function if exists fn_publicar_documento(text, text, text, date, text);
--   drop table if exists documentos_acuses;
--   drop table if exists documentos_institucionales;
--   drop table if exists documentos_tipos;
--   delete from storage.buckets where id = 'acuses';
--   Revertir significa volver a no poder probar que el reglamento se entregó.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

-- ── 1 · Qué clases de documento existen ─────────────────────────────────────
-- Se administra desde la pantalla. El código NUNCA escribe esta lista.
create table if not exists documentos_tipos (
  codigo         text primary key check (codigo ~ '^[a-z0-9_]{2,40}$'),
  nombre         text not null check (btrim(nombre) <> ''),
  orden          int  not null default 100,
  requiere_acuse boolean not null default true,
  activo         boolean not null default true
);

comment on table documentos_tipos is
  'Las clases de documento institucional que la empresa publica. Vive en tabla y no en el codigo para que anadir uno no exija una migracion.';
comment on column documentos_tipos.requiere_acuse is
  'Si es false, el documento se publica para consulta pero no se le pide constancia a nadie.';

insert into documentos_tipos (codigo, nombre, orden, requiere_acuse)
values ('rit', 'Reglamento Interno de Trabajo', 10, true)
on conflict (codigo) do nothing;

-- ── 2 · Las versiones publicadas, con el texto congelado ────────────────────
create table if not exists documentos_institucionales (
  id            uuid primary key default gen_random_uuid(),
  tipo          text not null references documentos_tipos(codigo),
  version       int  not null check (version > 0),
  titulo        text not null check (btrim(titulo) <> ''),
  documento     text not null check (btrim(documento) <> ''),
  notas         text,
  vigente_desde date not null,
  publicado_por uuid references personas(id),
  publicado_at  timestamptz not null default now(),
  unique (tipo, version)
);

comment on table documentos_institucionales is
  'Cada version publicada de un documento institucional, con su texto congelado. Congelado y no regenerado: si se regenerara, cambiar una coma dejaria todos los acuses previos apuntando a un texto que nadie firmo.';
comment on column documentos_institucionales.documento is
  'El texto literal que se comunico. Es la prueba: tiene que poder mostrarse igual dentro de cinco anios.';
comment on column documentos_institucionales.vigente_desde is
  'Desde cuando rige esta version. No es la fecha de publicacion: un reglamento puede publicarse hoy y regir el primero del mes que viene.';

create index if not exists idx_documentos_tipo_version
  on documentos_institucionales(tipo, version desc);

-- ── 3 · Las constancias ─────────────────────────────────────────────────────
create table if not exists documentos_acuses (
  documento_id     uuid not null references documentos_institucionales(id) on delete cascade,
  persona_id       uuid not null references personas(id),
  via              text not null check (via in ('sistema', 'papel')),
  nombre_declarado text,
  acusado_at       timestamptz not null default now(),
  registrado_por   uuid references personas(id),
  storage_path     text,
  nota             text,
  primary key (documento_id, persona_id),
  -- Cada via prueba de una forma distinta, y ninguna de las dos vale a medias.
  constraint chk_acuse_coherente check (
    (via = 'sistema'
       and nombre_declarado is not null and btrim(nombre_declarado) <> ''
       and registrado_por is null)
    or
    (via = 'papel'
       and storage_path is not null and btrim(storage_path) <> ''
       and registrado_por is not null)
  )
);

comment on table documentos_acuses is
  'Constancia de que una persona recibio una VERSION concreta de un documento. Una fila por persona y version: no se acusa dos veces lo mismo, y publicar una version nueva vuelve a pedir constancia a todo el mundo.';
comment on column documentos_acuses.via is
  'sistema = la dejo la propia persona desde el panel. papel = la registro DO por alguien sin cuenta, con el escaneo del cargo firmado adjunto.';

create index if not exists idx_acuses_documento on documentos_acuses(documento_id);
create index if not exists idx_acuses_persona   on documentos_acuses(persona_id);

-- ── 4 · Quien ve que ────────────────────────────────────────────────────────
alter table documentos_tipos            enable row level security;
alter table documentos_institucionales  enable row level security;
alter table documentos_acuses           enable row level security;

-- Los documentos los lee TODO el mundo: hacerlos conocer es justamente la
-- obligacion que esta migracion viene a cumplir.
drop policy if exists documentos_tipos_lectura on documentos_tipos;
create policy documentos_tipos_lectura on documentos_tipos
  for select to authenticated using (true);

drop policy if exists documentos_lectura on documentos_institucionales;
create policy documentos_lectura on documentos_institucionales
  for select to authenticated using (true);

-- Cada quien ve SU constancia; administracion y lideres ven todas.
drop policy if exists documentos_acuses_lectura on documentos_acuses;
create policy documentos_acuses_lectura on documentos_acuses
  for select to authenticated
  using (persona_id = fn_persona_actual_id() or fn_es_admin_o_lider() is true);

-- Escribir pasa SIEMPRE por las funciones de abajo, nunca por insert directo.

-- ── 5 · Publicar una version ────────────────────────────────────────────────
create or replace function fn_publicar_documento(
  p_tipo          text,
  p_titulo        text,
  p_documento     text,
  p_vigente_desde date default null,
  p_notas         text default null
)
returns int
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_yo      uuid;
  v_version int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider de DO puede publicar un documento institucional.';
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien publica, asi que no puedo auditarlo. Inicia sesion con tu usuario.';
  end if;

  if not exists (select 1 from documentos_tipos where codigo = p_tipo and activo) then
    raise exception 'No existe un tipo de documento activo con codigo "%".', p_tipo;
  end if;

  if p_documento is null or btrim(p_documento) = '' then
    raise exception 'No se puede publicar un documento vacio.';
  end if;

  -- Publicar dos veces EL MISMO texto no crea version nueva: obligaria a las 24
  -- personas a dejar constancia otra vez de algo que no cambio, y una constancia
  -- que se pide sin motivo ensena que la constancia es tramite.
  select version into v_version
  from documentos_institucionales
  where tipo = p_tipo and documento = p_documento
  order by version desc limit 1;

  if v_version is not null then
    return v_version;
  end if;

  select coalesce(max(version), 0) + 1 into v_version
  from documentos_institucionales where tipo = p_tipo;

  insert into documentos_institucionales
    (tipo, version, titulo, documento, notas, vigente_desde, publicado_por)
  values
    (p_tipo, v_version, btrim(p_titulo), p_documento,
     nullif(btrim(coalesce(p_notas, '')), ''),
     coalesce(p_vigente_desde, fn_hoy_lima()), v_yo);

  return v_version;
end;
$fn$;

grant  execute on function fn_publicar_documento(text, text, text, date, text) to authenticated;
revoke execute on function fn_publicar_documento(text, text, text, date, text) from public, anon;

-- ── 6 · Dejar constancia uno mismo ──────────────────────────────────────────
create or replace function fn_acusar_documento(
  p_documento_id     uuid,
  p_nombre_declarado text
)
returns void
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_yo uuid;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien deja la constancia. Inicia sesion con tu usuario.';
  end if;

  if p_nombre_declarado is null or btrim(p_nombre_declarado) = '' then
    raise exception 'Escribe tu nombre para dejar constancia.';
  end if;

  if not exists (select 1 from documentos_institucionales where id = p_documento_id) then
    raise exception 'Ese documento no existe.';
  end if;

  -- Una constancia no se rectifica sola: si ya esta, se queda como esta. Volver
  -- a escribirla borraria la fecha real de la primera, que es lo que prueba.
  insert into documentos_acuses (documento_id, persona_id, via, nombre_declarado)
  values (p_documento_id, v_yo, 'sistema', btrim(p_nombre_declarado))
  on conflict (documento_id, persona_id) do nothing;
end;
$fn$;

grant  execute on function fn_acusar_documento(uuid, text) to authenticated;
revoke execute on function fn_acusar_documento(uuid, text) from public, anon;

-- ── 7 · Registrar la constancia en papel de quien no tiene cuenta ───────────
create or replace function fn_registrar_acuse_papel(
  p_documento_id uuid,
  p_persona_id   uuid,
  p_path         text,
  p_acusado_at   timestamptz default null,
  p_nota         text default null
)
returns void
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_yo uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider de DO puede registrar una constancia en papel.';
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien registra, asi que no puedo auditarlo. Inicia sesion con tu usuario.';
  end if;

  if p_path is null or btrim(p_path) = '' then
    raise exception 'Falta el escaneo del cargo firmado. Sin el papel no hay constancia que registrar.';
  end if;

  if not exists (select 1 from documentos_institucionales where id = p_documento_id) then
    raise exception 'Ese documento no existe.';
  end if;

  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Esa persona no existe.';
  end if;

  -- La fecha buena es la del papel, no la de hoy: entre firmar y escanear pueden
  -- pasar dias, y de la fecha de recepcion cuelgan los plazos.
  if p_acusado_at is not null and p_acusado_at > now() then
    raise exception 'La fecha de recepcion no puede estar en el futuro.';
  end if;

  insert into documentos_acuses
    (documento_id, persona_id, via, acusado_at, registrado_por, storage_path, nota)
  values
    (p_documento_id, p_persona_id, 'papel', coalesce(p_acusado_at, now()), v_yo,
     btrim(p_path), nullif(btrim(coalesce(p_nota, '')), ''))
  on conflict (documento_id, persona_id) do nothing;
end;
$fn$;

grant  execute on function fn_registrar_acuse_papel(uuid, uuid, text, timestamptz, text) to authenticated;
revoke execute on function fn_registrar_acuse_papel(uuid, uuid, text, timestamptz, text) from public, anon;

-- ── 8 · Que hay publicado, y si me toca dejar constancia ────────────────────
create or replace function fn_documentos_vigentes()
returns table (
  documento_id   uuid,
  tipo           text,
  tipo_nombre    text,
  version        int,
  titulo         text,
  documento      text,
  vigente_desde  date,
  publicado_at   timestamptz,
  requiere_acuse boolean,
  mi_acuse_at    timestamptz,
  total_acuses   int,
  poblacion      int
)
language sql stable security definer set search_path = public
as $fn$
  with ultimas as (
    select distinct on (d.tipo) d.*
    from documentos_institucionales d
    order by d.tipo, d.version desc
  ),
  -- Quien tiene que recibirlo: toda persona activa. Los locadores no estan
  -- comprendidos por el reglamento, asi que tampoco cuentan aqui.
  poblacion as (
    select count(*)::int as n from personas
    where estado = 'activo' and en_planilla is true
  )
  select u.id, u.tipo, t.nombre, u.version, u.titulo, u.documento,
         u.vigente_desde, u.publicado_at, t.requiere_acuse,
         (select a.acusado_at from documentos_acuses a
           where a.documento_id = u.id and a.persona_id = fn_persona_actual_id()),
         (select count(*)::int from documentos_acuses a where a.documento_id = u.id),
         (select n from poblacion)
  from ultimas u
  join documentos_tipos t on t.codigo = u.tipo
  where t.activo
  order by t.orden, t.nombre;
$fn$;

grant  execute on function fn_documentos_vigentes() to authenticated;
revoke execute on function fn_documentos_vigentes() from public, anon;

-- ── 9 · Quien falta por dejar constancia ────────────────────────────────────
create or replace function fn_acuses_documento(p_documento_id uuid)
returns table (
  persona_id uuid,
  nombre     text,
  sede       text,
  tiene_cuenta boolean,
  acusado_at timestamptz,
  via        text
)
language sql stable security definer set search_path = public
as $fn$
  -- Devuelve vacio para quien no puede verlo, en vez de fallar: la pantalla
  -- sigue funcionando y simplemente no muestra el panel de seguimiento.
  select p.id, p.nombres || ' ' || p.apellidos, s.codigo,
         p.auth_user_id is not null,
         a.acusado_at, a.via
  from personas p
  join sedes s on s.id = p.sede_base_id
  left join documentos_acuses a
         on a.persona_id = p.id and a.documento_id = p_documento_id
  where p.estado = 'activo' and p.en_planilla is true
    and fn_es_admin_o_lider() is true
  order by (a.acusado_at is not null), s.codigo, p.nombres;
$fn$;

grant  execute on function fn_acuses_documento(uuid) to authenticated;
revoke execute on function fn_acuses_documento(uuid) from public, anon;

-- ── 10 · El almacen de los cargos escaneados ────────────────────────────────
-- Privado: son papeles firmados por personas. Se leen con URL firmada de vida
-- corta, como los del expediente disciplinario.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'acuses', 'acuses', false, 52428800,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf']
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- LAS TRES POLITICAS. No son tres por prolijidad: Supabase Storage escribe con
-- INSERT … ON CONFLICT DO UPDATE … RETURNING *, y esa sentencia necesita las
-- tres. Con una sola, subir un archivo falla y el mensaje de Postgres nombra la
-- tabla pero NO dice cual politica falto. Ver la 0172.
drop policy if exists acuses_insert on storage.objects;
create policy acuses_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'acuses' and fn_es_admin_o_lider() is true);

drop policy if exists acuses_select on storage.objects;
create policy acuses_select on storage.objects
  for select to authenticated
  using (bucket_id = 'acuses' and fn_es_admin_o_lider() is true);

drop policy if exists acuses_update on storage.objects;
create policy acuses_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'acuses' and fn_es_admin_o_lider() is true)
  with check (bucket_id = 'acuses' and fn_es_admin_o_lider() is true);

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (208, 'el_reglamento_se_entrega_y_queda_constancia')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobacion ────────────────────────────────────────────────────────────
-- Va la ULTIMA a proposito: el SQL Editor solo muestra el resultado de la
-- ultima consulta. Las cinco columnas tienen que decir SI.
select
  (select count(*) from documentos_tipos where codigo = 'rit') = 1
    as el_tipo_rit_existe,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_publicar_documento','fn_acusar_documento',
                        'fn_registrar_acuse_papel','fn_documentos_vigentes',
                        'fn_acuses_documento')) = 5
    as las_cinco_funciones_estan,
  -- La comprobacion que la 0204 ensenio a hacer: existir no basta, hay que
  -- poder ejecutarlas desde el navegador.
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_publicar_documento','fn_acusar_documento',
                        'fn_registrar_acuse_papel','fn_documentos_vigentes',
                        'fn_acuses_documento'))
    as el_navegador_las_puede_ejecutar,
  -- La que la 0172 ensenio a hacer: sin las TRES, no se puede subir un archivo.
  (select count(*) from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('acuses_insert','acuses_select','acuses_update')) = 3
    as el_almacen_tiene_sus_tres_politicas,
  (select count(*) from storage.buckets where id = 'acuses' and not public) = 1
    as el_almacen_es_privado;
