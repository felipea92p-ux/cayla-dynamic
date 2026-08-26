#!/bin/sh
# Un campo de fecha que arranca VACÍO y bloquea el envío. Solo lo nuevo.
#
# POR QUÉ EXISTE
#
# El 2026-08-26 no se pudo registrar un descanso médico real. El campo «Fecha de
# emisión» mostraba 26/08/2026 en pantalla y llegaba VACÍO al formulario: Safari
# había puesto el valor sin disparar el evento que React escucha. La validación
# —la de la pantalla y la del servidor— pedía un dato que estaba delante de los
# ojos, y no había salida: reescribirlo no servía, porque el problema no era el
# valor sino que nunca llegaba.
#
# Se intentó capturarlo por `onChange`, por `onBlur` y leyendo el DOM. Ninguno lo
# vio. Costó cinco despliegues y una tarde con la planilla del mes a dos días de
# cerrar. Lo que funcionó fue dejar de preguntar: el campo nace con un valor
# razonable —hoy, o el primer día del descanso—, visible y editable en un clic.
#
# LA REGLA, y está escrita en CLAUDE.md: un `input[type=date]` cuyo vacío BLOQUEA
# el envío no puede arrancar en "". Nace con el valor más probable. Los campos de
# fecha opcionales no molestan a nadie y este freno no los mira.
#
# SOLO LO QUE EL PUSH AGREGA, igual que numeracion.sh, reglas-de-la-casa.sh y
# lint-de-lo-nuevo.sh, y por el mismo motivo: hoy quedan tres campos así en el
# repositorio y frenar todos los push por ellos convertiría este freno en algo
# que se salta con --no-verify. La deuda vieja se paga en su propio lote.
#
# Para saltarlo en una urgencia real:  git push --no-verify

BASE="${LINT_BASE:-origin/main}"
git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || exit 0

RAIZ=$(git rev-parse --show-toplevel)
cd "$RAIZ" || exit 0

ARCHIVOS=$(git diff --name-only --diff-filter=d "$BASE...HEAD" -- 'apps/web/**/*.tsx' 2>/dev/null \
           | while read -r f; do [ -f "$f" ] && echo "$f"; done)
[ -z "$ARCHIVOS" ] && exit 0

export DIFF_BASE="$BASE"
printf '%s\n' "$ARCHIVOS" | python3 -c '
import io, os, re, subprocess, sys

base = os.environ["DIFF_BASE"]

def lineas_agregadas(ruta):
    """Números de línea (en HEAD) que este push añade a ese archivo."""
    try:
        d = subprocess.run(["git", "diff", "--unified=0", base + "...HEAD", "--", ruta],
                           capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return set()
    nums, ln = set(), 0
    for l in d.split("\n"):
        m = re.match(r"^@@ -\S+ \+(\d+)", l)
        if m:
            ln = int(m.group(1)); continue
        if l.startswith("+") and not l.startswith("+++"):
            nums.add(ln); ln += 1
    return nums

hallazgos = []
for ruta in [r.strip() for r in sys.stdin if r.strip()]:
    try:
        texto = io.open(ruta, encoding="utf-8").read()
    except Exception:
        continue
    lineas = texto.split("\n")
    nuevas = lineas_agregadas(ruta)

    # Qué estados pinta un input[type=date].
    de_fecha = set()
    for m in re.finditer(r"<input[^>]*type=\"date\"[^>]*>", texto, re.S):
        v = re.search(r"value=\{([A-Za-z0-9_]+)\}", m.group(0))
        if v: de_fecha.add(v.group(1))

    for nombre in de_fecha:
        # ¿arranca vacío, y esa línea la agrega ESTE push?
        decl = None
        for i, l in enumerate(lineas, 1):
            if re.search(r"const \[%s, set[A-Za-z0-9_]+\] = useState\(\"\"\)" % re.escape(nombre), l):
                decl = i; break
        if decl is None or decl not in nuevas:
            continue
        # ¿y su vacío corta el envío?
        if not re.search(r"if \(!%s[^)]*\)\s*\{[^}]*(?:error|Error)" % re.escape(nombre), texto, re.S):
            continue
        hallazgos.append((ruta, decl, nombre))

if not hallazgos:
    sys.exit(0)

print("")
print("  \033[31m✗ Un campo de fecha arranca vacío y su vacío bloquea el envío.\033[0m")
for ruta, ln, nombre in hallazgos:
    print("    %s:%d  ·  %s" % (ruta, ln, nombre))
print("")
print("    Safari puede pintar la fecha en el campo y NO entregarla al")
print("    formulario. Entonces la validación rechaza un dato que la persona")
print("    está viendo, y no hay forma de salir: reescribirlo tampoco llega.")
print("    Pasó el 2026-08-26 con un descanso médico y costó cinco despliegues.")
print("")
print("    Que nazca con el valor más probable —hoy, o la fecha de inicio—:")
print("")
print("      const [%s, set…] = useState(hoyLima());" % hallazgos[0][2])
print("")
print("    Sigue visible y se corrige en un clic. Si de verdad es opcional,")
print("    quita la validación que bloquea por vacío.")
print("")
sys.exit(1)
'
