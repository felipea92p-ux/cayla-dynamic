#!/usr/bin/env bash
# ============================================================================
# main-tiene-migraciones-que-no-tienes.sh
# ============================================================================
# AVISA —sin bloquear— cuando `main` tiene migraciones que esta rama no tiene.
#
# ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
#
# El 2026-08-20 una sesión construyó la 0276 sobre el cuerpo de la 0269 de
# `fn_planilla_calcular`, sin saber que otra sesión había fusionado a `main` la
# 0275 —«las vacaciones dejan de pagarse en cero»— y que Felipe ya la había
# pegado en producción. Pegar la 0276 habría devuelto a S/0.00 el mes de quien
# se toma sus vacaciones completas.
#
# Y no fue por descuido de método: se hicieron las dos comprobaciones que este
# repo manda. `./scripts/donde-vive.sh` dijo que la vigente era la 0269 —y era
# verdad EN ESA RAMA—, y `npx supabase db reset` reconstruyó un esquema entero
# sin errores —sin la 0275, que no estaba en el árbol—. Las dos herramientas
# miran el worktree, y el worktree estaba incompleto.
#
# Lo cazó pedirle el md5 a producción: 90 707 caracteres allá contra 89 527
# acá. O sea, lo cazó el último freno de la cadena, cuando el trabajo ya estaba
# hecho, verificado y commiteado. Este script lo caza al principio.
#
# ── POR QUÉ AVISA Y NO BLOQUEA ──────────────────────────────────────────────
#
# Por la misma regla que ya tenía escrita `migracion-sin-guardar.sh`: lo que
# sale de esta máquina se bloquea, lo que solo está en el disco se avisa. Ir por
# detrás de `main` es un estado legítimo y constante cuando trabajan varias
# sesiones en paralelo — bloquear cada push por eso enseñaría a usar
# `--no-verify`, y entonces el día que importe tampoco se leería.
#
# Sube el tono cuando la migración que falta TOCA UNA FUNCIÓN QUE TÚ TAMBIÉN
# ESTÁS TOCANDO, porque ese es exactamente el caso que hace daño y no se ve.
# ============================================================================
set -uo pipefail

rojo()  { printf '\033[31m%s\033[0m\n' "$1"; }
ambar() { printf '\033[33m%s\033[0m\n' "$1"; }
gris()  { printf '\033[90m%s\033[0m\n' "$1"; }

RAIZ="$(git rev-parse --show-toplevel)"
cd "$RAIZ" || exit 0

RAMA="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
[ "$RAMA" = "main" ] && exit 0

# Sin `origin/main` no hay nada que comparar (clon nuevo, o sin red).
git rev-parse --verify --quiet origin/main >/dev/null 2>&1 || exit 0

# Las migraciones que `main` tiene y esta rama no. Se comparan NOMBRES de
# archivo, no contenidos: un número que allá existe y acá no es el caso que
# importa, tenga el cuerpo que tenga.
MIAS="$(git ls-tree -r --name-only HEAD -- supabase/migrations 2>/dev/null | sed 's|.*/||' | sort)"
SUYAS="$(git ls-tree -r --name-only origin/main -- supabase/migrations 2>/dev/null | sed 's|.*/||' | sort)"
FALTAN="$(comm -13 <(echo "$MIAS") <(echo "$SUYAS"))"

[ -z "$FALTAN" ] && exit 0

CUANTAS="$(echo "$FALTAN" | grep -c . || true)"

echo ""
ambar "⚠ 'main' tiene $CUANTAS migración(es) que esta rama no tiene."
echo "$FALTAN" | sed 's/^/    /'
gris "  Tu 'supabase db reset' las está construyendo SIN ellas, así que el"
gris "  esquema local no es el de producción."

# ── La parte que de verdad importa: ¿chocan con lo que estás tocando? ───────
#
# Se sacan los nombres de función que define cada lado y se cruzan. Un choque
# aquí significa que tu migración va a PISAR lo que la de main ya dejó puesto,
# y que ninguna prueba tuya lo va a ver — porque tus pruebas corren sobre tu
# esquema, que tampoco la tiene.
fns_de() {
  grep -hoiE 'create (or replace )?function( if not exists)? +(public\.)?[a-z0-9_]+' 2>/dev/null \
    | sed -E 's/.*[. ]([a-z0-9_]+)$/\1/' | tr 'A-Z' 'a-z' | sort -u
}

MIS_FNS="$(git diff --name-only origin/main...HEAD -- supabase/migrations 2>/dev/null \
           | while read -r f; do [ -f "$f" ] && cat "$f"; done | fns_de)"

SUS_FNS="$(echo "$FALTAN" | while read -r n; do
             [ -n "$n" ] && git show "origin/main:supabase/migrations/$n" 2>/dev/null
           done | fns_de)"

CHOQUE="$(comm -12 <(echo "$MIS_FNS") <(echo "$SUS_FNS") | grep . || true)"

if [ -n "$CHOQUE" ]; then
  echo ""
  rojo "  ✗ Y TOCÁIS LAS MISMAS FUNCIONES:"
  echo "$CHOQUE" | sed 's/^/      /'
  gris "    Tu migración las reescribe partiendo de un cuerpo que ya no es el"
  gris "    vigente. Al pegarla, lo que hizo la de 'main' se revierte EN"
  gris "    SILENCIO: corre sin error y devuelve otro número."
  echo ""
  rojo "    Antes de seguir:"
  gris "      git merge origin/main     # y reconstruye: npx supabase db reset"
  gris "      ./scripts/donde-vive.sh <funcion>   # ahora sí dirá la vigente"
  gris "    Y pídele a producción el md5 ANTES de reescribir la función, no"
  gris "    antes de entregarla — para entonces ya está construida sobre el"
  gris "    cuerpo equivocado."
else
  gris "  Ninguna toca las funciones que tú tocas, así que no hay choque."
  gris "  Aun así, conviene traerlas:  git merge origin/main"
fi
echo ""

exit 0
