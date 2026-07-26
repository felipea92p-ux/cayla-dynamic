-- ============================================================================
-- 0075 — La suspensión cae en días que la persona IBA A TRABAJAR
-- (Escrita como "0071" en la copia de iCloud y aplicada en producción DESPUÉS
-- de la 0071-0073 de main; se renumera a 0075 para que una base reconstruida
-- desde cero termine idéntica a producción. Ver commit 8cfedac.)
-- ----------------------------------------------------------------------------
-- EL PROBLEMA (visto el 25/07/2026 en la suspensión de Mateo): el panel calcula
-- los días de suspensión sumando días de CALENDARIO desde mañana
-- (disciplina/page.tsx: addDias(desde, dias - 1)). A Mateo le tocó un sábado, y
-- Mateo no trabaja los sábados.
--
-- Una suspensión sin goce de haber que cae en el día libre NO ES UNA SANCIÓN:
-- la persona no deja de trabajar nada que fuera a trabajar, ni deja de cobrar
-- nada que fuera a cobrar. Una "suspensión de 3 días" que en realidad son 2
-- está mal impuesta, y en una inspección se cae.
--
-- LA REGLA: los días de suspensión son días LABORABLES de esa persona. Tres
-- días de suspensión desde un jueves, trabajando de lunes a viernes, son
-- jueves, viernes y lunes — se salta el descanso, no se lo regala.
--
-- La cascada de "¿le tocaba trabajar?" NO se reinventa: es exactamente la misma
-- que ya usa fn_falta_contadores (mig. 0060) para decidir si un día sin marcas
-- es una falta. Se extrae a fn_es_dia_laborable para que las dos la compartan —
-- si alguna vez divergieran, el sistema diría que faltó un día en el que,
-- según la suspensión, no debía venir.
--
-- Reversible: soltar las dos funciones nuevas.
-- ============================================================================

-- ── ¿A esta persona le tocaba trabajar este día? ────────────────────────────
-- Prioridad: el turno puntual manda; si no hay, el horario por día; si no,
-- los días laborables del tramo. Un feriado sin turno asignado no se trabaja.
create or replace function fn_es_dia_laborable(p_persona_id uuid, p_fecha date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with ev as (
    select (t.persona_id is not null) as hay_turno,
           coalesce(t.es_descanso, false) as turno_desc,
           tr.horario_por_dia as hpd,
           tr.dias_laborables as dl
    from (select 1) _
    left join turnos t on t.persona_id = p_persona_id and t.fecha = p_fecha
    left join lateral (
      select h.horario_por_dia, h.dias_laborables
      from horarios_asignados h
      where h.persona_id = p_persona_id
        and h.vigente_desde <= p_fecha
        and (h.vigente_hasta is null or h.vigente_hasta >= p_fecha)
      order by h.vigente_desde desc limit 1
    ) tr on true
  )
  select coalesce(
    (select (case when ev.hay_turno then not ev.turno_desc
                  when ev.hpd is not null then (ev.hpd ? (extract(dow from p_fecha)::int::text))
                  when ev.dl is not null then (extract(dow from p_fecha)::int = any(ev.dl))
                  else false end)
            and not (exists (select 1 from feriados f where f.fecha = p_fecha) and not ev.hay_turno)
     from ev),
    false);
$$;

grant execute on function fn_es_dia_laborable(uuid, date) to authenticated;

-- ── Los N días laborables de una suspensión, desde una fecha ────────────────
-- Devuelve las fechas concretas para que el panel las muestre y el memo las
-- imprima. Si p_desde no es laborable, arranca en el siguiente que sí lo sea:
-- el panel avisa del salto, pero el resultado nunca queda mal puesto.
--
-- El tope de 120 días de búsqueda es un cortafuegos, no una regla: alguien sin
-- horario vigente no tiene ningún día laborable y la búsqueda no terminaría.
create or replace function fn_dias_suspension(p_persona_id uuid, p_desde date, p_dias int)
returns table (fecha date)
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_cur date := p_desde; v_n int := 0; v_guarda int := 0;
begin
  if p_dias is null or p_dias < 1 then
    raise exception 'Los días de suspensión deben ser al menos 1.';
  end if;

  while v_n < p_dias and v_guarda < 120 loop
    if fn_es_dia_laborable(p_persona_id, v_cur) then
      fecha := v_cur;
      return next;
      v_n := v_n + 1;
    end if;
    v_cur := v_cur + 1;
    v_guarda := v_guarda + 1;
  end loop;

  if v_n < p_dias then
    raise exception 'No se encontraron % días laborables para esta persona en los próximos 120 días. ¿Tiene un horario vigente?', p_dias;
  end if;
end;
$$;

grant execute on function fn_dias_suspension(uuid, date, int) to authenticated;

-- ── Las fechas EXACTAS, no solo el rango ────────────────────────────────────
-- Saltarse los descansos hace que los días dejen de ser contiguos: jueves,
-- viernes y lunes. Imprimir eso como "del 23 al 27" mete en la sanción dos días
-- en los que la persona sí podía estar en su casa — el memo estaría afirmando
-- algo falso sobre el alcance del castigo. Se guardan las fechas una por una.
alter table expediente_disciplinario
  add column if not exists suspension_fechas date[];

-- ── Fijar la suspensión de un borrador, en un solo paso ─────────────────────
-- El cálculo vive en la base, no en el panel: es lo que determina cuántos días
-- deja de cobrar una persona, y no puede depender de qué pantalla lo pida.
create or replace function fn_expediente_set_suspension(p_id uuid, p_dias int, p_desde date)
returns table (fecha date)
language plpgsql
security definer
set search_path = public
as $$
declare r expediente_disciplinario%rowtype; v_fechas date[];
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede ajustar la suspensión de un borrador (estado actual: %).', r.estado;
  end if;
  if r.nivel <> 'suspension' then
    raise exception 'Este documento no es una suspensión.';
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso sobre este documento.';
  end if;

  select array_agg(d.fecha order by d.fecha) into v_fechas
  from fn_dias_suspension(r.persona_id, p_desde, p_dias) d;

  update expediente_disciplinario
    set suspension_dias = p_dias,
        suspension_fechas = v_fechas,
        suspension_desde = v_fechas[1],
        suspension_hasta = v_fechas[array_length(v_fechas, 1)]
    where id = p_id;

  return query select unnest(v_fechas) order by 1;
end;
$$;

grant execute on function fn_expediente_set_suspension(uuid, int, date) to authenticated;

notify pgrst, 'reload schema';
