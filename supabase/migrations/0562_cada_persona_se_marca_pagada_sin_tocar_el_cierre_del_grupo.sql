-- ============================================================================
-- 0562 · CADA PERSONA SE MARCA PAGADA SIN TOCAR EL CIERRE DEL GRUPO
-- ============================================================================
--
-- QUÉ PROMETE
--   Un checklist personal de Felipe dentro de Planilla: marcar a una persona
--   como «ya le transferí» mientras va pagando una por una durante el mes, y
--   poder desmarcarla si se equivocó — siempre con un motivo. NO es el pago
--   oficial del grupo: `fn_periodo_pagado` (0037/0323) sigue siendo la única
--   función que congela el desglose y decide qué entra a Costos y a la boleta.
--   Esta migración no mueve plata, no cambia ningún cálculo de
--   `fn_planilla_calcular` y no toca `periodo_grupo_pago`.
--
--   El estado de cada persona se guarda como una BITÁCORA de solo-inserciones
--   (igual que `marcajes` y `correcciones_auditoria`): cada marcado o
--   desmarcado es una fila nueva, nunca un UPDATE. «¿Está marcada?» se
--   responde mirando el ÚLTIMO evento de esa persona en ese periodo. Así el
--   motivo de un desmarcado nunca puede vivir en una tabla de historial
--   separada que se desincroniza de un estado aparte — el defecto que ya se
--   vio con «qué le tocaba trabajar ese día» antes de unificarlo.
--
--   El monto que queda en cada evento lo calcula el SERVIDOR en el instante
--   de marcar (con `fn_proyeccion_periodo`, la misma fuente que ya pinta la
--   columna «Total» en pantalla) — nunca se recibe del navegador. Si después
--   una corrección cambia el total de esa persona, el evento guardado NO se
--   actualiza solo: la pantalla compara ese monto congelado contra el total
--   de hoy y avisa si difieren. Solo admin puede marcar o desmarcar (decidido
--   con Felipe el 2026-10-29): ni líderes de equipo ni DO, a diferencia del
--   resto de Planilla, que sí dejan ver a admin y líder por igual.
--
-- QUÉ ASUME
--   Que `fn_proyeccion_periodo` sigue devolviendo cada fila con `persona_id`,
--   `tipo_vinculo` y `total` dentro de `filas` (0323) — es de ahí de donde
--   sale el monto y el grupo de cada evento, nunca de un parámetro que mande
--   el cliente.
--
-- POR QUÉ UNA TABLA NUEVA, Y POR QUÉ SIN UPDATE
--   La alternativa era una columna `pagado boolean` en una fila de estado por
--   (periodo, persona), con el motivo del desmarcado en una tabla de
--   historial aparte. Se descartó: esa forma tiene DOS fuentes para la misma
--   pregunta, que pueden desincronizarse. Con una bitácora de solo-inserciones
--   no hay UPDATE que pueda pisar nada, y el historial que ve Felipe en
--   pantalla es literalmente la misma tabla que decide el estado actual.
--
-- POR QUÉ `secuencia` Y NO `creado_at` PARA DECIDIR CUÁL ES «EL ÚLTIMO»
--   Lección de esta casa: dentro de una transacción (y toda prueba pgTAP corre
--   en una) `now()` vale lo mismo para todas las filas, así que marcar y
--   desmarcar a la misma persona en la misma prueba empatarían al
--   microsegundo si el orden dependiera de `creado_at` — el defecto que ya
--   persiguió la 0312/0386/0387/0388/0389 en otras seis funciones. Acá se
--   cierra de raíz con una columna `identity` (autoincremental, nunca empata,
--   no depende del reloj): `creado_at` queda solo para mostrarlo en pantalla.
--
-- POR QUÉ NO SE AUTO-DISPARA EL CIERRE DEL GRUPO
--   Se consideró que marcar a la última persona pendiente disparara sola
--   `fn_periodo_pagado`. Se descartó: ese cierre tiene sus propios frenos
--   (avisos revisados, periodos anteriores aceptados, y sobre todo la palabra
--   de confirmación cuando se paga ANTES de que el periodo termine, 0527) que
--   existen justo para evitar un congelado accidental — el incidente del
--   2026-10-21 que la 0545 tuvo que reparar. Felipe suele terminar de pagar a
--   todos antes del cierre del periodo, así que automatizarlo reproduciría
--   ese mismo accidente sin que nadie escriba la palabra. En su lugar, la
--   pantalla ofrece un aviso con un botón directo a «Revisar cierre»: el
--   check es tuyo, el cierre lo sigues confirmando tú.
--
-- CÓMO SE REVIERTE
--   drop trigger trg_pago_persona_eventos_solo_por_rpc on planilla_pago_persona_eventos;
--   drop function fn_bloquear_pago_persona_evento_directo();
--   drop function fn_pago_persona_marcar(uuid, uuid);
--   drop function fn_pago_persona_desmarcar(uuid, uuid, text);
--   drop function fn_pago_personas_estado(uuid);
--   drop function fn_es_admin();
--   drop table planilla_pago_persona_eventos;
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final.
-- ============================================================================

-- ── 1 · fn_es_admin — no existía: hasta hoy solo había fn_es_admin_o_lider ──
create or replace function fn_es_admin()
returns boolean
language sql
stable
as $$
  select coalesce(fn_rol_actual() = 'admin', false);
$$;

comment on function fn_es_admin() is
  'Rol admin exacto, sin líderes — 0562. fn_es_admin_o_lider() ya cubre admin+líder para lo que hoy comparte permiso; esta es para lo que Felipe quiso dejar solo para admin.';

-- ── 2 · La bitácora ──────────────────────────────────────────────────────────
create table if not exists planilla_pago_persona_eventos (
  id          uuid primary key default gen_random_uuid(),
  secuencia   bigint generated always as identity,
  periodo_id  uuid not null references periodos_planilla(id),
  persona_id  uuid not null references personas(id),
  grupo       text not null check (grupo in ('planilla','prueba','rxh','no_trabajador','practicante')),
  tipo        text not null check (tipo in ('marcado','desmarcado')),
  monto       numeric(10,2) not null check (monto >= 0),
  motivo      text check (tipo = 'marcado' or (motivo is not null and length(trim(motivo)) >= 3)),
  creado_por  uuid not null references personas(id),
  creado_at   timestamptz not null default now()
);

comment on table planilla_pago_persona_eventos is
  'Bitácora de solo-inserciones del checklist personal de pago, persona por persona — 0562. El estado actual de una persona en un periodo es el ÚLTIMO evento por `secuencia`. NO es el pago oficial del grupo (periodo_grupo_pago / fn_periodo_pagado); no participa de ningún cálculo de planilla.';

create index idx_pago_persona_eventos_estado on planilla_pago_persona_eventos (periodo_id, persona_id, secuencia desc);

alter table planilla_pago_persona_eventos enable row level security;
revoke all on planilla_pago_persona_eventos from anon, public;
grant select on planilla_pago_persona_eventos to authenticated;

drop policy if exists pago_persona_eventos_select_admin_lider on planilla_pago_persona_eventos;
create policy pago_persona_eventos_select_admin_lider on planilla_pago_persona_eventos
  for select to authenticated using (fn_es_admin_o_lider());
-- Escritura: NINGUNA política — solo entra por fn_pago_persona_marcar /
-- fn_pago_persona_desmarcar (security definer), igual que periodo_grupo_pago.

-- ── 3 · El candado: ni un insert/update/delete a mano se salta la puerta ───
-- Mismo mecanismo que fn_bloquear_sede_directa (0342): las dos funciones de
-- abajo corren security definer, así que mientras ejecutan `current_user` es
-- la dueña de la función (postgres), no la sesión que llamó. Pero acá además
-- se bloquea TODO update/delete, incluso desde postgres: un evento no se
-- edita ni se borra nunca — si fue un error, se desmarca con su motivo.
create or replace function fn_bloquear_pago_persona_evento_directo()
returns trigger
language plpgsql as $function$
begin
  if tg_op = 'INSERT' and current_user <> 'postgres' then
    raise exception 'Un evento de pago se crea con fn_pago_persona_marcar o fn_pago_persona_desmarcar, no con un insert directo.';
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception 'Un evento de pago no se edita ni se borra: si fue un error, se desmarca con su motivo.';
  end if;
  return coalesce(new, old);
end;
$function$;

drop trigger if exists trg_pago_persona_eventos_solo_por_rpc on planilla_pago_persona_eventos;
create trigger trg_pago_persona_eventos_solo_por_rpc
  before insert or update or delete on planilla_pago_persona_eventos
  for each row
  execute function fn_bloquear_pago_persona_evento_directo();

-- ── 4 · Marcar ───────────────────────────────────────────────────────────────
create or replace function fn_pago_persona_marcar(p_periodo_id uuid, p_persona_id uuid)
returns table (monto numeric, creado_at timestamptz)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_quien      uuid;
  v_calc       jsonb;
  v_fila       jsonb;
  v_grupo      text;
  v_monto      numeric;
  v_ya_marcado boolean;
  v_creado_at  timestamptz;
begin
  if fn_es_admin() is not true then
    raise exception 'Solo un administrador puede marcar el pago de una persona.';
  end if;

  if not exists (select 1 from periodos_planilla where id = p_periodo_id) then
    raise exception 'Periodo inexistente.';
  end if;

  select (tipo = 'marcado') into v_ya_marcado
    from planilla_pago_persona_eventos
   where periodo_id = p_periodo_id and persona_id = p_persona_id
   order by secuencia desc
   limit 1;

  if coalesce(v_ya_marcado, false) then
    raise exception 'Esta persona ya está marcada como pagada en este periodo.';
  end if;

  -- El monto y el grupo salen SIEMPRE del cálculo del servidor — nunca de lo
  -- que mande el navegador — con la misma función que pinta la columna Total.
  v_calc := fn_proyeccion_periodo(p_periodo_id);

  select f into v_fila
    from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
   where (f->>'persona_id')::uuid = p_persona_id
   limit 1;

  if v_fila is null then
    raise exception 'Esa persona no aparece en la planilla de este periodo.';
  end if;

  v_grupo := v_fila->>'tipo_vinculo';
  if v_grupo is null or v_grupo not in ('planilla','prueba','rxh','no_trabajador','practicante') then
    raise exception 'No se pudo determinar el grupo de esta persona en este periodo.';
  end if;

  v_monto := round((v_fila->>'total')::numeric, 2);

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién marca el pago, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  insert into planilla_pago_persona_eventos (periodo_id, persona_id, grupo, tipo, monto, creado_por)
  values (p_periodo_id, p_persona_id, v_grupo, 'marcado', v_monto, v_quien)
  returning planilla_pago_persona_eventos.creado_at into v_creado_at;

  return query select v_monto, v_creado_at;
end;
$function$;

comment on function fn_pago_persona_marcar(uuid, uuid) is
  'Marca a una persona como pagada en un periodo — checklist personal, 0562. El monto lo calcula esta función con fn_proyeccion_periodo, nunca el cliente. Solo admin. No toca periodo_grupo_pago ni ningún cálculo de planilla.';

revoke all on function fn_pago_persona_marcar(uuid, uuid) from public, anon;
grant execute on function fn_pago_persona_marcar(uuid, uuid) to authenticated;

-- ── 5 · Desmarcar — exige motivo ─────────────────────────────────────────────
create or replace function fn_pago_persona_desmarcar(p_periodo_id uuid, p_persona_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_quien  uuid;
  v_ultimo planilla_pago_persona_eventos;
begin
  if fn_es_admin() is not true then
    raise exception 'Solo un administrador puede desmarcar el pago de una persona.';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe el motivo del desmarcado (al menos 3 caracteres).';
  end if;

  select * into v_ultimo
    from planilla_pago_persona_eventos
   where periodo_id = p_periodo_id and persona_id = p_persona_id
   order by secuencia desc
   limit 1;

  if not found or v_ultimo.tipo <> 'marcado' then
    raise exception 'Esta persona no está marcada como pagada en este periodo.';
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién desmarca el pago, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  insert into planilla_pago_persona_eventos (periodo_id, persona_id, grupo, tipo, monto, motivo, creado_por)
  values (p_periodo_id, p_persona_id, v_ultimo.grupo, 'desmarcado', v_ultimo.monto, trim(p_motivo), v_quien);
end;
$function$;

comment on function fn_pago_persona_desmarcar(uuid, uuid, text) is
  'Desmarca a una persona pagada en un periodo — exige motivo de al menos 3 caracteres, 0562. Solo admin. El evento queda en la bitácora para siempre: no se edita ni se borra.';

revoke all on function fn_pago_persona_desmarcar(uuid, uuid, text) from public, anon;
grant execute on function fn_pago_persona_desmarcar(uuid, uuid, text) to authenticated;

-- ── 6 · Leer el estado de todas las personas de un periodo de un solo golpe ──
create or replace function fn_pago_personas_estado(p_periodo_id uuid)
returns table (
  persona_id        uuid,
  grupo             text,
  marcado           boolean,
  monto             numeric,
  marcado_at        timestamptz,
  marcado_por_nombre text
)
language plpgsql
stable
security definer
set search_path = public
as $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver el estado de pago por persona.';
  end if;

  return query
  with ultimo as (
    select distinct on (e.persona_id)
      e.persona_id, e.grupo, e.tipo, e.monto, e.creado_at, e.creado_por
    from planilla_pago_persona_eventos e
    where e.periodo_id = p_periodo_id
    order by e.persona_id, e.secuencia desc
  )
  select
    u.persona_id,
    u.grupo,
    (u.tipo = 'marcado'),
    u.monto,
    u.creado_at,
    nullif(trim(coalesce(pe.nombres, '') || ' ' || coalesce(pe.apellidos, '')), '')
  from ultimo u
  left join personas pe on pe.id = u.creado_por;
end;
$function$;

comment on function fn_pago_personas_estado(uuid) is
  'El último evento de cada persona en un periodo (marcado o no, y con qué monto y quién) — 0562. Admin o líder, igual que el resto de lectura de Planilla; solo marcar/desmarcar es admin exclusivo.';

revoke all on function fn_pago_personas_estado(uuid) from public, anon;
grant execute on function fn_pago_personas_estado(uuid) to authenticated;

notify pgrst, 'reload schema';

-- ── 7 · Rastro ───────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (562, 'cada_persona_se_marca_pagada_sin_tocar_el_cierre_del_grupo')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── 8 · Comprobación de que la pegada llegó entera ──────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_es_admin') = 1 as fn_es_admin_existe,
  (select count(*) from pg_proc where proname = 'fn_pago_persona_marcar') = 1 as fn_marcar_existe,
  (select count(*) from pg_proc where proname = 'fn_pago_persona_desmarcar') = 1 as fn_desmarcar_existe,
  (select count(*) from pg_proc where proname = 'fn_pago_personas_estado') = 1 as fn_estado_existe,
  (select count(*) from pg_trigger where tgname = 'trg_pago_persona_eventos_solo_por_rpc'
     and tgrelid = 'planilla_pago_persona_eventos'::regclass) = 1 as el_trigger_existe,
  (select count(*) from information_schema.columns
    where table_name = 'planilla_pago_persona_eventos' and column_name = 'secuencia') = 1 as la_secuencia_existe;
