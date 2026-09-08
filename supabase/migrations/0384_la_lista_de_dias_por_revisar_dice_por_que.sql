-- ============================================================================
-- 0384 · La lista de «días por revisar» dice POR QUÉ está cada día ahí
-- ============================================================================
--
-- QUÉ PROMETE
--   `fn_dias_por_revisar` gana una columna `motivo`, calculada EN VIVO, con tres
--   valores: 'secuencia_imposible', 'auto_cierre_sin_confirmar' y
--   'sello_sin_levantar'. Sigue devolviendo exactamente los mismos días que
--   antes — no esconde ninguno, no agrega ninguno. Lo único que cambia es que
--   ahora se puede decir la verdad sobre cada uno.
--
-- EL DEFECTO QUE ARREGLA (visto en producción el 2026-09-06)
--   La pantalla de Correcciones anunciaba «1 día quedó con una secuencia
--   imposible · Carlos Espejo · CCO · 2026-09-05». Ese día no tenía ninguna
--   secuencia imposible: era `Entrada 10:26 → Salida final 14:18`, que es
--   perfectamente posible. Lo único pendiente era confirmar la hora que había
--   puesto el auto-cierre.
--
--   Y la propia pantalla lo demostraba dos centímetros más abajo: al cargar el
--   día NO salía el aviso «La secuencia de marcas de este día no es posible»
--   (que se pregunta en vivo con `fn_dia_incoherente`), solo salía «Este día lo
--   cerró el sistema». El titular y el cuerpo de la misma pantalla se
--   contradecían.
--
-- LA CAUSA — una columna con tres significados
--   `fn_dias_por_revisar` lista toda marca no anulada en
--   `estado_revision = 'pendiente_revision'`. Pero a esa columna la escriben
--   tres cosas distintas, y ninguna deja dicho cuál fue:
--
--     1. La 0068 · el día quedó con una secuencia imposible → sella el día entero.
--     2. La 0089 · el auto-cierre nocturno puso una hora de salida que nadie ha
--        confirmado → nace 'pendiente_revision' (línea 114). La 0084 lo mantiene
--        A PROPÓSITO: «El auto-cierre conserva el suyo: es un sello por otro
--        motivo».
--     3. La 0207 · una marca cayó dentro de un periodo ya pagado → se sella ELLA
--        sola, sin sellar el día.
--
--   Más un residuo: un sello del caso 1 que nadie levantó, porque
--   `fn_levantar_sello_si_el_dia_cuadra` solo se llama desde las funciones de
--   corrección — nunca desde `fn_registrar_marcaje`. Es decir: la marca tardía
--   que ROMPE el día lo sella (0366, línea 430), y la marca tardía que lo
--   ARREGLA no lo desella.
--
--   Como el auto-cierre corre TODAS las noches, esa lista se llenaba sola de
--   días sanos bajo un titular de alarma. El daño no es el texto: es que el día
--   que una marca llegue de verdad fuera de orden va a estar enterrada entre
--   ellos y se va a leer como más de lo mismo. Un aviso que chilla siempre deja
--   de ser un aviso.
--
-- QUÉ ASUME
--   Que `fn_dia_incoherente` (0082) es la única autoridad sobre si un día cuadra
--   — la misma que ya usa el aviso de dentro de la pantalla, para que el titular
--   y el cuerpo no puedan volver a contradecirse. Y que «hay auto-cierre
--   pendiente» se pregunta con la MISMA condición que usa la pantalla:
--   `origen = 'auto_cierre' and anulada_at is null and estado_revision =
--   'pendiente_revision'`.
--
-- POR QUÉ `motivo` Y `periodo_pagado` SON DOS COLUMNAS Y NO UNA
--   Porque son dos preguntas: «¿por qué está sellado?» y «¿se puede tocar?».
--   Fundirlas sería repetir el pecado que esta migración arregla.
--
-- POR QUÉ SE CALCULA EN VIVO Y NO SE GUARDA
--   Un sello guardado dice que el día estuvo roto alguna vez, no que lo siga
--   estando — esa lección ya la pagó la 0084 con el día de Estefany del 17/07.
--   El `case` cuesta como mucho 50 llamadas a `fn_dia_incoherente` (el LIMIT se
--   aplica ANTES, en la CTE), cada una sobre las ~6 marcas de un día con índice
--   por persona y fecha. Es una pantalla que se abre dos veces al día.
--
-- LO QUE NO CIERRA, Y POR QUÉ NO
--   El agujero real es que `fn_registrar_marcaje` sella el día cuando queda roto
--   y no lo desella cuando una marca posterior lo arregla. La corrección natural
--   —un `else perform fn_levantar_sello_si_el_dia_cuadra(...)` sobre el `if` que
--   esa función YA evalúa, o sea a coste cero— NO se hace aquí porque
--   desharía, en la misma llamada, el sello que la 0207 acaba de poner a una
--   marca que cayó en periodo pagado: `fn_levantar_sello_si_el_dia_cuadra` no
--   distingue ese caso. Rompería la prueba 110, que defiende a propósito que ese
--   día «se avisa, no se esconde».
--   Cerrarlo exige decidir antes qué hace ese caso, y eso es diseño, no un else.
--   Mientras tanto ese residuo queda ETIQUETADO como 'sello_sin_levantar', que
--   es la mitad que sí se puede entregar hoy sin adivinar nada.
--
-- CÓMO SE REVIERTE
--   `DROP FUNCTION` + el cuerpo de la 0321 tal cual (quitando la columna
--   `motivo` de la firma y del select). Ningún dato cambia con esta migración:
--   no hay un solo `update` ni `insert` sobre `marcajes`.
--
-- md5 de partida (fn_dias_por_revisar, cuerpo de la 0321): fccc10394c1f5b0c74d061fcc66da140 · 989 caracteres
-- ============================================================================

-- Postgres no deja agregar una columna al tipo de retorno con CREATE OR REPLACE
-- (mismo caso que la 0321 y que la 0161 con fn_documentos_tablero).
DROP FUNCTION IF EXISTS public.fn_dias_por_revisar(integer);

CREATE FUNCTION public.fn_dias_por_revisar(p_limite integer DEFAULT 50)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, fecha date, marcas integer,
               periodo_pagado boolean, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with dias as (
    select m.persona_id,
           (p.nombres || ' ' || p.apellidos) as nombre,
           s.codigo as sede,
           (m.timestamp_marca at time zone 'America/Lima')::date as fecha,
           count(*)::int as marcas,
           -- Las marcas de aquí dentro ya vienen filtradas a «no anulada y
           -- pendiente de revisión», así que este bool_or es exactamente la
           -- misma pregunta que hace el aviso de la pantalla.
           bool_or(m.origen = 'auto_cierre') as hay_auto_cierre
    from marcajes m
    join personas p on p.id = m.persona_id
    join sedes s on s.id = p.sede_base_id
    where m.estado_revision = 'pendiente_revision'
      and m.anulada_at is null
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
         -- El orden importa: si el día SIGUE roto eso manda sobre todo lo demás,
         -- aunque además tenga un auto-cierre sin confirmar. Primero se ordena
         -- el día; confirmar una hora dentro de un día imposible no significa nada.
         case
           when fn_dia_incoherente(d.persona_id, d.fecha) then 'secuencia_imposible'
           when d.hay_auto_cierre                         then 'auto_cierre_sin_confirmar'
           else 'sello_sin_levantar'
         end as motivo
  from dias d
  order by d.fecha desc, d.nombre;
$function$;
grant execute on function fn_dias_por_revisar(int) to authenticated;
revoke execute on function fn_dias_por_revisar(int) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (384, 'la_lista_de_dias_por_revisar_dice_por_que')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
