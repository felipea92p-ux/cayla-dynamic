-- ============================================================================
-- 0584 — Cada quien dice cuándo puede trabajar
-- ============================================================================
--
-- QUÉ PROMETE
--   Tres cosas, y ninguna mueve plata:
--
--   1. La JORNADA de cada persona —cuántas horas a la semana trabaja, completa
--      o parcial— queda escrita en su ficha (`personas.jornada_semanal_horas`)
--      y la fija DO, con motivo y rastro. Hasta hoy no estaba en ninguna parte:
--      `contratos.horas_semanales` solo se llena en los convenios de prácticas.
--   2. Cada colaboradora puede decir desde «Lo mío · Mi disponibilidad» qué días
--      u horas NO puede trabajar (o prefiere no), por qué y desde cuándo. Va a
--      su líder de equipo, que la aprueba o la conversa. DO puede registrarla
--      por ella. Hasta que se aprueba, no se usa.
--   3. Un contrato de lectura para la sugerencia de turnos (sesión de Turnos):
--      `fn_disponibilidad_vigente`, ya expandido por fecha.
--
-- QUÉ ASUME
--   · btree_gist está instalada (0574, 0579): la usan los EXCLUDE de abajo.
--   · «Líder de equipo de la sede» = rol `supervisor_sede` y la misma
--     `sede_base_id` (como en la 0435 y la 0579). No hay jefe directo.
--   · `fn_es_admin_o_lider()` (0078) = admin o Líder DO.
--
-- DECIDIÓ FELIPE (2026-11-02 y 2026-11-03)
--   · Horas exactas, no franjas: cada excepción es un BLOQUE de un día —todo el
--     día o de una hora a otra, de media en media hora— con estado «no puedo» o
--     «prefiero no». Mañana y Tarde son atajos de la pantalla, no del modelo.
--   · Un bloque es de un DÍA DE LA SEMANA («los martes») o de una FECHA («el 15
--     de noviembre»); nunca de los dos.
--   · La disponibilidad es permanente: se registra una vez y sigue vigente
--     hasta que se cambia. La generación de turnos NUNCA la espera: quien no
--     registró nada se toma como «cualquier día y hora». El corte semanal (qué
--     aprobación entra en la sugerencia de qué semana) lo pone quien la lee,
--     con `p_aprobada_antes`; aquí no se escribe una hora.
--   · «Horario fijo» (quien no rota: hoy Angie y Keyla en TRU, y Danitza) sale
--     de SU disponibilidad aprobada, no de una lista en el código. Lo marca
--     quien aprueba, no ella: es una decisión de la líder o de DO.
--   · La jornada la fija DO. La colaboradora no la cambia. NO entra a la
--     planilla: es la referencia de «45 h de 45 h» en «Tu semana» y del aviso
--     de horas disponibles. Si algún día una regla de pago la lee, esa
--     migración tendrá que decirlo, y medir a quién le cambia.
--   · Las horas disponibles se miden contra la VENTANA de la sede, deducida de
--     los horarios vigentes de su equipo (la entrada más temprana y la salida
--     más tarde de cada día): `fn_sede_ventana_semanal`. No hay tabla de horario
--     de sede, y escribirlo a mano sería una lista que miente el día que cambie.
--   · DO registra la disponibilidad y fija la jornada desde /admin/disponibilidad.
--
-- CÓMO SE ARMA (y por qué)
--   · `disponibilidades`: una fila por cada envío, nunca se pisa. Estado:
--       enviada     → la mandó ella; espera a su líder.
--       aprobada    → vigente entre vigente_desde y vigente_hasta (vacío = sin fin).
--       conversar   → su líder quiere hablarlo antes (con respuesta escrita).
--       reemplazada → una más nueva la sustituyó (enviada o aprobada).
--       retirada    → ella la retiró antes de que la vieran.
--     Una sola `enviada` por persona (índice parcial). Dos `aprobada` no se
--     cruzan en el tiempo (EXCLUDE). Al aprobar una nueva, la aprobada anterior
--     se recorta al día anterior; si empezaba el mismo día o después, pasa a
--     `reemplazada`. Si la nueva tiene fin, al terminar NO revive la anterior:
--     se vuelve a «cualquier día y hora», que es lo que se pidió («hasta el fin
--     del ciclo»).
--   · `disponibilidad_bloques`: las excepciones de cada envío. Sin bloques =
--     puede todo. Dos bloques del mismo día no se cruzan (EXCLUDE).
--   · Se escribe SOLO por las funciones: revoke all + grant select (molde de la
--     0480 y la 0579), porque authenticated nace con INSERT/UPDATE/DELETE sobre
--     toda tabla nueva de public.
--   · La jornada se cambia por una puerta (`fn_set_jornada`) y un trigger
--     rechaza el update directo: el molde de campo sensible de la 0261, la
--     0295/0296 y la 0342 (CLAUDE.md, «Un campo sensible se cambia por una
--     función guardián»). No es plata, pero sí lo que se le muestra a cada una
--     como su compromiso semanal.
--
-- QUIÉN HACE QUÉ
--   enviar / retirar          la propia persona, activa
--   aprobar / conversar       la líder de equipo de su sede, DO o admin.
--                             Nunca la propia. Si ella es líder de equipo,
--                             admin o Líder DO, solo DO o admin.
--   registrar por ella        DO o admin (entra aprobada). Nunca la propia.
--   fijar la jornada          DO o admin, con motivo.
--   leer                      RLS: ella, la líder de su sede, DO y admin.
--                             El motivo también: no lo ve nadie más del equipo.
--
-- CONTRATO DE LECTURA — fn_disponibilidad_vigente(p_desde, p_hasta, p_sede_id, p_aprobada_antes)
--   Devuelve (persona_id, fecha, desde, hasta, estado), una fila por cada
--   restricción de cada día del rango, SOLO de disponibilidades aprobadas y de
--   personas activas:
--     estado = 'no_puede'     → la sugerencia NUNCA la pone ahí. En la grilla
--                               de Turnos sale rayado.
--     estado = 'prefiere_no'  → se respeta si alcanza la gente; si no, se avisa.
--     estado = 'horario_fijo' → desde/hasta vacíos: ese día conserva su horario
--                               base, la sugerencia no la mueve.
--     desde/hasta vacíos (en no_puede / prefiere_no) = TODO el día.
--     Un turno CHOCA con un bloque si se cruza con él, aunque sea un minuto
--     (los dos intervalos con fin abierto).
--   Quien no aparece en un día: puede a cualquier hora.
--   `p_aprobada_antes` (opcional): solo cuenta lo aprobado hasta ese instante.
--   Es el corte semanal; si va vacío, cuenta todo lo aprobado.
--   La llaman admin y Líder DO (cualquier sede) y la líder de equipo (la suya).
--   Rango máximo: 62 días.
--
-- ESTADOS QUE NUNCA DEBEN EXISTIR (y quién lo impide)
--   · Dos aprobadas que se cruzan en el tiempo → EXCLUDE disponibilidad_sin_cruces.
--   · Dos enviadas pendientes de la misma persona → índice único parcial.
--   · Un bloque con día de la semana Y fecha, o sin ninguno → CHECK.
--   · Un bloque con solo una hora, o que termina antes de empezar → CHECK.
--   · Un bloque fuera de la media hora (10:15) → CHECK.
--   · Dos bloques del mismo día que se cruzan → EXCLUDE bloque_sin_cruces.
--   · Una disponibilidad o una jornada escrita sin pasar por su función → sin
--     privilegio de escritura / trigger.
--   · Una persona que se aprueba a sí misma → las funciones.
--
-- SE ROMPE SI
--   · Se renombra `fn_disponibilidad_vigente` o cambia el significado de sus
--     estados: la lee la sugerencia de Turnos (otra sesión).
--   · Alguien lee `disponibilidades` directo sin filtrar `estado = 'aprobada'`:
--     usaría algo que la líder todavía no vio. Para eso está la función.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_disponibilidad_vigente(date, date, uuid, timestamptz);
--   drop function if exists fn_sede_ventana_semanal(uuid);
--   drop function if exists fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text);
--   drop function if exists fn_disponibilidad_resolver(uuid, text, text, boolean);
--   drop function if exists fn_disponibilidad_retirar(uuid);
--   drop function if exists fn_disponibilidad_enviar(text, text, date, date, jsonb, text);
--   drop function if exists fn_disponibilidad_aprobar_interno(uuid, uuid);
--   drop function if exists fn_disponibilidad_guardar_interno(uuid, text, text, date, date, jsonb, text, text, uuid, boolean);
--   drop function if exists fn_puede_resolver_disponibilidad(uuid);
--   drop table if exists disponibilidad_bloques, disponibilidades;   -- solo si nadie la usa
--   drop trigger if exists trg_personas_jornada_solo_por_rpc on personas;
--   drop function if exists fn_bloquear_jornada_directa();
--   drop function if exists fn_set_jornada(uuid, numeric, text);
--   alter table personas drop column if exists jornada_semanal_horas;
--   delete from migraciones_aplicadas where numero = 584;
--   (Las filas de correcciones_auditoria se quedan: son historia.)
--
-- CÓMO SE COMPRUEBA
--   La consulta del final debe devolver una fila con todo en true y
--   «584 · cada_quien_dice_cuando_puede_trabajar».
--
-- No reescribe ninguna función existente: no lleva md5 de partida. Se
-- comprobó con donde-vive.sh que ninguna de las funciones nuevas existía.
-- ============================================================================

-- ── 1 · La jornada ───────────────────────────────────────────────────────────

alter table personas add column if not exists jornada_semanal_horas numeric(4,2);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'personas_jornada_semanal_valida') then
    alter table personas add constraint personas_jornada_semanal_valida
      check (jornada_semanal_horas is null or (jornada_semanal_horas > 0 and jornada_semanal_horas <= 48));
  end if;
end;
$$;

comment on column personas.jornada_semanal_horas is
  'Horas por semana que trabaja (completa o parcial). La fija DO con fn_set_jornada. NO entra a la '
  'planilla: es la referencia de «Tu semana» y de «Mi disponibilidad». Vacía = no se fijó. 0584.';

create or replace function fn_set_jornada(p_persona_id uuid, p_horas numeric, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quien  uuid;
  v_antes  numeric;
  v_estado text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional o un administrador fija la jornada.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo del cambio (al menos 5 caracteres).';
  end if;
  if p_horas is not null and (p_horas <= 0 or p_horas > 48) then
    raise exception 'La jornada va de más de 0 a 48 horas por semana.';
  end if;

  select jornada_semanal_horas, estado into v_antes, v_estado from personas where id = p_persona_id;
  if not found then
    raise exception 'Persona inválida.';
  end if;
  if v_estado = 'inactivo' then
    raise exception 'Esa persona ya no está activa.';
  end if;
  if v_antes is not distinct from p_horas then
    return;
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo.';
  end if;

  update personas set jornada_semanal_horas = p_horas where id = p_persona_id;

  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.jornada_semanal_horas', v_antes::text, p_horas::text,
          trim(p_motivo) || ' — No cambia su pago: es la referencia de su semana.', v_quien);
end;
$$;

comment on function fn_set_jornada(uuid, numeric, text) is
  'Fija las horas semanales de la jornada de una persona (o null para borrarla). Solo DO o admin, '
  'con motivo y rastro. No entra a la planilla. 0584.';

revoke all on function fn_set_jornada(uuid, numeric, text) from public, anon;
grant execute on function fn_set_jornada(uuid, numeric, text) to authenticated;

create or replace function fn_bloquear_jornada_directa()
returns trigger
language plpgsql as $function$
begin
  if new.jornada_semanal_horas is distinct from old.jornada_semanal_horas and current_user <> 'postgres' then
    raise exception 'La jornada se cambia con fn_set_jornada, no con un update directo.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_personas_jornada_solo_por_rpc on personas;
create trigger trg_personas_jornada_solo_por_rpc
  before update on personas
  for each row
  execute function fn_bloquear_jornada_directa();

-- ── 2 · Las tablas ───────────────────────────────────────────────────────────

create table if not exists disponibilidades (
  id              uuid primary key default gen_random_uuid(),
  persona_id      uuid not null references personas(id),
  tipo            text not null check (tipo in ('total', 'parcial')),
  motivo          text check (motivo in ('estudios', 'hijos', 'salud', 'otro_trabajo', 'otro')),
  nota            text check (nota is null or length(nota) <= 300),
  vigente_desde   date not null,
  vigente_hasta   date,
  estado          text not null default 'enviada'
                    check (estado in ('enviada', 'aprobada', 'conversar', 'reemplazada', 'retirada')),
  horario_fijo    boolean not null default false,
  registrada_por  uuid not null references personas(id),
  creada_at       timestamptz not null default now(),
  resuelta_por    uuid references personas(id),
  resuelta_at     timestamptz,
  respuesta       text check (respuesta is null or length(respuesta) <= 500),
  constraint disponibilidad_vigencia_ordenada check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  constraint disponibilidad_parcial_con_motivo check (tipo = 'total' or motivo is not null),
  constraint disponibilidad_resuelta_completa check (
    estado not in ('aprobada', 'conversar') or (resuelta_por is not null and resuelta_at is not null)),
  constraint disponibilidad_conversar_con_respuesta check (estado <> 'conversar' or respuesta is not null)
);

comment on table disponibilidades is
  'Qué días u horas puede trabajar cada persona: una fila por envío, nunca se pisa. Solo la APROBADA '
  'se usa, y se lee con fn_disponibilidad_vigente. Se escribe solo por las funciones fn_disponibilidad_*. 0584.';

create unique index if not exists idx_disponibilidad_una_enviada
  on disponibilidades (persona_id) where estado = 'enviada';
create index if not exists idx_disponibilidades_persona on disponibilidades (persona_id, estado);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'disponibilidad_sin_cruces') then
    alter table disponibilidades add constraint disponibilidad_sin_cruces exclude using gist (
      persona_id with =,
      daterange(vigente_desde, vigente_hasta, '[]') with &&
    ) where (estado = 'aprobada');
  end if;
end;
$$;

create table if not exists disponibilidad_bloques (
  id                 uuid primary key default gen_random_uuid(),
  disponibilidad_id  uuid not null references disponibilidades(id),
  dia_semana         smallint check (dia_semana between 0 and 6),   -- 0 = domingo, como extract(dow)
  fecha              date,
  desde              time,
  hasta              time,
  estado             text not null check (estado in ('no_puede', 'prefiere_no')),
  constraint bloque_dia_o_fecha check ((dia_semana is null) <> (fecha is null)),
  constraint bloque_horas_completas check ((desde is null) = (hasta is null)),
  constraint bloque_horas_ordenadas check (desde is null or hasta > desde),
  constraint bloque_media_hora check (
    desde is null or (extract(second from desde) = 0 and extract(minute from desde) in (0, 30)
                      and extract(second from hasta) = 0 and extract(minute from hasta) in (0, 30)))
);

comment on table disponibilidad_bloques is
  'Las excepciones de una disponibilidad: un día de la semana o una fecha, todo el día (sin horas) o '
  'de una hora a otra, «no puede» o «prefiere no». Sin bloques = puede todo. 0584.';

create index if not exists idx_disponibilidad_bloques on disponibilidad_bloques (disponibilidad_id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'bloque_sin_cruces') then
    alter table disponibilidad_bloques add constraint bloque_sin_cruces exclude using gist (
      disponibilidad_id with =,
      coalesce(dia_semana, -1::smallint) with =,
      coalesce(fecha, date '1900-01-01') with =,
      int4range(
        (extract(hour from coalesce(desde, time '00:00')) * 60 + extract(minute from coalesce(desde, time '00:00')))::int,
        case when hasta is null then 1440
             else (extract(hour from hasta) * 60 + extract(minute from hasta))::int end,
        '[)'
      ) with &&
    );
  end if;
end;
$$;

-- ── 3 · Quién lee (RLS) y quién escribe (nadie, salvo las funciones) ─────────

alter table disponibilidades enable row level security;
alter table disponibilidad_bloques enable row level security;

drop policy if exists disponibilidad_select_admin_lider on disponibilidades;
create policy disponibilidad_select_admin_lider on disponibilidades
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists disponibilidad_select_supervisor on disponibilidades;
create policy disponibilidad_select_supervisor on disponibilidades
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede'
         and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));

drop policy if exists disponibilidad_select_propia on disponibilidades;
create policy disponibilidad_select_propia on disponibilidades
  for select to authenticated using (persona_id = fn_persona_actual_id());

-- Un bloque se ve si se ve su disponibilidad: el subselect corre con la RLS de
-- quien pregunta, así que hereda las tres políticas de arriba.
drop policy if exists disponibilidad_bloques_select on disponibilidad_bloques;
create policy disponibilidad_bloques_select on disponibilidad_bloques
  for select to authenticated
  using (exists (select 1 from disponibilidades d where d.id = disponibilidad_id));

revoke all on disponibilidades, disponibilidad_bloques from anon, authenticated, public;
grant select on disponibilidades, disponibilidad_bloques to authenticated;

-- ── 4 · Quién puede resolver la de una persona ───────────────────────────────

create or replace function fn_puede_resolver_disponibilidad(p_persona_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_yo_rol  rol_usuario;
  v_yo_sede uuid;
  v_rol     rol_usuario;
  v_sede    uuid;
begin
  if v_yo is null or v_yo = p_persona_id then
    return false;
  end if;
  select rol, sede_base_id into v_yo_rol, v_yo_sede from personas where id = v_yo and estado = 'activo';
  if v_yo_rol is null then
    return false;
  end if;
  if v_yo_rol in ('admin', 'lider_do') then
    return true;
  end if;
  select rol, sede_base_id into v_rol, v_sede from personas where id = p_persona_id;
  return v_yo_rol = 'supervisor_sede'
     and v_sede is not distinct from v_yo_sede
     and coalesce(v_rol::text, 'integrante') = 'integrante';
end;
$$;

comment on function fn_puede_resolver_disponibilidad(uuid) is
  '¿Quien llama puede aprobar o conversar la disponibilidad de esa persona? DO y admin sobre cualquiera; '
  'la líder de equipo sobre las integrantes de su sede. Nunca la propia. 0584.';

revoke all on function fn_puede_resolver_disponibilidad(uuid) from public, anon;
grant execute on function fn_puede_resolver_disponibilidad(uuid) to authenticated;

-- ── 5 · Lo que comparten enviar y registrar ──────────────────────────────────
-- Internas: validan y escriben. Sin grant a authenticated.

create or replace function fn_disponibilidad_guardar_interno(
  p_persona_id uuid, p_tipo text, p_motivo text, p_desde date, p_hasta date,
  p_bloques jsonb, p_nota text, p_estado text, p_registrada_por uuid, p_horario_fijo boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  v_b      jsonb;
  v_fecha  date;
  v_dia    smallint;
  v_desde  time;
  v_hasta  time;
begin
  if p_tipo not in ('total', 'parcial') then
    raise exception 'Elige «Cualquier día y hora» o «Hay días u horas que no puedo».';
  end if;
  if p_desde is null then
    raise exception 'Falta la fecha desde la que rige.';
  end if;
  if p_desde < fn_hoy_lima() then
    raise exception 'La disponibilidad rige de hoy en adelante: no se cambia un día que ya pasó.';
  end if;
  if p_hasta is not null and p_hasta < p_desde then
    raise exception 'La fecha «hasta» es anterior a la fecha «desde».';
  end if;
  if p_bloques is null or jsonb_typeof(p_bloques) <> 'array' then
    raise exception 'Los días que no puedes tienen que venir como una lista.';
  end if;
  if p_tipo = 'total' and jsonb_array_length(p_bloques) > 0 then
    raise exception '«Cualquier día y hora» no lleva días que no puedes.';
  end if;
  if p_tipo = 'parcial' and jsonb_array_length(p_bloques) = 0 then
    raise exception 'Marca al menos un día u hora que no puedes, o elige «Cualquier día y hora».';
  end if;
  if p_tipo = 'parcial' and p_motivo is null then
    raise exception 'Elige el motivo: lo ven solo tu líder de equipo y Desarrollo Organizacional.';
  end if;
  if jsonb_array_length(p_bloques) > 60 then
    raise exception 'Son demasiados bloques (máximo 60).';
  end if;

  -- Una nueva reemplaza a la que esperaba (si la había). Antes del insert: el
  -- índice único no deja convivir dos enviadas ni un instante.
  update disponibilidades set estado = 'reemplazada'
   where persona_id = p_persona_id and estado = 'enviada';

  insert into disponibilidades (persona_id, tipo, motivo, nota, vigente_desde, vigente_hasta, estado,
                                horario_fijo, registrada_por)
  values (p_persona_id, p_tipo, case when p_tipo = 'parcial' then p_motivo end, nullif(trim(p_nota), ''),
          p_desde, p_hasta, 'enviada', coalesce(p_horario_fijo, false), p_registrada_por)
  returning id into v_id;

  for v_b in select b from jsonb_array_elements(p_bloques) b loop
    v_dia   := (v_b->>'dia_semana')::smallint;
    v_fecha := (v_b->>'fecha')::date;
    v_desde := (v_b->>'desde')::time;
    v_hasta := (v_b->>'hasta')::time;
    if v_fecha is not null and (v_fecha < p_desde or (p_hasta is not null and v_fecha > p_hasta)) then
      raise exception 'El % cae fuera de la vigencia que elegiste.', to_char(v_fecha, 'DD/MM/YYYY');
    end if;
    if (v_desde is null) <> (v_hasta is null) then
      raise exception 'Cada tramo necesita su hora de inicio y su hora de fin.';
    end if;
    if v_desde is not null and v_hasta <= v_desde then
      raise exception 'El tramo de % a % termina antes de empezar.', to_char(v_desde, 'HH24:MI'), to_char(v_hasta, 'HH24:MI');
    end if;
    begin
      insert into disponibilidad_bloques (disponibilidad_id, dia_semana, fecha, desde, hasta, estado)
      values (v_id, v_dia, v_fecha, v_desde, v_hasta, v_b->>'estado');
    exception
      when exclusion_violation then
        raise exception 'Dos tramos del mismo día se cruzan. Júntalos en uno.';
      when check_violation then
        raise exception 'Revisa los días marcados: cada uno es un día de la semana o una fecha, con horas de media en media hora.';
    end;
  end loop;

  if p_estado = 'aprobada' then
    perform fn_disponibilidad_aprobar_interno(v_id, p_registrada_por);
  end if;
  return v_id;
end;
$$;

create or replace function fn_disponibilidad_aprobar_interno(p_id uuid, p_quien uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_d disponibilidades%rowtype;
begin
  select * into v_d from disponibilidades where id = p_id for update;

  -- Las aprobadas que se cruzan con la nueva: las que empiezan el mismo día o
  -- después quedan reemplazadas; las que empezaron antes se recortan al día
  -- anterior. Lo de después del fin de la nueva NO revive (ver el encabezado).
  update disponibilidades set estado = 'reemplazada'
   where persona_id = v_d.persona_id and estado = 'aprobada' and id <> p_id
     and vigente_desde >= v_d.vigente_desde;

  update disponibilidades set vigente_hasta = v_d.vigente_desde - 1
   where persona_id = v_d.persona_id and estado = 'aprobada' and id <> p_id
     and vigente_desde < v_d.vigente_desde
     and (vigente_hasta is null or vigente_hasta >= v_d.vigente_desde);

  update disponibilidades
     set estado = 'aprobada', resuelta_por = p_quien, resuelta_at = now()
   where id = p_id;
end;
$$;

revoke all on function fn_disponibilidad_guardar_interno(uuid, text, text, date, date, jsonb, text, text, uuid, boolean)
  from public, anon, authenticated;
revoke all on function fn_disponibilidad_aprobar_interno(uuid, uuid) from public, anon, authenticated;

-- ── 6 · Las puertas ──────────────────────────────────────────────────────────

create or replace function fn_disponibilidad_enviar(
  p_tipo text, p_motivo text, p_desde date, p_hasta date, p_bloques jsonb, p_nota text default null
)
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
  perform pg_advisory_xact_lock(hashtext('disponibilidad:' || v_yo::text));
  return fn_disponibilidad_guardar_interno(v_yo, p_tipo, p_motivo, p_desde, p_hasta,
                                           coalesce(p_bloques, '[]'::jsonb), p_nota, 'enviada', v_yo, false);
end;
$$;

comment on function fn_disponibilidad_enviar(text, text, date, date, jsonb, text) is
  'La colaboradora manda su disponibilidad a su líder de equipo. p_bloques: '
  '[{"dia_semana":2,"desde":"08:30","hasta":"14:00","estado":"no_puede"}, {"fecha":"2026-11-15","estado":"no_puede"}]. '
  'Reemplaza la que tenía pendiente. No se usa hasta que se aprueba. 0584.';

revoke all on function fn_disponibilidad_enviar(text, text, date, date, jsonb, text) from public, anon;
grant execute on function fn_disponibilidad_enviar(text, text, date, date, jsonb, text) to authenticated;

create or replace function fn_disponibilidad_retirar(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update disponibilidades set estado = 'retirada'
   where id = p_id and persona_id = fn_persona_actual_id() and estado = 'enviada';
  if not found then
    raise exception 'Solo puedes retirar tu propia disponibilidad mientras espera a tu líder.';
  end if;
end;
$$;

revoke all on function fn_disponibilidad_retirar(uuid) from public, anon;
grant execute on function fn_disponibilidad_retirar(uuid) to authenticated;

create or replace function fn_disponibilidad_resolver(
  p_id uuid, p_decision text, p_respuesta text default null, p_horario_fijo boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_d  disponibilidades%rowtype;
  v_yo uuid := fn_persona_actual_id();
begin
  select * into v_d from disponibilidades where id = p_id;
  if not found then
    raise exception 'Esa disponibilidad no existe.';
  end if;
  if fn_puede_resolver_disponibilidad(v_d.persona_id) is not true then
    raise exception 'No puedes resolver esta disponibilidad: la resuelve su líder de equipo o Desarrollo Organizacional.';
  end if;
  perform pg_advisory_xact_lock(hashtext('disponibilidad:' || v_d.persona_id::text));
  select * into v_d from disponibilidades where id = p_id for update;
  if v_d.estado <> 'enviada' then
    raise exception 'Esta disponibilidad ya no espera respuesta (está %).', v_d.estado;
  end if;

  if p_decision = 'aprobar' then
    update disponibilidades
       set horario_fijo = coalesce(p_horario_fijo, false), respuesta = nullif(trim(p_respuesta), '')
     where id = p_id;
    perform fn_disponibilidad_aprobar_interno(p_id, v_yo);
  elsif p_decision = 'conversar' then
    if p_respuesta is null or length(trim(p_respuesta)) < 5 then
      raise exception 'Escríbele qué quieres conversar (al menos 5 caracteres).';
    end if;
    update disponibilidades
       set estado = 'conversar', respuesta = trim(p_respuesta), resuelta_por = v_yo, resuelta_at = now()
     where id = p_id;
  else
    raise exception 'La decisión es «aprobar» o «conversar».';
  end if;
end;
$$;

comment on function fn_disponibilidad_resolver(uuid, text, text, boolean) is
  'La líder de equipo (de su sede), DO o admin aprueba o conversa una disponibilidad enviada. Al aprobar '
  'puede marcar «horario fijo». Nunca la propia. 0584.';

revoke all on function fn_disponibilidad_resolver(uuid, text, text, boolean) from public, anon;
grant execute on function fn_disponibilidad_resolver(uuid, text, text, boolean) to authenticated;

create or replace function fn_disponibilidad_registrar(
  p_persona_id uuid, p_tipo text, p_motivo text, p_desde date, p_hasta date, p_bloques jsonb,
  p_horario_fijo boolean default false, p_nota text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional o un administrador registra la disponibilidad de otra persona.';
  end if;
  if v_yo is null or v_yo = p_persona_id then
    raise exception 'Tu propia disponibilidad la mandas desde «Lo mío», y la aprueba otra persona.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no está activa.';
  end if;
  perform pg_advisory_xact_lock(hashtext('disponibilidad:' || p_persona_id::text));
  return fn_disponibilidad_guardar_interno(p_persona_id, p_tipo, p_motivo, p_desde, p_hasta,
                                           coalesce(p_bloques, '[]'::jsonb), p_nota, 'aprobada', v_yo, p_horario_fijo);
end;
$$;

comment on function fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text) is
  'DO o admin registra la disponibilidad de una persona por ella; entra aprobada y reemplaza la que '
  'tenía pendiente. 0584.';

revoke all on function fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text) from public, anon;
grant execute on function fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text) to authenticated;

-- ── 7 · La ventana de la sede ────────────────────────────────────────────────
-- Contra qué se miden las «horas disponibles»: la entrada más temprana y la
-- salida más tarde de cada día, entre los horarios vigentes HOY de las
-- personas activas de la sede. Solo devuelve dos horas por día: no expone el
-- horario de nadie.

create or replace function fn_sede_ventana_semanal(p_sede_id uuid)
returns table (dia smallint, abre time, cierra time)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if (fn_es_admin_o_lider() or fn_sede_actual_persona() = p_sede_id) is not true then
    raise exception 'No autorizado.';
  end if;

  return query
    with vigentes as (
      select h.*
        from horarios_asignados h
        join personas p on p.id = h.persona_id
       where p.sede_base_id = p_sede_id and p.estado = 'activo'
         and h.vigente_desde <= fn_hoy_lima()
         and (h.vigente_hasta is null or h.vigente_hasta >= fn_hoy_lima())
    ),
    tramos as (
      -- horario_por_dia: {"1": {"e": "08:30", "s": "14:30"}, …}
      select (k.key)::smallint as d, (k.value->>'e')::time as e, (k.value->>'s')::time as s
        from vigentes v, jsonb_each(v.horario_por_dia) k
       where v.horario_por_dia is not null and k.value->>'e' is not null and k.value->>'s' is not null
      union all
      -- legacy: dias_laborables con hora_entrada/hora_salida
      select dl::smallint, v.hora_entrada, v.hora_salida
        from vigentes v, unnest(v.dias_laborables) dl
       where v.horario_por_dia is null and v.hora_entrada is not null and v.hora_salida is not null
    )
    select t.d, min(t.e), max(t.s)
      from tramos t
     where t.s > t.e
     group by t.d
     order by t.d;
end;
$$;

comment on function fn_sede_ventana_semanal(uuid) is
  'De qué hora a qué hora hay alguien de la sede cada día de la semana (0 = domingo), según los '
  'horarios vigentes hoy. Es la ventana contra la que «Mi disponibilidad» mide las horas libres. 0584.';

revoke all on function fn_sede_ventana_semanal(uuid) from public, anon;
grant execute on function fn_sede_ventana_semanal(uuid) to authenticated;

-- ── 8 · El contrato de lectura ───────────────────────────────────────────────

create or replace function fn_disponibilidad_vigente(
  p_desde date, p_hasta date, p_sede_id uuid default null, p_aprobada_antes timestamptz default null
)
returns table (persona_id uuid, fecha date, desde time, hasta time, estado text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true
     and not (fn_rol_actual() = 'supervisor_sede' and p_sede_id is not null
              and fn_sede_actual_persona() = p_sede_id) then
    raise exception 'No autorizado.';
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 62 then
    raise exception 'El rango va de una fecha a otra, de hasta 62 días.';
  end if;

  return query
    with dias as (
      select g::date as f, extract(dow from g)::smallint as dow
        from generate_series(p_desde, p_hasta, interval '1 day') g
    ),
    vigentes as (
      select d.*, x.f, x.dow
        from disponibilidades d
        join personas p on p.id = d.persona_id and p.estado = 'activo'
        join dias x on x.f between d.vigente_desde and coalesce(d.vigente_hasta, 'infinity'::date)
       where d.estado = 'aprobada'
         and (p_sede_id is null or p.sede_base_id = p_sede_id)
         and (p_aprobada_antes is null or d.resuelta_at <= p_aprobada_antes)
    )
    select v.persona_id, v.f, b.desde, b.hasta, b.estado
      from vigentes v
      join disponibilidad_bloques b on b.disponibilidad_id = v.id
     where b.dia_semana = v.dow or b.fecha = v.f
    union all
    select v.persona_id, v.f, null::time, null::time, 'horario_fijo'::text
      from vigentes v
     where v.horario_fijo
     order by 1, 2, 3 nulls first;
end;
$$;

comment on function fn_disponibilidad_vigente(date, date, uuid, timestamptz) is
  'CONTRATO DE LECTURA para la sugerencia de turnos. Por persona y fecha: no_puede (nunca ahí), '
  'prefiere_no (si alcanza la gente) u horario_fijo (conserva su horario base). Sin horas = todo el día. '
  'Solo lo aprobado; p_aprobada_antes es el corte semanal. Ver el encabezado de la 0584.';

revoke all on function fn_disponibilidad_vigente(date, date, uuid, timestamptz) from public, anon;
grant execute on function fn_disponibilidad_vigente(date, date, uuid, timestamptz) to authenticated;

-- ── 9 · Registro ─────────────────────────────────────────────────────────────

insert into migraciones_aplicadas (numero, nombre) values (584, 'cada_quien_dice_cuando_puede_trabajar')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  exists (select 1 from information_schema.columns
           where table_name = 'personas' and column_name = 'jornada_semanal_horas')               as la_jornada_existe,
  exists (select 1 from pg_trigger where tgname = 'trg_personas_jornada_solo_por_rpc')            as la_jornada_tiene_candado,
  (select relrowsecurity from pg_class where oid = 'public.disponibilidades'::regclass)           as tiene_rls,
  (select count(*) = 3 from pg_policy where polrelid = 'public.disponibilidades'::regclass)       as tres_politicas,
  not has_table_privilege('authenticated', 'public.disponibilidades', 'INSERT')                   as nadie_escribe_directo,
  exists (select 1 from pg_constraint where conname = 'disponibilidad_sin_cruces')                as sin_cruces,
  to_regprocedure('fn_disponibilidad_vigente(date,date,uuid,timestamptz)') is not null            as el_contrato_existe,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 584)                as registro;
