# Variables del entorno local. Lo cargan los demás scripts; no se corre solo.
# La base vive dentro del directorio de git de este clon: la comparten todos los worktrees
# y nunca aparece en `git status` ni puede subirse por accidente.
RAIZ=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
#
# Una segunda instancia, para no tocar la que otra sesión tiene abierta (la base es UNA para todos los
# worktrees): ENTORNO_LOCAL=/otra/carpeta PUERTOS_LOCAL_DESDE=55990 node scripts/local/web.mjs
ENTORNO=${ENTORNO_LOCAL:-$(git -C "$RAIZ" rev-parse --path-format=absolute --git-common-dir)/entorno-local}
PGBIN=/opt/homebrew/opt/postgresql@17/bin
DESDE=${PUERTOS_LOCAL_DESDE:-55890}
PG_PUERTO=$DESDE
REST_PUERTO=$((DESDE + 1))
PUERTA_PUERTO=$((DESDE + 2))
REALTIME_PUERTO=$((DESDE + 3))
# Las opciones de Postgres, en un solo lugar (las usan crear-base.sh y arrancar.sh).
# `wal_level=logical` es lo que necesita Realtime para leer los avisos (ver tiempo-real.sh).
PG_OPCIONES="-p $PG_PUERTO -c listen_addresses=127.0.0.1 -c unix_socket_directories= -c max_connections=100 -c fsync=off -c timezone=UTC -c wal_level=logical -c max_wal_senders=10 -c max_replication_slots=10"
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export PATH=$PGBIN:$PATH
export PGHOST=127.0.0.1 PGPORT=$PG_PUERTO PGUSER=postgres PGDATABASE=postgres
export JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long
export PUERTA_PUERTO REST_PUERTO PG_PUERTO REALTIME_PUERTO
mkdir -p "$ENTORNO/logs"
