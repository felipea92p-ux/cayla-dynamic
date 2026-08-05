-- ============================================================================
-- 120_el_comprobante_pesa_hasta_50_mb.test.sql
-- ============================================================================
-- El 2026-08-05, cargando la primera asignación real, rebotó un PDF de 11.7 MB
-- contra un techo de 10 MB elegido pensando en «una foto de un recibo». La 0154
-- lo sube a 50 MB.
--
-- Pero lo que este archivo vigila no es el número: es que haya UN número.
--
-- El límite estaba escrito en dos sitios —el bucket, que rechaza, y una
-- constante en la pantalla, que avisa— sin nada que los obligara a coincidir. El
-- día que alguien cambiara uno solo, la pantalla diría «máximo 50 MB» y la base
-- rechazaría a los 10; y como el error de storage no habla de tamaño, nadie
-- sabría por dónde empezar a mirar. Ahora la pantalla pregunta, y esta prueba
-- comprueba que la función que le responde diga exactamente lo que el bucket
-- aplica — no un valor propio que pueda envejecer.
--
-- Es la tercera vez que este repositorio paga la misma forma de fallo: pasó con
-- «qué toca marcar» (SQL y navegador), con «qué es una falta» (pantalla y
-- documento) y con «quién puede leer la planilla» (un revoke y ningún guard).
-- ============================================================================
begin;
select plan(6);

-- ── El bucket, que es quien de verdad rechaza ──────────────────────────────
select is(
  (select file_size_limit from storage.buckets where id = 'comprobantes'),
  (50 * 1024 * 1024)::bigint,
  'BUCKET · el techo del bucket de comprobantes es de 50 MB');

select ok(
  (select allowed_mime_types @> array['application/pdf', 'image/jpeg', 'image/heic']
     from storage.buckets where id = 'comprobantes'),
  'BUCKET · acepta PDF y las fotos que salen de un celular (incluido HEIC de iPhone)');

select ok(
  (select not public from storage.buckets where id = 'comprobantes'),
  'BUCKET · sigue siendo privado: subir el techo no abrió los papeles a nadie');


-- ── La función que responde a la pantalla ──────────────────────────────────
select is(
  (select limite_bytes from fn_educacion_limite_comprobante()),
  (select file_size_limit from storage.buckets where id = 'comprobantes'),
  'UN SOLO SITIO · la función devuelve EXACTAMENTE el techo del bucket, no una copia');

select is(
  (select tipos from fn_educacion_limite_comprobante()),
  (select allowed_mime_types from storage.buckets where id = 'comprobantes'),
  'UN SOLO SITIO · y los formatos también salen del bucket');

-- La pantalla entra como `authenticated`. Sin este permiso la consulta falla y
-- la pantalla se queda con su valor de respaldo —10 MB— avisando de un techo que
-- ya no existe: el mismo desajuste, por otro camino.
select ok(
  has_function_privilege('authenticated', 'fn_educacion_limite_comprobante()', 'EXECUTE'),
  'UN SOLO SITIO · authenticated puede preguntarlo, que es quien lo pregunta');

select * from finish();
rollback;
