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
#   ./scripts/que-falta-pegar.sh            genera el archivo y dice dónde quedó
#   ./scripts/que-falta-pegar.sh --check    no escribe; falla si está desfasado
#   ./scripts/que-falta-pegar.sh --arregla  lo regenera Y lo commitea si hacía falta
#
# El `--arregla` lo corre el hook de pre-push. Antes corría `--check`, que solo
# avisaba: en un solo día frenó cuatro pushes para pedir un comando que el propio
# hook podía ejecutar. Ver la nota larga junto a `--arregla`.

set -e
# Al repo que se está empujando, no al que guarda este archivo: el `pre-push` de
# un worktree ejecuta la copia del repo PRINCIPAL (así resuelve `core.hooksPath`),
# y orientarse por `$0` haría revisar las migraciones de `main` en vez de las de
# la rama que se empuja. Misma corrección que en `hooks/numeracion.sh`.
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || true)"
cd "${RAIZ:-$(dirname "$0")/..}"

SALIDA="scripts/sql-manual/que_falta_pegar.sql"
TMP="$(mktemp)"
TMPC="$(mktemp)"
trap 'rm -f "$TMP" "$TMPC"' EXIT

# Desde la 0150 hacia adelante. Antes de esa no hay nada pendiente de pegar y
# listar 150 filas de historia solo esconde las que importan.
DESDE=150

# ── DE DÓNDE SALE LA LISTA, Y POR QUÉ YA NO DEL DISCO ────────────────────────
#
# Hasta el 2026-09-07 esta función hacía `ls supabase/migrations/*.sql`, o sea
# leía EL DIRECTORIO DE TRABAJO. Y ahí estaba el agujero que el 🔴#0 del
# `estado.md` llamaba «la mitad cara»:
#
#   si una migración se aplicó en producción desde un archivo que nunca se
#   commiteó, y ese archivo sigue en el disco de esa Mac, `ls` lo ve, entra a la
#   lista `repo`, y la consulta la marca «✓ aplicada». El hueco queda invisible
#   JUSTO en la máquina donde hay que verlo.
#
# Pasó tres veces: la 0177 (2026-08-07), la 0243 (2026-08-14) y la 0381
# (2026-09-05, un día entera sin que nada avisara). Ninguna la cazó una
# herramienta: las tres las encontró alguien mirando a mano.
#
# Ahora la lista sale de lo que está COMMITEADO, que es lo único que sobrevive
# a que ese disco falle:
#
#   · `origin/main` — lo que de verdad está en GitHub;
#   · `HEAD`        — lo commiteado en esta rama, que todavía no llegó a main.
#
# La UNIÓN de los dos, y no solo `origin/main`, porque si no una rama de trabajo
# vería todas las migraciones de main como «huérfanas». Lo que NO entra es el
# directorio de trabajo: un archivo sin commitear no es un ejemplar, es un
# borrador — y de eso ya avisa `migracion-sin-guardar.sh` en cada push.
#
# `sort -n` va sobre el número y no sobre el nombre, que ordenaría 0100 antes
# que 099. Y se deduplica POR NÚMERO: dos ramas pueden traer el mismo número con
# nombres distintos, y dos filas con el mismo `numero` duplicarían el join.
listar() {
  # Best-effort: si no hay red se compara contra la última foto de origin/main
  # que se trajo. Peor que estar al día, mucho mejor que mirar el disco.
  git fetch --quiet origin main 2>/dev/null || true
  {
    git ls-tree -r --name-only origin/main -- supabase/migrations 2>/dev/null
    git ls-tree -r --name-only HEAD        -- supabase/migrations 2>/dev/null
  } \
    | sed -E 's|.*/||' \
    | grep -E '^[0-9]+_.*\.sql$' \
    | awk -F_ -v d="$DESDE" '{ n = $1 + 0; if (n >= d) print }' \
    | sort -t_ -k1,1n \
    | awk -F_ '{ n = $1 + 0; if (n != visto) { print; visto = n } }'
}

if [ -z "$(listar)" ]; then
  echo "✗ No encontré migraciones en supabase/migrations. ¿Estás en la raíz del repo?" >&2
  exit 2
fi

# Las que están en el repo y NUNCA se van a aplicar, con su razón. Sin esto,
# la consulta las marcaría «FALTA PEGAR» en cada ejecución, para siempre — y un
# resumen que sale en rojo aunque todo esté bien enseña a no mirarlo. Es la
# misma razón por la que existe `huecos-conocidos.txt`.
NO_SE_PEGAN="$(dirname "$0")/hooks/no-se-pegan.txt"
nunca() {
  [ -f "$NO_SE_PEGAN" ] || return 0
  grep -E '^[0-9]+' "$NO_SE_PEGAN" | awk '{print $1 + 0}'
}

con_nombre() {
  local excluidas
  excluidas="$(nunca | tr '\n' ' ')"
  listar | sed -E "s/^0*([0-9]+)_(.*)\.sql$/\1|\2/" | while IFS='|' read -r n nom; do
    case " $excluidas " in
      *" $n "*) echo "    ($n, '$nom', true)," ;;
      *)        echo "    ($n, '$nom', false)," ;;
    esac
  done | sed '$ s/,$//'
}

# ── Las filas que sobran y YA SE EXPLICARON ─────────────────────────────────
#
# El estado «SOBRA LA FILA» (ver la consulta, más abajo) tiene dos desenlaces, y
# el segundo —«su contenido quedó superado, NO se recupera el archivo»— es
# permanente: esa fila va a estar en producción para siempre. Hasta el
# 2026-09-28 la consulta no tenía forma de saberlo, así que la 0393, investigada
# y medida el 2026-09-08, siguió saliendo como «⚠️ PEGADAS Y NO GUARDADAS» y
# «MIRA ARRIBA» en cada ejecución durante tres semanas, y el 2026-09-28 una
# sesión volvió a abrir desde cero una decisión que ya estaba tomada. El único
# aviso de esta consulta que cazó la 0177, la 0243 y la 0381 estaba aprendiendo
# a leerse como ruido.
#
# Se declara en `huecos-conocidos.txt`, que es donde ya vive la explicación, con
# una marca en la misma línea: `0393  [sobra la fila: <nombre>] <razón>`. Lee
# del árbol que se empuja y no del que guarda el script, por la misma razón que
# `hooks/numeracion.sh`: una rama puede explicar algo que `main` todavía no.
#
# POR QUÉ NÚMERO Y NOMBRE, no solo el número. Desde el 2026-09-10 el registro se
# escribe con `do update set nombre`: si otra migración se pega mañana con el
# número 393, la fila cambia de nombre. Esa fila sería una huérfana NUEVA, y una
# excepción atada solo al número la callaría. Es la misma lección de la 0405 y la
# 0409: un registro se verifica por `numero` Y `nombre`.
HUECOS_CONOCIDOS="scripts/hooks/huecos-conocidos.txt"
explicadas_cte() {
  local filas=""
  if [ -f "$HUECOS_CONOCIDOS" ]; then
    filas="$(grep -E '^[0-9]+[[:space:]]+\[sobra la fila: [^]]+\]' "$HUECOS_CONOCIDOS" \
      | sed -E "s/^0*([0-9]+)[[:space:]]+\[sobra la fila: ([^]]+)\].*/(\1, '\2')/" \
      | paste -sd, - || true)"
  fi
  if [ -n "$filas" ]; then
    echo "explicadas(numero, nombre) as (values $filas),"
  else
    # `values` vacío no es SQL válido; una lista sin filas sí.
    echo "explicadas(numero, nombre) as (select null::int, null::text where false),"
  fi
}

# ── El catálogo de versiones de fn_planilla_calcular, CALCULADO ──────────────
#
# Hasta el 2026-08-08 estas líneas se escribían a mano, y ese día mintieron TRES
# veces en una jornada: nacieron conociendo hasta la 0177, y mientras tanto
# entraron la 0185, 0186, 0187, 0192 y 0193. Cada vez la consulta decía «md5 SIN
# CATALOGAR» sobre una versión perfectamente conocida, y cada vez hubo que parar
# a comprobar si era una alarma real. Un aviso que grita por nada se deja de leer.
#
# Es exactamente lo que la cabecera de este script ya predicaba sobre la lista de
# migraciones: «si es un número que un comando puede calcular, no va escrito —
# va el comando». La lista lo cumplía; el catálogo no.
#
# CÓMO SE CALCULA. Se extrae el cuerpo de cada `create or replace function
# fn_planilla_calcular` de las migraciones y se le saca el md5, que es el mismo
# que Postgres guarda en `prosrc`. Comprobado contra los cinco valores medidos a
# mano el 2026-08-08 (0185, 0186, 0187, 0192, 0193): idénticos los cinco.
#
# Y DE CADA UNA SALEN DOS. La segunda es el mismo cuerpo pasado por Mac OS Roman
# —`iconv -f MAC`, que reproduce el daño byte a byte—, porque el 2026-08-08 la
# 0185 llegó a producción así y el catálogo la dio por desconocida. Distinguir
# «versión que no conozco» de «versión conocida, mal pegada» es la diferencia
# entre una alarma y una instrucción.
md5de() {
  if command -v md5 >/dev/null 2>&1; then md5 -q; else md5sum | cut -d' ' -f1; fi
}

# Lo que hace `pbcopy` con LC_CTYPE=C (0185): leer UTF-8 como Mac OS Roman. En la
# Mac es el `iconv` de siempre. Fuera de la Mac NO: el `iconv -f MAC` de glibc
# (Linux, las sesiones en la nube) traduce algún byte distinto que el de Apple
# —el 0xF0 es la manzana U+F8FF en Apple—, y el 2026-11-12 eso dio otro md5 para
# la 0476 (b04fd8e2… contra el 93e3ea7d… de main) y el hook de pre-push
# «arregló» el archivo bueno con el valor malo. El `mac_roman` de Python es el
# mapeo de Apple: con él, Linux da el mismo md5 que la Mac (medido con la 0476).
mac_roman_a_utf8() {
  if [ "$(uname)" != Darwin ] && command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; sys.stdout.buffer.write(sys.stdin.buffer.read().decode("mac_roman").encode())'
  else
    iconv -f MAC -t UTF-8
  fi
}

# ── DE UNA FUNCIÓN A SU md5, como lo guardaría Postgres ─────────────────────
#
# Hasta el 2026-11-09 esto servía solo a `fn_planilla_calcular`, solo con los
# delimitadores `$$` y `$function$`, y solo tal cual. Desde entonces vale para
# cualquier función de `hooks/funciones-de-plata.txt`, y de cada versión salen
# las formas en que de verdad llega a producción:
#
#   tal          el cuerpo exacto, que es lo que Postgres guarda en `prosrc`
#   pelado       sin comentarios: la mitad de las funciones de producción se
#                pegó así (medido el 2026-08-18). La regla es la MISMA que usa
#                `donde-vive.sh` en SQL —fuera la línea cuyo texto sin espacios
#                empieza con `--`, y de cada línea, desde el primer `--`—, para
#                que los dos digan lo mismo de la misma función.
#   crlf         pegada desde Windows: cada salto de línea llega como \r\n (0401)
#   crlf_pelado  pegada desde Windows y sin comentarios
#
# Y de la vigente, además, la de los acentos rotos (Mac OS Roman, 0185).
#
# Del archivo se toma la ÚLTIMA definición, no la primera: una migración que
# crea la función y la vuelve a crear más abajo deja viva la segunda. El cuerpo
# va desde lo que sigue al delimitador de apertura hasta justo antes del de
# cierre, aunque compartan línea con otro texto: así lo guarda Postgres, y un
# salto de línea de más o de menos cambia el md5 sin que se vea nada distinto.
#
# CADA ARCHIVO SE LEE UNA SOLA VEZ. La primera versión de esto pasaba un `awk`
# por función, por archivo y por forma: con las migraciones de planilla, de
# miles de líneas cada una, el script pasó de 5 a 27 segundos, y corre en cada
# push. Ahora un solo recorrido por archivo saca las funciones de la lista que
# defina, en sus cuatro formas, a archivos sueltos en `$CUERPOS/<función>/`; y
# los md5 se calculan todos de una vez.
EXTRAER_AWK='
BEGIN { n = split(lista, F, " "); est = 0 }
function abrir(s,   p, resto) {
  if (!match(s, /[$][A-Za-z_]*[$]/)) return
  delim = substr(s, RSTART, RLENGTH); resto = substr(s, RSTART + RLENGTH)
  p = index(resto, delim)
  if (p > 0) { ultimo[actual] = substr(resto, 1, p - 1); est = 0; return }
  buf = resto "\n"; est = 2
}
est == 0 {
  if ($0 ~ /^[ \t]*--/) next
  l = tolower($0)
  if (l !~ /create[ \t]+(or[ \t]+replace[ \t]+)?function/) next
  for (i = 1; i <= n; i++) {
    if (match(l, "create[ \t]+(or[ \t]+replace[ \t]+)?function[ \t]+(public[.])?" F[i] "[ \t]*[(]")) {
      actual = F[i]; est = 1; abrir(substr($0, RSTART + RLENGTH)); break
    }
  }
  next
}
est == 1 { abrir($0); next }
est == 2 {
  p = index($0, delim)
  if (p > 0) { ultimo[actual] = buf substr($0, 1, p - 1); est = 0; next }
  buf = buf $0 "\n"; next
}
function pelar(t,   m, L, j, x, y, out, primero) {
  m = split(t, L, "\n"); out = ""; primero = 1
  for (j = 1; j <= m; j++) {
    x = L[j]; y = x; gsub(/^ +| +$/, "", y)
    if (substr(y, 1, 2) == "--") continue
    sub(/[[:space:]]*--.*$/, "", x)
    out = primero ? x : out "\n" x; primero = 0
  }
  return out
}
function escribir(ruta, t) { printf "%s", t > ruta; close(ruta) }
END {
  for (f in ultimo) {
    t = ultimo[f]; if (t ~ /^[ \t\r\n]*$/) continue
    base = dir "/" f "/" num
    p = pelar(t); c = t; cp = p
    gsub(/\n/, "\r\n", c); gsub(/\n/, "\r\n", cp)
    escribir(base ".tal", t); escribir(base ".pelado", p)
    escribir(base ".crlf", c); escribir(base ".crlf_pelado", cp)
  }
}
'

FUNCIONES_DE_PLATA="scripts/hooks/funciones-de-plata.txt"
funciones_de_plata() {
  [ -f "$FUNCIONES_DE_PLATA" ] || return 0
  grep -E '^fn_[a-z0-9_]+' "$FUNCIONES_DE_PLATA" | awk '{print $1}'
}

# Extrae, una vez, el cuerpo de cada versión de cada función de la lista.
CUERPOS="$(mktemp -d)"
trap 'rm -f "$TMP" "$TMPC"; rm -rf "$CUERPOS"' EXIT
extraer_cuerpos() {
  LISTA="$(funciones_de_plata | tr '\n' ' ')"
  [ -z "$LISTA" ] && return 0
  for fn in $LISTA; do mkdir -p "$CUERPOS/$fn"; done
  ALTERNATIVAS="$(echo $LISTA | tr ' ' '|')"
  # `-l -i -E` y no `-lieE`: en el grep de esta Mac (ugrep) el `-e` del medio se
  # come el patrón como si fuera su argumento, y la lista sale vacía sin avisar.
  grep -l -i -E "create[ \t]+(or[ \t]+replace[ \t]+)?function[ \t]+(public\.)?(${ALTERNATIVAS})[ \t]*\(" \
       supabase/migrations/*.sql 2>/dev/null | sort | while read -r f; do
    NUM=$(basename "$f" | sed -E 's/^([0-9]+)_.*/\1/')
    awk -v lista="$LISTA" -v dir="$CUERPOS" -v num="$NUM" "$EXTRAER_AWK" "$f"
  done
}

# «md5 ruta» por línea, para muchos archivos de una vez.
md5_de_archivos() {
  if command -v md5 >/dev/null 2>&1; then md5 -r "$@"; else md5sum "$@" | awk '{print $1 " " $2}'; fi
}

# Los WHEN del CASE de una función: cada md5 conocido y lo que significa.
#
# EL VIGENTE VA PRIMERO, en sus cuatro formas. Un CASE de SQL resuelve por el
# PRIMER WHEN que coincide, y dos versiones pueden ser textualmente iguales: la
# 0339 partió `fn_planilla_calcular` en núcleo y envoltorio, y el envoltorio no
# volvió a cambiar. Si una etiqueta vieja («se quedó en la 0339») fuera antes,
# escondería para siempre a la correcta detrás de una alarma falsa: pasó el
# 2026-09-04 y dijo que producción llevaba diez migraciones de atraso en la
# función que paga a todos, cuando estaba al día. Después, las viejas de la más
# nueva a la más antigua, y cada md5 una sola vez.
catalogo() {
  FN="$1"; D="$CUERPOS/$FN"
  NUM_ULTIMO=$(ls "$D" 2>/dev/null | sed -E 's/\..*//' | sort -n | tail -1)
  [ -z "$NUM_ULTIMO" ] && return 0
  {
    md5_de_archivos "$D/$NUM_ULTIMO.tal" "$D/$NUM_ULTIMO.pelado" "$D/$NUM_ULTIMO.crlf" "$D/$NUM_ULTIMO.crlf_pelado" \
      | while read -r h ruta; do
          case "$ruta" in
            *.tal)         como="" ;;
            *.crlf_pelado) como=", desde Windows y sin comentarios" ;;
            *.pelado)      como=", pegada sin comentarios" ;;
            *.crlf)        como=", pegada desde Windows" ;;
          esac
          echo "             when '$h' then '✓   al día ($NUM_ULTIMO$como)'"
        done
    ROTO=$(mac_roman_a_utf8 < "$D/$NUM_ULTIMO.tal" 2>/dev/null | md5de)
    [ -n "$ROTO" ] && echo "             when '$ROTO' then '✗   $NUM_ULTIMO con los acentos rotos — vuelve a pegarla'"
    VIEJAS=$(ls "$D" | sed -E 's/\..*//' | sort -un | grep -v -x "$NUM_ULTIMO" | sort -rn)
    for NUM in $VIEJAS; do
      md5_de_archivos "$D/$NUM.tal" "$D/$NUM.pelado" | while read -r h ruta; do
        echo "             when '$h' then '❌  se quedó en la $NUM — la vigente es la $NUM_ULTIMO'"
      done
    done
  } | awk -F"'" '!visto[$2]++'
}

# El número de la migración que RETIRÓ la función, si la última que la toca la
# borra: un `drop function` (en código, no en el «cómo se revierte» de un
# comentario) posterior a su última definición. Una retirada que no existe en
# producción está bien; una retirada que sigue viva es la alarma.
retirada_en() {
  FN="$1"
  ULT_DROP=$(grep -l -i -E "^[[:space:]]*drop[[:space:]]+function[[:space:]]+(if[[:space:]]+exists[[:space:]]+)?(public\.)?${FN}[[:space:]]*(\(|;)" \
               supabase/migrations/*.sql 2>/dev/null | sort | tail -1)
  [ -z "$ULT_DROP" ] && return 0
  N_DROP=$(basename "$ULT_DROP" | sed -E 's/^0*([0-9]+)_.*/\1/')
  N_CREA=$(ls "$CUERPOS/$FN" 2>/dev/null | sed -E 's/\..*//; s/^0*//' | sort -n | tail -1)
  # Mayor ESTRICTO: la que borra y vuelve a crear en el mismo archivo (para
  # cambiar lo que devuelve, como la 0161) no la retira.
  if [ -z "$N_CREA" ] || [ "$N_DROP" -gt "$N_CREA" ]; then
    basename "$ULT_DROP" | sed -E 's/^([0-9]+)_.*/\1/'
  fi
}

# Una fila de la consulta por cada función de la lista. La de planilla conserva
# su nombre de siempre, PLANILLA, porque así la nombran el CLAUDE.md y quienes
# la leen; el núcleo también, porque desde la 0339 es el que de verdad calcula.
filas_de_plata() {
  i=0
  funciones_de_plata | while read -r fn; do
    i=$((i + 1))
    case "$fn" in fn_planilla_calcular*) etiqueta="PLANILLA" ;; *) etiqueta="PLATA" ;; esac
    [ "$i" -gt 1 ] && echo "  union all"
    RETIRADA=$(retirada_en "$fn")
    if [ -n "$RETIRADA" ]; then
      echo "  select '$etiqueta', '$fn', coalesce(("
      echo "           select '❌  sigue viva aunque la $RETIRADA la retiró'"
      echo "           from pg_proc p join pg_namespace n on n.oid = p.pronamespace"
      echo "           where n.nspname = 'public' and p.proname = '$fn' limit 1"
      echo "         ), '✓   retirada en la $RETIRADA, como debe'), $((1000000 + i))"
      continue
    fi
    echo "  select '$etiqueta', '$fn', coalesce(("
    echo "           select string_agg(case md5(p.prosrc)"
    catalogo "$fn"
    echo "             else '⚠   md5 sin catalogar: ' || left(md5(p.prosrc), 8) || ' — mídela con ./scripts/donde-vive.sh $fn'"
    echo "           end, ' · ')"
    echo "           from pg_proc p join pg_namespace n on n.oid = p.pronamespace"
    echo "           where n.nspname = 'public' and p.proname = '$fn'"
    echo "         ), '⚠   la función NO EXISTE'), $((1000000 + i))"
  done
}

extraer_cuerpos

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
--   · en qué versión está VIVA cada función que calcula, mueve o reporta plata
--     (la lista: scripts/hooks/funciones-de-plata.txt)
--
-- LO QUE EL REGISTRO NO PUEDE VER
--   Que una migración esté anotada NO prueba que su contenido siga vivo: una
--   pegada posterior pudo pisarlo sin dar ningún error. Pasó con
--   fn_costos_planilla: el 2026-11-09 era la de la 0099 aunque la 0260 y la 0323
--   figuraban aplicadas, y esta consulta no lo vio en cinco semanas porque solo
--   miraba el registro y fn_planilla_calcular. Por eso las filas PLANILLA y
--   PLATA miran el cuerpo real de cada función. «Al día» acepta las formas en
--   que una función llega a producción —tal cual, sin comentarios, desde
--   Windows—; «se quedó en la NNN» o «sin catalogar» es para mirar ese día.
-- ============================================================================

with repo(numero, nombre, nunca) as (values
CAB
con_nombre
cat <<'PIE'
),
diff as (
  -- `falta` NO incluye las que nunca se van a aplicar: esas se explican aparte
  -- y no cuentan como pendientes.
  select r.numero, r.nombre, r.nunca,
         (a.numero is null and not r.nunca) as falta,
         (a.numero is null and r.nunca)     as nunca_ira,
         a.aplicada_at
  from repo r
  left join migraciones_aplicadas a on a.numero = r.numero
),
-- ⚠️ LA PREGUNTA AL REVÉS, que es la que de verdad duele.
--
-- Todo lo de arriba responde «¿qué le falta a producción?». Esta responde
-- «¿qué tiene producción que NO está guardado en ninguna parte?» — una
-- migración aplicada cuyo único ejemplar puede ser un archivo sin commitear en
-- una Mac. Si ese disco falla, el SQL desaparece y `db reset` deja de poder
-- reconstruir el esquema.
--
-- Pasó tres veces (0177, 0243, 0381) y ninguna la cazó una herramienta: la
-- lista de arriba salía del DISCO, así que el archivo sin commitear entraba en
-- ella y se marcaba «✓ aplicada». Ahora la lista viene de git, así que lo que
-- no esté commiteado en ningún lado aparece acá.
--
-- SE LLAMA «SOBRA LA FILA» PORQUE ASÍ LA LLAMA YA `huecos-conocidos.txt`, que
-- desde su primera versión manda buscar ese estado exacto antes de silenciar un
-- hueco. Prometía una comprobación que nadie había construido: hasta el
-- 2026-09-07 ese texto no existía en ninguna parte del script ni de la consulta.
--
-- QUÉ HACER CUANDO APARECE UNA, y son dos cosas distintas que conviene no
-- confundir — el detector encuentra la discrepancia, no decide qué significa:
--
--   a) La migración existe y no se guardó → COMMITEARLA HOY. Es el caso de la
--      0177, la 0243 y la 0381.
--   b) El número se anotó pero su contenido quedó SUPERADO por migraciones
--      posteriores que sí están guardadas → NO commitear el archivo viejo, que
--      podría crear una sobrecarga y repetir el «function is not unique» de la
--      0297/0299. Se anota en `huecos-conocidos.txt` con su razón y la marca
--      `[sobra la fila: <nombre>]`: desde entonces sale acá como «ya
--      explicada» y deja de contar como alarma. Es el caso de la 0393, medido
--      el 2026-09-08.
--
-- Para distinguirlas hay que mirar si lo que esa migración creaba sigue vigente
-- en producción con la misma firma. Cero filas SIN EXPLICAR es lo normal.
PIE
explicadas_cte
cat <<'PIE1'
huerfanas as (
  select a.numero, a.nombre, a.aplicada_at,
         exists (select 1 from explicadas e
                  where e.numero = a.numero and e.nombre = a.nombre) as explicada
  from migraciones_aplicadas a
  where a.numero >= (select min(numero) from repo)
    and not exists (select 1 from repo r where r.numero = a.numero)
),
-- Las funciones de plata, por su cuerpo y no por el registro.
plata(etiqueta, funcion, estado, orden) as (
PIE1
filas_de_plata
cat <<'PIE1B'
)
select * from (
  -- Una fila por migración.
  select d.numero::text                        as num,
         d.nombre                              as que,
         case when d.falta     then '❌  FALTA PEGAR'
              when d.nunca_ira then '—   no se pega (ver scripts/hooks/no-se-pegan.txt)'
              else                  '✓   aplicada' end as estado,
         to_char(d.aplicada_at, 'DD/MM/YYYY')  as cuando,
         d.numero                              as orden
  from diff d

  union all

  -- Las huérfanas, una fila cada una y ANTES del resumen. Si hay alguna sin
  -- explicar, es lo único que importa de toda esta consulta. Las explicadas se
  -- siguen viendo —como las que no se pegan—, pero con su razón al lado.
  select a.numero::text,
         a.nombre,
         case when a.explicada
              then '—   sobra la fila, ya explicada (ver scripts/hooks/huecos-conocidos.txt)'
              else '⚠️  SOBRA LA FILA — revísala (ver abajo)' end,
         to_char(a.aplicada_at, 'DD/MM/YYYY'),
         999997
  from huerfanas a

  union all

  -- El resumen, al final y separado.
  select '——', '', '', '', 999998
  union all
  select 'RESUMEN',
         (select count(*) filter (where falta) from diff)::text || ' faltan · ' ||
         (select count(*) filter (where not falta and not nunca_ira) from diff)::text || ' aplicadas · ' ||
         (select count(*) filter (where nunca_ira) from diff)::text || ' que no se pegan · ' ||
         (select count(*) from diff)::text || ' en git' ||
         case when (select count(*) filter (where not explicada) from huerfanas) > 0
              then ' · ⚠️ ' || (select count(*) filter (where not explicada) from huerfanas)::text || ' PEGADAS Y NO GUARDADAS'
              else '' end ||
         case when (select count(*) from plata where estado not like '✓%') > 0
              then ' · ❌ ' || (select count(*) from plata where estado not like '✓%')::text || ' FUNCIONES DE PLATA NO ESTÁN AL DÍA'
              else '' end,
         -- Una huérfana sin explicar manda sobre todo lo demás: que falte pegar
         -- algo es atraso normal; que algo esté pegado y sin guardar es lo que
         -- costó tres sustos y no avisa solo.
         case when (select count(*) filter (where not explicada) from huerfanas) > 0 then '⚠️  MIRA ARRIBA'
              -- Una función de plata atrasada va antes que lo que falta pegar: el
              -- registro dice que está y el cuerpo dice que no.
              when (select count(*) from plata where estado not like '✓%') > 0 then '❌  MIRA ABAJO'
              when (select count(*) filter (where falta) from diff) = 0
              then '✓   al día' else '❌  hay pendientes' end,
         '', 999999

  union all

  -- Lo que el registro no puede responder: qué versión de cada función de plata
  -- está viva de verdad.
  select etiqueta, funcion || ' · versión viva', estado, '', orden from plata

  union all

  -- El barrido, que no depende de ninguna lista escrita a mano y por eso vale
  -- más que las filas de arriba: cuenta CUALQUIER función cuyo cuerpo lleve el
  -- signo «√», que en castellano no aparece nunca dentro de un mensaje. Su
  -- presencia siempre significa lo mismo: el texto entró leído como Mac OS
  -- Roman y cada acento quedó partido en dos.
  --
  -- La lógica no cambia —solo se rompen los mensajes que lee una persona— pero
  -- es la señal de que algo en el camino de pegado corrompe el texto, y eso hay
  -- que saberlo el mismo día, no dentro de un mes.
  select 'ACENTOS',
         'funciones con el texto roto',
         coalesce((
           select case when count(*) = 0 then '✓   ninguna'
                       else '❌  ' || count(*)::text || ': ' || string_agg(proname, ' ' order by proname) end
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'fn\_%'
             and p.prosrc like '%' || chr(8730) || '%'
         ), '—'),
         '', 2000000
) t
order by orden;
PIE1B
} > "$TMP"

al_dia() { [ -f "$SALIDA" ] && cmp -s "$TMP" "$SALIDA"; }
N=$(listar | wc -l | tr -d ' ')

# `--check` solo mira y no toca nada. Lo usa quien quiera preguntar sin efectos.
if [ "$1" = "--check" ]; then
  if al_dia; then exit 0; fi
  echo ""
  echo "  ✗ '$SALIDA' está desfasado: el repo tiene migraciones que la consulta no lista."
  echo "    Corre  ./scripts/que-falta-pegar.sh"
  echo ""
  exit 1
fi

# ── `--arregla`: lo que corre el hook de pre-push ───────────────────────────
#
# POR QUÉ NO SE LIMITA A AVISAR. Hasta el 2026-08-08 el hook comprobaba y, si
# estaba viejo, mandaba a correr este script a mano. En un solo día frenó CUATRO
# pushes por lo mismo, siempre con la misma solución de una línea. Un guardián
# que te para para pedirte algo que él mismo puede hacer enseña dos cosas malas:
# que sus avisos son trámite, y que `--no-verify` los quita. El día que frene por
# algo de verdad —un número duplicado, una prueba en rojo— va a estar hablándole
# a alguien que ya aprendió a saltárselo.
#
# POR QUÉ IGUAL ABORTA EL PUSH. Git ya calculó qué commits va a enviar antes de
# llamar al hook: el commit que se crea aquí no viajaría en este push. Abortar y
# pedir un segundo `git push` es lo único honesto — la alternativa sería subir a
# GitHub una versión de la consulta distinta de la que quedó en el disco.
#
# POR QUÉ `git commit -o`. En este repo varias sesiones comparten el índice de
# git, y un `git add` + `commit` corriente puede llevarse dentro lo que otra
# sesión acaba de preparar. La forma con `-o` commitea EXACTAMENTE esta ruta y
# nada más, mire como mire el índice.
if [ "$1" = "--arregla" ]; then
  if al_dia; then exit 0; fi
  cp "$TMP" "$SALIDA"

  # No se commitea en medio de una operación de git a medias ni con la cabeza
  # suelta: ahí un commit automático es una sorpresa, no una ayuda.
  GITDIR="$(git rev-parse --git-dir 2>/dev/null || echo .git)"
  if ! git symbolic-ref -q HEAD >/dev/null 2>&1 \
     || [ -e "$GITDIR/MERGE_HEAD" ] || [ -e "$GITDIR/CHERRY_PICK_HEAD" ] \
     || [ -d "$GITDIR/rebase-merge" ] || [ -d "$GITDIR/rebase-apply" ]; then
    echo ""
    echo "  ⚠ '$SALIDA' estaba desfasado y lo regeneré ($N migraciones)."
    echo "    NO lo commiteé: hay una operación de git a medias o la cabeza está suelta."
    echo "    Commitéalo tú y vuelve a empujar."
    echo ""
    exit 1
  fi

  if git commit -q -o "$SALIDA" -m "La consulta de qué falta pegar se pone al día sola

Regenerada por el hook de pre-push: el repo tenía migraciones que la consulta no
listaba, así que habría dicho «todo al día» ocultando justo las nuevas.

$N migraciones desde la $DESDE." 2>/dev/null; then
    echo ""
    echo "  ✓ '$SALIDA' estaba desfasado. Lo regeneré y lo commiteé ($N migraciones)."
    echo "    Vuelve a empujar:  git push"
    echo ""
  else
    echo ""
    echo "  ⚠ '$SALIDA' estaba desfasado y lo regeneré ($N migraciones)."
    echo "    No pude commitearlo. Hazlo tú y vuelve a empujar."
    echo ""
  fi
  exit 1
fi

cp "$TMP" "$SALIDA"
echo "✓ $SALIDA regenerado · $N migraciones desde la $DESDE"
echo "  Pégalo entero en el SQL Editor de producción. Solo lee."
