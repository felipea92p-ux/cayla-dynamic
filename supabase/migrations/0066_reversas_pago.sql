-- ============================================================================
-- 0066 — Rastro de reaperturas de pago (red de seguridad)
-- ----------------------------------------------------------------------------
-- Reabrir un periodo ya pagado YA se podía (fn_periodo_pagado(id, false)), pero
-- no dejaba rastro. Reabrir toca DINERO: debe quedar QUIÉN lo reabrió, CUÁNDO y
-- POR QUÉ. Esta migración agrega ese registro y una función que exige el motivo.
--
-- No cambia cómo se PAGA (fn_periodo_pagado sigue igual). Solo agrega la vía
-- auditada de REABRIR. Reversible: soltar la tabla y la función.
-- ============================================================================

create table if not exists reversas_pago (
  id uuid primary key default gen_random_uuid(),
  periodo_id uuid not null references periodos_planilla(id) on delete cascade,
  revertido_por uuid references personas(id),
  revertido_at timestamptz not null default now(),
  motivo text not null,
  pagado_at_previo timestamptz
);
create index if not exists idx_reversas_periodo on reversas_pago(periodo_id, revertido_at desc);

alter table reversas_pago enable row level security;
drop policy if exists reversas_select_admin_lider on reversas_pago;
create policy reversas_select_admin_lider on reversas_pago
  for select using (fn_es_admin_o_lider());

-- Reabrir un pago DEJANDO RASTRO. Exige motivo. Solo admin/líder. Solo si está pagado.
create or replace function fn_revertir_pago(p_periodo_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare v_estado text; v_pagado_at timestamptz;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede revertir un pago.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'El motivo de la reapertura es obligatorio (mínimo 4 caracteres).';
  end if;
  select estado, pagado_at into v_estado, v_pagado_at from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado <> 'pagado' then
    raise exception 'Ese periodo no está pagado (estado actual: %).', v_estado;
  end if;
  insert into reversas_pago (periodo_id, revertido_por, motivo, pagado_at_previo)
    values (p_periodo_id, fn_persona_actual_id(), trim(p_motivo), v_pagado_at);
  update periodos_planilla set estado = 'abierto', pagado_at = null where id = p_periodo_id;
end;
$$;
grant execute on function fn_revertir_pago(uuid, text) to authenticated;
revoke execute on function fn_revertir_pago(uuid, text) from public, anon;

notify pgrst, 'reload schema';
