-- ============================================================================
-- 0082 — El resto del sistema también sabe que una marca puede estar anulada
-- ----------------------------------------------------------------------------
-- PROMETE: que ninguna función del sistema siga contando una marca anulada como
--   si estuviera viva.
--
-- ASUME: la 0081, que añadió marcajes.anulada_at y enseñó a fn_recalcular_jornada
--   a ignorar las anuladas.
--
-- EL HUECO QUE CIERRA. La 0081 arregló el cálculo del pago, pero SEIS funciones
--   más leen la tabla de marcajes y ninguna sabía nada de la anulación. El
--   resultado habría sido un sistema que paga bien y a la vez ve una realidad
--   vieja en todo lo demás — el peor tipo de fallo, porque cada parte parece
--   correcta por separado:
--
--   fn_registrar_marcaje       Decide si la próxima marca es entrada o salida
--                              mirando el día. Con una entrada anulada, el
--                              terminal seguiría creyendo que la persona está
--                              dentro y le negaría marcar su entrada.
--   fn_siguiente_tipo_esperado Lo mismo, en la pantalla del terminal: ofrecería
--                              el botón equivocado.
--   fn_dia_incoherente         El sello de "secuencia imposible" seguiría puesto
--                              en un día que ya se arregló anulando las marcas
--                              sobrantes. Se arregla el día y sigue en rojo.
--   fn_auto_cierre             Cerraría el día usando la hora de una marca que
--                              ya no cuenta.
--   fn_ingresos                La fecha de ingreso de una persona sale de su
--                              primera marca. Si esa marca se anula, la fecha
--                              queda mal — y de ahí cuelgan vacaciones y CTS.
--   fn_dias_por_revisar        Seguiría pidiendo revisar días ya resueltos.
--
-- POR QUÉ ASÍ Y NO CON UNA VISTA. Se podría haber creado una vista
--   `marcajes_vivos` y apuntar todo ahí, pero eso deja dos nombres para la misma
--   cosa y la siguiente función que alguien escriba volverá a usar `marcajes` a
--   secas — el mismo olvido, otra vez. La condición se pone en cada consulta, que
--   es explícita y no se puede saltar sin verla.
--
-- CÓMO SE REVIERTE: `scripts/sql-manual/reverso_0082.sql` restaura las seis
--   funciones tal como estaban. Sin efecto sobre los datos.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_siguiente_tipo_esperado(p_persona_id uuid, p_fecha date)
 RETURNS tipo_marca
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_ultimo record;
  v_tiene_entrada boolean;
  v_tiene_salida_final boolean;
  v_pares jsonb := '{
    "salida_almuerzo": "retorno_almuerzo",
    "salida_personal": "retorno_personal",
    "salida_tramite": "retorno_tramite",
    "salida_medico": "retorno_medico",
    "salida_otro": "retorno_otro"
  }'::jsonb;
begin
  select exists(
    select 1 from marcajes
    where persona_id = p_persona_id
      and tipo = 'entrada'
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
      and anulada_at is null
  ) into v_tiene_entrada;

  if not v_tiene_entrada then
    return 'entrada';
  end if;

  select exists(
    select 1 from marcajes
    where persona_id = p_persona_id
      and tipo = 'salida_final'
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
      and anulada_at is null
  ) into v_tiene_salida_final;

  if v_tiene_salida_final then
    return null; -- jornada cerrada, ninguna acción válida
  end if;

  select tipo, timestamp_marca into v_ultimo
  from marcajes
  where persona_id = p_persona_id
    and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
  order by timestamp_marca desc
  limit 1;

  if v_pares ? v_ultimo.tipo::text then
    return (v_pares ->> v_ultimo.tipo::text)::tipo_marca;
  end if;

  return null; -- debe elegir tipo de salida — ambigüedad legítima, no se resuelve aquí
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_ingresos()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'persona_id', p.id,
    'fecha_ingreso', p.fecha_ingreso,
    'primera_entrada', pe.primera
  )), '[]'::jsonb)
  from personas p
  left join lateral (
    select (min(m.timestamp_marca) at time zone 'America/Lima')::date as primera
    from marcajes m where m.persona_id = p.id and m.anulada_at is null
  ) pe on true
  where fn_es_admin_o_lider();
$function$;

CREATE OR REPLACE FUNCTION public.fn_dias_por_revisar(p_limite integer DEFAULT 50)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, fecha date, marcas integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  order by 4 desc, 2
  limit greatest(p_limite, 1);
$function$;

CREATE OR REPLACE FUNCTION public.fn_dia_incoherente(p_persona_id uuid, p_fecha date)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  r record;
  v_estado text := 'sin_entrada';  -- sin_entrada | adentro | fuera | cerrado
  v_esperado text := null;         -- retorno que toca cuando está 'fuera'
  v_pares jsonb := '{
    "salida_almuerzo": "retorno_almuerzo",
    "salida_personal": "retorno_personal",
    "salida_tramite": "retorno_tramite",
    "salida_medico": "retorno_medico",
    "salida_otro": "retorno_otro"
  }'::jsonb;
begin
  for r in
    select tipo
    from marcajes
    where persona_id = p_persona_id
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
      and anulada_at is null
    order by timestamp_marca, id
  loop
    if v_estado = 'sin_entrada' then
      -- El día tiene que empezar por una entrada.
      if r.tipo <> 'entrada' then return true; end if;
      v_estado := 'adentro';

    elsif v_estado = 'cerrado' then
      -- Ya marcó salida final: cualquier cosa después es imposible.
      return true;

    elsif v_estado = 'fuera' then
      -- Salió temporalmente: lo único válido es SU retorno.
      if r.tipo::text <> v_esperado then return true; end if;
      v_estado := 'adentro';
      v_esperado := null;

    else -- 'adentro'
      if r.tipo = 'salida_final' then
        v_estado := 'cerrado';
      elsif v_pares ? r.tipo::text then
        v_estado := 'fuera';
        v_esperado := v_pares ->> r.tipo::text;
      else
        -- Entrada repetida, o un retorno sin salida previa.
        return true;
      end if;
    end if;
  end loop;

  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_auto_cierre()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_horas int;
  v_hoy_lima date := (now() at time zone 'America/Lima')::date;
  v_candidata record;
  v_ts_cierre timestamptz;
  v_cerradas int := 0;
begin
  select (valor #>> '{}')::int into v_horas from configuracion where clave = 'auto_cierre_horas';
  v_horas := coalesce(v_horas, 3);

  for v_candidata in
    select
      j.id as jornada_id,
      j.persona_id,
      j.fecha,
      j.sede_id,
      h.hora_salida
    from jornadas j
    -- cascada turno del día → horario_por_dia → legacy, igual que
    -- fn_recalcular_jornada, en vez de leer horarios_asignados.hora_salida directo
    left join lateral (
      select case
        when t.fecha is not null and t.es_descanso then null
        when t.fecha is not null then t.hora_salida
        when ha.horario_por_dia is not null
          then (ha.horario_por_dia -> extract(dow from j.fecha)::int::text ->> 's')::time
        else ha.hora_salida
      end as hora_salida
      from (select 1) uno
      left join turnos t on t.persona_id = j.persona_id and t.fecha = j.fecha
      left join lateral (
        select horario_por_dia, hora_salida
        from horarios_asignados
        where persona_id = j.persona_id
          and vigente_desde <= j.fecha
          and (vigente_hasta is null or vigente_hasta >= j.fecha)
        order by vigente_desde desc limit 1
      ) ha on true
    ) h on true
    where j.estado in ('abierta', 'en_pausa')
      and (
        (h.hora_salida is not null
          and now() >= ((j.fecha + h.hora_salida) at time zone 'America/Lima') + make_interval(hours => v_horas))
        or (h.hora_salida is null and j.fecha < v_hoy_lima)
      )
  loop
    if v_candidata.hora_salida is not null then
      v_ts_cierre := (v_candidata.fecha + v_candidata.hora_salida) at time zone 'America/Lima';
    else
      select max(timestamp_marca) into v_ts_cierre
      from marcajes
      where persona_id = v_candidata.persona_id
        and (timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha
        and anulada_at is null;
    end if;

    if v_ts_cierre is null then
      continue;
    end if;

    insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
    values (gen_random_uuid(), v_candidata.persona_id, v_candidata.sede_id, 'salida_final', v_ts_cierre, 'auto_cierre', 'pendiente_revision');

    insert into alertas (persona_id, tipo, canal, payload)
    values (
      v_candidata.persona_id,
      'auto_cierre',
      'push',
      jsonb_build_object('fecha', v_candidata.fecha, 'jornada_id', v_candidata.jornada_id, 'ts_cierre', v_ts_cierre)
    );

    v_cerradas := v_cerradas + 1;
  end loop;

  return v_cerradas;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_registrar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_timestamp_cliente timestamp with time zone, p_client_uuid uuid, p_origen origen_marca DEFAULT 'terminal'::origen_marca, p_terminal_id uuid DEFAULT NULL::uuid, p_sede_id uuid DEFAULT NULL::uuid, p_motivo_otro text DEFAULT NULL::text)
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
  v_ultimo_ts timestamptz;  -- NUEVO: hora de la última marca ya registrada del día
  v_atrasada boolean;       -- NUEVO: ¿esta marca llega fuera de orden?
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
        estado_revision = 'normal',
        client_uuid = p_client_uuid,
        terminal_id = p_terminal_id,
        server_received_at = now()
      where id = v_existente.id
      returning * into v_marcaje;

      return v_marcaje;
    end if;
  end if;

  insert into marcajes (
    client_uuid, persona_id, sede_id, terminal_id, tipo, motivo_otro, timestamp_marca, origen
  ) values (
    p_client_uuid, p_persona_id, v_sede_id, p_terminal_id, p_tipo, p_motivo_otro, p_timestamp_cliente, p_origen
  )
  returning * into v_marcaje;

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

-- Se re-declaran los permisos: desde la 0076 nada nace abierto, y una función
-- reemplazada sin su grant se manifiesta como "permission denied for function".
grant execute on function fn_siguiente_tipo_esperado(uuid, date) to authenticated;
grant execute on function fn_ingresos() to authenticated;
grant execute on function fn_dias_por_revisar(integer) to authenticated;
grant execute on function fn_dia_incoherente(uuid, date) to authenticated;
grant execute on function fn_auto_cierre() to authenticated;
grant execute on function fn_registrar_marcaje(uuid, tipo_marca, timestamptz, uuid, origen_marca, uuid, uuid, text) to authenticated;
revoke execute on function fn_registrar_marcaje(uuid, tipo_marca, timestamptz, uuid, origen_marca, uuid, uuid, text) from public, anon;
revoke execute on function fn_siguiente_tipo_esperado(uuid, date) from public, anon;
revoke execute on function fn_ingresos() from public, anon;
revoke execute on function fn_dias_por_revisar(integer) from public, anon;
revoke execute on function fn_dia_incoherente(uuid, date) from public, anon;
revoke execute on function fn_auto_cierre() from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (82, 'todo_el_sistema_conoce_las_anuladas')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
