#!/bin/bash
# Freno de numeración: que dos trabajos no reclamen el mismo número.
#
# POR QUÉ EXISTE. El 2026-08-05, en una sola jornada, hubo CUATRO choques entre
# sesiones que trabajaban en paralelo sobre este repo:
#
#   · la migración 0136 la reclamaron dos ramas a la vez;
#   · las pruebas 111, 112 y 114 quedaron duplicadas;
#   · un `db reset` ajeno aplicó un archivo sin commitear y dejó una prueba de
#     seguridad "pasando" contra una base que ya tenía el arreglo;
#   · y un `git checkout main` ajeno se llevó una rama a media tarea.
#
# Los dos primeros los caza esto. Un número duplicado no es desorden: es que dos
# personas creen tener la última migración, y la que se aplique segunda pisa a la
# primera sin avisar. En un sistema que calcula sueldos, eso es plata mal pagada.
#
# SOLO MIRA LO QUE ESTE PUSH AGREGA, y esa es la decisión de diseño que lo hace
# usable. La primera versión comparaba el árbol entero contra todas las ramas y
# encontraba nueve choques históricos —de ramas abandonadas, resueltos hace
# semanas renumerando— así que fallaba en CUALQUIER push. Un freno que chilla
# siempre se desactiva a la semana, y entonces no frena nada. Este solo habla de
# archivos que antes no existían.
#
# QUÉ HACE FALLAR EL PUSH
#   1. Dos archivos con el mismo número en el árbol de trabajo.
#   2. Un número NUEVO que otra rama sin fusionar ya usa para otra cosa.
#
# QUÉ SOLO AVISA
#   Los huecos. Hay casos legítimos documentados —la 0031 y la 0033 viven fuera
#   de git por datos personales— así que un hueco se mira, no se bloquea.
#
# Se salta con `git push --no-verify`.

set -euo pipefail
cd "$(dirname "$0")/../.."

rojo()  { printf "\033[31m%s\033[0m\n" "$1"; }
ambar() { printf "\033[33m%s\033[0m\n" "$1"; }
gris()  { printf "\033[90m%s\033[0m\n" "$1"; }

FALLO=0

# ── 1 · Duplicados dentro del árbol de trabajo ──────────────────────────────
# Instantáneo y siempre correcto: si dos archivos de la misma carpeta empiezan
# con el mismo número, uno de los dos está mal, venga de donde venga.
for dir in "supabase/migrations" "supabase/tests"; do
  [ -d "$dir" ] || continue
  DUPS=$(ls "$dir" | sed -E 's/^([0-9]+)_.*/\1/' | grep -E '^[0-9]+$' | sort | uniq -d || true)
  if [ -n "$DUPS" ]; then
    rojo "✗ Números repetidos en $dir:"
    for n in $DUPS; do
      gris "    $n →"
      ls "$dir" | grep -E "^${n}_" | sed 's/^/      /'
    done
    FALLO=1
  fi
done

# ── 2 · Lo NUEVO de este push, contra las ramas vivas ──────────────────────
# Nuevo = está acá y no en origin/main. Si no hay nada nuevo numerado, no se
# toca la red y el hook termina de inmediato.
NUEVOS=""
if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  EN_MAIN=$(git ls-tree -r --name-only origin/main -- supabase/migrations supabase/tests 2>/dev/null \
            | xargs -n1 basename 2>/dev/null | sort -u || true)
  AQUI=$(ls supabase/migrations supabase/tests 2>/dev/null | grep -E '^[0-9]+_' | sort -u || true)
  NUEVOS=$(comm -23 <(echo "$AQUI") <(echo "$EN_MAIN") || true)
fi

if [ -n "$NUEVOS" ]; then
  MERGED=$(git branch -r --merged origin/main 2>/dev/null | tr -d ' ' || true)
  CHOQUES=""

  for ref in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null); do
    case "$ref" in origin/HEAD|origin/main) continue;; esac
    echo "$MERGED" | grep -qx "$ref" && continue

    AJENOS=$(git ls-tree -r --name-only "$ref" -- supabase/migrations supabase/tests 2>/dev/null \
             | xargs -n1 basename 2>/dev/null | grep -E '^[0-9]+_' || true)
    [ -z "$AJENOS" ] && continue

    while read -r mio; do
      [ -z "$mio" ] && continue
      num=$(echo "$mio" | sed -E 's/^([0-9]+)_.*/\1/')
      # Mismo número y nombre distinto = choque. Mismo nombre = el mismo trabajo.
      otro=$(echo "$AJENOS" | grep -E "^${num}_" | grep -vFx "$mio" | head -1 || true)
      if [ -n "$otro" ]; then
        CHOQUES="${CHOQUES}    ${num} · tuyo «${mio}»
         ya usado en ${ref} por «${otro}»
"
      fi
    done <<< "$NUEVOS"
  done

  if [ -n "$CHOQUES" ]; then
    rojo "✗ Un número que agregas ya está reclamado por otra rama sin fusionar:"
    printf "%s" "$CHOQUES"
    gris "  Renumera lo tuyo: lo que ya está empujado tiene prioridad."
    FALLO=1
  fi
fi

# ── 3 · Huecos: se avisan, no se bloquean ──────────────────────────────────
HUECOS=$(ls supabase/migrations | sed -E 's/^([0-9]+)_.*/\1/' | grep -E '^[0-9]+$' | sort -n \
  | awk 'NR>1 && $1+0 != prev+1 { for (i=prev+1; i<$1+0; i++) printf "%04d ", i } { prev=$1+0 }')
if [ -n "$HUECOS" ]; then
  ambar "⚠ Huecos en las migraciones: $HUECOS"
  gris "  Un hueco puede ser algo aplicado en producción que nunca llegó al repo."
  gris "  No bloquea: la 0031 y la 0033 faltan a propósito (viven fuera de git por PII)."
fi

if [ "$FALLO" = "1" ]; then
  echo ""
  gris "  Para saltarlo a propósito:  git push --no-verify"
  exit 1
fi

exit 0
