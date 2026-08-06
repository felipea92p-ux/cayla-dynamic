-- ============================================================================
-- 0170 · El acta de descanso acepta la foto tal como sale del teléfono
-- ============================================================================
--
-- QUÉ PROMETE
--   `fn_subir_acta_descanso` acepta un acta fotografiada en HEIC/HEIF, el
--   formato en que un iPhone guarda sus fotos desde 2017. Todo lo demás de la
--   función queda igual: mismos permisos, mismo tope de peso, mismo upsert por
--   referencia.
--
-- QUÉ ASUME
--   Que el papel firmado se sube tal como se capturó. Nadie en una sede va a
--   convertir un archivo antes de subirlo, y pedírselo es trasladarle a la
--   persona un problema que es nuestro.
--
-- POR QUÉ SE ELIGIÓ ASÍ
--   El 2026-08-06 no se pudo subir ningún acta desde el Mac. La pantalla ofrecía
--   `accept="application/pdf,image/png,image/jpeg,image/webp"`, así que en el
--   diálogo de archivos las fotos .HEIC salían en gris: no se podían ni
--   seleccionar. El sistema no daba ningún error — simplemente no pasaba nada,
--   que es la peor forma de fallar. Y aunque se hubiera podido elegir, esta
--   función la habría rechazado con "Formato inválido".
--
--   Se descartó convertir la foto a JPEG en el navegador: Chrome no sabe
--   decodificar HEIC, así que la conversión habría funcionado en un navegador y
--   no en el otro — un sistema que se comporta distinto según con qué lo abras
--   es peor que uno que no convierte nunca.
--
--   Se descartó también mover estas actas a Storage (como sí lo están los
--   cargos disciplinarios y los comprobantes de educación) por ser un cambio de
--   otra naturaleza: acá solo se está quitando una puerta cerrada por descuido.
--   Queda anotado que el sistema guarda papeles firmados de dos maneras
--   distintas, y que una de las dos sobra.
--
--   HEIF va junto a HEIC porque son el mismo formato con dos nombres MIME:
--   según qué programa haya escrito el archivo, el navegador reporta uno u otro.
--   Aceptar solo uno deja fuera la mitad de los casos por una diferencia que
--   ninguna persona puede ver ni controlar.
--
-- CÓMO SE REVIERTE
--   Se vuelve a aplicar el bloque de `fn_subir_acta_descanso` de la migración
--   0073, que tiene la lista de formatos sin HEIC/HEIF.
--
-- Idempotente: es un `create or replace` y se puede pegar dos veces.
-- ============================================================================

create or replace function fn_subir_acta_descanso(
  p_referencia text,
  p_dataurl text,
  p_nombre text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_ref text := trim(p_referencia);
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede subir un acta.';
  end if;
  if v_ref is null or length(v_ref) < 3 then
    raise exception 'La referencia del acta es obligatoria.';
  end if;
  -- PDF o imagen: es un papel escaneado o fotografiado, nada más. HEIC/HEIF
  -- entran porque son lo que produce la cámara de un iPhone sin tocar nada.
  if p_dataurl is not null
     and p_dataurl !~ '^data:(application/pdf|image/(png|jpeg|webp|heic|heif));base64,' then
    raise exception 'Formato inválido: el acta debe ser un PDF o una imagen (PNG, JPEG, WEBP o HEIC).';
  end if;
  if p_dataurl is not null and length(p_dataurl) > 4194304 then
    raise exception 'El archivo pesa demasiado (máximo ~3 MB). Escanéalo en menor resolución o súbelo como PDF.';
  end if;

  insert into actas_descanso_sustitutorio (referencia, archivo_base64, archivo_nombre, subida_por)
  values (v_ref, p_dataurl, nullif(trim(p_nombre), ''), fn_persona_actual_id())
  on conflict (referencia) do update set
    archivo_base64 = excluded.archivo_base64,
    archivo_nombre = excluded.archivo_nombre,
    subida_por = excluded.subida_por,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

insert into migraciones_aplicadas (numero, nombre)
values (170, 'el_acta_acepta_la_foto_del_iphone')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
