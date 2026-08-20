-- ############################################################################
-- ####  LAS SEIS QUE CESARON ESTE MES — SOLO LEE, NO ESCRIBE NADA         ####
-- ############################################################################
--
-- Corriendo `las_tres_de_este_mes.sql` contra producción el 2026-08-19 apareció
-- algo que ninguna consulta anterior preguntaba: **seis personas cesaron dentro
-- del periodo 29/07–28/08**, y tres de ellas con `tipo_vinculo = 'prueba'`.
--
-- POR QUÉ ESO IMPORTA. `fn_devenga_beneficios(p_tipo)` es literalmente
-- `select p_tipo = 'planilla'`, así que quien cesa marcada como 'prueba' cobra
-- S/0.00 de gratificación trunca, S/0.00 de CTS y S/0.00 de vacaciones truncas,
-- salvo que alguien le haya puesto a mano las tres banderas de la 0196.
--
-- Y el único aviso que existía para eso —`fn_avisos_vinculo`, que la 0169
-- escribió precisamente para esto— filtra `estado = 'activo'`: se apaga en el
-- instante del cese, que es cuando esa etiqueta cuesta dinero.
--
-- ESTA CONSULTA NO DECIDE NADA. Solo pone al lado lo que se pagó y lo que
-- devengaría cada una si sus tres puertas estuvieran abiertas. La pregunta de
-- si el periodo de prueba devenga beneficios es de la norma, no de la base, y
-- se está verificando aparte. Aquí solo se mide, que es el orden correcto.
--
-- SEGUNDA COSA QUE MIDE. Jazmín Rios y Sisy Escorcho cesaron el 13/08 con UNA
-- sola marca en el periodo, mientras Luana —que cesó el mismo día— tiene 12.
-- Una marca sola puede ser correcta (no vino más) o puede ser marcaje perdido.
-- La diferencia son quince días de sueldo, así que se mira en vez de suponerse.
--
-- ES UN SOLO SELECT: el SQL Editor ejecuta solo la última sentencia.
-- ############################################################################

with sesion as (
  select set_config('request.jwt.claim.sub',
           (select auth_user_id::text from personas
             where rol = 'admin' and auth_user_id is not null
             order by (nombres ilike '%Felipe%') desc limit 1), true) as jwt
),
per as (
  select p.id, p.fecha_ini, p.fecha_fin
  from periodos_planilla p, sesion
  where (now() at time zone 'America/Lima')::date between p.fecha_ini and p.fecha_fin
  order by p.fecha_ini desc limit 1
),
cesantes as (
  select p.id, p.apellidos || ', ' || p.nombres as quien, p.tipo_vinculo,
         p.fecha_ingreso, p.fecha_cese, p.motivo_cese,
         p.devenga_grati, p.devenga_cts, p.devenga_vacaciones,
         (p.fecha_cese - p.fecha_ingreso) as dias_de_servicio,
         round(((p.fecha_cese - p.fecha_ingreso)/30.0)::numeric, 1) as meses_aprox
  from personas p, per
  where p.fecha_cese between per.fecha_ini and per.fecha_fin
),
liq as (
  select distinct on (l.persona_id) l.*
  from liquidacion_pagada l
  join cesantes c on c.id = l.persona_id
  where l.anulada is not true
  order by l.persona_id, l.version desc
),
-- Lo que las tres puertas dicen HOY para cada una.
puertas as (
  select c.id,
         fn_devenga(c.id, 'grati')      as puerta_grati,
         fn_devenga(c.id, 'cts')        as puerta_cts,
         fn_devenga(c.id, 'vacaciones') as puerta_vacaciones
  from cesantes c
),
-- Las marcas del periodo, para el segundo asunto.
marcas as (
  select c.id,
         (select count(*) from jornadas j, per
           where j.persona_id = c.id and j.fecha between per.fecha_ini and per.fecha_fin
             and coalesce(j.horas_trabajadas,0) > 0)                          as dias_marcados,
         (select count(*) from jornadas j, per
           where j.persona_id = c.id and j.fecha between per.fecha_ini and c.fecha_cese) as filas_de_jornada,
         (select max(j.fecha) from jornadas j
           where j.persona_id = c.id and coalesce(j.horas_trabajadas,0) > 0)  as ultima_marca,
         -- Días que le TOCABA trabajar entre el inicio del periodo y su cese,
         -- con el mismo criterio que usa el pago (horario del día).
         (select count(*) from per, generate_series(per.fecha_ini, c.fecha_cese, interval '1 day') d
           join lateral (select ha.dias_laborables, ha.horario_por_dia from horarios_asignados ha
                          where ha.persona_id = c.id and ha.vigente_desde <= d::date
                          order by ha.vigente_desde desc limit 1) hv on true
           where case when hv.horario_por_dia is not null
                        then hv.horario_por_dia ? (extract(dow from d)::int::text)
                      else extract(dow from d)::int = any(hv.dias_laborables) end) as le_tocaba
  from cesantes c
)
select c.quien,
       c.tipo_vinculo                                        as vinculo,
       to_char(c.fecha_ingreso,'DD/MM/YY')                   as ingreso,
       to_char(c.fecha_cese,'DD/MM/YY')                      as cese,
       c.meses_aprox                                         as meses_servicio,
       coalesce(c.motivo_cese,'—')                           as motivo,
       -- LAS TRES PUERTAS
       case when p.puerta_grati      then 'sí' else 'NO' end as devenga_grati,
       case when p.puerta_cts        then 'sí' else 'NO' end as devenga_cts,
       case when p.puerta_vacaciones then 'sí' else 'NO' end as devenga_vac,
       -- LO QUE SE LE PAGÓ, congelado
       coalesce(l.monto_periodo, 0)                          as pago_del_mes,
       coalesce(l.monto_grati, 0)                            as grati_pagada,
       coalesce(l.monto_cts, 0)                              as cts_pagada,
       coalesce(l.monto_vacaciones, 0)                       as vacaciones_pagadas,
       coalesce(l.total, 0)                                  as total_liquidacion,
       case when l.persona_id is null then 'SIN LIQUIDACIÓN CONGELADA'
            when coalesce(l.monto_grati,0) = 0 and coalesce(l.monto_cts,0) = 0
                 and coalesce(l.monto_vacaciones,0) = 0
              then '🚫 las tres truncas en CERO'
            else 'con truncas' end                           as truncas,
       -- EL SEGUNDO ASUNTO: marcas contra lo que le tocaba
       m.dias_marcados,
       m.le_tocaba                                           as dias_que_le_tocaba,
       to_char(m.ultima_marca,'DD/MM')                       as ultima_marca,
       case when m.le_tocaba > 0 and m.dias_marcados < m.le_tocaba / 2
              then '🚫 marcó menos de la mitad de lo que le tocaba — mirar si faltan marcajes'
            else 'ok' end                                    as señal_de_marcaje
from cesantes c
left join liq l   on l.persona_id = c.id
left join puertas p on p.id = c.id
left join marcas  m on m.id = c.id
order by (case when coalesce(l.monto_grati,0) = 0 and coalesce(l.monto_cts,0) = 0
                    and coalesce(l.monto_vacaciones,0) = 0 then 0 else 1 end),
         c.fecha_cese;
