-- ============================================================================
-- 0098 — Volver a pagar sin abrir la puerta
-- ----------------------------------------------------------------------------
-- EL PROBLEMA
--
-- Desde la 0096 el sistema DICE cuándo un periodo pagado dejó de cuadrar
-- (`fn_planilla_foto_diferencias`), pero no había forma de arreglarlo salvo la
-- ruta larga: reabrir con `fn_revertir_pago` y volver a marcar como pagado.
--
-- Esa ruta tiene un agujero real. Entre las dos operaciones el periodo queda en
-- estado `abierto`, y estar abierto LEVANTA todos los candados que protegen los
-- marcajes de ese periodo (0083, 0089, 0093, 0095). Si alguien cierra la
-- pestaña, se le cae la conexión o simplemente se distrae, el periodo se queda
-- abierto y desprotegido sin que nadie lo note — y ya no figura como pagado en
-- ninguna parte, así que tampoco aparece en Costos.
--
-- QUÉ PROMETE
--
-- `fn_repagar_periodo(periodo, motivo)`: en UNA sola operación, recalcula el
-- periodo con los datos de hoy, guarda una copia nueva y la deja como vigente.
-- El periodo NUNCA pasa por `abierto`: los candados no se levantan ni un
-- instante. O queda todo, o no queda nada.
--
-- Devuelve cuánto cambió: `{version, personas, neto_antes, neto_ahora,
-- diferencia}`, para que la pantalla pueda decir «se movió S/X» en vez de
-- «listo».
--
-- QUÉ ASUME
--
--   · Que el periodo YA está pagado. Marcar por primera vez sigue siendo
--     `fn_periodo_pagado`. Son dos actos distintos y se llaman distinto.
--   · Que el motivo es obligatorio, igual que en `fn_revertir_pago` (0066).
--     Volver a pagar cambia una cifra que ya se entregó: tiene que quedar por
--     qué, quién y cuándo.
--   · Que reabrir de verdad —para tocar marcajes— sigue siendo
--     `fn_revertir_pago`. Esta función NO la reemplaza: la usa quien solo
--     necesita que la foto vuelva a cuadrar con lo que ya está corregido.
--
-- POR QUÉ ASÍ
--
--   · El rastro va a `reversas_pago`, la tabla que ya existe para esto, con una
--     columna `tipo` nueva que distingue las dos cosas: `reapertura` (el
--     periodo se abrió) y `repago` (nunca se abrió, solo se recalculó). Sin esa
--     columna las dos quedarían indistinguibles en la auditoría, y no son lo
--     mismo: una levantó los candados y la otra no.
--   · Las filas que ya existen quedan como `reapertura`, que es lo que
--     efectivamente fueron.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_repagar_periodo(uuid, text);
--   alter table reversas_pago drop column if exists tipo;
-- ============================================================================

alter table reversas_pago add column if not exists tipo text not null default 'reapertura';

alter table reversas_pago drop constraint if exists chk_reversa_tipo;
alter table reversas_pago add constraint chk_reversa_tipo
  check (tipo in ('reapertura', 'repago'));

comment on column reversas_pago.tipo is
  '''reapertura'' = el periodo volvió a estado abierto y sus candados se levantaron (fn_revertir_pago). ''repago'' = nunca se abrió, solo se recalculó la foto (fn_repagar_periodo, 0098). No son lo mismo y la auditoría tiene que poder distinguirlas.';

-- ── Recalcular y volver a pagar, sin pasar por abierto ──────────────────────
create or replace function fn_repagar_periodo(p_periodo_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare
  v_estado text;
  v_pagado_at timestamptz;
  v_antes numeric;
  v_ahora numeric;
  v_ver int;
  v_n int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede volver a pagar un periodo.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'El motivo es obligatorio (mínimo 4 caracteres): volver a pagar cambia una cifra que ya se entregó.';
  end if;

  select estado, pagado_at into v_estado, v_pagado_at
  from periodos_planilla where id = p_periodo_id for update;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado <> 'pagado' then
    raise exception 'Ese periodo no está pagado (estado actual: %). Para marcarlo por primera vez usa el botón de Planilla.', v_estado;
  end if;

  -- El antes se lee ANTES de congelar: después, la vigente ya sería la nueva.
  select coalesce(sum(total), 0) into v_antes
  from v_planilla_pagada where periodo_id = p_periodo_id;

  insert into reversas_pago (periodo_id, revertido_por, motivo, pagado_at_previo, tipo)
  values (p_periodo_id, fn_persona_actual_id(), trim(p_motivo), v_pagado_at, 'repago');

  v_n := fn_planilla_congelar(p_periodo_id, 'pago', fn_persona_actual_id());

  -- El estado NO cambia: sigue 'pagado' de principio a fin. Solo se actualiza
  -- la fecha, que ahora es la de este pago.
  update periodos_planilla set pagado_at = now() where id = p_periodo_id;

  select coalesce(sum(total), 0), max(version) into v_ahora, v_ver
  from v_planilla_pagada where periodo_id = p_periodo_id;

  return jsonb_build_object(
    'version',     v_ver,
    'personas',    v_n,
    'neto_antes',  round(v_antes, 2),
    'neto_ahora',  round(v_ahora, 2),
    'diferencia',  round(v_ahora - v_antes, 2)
  );
end;
$fn$;

grant execute on function fn_repagar_periodo(uuid, text) to authenticated;
revoke execute on function fn_repagar_periodo(uuid, text) from public, anon;

comment on function fn_repagar_periodo(uuid, text) is
  'Recalcula un periodo YA pagado y guarda una copia nueva, sin que el periodo pase por estado abierto — los candados de sus marcajes no se levantan en ningún momento. Exige motivo y deja rastro en reversas_pago con tipo = repago.';

insert into migraciones_aplicadas (numero, nombre)
values (98, 'volver_a_pagar_sin_abrir_la_puerta')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
