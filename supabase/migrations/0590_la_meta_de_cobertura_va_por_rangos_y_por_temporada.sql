-- ============================================================================
-- 0590 · LA META DE COBERTURA VA POR RANGOS DE HORA Y POR TEMPORADA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cada sede diga cuánta gente necesita en piso —personal y líderes— por
--   RANGOS DE HORA que elige ella (de 09:00 a 12:00, de 12:00 a 18:00…), y no
--   solo «mañana» y «tarde» cortadas a las 14:15 como desde la 0039:
--     · una meta PREDETERMINADA por día de la semana;
--     · y EXCEPCIONES que la reemplazan durante el tiempo que se elija: uno o
--       varios días, una o varias semanas, uno o varios meses (una campaña,
--       diciembre, un feriado). Si dos se pisan, manda la más corta: un día
--       gana sobre su semana, una semana sobre su mes. Una excepción reemplaza
--       solo los días de la semana que define; los demás siguen con la
--       predeterminada.
--   Y una lectura única, `fn_metas_cobertura(sede, desde, hasta)`, que dice
--   para cada fecha qué rangos rigen y de qué meta salen.
--
-- DE DÓNDE SALE (Felipe, 2026-11-03)
--   · «Agregar rangos de hora, personal, líderes, por día o semana o mensual,
--     para cada tienda o sede; se puede dejar en cero; predeterminada, sugerido
--     y comparar.»
--   · «Por día, semana o mes» es por cuánto tiempo rige la meta: un día o qué
--     días, una semana o cuántas, un mes o qué meses.
--   · Manda la meta. Un rango SIN meta (null) deja que mande lo que pide la venta
--     (el sugerido: compras ÷ ritmo, con su mínimo, 0585). Una meta en CERO
--     significa «aquí no se exige a nadie» y no se pinta en rojo.
--
-- QUÉ ASUME
--   · `metas_cobertura` (0014/0038/0039) con dia_semana 0 = domingo … 6 = sábado.
--     Esta migración la SIEMBRA en el modelo nuevo y la deja de leer el panel;
--     no la borra (es historia) ni toca sus funciones de escritura.
--   · Las mismas reglas de quién de siempre: leen admin y Líder DO (todas las
--     sedes) y la líder de equipo (la suya); escriben admin y Líder DO
--     (fn_set_meta_cobertura, 0379).
--
-- POR QUÉ ASÍ
--   · Minutos desde medianoche (0–1440) y no `time`: un rango que llega al
--     cierre del día es [x, 1440), y un `time` de 24:00 se comporta raro.
--   · `personal` y `lideres` admiten null = «sin meta», distinto de 0. La 0039
--     no tenía esa diferencia: su 0 se pintaba «sin meta». Por eso la siembra
--     convierte el 0 viejo en null, y nada cambia de color al pegar esto.
--   · La siembra reproduce exactamente lo de antes: [00:00, 14:15) con la meta
--     de la mañana y [14:15, 24:00) con la de la tarde, y los líderes de ese día
--     en los dos.
--   · Una excepción tiene UNA vigencia contigua. Días sueltos que no se tocan
--     (el 24 y el 31) son dos excepciones; «los sábados de diciembre» es una
--     excepción de diciembre que solo define el sábado.
--   · Entre dos excepciones de igual largo que se pisan, manda la más reciente,
--     y después el id: un orden que no depende de cómo Postgres lea la tabla
--     (la regla de los desempates de CLAUDE.md).
--   · Sin rastro en correcciones_auditoria: ese rastro es por persona, y una
--     meta es de la sede. Cada fila guarda quién la creó, y una excepción
--     anulada no se borra.
--
-- ESTADOS QUE NUNCA
--   · Dos predeterminadas vivas de la misma sede → índice único parcial.
--   · Una excepción sin fechas, o que termina antes de empezar → CHECK.
--   · Dos rangos del mismo día de la misma meta que se cruzan → EXCLUDE.
--   · Un rango vacío o fuera del día → CHECK.
--   · Una meta escrita sin pasar por la función → no hay privilegio de escritura.
--
-- SE ROMPE SI
--   · Alguien vuelve a leer `metas_cobertura` para decidir una meta: estará
--     vieja desde el primer cambio. El panel la deja de leer en este PR
--     (Turnos, Dashboard, Incidencias y Reporte de sede).
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_metas_cobertura(uuid, date, date);
--   drop function if exists fn_guardar_meta_cobertura(uuid, uuid, text, date, date, jsonb);
--   drop function if exists fn_anular_meta_cobertura(uuid);
--   drop table if exists metas_cobertura_rangos;
--   drop table if exists metas_cobertura_periodos;
--   (metas_cobertura queda como estaba antes de esto: no se tocó.)
--
-- CÓMO SE COMPRUEBA
--   La consulta del final: las tablas, las funciones, cuántas sedes quedaron
--   sembradas y el registro «590 · la_meta_de_cobertura_va_por_rangos_y_por_temporada».
--
-- No reescribe ninguna función existente: no lleva md5 de partida.
-- ============================================================================

-- ── 1 · Las metas: la predeterminada y sus excepciones ──────────────────────
create table if not exists metas_cobertura_periodos (
  id                 uuid primary key default gen_random_uuid(),
  sede_id            uuid not null references sedes(id),
  nombre             text not null,
  es_predeterminada  boolean not null default false,
  vigente_desde      date,
  vigente_hasta      date,
  creado_por         uuid references personas(id),
  created_at         timestamptz not null default now(),
  anulada_at         timestamptz,
  anulada_por        uuid references personas(id),
  constraint meta_periodo_nombre check (btrim(nombre) <> ''),
  constraint meta_periodo_fechas check (
    (es_predeterminada and vigente_desde is null and vigente_hasta is null)
    or (not es_predeterminada and vigente_desde is not null and vigente_hasta is not null and vigente_hasta >= vigente_desde)
  )
);

comment on table metas_cobertura_periodos is
  'Una meta de cobertura de una sede: la PREDETERMINADA (sin fechas, una viva por sede) o una EXCEPCIÓN con vigencia '
  '(desde–hasta), que reemplaza a la predeterminada en los días de la semana que define. Manda la excepción más corta. '
  'Se escribe por fn_guardar_meta_cobertura y se lee por fn_metas_cobertura (0590).';

create unique index if not exists uq_meta_predeterminada_viva
  on metas_cobertura_periodos (sede_id) where es_predeterminada and anulada_at is null;
create index if not exists idx_metas_periodos_sede on metas_cobertura_periodos (sede_id, vigente_desde);

-- ── 2 · Los rangos de hora de cada día ──────────────────────────────────────
create table if not exists metas_cobertura_rangos (
  id          uuid primary key default gen_random_uuid(),
  periodo_id  uuid not null references metas_cobertura_periodos(id),
  dia_semana  int not null,
  desde_min   int not null,
  hasta_min   int not null,
  personal    int,
  lideres     int,
  constraint meta_rango_dia check (dia_semana between 0 and 6),
  constraint meta_rango_horas check (desde_min >= 0 and hasta_min <= 1440 and hasta_min > desde_min),
  constraint meta_rango_personal check (personal is null or personal between 0 and 50),
  constraint meta_rango_lideres check (lideres is null or lideres between 0 and 20)
);

comment on table metas_cobertura_rangos is
  'Los rangos de hora de un día de la semana de una meta: [desde_min, hasta_min) en minutos desde la medianoche, '
  'con cuánto personal y cuántos líderes hacen falta. null = sin meta (manda lo que pide la venta); 0 = no se exige '
  'a nadie. dia_semana 0 = domingo … 6 = sábado. 0590.';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'meta_rango_sin_cruces') then
    alter table metas_cobertura_rangos
      add constraint meta_rango_sin_cruces exclude using gist (
        periodo_id with =,
        dia_semana with =,
        int4range(desde_min, hasta_min, '[)') with &&
      );
  end if;
end;
$$;

create index if not exists idx_metas_rangos_periodo on metas_cobertura_rangos (periodo_id, dia_semana, desde_min);

-- ── 3 · Quién las lee (las mismas reglas que metas_cobertura, 0014) ─────────
alter table metas_cobertura_periodos enable row level security;
alter table metas_cobertura_rangos   enable row level security;

drop policy if exists metas_periodos_select_admin on metas_cobertura_periodos;
create policy metas_periodos_select_admin on metas_cobertura_periodos
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists metas_periodos_select_supervisor on metas_cobertura_periodos;
create policy metas_periodos_select_supervisor on metas_cobertura_periodos
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede' and sede_id = fn_sede_actual_persona());

drop policy if exists metas_rangos_select_admin on metas_cobertura_rangos;
create policy metas_rangos_select_admin on metas_cobertura_rangos
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists metas_rangos_select_supervisor on metas_cobertura_rangos;
create policy metas_rangos_select_supervisor on metas_cobertura_rangos
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede'
         and periodo_id in (select p.id from metas_cobertura_periodos p where p.sede_id = fn_sede_actual_persona()));

revoke all on metas_cobertura_periodos from anon, authenticated, public;
revoke all on metas_cobertura_rangos   from anon, authenticated, public;
grant select on metas_cobertura_periodos to authenticated;
grant select on metas_cobertura_rangos   to authenticated;

-- ── 4 · La siembra: lo de la 0039, tal cual, en el modelo nuevo ─────────────
-- Una predeterminada por cada sede que ya tenía metas. La mañana [00:00, 14:15) y
-- la tarde [14:15, 24:00); los líderes del día en los dos. El 0 viejo era «sin
-- meta» y queda null. Idempotente: no siembra dos veces la misma sede.
insert into metas_cobertura_periodos (sede_id, nombre, es_predeterminada)
select distinct m.sede_id, 'Predeterminada', true
  from metas_cobertura m
 where not exists (select 1 from metas_cobertura_periodos p
                    where p.sede_id = m.sede_id and p.es_predeterminada and p.anulada_at is null);

insert into metas_cobertura_rangos (periodo_id, dia_semana, desde_min, hasta_min, personal, lideres)
select p.id, m.dia_semana, t.desde_min, t.hasta_min,
       nullif(case when t.desde_min = 0 then m.meta else m.meta_tarde end, 0),
       nullif(m.meta_encargadas, 0)
  from metas_cobertura m
  join metas_cobertura_periodos p on p.sede_id = m.sede_id and p.es_predeterminada and p.anulada_at is null
  cross join (values (0, 855), (855, 1440)) t(desde_min, hasta_min)
 where ((case when t.desde_min = 0 then m.meta else m.meta_tarde end) > 0 or m.meta_encargadas > 0)
   and not exists (select 1 from metas_cobertura_rangos r where r.periodo_id = p.id);

-- ── 5 · La lectura única ────────────────────────────────────────────────────
-- Para cada fecha del rango: la meta que rige ese día de la semana (la excepción
-- vigente más corta que lo define; si no hay, la predeterminada) y sus rangos.
-- Una fecha sin rangos no devuelve filas: sin meta.
create or replace function fn_metas_cobertura(p_sede_id uuid, p_desde date, p_hasta date)
returns table (
  fecha date, desde_min int, hasta_min int, personal int, lideres int,
  periodo_id uuid, periodo_nombre text, es_predeterminada boolean
)
language plpgsql
stable
security invoker
set search_path = public
as $fn$
#variable_conflict use_column
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'El rango de fechas no es válido.';
  end if;
  if p_hasta - p_desde > 92 then
    raise exception 'Se pueden pedir hasta 92 días de metas a la vez.';
  end if;

  return query
  with dias as (
    select d.d::date as fecha, extract(dow from d.d)::int as dow
      from generate_series(p_desde, p_hasta, interval '1 day') d(d)
  ),
  candidatas as (
    select x.fecha, p.id as periodo_id, p.nombre, p.es_predeterminada,
           row_number() over (
             partition by x.fecha
             order by p.es_predeterminada,                                -- primero las excepciones
                      (p.vigente_hasta - p.vigente_desde) nulls last,     -- la más corta
                      p.created_at desc, p.id desc                        -- desempate estable
           ) as orden
      from dias x
      join metas_cobertura_periodos p
        on p.sede_id = p_sede_id and p.anulada_at is null
       and (p.es_predeterminada or x.fecha between p.vigente_desde and p.vigente_hasta)
     where exists (select 1 from metas_cobertura_rangos r where r.periodo_id = p.id and r.dia_semana = x.dow)
  )
  select c.fecha, r.desde_min, r.hasta_min, r.personal, r.lideres, c.periodo_id, c.nombre, c.es_predeterminada
    from candidatas c
    join dias x on x.fecha = c.fecha
    join metas_cobertura_rangos r on r.periodo_id = c.periodo_id and r.dia_semana = x.dow
   where c.orden = 1
   order by 1, 2;
end
$fn$;

comment on function fn_metas_cobertura(uuid, date, date) is
  'La meta de cobertura que rige cada fecha de una sede: los rangos de hora con su personal y sus líderes, de la '
  'excepción vigente más corta que define ese día de la semana o, si no hay, de la predeterminada. Sin filas = sin '
  'meta. Lee con las políticas de cada quien (SECURITY INVOKER). Hasta 92 días. 0590.';

revoke all on function fn_metas_cobertura(uuid, date, date) from public, anon;
grant execute on function fn_metas_cobertura(uuid, date, date) to authenticated;

-- ── 6 · La puerta: guardar una meta entera ──────────────────────────────────
-- p_periodo_id null + sin fechas = la predeterminada de la sede (la crea si no hay).
-- p_periodo_id null + fechas     = una excepción nueva.
-- p_periodo_id                   = reemplaza esa meta (nombre, fechas y rangos).
-- p_rangos: [{ "dia": 0-6, "desde_min": 540, "hasta_min": 720, "personal": 3|null, "lideres": 1|null }, …]
-- Reemplaza TODOS los rangos de esa meta de una vez: la pantalla no coordina varias llamadas.
create or replace function fn_guardar_meta_cobertura(
  p_sede_id    uuid,
  p_periodo_id uuid,
  p_nombre     text,
  p_desde      date,
  p_hasta      date,
  p_rangos     jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_id      uuid := p_periodo_id;
  v_periodo metas_cobertura_periodos;
  v_pred    boolean;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o Desarrollo Organizacional define la meta de cobertura.';
  end if;
  if not exists (select 1 from sedes where id = p_sede_id) then
    raise exception 'Esa sede no existe.';
  end if;
  if p_rangos is null or jsonb_typeof(p_rangos) <> 'array' then
    raise exception 'Los rangos tienen que venir como una lista.';
  end if;
  if jsonb_array_length(p_rangos) > 7 * 12 then
    raise exception 'Son demasiados rangos (máximo 12 por día).';
  end if;

  perform pg_advisory_xact_lock(hashtext('fn_guardar_meta_cobertura:' || p_sede_id::text));

  if v_id is not null then
    select * into v_periodo from metas_cobertura_periodos where id = v_id;
    if v_periodo.id is null or v_periodo.sede_id <> p_sede_id or v_periodo.anulada_at is not null then
      raise exception 'Esa meta no existe en esta sede.';
    end if;
    v_pred := v_periodo.es_predeterminada;
  else
    v_pred := p_desde is null and p_hasta is null;
  end if;

  if not v_pred then
    if p_desde is null or p_hasta is null then
      raise exception 'Una excepción lleva desde cuándo y hasta cuándo rige.';
    end if;
    if p_hasta < p_desde then
      raise exception 'La excepción termina antes de empezar.';
    end if;
    if p_hasta - p_desde > 366 then
      raise exception 'Una excepción dura como mucho un año; para algo permanente, cambia la predeterminada.';
    end if;
  end if;

  if v_id is null and v_pred then
    select id into v_id from metas_cobertura_periodos
     where sede_id = p_sede_id and es_predeterminada and anulada_at is null;
  end if;

  if v_id is null then
    insert into metas_cobertura_periodos (sede_id, nombre, es_predeterminada, vigente_desde, vigente_hasta, creado_por)
    values (p_sede_id,
            coalesce(nullif(btrim(p_nombre), ''), case when v_pred then 'Predeterminada' else 'Excepción' end),
            v_pred,
            case when v_pred then null else p_desde end,
            case when v_pred then null else p_hasta end,
            v_yo)
    returning id into v_id;
  else
    update metas_cobertura_periodos
       set nombre        = coalesce(nullif(btrim(p_nombre), ''), nombre),
           vigente_desde = case when v_pred then null else p_desde end,
           vigente_hasta = case when v_pred then null else p_hasta end
     where id = v_id;
  end if;

  delete from metas_cobertura_rangos where periodo_id = v_id;

  -- El EXCLUDE y los CHECK lo impiden igual; esto es para decirlo con palabras.
  if exists (
    select 1 from jsonb_array_elements(p_rangos) e
     where (e->>'dia') is null or (e->>'desde_min') is null or (e->>'hasta_min') is null
        or (e->>'dia')::int not between 0 and 6
        or (e->>'desde_min')::int < 0 or (e->>'hasta_min')::int > 1440
        or (e->>'hasta_min')::int <= (e->>'desde_min')::int
        or coalesce((e->>'personal')::int, 0) < 0 or coalesce((e->>'lideres')::int, 0) < 0
  ) then
    raise exception 'Cada rango lleva su día y sus horas (la de fin después de la de inicio), y no se piden números negativos.';
  end if;

  insert into metas_cobertura_rangos (periodo_id, dia_semana, desde_min, hasta_min, personal, lideres)
  select v_id, (e->>'dia')::int, (e->>'desde_min')::int, (e->>'hasta_min')::int,
         (e->>'personal')::int, (e->>'lideres')::int
    from jsonb_array_elements(p_rangos) e;

  return v_id;
end;
$$;

comment on function fn_guardar_meta_cobertura(uuid, uuid, text, date, date, jsonb) is
  'Guarda una meta de cobertura entera: la predeterminada de la sede (sin fechas) o una excepción con vigencia, con '
  'todos sus rangos de hora (reemplaza los anteriores). Admin y Líder DO. 0590.';

revoke all on function fn_guardar_meta_cobertura(uuid, uuid, text, date, date, jsonb) from public, anon;
grant execute on function fn_guardar_meta_cobertura(uuid, uuid, text, date, date, jsonb) to authenticated;

-- ── 7 · Quitar una excepción (la predeterminada no se quita: se cambia) ─────
create or replace function fn_anular_meta_cobertura(p_periodo_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_periodo metas_cobertura_periodos;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o Desarrollo Organizacional quita una excepción de la meta.';
  end if;
  select * into v_periodo from metas_cobertura_periodos where id = p_periodo_id;
  if v_periodo.id is null or v_periodo.anulada_at is not null then
    raise exception 'Esa excepción no existe o ya se quitó.';
  end if;
  if v_periodo.es_predeterminada then
    raise exception 'La meta predeterminada no se quita: se cambia.';
  end if;
  update metas_cobertura_periodos set anulada_at = now(), anulada_por = fn_persona_actual_id() where id = p_periodo_id;
end;
$$;

comment on function fn_anular_meta_cobertura(uuid) is
  'Quita una excepción de la meta de cobertura (queda anulada, no se borra). La predeterminada no se quita. 0590.';

revoke all on function fn_anular_meta_cobertura(uuid) from public, anon;
grant execute on function fn_anular_meta_cobertura(uuid) to authenticated;

-- ── 8 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (590, 'la_meta_de_cobertura_va_por_rangos_y_por_temporada')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regclass('public.metas_cobertura_periodos') is not null                                         as periodos,
  to_regclass('public.metas_cobertura_rangos') is not null                                           as rangos,
  not has_table_privilege('authenticated', 'public.metas_cobertura_rangos', 'INSERT')               as nadie_escribe_directo,
  to_regprocedure('fn_metas_cobertura(uuid,date,date)') is not null                                 as la_lectura,
  to_regprocedure('fn_guardar_meta_cobertura(uuid,uuid,text,date,date,jsonb)') is not null          as la_puerta,
  (select count(*) from metas_cobertura_periodos where es_predeterminada and anulada_at is null)     as sedes_sembradas,
  (select count(distinct sede_id) from metas_cobertura)                                             as sedes_con_meta_vieja,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 590)                   as registro;
