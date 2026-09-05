-- ============================================================================
-- 0382_el_roster_vuelve_a_preguntar_la_regla_en_vez_de_copiarla.sql
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que «esta persona puede marcar en esta sede» vuelva a tener UNA sola
--   respuesta. Hoy hay dos: `fn_persona_marca_en_sede` (0370), que es la que
--   usan el disparador de escritura y la función que lee las marcas del día, y
--   una copia escrita a mano dentro de la vista `terminal_roster` (0375).
--
--   No cambia a quién ofrece el roster. Ni una persona entra ni sale por esta
--   migración: la copia y la función dicen exactamente lo mismo HOY. De eso se
--   trata — el problema no es que difieran, es que puedan.
--
-- QUÉ ASUME
--
--   · La 0370: existe `fn_persona_marca_en_sede(uuid, uuid)`, es la que
--     responde la regla, y `authenticated` tiene su `execute`.
--   · La 0381: `terminal_roster` tiene SEIS columnas —las cinco de la 0375
--     más `foto_url`, en cuarta posición— y `security_invoker = false`.
--   Las dos están aplicadas en producción (confirmado el 2026-09-05:
--   `migraciones_aplicadas` lista 370, 371, 375 y 381, y el roster devuelve
--   `id,nombres,apellidos,foto_url,sede_codigo,sede_nombre`).
--
-- ⚠️ CORREGIDA EL 2026-09-05, ANTES DE PEGARSE NUNCA EN PRODUCCIÓN
--
--   Esta migración se escribió asumiendo las CINCO columnas de la 0375, que
--   era el estado que su rama conocía. Mientras tanto, en otra rama, la 0381
--   («cada quien sube su foto») le agregó `foto_url` a esta misma vista con un
--   `drop view` + `create view` — y se pegó en producción primero.
--
--   O sea: el mismo accidente que esta migración documenta más abajo
--   (0370 → 0375), una tercera vez, y esta vez en las dos direcciones. La
--   0381 se llevó por delante la delegación de sede al reescribir el `where`
--   desde el cuerpo de la 0375; y este archivo, tal como estaba escrito,
--   habría fallado en seco en cualquier reconstrucción del esquema desde cero
--   —CI, `supabase db reset`, restaurar un backup— porque
--   `create or replace view` no deja quitar ni reordenar columnas y, para
--   cuando le toca el turno, `foto_url` ya está puesta por la 0381.
--
--   Se corrige el cuerpo en vez de agregar una migración de parche encima
--   porque NUNCA llegó a aplicarse con éxito en producción: el estado real de
--   hoy (seis columnas, sin delegación) es incompatible con que este archivo
--   haya corrido allí alguna vez. Sin estado persistente que dependa de su
--   forma anterior, corregirlo respeta la regla de la casa —a una migración
--   ya aplicada no se le cambia el cuerpo— en vez de violarla.
--
--   Lo único que cambia respecto de la versión original: la lista de columnas
--   incluye `p.foto_url`. La delegación de sede, el `security_invoker`, los
--   permisos y las guardias son las mismas.
--
-- ── CÓMO SE PERDIÓ, QUE ES LO QUE HAY QUE ENTENDER ──────────────────────────
--
-- La 0370 quitó las DOS copias que había de esa condición —la de la vista
-- (0285) y la de `fn_persona_en_roster_terminal` (0241), que para entonces ya
-- habían divergido entre sí en el `is not true`— y las hizo preguntar a una
-- función. La 0375, escrita el mismo día en otra rama para un fin distinto
-- (que el kiosco deje de descargar `pin_hash`), tuvo que cambiar la lista de
-- columnas de la vista. Y como `create or replace view` no deja cambiar
-- columnas, hizo `drop view` + `create view` — reescribiendo el `where` desde
-- la 0285, con la condición otra vez a mano. Su propio comentario lo dice sin
-- saberlo: «Copiada LITERAL de personas_select_terminal_roster (0008)».
--
-- Nadie hizo nada mal. Las dos migraciones eran correctas por separado, se
-- fusionaron a `main` con las pruebas en verde, y se pegaron en producción en
-- el orden bueno. Lo que falló es que NADA lo notó:
--
--   · `main` quedó en verde. La prueba 293, que defiende la 0370, comprueba
--     que la vista ofrece a la MISMA gente después de delegar — y eso sigue
--     siendo cierto con la copia inline, porque la copia dice lo mismo. Medía
--     el resultado, no la estructura.
--   · El hook `main-tiene-migraciones-que-no-tienes.sh` avisa cuando `main`
--     trae una migración que toca tus mismas FUNCIONES. Una vista no es una
--     función.
--
-- Por eso esta migración trae su prueba (302) con una aserción sobre la
-- DEFINICIÓN de la vista, no sobre a quién devuelve. Es la única forma de que
-- el próximo `drop view` + `create view` —que va a ocurrir, porque cambiar
-- columnas obliga a él— no vuelva a pasar en silencio.
--
-- ── POR QUÉ `create or replace` Y NO `drop` + `create` ──────────────────────
--
-- Porque no se toca la lista de columnas: son las cinco de la 0375, en el
-- mismo orden. `create or replace view` conserva los permisos; el `drop` se
-- los lleva y obliga a reponerlos, que es una línea más que alguien puede
-- olvidar. La 0375 tuvo que hacer `drop` porque quitaba `pin_hash`; aquí no
-- hay ninguna razón para pagar ese costo.
--
-- Los `revoke`/`grant` de abajo van igual, y son deliberadamente redundantes:
-- si algún día alguien convierte esto en un `drop` + `create`, los permisos ya
-- están escritos al lado y no dependen de que se acuerde.
--
-- ── LO QUE NO CAMBIA, Y CONVIENE DECIRLO ────────────────────────────────────
--
-- El candado de sede NO depende de esta migración. Vive en el disparador
-- `trg_marcaje_sede_permitida` y en `fn_persona_marca_en_sede`, y la 0375
-- nunca los tocó: entre que se perdió la delegación y hoy, ni una marca de
-- otra sede pudo entrar. Esto es higiene, no un arreglo de seguridad. Se hace
-- ahora porque el día que alguien cambie la regla —agregar una sede física,
-- por ejemplo— va a cambiar la función y no la copia, y ahí sí se separan.
--
-- CÓMO SE REVIERTE
--   Volver a pegar el bloque `create view terminal_roster` de la 0375 (que
--   trae la condición escrita a mano). No hay datos que restaurar: una vista
--   no guarda nada.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final, y la prueba 302.
--
-- Idempotente: se puede pegar dos veces sin peligro.
-- ============================================================================


-- ── 0 · Comprobar ANTES de tocar nada ───────────────────────────────────────
-- Mismo patrón que la 0370 y la 0371. Si el terreno no es el que esta
-- migración asume, no se aplica NADA.
do $guardia$
declare
  v_cols  text;
  v_opts  text;
  v_def   text;
  v_md5   text;
  v_len   int;
begin
  -- 1 · La función que va a responder la regla. BLOQUEA.
  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_persona_marca_en_sede';

  if v_md5 is null then
    raise exception using
      message = 'FALTA LA 0370. fn_persona_marca_en_sede no existe.',
      hint    = 'Pega la 0370 antes que esta. Sin esa función, esta vista se quedaría '
             || 'preguntándole a algo que no está y el roster de las cuatro Mac mini '
             || 'devolvería un error en vez de una lista.';
  end if;

  if v_md5 <> '8348cdf1ca03edc9a7eecc5bc7dbd09b' then
    raise exception using
      message = 'PARA. fn_persona_marca_en_sede no es la de la 0370. md5 encontrado: '
             || v_md5 || ' (' || v_len || ' caracteres). Se esperaba '
             || '8348cdf1ca03edc9a7eecc5bc7dbd09b (187).',
      hint    = 'Alguien la reescribió. Esta migración hace que el roster dependa de ella, '
             || 'así que hay que saber qué dice antes de atarle una pantalla de producción. '
             || 'Corre ./scripts/donde-vive.sh fn_persona_marca_en_sede.';
  end if;

  -- 2 · La vista. Sus columnas tienen que ser las CINCO de la 0375. BLOQUEA.
  --     Se comprueban propiedades y no un md5 de `pg_get_viewdef`: esa función
  --     reformatea según la versión de Postgres, así que un md5 daría falsas
  --     alarmas entre local y producción sin haber cambiado nada.
  select string_agg(attname, ',' order by attnum) into v_cols
    from pg_attribute
   where attrelid = 'public.terminal_roster'::regclass
     and attnum > 0 and not attisdropped;

  if v_cols is null then
    raise exception using
      message = 'FALTA LA 0381 (o la 0375/0285). La vista terminal_roster no existe.',
      hint    = 'Esta migración la REESCRIBE; no la crea desde cero a propósito, para no '
             || 'plantar en producción una versión que nadie revisó.';
  end if;

  if v_cols <> 'id,nombres,apellidos,foto_url,sede_codigo,sede_nombre' then
    raise exception using
      message = 'PARA. terminal_roster no tiene las seis columnas de la 0381. Tiene: '
             || v_cols || '.',
      hint    = case
                  when position('pin_hash' in v_cols) > 0
                    then 'Todavía lleva pin_hash: falta pegar la 0375, que lo quita. Pégala '
                      || 'primero — si no, esta migración devolvería el hash al navegador.'
                  when position('foto_url' in v_cols) = 0
                    then 'Le falta foto_url: falta pegar la 0381, que la agrega. Pégala primero '
                      || '— si no, esta migración dejaría al terminal sin las fotos que esa '
                      || 'pantalla ya espera.'
                  else 'Producción tiene otra vista. Pegar esto la reemplazaría, y es la que '
                    || 'pinta el roster de las cuatro Mac mini.'
                end;
  end if;

  -- 3 · `security_invoker = false` es lo que hace que la vista se salte la RLS
  --     de `personas` y pueda devolver el roster al terminal. Si alguien lo
  --     cambió, esta migración lo dejaría igual y hay que saberlo.
  select array_to_string(reloptions, ',') into v_opts
    from pg_class where oid = 'public.terminal_roster'::regclass;

  if coalesce(v_opts, '') not like '%security_invoker=false%' then
    raise exception using
      message = 'PARA. terminal_roster ya no es security_invoker = false. Opciones: '
             || coalesce(v_opts, '(ninguna)') || '.',
      hint    = 'Alguien cambió cómo la vista resuelve permisos. Esta migración la reescribe '
             || 'asumiendo lo de la 0285/0375; revísalo antes.';
  end if;

  -- 4 · ¿Ya está aplicada? Se detecta por CÓDIGO, no por un comentario: un
  --     comentario se pierde si el cuerpo se pega sin comentarios.
  v_def := pg_get_viewdef('public.terminal_roster'::regclass, true);
  if position('fn_persona_marca_en_sede' in v_def) > 0 then
    raise notice 'La 0382 ya estaba aplicada (el roster ya delega la regla de sede). '
                 'Se vuelve a aplicar sin daño.';
  end if;
end
$guardia$;


-- ── 1 · El roster deja de llevar su propia copia de la regla ────────────────
--
-- Las mismas seis columnas de la 0381, en el mismo orden, con el mismo
-- `security_invoker`. Lo único que cambia es que la condición de sede ya no
-- está escrita aquí: se le pregunta a quien la responde para todo lo demás.
--
-- `estado = 'activo'` y el freno de `fn_sede_actual_terminal() is not null` se
-- quedan en la vista a propósito, y no se meten en la función:
--
--   · `fn_persona_marca_en_sede` responde SOLO por la sede. Que la persona esté
--     activa lo mira el roster (para no ofrecerla) y el cese lo mira
--     `trg_marcaje_no_posterior_al_cese` por FECHA (0086), que es más preciso:
--     una marca del lunes entregada tarde por la cola offline —después de que
--     esa persona cesara el martes— tiene que seguir entrando. Fundir las dos
--     preguntas en una función rompería ese caso.
--   · El `is not null` es el freno de la propia vista: sin sesión de terminal
--     no se devuelve NADA. Si viviera dentro de la función, el disparador de
--     escritura —que corre sin sesión de terminal— dejaría de autorizar a
--     nadie. Son dos preguntas distintas y por eso viven en dos sitios.
create or replace view terminal_roster
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
  'Lo unico que el kiosco de marcaje necesita ver de una persona: como se llama, su foto (0381) y de '
  'que sede es. Existe porque RLS filtra filas y no columnas, asi que mientras el terminal leyera '
  '`personas` su token alcanzaba el DNI y la remuneracion (0285). Desde la 0375 tampoco lleva '
  '`pin_hash`: el terminal ya no pide PIN. Desde la 0382 su condicion de sede la responde '
  'fn_persona_marca_en_sede, la misma que usan el disparador de escritura y '
  'fn_persona_en_roster_terminal — para que la regla no vuelva a tener dos copias que puedan separarse.';

-- Redundantes a propósito: `create or replace view` los conserva, pero si algún
-- día esto se convierte en `drop` + `create` —lo obliga cualquier cambio de
-- columnas— ya están escritos al lado.
revoke all    on terminal_roster from public, anon;
grant  select on terminal_roster to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (382, 'el_roster_vuelve_a_preguntar_la_regla_en_vez_de_copiarla')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── Comprobación ────────────────────────────────────────────────────────────
-- `delega` es la que importa: es lo que la prueba 293 no miraba y por eso la
-- regresión pasó sin que nadie la viera.
select
  (select string_agg(attname, ',' order by attnum) from pg_attribute
    where attrelid = 'public.terminal_roster'::regclass
      and attnum > 0 and not attisdropped)                                    as columnas,
  position('fn_persona_marca_en_sede' in
           pg_get_viewdef('public.terminal_roster'::regclass, true)) > 0      as delega,
  position('visible_todas_sedes' in
           pg_get_viewdef('public.terminal_roster'::regclass, true)) = 0      as sin_copia_inline,
  (select array_to_string(reloptions, ',') from pg_class
    where oid = 'public.terminal_roster'::regclass)                           as opciones,
  has_table_privilege('authenticated', 'public.terminal_roster', 'select')    as terminal_puede_leerla;
