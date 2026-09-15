-- ============================================================================
-- 0464 — Cierra los periodos que solo se quedaron abiertos por un grupo fantasma
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: reconcilia `periodos_planilla.estado`, sin tocar código, para
-- los periodos ya pasados que se quedaron 'abierto' SOLO porque un grupo
-- (tipo_vinculo) que ya no debería existir en ese rango —el defecto que
-- corrige la 0463— nunca llegó a marcarse pagado. Julio y agosto de 2026 son
-- el caso conocido.
--
-- ESTA MIGRACIÓN NO ES EL FIX. El fix es la 0463 («quien ingresa después no
-- se cuela en un periodo anterior», fusionada a `main` el mismo día desde
-- otra rama — `claude/practicantes-inicio-error-9315c7`, que encontró el
-- mismo defecto de forma independiente y lo corrigió con la misma condición:
-- `p.estado = 'activo' and p.fecha_ingreso <= p_fin`). Confirmado línea por
-- línea contra el cuerpo de la 0463: es exactamente el mismo cambio de fondo,
-- solo con distinto comentario — no hay nada que corregir dos veces.
--
-- LO QUE LA 0463 NO CUBRE, Y POR ESO ESTA MIGRACIÓN SIGUE HACIENDO FALTA. El
-- candado nuevo evita que un grupo fantasma vuelva a aparecer HACIA ADELANTE,
-- pero no cierra los periodos que YA quedaron atascados por su culpa. La
-- razón es estructural: `periodos_planilla.estado` solo pasa a 'pagado'
-- DENTRO de `fn_periodo_pagado` (0323), en el momento en que se marca el
-- ÚLTIMO grupo pendiente. Si ese grupo fantasma era el único que faltaba
-- —el caso de agosto, con planilla, prueba y rxh ya pagados—, no queda
-- ningún grupo real por el que alguien pueda volver a llamar a esa función:
-- los tres ya dicen 'pagado', y `fn_periodo_pagado` se niega a marcar de
-- nuevo un grupo que ya lo está. Sin este backfill, agosto se quedaría
-- diciendo "sin pagar" en el selector de /admin/planilla para siempre, aun
-- con la 0463 ya pegada.
--
-- QUÉ HACE, EXACTAMENTE. Para cada periodo con `estado = 'abierto'`, repite
-- el MISMO chequeo que ya hace `fn_periodo_pagado` al final de cada pago —
-- ¿todos los grupos con gente real (según `fn_planilla_calcular_nucleo`, ya
-- con el candado de la 0463 puesto) están en 'pagado' dentro de
-- `periodo_grupo_pago`?— y solo entonces lo cierra. No inventa ningún pago:
-- un periodo con un grupo real todavía pendiente de verdad (julio, con `rxh`
-- sin pagar) se queda exactamente como está. No es lógica nueva: es la lógica
-- que ya existe, vuelta a correr sobre datos viejos ahora que el cálculo de
-- quién tiene gente real ya no cuenta al fantasma.
--
-- QUÉ ASUME:
--   · Que para esta fecha ya se pegó la 0463 (o llega en el mismo lote, antes
--     que esta). Si se pegara esta migración SIN la 0463, `fn_planilla_
--     calcular_nucleo` seguiría contando al fantasma, `v_grupos_con_gente`
--     seguiría incluyéndolo, y el `if` de abajo simplemente no encontraría
--     ningún periodo que cerrar — no rompe nada, solo no hace nada.
--   · Que `periodos_planilla.estado` no necesita actor ni auditoría al
--     cerrarse por esta vía: es el mismo criterio que ya usa el propio
--     `fn_periodo_pagado`, cuyo `update periodos_planilla set estado =
--     'pagado', pagado_at = now() where id = p_periodo_id;` tampoco registra
--     quién lo disparó — el rastro de QUIÉN pagó cada cosa vive en
--     `periodo_grupo_pago.pagado_por`, por grupo, y ese no se toca aquí.
--
-- CÓMO SE REVIERTE: si algún periodo se cerró de más por error, se reabre con
--   "Revertir pago" desde /admin/planilla, grupo por grupo — el mismo camino
--   que ya existe para deshacer cualquier pago. No hay nada más que revertir:
--   esta migración no crea funciones, tablas ni columnas.
-- ============================================================================

do $$
declare
  v_per record;
  v_grupos_con_gente text[];
  v_cerrados int := 0;
begin
  for v_per in
    select id, fecha_ini, fecha_fin from periodos_planilla where estado = 'abierto'
  loop
    select array_agg(distinct f->>'tipo_vinculo') into v_grupos_con_gente
    from jsonb_array_elements(
      coalesce(fn_planilla_calcular_nucleo(v_per.fecha_ini, v_per.fecha_fin, v_per.id)->'filas', '[]'::jsonb)
    ) f;

    if v_grupos_con_gente is not null and not exists (
      select 1 from unnest(v_grupos_con_gente) g(grupo)
       where not exists (
         select 1 from periodo_grupo_pago
          where periodo_id = v_per.id and grupo = g.grupo and estado = 'pagado'
       )
    ) then
      update periodos_planilla set estado = 'pagado', pagado_at = now() where id = v_per.id;
      v_cerrados := v_cerrados + 1;
      raise notice '0464 · periodo % → % quedó cerrado: todos sus grupos reales ya estaban pagados.', v_per.fecha_ini, v_per.fecha_fin;
    end if;
  end loop;

  if v_cerrados = 0 then
    raise notice '0464 · ningún periodo tenía SOLO el grupo fantasma pendiente. Nada que cerrar.';
  end if;
end $$;

insert into migraciones_aplicadas (numero, nombre) values
  (464, 'la_planilla_deja_de_contar_a_quien_todavia_no_existia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
