-- ############################################################################
-- ####  ¿LA BOLETA DICE LO QUE SE PAGÓ?  — SOLO LEE, NO ESCRIBE NADA      ####
-- ############################################################################
--
-- Para qué. Al cerrar un mes, el sistema guarda una foto congelada de lo que se
-- le pagó a cada persona (`planilla_pagada_detalle`, migración 0096). Es
-- completa, es de solo-agregar y tiene un candado que exige que el desglose
-- sume el total.
--
-- **Pero la boleta no la usa.** La pantalla llama a `fn_proyeccion_periodo`, y
-- esa función —comprobado en la 0105, que es la vigente— hace exactamente esto:
-- comprueba el rol, busca el periodo, y llama a `fn_planilla_calcular`. No hay
-- ninguna rama que pregunte si el mes ya se pagó, y `planilla_pagada_detalle`
-- no aparece por ningún lado.
--
-- O sea que la boleta de un mes YA PAGADO se recalcula con las reglas de hoy y
-- los datos de hoy. Y `fn_planilla_calcular` se reescribió muchas veces desde
-- junio. Reimprimir la boleta de un mes cerrado puede dar un número distinto
-- del que salió del banco — sin avisar, porque la pantalla no sabe que está
-- recalculando.
--
-- Una boleta no es una pantalla informativa: es lo que se le entrega a la
-- persona y lo que mira SUNAFIL. Tiene que decir lo que se pagó.
--
-- Esto NO propone nada. Mide de qué tamaño es: cuántos meses están pagados,
-- cuántos tienen foto, y —lo que de verdad importa— a cuánta gente le saldría
-- hoy un número distinto del que cobró.
--
-- ── CÓMO SE LEE ─────────────────────────────────────────────────────────────
--
--   · «personas cuya boleta diría hoy otro número» = 0 → el riesgo es latente:
--     existe el camino, pero todavía no cambia ninguna cifra. Se arregla con
--     calma.
--   · > 0 → cada una de esas personas tiene hoy una boleta reimprimible que no
--     coincide con su depósito. Salen listadas abajo, con las dos cifras.
--   · «periodos pagados SIN foto» > 0 → esos son de antes de que existiera la
--     foto. Ahí no se puede leer nada congelado, y lo honesto es que la
--     pantalla lo diga en vez de dar un número recalculado como si fuera el
--     original.
--
-- OJO CON UNA COSA. Esta consulta llama a `fn_planilla_calcular`, que exige rol
-- de admin, y el SQL Editor no trae sesión — así que la fija ella misma en el
-- primer bloque. Si devolviera «Solo un administrador o líder puede calcular la
-- planilla», es que no encontró ninguna persona admin con `auth_user_id`.
--
-- Y puede tardar unos segundos: recalcula cada periodo pagado entero.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with sesion as (
  select set_config('request.jwt.claim.sub',
           (select auth_user_id::text from personas
             where rol = 'admin' and auth_user_id is not null
             order by (nombres ilike '%Felipe%') desc limit 1), true) as jwt
),
pagados as (
  select p.id, p.fecha_ini, p.fecha_fin, p.pagado_at
    from periodos_planilla p, sesion          -- el cross join fuerza la sesión
   where p.estado = 'pagado'
),
-- La foto vigente de cada periodo es la de mayor versión (append-only).
foto as (
  select d.periodo_id, d.persona_id, d.nombre, d.total, d.origen
    from planilla_pagada_detalle d
    join (select periodo_id, max(version) as v
            from planilla_pagada_detalle
           group by periodo_id) m
      on m.periodo_id = d.periodo_id and m.v = d.version
   where d.periodo_id in (select id from pagados)
),
-- Y lo que la boleta muestra HOY, que es esto y no la foto.
hoy as (
  select pg.id                       as periodo_id,
         (f->>'persona_id')::uuid    as persona_id,
         f->>'nombre'                as nombre,
         (f->>'total')::numeric      as total
    from pagados pg
   cross join lateral jsonb_array_elements(
     fn_planilla_calcular(pg.fecha_ini, pg.fecha_fin, pg.id) -> 'filas') f
),
-- Full join: interesa tanto quien está en los dos y no coincide, como quien
-- aparece en uno solo — alguien que cesó después sigue en la foto y ya no sale
-- del cálculo de hoy, y esa boleta tampoco se puede reimprimir bien.
comparacion as (
  select coalesce(f.periodo_id, h.periodo_id)          as periodo_id,
         coalesce(f.nombre, h.nombre, '(sin nombre)')  as quien,
         f.total                                        as pagado,
         h.total                                        as diria_hoy
    from foto f
    full outer join hoy h
      on h.periodo_id = f.periodo_id
     and h.persona_id = f.persona_id
),
distintas as (
  select c.*,
         pg.fecha_ini, pg.fecha_fin,
         coalesce(c.diria_hoy, 0) - coalesce(c.pagado, 0) as delta
    from comparacion c
    join pagados pg on pg.id = c.periodo_id
   where c.pagado is distinct from c.diria_hoy
     -- Quien no está en la foto y hoy calcula 0 no tiene boleta de ese mes: es
     -- gente que entró DESPUÉS y a la que el recálculo incluye con todo en
     -- cero. Sin este filtro sale una fila por cada una y tapan las de verdad.
     -- Si no está en la foto pero hoy calcula ALGO, eso sí es real: la boleta
     -- le mostraría un monto de un mes que nunca cobró.
     and not (c.pagado is null and coalesce(c.diria_hoy, 0) = 0)
),
sin_foto as (
  select count(*) as n
    from pagados pg
   where not exists (select 1 from foto f where f.periodo_id = pg.id)
)
select 1 as orden,
       case
         when (select count(*) from pagados) = 0
           then '·  Todavía no hay ningún mes pagado. Nada que comparar, y nada en riesgo aún.'
         when (select count(*) from distintas) = 0 and (select n from sin_foto) = 0
           then '✓  LATENTE. Todos los meses pagados tienen foto y hoy la boleta daría exactamente lo mismo. El camino malo existe pero todavía no cambia ninguna cifra: se arregla con calma.'
         when (select count(*) from distintas) = 0
           then '◑  LATENTE, pero hay ' || (select n from sin_foto)::text
                || ' mes(es) pagado(s) SIN foto. Hoy las cifras coinciden, pero de esos la boleta no tendría nunca de dónde leer lo original.'
         else '⚠  YA DIVERGE. A ' || (select count(*) from distintas)::text
              || ' persona(s) la boleta les diría hoy un número distinto del que cobraron. Están listadas abajo.'
       end                                                          as resultado,
       ''::text as detalle
union all
select 2, 'meses pagados', (select count(*) from pagados)::text
union all
select 3, 'de ellos, con foto congelada',
       (select count(distinct periodo_id) from foto)::text
union all
select 4, 'de ellos, SIN foto (la boleta no tendría de dónde leer)',
       (select n from sin_foto)::text
union all
select 5, 'personas cuya boleta diría hoy otro número',
       (select count(*) from distintas)::text
union all
select 6, 'la diferencia, sumada en soles',
       'S/ ' || to_char(coalesce((select sum(abs(delta)) from distintas), 0), 'FM999G999G990D00')
union all
select 7,
       'DIFERENCIA · ' || to_char(d.fecha_ini, 'DD/MM/YY') || '–' || to_char(d.fecha_fin, 'DD/MM/YY')
         || ' · ' || d.quien,
       'cobró ' || coalesce('S/ ' || to_char(d.pagado, 'FM999G999G990D00'), '(no estaba en la foto)')
         || '  ·  hoy diría ' || coalesce('S/ ' || to_char(d.diria_hoy, 'FM999G999G990D00'), '(ya no sale)')
  from distintas d
order by orden, resultado;
