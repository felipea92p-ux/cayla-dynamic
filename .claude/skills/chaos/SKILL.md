---
name: chaos
description: Usa MAL Dynamic a propósito, pantalla por pantalla y en local, para encontrar lo que se rompe antes de que le pase a una integrante a la hora de marcar o a DO el día de cerrar el mes. Elige ataques de un catálogo de 9 familias (entradas hostiles, doble clic, navegación torcida, concurrencia, permisos, red y sesión, celular, teclado y fechas), los ejecuta en el navegador y en la base, y después de cada ataque que escribe mira las invariantes, porque lo grave no es la pantalla caída sino el descuadre que nadie ve. Entrega un informe ordenado por gravedad y, con el OK de Felipe, la prueba de regresión y el arreglo de una pantalla. Úsala cuando Felipe diga «chaos», «rómpelo», «qué pasa si lo usan mal», o antes de dar por terminada una pantalla que guarda.
---

> Adaptada de `chaos` de `cayla-retail` (2026-11-06). Lo que cambió: aquí el daño es plata mal pagada y marcas que no cuadran, no stock; las
> invariantes viven en `invariantes.sql` y están probadas con `autoprueba.sql`; el catálogo es `catalogo.md`; y la base es la de `scripts/local`, con
> datos inventados. No hay foto y restauración como en Retail: la base local se rehace de cero, y eso es lo que se usa al terminar.

Ataca esta pantalla, módulo o ruta: $ARGUMENTS

**Contrato.**
Promete: de UNA pantalla o módulo, un informe de lo que se rompe cuando se usa mal, con pasos para repetirlo y evidencia de la base, de lo peor a lo menos malo.
Asume: la base de `scripts/local` (puerto 55890), tu rama actual y las cuentas `@dynamic.local`.
No hace: tocar producción, aplicar migraciones, cambiar una regla de pago, asistencia, disciplina o permisos, ni arreglar nada antes de que Felipe lea el informe.

**Uso.** `/chaos /admin/horas` (una pantalla) · `/chaos asistencia` (un módulo, pantalla por pantalla) · `--familias doble-clic,concurrencia` (acota). Sin argumento: pregunta cuál y para.

**Por qué importa lo que mira.** Un ataque casi nunca tira la pantalla. Lo que deja es un estado que nadie ve: una marca sin jornada, dos liquidaciones vigentes, un movimiento después de pagar. «No se cayó» no prueba nada. Y aquí ese estado es plata mal pagada a una persona real.

## Candados (si uno falla, se para y se dice cuál)

1. **Solo local.** La web debe hablar con `scripts/local`, puertos 55890 a 55892. Nunca el conector de Supabase de producción ni ningún SQL contra producción.
2. **Datos inventados.** Solo las cuentas de `scripts/local/LEEME.md`. Nada de una copia de producción: tiene DNI, sueldos y firmas.
3. **La base es de todos los worktrees de este clon.** Un ataque desde el navegador guarda de verdad. Antes de empezar, mira si otra sesión la usa (Fase 0). `crear-base.sh --de-cero` borra lo de todas: solo si nadie más la usa.
4. **El repo es público.** Informes y capturas van al directorio de scratchpad de la sesión. **Un hallazgo de permisos o de seguridad nunca entra a un archivo versionado:** ni a un commit, ni a un PR, ni a `docs/`. Solo al chat.
5. **Nada hacia afuera sin OK:** ni publicar, ni abrir un PR, ni enviar un correo. `RESEND_API_KEY` no se configura en local.
6. **Los arreglos vienen después del informe**, y lo que toque plata, permisos, disciplina, funciones SQL o migraciones es de Felipe.

## Fase 0 — Terreno (si algo falla, para y dilo)

1. `git status --short` y `git rev-list --left-right --count HEAD...origin/main`: se ataca el código de tu rama, no el de producción. Dilo.
2. **La base local necesita Postgres 17 y PostgREST de Homebrew.** `ls /opt/homebrew/opt/postgresql@17/bin/psql`. Si no están, para y díselo a Felipe: no los instales por tu cuenta y no uses la base de Docker, que es compartida. Si están, `export PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH` para todo lo que sigue. Si el worktree no trae dependencias, `npx pnpm install`.
3. `preview_start` con `dynamic-local` (es `node scripts/local/web.mjs`). Abre una pestaña propia y pasa su `tabId` siempre. El panel debe estar visible (`tabs_context` no puede decir «hidden»): oculto, la página no dibuja nada.
4. **Nadie más escribe:**
   ```bash
   psql -h 127.0.0.1 -p 55890 -U postgres -d postgres -At -c "select count(*) from pg_stat_activity where datname = current_database() and pid <> pg_backend_pid() and state = 'active'"
   psql -h 127.0.0.1 -p 55890 -U postgres -d postgres -At -c "select max(server_received_at) from marcajes"
   ```
   Si lo último escrito tiene menos de 10 minutos, pregúntale a Felipe.
5. **El detector está vivo:** la autoprueba tiene que nombrar `INV-01` a `INV-07`, las siete. Si falta una, se arregla primero: un detector ciego da calma falsa.
   ```bash
   { cat .claude/skills/chaos/autoprueba.sql .claude/skills/chaos/invariantes.sql; echo 'rollback;'; } | psql -h 127.0.0.1 -p 55890 -U postgres -d postgres -At -F '|' | cut -d'|' -f1 | grep '^INV-' | sort -u
   ```
6. **Foto de partida:** guarda la salida de `invariantes.sql` en el scratchpad. Lo que ya estaba no es culpa de ningún ataque. Las invariantes se probaron con filas de prueba, no con los datos sembrados: si la foto trae violaciones, léelas antes de seguir, porque puede ser la invariante la que esté mal.
7. Un navegador comparte cookies entre pestañas: **un ataque de dos cuentas a la vez se hace en la base**, con dos `psql`, o se declara «no cubierto».

## Fase 1 — Ingredientes y plan

Lee la `page.tsx` y lo que usa, y declara los ingredientes de la pantalla:

| Ingrediente | Cómo lo reconoces |
|---|---|
| `texto` `numero` `monto` `documento` `fecha` `archivo` | qué campos tiene: montos con «S/», DNI, fechas, subida de fotos |
| `guarda` `pasos` `modal` `lista` | un botón que llama una RPC; un formulario por pasos; `<Modal>`; tablas |
| `marcaje` `planilla` `liquidacion` `firma` `disciplina` | toca `fn_registrar_marcaje`, periodos, pagos, contratos, memos. **Un fallo aquí es de gravedad 1** |
| `id-en-url` `sede` `rol` `celular` | `[id]` en la ruta; depende de la sede; cambia por rol; «Lo mío» se usa en teléfono |

Elige de `catalogo.md` los ataques de las familias que aplican: el **núcleo** corre siempre. Dile a Felipe en dos líneas la pantalla, los ingredientes y cuántos ataques son. Con más de 40, acota y avisa.

## Fase 2 — Los ataques

Por cada ataque, en orden:

1. **Anuncia** su `id` y qué vas a hacer, en una línea.
2. **Ejecútalo** en su capa:
   - `navegador`: `computer`, `find`, `form_input`, `read_page`, `javascript_tool`. Para el doble clic, `double_click` y, en ráfaga, `for (…) boton.click()` en el mismo tick. Para la red, parchea `window.fetch` y restáuralo. Para el celular, `resize_window` con `preset: "mobile"` y al terminar `"desktop"`. Mira `read_console_messages` y `read_network_requests`: un error crudo de Postgres a la vista es hallazgo.
   - `base`: `psql` directo, **dentro de `begin … rollback`** siempre que no necesites que dos sesiones se vean. Para concurrencia, dos `psql` en paralelo con `set local request.jwt.claim.sub`. Un script temporal va al scratchpad, nunca al repo.
   - `ambas`: primero lo que ve la persona, luego lo que quedó.
3. **Evidencia**, con etiqueta: `[visto]`, `[base]`, `[código archivo:línea]` o `[inferido]`. Nunca captures con la página a medio animar.
4. **Si el ataque escribió, mira la base ahora:** corre `invariantes.sql` y compáralo con la foto. Lo nuevo es lo que rompió el ataque. Una `sospecha` se confirma a mano antes de afirmarla: puede ser legítima.
5. **Clasifica** y sigue. No arregles nada, ni siquiera lo obvio. Como no se restaura entre ataques, usa otra persona o fecha en el siguiente para que no se contaminen.

## Gravedad (la decide la evidencia, no el ataque)

| | Qué es | Ejemplo |
|---|---|---|
| **1 · Estado imposible** | la base quedó inconsistente, o cambia lo que se paga | doble clic en pagar y hay dos filas; una marca que no llegó a la jornada |
| **2 · Dato malo en silencio** | se guardó algo dudoso y nadie avisó | «1,299.50» guardado como 1.29; una fecha corrida un día por el huso |
| **3 · Pantalla caída** | se rompe lo que se ve, la base queda bien | página en blanco al recargar; un 500 |
| **4 · Error feo pero seguro** | rechaza bien, con un mensaje que nadie entiende | «23502 null value in column» a la vista |

Un rechazo claro y sin nada escrito **no es hallazgo**: se anota como «resistió». **Un falso positivo contra una persona** (una falta que no fue) sube a gravedad 1: es el peor error del sistema.

## Fase 3 — Informe

En el chat, con copia en el scratchpad. Tres líneas de entrada: pantalla, rama y SHA, cuántos ataques y cuántos resistieron. Después, los hallazgos, **agrupados por causa**:

```
#N · [Gravedad 1–4] Módulo ▸ pantalla — ataques: DC-01, NAV-03
Qué pasó: una frase, con la medida.
Cómo repetirlo: pasos exactos.
Evidencia: [base] INV-01 … · [visto] captura H<N>_…
Dónde: `archivo` [probable] o `archivo:línea` [código].
Arreglo sugerido: una línea, sin aplicarlo. Si toca plata, permisos, disciplina o SQL: «es de Felipe».
```

Termina con **«No cubierto»**: lo que no se pudo correr y por qué (dos cuentas en un navegador, la Mac mini real, Safari), lo que los datos inventados no prueban, y que el informe vale para esta rama, no para producción. Y con la pregunta de cuáles arreglar.

## Fase 4 — Arreglos (solo con el OK de Felipe)

Cada hallazgo elegido, en su commit:
1. **Primero la prueba que falla:** `tests/*.test.ts` si es lógica pura, `supabase/tests/*.sql` si es de la base. El hallazgo se vuelve prueba o vuelve a ocurrir.
2. **Después el arreglo, de una pantalla**, con las piezas que ya existen. Si el arreglo está en una función SQL, una política o una regla de pago, se deja escrito y lo ordena Felipe (`/construir`, `/decide`).
3. **Repite el mismo ataque:** tiene que resistir.

## Fase 5 — Cierre

- Restablece lo que parchaste en el navegador (`fetch`, viewport).
- Si nadie más usa la base, `./scripts/local/crear-base.sh --de-cero` y déjala limpia. Si alguien la usa, di qué quedó escrito.
- Lo que veas de paso y no sea de la pantalla va como tarea aparte, no al código.

## Lo que esta skill no hace

No juzga si la pantalla se entiende (`/formidable`) ni su responsive (`responsive:check`). No prueba volumen. No es un escáner de seguridad: la familia `permisos` comprueba que los candados declarados aguantan, no busca vulnerabilidades nuevas.
