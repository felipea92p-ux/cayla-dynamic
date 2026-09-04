-- ============================================================================
-- 0366 — Dos toques seguidos en el terminal no dejan dos marcas
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que una integrante que toca «Entrada» (o «Salida») dos veces
-- seguidas en el terminal —porque la pantalla tardó, porque el dedo rebotó,
-- porque no vio la confirmación— deje UNA marca, no dos. El segundo toque
-- devuelve la misma fila que el primero, igual que hoy hace un reintento con
-- el mismo client_uuid: para el terminal es un éxito, y lo es.
--
-- EL DEFECTO (hallazgo 21 de la auditoría del 2026-09-03/04): la idempotencia
-- por client_uuid protege los reintentos del MISMO envío, no un doble toque
-- físico. Cada toque genera su propio client_uuid, las dos llamadas llegan
-- casi a la vez, las dos ven «no hay entrada hoy» antes de que la otra
-- escriba, y quedan dos entradas (8:59 y 9:00). Incidencias muestra una marca
-- huérfana y las horas se confunden. Y para salida_final el hueco es más ancho
-- todavía: con la jornada cerrada, fn_siguiente_tipo_esperado devuelve null y
-- salida_final está en la lista de tipos que se aceptan con null, así que un
-- doble toque en la salida dejaba DOS salidas finales sin ninguna carrera de
-- por medio — bastaba con tocar dos veces.
--
-- QUÉ ASUME:
--   · Que una llamada RPC de Supabase es una transacción: el candado de
--     transacción se toma al entrar y se suelta al commit, así que dos
--     llamadas de la MISMA persona se ponen en fila, y cuando la segunda
--     empieza a leer ya ve lo que escribió la primera (read committed: su
--     select arranca después del commit de la otra). Personas distintas usan
--     claves distintas y no se estorban. Es el mismo candado que ya usa
--     fn_set_salario desde la 0019 (`salario:` || persona).
--   · Que ningún tipo de marca puede repetirse DE VERDAD en dos minutos:
--     entrada→entrada exige un día cerrado entre medias; salida_X→retorno_X→
--     salida_X en 120 segundos no ocurre; y salida_final→salida_final es
--     precisamente el hueco que la máquina de estados deja abierto. Por eso la
--     ventana es de dos minutos y no de treinta segundos: cubre un terminal
--     lento o una cola offline que reenvía, y sigue sin alcanzar a nada real.
--   · Y que un toque repetido lo es de la ÚLTIMA marca: si entre las dos hubo
--     otra marca viva de la persona —salió, volvió y salió otra vez en 90 s—,
--     la segunda es real y no se dedupe. Sin esa condición la revisión del
--     paquete midió que se devolvía la primera salida y la persona quedaba
--     «dentro» estando fuera; su retorno siguiente fallaba y el terminal lo
--     apartaba tras seis reintentos.
--
-- POR QUÉ SE ELIGIÓ ASÍ:
--   · Solo para origen = 'terminal'. Una corrección la hace una persona con
--     sesión, a propósito, y hoy tampoco pasa por la máquina de estados: si un
--     admin registra dos entradas a 30 segundos, eso es una decisión suya (o
--     un error suyo, con su rastro en correcciones_auditoria) y no se toca.
--   · Se DEVUELVE la marca ya existente en vez de lanzar. El terminal
--     reintenta seis veces un error y acaba descartando la marca; un éxito
--     silencioso es exactamente lo que un doble toque significa —«ya está
--     marcado»—, y es la misma semántica que la idempotencia por client_uuid
--     que esta función ya tenía. El terminal solo mira `error` (ver
--     apps/web/lib/terminal/enviar-marcaje.ts), no el cuerpo devuelto.
--   · Solo se dedupe contra otra marca DEL TERMINAL. Una salida_final del
--     robot (auto_cierre) a dos minutos de la real no es un toque repetido:
--     es la que la 0320 y la reconciliación de abajo tienen que REEMPLAZAR, y
--     si la búsqueda la devolviera, la marca real de la persona se perdería.
--   · El candado va ANTES de la idempotencia por client_uuid, para que dos
--     reintentos con el mismo client_uuid tampoco choquen entre sí contra la
--     unique de client_uuid: el segundo espera, y al entrar ya la encuentra.
--
-- QUÉ NO CAMBIA: la firma (9 parámetros, la de la 0353 — por eso no hay drop),
-- la máquina de estados, la 0207 (periodo pagado), la 0240 (medianoche), la
-- 0320 (la marca real gana al robot), la 0353 (confirmo_sin_refrigerio), el
-- camino de marcas atrasadas de la cola offline ni las correcciones. Todo el
-- cuerpo es el de la 0353 byte a byte salvo los dos bloques marcados
-- «CAMBIO 0366».
--
-- SE REVIERTE: `create or replace` con el cuerpo de la 0353 (sección 2).
--
-- VIGENTE EN: 0353_confirmacion_de_jornada_completa_al_marcar_salida.sql,
-- confirmado con donde-vive.sh el 2026-09-04.
-- md5 de partida (Postgres LOCAL): 572a2183c0c5f6f6ccc1df03cd1154da
--                 sin comentarios: ad5f52fea3e9d755acfc8a0b85b06e44
-- Antes de pegar esto en el SQL Editor, vuelve a pedirle el md5 a PRODUCCIÓN
-- con `./scripts/donde-vive.sh fn_registrar_marcaje` — esta función tiene ya
-- nueve versiones y varias sesiones trabajan a la vez sobre el mismo árbol.
-- Si producción no coincide con ninguno de los dos md5 de arriba, PARA.
-- ============================================================================

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
  -- ⇩⇩⇩ CAMBIO 0366 ⇩⇩⇩ CANDADO DE TRANSACCIÓN POR PERSONA.
  --
  -- Dos toques seguidos llegan como dos llamadas RPC casi simultáneas, y cada
  -- llamada es su propia transacción. Sin esto, las dos leen el día ANTES de
  -- que la otra escriba, las dos pasan la máquina de estados, y quedan dos
  -- marcas. Con esto, la segunda espera a que la primera haga commit y recién
  -- entonces lee: ya ve la marca de la primera, y el bloque de abajo se la
  -- devuelve en vez de insertar otra.
  --
  -- La clave lleva el id de la persona: personas distintas no se estorban, y
  -- dos llamadas de la misma persona se ponen en fila. Se suelta solo al
  -- terminar la transacción, que es lo que se quiere. Va antes incluso de la
  -- idempotencia por client_uuid, para que dos reintentos con el MISMO
  -- client_uuid tampoco choquen entre sí contra la unique de esa columna.
  perform pg_advisory_xact_lock(hashtext('fn_registrar_marcaje:' || p_persona_id::text));

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

  -- ⇩⇩⇩ CAMBIO 0366 ⇩⇩⇩ DOS TOQUES SEGUIDOS SON LA MISMA MARCA.
  --
  -- Si esta persona ya tiene, del terminal y sin anular, una marca del MISMO
  -- tipo a dos minutos o menos de esta, esta es un toque repetido: se devuelve
  -- aquella, no se inserta ni se lanza. Misma semántica que la idempotencia
  -- por client_uuid de arriba — el segundo toque ES la misma marca.
  --
  -- POR QUÉ DOS MINUTOS: ningún tipo puede repetirse de verdad en ese plazo.
  -- entrada→entrada exige un día cerrado entre medias; salida_X→retorno_X→
  -- salida_X en 120 s no existe; y salida_final→salida_final es justamente el
  -- hueco que la máquina de estados deja abierto (con la jornada cerrada,
  -- v_esperado es null y salida_final se acepta con null). Dos minutos cubren
  -- un terminal lento o una cola offline que reenvía, y no alcanzan a nada
  -- real.
  --
  -- Y NADA ENTRE MEDIAS: si entre aquella marca y esta hay OTRA marca viva de
  -- la persona (salida_personal 10:00:00 → retorno_personal 10:00:40 →
  -- salida_personal 10:01:30), la tercera no es un rebote: la persona volvió a
  -- salir. Sin esta condición se devolvía la de las 10:00 y la persona quedaba
  -- «dentro» estando fuera — medido en la revisión del paquete. Con ella,
  -- «mismo tipo a dos minutos» pasa a ser «toque repetido de la ÚLTIMA marca»,
  -- que es lo que el encabezado promete. Un doble toque nunca tiene nada en
  -- medio, así que el alcance del hallazgo 21 no se estrecha.
  --
  -- POR QUÉ SOLO TERMINAL, y solo contra marcas del terminal: una corrección la
  -- hace una persona con sesión, a propósito, y hoy tampoco pasa por la
  -- máquina de estados — su comportamiento no se toca. Y la salida_final del
  -- robot (auto_cierre) no es un toque: es lo que la 0320 y la reconciliación
  -- de más abajo tienen que reemplazar por la marca real, no lo que hay que
  -- devolver en su lugar.
  --
  -- POR QUÉ DEVOLVER EN VEZ DE LANZAR: el terminal reintenta seis veces un
  -- error y acaba descartando la marca. Un éxito silencioso es lo que un doble
  -- toque significa —«ya está marcado»—, y el terminal solo mira `error`.
  if p_origen = 'terminal' then
    select * into v_existente
    from marcajes m
    where m.persona_id = p_persona_id
      and m.tipo = p_tipo
      and m.origen = 'terminal'
      and m.anulada_at is null
      and m.timestamp_marca between p_timestamp_cliente - interval '2 minutes'
                                and p_timestamp_cliente + interval '2 minutes'
      and not exists (
        select 1 from marcajes x
        where x.persona_id = p_persona_id
          and x.anulada_at is null
          and x.timestamp_marca > least(m.timestamp_marca, p_timestamp_cliente)
          and x.timestamp_marca < greatest(m.timestamp_marca, p_timestamp_cliente)
      )
    order by greatest(m.timestamp_marca - p_timestamp_cliente,
                      p_timestamp_cliente - m.timestamp_marca)
    limit 1;
    if found then
      return v_existente;
    end if;
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
        -- ⇩⇩⇩ CAMBIO 0353 ⇩⇩⇩ este camino también deja un marcaje real de
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
    -- 0353: null salvo que el terminal haya preguntado (ver encabezado).
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

insert into migraciones_aplicadas (numero, nombre)
values (366, 'dos_toques_seguidos_no_dejan_dos_marcas')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
-- El cuerpo nuevo lleva el marcador y el candado; el de la 0353 no los tenía.
-- Y sigue habiendo UNA sola fn_registrar_marcaje: la firma no cambió.
select
  position('CAMBIO 0366' in p.prosrc) > 0                as tiene_el_cambio,
  position('pg_advisory_xact_lock' in p.prosrc) > 0      as tiene_el_candado,
  (select count(*) from pg_proc where proname = 'fn_registrar_marcaje') as una_sola_version
from pg_proc p
where p.proname = 'fn_registrar_marcaje';
