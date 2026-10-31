#!/usr/bin/env bash
# ============================================================================
# estado-que-miente.sh
# ============================================================================
# BLOQUEA el push cuando una entrada de `docs/estado.md` QUE ESTE PUSH TOCA
# dice «SIN FUSIONAR» de algo que ya está en `origin/main`.
# CUENTA —sin bloquear— las que ya venían mintiendo, y las que dicen «SIN
# PEGAR» de una migración publicada.
#
# Uso suelto, fuera del push:   ./scripts/hooks/estado-que-miente.sh --lista
# (imprime una por una las que solo se cuentan, con su encabezado entero)
#
# ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
#
# El 2026-09-19 se midió el archivo entero contra git y contra producción:
# **nueve entradas mentían**. La peor decía de la 0479 —el bono de cumpleaños
# entrando a la boleta— «ESCRITA, NO AUDITADA · NO PEGADA · SIN FUSIONAR»
# cuando las tres eran falsas: la migración se pegó a las 09:44:06 y se fusionó
# a las 09:45:24, en el orden correcto, con `db-tests` verde.
#
# El párrafo se escribió a las 08:55, cincuenta minutos antes, y nadie volvió a
# tocarlo en diez horas. El daño no fue teórico: una sesión posterior lo leyó,
# lo creyó, y levantó una alarma de plata —«producción le promete a alguien un
# bono que su base no sabe pagar»— que costó una consulta a producción para
# descartar. `CLAUDE.md` dice que `estado.md` es «el único archivo de estado»:
# es lo primero que lee quien llega, y mintiendo hace el daño que existe para
# evitar.
#
# ── LA REGLA, Y POR QUÉ ES DEMOSTRABLE ──────────────────────────────────────
#
# `docs/estado.md` viaja en este mismo repositorio, así que una entrada llega a
# `origin/main` con el mismo PR que fusiona el trabajo que describe.
#
#   Si un encabezado que dice «SIN FUSIONAR» YA ESTÁ en `origin/main`,
#   entonces está fusionado, y se contradice a sí mismo.
#
# No hay que adivinar nada: es el archivo desmintiéndose solo. Por eso compara
# el encabezado LITERAL (`grep -Fxq`, línea exacta, sin regex) y no interpreta
# la prosa — los encabezados llevan «·», comillas y emojis, y con regex
# cualquiera de esos se interpretaría.
#
# ── POR QUÉ SOLO BLOQUEA LO QUE EL PUSH TOCA ────────────────────────────────
#
# La primera versión (2026-09-19) miraba el archivo ENTERO y bloqueaba todo lo
# que encontrara. Se justificó así: «no hay deuda vieja — las nueve se
# corrigieron antes de escribir el hook, a propósito».
#
# **Esa premisa caducó en cinco semanas.** El 2026-10-29, al fusionar `main` en
# el PR que traía este hook (934 commits después), el archivo tenía **23**
# entradas diciendo «SIN FUSIONAR» de trabajo publicado. Se comprobaron siete
# al azar contra GitHub —#597, #598, #576, #541, #508, #491, #480— y las siete
# estaban MERGED: no eran falsos positivos, era deuda real multiplicada por
# 2.5 en un mes.
#
# Mirando el archivo entero, este hook habría fallado TODOS los push de TODAS
# las sesiones hasta que alguien pagara esas 23. Y eso es exactamente lo que
# `CLAUDE.md` ya tenía escrito para `numeracion.sh`, `reglas-de-la-casa.sh` y
# `lint-de-lo-nuevo.sh`: «la deuda vieja no molesta, y una regla nueva no puede
# entrar; la deuda se paga en su propio lote, no a costa de que este freno
# mienta». Un freno que chilla siempre se desactiva a la semana.
#
# Así que ahora: **bloquea solo las entradas que este push agrega o modifica**
# (las líneas `+## ` del diff contra `origin/main`), y **cuenta** el resto.
#
# ── Y POR QUÉ LA DEUDA SE CUENTA EN VEZ DE LISTARSE ─────────────────────────
#
# Veintitrés líneas rojas en cada push son ruido, y el ruido enseña a usar
# `--no-verify`. Una sola línea con el número no: el número subiendo ES la
# señal, y `--lista` da el detalle cuando alguien quiera pagarlo.
#
# ── LO QUE ESTE HOOK NO PUEDE VER ───────────────────────────────────────────
#
# **Git sabe qué está fusionado; no sabe qué está pegado.** «SIN PEGAR» solo lo
# responde producción (`./scripts/que-falta-pegar.sh`), así que eso se cuenta y
# nunca bloquea: puede ser cierto y estar bien anotado.
#
# **Y un hueco medido, no supuesto:** «tocar» se mide con las líneas `+## ` del
# diff, así que agregar o cambiar el CUERPO de una entrada que miente no marca
# su encabezado y NO bloquea — se probó el 2026-10-29 y pasó en verde. Dispara
# cuando el encabezado mismo se escribe o se reescribe. Se deja así a
# propósito: ensanchar «tocar» a toda la entrada volvería a hacer que cualquier
# edición del archivo tropiece con las 23 de deuda, que es lo que esta versión
# viene a evitar.
#
# Y hay algo que NINGUNA versión de este hook puede atrapar, conviene decirlo:
# una entrada nueva que dice «SIN FUSIONAR» es CORRECTA en el momento de
# escribirse, y se vuelve falsa cuando su PR se fusiona — momento en el que ya
# nadie la está tocando. Ese caso, el de la 0479, solo puede salir en el
# recuento. Por eso el recuento no es un adorno del freno: es la mitad que de
# verdad cubre el accidente que lo motivó.
#
# ── CÓMO SE SALE SI BLOQUEA ─────────────────────────────────────────────────
#
# Corrigiendo el encabezado de la entrada que estás tocando. En una urgencia,
# `git push --no-verify`.
# ============================================================================

set -u

rojo()  { printf '\033[31m%s\033[0m\n' "$1"; }
ambar() { printf '\033[33m%s\033[0m\n' "$1"; }
gris()  { printf '\033[90m%s\033[0m\n' "$1"; }

ARCHIVO="docs/estado.md"
LISTAR=0
[ "${1:-}" = "--lista" ] && LISTAR=1

# Sin `origin/main` no hay nada contra qué comparar (clon nuevo, o sin red).
git rev-parse --verify --quiet origin/main >/dev/null 2>&1 || exit 0

# La versión que se EMPUJA, nunca la del disco: el disco puede tener trabajo a
# medio escribir de esta o de otra sesión. Mismo criterio que
# `descarga-sin-nombre.sh`.
MIO="$(git show "HEAD:$ARCHIVO" 2>/dev/null)" || exit 0
[ -n "$MIO" ] || exit 0

EN_MAIN="$(git show "origin/main:$ARCHIVO" 2>/dev/null)" || exit 0

# Las migraciones que YA están publicadas, por número. Una sola llamada a git.
PUBLICADAS="$(git ls-tree -r --name-only origin/main -- supabase/migrations 2>/dev/null \
              | sed 's|.*/||; s|_.*||' | sort -u)"

# Los encabezados que ESTE PUSH agrega o modifica. Solo estos bloquean.
TOCADOS="$(git diff origin/main...HEAD -- "$ARCHIVO" 2>/dev/null \
           | sed -n 's/^+\(## .*\)$/\1/p')"

MENTIRAS=""          # bloquean: las que este push toca
DEUDA_FUSIONAR=""    # cuentan: ya venían mintiendo
DEUDA_PEGAR=""       # cuentan: «SIN PEGAR» de algo publicado

while IFS= read -r titulo; do
  case "$titulo" in
    '## '*) ;;
    *) continue ;;
  esac

  dice_sin_fusionar=0
  dice_sin_pegar=0
  case "$titulo" in *'SIN FUSIONAR'*) dice_sin_fusionar=1 ;; esac
  case "$titulo" in *'SIN PEGAR'*)    dice_sin_pegar=1 ;; esac
  [ "$dice_sin_fusionar" = 1 ] || [ "$dice_sin_pegar" = 1 ] || continue

  # ¿Este encabezado, literal, ya viajó a `origin/main`?
  entrada_publicada=0
  printf '%s\n' "$EN_MAIN" | grep -Fxq "$titulo" && entrada_publicada=1

  # ¿Lo toca este push?
  lo_toca=0
  printf '%s\n' "$TOCADOS" | grep -Fxq "$titulo" && lo_toca=1

  # Los números de migración del ENCABEZADO, no del cuerpo: el estado se
  # declara en el título, y el cuerpo cita migraciones históricas de contexto.
  NUMS="$(printf '%s' "$titulo" | grep -oE '0[0-9]{3}' | sort -u)"
  migracion_publicada=0
  for n in $NUMS; do
    printf '%s\n' "$PUBLICADAS" | grep -Fxq "$n" && { migracion_publicada=1; break; }
  done

  if [ "$dice_sin_fusionar" = 1 ] && [ "$entrada_publicada" = 1 ]; then
    # Con número exigimos las dos cosas: así el PR de solo-estado que describe
    # trabajo aún sin fusionar (el #445 fue así) no cae acá.
    if [ -z "$NUMS" ] || [ "$migracion_publicada" = 1 ]; then
      if [ "$lo_toca" = 1 ]; then
        MENTIRAS="${MENTIRAS}${titulo}"$'\n'
      else
        DEUDA_FUSIONAR="${DEUDA_FUSIONAR}${titulo}"$'\n'
      fi
      continue
    fi
  fi

  if [ "$dice_sin_pegar" = 1 ] && [ "$migracion_publicada" = 1 ]; then
    DEUDA_PEGAR="${DEUDA_PEGAR}${titulo}"$'\n'
  fi
done <<EOF
$MIO
EOF

cuenta() { [ -z "$1" ] && echo 0 || printf '%s' "$1" | grep -c '^## '; }
N_FUS="$(cuenta "$DEUDA_FUSIONAR")"
N_PEG="$(cuenta "$DEUDA_PEGAR")"

if [ "$N_FUS" -gt 0 ] || [ "$N_PEG" -gt 0 ]; then
  echo
  [ "$N_FUS" -gt 0 ] && ambar "⚠️  $ARCHIVO: $N_FUS entrada(s) dicen «SIN FUSIONAR» de trabajo ya publicado."
  [ "$N_PEG" -gt 0 ] && ambar "⚠️  $ARCHIVO: $N_PEG entrada(s) dicen «SIN PEGAR» de una migración ya publicada."
  if [ "$LISTAR" = 1 ]; then
    echo
    printf '%s%s' "$DEUDA_FUSIONAR" "$DEUDA_PEGAR" | while IFS= read -r t; do
      [ -n "$t" ] && ambar "    ${t#\#\# }"
    done
  else
    gris "    Para verlas:  ./scripts/hooks/estado-que-miente.sh --lista"
  fi
  echo
  gris "  Deuda vieja: no bloquea, igual que en numeracion.sh o lint-de-lo-nuevo.sh."
  gris "  Lo que importa es el número: si sube, el archivo está envejeciendo mal."
  [ "$N_PEG" -gt 0 ] && gris "  Lo de «SIN PEGAR» solo lo responde producción: ./scripts/que-falta-pegar.sh"
fi

if [ -n "$MENTIRAS" ]; then
  echo
  rojo "✗ Este push TOCA una entrada que dice «SIN FUSIONAR» de algo que ya está"
  rojo "  en origin/main:"
  echo
  printf '%s' "$MENTIRAS" | sort -u | while IFS= read -r t; do
    [ -n "$t" ] && rojo "    ${t#\#\# }"
  done
  echo
  gris "  El encabezado está, tal cual, en el estado.md de origin/main: o sea que"
  gris "  se fusionó, y fusionar es publicar. La entrada se desmiente sola."
  echo
  gris "  Corrige el encabezado y vuelve a empujar. Si de verdad describe algo sin"
  gris "  fusionar —un PR de solo-estado—, dilo con otras palabras, o salta el"
  gris "  freno a propósito:   git push --no-verify"
  echo
  exit 1
fi

exit 0
