-- ############################################################################
-- ####  ¿HAY HORARIOS SOLAPADOS?  — SOLO LEE, NO ESCRIBE NADA             ####
-- ############################################################################
--
-- Para qué. `horarios_asignados` guarda el horario de cada persona por tramos
-- de vigencia, pero lo único que impide duplicados es un índice PARCIAL sobre
-- «el tramo abierto» (`idx_horario_vigente_unico`, solo where vigente_hasta is
-- null). Nada impide que dos tramos CERRADOS se pisen, ni que uno cerrado se
-- solape con el abierto.
--
-- Y cuando dos tramos cubren el mismo día, quien decide es un
-- `order by vigente_desde desc limit 1` — en `fn_recalcular_jornada` y en
-- `apps/web/lib/admin/jornada-esperada.ts`. Elige uno **sin avisar**, y de esa
-- elección sale qué se esperaba de esa persona ese día: si llegó tarde, si
-- salió antes, o si faltó.
--
-- El arreglo es el mismo `EXCLUDE USING gist` que ya protege
-- `asignaciones_salario` desde la 0024. Pero **una restricción no se puede
-- agregar sobre datos que ya la violan**: si hoy existe aunque sea un solape, la
-- migración fallaría al pegarla, a mitad, en producción.
--
-- Por eso esto se corre ANTES de escribir esa migración, y no después.
--
-- ── CÓMO SE LEE ─────────────────────────────────────────────────────────────
--   ✓ = no hay solapes. El candado se puede poner tal cual.
--   ⚠ = los hay. Antes de poner el candado hay que decidir, caso por caso, qué
--       tramo vale — y esa decisión cambia qué se le contó a esa persona.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with tramos as (
  select h.id, h.persona_id,
         (p.nombres || ' ' || p.apellidos)                                   as persona,
         h.vigente_desde, h.vigente_hasta,
         daterange(h.vigente_desde,
                   coalesce(h.vigente_hasta, 'infinity'::date), '[]')        as rango
    from horarios_asignados h
    join personas p on p.id = h.persona_id
),
choques as (
  select a.persona,
         a.vigente_desde as desde_a, a.vigente_hasta as hasta_a,
         b.vigente_desde as desde_b, b.vigente_hasta as hasta_b,
         a.rango * b.rango as solape
    from tramos a
    join tramos b
      on b.persona_id = a.persona_id
     and b.id > a.id                 -- cada par una sola vez
     and a.rango && b.rango
)
select 1 as orden,
       case when (select count(*) from choques) = 0
            then '✓  Ningún horario solapado. El candado EXCLUDE se puede poner tal cual, sin tocar datos.'
            else '⚠  ' || (select count(*) from choques)::text
                 || ' par(es) de tramos que se pisan, en '
                 || (select count(distinct persona) from choques)::text
                 || ' persona(s). Hay que decidir cuál vale ANTES de poner el candado.'
       end                                                    as veredicto,
       ''::text as tramo_a, ''::text as tramo_b, ''::text as se_pisan_en
union all
select 2, persona,
       to_char(desde_a, 'DD/MM/YY') || ' → ' || coalesce(to_char(hasta_a, 'DD/MM/YY'), 'abierto'),
       to_char(desde_b, 'DD/MM/YY') || ' → ' || coalesce(to_char(hasta_b, 'DD/MM/YY'), 'abierto'),
       lower(solape)::text || ' … ' || (case when upper_inf(solape) then 'sin fin'
                                             else (upper(solape) - 1)::text end)
  from choques
union all
select 3,
       'total de tramos en la tabla',
       (select count(*) from tramos)::text,
       (select count(distinct persona_id) from tramos)::text || ' persona(s)',
       ''
order by orden, veredicto, tramo_a;
