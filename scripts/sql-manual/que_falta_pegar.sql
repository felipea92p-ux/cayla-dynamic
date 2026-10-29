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

with repo(numero, nombre, nunca) as (values
    (150, 'la_planilla_suma_la_educacion_y_exige_el_papel', false),
    (151, 'el_tope_de_educacion_bajo_llave', false),
    (152, 'la_movilidad_tiene_techo', false),
    (153, 'la_tabla_de_desembolsos_bajo_llave', false),
    (154, 'el_comprobante_pesa_hasta_50_mb', false),
    (155, 'el_libro_de_desembolsos_entra_al_repositorio', false),
    (156, 'la_movilidad_con_techo_se_anota', false),
    (157, 'los_documentos_firmados_entran_al_sistema', false),
    (158, 'las_provisiones_descuentan_lo_depositado', false),
    (159, 'sin_declaracion_firmada_no_se_devenga_movilidad', false),
    (160, 'quien_no_devenga_no_provisiona', false),
    (161, 'el_tablero_tambien_ve_el_cargo_del_cumpleanos', false),
    (162, 'el_tablero_no_le_pide_el_papel_a_quien_no_lo_firma', false),
    (163, 'las_truncas_descuentan_lo_ya_depositado', false),
    (164, 'la_liquidacion_por_cese_en_una_sola_cuenta', false),
    (165, 'el_bono_de_onomastico_rige_desde_que_existe', false),
    (166, 'la_movilidad_se_paga_por_donde_se_trabaja', false),
    (167, 'la_liquidacion_pagada_se_congela', false),
    (168, 'el_monto_del_libro_con_su_precision_real', false),
    (169, 'un_mes_en_prueba_deja_de_ser_gratis', false),
    (170, 'el_acta_acepta_la_foto_del_iphone', false),
    (171, 'ni_el_plus_ni_el_rendimiento_mueven_el_sueldo', false),
    (172, 'los_papeles_firmados_por_fin_se_pueden_subir', false),
    (173, 'el_sueldo_fijo_no_cobra_el_feriado_dos_veces', false),
    (174, 'un_cese_a_la_vez_por_persona', false),
    (175, 'el_acta_de_descanso_se_guarda_donde_los_demas_papeles', false),
    (176, 'quien_ya_se_fue_deja_de_tener_sueldo_vigente', false),
    (177, 'las_vacaciones_se_pagan_como_dias_trabajados', false),
    (178, 'caylo_deja_de_poder_asignarse', false),
    (179, 'la_pantalla_de_equipo_dice_cuando_y_por_que_se_fue', false),
    (180, 'el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron', false),
    (181, 'los_mensajes_rotos_vuelven_a_decir_lider', false),
    (182, 'el_cargo_dice_que_eres_el_rol_dice_que_abres', false),
    (183, 'los_periodos_vuelven_a_la_version_que_dice_el_repositorio', false),
    (184, 'las_dos_puertas_de_horario_que_nadie_usa_se_cierran', false),
    (185, 'el_sobretiempo_se_calcula_y_se_paga', false),
    (186, 'un_locador_no_cobra_vacaciones', false),
    (187, 'el_personal_de_direccion_no_genera_sobretiempo', false),
    (188, 'el_resellado_del_dia_entra_al_repositorio', false),
    (189, 'una_tardanza_de_tres_horas_deja_de_desaparecer', false),
    (190, 'quien_ya_se_jubilo_deja_de_aportar', false),
    (191, 'a_un_locador_no_se_le_mide_la_hora_de_entrada', false),
    (192, 'la_base_imponible_se_dice_una_sola_vez', false),
    (193, 'el_feriado_y_el_sobretiempo_entran_a_la_base_de_aportes', false),
    (194, 'el_interruptor_de_beneficios_por_persona_entra_al_repositorio', false),
    (195, 'las_cuatro_funciones_que_el_repositorio_no_conocia', false),
    (196, 'tres_puertas_en_vez_de_una_para_los_beneficios', false),
    (197, 'el_certificado_medico_se_guarda_y_los_20_dias_avisan', false),
    (198, 'el_cuspp_y_el_correo_entran_a_la_ficha', false),
    (199, 'un_locador_no_cobra_feriados_ni_aparece_provisionando', false),
    (200, 'el_semaforo_sabe_en_que_escalon_esta_cada_quien', false),
    (201, 'la_foto_del_pago_aprende_el_sobretiempo', false),
    (202, 'un_terminal_activo_sin_dueno_deja_de_poder_existir', false),
    (203, 'lo_que_se_congela_al_pagar_se_descongela_al_reabrir', false),
    (204, 'un_drop_se_lleva_el_permiso_y_la_pantalla_se_calla', false),
    (205, 'la_carta_de_despido_lleva_su_fecha_de_cese', false),
    (206, 'el_descargo_entra_al_legajo_y_la_imputacion_se_puede_cerrar', false),
    (207, 'una_marca_que_cae_en_un_periodo_pagado_deja_de_entrar_muda', false),
    (208, 'el_reglamento_se_entrega_y_queda_constancia', false),
    (209, 'reactivar_devuelve_el_sueldo_desde_el_dia_que_vuelve', false),
    (210, 'la_planilla_ve_la_liquidacion_que_ya_se_pago', false),
    (211, 'reemplazar_la_politica_de_movilidad_la_reemplaza', false),
    (212, 'ninguna_sancion_sin_escuchar_antes', false),
    (213, 'solo_agrava_lo_que_se_entrego', true),
    (214, 'la_carta_de_despido_la_firma_gerencia_general', false),
    (215, 'los_cinco_anexos_del_reglamento', false),
    (216, 'el_tipo_de_cada_sede_que_retail_necesita', false),
    (217, 'el_cajon_retail_y_sus_permisos', false),
    (218, 'retail_lee_la_identidad_de_dynamic', false),
    (219, 'el_catalogo_de_tiendas_entra_al_cajon', false),
    (220, 'la_operacion_de_tiendas_entra_al_cajon', false),
    (221, 'contabilidad_y_produccion_entran_al_cajon', false),
    (222, 'las_funciones_que_mueven_stock_caja_y_ventas', false),
    (223, 'las_funciones_de_finanzas_del_cajon', false),
    (224, 'las_funciones_de_produccion_del_taller', false),
    (225, 'el_buzon_de_fotos_de_producto', false),
    (226, 'el_material_del_modelo_y_las_seis_etapas', false),
    (227, 'las_once_de_retail_entran_al_registro', false),
    (228, 'no_se_sanciona_con_un_reglamento_que_no_se_entrego', false),
    (229, 'la_lista_de_constancias_solo_cuenta_a_quien_obliga', false),
    (230, 'el_terminal_puede_preguntar_la_hora', false),
    (231, 'marcar_despues_del_contrato_deja_de_pasar_en_silencio', false),
    (232, 'la_escalera_de_tardanzas_recupera_su_cuarto_escalon', false),
    (233, 'la_educacion_se_paga_por_el_dia_en_que_empieza', false),
    (234, 'cada_quien_puede_saber_en_que_periodo_esta', false),
    (235, 'la_segunda_suspension_cae_en_dias_habiles_y_no_se_pasa_del_tope', false),
    (236, 'un_concepto_en_cero_se_escribe_no_se_borra', false),
    (237, 'la_mitad_de_la_0213_que_produccion_nunca_recibio', false),
    (238, 'un_dia_compensatorio_que_no_compensa_deja_de_entrar', false),
    (239, 'la_hora_vale_lo_que_vale_el_mes_no_lo_que_dura_la_consulta', false),
    (240, 'la_salida_pasada_la_medianoche_por_fin_se_puede_marcar', false),
    (241, 'el_terminal_ve_el_dia_entero_de_quien_puede_marcar', false),
    (242, 'un_locador_no_tiene_base_imponible', false),
    (243, 'la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago', false),
    (244, 'la_0243_deja_de_pagar_de_menos_y_de_atascar_el_cierre', false),
    (245, 'la_retencion_de_cuarta_deja_de_hacerse_a_mano', false),
    (246, 'una_imputacion_prematura_no_tapa_el_escalon_que_falta', false),
    (247, 'una_licencia_con_goce_se_puede_registrar', false),
    (248, 'la_foto_del_pago_aprende_la_retencion_de_cuarta', false),
    (249, 'una_salida_real_siempre_se_puede_registrar', false),
    (250, 'la_boleta_no_le_dice_por_horas_a_un_monto_fijo', false),
    (251, 'una_liquidacion_marcada_por_error_se_puede_anular', false),
    (252, 'el_cierre_deja_de_caerse_por_quien_no_cobra_movilidad', false),
    (253, 'anular_deja_de_perder_el_descuento_que_el_freno_obligo_a_poner', false),
    (254, 'el_descanso_medico_deja_de_pagarse_en_cero', false),
    (255, 'marcar_una_liquidacion_pagada_no_revienta_por_una_nota_corta', false),
    (256, 'una_persona_puede_ver_sus_propias_faltas', false),
    (257, 'una_persona_puede_pedir_que_se_revise_un_dia', false),
    (260, 'la_pantalla_de_costos_dice_cuanto_salio_del_banco', false),
    (261, 'el_regimen_de_pension_recuerda_desde_cuando', false),
    (262, 'la_licencia_por_maternidad_deja_de_pagarse_en_cero', false),
    (263, 'los_veinte_dias_de_descanso_medico_entran_a_la_base', false),
    (264, 'el_risst_si_pide_constancia', false),
    (265, 'el_contador_de_constancias_cuenta_a_la_misma_gente', false),
    (266, 'una_comunicacion_de_cargos_ya_ocurrida_se_puede_declarar', false),
    (267, 'el_descargo_previo_pasa_a_ser_una_politica_de_la_empresa', false),
    (269, 'el_descanso_medico_tambien_prorratea_el_feriado', false),
    (270, 'los_dias_de_seleccion_pagados_no_piden_el_reglamento', false),
    (271, 'el_total_de_cts_descuenta_lo_mismo_que_sus_ventanas', false),
    (272, 'los_contratos_generados_entran_al_sistema', false),
    (273, 'el_libro_de_desembolsos_vale_para_los_cinco_beneficios', false),
    (274, 'las_provisiones_solo_listan_a_quien_devenga', false),
    (275, 'las_vacaciones_dejan_de_pagarse_en_cero', false),
    (276, 'una_sola_base_para_la_reserva', false),
    (277, 'cambiar_el_regimen_de_pension_vuelve_a_mover_el_descuento', false),
    (278, 'ni_los_descuentos_ni_los_beneficios_inflan_la_liquidacion', false),
    (279, 'una_sede_sabe_en_que_ciudad_esta', false),
    (280, 'el_descanso_semanal_trabajado_se_paga', false),
    (281, 'el_techo_de_educacion_se_reparte_y_sigue_al_rango', false),
    (282, 'una_sede_central_no_tiene_ciudad_propia', false),
    (283, 'las_vacaciones_no_gozadas_se_pagan_al_cesar', false),
    (284, 'no_se_cierra_el_mes_con_una_hora_que_nadie_marco', false),
    (285, 'el_kiosco_ve_solo_lo_que_necesita_para_marcar', false),
    (286, 'un_dia_fichado_no_se_paga_tambien_como_ausencia', false),
    (287, 'el_contrato_firmado_se_registra_y_sus_plazos_se_miden', false),
    (288, 'la_puerta_de_borrar_marcajes_se_cierra', false),
    (289, 'la_gratificacion_ya_depositada_no_se_paga_dos_veces', false),
    (290, 'un_comprobante_por_mes_y_no_uno_por_asignacion', false),
    (291, 'el_kiosco_deja_de_poder_leer_toda_la_fila', false),
    (292, 'nueve_funciones_dejan_de_responderle_a_cualquiera', false),
    (293, 'el_feriado_dentro_de_un_descanso_medico_se_paga', false),
    (294, 'una_suspension_no_pasa_del_tope_del_reglamento', false),
    (295, 'el_rol_ya_no_se_asigna_solo', false),
    (296, 'el_rol_solo_cambia_por_una_puerta', false),
    (297, 'avisar_antes_de_que_venza_un_record_de_vacaciones', false),
    (298, 'un_turno_que_cambia_deja_rastro', false),
    (299, 'avisar_antes_de_que_venza_un_record_de_vacaciones', false),
    (300, 'crear_a_alguien_tambien_pasa_por_el_escalafon', false),
    (301, 'retirar_la_copia_duplicada_del_aviso_de_vacaciones', false),
    (302, 'la_ausencia_pagada_se_devenga_por_dias_laborables', false),
    (303, 'la_negativa_a_firmar_entrega_el_documento', false),
    (304, 'una_marca_apartada_deja_de_vivir_en_un_solo_navegador', false),
    (305, 'un_retroactivo_dice_de_que_mes_viene', false),
    (306, 'el_descanso_medico_y_la_maternidad_pagan_solo_aprobados', false),
    (307, 'el_candado_del_mes_pagado_mide_la_jornada', false),
    (308, 'la_reserva_tampoco_devenga_sin_la_firma_de_do', false),
    (309, 'dos_horarios_no_pueden_cubrir_el_mismo_dia', false),
    (310, 'el_feriado_dentro_de_un_descanso_medico_tampoco_se_reserva_en_cero', false),
    (311, 'el_mes_cerrado_se_puede_documentar_y_el_corte_se_suma', false),
    (312, 'un_contrato_anulado_no_deja_su_fecha_puesta', false),
    (313, 'un_mes_ya_pagado_se_lee_no_se_recalcula', false),
    (314, 'el_duelo_de_un_familiar_directo_se_paga_y_las_licencias_tambien', false),
    (315, 'anon_deja_de_depender_de_una_regla_por_defecto', false),
    (316, 'lo_que_se_paga_por_licencia_tambien_se_declara', false),
    (317, 'la_remuneracion_vacacional_tambien_se_declara', false),
    (318, 'reabrir_el_dia_no_toca_la_salida_de_anoche', false),
    (319, 'que_cambio_respecto_al_mes_pasado', false),
    (320, 'la_marca_real_gana_a_la_que_adivino_el_robot', false),
    (321, 'dias_por_revisar_distingue_periodo_pagado', false),
    (322, 'se_crea_la_categoria_practicante', false),
    (323, 'pagar_planilla_y_rxh_por_separado', false),
    (324, 'la_practicante_dice_su_modalidad', false),
    (325, 'un_convenio_de_practicas_tambien_termina', false),
    (326, 'un_marcaje_sin_revisar_tampoco_cierra_el_mes', false),
    (327, 'el_candado_de_horas_pasa_a_ser_por_grupo', false),
    (328, 'la_comision_mixta_deja_de_cobrarse_como_flujo', false),
    (329, 'el_estimado_de_planilla_se_consulta_por_persona', false),
    (330, 'una_persona_puede_pedir_sus_vacaciones', false),
    (331, 'las_diecinueve_pasan_a_comision_mixta', false),
    (332, 'cambiar_el_regimen_no_reescribe_un_mes_pagado', false),
    (333, 'el_generador_de_contratos_hace_convenios_de_practicas', false),
    (334, 'desempeno_suma_ausencias_del_periodo', false),
    (335, 'objetivos_texto_de_apoyo', false),
    (336, 'el_tablero_avisa_el_tope_de_12_meses_del_convenio', false),
    (338, 'grati_cts_usan_el_sueldo_vigente_al_cierre', false),
    (339, 'fn_planilla_calcular_se_parte_en_nucleo_y_envoltorio', false),
    (340, 'meses_y_dias_no_inventaba_dias_en_un_rango_corto', false),
    (341, 'las_vacaciones_truncas_pagan_su_aporte_a_pension', false),
    (342, 'la_sede_tambien_se_cambia_por_una_puerta', false),
    (343, 'un_adelanto_de_beneficio_no_se_vuelve_a_calcular_solo', false),
    (344, 'primera_carga_de_dni_no_pide_motivo', false),
    (345, 'el_comentario_del_techo_de_educacion_deja_de_mentir', false),
    (346, 'la_bonificacion_extraordinaria_sale_aparte_al_pagar_la_grati', false),
    (347, 'el_generador_de_contratos_hace_indefinidos', false),
    (348, 'objetivos_copiar_mes_anterior', false),
    (349, 'boleta_desglosa_sobretiempo_25_35', false),
    (350, 'objetivos_historial_mensual', false),
    (351, 'el_tablon_de_anuncios_de_do', false),
    (353, 'confirmacion_de_jornada_completa_al_marcar_salida', false),
    (354, 'alertas_encargada_por_correo', false),
    (355, 'agregar_de_un_clic_la_gratificacion_cts_y_bonificacion_pendientes', false),
    (356, 'la_cola_de_alertas_de_vencimiento_se_llena_sola', false),
    (357, 'el_saldo_de_vacaciones_separa_calculo_de_permiso', false),
    (358, 'el_aviso_de_alertas_aprende_dos_audiencias', false),
    (359, 'el_aviso_de_alertas_tambien_avisa_al_propio_integrante', false),
    (360, 'un_horario_retroactivo_recorta_el_tramo_que_pisa', false),
    (361, 'copiar_objetivos_no_duplica_con_doble_clic', false),
    (362, 'la_cola_de_alertas_se_reserva_reintenta_y_avisa', false),
    (363, 'fn_provisiones_recupera_su_grant', false),
    (364, 'el_pin_nace_en_el_servidor', false),
    (365, 'las_provisiones_avisan_cuando_falta_el_tramo_de_salario', false),
    (366, 'dos_toques_seguidos_no_dejan_dos_marcas', false),
    (367, 'fn_registrar_marcaje_pierde_su_sobrecarga_vieja', false),
    (368, 'un_codigo_de_sede_no_se_pisa_en_silencio', false),
    (369, 'la_ficha_guarda_el_genero', false),
    (370, 'el_terminal_no_marca_por_otra_sede', false),
    (371, 'el_aviso_de_vencimiento_no_se_salta_a_quien_llego_despues', false),
    (372, 'el_nueve_por_ciento_deja_de_darse_por_pagado_solo', false),
    (373, 'a_la_0353_le_faltaba_su_columna_en_produccion', false),
    (374, 'el_rol_deja_de_contar_si_la_persona_no_esta_activa', false),
    (375, 'el_terminal_deja_de_tener_pin', false),
    (376, 'una_persona_cesada_deja_de_colarse_por_el_or_suelto', false),
    (377, 'las_alertas_de_antes_del_despacho_quedan_anotadas', false),
    (378, 'apariencia_tema_global', false),
    (379, 'fn_set_meta_cobertura_vuelve_a_ser_null_safe', false),
    (380, 'fn_set_horario_semanal_gana_el_mismo_candado_que_objetivos', false),
    (381, 'cada_quien_sube_su_foto_y_aparece_en_el_terminal', false),
    (382, 'el_roster_vuelve_a_preguntar_la_regla_en_vez_de_copiarla', false),
    (384, 'la_lista_de_dias_por_revisar_dice_por_que', false),
    (385, 'quien_trabaja_sin_horario_vigente', false),
    (386, 'el_tablero_de_contratos_desempata_como_su_hermana', false),
    (387, 'el_tablero_de_documentos_desempata_la_ruta', false),
    (388, 'un_borrador_se_corrige_no_se_duplica', false),
    (390, 'el_motor_de_faltas_desempata_como_el_de_tardanzas', false),
    (391, 'las_cuatro_que_quedaban_del_mismo_empate', false),
    (392, 'los_guardianes_de_retail_dejan_de_colarse_por_el_or_suelto', false),
    (395, 'firma_con_tres_metodos', false),
    (396, 'las_faltas_dejan_de_contar_despues_del_fin_de_contrato', false),
    (397, 'la_practicante_cobra_movilidad_y_educacion', false),
    (398, 'firma_propia_en_el_contrato', false),
    (399, 'el_colaborador_propone_do_aprueba', false),
    (400, 'los_papeles_de_cese_entran_al_sistema', false),
    (401, 'cada_quien_sube_su_dni_y_do_lo_aprueba', false),
    (402, 'el_colaborador_confirma_su_firma_en_el_contrato', false),
    (403, 'la_encargada_de_sede_tambien_aprueba_el_perfil', false),
    (404, 'queda_constancia_de_que_acepto_el_tratamiento', false),
    (405, 'la_correccion_de_dni_se_queda_en_do', false),
    (406, 'confirmar_la_firma_dos_veces_no_borra_la_primera', false),
    (407, 'el_dni_se_puede_cancelar_y_queda_dicho', false),
    (408, 'el_sancionado_firma_su_propio_memo', false),
    (409, 'el_terminal_por_fin_puede_leer_horario_y_turno', false),
    (410, 'el_regimen_de_pension_tambien_se_cambia_por_una_puerta', false),
    (411, 'la_tasa_de_pension_de_respaldo_se_valida_al_escribir', false),
    (412, 'el_memo_firmado_se_cierra_sin_entrega_si_la_persona_cesa', false),
    (413, 'a_un_practicante_ya_se_le_mide_la_tardanza', false),
    (414, 'los_practicantes_cuentan_sus_faltas_reales', false),
    (415, 'el_cese_tambien_deja_rastro', false),
    (416, 'quien_cesa_sin_marcas_ya_no_desaparece_de_la_planilla', false),
    (417, 'el_sueldo_fijo_se_prorratea_al_entrar_o_cesar_a_mitad', false),
    (418, 'las_ausencias_dejan_de_pagarse_tras_el_cese_y_el_sobretiempo_no_pierde_el_ciclo_del_borde', false),
    (419, 'los_feriados_de_la_pantalla_usan_el_periodo_no_el_mes_calendario', false),
    (421, 'quien_se_liquida_deja_de_estorbar', false),
    (422, 'las_colas_de_correcciones_dejan_de_ver_a_quien_ya_se_liquido', false),
    (423, 'la_declaracion_de_ruta_ya_no_necesita_escaneo', false),
    (424, 'una_practicante_tambien_declara_su_ruta', false),
    (425, 'la_declaracion_de_ruta_queda_fija_al_firmarla', false),
    (426, 'la_declaracion_de_ruta_ya_no_pregunta_por_el_taxi', false),
    (427, 'pedir_revision_de_contrato', false),
    (428, 'practicantes_visibles_en_provisiones', false),
    (429, 'la_declaracion_de_ruta_guarda_sus_datos_por_separado', false),
    (430, 'el_contrato_se_firma_completo_de_forma_digital', false),
    (431, 'aprobar_una_ausencia_tambien_respeta_el_periodo_pagado', false),
    (432, 'el_cese_tambien_se_cambia_por_una_puerta', false),
    (433, 'cambiar_la_cuenta_bancaria_deja_rastro', false),
    (434, 'con_hijos_tambien_deja_rastro', false),
    (435, 'una_persona_le_escribe_a_su_encargada', false),
    (436, 'la_bandeja_recuerda_lo_que_ya_viste', false),
    (437, 'una_correccion_no_pisa_un_expediente_ya_formal', false),
    (438, 'levantar_una_tardanza_no_pisa_un_expediente_ya_formal', false),
    (439, 'copiar_semana_anterior_por_sede', false),
    (440, 'el_horario_tambien_se_cambia_por_una_puerta', false),
    (441, 'ausencia_avisa_dias_con_jornada', false),
    (442, 'anular_lo_aprobado_exige_desarrollo_organizacional', false),
    (443, 'ausentismo_separa_pagado_y_excluye_pendiente', false),
    (444, 'un_horario_normal_no_puede_pisar_el_pasado', false),
    (445, 'el_calculo_de_una_jornada_se_vuelve_reusable', false),
    (446, 'cada_jornada_guarda_el_horario_con_que_se_midio', false),
    (447, 'corregir_un_horario_pasado_es_un_camino_aparte', false),
    (448, 'la_negativa_pide_motivo_y_el_reemplazo_queda_auditado', false),
    (449, 'objetivos_recuerdan_quien_los_toco', false),
    (450, 'la_constancia_de_estudios_se_entrega_y_se_revisa', false),
    (451, 'un_visto_bueno_recuerda_lo_que_acepto', false),
    (452, 'eliminar_un_periodo_deja_rastro', false),
    (453, 'la_bandeja_vuelve_a_reconocer_educacion', false),
    (454, 'liquidaciones_fecha_de_pago_y_diferencia_por_cierre', false),
    (455, 'una_ausencia_registrada_despues_frena_la_firma_de_una_falta', false),
    (456, 'republicar_sin_cambios_no_crea_version', false),
    (457, 'editar_categoria_incluye_el_salario_declarado', false),
    (458, 'constancias_por_version_historica', false),
    (459, 'mi_rango_actual_para_el_portal', false),
    (460, 'restaurar_una_version_anterior', false),
    (461, 'el_colaborador_pide_su_apoyo_educativo', false),
    (462, 'quien_firma_digital_ya_tiene_su_copia', false),
    (463, 'quien_ingresa_despues_no_se_cuela_en_un_periodo_anterior', false),
    (464, 'la_planilla_deja_de_contar_a_quien_todavia_no_existia', false),
    (465, 'el_practicante_devenga_su_descanso_y_su_subvencion_semestral', false),
    (467, 'la_practicante_devenga_su_media_subvencion', false),
    (468, 'seis_filas_fantasma_salen_de_una_foto_ya_pagada', false),
    (470, 'el_mtpe_ya_no_es_tramite_para_nadie', false),
    (471, 'se_retira_la_implementacion_paralela_de_la_0465', false),
    (473, 'la_bandeja_mia_tambien_recuerda_lo_que_ya_viste', false),
    (474, 'la_bandeja_deja_de_pagar_por_un_calculo_que_no_usa', false),
    (475, 'liquidaciones_pendientes_deja_de_calcular_dos_veces', false),
    (476, 'el_cuspp_deja_de_frenar_el_cierre_de_planilla', false),
    (477, 'el_bono_de_cumpleanos_se_firma_desde_el_sistema', false),
    (478, 'el_bono_de_cumpleanos_se_pide_y_do_confirma_la_transferencia', false),
    (479, 'el_bono_de_cumpleanos_firmado_entra_a_la_boleta', false),
    (480, 'las_novedades_del_sistema_se_marcan_como_vistas', false),
    (481, 'la_tienda_de_lima_sabe_su_ciudad', false),
    (482, 'las_boletas_oficiales_se_suben_y_se_publican', false),
    (483, 'los_reportes_y_quien_puede_verlos', false),
    (484, 'el_periodo_de_prueba_deja_de_generar_essalud', false),
    (485, 'el_practicante_ve_su_descanso_y_subvencion_semestral', false),
    (486, 'el_memo_se_entrega_por_info', false),
    (487, 'la_imputacion_lleva_la_firma_escaneada', false),
    (488, 'los_reportes_se_escriben_y_sus_plazos_corren', false),
    (489, 'la_declaracion_de_ruta_vuelve_a_preguntar_pasaje_y_taxi', false),
    (490, 'una_cuenta_de_servicio_no_es_una_persona', false),
    (491, 'la_planilla_y_las_listas_dejan_fuera_a_las_cuentas_de_servicio', false),
    (492, 'la_declaracion_de_ruta_se_renueva', false),
    (493, 'estadisticas_de_casos_para_el_dashboard', false),
    (494, 'casos_resumen_filtra_por_medianoche_de_lima', false),
    (495, 'se_repone_el_filtro_de_cuentas_de_servicio', false),
    (496, 'un_periodo_con_todo_pagado_deja_de_leerse_como_a_medias', false),
    (499, 'liquidada_es_de_su_cese_actual', false),
    (501, 'la_rmv_sube_a_1230_y_la_escala_la_sigue', false),
    (502, 'la_subvencion_pactada_de_los_practicantes_sigue_a_la_rmv_de_1230', false),
    (503, 'el_archivo_de_la_empresa', false),
    (504, 'los_practicantes_pasan_de_essalud_a_seguro_privado', false),
    (505, 'el_feriado_posterior_al_cese_no_corresponde', false),
    (506, 'un_alta_que_se_parece_a_alguien_pide_confirmacion', false),
    (507, 'el_alta_de_una_persona_solo_entra_por_fn_crear_persona', false),
    (508, 'el_rastro_de_correcciones_solo_lo_escriben_las_funciones', false),
    (509, 'tres_tablas_que_solo_se_escriben_por_sus_funciones', false),
    (510, 'la_lider_registra_una_falta_de_conducta', false),
    (511, 'do_toma_el_caso_y_lo_devuelve', false),
    (512, 'el_dni_no_va_en_el_nombre', false),
    (513, 'el_alta_pide_el_documento', false),
    (514, 'las_faltas_se_eligen_por_nombre_corto', false),
    (515, 'do_se_entera_y_la_lider_tambien', false),
    (516, 'la_persona_deja_constancia_de_haber_leido', false),
    (517, 'la_persona_ve_como_va_con_sus_tardanzas', false),
    (518, 'a_quien_le_toca_el_bono_de_cumpleanos_se_dice_una_vez', false),
    (519, 'el_bono_de_cumpleanos_tambien_lo_recibe_el_practicante', false),
    (520, 'el_bono_de_cumpleanos_una_sola_regla_y_el_practicante_cobra_por_transferencia', false),
    (521, 'el_bono_del_practicante_vuelve_a_la_boleta', false),
    (522, 'la_solicitud_educativa_pendiente_recibe_su_comprobante', false),
    (524, 'un_estudio_de_educacion_no_tapa_a_otro', false),
    (525, 'una_aprobacion_de_constancia_se_puede_revertir', false),
    (527, 'pagar_antes_de_la_fecha_tambien_corre_el_calendario', false),
    (528, 'los_seguros_del_equipo_entran_al_sistema', false),
    (529, 'un_pago_adelantado_cubre_varios_meses_y_el_historial_de_educacion', false),
    (530, 'mi_seguro_cada_colaborador_ve_su_seguro_y_abre_sus_pdf', false),
    (531, 'la_politica_de_movilidad_se_firma_con_la_firma_del_sistema', false),
    (532, 'las_boletas_se_firman_y_una_anulacion_se_restablece', false),
    (533, 'la_constancia_de_la_boleta_trae_sus_datos', false),
    (534, 'la_asistencia_por_sede_y_semana', false),
    (535, 'el_cese_separa_quien_puede_pedirlo_de_como_se_hace', false),
    (536, 'la_prueba_de_tres_dias', false),
    (537, 'en_la_prueba_se_paga_lo_trabajado_y_quien_se_retira_no_cobra', false),
    (538, 'el_dni_de_quien_esta_de_prueba_lo_sube_quien_lo_registra', false),
    (539, 'el_terminal_sabe_quien_esta_de_prueba', false),
    (540, 'las_aceptaciones_de_terminos_por_modulo', false),
    (541, 'levantar_una_tardanza_deja_rastro_en_el_historial', false),
    (542, 'la_diferencia_de_una_liquidacion_pagada_se_cierra_con_constancia', false),
    (543, 'vida_ley_es_un_seguro_del_sistema', false),
    (544, 'una_cuenta_de_servicio_no_queda_en_planilla', false),
    (548, 'los_avisos_que_fallaron_para_siempre_tienen_salida', false),
    (549, 'un_pago_unico_ya_sustentado_no_pide_calendario', false),
    (550, 'una_alerta_solo_se_marca_leida', false),
    (551, 'los_practicantes_tambien_reciben_las_normas', false),
    (552, 'los_parametros_tienen_puerta_y_dejan_rastro', false),
    (553, 'el_periodo_de_prueba_es_una_condicion_del_contrato', false),
    (554, 'quien_figuraba_de_prueba_pasa_a_planilla', false),
    (555, 'quien_se_retiro_en_prueba_cobra_lo_que_trabajo', false),
    (556, 'el_periodo_de_prueba_se_pacta_por_persona', false),
    (557, 'la_etiqueta_de_prueba_tiene_fecha_de_corte', false),
    (558, 'quien_paso_a_planilla_sin_contrato_vuelve_a_preseleccion', false),
    (559, 'vuelven_los_dias_de_preseleccion_en_parametros', false),
    (560, 'el_aviso_de_un_mes_dice_preseleccion', false),
    (561, 'la_preseleccion_no_tiene_seguro_y_vuelve_quien_quedo_como_rxh', false),
    (562, 'cada_persona_se_marca_pagada_sin_tocar_el_cierre_del_grupo', false)
),
diff as (
  -- `falta` NO incluye las que nunca se van a aplicar: esas se explican aparte
  -- y no cuentan como pendientes.
  select r.numero, r.nombre, r.nunca,
         (a.numero is null and not r.nunca) as falta,
         (a.numero is null and r.nunca)     as nunca_ira,
         a.aplicada_at
  from repo r
  left join migraciones_aplicadas a on a.numero = r.numero
),
-- ⚠️ LA PREGUNTA AL REVÉS, que es la que de verdad duele.
--
-- Todo lo de arriba responde «¿qué le falta a producción?». Esta responde
-- «¿qué tiene producción que NO está guardado en ninguna parte?» — una
-- migración aplicada cuyo único ejemplar puede ser un archivo sin commitear en
-- una Mac. Si ese disco falla, el SQL desaparece y `db reset` deja de poder
-- reconstruir el esquema.
--
-- Pasó tres veces (0177, 0243, 0381) y ninguna la cazó una herramienta: la
-- lista de arriba salía del DISCO, así que el archivo sin commitear entraba en
-- ella y se marcaba «✓ aplicada». Ahora la lista viene de git, así que lo que
-- no esté commiteado en ningún lado aparece acá.
--
-- SE LLAMA «SOBRA LA FILA» PORQUE ASÍ LA LLAMA YA `huecos-conocidos.txt`, que
-- desde su primera versión manda buscar ese estado exacto antes de silenciar un
-- hueco. Prometía una comprobación que nadie había construido: hasta el
-- 2026-09-07 ese texto no existía en ninguna parte del script ni de la consulta.
--
-- QUÉ HACER CUANDO APARECE UNA, y son dos cosas distintas que conviene no
-- confundir — el detector encuentra la discrepancia, no decide qué significa:
--
--   a) La migración existe y no se guardó → COMMITEARLA HOY. Es el caso de la
--      0177, la 0243 y la 0381.
--   b) El número se anotó pero su contenido quedó SUPERADO por migraciones
--      posteriores que sí están guardadas → NO commitear el archivo viejo, que
--      podría crear una sobrecarga y repetir el «function is not unique» de la
--      0297/0299. Se anota el número en `huecos-conocidos.txt` con su razón.
--      Es el caso de la 0393, medido el 2026-09-08.
--
-- Para distinguirlas hay que mirar si lo que esa migración creaba sigue vigente
-- en producción con la misma firma. Cero filas es lo normal.
huerfanas as (
  select a.numero, a.nombre, a.aplicada_at
  from migraciones_aplicadas a
  where a.numero >= (select min(numero) from repo)
    and not exists (select 1 from repo r where r.numero = a.numero)
)
select * from (
  -- Una fila por migración.
  select d.numero::text                        as num,
         d.nombre                              as que,
         case when d.falta     then '❌  FALTA PEGAR'
              when d.nunca_ira then '—   no se pega (ver scripts/hooks/no-se-pegan.txt)'
              else                  '✓   aplicada' end as estado,
         to_char(d.aplicada_at, 'DD/MM/YYYY')  as cuando,
         d.numero                              as orden
  from diff d

  union all

  -- Las huérfanas, una fila cada una y ANTES del resumen. Si hay alguna, es lo
  -- único que importa de toda esta consulta.
  select a.numero::text,
         a.nombre,
         '⚠️  SOBRA LA FILA — revísala (ver abajo)',
         to_char(a.aplicada_at, 'DD/MM/YYYY'),
         999997
  from huerfanas a

  union all

  -- El resumen, al final y separado.
  select '——', '', '', '', 999998
  union all
  select 'RESUMEN',
         (select count(*) filter (where falta) from diff)::text || ' faltan · ' ||
         (select count(*) filter (where not falta and not nunca_ira) from diff)::text || ' aplicadas · ' ||
         (select count(*) filter (where nunca_ira) from diff)::text || ' que no se pegan · ' ||
         (select count(*) from diff)::text || ' en git' ||
         case when (select count(*) from huerfanas) > 0
              then ' · ⚠️ ' || (select count(*) from huerfanas)::text || ' PEGADAS Y NO GUARDADAS'
              else '' end,
         -- Una huérfana manda sobre todo lo demás: que falte pegar algo es
         -- atraso normal; que algo esté pegado y sin guardar es lo que costó
         -- tres sustos y no avisa solo.
         case when (select count(*) from huerfanas) > 0 then '⚠️  MIRA ARRIBA'
              when (select count(*) filter (where falta) from diff) = 0
              then '✓   al día' else '❌  hay pendientes' end,
         '', 999999

  union all

  -- Y la única pregunta que el registro no puede responder.
  select 'PLANILLA',
         'fn_planilla_calcular · versión viva',
         coalesce((
           select case md5(prosrc)
             when 'dacebb574315f3f7d880c9117cb3de7f' then '0397 — al día con el repositorio'
             when '03bbe3413099044329ddaab8a1dec8c8' then '✗ 0397 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '6ad7e6bb9d7a1678924c07c89a8e9df4' then '⚠ se quedó en la 0025 — falta pegar lo posterior'
             when '83c9996ff2c82490c8191edc5bd0a996' then '✗ 0025 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '5b263656b9ff462699eaca0db6e1a7b4' then '⚠ se quedó en la 0026 — falta pegar lo posterior'
             when '9d00f7c9959638019bcde843dd204ea1' then '⚠ se quedó en la 0027 — falta pegar lo posterior'
             when '0209595e1e31cabde71a58e2f20b0330' then '✗ 0027 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '4eaf8a2dc5118e7e29afaf3c03f777d1' then '⚠ se quedó en la 0047 — falta pegar lo posterior'
             when 'bb5b21e571788ea5d3ae93d5a8a64b47' then '✗ 0047 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'bee6d6c37d83eb6fb98f333208c928a1' then '⚠ se quedó en la 0069 — falta pegar lo posterior'
             when '9a6846f5db22f3362082606b4ff72f95' then '✗ 0069 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'b400b2ecad0a5b7fc9c8d47f553708be' then '⚠ se quedó en la 0090 — falta pegar lo posterior'
             when 'ef970d812bd2975041abd5b493c78647' then '✗ 0090 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'e827bfeff70fd273356f89a986ad65bf' then '⚠ se quedó en la 0100 — falta pegar lo posterior'
             when 'da62c44e2acedee52765cc02b5427c6f' then '✗ 0100 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'e9c9409fcfa3f3fc6b337638cfcd7741' then '⚠ se quedó en la 0105 — falta pegar lo posterior'
             when '3bd35a73d8b48489ad050afa57a77eee' then '✗ 0105 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '079e6d87c34feedca8af94b8f27d7e54' then '⚠ se quedó en la 0109 — falta pegar lo posterior'
             when 'e6424a3e85c7a4d732556f16129886f3' then '✗ 0109 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'f37bf8c0b814f81274d6e2beb9711a10' then '⚠ se quedó en la 0110 — falta pegar lo posterior'
             when 'de95ba2b717d73cda61869ca32a6db6a' then '✗ 0110 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'd5b08b9ba9e271f8b427caef1d200489' then '⚠ se quedó en la 0111 — falta pegar lo posterior'
             when 'd55718fc12fca2d3553a4fae3fd45f81' then '✗ 0111 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'bc6f93f13c3a1ef18608c4c26368e53f' then '⚠ se quedó en la 0112 — falta pegar lo posterior'
             when '64c6161dc260c312742f32333f080525' then '✗ 0112 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '8579625601fe7a926e70d396526d0fe4' then '⚠ se quedó en la 0113 — falta pegar lo posterior'
             when 'aefe702fe4edb7e26dcb81ddc4d1504d' then '✗ 0113 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'a13dc52b70ab5d4afdfb732479bfbc0c' then '⚠ se quedó en la 0114 — falta pegar lo posterior'
             when '6717483cf5668e1aa62bb527347420c1' then '✗ 0114 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '0ec3cde07e6b7fa2123665ac4e0855f2' then '⚠ se quedó en la 0116 — falta pegar lo posterior'
             when '21febade6043a4e98836203f7d96cea1' then '✗ 0116 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'a99e6681ad0f856f4ccd8cf58ccc91e4' then '⚠ se quedó en la 0117 — falta pegar lo posterior'
             when '19521d9d3133f4e67949af967fc397ba' then '✗ 0117 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '9e7dffb54bd3cef1c1c33bbe576c99a1' then '⚠ se quedó en la 0118 — falta pegar lo posterior'
             when '56cf23c540edff4f08bda84aff1a2bbd' then '✗ 0118 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'fc986792fd3d0d19adcceb378babe9de' then '⚠ se quedó en la 0120 — falta pegar lo posterior'
             when '2c9ad7bfe83a1eedc9f8b452159a771d' then '✗ 0120 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'aa3639dbb9b6a20e194b24bb963b4b65' then '⚠ se quedó en la 0122 — falta pegar lo posterior'
             when 'ee17fa9eda410ddde13b521c237f5b9e' then '✗ 0122 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '19924714a7482291388a10c1f922e4c3' then '⚠ se quedó en la 0134 — falta pegar lo posterior'
             when '64e01bbec2acf10a5025c4c24ac585b6' then '✗ 0134 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '7917eb444c76116c22c6782236c8fb2f' then '⚠ se quedó en la 0142 — falta pegar lo posterior'
             when 'ad1112d74bf3856af80e0fcdf5a44aeb' then '✗ 0142 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'aa3f471cf18636f4d6725831864bff64' then '⚠ se quedó en la 0150 — falta pegar lo posterior'
             when '45cae1ccee8b24f5e3e8f5512122c18b' then '✗ 0150 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '5dc12a1413d38c740e9ac220fe4d8d66' then '⚠ se quedó en la 0159 — falta pegar lo posterior'
             when 'd6b4931c563646fe949b512744ee8072' then '✗ 0159 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '30e0ecbf11ac5939457df6c2b3cccc77' then '⚠ se quedó en la 0166 — falta pegar lo posterior'
             when '96041d2475318146fb9bf60826045f94' then '✗ 0166 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '46c6c3de546f4da080d328a079470478' then '⚠ se quedó en la 0171 — falta pegar lo posterior'
             when 'b7bcaa87ca7179fb140481878f61065b' then '✗ 0171 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'cb3c5de14dd2b5a8872965814d5e7cd9' then '⚠ se quedó en la 0173 — falta pegar lo posterior'
             when '296c9870840f27defecf80071a8e3b75' then '✗ 0173 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '93e96e37e05799121485e5721de3dc06' then '⚠ se quedó en la 0177 — falta pegar lo posterior'
             when '17e05875aa7d862e6e9310b124e81f7e' then '✗ 0177 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '187cb5c3b5389f507fc77a18f8af846c' then '⚠ se quedó en la 0185 — falta pegar lo posterior'
             when '244e9cf3de7412d7603c036040669a1b' then '✗ 0185 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'f81bcf49a3a20337365b06f5a850d53e' then '⚠ se quedó en la 0186 — falta pegar lo posterior'
             when '1654991224bc19095b32468683c5a8e4' then '✗ 0186 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'ba9dfd2726ea59b86b43fc057c210ece' then '⚠ se quedó en la 0187 — falta pegar lo posterior'
             when '9ea5860ccb48d497209051de551e8ab3' then '✗ 0187 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '684634d24dd1a28ace4e99f1fd174ad6' then '⚠ se quedó en la 0192 — falta pegar lo posterior'
             when 'f588806871f74189de370355dfb22767' then '✗ 0192 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '449cc75cc4d097096fd87cdbd13b68f1' then '⚠ se quedó en la 0193 — falta pegar lo posterior'
             when 'c6c75c8a3f12c6aeaf1cb9ac19a7044a' then '✗ 0193 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '3ca25dd82de07418c9b9c77abffc8dec' then '⚠ se quedó en la 0199 — falta pegar lo posterior'
             when '2c368e0da180350dad2221012a0a4d57' then '✗ 0199 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'f61eca56c6d2017155c990a958ecd3a6' then '⚠ se quedó en la 0233 — falta pegar lo posterior'
             when 'f38d38f3b72f1a8aa85b8e9a79b20d28' then '✗ 0233 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '7d285ab4eb0cd8c1e5871b0eebaf78a2' then '⚠ se quedó en la 0236 — falta pegar lo posterior'
             when '6124769053b350ff9c877b983275080a' then '✗ 0236 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '7d67ff3c1d769ebffc3de0af20ab83fe' then '⚠ se quedó en la 0239 — falta pegar lo posterior'
             when '6a920445e3fb7ca0fc4a79bf17c89374' then '✗ 0239 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'b9765d1799dc71a9363c292b62daab5e' then '⚠ se quedó en la 0242 — falta pegar lo posterior'
             when '8080aed645e88f7bbfa88723eb147306' then '✗ 0242 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '3fee1553db2482aa2566d54d1b67438b' then '⚠ se quedó en la 0245 — falta pegar lo posterior'
             when '7ee382b01ac1b48e1f9cf9337afc335e' then '✗ 0245 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '7799d0a7ecabee450d2dd7609c50fab1' then '⚠ se quedó en la 0250 — falta pegar lo posterior'
             when '31ea2d1949da27167f767dc903aecd78' then '✗ 0250 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'e8b055e5ec144e20629bdc8b7bdbd0ea' then '⚠ se quedó en la 0252 — falta pegar lo posterior'
             when '7c038d3bbbe63aba6ae0b2a09aa4196a' then '✗ 0252 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '19eb593a757e0b7480b6a1dc99d7f8c9' then '⚠ se quedó en la 0254 — falta pegar lo posterior'
             when '76b07847407ae03f1d24bb15096179fc' then '✗ 0254 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '0d0f5fdd5f53d29fb316be50c794cec6' then '⚠ se quedó en la 0261 — falta pegar lo posterior'
             when '3b690e4e66251589066edfe85a009a0a' then '✗ 0261 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '261329fc2a8045ece063cfb0e5d38eca' then '⚠ se quedó en la 0262 — falta pegar lo posterior'
             when '172b8aa710b3b06f89a53c3cf7ae6ff8' then '✗ 0262 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'f6b4f2649f4132dd2db5711b391b1f54' then '⚠ se quedó en la 0263 — falta pegar lo posterior'
             when 'ea201e37d15fbd3ef34d0c5bf8d722fd' then '✗ 0263 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '5e755bdedd964d289104e824eb2925ec' then '⚠ se quedó en la 0269 — falta pegar lo posterior'
             when '4f24030bdce39bd665a13f503a2e7d7e' then '✗ 0269 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'b132c828fde4aa5fedd6cf946fee7f08' then '⚠ se quedó en la 0275 — falta pegar lo posterior'
             when '3af7cdc468be355687ad53a4af446222' then '✗ 0275 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '2f38e5ce76bcb22164cd0794671b349f' then '⚠ se quedó en la 0276 — falta pegar lo posterior'
             when '2792fa305cc21dec63339fc03af71f30' then '✗ 0276 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '0912fcb75893b146ea778163ae9d1ecd' then '⚠ se quedó en la 0280 — falta pegar lo posterior'
             when '2398570d2d547504320b423d9b21b12f' then '✗ 0280 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '00346e399226432bee73b1047488d178' then '⚠ se quedó en la 0286 — falta pegar lo posterior'
             when '1be99135441ef1d937aa0cbfd059ae95' then '✗ 0286 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'b1fa2aaaee9a6e4192ea3d616e3d8304' then '⚠ se quedó en la 0293 — falta pegar lo posterior'
             when '70e0f0270b72ea121eb5ba8edda348e6' then '✗ 0293 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '4688bf0101891f347f05cf96c0db9e68' then '⚠ se quedó en la 0306 — falta pegar lo posterior'
             when 'cce36e70ae3d5f58d2fb9d063a451b16' then '✗ 0306 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'c8070bb865e977d2d0e6b1bb4bac58d2' then '⚠ se quedó en la 0314 — falta pegar lo posterior'
             when 'c60b66ae4c1eca9515f4e3b79be82c4d' then '✗ 0314 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'f6ece4f8e21a8171b0d393ddf47cd1ce' then '⚠ se quedó en la 0316 — falta pegar lo posterior'
             when '151ceaa7d2745e13718dbd5e53ca472f' then '✗ 0316 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when '6838c789a2f2444166f2dbebfd9faa0d' then '⚠ se quedó en la 0317 — falta pegar lo posterior'
             when '00cd2aae9b8d01b943bb99c06eaa3727' then '✗ 0317 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'c86ef4707f51bf57024efac7eea41643' then '⚠ se quedó en la 0322 — falta pegar lo posterior'
             when '71b1779aa219c4ea7b01d9a062563552' then '✗ 0322 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'dacebb574315f3f7d880c9117cb3de7f' then '⚠ se quedó en la 0339 — falta pegar lo posterior'
             when '03bbe3413099044329ddaab8a1dec8c8' then '✗ 0339 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             when 'dacebb574315f3f7d880c9117cb3de7f' then '⚠ se quedó en la 0349 — falta pegar lo posterior'
             when '03bbe3413099044329ddaab8a1dec8c8' then '✗ 0349 CON LOS ACENTOS ROTOS — vuelve a pegarla'
             else '⚠ md5 SIN CATALOGAR: ' || md5(prosrc)
           end
           from pg_proc where proname = 'fn_planilla_calcular'
         ), '⚠ la función NO EXISTE'),
         '', 1000000

  union all

  -- El barrido, que no depende de ninguna lista escrita a mano y por eso vale
  -- más que la fila de arriba: cuenta CUALQUIER función cuyo cuerpo lleve el
  -- signo «√», que en castellano no aparece nunca dentro de un mensaje. Su
  -- presencia siempre significa lo mismo: el texto entró leído como Mac OS
  -- Roman y cada acento quedó partido en dos.
  --
  -- La lógica no cambia —solo se rompen los mensajes que lee una persona— pero
  -- es la señal de que algo en el camino de pegado corrompe el texto, y eso hay
  -- que saberlo el mismo día, no dentro de un mes.
  select 'ACENTOS',
         'funciones con el texto roto',
         coalesce((
           select case when count(*) = 0 then '✓   ninguna'
                       else '❌  ' || count(*)::text || ': ' || string_agg(proname, ' ' order by proname) end
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'fn\_%'
             and p.prosrc like '%' || chr(8730) || '%'
         ), '—'),
         '', 1000001
) t
order by orden;
