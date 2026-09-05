-- ============================================================================
-- 0383_la_foto_del_roster_entra_al_repositorio_y_la_regla_sigue_siendo_una.sql
-- ============================================================================
--
-- QUÉ PROMETE
--
--   1. Que `personas.foto_url` —que HOY existe en producción y en ningún
--      archivo de este repositorio— quede documentada acá, para que una
--      restauración de respaldo o un `supabase db reset` la reproduzcan.
--   2. Que `terminal_roster` vuelva a PREGUNTAR la regla de sede en vez de
--      llevarla copiada, conservando esa columna.
--
--   No cambia a quién ofrece el roster. Ni una persona entra ni sale: la copia
--   y `fn_persona_marca_en_sede` dicen exactamente lo mismo hoy. El problema no
--   es que difieran — es que puedan.
--
-- QUÉ ASUME
--   · La 0370: existe `fn_persona_marca_en_sede(uuid, uuid)` y `authenticated`
--     tiene su `execute`.
--   · Que la vista es la de la 0375 (cinco columnas, como queda tras un
--     `db reset` limpio) O la que hay hoy en producción (seis, con `foto_url`).
--     La guardia acepta las dos y rechaza cualquier otra.
--
-- ── POR QUÉ EXISTE, Y ES LO QUE HAY QUE ENTENDER ────────────────────────────
--
-- El 2026-09-05, al pegar la 0382, su guardia abortó sin aplicar nada:
--
--     PARA. terminal_roster no tiene las cinco columnas de la 0375.
--     Tiene: id,nombres,apellidos,foto_url,sede_codigo,sede_nombre.
--
-- Se midió entonces, y esto es lo que apareció:
--
--   · `personas.foto_url` (text) existe en producción y en el Postgres local
--     compartido. NO existe en ninguna migración de este repositorio ni en
--     ninguna rama del remoto (se buscó en las 40 ramas de `origin`; los
--     únicos aciertos son de la 0219, que es retail y su `foto_url` está en
--     otra tabla).
--   · Nada del código la lee: `apps/web/lib/terminal/roster.ts` sigue pidiendo
--     las cinco columnas, y un `grep` sobre `apps/` y `packages/` no devuelve
--     nada.
--
-- O sea: alguien está construyendo «fotos en el roster» en una rama sin
-- fusionar y ya lo aplicó a producción antes de fusionarlo. Eso es el
-- accidente de la 0177 al revés — entonces el archivo vivía solo en una Mac;
-- acá el cambio vive solo en producción, y no había dónde leer qué se hizo ni
-- cómo deshacerlo. En la vista que pinta el roster de las cuatro Mac mini.
--
-- Y de paso trajo la tercera aparición del mismo defecto: al recrear la vista
-- para meter la columna, su `where` se reescribió desde una versión vieja y la
-- copia de la regla de sede volvió. Van tres — la 0285, la 0375 y esta — y
-- siempre por el mismo mecanismo: cambiar columnas obliga a `drop` + `create`,
-- y quien lo hace copia el `where` de donde puede.
--
-- ── POR QUÉ SE ADOPTA LA COLUMNA EN VEZ DE QUITARLA ─────────────────────────
--
-- Decisión de Felipe, 2026-09-05. Quitarla rompería el trabajo de esa sesión
-- sin hablarlo; dejarla sin archivo mantiene a producción y al repositorio
-- diciendo cosas distintas, que es justo lo que hace que la próxima migración
-- de esta vista vuelva a chocar. Adoptarla es lo único que cierra la brecha.
--
-- Todo lo de acá es idempotente a propósito: `add column if not exists` y una
-- vista que se recrea. Cuando esa sesión suba su propia migración, aplicarla
-- después de esta no rompe nada — y si la suya llega primero, esta tampoco.
-- Es la salida que no obliga a nadie a esperar al otro.
--
-- ── POR QUÉ `drop` + `create` Y NO `create or replace` ──────────────────────
--
-- Porque `create or replace view` no deja cambiar la lista de columnas, y acá
-- cambia en el camino que importa: tras un `db reset` limpio la vista tiene
-- cinco (la deja la 0382) y esta migración la lleva a seis. El `drop` se lleva
-- los permisos, así que se reponen abajo — es exactamente la línea que se
-- olvida y por la que una sede se queda sin roster.
--
-- ── LO QUE NO CAMBIA ────────────────────────────────────────────────────────
--
-- El candado de sede no depende de esto. Vive en `trg_marcaje_sede_permitida`
-- y en `fn_persona_marca_en_sede`, y ninguna de las tres recreaciones de la
-- vista los tocó: entre la primera copia y hoy no entró ni una marca de otra
-- sede. Esto es higiene.
--
-- Tampoco hace falta tocar el frontend. `roster.ts` nombra sus cinco columnas
-- una por una, así que una sexta en la vista le es indiferente — comprobado
-- contra `origin/main`.
--
-- CÓMO SE REVIERTE
--   Volver a pegar el bloque `create view terminal_roster` de la 0382 (cinco
--   columnas, delegando) y `alter table personas drop column if exists
--   foto_url`. Ojo: eso segundo borra los datos que la columna tenga.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final, y la prueba 302 — que se AMPLÍA en vez de duplicarse:
--   una segunda prueba interrogando la misma vista sería otra copia de la
--   misma pregunta, que es el defecto que esta migración viene a cerrar.
--
-- Idempotente: se puede pegar dos veces sin peligro.
-- ============================================================================


-- ── 0 · Comprobar ANTES de tocar nada ───────────────────────────────────────
do $guardia$
declare
  v_cols text;
  v_opts text;
  v_md5  text;
  v_len  int;
  -- `to_regclass` y no `'…'::regclass`: el cast LANZA si la vista no existe, y
  -- lo hace antes de que se pueda comprobar nada. Con él, la comprobación de
  -- «no existe» de más abajo era código muerto y el desenlace era un error
  -- crudo de Postgres en vez de la frase que dice qué pegar primero.
  v_vista oid := to_regclass('public.terminal_roster');
begin
  -- 1 · La función que va a responder la regla. BLOQUEA.
  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_persona_marca_en_sede';

  if v_md5 is null then
    raise exception using
      message = 'FALTA LA 0370. fn_persona_marca_en_sede no existe.',
      hint    = 'Pega la 0370 antes que esta. Sin esa función, el roster de las cuatro '
             || 'Mac mini devolvería un error en vez de una lista.';
  end if;

  if v_md5 <> '8348cdf1ca03edc9a7eecc5bc7dbd09b' then
    raise exception using
      message = 'PARA. fn_persona_marca_en_sede no es la de la 0370. md5 encontrado: '
             || v_md5 || ' (' || v_len || ' caracteres). Se esperaba '
             || '8348cdf1ca03edc9a7eecc5bc7dbd09b (187).',
      hint    = 'Alguien la reescribió. Esta migración le ata una pantalla de producción, '
             || 'así que hay que saber qué dice antes. Corre ./scripts/donde-vive.sh '
             || 'fn_persona_marca_en_sede.';
  end if;

  -- 2 · La vista. Se aceptan DOS formas, y ninguna más.
  --     Las dos existen de verdad: la de cinco es la que deja un `db reset`
  --     limpio (la 0382) y la que corre en CI; la de seis es la que hay hoy en
  --     producción. Una migración que solo aceptara una de las dos sería roja
  --     en CI o inaplicable en producción, según cuál eligiera.
  if v_vista is null then
    raise exception using
      message = 'FALTA LA 0285 (o la 0375, o la 0382). La vista terminal_roster no existe.',
      hint    = 'Esta migración la REESCRIBE; no la crea desde cero a propósito, para no '
             || 'plantar en producción una versión que nadie revisó.';
  end if;

  select string_agg(attname, ',' order by attnum) into v_cols
    from pg_attribute
   where attrelid = v_vista and attnum > 0 and not attisdropped;

  if v_cols not in ('id,nombres,apellidos,sede_codigo,sede_nombre',
                    'id,nombres,apellidos,foto_url,sede_codigo,sede_nombre') then
    raise exception using
      message = 'PARA. terminal_roster no es ninguna de las dos formas conocidas. Tiene: '
             || v_cols || '.',
      hint    = case
                  when position('pin_hash' in v_cols) > 0
                    then 'Todavía lleva pin_hash: falta pegar la 0375, que lo quita. Pégala '
                      || 'primero — si no, esta migración devolvería el hash al navegador.'
                  else 'Alguien le cambió las columnas otra vez, y sin archivo en el repo. '
                    || 'Mídelo con pg_get_viewdef antes de seguir; no lo supongas.'
                end;
  end if;

  -- 3 · `security_invoker = false` es lo que deja a la vista saltarse la RLS de
  --     `personas`. Con `true`, el terminal recibe cero filas y la sede se queda
  --     de pie sin que nada dé error.
  select array_to_string(reloptions, ',') into v_opts
    from pg_class where oid = v_vista;

  if coalesce(v_opts, '') not like '%security_invoker=false%' then
    raise exception using
      message = 'PARA. terminal_roster ya no es security_invoker = false. Opciones: '
             || coalesce(v_opts, '(ninguna)') || '.',
      hint    = 'Alguien cambió cómo la vista resuelve permisos. Revísalo antes: con '
             || '`true` el terminal recibe cero filas y no da ningún error.';
  end if;

  -- Reconocer el propio trabajo pide las DOS cosas, no una. Tras un `db reset`
  -- limpio la vista YA delega —eso lo dejó la 0382— y no tiene `foto_url`: con
  -- solo mirar la delegación, esta migración anunciaría «ya estaba aplicada»
  -- en el camino donde más trabajo hace. Un mensaje que miente enseña a no
  -- leer los mensajes.
  if position('fn_persona_marca_en_sede' in pg_get_viewdef(v_vista, true)) > 0
     and position('foto_url' in v_cols) > 0 then
    raise notice 'La 0383 ya estaba aplicada (el roster lleva foto_url y delega la regla '
                 'de sede). Se vuelve a aplicar sin daño.';
  end if;
end
$guardia$;


-- ── 1 · La columna entra al repositorio ─────────────────────────────────────
-- `if not exists` y `text` sin default: es exactamente lo que hay hoy en
-- producción (comprobado en `information_schema.columns`), así que pegarlo allá
-- no toca ni una fila. Donde de verdad hace efecto es en un `db reset` limpio y
-- en CI, que hasta ahora no la tenían.
--
-- No lleva `not null` ni default a propósito: `null` significa «esta persona no
-- tiene foto», que es el estado de casi todas.
alter table personas add column if not exists foto_url text;

comment on column personas.foto_url is
  'Foto de la persona para el roster del terminal. Se encontró EN PRODUCCIÓN el 2026-09-05 sin '
  'ninguna migración que la creara (ver el encabezado de la 0383): esta migración la documenta '
  'para que un restore o un db reset la reproduzcan. Nullable a propósito — null es «sin foto».';


-- ── 2 · El roster deja de llevar su propia copia de la regla ────────────────
--
-- Las seis columnas de producción, con `foto_url` en su sitio. Lo único que
-- cambia respecto de lo que hay allá es que la condición de sede ya no está
-- escrita acá: se le pregunta a quien la responde para todo lo demás.
--
-- `estado = 'activo'` y el freno de `fn_sede_actual_terminal() is not null` se
-- quedan en la vista a propósito, y no se meten en la función:
--
--   · `fn_persona_marca_en_sede` responde SOLO por la sede. Que la persona esté
--     activa lo mira el roster (para no ofrecerla) y el cese lo mira
--     `trg_marcaje_no_posterior_al_cese` por FECHA (0086), que es más preciso:
--     una marca del lunes entregada tarde por la cola offline —después de que
--     esa persona cesara el martes— tiene que seguir entrando. Fundir las dos
--     preguntas rompería ese caso.
--   · El `is not null` es el freno de la propia vista: sin sesión de terminal
--     no se devuelve NADA. Si viviera dentro de la función, el disparador de
--     escritura —que corre sin sesión de terminal— dejaría de autorizar a nadie.
drop view if exists terminal_roster;

create view terminal_roster
with (security_invoker = false)
as
select
  p.id,
  p.nombres,
  p.apellidos,
  p.foto_url,
  s.codigo as sede_codigo,
  s.nombre  as sede_nombre
from personas p
join sedes s on s.id = p.sede_base_id
where p.estado = 'activo'
  and fn_sede_actual_terminal() is not null
  and fn_persona_marca_en_sede(p.id, fn_sede_actual_terminal());

comment on view terminal_roster is
  'Lo unico que el kiosco de marcaje necesita ver de una persona: como se llama, de que sede es y '
  'su foto. Existe porque RLS filtra filas y no columnas, asi que mientras el terminal leyera '
  '`personas` su token alcanzaba el DNI y la remuneracion (0285). Desde la 0375 no lleva `pin_hash`: '
  'el terminal ya no pide PIN. Desde la 0383 lleva `foto_url` y su condicion de sede la responde '
  'fn_persona_marca_en_sede — la misma que usan el disparador de escritura y '
  'fn_persona_en_roster_terminal, para que la regla no vuelva a tener dos copias que puedan separarse.';

-- El `drop` se llevó los permisos. Reponerlos NO es opcional: sin el `select`,
-- las cuatro Mac mini reciben «permission denied» al pintar su lista.
revoke all    on terminal_roster from public, anon;
grant  select on terminal_roster to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (383, 'la_foto_del_roster_entra_al_repositorio_y_la_regla_sigue_siendo_una')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── Comprobación ────────────────────────────────────────────────────────────
-- `delega` y `sin_copia_inline` son las que importan: son lo que la prueba 293
-- no miraba y por lo que esto pasó tres veces sin que nadie lo viera.
select
  (select count(*) from information_schema.columns
    where table_name = 'personas' and column_name = 'foto_url')                as columna_documentada,
  (select string_agg(attname, ',' order by attnum) from pg_attribute
    where attrelid = 'public.terminal_roster'::regclass
      and attnum > 0 and not attisdropped)                                     as columnas,
  position('fn_persona_marca_en_sede' in
           pg_get_viewdef('public.terminal_roster'::regclass, true)) > 0       as delega,
  position('visible_todas_sedes' in
           pg_get_viewdef('public.terminal_roster'::regclass, true)) = 0       as sin_copia_inline,
  position('pin_hash' in
           pg_get_viewdef('public.terminal_roster'::regclass, true)) = 0       as sin_pin_hash,
  has_table_privilege('authenticated', 'public.terminal_roster', 'select')     as terminal_puede_leerla;
