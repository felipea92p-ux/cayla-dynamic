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
--   · en qué versión está VIVA cada función que calcula, mueve o reporta plata
--     (la lista: scripts/hooks/funciones-de-plata.txt)
--
-- LO QUE EL REGISTRO NO PUEDE VER
--   Que una migración esté anotada NO prueba que su contenido siga vivo: una
--   pegada posterior pudo pisarlo sin dar ningún error. Pasó con
--   fn_costos_planilla: el 2026-11-09 era la de la 0099 aunque la 0260 y la 0323
--   figuraban aplicadas, y esta consulta no lo vio en cinco semanas porque solo
--   miraba el registro y fn_planilla_calcular. Por eso las filas PLANILLA y
--   PLATA miran el cuerpo real de cada función. «Al día» acepta las formas en
--   que una función llega a producción —tal cual, sin comentarios, desde
--   Windows—; «se quedó en la NNN» o «sin catalogar» es para mirar ese día.
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
    (519, 'el_bono_de_cumpleanos_tambien_lo_recibe_el_practicante', true),
    (520, 'el_bono_de_cumpleanos_una_sola_regla_y_el_practicante_cobra_por_transferencia', false),
    (521, 'el_bono_del_practicante_vuelve_a_la_boleta', false),
    (522, 'la_solicitud_educativa_pendiente_recibe_su_comprobante', false),
    (523, 'acortar_el_hasta_de_educacion_deja_de_fallar', false),
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
    (545, 'reabrir_un_grupo_pagado_repara_sus_horas', false),
    (546, 'revertir_un_pago_repara_las_horas_del_grupo', false),
    (547, 'correcciones_distingue_un_grupo_pagado_con_el_periodo_abierto', false),
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
    (562, 'cada_persona_se_marca_pagada_sin_tocar_el_cierre_del_grupo', false),
    (563, 'la_baja_tras_una_reactivacion_ni_se_bloquea_ni_pierde_su_ultimo_dia', false),
    (564, 'se_puede_acortar_la_asignacion_de_educacion_de_quien_ya_no_esta_activo', false),
    (565, 'la_liquidacion_lista_lo_que_se_debe_de_periodos_anteriores', false),
    (566, 'el_descargo_previo_se_enciende', false),
    (567, 'la_lider_propone_suspension_y_do_la_impone', false),
    (568, 'la_falta_grave_llega_hasta_el_despido', false),
    (569, 'la_entrega_arranca_el_plazo_y_avisa_del_notario', false),
    (570, 'las_seis_faltas_graves_tienen_nombre_corto', false),
    (571, 'cada_parametro_dice_quien_lo_cambia', false),
    (572, 'la_invitacion_a_la_cuenta_sale_sola_una_vez', false),
    (573, 'el_practicante_se_paga_sobre_una_base_de_30_horas', false),
    (574, 'los_parametros_de_plata_tienen_vigencia_y_vista_previa', false),
    (575, 'la_base_del_practicante_la_decide_su_modalidad', false),
    (576, 'el_practicante_se_paga_por_hora_con_tope_semanal', false),
    (577, 'la_base_y_el_tope_del_practicante_se_cambian_desde_parametros', false),
    (578, 'el_sueldo_se_cambia_por_grupo_y_avisa_a_quien_toca', false),
    (579, 'el_almacen_se_planifica_por_dia', false),
    (580, 'ir_al_almacen_se_marca_en_el_terminal', false),
    (581, 'los_cargos_llegan_a_su_info', false),
    (582, 'lo_comunicado_no_cambia_y_el_descargo_se_lee_antes', false),
    (583, 'el_almacen_es_solo_de_las_tiendas', false),
    (584, 'cada_quien_dice_cuando_puede_trabajar', false),
    (585, 'la_venta_de_cada_hora_llega_a_turnos', false),
    (586, 'la_semana_sugerida_se_publica_de_una_vez', false),
    (587, 'este_dia_no_me_calza', false),
    (588, 'el_almacen_puede_ser_el_puesto_de_siempre', false),
    (589, 'la_lider_registra_la_disponibilidad', false),
    (590, 'la_meta_de_cobertura_va_por_rangos_y_por_temporada', false),
    (591, 'prefiero_trabajar_en_la_disponibilidad', false),
    (592, 'cambiar_el_turno_con_una_companera', false),
    (593, 'el_borrador_de_la_semana', false),
    (594, 'quien_ingresa_despues_no_marca_ni_devenga_antes_de_su_fecha', false),
    (595, 'la_fecha_de_ingreso_por_defecto_es_la_de_lima', false),
    (597, 'quien_se_da_de_baja_ya_no_entra', false),
    (598, 'liquidaciones_lista_sin_el_calculo_de_diferencias', false),
    (602, 'a_cada_persona_le_llega_el_aviso_de_su_seguro', false),
    (603, 'renovar_un_seguro_avisa_por_correo_a_do', false),
    (604, 'las_pantallas_se_enteran_al_instante', false),
    (605, 'la_salida_real_gana_tambien_en_el_panel', false),
    (607, 'el_reglamento_vigente_dice_que_es_la_version_4_0', false),
    (608, 'fn_costos_planilla_vuelve_a_la_version_vigente', false),
    (610, 'el_contrato_de_locacion_de_quien_cobra_por_honorarios', false),
    (612, 'costos_que_se_pueden_comparar_entre_sedes', false),
    (614, 'el_costo_de_cada_periodo_dice_de_que_esta_hecho', false),
    (615, 'el_contrato_de_locacion_se_genera_y_se_firma_en_dynamic', false)
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
--      0297/0299. Se anota en `huecos-conocidos.txt` con su razón y la marca
--      `[sobra la fila: <nombre>]`: desde entonces sale acá como «ya
--      explicada» y deja de contar como alarma. Es el caso de la 0393, medido
--      el 2026-09-08.
--
-- Para distinguirlas hay que mirar si lo que esa migración creaba sigue vigente
-- en producción con la misma firma. Cero filas SIN EXPLICAR es lo normal.
explicadas(numero, nombre) as (values (393, 'cualquiera_guarda_su_propia_firma')),
huerfanas as (
  select a.numero, a.nombre, a.aplicada_at,
         exists (select 1 from explicadas e
                  where e.numero = a.numero and e.nombre = a.nombre) as explicada
  from migraciones_aplicadas a
  where a.numero >= (select min(numero) from repo)
    and not exists (select 1 from repo r where r.numero = a.numero)
),
-- Las funciones de plata, por su cuerpo y no por el registro.
plata(etiqueta, funcion, estado, orden) as (
  select 'PLANILLA', 'fn_planilla_calcular_nucleo', coalesce((
           select string_agg(case md5(p.prosrc)
             when '7556c6de573137549c33692d6412e9f3' then '✓   al día (0577)'
             when '87343eb4edd67a9f6fd3ff423f956a22' then '✓   al día (0577, pegada sin comentarios)'
             when 'e90e3b5f4ca58e25de8eec0fd75b5934' then '✓   al día (0577, pegada desde Windows)'
             when 'fd4a16b11dd78e21d985ce3c1ebb96e8' then '✓   al día (0577, desde Windows y sin comentarios)'
             when '98845271658e0ea652fe53cc27e8bbea' then '✗   0577 con los acentos rotos — vuelve a pegarla'
             when '7f9a8a8ef951567eca1dbfd7c8d33f76' then '❌  se quedó en la 0576 — la vigente es la 0577'
             when '5f45bdb17a521dd06a851636803c6057' then '❌  se quedó en la 0576 — la vigente es la 0577'
             when '40748ba949e32789c06c48c8eac9fca8' then '❌  se quedó en la 0575 — la vigente es la 0577'
             when '14cdc80e1fbe702ab5eb31500f50d29c' then '❌  se quedó en la 0575 — la vigente es la 0577'
             when '8480448f341d0d6d424c4b31816878b2' then '❌  se quedó en la 0573 — la vigente es la 0577'
             when '8403aeb1f157d7ad1c92eefd8151da9c' then '❌  se quedó en la 0573 — la vigente es la 0577'
             when 'aad8a0f00628539f27a4d789a4c1ac04' then '❌  se quedó en la 0555 — la vigente es la 0577'
             when '2f73c7e931f7e0e42235d1104bc05dbe' then '❌  se quedó en la 0555 — la vigente es la 0577'
             when '4e25d9fd99e5e6a4e8f82952207c0652' then '❌  se quedó en la 0537 — la vigente es la 0577'
             when '195886a1d1967107791d8f9aff72e8ae' then '❌  se quedó en la 0537 — la vigente es la 0577'
             when '11425cadd0e0d2289283ac17d9cafec8' then '❌  se quedó en la 0524 — la vigente es la 0577'
             when '62c6e4f550ccbb005bb850a0092395ce' then '❌  se quedó en la 0524 — la vigente es la 0577'
             when 'f1781d68a87190ee75937eafc3f6facc' then '❌  se quedó en la 0504 — la vigente es la 0577'
             when 'ca3e922e46d5cc7adbab6ac81e595aaf' then '❌  se quedó en la 0504 — la vigente es la 0577'
             when '27dda4084d0efbad293c36d66a39adf7' then '❌  se quedó en la 0495 — la vigente es la 0577'
             when '27b82dcac5bef3f003553963abb6f1dd' then '❌  se quedó en la 0495 — la vigente es la 0577'
             when 'dd3eaed7707d997cb21963dc3549abc9' then '❌  se quedó en la 0491 — la vigente es la 0577'
             when '706301b8092d191a533ac54d143d2058' then '❌  se quedó en la 0484 — la vigente es la 0577'
             when 'bc267bf46a383186f5505973d78a58f6' then '❌  se quedó en la 0484 — la vigente es la 0577'
             when '4f5a98023616903a3765d68d4a566d9f' then '❌  se quedó en la 0463 — la vigente es la 0577'
             when 'cef78dd6dbd44dc2a57ade5a0dd24a0c' then '❌  se quedó en la 0463 — la vigente es la 0577'
             when 'afeaf7a77ca9ded8e67549b7413bc4ec' then '❌  se quedó en la 0418 — la vigente es la 0577'
             when 'dc97129b0c2bf83f418748dafbbde80e' then '❌  se quedó en la 0418 — la vigente es la 0577'
             when 'fd51c1ff32561d7806b5515447e8c0fb' then '❌  se quedó en la 0417 — la vigente es la 0577'
             when '202aae000ff52da8ea09c1847e9f9149' then '❌  se quedó en la 0417 — la vigente es la 0577'
             when 'ebb017c5cd1b0a856796edf4c1596ea9' then '❌  se quedó en la 0416 — la vigente es la 0577'
             when '1bfc928a8d75d79bdf4fd322bfa3dfe8' then '❌  se quedó en la 0416 — la vigente es la 0577'
             when 'aad24b5a1958563c425789e29f39fb29' then '❌  se quedó en la 0397 — la vigente es la 0577'
             when '368773a7f7ace1887d888219e0ef81f7' then '❌  se quedó en la 0397 — la vigente es la 0577'
             when '59229a838dd72c5285f6c4ff0be360b3' then '❌  se quedó en la 0349 — la vigente es la 0577'
             when '4f0c3467fdd5f9c511a1ecdc74a7335a' then '❌  se quedó en la 0349 — la vigente es la 0577'
             when '8fc2d28343d2ed6a18fe57246442e347' then '❌  se quedó en la 0339 — la vigente es la 0577'
             when 'f6f0684cbb70c4ccee7790a3a87e2be7' then '❌  se quedó en la 0339 — la vigente es la 0577'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_planilla_calcular_nucleo'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_planilla_calcular_nucleo'
         ), '⚠   la función NO EXISTE'), 1000001
  union all
  select 'PLANILLA', 'fn_planilla_calcular', coalesce((
           select string_agg(case md5(p.prosrc)
             when 'dacebb574315f3f7d880c9117cb3de7f' then '✓   al día (0397)'
             when '89a7d47f4fe8b368246eb7dd94f0a872' then '✓   al día (0397, pegada sin comentarios)'
             when 'cde403dc1e007a8b8a514a1caaf19ff4' then '✓   al día (0397, pegada desde Windows)'
             when 'd8e7978da1df4807579ea490b0dcb4a7' then '✓   al día (0397, desde Windows y sin comentarios)'
             when '03bbe3413099044329ddaab8a1dec8c8' then '✗   0397 con los acentos rotos — vuelve a pegarla'
             when 'c86ef4707f51bf57024efac7eea41643' then '❌  se quedó en la 0322 — la vigente es la 0397'
             when '812128114da1a72e22a20fe3ddea299b' then '❌  se quedó en la 0322 — la vigente es la 0397'
             when '6838c789a2f2444166f2dbebfd9faa0d' then '❌  se quedó en la 0317 — la vigente es la 0397'
             when '768cb9bc902c135edda8e603617a6fde' then '❌  se quedó en la 0317 — la vigente es la 0397'
             when 'f6ece4f8e21a8171b0d393ddf47cd1ce' then '❌  se quedó en la 0316 — la vigente es la 0397'
             when 'd4e883954165c44def38509c7bfb3304' then '❌  se quedó en la 0316 — la vigente es la 0397'
             when 'c8070bb865e977d2d0e6b1bb4bac58d2' then '❌  se quedó en la 0314 — la vigente es la 0397'
             when '006a830a8a8ddc67118c2d27de14ad90' then '❌  se quedó en la 0314 — la vigente es la 0397'
             when '4688bf0101891f347f05cf96c0db9e68' then '❌  se quedó en la 0306 — la vigente es la 0397'
             when '5585aa09f32b3d72534514477e7e43e6' then '❌  se quedó en la 0306 — la vigente es la 0397'
             when 'b1fa2aaaee9a6e4192ea3d616e3d8304' then '❌  se quedó en la 0293 — la vigente es la 0397'
             when '92a1c1a787e6f4da2b08277697cbb22d' then '❌  se quedó en la 0293 — la vigente es la 0397'
             when '00346e399226432bee73b1047488d178' then '❌  se quedó en la 0286 — la vigente es la 0397'
             when '41438e8d9f587c8651d2a02269595a6c' then '❌  se quedó en la 0286 — la vigente es la 0397'
             when '0912fcb75893b146ea778163ae9d1ecd' then '❌  se quedó en la 0280 — la vigente es la 0397'
             when '75d0ad65d2bbe81f01dfbd92fafeadf1' then '❌  se quedó en la 0280 — la vigente es la 0397'
             when '2f38e5ce76bcb22164cd0794671b349f' then '❌  se quedó en la 0276 — la vigente es la 0397'
             when 'b2c4baeeaf06640981b6fad5a784fe01' then '❌  se quedó en la 0276 — la vigente es la 0397'
             when 'b132c828fde4aa5fedd6cf946fee7f08' then '❌  se quedó en la 0275 — la vigente es la 0397'
             when 'bfc5280e79ffb94708d75cc4820ab826' then '❌  se quedó en la 0275 — la vigente es la 0397'
             when '5e755bdedd964d289104e824eb2925ec' then '❌  se quedó en la 0269 — la vigente es la 0397'
             when 'a4e36a11674285f04533c65d4dc56528' then '❌  se quedó en la 0269 — la vigente es la 0397'
             when 'f6b4f2649f4132dd2db5711b391b1f54' then '❌  se quedó en la 0263 — la vigente es la 0397'
             when '0576ce83061538cc9ff2a538358a5c7b' then '❌  se quedó en la 0263 — la vigente es la 0397'
             when '261329fc2a8045ece063cfb0e5d38eca' then '❌  se quedó en la 0262 — la vigente es la 0397'
             when '936c329acf7d586c7437d2bf7924ca5b' then '❌  se quedó en la 0262 — la vigente es la 0397'
             when '0d0f5fdd5f53d29fb316be50c794cec6' then '❌  se quedó en la 0261 — la vigente es la 0397'
             when '5cf6bf4909df4a9193d9561563ce4d8c' then '❌  se quedó en la 0261 — la vigente es la 0397'
             when '19eb593a757e0b7480b6a1dc99d7f8c9' then '❌  se quedó en la 0254 — la vigente es la 0397'
             when 'f012ce5a39bc000d509dbd2e0a32d44b' then '❌  se quedó en la 0254 — la vigente es la 0397'
             when 'e8b055e5ec144e20629bdc8b7bdbd0ea' then '❌  se quedó en la 0252 — la vigente es la 0397'
             when '9320ff68835957cf809c2002d1722833' then '❌  se quedó en la 0252 — la vigente es la 0397'
             when '7799d0a7ecabee450d2dd7609c50fab1' then '❌  se quedó en la 0250 — la vigente es la 0397'
             when '764c09721c74bbdddb78255607d3359d' then '❌  se quedó en la 0250 — la vigente es la 0397'
             when '3fee1553db2482aa2566d54d1b67438b' then '❌  se quedó en la 0245 — la vigente es la 0397'
             when 'b4802d9a407ced6acb8b1756b14c9d96' then '❌  se quedó en la 0245 — la vigente es la 0397'
             when 'b9765d1799dc71a9363c292b62daab5e' then '❌  se quedó en la 0242 — la vigente es la 0397'
             when '7a6a8a9d71b129bba7c9488d1b7c4957' then '❌  se quedó en la 0242 — la vigente es la 0397'
             when '7d67ff3c1d769ebffc3de0af20ab83fe' then '❌  se quedó en la 0239 — la vigente es la 0397'
             when 'fe2ed410d335828dec86aa3250947013' then '❌  se quedó en la 0239 — la vigente es la 0397'
             when '7d285ab4eb0cd8c1e5871b0eebaf78a2' then '❌  se quedó en la 0236 — la vigente es la 0397'
             when 'a6dea37009e588beedd7c45e850c668d' then '❌  se quedó en la 0236 — la vigente es la 0397'
             when 'f61eca56c6d2017155c990a958ecd3a6' then '❌  se quedó en la 0233 — la vigente es la 0397'
             when 'fb4a049d973f3180696ddd58096a99bc' then '❌  se quedó en la 0233 — la vigente es la 0397'
             when '3ca25dd82de07418c9b9c77abffc8dec' then '❌  se quedó en la 0199 — la vigente es la 0397'
             when 'af15b1d8e0ac6387c8b81bd63d7da1d1' then '❌  se quedó en la 0199 — la vigente es la 0397'
             when '449cc75cc4d097096fd87cdbd13b68f1' then '❌  se quedó en la 0193 — la vigente es la 0397'
             when 'c970dd69e7f7b10663c30cf35b51e11f' then '❌  se quedó en la 0193 — la vigente es la 0397'
             when '684634d24dd1a28ace4e99f1fd174ad6' then '❌  se quedó en la 0192 — la vigente es la 0397'
             when '7126feda5469f9fbddb9d9f485b7f98a' then '❌  se quedó en la 0192 — la vigente es la 0397'
             when 'ba9dfd2726ea59b86b43fc057c210ece' then '❌  se quedó en la 0187 — la vigente es la 0397'
             when '30181216bedbf719311300e3f26cf2cb' then '❌  se quedó en la 0187 — la vigente es la 0397'
             when 'f81bcf49a3a20337365b06f5a850d53e' then '❌  se quedó en la 0186 — la vigente es la 0397'
             when '9c3db3b34fd96e972c1ac734319d940f' then '❌  se quedó en la 0186 — la vigente es la 0397'
             when '187cb5c3b5389f507fc77a18f8af846c' then '❌  se quedó en la 0185 — la vigente es la 0397'
             when '064052093582dab81ba79960dea31fd6' then '❌  se quedó en la 0185 — la vigente es la 0397'
             when '93e96e37e05799121485e5721de3dc06' then '❌  se quedó en la 0177 — la vigente es la 0397'
             when 'ba54d2460495b01d02e502b0f7157637' then '❌  se quedó en la 0177 — la vigente es la 0397'
             when 'cb3c5de14dd2b5a8872965814d5e7cd9' then '❌  se quedó en la 0173 — la vigente es la 0397'
             when 'aca343e04e465cad2cf748ee93155190' then '❌  se quedó en la 0173 — la vigente es la 0397'
             when '46c6c3de546f4da080d328a079470478' then '❌  se quedó en la 0171 — la vigente es la 0397'
             when 'e40cb70a5f0cedc0accbac8ebcd60358' then '❌  se quedó en la 0171 — la vigente es la 0397'
             when '30e0ecbf11ac5939457df6c2b3cccc77' then '❌  se quedó en la 0166 — la vigente es la 0397'
             when 'af4992f6b933bcc84ef0a36f31f9d96e' then '❌  se quedó en la 0166 — la vigente es la 0397'
             when '5dc12a1413d38c740e9ac220fe4d8d66' then '❌  se quedó en la 0159 — la vigente es la 0397'
             when 'b49adbd3fdff4af3d656f21a94656a8e' then '❌  se quedó en la 0159 — la vigente es la 0397'
             when 'aa3f471cf18636f4d6725831864bff64' then '❌  se quedó en la 0150 — la vigente es la 0397'
             when '807a2a8d8731697bd7429e44787b6f60' then '❌  se quedó en la 0150 — la vigente es la 0397'
             when '7917eb444c76116c22c6782236c8fb2f' then '❌  se quedó en la 0142 — la vigente es la 0397'
             when '6a1a69954e96a561699d33ba73702131' then '❌  se quedó en la 0142 — la vigente es la 0397'
             when '19924714a7482291388a10c1f922e4c3' then '❌  se quedó en la 0134 — la vigente es la 0397'
             when '44238d7db8c192d42733fd76930f5d68' then '❌  se quedó en la 0134 — la vigente es la 0397'
             when 'aa3639dbb9b6a20e194b24bb963b4b65' then '❌  se quedó en la 0122 — la vigente es la 0397'
             when '47ad746dc86add2915ec906c4e1712a1' then '❌  se quedó en la 0122 — la vigente es la 0397'
             when 'fc986792fd3d0d19adcceb378babe9de' then '❌  se quedó en la 0120 — la vigente es la 0397'
             when '3fb83c5c622b5f06db9fb68ead36b97c' then '❌  se quedó en la 0120 — la vigente es la 0397'
             when '9e7dffb54bd3cef1c1c33bbe576c99a1' then '❌  se quedó en la 0118 — la vigente es la 0397'
             when 'ec35956f618148c9561d839b823de0d7' then '❌  se quedó en la 0118 — la vigente es la 0397'
             when 'a99e6681ad0f856f4ccd8cf58ccc91e4' then '❌  se quedó en la 0117 — la vigente es la 0397'
             when '871a03d32f971c98672ff8d6984469f2' then '❌  se quedó en la 0117 — la vigente es la 0397'
             when '0ec3cde07e6b7fa2123665ac4e0855f2' then '❌  se quedó en la 0116 — la vigente es la 0397'
             when '71dbbcec2c9ecbc7074ead8607808f1b' then '❌  se quedó en la 0116 — la vigente es la 0397'
             when 'a13dc52b70ab5d4afdfb732479bfbc0c' then '❌  se quedó en la 0114 — la vigente es la 0397'
             when 'b437779355b983c27d516e1857e1e89f' then '❌  se quedó en la 0114 — la vigente es la 0397'
             when '8579625601fe7a926e70d396526d0fe4' then '❌  se quedó en la 0113 — la vigente es la 0397'
             when '9abb2b1dfdb11e2d0bad59a9a3f2fdf5' then '❌  se quedó en la 0113 — la vigente es la 0397'
             when 'bc6f93f13c3a1ef18608c4c26368e53f' then '❌  se quedó en la 0112 — la vigente es la 0397'
             when '9405cb840a397199bb7e1fb8395a1384' then '❌  se quedó en la 0112 — la vigente es la 0397'
             when 'd5b08b9ba9e271f8b427caef1d200489' then '❌  se quedó en la 0111 — la vigente es la 0397'
             when '3421b00781129ac0989578ee858f2d6c' then '❌  se quedó en la 0111 — la vigente es la 0397'
             when 'f37bf8c0b814f81274d6e2beb9711a10' then '❌  se quedó en la 0110 — la vigente es la 0397'
             when 'a28d6bbc0e6a7c0d14fc2144449c8c4c' then '❌  se quedó en la 0110 — la vigente es la 0397'
             when '079e6d87c34feedca8af94b8f27d7e54' then '❌  se quedó en la 0109 — la vigente es la 0397'
             when '97a73bab6f0116b5e6a054ab4c66ded7' then '❌  se quedó en la 0109 — la vigente es la 0397'
             when 'e9c9409fcfa3f3fc6b337638cfcd7741' then '❌  se quedó en la 0105 — la vigente es la 0397'
             when '586bd01d3528bcf86fee0c56bd157654' then '❌  se quedó en la 0105 — la vigente es la 0397'
             when 'e827bfeff70fd273356f89a986ad65bf' then '❌  se quedó en la 0100 — la vigente es la 0397'
             when '549917eff84590dbc6d0fe87b3ce616a' then '❌  se quedó en la 0100 — la vigente es la 0397'
             when 'b400b2ecad0a5b7fc9c8d47f553708be' then '❌  se quedó en la 0090 — la vigente es la 0397'
             when '6e7de5d2b038d8df55a4433f8a33d2e2' then '❌  se quedó en la 0090 — la vigente es la 0397'
             when 'bee6d6c37d83eb6fb98f333208c928a1' then '❌  se quedó en la 0069 — la vigente es la 0397'
             when 'cf298d4e28fbc40e833d486b8e7409cb' then '❌  se quedó en la 0069 — la vigente es la 0397'
             when '4eaf8a2dc5118e7e29afaf3c03f777d1' then '❌  se quedó en la 0047 — la vigente es la 0397'
             when '763842a5b32ff86b2d90c2b1314bd25d' then '❌  se quedó en la 0047 — la vigente es la 0397'
             when '9d00f7c9959638019bcde843dd204ea1' then '❌  se quedó en la 0027 — la vigente es la 0397'
             when '55530d5655ecc83559b5e36b1bea10c4' then '❌  se quedó en la 0027 — la vigente es la 0397'
             when '5b263656b9ff462699eaca0db6e1a7b4' then '❌  se quedó en la 0026 — la vigente es la 0397'
             when '6ad7e6bb9d7a1678924c07c89a8e9df4' then '❌  se quedó en la 0025 — la vigente es la 0397'
             when '7b9fa00b76194ae23a8194e0d61fe253' then '❌  se quedó en la 0025 — la vigente es la 0397'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_planilla_calcular'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'
         ), '⚠   la función NO EXISTE'), 1000002
  union all
  select 'PLANILLA', 'fn_planilla_calcular_persona', coalesce((
           select string_agg(case md5(p.prosrc)
             when '4f0713a6c817e18e3fad6755ab4e7139' then '✓   al día (0397)'
             when '6467f3a9911e952c4b1c97848842a7f4' then '✓   al día (0397, pegada sin comentarios)'
             when 'e6fcb43b1a96a33f6b830c7f5c6be64d' then '✓   al día (0397, pegada desde Windows)'
             when 'bc1ec48079442a1947658e65a2c73970' then '✓   al día (0397, desde Windows y sin comentarios)'
             when '77dffbf75fd0521e6677955c4dfa61d6' then '✗   0397 con los acentos rotos — vuelve a pegarla'
             when '018c7819fc09ad99a26ffce4177f87b3' then '❌  se quedó en la 0329 — la vigente es la 0397'
             when '9a71f6edef21ca4a9fd4b2c80f006bba' then '❌  se quedó en la 0329 — la vigente es la 0397'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_planilla_calcular_persona'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_planilla_calcular_persona'
         ), '⚠   la función NO EXISTE'), 1000003
  union all
  select 'PLATA', 'fn_provisiones', coalesce((
           select string_agg(case md5(p.prosrc)
             when 'e36c150c5db587354d48d6b0916273bb' then '✓   al día (0491)'
             when '62a7146b113b6a061710b79bf9d038ef' then '✓   al día (0491, pegada sin comentarios)'
             when '32a92a7ffbb39b369abec2edba7cec0c' then '✓   al día (0491, pegada desde Windows)'
             when 'f6c0482d1118c832ddbedea5180f1343' then '✓   al día (0491, desde Windows y sin comentarios)'
             when '40fe8af23d63716036e99b09980e04ac' then '✗   0491 con los acentos rotos — vuelve a pegarla'
             when '51b69875b258b8c7d6812a8d64019f7b' then '❌  se quedó en la 0471 — la vigente es la 0491'
             when 'a89483d1f63933d7064550b9ccb441e9' then '❌  se quedó en la 0471 — la vigente es la 0491'
             when '08026578b3f7f97109d8c3dc53812fb7' then '❌  se quedó en la 0465 — la vigente es la 0491'
             when 'edc4eb855bc2734856b5706bda8149fe' then '❌  se quedó en la 0465 — la vigente es la 0491'
             when '6f33984ae7ce841d9dcbb7935324be6b' then '❌  se quedó en la 0372 — la vigente es la 0491'
             when '3585861dff4fb0804307cb5b8473302b' then '❌  se quedó en la 0372 — la vigente es la 0491'
             when '4b7b7bd996651f5e5a4d1a978cc3edb9' then '❌  se quedó en la 0365 — la vigente es la 0491'
             when '148ff0e066e187389605aefe056ae595' then '❌  se quedó en la 0365 — la vigente es la 0491'
             when '62795c4ec4f7c197dea4c2fefa82787f' then '❌  se quedó en la 0338 — la vigente es la 0491'
             when '67e5f56b1aa65a99cd839d2a360c91db' then '❌  se quedó en la 0338 — la vigente es la 0491'
             when 'b40ded0faad67ac72625369d22699562' then '❌  se quedó en la 0310 — la vigente es la 0491'
             when 'ab00d5f9dfd48ffc89e1e4f66a00e332' then '❌  se quedó en la 0310 — la vigente es la 0491'
             when 'adb0a986b32d26920fb9488a314b4d45' then '❌  se quedó en la 0308 — la vigente es la 0491'
             when '1f6439d0a445f5e82456b658df8c5ac8' then '❌  se quedó en la 0308 — la vigente es la 0491'
             when '866c0a1664afde204ae6d685760afb84' then '❌  se quedó en la 0302 — la vigente es la 0491'
             when '083aa93b57db9d3c42132e6b83d972c5' then '❌  se quedó en la 0302 — la vigente es la 0491'
             when '93531851f35abcdd295fd8fb4aa77922' then '❌  se quedó en la 0276 — la vigente es la 0491'
             when 'c3a8f243ce9fedab8b33fd2cff6760bc' then '❌  se quedó en la 0276 — la vigente es la 0491'
             when '84aae8bf6905f372d08a49b2056c3c3b' then '❌  se quedó en la 0274 — la vigente es la 0491'
             when 'ee7116bba5671fc383355019b7574573' then '❌  se quedó en la 0274 — la vigente es la 0491'
             when 'e057765cfa852239b9683267cf9244f4' then '❌  se quedó en la 0273 — la vigente es la 0491'
             when '4a3e38f89d6245e9c430560b58c3088e' then '❌  se quedó en la 0273 — la vigente es la 0491'
             when '86d01fa3ab543865f7245912377d92d9' then '❌  se quedó en la 0271 — la vigente es la 0491'
             when 'f42b026f691dabe4b92f896352dd51da' then '❌  se quedó en la 0271 — la vigente es la 0491'
             when 'fad142f69ea100b55a15a98b631f9e9c' then '❌  se quedó en la 0196 — la vigente es la 0491'
             when '42c548a9a3d6092883458188d490b167' then '❌  se quedó en la 0196 — la vigente es la 0491'
             when 'c09677917ebfd34aa9d67d342e0a0160' then '❌  se quedó en la 0160 — la vigente es la 0491'
             when 'b7fdb518019230e303b4c72cf55c856e' then '❌  se quedó en la 0160 — la vigente es la 0491'
             when '9b6be5fae9b82d5d1da3d7b8d1f82252' then '❌  se quedó en la 0158 — la vigente es la 0491'
             when '677aa5d5a27ef4a2b6089c4bd9e44ce5' then '❌  se quedó en la 0158 — la vigente es la 0491'
             when 'd07fe93b516328b0fc1d6986f6082c3c' then '❌  se quedó en la 0135 — la vigente es la 0491'
             when 'fe812de20f0c622b40fe04db0155bea3' then '❌  se quedó en la 0135 — la vigente es la 0491'
             when '5b6f7db22fcb2ba85008b3845f5ffa11' then '❌  se quedó en la 0134 — la vigente es la 0491'
             when '8efbc565485d278025955fc04c1300a4' then '❌  se quedó en la 0134 — la vigente es la 0491'
             when '77eec07c1e79a72a86c234d8827ec27d' then '❌  se quedó en la 0123 — la vigente es la 0491'
             when '2db29423c81aa7e1df55cab49633c8e0' then '❌  se quedó en la 0123 — la vigente es la 0491'
             when 'b550de5faa91c77c817760b71a3885f8' then '❌  se quedó en la 0122 — la vigente es la 0491'
             when '067471428ff5b6e1c3dce8d2dbc97ad1' then '❌  se quedó en la 0122 — la vigente es la 0491'
             when '1563fbf37d5f4e369f4571552b3097ca' then '❌  se quedó en la 0113 — la vigente es la 0491'
             when '752c81495f49a8df7b84370390096bb9' then '❌  se quedó en la 0113 — la vigente es la 0491'
             when 'ada683a910790ad3b9db24f804f2ca32' then '❌  se quedó en la 0112 — la vigente es la 0491'
             when '7151b05b4792598bc4f0385c1595d20a' then '❌  se quedó en la 0112 — la vigente es la 0491'
             when 'd7a580e4d6a7f3bfce9ba4ea7419b901' then '❌  se quedó en la 0091 — la vigente es la 0491'
             when '79ab5bf2a3081df56b5a7f4348f1ccaa' then '❌  se quedó en la 0091 — la vigente es la 0491'
             when '9dc5c6556880e544202b6c8b9c690c2b' then '❌  se quedó en la 0048 — la vigente es la 0491'
             when 'e32dd910eb59c3c4a4d5674a3f882570' then '❌  se quedó en la 0048 — la vigente es la 0491'
             when 'a124a16cc4d2f2339b88d1a4b022bb10' then '❌  se quedó en la 0035 — la vigente es la 0491'
             when 'ab67fd3d815e238f12dc51af06d58431' then '❌  se quedó en la 0035 — la vigente es la 0491'
             when 'f41fbffb0003d6247b23ad04be606af5' then '❌  se quedó en la 0030 — la vigente es la 0491'
             when '2824918732fa6408a25a8cfb25e0b153' then '❌  se quedó en la 0030 — la vigente es la 0491'
             when '7994e80b03131946a4dcd12d43899592' then '❌  se quedó en la 0029 — la vigente es la 0491'
             when '14d8b8c879a39ea9b8f5291e131abced' then '❌  se quedó en la 0029 — la vigente es la 0491'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_provisiones'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_provisiones'
         ), '⚠   la función NO EXISTE'), 1000004
  union all
  select 'PLATA', 'fn_planilla_congelar', coalesce((
           select string_agg(case md5(p.prosrc)
             when '3e581b656db64e9d3e55c4d404836441' then '✓   al día (0476)'
             when 'e12ef7d2fddff5b26cf339e0a5eb81ce' then '✓   al día (0476, pegada sin comentarios)'
             when 'bb6f77c44573275aff389960ca109dc5' then '✓   al día (0476, pegada desde Windows)'
             when 'dd9fc21c9df58e77bc1b0e4b638c3306' then '✓   al día (0476, desde Windows y sin comentarios)'
             when '93e3ea7dc0e661b90f7dc2ebb8b5f59c' then '✗   0476 con los acentos rotos — vuelve a pegarla'
             when '7a66a410278e86724092adf360904535' then '❌  se quedó en la 0323 — la vigente es la 0476'
             when '331e95a0eef8131185dfaff61987082e' then '❌  se quedó en la 0323 — la vigente es la 0476'
             when '645667b844f2e977534fbad6829632c5' then '❌  se quedó en la 0284 — la vigente es la 0476'
             when '28aedd342f7cc05fa05347a7909d6596' then '❌  se quedó en la 0284 — la vigente es la 0476'
             when '1692771a95d4fe46d1d01d7005b37728' then '❌  se quedó en la 0280 — la vigente es la 0476'
             when '63364f40980570e732b03374d04428cc' then '❌  se quedó en la 0280 — la vigente es la 0476'
             when '998f5305129d865719e531fd9c0d957f' then '❌  se quedó en la 0244 — la vigente es la 0476'
             when '42d59bddd0d28090c32178c38ecb287b' then '❌  se quedó en la 0244 — la vigente es la 0476'
             when 'e7e8058baf4eaef7b832c089c7c47fbd' then '❌  se quedó en la 0243 — la vigente es la 0476'
             when '9504720348bfa5234384012989fb569a' then '❌  se quedó en la 0243 — la vigente es la 0476'
             when 'af7956b5b84122c148196ff6a559adda' then '❌  se quedó en la 0201 — la vigente es la 0476'
             when '1cc68dc56acb76a68f3c6ce4cea9b82a' then '❌  se quedó en la 0201 — la vigente es la 0476'
             when '8c07866249e413c2b76bb7f5a75b47da' then '❌  se quedó en la 0134 — la vigente es la 0476'
             when '1c6297943a4725112e48982c4c9ee285' then '❌  se quedó en la 0134 — la vigente es la 0476'
             when '1b916cb6ba3643297fe75e6b1c3a24d1' then '❌  se quedó en la 0127 — la vigente es la 0476'
             when 'd73fcd77d90d6909fedc1ef55a14c318' then '❌  se quedó en la 0127 — la vigente es la 0476'
             when '3ef6a55f0b4d70ebc4f9cb7572d4a939' then '❌  se quedó en la 0096 — la vigente es la 0476'
             when 'b1f1c38057e2417d581e2506818527a4' then '❌  se quedó en la 0096 — la vigente es la 0476'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_planilla_congelar'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_planilla_congelar'
         ), '⚠   la función NO EXISTE'), 1000005
  union all
  select 'PLATA', 'fn_planilla_congelar_pendientes', coalesce((
           select string_agg(case md5(p.prosrc)
             when '29a080658c80f06c79ff68dfc1771bae' then '✓   al día (0323)'
             when 'c238d46d08f45c7828a2e94ee29a20ea' then '✓   al día (0323, pegada desde Windows)'
             when 'f9fca2b0f9e6fbe6b667ce8a481e69a7' then '✗   0323 con los acentos rotos — vuelve a pegarla'
             when '433bebcadda139cfb3a723e269f9b0b6' then '❌  se quedó en la 0096 — la vigente es la 0323'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_planilla_congelar_pendientes'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_planilla_congelar_pendientes'
         ), '⚠   la función NO EXISTE'), 1000006
  union all
  select 'PLATA', 'fn_periodo_pagado', coalesce((
           select string_agg(case md5(p.prosrc)
             when '4c655cdd6b1b73784037491baabc02d2' then '✓   al día (0323)'
             when '7bf1b7ac9384fda0f86d297426e790b0' then '✓   al día (0323, pegada sin comentarios)'
             when '44e3c5dfa50a665566fec91ac9add366' then '✓   al día (0323, pegada desde Windows)'
             when '3ebe2d06d0c7e3512f8a334a28b915cc' then '✓   al día (0323, desde Windows y sin comentarios)'
             when 'fde0d3864c04e5d6de54784d208015f4' then '✗   0323 con los acentos rotos — vuelve a pegarla'
             when 'ba09a250d6496084f093dccb2bd9108b' then '❌  se quedó en la 0096 — la vigente es la 0323'
             when '0d7897c8043128160a3f0bbfd42a108c' then '❌  se quedó en la 0095 — la vigente es la 0323'
             when 'e503c37f75625c7db7512a2276993a6f' then '❌  se quedó en la 0025 — la vigente es la 0323'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_periodo_pagado'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_periodo_pagado'
         ), '⚠   la función NO EXISTE'), 1000007
  union all
  select 'PLATA', 'fn_revertir_pago', coalesce((
           select string_agg(case md5(p.prosrc)
             when '0e9f58bed7f60fd01dbff3ab36c8bda1' then '✓   al día (0546)'
             when 'bab96337babf321944b9db2baa228e53' then '✓   al día (0546, pegada sin comentarios)'
             when 'f2f63bd841e6f34d37ae35ed987cadcc' then '✓   al día (0546, pegada desde Windows)'
             when '502850fa97280075c2648be1b6e967d3' then '✓   al día (0546, desde Windows y sin comentarios)'
             when '973f205e7ed257edcbf3f2ea640a3bb2' then '✗   0546 con los acentos rotos — vuelve a pegarla'
             when 'ac66bb056d28898f209ec7e17b9511af' then '❌  se quedó en la 0323 — la vigente es la 0546'
             when '8a28101cbcfafe2e35665224815a70f4' then '❌  se quedó en la 0323 — la vigente es la 0546'
             when '76e13c78f37272a0fcb549b87c224947' then '❌  se quedó en la 0203 — la vigente es la 0546'
             when '1176db7e5595eefbb3aa8efaa6f18a1d' then '❌  se quedó en la 0203 — la vigente es la 0546'
             when '05d12836850e6fb9a5745ff661a1f23a' then '❌  se quedó en la 0066 — la vigente es la 0546'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_revertir_pago'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_revertir_pago'
         ), '⚠   la función NO EXISTE'), 1000008
  union all
  select 'PLATA', 'fn_repagar_periodo', coalesce((
           select string_agg(case md5(p.prosrc)
             when '7d2a5ffb4ca80368f3312925cbf706d8' then '✓   al día (0323)'
             when '0399c817e02a33a2d7b2e948c1612169' then '✓   al día (0323, pegada sin comentarios)'
             when '6ff8f29b2fddfd4ab809c854da9db8c0' then '✓   al día (0323, pegada desde Windows)'
             when '6c3f1cf20145c79c8d96997cf11f8998' then '✓   al día (0323, desde Windows y sin comentarios)'
             when '03def4d04f9fa78bc153126ab3725e8e' then '✗   0323 con los acentos rotos — vuelve a pegarla'
             when 'ae86e4e9204325dec278ff2617083bb0' then '❌  se quedó en la 0098 — la vigente es la 0323'
             when '5a6f698ce7443f3a8e5d9e4822f6badf' then '❌  se quedó en la 0098 — la vigente es la 0323'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_repagar_periodo'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_repagar_periodo'
         ), '⚠   la función NO EXISTE'), 1000009
  union all
  select 'PLATA', 'fn_proyeccion_periodo', coalesce((
           select string_agg(case md5(p.prosrc)
             when '7724765c6a73abbcf01378b807ac93c9' then '✓   al día (0323)'
             when 'f883bd1063c4f35d6a3a6ec0c78212c7' then '✓   al día (0323, pegada sin comentarios)'
             when 'b7ac9bf4f3d7abee8434501b09f404bb' then '✓   al día (0323, pegada desde Windows)'
             when 'aa56108a87cf91bec49bff57b28ebdc6' then '✓   al día (0323, desde Windows y sin comentarios)'
             when '2d4699602909ce55aad43f71f739d788' then '✗   0323 con los acentos rotos — vuelve a pegarla'
             when '0c9718e51240a97b809495c28a68ce93' then '❌  se quedó en la 0313 — la vigente es la 0323'
             when '1fd7511c585c331ead402a55ae7cc463' then '❌  se quedó en la 0313 — la vigente es la 0323'
             when 'fad72eefc30b5b2de9dd81460cf87dd9' then '❌  se quedó en la 0105 — la vigente es la 0323'
             when '63cd6604ab9e6e9793d5f5a65c711977' then '❌  se quedó en la 0104 — la vigente es la 0323'
             when 'e3a68815feac82da3ea293ed1a63a5ab' then '❌  se quedó en la 0104 — la vigente es la 0323'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_proyeccion_periodo'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo'
         ), '⚠   la función NO EXISTE'), 1000010
  union all
  select 'PLATA', 'fn_costos_planilla', coalesce((
           select string_agg(case md5(p.prosrc)
             when 'a25fbbc2a67dcc6b07f1cb2a8647c124' then '✓   al día (0608)'
             when '171b0f29312249244e60dff106b73887' then '✓   al día (0608, pegada sin comentarios)'
             when '5431bd4f16d008a90612a6ab564a2764' then '✓   al día (0608, pegada desde Windows)'
             when '0e9fbcdce8ab6f53a6ffff6c8fa2f829' then '✓   al día (0608, desde Windows y sin comentarios)'
             when 'd23ea98ef93328615caaeb37286f0f55' then '✗   0608 con los acentos rotos — vuelve a pegarla'
             when '939e5ef4840e6ca088b08a17d2084e74' then '❌  se quedó en la 0260 — la vigente es la 0608'
             when '32beb6a3c1bd9790cfa0f49b2b41be53' then '❌  se quedó en la 0260 — la vigente es la 0608'
             when '2e960fc4db713c4fc4dad10f6c42a67b' then '❌  se quedó en la 0099 — la vigente es la 0608'
             when '85ed93683f4deeaaf1bab2367862c195' then '❌  se quedó en la 0099 — la vigente es la 0608'
             when '6c15090ca01d6d581ed579e3d17efbb8' then '❌  se quedó en la 0097 — la vigente es la 0608'
             when '3b28c16970dac901fff93637d6c20df0' then '❌  se quedó en la 0097 — la vigente es la 0608'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_costos_planilla'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_costos_planilla'
         ), '⚠   la función NO EXISTE'), 1000011
  union all
  select 'PLATA', 'fn_vacaciones_truncas', coalesce((
           select string_agg(case md5(p.prosrc)
             when 'f4b999990f36f2471dce7ba8f053b27f' then '✓   al día (0341)'
             when '1ac4f5f78e9870390ea12f0be7f9f62e' then '✓   al día (0341, pegada sin comentarios)'
             when '07719de72894b212b0b904e3c64eb869' then '✓   al día (0341, pegada desde Windows)'
             when '9c03d69c3cae85576bb8e11a886acb4c' then '✓   al día (0341, desde Windows y sin comentarios)'
             when '66888cb5e9c03804ec2188ac750bdd9b' then '✗   0341 con los acentos rotos — vuelve a pegarla'
             when '530af4af90c1fa90d0f9b9e8c36b1f05' then '❌  se quedó en la 0297 — la vigente es la 0341'
             when 'd1d87a44eaf89377e48e832261972264' then '❌  se quedó en la 0297 — la vigente es la 0341'
             when 'a005fc6907be6a55d7243bdf6e65aa9d' then '❌  se quedó en la 0283 — la vigente es la 0341'
             when '9a95ca72803189a2b56f321a24e7bdae' then '❌  se quedó en la 0283 — la vigente es la 0341'
             when '9535ed57eebc317ddbefca0dc8fd409e' then '❌  se quedó en la 0278 — la vigente es la 0341'
             when '47baa810366546ef4db66d5ea50de8ee' then '❌  se quedó en la 0278 — la vigente es la 0341'
             when '0d411bdbc3edd858264f80d7a929ddc9' then '❌  se quedó en la 0196 — la vigente es la 0341'
             when '31fcce36551b5499b4773e2e879d0839' then '❌  se quedó en la 0196 — la vigente es la 0341'
             when 'fdb8caba30b8652037a2312296f7a39c' then '❌  se quedó en la 0129 — la vigente es la 0341'
             when '1c27c4807089a88e299be2ebf4be6746' then '❌  se quedó en la 0129 — la vigente es la 0341'
             when 'ab17762b22fb34c67f557c7aba56226b' then '❌  se quedó en la 0087 — la vigente es la 0341'
             when '4781866e5cd00d0f8a0e62c23ad57272' then '❌  se quedó en la 0087 — la vigente es la 0341'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_vacaciones_truncas'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_vacaciones_truncas'
         ), '⚠   la función NO EXISTE'), 1000012
  union all
  select 'PLATA', 'fn_cts_trunca', coalesce((
           select string_agg(case md5(p.prosrc)
             when '62edcd69debfe33261d41759192555c2' then '✓   al día (0278)'
             when 'fd1da0c43ac790d5cdf2cd6bad558d74' then '✓   al día (0278, pegada sin comentarios)'
             when '266c1d58012054006288458c8720c263' then '✓   al día (0278, pegada desde Windows)'
             when '7eca562787ba1b1be0071e9c5d2757ba' then '✓   al día (0278, desde Windows y sin comentarios)'
             when 'cf3045b08f1ee8665fb8ceedbfdc267f' then '✗   0278 con los acentos rotos — vuelve a pegarla'
             when '84e6226144339fef7eb1bee079f7de5b' then '❌  se quedó en la 0196 — la vigente es la 0278'
             when 'b30b95baecb6fe5685a4fe144ee1aafa' then '❌  se quedó en la 0196 — la vigente es la 0278'
             when '1538ac9dfbc59d71f6e48260a3df410b' then '❌  se quedó en la 0163 — la vigente es la 0278'
             when 'ed66f489563979fe8503b06834de68b8' then '❌  se quedó en la 0163 — la vigente es la 0278'
             when '33a6b796c2bc91e496d591d0337900f1' then '❌  se quedó en la 0129 — la vigente es la 0278'
             when 'e22724f77efe97b401ceb56f19af2334' then '❌  se quedó en la 0129 — la vigente es la 0278'
             when 'cec45b4dde4d3f6e7e5abc45a076ab5e' then '❌  se quedó en la 0087 — la vigente es la 0278'
             when 'd2ef429a227c3eefa9eb9106a138c9af' then '❌  se quedó en la 0087 — la vigente es la 0278'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_cts_trunca'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_cts_trunca'
         ), '⚠   la función NO EXISTE'), 1000013
  union all
  select 'PLATA', 'fn_grati_trunca', coalesce((
           select string_agg(case md5(p.prosrc)
             when 'fc8bdd9c80e9304137ee19baa21c83ff' then '✓   al día (0163)'
             when '96a3ccaac63df85bef7ff72b39ab21e2' then '✓   al día (0163, pegada sin comentarios)'
             when 'ccfbe39126686399c3de5524f56d9b87' then '✓   al día (0163, pegada desde Windows)'
             when '729949f397a1e9b83ae8a4e7b6a3daa9' then '✓   al día (0163, desde Windows y sin comentarios)'
             when '0084f4cc66b02654c4f2b2e9532b2cce' then '✗   0163 con los acentos rotos — vuelve a pegarla'
             when 'e5d3fca5304b54c7de6777f0c6f17ad1' then '❌  se quedó en la 0129 — la vigente es la 0163'
             when '48ab9c755d17f87d67bd213282e03e2a' then '❌  se quedó en la 0129 — la vigente es la 0163'
             when 'ef453848206b7fb1cdc394a33571edcb' then '❌  se quedó en la 0087 — la vigente es la 0163'
             when '18b8a0ef50d78510a25af5db5f3284dc' then '❌  se quedó en la 0087 — la vigente es la 0163'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_grati_trunca'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_grati_trunca'
         ), '⚠   la función NO EXISTE'), 1000014
  union all
  select 'PLATA', 'fn_grati_trunca_bruta', coalesce((
           select string_agg(case md5(p.prosrc)
             when '0b932c856bbe6f189b53a08a6fbf161f' then '✓   al día (0343)'
             when '05c1b09e2a22df1824bc0167003939c8' then '✓   al día (0343, pegada sin comentarios)'
             when '9a03bf50bfdc7e343239c577c47108c8' then '✓   al día (0343, pegada desde Windows)'
             when '7cf60b0eebaeb3ac6abf4629d505cf7c' then '✓   al día (0343, desde Windows y sin comentarios)'
             when '83ec1cf9753cbad03ca9d099ed9e2945' then '✗   0343 con los acentos rotos — vuelve a pegarla'
             when '8a4d089c3bf1bc78ef0563191c942a2f' then '❌  se quedó en la 0289 — la vigente es la 0343'
             when 'c56aa4fb65eaaeeadad589b88ab4fa9e' then '❌  se quedó en la 0289 — la vigente es la 0343'
             when '78cb6ac19121bb40f76d62f23f58dfd4' then '❌  se quedó en la 0196 — la vigente es la 0343'
             when '1832cbfe08d0a9c52c1fd5ad6640d822' then '❌  se quedó en la 0196 — la vigente es la 0343'
             when 'e5d3fca5304b54c7de6777f0c6f17ad1' then '❌  se quedó en la 0163 — la vigente es la 0343'
             when '48ab9c755d17f87d67bd213282e03e2a' then '❌  se quedó en la 0163 — la vigente es la 0343'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_grati_trunca_bruta'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_grati_trunca_bruta'
         ), '⚠   la función NO EXISTE'), 1000015
  union all
  select 'PLATA', 'fn_grati_cts_periodo', coalesce((
           select string_agg(case md5(p.prosrc)
             when '029c534ff79b6e60d7a5a760be659053' then '✓   al día (0346)'
             when '6fa0ce305883c9d3216161998cee43bc' then '✓   al día (0346, pegada sin comentarios)'
             when 'ba3842ca25d44d0c33eaae589ad8831e' then '✓   al día (0346, pegada desde Windows)'
             when 'ab45ed033f142e0a9dadee1c8d35a813' then '✓   al día (0346, desde Windows y sin comentarios)'
             when '8167a3ba9914f22c1fe4debb025df8bc' then '✗   0346 con los acentos rotos — vuelve a pegarla'
             when '2051d2fc838ca0514a75f32791aef614' then '❌  se quedó en la 0338 — la vigente es la 0346'
             when '1737f40c452fe240db07ea2a4a2320d3' then '❌  se quedó en la 0338 — la vigente es la 0346'
             when '0bc70f11dd23ede89441e11486d58d70' then '❌  se quedó en la 0088 — la vigente es la 0346'
             when '1c01cf1afcedd57358d9c7cd4f65346c' then '❌  se quedó en la 0088 — la vigente es la 0346'
             when 'b9739b9367b2e32bf250dc6455d9e30f' then '❌  se quedó en la 0050 — la vigente es la 0346'
             when 'c9f611aa3eb2e7efff0c9c8b6451aa3a' then '❌  se quedó en la 0050 — la vigente es la 0346'
             when '8357793976dc7db790fb443c067d4cac' then '❌  se quedó en la 0049 — la vigente es la 0346'
             when '9ea7afb55c21135c7370e946eb3e4020' then '❌  se quedó en la 0049 — la vigente es la 0346'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_grati_cts_periodo'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_grati_cts_periodo'
         ), '⚠   la función NO EXISTE'), 1000016
  union all
  select 'PLATA', 'fn_liquidacion', coalesce((
           select string_agg(case md5(p.prosrc)
             when 'c229efda8ca8ee484a9eafd7959e8829' then '✓   al día (0244)'
             when '39e2e6fb82c02a2b5920f6dae056223c' then '✓   al día (0244, pegada sin comentarios)'
             when '71eefc2793f5511ea58468c203279076' then '✓   al día (0244, pegada desde Windows)'
             when '92d8e6525a312bb482657f45dc0fbad9' then '✓   al día (0244, desde Windows y sin comentarios)'
             when 'f50c5705121cc41f09e372eba0acae46' then '✗   0244 con los acentos rotos — vuelve a pegarla'
             when 'c724dc210b4974e2dd887aee373a02e8' then '❌  se quedó en la 0243 — la vigente es la 0244'
             when 'b574a405f47e8e42ebf1d866de93cc6e' then '❌  se quedó en la 0243 — la vigente es la 0244'
             when 'f346444e985b40caf0e5e4f3df4e1f43' then '❌  se quedó en la 0164 — la vigente es la 0244'
             when '2e7073f098287c0b050c8440470a6bc5' then '❌  se quedó en la 0164 — la vigente es la 0244'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_liquidacion'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_liquidacion'
         ), '⚠   la función NO EXISTE'), 1000017
  union all
  select 'PLATA', 'fn_liquidacion_pagar', coalesce((
           select string_agg(case md5(p.prosrc)
             when 'e9b657d6b1b4f7f72310c6e988fcc725' then '✓   al día (0454)'
             when '3331e2e3d3a10183e09f0c9c7f73fb5e' then '✓   al día (0454, pegada sin comentarios)'
             when 'f5a0565c028c3958c4af0368bd5bc3cb' then '✓   al día (0454, pegada desde Windows)'
             when '1f88dd83154a3c305407a1d6d12d1ac0' then '✓   al día (0454, desde Windows y sin comentarios)'
             when 'ef6cc45d94a46a1ed701991cf220fcd4' then '✗   0454 con los acentos rotos — vuelve a pegarla'
             when '0e5b1a1d4c3d3e75d0ba1e160d450d79' then '❌  se quedó en la 0255 — la vigente es la 0454'
             when '0bcd3e31ed192d71bf26ce11e5569efb' then '❌  se quedó en la 0255 — la vigente es la 0454'
             when '0f54650a4fd955b83e937486cfe8e7eb' then '❌  se quedó en la 0167 — la vigente es la 0454'
             when 'e510224bedcdecbef86f3099e20642d3' then '❌  se quedó en la 0167 — la vigente es la 0454'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_liquidacion_pagar'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_liquidacion_pagar'
         ), '⚠   la función NO EXISTE'), 1000018
  union all
  select 'PLATA', 'fn_liquidacion_diferencias', coalesce((
           select string_agg(case md5(p.prosrc)
             when 'facbab10e25e5b04b5c6315cbe863d88' then '✓   al día (0454)'
             when 'ae604dd6c37ddd19de5cebd5c50804ad' then '✓   al día (0454, pegada sin comentarios)'
             when '8414d4f483644b59fa515a0337de6913' then '✓   al día (0454, pegada desde Windows)'
             when '2bf52da267ca83e9e4287954e23325e2' then '✓   al día (0454, desde Windows y sin comentarios)'
             when '8e461c442a542b139bce81bb37da39c8' then '✗   0454 con los acentos rotos — vuelve a pegarla'
             when '8b52942fd1a8029c9600ba6a00cc6754' then '❌  se quedó en la 0251 — la vigente es la 0454'
             when '57b802d098f06ec9dd26b1e5c25be692' then '❌  se quedó en la 0251 — la vigente es la 0454'
             when 'e803b9b00e497f18a069beeedf622980' then '❌  se quedó en la 0167 — la vigente es la 0454'
             when 'b18b73ca5949292c596bd1444b564d2f' then '❌  se quedó en la 0167 — la vigente es la 0454'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_liquidacion_diferencias'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_liquidacion_diferencias'
         ), '⚠   la función NO EXISTE'), 1000019
  union all
  select 'PLATA', 'fn_liquidaciones_pendientes', coalesce((
           select string_agg(case md5(p.prosrc)
             when '1d69c2b044e8f058dd199f6f95e7951e' then '✓   al día (0475)'
             when 'e20ddb0a92fd5344375c1dfbe959db49' then '✓   al día (0475, pegada sin comentarios)'
             when 'f4a179c62f4ffa6657ddba979cfe1ccb' then '✓   al día (0475, pegada desde Windows)'
             when '094289b8a7f89f064722293bb478441d' then '✓   al día (0475, desde Windows y sin comentarios)'
             when 'a9f0f6dd2becaf3f95a01e53d7da71b5' then '✗   0475 con los acentos rotos — vuelve a pegarla'
             when '3b8560fc935080cf485cb1a6895bf373' then '❌  se quedó en la 0454 — la vigente es la 0475'
             when 'cbb2c6978238bfccfd6350f1f14ff387' then '❌  se quedó en la 0454 — la vigente es la 0475'
             when '924153ffc2446d6de4067168d4127ea1' then '❌  se quedó en la 0251 — la vigente es la 0475'
             when '24a08306ff6ae9924dab03340def6b20' then '❌  se quedó en la 0251 — la vigente es la 0475'
             when 'b52de313bf26b012e6cdbb89bf0ff292' then '❌  se quedó en la 0167 — la vigente es la 0475'
             when '56774b85a2c74b3d668fea0a3aaab62b' then '❌  se quedó en la 0164 — la vigente es la 0475'
             when '35e6393367c4f01bbced5aaedfbc0f40' then '❌  se quedó en la 0164 — la vigente es la 0475'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_liquidaciones_pendientes'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_liquidaciones_pendientes'
         ), '⚠   la función NO EXISTE'), 1000020
  union all
  select 'PLATA', 'fn_educacion_monto', coalesce((
           select string_agg(case md5(p.prosrc)
             when 'd04294d428d0dcfb82e44e1e5af60ed9' then '✓   al día (0281)'
             when '34b64714bf70d9cce3c7c39724eab82a' then '✓   al día (0281, pegada sin comentarios)'
             when '2524a59a502c9f0da60b9cfcdfe22b38' then '✓   al día (0281, pegada desde Windows)'
             when 'fb103a38416441ed139cfea42144bed1' then '✓   al día (0281, desde Windows y sin comentarios)'
             when '3c8e59c3d476a7c2335f0497c3caaad6' then '❌  se quedó en la 0149 — la vigente es la 0281'
             when '85c19bb03591e507575b634ecc0f46f0' then '❌  se quedó en la 0149 — la vigente es la 0281'
             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh fn_educacion_monto'
           end, ' · ')
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_educacion_monto'
         ), '⚠   la función NO EXISTE'), 1000021
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

  -- Las huérfanas, una fila cada una y ANTES del resumen. Si hay alguna sin
  -- explicar, es lo único que importa de toda esta consulta. Las explicadas se
  -- siguen viendo —como las que no se pegan—, pero con su razón al lado.
  select a.numero::text,
         a.nombre,
         case when a.explicada
              then '—   sobra la fila, ya explicada (ver scripts/hooks/huecos-conocidos.txt)'
              else '⚠️  SOBRA LA FILA — revísala (ver abajo)' end,
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
         case when (select count(*) filter (where not explicada) from huerfanas) > 0
              then ' · ⚠️ ' || (select count(*) filter (where not explicada) from huerfanas)::text || ' PEGADAS Y NO GUARDADAS'
              else '' end ||
         case when (select count(*) from plata where estado not like '✓%') > 0
              then ' · ❌ ' || (select count(*) from plata where estado not like '✓%')::text || ' FUNCIONES DE PLATA NO ESTÁN AL DÍA'
              else '' end,
         -- Una huérfana sin explicar manda sobre todo lo demás: que falte pegar
         -- algo es atraso normal; que algo esté pegado y sin guardar es lo que
         -- costó tres sustos y no avisa solo.
         case when (select count(*) filter (where not explicada) from huerfanas) > 0 then '⚠️  MIRA ARRIBA'
              -- Una función de plata atrasada va antes que lo que falta pegar: el
              -- registro dice que está y el cuerpo dice que no.
              when (select count(*) from plata where estado not like '✓%') > 0 then '❌  MIRA ABAJO'
              when (select count(*) filter (where falta) from diff) = 0
              then '✓   al día' else '❌  hay pendientes' end,
         '', 999999

  union all

  -- Lo que el registro no puede responder: qué versión de cada función de plata
  -- está viva de verdad.
  select etiqueta, funcion || ' · versión viva', estado, '', orden from plata

  union all

  -- El barrido, que no depende de ninguna lista escrita a mano y por eso vale
  -- más que las filas de arriba: cuenta CUALQUIER función cuyo cuerpo lleve el
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
         '', 2000000
) t
order by orden;
