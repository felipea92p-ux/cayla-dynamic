#!/usr/bin/env bash
# ##############################################################################
# ####  COPIA DE LOS ARCHIVOS DE LAS BOLETAS OFICIALES (bucket «boletas»)   ####
# ##############################################################################
#
# Para qué. El respaldo de la base de datos NO incluye los archivos de Storage:
# la prueba de restauración (docs/prueba-restauracion-backup.md) solo cubre el
# esquema `public` y deja `storage` fuera a propósito. Las boletas oficiales
# (0482) son archivos —fotos y PDF— que viven SOLO en el bucket «boletas». La
# base guarda quién las publicó y cuándo las confirmó cada persona, pero no el
# documento. Si Storage pierde un archivo, la constancia queda apuntando a nada,
# y esos archivos no se pueden volver a generar: son la boleta que entregó el
# contador.
#
# Qué hace. Baja el bucket «boletas» entero a una carpeta FUERA del repositorio,
# comprueba que lo bajado coincide con lo que Storage lista, y deja un
# manifiesto con la huella (sha256) de cada archivo para poder comprobar después
# que nada se alteró ni se perdió.
#
# Qué NO hace. No sube nada, no borra nada, no toca la base. No usa la clave de
# servicio (está rotada a propósito, ver CLAUDE.md): usa TU sesión del CLI
# (`npx supabase login`) y el proyecto enlazado (`npx supabase link`). Igual que
# el SQL, esto lo corre Felipe a mano; ningún script corre solo contra producción.
#
# Uso:
#   ./scripts/respaldar-boletas.sh                       # carpeta por defecto
#   ./scripts/respaldar-boletas.sh /Volumes/OTRO/boletas # otra carpeta (vacía)
#   ./scripts/respaldar-boletas.sh --simulacro           # solo muestra qué haría
#
# Por defecto la carpeta es ~/CAYLA-respaldos/boletas/AAAA-MM-DD_HHMM. Se niega a
# escribir dentro de un repositorio git: las boletas llevan sueldos y descuentos
# de personas reales, y eso no se commitea (ver «Datos personales fuera de git»).
#
# Cuándo. Una vez al mes, después de cerrar el periodo y publicar las boletas.
# Son ~30 personas × 12 meses ≈ 180 MB al año: cabe en cualquier disco, así que
# cada corrida es una copia completa y fechada, no un delta que haya que armar.
#
# UNA COPIA EN EL MISMO DISCO DE LA MAC NO ES UN RESPALDO. Al terminar, mueve o
# copia la carpeta a un SEGUNDO lugar (otro disco, otro servicio). El script no
# lo hace por ti a propósito: dónde vive esa segunda copia es decisión tuya.
#
# Probar sin tocar producción: con el Supabase local levantado,
#   MODO_STORAGE=--local ./scripts/respaldar-boletas.sh /tmp/prueba-boletas
#
# Se comprueba que quedó bien con las dos últimas líneas de la salida: «COINCIDE»
# y el conteo de archivos. Y con el tiempo, con el manifiesto:
#   cd <carpeta> && shasum -a 256 -c MANIFIESTO.sha256

set -euo pipefail
umask 077   # sueldos de personas reales: solo tú lees lo que se baja

SUPABASE_CMD="${SUPABASE_CMD:-npx supabase}"
MODO_STORAGE="${MODO_STORAGE:---linked}"
BUCKET="boletas"

read -r -a SUPA <<< "$SUPABASE_CMD"
supa() { "${SUPA[@]}" "$@"; }

SIMULACRO=0
DESTINO=""
for arg in "$@"; do
  case "$arg" in
    --simulacro) SIMULACRO=1 ;;
    -h|--help) sed -n '2,47p' "$0"; exit 0 ;;
    -*) echo "✗ Opción desconocida: $arg" >&2; exit 2 ;;
    *) DESTINO="$arg" ;;
  esac
done

if [ -z "$DESTINO" ]; then
  DESTINO="$HOME/CAYLA-respaldos/boletas/$(date +%Y-%m-%d_%H%M)"
fi

# ── 1 · La carpeta destino: fuera de git y vacía ───────────────────────────────
# Ruta absoluta sin exigir que exista todavía.
mkdir -p "$(dirname "$DESTINO")"
DESTINO="$(cd "$(dirname "$DESTINO")" && pwd)/$(basename "$DESTINO")"

d="$DESTINO"
while [ "$d" != "/" ] && [ -n "$d" ]; do
  if [ -e "$d/.git" ]; then
    echo "✗ $DESTINO está dentro de un repositorio git ($d)." >&2
    echo "  Las boletas llevan sueldos de personas reales y no se commitean." >&2
    echo "  Elige una carpeta fuera del repositorio." >&2
    exit 1
  fi
  d="$(dirname "$d")"
done

if [ -e "$DESTINO" ] && [ -n "$(ls -A "$DESTINO" 2>/dev/null)" ]; then
  echo "✗ $DESTINO ya tiene contenido." >&2
  echo "  No mezclo una copia nueva con una vieja: elige una carpeta vacía o bórrala tú." >&2
  exit 1
fi

if [ "$SIMULACRO" = 1 ]; then
  echo "Simulacro — no se baja nada. Haría esto:"
  echo "  1. ${SUPABASE_CMD} storage cp -r ss:///${BUCKET} \"$DESTINO\" -j 4 ${MODO_STORAGE}"
  echo "  2. ${SUPABASE_CMD} storage ls -r ss:///${BUCKET} ${MODO_STORAGE}   (y comparar el conteo)"
  echo "  3. Escribir MANIFIESTO.sha256 y LEEME.txt en $DESTINO"
  exit 0
fi

# ── 2 · Bajar el bucket ────────────────────────────────────────────────────────
mkdir -p "$DESTINO"
chmod 700 "$DESTINO"
echo "→ Bajando el bucket «${BUCKET}» a $DESTINO"
if ! supa storage cp -r "ss:///${BUCKET}" "$DESTINO" -j 4 "$MODO_STORAGE"; then
  echo "✗ La descarga falló. Lo que haya en $DESTINO es INCOMPLETO: no lo uses." >&2
  echo "  Revisa que estés con sesión (npx supabase login) y con el proyecto enlazado" >&2
  echo "  (npx supabase link), y vuelve a correrlo con otra carpeta." >&2
  exit 1
fi

# ── 3 · ¿Lo bajado coincide con lo que Storage lista? ─────────────────────────
# Cuenta líneas que terminan en extensión de archivo (jpg, png, pdf, heic…): las
# rutas de las hojas tienen la forma <uuid>/<uuid>/<uuid>.<ext> (0482).
LISTADO="$(supa storage ls -r "ss:///${BUCKET}" "$MODO_STORAGE")"
EN_STORAGE="$(printf '%s\n' "$LISTADO" | grep -c -E '\.[A-Za-z0-9]{2,5}$' || true)"
EN_COPIA="$(find "$DESTINO" -type f | grep -c -E '\.[A-Za-z0-9]{2,5}$' || true)"

if [ "$EN_STORAGE" -eq 0 ] && [ "$EN_COPIA" -eq 0 ]; then
  echo "⚠ Storage no lista ningún archivo en «${BUCKET}»."
  echo "  Si todavía no se ha publicado ninguna boleta, es lo esperado."
  echo "  Si ya se publicaron, el proyecto enlazado NO es el de producción: revisa"
  echo "  con  npx supabase projects list"
  exit 0
fi

if [ "$EN_STORAGE" -ne "$EN_COPIA" ]; then
  echo "✗ NO COINCIDE: Storage lista $EN_STORAGE archivos y la copia trae $EN_COPIA." >&2
  echo "  La copia está incompleta o Storage cambió mientras se bajaba. Vuelve a correrlo." >&2
  exit 1
fi

# ── 4 · Manifiesto y LEEME ─────────────────────────────────────────────────────
(
  cd "$DESTINO"
  find . -type f ! -name MANIFIESTO.sha256 ! -name LEEME.txt -print0 \
    | sort -z | xargs -0 shasum -a 256 > MANIFIESTO.sha256
)
{
  echo "Copia del bucket «${BUCKET}» — boletas oficiales de CAYLA Dynamic"
  echo "Fecha de la copia: $(date '+%Y-%m-%d %H:%M')"
  echo "Archivos: $EN_COPIA"
  echo
  echo "Comprobar que nada cambió:  shasum -a 256 -c MANIFIESTO.sha256"
  echo "Esta carpeta lleva sueldos de personas reales. No se sube a git ni se comparte."
  echo "Una copia en el mismo disco no es respaldo: guarda una SEGUNDA copia en otro lugar."
} > "$DESTINO/LEEME.txt"

echo
echo "✓ COINCIDE: Storage lista $EN_STORAGE archivos y la copia trae $EN_COPIA."
echo "✓ Manifiesto escrito: $DESTINO/MANIFIESTO.sha256"
echo
echo "Falta lo que este script no puede hacer por ti:"
echo "  1. Abre dos boletas al azar de esta carpeta y comprueba que se leen."
echo "  2. Copia la carpeta a un SEGUNDO lugar (otro disco u otro servicio)."
