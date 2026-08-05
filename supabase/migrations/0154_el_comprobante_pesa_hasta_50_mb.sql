-- ============================================================================
-- 0154 — Un comprobante puede pesar hasta 50 MB, y el límite vive en un solo sitio
-- ============================================================================
--
-- QUÉ PROMETE
--   Que subir el comprobante de una asignación por educación no obligue a nadie
--   a comprimir el archivo antes, y que el número que la pantalla anuncia sea
--   exactamente el que la base aplica — no una copia suya que puede quedar vieja.
--
-- QUÉ ASUME
--   Que el límite GLOBAL de storage del proyecto es de al menos 50 MB. El del
--   bucket no puede superarlo: si el proyecto está en 10 MB, poner 50 acá no
--   sirve de nada y la subida falla igual, con otro mensaje. En local vive en
--   `supabase/config.toml` ([storage] file_size_limit = "50MiB"); en producción,
--   en el panel de Supabase → Storage → Settings → Upload file size limit.
--
-- POR QUÉ AHORA
--   El 2026-08-05, cargando la primera asignación real, rebotó un PDF de 11.7 MB
--   («Janis Revilla – Cultural.pdf») contra el techo de 10 MB que puso la 0136.
--   Ese techo se eligió pensando en «una foto de un recibo»; un escaneo de varias
--   páginas o una foto de un celular moderno lo pasan sin esfuerzo. Comprimir a
--   mano cada comprobante es trabajo que el sistema le estaba creando a DO por
--   una constante mal calibrada.
--
-- POR QUÉ EL LÍMITE PASA A LEERSE Y NO A COPIARSE
--   Estaba escrito en dos sitios: `storage.buckets.file_size_limit` (que es quien
--   de verdad rechaza) y `MAX_BYTES` en la pantalla (que es quien avisa). Nada
--   obligaba a que coincidieran. El día que alguien cambiara uno solo, la
--   pantalla diría «máximo 50 MB» y la base rechazaría a los 10 — y el mensaje
--   de error no hablaría de tamaño, así que nadie sabría por dónde empezar a
--   mirar. Es la misma forma de fallo que este repositorio ya pagó con «qué toca
--   marcar» (SQL y navegador), «qué es una falta» (pantalla y documento) y
--   «quién puede leer la planilla» (un revoke y ningún guard).
--
--   La regla del repo dice que no se escribe a mano una lista de algo que vive en
--   una tabla. El límite vive en `storage.buckets`, así que la pantalla lo
--   pregunta. `fn_educacion_limite_comprobante()` devuelve también los tipos de
--   archivo aceptados, que sufrían de lo mismo.
--
--   Va por función y no por SELECT directo porque `storage.buckets` no es legible
--   para el rol `authenticated`: sin la función, la pantalla tendría que llevar
--   la copia igual.
--
-- CÓMO SE REVIERTE
--   update storage.buckets set file_size_limit = 10485760 where id = 'comprobantes';
--   drop function if exists fn_educacion_limite_comprobante();
--   Y devolver a la pantalla su constante. Los archivos ya subidos NO se tocan:
--   bajar el límite no borra ni invalida lo que ya está guardado, solo impide
--   subidas nuevas más grandes.
-- ============================================================================

-- 50 MiB. Se escribe la cuenta y no el número crudo para que se lea sin
-- calculadora — el 10485760 de la 0136 no le decía nada a nadie.
update storage.buckets
   set file_size_limit = 50 * 1024 * 1024
 where id = 'comprobantes';


-- ── El único sitio donde la pantalla pregunta qué cabe ──────────────────────
create or replace function fn_educacion_limite_comprobante()
returns table (limite_bytes bigint, tipos text[])
language sql
stable
security definer
set search_path = public
as $$
  select b.file_size_limit, b.allowed_mime_types
  from storage.buckets b
  where b.id = 'comprobantes';
$$;

comment on function fn_educacion_limite_comprobante() is
  'Cuánto puede pesar un comprobante y qué formatos se aceptan, leídos del bucket '
  'que de verdad los aplica. La pantalla los consulta en vez de llevar su propia '
  'copia: dos copias del mismo número terminan discrepando, y el día que pasa, el '
  'error que ve la persona no habla de tamaño.';

grant execute on function fn_educacion_limite_comprobante() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (154, 'el_comprobante_pesa_hasta_50_mb')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_bucket bigint;
begin
  select file_size_limit into v_bucket from storage.buckets where id = 'comprobantes';
  raise notice '0154 · el comprobante puede pesar hasta % MB.', round(v_bucket / 1024.0 / 1024.0);
  raise notice '0154 · si una subida grande sigue fallando, el techo que manda es el GLOBAL del proyecto:';
  raise notice '0154 ·   panel de Supabase -> Storage -> Settings -> Upload file size limit.';
end $mig$;
