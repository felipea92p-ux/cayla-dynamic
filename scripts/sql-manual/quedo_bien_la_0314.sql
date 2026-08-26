-- ============================================================================
-- ¿QUEDÓ BIEN LA 0314, Y NO SE LLEVÓ NADA POR DELANTE?
-- ============================================================================
-- Solo LEE. Se pega entero en el SQL Editor de Supabase.
--
-- La 0314 se pegó SIN pedir antes el md5 de partida a producción, que es el
-- paso que la casa exige justo antes de entregar. No pasa nada malo por sí
-- solo: lo que hace ese md5 es avisar de que producción tenía una versión más
-- nueva que la de partida, en cuyo caso pegar la revierte EN SILENCIO. Esta
-- consulta lo comprueba después, que es lo que queda por hacer.
--
-- CÓMO SE LEE LA FILA QUE DEVUELVE
--
--   md5_ahora = c8070bb865e977d2d0e6b1bb4bac58d2  y  chars_ahora = 102178
--     → la 0314 quedó EXACTA. Todo bien, nada que revisar.
--
--   tiene_la_0314 = false
--     → la migración NO se aplicó. Mirar qué devolvió el SQL Editor.
--
--   cascadas_laborables_debe_ser_4 <> 4
--     → se perdió un lateral de «¿le tocaba trabajar ese día?» (la 0302).
--
--   tiene_la_0314 = true pero el md5 NO coincide
--     → se aplicó, pero el cuerpo no es el esperado. Las columnas
--       `sigue_la_0NNN` de abajo dicen cuál se perdió. Cualquiera en false es
--       una migración REVERTIDA y hay que repegarla.
--
--   sobrecargas > 1
--     → hay DOS funciones fn_planilla_calcular conviviendo. Es el accidente de
--       la 0297/0299: no falla al pegar, falla al abrir la pantalla.
--
--   licencias_en_periodo_pagado > 0
--     → a esa persona se le pagó de menos ANTES de la 0314. Hay que devolverle
--       la diferencia; la 0314 solo evita que vuelva a pasar.
-- ============================================================================

select
  -- 1 · ¿el cuerpo es el que se pegó?
  (select md5(prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')      as md5_ahora,
  (select length(prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')      as chars_ahora,
  (select position('CAMBIO 0314' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')      as tiene_la_0314,

  -- 2 · ¿SIGUE ahí lo que otras migraciones metieron? Cualquier false es una
  --     reversión silenciosa, que es el daño exacto del que avisa el md5.
  (select position('CAMBIO 0275' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')      as sigue_la_0275_vacaciones,
  (select position('CAMBIO 0286' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')      as sigue_la_0286_dia_fichado,
  -- La 0302 no dejó marcador propio, así que se cuenta su huella: los CUATRO
  -- laterales que preguntan «¿le tocaba trabajar ese día?». Si baja de 4, uno se
  -- perdió y alguien está devengando por días de calendario.
  (select (length(prosrc) - length(replace(prosrc, 'any(hv.dias_laborables)', '')))
          / length('any(hv.dias_laborables)')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')      as cascadas_laborables_debe_ser_4,
  (select position('CAMBIO 0306' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')      as sigue_la_0306_aprobacion,

  -- 3 · el accidente de la 0297/0299: dos funciones con el mismo nombre
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')      as sobrecargas,

  -- 4 · el catálogo
  (select paga from tipos_ausencia where codigo = 'duelo_familiar_directo') as duelo_directo_paga,
  (select requiere_aprobacion from tipos_ausencia where codigo = 'duelo_familiar_directo')
                                                                            as duelo_directo_pide_firma,
  (select nombre from tipos_ausencia where codigo = 'duelo')                as nombre_del_otro_duelo,
  (select count(*) = 1 from migraciones_aplicadas where numero = 314)       as quedo_el_rastro,

  -- 5 · lo que faltaba por preguntar: ¿le costó plata a alguien?
  (select count(*) from ausencias
    where tipo = 'licencia_con_goce' and anulada_at is null)                as licencias_total,
  (select count(*)
     from ausencias a
     join periodos_planilla pp
       on pp.estado = 'pagado'
      and a.fecha_inicio <= pp.fecha_fin
      and a.fecha_fin    >= pp.fecha_ini
    where a.tipo = 'licencia_con_goce' and a.anulada_at is null)            as licencias_en_periodo_pagado,
  (select count(distinct a.persona_id)
     from ausencias a
     join periodos_planilla pp
       on pp.estado = 'pagado'
      and a.fecha_inicio <= pp.fecha_fin
      and a.fecha_fin    >= pp.fecha_ini
    where a.tipo = 'licencia_con_goce' and a.anulada_at is null)            as personas_afectadas;
