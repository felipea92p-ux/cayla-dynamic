-- ============================================================================
-- ¿EL PADRÓN DICE LO MISMO QUE LA PLANILLA PAGA? — solo LEE. SQL Editor.
-- ============================================================================
--
-- EL PROBLEMA. Hay DOS campos distintos, en DOS tablas distintas, para la misma
-- pregunta —«¿tiene hijos menores a su cargo?»— y nada los mantiene de acuerdo:
--
--   personas.con_hijos            (0025, boolean not null default false)
--       · lo escribe la pantalla de EQUIPO, con fn_set_con_hijos
--       · es el que DECIDE EL PAGO: fn_planilla_calcular hace
--         `case when pe.con_hijos then round(v_asig,2) else 0 end`
--
--   datos_personales.hijos_menores  (0061, boolean NULLABLE)
--       · lo escribe la pantalla de DATOS PERSONALES, con fn_set_datos_personales
--       · es el que SALE EN EL PADRÓN que va al contador para el T-Registro
--
-- Ninguna migración menciona los dos a la vez. Ninguna pantalla escribe los dos.
-- Comprobado con grep sobre supabase/migrations y sobre apps/web.
--
-- POR QUÉ IMPORTA. La asignación familiar son S/113 al mes (10% de la RMV) y es
-- un derecho, no una liberalidad. Los dos desacuerdos posibles duelen distinto:
--
--   · paga y NO declara  → se le abona bien, pero el papel que la empresa emite
--     dice lo contrario. En una fiscalización el documento propio contradice la
--     planilla propia.
--   · declara y NO paga  → el padrón le dice al contador que tiene hijos, y la
--     planilla le abona S/0. Es plata que la ley le debe a esa persona.
--
-- Y HAY UN TERCER ESTADO que el padrón hoy borra: `hijos_menores` es NULL
-- cuando nadie ha llenado la ficha. La pantalla lo imprime como «NO», así que
-- el padrón AFIRMA algo que en realidad no se sabe.
--
-- NO DEVUELVE DATOS PERSONALES: solo cuentas. Se puede compartir el resultado.
-- Si alguna fila sale distinta de cero, la consulta que da los nombres se pide
-- aparte.
-- ============================================================================

with base as (
  select
    p.id,
    p.con_hijos                          as paga,       -- lo que decide el pago
    d.hijos_menores                      as declara,    -- lo que sale en el padrón
    (d.persona_id is null)               as sin_ficha
  from personas p
  left join datos_personales d on d.persona_id = p.id
  where p.estado = 'activo'
    and p.en_planilla is not false       -- un locador no cobra asignación familiar
)
select * from (
  select 0 as orden,
         'Personas activas en planilla' as que_se_mide,
         count(*)::text as cuantas,
         '' as por_que_importa
  from base

  union all
  select 1,
         case when count(*) = 0 then 'De acuerdo: paga y declara lo mismo'
              else 'De acuerdo: paga y declara lo mismo' end,
         count(*)::text,
         'Estas están bien'
  from base where declara is not null and paga = declara

  union all
  select 2,
         case when count(*) = 0 then 'PAGA pero el padrón dice NO'
              else '⚠ PAGA pero el padrón dice NO' end,
         count(*)::text,
         'Se le abona S/113 y el papel que la empresa emite lo niega'
  from base where paga is true and declara is distinct from true

  union all
  select 3,
         case when count(*) = 0 then 'DECLARA hijos pero no se le paga'
              else '⚠ DECLARA hijos pero NO se le paga' end,
         count(*)::text,
         'Plata que la ley le debe a esa persona: S/113 por periodo'
  from base where declara is true and paga is not true

  union all
  select 4,
         case when count(*) = 0 then 'Sin dato en la ficha (el padrón imprime NO)'
              else '⚠ Sin dato en la ficha — el padrón AFIRMA un NO que nadie declaró' end,
         count(*)::text,
         'Tres estados colapsados en dos: true, false y "no se sabe"'
  from base where sin_ficha or declara is null

  union all
  select 5,
         'De esas, cuántas además SÍ cobran asignación',
         count(*)::text,
         'Son las que hoy ya cobran y el padrón niega'
  from base where (sin_ficha or declara is null) and paga is true
) x
order by orden;
