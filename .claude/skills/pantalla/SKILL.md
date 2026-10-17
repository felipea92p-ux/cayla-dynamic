---
name: pantalla
description: Analiza una pantalla (captura o ruta) o un flujo de Dynamic — estética, lógica de negocio, arquitectura y rendimiento, funciones, utilidad y conexión con planilla/asistencia —, mide si cumple su finalidad y cuán relevante es, y propone 12 tareas ordenadas por importancia. Úsala cuando Felipe pase una captura o una ruta. Con `rapido` en los argumentos hace una pasada barata.
---

Analiza la pantalla o el flujo que Felipe indica: $ARGUMENTS

> Adaptada de la skill `pantalla` de `cayla-retail` (2026-10-13). Lo que cambió: aquí
> el dinero es **planilla** y no stock, el esquema es `public` y no `retail`, no hay
> `docs/datos/` ni `BACKLOG.md`, y el "visto bueno" de la estética son los trece
> `--color-*` de `globals.css`. Si retail mejora el método, se trae a mano.

**Entrada:** captura(s) y/o ruta (ej. `/admin/horas`). Sin captura, lees el código y lo declaras: `[visto]` queda vacío y no se inventa. Sin ruta ni captura, las pides y paras.
**Alcance:** una pantalla = una ruta. Varias del mismo recorrido = un flujo: cada pantalla y, aparte, las costuras (qué dato viaja, cuál se pierde, dónde se equivoca la integrante o la líder).
**Modo:** `rapido` = ver al final. Sin él, completo.
**Regla madre:** solo analizas y propones. No toques código, migraciones ni `estado.md`; ejecutar es un paso aparte que Felipe ordena ("haz de la #1 a la #4"). Y por la regla de la casa, **preguntas con `AskUserQuestion`, opción recomendada primero, antes de ejecutar cualquier cosa de peso.**

## Paso 0 — Terreno (antes de opinar)

1. `git fetch origin` y `git rev-list --left-right --count HEAD...origin/main`. Si la rama va detrás, lee con `git show origin/main:<ruta>`: este repo ya tomó código viejo por vigente. Si el `fetch` falla, dilo en la primera línea.
2. `./scripts/sesiones.sh` y `git log --all --oneline -20`: ¿otra sesión toca esa pantalla? Dilo en la primera línea; sus tareas pueden chocar.
3. ¿Ya existe `docs/pantallas/<slug>.md`? Es un re-análisis: léelo. Antes, `git diff --stat <SHA del encabezado> origin/main -- <archivos de la pantalla>`: si cambiaron, el análisis previo está **vencido** y no se toma como base. Lee también las auditorías fechadas que ya haya (`docs/auditoria-*-2026-*.md`, p. ej. dashboard, planilla, info) y `docs/hallazgos-abiertos.md`: no re-levantes lo ya medido ni lo ya descartado.
4. Declara en pocas líneas: tipo de pantalla (terminal, panel, «Lo mío», reporte, configuración); **dispositivo que se juzga** (terminal = Mac mini a pantalla completa en la sede; «Lo mío» = celular de la integrante; panel = escritorio de la líder o de DO); rol y sede con que se ve; **finalidad** ("esta pantalla existe para X").
   La finalidad sale de `CLAUDE.md`, `docs/estado.md`, `apps/web/app/(admin)/admin/nav-items.ts` y el comentario de cabecera del `page.tsx`, **nunca de la captura**. Si docs y pantalla no coinciden, eso ya es hallazgo.

## Paso 1 — Mapa del código

Delega la lectura a un subagente `Explore` para no llenar la conversación; que devuelva un mapa con `archivo:línea`. Cadena a trazar: `page.tsx` → componentes (`components/ui/*`, `components/nav/*`) → `lib/` → `supabase.rpc(...)`/`.from(...)` → función `fn_*` → RLS. Para cada `fn_*` que toque plata o asistencia: `./scripts/donde-vive.sh fn_x` (la versión vigente, no la primera que salga en `grep`).
Anota además, siempre: si el `page.tsx` es `"use client"`, cuántas líneas tiene, cuántos `useEffect` piden datos, si hay `loading.tsx`/`error.tsx` en su segmento, si carga modales con `next/dynamic`.

## Paso 2 — Consulta SQL (completo)

Lee `plantilla-sql.md`, arma la consulta, **pruébala antes en el Postgres local** (`docker exec supabase_db_cayla-dynamic psql -U postgres …`), **entrégala y detente**. Felipe la corre en el SQL Editor de producción y pega el JSON. Si el mensaje ya trae resultados o dice "sin SQL", sigue y marca lo que quede sin datos reales. **Nunca asumas que lo que ves en local es lo que pasa en producción**; si se contradicen, gana producción.

## Paso 3 — Las seis dimensiones

Cada una con puntaje 0–10 y cada afirmación con su etiqueta: `[visto]` captura/navegador · `[código archivo:línea]` · `[producción]` · `[inferido]` · `[no verificable]`. Nunca mezcles lo visto con lo supuesto.

1. **Estética**, cuatro capas en este orden. (a) Coherencia con Dynamic: los trece `--color-*` y los radios/z-index de `globals.css`; nunca un color Tailwind por defecto (la excepción es `bg-black/NN` como velo de modal y la vista previa de firma); documentos `.hoja` siguen el tema en pantalla y se fuerzan claros solo al imprimir; primitivos de `components/ui/` (`Boton`, `Tabla`, `Insignia`, `Modal`, `CabeceraPagina`…) en vez de clases copiadas; compárala con 2–3 pantallas hermanas. (b) Marca y tono: español, vocabulario de la casa (integrante, líder de equipo, sede; nunca empleado/jefe/sucursal/RRHH). (c) Heurísticas universales: Nielsen; WCAG (contraste ≥4.5:1, objetivo táctil ≥44 px, foco — ya hay un `:focus-visible` global en `globals.css`, así que solo es hallazgo si una pantalla lo anula). (d) **Movimiento y feedback**: ¿el sistema responde en <100 ms a un toque?, ¿hay estado de carga/vacío/error distinto?, ¿las animaciones usan los `@keyframes` y `ease-salida` del sistema y respetan `prefers-reduced-motion`?
2. **Lógica de negocio**: contra `CLAUDE.md` (marcajes append-only, «Dynamic avisa, nunca sanciona», «los falsos positivos son el peor error», exclusiones antes de contar), `docs/planilla-anexo-tecnico.md` si toca planilla, y `docs/estado.md` para decisiones recientes. Cada hallazgo cita la regla que viola; si ninguna regla escrita cubre el punto, dilo ("ninguna decisión escrita cubre esto") en vez de inventarla. Cuestiona cómo lo hacen Workday/Oracle HCM/BambooHR/Odoo (ver `docs/comparacion-workday-oracle-dynamic-2026-09-02.md`), **con filtro obligatorio: ¿le sirve a ~30 personas y 4 sedes hoy?** Si no, va a "Futuro" y no cuenta entre las 12. Lo que viene de memoria se marca no verificado.
3. **Arquitectura y rendimiento**: cadena completa; estados imposibles (qué constraint impide el estado inválido); dónde empieza y termina la transacción; concurrencia (dos líderes, el mismo registro, el mismo milisegundo); caída externa con una frase escrita: «se degrada así, no pierde este dato»; **volumen con números** (filas en 3 años, consultas por minuto con N pestañas abiertas) — sin número no hay opinión de rendimiento. Rendimiento percibido: Server vs Client Component, cascada de peticiones (sesión → datos), tamaño del archivo, `loading.tsx`, carga diferida. Suma los lentes que la pantalla pida (RLS, datos personales, Ley peruana) y di por qué.
4. **Funciones**: las que existen y funcionan · las fantasma (botón o promesa sin lógica detrás) · las que faltan para cumplir la finalidad · las que sobran (antes de agregar, se borra).
5. **Utilidad (persona sin contexto)**: recorre un escenario real —una integrante que olvidó marcar la salida; una líder de sede que llega con 12 pendientes; Desarrollo Organizacional el día 28 cerrando planilla; una integrante nueva en su celular— y anota dónde duda o se equivoca. Si se equivoca, el fallo es del diseño, no de la capacitación. **El terminal marca SIN PIN a propósito (decisión de Felipe): no lo vuelvas a proponer.**
6. **Conexión con el sistema**: aguas arriba (de dónde vienen sus datos), aguas abajo (qué consume lo que crea: planilla, boleta, bandeja, anuncios, disciplina), módulos vecinos, y qué pasa si Supabase no responde.

**Dos puntajes:**
- **Cumple su finalidad** = promedio de las 6, con **tope 5 si hay un defecto que pueda pagar mal a una persona o acusar de falta a quien no debía** (un candado roto pesa más que cinco pantallas bonitas).
- **Relevancia** = (2·Gestión + Dinero/obligación legal + Frecuencia + Qué se detiene) / 5, cada criterio de 0 a 10 con una línea de justificación. Categoría: ≥8 **Núcleo** · 6–7.9 **Soporte** · 4–5.9 **Comodidad** · <4 **Prescindible**.

## Paso 4 — Las 12 tareas

Siempre 12. Tipos: **Reconstruir · Corregir · Mejorar · Eliminar/fusionar/conectar · Replantear**. Orden por impacto + riesgo (lo que puede pagar mal o acusar mal, arriba), con dependencias marcadas. Las de bajo valor al final, rotuladas `bajo valor / opcional / futuro`.
Cada tarea: **dónde exactamente** (archivo:línea, tabla o RPC) · **por qué en ese puesto** · **cómo lo verificas tú** (algo observable en el navegador o con una consulta, no "compila") · **esfuerzo** (S/M/L) · **dependencias**.
Las estructurales (Reconstruir, Replantear) llevan además `DECIDÍ:` · `DESCARTÉ:` la alternativa real con su costo · `SE ROMPE SI:` un escenario específico (jamás "hay que pensar en escalabilidad").
**Replantear:** si existe una estrategia que apoye mejor la gestión que la pantalla tal como está pensada, va aparte como "Estrategia alternativa" con Ganas/Pagas, y una de las 12 pide a Felipe que decida. No reordenes las 12 ni la des por decidida.
**Si las tareas tocan SQL de plata**, recuerda en la tarea las reglas de la casa: md5 de producción antes de escribir y antes de entregar, auditoría empírica en `BEGIN … ROLLBACK`, y que la migración se pega ANTES de fusionar.

## Paso 5 — Actitud, salida y sincronía

- **Objeción primero:** lo peor arriba, sin cortesía; "sin objeción" solo si es cierto. Luego **"Lo que está bien y no se toca"** con evidencia. Cierra con **"Fuera de esta pantalla"**: la única cosa de mayor consecuencia que Felipe no preguntó.
- **Privacidad:** todo dato personal de la captura o del SQL (nombres, DNI, correos, sueldos por persona, fechas de ingreso) se escribe a disco como `[integrante]`, `[DNI]`, `[monto]`. `docs/pantallas/` va a git y el historial no se borra.
- **Salida:** todo va a `docs/pantallas/<slug>.md` (slug = ruta sin barras, ej. `admin-horas`) con `plantilla-analisis.md`. Al chat solo llegan: veredicto en 2 líneas, los dos puntajes, las 3 primeras tareas y el enlace.
- **Contra análisis previos:** el mismo defecto en 3 o más pantallas es **una** tarea raíz, no tres. Dos pantallas que resuelven lo mismo de dos formas: una está mal, dilo aunque las dos funcionen.
- **`estado.md` y `hallazgos-abiertos.md`:** no los edites (otras sesiones los tocan; en Dynamic, `estado.md` es el único archivo de estado). Deja al final del análisis "Líneas propuestas para hallazgos-abiertos.md", una por tarea con `[pantalla:<slug>]`; Felipe aprueba antes de anexarlas.
- **Commit:** el análisis es trabajo que solo existe mientras nadie mueva el árbol. Sugiere commitearlo con `git commit -o docs/pantallas/<slug>.md` — pero commitear es decisión de Felipe.

## Modo rápido

Sin SQL, sin referentes de ERP, sin inventario ni subagente. Lee `page.tsx`, los componentes principales y su `lib/`. Las 6 dimensiones en 1–2 líneas, los dos puntajes, las 12 tareas en una línea cada una. Marca el archivo `rápido`: en el historial esa fila no es comparable con las de modo completo.
