-- ============================================================================
-- 0362 — La cola de alertas se reserva, reintenta y avisa
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que el despacho diario de avisos por correo
-- (/api/alertas-encargadas, cron de Vercel a las 12:00 UTC) deje de tener
-- tres formas silenciosas de fallar:
--
--   · un mismo aviso ya no puede salir dos veces porque dos ejecuciones se
--     solaparon (hallazgo 16 de la auditoría del 2026-09-03/04);
--   · si la ejecución muere a mitad del lote —el plan Hobby de Vercel corta a
--     los 10 s si no se declara más, y con ~15-20 pendientes acumulados se
--     pasa—, los correos ya enviados NO se vuelven a mandar al día siguiente
--     (hallazgo 17);
--   · un envío que Resend rechazó se reintenta —hasta tres veces— en vez de
--     quedar 'fallido' para siempre sin que nadie se entere, y lo que quedó
--     del viernes ya no se descarta por un fin de semana sin cron: la ventana
--     pasa de 2 a 7 días (hallazgo 18). Y lo que de verdad no va a salir
--     —tres fallos, una fila atascada, una caducada— ahora se cuenta en una
--     función que la Bandeja lee y muestra a DO.
--
-- EL DEFECTO, en detalle. La 0354 diseñó la cola con dos pasos sin candado
-- entre medio: `fn_alertas_email_pendientes` lista TODO lo 'pendiente', la
-- ruta manda el correo y recién después `fn_marcar_alerta_resultado` cierra
-- la fila. Entre el primer paso y el último, la fila sigue diciendo
-- 'pendiente' para cualquier otra ejecución que llegue —un reintento del
-- cron, un redeploy que dispara la ruta dos veces— y esa segunda lectura ve
-- las mismas filas y manda los mismos correos. Es el mismo agujero que
-- cerró la 0361 en objetivos con el doble clic, en otra mesa. Y del lado
-- del fallo, 'fallido' no se releía nunca: el filtro era `estado =
-- 'pendiente'`, así que un 502 de Resend un martes dejaba ese aviso muerto
-- sin registro visible. La ventana de 48 h remataba: si el cron del sábado
-- y el domingo no corrieron, lo del viernes ya estaba fuera el lunes.
--
-- QUÉ ASUME
--   · Que solo la ruta de servidor (con la llave de servicio) escribe
--     'procesando': ninguna pantalla ni pg_cron reserva filas. Por eso
--     `fn_alertas_reservar` queda sin `grant` a `authenticated`.
--   · Que un despacho que sigue diciendo 'procesando' después de UNA HORA es
--     una ejecución que murió, no una que sigue trabajando: la ruta declara
--     60 s como máximo (el tope del plan Hobby), así que a la hora ya no hay
--     nadie del otro lado.
--   · Que el número de filas que pueden acumularse es el de siempre (decenas,
--     no miles): `fn_alertas_despacho_resumen` cuenta con `count(*)` sobre la
--     tabla entera sin índice nuevo, y a esta escala no hace falta.
--
-- POR QUÉ SE ELIGIÓ ASÍ
--   · UNA sola definición de «despachable» —`fn_alerta_despachable`— que
--     leen la lista, la reserva y el resumen. Antes el predicado estaba
--     escrito dos veces (una por rama del `union all`) y con este cambio
--     habrían sido cuatro copias de una condición con cinco términos; la
--     forma en que se desincronizan copias así es la regla 3 de
--     `packages/shared`, en SQL.
--   · Reservar ANTES de enviar, con un compare-and-set (`update … where
--     fn_alerta_despachable(...)` y `return found`): dos ejecuciones pueden
--     listar la misma fila, pero solo una consigue el `update` —la segunda
--     espera el candado de fila, reevalúa el `where` sobre la versión nueva
--     (ya 'procesando', recién marcada) y se queda con cero filas—. Eso es
--     lo que resuelve el 16. Y como la marca queda ANTES del envío, si la
--     ejecución muere, solo la fila en vuelo queda 'procesando'; las ya
--     enviadas dicen 'enviado' y las no tocadas siguen 'pendiente' — eso
--     resuelve el 17.
--   · Una fila 'procesando' atascada más de una hora se vuelve a despachar,
--     con tope de 3 intentos. Se asume a propósito un riesgo, acotado y
--     documentado: si el corte cayó JUSTO entre que Resend aceptó el correo
--     y que la fila se marcó 'enviado', ese aviso saldrá dos veces. Se
--     prefiere así porque perder un aviso de contrato por vencer cuesta más
--     que un correo repetido — y la ventana en que puede pasar son los
--     milisegundos entre dos llamadas, no las horas de antes.
--   · Tope de 3 intentos, no infinito: un fallo que se repite tres días
--     seguidos no es transitorio —una clave de Resend rotada, un dominio
--     sin verificar— y seguir insistiendo solo esconde que hace falta una
--     persona. A partir del tercero la fila queda 'fallido' definitiva y
--     el resumen la cuenta para que la Bandeja la muestre.
--   · Siete días de ventana: cubre un fin de semana largo sin cron y un par
--     de días de despliegue roto. Lo más viejo que eso ya no es aviso, es
--     historia, y se cuenta como «caducado» en el resumen en vez de salir
--     de golpe cuando alguien arregle el cron.
--   · El resumen reparte cada fila en UNA sola categoría —definitiva,
--     atascada o caducada— y «caducada» se acota a lo que el despacho pudo
--     haber listado alguna vez: filas creadas desde que la 0354 existe en
--     ESTA base (`migraciones_aplicadas.aplicada_at`). `alertas` guarda
--     auto-cierres 'pendiente' desde julio que la 0354 dejó fuera A
--     PROPÓSITO —nunca fueron candidatos, ver su encabezado—; contarlos
--     habría encendido la tarjeta de la Bandeja desde el primer día con
--     decenas de avisos de julio «que hay que dar a mano», sin manera de
--     descartarlos, y la Bandeja no habría vuelto a decir «No hay nada
--     pendiente». Un falso positivo permanente en la pantalla que decide
--     qué mira una persona: el peor error de esta casa. (Lo cazó la revisión
--     del 2026-09-04 midiendo: una definitiva de 9 días más una pendiente
--     de agosto daban caducadas = 2.)
--   · Una fila que murió en su tercer intento ('procesando' atascada con
--     intentos ≥ 3) es definitiva, no atascada: nadie la va a retomar, y
--     decirle a DO que «se reintenta sola» sería mentirle. Y un
--     `procesando_desde` nulo —solo posible editando a mano— se trata como
--     atascado desde siempre (`coalesce(…, '-infinity')`) en vez de volver
--     la fila invisible por un `null` en la comparación.
--
-- QUÉ NO CAMBIA
--   · Las DOS ramas del `union all` de la 0359 —quién recibe cada tipo de
--     aviso, cómo se arma el destinatario, el dedupe de la propia persona
--     con su encargada— van intactas. Lo único que cambia en ellas es que
--     leen de una CTE `candidatas` en vez de repetir el filtro, y que
--     devuelven dos columnas más al final (`intentos`, `estado_previo`).
--   · `fn_marcar_alerta_resultado` conserva su firma y su `raise` cuando la
--     fila no existe. Ya no toca `intentos`: lo hace `fn_alertas_reservar`.
--   · Las plantillas de correo, el cron y la variable `CRON_SECRET`.
--
-- SE REVIERTE
--   drop function if exists fn_alertas_despacho_resumen();
--   drop function if exists fn_alertas_reservar(uuid);
--   drop function if exists fn_alertas_email_pendientes();
--   → volver a crearla con el cuerpo exacto de la 0359 (y
--     fn_marcar_alerta_resultado con el de la 0354);
--   drop function if exists fn_alerta_despachable(text, int, timestamptz, timestamptz);
--   update alertas set estado = 'pendiente', procesando_desde = null
--     where estado = 'procesando';
--   alter table alertas drop constraint if exists alertas_estado_check;
--   alter table alertas add constraint alertas_estado_check
--     check (estado in ('pendiente', 'enviado', 'fallido'));
--   Las columnas `intentos`, `procesando_desde` y `ultimo_intento_at` pueden
--   quedarse: no molestan y guardan historia. Y la ruta tiene que volver a
--   la versión anterior en el mismo despliegue, porque llama a
--   `fn_alertas_reservar`.
--
-- VIGENTE EN: 0359_el_aviso_de_alertas_tambien_avisa_al_propio_integrante.sql
-- para fn_alertas_email_pendientes (confirmado con donde-vive.sh el
-- 2026-09-04: 0354 → 0358 → 0359), y 0354_alertas_encargada_por_correo.sql
-- para fn_marcar_alerta_resultado (única definición).
-- md5 de partida (Postgres LOCAL) de fn_alertas_email_pendientes:
--   tal cual:         17f54441b4cb39b5ae20fa4f22bb1cc2
--   sin comentarios:  1e41c816f656d9ca6155b253915fbf16
-- Antes de pegar en el SQL Editor, vuelve a pedir el md5 a PRODUCCIÓN con
-- `./scripts/donde-vive.sh fn_alertas_email_pendientes` — la 0358 y la 0359
-- son de esta misma semana y varias sesiones trabajan sobre el mismo árbol.
-- ============================================================================

-- ── 1 · La tabla aprende el estado 'procesando' y a contar intentos ─────────

alter table alertas drop constraint if exists alertas_estado_check;
alter table alertas add constraint alertas_estado_check
  check (estado in ('pendiente', 'procesando', 'enviado', 'fallido'));

alter table alertas add column if not exists intentos int not null default 0;
alter table alertas add column if not exists procesando_desde timestamptz;
alter table alertas add column if not exists ultimo_intento_at timestamptz;

comment on column alertas.intentos is
  'Cuántas veces el despacho reservó esta fila para intentar enviarla. Lo sube fn_alertas_reservar; a partir de 3 ya no se reintenta (0362).';
comment on column alertas.procesando_desde is
  'Desde cuándo está reservada por una ejecución del despacho. Más de una hora en ''procesando'' significa que esa ejecución murió (0362).';
comment on column alertas.ultimo_intento_at is
  'Última vez que el despacho intentó enviarla, con éxito o sin él (0362).';

-- ── 2 · UNA sola definición de «despachable» ────────────────────────────────
-- Es `stable` y no `immutable` porque depende de now(). Recibe columnas, no
-- una fila, para que el `update` de fn_alertas_reservar la pueda usar en su
-- `where` sin subconsulta y Postgres la inserte en línea.

create or replace function fn_alerta_despachable(
  p_estado text,
  p_intentos int,
  p_procesando_desde timestamptz,
  p_created_at timestamptz
)
returns boolean
language sql stable
as $fn$
  select p_created_at > now() - interval '7 days'
     and (
           p_estado = 'pendiente'
        or (p_estado = 'fallido' and p_intentos < 3)
        or (p_estado = 'procesando'
            -- Un procesando_desde nulo (solo por edición a mano) cuenta
            -- como atascado desde siempre; sin el coalesce el `<` daría
            -- null y la fila no sería ni despachable ni atascada.
            and coalesce(p_procesando_desde, '-infinity'::timestamptz) < now() - interval '1 hour'
            and p_intentos < 3)
     );
$fn$;

revoke all on function fn_alerta_despachable(text, int, timestamptz, timestamptz) from public, anon, authenticated;

-- ── 3 · fn_alertas_email_pendientes devuelve dos columnas más ───────────────
-- Cambia la tabla que devuelve, y a una función `returns table` no se le
-- puede agregar una columna con `create or replace`: hay que tirarla y
-- crearla de nuevo (mismo camino que la 0161 con fn_documentos_tablero).
-- Nadie más depende de ella: solo la ruta, con la llave de servicio.

drop function if exists fn_alertas_email_pendientes();

create function fn_alertas_email_pendientes()
returns table (
  alerta_id uuid,
  tipo text,
  payload jsonb,
  persona_nombre text,
  sede_codigo text,
  destinatarios text[],
  destinatarios_nombres text[],
  -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩ — para que la ruta sepa en qué intento va y si
  -- la fila venía de un corte ('procesando') y avise a Sentry.
  intentos int,
  estado_previo text
)
language sql stable security definer set search_path = public
as $fn$
  -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩ — el predicado se escribe UNA vez, acá, y las dos
  -- ramas leen de esta CTE. Antes cada rama repetía
  --   where al.estado = 'pendiente'
  --     and al.created_at > now() - interval '2 days'
  with candidatas as (
    select al.*
    from alertas al
    where fn_alerta_despachable(al.estado, al.intentos, al.procesando_desde, al.created_at)
  ),
  combinado as (
    -- Rama 1 — igual a la 0354/0358, salvo el CAMBIO 0359: el correo y el
    -- nombre de la propia persona (pe) se agregan al arreglo de la
    -- encargada, deduplicado por si es, a la vez, su propia encargada.
    select al.id, al.tipo, al.payload, al.created_at,
           pe.nombres || ' ' || pe.apellidos as persona_nombre,
           sd.codigo as sede_codigo,
           array(
             select distinct x from unnest(
               coalesce(array_agg(distinct enc.email) filter (where enc.email is not null), '{}')
               || case when pe.email is not null then array[pe.email] else '{}'::text[] end
             ) as x
           ) as destinatarios,
           array(
             select distinct x from unnest(
               coalesce(array_agg(distinct (enc.nombres || ' ' || enc.apellidos)) filter (where enc.email is not null), '{}')
               || case when pe.email is not null then array[pe.nombres || ' ' || pe.apellidos] else '{}'::text[] end
             ) as x
           ) as destinatarios_nombres,
           -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩
           al.intentos,
           al.estado as estado_previo
    -- from alertas al
    -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩
    from candidatas al
    join personas pe on pe.id = al.persona_id
    join sedes sd on sd.id = pe.sede_base_id
    left join personas enc
      on enc.sede_base_id = pe.sede_base_id
     and enc.estado = 'activo'
     and (enc.rol = 'supervisor_sede' or enc.es_encargada_piso)
    -- where al.estado = 'pendiente'
    --   and al.created_at > now() - interval '2 days'
    --   and al.tipo not in ('contrato_por_vencer', 'vacaciones_por_vencer')
    -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩ — el estado y la ventana ya los decidió `candidatas`.
    where al.tipo not in ('contrato_por_vencer', 'vacaciones_por_vencer')
    -- CAMBIO 0359: pe.email se agrega al group by (funcionalmente
    -- dependiente de pe.id, ya presente vía el join).
    -- group by al.id, al.tipo, al.payload, al.created_at, pe.nombres, pe.apellidos, pe.email, sd.codigo
    -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩ — las dos columnas nuevas entran al group by.
    group by al.id, al.tipo, al.payload, al.created_at, al.intentos, al.estado, pe.nombres, pe.apellidos, pe.email, sd.codigo

    union all

    -- Rama 2 (0356/0357) — SIN CAMBIOS de destinatario: YA es `al.persona_id`,
    -- decidido al escribir. No hay encargada que buscar, y agregar a la
    -- propia persona otra vez no tendría sentido: ya es la única destinataria.
    select al.id, al.tipo, al.payload, al.created_at,
           coalesce(al.payload ->> 'persona', pe.nombres || ' ' || pe.apellidos) as persona_nombre,
           coalesce(al.payload ->> 'sede', '—') as sede_codigo,
           case when pe.email is not null then array[pe.email] else '{}'::text[] end as destinatarios,
           case when pe.email is not null then array[pe.nombres || ' ' || pe.apellidos] else '{}'::text[] end as destinatarios_nombres,
           -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩
           al.intentos,
           al.estado as estado_previo
    -- from alertas al
    -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩
    from candidatas al
    join personas pe on pe.id = al.persona_id
    -- where al.estado = 'pendiente'
    --   and al.created_at > now() - interval '2 days'
    --   and al.tipo in ('contrato_por_vencer', 'vacaciones_por_vencer')
    -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩
    where al.tipo in ('contrato_por_vencer', 'vacaciones_por_vencer')
  )
  -- select id, tipo, payload, persona_nombre, sede_codigo, destinatarios, destinatarios_nombres
  -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩
  select id, tipo, payload, persona_nombre, sede_codigo, destinatarios, destinatarios_nombres, intentos, estado_previo
  from combinado
  order by created_at;
$fn$;

revoke all on function fn_alertas_email_pendientes() from public, anon, authenticated;

-- ── 4 · La reserva: el compare-and-set ──────────────────────────────────────
-- Devuelve true si ESTA llamada se quedó con la fila; false si ya no era
-- despachable —porque otra ejecución la reservó un instante antes, porque ya
-- salió, o porque agotó sus tres intentos—. La ruta manda el correo SOLO si
-- recibe true. `intentos` sube acá y no al marcar el resultado, para que una
-- ejecución que muera después de reservar también cuente como intento.

create or replace function fn_alertas_reservar(p_id uuid)
returns boolean
language plpgsql security definer set search_path = public
as $fn$
begin
  update alertas
     set estado = 'procesando',
         procesando_desde = now(),
         intentos = intentos + 1,
         ultimo_intento_at = now()
   where id = p_id
     and fn_alerta_despachable(estado, intentos, procesando_desde, created_at);

  return found;
end;
$fn$;

revoke all on function fn_alertas_reservar(uuid) from public, anon, authenticated;

-- ── 5 · Marcar el resultado: cierra la reserva, no cuenta intentos ──────────

create or replace function fn_marcar_alerta_resultado(p_id uuid, p_exito boolean, p_nota text default null)
returns void
language plpgsql security definer set search_path = public
as $fn$
begin
  -- update alertas
  -- set estado = case when p_exito then 'enviado' else 'fallido' end,
  --     enviado_at = case when p_exito then now() else enviado_at end,
  --     nota_fallo = nullif(trim(coalesce(p_nota, '')), '')
  -- where id = p_id;
  -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩ — la reserva se suelta en los dos casos; un éxito
  -- borra la nota del fallo anterior, para que no quede colgada de un
  -- reintento que sí salió.
  update alertas
     set estado = case when p_exito then 'enviado' else 'fallido' end,
         enviado_at = case when p_exito then now() else enviado_at end,
         nota_fallo = case when p_exito then null else nullif(trim(coalesce(p_nota, '')), '') end,
         procesando_desde = null
   where id = p_id;

  if not found then
    raise exception 'Esa alerta (%) ya no existe.', p_id;
  end if;
end;
$fn$;

revoke all on function fn_marcar_alerta_resultado(uuid, boolean, text) from public, anon, authenticated;

-- ── 6 · El resumen que lee la Bandeja ───────────────────────────────────────
-- Lo que el despacho NO va a resolver solo, contado para que una persona lo
-- vea. Cada fila cae en UNA sola categoría, porque la Bandeja las suma en un
-- total y una fila contada dos veces es un aviso inventado:
--   · fallidas_definitivas: tres intentos, sea que el tercero terminó en
--     'fallido' o que la ejecución murió con él en vuelo ('procesando' con
--     intentos ≥ 3). Nadie las va a tocar más. Van con `motivos_definitivos`
--     —las notas distintas del último fallo— para que la tarjeta diga POR
--     QUÉ: «sin encargada con correo» se arregla en Equipo, no en Resend.
--   · atascadas: 'procesando' desde hace más de una hora, con intentos que
--     le quedan y dentro de la ventana — las que el próximo despacho SÍ va
--     a retomar solo.
--   · caducadas: sin salir, fuera de la ventana de 7 días y con intentos
--     que le quedaban, acotadas a lo creado desde que la 0354 existe en
--     esta base (ver el encabezado: lo anterior es el backlog que la 0354
--     dejó fuera a propósito, no un aviso que caducó). Se lee `aplicada_at`
--     y no una fecha escrita porque en cada base la 0354 se pegó un día
--     distinto; si no hubiera registro, se cae al día en que se pegó en
--     producción.
-- Y dos datos de contexto: cuántas esperan el próximo despacho y cuándo
-- salió el último correo — si esa fecha se aleja, el cron dejó de correr.

create or replace function fn_alertas_despacho_resumen()
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_resumen jsonb;
  -- Desde cuándo existe el despacho en ESTA base. Antes de eso una fila
  -- 'pendiente' no caducó: nunca fue candidata.
  v_desde_despacho timestamptz := coalesce(
    (select ma.aplicada_at from migraciones_aplicadas ma where ma.numero = 354),
    timestamptz '2026-09-03 00:00:00-05'
  );
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede ver el estado del despacho de avisos.';
  end if;

  select jsonb_build_object(
    'despachables',
      count(*) filter (where fn_alerta_despachable(a.estado, a.intentos, a.procesando_desde, a.created_at)),
    'atascadas',
      count(*) filter (where a.estado = 'procesando'
                         and coalesce(a.procesando_desde, '-infinity'::timestamptz) < now() - interval '1 hour'
                         and a.intentos < 3
                         and a.created_at > now() - interval '7 days'),
    'fallidas_definitivas',
      count(*) filter (where a.estado in ('fallido', 'procesando') and a.intentos >= 3),
    'caducadas',
      count(*) filter (where a.estado <> 'enviado'
                         and a.enviado_at is null
                         and a.intentos < 3
                         and a.created_at <= now() - interval '7 days'
                         and a.created_at >= v_desde_despacho),
    'ultimo_envio_at',
      max(a.enviado_at),
    'motivos_definitivos',
      coalesce(
        (select jsonb_agg(distinct d.nota_fallo)
           from alertas d
          where d.estado in ('fallido', 'procesando')
            and d.intentos >= 3
            and d.nota_fallo is not null),
        '[]'::jsonb
      )
  )
  into v_resumen
  from alertas a;

  return v_resumen;
end;
$fn$;

grant execute on function fn_alertas_despacho_resumen() to authenticated;
revoke execute on function fn_alertas_despacho_resumen() from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (362, 'la_cola_de_alertas_se_reserva_reintenta_y_avisa')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'alertas_estado_check') like '%procesando%' as check_acepta_procesando,
  (select count(*) from information_schema.columns where table_name = 'alertas' and column_name in ('intentos', 'procesando_desde', 'ultimo_intento_at')) as columnas_nuevas,
  (select count(*) from pg_proc where proname = 'fn_alerta_despachable') as fn_despachable,
  (select count(*) from pg_proc where proname = 'fn_alertas_reservar') as fn_reservar,
  (select count(*) from pg_proc where proname = 'fn_alertas_despacho_resumen') as fn_resumen,
  (select pg_get_functiondef('fn_alertas_despacho_resumen'::regproc)) like '%motivos_definitivos%' as resumen_dice_el_motivo,
  (select pg_get_functiondef('fn_alertas_email_pendientes'::regproc)) like '%candidatas%' as pendientes_lee_candidatas,
  (select pg_get_functiondef('fn_alertas_email_pendientes'::regproc)) like '%union all%' as tiene_las_dos_ramas;
