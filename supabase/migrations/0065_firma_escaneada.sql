-- ============================================================================
-- 0065 — Firma escaneada del firmante (para memos leves)
-- ----------------------------------------------------------------------------
-- Felipe (y quien firme) sube su firma escaneada UNA vez; el sistema la imprime
-- en los memos que ESA persona firma, solo en niveles leves (verbal / amonestación
-- / suspensión). Despido/imputación NO llevan firma escaneada (van con firma
-- digital certificada o manuscrita) — eso lo controla la pantalla del memo.
--
-- Se guarda como data-URL (data:image/png;base64,…) en la BASE, NO en el código
-- (activo sensible fuera del repositorio). Columna atrapada en el schema cache de
-- PostgREST → se LEE y ESCRIBE por RPC. Cada quien guarda solo la SUYA.
-- ============================================================================

alter table personas add column if not exists firma_base64 text;

-- Guardar MI propia firma (admin/líder — son los firmantes). Pasar null la borra.
create or replace function fn_set_mi_firma(p_dataurl text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not fn_es_admin_o_lider() then
    raise exception 'Solo un administrador o líder puede guardar su firma.';
  end if;
  if p_dataurl is not null and p_dataurl !~ '^data:image/(png|jpeg);base64,' then
    raise exception 'Formato inválido: la firma debe ser una imagen PNG o JPEG.';
  end if;
  update personas set firma_base64 = p_dataurl where id = fn_persona_actual_id();
  if not found then raise exception 'No se encontró tu persona.'; end if;
end;
$$;
grant execute on function fn_set_mi_firma(text) to authenticated;
revoke execute on function fn_set_mi_firma(text) from public, anon;

-- Leer la firma de un firmante (para imprimirla en su memo). Admin/líder pueden
-- leer la de cualquiera (gestionan todo); un supervisor lee para imprimir los
-- memos de su sede; cualquiera puede leer la propia. Fuera de eso, no se expone.
create or replace function fn_firma_persona(p_persona_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select firma_base64 from personas
  where id = p_persona_id
    and (fn_es_admin_o_lider()
         or id = fn_persona_actual_id()
         or fn_rol_actual() = 'supervisor_sede');
$$;
grant execute on function fn_firma_persona(uuid) to authenticated;
revoke execute on function fn_firma_persona(uuid) from public, anon;

notify pgrst, 'reload schema';
