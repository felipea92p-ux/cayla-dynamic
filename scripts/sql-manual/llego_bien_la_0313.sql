-- ############################################################################
-- ####  ¿LLEGÓ BIEN LA 0313?  — SOLO LEE, NO ESCRIBE NADA                 ####
-- ############################################################################
--
-- Se corre DESPUÉS de pegar la 0313.
--
-- ── LA TRAMPA QUE ESTA CONSULTA EXISTE PARA EVITAR ──────────────────────────
--
-- `la_boleta_dice_lo_que_se_pago.sql` —la que encontró las 17— seguirá diciendo
-- 17 después del arreglo, y eso NO es un fallo. Esa consulta le pregunta a
-- `fn_planilla_calcular` directamente. El recálculo sigue dando otro número: lo
-- que la 0313 cambia es que la boleta deje de mostrarlo.
--
-- Ésta pregunta por el camino de verdad, el que usan las dos pantallas:
-- `fn_proyeccion_periodo`. Si la 0313 llegó bien, aquí las diferencias son 0.
--
-- ── CÓMO SE LEE ─────────────────────────────────────────────────────────────
--
--   md5_ahora = 0c9718e51240a97b809495c28a68ce93
--     → la función es la de la 0313. Si es otro, la migración no entró (o entró
--       otra cosa) y lo demás no significa nada.
--
--   personas_que_no_cuadran = 0
--     → la boleta de cada mes pagado dice exactamente lo que se pagó. Cerrado.
--
--   personas_que_no_cuadran > 0
--     → quedó alguna. Salen listadas con las dos cifras.
--
--   fuente_de_cada_periodo
--     → 'foto' en los pagados con foto, 'recalculo_sin_foto' en los pagados sin
--       ella —esos son de antes del registro congelado y la pantalla tendría que
--       avisarlo—, y 'calculo' en los abiertos, que es lo correcto.
--
-- OJO: llama a `fn_proyeccion_periodo`, que exige rol de admin, y el SQL Editor
-- no trae sesión — así que la fija ella misma. Y tarda unos segundos: la 0313
-- sigue calculando el sobre del periodo aunque las cifras salgan de la foto.
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
  select p.id, p.fecha_ini, p.fecha_fin
    from periodos_planilla p, sesion
   where p.estado = 'pagado'
),
-- Lo que la BOLETA muestra ahora, por su camino real.
boleta as (
  select pg.id                                     as periodo_id,
         (f->>'persona_id')::uuid                  as persona_id,
         f->>'nombre'                              as nombre,
         round((f->>'total')::numeric, 2)          as total_boleta
    from pagados pg
    cross join lateral jsonb_array_elements(
           fn_proyeccion_periodo(pg.id) -> 'filas') f
),
-- Y lo que se pagó: la última versión DE CADA PERSONA, igual que la 0313.
foto as (
  select distinct on (d.periodo_id, d.persona_id)
         d.periodo_id, d.persona_id, d.nombre,
         round(d.total, 2) as total_foto
    from planilla_pagada_detalle d
   where d.periodo_id in (select id from pagados)
   order by d.periodo_id, d.persona_id, d.version desc
),
descuadres as (
  select coalesce(b.nombre, f.nombre) as nombre,
         f.total_foto, b.total_boleta
    from foto f
    full join boleta b
      on b.periodo_id = f.periodo_id and b.persona_id = f.persona_id
   where coalesce(b.total_boleta, -1) is distinct from coalesce(f.total_foto, -1)
),
fuentes as (
  select string_agg(distinct fn_proyeccion_periodo(pg.id) ->> 'fuente', ', ')
    from pagados pg
)
select
  (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo')  as md5_ahora,
  (select count(*)::int from descuadres)                                 as personas_que_no_cuadran,
  (select count(*)::int from foto)                                       as personas_en_la_foto,
  (select count(*)::int from boleta)                                     as personas_en_la_boleta,
  (select * from fuentes)                                                as fuente_de_cada_periodo,
  (select string_agg(nombre || ': foto ' || coalesce(total_foto::text,'—')
                     || ' vs boleta ' || coalesce(total_boleta::text,'—'), ' | ')
     from descuadres)                                                    as quienes_no_cuadran;
