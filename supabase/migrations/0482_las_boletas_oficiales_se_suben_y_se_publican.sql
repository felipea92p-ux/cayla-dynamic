-- ============================================================================
-- 0482_las_boletas_oficiales_se_suben_y_se_publican.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que Desarrollo Organizacional (DO) pueda subir la BOLETA OFICIAL de cada
--   persona y periodo —la que entrega el contador, en foto o en PDF, de una o de
--   varias hojas—, revisarla y publicarla; y que cada persona vea y guarde solo
--   la suya, y pueda confirmar que la recibió. Quedan escritos, por cada boleta:
--   cuándo se publicó, cuándo la abrió la persona por primera vez y cuándo
--   confirmó su recepción.
--
--   NO es la boleta calculada por el sistema (`/mio/boleta`, `BoletaHoja`), que
--   sigue existiendo y solo muestra el periodo en curso. Esta es la del contador,
--   la que vale una vez pagado el periodo. Los dos documentos no se mezclan: esta
--   migración no toca ni lee `fn_planilla_calcular` ni ninguna función existente.
--
-- QUÉ ASUME
--   · `fn_es_admin_o_lider()` es «DO» (0078). La encargada de sede NO ve boletas:
--     es plata de otras personas, igual que la planilla (`puedeVerPlanilla`).
--   · `fn_persona_actual_id()` identifica a quien llama.
--   · Que el pago es por GRUPO (0323): una persona solo tiene boleta oficial de un
--     periodo cuando `periodo_grupo_pago` dice `pagado` para su `tipo_vinculo`.
--     TODOS los grupos reciben boleta —decisión de Felipe, 2026-09-19—: no se
--     excluye a practicantes, a quien lleva sueldo fijo ni a nadie por su cargo.
--   · Que los archivos los sube el navegador al bucket `boletas` ANTES de llamar
--     a `fn_boleta_guardar_version`. Ver «POR QUÉ EL ARCHIVO VA PRIMERO».
--   · Que Storage guarda el peso y el tipo de cada archivo en
--     `storage.objects.metadata` (`size`, `mimetype`). La función los lee de ahí:
--     no confía en lo que el navegador diga que subió.
--
-- ── LA FORMA: TRES COSAS QUE NO SE PUEDEN CONFUNDIR ──────────────────────────
--
--   ARCHIVO   Un objeto de Storage. Inmutable: nunca se sobrescribe ni se borra
--             una vez que una versión lo usa.
--   VERSIÓN   Una lista ORDENADA de hojas (todas fotos, o todos PDF). Solo se
--             agrega: editar una boleta es crear la versión N+1, que reutiliza las
--             hojas que se conservan y suma las nuevas. Nada se copia.
--   BOLETA    Una por (periodo, persona). Solo lleva su estado; su versión vigente
--             es la de número mayor.
--
--   Tablas:  boletas · boletas_versiones · boletas_partes · boletas_acuses
--
--   Se descartó guardar las hojas como un arreglo `jsonb` dentro de la versión:
--   no admite llaves ni restricciones únicas por hoja, y la política de Storage
--   necesita encontrar la hoja por su ruta con un índice.
--   Se descartó meter estas boletas en `documentos`/Documentación: ahí ya se
--   acumulan las firmas y los pendientes de cada persona; 30 personas × 12 meses
--   son ~360 filas al año que inundarían ese tablero y sus contadores.
--
-- ── EL ACUSE VA POR VERSIÓN, NO POR BOLETA ───────────────────────────────────
--
--   `boletas_acuses` cuelga de la VERSIÓN. Si la persona abre la versión 1 y DO
--   la reemplaza por la 2 antes de que confirme, su «recibí» no puede quedar
--   puesto sobre la 2 sin que la haya visto. Y al revés: si la 2 la avisa de
--   nuevo, el acuse de la 1 se CONSERVA —la constancia de lo que sí recibió no se
--   borra porque después cambiaron el documento—, y la 2 empieza limpia.
--
--   Cuando solo se REORDENARON las hojas y DO decide no avisar (`p_avisar =
--   false`), la versión nueva hereda el acuse de la anterior: el contenido es el
--   mismo. Si cambió el contenido —se agregó o se quitó una hoja— avisar es
--   OBLIGATORIO y `p_avisar = false` se ignora: un contenido nuevo no puede quedar
--   bajo la confirmación de otro. Esa regla vive aquí y no en la pantalla.
--
-- ── ESTADOS QUE NUNCA DEBEN EXISTIR (y qué los hace imposibles) ──────────────
--
--   · dos boletas activas de la misma persona y periodo ..... unique(periodo, persona)
--   · una boleta publicada sin fecha ni quién la publicó ..... check
--   · una boleta anulada sin motivo escrito ................ check (≥ 5 letras)
--   · una versión con fotos y PDF mezclados ................ llave compuesta
--       (version_id, tipo) → versiones(id, tipo) + check de `mime` contra `tipo`
--   · una hoja cuya ruta no es de esa persona y periodo ..... check de forma +
--       la función compara el prefijo contra los parámetros
--   · «recibí» sin haberla abierto .......................... check en acuses
--   · una versión editada o borrada .......................... trigger que rechaza
--       todo `update`/`delete` sobre versiones y hojas, sin excepciones
--   · un acuse que cambia después de puesto ................. trigger: solo
--       null → valor; y solo desde el sistema (`current_user = 'postgres'`)
--   · una persona leyendo la boleta de otra, o un borrador ... la política de
--       Storage exige dueña + publicada + versión vigente
--   · pisar un archivo que una versión ya usa ................ la política de
--       update/delete de Storage exige que no esté referenciado
--
--   Sin policies de escritura y con los permisos revocados a mano (mismo
--   criterio que la 0480): toda escritura pasa por las funciones de abajo.
--
-- ── POR QUÉ EL ARCHIVO VA PRIMERO (Werner Vogels) ────────────────────────────
--
--   El navegador sube los archivos y solo después pide crear la versión. Si
--   Storage cae a mitad, no queda ninguna fila: DO reintenta y ya. Si fuera al
--   revés, una caída dejaría una boleta que la persona ve pero no abre. Un archivo
--   huérfano (subido y nunca usado) es inofensivo y se puede borrar —la política
--   de delete lo permite justamente porque nadie lo referencia—; una fila rota
--   no. La función verifica que cada ruta EXISTA en `storage.objects` antes de
--   aceptarla.
--
-- ── LO QUE SE PUEDE PERDER Y LO QUE NO ───────────────────────────────────────
--
--   Si Storage no responde: la subida falla entera, sin filas. Se degrada así:
--   DO no puede subir, y la persona sigue viendo la LISTA de sus boletas y sus
--   fechas (viven en la base), pero NO puede abrir ni guardar las hojas: los
--   archivos están en Storage y las URL firmadas (60 segundos) las pide el
--   navegador. Su confirmación, si ya la dio, no se pierde.
--   (Corregido el 2026-09-19: este párrafo decía que «la persona sigue viendo lo
--   ya publicado», y sin Storage no se abre ningún archivo.)
--   Y hay una pérdida que ESTE diseño no evita: si Storage pierde un archivo, la
--   base conserva quién lo publicó y cuándo lo confirmó la persona, pero no el
--   documento. El respaldo de la base NO incluye Storage: ver
--   `scripts/respaldar-boletas.sh`.
--   La marca «vista» prueba que se pidieron los archivos, no que se leyeron.
--
-- ── NÚMEROS (Jeff Dean) ──────────────────────────────────────────────────────
--
--   ~30 personas × 12 meses ≈ 360 boletas al año; a 3 años ≈ 1 100 filas. Ninguna
--   consulta necesita índice más allá de la llave única. El almacenamiento es lo
--   único que puede crecer: una foto de celular pesa 1–4 MB, y el navegador la
--   reduce a un JPG de ~500 KB antes de subirla (≈ 180 MB/año). El tope duro es de
--   500 MB por boleta y 50 MB por archivo (el del bucket); son techos, no un
--   presupuesto. No hay tope por CANTIDAD de hojas —decisión de Felipe—; el de
--   1 000 de aquí abajo solo impide que un jsonb absurdo bloquee la base.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists
--     fn_boleta_guardar_version(uuid, uuid, text, jsonb, boolean, text),
--     fn_boletas_publicar(uuid, uuid[]), fn_boleta_anular(uuid, text),
--     fn_boleta_marcar_papel(uuid, uuid), fn_boletas_tablero(uuid),
--     fn_boleta_versiones(uuid), fn_boleta_partes(uuid), fn_mis_boletas(),
--     fn_boleta_confirmar_recibo(uuid), fn_boleta_puede_ver(text),
--     fn_boleta_archivo_libre(text) cascade;
--   drop policy boletas_insert/select/update/delete on storage.objects;
--   drop table boletas_acuses, boletas_partes, boletas_versiones, boletas;
--   delete from storage.objects where bucket_id = 'boletas';   -- vaciar antes
--   delete from storage.buckets where id = 'boletas';
--   Nada de planilla, asistencia ni pago lee estas tablas: revertir solo quita la
--   pantalla de boletas. Ojo: borrarlas destruye las constancias de recepción.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================


-- ── 1 · El bucket ────────────────────────────────────────────────────────────
-- 50 MB por archivo: el mismo techo que los demás buckets de papeles. Las fotos
-- llegan ya reducidas; un PDF del contador pesa cientos de KB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('boletas', 'boletas', false, 52428800,
        array['image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;


-- ── 2 · Las tablas ───────────────────────────────────────────────────────────
create table if not exists boletas (
  id            uuid primary key default gen_random_uuid(),
  periodo_id    uuid not null references periodos_planilla(id),
  persona_id    uuid not null references personas(id),
  -- borrador: subida, la persona no la ve. publicada: la ve. papel: se le entregó
  -- impresa (quien no tiene cuenta). anulada: retirada, con motivo.
  estado        text not null default 'borrador'
                  check (estado in ('borrador', 'publicada', 'papel', 'anulada')),
  -- Para `papel` es la fecha de entrega. Se conserva al anular: es historia.
  publicada_at  timestamptz,
  publicada_por uuid references personas(id),
  anulada_at    timestamptz,
  anulada_por   uuid references personas(id),
  anulada_motivo text,
  creada_at     timestamptz not null default now(),
  creada_por    uuid not null references personas(id),
  unique (periodo_id, persona_id),
  constraint boleta_publicada_tiene_fecha check (
    estado not in ('publicada', 'papel')
    or (publicada_at is not null and publicada_por is not null)
  ),
  constraint boleta_anulada_tiene_motivo check (
    estado <> 'anulada'
    or (anulada_at is not null and anulada_por is not null
        and char_length(btrim(anulada_motivo)) >= 5)
  )
);

comment on table boletas is
  'Boleta oficial (la del contador) por persona y periodo. Solo lleva el estado; su contenido está en boletas_versiones. Escritura solo por las fn_boleta_*.';

create table if not exists boletas_versiones (
  id         uuid primary key default gen_random_uuid(),
  boleta_id  uuid not null references boletas(id),
  n          int  not null check (n >= 1),
  tipo       text not null check (tipo in ('imagen', 'pdf')),
  -- false solo cuando únicamente se reordenaron las hojas y DO decidió no avisar.
  avisar     boolean not null default true,
  nota       text,
  creada_at  timestamptz not null default now(),
  creada_por uuid not null references personas(id),
  unique (boleta_id, n),
  unique (id, tipo)   -- para la llave compuesta de las hojas
);

comment on table boletas_versiones is
  'Lista ordenada de hojas de una boleta. Solo se agrega: editar es crear la versión N+1.';

create table if not exists boletas_partes (
  id           uuid primary key default gen_random_uuid(),
  version_id   uuid not null,
  tipo         text not null,
  orden        int  not null check (orden >= 1),
  -- <periodo>/<persona>/<uuid>.<ext> — ids, nunca DNI ni nombre.
  storage_path text not null check (
    storage_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]{2,5}$'
  ),
  mime         text not null,
  bytes        bigint not null check (bytes > 0),
  foreign key (version_id, tipo) references boletas_versiones (id, tipo),
  unique (version_id, orden),
  unique (version_id, storage_path),
  -- Fotos con fotos, PDF con PDF: una versión no mezcla.
  check ((tipo = 'imagen' and mime like 'image/%') or (tipo = 'pdf' and mime = 'application/pdf'))
);

create index if not exists idx_boletas_partes_ruta on boletas_partes (storage_path);

comment on table boletas_partes is
  'Una hoja (foto o PDF) de una versión. El mismo archivo puede aparecer en varias versiones.';

create table if not exists boletas_acuses (
  version_id  uuid primary key references boletas_versiones(id),
  vista_at    timestamptz,
  recibida_at timestamptz,
  constraint acuse_recibi_exige_haber_abierto check (vista_at is not null or recibida_at is null),
  constraint acuse_en_orden check (recibida_at is null or recibida_at >= vista_at)
);

comment on table boletas_acuses is
  'Por versión: cuándo la persona la abrió por primera vez y cuándo confirmó que la recibió. Solo avanza (null → valor) y solo desde el sistema.';


-- ── 3 · Lo que no se edita ni se borra ───────────────────────────────────────
create or replace function fn_boletas_solo_agregar()
returns trigger language plpgsql as $$
begin
  raise exception 'Las versiones de una boleta y sus hojas no se editan ni se borran: se agrega una versión nueva.';
end;
$$;

drop trigger if exists boletas_versiones_solo_agregar on boletas_versiones;
create trigger boletas_versiones_solo_agregar
  before update or delete on boletas_versiones
  for each row execute function fn_boletas_solo_agregar();

drop trigger if exists boletas_partes_solo_agregar on boletas_partes;
create trigger boletas_partes_solo_agregar
  before update or delete on boletas_partes
  for each row execute function fn_boletas_solo_agregar();

-- Molde de campo sensible (0261, 0295, 0342): el rol de conexión de un cliente
-- por PostgREST es `authenticated`; una función `security definer` de esta
-- migración corre como `postgres`. Comparar `current_user` distingue las dos.
create or replace function fn_boletas_acuses_guardian()
returns trigger language plpgsql as $$
begin
  if current_user <> 'postgres' then
    raise exception 'Una confirmación de recepción solo se escribe desde el sistema.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Una confirmación de recepción no se borra.';
  end if;
  if tg_op = 'UPDATE' then
    if old.vista_at is not null and new.vista_at is distinct from old.vista_at then
      raise exception 'La fecha de la primera apertura no se corre.';
    end if;
    if old.recibida_at is not null and new.recibida_at is distinct from old.recibida_at then
      raise exception 'La fecha de la confirmación no se corre.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists boletas_acuses_guardian on boletas_acuses;
create trigger boletas_acuses_guardian
  before insert or update or delete on boletas_acuses
  for each row execute function fn_boletas_acuses_guardian();


-- ── 4 · Permisos y RLS ───────────────────────────────────────────────────────
-- Lectura directa: solo DO. La persona lee lo suyo por fn_mis_boletas y
-- fn_boleta_partes, que son `security definer`. Se quita todo lo que Supabase
-- concede por defecto (incluye escribir y `truncate`) y se devuelve solo leer.
alter table boletas          enable row level security;
alter table boletas_versiones enable row level security;
alter table boletas_partes   enable row level security;
alter table boletas_acuses   enable row level security;

drop policy if exists boletas_select_do          on boletas;
drop policy if exists boletas_versiones_select_do on boletas_versiones;
drop policy if exists boletas_partes_select_do   on boletas_partes;
drop policy if exists boletas_acuses_select_do   on boletas_acuses;
create policy boletas_select_do          on boletas          for select to authenticated using (fn_es_admin_o_lider() is true);
create policy boletas_versiones_select_do on boletas_versiones for select to authenticated using (fn_es_admin_o_lider() is true);
create policy boletas_partes_select_do   on boletas_partes   for select to authenticated using (fn_es_admin_o_lider() is true);
create policy boletas_acuses_select_do   on boletas_acuses   for select to authenticated using (fn_es_admin_o_lider() is true);

revoke all on boletas, boletas_versiones, boletas_partes, boletas_acuses from anon, authenticated, public;
grant select on boletas, boletas_versiones, boletas_partes, boletas_acuses to authenticated;


-- ── 5 · Quién abre qué archivo (Storage) ─────────────────────────────────────
-- DO abre todo. La persona abre SOLO las hojas de la versión vigente de una
-- boleta suya y publicada: ni un borrador, ni una anulada, ni una versión vieja.
create or replace function fn_boleta_puede_ver(p_path text)
returns boolean
language plpgsql stable security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is true then return true; end if;
  return exists (
    select 1
      from boletas_partes pt
      join boletas_versiones v on v.id = pt.version_id
      join boletas b on b.id = v.boleta_id
     where pt.storage_path = p_path
       and b.persona_id = fn_persona_actual_id()
       and b.estado = 'publicada'
       and v.n = (select max(v2.n) from boletas_versiones v2 where v2.boleta_id = b.id)
  );
end;
$fn$;

-- Un archivo está «libre» si ninguna versión lo usa: solo entonces se puede
-- pisar o borrar (limpiar un archivo huérfano). Es lo que vuelve inmutables los
-- archivos que ya son parte de una boleta.
create or replace function fn_boleta_archivo_libre(p_path text)
returns boolean
language sql stable security definer set search_path = public
as $fn$
  select not exists (select 1 from boletas_partes pt where pt.storage_path = p_path);
$fn$;

grant execute on function fn_boleta_puede_ver(text), fn_boleta_archivo_libre(text) to authenticated;
revoke execute on function fn_boleta_puede_ver(text), fn_boleta_archivo_libre(text) from public, anon;

-- Las CUATRO políticas, no una: Supabase Storage escribe con
-- `INSERT … ON CONFLICT DO UPDATE … RETURNING *` y necesita las tres para subir
-- (0172, 0175, 0197 costaron medio día por faltar una).
drop policy if exists boletas_insert on storage.objects;
drop policy if exists boletas_select on storage.objects;
drop policy if exists boletas_update on storage.objects;
drop policy if exists boletas_delete on storage.objects;

create policy boletas_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'boletas'
    and fn_es_admin_o_lider() is true
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]{2,5}$'
  );

create policy boletas_select on storage.objects
  for select to authenticated
  using (bucket_id = 'boletas' and fn_boleta_puede_ver(name));

create policy boletas_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'boletas' and fn_es_admin_o_lider() is true and fn_boleta_archivo_libre(name))
  with check (bucket_id = 'boletas' and fn_es_admin_o_lider() is true and fn_boleta_archivo_libre(name));

create policy boletas_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'boletas' and fn_es_admin_o_lider() is true and fn_boleta_archivo_libre(name));


-- ── 6 · DO sube o edita una boleta (crea la versión N+1) ─────────────────────
-- Contrato:
--   p_tipo    'imagen' o 'pdf'; todas las hojas son de ese tipo.
--   p_partes  arreglo ORDENADO de {"path": "<periodo>/<persona>/<uuid>.<ext>"}.
--             Las rutas ya deben existir en el bucket. Para conservar una hoja de
--             la versión anterior se vuelve a mandar su misma ruta.
--   p_avisar  solo cuenta cuando la boleta está publicada y únicamente cambió el
--             orden. Con contenido nuevo se avisa siempre.
-- Devuelve el id de la versión creada. Todo ocurre en una transacción: si algo
-- falla no queda ni la boleta ni la versión a medias.
create or replace function fn_boleta_guardar_version(
  p_periodo_id uuid,
  p_persona_id uuid,
  p_tipo       text,
  p_partes     jsonb,
  p_avisar     boolean default true,
  p_nota       text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien   uuid := fn_persona_actual_id();
  v_grupo   text;
  v_boleta  boletas%rowtype;
  v_vig     boletas_versiones%rowtype;
  v_hay_vig boolean;
  v_version uuid;
  v_n       int;
  v_paths   text[];
  v_old     text[];
  v_total   bigint;
  v_cuantas int;
  v_mal     int;
  v_mismo   boolean;
  v_avisa   boolean;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede subir boletas.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_tipo is null or p_tipo not in ('imagen', 'pdf') then
    raise exception 'El tipo de boleta tiene que ser «imagen» o «pdf».';
  end if;
  if p_partes is null or jsonb_typeof(p_partes) <> 'array' or jsonb_array_length(p_partes) = 0 then
    raise exception 'Agrega al menos una foto o un PDF.';
  end if;
  if jsonb_array_length(p_partes) > 1000 then
    raise exception 'Son demasiadas hojas para una sola boleta.';
  end if;

  select p.tipo_vinculo into v_grupo from personas p where p.id = p_persona_id;
  if not found then
    raise exception 'Esa persona no existe.';
  end if;
  -- Sin fila en periodo_grupo_pago = no pagado (0323 midió cero casos de fila ausente).
  if not exists (select 1 from periodo_grupo_pago g
                  where g.periodo_id = p_periodo_id and g.grupo = v_grupo and g.estado = 'pagado') then
    raise exception 'Ese periodo todavía no está pagado para el grupo de esa persona: la boleta oficial se sube cuando cierra.';
  end if;

  -- Una sola fila por (periodo, persona) y con candado: dos DO subiendo la misma
  -- boleta a la vez se ordenan, no se pisan.
  insert into boletas (periodo_id, persona_id, creada_por)
  values (p_periodo_id, p_persona_id, v_quien)
  on conflict (periodo_id, persona_id) do nothing;
  select * into v_boleta from boletas b
   where b.periodo_id = p_periodo_id and b.persona_id = p_persona_id for update;

  if v_boleta.estado = 'papel' then
    raise exception 'Esa boleta está anotada como entregada en papel. Anúlala antes de subir una digital.';
  end if;

  -- Cada hoja: ruta con el prefijo de ESTA persona y periodo, sin repetirse, y
  -- que exista en Storage. El peso y el tipo salen de Storage, no del cliente.
  select array_agg(e.item->>'path' order by e.ord), count(*)
    into v_paths, v_cuantas
    from jsonb_array_elements(p_partes) with ordinality as e(item, ord);

  if exists (select 1 from unnest(v_paths) as r(path)
              where r.path is null
                 or r.path !~ ('^' || p_periodo_id::text || '/' || p_persona_id::text || '/[0-9a-f-]{36}\.[a-z0-9]{2,5}$')) then
    raise exception 'Una de las hojas no corresponde a esta persona y periodo.';
  end if;
  if (select count(distinct r.path) from unnest(v_paths) as r(path)) <> v_cuantas then
    raise exception 'Hay una hoja repetida.';
  end if;

  select coalesce(sum((o.metadata->>'size')::bigint), 0),
         count(*),
         count(*) filter (where not coalesce(
              (p_tipo = 'imagen' and o.metadata->>'mimetype' like 'image/%')
           or (p_tipo = 'pdf'    and o.metadata->>'mimetype' = 'application/pdf'), false))
    into v_total, v_n, v_mal
    from storage.objects o
   where o.bucket_id = 'boletas' and o.name = any(v_paths);

  if v_n <> v_cuantas then
    raise exception 'Una de las hojas no llegó al almacén. Vuelve a subirla.';
  end if;
  if v_mal > 0 then
    raise exception 'Todas las hojas de una boleta tienen que ser del mismo tipo (fotos o PDF).';
  end if;
  if v_total > 524288000 then
    raise exception 'La boleta pasa el tope de 500 MB. Quita alguna hoja.';
  end if;

  -- La versión vigente, si la hay. `n` es único por boleta: el orden es total.
  select * into v_vig from boletas_versiones v
   where v.boleta_id = v_boleta.id order by v.n desc limit 1;
  v_hay_vig := found;
  v_avisa := true;

  if v_hay_vig then
    select array_agg(pt.storage_path order by pt.orden) into v_old
      from boletas_partes pt where pt.version_id = v_vig.id;
    if v_old = v_paths and v_vig.tipo = p_tipo and v_boleta.estado <> 'anulada' then
      raise exception 'No hiciste ningún cambio: agrega, quita o reordena alguna hoja.';
    end if;
    v_mismo := v_vig.tipo = p_tipo
      and (select array_agg(x order by x) from unnest(v_old) as x)
        = (select array_agg(x order by x) from unnest(v_paths) as x);
    if v_boleta.estado = 'publicada' then
      -- Solo se puede NO avisar si el contenido es el mismo (solo se reordenó).
      v_avisa := coalesce(p_avisar, true) or not coalesce(v_mismo, false);
    end if;
  end if;

  v_n := coalesce(v_vig.n, 0) + 1;
  insert into boletas_versiones (boleta_id, n, tipo, avisar, nota, creada_por)
  values (v_boleta.id, v_n, p_tipo, v_avisa, nullif(btrim(p_nota), ''), v_quien)
  returning id into v_version;

  insert into boletas_partes (version_id, tipo, orden, storage_path, mime, bytes)
  select v_version, p_tipo, e.ord::int, e.item->>'path',
         o.metadata->>'mimetype', (o.metadata->>'size')::bigint
    from jsonb_array_elements(p_partes) with ordinality as e(item, ord)
    join storage.objects o on o.bucket_id = 'boletas' and o.name = e.item->>'path';

  -- Sin aviso: la constancia de la versión anterior sigue valiendo para esta.
  if v_hay_vig and v_boleta.estado = 'publicada' and not v_avisa then
    insert into boletas_acuses (version_id, vista_at, recibida_at)
    select v_version, a.vista_at, a.recibida_at
      from boletas_acuses a where a.version_id = v_vig.id;
  end if;

  -- Una anulada que se vuelve a subir arranca otra vez como borrador.
  if v_boleta.estado = 'anulada' then
    update boletas set estado = 'borrador' where id = v_boleta.id;
  end if;

  return v_version;
end;
$fn$;


-- ── 7 · DO publica ───────────────────────────────────────────────────────────
-- Publica los borradores de un periodo (todos, o solo las personas dadas). Solo
-- entran los que tienen al menos una versión y cuyo grupo sigue pagado: un grupo
-- que se reabrió entre la subida y la publicación no publica boletas de un
-- periodo que dejó de estar cerrado. Devuelve cuántas publicó.
create or replace function fn_boletas_publicar(p_periodo_id uuid, p_personas uuid[] default null)
returns int
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_n     int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede publicar boletas.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  update boletas b
     set estado = 'publicada', publicada_at = now(), publicada_por = v_quien
   where b.periodo_id = p_periodo_id
     and b.estado = 'borrador'
     and (p_personas is null or b.persona_id = any(p_personas))
     and exists (select 1 from boletas_versiones v where v.boleta_id = b.id)
     and exists (select 1 from personas pe
                   join periodo_grupo_pago g
                     on g.grupo = pe.tipo_vinculo and g.periodo_id = b.periodo_id and g.estado = 'pagado'
                  where pe.id = b.persona_id);
  get diagnostics v_n = row_count;
  return v_n;
end;
$fn$;


-- ── 8 · DO anula ─────────────────────────────────────────────────────────────
-- El motivo es obligatorio y queda en `correcciones_auditoria`, igual que los
-- demás cambios de campos sensibles. Los archivos se conservan.
create or replace function fn_boleta_anular(p_boleta_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_b     boletas%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede anular boletas.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo (al menos 5 letras): queda anotado junto a la boleta.';
  end if;

  select * into v_b from boletas b where b.id = p_boleta_id for update;
  if not found then
    raise exception 'Esa boleta no existe.';
  end if;
  if v_b.estado = 'anulada' then
    raise exception 'Esa boleta ya está anulada.';
  end if;

  update boletas
     set estado = 'anulada', anulada_at = now(), anulada_por = v_quien,
         anulada_motivo = btrim(p_motivo)
   where id = p_boleta_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (v_b.persona_id, 'boletas.estado', v_b.estado, 'anulada', btrim(p_motivo), v_quien);
end;
$fn$;


-- ── 9 · DO anota una entrega en papel ────────────────────────────────────────
-- Para quien no tiene cuenta y no puede abrir su boleta en el sistema. Deja la
-- constancia de la entrega; no sube ningún archivo.
create or replace function fn_boleta_marcar_papel(p_periodo_id uuid, p_persona_id uuid)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_grupo text;
  v_id    uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede anotar entregas en papel.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  select p.tipo_vinculo into v_grupo from personas p where p.id = p_persona_id;
  if not found then
    raise exception 'Esa persona no existe.';
  end if;
  if not exists (select 1 from periodo_grupo_pago g
                  where g.periodo_id = p_periodo_id and g.grupo = v_grupo and g.estado = 'pagado') then
    raise exception 'Ese periodo todavía no está pagado para el grupo de esa persona.';
  end if;

  insert into boletas (periodo_id, persona_id, estado, publicada_at, publicada_por, creada_por)
  values (p_periodo_id, p_persona_id, 'papel', now(), v_quien, v_quien)
  on conflict (periodo_id, persona_id) do update
     set estado = 'papel', publicada_at = now(), publicada_por = v_quien
   where boletas.estado = 'anulada'
  returning id into v_id;

  if v_id is null then
    raise exception 'Esa persona ya tiene boleta en este periodo.';
  end if;
  return v_id;
end;
$fn$;


-- ── 10 · DO mira el periodo: una fila por persona ────────────────────────────
-- Devuelve a TODAS las personas activas (y a quien, aunque ya no lo esté, tenga
-- boleta en ese periodo). `actualizada` = es una versión avisada posterior a la
-- primera y la persona todavía no la confirmó: se apaga sola al confirmar. `estado` es: falta · borrador · publicada · papel ·
-- anulada. La pantalla deriva «vista» y «confirmada» de las dos fechas.
create or replace function fn_boletas_tablero(p_periodo_id uuid)
returns table (
  persona_id uuid, nombre text, cargo text, sede_codigo text, tipo_vinculo text,
  tiene_cuenta boolean, grupo_pagado boolean,
  boleta_id uuid, estado text,
  version_id uuid, version_n int, tipo text, n_partes int, bytes bigint, actualizada boolean,
  publicada_at timestamptz, vista_at timestamptz, recibida_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve las boletas de todos.';
  end if;

  return query
  select pe.id,
         btrim(pe.nombres || ' ' || pe.apellidos),
         pe.cargo,
         s.codigo,
         pe.tipo_vinculo,
         (pe.auth_user_id is not null),
         exists (select 1 from periodo_grupo_pago g
                  where g.periodo_id = p_periodo_id and g.grupo = pe.tipo_vinculo and g.estado = 'pagado'),
         b.id,
         coalesce(b.estado, 'falta'),
         v.id, v.n, v.tipo,
         coalesce(x.n_partes, 0)::int,
         coalesce(x.bytes, 0)::bigint,
         coalesce(v.n > 1 and v.avisar and a.recibida_at is null, false),
         b.publicada_at, a.vista_at, a.recibida_at
    from personas pe
    join sedes s on s.id = pe.sede_base_id
    left join boletas b on b.periodo_id = p_periodo_id and b.persona_id = pe.id
    left join lateral (
      select vv.id, vv.n, vv.tipo, vv.avisar
        from boletas_versiones vv where vv.boleta_id = b.id
       order by vv.n desc limit 1
    ) v on true
    left join boletas_acuses a on a.version_id = v.id
    left join lateral (
      select count(*) as n_partes, sum(pt.bytes) as bytes
        from boletas_partes pt where pt.version_id = v.id
    ) x on true
   where pe.estado = 'activo' or b.id is not null
   order by pe.nombres, pe.apellidos, pe.id;
end;
$fn$;


-- ── 11 · DO ve el historial de versiones de una boleta ───────────────────────
create or replace function fn_boleta_versiones(p_boleta_id uuid)
returns table (
  version_id uuid, n int, tipo text, n_partes int, bytes bigint, avisar boolean, nota text,
  creada_at timestamptz, creada_por text, vigente boolean,
  vista_at timestamptz, recibida_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve el historial de una boleta.';
  end if;

  return query
  select v.id, v.n, v.tipo,
         coalesce(x.n_partes, 0)::int, coalesce(x.bytes, 0)::bigint,
         v.avisar, v.nota, v.creada_at,
         btrim(cp.nombres || ' ' || cp.apellidos),
         (v.n = (select max(v2.n) from boletas_versiones v2 where v2.boleta_id = v.boleta_id)),
         a.vista_at, a.recibida_at
    from boletas_versiones v
    join personas cp on cp.id = v.creada_por
    left join boletas_acuses a on a.version_id = v.id
    left join lateral (
      select count(*) as n_partes, sum(pt.bytes) as bytes
        from boletas_partes pt where pt.version_id = v.id
    ) x on true
   where v.boleta_id = p_boleta_id
   order by v.n desc;
end;
$fn$;


-- ── 12 · Las rutas de una versión — y la primera apertura ────────────────────
-- Si quien llama es la DUEÑA de una boleta publicada y esta es su versión
-- vigente: devuelve las hojas y deja escrita la primera apertura (una sola vez).
-- Si es DO mirando la boleta de otra persona: devuelve las hojas SIN marcar nada
-- (DO revisando no es la persona recibiéndola). Cualquier otro caso, error.
-- Ir primero por la dueña permite que una persona de DO vea la suya como
-- integrante y sí quede marcada.
create or replace function fn_boleta_partes(p_version_id uuid)
returns table (orden int, storage_path text, mime text, bytes bigint)
language plpgsql security definer set search_path = public
as $fn$
declare
  v_yo       uuid := fn_persona_actual_id();
  v_persona  uuid;
  v_estado   text;
  v_vigente  boolean;
begin
  select b.persona_id, b.estado,
         (v.n = (select max(v2.n) from boletas_versiones v2 where v2.boleta_id = b.id))
    into v_persona, v_estado, v_vigente
    from boletas_versiones v
    join boletas b on b.id = v.boleta_id
   where v.id = p_version_id;
  if not found then
    raise exception 'Esa boleta no existe.';
  end if;

  if v_yo is not null and v_persona = v_yo and v_estado = 'publicada' and v_vigente then
    insert into boletas_acuses (version_id, vista_at) values (p_version_id, now())
    on conflict (version_id) do update
       set vista_at = coalesce(boletas_acuses.vista_at, excluded.vista_at);
  elsif fn_es_admin_o_lider() is not true then
    raise exception 'Esa boleta no está disponible.';
  end if;

  return query
  select pt.orden, pt.storage_path, pt.mime, pt.bytes
    from boletas_partes pt where pt.version_id = p_version_id
   order by pt.orden;
end;
$fn$;


-- ── 13 · La persona confirma que la recibió ──────────────────────────────────
-- Solo la dueña, solo de la versión VIGENTE y publicada, y solo si ya la abrió. Si DO la reemplazó
-- mientras la tenía abierta, se rechaza con un mensaje que dice qué hacer: la
-- confirmación jamás cae sobre una versión que no vio. Idempotente.
create or replace function fn_boleta_confirmar_recibo(p_version_id uuid)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_persona uuid;
  v_estado  text;
  v_vigente boolean;
begin
  if v_yo is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  select b.persona_id, b.estado,
         (v.n = (select max(v2.n) from boletas_versiones v2 where v2.boleta_id = b.id))
    into v_persona, v_estado, v_vigente
    from boletas_versiones v
    join boletas b on b.id = v.boleta_id
   where v.id = p_version_id;
  if not found then
    raise exception 'Esa boleta no existe.';
  end if;
  if v_persona <> v_yo then
    raise exception 'Esa boleta no es tuya.';
  end if;
  if v_estado <> 'publicada' then
    raise exception 'Esa boleta no está disponible.';
  end if;
  if not v_vigente then
    raise exception 'Tu boleta se actualizó: ábrela de nuevo antes de confirmar.';
  end if;

  -- Confirmar que la recibió exige haberla ABIERTO: quien confirma sin haberla
  -- pedido no está confirmando nada. La primera apertura la escribe
  -- `fn_boleta_partes`; sin ella, esto se rechaza con un mensaje que dice qué hacer.
  if not exists (select 1 from boletas_acuses a
                  where a.version_id = p_version_id and a.vista_at is not null) then
    raise exception 'Ábrela con «Ver» antes de confirmar que la recibiste.';
  end if;

  -- Idempotente: si ya estaba confirmada, la fecha de la primera vez no se corre.
  update boletas_acuses
     set recibida_at = coalesce(recibida_at, now())
   where version_id = p_version_id;
end;
$fn$;


-- ── 14 · Lo mío: los periodos pagados de la persona y su boleta ──────────────
-- Una fila por periodo cuyo grupo ya está pagado (o donde ya hay boleta), del más
-- reciente al más viejo. Los borradores y las anuladas NO salen: para la persona
-- ese periodo figura «aún no publicada». Sin cuenta enlazada devuelve vacío.
create or replace function fn_mis_boletas()
returns table (
  periodo_id uuid, fecha_ini date, fecha_fin date,
  boleta_id uuid, estado text,
  version_id uuid, version_n int, tipo text, n_partes int, bytes bigint, actualizada boolean,
  publicada_at timestamptz, vista_at timestamptz, recibida_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_yo    uuid := fn_persona_actual_id();
  v_grupo text;
begin
  if v_yo is null then
    return;
  end if;
  select p.tipo_vinculo into v_grupo from personas p where p.id = v_yo;

  return query
  select pe.id, pe.fecha_ini, pe.fecha_fin,
         b.id, b.estado,
         v.id, v.n, v.tipo,
         coalesce(x.n_partes, 0)::int, coalesce(x.bytes, 0)::bigint,
         coalesce(v.n > 1 and v.avisar and a.recibida_at is null, false),
         b.publicada_at, a.vista_at, a.recibida_at
    from periodos_planilla pe
    left join boletas b
           on b.periodo_id = pe.id and b.persona_id = v_yo and b.estado in ('publicada', 'papel')
    left join lateral (
      select vv.id, vv.n, vv.tipo, vv.avisar
        from boletas_versiones vv where vv.boleta_id = b.id
       order by vv.n desc limit 1
    ) v on true
    left join boletas_acuses a on a.version_id = v.id
    left join lateral (
      select count(*) as n_partes, sum(pt.bytes) as bytes
        from boletas_partes pt where pt.version_id = v.id
    ) x on true
   where b.id is not null
      or exists (select 1 from periodo_grupo_pago g
                  where g.periodo_id = pe.id and g.grupo = v_grupo and g.estado = 'pagado')
   order by pe.fecha_ini desc, pe.id
   limit 36;
end;
$fn$;


-- ── 15 · Permisos de las funciones ───────────────────────────────────────────
-- Ninguna `fn_*` llamable por la API responde a quien no inició sesión (prueba
-- 250): cada una se quita de PUBLIC y de anon y se concede solo a authenticated.
grant execute on function
  fn_boleta_guardar_version(uuid, uuid, text, jsonb, boolean, text),
  fn_boletas_publicar(uuid, uuid[]),
  fn_boleta_anular(uuid, text),
  fn_boleta_marcar_papel(uuid, uuid),
  fn_boletas_tablero(uuid),
  fn_boleta_versiones(uuid),
  fn_boleta_partes(uuid),
  fn_boleta_confirmar_recibo(uuid),
  fn_mis_boletas()
to authenticated;
revoke execute on function
  fn_boleta_guardar_version(uuid, uuid, text, jsonb, boolean, text),
  fn_boletas_publicar(uuid, uuid[]),
  fn_boleta_anular(uuid, text),
  fn_boleta_marcar_papel(uuid, uuid),
  fn_boletas_tablero(uuid),
  fn_boleta_versiones(uuid),
  fn_boleta_partes(uuid),
  fn_boleta_confirmar_recibo(uuid),
  fn_mis_boletas()
from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (482, 'las_boletas_oficiales_se_suben_y_se_publican')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name in ('boletas','boletas_versiones','boletas_partes','boletas_acuses')) as tablas_de_4,
  (select count(*) from pg_proc where proname in (
     'fn_boleta_guardar_version','fn_boletas_publicar','fn_boleta_anular','fn_boleta_marcar_papel',
     'fn_boletas_tablero','fn_boleta_versiones','fn_boleta_partes','fn_boleta_confirmar_recibo',
     'fn_mis_boletas','fn_boleta_puede_ver','fn_boleta_archivo_libre')) as funciones_de_11,
  (select count(*) from pg_policies where schemaname = 'storage' and policyname like 'boletas\_%') as politicas_storage_de_4,
  (select count(*) from storage.buckets where id = 'boletas' and public is false) as bucket_privado,
  (select count(*) from pg_class where relname in ('boletas','boletas_versiones','boletas_partes','boletas_acuses') and relrowsecurity) as rls_de_4,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 482) as registro;
