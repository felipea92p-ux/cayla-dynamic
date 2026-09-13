-- ============================================================================
-- La Bandeja recuerda lo que ya viste
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: una tabla mínima para que la Bandeja del panel (ADR 0002)
--   pueda distinguir "esto es nuevo desde tu última visita" de "esto lleva
--   días esperando y ya lo viste". No decide nada de negocio, no bloquea
--   ninguna aprobación: es una marca de tiempo por persona e ítem, nada más.
--
-- QUÉ ASUME: que `fn_persona_actual_id()` identifica a quien marca. Solo
--   cubre los 5 tipos de la zona "Por aprobar" de la Bandeja — la zona
--   informativa (sin horario, vacaciones por vencer, educación) nunca se
--   resuelve desde ahí, así que "visto" no cambiaría ninguna acción posible
--   y no se modela acá (ver ADR 0002, decisión #2).
--
-- POR QUÉ UNA TABLA Y NO UN MOTOR GENÉRICO: esta es la única señal que la
--   Bandeja hoy no puede derivar de las tablas existentes — todo lo demás
--   (orden, agrupación, filtro de sede) es una decisión de la pantalla, no
--   un dato que falte guardar. Antes de meter esto en el núcleo se probó que
--   NO puede vivir afuera (principio de núcleo mínimo): ningún RPC existente
--   guarda "quién vio qué", y fingirlo con localStorage se perdería al
--   cambiar de dispositivo, cosa que si pasa en este equipo (Mac mini de
--   sede + laptop personal).
--
-- CÓMO SE REVIERTE:
--   drop function if exists fn_bandeja_marcar_visto(text, uuid);
--   drop table if exists bandeja_vistos cascade;
--   No cuelga nada de esta tabla: ningún cálculo de planilla ni de asistencia
--   la lee. Borrarla solo hace que la Bandeja vuelva a mostrar todo como
--   "nuevo" siempre.
--
-- Idempotente: `create table if not exists`, `create or replace`, política
-- con `drop policy if exists` delante.
-- ============================================================================

create table if not exists bandeja_vistos (
  persona_id uuid not null references personas(id),
  -- Los 5 tipos de la zona "Por aprobar" (ADR 0002). Un valor fuera de esta
  -- lista es un error de quien llama, no un tipo nuevo silencioso.
  tipo_item  text not null check (tipo_item in (
    'revision', 'revision_movilidad', 'revision_contrato',
    'solicitud_vacacion', 'solicitud_perfil'
  )),
  item_id    uuid not null,
  visto_at   timestamptz not null default now(),
  primary key (persona_id, tipo_item, item_id)
);

comment on table bandeja_vistos is
  'Qué ítem de la zona "Por aprobar" de la Bandeja ya vio cada persona '
  '(ADR 0002, decisión #2). Escritura solo por fn_bandeja_marcar_visto — '
  'lectura directa por policy, sin RPC, porque es un solo campo sin join.';

alter table bandeja_vistos enable row level security;

-- Lectura: la propia, sin excepción — ni admin ni líder necesitan ver qué
-- vio otra persona, esto no es una auditoría, es una preferencia de cada
-- quien mira su propia Bandeja.
drop policy if exists bandeja_vistos_select_propia on bandeja_vistos;
create policy bandeja_vistos_select_propia on bandeja_vistos
  for select to authenticated using (persona_id = fn_persona_actual_id());

grant select on bandeja_vistos to authenticated;
revoke all on bandeja_vistos from anon, public;

-- ---------------------------------------------------------------------------
-- Marcar visto. Upsert: volver a marcar el mismo ítem solo actualiza el
-- momento, no falla ni crea una segunda fila.
-- ---------------------------------------------------------------------------
create or replace function fn_bandeja_marcar_visto(p_tipo_item text, p_item_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;
  if p_tipo_item not in ('revision', 'revision_movilidad', 'revision_contrato',
                          'solicitud_vacacion', 'solicitud_perfil') then
    raise exception 'Tipo de ítem de Bandeja no reconocido: %', p_tipo_item;
  end if;

  insert into bandeja_vistos (persona_id, tipo_item, item_id)
  values (v_persona, p_tipo_item, p_item_id)
  on conflict (persona_id, tipo_item, item_id) do update set visto_at = now();
end;
$$;

grant execute on function fn_bandeja_marcar_visto(text, uuid) to authenticated;
revoke execute on function fn_bandeja_marcar_visto(text, uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (435, 'la_bandeja_recuerda_lo_que_ya_viste')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables where table_name = 'bandeja_vistos') as tabla_creada,
  (select count(*) from pg_proc where proname = 'fn_bandeja_marcar_visto') as fn_marcar;
