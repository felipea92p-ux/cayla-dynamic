-- ============================================================================
-- 0068 — Marcas que llegan tarde: nunca se pierden, y el día se SELLA si quedó roto
-- ----------------------------------------------------------------------------
-- EL PROBLEMA (dos bugs encadenados, hallados el 23/07/2026 con el día de una
-- persona que mostraba DOS "salida a almuerzo" seguidas):
--
--   Bug 1 · fn_registrar_marcaje valida la marca nueva contra la ÚLTIMA marca
--   del día, pero nunca mira SI LA MARCA QUE LLEGA ES DE AHORA O DE HACE RATO.
--   Una marca hecha sin señal a las 14:11 que se sincroniza a las 20:00 se juzga
--   contra un presente que ya no le corresponde.
--
--   Bug 2 (peor, invisible) · cuando esa validación la RECHAZA, la cola de la
--   terminal reintenta; a los 6 intentos BORRABA la marca de IndexedDB sin dejar
--   rastro. Como el rechazo por secuencia es determinista (siempre falla igual),
--   se perdían marcas de asistencia REALES en silencio.
--
-- LA REGLA (deliberadamente precisa, para no generar falsas alarmas):
--   · Una marca ATRASADA no se valida por secuencia — se acepta siempre. Nunca
--     se pierde un dato que una persona hizo de verdad. Esto además corta la
--     cadena del Bug 2: sin rechazo, no hay reintentos, no hay borrado.
--   · Las marcas EN VIVO siguen con la validación estricta de siempre (el
--     candado anti-doble-marcado del terminal no se toca).
--   · Después de insertar, se revisa si el día quedó INCOHERENTE. Solo en ese
--     caso se sella con 'pendiente_revision'. Una marca que llega tarde pero
--     encaja bien en la secuencia NO ensucia nada: sin sello, sin ruido.
--
-- Reversible: soltar fn_dia_incoherente y restaurar fn_registrar_marcaje de 0002.
-- ============================================================================

-- ── ¿La jornada de esta persona, ordenada por hora, es POSIBLE? ──────────────
-- Camina el día marca por marca aplicando las mismas reglas del terminal.
-- Devuelve true si encuentra un paso imposible (dos salidas seguidas, un retorno
-- sin su salida, algo después del cierre, una entrada repetida…).
create or replace function fn_dia_incoherente(p_persona_id uuid, p_fecha date)
returns boolean
language plpgsql
stable
set search_path = public
as $$
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
$$;

grant execute on function fn_dia_incoherente(uuid, date) to authenticated;

-- ── fn_registrar_marcaje: idéntica a 0002 salvo el manejo de marcas atrasadas ─
create or replace function fn_registrar_marcaje(
  p_persona_id uuid,
  p_tipo tipo_marca,
  p_timestamp_cliente timestamptz,
  p_client_uuid uuid,
  p_origen origen_marca default 'terminal',
  p_terminal_id uuid default null,
  p_sede_id uuid default null,
  p_motivo_otro text default null
)
returns marcajes
language plpgsql
security definer
set search_path = public
as $$
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
    and (timestamp_marca at time zone 'America/Lima')::date = v_fecha;

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
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha;

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
$$;

grant execute on function fn_registrar_marcaje to authenticated;

-- ── Los días sellados, listos para corregir ─────────────────────────────────
-- Sin esto el sello sería inútil: nadie va a revisar persona por persona
-- adivinando qué día quedó roto. Esta lista es la que los hace visibles.
create or replace function fn_dias_por_revisar(p_limite int default 50)
returns table (persona_id uuid, nombre text, sede text, fecha date, marcas int)
language sql
stable
security definer
set search_path = public
as $$
  select m.persona_id,
         (p.nombres || ' ' || p.apellidos) as nombre,
         s.codigo as sede,
         (m.timestamp_marca at time zone 'America/Lima')::date as fecha,
         count(*)::int as marcas
  from marcajes m
  join personas p on p.id = m.persona_id
  join sedes s on s.id = p.sede_base_id
  where m.estado_revision = 'pendiente_revision'
    and (fn_es_admin_o_lider()
         or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona()))
  group by m.persona_id, p.nombres, p.apellidos, s.codigo,
           (m.timestamp_marca at time zone 'America/Lima')::date
  order by 4 desc, 2
  limit greatest(p_limite, 1);
$$;

grant execute on function fn_dias_por_revisar(int) to authenticated;

notify pgrst, 'reload schema';
