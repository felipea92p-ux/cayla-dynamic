#!/bin/sh
# Genera `scripts/sql-manual/que_falta_pegar.sql` a partir del directorio de
# migraciones, para que la consulta nunca liste un repositorio que ya no existe.
#
# POR QUÉ ESTO ES UN SCRIPT Y NO UN ARCHIVO ESCRITO A MANO
#
# La consulta necesita saber qué migraciones hay en el repo para poder restarle
# lo que producción tiene anotado. Ese dato ya vive en `supabase/migrations`, así
# que copiarlo a mano dentro de un `.sql` crea una segunda copia de la verdad —
# y una copia que hay que acordarse de actualizar es una copia que va a mentir.
#
# El 2026-08-07 ese patrón falló dos veces en un día: una guía de pegado con el
# rango en el nombre quedó desfasada en dos horas, y una lista de migraciones
# supuesta —no consultada— estuvo a una pegada de revertir la 0171 en producción.
# La regla del `estado.md` es la misma: «si es un número que un comando puede
# calcular, no va escrito — va el comando».
#
# QUÉ HACE
#   · lee los .sql de supabase/migrations
#   · escribe la consulta con esa lista adentro
#   · no toca la base: lo que genera solo LEE
#
# CÓMO SE USA
#   ./scripts/que-falta-pegar.sh          genera el archivo y dice dónde quedó
#   ./scripts/que-falta-pegar.sh --check  no escribe; falla si está desfasado
#
# El `--check` lo corre el hook de pre-push. Así el archivo no puede quedarse
# viejo sin que alguien se entere ANTES de que haga falta.

set -e
cd "$(dirname "$0")/.."

SALIDA="scripts/sql-manual/que_falta_pegar.sql"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Desde la 0150 hacia adelante. Antes de esa no hay nada pendiente de pegar y
# listar 150 filas de historia solo esconde las que importan.
DESDE=150

# La lista, en dos formatos: con nombre para la tabla, y solo el número para el
# conteo. `sort -n` sobre el número y no sobre el nombre del archivo, que
# ordenaría 0100 antes que 099.
listar() {
  ls supabase/migrations/*.sql 2>/dev/null \
    | sed -E 's|.*/||' \
    | grep -E '^[0-9]+_' \
    | awk -F_ -v d="$DESDE" '{ n = $1 + 0; if (n >= d) print }' \
    | sort -t_ -k1,1n
}

if [ -z "$(listar)" ]; then
  echo "✗ No encontré migraciones en supabase/migrations. ¿Estás en la raíz del repo?" >&2
  exit 2
fi

con_nombre() {
  listar | sed -E "s/^0*([0-9]+)_(.*)\.sql$/    (\1, '\2'),/" | sed '$ s/,$//'
}
solo_numero() {
  listar | sed -E "s/^0*([0-9]+)_.*\.sql$/    (\1),/" | sed '$ s/,$//'
}

{
cat <<'CAB'
-- ============================================================================
-- ¿QUÉ ME FALTA PEGAR? — solo LEE, no cambia nada. Pégala en el SQL Editor.
-- ============================================================================
--
-- ⚠️ ARCHIVO GENERADO. No lo edites a mano: lo reescribe
--    ./scripts/que-falta-pegar.sh
--    y el hook de pre-push falla si se quedó viejo.
--
-- QUÉ RESPONDE
--   Compara lo que hay en el repositorio contra lo que producción tiene anotado
--   y dice, fila por fila, cuál falta. No hay que cruzar nada a mano.
--
-- POR QUÉ EXISTE
--   El 2026-08-07 una guía dio por pendiente una migración que ya estaba
--   aplicada, y estuvo a una pegada de revertir la 0171 en producción. La
--   diferencia entre suponer y preguntar son estas veinte líneas.
--
-- LO QUE NO PUEDE VER
--   Que una migración esté anotada NO prueba que su contenido siga vivo: una
--   pegada posterior pudo pisarlo sin dar ningún error. Para
--   `fn_planilla_calcular` —la que decide lo que cobra cada persona— eso se
--   comprueba con el md5 del tercer bloque, que mira el cuerpo real y no el
--   registro.
-- ============================================================================

-- ── 1 · Migración por migración ────────────────────────────────────────────
with repo(numero, nombre) as (values
CAB
con_nombre
cat <<'PIE'
)
select
  r.numero,
  r.nombre,
  case when a.numero is null then '❌  FALTA PEGAR' else '✓   aplicada' end as estado,
  a.aplicada_at
from repo r
left join migraciones_aplicadas a on a.numero = r.numero
order by r.numero;


-- ── 2 · Cuántas faltan, de un vistazo ──────────────────────────────────────
with repo(numero) as (values
PIE
solo_numero
cat <<'PIE2'
)
select count(*) filter (where a.numero is null)     as faltan,
       count(*) filter (where a.numero is not null) as aplicadas,
       count(*)                                     as total_en_el_repo
from repo r left join migraciones_aplicadas a on a.numero = r.numero;


-- ── 3 · En qué versión está VIVA la función que calcula la planilla ────────
-- El registro dice qué se pegó; esto dice qué quedó. No siempre coinciden.
select md5(prosrc) as md5_actual,
       case md5(prosrc)
         when '30e0ecbf11ac5939457df6c2b3cccc77' then '0166 — la movilidad por sede física'
         when '46c6c3de546f4da080d328a079470478' then '0171 — sin plus ni rendimiento'
         when 'cb3c5de14dd2b5a8872965814d5e7cd9' then '0173 — el sueldo fijo no duplica el feriado'
         when '93e96e37e05799121485e5721de3dc06' then '0177 — las vacaciones se pagan'
         else '⚠ md5 DESCONOCIDO: nadie lo ha catalogado. Avisar antes de pegar nada que toque la planilla.'
       end as version_viva
from pg_proc where proname = 'fn_planilla_calcular';
PIE2
} > "$TMP"

if [ "$1" = "--check" ]; then
  if [ ! -f "$SALIDA" ] || ! cmp -s "$TMP" "$SALIDA"; then
    echo ""
    echo "  ✗ '$SALIDA' está desfasado: el repo tiene migraciones que la consulta no lista."
    echo "    Corre  ./scripts/que-falta-pegar.sh  y vuelve a intentar el push."
    echo ""
    exit 1
  fi
  exit 0
fi

cp "$TMP" "$SALIDA"
N=$(listar | wc -l | tr -d ' ')
echo "✓ $SALIDA regenerado · $N migraciones desde la $DESDE"
echo "  Pégalo entero en el SQL Editor de producción. Solo lee."
