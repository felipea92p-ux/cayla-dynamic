-- ============================================================================
-- 0044 — Corrige el saldo de vacaciones y clasifica los movimientos de planilla
-- ============================================================================
-- BUG QUE CORRIGE (lo encontró Felipe 2026-07-20): el saldo salía NEGATIVO en
-- quienes simplemente usaron los días que les tocaban (Janis −6.8, Sandra −7.9,
-- Melany −9.7). La causa: 0043 comparaba los días ganados DESDE SU ÚLTIMO
-- ANIVERSARIO contra los días tomados en esa misma ventana. Pero unas vacaciones
-- tomadas en enero 2026 se ganaron el año ANTERIOR — se estaba cobrando un
-- retiro contra una alcancía que acababa de reiniciarse.
--
-- LA CUENTA CORRECTA ES ACUMULADA desde la fecha de ingreso:
--   dias_ganados  = 15 por cada año de servicio (prorrateado), SIN tope
--   dias_tomados  = todo lo registrado en su historia, hasta la fecha de corte
--   saldo         = ganados − tomados
-- Un saldo negativo pasa a ser información REAL y útil: significa que tomó días
-- por adelantado (caso Chiara, "vacaciones adelantadas"), no un error de conteo.
--
-- El monto pasa a ser "lo que le toca por los días que tiene PENDIENTES"
-- (saldo/15 × medio sueldo × factor), que es lo accionable al momento de pagar.
-- Se topa en 0: no existe un pago negativo.

create or replace function fn_vacaciones_resumen(p_as_of date default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_as_of date;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver el resumen de vacaciones.';
  end if;
  v_as_of := coalesce(p_as_of, current_date);

  select coalesce(jsonb_agg(s.fila order by s.nombre), '[]'::jsonb) into v_out
  from (
    select
      (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id',          p.id,
        'nombre',              p.nombres || ' ' || p.apellidos,
        'fecha_ingreso',       p.fecha_ingreso,
        'aniversario_ini',     av.aniv_ini,
        'aniversario_next',    av.aniv_next,
        'dias_transcurridos',  gd.dias_transcurridos,
        'dias_ganados',        gd.dias_ganados,
        'dias_tomados',        gd.dias_tomados,
        'dias_saldo',          round(gd.dias_ganados - gd.dias_tomados, 1),
        'dias_con_marca',      coalesce(hm.dias_con_marca, 0),
        'horas_marcadas',      round(coalesce(hm.horas, 0), 2),
        'feriados_en_periodo', coalesce(fe.n, 0),
        'horas_feriados',      round(gd.horas_feriados, 2),
        'horas_base',          round(gd.base_horas, 2),
        'factor',              gd.factor,
        'salario',             sal.salario,
        -- Lo que le toca por sus días PENDIENTES. Topado en 0: no hay pago negativo.
        'monto_estimado',      case when sal.salario is not null
                                 then round(greatest(0,
                                        (sal.salario / 2) * gd.factor
                                        * (gd.dias_ganados - gd.dias_tomados) / 15.0
                                      ), 2)
                                 else null end
      ) as fila
    from personas p
    -- aniversario (solo informativo: el saldo ya NO depende de esta ventana)
    join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) av on true
    -- horas marcadas en el AÑO EN CURSO (desde su último aniversario): es la
    -- referencia del ritmo de trabajo con que se paga el descanso.
    left join lateral (
      select sum(j.horas_trabajadas) as horas,
             count(*) filter (where j.horas_trabajadas > 0) as dias_con_marca
      from jornadas j
      where j.persona_id = p.id
        and j.fecha between av.aniv_ini and v_as_of
        and j.horas_trabajadas is not null and j.horas_trabajadas > 0
    ) hm on true
    left join lateral (
      select count(*) as n
      from feriados f
      where f.fecha between av.aniv_ini and v_as_of
        and not exists (
          select 1 from jornadas j2
          where j2.persona_id = p.id and j2.fecha = f.fecha
            and j2.horas_trabajadas is not null and j2.horas_trabajadas > 0
        )
    ) fe on true
    -- Días tomados en TODA su historia (no recortado a la ventana del aniversario):
    -- ésta es la corrección de fondo respecto de 0043.
    left join lateral (
      select coalesce(sum(
               greatest(0, (least(v.fecha_fin, v_as_of) - v.fecha_inicio) + 1)
             ), 0)::numeric as dias
      from vacaciones v
      where v.persona_id = p.id and v.fecha_inicio <= v_as_of
    ) vt on true
    -- días tomados dentro del año en curso: solo para descontarlos de la BASE de
    -- horas (esos días no se le pueden exigir trabajados)
    left join lateral (
      select coalesce(sum(
               greatest(0, (least(v.fecha_fin, v_as_of) - greatest(v.fecha_inicio, av.aniv_ini)) + 1)
             ), 0)::numeric as dias
      from vacaciones v
      where v.persona_id = p.id
        and v.fecha_inicio <= v_as_of and v.fecha_fin >= av.aniv_ini
    ) vv on true
    left join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        and a.vigente_desde <= v_as_of
        and (a.vigente_hasta is null or a.vigente_hasta >= v_as_of)
      order by a.vigente_desde desc limit 1
    ) sal on true
    join lateral (
      select
        (v_as_of - av.aniv_ini) as dias_transcurridos,
        -- ACUMULADO desde el ingreso, sin tope: 2 años de servicio = 30 días
        round(15.0 * greatest(0, (v_as_of - p.fecha_ingreso))::numeric / 365.0, 1) as dias_ganados,
        vt.dias as dias_tomados,
        (45.0 * greatest(0, (v_as_of - av.aniv_ini) - vv.dias)::numeric / 7.0) as base_horas,
        coalesce(
          coalesce(fe.n, 0)::numeric
            * coalesce(hm.horas, 0) / nullif(coalesce(hm.dias_con_marca, 0), 0)
        , 0) as horas_feriados
    ) g0 on true
    join lateral (
      select g0.dias_transcurridos, g0.dias_ganados, g0.dias_tomados,
             g0.base_horas, g0.horas_feriados,
             case when g0.base_horas > 0
               then round((coalesce(hm.horas, 0) + g0.horas_feriados) / g0.base_horas, 4)
               else 0 end as factor
    ) gd on true
    where p.estado = 'activo' and p.fecha_ingreso is not null
  ) s;

  return coalesce(v_out, '[]'::jsonb);
end;
$$;

grant execute on function fn_vacaciones_resumen(date) to authenticated;

-- ── Clasificar los movimientos de planilla ───────────────────────────────────
-- Felipe pidió un desplegable con bono / descuento / vacaciones / otros.
-- DECISIÓN DE DISEÑO: NO se agregan valores nuevos a `tipo`. `tipo` gobierna la
-- ARITMÉTICA (bono suma, descuento resta) y cambiarlo obligaría a tocar la
-- función que calcula la planilla — dinero que ya se está pagando. En su lugar
-- se agrega `categoria`, que solo ETIQUETA el movimiento. Así el desplegable
-- muestra las cuatro opciones y el cálculo del total queda intacto:
--   Bono → (bono, null) · Descuento → (descuento, null)
--   Vacaciones → (bono, 'vacaciones') · Otros → (bono, 'otros')
-- Para restar siempre se usa Descuento.
alter table movimientos_planilla add column if not exists categoria text;
alter table movimientos_planilla drop constraint if exists movimientos_categoria_valida;
alter table movimientos_planilla add constraint movimientos_categoria_valida
  check (categoria is null or categoria in ('vacaciones', 'otros'));

-- Versión con categoría. Se agrega como sobrecarga (6 argumentos) para no romper
-- la de 5 que ya existe y está en uso.
create or replace function fn_agregar_movimiento(
  p_periodo_id uuid,
  p_persona_id uuid,
  p_tipo text,
  p_concepto text,
  p_monto numeric,
  p_categoria text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_estado text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar movimientos.';
  end if;
  select estado into v_estado from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  if p_tipo is null or p_tipo not in ('bono', 'descuento') then
    raise exception 'Tipo inválido (bono o descuento).';
  end if;
  if p_categoria is not null and p_categoria not in ('vacaciones', 'otros') then
    raise exception 'Categoría inválida.';
  end if;
  if p_concepto is null or length(trim(p_concepto)) < 2 then
    raise exception 'El concepto es obligatorio.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a 0.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;

  insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria, creado_por)
  values (p_periodo_id, p_persona_id, p_tipo, trim(p_concepto), round(p_monto, 2),
          nullif(trim(coalesce(p_categoria, '')), ''), fn_persona_actual_id());
end;
$$;

grant execute on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text) to authenticated;
revoke execute on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text) from public, anon;
