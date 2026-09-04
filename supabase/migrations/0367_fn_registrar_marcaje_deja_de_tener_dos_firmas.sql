-- ============================================================================
-- 0367 — fn_registrar_marcaje deja de tener dos firmas (arregla un daño de la 0353)
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que en producción exista UNA sola versión de
-- fn_registrar_marcaje — la de 9 argumentos que trajo la 0353
-- (con `p_confirmo_sin_refrigerio`) — y no dos conviviendo.
--
-- EL DEFECTO, encontrado el 2026-09-04 desde el propio terminal de CENTRAL:
-- el marcaje dejó de funcionar para todo el mundo, con este error en los
-- logs del terminal —
--
--   Could not choose the best candidate function between:
--   public.fn_registrar_marcaje(... 8 argumentos, termina en p_motivo_otro),
--   public.fn_registrar_marcaje(... 9 argumentos, termina en
--     p_confirmo_sin_refrigerio)
--
-- — y confirmado contra producción con
--
--   select p.oid, pg_get_function_identity_arguments(p.oid)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'fn_registrar_marcaje';
--
-- que devolvió DOS filas: oid 17929 (8 argumentos, la de antes de la 0353) y
-- oid 22654 (9 argumentos, la de la 0353). La 0353 SÍ trae, en su propio
-- encabezado, un `drop function if exists ...` de la firma vieja de 8
-- argumentos — con la advertencia explícita de que sin ese drop quedarían
-- las dos conviviendo — pero ese `drop` no llegó a aplicarse en producción
-- (solo el `create or replace` de la nueva). No se puede saber desde acá por
-- qué —pegado parcial, corte a mitad de ejecución—; no hace falta saberlo
-- para arreglarlo.
--
-- El efecto no fue "una marca se ve rara": PostgREST manda los argumentos de
-- un `.rpc()` con nombre, y casi ninguna marca real trae
-- `p_confirmo_sin_refrigerio` (solo la trae cuando el modal de refrigerio de
-- la 0353 se disparó) — así que para casi cualquier marca, de cualquier
-- persona, en cualquier sede, PostgREST no podía decidir entre las dos
-- firmas y rechazaba el `insert` entero. Es el mismo defecto de fondo que ya
-- le pasó a este repo con `fn_vacaciones_por_vencer` el 2026-08-25: dos
-- funciones con el mismo nombre, la última con todos sus argumentos por
-- default, conviviendo en silencio hasta que alguien las llama sin el último.
--
-- QUÉ ASUME: que la de 9 argumentos (oid 22654) es la única que debe quedar
-- viva — es la que trae `confirmo_sin_refrigerio`, y ningún llamador de este
-- repo (terminal, Correcciones, la cola offline) apunta a la de 8. No hace
-- falta volver a definir su cuerpo: ya está en producción y funciona sola en
-- cuanto deja de competir con la otra.
--
-- POR QUÉ SE ELIGIÓ ASÍ (solo el drop, sin `create or replace`): esta función
-- ya tiene 9 versiones en el historial y otra sesión (0366, sin fusionar
-- todavía) está trabajando sobre el cuerpo de la 0353 al mismo tiempo. Repetir
-- ese cuerpo acá sería una décima copia y un riesgo de pisar ese trabajo por
-- numeración. Esta migración no toca el cuerpo de nada — solo borra la firma
-- sobrante — así que no compite con ella.
--
-- SE REVIERTE: no hace falta. La firma de 8 argumentos no la usa ningún
-- código de este repo; si hiciera falta recuperarla, su cuerpo exacto está en
-- supabase/migrations/0327_el_candado_de_horas_pasa_a_ser_por_grupo.sql.
--
-- Es un DROP de una firma sobrante, no una reescritura de cuerpo: no aplica
-- la comprobación de md5 de partida (esa es para cuando se copia un `prosrc`
-- para reescribirlo). Sí conviene, antes de pegar esto, volver a correr la
-- consulta del encabezado de arriba y confirmar que las dos firmas siguen
-- ahí — si alguien ya la arregló a mano entre que se escribió esto y que se
-- pega, el `if exists` hace que sea inofensivo pegarla de todas formas.
-- ============================================================================

drop function if exists public.fn_registrar_marcaje(
  uuid, tipo_marca, timestamp with time zone, uuid, origen_marca, uuid, uuid, text
);

insert into migraciones_aplicadas (numero, nombre)
values (367, 'fn_registrar_marcaje_deja_de_tener_dos_firmas')
on conflict (numero) do nothing;
