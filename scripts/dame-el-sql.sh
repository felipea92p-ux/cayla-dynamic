#!/bin/sh
# Entrega una migración para pegar en el SQL Editor — y solo si está a salvo.
#
# ── EL AGUJERO QUE CIERRA ───────────────────────────────────────────────────
#
# El 2026-08-07 se descubrió que la migración 0177 —que cambia cómo se pagan las
# vacaciones— estaba APLICADA EN PRODUCCIÓN y su único ejemplar en el mundo era
# un archivo sin commitear en el disco de una Mac. No estaba en GitHub. Si ese
# disco fallaba, nadie podía saber qué se le había hecho al cálculo de planilla
# ni cómo deshacerlo.
#
# Ninguno de los frenos que ya existían lo veía:
#   · `desplegar.sh` protege de PUBLICAR código sin guardar, no de PEGARLO;
#   · `hooks/pre-push` solo mira lo que se empuja;
#   · la prueba pgTAP 122 compara la base contra los archivos del disco —
#     incluidos los que nadie guardó.
#
# Los tres cuidan el camino de Vercel. El SQL a producción va por otro camino:
# alguien abre un archivo, lo copia y lo pega. Ese camino no tenía freno.
#
# ── POR QUÉ ENTREGA EL ARCHIVO EN VEZ DE SOLO AVISAR ────────────────────────
#
# Un script que solo dice «ojo, verifica antes de pegar» se olvida el día que hay
# prisa. Este se pone en el medio: es la forma más CÓMODA de obtener el SQL —te
# lo deja copiado en el portapapeles— y de paso comprueba. Si el archivo no está
# a salvo, no te lo da y te dice exactamente qué falta.
#
# ── QUÉ COMPRUEBA, Y POR QUÉ LAS TRES ───────────────────────────────────────
#
#   1. Que git lo conozca. Un archivo sin `git add` no existe para nadie más.
#   2. Que lo guardado sea lo que vas a pegar. Con cambios sin commitear,
#      producción recibiría una versión que el repo no tiene.
#   3. Que esté en GitHub, byte por byte. Es la única de las tres que sobrevive
#      a que esta Mac se rompa — y es la que faltó con la 0177.
#
# CÓMO SE USA
#   ./scripts/dame-el-sql.sh 173        una migración por su número
#   ./scripts/dame-el-sql.sh 0173       da igual con ceros o sin ellos
#   ./scripts/dame-el-sql.sh scripts/sql-manual/encender_sexto_cts.sql
#
# Qué NO hace: no se conecta a producción ni ejecuta nada. Solo lee y copia.

set -e

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || true)"
cd "${RAIZ:-$(dirname "$0")/..}"

rojo()  { printf "\033[31m%s\033[0m\n" "$1"; }
verde() { printf "\033[32m%s\033[0m\n" "$1"; }
ambar() { printf "\033[33m%s\033[0m\n" "$1"; }
gris()  { printf "\033[90m%s\033[0m\n" "$1"; }

if [ -z "${1:-}" ]; then
  rojo "✗ Falta decir qué SQL quieres."
  gris "  ./scripts/dame-el-sql.sh 173"
  gris "  ./scripts/dame-el-sql.sh scripts/sql-manual/encender_sexto_cts.sql"
  gris ""
  gris "  ¿No sabes cuál falta?  ./scripts/que-falta-pegar.sh"
  exit 1
fi

# ── Encontrar el archivo ────────────────────────────────────────────────────
# Un número busca en migraciones; cualquier otra cosa se toma como ruta.
if echo "$1" | grep -qE '^[0-9]+$'; then
  NUM=$(printf "%04d" "$1")
  ARCHIVO=$(ls supabase/migrations/${NUM}_*.sql 2>/dev/null | head -1 || true)
  if [ -z "$ARCHIVO" ]; then
    rojo "✗ No hay ninguna migración $NUM en supabase/migrations."
    gris "  La última es: $(ls -1 supabase/migrations | tail -1)"
    exit 1
  fi
else
  ARCHIVO="$1"
  if [ ! -f "$ARCHIVO" ]; then
    rojo "✗ No existe el archivo: $ARCHIVO"
    exit 1
  fi
fi

echo ""
echo "  $ARCHIVO"
gris "  $(wc -l < "$ARCHIVO" | tr -d ' ') líneas"
echo ""

FALLO=0

# ── 1 · ¿Git lo conoce? ─────────────────────────────────────────────────────
if ! git ls-files --error-unmatch "$ARCHIVO" >/dev/null 2>&1; then
  rojo "✗ Este archivo NO está en git. Existe solo en este disco."
  gris "    git add \"$ARCHIVO\" && git commit && git push"
  FALLO=1
else
  # ── 2 · ¿Lo guardado es lo que vas a pegar? ───────────────────────────────
  if ! git diff --quiet HEAD -- "$ARCHIVO" 2>/dev/null; then
    rojo "✗ Tiene cambios sin commitear: pegarías algo que el repo no tiene."
    gris "    git add \"$ARCHIVO\" && git commit && git push"
    FALLO=1
  fi

  # ── 3 · ¿Está en GitHub, byte por byte? ───────────────────────────────────
  # `git fetch` primero: sin él se compara contra una foto vieja de origin/main
  # y un archivo empujado hace un minuto parecería ausente.
  git fetch origin --quiet 2>/dev/null || gris "  (sin red: se compara con lo último que se trajo de GitHub)"

  if ! git cat-file -e "origin/main:$ARCHIVO" 2>/dev/null; then
    rojo "✗ NO está en GitHub. Si este disco falla, este SQL desaparece."
    gris "    Es exactamente lo que pasó con la 0177 el 2026-08-07."
    gris "    git push"
    FALLO=1
  elif ! git diff --quiet origin/main -- "$ARCHIVO" 2>/dev/null; then
    rojo "✗ Lo que hay en GitHub NO es igual a este archivo."
    gris "    Pegarías una versión que nadie más tiene. Empuja lo tuyo:"
    gris "    git push"
    FALLO=1
  fi
fi

# ── 4 · ¿Alguna migración POSTERIOR redefine lo mismo? ──────────────────────
#
# EL AGUJERO QUE CIERRA, medido el 2026-08-08. Producción tenía la 0177 anotada
# como aplicada y sin embargo `fn_planilla_calcular` corría el cuerpo de la 0173:
# las vacaciones habían dejado de pagarse como días trabajados. Las horas de
# pegado descartaron el orden —la 0177 entró once segundos DESPUÉS de la 0173— y
# ninguna migración posterior la redefine.
#
# La pisó un archivo suelto. Cinco `aplicar_*.sql` llevaban dentro el cuerpo
# ENTERO de la función, cada uno con una versión distinta; pegar cualquiera para
# arreglar otra cosa revertía la planilla en silencio, sin error y sin aviso. Los
# cuatro obsoletos se borraron ese día, pero eso NO cerraba el agujero: las
# migraciones siguen en el repo y este mismo script las entrega. `dame-el-sql.sh
# 166` te da el cuerpo de julio con una sonrisa.
#
# Y no queda rastro: las migraciones se anotan con `on conflict (numero) do
# nothing`, así que un repegado sobrescribe la función sin actualizar la fila. La
# hora que ves es la del PRIMER pegado. La evidencia se destruye por diseño, y por
# eso no se pudo saber quién lo hizo.
#
# Ya había pasado antes con `fn_crear_periodo` y `fn_eliminar_periodo`: eso es la
# 0183. Dos veces, dos funciones, el mismo mecanismo.
#
# Solo AVISA, no bloquea: reaplicar una migración vieja a propósito es legítimo
# (revertir algo, reparar una base a medias). Lo que no puede pasar es hacerlo
# creyendo que no tiene consecuencias.
# El número sale de las DOS formas de nombrar que usa este repo:
#   0163_las_truncas_descuentan.sql   ← una migración
#   aplicar_0163.sql                  ← su copia lista para pegar
#
# Hasta el 2026-08-08 solo se reconocía la primera, así que esta comprobación
# **no corría para ningún `aplicar_*`** — justo los archivos que causaron el
# incidente que la motivó. Y no corría en silencio: entregaba el SQL sin decir
# una palabra, que es peor que no tener la comprobación, porque quien la conoce
# confía en ella.
NUM_PEDIDO=$(basename "$ARCHIVO" | sed -nE 's/^([0-9]+)_.*/\1/p')
[ -z "$NUM_PEDIDO" ] && NUM_PEDIDO=$(basename "$ARCHIVO" | sed -nE 's/^aplicar_0*([0-9]+).*/\1/p')

# Si aun así no hay número, la comprobación NO puede correr — y hay que decirlo.
# Un chequeo que se salta callado enseña que estaba en verde cuando en realidad
# ni miró. Es la misma regla que el resto de este repositorio viene aplicando:
# un dato ausente y un resultado limpio no pueden verse iguales.
if [ -z "$NUM_PEDIDO" ]; then
  echo ""
  gris "  (No pude sacar un número de este nombre, así que no comprobé si"
  gris "   revierte algo que una migración posterior ya arregló. Si lleva dentro"
  gris "   el cuerpo de una función, míralo con ./scripts/donde-vive.sh)"
fi

if [ -n "$NUM_PEDIDO" ]; then
  PISARIA=""
  # Las dos formas de definir que usa este repo: `create or replace function` y
  # el `drop` + `create` de las que devuelven TABLE. Mayúsculas o minúsculas, con
  # prefijo `public.` o sin él — la 0081 escribe distinto que las demás.
  FUNCS=$(grep -oiE "function[[:space:]]+(public\.)?fn_[a-z0-9_]+" "$ARCHIVO" 2>/dev/null \
          | sed -E 's/.*(fn_[a-zA-Z0-9_]+)/\1/' | tr 'A-Z' 'a-z' | sort -u)

  for fn in $FUNCS; do
    ULTIMA=""
    for otra in supabase/migrations/*.sql; do
      n=$(basename "$otra" | sed -nE 's/^([0-9]+)_.*/\1/p')
      [ -z "$n" ] && continue
      [ "$n" -le "$NUM_PEDIDO" ] 2>/dev/null && continue
      if grep -qiE "function[[:space:]]+(public\.)?${fn}[[:space:]]*\(" "$otra" 2>/dev/null; then
        ULTIMA="$n  $(basename "$otra" .sql)"
      fi
    done
    [ -n "$ULTIMA" ] && PISARIA="${PISARIA}    ${fn}
      la redefine después la ${ULTIMA}
"
  done

  if [ -n "$PISARIA" ]; then
    echo ""
    ambar "⚠ OJO: esto REVIERTE funciones que una migración posterior ya arregló."
    printf "%s" "$PISARIA"
    gris "  Pegarlo devuelve esas funciones a la versión de esta migración, sin"
    gris "  error y sin aviso. Y no quedará rastro: el apunte no se actualiza al"
    gris "  repegar, así que después nadie podrá saber que pasó."
    echo ""
    gris "  Si lo que quieres es la versión VIGENTE, pide la última:"
    gris "    ./scripts/donde-vive.sh <nombre_de_la_funcion>"
    echo ""
  fi
fi

if [ "$FALLO" = "1" ]; then
  echo ""
  rojo "  NO lo pegues todavía."
  gris "  Arregla lo de arriba y vuelve a correr esto."
  echo ""
  exit 1
fi

# ── A salvo: al portapapeles ────────────────────────────────────────────────
verde "✓ Guardado en git y en GitHub. Se puede pegar."
if command -v pbcopy >/dev/null 2>&1; then
  # LC_CTYPE=UTF-8 NO ES DECORACIÓN. Sin esto, pbcopy lee los bytes como
  # MacRoman —el locale de esta Mac es LC_CTYPE="C"— y deja en el portapapeles
  # un texto donde cada tilde se partió en dos: «función» sale «funci√≥n» y
  # «⚠️» sale «‚ö†Ô∏è». El navegador pega ESO, y queda guardado así en la base.
  #
  # Engaña porque `pbpaste` con el mismo locale deshace la conversión y todo se
  # ve bien desde el terminal. Solo se nota al mirar la función ya aplicada.
  #
  # Se descubrió el 2026-08-08: la 0185 se pegó en producción con TODOS sus
  # acentos rotos, incluido el mensaje que ve la persona —«Solo un administrador
  # o l√≠der puede calcular la planilla»—. El SQL corre igual, así que nada
  # falla: solo se lee mal, y las migraciones de este repo se leen.
  LC_CTYPE=UTF-8 pbcopy < "$ARCHIVO"

  # Comprobación de que llegó entero. Si el portapapeles no devuelve byte por
  # byte lo mismo que el archivo, mejor no pegar nada: un aviso vale más que
  # una migración corrupta que nadie mira hasta dentro de tres meses.
  if LC_CTYPE=UTF-8 pbpaste 2>/dev/null | cmp -s - "$ARCHIVO"; then
    echo ""
    echo "  Copiado al portapapeles. Pégalo en el SQL Editor de Supabase (⌘V)."
  else
    echo ""
    rojo "✗ El portapapeles no coincide byte por byte con el archivo."
    gris "  Algo está transformando el texto — probablemente los acentos."
    gris "  NO pegues eso. Ábrelo y cópialo a mano:  $ARCHIVO"
    echo ""
    exit 1
  fi
else
  echo ""
  gris "  Ábrelo y cópialo entero:  $ARCHIVO"
fi
echo ""
gris "  Y recuerda: lo que devuelva el SQL Editor es la única confirmación."
gris "  Si sale un WARNING o un ERROR, no lo des por aplicado."
echo ""
