# Probar que el respaldo se puede restaurar de verdad

**Para quién:** Felipe, cuando quiera comprobar que el respaldo de producción
sirve de algo más que estar ahí.
**Cuándo:** después de cerrar un mes, o al menos una vez por trimestre — y
siempre que cambie algo grande en `supabase/migrations/`.

---

## Dos riesgos distintos, y por qué no es el mismo

Ya existe [`scripts/sql-manual/la_boleta_dice_lo_que_se_pago.sql`](../scripts/sql-manual/la_boleta_dice_lo_que_se_pago.sql),
que corre en el SQL Editor de producción y comprueba que `fn_planilla_calcular`
no se haya movido desde que se pagó un mes cerrado. Ese es un riesgo de
**lógica**: la función cambió, y recalcular hoy da otro número.

Esto de acá comprueba algo distinto y anterior: que el **archivo del
respaldo** de verdad contiene los datos y se puede volver a convertir en una
base de datos que responde. Nadie lo había probado — ni falta que hacía
mientras nada fallara, pero un respaldo que nunca se restauró es una promesa,
no un hecho. Las dos pruebas se complementan; ninguna reemplaza a la otra.

---

## Paso 0 · Confirmar qué hay activado en Supabase

Esto se mira una vez, no cada vez, y solo tú puedes verlo (necesita tu cuenta
del dashboard):

En el proyecto de producción → **Project Settings → Database → Backups**,
confirma:

- Si el plan trae **Point-in-Time Recovery (PITR)**, y cuál es la ventana de
  retención (cuántos días atrás se puede restaurar).
- Si no lo trae, Supabase igual guarda respaldos diarios automáticos con
  retención más corta — confirma cuántos días.

No asumas nada de esto desde el código: es una propiedad del plan contratado,
no de las migraciones.

---

## Paso 1 · Sacar un archivo de producción

Desde tu máquina, con tu cadena de conexión de producción — **nunca dentro de
un script que se vaya a commitear**:

```bash
docker run --rm postgres:17-alpine pg_dump "$CADENA_DE_PRODUCCION" \
  --schema=public --no-owner --no-privileges --format=custom \
  > respaldo_$(date +%Y%m%d).dump
```

**Por qué `--schema=public` y no la base entera.** Ahí vive todo lo que este
sistema modela con sus propias migraciones: `personas`, `marcajes`,
`periodos_planilla`, `planilla_pagada_detalle`, etc. Los esquemas que
administra la plataforma (`auth`, `storage`, `cron`, `extensions`) no están
gobernados por `supabase/migrations/` y no son lo que esta prueba necesita
verificar — además de que traen roles y extensiones propias de la
infraestructura de Supabase que un Postgres corriente no tiene, y que harían
fallar la restauración por razones que no tienen nada que ver con si el
respaldo sirve.

**Por qué con Docker y no instalando `psql`/`pg_dump` en la Mac.** Ya usas
Docker para `npx supabase db start`; esto sigue el mismo patrón en vez de
sumar una instalación nueva solo para esta prueba.

---

## Paso 2 · Restaurar y verificar, en un Postgres desechable

```bash
./scripts/probar-restauracion-backup.sh respaldo_20260829.dump
```

El script:

1. Levanta un Postgres 17 vacío en un contenedor propio — **no toca** el
   Supabase local que usan las demás sesiones de trabajo (nombre y ciclo de
   vida separados).
2. Restaura el archivo ahí dentro.
3. Lee — solo lee — `periodos_planilla` y `planilla_pagada_detalle`, y
   muestra el total pagado por periodo.
4. Borra el contenedor al terminar, incluso si algo falla a medias.

No pide ni ve tu cadena de conexión de producción en ningún momento — solo
recibe el archivo que ya generaste tú mismo en el paso 1.

---

## Paso 3 · Leer el resultado

El script termina con una tabla como esta:

```
      periodo      | estado | personas_en_la_foto | total_de_la_foto
-------------------+--------+----------------------+------------------
 29/07/26–28/08/26 | pagado |                   28 | S/ 41,230.50
```

Compara el total a ojo contra lo que sabes que se transfirió ese mes, o contra
la última vez que corriste `la_boleta_dice_lo_que_se_pago.sql` en producción
(que lee la misma tabla). Si coincide, el respaldo de ese punto en el tiempo
es utilizable. Si el script se corta antes de llegar a la tabla, léelo — dice
en qué paso falló y por qué, no solo que falló.

**Qué NO prueba esto.** Que el archivo restaure no dice que la lógica de hoy
reproduzca lo que se pagó — para eso está la otra consulta. Tampoco prueba
`auth`, `storage` ni `pg_cron`: esos quedan fuera a propósito (ver Paso 1).

---

## Los archivos de Storage no están en este respaldo (las boletas oficiales)

Todo lo de arriba es la BASE. Los archivos que viven en Storage —hoy, las boletas
oficiales que sube DO (0482, bucket «boletas»)— no entran en ningún paso de esta
guía. Por lo que se sabe de Supabase, tampoco entran en el respaldo diario de la
base de datos (**confírmalo en la consola de tu plan**: es un dato de la
plataforma, no de este repositorio).

**Qué se perdería.** La base guarda quién publicó cada boleta y cuándo la abrió y
la confirmó cada persona; el documento —la foto o el PDF que entregó el contador—
está solo en el bucket. Si Storage pierde un archivo, la constancia queda apuntando
a nada, y ese archivo no se puede regenerar: no lo calculó el sistema.

**Qué hacer.** Una vez al mes, después de cerrar el periodo y publicar las boletas:

```bash
./scripts/respaldar-boletas.sh            # baja el bucket a ~/CAYLA-respaldos/boletas/…
```

Lo baja fuera del repositorio (lleva sueldos de personas reales), comprueba que lo
bajado coincide con lo que Storage lista y deja un `MANIFIESTO.sha256` para
comprobar después que nada cambió. **Luego copia esa carpeta a un segundo lugar**
(otro disco u otro servicio): una copia en el mismo disco de la Mac no es respaldo.
Son ≈ 180 MB al año, así que cada corrida es una copia completa y fechada.

**Qué NO está probado.** Restaurar. La base referencia cada hoja por su ruta
(`<periodo>/<persona>/<uuid>.<ext>`), así que restaurar es volver a subir cada
archivo a **la misma ruta**. Cuando haya una primera copia real, prueba restaurar
UN archivo en el Supabase local (`MODO_STORAGE=--local`) antes de necesitarlo.
Tampoco se ha corrido el script contra el CLI de Supabase real: se probó con un
CLI de mentira (10 casos, incluida una copia incompleta y una descarga que falla).
En la primera corrida real, si el conteo dice «NO COINCIDE» y los números
parecen razonables, puede ser el formato de lo que lista el CLI: se ajusta el
`grep` del paso 3 del script. Falla en voz alta, no en silencio: un conteo que no
coincide nunca se da por bueno.

---

## Con qué frecuencia

No hay una regla escrita todavía porque nunca se había hecho. Como punto de
partida: una vez después de cada cierre de mes (día 28) y una vez si se
aplica una migración que reescribe `fn_planilla_calcular` u otra función de
planilla. Si con el tiempo esto se vuelve rutina, vale la pena anotar aquí
cada corrida — fecha, periodo probado, si coincidió — para que quede un
historial de que la promesa se cumplió, no solo que se probó una vez.
