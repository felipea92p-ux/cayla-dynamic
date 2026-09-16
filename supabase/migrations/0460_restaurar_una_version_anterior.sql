-- ============================================================================
-- 0460_restaurar_una_version_anterior.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que publicar una versión con un error no deje a DO sin salida. Hoy no
--   existe forma de volver a la anterior: republicar su mismo texto no la
--   vuelve vigente, porque `fn_publicar_documento` deduplica por contenido y
--   devuelve el número de la fila que ya existe con ese texto —el viejo—, sin
--   crear una fila nueva que sea la de mayor `version`. Esta migración agrega
--   `fn_restaurar_documento(p_documento_id)`: toma una versión histórica y la
--   vuelve a publicar como versión nueva, sin pasar por esa deduplicación.
--
-- QUÉ ASUME
--   Esta migración NO reescribe `fn_publicar_documento` ni `documentos_institucionales`
--   — no hace falta un md5 de partida de ninguna de las dos. Lo que sí asume
--   es su COMPORTAMIENTO vigente, confirmado con `donde-vive.sh` el
--   2026-09-15: la última migración que toca `fn_publicar_documento` es la
--   0265, y su md5 local es 2c6b7f9507d609645cc75028bbd59752
--   (99ccd9bb... es el md5 declarado en la 0265, de ANTES de esa migración —
--   el de partida de ella, no el vigente hoy). Esta migración se escribió
--   leyendo el cuerpo de la 0265 tal cual está en el repositorio.
--
--   No se pudo pedir el md5 de PRODUCCIÓN de `fn_publicar_documento` porque
--   esta sesión no tiene acceso al SQL Editor — Felipe lo confirma antes de
--   pegar, con la misma consulta que `donde-vive.sh` ya imprime.
--
-- ── POR QUÉ UNA FUNCIÓN NUEVA Y NO UN PARÁMETRO EN `fn_publicar_documento` ──
--
-- Se evaluaron las dos formas. Agregar `p_forzar boolean default false` a
-- `fn_publicar_documento` evitaba duplicar el guard y el cálculo de versión,
-- pero le cambia la firma a la función más usada del módulo —la que corre
-- cada vez que se publica cualquier documento— para un caso de uso que
-- ocurre pocas veces al año. Una función separada, con su propio nombre que
-- dice exactamente lo que autoriza, dejó `fn_publicar_documento` intacta y no
-- agranda la superficie de riesgo de la función que ya está en producción
-- todos los días.
--
-- ── QUÉ HACE, EXACTAMENTE ────────────────────────────────────────────────────
--
--   1. Exige DO, igual que publicar.
--   2. Busca la fila de `documentos_institucionales` que se le pide restaurar.
--   3. Si esa fila YA es la vigente (no hay ninguna versión posterior de su
--      mismo tipo), no hay nada que restaurar — excepción.
--   4. Calcula el correlativo `version` EN ESE MOMENTO, no antes: si alguien
--      publicó una versión nueva mientras la pantalla estaba abierta,
--      restaurar tiene que quedar DESPUÉS de esa, nunca pisarla.
--   5. Inserta una fila nueva con el mismo `tipo`, `titulo`, `documento` y
--      `etiqueta_version` de la versión restaurada, `vigente_desde = hoy`, y
--      una nota que deja dicho de qué versión viene — para que quien lo lea
--      dentro de un año no tenga que adivinarlo.
--   6. NO toca `documentos_acuses`. La versión nueva nace sin ninguna
--      constancia, igual que cualquier versión publicada por
--      `fn_publicar_documento` — restaurar no reinstala las constancias
--      viejas, porque esas constancias son la prueba de que alguien recibió
--      OTRA fila, con otro `documento_id`.
--
-- ── SE ROMPE SI ──────────────────────────────────────────────────────────────
--
--   Alguien restaura una versión justo cuando otra sesión está publicando una
--   distinta del mismo tipo. Por eso el correlativo se recalcula dentro de la
--   función, con el mismo `select coalesce(max(version), 0) + 1` que usa
--   `fn_publicar_documento` — nunca un número leído antes y guardado en el
--   cliente.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--
--   drop function if exists fn_restaurar_documento(uuid);
--
--   No deja nada más que revertir: no agrega columnas ni toca ninguna función
--   existente.
-- ============================================================================

create function fn_restaurar_documento(p_documento_id uuid)
returns int
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_yo      uuid;
  v_origen  documentos_institucionales%rowtype;
  v_version int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider de DO puede restaurar una version.';
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien restaura, asi que no puedo auditarlo. Inicia sesion con tu usuario.';
  end if;

  select * into v_origen from documentos_institucionales where id = p_documento_id;
  if not found then
    raise exception 'No existe la version que se quiere restaurar.';
  end if;

  if not exists (
    select 1 from documentos_institucionales
     where tipo = v_origen.tipo and version > v_origen.version
  ) then
    raise exception 'Esta ya es la version vigente. No hay nada que restaurar.';
  end if;

  -- El correlativo se recalcula AHORA: ver "SE ROMPE SI" arriba.
  select coalesce(max(version), 0) + 1 into v_version
  from documentos_institucionales where tipo = v_origen.tipo;

  insert into documentos_institucionales
    (tipo, version, titulo, documento, notas, vigente_desde, publicado_por, etiqueta_version)
  values
    (v_origen.tipo, v_version, v_origen.titulo, v_origen.documento,
     'Restaurada de la version ' || v_origen.version
       || coalesce(' (' || v_origen.etiqueta_version || ')', '') || '.',
     fn_hoy_lima(), v_yo, v_origen.etiqueta_version);

  return v_version;
end;
$fn$;

comment on function fn_restaurar_documento(uuid) is
  'Vuelve a publicar el texto de una version historica como version nueva, sin pasar por la deduplicacion por contenido de fn_publicar_documento. Existe porque hoy no hay forma de deshacer una publicacion con un error: republicar el mismo texto devuelve el numero de la fila vieja en vez de crear una vigente nueva.';

grant  execute on function fn_restaurar_documento(uuid) to authenticated;
revoke execute on function fn_restaurar_documento(uuid) from public, anon;

-- PostgREST guarda en cache qué funciones existen. Sin esto, el panel llama a
-- una función que para PostgREST todavía no existe.
notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (460, '0460_restaurar_una_version_anterior')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_restaurar_documento') = 1
                                                            as existe,
  has_function_privilege('authenticated',
    'fn_restaurar_documento(uuid)', 'EXECUTE')              as authenticated_puede,
  (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_restaurar_documento')
                                                            as md5_fn_restaurar_documento;
