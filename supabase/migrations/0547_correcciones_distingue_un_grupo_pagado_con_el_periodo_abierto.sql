-- ============================================================================
-- 0547 · Correcciones distingue «su grupo ya se pagó» de «ya cuadra»
-- ============================================================================
--
-- QUÉ PROMETE
--   `fn_dias_por_revisar` sigue devolviendo exactamente los mismos días —no
--   esconde ninguno ni agrega ninguno— pero gana:
--     · un motivo nuevo, 'grupo_pagado_periodo_abierto', para el día cuya marca
--       está sellada porque el GRUPO de esa persona ya se pagó mientras el
--       periodo sigue abierto;
--     · dos columnas, `grupo_pagado` y `grupo_pagado_at`, con qué grupo y cuándo,
--       para poder decirlo en pantalla con todas sus letras.
--
-- EL DEFECTO (visto en producción el 2026-10-21)
--   El grupo «planilla» se marcó pagado por error a mitad de periodo. Cada marca
--   nueva de esa gente entró sellada (0207) y sus horas dejaron de recalcularse.
--   Correcciones mostró esos días en la banda «N días quedaron marcados y ya
--   cuadran · No hay nada que corregir»: cierto sobre la secuencia de marcas y
--   falso sobre lo que importaba. Era lo único visible de un pago que bloqueaba
--   las horas de diez personas, y se leyó como un sello viejo sin importancia.
--
--   La causa de fondo es que `fn_dias_por_revisar` pregunta «¿está pagado?» solo
--   por `periodos_planilla.estado`, que pasa a 'pagado' cuando TODOS los grupos
--   con gente se pagan. El candado de horas es por grupo (0327). Un grupo pagado
--   solo es invisible para esa pregunta.
--
-- POR QUÉ NO BASTA CON CAMBIAR `periodo_pagado` POR EL CANDADO POR PERSONA
--   Sería lo primero que se le ocurre a cualquiera, y haría daño: la pantalla
--   oculta los días con `periodo_pagado = true` a propósito (no hay nada que
--   corregir en un periodo ya cerrado sin reabrirlo). Con el candado por persona,
--   los días de este incidente PASARÍAN A ESTAR OCULTOS y el aviso desaparecería
--   justo cuando hacía falta. `periodo_pagado` sigue significando «el periodo
--   entero está pagado»; lo nuevo es una respuesta distinta a una pregunta
--   distinta: «¿se pagó solo una parte con el periodo aún abierto?».
--
-- QUÉ CAMBIA, Y QUÉ NO
--   · Mismos días, mismas columnas de antes en el mismo orden (las dos nuevas van
--     al final), mismo permiso, mismo filtro por sede y por liquidados (0422).
--   · El motivo nuevo SOLO reemplaza a 'sello_sin_levantar', que es lo último que
--     se evalúa. Un día realmente roto sigue siendo 'secuencia_imposible' y un
--     auto-cierre sin confirmar sigue siendo 'auto_cierre_sin_confirmar': esos dos
--     mandan sobre el pago del grupo.
--   · `grupo_pagado*` es null cuando el periodo entero está pagado.
--
-- QUÉ ASUME
--   · Que `fn_dias_por_revisar` en producción es la de la 0422. Se comprueba al
--     principio con md5 (tres formas, como documenta CLAUDE.md): si no coincide,
--     PARA sin aplicar nada.
--   · Que `periodo_grupo_pago` (0323) tiene como máximo una fila por (periodo,
--     grupo) — su clave primaria —, así que una persona tiene como máximo un grupo
--     pagado por periodo.
--
-- COSTO
--   Una subconsulta por día listado, con el límite de 50 que ya tenía la función,
--   sobre una tabla de unas pocas filas por periodo. No cambia nada que se note.
--
-- CÓMO SE REVIERTE
--   `drop function fn_dias_por_revisar(integer)` y volver a pegar el cuerpo de la
--   0422 (sin las dos columnas). La pantalla que ya lee las columnas nuevas dejaría
--   de recibirlas: se tolera, quedan `undefined` y la banda nueva no sale.
--
-- md5 de partida (fn_dias_por_revisar, cuerpo de la 0422), medido en un Postgres
-- desechable con las migraciones de esta rama. La confirmación contra producción
-- la hace el bloque de abajo AL PEGAR, no una persona de memoria:
--   tal cual              cdd73993f944f3038c5ff4cbda9dc8ff · 1710 caracteres
--   sin comentarios       347b96984d1359d39c52b62bf395fdeb
--   crlf tal cual         261afa118867ccbaae95c5a18592a8b4
-- ============================================================================

do $$
declare
  v_md5 text;
  v_len integer;
  v_pelada text;
begin
  select md5(p.prosrc), length(p.prosrc),
         md5(array_to_string(array(
           select regexp_replace(l, '[[:space:]]*--.*$', '')
             from unnest(string_to_array(p.prosrc, chr(10))) as l
            where btrim(l) not like '--%'), chr(10)))
    into v_md5, v_len, v_pelada
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_dias_por_revisar';

  if v_md5 is null then
    raise exception '0547 · PARA. fn_dias_por_revisar no existe en esta base. No se aplicó nada.';
  end if;

  -- Mismo código, tres formas de llegar a producción (CLAUDE.md): tal cual, sin
  -- comentarios, o con \r\n si se pegó desde Windows. NO cubre «desde Windows Y sin
  -- comentarios a la vez» (CLAUDE.md lo dice): ahí PARA, y la salida es medir.
  if v_md5 not in ('cdd73993f944f3038c5ff4cbda9dc8ff', '261afa118867ccbaae95c5a18592a8b4')
     and v_pelada <> '347b96984d1359d39c52b62bf395fdeb'
  then
    raise exception '0547 · PARA. fn_dias_por_revisar en esta base es % (% caracteres; sin comentarios %), y no es ninguna de las formas esperadas. Producción tiene otra versión: no se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_dias_por_revisar.', v_md5, v_len, v_pelada;
  end if;
end
$$;

-- Postgres no deja agregar columnas al tipo de retorno con CREATE OR REPLACE
-- (mismo caso que la 0384 y que la 0161 con fn_documentos_tablero).
drop function if exists public.fn_dias_por_revisar(integer);

create function public.fn_dias_por_revisar(p_limite integer default 50)
 returns table(persona_id uuid, nombre text, sede text, fecha date, marcas integer,
               periodo_pagado boolean, motivo text,
               grupo_pagado text, grupo_pagado_at timestamptz)
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
  with dias as (
    select m.persona_id,
           (p.nombres || ' ' || p.apellidos) as nombre,
           s.codigo as sede,
           (m.timestamp_marca at time zone 'America/Lima')::date as fecha,
           count(*)::int as marcas,
           bool_or(m.origen = 'auto_cierre') as hay_auto_cierre
    from marcajes m
    join personas p on p.id = m.persona_id
    join sedes s on s.id = p.sede_base_id
    where m.estado_revision = 'pendiente_revision'
      and m.anulada_at is null
      -- 0422: quien ya cobró su liquidación deja de aparecer para siempre en esta
      -- cola. Mientras no se le liquide, sigue viéndose.
      and not fn_persona_liquidada(p.id)
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona()))
    group by m.persona_id, p.nombres, p.apellidos, s.codigo,
             (m.timestamp_marca at time zone 'America/Lima')::date
    order by (m.timestamp_marca at time zone 'America/Lima')::date desc,
             (p.nombres || ' ' || p.apellidos)
    limit greatest(p_limite, 1)
  )
  select d.persona_id, d.nombre, d.sede, d.fecha, d.marcas,
         exists (
           select 1 from periodos_planilla pp
           where pp.estado = 'pagado' and d.fecha between pp.fecha_ini and pp.fecha_fin
         ) as periodo_pagado,
         case
           when fn_dia_incoherente(d.persona_id, d.fecha) then 'secuencia_imposible'
           when d.hay_auto_cierre                         then 'auto_cierre_sin_confirmar'
           -- ⇩ CAMBIO 0547: lo último que se evalúa. Un día roto o un auto-cierre
           -- sin confirmar siguen mandando; esto solo parte en dos el cajón de
           -- sastre que era 'sello_sin_levantar'.
           when gp.grupo is not null                      then 'grupo_pagado_periodo_abierto'
           else 'sello_sin_levantar'
         end as motivo,
         gp.grupo     as grupo_pagado,
         gp.pagado_at as grupo_pagado_at
  from dias d
  -- ⇩ CAMBIO 0547: ¿el GRUPO de esta persona se pagó en un periodo que sigue
  -- abierto? Es la pregunta que `periodo_pagado` no puede contestar: solo se
  -- enciende cuando TODOS los grupos con gente se pagaron. `pp.estado <> 'pagado'`
  -- es exactamente la negación de `periodo_pagado`, así que las dos columnas no
  -- pueden decirse a la vez. El orden del `limit 1` es un ancla: la clave primaria
  -- ya garantiza una sola fila, pero un `limit 1` sin orden no es un orden.
  left join lateral (
    select g.grupo, g.pagado_at
      from periodos_planilla pp
      join periodo_grupo_pago g on g.periodo_id = pp.id and g.estado = 'pagado'
      join personas pe on pe.id = d.persona_id and pe.tipo_vinculo = g.grupo
     where d.fecha between pp.fecha_ini and pp.fecha_fin
       and pp.estado <> 'pagado'
     order by pp.fecha_ini desc, pp.id
     limit 1
  ) gp on true
  order by d.fecha desc, d.nombre;
$fn$;

grant execute on function public.fn_dias_por_revisar(int) to authenticated;
revoke execute on function public.fn_dias_por_revisar(int) from public, anon;

comment on function public.fn_dias_por_revisar(int) is
  '0547 — Días con marcas selladas, con el motivo EN VIVO. Desde la 0547 parte en dos «sello_sin_levantar»: ''grupo_pagado_periodo_abierto'' cuando el grupo de la persona se pagó con el periodo todavía abierto (con grupo_pagado y grupo_pagado_at), y el de siempre cuando de verdad solo queda un sello viejo en un día que cuadra. Devuelve los mismos días que antes.';

insert into migraciones_aplicadas (numero, nombre)
values (547, 'correcciones_distingue_un_grupo_pagado_con_el_periodo_abierto')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────────
-- Las dos columnas existen, y el registro dice ESTA migración (número Y nombre).
select exists (
         select 1 from information_schema.routines r
          where r.routine_schema = 'public' and r.routine_name = 'fn_dias_por_revisar'
       ) as existe,
       position('CAMBIO 0547' in pg_get_functiondef('public.fn_dias_por_revisar(integer)'::regprocedure)) > 0 as tiene_el_cambio,
       (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 547) as registro;
