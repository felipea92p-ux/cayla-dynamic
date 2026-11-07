# Dynamic en tu computadora, sin Docker

Levanta Dynamic con **login real y datos inventados**. Nada de aquí toca producción ni las bases que comparten los otros worktrees. Docker solo se usa para el tiempo real, y es opcional: ver [Tiempo real](#tiempo-real). **Nunca se copia producción aquí**: tiene DNI, sueldos y firmas reales.

## Encender

```bash
node scripts/local/web.mjs
```

La primera vez crea la base (unos 40 segundos). Después abre <http://localhost:3000>. Desde el panel de Claude es la entrada `dynamic-local` de `.claude/launch.json`.

Clave de todas las cuentas: `Colibri-Local-2026`.

| Cuenta | Quién es | Para qué sirve |
|---|---|---|
| `admin@dynamic.local` | Administradora, en Central | El menú completo |
| `do@dynamic.local` | Líder de Desarrollo Organizacional | Personas, documentos, pago |
| `lider@dynamic.local` | Líder de equipo, Tienda TRU | Lo que ve una tienda |
| `lider.aqp@dynamic.local` · `lider.lim@dynamic.local` | Líder de equipo de AQP y del Taller | Otras sedes |
| `integrante@dynamic.local` | Ana, con contrato, memo y bono firmados | «Lo mío» con datos |
| `nombre.largo@dynamic.local` | El nombre más largo posible | Lo que rompe tablas y fichas |
| `sin.datos@dynamic.local` | Recién entró: sin horario, sin marcas ni sueldo | Los estados vacíos |
| `de.baja@dynamic.local` | De baja | El ingreso tiene que rechazarla |
| `terminal-tru@dynamic.local` (también `-lim`, `-aqp`, `-cco`) | La Mac mini de cada sede | El terminal de marcaje |

También hay personas sin cuenta: recibos por honorarios, practicante, preselección, vacaciones en curso y descanso médico. Los periodos incluyen un febrero, uno de 20 días (el mínimo que la base admite), dos pagados y el abierto. Cada vez que arranca se agregan las marcas de los días que falten, para que el Dashboard no se quede en el pasado.

Y dos personas que ya cesaron, para que Liquidaciones tenga un detalle con monto:

| Persona | Dónde sale | Para qué sirve |
|---|---|---|
| Filomena del Rosario Altamirano-Bustamante de la Cruz Zevallos | Pendientes, con monto | El nombre largo en la lista y el detalle por pagar |
| Olga Bustos Rivas | Pagadas | El detalle de una liquidación ya congelada |

Una cesada solo está en Pendientes 48 horas, así que al arrancar se mueve el cese de Filomena a hoy si ya se le acabó el plazo. Si la marcas como pagada para probar, se queda en Pagadas y `responsive:check liquidaciones` da ERROR hasta que la anules en la pantalla.

Lo que cambian en otras pantallas, medido el 2026-11-06 comparando el texto de las 52 pantallas sin parámetros, con la cuenta de admin (y 7 con la de líder de TRU). El periodo de marzo no es la vista por defecto de Planilla: se midió consultando el cálculo.

| Pantalla | Cambio |
|---|---|
| Equipo | «Ya no están» pasa de 1 a 3 (la líder de TRU ve de 0 a 1) |
| Liquidaciones | Una en Pendientes, una en Pagadas |
| Planilla, periodo abierto | Filomena aparece a S/ 0.00 y sin horas. 22 → 23 personas, «Planilla» 19 → 20. El total a pagar no cambia; el EsSalud sube S/ 110.70, porque su piso no se prorratea (0116) |
| Planilla, periodo del 1 al 20 de marzo | Olga aparece igual, con S/ 101.70 de EsSalud |

Ni el Dashboard, ni la Bandeja, ni Provisiones cambian. Si el cese de Filomena se vence sin que nadie arranque, además sale en la Bandeja como vencida. Ninguna prueba depende de estos datos: las pgTAP y `vitest` traen los suyos.

## Otras órdenes

```bash
./scripts/local/apagar.sh                # apaga (también el tiempo real); los datos se quedan
./scripts/local/tiempo-real.sh           # enciende solo el tiempo real, si el resto ya está encendido
./scripts/local/crear-base.sh --de-cero  # borra y rehace la base con todas las migraciones de este worktree
node scripts/local/sembrar.mjs --solo-ceses  # agrega a las dos cesadas a una base que ya existe; no borra nada y se puede repetir
```

`arrancar.sh` ya corre `--solo-ceses`, así que normalmente no hace falta pedirlo.

`arrancar.sh` también corre `--solo-seguros`: si la base no tiene ninguna póliza, siembra una Vida Ley colectiva que vence en 20 días y una póliza FOLA, y deja a una persona de planilla sin Vida Ley. No toca una base que ya tenga pólizas.

**`--de-cero` borra la base que usan todos los worktrees de este clon:** no lo corras si otra sesión la está usando. La base vive en `$(git rev-parse --git-common-dir)/entorno-local`, así que no aparece en `git status` ni puede subirse por accidente.

## Qué es de verdad y qué no

| Pieza | Puerto | Qué es |
|---|---|---|
| Base de datos | 55890 | Postgres 17 de Homebrew, con **todas las migraciones reales** y sus reglas y permisos |
| API | 55891 | PostgREST, el mismo de producción |
| Puerta | 55892 | `puerta.mjs`: reemplaza a Kong y a GoTrue. Comprueba la clave contra `auth.users` igual que GoTrue. Reenvía el websocket `/realtime/v1/` |
| Tiempo real | 55893 | El Realtime de Supabase **de verdad** (`realtime:v2.124.2`, la de la CLI de CI), en Docker, conectado a esta base. Opcional |

**Lo que no reproduce:**

- **Correo:** «Olvidé mi clave» responde bien, pero el correo no sale.
- **Fotos y PDF:** no hay almacenamiento. Subir o abrir un archivo da error, y eso incluye el PDF de las boletas.
- **Tareas programadas:** `pg_cron` queda registrado, pero no corre nunca.
- Un defecto que dependa del GoTrue de verdad no aparece aquí.

Para esos casos sigue estando `supabase start`, que necesita Docker.

## Tiempo real

Con **Docker prendido**, `arrancar.sh` levanta el Realtime de Supabase (`tiempo-real.sh`) y las pantallas se enteran de un cambio en unos 50 ms, igual que en producción (migración 0604). Para verlo, abre la misma pantalla en dos ventanas —por ejemplo Turnos como `admin@` y como `lider@`— y cambia algo en una.

**Sin Docker** no se rompe nada: la línea «Tiempo real: apagado» lo dice al encender, y las pantallas se ponen al día al volver a la pestaña y cada 5 min.

Lo que conviene saber:

- **La base tiene que haber arrancado con `wal_level=logical`.** Desde el 2026-11-07 las opciones de Postgres lo piden (`PG_OPCIONES` en `comun.sh`), pero solo valen desde el próximo arranque. Si tu base ya estaba encendida, `arrancar.sh` lo avisa: apágala y vuelve a encenderla **cuando nadie la esté usando**, porque es una sola para todos los worktrees.
- **Realtime entra como `supabase_admin`, no como `postgres`.** Lo que crea `postgres` nace sin permiso de ejecutar (la 0076), y entonces Realtime contesta «Unauthorized» a todo el mundo. Pasó la primera vez que se probó.
- **La política de la 0604 se pone al final.** La migración solo crea la política si `realtime.messages` existe, y esa tabla la crea Realtime la primera vez que arranca. `tiempo-real.sh` vuelve a correr la última migración que la define.
- Si algo falla: `docker logs dynamic-local-realtime-55893`.

## Una segunda instancia

La base es **una sola para todos los worktrees**. Si otra sesión la tiene abierta (`lsof -iTCP:55892 -sTCP:LISTEN` y mira de qué carpeta sale), no la apagues: levanta otra con su carpeta y sus puertos.

```bash
ENTORNO_LOCAL=/tmp/mi-entorno PUERTOS_LOCAL_DESDE=55990 PORT=3010 node scripts/local/web.mjs
```

Usa los puertos 55990 a 55993 y la app en el 3010. La primera vez crea su propia base desde cero con las migraciones de **tu** worktree. Para apagarla, las mismas dos variables delante de `./scripts/local/apagar.sh`.

## Trampas medidas

- **El lanzador tiene que ser Node, no bash:** el panel corre el programa como proceso propio, y el bash de Homebrew se queda colgado para siempre esperando un permiso de macOS para leer el disco externo (`sample` lo mostró detenido en `getcwd`).
- **Clave fuerte:** las cuentas con poder pasan a «Nueva clave» si la clave no cumple la regla, por eso la de prueba no lleva el nombre de la empresa.
- **Migraciones nuevas:** si un worktree trae migraciones que la base no tiene, `arrancar.sh` lo avisa y no las aplica solo.
- **Estilos:** si un cambio en `globals.css` no llega al navegador, reinicia el servidor. Pasó el 2026-11-05 con el servidor corriendo desde el disco externo.
