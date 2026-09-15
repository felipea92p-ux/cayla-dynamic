-- ============================================================================
-- 0456 — Republicar sin cambios de contenido no crea versión ni reinicia
-- constancias
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que "Publicar" y "Volver a publicar" dejen de ser, en los hechos, el mismo
--   botón con dos etiquetas: si el documento que se publicaría HOY dice
--   exactamente lo mismo que la versión vigente, se devuelve esa misma
--   versión — sin insertar una fila nueva y sin reiniciar las constancias de
--   las ~22 personas obligadas.
--
-- QUÉ ASUME
--
--   · La 0141 congela `politica_salarial.documento` como el JSON completo que
--     arma `construirDocumento()` (apps/web/lib/politica-salarial.ts). Toda
--     versión publicada desde que ese formato existe empieza con `{`.
--   · `fecha` es el único campo de ese JSON que cambia todos los días sin que
--     el contenido cambie: es la fecha de HOY, calculada en el navegador cada
--     vez que se arma el documento en vivo.
--
-- EL DEFECTO QUE CORRIGE, Y CÓMO SE MANIFESTÓ
--
--   `fn_publicar_politica_salarial` (0141) decide si crear versión nueva
--   comparando el TEXTO CRUDO: `documento = p_documento`. Como ese texto
--   incluye la fecha de hoy, dos publicaciones en días distintos nunca
--   coinciden, aunque el resto del documento sea idéntico — así que casi
--   cualquier clic en "Volver a publicar" terminaba creando una versión
--   nueva y reiniciando las constancias de todo el equipo sin avisar.
--
--   Ya pasó: `docs/estado.md` registra el incidente como "v3 quemada", y
--   anota el arreglo pendiente ("hash del TEXTO, rechazo de publicar versión
--   idéntica") sin implementar hasta esta migración.
--
--   El frontend YA calcula esto bien para decidir la ETIQUETA del botón
--   (`documentoTieneCambios`, que compara todo menos `fecha`) — el defecto
--   es que esa comparación nunca llegaba al servidor, que es quien de verdad
--   decide si inserta una fila.
--
-- POR QUÉ SE COMPARA SOLO CONTRA LA ÚLTIMA VERSIÓN, Y NO CONTRA CUALQUIERA
--
--   La 0141 buscaba coincidencia en TODA la tabla (`order by version desc
--   limit 1` sobre un `where` sin filtrar por ser la última fila). Eso puede
--   devolver un número de versión que ya no es el vigente si el contenido
--   volviera a coincidir con una versión vieja — un caso que no debería
--   poder pasar en la práctica, pero que además contradice la premisa de que
--   "vigente" es siempre `max(version)`. Comparar solo contra la última fila
--   es más simple y no tiene ese borde.
--
-- POR QUÉ CAMBIA EL TIPO DE RETORNO
--
--   Antes devolvía solo el número de versión, y la pantalla no podía saber
--   si acababa de crear una versión nueva o si le devolvieron la vigente sin
--   tocar nada. Ahora devuelve `{version, nueva}` para que el aviso que ve
--   quien publica diga la verdad: "no había cambios, sigue la versión N" o
--   "se publicó la versión N nueva, pide constancias otra vez".
--
-- QUÉ NO CAMBIA
--
--   Si el `huella_cuadro` es igual pero el documento guardado no es JSON
--   (una versión publicada antes de que existiera ese formato), no hay forma
--   de comparar contenido sin fecha: se trata como distinta y se publica
--   igual, que es el comportamiento de hoy. No se toca ninguna versión ya
--   publicada.
--
-- CÓMO SE REVIERTE
--   drop function fn_publicar_politica_salarial(text, text);
--   Y volver a aplicar el bloque de fn_publicar_politica_salarial de la 0141
--   (returns int, comparación por texto crudo).
-- ============================================================================

drop function if exists fn_publicar_politica_salarial(text, text);

create or replace function fn_publicar_politica_salarial(
  p_documento text,
  p_notas     text default null
)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_yo               uuid;
  v_version          int;
  v_huella           text;
  v_ultimo           politica_salarial%rowtype;
  v_mismo_contenido  boolean := false;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede publicar la politica salarial.';
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien publica, asi que no puedo auditarlo. Inicia sesion con tu usuario.';
  end if;

  if p_documento is null or btrim(p_documento) = '' then
    raise exception 'No se puede publicar una politica vacia.';
  end if;

  v_huella := md5(fn_cuadro_categorias()::text);

  select * into v_ultimo from politica_salarial order by version desc limit 1;

  -- ¿Dice lo mismo que la version vigente? Se compara el CONTENIDO (el
  -- documento sin la fecha de hoy), no el texto crudo -- ver "EL DEFECTO QUE
  -- CORRIGE" arriba.
  if v_ultimo.version is not null
     and v_ultimo.huella_cuadro = v_huella
     and v_ultimo.documento is not null
     and btrim(v_ultimo.documento) like '{%' then
    begin
      v_mismo_contenido := (p_documento::jsonb - 'fecha') = (v_ultimo.documento::jsonb - 'fecha');
    exception when others then
      -- p_documento no es JSON valido (no deberia pasar: lo arma
      -- documentoAJson) o el guardado no lo es (version pre-JSON). No se
      -- puede comparar por contenido: se trata como distinta.
      v_mismo_contenido := false;
    end;
  end if;

  if v_mismo_contenido then
    return jsonb_build_object('version', v_ultimo.version, 'nueva', false);
  end if;

  select coalesce(max(version), 0) + 1 into v_version from politica_salarial;

  insert into politica_salarial (version, documento, huella_cuadro, notas, publicada_por)
  values (v_version, p_documento, v_huella, nullif(btrim(coalesce(p_notas,'')), ''), v_yo);

  return jsonb_build_object('version', v_version, 'nueva', true);
end;
$fn$;

grant  execute on function fn_publicar_politica_salarial(text, text) to authenticated;
revoke execute on function fn_publicar_politica_salarial(text, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (456, 'republicar_sin_cambios_no_crea_version')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

do $mig$
begin
  raise notice '0456 · fn_publicar_politica_salarial ahora devuelve {version, nueva}';
  raise notice '0456 · republicar sin cambios de contenido ya no crea version ni reinicia constancias';
end $mig$;
