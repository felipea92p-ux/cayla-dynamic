-- ############################################################################
-- ####  ANTES (Y DESPUÉS) DE PEGAR LA 0502 — SOLO LEE, NO ESCRIBE NADA    ####
-- ############################################################################
--
-- Para qué. La 0502 sube a su piso legal (RMV de S/ 1,230, o su proporción a las
-- horas pactadas) la subvención de los practicantes activos que hoy cobran menos,
-- desde el 2026-10-01. Antes de pegarla hay que ver QUIÉN sube, con qué horas
-- (las que se CONOCEN y las que se SUPONEN) y a quién deja fuera; después, que no
-- queda nadie bajo su piso. Este mismo script sirve para las dos cosas.
--
-- ⚠️ LA FILA 6 ES LA CONFIRMACIÓN. En producción hay practicantes sin ningún
-- convenio con horas pactadas cargado, y el sistema los lee como JORNADA COMPLETA
-- de su modalidad (30 h el preprofesional, 48 h el profesional). La 0502 hace lo
-- mismo. Si alguno trabaja en verdad menos horas, subirlo a 1,230 le sube de más y
-- NO se puede deshacer sin bajarle una subvención ya pagada. Por eso Felipe lee la
-- fila 6 —una línea por practicante, con «horas SUPUESTAS» donde no hay dato— y
-- confirma persona por persona ANTES de pegar. Quien tenga dudas se corrige
-- primero: se carga su convenio con las horas reales (Contratos) y se vuelve a
-- correr este script.
--
-- Cómo se usa. Es UNA sola consulta a propósito: el SQL Editor solo muestra el
-- último resultado, y una consulta por comprobación se pierde. Se pega entera y da
-- una tabla de comprobaciones (orden · qué · resultado). NO lleva nombres,
-- sueldos ni ids de nadie escritos acá; los nombres salen solo en el resultado.
--
-- LA REGLA que está dentro (entre «>>> REGLA 0502» y «<<< REGLA 0502») es la
-- MISMA, palabra por palabra, que ejecuta la migración y que mide la prueba 396;
-- tests/practicantes-piso-misma-regla.test.ts las compara. Lo que este script dice
-- que hará la 0502 es lo que la 0502 hace.
--
-- Va contra las TABLAS, no contra funciones de diagnóstico: varias devuelven cero
-- filas en el Editor por el guard de admin, y cero filas se lee igual que
-- «no hay nada».
-- ############################################################################

with
reglas as (
-- >>> REGLA 0502
with
conv as (
  -- El convenio de prácticas que manda por persona: el más reciente sin anular.
  -- El orden es el de fn_contratos_tablero (0386), que contesta esta misma
  -- pregunta en otra pantalla: generado_at, inicio, fin y id como ancla.
  select distinct on (c.persona_id) c.persona_id, c.horas_semanales
    from contratos_generados c
   where c.tipo = 'convenio_practicas' and c.anulado_at is null
   order by c.persona_id, c.generado_at desc, c.fecha_inicio desc,
            c.fecha_fin desc, c.id desc
),
rmv as (
  -- La RMV tal como la lee la planilla: la fila vigente en esa fecha.
  select pl.valor
    from parametros_laborales pl
   where pl.clave = 'rmv' and pl.sede_codigo is null
     and pl.vigente_desde <= date '2026-10-01'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-01')
   order by pl.vigente_desde desc
   limit 1
),
base as (
  select p.id as persona_id,
         a.rango,
         a.salario_mensual_soles as sal,
         p.sueldo_base_legal     as base,
         a.base_provision        as bp,
         p.sueldo_fijo           as sfijo,
         p.fecha_ingreso         as ingreso,
         p.practicante_modalidad as modalidad,
         cv.horas_semanales      as horas,
         (cv.horas_semanales is null) as asumida,
         (select r.valor from rmv r)  as rmv,
         exists (select 1 from asignaciones_salario f
                  where f.persona_id = p.id
                    and f.vigente_desde > date '2026-10-01') as futuro,
         -- Un cambio de sueldo ya programado: un tramo CERRADO que todavía cubre
         -- el 1-oct. Lo que se pagará ese día no es el tramo abierto que lee la
         -- regla sino ese, y no se resuelve a ciegas.
         exists (select 1 from asignaciones_salario f
                  where f.persona_id = p.id
                    and f.vigente_desde <= date '2026-10-01'
                    and f.vigente_hasta >= date '2026-10-01') as programado
    from personas p
    left join asignaciones_salario a
      on a.persona_id = p.id and a.vigente_hasta is null
    left join conv cv on cv.persona_id = p.id
   where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
     and coalesce(p.cuenta_de_servicio, false) = false
),
con_piso as (
  select b.*,
         case when b.modalidad = 'preprofesional' and b.horas is not null
              then round(b.rmv * least(b.horas, 30) / 30, 2)
              else b.rmv end as piso
    from base b
)
select c.persona_id, c.rango, c.modalidad, c.horas, c.asumida,
       c.sal, c.base, c.bp, c.sfijo, c.futuro, c.programado, c.rmv, c.piso,
       case
         when c.modalidad is null then 'omitida_sin_modalidad'
         when c.rango is null then 'omitida_sin_tramo'
         when c.asumida and c.ingreso > date '2026-10-01' then 'omitida_ingreso_posterior'
         when c.sal >= c.piso
           then case when c.piso < c.rmv then 'cumple_jornada_reducida' else 'cumple' end
         when c.sal < c.piso then 'sube'
         else 'sin_dato'
       end as accion
  from con_piso c
-- <<< REGLA 0502
),
-- Con nombre y con lo que haría la migración, para leerlo (los nombres salen solo acá).
quien as (
  select r.*,
         p.apellidos || ', ' || p.nombres as nombre,
         p.fecha_ingreso as ingreso_fecha,
         -- Lo que DETENDRÍA la migración (los mismos casos que su sección 1.3).
         ((r.accion = 'sube' and (r.bp is not null or r.sfijo is true or r.futuro))
          or (r.programado and r.accion in ('sube', 'cumple', 'cumple_jornada_reducida'))) as detiene
    from reglas r
    join personas p on p.id = r.persona_id
),
-- Las horas del último periodo pagado de cada practicante, para medir lo que cuesta.
ult as (
  select distinct on (d.persona_id) d.persona_id, d.horas_mes,
         (pp.fecha_fin - pp.fecha_ini + 1) as dias
    from planilla_pagada_detalle d
    join periodos_planilla pp on pp.id = d.periodo_id
   where pp.estado = 'pagado'
   order by d.persona_id, pp.fecha_fin desc, d.version desc
),
filas(orden, que, resultado) as (

  select 1, '(i) Practicantes activos (sin cuentas de servicio) por lo que haría la 0502',
         (select coalesce(string_agg(x.accion || ': ' || x.n, E'\n' order by x.accion), 'ninguno')
            from (select accion, count(*) n from quien group by accion) x)

  union all select 2, '(i) RMV que lee la regla el 2026-10-01 / el 2026-09-30 (esperado: 1230 / 1130; la 0502 se detiene si el 1-oct no es 1230)',
         (select coalesce((select valor::text from parametros_laborales pl
                            where pl.clave = 'rmv' and pl.sede_codigo is null
                              and pl.vigente_desde <= date '2026-10-01'
                              and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-01')
                            order by pl.vigente_desde desc limit 1)::text, 'SIN FILA')
                 || ' / ' ||
                 coalesce((select valor::text from parametros_laborales pl
                            where pl.clave = 'rmv' and pl.sede_codigo is null
                              and pl.vigente_desde <= date '2026-09-30'
                              and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-30')
                            order by pl.vigente_desde desc limit 1)::text, 'SIN FILA'))

  union all select 3, '(ii) Casos que DETIENEN la migración — esperado: todo en 0',
         (select 'base_provision propia: '        || count(*) filter (where accion = 'sube' and bp is not null)
              || ' · sueldo fijo: '               || count(*) filter (where accion = 'sube' and sfijo is true)
              || ' · tramo ya programado después del 1-oct: ' || count(*) filter (where accion = 'sube' and futuro)
              || ' · cambio programado que cubre el 1-oct: '  || count(*) filter (where programado and accion in ('sube', 'cumple', 'cumple_jornada_reducida'))
            from quien)

  union all select 4, '(ii) Admin que firmará el rastro de los tramos (activo más antiguo con usuario)',
         (select coalesce(p.apellidos || ', ' || p.nombres || ' · ingreso ' || coalesce(p.fecha_ingreso::text, '?'),
                          'NINGUNO: la migración se detendría')
            from (select 1) u
            left join lateral (select * from personas
                                where rol = 'admin' and estado = 'activo' and auth_user_id is not null
                                order by fecha_ingreso nulls last, id limit 1) p on true)

  union all select 5, '(iii) La SUPOSICIÓN «jornada completa»: a cuántos de los que suben se les SUPONE (sin horas pactadas en un convenio del sistema)',
         (select count(*) filter (where accion = 'sube' and asumida)::text || ' de ' || count(*) filter (where accion = 'sube')
              || ' (profesionales: ' || count(*) filter (where accion = 'sube' and asumida and modalidad = 'profesional')
              || ' · preprofesionales: ' || count(*) filter (where accion = 'sube' and asumida and modalidad = 'preprofesional')
              || ') · con horas leídas de su convenio: ' || count(*) filter (where accion = 'sube' and not asumida)
            from quien)

  union all select 6, 'Practicante: ' || nombre || ' · ' || coalesce(modalidad, '(sin modalidad)')
                      || ' · horas ' || case when horas is not null then horas::text || ' h (de su convenio)'
                                             else 'COMPLETAS de su modalidad, SUPUESTAS (ningún convenio del sistema las fija)' end
                      || ' · paga hoy ' || coalesce(sal::text, 'SIN SUBVENCIÓN CARGADA')
                      || ' · piso ' || coalesce(piso::numeric(10,2)::text, '?'),
         case
           when detiene then 'DETIENE LA MIGRACIÓN: tiene '
                || concat_ws(' y ',
                     case when accion = 'sube' and bp is not null then 'base_provision propia' end,
                     case when accion = 'sube' and sfijo is true then 'sueldo fijo' end,
                     case when accion = 'sube' and futuro then 'un tramo programado después del 1-oct' end,
                     case when programado then 'un cambio de sueldo programado que cubre el 1-oct' end)
           when accion = 'sube' then 'SUBE a ' || piso::numeric(10,2)::text
                || case when asumida then ' — por jornada completa SUPUESTA: CONFIRMAR que trabaja esas horas'
                        else ' — con las horas de su convenio' end
                || case when base is not null and base < piso then ' · su base legal (' || base::text || ') sube con ella'
                        when base is null then ' · su base legal sigue sin confirmar (nula)' else '' end
           when accion = 'cumple' then 'NO SE TOCA: ya cobra su piso o más (nunca se baja)'
           when accion = 'cumple_jornada_reducida'
             then 'NO SE TOCA: pactó ' || horas::text || ' h y ya cobra su piso proporcional'
           when accion = 'omitida_sin_modalidad' then 'QUEDA FUERA: sin modalidad no se sabe si su piso es proporcional (cargarla en Equipo)'
           when accion = 'omitida_sin_tramo' then 'QUEDA FUERA: sin subvención cargada no se inventa un monto'
           when accion = 'omitida_ingreso_posterior'
             then 'QUEDA FUERA: ingresó el ' || ingreso_fecha::text || ', después del 1-oct, y no tiene horas pactadas'
           else 'SIN DATO: la regla no lo reconoció' end
         from quien

  union all select 7, '(iii) Practicantes activos considerados (sin cuentas de servicio)', (select count(*)::text from quien)

  union all select 8, '(iv) Lo que sube un periodo COMPLETO con las horas del último periodo pagado (solo los que suben; el primer periodo, 28-sep → 28-oct, paga 3 de sus 31 días al sueldo viejo)',
         (select coalesce('S/ ' || round(sum(u.horas_mes * (q.piso - q.sal) / (6.5 * u.dias)), 2)::text
                          || ' en total, con las horas de ' || count(*) || ' persona(s)',
                          'ninguno de los que suben tiene un periodo pagado: sin horas reales no hay cifra (modelo: +S/ 100 como máximo por persona y mes, con 6.5 h todos los días)')
            from quien q join ult u on u.persona_id = q.persona_id
           where q.accion = 'sube')

  union all select 9, '(iv) De los que suben, con una asignación de educación VIGENTE que no es el 75 % de su costo (el tramo nuevo se la realinearía; la migración lo avisa)',
         (select count(distinct q.persona_id)::text
            from quien q
            join asignaciones_educacion e on e.persona_id = q.persona_id
           where q.accion = 'sube' and e.vigente_hasta >= date '2026-10-01'
             and e.monto is distinct from round(e.costo_declarado * 75 / 100.0, 2))

  union all select 10, '(iv) Los que suben con un mes PAGADO de rendimiento < 100 (frenaría la base legal) — esperado: 0',
         (select count(distinct q.persona_id)::text
            from quien q
            join rendimiento_mensual r on r.persona_id = q.persona_id
           where q.accion = 'sube' and r.porcentaje < 100
             and exists (select 1 from periodos_planilla pp
                          where pp.estado = 'pagado'
                            and extract(year from pp.fecha_fin)::int = r.anio
                            and extract(month from pp.fecha_fin)::int = r.mes))

  union all select 11, '(v) Periodos con fecha_fin desde el 1-oct y su estado, y si el grupo PRACTICANTE ya está pagado — esperado: ninguno pagado (la 0502 se pega ANTES de pagarlos)',
         (select coalesce(string_agg(pp.fecha_ini || ' → ' || pp.fecha_fin || ' (' || pp.estado
                            || case when exists (select 1 from periodo_grupo_pago g
                                                  where g.periodo_id = pp.id and g.grupo = 'practicante' and g.estado = 'pagado')
                                    then ' · PRACTICANTES YA PAGADOS' else '' end || ')',
                          ' · ' order by pp.fecha_ini), 'ninguno')
            from periodos_planilla pp where pp.fecha_fin >= date '2026-10-01')

  union all select 12, '(vi) Practicantes que la regla encuentra BAJO su piso — esperado ANTES: los que suben (fila 1) · DESPUÉS: 0',
         (select count(*)::text from quien where accion = 'sube')

  union all select 13, '(vi) Tramos de subvención abiertos que dejó la 0502 (nota «Migración 0502.») — esperado ANTES: 0 · DESPUÉS: tantos como los que subían',
         (select count(*)::text from asignaciones_salario a
           where a.nota like '%Migración 0502.' and a.vigente_desde = date '2026-10-01' and a.vigente_hasta is null)

  union all select 14, '(vi) Practicantes activos con la subvención vigente bajo 1,230 — esperado DESPUÉS: solo los de jornada reducida o los que quedaron fuera (fila 6)',
         (select count(*)::text from personas p
            join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
           where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
             and coalesce(p.cuenta_de_servicio, false) = false
             and a.salario_mensual_soles < 1230)

  union all select 15, '(vi) Practicantes con la base legal POR DEBAJO de su subvención (la constancia diría menos de lo que se paga) — esperado DESPUÉS: 0',
         (select count(*)::text from quien where sal is not null and base is not null and base < sal)

  union all select 16, '(vi) migraciones_aplicadas 501–502, con número Y nombre — esperado ANTES: solo la 501 · DESPUÉS: las dos',
         (select coalesce(string_agg(numero || ' ' || nombre, E'\n' order by numero), '(ninguna de las dos está)')
            from migraciones_aplicadas where numero between 501 and 502)
)
select orden, que, resultado from filas order by orden, que, resultado;
