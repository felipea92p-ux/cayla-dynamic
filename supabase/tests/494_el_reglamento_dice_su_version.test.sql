-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 494 — El Reglamento dice su versión (0607)
-- ============================================================================
-- En producción, el Reglamento vigente se publicó sin `etiqueta_version`. La
-- 0607 se la pone con `fn_documento_poner_etiqueta`, y esta prueba ejercita ESA
-- función, la misma que llama la migración.
--
-- Lo que se exige aquí:
--   1. Pone la etiqueta cuando la portada del texto declara esa versión, y solo
--      a la publicación pedida (tipo y número).
--   2. Lee la PRIMERA versión que el texto declara: un 4.1 que «sustituye a la
--      versión 4.0» no se rotula 4.0.
--   3. No pisa una etiqueta ya puesta, y repetirla no cambia nada.
--   4. Acepta «VERSIÓN», «Versión» y «Version»; no confunde «4.0» con «4.01».
--   5. Rechaza una etiqueta que no sea un número de versión.
--   6. No toca el texto: el documento sigue siendo el que se firmó.
--   7. La app no puede llamarla, y la 0607 quedó registrada con su nombre.
--
-- Las publicaciones de prueba usan números de versión 49401 en adelante para no
-- chocar con las que traiga la base (el entorno local siembra la 1 y la 2).
-- ============================================================================
begin;
select plan(17);

insert into documentos_institucionales (tipo, version, titulo, documento, vigente_desde) values
  ('rit', 49401, 'Reglamento 4.0',
   E'# REGLAMENTO INTERNO DE TRABAJO\n\n**CAYLA S.A.C.**\n**Versión 4.0** — 10 de agosto de 2026\n\n> Sustituye íntegramente a la versión 3.0.',
   '2026-08-11'),
  ('rit', 49402, 'Reglamento 4.1',
   E'# REGLAMENTO INTERNO DE TRABAJO\n\n**Versión 4.1** — 1 de marzo de 2027\n\n> Sustituye íntegramente a la versión 4.0.',
   '2027-03-01'),
  ('rit', 49403, 'Reglamento en mayúsculas',
   E'REGLAMENTO INTERNO DE TRABAJO — VERSIÓN 4.0\n\nTexto.', '2026-08-11'),
  ('rit', 49404, 'Reglamento sin tilde',
   E'Reglamento. Version: 4.0\n\nTexto.', '2026-08-11'),
  ('rit', 49405, 'Reglamento 4.01',
   E'**Versión 4.01** — texto de prueba.', '2026-08-11'),
  ('rit', 49406, 'Reglamento sin versión',
   E'Un texto que no dice qué versión es.', '2026-08-11');

insert into documentos_institucionales (tipo, version, titulo, documento, vigente_desde, etiqueta_version) values
  ('rit', 49407, 'Reglamento ya rotulado', E'**Versión 4.0** — ya tenía etiqueta.', '2026-08-11', '4.0-papel');

-- Otro tipo de documento con el MISMO número y que también declara «Versión 4.0»,
-- para comprobar que se respeta el tipo pedido. Su tipo se crea aquí: si
-- dependiera de uno sembrado, en una base sin él la aserción pasaría sin probar nada.
insert into documentos_tipos (codigo, nombre, orden, requiere_acuse)
values ('prueba_494', 'Documento de prueba 494', 999, false);
insert into documentos_institucionales (tipo, version, titulo, documento, vigente_desde)
values ('prueba_494', 49401, 'Otro documento', E'**Versión 4.0**', '2026-08-11');

create temp table md5_antes as
  select version, md5(documento) as huella from documentos_institucionales where tipo = 'rit' and version > 49400;

-- ── 1 · La portada declara 4.0 → se rotula, y solo esa ──────────────────────
select is(fn_documento_poner_etiqueta('rit', 49401, '4.0'), 1,
  'ROTULA · la publicación cuya portada dice «Versión 4.0» recibe la etiqueta');
select is((select etiqueta_version from documentos_institucionales where tipo = 'rit' and version = 49401), '4.0',
  'ROTULA · la etiqueta quedó en «4.0»');
select is((select etiqueta_version from documentos_institucionales where tipo = 'prueba_494' and version = 49401), null::text,
  'ROTULA · otro tipo de documento con el mismo número no se toca');

-- ── 2 · La primera versión que declara, no cualquiera que mencione ──────────
select is(fn_documento_poner_etiqueta('rit', 49402, '4.0'), 0,
  'PORTADA · un 4.1 que «sustituye a la versión 4.0» NO se rotula 4.0');
select is((select etiqueta_version from documentos_institucionales where tipo = 'rit' and version = 49402), null::text,
  'PORTADA · y su etiqueta sigue vacía');
select is(fn_documento_poner_etiqueta('rit', 49402, '4.1'), 1,
  'PORTADA · con la versión que sí declara, se rotula');

-- ── 3 · No pisa, y repetir no hace nada ──────────────────────────────────────
select is(fn_documento_poner_etiqueta('rit', 49407, '4.0'), 0,
  'NO PISA · una etiqueta ya puesta no se cambia');
select is((select etiqueta_version from documentos_institucionales where tipo = 'rit' and version = 49407), '4.0-papel',
  'NO PISA · sigue la que estaba');
select is(fn_documento_poner_etiqueta('rit', 49401, '4.0'), 0,
  'IDEMPOTENTE · repetirla no cambia nada');

-- ── 4 · Cómo se escribe la palabra, y el número exacto ──────────────────────
select is(fn_documento_poner_etiqueta('rit', 49403, '4.0'), 1,
  'ESCRITURA · «VERSIÓN 4.0» en mayúsculas y con tilde');
select is(fn_documento_poner_etiqueta('rit', 49404, ' 4.0 '), 1,
  'ESCRITURA · «Version: 4.0» sin tilde, y la etiqueta llega con espacios');
select is(fn_documento_poner_etiqueta('rit', 49405, '4.0'), 0,
  'EXACTO · «4.01» no es «4.0»');
select is(fn_documento_poner_etiqueta('rit', 49406, '4.0'), 0,
  'EXACTO · un texto que no declara versión no se rotula');

-- ── 5 · La etiqueta tiene que ser un número de versión ───────────────────────
select throws_like(
  $$ select fn_documento_poner_etiqueta('rit', 49406, 'cuatro') $$,
  '%número de versión%',
  'FORMATO · «cuatro» no es una etiqueta');

-- ── 6 · El texto no se toca ──────────────────────────────────────────────────
select is(
  (select count(*)::int from documentos_institucionales d join md5_antes a using (version)
    where d.tipo = 'rit' and md5(d.documento) <> a.huella),
  0,
  'TEXTO · ningún documento cambió una coma');

-- ── 7 · La puerta y el registro ──────────────────────────────────────────────
select is(
  has_function_privilege('authenticated', 'public.fn_documento_poner_etiqueta(text, int, text)'::regprocedure, 'EXECUTE')
  or has_function_privilege('anon', 'public.fn_documento_poner_etiqueta(text, int, text)'::regprocedure, 'EXECUTE'),
  false,
  'PUERTA · la app no puede llamarla');
select is((select nombre from migraciones_aplicadas where numero = 607),
  'el_reglamento_vigente_dice_que_es_la_version_4_0',
  'REGISTRO · la 0607 está registrada con su nombre');

select * from finish();
rollback;
