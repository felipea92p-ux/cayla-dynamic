-- ============================================================================
-- 0443_ausentismo_separa_pagado_y_excluye_pendiente.sql
-- ============================================================================
-- QUÉ PROMETE
--   fn_ausencias_resumen (0334) —el agregado detrás del indicador
--   "Ausencias" de Desempeño del equipo— deja de mezclar dos cosas en un solo
--   número, y deja de contar lo que Desarrollo Organizacional todavía no
--   confirmó:
--
--   1. Dos cifras en vez de una: `dias_pagados` (descanso médico, maternidad,
--      licencia con goce, duelo familiar directo, vacaciones — lo que CAYLA sí
--      paga, por ley o por decisión propia) y `dias_no_pagados` (permiso
--      personal, "otro", etc.). `dias_total` se queda, como la suma de las
--      dos, para quien ya lo usaba así.
--   2. Una ausencia de un tipo que exige aprobación de DO y que TODAVÍA no
--      fue aprobada deja de sumar en NINGUNA de las tres cifras. Antes sumaba
--      desde el momento de registrarse, así que una licencia con goce
--      registrada por error —o rechazada después— ya había inflado el
--      "ausentismo" de esa persona mientras estuvo pendiente.
--
-- QUÉ ASUME
--   Nada nuevo: no toca `ausencias` ni `tipos_ausencia`, solo lee. La firma
--   gana dos columnas (`dias_pagados`, `dias_no_pagados`); quien ya llamaba a
--   esta función y solo miraba `dias_total`/`registros`/`por_tipo` sigue
--   funcionando igual.
--
-- POR QUÉ "PAGADO" Y NO "LEY" (una corrección al lenguaje de la auditoría que
-- pidió esto)
--   La primera idea era separar "justificado por ley" (descanso médico,
--   maternidad) de "otras". Pero el catálogo ya tiene más tipos con
--   `paga = true` que solo esos dos —duelo familiar directo (0314) y licencia
--   con goce (0247) los paga CAYLA por decisión propia, no por mandato legal
--   directo— y esa distinción no vive en ninguna columna. Inventar una
--   columna "es_mandato_legal" para esta migración habría sido resolver un
--   problema que no se pidió. `paga` ya existe, ya es la que la propia
--   pantalla de Ausencias le muestra a quien registra ("· se paga"), y de
--   hecho separa mejor lo que a Desempeño le interesa: todo lo pagado ya pasó
--   —o pasa— por una aprobación de DO; todo lo no pagado es lo que puede
--   acumular un patrón sin que nadie más que la propia sede lo revise.
--
-- POR QUÉ requiere_aprobacion Y NO SOLO aprobada_at (mismo hallazgo que la
-- 0442, en la función vecina)
--   `vacaciones` tiene `paga = true` pero `requiere_aprobacion = false`: nace
--   aprobada automáticamente, sin que DO decida nada. Si el filtro mirara
--   `aprobada_at is not null` a secas, no excluiría ninguna vacación —da
--   igual, porque todas nacen aprobadas—, así que el filtro real que importa
--   es sobre los tipos que SÍ pueden quedar pendientes: `not t.requiere_aprobacion
--   or a.aprobada_at is not null` dice "esta fila cuenta si su tipo no
--   necesita aprobación, o si ya la tiene".
--
-- SE ROMPE SI
--   Alguien lee `dias_pagados` como "ausentismo grave" y lo trata igual que
--   una falta — no lo es: incluye descanso médico y maternidad, protegidos
--   por ley, junto con licencias que CAYLA concedió a propósito. La pantalla
--   que consume esto (ver el commit de /admin/horas que acompaña a esta
--   migración) tiene que decirlo en el propio rótulo, no solo en el dato.
--
-- CÓMO SE REVIERTE
--   Repegar el cuerpo de fn_ausencias_resumen tal como está en la 0334.
--
-- MD5 DE PARTIDA (Postgres LOCAL, no producción — pedir el de producción con
-- donde-vive.sh justo antes de pegar esto, no antes de escribirlo):
--   c4425702b052d42943d3acd751d9eff6
--
-- NOTA DE FORMA: esta función devuelve TABLE y gana dos columnas nuevas
-- (dias_pagados, dias_no_pagados) — Postgres no deja agregarle columnas a un
-- resultado de tabla con `create or replace` (mismo caso que la 0161 con
-- fn_documentos_tablero), así que hace falta `drop function` antes.
-- ============================================================================

drop function if exists fn_ausencias_resumen(date, date);

create function fn_ausencias_resumen(p_desde date, p_hasta date)
returns table (
  persona_id uuid, dias_total int, dias_pagados int, dias_no_pagados int,
  registros int, por_tipo jsonb
)
language sql stable security definer set search_path = public as $fn$
  select a.persona_id,
         sum(least(a.fecha_fin, p_hasta) - greatest(a.fecha_inicio, p_desde) + 1)::int as dias_total,
         coalesce((sum(least(a.fecha_fin, p_hasta) - greatest(a.fecha_inicio, p_desde) + 1)
                    filter (where t.paga))::int, 0) as dias_pagados,
         coalesce((sum(least(a.fecha_fin, p_hasta) - greatest(a.fecha_inicio, p_desde) + 1)
                    filter (where not t.paga))::int, 0) as dias_no_pagados,
         count(*)::int as registros,
         jsonb_object_agg(
           t.nombre,
           least(a.fecha_fin, p_hasta) - greatest(a.fecha_inicio, p_desde) + 1
         ) as por_tipo
  from ausencias a
  join personas pe on pe.id = a.persona_id
  join tipos_ausencia t on t.codigo = a.tipo
  where a.anulada_at is null
    -- CAMBIO 0443: lo que exige aprobación de DO y todavía no la tiene no
    -- cuenta como ausentismo — ver "POR QUÉ requiere_aprobacion" arriba.
    and (not t.requiere_aprobacion or a.aprobada_at is not null)
    and daterange(a.fecha_inicio, a.fecha_fin, '[]') && daterange(p_desde, p_hasta, '[]')
    and (fn_es_admin_o_lider()
         or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona())
         or a.persona_id = fn_persona_actual_id())
  group by a.persona_id;
$fn$;

comment on function fn_ausencias_resumen(date, date) is
  'Total de días de ausencia por persona en un rango, recortado a sus bordes, separado en pagados/no pagados y con desglose por tipo. Excluye lo anulado y lo que exige aprobación de DO y todavía no la tiene (0443). Misma visibilidad que fn_ausencias (0101): admin/líder todas, encargada su sede, cada persona la suya.';

grant execute on function fn_ausencias_resumen(date, date) to authenticated;
revoke execute on function fn_ausencias_resumen(date, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (443, 'ausentismo_separa_pagado_y_excluye_pendiente')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select prosrc like '%CAMBIO 0443%' as candado_presente
  from pg_proc where proname = 'fn_ausencias_resumen';
