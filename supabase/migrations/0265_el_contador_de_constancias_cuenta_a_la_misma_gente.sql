-- ============================================================================
-- 0265_el_contador_de_constancias_cuenta_a_la_misma_gente.sql
-- ============================================================================
-- QUÉ PROMETE
--   1. Que «N de M han dejado constancia» cuente arriba y abajo a las MISMAS
--      personas, y que no pueda volver a decir «24 de 24» mientras faltan.
--   2. Que la versión que la integrante lee en el documento —«versión 4.0»— y la
--      que el sistema registra dejen de ser dos números que nadie puede
--      conciliar.
--
-- QUÉ ASUME
--   md5 de partida, pedido al SQL Editor de PRODUCCIÓN el 2026-08-17:
--     fn_documentos_vigentes  5a896417a23a5ef8bd1c4c55e3d5c3dc   (893 caracteres)
--     fn_publicar_documento   99ccd9bbd2367f0547af8c8760c6dfd4   (1567 caracteres)
--   Las dos vienen de la 0208 y el Postgres local coincide con producción, así
--   que el cuerpo se copió de ahí (verificado con `donde-vive.sh`).
--
-- ── POR QUÉ LAS DOS COSAS EN UNA SOLA MIGRACIÓN ─────────────────────────────
--
-- Porque las dos caen sobre `fn_documentos_vigentes`, y esa función devuelve
-- TABLE: añadirle una columna exige `drop` y `create`, no admite
-- `create or replace`. Separarlas obligaría a dos `drop` de la misma función en
-- dos pasos, y el md5 de partida de la segunda tendría que declarar un número
-- que hoy no existe —el que dejara la primera—, o sea una comprobación que nadie
-- podría hacer antes de pegar. Una sola pasada es lo verificable.
--
-- ── DEFECTO 1 · EL NUMERADOR Y EL DENOMINADOR HABLABAN DE OTRA GENTE ────────
--
-- `total_acuses` contaba TODA fila de `documentos_acuses`. `poblacion` contaba
-- solo `estado = 'activo' and en_planilla is true`. Son dos poblaciones
-- distintas, y la desviación llega **por el paso del tiempo, sin que nadie se
-- equivoque**: quien deja su constancia y después cesa se queda en el numerador
-- —y DEBE quedarse, esa fila es la prueba de que recibió el documento— pero sale
-- del denominador. Con unas 24 personas activas de unas 30, esto ocurre solo.
--
-- Y el síntoma es peor que un número raro: en la pantalla, el mismo texto que
-- dice «N de M han dejado constancia · faltan …» ES el botón que abre la lista
-- que lo desmiente. Se leería «24 de 24» sin el «faltan», o el imposible
-- «24 de 23», justo en el panel con el que Desarrollo Organizacional decide a
-- quién le falta entregar el Reglamento. Un contador que dice que ya está
-- completo es exactamente el que hace que nadie mire la lista.
--
-- ── POR QUÉ UNA FUNCIÓN PARA LA POBLACIÓN Y NO UN `AND` MÁS ─────────────────
--
-- Porque «a quién obliga el Reglamento» se responde hoy en tres sitios con la
-- misma frase escrita a mano: aquí, en `fn_acuses_documento` (0208) y en
-- `fn_sin_constancia_del_reglamento` (0229). La 0229 dejó escrito en su propio
-- encabezado que dos respuestas distintas a la misma pregunta son lo que el
-- CLAUDE.md prohíbe — y arregló una de las tres. `fn_poblacion_obligada()` es
-- esa respuesta, en un solo sitio y con su porqué.
--
-- Se usa YA en `fn_documentos_vigentes`, en el numerador y en el denominador.
-- Las otras dos se quedan con su copia literal y NO es un olvido: las dos
-- devuelven TABLE y tocarlas pediría su propio `drop`, su propio md5 de partida
-- y su propia prueba pgTAP; y `fn_sin_constancia_del_reglamento` además tiene
-- dos versiones en el repositorio. Mezclar eso aquí convertiría una corrección
-- medible en una reescritura de tres funciones en la misma pasada. Queda
-- pendiente, dicho aquí para que se lea como deuda y no como descuido.
--
-- ── DEFECTO 2 · DOS NÚMEROS DE VERSIÓN QUE NO SE PUEDEN CONCILIAR ───────────
--
-- `documentos_institucionales.version` es un correlativo que la propia función
-- calcula como `max(version) + 1` por tipo. El TEXTO del documento lleva su
-- versión editorial escrita dentro —«Versión 4.0 — 10 de agosto de 2026»—. Son
-- dos contadores independientes que solo coincidirían por casualidad, y con el
-- Reglamento 4.0 publicado como `version = 1`, el 5.0 será la 2: el desfase de
-- tres se queda para siempre.
--
-- Lo que eso rompe es concreto: el cargo que la integrante FIRMA dice «versión
-- 4.0» y la constancia del sistema apunta a «versión 1». El día que haya que
-- probar qué versión recibió cada quien, el legajo de papel y la base no se
-- pueden cruzar sin abrir el texto congelado y leerlo. En los anexos se
-- multiplica por cinco: cuatro de los cinco declaran «versión 4.0» heredada del
-- Reglamento.
--
-- ── POR QUÉ SE PIDE Y NO SE DEDUCE DEL TEXTO ────────────────────────────────
--
-- Se pensó en leer la etiqueta del propio documento con un patrón. No se hace:
-- solo el Reglamento la tiene en un sitio predecible, los anexos la llevan
-- embutida en prosa, y los documentos que se PEGAN desde un Word o un Canva
-- —la vía que existe desde hoy para la misión y los valores— pueden no traerla.
-- Un analizador acertaría en uno y fallaría en silencio en el resto, que es la
-- peor de las dos formas de fallar. Se pide como dato, junto a `vigente_desde` y
-- las notas, que ya se piden.
--
-- Es OPCIONAL a propósito: un documento sin versión editorial es legítimo, y
-- exigirla convertiría en obligatorio un dato que la mitad de los documentos no
-- tiene. Cuando falta, la pantalla sigue mostrando el correlativo.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   Volver a pegar los cuerpos de `fn_documentos_vigentes` y
--   `fn_publicar_documento` tal como están en la 0208 (drop + create, por el
--   TABLE y por el parámetro nuevo), y:
--     alter table documentos_institucionales drop column etiqueta_version;
--
--   La columna no se revierte «por si acaso»: lo que guarda es lo que dice el
--   papel que alguien firmó.
-- ============================================================================

-- ── 1 · A quién obliga el Reglamento, dicho una sola vez ────────────────────
--
-- Criterio del artículo 2.1: toda persona activa con contrato de trabajo. Los
-- locadores no están comprendidos por el Reglamento, así que tampoco cuentan.
create or replace function fn_poblacion_obligada()
returns setof uuid
language sql stable security definer set search_path = public
as $fn$
  select id from personas
  where estado = 'activo' and en_planilla is true;
$fn$;

comment on function fn_poblacion_obligada() is
  'Las personas a las que el Reglamento obliga y a las que por tanto se les pide constancia. Vive en una sola funcion porque la misma pregunta se respondia con la misma frase escrita a mano en tres sitios, y dos respuestas distintas a una sola pregunta es lo que este repositorio prohibe.';

grant  execute on function fn_poblacion_obligada() to authenticated;
revoke execute on function fn_poblacion_obligada() from public, anon;

-- ── 2 · La etiqueta de versión que dice el documento ────────────────────────
alter table documentos_institucionales
  add column if not exists etiqueta_version text;

comment on column documentos_institucionales.etiqueta_version is
  'La version que el DOCUMENTO declara en su propio texto —«4.0»—, que es la que aparece en el cargo que la integrante firma. Distinta del correlativo `version`, que solo cuenta cuantas veces se ha publicado este tipo en el sistema. Sin las dos, el legajo de papel y la base no se pueden cruzar.';

-- ── 3 · El contador, y la etiqueta en la lista ──────────────────────────────
-- `drop` y no `create or replace`: la función devuelve TABLE y se le añade una
-- columna, y Postgres no deja cambiar el tipo de retorno de otra forma.
drop function if exists fn_documentos_vigentes();

create function fn_documentos_vigentes()
returns table (
  documento_id     uuid,
  tipo             text,
  tipo_nombre      text,
  version          int,
  etiqueta_version text,
  titulo           text,
  documento        text,
  vigente_desde    date,
  publicado_at     timestamptz,
  requiere_acuse   boolean,
  mi_acuse_at      timestamptz,
  total_acuses     int,
  poblacion        int
)
language sql stable security definer set search_path = public
as $fn$
  with ultimas as (
    select distinct on (d.tipo) d.*
    from documentos_institucionales d
    order by d.tipo, d.version desc
  )
  select u.id, u.tipo, t.nombre, u.version, u.etiqueta_version, u.titulo, u.documento,
         u.vigente_desde, u.publicado_at, t.requiere_acuse,
         (select a.acusado_at from documentos_acuses a
           where a.documento_id = u.id and a.persona_id = fn_persona_actual_id()),
         -- El numerador se limita a la MISMA poblacion que el denominador. Quien
         -- acuso y despues ceso conserva su fila —es su prueba— pero deja de
         -- contar en un panel que mide a quien le falta entregar el documento.
         (select count(*)::int from documentos_acuses a
           where a.documento_id = u.id
             and a.persona_id in (select fn_poblacion_obligada())),
         (select count(*)::int from fn_poblacion_obligada())
  from ultimas u
  join documentos_tipos t on t.codigo = u.tipo
  where t.activo
  order by t.orden, t.nombre;
$fn$;

grant  execute on function fn_documentos_vigentes() to authenticated;
revoke execute on function fn_documentos_vigentes() from public, anon;

-- ── 4 · Publicar, aceptando la etiqueta ────────────────────────────────────
-- `drop` primero: añadir un parámetro —aunque tenga valor por omisión— crea una
-- SOBRECARGA nueva en vez de reemplazar, y con las dos vivas nadie sabe cuál
-- llama el cliente.
drop function if exists fn_publicar_documento(text, text, text, date, text);

create function fn_publicar_documento(
  p_tipo          text,
  p_titulo        text,
  p_documento     text,
  p_vigente_desde date default null,
  p_notas         text default null,
  p_etiqueta      text default null
)
returns int
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_yo      uuid;
  v_version int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider de DO puede publicar un documento institucional.';
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien publica, asi que no puedo auditarlo. Inicia sesion con tu usuario.';
  end if;

  if not exists (select 1 from documentos_tipos where codigo = p_tipo and activo) then
    raise exception 'No existe un tipo de documento activo con codigo "%".', p_tipo;
  end if;

  if p_documento is null or btrim(p_documento) = '' then
    raise exception 'No se puede publicar un documento vacio.';
  end if;

  -- Publicar dos veces EL MISMO texto no crea version nueva: obligaria a las 24
  -- personas a dejar constancia otra vez de algo que no cambio, y una constancia
  -- que se pide sin motivo ensena que la constancia es tramite.
  select version into v_version
  from documentos_institucionales
  where tipo = p_tipo and documento = p_documento
  order by version desc limit 1;

  if v_version is not null then
    return v_version;
  end if;

  select coalesce(max(version), 0) + 1 into v_version
  from documentos_institucionales where tipo = p_tipo;

  insert into documentos_institucionales
    (tipo, version, titulo, documento, notas, vigente_desde, publicado_por, etiqueta_version)
  values
    (p_tipo, v_version, btrim(p_titulo), p_documento,
     nullif(btrim(coalesce(p_notas, '')), ''),
     coalesce(p_vigente_desde, fn_hoy_lima()), v_yo,
     nullif(btrim(coalesce(p_etiqueta, '')), ''));

  return v_version;
end;
$fn$;

grant  execute on function fn_publicar_documento(text, text, text, date, text, text) to authenticated;
revoke execute on function fn_publicar_documento(text, text, text, date, text, text) from public, anon;

-- PostgREST guarda en cache la firma de las funciones. Sin esto, el panel sigue
-- llamando a la de cinco parametros y la etiqueta se pierde en silencio.
notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (265, '0265_el_contador_de_constancias_cuenta_a_la_misma_gente')
on conflict (numero) do nothing;

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
-- Un solo select, porque el SQL Editor solo devuelve el ultimo.
-- Tiene que salir: numerador_correcto = true, columna_etiqueta = true,
-- publicar_con_etiqueta = 6 (los parametros que ahora acepta).
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_poblacion_obligada') = 1
                                                              as poblacion_unica,
  exists (select 1 from information_schema.columns
           where table_name = 'documentos_institucionales'
             and column_name = 'etiqueta_version')             as columna_etiqueta,
  (select pronargs from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_publicar_documento')
                                                              as publicar_con_etiqueta,
  (select position('fn_poblacion_obligada' in p.prosrc) > 0
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_documentos_vigentes')
                                                              as numerador_correcto,
  (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_documentos_vigentes')
                                                              as md5_nuevo_vigentes;
