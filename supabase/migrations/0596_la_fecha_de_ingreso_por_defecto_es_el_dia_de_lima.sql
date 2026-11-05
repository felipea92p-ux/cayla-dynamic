-- ============================================================================
-- 0596 · LA FECHA DE INGRESO POR DEFECTO ES EL DÍA DE LIMA, NO EL DEL SERVIDOR
-- ============================================================================
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--   Que una persona dada de alta SIN fecha de ingreso queda con el día de hoy
--   EN LIMA, a cualquier hora. Antes quedaba con el día del servidor (UTC), que
--   desde las 19:00 hora peruana ya es mañana.
--
-- ── EL PROBLEMA ─────────────────────────────────────────────────────────────
--   `personas.fecha_ingreso` nació con `default current_date` (0001). El
--   servidor corre en UTC, así que entre las 19:00 y la medianoche de Lima ese
--   default da el día SIGUIENTE. `fn_crear_persona` no recibe fecha y confía en
--   el default, de modo que quien se daba de alta de noche «ingresaba mañana».
--
--   Eso era inofensivo hasta la 0594, que rechaza toda marca anterior a un
--   ingreso que todavía no llegó. Desde ahí, a esa persona:
--     · el terminal no la ofrece hasta el día siguiente,
--     · no se le puede registrar ni corregir una marca de hoy ni de antes.
--   Se vio primero en CI (no en producción: la 0594 aún no estaba pegada): la
--   corrida de `db-tests` del 2026-11-04 a las 20:31 hora de Lima rompió 19
--   pruebas, todas por el mismo motivo —«esa persona ingresa el 05/11/2026»—.
--
-- ── QUÉ CAMBIA ──────────────────────────────────────────────────────────────
--   `personas.fecha_ingreso` pasa a `default fn_hoy_lima()`. Nada más: ninguna
--   fila existente se toca, y quien ya tiene fecha la conserva. El mismo criterio
--   que ya dice el comentario de `fn_hoy_lima` (0091): usar siempre esa función
--   en vez de `current_date`.
--
-- ── ORDEN ───────────────────────────────────────────────────────────────────
--   Pegar ANTES o junto con la 0594. Si la 0594 se pega primero, las altas de
--   noche quedan «ingresando mañana» hasta que esta se pegue.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   alter table personas alter column fecha_ingreso set default current_date;
-- ============================================================================

set local lock_timeout = '3s';

alter table personas alter column fecha_ingreso set default fn_hoy_lima();

insert into migraciones_aplicadas (numero, nombre) values (596, 'la_fecha_de_ingreso_por_defecto_es_el_dia_de_lima')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
