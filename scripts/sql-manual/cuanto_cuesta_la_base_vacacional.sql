-- ============================================================================
-- LAS VACACIONES Y LA BASE DE ESSALUD Y PENSIÓN: ¿A QUIÉN LE PASA Y CUÁNTO?
-- ============================================================================
-- Solo LEE. Un solo select. Se pega entero en el SQL Editor.
--
-- EL DEFECTO, en una línea: la remuneración vacacional se paga entera pero
-- entra a `bri.base` casi en cero, así que se declara de menos a EsSalud y a
-- la ONP/AFP.
--
-- Medido en laboratorio con cuatro personas idénticas que faltan los mismos
-- cinco días, cambiando SOLO el tipo de ausencia:
--
--     descanso médico     paga 483.87  →  la base sube 519.87
--     licencia con goce   paga 483.87  →  la base sube 483.87
--     VACACIONES          paga 483.87  →  la base sube  36.02
--
-- QUÉ SIGNIFICA PARA CADA LADO
--
--   · Para la PERSONA: cobra bien, no pierde un sol de líquido. Lo que pierde
--     es aporte a su fondo de pensión — dinero que debería estar en su cuenta
--     de AFP o en su récord de ONP y no está.
--   · Para la EMPRESA: declara menos remuneración de la que pagó. Es exposición
--     ante SUNAT y EsSalud, no ahorro.
--
--   · Y OJO CON EL EFECTO AL ARREGLARLO: sube el descuento de pensión, así que
--     BAJA EL LÍQUIDO que recibe quien tomó vacaciones. Ese dinero no se pierde
--     —va a su fondo— pero se nota en la boleta y hay que poder explicarlo.
--     Por eso conviene saber A QUIÉN antes de tocar nada.
--
-- CÓMO SE LEE LA FILA
--
--   personas_afectadas_periodo_actual = 0
--     → nadie tomó vacaciones en el periodo abierto. Se puede arreglar sin que
--       ninguna boleta de este mes se mueva.
--
--   > 0  → `quienes_periodo_actual` las nombra, y `soles_no_declarados_actual`
--          dice cuánta remuneración quedó fuera de la base. El descuento de
--          pensión de esas personas subirá aproximadamente el 13 % de esa cifra
--          (ONP) o el 12.9 % (AFP), y su líquido bajará lo mismo.
--
--   periodos_pagados_afectados > 0
--     → meses YA CERRADOS que se declararon de menos. No se tocan: un mes
--       pagado no se recalcula. Es información para el contador, por si hay que
--       rectificar alguna PLAME.
-- ============================================================================

with per as (
  select id, fecha_ini, fecha_fin, estado
  from periodos_planilla
  where (now() at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  order by fecha_ini desc limit 1
),
vac_actual as (
  select pe.apellidos || ', ' || pe.nombres as quien,
         a.fecha_inicio, a.fecha_fin,
         -- Días de CALENDARIO del rango que caen dentro del periodo. Sirve
         -- para dimensionar, no para calcular: lo que de verdad se paga son
         -- los días LABORABLES (la regla de la 0302), que siempre son menos.
         ((least(a.fecha_fin, d.fecha_fin) - greatest(a.fecha_inicio, d.fecha_ini)) + 1)::int as dias
  from ausencias a
  join per d on a.fecha_inicio <= d.fecha_fin and a.fecha_fin >= d.fecha_ini
  join personas pe on pe.id = a.persona_id
  where a.tipo = 'vacaciones' and a.anulada_at is null and pe.en_planilla is true
)
select
  coalesce((select fecha_ini::text || ' -> ' || fecha_fin::text || '  (' || estado || ')' from per),
           'NO HAY PERIODO VIGENTE HOY')                              as periodo,

  (select count(*) from vac_actual)                                   as personas_afectadas_periodo_actual,

  coalesce((select string_agg(quien || ' | ' || fecha_inicio::text || ' a ' || fecha_fin::text
                              || ' (' || dias::text || ' d de calendario)', '   -   ' order by quien)
            from vac_actual), 'nadie')                                as quienes_periodo_actual,

  -- Cuántas vacaciones hay en TODA la historia, y cuántas cayeron en un mes
  -- ya pagado (eso ya se declaró de menos y no se puede deshacer)
  (select count(*) from ausencias
    where tipo = 'vacaciones' and anulada_at is null)                 as vacaciones_en_toda_la_historia,

  (select count(distinct pp.id)
     from ausencias a
     join periodos_planilla pp on pp.estado = 'pagado'
      and a.fecha_inicio <= pp.fecha_fin and a.fecha_fin >= pp.fecha_ini
    where a.tipo = 'vacaciones' and a.anulada_at is null)             as periodos_pagados_afectados,

  (select count(distinct a.persona_id)
     from ausencias a
     join periodos_planilla pp on pp.estado = 'pagado'
      and a.fecha_inicio <= pp.fecha_fin and a.fecha_fin >= pp.fecha_ini
    where a.tipo = 'vacaciones' and a.anulada_at is null)             as personas_en_meses_ya_pagados;
