# CAYLA Dynamic — cómo se trabaja en este repo

App de asistencia y planilla de CAYLA. Cuatro sedes — **Central (CCO)** ·
**Taller LIM** · **Tienda AQP** · **Tienda TRU** — y ~30 personas entre activas e
inactivas. En producción y en uso real todos los días: **cayla-dynamic.vercel.app**.

Ojo con `docs/plan.md` y con cualquier texto viejo que hable de "3 sedes": el
plan original era TRU/LIM/AQP y Central se sumó después. Central no es tienda:
ahí están administración y Desarrollo Organizacional.

Lo que registra este sistema **alimenta el pago**. Un error acá no es un bug de
pantalla: es plata mal pagada a una persona real. Ese es el criterio que ordena
todas las reglas de abajo.

> Este archivo dice **cómo se trabaja**. Para saber **dónde estamos hoy**,
> lee [`docs/estado.md`](docs/estado.md) — es el único archivo de estado.

---

## Reglas de trabajo (no negociables)

**SQL a producción lo aplica Felipe a mano.**
No hay despliegue automático de migraciones. La clave de servicio está rotada a
propósito: ningún script corre contra producción. El flujo es:
la migración se escribe en `supabase/migrations/00NN_*.sql`, y Felipe la pega en
el **SQL Editor de Supabase**. Cuando hace falta una versión lista para pegar,
vive en `scripts/sql-manual/aplicar_00NN.sql`.

**El SQL se pide con el script, no se abre el archivo:**

```bash
./scripts/que-falta-pegar.sh     # genera la consulta de qué falta en producción
./scripts/dame-el-sql.sh 173     # entrega esa migración, si está a salvo
```

`dame-el-sql.sh` se niega a darte el archivo si no está en git, si tiene cambios
sin commitear o si no está en GitHub byte por byte; si está a salvo, te lo deja
en el portapapeles. Existe porque el 2026-08-07 se descubrió que la **0177 —que
cambia cómo se pagan las vacaciones— estaba aplicada en producción y su único
ejemplar era un archivo sin commitear en esta Mac**. Ninguno de los otros frenos
lo veía: `desplegar.sh` cuida el camino de Vercel, y el SQL va por otro camino.

**El md5 de una función se pide a PRODUCCIÓN, no se copia del local.** Cuando
una migración reescribe una función y su encabezado declara «md5 de partida: X»,
ese X tiene que venir del SQL Editor. El 2026-08-08 se declaró el md5 local en la
0185 y costó una hora de falsa alarma: producción devolvía otro porque `pbcopy`
había roto los acentos al copiar (locale `LC_CTYPE=C` → MacRoman), y el texto
llegó como «Solo un administrador o l√≠der». El SQL corre igual, así que nada
falla — solo se vuelve ilegible, y estas migraciones se leen. Ya está arreglado
en el script, que ahora compara el portapapeles byte por byte y se niega si no
coincide; la regla de método queda igual.

Y cuando dos md5 no coinciden: **medir dónde está la diferencia** —posiciones de
marcadores dentro del `prosrc`, `octet_length` contra `length`, un `substring`
del principio— en vez de proponer explicaciones. Ese día se probaron tres
hipótesis falsas antes de que el primer `substring` lo resolviera de un vistazo.

**Antes de dar cualquier SQL que toque plata, se audita empíricamente.**
Contra el Postgres local, dentro de `BEGIN … ROLLBACK`, con casos reales. No se
entrega un cálculo de planilla, provisiones, bonos o CTS "revisado a ojo".

**Desplegar a producción se pregunta SIEMPRE.**
```bash
npx vercel --prod --yes    # solo con OK explícito de Felipe
```
Vista previa sin permiso: `npx vercel --yes`.

**Ojo con el entorno.** El panel apunta al Supabase **local** (127.0.0.1), no a
producción. Para diagnosticar prod, Felipe corre SELECTs en el SQL Editor. Nunca
asumir que lo que se ve en local es lo que pasa en prod.

⚠️ **Y ese `.env.local` HOY NO EXISTE.** Este archivo decía que vivía en
`apps/web/.env.local`; ahí no hay nada, y el de la raíz solo trae un token de
Vercel, sin las claves de Supabase. Un clon nuevo **no puede levantar el panel**:
cualquier pantalla revienta al renderizar con «supabaseUrl is required», y no se
nota que es el entorno porque el síntoma parece un error de la pantalla. Se
resuelve creando `apps/web/.env.local` con `NEXT_PUBLIC_SUPABASE_URL` y
`NEXT_PUBLIC_SUPABASE_ANON_KEY` de `npx supabase status` — y para eso hace falta
que la pila entera esté arriba (`npx supabase start`), no solo Postgres:
`npx supabase db start` levanta la base pero **no la API**, y sin API el
navegador no tiene con quién hablar.

**Desplegar desde un worktree crea un proyecto de Vercel NUEVO.** `.vercel` está
en `.gitignore`, así que un worktree no hereda el enlace y el CLI se inventa un
proyecto con el nombre de la carpeta. El 2026-08-10 eso mandó un despliegue a un
proyecto vacío llamado `tardanzas-memos-issue-7f4e44`: falló por no tener
variables de entorno, y si hubiera compilado habría publicado la app en una URL
que nadie mira mientras alguien anunciaba «desplegado». Antes de desplegar desde
un worktree: `cp ../../.vercel/project.json .vercel/` y comprobar con
`npx vercel env ls` que salen las variables de **cayla-dynamic**.

**Datos personales fuera de git.** Correos, DNI, sueldos por persona y fechas de
ingreso reales no se commitean. Hay dos scripts explícitamente ignorados en
`.gitignore` por eso (`aplicar_0031`, `aplicar_0033`). Antes de subir cualquier
script nuevo, revisar que no lleve PII.

---

## Idioma y vocabulario

Todo en español: pantallas, mensajes de error, comentarios de negocio, nombres de
migraciones. Los nombres de variables y funciones siguen la convención en inglés.

| Se dice | Nunca |
|---|---|
| integrante, colaboradora | empleado |
| líder de equipo, encargada de sede | jefe, supervisor |
| sede, tienda, boutique | sucursal |
| Desarrollo Organizacional (DO) | RRHH |
| clienta | cliente (para quien compra) |

El código tiene el rol `supervisor_sede` en la base por historia; en pantalla y en
prosa siempre es **encargada**.

---

## Cómo está hecho

```
apps/web/            Next.js — un solo despliegue, dos superficies:
  app/(terminal)/      terminal de marcaje de cada sede (Mac mini a pantalla completa)
  app/(admin)/         panel de administración (24 pantallas)
  app/api/             4 rutas de servidor (espejo, admin, reabrir-día, sentry)
packages/shared/     las reglas que NO son de una pantalla (ver abajo)
packages/database/   tipos generados de Supabase + cliente tipado
supabase/migrations/ el esquema, una migración por cambio
scripts/sql-manual/  la versión lista para pegar en el SQL Editor
docs/                referencia (ver abajo)
```

Backend: **Supabase** (Postgres + Auth + RLS + pg_cron). Hosting: **Vercel**.
Monorepo con pnpm + Turborepo.

**Qué va en `packages/shared` y qué no.** Va lo que dos pantallas podrían
necesitar responder igual: quién puede qué (`permisos.ts`, `escalafon.ts`),
cuándo es hoy en Perú (`fecha-lima.ts`), los catálogos y sus etiquetas
(`enums.ts`, `labels.ts`), la máquina de estados del marcaje. No va nada que
toque el navegador, Supabase ni React — por eso se puede probar con `vitest` sin
levantar nada.

Tres reglas que se ganaron a golpes (agosto 2026, tras juntar 35 copias de la
misma condición de permiso y 32 del huso horario de Lima):

1. **Nunca comparar `rol` contra un string literal fuera de `permisos.ts`.** Si
   hace falta un permiso nuevo, se agrega una función ahí y se usa. Un
   `rol === "admin"` suelto en una pantalla es un permiso que nadie va a
   encontrar el día que haya que cambiarlo.
2. **Nunca escribir `"America/Lima"` fuera de `fecha-lima.ts`.** El corte del día
   decide a qué fecha se le paga un marcaje; no puede tener dos versiones.
3. **Nunca una lista escrita a mano de algo que vive en una tabla.** Aquí hubo un
   `SEDES = ["TRU","LIM","AQP"]` que se volvió falso cuando abrió Central. Si el
   dato se gestiona desde una pantalla, se lee de la base — y si de verdad hace
   falta una constante para pintar un desplegable, se dice en un comentario que
   la verdad está en la tabla (ver `REGIMENES_PENSION`).

```bash
npx pnpm install
npx pnpm dev          # levanta todo
npx pnpm typecheck
npx pnpm test         # vitest
```

---

## Antes de reescribir una función SQL

**Nunca copies el cuerpo de una función sin preguntar cuál es la versión vigente:**

```bash
./scripts/donde-vive.sh fn_planilla_calcular
```

Dice en qué migraciones está definida, cuál es la última —la única de la que se
puede copiar—, si alguien la borró después y ya no existe, y si el Postgres
local coincide con ella.

Hace falta porque un `grep` normal miente. La 0081 escribe
`CREATE OR REPLACE FUNCTION public.fn_…` en mayúsculas y con prefijo, mientras
otras la escriben en minúsculas y sin él: buscar a mano encuentra unas
definiciones y se salta otras. `fn_planilla_calcular` tiene **23 versiones**
repartidas y pesa 37.000 caracteres.

Y hay una segunda forma de definir, la que usan las funciones que devuelven
`TABLE`: como Postgres no deja agregarles una columna con `create or replace`,
la migración hace `drop function …` y a continuación `create function …`. La
0161 lo hace con `fn_documentos_tablero`; el script lo cuenta como definición
igual que un `create or replace`.

El 2026-08-05 esto casi mete a producción una migración copiada de la 0017
creyéndola la última —era la 0081, 64 migraciones después— que habría revertido
en silencio toda la lógica de marcas anuladas. Lo cazaron dos pruebas por azar.

## Convención de migraciones

- Un archivo por cambio, numerado correlativo: `00NN_descripcion_en_espanol.sql`.
- **Encabezado obligatorio en comentario**: qué promete, qué asume, por qué se
  eligió así, y cómo se revierte. Las migraciones de este repo se leen como
  documentación del negocio — mantener ese estándar (ver `0073` y `0076` como
  referencia de la forma).
- **Idempotentes** siempre que se pueda: se pegan a mano, y una mano se equivoca.
- Nada de `drop` de datos. Las personas nunca se borran, se marcan inactivas —
  su historial sostiene los reportes de periodos pasados.
- **Numeración sin huecos.** Un hueco significa que algo se aplicó en producción
  sin quedar en el repo. Si tienes que saltarte un número, documenta por qué.

---

## Principios del sistema (por qué está hecho así)

**Los marcajes son la fuente de verdad, y son append-only.**
`jornadas` es un resumen derivado que mantiene un trigger. Nunca se corrige una
jornada por debajo: se corrige el marcaje y la jornada se recalcula. Toda edición
manual deja rastro en `correcciones_auditoria` con motivo obligatorio.

**Toda escritura de marcaje pasa por `fn_registrar_marcaje`.** Nunca un insert
directo desde el cliente. Ahí vive la lógica de "¿esto es entrada o salida?" y la
reconciliación de marcajes offline que llegan tarde.

**El doble marcado se previene por diseño, no por validación.** El terminal nunca
deja elegir "entrada" o "salida": lo decide el estado abierto de esa persona. Un
`if` que detecta duplicados sería la señal de que el diseño falló.

**Dynamic avisa, nunca sanciona solo.** Tardanzas y faltas se detectan, se cuentan
y se documentan; la decisión de conversar o amonestar es siempre de una persona.
Esto no es una preferencia de producto: la ley peruana (D.S. 003-97-TR art. 25)
exige reiteración y sanciones progresivas documentadas. El sistema arma el
expediente; nunca dice "despide".

**Los falsos positivos son el peor error.** Acusar de falta a quien no debía
cuesta más que dejar pasar una falta real. Por eso las exclusiones
(`en_planilla`, `sueldo_fijo`, vacaciones, feriados, sin horario) se aplican antes
de contar, no después.

**Guards `SECURITY DEFINER` null-safe.** Siempre `if fn_es_admin_o_lider() is not true`,
nunca `if not fn_es_admin_o_lider()` — un `null` no debe pasar como autorizado.
Desde la 0078 los booleanos de permiso ya no devuelven `null`, pero la forma
`is not true` sigue siendo la obligatoria: cualquier condición que compare un
UUID contra `fn_persona_actual_id()` vuelve a producir `null` por su cuenta.

**El terminal marca SIN PIN, y es a propósito** (decisión de Felipe, jul-2026).
Se prioriza que marcar sea instantáneo; el control real es que la Mac mini está
a la vista de todo el equipo, no una clave. Esto significa que el sistema **no
garantiza** que una marca la hizo la persona a la que pertenece: no se puede usar
una marca como prueba individual en un procedimiento disciplinario sin otro
respaldo. No volver a proponer el PIN salvo que Felipe lo pida.

**Reglas de planilla ya decididas, no se reabren:** régimen MYPE pequeña empresa,
base de 6.5 h, pago = salario × horas / (6.5 × días). Los factores de provisiones
(grati 8.33 % · CTS 4.17 % · vacaciones 4.17 %) viven en
`configuracion.planilla_provisiones`.

**Antes de tocar cualquier cálculo de planilla, lee
[`docs/planilla-anexo-tecnico.md`](docs/planilla-anexo-tecnico.md).** No es documentación
de cortesía: tiene una tabla de **cinco defectos que parecen reales y no lo son**
—el factor 6.5, el "efecto calendario", el riesgo de RMV, el prorrateo del
feriado, el promedio de días trabajados— cada uno con la medición que lo
descarta. En agosto de 2026 una sesión los persiguió durante horas y estuvo a
punto de subir la planilla 1.11 % corrigiendo algo que funcionaba.

Tres cosas de ahí que ahorran el mismo camino:

- **El periodo va del 29 al 28**, no es mes calendario. Leerlo de
  `periodos_planilla`, nunca asumirlo.
- **En Trujillo se trabaja domingo.** Cualquier consulta que asuma «lunes a
  sábado» da resultados falsos para esa sede.
- **La jornada son 45 h/semana contra un máximo legal de 48.** Se cumple en tres
  regímenes distintos (6 días en TRU, 5 en LIM y AQP) que suman lo mismo; un
  promedio que los mezcle no significa nada.

Y la regla de método que costó esas horas: **medir contra la base antes de
proponer**, no razonar sobre el supuesto anterior. La «base» incluye los
documentos de este repo: el 2026-08-08 se presentó como descuido algo que
`docs/analisis-estructura-remunerativa-2026-07-30.md` ya tenía decidido con el
contador y con su exposición cuantificada.

**El sobretiempo se paga solo desde la 0185, y se mide contra 48 h SEMANALES.**
Nunca contra 8 h diarias: el art. 25 de la Constitución dice «ocho horas diarias
O cuarenta y ocho semanales» y CAYLA pactó la semanal. Medido por día, el taller
de Lima (5 días de 9 h = 45 h) generaría sobretiempo todas las semanas haciendo
tres horas menos que el máximo legal.

- **«Semana» es un ciclo de siete días, no lunes a domingo.** Criterio vinculante
  del Informe 027-2021-MTPE/14. El ciclo empieza tras un descanso y se corta a
  los 7 días; sin ese corte, doce días seguidos de 8 h darían 48 h de exceso en
  vez de 8.
- **Los ciclos no se solapan.** La alerta de Incidencias sí usa ventana móvil,
  porque ahí el objetivo es no perderse ningún tramo cargado. En el pago, una
  ventana móvil pagaría la misma hora siete veces.
- **Se paga el RECARGO (25 % / 35 %), no la hora completa** — ya está en
  `pago_base`. Es el error que la 0173 corrigió con el feriado del sueldo fijo.
- **Tres exclusiones distintas, y no se funden:** RxH (no tiene jornada),
  `personal_direccion` (art. 5 del D.S. 007-2002-TR, columna propia desde la
  0187) y `sueldo_fijo` (su pago no depende de horas). Deducir dirección del rol
  del sistema le quitaría el derecho a quien reciba admin para otra cosa.

**El feriado y el sobretiempo entran a la base de EsSalud y pensión (0193).** No
admiten discusión: el art. 19 del D.S. 001-97-TR no los lista como no
remunerativos y SUNAT les da código propio en la PLAME — 0105, 0106 y 0107. Lo
que sí queda fuera, y es decisión sustentada, es el complemento variable y el
plus por objetivos; y la movilidad y la educación son no remunerativas por el
art. 19 e) y f).

- **Las sobretasas COMPLETAN una base declarada; no crean una donde no la hay.**
  Sin esa condición, a un RxH le aparecían S/41.39 de pensión de la nada y a un
  sueldo fijo S/46.45 — los dos tienen la básica en 0 a propósito.
- **La base se dice una sola vez** (`bri.base`, migración 0192). Antes estaba
  escrita literal en cinco sitios.
- **La vía legal para reducir el monto en origen no es dejar de declararlo:** es
  el descanso sustitutorio por feriado trabajado (art. 9, D. Leg. 713, quita la
  sobretasa del 100 %) y el acuerdo escrito de compensación del sobretiempo con
  descanso equivalente (art. 10 del TUO, dentro del mes calendario siguiente).

---

## Qué hay en `docs/`

| Ruta | Qué es |
|---|---|
| `estado.md` | **Dónde estamos hoy.** Se sobrescribe, no se acumula. |
| `terminales-mac-mini.md` | Manual para dejar la Mac mini de una sede como terminal. |
| `trabajar-en-dos-maquinas.md` | Ir y venir entre MacBook y Mac mini sin perder trabajo. |
| `disciplina-tardanzas-faltas/` | Marco legal peruano, plantillas de cartas, RIT. El `09` es el que se usa el día que alguien presenta un descargo. |
| `revision-2026-07-15/` | Auditoría de seguridad. Vive hasta cerrar sus pendientes. |
| `integracion-retail/` | Plan del puente con retail. Aún no arranca. |
| `plan.md` | **Documento histórico** (jul 2026, antes de construir). Buen contexto del porqué; su estructura de carpetas y su roadmap ya no describen el sistema actual. |
| `planilla-anexo-tecnico.md` | **Anexo técnico**, no es la política. Cómo se paga, de dónde sale el factor 6.5, cómo se paga un feriado, y una tabla de cinco defectos aparentes que ya se midieron y descartaron. **Leer antes de tocar cualquier cálculo de planilla.** ⚠️ La política salarial OFICIAL no vive acá: vive publicada en el sistema (migración 0141, pantalla `/admin/politica-salarial`), versionada y con acuse de recibo del equipo. |
| `analisis-estructura-remunerativa-2026-07-30.md` | **Informe fechado.** El sustento del diseño remunerativo, escrito para revisar con el contador. Rescatado de una rama antes de borrarla. |
| `plan-2026-07-25.md` | **Documento histórico.** Cuatro auditorías de código de julio. Se conserva por el registro, no por su lista de tareas. |

**No crear documentos de estado con fecha en el nombre.** Ese hábito produjo cinco
archivos que se contradecían entre sí. Si algo cambió, se edita `estado.md`.

---

## La red de seguridad (jul-2026)

**Antes de subir a GitHub** corre solo un hook (`scripts/hooks/pre-push`) que
verifica la **numeración**, el `typecheck` y las pruebas de interfaz. Si algo está
en rojo, el push no se hace. Toma unos 10 segundos.

**Y hay una cosa que ese hook arregla solo, en vez de pedírtela.** La consulta
`scripts/sql-manual/que_falta_pegar.sql` lleva dentro la lista de migraciones del
repo, así que cada migración nueva la deja corta. Si la encuentra vieja, **la
regenera, la commitea él** (solo esa ruta, con `git commit -o`, que es la forma
que no se lleva por delante lo que otra sesión tenga preparado en el índice) y
aborta pidiendo un segundo `git push` — git ya había decidido qué commits enviar
antes de llamar al hook, así que ese commit nuevo no viajaría en el primero.

Antes solo avisaba, y el 2026-08-08 frenó **cuatro** pushes en un día para pedir
siempre el mismo comando de una línea. Un guardián que te para para pedirte algo
que él mismo puede hacer enseña que sus avisos son trámite; el día que frene por
un número duplicado, ya le habrá enseñado a quien lo lee a usar `--no-verify`.

**Antes de crear una migración o una prueba, pregunta qué número toca:**

```bash
./scripts/siguiente-numero.sh
```

Mira las tres fuentes que hacen falta: todas las ramas, el directorio de trabajo
(lo que otra sesión escribió y aún no commiteó — el caso que más veces se coló) y
`migraciones_aplicadas` en la base local, que es donde aparece lo que alguien
aplicó a mano sin dejar archivo. El 2026-08-05 hubo tres colisiones en un día
porque la convención decía «mira `ls`», y `ls` solo ve la rama en la que estás.

La verificación de numeración (`scripts/hooks/numeracion.sh`) frena el push si dos
archivos de `supabase/migrations` o `supabase/tests` comparten número, o si un
número **nuevo** ya lo reclamó otra rama sin fusionar. Los huecos solo avisan: la
0031 y la 0033 faltan a propósito, viven fuera de git por datos personales.

El hook y el script son las dos mitades: el script te dice qué número tomar
**antes** de escribir; el hook te frena **después**, cuando el nombre ya está en
la cabecera, en los mensajes y en la prueba. Renumerar en ese punto es caro, y una
colisión que llega hasta ahí deja `supabase db reset` abortando con `duplicate key
value violates unique constraint "schema_migrations_pkey"` — no es desorden, es no
poder reconstruir el esquema.

Solo mira lo que el push agrega, y esa es la razón de que sirva: comparar el árbol
entero contra todas las ramas encuentra choques históricos de ramas abandonadas y
falla en cualquier push. Un freno que chilla siempre se desactiva a la semana.

Se eligió un hook local y **no** la protección de rama de GitHub porque esa
habría exigido abrir un pull request por cada cambio — fricción constante para
quien trabaja sola, a cambio de la misma garantía.

Para que el hook funcione en un clon nuevo hay que activarlo una vez:
```bash
git config core.hooksPath scripts/hooks
```

**Para desplegar**, en vez de `npx vercel` directo:
```bash
./scripts/desplegar.sh          # vista previa
./scripts/desplegar.sh prod     # producción, pregunta antes
```
Verifica que no haya cambios sin guardar, que GitHub esté al día, que las
pruebas de GitHub de ese commit hayan pasado —**incluidas las de base de datos
(pgTAP)**— y recién ahí publica. Para producción pide escribir `publicar` como
confirmación.

**Las pgTAP también corren en esta Mac**, y conviene correrlas antes de subir:
```bash
npx supabase db start    # levanta Postgres y aplica todas las migraciones
npx supabase test db     # 34 archivos, 302 pruebas, ~3 segundos
```
Ojo con el resumen: `Bad plan. You planned N tests but ran M` **no** es un error de
conteo, es un archivo que abortó a media ejecución — las pruebas que faltaron nunca
verificaron nada. Se lee igual de discreto que un descuido y no lo es.

Comprobado el 2026-08-04 con Docker Desktop 29.6.2 y Supabase CLI 2.109.1. El
`db start` es además la mejor verificación de una migración nueva: aplica el
esquema entero desde cero, así que un error de sintaxis o una dependencia rota
salta ahí y no en producción. (Este archivo decía lo contrario —«no corren en
esta Mac porque necesitan Docker»— y era falso.)

En una urgencia real ambos se saltan: `git push --no-verify` y `npx vercel --prod`.
Que se pueda saltar a propósito es parte del diseño; que se salte sin querer, no.
