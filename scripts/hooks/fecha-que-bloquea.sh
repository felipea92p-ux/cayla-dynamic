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
# EXTENDIDO el 2026-09-05: la auditoría de esa fecha encontró que un commit del
# 30/08 dijo haber corregido "dos formularios más con el bug de fecha-vacía-
# bloquea-envío" (datos-personales, educación) y en realidad aplicó la
# combinación de técnicas que este mismo archivo documenta arriba como YA
# PROBADA Y SIN ÉXITO (onChange + onBlur + ref), no la solución real. Y este
# freno no los vio: su expresión regular solo reconocía `useState("")` con
# identificador simple, no un objeto (`useState({..., campo: ""})`) —
# exactamente el patrón de esos dos casos y de un tercero ya existente en
# admin/equipo. Ahora también reconoce `value={objeto.campo}` y busca
# `campo: ""` dentro del literal que inicializa ese objeto — sigue siendo una
# heurística de ventana de texto, no un parser, así que un objeto muy anidado
# o partido en variables intermedias puede seguir sin verse.
#
# Para saltarlo en una urgencia real:  git push --no-verify

BASE="${LINT_BASE:-origin/main}"
git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || exit 0

RAIZ=$(git rev-parse --show-toplevel)
cd "$RAIZ" || exit 0

ARCHIVOS=$(git diff --name-only --diff-filter=d "$BASE...HEAD" -- 'apps/web/**/*.tsx' 2>/dev/null \
           | while read -r f; do [ -f "$f" ] && echo "$f"; done)
[ -z "$ARCHIVOS" ] && exit 0

# Un Python que ARRANQUE, no uno que exista en el PATH. Mismo motivo y mismo
# arreglo que `lint-de-lo-nuevo.sh` (2026-09-28): en Windows `python3` y
# `python` existen siempre como acceso directo de la Microsoft Store, que sin
# Python instalado imprime «no se encontró Python» y falla — y ese fallo se lee
# igual que el `sys.exit(1)` de «hay un campo de fecha que bloquea», así que
# frenaba push que no tenían ninguno. Sin Python se avisa y se deja pasar.
PY=""
for candidato in python3 python; do
  if "$candidato" -c 'import json' >/dev/null 2>&1; then PY="$candidato"; break; fi
done
if [ -z "$PY" ]; then
  echo "  ⚠ No hay Python en esta máquina; este freno corrió pero este push NO se revisó."
  exit 0
fi

export DIFF_BASE="$BASE"
printf '%s\n' "$ARCHIVOS" | "$PY" -c '
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

    # Qué estados pinta un input[type=date]. `objeto.campo` cuenta igual que
    # un identificador simple — es el patrón de un formulario en un solo
    # `useState({...})` en vez de un `useState` por campo.
    de_fecha = set()
    for m in re.finditer(r"<input[^>]*type=\"date\"[^>]*>", texto, re.S):
        v = re.search(r"value=\{([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)?)\}", m.group(0))
        if v: de_fecha.add(v.group(1))

    def declaracion_simple(nombre):
        pat = r"const \[%s, set[A-Za-z0-9_]+\] = useState\(\"\"\)" % re.escape(nombre)
        for i, l in enumerate(lineas, 1):
            if re.search(pat, l):
                return i
        return None

    def campo_vacio_desde(inicio, campo):
        """¿"campo: \"\"" aparece en una ventana razonable después de `inicio`?"""
        ventana = texto[inicio:inicio + 4000]
        fm = re.search(r"\b%s\s*:\s*\"\"" % re.escape(campo), ventana)
        if not fm:
            return None
        return texto.count("\n", 0, inicio + fm.start()) + 1

    def declaracion_de_constante(nombre):
        """Dónde arranca el literal de `const NOMBRE = {...}` o `const NOMBRE: Tipo = {...}`."""
        m = re.search(r"const %s(?:\s*:\s*[A-Za-z0-9_<>]+)?\s*=\s*\{" % re.escape(nombre), texto)
        return m.end() if m else None

    def declaracion_en_objeto(objeto, campo):
        # Busca dónde se inicializa el objeto (useState(...), con o sin tipo
        # genérico) y, DENTRO de una ventana razonable después de eso, si el
        # campo nace en "". La ventana evita casarse con un objeto homónimo
        # de más abajo en el archivo.
        #
        # El argumento de useState no siempre es un literal en línea: el
        # patrón real de este repo es `useState(NOMBRE_VACIO)` o
        # `useState({ ...NOMBRE_VACIO })`, con el objeto vacío declarado
        # aparte como constante — así se resetea el formulario sin repetir
        # los campos en cada sitio que lo limpia. Si el argumento es un
        # literal inline, se mira directamente ahí.
        m = re.search(
            r"const \[%s,\s*set[A-Za-z0-9_]+\]\s*=\s*useState(?:<[^>()]*>)?\(((?:[^()]|\([^()]*\))*)\)"
            % re.escape(objeto),
            texto,
        )
        if not m:
            return None
        arg = m.group(1).strip()

        referencia = re.match(r"^\{\s*\.\.\.([A-Za-z0-9_]+)", arg) or re.match(r"^([A-Za-z0-9_]+)$", arg)
        if referencia:
            inicio_const = declaracion_de_constante(referencia.group(1))
            if inicio_const is not None:
                resultado = campo_vacio_desde(inicio_const, campo)
                if resultado is not None:
                    return resultado
        # Última opción: el literal está inline en el propio useState(...).
        return campo_vacio_desde(m.start(1), campo)

    for nombre in de_fecha:
        # ¿arranca vacío, y esa línea la agrega ESTE push?
        if "." in nombre:
            objeto, campo = nombre.split(".", 1)
            decl = declaracion_en_objeto(objeto, campo)
        else:
            decl = declaracion_simple(nombre)
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
_nombre_ej = hallazgos[0][2]
if "." in _nombre_ej:
    _obj, _campo = _nombre_ej.split(".", 1)
    print("      %s: hoyLima()   dentro del literal que inicializa %s" % (_campo, _obj))
else:
    print("      const [%s, set…] = useState(hoyLima());" % _nombre_ej)
print("")
print("    Sigue visible y se corrige en un clic. Si de verdad es opcional,")
print("    quita la validación que bloquea por vacío.")
print("")
sys.exit(1)
'
