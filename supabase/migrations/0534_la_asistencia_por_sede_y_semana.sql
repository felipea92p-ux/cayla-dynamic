-- ============================================================================
-- 0534 · La asistencia por sede, semana y día de la semana
-- ============================================================================
-- QUÉ PROMETE
--
--   `fn_asistencia_serie(p_desde, p_hasta, p_sede_id)` devuelve, por cada
--   (sede, semana, día de la semana), lo que hace falta para dibujar tres
--   gráficos de tendencia en el Dashboard SIN que el navegador baje la tabla
--   `jornadas` entera (≈5 mil filas a 6 meses y PostgREST corta en 1 000):
--
--     · `dias_trabajados` — personas con entrada ese día en esa sede.
--     · `faltas`          — faltas SIN justificar (las que cuenta `fn_faltas`).
--     · `offsets`         — por cada día trabajado con horario conocido, los
--                           minutos entre la hora de entrada marcada y la
--                           esperada (negativo = llegó antes). Una lista
--                           por fila, no una mediana: así el navegador puede
--                           sumar semanas y calcular la mediana y el rango
--                           exactos de cualquier periodo, cosa que no se
--                           puede hacer promediando medianas.
--
--   Con esos tres números salen: asistencia sobre lo esperado (días
--   trabajados ÷ días trabajados + faltas), a qué hora llega cada sede frente
--   a su horario, y en qué día de la semana se llega más tarde.
--
-- QUÉ ASUME
--
--   · «Qué le tocaba trabajar» NO se vuelve a escribir aquí: las faltas salen
--     de `fn_faltas` (0414), que ya resuelve la cascada turno → horario por
--     día → días laborables, vacaciones, justificaciones, feriados y
--     suspensiones. Si esa cascada cambia, esta serie cambia con ella.
--   · La hora esperada sale de `jornadas.horario_aplicado` (0446), el horario
--     CON EL QUE se midió esa jornada. Una jornada anterior a la 0446 que
--     nadie recalculó no lo tiene: no entra a `offsets`, y la pantalla lo dice
--     («desde que se guarda el horario»), no lo grafica como cero.
--   · La sede es la sede BASE de la persona hoy (`personas.sede_base_id`), la
--     misma que usa `fn_faltas`. La base no guarda historia de la sede de
--     cada quien: una persona que cambió de sede arrastra su pasado a la
--     nueva. Se dice en la pantalla.
--   · Solo cuenta a quien `fn_faltas` cuenta hoy: activo, planilla o
--     practicante, sin sueldo fijo. Quien ya cesó desaparece de las series
--     pasadas (sesgo conocido; es el mismo de `fn_faltas`).
--   · Hasta ayer: el día de hoy no se cierra hasta que termina.
--
-- QUIÉN LA VE
--
--   Admin y DO ven todas las sedes; el líder de equipo (`supervisor_sede`)
--   solo la suya. Nadie más: ni siquiera una integrante su propia fila —esto
--   es un tablero de sede, no una consulta personal—. Es SECURITY DEFINER
--   porque lee `personas` y `jornadas` de varias personas, y por eso el
--   permiso se decide AQUÍ, con `is true` (un `null` no pasa como autorizado).
--
-- LO QUE NO ES
--
--   No es un ranking: no devuelve a nadie por nombre ni por id. Es lectura:
--   no cambia ninguna jornada ni ningún pago.
--
-- VOLUMEN (estimado, no medido)
--
--   4 sedes × 52 semanas × 7 días ≈ 1 450 filas por año, cada una con una
--   lista de ≤ 8 enteros. A 3 años ≈ 4 mil filas. Se pide una vez, al abrir
--   la pestaña de tendencias; no entra en el refresco de 30 s del Dashboard.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_asistencia_serie(date, date, uuid);
-- ============================================================================

create or replace function fn_asistencia_serie(
  p_desde date,
  p_hasta date,
  p_sede_id uuid default null
)
returns table (
  sede_codigo     text,
  semana          date,
  dia_semana      int,
  dias_trabajados int,
  faltas          int,
  offsets         int[]
)
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare
  v_rol  rol_usuario := fn_rol_actual();
  v_sede uuid        := fn_sede_actual_persona();
  v_hasta date       := least(p_hasta, (now() at time zone 'America/Lima')::date - 1);
begin
  -- Solo quien gestiona: DO/admin ven todo, el líder de equipo solo su sede.
  if not (coalesce(v_rol in ('admin', 'lider_do'), false)
          or coalesce(v_rol = 'supervisor_sede', false)) then
    return;
  end if;
  if p_desde is null or v_hasta is null or v_hasta < p_desde then
    return;
  end if;

  return query
  with medibles as (
    -- Las mismas personas que cuenta fn_faltas (0414), y solo las que quien
    -- pregunta puede ver.
    select pe.id as persona_id, s.id as sede_id, s.codigo as sede_codigo
    from personas pe
    join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo'
      and (pe.en_planilla = true or pe.tipo_vinculo = 'practicante')
      and pe.sueldo_fijo = false
      and (p_sede_id is null or s.id = p_sede_id)
      and (coalesce(v_rol in ('admin', 'lider_do'), false)
           or pe.sede_base_id = v_sede)
  ),
  trabajados as (
    select m.sede_codigo, j.fecha,
      -- minutos entre la entrada marcada y la esperada, solo si la jornada
      -- guardó con qué horario se midió y ese día no era descanso.
      case
        when j.horario_aplicado ? 'entrada'
         and coalesce((j.horario_aplicado ->> 'es_descanso')::boolean, false) = false
        then round(extract(epoch from (
               (j.entrada_ts at time zone 'America/Lima')::time
               - (j.horario_aplicado ->> 'entrada')::time)) / 60.0)::int
      end as offset_min
    from jornadas j
    join medibles m on m.persona_id = j.persona_id
    where j.fecha between p_desde and v_hasta
      and j.entrada_ts is not null
  ),
  sin_justificar as (
    select f.sede as sede_codigo, f.fecha
    from fn_faltas(p_desde, v_hasta) f
    where f.justificada is not true
      and f.sede in (select m.sede_codigo from medibles m)
      and f.persona_id in (select m.persona_id from medibles m)
  ),
  filas as (
    select t.sede_codigo, t.fecha, 1 as trabajado, 0 as falta, t.offset_min
    from trabajados t
    union all
    select g.sede_codigo, g.fecha, 0, 1, null::int
    from sin_justificar g
  )
  select
    x.sede_codigo,
    date_trunc('week', x.fecha)::date as semana,
    extract(dow from x.fecha)::int as dia_semana,
    sum(x.trabajado)::int as dias_trabajados,
    sum(x.falta)::int as faltas,
    coalesce(array_agg(x.offset_min order by x.offset_min) filter (where x.offset_min is not null), '{}'::int[]) as offsets
  from filas x
  group by x.sede_codigo, date_trunc('week', x.fecha)::date, extract(dow from x.fecha)::int
  order by 2, 1, 3;
end;
$$;

grant execute on function fn_asistencia_serie(date, date, uuid) to authenticated;
revoke execute on function fn_asistencia_serie(date, date, uuid) from public, anon;

comment on function fn_asistencia_serie(date, date, uuid) is
  'Asistencia por (sede, semana, día de la semana) para los gráficos de tendencia del Dashboard: días trabajados, faltas sin justificar y, por cada día trabajado con horario conocido, los minutos de la entrada marcada frente a la esperada. Hasta ayer; solo admin, DO y líder de equipo (su sede).';

insert into migraciones_aplicadas (numero, nombre)
values (534, 'la_asistencia_por_sede_y_semana')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';
