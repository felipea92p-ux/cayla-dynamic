-- ============================================================================
-- 0334_desempeno_suma_ausencias_del_periodo.sql
-- ============================================================================
-- QUÉ PROMETE
--   Un agregado de solo lectura —cuántos días de ausencia tuvo cada persona en
--   un rango, y de qué tipo— para que "Desempeño del equipo" (/admin/horas)
--   deje de ser el único de los cuatro indicadores de gestión (tardanzas,
--   ausentismo, antigüedad, cumplimiento de objetivos) que no muestra.
--
-- QUÉ ASUME
--   Nada nuevo. Una función nueva. No toca `ausencias`, `tipos_ausencia` ni
--   ninguna función existente.
--
-- ── POR QUÉ HACÍA FALTA ──────────────────────────────────────────────────────
--
-- `fn_ausencias(p_desde, p_hasta, p_persona_id)` (0101) ya existe, pero
-- devuelve una fila POR AUSENCIA, no un total por persona. Sumarlas en el
-- cliente para treinta personas en un año sería traer y sumar en TypeScript lo
-- que Postgres ya sabe agregar, y —peor— dejaría el criterio de "qué cuenta"
-- (rango solapado, no anulada, recortado a los bordes del periodo) escrito dos
-- veces: una en la base y otra en la pantalla, con el riesgo de que diverjan.
--
-- Tardanzas ya tiene su propio agregado (`fn_tardanzas_resumen`, 0311) y
-- objetivos también (`fn_objetivos_resumen`, 0032). Ausencias era el único de
-- los cuatro sin uno — no porque nadie lo necesitara, sino porque hasta ahora
-- nadie lo había pedido en esta forma.
--
-- ── POR QUÉ RECORTADO AL RANGO, IGUAL QUE `fn_vacaciones_saldo` ─────────────
--
-- Una ausencia de once días que empieza tres días antes de `p_desde` no debe
-- contar los once — solo los que caen dentro del periodo que se está mirando.
-- Mismo `least(fecha_fin, p_hasta) - greatest(fecha_inicio, p_desde) + 1` que
-- ya usa `fn_vacaciones_saldo` (0297) para lo mismo.
--
-- ── POR QUÉ EL DESGLOSE TRAE EL NOMBRE DEL TIPO, NO SU CÓDIGO ────────────────
--
-- La pantalla que va a consumir esto no carga hoy el catálogo `tipos_ausencia`
-- (no lo necesitaba). Pedirle que lo cargue aparte solo para traducir
-- `descanso_medico` a "Descanso médico" es una consulta más por algo que la
-- función ya puede resolver con un join que ya hace. Se paga acá, una vez.
--
-- ── MISMA VISIBILIDAD QUE `fn_ausencias`, A PROPÓSITO ────────────────────────
--
-- Copiado literal de 0101: admin/líder ven a cualquiera, la encargada de sede
-- solo a la suya, cada persona a sí misma. Dos criterios de "quién ve a quién"
-- para el mismo dato es exactamente el tipo de grieta que costó la 0277 en
-- otro sitio (columna y tramo divergentes) — acá se evita copiando el mismo
-- criterio en vez de inventar uno nuevo "parecido".
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_ausencias_resumen(date, date);
--   Revertir solo apaga la columna nueva de "Desempeño": ninguna ausencia,
--   liquidación ni saldo depende de esta función.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final.
-- ============================================================================

create or replace function fn_ausencias_resumen(p_desde date, p_hasta date)
returns table (persona_id uuid, dias_total int, registros int, por_tipo jsonb)
language sql stable security definer set search_path = public as $fn$
  select a.persona_id,
         sum(least(a.fecha_fin, p_hasta) - greatest(a.fecha_inicio, p_desde) + 1)::int as dias_total,
         count(*)::int as registros,
         jsonb_object_agg(
           t.nombre,
           least(a.fecha_fin, p_hasta) - greatest(a.fecha_inicio, p_desde) + 1
         ) as por_tipo
  from ausencias a
  join personas pe on pe.id = a.persona_id
  join tipos_ausencia t on t.codigo = a.tipo
  where a.anulada_at is null
    and daterange(a.fecha_inicio, a.fecha_fin, '[]') && daterange(p_desde, p_hasta, '[]')
    and (fn_es_admin_o_lider()
         or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona())
         or a.persona_id = fn_persona_actual_id())
  group by a.persona_id;
$fn$;

comment on function fn_ausencias_resumen(date, date) is
  'Total de días de ausencia por persona en un rango, recortado a sus bordes, con desglose por tipo. Lee `ausencias`; no la reemplaza ni la recalcula. Misma visibilidad que fn_ausencias (0101): admin/líder todas, encargada su sede, cada persona la suya.';

grant execute on function fn_ausencias_resumen(date, date) to authenticated;
revoke execute on function fn_ausencias_resumen(date, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (334, 'desempeno_suma_ausencias_del_periodo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select count(*) as fn_creada from pg_proc where proname = 'fn_ausencias_resumen';
