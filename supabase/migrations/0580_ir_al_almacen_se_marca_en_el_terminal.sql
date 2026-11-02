-- ============================================================================
-- 0580 — Ir al almacén se marca en el terminal (y no es un marcaje)
-- ----------------------------------------------------------------------------
-- DE DÓNDE SALE. Felipe (2026-11-02): «vamos a empezar a llevar unas 2 chicas de
--   piso al almacén, y la líder de equipo necesita saber quién está en piso y
--   quién no». El almacén está dentro de cada sede (otro piso, la trastienda): se
--   marca en el mismo terminal y no es otra sede. Con lo que se registre se quiere
--   medir después qué días y a qué horas se va más gente al almacén y si el piso
--   quedó corto. Diseñado con la sesión de Turnos y cobertura (maqueta «Terminal»).
--
-- QUÉ PROMETE.
--   · `cambios_ubicacion`: cada vez que alguien dice en el terminal «Voy a
--     almacén» o «Vuelvo a tienda», una fila. Append-only: no se borra ni se
--     edita; se ANULA con motivo, como los marcajes (0081).
--   · Un cambio de ubicación NO ES UN MARCAJE. No abre ni cierra la jornada, no
--     cambia horas ni pago, y por eso NO pasa por fn_registrar_marcaje ni toca
--     `marcajes` ni `jornadas`. Esta migración no lee ni escribe nada de plata.
--   · Se escribe por UNA puerta, `fn_registrar_cambio_ubicacion`, con las mismas
--     tres comprobaciones de identidad que fn_registrar_marcaje (terminal activo,
--     sesión = ese terminal, persona en su lista) y la misma idempotencia por
--     `client_uuid`, porque llega por la misma cola sin conexión.
--   · Se lee el día armado en tramos con `fn_ubicaciones_del_dia`.
--
-- ── CONTRATO CON LA SESIÓN DE TURNOS (otra sesión depende de estos nombres) ──
--
--   public.cambios_ubicacion
--     id, client_uuid (único), persona_id, sede_id, terminal_id,
--     ubicacion          'tienda' | 'almacen'
--     timestamp_cambio   la hora del terminal (como timestamp_marca)
--     vuelve_previsto    solo con 'almacen'; null = «hasta que vuelva»
--     origen             'terminal' | 'panel'
--     registrado_por     quién lo cargó desde el panel (null desde el terminal)
--     server_received_at cuándo llegó al servidor (la cola puede traerlo tarde)
--     anulado_at, anulado_por, anulado_motivo
--
--   public.fn_ubicaciones_del_dia(p_sede_id uuid, p_fecha date)
--     returns table (persona_id uuid, desde timestamptz, hasta timestamptz)
--     Una fila por TRAMO REAL EN ALMACÉN de ese día en esa sede. `hasta` null =
--     sigue allí ahora. Legible por admin, lider_do y la líder de equipo
--     (supervisor_sede) de ESA sede; cualquier otro recibe un error.
--
--     Cómo se arma un tramo (decidido con Felipe el 2026-11-02):
--       1. Lo anulado no existe.
--       2. Empieza en un «almacen». Termina con lo PRIMERO de:
--            · el siguiente cambio de esa persona ese día (un «tienda»);
--            · su salida final de esa jornada, no anulada (si reabre el día, la
--              salida queda anulada y el tramo se reabre solo);
--            · su `vuelve_previsto`, SI YA PASÓ. Olvidarse de marcar la vuelta
--              va a ser el error más común, y sin este cierre una persona
--              figuraría todo el día en almacén y el reporte diría «el piso
--              quedó corto» cuando no lo quedó. Quien de verdad se queda más
--              usa «Hasta que vuelva» o vuelve a marcar.
--       3. Dos «almacen» seguidos (un doble toque, o alargar el tiempo) se
--          juntan en un tramo si se tocan; si entre los dos venció el primero,
--          son dos tramos con el piso en medio.
--       4. El refrigerio NO corta el tramo: dónde está lo dice esta tabla y si
--          está presente lo dicen los marcajes. Cruzar las dos cosas es de quien
--          pinta la cobertura.
--       5. Devuelve TODOS los tramos, también los de menos de 30 minutos: es la
--          vista en vivo, y un tramo que acaba de empezar siempre dura menos.
--          «Los cambios de menos de 30 minutos no cuentan» es regla de los
--          REPORTES, y se aplica allí, no aquí.
--
--   Lo planificado (`puestos_planificados`, de la sesión de Turnos) no se lee ni
--   se toca aquí: esto es lo REAL. Si lo planificado dice almacén y ella marca
--   «Vuelvo a tienda», queda lo que pasó.
--
-- QUÉ ASUME. Hasta la 0578. `terminales`, `personas`, `marcajes.fecha_jornada`
--   (0240), `fn_es_admin_o_lider` (0078), `fn_rol_actual`, `fn_sede_actual_persona`
--   y `fn_sede_actual_terminal` (0005), `fn_persona_en_roster_terminal` (0241).
--   La 0579 queda para `puestos_planificados` (sesión de Turnos).
--
-- POR QUÉ ASÍ.
--   · Tabla propia y no un tipo nuevo de marcaje: un tipo nuevo entraría a la
--     máquina de estados de fn_registrar_marcaje, a fn_recalcular_jornada y al
--     cálculo de horas. Ubicación y pago no tienen nada que ver.
--   · No exige jornada abierta para registrar: la cola puede subir el cambio
--     antes que la entrada que lo precede, y un registro real no se pierde por
--     llegar en otro orden. El terminal solo lo ofrece a quien está trabajando.
--   · El terminal lee la TABLA (política `cambios_ubicacion_select_terminal`,
--     la misma condición que `marcajes_select_terminal`) y no la función, porque
--     necesita `vuelve_previsto` para decir «vuelves 13:32». Así el contrato de
--     la función queda como se acordó.
--   · Guardas con `is not true` (CLAUDE.md). Sin fila en `personas` —el
--     terminal— nadie pasa por la puerta del panel.
--
-- CÓMO SE REVIERTE. Nada depende de esto para pagar. Para retirarlo:
--     drop function if exists public.fn_ubicaciones_del_dia(uuid, date);
--     drop function if exists public.fn_anular_cambio_ubicacion(uuid, text);
--     drop function if exists public.fn_registrar_cambio_ubicacion(uuid, text, timestamptz, uuid, text, uuid, timestamptz, uuid);
--   y la tabla se deja (su historial es lo que se quería medir).
-- ============================================================================

-- ── 1 · La tabla ────────────────────────────────────────────────────────────
create table if not exists public.cambios_ubicacion (
  id                 uuid primary key default gen_random_uuid(),
  client_uuid        uuid not null unique,
  persona_id         uuid not null references personas(id),
  sede_id            uuid not null references sedes(id),
  terminal_id        uuid references terminales(id),
  ubicacion          text not null check (ubicacion in ('tienda', 'almacen')),
  timestamp_cambio   timestamptz not null,
  vuelve_previsto    timestamptz,
  origen             text not null default 'terminal' check (origen in ('terminal', 'panel')),
  registrado_por     uuid references personas(id),
  server_received_at timestamptz not null default now(),
  anulado_at         timestamptz,
  anulado_por        uuid references personas(id),
  anulado_motivo     text,
  -- Desde el terminal se sabe qué terminal; desde el panel, quién.
  constraint cambios_ubicacion_quien check (
    (origen = 'terminal' and terminal_id is not null)
    or (origen = 'panel' and registrado_por is not null)
  ),
  -- «Vuelvo a las 13:32» solo tiene sentido yendo al almacén, y después de irse.
  constraint cambios_ubicacion_vuelve check (
    vuelve_previsto is null
    or (ubicacion = 'almacen' and vuelve_previsto > timestamp_cambio)
  ),
  -- Estado imposible (mismo criterio que marcajes, 0081): anulado sin saber
  -- quién ni por qué.
  constraint cambios_ubicacion_anulacion check (
    (anulado_at is null and anulado_por is null and anulado_motivo is null)
    or (anulado_at is not null and anulado_por is not null and length(trim(anulado_motivo)) >= 3)
  )
);

create index if not exists idx_cambios_ubicacion_sede_ts
  on public.cambios_ubicacion (sede_id, timestamp_cambio);
create index if not exists idx_cambios_ubicacion_persona_ts
  on public.cambios_ubicacion (persona_id, timestamp_cambio);

comment on table public.cambios_ubicacion is
  'Dónde está alguien dentro de su sede: tienda o almacén (0580). NO es un marcaje: no abre ni '
  'cierra la jornada ni cambia horas o pago. Append-only: se anula con motivo, nunca se borra. '
  'Se escribe solo por fn_registrar_cambio_ubicacion; se lee armado con fn_ubicaciones_del_dia.';

-- ── 2 · Append-only, de verdad ──────────────────────────────────────────────
-- Sin políticas de escritura ningún cliente puede tocarla; esto cuida además lo
-- que llega por el SQL Editor o por una función futura que se equivoque.
create or replace function public.fn_cambios_ubicacion_solo_anular()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'un cambio de ubicación no se borra: se anula con motivo (fn_anular_cambio_ubicacion)';
  end if;
  if old.anulado_at is not null then
    raise exception 'este cambio de ubicación ya está anulado y no se vuelve a tocar';
  end if;
  if (new.id, new.client_uuid, new.persona_id, new.sede_id, new.terminal_id, new.ubicacion,
      new.timestamp_cambio, new.vuelve_previsto, new.origen, new.registrado_por, new.server_received_at)
     is distinct from
     (old.id, old.client_uuid, old.persona_id, old.sede_id, old.terminal_id, old.ubicacion,
      old.timestamp_cambio, old.vuelve_previsto, old.origen, old.registrado_por, old.server_received_at)
  then
    raise exception 'un cambio de ubicación no se edita: se anula con motivo y se registra otro';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cambios_ubicacion_solo_anular on public.cambios_ubicacion;
create trigger trg_cambios_ubicacion_solo_anular
  before update or delete on public.cambios_ubicacion
  for each row execute function public.fn_cambios_ubicacion_solo_anular();

-- ── 3 · Quién la lee ────────────────────────────────────────────────────────
alter table public.cambios_ubicacion enable row level security;

revoke all on table public.cambios_ubicacion from public, anon, authenticated;
grant select on table public.cambios_ubicacion to authenticated;

-- El terminal: su sede y las personas de su lista. Es la condición de
-- marcajes_select_terminal (0241), para que las dos no digan cosas distintas.
drop policy if exists cambios_ubicacion_select_terminal on public.cambios_ubicacion;
create policy cambios_ubicacion_select_terminal on public.cambios_ubicacion
  for select to authenticated
  using (
    fn_sede_actual_terminal() is not null
    and sede_id = fn_sede_actual_terminal()
    and fn_persona_en_roster_terminal(persona_id)
  );

-- El panel: admin y lider_do todo; la líder de equipo, su sede.
drop policy if exists cambios_ubicacion_select_panel on public.cambios_ubicacion;
create policy cambios_ubicacion_select_panel on public.cambios_ubicacion
  for select to authenticated
  using (
    fn_es_admin_o_lider()
    or (fn_rol_actual() = 'supervisor_sede' and sede_id = fn_sede_actual_persona())
  );

-- ── 4 · La puerta de escritura ──────────────────────────────────────────────
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
    if not exists (
      select 1 from personas p
       where p.id = p_persona_id and p.estado = 'activo'
         and (p.sede_base_id = v_sede_id or p.visible_todas_sedes = true)
    ) then
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

comment on function public.fn_registrar_cambio_ubicacion(uuid, text, timestamptz, uuid, text, uuid, timestamptz, uuid) is
  'La única puerta para registrar «Voy a almacén» / «Vuelvo a tienda» (0580). NO es un marcaje. '
  'Idempotente por client_uuid. Terminal: mismas comprobaciones de identidad que fn_registrar_marcaje. '
  'Panel: admin, lider_do o la líder de equipo de esa sede.';

revoke execute on function public.fn_registrar_cambio_ubicacion(uuid, text, timestamptz, uuid, text, uuid, timestamptz, uuid) from public, anon;
grant execute on function public.fn_registrar_cambio_ubicacion(uuid, text, timestamptz, uuid, text, uuid, timestamptz, uuid) to authenticated, service_role;

-- ── 5 · Anular, con motivo y rastro ─────────────────────────────────────────
create or replace function public.fn_anular_cambio_ubicacion(p_id uuid, p_motivo text)
returns public.cambios_ubicacion
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fila  cambios_ubicacion;
  v_autor uuid;
begin
  select id into v_autor from personas where auth_user_id = auth.uid();
  select * into v_fila from cambios_ubicacion where id = p_id for update;
  if not found then
    raise exception 'cambio de ubicación % no encontrado', p_id;
  end if;
  if v_autor is null
     or (fn_es_admin_o_lider()
         or (fn_rol_actual() = 'supervisor_sede' and fn_sede_actual_persona() = v_fila.sede_id)) is not true
  then
    raise exception 'Sin permiso para anular ubicaciones de esa sede';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'el motivo es obligatorio';
  end if;
  if v_fila.anulado_at is not null then
    raise exception 'este cambio de ubicación ya está anulado';
  end if;

  update cambios_ubicacion
     set anulado_at = now(), anulado_por = v_autor, anulado_motivo = trim(p_motivo)
   where id = p_id
  returning * into v_fila;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_fila.persona_id, 'cambio_ubicacion',
     v_fila.ubicacion || ' ' || to_char(v_fila.timestamp_cambio at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
     'anulado', v_autor, trim(p_motivo));

  return v_fila;
end;
$$;

comment on function public.fn_anular_cambio_ubicacion(uuid, text) is
  'Anula un cambio de ubicación (0580): admin, lider_do o la líder de equipo de esa sede. Motivo '
  'obligatorio; deja rastro en correcciones_auditoria. Nunca borra.';

revoke execute on function public.fn_anular_cambio_ubicacion(uuid, text) from public, anon;
grant execute on function public.fn_anular_cambio_ubicacion(uuid, text) to authenticated, service_role;

-- ── 6 · La lectura del contrato ─────────────────────────────────────────────
create or replace function public.fn_ubicaciones_del_dia(p_sede_id uuid, p_fecha date)
returns table (persona_id uuid, desde timestamptz, hasta timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if (fn_es_admin_o_lider()
      or (fn_rol_actual() = 'supervisor_sede' and fn_sede_actual_persona() = p_sede_id)) is not true
  then
    raise exception 'Sin permiso para ver las ubicaciones de esa sede';
  end if;

  return query
  with cambios as (
    select c.id, c.persona_id, c.ubicacion, c.timestamp_cambio as t, c.vuelve_previsto
      from cambios_ubicacion c
     where c.sede_id = p_sede_id
       and c.anulado_at is null
       and (c.timestamp_cambio at time zone 'America/Lima')::date = p_fecha
  ),
  -- Cada «almacen» con su fin: lo primero entre el siguiente cambio, la salida
  -- final de esa jornada y la vuelta prevista ya vencida. `least` ignora nulos;
  -- si los tres son nulos, sigue allí. `id` desempata dos cambios del mismo
  -- instante (un doble toque), y es solo un ancla.
  con_fin as (
    select k.persona_id, k.t as inicio,
           least(
             lead(k.t) over (partition by k.persona_id order by k.t, k.id),
             (select min(m.timestamp_marca)
                from marcajes m
               where m.persona_id = k.persona_id
                 and m.tipo = 'salida_final'
                 and m.anulada_at is null
                 and m.timestamp_marca > k.t
                 and coalesce(m.fecha_jornada, (m.timestamp_marca at time zone 'America/Lima')::date) = p_fecha),
             case when k.vuelve_previsto <= now() then k.vuelve_previsto end
           ) as fin,
           k.ubicacion, k.id
      from cambios k
  ),
  almacen as (
    select a.persona_id, a.inicio, a.fin, a.id,
           -- Empieza un tramo nuevo si el anterior ya había terminado antes de éste.
           case when lag(a.fin) over w is null or lag(a.fin) over w < a.inicio then 1 else 0 end as nuevo
      from con_fin a
     where a.ubicacion = 'almacen'
    window w as (partition by a.persona_id order by a.inicio, a.id)
  ),
  islas as (
    select b.persona_id, b.inicio, b.fin,
           sum(b.nuevo) over (partition by b.persona_id order by b.inicio, b.id) as isla
      from almacen b
  )
  select i.persona_id,
         min(i.inicio) as desde,
         case when bool_or(i.fin is null) then null else max(i.fin) end as hasta
    from islas i
   group by i.persona_id, i.isla
  having bool_or(i.fin is null) or max(i.fin) > min(i.inicio)
   order by 1, 2;
end;
$$;

comment on function public.fn_ubicaciones_del_dia(uuid, date) is
  'CONTRATO con Turnos (0580): tramos reales en almacén de un día y una sede — persona_id, desde, '
  'hasta (null = sigue allí). Cierra con «Vuelvo a tienda», la salida final no anulada o la vuelta '
  'prevista ya vencida. Devuelve también los tramos cortos: el filtro de 30 min es de los reportes. '
  'Admin, lider_do o la líder de equipo de esa sede.';

revoke execute on function public.fn_ubicaciones_del_dia(uuid, date) from public, anon;
grant execute on function public.fn_ubicaciones_del_dia(uuid, date) to authenticated, service_role;

insert into migraciones_aplicadas (numero, nombre)
values (580, 'ir_al_almacen_se_marca_en_el_terminal')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ───────────────────────────────────────────────────────────
-- Debe devolver UNA fila: t · t · t · t · 2 · «580 · ir_al_almacen_se_marca_en_el_terminal».
select
  to_regclass('public.cambios_ubicacion') is not null                                   as tabla,
  (select count(*) = 1 from pg_proc where proname = 'fn_registrar_cambio_ubicacion')    as registrar,
  (select count(*) = 1 from pg_proc where proname = 'fn_anular_cambio_ubicacion')       as anular,
  (select count(*) = 1 from pg_proc where proname = 'fn_ubicaciones_del_dia')           as leer,
  (select count(*)::int from pg_policies where tablename = 'cambios_ubicacion')         as politicas,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 580)      as registro;
