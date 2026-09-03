-- ============================================================================
-- 0350 — Confirmación de un toque al marcar salida sin retorno de refrigerio
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: cuando alguien marca su salida_final y ese día NUNCA marcó una
-- salida a refrigerio, el terminal le pregunta en el momento —"¿trabajaste
-- corrido, sin parar a almorzar?"— y esa respuesta queda guardada DENTRO del
-- propio marcaje de salida_final, en la columna nueva
-- `confirmo_sin_refrigerio` (true = "sí, corrido", false = "no, sí almorcé,
-- se me olvidó marcar", null = nunca se le preguntó porque ese día sí tenía
-- una salida a refrigerio marcada).
--
-- LA CONDICIÓN NO ES "salida a refrigerio sin retorno" — se descartó al
-- escribir esto: el candado anti-doble-marcado de esta misma función
-- (fn_siguiente_tipo_esperado, más abajo) YA exige `retorno_almuerzo` antes
-- de aceptar cualquier otra marca; una persona en el terminal nunca puede
-- llegar a elegir salida_final con un refrigerio abierto — se lo pide primero
-- el candado. La única ambigüedad alcanzable EN VIVO es la otra: que nunca
-- haya marcado salida a refrigerio en todo el día.
--
-- QUÉ ASUME: que la pregunta en el momento vale más como evidencia que la
-- misma pregunta hecha por un admin días después en Incidencias — la persona
-- todavía se acuerda, y la respuesta queda con su propio timestamp de marcaje.
-- No sustituye la revisión de Incidencias: esto es un dato más para que quien
-- revisa decida con más contexto, no una aprobación automática. A propósito
-- NO llama a fn_aceptar_incidencia (ver más abajo) — esa función exige
-- fn_verificar_corrector (admin/líder/encargada de sede), y el terminal
-- autentica como el DISPOSITIVO, no como esa persona. Dejar que el terminal
-- auto-aceptara la incidencia sería que un aparato sin PIN se autoapruebe algo
-- que hoy exige el visto bueno de una persona con rol — el mismo agujero que
-- el terminal sin PIN ya evita en todo lo demás con cuidado.
--
-- POR QUÉ SE ELIGIÓ ASÍ (y no "preguntar siempre al marcar salida"): el
-- terminal existe para marcar instantáneo — CLAUDE.md documenta esa decisión
-- de Felipe (sin PIN, a propósito) — así que agregar un toque extra a CADA
-- salida de CADA persona todos los días habría sido fricción constante para
-- resolver una ambigüedad que casi nunca ocurre. La pregunta sale solo cuando
-- el propio terminal, con los marcajes que ya tiene cargados del día
-- (marcajesHoyRef), puede ver la ambigüedad real: hay una salida_almuerzo sin
-- su retorno. Es la misma condición que ya usa Incidencias para mostrar "Sin
-- marca de retorno del almuerzo" (tiene_salida_no_retornada), preguntada
-- antes en vez de después.
--
-- QUÉ NO HACE: no agrega ninguna validación que bloquee el marcaje. Un "No, sí
-- almorcé" no arregla nada por sí solo — sigue haciendo falta que un admin
-- registre las horas reales en Correcciones, exactamente como hoy. La única
-- diferencia es que ese admin ya no parte de cero: tiene la palabra de la
-- persona, con hora, antes de decidir.
--
-- RIESGO CONOCIDO Y ACEPTADO: algún horario con `almuerzo_min_minutos = 0`
-- (turno corto sin refrigerio obligatorio) dispararía la pregunta sin que
-- haya ambigüedad real, porque el terminal no tiene el horario cargado para
-- descartarlo. Se acepta: ninguna respuesta cambia lo que se paga —esto es
-- evidencia, no una validación—, así que el costo de un falso disparo es, como
-- mucho, un toque de más en la pantalla, nunca una acusación ni un descuento.
--
-- SE REVIERTE: soltando la columna (los datos que llegue a guardar se
-- pierden, y es aceptable — es un dato de apoyo, no la fuente de verdad del
-- marcaje) y devolviendo fn_registrar_marcaje a su forma de la 0327 (drop del
-- signature de 9 argumentos, create del de 8).
--
-- md5 de partida (Postgres LOCAL, no producción): 70a606f884ce46931bc2cee9cab97656
-- Antes de pegar esto en el SQL Editor, vuelve a pedirle el md5 a PRODUCCIÓN
-- con donde-vive.sh — esta migración se escribió en una sesión donde varias
-- otras trabajan al mismo tiempo sobre el mismo árbol.
-- ============================================================================

-- ── 1 · La columna ───────────────────────────────────────────────────────────
-- Nullable a propósito: null significa "nunca se le preguntó" (el 99% de las
-- salidas, sin ambigüedad), y eso es distinto de false ("preguntado, y dijo
-- que no trabajó corrido"). Fundir los dos en un default `false` borraría esa
-- distinción y haría parecer que TODAS las salidas fueron revisadas.
alter table marcajes add column if not exists confirmo_sin_refrigerio boolean;

comment on column marcajes.confirmo_sin_refrigerio is
  'Solo en marcajes de salida_final cuando ese día no había ninguna salida_almuerzo marcada. true = la persona confirmó, al marcar, que trabajó corrido sin parar a almorzar. false = dijo que sí almorzó pero olvidó marcar la salida a refrigerio. null = no se le preguntó (ese día sí marcó su salida a refrigerio, o el marcaje es de otro tipo).';

-- ── 2 · fn_registrar_marcaje ─────────────────────────────────────────────────
-- Se agrega UN parámetro nuevo al final, con default null: los llamadores que
-- ya existen (Correcciones, la cola offline vieja, cualquier reintento en
-- vuelo) no lo mandan y siguen funcionando exactamente igual.
--
-- OJO: agregar un parámetro con `create or replace function` NO reemplaza la
-- función — Postgres compara la lista de tipos de los argumentos, y una lista
-- más larga es un signature DISTINTO. Sin el `drop function` de abajo, esto
-- habría dejado DOS versiones de fn_registrar_marcaje conviviendo —el
-- accidente que ya le pasó a este repo con fn_vacaciones_por_vencer el
-- 2026-08-25 (dos funciones con el mismo nombre y argumentos todos con
-- default, "function ... is not unique", el aviso de vacaciones dejó de
-- verse)—, y esta vez habría roto CADA marcaje de CADA persona en producción,
-- no solo una pantalla.
drop function if exists public.fn_registrar_marcaje(
  uuid, tipo_marca, timestamp with time zone, uuid, origen_marca, uuid, uuid, text
);

CREATE OR REPLACE FUNCTION public.fn_registrar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_timestamp_cliente timestamp with time zone, p_client_uuid uuid, p_origen origen_marca DEFAULT 'terminal'::origen_marca, p_terminal_id uuid DEFAULT NULL::uuid, p_sede_id uuid DEFAULT NULL::uuid, p_motivo_otro text DEFAULT NULL::text, p_confirmo_sin_refrigerio boolean DEFAULT NULL::boolean)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sede_id uuid;
  v_marcaje marcajes;
  v_existente marcajes;
  v_fecha date;
  v_esperado tipo_marca;
  v_caller_rol rol_usuario;
  v_terminal_auth uuid;
  v_ultimo_ts timestamptz;
  v_atrasada boolean;
  v_en_pagado boolean;     -- 0207: ¿esta marca cae dentro de un periodo ya pagado?
  v_cruzo_medianoche boolean := false;  -- 0240: ¿cierra una jornada del día anterior?
  v_jornada_abierta date;               -- 0240: y de qué día es esa jornada
  v_jornada_estado text;                -- 0320: ¿la cerró el robot o sigue abierta?
  v_sintetica marcajes;                 -- 0320: la salida_final que puso el auto-cierre
begin
  -- Idempotencia: reintentos offline con el mismo client_uuid no duplican.
  select * into v_existente from marcajes where client_uuid = p_client_uuid;
  if found then
    return v_existente;
  end if;

  if p_origen = 'terminal' then
    if p_terminal_id is null then
      raise exception 'p_terminal_id es obligatorio cuando origen = terminal';
    end if;
    select sede_id, auth_user_id into v_sede_id, v_terminal_auth
    from terminales where id = p_terminal_id and activo;
    if v_sede_id is null then
      raise exception 'terminal % no encontrado o inactivo', p_terminal_id;
    end if;
    if auth.uid() is not null and v_terminal_auth is not null and auth.uid() <> v_terminal_auth then
      raise exception 'el terminal autenticado no coincide con p_terminal_id';
    end if;
  else
    if p_sede_id is null then
      raise exception 'p_sede_id es obligatorio cuando origen != terminal';
    end if;
    select rol into v_caller_rol from personas where auth_user_id = auth.uid();
    if v_caller_rol is null or v_caller_rol not in ('admin', 'lider_do', 'supervisor_sede') then
      raise exception 'no autorizado para registrar marcajes con origen %', p_origen;
    end if;
    if v_caller_rol = 'supervisor_sede' then
      if not exists (
        select 1 from personas
        where auth_user_id = auth.uid() and sede_base_id = p_sede_id
      ) then
        raise exception 'un supervisor_sede solo puede corregir marcajes de su propia sede';
      end if;
    end if;
    v_sede_id := p_sede_id;
  end if;

  if p_tipo = 'salida_otro' and (p_motivo_otro is null or length(trim(p_motivo_otro)) < 3) then
    raise exception 'motivo_otro es obligatorio para salida_otro';
  end if;

  v_fecha := (p_timestamp_cliente at time zone 'America/Lima')::date;

  -- ⇩⇩⇩ CAMBIO 0240 ⇩⇩⇩ LA JORNADA MANDA, NO EL CALENDARIO.
  --
  -- Quien cierra tienda a las 00:30 no podía marcar su salida: el sistema miraba
  -- el día NUEVO, no encontraba ninguna entrada y esperaba una `entrada`. La
  -- salida real se rechazaba en la puerta —medido: «tipo salida_final no válido
  -- en el estado actual (se esperaba entrada)»— y de ahí salían DOS errores de
  -- signo contrario: el día anterior lo cerraba el cron con la hora programada
  -- (le faltaban 1.5 h de las que trabajó) y nacía un día fantasma que el cron
  -- cerraba en 22.5 h. En una sola noche: 30.5 h registradas donde hubo 9.5.
  --
  -- Con esto, esa marca pertenece a la JORNADA que sigue abierta, aunque el
  -- calendario ya haya cambiado de día. No se inventa nada: se usan las dos
  -- marcas reales y se dice que son del mismo turno, que es como lo cuenta una
  -- persona — «anoche salí tarde».
  --
  -- SOLO PARA SALIDAS Y RETORNOS. Una `entrada` a las 00:30 abre un día nuevo
  -- como siempre: puede ser alguien empezando su turno, y confundir eso sería
  -- cambiar un error por otro.
  --
  -- EL TOPE DE 16 HORAS es lo que impide que una jornada que alguien olvidó
  -- cerrar se coma el día siguiente. Pasado ese tope, la marca vuelve a ser del
  -- día que dice el calendario y el auto-cierre hace su trabajo.
  if p_tipo::text like 'salida\_%' escape '\' or p_tipo::text like 'retorno\_%' escape '\' then
    -- ⇩⇩⇩ CAMBIO 0320 ⇩⇩⇩ TAMBIÉN SI EL ROBOT LLEGÓ PRIMERO.
    --
    -- Acá decía `j.estado in ('abierta', 'en_pausa')`, y con eso la promesa nº1
    -- de la 0240 —«que quien cierra tienda pasada la medianoche PUEDA marcar su
    -- salida»— solo se cumplía durante las 3 horas siguientes a su hora
    -- programada. `fn_auto_cierre` corre cada 15 minutos y cierra cualquier
    -- jornada abierta pasado ese plazo; a partir de ahí esta rama no encontraba
    -- nada y la salida REAL se rechazaba con el mismo error que la 0240 cita en
    -- su encabezado como lo que resuelve.
    --
    -- Medido el 2026-08-26 contra el Postgres local, horario 13:00–21:00:
    -- trabajó de 13:00 a 00:30 —11,50 h— y le quedaban 8,00 h puestas por el
    -- robot. Su salida: «tipo salida_final no válido en el estado actual (se
    -- esperaba entrada)». Y el agravante: el terminal le ofrecía ENTRADA, se
    -- aceptaba, y nacía el día fantasma que la 0240 existe para evitar.
    --
    -- `auto_cerrada_pendiente` se llama así justamente porque el robot ADIVINÓ:
    -- puso la hora programada, no la real. Una marca de una persona es mejor
    -- evidencia que una suposición, y por eso gana.
    select j.fecha, j.estado into v_jornada_abierta, v_jornada_estado
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha < v_fecha
      and j.estado in ('abierta', 'en_pausa', 'auto_cerrada_pendiente')
      and j.entrada_ts is not null
      and p_timestamp_cliente <= j.entrada_ts + interval '16 hours'
    order by j.fecha desc
    limit 1;

    if found then
      v_fecha := v_jornada_abierta;
      v_cruzo_medianoche := true;
    end if;
  end if;

  -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ ¿Cae dentro de un periodo ya pagado?
  -- Se calcula acá arriba, una sola vez, porque hace falta en los DOS caminos
  -- por los que esta función deja una marca: el insert del final y la
  -- reconciliación del auto-cierre, que retorna antes de llegar a él.
  --
  -- Lo que NO se hace con esto es rechazar. La 0068 ya lo dejó escrito: la
  -- terminal reintenta seis veces y acaba descartando la marca. Perder el
  -- registro de alguien que sí estuvo es peor que un día pagado que no cuadra.
  select fn_fecha_en_periodo_pagado(v_fecha, p_persona_id) into v_en_pagado;

  -- ⇩⇩⇩ CAMBIO 0320 ⇩⇩⇩ LA MARCA REAL GANA A LA QUE ADIVINÓ EL ROBOT.
  --
  -- Adoptar la jornada no basta: la `salida_final` sintética del auto-cierre
  -- sigue ahí, así que `fn_siguiente_tipo_esperado` volvería a esperar una
  -- `entrada` y la salida real se rechazaría igual. Hay que retirarla.
  --
  -- SE ANULA, NO SE BORRA — los marcajes son append-only, y esto deja su rastro
  -- en `correcciones_auditoria` como cualquier otra corrección.
  --
  -- ES MUY ACOTADO, y cada condición está por algo:
  --   · `origen = 'auto_cierre'`  → solo lo que puso el robot. Una marca de una
  --     persona no se toca nunca por esta vía.
  --   · `estado_revision <> 'revisada'` → si alguien de DO ya la confirmó, es
  --     una decisión humana y manda sobre esto.
  --   · `not v_en_pagado` → en un mes ya pagado no se cambia nada. Ahí se
  --     mantiene el comportamiento de antes, que rechaza: es preferible que la
  --     marca no entre a que cambie sola una planilla que ya salió del banco.
  --     Se corrige reabriendo el periodo, como todo lo demás.
  --   · el tope de 16 h de la 0240 sigue mandando: viene heredado del `select`
  --     de arriba, que es el único que puede poner `v_jornada_estado`.
  --
  -- `corregido_por` es la propia persona porque el terminal no tiene sesión
  -- —marca sin PIN, y es a propósito— y porque es honesto: su marca real es la
  -- evidencia que corrige la suposición.
  if v_jornada_estado = 'auto_cerrada_pendiente' and not v_en_pagado then
    select * into v_sintetica
    from marcajes m
    where m.persona_id = p_persona_id
      and m.tipo = 'salida_final'
      and m.origen = 'auto_cierre'
      and m.anulada_at is null
      and m.estado_revision is distinct from 'revisada'
      and fn_fecha_de_jornada(m.timestamp_marca, m.fecha_jornada) = v_fecha
    order by m.timestamp_marca desc
    limit 1
    for update;

    if found then
      update marcajes
         set anulada_at     = now(),
             anulada_por    = p_persona_id,
             anulada_motivo = 'La persona marcó su salida real: el auto-cierre había '
                              || 'supuesto la hora programada (0320).'
       where id = v_sintetica.id;

      insert into correcciones_auditoria
        (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo,
         corregido_por, motivo)
      values (v_sintetica.id, p_persona_id, 'auto_cierre_reemplazado',
              'salida_final @ ' || v_sintetica.timestamp_marca::text,
              'salida_final @ ' || p_timestamp_cliente::text,
              p_persona_id,
              'Cerró tienda después de la ventana del auto-cierre y marcó su '
              || 'salida real. La marca del robot se retira (0320).');
    end if;
  end if;

  -- ¿LLEGA ATRASADA? Su hora es anterior a la última ya registrada de ese día:
  -- viene de la cola offline. No se le puede aplicar la validación de secuencia
  -- (se juzgaría contra un presente que no le corresponde, se rechazaría, y la
  -- terminal acabaría borrándola tras 6 reintentos). Se acepta siempre.
  select max(timestamp_marca) into v_ultimo_ts
  from marcajes
  where persona_id = p_persona_id
    and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
    and anulada_at is null;

  v_atrasada := v_ultimo_ts is not null and p_timestamp_cliente < v_ultimo_ts;

  -- Marcas EN VIVO: candado anti-doble-marcado de siempre, intacto.
  if p_origen = 'terminal' and not v_atrasada then
    v_esperado := fn_siguiente_tipo_esperado(p_persona_id, v_fecha);
    if v_esperado is not null and v_esperado <> p_tipo then
      raise exception 'tipo % no válido en el estado actual (se esperaba %)', p_tipo, v_esperado;
    end if;
    if v_esperado is null and p_tipo not in (
      'salida_final', 'salida_almuerzo', 'salida_personal', 'salida_tramite', 'salida_medico', 'salida_otro'
    ) then
      raise exception 'tipo % no válido: la jornada ya está cerrada o requiere elegir un tipo de salida', p_tipo;
    end if;
  end if;

  -- Reconciliación: una salida_final real que llega después de un auto-cierre
  -- sintético del mismo día reemplaza el registro sintético, no lo duplica.
  if p_tipo = 'salida_final' then
    select * into v_existente
    from marcajes
    where persona_id = p_persona_id
      and tipo = 'salida_final'
      and origen = 'auto_cierre'
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and anulada_at is null;

    if found then
      update marcajes set
        timestamp_marca = p_timestamp_cliente,
        origen = p_origen,
        -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ Este es el camino delicado, y el que se olvida:
        -- cambia la HORA de una marca que ya existía dentro del periodo pagado,
        -- y además ponía 'normal' a secas, borrando cualquier sello previo.
        estado_revision = case when v_en_pagado then 'pendiente_revision'::estado_revision
                               else 'normal'::estado_revision end,
        client_uuid = p_client_uuid,
        terminal_id = p_terminal_id,
        server_received_at = now(),
        -- ⇩⇩⇩ CAMBIO 0350 ⇩⇩⇩ este camino también deja un marcaje real de
        -- salida_final: si el terminal preguntó, la respuesta se guarda igual
        -- que en el camino del insert de abajo.
        confirmo_sin_refrigerio = p_confirmo_sin_refrigerio
      where id = v_existente.id
      returning * into v_marcaje;

      return v_marcaje;
    end if;
  end if;

  insert into marcajes (
    client_uuid, persona_id, sede_id, terminal_id, tipo, motivo_otro, timestamp_marca, origen,
    -- 0240: solo lleva valor cuando la marca pertenece a la jornada de OTRO día.
    -- Null en todo lo demás, que es el 99 % de los casos: así la columna dice
    -- «esto es una excepción» en vez de repetir lo que el timestamp ya sabe.
    fecha_jornada,
    -- 0350: null salvo que el terminal haya preguntado (ver encabezado).
    confirmo_sin_refrigerio
  ) values (
    p_client_uuid, p_persona_id, v_sede_id, p_terminal_id, p_tipo, p_motivo_otro, p_timestamp_cliente, p_origen,
    case when v_cruzo_medianoche then v_fecha else null end,
    p_confirmo_sin_refrigerio
  )
  returning * into v_marcaje;

  -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ La marca entra, pero no entra muda.
  -- Solo se sella ELLA y no el día entero: el día ya se pagó y su jornada es
  -- correcta como foto de lo que se pagó — lo anómalo es la recién llegada.
  if v_en_pagado then
    update marcajes set estado_revision = 'pendiente_revision' where id = v_marcaje.id;
    select * into v_marcaje from marcajes where id = v_marcaje.id;
  end if;

  -- ¿El día quedó IMPOSIBLE al ordenarlo por hora? Entonces se sella para que
  -- aparezca en Correcciones. No se pierde nada, pero deja de estar en silencio.
  -- Solo se sella si de verdad quedó roto: una marca atrasada que encaja bien
  -- en la secuencia no genera ninguna alarma.
  if fn_dia_incoherente(p_persona_id, v_fecha) then
    update marcajes
      set estado_revision = 'pendiente_revision'
    where persona_id = p_persona_id
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and estado_revision = 'normal';
    select * into v_marcaje from marcajes where id = v_marcaje.id;
  end if;

  return v_marcaje;
end;
$function$;

grant execute on function fn_registrar_marcaje(uuid, tipo_marca, timestamptz, uuid, origen_marca, uuid, uuid, text, boolean) to authenticated;
revoke execute on function fn_registrar_marcaje(uuid, tipo_marca, timestamptz, uuid, origen_marca, uuid, uuid, text, boolean) from public, anon;
