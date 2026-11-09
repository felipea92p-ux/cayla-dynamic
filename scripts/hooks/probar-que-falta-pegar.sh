#!/bin/bash
# Prueba que las filas PLANILLA y PLATA de `que_falta_pegar.sql` digan la verdad, contra la base local de
# `scripts/local` (la de `node scripts/local/web.mjs`). Cada caso cambia UNA función dentro de BEGIN … ROLLBACK,
# corre la consulta generada y mira qué dice su fila: no deja nada cambiado.
#
# Un freno se prueba con casos que DEBEN marcar, no solo con uno que debe pasar: el linter de la casa se escribió
# cuatro veces dando el push por bueno antes de funcionar. Aquí, los que deben marcar son la función atrasada, la
# desconocida y la retirada que sigue viva; los que NO deben marcar son las formas en que una función al día llega a
# producción (sin comentarios, desde Windows).
#
#   ./scripts/hooks/probar-que-falta-pegar.sh
#
# Necesita la base local encendida, con `fn_costos_planilla` al día con el repositorio.
set -u
cd "$(git rev-parse --show-toplevel)"
source scripts/local/comun.sh >/dev/null 2>&1 || { echo "✗ No encontré scripts/local/comun.sh"; exit 2; }
psql -At -c "select 1" >/dev/null 2>&1 || { echo "✗ La base local no responde. Enciéndela: node scripts/local/web.mjs"; exit 2; }

./scripts/que-falta-pegar.sh >/dev/null || exit 2
CONSULTA="scripts/sql-manual/que_falta_pegar.sql"
FN="fn_costos_planilla"
VIGENTE=$(ls supabase/migrations | grep -E '^[0-9]+_' | while read -r f; do
  grep -q -i -E "create[ \t]+(or[ \t]+replace[ \t]+)?function[ \t]+(public\.)?${FN}[ \t]*\(" "supabase/migrations/$f" && echo "${f%%_*}"
done | sort -n | tail -1)

# Recrea la función con el cuerpo que da la expresión SQL $1 (sobre `b`, el cuerpo actual).
recrear() {
  cat <<SQL
do \$caso\$ declare b text; begin
  select prosrc into b from pg_proc where proname = '$FN';
  b := $1;
  execute format('create or replace function $FN(p_desde date, p_hasta date) returns jsonb language plpgsql stable security definer set search_path = public as %L', b);
end \$caso\$;
SQL
}
PELAR="array_to_string(array(select regexp_replace(l, '[[:space:]]*--.*\$', '') from unnest(string_to_array(b, chr(10))) l where btrim(l) not like '--%'), chr(10))"

fila() {  # $1 = SQL que prepara el caso, $2 = función cuya fila se lee
  { echo "begin;"; echo "$1"; cat "$CONSULTA"; echo "rollback;"; } | psql -q -At -F '|' 2>&1 \
    | awk -F'|' -v f="$2 · versión viva" '$2 == f { print $3 }'
}

FALLOS=0
caso() {  # $1 = nombre, $2 = SQL, $3 = función, $4 = lo que la fila tiene que contener
  local obtenido; obtenido=$(fila "$2" "$3")
  case "$obtenido" in
    *"$4"*) echo "  ✓ $1  →  $obtenido" ;;
    *)      echo "  ✗ $1  →  «$obtenido», se esperaba «$4»"; FALLOS=$((FALLOS + 1)) ;;
  esac
}

echo "que_falta_pegar.sql · $FN, vigente en la $VIGENTE"
caso "al día"                         ""                                              "$FN" "✓   al día ($VIGENTE)"
caso "pegada sin comentarios"         "$(recrear "$PELAR")"                           "$FN" "✓   al día ($VIGENTE, pegada sin comentarios)"
caso "pegada desde Windows"           "$(recrear "replace(b, chr(10), chr(13) || chr(10))")" "$FN" "✓   al día ($VIGENTE, pegada desde Windows)"
caso "desde Windows sin comentarios"  "$(recrear "replace($PELAR, chr(10), chr(13) || chr(10))")" "$FN" "✓   al día ($VIGENTE, desde Windows y sin comentarios)"
caso "atrasada en la 0099 (lo que pasó)" \
  "$(python3 - <<'PY'
import re
s = open('supabase/migrations/0099_una_tienda_no_es_una_oficina.sql', encoding='utf-8').read()
print(re.search(r'create or replace function (?:public\.)?fn_costos_planilla\s*\(.*?\$fn\$;', s, re.S | re.I).group(0))
PY
)" "$FN" "❌  se quedó en la 0099"
caso "un cuerpo que nadie escribió"   "$(recrear "b || ' '")"                          "$FN" "⚠   md5 sin catalogar"

# La retirada: se agrega a la lista, solo para esta prueba, una función que la 0327 borró, y se la revive.
LISTA="scripts/hooks/funciones-de-plata.txt"
cp "$LISTA" "$LISTA.respaldo"
trap 'mv -f "$LISTA.respaldo" "$LISTA"; ./scripts/que-falta-pegar.sh >/dev/null' EXIT
echo "fn_calcular_bono_puntualidad  solo para la prueba" >> "$LISTA"
./scripts/que-falta-pegar.sh >/dev/null
caso "retirada y ausente"             ""                                              "fn_calcular_bono_puntualidad" "✓   retirada en la 0327, como debe"
caso "retirada y viva"                "create function fn_calcular_bono_puntualidad() returns int language sql as \$x\$ select 1 \$x\$;" \
                                                                                      "fn_calcular_bono_puntualidad" "❌  sigue viva aunque la 0327 la retiró"

echo ""
if [ "$FALLOS" -eq 0 ]; then echo "✓ los 8 casos dicen lo que tienen que decir"; else echo "✗ $FALLOS casos fallaron"; exit 1; fi
