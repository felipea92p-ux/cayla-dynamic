-- ============================================================================
-- 0377_las_alertas_de_antes_del_despacho_quedan_anotadas.sql
-- ============================================================================
-- QUÉ PROMETE
--   Dejar escrito, DENTRO de cada fila, por qué las alertas 'pendiente'
--   creadas antes de que existiera el despacho por correo (0354,
--   2026-09-03) se van a quedar así para siempre — sin cambiar `estado` ni
--   ningún otro dato de negocio. No hay ninguna aquí que "haya que arreglar":
--   es la deuda que la propia 0354 dejó a propósito, medida el 2026-09-05
--   (auditoría del 2026-09-03/04, crítico 10): 75 filas de tipo
--   'auto_cierre', la más vieja del 2026-06-28, todas con canal='push' e
--   `intentos = 0` — el despacho nunca las tocó.
--
-- QUÉ ASUME
--   Que `migraciones_aplicadas` tiene la fecha real en que la 0354 se aplicó
--   EN ESTA BASE (`aplicada_at`). Es la misma fuente que ya usa
--   `fn_alertas_despacho_resumen` (0362) para su `v_desde_despacho` — no se
--   repite la fecha como litera a mano una segunda vez.
--
-- POR QUÉ NO SE MARCAN 'fallido' (que es lo que sugería, sin saberlo, el
-- encabezado de la propia 0354: "si de verdad importa saldarlas... márcalas
-- 'fallido' a mano con un motivo")
--
--   Esa frase se escribió ANTES de que existiera `fn_alertas_despacho_resumen`
--   (0362, el mismo día). Su bucket `fallidas_definitivas` cuenta
--   `estado in ('fallido','procesando') and intentos >= 3` SIN filtro de
--   fecha — a propósito, para que una fila que de verdad agotó sus 3
--   reintentos HOY se vea siempre, sin caducar. Si esta migración marcara
--   estas 75 filas como 'fallido', aparecerían de golpe como "75 fallidas
--   definitivas" en la Bandeja de DO el mismo día que se pega — exactamente
--   el "falso positivo permanente en la pantalla que decide qué mira una
--   persona" que el propio encabezado de la 0362 nombra como "el peor error
--   de esta casa", el mismo problema que ya evitó una vez con la ventana de
--   `caducadas`. Se prefiere dejarlas `pendiente`: hoy son invisibles para
--   `fn_alertas_despacho_resumen` en las CUATRO categorías que devuelve
--   (no son `despachables` — created_at no cae en los últimos 7 días; no son
--   `atascadas` — no están `procesando`; no son `fallidas_definitivas` — no
--   están `fallido`/`procesando`; no son `caducadas` — created_at es anterior
--   a `v_desde_despacho`, la 0362 ya las excluye por nombre), y esta
--   migración no cambia eso.
--
-- QUÉ NO HACE
--   No toca `estado`, `enviado_at`, `leido_at` ni `intentos`. No borra
--   ninguna fila (CLAUDE.md: nada se borra). No repite el envío ni intenta
--   despacharlas — `fn_alerta_despachable` sigue diciendo que no son
--   candidatas, y eso no cambia acá.
--
-- ES IDEMPOTENTE: el `where nota_fallo is null` hace que una segunda pegada
-- no vuelva a tocar las filas ya anotadas, y una fila nueva que llegue a
-- cumplir la condición (no debería — el corte es una fecha fija del pasado)
-- tampoco se toca dos veces.
--
-- CÓMO SE REVIERTE
--   update alertas set nota_fallo = null
--    where nota_fallo like 'Backlog previo al despacho por correo%';
-- ============================================================================

update alertas
set nota_fallo = 'Backlog previo al despacho por correo (0354, 2026-09-03) — nunca fue candidata al envío: fn_alerta_despachable exige created_at de los últimos 7 días. Revisado y anotado el 2026-09-05 (auditoría 2026-09-03/04, crítico 10); no se reintenta ni se marca fallida a propósito, ver encabezado de la 0377.'
where estado = 'pendiente'
  and created_at < coalesce(
        (select ma.aplicada_at from migraciones_aplicadas ma where ma.numero = 354),
        timestamptz '2026-09-03 00:00:00-05'
      )
  and nota_fallo is null;

insert into migraciones_aplicadas (numero, nombre)
values (377, 'las_alertas_de_antes_del_despacho_quedan_anotadas')
on conflict (numero) do nothing;

-- ── Comprobación ─────────────────────────────────────────────────────────
-- No llama a fn_alertas_despacho_resumen(): exige fn_es_admin_o_lider(), que
-- mira auth.uid(), y el SQL Editor no trae un usuario autenticado — mismo
-- motivo que ya documentó las_alertas_de_resend_llegan.sql. Se lee la tabla
-- directo, con la misma fórmula que usa esa función para 'fallidas_definitivas'.
select
  (select count(*) from alertas
    where estado = 'pendiente'
      and created_at < coalesce((select ma.aplicada_at from migraciones_aplicadas ma where ma.numero = 354), timestamptz '2026-09-03 00:00:00-05')
      and nota_fallo like 'Backlog previo al despacho por correo%') as filas_anotadas,
  (select count(*) from alertas
    where estado in ('fallido', 'procesando') and intentos >= 3) as bandeja_fallidas_no_debe_subir;
