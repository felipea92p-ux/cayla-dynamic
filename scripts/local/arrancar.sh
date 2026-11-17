#!/bin/bash
# Enciende el entorno local: base (si no existe, la crea con sus datos inventados), PostgREST y la puerta.
# No toca las bases compartidas ni producción. Docker solo para el tiempo real, y solo si está prendido (tiempo-real.sh).
set -u
source "$(dirname "$0")/comun.sh"
[ -d "$ENTORNO/pg" ] || "$RAIZ/scripts/local/crear-base.sh" || exit 1

pg_ctl -D "$ENTORNO/pg" status >/dev/null 2>&1 || pg_ctl -D "$ENTORNO/pg" -l "$ENTORNO/logs/postgres.log" -w \
  -o "$PG_OPCIONES" start >/dev/null \
  || { echo "Postgres no arrancó: mira $ENTORNO/logs/postgres.log"; exit 1; }

# Si este worktree trae migraciones que la base no tiene, avisa: no las aplica por su cuenta.
faltan=$(comm -23 <(ls "$RAIZ/supabase/migrations" | grep -E '^[0-9]{4}_' | sed -E 's/^0*([0-9]+)_.*/\1/' | LC_ALL=C sort) \
                  <(psql -At -c "select numero from migraciones_aplicadas" | LC_ALL=C sort) | wc -l | tr -d ' ')
[ "$faltan" -gt 0 ] && echo "Ojo: faltan $faltan migraciones de este worktree en la base local. Para ponerla al día: ./scripts/local/crear-base.sh --de-cero"

sed -e "s/PG_PUERTO/$PG_PUERTO/" -e "s/JWT_SECRETO/$JWT_SECRET/" -e "s/REST_PUERTO/$REST_PUERTO/" "$RAIZ/scripts/local/postgrest.conf.plantilla" > "$ENTORNO/postgrest.conf"
if ! lsof -iTCP:$REST_PUERTO -sTCP:LISTEN >/dev/null 2>&1; then
  # Sin PostgREST la app entra (la puerta atiende el ingreso) y después no puede leer ni guardar nada: cada pantalla
  # recibe un 502 y parece rota por otra causa. Se dice aquí, antes de encender lo demás.
  command -v postgrest >/dev/null 2>&1 \
    || { echo "Falta PostgREST: no está instalado o no está en el PATH. Sin él la app no puede leer ni guardar datos. En Mac: brew install postgrest"; exit 1; }
  nohup postgrest "$ENTORNO/postgrest.conf" >"$ENTORNO/logs/postgrest.log" 2>&1 &
fi
if ! lsof -iTCP:$PUERTA_PUERTO -sTCP:LISTEN >/dev/null 2>&1; then
  nohup node "$RAIZ/scripts/local/puerta.mjs" >"$ENTORNO/logs/puerta.log" 2>&1 &
fi
node "$RAIZ/scripts/local/sembrar.mjs" --solo-marcas
node "$RAIZ/scripts/local/sembrar.mjs" --solo-ceses
node "$RAIZ/scripts/local/sembrar.mjs" --solo-seguros
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -sf "http://127.0.0.1:$PUERTA_PUERTO/salud" >/dev/null && break
  sleep 0.5
done
curl -sf "http://127.0.0.1:$PUERTA_PUERTO/salud" >/dev/null || { echo "La puerta no responde: mira $ENTORNO/logs/puerta.log"; exit 1; }
# La API de datos también tiene que contestar antes de decir «encendido». Hasta el 2026-11-17 no se comprobaba: con
# PostgREST caído este script terminaba bien y la app recibía «rest_caido» en cada pantalla. Cualquier respuesta por
# debajo de 500 vale (PostgREST contesta 503 mientras no puede hablar con la base); que no conteste nadie, no.
rest_responde() {
  local codigo
  codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$REST_PUERTO/" 2>/dev/null)
  [ "${codigo:-000}" -ge 200 ] && [ "${codigo:-000}" -lt 500 ]
}
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  rest_responde && break
  sleep 0.5
done
rest_responde || { echo "PostgREST no responde en el puerto $REST_PUERTO: mira $ENTORNO/logs/postgrest.log"; exit 1; }
"$RAIZ/scripts/local/tiempo-real.sh"
echo "Entorno local encendido. Cuentas: ver scripts/local/LEEME.md"
