-- ============================================================================
-- ¿QUEDÓ BIEN LA 0317, Y NO SE LLEVÓ NADA POR DELANTE?
-- ============================================================================
-- Solo LEE. Se pega entero en el SQL Editor de Supabase, DESPUÉS de la 0317.
--
-- Existe por lo que pasó con la 0314 el 2026-08-26: se pegó, no se aplicó nada,
-- y no hubo error visible. Un «seis true» dice que la migración hizo lo suyo;
-- no dice qué se llevó por delante. Son dos preguntas y esta es la segunda.
--
-- CÓMO SE LEE LA FILA QUE DEVUELVE
--
--   md5_ahora = 6838c789a2f2444166f2dbebfd9faa0d  y  chars_ahora = 107341
--     → la 0317 quedó EXACTA. Todo bien.
--
--   tiene_la_0317 = false
--     → no se aplicó. Mirar qué devolvió el SQL Editor.
--
--   tiene_la_0317 = true pero el md5 NO coincide
--     → se aplicó y el cuerpo no es el esperado. Las columnas `sigue_...` de
--       abajo dicen cuál se perdió. Cualquiera en false es una REVERSIÓN.
--
--   sobrecargas > 1
--     → hay DOS fn_planilla_calcular conviviendo (el accidente 0297/0299). No
--       falla al pegar: falla al abrir la pantalla.
-- ============================================================================

select
  (select md5(prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as md5_ahora,
  (select length(prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as chars_ahora,
  (select position('CAMBIO 0317' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as tiene_la_0317,

  -- Lo que NO se puede haber perdido al reescribir la función
  (select position('pb.monto_descanso_medico, 0), 2)' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as sigue_la_0263_descanso_medico,
  (select position('pb.monto_subsidio_maternidad, 0), 2)' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as sigue_la_0262_maternidad,
  (select position('t.codigo = a.tipo and t.paga' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as sigue_la_0314_catalogo,
  (select position('pb.monto_licencia_con_goce, 0), 2)' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as sigue_la_0316_licencia,
  (select position('CAMBIO 0275' in prosrc) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as sigue_la_0275_vacaciones,
  (select (length(prosrc) - length(replace(prosrc, 'any(hv.dias_laborables)', '')))
          / length('any(hv.dias_laborables)')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as cascadas_laborables_debe_ser_4,

  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')       as sobrecargas,

  (select nombre from tipos_ausencia where codigo = 'duelo_familiar_directo') as nombre_del_duelo_directo,
  (select count(*) = 1 from migraciones_aplicadas where numero = 317)         as quedo_el_rastro;
