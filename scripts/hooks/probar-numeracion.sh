#!/usr/bin/env bash
# Prueba de `numeracion.sh` contra un repositorio de mentira.
#
#   scripts/hooks/probar-numeracion.sh [ruta/a/numeracion.sh]
#
# POR QUÉ EXISTE. El 2026-10-10 el hook de numeración se negó a dejar pasar un
# push legítimo con «declare: -A: invalid option»: usaba mapas asociativos (bash
# 4+) y la Mac de desarrollo solo tiene el bash 3.2 de Apple. Ya había pasado
# el 2026-09-08 y se había «arreglado» cambiando el shebang a `env bash`, o sea
# suponiendo que la máquina tenía otro bash instalado. Nadie lo notó antes
# porque el bloque con `declare -A` solo corre cuando el push AGREGA un archivo
# numerado: todos los demás pushes lo saltan y el hook parecía sano.
#
# Esa es la forma de fallar que esto cubre. Corre cada caso con CADA intérprete
# que haya —/bin/bash, zsh, el `bash` del PATH si es otro, y la ruta directa por
# el shebang, que es como lo llama `pre-push`— y mira dos cosas: el resultado
# (código de salida y mensaje) y que no salga ningún error del intérprete.
#
# Incluye casos que DEBEN bloquear, no solo casos que pasan: un freno que da el
# push por bueno cuando falla en silencio se ve idéntico a uno que funciona.
#
# Y comprueba por separado que el script no use nada de bash 4+. Esa comprobación
# es la que vale en una Mac que SÍ tenga bash 5: ahí los casos pasarían igual con
# `declare -A`, y el defecto volvería a esperar a la máquina que no lo tiene.
#
# No toca el repo real: todo ocurre en un directorio temporal, con la
# configuración global de git apagada (si no, el `core.hooksPath` de esta Mac
# dispararía el `pre-push` verdadero con cada push de la prueba).

set -u

AQUI="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-$AQUI/numeracion.sh}"
[ -f "$SCRIPT" ] || { echo "No existe $SCRIPT" >&2; exit 2; }
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=prueba GIT_AUTHOR_EMAIL=prueba@example.invalid
export GIT_COMMITTER_NAME=prueba GIT_COMMITTER_EMAIL=prueba@example.invalid

BIEN=0
MAL=0

# ── Armado ───────────────────────────────────────────────────────────────────
# `origin/main` trae las migraciones 0001 y 0002 y la prueba 01. Sin huecos, para
# que el aviso de huecos no ensucie lo que se mira.
montar() {
  rm -rf "$TMP/origin.git" "$TMP/work"
  git init -q --bare -b main "$TMP/origin.git"
  git init -q -b main "$TMP/work"
  (
    cd "$TMP/work" || exit 1
    git remote add origin "$TMP/origin.git"
    mkdir -p supabase/migrations supabase/tests scripts/hooks
    : > scripts/hooks/huecos-conocidos.txt
    echo x > supabase/migrations/0001_base.sql
    echo x > supabase/migrations/0002_segunda.sql
    echo x > supabase/tests/01_base.test.sql
    git add -A
    git commit -q -m base
    git push -q origin main
  )
}

# Una rama de otra sesión, ya empujada y sin fusionar. Los archivos se dan
# relativos a `supabase/`: migrations/0003_x.sql, tests/02_x.test.sql…
rama_ajena() {
  local rama="$1" f
  shift
  (
    cd "$TMP/work" || exit 1
    git checkout -q -b "$rama" main
    for f in "$@"; do echo "$f" > "supabase/$f"; done
    git add -A
    git commit -q -m "$rama"
    git push -q origin "$rama"
    git checkout -q main
  )
}

# La rama que se está empujando: lo que agrega sobre `origin/main` es lo «nuevo».
mi_rama() {
  local f
  (
    cd "$TMP/work" || exit 1
    git checkout -q -b mia main
    for f in "$@"; do echo "$f" > "supabase/$f"; done
    git add -A
    git commit -q --allow-empty -m mia
  )
}

# ── Ejecución y veredicto ────────────────────────────────────────────────────
correr() {
  SALIDA="$(cd "$TMP/work" && "$@" 2>&1)"
  CODIGO=$?
}

# evaluar «caso» «código esperado» «+texto que debe salir» «-texto que NO debe salir»…
# `printf '%s'` y no `echo`: la salida lleva barras invertidas que `echo` interpreta.
evaluar() {
  local caso="$1" esperado="$2" falla="" patron
  shift 2
  [ "$CODIGO" = "$esperado" ] || falla="$falla código $CODIGO (esperaba $esperado);"
  for patron in "$@"; do
    case "$patron" in
      +*) printf '%s' "$SALIDA" | grep -qF -- "${patron#+}" || falla="$falla falta «${patron#+}»;" ;;
      -*) if printf '%s' "$SALIDA" | grep -qF -- "${patron#-}"; then falla="$falla sobra «${patron#-}»;"; fi ;;
    esac
  done
  if printf '%s' "$SALIDA" | grep -qE 'invalid option|command not found|syntax error|bad substitution|unbound variable|not an identifier'; then
    falla="$falla error del intérprete;"
  fi

  if [ -z "$falla" ]; then
    BIEN=$((BIEN + 1))
    printf '  \033[32m✓\033[0m %-48s %s\n' "$caso" "$INTERPRETE"
  else
    MAL=$((MAL + 1))
    printf '  \033[31m✗\033[0m %-48s %s\n' "$caso" "$INTERPRETE"
    printf '      %s\n' "$falla"
    printf '%s\n' "$SALIDA" | sed 's/^/      │ /'
  fi
}

# Corre el caso con cada intérprete. Lo que está armado en $TMP/work no se toca
# entre uno y otro: `numeracion.sh` solo lee.
con_cada_interprete() {
  local caso="$1" esperado="$2" i
  shift 2
  for i in $INTERPRETES; do
    INTERPRETE="$i"
    if [ "$i" = "directo" ]; then
      correr "$SCRIPT"
    else
      correr "$i" "$SCRIPT"
    fi
    evaluar "$caso" "$esperado" "$@"
  done
}

INTERPRETES="/bin/bash"
command -v zsh >/dev/null 2>&1 && INTERPRETES="$INTERPRETES zsh"
OTRO_BASH="$(command -v bash || true)"
if [ -n "$OTRO_BASH" ] && [ "$OTRO_BASH" != "/bin/bash" ]; then INTERPRETES="$INTERPRETES $OTRO_BASH"; fi
[ -x "$SCRIPT" ] && INTERPRETES="$INTERPRETES directo"

echo "Probando $SCRIPT"
echo "  bash de Apple: $(/bin/bash --version | head -1)"

# ── 0 · Nada de bash 4+ (los comentarios se ignoran: este mismo archivo cita lo prohibido) ──
PROHIBIDO='declare -A|local -A|typeset -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)\}|\|&|&>>|coproc'
USOS="$(grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -nE "$PROHIBIDO" || true)"
if [ -z "$USOS" ]; then
  BIEN=$((BIEN + 1))
  printf '  \033[32m✓\033[0m %s\n' "no usa nada de bash 4+"
else
  MAL=$((MAL + 1))
  printf '  \033[31m✗\033[0m %s\n' "usa algo que el bash 3.2 de Apple no tiene:"
  printf '%s\n' "$USOS" | sed 's/^/      │ /'
fi

# ── 1 · Nada nuevo: el bloque entero se salta ────────────────────────────────
montar
mi_rama
con_cada_interprete "nada nuevo" 0 "+numeración sin novedad" "-ya está reclamado"

# ── 2 · Lo nuevo no choca con nadie ──────────────────────────────────────────
montar
rama_ajena otra migrations/0004_otra.sql
mi_rama migrations/0003_mia.sql
con_cada_interprete "sin choque" 0 "+numeración sin novedad" "-ya está reclamado"

# ── 3 · El mismo número lo usa OTRO archivo en una rama sin fusionar: DEBE frenar ──
montar
rama_ajena otra migrations/0003_otra.sql
mi_rama migrations/0003_mia.sql
con_cada_interprete "choque de número con otra rama" 1 \
  "+ya está reclamado por otra rama sin fusionar" "+0003_otra.sql" "+0003_mia.sql" "-sin novedad"

# ── 4 · Mismo número Y mismo archivo en otra rama: es el mismo trabajo, se ignora ──
# Es lo que pasa en cada segundo push de una rama: `origin/mia` ya trae lo suyo.
montar
rama_ajena mia-antes migrations/0003_mia.sql
mi_rama migrations/0003_mia.sql
con_cada_interprete "mismo archivo en otra rama" 0 "+numeración sin novedad" "-ya está reclamado"

# ── 5 · Dos números nuevos: uno es el mismo trabajo y el otro es un choque ───
# Que el primero se ignore no puede esconder el segundo, ni acusarse a sí mismo.
montar
rama_ajena mezcla migrations/0003_mia.sql migrations/0004_otra.sql
mi_rama migrations/0003_mia.sql migrations/0004_mia.sql
con_cada_interprete "uno igual y otro en choque" 1 \
  "+0004_otra.sql" "+tuyo «0004_mia.sql»" "-tuyo «0003_mia.sql»" "-sin novedad"

# ── 6 · El choque también se mira en supabase/tests ──────────────────────────
montar
rama_ajena pruebas tests/02_otra.test.sql
mi_rama tests/02_mia.test.sql
con_cada_interprete "choque en supabase/tests" 1 \
  "+ya está reclamado por otra rama sin fusionar" "+02_otra.test.sql" "-sin novedad"

echo
if [ "$MAL" -eq 0 ]; then
  printf '\033[32m%s bien, ninguna mal.\033[0m\n' "$BIEN"
  exit 0
fi
printf '\033[31m%s bien, %s mal.\033[0m\n' "$BIEN" "$MAL"
exit 1
