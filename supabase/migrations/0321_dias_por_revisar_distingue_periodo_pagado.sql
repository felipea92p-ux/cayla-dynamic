-- ============================================================================
-- 0321 · fn_dias_por_revisar distingue el día de un periodo ya pagado
-- ============================================================================
-- QUÉ PROMETE: `fn_dias_por_revisar` gana una columna `periodo_pagado`. Sigue
--   devolviendo TODOS los días con secuencia imposible, incluidos los de un
--   periodo ya pagado — eso no cambia, y no debe cambiar: la prueba
--   `110_un_periodo_pagado_no_cambia_de_horas.test.sql` (líneas 114-123)
--   defiende a propósito que ese día "se avisa, no se esconde", porque
--   esconderlo escondería también el caso real en que la marca tardía SÍ
--   importa para entender una diferencia entre `jornadas` y lo que se pagó.
--   Lo que cambia es que el panel ahora puede distinguir "puedo corregir esto"
--   de "esto es historia, no hay acción posible", en vez de tratarlos igual.
--
-- QUÉ ASUME: que un día cuya fecha cae en un `periodos_planilla` con
--   estado = 'pagado' no se puede corregir sin reabrir el periodo primero —
--   `fn_anular_marcaje` ya lo rechaza así (0089, líneas 220-227), y las dos
--   rutas para levantar el sello sin anular no existen. Ver
--   `fn_levantar_sello_si_el_dia_cuadra` y `fn_resellar_dia`: las dos dependen
--   de que el día deje de ser incoherente.
--
-- POR QUÉ ASÍ Y NO FILTRANDO EL LISTADO: una versión anterior de esta
--   migración quitaba del todo los días de periodos pagados. Se descartó
--   porque contradice la 110 explícitamente y porque el criterio de la casa
--   es que los falsos positivos y la información oculta son ambos un riesgo —
--   mejor decir "esto es histórico y no requiere acción" que no decir nada.
--
-- CÓMO SE REVIERTE: `create or replace function` con el cuerpo de la 0082
--   (líneas 117-139), quitando la columna `periodo_pagado`.
-- ============================================================================

-- Postgres no deja agregar una columna al tipo de retorno con CREATE OR
-- REPLACE (mismo caso que la 0161 con fn_documentos_tablero): hay que
-- soltarla primero.
DROP FUNCTION IF EXISTS public.fn_dias_por_revisar(integer);

CREATE FUNCTION public.fn_dias_por_revisar(p_limite integer DEFAULT 50)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, fecha date, marcas integer, periodo_pagado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select d.persona_id, d.nombre, d.sede, d.fecha, d.marcas,
         exists (
           select 1 from periodos_planilla pp
           where pp.estado = 'pagado' and d.fecha between pp.fecha_ini and pp.fecha_fin
         ) as periodo_pagado
  from (
    select m.persona_id,
           (p.nombres || ' ' || p.apellidos) as nombre,
           s.codigo as sede,
           (m.timestamp_marca at time zone 'America/Lima')::date as fecha,
           count(*)::int as marcas
    from marcajes m
    join personas p on p.id = m.persona_id
    join sedes s on s.id = p.sede_base_id
    where m.estado_revision = 'pendiente_revision'
      and m.anulada_at is null
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona()))
    group by m.persona_id, p.nombres, p.apellidos, s.codigo,
             (m.timestamp_marca at time zone 'America/Lima')::date
  ) d
  order by d.fecha desc, d.nombre
  limit greatest(p_limite, 1);
$function$;
grant execute on function fn_dias_por_revisar(int) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (321, 'dias_por_revisar_distingue_periodo_pagado')
on conflict (numero) do nothing;
