-- ============================================================================
-- 0348_el_tablon_de_anuncios_de_do.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que Desarrollo Organizacional pueda publicar un comunicado (cierre de
--   planilla, feriado, política nueva) que las cuatro sedes vean dentro del
--   sistema, con fecha de publicación y quién lo escribió, en vez de que ese
--   aviso solo exista en un chat de WhatsApp que nadie puede volver a
--   encontrar dos meses después.
--
-- QUÉ ASUME
--   Nada nuevo. Tablas nuevas, funciones nuevas. No toca `ausencias`,
--   `documentos_institucionales` ni ninguna función existente.
--
-- ── POR QUÉ UNA TABLA APARTE, Y NO UN TIPO MÁS DE `documentos_institucionales` ──
--
-- `documentos_institucionales` (0208) existe para lo que la ley obliga a
-- probar que se entregó: versiona el texto, lo CONGELA al publicar, y exige
-- un acuse legal —por sistema o por papel escaneado, para las personas sin
-- cuenta— porque ahí la constancia es la prueba en un procedimiento. Un
-- anuncio de "mañana es feriado" no es eso: no hay ninguna norma que exija
-- poder demostrar quién lo leyó, y forzarlo por ese camino habría significado
-- pedirle a alguien un acuse formal por cada aviso operativo — el aviso deja
-- de leerse como información y empieza a leerse como trámite, y un trámite
-- de más es exactamente lo que hace que la gente deje de leer el primero.
--
-- Por eso acá la "lectura" es un marcador liviano (`anuncios_leidos`, sin
-- vía 'papel', sin archivo firmado): sirve para que DO vea si un anuncio
-- caló, no para sostener una sanción.
--
-- ── POR QUÉ SE ANULA, Y NUNCA SE EDITA NI SE BORRA ──────────────────────────
--
-- Mismo criterio que el resto del repositorio: nada de las personas se borra
-- para siempre. Editar el cuerpo después de publicado dejaría a quien ya lo
-- leyó constando de un texto que nadie escribió; por eso NO hay
-- `fn_editar_anuncio`. Se anula (`anulado_at`) y, si hace falta corregir algo,
-- se publica uno nuevo — el mismo criterio que ya usa
-- `solicitudes_vacaciones` con 'cancelada' en vez de un DELETE.
--
-- ── POR QUÉ LO PUBLICA DO, Y NO LA ENCARGADA DE SEDE ─────────────────────────
--
-- El pedido que lo originó dice explícitamente "anuncios de DO", y un anuncio
-- sin dueño claro —cualquiera podría publicar a las cuatro sedes a la vez—
-- sería ruido, no comunicación. `puedeGestionarAnuncios` (packages/shared)
-- se nombra aparte de `puedeOperarEquipo`: hoy las dos listas de roles
-- coinciden con DO, pero la pregunta "quién opera ausencias/turnos del día a
-- día" y "quién habla en nombre de la empresa a las cuatro sedes" no son la
-- misma pregunta, y no deben empezar a compartir respuesta solo porque hoy
-- casualmente coinciden (ver el comentario de `puedeGestionarContratos` en el
-- mismo archivo, misma decisión).
--
-- ── POR QUÉ `sede_id` OPCIONAL, Y NO UNA TABLA DE DESTINATARIOS ──────────────
--
-- La mayoría de anuncios son para las cuatro sedes (`sede_id is null`). Un
-- anuncio de una sola sede ("Trujillo: revisen el horario del feriado") es
-- la excepción, y una sola columna nullable la cubre entera sin inventar una
-- tabla de destinatarios que, con 30 personas en 4 sedes, no tiene ningún
-- caso real que justifique su complejidad.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_marcar_anuncio_leido(uuid);
--   drop function if exists fn_anuncios_vigentes(boolean);
--   drop function if exists fn_anular_anuncio(uuid);
--   drop function if exists fn_publicar_anuncio(text, text, uuid);
--   drop table if exists anuncios_leidos;
--   drop table if exists anuncios;
--   Revertir significa volver a que el único registro de un comunicado sea
--   el chat donde se mandó.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

-- ── 1 · El anuncio ───────────────────────────────────────────────────────────
create table if not exists anuncios (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null check (btrim(titulo) <> '' and char_length(titulo) <= 200),
  cuerpo        text not null check (btrim(cuerpo) <> ''),
  -- null = las cuatro sedes. No null = solo esa sede.
  sede_id       uuid references sedes(id),
  publicado_por uuid not null references personas(id),
  publicado_at  timestamptz not null default now(),
  anulado_at    timestamptz,
  anulado_por   uuid references personas(id),
  constraint chk_anuncios_anulado_completo check (
    (anulado_at is null) = (anulado_por is null)
  )
);

comment on table anuncios is
  'Comunicados de Desarrollo Organizacional al equipo. Nunca se edita ni se borra: se anula y, si hace falta corregir, se publica uno nuevo.';
comment on column anuncios.sede_id is
  'null = las cuatro sedes. Con valor, solo esa sede lo ve.';

create index if not exists idx_anuncios_vigentes
  on anuncios (publicado_at desc) where anulado_at is null;

alter table anuncios enable row level security;

drop policy if exists anuncios_select_equipo on anuncios;
create policy anuncios_select_equipo on anuncios
  for select to authenticated using (
    anulado_at is null
    and (
      sede_id is null
      or sede_id = (select p.sede_base_id from personas p where p.id = fn_persona_actual_id())
    )
  );

drop policy if exists anuncios_select_do on anuncios;
create policy anuncios_select_do on anuncios
  for select to authenticated using (fn_es_admin_o_lider() is true);

-- Sin policies de insert/update/delete: toda escritura pasa por las RPC
-- security definer de abajo — mismo patrón que `solicitudes_vacaciones` (0330).
grant select on anuncios to authenticated;
revoke all on anuncios from anon, public;

-- ── 2 · Quién ya lo leyó — marcador liviano, no un acuse legal ──────────────
create table if not exists anuncios_leidos (
  anuncio_id uuid not null references anuncios(id),
  persona_id uuid not null references personas(id),
  leido_at   timestamptz not null default now(),
  primary key (anuncio_id, persona_id)
);

comment on table anuncios_leidos is
  'Quién ya vio cada anuncio. Marcador de alcance, no un acuse legal — para eso está documentos_institucionales.';

alter table anuncios_leidos enable row level security;

drop policy if exists anuncios_leidos_select_propia on anuncios_leidos;
create policy anuncios_leidos_select_propia on anuncios_leidos
  for select to authenticated using (persona_id = fn_persona_actual_id());

drop policy if exists anuncios_leidos_select_do on anuncios_leidos;
create policy anuncios_leidos_select_do on anuncios_leidos
  for select to authenticated using (fn_es_admin_o_lider() is true);

grant select on anuncios_leidos to authenticated;
revoke all on anuncios_leidos from anon, public;

-- ── 3 · Publicar ──────────────────────────────────────────────────────────
create or replace function fn_publicar_anuncio(
  p_titulo  text,
  p_cuerpo  text,
  p_sede_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_persona uuid := fn_persona_actual_id();
  v_id      uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede publicar un anuncio.';
  end if;

  if btrim(coalesce(p_titulo, '')) = '' then
    raise exception 'El anuncio necesita un título.';
  end if;
  if btrim(coalesce(p_cuerpo, '')) = '' then
    raise exception 'El anuncio necesita un cuerpo.';
  end if;

  if p_sede_id is not null and not exists (select 1 from sedes where id = p_sede_id) then
    raise exception 'Esa sede no existe.';
  end if;

  insert into anuncios (titulo, cuerpo, sede_id, publicado_por)
  values (btrim(p_titulo), btrim(p_cuerpo), p_sede_id, v_persona)
  returning id into v_id;

  return v_id;
end;
$fn$;
grant execute on function fn_publicar_anuncio(text, text, uuid) to authenticated;
revoke execute on function fn_publicar_anuncio(text, text, uuid) from public, anon;

-- ── 4 · Anular ────────────────────────────────────────────────────────────
create or replace function fn_anular_anuncio(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede anular un anuncio.';
  end if;

  update anuncios
  set anulado_at = now(), anulado_por = fn_persona_actual_id()
  where id = p_id and anulado_at is null;

  if not found then
    raise exception 'Ese anuncio no existe o ya estaba anulado.';
  end if;
end;
$fn$;
grant execute on function fn_anular_anuncio(uuid) to authenticated;
revoke execute on function fn_anular_anuncio(uuid) from public, anon;

-- ── 5 · Leer, para el panel y para "Lo mío" ──────────────────────────────────
create or replace function fn_anuncios_vigentes(p_incluir_anulados boolean default false)
returns table (
  id uuid, titulo text, cuerpo text,
  sede_id uuid, sede_codigo text,
  publicado_por_nombre text, publicado_at timestamptz,
  anulado_at timestamptz,
  mi_leido_at timestamptz,
  total_lectores int
)
language sql stable security definer set search_path = public as $fn$
  select a.id, a.titulo, a.cuerpo,
         a.sede_id, sd.codigo,
         pu.nombres || ' ' || pu.apellidos, a.publicado_at,
         a.anulado_at,
         al.leido_at,
         (select count(*)::int from anuncios_leidos where anuncio_id = a.id)
  from anuncios a
  join personas pu on pu.id = a.publicado_por
  left join sedes sd on sd.id = a.sede_id
  left join anuncios_leidos al on al.anuncio_id = a.id and al.persona_id = fn_persona_actual_id()
  where (
    a.anulado_at is null
    or (p_incluir_anulados and fn_es_admin_o_lider() is true)
  )
  and (
    fn_es_admin_o_lider() is true
    or a.sede_id is null
    or a.sede_id = (select p.sede_base_id from personas p where p.id = fn_persona_actual_id())
  )
  order by a.publicado_at desc;
$fn$;
grant execute on function fn_anuncios_vigentes(boolean) to authenticated;
revoke execute on function fn_anuncios_vigentes(boolean) from public, anon;

-- ── 6 · Marcar como leído — idempotente, cualquiera puede dejar su propia marca ──
create or replace function fn_marcar_anuncio_leido(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if not exists (select 1 from anuncios where id = p_id) then
    raise exception 'Ese anuncio no existe.';
  end if;

  insert into anuncios_leidos (anuncio_id, persona_id)
  values (p_id, v_persona)
  on conflict (anuncio_id, persona_id) do nothing;
end;
$fn$;
grant execute on function fn_marcar_anuncio_leido(uuid) to authenticated;
revoke execute on function fn_marcar_anuncio_leido(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (348, 'el_tablon_de_anuncios_de_do')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables where table_name = 'anuncios') as tabla_anuncios,
  (select count(*) from information_schema.tables where table_name = 'anuncios_leidos') as tabla_leidos,
  (select count(*) from pg_proc where proname = 'fn_publicar_anuncio') as fn_publicar,
  (select count(*) from pg_proc where proname = 'fn_anular_anuncio') as fn_anular,
  (select count(*) from pg_proc where proname = 'fn_anuncios_vigentes') as fn_vigentes,
  (select count(*) from pg_proc where proname = 'fn_marcar_anuncio_leido') as fn_marcar_leido;
