-- ============================================================================
-- 0364 — El PIN nace en el servidor
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que regenerar el PIN de una integrante sea una operación del
-- servidor con su propio permiso —`fn_regenerar_pin(p_persona_id)`— y que
-- `personas.pin_hash` deje de poder escribirse desde el navegador por REST.
-- El PIN se genera con pgcrypto, se hashea con bcrypt ahí mismo y se devuelve
-- UNA sola vez, exactamente como hoy lo muestra la pantalla de Equipo.
--
-- EL DEFECTO (hallazgo 22 de la auditoría del 2026-09-03/04): «Nuevo PIN» en
-- /admin/equipo generaba los 4 dígitos en el navegador, calculaba el bcrypt
-- ahí mismo y hacía `supabase.from("personas").update({ pin_hash })` — sin
-- RPC y sin ningún chequeo propio. Lo único que frenaba esa escritura era la
-- RLS `personas_update_admin_lider` (0003). El día que esa regla se relajara
-- por cualquier otro motivo —una columna nueva que una encargada tiene que
-- poder editar, por ejemplo— cualquier cuenta con sesión podría cambiarle el
-- PIN a cualquiera, y el PIN es lo que el terminal de la sede reconoce al
-- marcar. Un permiso que depende de que OTRA regla no cambie no es un
-- permiso: es una coincidencia.
--
-- QUÉ ASUME:
--   · pgcrypto instalado (0001). La 0001 lo crea sin `with schema`, así que
--     dónde vive lo decide la imagen de Postgres: en Supabase —local y
--     hosted— cae en `extensions`, NO en `public`. Se midió antes de escribir
--     esto: con `set search_path = public` y sin calificar, `gen_salt` no
--     resuelve —«function gen_salt(unknown, integer) does not exist»— y la
--     función revienta al primer uso. Y ese uso NO es el pegado: la migración
--     entraría limpia y el error saldría al primer clic en «Nuevo PIN».
--     Por eso la función declara `search_path = public, extensions` y llama a
--     `crypt`, `gen_salt` y `gen_random_bytes` sin calificar: resuelven igual
--     si pgcrypto está en `extensions` o si en producción estuviera en
--     `public`. Incluir `extensions` en el search_path de un `security
--     definer` es seguro: en ese esquema solo `postgres` puede crear objetos
--     (medido en `pg_namespace.nspacl`), así que nadie puede colarle una
--     función homónima. La comprobación de abajo dice además en qué esquema
--     quedó pgcrypto, para que se vea al pegar y no al usar.
--   · `gen_salt('bf', 10)` produce un hash `$2a$10$…`, que es el mismo
--     formato que hoy escribe bcryptjs desde el navegador y que
--     `apps/web/lib/terminal/pin.ts` compara con `bcryptjs.compare`. Se
--     comprobó de punta a punta: un hash hecho acá compara `true` en Node con
--     la bcryptjs del proyecto. Si esa compatibilidad se rompiera, el terminal
--     dejaría de reconocer los PIN regenerados — y no fallaría al pegar esto,
--     fallaría al marcar.
--   · Quien regenera es admin o lider_do: `fn_es_admin_o_lider()`, que es
--     EXACTAMENTE la condición de la RLS que hoy gobierna esa escritura. No se
--     amplía a `supervisor_sede`: esta migración cambia la puerta, no quién
--     pasa por ella.
--
-- POR QUÉ SE ELIGIÓ ASÍ:
--   · El RPC corre `security definer`: mientras ejecuta, `current_user` es la
--     dueña de la función (`postgres`), no la sesión que la llamó. Un UPDATE
--     directo desde PostgREST corre como `authenticated`. El trigger de abajo
--     distingue exactamente eso — mismo mecanismo que `fn_bloquear_rol_directo`
--     (0296) y `fn_bloquear_sede_directa` (0342). Aquellos comparan contra
--     `<> 'postgres'`; este cierra por lista (`in ('authenticated', 'anon')`)
--     porque son los dos roles con los que llega el navegador, y son los dos
--     que no tienen por qué escribir un hash jamás.
--   · El candado es `before update OF pin_hash`: solo se evalúa cuando el
--     UPDATE toca esa columna. Crear personas —`fn_crear_persona`, que todavía
--     recibe el hash del navegador; esa es la deuda del hallazgo crítico 1 y
--     queda FUERA de esta migración— es un INSERT y no lo ve. Editar nombres,
--     correo o cualquier otro campo tampoco lo dispara.
--   · Se devuelve el PIN en claro UNA vez, como respuesta del RPC, y no se
--     guarda en ningún lado más que como hash. Igual que hoy.
--   · Los 4 dígitos salen de `gen_random_bytes(4)` leído como entero sin signo
--     (`::bit(32)::bigint`, que va de 0 a 4 294 967 295) módulo 10 000. Va a
--     bigint y no a int a propósito: como int el bit más alto lo vuelve
--     negativo y `abs(-2147483648)` desborda — una vez cada cuatro mil
--     millones, que es exactamente la clase de error que nadie reproduce.
--
-- QUÉ NO CAMBIA: `fn_crear_persona` (sigue recibiendo `p_pin_hash`), la
-- validación del PIN en el terminal (`pin.ts`, bcryptjs en el navegador —
-- hallazgo crítico 1, fuera de alcance), la RLS de `personas`, y ningún hash
-- ya guardado: a nadie se le regenera nada por pegar esto.
--
-- SE REVIERTE:
--   drop trigger if exists trg_personas_pin_solo_por_rpc on personas;
--   drop function if exists fn_trg_pin_solo_por_rpc();
--   drop function if exists fn_regenerar_pin(uuid);
-- …y la pantalla vuelve al update directo (git revert del commit).
--
-- Función NUEVA: `donde-vive.sh fn_regenerar_pin` y `fn_trg_pin_solo_por_rpc`
-- confirmaron el 2026-09-04 que ninguna migración ni rama las definía. Antes
-- de pegar en el SQL Editor, vuelve a preguntarlo: varias sesiones trabajan
-- sobre el mismo árbol.
-- ============================================================================

-- ── 1 · La puerta: fn_regenerar_pin ──────────────────────────────────────────
create or replace function fn_regenerar_pin(p_persona_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  v_estado text;
  v_pin    text;
begin
  -- Espeja la RLS `personas_update_admin_lider` (0003), que es la única
  -- condición que hoy gobierna esta escritura. `is not true` y no `not`: un
  -- null nunca pasa como autorizado.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede regenerar un PIN.';
  end if;

  select estado into v_estado from personas where id = p_persona_id;
  if v_estado is null then
    raise exception 'No existe ninguna persona con ese id.';
  end if;
  if v_estado <> 'activo' then
    raise exception 'Esa persona está inactiva: no necesita PIN. Si vuelve al equipo, reactívala primero.';
  end if;

  -- Cuatro dígitos, con ceros a la izquierda ('0042' es un PIN válido).
  v_pin := lpad(
    ((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 10000)::text,
    4, '0');

  -- bcrypt con factor 10: '$2a$10$…', el mismo formato que bcryptjs.
  update personas
     set pin_hash = crypt(v_pin, gen_salt('bf', 10))
   where id = p_persona_id;

  return v_pin;
end;
$function$;

grant execute on function fn_regenerar_pin(uuid) to authenticated;
revoke execute on function fn_regenerar_pin(uuid) from public, anon;

-- ── 2 · El candado: pin_hash no se escribe desde el navegador ───────────────
-- `fn_regenerar_pin` corre `security definer`, así que mientras ejecuta
-- `current_user` es `postgres` y este trigger la deja pasar. Un UPDATE que
-- llega por PostgREST corre como `authenticated` (con sesión) o `anon` (sin
-- ella): a esos dos se les cierra, aunque la RLS los dejara pasar.
--
-- Es `before update OF pin_hash`: un INSERT (fn_crear_persona) o un UPDATE
-- de otras columnas ni siquiera lo evalúan.
create or replace function fn_trg_pin_solo_por_rpc()
returns trigger
language plpgsql
as $function$
begin
  if new.pin_hash is distinct from old.pin_hash
     and current_user in ('authenticated', 'anon') then
    raise exception 'El PIN no se escribe desde el navegador: usa fn_regenerar_pin.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_personas_pin_solo_por_rpc on personas;
create trigger trg_personas_pin_solo_por_rpc
  before update of pin_hash on personas
  for each row
  execute function fn_trg_pin_solo_por_rpc();

insert into migraciones_aplicadas (numero, nombre)
values (364, 'el_pin_nace_en_el_servidor')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
-- Las tres primeras columnas tienen que decir true / true / 1. La cuarta dice
-- en qué esquema vive pgcrypto (`extensions` en Supabase); la función lo
-- encuentra en `extensions` o en `public`, pero si dijera OTRA cosa o null,
-- «Nuevo PIN» fallaría al primer clic — y esta es la única línea que lo avisa
-- antes. La quinta genera un hash de verdad con la misma cadena que usa la
-- función (con el search_path de la sesión, que en el SQL Editor y en psql
-- de Supabase ya incluye `extensions`): tiene que decir 60, el largo de un
-- '$2a$10$…' — el formato que compara bcryptjs en el terminal.
select
  exists (select 1 from pg_proc where proname = 'fn_regenerar_pin')            as existe_la_puerta,
  exists (select 1 from pg_trigger
           where tgname = 'trg_personas_pin_solo_por_rpc'
             and tgrelid = 'personas'::regclass)                               as existe_el_candado,
  (select count(*) from pg_proc where proname = 'fn_regenerar_pin')            as una_sola_version,
  (select extnamespace::regnamespace::text from pg_extension
    where extname = 'pgcrypto')                                                as pgcrypto_en,
  length(crypt('0000', gen_salt('bf', 10)))                                    as largo_del_hash;
