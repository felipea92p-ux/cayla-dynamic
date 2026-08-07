-- ============================================================================
-- ¿QUÉ ME FALTA PEGAR? — solo LEE, no cambia nada. Pégala en el SQL Editor.
-- ============================================================================
-- Compara lo que hay en el repositorio contra lo que producción tiene anotado,
-- y te dice fila por fila cuál falta. No hay que cruzar nada a mano.
--
-- POR QUÉ ESTA CONSULTA EXISTE
--   El 2026-08-07 una guía dio por pendiente una migración que ya estaba
--   aplicada, y estuvo a una pegada de revertir la 0171 en producción. La
--   diferencia entre suponer y preguntar son estas veinte líneas.
--
-- CÓMO SE ACTUALIZA LA LISTA cuando el repo crezca — una sola línea:
--   ls supabase/migrations/ | sed -E "s/^0*([0-9]+)_(.*)\.sql$/    (\1, '\2'),/"
--   y se reemplaza el bloque `repo` de abajo.
--
-- LO QUE ESTA CONSULTA NO PUEDE VER
--   Que una migración esté anotada NO prueba que su contenido esté vivo: alguien
--   pudo aplicarla y otra pegada posterior pudo pisarla. Para `fn_planilla_calcular`
--   —la que decide lo que cobra cada persona— eso se comprueba con el md5 de
--   abajo, que mira el cuerpo real y no el registro.
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
    (179, 'la_pantalla_de_equipo_dice_cuando_y_por_que_se_fue')
)
select
  r.numero,
  r.nombre,
  case when a.numero is null then '❌  FALTA PEGAR' else '✓   aplicada' end as estado,
  a.aplicada_at
from repo r
left join migraciones_aplicadas a on a.numero = r.numero
order by r.numero;


-- ── Cuántas faltan, de un vistazo ──────────────────────────────────────────
with repo(numero) as (values
    (150),
    (151),
    (152),
    (153),
    (154),
    (155),
    (156),
    (157),
    (158),
    (159),
    (160),
    (161),
    (162),
    (163),
    (164),
    (165),
    (166),
    (167),
    (168),
    (169),
    (170),
    (171),
    (172),
    (173),
    (174),
    (175),
    (176),
    (177),
    (178),
    (179)
)
select count(*) filter (where a.numero is null) as faltan,
       count(*) filter (where a.numero is not null) as aplicadas,
       count(*) as total_en_el_repo
from repo r left join migraciones_aplicadas a on a.numero = r.numero;


-- ── Y en qué versión está de verdad la función que calcula la planilla ─────
-- El registro dice qué se pegó; esto dice qué quedó vivo. No siempre coinciden.
select md5(prosrc) as md5_actual,
       case md5(prosrc)
         when '30e0ecbf11ac5939457df6c2b3cccc77' then '0166 — la movilidad por sede física'
         when '46c6c3de546f4da080d328a079470478' then '0171 — sin plus ni rendimiento'
         when 'cb3c5de14dd2b5a8872965814d5e7cd9' then '0173 — el sueldo fijo no duplica el feriado'
         when '93e96e37e05799121485e5721de3dc06' then '0177 — las vacaciones se pagan'
         else '⚠ md5 DESCONOCIDO: nadie lo ha catalogado. Avisar antes de pegar nada que toque la planilla.'
       end as version_viva
from pg_proc where proname = 'fn_planilla_calcular';
