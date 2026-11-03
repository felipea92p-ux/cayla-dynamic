-- ============================================================================
-- 0593 · EL BORRADOR DE LA SEMANA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la semana que arma la líder en Turnos se pueda GUARDAR sin publicarla:
--   un borrador por sede y semana, que sobrevive a recargar la página, que ven
--   la líder de esa sede, DO y admin, y que se compara contra lo publicado
--   antes de decidir. Hasta hoy la propuesta de «Sugerir la semana» (0586)
--   vivía solo en la pantalla: o se publicaba en ese momento o se perdía.
--
--   El borrador tiene dos cosas:
--     · los DÍAS: para cada persona y fecha, su turno (entrada y salida) o su
--       descanso (las dos en null). Es lo que se publica.
--     · las NOTAS: un texto por persona. Es lo que se usa con quien factura por
--       recibo por honorarios (RxH): no tiene jornada ni horario (RIT 2.5 y
--       9.7), así que no se le pone turno, pero la líder necesita anotar
--       «se la necesita el sábado de 12 a 16». Decisión de Felipe
--       (2026-11-03): «sin horario, pero solo hacer un borrador para saber
--       cuándo se la necesita, como una nota; lo puede ver la líder, DO y
--       superiores». Una nota NUNCA se publica ni la ve la persona.
--
--   Y una puerta para publicarlo: `fn_turnos_borrador_publicar` exige que lo
--   que se publica sea exactamente lo del borrador, lo publica con
--   `fn_publicar_semana` (0586) —sus permisos, su regla del turno propio de la
--   líder, su todo o nada— y marca el borrador como publicado, en la misma
--   transacción.
--
-- QUÉ ASUME
--   · `fn_publicar_semana(uuid, date, jsonb, text)` vigente en la 0586
--     (donde-vive.sh). Esta migración la LLAMA, no la reescribe.
--   · Quién toca la semana de una sede es lo que ya dice la 0586: admin, Líder
--     DO, o la líder de equipo de esa sede. Se repite esa misma condición.
--   · `personas.tipo_vinculo` con los valores de la 0322: a 'rxh' y a
--     'no_trabajador' no les corresponde horario (`leCorrespondeHorario`,
--     packages/shared/src/vinculo.ts).
--
-- POR QUÉ ASÍ
--   · Una tabla nueva y no escribir en `turnos`: lo que está en `turnos` es lo
--     que el terminal, la planilla y «Lo mío» toman por cierto. Un borrador ahí
--     sería un turno a medias que alguien ya está leyendo.
--   · Uno VIVO por sede y lunes (índice único parcial): dos borradores de la
--     misma semana serían dos verdades sobre qué se va a publicar. Los
--     publicados y descartados se quedan: dicen qué se propuso y quién lo
--     decidió.
--   · Guardar REEMPLAZA los días y las notas del borrador vivo (todo o nada):
--     la pantalla manda la semana entera tal como la ve, que es lo que la
--     persona revisó.
--   · Lo que se publica lo calcula la pantalla (solo los días que cambian
--     respecto de lo que hoy tiene cada persona), porque «qué tiene hoy» es la
--     cascada turno → horario por día → días laborables de
--     `lib/admin/jornada-esperada.ts`, y CLAUDE.md prohíbe una quinta copia.
--     La base no confía en esa cuenta para lo que importa: cada fila tiene que
--     ser idéntica a un día del borrador, y la 0586 vuelve a validar todo.
--
-- ESTADOS QUE NUNCA
--   · Nunca dos borradores vivos de la misma sede y semana.
--   · Nunca un turno de borrador para alguien sin horario (RxH, no trabajador):
--     para esa persona solo cabe la nota.
--   · Nunca se publica algo distinto de lo que tiene el borrador.
--   · Nunca un borrador viejo pisa un día que cambió después de guardarlo (un
--     cambio con una compañera aprobado, o uno hecho a mano): se niega y dice
--     cuál. Se mide con `turnos.created_at`, que cada cambio reescribe.
--   · Nunca un borrador publicado o descartado vuelve a cambiar.
--   · Nunca lo lee una integrante: RLS solo deja a admin, DO y la líder de esa
--     sede.
--
-- SE ROMPE SI
--   · `fn_publicar_semana` cambia de firma: esta la llama.
--   · Cambia quién publica la semana en la 0586: hay que cambiarlo también en
--     `fn_turnos_borrador_puede` de aquí.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_turnos_borrador_publicar(uuid, date, jsonb, text);
--   drop function if exists fn_turnos_borrador_descartar(uuid, date);
--   drop function if exists fn_turnos_borrador_guardar(uuid, date, jsonb, jsonb, text);
--   drop function if exists fn_turnos_borrador_puede(uuid);
--   (las tablas se dejan: son historia de lo que se propuso. Si de verdad
--    sobran: drop table turnos_borrador_notas, turnos_borrador_dias,
--    turnos_borradores.)
--   delete from migraciones_aplicadas where numero = 593;
--
-- CÓMO SE COMPRUEBA
--   La consulta del final: todo en true y «593 · el_borrador_de_la_semana».
--   Solo crea tablas nuevas: no altera ninguna en uso, así que va entera.
-- ============================================================================

set local lock_timeout = '3s';

-- ── 0 · Guardia ─────────────────────────────────────────────────────────────
do $guardia$
begin
  if to_regprocedure('fn_publicar_semana(uuid,date,jsonb,text)') is null then
    raise exception 'Falta la 0586 (fn_publicar_semana): esta migración la llama.';
  end if;
end
$guardia$;

-- ── 1 · Las tablas ──────────────────────────────────────────────────────────
create table if not exists turnos_borradores (
  id             uuid primary key default gen_random_uuid(),
  sede_id        uuid not null references sedes(id),
  lunes          date not null check (extract(isodow from lunes) = 1),
  origen         text not null default 'manual' check (origen in ('sugerido', 'manual')),
  creado_por     uuid references personas(id),
  creado_at      timestamptz not null default now(),
  actualizado_por uuid references personas(id),
  actualizado_at timestamptz not null default now(),
  publicado_por  uuid references personas(id),
  publicado_at   timestamptz,
  descartado_por uuid references personas(id),
  descartado_at  timestamptz,
  constraint turnos_borrador_un_final check (publicado_at is null or descartado_at is null)
);

create unique index if not exists turnos_borradores_uno_vivo
  on turnos_borradores (sede_id, lunes)
  where publicado_at is null and descartado_at is null;

create table if not exists turnos_borrador_dias (
  borrador_id uuid not null references turnos_borradores(id),
  persona_id  uuid not null references personas(id),
  fecha       date not null,
  entrada     time,
  salida      time,
  primary key (borrador_id, persona_id, fecha),
  constraint turnos_borrador_dia_entrada_y_salida check ((entrada is null) = (salida is null)),
  constraint turnos_borrador_dia_ordenado check (entrada is null or salida > entrada)
);

create table if not exists turnos_borrador_notas (
  borrador_id uuid not null references turnos_borradores(id),
  persona_id  uuid not null references personas(id),
  nota        text not null check (length(trim(nota)) between 1 and 300),
  primary key (borrador_id, persona_id)
);

comment on table turnos_borradores is
  'La semana que la líder arma en Turnos, guardada sin publicar: una viva por sede y lunes. 0593.';
comment on table turnos_borrador_dias is
  'Turno (entrada y salida) o descanso (las dos null) de cada persona y fecha de un borrador. Es lo que se publica. 0593.';
comment on table turnos_borrador_notas is
  'Una nota por persona en un borrador («se la necesita el sábado de 12 a 16»), sobre todo para RxH, que no lleva turno. Nunca se publica. 0593.';

-- ── 2 · Quién la ve ─────────────────────────────────────────────────────────
alter table turnos_borradores     enable row level security;
alter table turnos_borrador_dias  enable row level security;
alter table turnos_borrador_notas enable row level security;

drop policy if exists turnos_borradores_select_admin on turnos_borradores;
create policy turnos_borradores_select_admin on turnos_borradores
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists turnos_borradores_select_supervisor on turnos_borradores;
create policy turnos_borradores_select_supervisor on turnos_borradores
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede' and sede_id = fn_sede_actual_persona());

drop policy if exists turnos_borrador_dias_select_admin on turnos_borrador_dias;
create policy turnos_borrador_dias_select_admin on turnos_borrador_dias
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists turnos_borrador_dias_select_supervisor on turnos_borrador_dias;
create policy turnos_borrador_dias_select_supervisor on turnos_borrador_dias
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede'
         and borrador_id in (select b.id from turnos_borradores b where b.sede_id = fn_sede_actual_persona()));

drop policy if exists turnos_borrador_notas_select_admin on turnos_borrador_notas;
create policy turnos_borrador_notas_select_admin on turnos_borrador_notas
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists turnos_borrador_notas_select_supervisor on turnos_borrador_notas;
create policy turnos_borrador_notas_select_supervisor on turnos_borrador_notas
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede'
         and borrador_id in (select b.id from turnos_borradores b where b.sede_id = fn_sede_actual_persona()));

-- Nadie escribe directo: todo pasa por las funciones de abajo.
revoke all on turnos_borradores     from anon, authenticated, public;
revoke all on turnos_borrador_dias  from anon, authenticated, public;
revoke all on turnos_borrador_notas from anon, authenticated, public;
grant select on turnos_borradores     to authenticated;
grant select on turnos_borrador_dias  to authenticated;
grant select on turnos_borrador_notas to authenticated;

-- ── 3 · Quién la toca (la misma regla que publica, 0586) ────────────────────
create or replace function fn_turnos_borrador_puede(p_sede_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_editor personas;
begin
  select * into v_editor from personas where auth_user_id = auth.uid() and estado = 'activo';
  if v_editor.id is null then
    raise exception 'No autorizado.';
  end if;
  if (v_editor.rol in ('admin', 'lider_do')
      or (v_editor.rol = 'supervisor_sede' and v_editor.sede_base_id = p_sede_id)) is not true then
    raise exception 'Solo la líder de equipo de esta sede, DO o un administrador tocan el borrador de su semana.';
  end if;
  return v_editor.id;
end;
$$;

comment on function fn_turnos_borrador_puede(uuid) is
  'Devuelve la persona que edita si puede tocar el borrador de esa sede (admin, Líder DO o la líder de la sede); si no, se niega. Misma regla que fn_publicar_semana (0586). 0593.';
revoke all on function fn_turnos_borrador_puede(uuid) from public, anon, authenticated;

-- ── 4 · Guardar ─────────────────────────────────────────────────────────────
create or replace function fn_turnos_borrador_guardar(
  p_sede_id uuid,
  p_lunes   date,
  p_dias    jsonb,
  p_notas   jsonb default '[]'::jsonb,
  p_origen  text  default 'manual'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo  uuid := fn_turnos_borrador_puede(p_sede_id);
  v_id  uuid;
  r     record;
  v_obj personas;
begin
  if p_lunes is null or extract(isodow from p_lunes) <> 1 then
    raise exception 'El borrador es de una semana, desde su lunes.';
  end if;
  if p_lunes + 6 <= fn_hoy_lima() then
    raise exception 'Esa semana ya pasó: no tiene días que planificar.';
  end if;
  if coalesce(p_origen, '') not in ('sugerido', 'manual') then
    raise exception 'El origen del borrador es «sugerido» o «manual».';
  end if;
  if p_dias is null or jsonb_typeof(p_dias) <> 'array' then
    raise exception 'Los días del borrador van en una lista.';
  end if;
  if p_notas is null or jsonb_typeof(p_notas) <> 'array' then
    raise exception 'Las notas del borrador van en una lista.';
  end if;

  -- Cada día: de la semana, que todavía no llega, de alguien activo de esta sede al que le corresponde horario.
  for r in
    select (x->>'persona_id')::uuid as persona_id, (x->>'fecha')::date as fecha,
           nullif(x->>'entrada', '')::time as entrada, nullif(x->>'salida', '')::time as salida
      from jsonb_array_elements(p_dias) x
  loop
    if r.persona_id is null or r.fecha is null then
      raise exception 'Cada día del borrador lleva persona y fecha.';
    end if;
    if r.fecha < p_lunes or r.fecha > p_lunes + 6 then
      raise exception 'El día % no es de la semana que empieza el %.', to_char(r.fecha, 'DD/MM'), to_char(p_lunes, 'DD/MM');
    end if;
    if r.fecha <= fn_hoy_lima() then
      raise exception 'El borrador planifica días que todavía no llegan (el % ya llegó).', to_char(r.fecha, 'DD/MM');
    end if;
    if (r.entrada is null) <> (r.salida is null) or (r.entrada is not null and r.salida <= r.entrada) then
      raise exception 'Un turno lleva entrada y salida, y la salida va después de la entrada.';
    end if;
    select * into v_obj from personas where id = r.persona_id;
    if v_obj.id is null or v_obj.estado <> 'activo' or v_obj.sede_base_id is distinct from p_sede_id then
      raise exception 'Uno de los días es de alguien que no está activo en esta sede.';
    end if;
    if v_obj.tipo_vinculo in ('rxh', 'no_trabajador') then
      raise exception 'A % no le corresponde horario (no tiene jornada): déjale una nota en el borrador.', v_obj.nombres;
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(p_dias) x)
     <> (select count(distinct (x->>'persona_id') || '|' || (x->>'fecha')) from jsonb_array_elements(p_dias) x) then
    raise exception 'Hay un día repetido para la misma persona.';
  end if;

  -- Cada nota: de alguien activo de esta sede, con texto, una por persona.
  for r in
    select (x->>'persona_id')::uuid as persona_id, trim(coalesce(x->>'nota', '')) as nota
      from jsonb_array_elements(p_notas) x
  loop
    if r.persona_id is null then
      raise exception 'Cada nota del borrador lleva persona.';
    end if;
    if length(r.nota) not between 1 and 300 then
      raise exception 'Una nota lleva texto, hasta 300 caracteres.';
    end if;
    if not exists (select 1 from personas where id = r.persona_id and estado = 'activo' and sede_base_id = p_sede_id) then
      raise exception 'Una de las notas es de alguien que no está activo en esta sede.';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(p_notas) x)
     <> (select count(distinct x->>'persona_id') from jsonb_array_elements(p_notas) x) then
    raise exception 'Hay dos notas para la misma persona.';
  end if;

  perform pg_advisory_xact_lock(hashtext('turnos_borrador|' || p_sede_id::text || '|' || p_lunes::text));

  select id into v_id from turnos_borradores
   where sede_id = p_sede_id and lunes = p_lunes and publicado_at is null and descartado_at is null
   for update;
  if v_id is null then
    insert into turnos_borradores (sede_id, lunes, origen, creado_por, actualizado_por)
    values (p_sede_id, p_lunes, p_origen, v_yo, v_yo)
    returning id into v_id;
  else
    update turnos_borradores
       set origen = p_origen, actualizado_por = v_yo, actualizado_at = now()
     where id = v_id;
  end if;

  -- Guardar reemplaza: el borrador queda exactamente como lo mandó la pantalla.
  delete from turnos_borrador_dias  where borrador_id = v_id;
  delete from turnos_borrador_notas where borrador_id = v_id;
  insert into turnos_borrador_dias (borrador_id, persona_id, fecha, entrada, salida)
  select v_id, (x->>'persona_id')::uuid, (x->>'fecha')::date,
         nullif(x->>'entrada', '')::time, nullif(x->>'salida', '')::time
    from jsonb_array_elements(p_dias) x;
  insert into turnos_borrador_notas (borrador_id, persona_id, nota)
  select v_id, (x->>'persona_id')::uuid, trim(x->>'nota')
    from jsonb_array_elements(p_notas) x;

  return v_id;
end;
$$;

comment on function fn_turnos_borrador_guardar(uuid, date, jsonb, jsonb, text) is
  'Guarda el borrador vivo de la semana de una sede (lo crea si no hay): reemplaza sus días y sus notas. Admin, Líder DO o la líder de la sede. 0593.';
revoke all on function fn_turnos_borrador_guardar(uuid, date, jsonb, jsonb, text) from public, anon;
grant execute on function fn_turnos_borrador_guardar(uuid, date, jsonb, jsonb, text) to authenticated;

-- ── 5 · Descartar ───────────────────────────────────────────────────────────
create or replace function fn_turnos_borrador_descartar(p_sede_id uuid, p_lunes date)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_turnos_borrador_puede(p_sede_id);
begin
  update turnos_borradores
     set descartado_por = v_yo, descartado_at = now()
   where sede_id = p_sede_id and lunes = p_lunes and publicado_at is null and descartado_at is null;
  return found;
end;
$$;

comment on function fn_turnos_borrador_descartar(uuid, date) is
  'Descarta el borrador vivo de esa sede y semana (queda como historia). Devuelve false si no había. 0593.';
revoke all on function fn_turnos_borrador_descartar(uuid, date) from public, anon;
grant execute on function fn_turnos_borrador_descartar(uuid, date) to authenticated;

-- ── 6 · Publicar ────────────────────────────────────────────────────────────
create or replace function fn_turnos_borrador_publicar(
  p_sede_id uuid,
  p_lunes   date,
  p_turnos  jsonb,
  p_motivo  text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo       uuid := fn_turnos_borrador_puede(p_sede_id);
  v_id       uuid;
  v_n        integer;
  v_guardado timestamptz;
  v_persona  uuid;
  v_fecha    date;
begin
  perform pg_advisory_xact_lock(hashtext('turnos_borrador|' || p_sede_id::text || '|' || p_lunes::text));

  select id into v_id from turnos_borradores
   where sede_id = p_sede_id and lunes = p_lunes and publicado_at is null and descartado_at is null
   for update;
  if v_id is null then
    raise exception 'No hay un borrador de esa semana para publicar.';
  end if;
  if p_turnos is null or jsonb_typeof(p_turnos) <> 'array' or jsonb_array_length(p_turnos) = 0 then
    raise exception 'No hay cambios que publicar: el borrador dice lo mismo que lo publicado.';
  end if;

  -- Lo que se publica es lo del borrador, fila por fila.
  if exists (
    select 1
      from jsonb_array_elements(p_turnos) x
     where not exists (
       select 1 from turnos_borrador_dias d
        where d.borrador_id = v_id
          and d.persona_id = (x->>'persona_id')::uuid
          and d.fecha = (x->>'fecha')::date
          and d.entrada is not distinct from nullif(x->>'entrada', '')::time
          and d.salida  is not distinct from nullif(x->>'salida', '')::time)
  ) then
    raise exception 'Lo que se publica tiene que ser lo del borrador. Vuelve a guardarlo y publica de nuevo.';
  end if;

  -- Un día que cambió DESPUÉS de guardar el borrador (un cambio con una compañera aprobado, 0592, o uno
  -- hecho a mano) no se pisa en silencio: `turnos.created_at` se reescribe con cada cambio.
  select actualizado_at into v_guardado from turnos_borradores where id = v_id;
  select t.persona_id, t.fecha into v_persona, v_fecha
    from jsonb_array_elements(p_turnos) x
    join turnos t on t.persona_id = (x->>'persona_id')::uuid and t.fecha = (x->>'fecha')::date
   where t.created_at > v_guardado
   order by t.fecha, t.persona_id
   limit 1;
  if v_fecha is not null then
    raise exception 'El turno de % del % cambió después de guardar el borrador. Míralo en la grilla: descarta el borrador y vuelve a armarlo, o cambia ese día a mano.',
      (select nombres from personas where id = v_persona), to_char(v_fecha, 'DD/MM');
  end if;

  -- Sus permisos, su regla del turno propio de la líder y su todo o nada son los de la 0586.
  v_n := fn_publicar_semana(p_sede_id, p_lunes, p_turnos,
                            coalesce(nullif(trim(p_motivo), ''), 'Borrador de Turnos revisado y publicado.'));

  update turnos_borradores set publicado_por = v_yo, publicado_at = now() where id = v_id;
  return v_n;
end;
$$;

comment on function fn_turnos_borrador_publicar(uuid, date, jsonb, text) is
  'Publica el borrador vivo de esa sede y semana: las filas tienen que ser días del borrador; publica con fn_publicar_semana (0586) y lo marca publicado, todo en una transacción. 0593.';
revoke all on function fn_turnos_borrador_publicar(uuid, date, jsonb, text) from public, anon;
grant execute on function fn_turnos_borrador_publicar(uuid, date, jsonb, text) to authenticated;

-- ── 7 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (593, 'el_borrador_de_la_semana')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regclass('public.turnos_borradores') is not null
    and to_regclass('public.turnos_borrador_dias') is not null
    and to_regclass('public.turnos_borrador_notas') is not null                                   as las_tablas,
  (select bool_and(relrowsecurity) from pg_class
    where oid in ('public.turnos_borradores'::regclass, 'public.turnos_borrador_dias'::regclass,
                  'public.turnos_borrador_notas'::regclass))                                       as tienen_rls,
  not has_table_privilege('authenticated', 'public.turnos_borrador_dias', 'INSERT')               as nadie_escribe_directo,
  to_regprocedure('fn_turnos_borrador_guardar(uuid,date,jsonb,jsonb,text)') is not null
    and to_regprocedure('fn_turnos_borrador_descartar(uuid,date)') is not null
    and to_regprocedure('fn_turnos_borrador_publicar(uuid,date,jsonb,text)') is not null           as las_puertas,
  not has_function_privilege('anon', 'fn_turnos_borrador_guardar(uuid,date,jsonb,jsonb,text)', 'EXECUTE') as anon_no,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 593)                  as registro;
