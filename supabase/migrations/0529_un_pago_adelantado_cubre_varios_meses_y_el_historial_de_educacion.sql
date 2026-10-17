-- ============================================================================
-- 0529 — Un pago adelantado cubre varios meses; la cuadrícula sabe qué apoyo se
--        pagó cada mes; y Educación tiene un historial general e individual
-- ============================================================================
--
-- ESTADO: SIN PEGAR (2026-10-17). Se pega DESPUÉS de la 0525 y ANTES de fusionar el PR
-- que trae sus pantallas. No reescribe ninguna función existente: todo lo de aquí es
-- nuevo (dos columnas, una tabla, funciones y triggers propios), así que no hay md5 de
-- partida. La sección 0 comprueba sola que esos nombres no existan todavía (si
-- existen sin la 0529 registrada, PARA). Prueba: supabase/tests/424 (50 aserciones;
-- sin esta migración, falla).
--
-- QUÉ PROMETE
--
--   1. PAGO ADELANTADO. Una integrante que pagó de agosto a diciembre de una vez
--      sube UNA constancia que dice qué meses cubre, y cuánto corresponde a cada
--      mes: el que sabe, o el total dividido; un mes corregido a mano lleva su
--      motivo. DO la revisa una sola vez. Aprobada, el calendario de la familia
--      salta al pago siguiente al último mes cubierto (enero), y el sistema deja
--      de pedirle constancia de esos meses.
--   2. EL APOYO DE CADA MES. `fn_educacion_apoyo_pagado` dice cuánto se pagó de
--      educación a cada persona en cada periodo ya CERRADO, leído de la foto de
--      la planilla (0096), para que la cuadrícula pueda decir «pagado» con un
--      dato y no con una suposición.
--   3. EL HISTORIAL. `fn_educacion_historial` junta en una lista todo lo que pasó
--      en Educación —solicitudes, altas y cambios del apoyo, envíos, aprobaciones,
--      rechazos, reversiones, cierres—. DO ve el de todos (o el de una persona);
--      la integrante ve solo el suyo, sin nombres de quién de DO lo hizo.
--
-- DECISIONES DE FELIPE (2026-10-17)
--   · Los meses se cuentan por MES CALENDARIO, ambos incluidos.
--   · En enero se sigue pagando y se pide la constancia nueva: esto no toca la
--     planilla ni la regla «solo alerta» de la 0450.
--   · Si el monto de un mes es menor que el costo declarado, la PANTALLA de DO
--     lo avisa al revisar; aquí no se bloquea.
--   · Si un mes está mal, DO rechaza la constancia ENTERA (la misma función de
--     siempre, `fn_educacion_resolver_entrega`).
--   · La constancia sola no crea el apoyo ni enciende el pago.
--
-- POR QUÉ ASÍ
--   · La constancia de varios meses ES una constancia normal (misma tabla, mismos
--     archivos, misma revisión, mismo espejo de pago). Lo único nuevo es que dice
--     qué meses cubre: `cubre_desde`/`cubre_hasta` y una fila por mes en
--     `educacion_entrega_meses`. Así aprobar, rechazar, revertir (0525) y el
--     historial funcionan sin una sola rama nueva.
--   · Se envía con su propia función, que llama a `fn_educacion_enviar_entrega`
--     (sin tocarla) y después anota la cobertura en la misma transacción: si la
--     cobertura no pasa sus validaciones, no queda ni el envío.
--   · El calendario se mueve con un trigger propio al aprobar. No se reescribe
--     `fn_educacion_avanzar_calendario` (0527, pegada hoy): su regla compara el
--     día del pago con la próxima fecha, y un pago adelantado se hace ANTES de
--     los meses que cubre — justo el caso que esa regla no alcanza.
--
-- QUÉ NO HACE
--   · No cambia lo que se paga. No toca fn_planilla_calcular ni el espejo.
--   · No reparte el apoyo por estudio: la foto de planilla guarda el total de
--     educación por persona y periodo; si alguien tiene dos estudios, la
--     cuadrícula dice el total de la persona.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_educacion_cobertura_calendario on educacion_entregas;
--   drop trigger if exists trg_educacion_cobertura_inmutable on educacion_entregas;
--   drop function if exists fn_educacion_cobertura_calendario(), fn_educacion_cobertura_inmutable(),
--     fn_educacion_cobertura_mover_calendario(uuid),
--     fn_educacion_enviar_adelantado(uuid,uuid,date,text,jsonb,jsonb,text,uuid),
--     fn_educacion_coberturas(), fn_educacion_apoyo_pagado(date), fn_educacion_historial(uuid,date,date);
--   drop table if exists educacion_entrega_meses;
--   alter table educacion_entregas drop column if exists cubre_hasta, drop column if exists cubre_desde;
-- ============================================================================


-- ── 0 · Comprobar ANTES de tocar nada ───────────────────────────────────────
-- Todo lo de esta migración es nuevo. Si alguna de sus funciones o su tabla ya existe en esta base
-- y la 0529 NO está registrada, alguien creó algo con el mismo nombre por otro camino: pegar esto lo
-- pisaría en silencio (el accidente de la 0297 y la 0299). Entonces no se aplica NADA. Repegar la
-- 0529 ya registrada sí pasa: es idempotente.
do $$
declare v_hay text;
begin
  if exists (select 1 from migraciones_aplicadas where numero = 529) then return; end if;
  select string_agg(x, ', ') into v_hay from (
    select p.proname::text as x from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('fn_educacion_enviar_adelantado', 'fn_educacion_coberturas',
       'fn_educacion_apoyo_pagado', 'fn_educacion_historial', 'fn_educacion_cobertura_mover_calendario',
       'fn_educacion_cobertura_calendario', 'fn_educacion_cobertura_inmutable')
    union all
    select 'tabla educacion_entrega_meses' where to_regclass('public.educacion_entrega_meses') is not null
  ) t;
  if v_hay is not null then
    raise exception '0529 · PARA. Ya existe en esta base: %. La 0529 no está registrada, así que eso lo creó otro camino. No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh.', v_hay;
  end if;
end $$;


-- ── A · Qué meses cubre una constancia ──────────────────────────────────────
alter table educacion_entregas
  add column if not exists cubre_desde date,
  add column if not exists cubre_hasta date;

alter table educacion_entregas drop constraint if exists educacion_entrega_cobertura_valida;
alter table educacion_entregas add constraint educacion_entrega_cobertura_valida check (
  (cubre_desde is null and cubre_hasta is null)
  or (cubre_desde is not null and cubre_hasta is not null
      and extract(day from cubre_desde) = 1 and extract(day from cubre_hasta) = 1
      and cubre_hasta > cubre_desde)
);

create table if not exists educacion_entrega_meses (
  entrega_id uuid not null references educacion_entregas(id),
  mes        date not null,
  monto      numeric(10,2) not null,
  origen     text not null,
  motivo     text,
  primary key (entrega_id, mes),
  constraint educacion_mes_es_dia_1 check (extract(day from mes) = 1),
  constraint educacion_mes_monto check (monto >= 0),
  constraint educacion_mes_origen check (origen in ('calculado', 'puesto', 'manual')),
  constraint educacion_mes_motivo check (
    (origen = 'manual' and length(trim(coalesce(motivo, ''))) >= 3)
    or (origen <> 'manual' and motivo is null))
);
comment on table educacion_entrega_meses is
  'Los meses que cubre una constancia de pago adelantado (0529), con lo que corresponde a cada uno: calculado (total ÷ meses), puesto (lo sabía la integrante) o manual (lo corrigió, con motivo). Solo se escribe por fn_educacion_enviar_adelantado y nunca se cambia.';

alter table educacion_entrega_meses enable row level security;
revoke all on educacion_entrega_meses from anon, authenticated;
grant select on educacion_entrega_meses to authenticated;
drop policy if exists educacion_entrega_meses_lectura on educacion_entrega_meses;
create policy educacion_entrega_meses_lectura on educacion_entrega_meses for select to authenticated using (
  exists (select 1 from educacion_entregas e join asignaciones_educacion a on a.id = e.asignacion_id
           where e.id = educacion_entrega_meses.entrega_id
             and (fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id())));

-- Lo enviado no se reescribe (mismo criterio que la 0450): la cobertura se pone
-- una vez, de null a valor, y los meses no se tocan ni se borran.
create or replace function fn_educacion_cobertura_inmutable()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name = 'educacion_entrega_meses' then
    raise exception 'Los meses de un pago adelantado no se cambian: si están mal, se rechaza y se envía otra.';
  end if;
  if old.cubre_desde is not null
     and (new.cubre_desde, new.cubre_hasta) is distinct from (old.cubre_desde, old.cubre_hasta) then
    raise exception 'Los meses que cubre una constancia no se cambian: si están mal, se rechaza y se envía otra.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_educacion_cobertura_inmutable on educacion_entregas;
create trigger trg_educacion_cobertura_inmutable
  before update on educacion_entregas
  for each row execute function fn_educacion_cobertura_inmutable();

drop trigger if exists trg_educacion_meses_inmutables on educacion_entrega_meses;
create trigger trg_educacion_meses_inmutables
  before update or delete on educacion_entrega_meses
  for each row execute function fn_educacion_cobertura_inmutable();


-- ── B · Enviar un pago adelantado ───────────────────────────────────────────
-- p_meses: [{ "mes": "2026-08-01", "monto": 120, "origen": "calculado"|"puesto"|"manual", "motivo": "…" }]
create or replace function fn_educacion_enviar_adelantado(
  p_id            uuid,
  p_asignacion_id uuid,
  p_fecha_pago    date,
  p_tipo          text,
  p_meses         jsonb,
  p_archivos      jsonb,
  p_nota          text default null,
  p_reemplaza_a   uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n       int;
  v_desde   date;
  v_hasta   date;
  v_m       jsonb;
  v_prev    date := null;
  v_mes     date;
  v_proxima date;
  v_estado  text;
begin
  if p_meses is null or jsonb_typeof(p_meses) <> 'array' then
    raise exception 'Faltan los meses que cubre el pago.';
  end if;
  v_n := jsonb_array_length(p_meses);
  if v_n < 2 then
    raise exception 'Un pago adelantado cubre al menos dos meses. Si es un solo mes, envíala como siempre.';
  end if;
  if v_n > 24 then
    raise exception 'Un pago adelantado cubre como máximo 24 meses.';
  end if;

  -- Los meses: consecutivos, día 1, en orden, con monto, y con motivo si se corrigió.
  for v_m in select value from jsonb_array_elements(p_meses) loop
    v_mes := (v_m->>'mes')::date;
    if v_mes is null or extract(day from v_mes) <> 1 then
      raise exception 'Cada mes se indica por su día 1.';
    end if;
    if v_prev is not null and v_mes <> (v_prev + interval '1 month')::date then
      raise exception 'Los meses tienen que ser seguidos, del primero al último.';
    end if;
    if (v_m->>'monto') is null or (v_m->>'monto')::numeric < 0 then
      raise exception 'Cada mes necesita su monto (puede ser 0).';
    end if;
    if coalesce(v_m->>'origen', '') not in ('calculado', 'puesto', 'manual') then
      raise exception 'Origen del monto no válido.';
    end if;
    if v_m->>'origen' = 'manual' and length(trim(coalesce(v_m->>'motivo', ''))) < 3 then
      raise exception 'Si corriges el monto de % escribe por qué (al menos 3 letras).', to_char(v_mes, 'MM/YYYY');
    end if;
    v_prev := v_mes;
  end loop;
  v_desde := (p_meses->0->>'mes')::date;
  v_hasta := v_prev;
  if (select sum((x->>'monto')::numeric) from jsonb_array_elements(p_meses) x) <= 0 then
    raise exception 'El total pagado tiene que ser mayor que cero.';
  end if;

  -- La próxima constancia: el mismo día del mes en que pagó, el mes siguiente al
  -- último cubierto (pagó el 15 de agosto hasta diciembre → el 15 de enero). Si
  -- ese mes no tiene ese día (31), el último día del mes.
  v_proxima := least(
    (v_hasta + interval '1 month')::date + (extract(day from p_fecha_pago)::int - 1),
    ((v_hasta + interval '2 month')::date - 1));

  -- El envío es una constancia normal: las mismas validaciones, los mismos archivos.
  perform fn_educacion_enviar_entrega(p_id, p_asignacion_id, p_fecha_pago, p_tipo, v_proxima,
                                      p_archivos, p_nota, p_reemplaza_a);

  update educacion_entregas set cubre_desde = v_desde, cubre_hasta = v_hasta where id = p_id
  returning estado into v_estado;

  insert into educacion_entrega_meses (entrega_id, mes, monto, origen, motivo)
  select p_id, (x->>'mes')::date, round((x->>'monto')::numeric, 2), x->>'origen',
         case when x->>'origen' = 'manual' then trim(x->>'motivo') end
    from jsonb_array_elements(p_meses) x;

  -- Si la cargó DO a nombre de alguien, ya nació aprobada: el calendario se mueve ahora.
  if v_estado = 'aprobada' then
    perform fn_educacion_cobertura_mover_calendario(p_id);
  end if;

  return p_id;
end;
$$;


-- ── C · Aprobada, el calendario salta al mes siguiente al último cubierto ────
create or replace function fn_educacion_cobertura_mover_calendario(p_entrega_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  -- Solo hacia adelante: si DO ya fijó una fecha posterior, no se toca.
  update asignaciones_educacion a
     set proxima_fecha_pago = e.proxima_fecha_pago
    from educacion_entregas e
    join asignaciones_educacion x on x.id = e.asignacion_id
   where e.id = p_entrega_id
     and e.estado = 'aprobada'
     and e.cubre_hasta is not null
     and a.familia_id = x.familia_id
     and (a.proxima_fecha_pago is null or a.proxima_fecha_pago < e.proxima_fecha_pago);
$$;
revoke execute on function fn_educacion_cobertura_mover_calendario(uuid) from public, anon, authenticated;

create or replace function fn_educacion_cobertura_calendario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.cubre_hasta is not null and new.estado = 'aprobada' and old.estado is distinct from 'aprobada' then
    perform fn_educacion_cobertura_mover_calendario(new.id);
  end if;
  return null;
end;
$$;

drop trigger if exists trg_educacion_cobertura_calendario on educacion_entregas;
create trigger trg_educacion_cobertura_calendario
  after update of estado on educacion_entregas
  for each row execute function fn_educacion_cobertura_calendario();


-- ── D · Los meses cubiertos, para pintar la cuadrícula ──────────────────────
create or replace function fn_educacion_coberturas()
returns table (entrega_id uuid, familia_id uuid, mes date, monto numeric, origen text, motivo text)
language sql
stable
security definer
set search_path = public
as $$
  select m.entrega_id, a.familia_id, m.mes, m.monto, m.origen, m.motivo
    from educacion_entrega_meses m
    join educacion_entregas e on e.id = m.entrega_id
    join asignaciones_educacion a on a.id = e.asignacion_id
   where fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id()
   order by a.familia_id, m.entrega_id, m.mes;
$$;


-- ── E · El apoyo que se pagó cada mes, de la foto de la planilla ─────────────
-- El mes de un periodo es el de su cierre (29 de setiembre → 28 de octubre =
-- octubre). La foto vigente es la de mayor versión de cada (periodo, grupo,
-- persona) (0096/0323).
create or replace function fn_educacion_apoyo_pagado(p_desde date)
returns table (persona_id uuid, mes date, monto numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve lo pagado en la planilla.';
  end if;
  return query
  select d.persona_id, date_trunc('month', p.fecha_fin)::date, sum(coalesce(d.monto_educacion, 0))::numeric
    from planilla_pagada_detalle d
    join periodos_planilla p on p.id = d.periodo_id
   where p.fecha_fin >= coalesce(p_desde, '1900-01-01'::date)
     and d.version = (select max(d2.version) from planilla_pagada_detalle d2
                       where d2.periodo_id = d.periodo_id and d2.grupo = d.grupo and d2.persona_id = d.persona_id)
   group by d.persona_id, date_trunc('month', p.fecha_fin)
  having sum(coalesce(d.monto_educacion, 0)) > 0;
end;
$$;


-- ── F · El historial ────────────────────────────────────────────────────────
-- Devuelve los HECHOS crudos; cómo se dicen en castellano lo decide
-- `apps/web/lib/educacion-historial.ts`, con pruebas. DO ve todo (o una persona);
-- la integrante, solo lo suyo y sin el nombre de quién de DO lo hizo ni los
-- motivos internos (sí el motivo de un rechazo: es para ella).
create or replace function fn_educacion_historial(
  p_persona_id uuid default null,
  p_desde      date default null,
  p_hasta      date default null
)
returns table (
  ocurrio_at     timestamptz,
  persona_id     uuid,
  persona        text,
  sede           text,
  fuente         text,
  campo          text,
  valor_anterior text,
  valor_nuevo    text,
  motivo         text,
  quien          text,
  entrega_id     uuid,
  cubre_desde    date,
  cubre_hasta    date
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_do  boolean := fn_es_admin_o_lider() is true;
  v_yo  uuid    := fn_persona_actual_id();
  v_ini timestamptz := case when p_desde is null then null else (p_desde::timestamp) at time zone 'America/Lima' end;
  v_fin timestamptz := case when p_hasta is null then null else ((p_hasta + 1)::timestamp) at time zone 'America/Lima' end;
  v_quien uuid;
begin
  if v_do then
    v_quien := p_persona_id;
  else
    if v_yo is null then raise exception 'Tu cuenta no está enlazada con tu ficha.'; end if;
    v_quien := v_yo;
  end if;

  return query
  with hechos as (
    -- Lo que dejaron escrito las funciones de Educación.
    select c.corregido_at as at, c.persona_id as pid, 'auditoria'::text as fuente,
           c.campo_modificado as campo, c.valor_anterior as va, c.valor_nuevo as vn,
           c.motivo as mot, c.corregido_por as por, null::uuid as eid, null::date as cd, null::date as ch
      from correcciones_auditoria c
     where c.campo_modificado like 'educacion%'
       and c.campo_modificado not like 'educacion_dias_%'
       and c.persona_id is not null
       -- El envío y el retiro de una constancia se leen de la constancia misma (abajo),
       -- que sabe su id y los meses que cubre; su fila de auditoría diría lo mismo dos veces.
       and not (c.campo_modificado = 'educacion_entrega' and (c.valor_anterior is null or c.valor_nuevo = 'retirada'))
    union all
    -- Los envíos de constancias (la auditoría registra su revisión, no su envío).
    select e.enviada_at, a.persona_id, 'envio', e.origen, null, null, null, e.enviada_por, e.id, e.cubre_desde, e.cubre_hasta
      from educacion_entregas e join asignaciones_educacion a on a.id = e.asignacion_id
    union all
    -- Las que la integrante retiró antes de la revisión.
    select e.retirada_at, a.persona_id, 'retiro', null, null, null, null, a.persona_id, e.id, e.cubre_desde, e.cubre_hasta
      from educacion_entregas e join asignaciones_educacion a on a.id = e.asignacion_id
     where e.retirada_at is not null
  )
  select h.at, h.pid, pe.nombres || ' ' || pe.apellidos, coalesce(s.codigo, '?'),
         h.fuente, h.campo, h.va, h.vn,
         case when v_do or h.campo = 'educacion_entrega' then h.mot end,
         case when v_do then por.nombres || ' ' || por.apellidos end,
         h.eid, h.cd, h.ch
    from hechos h
    join personas pe on pe.id = h.pid
    left join sedes s on s.id = pe.sede_base_id
    left join personas por on por.id = h.por
   where (v_quien is null or h.pid = v_quien)
     and (v_ini is null or h.at >= v_ini)
     and (v_fin is null or h.at < v_fin)
   order by h.at desc, h.eid nulls last;
end;
$$;


-- ── G · Quién puede llamar a qué ────────────────────────────────────────────
grant execute on function fn_educacion_enviar_adelantado(uuid,uuid,date,text,jsonb,jsonb,text,uuid) to authenticated;
grant execute on function fn_educacion_coberturas()                  to authenticated;
grant execute on function fn_educacion_apoyo_pagado(date)            to authenticated;
grant execute on function fn_educacion_historial(uuid,date,date)     to authenticated;
revoke execute on function fn_educacion_enviar_adelantado(uuid,uuid,date,text,jsonb,jsonb,text,uuid) from public, anon;
revoke execute on function fn_educacion_coberturas()                 from public, anon;
revoke execute on function fn_educacion_apoyo_pagado(date)           from public, anon;
revoke execute on function fn_educacion_historial(uuid,date,date)    from public, anon;
revoke execute on function fn_educacion_cobertura_calendario()       from public, anon, authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (529, 'un_pago_adelantado_cubre_varios_meses_y_el_historial_de_educacion')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── COMPROBACIÓN (un solo select; el SQL Editor corre solo el último) ────────
-- Antes de pegar, que nada de esto exista ya en producción (todo en 0 / null):
--   select (select count(*) from pg_proc where proname in ('fn_educacion_enviar_adelantado', 'fn_educacion_coberturas',
--             'fn_educacion_apoyo_pagado', 'fn_educacion_historial', 'fn_educacion_cobertura_mover_calendario')) as funciones,
--          to_regclass('public.educacion_entrega_meses') as tabla,
--          (select count(*) from information_schema.columns where table_name = 'educacion_entregas'
--             and column_name in ('cubre_desde', 'cubre_hasta')) as columnas;
-- Después de pegar:
--   select (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 529) as registro,
--          (select count(*) from pg_proc where proname in ('fn_educacion_enviar_adelantado', 'fn_educacion_coberturas',
--             'fn_educacion_apoyo_pagado', 'fn_educacion_historial', 'fn_educacion_cobertura_mover_calendario',
--             'fn_educacion_cobertura_calendario', 'fn_educacion_cobertura_inmutable')) as funciones_7,
--          to_regclass('public.educacion_entrega_meses') is not null as tabla,
--          (select count(*) from pg_trigger where tgname in ('trg_educacion_cobertura_calendario',
--             'trg_educacion_cobertura_inmutable', 'trg_educacion_meses_inmutables')) as triggers_3;
