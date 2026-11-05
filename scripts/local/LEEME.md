# Dynamic en tu computadora, sin Docker

Levanta Dynamic con **login real y datos inventados**. Nada de aquí toca producción, ni Docker, ni las bases que comparten los otros worktrees. **Nunca se copia producción aquí**: tiene DNI, sueldos y firmas reales.

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

## Otras órdenes

```bash
./scripts/local/apagar.sh                # apaga; los datos se quedan
./scripts/local/crear-base.sh --de-cero  # borra y rehace la base con todas las migraciones de este worktree
```

**`--de-cero` borra la base que usan todos los worktrees de este clon:** no lo corras si otra sesión la está usando. La base vive en `$(git rev-parse --git-common-dir)/entorno-local`, así que no aparece en `git status` ni puede subirse por accidente.

## Qué es de verdad y qué no

| Pieza | Puerto | Qué es |
|---|---|---|
| Base de datos | 55890 | Postgres 17 de Homebrew, con **todas las migraciones reales** y sus reglas y permisos |
| API | 55891 | PostgREST, el mismo de producción |
| Puerta | 55892 | `puerta.mjs`: reemplaza a Kong y a GoTrue. Comprueba la clave contra `auth.users` igual que GoTrue |

**Lo que no reproduce:**

- **Correo:** «Olvidé mi clave» responde bien, pero el correo no sale.
- **Fotos y PDF:** no hay almacenamiento. Subir o abrir un archivo da error, y eso incluye el PDF de las boletas.
- **Tareas programadas:** `pg_cron` queda registrado, pero no corre nunca.
- **Tiempo real:** las pantallas que dependen de él no se actualizan solas.
- Un defecto que dependa del GoTrue de verdad no aparece aquí.

Para esos casos sigue estando `supabase start`, que necesita Docker.

## Trampas medidas

- **El lanzador tiene que ser Node, no bash:** el panel corre el programa como proceso propio, y el bash de Homebrew se queda colgado para siempre esperando un permiso de macOS para leer el disco externo (`sample` lo mostró detenido en `getcwd`).
- **Clave fuerte:** las cuentas con poder pasan a «Nueva clave» si la clave no cumple la regla, por eso la de prueba no lleva el nombre de la empresa.
- **Migraciones nuevas:** si un worktree trae migraciones que la base no tiene, `arrancar.sh` lo avisa y no las aplica solo.
- **Estilos:** si un cambio en `globals.css` no llega al navegador, reinicia el servidor. Pasó el 2026-11-05 con el servidor corriendo desde el disco externo.
