-- ############################################################################
-- ####  ANTES (Y DESPUÉS) DE PEGAR LA 0502 — SOLO LEE, NO ESCRIBE NADA    ####
-- ############################################################################
--
-- Para qué. La 0502 alinea a la RMV nueva (S/ 1,230, o su proporción a las horas
-- pactadas) la subvención PACTADA de los practicantes activos que hoy cobran
-- menos, desde el 2026-10-01. Antes de pegarla hay que ver QUIÉN sube, con qué
-- horas (las que se CONOCEN y las que se SUPONEN) y a quién deja fuera; después,
-- que no queda nadie bajo su referencia. Este mismo script sirve para las dos cosas.
--
-- ⚠️ LO QUE ESTE SCRIPT (Y LA 0502) NO DICE. Que la boleta llegue a esa cifra.
-- La planilla paga a un practicante POR LAS HORAS MARCADAS: un preprofesional que
-- cumple sus 30 h semanales cobra ≈ dos tercios del tramo, con 1,130 y con
-- 1,230. Si eso cumple el art. 45 de la Ley 28518 es consulta abierta con el
-- laboralista (docs/estado.md); la 0502 sube lo PACTADO, no la resuelve.
--
-- ⚠️ LA FILA 6 ES LA CONFIRMACIÓN. En producción hay practicantes sin ningún
-- convenio con horas pactadas cargado, y el sistema los lee como JORNADA COMPLETA
-- de su modalidad (30 h el preprofesional, 48 h el profesional). La 0502 hace lo
-- mismo. Si alguno trabaja en verdad menos horas, subirlo le sube de más y NO se
-- puede deshacer sin bajarle una subvención ya pagada. Por eso Felipe lee la fila
-- 6 —una entrada por practicante: modalidad, horas SUPUESTAS en número, lo que
-- marcó en el último periodo pagado, su horario, sus convenios y si están
-- firmados— y confirma persona por persona ANTES de pegar.
--
-- Lo que la protección por horas SÍ y NO alcanza (revisión del 2026-10-01):
--   · SOLO el PREPROFESIONAL con un convenio generado CON horas queda protegido:
--     el generador guarda horas únicamente para él, y la regla las ignora si la
--     modalidad no es «preprofesional». Quien tenga dudas, se corrige primero: se
--     carga su convenio con las horas reales (Contratos) y se vuelve a correr
--     este script.
--   · Para un PROFESIONAL esa protección es NULA POR CONSTRUCCIÓN: su convenio
--     nunca lleva horas, la regla le aplica la RMV entera, y no existe dónde
--     cargar «este profesional trabaja menos» para que la regla lo lea. Para un
--     profesional de jornada reducida NO hay protección. Si Felipe duda de alguno
--     de ellos, NO SE PEGA.
--   · Dos convenios que se CONTRADICEN (horas distintas entre sí, o uno con horas
--     y otro sin ellas) DETIENEN la migración («conflicto de convenios»): la fila
--     6 los lista con sus horas y si están firmados, para anular el que sobra.
--
-- Cómo se usa. Es UNA sola consulta a propósito: el SQL Editor solo muestra el
-- último resultado, y una consulta por comprobación se pierde. Se pega entera y da
-- una tabla de comprobaciones (orden · qué · resultado). NO lleva nombres,
-- sueldos ni ids de nadie escritos acá; los nombres salen solo en el resultado.
--
-- Y lo que importa viaja en filas, no en avisos: el SQL Editor NO muestra los
-- RAISE NOTICE (por eso existe llego_bien_la_0309.sql). La migración devuelve al
-- final una fila con sus conteos —tramos, quién subió por suposición y quién con
-- horas de su convenio, educación realineada— y este script la repite en las filas
-- 12 a 16 para el DESPUÉS.
--
-- LA REGLA que está dentro (entre «>>> REGLA 0502» y «<<< REGLA 0502») es la
-- MISMA, palabra por palabra, que ejecuta la migración y que mide la prueba 396;
-- tests/practicantes-subvencion-misma-regla.test.ts las compara. Lo que este script
-- dice que hará la 0502 es lo que la 0502 hace.
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
  -- Los convenios de prácticas NO anulados de cada persona que TRAEN horas
  -- pactadas, firmados o en borrador: equivocarse hacia «protegerlo» se arregla
  -- pegando de nuevo; subir de más no se deshace. Valen todos juntos, no «el más
  -- reciente»: si dicen cosas distintas esa persona es un CONFLICTO (abajo).
  select c.persona_id,
         min(c.horas_semanales)                as horas,
         count(distinct c.horas_semanales) > 1 as horas_distintas
    from contratos_generados c
   where c.tipo = 'convenio_practicas' and c.anulado_at is null
     and c.horas_semanales is not null
   group by c.persona_id
),
sin_horas as (
  -- Los NO anulados que NO traen horas: el generador no pudo determinarlas, o es
  -- el convenio de un profesional, a quien nunca se le guardan.
  select distinct c.persona_id
    from contratos_generados c
   where c.tipo = 'convenio_practicas' and c.anulado_at is null
     and c.horas_semanales is null
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
         cv.horas                as horas,
         (cv.horas is null)      as asumida,
         -- Dos convenios vigentes que se CONTRADICEN: horas distintas entre sí, o
         -- uno con horas y otro sin ellas. No se elige cuál «manda»: la migración
         -- se detiene y Felipe decide a mano.
         (coalesce(cv.horas_distintas, false)
          or (cv.persona_id is not null and sh.persona_id is not null)) as conflicto,
         (select r.valor from rmv r)  as rmv,
         -- Un tramo de sueldo que EMPIEZA el 1-oct o después: programado, o el de
         -- quien ingresó hoy o más tarde. fn_set_salario BORRA todo tramo con
         -- vigente_desde >= la fecha, y la reversión —que reabre el tramo cerrado
         -- el 30-sep— lo dejaría sin ninguno.
         exists (select 1 from asignaciones_salario f
                  where f.persona_id = p.id
                    and f.vigente_desde >= date '2026-10-01') as desde_oct,
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
    left join sin_horas sh on sh.persona_id = p.id
   where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
     and coalesce(p.cuenta_de_servicio, false) = false
),
con_piso as (
  select b.*,
         case when b.conflicto then null
              when b.modalidad = 'preprofesional' and b.horas is not null
              then round(b.rmv * least(b.horas, 30) / 30, 2)
              else b.rmv end as piso
    from base b
)
select c.persona_id, c.rango, c.modalidad, c.horas, c.asumida, c.conflicto,
       c.sal, c.base, c.bp, c.sfijo, c.desde_oct, c.programado, c.rmv, c.piso,
       case
         when c.conflicto then 'conflicto_convenios'
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
         -- Las horas que se SUPONEN cuando ningún convenio las fija: la jornada
         -- completa de su modalidad.
         case r.modalidad when 'preprofesional' then 30 when 'profesional' then 48 end as horas_modalidad,
         -- Lo que DETENDRÍA la migración (los mismos casos que su sección 1.3, más
         -- el conflicto de convenios).
         ((r.accion = 'sube' and (r.bp is not null or r.sfijo is true or r.desde_oct))
          or (r.programado and r.accion in ('sube', 'cumple', 'cumple_jornada_reducida'))
          or r.accion = 'conflicto_convenios') as detiene
    from reglas r
    join personas p on p.id = r.persona_id
),
-- Lo que hay en el sistema, convenio por convenio (sin anulados): cuántos, con
-- cuántas horas y si están firmados (fecha_firma, que es lo que el sistema lee como
-- «firmado»: la firma digital no deja escaneo y el escaneo no es el criterio).
convenios as (
  select c.persona_id, count(*) as n,
         bool_or(c.fecha_firma is not null) as hay_firmado,
         string_agg(coalesce(trim_scale(c.horas_semanales)::text || ' h', 'SIN horas')
                    || case when c.fecha_firma is not null then ' (firmado)' else ' (SIN firmar)' end,
                    ' · ' order by c.generado_at desc, c.fecha_inicio desc, c.id desc) as lista
    from contratos_generados c
   where c.tipo = 'convenio_practicas' and c.anulado_at is null
   group by c.persona_id
),
-- Las horas del último periodo pagado de cada practicante, para medir lo que
-- marcó y lo que cuesta.
ult as (
  select distinct on (d.persona_id) d.persona_id, d.horas_mes,
         (pp.fecha_fin - pp.fecha_ini + 1) as dias
    from planilla_pagada_detalle d
    join periodos_planilla pp on pp.id = d.periodo_id
   where pp.estado = 'pagado'
   order by d.persona_id, pp.fecha_fin desc, d.version desc
),
-- El horario vigente el 1-oct, SOLO como señal (no lleva datos personales): su
-- «horas_semana_objetivo» nace en 45 por defecto y Contratos decidió el 2026-08-19
-- no tomarlo como la jornada pactada.
horario as (
  select distinct on (h.persona_id) h.persona_id, h.horas_semana_objetivo
    from horarios_asignados h
   where h.vigente_desde <= date '2026-10-01'
     and (h.vigente_hasta is null or h.vigente_hasta >= date '2026-10-01')
   order by h.persona_id, h.vigente_desde desc
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
         (select 'CONFLICTO DE CONVENIOS: '       || count(*) filter (where accion = 'conflicto_convenios')
              || ' · base_provision propia: '     || count(*) filter (where accion = 'sube' and bp is not null)
              || ' · sueldo fijo: '               || count(*) filter (where accion = 'sube' and sfijo is true)
              || ' · tramo que empieza el 1-oct o después (ingresó hoy o lo tiene programado): ' || count(*) filter (where accion = 'sube' and desde_oct)
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
              || ' (profesionales, SIN protección por horas posible: ' || count(*) filter (where accion = 'sube' and asumida and modalidad = 'profesional')
              || ' · preprofesionales: ' || count(*) filter (where accion = 'sube' and asumida and modalidad = 'preprofesional')
              || ') · con horas leídas de su convenio: ' || count(*) filter (where accion = 'sube' and not asumida)
            from quien)

  union all select 6, 'Practicante: ' || q.nombre || ' · ' || coalesce(q.modalidad, '(sin modalidad)')
                      || ' · paga hoy ' || coalesce(q.sal::text, 'SIN SUBVENCIÓN CARGADA')
                      || ' · piso ' || coalesce(q.piso::numeric(10,2)::text, 'sin calcular'),
         case
           when q.accion = 'conflicto_convenios'
             then 'DETIENE LA MIGRACIÓN: conflicto de convenios (los de abajo se contradicen: horas distintas entre sí, o con horas y sin horas). Anular en Contratos el que sobra y volver a correr este script'
           when q.detiene then 'DETIENE LA MIGRACIÓN: tiene '
                || concat_ws(' y ',
                     case when q.accion = 'sube' and q.bp is not null then 'base_provision propia' end,
                     case when q.accion = 'sube' and q.sfijo is true then 'sueldo fijo' end,
                     case when q.accion = 'sube' and q.desde_oct then 'un tramo de sueldo que empieza el 1-oct o después (fn_set_salario lo borraría)' end,
                     case when q.programado then 'un cambio de sueldo programado que cubre el 1-oct' end)
           when q.accion = 'sube' then 'SUBE a ' || q.piso::numeric(10,2)::text
                || case when q.asumida
                        then ' — por jornada completa SUPUESTA de ' || q.horas_modalidad || ' h: CONFIRMAR que trabaja esas horas'
                             || case when q.modalidad = 'profesional'
                                     then ' (un profesional de jornada reducida NO tiene protección: si dudas de esta persona, NO se pega)'
                                     else '' end
                        else ' — con las ' || trim_scale(q.horas)::text || ' h de su convenio' end
                || case when q.base is not null and q.base < q.piso then ' · su base legal (' || q.base::text || ') sube con ella'
                        when q.base is null then ' · su base legal sigue sin confirmar (nula)' else '' end
           when q.accion = 'cumple' then 'NO SE TOCA: ya cobra su piso o más (nunca se baja)'
           when q.accion = 'cumple_jornada_reducida'
             then 'NO SE TOCA: pactó ' || trim_scale(q.horas)::text || ' h y ya cobra su piso proporcional'
                  || case when cv.hay_firmado then ' (hay convenio firmado)'
                          else ' (solo en un convenio SIN FIRMAR: también protege; si es un error, anúlalo y vuelve a correr este script)' end
           when q.accion = 'omitida_sin_modalidad' then 'QUEDA FUERA: sin modalidad no se sabe si su piso es proporcional (cargarla en Equipo)'
           when q.accion = 'omitida_sin_tramo' then 'QUEDA FUERA: sin subvención cargada no se inventa un monto'
           when q.accion = 'omitida_ingreso_posterior'
             then 'QUEDA FUERA: ingresó el ' || q.ingreso_fecha::text || ', después del 1-oct, y no tiene horas pactadas'
           else 'SIN DATO: la regla no lo reconoció' end
         || E'\n   · HORAS: ' || case
              when q.accion = 'conflicto_convenios' then 'NO SE PUEDEN LEER (convenios en conflicto)'
              when q.modalidad is null then 'sin modalidad: no se supone nada'
              when q.asumida then 'SUPUESTAS ' || q.horas_modalidad || ' h por semana (jornada completa de su modalidad; NINGÚN convenio del sistema las fija)'
              else trim_scale(q.horas)::text || ' h por semana, de su convenio'
                   || case when q.modalidad = 'profesional'
                           then ' — LA REGLA IGNORA ESTAS HORAS: solo el preprofesional tiene referencia proporcional'
                           else '' end end
         || E'\n   · CONVENIOS del sistema (sin anulados): ' || coalesce(cv.n::text || ' → ' || cv.lista, 'ninguno')
         || E'\n   · LO QUE MARCÓ en el último periodo pagado: '
            || case when u.horas_mes is not null
                    then '≈ ' || round(u.horas_mes * 7.0 / u.dias, 1)::text || ' h por semana (horas del periodo ÷ días × 7; aprox.)'
                    else 'sin periodo pagado: sin dato' end
         || E'\n   · HORARIO vigente: '
            || case when hz.horas_semana_objetivo is not null
                    then 'objetivo de ' || trim_scale(hz.horas_semana_objetivo)::text
                         || ' h por semana — señal DÉBIL: nace en 45 por defecto y no es la jornada pactada'
                    else 'sin horario vigente' end
         from quien q
         left join convenios cv on cv.persona_id = q.persona_id
         left join ult u on u.persona_id = q.persona_id
         left join horario hz on hz.persona_id = q.persona_id

  union all select 7, '(iii) Practicantes activos considerados (sin cuentas de servicio)', (select count(*)::text from quien)

  union all select 8, '(iv) Lo que sube un periodo COMPLETO con las horas del último periodo pagado (solo los que suben; el primer periodo, 28-sep → 28-oct, paga 3 de sus 31 días al sueldo viejo)',
         (select coalesce('S/ ' || round(sum(u.horas_mes * (q.piso - q.sal) / (6.5 * u.dias)), 2)::text
                          || ' en total, con las horas de ' || count(*) || ' persona(s)',
                          'ninguno de los que suben tiene un periodo pagado: sin horas reales no hay cifra (modelo: +S/ 100 como máximo por persona y mes, con 6.5 h todos los días)')
            from quien q join ult u on u.persona_id = q.persona_id
           where q.accion = 'sube')

  union all select 9, '(iv) De los que suben, con una asignación de educación VIGENTE que no es el 75 % de su costo (el tramo nuevo se la realinearía; la migración lo cuenta en educacion_realineada_hoy)',
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

  union all select 12, '(vi) Practicantes que la regla encuentra BAJO su referencia — esperado ANTES: los que suben (fila 1) · DESPUÉS: 0',
         (select count(*)::text from quien where accion = 'sube')

  union all select 13, '(vi) Tramos de subvención abiertos que dejó la 0502 (nota «Migración 0502.»), y de ellos cuántos por suposición (la nota dice SUPUESTA) y cuántos con horas de convenio — esperado ANTES: 0 · DESPUÉS: tantos como los que subían, con la misma división que la fila 5',
         (select count(*)::text
              || ' (por suposición: ' || count(*) filter (where a.nota like '%SUPUESTA%')
              || ' · con horas de convenio: ' || count(*) filter (where a.nota not like '%SUPUESTA%') || ')'
            from asignaciones_salario a
           where a.nota like '%Migración 0502.' and a.vigente_desde = date '2026-10-01' and a.vigente_hasta is null)

  union all select 14, '(vi) Practicantes activos con la subvención vigente bajo 1,230 — esperado DESPUÉS: solo los de jornada reducida o los que quedaron fuera (fila 6)',
         (select count(*)::text from personas p
            join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
           where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
             and coalesce(p.cuenta_de_servicio, false) = false
             and a.salario_mensual_soles < 1230)

  union all select 15, '(vi) Practicantes con la base legal POR DEBAJO de su subvención (la constancia diría menos de lo que se paga) — esperado DESPUÉS: 0',
         (select count(*)::text from quien where sal is not null and base is not null and base < sal)

  union all select 16, '(vi) migraciones_aplicadas 501–502, con número Y nombre — esperado ANTES: solo la 501 · DESPUÉS: las dos, la 502 como «la_subvencion_pactada_de_los_practicantes_sigue_a_la_rmv_de_1230»',
         (select coalesce(string_agg(numero || ' ' || nombre, E'\n' order by numero), '(ninguna de las dos está)')
            from migraciones_aplicadas where numero between 501 and 502)
)
select orden, que, resultado from filas order by orden, que, resultado;
