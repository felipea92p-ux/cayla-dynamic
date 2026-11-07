-- ============================================================================
-- 0601 — Renovar un seguro avisa por correo a Desarrollo Organizacional
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
--   DESCARTÉ:  Agregarlo a `fn_generar_alertas_vencimiento`: reescribe una función que
--              funciona a cambio de nada, y ese aviso es por persona, no por póliza.
--   DESCARTÉ:  Callar lo que `renueva_sola` dice que renueva: es un dato sin confirmar.
--   DESCARTÉ:  Avisar de «planilla sin Vida Ley»: espera al contador (0543, Felipe 2026-10-19).
--              Aquí solo se avisa de pólizas que existen.
--   SE ROMPE SI: el cron de la 0601 no queda programado. La comprobación del final lo dice.
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
--   y restaurar `fn_alertas_email_pendientes` (0362), `fn_alerta_sigue_vigente` (0548)
--   y el check de `alertas` (0356), después de
--   `delete from alertas where tipo = 'seguro_por_renovar';`.
-- ============================================================================

do $guardia$
declare
  v_pendientes text;
  v_vigente    text;
begin
  select md5(p.prosrc) into v_pendientes from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_alertas_email_pendientes';
  select md5(p.prosrc) into v_vigente from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_alerta_sigue_vigente';

  -- Repegar es seguro: la segunda vez las dos ya llevan este cambio.
  if v_pendientes is distinct from '3de746201618418138af4352176c36f9'
     and not exists (select 1 from pg_proc where proname = 'fn_alertas_email_pendientes' and prosrc like '%CAMBIO 0601%') then
    raise exception 'fn_alertas_email_pendientes no es la versión de partida (md5 %). Corre ./scripts/donde-vive.sh antes de seguir.', v_pendientes;
  end if;
  if v_vigente is distinct from '7c34b4e12f83010204e9296a05abe6ff'
     and not exists (select 1 from pg_proc where proname = 'fn_alerta_sigue_vigente' and prosrc like '%CAMBIO 0601%') then
    raise exception 'fn_alerta_sigue_vigente no es la versión de partida (md5 %). Corre ./scripts/donde-vive.sh antes de seguir.', v_vigente;
  end if;
end
$guardia$;

-- ── 1 · El tipo nuevo ────────────────────────────────────────────────────────

alter table alertas drop constraint alertas_tipo_check;
alter table alertas add constraint alertas_tipo_check check (
  tipo = any (array[
    'olvido_salida', 'tardanza', 'salida_no_retornada', 'auto_cierre', 'digest_diario',
    'vacaciones_por_vencer', 'contrato_por_vencer',
    -- ⇩ CAMBIO 0601 ⇩
    'seguro_por_renovar'
  ])
);

-- ── 2 · Quién tiene que renovar ──────────────────────────────────────────────
-- Una fila por póliza y por destinatario de DO. La identidad de la póliza es la misma
-- de `hermanasDe` en `lib/admin/seguros.ts`: seguro, número y fecha de fin.

create or replace function fn_generar_alertas_seguros()
returns int
language plpgsql security definer set search_path = public
as $fn$
declare
  v_hoy       date := fn_hoy_lima();
  v_generadas int;
begin
  with por_vencer as (
    select z.producto, t.nombre as seguro, z.aseguradora, z.numero_poliza, z.vigente_hasta,
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
       and not exists (
             select 1 from polizas_seguro r
              where r.persona_id = z.persona_id and r.producto = z.producto and r.anulada_at is null
                and r.vigente_desde <= z.vigente_hasta and r.vigente_hasta > z.vigente_hasta
           )
  ),
  polizas as (
    select producto, numero_clave, vigente_hasta,
           min(seguro) as seguro, min(aseguradora) as aseguradora, min(numero_poliza) as numero_poliza,
           count(*)::int as personas, min(persona) as primera, min(sede) as sede, count(distinct sede) as sedes,
           case when vigente_hasta - v_hoy <= 15 then 15 else 45 end as tramo
      from por_vencer
     group by producto, numero_clave, vigente_hasta
  ),
  eventos as (
    select pz.*, pz.producto || '|' || pz.numero_clave || '|' || pz.vigente_hasta::text || '|' || pz.tramo::text as evento
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
    -- ⇩⇩⇩ CAMBIO 0601 ⇩⇩⇩ — un aviso de seguro ya viene con su destinatario de DO: la líder de equipo no recibe el de cada integrante.
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
    -- ⇩⇩⇩ CAMBIO 0601 ⇩⇩⇩
    where al.tipo in ('contrato_por_vencer', 'vacaciones_por_vencer', 'seguro_por_renovar')
  )
  -- select id, tipo, payload, persona_nombre, sede_codigo, destinatarios, destinatarios_nombres
  -- ⇩⇩⇩ CAMBIO 0362 ⇩⇩⇩
  select id, tipo, payload, persona_nombre, sede_codigo, destinatarios, destinatarios_nombres, intentos, estado_previo
  from combinado
  order by created_at;$fn$;

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

  -- ⇩⇩⇩ CAMBIO 0601 ⇩⇩⇩
  elsif p_tipo = 'seguro_por_renovar' then
    -- OJO: alertas.persona_id es el DO destinatario. La póliza va en el payload.
    -- Sigue vigente mientras quede alguien activo en esa póliza sin una que empalme:
    -- registrar la renovación apaga el correo, igual que apaga el de la Bandeja.
    if p_payload ->> 'producto' is null or p_payload ->> 'numero_poliza' is null or p_payload ->> 'vigente_hasta' is null then
      return false;
    end if;
    v_fin := (p_payload ->> 'vigente_hasta')::date;

    return v_fin >= v_hoy
       and exists (
             select 1
               from polizas_seguro z
               join personas p on p.id = z.persona_id
              where z.producto = p_payload ->> 'producto'
                and lower(btrim(z.numero_poliza)) = lower(btrim(p_payload ->> 'numero_poliza'))
                and z.vigente_hasta = v_fin
                and z.anulada_at is null
                and p.estado = 'activo'
                and not exists (
                      select 1 from polizas_seguro r
                       where r.persona_id = z.persona_id and r.producto = z.producto and r.anulada_at is null
                         and r.vigente_desde <= z.vigente_hasta and r.vigente_hasta > z.vigente_hasta
                    )
           );
  end if;

  -- Un tipo sin regla propia (o uno futuro) no se puede comprobar contra el
  -- mundo: sigue vigente solo por la ventana, que decide quien llama.
  return true;
exception
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    return false;
end;$fn$;

-- ── 5 · El cron ──────────────────────────────────────────────────────────────
-- A las 11:00 UTC (6 a. m. en Lima), una hora antes del despacho.

select cron.schedule('generar-alertas-seguros', '0 11 * * *', $$select fn_generar_alertas_seguros()$$);

-- ── 6 · Registro ─────────────────────────────────────────────────────────────

insert into migraciones_aplicadas (numero, nombre) values (601, 'renovar_un_seguro_avisa_por_correo_a_do')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regprocedure('fn_generar_alertas_seguros()') is not null                                  as la_funcion_existe,
  not has_function_privilege('authenticated', 'fn_generar_alertas_seguros()', 'execute')        as nadie_la_llama_con_sesion,
  (select pg_get_constraintdef(oid) like '%seguro_por_renovar%' from pg_constraint
    where conname = 'alertas_tipo_check')                                                       as el_tipo_entra,
  (select prosrc like '%CAMBIO 0601%' from pg_proc where proname = 'fn_alertas_email_pendientes') as la_cola_lo_conoce,
  (select prosrc like '%CAMBIO 0601%' from pg_proc where proname = 'fn_alerta_sigue_vigente')     as la_vigencia_lo_conoce,
  (select nombre from migraciones_aplicadas where numero = 601)                                 as registro;
