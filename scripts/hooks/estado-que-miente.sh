#!/usr/bin/env bash
# ============================================================================
# estado-que-miente.sh
# ============================================================================
# BLOQUEA el push cuando `docs/estado.md` dice «SIN FUSIONAR» de algo que YA
# está en `origin/main`. AVISA —sin bloquear— cuando dice «SIN PEGAR» de una
# migración que ya está publicada.
#
# ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
#
# El 2026-09-19 se midió el archivo entero contra git y contra producción:
# **ocho entradas mentían**. La peor era la de la 0479 («el bono de cumpleaños
# firmado entra a la boleta»), que decía «ESCRITA, NO AUDITADA · NO PEGADA ·
# SIN FUSIONAR» cuando las tres eran falsas — la migración se pegó a las
# 09:44:06 y se fusionó a las 09:45:24, en el orden correcto, y `db-tests` ya
# había pasado con su prueba 378.
#
# El párrafo se escribió a las 08:55, cincuenta minutos antes, y nadie volvió a
# tocarlo en diez horas. El daño no fue teórico: una sesión posterior lo leyó,
# lo creyó, y levantó una alarma de plata —«producción le promete a alguien un
# bono que su base no sabe pagar»— que costó una consulta a producción para
# descartar. `CLAUDE.md` dice que `estado.md` es «el único archivo de estado»:
# es lo primero que lee quien llega, y mintiendo hace exactamente el daño que
# existe para evitar.
#
# Las otras siete: la entrada de Incidencias (#447), la del Dashboard (#435),
# la 0480, las 0474/0475, la 0463 y la 0461 — estas dos últimas diciendo «SIN
# PEGAR» llevando cuatro días fusionadas, y la 0461 toca apoyo educativo. Y la
# 0481 no tenía entrada siquiera.
#
# ── LA REGLA, Y POR QUÉ ES DEMOSTRABLE ──────────────────────────────────────
#
# `docs/estado.md` viaja en este mismo repositorio, así que una entrada llega a
# `origin/main` con el mismo PR que fusiona el trabajo que describe.
#
#   Si un encabezado que dice «SIN FUSIONAR» YA ESTÁ en `origin/main`,
#   entonces está fusionado, y se contradice a sí mismo.
#
# No hay que adivinar nada: es el archivo desmintiéndose solo. Por eso el hook
# compara el encabezado LITERAL (`grep -Fxq`, línea exacta, sin regex) y no
# intenta interpretar la prosa.
#
# ── LA SEGUNDA MITAD, QUE EVITA EL FALSO POSITIVO ───────────────────────────
#
# Hay un caso legítimo: un PR que solo actualiza `estado.md` describiendo
# trabajo que todavía no se fusiona (el #445 fue así). Entonces el encabezado
# viaja a `main` diciendo «SIN FUSIONAR» con toda la razón.
#
# Por eso, cuando el encabezado nombra una migración, el hook exige LAS DOS
# cosas para bloquear: que la entrada esté en `main` Y que su migración también.
# Solo así es una mentira demostrable. Sin número no se puede distinguir, y ahí
# el hook bloquea igual pero el mensaje dice cómo salir.
#
# ── LO QUE ESTE HOOK NO PUEDE VER, Y CONVIENE SABERLO ───────────────────────
#
# **Git sabe qué está fusionado; no sabe qué está pegado.** De las ocho del
# 2026-09-19, este hook habría cazado siete. La octava —la 0481, que no tenía
# entrada— es una AUSENCIA, y una ausencia no se caza sin ruido: hay 464
# migraciones y casi ninguna tiene entrada propia, ni debe tenerla.
#
# Y «SIN PEGAR» solo lo puede responder producción. El hook avisa cuando el
# estado es peligroso (publicada + dice que no se pegó) pero NO bloquea,
# porque puede ser perfectamente cierto y bien anotado. Para convertir ese
# aviso en un freno haría falta consultar `migraciones_aplicadas` desde CI con
# una clave de solo lectura, y eso es una decisión que no toma un hook.
#
# ── POR QUÉ MIRA EL ARCHIVO ENTERO Y NO SOLO LO QUE EL PUSH AGREGA ──────────
#
# Al revés que `numeracion.sh`, `reglas-de-la-casa.sh` o `lint-de-lo-nuevo.sh`.
# Esos miran solo lo nuevo porque la deuda vieja del repo es grande y un freno
# que chilla siempre se desactiva a la semana.
#
# Acá no hay deuda vieja: las ocho se corrigieron el 2026-09-19 antes de
# escribir este hook, justamente para que pudiera mirar el archivo completo. Y
# tiene que mirarlo completo, porque **el daño lo hace la entrada que envejece
# mintiendo**, no la que se escribe hoy. La de la 0479 era correcta en el
# minuto en que se escribió; se volvió falsa cincuenta minutos después, sin que
# nadie tocara el archivo. Un hook que solo mire el diff no vería nunca ese
# caso, que es el único que ha pasado.
#
# Mismo criterio que `descarga-sin-nombre.sh`: lo que hay que comprobar es una
# propiedad del archivo, no de una línea.
#
# ── CÓMO SE SALE SI BLOQUEA ─────────────────────────────────────────────────
#
# Corrigiendo el encabezado, que es el trabajo de treinta segundos que nadie
# hizo ocho veces. En una urgencia real, `git push --no-verify`.
# ============================================================================

set -u

rojo()  { printf '\033[31m%s\033[0m\n' "$1"; }
ambar() { printf '\033[33m%s\033[0m\n' "$1"; }
gris()  { printf '\033[90m%s\033[0m\n' "$1"; }

ARCHIVO="docs/estado.md"

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

MENTIRAS=""
AVISOS=""

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

  # ¿Este encabezado, literal, ya viajó a `origin/main`? `-F` y `-x`: cadena
  # fija y línea completa. Los encabezados llevan «·», «»» y emojis, y con
  # regex cualquiera de esos se interpretaría.
  entrada_publicada=0
  if printf '%s\n' "$EN_MAIN" | grep -Fxq "$titulo"; then
    entrada_publicada=1
  fi

  # Los números de migración del ENCABEZADO, no del cuerpo: el estado se
  # declara en el título, y el cuerpo cita migraciones históricas como contexto.
  NUMS="$(printf '%s' "$titulo" | grep -oE '0[0-9]{3}' | sort -u)"

  migracion_publicada=0
  for n in $NUMS; do
    if printf '%s\n' "$PUBLICADAS" | grep -Fxq "$n"; then
      migracion_publicada=1
      break
    fi
  done

  if [ "$dice_sin_fusionar" = 1 ] && [ "$entrada_publicada" = 1 ]; then
    # Con número, exigimos las dos cosas: así el PR de solo-estado que describe
    # trabajo aún sin fusionar (caso legítimo) no cae acá.
    if [ -z "$NUMS" ] || [ "$migracion_publicada" = 1 ]; then
      MENTIRAS="${MENTIRAS}${titulo}"$'\n'
      continue
    fi
  fi

  if [ "$dice_sin_pegar" = 1 ] && [ "$migracion_publicada" = 1 ]; then
    AVISOS="${AVISOS}${titulo}"$'\n'
  fi
done <<EOF
$MIO
EOF

if [ -n "$AVISOS" ]; then
  echo
  ambar "⚠️  $ARCHIVO dice «SIN PEGAR» de algo que ya está PUBLICADO:"
  echo
  printf '%s' "$AVISOS" | while IFS= read -r t; do
    [ -n "$t" ] && ambar "    ${t#\#\# }"
  done
  echo
  gris "  Si de verdad no está pegada, el código lleva tiempo en el aire por"
  gris "  delante de su base — la ventana de la 0404, la 0407 y la 0440."
  gris "  Esto no lo puede responder git. Córrelo contra producción:"
  gris "      ./scripts/que-falta-pegar.sh"
  echo
  gris "  No bloquea: «SIN PEGAR» puede ser cierto y estar bien anotado."
fi

if [ -n "$MENTIRAS" ]; then
  echo
  rojo "✗ $ARCHIVO dice «SIN FUSIONAR» de algo que YA ESTÁ en origin/main."
  echo
  printf '%s' "$MENTIRAS" | while IFS= read -r t; do
    [ -n "$t" ] && rojo "    ${t#\#\# }"
  done
  echo
  gris "  El encabezado está, tal cual, en el estado.md de origin/main: o sea"
  gris "  que se fusionó, y fusionar es publicar. La entrada se desmiente sola."
  echo
  gris "  Corrige el encabezado y vuelve a empujar. Si la entrada describe algo"
  gris "  que de verdad sigue sin fusionarse —un PR de solo-estado—, dilo en el"
  gris "  encabezado con otras palabras, o salta el freno a propósito:"
  gris "      git push --no-verify"
  echo
  gris "  Por qué esto bloquea y no avisa: el 2026-09-19 ocho entradas mentían,"
  gris "  y una hizo que otra sesión levantara una alarma de plata que no era."
  echo
  exit 1
fi

exit 0
