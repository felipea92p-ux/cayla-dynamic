-- ============================================================================
-- 0394 — La firma GENERADA tiene que corresponder al nombre registrado
-- ----------------------------------------------------------------------------
-- PROMETE: que `fn_set_mi_firma` rechace una firma generada cuyo texto no se
--   pueda reconocer como el nombre de quien la guarda — para que no pase como
--   "firma" cualquier cadena de letras (p.ej. "jsdlaksj"). No hace falta que
--   sea el nombre completo: alcanza con el primer nombre completo, al menos un
--   apellido completo, y el resto (otro nombre) como inicial o completo —
--   exactamente lo que la pantalla ya sugiere como formato («Felipe M. Diaz»
--   para «Felipe Manuel Diaz Lopez»).
--
-- ASUME: `fn_set_mi_firma` tal como quedó en la 0393 — confirmado con
--   `donde-vive.sh fn_set_mi_firma` antes de escribir esto: es la última
--   versión, md5 local 240e266ee4732ddfecc029c3182c1ed2 (idéntico con y sin
--   comentarios). Pedir el md5 de PRODUCCIÓN queda para quien la pegue, justo
--   antes de pegarla.
--
-- POR QUÉ ACÁ Y NO SOLO EN LA PANTALLA. La pantalla (apps/web/lib/firma-generador.ts)
--   ya hace esta misma comprobación ANTES de generar la imagen, para avisar al
--   toque. Pero un aviso en pantalla es cosmético: quien llama al RPC directo
--   se lo salta entero. Esta firma la va a llevar un contrato de trabajo, así
--   que quien de verdad tiene que exigirlo es la función guardián — el mismo
--   criterio que ya viene de "un campo sensible se cambia por una función
--   guardián, nunca por confianza en quien llama" (CLAUDE.md).
--
-- POR QUÉ SOLO LA GENERADA, NO LA ESCANEADA. Un escaneo no tiene "texto": es
--   una foto de una firma manuscrita, y esta migración no le pide nada nuevo.
--   Por eso el candado es un parámetro NUEVO Y OPCIONAL (`p_texto_firma`,
--   default null) — cuando viene null (las pantallas de siempre: política
--   salarial, liquidaciones, documentación, contratos, ficha de personas,
--   todas suben un escaneo) el comportamiento no cambia ni un carácter.
--
-- DROP ANTES DE CREATE, A PROPÓSITO. `create or replace` no sirve para esto:
--   Postgres identifica una función por su lista de TIPOS de parámetros, y
--   `fn_set_mi_firma(text)` y `fn_set_mi_firma(text, text)` son dos funciones
--   DISTINTAS aunque la segunda tenga default. Sin el `drop`, quedarían las
--   dos vivas — y una llamada con un solo argumento sería AMBIGUA entre
--   "la de un parámetro" y "la de dos con el segundo por defecto", exactamente
--   el desastre de las dos `fn_vacaciones_por_vencer` de la 0297/0299 que este
--   mismo archivo ya cuenta: `function ... is not unique`, y esta vez sobre
--   una función que se llama todo el tiempo, no una que se abre una vez al
--   mes. El `drop` deja un solo nombre posible.
--
-- CÓMO SE REVIERTE: `drop function fn_set_mi_firma(text, text);` y volver a
--   crear la de un solo parámetro, tal como está en la 0393. `fn_firma_texto_coincide`
--   se puede dejar (no la usa nadie más) o borrarla con
--   `drop function fn_firma_texto_coincide(text, text, text);`.
-- ============================================================================

-- ── El criterio de coincidencia, aparte y probable por sí solo ──────────────
-- Reglas (las mismas que apps/web/lib/firma-generador.ts — si cambian acá,
-- cambian allá, y viceversa; no hay forma de compartir código entre SQL y
-- TypeScript, así que se mantienen ALINEADAS a mano):
--   1. Cada palabra del texto tiene que reconocerse como un nombre o apellido
--      real (completo) o como su INICIAL (una letra, con o sin punto).
--   2. El PRIMER nombre tiene que aparecer completo — no basta su inicial.
--   3. Al menos UN apellido tiene que aparecer completo.
--   4. Sin tildes ni mayúsculas: "Félipe" y "felipe" son la misma palabra.
-- Con eso, "Felipe M. Diaz" (de "Felipe Manuel Diaz Lopez") pasa, "M. Diaz"
-- no pasa (falta el primer nombre completo), "Felipe" solo no pasa (falta un
-- apellido), y "jsdlaksj" no pasa (no reconoce ninguna palabra).
create or replace function fn_firma_texto_coincide(p_texto text, p_nombres text, p_apellidos text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_texto          text[];
  v_nombres        text[];
  v_apellidos      text[];
  v_reales         text[];
  v_tok            text;
  v_limpio         text;
  v_tiene_apellido boolean := false;
begin
  v_texto     := string_to_array(nullif(trim(regexp_replace(translate(lower(coalesce(p_texto, '')), 'áéíóúüñ', 'aeiouun'), '\s+', ' ', 'g')), ''), ' ');
  v_nombres   := string_to_array(trim(regexp_replace(translate(lower(coalesce(p_nombres, '')), 'áéíóúüñ', 'aeiouun'), '\s+', ' ', 'g')), ' ');
  v_apellidos := string_to_array(trim(regexp_replace(translate(lower(coalesce(p_apellidos, '')), 'áéíóúüñ', 'aeiouun'), '\s+', ' ', 'g')), ' ');

  if v_texto is null then
    return false;
  end if;

  v_reales := v_nombres || v_apellidos;

  foreach v_tok in array v_texto loop
    v_limpio := regexp_replace(v_tok, '\.$', '');
    if v_limpio = '' then continue; end if;
    if length(v_limpio) = 1 then
      if not exists (select 1 from unnest(v_reales) r where left(r, 1) = v_limpio) then
        return false;
      end if;
    else
      if not (v_limpio = any(v_reales)) then
        return false;
      end if;
      if v_limpio = any(v_apellidos) then
        v_tiene_apellido := true;
      end if;
    end if;
  end loop;

  if not (v_nombres[1] = any(v_texto)) then
    return false;
  end if;

  if not v_tiene_apellido then
    return false;
  end if;

  return true;
end;
$$;
grant execute on function fn_firma_texto_coincide(text, text, text) to authenticated;
revoke execute on function fn_firma_texto_coincide(text, text, text) from public, anon;

-- ── El guardián ──────────────────────────────────────────────────────────────
drop function if exists fn_set_mi_firma(text);

create or replace function fn_set_mi_firma(p_dataurl text, p_texto_firma text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_yo uuid;
  v_nombres text;
  v_apellidos text;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  if p_dataurl is null then
    delete from firmas_escaneadas where persona_id = v_yo;
    return;
  end if;
  if p_dataurl !~ '^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$' then
    raise exception 'Formato inválido: la firma debe ser una imagen PNG o JPEG.';
  end if;
  if length(p_dataurl) > 400000 then
    raise exception 'La firma pesa demasiado (% KB, el máximo es 390 KB). Vuelve a generarla o escanearla más pequeña.',
      round(length(p_dataurl) / 1024.0);
  end if;

  -- Solo se exige cuando quien llama manda el texto: la firma GENERADA a
  -- partir de un nombre escrito. Un escaneo no tiene texto que comparar, y
  -- las pantallas de siempre no mandan este parámetro — para ellas, nada
  -- cambia.
  if p_texto_firma is not null then
    select nombres, apellidos into v_nombres, v_apellidos from personas where id = v_yo;
    if not fn_firma_texto_coincide(p_texto_firma, v_nombres, v_apellidos) then
      raise exception 'Esa firma no corresponde a tu nombre registrado (% %). Escríbela con tu nombre y tu apellido.',
        v_nombres, v_apellidos;
    end if;
  end if;

  insert into firmas_escaneadas (persona_id, imagen, actualizado_at)
  values (v_yo, p_dataurl, now())
  on conflict (persona_id) do update
    set imagen = excluded.imagen, actualizado_at = now();
end;
$$;
grant execute on function fn_set_mi_firma(text, text) to authenticated;
revoke execute on function fn_set_mi_firma(text, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (394, 'la_firma_generada_tiene_que_ser_tu_nombre')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
