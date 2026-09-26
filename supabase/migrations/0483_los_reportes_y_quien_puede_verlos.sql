-- ============================================================================
-- 0483_los_reportes_y_quien_puede_verlos.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que exista dónde guardar un REPORTE —sobre una compañera, la empresa, una
--   clienta o una idea de mejora— y que la base, no la pantalla, decida quién
--   puede leerlo. Es el paso 1 de la Fase 1 de `docs/plan-reportes.md`
--   (sección 16): tablas, la marca de Gerencia General, los órganos del
--   Título X, la regla de acceso, la RLS y el bucket privado.
--
--   NO trae todavía cómo se ESCRIBE un reporte: `fn_reporte_crear`, el hilo,
--   los plazos y el cierre son el paso 2. Hasta entonces las tablas están
--   vacías y ningún cliente puede escribir en ellas: no tienen permisos de
--   escritura, solo de lectura filtrada por RLS.
--
-- QUÉ ASUME
--   · La cadena del Reglamento que Felipe fijó el 2026-09-26 (plan, decisiones
--     11 a 19): colaboradora → líder de equipo → DO → Gerencia General.
--   · Medido en producción ese mismo día: 5 admins activos y 1 `lider_do`. Por
--     eso la Gerencia General NO es el rol admin (lo que dice `fn_cargo_de_rol`,
--     0074): es una marca propia, `configuracion.gerencia_general`, y hoy es
--     una sola persona, Felipe. Los otros admins no ven reportes.
--   · «Líder de equipo de la sede» se resuelve como en la 0435:
--     `rol = 'supervisor_sede' and sede_base_id = X`. No hay jefe directo.
--   · `fn_persona_actual_id()` (0005) identifica a quien llama, y
--     `fn_hoy_lima()` (0091) da la fecha de hoy en Lima.
--
-- ── LA REGLA, EN UNA TABLA (plan, sección 7) ─────────────────────────────────
--
--   Vive UNA sola vez, en `fn_reporte_acceso`. La RLS, el bucket y
--   `fn_reporte_quien_lo_leera` la llaman; nadie la vuelve a escribir.
--
--   Reclamo (43-B) y convivencia (43-A):
--     · la líder de la sede del hecho: solo si nadie de nivel 1 o más está
--       involucrado (el reporte es sobre colaboradoras, o sobre nadie);
--     · DO (`lider_do`): todo;
--     · la Gerencia General: todo;
--     · los demás admins: nada.
--   Título X (arts. 47–51):
--     · DO: todo;
--     · la Gerencia General: solo si hay una `lider_do` involucrada (48.2);
--     · quien investiga en la sede (Delegada, suplente o designada): la primera
--       que no esté mencionada, en ese orden (48.3);
--     · la líder: NUNCA el contenido. Solo ve la instrucción de una medida de
--       protección que DO le encargue (`reporte_medidas`).
--   Y siempre: quien está MENCIONADA (involucrada o testigo) no lo ve, sea cual
--   sea su rol, y quien lo ESCRIBIÓ no lo gestiona, pero sí lo ve.
--
--   La regla de la mención resuelve sola los dos casos del 48.2 y el 48.2-bis:
--   un reporte sobre DO no lo ve DO, porque está mencionada, y uno sobre la
--   Gerencia General no lo ve la Gerencia General, por lo mismo. No hace falta
--   una fila por cada escalón.
--
-- ── POR QUÉ UNA FOTO Y NO UNA CONSULTA EN VIVO ───────────────────────────────
--
--   `reporte_personas` guarda el rol y el nivel de cada persona AL MOMENTO de
--   mencionarla, y `reportes.nivel` guarda el máximo de las involucradas. La
--   regla lee la foto, no `personas.rol`. Si no fuera así, ascender a una
--   colaboradora a líder, o quitarle a alguien la marca de Gerencia General,
--   cambiaría quién lee reportes que ya existen: quien se quita la marca
--   ganaría acceso a lo que se dijo de ella. Mismo criterio que la sede de la
--   0435. `nivel` nunca baja: lo impide un trigger.
--
--   Lo que SÍ se lee en vivo es quién es hoy la líder de la sede, la persona de
--   DO o la Delegada: si la líder de Trujillo cambia, los reportes de Trujillo
--   pasan a la nueva. Esa es la mitad que tiene que seguir a la organización.
--
-- ── LA MARCA DE GERENCIA GENERAL ─────────────────────────────────────────────
--
--   Va en `configuracion` y no en `personas`, por la misma razón que el
--   firmante de la 0147: es UNA fila que cambia cada varios años, y la pregunta
--   es «quién es», no «¿esta persona lo es?».
--
--   `configuracion` la pueden escribir admin y líder por RLS (0007). Para esta
--   clave eso sería una puerta abierta: cualquiera de los cinco admins podría
--   marcarse a sí mismo. Un trigger la cierra: la fila `gerencia_general` solo
--   la escribe `postgres`, es decir, el SQL Editor. Es el molde de campo
--   sensible (0261, 0295/0296, 0342, 0482), aplicado a una clave en vez de a
--   una columna. Se cambia así:
--
--     update configuracion
--        set valor = jsonb_build_object('persona_id', '<uuid de la persona>')
--      where clave = 'gerencia_general';
--
--   Se siembra UNA vez desde `firmante_empresa` (0147), que ya apunta a Felipe
--   con el cargo «Gerencia General». Si esa fila no existe, o no apunta a un
--   admin activo, no se siembra nada y la comprobación del final lo dice:
--   entonces NINGÚN admin ve reportes, que es el lado seguro. Un reporte sin
--   Gerencia General lo sigue viendo DO.
--
-- ── LO QUE LA RLS NO PUEDE PROMETER ──────────────────────────────────────────
--
--   Protege contra el panel, no contra quien tiene el SQL Editor, que puede
--   leer cualquier tabla. Hoy ese es Felipe, y por eso un reporte sobre la
--   Gerencia General no tiene reserva técnica completa (plan, sección 7). La
--   pantalla del paso 3 lo dice y ofrece el sobre cerrado y los canales
--   externos.
--
-- ── ESTADOS QUE NUNCA DEBEN EXISTIR (y qué los hace imposibles) ──────────────
--
--   · Que un cliente escriba un reporte, un mensaje o un evento con un PATCH:
--     sin permisos de escritura (`revoke all … grant select`).
--   · Que se borre un reporte o se reescriba su relato: trigger.
--   · Que baje el nivel de un reporte: trigger.
--   · Que se edite o borre un mensaje, un evento, una mención o un adjunto
--     registrado: son solo de agregar, por trigger.
--   · Que un admin se marque como Gerencia General: trigger en `configuracion`.
--   · Que la marca apunte a alguien inexistente, cesado o sin rol admin:
--     trigger.
--   · Que se pise o se borre la evidencia ya registrada en el bucket: las
--     políticas de update y delete exigen que el archivo esté «libre».
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_reporte_quien_lo_leera(text, uuid, uuid[], uuid[]),
--     fn_reporte_puede_ver_archivo(text), fn_reporte_archivo_libre(text),
--     fn_reporte_puede_ver(uuid), fn_reporte_puede_gestionar(uuid),
--     fn_reporte_motivo(uuid), fn_reporte_motivo_de(uuid, uuid),
--     fn_reporte_es_autor(uuid), fn_reporte_acceso(uuid, uuid, text, uuid, smallint, boolean, uuid[]),
--     fn_reporte_nivel_persona(uuid), fn_gerencia_general_id() cascade;
--   drop policy reportes_insert/select/update/delete on storage.objects;
--   drop table reporte_medidas, reporte_adjuntos, reporte_eventos,
--     reporte_mensajes, reporte_personas, reportes, organos_titulo_x;
--   drop sequence reportes_codigo_seq;
--   drop trigger trg_guarda_gerencia_general on configuracion;
--   drop function fn_guarda_gerencia_general();
--   delete from configuracion where clave = 'gerencia_general';
--   delete from storage.objects where bucket_id = 'reportes';   -- vaciar antes
--   delete from storage.buckets where id = 'reportes';
--   Nada de asistencia, planilla ni disciplina lee estas tablas. Ojo: una vez
--   que haya reportes, borrarlas destruye el registro que exige el 43-B.4.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última. La columna `gerencia_general` tiene que decir el
--   nombre de Felipe; si dice «SIN MARCA», hay que ponerla a mano (ver arriba).
-- ============================================================================


-- ── 1 · La marca de Gerencia General ────────────────────────────────────────
-- SIN `security definer`, a propósito: así `current_user` es quien ejecuta la
-- escritura —`authenticated` por PostgREST, `postgres` en el SQL Editor— y no
-- el dueño de la función. Es el mismo detalle que hace funcionar a
-- `fn_bloquear_sede_directa` (0342).
create or replace function fn_guarda_gerencia_general()
returns trigger
language plpgsql
set search_path = public
as $fn$
declare
  v_persona uuid;
  v_estado  text;
  v_rol     text;
begin
  if tg_op = 'DELETE' then
    if old.clave = 'gerencia_general' and current_user <> 'postgres' then
      raise exception 'La marca de Gerencia General solo se cambia desde el SQL Editor.';
    end if;
    return old;
  end if;

  if new.clave <> 'gerencia_general'
     and (tg_op = 'INSERT' or old.clave <> 'gerencia_general') then
    return new;
  end if;

  if current_user <> 'postgres' then
    raise exception 'La marca de Gerencia General solo se cambia desde el SQL Editor.';
  end if;

  if new.clave <> 'gerencia_general' then
    raise exception 'La fila gerencia_general no se renombra.';
  end if;

  begin
    v_persona := (new.valor ->> 'persona_id')::uuid;
  exception when others then
    raise exception 'gerencia_general: `persona_id` tiene que ser un identificador de persona válido.';
  end;

  if v_persona is null then
    raise exception 'gerencia_general: falta `persona_id`.';
  end if;

  select p.estado::text, p.rol::text into v_estado, v_rol
    from personas p where p.id = v_persona;

  if v_estado is null then
    raise exception 'gerencia_general: no existe ninguna persona con ese identificador.';
  end if;
  if v_estado <> 'activo' then
    raise exception 'gerencia_general: esa persona está inactiva.';
  end if;
  if v_rol <> 'admin' then
    raise exception 'gerencia_general: la Gerencia General tiene que tener rol admin (tiene %).', v_rol;
  end if;

  return new;
end;
$fn$;

drop trigger if exists trg_guarda_gerencia_general on configuracion;
create trigger trg_guarda_gerencia_general
  before insert or update or delete on configuracion
  for each row execute function fn_guarda_gerencia_general();

-- Siembra desde el firmante de la 0147, solo si apunta a un admin activo. El
-- filtro va en el SELECT y no en el trigger a propósito: si no se cumple, no
-- se inserta nada y la migración sigue; el trigger abortaría la migración
-- entera por un dato que se arregla con un UPDATE.
insert into configuracion (clave, valor, descripcion)
select
  'gerencia_general',
  jsonb_build_object('persona_id', p.id),
  'Quién es la Gerencia General para el Reglamento: la persona que el 48.2-bis aparta y que recibe los reportes sobre DO. No es el rol admin: hay varios admins y una sola Gerencia General. Solo se cambia desde el SQL Editor. Ver migración 0483.'
from configuracion c
join personas p on p.id = (c.valor ->> 'persona_id')::uuid
where c.clave = 'firmante_empresa'
  and c.valor ->> 'cargo' = 'Gerencia General'
  and p.estado = 'activo'
  and p.rol = 'admin'
on conflict (clave) do nothing;

create or replace function fn_gerencia_general_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $fn$
  -- Solo si sigue activa y con rol admin: una marca que apunta a alguien que
  -- ya no está no le da a nadie la vista de la Gerencia General.
  select p.id
    from configuracion c
    join personas p on p.id = (c.valor ->> 'persona_id')::uuid
   where c.clave = 'gerencia_general'
     and p.estado = 'activo'
     and p.rol = 'admin';
$fn$;


-- ── 2 · Quién investiga el Título X en cada sede ────────────────────────────
-- Su verdad está en un acta (48.3, 48.6), no en el código. La identidad de la
-- Delegada se publica en cada sede, así que leerla no es reservado.
create table if not exists organos_titulo_x (
  id          uuid primary key default gen_random_uuid(),
  sede_id     uuid not null references sedes(id),
  persona_id  uuid not null references personas(id),
  -- delegada: elegida por las trabajadoras (48.3) · suplente: la elegida en la
  -- misma elección · designada: la que nombra la Gerencia General mientras no
  -- haya Delegada o el cargo esté vacante.
  papel       text not null check (papel in ('delegada', 'suplente', 'designada')),
  desde       date not null,
  hasta       date,
  acta        text,
  creado_at   timestamptz not null default now(),
  constraint chk_organo_fechas check (hasta is null or hasta >= desde)
);

create index if not exists idx_organos_titulo_x_sede on organos_titulo_x(sede_id);


-- ── 3 · Los reportes ────────────────────────────────────────────────────────
-- Un contador único para todos los años: el código es para nombrar un caso sin
-- nombrar a nadie («el R-2026-0007»), no para contar cuántos hubo por año.
create sequence if not exists reportes_codigo_seq;

create table if not exists reportes (
  id                  uuid primary key default gen_random_uuid(),
  codigo              text not null unique
                        default 'R-' || extract(year from fn_hoy_lima())::int
                                || '-' || lpad(nextval('reportes_codigo_seq')::text, 4, '0'),
  -- Confidencial: solo lo ven quienes gestionan (plan, decisión 2).
  autor_id            uuid not null references personas(id),
  -- La sede DEL HECHO, no la de quien escribe: decide qué líder lo ve.
  sede_id             uuid not null references sedes(id),
  tipo                text not null check (tipo in ('persona', 'empresa', 'clienta', 'idea')),
  -- reclamo: 43-B · convivencia: 43-A · titulo_x: arts. 47–51.
  via                 text not null check (via in ('reclamo', 'convivencia', 'titulo_x')),
  urgente             boolean not null default false,
  -- El máximo nivel entre las INVOLUCRADAS, según su foto en reporte_personas:
  -- 0 colaboradora · 1 líder · 2 DO u otro admin · 3 Gerencia General.
  -- Lo mantiene el trigger de reporte_personas; nunca baja.
  nivel               smallint not null default 0 check (nivel between 0 and 3),
  fecha_hecho         date not null,
  relato              text not null check (length(trim(relato)) > 0),
  espera              text check (espera in ('que_se_sepa', 'conversar', 'que_cambie', 'que_se_actue')),
  primera_vez         boolean,
  ya_conversado       text,
  -- Solo si es sobre una clienta. Nunca datos personales de ella.
  ticket              text,
  estado              text not null default 'recibido'
                        check (estado in ('recibido', 'en_revision', 'cerrado')),
  -- Quién lleva el caso ahora. Lo fija fn_reporte_crear y lo sube
  -- fn_reporte_escalar (paso 2). NO decide quién puede leerlo: eso es la regla.
  gestiona            text check (gestiona in ('lider', 'do', 'gerencia')),
  creado_at           timestamptz not null default now(),
  -- Los plazos NO van aquí: el Título X tiene nueve, encadenados (el informe
  -- abre el traslado y la decisión). Viven en `reporte_plazos` (0484).
  cerrado_at          timestamptz,
  cierre_texto        text,
  cierre_resultado    text check (cierre_resultado in
                        ('resuelto', 'confirmado', 'no_confirmado', 'derivado_disciplinario', 'sin_accion')),
  -- El puente con disciplina: un enlace, nunca una sanción (plan, sección 11).
  expediente_id       uuid references expediente_disciplinario(id),
  constraint chk_reporte_cierre_completo check (
    (estado = 'cerrado') = (cerrado_at is not null)
    and (estado <> 'cerrado' or (cierre_resultado is not null and length(trim(coalesce(cierre_texto, ''))) > 0))
  ),
  constraint chk_reporte_ticket_solo_clienta check (ticket is null or tipo = 'clienta')
);

create index if not exists idx_reportes_sede   on reportes(sede_id, creado_at desc);
create index if not exists idx_reportes_autor  on reportes(autor_id, creado_at desc);

-- A quién menciona el reporte. La FOTO de su rol y su nivel se toma al
-- insertar (ver «POR QUÉ UNA FOTO»).
create table if not exists reporte_personas (
  reporte_id  uuid not null references reportes(id),
  persona_id  uuid not null references personas(id),
  papel       text not null check (papel in ('involucrada', 'testigo')),
  rol         rol_usuario,
  nivel       smallint not null default 0 check (nivel between 0 and 3),
  creado_at   timestamptz not null default now(),
  primary key (reporte_id, persona_id)
);

create index if not exists idx_reporte_personas_persona on reporte_personas(persona_id);

-- El hilo. `interno` = nota que quien reportó no ve.
create table if not exists reporte_mensajes (
  id          uuid primary key default gen_random_uuid(),
  reporte_id  uuid not null references reportes(id),
  autor_id    uuid not null references personas(id),
  texto       text not null check (length(trim(texto)) > 0),
  interno     boolean not null default false,
  creado_at   timestamptz not null default now()
);

create index if not exists idx_reporte_mensajes on reporte_mensajes(reporte_id, creado_at);

-- La línea de tiempo y el rastro del 44.13, incluida cada apertura de la ficha.
-- No va a `correcciones_auditoria`: esa exige `campo_modificado` y no tiene
-- dónde decir «quién leyó».
create table if not exists reporte_eventos (
  id          uuid primary key default gen_random_uuid(),
  reporte_id  uuid not null references reportes(id),
  tipo        text not null check (tipo in
                ('creado', 'acuse', 'estado', 'reclasificado', 'escalado', 'accion',
                 'medida', 'plazo', 'derivado_expediente', 'cerrado', 'lectura')),
  por         uuid references personas(id),
  at          timestamptz not null default now(),
  detalle     jsonb not null default '{}'::jsonb
);

create index if not exists idx_reporte_eventos on reporte_eventos(reporte_id, at);

-- Los archivos, ya registrados. Un archivo del bucket que no está aquí está
-- «libre»: a medio subir, o huérfano. Uno registrado ya es evidencia y no se
-- pisa ni se borra (mismo molde que `boletas_partes`, 0482).
create table if not exists reporte_adjuntos (
  id            uuid primary key default gen_random_uuid(),
  reporte_id    uuid not null references reportes(id),
  storage_path  text not null unique,
  subido_por    uuid not null references personas(id),
  interno       boolean not null default false,
  mimetype      text,
  bytes         bigint,
  creado_at     timestamptz not null default now()
);

create index if not exists idx_reporte_adjuntos on reporte_adjuntos(reporte_id);

-- Lo ÚNICO que ve la líder de un caso del Título X: qué hacer, no por qué
-- (plan, decisión 16). La instrucción no puede llevar los hechos; eso lo
-- cuida quien la escribe en DO, y la pantalla del paso 4 se lo recuerda.
create table if not exists reporte_medidas (
  id               uuid primary key default gen_random_uuid(),
  reporte_id       uuid not null references reportes(id),
  para_persona_id  uuid not null references personas(id),
  instruccion      text not null check (length(trim(instruccion)) > 0),
  vigente_hasta    date,
  cumplida_at      timestamptz,
  creada_por       uuid not null references personas(id),
  creado_at        timestamptz not null default now()
);

create index if not exists idx_reporte_medidas_para on reporte_medidas(para_persona_id);


-- ── 4 · Los niveles y la foto ───────────────────────────────────────────────
-- 0 colaboradora · 1 líder · 2 DO u otro admin · 3 Gerencia General.
-- Una persona inactiva cuenta como 0: ya no tiene acceso a nada.
create or replace function fn_reporte_nivel_persona(p_persona uuid)
returns smallint
language sql
stable
security definer
set search_path = public
as $fn$
  select case
    when p.id = fn_gerencia_general_id()     then 3
    when p.estado <> 'activo'               then 0
    when p.rol in ('lider_do', 'admin')     then 2
    when p.rol = 'supervisor_sede'          then 1
    else 0
  end::smallint
  from personas p
  where p.id = p_persona;
$fn$;

create or replace function fn_reporte_personas_foto()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  select p.rol into new.rol from personas p where p.id = new.persona_id;
  new.nivel := coalesce(fn_reporte_nivel_persona(new.persona_id), 0);
  return new;
end;
$fn$;

drop trigger if exists trg_reporte_personas_foto on reporte_personas;
create trigger trg_reporte_personas_foto
  before insert on reporte_personas
  for each row execute function fn_reporte_personas_foto();

create or replace function fn_reporte_personas_sube_nivel()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if new.papel = 'involucrada' then
    update reportes set nivel = greatest(nivel, new.nivel)
     where id = new.reporte_id and nivel < new.nivel;
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_reporte_personas_sube_nivel on reporte_personas;
create trigger trg_reporte_personas_sube_nivel
  after insert on reporte_personas
  for each row execute function fn_reporte_personas_sube_nivel();


-- ── 5 · Lo que no se edita ni se borra ──────────────────────────────────────
create or replace function fn_reportes_guardian()
returns trigger
language plpgsql
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'Un reporte no se borra: es el registro que exige el 43-B.4.';
  end if;
  if new.autor_id    is distinct from old.autor_id
     or new.codigo    is distinct from old.codigo
     or new.creado_at is distinct from old.creado_at
     or new.relato    is distinct from old.relato
     or new.fecha_hecho is distinct from old.fecha_hecho then
    raise exception 'Lo que se reportó no se reescribe: se agrega un mensaje al hilo.';
  end if;
  if new.nivel < old.nivel then
    raise exception 'El nivel de un reporte no baja: bajarlo abriría el caso a quien no debía verlo.';
  end if;
  if old.estado = 'cerrado' and new.estado <> 'cerrado' then
    raise exception 'Un reporte cerrado no se reabre.';
  end if;
  if old.expediente_id is not null and new.expediente_id is distinct from old.expediente_id then
    raise exception 'El enlace a un expediente disciplinario no se cambia.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_reportes_guardian on reportes;
create trigger trg_reportes_guardian
  before update or delete on reportes
  for each row execute function fn_reportes_guardian();

create or replace function fn_reportes_solo_agregar()
returns trigger
language plpgsql
as $fn$
begin
  raise exception 'En un reporte, % solo se agrega: no se edita ni se borra.', tg_table_name;
end;
$fn$;

drop trigger if exists trg_reporte_personas_solo_agregar on reporte_personas;
create trigger trg_reporte_personas_solo_agregar
  before update or delete on reporte_personas
  for each row execute function fn_reportes_solo_agregar();

drop trigger if exists trg_reporte_mensajes_solo_agregar on reporte_mensajes;
create trigger trg_reporte_mensajes_solo_agregar
  before update or delete on reporte_mensajes
  for each row execute function fn_reportes_solo_agregar();

drop trigger if exists trg_reporte_eventos_solo_agregar on reporte_eventos;
create trigger trg_reporte_eventos_solo_agregar
  before update or delete on reporte_eventos
  for each row execute function fn_reportes_solo_agregar();

drop trigger if exists trg_reporte_adjuntos_solo_agregar on reporte_adjuntos;
create trigger trg_reporte_adjuntos_solo_agregar
  before update or delete on reporte_adjuntos
  for each row execute function fn_reportes_solo_agregar();


-- ── 6 · LA REGLA ────────────────────────────────────────────────────────────
-- Devuelve POR QUÉ una persona gestiona un reporte ('gerencia', 'do', 'lider',
-- 'investigadora') o null si no lo gestiona. Que devuelva el motivo y no un
-- booleano es lo que permite que `fn_reporte_quien_lo_leera` diga los cargos
-- sin una segunda copia de la regla.
--
-- Recibe los datos del reporte y no su id para servir también ANTES de que el
-- reporte exista (la línea «quién lo va a leer» del formulario). No se expone
-- a los clientes: la llaman las funciones de abajo.
create or replace function fn_reporte_acceso(
  p_viewer        uuid,
  p_autor         uuid,
  p_via           text,
  p_sede          uuid,
  p_nivel         smallint,
  p_contra_do     boolean,
  p_mencionadas   uuid[]
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_rol          text;
  v_sede_base    uuid;
  v_investigador uuid;
begin
  if p_viewer is null then
    return null;
  end if;

  -- Nadie gestiona lo que escribió ni lo que lo menciona.
  if p_viewer = p_autor or p_viewer = any(coalesce(p_mencionadas, '{}'::uuid[])) then
    return null;
  end if;

  select p.rol::text, p.sede_base_id into v_rol, v_sede_base
    from personas p
   where p.id = p_viewer and p.estado = 'activo';

  if v_rol is null then
    return null;
  end if;

  if p_via = 'titulo_x' then
    if v_rol = 'lider_do' then
      return 'do';
    end if;
    -- 48.2: contra la titular de DO, la Gerencia General.
    if p_contra_do is true and p_viewer is not distinct from fn_gerencia_general_id() then
      return 'gerencia';
    end if;
    -- 48.3: una sola investigadora por caso, la primera no mencionada.
    select o.persona_id into v_investigador
      from organos_titulo_x o
     where o.sede_id = p_sede
       and o.desde <= fn_hoy_lima()
       and (o.hasta is null or o.hasta >= fn_hoy_lima())
       and o.persona_id <> all(coalesce(p_mencionadas, '{}'::uuid[]))
       and o.persona_id <> p_autor
     order by case o.papel when 'delegada' then 1 when 'suplente' then 2 else 3 end,
              o.desde desc, o.id
     limit 1;
    if v_investigador is not distinct from p_viewer then
      return 'investigadora';
    end if;
    return null;
  end if;

  -- Reclamo y convivencia.
  if p_viewer is not distinct from fn_gerencia_general_id() then
    return 'gerencia';
  end if;
  if v_rol = 'lider_do' then
    return 'do';
  end if;
  if v_rol = 'supervisor_sede' and p_nivel = 0 and v_sede_base = p_sede then
    return 'lider';
  end if;
  return null;
end;
$fn$;

-- La regla aplicada a un reporte que ya existe, para una persona cualquiera.
-- Interna: la usan las funciones que necesitan saber si HAY alguien que pueda
-- recibir un caso (paso 2), sin exponer a quién.
create or replace function fn_reporte_motivo_de(p_reporte uuid, p_viewer uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_r            record;
  v_mencionadas  uuid[];
  v_contra_do    boolean;
begin
  select r.autor_id, r.via, r.sede_id, r.nivel into v_r
    from reportes r where r.id = p_reporte;
  if not found then
    return null;
  end if;

  select coalesce(array_agg(rp.persona_id), '{}'::uuid[]),
         coalesce(bool_or(rp.papel = 'involucrada' and rp.rol = 'lider_do'), false)
    into v_mencionadas, v_contra_do
    from reporte_personas rp
   where rp.reporte_id = p_reporte;

  return fn_reporte_acceso(p_viewer, v_r.autor_id, v_r.via, v_r.sede_id,
                           v_r.nivel, v_contra_do, v_mencionadas);
end;
$fn$;

-- Por qué quien llama gestiona este reporte: 'gerencia', 'do', 'lider',
-- 'investigadora', o null. Las funciones de escritura deciden con esto qué
-- puede hacer cada una (la líder no cierra un caso de convivencia, la
-- investigadora no decide).
create or replace function fn_reporte_motivo(p_reporte uuid)
returns text
language sql
stable
security definer
set search_path = public
as $fn$
  select fn_reporte_motivo_de(p_reporte, fn_persona_actual_id());
$fn$;

create or replace function fn_reporte_puede_gestionar(p_reporte uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select fn_reporte_motivo(p_reporte) is not null;
$fn$;

create or replace function fn_reporte_es_autor(p_reporte uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    (select r.autor_id = fn_persona_actual_id() from reportes r where r.id = p_reporte),
    false);
$fn$;

create or replace function fn_reporte_puede_ver(p_reporte uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select fn_reporte_es_autor(p_reporte) or fn_reporte_puede_gestionar(p_reporte);
$fn$;

-- Lo que el formulario muestra antes de enviar: CARGOS, nunca nombres. Corre
-- la misma regla sobre cada persona que podría gestionarlo.
create or replace function fn_reporte_quien_lo_leera(
  p_via           text,
  p_sede          uuid,
  p_involucradas  uuid[],
  p_testigos      uuid[]
)
returns table (cargo text)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_yo          uuid := fn_persona_actual_id();
  v_mencionadas uuid[] := coalesce(p_involucradas, '{}'::uuid[]) || coalesce(p_testigos, '{}'::uuid[]);
  v_nivel       smallint;
  v_contra_do   boolean;
begin
  if v_yo is null then
    raise exception 'Tu usuario no está enlazado a una ficha.';
  end if;
  if p_via not in ('reclamo', 'convivencia', 'titulo_x') then
    raise exception 'Vía de reporte desconocida.';
  end if;

  select coalesce(max(fn_reporte_nivel_persona(x)), 0)::smallint,
         coalesce(bool_or(p.rol = 'lider_do'), false)
    into v_nivel, v_contra_do
    from unnest(coalesce(p_involucradas, '{}'::uuid[])) x
    left join personas p on p.id = x;

  return query
  select distinct case a.motivo
           when 'gerencia'      then 'Gerencia General'
           when 'do'            then 'Desarrollo Organizacional'
           when 'lider'         then 'La líder de equipo de la sede'
           when 'investigadora' then 'Quien investiga el hostigamiento sexual en la sede'
         end
    from (
      select fn_reporte_acceso(c.id, v_yo, p_via, p_sede, v_nivel, v_contra_do, v_mencionadas) as motivo
        from (
          select p.id from personas p
           where p.estado = 'activo' and p.rol in ('supervisor_sede', 'lider_do', 'admin')
          union
          select o.persona_id from organos_titulo_x o where o.sede_id = p_sede
        ) c
    ) a
   where a.motivo is not null;
end;
$fn$;


-- ── 7 · Permisos y RLS ──────────────────────────────────────────────────────
-- Lectura directa, filtrada por la regla. Ninguna escritura: todo lo que se
-- escriba entrará por las funciones del paso 2. Se quita todo lo que Supabase
-- concede por defecto (incluye escribir y `truncate`) y se devuelve solo leer.
alter table reportes          enable row level security;
alter table reporte_personas  enable row level security;
alter table reporte_mensajes  enable row level security;
alter table reporte_eventos   enable row level security;
alter table reporte_adjuntos  enable row level security;
alter table reporte_medidas   enable row level security;
alter table organos_titulo_x  enable row level security;

drop policy if exists reportes_select          on reportes;
drop policy if exists reporte_personas_select  on reporte_personas;
drop policy if exists reporte_mensajes_select  on reporte_mensajes;
drop policy if exists reporte_eventos_select   on reporte_eventos;
drop policy if exists reporte_adjuntos_select  on reporte_adjuntos;
drop policy if exists reporte_medidas_select   on reporte_medidas;
drop policy if exists organos_titulo_x_select  on organos_titulo_x;

create policy reportes_select on reportes
  for select to authenticated
  using (fn_reporte_puede_ver(id));

-- Quien reportó ve a quiénes nombró ella misma; nada más.
create policy reporte_personas_select on reporte_personas
  for select to authenticated
  using (fn_reporte_puede_ver(reporte_id));

-- Las notas internas, solo quien gestiona.
create policy reporte_mensajes_select on reporte_mensajes
  for select to authenticated
  using (fn_reporte_puede_gestionar(reporte_id)
         or (not interno and fn_reporte_es_autor(reporte_id)));

-- La línea de tiempo (reclasificaciones, lecturas) no es para quien reportó.
create policy reporte_eventos_select on reporte_eventos
  for select to authenticated
  using (fn_reporte_puede_gestionar(reporte_id));

create policy reporte_adjuntos_select on reporte_adjuntos
  for select to authenticated
  using (fn_reporte_puede_gestionar(reporte_id)
         or (not interno and fn_reporte_es_autor(reporte_id)));

-- La líder ve SU instrucción sin ver el reporte.
create policy reporte_medidas_select on reporte_medidas
  for select to authenticated
  using (fn_reporte_puede_gestionar(reporte_id)
         or para_persona_id = fn_persona_actual_id());

-- Pública dentro del equipo: el 48.6 manda publicarla en cada sede.
create policy organos_titulo_x_select on organos_titulo_x
  for select to authenticated
  using (true);

revoke all on reportes, reporte_personas, reporte_mensajes, reporte_eventos,
              reporte_adjuntos, reporte_medidas, organos_titulo_x
  from anon, authenticated, public;
grant select on reportes, reporte_personas, reporte_mensajes, reporte_eventos,
                reporte_adjuntos, reporte_medidas, organos_titulo_x
  to authenticated;
revoke all on sequence reportes_codigo_seq from anon, authenticated, public;


-- ── 8 · El bucket y quién abre qué archivo ──────────────────────────────────
-- Ruta: <reporte_id>/<uuid>.<ext>. El primer tramo decide todo.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('reportes', 'reportes', false, 52428800,
        array['image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Lee la ruta con cuidado: una ruta mal formada devuelve false, no un error de
-- conversión a uuid (el orden en que Postgres evalúa un AND no está garantizado).
create or replace function fn_reporte_de_ruta(p_path text)
returns uuid
language sql
immutable
as $fn$
  select case
    when p_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f-]{36}\.[a-z0-9]{2,5}$'
    then split_part(p_path, '/', 1)::uuid
  end;
$fn$;

create or replace function fn_reporte_puede_ver_archivo(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_reporte uuid := fn_reporte_de_ruta(p_path);
begin
  if v_reporte is null then
    return false;
  end if;
  if fn_reporte_puede_gestionar(v_reporte) then
    return true;
  end if;
  -- Quien reportó abre lo que ella subió y lo no interno. Un archivo aún sin
  -- registrar lo abre también, porque Storage devuelve la fila recién subida.
  return fn_reporte_es_autor(v_reporte)
     and not exists (select 1 from reporte_adjuntos a where a.storage_path = p_path and a.interno);
end;
$fn$;

create or replace function fn_reporte_archivo_libre(p_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select not exists (select 1 from reporte_adjuntos a where a.storage_path = p_path);
$fn$;

-- Las CUATRO políticas, como en la 0482: Storage sube con
-- `INSERT … ON CONFLICT DO UPDATE … RETURNING *` y necesita tres para subir.
drop policy if exists reportes_insert on storage.objects;
drop policy if exists reportes_select on storage.objects;
drop policy if exists reportes_update on storage.objects;
drop policy if exists reportes_delete on storage.objects;

create policy reportes_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'reportes' and fn_reporte_puede_ver_archivo(name));

create policy reportes_select on storage.objects
  for select to authenticated
  using (bucket_id = 'reportes' and fn_reporte_puede_ver_archivo(name));

create policy reportes_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'reportes' and fn_reporte_puede_ver_archivo(name) and fn_reporte_archivo_libre(name))
  with check (bucket_id = 'reportes' and fn_reporte_puede_ver_archivo(name) and fn_reporte_archivo_libre(name));

create policy reportes_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'reportes' and fn_reporte_puede_ver_archivo(name) and fn_reporte_archivo_libre(name));


-- ── 9 · Permisos de las funciones ───────────────────────────────────────────
-- Las que llaman la RLS y la pantalla, a `authenticated`. La regla desnuda
-- (`fn_reporte_acceso`) y los niveles, a nadie: responderían sobre cualquier
-- persona que se les pase.
grant execute on function
  fn_gerencia_general_id(),
  fn_reporte_motivo(uuid),
  fn_reporte_puede_gestionar(uuid),
  fn_reporte_es_autor(uuid),
  fn_reporte_puede_ver(uuid),
  fn_reporte_quien_lo_leera(text, uuid, uuid[], uuid[]),
  fn_reporte_puede_ver_archivo(text),
  fn_reporte_archivo_libre(text),
  fn_reporte_de_ruta(text)
to authenticated;

revoke execute on function
  fn_gerencia_general_id(),
  fn_reporte_motivo(uuid),
  fn_reporte_puede_gestionar(uuid),
  fn_reporte_es_autor(uuid),
  fn_reporte_puede_ver(uuid),
  fn_reporte_quien_lo_leera(text, uuid, uuid[], uuid[]),
  fn_reporte_puede_ver_archivo(text),
  fn_reporte_archivo_libre(text),
  fn_reporte_de_ruta(text)
from public, anon;

revoke execute on function
  fn_reporte_acceso(uuid, uuid, text, uuid, smallint, boolean, uuid[]),
  fn_reporte_motivo_de(uuid, uuid),
  fn_reporte_nivel_persona(uuid),
  fn_guarda_gerencia_general(),
  fn_reporte_personas_foto(),
  fn_reporte_personas_sube_nivel()
from public, anon, authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (483, 'los_reportes_y_quien_puede_verlos')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name in
      ('reportes','reporte_personas','reporte_mensajes','reporte_eventos',
       'reporte_adjuntos','reporte_medidas','organos_titulo_x')) as tablas_de_7,
  (select count(*) from pg_class where relname in
      ('reportes','reporte_personas','reporte_mensajes','reporte_eventos',
       'reporte_adjuntos','reporte_medidas','organos_titulo_x') and relrowsecurity) as rls_de_7,
  (select count(*) from pg_policies where schemaname = 'storage' and policyname like 'reportes\_%') as politicas_storage_de_4,
  (select count(*) from storage.buckets where id = 'reportes' and public is false) as bucket_privado,
  coalesce((select p.apellidos || ' ' || p.nombres from personas p where p.id = fn_gerencia_general_id()),
           'SIN MARCA — ver el encabezado') as gerencia_general,
  (select count(*) from organos_titulo_x) as organos_titulo_x,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 483) as registro;
