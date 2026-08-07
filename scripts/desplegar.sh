#!/bin/bash
# Publicar Dynamic, con las revisiones hechas antes y no después.
#
#   ./scripts/desplegar.sh          vista previa (dirección temporal)
#   ./scripts/desplegar.sh prod     producción — pide escribir "publicar"
#
# `CLAUDE.md` describía este script desde julio, pero nunca existió: cada
# despliegue salía con `npx vercel` a pelo, sin ninguna de las verificaciones
# que el documento prometía.
#
# QUÉ VERIFICA, y por qué cada una:
#   1. No hay cambios sin guardar  → se publicaría algo que no está en git y
#      nadie podría reconstruir después qué se subió.
#   2. GitHub está al día          → si el commit no está en el remoto, las
#      pruebas de GitHub nunca corrieron sobre él.
#   3. Las pruebas de ESE commit pasaron → incluidas las de base de datos
#      (pgTAP), que no corren en esta Mac sin Docker.
#
# En una urgencia real esto se salta con `npx vercel --prod` directo. Que se
# pueda saltar a propósito es parte del diseño; que se salte sin querer, no.

set -euo pipefail
cd "$(dirname "$0")/.."

PROD=false
[ "${1:-}" = "prod" ] && PROD=true

rojo()  { printf "\033[31m%s\033[0m\n" "$1"; }
verde() { printf "\033[32m%s\033[0m\n" "$1"; }
gris()  { printf "\033[90m%s\033[0m\n" "$1"; }

echo ""
if $PROD; then echo "Desplegando a PRODUCCIÓN"; else echo "Desplegando una vista previa"; fi
echo ""

# ── 1 · Nada sin guardar ────────────────────────────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
  rojo "✗ Hay cambios sin guardar."
  gris "  Publicar ahora subiría código que no está en git y después nadie"
  gris "  podría saber qué se subió. Haz commit primero:"
  git status --short | head -10
  exit 1
fi
verde "✓ Todo guardado en git."

# ── 2 · GitHub al día ───────────────────────────────────────────────────────
RAMA=$(git rev-parse --abbrev-ref HEAD)
git fetch origin "$RAMA" --quiet 2>/dev/null || true
PENDIENTES=$(git rev-list --count "origin/$RAMA..HEAD" 2>/dev/null || echo "0")
if [ "$PENDIENTES" != "0" ]; then
  rojo "✗ Hay $PENDIENTES commit(s) que GitHub no tiene."
  gris "  Las pruebas de GitHub no corrieron sobre este código. Sube primero:"
  gris "    git push"
  exit 1
fi
verde "✓ GitHub está al día."

# ── 2b · Y al día con main ──────────────────────────────────────────────────
# El paso 2 comprueba que TU RAMA esté al día con SU PROPIO origin. Eso no dice
# nada de si tu rama está al día respecto de `main`, y ahí estuvo la trampa del
# 2026-08-06: se desplegó una rama nacida de un `main` de tres horas antes. El
# script imprimió sus tres ✓ verdes, el deploy salió limpio, y producción se
# quedó sin 25 commits —la pantalla de liquidación por cese entre ellos— hasta
# que alguien miró por otro motivo. Un freno que da luz verde en el caso que
# tenía que frenar es peor que no tenerlo: se confía en él.
#
# Se compara contra `origin/main` y no contra el `main` local, porque el local
# puede llevar días sin actualizar y es justo lo que no queremos suponer.
git fetch origin main --quiet 2>/dev/null || true
if git rev-parse --verify --quiet origin/main >/dev/null; then
  if ! git merge-base --is-ancestor origin/main HEAD; then
    DETRAS=$(git rev-list --count HEAD..origin/main)
    rojo "✗ Esta rama no contiene main: le faltan $DETRAS commit(s)."
    gris "  Publicar ahora dejaría producción SIN ese trabajo. Tráelo primero:"
    gris "    git merge origin/main"
    gris "  Y si de verdad quieres publicar una rama vieja a propósito:"
    gris "    npx vercel --prod"
    exit 1
  fi
  verde "✓ La rama contiene todo lo que hay en main."
else
  gris "· No hay origin/main con qué comparar. Se sigue igual."
fi

# ── 3 · Las pruebas de ESTE commit ──────────────────────────────────────────
# OJO CON EL jq. La versión anterior era `.[0] | if .status != "completed" …`, y
# sobre un arreglo VACÍO `.[0]` da null: `null.status` es null, `null != "completed"`
# es cierto, y devolvía "corriendo". O sea que «no hay ninguna corrida» se
# reportaba como «todavía están corriendo», y la rama `""` de abajo —escrita justo
# para ese caso— era inalcanzable. El workflow solo se dispara en `main`, así que
# desplegar desde cualquier otra rama se bloqueaba para siempre.
# Encontrado el 2026-08-05 intentando desplegar desde una rama de trabajo.
COMMIT=$(git rev-parse HEAD)
if command -v gh >/dev/null 2>&1; then
  ESTADO=$(gh run list --commit "$COMMIT" --limit 1 --json conclusion,status \
             --jq 'if length == 0 then "" else (.[0] | if .status != "completed" then "corriendo" else .conclusion end) end' 2>/dev/null || echo "")
  case "$ESTADO" in
    success)   verde "✓ Las pruebas de GitHub pasaron (incluidas las de base de datos)." ;;
    corriendo) rojo "✗ Las pruebas de GitHub todavía están corriendo."
               gris "  Espera a que terminen: gh run watch"; exit 1 ;;
    failure)   rojo "✗ Las pruebas de GitHub FALLARON en este commit."
               gris "  Míralas: gh run list --commit $COMMIT"; exit 1 ;;
    "")        gris "· No se encontró una corrida de GitHub para este commit."
               gris "  Puede que aún no haya arrancado. Se sigue igual." ;;
    *)         gris "· Estado de las pruebas: $ESTADO. Se sigue igual." ;;
  esac
else
  gris "· 'gh' no está instalado: no se pudieron verificar las pruebas de GitHub."
  gris "  Se sigue igual, pero sin esa red."
fi

# ── 4 · Producción pide confirmación escrita ────────────────────────────────
if $PROD; then
  echo ""
  gris "Esto va a cambiar lo que ve el equipo en cayla-dynamic.vercel.app"
  printf "Escribe \033[1mpublicar\033[0m para confirmar: "
  read -r RESPUESTA
  if [ "$RESPUESTA" != "publicar" ]; then
    echo ""
    gris "Cancelado. No se publicó nada."
    exit 0
  fi
fi

echo ""
if $PROD; then
  npx vercel --prod --yes
else
  npx vercel --yes
fi
