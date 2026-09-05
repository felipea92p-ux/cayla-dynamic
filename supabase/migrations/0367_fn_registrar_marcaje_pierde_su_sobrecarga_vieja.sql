-- ============================================================================
-- 0367 — fn_registrar_marcaje pierde su sobrecarga vieja (arregla un daño de la 0353)
-- ----------------------------------------------------------------------------
-- PROMETE: que vuelva a existir UNA sola versión de fn_registrar_marcaje en
--   producción — la de 9 argumentos (con p_confirmo_sin_refrigerio) que trajo
--   la 0353 — sin tocar su cuerpo ni su lógica de negocio.
--
-- ASUME: 0353 y el resto hasta la 0363.
--
-- QUÉ PASÓ. La 0353 agregó un parámetro nuevo a fn_registrar_marcaje —pasó de
--   8 a 9 argumentos— y, precisamente para evitar el accidente de
--   fn_vacaciones_por_vencer (2026-08-25, dos funciones con el mismo nombre,
--   "function ... is not unique"), su propio texto trae un
--   `drop function if exists ...(uuid, tipo_marca, timestamp with time zone,
--   uuid, origen_marca, uuid, uuid, text)` justo antes del `create or replace`
--   de la firma nueva. Ese DROP no llegó a tomar efecto en producción — el
--   porqué exacto no se pudo determinar sin acceso de servicio a producción,
--   y no hace falta para corregirlo: el síntoma en pantalla lo confirma sin
--   ambigüedad.
--
--   El resultado, reportado por Felipe el 2026-09-04: el terminal y el panel
--   de Correcciones ("Registrarla con su hora" sobre una marca apartada, que
--   llama a fn_registrar_marcaje posicional con 8 argumentos desde
--   fn_resolver_marca_apartada, 0304) empezaron a fallar con «Could not
--   choose the best candidate function» / «function ... is not unique» en
--   cualquier llamada que no mande p_confirmo_sin_refrigerio — es decir,
--   prácticamente todas: retorno_almuerzo, salida_almuerzo, y la resolución
--   de marcas apartadas. Bloqueaba marcar Y bloqueaba repararlo.
--
-- POR QUÉ SOLO EL DROP Y NADA MÁS. La función de 9 argumentos ya está bien:
--   es la que trajo la 0353, con su lógica y su grant correctos. Lo único que
--   falta es retirar la sobrecarga vieja que quedó viva por error — el mismo
--   DROP que la 0353 ya tenía escrito. No hace falta reescribir el cuerpo ni
--   arriesgar su md5 de producción por una razón que no es esa.
--
-- CÓMO SE REVIERTE: no se revierte — recrear la sobrecarga de 8 argumentos
--   sería reintroducir el mismo accidente a propósito. Si algún llamador
--   externo dependiera de la firma vieja (ninguno detectado en este repo:
--   todos los llamadores internos —terminal, Correcciones, la cola offline—
--   pasan por la de 9, que acepta los mismos 8 primeros argumentos porque el
--   noveno tiene DEFAULT NULL), se corrige ese llamador, no esta migración.
-- ============================================================================

drop function if exists public.fn_registrar_marcaje(
  uuid, tipo_marca, timestamp with time zone, uuid, origen_marca, uuid, uuid, text
);

insert into migraciones_aplicadas (numero, nombre)
values (367, 'fn_registrar_marcaje_pierde_su_sobrecarga_vieja')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
-- Debe devolver UNA sola fila: la de 9 argumentos.
select oid::regprocedure, pronargs
from pg_proc
where proname = 'fn_registrar_marcaje';
