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

**El md5 de una función se pide a PRODUCCIÓN, no se copia del local, y se pide
ANTES DE ESCRIBIR, no antes de entregar.** Cuando una migración reescribe una
función y su encabezado declara «md5 de partida: X», ese X tiene que venir del
SQL Editor.

Lo de «antes de escribir» se aprendió el 2026-08-20 y costó una migración
entera. La 0276 se construyó sobre el cuerpo de la 0269 de
`fn_planilla_calcular` porque `donde-vive.sh` dijo que esa era la vigente —y lo
era, EN ESA RAMA— mientras otra sesión ya había fusionado la 0275 a `main` y
Felipe la había pegado. Pegar la 0276 habría devuelto a **S/ 0.00** el mes de
quien se toma sus vacaciones completas. Las dos herramientas de la casa miraron
el worktree y el worktree estaba incompleto; lo cazó el md5 de producción —90 707
caracteres allá contra 89 527 acá— cuando el trabajo ya estaba hecho, verificado
y commiteado. Pedirlo al principio cuesta un minuto; pedirlo al final cuesta
rehacerlo todo. Y ahora `scripts/hooks/main-tiene-migraciones-que-no-tienes.sh`
avisa además cuando `main` trae una migración que toca tus mismas funciones. El 2026-08-08 se declaró el md5 local en la
0185 y costó una hora de falsa alarma: producción devolvía otro porque `pbcopy`
había roto los acentos al copiar (locale `LC_CTYPE=C` → MacRoman), y el texto
llegó como «Solo un administrador o l√≠der». El SQL corre igual, así que nada
falla — solo se vuelve ilegible, y estas migraciones se leen. Ya está arreglado
en el script, que ahora compara el portapapeles byte por byte y se niega si no
coincide; la regla de método queda igual.

**Y en una sesión larga, el md5 se vuelve a pedir JUSTO ANTES DE ENTREGAR.**
Pedirlo una vez al principio no basta, y el 2026-08-25 costó una avería en
producción. La sesión preguntó el número libre y la versión vigente al empezar;
las dos herramientas contestaron bien —el árbol llegaba hasta la 0257— y sobre
esa respuesta se construyó la 0261 partiendo del cuerpo de la 0254. Mientras
tanto otra sesión fusionó **cuarenta y cuatro migraciones** al árbol compartido.
Al pegarla, `fn_planilla_calcular` volvió de 96 354 caracteres a 77 493:
revirtió la maternidad, el descanso médico, el descanso semanal trabajado y —la
peor— la **0275, «las vacaciones dejan de pagarse en cero»**.

El md5 SÍ se pidió, y coincidió. Ese es el detalle que enseña: coincidió porque
se preguntó al principio, y entre la pregunta y la pegada el árbol se movió. Un
md5 es una foto, no una garantía; caduca en cuanto alguien más trabaja.

Así que la regla se amplía: `donde-vive.sh` y el md5 de producción se vuelven a
consultar **en el mensaje en que se entrega el SQL**, no en el que se empieza a
escribirlo. Cuesta un minuto. La otra opción costó repegar la 0293 entera con la
planilla del mes a tres días de cerrar.

Y la señal que lo delata sin ninguna herramienta: la línea **PLANILLA** de
`que_falta_pegar.sql` dice qué versión de `fn_planilla_calcular` corre de verdad.
Si dice «se quedó en la 00NN», producción tiene una función más vieja que el
repositorio — mírala SIEMPRE después de pegar algo que la reescriba.

**Y el md5 de llegada se mide DESPUÉS de renumerar, nunca antes.** Cuando el
hook obliga a cambiar el número —pasa a menudo, con varias sesiones tomando
números a la vez— los marcadores «CAMBIO 00NN» del cuerpo cambian con él, y el
md5 cambia mientras la longitud NO, porque los dos números ocupan cuatro
caracteres. Eso produce la firma más desconcertante que hay acá: **misma
longitud, distinto hash**, que parece corrupción de acentos y no lo es. Pasó con
la 0286 el 2026-08-24, se documentó, y volvió a pasar con la 0289 al día
siguiente — porque lo escrito decía cómo reconocer el síntoma y no cuándo medir.
Si aparece igual, `position('CAMBIO 00NN' in prosrc)` contra producción lo
resuelve de un vistazo.

Y cuando dos md5 no coinciden: **medir dónde está la diferencia** —posiciones de
marcadores dentro del `prosrc`, `octet_length` contra `length`, un `substring`
del principio— en vez de proponer explicaciones. Ese día se probaron tres
hipótesis falsas antes de que el primer `substring` lo resolviera de un vistazo.

**Y hay una tercera causa benigna, además de los comentarios: pegar desde
Windows mete un `\r` por línea.** Pasó con la 0401 el 2026-09-08, la primera
que se pegó desde esa máquina. Las tres funciones que reescribía quedaron en
producción **más largas que el repositorio, cada una por exactamente su número
de saltos de línea** —+42, +68 y +119—, porque el camino entre el archivo y el
SQL Editor convirtió cada `\n` en `\r\n`.

La firma es inconfundible y se comprueba en una consulta:

```sql
select proname, length(prosrc) - length(replace(prosrc, chr(13), '')) as retornos
  from pg_proc where proname = 'fn_lo_que_sea';
```

Si eso da el número de líneas del cuerpo, es esto y **no hay nada roto**: un
`\r` antes de un salto de línea es espacio en blanco para PL/pgSQL, así que la
función se comporta igual. Se comprobó midiendo: el archivo y el Postgres local
coincidían byte por byte entre sí, y solo producción difería.

Lo que sí queda roto es hacia adelante: **el md5 de esas tres no va a volver a
coincidir nunca con el del repositorio.** Se decidió dejarlo (repegar desde el
mismo Windows probablemente reproduce el `\r`, y no arregla nada que esté mal)
y anotarlo acá, que es lo que evita que la próxima sesión pare en seco o —peor—
aprenda a ignorar un aviso de md5.

Y desde el 2026-10-13 `donde-vive.sh` imprime también las dos variantes con
`\r\n` —`crlf_tal_cual` y `crlf_sin_comentarios`— junto a las de siempre, y el
cuarto desenlace: coincide una variante CRLF → mismo código pegado desde
Windows; seguir, y declarar en la migración el md5 de PRODUCCIÓN. Se agregó
porque ese día, antes de pegar la 0518, `fn_documentos_tablero` devolvió en
producción `56aff7b1…` / `d138aae9…` —ninguno de los dos del script— y hubo que
demostrar a mano, con la 0492 dentro de `begin … rollback`, que era este caso y
no otra versión.

Distinguir esta causa de la grave importa: si la diferencia **no** cuadra con el
número de líneas ni con los comentarios, entonces sí es otra versión y hay que
parar. Ver también `docs/estado.md`, que documenta el CRLF en disco — es el
mismo origen, por otra vía.

**Y que no coincidan es LO NORMAL, no la excepción.** Medido el 2026-08-18 en el
SQL Editor: **119 de las 243 funciones de producción —el 49 %— no tienen ni una
línea de comentario**. Se pegaron sin ellos. Así que su md5 nunca va a ser el del
repositorio, y el síntoma es idéntico al del accidente grave: «producción tiene
otra versión».

Ese día se fue media hora en distinguirlos a mano con `fn_tardanzas_resumen`
(producción `49b3cf99…`, local `16f4991a…`). La respuesta era benigna: mismo
código, sin los comentarios — se comprobó quitándoselos al cuerpo local, que da
1818 caracteres y el md5 de producción exacto.

`donde-vive.sh` ya no te deja en esa duda: da **los dos md5** —tal cual y sin
comentarios— y te imprime la consulta lista para pegar en producción, con los
tres desenlaces escritos. Si coincide el primero, seguir. Si coincide el segundo,
seguir pero declarando en la migración el md5 de PRODUCCIÓN. Si no coincide
ninguno, parar.

Lo que **no** se propone es repegar 119 funciones. Pero conviene saber lo que
cuesta: estas migraciones se leen como documentación del negocio, y en producción
la mitad de esa explicación no está.

**Antes de dar cualquier SQL que toque plata, se audita empíricamente.**
Contra el Postgres local, dentro de `BEGIN … ROLLBACK`, con casos reales. No se
entrega un cálculo de planilla, provisiones, bonos o CTS "revisado a ojo".

**Desplegar a producción se pregunta SIEMPRE.**
```bash
npx vercel --prod --yes    # solo con OK explícito de Felipe
```
Vista previa sin permiso: `npx vercel --yes`.

⚠️ **PERO OJO: `main` se publica SOLA. Fusionar un PR ES desplegar a
producción.** Medido el 2026-09-10 y decidido por Felipe ese día: se queda así.
La integración de Git de Vercel tiene `main` como rama de producción, así que
**cualquier push a `main` publica** — se comprobó con un commit que solo cambia
un `.md` y aun así redesplegó en menos de un minuto.

Lo que eso significa, y hay que tenerlo presente al pedir permiso:

- **`desplegar.sh prod` vigila un camino por el que producción ya no pasa.**
  Sus comprobaciones (árbol limpio, GitHub al día, CI verde incluidas las
  pgTAP, escribir `publicar`) siguen siendo correctas y **no se aplican** a los
  despliegues que salen de un `git push`. Misma forma que el agujero de la 0177
  y la 0243 con `dame-el-sql.sh`: el freno está bien, el camino cómodo no pasa
  por él.
- **Desde el 2026-09-21, fusionar un PR exige `db-tests` y `ui-tests` en verde
  — pero eso no es lo mismo que «CI verde sobre lo que se publica».** Lo exige
  el ruleset «main: pruebas obligatorias» de GitHub (qué cubre y quién lo
  salta: ver «La red de seguridad»). Antes no había nada: el 2026-09-10
  producción sirvió el código de tres merges durante ~20 minutos mientras
  `db-tests` todavía corría. Lo que el ruleset todavía NO garantiza, medido el
  2026-10-01:
  - **Cuentan las pruebas del PR, no las del commit que llega a `main`.** El
    ruleset tiene `strict=false`: no exige que la rama esté al día con `main`.
    Las pruebas de un PR corren sobre su mezcla con el `main` *del momento en
    que arrancaron*; si otro PR se fusiona en el medio, el tuyo entra con
    pruebas que nunca vieron ese cambio. Pasó 1 vez en las 25 fusiones del
    21-sep al #482: el #468 se probó a las 17:45 (UTC) y se fusionó a las
    17:51, un minuto después que el #466. La corrida de `main` sobre los dos
    juntos dio verde — después de publicados. Donde esto duele es la forma del
    accidente de la 0261: dos PR que reescriben la misma función partiendo de
    la misma versión pasan cada uno en verde, y juntos el de número mayor
    revierte al otro sin que ninguna prueba lo haya visto antes de publicar.
  - **La corrida de `main` después de fusionar sigue sin frenar nada.** Vercel
    publica en menos de un minuto; `db-tests` tarda unos cinco.
  - Exigir ramas al día (`strict=true`) cerraría el primer hueco, a cambio de
    volver a correr el CI de todos los PR listos cada vez que uno se fusiona —
    con diez worktrees, y con el plan de Actions que ya se agotó una vez el
    2026-08-26. No está decidido; es de Felipe.
- **`gh pr merge N --merge` a secas ya no fusiona si las pruebas no
  terminaron**: se niega y ofrece `--auto` (medido el 2026-10-01 con el #482).
  - **`--auto` es publicar en diferido**: deja la fusión armada y GitHub la
    hace solo en cuanto las dos pruebas den verde, sin que nadie mire. Es la
    forma correcta de «fusiona cuando esté verde», y por eso **se arma solo
    cuando Felipe lo pidió para ESE PR**, con la migración ya pegada y con
    `--merge` (`main` va con commits de fusión). El riesgo no es teórico:
    encender «Auto-fix pull requests» en la app de escritorio la ha armado
    sola, en squash, sin que nadie lo pidiera —el #464 el 2026-09-27 y el
    #483 el 2026-10-01—, y en el #483 el panel de la app siguió diciendo que
    no estaba armada. Lo único fiable es
    `gh pr view N --json autoMergeRequest`: `null` es desarmada. Si aparece
    armada sin que nadie la pidiera, se desarma (`gh pr merge N --disable-auto`)
    y se avisa con la hora y quién la armó.
  - **`--admin` salta el ruleset.** No es otra forma de fusionar: es la salida
    de emergencia, y va con OK explícito de Felipe para ese PR.
- **Y de aquí sale el orden que importa: la migración se pega ANTES de fusionar
  el PR que la usa.** Después de fusionar, el frontend ya está en el aire. Ese
  día falló dos veces —la 0404 dejó el envío del DNI rompiéndose *después* de
  subir las dos fotos, y el PR de la 0407 iba a publicar un botón que llamaba a
  una función inexistente— y a las dos las cazó alguien mirando, no un freno.

Así que pedir permiso para fusionar y pedirlo para publicar son la misma
petición. Dilo así cuando lo pidas.

**Y una sesión de Claude comenta en el PR ANTES de fusionarlo.** Todas las
sesiones trabajan con la cuenta de Felipe, así que para GitHub «lo fusionó
Felipe» y «lo fusionó una sesión» son lo mismo. El 2026-10-06 el #505 se fusionó
diez minutos después de abrirse y no hubo forma de saber cuál de las dos cosas
pasó. Estaba bien hecho —por PR, con `db-tests` y `ui-tests` en verde— y aun así
quedó sin respuesta la pregunta que importa: ¿alguien lo pidió?

El comentario lleva la marca `<!-- cayla:fusion-sesion -->` y cuatro líneas:
**Sesión** (worktree y rama), **Pidió** (quién, con sus palabras, y cuándo),
**Pruebas** (estado de `db-tests` y `ui-tests` al fusionar) y **SQL** («no hay»,
o qué migración se pegó antes y quién lo confirmó). Tiene que ser POSTERIOR al
último commit del PR: un comentario de las 10:00 no avala un commit de las
10:30, así que si empujas algo después —o traes `main` a la rama— se comenta de
nuevo.

Lo vigila `.claude/hooks/comentar-antes-de-fusionar.sh`, registrado en
`.claude/settings.json`: frena `gh pr merge` —también con `--auto`, que es
publicar en diferido— si falta el comentario, e imprime el formato exacto. Dos
límites, y conviene saberlos: solo cubre a las sesiones de Claude que parten de
una rama con este archivo (una web de GitHub o `gh api …/merge` no pasan por
él), y si no puede leer el PR **frena**, no deja pasar. Que no lo vea un freno
no es permiso: la regla es la de arriba, el freno solo la hace difícil de
olvidar.

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
un worktree hay que copiar el enlace y comprobarlo:

```bash
mkdir -p .vercel && cp "$(git rev-parse --path-format=absolute --git-common-dir)/../.vercel/project.json" .vercel/
npx vercel env ls          # tienen que salir las variables de cayla-dynamic
```

**La ruta se pregunta, no se cuenta a mano.** Este archivo decía
`cp ../../.vercel/project.json .vercel/`, y esos dos niveles solo valen si el
worktree cuelga justo debajo del repo. Los que crea Claude Code viven en
`.claude/worktrees/<nombre>/`, o sea **tres** niveles: el 2026-08-15 la ruta no
existía y el `cp` falló. Falló ruidoso y no pasó nada, pero el modo en que ese
`cp` hace daño es al revés — copiando algo que no es el enlace bueno, o no
copiando nada mientras alguien cree que sí. `--git-common-dir` devuelve el `.git`
del repo principal desde cualquier worktree y desde el repo mismo, así que la
línea es una sola y no hay que saber a qué profundidad estás.

Y el `npx vercel env ls` no es adorno: es lo único que distingue «copié el
enlace» de «copié el enlace CORRECTO». Tiene que decir `cayla/cayla-dynamic`.

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
| líder de equipo | jefe, supervisor, encargada |
| sede, tienda, boutique | sucursal |
| Desarrollo Organizacional (DO) | RRHH |
| clienta | cliente (para quien compra) |

El código tiene el rol `supervisor_sede` en la base por historia —y con él nombres
como `esEncargada`, `es_encargada_piso` o `meta_encargadas`, que no se renombran—;
en pantalla y en prosa siempre es **líder de equipo**, y **«líder(es)»** a secas en
los contadores cortos («Líderes en piso»). Hasta el 2026-09-18 la pantalla decía
«encargada» en unos sitios y «líder de equipo» en otros (Equipo, Objetivos, la
boleta): dos palabras para la misma persona. No se confunde con `lider_do`, que
es «Líder DO» (Desarrollo Organizacional).

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

Y una cuarta, de agosto de 2026: **«qué le tocaba trabajar ese día» se pregunta a
`apps/web/lib/admin/jornada-esperada.ts`, no se vuelve a escribir.** Ahí vive la
cascada *turno del día → `horario_por_dia` → `dias_laborables`* que espeja
`fn_recalcular_jornada`, con sus pruebas en `tests/jornada-esperada.test.ts`.
Vive en `apps/web/lib` y no en `packages/shared` porque hoy solo la usa el panel;
el día que la necesite el terminal, se muda. Hubo dos copias más viejas y
parciales: en `admin/correcciones/page.tsx` (`calcularEsperado`), solo la hora
de entrada y con un bug real —su rama legacy no comprobaba `dias_laborables`—,
y en `admin/incidencias/page.tsx` (`trabajaEseDia`), solo booleano. Las dos se
unificaron el 2026-08-25. La cuarta copia —`admin/turnos/page.tsx`
(`horasDeTramo`, `celda`)— se unificó el 2026-09-03: tenía una divergencia
silenciosa (rellenaba `dias_laborables` con `[1,2,3,4,5]` cuando venía vacío,
un default que la cascada canónica nunca aplica) que nunca disparó porque esa
columna es NOT NULL en `horarios_asignados`, pero habría mostrado lunes a
viernes donde el resto del sistema mostraba descanso. **No se escribe una
quinta.** Esa regla decide si a alguien se le cuenta una falta.

Y una quinta, del 2026-08-26: **un campo de fecha cuyo vacío BLOQUEA el envío
no puede arrancar en `""`.** Nace con el valor más probable —hoy, o la fecha de
inicio de lo que se está registrando—, visible y editable en un clic.

No es una preferencia de forma. Ese día no se pudo registrar un descanso médico
real: el campo «Fecha de emisión» mostraba `26/08/2026` en pantalla y llegaba
**vacío** al formulario, porque Safari había puesto el valor sin disparar el
evento que React escucha. La validación de la pantalla y la del servidor pedían
las dos un dato que estaba delante de los ojos, y no había salida — reescribirlo
tampoco llegaba, porque el problema no era el valor sino el camino.

Se intentó capturarlo por `onChange`, por `onBlur` y leyendo el valor del DOM.
**Ninguno de los tres lo vio.** Lo que funcionó fue dejar de preguntar: lo que se
muestra y lo que se manda pasaron a ser el mismo valor derivado. Costó cinco
despliegues a producción y una tarde, con la planilla del mes a dos días de
cerrar.

Lo vigila `scripts/hooks/fecha-que-bloquea.sh`, sobre lo que el push agrega.
Quedan tres campos así de antes —`contratos` y `documentacion` ya arreglados, y
`simIni` en `planilla`, que solo afecta a una simulación—; la deuda vieja se
paga en su lote y no a costa de que el freno mienta.

Y una sexta, del 2026-08-31: **nunca un color de Tailwind por defecto
—`bg-white`, `amber-100`, `bg-black`, `text-slate-900`— fuera de los trece
`--color-*` de `globals.css`.** Toda la pantalla se pinta con esos trece
nombres (`bg-crema`, `text-tinta`, `bg-papel`…) precisamente para que el modo
oscuro pudiera llegar redefiniéndolos, sin tocar un componente. Un color de
Tailwind por defecto no sigue esa redefinición: se queda con su valor fijo,
así que al construir el modo oscuro esos sitios se quedaban como un parche
claro pegado en medio de una pantalla ya oscura.

Eran nueve hasta el 2026-09-06, cuando se sumaron `--color-hueso` (una
superficie "hundida" — hasta entonces solo había una elevada, `papel`, y
ninguna por debajo de `crema`; se usa en inputs y en la zebra de tablas) y
`--color-pizarra` (el estado "informativo/en proceso" — programado, en
revisión, pendiente de firma — que no encajaba en positivo/advertencia/alerta
y por eso se apilaba sin distinguirse sobre `sand`). Los dos se midieron
contra la fórmula de contraste WCAG antes de aceptarse (≥4.5:1 en los pares
que los usan) — el mismo criterio que ya exige este archivo para planilla:
medir, no asumir.

Y trece desde el 2026-10-05: `--color-azul` (en pausa por un trámite, un
médico u otro motivo) y `--color-ceniza` (turno terminado), para el estado de
cada integrante en el terminal. «En refrigerio» y «En pausa» compartían ámbar
y no se distinguían, y ninguno de los once cubría un azul franco ni un gris de
«ya terminó». Se midieron como se pintan de verdad —sobre la casilla teñida y
como insignia sobre crema— y uno de los dos **falló la primera vez**:
`#68645c` daba 4.27:1 como insignia, así que se oscureció a `#635f58`. El
detalle y las cifras están junto a los tokens en `globals.css`, incluida la
separación entre los cuatro colores del estado para quien tiene daltonismo (la
más ajustada, verde/ceniza, es 10.6 bajo deuteranopía: por eso el color nunca
va solo, cada estado lleva además ícono y palabra).

Se midió al escribirlo: ~20 usos sueltos en 11 archivos, casi todos insignias
de aviso (`amber-100`/`amber-800` para "sin ficha", "valor antiguo", "fuera de
la base") y un par de tarjetas (`bg-white`). Dos de esos sitios no eran un
descuido sino que corrigieron algo peor, y por eso importa distinguir un color
suelto de un color que solo PARECE suelto: cuatro botones de
`admin/contratos/page.tsx` tenían `bg-tinta` con `text-white` en vez de
`text-crema` —`bg-tinta` se aclara en oscuro, así que el texto blanco fijo se
habría vuelto ilegible sobre un botón que dejó de ser oscuro— y cuatro
overlays de modal (buscador, atajos, acuses pendientes, cerrar el día en
`admin/horas`) usaban `bg-tinta/NN` como scrim: en oscuro eso ACLARA el fondo
en vez de oscurecerlo, lo contrario de lo que un scrim tiene que hacer. Esos
pasan a `bg-black/NN`, que sí oscurece en los dos temas — el criterio que ya
usaban los modales de turnos, incidencias, horarios y correcciones.

Y la excepción, que hay que distinguir con cuidado porque son DOS excepciones
distintas, no una:

- Los documentos con la clase `.hoja` —boleta, contrato, documentación, Hoja
  de sede, el memo disciplinario desde el 2026-08-31— NO llevan un color
  fijo: en pantalla siguen el tema como cualquier otra pantalla (`.hoja` no
  pinta nada por sí sola), y solo se fuerzan a la paleta clara AL IMPRIMIR,
  por la regla ya escrita en `@media print` de `globals.css`. Es la forma
  correcta: nadie necesita ver un contrato en modo oscuro mientras lo revisa
  en pantalla, pero el papel que sale de la impresora sí tiene que ser
  siempre el mismo, para siempre.
- La vista previa "Así se verá sobre la línea del memo" de la firma, en
  `admin/personas/[id]/page.tsx`, usa `bg-white` fijo A PROPÓSITO, sin pasar
  por `.hoja` ni por los tokens: es un rectángulo que simula el papel del memo
  impreso, y ese papel no cambia con el tema de quien lo mira.

**Política salarial ya NO es esta excepción.** Hasta el 2026-09-05 usaba
`bg-white`/`slate-*` fijos igual que la firma, pero el commit `ea6286f`
("La política salarial deja de ignorar el modo oscuro") la migró entera a
los tokens — hoy sigue el tema como cualquier otra pantalla del panel. Si una
sesión futura la encuentra con un color fijo, no es la excepción histórica
reapareciendo: es una regresión real. (Pendiente sin resolver aquí: la lista
de verificación del Día 2 en `docs/plan-apariencia-2026-09-06.md` todavía
repite la suposición vieja de que política salarial se queda fija.)

La lección de las dos que quedan: nunca asumir cuál aplica sin mirar si el
contenedor lleva `.hoja` o un color fijo — la resolvió al construir el memo,
que hasta entonces caía en la segunda categoría sin que hubiera una razón
para eso, solo porque nunca se había actualizado.

```bash
npx pnpm install
npx pnpm dev          # levanta todo
npx pnpm typecheck
npx pnpm test         # vitest
```

---

## Antes de escribir una función SQL — aunque sea nueva

`donde-vive.sh` no es solo para reescribir: **se corre también antes de CREAR**.
El 2026-08-25 la 0299 creó `fn_vacaciones_por_vencer` sin comprobar que la
**0297** ya la había creado dos días antes desde otra rama, con su prueba, su
banda en la pantalla, su entrada en el menú y sus tipos regenerados. Se
construyó dos veces la misma función.

Y no quedó en trabajo perdido: las dos tenían todos sus argumentos con valor por
defecto, así que la llamada sin argumentos encajaba en las dos y Postgres se
negaba —«function … is not unique»—. **El aviso de vacaciones dejó de mostrarse
en producción**, y como siempre con las sobrecargas, no falló al pegar la
migración: falló al abrir la pantalla.

Con varias sesiones trabajando a la vez, «esta función no existe» es una
suposición, no un hecho. Cuesta dos segundos comprobarlo:

```bash
./scripts/donde-vive.sh fn_lo_que_vayas_a_crear
```

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
- **El registro va con `do update`, no con `do nothing`.** La línea del final de
  cada migración se escribe así:

  ```sql
  insert into migraciones_aplicadas (numero, nombre) values (NNN, 'descripcion')
  on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
  ```

  Con `do nothing` —como estaba hasta el 2026-09-10— repegar sigue sin fallar,
  pero **una colisión de número se vuelve invisible**: el DDL se aplica y el
  registro se queda con la fila de OTRA migración, sin que nada avise. Ese día
  pasó dos veces en la misma tarde: se tragó el registro de la **0405** (el
  número lo tenía ocupado la migración de la AFP con su numeración vieja) y el
  de la **0409** (lo tenía la del memo, renumerada después a 0412). Con
  `do update` repegar sigue siendo seguro y el número robado **se ve**: la fila
  cambia de nombre delante de quien pega.

  Y la comprobación que va con esto: **al verificar un registro se piden
  `numero` Y `nombre`.** Un `array_agg(numero)` no distingue «está la mía» de
  «está otra con mi número» — ese fue justamente el paso que dejó pasar las dos.

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

**Un número que DO debería poder cambiar va al catálogo de parámetros, no a una constante** (0551, oct-2026). `parametros_catalogo`
dice qué se puede mirar y cambiar desde `/admin/parametros` (nombre, unidad, mínimo, máximo, clase) y el valor sigue viviendo donde ya
vivía (`configuracion`). Se cambia por UNA puerta, `fn_parametro_cambiar`, que exige motivo y respeta los límites; un trigger sobre
`configuracion` rechaza la escritura directa de esas claves y **escribe `parametros_historial` por cualquier camino**, también el
SQL Editor (marcado «base», sin autor). Para sumar uno: una migración que inserta su fila del catálogo (con mínimo y máximo: un
editable sin tope no se acepta), y el código lee el valor de la tabla, no lo repite. Tres clases, tres cuidados: *operativo* (lo decide DO),
*plata* (exige **vigencia** y vista previa de a quién le cambia —un valor sin fecha reescribe los periodos ya pagados, como pasó con
`tasa_afp`—; entra en la rebanada 2) y *normativo* (ley o RIT; solo la dirección, y nada hoy es editable). **La escalera disciplinaria
no es un parámetro libre**: es del RIT y solo se mueve atada a una versión del RIT, porque aplicar una escalera distinta a la que la
persona recibió firmada vuelve impugnable la sanción. El trigger no es `SECURITY DEFINER` y no debe serlo (el mismo motivo de la 0550).

**Guards `SECURITY DEFINER` null-safe.** Siempre `if fn_es_admin_o_lider() is not true`,
nunca `if not fn_es_admin_o_lider()` — un `null` no debe pasar como autorizado.
Desde la 0078 los booleanos de permiso ya no devuelven `null`, pero la forma
`is not true` sigue siendo la obligatoria: cualquier condición que compare un
UUID contra `fn_persona_actual_id()` vuelve a producir `null` por su cuenta.

**Un campo sensible se cambia por una función guardián, nunca por `UPDATE`
directo — y la función se cierra con un trigger, no con la confianza.**
El molde es siempre el mismo: una función `SECURITY DEFINER` que valida
(rol, estado de la fila, reglas de negocio) y escribe con
`insert into correcciones_auditoria`, más un trigger `before update` que
rechaza cualquier cambio a esa columna que no venga de esa función —
comparando `current_user <> 'postgres'`, que es como Postgres distingue "lo
hizo una función interna" de "lo hizo un cliente por PostgREST", ya que el
rol de conexión es el mismo (`authenticated`) en los dos casos. Son ya tres
instancias, cada una escrita por separado sin generalizar:
`fn_cambiar_regimen_pension` (0261), `fn_set_rol` + `fn_bloquear_rol_directo`
(0295/0296) y `fn_set_sede_base` + `fn_bloquear_sede_directa` (0342).

Se nombra acá porque nunca se había escrito como regla, solo se había
repetido — y una comparación de arquitectura contra otros ERP (Workday,
Oracle, BambooHR, Odoo; ver
[`docs/comparacion-workday-oracle-dynamic-2026-09-02.md`](docs/comparacion-workday-oracle-dynamic-2026-09-02.md))
la señaló como el mismo primitivo que esos sistemas resuelven una sola vez
en el núcleo, mientras que acá se venía reinventando cada vez que un campo
nuevo resultaba tocar plata o una obligación legal. La próxima columna
sensible sigue este molde por regla, no porque alguien se acuerde de las
tres anteriores.

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

## Novedades del sistema

**Un cambio que el equipo va a notar lleva su novedad en el MISMO pull
request.** La lista vive en `apps/web/lib/novedades.ts`. Se lee en
`/admin/anuncios`, debajo de los comunicados de DO, y en el «Resumen» de «Lo
mío» —solo ahí, no en sus otras secciones—, donde solo
aparecen las que a esa persona le faltan por entender (las tres más recientes,
con su primer párrafo). El encabezado del archivo dice qué va, qué no y cómo se
escribe una entrada.

Está en el código y no en la tabla `anuncios` por una razón de orden: `main` se
publica sola, así que una novedad en el código sale con la mejora que cuenta,
ni antes ni después. Una fila en `anuncios` exigiría una migración, y la
migración se pega ANTES de fusionar: el aviso «ya puedes hacer X» estaría en
pantalla mientras X todavía no existe.

Criterio: ¿alguien de una sede lo va a notar al usar el sistema? Un error que
dejó de pasar, una pantalla que dice otra cosa, un botón nuevo: sí. Refactores,
pruebas, migraciones internas y renumeraciones: no. Medido el 2026-09-19, de
169 commits desde el 15 de septiembre, 55 eran solo bastidores — por eso no se
generan solas desde los mensajes de commit.

**Qué guarda la base, y qué pasa si falta.** Solo quién entendió cada novedad:
`novedades_vistas` (0480), por persona, con `fn_marcar_novedad_vista`. «Nueva» =
de los últimos 14 días y sin entender; esa regla vive en un solo sitio
(`esNovedadPendiente`) y la usan las dos pantallas. **La 0480 se pega ANTES de
fusionar**, como toda migración; si el código llega primero no se rompe nada:
sin poder leer las marcas, «Lo mío» calla y Anuncios muestra por fecha, sin
botón. El `id` de cada entrada tiene un formato que la base también exige, y
`tests/novedades.test.ts` compara los dos lados.

**Nunca una regla de pago, un descuento, una tardanza o algo disciplinario.**
«Entendido» en una novedad es un marcador liviano, sin acuse: no prueba que
nadie se enteró, y lo que afecta a una persona hay que poder probar que se le
informó. Lo que cambie cuánto se le paga a alguien va por la Política salarial
(versionada, con acuse) o por Normas; en una novedad, como mucho, se avisa que
hay algo nuevo que leer allá. Y sin nombres ni montos: la lista baja al
navegador de todo el mundo, y la audiencia (`todos` / `panel` / `do`) decide qué
se dibuja, no qué es secreto. `tests/novedades.test.ts` vigila montos, DNI,
correos y el vocabulario.

**Nada obliga a escribirla: es memoria, y ya se sabe lo que valen las reglas de
este archivo que dependen de eso.** La señal de que se está olvidando es que la
entrada más reciente tenga semanas mientras `main` no ha parado. No se puso un
freno en el push porque la mayoría de los cambios de pantalla no se notan, y un
aviso que salta siempre se aprende a ignorar; si el olvido se repite, el paso
siguiente es medir cuántos cambios notables hubo sin entrada antes de decidir.

---

## Qué hay en `docs/`

| Ruta | Qué es |
|---|---|
| `estado.md` | **Dónde estamos hoy.** Se sobrescribe, no se acumula. |
| `easter-eggs.md` | **Los secretos del sistema** y cómo activarlos: el código Konami, «colibrí» en el buscador, los clics del login, los toques de fecha y el colibrí sin internet. Si agregas uno, se anota ahí en el mismo PR. |
| `cerrar-el-mes-sin-pagar-dos-veces.md` | El día 28, al cerrar la planilla: qué avisa el sistema cuando alguien cesó a mitad de mes y ya cobró su liquidación, y qué apretar. |
| `prueba-restauracion-backup.md` | Cómo comprobar, con `scripts/probar-restauracion-backup.sh`, que el respaldo de producción se puede restaurar de verdad — no solo que existe. |
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

**Nunca exportes `LC_ALL=C` en la shell que va a llamar a `dame-el-sql.sh`.**
El 2026-08-25 una sesión lo hizo y el portapapeles salió con los acentos rotos
—«QU√â PROMETE» por «QUÉ PROMETE», 76 acentos donde el archivo tiene 425—. Eso
ya está documentado más arriba como accidente de 2026-08-08, y el script se
arregló entonces para compararse byte por byte y negarse si no coincide.

Lo nuevo, y es lo que hay que recordar: **el script se declaró conforme.** Su
comprobación corre bajo el mismo locale roto, así que compara texto corrupto
contra texto corrupto y coinciden. El guardián y el vigilado leían lo mismo.

Un freno solo protege de lo que puede ver. La comprobación buena es externa y
con el locale explícito:

```bash
unset LC_ALL; export LANG=en_US.UTF-8 LC_CTYPE=en_US.UTF-8
./scripts/dame-el-sql.sh 0NNN
diff <(pbpaste) supabase/migrations/0NNN_*.sql && echo "idéntico"
```

El SQL corrupto corre igual —nada falla— y deja la migración ilegible. Y estas
migraciones se leen: son la documentación del negocio.

**Antes de subir a GitHub** corre solo un hook (`scripts/hooks/pre-push`) que
verifica la **numeración**, **las dos reglas de abajo que se cumplían de memoria**,
el `typecheck` y las pruebas de interfaz. Si algo está en rojo, el push no se
hace. Toma unos 10 segundos.

**Dos de las reglas de este archivo ya no dependen de que alguien las recuerde**
(`scripts/hooks/reglas-de-la-casa.sh`, ago-2026): comparar `rol` contra un
literal fuera de `permisos.ts`, y escribir `"America/Lima"` fuera de
`fecha-lima.ts`. Las dos estaban escritas aquí y las dos se habían vuelto a
romper — la auditoría de agosto encontró **diez** de la primera y **tres** de la
segunda. Y las dos reglas se habían escrito DESPUÉS de juntar 35 y 32 copias
respectivamente, así que el problema nunca fue la redacción: era que un
documento es memoria, y aquí trabajan varias sesiones a la vez.

Solo mira **lo que el push agrega**, igual que la verificación de numeración y
por el mismo motivo: comparar el árbol entero encontraría las trece que ya están
y fallaría en todos los push. La deuda vieja no molesta, y una regla nueva no
puede entrar; la deuda se paga en su propio lote, no a costa de que este freno
mienta. Ignora comentarios a propósito — este archivo cita `rol === "admin"`
para explicar la regla, y castigar a quien la explica sería absurdo.

Bloquea en vez de avisar, y ahí la distinción es la que el hook ya tenía
escrita: esto habla de lo que **sale** hacia GitHub, no de lo que hay a medio
escribir en el disco.

**Y desde el 2026-08-26, las fechas que arrancan vacías**
(`scripts/hooks/fecha-que-bloquea.sh`). Ver la regla arriba: caza el
`input[type=date]` que arranca en `""` y cuya validación corta el envío. Se
probó con un caso que DEBE bloquear antes de entregarlo, y con dos que deben
pasar —el mismo campo arreglado, y una fecha opcional—, que es la lección que
dejó el linter cuando se escribió cuatro veces dando el push por bueno.

**Y desde el 2026-08-25 corre también el linter, sobre lo que el push agrega**
(`scripts/hooks/lint-de-lo-nuevo.sh`). ESLint llevaba instalado y configurado
desde julio, con su tarea de turbo y su script en el `package.json`, y no lo
ejecutaba nadie: ni el hook, ni GitHub, ni `desplegar.sh`. La auditoría de
agosto lo encontró con 119 errores; **una semana después eran 131**. Creció en
doce sin que nadie lo notara, que es exactamente lo que le pasa a un guardián
instalado y apagado.

Mismo criterio que los dos de arriba: la deuda vieja no frena a nadie, el error
132 no entra. Y es barato porque no lintea el repositorio entero —solo los
archivos que el push modifica—, así que un push de puro SQL sale en cuatro
centésimas.

Ojo con una cosa al tocarlo: **se escribió cuatro veces antes de funcionar, y
las cuatro veces fallaba en silencio dando el push por bueno**. Colar una ruta
de `packages/` hace que eslint aborte sin analizar nada; pasarle las rutas sin
`xargs` las manda como un solo argumento; `${SALIDA#[}` nunca quita el corchete
porque `[` es un carácter de patrón; y `echo` interpreta los `\n` que el JSON de
eslint lleva dentro de sus mensajes, así que hay que usar `printf '%s'`. Ninguno
de los cuatro daba error: todos devolvían «todo bien». Por eso un freno se
prueba con un caso que DEBE bloquear, no solo con uno que debe pasar.

No verifica una tercera que se probó y se descartó: buscar `horario_por_dia`
fuera de `jornada-esperada.ts` para cazar las copias de «qué le tocaba trabajar
ese día». Da 28 aciertos y casi todos son pantallas que leen esa columna con
todo el derecho. Un guardián con ese ruido se desactiva a la semana, así que esa
regla sigue dependiendo de que alguien la recuerde.

**Y desde el 2026-09-10, una pantalla que imprime sin fijar el nombre del PDF**
(`scripts/hooks/descarga-sin-nombre.sh`). El nombre con el que el navegador
sugiere guardar un PDF es `document.title` al momento de imprimir; sin fijarlo
queda en «Dynamic — CAYLA» para cualquier persona y cualquier papel. Ya existía
`useTituloDocumento()` (`apps/web/lib/admin/use-titulo-documento.ts`, decidido
con Felipe el 2026-07-28 tras el mismo problema con las boletas) y las otras 12
pantallas imprimibles lo usaban — Liquidaciones lo tenía sin usar en sus tres
papeles (liquidación, certificado de trabajo, constancia de cese), justo los
que se entregan a alguien que ya se fue de la empresa.

Distinto de los de arriba en una cosa: no mira **líneas** agregadas por el push,
mira **archivos** que el push toca, enteros, en la versión que se empuja
(`git show HEAD:archivo`, nunca el disco). Lo que hay que comprobar —¿este
archivo llama a `window.print()` sin tener `useTituloDocumento()` en algún
lado?— es una propiedad del archivo completo, no de una línea: el hook puede
vivir a cientos de líneas de la llamada a imprimir, y mirar solo el diff de
líneas se lo perdería si alguien le agrega un botón nuevo a una pantalla ya
existente. Mismo criterio en lo demás: solo los archivos que el push toca
—hoy no queda ninguno con este defecto, así que no hay deuda vieja que
pagar—, y bloquea, no avisa.

**Y desde el 2026-10-17, que un push no pueda volver a escribir a mano una pieza
que ya tiene componente** (`scripts/hooks/receta-suelta.sh`, paso 2 del
[ADR 0004](docs/adr/0004-diseno-unificado.md)). El ADR decidió una sola forma
para cada pieza del panel y la puso en `apps/web/components/ui`; cuatro días
después ya había siete archivos nuevos con la tarjeta escrita a mano
(`components/educacion/*`, `components/boletas/hoja-constancia-boleta.tsx`).
Nadie lo hizo mal a propósito: la pantalla de al lado trae la receta vieja y
copiarla cuesta menos. Es la historia de `rol === "admin"` otra vez.

Busca nueve recetas y bloquea cuando el push **suma** una: tarjeta
(`rounded-superficie border border-sand bg-papel` → `<TarjetaInfo>`, `<EstadoVacio>`
o `<Tabla>`), cifra (→ `<Cifra>`), filtro (`<button aria-pressed>`, o un botón que
se enciende con `bg-tinta text-crema` → `<Filtro>`), aviso (borde y fondo del
mismo color → `<BannerAviso>`), la clase `etiqueta` (→ `<Rotulo>` y compañía),
`<h1>` de pantalla (→ `<CabeceraPagina>`), encabezado/fila de tabla (→
`<TablaEncabezado>`, `<Fila>`), «Cargando…» como texto (→ `<Cargando />`) y el
cajón por la derecha (→ `<Drawer>`). Exentos: `components/ui`, el terminal, y los
papeles que se imprimen (una clase `print:` exime la tarjeta y el aviso; la clase
`hoja` en el archivo exime cifra, rótulo y tabla). Al 2026-10-17 quedaban **270 recetas en 82
archivos**: `RECETA_TODO=1 RECETA_RESUMEN=1 python3 scripts/hooks/receta-suelta.py`
las recuenta sin frenar nada.

Cuatro cosas que conviene saber antes de que frene tu push:

- **Solo cuenta lo que se SUMA.** Se compara por *hunk*: si una línea que ya tenía
  la receta solo cambió (un hotfix que toca el `className` de una tarjeta vieja),
  no cuenta. Quitar tarjetas viejas, migrar una pantalla o renombrar un archivo
  tampoco. Lo que sí: un archivo nuevo, una receta donde no había, y mover una
  tarjeta de un archivo a otro (cuenta como nueva).
- **La salida legítima no es `--no-verify`.** Una caja que de verdad no es la
  pieza —un `<details>`, un acordeón— se declara en esa línea o en una de las dos
  de arriba: `{/* receta-propia: es un <details> y TarjetaInfo no puede serlo */}`.
  El motivo es obligatorio y se busca con grep. No sirve para «el componente casi
  sirve»: eso se arregla en el componente, que es el punto del ADR.
- **No ve todo.** Una receta partida en dos cadenas de un `cx()`, un borde
  condicional o un `<Link>` con forma de tarjeta se le escapan. Es un escáner de
  cadenas y etiquetas, no un compilador, y está dicho en su cabecera.
- **Sin Python 3 avisa y deja pasar**, como `lint-de-lo-nuevo.sh`.

**Qué familias entran y cuáles no** salió de un segundo barrido (2026-10-17) que
el ADR pedía antes de poner el freno —«un freno sobre un inventario incompleto
bloquea lo equivocado»—. *Entran* los estados de carga (`components/cargando.tsx`
existe desde el 27-jul y no está en `ui`, así que el ADR no lo vio: 36 usos del
componente contra 20 «Cargando…» a mano) y el cajón derecho. *No entran* los
avisos emergentes (`useToast()` ya es el único: ningún aviso `fixed bottom-` suelto fuera de él) ni
los esqueletos (cero `animate-pulse`). Y las **pestañas no entran por una razón
que es una decisión abierta, no un descuido**: el ADR las unió a los filtros, pero
cuatro de las cinco `tablist` del panel son pestañas *subrayadas* (la quinta es un
segmentado) y `<Filtro>` no es el destino de las cuatro; bloquear sin destino es bloquear lo equivocado. Queda en el
ADR como pendiente. Tampoco `<Insignia>` ni `<Modal>` (anteriores al ADR) ni la
escala de radios (`rounded-lg`/`rounded-xl` es otra regla).

Medido contra la historia antes de entregarlo (cada merge simulado como un push):
de los últimos 30 merges habrían frenado **6** (los 4 del rediseño de Educación,
las modales de Boletas y el rótulo del saludo de cumpleaños, todos sumando recetas
de verdad); de los últimos 30 commits sueltos, **1**; de los últimos 150 merges
(15-sep → 17-oct), **36**, y de 175 hallazgos solo 9 eran código movido de sitio.
La migración de cinco secciones (#552, que quitó 71 recetas) pasa. Su prueba es
`scripts/hooks/probar-receta-suelta.sh`: 36 casos —18 que **deben bloquear**,
11 que deben pasar, 5 de hunk y 2 de entorno— con cada intérprete (177
comprobaciones). Y se confirmó rompiendo el hook a propósito de ocho maneras
distintas: la prueba se puso en rojo las ocho veces.

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

**Y por lo mismo: `git commit --amend` NO se usa en este árbol.** Aquí trabajan
varias sesiones a la vez —el 2026-08-14 eran cuatro— compartiendo directorio e
índice, así que **HEAD puede moverse entre que commiteas y que amendas**. Ese día
pasó: una sesión commiteó, otra commiteó encima en los segundos siguientes, y el
`--amend` de la primera reescribió el commit de la segunda — le dejó su cambio de
`CLAUDE.md` con un mensaje sobre la maternidad, que no tenía nada que ver.

El contenido no se perdió: lo que se pierde es el mensaje del otro, y con él la
única explicación de por qué existe ese cambio. **Si un mensaje sale mal, se
arregla con un commit nuevo que lo explique, nunca reescribiendo el anterior.**
Es la misma razón por la que se commitea con `git commit -o <ruta>`: en un árbol
compartido, toda operación de git tiene que ser explícita sobre qué toca.

**Y avisa —sin bloquear— si hay una migración sin commitear**
(`scripts/hooks/migracion-sin-guardar.sh`). Porque el descuido de la 0177 volvió
a pasar: el 2026-08-14 la **0243**, que cambia una liquidación por cese, quedó
aplicada en producción con sus archivos sin commitear, y hubo cuatro pushes en el
medio que no dijeron nada. `dame-el-sql.sh` no lo evita y no puede — solo protege
a quien lo usa, y si tienes la migración abierta delante, copiarla del editor es
lo natural. El agujero no estaba en el script: estaba en que **el camino cómodo no
pasa por él**.

Distingue el archivo recién escrito del que **ya sobrevivió a un commit**: el
segundo no es trabajo en curso, es trabajo olvidado, y el aviso cambia de tono.
No bloquea a propósito, por la regla que este hook ya tenía escrita para
`types.ts` — *lo que sale de esta máquina se bloquea; lo que solo está en el disco
se avisa* —, porque con varias sesiones en paralelo una migración a medio escribir
es un caso legítimo constante.

**Y ese aviso solo mira migraciones. Todo lo demás se protege solo con el
hábito: se commitea ANTES de pasar a lo siguiente, no al terminar la jornada.**
El 2026-08-18 se perdieron los tres informes de la auditoría de agosto —116
agentes, dos horas— y una migración ya escrita, auditada contra la base y con su
prueba en verde. No los borró nadie a propósito: otra sesión movió el árbol
compartido y se llevó por delante lo que estaba sin guardar. El trabajo
intelectual se pudo rehacer porque los datos de los agentes vivían fuera del
repo; el resto se escribió dos veces.

Con cuatro sesiones compartiendo directorio, un archivo sin commitear no es
«trabajo en curso»: es trabajo que solo existe mientras nadie toque el árbol. Y
la ventana no es de horas — basta con que otra sesión haga un `checkout` en el
minuto siguiente.

Lo caro no fue rehacerlo. Fue que **la migración quedó obsoleta antes de poder
entregarla**: partía de la 0263 y, mientras se rehacía el trabajo, la función
vigente pasó a ser la 0269. Pegada tal cual habría revertido esa migración en
silencio — exactamente el accidente que `donde-vive.sh` existe para evitar, por
el camino de haber tardado demasiado en guardar.

**Y antes de EMPEZAR algo, mira si otra rama ya lo está haciendo.**

```bash
git log --all --oneline -20                    # qué se está construyendo ahora mismo
git grep -l "fn_lo_que_vas_a_tocar" $(git for-each-ref --format='%(refname)' refs/heads refs/remotes)
```

Cuesta diez segundos y el 2026-08-25 habría ahorrado esto: **dos sesiones
construyeron la misma función el mismo día**, cada una con su migración —la 0297
y la 0299—, las dos se fusionaron a `main` y las dos se pegaron en producción.
Como sus firmas diferían (`p_dias, p_as_of` contra `p_dias_aviso`), Postgres no
protestó: guardó dos funciones con el mismo nombre, con ventanas distintas
—60 días contra 90— y alcances distintos. Nada falló, y ese es el problema: dos
puertas para la misma pregunta conviviendo en silencio hasta que alguien note que
la pantalla y el contador no dicen lo mismo. Se descubrió contando funciones
después de pegar, y costó dos migraciones más para retirar una —la 0301 y una
0302 que hubo que tirar porque hacía lo mismo—.

Ese mismo día, más temprano, `siguiente-numero.sh` había repartido un número ya
ocupado por la misma razón de fondo: **aquí trabajan diez worktrees a la vez y
cada uno solo se ve a sí mismo**. Aquello se arregló en el script; esto no lo
caza ninguna herramienta, porque «otra rama está construyendo esta misma idea» no
se parece a nada que se pueda comparar automáticamente sin ruido.

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

**Y del lado de GitHub, desde el 2026-09-21: el ruleset «main: pruebas
obligatorias».** Al principio se eligió solo el hook local y **no** proteger
`main` en GitHub, porque eso habría exigido abrir un pull request por cada
cambio — fricción constante para quien trabaja sola. Ese razonamiento caducó:
para entonces todo entraba ya por PR, y el 2026-09-21 a las 09:34 (hora de
Lima) se creó un ruleset sobre la rama por defecto. Tampoco era «la misma
garantía»: el hook corre en esta Mac, se salta con `--no-verify` y no corre
las pgTAP; el ruleset vive en GitHub y mira el CI. No se reemplazan: el hook
frena lo que sale de la Mac, el ruleset lo que entra a `main`.

Ojo al buscarlo: **no es la protección de rama clásica** —
`gh api repos/felipea92p-ux/cayla-dynamic/branches/main/protection` da 404 y
eso NO significa que `main` esté desprotegida—. Se mira así:

```bash
gh api repos/felipea92p-ux/cayla-dynamic/rulesets/23773404
gh api repos/felipea92p-ux/cayla-dynamic/rules/branches/main   # las reglas que aplican hoy
```

Tiene tres reglas: no se puede borrar `main` (`deletion`), no se le puede
reescribir la historia (`non_fast_forward`, o sea `push --force`), y nada
entra sin `db-tests` y `ui-tests` en verde (`required_status_checks`, las dos
de GitHub Actions, con `strict=false` — qué deja pasar eso está en «Desplegar
a producción»). Y una excepción que lo cambia todo, medida el 2026-10-01:

| | Colaborador con permiso de escritura (hoy hay uno) | Admin (hoy solo la cuenta de Felipe) |
|---|---|---|
| Fusionar un PR sin las dos pruebas en verde | bloqueado | bloqueado por defecto; `gh pr merge --admin` lo salta |
| `git push` directo a `main` | bloqueado sin las dos pruebas en verde | **pasa** |
| `push --force` o borrar `main` | bloqueado | pasa |

La columna de la derecha sale de `bypass_actors`: el rol de repositorio
`admin` con `bypass_mode: always` — «always» quiere decir que el salto vale
también para un push directo, no solo dentro de un PR. **Y toda sesión de
Claude trabaja con la cuenta de Felipe**, así que para el ruleset cada sesión
es admin. Lo que de verdad protege a `main` de una sesión no es el ruleset:
es que el camino normal (`gh pr merge`) pasa por él, y que `--admin` y el
push directo a `main` no se usan sin OK explícito de Felipe. Lo del push
directo no se probó con un push real, porque ese push publica.

Lo que sí se midió es que hasta hoy nadie lo saltó. En septiembre, hasta el
día 21, entraron a `main` 32 commits sin pull request (los últimos el 10-sep);
desde el ruleset, **cero**: las 25 fusiones del 21-sep al #482 (1-oct)
entraron por PR, y GitHub no registra ni una evaluación en `bypass`. Se
vuelve a comprobar en una línea — si devuelve algo distinto de `[]`, algo
llegó a producción sin pruebas. El `time_period` no es adorno: sin él, la API mira solo las últimas
24 horas y un `[]` no dice nada del resto del mes.

```bash
gh api "repos/felipea92p-ux/cayla-dynamic/rulesets/rule-suites?ref=refs/heads/main&rule_suite_result=bypass&time_period=month"
```

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

**La señal fiable de las pgTAP es `db-tests` de GitHub Actions, no esta Mac.**
`.github/workflows/tests.yml` corre `supabase db start` + `supabase test db` en
CADA pull request y en cada push a `main`, sobre una base construida desde cero.
Eso es lo que hay que mirar antes de dar una migración por buena, y es lo que
`desplegar.sh` ya exige. Hoy son **214 archivos y ~2 188 aserciones**, no las
«34 archivos, 302 pruebas» que decía este párrafo.

**Y ojo con correrlas en esta Mac, porque el Postgres local es UNO SOLO para los
~10 worktrees.** `npx supabase test db` mide una base que otras sesiones mueven
por debajo, y `npx supabase db reset` **le destruye el estado a todo el mundo**.
El 2026-09-04, en una sola sesión, otra ventana la reinició tres veces mientras
se verificaba un PR: `max(numero)` de `migraciones_aplicadas` fue 363 → 357 →
348 → servidor caído → 372.

Eso produjo DOS falsos rojos, y los dos se leen como deuda vieja del repositorio:

- `274` fallaba porque a la base compartida le faltaban migraciones que el
  worktree sí tenía. En CI estaba verde.
- `194` ni siquiera fallaba: el contador casero hacía `grep` de «error» y casaba
  con el texto de una aserción — «(por error: el dinero nunca salió del banco)».

Se fue media hora en perseguir dos defectos que no existían. Así que si hace
falta medir en local antes de subir, hay dos reglas:

1. **Aísla la deriva.** Aplica dentro de `begin … rollback` las migraciones que
   le falten a la base (compara `migraciones_aplicadas` contra
   `ls supabase/migrations`), y corre ahí tu prueba. Nunca `db reset`.
2. **Corre siempre el control**: la misma prueba SIN tus cambios. Sin él no se
   puede distinguir «lo rompí yo» de «ya venía así», que es exactamente el error
   que se cometió.

Lo que sí sigue siendo cierto, y es la mitad útil de correrlas acá: `db start`
aplica el esquema entero desde cero, así que un error de sintaxis o una
dependencia rota de una migración nueva salta ahí y no en producción. (Este
archivo llegó a decir que las pgTAP «no corren en esta Mac porque necesitan
Docker», y eso era falso; comprobado el 2026-08-04 con Docker Desktop 29.6.2 y
Supabase CLI 2.109.1.)

Ojo con el resumen: `Bad plan. You planned N tests but ran M` **no** es un error de
conteo, es un archivo que abortó a media ejecución — las pruebas que faltaron nunca
verificaron nada. Se lee igual de discreto que un descuido y no lo es.

**Y hay un tercer falso rojo que NO es deriva de la base, aunque se le parece:
una prueba que va y viene sin que nadie toque nada.** Ahí lo que falla no es el
entorno, es un empate sin desempatar dentro de la propia prueba.

El molde es siempre el mismo: una columna `default now()`, y `now()` dentro de
una transacción vale LO MISMO para todas las filas. Como toda prueba pgTAP corre
entera dentro de `begin … rollback`, dos filas creadas ahí empatan al
microsegundo — y si la consulta las ordena solo por esa columna, cuál gana lo
decide el orden físico de la tabla, que cambia con lo que dejaron las
transacciones revertidas de las pruebas anteriores. Por eso la misma prueba pasa
en la suite completa y falla corriéndola sola, sin reconstruir nada.

Ya pasó tres veces: la 0312 lo cazó en `fn_contrato_firmado_vigente_de`
(ago-2026); el 2026-09-06 la prueba **274** volvió a hacerlo en
`fn_contratos_tablero` — con `db-tests` verde en `main` al mismo tiempo, porque
verde ahí es dónde cayó la moneda esa vez, no una prueba de que el caso esté
bien—, y lo arregló la **0386** con los mismos tres desempates de la 0312; y al
buscar la misma forma en el resto del esquema apareció en `fn_documentos_tablero`
(**0387**), donde pesaba más: la fila que gana ahí decide si el tablero dice
«firmó el pacto de movilidad» o «se negó a firmarlo», y sin pacto firmado ese
monto no es no remunerativo (RTF 05449-4-2007). Dos personas con el MISMO
expediente contestaban al revés una de la otra según el orden en que se
guardaron sus papeles.

Y una cuarta, la **0388**, que enseña que esta familia tiene DOS especies y
conviene no confundirlas. `fn_expediente_generar_falta` ordenaba por
`entregado_at desc limit 1`, y ahí el empate **no necesita una transacción**:
`entregado_at` no es `now()`, es un parámetro, y la pantalla manda el MEDIODÍA
DE LIMA cuando se marca una entrega con fecha pasada (`instanteEntrega`). Dos
documentos entregados el mismo día pasado empatan al microsegundo **en
producción**. De esa fila salen el escalón anterior, el corte de non bis in idem
y el antecedente citado — así que dos personas con el mismo expediente recibían
peldaños distintos de la escalera disciplinaria según el orden en que se
guardaron sus papeles.

**La distinción que hay que hacer siempre, y decide cuánto cuidado hace falta:**
si el empate solo ocurre dentro de una transacción, el desempate es inerte en
producción y se puede agregar sin más. Si la columna admite un valor elegido por
quien usa la pantalla —una fecha pasada, un mediodía fijo—, el empate es real y
el desempate **cambia comportamiento**: hay que medir a quién afecta antes de
pegarlo, no después.

Y ahí el criterio tampoco se inventa. La 0388 no eligió uno: copió el que
`fn_tardanza_escalon_al` (0311) ya usaba para la misma pregunta en el motor de
TARDANZAS. Las dos mitades del sistema disciplinario respondiendo distinto es lo
que la 0237 ya había venido a cerrar una vez — conviene mirar la función hermana
antes de decidir nada.

Las cuatro que quedaban —`fn_contratos_listar`, `fn_documentos_estado_politica`,
`fn_documentos_listar` y `fn_educacion_espejo_comprobante`— se cerraron juntas en
la **0389**, todas del tipo inerte. **La familia está completa: hoy no queda
ninguna.** Se comprueba de un tirón preguntándole al catálogo por un `order by`
que termine en una columna de fecha dentro de una consulta con `distinct on` o
`limit 1`:

```sql
select p.proname, m[1]
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
  lateral regexp_matches(p.prosrc, 'order by[^;]{0,120}', 'gi') m
 where n.nspname = 'public'
   and (p.prosrc ~* 'distinct on' or p.prosrc ~* 'limit[[:space:]]+1')
   and m[1] ~* '_at[[:space:]]+desc[[:space:]]*(limit|\)|$)';
```

Y el desempate nunca se inventa: se le pregunta primero a la función hermana —la
que responde esa misma pregunta en la otra pantalla o en la otra mitad del
sistema— y se copia el suyo. Las cuatro de la 0389 recibieron el de su hermana
(`fn_contratos_tablero`, `fn_documentos_tablero`), no uno nuevo. Que dos
funciones de la MISMA pantalla puedan contestar distinto a «cuál es el vigente»
es el defecto de fondo; los empates solo son cómo se manifiesta.

Un aviso sobre cómo se prueban estas: **el orden de inserción no siempre alcanza
para hacer fallar el control.** El caso de `educacion_comprobantes` acertaba sin
la migración porque el plan salía `Index Scan Backward` y devolvía el empate en
el orden que casualmente convenía. Lo que sí prueba de verdad es forzar el otro
plan —`set local enable_indexscan = off`, que dura solo la transacción—, porque
lo que está en juego es exactamente eso: que la respuesta no dependa de CÓMO
Postgres decida leer la tabla.

Y el criterio que se agrega es un **ancla**, no una regla: `id desc` es un uuid,
no significa nada. Va siempre DESPUÉS del último criterio real, así que solo
puede disparar en un empate que producción no sabe producir — por eso es seguro.
Inventar ahí un criterio de negocio («entre una firma y una negativa del mismo
día manda la negativa») sería meter política laboral en un `order by`, y esa
decisión no es de una migración.

Cómo se reconoce en dos minutos, antes de sospechar del entorno: si el valor que
sale es el de OTRA fila plausible —no un valor absurdo—, mira el `order by` de la
consulta que lo eligió. Si termina en una columna `now()`, es esto.

**Y la regla que deja atrás: un `distinct on` o un `limit 1` ordenado por una
columna `now()` necesita desempate explícito, aunque en producción nunca empate.**
En producción no empata porque cada escritura entra en su propia transacción; en
una prueba siempre empata. Un orden que depende del orden físico no es un orden.

En una urgencia real los tres se saltan: `git push --no-verify` (el hook),
`npx vercel --prod` (`desplegar.sh`) y `gh pr merge --admin` (el ruleset — o
un push directo a `main`, que con la cuenta de Felipe también pasa).
Que se pueda saltar a propósito es parte del diseño; que se salte sin querer, no.
Y el tercero publica en el acto, así que lo decide Felipe, nunca una sesión.
