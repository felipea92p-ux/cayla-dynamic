-- ============================================================================
-- 0302 — Una sola fn_vacaciones_por_vencer
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_vacaciones_por_vencer` vuelva a ser UNA función. Hoy hay dos, y
--   llamarla revienta.
--
-- QUÉ ASUME
--   · Que la que se queda es la de la **0297** —`(p_dias int default 60,
--     p_as_of date default null)`—, por decisión de Felipe el 2026-08-25.
--   · Que la que sobra es la de la **0299**, `(p_dias_aviso int default 90)`.
--   · No se toca el cuerpo de ninguna, así que no hay md5 de partida: esto solo
--     quita una función y no reescribe la otra.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- En `main` conviven dos migraciones que definen la misma función con firmas
-- distintas, y **las dos están aplicadas** (`migraciones_aplicadas` tiene el 297
-- y el 299):
--
--     0297 · fn_vacaciones_por_vencer(p_dias int default 60, p_as_of date default null)
--     0299 · fn_vacaciones_por_vencer(p_dias_aviso int default 90)
--
-- No son la misma función renumerada: devuelven **columnas distintas**. La 0297
-- da `persona · sede · dias_pendientes · records_sin_gozar · records_vencidos`;
-- la 0299 da `nombre · dias_saldo · records_pendientes · ya_vencido`. Son dos
-- implementaciones paralelas del mismo aviso.
--
-- Como en las dos TODOS los argumentos tienen valor por defecto, una llamada de
-- un solo entero —`fn_vacaciones_por_vencer(90)`— encaja en ambas y Postgres se
-- niega: **«function fn_vacaciones_por_vencer(integer) is not unique»**. Eso es
-- lo que tiene el CI de `main` en rojo, y con él cualquier rama que salga de
-- ahí. Y si alguien pega las dos en producción, la pantalla de Ausencias
-- revienta igual al abrirse.
--
-- ── CÓMO PASÓ, QUE VALE LA PENA DEJARLO ESCRITO ─────────────────────────────
--
-- El commit que introdujo la 0299 dice «Renumerar a 0299 y 234: el 0298 lo
-- tenía otra rama» — esa otra rama es la que traía la 0298. Al renumerar quedó
-- el archivo anterior en su sitio, y como la firma había cambiado, el
-- `create or replace` no reemplazó nada: **creó una segunda sobrecarga**.
--
-- Es exactamente el riesgo que `CLAUDE.md` describe para las funciones que
-- devuelven `TABLE`: cambiarles la firma exige `drop function` antes del
-- `create`, o la anterior sigue viva al lado.
--
-- ── QUÉ CAMBIA ──────────────────────────────────────────────────────────────
--
-- Se quita la sobrecarga de un argumento. La de la 0297 no se toca.
--
-- Y se comprueba después: si al quitarla no quedara ninguna, esta migración
-- **aborta con un mensaje que dice qué falta**, en vez de dejar la base sin la
-- función y que se descubra al abrir la pantalla. Ese caso solo puede darse en
-- una base donde se pegó la 0299 y no la 0297.
--
-- ── LO QUE ESTA MIGRACIÓN NO DECIDE ─────────────────────────────────────────
--
-- Los archivos de la 0299 y su prueba se quedan donde están: su número está
-- registrado en `migraciones_aplicadas` y borrarlos abriría un hueco sin
-- explicar. Lo que se ajusta aparte, fuera de esta migración, es lo que leía la
-- forma que se va: la pantalla de Ausencias y la prueba 234.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   Pegar de nuevo el bloque `create or replace function` de la 0299. No toca
--   tablas ni datos: revertir no pierde nada.
--
-- ============================================================================

drop function if exists fn_vacaciones_por_vencer(int);

do $$
begin
  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'fn_vacaciones_por_vencer'
  ) then
    raise exception 'Al quitar la sobrecarga sobrante no quedó ninguna fn_vacaciones_por_vencer. Esta base tenía la 0299 pero no la 0297: pega la 0297 antes que esta.';
  end if;
end
$$;


insert into migraciones_aplicadas (numero, nombre)
values (302, 'una_sola_fn_vacaciones_por_vencer')
on conflict (numero) do nothing;
