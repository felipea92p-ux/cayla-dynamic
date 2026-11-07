#!/bin/bash
# Enciende el Realtime de Supabase para el entorno local, si hay Docker. Lo llama arrancar.sh; se puede correr solo.
#
# Promete: con Docker prendido, las pantallas del entorno local se enteran de un cambio en ~50 ms, igual que en
#          producción (migración 0604). Es el servidor de Realtime de verdad, no una imitación, conectado a la base local.
# Sin Docker no pasa nada malo: dice en una línea que el tiempo real queda apagado y las pantallas se ponen al día
#          con su respaldo de 5 min. Por eso termina siempre con 0: el resto del entorno no depende de esto.
#
# Lo que hace falta y por qué:
#   * `wal_level=logical` en la base: Realtime lee los avisos de `realtime.messages` por replicación lógica.
#     Lo pone PG_OPCIONES (comun.sh), pero solo vale desde el próximo arranque de Postgres.
#   * La política `tiempo_real_escuchar` la crea la 0604 SOLO si `realtime.messages` existe, y esa tabla la crea
#     Realtime la primera vez que arranca. En una base nueva la migración corre antes, así que al final se vuelve a
#     correr la última migración que define la política, que es idempotente como todas.
set -u
source "$(dirname "$0")/comun.sh"
IMAGEN=public.ecr.aws/supabase/realtime:v2.124.2   # la misma que levanta la CLI 2.113.0 de CI
NOMBRE=dynamic-local-realtime-$REALTIME_PUERTO

if ! docker info >/dev/null 2>&1; then
  echo "Tiempo real: apagado (Docker no está prendido). Las pantallas se ponen al día cada 5 min."
  exit 0
fi
if [ "$(psql -At -c 'show wal_level')" != logical ]; then
  echo "Tiempo real: apagado. La base arrancó antes de que se pidiera wal_level=logical."
  echo "  Apágala y vuelve a encenderla cuando nadie la esté usando: ./scripts/local/apagar.sh && node scripts/local/web.mjs"
  exit 0
fi

# Donde Realtime guarda su configuración (`_realtime`) y donde crea sus tablas (`realtime`). La imagen de Supabase
# los trae creados; la base local, no.
psql -q -c "set client_min_messages = warning; create schema if not exists _realtime; create schema if not exists realtime;" >/dev/null
# Y un rol de Supabase al que sus migraciones dan permisos: sin él se quedan en la 79 de 81 (medido con la v2.124.2).
psql -q -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'dashboard_user') then create role dashboard_user nologin; end if; end \$\$;" >/dev/null

if [ -z "$(docker ps -q -f "name=^${NOMBRE}$")" ]; then
  docker rm -f "$NOMBRE" >/dev/null 2>&1
  # host.docker.internal: desde el contenedor, la base de esta Mac (que solo escucha en 127.0.0.1).
  # DB_USER=supabase_admin, como en Supabase, y NO postgres: lo que crea `postgres` nace sin permiso de ejecutar
  # (la 0076 se lo quitó por defecto), y entonces nadie puede llamar a `realtime.topic()` y Realtime contesta
  # «Unauthorized» a todo el mundo. Pasó la primera vez que se probó (2026-11-07).
  docker run -d --name "$NOMBRE" -p "127.0.0.1:$REALTIME_PUERTO:4000" \
    -e PORT=4000 -e APP_NAME=realtime -e SEED_SELF_HOST=true -e RUN_JANITOR=true -e MAX_HEADER_LENGTH=4096 \
    -e DB_HOST=host.docker.internal -e DB_PORT="$PG_PUERTO" -e DB_NAME=postgres -e DB_USER=supabase_admin -e DB_PASSWORD=postgres \
    -e DB_AFTER_CONNECT_QUERY='SET search_path TO _realtime' -e DB_ENC_KEY=supabaserealtime \
    -e API_JWT_SECRET="$JWT_SECRET" -e METRICS_JWT_SECRET="$JWT_SECRET" -e SECRET_KEY_BASE="$(openssl rand -hex 32)" \
    -e ERL_AFLAGS='-proto_dist inet_tcp' -e DNS_NODES="''" \
    "$IMAGEN" >/dev/null 2>"$ENTORNO/logs/realtime-docker.err" \
    || { echo "Tiempo real: el contenedor no arrancó (mira $ENTORNO/logs/realtime-docker.err)."; exit 0; }
fi

for _ in $(seq 1 60); do
  curl -sf -o /dev/null -H Host:realtime-dev "http://127.0.0.1:$REALTIME_PUERTO/api/ping" && break
  sleep 1
done
if ! curl -sf -o /dev/null -H Host:realtime-dev "http://127.0.0.1:$REALTIME_PUERTO/api/ping"; then
  echo "Tiempo real: el servidor no responde (docker logs $NOMBRE)."
  exit 0
fi

# Realtime prepara la base al conectarse (sus migraciones y `realtime.messages`): se le dan unos segundos, y
# no se da por encendido con la tabla sola —la primera vez que se probó, la tabla estaba y faltaban 2 migraciones—.
listo() { psql -At -c "select to_regclass('realtime.messages') is not null and to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null" 2>/dev/null; }
for _ in $(seq 1 30); do [ "$(listo)" = t ] && ! docker logs "$NOMBRE" 2>&1 | grep -q "Failed to set-up tenant" && break; sleep 1; done
if [ "$(listo)" != t ] || docker logs "$NOMBRE" 2>&1 | grep -q "Failed to set-up tenant"; then
  echo "Tiempo real: el servidor responde pero no terminó de preparar la base ($(docker logs "$NOMBRE" 2>&1 | grep -o 'Failed to set-up tenant.*message: "[^"]*"' | tail -1))."
  exit 0
fi

# La política, si la base la necesita y todavía no la tiene.
if [ "$(psql -At -c "select to_regprocedure('fn_tiempo_real_puede_escuchar(text)') is not null
                        and not exists (select 1 from pg_policies where schemaname = 'realtime' and policyname = 'tiempo_real_escuchar')")" = t ]; then
  ultima=$(grep -l "create policy tiempo_real_escuchar" "$RAIZ"/supabase/migrations/*.sql | LC_ALL=C sort | tail -1)
  psql -X -1 -q -v ON_ERROR_STOP=1 -f "$ultima" >"$ENTORNO/logs/realtime-politica.out" 2>&1 \
    || { echo "Tiempo real: no se pudo poner la política (mira $ENTORNO/logs/realtime-politica.out)."; exit 0; }
fi
echo "Tiempo real: encendido (Realtime en el puerto $REALTIME_PUERTO, contenedor $NOMBRE)."
