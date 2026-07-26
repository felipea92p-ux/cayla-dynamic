-- ============================================================================
-- CONSULTA DE IMPACTO — ¿cuánto cambia la grati/CTS al aplicar la regla legal
-- de regularidad sobre la sobretasa de feriados trabajados?
-- ----------------------------------------------------------------------------
-- SOLO LEE. No modifica nada. Pegar en el SQL Editor de Supabase y ver el
-- resultado. Es para decidir CON EL NÚMERO A LA VISTA antes de cambiar el
-- cálculo, tal como pediste.
--
-- LA REGLA QUE SE EVALÚA (Ley 27735 y D.S. 001-97-TR): un concepto variable
-- —como el pago adicional por trabajar un feriado— entra a la remuneración
-- computable de la gratificación y de la CTS SOLO si la persona lo percibió
-- en al menos TRES MESES del semestre. Cuando entra, se suma lo percibido en
-- el semestre y se divide entre SEIS (es un promedio, no el total).
--
-- CÓMO LEER EL RESULTADO:
--   meses_con_feriado  → en cuántos meses distintos del semestre cobró sobretasa
--   cumple_regularidad → si es 'sí', ese promedio DEBE entrar al cálculo
--   promedio_a_sumar   → cuánto se agregaría a la base de su grati/CTS
--   Si la última columna dice 'no suma nada', para esa persona no cambia nada.
--
-- OJO: esto mide el semestre en curso (enero–junio o julio–diciembre según la
-- fecha de hoy). Para ver el otro semestre, cambia las dos fechas de abajo.
-- ============================================================================

with parametros as (
  -- Semestre en curso, en hora de Lima.
  select
    case when extract(month from (now() at time zone 'America/Lima')::date) <= 6
         then make_date(extract(year from (now() at time zone 'America/Lima')::date)::int, 1, 1)
         else make_date(extract(year from (now() at time zone 'America/Lima')::date)::int, 7, 1)
    end as desde,
    case when extract(month from (now() at time zone 'America/Lima')::date) <= 6
         then make_date(extract(year from (now() at time zone 'America/Lima')::date)::int, 6, 30)
         else make_date(extract(year from (now() at time zone 'America/Lima')::date)::int, 12, 31)
    end as hasta
),
-- Días de feriado efectivamente trabajados por cada persona en el semestre.
feriados_trabajados as (
  select
    j.persona_id,
    date_trunc('month', j.fecha)::date as mes,
    j.fecha,
    j.horas_trabajadas
  from jornadas j
  join feriados f on f.fecha = j.fecha
  cross join parametros p
  where j.fecha between p.desde and p.hasta
    and j.entrada_ts is not null
    and coalesce(j.horas_trabajadas, 0) > 0
),
-- Valor de la SOBRETASA de cada uno de esos días, al salario vigente ese día.
-- La sobretasa es el pago ADICIONAL por trabajar el feriado (el pago triple se
-- compone de: el día que ya se paga + el trabajado + la sobretasa del 100%).
sobretasa as (
  select
    ft.persona_id,
    ft.mes,
    sum(round(
      (asal.salario_mensual_soles / (6.5 * 30.0)) * least(ft.horas_trabajadas, 6.5)
    , 2)) as monto_mes
  from feriados_trabajados ft
  left join lateral (
    select a.salario_mensual_soles from asignaciones_salario a
    where a.persona_id = ft.persona_id
      and a.vigente_desde <= ft.fecha
      and (a.vigente_hasta is null or a.vigente_hasta >= ft.fecha)
    order by a.vigente_desde desc limit 1
  ) asal on true
  where asal.salario_mensual_soles is not null
  group by ft.persona_id, ft.mes
),
resumen as (
  select
    s.persona_id,
    count(distinct s.mes) as meses_con_feriado,
    sum(s.monto_mes)      as total_semestre,
    round(sum(s.monto_mes) / 6.0, 2) as promedio_entre_6
  from sobretasa s
  group by s.persona_id
)
select
  pe.nombres || ' ' || pe.apellidos                        as colaboradora,
  sd.codigo                                                as sede,
  r.meses_con_feriado,
  'S/ ' || to_char(r.total_semestre, 'FM9990.00')          as cobrado_en_el_semestre,
  case when r.meses_con_feriado >= 3 then 'sí' else 'no' end as cumple_regularidad,
  case when r.meses_con_feriado >= 3
       then 'S/ ' || to_char(r.promedio_entre_6, 'FM9990.00')
       else 'S/ 0.00' end                                  as promedio_a_sumar,
  case when r.meses_con_feriado >= 3
       then 'Su grati y CTS suben: se agrega S/ ' || to_char(r.promedio_entre_6, 'FM9990.00') || ' a la base'
       else 'no suma nada (solo ' || r.meses_con_feriado || ' mes(es), la ley pide 3)'
  end                                                      as efecto
from resumen r
join personas pe on pe.id = r.persona_id
join sedes    sd on sd.id = pe.sede_base_id
order by (r.meses_con_feriado >= 3) desc, r.promedio_entre_6 desc nulls last;

-- Si esta consulta no devuelve ninguna fila, significa que en el semestre en
-- curso nadie trabajó un feriado: aplicar la regla no cambiaría ningún pago
-- hoy, y conviene implementarla igual para que quede correcta hacia adelante.
