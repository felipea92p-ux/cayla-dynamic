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
1. Correr `01-reconciliacion.sql` → **Parte A** en la base de **Dynamic**.
2. Correr **Parte B** en la base de **retail** (primero la mini-consulta que lista las columnas de `retail.personas`, para ajustar los nombres).
3. **Pegarme las dos salidas** → yo produzco el diff exacto:
   - Quién está en las dos (DNI coincide).
   - Quién está solo en una.
   - Quién **no tiene DNI** (los que van a dar problema).
   - Sedes: qué difiere entre las dos listas.

**Entregable:** foto clara del desajuste + la lista de DNIs a limpiar.

### Fase 1 — Limpiar DNIs · variable · trabajo de DATOS (Felipe/DO), no código
El amarre es el DNI. Todo el que no tenga DNI, o lo tenga distinto en cada lado (un dígito, un espacio), hay que arreglarlo. **Esta es la tarea de verdad** — sin DNIs limpios, la ventanita duplica gente.
- *Qué hace:* dejar el DNI confiable en los dos lados.
- *Qué revisar:* que cada persona activa tenga DNI y que coincida entre bases.
- *Reversible:* sí, son ediciones de datos a mano.

### Fase 2 — La "ventanita" en Dynamic · ~1 h · **la hago yo (este repo)**
- Migración: crear las vistas de solo lectura `v_personas_publica` y `v_sedes_publica` (solo DNI, nombre, sede, activo).
- Borrador ya escrito en `02-vista-personas-DRAFT.sql` (para revisar juntos).
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
