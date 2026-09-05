-- ============================================================================
-- 0260 — La pantalla de Costos dice cuánto salió del banco
-- ============================================================================
--
-- QUÉ PROMETE
--   Una cifra más en `fn_costos_planilla`: `salio_del_banco`. Es lo que se le
--   transfiere a la gente MÁS los tres pagos que CAYLA hace por ella y que no
--   aparecían sumados en ninguna pantalla.
--
--   NO CAMBIA NINGUNA CIFRA EXISTENTE. `neto`, `provisiones` y `costo` salen
--   idénticos. La función solo LEE la foto de los pagos congelados: no puede
--   mover un pago ni con un error de escritura.
--
-- ── QUÉ FALTABA, MEDIDO ────────────────────────────────────────────────────
--
-- La pantalla responde dos preguntas y le faltaba la tercera:
--
--   ¿cuánto le llegó a la gente?   → «Se transfirió» (neto)
--   ¿cuánto devengué?              → «Costo real» = neto + provisiones
--   ¿cuánta plata salió?           → no estaba
--
-- Medido contra el Postgres local con un periodo cerrado de dos personas:
--
--     quien              a la persona   AFP   EsSalud   4ta   costo   BANCO
--     ────────────────   ────────────  ─────  ───────  ─────  ──────  ──────
--     locador retenido         600.00     —        —   52.17  600.00  652.17
--     trabajadora              699.19  103.74  101.70      —  839.04  904.63
--
-- La brecha grande NO es de los locadores: en quien está en planilla son
-- S/205.44 sobre S/839.04, un 24 %. El descuento de pensión sale de la cuenta de
-- CAYLA rumbo a la AFP (0110) y el 9 % de EsSalud es íntegramente de la empresa
-- (0116); ninguno de los dos estaba en «costo real», y la retención de cuarta
-- (0245) se sumó a esa lista.
--
-- ── LO QUE NO ES, Y POR QUÉ IMPORTA DECIRLO ────────────────────────────────
--
-- **No corrige «costo real».** La 0097 lo definió como «lo que recibe la persona
-- MÁS las provisiones» y esa definición es correcta para lo que sirve: la vista
-- DEVENGADA, la que usa el contador. Esta cifra es la de CAJA, y son preguntas
-- distintas. La pantalla ya tiene la costumbre de no mezclarlas —«Se transfirió»
-- y «Costo real» conviven desde la 0097— y esta se suma como una tercera.
--
-- **Y no lleva provisiones a propósito.** Se devengan este mes y se pagan
-- después. Sumarlas volvería la cifra un híbrido de caja y devengado, que es
-- justo lo que la hace difícil de leer.
--
-- QUÉ ASUME
--   Que la versión de partida es la **0099**, confirmada por
--   `./scripts/donde-vive.sh fn_costos_planilla`. El cuerpo NO se copió a ojo:
--   se extrajo del archivo de la 0099 y los cambios se aplicaron por reemplazo
--   de cadena EXACTA con conteo esperado, con un script que aborta si no cuadra.
--
--   Asume también que `v_planilla_pagada` expone la columna `fila` con el JSON
--   congelado — está desde la 0096. Los tres términos salen de ahí y NO de
--   columnas de la vista: la vista no expone `descuento_pension` ni
--   `aporte_essalud`, y ampliarla obligaría a revisar sus otros tres
--   consumidores (`fn_liquidacion`, `fn_repagar_periodo` y
--   `fn_planilla_foto_diferencias`). El `fila` ya es la fuente de la que la 0248
--   deriva `retencion_4ta`.
--
--   ⚠️ **md5 de partida — CONFIRMAR EN PRODUCCIÓN ANTES DE PEGAR.** En esta Mac
--   la función vigente da `2e960fc4db713c4fc4dad10f6c42a67b`. Ese md5 es local y
--   no vale como prueba (regla de CLAUDE.md, incidente de la 0185):
--
--       select md5(prosrc) from pg_proc p join pg_namespace n
--         on n.oid = p.pronamespace
--        where n.nspname = 'public' and p.proname = 'fn_costos_planilla';
--
-- CÓMO SE REVIERTE
--   Restaurar `fn_costos_planilla` desde la 0099, tal cual. No toca tablas, ni
--   vistas, ni datos, ni permisos.
-- ============================================================================

create or replace function fn_costos_planilla(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver los costos de planilla.';
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'El rango de fechas no es válido.';
  end if;

  with base as (
    select
      f.*,
      pp.fecha_ini,
      pp.fecha_fin,
      pp.pagado_at,
      extract(year  from pp.fecha_fin)::int as anio,
      extract(month from pp.fecha_fin)::int as mes,
      coalesce(se.tipo, 'tienda') as sede_tipo,
      coalesce(se.nombre, f.sede_codigo) as sede_nombre,
      -- ⇩⇩⇩ CAMBIO 0260 ⇩⇩⇩ LOS TRES PAGOS QUE SALEN Y NO SE SUMABAN.
      -- Salen del `fila` congelado, no de columnas de la vista: la vista no
      -- expone los dos primeros, y ampliarla obligaría a revisar sus otros
      -- tres consumidores. El `fila` ya viaja en ella, y es de donde la 0248
      -- deriva `retencion_4ta`.
      -- Con `coalesce` a 0 porque una foto RECONSTRUIDA (origen
      -- 'retroactivo') puede no traer la clave: entonces esta cifra vale lo
      -- mismo que el neto, que es lo que se sabía de ese periodo.
      coalesce((f.fila->>'descuento_afp')::numeric, 0)  as pension_remitida,
      coalesce((f.fila->>'aporte_essalud')::numeric, 0) as essalud_empresa,
      coalesce((f.fila->>'retencion_4ta')::numeric, 0)  as retencion_remitida
    from v_planilla_pagada f
    join periodos_planilla pp on pp.id = f.periodo_id
    left join sedes se on se.codigo = f.sede_codigo
    where pp.estado = 'pagado'
      and pp.fecha_fin between p_desde and p_hasta
  )
  select jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,

    'periodos_retroactivos', (
      select count(distinct periodo_id)::int from base where origen = 'retroactivo'
    ),

    'totales', (
      select jsonb_build_object(
        'personas',    count(distinct persona_id),
        'periodos',    count(distinct periodo_id),
        'neto',        coalesce(round(sum(total), 2), 0),
        'provisiones', coalesce(round(sum(provision_total), 2), 0),
        'costo',       coalesce(round(sum(costo_total), 2), 0),
        'salio_del_banco', coalesce(round(sum(total + pension_remitida + essalud_empresa + retencion_remitida), 2), 0)   -- CAMBIO 0260
      ) from base
    ),

    'por_periodo', (
      select coalesce(jsonb_agg(x order by x->>'fecha_fin' desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'periodo_id',  b.periodo_id,
          'fecha_ini',   b.fecha_ini,
          'fecha_fin',   b.fecha_fin,
          'anio',        b.anio,
          'mes',         b.mes,
          'pagado_at',   max(b.pagado_at),
          'congelada_at', max(b.congelada_at),
          'version',     max(b.version),
          'reconstruida', bool_or(b.origen = 'retroactivo'),
          'personas',    count(*),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2)   -- CAMBIO 0260
        ) as x
        from base b
        group by b.periodo_id, b.fecha_ini, b.fecha_fin, b.anio, b.mes
      ) s
    ),

    -- ⇩ NUEVO 0099: el tipo, y las dos cifras que sí permiten comparar.
    -- El costo por persona se calcula sobre personas DISTINTAS, no sobre filas:
    -- alguien que cobró en tres periodos es una persona, no tres.
    'por_sede', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'sede',        b.sede_codigo,
          'nombre',      b.sede_nombre,
          'tipo',        b.sede_tipo,
          'personas',    count(distinct b.persona_id),
          'horas',       round(sum(b.horas_mes), 2),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2),   -- CAMBIO 0260
          'costo_por_persona', round(sum(b.costo_total) / nullif(count(distinct b.persona_id), 0), 2),
          'costo_por_hora',    round(sum(b.costo_total) / nullif(sum(b.horas_mes), 0), 2)
        ) as x
        from base b
        group by b.sede_codigo, b.sede_nombre, b.sede_tipo
      ) s
    ),

    -- Operar las tiendas cuesta X · producir en el taller cuesta Y ·
    -- administrar cuesta Z. Es la lectura que el total por sede no da.
    'por_tipo', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'tipo',        b.sede_tipo,
          'sedes',       count(distinct b.sede_codigo),
          'personas',    count(distinct b.persona_id),
          'horas',       round(sum(b.horas_mes), 2),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2),   -- CAMBIO 0260
          'costo_por_persona', round(sum(b.costo_total) / nullif(count(distinct b.persona_id), 0), 2),
          'costo_por_hora',    round(sum(b.costo_total) / nullif(sum(b.horas_mes), 0), 2)
        ) as x
        from base b
        group by b.sede_tipo
      ) s
    ),

    'por_area', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'area',        b.area_codigo,
          'nombre',      coalesce(ar.nombre, b.area_codigo, 'Sin área'),
          'operativa',   coalesce(ar.operativa, false),
          'personas',    count(distinct b.persona_id),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2)   -- CAMBIO 0260
        ) as x
        from base b
        left join areas ar on ar.codigo = b.area_codigo
        group by b.area_codigo, ar.nombre, ar.operativa
      ) s
    ),

    'por_persona', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'persona_id',  b.persona_id,
          'nombre',      max(b.nombre),
          'sede',        max(b.sede_codigo),
          'area',        max(b.area_codigo),
          'periodos',    count(*),
          'horas',       round(sum(b.horas_mes), 2),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2)   -- CAMBIO 0260
        ) as x
        from base b
        group by b.persona_id
      ) s
    )
  ) into v_out;

  return v_out;
end;
$fn$;
-- ── Comprobaciones de que quedó puesto ──────────────────────────────────────
select
  (select (length(prosrc) - length(replace(prosrc, 'CAMBIO 0260', ''))) / length('CAMBIO 0260')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_costos_planilla')
    as marcas_0260_esperadas_7,

  -- Los seis agregados tienen que haber aprendido la cifra: el total, por
  -- periodo, por sede, por área y los dos cruces. Si sale menos, alguno se
  -- quedó atrás y su tabla mostraría una columna vacía.
  (select (length(prosrc) - length(replace(prosrc, 'salio_del_banco', ''))) / length('salio_del_banco')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_costos_planilla')
    as claves_esperadas_6,

  -- Y que la 0099 siga entera: el tipo de sede es lo que ella agregó.
  (select prosrc ~ 'sede_tipo'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_costos_planilla')
    as la_0099_sigue_puesta;

insert into migraciones_aplicadas (numero, nombre)
values (260, 'la_pantalla_de_costos_dice_cuanto_salio_del_banco')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
