-- ============================================================================
-- 0412 — El memo firmado se cierra sin entrega si la persona cesa
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Un tercer desenlace para un documento disciplinario YA FIRMADO, para cuando
-- la persona cesa antes de que se le pueda entregar: `fn_expediente_cerrar_sin_
-- entrega`, que solo actúa si la persona ya está `inactivo` y deja rastro
-- explícito en `observacion` (motivo, fecha, y la fecha de cese si existe).
--
-- ASUME: existe `expediente_disciplinario` (0056), `fn_expediente_puede_actuar`
-- (0058) y `personas.estado`/`personas.fecha_cese` (0086).
--
-- ── QUÉ ESTABA ROTO ──────────────────────────────────────────────────────────
--
-- «Firmados — por entregar» en la pantalla de Disciplina sale de un query
-- directo del cliente sobre `expediente_disciplinario` (sin filtrar por
-- `personas.estado`), y sus únicas acciones — subir cargo firmado, acta de
-- negativa, marcar entregado, cambiar firmante — asumen todas que la persona
-- SIGUE ahí para recibir el documento. Ninguna sirve cuando ya cesó: el
-- expediente se queda en `estado = 'firmado'` para siempre, sin ninguna acción
-- que lo resuelva.
--
-- `fn_expediente_anular` (0058) técnicamente lo saca de esa lista, pero
-- significa otra cosa: «este documento no debió emitirse». El de Paola SÍ era
-- válido — la tardanza ocurrió, la sanción correspondía, se firmó en regla —
-- solo que ya no hay a quién notificarle. Anularlo mentiría en el legajo.
--
-- ── POR QUÉ EL GUARDIÁN MIRA `personas.estado`, NO LA PANTALLA ───────────────
--
-- Si solo se ocultara a los cesados de la lista (sin esta función), el
-- expediente de Paola quedaría huérfano: invisible, sin cerrar, sin que nadie
-- vuelva a verlo. La función exige `estado <> 'activo'` porque es la única
-- condición que hace válido este cierre — mientras la persona siga activa, el
-- camino sigue siendo entregarle el documento, no cerrarlo.
--
-- ── CÓMO SE REVIERTE ───────────────────────────────────────────────────────
--
-- Soltando `fn_expediente_cerrar_sin_entrega` y devolviendo el check de
-- `estado` a sus cuatro valores originales. Un documento ya cerrado con esta
-- función puede recuperarse con `fn_expediente_anular` (no mira el estado
-- actual) si hiciera falta declararlo inválido en vez de sin entrega.
-- ============================================================================

-- El estado nuevo. Se reescribe el check entero: `add constraint` sobre una
-- columna que ya tiene uno deja los dos vivos y el viejo seguiría rechazando.
alter table expediente_disciplinario drop constraint if exists expediente_disciplinario_estado_check;
alter table expediente_disciplinario add constraint expediente_disciplinario_estado_check
  check (estado in ('borrador','firmado','entregado','anulado','cerrado_sin_entrega'));

-- ── Cerrar sin entrega: firmado → cerrado_sin_entrega (solo si la persona ya cesó) ─
create or replace function fn_expediente_cerrar_sin_entrega(p_id uuid, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  r expediente_disciplinario%rowtype;
  v_p personas%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'firmado' then
    raise exception 'Solo se cierra sin entrega un documento firmado (estado actual: %).', r.estado;
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then raise exception 'Sin permiso.'; end if;

  select * into v_p from personas where id = r.persona_id;
  if not found then raise exception 'La persona no existe.'; end if;
  -- EL GUARDIÁN DE FONDO: mientras la persona siga activa, cerrar sin entrega
  -- sería un atajo para no entregarle un documento que sí se le puede entregar.
  if v_p.estado = 'activo' then
    raise exception
      '% sigue activa: esta acción es solo para cuando la persona ya cesó y no '
      'se le puede entregar el documento. Usa «entregar sin papel» o sube el cargo firmado.',
      v_p.nombres;
  end if;

  update expediente_disciplinario
    set estado = 'cerrado_sin_entrega',
        observacion = trim(coalesce(observacion, '') || ' [CERRADO SIN ENTREGA ' || to_char(now(), 'YYYY-MM-DD')
          || ': la persona cesó' || coalesce(' el ' || to_char(v_p.fecha_cese, 'DD/MM/YYYY'), '')
          || coalesce('. ' || p_motivo, '') || ']')
    where id = p_id;
end;
$$;

grant execute on function fn_expediente_cerrar_sin_entrega(uuid, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (412, 'el_memo_firmado_se_cierra_sin_entrega_si_la_persona_cesa')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las dos deben decir true.
select
  (select pg_get_constraintdef(oid) ilike '%cerrado_sin_entrega%' from pg_constraint
    where conname = 'expediente_disciplinario_estado_check')
                                                          as el_estado_admite_el_cierre,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_cerrar_sin_entrega') = 1
                                                          as existe_una_sola_version;
