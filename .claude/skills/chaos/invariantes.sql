-- Invariantes de /chaos: lo que tiene que ser cierto en la base después de cualquier
-- ataque. Es UN solo select y solo lee. Cada fila que devuelve es una violación.
--
--   psql -h 127.0.0.1 -p 55890 -U postgres -d postgres -At -F '|' -f .claude/skills/chaos/invariantes.sql
--
-- No repite lo que ya garantiza una restricción: los solapes de periodos, ausencias y
-- sueldos son EXCLUDE, la foto de planilla cuadra por `chk_foto_cuadra` y una marca
-- anulada, una ausencia anulada o una corrección exigen autor y motivo por CHECK. Aquí va lo que ninguna
-- restricción ve.
--
-- gravedad: 1 estado imposible · 2 dato malo en silencio · sospecha (se confirma a mano
-- antes de afirmar nada: puede tener una explicación legítima).
with marcas_vivas as (
  select id, persona_id, tipo, timestamp_marca,
         coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date) as fecha
    from marcajes
   where anulada_at is null
)
select 'INV-01' as invariante, '1' as gravedad,
       'marca viva sin jornada' as que, m.persona_id::text as persona, m.fecha::text as detalle
  from marcas_vivas m
 where not exists (select 1 from jornadas j where j.persona_id = m.persona_id and j.fecha = m.fecha)
union all
select 'INV-02', '1', 'jornada imposible', j.persona_id::text,
       j.fecha::text || ' entrada ' || coalesce(j.entrada_ts::text, '-') || ' salida ' || coalesce(j.salida_final_ts::text, '-')
  from jornadas j
 where j.salida_final_ts < j.entrada_ts or j.horas_trabajadas < 0
union all
select 'INV-03', '1', 'dos liquidaciones vigentes', l.persona_id::text, count(*)::text || ' versiones vigentes'
  from liquidacion_pagada l
 where l.anulada is not true
   and not exists (select 1 from liquidacion_pagada a
                    where a.persona_id = l.persona_id and a.anulada and a.anula_version = l.version)
 group by l.persona_id
having count(*) > 1
union all
select 'INV-04', '1', 'periodo pagado sin fecha de pago', p.id::text, p.fecha_ini::text || ' a ' || p.fecha_fin::text
  from periodos_planilla p
 where p.estado = 'pagado' and p.pagado_at is null
union all
select 'INV-05', 'sospecha', 'doble marca en menos de 10 segundos', a.persona_id::text, a.tipo::text || ' ' || a.timestamp_marca::text
  from marcas_vivas a
  join marcas_vivas b
    on b.persona_id = a.persona_id and b.tipo = a.tipo and b.id <> a.id
   and b.timestamp_marca >= a.timestamp_marca
   and b.timestamp_marca <  a.timestamp_marca + interval '10 seconds'
union all
select 'INV-06', 'sospecha', 'movimiento creado después de pagar el periodo', m.persona_id::text,
       m.concepto || ' ' || m.created_at::text
  from movimientos_planilla m
  join periodos_planilla p on p.id = m.periodo_id
 where p.estado = 'pagado' and m.created_at > p.pagado_at
union all
select 'INV-07', 'sospecha', 'planilla pagada después del cese con liquidación vigente', d.persona_id::text,
       p.fecha_ini::text || ' total ' || d.total::text
  from planilla_pagada_detalle d
  join periodos_planilla p on p.id = d.periodo_id
  join liquidacion_pagada l on l.persona_id = d.persona_id and l.anulada is not true
 where d.total > 0 and p.fecha_ini > l.fecha_cese
order by 1, 4;
