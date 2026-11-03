-- ============================================================================
-- 0583 — El almacén es solo de las tiendas
-- ----------------------------------------------------------------------------
-- DE DÓNDE SALE. Felipe (2026-11-03): «solo los que son tienda deben tener la
--   opción de ir al almacén, no pueden habilitar la opción de ir al almacén a los
--   de oficina, central o taller. Que sean únicos para tienda.»
--
-- QUÉ PROMETE. `fn_registrar_cambio_ubicacion` (0580) se niega si la sede donde
--   se registra NO es `tienda` (`sedes.tipo`, 0099), o si la sede base de la
--   persona no lo es. Vale para los dos orígenes: terminal y panel. El terminal
--   ya no ofrece el botón en esos casos (mismo PR); esto es lo que lo hace
--   cumplir aunque alguien llame a la función por otro lado.
--
-- QUÉ NO HACE. No borra ni anula nada: lo que ya se registró queda (hoy la
--   tabla está vacía en producción, medido el 2026-11-02). No toca
--   `fn_ubicaciones_del_dia` ni `fn_anular_cambio_ubicacion`: anular un registro
--   viejo de una sede que dejó de ser tienda tiene que seguir siendo posible.
--   Lo planificado (`puestos_planificados`, 0579) es de Turnos y no se toca.
--
-- POR QUÉ LAS DOS SEDES. La del terminal decide si allí hay almacén y piso que
--   cubrir. La base de la persona decide si es del equipo de tienda: alguien de
--   Central con `visible_todas_sedes` que marque en una tienda no va «al
--   almacén», está de visita.
--
-- QUÉ ASUME. La 0580 pegada tal cual: md5 de partida medido en PRODUCCIÓN el
--   2026-11-02 — `d305303146d517fbc36325701260a5e2`, 3 829 caracteres, sin \r —.
--   Si el cuerpo vigente es otro, la migración PARA sin tocar nada.
--
-- CÓMO SE REVIERTE. Volver a pegar la función tal cual está en la 0580.
-- ============================================================================

-- ── 0 · Precondición: el cuerpo vigente es el de la 0580 ───────────────────
do $$
declare
  v_md5 text;
  v_len int;
begin
  select md5(prosrc), length(prosrc) into v_md5, v_len
    from pg_proc where proname = 'fn_registrar_cambio_ubicacion' and pronamespace = 'public'::regnamespace;
  if v_md5 is null then
    raise exception '0583 · PARA: fn_registrar_cambio_ubicacion no existe. Falta la 0580.';
  end if;
  if v_md5 not in ('d305303146d517fbc36325701260a5e2', '25ae1cbc2a75b16ac99fd1d2ca3cb94c') then
    raise exception '0583 · PARA: producción tiene otra versión de fn_registrar_cambio_ubicacion (md5 %, % caracteres). No se aplica nada.', v_md5, v_len;
  end if;
end;
$$;

create or replace function public.fn_registrar_cambio_ubicacion(
  p_persona_id       uuid,
  p_ubicacion        text,
  p_timestamp_cambio timestamptz,
  p_client_uuid      uuid,
  p_origen           text        default 'terminal',
  p_terminal_id      uuid        default null,
  p_vuelve_previsto  timestamptz default null,
  p_sede_id          uuid        default null
)
returns public.cambios_ubicacion
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existente     cambios_ubicacion;
  v_nuevo         cambios_ubicacion;
  v_sede_id       uuid;
  v_terminal_auth uuid;
  v_autor         uuid;
begin
  if p_persona_id is null or p_ubicacion is null or p_timestamp_cambio is null or p_client_uuid is null then
    raise exception 'persona, ubicación, hora y client_uuid son obligatorios';
  end if;
  if p_ubicacion not in ('tienda', 'almacen') then
    raise exception 'ubicación % no válida (tienda o almacen)', p_ubicacion;
  end if;
  if p_origen is null or p_origen not in ('terminal', 'panel') then
    raise exception 'origen % no válido (terminal o panel)', p_origen;
  end if;

  -- Idempotencia: la cola reintenta con el mismo client_uuid. El candado evita
  -- que dos reintentos simultáneos choquen contra la unique.
  perform pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 580));
  select * into v_existente from cambios_ubicacion where client_uuid = p_client_uuid;
  if found then
    if v_existente.persona_id is distinct from p_persona_id then
      raise exception 'client_uuid % ya usado por otra persona', p_client_uuid;
    end if;
    return v_existente;
  end if;

  if p_origen = 'terminal' then
    if p_terminal_id is null then
      raise exception 'p_terminal_id es obligatorio cuando origen = terminal';
    end if;
    select sede_id, auth_user_id into v_sede_id, v_terminal_auth
      from terminales where id = p_terminal_id and activo;
    if not found then
      raise exception 'terminal % no encontrado o inactivo', p_terminal_id;
    end if;
    -- Mismo texto que fn_registrar_marcaje: la cola del terminal lo reconoce
    -- como desajuste de sesión, no como rechazo del registro.
    if auth.uid() is not null and auth.uid() is distinct from v_terminal_auth then
      raise exception 'el terminal autenticado no coincide con p_terminal_id';
    end if;
    -- Quién puede marcar en esta sede lo dice UNA regla desde la 0370
    -- (fn_persona_marca_en_sede), la misma del roster y del candado de marcajes.
    if not exists (select 1 from personas p where p.id = p_persona_id and p.estado = 'activo')
       or fn_persona_marca_en_sede(p_persona_id, v_sede_id) is not true
    then
      raise exception 'esa persona no está en la lista de este terminal';
    end if;
  else
    if p_sede_id is null then
      raise exception 'p_sede_id es obligatorio cuando origen = panel';
    end if;
    select id into v_autor from personas where auth_user_id = auth.uid();
    if v_autor is null
       or (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and fn_sede_actual_persona() = p_sede_id)) is not true
    then
      raise exception 'Sin permiso para registrar ubicaciones de esa sede';
    end if;
    v_sede_id := p_sede_id;
  end if;

  -- CAMBIO 0583 · El almacén es solo de las tiendas. Ni la sede donde se marca
  -- ni la sede base de la persona pueden ser central o taller: en Central y en
  -- el Taller no hay «piso» que cubrir, y sus terminales no ofrecen el botón.
  -- Va DESPUÉS de la idempotencia: un reintento de algo ya guardado sigue
  -- contestando con la fila, aunque la sede cambiara de tipo en el medio.
  if (select s.tipo from sedes s where s.id = v_sede_id) is distinct from 'tienda' then
    raise exception 'El almacén solo se marca en una tienda: esta sede no es tienda.';
  end if;
  if (select s.tipo from personas p join sedes s on s.id = p.sede_base_id where p.id = p_persona_id)
     is distinct from 'tienda' then
    raise exception 'El almacén es solo para el equipo de tienda: esta persona es de central o taller.';
  end if;

  -- Un reloj de terminal adelantado no puede escribir el futuro. El pasado sí
  -- se acepta: es la cola sin conexión subiendo lo que se hizo de verdad.
  if p_timestamp_cambio > now() + interval '5 minutes' then
    raise exception 'la hora del cambio (%) está en el futuro', p_timestamp_cambio;
  end if;
  if p_vuelve_previsto is not null then
    if p_ubicacion <> 'almacen' then
      raise exception 'vuelve_previsto solo va con almacen';
    end if;
    if p_vuelve_previsto <= p_timestamp_cambio or p_vuelve_previsto > p_timestamp_cambio + interval '16 hours' then
      raise exception 'vuelve_previsto fuera de rango';
    end if;
  end if;

  insert into cambios_ubicacion
    (client_uuid, persona_id, sede_id, terminal_id, ubicacion, timestamp_cambio,
     vuelve_previsto, origen, registrado_por)
  values
    (p_client_uuid, p_persona_id, v_sede_id,
     case when p_origen = 'terminal' then p_terminal_id end,
     p_ubicacion, p_timestamp_cambio, p_vuelve_previsto, p_origen, v_autor)
  returning * into v_nuevo;

  return v_nuevo;
end;
$$;


insert into migraciones_aplicadas (numero, nombre)
values (583, 'el_almacen_es_solo_de_las_tiendas')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ───────────────────────────────────────────────────────────
-- Debe dar: tiene_el_cambio t · md5 de llegada · «583 · el_almacen_es_solo_de_las_tiendas».
select position('CAMBIO 0583' in prosrc) > 0 as tiene_el_cambio,
       md5(prosrc) as md5_llegada, length(prosrc) as largo,
       (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 583) as registro
  from pg_proc where proname = 'fn_registrar_cambio_ubicacion' and pronamespace = 'public'::regnamespace;
