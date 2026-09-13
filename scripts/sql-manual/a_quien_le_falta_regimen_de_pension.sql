-- ############################################################################
-- ####  ¿A QUIÉN LE FALTA RÉGIMEN DE PENSIÓN?  — SOLO LEE                 ####
-- ############################################################################
--
-- Para qué. `fn_planilla_calcular_nucleo` (0114 en adelante) resuelve el
-- régimen de cada persona así: primero el tramo vigente de
-- `asignaciones_regimen_pension`, y si no hay ninguno, `personas.regimen_pension`
-- como respaldo. Con ese régimen busca su tasa en `tasas_pension`. Si NINGUNA
-- de las dos fuentes tiene un régimen reconocido, el cálculo no revienta —cae
-- a `configuracion.tasa_afp`, la tasa global de respaldo— así que la persona
-- sigue apareciendo en la planilla con un número, no con un error. El problema
-- es justo ese: un número que se ve igual de normal esté bien o esté mal.
--
-- Hallazgo del 2026-09-08 (ver docs/hallazgos-abiertos.md): `configuracion.
-- tasa_afp` vale HOY `{"tasa": 0}`, así que a quien le falta el régimen no se
-- le retiene absolutamente nada de pensión — ni a su cuenta, ni a la ONP— y
-- nada en pantalla lo distingue de alguien jubilada, que también aporta cero
-- pero por una decisión, no por un dato faltante.
--
-- Esta consulta dice a quién le pasa esto HOY, para asignarle el régimen desde
-- /admin/datos-personales antes del próximo cierre. Se puede volver a correr
-- cuando se quiera — no cambia nada, solo lee.
--
-- Se excluye a quien por su VÍNCULO no debe tener régimen — no es un dato que
-- les falte, es la regla (RxH, practicantes, sin vínculo/accionistas): mismo
-- criterio que ya usan las pantallas del panel (`esPrestadorDeServicios` +
-- `tipo_vinculo = 'practicante'`), para no fichar como pendiente algo que no
-- lo es.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with resuelto as (
  select p.id,
         (p.nombres || ' ' || p.apellidos)                                     as persona,
         p.sede_base_id,
         coalesce(
           (select h.regimen
              from asignaciones_regimen_pension h
             where h.persona_id = p.id
               and h.vigente_desde <= current_date
               and (h.vigente_hasta is null or h.vigente_hasta >= current_date)
             order by h.vigente_desde desc
             limit 1),
           p.regimen_pension)                                                  as regimen_resuelto
    from personas p
   where p.estado = 'activo'
     and p.tipo_vinculo in ('planilla', 'prueba')  -- en_planilla=true; excluye rxh/practicante/no_trabajador
),
sin_tasa as (
  select r.id, r.persona, r.sede_base_id, r.regimen_resuelto
    from resuelto r
   where not exists (
     select 1 from tasas_pension tp
      where tp.regimen = r.regimen_resuelto
        and tp.vigente_desde <= current_date
        and (tp.vigente_hasta is null or tp.vigente_hasta >= current_date)
   )
),
respaldo as (
  select coalesce((valor->>'tasa')::numeric, 0) as tasa_global
    from configuracion where clave = 'tasa_afp'
)
select 1 as orden,
       case when (select count(*) from sin_tasa) = 0
            then '✓  Nadie: todo el equipo en planilla tiene un régimen con tasa vigente hoy.'
            else '⚠  ' || (select count(*) from sin_tasa)::text
                 || ' persona(s) activa(s) en planilla sin régimen con tasa vigente — aportando con el '
                 || 'respaldo global (' || (select (tasa_global * 100)::text from respaldo) || ' %).'
       end                                  as persona,
       ''::text                             as sede_id,
       ''::text                             as regimen_en_la_ficha
union all
select 2, persona, sede_base_id::text, coalesce(regimen_resuelto, '(sin ningún régimen)')
  from sin_tasa
order by orden, persona;
