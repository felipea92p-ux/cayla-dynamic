-- ============================================================================
-- 0058_expediente_funciones.sql — Crear / firmar / entregar / anular documentos
-- ============================================================================
-- PROMETE: toda escritura al legajo (0056) pasa por aquí, con permiso validado y
--   la máquina de estados respetada: borrador → firmado → entregado (o → anulado).
--   El correlativo se asigna al FIRMAR (no antes), así no se queman números.
-- ASUME: expediente_disciplinario y fn_expediente_correlativo (0056); helpers RLS.
--
-- Permisos (decisión de Felipe): la encargada de sede firma solo Nivel 1-2
--   (verbal/amonestación) de SU sede; suspensión/imputación/despido, solo admin/DO.
-- Blindaje: Nivel 4 (imputación/despido) NO admite entrega por correo — físico o
--   notarial, aunque el correo esté pactado en el contrato.
--
-- Esta migración es la CAPA DE ESTADO. La detección automática (qué nivel toca y
-- rellenar los hechos desde Dynamic, con non bis in idem) va en 0059, y llama a
-- fn_expediente_crear_borrador con los valores ya calculados.

-- ── Código de documento T-01…/F-01…/R-01… según (tipo, nivel) ────────────────
create or replace function fn_expediente_doc_code(p_tipo text, p_nivel text)
returns text language sql immutable as $$
  select case p_tipo
    when 'tardanza' then case p_nivel
      when 'amonestacion' then 'T-01' when 'suspension' then 'T-02'
      when 'imputacion' then 'T-03' when 'despido' then 'T-04' else 'T-00' end
    when 'falta' then case p_nivel
      when 'verbal' then 'F-01' when 'amonestacion' then 'F-02' when 'suspension' then 'F-03'
      when 'imputacion' then 'F-04' when 'despido' then 'F-05' else 'F-00' end
    else case p_nivel
      when 'verbal' then 'R-01' when 'amonestacion' then 'R-02' when 'suspension' then 'R-03'
      when 'imputacion' then 'R-04' when 'despido' then 'R-05' else 'R-00' end
  end;
$$;

-- ── ¿Puede el usuario actual actuar sobre un doc de este nivel para esta persona? ─
create or replace function fn_expediente_puede_actuar(p_persona_id uuid, p_nivel text)
returns boolean language sql stable security definer set search_path = public as $$
  select fn_es_admin_o_lider()
      or (fn_rol_actual() = 'supervisor_sede'
          and p_nivel in ('verbal','amonestacion')
          and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona());
$$;

-- ── Crear un borrador ────────────────────────────────────────────────────────
create or replace function fn_expediente_crear_borrador(
  p_persona_id uuid, p_tipo_causal text, p_nivel text,
  p_hechos jsonb default '[]'::jsonb,
  p_periodo_desde date default null, p_periodo_hasta date default null,
  p_doc_previo_id uuid default null,
  p_suspension_dias int default null, p_suspension_desde date default null, p_suspension_hasta date default null,
  p_observacion text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_p personas%rowtype;
begin
  if not fn_expediente_puede_actuar(p_persona_id, p_nivel) then
    raise exception 'Sin permiso para generar un documento de nivel % para esta persona.', p_nivel;
  end if;
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;
  if v_p.estado <> 'activo' or v_p.en_planilla = false or v_p.sueldo_fijo = true then
    raise exception 'A esta persona no se le mide disciplina (inactiva, fuera de planilla o sueldo fijo).';
  end if;
  insert into expediente_disciplinario (
    persona_id, tipo_causal, nivel, estado, hechos,
    periodo_desde, periodo_hasta, doc_previo_id,
    suspension_dias, suspension_desde, suspension_hasta, observacion, creado_por)
  values (
    p_persona_id, p_tipo_causal, p_nivel, 'borrador', coalesce(p_hechos, '[]'::jsonb),
    p_periodo_desde, p_periodo_hasta, p_doc_previo_id,
    p_suspension_dias, p_suspension_desde, p_suspension_hasta, p_observacion, fn_persona_actual_id())
  returning id into v_id;
  return v_id;
end;
$$;

-- ── Firmar: borrador → firmado (asigna correlativo aquí, no antes) ────────────
create or replace function fn_expediente_firmar(p_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype; v_corr text;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede firmar un borrador (estado actual: %).', r.estado;
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso para firmar un documento de nivel %.', r.nivel;
  end if;
  v_corr := fn_expediente_correlativo(fn_expediente_doc_code(r.tipo_causal, r.nivel));
  update expediente_disciplinario
    set estado = 'firmado', firmante_id = fn_persona_actual_id(), firmado_at = now(), correlativo = v_corr
    where id = p_id;
  return v_corr;
end;
$$;

-- ── Entregar: firmado → entregado (con blindaje de Nivel 4) ───────────────────
create or replace function fn_expediente_entregar(p_id uuid, p_medio text, p_fecha timestamptz default now())
returns void language plpgsql security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'firmado' then
    raise exception 'Solo se entrega un documento firmado (estado actual: %).', r.estado;
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then raise exception 'Sin permiso.'; end if;
  if p_medio not in ('fisico','correo','notarial') then raise exception 'Medio de entrega inválido.'; end if;
  if r.nivel in ('imputacion','despido') and p_medio = 'correo' then
    raise exception 'Nivel 4 (imputación/despido) no admite entrega por correo: usa físico o notarial.';
  end if;
  update expediente_disciplinario
    set estado = 'entregado', medio_entrega = p_medio, entregado_at = p_fecha
    where id = p_id;
end;
$$;

-- ── Anular: cualquier estado → anulado (solo admin/DO) ───────────────────────
create or replace function fn_expediente_anular(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not fn_es_admin_o_lider() then raise exception 'Solo admin/líder DO puede anular un documento.'; end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then raise exception 'Indica el motivo de la anulación.'; end if;
  if not exists (select 1 from expediente_disciplinario where id = p_id) then
    raise exception 'El documento no existe.';
  end if;
  update expediente_disciplinario
    set estado = 'anulado',
        observacion = trim(coalesce(observacion, '') || ' [ANULADO ' || to_char(now(), 'YYYY-MM-DD') || ': ' || p_motivo || ']')
    where id = p_id;
end;
$$;

grant execute on function fn_expediente_crear_borrador(uuid,text,text,jsonb,date,date,uuid,int,date,date,text) to authenticated;
grant execute on function fn_expediente_firmar(uuid) to authenticated;
grant execute on function fn_expediente_entregar(uuid,text,timestamptz) to authenticated;
grant execute on function fn_expediente_anular(uuid,text) to authenticated;
-- fn_expediente_doc_code / fn_expediente_puede_actuar: solo uso interno, no se otorgan.
