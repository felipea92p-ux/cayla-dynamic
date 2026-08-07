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
# Al repo que se está empujando, no al que guarda este archivo: el `pre-push` de
# un worktree ejecuta la copia del repo PRINCIPAL (así resuelve `core.hooksPath`),
# y orientarse por `$0` haría revisar las migraciones de `main` en vez de las de
# la rama que se empuja. Misma corrección que en `hooks/numeracion.sh`.
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || true)"
cd "${RAIZ:-$(dirname "$0")/..}"

SALIDA="scripts/sql-manual/que_falta_pegar.sql"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Desde la 0150 hacia adelante. Antes de esa no hay nada pendiente de pegar y
# listar 150 filas de historia solo esconde las que importan.
DESDE=150

# La lista de migraciones, ordenada. `sort -n` sobre el número y no sobre el nombre del archivo, que
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
-- ES UNA SOLA CONSULTA, Y ESO IMPORTA. La primera versión eran tres `select`
-- seguidos, y el SQL Editor de Supabase muestra únicamente el resultado del
-- ÚLTIMO: los otros dos se ejecutaban y no los veía nadie. Una herramienta de
-- diagnóstico que esconde dos tercios de su diagnóstico es peor que no tenerla,
-- porque uno cree que ya miró.
--
-- QUÉ RESPONDE, todo en la misma tabla
--   · migración por migración, cuál falta pegar y cuál está anotada
--   · el resumen: cuántas faltan de cuántas
--   · en qué versión está VIVA `fn_planilla_calcular`
--
-- LO QUE NO PUEDE VER
--   Que una migración esté anotada NO prueba que su contenido siga vivo: una
--   pegada posterior pudo pisarlo sin dar ningún error. Por eso las dos últimas
--   filas miran el cuerpo real de la función y no el registro.
-- ============================================================================

with repo(numero, nombre) as (values
CAB
con_nombre
cat <<'PIE'
),
diff as (
  select r.numero, r.nombre, (a.numero is null) as falta, a.aplicada_at
  from repo r
  left join migraciones_aplicadas a on a.numero = r.numero
)
select * from (
  -- Una fila por migración.
  select d.numero::text                        as num,
         d.nombre                              as que,
         case when d.falta then '❌  FALTA PEGAR' else '✓   aplicada' end as estado,
         to_char(d.aplicada_at, 'DD/MM/YYYY')  as cuando,
         d.numero                              as orden
  from diff d

  union all

  -- El resumen, al final y separado.
  select '——', '', '', '', 999998
  union all
  select 'RESUMEN',
         (select count(*) filter (where falta) from diff)::text || ' faltan · ' ||
         (select count(*) filter (where not falta) from diff)::text || ' aplicadas · ' ||
         (select count(*) from diff)::text || ' en el repo',
         case when (select count(*) filter (where falta) from diff) = 0
              then '✓   al día' else '❌  hay pendientes' end,
         '', 999999

  union all

  -- Y la única pregunta que el registro no puede responder.
  select 'PLANILLA',
         'fn_planilla_calcular · versión viva',
         coalesce((
           select case md5(prosrc)
             when '30e0ecbf11ac5939457df6c2b3cccc77' then '0166 — movilidad por sede física'
             when '46c6c3de546f4da080d328a079470478' then '0171 — sin plus ni rendimiento'
             when 'cb3c5de14dd2b5a8872965814d5e7cd9' then '0173 — sueldo fijo no duplica feriado'
             when '93e96e37e05799121485e5721de3dc06' then '0177 — las vacaciones se pagan'
             else '⚠ md5 SIN CATALOGAR: ' || md5(prosrc)
           end
           from pg_proc where proname = 'fn_planilla_calcular'
         ), '⚠ la función NO EXISTE'),
         '', 1000000
) t
order by orden;
PIE
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
