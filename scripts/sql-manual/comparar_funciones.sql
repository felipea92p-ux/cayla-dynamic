-- ============================================================================
-- comparar_funciones.sql — ¿qué le falta a producción?
-- ----------------------------------------------------------------------------
-- SOLO LEE. No modifica nada. Se puede correr las veces que haga falta.
--
-- Compara el texto de cada función `fn_*` de producción contra el de una base
-- construida desde cero con las 101 migraciones del repositorio en orden.
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
  ('fn_rol_actual()','74a308165b3da1e740a21e199bde1c36'),
  ('fn_persona_actual_id()','e2638cb6bced205433c784da592d7d27'),
  ('fn_set_updated_at()','1c4318bee4240d4113d86fad7eb15623'),
  ('fn_es_admin_o_lider()','77c2b4dbc2e00ed06cf048f830ef3efb'),
  ('fn_trg_marcajes_recalcular_jornada()','8686363919f2c4c53c4ca3691cba6c9e'),
  ('fn_trg_marcajes_delete_recalcular()','f1d6f346114f4de6d46d4799c6ae1e08'),
  ('fn_verificar_corrector(p_persona_objetivo uuid)','1ca3cb77fdcfddd25ea7ef31ff0eab6e'),
  ('fn_quitar_horario(p_persona_id uuid, p_desde date)','8dfc686df1a2944393320497a92c6d76'),
  ('fn_recalcular_jornada(p_persona_id uuid, p_fecha date)','725d20d0935e4507a9301ff9f9ce11fd'),
  ('fn_salarios_vigentes()','92dd2c78d79eccfa386f147fafd4cf02'),
  ('fn_guardar_area(p_codigo text, p_nombre text, p_operativa boolean, p_orden integer)','a78673d2790695b5c6f6a5d81165d2d9'),
  ('fn_areas()','ae59345d674045259d98a04fd5900f80'),
  ('fn_crear_persona(p_nombres text, p_apellidos text, p_sede_base_id uuid, p_rol text, p_funcion text, p_email text, p_pin_hash text)','b74c3530652abb56c9bc97101e4512d0'),
  ('fn_feriados(p_anio integer)','1602210d11beebeaf2a3d55f96228a43'),
  ('fn_puede_gestionar_objetivos(p_persona_id uuid)','ff2987757cfad220e27b5029427befca'),
  ('fn_provisiones(p_as_of date)','d7a580e4d6a7f3bfce9ba4ea7419b901'),
  ('fn_mes_planilla_pagado(p_anio integer, p_mes integer)','fe4b0e0f798a6d65393f3017ed5363ef'),
  ('fn_set_mi_firma(p_dataurl text)','240e266ee4732ddfecc029c3182c1ed2'),
  ('fn_proyeccion_planilla(p_anio integer, p_mes integer)','cac0cb1099283cc4c3c327783c76c369'),
  ('fn_eliminar_periodo(p_periodo_id uuid)','14acc43cf164ba17e9e7e6cf0f7dc228'),
  ('fn_planilla_calcular(p_ini date, p_fin date, p_periodo_id uuid)','e827bfeff70fd273356f89a986ad65bf'),
  ('fn_objetivos_checklist(p_anio integer, p_mes integer, p_persona_id uuid)','fea63da0b5964eb738907a26df3907c5'),
  ('fn_set_descanso(p_persona_id uuid, p_fecha date)','b5d0a2bfb5ee709e73ff3f8d18e3a200'),
  ('fn_quitar_turno(p_persona_id uuid, p_fecha date)','c0f7d21aba09ad6621148ee9945b42d5'),
  ('fn_calcular_bono_puntualidad(p_periodo_id uuid)','00996c51302e4e3ec098179c308a5a77'),
  ('fn_historial_salario(p_persona_id uuid)','2cae9314ec12264e1267d7ca6ac87bba'),
  ('fn_agregar_movimiento(p_periodo_id uuid, p_persona_id uuid, p_tipo text, p_concepto text, p_monto numeric, p_categoria text)','7d33eff44024a852567e80906bd2c160'),
  ('fn_grati_cts_periodo(p_periodo_id uuid)','0bc70f11dd23ede89441e11486d58d70'),
  ('fn_set_funcion(p_persona_id uuid, p_funcion text)','22cae06af36f3158eda775de5f635c50'),
  ('fn_firma_persona(p_persona_id uuid)','ae3af62d8f1e88f5e86438f7d0605f39'),
  ('fn_levantar_tardanza(p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text)','55ab73386b32c9932df0c7c953109a00'),
  ('fn_personas_funciones()','2f0e02999aa1c77448eb06c0fd39fca8'),
  ('fn_area_activa(p_codigo text, p_activa boolean)','5e472c9a6ba2894dae59dbc32ff427c7'),
  ('fn_agregar_movimiento(p_periodo_id uuid, p_persona_id uuid, p_tipo text, p_concepto text, p_monto numeric)','ee67c18902ee72c36366505e3218886c'),
  ('fn_set_visible_todas_sedes(p_persona_id uuid, p_valor boolean)','b5dc7eed73e7d886ef35131d5fda331b'),
  ('fn_dcs_validar_dia_laborable()','5de3db54781a6d67fa9b94905667f95c'),
  ('fn_periodo_pagado(p_periodo_id uuid, p_pagado boolean)','ba09a250d6496084f093dccb2bd9108b'),
  ('fn_quitar_levantamiento(p_persona_id uuid, p_fecha date)','df8917240242b38797bd94ff5877c0bb'),
  ('fn_eliminar_marcaje(p_marcaje_id uuid, p_motivo text)','838b05b1bac115d28b86ea0df0ee33e4'),
  ('fn_registrar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_timestamp_cliente timestamp with time zone, p_client_uuid uuid, p_origen origen_marca, p_terminal_id uuid, p_sede_id uuid, p_motivo_otro text)','5a477b781d4dbbc639b8621ba8b3c7be'),
  ('fn_corregir_marcaje(p_marcaje_id uuid, p_nuevo_ts timestamp with time zone, p_motivo text)','12353fd8c20e09b58c2c3f89bc19ab97'),
  ('fn_quitar_feriado(p_fecha date)','78c1592506fa7abe332bcbb7c9e06f49'),
  ('fn_sede_actual_persona()','fd2b6fe2563a26f358cd898647bc71c1'),
  ('fn_sede_actual_terminal()','a87b7ee707624305643e0973dba4e978'),
  ('fn_exigir_admin()','7bcd0acc91afecc3d41c2212611b60af'),
  ('fn_agregar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_ts timestamp with time zone, p_motivo text, p_motivo_otro text)','6ac4844a5b71ac50693d60f660b8a5b3'),
  ('fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana integer, p_meta integer)','6a778324d37b3bb992f553fb8a1c8324'),
  ('fn_set_turno(p_persona_id uuid, p_fecha date, p_hora_entrada time without time zone, p_hora_salida time without time zone)','af2b07ee7a0701e8b2603d20fb413f5b'),
  ('fn_set_horario(p_persona_id uuid, p_hora_entrada time without time zone, p_hora_salida time without time zone, p_vigente_desde date, p_almuerzo_min integer, p_almuerzo_max integer, p_dias_laborables integer[])','18e285ca89e6f341909deb7a1392fbe8'),
  ('fn_set_horario_semanal(p_persona_id uuid, p_vigente_desde date, p_horario jsonb)','68790773c6b7e54830e02ecbdec540bf'),
  ('fn_jornadas_extra(p_desde date, p_hasta date, p_persona_id uuid)','73f003e983cf317867e9d8f5a273879d'),
  ('fn_expediente_puede_actuar(p_persona_id uuid, p_nivel text)','9364c2070cd8e6b7d839093c8ac3ec4b'),
  ('fn_quitar_movimiento(p_movimiento_id uuid)','6acec517707973b4e7c7461c8678ce28'),
  ('fn_set_con_hijos(p_persona_id uuid, p_con_hijos boolean)','a5a5f35e8bedd9f128b2b92c05d0e1ff'),
  ('fn_set_feriado(p_fecha date, p_nombre text)','719d2dc02f9408322518c4b116d5775a'),
  ('fn_periodos()','e56f3b3c15ae8dd4d702d0dd13b63be1'),
  ('fn_objetivos_sync_mes(p_persona_id uuid, p_anio integer, p_mes integer)','fa33e9e21044daabec1586bd4b544a65'),
  ('fn_crear_periodo(p_fecha_fin date, p_fecha_ini date)','c2f7ac69eb357d742fcbd30e3be063a9'),
  ('fn_proyeccion_periodo(p_periodo_id uuid)','fad72eefc30b5b2de9dd81460cf87dd9'),
  ('fn_ingresos()','66c1c7d709719f25e1b8e9fb7f1780bf'),
  ('fn_simular_planilla(p_ini date, p_fin date)','a4d5b292e6d51f4ce9f034e3890b99ff'),
  ('fn_set_fecha_ingreso(p_persona_id uuid, p_fecha date)','5f4a4aa7cdf3a16a53e1c42017e23108'),
  ('fn_objetivos_resumen(p_anio integer, p_mes integer)','de85e39f25c4e9873625b06dfa99962b'),
  ('fn_objetivo_agregar(p_persona_id uuid, p_anio integer, p_mes integer, p_descripcion text)','f0f66c3da8248b752dd26a32a763fb69'),
  ('fn_objetivo_marcar(p_item_id uuid, p_cumplido boolean)','ea9efea843c782d9e0e5118df5707aa5'),
  ('fn_objetivo_eliminar(p_item_id uuid)','8831f1382677f2a7741824161a226504'),
  ('fn_objetivo_editar(p_item_id uuid, p_descripcion text)','81143dec842bdd957d9eeda7609b2d1e'),
  ('fn_dia_suspendido(p_persona_id uuid, p_fecha date)','e1fe46d889b2906a38d1b97ec8da0da8'),
  ('fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana integer, p_meta_manana integer, p_meta_tarde integer)','0dcf75bcebed1493c6007ade98df2afb'),
  ('fn_set_objetivos(p_persona_id uuid, p_anio integer, p_mes integer, p_cumplidos integer, p_total integer)','f1862b8bf206d2983df6a7b2e5f2750d'),
  ('fn_auto_cierre()','a8c6fd980082ba54e7705abb89181f51'),
  ('fn_set_salario(p_persona_id uuid, p_rango text, p_salario numeric, p_vigente_desde date, p_nota text)','55f844f6a6268b4f7051aa25a0103c9c'),
  ('fn_set_meta_encargadas(p_sede_id uuid, p_dia_semana integer, p_meta integer)','dd079847713710280c0aa46439ad1903'),
  ('fn_set_encargada_piso(p_persona_id uuid, p_valor boolean)','51fc254417cd7e7f0f394b573432afcc'),
  ('fn_set_vacaciones(p_persona_id uuid, p_fecha_inicio date, p_fecha_fin date, p_observacion text)','14f66ca1723609ec1bdec5359844e8e4'),
  ('fn_quitar_vacaciones(p_id uuid)','d3d46e1c03adf5fdd8c44e84fa5ffc4b'),
  ('fn_sede_activa(p_codigo text, p_activa boolean)','bef707ff91fd487b3411c57016dc715d'),
  ('fn_vacaciones_resumen(p_as_of date)','9d15efaec6147c3fbd1357ec7e7020d4'),
  ('fn_set_justificacion(p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text)','cfc9b3387206ed565b0e5381364f060d'),
  ('fn_quitar_justificacion(p_persona_id uuid, p_fecha date)','c7fdf49a99bfa1659aae06b88c377ea6'),
  ('fn_faltas(p_desde date, p_hasta date)','8887c5d18d8893bdf5b6383afdf1ff40'),
  ('fn_aceptar_incidencia(p_persona_id uuid, p_fecha date, p_tipo text, p_nota text)','555ebacee3040e94f6a139e648919824'),
  ('fn_quitar_aceptacion(p_persona_id uuid, p_fecha date, p_tipo text)','44da7f2c66b272d34aa79553f981026f'),
  ('fn_expediente_correlativo(p_prefijo text)','80bc6bce2a95165c203371f5bf6bdd19'),
  ('fn_expediente_doc_code(p_tipo text, p_nivel text)','972ff7808ba22e266c707ba9eaac743b'),
  ('fn_expediente_crear_borrador(p_persona_id uuid, p_tipo_causal text, p_nivel text, p_hechos jsonb, p_periodo_desde date, p_periodo_hasta date, p_doc_previo_id uuid, p_suspension_dias integer, p_suspension_desde date, p_suspension_hasta date, p_observacion text)','aa4f18d662ada729252406e718c77ac8'),
  ('fn_expediente_entregar(p_id uuid, p_medio text, p_fecha timestamp with time zone)','860001cc15a127e2d305539ad09c23a6'),
  ('fn_expediente_anular(p_id uuid, p_motivo text)','e5029b8f389a0a10d3947a204b1f9c1b'),
  ('fn_expediente_editar_borrador(p_id uuid, p_suspension_dias integer, p_suspension_desde date, p_suspension_hasta date, p_observacion text, p_hechos jsonb)','eac45387c58102ba404b6ba275345031'),
  ('fn_expediente_generar_tardanza(p_persona_id uuid)','c903afab5449965c45d055fcd27c1d39'),
  ('fn_revertir_pago(p_periodo_id uuid, p_motivo text)','05d12836850e6fb9a5745ff661a1f23a'),
  ('fn_expediente_generar_falta(p_persona_id uuid)','de232c1bddeb768e2f67f3894db8bd22'),
  ('fn_tardanzas_resumen(p_as_of date)','6eaceebecae9e7f5849aa1e1bb98067e'),
  ('fn_faltas_resumen(p_as_of date)','908b5225767289bef9adf3c6172f08b4'),
  ('fn_otorgar_descanso_sustitutorio(p_persona_id uuid, p_fecha_feriado date, p_fecha_descanso date, p_estado text, p_acta_ref text)','1cd1f6ac80ed669dd5a6e6c11db8cfc6'),
  ('fn_firmantes_disponibles()','4247b15f0763441dde3089d0029c6923'),
  ('fn_expediente_puede_adjuntar(p_path text)','82c7454151e1424de088dadd4a3119a5'),
  ('fn_quitar_descanso_sustitutorio(p_id uuid)','c8eb8b7854aab7536ddf0cefc40f02a0'),
  ('fn_expediente_firmar(p_id uuid, p_firmante_id uuid)','adde09b0a8dc8a390eaabbd1929604a7'),
  ('fn_aprobar_ausencia(p_id uuid)','e10c71925cd60498dcc45a4add2d61be'),
  ('fn_feriados_laborados(p_desde date, p_hasta date)','d2da31c15e5a245aa6df0a2ec0762b4f'),
  ('fn_actas_descanso()','0839c9738daecd37a3321f96d08bf175'),
  ('fn_subir_acta_descanso(p_referencia text, p_dataurl text, p_nombre text)','1f5dadf29e4bbb286a52add371f6d0a7'),
  ('fn_acta_descanso(p_referencia text)','7006e0241fd1ab8b4a1a4fce97881bcd'),
  ('fn_cargo_de_rol(p_rol rol_usuario)','c148dd8c134ba137925f21c41dce1ca2'),
  ('fn_expediente_adjuntar(p_documento_id uuid, p_path text, p_tipo text, p_fecha_entrega timestamp with time zone, p_nota text)','e393b325e6c47d8f87119fd1f7418706'),
  ('fn_es_dia_laborable(p_persona_id uuid, p_fecha date)','e266f4286a38e57dcef1bd3db6471b4a'),
  ('fn_dias_suspension(p_persona_id uuid, p_desde date, p_dias integer)','4db223a7178ee0e68a3d85bfa042d0b9'),
  ('fn_expediente_set_suspension(p_id uuid, p_dias integer, p_desde date)','96f32dbd2ff1c41da38765ef1ec5bbf6'),
  ('fn_mi_firma()','6888305c9fd04e2aa6f48865dac2d83e'),
  ('fn_firma_de_memo(p_doc_id uuid)','0fbf7b2a6f0e721125415a024b05125c'),
  ('fn_expediente_firmantes(p_id uuid)','9ec82c60f3d5c92e6bdeeb7f3d695c19'),
  ('fn_set_datos_personales(p_persona_id uuid, p_nombre_dni text, p_fecha_nacimiento date, p_estado_civil text, p_direccion text, p_celular text, p_entidad_bancaria text, p_numero_cuenta text, p_grado_instruccion text, p_hijos_menores boolean, p_foto_dni_url text, p_foto_personal_url text, p_foto_profesional_url text)','d9b173ef511fe534eff9fc94d695497e'),
  ('fn_feriados_cobertura()','a790e743a6548a8b66cfe3f676c5c467'),
  ('fn_familia_marca(p_tipo tipo_marca)','5c1c6168f2f8a2273a8ec1cc00fda20c'),
  ('fn_corregir_marca(p_marcaje_id uuid, p_nuevo_tipo tipo_marca, p_nuevo_ts timestamp with time zone, p_motivo text)','1ef15c4480eea7f095b505d92aa5f598'),
  ('fn_siguiente_tipo_esperado(p_persona_id uuid, p_fecha date)','83d209b8bda41ff89e26fea7277e14d1'),
  ('fn_repagar_periodo(p_periodo_id uuid, p_motivo text)','ae86e4e9204325dec278ff2617083bb0'),
  ('fn_dias_por_revisar(p_limite integer)','8d17f437a3a134413f03092b6f4f875f'),
  ('fn_dia_incoherente(p_persona_id uuid, p_fecha date)','e76cd69c17717e50498c3e89f93ffe96'),
  ('fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)','0d2fc7ac6ba6d79ddfe94aa600d65654'),
  ('fn_levantar_sello_si_el_dia_cuadra(p_persona_id uuid, p_fecha date)','cd483362942e8747ad01037a6740c60e'),
  ('fn_planilla_congelar(p_periodo_id uuid, p_origen text, p_autor uuid)','3ef6a55f0b4d70ebc4f9cb7572d4a939'),
  ('fn_devenga_beneficios(p_tipo text)','5c99fb45d0b40ad82a11ed85a65f03d9'),
  ('fn_planilla_foto_diferencias(p_periodo_id uuid)','3ab4453288cc6779621ac816be200575'),
  ('fn_cesar_persona(p_persona_id uuid, p_fecha_cese date, p_motivo text, p_tipo_vinculo text)','da76f971ded2d7c4f91fff2f82c403b2'),
  ('fn_reactivar_persona(p_persona_id uuid)','b0fd63db156a1a20219e3c0d2df5abf8'),
  ('fn_planilla_congelar_pendientes()','433bebcadda139cfb3a723e269f9b0b6'),
  ('fn_marcaje_no_posterior_al_cese()','7b69d46ed6f9139095293bc82463fefd'),
  ('fn_meses_y_dias(p_desde date, p_hasta date)','3ec471defb94971909962762b2f7f3aa'),
  ('fn_remuneracion_computable(p_persona_id uuid, p_fecha_ref date)','f7d21e13a70efa3965c8362ef0eac934'),
  ('fn_grati_trunca(p_persona_id uuid, p_fecha_cese date)','ef453848206b7fb1cdc394a33571edcb'),
  ('fn_cts_trunca(p_persona_id uuid, p_fecha_cese date)','cec45b4dde4d3f6e7e5abc45a076ab5e'),
  ('fn_vacaciones_truncas(p_persona_id uuid, p_fecha_cese date)','ab17762b22fb34c67f557c7aba56226b'),
  ('fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)','fca64b89294b950ad0e2d2c782a144fc'),
  ('fn_confirmar_auto_cierre(p_marcaje_id uuid, p_motivo text)','bb55fc2a3ef9f63af0f5edcbd1e154be'),
  ('fn_hoy_lima()','e87871ddf03a82da311265290ba2060c'),
  ('fn_falta_contadores(p_persona_id uuid, p_desde date)','87f843f521cab2245ca07d887c7f68c0'),
  ('fn_trg_foto_es_inmutable()','3d8fff6c913de4ad1b4b57743bc20b9b'),
  ('fn_costos_planilla(p_desde date, p_hasta date)','2e960fc4db713c4fc4dad10f6c42a67b'),
  ('fn_trg_vacaciones_insert()','ab3c278607fcaf60b1aa4c589bffc107'),
  ('fn_guardar_sede(p_codigo text, p_nombre text, p_tipo text)','b83590a169a115d07c5ab36c156aaf9e'),
  ('fn_trg_justificaciones_insert()','68df6b672b3548ec72075464458afcf7'),
  ('fn_registrar_ausencia(p_persona_id uuid, p_tipo text, p_fecha_inicio date, p_fecha_fin date, p_motivo text, p_doc_profesional text, p_doc_colegiatura text, p_doc_fecha date)','b6251b8b32f76e51749a51d68821ed01'),
  ('fn_anular_ausencia(p_id uuid, p_motivo text)','5250204856581f5306fdbe9666df0870'),
  ('fn_ausencias(p_desde date, p_hasta date, p_persona_id uuid)','d9649325c740c9acf3ff544dcc541713'),
  ('fn_ausencias_alerta(p_persona_id uuid)','3c6fb48bc723004be7a9aa3359443bce'),
  ('fn_tipos_ausencia()','e4f4c232ac980951897926d136e6ca40'),
  ('fn_justificar_falta(p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text)','01a3663f33ceaf6968e006c904023b99')
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
