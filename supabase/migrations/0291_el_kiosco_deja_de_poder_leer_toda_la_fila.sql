-- ============================================================================
-- 0291 · EL KIOSCO DEJA DE PODER LEER TODA LA FILA DE `personas`
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una sesión de terminal ya no pueda pedir, por REST directo, el
--   documento de identidad ni el sueldo base legal de nadie de su sede.
--
-- EL DEFECTO, EN UNA LÍNEA
--   `personas_select_terminal_roster` (la 0008) deja leer la FILA entera a
--   quien tenga una sesión de terminal — RLS filtra filas, no columnas. La
--   pantalla del terminal solo pide cuatro campos, pero el permiso alcanza
--   para pedir todos: `GET /rest/v1/personas?select=documento,sueldo_base_legal`
--   con el token de cualquier terminal sigue devolviendo esos datos hoy.
--
-- POR QUÉ IMPORTA
--   El terminal marca SIN PIN, a propósito (decisión de Felipe, jul-2026): el
--   control real es que la Mac mini está a la vista de todo el equipo, no una
--   clave. Eso significa que su token no es un secreto fuerte — y hoy ese
--   token alcanza para leer el DNI y el sueldo base de toda la sede, no solo
--   para marcar.
--
-- POR QUÉ SE PUEDE QUITAR YA, Y NO ES UN RIESGO NUEVO
--   Porque el reemplazo ya existe y ya está en uso. La 0285 construyó la vista
--   `terminal_roster`, que expone solo lo que el terminal necesita para
--   marcar, y `apps/web/lib/terminal/roster.ts` ya lee de esa vista — no de
--   `personas`. Verificado antes de escribir esta migración: no hay ningún
--   `.from("personas")` en el código del terminal, ni en roster.ts ni en
--   ningún otro archivo de `apps/web/app/(terminal)` ni `apps/web/lib/terminal`.
--   El propio comentario de la 0285 ya avisaba: la policy vieja se retiraría
--   «en una migración posterior, después de desplegar el frontend». Ese
--   frontend ya está desplegado; falta este paso.
--
-- QUÉ NO ROMPE
--   Se revisaron las otras tres políticas de SELECT sobre `personas` y
--   ninguna le da a una sesión de terminal acceso a filas ajenas por otro
--   camino: `personas_select_admin_lider` exige `fn_es_admin_o_lider()`,
--   `personas_select_supervisor` exige rol `supervisor_sede`, y
--   `personas_select_propia` solo deja ver la fila cuyo `auth_user_id`
--   coincide con quien pregunta — nunca la de otra persona. Sin la policy del
--   terminal, una sesión de terminal deja de tener CUALQUIER SELECT sobre
--   `personas`, y sigue teniendo el suyo sobre `terminal_roster`.
--
-- CÓMO SE REVIERTE
--   Volver a crear la policy con el texto de la 0008:
--     create policy personas_select_terminal_roster on personas for select
--       using (estado = 'activo' and fn_sede_actual_terminal() is not null
--             and (sede_base_id = fn_sede_actual_terminal() or visible_todas_sedes));
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final. Y en la Mac mini de cualquier sede: el terminal
--   sigue marcando exactamente igual, porque nunca dependió de esta policy.
-- ============================================================================

drop policy if exists personas_select_terminal_roster on personas;

insert into migraciones_aplicadas (numero, nombre)
values (291, '0291_el_kiosco_deja_de_poder_leer_toda_la_fila')
on conflict (numero) do nothing;

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select
  not exists (
    select 1 from pg_policies
    where tablename = 'personas' and policyname = 'personas_select_terminal_roster'
  ) as la_policy_vieja_ya_no_existe,
  (select count(*) from pg_policies where tablename = 'personas' and cmd = 'SELECT') as policies_select_que_quedan;
