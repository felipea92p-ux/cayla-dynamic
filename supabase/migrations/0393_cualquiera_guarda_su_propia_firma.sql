-- ============================================================================
-- 0393 — Cualquier persona guarda su propia firma, no solo admin/líder
-- ----------------------------------------------------------------------------
-- PROMETE: que `fn_set_mi_firma` deje de exigir `fn_es_admin_o_lider()` para
--   guardar la propia firma. Sigue exigiendo tener una fila en `personas`
--   (`fn_persona_actual_id()` no nulo) — eso ya bastaba para dejar fuera a la
--   TERMINAL de cada sede, que se autentica pero no tiene fila. Nada más
--   cambia: mismo nombre, mismos parámetros, misma tabla, mismos límites de
--   formato y peso.
--
-- ASUME: `firmas_escaneadas` y `fn_set_mi_firma`/`fn_mi_firma` tal como quedaron
--   en la 0076 — confirmado con `donde-vive.sh fn_set_mi_firma` ANTES de escribir
--   esta migración: es la última versión, md5 local 240e266ee4732ddfecc029c3182c1ed2
--   (idéntico con y sin comentarios). Pedir el md5 de PRODUCCIÓN queda para
--   quien la pegue, justo antes de pegarla — puede haberse movido desde que
--   se escribió esto.
--
-- POR QUÉ. La restricción nació en la 0065: hasta ahora "mi firma" solo servía
--   para firmar documentos EN NOMBRE DE LA EMPRESA (memos leves, el
--   `firmante_empresa` que se estampa en un contrato) — y solo admin/líder
--   pueden ser esos firmantes. Ahora cada colaboradora necesita generar SU
--   PROPIA firma para estamparla en SU PROPIO contrato de trabajo, y esa
--   persona casi nunca es admin ni líder.
--
--   No hace falta tabla ni función nueva. `fn_set_mi_firma` ya solo toca la
--   fila de `fn_persona_actual_id()` — nunca la de otra persona — así que
--   quitarle el candado de rol no abre ninguna puerta que la forma misma de
--   la función no tuviera ya cerrada: sigue siendo "guarda LA MÍA", nunca
--   "guarda la de quien yo diga". Y `fn_mi_firma()` (la lectura) nunca tuvo
--   esa restricción — con esto lectura y escritura quedan simétricas, que es
--   lo que ya deberían haber sido.
--
--   El nombre de la tabla («firmas_escaneadas») queda desactualizado: ahora
--   también guarda firmas GENERADAS a partir de un nombre escrito en letra
--   cursiva (ver apps/web/lib/firma-generador.ts), no solo escaneos de una
--   firma manuscrita. Pero para la base es solo una imagen PNG en los dos
--   casos — ninguna regla de esta migración distingue el origen — así que
--   renombrar la tabla no cambiaría ningún comportamiento; se deja así y se
--   deja escrito acá el porqué, en vez de mudar datos por estética.
--
--   Esta migración SOLO habilita guardar y leer la firma propia. No cambia
--   ninguna pantalla ni ningún documento generado: el contrato de cada
--   colaboradora todavía no imprime esta firma en ningún lado — eso es
--   trabajo de interfaz aparte, a propósito, para cuando exista el módulo
--   de "mis datos" del panel personal.
--
-- CÓMO SE REVIERTE: reponer, al principio del cuerpo, el candado de la 0076:
--   `if not coalesce(fn_es_admin_o_lider(), false) then raise exception
--   'Solo un administrador o líder puede guardar su firma.'; end if;`
-- ============================================================================

create or replace function fn_set_mi_firma(p_dataurl text)
returns void language plpgsql security definer set search_path = public as $$
declare v_yo uuid;
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

  insert into firmas_escaneadas (persona_id, imagen, actualizado_at)
  values (v_yo, p_dataurl, now())
  on conflict (persona_id) do update
    set imagen = excluded.imagen, actualizado_at = now();
end;
$$;
grant execute on function fn_set_mi_firma(text) to authenticated;
revoke execute on function fn_set_mi_firma(text) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (393, 'cualquiera_guarda_su_propia_firma')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
