#!/bin/bash
# Qué número toca — para preguntarlo ANTES de crear el archivo.
#
# POR QUÉ EXISTE. `scripts/hooks/numeracion.sh` ya caza las colisiones, pero lo
# hace al hacer push: cuando el archivo ya está escrito, nombrado y commiteado, y
# renumerarlo obliga a tocar la cabecera, los mensajes y la prueba. El 2026-08-05
# hubo tres colisiones en un día y las tres se cazaron tarde; una de ellas dejó
# `supabase db reset` abortando con «duplicate key value violates unique
# constraint schema_migrations_pkey», que no es desorden: es no poder reconstruir
# el esquema.
#
# La convención decía «mira `ls` antes de numerar», y `ls` solo ve la rama en la
# que estás. Con varias sesiones en paralelo eso dejó de alcanzar.
#
# QUÉ MIRA, y por qué las tres fuentes hacen falta:
#   · todas las ramas, locales y remotas → lo que otra rama ya reclamó;
#   · el directorio de trabajo           → lo que otra sesión escribió y aún no
#                                          commiteó, que es el caso que más
#                                          veces se coló;
#   · `migraciones_aplicadas` en la base local, si está levantada → lo que
#     alguien aplicó a mano sin dejar archivo. Así se perdió la 0137 un día
#     entero.
#
#   ./scripts/siguiente-numero.sh          los dos, migración y prueba
#   ./scripts/siguiente-numero.sh mig      solo el de migración
#   ./scripts/siguiente-numero.sh test     solo el de prueba
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

verde() { printf "\033[32m%s\033[0m\n" "$1"; }
gris()  { printf "\033[90m%s\033[0m\n" "$1"; }
rojo()  { printf "\033[31m%s\033[0m\n" "$1"; }

# Todos los números ocupados de un directorio, mirando ramas + disco.
ocupados() {
  local dir="$1"
  {
    for r in $(git for-each-ref --format='%(refname)' refs/heads refs/remotes 2>/dev/null); do
      git ls-tree -r --name-only "$r" "$dir" 2>/dev/null || true
    done
    ls "$dir" 2>/dev/null || true
  } | sed 's|.*/||' | grep -E '^[0-9]+_' | sed 's/^0*//; s/_.*//' | sort -n | uniq
}

# Lo que la base local dice que se aplicó. Puede no estar levantada: entonces se
# omite y se avisa, en vez de fallar — la respuesta sigue siendo útil sin esto.
aplicados_en_la_base() {
  docker exec supabase_db_cayla-dynamic psql -U postgres -d postgres -At \
    -c "select numero from migraciones_aplicadas order by numero;" 2>/dev/null || true
}

informe() {
  local etiqueta="$1" dir="$2" ancho="$3" mirar_base="$4"

  local nums; nums=$(ocupados "$dir")
  if [ -z "$nums" ]; then rojo "No encontré archivos numerados en $dir"; return 1; fi

  local extra=""
  if [ "$mirar_base" = "si" ]; then
    extra=$(aplicados_en_la_base)
    if [ -z "$extra" ]; then
      gris "  (la base local no responde: no puedo comprobar lo aplicado a mano)"
    fi
  fi

  local todos; todos=$(printf '%s\n%s\n' "$nums" "$extra" | grep -E '^[0-9]+$' | sort -n | uniq)
  local ultimo; ultimo=$(echo "$todos" | tail -1)
  local siguiente=$((ultimo + 1))

  verde "$(printf "%s → siguiente libre: %0${ancho}d" "$etiqueta" "$siguiente")"

  # Los duplicados que YA existen en el disco: si hay, el número siguiente es lo
  # de menos.
  local dup
  dup=$(ls "$dir" 2>/dev/null | grep -E '^[0-9]+_' | sed 's/_.*//' | sort -n | uniq -d || true)
  if [ -n "$dup" ]; then
    rojo "  ⚠ ya hay números DUPLICADOS en el directorio: $(echo "$dup" | tr '\n' ' ')"
    rojo "    Con eso, 'supabase db reset' aborta. Resuélvelo antes de crear nada."
  fi

  # Los huecos solo se informan para migraciones, donde la numeración es densa y
  # un hueco significa algo. Las pruebas se numeraron por decenas durante meses
  # (10, 20, 30…), así que listar sus huecos escupe 65 números y no dice nada —
  # y un aviso que chilla siempre se acaba ignorando, incluido el que sí importa.
  if [ "$mirar_base" = "si" ]; then
    local huecos
    huecos=$(echo "$todos" | awk 'NR>1 && $1!=prev+1 {for(i=prev+1;i<$1;i++) printf "%s ", i} {prev=$1}')
    if [ -n "$huecos" ]; then
      gris "  huecos (no son error, pero no los reutilices): $huecos"
    fi
  fi
}

QUE="${1:-todo}"
echo ""
case "$QUE" in
  mig|migracion|migración) informe "migración" "supabase/migrations" 4 "si" ;;
  test|prueba)             informe "prueba   " "supabase/tests"      1 "no" ;;
  *)
    informe "migración" "supabase/migrations" 4 "si"
    informe "prueba   " "supabase/tests"      1 "no"
    ;;
esac
echo ""
gris "Mira esto ANTES de crear el archivo. El hook de pre-push caza la colisión"
gris "igual, pero cuando el nombre ya está en la cabecera y en la prueba."
