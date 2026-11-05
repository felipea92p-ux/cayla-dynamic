#!/bin/bash
# Apaga el entorno local. Los datos se quedan; para borrarlos: crear-base.sh --de-cero
set -u
source "$(dirname "$0")/comun.sh"
for p in $REST_PUERTO $PUERTA_PUERTO; do lsof -tiTCP:$p -sTCP:LISTEN | xargs -r kill 2>/dev/null; done
pg_ctl -D "$ENTORNO/pg" -m fast stop >/dev/null 2>&1
echo "Apagado."
