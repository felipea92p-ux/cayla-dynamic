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
#   1. Dos archivos con el mismo número en el árbol de trabajo. Acá SÍ se mira el
#      directorio entero, commiteado o no: dos archivos con el mismo número
#      revientan tu propio `db reset`, venga de donde venga el segundo.
#   2. Un número NUEVO —que agregan TUS COMMITS— que otra rama sin fusionar ya
#      usa para otra cosa. Esta mira los commits, no el directorio: ver la nota
#      larga en la comprobación 2.
#
# QUÉ SOLO AVISA
#   Los huecos, y solo los que nadie explicó todavía. Los ya investigados viven
#   en `huecos-conocidos.txt` con su razón al lado; se sacan del aviso para que
#   lo que quede signifique algo. Un hueco se mira, no se bloquea: durante una
#   renumeración legítima existe por unos segundos.
#
# Se salta con `git push --no-verify`.

set -euo pipefail

# Al repo que se está empujando, no al que guarda este archivo.
#
# `core.hooksPath` de un worktree resuelve al repo PRINCIPAL, así que git ejecuta
# la copia de allá y `$0` apunta allá. Orientarse por `$0` hacía que un push desde
# `.claude/worktrees/loquesea` revisara `main` del repo principal en vez de la rama
# que se está empujando: acusaba por archivos ajenos sin commitear y —lo grave—
# NUNCA revisó los números de ninguna rama de worktree, que es donde ocurre casi
# todo el trabajo en paralelo. Un freno que mira el sitio equivocado no avisa de
# menos: avisa de otra cosa.
#
# `--show-toplevel` da la raíz del worktree real se ejecute desde donde se
# ejecute, porque git corre los hooks con el directorio actual dentro de ESE
# árbol. Si no hubiera repo, se cae al método viejo en vez de quedarse a medias.
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || true)"
cd "${RAIZ:-$(dirname "$0")/../..}"

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
# Nuevo = lo que TUS COMMITS agregan sobre origin/main. Si no hay nada nuevo
# numerado, no se toca la red y el hook termina de inmediato.
#
# Ojo con la diferencia entre esto y un `ls`, que es la que hacía inservible al
# hook: hasta el 2026-08-06 esta línea listaba el DIRECTORIO DE TRABAJO, así que
# los archivos sin commitear de otra sesión contaban como tuyos. El hook te
# acusaba —«renumera lo tuyo»— por un choque de archivos que tu push ni siquiera
# llevaba, y la única salida era `--no-verify`. Es el peor modo de fallar que
# puede tener un freno: castigar por algo ajeno enseña a saltárselo.
#
# `--no-renames` es a propósito: renumerar un archivo tiene que contar como un
# número nuevo, que es exactamente lo que hay que verificar.
#
# Lo que se pierde: un archivo numerado sin commitear ya no se compara contra las
# otras ramas. No es un hueco real — todavía no sale de esta máquina, y para el
# momento de escribirlo está `siguiente-numero.sh`, que sí mira el directorio de
# trabajo. Y el caso grave (dos archivos con el mismo número acá, que revienta tu
# propio `db reset`) lo sigue cazando la comprobación 1, commiteados o no.
#
# ── POR QUÉ `sed` Y NO `basename` ───────────────────────────────────────────
#
# Estas tres líneas decían `| xargs -n1 basename`, que lanza UN PROCESO POR
# ARCHIVO. Son 621 archivos entre `migrations` y `tests`, y el bucle de abajo
# los recorre una vez por cada rama remota sin fusionar — hoy 45 de 152. En
# Linux eso se nota; en Windows, donde crear un proceso cuesta un orden de
# magnitud más, es la diferencia entre un hook y un castigo.
#
# Medido el 2026-09-08 en la máquina de Dany, sobre `origin/main`:
#
#     | xargs -n1 basename   39,98 s por rama   →  ~30 min de push
#     | sed 's|.*/||'         0,14 s por rama   →  ~6 s de push
#
# 287 veces, y la salida es IDÉNTICA byte por byte (comprobado con `diff`
# sobre los 621 nombres, no supuesto). `basename` sobre una lista de rutas sin
# barra final es exactamente «quitar todo hasta la última barra», que es lo que
# hace ese `sed` — el mismo idioma que `que-falta-pegar.sh` ya usaba al lado.
#
# Importa más de lo que parece: un push de media hora enseña a usar
# `--no-verify`, y entonces el hook deja de existir el día que de verdad haga
# falta. Un freno lento se desactiva solo.
NUEVOS=""
if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  EN_MAIN=$(git ls-tree -r --name-only origin/main -- supabase/migrations supabase/tests 2>/dev/null \
            | sed 's|.*/||' | sort -u || true)
  AQUI=$(git diff --name-only --diff-filter=A --no-renames origin/main..HEAD \
           -- supabase/migrations supabase/tests 2>/dev/null \
         | sed 's|.*/||' | grep -E '^[0-9]+_' | sort -u || true)
  NUEVOS=$(comm -23 <(echo "$AQUI") <(echo "$EN_MAIN") || true)
fi

if [ -n "$NUEVOS" ]; then
  MERGED=$(git branch -r --merged origin/main 2>/dev/null | tr -d ' ' || true)
  CHOQUES=""

  for ref in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null); do
    case "$ref" in origin/HEAD|origin/main) continue;; esac
    echo "$MERGED" | grep -qx "$ref" && continue

    AJENOS=$(git ls-tree -r --name-only "$ref" -- supabase/migrations supabase/tests 2>/dev/null \
             | sed 's|.*/||' | grep -E '^[0-9]+_' || true)
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

# ── 3 · Huecos: solo los que NADIE explicó todavía ─────────────────────────
# Avisa, no bloquea: en medio de una renumeración legítima un hueco existe por
# unos segundos, y frenar el push por eso sería fricción sin motivo.
#
# Los ya investigados viven en `huecos-conocidos.txt`, con su razón escrita al
# lado. Se sacan de la lista para que lo que quede signifique algo: hasta hoy
# esto imprimía los cinco huecos en cada push, cuatro de ellos explicados y
# ninguno accionable. Un aviso que dice siempre lo mismo se deja de leer, y el
# día que aparezca uno de verdad va a estar en esa misma línea que nadie mira.
# Del árbol que se revisa, no del que guarda el script: una rama puede explicar un
# hueco que en `main` todavía no está anotado.
CONOCIDOS="scripts/hooks/huecos-conocidos.txt"

HUECOS=$(ls supabase/migrations | sed -E 's/^([0-9]+)_.*/\1/' | grep -E '^[0-9]+$' | sort -n \
  | awk 'NR>1 && $1+0 != prev+1 { for (i=prev+1; i<$1+0; i++) printf "%04d\n", i } { prev=$1+0 }')

# Un hueco conocido que YA NO ES HUECO —porque alguien creó ese archivo— deja
# una línea muerta en el .txt. Se avisa, porque una lista de excepciones que
# nadie limpia termina silenciando un número que volvió a estar en uso.
SOBRAN=""
NUEVOS_HUECOS=""
if [ -f "$CONOCIDOS" ]; then
  LISTA=$(grep -vE '^\s*(#|$)' "$CONOCIDOS" | awk '{print $1}' || true)
  for n in $HUECOS; do
    echo "$LISTA" | grep -qx "$n" || NUEVOS_HUECOS="${NUEVOS_HUECOS}${n} "
  done
  for n in $LISTA; do
    echo "$HUECOS" | grep -qx "$n" || SOBRAN="${SOBRAN}${n} "
  done
else
  NUEVOS_HUECOS=$(echo "$HUECOS" | tr '\n' ' ')
  gris "  (no se encontró $CONOCIDOS: se avisan todos los huecos)"
fi

# Un número disparatado —un 0900 donde iba un 0090— no deja un hueco: deja
# ochocientos. La lista completa llena la pantalla y **sepulta el mensaje rojo**
# de arriba, que es el que hace fallar el push. Comprobado el 2026-08-07
# probando la comprobación 2 con un 0900: el «✗ ya está reclamado por otra rama»
# quedó enterrado bajo 720 números.
#
# Por eso a partir de doce se resume. El caso normal —dos o tres huecos, que es
# lo que hay— sigue viéndose entero, y el caso raro deja de tapar lo importante:
# ochocientos huecos seguidos no son ochocientos problemas, son UN número mal
# escrito, y lo que hay que decir es eso.
if [ -n "$NUEVOS_HUECOS" ]; then
  CUANTOS=$(echo "$NUEVOS_HUECOS" | wc -w | tr -d ' ')
  if [ "$CUANTOS" -gt 12 ]; then
    PRIMERO=$(echo "$NUEVOS_HUECOS" | awk '{print $1}')
    ULTIMO=$(echo "$NUEVOS_HUECOS" | awk '{print $NF}')
    ambar "⚠ $CUANTOS huecos sin explicar, del $PRIMERO al $ULTIMO."
    gris "  Tantos seguidos casi nunca son tantos problemas: suele ser UN archivo"
    gris "  con un número muy por encima del resto. Míralo con:"
    gris "      ls supabase/migrations | tail -3"
  else
    ambar "⚠ Hueco sin explicar en las migraciones: $NUEVOS_HUECOS"
    gris "  Puede ser algo aplicado en producción que nunca llegó al repo."
    gris "  Compruébalo con ./scripts/que-falta-pegar.sh (genera la consulta al día);"
    gris "  si resulta explicado, anótalo en scripts/hooks/huecos-conocidos.txt."
  fi
fi

if [ -n "$SOBRAN" ]; then
  ambar "⚠ Estos números ya no son huecos y siguen en huecos-conocidos.txt: $SOBRAN"
  gris "  Borra esas líneas: si no, el día que ese número se duplique nadie se entera."
fi

if [ -z "$NUEVOS_HUECOS" ] && [ -z "$SOBRAN" ] && [ "$FALLO" = "0" ]; then
  gris "  numeración sin novedad."
fi

if [ "$FALLO" = "1" ]; then
  echo ""
  gris "  Para saltarlo a propósito:  git push --no-verify"
  exit 1
fi

exit 0
