#!/bin/bash
# Enciende el entorno local: base (si no existe, la crea con sus datos inventados), PostgREST y la puerta.
# No toca Docker, ni las bases compartidas, ni producción.
set -u
source "$(dirname "$0")/comun.sh"
[ -d "$ENTORNO/pg" ] || "$RAIZ/scripts/local/crear-base.sh" || exit 1

pg_ctl -D "$ENTORNO/pg" status >/dev/null 2>&1 || pg_ctl -D "$ENTORNO/pg" -l "$ENTORNO/logs/postgres.log" -w \
  -o "-p $PG_PUERTO -c listen_addresses=127.0.0.1 -c unix_socket_directories= -c max_connections=100 -c fsync=off -c timezone=UTC" start >/dev/null \
  || { echo "Postgres no arrancó: mira $ENTORNO/logs/postgres.log"; exit 1; }

# Si este worktree trae migraciones que la base no tiene, avisa: no las aplica por su cuenta.
faltan=$(comm -23 <(ls "$RAIZ/supabase/migrations" | grep -E '^[0-9]{4}_' | sed -E 's/^0*([0-9]+)_.*/\1/' | LC_ALL=C sort) \
                  <(psql -At -c "select numero from migraciones_aplicadas" | LC_ALL=C sort) | wc -l | tr -d ' ')
[ "$faltan" -gt 0 ] && echo "Ojo: faltan $faltan migraciones de este worktree en la base local. Para ponerla al día: ./scripts/local/crear-base.sh --de-cero"

sed -e "s/PG_PUERTO/$PG_PUERTO/" -e "s/JWT_SECRETO/$JWT_SECRET/" -e "s/REST_PUERTO/$REST_PUERTO/" "$RAIZ/scripts/local/postgrest.conf.plantilla" > "$ENTORNO/postgrest.conf"
if ! lsof -iTCP:$REST_PUERTO -sTCP:LISTEN >/dev/null 2>&1; then
  nohup postgrest "$ENTORNO/postgrest.conf" >"$ENTORNO/logs/postgrest.log" 2>&1 &
fi
if ! lsof -iTCP:$PUERTA_PUERTO -sTCP:LISTEN >/dev/null 2>&1; then
  nohup node "$RAIZ/scripts/local/puerta.mjs" >"$ENTORNO/logs/puerta.log" 2>&1 &
fi
node "$RAIZ/scripts/local/sembrar.mjs" --solo-marcas
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -sf "http://127.0.0.1:$PUERTA_PUERTO/salud" >/dev/null && break
  sleep 0.5
done
curl -sf "http://127.0.0.1:$PUERTA_PUERTO/salud" >/dev/null || { echo "La puerta no responde: mira $ENTORNO/logs/puerta.log"; exit 1; }
echo "Entorno local encendido. Cuentas: ver scripts/local/LEEME.md"
