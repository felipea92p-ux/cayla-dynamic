#!/bin/bash
# ¿Dónde está la versión VIGENTE de una función?
#
#   ./scripts/donde-vive.sh fn_recalcular_jornada
#
# POR QUÉ EXISTE. El 2026-08-05 escribí una migración copiando el cuerpo de
# `fn_recalcular_jornada` desde la migración 0017, convencido de que era la
# última. La última era la 0081 — sesenta y cuatro migraciones después. Esa
# versión habría revertido en silencio toda la lógica de marcas anuladas, y en
# producción nadie se habría enterado hasta cuadrar una planilla.
#
# Lo cazaron dos pruebas de puro azar. La causa no fue descuido: fue que buscar
# «la última definición» exige un grep sobre 150 archivos Y acordarse de que la
# 0081 la escribe `CREATE OR REPLACE FUNCTION public.fn_…` en mayúsculas y con
# prefijo, mientras las otras cuatro la escriben en minúsculas y sin él. Un grep
# normal encuentra cuatro definiciones y se salta justamente la que importa.
#
# `fn_planilla_calcular` —la que decide lo que cobra cada persona— tiene hoy
# VEINTITRÉS definiciones repartidas y pesa 37.000 caracteres. Ahí este error no
# es hipotético: es cuestión de tiempo.
#
# LAS DOS FORMAS DE ESCRIBIR UNA DEFINICIÓN. Postgres no deja cambiar el tipo de
# retorno con un `create or replace`: para agregarle una columna a una función
# que devuelve TABLE hay que borrarla y volver a crearla. Así que una definición
# vigente llega de dos maneras, y las dos cuentan igual:
#
#     create or replace function fn_x()      ← la habitual
#
#     drop function if exists fn_x();        ← y a continuación, en el mismo archivo
#     create function fn_x()                    la definición que vale
#
# Este script leyó durante un tiempo solo la primera. Con eso `fn_documentos_tablero`
# aparecía como si viviera todavía en la 0157, cuando la 0161 la había recreado para
# devolver también `bono_firmada_el`, `bono_mes` y `bono_estado`. Copiar de la 0157
# se llevaba esas tres columnas por delante sin que fallara nada: la pantalla de
# Documentación se quedaba ciega para los cargos del bono de cumpleaños y el sistema
# no decía ni una palabra. Exactamente el modo de fallo que este script existe para
# evitar.
#
# Un `drop function` SIN un `create` después es la otra cara: ahí la función dejó
# de existir, y ofrecer su último cuerpo para copiar sería resucitar algo que
# alguien decidió eliminar (le pasaba a `fn_sembrar_ingresos`, que la 0041 borró).
#
# QUÉ RESPONDE
#   · en qué migraciones está definida, en orden;
#   · cuál es la ÚLTIMA, que es la única de la que se puede copiar;
#   · si alguien la borró después y ya no existe;
#   · si el Postgres local coincide con esa última — y si no, avisa de que la
#     base está contaminada y no sirve como referencia.

set -euo pipefail
cd "$(dirname "$0")/.."

rojo()  { printf "\033[31m%s\033[0m\n" "$1"; }
verde() { printf "\033[32m%s\033[0m\n" "$1"; }
ambar() { printf "\033[33m%s\033[0m\n" "$1"; }
gris()  { printf "\033[90m%s\033[0m\n" "$1"; }

FN="${1:-}"
if [ -z "$FN" ]; then
  echo "Uso:  ./scripts/donde-vive.sh <nombre_de_la_funcion>"
  gris "  ejemplo:  ./scripts/donde-vive.sh fn_planilla_calcular"
  exit 2
fi

# El nombre se normaliza UNA vez, aquí, y de aquí en adelante nadie vuelve a
# pensar en mayúsculas ni en el prefijo. Postgres guarda los nombres en
# minúsculas: sin esto, escribir `FN_X` encontraba el archivo pero luego no
# encontraba la función en la base, y el script culpaba a la base local de estar
# incompleta cuando el único problema era cómo se había tecleado la pregunta.
FN=$(printf '%s' "$FN" | tr 'A-Z' 'a-z' | sed -E 's/^public\.//')

# ── Los hechos: qué le pasó a esta función, migración por migración ─────────
#
# Recorre los .sql en orden y anota, por archivo, si lo que hay dentro CREA la
# función o solo la BORRA. Un archivo que la crea cuenta como definición aunque
# antes traiga un `drop` — es justo lo que hace la 0161: borra en la línea 67 y
# crea en la 69, porque Postgres no deja cambiar el tipo de retorno con un
# `create or replace`.
#
# La unidad es el ARCHIVO, no la línea, y eso es deliberado. La 0099 crea
# `fn_guardar_sede(text,text,text)` en la línea 90 y en la 121 borra la firma
# vieja de dos argumentos: mirar solo el último renglón la daría por muerta
# cuando en realidad acababa de nacer. Distinguirlo de verdad exigiría comparar
# las firmas argumento por argumento; a cambio de no escribir ese parser, el
# script asume que un archivo que crea la función la deja viva.
#
# Se ignora lo que va después de `--`. No es cosmética: casi todas las
# migraciones traen en su cabecera un «CÓMO SE REVIERTE: drop function fn_x»
# que jamás se ejecutó. Contarlo daría por muerta a media base de código.
EVENTOS=$(
  awk -v fn="$FN" '
    BEGIN {
      # `\b` no existe en el awk de macOS: el borde se escribe a mano.
      borde  = "[^a-z0-9_]"
      crear  = "(^|" borde ")create[ \t]+(or[ \t]+replace[ \t]+)?function[ \t]+(public\\.)?" fn borde
      borrar = "(^|" borde ")drop[ \t]+function[ \t]+(if[ \t]+exists[ \t]+)?(public\\.)?" fn borde
    }
    {
      linea = tolower($0)
      sub(/--.*/, "", linea)      # fuera los comentarios de fin de línea
      linea = linea " "           # colchón, para que el nombre pueda cerrar la línea
      if (linea ~ crear)       clase[FILENAME] = "crea"
      else if (linea ~ borrar) { if (clase[FILENAME] == "") clase[FILENAME] = "borra" }
      else next
      if (!visto[FILENAME]++) orden[++n] = FILENAME
    }
    END { for (i = 1; i <= n; i++) print clase[orden[i]] "\t" orden[i] }
  ' supabase/migrations/*.sql 2>/dev/null || true
)

if [ -z "$EVENTOS" ]; then
  rojo "✗ Ninguna migración define «${FN}»."
  gris "  ¿Está bien escrito el nombre? Prueba:  ls supabase/migrations | xargs grep -lie '$FN'"
  exit 1
fi

# Los archivos que la crean, en orden de migración.
ARCHIVOS=$(echo "$EVENTOS" | awk -F'\t' '$1=="crea" { print $2 }')
ARCHIVO_FINAL=$(echo "$EVENTOS" | tail -1 | cut -f2)

if [ -z "$ARCHIVOS" ]; then
  # Solo hay borrados: la función se creó fuera de estas migraciones.
  rojo "✗ «${FN}» solo aparece borrada, nunca creada, en supabase/migrations."
  gris "  Última mención:  $(basename "$ARCHIVO_FINAL")"
  exit 1
fi

CUANTAS=$(echo "$ARCHIVOS" | wc -l | tr -d ' ')
ULTIMA=$(echo "$ARCHIVOS" | tail -1)

echo ""
echo "«${FN}» está definida en $CUANTAS migración(es):"
echo "$ARCHIVOS" | while read -r f; do
  if [ "$f" != "$ULTIMA" ]; then
    gris "    $(basename "$f")"
  elif [ "$ARCHIVO_FINAL" = "$ULTIMA" ]; then
    verde "  → $(basename "$f")   ← LA VIGENTE, copia de esta"
  else
    ambar "    $(basename "$f")   ← la última definición… pero mira abajo"
  fi
done

# ── ¿Sigue existiendo? ──────────────────────────────────────────────────────
# Si después de la última migración que la define hay otra que solo la borra,
# la función ya no está. Ofrecer su cuerpo para copiar sería resucitar algo que
# alguien decidió eliminar.
if [ "$ARCHIVO_FINAL" != "$ULTIMA" ]; then
  echo ""
  rojo "✗ «${FN}» YA NO EXISTE: la borró $(basename "$ARCHIVO_FINAL")."
  gris "  Su última definición fue $(basename "$ULTIMA"), pero se eliminó después."
  gris "  Volver a crearla es una decisión de negocio, no un copiar y pegar."
  echo ""
  exit 0
fi

if [ "$CUANTAS" -gt 1 ]; then
  echo ""
  ambar "⚠ Hay $CUANTAS versiones. Copiar de cualquiera que no sea la última revierte"
  gris "  en silencio todo lo que se arregló entre medias."
fi

# ── ¿Coincide con la base local? ────────────────────────────────────────────
CONT=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -m1 'supabase_db_' || true)
if [ -z "$CONT" ]; then
  echo ""
  gris "  (El Postgres local no está levantado, así que no se pudo comparar."
  gris "   Para comparar:  npx supabase db start)"
  exit 0
fi

SQL_MD5="select md5(p.prosrc) || '|' || md5(array_to_string(array(
             select regexp_replace(l, '[[:space:]]*--.*\$', '')
             from unnest(string_to_array(p.prosrc, chr(10))) as l
             where btrim(l) not like '--%'
           ), chr(10)))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '$FN' limit 1"

PAR=$(docker exec "$CONT" psql -U postgres -d postgres -tAc "$SQL_MD5" 2>/dev/null | tr -d ' ' || true)
VIVA=${PAR%%|*}
PELADA=${PAR##*|}

if [ -z "$VIVA" ]; then
  echo ""
  ambar "⚠ La función no existe en el Postgres local."
  gris "  La base no tiene aplicadas todas las migraciones. Reconstrúyela antes de"
  gris "  usarla como referencia:  npx supabase db reset"
  exit 0
fi

# El cuerpo tal como quedó en la base es la verdad; se compara contra el texto
# de la última migración por si alguien aplicó SQL a mano encima.
echo ""
verde "✓ Copia el cuerpo de:  $ULTIMA"
echo ""
gris "  md5 de tu base local:      $VIVA"
gris "  el mismo, sin comentarios: $PELADA"
echo ""

# ── Por qué hay DOS md5, y por qué el segundo hace falta ────────────────────
#
# El md5 de partida se le pide a PRODUCCIÓN, no se copia de aquí — eso ya lo
# decía el CLAUDE.md. Lo que no decía es que ese número casi nunca coincide:
# medido el 2026-08-18, el 49 % de las funciones de producción NO TIENEN NI UNA
# LÍNEA DE COMENTARIO. Se pegaron sin ellos.
#
# Y ese detalle convertía la comprobación en ruido: el síntoma de «producción
# perdió los comentarios» es exactamente el mismo que el de «producción tiene
# otra versión», que es el accidente grave que este script existe para evitar.
# Media hora se fue en distinguirlos a mano la primera vez.
#
# Con el md5 sin comentarios al lado, los tres casos se separan de un vistazo.
ambar "  PÍDESELO A PRODUCCIÓN. Pega esto en el SQL Editor (solo lee):"
echo ""
cat <<SQL
    select md5(p.prosrc)                                   as tal_cual,
           md5(array_to_string(array(
             select regexp_replace(l, '[[:space:]]*--.*\$', '')
             from unnest(string_to_array(p.prosrc, chr(10))) as l
             where btrim(l) not like '--%'
           ), chr(10)))                                    as sin_comentarios,
           length(p.prosrc)                                as caracteres
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = '$FN';
SQL
echo ""
gris "  Y así se lee lo que devuelva:"
gris ""
gris "   · tal_cual = $VIVA"
gris "     → producción está idéntica a esta Mac. Sigue tranquila."
gris ""
gris "   · sin_comentarios = $PELADA  (y tal_cual distinto)"
gris "     → MISMO CÓDIGO. Producción perdió los comentarios al pegarse, que le"
gris "       pasa a la mitad de las funciones. Sigue — pero declara en tu"
gris "       migración el md5 de PRODUCCIÓN, no el de aquí."
gris ""
gris "   · ninguno de los dos coincide"
gris "     → PARA. Producción tiene otra versión, y copiar de $ULTIMA la"
gris "       revertiría en silencio. Mide dónde está la diferencia antes de"
gris "       proponer explicaciones: length contra octet_length, y un substring"
gris "       del principio."
echo ""
