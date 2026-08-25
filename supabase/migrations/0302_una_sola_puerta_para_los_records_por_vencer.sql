-- ============================================================================
-- 0302 — Una sola puerta para los récords por vencer.
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que quede UNA función `fn_vacaciones_por_vencer` en la base, y no dos con el
--   mismo nombre respondiendo distinto a la misma pregunta.
--
-- ── QUÉ PASÓ, PORQUE CONVIENE QUE QUEDE ESCRITO ─────────────────────────────
--
--   El 2026-08-25 dos sesiones construyeron la misma función el mismo día, sin
--   saber la una de la otra:
--
--     0299 · fn_vacaciones_por_vencer(p_dias_aviso int default 90)
--     0297 · fn_vacaciones_por_vencer(p_dias int default 60, p_as_of date)
--
--   Las dos se fusionaron a `main` y las dos se pegaron en producción. Como sus
--   firmas difieren, Postgres no protestó: las guardó como dos funciones
--   distintas con el mismo nombre. Se descubrió contando funciones después de
--   pegar la 0297 — salieron cuatro donde debían salir tres.
--
--   Nada se rompió, y ese es justamente el problema: dos puertas para la misma
--   pregunta, con ventanas distintas (90 días contra 60) y alcances distintos
--   (solo DO contra DO, encargada y cada persona), conviviendo en silencio hasta
--   que alguien note que la pantalla y el contador no dicen lo mismo.
--
-- ── POR QUÉ SE QUEDA LA DE LA 0297 ──────────────────────────────────────────
--
--   Decidido por Felipe el 2026-08-25, y no por antigüedad sino por lo que cada
--   una hace:
--
--     · avisa a 60 días, que es lo que decidió ese mismo día;
--     · la ven los tres —DO todo, la encargada su sede, cada persona la suya—,
--       que también se decidió ese día. La de la 0299 es solo para DO;
--     · quien ya tiene un récord VENCIDO sale siempre, aunque su próximo
--       vencimiento esté a un año: sin eso desaparecía de la lista justo la
--       persona más urgente;
--     · y viene con la corrección de `records_vencidos` en la hoja de cese, que
--       contaba récords sin gozar y los llamaba vencidos.
--
--   Lo que la 0299 hizo mejor, y queda dicho para que no se pierda: fue la
--   primera en señalar que `fn_vacaciones_resumen` no la mostraba ninguna
--   pantalla. Eso sigue siendo cierto y sigue sin resolverse.
--
-- QUÉ ASUME
--   · Que la 0297 está aplicada (lo está: pegada el 2026-08-25 y verificada).
--   · Que nadie llama a la versión de un solo argumento. Comprobado en el
--     repositorio: la única llamada era la de `admin/ausencias`, y ya apunta a
--     la que se queda.
--
-- QUÉ MUEVE
--   Ningún pago, ninguna fila. Retira una función que hoy no llama nadie.
--
-- CÓMO SE REVIERTE
--   Volver a pegar la `0299`, tal cual. Al tener otra firma, convive con la de
--   la 0297 sin conflicto — que es exactamente cómo llegamos acá.
-- ============================================================================

-- Por firma y no por nombre: el `drop` sin argumentos fallaría con «function
-- name is not unique», y el que lleva la firma equivocada se llevaría por
-- delante la que queremos conservar.
drop function if exists public.fn_vacaciones_por_vencer(int);

do $comprobar$
declare v_n int;
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_vacaciones_por_vencer';

  if v_n <> 1 then
    raise exception
      'Debería quedar exactamente UNA fn_vacaciones_por_vencer y quedaron %. '
      'No sigas: mira sus firmas con pg_get_function_identity_arguments antes de tocar nada.', v_n;
  end if;

  raise notice '0302 · queda una sola fn_vacaciones_por_vencer, la de la 0297.';
end $comprobar$;

insert into migraciones_aplicadas (numero, nombre)
values (302, 'una_sola_puerta_para_los_records_por_vencer')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
