-- ============================================================================
-- 0359 — El aviso de auto-cierre también le llega al propio integrante
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: dentro de la Rama 1 de `fn_alertas_email_pendientes` (la que
-- la 0358 dejó explícitamente igual a la 0354 — auto_cierre, tardanza,
-- salida_no_retornada, digest_diario), el correo y el nombre de la PROPIA
-- persona involucrada se agregan a los mismos dos arreglos que ya llevan a
-- la(s) encargada(s) — decisión explícita de Felipe (2026-09-03): que quien
-- se auto-cerró también se entere, no solo quien la supervisa.
--
-- La Rama 2 (contrato_por_vencer / vacaciones_por_vencer, 0356/0357) NO se
-- toca: ya manda directo a `al.persona_id` por diseño de la 0358 — agregarle
-- esto sería una segunda vez la misma cosa, no una mejora.
--
-- ESTA MIGRACIÓN SE ESCRIBE SOBRE EL CUERPO DE LA 0358, NO SOBRE EL DE LA
-- 0354: mientras se escribía esta migración, otra sesión (`claude/cola-
-- alertas-vencimiento`) fusionó a `main` la 0356/0357/0358, que reestructuró
-- `fn_alertas_email_pendientes` en un `with combinado as (... union all ...)`
-- para separar "avisa a la encargada" de "avisa directo a la persona, ya
-- decidido al escribir". Copiar del cuerpo viejo de la 0354 habría revertido
-- esa reestructuración en silencio — el mismo patrón 0297/0299 que ya
-- documenta CLAUDE.md. Este archivo se reescribió por completo después de
-- confirmar con `git show origin/main:...0358...sql` cuál es el cuerpo
-- vigente.
--
-- QUÉ ASUME: lo mismo que ya asumía la versión anterior de esta migración —
-- `personas.email` puede venir vacío, y la misma persona puede ser a la vez
-- la afectada Y su propia encargada de sede (se dedupea con
-- `array(select distinct ... from unnest(...))`).
--
-- SE REVIERTE: `CREATE OR REPLACE FUNCTION` con el cuerpo exacto de la 0358.
--
-- md5 de partida (Postgres LOCAL, no producción) — fn_alertas_email_pendientes
-- TAL COMO QUEDÓ EN LA 0358 (no en la 0354): pídelo con donde-vive.sh justo
-- antes de pegar. La 0358 en sí, a la fecha de escribir esto, todavía no
-- está confirmada como pegada en producción (docs/estado.md no la marca) —
-- si no lo está, esta migración incluye su misma lógica, así que pegar solo
-- la 0359 alcanza; si ya la pegaron, donde-vive.sh lo va a decir y esta
-- migración la reemplaza limpio (mismo cuerpo, con la Rama 1 extendida).
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
           ) as destinatarios_nombres
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
    -- CAMBIO 0359: pe.email se agrega al group by (funcionalmente
    -- dependiente de pe.id, ya presente vía el join).
    group by al.id, al.tipo, al.payload, al.created_at, pe.nombres, pe.apellidos, pe.email, sd.codigo

    union all

    -- Rama 2 (0356/0357) — SIN CAMBIOS: el destinatario YA es `al.persona_id`,
    -- decidido al escribir. No hay encargada que buscar, y agregar a la
    -- propia persona otra vez no tendría sentido: ya es la única destinataria.
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
values (359, 'el_aviso_de_alertas_tambien_avisa_al_propio_integrante')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_alertas_email_pendientes') as fn_sigue_existiendo,
  (select pg_get_functiondef('fn_alertas_email_pendientes'::regproc)) like '%union all%' as tiene_las_dos_ramas;
