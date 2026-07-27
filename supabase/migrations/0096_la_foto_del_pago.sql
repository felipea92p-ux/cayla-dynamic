-- ============================================================================
-- 0096 — La foto del pago
-- ----------------------------------------------------------------------------
-- EL PROBLEMA
--
-- La planilla no se guarda: se CALCULA en vivo cada vez que alguien abre la
-- pantalla. `fn_planilla_calcular` lee marcajes, horarios, salarios vigentes,
-- feriados, descansos sustitutorios, bonos y descuentos, y devuelve el número
-- de ese instante. Marcar un periodo como «pagado» solo cambia una palabra en
-- `periodos_planilla.estado`: no congela nada.
--
-- Eso significa que el total de un periodo YA PAGADO puede cambiar después. Hoy
-- se cerraron tres formas de que pasara (0093 descanso sustitutorio, 0095 horas
-- negativas, 0089 el candado al confirmar un auto-cierre), pero cerrar puertas
-- de una en una no es una garantía: cualquier función futura que toque un dato
-- de un mes ya pagado vuelve a abrir el agujero, y nadie se entera, porque no
-- hay contra qué comparar.
--
-- Y sin un número que no se mueva no hay contabilidad de costos posible. Un
-- costo que cambia solo no se puede cerrar con el contador, no se puede sumar
-- por sede ni por área, y no se puede entregar a nadie.
--
-- QUÉ PROMETE ESTA MIGRACIÓN
--
--   1. Al marcar un periodo como pagado se guarda una copia intacta del
--      desglose de cada persona, tal como se calculó en ese momento.
--   2. Esa copia no se edita ni se borra nunca. El esquema lo impide.
--   3. Si un recálculo posterior ya no coincide, el sistema lo puede DECIR
--      (`fn_planilla_foto_diferencias`) en vez de cambiar la cifra en silencio.
--   4. La copia guarda dónde estaba la persona ese mes —sede y área— no dónde
--      está hoy. Si mañana la trasladan de AQP a Central, el costo de julio
--      sigue siendo de AQP.
--
-- QUÉ ASUME
--
--   · Que `fn_planilla_calcular` es la única fuente del cálculo. La foto no
--     recalcula nada por su cuenta: copia lo que esa función devolvió. Si la
--     fórmula está mal, la foto guarda el error — su trabajo es que el número
--     no cambie, no que sea correcto. Lo correcto lo fijan las pruebas 10 y 20.
--   · Que un periodo pagado se reabre solo por `fn_revertir_pago`, que exige
--     motivo (0066), y que reabrir NO borra la foto anterior.
--
-- POR QUÉ ASÍ, Y NO DE OTRA FORMA
--
--   · Versiones, no un booleano «vigente». Si el periodo se reabre y se vuelve
--     a pagar, la foto nueva es la versión 2 y la 1 se queda. La vigente es
--     siempre la de mayor número: es un dato derivado, no una marca que alguien
--     tenga que acordarse de apagar. Una marca que se puede olvidar de apagar
--     es un estado inválido esperando su turno.
--   · La foto se escribe DENTRO de `fn_periodo_pagado`, en la misma
--     transacción. Si la foto falla, el periodo no queda pagado. Un periodo
--     pagado sin foto sería justo el estado que esta migración existe para
--     hacer imposible.
--   · Se guarda el desglose en columnas Y la fila completa en `fila` jsonb. Las
--     columnas son para sumar (costos por sede, por área, por mes). El jsonb es
--     para reimprimir la boleta exactamente igual dentro de tres años, aunque
--     para entonces el cálculo haya cambiado de forma.
--   · `costo_total` = lo que recibe la persona + las provisiones. Es la cifra
--     que le cuesta a CAYLA, y es distinta de lo que se transfiere. El contador
--     necesita las dos, así que se guardan las dos.
--
-- LOS PERIODOS QUE YA ESTABAN PAGADOS
--
-- Al final se toma una foto retroactiva de los periodos que ya figuran como
-- pagados. Queda marcada con `origen = 'retroactivo'`, y eso hay que decirlo en
-- pantalla: es el número de HOY, no el del día en que se pagó. Si algo se movió
-- entre medias, esa foto ya nació con el desvío dentro. Es lo único honesto que
-- se puede hacer con lo que hay; de aquí en adelante todas serán 'pago'.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_planilla_foto_diferencias(uuid);
--   drop function if exists fn_planilla_congelar_pendientes();
--   drop function if exists fn_planilla_congelar(uuid, text, uuid);
--   drop view  if exists v_planilla_pagada;
--   drop table if exists planilla_pagada_detalle;   -- borra el histórico
--   -- y restaurar fn_periodo_pagado con el cuerpo de la 0095.
-- ============================================================================

-- ── La tabla ────────────────────────────────────────────────────────────────
create table if not exists planilla_pagada_detalle (
  periodo_id   uuid not null references periodos_planilla(id),
  persona_id   uuid not null references personas(id),
  version      int  not null check (version >= 1),

  congelada_at  timestamptz not null default now(),
  congelada_por uuid references personas(id),
  origen        text not null check (origen in ('pago', 'retroactivo')),

  -- Dónde estaba la persona ESE mes. Si la trasladan después, el costo del
  -- periodo no se muda con ella.
  nombre       text not null,
  sede_codigo  text not null,
  area_codigo  text,
  rango        text,
  salario_ref  numeric(12,2),

  horas_mes        numeric(10,2) not null default 0 check (horas_mes >= 0),
  dias_trabajados  int           not null default 0 check (dias_trabajados >= 0),

  pago_base            numeric(12,2) not null default 0,
  monto_feriados       numeric(12,2) not null default 0,
  monto_plus           numeric(12,2) not null default 0,
  asignacion_familiar  numeric(12,2) not null default 0,
  bonos                numeric(12,2) not null default 0,
  descuentos           numeric(12,2) not null default 0,
  total                numeric(12,2) not null,

  provision_gratificacion numeric(12,2) not null default 0,
  provision_cts           numeric(12,2) not null default 0,
  provision_vacaciones    numeric(12,2) not null default 0,
  provision_total         numeric(12,2) not null default 0,

  -- Lo que le cuesta a CAYLA: lo que recibe la persona más lo que se provisiona
  -- por ella. Generada, para que no pueda desalinearse de sus dos sumandos.
  costo_total numeric(12,2) generated always as (total + provision_total) stored,

  fila jsonb not null,

  primary key (periodo_id, persona_id, version),

  -- El desglose tiene que sumar el total. Si un día `fn_planilla_calcular`
  -- cambia de forma y deja de cuadrar, esto revienta al pagar —ruidosamente—
  -- en vez de guardar una foto que no se sostiene.
  constraint chk_foto_cuadra check (
    total = pago_base + monto_feriados + monto_plus
          + asignacion_familiar + bonos - descuentos
  )
);

comment on table planilla_pagada_detalle is
  'La foto del pago: el desglose por persona congelado en el momento de marcar el periodo como pagado. Append-only — no se edita ni se borra. La vigente de cada periodo es la de mayor version.';
comment on column planilla_pagada_detalle.origen is
  '''pago'' = tomada al marcar el periodo como pagado. ''retroactivo'' = reconstruida por la 0096 para periodos que ya figuraban pagados; es el número del día de la migración, no el del día del pago.';
comment on column planilla_pagada_detalle.costo_total is
  'Lo que le cuesta a CAYLA (total + provisiones). Distinto de `total`, que es lo que recibe la persona.';

create index if not exists idx_foto_periodo  on planilla_pagada_detalle(periodo_id, version desc);
create index if not exists idx_foto_persona  on planilla_pagada_detalle(persona_id, congelada_at desc);
create index if not exists idx_foto_sede     on planilla_pagada_detalle(sede_codigo);

-- ── Append-only, de verdad ──────────────────────────────────────────────────
-- No basta con no escribir un UPDATE: basta con que alguien lo escriba una vez.
create or replace function fn_trg_foto_es_inmutable()
returns trigger language plpgsql as $fn$
begin
  raise exception 'La foto de una planilla pagada no se modifica ni se borra. Si el pago estaba mal, reabre el periodo con Revertir pago (queda el motivo) y vuelve a pagarlo: se guardará una versión nueva y esta queda como histórico.';
end;
$fn$;

drop trigger if exists trg_foto_es_inmutable on planilla_pagada_detalle;
create trigger trg_foto_es_inmutable
  before update or delete on planilla_pagada_detalle
  for each row execute function fn_trg_foto_es_inmutable();

-- ── Quién la puede leer ─────────────────────────────────────────────────────
alter table planilla_pagada_detalle enable row level security;
revoke all on planilla_pagada_detalle from anon, public;
grant select on planilla_pagada_detalle to authenticated;

drop policy if exists foto_select_admin_lider on planilla_pagada_detalle;
create policy foto_select_admin_lider on planilla_pagada_detalle
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists foto_select_propia on planilla_pagada_detalle;
create policy foto_select_propia on planilla_pagada_detalle
  for select to authenticated using (persona_id = fn_persona_actual_id());
-- Escritura: NINGUNA política. Solo entra por las funciones de abajo.

-- ── La vigente de cada periodo ──────────────────────────────────────────────
drop view if exists v_planilla_pagada;
create view v_planilla_pagada with (security_invoker = true) as
select d.*
from planilla_pagada_detalle d
where d.version = (
  select max(x.version) from planilla_pagada_detalle x where x.periodo_id = d.periodo_id
);

comment on view v_planilla_pagada is
  'Solo la foto vigente de cada periodo (la de mayor version). Lo que hay que sumar para contabilidad.';

-- ── Tomar la foto ───────────────────────────────────────────────────────────
-- CONTRATO: asume que quien llama YA verificó la autorización. Es interna: no
-- se concede a `authenticated`. Sus dos únicas puertas son fn_periodo_pagado y
-- fn_planilla_congelar_pendientes, y las dos comprueban admin/líder primero.
create or replace function fn_planilla_congelar(p_periodo_id uuid, p_origen text, p_autor uuid)
returns int
language plpgsql security definer set search_path = public as $fn$
declare
  v_per record;
  v_calc jsonb;
  v_ver int;
  v_n int;
begin
  -- `for update` sobre el periodo: dos personas pulsando «Pagado» a la vez no
  -- pueden calcular ambas la versión 1 y chocar contra la llave primaria.
  select * into v_per from periodos_planilla where id = p_periodo_id for update;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_calc := fn_planilla_calcular(v_per.fecha_ini, v_per.fecha_fin, p_periodo_id);

  select coalesce(max(version), 0) + 1 into v_ver
  from planilla_pagada_detalle where periodo_id = p_periodo_id;

  insert into planilla_pagada_detalle (
    periodo_id, persona_id, version, congelada_por, origen,
    nombre, sede_codigo, area_codigo, rango, salario_ref,
    horas_mes, dias_trabajados,
    pago_base, monto_feriados, monto_plus, asignacion_familiar,
    bonos, descuentos, total,
    provision_gratificacion, provision_cts, provision_vacaciones, provision_total,
    fila
  )
  select
    p_periodo_id,
    (f->>'persona_id')::uuid,
    v_ver,
    p_autor,
    p_origen,
    f->>'nombre',
    f->>'sede',
    pe.funcion,
    f->>'rango',
    (f->>'salario_ref')::numeric,
    coalesce((f->>'horas_mes')::numeric, 0),
    coalesce((f->>'dias_trabajados')::int, 0),
    coalesce((f->>'pago_base')::numeric, 0),
    coalesce((f->>'monto_feriados')::numeric, 0),
    coalesce((f->>'monto_plus')::numeric, 0),
    coalesce((f->>'asignacion_familiar')::numeric, 0),
    coalesce((f->>'bonos')::numeric, 0),
    coalesce((f->>'descuentos')::numeric, 0),
    coalesce((f->>'total')::numeric, 0),
    coalesce((f->>'provision_gratificacion')::numeric, 0),
    coalesce((f->>'provision_cts')::numeric, 0),
    coalesce((f->>'provision_vacaciones')::numeric, 0),
    coalesce((f->>'provision_total')::numeric, 0),
    f
  from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
  left join personas pe on pe.id = (f->>'persona_id')::uuid;

  get diagnostics v_n = row_count;
  return v_n;
end;
$fn$;

revoke all on function fn_planilla_congelar(uuid, text, uuid) from public, anon, authenticated;
grant execute on function fn_planilla_congelar(uuid, text, uuid) to service_role;
drop function if exists fn_planilla_congelar(uuid, text);

insert into funciones_nunca_para_authenticated (funcion, motivo) values
  ('fn_planilla_congelar', 'Escribe la foto contable de un pago. Solo la llaman fn_periodo_pagado y fn_planilla_congelar_pendientes, que ya verificaron quién es.')
on conflict (funcion) do nothing;

-- ── Marcar como pagado ahora congela ────────────────────────────────────────
-- Misma transacción a propósito (Jim Gray): si la foto no se puede guardar, el
-- periodo NO queda pagado. Un pagado sin foto es el estado que no debe existir.
create or replace function fn_periodo_pagado(p_periodo_id uuid, p_pagado boolean)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_estado text; v_n int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede marcar un pago.';
  end if;

  if coalesce(p_pagado, false) is not true then
    raise exception 'Para reabrir un pago usa Revertir pago: la regla del sistema es que quede el motivo, quién lo hizo y cuándo. Reabrir levanta los candados que protegen los marcajes de ese periodo.';
  end if;

  select estado into v_estado from periodos_planilla where id = p_periodo_id for update;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Ese periodo ya está pagado. Su desglose quedó congelado; para cambiarlo hay que reabrirlo con Revertir pago.';
  end if;

  v_n := fn_planilla_congelar(p_periodo_id, 'pago', fn_persona_actual_id());

  update periodos_planilla
     set estado = 'pagado', pagado_at = now()
   where id = p_periodo_id;
end;
$fn$;
grant execute on function fn_periodo_pagado(uuid, boolean) to authenticated;
revoke execute on function fn_periodo_pagado(uuid, boolean) from public, anon;

-- ── ¿La foto sigue cuadrando con la realidad? ───────────────────────────────
-- No corrige nada. Solo dice qué se movió, para que lo decida una persona.
create or replace function fn_planilla_foto_diferencias(p_periodo_id uuid)
returns table (
  persona_id uuid,
  nombre text,
  total_foto numeric,
  total_ahora numeric,
  diferencia numeric
)
language plpgsql stable security definer set search_path = public as $fn$
declare v_per record; v_calc jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede revisar una planilla pagada.';
  end if;

  select * into v_per from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_calc := fn_planilla_calcular(v_per.fecha_ini, v_per.fecha_fin, p_periodo_id);

  return query
  with foto as (
    select v.persona_id, v.nombre, v.total
    from v_planilla_pagada v
    where v.periodo_id = p_periodo_id
  ),
  ahora as (
    select (f->>'persona_id')::uuid as persona_id,
           f->>'nombre'             as nombre,
           (f->>'total')::numeric   as total
    from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
  )
  select coalesce(fo.persona_id, ah.persona_id),
         coalesce(fo.nombre, ah.nombre),
         fo.total,
         ah.total,
         coalesce(ah.total, 0) - coalesce(fo.total, 0)
  from foto fo
  full outer join ahora ah on ah.persona_id = fo.persona_id
  -- Solo lo que NO cuadra: alguien que aparece ahora y no estaba, alguien que
  -- estaba y ya no aparece, o un total distinto.
  where fo.total is distinct from ah.total;
end;
$fn$;
grant execute on function fn_planilla_foto_diferencias(uuid) to authenticated;
revoke execute on function fn_planilla_foto_diferencias(uuid) from public, anon;

-- ── La red para lo que ya estaba pagado ─────────────────────────────────────
create or replace function fn_planilla_congelar_pendientes()
returns int language plpgsql security definer set search_path = public as $fn$
declare r record; v_total int := 0;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede tomar la foto de un pago.';
  end if;

  for r in
    select p.id from periodos_planilla p
    where p.estado = 'pagado'
      and not exists (select 1 from planilla_pagada_detalle d where d.periodo_id = p.id)
    order by p.fecha_ini
  loop
    v_total := v_total + fn_planilla_congelar(r.id, 'retroactivo', fn_persona_actual_id());
  end loop;

  return v_total;
end;
$fn$;
grant execute on function fn_planilla_congelar_pendientes() to authenticated;
revoke execute on function fn_planilla_congelar_pendientes() from public, anon;

-- ── La foto retroactiva de lo que ya estaba pagado ──────────────────────────
-- `fn_planilla_calcular` exige sesión de admin desde la 0090, y en el SQL Editor
-- no hay ninguna. Se presta la identidad de una cuenta admin SOLO dentro de esta
-- transacción (`set_config(..., true)` es local) y la foto queda marcada como
-- retroactiva y sin autor: nadie la tomó, la reconstruyó la migración.
do $mig$
declare v_admin uuid; r record; v_filas int := 0; v_periodos int := 0;
begin
  select pe.auth_user_id into v_admin
  from personas pe
  where pe.rol = 'admin' and pe.auth_user_id is not null and pe.estado = 'activo'
  order by pe.nombres, pe.apellidos limit 1;

  if v_admin is null then
    raise notice '0096 · No hay ninguna cuenta admin activa: la foto retroactiva no se tomó. Entrar a Dynamic como admin y llamar a fn_planilla_congelar_pendientes().';
    return;
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  for r in
    select p.id from periodos_planilla p
    where p.estado = 'pagado'
      and not exists (select 1 from planilla_pagada_detalle d where d.periodo_id = p.id)
    order by p.fecha_ini
  loop
    v_filas := v_filas + fn_planilla_congelar(r.id, 'retroactivo', null);
    v_periodos := v_periodos + 1;
  end loop;

  raise notice '0096 · Foto retroactiva tomada: % periodos, % personas.', v_periodos, v_filas;
end;
$mig$;

insert into migraciones_aplicadas (numero, nombre)
values (96, 'la_foto_del_pago')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
