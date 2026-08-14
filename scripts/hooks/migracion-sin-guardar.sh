#!/bin/bash
# Aviso: hay una migración que no está en git, y puede estar ya en producción.
#
# POR QUÉ EXISTE. Ha pasado DOS VECES, y la segunda con el freno ya construido:
#
#   · 2026-08-07 — la 0177, que cambia cómo se pagan las vacaciones, se descubrió
#     aplicada en producción con su único ejemplar en un archivo sin commitear en
#     la MacBook. De ahí salió `dame-el-sql.sh`.
#   · 2026-08-14 — la 0243, que cambia una liquidación por cese, exactamente
#     igual. Y en el medio hubo cuatro `git push` que no dijeron nada.
#
# `dame-el-sql.sh` no lo evitó y no puede: solo protege a quien lo usa. Si tienes
# la migración abierta delante, copiarla del editor es lo natural, y ahí el script
# no participa. Ni `numeracion.sh` ni `que-falta-pegar.sh` lo ven tampoco, porque
# los dos miran git y el archivo justamente no está en git.
#
# El agujero no estaba en el script: estaba en que EL CAMINO CÓMODO NO PASA POR
# ÉL. Esto no cierra ese camino —no se puede— sino que hace imposible no ver el
# archivo que quedó suelto.
#
# ── POR QUÉ AVISA Y NO BLOQUEA ──────────────────────────────────────────────
#
# Es la regla que este hook ya tenía escrita para `types.ts`: «un freno tiene que
# hablar de lo que SALE de esta máquina, no de lo que hay en el disco». Una
# migración sin commitear es del disco, y hay un caso legítimo constante: otra
# sesión escribiéndola ahora mismo. Este repo tiene varias sesiones trabajando en
# paralelo — es la causa de la mitad de sus cicatrices.
#
# Bloquear ahí sería repetir dos errores ya pagados: `desplegar.sh` frenó un
# despliegue el 2026-08-06 por archivos .sql de otra sesión, y
# `que-falta-pegar.sh --check` frenó cuatro pushes en un día. Un freno que se
# salta todos los días no frena el día que importa.
#
# LA VUELTA DE TUERCA, y es lo que hace este caso distinto de `types.ts`: ahí el
# problema era que algo malo VIAJABA. Acá es que algo necesario NO viaja, y esa
# ausencia es exactamente el daño. Por eso el aviso no puede ser una línea gris
# más: distingue el archivo recién escrito del que ya sobrevivió a un commit —
# ese segundo no es trabajo en curso, es trabajo olvidado.
#
# ── LO QUE ESTO NO PUEDE SABER, Y CONVIENE NO FINGIR ────────────────────────
#
# Si la migración ya se pegó en producción o no. Ese dato vive solo en producción.
# El aviso no afirma que se pegó: dice que si se pegó, este es el estado de la
# 0177. La comprobación de verdad es `./scripts/que-falta-pegar.sh`.
#
# Y un caso que se le escapa a propósito: una migración YA COMMITEADA a la que
# alguien le hizo cambios sin commitear y pegó esos cambios. `git ls-files
# --others` solo ve lo que no está en git, así que eso no sale. Se deja fuera
# porque ahí el archivo sí existe en la historia —se puede leer y comparar— y
# porque ampliarlo a los modificados haría saltar el aviso cada vez que alguien
# está editando una migración, que es todo el rato.
#
# Se salta con `git push --no-verify`, como todo lo demás.

set -euo pipefail
cd "$(dirname "$0")/../.."

ambar() { printf "\033[33m%s\033[0m\n" "$1"; }
gris()  { printf "\033[90m%s\033[0m\n" "$1"; }

# `--exclude-standard` respeta .gitignore a propósito: en este repo hay SQL
# ignorado por llevar datos personales (`scripts/sql-manual/ficha_*.sql`), y esos
# no están sin guardar por descuido sino por decisión.
SUELTAS=$(git ls-files --others --exclude-standard -- 'supabase/migrations/*.sql' || true)
[ -z "$SUELTAS" ] && exit 0

# Cuándo fue el último commit. Sirve para separar «la estoy escribiendo» de «se
# quedó atrás»: un archivo que sobrevivió a un commit ya no es trabajo en curso.
HEAD_TS=$(git log -1 --format=%ct 2>/dev/null || echo 0)

mtime() {
  # BSD (esta Mac) y GNU, porque el día que esto corra en otra parte no debe
  # morir por un flag de `stat`.
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

OLVIDADAS=""
NUEVAS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ "$(mtime "$f")" -lt "$HEAD_TS" ]; then
    OLVIDADAS="${OLVIDADAS}${f}
"
  else
    NUEVAS="${NUEVAS}${f}
"
  fi
done <<EOF
$SUELTAS
EOF

echo ""
if [ -n "$OLVIDADAS" ]; then
  ambar "  ⚠ Hay una migración sin guardar que YA SOBREVIVIÓ A UN COMMIT:"
  echo ""
  printf '%s' "$OLVIDADAS" | sed 's/^/      /'
  echo ""
  gris "    Se escribió antes de tu último commit y no entró en él. Eso ya no es"
  gris "    trabajo en curso. Si además se pegó en el SQL Editor, producción tiene"
  gris "    un cálculo cuyo único ejemplar está en esta Mac — el estado exacto en"
  gris "    el que se encontró la 0177 el 2026-08-07 y la 0243 el 2026-08-14."
else
  ambar "  ⚠ Hay una migración sin guardar en git:"
  echo ""
  printf '%s' "$NUEVAS" | sed 's/^/      /'
  echo ""
  gris "    Si la estás escribiendo ahora, ignora esto. Si ya la pegaste en el"
  gris "    SQL Editor, su único ejemplar está en esta Mac y nadie más puede"
  gris "    leerla, auditarla ni revertirla."
fi

# Su prueba, si la hay: una migración de este repo sin prueba es media migración,
# y se olvida por el mismo descuido.
PRUEBAS=$(git ls-files --others --exclude-standard -- 'supabase/tests/*.sql' || true)
if [ -n "$PRUEBAS" ]; then
  echo ""
  gris "    Y su prueba también está suelta:"
  printf '%s\n' "$PRUEBAS" | sed 's/^/      /'
fi

# Las dos listas se unen con un salto de línea explícito, no pegando las
# variables: `$(...)` se come el salto final de `git ls-files`, así que
# `$SUELTAS$PRUEBAS` producía «…0243.sqlsupabase/tests/184…». Lo cazó la prueba
# del caso 3, y era justo la línea que existe para copiarse.
echo ""
gris "    Para guardarla:"
echo ""
printf '      git add %s\n' \
  "$(printf '%s\n%s\n' "$SUELTAS" "$PRUEBAS" | grep . | tr '\n' ' ' | sed 's/ $//')"
gris "      git commit"
echo ""
gris "    Y para saber qué hay de verdad en producción:  ./scripts/que-falta-pegar.sh"
echo ""

# Nunca bloquea. Ver la nota larga de arriba.
exit 0
