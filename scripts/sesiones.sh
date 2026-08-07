#!/bin/bash
# Qué sesiones de Claude están vivas sobre este repo, y cuáles están tocando algo.
#
# POR QUÉ EXISTE. El 2026-08-06 pregunté por las sesiones activas y la lista que
# devuelve la app dijo que NINGUNA estaba corriendo. Había dos. El campo que
# informa eso se queda viejo; los procesos del sistema no.
#
# Importa porque este repo se trabaja con varias sesiones a la vez sobre el MISMO
# árbol y el MISMO Postgres local. Saber quién está vivo es lo que decide si
# puedes hacer `db reset`, editar `docs/estado.md` o fiarte de un `git status` —
# ese día el estado de la rama cambió tres veces en un minuto porque otra sesión
# estaba rebasando por debajo.
#
#   ./scripts/sesiones.sh

set -uo pipefail
cd "$(dirname "$0")/.."

verde() { printf "\033[32m%s\033[0m\n" "$1"; }
ambar() { printf "\033[33m%s\033[0m\n" "$1"; }
gris()  { printf "\033[90m%s\033[0m\n" "$1"; }

# Cuál de todas es la sesión desde la que se corre esto. Se averigua subiendo por
# los padres de este proceso hasta encontrar un `claude`: preguntar por $$ no
# sirve, porque $$ es este script, no la sesión que lo lanzó.
ANCESTROS=""
p=$$
for _ in 1 2 3 4 5 6 7 8 9 10; do
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  [ -z "$p" ] || [ "$p" = "0" ] || [ "$p" = "1" ] && break
  ANCESTROS="${ANCESTROS}${p} "
done

echo ""
echo "SESIONES DE CLAUDE VIVAS"
echo ""

# Traduce el formato de `ps`: «02-21:37:49» son 2 días y 21 horas. Nadie tiene por
# qué descifrar eso para saber si una sesión lleva demasiado abierta.
edad() {
  case "$1" in
    *-*) printf '%dd %dh' "${1%%-*}" "$(printf '%s' "${1#*-}" | cut -d: -f1 | sed 's/^0//;s/^$/0/')" ;;
    *:*:*) printf '%dh %dm' "$(printf '%s' "$1" | cut -d: -f1 | sed 's/^0//;s/^$/0/')" \
                            "$(printf '%s' "$1" | cut -d: -f2 | sed 's/^0//;s/^$/0/')" ;;
    *) printf '%dm' "$(printf '%s' "$1" | cut -d: -f1 | sed 's/^0//;s/^$/0/')" ;;
  esac
}

# Cada sesión levanta dos procesos (el lanzador y el real) con el mismo
# `--resume=<uuid>`. Se cuenta una sola vez por uuid.
#
# Y lo que de verdad importa de cada una NO es la ruta, es en cuál de las TRES
# situaciones está — que es lo que decide si te puede pisar el trabajo:
#   · esta misma carpeta → comparte índice de git, árbol Y Postgres local. Peligrosa.
#   · un worktree        → tiene su copia del árbol; solo comparte Postgres y remoto.
#   · otro proyecto      → no comparte nada.
# La versión anterior imprimía la ruta cruda y las tres se leían igual: un «.» no
# le dice a nadie que esa sesión puede reescribirle el archivo que tiene abierto.
VISTAS=""
N=0; AQUI=0; EN_WT=0; OTROS=0
while read -r pid tiempo resto; do
  uuid=$(printf '%s' "$resto" | grep -oE '\-\-resume=[0-9a-f-]+' | head -1 | cut -d= -f2)
  [ -z "$uuid" ] && continue
  printf '%s' "$VISTAS" | grep -q "$uuid" && continue
  VISTAS="${VISTAS}${uuid} "
  N=$((N + 1))

  dir=$(lsof -p "$pid" -a -d cwd -Fn 2>/dev/null | grep '^n' | sed 's/^n//' | head -1)

  case "$dir" in
    "")            donde="(no se pudo leer)";        color=gris ;;
    "$PWD")        donde="ESTA CARPETA — comparte todo contigo"; color=ambar; AQUI=$((AQUI+1)) ;;
    "$PWD"/.claude/worktrees/*)
                   donde="worktree ${dir##*/}";      color=verde; EN_WT=$((EN_WT+1)) ;;
    "$PWD"/*)      donde="subcarpeta ${dir#$PWD/}";  color=ambar; AQUI=$((AQUI+1)) ;;
    *)             donde="otro proyecto (${dir##*/})"; color=gris;  OTROS=$((OTROS+1)) ;;
  esac

  if printf '%s' "$ANCESTROS" | grep -qw "$pid"; then
    donde="$donde  ← ESTA, la que estás usando"
    color=verde
  fi

  $color "$(printf "  %-7s  abierta hace %-8s  %s" "$pid" "$(edad "$tiempo")" "$donde")"
done < <(ps ax -o pid=,etime=,command= 2>/dev/null | grep -E "MacOS/claude " | grep -v disclaimer)

if [ "$N" = "0" ]; then
  gris "  ninguna."
else
  echo ""
  if [ "$AQUI" -gt 1 ]; then
    ambar "  $AQUI sesiones están en ESTA carpeta (contando la tuya)."
    gris  "  Comparten el índice de git, el árbol de trabajo y el Postgres local:"
    gris  "  cualquiera puede reescribir un archivo que tú tengas a medias, o meter"
    gris  "  lo suyo dentro de tu commit. Cierra las que ya no uses."
  elif [ "$AQUI" = "1" ]; then
    verde "  Eres la única en esta carpeta. Nadie te va a pisar."
  fi
  [ "$EN_WT" -gt 0 ] && gris "  $EN_WT en su propio worktree: tienen su copia del árbol, no te pisan archivos."
  [ "$OTROS" -gt 0 ] && gris "  $OTROS en otro proyecto: no comparten nada con este repo."
fi
echo ""
gris "  Ojo: la lista de sesiones de la app tiene un campo «isRunning» que se"
gris "  queda viejo. Estos son los procesos de verdad."

echo ""
echo "WORKTREES (cada una puede tener su propia sesión)"
echo ""
git worktree list | sed 's/^/  /'

echo ""
echo "¿ALGUIEN ESTÁ ESCRIBIENDO?"
echo ""
RECIENTES=$(find . -type f -mmin -10 \
  -not -path './.git/*' -not -path '*/node_modules/*' \
  -not -path './supabase/.temp/*' -not -path './.claude/worktrees/*' \
  -not -name '*.tsbuildinfo' -not -name '.DS_Store' 2>/dev/null | head -10)

if [ -n "$RECIENTES" ]; then
  ambar "  Sí — escrito en los últimos 10 minutos:"
  printf '%s\n' "$RECIENTES" | sed 's/^/    /'
  echo ""
  gris "  Con esto en movimiento, no hagas \`supabase db reset\` ni edites"
  gris "  docs/estado.md: le pisas el trabajo a quien esté a media tarea."
else
  verde "  No — nadie ha escrito en los últimos 10 minutos."
fi

echo ""
echo "RAMA"
echo ""
git status -sb 2>/dev/null | head -1 | sed 's/^/  /'
gris "  Si esto cambia entre dos ejecuciones, hay otra sesión operando git."
echo ""
