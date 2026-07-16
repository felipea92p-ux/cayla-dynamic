-- ============================================================================
-- PARCHE PROPUESTO 01 — fn_registrar_marcaje: PIN real + validación de sede
-- ----------------------------------------------------------------------------
-- Hallazgo (reportes A, D y E — encontrado de forma independiente por los 3):
-- fn_registrar_marcaje nunca recibe ni valida PIN (la verificación hoy corre
-- 100% en el navegador del kiosko, contra un pin_hash que se descarga
-- completo al dispositivo), nunca valida que la persona marcada pertenezca a
-- la sede del terminal, y el chequeo de "terminal autenticado" se salta
-- enteramente cuando la llamada no tiene sesión (auth.uid() es NULL).
--
-- Esto significa: cualquiera con acceso a la consola del navegador de un
-- kiosko puede llamar el RPC directo y marcar entrada/salida de cualquier
-- persona, de cualquier sede, sin PIN — incluso hoy que requiere_pin=false
-- en las 3 sedes, porque el problema de fondo (sin sesión, sin validar sede)
-- es independiente de si el PIN está activado o no.
--
-- NO APLICADO — propuesta para revisar y aplicar tú mismo. Son 3 cambios
-- independientes dentro de la misma función (se pueden aplicar juntos o por
-- partes si preferís ir con calma):
--   (1) Exigir sesión de terminal real (rechazar auth.uid() NULL).
--   (2) Validar que p_persona_id pertenezca a la sede del terminal (o tenga
--       visible_todas_sedes) Y esté activa — cierra de paso el hallazgo 🟡
--       de "estado activo" que reportó D, es la misma validación.
--   (3) Verificar el PIN SERVER-SIDE cuando terminales.requiere_pin = true,
--       usando pgcrypto (ya habilitado desde 0001_init.sql) contra el
--       pin_hash real — nunca hace falta mandar el hash al cliente para
--       esto. Si requiere_pin = false (como hoy en las 3 sedes), el
--       parámetro p_pin simplemente se ignora — no cambia nada del
--       comportamiento actual mientras el PIN siga apagado.
--
-- IMPORTANTE — esto solo tiene efecto real si el terminal manda el PIN: ver
-- la nota de "cambio de frontend necesario" al final de este archivo. Sin
-- ese cambio, el punto (3) queda listo pero inactivo (p_pin siempre llega
-- NULL, y como requiere_pin=false hoy, no bloquea nada — los puntos (1) y
-- (2) sí quedan activos de inmediato en cuanto se aplica este SQL, sin
-- depender del frontend).
-- ============================================================================

create or replace function fn_registrar_marcaje(
  p_persona_id uuid,
  p_tipo tipo_marca,
  p_timestamp_cliente timestamptz,
  p_client_uuid uuid,
  p_origen origen_marca default 'terminal',
  p_terminal_id uuid default null,
  p_sede_id uuid default null,
  p_motivo_otro text default null,
  p_pin text default null
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
  v_requiere_pin boolean;
  v_pin_hash text;
begin
  select * into v_existente from marcajes where client_uuid = p_client_uuid;
  if found then
    return v_existente;
  end if;

  if p_origen = 'terminal' then
    if p_terminal_id is null then
      raise exception 'p_terminal_id es obligatorio cuando origen = terminal';
    end if;
    select sede_id, auth_user_id, requiere_pin
      into v_sede_id, v_terminal_auth, v_requiere_pin
    from terminales where id = p_terminal_id and activo;
    if v_sede_id is null then
      raise exception 'terminal % no encontrado o inactivo', p_terminal_id;
    end if;

    -- CAMBIO (1): antes, si auth.uid() era NULL (sin sesión), esta condición
    -- completa daba false y el chequeo se saltaba entero. Ahora se exige
    -- sesión de terminal SIEMPRE, y además que coincida con p_terminal_id.
    if auth.uid() is null then
      raise exception 'se requiere una sesión de terminal autenticada';
    end if;
    if v_terminal_auth is not null and auth.uid() <> v_terminal_auth then
      raise exception 'el terminal autenticado no coincide con p_terminal_id';
    end if;

    -- CAMBIO (2): antes no se validaba que la persona marcada perteneciera a
    -- esta sede, ni que siguiera activa. Cierra también el hallazgo de
    -- "estado activo" (mismo chequeo, mismo lugar).
    if not exists (
      select 1 from personas
      where id = p_persona_id
        and estado = 'activo'
        and (sede_base_id = v_sede_id or visible_todas_sedes)
    ) then
      raise exception 'la persona no pertenece a esta sede o no está activa';
    end if;

    -- CAMBIO (3): PIN verificado server-side, solo si el terminal lo exige.
    -- pgcrypto (habilitado desde 0001_init.sql) sabe comparar contra un hash
    -- bcrypt estándar ($2a$/$2b$) sin necesitar la librería de Node — el
    -- pin_hash generado con bcryptjs en el cliente es compatible tal cual.
    if coalesce(v_requiere_pin, false) then
      select pin_hash into v_pin_hash from personas where id = p_persona_id;
      if p_pin is null or v_pin_hash is null or crypt(p_pin, v_pin_hash) <> v_pin_hash then
        raise exception 'PIN incorrecto';
      end if;
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

  if p_origen = 'terminal' then
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

  return v_marcaje;
end;
$$;

-- Misma disciplina de permisos que el resto de funciones desde 0023 —
-- fn_registrar_marcaje NUNCA tuvo el revoke, esto lo cierra de una vez.
grant execute on function fn_registrar_marcaje(uuid, tipo_marca, timestamptz, uuid, origen_marca, uuid, uuid, text, text) to authenticated;
revoke execute on function fn_registrar_marcaje(uuid, tipo_marca, timestamptz, uuid, origen_marca, uuid, uuid, text, text) from public, anon;

notify pgrst, 'reload schema';

-- ============================================================================
-- Además, mismo hallazgo de fondo, otras 10 funciones de Sprint 0 nunca
-- tuvieron su revoke (confirmado por A y B): fn_siguiente_tipo_esperado,
-- fn_corregir_marcaje, fn_agregar_marcaje, fn_eliminar_marcaje,
-- fn_set_horario, fn_quitar_horario, fn_set_turno, fn_set_descanso,
-- fn_quitar_turno, fn_set_meta_cobertura. Para la mayoría el chequeo interno
-- ya las protege (fallan si no hay fila en personas), pero por higiene y
-- consistencia con el patrón que el propio equipo adoptó en 0023:
-- ============================================================================

revoke execute on function fn_siguiente_tipo_esperado(uuid, date) from public, anon;
revoke execute on function fn_corregir_marcaje(uuid, timestamptz, text) from public, anon;
revoke execute on function fn_agregar_marcaje(uuid, tipo_marca, timestamptz, text, text) from public, anon;
revoke execute on function fn_eliminar_marcaje(uuid, text) from public, anon;
revoke execute on function fn_set_horario(uuid, time, time, date, int, int, int[]) from public, anon;
revoke execute on function fn_quitar_horario(uuid, date) from public, anon;
revoke execute on function fn_set_turno(uuid, date, time, time) from public, anon;
revoke execute on function fn_set_descanso(uuid, date) from public, anon;
revoke execute on function fn_quitar_turno(uuid, date) from public, anon;

-- Firmas verificadas contra el texto real de las migraciones (0009, 0010,
-- 0011, 0014, 0015) el mismo día de este parche — no debería haber sorpresas,
-- pero si igual algún REVOKE falla por firma no encontrada, Postgres avisa
-- con un error claro (no falla silencioso): ajusta esa línea y seguí con el
-- resto.

-- ============================================================================
-- fn_set_meta_cobertura: corrige también el guard inseguro (no solo el
-- revoke de arriba). Antes usaba `not in (...)`, que con fn_rol_actual()
-- devolviendo NULL (cualquier sesión sin fila en personas — terminal, o
-- anon) hace que el IF nunca dispare la excepción. Ahora reusa el helper
-- fn_es_admin_o_lider(), igual que el resto del código desde 0019/0020.
-- ============================================================================

create or replace function fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana int, p_meta int)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador puede definir la meta de cobertura.';
  end if;
  if p_dia_semana < 0 or p_dia_semana > 6 then raise exception 'Día de la semana inválido.'; end if;
  if p_meta < 0 then raise exception 'La meta no puede ser negativa.'; end if;
  insert into metas_cobertura (sede_id, dia_semana, meta, updated_at)
  values (p_sede_id, p_dia_semana, p_meta, now())
  on conflict (sede_id, dia_semana) do update set meta = excluded.meta, updated_at = now();
end;
$$;

grant execute on function fn_set_meta_cobertura(uuid, int, int) to authenticated;
revoke execute on function fn_set_meta_cobertura(uuid, int, int) from public, anon;

-- ============================================================================
-- CAMBIO DE FRONTEND NECESARIO para que el punto (3) tenga efecto real
-- (opcional — solo si en algún momento decides reactivar requiere_pin):
-- ----------------------------------------------------------------------------
-- Hoy `apps/web/lib/terminal/pin.ts` verifica el PIN en el navegador y,
-- si pasa, llama a fn_registrar_marcaje SIN mandar el PIN. Para que el
-- servidor de verdad lo revise:
--   1. En el punto donde `marcar/page.tsx` arma los args de
--      supabase.rpc('fn_registrar_marcaje', {...}), agregar `p_pin: pin`
--      (el PIN que la persona tecleó, en texto plano, va por el canal ya
--      cifrado de la sesión — no hace falta hashearlo en el cliente).
--   2. Se puede (y probablemente conviene) DEJAR la verificación client-side
--      de pin.ts como está, como primer filtro de UX rápido (feedback
--      inmediato sin round-trip) — la verificación server-side es la que
--      de verdad importa para seguridad, ambas pueden convivir.
--   3. Considerar YA NO descargar pin_hash al roster del terminal
--      (`apps/web/lib/terminal/roster.ts`) una vez que el servidor sea la
--      única fuente de verdad — hoy ese hash viaja al dispositivo y queda en
--      IndexedDB sin necesidad, es superficie de ataque de más (fuerza bruta
--      offline sin límite de intentos). Esto sí es un cambio más grande de
--      UX/offline (hoy el modo offline depende de validar el PIN local sin
--      red) — vale la pena pensarlo con calma, no es parte de este parche.
-- ============================================================================
