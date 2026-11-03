-- ============================================================================
-- 0587 — «Este día no me calza»
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una colaboradora pueda decir, desde «Lo mío · Mis turnos», que un día
--   ya publicado no le calza: el motivo (estudios, hijos, salud, otro trabajo,
--   otro) y lo que propone («puedo en la tarde», «puedo en la mañana», «ese día
--   no puedo»). Va a su líder de equipo; si en 48 h nadie respondió, DO lo ve
--   como suyo. Mientras tanto su turno sigue como está. La respuesta le llega a
--   su Bandeja. No mueve plata ni toca turnos: es un PEDIDO, no un cambio.
--
-- QUÉ ASUME
--   · `fn_puede_resolver_disponibilidad` (0584) dice quién resuelve lo de una
--     persona: su líder de equipo (si ella es integrante), DO o admin, nunca la
--     propia. Es la misma pregunta, así que se usa la misma función: dos
--     reglas para «quién le contesta a ella» se desincronizarían.
--   · La Bandeja (0436 → 0515) recuerda lo visto en `bandeja_vistos`.
--
-- DECIDIÓ FELIPE (2026-11-02)
--   · Va a su líder; si en 48 h nadie responde, pasa a DO con todo su
--     historial. Mientras tanto el turno sigue como está.
--   · Como respaldo, la líder o DO pueden resolverlo «cambiando con una
--     compañera». Eso es la entrega 4 y escribe turnos: acá solo queda el
--     valor de resolución reservado.
--
-- POR QUÉ ASÍ
--   · Una tabla propia y no Reportes (0483/0488): Reportes es el canal del RIT,
--     con plazos legales, Gerencia General y estadísticas de casos. Un pedido de
--     horario no es un reclamo del 43-B. El molde es «revisar un día» (0257):
--     ella pide sobre una fecha, su líder responde con un texto, y la respuesta
--     llega a su Bandeja.
--   · Las 48 h NO las mueve un cron: «pasó a DO» se calcula al leer
--     (`fn_turno_pedido_con_do`). DO puede contestar siempre; lo que cambia a
--     las 48 h es que su pantalla se lo muestra como pendiente suyo. Un cron
--     sería un job más que vigilar para algo que una comparación resuelve.
--   · «Aceptar» NO cambia el turno solo: la líder lo cambia en Turnos, con
--     fn_set_turno (que deja su rastro y lo ve el historial de la 0587 en
--     adelante). Cambiar turnos desde acá duplicaría esa puerta.
--
-- QUIÉN HACE QUÉ
--   pedir / retirar      la propia persona, activa; de hoy a 21 días adelante
--   responder            fn_puede_resolver_disponibilidad (su líder, DO, admin)
--   leer                 RLS: ella, la líder de su sede, DO y admin
--
-- ESTADOS QUE NUNCA DEBEN EXISTIR (y quién lo impide)
--   · Dos pedidos abiertos de la misma persona para el mismo día → índice
--     único parcial.
--   · Un pedido resuelto sin quién ni cuándo → CHECK.
--   · Un pedido escrito sin pasar por las funciones → sin privilegio de
--     escritura (revoke all + grant select, molde 0480/0579/0584).
--   · Que alguien se responda a sí misma → fn_puede_resolver_disponibilidad.
--
-- LA BANDEJA (lo único que REESCRIBE)
--   `fn_bandeja_marcar_visto` acepta un tipo nuevo, 'pedido_turno', y el CHECK
--   de `bandeja_vistos` también. Se copió de la versión VIGENTE, la 0515
--   (donde-vive.sh), y su md5 se pidió a PRODUCCIÓN antes de escribir
--   (2026-11-03): md5 de partida `4c580745ad94233c3ddae47efb5d7d2e`, 893
--   caracteres, sin `\r`. Coincide con el Postgres local. Si producción ya no
--   devuelve eso al pegar, PARAR: alguien la cambió en el medio.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_turno_pedido_responder(uuid, text, text);
--   drop function if exists fn_turno_pedido_retirar(uuid);
--   drop function if exists fn_turno_pedido_crear(date, text, text, text);
--   drop function if exists fn_turno_pedido_con_do(timestamptz, text);
--   drop table if exists turno_pedidos;            -- solo si nadie la usa
--   La Bandeja: volver a pegar fn_bandeja_marcar_visto y el CHECK de la 0515.
--   delete from migraciones_aplicadas where numero = 587;
--
-- CÓMO SE COMPRUEBA
--   La consulta del final: todo en true, el md5 de llegada de la Bandeja y
--   «587 · este_dia_no_me_calza».
-- ============================================================================

-- ── 1 · La tabla ─────────────────────────────────────────────────────────────

create table if not exists turno_pedidos (
  id           uuid primary key default gen_random_uuid(),
  persona_id   uuid not null references personas(id),
  fecha        date not null,
  motivo       text not null check (motivo in ('estudios', 'hijos', 'salud', 'otro_trabajo', 'otro')),
  propuesta    text not null check (propuesta in ('tarde', 'manana', 'no_puede')),
  comentario   text check (comentario is null or length(comentario) <= 300),
  estado       text not null default 'abierto' check (estado in ('abierto', 'resuelto', 'retirado')),
  creado_at    timestamptz not null default now(),
  resuelto_por uuid references personas(id),
  resuelto_at  timestamptz,
  resolucion   text check (resolucion in ('acepta', 'se_mantiene', 'cambio_companera', 'otro')),
  respuesta    text check (respuesta is null or length(respuesta) <= 500),
  constraint pedido_resuelto_completo check (
    estado <> 'resuelto' or (resuelto_por is not null and resuelto_at is not null and resolucion is not null))
);

comment on table turno_pedidos is
  '«Este día no me calza»: el pedido de una colaboradora sobre un día con turno publicado. Va a su líder; '
  'a las 48 h sin respuesta lo ve DO (fn_turno_pedido_con_do). No cambia turnos. Solo por fn_turno_pedido_*. 0587.';

create unique index if not exists idx_turno_pedido_uno_abierto
  on turno_pedidos (persona_id, fecha) where estado = 'abierto';
create index if not exists idx_turno_pedidos_abiertos on turno_pedidos (estado, creado_at);

alter table turno_pedidos enable row level security;

drop policy if exists turno_pedidos_select_admin_lider on turno_pedidos;
create policy turno_pedidos_select_admin_lider on turno_pedidos
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists turno_pedidos_select_supervisor on turno_pedidos;
create policy turno_pedidos_select_supervisor on turno_pedidos
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede'
         and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));

drop policy if exists turno_pedidos_select_propia on turno_pedidos;
create policy turno_pedidos_select_propia on turno_pedidos
  for select to authenticated using (persona_id = fn_persona_actual_id());

revoke all on turno_pedidos from anon, authenticated, public;
grant select on turno_pedidos to authenticated;

-- ── 2 · Las 48 horas, en un solo sitio ───────────────────────────────────────

create or replace function fn_turno_pedido_con_do(p_creado_at timestamptz, p_estado text)
returns boolean
language sql
stable
as $$
  select p_estado = 'abierto' and now() >= p_creado_at + interval '48 hours';
$$;

comment on function fn_turno_pedido_con_do(timestamptz, text) is
  '¿Este pedido ya pasó a DO? Abierto y con 48 h o más sin respuesta. Se calcula al leer: no hay cron. 0587.';

grant execute on function fn_turno_pedido_con_do(timestamptz, text) to authenticated;

-- ── 3 · Las puertas ──────────────────────────────────────────────────────────

create or replace function fn_turno_pedido_crear(
  p_fecha date, p_motivo text, p_propuesta text, p_comentario text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
  v_id uuid;
begin
  if v_yo is null or not exists (select 1 from personas where id = v_yo and estado = 'activo') then
    raise exception 'No autorizado.';
  end if;
  if p_fecha is null or p_fecha < fn_hoy_lima() then
    raise exception 'Ese día ya pasó. Si algo de un día pasado no está bien, pide que lo revisen desde «Mis días».';
  end if;
  if p_fecha > fn_hoy_lima() + 21 then
    raise exception 'Solo se piden días de las próximas tres semanas. Para algo más adelante, cambia tu disponibilidad.';
  end if;
  if p_motivo is null or p_motivo not in ('estudios', 'hijos', 'salud', 'otro_trabajo', 'otro') then
    raise exception 'Elige el motivo.';
  end if;
  if p_propuesta is null or p_propuesta not in ('tarde', 'manana', 'no_puede') then
    raise exception 'Elige qué te calza ese día.';
  end if;
  if exists (select 1 from turno_pedidos where persona_id = v_yo and fecha = p_fecha and estado = 'abierto') then
    raise exception 'Ya pediste ese día y tu líder todavía no te responde.';
  end if;

  insert into turno_pedidos (persona_id, fecha, motivo, propuesta, comentario)
  values (v_yo, p_fecha, p_motivo, p_propuesta, nullif(trim(p_comentario), ''))
  returning id into v_id;
  return v_id;
end;
$$;

comment on function fn_turno_pedido_crear(date, text, text, text) is
  'La colaboradora dice que un día no le calza (de hoy a 21 días). Va a su líder; su turno sigue igual. 0587.';

revoke all on function fn_turno_pedido_crear(date, text, text, text) from public, anon;
grant execute on function fn_turno_pedido_crear(date, text, text, text) to authenticated;

create or replace function fn_turno_pedido_retirar(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update turno_pedidos set estado = 'retirado'
   where id = p_id and persona_id = fn_persona_actual_id() and estado = 'abierto';
  if not found then
    raise exception 'Solo puedes retirar un pedido tuyo que todavía espera respuesta.';
  end if;
end;
$$;

revoke all on function fn_turno_pedido_retirar(uuid) from public, anon;
grant execute on function fn_turno_pedido_retirar(uuid) to authenticated;

create or replace function fn_turno_pedido_responder(p_id uuid, p_resolucion text, p_respuesta text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_p turno_pedidos%rowtype;
begin
  select * into v_p from turno_pedidos where id = p_id for update;
  if not found then
    raise exception 'Ese pedido no existe.';
  end if;
  if fn_puede_resolver_disponibilidad(v_p.persona_id) is not true then
    raise exception 'Este pedido lo responde su líder de equipo o Desarrollo Organizacional.';
  end if;
  if v_p.estado <> 'abierto' then
    raise exception 'Este pedido ya no espera respuesta (está %).', v_p.estado;
  end if;
  if p_resolucion is null or p_resolucion not in ('acepta', 'se_mantiene', 'otro') then
    -- 'cambio_companera' queda para la entrega 4, que es la que cambia los turnos.
    raise exception 'La respuesta es «acepta», «se_mantiene» u «otro».';
  end if;
  if p_resolucion in ('se_mantiene', 'otro') and (p_respuesta is null or length(trim(p_respuesta)) < 5) then
    raise exception 'Si el turno se mantiene, explícale por qué (al menos 5 caracteres).';
  end if;

  update turno_pedidos
     set estado = 'resuelto', resolucion = p_resolucion, respuesta = nullif(trim(p_respuesta), ''),
         resuelto_por = fn_persona_actual_id(), resuelto_at = now()
   where id = p_id;
end;
$$;

comment on function fn_turno_pedido_responder(uuid, text, text) is
  'Su líder (de su sede), DO o admin responde un pedido: acepta (y cambia el turno en Turnos), se_mantiene u '
  'otro, con su mensaje. Nunca la propia. No toca turnos. 0587.';

revoke all on function fn_turno_pedido_responder(uuid, text, text) from public, anon;
grant execute on function fn_turno_pedido_responder(uuid, text, text) to authenticated;

-- ── 4 · La Bandeja aprende 'pedido_turno' ────────────────────────────────────
-- Copiada de la 0515 (la vigente). md5 de partida en producción:
-- 4c580745ad94233c3ddae47efb5d7d2e (893 car.). Único cambio: el tipo nuevo.

alter table bandeja_vistos drop constraint if exists bandeja_vistos_tipo_item_check;
alter table bandeja_vistos add constraint bandeja_vistos_tipo_item_check check (tipo_item in (
  'revision', 'revision_movilidad', 'revision_contrato',
  'solicitud_vacacion', 'solicitud_perfil',
  'entrega_educacion', 'aviso_fin_educacion',
  'solicitud_educacion',
  'cambio_turno',
  'conducta_registrada', 'caso_traspasado',
  -- ⇩ CAMBIO 0587 ⇩
  'pedido_turno'
));

create or replace function fn_bandeja_marcar_visto(p_tipo_item text, p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;
  -- ⇩ CAMBIO 0473 ⇩ cambio_turno.
  if p_tipo_item not in ('revision', 'revision_movilidad', 'revision_contrato',
                          'solicitud_vacacion', 'solicitud_perfil',
                          'entrega_educacion', 'aviso_fin_educacion',
                          'solicitud_educacion', 'cambio_turno',
                          -- CAMBIO 0515 · avisos de conducta
                          'conducta_registrada', 'caso_traspasado',
                          -- CAMBIO 0587 · «Este día no me calza»
                          'pedido_turno') then
    raise exception 'Tipo de ítem de Bandeja no reconocido: %', p_tipo_item;
  end if;

  insert into bandeja_vistos (persona_id, tipo_item, item_id)
  values (v_persona, p_tipo_item, p_item_id)
  on conflict (persona_id, tipo_item, item_id) do update set visto_at = now();
end;
$function$;

-- ── 5 · Registro ─────────────────────────────────────────────────────────────

insert into migraciones_aplicadas (numero, nombre) values (587, 'este_dia_no_me_calza')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regclass('public.turno_pedidos') is not null                                           as la_tabla_existe,
  (select relrowsecurity from pg_class where oid = 'public.turno_pedidos'::regclass)          as tiene_rls,
  not has_table_privilege('authenticated', 'public.turno_pedidos', 'INSERT')                  as nadie_escribe_directo,
  to_regprocedure('fn_turno_pedido_responder(uuid,text,text)') is not null                    as la_respuesta_existe,
  (select pg_get_constraintdef(oid) like '%pedido_turno%' from pg_constraint
    where conname = 'bandeja_vistos_tipo_item_check')                                          as la_bandeja_lo_acepta,
  (select md5(prosrc) || ' · ' || length(prosrc) from pg_proc where proname = 'fn_bandeja_marcar_visto') as bandeja_md5_de_llegada,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 587)            as registro;
