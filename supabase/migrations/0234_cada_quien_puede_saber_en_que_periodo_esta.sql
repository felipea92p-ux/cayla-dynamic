-- ============================================================================
-- 0234_cada_quien_puede_saber_en_que_periodo_esta.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que cualquier persona con sesión pueda LEER el calendario de periodos de
--   planilla: sus fechas y si está pagado. Nada más, y nada de nadie.
--
-- QUÉ ASUME
--   Que `periodos_planilla` sigue teniendo solo lo que tiene desde la 0025:
--   `fecha_ini`, `fecha_fin`, `estado`, `pagado_at`, `creado_por` y `created_at`.
--   Ningún monto, ninguna persona, ningún concepto. Lo que cobra cada quien vive
--   en otras tablas y en `fn_planilla_calcular`, que exige admin y no se toca.
--
-- POR QUÉ EXISTE
--
--   Para la pantalla «Lo mío» (/mio), donde cada integrante ve sus días
--   trabajados, sus horas y sus tardanzas. Esa pantalla tiene que abrirse en el
--   periodo con el que se le PAGA —del 29 al 28—, no en el mes calendario: si
--   mostrara del 1 al 30, su total no cuadraría nunca con su boleta y la
--   pantalla generaría la pregunta que venía a evitar.
--
--   Y ese tramo no se puede calcular en el navegador. El `CLAUDE.md` lo prohíbe
--   con todas las letras —«el periodo va del 29 al 28, leerlo de
--   `periodos_planilla`, nunca asumirlo»— y la razón está en el propio esquema:
--   el CHECK de la 0025 admite periodos de 20 a 46 días, así que la regla del
--   29 es la costumbre, no una garantía. Un periodo corto o corrido dejaría a la
--   pantalla mintiendo sin que nadie se entere.
--
--   Hasta hoy la única política de lectura era `periodos_select_admin_lider`.
--
-- POR QUÉ ES SEGURO ABRIRLA, Y POR QUÉ NO ES UN PRECEDENTE
--
--   Un periodo de planilla es un calendario de la empresa, no un dato de una
--   persona: dice del 29 de julio al 28 de agosto, y si ya se pagó. Todo el
--   equipo lo sabe igualmente — es el día que cobran.
--
--   Se abre la LECTURA y solo la lectura. La escritura sigue pasando por
--   `fn_crear_periodo`, `fn_periodo_pagado` y `fn_revertir_pago`, con sus
--   guardas intactas. Y no habilita nada de dinero: quien pida
--   `fn_planilla_calcular` sin ser admin sigue recibiendo una excepción, que es
--   lo que mide la prueba 91 desde julio.
--
-- CÓMO SE REVIERTE
--     drop policy if exists periodos_select_calendario on periodos_planilla;
--   Con eso vuelve a verlo solo DO, y la pantalla /mio se queda sin saber en qué
--   periodo está — habría que decidir entre mes calendario o ventana móvil.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final devuelve una fila con los dos `true`.
-- ============================================================================

-- Se AÑADE una política, no se reemplaza la que había: en Postgres las de SELECT
-- se suman con OR, así que DO sigue entrando por la suya. Dejar viva la vieja
-- también hace que revertir esto no le quite el acceso a nadie.
drop policy if exists periodos_select_calendario on periodos_planilla;
create policy periodos_select_calendario on periodos_planilla
  for select to authenticated
  using (true);

comment on table periodos_planilla is
  'El calendario de pago: del 29 al 28, con su estado. Lo lee cualquiera con sesión desde la 0234 —la pantalla /mio necesita saber en qué periodo está—; escribirlo sigue siendo solo por RPC.';

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (234, 'cada_quien_puede_saber_en_que_periodo_esta')
on conflict (numero) do nothing;


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Dos `true`: la política nueva existe, y la de DO sigue en su sitio.
select
  exists (select 1 from pg_policies
           where tablename = 'periodos_planilla'
             and policyname = 'periodos_select_calendario')      as la_puede_leer_cualquiera,
  exists (select 1 from pg_policies
           where tablename = 'periodos_planilla'
             and policyname = 'periodos_select_admin_lider')     as do_conserva_la_suya;
