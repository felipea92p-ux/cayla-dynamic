#!/bin/sh
# Una sesión de Claude no fusiona (ni programa la fusión de) un PR sin dejar un
# comentario que diga quién, por qué y qué se verificó.
#
# POR QUÉ EXISTE
#
# Fusionar un PR a `main` ES publicar en producción (ver CLAUDE.md). El
# 2026-10-06 el #505 se fusionó 10 minutos después de abrirse, con la cuenta de
# Felipe, y no había forma de saber si lo hizo él o una sesión: todas las
# sesiones de Claude trabajan con esa cuenta, así que para GitHub son la misma
# persona. La fusión estuvo bien hecha —por PR, con las pruebas en verde— y
# aun así quedó una pregunta sin respuesta: ¿alguien lo pidió?
#
# Este freno no impide fusionar: obliga a dejar rastro ANTES. El comentario es
# la única prueba que sobrevive a la sesión, que se cierra y se olvida.
#
# QUÉ PROMETE
#   Frena `gh pr merge` (también con `--auto`, que es publicar en diferido) si
#   el PR no tiene un comentario de sesión POSTERIOR a su último commit.
#   `--disable-auto` pasa siempre: desarmar una fusión nunca es el riesgo.
#
# QUÉ ASUME
#   Que `gh` está autenticado y que hay red. Si no se puede leer el PR, FRENA:
#   la misma red caída haría fallar la fusión, y un freno que deja pasar lo que
#   no pudo comprobar es el que enseña a ignorarlo.
#
# POR QUÉ «POSTERIOR AL ÚLTIMO COMMIT»
#   Un comentario de las 10:00 no dice nada de un commit de las 10:30: avalaría
#   código que nadie describió. Si se empuja algo después de comentar —o se
#   trae `main` a la rama—, hay que volver a comentar.
#
# QUÉ NO CUBRE
#   Una fusión hecha a mano en la web de GitHub, o con `gh api …/merge`. Eso lo
#   hace una persona mirando una pantalla; el freno es para quien no la mira.
#
# SE ROMPE SI
#   El texto de las etiquetas cambia aquí y no en CLAUDE.md, o al revés: la
#   sesión comentaría con un formato que el freno no reconoce y se quedaría
#   atascada sin saber por qué. El mensaje de abajo imprime el formato exacto.
#
# Entra un JSON por stdin (el evento PreToolUse de Claude Code). Salir con 2
# frena la llamada y le muestra a la sesión lo que sale por stderr.

MARCA='<!-- cayla:fusion-sesion -->'

entrada=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "Falta jq: este freno lo necesita para leer la llamada. Instálalo (brew install jq)." >&2
  exit 2
fi

orden=$(printf '%s' "$entrada" | jq -r '.tool_input.command // empty')

# Solo `gh pr merge`, aunque venga dentro de `cd x && gh pr merge …`.
case "$orden" in
  *"gh pr merge"*) ;;
  *) exit 0 ;;
esac

# Los argumentos de ESE comando: lo que sigue a «gh pr merge» hasta el primer
# separador de shell. Sin esto, un `&& git push --force` posterior se leería
# como argumento del merge.
args=$(printf '%s' "$orden" | sed -e 's/.*gh pr merge//' -e 's/&&.*//' -e 's/;.*//' -e 's/|.*//' | head -n 1)

case " $args " in
  *" --disable-auto "*|*" --help "*|*" -h "*) exit 0 ;;
esac

# Número del PR y repo, si vienen en la orden. Acepta `505`, la URL completa y
# `-R owner/repo` / `--repo owner/repo`.
numero=""
repo=""
siguiente_es_repo=0
for t in $args; do
  if [ "$siguiente_es_repo" = 1 ]; then repo="$t"; siguiente_es_repo=0; continue; fi
  case "$t" in
    -R|--repo) siguiente_es_repo=1 ;;
    --repo=*) repo="${t#--repo=}" ;;
    https://github.com/*/pull/*)
      numero="${t##*/pull/}"; numero="${numero%%[!0-9]*}"
      repo=$(printf '%s' "$t" | sed -E 's#https://github.com/([^/]+/[^/]+)/pull/.*#\1#') ;;
    *[!0-9]*) ;;
    ?*) [ -z "$numero" ] && numero="$t" ;;
  esac
done

if [ -n "$repo" ]; then ref_repo="--repo $repo"; else ref_repo=""; fi

# Sin número en la orden, `gh pr merge` usa el PR de la rama actual.
# shellcheck disable=SC2086
if [ -z "$numero" ]; then
  numero=$(gh pr view $ref_repo --json number --jq .number 2>/dev/null)
fi
if [ -z "$numero" ]; then
  echo "No pude saber qué PR vas a fusionar (gh no contestó). No se fusiona a ciegas: indica el número o revisa gh auth status." >&2
  exit 2
fi

# shellcheck disable=SC2086
datos=$(gh pr view "$numero" $ref_repo --json comments,commits 2>/dev/null)
if [ -z "$datos" ]; then
  echo "No pude leer el PR $numero (gh no contestó). No se fusiona sin poder comprobar su comentario de sesión." >&2
  exit 2
fi

# Un comentario vale si: lleva la marca, trae las cuatro etiquetas y es
# posterior al último commit. Las etiquetas están para que no valga un
# comentario vacío con la marca pegada.
valido=$(printf '%s' "$datos" | jq -r --arg marca "$MARCA" '
  (.commits | map(.committedDate) | max) as $ultimo
  | [ .comments[]
      | select(.body | contains($marca))
      | select(.body | test("Sesión:") and test("Pidió:") and test("Pruebas:") and test("SQL:"))
      | select(.createdAt >= $ultimo) ]
  | length')

if [ "${valido:-0}" -ge 1 ] 2>/dev/null; then
  exit 0
fi

cat >&2 <<EOF
Falta el comentario de sesión en el PR $numero. Fusionar publica en producción, y todas las
sesiones firman como la misma persona: sin comentario nadie podrá saber después quién lo
pidió ni qué se comprobó.

Deja este comentario (con los datos reales) y vuelve a intentar. Tiene que ser POSTERIOR al
último commit del PR; si empujas algo después, se comenta de nuevo:

  gh pr comment $numero $ref_repo --body-file - <<'COMENTARIO'
  $MARCA
  **Fusión pedida desde una sesión de Claude**

  - Sesión: <nombre del worktree> · rama <rama>
  - Pidió: <quién lo pidió, con sus palabras, y cuándo (hora de Lima)>
  - Pruebas: <db-tests y ui-tests: estado al momento de fusionar>
  - SQL: <«no hay», o qué migración se pegó en Supabase ANTES y quién lo confirmó>
  COMENTARIO

Si nadie pidió fusionar este PR, no lo fusiones: pregunta primero.
EOF
exit 2
