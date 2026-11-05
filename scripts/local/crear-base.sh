#!/bin/bash
# Crea desde cero la base del entorno local: arranque + todas las migraciones del repo + datos inventados.
# Si ya existe, la deja como está; para empezar de cero: ./scripts/local/crear-base.sh --de-cero
set -u
source "$(dirname "$0")/comun.sh"
DATOS=$ENTORNO/pg

if [ "${1:-}" = "--de-cero" ] && [ -d "$DATOS" ]; then
  pg_ctl -D "$DATOS" -m fast stop >/dev/null 2>&1
  rm -rf "$DATOS"
fi
if [ -d "$DATOS" ]; then echo "La base ya existe en $DATOS (usa --de-cero para rehacerla)."; exit 0; fi

initdb -D "$DATOS" -U postgres --auth=trust --locale-provider=builtin --builtin-locale=C.UTF-8 -E UTF8 >"$ENTORNO/logs/initdb.log" 2>&1 \
  || { echo "initdb falló: mira $ENTORNO/logs/initdb.log"; exit 1; }
pg_ctl -D "$DATOS" -l "$ENTORNO/logs/postgres.log" -w \
  -o "-p $PG_PUERTO -c listen_addresses=127.0.0.1 -c unix_socket_directories= -c max_connections=100 -c fsync=off -c timezone=UTC" start >/dev/null \
  || { echo "Postgres no arrancó: mira $ENTORNO/logs/postgres.log"; exit 1; }

psql -q -v ON_ERROR_STOP=1 -f "$RAIZ/scripts/local/arranque-base.sql" >"$ENTORNO/logs/arranque.out" 2>&1 \
  || { echo "El arranque falló:"; tail -5 "$ENTORNO/logs/arranque.out"; exit 1; }

# Cada migración en su transacción, en orden, igual que CI. Se quita solo la línea de pg_cron.
total=0
for f in $(ls "$RAIZ/supabase/migrations" | grep -E '^[0-9]{4}_.*\.sql$' | LC_ALL=C sort); do
  { echo 'begin;'; sed -e 's/^create extension if not exists pg_cron.*$/-- (pg_cron: no existe en local; ver arranque-base.sql)/I' "$RAIZ/supabase/migrations/$f"; echo 'commit;'; } \
    | psql -q -v ON_ERROR_STOP=1 >"$ENTORNO/logs/ultima.out" 2>&1 \
    || { echo "Falló la migración $f:"; tail -8 "$ENTORNO/logs/ultima.out"; exit 1; }
  total=$((total+1))
done
echo "Migraciones aplicadas: $total"

node "$RAIZ/scripts/local/sembrar.mjs" || { echo "Los datos inventados fallaron."; exit 1; }
