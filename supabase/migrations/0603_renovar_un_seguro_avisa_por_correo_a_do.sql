-- ============================================================================
-- 0603 — Renovar un seguro avisa por correo a Desarrollo Organizacional
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que toda póliza por terminar y sin renovación registrada llegue por correo a
--   DO, a los 45 y a los 15 días, también si nadie abre el panel. Pedido de Felipe,
--   2026-11-06: «que me avise en el momento que se tenga que renovar». Antes el
--   aviso existía solo en la Bandeja del panel: quien no entraba, no se enteraba.
--
--   Una póliza colectiva es UN correo por destinatario, no uno por persona asegurada.
--
-- QUÉ ASUME
--
--   · md5 de partida pedidos a PRODUCCIÓN el 2026-11-06, los dos sin retornos:
--       fn_alertas_email_pendientes  3de746201618418138af4352176c36f9 (4075 caracteres, 0362)
--       fn_alerta_sigue_vigente      7c34b4e12f83010204e9296a05abe6ff (3007 caracteres, 0548)
--       fn_alertas_resolver_fallidas 9642d1bd976b8a9a07895ad2dabcea20 (6729 caracteres, 0548; md5 del
--                                    repositorio: se confirma contra producción antes de pegar)
--   · Que el cron de pg_cron corre en producción, y el despacho de Vercel a las 12:00 UTC.
--     Por eso la generación va a las 11:00: la de `fn_generar_alertas_vencimiento`
--     corre a las 13:00 y sus filas esperan al día siguiente. No se toca aquí.
--   · `vigente_hasta` es EXCLUSIVO, como en toda la 0528.
--
-- POR QUÉ SE ELIGIÓ ASÍ
--
--   DECIDÍ:    Una función y un cron propios, y el tramo dentro de `evento`.
--              `fn_generar_alertas_vencimiento` da un solo toque por hecho; una caída del
--              correo dejaría a la póliza sin aviso, y aquí hay dos oportunidades.
--   DECIDÍ:    Una sola pregunta, `fn_seguro_sin_renovar`, para quien genera el aviso y para
--              quien lo revisa antes de enviarlo. El aviso le dice a DO lo mismo que la pantalla:
--              quien cambió de seguro no pide renovar el que dejó.
--   DECIDÍ:    La cola no entrega un aviso que ya no es cierto, y el cron lo cierra. Este correo
--              afirma «no hay renovación registrada»: una fila que esperó por una avería de
--              Resend no puede salir después de que alguien renovó.
--   DESCARTÉ:  Agregarlo a `fn_generar_alertas_vencimiento`: reescribe una función que
--              funciona a cambio de nada, y ese aviso es por persona, no por póliza.
--   DESCARTÉ:  Callar lo que `renueva_sola` dice que renueva: es un dato sin confirmar.
--   DESCARTÉ:  Avisar de «planilla sin Vida Ley»: espera al contador (0543, Felipe 2026-10-19).
--              Aquí solo se avisa de pólizas que existen.
--   SE ROMPE SI: el cron de la 0603 no queda programado. La comprobación del final lo dice.
--   SE ROMPE SI: otra migración reescribe estas funciones desde la misma versión de partida: la
--              guardia de abajo la detiene. La rama de licencias lo hace; la segunda en llegar
--              se rehace sobre la primera y vuelve a pedir el md5.
--
-- QUÉ NO HACE
--
--   · No toca planilla ni pago: la prima se paga a la aseguradora.
--   · No renueva nada. Avisa; decide una persona.
--   · No le escribe a la persona asegurada ni a su líder de equipo.
--
-- SE REVIERTE
--
--   select cron.unschedule('generar-alertas-seguros');
--   drop function fn_generar_alertas_seguros();
--   drop function fn_seguro_sin_renovar(uuid, text, date);
--   y restaurar `fn_alertas_email_pendientes` (0362), `fn_alerta_sigue_vigente` y
--   `fn_alertas_resolver_fallidas` (0548) y el check de `alertas` (0356), después de
--   `delete from alertas where tipo = 'seguro_por_renovar';`.
-- ============================================================================

do $guardia$
declare
  v_pendientes text;
  v_vigente    text;
  v_resolver   text;
begin
  select md5(p.prosrc) into v_pendientes from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_alertas_email_pendientes';
  select md5(p.prosrc) into v_vigente from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_alerta_sigue_vigente';

  select md5(p.prosrc) into v_resolver from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_alertas_resolver_fallidas';

  -- Repegar es seguro: la segunda vez las tres ya llevan este cambio.
  if v_pendientes is distinct from '3de746201618418138af4352176c36f9'
     and not exists (select 1 from pg_proc where proname = 'fn_alertas_email_pendientes' and prosrc like '%CAMBIO 0603%') then
    raise exception 'fn_alertas_email_pendientes no es la versión de partida (md5 %). Corre ./scripts/donde-vive.sh antes de seguir.', v_pendientes;
  end if;
  if v_vigente is distinct from '7c34b4e12f83010204e9296a05abe6ff'
     and not exists (select 1 from pg_proc where proname = 'fn_alerta_sigue_vigente' and prosrc like '%CAMBIO 0603%') then
    raise exception 'fn_alerta_sigue_vigente no es la versión de partida (md5 %). Corre ./scripts/donde-vive.sh antes de seguir.', v_vigente;
  end if;
  if v_resolver is distinct from '9642d1bd976b8a9a07895ad2dabcea20'
     and not exists (select 1 from pg_proc where proname = 'fn_alertas_resolver_fallidas' and prosrc like '%CAMBIO 0603%') then
    raise exception 'fn_alertas_resolver_fallidas no es la versión de partida (md5 %). Corre ./scripts/donde-vive.sh antes de seguir.', v_resolver;
  end if;
end
$guardia$;

-- ── 1 · El tipo nuevo ────────────────────────────────────────────────────────

alter table alertas drop constraint alertas_tipo_check;
alter table alertas add constraint alertas_tipo_check check (
  tipo = any (array[
    'olvido_salida', 'tardanza', 'salida_no_retornada', 'auto_cierre', 'digest_diario',
    'vacaciones_por_vencer', 'contrato_por_vencer',
    -- ⇩ CAMBIO 0603 ⇩
    'seguro_por_renovar'
  ])
);

-- ── 2 · Quién tiene que renovar ──────────────────────────────────────────────
-- Una fila por póliza y por destinatario de DO. La identidad de la póliza es la misma
-- de `hermanasDe` en `lib/admin/seguros.ts`: seguro, aseguradora, número y las dos fechas.

-- ¿Esta póliza de esta persona pide renovarse? No si otra empalma, y tampoco si es un seguro
-- principal que ya no es el suyo: quien pasó de FOLA a EsSalud no renueva FOLA, y la pantalla
-- no se lo pide. La baja de ese seguro va por «cambios por cerrar». Un complementario no se
-- compara con el principal: va además.
create or replace function fn_seguro_sin_renovar(p_persona_id uuid, p_producto text, p_vigente_hasta date)
returns boolean
language sql stable security definer set search_path = public
as $fn$
  select not exists (
           select 1 from polizas_seguro r
            where r.persona_id = p_persona_id and r.producto = p_producto and r.anulada_at is null
              and r.vigente_desde <= p_vigente_hasta and r.vigente_hasta > p_vigente_hasta
         )
     and (not t.principal or t.clave is not distinct from fn_seguro_tipo_principal(p_persona_id, fn_hoy_lima()))
    from seguros_tipos t
   where t.clave = p_producto;
$fn$;

revoke all on function fn_seguro_sin_renovar(uuid, text, date) from public, anon, authenticated;

create or replace function fn_generar_alertas_seguros()
returns int
language plpgsql security definer set search_path = public
as $fn$
declare
  v_hoy       date := fn_hoy_lima();
  v_generadas int;
begin
  -- Lo que esperaba salir y ya no es cierto se cierra con su motivo, para que no se cuente
  -- como un aviso caducado que alguien tenga que revisar.
  update alertas a
     set estado = 'descartada',
         intentos = greatest(a.intentos, 3),
         procesando_desde = null,
         nota_fallo = 'descartada: el hecho ya no está vigente · por el cron el ' || v_hoy
           || coalesce(' · ' || a.nota_fallo, '')
   where a.tipo = 'seguro_por_renovar'
     and a.estado in ('pendiente', 'fallido')
     and fn_alerta_sigue_vigente(a.tipo, a.persona_id, a.payload) is not true;

  with por_vencer as (
    select z.producto, t.nombre as seguro, z.aseguradora, z.numero_poliza, z.vigente_desde, z.vigente_hasta,
           lower(btrim(z.aseguradora)) as aseguradora_clave,
           lower(btrim(z.numero_poliza)) as numero_clave,
           p.nombres || ' ' || p.apellidos as persona,
           coalesce(s.codigo, '—') as sede
      from polizas_seguro z
      join seguros_tipos t on t.clave = z.producto
      join personas p on p.id = z.persona_id
      left join sedes s on s.id = p.sede_base_id
     where z.anulada_at is null
       and p.estado = 'activo'
       and not p.cuenta_de_servicio
       and z.vigente_desde <= v_hoy
       and z.vigente_hasta between v_hoy and v_hoy + 45
       and fn_seguro_sin_renovar(z.persona_id, z.producto, z.vigente_hasta) is true
  ),
  polizas as (
    select producto, aseguradora_clave, numero_clave, vigente_desde, vigente_hasta,
           min(seguro) as seguro, min(aseguradora) as aseguradora, min(numero_poliza) as numero_poliza,
           count(*)::int as personas, min(persona) as primera, min(sede) as sede, count(distinct sede) as sedes,
           case when vigente_hasta - v_hoy <= 15 then 15 else 45 end as tramo
      from por_vencer
     group by producto, aseguradora_clave, numero_clave, vigente_desde, vigente_hasta
  ),
  eventos as (
    select pz.*, concat_ws('|', pz.producto, pz.aseguradora_clave, pz.numero_clave, pz.vigente_desde, pz.vigente_hasta, pz.tramo) as evento
      from polizas pz
  )
  insert into alertas (persona_id, tipo, canal, payload)
  select do_.id, 'seguro_por_renovar', 'email',
    jsonb_build_object(
      'evento', e.evento,
      'producto', e.producto,
      'seguro', e.seguro,
      'aseguradora', e.aseguradora,
      'numero_poliza', e.numero_poliza,
      'personas', e.personas,
      -- Sin nombres de una colectiva: `persona` es lo que se lee en la lista de avisos.
      'persona', case when e.personas = 1 then e.primera else e.personas::text || ' personas' end,
      'sede', case when e.sedes = 1 then e.sede else 'Varias sedes' end,
      'vigente_desde', e.vigente_desde,
      'vigente_hasta', e.vigente_hasta,
      'dias_restantes', e.vigente_hasta - v_hoy,
      'tramo', e.tramo
    )
    from eventos e
   cross join (
     select id from personas where rol in ('admin', 'lider_do') and estado = 'activo' and email is not null
   ) do_
   where not exists (
     select 1 from alertas a
      where a.tipo = 'seguro_por_renovar'
        and a.payload ->> 'evento' = e.evento
        and a.persona_id = do_.id
        and a.canal = 'email'
   );
  get diagnostics v_generadas = row_count;

  return v_generadas;
end;
$fn$;

revoke all on function fn_generar_alertas_seguros() from public, anon, authenticated;

-- ── 3 · A quién le llega ─────────────────────────────────────────────────────
-- Copiada de la 0362 (la vigente). Único cambio: el tipo nuevo en las dos listas.

create or replace function fn_alertas_email_pendientes()
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
      -- ⇩⇩⇩ CAMBIO 0603 ⇩⇩⇩ — este correo afirma que no hay renovación: si ya la hay, no sale.
      and (al.tipo <> 'seguro_por_renovar' or fn_alerta_sigue_vigente(al.tipo, al.persona_id, al.payload) is true)
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
    -- ⇩⇩⇩ CAMBIO 0603 ⇩⇩⇩ — un aviso de seguro ya viene con su destinatario de DO: la líder de equipo no recibe el de cada integrante.
    where al.tipo not in ('contrato_por_vencer', 'vacaciones_por_vencer', 'seguro_por_renovar')
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
    -- ⇩⇩⇩ CAMBIO 0603 ⇩⇩⇩
    where al.tipo in ('contrato_por_vencer', 'vacaciones_por_vencer', 'seguro_por_renovar')
  )
  -- select id, tipo, payload, persona_nombre, sede_codigo, destinatarios, destinatarios_nombres
  -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩
  select id, tipo, payload, persona_nombre, sede_codigo, destinatarios, destinatarios_nombres, intentos, estado_previo
  from combinado
  order by created_at;
$fn$;

revoke all on function fn_alertas_email_pendientes() from public, anon, authenticated;

-- ── 4 · Un aviso que ya no hace falta no sale ────────────────────────────────
-- Copiada de la 0548 (la vigente). Único cambio: la rama del tipo nuevo.

create or replace function fn_alerta_sigue_vigente(p_tipo text, p_persona_id uuid, p_payload jsonb)
returns boolean
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_persona uuid;
  v_ts      timestamptz;
  v_fin     date;
  v_vence   date;
  v_hoy     date := fn_hoy_lima();
  v_saldo   jsonb;
begin
  if p_tipo = 'auto_cierre' then
    -- La persona del aviso ES alertas.persona_id (el integrante cuya salida se
    -- cerró sola). La salida inventada se identifica por su instante exacto.
    if p_persona_id is null or p_payload ->> 'ts_cierre' is null then
      return false;
    end if;
    v_ts := (p_payload ->> 'ts_cierre')::timestamptz;

    return exists (
             select 1
               from marcajes m
              where m.persona_id = p_persona_id
                and m.origen = 'auto_cierre'
                and m.tipo = 'salida_final'
                and m.timestamp_marca = v_ts
                and m.estado_revision = 'pendiente_revision'
                and m.anulada_at is null
           )
       and fn_persona_liquidada(p_persona_id) is not true;

  elsif p_tipo = 'contrato_por_vencer' then
    -- OJO: alertas.persona_id es el DO destinatario. La persona del contrato
    -- va en el payload.
    if p_payload ->> 'persona_id' is null or p_payload ->> 'fecha_fin_contrato' is null then
      return false;
    end if;
    v_persona := (p_payload ->> 'persona_id')::uuid;
    v_fin     := (p_payload ->> 'fecha_fin_contrato')::date;

    return exists (
             select 1
               from personas p
              where p.id = v_persona
                and p.estado = 'activo'
                and p.fecha_fin_contrato = v_fin
                and p.fecha_fin_contrato >= v_hoy
           );

  elsif p_tipo = 'vacaciones_por_vencer' then
    -- Igual que arriba: la persona de las vacaciones va en el payload.
    if p_payload ->> 'persona_id' is null then
      return false;
    end if;
    v_persona := (p_payload ->> 'persona_id')::uuid;
    v_vence   := (p_payload ->> 'vence_el')::date;   -- null si el payload no lo trae

    -- Primero que exista y siga activa: fn_vacaciones_saldo_interno revienta
    -- ('La persona no existe.') si no la encuentra.
    if not exists (select 1 from personas p where p.id = v_persona and p.estado = 'activo') then
      return false;
    end if;

    -- El MISMO cálculo y las MISMAS condiciones con las que
    -- fn_generar_alertas_vencimiento (0371) creó el aviso.
    v_saldo := fn_vacaciones_saldo_interno(v_persona, v_hoy);

    return coalesce((v_saldo ->> 'aplica')::boolean, false)
       and coalesce((v_saldo ->> 'records_sin_gozar')::int, 0) > 0
       and (   coalesce((v_saldo ->> 'dias_para_vencer')::int, 1000) <= 60
            or coalesce((v_saldo ->> 'records_vencidos')::int, 0) > 0)
       and (v_vence is null or (v_saldo ->> 'vence_el')::date = v_vence);

  -- ⇩⇩⇩ CAMBIO 0603 ⇩⇩⇩
  elsif p_tipo = 'seguro_por_renovar' then
    -- OJO: alertas.persona_id es el DO destinatario. La póliza va en el payload.
    -- Sigue vigente mientras quede alguien activo en esa póliza sin una que empalme:
    -- registrar la renovación apaga el correo, igual que apaga el de la Bandeja.
    if p_payload ->> 'producto' is null or p_payload ->> 'aseguradora' is null or p_payload ->> 'numero_poliza' is null
       or p_payload ->> 'vigente_desde' is null or p_payload ->> 'vigente_hasta' is null then
      return false;
    end if;
    v_fin := (p_payload ->> 'vigente_hasta')::date;

    return v_fin >= v_hoy
       and exists (
             select 1
               from polizas_seguro z
               join personas p on p.id = z.persona_id
              where z.producto = p_payload ->> 'producto'
                and lower(btrim(z.aseguradora)) = lower(btrim(p_payload ->> 'aseguradora'))
                and lower(btrim(z.numero_poliza)) = lower(btrim(p_payload ->> 'numero_poliza'))
                and z.vigente_desde = (p_payload ->> 'vigente_desde')::date
                and z.vigente_hasta = v_fin
                and z.anulada_at is null
                and p.estado = 'activo'
                and not p.cuenta_de_servicio
                and fn_seguro_sin_renovar(z.persona_id, z.producto, z.vigente_hasta) is true
           );
  end if;

  -- Un tipo sin regla propia (o uno futuro) no se puede comprobar contra el
  -- mundo: sigue vigente solo por la ventana, que decide quien llama.
  return true;
exception
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    return false;
end;
$fn$;

-- ── 4b · Si el correo falló, se puede reencolar ──────────────────────────────
-- Copiada de la 0548 (la vigente). Único cambio: el tipo nuevo, igual que contratos y
-- vacaciones: sin esto, el aviso de los 15 días, el último, se perdería para siempre.

create or replace function fn_alertas_resolver_fallidas(p_ejecutar boolean default false)
returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  v_ejecutar  boolean := p_ejecutar is true;   -- null cuenta como «solo mirar»
  v_hoy       text    := fn_hoy_lima()::text;
  v_quien     text;
  v_resultado jsonb;
begin
  -- Mismo permiso que la tarjeta Sistema: fn_alertas_despacho_resumen (0362).
  -- `is not true`, no `not`: un null no puede pasar como autorizado.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede resolver los avisos que fallaron.';
  end if;

  if v_ejecutar then
    -- Quién resuelve queda en la nota de cada fila.
    v_quien := coalesce(
      (select p.nombres || ' ' || p.apellidos from personas p where p.id = fn_persona_actual_id()),
      'Desarrollo Organizacional');

    -- PASO 1 — bloquear, y nada más. Ordenado por id para que dos resolver
    -- simultáneos tomen los bloqueos en el mismo orden y no se crucen. Si otra
    -- sesión ya está resolviendo, esto ESPERA su commit; al despertar,
    -- Postgres re-evalúa la condición sobre la fila ya cambiada y las que esa
    -- sesión resolvió dejan de entrar. La vista previa NO pasa por acá: mirar
    -- no bloquea a nadie.
    perform 1
       from alertas a
      where fn_alerta_sin_salida(a.estado, a.intentos, a.procesando_desde, a.enviado_at, a.created_at)
      order by a.id
        for update of a;
  end if;

  -- PASO 2 — clasificar y escribir en UNA sentencia (una transacción). En
  -- READ COMMITTED esta sentencia toma su propia foto DESPUÉS de los
  -- bloqueos, así que ve lo que la otra sesión dejó.
  with candidatas as materialized (
    select a.id, a.tipo, a.persona_id, a.payload, a.nota_fallo, a.created_at
      from alertas a
     where fn_alerta_sin_salida(a.estado, a.intentos, a.procesando_desde, a.enviado_at, a.created_at)
  ),
  clasificadas as materialized (
    select c.id, c.tipo, c.nota_fallo,
           -- La ventana se lee de fn_alerta_despachable, no se copia, y se mide
           -- como la verá el despacho de MAÑANA (corre una vez al día): una
           -- fila 'pendiente' sin intentos creada hace `created_at + 1 día`
           -- ¿saldría?
           fn_alerta_despachable('pendiente', 0, null, c.created_at - interval '1 day') as en_ventana,
           fn_alerta_sigue_vigente(c.tipo, c.persona_id, c.payload)                     as vigente
      from candidatas c
  ),
  destinos as materialized (
    select k.id, k.tipo, k.nota_fallo, k.en_ventana,
           case
             -- Vigente y le alcanza la ventana: vuelve a la cola tal cual.
             when k.vigente and k.en_ventana then 'reencolar'
             -- Vigente, ya pasó la ventana, pero es un HECHO DE ESTADO que no
             -- se vuelve a generar (el not exists de la 0371 ignora el
             -- estado) y sigue siendo cierto: vuelve con otra semana.
             -- ⇩⇩⇩ CAMBIO 0603 ⇩⇩⇩ — el `not exists` de `fn_generar_alertas_seguros` tampoco mira el estado.
             when k.vigente and k.tipo in ('contrato_por_vencer', 'vacaciones_por_vencer', 'seguro_por_renovar') then 'reencolar'
             -- Vigente, ya pasó la ventana, y el hecho sigue a la vista en su
             -- pantalla: solo se deja de mandar el correo.
             when k.vigente then 'fuera_de_ventana'
             -- No vigente (o un null: no se pudo comprobar): ya no hay nada
             -- que avisar.
             else 'ya_no_vigente'
           end as destino
      from clasificadas k
  ),
  reencoladas as (
    update alertas a
       set estado = 'pendiente',
           intentos = 0,
           procesando_desde = null,
           -- Ventana renovada: otra semana para salir, y la fecha original
           -- se guarda (la primera, si se renueva más de una vez).
           created_at = case when d.en_ventana then a.created_at else now() end,
           payload = case when d.en_ventana then a.payload
                          else a.payload || jsonb_build_object(
                                 'creada_originalmente',
                                 coalesce(a.payload -> 'creada_originalmente', to_jsonb(a.created_at)))
                     end,
           nota_fallo = 'reencolada'
             || case when d.en_ventana then '' else ' con ventana renovada' end
             || ' por ' || v_quien || ' el ' || v_hoy
             || coalesce(' · ' || a.nota_fallo, '')
      from destinos d
     where v_ejecutar
       and d.destino = 'reencolar'
       and a.id = d.id
       -- Revalida bajo el candado del propio update.
       and fn_alerta_sin_salida(a.estado, a.intentos, a.procesando_desde, a.enviado_at, a.created_at)
    returning a.id
  ),
  descartadas as (
    update alertas a
       set estado = 'descartada',
           -- Al menos 3: con menos, una caducada descartada se volvería a
           -- contar como caducada (estado <> 'enviado', intentos < 3).
           intentos = greatest(a.intentos, 3),
           procesando_desde = null,
           nota_fallo = 'descartada: '
             || case d.destino
                  when 'fuera_de_ventana' then 'fuera de la ventana de despacho, pero el hecho sigue vigente'
                  else 'el hecho ya no está vigente'
                end
             || ' · por ' || v_quien || ' el ' || v_hoy
             || coalesce(' · ' || a.nota_fallo, '')
      from destinos d
     where v_ejecutar
       and d.destino <> 'reencolar'
       and a.id = d.id
       and fn_alerta_sin_salida(a.estado, a.intentos, a.procesando_desde, a.enviado_at, a.created_at)
    returning a.id
  ),
  -- Lo que de verdad se escribió. En la vista previa no hay updates y se
  -- cuenta toda la clasificación: mostrar y ejecutar salen del mismo cálculo.
  hechos as (
    select d.*
      from destinos d
     where not v_ejecutar
        or d.id in (select r.id from reencoladas r union all select x.id from descartadas x)
  )
  select jsonb_build_object(
           'ejecutado', v_ejecutar,
           'reencolar', jsonb_build_object(
             'total', count(*) filter (where h.destino = 'reencolar'),
             'por_tipo', coalesce(
               (select jsonb_object_agg(t.tipo, t.n)
                  from (select x.tipo, count(*) as n
                          from hechos x
                         where x.destino = 'reencolar'
                         group by x.tipo) t),
               '{}'::jsonb),
             'ventana_renovada', count(*) filter (where h.destino = 'reencolar' and not h.en_ventana)
           ),
           'descartar', jsonb_build_object(
             'total', count(*) filter (where h.destino <> 'reencolar'),
             'por_motivo', jsonb_build_object(
               'fuera_de_ventana', count(*) filter (where h.destino = 'fuera_de_ventana'),
               'ya_no_vigente',    count(*) filter (where h.destino = 'ya_no_vigente')
             )
           )
         )
    into v_resultado
    from hechos h;

  return v_resultado;
end;
$fn$;

-- ── 5 · El cron ──────────────────────────────────────────────────────────────
-- A las 11:00 UTC (6 a. m. en Lima), una hora antes del despacho.

select cron.schedule('generar-alertas-seguros', '0 11 * * *', $$select fn_generar_alertas_seguros()$$);

-- ── 6 · Registro ─────────────────────────────────────────────────────────────

insert into migraciones_aplicadas (numero, nombre) values (603, 'renovar_un_seguro_avisa_por_correo_a_do')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regprocedure('fn_generar_alertas_seguros()') is not null                                  as la_funcion_existe,
  not has_function_privilege('authenticated', 'fn_generar_alertas_seguros()', 'execute')        as nadie_la_llama_con_sesion,
  (select pg_get_constraintdef(oid) like '%seguro_por_renovar%' from pg_constraint
    where conname = 'alertas_tipo_check')                                                       as el_tipo_entra,
  (select prosrc like '%CAMBIO 0603%' from pg_proc where proname = 'fn_alertas_email_pendientes') as la_cola_lo_conoce,
  (select prosrc like '%CAMBIO 0603%' from pg_proc where proname = 'fn_alerta_sigue_vigente')     as la_vigencia_lo_conoce,
  (select prosrc like '%CAMBIO 0603%' from pg_proc where proname = 'fn_alertas_resolver_fallidas') as el_reintento_lo_conoce,
  (select count(*) from cron.job where jobname = 'generar-alertas-seguros')                     as cron_de_1,
  (select nombre from migraciones_aplicadas where numero = 603)                                 as registro;
