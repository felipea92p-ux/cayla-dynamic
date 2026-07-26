-- ============================================================================
-- 0077 — La base sabe qué migraciones tiene puestas
-- ----------------------------------------------------------------------------
-- PROMETE: que un solo SELECT diga la verdad sobre qué migraciones corrieron
-- en ESTA base — sin depender de la memoria de nadie ni de un documento.
--
-- EL PROBLEMA QUE CIERRA: las migraciones se pegan a mano en el SQL Editor
-- (decisión deliberada: la clave de servicio está rotada). Eso funciona, pero
-- dejó el estado de producción documentado en prosa, y la prosa se quedó en la
-- 0034 mientras la base iba por la 0073. En julio 2026 eso ya costó un enredo
-- real: dos migraciones aplicadas en prod (0074/0075) cuyo archivo estuvo a
-- punto de perderse en una copia de iCloud.
--
-- CÓMO SE USA: cada migración, desde la 0078 en adelante, termina con su línea
--   insert into migraciones_aplicadas (numero, nombre) values (78, '...')
--   on conflict (numero) do nothing;
-- Si el archivo se pega dos veces, la segunda no hace nada (todas las
-- migraciones de este repo son idempotentes; el registro también).
--
-- CARGA RETROACTIVA: esta migración registra la 0001–0073 de una vez, porque
-- esta base ya las tiene (si estás leyendo esto desde el SQL Editor de prod,
-- es porque prod ya va por aquí). La 0074/0075/0076 se registran en el bloque
-- final SOLO si sus objetos existen — así el mismo archivo dice la verdad
-- también en una base local que vaya en otro punto.
--
-- Reversible: drop table migraciones_aplicadas (no toca nada del negocio).
-- ============================================================================

create table if not exists migraciones_aplicadas (
  numero      int primary key,
  nombre      text not null,
  aplicada_at timestamptz not null default now()
);

-- Nadie escribe ni lee esto desde la app: es del operador (SQL Editor).
alter table migraciones_aplicadas enable row level security;
revoke all on migraciones_aplicadas from authenticated, anon;

-- ── Retroactivo: lo que esta base ya tiene si llegó hasta aquí ──────────────
-- (Nombres tomados de los archivos reales de supabase/migrations/. La 0031 y
-- la 0033 viven fuera de git por datos personales — scripts/sql-manual/ — pero
-- en esta base sí corrieron, así que se registran.)
insert into migraciones_aplicadas (numero, nombre) values
  ( 1,'init'),( 2,'functions'),( 3,'rls'),( 4,'grants'),
  ( 5,'fix_rls_recursion'),( 6,'personas_email'),( 7,'auto_cierre'),( 8,'visible_todas_sedes'),
  ( 9,'correcciones'),(10,'correccion_supervisor'),(11,'editor_horarios'),(12,'terminal_requiere_pin'),
  (13,'turnos_por_dia'),(14,'turnos_cobertura'),(15,'horario_base_dias_refrigerio'),(16,'horario_por_dia'),
  (17,'salida_temprana_extra'),(18,'funcion_persona'),(19,'salarios'),(20,'rpc_bypass_cache'),
  (21,'areas'),(22,'areas_catalogo'),(23,'parche_areas'),(24,'planilla'),
  (25,'planilla_periodos'),(26,'parche_planilla_v2'),(27,'feriado_por_ingreso'),(28,'ingreso_primera_marca'),
  (29,'provisiones_acumuladas'),(30,'provisiones_anual'),(31,'historico_2025_sql_manual'),(32,'objetivos_checklist'),
  (33,'ingresos_2025_sql_manual'),(34,'bono_puntualidad'),(35,'provisiones_zona_horaria'),(36,'auto_cierre_horario'),
  (37,'candado_periodo_pagado'),(38,'meta_encargadas'),(39,'meta_por_tramo'),(40,'encargada_piso'),
  (41,'drop_sembrar_ingresos'),(42,'vacaciones'),(43,'vacaciones_resumen'),(44,'vacaciones_saldo_acumulado'),
  (45,'historico_2025_diario'),(46,'en_planilla'),(47,'sueldo_fijo'),(48,'provisiones_sueldo_fijo'),
  (49,'grati_cts_en_planilla'),(50,'nombres_internos_grati_cts'),(51,'faltas_deteccion'),(52,'incidencias_aceptadas'),
  (53,'levantar_tardanza'),(54,'faltas_resumen'),(55,'faltas_en30_ventana_movil'),(56,'expediente_disciplinario'),
  (57,'tardanzas_resumen'),(58,'expediente_funciones'),(59,'generar_tardanza'),(60,'generar_falta'),
  (61,'datos_personales'),(62,'tardanzas_ultima_fecha'),(63,'sedes_gestionables'),(64,'tardanzas_resumen_no_bis_in_idem'),
  (65,'firma_escaneada'),(66,'reversas_pago'),(67,'tardanzas_faltas_as_of'),(68,'marcajes_fuera_de_orden'),
  (69,'feriado_descanso_sustitutorio'),(70,'faltas_conocen_descanso_sustitutorio'),(71,'elegir_firmante'),
  (72,'descanso_sustitutorio_acuerdo_previo'),(73,'actas_descanso_sustitutorio')
on conflict (numero) do nothing;

-- ── 0074–0076: solo si de verdad están (verifica el objeto, no la memoria) ──
do $$
begin
  -- 0074: firmante elegible + cargo entregado (existe su tabla de adjuntos)
  if to_regclass('public.expediente_adjuntos') is not null then
    insert into migraciones_aplicadas (numero, nombre)
    values (74, 'firmante_elegible_y_cargo_entregado') on conflict (numero) do nothing;
  end if;
  -- 0075: suspensión en días laborables (existe fn_dias_suspension)
  if exists (select 1 from pg_proc where proname = 'fn_dias_suspension') then
    insert into migraciones_aplicadas (numero, nombre)
    values (75, 'suspension_en_dias_laborables') on conflict (numero) do nothing;
  end if;
  -- 0076: cierre de ejecución anónima (existe la tabla de firmas)
  if to_regclass('public.firmas_escaneadas') is not null then
    insert into migraciones_aplicadas (numero, nombre)
    values (76, 'cerrar_ejecucion_anonima') on conflict (numero) do nothing;
  end if;
end $$;

insert into migraciones_aplicadas (numero, nombre) values (77, 'registro_de_migraciones')
on conflict (numero) do nothing;

-- Para leer el estado:  select * from migraciones_aplicadas order by numero;
-- Para ver huecos:      select generate_series(1, (select max(numero) from migraciones_aplicadas)) n
--                       except select numero from migraciones_aplicadas order by 1;
