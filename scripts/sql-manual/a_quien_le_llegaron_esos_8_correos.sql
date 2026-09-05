-- ############################################################################
-- ####  ¿A QUIÉN LE LLEGARON LOS 8 CORREOS QUE YA SALIERON?  — SOLO LEE     ####
-- ############################################################################
--
-- Sigue a `las_alertas_de_resend_llegan.sql`. Ese primer corte trajo una
-- sorpresa: 8 alertas de tipo `auto_cierre` pasaron a `estado = 'enviado'`
-- el 2026-09-05 (todas con `ultimo_intento_at` ~03:10 UTC, un solo lote) — así
-- que Resend SÍ aceptó enviarlas. Eso no contesta la pregunta del hallazgo 10:
-- «¿a la casilla de quién?». Si `RESEND_FROM` sigue en el dominio sandbox
-- (`onboarding@resend.dev`), Resend solo entrega a la cuenta dueña de la API
-- key — así que un envío "exitoso" puede estar llegando siempre a la MISMA
-- persona (quien registró la cuenta de Resend) y nunca a la encargada real.
--
-- ESTA CONSULTA RESUELVE ESO DESDE LA BASE, sin necesitar el panel de Resend:
-- reconstruye a qué destinatarios apuntaba cada alerta ya enviada, con el
-- mismo criterio que usa la versión VIGENTE de `fn_alertas_email_pendientes`
-- (0362, que hereda el cambio de la 0359): la o las personas con
-- `rol = 'supervisor_sede'` o `es_encargada_piso`, activas, de la MISMA sede
-- que la persona cuyo auto-cierre disparó el aviso — MÁS el propio correo de
-- esa persona (0359: «el aviso también avisa al propio integrante»), que es
-- el único destinatario en sedes sin encargada dedicada, como CCO (Central no
-- es tienda: ahí no hay "encargada de piso", solo administración y DO).
-- La primera versión de este archivo no incluía el correo propio y por eso
-- mostraba destinatarios vacíos para CCO — corregido acá.
--
-- QUÉ MIRAR:
--   · Si `destinatarios` sale VACÍO para alguna fila, esa sede no tiene
--     encargada con correo activo — el correo no tenía a quién llegarle y
--     probablemente ni se intentó enviar (revisar `sinDestinatario` en la
--     respuesta de la ruta, no acá).
--   · Si TODOS los `destinatarios` de las 8 filas son el MISMO correo, y ese
--     correo es el que administra la cuenta de Resend (la que ves si entras a
--     resend.com/domains) — eso confirma la sospecha del hallazgo 10: Resend
--     entrega porque el destinatario coincide con el dueño de la cuenta, no
--     porque el dominio esté verificado para mandar a cualquiera.
--   · Si los correos son DISTINTOS y de dominios reales de las encargadas —
--     el hallazgo 10 está resuelto: hay un dominio propio verificado.
--
-- ES UN SOLO SELECT A PROPÓSITO: el SQL Editor de Supabase ejecuta solo la
-- última sentencia.
-- ############################################################################

select
  al.id as alerta_id,
  al.tipo,
  al.enviado_at,
  (pe.nombres || ' ' || pe.apellidos) as persona_del_auto_cierre,
  sd.codigo as sede,
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
where al.estado = 'enviado'
group by al.id, al.tipo, al.enviado_at, pe.nombres, pe.apellidos, pe.email, sd.codigo
order by al.enviado_at desc;
