-- ============================================================================
-- 0304 — Una marca apartada deja de vivir en un solo navegador.
-- ============================================================================
--
-- QUÉ PROMETE
--
--   1 · Que una marca que el terminal no logró enviar deje de existir solo en el
--       IndexedDB de esa Mac mini, y se pueda ver desde el panel.
--   2 · Que se pueda RESOLVER: reponerla —con su hora original, no la de hoy— o
--       declararla improcedente, siempre con motivo y con rastro.
--   3 · Que el aviso rojo del terminal se apague cuando alguien la resolvió, y
--       solo entonces.
--
-- ── EL AGUJERO, TAL COMO ESTÁ HOY ───────────────────────────────────────────
--
--   Cuando el envío falla seis veces, la cola del terminal NO borra la marca: la
--   APARTA. Eso fue deliberado y es lo correcto — «una marca que una persona hizo
--   de verdad jamás se destruye»—. Lo que faltaba es todo lo que viene después:
--
--     · la marca queda en el navegador de esa Mac mini y en ningún otro sitio;
--     · el terminal muestra «⚠ N sin registrar — avisa a tu encargada», en rojo
--       y PARA SIEMPRE: nada la repone, nada la borra, nada apaga el aviso;
--     · y cuando la encargada va a mirar, no tiene dónde. `obtenerDescartadas()`
--       solo se usa para contar.
--
--   Las dos del 13-ago siguen ahí. Un aviso rojo permanente en la pantalla que
--   mira todo el equipo deja de leerse en tres días — y entonces el día que
--   aparezca una marca de verdad, nadie la va a ver. Una marca guardada que nadie
--   sabe que existe se pierde igual que una borrada, solo que más tarde.
--
-- ── POR QUÉ SE RESUELVE EN CORRECCIONES Y NO EN UNA PANTALLA NUEVA ──────────
--
--   Decidido por Felipe el 2026-08-25. Correcciones es donde YA se arregla un
--   marcaje: la apartada aparece ahí con su hora y su error, y se resuelve con el
--   mismo gesto que cualquier otra. Una pantalla propia estaría vacía casi
--   siempre, y un rincón vacío es un rincón que nadie abre.
--
-- ── POR QUÉ EL AVISO NO SE PUEDE SILENCIAR DESDE EL TERMINAL ────────────────
--
--   También decidido ese día, y contra la comodidad: un botón para quitar el
--   aviso sin tocar la marca es exactamente cómo una marca real termina sin
--   registrarse. El aviso se apaga cuando alguien decidió qué pasa con ella
--   —reponerla o declararla improcedente, con motivo— y no antes.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
--   No recoge sola las que ya cayeron: esas viven en un navegador y solo ese
--   navegador puede subirlas. El terminal las sube en cuanto vuelva a tener red
--   y alguien abra la pantalla de marcaje — así que las dos del 13-ago aparecerán
--   la próxima vez que esa Mac mini se use, no antes.
--
--   Y no cambia la cola: seguir apartando tras seis fallos sigue siendo lo
--   correcto. Lo que cambia es que apartar deja de ser el final del camino.
--
-- QUÉ ASUME
--   · `fn_registrar_marcaje(uuid, tipo_marca, timestamptz, uuid, origen_marca,
--     uuid, uuid, text)` — se LLAMA, no se reescribe: reponer una marca tiene que
--     pasar por la única puerta de escritura de marcajes, con su lógica de
--     entrada/salida y de reconciliación intacta.
--   · Que la sesión del terminal no tiene fila en `personas`, así que
--     `fn_persona_actual_id()` devuelve null para ella. De ahí sale su permiso
--     para reportar, y solo para reportar.
--   · `correcciones_auditoria`, `fn_es_admin_o_lider()`, `fn_rol_actual()`,
--     `fn_sede_actual_persona()`, `fn_hoy_lima()`.
--
-- QUÉ MUEVE AL PEGARSE
--   Nada. Crea una tabla vacía y sus funciones. Ningún marcaje, ningún pago.
--
-- CÓMO SE REVIERTE
--   drop function fn_marca_apartada_resolver(uuid, text, text);
--   drop function fn_marcas_apartadas();
--   drop function fn_marcas_apartadas_resueltas(text[]);
--   drop function fn_marca_apartada_reportar(text, uuid, tipo_marca, timestamptz, uuid, text, text);
--   drop table marcas_apartadas;
--   Ningún marcaje repuesto se deshace: esos ya son marcajes normales.
-- ============================================================================


-- ── A · La tabla ────────────────────────────────────────────────────────────
create table if not exists marcas_apartadas (
  id                uuid primary key default gen_random_uuid(),
  -- El mismo uuid con el que la cola la identifica en el navegador. Es lo que
  -- hace que subirla dos veces no la duplique, y lo que permite al terminal
  -- preguntar después si ya se resolvió.
  client_uuid       uuid not null unique,
  persona_id        uuid not null references personas(id),
  terminal_id       uuid,
  tipo              tipo_marca not null,
  motivo_otro       text,
  -- La hora en que la persona marcó, no la hora en que se supo de esto.
  timestamp_cliente timestamptz not null,
  ultimo_error      text,
  reportada_at      timestamptz not null default now(),

  resuelta_at       timestamptz,
  resuelta_por      uuid references personas(id),
  resolucion        text check (resolucion in ('repuesta', 'improcedente')),
  motivo            text,

  -- Resuelta es todo o nada: no existe «resuelta sin decir cómo» ni «con
  -- resolución pero sin fecha». Un estado a medias acá significa una marca que
  -- nadie sabe si entró.
  constraint marca_apartada_resolucion_completa check (
    (resuelta_at is null and resuelta_por is null and resolucion is null and motivo is null)
    or
    (resuelta_at is not null and resuelta_por is not null and resolucion is not null
     and motivo is not null and length(trim(motivo)) >= 3)
  )
);

comment on table marcas_apartadas is
  'Marcas que el terminal no logró enviar y apartó tras seis intentos. Existen para '
  'que dejen de vivir solo en el navegador de una Mac mini: acá se ven desde el panel '
  'y se resuelven. No son marcajes — un marcaje solo nace por fn_registrar_marcaje.';

create index if not exists idx_marcas_apartadas_sin_resolver
  on marcas_apartadas (reportada_at) where resuelta_at is null;

alter table marcas_apartadas enable row level security;

revoke all on marcas_apartadas from authenticated, anon;
grant select on marcas_apartadas to authenticated;

-- Se lee con el mismo alcance con que se corrige un marcaje: DO ve las cuatro
-- sedes, la encargada la suya. Escribir es solo por las funciones de abajo.
drop policy if exists marcas_apartadas_lectura on marcas_apartadas;
create policy marcas_apartadas_lectura on marcas_apartadas
  for select to authenticated
  using (
    fn_es_admin_o_lider()
    or exists (
      select 1 from personas p
       where p.id = marcas_apartadas.persona_id
         and fn_rol_actual() = 'supervisor_sede'::rol_usuario
         and p.sede_base_id = fn_sede_actual_persona())
  );


-- ── B · El terminal la reporta ──────────────────────────────────────────────
-- Idempotente por `client_uuid`: el terminal la sube cada vez que arranca hasta
-- que se resuelva, y subirla dos veces no la duplica ni pisa lo que ya se
-- decidió sobre ella.
--
-- El permiso: la sesión del terminal no tiene fila en `personas`, así que
-- `fn_persona_actual_id()` devuelve null para ella y eso es precisamente lo que
-- la identifica. Se acepta también a DO por si alguna vez hay que reportar una a
-- mano. Lo que NO puede hacer nadie por esta puerta es crear un marcaje: esto
-- solo deja constancia de que una marca existió y no entró.
create or replace function fn_marca_apartada_reportar(
  p_client_uuid       uuid,
  p_persona_id        uuid,
  p_tipo              tipo_marca,
  p_timestamp_cliente timestamptz,
  p_terminal_id       uuid  default null,
  p_ultimo_error      text  default null,
  p_motivo_otro       text  default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if fn_persona_actual_id() is not null and fn_es_admin_o_lider() is not true then
    raise exception 'Solo el terminal o Desarrollo Organizacional reportan una marca apartada.';
  end if;

  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Esa persona no existe.';
  end if;

  -- Si esa marca YA entró como marcaje, no hay nada que reportar: la cola del
  -- terminal se equivocó al apartarla (pasó con los rechazos por marca atrasada,
  -- migración 0068). Se devuelve null y el terminal la borra de su cola.
  if exists (select 1 from marcajes where client_uuid = p_client_uuid) then
    return null;
  end if;

  insert into marcas_apartadas
    (client_uuid, persona_id, terminal_id, tipo, motivo_otro, timestamp_cliente, ultimo_error)
  values
    (p_client_uuid, p_persona_id, p_terminal_id, p_tipo,
     nullif(trim(coalesce(p_motivo_otro, '')), ''), p_timestamp_cliente,
     nullif(trim(coalesce(p_ultimo_error, '')), ''))
  on conflict (client_uuid) do nothing
  returning id into v_id;

  -- Ya estaba reportada: se devuelve la que hay, no un error.
  if v_id is null then
    select id into v_id from marcas_apartadas where client_uuid = p_client_uuid;
  end if;

  return v_id;
end;
$$;

grant execute on function fn_marca_apartada_reportar(uuid, uuid, tipo_marca, timestamptz, uuid, text, text) to authenticated;


-- ── C · Lo que ve Correcciones ──────────────────────────────────────────────
create or replace function fn_marcas_apartadas()
returns table (
  id                uuid,
  client_uuid       uuid,
  persona_id        uuid,
  persona           text,
  sede              text,
  tipo              text,
  timestamp_cliente timestamptz,
  fecha             date,
  ultimo_error      text,
  reportada_at      timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, m.client_uuid, m.persona_id,
         p.nombres || ' ' || p.apellidos,
         coalesce(s.codigo, '?'),
         m.tipo::text,
         m.timestamp_cliente,
         (m.timestamp_cliente at time zone 'America/Lima')::date,
         m.ultimo_error,
         m.reportada_at
    from marcas_apartadas m
    join personas p on p.id = m.persona_id
    left join sedes s on s.id = p.sede_base_id
   where m.resuelta_at is null
     and ( fn_es_admin_o_lider() is true
        or ( fn_rol_actual() = 'supervisor_sede'::rol_usuario
             and p.sede_base_id = fn_sede_actual_persona() ) )
   order by m.timestamp_cliente;
$$;

grant execute on function fn_marcas_apartadas() to authenticated;


-- ── D · Resolverla ──────────────────────────────────────────────────────────
-- Dos desenlaces y ninguno silencioso. Reponer NO escribe el marcaje a mano:
-- llama a `fn_registrar_marcaje`, que es la única puerta de escritura y la que
-- sabe si esto es una entrada o una salida. Si el servidor la vuelve a rechazar,
-- el error sale a la pantalla en vez de quedar la marca «resuelta» sin haber
-- entrado.
create or replace function fn_marca_apartada_resolver(
  p_id         uuid,
  p_resolucion text,
  p_motivo     text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m   marcas_apartadas%rowtype;
  v_p   personas%rowtype;
  v_yo  uuid := fn_persona_actual_id();
begin
  select * into v_m from marcas_apartadas where id = p_id;
  if not found then raise exception 'Esa marca apartada no existe.'; end if;

  select * into v_p from personas where id = v_m.persona_id;

  if fn_es_admin_o_lider() is not true
     and not ( fn_rol_actual() = 'supervisor_sede'::rol_usuario
               and v_p.sede_base_id = fn_sede_actual_persona() ) then
    raise exception 'No puedes resolver una marca apartada de otra sede.';
  end if;

  if v_m.resuelta_at is not null then
    raise exception 'Esa marca ya se resolvió el % como «%».',
      to_char(v_m.resuelta_at, 'DD/MM/YYYY'), v_m.resolucion;
  end if;

  if p_resolucion not in ('repuesta', 'improcedente') then
    raise exception 'La resolución es «repuesta» o «improcedente» (llegó «%»).', p_resolucion;
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué. Esto decide si un día de trabajo queda registrado o no.';
  end if;

  -- Reponer: por la puerta de siempre, con la hora ORIGINAL. Si vuelve a fallar
  -- —el día ya está en un periodo pagado, por ejemplo— la excepción sube tal
  -- cual y no se marca nada como resuelto.
  if p_resolucion = 'repuesta' then
    perform fn_registrar_marcaje(
      v_m.persona_id, v_m.tipo, v_m.timestamp_cliente, v_m.client_uuid,
      'terminal'::origen_marca, v_m.terminal_id, v_p.sede_base_id, v_m.motivo_otro);
  end if;

  update marcas_apartadas
     set resuelta_at  = now(),
         resuelta_por = v_yo,
         resolucion   = p_resolucion,
         motivo       = trim(p_motivo)
   where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_m.persona_id, 'marca_apartada',
     v_m.tipo::text || ' del ' || to_char(v_m.timestamp_cliente, 'DD/MM/YYYY HH24:MI')
       || coalesce(' · ' || v_m.ultimo_error, ''),
     p_resolucion, coalesce(v_yo, v_m.persona_id), trim(p_motivo));

  return jsonb_build_object(
    'resolucion', p_resolucion,
    'persona', v_p.nombres || ' ' || v_p.apellidos,
    'marca', to_char(v_m.timestamp_cliente, 'DD/MM/YYYY HH24:MI'));
end;
$$;

grant execute on function fn_marca_apartada_resolver(uuid, text, text) to authenticated;


-- ── E · Lo que apaga el aviso del terminal ──────────────────────────────────
-- El terminal pregunta por las suyas y borra de su cola las que alguien ya
-- resolvió. No hay otra forma de apagar ese aviso, y es a propósito.
create or replace function fn_marcas_apartadas_resueltas(p_client_uuids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.client_uuid
    from marcas_apartadas m
   where m.client_uuid = any(p_client_uuids)
     and m.resuelta_at is not null
  union
  -- Y las que entraron por su cuenta: si el marcaje existe, la cola del terminal
  -- se equivocó al apartarla y no tiene sentido que la siga mostrando.
  select k.client_uuid
    from marcajes k
   where k.client_uuid = any(p_client_uuids);
$$;

grant execute on function fn_marcas_apartadas_resueltas(uuid[]) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (304, 'una_marca_apartada_deja_de_vivir_en_un_solo_navegador')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $fin$
begin
  raise notice '0304 · una marca apartada ya se ve desde el panel y se puede resolver.';
end $fin$;
