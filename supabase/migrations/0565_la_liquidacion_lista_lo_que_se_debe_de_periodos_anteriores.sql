-- ============================================================================
-- 0565 · LA LIQUIDACIÓN LISTA LO QUE SE DEBE DE PERIODOS ANTERIORES
-- ============================================================================
--
-- QUÉ PROMETE
--   Una función de SOLO LECTURA, `fn_liquidacion_periodos_anteriores(persona,
--   fecha_cese)`, que devuelve —uno por fila— los periodos de planilla ANTERIORES
--   al del cese en los que esa persona trabajó y todavía no cobró, con lo que le
--   toca en cada uno. La pantalla de Liquidaciones lo pinta debajo del desglose:
--   «de dónde sale cada parte de lo que se le debe».
--
-- DE DÓNDE SALE
--   Medido en producción el 2026-10-29. Emily Rico y Milagritos Zarate cesaron el
--   29/10, que ya es el periodo NUEVO (29/10–28/11): su liquidación calcula solo
--   ese día (S/ 145) y el sueldo de 28/09–28/10, que sigue ABIERTO y las incluye
--   (S/ 438.42 y S/ 1 000.05 en la planilla), no aparece en ninguna parte de la
--   liquidación. Nada se les deja de pagar —la planilla de ese periodo lo paga—,
--   pero quien mira Liquidaciones ve S/ 145 y puede creer que eso es todo lo que
--   se les debe. Felipe pidió ver «todo lo que no se pagó, desglosado por periodo».
--
-- QUÉ ASUME
--   · «Pagado» es lo que ya decide `fn_fecha_en_periodo_pagado` (0323/0562): el
--     GRUPO de la persona (su vínculo) tiene ese periodo marcado pagado. No se
--     inventa otro criterio.
--   · El monto de cada periodo sale de `fn_planilla_calcular` —el mismo cálculo
--     que usa `fn_liquidacion` para el periodo del cese—, sobre el periodo
--     ENTERO: todos los periodos anteriores al cese están completos.
--   · Un periodo con total cero no se lista: no hay nada que mostrar.
--
-- QUÉ NO HACE (a propósito)
--   · NO CAMBIA NINGÚN MONTO. No toca `fn_liquidacion`, ni `fn_planilla_calcular`,
--     ni `liquidacion_pagada`. Lo que lista NO se suma al total de la liquidación:
--     ese dinero sale por la planilla de cada periodo. Sumarlo aquí lo pagaría
--     dos veces —al pagar la liquidación y al cerrar la planilla— y la planilla
--     no sabe descontar lo que una liquidación pagó de un periodo ANTERIOR al del
--     cese (la 0243/0244 solo lo hace con el periodo del cese). Esa alternativa
--     —que la liquidación pague todo y la planilla lo descuente— se descartó con
--     Felipe el 2026-10-29: reescribe `fn_planilla_calcular_nucleo`.
--   · Es una función NUEVA: no hay md5 de partida. Antes de crearla se comprobó
--     con `donde-vive.sh` que nadie la definía.
--
-- MEDIDO ANTES DE ESCRIBIRLA (producción, 2026-10-29, solo lectura)
--   Entre las cesadas con la liquidación sin pagar, el criterio de arriba lista
--   exactamente dos filas —Emily Rico y Milagritos Zarate, periodo 28/09–28/10,
--   abierto, S/ 438.42 y S/ 1 000.05—, y ninguna otra: sin falsos positivos.
--
-- CÓMO SE REVIERTE
--   `drop function fn_liquidacion_periodos_anteriores(uuid, date);` — nada la
--   llama salvo la pantalla de Liquidaciones, que sin ella simplemente no pinta
--   el bloque.
-- ============================================================================

create or replace function fn_liquidacion_periodos_anteriores(
  p_persona_id uuid,
  p_fecha_cese date default null
)
returns table (
  periodo_id uuid,
  fecha_ini  date,
  fecha_fin  date,
  estado     text,
  total      numeric
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_p    personas%rowtype;
  v_cese date;
begin
  -- Dentro, como las otras funciones de liquidación: un revoke se deshace la
  -- próxima vez que alguien conceda en masa (0076), un guard no. `is not true`:
  -- un null no pasa.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  v_cese := coalesce(p_fecha_cese, v_p.fecha_cese);
  if v_cese is null then
    raise exception 'Esa persona no tiene fecha de cese. Regístrala en Equipo antes de liquidar.';
  end if;

  return query
  select t.id, t.fecha_ini, t.fecha_fin, t.estado, t.total
    from (
      select pp.id, pp.fecha_ini, pp.fecha_fin, pp.estado::text as estado,
             round(coalesce((
               select (e->>'total')::numeric
                 from jsonb_array_elements(fn_planilla_calcular(pp.fecha_ini, pp.fecha_fin, pp.id) -> 'filas') e
                where (e->>'persona_id')::uuid = p_persona_id
             ), 0), 2) as total
        from periodos_planilla pp
       -- Periodos COMPLETOS anteriores al del cese: el del cese (y lo que sigue)
       -- ya lo calcula `fn_liquidacion`. Con `fecha_fin < v_cese` el periodo que
       -- contiene el cese queda fuera sin tener que buscarlo.
       where pp.fecha_fin < v_cese
         and pp.fecha_fin >= v_p.fecha_ingreso
         and not fn_fecha_en_periodo_pagado(pp.fecha_fin, p_persona_id)
    ) t
   where t.total > 0
   order by t.fecha_ini;
end;
$fn$;

revoke execute on function fn_liquidacion_periodos_anteriores(uuid, date) from public, anon;
grant  execute on function fn_liquidacion_periodos_anteriores(uuid, date) to authenticated;

comment on function fn_liquidacion_periodos_anteriores(uuid, date) is
  'Los periodos de planilla anteriores al del cese en los que la persona trabajó y todavía no cobró, con lo que le toca en cada uno (0565). '
  'Solo informativa: NO se suma a la liquidación, ese dinero sale por la planilla de cada periodo. Admin y líder DO.';

insert into migraciones_aplicadas (numero, nombre) values (565, 'la_liquidacion_lista_lo_que_se_debe_de_periodos_anteriores')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_liquidacion_periodos_anteriores') as una_sola_funcion,
  has_function_privilege('authenticated', 'fn_liquidacion_periodos_anteriores(uuid, date)', 'execute') as authenticated_ejecuta,
  has_function_privilege('anon', 'fn_liquidacion_periodos_anteriores(uuid, date)', 'execute') as anon_no,
  (select count(*) from migraciones_aplicadas where numero = 565 and nombre like 'la_liquidacion_lista%') as registrada;
