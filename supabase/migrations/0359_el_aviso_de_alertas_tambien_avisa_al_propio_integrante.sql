-- ============================================================================
-- 0359 — El aviso de alertas también le llega al propio integrante
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: `fn_alertas_email_pendientes` (0354) hoy solo arma los
-- destinatarios con la(s) encargada(s) de la sede. Esta migración agrega, en
-- esos mismos dos arreglos, el correo y el nombre de la PROPIA persona
-- involucrada en la alerta — decisión explícita de Felipe (2026-09-03): que
-- quien se auto-cerró también se entere, no solo quien la supervisa.
--
-- QUÉ ASUME: que `personas.email` puede venir vacío (no todo integrante tiene
-- correo cargado) — en ese caso simplemente no se agrega nada, igual que ya
-- pasa hoy si una sede no tiene ninguna encargada con correo. Y que la misma
-- persona puede ser, a la vez, la afectada Y la encargada de su propia sede
-- (un caso real: una supervisor_sede que se auto-cierra su propio día) — para
-- que eso no le mande el mismo correo dos veces, el arreglo final se dedupea
-- con `array(select distinct ... from unnest(...))`.
--
-- POR QUÉ ASÍ (y no reescribir la consulta entera): un solo cambio aditivo
-- sobre la forma que ya existe — se agrega `pe.email` al `group by` (es
-- funcionalmente dependiente de `pe.id`, que ya está en el join; Postgres no
-- lo sabe solo y lo exige explícito) y cada arreglo de salida se concatena
-- con el correo/nombre de `pe` antes de dedupear. Ninguna otra línea del
-- cuerpo de la 0354 se toca: ni el filtro de 48 h, ni el criterio de quién es
-- encargada, ni `fn_marcar_alerta_resultado`, ni `/api/alertas-encargadas`.
--
-- SE REVIERTE: `CREATE OR REPLACE FUNCTION` con el cuerpo exacto de la 0354.
--
-- md5 de partida (Postgres LOCAL, no producción) — fn_alertas_email_pendientes: 45172bb22cd1e1840c19c9201d51bac1
-- Esta función nació en la 0354 y, a la fecha de escribir esto, la 0354
-- todavía no se ha pegado en producción (docs/estado.md no la marca «PEGADA
-- Y VERIFICADA») — así que lo más probable es que este md5 ni siquiera
-- exista todavía en producción. Confírmalo con donde-vive.sh antes de pegar
-- esta migración: si la función no existe, hay que pegar la 0354 primero.
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
  select
    al.id,
    al.tipo,
    al.payload,
    pe.nombres || ' ' || pe.apellidos,
    sd.codigo,
    -- ⇩⇩⇩ CAMBIO 0359 ⇩⇩⇩ se agrega el correo de la propia persona (pe.email)
    -- al arreglo de encargadas, y se dedupea por si es, a la vez, su propia
    -- encargada de sede.
    array(
      select distinct x from unnest(
        coalesce(array_agg(distinct enc.email) filter (where enc.email is not null), '{}')
        || case when pe.email is not null then array[pe.email] else '{}'::text[] end
      ) as x
    ),
    array(
      select distinct x from unnest(
        coalesce(array_agg(distinct (enc.nombres || ' ' || enc.apellidos)) filter (where enc.email is not null), '{}')
        || case when pe.email is not null then array[pe.nombres || ' ' || pe.apellidos] else '{}'::text[] end
      ) as x
    )
  from alertas al
  join personas pe on pe.id = al.persona_id
  join sedes sd on sd.id = pe.sede_base_id
  left join personas enc
    on enc.sede_base_id = pe.sede_base_id
   and enc.estado = 'activo'
   and (enc.rol = 'supervisor_sede' or enc.es_encargada_piso)
  where al.estado = 'pendiente'
    and al.created_at > now() - interval '2 days'
  -- ⇩⇩⇩ CAMBIO 0359 ⇩⇩⇩ pe.email se agrega al group by: es funcionalmente
  -- dependiente de pe.id (ya presente vía el join), pero Postgres exige que
  -- toda columna no agregada esté explícita en el group by.
  group by al.id, al.tipo, al.payload, al.created_at, pe.nombres, pe.apellidos, pe.email, sd.codigo
  order by al.created_at;
$fn$;

revoke all on function fn_alertas_email_pendientes() from public, anon, authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (359, 'el_aviso_de_alertas_tambien_avisa_al_propio_integrante')
on conflict (numero) do nothing;
