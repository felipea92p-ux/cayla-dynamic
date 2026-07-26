-- ============================================================================
-- APLICAR 0076 → 0080 · paquete de seguridad y correcciones
-- ----------------------------------------------------------------------------
-- Pegar ENTERO en el SQL Editor de Supabase y pulsar Run UNA vez.
-- Es idempotente: si lo pegas dos veces, la segunda no hace daño.
--
-- QUÉ APLICA, EN ORDEN:
--   0076 · Cierra la ejecución anónima. Hoy la clave pública que viaja en el
--          JavaScript del sitio puede ejecutar 51 funciones que saltan todos
--          los permisos (registrar marcas por cualquiera, sobrescribir cuentas
--          bancarias, firmar memos). Después de esto: ninguna.
--          También saca la firma escaneada de `personas` a su propia tabla.
--   0077 · Crea el registro de qué migraciones tiene esta base, y lo llena
--          hacia atrás. Después de esto, un SELECT dice la verdad.
--   0078 · Arregla los permisos que "fallan abiertos": hoy una terminal de
--          sede puede sobrescribir la cuenta bancaria de una colaboradora
--          porque el guard responde NULL y el `if not NULL` no bloquea.
--   0079 · Los días de suspensión sin goce dejan de contar como faltas
--          injustificadas (hoy la sanción alimenta el expediente de despido).
--
-- NO incluye la 0074 ni la 0075 a propósito: esas cambian una regla de negocio
-- (quién puede figurar como firmante de un memo) y esa decisión sigue abierta.
--
-- VERIFICADO el 26/07/2026 contra un PostgreSQL 17 limpio con las 79
-- migraciones aplicadas desde cero. Al final hay un bloque de comprobación.
-- ============================================================================


-- ═════════════════════════════════════════════════════════════════════════
-- ↓↓↓  0076_cerrar_ejecucion_anonima.sql
--   0080 · Carga los feriados nacionales hasta 2032 (hoy solo hay 2026: el
--          1 de enero de 2027 la planilla dejaria de pagarlos sin avisar) y
--          agrega un aviso cuando queden menos de 3 meses de calendario.

-- =========================================================================
-- >>>  0076_cerrar_ejecucion_anonima.sql
-- =========================================================================
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
    execute format('grant execute on function %s to authenticated, service_role', r.sig);
    execute format('revoke execute on function %s from public', r.sig);
    n := n + 1;
  end loop;
  raise notice 'Funciones cerradas a anon: %', n;
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

-- =========================================================================
-- >>>  0077_registro_de_migraciones.sql
-- =========================================================================
-- ============================================================================
-- 0077 — La base sabe qué migraciones tiene puestas
-- ----------------------------------------------------------------------------
-- PROMETE: que un solo SELECT diga la verdad sobre qué migraciones corrieron
-- en ESTA base — sin depender de la memoria de nadie ni de un documento.
--
-- EL PROBLEMA QUE CIERRA: las migraciones se pegan a mano en el SQL Editor
-- (decisión deliberada: la clave de servicio está rotada). Eso funciona, pero
-- dejó el estado de producción documentado en prosa, y la prosa se quedó en la
-- 0034 mientras la base iba por la 0073. En julio 2026 eso ya costó un enredo
-- real: dos migraciones aplicadas en prod (0074/0075) cuyo archivo estuvo a
-- punto de perderse en una copia de iCloud.
--
-- CÓMO SE USA: cada migración, desde la 0078 en adelante, termina con su línea
--   insert into migraciones_aplicadas (numero, nombre) values (78, '...')
--   on conflict (numero) do nothing;
-- Si el archivo se pega dos veces, la segunda no hace nada (todas las
-- migraciones de este repo son idempotentes; el registro también).
--
-- CARGA RETROACTIVA: esta migración registra la 0001–0073 de una vez, porque
-- esta base ya las tiene (si estás leyendo esto desde el SQL Editor de prod,
-- es porque prod ya va por aquí). La 0074/0075/0076 se registran en el bloque
-- final SOLO si sus objetos existen — así el mismo archivo dice la verdad
-- también en una base local que vaya en otro punto.
--
-- Reversible: drop table migraciones_aplicadas (no toca nada del negocio).
-- ============================================================================

create table if not exists migraciones_aplicadas (
  numero      int primary key,
  nombre      text not null,
  aplicada_at timestamptz not null default now()
);

-- Nadie escribe ni lee esto desde la app: es del operador (SQL Editor).
alter table migraciones_aplicadas enable row level security;
revoke all on migraciones_aplicadas from authenticated, anon;

-- ── Retroactivo: lo que esta base ya tiene si llegó hasta aquí ──────────────
-- (Nombres tomados de los archivos reales de supabase/migrations/. La 0031 y
-- la 0033 viven fuera de git por datos personales — scripts/sql-manual/ — pero
-- en esta base sí corrieron, así que se registran.)
insert into migraciones_aplicadas (numero, nombre) values
  ( 1,'init'),( 2,'functions'),( 3,'rls'),( 4,'grants'),
  ( 5,'fix_rls_recursion'),( 6,'personas_email'),( 7,'auto_cierre'),( 8,'visible_todas_sedes'),
  ( 9,'correcciones'),(10,'correccion_supervisor'),(11,'editor_horarios'),(12,'terminal_requiere_pin'),
  (13,'turnos_por_dia'),(14,'turnos_cobertura'),(15,'horario_base_dias_refrigerio'),(16,'horario_por_dia'),
  (17,'salida_temprana_extra'),(18,'funcion_persona'),(19,'salarios'),(20,'rpc_bypass_cache'),
  (21,'areas'),(22,'areas_catalogo'),(23,'parche_areas'),(24,'planilla'),
  (25,'planilla_periodos'),(26,'parche_planilla_v2'),(27,'feriado_por_ingreso'),(28,'ingreso_primera_marca'),
  (29,'provisiones_acumuladas'),(30,'provisiones_anual'),(31,'historico_2025_sql_manual'),(32,'objetivos_checklist'),
  (33,'ingresos_2025_sql_manual'),(34,'bono_puntualidad'),(35,'provisiones_zona_horaria'),(36,'auto_cierre_horario'),
  (37,'candado_periodo_pagado'),(38,'meta_encargadas'),(39,'meta_por_tramo'),(40,'encargada_piso'),
  (41,'drop_sembrar_ingresos'),(42,'vacaciones'),(43,'vacaciones_resumen'),(44,'vacaciones_saldo_acumulado'),
  (45,'historico_2025_diario'),(46,'en_planilla'),(47,'sueldo_fijo'),(48,'provisiones_sueldo_fijo'),
  (49,'grati_cts_en_planilla'),(50,'nombres_internos_grati_cts'),(51,'faltas_deteccion'),(52,'incidencias_aceptadas'),
  (53,'levantar_tardanza'),(54,'faltas_resumen'),(55,'faltas_en30_ventana_movil'),(56,'expediente_disciplinario'),
  (57,'tardanzas_resumen'),(58,'expediente_funciones'),(59,'generar_tardanza'),(60,'generar_falta'),
  (61,'datos_personales'),(62,'tardanzas_ultima_fecha'),(63,'sedes_gestionables'),(64,'tardanzas_resumen_no_bis_in_idem'),
  (65,'firma_escaneada'),(66,'reversas_pago'),(67,'tardanzas_faltas_as_of'),(68,'marcajes_fuera_de_orden'),
  (69,'feriado_descanso_sustitutorio'),(70,'faltas_conocen_descanso_sustitutorio'),(71,'elegir_firmante'),
  (72,'descanso_sustitutorio_acuerdo_previo'),(73,'actas_descanso_sustitutorio')
on conflict (numero) do nothing;

-- ── 0074–0076: solo si de verdad están (verifica el objeto, no la memoria) ──
do $$
begin
  -- 0074: firmante elegible + cargo entregado (existe su tabla de adjuntos)
  if to_regclass('public.expediente_adjuntos') is not null then
    insert into migraciones_aplicadas (numero, nombre)
    values (74, 'firmante_elegible_y_cargo_entregado') on conflict (numero) do nothing;
  end if;
  -- 0075: suspensión en días laborables (existe fn_dias_suspension)
  if exists (select 1 from pg_proc where proname = 'fn_dias_suspension') then
    insert into migraciones_aplicadas (numero, nombre)
    values (75, 'suspension_en_dias_laborables') on conflict (numero) do nothing;
  end if;
  -- 0076: cierre de ejecución anónima (existe la tabla de firmas)
  if to_regclass('public.firmas_escaneadas') is not null then
    insert into migraciones_aplicadas (numero, nombre)
    values (76, 'cerrar_ejecucion_anonima') on conflict (numero) do nothing;
  end if;
end $$;

insert into migraciones_aplicadas (numero, nombre) values (77, 'registro_de_migraciones')
on conflict (numero) do nothing;

-- Para leer el estado:  select * from migraciones_aplicadas order by numero;
-- Para ver huecos:      select generate_series(1, (select max(numero) from migraciones_aplicadas)) n
--                       except select numero from migraciones_aplicadas order by 1;

-- =========================================================================
-- >>>  0078_guards_no_fallan_abiertos.sql
-- =========================================================================
-- ============================================================================
-- 0078 — Que un permiso que no se sabe responder sea "no", nunca "quizá"
-- ----------------------------------------------------------------------------
-- PROMETE: que ningún guard de permiso del sistema deje pasar una operación
--   porque la respuesta fue NULL en vez de false.
-- ASUME: la 0076 ya corrigió fn_expediente_puede_actuar (sus 7 usos quedan
--   cubiertos por ella). Esta cierra los que quedaron.
--
-- EL DEFECTO, EN CRIOLLO. Los permisos se preguntan así:
--
--     if not fn_es_admin_o_lider() then raise exception 'Sin permiso'; end if;
--
-- fn_es_admin_o_lider() es `fn_rol_actual() in ('admin','lider_do')`. Cuando
-- quien pregunta NO TIENE FILA en `personas`, fn_rol_actual() devuelve NULL, y
-- `NULL in (...)` es NULL — no es false, es "no sé". Y `not NULL` también es
-- NULL. Un `if` con condición NULL NO ENTRA: el `raise exception` nunca se
-- dispara y la operación continúa como si el permiso estuviera concedido.
--
-- QUIÉN ES ESA IDENTIDAD SIN FILA EN personas: la TERMINAL de cada sede. Se
-- autentica con su propio usuario y clave (no es una colaboradora), así que
-- tiene sesión válida y no tiene fila. Es decir, no es un caso hipotético: hay
-- tres de esas identidades encendidas todo el día en TRU, LIM y AQP.
--
-- REPRODUCIDO EL 26/07/2026 contra un Postgres limpio con las 77 migraciones:
-- con la sesión de un terminal, `fn_set_datos_personales` sobrescribió la
-- cuenta bancaria y el número de cuenta de una colaboradora sin error alguno.
--
-- POR QUÉ SE ARREGLA EN LA RAÍZ Y NO GUARD POR GUARD. Se podría envolver cada
-- `if` en un `coalesce`. Pero entonces el próximo guard que alguien escriba
-- vuelve a nacer roto: la forma natural de escribirlo es la insegura. Se
-- corrige la FUENTE — que fn_es_admin_o_lider nunca conteste NULL — y con eso
-- los cuatro sitios que la usan quedan sanos sin tocarlos, incluidos los que
-- se escriban mañana. Solo queda un guard compuesto (datos personales) que
-- mezcla tres preguntas distintas; ese sí se reescribe a mano, con la forma
-- `is not true` que manda CLAUDE.md.
--
-- Reversible: volver a las definiciones de 0003 / 0061 / 0074.
-- ============================================================================

-- ── La raíz: un booleano de permiso jamás contesta "no sé" ──────────────────
-- Ojo: fn_rol_actual() SÍ debe poder devolver NULL — "esta identidad no tiene
-- rol" es un hecho verdadero y otras consultas lo usan. Lo que no puede seguir
-- pasando es que esa incertidumbre se propague a una PREGUNTA DE PERMISO.
create or replace function fn_es_admin_o_lider()
returns boolean
language sql stable
as $$
  select coalesce(fn_rol_actual() in ('admin', 'lider_do'), false);
$$;

-- ── Adjuntar al expediente: hereda el NULL de puede_actuar ──────────────────
-- La 0076 ya hizo que fn_expediente_puede_actuar conteste false. Se blinda
-- igual aquí para que esta función sea correcta por sí sola y no dependa del
-- orden en que se apliquen las migraciones.
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
  return coalesce(fn_expediente_puede_actuar(v_doc.persona_id, v_doc.nivel), false);
end;
$$;

-- ── El guard compuesto de datos personales ──────────────────────────────────
-- Aquí el coalesce de la raíz no alcanza: las otras dos ramas comparan UUIDs
-- (`p_persona_id = fn_persona_actual_id()`), y comparar contra NULL da NULL.
-- `false or NULL or NULL` sigue siendo NULL. Por eso la condición entera se
-- evalúa con `is not true`: la única respuesta que abre la puerta es un TRUE
-- explícito.
--
-- Se conserva el resto del cuerpo tal cual estaba en la 0061.
create or replace function fn_set_datos_personales(
  p_persona_id uuid,
  p_nombre_dni text default null, p_fecha_nacimiento date default null, p_estado_civil text default null,
  p_direccion text default null, p_celular text default null,
  p_entidad_bancaria text default null, p_numero_cuenta text default null,
  p_grado_instruccion text default null, p_hijos_menores boolean default null,
  p_foto_dni_url text default null, p_foto_personal_url text default null, p_foto_profesional_url text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if (fn_es_admin_o_lider()
      or p_persona_id = fn_persona_actual_id()
      or (fn_rol_actual() = 'supervisor_sede'
          and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona())
     ) is not true then
    raise exception 'Sin permiso para editar los datos personales de esta persona.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;
  insert into datos_personales as dp (
    persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular,
    entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores,
    foto_dni_url, foto_personal_url, foto_profesional_url, actualizado_por, actualizado_at)
  values (
    p_persona_id, p_nombre_dni, p_fecha_nacimiento, p_estado_civil, p_direccion, p_celular,
    p_entidad_bancaria, p_numero_cuenta, p_grado_instruccion, p_hijos_menores,
    p_foto_dni_url, p_foto_personal_url, p_foto_profesional_url, fn_persona_actual_id(), now())
  -- Cuerpo IDÉNTICO al de la 0061: esta migración cambia el permiso, nada más.
  -- (Un campo enviado en null se limpia a propósito — así estaba y así queda;
  -- cambiarlo a "null preserva" sería otra decisión y va en otra migración.)
  on conflict (persona_id) do update set
    nombre_dni = excluded.nombre_dni, fecha_nacimiento = excluded.fecha_nacimiento,
    estado_civil = excluded.estado_civil, direccion = excluded.direccion, celular = excluded.celular,
    entidad_bancaria = excluded.entidad_bancaria, numero_cuenta = excluded.numero_cuenta,
    grado_instruccion = excluded.grado_instruccion, hijos_menores = excluded.hijos_menores,
    foto_dni_url = excluded.foto_dni_url, foto_personal_url = excluded.foto_personal_url,
    foto_profesional_url = excluded.foto_profesional_url,
    actualizado_por = fn_persona_actual_id(), actualizado_at = now();
end;
$$;

revoke execute on function fn_set_datos_personales(uuid, text, date, text, text, text, text, text, text, boolean, text, text, text) from public, anon;
grant  execute on function fn_set_datos_personales(uuid, text, date, text, text, text, text, text, text, boolean, text, text, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre) values (78, 'guards_no_fallan_abiertos')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- =========================================================================
-- >>>  0079_suspension_no_es_falta.sql
-- =========================================================================
-- ============================================================================
-- 0079 — Cumplir una suspensión no es faltar
-- ----------------------------------------------------------------------------
-- PROMETE: que los días en que una persona está cumpliendo una suspensión sin
--   goce de haber queden registrados como ausencia AUTORIZADA (visibles, con
--   su motivo), y no sumen al conteo disciplinario que empuja al despido.
-- ASUME: la suspensión vive en expediente_disciplinario con estado 'firmado' u
--   'entregado' y su rango en suspension_desde…suspension_hasta (mig. 0056).
--
-- EL DEFECTO. La detección de faltas (última versión en 0070) excluye del
-- conteo: vacaciones, justificaciones, descanso sustitutorio y feriados sin
-- turno. No excluye las suspensiones. Y una suspensión es justamente un día
-- que la persona TENÍA programado trabajar y en el que, por orden de la
-- empresa, no vino y no marcó. Es decir: cumple los cuatro requisitos de
-- "falta injustificada" y se cuenta como tal.
--
-- LA CONSECUENCIA, EN CONCRETO. Suspendes a alguien tres días. El sistema
-- registra tres faltas injustificadas. El umbral legal del art. 25-h del
-- D.S. 003-97-TR se configura con más de cinco en treinta días: dos
-- suspensiones cortas en un mes y el semáforo se pone rojo, el sistema arma el
-- expediente y señala "posible causal". La sanción que ya se cumplió se
-- convierte en la prueba para la siguiente. Eso es sancionar dos veces el
-- mismo hecho, y no se sostiene ante una inspección ni ante un juez.
--
-- ESTA REGLA YA EXISTÍA EN EL SISTEMA, A MEDIAS. La 0064 corrigió exactamente
-- esto para las tardanzas ("non bis in idem": una tardanza ya amonestada no
-- vuelve a contar). Faltas nació sin esa mitad. No se está inventando un
-- criterio: se está terminando de aplicar el que ya tomaste.
--
-- DECISIÓN (Felipe, 26/07/2026): el día se ve, con su motivo 'suspension',
-- pero no cuenta. Se descartó ocultarlo, porque el legajo tiene que poder
-- mostrar que la sanción se cumplió; y se descartó justificarlo a mano,
-- porque depende de que nadie olvide un paso y el olvido escala solo.
--
-- POR QUÉ NO SE MATERIALIZA. Igual que las faltas y las tardanzas, el día
-- suspendido no se escribe en ninguna tabla: se computa. Si se guardara,
-- anular un expediente dejaría filas mintiendo.
--
-- SOLO CUENTAN LOS DOCUMENTOS VIVOS ('firmado','entregado'). Un borrador aún
-- no sanciona a nadie, y uno anulado dejó de hacerlo: en ambos casos el día
-- vuelve a ser una ausencia común, que es lo correcto.
--
-- Reversible: restaurar fn_faltas y fn_faltas_resumen de la 0070.
-- ============================================================================

-- ── ¿Esta persona estaba cumpliendo suspensión este día? ────────────────────
-- Se extrae a una función propia para que las dos consultas de faltas usen
-- LA MISMA definición. Si divergieran, el detalle diría una cosa y el semáforo
-- otra sobre la misma persona — que es como nacen los errores que nadie cree.
create or replace function fn_dia_suspendido(p_persona_id uuid, p_fecha date)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from expediente_disciplinario e
    where e.persona_id = p_persona_id
      and e.estado in ('firmado', 'entregado')
      and e.suspension_desde is not null
      and p_fecha between e.suspension_desde and e.suspension_hasta
  );
$$;
grant  execute on function fn_dia_suspendido(uuid, date) to authenticated;
revoke execute on function fn_dia_suspendido(uuid, date) from public, anon;


-- ── El detalle día por día ──────────────────────────────────────────────────
-- Cuerpo idéntico al de la 0070 salvo el nuevo left join `sus` y su aparición
-- en `justificada` y `motivo`.
create or replace function fn_faltas(p_desde date, p_hasta date)
returns table (persona_id uuid, nombre text, sede text, fecha date, justificada boolean, motivo text)
language sql stable security definer set search_path = public
as $$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede, pe.fecha_ingreso
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  dias as (
    select m.id as persona_id, m.nombre, m.sede, gs::date as fecha
    from medibles m
    cross join lateral generate_series(
      greatest(p_desde, m.fecha_ingreso),
      least(p_hasta, (now() at time zone 'America/Lima')::date - 1),
      interval '1 day') gs
  ),
  evaluado as (
    select d.*,
      (t.persona_id is not null) as hay_turno,
      coalesce(t.es_descanso, false) as turno_descanso,
      tr.horario_por_dia, tr.dias_laborables
    from dias d
    left join turnos t on t.persona_id = d.persona_id and t.fecha = d.fecha
    left join lateral (
      select h.horario_por_dia, h.dias_laborables
      from horarios_asignados h
      where h.persona_id = d.persona_id and h.vigente_desde <= d.fecha
        and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
      order by h.vigente_desde desc limit 1
    ) tr on true
  ),
  tocaba as (
    select e.*,
      case
        when e.hay_turno then not e.turno_descanso                       -- el turno del día manda
        when e.horario_por_dia is not null then (e.horario_por_dia ? (extract(dow from e.fecha)::int::text))
        when e.dias_laborables is not null then (extract(dow from e.fecha)::int = any(e.dias_laborables))
        else false
      end as trabaja
    from evaluado e
  )
  select tb.persona_id, tb.nombre, tb.sede, tb.fecha,
    (v.persona_id is not null or ju.motivo is not null or ds.persona_id is not null
     or sus.es is not null) as justificada,
    coalesce(
      -- La suspensión manda sobre cualquier otro motivo: es un hecho de la
      -- empresa, no una situación de la persona.
      case when sus.es is not null then 'suspension' end,
      ju.motivo,
      case when v.persona_id is not null then 'vacaciones' end,
      case when ds.persona_id is not null then 'descanso_sustitutorio' end
    ) as motivo
  from tocaba tb
  left join lateral (
    select 1 as persona_id from jornadas j
    where j.persona_id = tb.persona_id and j.fecha = tb.fecha and j.entrada_ts is not null limit 1
  ) presente on true
  left join lateral (
    select 1 as persona_id from vacaciones vc
    where vc.persona_id = tb.persona_id and tb.fecha between vc.fecha_inicio and vc.fecha_fin limit 1
  ) v on true
  left join justificaciones_asistencia ju on ju.persona_id = tb.persona_id and ju.fecha = tb.fecha
  left join lateral (
    select 1 as persona_id from feriados_descanso_sustitutorio d
    where d.persona_id = tb.persona_id
      and d.fecha_descanso_sustitutorio = tb.fecha
      and d.estado in ('PENDIENTE', 'OTORGADO') limit 1
  ) ds on true
  -- ⇩ CAMBIO 0079: el día que se cumple una sanción no es una falta
  left join lateral (
    select 1 as es where fn_dia_suspendido(tb.persona_id, tb.fecha)
  ) sus on true
  left join lateral (
    select 1 as es from feriados f where f.fecha = tb.fecha limit 1
  ) fer on true
  where tb.trabaja
    and presente.persona_id is null                       -- no marcó = ausente
    and not (fer.es is not null and not tb.hay_turno)     -- feriado sin turno explícito: no cuenta
  order by tb.fecha desc, tb.nombre;
$$;

grant  execute on function fn_faltas(date, date) to authenticated;
revoke execute on function fn_faltas(date, date) from public, anon;


-- ── El semáforo legal ───────────────────────────────────────────────────────
-- Cuerpo idéntico al de la 0070 salvo la rama nueva en `sched`. Este es el que
-- de verdad importa: es el que dispara "posible causal — revisar".
create or replace function fn_faltas_resumen(p_as_of date default null)
returns table (persona_id uuid, nombre text, sede text, consecutivas int, en_30 int, en_180 int, nivel text)
language sql stable security definer set search_path = public
as $$
  with rango as (select greatest(coalesce(p_as_of, current_date) - 180, date '2026-01-01') as ini, coalesce(p_as_of, current_date) - 1 as fin),
  medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
           greatest((select ini from rango), pe.fecha_ingreso) as desde
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  dias as (
    select m.id as pid, gs::date as fecha
    from medibles m cross join lateral generate_series(m.desde, (select fin from rango), interval '1 day') gs
  ),
  ev as (
    select d.pid, d.fecha,
      (t.persona_id is not null) as hay_turno, coalesce(t.es_descanso, false) as turno_desc,
      tr.horario_por_dia as hpd, tr.dias_laborables as dl
    from dias d
    left join turnos t on t.persona_id = d.pid and t.fecha = d.fecha
    left join lateral (
      select h.horario_por_dia, h.dias_laborables from horarios_asignados h
      where h.persona_id = d.pid and h.vigente_desde <= d.fecha and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
      order by h.vigente_desde desc limit 1
    ) tr on true
  ),
  -- solo días PROGRAMADOS (le tocaba; feriado sin turno no cuenta), con su estado
  sched as (
    select ev.pid, ev.fecha,
      case
        when exists (select 1 from jornadas j where j.persona_id = ev.pid and j.fecha = ev.fecha and j.entrada_ts is not null) then 'presente'
        -- ⇩ CAMBIO 0079: cumplir la sanción no alimenta la sanción siguiente
        when fn_dia_suspendido(ev.pid, ev.fecha) then 'just'
        when exists (select 1 from vacaciones v where v.persona_id = ev.pid and ev.fecha between v.fecha_inicio and v.fecha_fin)
          or exists (select 1 from justificaciones_asistencia ju where ju.persona_id = ev.pid and ju.fecha = ev.fecha)
          or exists (select 1 from feriados_descanso_sustitutorio d
                     where d.persona_id = ev.pid and d.fecha_descanso_sustitutorio = ev.fecha
                       and d.estado in ('PENDIENTE', 'OTORGADO')) then 'just'
        else 'falta'
      end as estado
    from ev
    where (case when ev.hay_turno then not ev.turno_desc
                when ev.hpd is not null then (ev.hpd ? (extract(dow from ev.fecha)::int::text))
                when ev.dl is not null then (extract(dow from ev.fecha)::int = any(ev.dl))
                else false end)
      and not (exists (select 1 from feriados f where f.fecha = ev.fecha) and not ev.hay_turno)
  ),
  rn as (
    select pid, estado, row_number() over (partition by pid order by fecha desc) as rk from sched
  ),
  consec as (
    -- racha reciente de faltas: hasta el primer día no-falta desde el más reciente
    select pid, (coalesce(min(rk) filter (where estado <> 'falta'), max(rk) + 1) - 1) as consecutivas
    from rn group by pid
  ),
  faltas_dias as (
    select pid, fecha from sched where estado = 'falta'
  ),
  -- VENTANA MÓVIL: por cada día-falta, faltas en [d-29, d]; se queda el máximo
  c30 as (
    select pid, max(cnt) as n
    from (
      select a.pid, a.fecha, count(*) as cnt
      from faltas_dias a
      join faltas_dias b on b.pid = a.pid and b.fecha between a.fecha - 29 and a.fecha
      group by a.pid, a.fecha
    ) w
    group by pid
  ),
  c180 as (select pid, count(*) as n from sched where estado = 'falta' group by pid)
  select m.id, m.nombre, m.sede,
    coalesce(cc.consecutivas, 0)::int, coalesce(c30.n, 0)::int, coalesce(c180.n, 0)::int,
    case
      when coalesce(cc.consecutivas,0) > 3 or coalesce(c30.n,0) > 5 or coalesce(c180.n,0) > 15 then 'rojo'
      when coalesce(cc.consecutivas,0) = 3 or coalesce(c30.n,0) >= 4 or coalesce(c180.n,0) >= 12 then 'ambar'
      else 'verde'
    end as nivel
  from medibles m
  left join consec cc on cc.pid = m.id
  left join c30  on c30.pid  = m.id
  left join c180 on c180.pid = m.id
  where coalesce(cc.consecutivas,0) >= 3 or coalesce(c30.n,0) >= 4 or coalesce(c180.n,0) >= 12
  order by (case when coalesce(cc.consecutivas,0) > 3 or coalesce(c30.n,0) > 5 or coalesce(c180.n,0) > 15 then 1 else 2 end), m.nombre;
$$;

grant  execute on function fn_faltas_resumen(date) to authenticated;
revoke execute on function fn_faltas_resumen(date) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (79, 'suspension_no_es_falta')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- =========================================================================
-- >>>  0080_feriados_hasta_2032.sql
-- =========================================================================
-- ============================================================================
-- 0080 — Feriados hasta 2032, y un aviso para que no se vuelva a acabar
-- ----------------------------------------------------------------------------
-- PROMETE: que la planilla siga pagando los feriados correctamente hasta
--   diciembre de 2032, y que el sistema avise con meses de anticipación antes
--   de quedarse sin calendario.
--
-- EL DEFECTO. La tabla `feriados` se sembró en la 0024 solo con 2026. El motor
-- de planilla la consulta para dos cosas: pagar el día feriado a quien no
-- trabaja, y aplicar la sobretasa a quien sí lo trabaja. Un día que no está en
-- la tabla simplemente NO ES FERIADO para el sistema: no hay error, no hay
-- aviso, la planilla sale más baja y cuadra consigo misma.
--
-- El 1 de enero de 2027 eso habría pasado con Año Nuevo. Nadie lo habría
-- notado hasta que una colaboradora reclamara — y para entonces habría varias
-- planillas pagadas de menos.
--
-- POR QUÉ SEIS AÑOS Y NO UNO. Decisión de Felipe (26/07/2026): "¿qué pasa si
-- mañana yo no estoy?". Un año resuelve el próximo enero y devuelve el mismo
-- riesgo al siguiente diciembre, cuando puede que quien sepa de esto ya no
-- esté mirando. El calendario de feriados nacionales es estable; cargarlo
-- largo cuesta lo mismo que cargarlo corto.
--
-- LAS FECHAS MÓVILES NO SE ADIVINARON. Jueves y Viernes Santo dependen de la
-- Pascua, que se calculó con el algoritmo gregoriano de computus
-- (Meeus/Jones/Butcher) y se validó contra 2024, 2025 y 2026 — este último
-- coincide exactamente con lo ya sembrado en la 0024.
--
-- LO QUE ESTO NO CUBRE. Si el Congreso crea un feriado nuevo o declara un día
-- no laborable puntual, no aparece acá. Para eso está el aviso: la pantalla de
-- Feriados es editable, y ahora dice cuándo se está por acabar el calendario.
--
-- Reversible: `delete from feriados where fecha >= '2027-01-01'` y soltar la
-- función de aviso.
-- ============================================================================

insert into feriados (fecha, nombre) values
  ('2027-01-01', 'Año Nuevo'),
  ('2027-03-25', 'Jueves Santo'),
  ('2027-03-26', 'Viernes Santo'),
  ('2027-05-01', 'Día del Trabajo'),
  ('2027-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2027-06-29', 'San Pedro y San Pablo'),
  ('2027-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2027-07-28', 'Fiestas Patrias'),
  ('2027-07-29', 'Fiestas Patrias'),
  ('2027-08-06', 'Batalla de Junín'),
  ('2027-08-30', 'Santa Rosa de Lima'),
  ('2027-10-08', 'Combate de Angamos'),
  ('2027-11-01', 'Todos los Santos'),
  ('2027-12-08', 'Inmaculada Concepción'),
  ('2027-12-09', 'Batalla de Ayacucho'),
  ('2027-12-25', 'Navidad'),
  ('2028-01-01', 'Año Nuevo'),
  ('2028-04-13', 'Jueves Santo'),
  ('2028-04-14', 'Viernes Santo'),
  ('2028-05-01', 'Día del Trabajo'),
  ('2028-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2028-06-29', 'San Pedro y San Pablo'),
  ('2028-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2028-07-28', 'Fiestas Patrias'),
  ('2028-07-29', 'Fiestas Patrias'),
  ('2028-08-06', 'Batalla de Junín'),
  ('2028-08-30', 'Santa Rosa de Lima'),
  ('2028-10-08', 'Combate de Angamos'),
  ('2028-11-01', 'Todos los Santos'),
  ('2028-12-08', 'Inmaculada Concepción'),
  ('2028-12-09', 'Batalla de Ayacucho'),
  ('2028-12-25', 'Navidad'),
  ('2029-01-01', 'Año Nuevo'),
  ('2029-03-29', 'Jueves Santo'),
  ('2029-03-30', 'Viernes Santo'),
  ('2029-05-01', 'Día del Trabajo'),
  ('2029-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2029-06-29', 'San Pedro y San Pablo'),
  ('2029-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2029-07-28', 'Fiestas Patrias'),
  ('2029-07-29', 'Fiestas Patrias'),
  ('2029-08-06', 'Batalla de Junín'),
  ('2029-08-30', 'Santa Rosa de Lima'),
  ('2029-10-08', 'Combate de Angamos'),
  ('2029-11-01', 'Todos los Santos'),
  ('2029-12-08', 'Inmaculada Concepción'),
  ('2029-12-09', 'Batalla de Ayacucho'),
  ('2029-12-25', 'Navidad'),
  ('2030-01-01', 'Año Nuevo'),
  ('2030-04-18', 'Jueves Santo'),
  ('2030-04-19', 'Viernes Santo'),
  ('2030-05-01', 'Día del Trabajo'),
  ('2030-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2030-06-29', 'San Pedro y San Pablo'),
  ('2030-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2030-07-28', 'Fiestas Patrias'),
  ('2030-07-29', 'Fiestas Patrias'),
  ('2030-08-06', 'Batalla de Junín'),
  ('2030-08-30', 'Santa Rosa de Lima'),
  ('2030-10-08', 'Combate de Angamos'),
  ('2030-11-01', 'Todos los Santos'),
  ('2030-12-08', 'Inmaculada Concepción'),
  ('2030-12-09', 'Batalla de Ayacucho'),
  ('2030-12-25', 'Navidad'),
  ('2031-01-01', 'Año Nuevo'),
  ('2031-04-10', 'Jueves Santo'),
  ('2031-04-11', 'Viernes Santo'),
  ('2031-05-01', 'Día del Trabajo'),
  ('2031-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2031-06-29', 'San Pedro y San Pablo'),
  ('2031-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2031-07-28', 'Fiestas Patrias'),
  ('2031-07-29', 'Fiestas Patrias'),
  ('2031-08-06', 'Batalla de Junín'),
  ('2031-08-30', 'Santa Rosa de Lima'),
  ('2031-10-08', 'Combate de Angamos'),
  ('2031-11-01', 'Todos los Santos'),
  ('2031-12-08', 'Inmaculada Concepción'),
  ('2031-12-09', 'Batalla de Ayacucho'),
  ('2031-12-25', 'Navidad'),
  ('2032-01-01', 'Año Nuevo'),
  ('2032-03-25', 'Jueves Santo'),
  ('2032-03-26', 'Viernes Santo'),
  ('2032-05-01', 'Día del Trabajo'),
  ('2032-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2032-06-29', 'San Pedro y San Pablo'),
  ('2032-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2032-07-28', 'Fiestas Patrias'),
  ('2032-07-29', 'Fiestas Patrias'),
  ('2032-08-06', 'Batalla de Junín'),
  ('2032-08-30', 'Santa Rosa de Lima'),
  ('2032-10-08', 'Combate de Angamos'),
  ('2032-11-01', 'Todos los Santos'),
  ('2032-12-08', 'Inmaculada Concepción'),
  ('2032-12-09', 'Batalla de Ayacucho'),
  ('2032-12-25', 'Navidad')
on conflict (fecha) do nothing;

-- ── El aviso: cuánto calendario queda ───────────────────────────────────────
-- Devuelve hasta cuándo hay feriados cargados y si urge extender. Lo consume
-- la pantalla de Feriados; se prefiere una función a una consulta suelta para
-- que el criterio de "se está acabando" viva en un solo lugar.
create or replace function fn_feriados_cobertura()
returns table (ultimo_feriado date, meses_restantes int, nivel text, mensaje text)
language sql stable security definer set search_path = public as $$
  with u as (select max(fecha) as f from feriados),
       m as (select u.f,
                    (extract(year  from age(u.f, (now() at time zone 'America/Lima')::date)) * 12
                   + extract(month from age(u.f, (now() at time zone 'America/Lima')::date)))::int as meses
             from u)
  select m.f,
         m.meses,
         case when m.meses < 3 then 'rojo' when m.meses < 12 then 'ambar' else 'verde' end,
         case
           when m.f is null then 'No hay ningún feriado cargado: la planilla no está pagando feriados.'
           when m.meses < 3 then
             'Quedan menos de 3 meses de feriados cargados (hasta ' || to_char(m.f,'DD/MM/YYYY') ||
             '). Después de esa fecha la planilla dejará de pagar los feriados SIN avisar.'
           when m.meses < 12 then
             'Quedan ' || m.meses || ' meses de feriados cargados (hasta ' || to_char(m.f,'DD/MM/YYYY') || '). Conviene extender el calendario.'
           else
             'Calendario cargado hasta ' || to_char(m.f,'DD/MM/YYYY') || ' (' || m.meses || ' meses).'
         end
  from m;
$$;
grant  execute on function fn_feriados_cobertura() to authenticated;
revoke execute on function fn_feriados_cobertura() from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (80, 'feriados_hasta_2032')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- =========================================================================
-- COMPROBACIÓN — debe salir todo en verde
-- ============================================================================
select 'Funciones abiertas a cualquiera (debe ser 0 o 1 trigger)' as revision,
       count(*)::text as resultado
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and has_function_privilege('anon', p.oid, 'execute')
union all
select 'Migraciones registradas', count(*)::text from migraciones_aplicadas
union all
select 'Última migración aplicada', max(numero)::text from migraciones_aplicadas
union all
select 'Huecos en la numeración (debe decir: ninguno)',
       coalesce(string_agg(n::text, ', '), 'ninguno')
from (select generate_series(1, (select max(numero) from migraciones_aplicadas)) n
      except select numero from migraciones_aplicadas) q
union all
select 'Guard null-safe (debe decir: false, no vacío)',
       coalesce(fn_es_admin_o_lider()::text, '⚠️ SIGUE DEVOLVIENDO NULL')
union all
select 'Feriados cargados hasta', to_char(max(fecha), 'DD/MM/YYYY') from feriados;
