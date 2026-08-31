-- ============================================================================
-- 0330_una_persona_puede_pedir_sus_vacaciones.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que una persona pida sus propias vacaciones desde "Lo mío" (fechas +
--   comentario opcional), que Desarrollo Organizacional las apruebe o las
--   rechace desde el panel, y que aprobar cree la ausencia real —la misma
--   que ya paga y ya cuenta contra el saldo— sin inventar un segundo cálculo.
--
-- QUÉ ASUME
--   Nada nuevo. Tabla nueva, funciones nuevas. No toca `ausencias`,
--   `tipos_ausencia` ni ninguna función existente.
--
-- ── POR QUÉ UNA TABLA APARTE, Y NO INSERTAR DIRECTO EN `ausencias` ──────────
--
-- `tipos_ausencia.vacaciones.requiere_aprobacion` es `false` (0101): hoy
-- registrar una vacación ES aprobarla, porque quien la registra es DO o la
-- encargada, y su acto de escribirla ya es la decisión. Ponerlo en `true`
-- para habilitar esta pantalla habría cambiado ese comportamiento para TODA
-- vacación futura, incluida la que DO sigue registrando a mano — un permiso
-- compartido que hoy decide una sola cosa pasaría a decidir dos.
--
-- Y crear un tipo paralelo (`vacaciones_solicitada`) habría sido la otra
-- forma de romperlo: la vista `vacaciones`, `fn_vacaciones_saldo` y
-- `fn_vacaciones_truncas` filtran por `tipo = 'vacaciones'` a secas. Dos
-- tipos para la misma pregunta es exactamente el accidente que ya pasó con
-- `fn_vacaciones_por_vencer` en la 0297/0299 (dos funciones, una pregunta) y
-- que la 0301 tuvo que deshacer.
--
-- `solicitudes_vacaciones` vive fuera de `ausencias` a propósito: mientras
-- está pendiente NO es una ausencia real, no cuenta contra el saldo, no
-- aparece en ninguna liquidación. Solo se convierte en una fila de
-- `ausencias` —con `fn_registrar_ausencia`, la misma función de siempre— en
-- el instante en que DO aprueba. Un rechazo no deja rastro en `ausencias`
-- porque nunca debió estar ahí.
--
-- ── POR QUÉ LA APRUEBA DO Y NO LA ENCARGADA DE LA SEDE ──────────────────────
--
-- Porque `fn_aprobar_ausencia` ya decidió esto para toda ausencia que paga,
-- con esta frase en su propio cuerpo: "La aprobación es de DO, no de la
-- sede: es lo único que convierte días en plata". Las vacaciones pagan.
-- Copiar el "aprueba el jefe directo" de un competidor sin mirar esto habría
-- abierto, para vacaciones, un permiso más ancho que el que ya existe para
-- cualquier otra ausencia remunerada — sin que nadie lo hubiera decidido así
-- a propósito.
--
-- ── POR QUÉ "CANCELADA" Y NO UN DELETE (a diferencia de `fn_quitar_revision`) ─
--
-- `revisiones_pedidas` borra la fila al retirarla porque una revisión
-- retirada no le importa a nadie más. Una solicitud de vacaciones retirada
-- sí puede importarle a DO —"pidió y se arrepintió" es una fecha que alguien
-- más pudo haber empezado a mirar—, y este repositorio no borra registros de
-- personas salvo que sea ruido puro. Se marca `cancelada` y queda.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_solicitudes_vacaciones(boolean);
--   drop function if exists fn_cancelar_solicitud_vacaciones(uuid);
--   drop function if exists fn_resolver_solicitud_vacaciones(uuid, boolean, text);
--   drop function if exists fn_solicitar_vacaciones(date, date, text);
--   drop table if exists solicitudes_vacaciones;
--   Revertir significa volver a que pedir vacaciones sea siempre "habla con
--   tu encargada" — ninguna ausencia ya aprobada se ve afectada, porque
--   nacieron como filas normales de `ausencias` vía `fn_registrar_ausencia`.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

-- ── 1 · La solicitud, mientras no es una ausencia todavía ───────────────────
create table if not exists solicitudes_vacaciones (
  id            uuid primary key default gen_random_uuid(),
  persona_id    uuid not null references personas(id),
  fecha_inicio  date not null,
  fecha_fin     date not null,
  comentario    text,
  estado        text not null default 'pendiente'
                  check (estado in ('pendiente', 'aprobada', 'rechazada', 'cancelada')),
  pedida_at     timestamptz not null default now(),
  resuelta_at   timestamptz,
  resuelta_por  uuid references personas(id),
  respuesta     text,
  -- La ausencia real que nació de esta solicitud al aprobarse. Null mientras
  -- está pendiente, y siempre null si termina rechazada o cancelada.
  ausencia_id   uuid references ausencias(id),
  constraint chk_solicitud_vacaciones_rango check (fecha_fin >= fecha_inicio),
  constraint chk_solicitud_vacaciones_resuelta_completa check (
    estado = 'pendiente' or (resuelta_at is not null and resuelta_por is not null)
  ),
  constraint chk_solicitud_vacaciones_ausencia_solo_si_aprobada check (
    (estado = 'aprobada') = (ausencia_id is not null)
  )
);

comment on table solicitudes_vacaciones is
  'Una persona pide sus vacaciones; DO aprueba o rechaza. Aprobar crea la fila real en `ausencias` via fn_registrar_ausencia — esta tabla nunca es la fuente de verdad de una ausencia, solo del pedido.';
comment on column solicitudes_vacaciones.ausencia_id is
  'La ausencia que esta solicitud produjo al aprobarse. Trazabilidad, no una segunda fuente: la ausencia manda desde que existe.';

create index if not exists idx_solicitudes_vacaciones_persona
  on solicitudes_vacaciones (persona_id, pedida_at desc);
create index if not exists idx_solicitudes_vacaciones_pendientes
  on solicitudes_vacaciones (pedida_at) where estado = 'pendiente';

-- Dos solicitudes pendientes de la misma persona no pueden pedir días que se
-- crucen: sin esto, alguien podría reservar el mismo rango dos veces con dos
-- solicitudes distintas mientras ninguna está resuelta todavía. Usa la misma
-- técnica que `ausencias_sin_solape` (btree_gist ya está habilitado desde la 0101).
alter table solicitudes_vacaciones drop constraint if exists solicitudes_vacaciones_pendientes_sin_solape;
alter table solicitudes_vacaciones add constraint solicitudes_vacaciones_pendientes_sin_solape
  exclude using gist (
    persona_id with =,
    daterange(fecha_inicio, fecha_fin, '[]') with &&
  ) where (estado = 'pendiente');

alter table solicitudes_vacaciones enable row level security;

drop policy if exists solicitudes_vacaciones_select_propia on solicitudes_vacaciones;
create policy solicitudes_vacaciones_select_propia on solicitudes_vacaciones
  for select to authenticated using (persona_id = fn_persona_actual_id());

drop policy if exists solicitudes_vacaciones_select_admin_lider on solicitudes_vacaciones;
create policy solicitudes_vacaciones_select_admin_lider on solicitudes_vacaciones
  for select to authenticated using (fn_es_admin_o_lider() is true);

-- Sin policies de insert/update/delete: toda escritura pasa por las RPC
-- security definer de abajo — mismo patrón que `revisiones_pedidas` (0257).
grant select on solicitudes_vacaciones to authenticated;
revoke all on solicitudes_vacaciones from anon, public;

-- ── 2 · Pedir ─────────────────────────────────────────────────────────────
create or replace function fn_solicitar_vacaciones(
  p_fecha_inicio date,
  p_fecha_fin    date,
  p_comentario   text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_persona uuid := fn_persona_actual_id();
  v_saldo   jsonb;
  v_dias    int;
  -- numeric, no int: `dias_pendientes` puede traer decimales (el récord en
  -- curso se gana proporcional al mes), y `'12.50'::int` directamente falla
  -- en Postgres — hay que pasar por numeric primero.
  v_pend    numeric;
  v_id      uuid;
begin
  if v_persona is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.';
  end if;

  if p_fecha_fin < p_fecha_inicio then
    raise exception 'La fecha de fin no puede ser anterior a la de inicio.';
  end if;

  if p_fecha_inicio < fn_hoy_lima() then
    raise exception 'No se pueden solicitar vacaciones para una fecha que ya pasó.';
  end if;

  -- Reutiliza el mismo cálculo que ya ve la persona en "Lo mío": nunca un
  -- segundo criterio de saldo que pudiera decir algo distinto.
  v_saldo := fn_vacaciones_saldo(v_persona, null);
  if coalesce((v_saldo ->> 'aplica')::boolean, false) is not true then
    raise exception 'No tienes vacaciones acumuladas para solicitar.';
  end if;

  v_dias := (p_fecha_fin - p_fecha_inicio) + 1;
  v_pend := coalesce((v_saldo ->> 'dias_pendientes')::numeric, 0);
  if v_dias::numeric > v_pend then
    -- `floor(...)::int` es solo para el mensaje: nadie quiere leer "14.33
    -- días pendientes". La comparación de arriba ya usó el valor exacto.
    raise exception 'Pides % día(s) y tienes % pendiente(s). Ajusta el rango.', v_dias, floor(v_pend)::int;
  end if;

  -- Chequeo temprano y legible contra ausencias YA reales. La red final —para
  -- carreras entre dos solicitudes a la vez— es la propia exclusion
  -- constraint de `ausencias`, capturada más abajo.
  if exists (
    select 1 from ausencias
    where persona_id = v_persona and anulada_at is null
      and daterange(fecha_inicio, fecha_fin, '[]') && daterange(p_fecha_inicio, p_fecha_fin, '[]')
  ) then
    raise exception 'Ya tienes una ausencia registrada que se cruza con esas fechas.';
  end if;

  insert into solicitudes_vacaciones (persona_id, fecha_inicio, fecha_fin, comentario)
  values (v_persona, p_fecha_inicio, p_fecha_fin, nullif(trim(p_comentario), ''))
  returning id into v_id;

  return v_id;
exception
  when exclusion_violation then
    raise exception 'Ya tienes otra solicitud pendiente que se cruza con esas fechas.';
end;
$fn$;
grant execute on function fn_solicitar_vacaciones(date, date, text) to authenticated;
revoke execute on function fn_solicitar_vacaciones(date, date, text) from public, anon;

-- ── 3 · Retirar la propia, mientras siga pendiente ──────────────────────────
create or replace function fn_cancelar_solicitud_vacaciones(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  update solicitudes_vacaciones
  set estado = 'cancelada', resuelta_at = now(), resuelta_por = v_persona
  where id = p_id and persona_id = v_persona and estado = 'pendiente';

  if not found then
    raise exception 'Esa solicitud no existe, no es tuya, o ya fue resuelta.';
  end if;
end;
$fn$;
grant execute on function fn_cancelar_solicitud_vacaciones(uuid) to authenticated;
revoke execute on function fn_cancelar_solicitud_vacaciones(uuid) from public, anon;

-- ── 4 · Resolver — solo DO, igual que fn_aprobar_ausencia ───────────────────
create or replace function fn_resolver_solicitud_vacaciones(
  p_id       uuid,
  p_aprobar  boolean,
  p_respuesta text default null
)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_s solicitudes_vacaciones%rowtype;
  v_ausencia_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede resolver una solicitud de vacaciones.';
  end if;

  select * into v_s from solicitudes_vacaciones where id = p_id;
  if not found then raise exception 'Esa solicitud ya no existe.'; end if;
  if v_s.estado <> 'pendiente' then
    raise exception 'Esa solicitud ya fue % — no se puede resolver dos veces.', v_s.estado;
  end if;

  if p_aprobar then
    -- La misma función que usa DO para registrar cualquier ausencia a mano.
    -- Como 'vacaciones' no exige aprobación (0101), nace ya aprobada dentro
    -- de fn_registrar_ausencia — el aprobar de ESTA solicitud es lo que
    -- decidió crearla, no un segundo visto bueno pendiente.
    v_ausencia_id := fn_registrar_ausencia(
      v_s.persona_id, 'vacaciones', v_s.fecha_inicio, v_s.fecha_fin, v_s.comentario
    );
    update solicitudes_vacaciones
    set estado = 'aprobada',
        resuelta_at = now(),
        resuelta_por = fn_persona_actual_id(),
        respuesta = nullif(trim(coalesce(p_respuesta, '')), ''),
        ausencia_id = v_ausencia_id
    where id = p_id;
  else
    if coalesce(trim(p_respuesta), '') = '' then
      raise exception 'Para rechazar hace falta decir por qué, aunque sea en una línea.';
    end if;
    update solicitudes_vacaciones
    set estado = 'rechazada',
        resuelta_at = now(),
        resuelta_por = fn_persona_actual_id(),
        respuesta = trim(p_respuesta)
    where id = p_id;
  end if;
end;
$fn$;
grant execute on function fn_resolver_solicitud_vacaciones(uuid, boolean, text) to authenticated;
revoke execute on function fn_resolver_solicitud_vacaciones(uuid, boolean, text) from public, anon;

-- ── 5 · Leer, para el panel (mismo criterio de visibilidad que la tabla) ────
create or replace function fn_solicitudes_vacaciones(p_solo_pendientes boolean default true)
returns table (
  id uuid, persona_id uuid, nombre text, sede text,
  fecha_inicio date, fecha_fin date, dias int, comentario text,
  estado text, pedida_at timestamptz,
  resuelta_por_nombre text, resuelta_at timestamptz, respuesta text
)
language sql stable security definer set search_path = public as $fn$
  select s.id, s.persona_id, pe.nombres || ' ' || pe.apellidos, sd.codigo,
         s.fecha_inicio, s.fecha_fin, (s.fecha_fin - s.fecha_inicio + 1)::int, s.comentario,
         s.estado, s.pedida_at,
         res.nombres || ' ' || res.apellidos, s.resuelta_at, s.respuesta
  from solicitudes_vacaciones s
  join personas pe on pe.id = s.persona_id
  join sedes sd on sd.id = pe.sede_base_id
  left join personas res on res.id = s.resuelta_por
  where (not p_solo_pendientes or s.estado = 'pendiente')
    and (fn_es_admin_o_lider() or s.persona_id = fn_persona_actual_id())
  order by s.pedida_at desc;
$fn$;
grant execute on function fn_solicitudes_vacaciones(boolean) to authenticated;
revoke execute on function fn_solicitudes_vacaciones(boolean) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (330, 'una_persona_puede_pedir_sus_vacaciones')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables where table_name = 'solicitudes_vacaciones') as tabla_creada,
  (select count(*) from pg_proc where proname = 'fn_solicitar_vacaciones') as fn_solicitar,
  (select count(*) from pg_proc where proname = 'fn_cancelar_solicitud_vacaciones') as fn_cancelar,
  (select count(*) from pg_proc where proname = 'fn_resolver_solicitud_vacaciones') as fn_resolver,
  (select count(*) from pg_proc where proname = 'fn_solicitudes_vacaciones') as fn_leer;
