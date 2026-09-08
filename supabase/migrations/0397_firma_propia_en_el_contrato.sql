-- ============================================================================
-- 0397 — La colaboradora también firma su propio contrato
-- ============================================================================
--
-- QUÉ PROMETE
--   Cualquier persona con ficha puede generar y guardar SU PROPIA firma
--   (`fn_set_mi_firma`, con sus tres métodos desde la 0395) — no solo
--   admin/líder_do, que es a quien esa función servía hasta hoy. Y cualquiera
--   puede leer la firma de LA EMPRESA (`fn_firma_empresa`, nueva), para poder
--   estampar las dos firmas de un contrato al mirarlo desde su propio perfil
--   (/mio/contrato), no solo desde el panel de administración.
--
-- QUÉ ASUME
--   Que la firma de la empresa no es un dato reservado: ya está impresa en el
--   papel físico que cada colaboradora recibe de su contrato — mostrarla en
--   pantalla no revela nada que el papel no muestre. Lo que sí sigue cerrado,
--   y esta migración no lo toca, es ESTAMPARLA en un documento ajeno:
--   `fn_firma_empresa()` no recibe ningún `persona_id`, solo devuelve la de
--   quien esté configurada en `configuracion.firmante_empresa` (0147) — nadie
--   puede pedir "la firma de fulano" con esta función.
--
-- POR QUÉ ASÍ
--   `fn_set_mi_firma` nació (0065/0076) restringida a admin/líder_do porque
--   hasta hoy solo ellos firmaban documentos DE LA EMPRESA: memos, contratos
--   como firmante, política salarial. La función siempre escribe sobre la
--   PROPIA fila (`fn_persona_actual_id()`, nunca un parámetro), así que abrir
--   el guard a cualquier rol no le da a nadie acceso a la firma de otra
--   persona — el único cambio es que ahora también sirve para que una
--   colaboradora o practicante firme SU contrato de trabajo, una necesidad
--   que no existía cuando se escribió esa restricción.
--
-- CÓMO SE REVIERTE
--   -- Cuerpo de la 0395, con el guard de admin/líder de vuelta:
--   create or replace function fn_set_mi_firma(p_dataurl text, p_tipo text default 'imagen', p_estilo text default null)
--   returns void language plpgsql security definer set search_path = public as $$
--   declare v_yo uuid; v_estilo text;
--   begin
--     if not coalesce(fn_es_admin_o_lider(), false) then
--       raise exception 'Solo un administrador o líder puede guardar su firma.';
--     end if;
--     v_yo := fn_persona_actual_id();
--     ... (resto igual, ver 0395)
--   end; $$;
--   drop function if exists fn_firma_empresa();
--
-- md5 de partida (LOCAL) de fn_set_mi_firma, la que esta migración reemplaza:
-- 240e266ee4732ddfecc029c3182c1ed2 — confirmar contra producción con
-- donde-vive.sh antes de pegar; si no coincide, PARAR (ver protocolo en
-- CLAUDE.md).
-- ============================================================================

-- ── Cualquiera firma lo suyo, no solo admin/líder ────────────────────────────
-- Mismo cuerpo que la 0395, sin el `if not coalesce(fn_es_admin_o_lider()...)`
-- del principio. Todo lo demás —validaciones de formato, peso, estilo— sigue
-- igual: lo único que cambia es QUIÉN puede llamarla, nunca SOBRE QUÉ fila
-- escribe.
create or replace function fn_set_mi_firma(p_dataurl text, p_tipo text default 'imagen', p_estilo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_yo uuid; v_estilo text;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  if p_dataurl is null then
    delete from firmas_escaneadas where persona_id = v_yo;
    return;
  end if;
  if p_tipo not in ('imagen', 'dibujo', 'tipografica') then
    raise exception 'Método de firma inválido: %.', p_tipo;
  end if;
  v_estilo := case when p_tipo = 'tipografica' then p_estilo else null end;
  if p_tipo = 'tipografica' and (v_estilo is null or v_estilo not in ('elegante', 'a_mano', 'clasica')) then
    raise exception 'Elige un estilo de firma válido.';
  end if;
  if p_dataurl !~ '^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$' then
    raise exception 'Formato inválido: la firma debe ser una imagen PNG o JPEG.';
  end if;
  if length(p_dataurl) > 400000 then
    raise exception 'La firma pesa demasiado (% KB, el máximo es 390 KB). Vuelve a escanearla más pequeña.',
      round(length(p_dataurl) / 1024.0);
  end if;

  insert into firmas_escaneadas (persona_id, imagen, tipo, estilo, actualizado_at)
  values (v_yo, p_dataurl, p_tipo, v_estilo, now())
  on conflict (persona_id) do update
    set imagen = excluded.imagen, tipo = excluded.tipo, estilo = excluded.estilo, actualizado_at = now();
end;
$$;
grant execute on function fn_set_mi_firma(text, text, text) to authenticated;
revoke execute on function fn_set_mi_firma(text, text, text) from public, anon;

-- ── La firma de la empresa, para estampar en cualquier documento que la lleve ─
-- `fn_mi_firma()` (0076) solo sirve para "mi propia firma": el panel de admin
-- la usa para el firmante de la empresa porque ahí quien mira ES esa persona.
-- En /mio/contrato quien mira es la colaboradora, nunca la firmante — por eso
-- hace falta una función aparte que no dependa de quién pregunta.
create or replace function fn_firma_empresa()
returns text
language sql stable security definer set search_path = public as $$
  select f.imagen
    from configuracion c
    join firmas_escaneadas f on f.persona_id = (c.valor ->> 'persona_id')::uuid
   where c.clave = 'firmante_empresa';
$$;
grant execute on function fn_firma_empresa() to authenticated;
revoke execute on function fn_firma_empresa() from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (397, 'firma_propia_en_el_contrato')
on conflict (numero) do nothing;
