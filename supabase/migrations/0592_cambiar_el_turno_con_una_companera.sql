-- ============================================================================
-- 0592 — Cambiar el turno con una compañera
-- ============================================================================
--
-- QUÉ PROMETE
--   Que dos compañeras de la misma sede se cambien el turno de UN día: «tú mi
--   mañana, yo tu tarde». Ella lo propone; la compañera acepta o no; su líder
--   de equipo (o DO) lo aprueba; y recién ahí el sistema intercambia los dos
--   turnos de una vez —los dos o ninguno—, con su rastro en el historial.
--   También la líder, desde «Este día no me calza» (0587), puede proponerlo
--   ella: entonces basta con que la compañera acepte.
--
-- DECIDIÓ FELIPE (2026-11-03): las tres recomendadas.
--   A · Solo turnos del MISMO DÍA. No cruza días: un cambio entre días mueve el
--       descanso semanal y las horas del ciclo de 7 días (sobretiempo, CLAUDE.md)
--       y eso pide su propia auditoría de plata. Queda para después.
--   · La compañera tiene que aceptar: a nadie se le cambia el turno sin preguntarle.
--   · La líder aprueba aunque las dos estén de acuerdo: es quien ve la cobertura.
--
-- POR QUÉ ASÍ
--   · Mismo LARGO de turno, además del mismo día. Con eso ninguna de las dos
--     cambia sus horas del día ni de la semana: el pago no se mueve, que es lo
--     que prometía la opción A. Un cambio entre turnos de distinto largo lo hace
--     la líder en Turnos, como siempre.
--   · El intercambio guarda una FOTO de los dos turnos al proponerse. Si alguno
--     cambió en el medio (otro cambio, Turnos, la semana sugerida), el
--     intercambio se niega: aplicar sobre otra cosa de la que se aceptó sería
--     cambiarle a alguien un turno que no aceptó.
--   · Escribe `turnos` directo, no por fn_set_turno: fn_set_turno exige que
--     quien llama tenga permiso de corregir, y en el caso «la líder lo propuso,
--     la compañera acepta» quien llama es la compañera. El permiso real lo dio
--     la líder al proponer o al aprobar; por eso el rastro lo firma ella
--     (`corregido_por`). Copia de fn_set_turno (0327) lo que importa: el
--     candado del periodo pagado, la auditoría con el motivo que empieza
--     «Turno del DD/MM/YYYY» (lo lee el historial, 0587) y fn_recalcular_jornada.
--   · El piso o almacén de ese día (puestos_planificados, 0579/0588) NO se
--     intercambia: es de la sesión de Turnos y depende del puesto base de cada
--     una. La pantalla le avisa a la líder que lo revise.
--   · Las 48 h para que pase a DO son las de la 0587, al leer. No hay cron.
--
-- QUIÉN HACE QUÉ
--   proponer          la propia persona, activa, de hoy a 21 días, con una
--                     compañera activa de su sede que trabaja ese día un turno
--                     distinto del mismo largo
--   proponer por      su líder / DO, desde un pedido abierto de «Este día no me calza»
--   contestar         solo la compañera
--   aprobar           fn_puede_resolver_disponibilidad sobre LAS DOS (0584)
--   retirar           quien lo propuso, mientras no está aplicado
--   leer              RLS: las dos, la líder de su sede, DO y admin
--
-- ESTADOS
--   propuesto → aceptado → aprobado            (lo propuso ella)
--   propuesto → aprobado                       (lo propuso su líder o DO)
--   propuesto → rechazado | retirado
--   aceptado  → no_aprobado | retirado
--
-- QUÉ NO REESCRIBE
--   Ninguna función existente: todas son nuevas (donde-vive.sh, 2026-11-03).
--   No lleva md5 de partida. Escribe en turno_pedidos (0587) solo para dejar
--   resuelto el pedido del que salió, con la resolución que la 0587 dejó
--   reservada: 'cambio_companera'.
--
-- CÓMO SE PEGA — EN TRES PARTES, UNA POR UNA (la lección de la 0591, 2026-11-03)
--   El SQL Editor corre todo lo pegado en UNA transacción, y esta migración junta
--   dos cosas que no se llevan: crear `turno_cambios` con claves foráneas a
--   `personas` y `turno_pedidos` (que bloquean esas tablas, en uso, hasta el
--   final) y crear políticas (que en Supabase toman bloqueos exclusivos sobre las
--   tablas de `auth` y `storage`). Con el Asesor de seguridad del panel mirando,
--   ese cruce es la receta del «40P01 deadlock detected»; la 0591 lo dio en
--   producción el 2026-11-03 y no se aplicó nada. Por eso:
--     PARTE 1 · la tabla y sus índices        (toca `personas` y `turno_pedidos` solo para las claves)
--     PARTE 2 · RLS, políticas y permisos      (las políticas, solas)
--     PARTE 3 · las funciones, el registro y la comprobación
--   Cada parte se pega SOLA, en ese orden, y las dos primeras empiezan con
--   `set local lock_timeout = '3s'`: si no consiguen el bloqueo fallan con 55P03
--   en vez de quedarse en cola frenando a todos los que vienen detrás; se
--   repegan. Las partes 2 y 3 se niegan a correr si falta la anterior. Todas son
--   idempotentes. Entera, en un solo bloque, sigue siendo válida en una base sin
--   tráfico (`supabase db reset`, las pruebas).
--
-- ANTES DE PEGAR (solo lee; no hay md5 de partida porque ninguna función existía)
--     select to_regclass('public.turno_cambios') is not null as ya_existe_la_tabla,
--            (select count(*) from pg_proc where proname like 'fn_turno_cambio%') as funciones,
--            (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 592) as registro;
--   Esperado: false, 0 y null. Si no: ya está pegada (o a medias); repegar es seguro,
--   pero mira primero qué devolvió.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_turno_cambios_mios();
--   drop function if exists fn_turno_cambio_candidatas(date, uuid);
--   drop function if exists fn_turno_cambio_retirar(uuid);
--   drop function if exists fn_turno_cambio_resolver(uuid, boolean, text);
--   drop function if exists fn_turno_cambio_contestar(uuid, boolean, text);
--   drop function if exists fn_turno_cambio_proponer_por_pedido(uuid, uuid);
--   drop function if exists fn_turno_cambio_proponer(date, uuid, text);
--   drop function if exists fn_turno_cambio_aplicar_interno(uuid, uuid);
--   drop table if exists turno_cambios;     -- solo si nadie la usa
--   delete from migraciones_aplicadas where numero = 592;
--   (Los turnos ya intercambiados se quedan: tienen su rastro en correcciones_auditoria.)
--
-- CÓMO SE COMPRUEBA
--   La consulta del final: todo en true y «592 · cambiar_el_turno_con_una_companera».
-- ============================================================================

-- ═══ PARTE 1 · La tabla y sus índices ═══════════════════════════════════════

set local lock_timeout = '3s';

-- ── 1 · La tabla ─────────────────────────────────────────────────────────────

create table if not exists turno_cambios (
  id                 uuid primary key default gen_random_uuid(),
  fecha              date not null,
  solicitante_id     uuid not null references personas(id),
  companera_id       uuid not null references personas(id),
  propuesto_por      uuid not null references personas(id),
  pedido_id          uuid references turno_pedidos(id),
  -- La foto de los dos turnos al proponerse.
  sol_entrada        time not null,
  sol_salida         time not null,
  comp_entrada       time not null,
  comp_salida        time not null,
  comentario         text check (comentario is null or length(comentario) <= 300),
  estado             text not null default 'propuesto'
                     check (estado in ('propuesto', 'aceptado', 'rechazado', 'aprobado', 'no_aprobado', 'retirado')),
  creado_at          timestamptz not null default now(),
  contestado_at      timestamptz,
  respuesta_companera text check (respuesta_companera is null or length(respuesta_companera) <= 300),
  resuelto_por       uuid references personas(id),
  resuelto_at        timestamptz,
  respuesta          text check (respuesta is null or length(respuesta) <= 500),
  constraint cambio_entre_dos check (solicitante_id <> companera_id),
  constraint cambio_aprobado_completo check (
    estado not in ('aprobado', 'no_aprobado') or (resuelto_por is not null and resuelto_at is not null))
);

comment on table turno_cambios is
  'Dos compañeras de la misma sede se cambian el turno de un día (mismo largo). La compañera acepta y su '
  'líder aprueba; recién ahí se intercambian los dos turnos. Solo por fn_turno_cambio_*. 0592.';

-- Una sola propuesta viva por persona y día, de cada lado.
create unique index if not exists idx_turno_cambio_vivo_solicitante
  on turno_cambios (solicitante_id, fecha) where estado in ('propuesto', 'aceptado');
create unique index if not exists idx_turno_cambio_vivo_companera
  on turno_cambios (companera_id, fecha) where estado in ('propuesto', 'aceptado');

-- ═══ PARTE 2 · RLS, políticas y permisos (las políticas, solas) ══════════════
-- Se pega DESPUÉS de la parte 1 y sola.

set local lock_timeout = '3s';

do $$
begin
  if to_regclass('public.turno_cambios') is null then
    raise exception 'Falta la PARTE 1 (la tabla): pégala primero y sola, y después esta.';
  end if;
end;
$$;

alter table turno_cambios enable row level security;

drop policy if exists turno_cambios_select_admin_lider on turno_cambios;
create policy turno_cambios_select_admin_lider on turno_cambios
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists turno_cambios_select_supervisor on turno_cambios;
create policy turno_cambios_select_supervisor on turno_cambios
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede'
         and solicitante_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));

drop policy if exists turno_cambios_select_propia on turno_cambios;
create policy turno_cambios_select_propia on turno_cambios
  for select to authenticated
  using (solicitante_id = fn_persona_actual_id() or companera_id = fn_persona_actual_id());

revoke all on turno_cambios from anon, authenticated, public;
grant select on turno_cambios to authenticated;

-- ═══ PARTE 3 · Las funciones, el registro y la comprobación ═════════════════
-- Se pega DESPUÉS de las partes 1 y 2 y sola.

do $$
begin
  if to_regclass('public.turno_cambios') is null
     or not exists (select 1 from pg_policies where tablename = 'turno_cambios' and policyname = 'turno_cambios_select_propia') then
    raise exception 'Faltan la PARTE 1 o la PARTE 2 (la tabla y sus políticas): pégalas primero, cada una sola, y después esta.';
  end if;
end;
$$;

-- La regla de candidatas sin el control de quién llama: la usan las puertas,
-- que ya controlaron. Interna: sin grant.
create or replace function fn_turno_cambio_candidatas_de(p_fecha date, p_persona_id uuid)
returns table (persona_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select p.id
    from personas me
    join turnos tm on tm.persona_id = me.id and tm.fecha = p_fecha
    join personas p on p.sede_base_id = me.sede_base_id and p.id <> me.id and p.estado = 'activo'
                   and coalesce(p.cuenta_de_servicio, false) = false
    join turnos t on t.persona_id = p.id and t.fecha = p_fecha
   where me.id = p_persona_id and me.estado = 'activo'
     and not tm.es_descanso and tm.hora_salida is not null
     and not t.es_descanso and t.hora_salida is not null
     and t.hora_salida - t.hora_entrada = tm.hora_salida - tm.hora_entrada
     and (t.hora_entrada, t.hora_salida) is distinct from (tm.hora_entrada, tm.hora_salida)
     and not exists (select 1 from turno_cambios c
                      where c.fecha = p_fecha and c.estado in ('propuesto', 'aceptado')
                        and p.id in (c.solicitante_id, c.companera_id));
$$;

-- ── 2 · Qué compañeras sirven ese día ────────────────────────────────────────
-- Las de su sede, activas, que trabajan ese día un turno distinto del mismo
-- largo, y que no tienen ya un cambio vivo ese día. Devuelve solo nombre y
-- horario de ese día: lo que ya está publicado en la tienda.

create or replace function fn_turno_cambio_candidatas(p_fecha date, p_persona_id uuid default null)
returns table (persona_id uuid, nombre text, hora_entrada time, hora_salida time)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_quien uuid := coalesce(p_persona_id, fn_persona_actual_id());
begin
  if v_quien is null then
    raise exception 'No autorizado.';
  end if;
  if p_persona_id is not null and p_persona_id is distinct from fn_persona_actual_id()
     and fn_puede_resolver_disponibilidad(p_persona_id) is not true then
    raise exception 'No autorizado.';
  end if;
  -- La regla vive en fn_turno_cambio_candidatas_de (abajo), la misma que usan las puertas.
  return query
    select p.id, trim(p.nombres || ' ' || coalesce(p.apellidos, '')), t.hora_entrada, t.hora_salida
      from fn_turno_cambio_candidatas_de(p_fecha, v_quien) c
      join personas p on p.id = c.persona_id
      join turnos t on t.persona_id = p.id and t.fecha = p_fecha
     order by t.hora_entrada, p.nombres;
end;
$$;

comment on function fn_turno_cambio_candidatas(date, uuid) is
  'Con quién se puede cambiar el turno ese día: su sede, activa, turno distinto del mismo largo, sin otro '
  'cambio vivo. Sin p_persona_id, para quien llama; con él, solo si quien llama la resuelve. 0592.';

revoke all on function fn_turno_cambio_candidatas(date, uuid) from public, anon;
grant execute on function fn_turno_cambio_candidatas(date, uuid) to authenticated;

-- ── 3 · Lo que comparten las puertas ─────────────────────────────────────────

create or replace function fn_turno_cambio_crear_interno(
  p_fecha date, p_solicitante uuid, p_companera uuid, p_propuesto_por uuid, p_pedido uuid, p_comentario text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ts turnos%rowtype;
  v_tc turnos%rowtype;
  v_id uuid;
begin
  if p_fecha is null or p_fecha < fn_hoy_lima() then
    raise exception 'Ese día ya pasó.';
  end if;
  if p_fecha > fn_hoy_lima() + 21 then
    raise exception 'Solo se cambian turnos de las próximas tres semanas.';
  end if;
  if p_companera is null or p_companera = p_solicitante then
    raise exception 'Elige con qué compañera cambiarlo.';
  end if;
  if not exists (select 1 from fn_turno_cambio_candidatas_de(p_fecha, p_solicitante) c where c.persona_id = p_companera) then
    raise exception 'Con esa compañera no se puede: tiene que ser de tu sede y trabajar ese día un turno distinto del mismo largo.';
  end if;
  if fn_fecha_en_periodo_pagado(p_fecha, p_solicitante) or fn_fecha_en_periodo_pagado(p_fecha, p_companera) then
    raise exception 'Ese día cae en un periodo ya pagado.';
  end if;
  if exists (select 1 from turno_cambios where fecha = p_fecha and estado in ('propuesto', 'aceptado')
               and p_solicitante in (solicitante_id, companera_id)) then
    raise exception 'Ya hay un cambio de turno pendiente para ese día.';
  end if;

  select * into v_ts from turnos where persona_id = p_solicitante and fecha = p_fecha;
  select * into v_tc from turnos where persona_id = p_companera and fecha = p_fecha;

  insert into turno_cambios (fecha, solicitante_id, companera_id, propuesto_por, pedido_id,
                             sol_entrada, sol_salida, comp_entrada, comp_salida, comentario)
  values (p_fecha, p_solicitante, p_companera, p_propuesto_por, p_pedido,
          v_ts.hora_entrada, v_ts.hora_salida, v_tc.hora_entrada, v_tc.hora_salida,
          nullif(trim(p_comentario), ''))
  returning id into v_id;
  return v_id;
end;
$$;

-- Intercambia los dos turnos. Los dos o ninguno: si alguno ya no es el de la foto, se niega.
create or replace function fn_turno_cambio_aplicar_interno(p_id uuid, p_firma uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c  turno_cambios%rowtype;
  v_ts turnos%rowtype;
  v_tc turnos%rowtype;
  v_motivo text;
begin
  select * into v_c from turno_cambios where id = p_id for update;
  if v_c.fecha < fn_hoy_lima() then
    raise exception 'Ese día ya pasó: el cambio ya no se puede aplicar.';
  end if;
  if fn_fecha_en_periodo_pagado(v_c.fecha, v_c.solicitante_id) or fn_fecha_en_periodo_pagado(v_c.fecha, v_c.companera_id) then
    raise exception 'Ese día cae en un periodo ya pagado.';
  end if;
  select * into v_ts from turnos where persona_id = v_c.solicitante_id and fecha = v_c.fecha for update;
  select * into v_tc from turnos where persona_id = v_c.companera_id and fecha = v_c.fecha for update;
  if v_ts.id is null or v_tc.id is null or v_ts.es_descanso or v_tc.es_descanso
     or (v_ts.hora_entrada, v_ts.hora_salida) is distinct from (v_c.sol_entrada, v_c.sol_salida)
     or (v_tc.hora_entrada, v_tc.hora_salida) is distinct from (v_c.comp_entrada, v_c.comp_salida) then
    raise exception 'Uno de los dos turnos cambió desde que se propuso el cambio. Hay que proponerlo de nuevo.';
  end if;

  update turnos set hora_entrada = v_c.comp_entrada, hora_salida = v_c.comp_salida,
                    origen = 'panel', created_at = now(), creado_por = p_firma
   where id = v_ts.id;
  update turnos set hora_entrada = v_c.sol_entrada, hora_salida = v_c.sol_salida,
                    origen = 'panel', created_at = now(), creado_por = p_firma
   where id = v_tc.id;

  -- Empieza con «Turno del DD/MM/YYYY»: el historial saca el día de ahí (0587).
  v_motivo := 'Turno del ' || to_char(v_c.fecha, 'DD/MM/YYYY')
           || ' cambiado con una compañera: lo pidieron, la compañera aceptó y lo aprobó su líder o DO. '
           || 'Las dos trabajan las mismas horas ese día.';
  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (null, v_c.solicitante_id, 'turnos.horario', fn_turno_texto(false, v_c.sol_entrada, v_c.sol_salida),
     fn_turno_texto(false, v_c.comp_entrada, v_c.comp_salida), p_firma, v_motivo),
    (null, v_c.companera_id, 'turnos.horario', fn_turno_texto(false, v_c.comp_entrada, v_c.comp_salida),
     fn_turno_texto(false, v_c.sol_entrada, v_c.sol_salida), p_firma, v_motivo);

  perform fn_recalcular_jornada(v_c.solicitante_id, v_c.fecha);
  perform fn_recalcular_jornada(v_c.companera_id, v_c.fecha);

  update turno_cambios set estado = 'aprobado',
         resuelto_por = coalesce(resuelto_por, p_firma), resuelto_at = coalesce(resuelto_at, now())
   where id = p_id;

  -- Si salió de «Este día no me calza», ese pedido queda resuelto con la resolución reservada en la 0587.
  if v_c.pedido_id is not null then
    update turno_pedidos
       set estado = 'resuelto', resolucion = 'cambio_companera', resuelto_por = p_firma, resuelto_at = now(),
           respuesta = coalesce(respuesta, 'Te lo cambiamos con una compañera: mira tu turno nuevo en «Mis turnos».')
     where id = v_c.pedido_id and estado = 'abierto';
  end if;
end;
$$;

revoke all on function fn_turno_cambio_crear_interno(date, uuid, uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function fn_turno_cambio_candidatas_de(date, uuid) from public, anon, authenticated;
revoke all on function fn_turno_cambio_aplicar_interno(uuid, uuid) from public, anon, authenticated;

-- ── 4 · Las puertas ──────────────────────────────────────────────────────────

create or replace function fn_turno_cambio_proponer(p_fecha date, p_companera_id uuid, p_comentario text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
begin
  if v_yo is null or not exists (select 1 from personas where id = v_yo and estado = 'activo') then
    raise exception 'No autorizado.';
  end if;
  return fn_turno_cambio_crear_interno(p_fecha, v_yo, p_companera_id, v_yo, null, p_comentario);
end;
$$;

comment on function fn_turno_cambio_proponer(date, uuid, text) is
  'Ella le propone a una compañera cambiarse el turno de ese día. Va a la compañera y, si acepta, a su líder. 0592.';

create or replace function fn_turno_cambio_proponer_por_pedido(p_pedido_id uuid, p_companera_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_p  turno_pedidos%rowtype;
begin
  select * into v_p from turno_pedidos where id = p_pedido_id;
  if not found or v_p.estado <> 'abierto' then
    raise exception 'Ese pedido ya no espera respuesta.';
  end if;
  if fn_puede_resolver_disponibilidad(v_p.persona_id) is not true
     or fn_puede_resolver_disponibilidad(p_companera_id) is not true then
    raise exception 'Este cambio lo propone su líder de equipo o Desarrollo Organizacional.';
  end if;
  return fn_turno_cambio_crear_interno(v_p.fecha, v_p.persona_id, p_companera_id, fn_persona_actual_id(),
                                       p_pedido_id, null);
end;
$$;

comment on function fn_turno_cambio_proponer_por_pedido(uuid, uuid) is
  'Desde un pedido de «Este día no me calza», su líder o DO propone cambiarlo con una compañera. Basta con que '
  'la compañera acepte: quien lo propuso ya lo aprobó. 0592.';

create or replace function fn_turno_cambio_contestar(p_id uuid, p_acepta boolean, p_respuesta text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c  turno_cambios%rowtype;
begin
  select * into v_c from turno_cambios where id = p_id for update;
  if not found or v_c.companera_id is distinct from fn_persona_actual_id() then
    raise exception 'Este cambio lo contesta la compañera a la que se lo pidieron.';
  end if;
  if v_c.estado <> 'propuesto' then
    raise exception 'Este cambio ya no espera tu respuesta (está %).', v_c.estado;
  end if;
  if p_acepta is null then
    raise exception 'Di si aceptas o no.';
  end if;

  update turno_cambios
     set estado = case when p_acepta then 'aceptado' else 'rechazado' end,
         contestado_at = now(), respuesta_companera = nullif(trim(p_respuesta), '')
   where id = p_id;

  -- Lo propuso su líder o DO: ya está aprobado, se aplica.
  if p_acepta and v_c.propuesto_por <> v_c.solicitante_id then
    perform fn_turno_cambio_aplicar_interno(p_id, v_c.propuesto_por);
  end if;
end;
$$;

comment on function fn_turno_cambio_contestar(uuid, boolean, text) is
  'La compañera acepta o no el cambio de turno. Si lo propuso su líder o DO, aceptar lo aplica. 0592.';

create or replace function fn_turno_cambio_resolver(p_id uuid, p_aprueba boolean, p_respuesta text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c  turno_cambios%rowtype;
  v_yo uuid := fn_persona_actual_id();
begin
  select * into v_c from turno_cambios where id = p_id for update;
  if not found then
    raise exception 'Ese cambio no existe.';
  end if;
  if fn_puede_resolver_disponibilidad(v_c.solicitante_id) is not true
     or fn_puede_resolver_disponibilidad(v_c.companera_id) is not true then
    raise exception 'Este cambio lo aprueba su líder de equipo o Desarrollo Organizacional.';
  end if;
  if v_c.estado <> 'aceptado' then
    raise exception 'Este cambio no espera aprobación (está %).', v_c.estado;
  end if;
  if p_aprueba is null then
    raise exception 'Di si lo apruebas o no.';
  end if;
  if not p_aprueba and (p_respuesta is null or length(trim(p_respuesta)) < 5) then
    raise exception 'Si no lo apruebas, explícales por qué (al menos 5 caracteres).';
  end if;

  update turno_cambios set respuesta = nullif(trim(p_respuesta), ''), resuelto_por = v_yo, resuelto_at = now(),
         estado = case when p_aprueba then estado else 'no_aprobado' end
   where id = p_id;
  if p_aprueba then
    perform fn_turno_cambio_aplicar_interno(p_id, v_yo);
  end if;
end;
$$;

comment on function fn_turno_cambio_resolver(uuid, boolean, text) is
  'Su líder (de las dos) o DO aprueba o no un cambio que la compañera ya aceptó. Aprobar intercambia los dos '
  'turnos; no aprobar exige decir por qué. 0592.';

create or replace function fn_turno_cambio_retirar(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update turno_cambios set estado = 'retirado'
   where id = p_id and propuesto_por = fn_persona_actual_id() and estado in ('propuesto', 'aceptado');
  if not found then
    raise exception 'Solo quien lo propuso lo retira, y solo mientras no está aplicado.';
  end if;
end;
$$;

-- Lo que ve ella en «Lo mío»: sus cambios, de los dos lados, con el nombre de la otra.
create or replace function fn_turno_cambios_mios()
returns table (id uuid, fecha date, soy text, otra_nombre text, mi_entrada time, mi_salida time,
               otra_entrada time, otra_salida time, estado text, comentario text,
               respuesta_companera text, respuesta text, lo_propuso_su_lider boolean,
               creado_at timestamptz, contestado_at timestamptz, resuelto_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.fecha,
         case when c.solicitante_id = fn_persona_actual_id() then 'solicitante' else 'companera' end,
         trim(o.nombres || ' ' || coalesce(o.apellidos, '')),
         case when c.solicitante_id = fn_persona_actual_id() then c.sol_entrada else c.comp_entrada end,
         case when c.solicitante_id = fn_persona_actual_id() then c.sol_salida else c.comp_salida end,
         case when c.solicitante_id = fn_persona_actual_id() then c.comp_entrada else c.sol_entrada end,
         case when c.solicitante_id = fn_persona_actual_id() then c.comp_salida else c.sol_salida end,
         c.estado, c.comentario, c.respuesta_companera, c.respuesta,
         c.propuesto_por <> c.solicitante_id,
         c.creado_at, c.contestado_at, c.resuelto_at
    from turno_cambios c
    join personas o on o.id = case when c.solicitante_id = fn_persona_actual_id() then c.companera_id else c.solicitante_id end
   where fn_persona_actual_id() in (c.solicitante_id, c.companera_id)
   order by c.creado_at desc, c.id desc
   limit 50;
$$;

revoke all on function fn_turno_cambio_proponer(date, uuid, text) from public, anon;
revoke all on function fn_turno_cambio_proponer_por_pedido(uuid, uuid) from public, anon;
revoke all on function fn_turno_cambio_contestar(uuid, boolean, text) from public, anon;
revoke all on function fn_turno_cambio_resolver(uuid, boolean, text) from public, anon;
revoke all on function fn_turno_cambio_retirar(uuid) from public, anon;
revoke all on function fn_turno_cambios_mios() from public, anon;
grant execute on function fn_turno_cambio_proponer(date, uuid, text) to authenticated;
grant execute on function fn_turno_cambio_proponer_por_pedido(uuid, uuid) to authenticated;
grant execute on function fn_turno_cambio_contestar(uuid, boolean, text) to authenticated;
grant execute on function fn_turno_cambio_resolver(uuid, boolean, text) to authenticated;
grant execute on function fn_turno_cambio_retirar(uuid) to authenticated;
grant execute on function fn_turno_cambios_mios() to authenticated;

-- ── 5 · Registro ─────────────────────────────────────────────────────────────

insert into migraciones_aplicadas (numero, nombre) values (592, 'cambiar_el_turno_con_una_companera')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regclass('public.turno_cambios') is not null                                         as la_tabla_existe,
  (select relrowsecurity from pg_class where oid = 'public.turno_cambios'::regclass)        as tiene_rls,
  not has_table_privilege('authenticated', 'public.turno_cambios', 'INSERT')                as nadie_escribe_directo,
  not has_function_privilege('authenticated', 'fn_turno_cambio_aplicar_interno(uuid,uuid)', 'EXECUTE') as aplicar_es_interno,
  to_regprocedure('fn_turno_cambio_resolver(uuid,boolean,text)') is not null                as la_aprobacion_existe,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 592)          as registro;
