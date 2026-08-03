-- ============================================================================
-- 0131 — Volver un memo firmado a borrador para corregir el firmante
-- ----------------------------------------------------------------------------
-- POR QUÉ: el memo imprime como suscriptor a quien figura en firmante_id (así el
-- papel nunca miente sobre quién firmó — decisión de la mig. 0074). El firmante
-- se elige AL FIRMAR, con validación de derechos. Pero una vez firmado ya no se
-- podía cambiar, y si se eligió por error a la persona equivocada (p. ej. la
-- encargada que solo lo tramitó, en vez de Gerencia), no había salida limpia.
--
-- QUÉ HACE: permite VOLVER A BORRADOR un documento firmado que TODAVÍA NO SE
-- ENTREGA. Al volver a borrador reaparece el selector de firmante ya existente,
-- se elige al correcto y se re-firma — reusando toda la validación de derechos
-- de fn_expediente_firmar, sin duplicar nada.
--
-- LÍMITE DELIBERADO (Lamport: el estado "final" no se reescribe):
--   · Solo desde 'firmado'. Un 'entregado' YA es un artefacto del mundo real
--     (se le dio a la persona) → ese no se reabre: se ANULA con motivo y se
--     regenera (fn_expediente_anular, que deja rastro en el legajo).
--   · Deja constancia en `observacion` de que se reabrió y quién firmaba antes.
--   · Al re-firmar se asigna un correlativo NUEVO (el numerador no reusa): el
--     número viejo queda como hueco, que es lo correcto para un acto rehecho.
--
-- Reversible: soltar la función.
-- ============================================================================
create or replace function fn_expediente_reabrir(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r expediente_disciplinario%rowtype;
  v_firmante_ant text;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;

  if r.estado <> 'firmado' then
    raise exception 'Solo se puede volver a borrador un documento firmado que aún no se entrega (estado actual: %). Un documento entregado se anula, no se reabre.', r.estado;
  end if;

  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso sobre un documento de nivel %.', r.nivel;
  end if;

  select nombres || ' ' || apellidos into v_firmante_ant
  from personas where id = r.firmante_id;

  update expediente_disciplinario
    set estado       = 'borrador',
        firmante_id  = null,
        firmado_at   = null,
        correlativo  = null,
        observacion  = trim(coalesce(observacion, '')
                       || ' [REABIERTO ' || to_char(now(), 'YYYY-MM-DD')
                       || ': vuelto a borrador para cambiar el firmante'
                       || coalesce(' (firmaba ' || v_firmante_ant || ')', '') || ']')
    where id = p_id;
end;
$$;

grant execute on function fn_expediente_reabrir(uuid) to authenticated;

notify pgrst, 'reload schema';
