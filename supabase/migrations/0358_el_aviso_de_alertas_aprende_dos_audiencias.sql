-- ============================================================================
-- 0358_el_aviso_de_alertas_aprende_dos_audiencias.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que `fn_alertas_email_pendientes` (0354) siga devolviendo EXACTO lo mismo
--   para `auto_cierre`/`tardanza`/`salida_no_retornada`/`digest_diario`
--   —encargada de la sede de `alertas.persona_id`, resuelta al leer— y que
--   además resuelva `contrato_por_vencer`/`vacaciones_por_vencer` (0356/0357)
--   por su propio camino: el destinatario YA es `alertas.persona_id`, decidido
--   al escribir, sin volver a buscar una encargada.
--
-- QUÉ ASUME
--   Que nadie más escribe hoy en `alertas` con esos dos tipos nuevos salvo
--   `fn_generar_alertas_vencimiento`, y que su forma de payload
--   (`persona`, `sede`, y los campos propios de cada tipo) es la que ya
--   fijaron la 0356 y la 0357.
--
-- ── md5 DE PARTIDA — A CONFIRMAR CONTRA PRODUCCIÓN ANTES DE PEGAR ───────────
--
--   select md5(prosrc) from pg_proc where proname = 'fn_alertas_email_pendientes';
--
--   Esta migración se escribió sobre el cuerpo tal cual quedó en la 0354,
--   la única migración que la define (`donde-vive.sh` lo confirma, sin
--   historial de reescrituras). Aun así, la 0354 ya está en producción y
--   corriendo a diario — CONFIRMA el md5 antes de pegar esto, no lo asumas
--   por el número de migración.
--
-- ── POR QUÉ DOS RAMAS EN VEZ DE UNA CONDICIÓN DENTRO DE LA MISMA CONSULTA ───
--
-- La consulta de la 0354 resuelve el destinatario con un `left join` a
-- `personas enc` sobre `sede_base_id` + rol de encargada, agregado con
-- `array_agg`. Meter un `case` adentro de esa agregación para "a veces el
-- destinatario es otra persona" habría vuelto la consulta más difícil de
-- leer que la pregunta que responde. Separada en dos SELECT —cada uno tan
-- simple como si fuera el único— y unidos con `union all`, la rama de
-- `auto_cierre` queda literalmente la misma consulta de la 0354, con un
-- solo filtro de tipo agregado: quien la lea puede comparar línea por línea
-- que no cambió, sin tener que seguir un `case` entrelazado.
--
-- ── POR QUÉ EL DESTINATARIO NO SE RESUELVE COMO ENCARGADA PARA ESTOS DOS ───
--
-- La encargada de sede no ve datos de contrato ni acumulado de vacaciones de
-- otra persona en ningún lugar del panel hoy —esa vista es de DO—, así que
-- mandárselo por correo abriría un canal que la propia RLS no abre en
-- pantalla. `fn_generar_alertas_vencimiento` ya decidió el destinatario
-- correcto al escribir (0356: "por qué solo admin/líder DO"); esta consulta
-- solo tiene que respetarlo, no volver a decidirlo.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   Pegar de nuevo el cuerpo de `fn_alertas_email_pendientes` tal como quedó
--   en la 0354 (una sola rama, sin `union all`). Ningún dato se pierde:
--   las alertas de contrato/vacaciones por vencer simplemente vuelven a
--   salir con destinatarios vacíos —"sin encargada con correo activo en esa
--   sede"— hasta que se revierta esta migración de nuevo.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

create or replace function fn_alertas_email_pendientes()
returns table (
  alerta_id uuid,
  tipo text,
  payload jsonb,
  persona_nombre text,
  sede_codigo text,
  destinatarios text[],
  destinatarios_nombres text[]
)
language sql stable security definer set search_path = public
as $fn$
  with combinado as (
    -- Rama 1 — sin cambios respecto a la 0354: la encargada de la sede de
    -- quien protagoniza el aviso.
    select al.id, al.tipo, al.payload, al.created_at,
           pe.nombres || ' ' || pe.apellidos as persona_nombre,
           sd.codigo as sede_codigo,
           coalesce(array_agg(distinct enc.email) filter (where enc.email is not null), '{}') as destinatarios,
           coalesce(array_agg(distinct (enc.nombres || ' ' || enc.apellidos)) filter (where enc.email is not null), '{}') as destinatarios_nombres
    from alertas al
    join personas pe on pe.id = al.persona_id
    join sedes sd on sd.id = pe.sede_base_id
    left join personas enc
      on enc.sede_base_id = pe.sede_base_id
     and enc.estado = 'activo'
     and (enc.rol = 'supervisor_sede' or enc.es_encargada_piso)
    where al.estado = 'pendiente'
      and al.created_at > now() - interval '2 days'
      and al.tipo not in ('contrato_por_vencer', 'vacaciones_por_vencer')
    group by al.id, al.tipo, al.payload, al.created_at, pe.nombres, pe.apellidos, sd.codigo

    union all

    -- Rama 2 (0356/0357) — el destinatario YA es `al.persona_id`: lo decidió
    -- fn_generar_alertas_vencimiento al escribir. No hay encargada que buscar.
    select al.id, al.tipo, al.payload, al.created_at,
           coalesce(al.payload ->> 'persona', pe.nombres || ' ' || pe.apellidos) as persona_nombre,
           coalesce(al.payload ->> 'sede', '—') as sede_codigo,
           case when pe.email is not null then array[pe.email] else '{}'::text[] end as destinatarios,
           case when pe.email is not null then array[pe.nombres || ' ' || pe.apellidos] else '{}'::text[] end as destinatarios_nombres
    from alertas al
    join personas pe on pe.id = al.persona_id
    where al.estado = 'pendiente'
      and al.created_at > now() - interval '2 days'
      and al.tipo in ('contrato_por_vencer', 'vacaciones_por_vencer')
  )
  select id, tipo, payload, persona_nombre, sede_codigo, destinatarios, destinatarios_nombres
  from combinado
  order by created_at;
$fn$;

revoke all on function fn_alertas_email_pendientes() from public, anon, authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (358, 'el_aviso_de_alertas_aprende_dos_audiencias')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_alertas_email_pendientes') as fn_sigue_existiendo,
  (select pg_get_functiondef('fn_alertas_email_pendientes'::regproc)) like '%union all%' as tiene_las_dos_ramas;
