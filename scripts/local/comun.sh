# Variables del entorno local. Lo cargan los demás scripts; no se corre solo.
# La base vive dentro del directorio de git de este clon: la comparten todos los worktrees
# y nunca aparece en `git status` ni puede subirse por accidente.
RAIZ=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
ENTORNO=$(git -C "$RAIZ" rev-parse --path-format=absolute --git-common-dir)/entorno-local
PGBIN=/opt/homebrew/opt/postgresql@17/bin
PG_PUERTO=55890
REST_PUERTO=55891
PUERTA_PUERTO=55892
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export PATH=$PGBIN:$PATH
export PGHOST=127.0.0.1 PGPORT=$PG_PUERTO PGUSER=postgres PGDATABASE=postgres
export JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long
export PUERTA_PUERTO REST_PUERTO PG_PUERTO
mkdir -p "$ENTORNO/logs"
