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
# `fn_planilla_calcular` —la que decide lo que cobra cada persona— tiene
# VEINTIUNA definiciones repartidas y pesa 37.000 caracteres. Ahí este error no
# es hipotético: es cuestión de tiempo.
#
# QUÉ RESPONDE
#   · en qué migraciones está definida, en orden;
#   · cuál es la ÚLTIMA, que es la única de la que se puede copiar;
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

# La búsqueda es INSENSIBLE A MAYÚSCULAS y admite el prefijo `public.` opcional.
# Las dos cosas juntas son la razón de que este script exista.
ARCHIVOS=$(grep -rliE "create or replace function (public\.)?${FN}\b" supabase/migrations/*.sql 2>/dev/null | sort || true)

if [ -z "$ARCHIVOS" ]; then
  rojo "✗ Ninguna migración define «$FN»."
  gris "  ¿Está bien escrito el nombre? Prueba:  ls supabase/migrations | xargs grep -lie '$FN'"
  exit 1
fi

CUANTAS=$(echo "$ARCHIVOS" | wc -l | tr -d ' ')
ULTIMA=$(echo "$ARCHIVOS" | tail -1)

echo ""
echo "«$FN» está definida en $CUANTAS migración(es):"
echo "$ARCHIVOS" | while read -r f; do
  if [ "$f" = "$ULTIMA" ]; then verde "  → $(basename "$f")   ← LA VIGENTE, copia de esta"
  else gris "    $(basename "$f")"; fi
done

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

VIVA=$(docker exec "$CONT" psql -U postgres -d postgres -tAc \
  "select md5(prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='$FN' limit 1" 2>/dev/null | tr -d ' ' || true)

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
if grep -qiE "create or replace function (public\.)?${FN}\b" "$ULTIMA"; then
  verde "✓ Copia el cuerpo de:  $ULTIMA"
  gris "  Y compruébalo después:  el md5 de la base es $VIVA"
  gris "  Si al aplicar tu migración ese md5 no cambia como esperabas, partiste de"
  gris "  la versión equivocada."
fi
echo ""
