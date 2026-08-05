-- ============================================================================
-- comparar_funciones.sql — ¿qué le falta a producción?
-- ----------------------------------------------------------------------------
-- HUELLAS REGENERADAS EL 2026-08-05 contra el esquema completo (hasta la 0151).
-- Las anteriores eran de cuando el repo iba por la 0101: 45 migraciones atrás,
-- así que la comparación llevaba meses sin poder decir nada útil.
-- Cubre 182 funciones y 242 candados.
-- ----------------------------------------------------------------------------
-- SOLO LEE. No modifica nada. Se puede correr las veces que haga falta.
--
-- Compara el texto de cada función `fn_*` de producción contra el de una base
-- construida desde cero con las 146 migraciones del repositorio en orden.
--
-- No busca frases ni marcadores: compara la huella del texto completo. Una
-- función o es idéntica o no lo es, y eso no se puede interpretar a favor.
--
-- Nació porque `migraciones_aplicadas` decía que la 0089 estaba aplicada y su
-- contenido no estaba en la base. Un hueco en el registro se ve; una migración
-- registrada que nunca corrió, no.
--
-- Las funciones se identifican por su FIRMA COMPLETA y no por su nombre: dos de
-- ellas están sobrecargadas (mismo nombre, distintos argumentos) y compararlas
-- por nombre daba dos diferencias falsas. Se descubrió corriendo esta consulta
-- contra la base de referencia esperando cero filas — y no dio cero.
--
-- QUÉ SIGNIFICA EL RESULTADO
--   · Sin filas        → producción está exactamente al día.
--   · desactualizada   → tiene una versión vieja, aunque el registro diga que
--                        la migración se aplicó.
--   · no existe        → la función nunca llegó a crearse.
--   · sobra            → existe en producción y no en el repositorio: resto de
--                        algo aplicado a mano que hay que documentar o quitar.
-- ============================================================================
with esperado(firma, huella) as (values
  ('fn_aceptar_incidencia(p_persona_id uuid, p_fecha date, p_tipo text, p_nota text)','555ebacee3040e94f6a139e648919824'),
  ('fn_acta_descanso(p_referencia text)','7006e0241fd1ab8b4a1a4fce97881bcd'),
  ('fn_actas_descanso()','0839c9738daecd37a3321f96d08bf175'),
  ('fn_acusar_politica_salarial(p_nombre text)','dbea272d336bd58d110d3b3e2181e3ee'),
  ('fn_acuses_politica_salarial()','3dcdc3e71b1b41b0c09f6241da748c03'),
  ('fn_agregar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_ts timestamp with time zone, p_motivo text, p_motivo_otro text)','6ac4844a5b71ac50693d60f660b8a5b3'),
  ('fn_agregar_movimiento(p_periodo_id uuid, p_persona_id uuid, p_tipo text, p_concepto text, p_monto numeric)','ee67c18902ee72c36366505e3218886c'),
  ('fn_agregar_movimiento(p_periodo_id uuid, p_persona_id uuid, p_tipo text, p_concepto text, p_monto numeric, p_categoria text)','7d33eff44024a852567e80906bd2c160'),
  ('fn_anular_ausencia(p_id uuid, p_motivo text)','5250204856581f5306fdbe9666df0870'),
  ('fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)','fca64b89294b950ad0e2d2c782a144fc'),
  ('fn_aprobar_ausencia(p_id uuid)','e10c71925cd60498dcc45a4add2d61be'),
  ('fn_area_activa(p_codigo text, p_activa boolean)','5e472c9a6ba2894dae59dbc32ff427c7'),
  ('fn_areas()','ae59345d674045259d98a04fd5900f80'),
  ('fn_ausencias(p_desde date, p_hasta date, p_persona_id uuid)','d9649325c740c9acf3ff544dcc541713'),
  ('fn_ausencias_alerta(p_persona_id uuid)','3c6fb48bc723004be7a9aa3359443bce'),
  ('fn_auto_cierre()','a8c6fd980082ba54e7705abb89181f51'),
  ('fn_calcular_bono_puntualidad(p_periodo_id uuid)','00996c51302e4e3ec098179c308a5a77'),
  ('fn_cargo_de_rol(p_rol rol_usuario)','c148dd8c134ba137925f21c41dce1ca2'),
  ('fn_cerrar_derechohabiente(p_id uuid, p_hasta date)','ec87470ce6be61477c712a0f23bb1589'),
  ('fn_cesar_persona(p_persona_id uuid, p_fecha_cese date, p_motivo text, p_tipo_vinculo text)','da76f971ded2d7c4f91fff2f82c403b2'),
  ('fn_confirmar_auto_cierre(p_marcaje_id uuid, p_motivo text)','bb55fc2a3ef9f63af0f5edcbd1e154be'),
  ('fn_contratos_por_vencer(p_dias integer)','3e78bec11268786382aeb459b690125f'),
  ('fn_corregir_marca(p_marcaje_id uuid, p_nuevo_tipo tipo_marca, p_nuevo_ts timestamp with time zone, p_motivo text)','1ef15c4480eea7f095b505d92aa5f598'),
  ('fn_corregir_marcaje(p_marcaje_id uuid, p_nuevo_ts timestamp with time zone, p_motivo text)','12353fd8c20e09b58c2c3f89bc19ab97'),
  ('fn_costos_planilla(p_desde date, p_hasta date)','2e960fc4db713c4fc4dad10f6c42a67b'),
  ('fn_crear_periodo(p_fecha_fin date, p_fecha_ini date)','c2f7ac69eb357d742fcbd30e3be063a9'),
  ('fn_crear_persona(p_nombres text, p_apellidos text, p_sede_base_id uuid, p_rol text, p_funcion text, p_email text, p_pin_hash text)','b74c3530652abb56c9bc97101e4512d0'),
  ('fn_cts_trunca(p_persona_id uuid, p_fecha_cese date)','33a6b796c2bc91e496d591d0337900f1'),
  ('fn_cuadro_categorias()','cf790aadc2695bdcf2ce6194646e7065'),
  ('fn_dcs_validar_dia_laborable()','5de3db54781a6d67fa9b94905667f95c'),
  ('fn_devenga_beneficios(p_tipo text)','5c99fb45d0b40ad82a11ed85a65f03d9'),
  ('fn_dia_incoherente(p_persona_id uuid, p_fecha date)','e76cd69c17717e50498c3e89f93ffe96'),
  ('fn_dia_suspendido(p_persona_id uuid, p_fecha date)','e1fe46d889b2906a38d1b97ec8da0da8'),
  ('fn_dias_por_revisar(p_limite integer)','8d17f437a3a134413f03092b6f4f875f'),
  ('fn_dias_suspension(p_persona_id uuid, p_desde date, p_dias integer)','4db223a7178ee0e68a3d85bfa042d0b9'),
  ('fn_educacion_candidatos()','906b7714b5c859e2d2f62dd4637e5de6'),
  ('fn_educacion_cerrar(p_id uuid, p_hasta date)','9d6fef4c5564722e99d6fbbd3e13c2d5'),
  ('fn_educacion_cerrar(p_id uuid, p_hasta date, p_motivo text)','63c3b66015d35f69b2fab2fe476325e6'),
  ('fn_educacion_cerrar_al_cesar()','6305c1a1cc9f02306ab50ea2e999a2ff'),
  ('fn_educacion_desde_cuando_puede_regir()','0df7a7963b920fd5d7802c6f996213f9'),
  ('fn_educacion_fecha_pagada(p_fecha date)','1d1a56ac5692e55b37d586d12e1f5339'),
  ('fn_educacion_listar()','18bfe2453c2984c9a15de4a6d7865374'),
  ('fn_educacion_monto(p_persona_id uuid, p_costo numeric)','3c8e59c3d476a7c2335f0497c3caaad6'),
  ('fn_educacion_por_atender()','b1f0f4c28593947e316b52858a0ca894'),
  ('fn_educacion_puede_ver(p_path text)','b9b9702116f258f7dbf5b0271693d087'),
  ('fn_educacion_registrar(p_persona_id uuid, p_institucion text, p_costo_declarado numeric, p_beneficiario text, p_vigente_desde date, p_vigente_hasta date, p_beneficiario_nombre text, p_comprobante_url text, p_nota text, p_id uuid, p_motivo text)','468ac92ce5cdcfff0331e40da1fab210'),
  ('fn_educacion_respeta_el_tope()','2e58508026b474248e9dba065239614f'),
  ('fn_eliminar_marcaje(p_marcaje_id uuid, p_motivo text)','838b05b1bac115d28b86ea0df0ee33e4'),
  ('fn_eliminar_periodo(p_periodo_id uuid)','14acc43cf164ba17e9e7e6cf0f7dc228'),
  ('fn_es_admin_o_lider()','77c2b4dbc2e00ed06cf048f830ef3efb'),
  ('fn_es_dia_laborable(p_persona_id uuid, p_fecha date)','e266f4286a38e57dcef1bd3db6471b4a'),
  ('fn_exigir_admin()','7bcd0acc91afecc3d41c2212611b60af'),
  ('fn_expediente_adjuntar(p_documento_id uuid, p_path text, p_tipo text, p_fecha_entrega timestamp with time zone, p_nota text)','e393b325e6c47d8f87119fd1f7418706'),
  ('fn_expediente_anular(p_id uuid, p_motivo text)','e5029b8f389a0a10d3947a204b1f9c1b'),
  ('fn_expediente_correlativo(p_prefijo text)','80bc6bce2a95165c203371f5bf6bdd19'),
  ('fn_expediente_crear_borrador(p_persona_id uuid, p_tipo_causal text, p_nivel text, p_hechos jsonb, p_periodo_desde date, p_periodo_hasta date, p_doc_previo_id uuid, p_suspension_dias integer, p_suspension_desde date, p_suspension_hasta date, p_observacion text)','aa4f18d662ada729252406e718c77ac8'),
  ('fn_expediente_doc_code(p_tipo text, p_nivel text)','972ff7808ba22e266c707ba9eaac743b'),
  ('fn_expediente_editar_borrador(p_id uuid, p_suspension_dias integer, p_suspension_desde date, p_suspension_hasta date, p_observacion text, p_hechos jsonb)','eac45387c58102ba404b6ba275345031'),
  ('fn_expediente_entregar(p_id uuid, p_medio text, p_fecha timestamp with time zone)','860001cc15a127e2d305539ad09c23a6'),
  ('fn_expediente_firmantes(p_id uuid)','9ec82c60f3d5c92e6bdeeb7f3d695c19'),
  ('fn_expediente_firmar(p_id uuid, p_firmante_id uuid)','adde09b0a8dc8a390eaabbd1929604a7'),
  ('fn_expediente_generar_falta(p_persona_id uuid)','de232c1bddeb768e2f67f3894db8bd22'),
  ('fn_expediente_generar_tardanza(p_persona_id uuid)','c903afab5449965c45d055fcd27c1d39'),
  ('fn_expediente_puede_actuar(p_persona_id uuid, p_nivel text)','9364c2070cd8e6b7d839093c8ac3ec4b'),
  ('fn_expediente_puede_adjuntar(p_path text)','82c7454151e1424de088dadd4a3119a5'),
  ('fn_expediente_reabrir(p_id uuid)','5c1573806022f78d087fec327ed1eef6'),
  ('fn_expediente_set_suspension(p_id uuid, p_dias integer, p_desde date)','96f32dbd2ff1c41da38765ef1ec5bbf6'),
  ('fn_falta_contadores(p_persona_id uuid, p_desde date)','87f843f521cab2245ca07d887c7f68c0'),
  ('fn_faltas(p_desde date, p_hasta date)','8887c5d18d8893bdf5b6383afdf1ff40'),
  ('fn_faltas_resumen(p_as_of date)','908b5225767289bef9adf3c6172f08b4'),
  ('fn_familia_marca(p_tipo tipo_marca)','5c1c6168f2f8a2273a8ec1cc00fda20c'),
  ('fn_feriados(p_anio integer)','1602210d11beebeaf2a3d55f96228a43'),
  ('fn_feriados_cobertura()','a790e743a6548a8b66cfe3f676c5c467'),
  ('fn_feriados_laborados(p_desde date, p_hasta date)','d2da31c15e5a245aa6df0a2ec0762b4f'),
  ('fn_fijar_base_declarada(p_rango text, p_monto numeric, p_vigente_desde date, p_omitir uuid[])','053869326ca87177a32fb772bc64442e'),
  ('fn_firma_de_memo(p_doc_id uuid)','f1c0ab05e73ef79f39332c08164d3799'),
  ('fn_firma_persona(p_persona_id uuid)','ae3af62d8f1e88f5e86438f7d0605f39'),
  ('fn_firmantes_disponibles()','4247b15f0763441dde3089d0029c6923'),
  ('fn_grati_cts_periodo(p_periodo_id uuid)','0bc70f11dd23ede89441e11486d58d70'),
  ('fn_grati_trunca(p_persona_id uuid, p_fecha_cese date)','e5d3fca5304b54c7de6777f0c6f17ad1'),
  ('fn_guardar_area(p_codigo text, p_nombre text, p_operativa boolean, p_orden integer)','a78673d2790695b5c6f6a5d81165d2d9'),
  ('fn_guardar_sede(p_codigo text, p_nombre text, p_tipo text)','b83590a169a115d07c5ab36c156aaf9e'),
  ('fn_historial_salario(p_persona_id uuid)','2cae9314ec12264e1267d7ca6ac87bba'),
  ('fn_hoy_lima()','e87871ddf03a82da311265290ba2060c'),
  ('fn_ingresos()','66c1c7d709719f25e1b8e9fb7f1780bf'),
  ('fn_jornadas_extra(p_desde date, p_hasta date, p_persona_id uuid)','73f003e983cf317867e9d8f5a273879d'),
  ('fn_justificar_falta(p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text)','01a3663f33ceaf6968e006c904023b99'),
  ('fn_levantar_sello_si_el_dia_cuadra(p_persona_id uuid, p_fecha date)','cd483362942e8747ad01037a6740c60e'),
  ('fn_levantar_tardanza(p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text)','55ab73386b32c9932df0c7c953109a00'),
  ('fn_marcaje_no_posterior_al_cese()','7b69d46ed6f9139095293bc82463fefd'),
  ('fn_mes_planilla_pagado(p_anio integer, p_mes integer)','fe4b0e0f798a6d65393f3017ed5363ef'),
  ('fn_meses_y_dias(p_desde date, p_hasta date)','3ec471defb94971909962762b2f7f3aa'),
  ('fn_mi_firma()','6888305c9fd04e2aa6f48865dac2d83e'),
  ('fn_movilidad_no_supera_el_techo()','1d18c11bd495046915d5fbd603c0e294'),
  ('fn_objetivo_agregar(p_persona_id uuid, p_anio integer, p_mes integer, p_descripcion text)','f0f66c3da8248b752dd26a32a763fb69'),
  ('fn_objetivo_editar(p_item_id uuid, p_descripcion text)','81143dec842bdd957d9eeda7609b2d1e'),
  ('fn_objetivo_eliminar(p_item_id uuid)','8831f1382677f2a7741824161a226504'),
  ('fn_objetivo_marcar(p_item_id uuid, p_cumplido boolean)','ea9efea843c782d9e0e5118df5707aa5'),
  ('fn_objetivos_checklist(p_anio integer, p_mes integer, p_persona_id uuid)','fea63da0b5964eb738907a26df3907c5'),
  ('fn_objetivos_resumen(p_anio integer, p_mes integer)','de85e39f25c4e9873625b06dfa99962b'),
  ('fn_objetivos_sync_mes(p_persona_id uuid, p_anio integer, p_mes integer)','fa33e9e21044daabec1586bd4b544a65'),
  ('fn_otorgar_descanso_sustitutorio(p_persona_id uuid, p_fecha_feriado date, p_fecha_descanso date, p_estado text, p_acta_ref text)','1cd1f6ac80ed669dd5a6e6c11db8cfc6'),
  ('fn_periodo_pagado(p_periodo_id uuid, p_pagado boolean)','ba09a250d6496084f093dccb2bd9108b'),
  ('fn_periodos()','e56f3b3c15ae8dd4d702d0dd13b63be1'),
  ('fn_persona_actual_id()','e2638cb6bced205433c784da592d7d27'),
  ('fn_personas_funciones()','a7382fd64ff95b65b3f2a8c26220dba5'),
  ('fn_planilla_calcular(p_ini date, p_fin date, p_periodo_id uuid)','aa3f471cf18636f4d6725831864bff64'),
  ('fn_planilla_congelar(p_periodo_id uuid, p_origen text, p_autor uuid)','8c07866249e413c2b76bb7f5a75b47da'),
  ('fn_planilla_congelar_pendientes()','433bebcadda139cfb3a723e269f9b0b6'),
  ('fn_planilla_foto_diferencias(p_periodo_id uuid)','3ab4453288cc6779621ac816be200575'),
  ('fn_politica_salarial_vigente()','4c099d907033aa874acecb98ca5ceb87'),
  ('fn_provisiones(p_as_of date)','d07fe93b516328b0fc1d6986f6082c3c'),
  ('fn_proyeccion_periodo(p_periodo_id uuid)','fad72eefc30b5b2de9dd81460cf87dd9'),
  ('fn_proyeccion_planilla(p_anio integer, p_mes integer)','cac0cb1099283cc4c3c327783c76c369'),
  ('fn_publicar_politica_salarial(p_documento text, p_notas text)','28fed0726c50ad5af3f10d2ef8f626bc'),
  ('fn_puede_gestionar_objetivos(p_persona_id uuid)','ff2987757cfad220e27b5029427befca'),
  ('fn_quitar_aceptacion(p_persona_id uuid, p_fecha date, p_tipo text)','44da7f2c66b272d34aa79553f981026f'),
  ('fn_quitar_descanso_sustitutorio(p_id uuid)','c8eb8b7854aab7536ddf0cefc40f02a0'),
  ('fn_quitar_feriado(p_fecha date)','78c1592506fa7abe332bcbb7c9e06f49'),
  ('fn_quitar_horario(p_persona_id uuid, p_desde date)','8dfc686df1a2944393320497a92c6d76'),
  ('fn_quitar_justificacion(p_persona_id uuid, p_fecha date)','c7fdf49a99bfa1659aae06b88c377ea6'),
  ('fn_quitar_levantamiento(p_persona_id uuid, p_fecha date)','df8917240242b38797bd94ff5877c0bb'),
  ('fn_quitar_movimiento(p_movimiento_id uuid)','6acec517707973b4e7c7461c8678ce28'),
  ('fn_quitar_rendimiento(p_persona_id uuid, p_anio integer, p_mes integer)','c912f7a665c207a54871680dafb9264b'),
  ('fn_quitar_turno(p_persona_id uuid, p_fecha date)','c0f7d21aba09ad6621148ee9945b42d5'),
  ('fn_quitar_vacaciones(p_id uuid)','d3d46e1c03adf5fdd8c44e84fa5ffc4b'),
  ('fn_reabrir_dia(p_persona_id uuid, p_motivo text)','8730c7a1a53a239e9d983449ad4eafa1'),
  ('fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)','0d2fc7ac6ba6d79ddfe94aa600d65654'),
  ('fn_reactivar_persona(p_persona_id uuid)','b0fd63db156a1a20219e3c0d2df5abf8'),
  ('fn_recalcular_jornada(p_persona_id uuid, p_fecha date)','e2c8e9af2a6a9a855331abb3895b90f6'),
  ('fn_registrar_ausencia(p_persona_id uuid, p_tipo text, p_fecha_inicio date, p_fecha_fin date, p_motivo text, p_doc_profesional text, p_doc_colegiatura text, p_doc_fecha date)','b6251b8b32f76e51749a51d68821ed01'),
  ('fn_registrar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_timestamp_cliente timestamp with time zone, p_client_uuid uuid, p_origen origen_marca, p_terminal_id uuid, p_sede_id uuid, p_motivo_otro text)','5a477b781d4dbbc639b8621ba8b3c7be'),
  ('fn_remuneracion_computable(p_persona_id uuid, p_fecha_ref date)','119fbcb6faca8c4a808e9ecf7b1f4838'),
  ('fn_repagar_periodo(p_periodo_id uuid, p_motivo text)','ae86e4e9204325dec278ff2617083bb0'),
  ('fn_revertir_pago(p_periodo_id uuid, p_motivo text)','05d12836850e6fb9a5745ff661a1f23a'),
  ('fn_rol_actual()','74a308165b3da1e740a21e199bde1c36'),
  ('fn_salarios_vigentes()','92dd2c78d79eccfa386f147fafd4cf02'),
  ('fn_sede_activa(p_codigo text, p_activa boolean)','bef707ff91fd487b3411c57016dc715d'),
  ('fn_sede_actual_persona()','fd2b6fe2563a26f358cd898647bc71c1'),
  ('fn_sede_actual_terminal()','a87b7ee707624305643e0973dba4e978'),
  ('fn_set_categoria(p_rango text, p_proposito text, p_funciones text, p_requisitos text, p_criterio text)','fcc1e595715a40205b97b1f36312671c'),
  ('fn_set_con_hijos(p_persona_id uuid, p_con_hijos boolean)','a5a5f35e8bedd9f128b2b92c05d0e1ff'),
  ('fn_set_datos_personales(p_persona_id uuid, p_nombre_dni text, p_fecha_nacimiento date, p_estado_civil text, p_direccion text, p_celular text, p_entidad_bancaria text, p_numero_cuenta text, p_grado_instruccion text, p_hijos_menores boolean, p_foto_dni_url text, p_foto_personal_url text, p_foto_profesional_url text, p_emergencia_nombre text, p_emergencia_vinculo text, p_emergencia_telefono text, p_discapacidad boolean, p_discapacidad_conadis text)','0a766c0210e75308b8a393a6922641a9'),
  ('fn_set_derechohabiente(p_id uuid, p_persona_id uuid, p_nombres text, p_apellidos text, p_vinculo text, p_documento text, p_fecha_nacimiento date, p_essalud boolean, p_vida_ley boolean, p_nota text)','593ecdb3ee09f78c6c6cf2cf140997eb'),
  ('fn_set_descanso(p_persona_id uuid, p_fecha date)','b5d0a2bfb5ee709e73ff3f8d18e3a200'),
  ('fn_set_documento(p_persona_id uuid, p_documento text, p_motivo text)','6ed5eeef04c61ee0ad669637ee1400c5'),
  ('fn_set_encargada_piso(p_persona_id uuid, p_valor boolean)','51fc254417cd7e7f0f394b573432afcc'),
  ('fn_set_fecha_ingreso(p_persona_id uuid, p_fecha date)','5f4a4aa7cdf3a16a53e1c42017e23108'),
  ('fn_set_feriado(p_fecha date, p_nombre text)','719d2dc02f9408322518c4b116d5775a'),
  ('fn_set_fin_contrato(p_persona_id uuid, p_fecha date, p_motivo text)','fda44096317b747e94327c5404aedb5c'),
  ('fn_set_funcion(p_persona_id uuid, p_funcion text)','22cae06af36f3158eda775de5f635c50'),
  ('fn_set_horario(p_persona_id uuid, p_hora_entrada time without time zone, p_hora_salida time without time zone, p_vigente_desde date, p_almuerzo_min integer, p_almuerzo_max integer, p_dias_laborables integer[])','18e285ca89e6f341909deb7a1392fbe8'),
  ('fn_set_horario_semanal(p_persona_id uuid, p_vigente_desde date, p_horario jsonb)','68790773c6b7e54830e02ecbdec540bf'),
  ('fn_set_justificacion(p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text)','0db19cb64c41e5eb01035a22396423fe'),
  ('fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana integer, p_meta integer)','6a778324d37b3bb992f553fb8a1c8324'),
  ('fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana integer, p_meta_manana integer, p_meta_tarde integer)','0dcf75bcebed1493c6007ade98df2afb'),
  ('fn_set_meta_encargadas(p_sede_id uuid, p_dia_semana integer, p_meta integer)','dd079847713710280c0aa46439ad1903'),
  ('fn_set_mi_firma(p_dataurl text)','240e266ee4732ddfecc029c3182c1ed2'),
  ('fn_set_objetivos(p_persona_id uuid, p_anio integer, p_mes integer, p_cumplidos integer, p_total integer)','f1862b8bf206d2983df6a7b2e5f2750d'),
  ('fn_set_regimen_pension(p_persona_id uuid, p_regimen text)','da460442eae9b94cbd189ea17b2b5652'),
  ('fn_set_rendimiento(p_persona_id uuid, p_anio integer, p_mes integer, p_porcentaje numeric, p_etiqueta_codigo text)','0e924aed4ff320a40094acfd44ba0018'),
  ('fn_set_salario(p_persona_id uuid, p_rango text, p_salario numeric, p_vigente_desde date, p_nota text)','55f844f6a6268b4f7051aa25a0103c9c'),
  ('fn_set_sueldo_base_legal(p_persona_id uuid, p_monto numeric)','4295f913a4ecb792c98477b0481b1499'),
  ('fn_set_tipo_vinculo(p_persona_id uuid, p_tipo text)','a1b6828c756ae184329dbc51d85aa9d1'),
  ('fn_set_turno(p_persona_id uuid, p_fecha date, p_hora_entrada time without time zone, p_hora_salida time without time zone)','af2b07ee7a0701e8b2603d20fb413f5b'),
  ('fn_set_updated_at()','1c4318bee4240d4113d86fad7eb15623'),
  ('fn_set_vacaciones(p_persona_id uuid, p_fecha_inicio date, p_fecha_fin date, p_observacion text)','14f66ca1723609ec1bdec5359844e8e4'),
  ('fn_set_visible_todas_sedes(p_persona_id uuid, p_valor boolean)','b5dc7eed73e7d886ef35131d5fda331b'),
  ('fn_siguiente_tipo_esperado(p_persona_id uuid, p_fecha date)','eb19e1a5549190fc3f167adc7f2195da'),
  ('fn_simular_planilla(p_ini date, p_fin date)','a4d5b292e6d51f4ce9f034e3890b99ff'),
  ('fn_subir_acta_descanso(p_referencia text, p_dataurl text, p_nombre text)','1f5dadf29e4bbb286a52add371f6d0a7'),
  ('fn_tardanzas_resumen(p_as_of date)','6eaceebecae9e7f5849aa1e1bb98067e'),
  ('fn_tipos_ausencia()','e4f4c232ac980951897926d136e6ca40'),
  ('fn_trg_foto_es_inmutable()','3d8fff6c913de4ad1b4b57743bc20b9b'),
  ('fn_trg_justificaciones_insert()','00681ffa094a9845e97e356663fc240b'),
  ('fn_trg_marcajes_delete_recalcular()','f1d6f346114f4de6d46d4799c6ae1e08'),
  ('fn_trg_marcajes_recalcular_jornada()','8686363919f2c4c53c4ca3691cba6c9e'),
  ('fn_trg_vacaciones_insert()','018dccfbcf1c260d7aa307294f400d0b'),
  ('fn_vacaciones_resumen(p_as_of date)','9d15efaec6147c3fbd1357ec7e7020d4'),
  ('fn_vacaciones_truncas(p_persona_id uuid, p_fecha_cese date)','fdb8caba30b8652037a2312296f7a39c'),
  ('fn_valida_firmante_empresa()','b305bfcbcb36a209cdd7fffde4cce4e4'),
  ('fn_verificar_corrector(p_persona_objetivo uuid)','1ca3cb77fdcfddd25ea7ef31ff0eab6e')
),
real as (
  select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as firma,
         md5(p.prosrc) as huella
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'fn\_%'
)
select coalesce(e.firma, r.firma) as funcion,
       case when r.firma is null then 'no existe en produccion'
            when e.firma is null then 'sobra en produccion (no esta en el repo)'
            else 'desactualizada' end as estado
from esperado e
full outer join real r on r.firma = e.firma
where e.huella is distinct from r.huella
order by 2, 1;

-- ============================================================================
-- SEGUNDA PARTE — ¿y los CANDADOS?
-- ----------------------------------------------------------------------------
-- Todo lo de arriba mira pg_proc y solo pg_proc. Una base puede tener las 182
-- funciones al día y haber perdido un constraint: nada se rompe, nada avisa, y
-- el daño aparece en la planilla del mes siguiente.
--
-- El caso concreto: `periodos_sin_solape` sobre periodos_planilla. Sin él, dos
-- periodos pueden compartir días y esos días se pagan DOS VECES — las dos
-- planillas salen cuadradas por separado, así que no hay descuadre que mirar.
-- Ese constraint se creó en la 0025 y `periodos_etiqueta_unica` en la 0026; si
-- alguna de las dos se saltó en producción, hasta ahora no había forma de verlo.
--
-- Se comparan TODOS los constraints de las tablas —CHECK, unicidad, exclusión,
-- clave primaria y clave foránea— más los índices únicos que no respaldan a
-- ningún constraint (periodos_etiqueta_unica es de estos: se creó con `create
-- unique index`, así que en pg_constraint no aparece).
--
-- QUÉ SIGNIFICA EL RESULTADO
--   · Sin filas        → producción tiene todos los candados, iguales.
--   · FALTA EL CANDADO → el más grave: la tabla acepta lo que debería rechazar.
--   · distinto         → existe pero protege otra cosa (revisar la definición).
--   · sobra            → hay un candado que el repositorio no conoce.
--
-- Las huellas son del texto canónico que deparsa Postgres, no del texto de la
-- migración; comparar solo tiene sentido entre bases de la misma versión mayor.
-- ============================================================================
with esperado(objeto, huella) as (values
  ('actas_descanso_sustitutorio.actas_descanso_sustitutorio_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('actas_descanso_sustitutorio.actas_descanso_sustitutorio_referencia_check','e7b53c56f713273ff966fd548efdac3a'),
  ('actas_descanso_sustitutorio.actas_descanso_sustitutorio_referencia_key','044478bb6901285bef4e66b3c0c25c60'),
  ('actas_descanso_sustitutorio.actas_descanso_sustitutorio_subida_por_fkey','4c9f25d9a111fdbcb6cbc1f323e53878'),
  ('alertas.alertas_canal_check','10f018680195e37ffa458ec1157a0f18'),
  ('alertas.alertas_estado_check','89cc99e4320552b86614a045a132c139'),
  ('alertas.alertas_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('alertas.alertas_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('alertas.alertas_tipo_check','9d355c3e381a89d0ea6048e85da7b1d0'),
  ('areas.areas_codigo_check','417f9953a829dccaf253f102ca060e32'),
  ('areas.areas_nombre_check','849be147c605276b91fc653f5015ed35'),
  ('areas.areas_pkey','cccb569f42d50ac0ef5c26ab5461ced2'),
  ('asignaciones_educacion.asignaciones_educacion_beneficiario_check','752f753bc90b8ad61a3815b6387b4177'),
  ('asignaciones_educacion.asignaciones_educacion_check','dedc3d93c88946113b43ec2628b10d0d'),
  ('asignaciones_educacion.asignaciones_educacion_cobertura_pct_check','f2b9302b770162598ed6f486eadaae34'),
  ('asignaciones_educacion.asignaciones_educacion_costo_declarado_check','abe7d6f2787b182318224a83c90f3255'),
  ('asignaciones_educacion.asignaciones_educacion_monto_check','e2ffecc5181e8825735c900ae4472bc7'),
  ('asignaciones_educacion.asignaciones_educacion_persona_id_fkey','7646047af0584a18827895fa51cf2b76'),
  ('asignaciones_educacion.asignaciones_educacion_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('asignaciones_educacion.asignaciones_educacion_registrado_por_fkey','14f0e3769c255deefd44d7ff647f6afd'),
  ('asignaciones_educacion.educacion_cobertura_es_75','cbaa84bbe7bb141d2ee07bfd84ce54a8'),
  ('asignaciones_educacion.educacion_hijo_lleva_nombre','71bb70ee957bdbc6f1d4c7bc08283815'),
  ('asignaciones_educacion.educacion_no_excede_el_comprobante','e844b0e9c324716f28563844ac93238f'),
  ('asignaciones_educacion.idx_asignaciones_educacion_unica','26671021cab5553157b1f6ddaf7d7728'),
  ('asignaciones_salario.asignacion_salario_sin_solape','01202aa5d7d000cc835ea04f8de609f0'),
  ('asignaciones_salario.asignaciones_salario_asignado_por_fkey','3cf94ce035f5c9bc9af38337b3c54990'),
  ('asignaciones_salario.asignaciones_salario_base_provision_check','27a95906e7b76fb502ac19927e2d2172'),
  ('asignaciones_salario.asignaciones_salario_check','dedc3d93c88946113b43ec2628b10d0d'),
  ('asignaciones_salario.asignaciones_salario_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('asignaciones_salario.asignaciones_salario_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('asignaciones_salario.asignaciones_salario_rango_check','cd0c84c4fce25ffdc579c73941278725'),
  ('asignaciones_salario.asignaciones_salario_salario_mensual_soles_check','815f7ed91ecb72ba86464af52d70bf74'),
  ('asignaciones_salario.idx_salario_vigente_unico','8b70caf46890126e3593dd1d961cdd40'),
  ('ausencias.ausencias_anulada_por_fkey','aab3aeb5c01ebe2a89cc3f22c4b51995'),
  ('ausencias.ausencias_aprobada_por_fkey','40cb7ab56736864777693cc4407d4e98'),
  ('ausencias.ausencias_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('ausencias.ausencias_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('ausencias.ausencias_registrada_por_fkey','13b92923efb6360c4237721805f6bba9'),
  ('ausencias.ausencias_sin_solape','5a2f3c6a844b37825a04c8ed2f81db41'),
  ('ausencias.ausencias_tipo_fkey','c0e57600d3a9ea0150ec93281012441e'),
  ('ausencias.chk_ausencia_anulacion','61e046865e8f5b6b5cbc22f0c656e6eb'),
  ('ausencias.chk_ausencia_aprobacion','30d9555ec0b369d1ec0f173e125e71ec'),
  ('ausencias.chk_ausencia_rango','e74bf7fc01865cf5a8cc03950f3bd686'),
  ('categorias_laborales.categorias_laborales_actualizado_por_fkey','94db854067f064d5b6f06a08556d655f'),
  ('categorias_laborales.categorias_laborales_orden_key','51c5f1c7fe069f4314e13daffaf67382'),
  ('categorias_laborales.categorias_laborales_pkey','9ae4ef4d22697a2f752bffb64c97c812'),
  ('categorias_laborales.categorias_laborales_salario_declarado_positivo','9acb4ce91c157a22576cb554fd0f9310'),
  ('configuracion.configuracion_pkey','24afc485589376dbdfe306825a99d611'),
  ('correcciones_auditoria.correcciones_auditoria_corregido_por_fkey','08da73998b1051a5bdf4dad5af12abbb'),
  ('correcciones_auditoria.correcciones_auditoria_marcaje_id_fkey','241bcf90a7aea4604dfb5fe5f38d1431'),
  ('correcciones_auditoria.correcciones_auditoria_motivo_check','e27a511642e8df87de76f225399b7a34'),
  ('correcciones_auditoria.correcciones_auditoria_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('correcciones_auditoria.correcciones_auditoria_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('datos_personales.datos_personales_actualizado_por_fkey','94db854067f064d5b6f06a08556d655f'),
  ('datos_personales.datos_personales_persona_id_fkey','4e4c38e173fa4f70bf634d94ac3a9c1b'),
  ('datos_personales.datos_personales_pkey','32d71b2722e7063a500470441be9a308'),
  ('derechohabientes.derechohabientes_check','718047271fa458015fde35e0cdceab97'),
  ('derechohabientes.derechohabientes_persona_id_fkey','4e4c38e173fa4f70bf634d94ac3a9c1b'),
  ('derechohabientes.derechohabientes_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('derechohabientes.derechohabientes_registrado_por_fkey','14f0e3769c255deefd44d7ff647f6afd'),
  ('derechohabientes.derechohabientes_vinculo_check','97cbe32a54702093742f7a6a65a593f6'),
  ('etiquetas_complemento.etiquetas_complemento_pkey','cccb569f42d50ac0ef5c26ab5461ced2'),
  ('expediente_adjuntos.expediente_adjuntos_documento_id_fkey','2d154a91b14cd0ee1bb4b5cacbac0901'),
  ('expediente_adjuntos.expediente_adjuntos_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('expediente_adjuntos.expediente_adjuntos_storage_path_key','0927748ee0c0c1848334f147e44534a4'),
  ('expediente_adjuntos.expediente_adjuntos_subido_por_fkey','e7f0f8bd4a275c215b2380589b12eb71'),
  ('expediente_adjuntos.expediente_adjuntos_tipo_check','e0d713a8c67bf9819b9fd345bdd33ccc'),
  ('expediente_correlativo_seq.expediente_correlativo_seq_pkey','047b1df4bacb395fd12be06b04ddc09d'),
  ('expediente_disciplinario.chk_entregado_completo','a58f925d8a679f2d8cc1d84efae0b7f5'),
  ('expediente_disciplinario.chk_firmado_completo','cc32d60c44117113ddff6293f630acc2'),
  ('expediente_disciplinario.chk_periodo','f901350abd28dcb1f54b19cc0faf67e4'),
  ('expediente_disciplinario.chk_susp_completa','a3227c74af94b8d195a482efa1eda08b'),
  ('expediente_disciplinario.expediente_disciplinario_correlativo_key','1def318f1d860621157b45d6e0d8b54e'),
  ('expediente_disciplinario.expediente_disciplinario_creado_por_fkey','13c32e43a66dbde7ce534cc835325769'),
  ('expediente_disciplinario.expediente_disciplinario_doc_previo_id_fkey','bb452303a8a249c5a179d2a1d980535d'),
  ('expediente_disciplinario.expediente_disciplinario_estado_check','9b1229ba48d80df5a3b41330a4ed62af'),
  ('expediente_disciplinario.expediente_disciplinario_firmante_id_fkey','cd8a04fab53ef6ff09ec572fb7474799'),
  ('expediente_disciplinario.expediente_disciplinario_medio_entrega_check','31b39e6dbe8adfa929cc49eba1779d71'),
  ('expediente_disciplinario.expediente_disciplinario_nivel_check','b4f5ea87670975e5231d53978dc5998b'),
  ('expediente_disciplinario.expediente_disciplinario_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('expediente_disciplinario.expediente_disciplinario_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('expediente_disciplinario.expediente_disciplinario_tipo_causal_check','36347f0871a9b336686db8c46738352f'),
  ('factores_categoria.factores_categoria_pkey','5ca64251f4ae9de447909631dc6ce869'),
  ('factores_categoria.factores_categoria_rango_fkey','412b6127d414139e89e5f64845295ae4'),
  ('feriados.feriados_nombre_check','849be147c605276b91fc653f5015ed35'),
  ('feriados.feriados_pkey','c8dca82b8c94bc4b619b555658241810'),
  ('feriados_descanso_sustitutorio.chk_dcs_acta','e2c78d2fb896ef99de3e66252341be21'),
  ('feriados_descanso_sustitutorio.chk_dcs_dias_distintos','d4528cc249b99829bf938a33278b0e28'),
  ('feriados_descanso_sustitutorio.feriados_descanso_sustitutorio_estado_check','b7ad6cf26205c3334585557d1301a409'),
  ('feriados_descanso_sustitutorio.feriados_descanso_sustitutorio_fecha_feriado_fkey','72faeffff915572dac8e6a8c6211d892'),
  ('feriados_descanso_sustitutorio.feriados_descanso_sustitutorio_otorgado_por_fkey','eb1750daf97d82ca3937bc8111552541'),
  ('feriados_descanso_sustitutorio.feriados_descanso_sustitutorio_persona_id_fkey','4e4c38e173fa4f70bf634d94ac3a9c1b'),
  ('feriados_descanso_sustitutorio.feriados_descanso_sustitutorio_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('feriados_descanso_sustitutorio.uq_dcs_descanso','ea140328fbb9a1dae94dd1cbcd2051e7'),
  ('feriados_descanso_sustitutorio.uq_dcs_feriado','c1ea7beb8c0c8298ae3da580e72d4929'),
  ('firmas_escaneadas.chk_firma_es_imagen','12c86aa368af310f1c8076e2cc6b4d68'),
  ('firmas_escaneadas.chk_firma_peso','7e2294e5bf82239a8e85a677d62d2272'),
  ('firmas_escaneadas.firmas_escaneadas_persona_id_fkey','4e4c38e173fa4f70bf634d94ac3a9c1b'),
  ('firmas_escaneadas.firmas_escaneadas_pkey','32d71b2722e7063a500470441be9a308'),
  ('funciones_nunca_para_authenticated.funciones_nunca_para_authenticated_pkey','78d4b2bac8a6ec38c64fb7b537bbbb60'),
  ('google_sheets_sync_queue.google_sheets_sync_queue_estado_check','a1c2c87a0b7e058a1a58212f334afe58'),
  ('google_sheets_sync_queue.google_sheets_sync_queue_jornada_id_fkey','c9301848bf78f8fb428a6de10750e6c1'),
  ('google_sheets_sync_queue.google_sheets_sync_queue_marcaje_id_fkey','88003f03e14dc904e641b0922924be9b'),
  ('google_sheets_sync_queue.google_sheets_sync_queue_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('horarios_asignados.horarios_asignados_check','dedc3d93c88946113b43ec2628b10d0d'),
  ('horarios_asignados.horarios_asignados_check1','a7e0de34661a96c1b56fcf25f47cf529'),
  ('horarios_asignados.horarios_asignados_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('horarios_asignados.horarios_asignados_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('horarios_asignados.idx_horario_vigente_unico','de131467769a743585135f8e69910aac'),
  ('incidencias_aceptadas.incidencias_aceptadas_aceptado_por_fkey','73276168bbbcd63dc455ee29a16ce5f1'),
  ('incidencias_aceptadas.incidencias_aceptadas_persona_id_fecha_tipo_key','c869d481864b7c8fcc7292413e259b2b'),
  ('incidencias_aceptadas.incidencias_aceptadas_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('incidencias_aceptadas.incidencias_aceptadas_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('jornadas.chk_horas_no_negativas','8d4d9bbf3834887fbc12ed192f0bb16c'),
  ('jornadas.jornadas_persona_id_fecha_key','e110093313b5d08a5585d221aecb5eab'),
  ('jornadas.jornadas_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('jornadas.jornadas_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('jornadas.jornadas_sede_id_fkey','1b80ffdf5e25a53c8e1e1c4505c92bd6'),
  ('marcajes.chk_anulacion_completa','30bf0d5455e9331cfaf1470d0b3e0add'),
  ('marcajes.marcajes_anulada_por_fkey','aab3aeb5c01ebe2a89cc3f22c4b51995'),
  ('marcajes.marcajes_check','5be7793a01fc8c803c0032bc1164efd4'),
  ('marcajes.marcajes_client_uuid_key','017ac692e85e239dac1a7d1ac88c1619'),
  ('marcajes.marcajes_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('marcajes.marcajes_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('marcajes.marcajes_sede_id_fkey','1b80ffdf5e25a53c8e1e1c4505c92bd6'),
  ('marcajes.marcajes_terminal_id_fkey','07522e0386398dfec7fa0fed1cd1d832'),
  ('metas_cobertura.metas_cobertura_dia_semana_check','99f1206bbe57dea60c2189a19c103a96'),
  ('metas_cobertura.metas_cobertura_meta_check','80c9a9f9f4fe9a7ff0a6f0e7f5076db7'),
  ('metas_cobertura.metas_cobertura_meta_encargadas_check','49afbffe6157f1c374c271cc1185302a'),
  ('metas_cobertura.metas_cobertura_meta_tarde_check','bdff0f17753c1d8d546cccd6612855d1'),
  ('metas_cobertura.metas_cobertura_pkey','7e338e81c8d9c4b6bc059b8db33b1cba'),
  ('metas_cobertura.metas_cobertura_sede_id_fkey','1b80ffdf5e25a53c8e1e1c4505c92bd6'),
  ('migraciones_aplicadas.migraciones_aplicadas_pkey','762cb1a31512b3ef03f3eda9da7552c6'),
  ('movimientos_planilla.movimientos_categoria_valida','b6481db54c531617c2e98e49e77b7e34'),
  ('movimientos_planilla.movimientos_planilla_concepto_check','0f54cb30aa6f549eaa02782370c88b92'),
  ('movimientos_planilla.movimientos_planilla_creado_por_fkey','13c32e43a66dbde7ce534cc835325769'),
  ('movimientos_planilla.movimientos_planilla_monto_check','091e0278f47e675ce0301dece9444634'),
  ('movimientos_planilla.movimientos_planilla_periodo_id_fkey','300920d107dea6e237e9dfdd124896ca'),
  ('movimientos_planilla.movimientos_planilla_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('movimientos_planilla.movimientos_planilla_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('movimientos_planilla.movimientos_planilla_tipo_check','6cee2b117089457329b0d0af9e33f967'),
  ('objetivos_items.objetivos_items_anio_check','dcee967f882bb6590e0d8f04722c9898'),
  ('objetivos_items.objetivos_items_descripcion_check','652262c72f3a92fcfa6f3a64c054b45e'),
  ('objetivos_items.objetivos_items_mes_check','cd117f9e1948c999f1bf8fb821a635f0'),
  ('objetivos_items.objetivos_items_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('objetivos_items.objetivos_items_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('objetivos_mensuales.objetivos_mensuales_anio_check','dcee967f882bb6590e0d8f04722c9898'),
  ('objetivos_mensuales.objetivos_mensuales_check','696dd7b47485c45f711b057cc26b57e7'),
  ('objetivos_mensuales.objetivos_mensuales_cumplidos_check','d9be119ab05c05ee5fc70fdb9cba6fa5'),
  ('objetivos_mensuales.objetivos_mensuales_mes_check','cd117f9e1948c999f1bf8fb821a635f0'),
  ('objetivos_mensuales.objetivos_mensuales_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('objetivos_mensuales.objetivos_mensuales_pkey','09e3ca5f2e9ea45580f650b241d48c81'),
  ('objetivos_mensuales.objetivos_mensuales_total_check','37728aa83e3fa24523fdb37cc0d285c9'),
  ('parametros_laborales.idx_parametros_laborales_unica_por_sede','f58433b12ef80a110096a9e11fb4ad27'),
  ('parametros_laborales.parametros_laborales_check','dedc3d93c88946113b43ec2628b10d0d'),
  ('parametros_laborales.parametros_laborales_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('parametros_laborales.parametros_laborales_valor_check','19c7706269e5d552fbabcf30d3646f03'),
  ('periodos_planilla.periodos_etiqueta_unica','4e033d2e992995e2638c0336f5f776d9'),
  ('periodos_planilla.periodos_planilla_check','e53d038ac59481b8175ddc3eb72e9947'),
  ('periodos_planilla.periodos_planilla_creado_por_fkey','13c32e43a66dbde7ce534cc835325769'),
  ('periodos_planilla.periodos_planilla_estado_check','19f3b29752b7cddb53348be5de8c3338'),
  ('periodos_planilla.periodos_planilla_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('periodos_planilla.periodos_sin_solape','82bccaebfa1caf9b6701e4f166a3c65a'),
  ('personas.idx_personas_documento_unico','fd3c4feebeb1f22c7fe197f0cc75d6e9'),
  ('personas.personas_auth_user_id_fkey','f91277b3e8169a1b117532ba0a21d069'),
  ('personas.personas_auth_user_id_key','3939596b6b0eb0c3a60cbfda6e98ad0c'),
  ('personas.personas_cese_coherente','0de7893d1b7bb5cdfeff8e75d41e3937'),
  ('personas.personas_email_key','cb128631a72269d9e93b234b2814eb06'),
  ('personas.personas_estado_check','a86c8c197717eb736bbed1737c550dc0'),
  ('personas.personas_fin_contrato_coherente','5d6538abd187ac1e8459719f4f0e627d'),
  ('personas.personas_funcion_fk','38182bf7a91b167eef620ad98158e563'),
  ('personas.personas_motivo_cese_valido','7560c8a0cc2c372bd871db0561eacaec'),
  ('personas.personas_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('personas.personas_regimen_pension_valido','70ea431a97d69fb7ba8e1b26127c1700'),
  ('personas.personas_sede_base_id_fkey','a823b37b2fc2f08d8c9b46a3e547f0ea'),
  ('personas.personas_sueldo_base_legal_positivo','396db465e57043dfb98b0c497856a8e3'),
  ('personas.personas_tipo_vinculo_valido','fd2bdfaafcea3d7e5279772e268d6195'),
  ('planilla_pagada_detalle.chk_foto_cuadra','9a7c8c286494b9728bc8d38df2648ae3'),
  ('planilla_pagada_detalle.planilla_pagada_detalle_congelada_por_fkey','ebf2ae660b1a451b3a90a006ff01da77'),
  ('planilla_pagada_detalle.planilla_pagada_detalle_dias_trabajados_check','8c41df152e6354d20dbaec4ab083aa57'),
  ('planilla_pagada_detalle.planilla_pagada_detalle_horas_mes_check','164af8af5294d58490aa1e097c18cda2'),
  ('planilla_pagada_detalle.planilla_pagada_detalle_origen_check','1c72dd81244874cfeb1b5deb04741ef8'),
  ('planilla_pagada_detalle.planilla_pagada_detalle_periodo_id_fkey','0a902aec03694b023eda9c99cd7059bc'),
  ('planilla_pagada_detalle.planilla_pagada_detalle_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('planilla_pagada_detalle.planilla_pagada_detalle_pkey','6f3a8f11e4fb1be79fb489c2ded26961'),
  ('planilla_pagada_detalle.planilla_pagada_detalle_version_check','3e5843bf80ef107834bb748fbe091642'),
  ('politica_salarial.politica_salarial_documento_check','89dd750a0be307d42c89aba866141c75'),
  ('politica_salarial.politica_salarial_pkey','c820ea89255a83223217f1d7da6de5eb'),
  ('politica_salarial.politica_salarial_publicada_por_fkey','3b94b67bb051f16dfab905236838ec8d'),
  ('politica_salarial_acuses.politica_salarial_acuses_nombre_declarado_check','6410e348ccb5f0976f229933302bbaa9'),
  ('politica_salarial_acuses.politica_salarial_acuses_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('politica_salarial_acuses.politica_salarial_acuses_pkey','6e4b2c1ba491fc1b8efc3c7e349dd9e1'),
  ('politica_salarial_acuses.politica_salarial_acuses_version_fkey','782ea2a6927d9396227b011202896a36'),
  ('push_tokens.push_tokens_persona_id_expo_push_token_key','e86710c5b5569a4a25c9c2b356ba4430'),
  ('push_tokens.push_tokens_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('push_tokens.push_tokens_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('push_tokens.push_tokens_plataforma_check','b8a913d87aa7bd8cc2f7e0bc89a10b07'),
  ('rendimiento_mensual.rendimiento_mensual_etiqueta_codigo_fkey','7842a1bc96e075787aa45b1d9de16828'),
  ('rendimiento_mensual.rendimiento_mensual_mes_check','cd117f9e1948c999f1bf8fb821a635f0'),
  ('rendimiento_mensual.rendimiento_mensual_persona_id_fkey','4e4c38e173fa4f70bf634d94ac3a9c1b'),
  ('rendimiento_mensual.rendimiento_mensual_pkey','09e3ca5f2e9ea45580f650b241d48c81'),
  ('rendimiento_mensual.rendimiento_mensual_porcentaje_check','204ba4582dd0e763c16bbd915e2afe6b'),
  ('rendimiento_mensual.rendimiento_mensual_puesto_por_fkey','76347bff83982e4ebfa99a57c84eaff7'),
  ('reversas_pago.chk_reversa_tipo','297ca01e21cb87fd7834555b20e0fd9b'),
  ('reversas_pago.reversas_pago_periodo_id_fkey','300920d107dea6e237e9dfdd124896ca'),
  ('reversas_pago.reversas_pago_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('reversas_pago.reversas_pago_revertido_por_fkey','76d130691831ae83cb9597e6fb2f99c2'),
  ('sedes.chk_sede_tipo','29aafb335e214fc9ed3b3e4e61c9a6b7'),
  ('sedes.sedes_codigo_formato','0aef0e2978cd82013de57a60faa02be0'),
  ('sedes.sedes_codigo_key','71cd40930c291836ca3b6a0bcdcbee56'),
  ('sedes.sedes_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('tardanzas_justificadas.tardanzas_justificadas_creado_por_fkey','13c32e43a66dbde7ce534cc835325769'),
  ('tardanzas_justificadas.tardanzas_justificadas_motivo_check','187a8c6b3bfebc3db740bfe0f92d8ea2'),
  ('tardanzas_justificadas.tardanzas_justificadas_persona_id_fecha_key','e110093313b5d08a5585d221aecb5eab'),
  ('tardanzas_justificadas.tardanzas_justificadas_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('tardanzas_justificadas.tardanzas_justificadas_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('tarifas_hora.idx_tarifa_vigente_unica','6a799bece17d1f1998764991b4891531'),
  ('tarifas_hora.tarifas_hora_check','dedc3d93c88946113b43ec2628b10d0d'),
  ('tarifas_hora.tarifas_hora_creado_por_fkey','13c32e43a66dbde7ce534cc835325769'),
  ('tarifas_hora.tarifas_hora_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('tarifas_hora.tarifas_hora_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('tarifas_hora.tarifas_hora_tarifa_hora_soles_check','6b1faaf56fed249e0525f459f64fb60d'),
  ('tasas_pension.idx_tasas_pension_vigente_unica','0384247c1f8dde20795660d246b0af0a'),
  ('tasas_pension.tasas_pension_aporte_check','bc465663ddc036854b79d701d99a3689'),
  ('tasas_pension.tasas_pension_check','dedc3d93c88946113b43ec2628b10d0d'),
  ('tasas_pension.tasas_pension_comision_check','aeb9045d6733d339d7c70629f40c02d2'),
  ('tasas_pension.tasas_pension_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('tasas_pension.tasas_pension_prima_check','18baf466d9124a8b812e0f4267167761'),
  ('terminales.terminales_auth_user_id_fkey','f91277b3e8169a1b117532ba0a21d069'),
  ('terminales.terminales_auth_user_id_key','3939596b6b0eb0c3a60cbfda6e98ad0c'),
  ('terminales.terminales_pkey','4c6419b3704337bbfe50f018842a9ad3'),
  ('terminales.terminales_sede_id_fkey','1b80ffdf5e25a53c8e1e1c4505c92bd6'),
  ('tipos_ausencia.tipos_ausencia_codigo_check','f8de4afa885d214f7973e1898003e997'),
  ('tipos_ausencia.tipos_ausencia_nombre_check','65431cde9aa3a02fb92d902c04f57596'),
  ('tipos_ausencia.tipos_ausencia_pkey','cccb569f42d50ac0ef5c26ab5461ced2'),
  ('topes_educacion_rango.topes_educacion_rango_pkey','9ae4ef4d22697a2f752bffb64c97c812'),
  ('topes_educacion_rango.topes_educacion_rango_rango_check','cd0c84c4fce25ffdc579c73941278725'),
  ('topes_educacion_rango.topes_educacion_rango_tope_mensual_check','83a3de472626d34ab84d1a44d094e045'),
  ('turnos.turnos_entrada_o_descanso','9e60d2ed8ded0ccf034f0403ad5ab11f'),
  ('turnos.turnos_persona_id_fecha_key','e110093313b5d08a5585d221aecb5eab'),
  ('turnos.turnos_persona_id_fkey','c2ecc9319269960c1e7ce5f23bf9d02e'),
  ('turnos.turnos_pkey','4c6419b3704337bbfe50f018842a9ad3')
),
real as (
  select objeto, md5(definicion) as huella
  from (
    select c.relname || '.' || con.conname as objeto,
           pg_get_constraintdef(con.oid) as definicion
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      -- Los CINCO tipos, no dos. Hasta el 2026-08-05 esto decía `in ('x','u')`
      -- y miraba 19 candados de 234: quedaban fuera los 98 CHECK, los 47
      -- PRIMARY KEY y los 70 FOREIGN KEY. Los CHECK son justo donde vive la
      -- regla de negocio de este sistema —«una persona inactiva tiene fecha de
      -- cese», «las horas no son negativas», «un memo firmado tiene
      -- correlativo»— y perder uno no rompe nada: la tabla empieza a aceptar
      -- lo que antes rechazaba, y se nota meses después en una planilla.
      and con.contype in ('x', 'u', 'c', 'p', 'f')

    union all

    select c.relname || '.' || ix.relname,
           pg_get_indexdef(i.indexrelid)
    from pg_index i
    join pg_class c on c.oid = i.indrelid
    join pg_class ix on ix.oid = i.indexrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and i.indisunique
      and not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid)
  ) t
)
select coalesce(e.objeto, r.objeto) as candado,
       case when r.objeto is null then 'FALTA EL CANDADO en produccion'
            when e.objeto is null then 'sobra en produccion (no esta en el repo)'
            else 'distinto (protege otra cosa)' end as estado
from esperado e
full outer join real r on r.objeto = e.objeto
where e.huella is distinct from r.huella
order by 2, 1;
