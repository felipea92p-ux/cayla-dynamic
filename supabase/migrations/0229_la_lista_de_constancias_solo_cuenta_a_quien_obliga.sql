-- ============================================================================
-- 0229 — La lista de constancias solo cuenta a quien el Reglamento obliga
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que `fn_sin_constancia_del_reglamento` —la lista de a quién hay que
-- perseguir— cuente únicamente a las personas a las que el Reglamento se les
-- aplica.
--
-- ── QUÉ ESTABA MAL ──────────────────────────────────────────────────────────
--
-- Contaba a todas las personas activas. El 12-08-2026, con el Reglamento
-- publicado y una sola constancia dejada, devolvía **24** cuando las que faltan
-- son **20**: metía en la cuenta a las locadoras de servicios y a quien no es
-- trabajadora.
--
-- El artículo 2.1 no deja lugar a dudas:
--
--   «Este Reglamento es de aplicación obligatoria para todas las personas que
--    mantienen con CAYLA un CONTRATO DE TRABAJO…»
--
-- Quien no tiene contrato de trabajo no está obligada por el Reglamento, así
-- que no tiene constancia que dejar. Ponerla en una lista de pendientes es
-- pedirle a Desarrollo Organizacional que persiga cuatro firmas que no existen
-- — y una lista de pendientes que nunca llega a cero se deja de mirar.
--
-- ── DE DÓNDE SALE EL CRITERIO ───────────────────────────────────────────────
--
-- No se inventa aquí: es el mismo `estado = 'activo' and en_planilla is true`
-- con el que `fn_documentos_vigentes` calcula la población de la pantalla de
-- Normas. Por eso la pantalla decía «1 de 21» mientras esta función contaba
-- sobre 25: eran dos respuestas distintas a la misma pregunta, que es
-- exactamente lo que el CLAUDE.md prohíbe.
--
-- ── QUÉ NO SE TOCA, Y POR QUÉ ───────────────────────────────────────────────
--
-- `fn_reglamento_no_acusado`, el candado individual, queda igual. Sería
-- razonable que a una locadora le respondiera «el Reglamento no se le aplica»
-- en vez de «falta su constancia» —y hay un argumento fuerte para ello: un memo
-- disciplinario contra una locadora es, por sí solo, un indicio de
-- subordinación, que es justo lo que la 0182 se escribió para evitar—. Pero eso
-- cambia A QUIÉN frena el sistema y por qué, y esa es una decisión de Felipe,
-- no un efecto colateral de arreglar un número.
--
-- Mientras tanto el candado se queda del lado seguro: si alguien intentara
-- sancionar a una locadora, la frena igual.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Restaurando el cuerpo de la 0228. No toca datos.
--
-- md5 de partida (pedirlo a PRODUCCIÓN, no al Postgres local):
--   fn_sin_constancia_del_reglamento  eb518360d999b73b642bd05288115783  (0228)
-- ============================================================================

create or replace function fn_sin_constancia_del_reglamento()
returns table(persona_id uuid, motivo text)
language sql stable security definer set search_path = public as $$
  select p.id, fn_reglamento_no_acusado(p.id, fn_hoy_lima())
  from personas p
  where p.estado = 'activo'
    -- ART. 2.1: el Reglamento obliga a quien tiene contrato de trabajo. Mismo
    -- criterio que usa fn_documentos_vigentes para la población de Normas.
    and p.en_planilla is true
    and fn_reglamento_no_acusado(p.id, fn_hoy_lima()) is not null
    -- Solo lo ve quien puede actuar sobre un expediente. Es una lista de quién
    -- no ha firmado algo: no es secreta, pero tampoco es de todos.
    and fn_es_admin_o_lider() is true;
$$;

comment on function fn_sin_constancia_del_reglamento() is
  'Quien tiene contrato de trabajo (art. 2.1) y no tiene constancia del Reglamento vigente hoy, para avisar en Disciplina antes de empezar un procedimiento (numeral 60.5).';

grant execute on function fn_sin_constancia_del_reglamento() to authenticated, service_role;
revoke execute on function fn_sin_constancia_del_reglamento() from public;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (229, 'la_lista_de_constancias_solo_cuenta_a_quien_obliga')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
--
-- `en_la_lista` es el número que Desarrollo Organizacional tiene que perseguir,
-- y ahora debe coincidir con el «faltan N» de la pantalla de Normas. Antes de
-- esta migración salía 24; debería salir 20.
--
-- `sobre_activas` es lo que contaba antes, y se muestra al lado a propósito: la
-- diferencia entre los dos números son las personas sin contrato de trabajo.
--
-- OJO CON UNA COSA: no se llama a `fn_sin_constancia_del_reglamento()` aquí. Esa
-- función exige `fn_es_admin_o_lider()`, y en el SQL Editor no hay sesión de
-- nadie: devolvería 0 y parecería que la lista se rompió. Se repite su condición
-- a mano, que es lo que de verdad se quiere medir.
select
  (select count(*) from personas p
    where p.estado = 'activo'
      and p.en_planilla is true
      and fn_reglamento_no_acusado(p.id, fn_hoy_lima()) is not null)         as en_la_lista,
  (select count(*) from personas p
    where p.estado = 'activo'
      and fn_reglamento_no_acusado(p.id, fn_hoy_lima()) is not null)         as sobre_activas,
  (select count(*) from personas
    where estado = 'activo' and en_planilla is true)                         as con_contrato_de_trabajo,
  (select count(*) from personas
    where estado = 'activo' and en_planilla is not true)                     as sin_contrato_de_trabajo;
