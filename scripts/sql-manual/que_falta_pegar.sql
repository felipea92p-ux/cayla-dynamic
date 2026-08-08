-- ============================================================================
-- ¿QUÉ ME FALTA PEGAR? — solo LEE, no cambia nada. Pégala en el SQL Editor.
-- ============================================================================
--
-- ⚠️ ARCHIVO GENERADO. No lo edites a mano: lo reescribe
--    ./scripts/que-falta-pegar.sh
--    y el hook de pre-push falla si se quedó viejo.
--
-- ES UNA SOLA CONSULTA, Y ESO IMPORTA. La primera versión eran tres `select`
-- seguidos, y el SQL Editor de Supabase muestra únicamente el resultado del
-- ÚLTIMO: los otros dos se ejecutaban y no los veía nadie. Una herramienta de
-- diagnóstico que esconde dos tercios de su diagnóstico es peor que no tenerla,
-- porque uno cree que ya miró.
--
-- QUÉ RESPONDE, todo en la misma tabla
--   · migración por migración, cuál falta pegar y cuál está anotada
--   · el resumen: cuántas faltan de cuántas
--   · en qué versión está VIVA `fn_planilla_calcular`
--
-- LO QUE NO PUEDE VER
--   Que una migración esté anotada NO prueba que su contenido siga vivo: una
--   pegada posterior pudo pisarlo sin dar ningún error. Por eso las dos últimas
--   filas miran el cuerpo real de la función y no el registro.
-- ============================================================================

with repo(numero, nombre) as (values
    (150, 'la_planilla_suma_la_educacion_y_exige_el_papel'),
    (151, 'el_tope_de_educacion_bajo_llave'),
    (152, 'la_movilidad_tiene_techo'),
    (153, 'la_tabla_de_desembolsos_bajo_llave'),
    (154, 'el_comprobante_pesa_hasta_50_mb'),
    (155, 'el_libro_de_desembolsos_entra_al_repositorio'),
    (156, 'la_movilidad_con_techo_se_anota'),
    (157, 'los_documentos_firmados_entran_al_sistema'),
    (158, 'las_provisiones_descuentan_lo_depositado'),
    (159, 'sin_declaracion_firmada_no_se_devenga_movilidad'),
    (160, 'quien_no_devenga_no_provisiona'),
    (161, 'el_tablero_tambien_ve_el_cargo_del_cumpleanos'),
    (162, 'el_tablero_no_le_pide_el_papel_a_quien_no_lo_firma'),
    (163, 'las_truncas_descuentan_lo_ya_depositado'),
    (164, 'la_liquidacion_por_cese_en_una_sola_cuenta'),
    (165, 'el_bono_de_onomastico_rige_desde_que_existe'),
    (166, 'la_movilidad_se_paga_por_donde_se_trabaja'),
    (167, 'la_liquidacion_pagada_se_congela'),
    (168, 'el_monto_del_libro_con_su_precision_real'),
    (169, 'un_mes_en_prueba_deja_de_ser_gratis'),
    (170, 'el_acta_acepta_la_foto_del_iphone'),
    (171, 'ni_el_plus_ni_el_rendimiento_mueven_el_sueldo'),
    (172, 'los_papeles_firmados_por_fin_se_pueden_subir'),
    (173, 'el_sueldo_fijo_no_cobra_el_feriado_dos_veces'),
    (174, 'un_cese_a_la_vez_por_persona'),
    (175, 'el_acta_de_descanso_se_guarda_donde_los_demas_papeles'),
    (176, 'quien_ya_se_fue_deja_de_tener_sueldo_vigente'),
    (177, 'las_vacaciones_se_pagan_como_dias_trabajados'),
    (178, 'caylo_deja_de_poder_asignarse'),
    (179, 'la_pantalla_de_equipo_dice_cuando_y_por_que_se_fue'),
    (180, 'el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron'),
    (181, 'los_mensajes_rotos_vuelven_a_decir_lider'),
    (182, 'el_cargo_dice_que_eres_el_rol_dice_que_abres'),
    (183, 'dos_periodos_del_mismo_mes_pagarian_el_plus_dos_veces')
),
diff as (
  select r.numero, r.nombre, (a.numero is null) as falta, a.aplicada_at
  from repo r
  left join migraciones_aplicadas a on a.numero = r.numero
)
select * from (
  -- Una fila por migración.
  select d.numero::text                        as num,
         d.nombre                              as que,
         case when d.falta then '❌  FALTA PEGAR' else '✓   aplicada' end as estado,
         to_char(d.aplicada_at, 'DD/MM/YYYY')  as cuando,
         d.numero                              as orden
  from diff d

  union all

  -- El resumen, al final y separado.
  select '——', '', '', '', 999998
  union all
  select 'RESUMEN',
         (select count(*) filter (where falta) from diff)::text || ' faltan · ' ||
         (select count(*) filter (where not falta) from diff)::text || ' aplicadas · ' ||
         (select count(*) from diff)::text || ' en el repo',
         case when (select count(*) filter (where falta) from diff) = 0
              then '✓   al día' else '❌  hay pendientes' end,
         '', 999999

  union all

  -- Y la única pregunta que el registro no puede responder.
  select 'PLANILLA',
         'fn_planilla_calcular · versión viva',
         coalesce((
           select case md5(prosrc)
             when '30e0ecbf11ac5939457df6c2b3cccc77' then '0166 — movilidad por sede física'
             when '46c6c3de546f4da080d328a079470478' then '0171 — sin plus ni rendimiento'
             when 'cb3c5de14dd2b5a8872965814d5e7cd9' then '0173 — sueldo fijo no duplica feriado'
             when '93e96e37e05799121485e5721de3dc06' then '0177 — las vacaciones se pagan'
             else '⚠ md5 SIN CATALOGAR: ' || md5(prosrc)
           end
           from pg_proc where proname = 'fn_planilla_calcular'
         ), '⚠ la función NO EXISTE'),
         '', 1000000
) t
order by orden;
