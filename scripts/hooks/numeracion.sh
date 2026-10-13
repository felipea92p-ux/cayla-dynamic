#!/usr/bin/env bash
# Freno de numeración: que dos trabajos no reclamen el mismo número.
#
# TIENE QUE CORRER EN BASH 3.2. macOS trae de fábrica el de 2007 en `/bin/bash`
# —Apple lo congeló ahí por licencia GPLv3—, y en una Mac de desarrollo sin nada
# instalado aparte es el único que hay. Por eso este script no usa nada de bash 4+:
# ni `declare -A` (mapas asociativos), ni `mapfile`, ni `${x,,}`.
# `probar-numeracion.sh` lo vigila, y lo vigila aparte de los casos porque en una
# Mac que SÍ tenga bash 5 los casos pasarían igual con `declare -A`.
#
# Es la misma falla dos veces, y la primera «se arregló» mal. El 2026-09-08 un
# push de migración se frenó con «declare: -A: invalid option» —nada que ver con
# una colisión de números— y se cambió `#!/bin/bash` por `#!/usr/bin/env bash`,
# que solo ayuda si la Mac tiene otro bash instalado (`brew install bash`). La
# Mac de desarrollo no lo tiene: el 2026-10-10 volvió a pasar, idéntico. Un
# arreglo que depende de algo instalado en la máquina falla en la que no lo
# tiene. Y se escondía bien: el bloque con `declare -A` solo corre cuando el
# push AGREGA un archivo numerado, así que todos los demás pushes lo saltaban y
# el hook parecía sano. `env bash` se queda —es inofensivo y deja usar un bash
# más nuevo si lo hay—, pero ya no es lo que lo hace funcionar.
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
NUEVOS=""
if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  # `sed 's#.*/##'` y no `xargs -n1 basename`: son el mismo resultado —el
  # nombre del archivo, sin la carpeta— pero `xargs -n1` arranca un proceso
  # `basename` POR LÍNEA. `supabase/migrations` + `supabase/tests` ya suman
  # más de 600 archivos, así que esa única línea eran más de 600 procesos
  # nuevos, y `sed` hace lo mismo en un solo proceso para todo el listado.
  # Medido el 2026-09-08: esta línea sola, tal como estaba, se quedaba varios
  # segundos colgada — y el mismo patrón se repetía más abajo, una vez por
  # cada rama sin fusionar. En Windows/Git Bash cada proceso nuevo cuesta
  # mucho más que en Linux —y con antivirus escaneando cada `.exe`, más
  # todavía—, así que esto era, con diferencia, lo más caro de todo el hook.
  EN_MAIN=$(git ls-tree -r --name-only origin/main -- supabase/migrations supabase/tests 2>/dev/null \
            | sed 's#.*/##' | sort -u || true)
  AQUI=$(git diff --name-only --diff-filter=A --no-renames origin/main..HEAD \
           -- supabase/migrations supabase/tests 2>/dev/null \
         | sed 's#.*/##' | grep -E '^[0-9]+_' | sort -u || true)
  NUEVOS=$(comm -23 <(echo "$AQUI") <(echo "$EN_MAIN") || true)
fi

if [ -n "$NUEVOS" ]; then
  CHOQUES=""

  # Antes esto recorría TODAS las ramas remotas y descartaba las ya fusionadas
  # una por una, con un `echo | grep` por rama — dos procesos más, solo para
  # decidir si saltarla. `--no-merged` le pide a git esa misma lista de una
  # sola vez: una rama ya fusionada a `origin/main` no puede tener un choque
  # de números que `main` no tenga ya resuelto, así que ni hace falta mirarla
  # — ni con el grep de descarte, ni con el `ls-tree` de después.
  #
  # Medido el 2026-09-08 en este repo: 147 ramas remotas, 108 ya fusionadas y
  # nunca borradas. `--no-merged` deja el bucle en las ~40 que sí importan.

  # Lo que agrega este push, guardado de dos formas que no piden arreglos
  # asociativos (bash 4+, ver el encabezado) y que valen igual en bash 3.2 y
  # en zsh. Hace falta distinguir «mismo número, mismo trabajo» (se ignora) de
  # «mismo número, archivo distinto» (choque de verdad) sin volver a forkear
  # nada, y las dos preguntas son una expansión de bash cada una:
  #
  #   · `MIOS`: los nombres exactos, uno por línea y con un salto de línea
  #     también delante y detrás. «¿este nombre es uno de los míos?» es un
  #     `case` con `*"${NL}nombre${NL}"*`, y «¿cuál es mi archivo con este
  #     número?» es cortar la cadena en `${NL}0402_`. El salto de línea de cada
  #     lado es lo que impide que `0402_` case dentro de `10402_x`, o que un
  #     nombre case como prefijo de otro más largo. Y lo entrecomillado dentro
  #     de un `case` o de un `${x#…}` es literal, así que un nombre con `[` o
  #     `*` no se vuelve patrón.
  #   · `NUMS_REGEX`: solo los números. Deja filtrar cada rama de un tirón, en
  #     vez de traer sus 600+ archivos numerados para compararlos uno por uno.
  #     `${mio%%_*}` corta en el primer «_», y un nombre de archivo de este
  #     repo siempre empieza por «NNNN_».
  #
  # Con un `declare -A` zsh tampoco era una salida: guarda las comillas dentro
  # de la clave (`mapa["$num"]=…` crea la clave `"0402"`) y nunca la vuelve a
  # encontrar, así que el choque se perdía sin ningún error.
  NL=$'\n'
  MIOS="${NL}${NUEVOS}${NL}"
  NUMS_REGEX=""
  while IFS= read -r mio; do
    [ -z "$mio" ] && continue
    NUMS_REGEX="${NUMS_REGEX:+$NUMS_REGEX|}${mio%%_*}"
  done <<< "$NUEVOS"

  # Esto era, con diferencia, lo más caro de todo el hook: por cada una de las
  # ~40 ramas, un `while read` volvía a forkear `echo`/`sed`/`grep`/`head` por
  # cada archivo nuevo de ESTE push, comparando contra los 600+ archivos de
  # ESA rama cada vez. En Windows/Git Bash cada proceso nuevo cuesta mucho más
  # que en Linux —y con antivirus escaneando cada `.exe`, más todavía—, así
  # que decenas de miles de forks de sobra se notaban: un push real llegó a
  # tardar varios MINUTOS parado exactamente acá.
  #
  # Ahora, por rama: UN git ls-tree, UN sed, y UN grep que ya filtra solo a
  # los números que importan (`NUMS_REGEX`) — así que lo normal es que
  # `AJENOS` salga vacío y la rama se descarte sin más. Si algo coincide,
  # comparar el nombre exacto son dos expansiones sobre `MIOS` y un `case` —
  # cero procesos nuevos.
  for ref in $(git branch -r --no-merged origin/main 2>/dev/null | tr -d ' '); do
    [ -z "$NUMS_REGEX" ] && break
    AJENOS=$(git ls-tree -r --name-only "$ref" -- supabase/migrations supabase/tests 2>/dev/null \
             | sed 's#.*/##' | grep -E "^(${NUMS_REGEX})_" || true)
    [ -z "$AJENOS" ] && continue

    while IFS= read -r otro; do
      [ -z "$otro" ] && continue
      # Mismo nombre exacto = el mismo trabajo, que ya viajó en un push anterior.
      case "$MIOS" in *"${NL}${otro}${NL}"*) continue ;; esac
      # Mismo número y nombre distinto = choque. `AJENOS` ya viene filtrado a
      # MIS números, así que siempre hay un archivo mío con este número que
      # nombrar. Sin comillas externas a propósito: lo de adentro es el patrón.
      num="${otro%%_*}"
      antes="${NL}${num}_"
      resto=${MIOS#*"$antes"}
      mio=${num}_${resto%%"$NL"*}
      CHOQUES="${CHOQUES}    ${num} · tuyo «${mio}»
         ya usado en ${ref} por «${otro}»
"
    done <<< "$AJENOS"
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
