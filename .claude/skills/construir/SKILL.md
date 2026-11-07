---
name: construir
description: Ejecuta una construcción grande de Dynamic (pantalla nueva, módulo, migración con función y pantalla) actividad por actividad, cada una un corte vertical verificable con su propio commit y sin desviarse a nada fuera de ella. Úsala para trabajo de varios pasos que normalmente se dispersa; no para un arreglo de un solo archivo.
---

> Adaptada de `construir` de `cayla-retail` (2026-11-06). Lo que cambió: el cierre es `docs/estado.md` y no bitácora y backlog, los commits son
> frases en español, y se suman las reglas de Dynamic sobre SQL, vidrio y novedades.

Construye $ARGUMENTS con este protocolo. El objetivo es cortar el divagar, no añadir ceremonia.

## 0. Apuesta el alcance antes de tocar código

Terreno primero: `git log --all --oneline -20` y `./scripts/sesiones.sh` (¿otra sesión lo está haciendo?), y `./scripts/donde-vive.sh <función>` por cada función SQL que vayas a crear o reescribir.

Arma la lista COMPLETA de actividades. Cada una es un corte vertical demostrable de punta a punta («aprobar un cambio de turno» = esquema + función + pantalla + prueba), nunca una capa sola. Ordénalas por dependencia técnica y usa el valor de negocio para desempatar.

Preséntala como lista numerada corta, una línea por actividad con lo que queda demostrable al cerrarla, y espera la aprobación de Felipe con `AskUserQuestion` antes de escribir código. Es la única pausa dura del flujo.

## 1. Por cada actividad aprobada, en orden

a. Anuncia en una línea qué vas a hacer y cómo lo vas a verificar: un comando, una prueba o la pantalla en el navegador. Nunca «debería funcionar».
b. Constrúyela completa. Ningún refactor «ya que estoy aquí» y ningún archivo fuera de lo que esa actividad necesita, aunque sea de dos líneas.
c. Verifícala con evidencia real. Si es pantalla, `preview_start` con `dynamic-local` (datos inventados, nunca producción). Si toca plata, `BEGIN … ROLLBACK` contra el Postgres local con casos reales, y la prueba de control sin tu cambio.
d. Un commit por actividad, con `git commit -o <rutas>` y un mensaje en español que diga qué cambia para quien usa el sistema. Nunca `--amend`. Se commitea antes de pasar a lo siguiente: un archivo sin commitear solo existe mientras nadie toque el árbol.
e. Reporta en tres líneas qué hiciste, por qué así y qué se rompería sin esto, y pasa a la siguiente.

## 2. Reglas de Dynamic que una construcción no se salta

- **Migraciones:** número con `./scripts/siguiente-numero.sh`, encabezado completo, idempotente, registro con `do update`. Felipe las pega a mano: se entregan con `./scripts/dame-el-sql.sh`, nunca transcritas al chat.
- **Una función que se reescribe:** md5 de producción al empezar y otra vez en el mensaje en que se entrega el SQL, porque un md5 es una foto. El de llegada se mide después de renumerar.
- **Más de una tabla en uso:** la migración se pega en partes.
- **La migración se pega ANTES de fusionar el PR que la usa.** Fusionar es publicar.
- **Diseño:** todo CSS de vidrio cuelga de `[data-vidrio="panel"]` o `[data-vidrio="terminal"]`, y nada se sube sin que Felipe lo vea en local.
- **Un cambio que el equipo va a notar** lleva su novedad en `apps/web/lib/novedades.ts`, en el mismo PR. Nunca una regla de pago, un descuento, una tardanza ni algo disciplinario.
- **Lo que deciden las personas:** Dynamic avisa, nunca sanciona solo.

## 3. Si algo FUERA de la actividad la bloquea

No inventes una regla nueva. ¿Ya vive en el repo, el esquema o `docs/`? Úsala. Si no, y cuesta más de 30 minutos deshacerlo mal o es de cómo opera CAYLA, detente y usa `/decide`. Si no, resuélvelo, sigue y dilo en el reporte de esa actividad.

## 4. Si algo NO bloquea pero vale la pena arreglar

No lo toques. Propónlo como tarea aparte, con `archivo:línea`, y sigue. Si solo lo mencionas en el reporte, se pierde.

## 5. Si la LISTA resulta estar mal

Falta una actividad, el orden no sirve o una era en realidad dos: detente, explica por qué y repropón la lista completa. No sigas por inercia con un plan que ya sabes que está mal.

## 6. Al cerrar la última actividad

Actualiza `docs/estado.md` si cambió dónde estamos, deja un ADR si hubo una decisión estructural, y usa `/abrir-pr` cuando Felipe pida subirlo. No fusiones: fusionar es publicar y lo pide Felipe.
