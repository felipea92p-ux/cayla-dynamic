-- ============================================================================
-- 0354_alertas_encargada_por_correo.sql
-- ============================================================================
-- QUÉ PROMETE
--   Dos funciones nuevas, ninguna existente tocada:
--     · fn_alertas_email_pendientes() — para cada fila de `alertas` en estado
--       'pendiente', arma a quién avisar: la(s) encargada(s) activas de la
--       sede de la persona involucrada, con su correo.
--     · fn_marcar_alerta_resultado(id, exito, nota) — cierra esa fila como
--       'enviado' o 'fallido', con una nota si falló.
--   Las dos las llama /api/alertas-encargadas (ruta de servidor, con la llave
--   de servicio) desde un cron de Vercel. Esta migración no manda ningún
--   correo — solo prepara la cola para que algo externo pueda leerla.
--
-- QUÉ ASUME
--   Que "quién es la encargada de una sede" es el mismo criterio que ya usa
--   el resto del panel (Turnos, `esEncargada`): rol = 'supervisor_sede' o
--   `es_encargada_piso`, y `estado = 'activo'`. No se inventa un criterio
--   nuevo acá — si ese criterio cambia, cambia en un solo lugar y esta
--   función lo hereda con el próximo `CREATE OR REPLACE`.
--
-- ── POR QUÉ EXISTE, Y POR QUÉ IGNORA LA COLUMNA `canal` ─────────────────────
--
-- `alertas` se escribe desde la 0007 (fn_auto_cierre, reescrita 7 veces desde
-- entonces) con `canal = 'push'` — pensado para `push_tokens`, una tabla para
-- tokens de Expo que nunca tuvo una app móvil detrás. Nadie despachó nunca
-- una fila: `estado` se queda en 'pendiente' para siempre, y `push_tokens`
-- está vacía. `canal = 'email'` y `tipo = 'tardanza'` están en el CHECK desde
-- el día uno y jamás se usaron.
--
-- Hasta que exista una app con `push_tokens` real, todo pendiente se despacha
-- por correo — es el único camino de entrega que hoy existe de verdad. Por
-- eso esta función NO filtra por `canal`: lee cualquier `estado = 'pendiente'`,
-- sin importar qué canal declaró. El día que `push` tenga un dispatcher real,
-- esta función se ajusta para no duplicar el envío — no antes.
--
-- Y por lo mismo, esta primera vuelta avisa a la ENCARGADA sobre la persona
-- del `alertas.persona_id` — no a esa persona sobre sí misma (que era el
-- diseño original, pensado para su propio teléfono). Son audiencias
-- distintas; la de "avisarle a ella misma" queda fuera de este cambio.
--
-- ── POR QUÉ SOLO LAS ÚLTIMAS 48 H ────────────────────────────────────────────
--
-- `alertas` lleva acumulando filas 'pendiente' desde agosto sin que nadie las
-- lea. Si esta función las devolviera TODAS, el primer despacho le mandaría a
-- cada encargada un correo por cada auto-cierre de los últimos meses —ruido,
-- no aviso. Se acota a `created_at > now() - interval '2 days'`; las más
-- viejas quedan pendientes sin despachar. Si de verdad importa saldarlas,
-- es una decisión aparte —marcarlas 'fallido' a mano con un motivo— no algo
-- que este cambio debe decidir en silencio.
--
-- ── POR QUÉ NO SE RESTRINGE A `canal = 'email'` NI SE TOCA fn_auto_cierre ───
--
-- Se pudo haber cambiado fn_auto_cierre para que además inserte una fila
-- dirigida a la encargada. No se hizo: es una función con historia productiva
-- (7 reescrituras, la última en la 0327) y tocarla exige el protocolo de
-- md5 contra producción antes de escribir una sola línea (ver CLAUDE.md). Se
-- prefirió resolver "quién es la encargada" AL LEER, no al escribir —así el
-- dato ya escrito desde la 0007 se aprovecha tal cual, y fn_auto_cierre queda
-- exactamente como está.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_marcar_alerta_resultado(uuid, boolean, text);
--   drop function if exists fn_alertas_email_pendientes();
--   alter table alertas drop column if exists nota_fallo;
--   Ninguna fila de `alertas` se ve afectada: revertir vuelve a dejar la cola
--   sin lector, como estaba desde la 0007.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final.
-- ============================================================================

alter table alertas add column if not exists nota_fallo text;

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
  select
    al.id,
    al.tipo,
    al.payload,
    pe.nombres || ' ' || pe.apellidos,
    sd.codigo,
    coalesce(array_agg(distinct enc.email) filter (where enc.email is not null), '{}'),
    coalesce(array_agg(distinct (enc.nombres || ' ' || enc.apellidos)) filter (where enc.email is not null), '{}')
  from alertas al
  join personas pe on pe.id = al.persona_id
  join sedes sd on sd.id = pe.sede_base_id
  left join personas enc
    on enc.sede_base_id = pe.sede_base_id
   and enc.estado = 'activo'
   and (enc.rol = 'supervisor_sede' or enc.es_encargada_piso)
  where al.estado = 'pendiente'
    and al.created_at > now() - interval '2 days'
  group by al.id, al.tipo, al.payload, al.created_at, pe.nombres, pe.apellidos, sd.codigo
  order by al.created_at;
$fn$;

revoke all on function fn_alertas_email_pendientes() from public, anon, authenticated;

create or replace function fn_marcar_alerta_resultado(p_id uuid, p_exito boolean, p_nota text default null)
returns void
language plpgsql security definer set search_path = public
as $fn$
begin
  update alertas
  set estado = case when p_exito then 'enviado' else 'fallido' end,
      enviado_at = case when p_exito then now() else enviado_at end,
      nota_fallo = nullif(trim(coalesce(p_nota, '')), '')
  where id = p_id;

  if not found then
    raise exception 'Esa alerta (%) ya no existe.', p_id;
  end if;
end;
$fn$;

revoke all on function fn_marcar_alerta_resultado(uuid, boolean, text) from public, anon, authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (354, 'alertas_encargada_por_correo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.columns where table_name = 'alertas' and column_name = 'nota_fallo') as columna_nota_fallo,
  (select count(*) from pg_proc where proname = 'fn_alertas_email_pendientes') as fn_leer,
  (select count(*) from pg_proc where proname = 'fn_marcar_alerta_resultado') as fn_marcar;
