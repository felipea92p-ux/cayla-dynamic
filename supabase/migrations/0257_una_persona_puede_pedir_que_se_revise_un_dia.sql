-- ============================================================================
-- Una persona puede pedir que se revise un día suyo
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que lo que una integrante ve mal en «Lo mío» deje constancia, y
--   que esa constancia le llegue a quien puede arreglarlo. Ni más: pedir una
--   revisión NO cambia ningún cálculo, no toca la jornada, no justifica nada.
--   Es un mensaje con fecha, autor y respuesta.
--
-- QUÉ ASUME: que `fn_persona_actual_id()` identifica a quien pide. Quien no
--   tenga fila en `personas` no puede pedir nada — la función lanza en vez de
--   escribir una fila huérfana.
--
-- POR QUÉ: hasta hoy «Lo mío» terminaba cada sección en «avísale a tu
--   encargada». Eso, en un teléfono, es un callejón: ve que el 12 le figura
--   incompleto, cierra el navegador y se acuerda cuando llega la boleta. Y para
--   entonces el marcaje ya está dentro de un periodo cerrado.
--
--   El sistema ya sabe detectar los días raros; lo que no tenía es la voz de la
--   única persona que sabe qué pasó ese día. Esto no es un buzón de quejas: es
--   la mitad que faltaba del principio de que un marcaje se corrige, no se
--   discute a fin de mes.
--
-- LO QUE DELIBERADAMENTE NO HACE
--   · No bloquea el cierre del periodo. Una petición sin atender es una tarea,
--     no un freno: frenar la planilla de treinta personas por un comentario
--     sería un poder que nadie pidió darle a este formulario.
--   · No corrige nada sola. La corrección sigue pasando por Correcciones, con
--     su motivo y su rastro en `correcciones_auditoria`.
--   · No permite pedir revisión de un día FUTURO. Todavía no ha pasado.
--
-- CÓMO SE REVIERTE: `drop table revisiones_pedidas cascade;` y soltar las tres
--   funciones. No cuelga nada de esta tabla: ningún cálculo la lee.
--
-- Idempotente: `create table if not exists`, `create or replace`, políticas con
-- `drop policy if exists` delante.
-- ============================================================================

create table if not exists revisiones_pedidas (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  fecha date not null,
  -- El comentario es OBLIGATORIO y con un mínimo. Una petición sin texto
  -- obliga a quien la atiende a adivinar, y lo que va a hacer es cerrarla.
  comentario text not null check (length(trim(comentario)) >= 5),
  pedida_at timestamptz not null default now(),
  atendida_at timestamptz,
  atendida_por uuid references personas(id),
  respuesta text,
  -- Una por persona y día. Volver a pedirla reabre la misma fila en vez de
  -- fabricar una lista de duplicados que nadie va a leer entera.
  unique (persona_id, fecha),
  -- Atendida sin quién la atendió es un registro que no prueba nada.
  constraint chk_revision_atendida_completa
    check (atendida_at is null or atendida_por is not null)
);

create index if not exists idx_revisiones_pendientes
  on revisiones_pedidas (fecha) where atendida_at is null;

alter table revisiones_pedidas enable row level security;

-- Lectura: la suya, la de su sede, o todo si es admin/líder. Escritura SOLO por
-- las RPC de abajo — sin policies de insert/update, igual que el resto del
-- sistema: una tabla que se puede escribir por REST es una regla que vive en el
-- navegador.
drop policy if exists revisiones_select_propia on revisiones_pedidas;
create policy revisiones_select_propia on revisiones_pedidas
  for select to authenticated using (persona_id = fn_persona_actual_id());

drop policy if exists revisiones_select_admin_lider on revisiones_pedidas;
create policy revisiones_select_admin_lider on revisiones_pedidas
  for select to authenticated using (fn_es_admin_o_lider() is true);

drop policy if exists revisiones_select_supervisor on revisiones_pedidas;
create policy revisiones_select_supervisor on revisiones_pedidas
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede'
    and exists (select 1 from personas p
                where p.id = revisiones_pedidas.persona_id
                  and p.sede_base_id = fn_sede_actual_persona())
  );

-- ---------------------------------------------------------------------------
-- Pedir. Reabre si ya existía: volver a decirlo borra la respuesta anterior,
-- porque lo que se respondió antes ya no es la conversación de ahora.
-- ---------------------------------------------------------------------------
create or replace function fn_pedir_revision(p_fecha date, p_comentario text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.';
  end if;
  if p_fecha > fn_hoy_lima() then
    raise exception 'No se puede pedir revisión de un día que todavía no pasó.';
  end if;
  -- Un tope hacia atrás, y no es burocracia: más allá de tres meses el marcaje
  -- vive en periodos pagados y cerrados, y lo que hay que abrir ahí no es un
  -- comentario en una pantalla sino una conversación con Desarrollo
  -- Organizacional. Prometer que se revisa lo que ya se pagó sería mentir.
  if p_fecha < fn_hoy_lima() - 90 then
    raise exception 'Ese día tiene más de 90 días. Habla directamente con Desarrollo Organizacional.';
  end if;
  if length(trim(coalesce(p_comentario, ''))) < 5 then
    raise exception 'Cuéntanos qué pasó ese día, aunque sea en una línea.';
  end if;

  insert into revisiones_pedidas (persona_id, fecha, comentario)
  values (v_persona, p_fecha, trim(p_comentario))
  on conflict (persona_id, fecha) do update set
    comentario   = excluded.comentario,
    pedida_at    = now(),
    atendida_at  = null,
    atendida_por = null,
    respuesta    = null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Retirarla. Se dio cuenta de que estaba bien; que no pueda deshacerlo la
-- obligaría a dejar una tarea falsa en la lista de otra persona.
-- ---------------------------------------------------------------------------
create or replace function fn_quitar_revision(p_fecha date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;
  -- Solo puede retirar la SUYA, y solo mientras nadie la haya atendido: una vez
  -- respondida, la conversación ya existió y borrarla dejaría a la otra parte
  -- sin rastro de algo que sí hizo.
  delete from revisiones_pedidas
  where persona_id = v_persona and fecha = p_fecha and atendida_at is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atenderla. Guard null-safe: `is not true`, nunca `not (...)`.
-- ---------------------------------------------------------------------------
create or replace function fn_atender_revision(p_id uuid, p_respuesta text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_puede boolean;
begin
  select (fn_es_admin_o_lider() is true)
      or (fn_rol_actual() = 'supervisor_sede'
          and exists (select 1 from personas p
                      join revisiones_pedidas r on r.persona_id = p.id
                      where r.id = p_id and p.sede_base_id = fn_sede_actual_persona()))
    into v_puede;

  if v_puede is not true then
    raise exception 'Solo un administrador, un líder o la encargada de esa sede puede atender una revisión.';
  end if;

  update revisiones_pedidas
  set atendida_at  = now(),
      atendida_por = fn_persona_actual_id(),
      respuesta    = nullif(trim(coalesce(p_respuesta, '')), '')
  where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lo que el panel necesita leer, en una sola llamada y con el nombre resuelto.
-- Va por RPC jsonb y no por REST con embed: el schema cache de PostgREST está
-- trabado en este proyecto desde la 0020 y los embeds fallan sin avisar.
-- La visibilidad la repite acá porque una función `security definer` no hereda
-- las policies de la tabla.
-- ---------------------------------------------------------------------------
create or replace function fn_revisiones_pedidas(p_solo_pendientes boolean default true)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'persona_id', r.persona_id,
           'nombre', p.nombres || ' ' || p.apellidos,
           'sede', s.codigo,
           'fecha', r.fecha,
           'comentario', r.comentario,
           'pedida_at', r.pedida_at,
           'atendida_at', r.atendida_at,
           'respuesta', r.respuesta
         ) order by r.fecha desc, p.apellidos), '[]'::jsonb)
  from revisiones_pedidas r
  join personas p on p.id = r.persona_id
  join sedes s on s.id = p.sede_base_id
  where (p_solo_pendientes is not true or r.atendida_at is null)
    and (
      fn_es_admin_o_lider() is true
      or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona())
      or r.persona_id = fn_persona_actual_id()
    );
$$;

grant execute on function fn_pedir_revision(date, text)      to authenticated;
grant execute on function fn_quitar_revision(date)           to authenticated;
grant execute on function fn_atender_revision(uuid, text)    to authenticated;
grant execute on function fn_revisiones_pedidas(boolean)     to authenticated;
revoke execute on function fn_pedir_revision(date, text)     from public, anon;
revoke execute on function fn_quitar_revision(date)          from public, anon;
revoke execute on function fn_atender_revision(uuid, text)   from public, anon;
revoke execute on function fn_revisiones_pedidas(boolean)    from public, anon;

grant select on revisiones_pedidas to authenticated;

-- El rastro. Sin esta fila, `que_falta_pegar.sql` no puede decir si esta
-- migración llegó a producción, y la prueba 122 falla a propósito.
insert into migraciones_aplicadas (numero, nombre)
values (257, 'una_persona_puede_pedir_que_se_revise_un_dia')
on conflict (numero) do nothing;
