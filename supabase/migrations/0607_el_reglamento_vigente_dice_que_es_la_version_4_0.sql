-- ============================================================================
-- 0607 — El Reglamento vigente dice que es la versión 4.0
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que la publicación del Reglamento Interno de Trabajo que rige en Normas lleve
-- la etiqueta «4.0», que es la versión que su propio texto declara en la
-- portada. Y una función para hacer lo mismo con cualquier publicación que haya
-- quedado sin etiqueta, sin poder ponerle una que su texto no diga.
--
-- ── EL PROBLEMA, MEDIDO ─────────────────────────────────────────────────────
--
-- Felipe, en el SQL Editor de producción, el 2026-11-09:
--
--     version 1 · etiqueta_version null · vigente_desde 2026-08-11
--
-- La columna `etiqueta_version` existe desde la 0265 justamente para esto: el
-- cargo que firma la colaboradora dice «4.0», el correlativo de la base dice
-- «1», y sin la etiqueta el legajo de papel y la base no se pueden cruzar. La
-- publicación se hizo sin ella, así que en producción ese cruce nunca existió.
--
-- Se notó por la guía «Cómo funciona la disciplina» (PR #715): para saber si
-- resume el Reglamento que rige, compara su versión con esta etiqueta. Sin
-- etiqueta tuvo que comparar fechas, que es un dato más pobre (no distingue
-- una versión nueva de la misma versión vuelta a publicar).
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que en producción la publicación 1 de tipo `rit` es el texto 4.0. NO se
--     da por hecho: la función lee el texto y solo pone la etiqueta si la
--     primera versión que el texto declara es «4.0». Si no la declara, no toca
--     nada (devuelve 0) y la consulta de verificación lo muestra.
--   · Que la etiqueta es un dato DEL documento y no del texto. El texto sigue
--     congelado (0208: «si se regenerara, cambiar una coma dejaría todos los
--     acuses previos apuntando a un texto que nadie firmó»); esta migración no
--     lo toca. Tampoco toca ninguna constancia.
--
-- ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
--
-- POR QUÉ UNA FUNCIÓN Y NO UN UPDATE SUELTO. Es el molde de la 0581
-- (`fn_cargos_reabrir_plazo_sin_info`): la migración llama a la función y la
-- prueba 494 ejercita LA MISMA función. Con un UPDATE suelto, la prueba
-- tendría que copiar la sentencia, y probaría una copia, no lo que se pega.
--
-- POR QUÉ «LA PRIMERA VERSIÓN QUE EL TEXTO DECLARA» Y NO «EL TEXTO MENCIONA
-- 4.0». Un Reglamento 4.1 diría en su portada «Versión 4.1» y unas líneas más
-- abajo «sustituye íntegramente a la versión 4.0»: buscar «4.0» en cualquier
-- parte lo rotularía mal. La portada va primero en todo documento de la casa,
-- así que la primera mención es la suya.
--
-- POR QUÉ NO PISA UNA ETIQUETA YA PUESTA. Quien la escribió al publicar sabía
-- algo que esta función no sabe. Si alguna está mal, se corrige a mano y con
-- motivo, no por una función que lee texto.
--
-- POR QUÉ NADIE MÁS PUEDE LLAMARLA. No es una pantalla: es una herramienta de
-- migración. Se le quita el permiso a `anon` y `authenticated` (Supabase se lo
-- da por defecto a toda función nueva). No es SECURITY DEFINER: la llama quien
-- pega el SQL.
--
-- ── LO QUE NO HACE, Y POR QUÉ ───────────────────────────────────────────────
--
-- No toca `vigente_desde`. El texto del Reglamento dice que rige desde el 10
-- de agosto (art. 60.1) y la fila dice 11, el día en que se publicó en Normas
-- (lo dice la cabecera de la 0228). La consecuencia, medida: el freno del 60.5
-- (`fn_reglamento_no_acusado`) busca la versión que regía en la fecha de los
-- hechos con `vigente_desde <= fecha`. Para un hecho del 10 de agosto no
-- encuentra ninguna y calla, que es lo que la 0228 decidió para los hechos
-- anteriores a la primera publicación. Mover esa fecha cambiaría a qué hechos
-- se les exige la constancia: es decisión de Felipe, no de esta migración. La
-- consulta para medir cuántos documentos caen en ese día va en el PR.
--
-- ── CÓMO SE VERIFICA DESPUÉS DE PEGAR ───────────────────────────────────────
--
--   select d.version, d.etiqueta_version, d.vigente_desde,
--          (select nombre from migraciones_aplicadas where numero = 607) as registro
--     from documentos_institucionales d
--    where d.tipo = 'rit' order by d.version desc;
--
--   Lo esperado: la fila de la versión 1 con etiqueta «4.0» y el registro con
--   su nombre. Si la etiqueta sigue vacía, el texto de producción no declara
--   «Versión 4.0» en su portada: parar y mirarlo, no forzarla.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   update documentos_institucionales set etiqueta_version = null
--    where tipo = 'rit' and version = 1 and etiqueta_version = '4.0';
--   drop function if exists fn_documento_poner_etiqueta(text, int, text);
--   delete from migraciones_aplicadas where numero = 607;
--
-- Idempotente: repegarla no cambia nada, porque la función no toca una
-- etiqueta ya puesta.
-- ============================================================================

create or replace function fn_documento_poner_etiqueta(
  p_tipo     text,
  p_version  int,
  p_etiqueta text
)
returns int
language plpgsql volatile set search_path = public
as $fn$
declare
  v_etiqueta text := nullif(btrim(coalesce(p_etiqueta, '')), '');
  v_filas    int;
begin
  -- Solo números con puntos («4.0», «4.1», «5»): es lo que un Reglamento
  -- declara, y así la comparación de abajo es exacta.
  if v_etiqueta is null or v_etiqueta !~ '^[0-9]+(\.[0-9]+)*$' then
    raise exception 'La etiqueta tiene que ser un número de versión como «4.0»; llegó «%».', coalesce(p_etiqueta, '');
  end if;

  update documentos_institucionales d
     set etiqueta_version = v_etiqueta
   where d.tipo = p_tipo
     and d.version = p_version
     -- No pisa la que alguien escribió al publicar.
     and nullif(btrim(coalesce(d.etiqueta_version, '')), '') is null
     -- La PRIMERA versión que el texto declara: «Versión 4.0», «VERSIÓN 4.0»,
     -- «version 4.0». Las letras van una por una porque, con la colación C,
     -- lower() no baja la «Ó».
     and substring(d.documento from '[Vv][Ee][Rr][Ss][Ii][OoÓó][Nn][^0-9A-Za-z]{1,6}([0-9]+(\.[0-9]+)*)') = v_etiqueta;

  get diagnostics v_filas = row_count;
  return v_filas;
end;
$fn$;

comment on function fn_documento_poner_etiqueta(text, int, text) is
  'Pone la etiqueta de versión («4.0») a una publicación de documentos_institucionales que quedó sin ella, solo si la primera versión que declara su texto es esa. No pisa una etiqueta ya puesta. Devuelve cuántas filas cambió (0 o 1). Herramienta de migración: nadie de la app puede llamarla (0607).';

revoke execute on function fn_documento_poner_etiqueta(text, int, text) from public, anon, authenticated;

-- El Reglamento vigente en producción: publicación 1, texto 4.0 (medido el
-- 2026-11-09). En una base sin esa fila —CI, `db reset`, el entorno local— no
-- hace nada.
do $$
declare
  v_filas int := fn_documento_poner_etiqueta('rit', 1, '4.0');
begin
  raise notice '0607: % publicación(es) del Reglamento recibieron la etiqueta 4.0.', v_filas;
end;
$$;

insert into migraciones_aplicadas (numero, nombre)
values (607, 'el_reglamento_vigente_dice_que_es_la_version_4_0')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
