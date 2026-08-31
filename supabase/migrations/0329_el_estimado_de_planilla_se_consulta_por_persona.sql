-- ============================================================================
-- 0329 · el estimado de planilla se puede consultar por persona
-- ============================================================================
-- QUÉ PROMETE: `fn_planilla_calcular_persona(p_persona_id, p_periodo_id)`
--   devuelve la fila de UNA persona dentro de un periodo — el mismo `jsonb`
--   que hoy solo se puede obtener corriendo `fn_planilla_calcular` para las
--   ~30 personas activas a la vez desde `/admin/planilla`. No agrega ningún
--   dato nuevo: es una forma más barata de pedir uno que ya existe.
--
--   Respeta la fragmentación por grupo que trajo la 0323: si el grupo
--   (`personas.tipo_vinculo`) de esa persona YA se pagó en ese periodo
--   (`periodo_grupo_pago.estado = 'pagado'`), se lee su foto congelada de
--   `planilla_pagada_detalle` — nunca se recalcula lo ya pagado, mismo
--   criterio que `fn_proyeccion_periodo`. Si su grupo sigue abierto, se
--   calcula en vivo.
--
--   Acceso: SOLO admin/líder, igual que `fn_proyeccion_periodo` y que
--   `fn_planilla_calcular` misma. Ninguna otra identidad puede consultar
--   NADA por esta función, ni siquiera su propio `persona_id` — ver
--   "QUÉ ASUME" abajo para por qué eso no era negociable hoy.
--
-- QUÉ ASUME:
--   · Que "estimado" no es "oficial": esta función es de solo lectura y no
--     escribe nada. El número que devuelve puede bajar de una consulta a
--     otra sin que nada esté mal — una corrección retroactiva, una jornada
--     que se anula por incoherente. Cualquier pantalla que la consuma debe
--     mostrarlo etiquetado como estimado, no como el pago final.
--   · Que `fn_planilla_calcular(p_ini, p_fin, p_periodo_id)` sigue devolviendo
--     `jsonb` con una clave `'filas'`, cada una con `persona_id` (0322 es la
--     vigente al escribir esto — confirmado con `donde-vive.sh`, sin cambios
--     de forma desde entonces).
--   · Que `personas.tipo_vinculo` (0085) sigue siendo el dato que dice a qué
--     grupo pertenece una persona, y que coincide con los valores de
--     `periodo_grupo_pago.grupo` (0323).
--
-- POR QUÉ ASÍ Y NO DUPLICANDO LAS CTEs DE fn_planilla_calcular FILTRADAS A
--   UNA PERSONA: se consideró copiar y filtrar la lógica de negocio (30
--   veces más barata por llamada) pero se descartó a propósito. A la escala
--   de CAYLA (~30 personas activas), calcular a las treinta para quedarse
--   con una es un costo que Postgres no siente. Copiar en cambio esa lógica
--   —55 versiones históricas, RxH, personal de dirección, sueldo fijo,
--   licencias, descanso médico, cada exclusión con su propia razón legal—
--   crea una segunda copia que se puede desalinear de la oficial la próxima
--   vez que alguien toque `fn_planilla_calcular` y no recuerde que existe
--   esta. Es el mismo motivo por el que la 0192 dejó de escribir la base
--   imponible en cinco sitios distintos y la puso en uno solo. Esta función
--   NUNCA reimplementa una regla de negocio: llama a la oficial y se queda
--   con una fila.
--
-- POR QUÉ NO SE ABRIÓ A CADA PERSONA DESDE EL DÍA UNO (aunque se conversó y
--   se decidió que valía la pena): `fn_planilla_calcular` trae desde la 0090
--   un guard escrito DENTRO de su cuerpo —"Solo un administrador o líder
--   puede calcular la planilla"— con un comentario explícito de que no se
--   toca nunca: la 0076 había abierto esa función a cualquier sesión con
--   login (la terminal de tienda incluida) al conceder permisos en masa, y
--   un `revoke` se deshace solo con el próximo `grant` masivo — un guard
--   interno no. Probado en vivo (`262_...test.sql`, 2026-08-31): cuando esta
--   función intenta calcular EN VIVO para una persona que no es admin/líder
--   (el caso que de verdad importa — mientras su periodo sigue abierto),
--   `fn_planilla_calcular` la rechaza igual, sin importar que esta función ya
--   la hubiera autorizado a ver su propio dato. Solo funcionaría para el
--   caso ya pagado (leyendo la foto, que no pasa por ese guard) — el caso
--   que a nadie le importa, porque el valor de un estimado está en verlo
--   MIENTRAS se genera. Abrirlo de verdad exige o bien duplicar la lógica de
--   cálculo (el riesgo de la 0192 otra vez, y a la escala completa del motor,
--   no de una fórmula) o repensar con cuidado cómo `fn_planilla_calcular`
--   decide quién puede pedirle un cálculo — eso es trabajo de arquitectura
--   aparte, no algo para resolver de paso en un primer cambio chico.
--
-- CÓMO SE REVIERTE: `drop function if exists
--   public.fn_planilla_calcular_persona(uuid, uuid);` — no toca ninguna
--   tabla ni ninguna otra función.
-- ============================================================================

create or replace function public.fn_planilla_calcular_persona(
  p_persona_id uuid,
  p_periodo_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_p      record;
  v_grupo  text;
  v_pagado boolean;
  v_fila   jsonb;
begin
  -- Solo admin/líder — mismo guard que fn_proyeccion_periodo. Nada de
  -- self-service todavía: ver "POR QUÉ NO SE ABRIÓ..." arriba.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Sin permiso para consultar esta planilla';
  end if;

  select * into v_p from periodos_planilla where id = p_periodo_id;
  if not found then
    raise exception 'El periodo no existe';
  end if;

  select tipo_vinculo into v_grupo from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe';
  end if;

  -- ¿su grupo ya se pagó en este periodo? Mismo criterio que
  -- fn_proyeccion_periodo (0323): lo pagado se lee, nunca se recalcula.
  select exists (
    select 1 from periodo_grupo_pago
     where periodo_id = p_periodo_id and grupo = v_grupo and estado = 'pagado'
  ) into v_pagado;

  if v_pagado then
    select d.fila into v_fila
      from planilla_pagada_detalle d
     where d.periodo_id = p_periodo_id
       and d.grupo = v_grupo
       and d.persona_id = p_persona_id
     order by d.version desc
     limit 1;

    return coalesce(v_fila, jsonb_build_object('persona_id', p_persona_id, 'sin_datos', true))
           || jsonb_build_object('fuente', 'foto');
  end if;

  -- En vivo: la MISMA función oficial, sin ninguna regla de negocio
  -- reimplementada — solo nos quedamos con la fila de esta persona.
  select f into v_fila
    from jsonb_array_elements(
      (fn_planilla_calcular(v_p.fecha_ini, v_p.fecha_fin, v_p.id)) -> 'filas'
    ) f
   where (f ->> 'persona_id')::uuid = p_persona_id;

  return coalesce(v_fila, jsonb_build_object('persona_id', p_persona_id, 'sin_datos', true))
         || jsonb_build_object('fuente', 'calculo');
end;
$function$;

comment on function public.fn_planilla_calcular_persona(uuid, uuid) is
  'Estimado de planilla de UNA persona en un periodo — 0329. Lee la foto si su grupo ya se pagó, calcula en vivo si no. Envoltorio de fn_planilla_calcular: no duplica ninguna regla de negocio. Solo admin/líder — el self-service queda pendiente, bloqueado por el guard interno (0090) de fn_planilla_calcular.';

revoke execute on function public.fn_planilla_calcular_persona(uuid, uuid) from public, anon;
grant  execute on function public.fn_planilla_calcular_persona(uuid, uuid) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (329, 'el_estimado_de_planilla_se_consulta_por_persona')
on conflict (numero) do nothing;
