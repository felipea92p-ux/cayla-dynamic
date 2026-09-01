# Plan de trabajo — Coser la costura entre Dynamic y CAYLA retail
**Objetivo del día: 2026-07-23** · Estado: PLANIFICADO (nada aplicado todavía)

## El problema, en una línea
`personas` y `sedes` viven **duplicadas** en las dos bases (Dynamic y retail), sin nadie que las mantenga iguales → **van a divergir**. Hay que darles **un dueño** (Dynamic) y que retail las **lea en vivo**.

## La solución decidida (recordatorio de anoche)
- **Dueño de personas y sedes: Dynamic** (es el HR + ya tiene el admin de sedes). Retail las *consume*, no las inventa.
- **Mecanismo: retail JALA en vivo** (la caja trabaja siempre con internet) desde una **"ventanita" de solo lectura** en Dynamic que expone **solo lo mínimo**: DNI, nombre, sede, activo — **nada** de sueldo, disciplina ni datos personales.
- **Amarre: por DNI** (el mismo documento en las dos bases).
- **Una sola dirección:** retail lee, **nunca** escribe de vuelta.
- **Red de seguridad:** retail guarda la última lista que vio, por si Dynamic parpadea (la caja nunca se traba).

---

## Las fases (en orden — no saltarse ninguna)

### Fase 0 — Reconciliación (diagnóstico) · ~30 min · SOLO LECTURA, cero riesgo
Medir el desajuste real **antes** de tocar nada. Se cambia el terreno antes de cambiarlo.

`01-reconciliacion.sql` son **tres bloques, una sola consulta cada uno** — el SQL
Editor de Supabase muestra el resultado de la última sentencia, así que un bloque
con tres SELECT enseña uno y esconde dos:

1. **Bloque A**, en **Dynamic**: qué tan limpio está el DNI de este lado
   (activas sin documento, formato raro, repetidos, los que empiezan con cero) y
   quién trabaja en una sede distinta a su sede base.
2. **Bloque B**, en **retail**: `B0` descubre cómo se llaman las columnas, `B1`
   devuelve **una sola celda** con la lista entera ya empaquetada.
3. **Bloque C**, en **Dynamic**: se pega ahí la celda de B1 y **el diff lo hace
   SQL**, no el ojo — quién coincide, quién está solo en un lado, quién comparte
   DNI con otro nombre, quién está activa acá e inactiva allá.

El amarre del bloque C **normaliza** antes de comparar (mayúsculas, sin espacios
ni guiones, y rellena con ceros a la izquierda los DNI de solo dígitos). Sin eso,
`08817189` y `8817189` —el mismo documento guardado como texto acá y como número
allá— aparecen como dos personas huérfanas y la Fase 1 se convierte en una
cacería inventada.

**Entregable:** foto clara del desajuste + la lista de DNIs a limpiar.
⚠️ La salida lleva DNI y nombres reales: no se commitea ni se pega en una issue.

### Fase 1 — Limpiar DNIs · variable · trabajo de DATOS (Felipe/DO), no código
El amarre es el DNI. Todo el que no tenga DNI, o lo tenga distinto en cada lado (un dígito, un espacio), hay que arreglarlo. **Esta es la tarea de verdad** — sin DNIs limpios, la ventanita duplica gente.
- *Qué hace:* dejar el DNI confiable en los dos lados.
- *Qué revisar:* que cada persona activa tenga DNI y que coincida entre bases.
- *Reversible:* sí, son ediciones de datos a mano.

### Fase 2 — La "ventanita" en Dynamic · ~1 h · **la hago yo (este repo)**
- Migración: crear las vistas de solo lectura `v_personas_publica` y `v_sedes_publica` (solo DNI, nombre, sede, activo).
- Borrador ya escrito en `02-vista-personas-DRAFT.sql` (para revisar juntos).
  ⚠️ **Ese borrador NO se aplica tal cual.** Medido el 2026-08-11: sin
  `security_invoker` y con el `alter default privileges` de la 0004, la vista de
  sedes nace **escribible** por cualquier sesión con login (un `update` tocó las
  3 sedes, un `delete` también pasó) y la de personas expone el DNI de todas a
  cualquier integrante. El detalle y lo que la versión buena tiene que llevar
  están en el encabezado del propio borrador.
- **Decidir el acceso de retail** (la única decisión estructural que falta):
  - **Opción A — Key de solo lectura:** retail se conecta a la API de Supabase de Dynamic con una clave que SOLO puede leer estas dos vistas. Más simple.
  - **Opción B — Una Edge Function:** un mini-endpoint en Dynamic que devuelve el JSON. Más control, más piezas.
  - *Recomendación:* A, si los permisos alcanzan; si no, B.
- **Las 3 líneas de la migración** (para tus nervios):
  - *Qué hace:* crea dos "ventanas" que muestran solo columnas seguras; no copia ni mueve datos.
  - *Qué devuelve si salió bien:* "Success. No rows returned".
  - *¿Reversible?* Sí — una vista se borra con una línea, sin tocar los datos.

### Fase 3 — Retail "se asoma" · **otro repo / otro chat**
- En la app de retail: al abrir la lista de vendedoras, consultar la ventanita, emparejar por DNI, mostrar la lista fresca, y guardar la última vista como respaldo.
- Es trabajo del **otro sistema** → sesión aparte con el repo de retail.

### Fase 4 — (opcional, después) ventas → desempeño
El segundo puente, retail → Dynamic: que las ventas de una persona alimenten su desempeño/objetivos aquí. **No ahora.**

---

## Reglas de oro (no romper)
1. **Reconciliar antes de construir** (Fase 0 antes que Fase 2).
2. **Sedes antes que personas** (una persona necesita su sede primero).
3. **Nunca borrar — desactivar** (retail tiene ventas viejas atadas a cada persona).
4. **Una sola dirección** (retail lee; jamás escribe a Dynamic).
5. **La ventanita solo deja pasar lo seguro** (nada de sueldo/disciplina/datos personales).

## Qué NO hacer mañana
- ❌ Fusionar los dos sistemas.
- ❌ Sincronizar inventario o contabilidad.
- ❌ Dar acceso de **escritura** a retail.
- ❌ La sincronización "al instante" con mensajero + reintentos (frágil e innecesaria: jalar en vivo es más fresco y más simple).

## Se rompe si…
- …el DNI no está limpio → la ventanita no reconoce a la persona y la duplica. (Por eso la Fase 1 es la de verdad.)
- …retail borra en vez de desactivar → rompe el histórico de ventas.
- …alguien deja que los dos sistemas sigan editando personas/sedes por su cuenta → en meses no sabes cuál lista es la buena.

## Cómo arrancamos mañana
Dime **"empecemos con la reconciliación"** y te guío la Fase 0 paso a paso (solo lectura, 30 min). Con esa foto decidimos el resto.
