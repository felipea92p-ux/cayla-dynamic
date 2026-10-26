-- ============================================================================
-- 0550 · Una alerta solo se marca leída; todo lo demás lo mueve el despacho
-- ============================================================================
--
-- ── QUÉ PASÓ ────────────────────────────────────────────────────────────────
--
-- El 2026-10-25, al revisar la 0548, un revisor midió un hueco que viene de la
-- 0003: la política `alertas_marcar_leida_propia` deja a la DUEÑA de una fila
-- (`persona_id = fn_persona_actual_id()`) hacer UPDATE, y una política de RLS
-- filtra FILAS, no columnas. Como `authenticated` tiene `grant update` sobre
-- toda la tabla (0004), la dueña puede reescribir cualquier campo de sus
-- propias alertas por PostgREST, sin pasar por el despacho.
--
-- Se midió otra vez contra el esquema real (las 544 migraciones de `main`, un
-- Postgres 17 desechable), con `set role authenticated` y la sesión de una
-- integrante: `update alertas set estado = 'enviado', intentos = 0, … where
-- persona_id = <la suya>` devolvió UPDATE 1, y la fila quedó con ONCE columnas
-- reescritas —las 13 de la tabla menos `leido_at` y `persona_id`; esta última
-- la frena el `with check` de la política, que no deja pasar la fila a otra
-- persona—, no solo las cinco del hallazgo: `estado`, `intentos`, `enviado_at`,
-- `nota_fallo`, `procesando_desde`, y además `ultimo_intento_at`, `created_at`,
-- `id`, `tipo`, `canal` y `payload`. La fila de OTRA persona sigue protegida
-- (UPDATE 0), y INSERT y DELETE ya estaban cerrados por RLS (no hay política
-- para ellos: el INSERT da «violates row-level security», el DELETE borra 0).
--
-- Quién es dueña de qué: de sus `auto_cierre`, cada integrante; de los avisos
-- de vencimiento (`contrato_por_vencer`, `vacaciones_por_vencer`), el destinatario
-- de DO. Con eso, alguien podía darse un aviso por «enviado», devolverse los
-- intentos a cero, o esconder un fallo borrando `nota_fallo`.
--
-- Lo que lo hace más serio que «tocar el estado de la cola»: `tipo` y `payload`
-- también estaban abiertos, y `/api/alertas-encargadas` arma el correo con
-- ellos —el asunto, el cuerpo y los datos del contrato o de las vacaciones salen
-- del `payload`, tal cual—. Una integrante podía fabricarse un aviso con el
-- texto que quisiera y el despacho lo mandaba a su encargada o a DO desde el
-- remitente verificado de Dynamic. Es un correo de texto plano, sin código, pero
-- llega con la autoridad de la casa.
--
-- Y la brecha creció sola. La tabla tenía 9 columnas cuando la 0003 puso la
-- política; la 0354 sumó `nota_fallo` y la 0362 sumó `intentos`,
-- `procesando_desde` y `ultimo_intento_at`: cada
-- `add column` posterior quedó escribible por la dueña SIN que nadie lo
-- decidiera, porque el grant y la política no saben de columnas. El estado.md
-- ya lo anotaba («la 0362 lo amplía un poco»); la 0548 lo repitió como
-- pendiente. Esta migración lo cierra.
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--
-- Que un UPDATE directo sobre `alertas` —el de PostgREST, que corre como
-- `authenticated` o `anon`— solo pueda cambiar `leido_at`. Cualquier otra
-- diferencia entre la fila vieja y la nueva aborta con una frase legible, y la
-- fila no se mueve. Eso incluye ir de contrabando junto a `leido_at`
-- (`set leido_at = now(), estado = 'enviado'` también se rechaza).
--
-- Lo único que la dueña conserva es marcar leída, que es para lo que existe la
-- política. Quien ESCRIBE de verdad la cola sigue escribiéndola: las funciones
-- `SECURITY DEFINER` —`fn_alertas_reservar`, `fn_marcar_alerta_resultado`,
-- `fn_auto_cierre`, `fn_generar_alertas_vencimiento`, y las dos de la 0548 si
-- se pega— corren como `postgres` (su dueño), no como quien las llamó, y el
-- freno solo mira a quien NO es `postgres`. Una corrección a mano desde el SQL
-- Editor también corre como `postgres` y pasa.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que todo lo que actualiza `alertas` en producción es `SECURITY DEFINER` y
--     de `postgres`. Comprobado en el repositorio con el catálogo de un banco
--     con las 544 migraciones de `main`: las que actualizan (`fn_alertas_reservar`,
--     `fn_marcar_alerta_resultado`) y las que solo insertan (`fn_auto_cierre`,
--     `fn_generar_alertas_vencimiento`) son `prosecdef = true`, dueño `postgres`;
--     con la 0548 puesta se suman `fn_alertas_resolver_fallidas` y
--     `fn_alertas_devolver_intento`, también `SECURITY DEFINER` de `postgres`.
--     (El freno es BEFORE UPDATE: un INSERT no lo toca.) Y la app:
--     ninguna pantalla ni ruta hace `.from("alertas")` —el despacho
--     (`/api/alertas-encargadas`) usa la llave de servicio SOLO para llamar a
--     esas funciones por `rpc`—; `leido_at` no lo escribe nadie hoy (la app
--     móvil que lo iba a usar nunca existió). Lo de producción que se pegó a
--     mano y no está en el repo lo dice la consulta de «ANTES DE PEGAR».
--   · Que `fn_bloquear_alertas_directo` NO sea `SECURITY DEFINER` (ver abajo,
--     es la mitad del diseño).
--
-- ── DECIDÍ / DESCARTÉ / SE ROMPE SI ─────────────────────────────────────────
--
--   DECIDÍ: un trigger BEFORE UPDATE con lista PERMITIDA —solo `leido_at` puede
--     cambiar—, que aborta cuando `current_user <> 'postgres'`. Es el molde de
--     `fn_bloquear_rol_directo` (0296) y `fn_bloquear_sede_directa` (0342),
--     con la diferencia de que acá se nombra lo que SÍ se puede tocar y no lo
--     que no.
--
--   DESCARTÉ 1 · la lista de columnas PROHIBIDAS (`new.estado is distinct from
--     old.estado or new.intentos …`, las cinco del hallazgo). Es lo que hacen
--     los dos moldes, pero allá la tabla tiene UNA columna sensible; acá la
--     tabla entera es del sistema salvo una. La lista corta ya habría dejado
--     pasar `tipo`, `canal` y `payload` (el correo), y cada `add column` futuro
--     nacería abierto como nacieron los cuatro de la 0354/0362. Con la lista
--     permitida una columna nueva nace CERRADA: si algún día la dueña debe
--     poder escribirla, alguien tiene que decirlo aquí.
--
--   DESCARTÉ 2 · `revoke update on alertas from authenticated` + `grant update
--     (leido_at)`. Aquí SÍ funcionaría (la 0296 lo descarta para `personas`
--     porque el grant de tabla sigue vivo al revocar solo una columna; acá se
--     revoca la tabla entera y se concede la columna), y la 0508 lo hizo para
--     `correcciones_auditoria`. Pero queda una sola cerradura, y es la que la
--     0004 abre con `grant select, insert, update, delete on all tables in
--     schema public to authenticated`: una migración futura que repita esa
--     línea reabre la tabla entera en silencio, y el error de quien lo intenta
--     es «permission denied», no una frase. El trigger no mira los grants.
--
--   DESCARTÉ 3 · una función guardián `fn_marcar_alerta_leida`. El molde de la
--     casa pide función + trigger cuando alguien tiene que ESCRIBIR el campo
--     por una puerta con reglas. Acá las puertas con reglas ya existen (las
--     cuatro funciones de la cola) y la única columna abierta no la escribe
--     nadie: una función sin llamador es código que se mantiene sin que nadie
--     la use. La política `alertas_marcar_leida_propia` + este trigger dicen,
--     juntos, «la dueña, su fila, solo `leido_at`». Si algún día hay una app
--     que marque leídas, esa función se escribe entonces, con quien la llame.
--
--   SE ROMPE SI:
--     1. Alguien escribe un Edge Function o una ruta que haga `update alertas`
--        DIRECTO con la llave de servicio. Esa conexión corre como
--        `service_role`, no como `postgres`: el trigger la rechaza con la frase
--        de abajo. Falla en voz alta y sin dejar nada a medias; la salida es
--        una función `SECURITY DEFINER` como las cuatro de hoy. Es a propósito:
--        la llave de servicio no es más confiable que la sesión de una
--        integrante cuando el que escribe es código de una pantalla.
--     2. Alguien marca `fn_bloquear_alertas_directo` como `SECURITY DEFINER`
--        «por consistencia». Entonces `current_user` vale siempre `postgres`
--        dentro del trigger y deja pasar TODO, sin error. Es la falla más
--        silenciosa posible; la prueba 442 y la comprobación del final la
--        cazan (`el_freno_corre_con_quien_escribe`).
--     3. Una función de producción pegada a mano, fuera del repo, que haga
--        `update alertas` SIN ser `SECURITY DEFINER` (la corre la llave de
--        servicio o una sesión): dejaría de funcionar. La consulta de «ANTES DE
--        PEGAR» la nombra.
--     4. Se corre una sesión con `session_replication_role = replica`: apaga
--        TODOS los triggers. Solo la puede poner un superusuario, nunca un
--        cliente de PostgREST, pero conviene saberlo al montar fixtures en una
--        prueba (la 271 lo explica).
--
-- ── QUÉ NO HACE ─────────────────────────────────────────────────────────────
--
--   · No toca la política `alertas_marcar_leida_propia` (la dueña, su fila) ni
--     ningún grant: el trigger no depende de ellos.
--   · No limita QUÉ valor puede poner la dueña en `leido_at` (vaciarlo, o una
--     fecha). Marcar y desmarcar leída es suyo y no mueve nada que se pague ni
--     se despache.
--   · No reescribe ninguna función existente: no hay «md5 de partida».
--     `fn_bloquear_alertas_directo` es nueva (comprobado con donde-vive.sh y
--     con git grep sobre todas las ramas el 2026-10-25).
--   · No cierra INSERT ni DELETE: ya estaban cerrados por RLS (medido).
--   · No depende de la 0548: protege también el estado 'descartada' que esa
--     migración agrega, pero no la necesita. Se pega antes o después.
--
-- ── ANTES DE PEGAR ──────────────────────────────────────────────────────────
-- Dos consultas, en el SQL Editor. La primera debe volver SIN FILAS: si nombra
-- alguna función, esa dejará de poder escribir en `alertas` al pegar esta
-- migración, y hay que mirarla antes. La segunda debe dar `null` en `registro_550`
-- (si ya dice «550 · …» esta migración ya estaba pegada y repegarla es inocuo).
--
--   select p.proname, p.prosecdef, pg_get_userbyid(p.proowner) as dueno
--     from pg_proc p
--    where p.pronamespace = 'public'::regnamespace
--      and p.prosrc ~* '(update|delete[[:space:]]+from)[[:space:]]+(public\.)?alertas([^a-z_]|$)'
--      and not (p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres');
--
--   select (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 550) as registro_550,
--          (select count(*) from pg_trigger where tgrelid = 'alertas'::regclass and not tgisinternal) as triggers_en_alertas;
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
-- No cambia ningún dato ni ningún grant, así que revertir es solo quitar el
-- freno (y reabre el hueco de arriba):
--
--   drop trigger if exists trg_alertas_solo_leida_directo on alertas;
--   drop function if exists fn_bloquear_alertas_directo();
--   delete from migraciones_aplicadas where numero = 550;
--
-- ── CÓMO SE COMPRUEBA QUE ENTRÓ ─────────────────────────────────────────────
-- El `select` del final. Las cuatro primeras columnas deben dar `true` (o 0 en
-- la tercera).
-- ============================================================================

create or replace function fn_bloquear_alertas_directo()
returns trigger
language plpgsql as $function$
begin
  -- Se compara la fila entera, menos `leido_at`: lo que no se nombra aquí está
  -- cerrado, incluidas las columnas que se agreguen después. `to_jsonb` ve
  -- también `payload`, que es un jsonb dentro de otro jsonb.
  --
  -- OJO: esta función NO es `security definer` y no debe serlo. Mientras corre,
  -- `current_user` tiene que seguir siendo quien escribe (PostgREST:
  -- `authenticated`; las funciones de la cola: `postgres`, su dueño). Con
  -- `security definer` sería siempre `postgres` y el freno no frenaría nada.
  if (to_jsonb(new) - 'leido_at') is distinct from (to_jsonb(old) - 'leido_at')
     and current_user <> 'postgres' then
    raise exception 'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_alertas_solo_leida_directo on alertas;
create trigger trg_alertas_solo_leida_directo
  before update on alertas
  for each row
  execute function fn_bloquear_alertas_directo();

comment on trigger trg_alertas_solo_leida_directo on alertas is
  'Un UPDATE directo (PostgREST, current_user <> postgres) solo puede cambiar leido_at; lo demás lo escriben las funciones de la cola, que corren como postgres (0550).';

insert into migraciones_aplicadas (numero, nombre)
values (550, 'una_alerta_solo_se_marca_leida')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();


-- ── Comprobación ────────────────────────────────────────────────────────────
-- `el_freno_esta_puesto`, `el_freno_corre_con_quien_escribe` y `registro` deben
-- dar `true` / `550 · una_alerta_solo_se_marca_leida`; `escritores_que_el_freno_
-- dejaria_fuera` debe dar 0 (la misma consulta de «ANTES DE PEGAR», contada).
select
  (select count(*) = 1 from pg_trigger
    where tgname = 'trg_alertas_solo_leida_directo'
      and tgrelid = 'alertas'::regclass
      and tgenabled = 'O')
    as el_freno_esta_puesto,
  (select not prosecdef from pg_proc
    where proname = 'fn_bloquear_alertas_directo' and pronamespace = 'public'::regnamespace)
    as el_freno_corre_con_quien_escribe,
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prosrc ~* '(update|delete[[:space:]]+from)[[:space:]]+(public\.)?alertas([^a-z_]|$)'
      and not (p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'))
    as escritores_que_el_freno_dejaria_fuera,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 550)
    as registro;
