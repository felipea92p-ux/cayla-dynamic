-- ============================================================================
-- 0503_el_archivo_de_la_empresa.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que los papeles que CAYLA presenta o recibe de una autoridad —la constancia
--   de inscripción de un banco de datos personales, la de REMYPE, una licencia
--   de funcionamiento, un certificado de Defensa Civil, la ficha RUC, una
--   vigencia de poder— vivan DENTRO de Dynamic, en un archivo que solo ve
--   Desarrollo Organizacional, y que de cada uno quede escrito quién lo subió,
--   cuándo, qué dice y hasta cuándo vale. Para tenerlos a la mano el día de una
--   inspección o una fiscalización.
--
--   Nada se borra. Corregir un dato o traer la versión nueva de un papel crea
--   una ficha nueva que REEMPLAZA a la anterior, y la anterior queda en el
--   historial. Un papel que dejó de aplicar se RETIRA, con motivo escrito.
--
-- QUÉ ASUME
--   · `fn_es_admin_o_lider()` es «DO» (0078): dirección y quien lleva DO. La
--     líder de equipo NO ve este archivo (ver «SE ROMPE SI»).
--   · `fn_persona_actual_id()` identifica a quien llama.
--   · Que el navegador sube el archivo al bucket `archivo-empresa` ANTES de
--     llamar a `fn_archivo_subir`. Ver «POR QUÉ EL ARCHIVO VA PRIMERO».
--   · Que Storage guarda el peso y el tipo de cada archivo en
--     `storage.objects.metadata` (`size`, `mimetype`). La función los lee de
--     ahí: no confía en lo que el navegador diga que subió (molde de la 0482).
--
-- ── POR QUÉ UNA TABLA NUEVA Y NO UNA QUE YA EXISTE ───────────────────────────
--
--   Hasta hoy, TODO lo que se sube a Dynamic cuelga de una persona: contratos,
--   certificados médicos, cargos firmados, fotos del DNI, boletas. Este papel
--   es de la empresa.
--
--   Se descartó `documentos_institucionales` (Normas, 0208): es lo que la
--   empresa le COMUNICA al equipo, lo lee toda cuenta con sesión
--   (`using (true)`) y guarda texto, no archivos. La constancia de inscripción
--   de un banco de datos lleva el DNI del representante legal; publicarla ahí
--   la ponía a la vista de todo el equipo.
--   Se descartó `documentos_firmados` (Documentación, 0157): tiene
--   `alcance = 'empresa'`, pero su `tipo` solo admite ruta, política y bono, y
--   alimenta los contadores de pendientes de cada persona.
--   Se descartó una carpeta de Drive: el Reglamento ya vivió en un enlace de
--   Drive que se cayó (0208), y ahí no queda quién subió qué ni cuándo vence.
--
-- ── POR QUÉ «REEMPLAZAR» Y NO «EDITAR» ───────────────────────────────────────
--
--   Una ficha no se edita nunca. Corregir el título, la fecha o la sede crea
--   una ficha nueva que apunta a la anterior (`reemplaza_a`) y PUEDE usar el
--   mismo archivo: la ruta no es única a propósito. Así hay UN solo camino para
--   las dos cosas —traer la versión nueva de un certificado y arreglar un dato
--   mal escrito— y el historial dice siempre qué decía la ficha antes.
--
--   No hay tabla de «categorías»: se agrupa por `entidad` (quién emite el
--   papel), que es como lo pide quien inspecciona. La pantalla sugiere las
--   entidades ya usadas para que no aparezcan «ANPD» y «MINJUS» como dos.
--
-- ── ESTADOS QUE NUNCA DEBEN EXISTIR (y qué los hace imposibles) ──────────────
--
--   · una ficha sin archivo ................................. not null + la
--       función exige que la ruta exista en Storage
--   · una ruta con nombres o DNI ............................ check de forma:
--       solo `<uuid>.<ext>`
--   · un papel que vence antes de emitirse ................... check
--   · un papel fechado en el futuro .......................... la función
--   · dos fichas que reemplazan a la misma (una bifurcación) . índice único
--       parcial sobre `reemplaza_a`
--   · reemplazar una ficha retirada .......................... la función,
--       con la fila bloqueada
--   · una ficha retirada sin motivo, o un motivo sin retiro .. check
--   · una ficha editada o borrada ............................ trigger: solo se
--       admite escribir el retiro, una vez, y solo desde el sistema
--   · alguien sin DO leyendo un papel ........................ RLS + política
--       de Storage
--   · pisar o borrar un archivo que una ficha usa ............ la política de
--       update/delete de Storage exige que nadie lo referencie
--
-- ── POR QUÉ NO SE ESCRIBE EN `correcciones_auditoria` ────────────────────────
--
--   Su `persona_id` es NOT NULL y este papel no es de nadie. El rastro vive en
--   la propia fila: `subido_por`/`subido_at`, y `retirado_*` para el retiro.
--   Como ninguna fila se edita, esas columnas no se pueden reescribir después.
--
-- ── POR QUÉ EL ARCHIVO VA PRIMERO (Werner Vogels) ────────────────────────────
--
--   El navegador sube el archivo y solo después pide crear la ficha. Si Storage
--   no responde, la subida falla entera y no queda ninguna fila: DO reintenta.
--   Si fuera al revés, una caída dejaría una ficha que nadie puede abrir. Un
--   archivo huérfano (subido y nunca registrado) es inofensivo: la política de
--   delete permite limpiarlo justamente porque nadie lo usa.
--
--   Se degrada así: sin Storage, DO no puede subir ni abrir papeles; la lista
--   de fichas sigue viéndose, porque vive en Postgres. No se pierde ningún dato.
--
-- ── CONCURRENCIA ─────────────────────────────────────────────────────────────
--
--   Dos personas de DO reemplazando o retirando la MISMA ficha a la vez: las
--   dos funciones la bloquean con `for update`, así que se ordenan. La segunda
--   recibe «esa ficha ya fue reemplazada» y no queda ninguna bifurcación; si
--   aun así llegaran a escribir, el índice único de `reemplaza_a` lo rechaza.
--
-- ── NÚMEROS (Jeff Dean) ──────────────────────────────────────────────────────
--
--   Hoy: dos PDF de 32 y 65 KB. Con cuatro sedes, en tres años: licencia y
--   Defensa Civil por sede, REMYPE, ficha RUC, vigencia de poder, bancos de
--   datos, acuerdos de encargo… del orden de 30 a 60 papeles, ~100 fichas
--   contando correcciones. Ninguna consulta necesita más índice que la llave.
--   Tope de 50 MB por archivo: el mismo de los demás buckets de papeles.
--
-- ── SE ROMPE SI ──────────────────────────────────────────────────────────────
--
--   El inspector llega a una tienda y quien está ahí es la líder de equipo: no
--   ve este archivo. Si eso pasa, se le abre la lectura de los papeles de SU
--   sede (`sede_id`), no del archivo entero.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists
--     fn_archivo_subir(text, text, text, text, text, date, date, uuid, text, uuid),
--     fn_archivo_retirar(uuid, text), fn_archivo_empresa(),
--     fn_archivo_libre(text);
--   drop policy archivo_empresa_insert/select/update/delete on storage.objects;
--   drop table archivo_empresa;   -- se lleva el trigger y su función con
--   drop function if exists fn_archivo_empresa_solo_retirar();
--   delete from storage.objects where bucket_id = 'archivo-empresa';  -- vaciar antes
--   delete from storage.buckets where id = 'archivo-empresa';
--   Nada de planilla, asistencia ni pago lee esta tabla: revertir solo quita la
--   pantalla. Ojo: borrarla destruye el registro de quién subió cada papel.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================


-- ── 1 · El bucket ────────────────────────────────────────────────────────────
-- Privado. Los papeles de una autoridad llegan casi siempre en PDF; las fotos
-- se admiten para el papel que solo existe impreso (una licencia colgada en la
-- tienda). HEIC porque así guarda un iPhone sus fotos (lección de la 0170).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('archivo-empresa', 'archivo-empresa', false, 52428800,
        array['application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;


-- ── 2 · La tabla ─────────────────────────────────────────────────────────────
create table if not exists archivo_empresa (
  id              uuid primary key default gen_random_uuid(),
  titulo          text not null check (char_length(btrim(titulo)) between 3 and 200),
  -- Quién emite el papel: «Autoridad Nacional de Protección de Datos
  -- Personales», «SUNAT», «Municipalidad de Trujillo». Texto libre a propósito.
  entidad         text not null check (char_length(btrim(entidad)) between 2 and 200),
  -- El número o código que trae el papel (INS-2026-5135). Opcional: no todos
  -- lo tienen.
  numero          text check (numero is null or char_length(btrim(numero)) between 1 and 100),
  fecha_documento date not null,
  vence_el        date,
  -- Vacía = vale para toda la empresa. Con sede = es de ese local (su licencia,
  -- su certificado de Defensa Civil).
  sede_id         uuid references sedes(id),
  nota            text check (nota is null or char_length(nota) <= 2000),
  -- `<uuid>.<ext>` y nada más: ni nombres ni DNI en la ruta. NO es única: una
  -- corrección reutiliza el archivo de la ficha que reemplaza.
  storage_path    text not null check (storage_path ~ '^[0-9a-f-]{36}\.[a-z0-9]{2,5}$'),
  -- El nombre con que se subió, para reconocerlo al abrirlo.
  nombre_archivo  text not null check (char_length(btrim(nombre_archivo)) between 1 and 255),
  mime            text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif')),
  bytes           bigint not null check (bytes > 0),
  reemplaza_a     uuid references archivo_empresa(id),
  subido_por      uuid not null references personas(id),
  subido_at       timestamptz not null default now(),
  retirado_at     timestamptz,
  retirado_por    uuid references personas(id),
  retirado_motivo text,
  constraint archivo_vence_despues_de_emitirse check (vence_el is null or vence_el >= fecha_documento),
  constraint archivo_no_se_reemplaza_a_si_mismo check (reemplaza_a is null or reemplaza_a <> id),
  constraint archivo_retiro_completo check (
    (retirado_at is null and retirado_por is null and retirado_motivo is null)
    or (retirado_at is not null and retirado_por is not null
        and char_length(btrim(retirado_motivo)) >= 5)
  )
);

comment on table archivo_empresa is
  'Papeles de la empresa ante autoridades (inscripciones, licencias, constancias). Solo DO. Una fila por ficha; ninguna se edita ni se borra: corregir es crear otra que la reemplaza. Escritura solo por fn_archivo_subir y fn_archivo_retirar.';
comment on column archivo_empresa.reemplaza_a is
  'La ficha que esta reemplaza. Una ficha es vigente si nadie la reemplaza y no está retirada.';
comment on column archivo_empresa.storage_path is
  'Ruta en el bucket archivo-empresa. No es única: una corrección de datos reutiliza el archivo.';

-- Una ficha se reemplaza UNA vez: sin esto, dos correcciones simultáneas
-- dejarían dos «vigentes» del mismo papel.
create unique index if not exists idx_archivo_empresa_reemplaza_a
  on archivo_empresa (reemplaza_a) where reemplaza_a is not null;
-- La política de Storage pregunta por la ruta en cada lectura.
create index if not exists idx_archivo_empresa_ruta on archivo_empresa (storage_path);


-- ── 3 · Lo que no se edita ni se borra ───────────────────────────────────────
-- Lo único que se escribe después de crear una ficha es su retiro, una vez, y
-- solo desde `fn_archivo_retirar`. Molde de campo sensible (0261, 0295, 0342,
-- 0482): un cliente por PostgREST conecta como `authenticated`; una función
-- `security definer` de esta migración corre como `postgres`.
create or replace function fn_archivo_empresa_solo_retirar()
returns trigger language plpgsql as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'Un papel del archivo no se borra: se retira, con motivo.';
  end if;
  if current_user <> 'postgres' then
    raise exception 'Una ficha del archivo solo se modifica desde el sistema.';
  end if;
  if old.retirado_at is not null then
    raise exception 'Esa ficha ya está retirada.';
  end if;
  if (new.titulo, new.entidad, new.numero, new.fecha_documento, new.vence_el, new.sede_id,
      new.nota, new.storage_path, new.nombre_archivo, new.mime, new.bytes, new.reemplaza_a,
      new.subido_por, new.subido_at, new.id)
     is distinct from
     (old.titulo, old.entidad, old.numero, old.fecha_documento, old.vence_el, old.sede_id,
      old.nota, old.storage_path, old.nombre_archivo, old.mime, old.bytes, old.reemplaza_a,
      old.subido_por, old.subido_at, old.id) then
    raise exception 'Una ficha del archivo no se edita: se reemplaza por otra.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists archivo_empresa_solo_retirar on archivo_empresa;
create trigger archivo_empresa_solo_retirar
  before update or delete on archivo_empresa
  for each row execute function fn_archivo_empresa_solo_retirar();


-- ── 4 · Permisos y RLS ───────────────────────────────────────────────────────
-- Leer: solo DO. Escribir: nadie directo; todo por las funciones de abajo. Se
-- quita lo que Supabase concede por defecto (incluye escribir y `truncate`).
alter table archivo_empresa enable row level security;

drop policy if exists archivo_empresa_select_do on archivo_empresa;
create policy archivo_empresa_select_do on archivo_empresa
  for select to authenticated using (fn_es_admin_o_lider() is true);

revoke all on archivo_empresa from anon, authenticated, public;
grant select on archivo_empresa to authenticated;


-- ── 5 · Storage ──────────────────────────────────────────────────────────────
-- Un archivo está «libre» si ninguna ficha lo usa: solo entonces se puede pisar
-- o borrar (limpiar un huérfano). Es lo que vuelve inmutable lo ya archivado.
create or replace function fn_archivo_libre(p_path text)
returns boolean
language sql stable security definer set search_path = public
as $fn$
  select not exists (select 1 from archivo_empresa a where a.storage_path = p_path);
$fn$;

grant execute on function fn_archivo_libre(text) to authenticated;
revoke execute on function fn_archivo_libre(text) from public, anon;

-- Las CUATRO políticas, no una: Supabase Storage escribe con
-- `INSERT … ON CONFLICT DO UPDATE … RETURNING *` y necesita insert, select y
-- update para subir (0172, 0175, 0197 costaron medio día por faltar una).
drop policy if exists archivo_empresa_insert on storage.objects;
drop policy if exists archivo_empresa_select on storage.objects;
drop policy if exists archivo_empresa_update on storage.objects;
drop policy if exists archivo_empresa_delete on storage.objects;

create policy archivo_empresa_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'archivo-empresa'
    and fn_es_admin_o_lider() is true
    and name ~ '^[0-9a-f-]{36}\.[a-z0-9]{2,5}$'
  );

create policy archivo_empresa_select on storage.objects
  for select to authenticated
  using (bucket_id = 'archivo-empresa' and fn_es_admin_o_lider() is true);

create policy archivo_empresa_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'archivo-empresa' and fn_es_admin_o_lider() is true and fn_archivo_libre(name))
  with check (bucket_id = 'archivo-empresa' and fn_es_admin_o_lider() is true and fn_archivo_libre(name));

create policy archivo_empresa_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'archivo-empresa' and fn_es_admin_o_lider() is true and fn_archivo_libre(name));


-- ── 6 · Subir un papel, o reemplazar uno ─────────────────────────────────────
-- Contrato:
--   p_storage_path  `<uuid>.<ext>` ya subido al bucket. Para corregir solo los
--                   datos, se manda la ruta de la ficha que se reemplaza.
--   p_reemplaza_a   null para un papel nuevo; el id de la ficha vigente que
--                   esta corrige o actualiza.
-- Devuelve el id de la ficha creada. Todo en una transacción: o queda la ficha
-- entera o no queda nada.
create or replace function fn_archivo_subir(
  p_storage_path    text,
  p_nombre_archivo  text,
  p_titulo          text,
  p_entidad         text,
  p_numero          text,
  p_fecha_documento date,
  p_vence_el        date,
  p_sede_id         uuid,
  p_nota            text,
  p_reemplaza_a     uuid default null
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_obj   storage.objects%rowtype;
  v_ant   archivo_empresa%rowtype;
  v_id    uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede subir papeles al archivo de la empresa.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_titulo is null or char_length(btrim(p_titulo)) < 3 then
    raise exception 'Escribe qué papel es (al menos 3 letras).';
  end if;
  if p_entidad is null or char_length(btrim(p_entidad)) < 2 then
    raise exception 'Escribe quién emite el papel.';
  end if;
  if p_fecha_documento is null then
    raise exception 'Falta la fecha del papel.';
  end if;
  if p_fecha_documento > fn_hoy_lima() then
    raise exception 'La fecha del papel no puede ser posterior a hoy.';
  end if;
  if p_vence_el is not null and p_vence_el < p_fecha_documento then
    raise exception 'El papel no puede vencer antes de la fecha en que se emitió.';
  end if;
  if p_nombre_archivo is null or btrim(p_nombre_archivo) = '' then
    raise exception 'Falta el nombre del archivo.';
  end if;
  if p_storage_path is null or p_storage_path !~ '^[0-9a-f-]{36}\.[a-z0-9]{2,5}$' then
    raise exception 'La ruta del archivo no tiene la forma esperada.';
  end if;

  -- El peso y el tipo salen de Storage, no de lo que diga el navegador.
  select * into v_obj from storage.objects o
   where o.bucket_id = 'archivo-empresa' and o.name = p_storage_path;
  if not found then
    raise exception 'El archivo no llegó al almacén. Vuelve a subirlo.';
  end if;

  if p_reemplaza_a is not null then
    select * into v_ant from archivo_empresa a where a.id = p_reemplaza_a for update;
    if not found then
      raise exception 'La ficha que quieres reemplazar no existe.';
    end if;
    if v_ant.retirado_at is not null then
      raise exception 'Esa ficha está retirada: no se reemplaza. Sube el papel como nuevo.';
    end if;
    if exists (select 1 from archivo_empresa a where a.reemplaza_a = p_reemplaza_a) then
      raise exception 'Esa ficha ya fue reemplazada por otra. Recarga la pantalla.';
    end if;
  end if;

  insert into archivo_empresa
    (titulo, entidad, numero, fecha_documento, vence_el, sede_id, nota,
     storage_path, nombre_archivo, mime, bytes, reemplaza_a, subido_por)
  values
    (btrim(p_titulo), btrim(p_entidad), nullif(btrim(p_numero), ''), p_fecha_documento,
     p_vence_el, p_sede_id, nullif(btrim(p_nota), ''),
     p_storage_path, btrim(p_nombre_archivo),
     v_obj.metadata->>'mimetype', (v_obj.metadata->>'size')::bigint,
     p_reemplaza_a, v_quien)
  returning id into v_id;

  return v_id;
end;
$fn$;


-- ── 7 · Retirar un papel ─────────────────────────────────────────────────────
-- Para lo que dejó de aplicar (una sede que cerró) o se subió por error. Solo
-- la ficha vigente: retirar una vieja no significaría nada. El archivo se
-- conserva.
create or replace function fn_archivo_retirar(p_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_f     archivo_empresa%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede retirar papeles del archivo de la empresa.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo (al menos 5 letras): queda anotado junto al papel.';
  end if;

  select * into v_f from archivo_empresa a where a.id = p_id for update;
  if not found then
    raise exception 'Esa ficha no existe.';
  end if;
  if v_f.retirado_at is not null then
    raise exception 'Esa ficha ya está retirada.';
  end if;
  if exists (select 1 from archivo_empresa a where a.reemplaza_a = p_id) then
    raise exception 'Esa ficha ya fue reemplazada: se retira la versión vigente.';
  end if;

  update archivo_empresa
     set retirado_at = now(), retirado_por = v_quien, retirado_motivo = btrim(p_motivo)
   where id = p_id;
end;
$fn$;


-- ── 8 · Lo que ve la pantalla ────────────────────────────────────────────────
-- Todas las fichas, con su estado ya resuelto: la regla de qué es «vigente»
-- vive aquí y en ningún otro sitio.
create or replace function fn_archivo_empresa()
returns table (
  id                  uuid,
  titulo              text,
  entidad             text,
  numero              text,
  fecha_documento     date,
  vence_el            date,
  sede_id             uuid,
  sede_nombre         text,
  nota                text,
  storage_path        text,
  nombre_archivo      text,
  mime                text,
  bytes               bigint,
  reemplaza_a         uuid,
  reemplazada_por     uuid,
  estado              text,
  subido_por_nombre   text,
  subido_at           timestamptz,
  retirado_at         timestamptz,
  retirado_por_nombre text,
  retirado_motivo     text
)
language plpgsql stable security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve el archivo de la empresa.';
  end if;

  return query
  select a.id, a.titulo, a.entidad, a.numero, a.fecha_documento, a.vence_el,
         a.sede_id, s.nombre, a.nota, a.storage_path, a.nombre_archivo, a.mime, a.bytes,
         a.reemplaza_a, r.id,
         case when a.retirado_at is not null then 'retirada'
              when r.id is not null           then 'reemplazada'
              else 'vigente' end,
         btrim(ps.nombres || ' ' || ps.apellidos), a.subido_at,
         a.retirado_at, btrim(pr.nombres || ' ' || pr.apellidos), a.retirado_motivo
    from archivo_empresa a
    left join archivo_empresa r on r.reemplaza_a = a.id
    left join sedes s     on s.id  = a.sede_id
    left join personas ps on ps.id = a.subido_por
    left join personas pr on pr.id = a.retirado_por
   -- `id` como ancla del orden: dos fichas subidas en la misma transacción
   -- empatan en `subido_at` (lección de la 0312/0389).
   order by a.entidad, a.subido_at desc, a.id desc;
end;
$fn$;


-- ── 9 · Quién puede llamar qué ───────────────────────────────────────────────
-- Desde la 0076 ninguna función nace con EXECUTE para nadie: sin estos grants
-- la pantalla queda vacía sin dar error (0204).
grant execute on function
  fn_archivo_subir(text, text, text, text, text, date, date, uuid, text, uuid),
  fn_archivo_retirar(uuid, text),
  fn_archivo_empresa()
to authenticated;
revoke execute on function
  fn_archivo_subir(text, text, text, text, text, date, date, uuid, text, uuid),
  fn_archivo_retirar(uuid, text),
  fn_archivo_empresa()
from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (503, 'el_archivo_de_la_empresa')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'archivo_empresa') as tabla_de_1,
  (select count(*) from pg_proc where proname in (
     'fn_archivo_subir','fn_archivo_retirar','fn_archivo_empresa','fn_archivo_libre',
     'fn_archivo_empresa_solo_retirar')) as funciones_de_5,
  (select count(*) from pg_policies where schemaname = 'storage' and policyname like 'archivo\_empresa\_%') as politicas_storage_de_4,
  (select count(*) from storage.buckets where id = 'archivo-empresa' and public is false) as bucket_privado,
  (select relrowsecurity from pg_class where relname = 'archivo_empresa') as rls_activa,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 503) as registro;
