-- ============================================================================
-- adelantos_de_cts_en_ventana_equivocada.sql — SOLO LECTURA
-- ============================================================================
-- QUÉ BUSCA
--   Filas de `desembolsos_beneficios` de CTS cuya ventana/año no cuadra con el
--   periodo que contiene su fecha de pago, según la MISMA regla que usa
--   `fn_cts_trunca` (0278) para ubicar un cese:
--     ene–abr → cts_may del mismo año   (periodo nov anterior–abr)
--     may–oct → cts_nov del mismo año   (periodo may–oct)
--     nov–dic → cts_may del año SIGUIENTE (periodo nov–abr)
--
-- POR QUÉ
--   El modal «Adelanto de beneficio» de Planilla (0343) decidía la CTS con
--   «mes <= 6 → cts_may, si no cts_nov» —la regla de la gratificación— y
--   anotaba siempre origen 'transferencia' y año del pago. Así, una CTS
--   adelantada en mayo o junio quedó en cts_may (ventana ya depositada) y una de
--   noviembre o diciembre en cts_nov del mismo año. Esas filas las restan
--   `fn_provisiones`, `fn_cts_trunca` y la liquidación.
--
-- CÓMO LEER EL VEREDICTO
--   · «no cuadra»            → la fecha cae en otro periodo. Hay que decidir.
--   · «puede ser un depósito atrasado» → la fecha cae entre el 1 y el 15 del
--     mes siguiente al cierre de la ventana anotada (ej. cts_may pagada el
--     10/05). La fecha sola no distingue un adelanto del periodo nuevo de un
--     depósito tardío del anterior: mirar la nota.
--   Las filas que cuadran no salen.
--
-- Se pega en el SQL Editor tal cual. No escribe nada.
-- ============================================================================

with cts as (
  select d.id, d.persona_id, d.ventana, d.anio, d.monto, d.fecha_pago, d.origen, d.nota,
         d.created_at, d.registrado_por,
         extract(month from d.fecha_pago)::int as mes,
         extract(year  from d.fecha_pago)::int as y
    from desembolsos_beneficios d
   where d.ventana in ('cts_may', 'cts_nov')
),
esperado as (
  select c.*,
         case when c.mes <= 4 then 'cts_may' when c.mes <= 10 then 'cts_nov' else 'cts_may' end as ventana_segun_fecha,
         case when c.mes >= 11 then c.y + 1 else c.y end                                          as anio_segun_fecha
    from cts c
)
select
  p.nombres || ' ' || p.apellidos                         as persona,
  p.estado,
  p.fecha_cese,
  e.ventana || ' ' || e.anio                              as anotada_como,
  e.ventana_segun_fecha || ' ' || e.anio_segun_fecha      as segun_su_fecha,
  e.monto,
  e.fecha_pago,
  e.origen,
  e.nota,
  (e.created_at at time zone 'America/Lima')::date        as anotada_el,
  quien.nombres || ' ' || quien.apellidos                 as anotada_por,
  case
    when (e.ventana = 'cts_may' and e.fecha_pago between make_date(e.anio, 5, 1) and make_date(e.anio, 5, 15))
      or (e.ventana = 'cts_nov' and e.fecha_pago between make_date(e.anio, 11, 1) and make_date(e.anio, 11, 15))
      then 'puede ser un depósito atrasado'
    else 'no cuadra'
  end                                                      as veredicto,
  e.id                                                     as desembolso_id
from esperado e
join personas p on p.id = e.persona_id
left join personas quien on quien.id = e.registrado_por
where (e.ventana, e.anio) is distinct from (e.ventana_segun_fecha, e.anio_segun_fecha)
-- Primero lo que no cuadra; lo dudoso (posible depósito atrasado) al final.
-- «no cuadra» < «puede ser…» en orden alfabético; Postgres no deja usar el
-- alias dentro de una expresión, solo el alias suelto.
order by veredicto, e.fecha_pago;

-- Y el total de la población, para saber de qué tamaño es la decisión:
select e.origen,
       count(*)                                                                         as filas_cts,
       count(*) filter (where (e.ventana, e.anio) is distinct from (e.ventana_segun_fecha, e.anio_segun_fecha)) as no_cuadran
  from (
    select d.*,
           case when extract(month from d.fecha_pago) <= 4 then 'cts_may'
                when extract(month from d.fecha_pago) <= 10 then 'cts_nov' else 'cts_may' end as ventana_segun_fecha,
           case when extract(month from d.fecha_pago) >= 11 then extract(year from d.fecha_pago)::int + 1
                else extract(year from d.fecha_pago)::int end                                   as anio_segun_fecha
      from desembolsos_beneficios d
     where d.ventana in ('cts_may', 'cts_nov')
  ) e
 group by e.origen
 order by e.origen;
