-- ############################################################################
-- ####  ¿LAS ALERTAS DE RESEND ESTÁN LLEGANDO A ALGUIEN?  — SOLO LEE       ####
-- ############################################################################
--
-- Crítico 10 de la auditoría 2026-09-03/04: «Alertas de Resend sin llegar a
-- nadie» — SIN VERIFICAR. Este archivo es esa verificación, hecha una sola
-- vez contra producción, sin depender de que el panel nuevo (Bandeja, 0362)
-- ya esté desplegado: lee la tabla `alertas` directo, con la misma regla de
-- «despachable»/«atascada»/«caducada»/«fallida definitiva» que
-- `fn_alertas_despacho_resumen` usa en pantalla, para no inventar un segundo
-- criterio que después discrepe del que ve DO.
--
-- NO SE LLAMA A `fn_alertas_despacho_resumen()` AQUÍ A PROPÓSITO: exige
-- `fn_es_admin_o_lider()`, que mira `auth.uid()`, y el SQL Editor no trae un
-- usuario autenticado — reventaría con «Solo Desarrollo Organizacional puede
-- ver el estado del despacho de avisos.» Esta consulta llega al mismo dato
-- leyendo la tabla directo, que el rol de Postgres del SQL Editor sí puede.
--
-- QUÉ MIRAR EN EL RESULTADO:
--   · `nunca_se_envio_ningun_email` en TRUE es la respuesta corta al hallazgo: si es
--     así, ningún correo salió jamás desde que existe el despacho (0354,
--     2026-09-03) — ni uno solo, aunque el cron haya corrido cada día.
--   · `motivos_fallo_recientes` trae el texto exacto que Resend devolvió (via
--     `nota_fallo`, escrito por la ruta en cada intento). Si dice algo con
--     "verify a domain" o "403", el problema es el dominio de `RESEND_FROM`
--     sin verificar — `RESEND_FROM` cae a `onboarding@resend.dev` si la
--     variable no está puesta en Vercel, y ese remitente de prueba de Resend
--     solo entrega a la cuenta dueña de la API key, nunca a las encargadas.
--   · `filas_ultimos_30_dias = 0` con `filas_totales > 0` dice que el cron
--     dejó de correr o de encontrar pendientes — no es un problema de Resend,
--     es que no ha habido nada que despachar o el cron está caído.
--   · `filas_totales = 0` dice que nunca se generó ni una alerta — el defecto
--     estaría antes, en lo que llena `alertas` (auto-cierre, vencimientos),
--     no en el envío.
--
-- ES UN SOLO SELECT A PROPÓSITO: el SQL Editor de Supabase ejecuta solo la
-- última sentencia.
-- ############################################################################

select
  (select count(*) from alertas) as filas_totales,
  (select count(*) from alertas where created_at > now() - interval '30 days') as filas_ultimos_30_dias,
  (select count(*) from alertas where canal = 'email') as filas_canal_email,
  (select max(enviado_at) filter (where canal = 'email') from alertas) as ultimo_envio_exitoso_email,
  (select max(enviado_at) filter (where canal = 'email') is null
      and count(*) filter (where canal = 'email') > 0
     from alertas) as nunca_se_envio_ningun_email,
  (select count(*) from alertas where estado = 'pendiente') as pendientes_ahora,
  (select count(*) from alertas
    where estado = 'procesando'
      and coalesce(procesando_desde, '-infinity'::timestamptz) < now() - interval '1 hour'
      and intentos < 3
      and created_at > now() - interval '7 days') as atascadas_ahora,
  (select count(*) from alertas
    where estado in ('fallido', 'procesando') and intentos >= 3) as fallidas_definitivas_totales,
  (select count(*) from alertas
    where estado <> 'enviado' and enviado_at is null and intentos < 3
      and created_at <= now() - interval '7 days') as caducadas_totales,
  (select jsonb_agg(distinct nota_fallo)
     from alertas
    where nota_fallo is not null
      and created_at > now() - interval '30 days') as motivos_fallo_recientes,
  (select jsonb_agg(jsonb_build_object(
            'tipo', tipo, 'estado', estado, 'intentos', intentos,
            'creado', created_at, 'ultimo_intento', ultimo_intento_at,
            'nota', nota_fallo
          ) order by created_at desc)
     from alertas
    where created_at > now() - interval '14 days'
    limit 20) as ultimas_20_filas_detalle;
