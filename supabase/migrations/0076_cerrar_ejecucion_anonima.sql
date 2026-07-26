-- ============================================================================
-- 0076 — Cerrar la ejecución anónima y sacar la firma escaneada de `personas`
-- ----------------------------------------------------------------------------
-- PROMETE:
--   1. Que nadie sin sesión (rol `anon`, la clave que viaja en el JavaScript
--      público) pueda ejecutar ninguna función del sistema — y que las funciones
--      que se creen de aquí en adelante nazcan cerradas, sin depender de que
--      cada migración se acuerde de revocar.
--   2. Que el permiso para actuar sobre un expediente responda `false` y no
--      `null` cuando quien pregunta no es una persona (una terminal de sede).
--   3. Que la firma escaneada viva en su propia tabla, inalcanzable por la API
--      REST, y se lea SOLO en el contexto del documento que la lleva impresa.
--
-- ASUME: personas, expediente_disciplinario, los helpers de RLS de 0003/0005,
--   la columna personas.firma_base64 de 0065.
--
-- NO TOCA (a propósito): fn_registrar_marcaje. Su candado de identidad de
--   terminal (0068) tampoco valida cuando auth.uid() es null, pero ese hueco
--   solo era alcanzable por `anon` — y el bloque 1 se lo quita. Reescribir la
--   función que registra las marcas de la tienda merece su propia migración con
--   su propia prueba, no ir de pasajera en esta.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · La ejecución anónima
-- ════════════════════════════════════════════════════════════════════════════
-- Postgres concede EXECUTE a PUBLIC en toda función nueva, y `anon` hereda de
-- PUBLIC. De las 88 funciones con `grant ... to authenticated`, 37 nunca
-- recibieron el `revoke ... from public` — entre ellas fn_registrar_marcaje,
-- fn_corregir_marcaje, fn_eliminar_marcaje, fn_set_datos_personales y
-- fn_expediente_crear_borrador.
--
-- ORDEN CRÍTICO — conceder antes de revocar, y en esta misma transacción:
--   los helpers de RLS (fn_rol_actual, fn_persona_actual_id, fn_es_admin_o_lider,
--   fn_sede_actual_persona, fn_sede_actual_terminal, fn_expediente_puede_actuar)
--   NUNCA tuvieron un grant explícito. Hoy funcionan únicamente por ese EXECUTE
--   heredado de PUBLIC. Si se revocara primero, toda política RLS del sistema
--   quedaría inejecutable y NADIE podría leer un solo dato.
--
-- Esto NO cambia lo que puede hacer un usuario con sesión: `authenticated` ya
-- forma parte de PUBLIC, así que el grant explícito solo deja por escrito lo
-- que ya tenía. Lo único que se pierde es el acceso de `anon`.
do $$
declare
  r record;
  n int := 0;
  omitidas text[] := '{}';
  s text;
begin
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      -- Las funciones de trigger no se invocan por RPC: Postgres no comprueba
      -- EXECUTE al dispararlas. Quedan fuera para no tocar lo que no hace falta.
      and p.prorettype <> 'trigger'::regtype
      -- Nada de pgcrypto / pg_cron / btree_gist: revocar EXECUTE en funciones de
      -- extensión (gen_random_uuid, por ejemplo) rompería los defaults de tabla.
      and not exists (
        select 1 from pg_depend d
        where d.objid = p.oid and d.deptype = 'e')
  loop
    -- Cada función se trata por separado y los fallos NO abortan el recorrido.
    --
    -- Este archivo se pega a mano en el SQL Editor, donde se corre como el rol
    -- `postgres` de Supabase — que NO es superusuario. Si alguna función de
    -- `public` pertenece a otro rol, el `grant` levanta "must be owner of
    -- function" y, sin este bloque, el DO entero se cae y NADA de las 800
    -- líneas siguientes llega a ejecutarse: la base queda igual que antes y sin
    -- ninguna pista de por qué.
    --
    -- Lo que no se pudo tocar se reporta al final por nombre, para revisarlo a
    -- mano. Es preferible cerrar 99 funciones y saber cuál falta, a no cerrar
    -- ninguna.
    begin
      execute format('grant execute on function %s to authenticated, service_role', r.sig);
      execute format('revoke execute on function %s from public', r.sig);
      n := n + 1;
    exception when others then
      omitidas := array_append(omitidas, r.sig || '  (' || sqlerrm || ')');
    end;
  end loop;

  raise notice 'Funciones cerradas a anon: %', n;
  if array_length(omitidas, 1) > 0 then
    raise warning 'NO se pudieron cerrar % función(es). Revisar a mano:', array_length(omitidas, 1);
    foreach s in array omitidas loop
      raise warning '  · %', s;
    end loop;
  end if;
end $$;

-- Que las FUTURAS nazcan cerradas. Esto es lo que convierte "acordarse del
-- revoke" en "imposible olvidarlo": la razón por la que se escaparon 37 veces
-- no fue descuido, fue que nada lo impedía.
--
-- Aplica a las funciones que cree el rol que ejecuta esta migración (en Supabase,
-- `postgres`). `authenticated` se sigue concediendo explícitamente en cada
-- migración, como ya se hace en las 88 existentes.
--
-- SÍNTOMA SI SE OLVIDA UN GRANT: la pantalla recibe
--   "permission denied for function fn_algo"
-- Se arregla añadiendo `grant execute on function fn_algo to authenticated;`
-- a la migración que la crea. Falla cerrado y a la vista — no en silencio.
--
-- OJO CON LA FALTA DE "in schema" EN LA PRIMERA LÍNEA — no es un olvido:
--   el EXECUTE que PUBLIC tiene por defecto sobre las funciones es GLOBAL, no
--   por schema. Una cláusula `in schema public` solo puede AÑADIR privilegios
--   encima de ese default; nunca restarlos. Escrita como
--     alter default privileges IN SCHEMA public revoke execute ... from public
--   la sentencia se acepta sin error, no registra nada en pg_default_acl y las
--   funciones nuevas siguen naciendo abiertas a `anon`. Verificado en
--   PostgreSQL 16: con `in schema` → anon puede; sin él → anon no puede.
--
-- EFECTO SECUNDARIO A TENER PRESENTE: al ser global para el rol que aplica las
--   migraciones (`postgres`), esto también alcanza a las funciones que ese rol
--   cree en OTROS schemas. En la práctica solo importa al instalar una extensión
--   nueva: sus funciones nacerían sin EXECUTE para PUBLIC y habría que
--   concederlo a mano. El síntoma es el mismo "permission denied for function".
alter default privileges revoke execute on functions from public;
alter default privileges in schema public grant execute on functions to service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · El permiso que respondía "no sé" en vez de "no"
-- ════════════════════════════════════════════════════════════════════════════
-- fn_expediente_puede_actuar devolvía NULL cuando quien pregunta no tiene fila
-- en `personas`. El caso real: una TERMINAL de sede. Está autenticada (tiene su
-- propio auth_user_id) pero no es una persona, así que fn_rol_actual() devuelve
-- null y toda la expresión se propaga a null.
--
-- Sus 7 usos tienen la forma `if not fn_expediente_puede_actuar(...) then raise`.
-- Y `not null` es null, que no es verdadero: el `if` no entra y la excepción
-- nunca se lanza. Resultado: la tablet de una boutique podía crear, editar,
-- firmar, entregar y anular expedientes — y con el firmante explícito de 0071,
-- emitir un memo firmado por gerencia.
--
-- Se arregla en la RAÍZ y no en los 7 llamadores: una función que responde una
-- pregunta de permiso no tiene por qué poder contestar "no sé".
create or replace function fn_expediente_puede_actuar(p_persona_id uuid, p_nivel text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(fn_es_admin_o_lider(), false)
      or coalesce(
           fn_rol_actual() = 'supervisor_sede'
           and p_nivel in ('verbal','amonestacion')
           and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona()
         , false);
$$;
grant execute on function fn_expediente_puede_actuar(uuid, text) to authenticated;
revoke execute on function fn_expediente_puede_actuar(uuid, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · La firma escaneada sale de `personas`
-- ════════════════════════════════════════════════════════════════════════════
-- Por qué se muda de tabla en lugar de revocar la columna: `authenticated` tiene
-- SELECT sobre la tabla `personas` completa (0004_grants.sql:12). En Postgres un
-- `revoke select (firma_base64)` no reduce nada mientras exista ese privilegio a
-- nivel de tabla — habría quedado con apariencia de cerrado y abierto igual.
--
-- Y las políticas de `personas` la exponían de verdad: la encargada lee las filas
-- de su sede (0003_rls.sql:66) y la TERMINAL lee las personas activas de su sede
-- (0008:12). O sea, la tablet de la tienda podía pedir la fila entera del
-- firmante. Una cuenta bancaria filtrada permite recibir; una firma escaneada
-- permite EMITIR, y el sistema no puede saber que salió de ahí.
--
-- La tabla nueva lleva RLS SIN NINGUNA POLÍTICA: acceso directo negado para
-- todos, incluido admin. Solo se entra por las tres funciones de abajo.
create table if not exists firmas_escaneadas (
  persona_id     uuid primary key references personas(id) on delete cascade,
  imagen         text not null,
  actualizado_at timestamptz not null default now(),
  -- Estados imposibles: una firma que no es una imagen, o un escaneo a 600 dpi
  -- de una hoja entera (10 MB de texto en una fila). El tope holgado es de la
  -- tabla; el estricto lo pone fn_set_mi_firma, para que ninguna firma que ya
  -- existe haga fallar esta migración.
  constraint chk_firma_es_imagen check (imagen ~ '^data:image/(png|jpeg);base64,'),
  constraint chk_firma_peso      check (length(imagen) <= 1048576)
);

alter table firmas_escaneadas enable row level security;
revoke all on firmas_escaneadas from authenticated, anon;

-- Mudanza de lo que ya está cargado.
--
-- Todo el bloque va dentro de un condicional porque esta migración se pega A
-- MANO en el SQL Editor, y una mano hace doble clic. En la segunda pasada la
-- columna `personas.firma_base64` ya no existe (la borra el paso siguiente) y
-- un `insert ... select firma_base64` reventaría a media migración, dejándola
-- aplicada por la mitad. No se puede resolver con `if exists` a secas: el
-- planificador valida la columna aunque la rama no se ejecute, así que la
-- consulta va como texto y solo se compila si de verdad hay algo que mudar.
do $mudanza$
declare n_origen int; n_destino int; n_malformadas int;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'personas' and column_name = 'firma_base64'
  ) then
    raise notice 'La mudanza de firmas ya se hizo (la columna firma_base64 no existe). Nada que hacer.';
    return;
  end if;

  execute $mv$
    insert into firmas_escaneadas (persona_id, imagen)
    select id, firma_base64 from personas
    where firma_base64 is not null
      and firma_base64 ~ '^data:image/(png|jpeg);base64,'
    on conflict (persona_id) do nothing
  $mv$;

  execute 'select count(*) from personas where firma_base64 is not null' into n_origen;
  select count(*) into n_destino from firmas_escaneadas;
  execute $ct$select count(*) from personas
             where firma_base64 is not null
               and firma_base64 !~ '^data:image/(png|jpeg);base64,'$ct$ into n_malformadas;

  raise notice 'Firmas en personas: % · migradas: % · descartadas por formato: %',
    n_origen, n_destino, n_malformadas;
  if n_malformadas > 0 then
    raise warning 'Hay % firma(s) con formato inválido que NO se migraron. Revisar antes de dar por buena la mudanza.', n_malformadas;
  end if;
end
$mudanza$;

-- Y se va la columna: mientras exista, sigue viajando en cualquier `select *`
-- sobre personas. El reverso de esta migración la recrea y copia de vuelta.
alter table personas drop column if exists firma_base64;


-- ── Guardar MI firma ─────────────────────────────────────────────────────────
-- Igual que antes (solo admin/líder, que son quienes firman; null la borra),
-- pero ahora escribe en la tabla nueva y valida el peso de verdad.
-- 400 000 caracteres ≈ 300 KB de imagen: la pantalla ya reescala la firma a
-- 520 px de ancho, así que una firma real ronda los 20–80 KB.
create or replace function fn_set_mi_firma(p_dataurl text)
returns void language plpgsql security definer set search_path = public as $$
declare v_yo uuid;
begin
  if not coalesce(fn_es_admin_o_lider(), false) then
    raise exception 'Solo un administrador o líder puede guardar su firma.';
  end if;
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  if p_dataurl is null then
    delete from firmas_escaneadas where persona_id = v_yo;
    return;
  end if;
  if p_dataurl !~ '^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$' then
    raise exception 'Formato inválido: la firma debe ser una imagen PNG o JPEG.';
  end if;
  if length(p_dataurl) > 400000 then
    raise exception 'La firma pesa demasiado (% KB, el máximo es 390 KB). Vuelve a escanearla más pequeña.',
      round(length(p_dataurl) / 1024.0);
  end if;

  insert into firmas_escaneadas (persona_id, imagen, actualizado_at)
  values (v_yo, p_dataurl, now())
  on conflict (persona_id) do update
    set imagen = excluded.imagen, actualizado_at = now();
end;
$$;
grant execute on function fn_set_mi_firma(text) to authenticated;
revoke execute on function fn_set_mi_firma(text) from public, anon;

-- ── Ver MI firma ─────────────────────────────────────────────────────────────
-- Para la pantalla de perfil, donde cada firmante gestiona la suya.
create or replace function fn_mi_firma()
returns text language sql stable security definer set search_path = public as $$
  select imagen from firmas_escaneadas where persona_id = fn_persona_actual_id();
$$;
grant execute on function fn_mi_firma() to authenticated;
revoke execute on function fn_mi_firma() from public, anon;

-- ── Ver la firma QUE LLEVA ESTE DOCUMENTO ────────────────────────────────────
-- El error de fondo de fn_firma_persona no era el filtro flojo: era la pregunta.
-- Preguntaba "¿puedo leer la firma de esta persona?" cuando lo que hay que
-- preguntar es "¿puedo leer la firma de quien suscribe este documento?".
--
-- Por eso la encargada de una boutique SÍ puede imprimir un memo de su sede
-- firmado por gerencia (que está en otra sede) — la delegación de firma sigue
-- funcionando — pero NO puede pedir la firma de gerencia a secas.
--
-- La condición replica las políticas de SELECT de expediente_disciplinario
-- (0056:100-112): si puedes ver el memo, puedes ver la firma impresa en él.
-- Ni una regla nueva de visibilidad.
--
-- Los niveles graves quedan fuera: imputación y despido van con firma digital
-- certificada o manuscrita, nunca escaneada. Estaba dicho en el comentario de
-- 0065 y confiado a la pantalla; aquí lo hace cumplir la base.
create or replace function fn_firma_de_memo(p_doc_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select f.imagen
  from expediente_disciplinario d
  join firmas_escaneadas f on f.persona_id = d.firmante_id
  where d.id = p_doc_id
    and d.nivel in ('verbal','amonestacion','suspension')
    and (coalesce(fn_es_admin_o_lider(), false)
         or (fn_rol_actual() = 'supervisor_sede'
             and d.persona_id in (select id from personas
                                  where sede_base_id = fn_sede_actual_persona()))
         or d.persona_id = fn_persona_actual_id());
$$;
grant execute on function fn_firma_de_memo(uuid) to authenticated;
revoke execute on function fn_firma_de_memo(uuid) from public, anon;

-- ── fn_firma_persona: cerrada, no borrada ────────────────────────────────────
-- Se deja existir a propósito. La pantalla de perfil que hoy está en producción
-- todavía la llama, y borrarla ahora dejaría esa pantalla con un error hasta que
-- se despliegue el frontend nuevo. Cerrada a "solo la tuya", el agujero queda
-- tapado y nada se rompe. La borra la migración siguiente, ya con el front al día.
create or replace function fn_firma_persona(p_persona_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select imagen from firmas_escaneadas
  where persona_id = p_persona_id
    and persona_id = fn_persona_actual_id();
$$;
grant execute on function fn_firma_persona(uuid) to authenticated;
revoke execute on function fn_firma_persona(uuid) from public, anon;

-- ── fn_expediente_firmantes: seguía leyendo la columna que esta migración borra ──
-- La 0074 la definió con `p.firma_base64 is not null` para el aviso "tiene
-- firma". Al soltar la columna, Postgres no avisa (no rastrea dependencias
-- dentro del cuerpo de una función): el diálogo de firmar habría reventado en
-- runtime la próxima vez que alguien lo abriera. Misma lógica, fuente nueva.
--
-- Va dentro de un condicional porque esta función NACE en la 0074, que se
-- aplicó en producción desde otra máquina. Si esta base todavía no la tiene,
-- no se inventa aquí: la 0074 ya la trae bien y esta migración no debe
-- adelantarse a ella. Cuando la 0074 sí está, se corrige.
do $fix$
begin
  if exists (select 1 from pg_proc where proname = 'fn_expediente_firmantes') then
    execute $ddl$
create or replace function fn_expediente_firmantes(p_id uuid)
returns table (persona_id uuid, nombre text, cargo text, tiene_firma boolean)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if fn_expediente_puede_actuar(r.persona_id, r.nivel) is not true then
    raise exception 'Sin permiso sobre este documento.';
  end if;

  return query
  select p.id,
         (p.nombres || ' ' || p.apellidos)::text,
         fn_cargo_de_rol(p.rol),
         exists (select 1 from firmas_escaneadas f where f.persona_id = p.id)
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
$fn$;
    $ddl$;
    execute 'grant execute on function fn_expediente_firmantes(uuid) to authenticated';
    execute 'revoke execute on function fn_expediente_firmantes(uuid) from public, anon';
  end if;
end
$fix$;


notify pgrst, 'reload schema';
