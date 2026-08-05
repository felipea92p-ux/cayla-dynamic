-- ============================================================================
-- 119_la_movilidad_tiene_techo.test.sql
-- ============================================================================
-- La 0152 pone una puerta a la entrada de parametros_laborales: nadie carga una
-- tarifa de movilidad por encima del 4 % de la RMV vigente en la fecha desde la
-- que esa tarifa rige.
--
-- Lo que se prueba, y por qué cada caso:
--
--   · S/45.20 con RMV de S/1,130 entra, S/45.21 no. El borde exacto, porque un
--     techo que se equivoca por un céntimo hacia arriba no es un techo.
--   · Las tres tarifas reales (S/10 y S/12) entran sin ruido. Si esta prueba
--     fallara, la migración estaría rompiendo un pago vivo.
--   · El techo se mide contra la RMV de la FECHA DE LA TARIFA, no la de hoy:
--     una tarifa que rige desde un periodo con RMV baja no puede colarse porque
--     la RMV subió después.
--   · Una fecha sin RMV cargada deja pasar. Falla abierto a propósito.
--   · Las otras claves de la tabla ni se enteran: cargar la RMV misma en 1,300
--     no puede activar un candado que es de movilidad.
--   · Un UPDATE también pasa por la puerta, no solo el INSERT. Editar una fila
--     buena para volverla mala es la vía más probable de que esto ocurra.
--
-- Todo en begin/rollback, con fechas de 2029 y una sede de laboratorio: al
-- terminar no queda nada.
-- ============================================================================
begin;
select plan(10);

-- ── Semilla ─────────────────────────────────────────────────────────────────
-- Una RMV propia en 2029 para no depender de la que tenga cargada la base real.
-- 4 % de 1,130 = 45.20 exactos, que es el borde que interesa.
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('rmv', 1130.00, '2029-01-01', 'Laboratorio de la prueba 119');

-- Y una segunda RMV más alta desde mitad de año, para probar que el techo se
-- mide contra la fecha de la tarifa y no contra la más reciente.
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('rmv', 2000.00, '2029-07-01', 'Laboratorio de la prueba 119 — RMV posterior');

update parametros_laborales
   set vigente_hasta = '2029-06-30'
 where clave = 'rmv' and vigente_desde = '2029-01-01';


-- ── 1 · Las tarifas reales de CAYLA entran sin ruido ────────────────────────
-- Si alguna de estas fallara, la 0152 estaría rompiendo un pago vivo.
select lives_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 10, 'ZZTRU', '2029-02-01', 'Laboratorio: la tarifa real de TRU')
$$, 'REALES · S/10 (AQP y TRU) entra: está a menos de un cuarto del techo');

select lives_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 12, 'ZZLIM', '2029-02-01', 'Laboratorio: la tarifa real de LIM')
$$, 'REALES · S/12 (LIM) entra: sigue muy por debajo del techo');


-- ── 2 · El borde exacto ─────────────────────────────────────────────────────
-- 4 % de 1,130 son 45.20. Un techo que deja pasar 45.21 no es un techo.
select lives_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 45.20, 'ZZBOR', '2029-02-01', 'Laboratorio: el borde exacto')
$$, 'BORDE · S/45.20 entra — es el 4% clavado de una RMV de S/1,130');

select throws_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 45.21, 'ZZMAL', '2029-02-01', 'Laboratorio: un céntimo de más')
$$, '23514', null,
  'BORDE · S/45.21 se rechaza — un céntimo por encima del techo ya no pasa');


-- ── 3 · El techo se mide contra la RMV de la fecha de la tarifa ─────────────
-- Desde julio de 2029 la RMV del laboratorio es S/2,000, así que el techo sube a
-- S/80. La misma tarifa de S/60 se rechaza en febrero y se acepta en agosto.
select throws_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 60, 'ZZFEC', '2029-02-01', 'Laboratorio: S/60 bajo la RMV vieja')
$$, '23514', null,
  'FECHA · S/60 se rechaza en febrero: la RMV de ese periodo es S/1,130 y el techo S/45.20');

select lives_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 60, 'ZZFEC', '2029-08-01', 'Laboratorio: S/60 bajo la RMV nueva')
$$, 'FECHA · el mismo S/60 entra en agosto: ahí la RMV es S/2,000 y el techo S/80');


-- ── 4 · Sin RMV de referencia, falla abierto ────────────────────────────────
-- 2019 es anterior a cualquier RMV cargada acá. Bloquear por la ausencia de un
-- dato de referencia sería peor que dejar pasar: es el mismo criterio que la
-- 0149 aplicó al techo de educación.
select lives_ok($$
  insert into parametros_laborales (clave, valor, sede_codigo, vigente_desde, sustento)
  values ('movilidad_diaria', 999, 'ZZVIE', '2019-01-01', 'Laboratorio: sin RMV vigente para esa fecha')
$$, 'SIN RMV · una fecha sin RMV cargada deja pasar — falla abierto a propósito');


-- ── 5 · Las otras claves ni se enteran ──────────────────────────────────────
-- El WHEN del trigger filtra en el motor. Cargar la RMV en S/1,300 no puede
-- disparar un candado que es de movilidad.
select lives_ok($$
  insert into parametros_laborales (clave, valor, vigente_desde, sustento)
  values ('rmv', 1300.00, '2029-09-01', 'Laboratorio: la RMV que viene')
$$, 'OTRAS CLAVES · cargar la RMV no pasa por el candado de movilidad');


-- ── 6 · Editar también pasa por la puerta ───────────────────────────────────
-- La vía más probable de meter una tarifa mala no es crearla: es editar una
-- buena desde la pantalla. Un trigger solo de INSERT dejaría ese hueco abierto.
select throws_ok($$
  update parametros_laborales
     set valor = 500
   where clave = 'movilidad_diaria' and sede_codigo = 'ZZTRU'
$$, '23514', null,
  'UPDATE · subir una tarifa existente a S/500 también se rechaza');

select is(
  (select valor from parametros_laborales
    where clave = 'movilidad_diaria' and sede_codigo = 'ZZTRU'),
  10::numeric(12,5),
  'UPDATE · y la tarifa queda en su valor original, sin tocar');


select * from finish();
rollback;
