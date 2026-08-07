#!/bin/sh
# Entrega una migración para pegar en el SQL Editor — y solo si está a salvo.
#
# ── EL AGUJERO QUE CIERRA ───────────────────────────────────────────────────
#
# El 2026-08-07 se descubrió que la migración 0177 —que cambia cómo se pagan las
# vacaciones— estaba APLICADA EN PRODUCCIÓN y su único ejemplar en el mundo era
# un archivo sin commitear en el disco de una Mac. No estaba en GitHub. Si ese
# disco fallaba, nadie podía saber qué se le había hecho al cálculo de planilla
# ni cómo deshacerlo.
#
# Ninguno de los frenos que ya existían lo veía:
#   · `desplegar.sh` protege de PUBLICAR código sin guardar, no de PEGARLO;
#   · `hooks/pre-push` solo mira lo que se empuja;
#   · la prueba pgTAP 122 compara la base contra los archivos del disco —
#     incluidos los que nadie guardó.
#
# Los tres cuidan el camino de Vercel. El SQL a producción va por otro camino:
# alguien abre un archivo, lo copia y lo pega. Ese camino no tenía freno.
#
# ── POR QUÉ ENTREGA EL ARCHIVO EN VEZ DE SOLO AVISAR ────────────────────────
#
# Un script que solo dice «ojo, verifica antes de pegar» se olvida el día que hay
# prisa. Este se pone en el medio: es la forma más CÓMODA de obtener el SQL —te
# lo deja copiado en el portapapeles— y de paso comprueba. Si el archivo no está
# a salvo, no te lo da y te dice exactamente qué falta.
#
# ── QUÉ COMPRUEBA, Y POR QUÉ LAS TRES ───────────────────────────────────────
#
#   1. Que git lo conozca. Un archivo sin `git add` no existe para nadie más.
#   2. Que lo guardado sea lo que vas a pegar. Con cambios sin commitear,
#      producción recibiría una versión que el repo no tiene.
#   3. Que esté en GitHub, byte por byte. Es la única de las tres que sobrevive
#      a que esta Mac se rompa — y es la que faltó con la 0177.
#
# CÓMO SE USA
#   ./scripts/dame-el-sql.sh 173        una migración por su número
#   ./scripts/dame-el-sql.sh 0173       da igual con ceros o sin ellos
#   ./scripts/dame-el-sql.sh scripts/sql-manual/encender_sexto_cts.sql
#
# Qué NO hace: no se conecta a producción ni ejecuta nada. Solo lee y copia.

set -e

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || true)"
cd "${RAIZ:-$(dirname "$0")/..}"

rojo()  { printf "\033[31m%s\033[0m\n" "$1"; }
verde() { printf "\033[32m%s\033[0m\n" "$1"; }
gris()  { printf "\033[90m%s\033[0m\n" "$1"; }

if [ -z "${1:-}" ]; then
  rojo "✗ Falta decir qué SQL quieres."
  gris "  ./scripts/dame-el-sql.sh 173"
  gris "  ./scripts/dame-el-sql.sh scripts/sql-manual/encender_sexto_cts.sql"
  gris ""
  gris "  ¿No sabes cuál falta?  ./scripts/que-falta-pegar.sh"
  exit 1
fi

# ── Encontrar el archivo ────────────────────────────────────────────────────
# Un número busca en migraciones; cualquier otra cosa se toma como ruta.
if echo "$1" | grep -qE '^[0-9]+$'; then
  NUM=$(printf "%04d" "$1")
  ARCHIVO=$(ls supabase/migrations/${NUM}_*.sql 2>/dev/null | head -1 || true)
  if [ -z "$ARCHIVO" ]; then
    rojo "✗ No hay ninguna migración $NUM en supabase/migrations."
    gris "  La última es: $(ls -1 supabase/migrations | tail -1)"
    exit 1
  fi
else
  ARCHIVO="$1"
  if [ ! -f "$ARCHIVO" ]; then
    rojo "✗ No existe el archivo: $ARCHIVO"
    exit 1
  fi
fi

echo ""
echo "  $ARCHIVO"
gris "  $(wc -l < "$ARCHIVO" | tr -d ' ') líneas"
echo ""

FALLO=0

# ── 1 · ¿Git lo conoce? ─────────────────────────────────────────────────────
if ! git ls-files --error-unmatch "$ARCHIVO" >/dev/null 2>&1; then
  rojo "✗ Este archivo NO está en git. Existe solo en este disco."
  gris "    git add \"$ARCHIVO\" && git commit && git push"
  FALLO=1
else
  # ── 2 · ¿Lo guardado es lo que vas a pegar? ───────────────────────────────
  if ! git diff --quiet HEAD -- "$ARCHIVO" 2>/dev/null; then
    rojo "✗ Tiene cambios sin commitear: pegarías algo que el repo no tiene."
    gris "    git add \"$ARCHIVO\" && git commit && git push"
    FALLO=1
  fi

  # ── 3 · ¿Está en GitHub, byte por byte? ───────────────────────────────────
  # `git fetch` primero: sin él se compara contra una foto vieja de origin/main
  # y un archivo empujado hace un minuto parecería ausente.
  git fetch origin --quiet 2>/dev/null || gris "  (sin red: se compara con lo último que se trajo de GitHub)"

  if ! git cat-file -e "origin/main:$ARCHIVO" 2>/dev/null; then
    rojo "✗ NO está en GitHub. Si este disco falla, este SQL desaparece."
    gris "    Es exactamente lo que pasó con la 0177 el 2026-08-07."
    gris "    git push"
    FALLO=1
  elif ! git diff --quiet origin/main -- "$ARCHIVO" 2>/dev/null; then
    rojo "✗ Lo que hay en GitHub NO es igual a este archivo."
    gris "    Pegarías una versión que nadie más tiene. Empuja lo tuyo:"
    gris "    git push"
    FALLO=1
  fi
fi

if [ "$FALLO" = "1" ]; then
  echo ""
  rojo "  NO lo pegues todavía."
  gris "  Arregla lo de arriba y vuelve a correr esto."
  echo ""
  exit 1
fi

# ── A salvo: al portapapeles ────────────────────────────────────────────────
verde "✓ Guardado en git y en GitHub. Se puede pegar."
if command -v pbcopy >/dev/null 2>&1; then
  pbcopy < "$ARCHIVO"
  echo ""
  echo "  Copiado al portapapeles. Pégalo en el SQL Editor de Supabase (⌘V)."
else
  echo ""
  gris "  Ábrelo y cópialo entero:  $ARCHIVO"
fi
echo ""
gris "  Y recuerda: lo que devuelva el SQL Editor es la única confirmación."
gris "  Si sale un WARNING o un ERROR, no lo des por aplicado."
echo ""
