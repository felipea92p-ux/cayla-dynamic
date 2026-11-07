#!/usr/bin/env bash
# Choques de esta rama contra `main` y contra los PR abiertos. Solo lee.
#
#   bash .claude/skills/abrir-pr/choques.sh
#
# Sale con 0 si no hay choque seguro, con 1 si lo hay y con 2 si no pudo mirar los PR.
#
# Lo que hace daño aquí no es un conflicto de git: dos migraciones que reescriben la
# misma función no se tocan. Por eso compara NOMBRES de función, no líneas. Así se
# revirtió la 0275 con la 0261 (2026-08-25).
#
# No usa arreglos asociativos: el bash de macOS es 3.2. Ni `LC_ALL=C`, por lo que
# le pasó a dame-el-sql.sh.
set -uo pipefail

RAIZ="$(git rev-parse --show-toplevel)" || exit 2
cd "$RAIZ" || exit 2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git fetch origin main --quiet 2>/dev/null || echo "⚠ No pude traer origin/main: comparo contra lo último que tengo."
BASE="$(git merge-base HEAD origin/main)" || { echo "No encuentro origin/main."; exit 2; }

# Lee un SQL por la entrada y escribe los nombres de función que define, sin esquema y en minúsculas.
funciones() {
  grep -iE '^[[:space:]]*create[[:space:]]+(or[[:space:]]+replace[[:space:]]+)?function' \
    | sed -E 's/.*[Ff][Uu][Nn][Cc][Tt][Ii][Oo][Nn][[:space:]]+//; s/^[Pp][Uu][Bb][Ll][Ii][Cc]\.//; s/[ (].*//' \
    | tr 'A-Z' 'a-z' | sort -u
}
numero() { sed -E 's|.*/||; s/^([0-9]+).*/\1/'; }

git diff --name-only --diff-filter=A "$BASE" HEAD -- supabase/migrations | sort > "$TMP/mias"
git diff --name-only "$BASE" HEAD | sort > "$TMP/archivos"
numero < "$TMP/mias" | sort -u > "$TMP/mis-numeros"
: > "$TMP/mis-funciones"
while read -r f; do [ -n "$f" ] && git show "HEAD:$f" | funciones >> "$TMP/mis-funciones"; done < "$TMP/mias"
sort -u -o "$TMP/mis-funciones" "$TMP/mis-funciones"

echo "Rama: $(git branch --show-current) · $(wc -l < "$TMP/archivos" | tr -d ' ') archivos · $(wc -l < "$TMP/mias" | tr -d ' ') migraciones nuevas · $(wc -l < "$TMP/mis-funciones" | tr -d ' ') funciones"
echo

SEGUROS=0
PROBABLES=0

# ── Contra main: lo que entró después de que esta rama se separó ──────────────
git diff --name-only --diff-filter=A "$BASE" origin/main -- supabase/migrations | sort > "$TMP/de-main"
while read -r f; do
  [ -n "$f" ] || continue
  n="$(echo "$f" | numero)"
  if grep -qx "$n" "$TMP/mis-numeros"; then
    echo "🔴 SEGURO · main ya usa el número $n: $f"
    SEGUROS=$((SEGUROS + 1))
  fi
  git show "origin/main:$f" | funciones > "$TMP/f"
  for fn in $(comm -12 "$TMP/f" "$TMP/mis-funciones"); do
    echo "🔴 SEGURO · $fn cambió en main ($f): tu versión parte de una anterior"
    SEGUROS=$((SEGUROS + 1))
  done
done < "$TMP/de-main"

# ── Contra los PR abiertos ────────────────────────────────────────────────────
if ! gh pr list --state open --limit 60 --json number,headRefName --jq '.[] | "\(.number) \(.headRefName)"' > "$TMP/prs"; then
  echo "No pude leer los PR abiertos. «No pude mirar» no es «no hay choques»."
  exit 2
fi
MI_RAMA="$(git branch --show-current)"
REGISTROS='^(apps/web/lib/novedades\.ts|apps/web/app/\(admin\)/admin/nav-items\.ts|scripts/sql-manual/que_falta_pegar\.sql)$'

while read -r pr rama; do
  [ -n "$pr" ] || continue
  [ "$rama" = "$MI_RAMA" ] && continue
  if ! gh pr diff "$pr" --name-only 2>/dev/null | sort > "$TMP/del-pr"; then
    echo "⚠ No pude leer el PR $pr."
    continue
  fi
  git fetch origin "+refs/heads/$rama:refs/remotes/origin/$rama" --quiet 2>/dev/null
  while read -r f; do
    case "$f" in supabase/migrations/*) ;; *) continue ;; esac
    n="$(echo "$f" | numero)"
    if grep -qx "$n" "$TMP/mis-numeros"; then
      echo "🔴 SEGURO · el PR $pr usa el número $n: $f"
      SEGUROS=$((SEGUROS + 1))
    fi
    git show "origin/$rama:$f" 2>/dev/null | funciones > "$TMP/f"
    for fn in $(comm -12 "$TMP/f" "$TMP/mis-funciones"); do
      echo "🟠 PROBABLE · $fn también la reescribe el PR $pr ($f)"
      PROBABLES=$((PROBABLES + 1))
    done
  done < "$TMP/del-pr"
  comm -12 "$TMP/del-pr" "$TMP/archivos" > "$TMP/comunes"
  while read -r f; do
    [ -n "$f" ] || continue
    if echo "$f" | grep -qE "$REGISTROS"; then
      echo "🟠 PROBABLE · archivo de registro en común con el PR $pr: $f"
      PROBABLES=$((PROBABLES + 1))
    else
      echo "ℹ en común con el PR $pr: $f"
    fi
  done < "$TMP/comunes"
done < "$TMP/prs"

echo
echo "$SEGUROS choques seguros · $PROBABLES probables · $(wc -l < "$TMP/prs" | tr -d ' ') PR abiertos revisados"
[ "$SEGUROS" -eq 0 ]
