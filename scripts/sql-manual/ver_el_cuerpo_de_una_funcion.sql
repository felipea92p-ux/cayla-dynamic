-- ############################################################################
-- ####  SOLO LEE. Devuelve UNA fila. Instantáneo.                          ####
-- ############################################################################
--
-- ver_el_cuerpo_de_una_funcion.sql — el último recurso: mirar el texto
--
-- POR QUÉ ESTE ARCHIVO EXISTE. Una huella dice QUE algo cambió, nunca QUÉ. El
-- 2026-08-07 la comparación dejó 22 funciones distintas entre producción y el
-- repositorio, y sobre esas 22 se probaron —y se descartaron midiendo— tres
-- explicaciones seguidas:
--
--   · «un barrido sobre las funciones de escritura» — no encajaba: funciones
--     que escriben igual, como fn_set_salario o fn_set_vacaciones, coinciden.
--   · «el texto se aplicó desde una migración vieja» — no encajaba: la última
--     migración que las define es la misma que la de las que sí coinciden.
--   · «los acentos quedaron descompuestos» (NFD) — la forma encajaba exacto,
--     310→313 caracteres y 313→316 bytes, y aun así la huella no: el cuerpo
--     del repositorio pasado a NFD da 8259f651 y producción tiene cfb3c0c0.
--
-- Tres teorías y tres veces medir para tumbarlas. A la cuarta se deja de
-- adivinar: `fn_set_con_hijos` son seis líneas y 310 caracteres. Se pide el
-- texto y se mira. Sale más barato que la siguiente teoría.
--
-- La regla que queda: cuando una huella no cuadra y el objeto es pequeño, se
-- lee el objeto. Comparar resúmenes es rápido hasta que deja de serlo.
--
-- SE ELIGIÓ fn_set_con_hijos por ser la más corta de las 22 y no tocar dinero:
-- su cuerpo entero cabe en la pantalla y no hay nada delicado en él.
-- ############################################################################

select
  (select length(p.prosrc)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_set_con_hijos') as caracteres,

  (select octet_length(p.prosrc)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_set_con_hijos') as bytes,

  -- El texto tal cual. Es lo único que no puede malinterpretarse.
  (select p.prosrc
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_set_con_hijos') as cuerpo,

  -- Y la medida de las 22, para saber de una vez si lo que se vea arriba
  -- explica a todas o solo a esta. Formato: nombre/argumentos/caracteres/bytes
  (select string_agg(p.proname || '/' || p.pronargs || '/' || length(p.prosrc)
                     || '/' || octet_length(p.prosrc), ' ' order by p.proname, p.pronargs)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_agregar_marcaje','fn_agregar_movimiento','fn_corregir_marcaje',
                        'fn_crear_periodo','fn_eliminar_marcaje','fn_eliminar_periodo',
                        'fn_fijar_base_declarada','fn_proyeccion_planilla','fn_quitar_feriado',
                        'fn_quitar_movimiento','fn_quitar_rendimiento','fn_quitar_turno',
                        'fn_set_con_hijos','fn_set_descanso','fn_set_feriado',
                        'fn_set_horario_semanal','fn_set_justificacion','fn_set_meta_cobertura',
                        'fn_set_rendimiento','fn_set_sueldo_base_legal','fn_set_turno',
                        'fn_simular_planilla')) as medidas_de_las_22;
