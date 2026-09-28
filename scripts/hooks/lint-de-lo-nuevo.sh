#!/bin/sh
# El linter, pero solo sobre lo que este push AGREGA.
#
# POR QUÉ EXISTE
#
# ESLint lleva instalado y configurado desde julio, con su tarea de turbo y su
# script en el package.json. No lo ejecuta nadie: ni el pre-push, ni GitHub
# Actions, ni desplegar.sh. La auditoría de agosto lo encontró con 119 errores.
# Una semana después eran 131 — creció en doce sin que nadie lo notara, que es
# exactamente lo que le pasa a un guardián instalado y apagado.
#
# SOLO MIRA LO QUE EL PUSH AGREGA, y no es una concesión: es la única forma de
# que sirva.
#
# Exigir los 131 viejos frenaría TODOS los push, incluidos los que no tocan una
# línea de TypeScript, y en una semana se estaría usando `--no-verify` por
# costumbre. Es la misma lección que numeracion.sh y reglas-de-la-casa.sh llevan
# escritas en su cabecera, y la que este repositorio ya pagó tres veces el mismo
# día con lo de `types.ts`.
#
# Así que la deuda vieja no molesta a nadie y el error 132 no entra. La deuda se
# paga en su propio lote —si alguna vez merece la pena— y no a costa de que este
# freno mienta.
#
# QUÉ NO HACE, Y ES DELIBERADO
#
#   · No mira los avisos (`warning`), solo los errores. Un aviso que bloquea un
#     push es un aviso que se convierte en error de verdad para quien tiene prisa.
#   · No corre si el push no toca ningún .ts ni .tsx. En este repositorio la
#     mayoría de los push son SQL, así que casi siempre sale en un parpadeo.
#   · No lintea el repositorio entero: solo los archivos que el push modifica.
#     Todo son 14 segundos; un archivo, dos y medio.
#   · No juzga un archivo con cambios SIN COMMITEAR. Esos no viajan en el push y
#     sus líneas no cuadran con el diff — frenar por ellos sería castigar a
#     alguien por lo que otra sesión tiene a medio escribir. Es la misma
#     distinción que este hook ya tenía escrita para `types.ts`.
#   · No mira `types.ts`: es generado, y sus avisos no los escribe nadie.
#
# Para saltarlo en una urgencia real:  git push --no-verify

# La base se puede apuntar a otro commit con LINT_BASE. Existe para poder
# PROBAR este freno sin tocar el árbol compartido: con una base vieja, el
# "push" simulado incluye muchas más líneas y se ve si el cruce funciona.
# En el pre-push nadie la define, así que siempre es origin/main.
BASE="${LINT_BASE:-origin/main}"
git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || exit 0

RAIZ=$(git rev-parse --show-toplevel)
cd "$RAIZ" || exit 0

# SOLO apps/web, y no es un descuido: es el único paquete con configuración de
# eslint. Colar una ruta de packages/ hace que eslint aborte con «No files
# matching the pattern» y NO ANALICE NINGUNA — el guardián se volvía ciego
# entero por un archivo. Medido antes de entregarlo.
ARCHIVOS=$(git diff --name-only --diff-filter=d "$BASE...HEAD" -- 'apps/web/**/*.ts' 'apps/web/**/*.tsx' 2>/dev/null \
           | grep -v '/types\.ts$' | while read -r f; do [ -f "$f" ] && echo "$f"; done)
[ -z "$ARCHIVOS" ] && exit 0

SUCIOS=$(git diff --name-only -- $ARCHIVOS 2>/dev/null)
if [ -n "$SUCIOS" ]; then
  LIMPIOS=$(for f in $ARCHIVOS; do echo "$SUCIOS" | grep -qx "$f" || echo "$f"; done)
else
  LIMPIOS="$ARCHIVOS"
fi
[ -z "$LIMPIOS" ] && exit 0

RUTAS=$(for f in $LIMPIOS; do echo "$f" | sed 's|^apps/web/||'; done)
# Por `xargs` y no por `$RUTAS` a secas: sin él, las seis rutas viajan como UN
# solo argumento con saltos de linea dentro, eslint no encuentra ese "archivo" y
# aborta sin analizar nada. Es el segundo modo en que este guardian se volvia
# ciego en silencio; el primero fue colar una ruta de packages/.
SALIDA=$(cd "$RAIZ/apps/web" && echo "$RUTAS" | xargs npx eslint --format json 2>/dev/null)

# Si eslint no devolvió JSON, se DICE. Callar aquí es como fallaba la primera
# versión de este script: parecía que todo estaba bien y no había mirado nada.
# Con `case` y no con ${SALIDA#[}: el corchete es un caracter de patron, asi
# que esa expansion NUNCA quita nada y la comprobacion daba siempre verdadero.
# Tercer modo en que este guardian se rendia en silencio, y el mas tonto.
case "$SALIDA" in
  \[*) : ;;
  *)
    echo "  ⚠ El linter no devolvió nada analizable; este push NO se revisó."
    echo "    Compruébalo a mano:  npx pnpm --filter @cayla-dynamic/web lint"
    exit 0 ;;
esac

# Un Python que ARRANQUE, no uno que exista en el PATH. En Windows `python3` y
# `python` existen siempre: son el acceso directo de la Microsoft Store, que
# sin Python instalado imprime «no se encontró Python» y falla. El 2026-09-28,
# en el primer push desde esa máquina, eso se leyó como «este push agrega
# errores de lint» y frenó un push que no tenía ninguno. `command -v` no lo
# distingue; ejecutarlo sí. Sin Python se avisa y se deja pasar, igual que
# cuando eslint no devuelve nada: este freno bloquea por errores de lint, no
# por lo que tenga instalado la máquina de quien empuja.
PY=""
for candidato in python3 python; do
  if "$candidato" -c 'import json' >/dev/null 2>&1; then PY="$candidato"; break; fi
done
if [ -z "$PY" ]; then
  echo "  ⚠ No hay Python en esta máquina; el linter corrió pero este push NO se revisó."
  echo "    Compruébalo a mano:  npx pnpm --filter @cayla-dynamic/web lint"
  exit 0
fi

export DIFF_BASE="$BASE"
# Con printf y NO con echo: en algunos `sh` echo interpreta las secuencias de
# escape, y el JSON de eslint lleva \n dentro de los mensajes. Los convertia en
# saltos reales y rompia el JSON antes de que python lo viera. Cuarto y ultimo
# modo en que este guardian se volvia ciego sin decirlo.
printf '%s' "$SALIDA" | "$PY" -c '
import json, subprocess, sys, os, re

base = os.environ["DIFF_BASE"]
try:
    informes = json.load(sys.stdin)
except Exception:
    # No se calla: la primera version de este script salia en silencio por aqui
    # y parecia que todo estaba bien.
    print("  ! No pude leer la salida del linter; este push no se reviso.")
    sys.exit(0)

def lineas_agregadas(ruta):
    """Números de línea (en HEAD) que este push añade a ese archivo."""
    try:
        d = subprocess.run(["git", "diff", "--unified=0", base + "...HEAD", "--", ruta],
                           capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return None
    nums, ln = set(), 0
    for l in d.split("\n"):
        m = re.match(r"^@@ -\S+ \+(\d+)", l)
        if m:
            ln = int(m.group(1)); continue
        if l.startswith("+") and not l.startswith("+++"):
            nums.add(ln); ln += 1
    return nums

raiz = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip()
nuevos = []
for inf in informes:
    ruta = os.path.relpath(inf["filePath"], raiz)
    errores = [m for m in inf.get("messages", []) if m.get("severity") == 2]
    if not errores:
        continue
    agregadas = lineas_agregadas(ruta)
    if agregadas is None:
        continue
    for m in errores:
        if m.get("line") in agregadas:
            # El mensaje de eslint trae saltos de linea dentro; en una linea
            # de terminal se ven como texto partido a la mitad.
            texto = " ".join(m["message"].split())
            nuevos.append((ruta, m["line"], m.get("ruleId") or "-", texto))

if not nuevos:
    sys.exit(0)

print("")
print("  \033[31m* Este push agrega %d error(es) de lint nuevo(s).\033[0m" % len(nuevos))
print("")
for ruta, linea, regla, msg in nuevos[:20]:
    print("    %s:%s" % (ruta, linea))
    print("      %s" % msg[:100])
    print("      \033[90m(%s)\033[0m" % regla)
if len(nuevos) > 20:
    print("    ... y %d mas." % (len(nuevos) - 20))
print("")
print("  \033[90mLos errores que YA existian no se miran: este freno solo juzga lo que")
print("  este push anade. Asi la deuda vieja no molesta y una regla nueva no entra.")
print("")
print("  Para verlos con contexto:  npx pnpm --filter @cayla-dynamic/web lint")
print("  En una urgencia real:      git push --no-verify\033[0m")
print("")
sys.exit(1)
'
