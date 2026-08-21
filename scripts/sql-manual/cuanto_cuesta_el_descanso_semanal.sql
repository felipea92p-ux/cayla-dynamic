-- ############################################################################
-- ####  ¿CUÁNTO CUESTA EL DESCANSO SEMANAL NO DADO?  — SOLO LEE            ####
-- ############################################################################
--
-- Nace del `a_quien_le_pega.sql` del 2026-08-20: su pregunta 8 devolvió SEIS
-- rachas de 7+ días seguidos sin descanso, cinco personas, cinco de ellas en
-- TRU. Eso confirma la población; esto pone el número.
--
-- POR QUÉ HACE FALTA EL NÚMERO ANTES DE CONSTRUIR NADA. La sobretasa del 100 %
-- del art. 3 del D. Leg. 713 no existe en el sistema —está decidida con Felipe
-- y sin construir—. Sin saber si son ochenta soles o mil no se puede decidir ni
-- con qué urgencia se construye ni si se reabre un periodo ya pagado, que es
-- una operación con su propio riesgo. Es la regla de la casa: medir contra la
-- base antes de proponer.
--
-- ES UN SOLO SELECT A PROPÓSITO. El SQL Editor de Supabase ejecuta únicamente
-- la última sentencia; partirlo en bloques perdería todos menos el último, en
-- silencio. Y LA SESIÓN DE ADMIN VA DENTRO, igual que en `a_quien_le_pega.sql`.
--
-- ── LO QUE ESTA CONSULTA DECIDE, Y HAY QUE PODER DISCUTIR ───────────────────
--
-- 1. QUÉ ES UNA SEMANA. Un ciclo de siete días que empieza tras un descanso y
--    se corta a los siete, NO lunes a domingo. Es el criterio del Informe
--    027-2021-MTPE/14 y es el mismo que ya usa `fn_planilla_calcular` para el
--    sobretiempo desde la 0185 — se copió su lógica de rachas (`ot_islas`,
--    `ot_ciclos`) a propósito, para que las dos cuenten igual.
--
-- 2. QUÉ DÍA DISPARA LA SOBRETASA. El SÉPTIMO de cada ciclo completo: es el que
--    se trabajó en lugar de descansar. Una racha de ocho días paga UNA
--    sobretasa, no dos — el octavo abre un ciclo nuevo que todavía no se ha
--    cerrado sin descanso. Los ciclos no se solapan, por lo mismo que en el
--    sobretiempo: una ventana móvil cobraría el mismo día siete veces.
--
-- 3. CUÁNTO VALE. Exactamente lo que ya vale la sobretasa del feriado
--    trabajado en `fn_planilla_calcular`: `horas_del_día × salario / v_base`,
--    con `v_base = 6.5 × días del periodo`. No se inventa una valorización
--    nueva — si el feriado y el descanso semanal se valoraran distinto, una de
--    las dos estaría mal.
--
--    Se paga el RECARGO, no el día completo: las horas de ese día ya están
--    dentro de `pago_base`. Es el error que la 0173 corrigió con el feriado.
--
-- 4. A QUIÉN NO SE LE MIDE. Locadores (`en_planilla = false`): un RxH no tiene
--    descanso remunerado que respetarle, mismo criterio que la 0199 con los
--    feriados. Y sueldo fijo (`sueldo_fijo = true`): su pago no depende de
--    horas, así que una sobretasa por horas no le aplica igual — la 0173 ya
--    tuvo que arreglar justo eso en el feriado.
--
-- 5. AL PERSONAL DE DIRECCIÓN SÍ SE LE MIDE, Y SE LE MARCA. La 0187 lo excluye
--    del sobretiempo por el art. 5 del D.S. 007-2002-TR — pero ese artículo
--    excluye de la JORNADA MÁXIMA, y el descanso semanal es otra norma
--    (D. Leg. 713). No está resuelto, así que la fila sale con el aviso puesto
--    en vez de desaparecer: esconderla decidiría la pregunta legal por
--    omisión, y a favor de la empresa.
--
-- ── LO QUE ESTA CONSULTA NO PUEDE SABER ─────────────────────────────────────
--
-- SI HUBO DESCANSO SUSTITUTORIO. El sistema solo lo registra para FERIADOS
-- (tabla `feriados_descanso_sustitutorio`, migraciones 0069/0093/0238). Para el
-- descanso semanal no hay dónde anotarlo, así que no hay dónde leerlo. Si
-- alguna de estas personas descansó otro día, su sobretasa es CERO y lo que
-- falta es el registro, no la plata. Eso lo saben las encargadas.
--
-- Por eso la columna se llama `sobretasa_si_no_hubo_sustitutorio` y no
-- `lo_que_se_debe`.
-- ############################################################################

with sesion as (
  select set_config('request.jwt.claim.sub',
           (select auth_user_id::text from personas
             where rol = 'admin' and auth_user_id is not null
             order by (nombres ilike '%Felipe%') desc limit 1), true) as jwt
),
-- El periodo en curso y el anterior. El anterior entra a propósito: ahí caen
-- dos de las seis rachas, y saber que ya está pagado es justo la diferencia
-- entre «se corrige antes del 28» y «hay que decidir si se reabre».
periodos as (
  select p.id, p.fecha_ini, p.fecha_fin, p.estado, p.pagado_at,
         6.5 * ((p.fecha_fin - p.fecha_ini) + 1) as v_base,
         row_number() over (order by p.fecha_ini desc) as reciente
  from periodos_planilla p, sesion
  where p.fecha_ini <= (now() at time zone 'America/Lima')::date
  order by p.fecha_ini desc
  limit 2
),
ventana as (
  select min(fecha_ini) as desde, max(fecha_fin) as hasta from periodos
),
gente as (
  select p.id, p.apellidos || ', ' || p.nombres as quien,
         coalesce(s.codigo, '?') as sede,
         p.en_planilla, p.sueldo_fijo, p.personal_direccion
  from personas p
  left join sedes s on s.id = p.sede_base_id
  where coalesce(p.en_planilla, false)          -- un RxH no tiene descanso que respetarle
    and not coalesce(p.sueldo_fijo, false)      -- su pago no depende de horas
),
-- Se lee SIETE DÍAS ANTES de la ventana, igual que `ot_dias` en la 0185: una
-- racha que empezó antes tiene que medirse entera o su séptimo día desaparece.
dias as (
  select j.persona_id, j.fecha, j.horas_trabajadas as h
  from jornadas j, ventana v
  where j.fecha between v.desde - 7 and v.hasta
    and coalesce(j.horas_trabajadas, 0) > 0
),
-- Rachas de días consecutivos. Un descanso las corta: en días seguidos, la
-- fecha menos su número de orden da siempre el mismo valor.
islas as (
  select persona_id, fecha, h,
         fecha - (row_number() over (partition by persona_id order by fecha))::int as isla
  from dias
),
-- Dentro de cada racha, el orden del día y su bloque de siete.
ciclos as (
  select persona_id, fecha, h, isla,
         row_number() over (partition by persona_id, isla order by fecha) as dia_n
  from islas
),
-- El séptimo día de cada ciclo completo: el que se trabajó en vez de descansar.
disparos as (
  select c.persona_id, c.fecha as dia_sin_descanso, c.h as horas,
         c.isla,
         (select min(fecha) from ciclos c2
           where c2.persona_id = c.persona_id and c2.isla = c.isla) as racha_desde,
         (select max(fecha) from ciclos c2
           where c2.persona_id = c.persona_id and c2.isla = c.isla) as racha_hasta,
         (select count(*) from ciclos c2
           where c2.persona_id = c.persona_id and c2.isla = c.isla) as racha_dias
  from ciclos c
  where c.dia_n % 7 = 0
),
valorado as (
  select g.quien, g.sede, g.personal_direccion,
         d.dia_sin_descanso, d.horas, d.racha_desde, d.racha_hasta, d.racha_dias,
         per.id as periodo_id, per.fecha_ini, per.fecha_fin, per.estado as periodo_estado,
         per.pagado_at, per.v_base, per.reciente,
         -- El salario VIGENTE ese día, igual que hace `tramos` en la función.
         (select a.salario_mensual_soles from asignaciones_salario a
           where a.persona_id = d.persona_id
             and a.vigente_desde <= d.dia_sin_descanso
             and (a.vigente_hasta is null or a.vigente_hasta >= d.dia_sin_descanso)
           order by a.vigente_desde desc limit 1) as salario
  from disparos d
  join gente g on g.id = d.persona_id
  join periodos per on d.dia_sin_descanso between per.fecha_ini and per.fecha_fin
),
filas as (
  select
    to_char(v.dia_sin_descanso, 'DD/MM')                              as dia_que_dispara,
    v.quien,
    v.sede,
    v.racha_dias || ' días (' || to_char(v.racha_desde, 'DD/MM')
      || '→' || to_char(v.racha_hasta, 'DD/MM') || ')'                as racha,
    round(v.horas, 2)                                                 as horas_ese_dia,
    v.salario,
    round(v.salario / v.v_base, 4)                                    as valor_hora,
    round(v.horas * v.salario / v.v_base, 2)                          as sobretasa_si_no_hubo_sustitutorio,
    case
      when v.salario is null then '⚠ SIN SALARIO VIGENTE — no se puede valorizar'
      when v.pagado_at is not null or v.periodo_estado = 'pagado'
        then '🔒 periodo YA PAGADO (' || to_char(v.fecha_ini,'DD/MM') || '→'
             || to_char(v.fecha_fin,'DD/MM') || ') — decidir si se reabre'
      else '🟢 se paga el ' || to_char(v.fecha_fin, 'DD/MM')
           || ' — a tiempo de corregirlo'
    end                                                               as donde_cae,
    case when v.personal_direccion
         then '⚠ personal de dirección — el art. 5 lo excluye de la JORNADA, no del descanso semanal. Sin resolver.'
         else '' end                                                  as ojo,
    v.reciente as orden_periodo, v.dia_sin_descanso as orden_dia, 1 as orden_bloque
  from valorado v
),
-- LOS TOTALES SOLO CUENTAN LO QUE SUMAN. Contar una fila sin salario vigente
-- dentro del «6 días · S/258.05» hace que el número parezca el de seis días
-- cuando es el de cinco, y nadie lo nota: los dos son verosímiles. Las
-- no valorizables se cuentan aparte y se dicen en voz alta.
total_pagable as (
  select coalesce(sum(round(v.horas * v.salario / v.v_base, 2))
           filter (where v.salario is not null), 0)                   as monto,
         count(*) filter (where v.salario is not null)                as cuantas,
         count(*) filter (where v.salario is null)                    as sin_valorizar
  from valorado v
  where v.pagado_at is null and v.periodo_estado is distinct from 'pagado'
),
total_cerrado as (
  select coalesce(sum(round(v.horas * v.salario / v.v_base, 2))
           filter (where v.salario is not null), 0)                   as monto,
         count(*) filter (where v.salario is not null)                as cuantas,
         count(*) filter (where v.salario is null)                    as sin_valorizar
  from valorado v
  where v.pagado_at is not null or v.periodo_estado = 'pagado'
)
select dia_que_dispara, quien, sede, racha, horas_ese_dia, salario, valor_hora,
       sobretasa_si_no_hubo_sustitutorio, donde_cae, ojo
from (
  select * from filas
  union all
  select '——', '', '', '', null, null, null, null, '', '', 9, '9999-12-30'::date, 8
  union all
  select 'TOTAL', 'este periodo, todavía corregible',
         (select cuantas from total_pagable) || ' día(s)', '', null, null, null,
         (select monto from total_pagable),
         '🟢 esto es lo que se dejaría de pagar el 28 si no se construye'
           || (select case when sin_valorizar > 0
                      then ' · ⚠ y ' || sin_valorizar || ' día(s) MÁS sin salario vigente, fuera de este total'
                      else '' end from total_pagable), '',
         9, '9999-12-31'::date, 9
  union all
  select 'TOTAL', 'periodo anterior, ya pagado',
         (select cuantas from total_cerrado) || ' día(s)', '', null, null, null,
         (select monto from total_cerrado),
         '🔒 esto solo se corrige reabriendo un periodo cerrado'
           || (select case when sin_valorizar > 0
                      then ' · ⚠ y ' || sin_valorizar || ' día(s) MÁS sin salario vigente, fuera de este total'
                      else '' end from total_cerrado), '',
         9, '9999-12-31'::date, 10
) t
order by orden_bloque, orden_periodo, orden_dia;
