-- ############################################################################
-- ####  ¿A QUIÉN LE PASA HOY?  — SOLO LEE, NO ESCRIBE NADA                ####
-- ############################################################################
--
-- Para qué. La auditoría del 2026-08-14 dejó ~40 hallazgos medidos EN EL
-- LABORATORIO. Un hallazgo de laboratorio no es un hallazgo hasta que se sabe
-- qué persona real cae en él — esa lección costó cinco falsas alarmas en un día,
-- incluida una que se dio por viva porque el veredicto metía un campo
-- informativo en la misma condición que el dinero.
--
-- Esto le aplica a cada uno el único filtro que decide si vale la pena
-- arreglarlo: ¿HAY ALGUIEN HOY a quien le pueda pasar?
--
-- Se lee así:  ⚠ = hay gente, hay que mirarlo  ·  ✓ = existe el defecto, pero
-- no tiene a quién pasarle en CAYLA hoy
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- Y va contra las TABLAS, no contra funciones de diagnóstico: cinco de ellas
-- devuelven cero filas en el Editor por el guard de admin, y cero filas se lee
-- igual que «no hay nada».
-- ############################################################################

with per as (
  select id, fecha_ini, fecha_fin from periodos_planilla
  where (now() at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  order by fecha_ini desc limit 1
),
d as (select coalesce((select fecha_ini from per), date '1900-01-01') as ini,
             coalesce((select fecha_fin from per), date '1900-01-01') as fin),
h(orden, hallazgo, quienes) as (

  select 1, 'Liquidación pagada + persona ACTIVA → puede devengar dos veces',
         (select string_agg(p.nombres||' '||p.apellidos, ' · ')
            from liquidacion_pagada l join personas p on p.id = l.persona_id
           where l.anulada is not true and p.estado = 'activo')

  union all select 2, 'Vacaciones truncas: quién lleva 1 AÑO o más (pierde récords anteriores)',
         (select string_agg(p.nombres||' '||p.apellidos, ' · ')
            from personas p
           where p.estado='activo' and p.en_planilla is true
             and p.fecha_ingreso <= (now() at time zone 'America/Lima')::date - 365)

  union all select 3, 'Sigue en tipo_vinculo=prueba pasado el mes → no devenga NADA',
         (select string_agg(p.nombres||' '||p.apellidos, ' · ')
            from personas p
           where p.estado='activo' and p.tipo_vinculo = 'prueba'
             and p.fecha_ingreso <= (now() at time zone 'America/Lima')::date - 31)

  union all select 4, 'Cesada con movimiento en el periodo → EsSalud y asig. familiar fantasma',
         (select string_agg(distinct p.nombres||' '||p.apellidos, ' · ')
            from movimientos_planilla m join personas p on p.id = m.persona_id, per
           where m.periodo_id = per.id and p.estado <> 'activo')

  union all select 5, 'Educación asignada a quien NO tiene tramo de salario → sin tope',
         (select string_agg(distinct p.nombres||' '||p.apellidos, ' · ')
            from asignaciones_educacion e join personas p on p.id = e.persona_id
           where not exists (select 1 from asignaciones_salario a
                              where a.persona_id = p.id and a.vigente_hasta is null))

  union all select 6, 'Desembolsos con ventana «vacaciones» → nadie los lee, se pagan otra vez',
         (select string_agg(distinct p.nombres||' '||p.apellidos||' ('||b.ventana||')', ' · ')
            from desembolsos_beneficios b join personas p on p.id = b.persona_id
           where b.ventana = 'vacaciones')

  union all select 7, 'Cambio de sueldo DENTRO del periodo → sobretiempo mal valorado',
         (select string_agg(distinct p.nombres||' '||p.apellidos, ' · ')
            from asignaciones_salario a join personas p on p.id = a.persona_id, d
           where a.vigente_desde > d.ini and a.vigente_desde <= d.fin)

  union all select 8, 'Vacaciones con marcaje encima → el día se paga DOS veces',
         (select string_agg(distinct p.nombres||' '||p.apellidos, ' · ')
            from vacaciones v join personas p on p.id = v.persona_id
            join jornadas j on j.persona_id = v.persona_id
              and j.fecha between v.fecha_inicio and v.fecha_fin and j.horas_trabajadas > 0, d
           where v.fecha_inicio <= d.fin and v.fecha_fin >= d.ini and j.fecha between d.ini and d.fin)

  union all select 9, 'Ausencia PAGABLE registrada → se pagará S/0.00',
         (select string_agg(distinct p.nombres||' '||p.apellidos||' ('||a.tipo||')', ' · ')
            from ausencias a join personas p on p.id = a.persona_id
            join tipos_ausencia t on t.codigo = a.tipo and t.paga is true, d
           where a.anulada_at is null and a.fecha_inicio <= d.fin and a.fecha_fin >= d.ini
             and p.en_planilla is true and a.tipo <> 'vacaciones')

  union all select 10, 'En planilla SIN régimen de pensión → no se le retiene nada',
         (select string_agg(p.nombres||' '||p.apellidos, ' · ')
            from personas p
           where p.estado='activo' and p.en_planilla is true and p.regimen_pension is null)

  union all select 11, 'En planilla SIN cuenta bancaria → no se le puede transferir',
         (select string_agg(p.nombres||' '||p.apellidos, ' · ')
            from personas p left join datos_personales dp on dp.persona_id = p.id
           where p.estado='activo' and p.en_planilla is true
             and coalesce(dp.numero_cuenta,'') = '')

  union all select 12, 'RMV cargada (si el decreto ya subió, el piso de EsSalud va corto)',
         (select 'RMV = S/' || valor::text || ' desde ' || vigente_desde::text
            from parametros_laborales
           where clave = 'rmv' and vigente_hasta is null limit 1)
)
select h.hallazgo,
       case when h.quienes is null or h.quienes = '' then '✓  nadie'
            else '⚠  HAY GENTE' end                     as hay_alguien,
       coalesce(h.quienes, '—')                          as quienes
from h order by h.orden;
