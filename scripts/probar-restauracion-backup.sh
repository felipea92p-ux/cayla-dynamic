#!/usr/bin/env bash
# ##############################################################################
# ####  ¿EL RESPALDO SE PUEDE RESTAURAR DE VERDAD?                        ####
# ##############################################################################
#
# Para qué. `scripts/sql-manual/la_boleta_dice_lo_que_se_pago.sql` ya comprueba
# que `fn_planilla_calcular` no se haya movido desde que se pagó un mes — un
# riesgo de LÓGICA. Este script comprueba algo distinto y anterior: que el
# ARCHIVO del respaldo de producción de verdad contiene los datos y se puede
# convertir otra vez en una base de datos que responde. Nadie lo había probado.
#
# No toca producción. No pide ni ve la cadena de conexión de producción — ese
# dato lo maneja Felipe a mano, igual que el SQL (ver CLAUDE.md). Este script
# solo recibe un ARCHIVO ya exportado y lo restaura en un Postgres desechable,
# aislado, en un nombre de contenedor propio que no toca el Supabase local que
# comparten las demás sesiones.
#
# Solo necesita Docker — nada de instalar psql/pg_dump/pg_restore en la Mac.
# Todo corre DENTRO del contenedor, con los binarios que ya trae la imagen de
# Postgres (el mismo patrón que ya usa `npx supabase db start`).
#
# CÓMO SE OBTIENE EL ARCHIVO (a mano, desde tu máquina, con tu cadena de
# conexión de producción — nunca dentro de un script versionado):
#
#   docker run --rm postgres:17-alpine pg_dump "$CADENA_DE_PRODUCCION" \
#     --schema=public --no-owner --no-privileges --format=custom \
#     > respaldo_$(date +%Y%m%d).dump
#
# Por qué `--schema=public`: ahí vive todo lo que este sistema mismo modela
# (personas, marcajes, periodos_planilla, planilla_pagada_detalle...). Los
# esquemas que administra la plataforma de Supabase (auth, storage, cron,
# extensions) no están gobernados por las migraciones de este repo y no son lo
# que esta prueba necesita verificar. Ver docs/prueba-restauracion-backup.md.
#
# USO
#   ./scripts/probar-restauracion-backup.sh respaldo.dump
#
# QUÉ HACE, EN ORDEN
#   1. Levanta un Postgres 17 vacío y desechable (mismo major_version que
#      supabase/config.toml) en un contenedor propio.
#   2. Copia el archivo adentro y lo restaura ahí, con las herramientas que ya
#      trae la imagen — nunca con binarios del host.
#   3. Lee — solo lee — periodos_planilla y planilla_pagada_detalle, y muestra
#      el total pagado por periodo para que lo compares a ojo con lo que sabes
#      que se pagó (o con la última salida de la_boleta_dice_lo_que_se_pago.sql
#      en producción).
#   4. Apaga y borra el contenedor SIEMPRE, incluso si algo falla a medias.
#
# QUÉ NO PRUEBA. Que el archivo restaure no prueba que la lógica de hoy
# reproduzca lo que se pagó — eso es lo que ya mide
# `la_boleta_dice_lo_que_se_pago.sql`. Las dos pruebas se complementan; ninguna
# reemplaza a la otra.
# ##############################################################################

set -euo pipefail

ARCHIVO="${1:-}"
if [[ -z "$ARCHIVO" ]]; then
  echo "Uso: $0 <archivo_de_respaldo.dump>" >&2
  exit 1
fi
if [[ ! -s "$ARCHIVO" ]]; then
  echo "✗ No existe o está vacío: $ARCHIVO" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "✗ Hace falta Docker (el mismo que usa 'npx supabase db start')." >&2
  exit 1
fi

CONTENEDOR="cayla-prueba-restauracion"
IMAGEN="postgres:17-alpine"
CLAVE="prueba-local-no-es-secreto"
DENTRO="/tmp/respaldo.dump"

# Por si quedó un contenedor de una corrida anterior que falló a medias.
docker rm -f "$CONTENEDOR" >/dev/null 2>&1 || true

limpiar() {
  local codigo=$?
  docker rm -f "$CONTENEDOR" >/dev/null 2>&1 || true
  if [[ $codigo -ne 0 ]]; then
    echo "✗ La prueba se detuvo con error. El contenedor desechable ya se borró." >&2
  fi
}
trap limpiar EXIT

echo "· Levantando Postgres 17 desechable (sin publicar puerto — todo corre por 'docker exec')…"
docker run -d --name "$CONTENEDOR" \
  -e POSTGRES_PASSWORD="$CLAVE" \
  -e POSTGRES_DB=restauracion \
  "$IMAGEN" >/dev/null

correr() { docker exec -e PGPASSWORD="$CLAVE" "$CONTENEDOR" "$@"; }

echo "· Esperando a que responda…"
LISTO=""
for _ in $(seq 1 30); do
  if correr pg_isready -U postgres >/dev/null 2>&1; then
    LISTO=1
    break
  fi
  sleep 1
done
if [[ -z "$LISTO" ]]; then
  echo "✗ El Postgres desechable no respondió en 30s." >&2
  exit 1
fi

echo "· Preparando extensiones que el esquema suele necesitar (pgcrypto, uuid-ossp, btree_gist)…"
# En un esquema APARTE, no en public: el paso siguiente restaura con --clean,
# que borra y recrea public entero. Si las extensiones vivieran ahí, ese mismo
# --clean se las llevaría por delante antes de que sirvan de algo.
# btree_gist hace falta para restricciones EXCLUDE USING gist sobre uuid —
# CAYLA las usa para "esta persona no puede tener dos tramos vigentes que se
# solapen" (horarios, sueldo, ausencias). Sin la extensión, esas cuatro
# restricciones no se recrean y el respaldo quedaría con ese candado abierto.
correr psql -U postgres -d restauracion -v ON_ERROR_STOP=1 -q -c "
  create schema if not exists extensiones_prueba;
  create extension if not exists pgcrypto with schema extensiones_prueba;
  create extension if not exists \"uuid-ossp\" with schema extensiones_prueba;
  create extension if not exists btree_gist with schema extensiones_prueba;
  alter database restauracion set search_path = public, extensiones_prueba;
"

echo "· Creando los roles que Supabase da por sentados (authenticated, anon, service_role)…"
# El pg_dump con --schema=public trae las políticas RLS de CAYLA (son objetos
# de public), pero esos roles los administra la plataforma de Supabase, fuera
# de public — no vienen en el archivo. Sin ellos, cada CREATE POLICY falla
# por "el rol no existe", y la base restaurada quedaría con RLS encendida
# pero sin una sola política: no es que el dato quede expuesto (Postgres deja
# afuera a todo el que no sea el dueño de la tabla cuando RLS está prendido
# sin políticas), pero la prueba de restauración no estaría probando nada del
# modelo de seguridad de este sistema, que es justo lo que sostiene el
# aislamiento por sede. Roles NOLOGIN: no hace falta autenticarse como ellos,
# solo que existan para que las políticas se puedan crear.
correr psql -U postgres -d restauracion -v ON_ERROR_STOP=1 -q -c "
  do \$\$
  begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
      create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'anon') then
      create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
      create role service_role nologin;
    end if;
  end \$\$;
"

echo "· Copiando $ARCHIVO adentro del contenedor…"
docker cp "$ARCHIVO" "$CONTENEDOR:$DENTRO"

echo "· Restaurando…"
if correr pg_restore --list "$DENTRO" >/dev/null 2>&1; then
  # Formato custom/directory/tar (pg_dump --format=custom, el que recomienda
  # el encabezado). --no-owner/--no-privileges: el rol que dumpeó producción
  # no existe en este Postgres desechable. --clean/--if-exists: el contenedor
  # ya trae un esquema `public` vacío de fábrica, y sin esto el propio
  # `CREATE SCHEMA public` del volcado choca contra él — un solo error de ese
  # tipo basta para que pg_restore se salte TODO lo que depende de public,
  # tablas incluidas, sin decirlo con claridad.
  set +e
  SALIDA=$(correr pg_restore --clean --if-exists --no-owner --no-privileges \
             -U postgres -d restauracion "$DENTRO" 2>&1)
  CODIGO=$?
  set -e

  # Lo único que se tolera, con nombre y apellido: que el esquema `auth` no
  # exista. Es la única pieza que este script deja fuera A PROPÓSITO (ver
  # encabezado y docs/prueba-restauracion-backup.md) — administra Supabase,
  # no las migraciones de este repo. Cualquier OTRA cosa que pg_restore no
  # haya podido crear es una tabla, restricción o política real de CAYLA que
  # no volvió, y eso sí tiene que parar la prueba.
  ESPERADOS=$(echo "$SALIDA" | grep -c \
    -e 'schema "auth" does not exist' \
    -e 'function auth\.uid() does not exist' \
    || true)
  TOTAL=$(echo "$SALIDA" | grep -c '^pg_restore: error:' || true)
  INESPERADOS=$((TOTAL - ESPERADOS))

  echo "$SALIDA" | grep -v "^pg_restore: warning: errors ignored on restore" || true

  if [[ $INESPERADOS -gt 0 ]]; then
    echo "✗ $INESPERADOS error(es) de pg_restore que NO son el esquema auth excluido a propósito." >&2
    echo "  Eso es una tabla, restricción o política de CAYLA que no volvió. Revisa el detalle arriba." >&2
    exit 1
  elif [[ $TOTAL -gt 0 ]]; then
    echo "· $TOTAL advertencia(s) — todas del esquema auth, excluido a propósito (ver encabezado). Sigue."
  fi
else
  # Volcado en texto plano (pg_dump sin --format, o --format=plain).
  correr psql -U postgres -d restauracion -v ON_ERROR_STOP=1 -q -f "$DENTRO"
fi

echo "· Restauración terminada. Verificando qué llegó…"
echo

FALTA_TABLA=$(correr psql -U postgres -d restauracion -tA -c "
  select string_agg(t, ', ') from (
    select unnest(array['periodos_planilla','planilla_pagada_detalle']) as t
    except
    select tablename from pg_tables where schemaname = 'public'
  ) x;
")
if [[ -n "$FALTA_TABLA" ]]; then
  echo "✗ El respaldo restauró, pero faltan tablas: $FALTA_TABLA" >&2
  echo "  Revisa que el pg_dump se haya hecho con --schema=public (ver encabezado)." >&2
  exit 1
fi

correr psql -U postgres -d restauracion -c "
  with foto as (
    select d.periodo_id, d.persona_id, d.total
      from planilla_pagada_detalle d
      join (select periodo_id, max(version) as v
              from planilla_pagada_detalle group by periodo_id) m
        on m.periodo_id = d.periodo_id and m.v = d.version
  )
  select to_char(p.fecha_ini, 'DD/MM/YY') || '–' || to_char(p.fecha_fin, 'DD/MM/YY') as periodo,
         p.estado,
         count(f.persona_id) as personas_en_la_foto,
         'S/ ' || to_char(coalesce(sum(f.total), 0), 'FM999G999G990D00') as total_de_la_foto
    from periodos_planilla p
    left join foto f on f.periodo_id = p.id
   group by p.id, p.fecha_ini, p.fecha_fin, p.estado
   order by p.fecha_ini desc;
"

echo
echo "✓ El respaldo restaura y responde. Compara los totales de arriba a ojo"
echo "  contra lo que sabes que se pagó, o contra la última salida de"
echo "  scripts/sql-manual/la_boleta_dice_lo_que_se_pago.sql en producción."
