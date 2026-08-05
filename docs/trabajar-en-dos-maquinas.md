# Trabajar en dos máquinas sin perder nada

MacBook en una ciudad, Mac mini en otra, la misma persona programando en ambas.
Esta guía es para copiar y pegar: no hace falta entender git para seguirla.

> **La idea en una frase:** GitHub es tu mochila. Antes de cerrar la laptop metes
> todo en la mochila; al llegar a la otra máquina la abres. Si un día se te
> olvida meter algo, ese algo se queda en la ciudad donde estabas.

**iCloud no sirve para esto.** Sincroniza a destiempo, deja archivos a medio
copiar y pelea con `node_modules`. Git existe justamente para este problema.
La copia que quedó en iCloud está pendiente de limpiar — mientras tanto, trabaja
**siempre** en `~/Proyectos/cayla-dynamic`.

---

## 🔒 La regla de oro

**Nunca dejes trabajo sin subir en dos máquinas a la vez.**

Todo lo demás en esta guía es esa regla, escrita en comandos.

---

## 🔴 CIERRO — me voy de esta máquina

Tres comandos. Siempre los mismos, estés donde estés.

**1 · Ver qué toqué** (opcional, pero tranquiliza)

```bash
git status
```

**2 · Guardar todo con un mensaje**

```bash
git add -A && git commit -m "lo que hice hoy en una línea"
```

**3 · Mandarlo a GitHub**

```bash
git push
```

Al hacer `push` verás esto, y tarda unos 10 segundos:

```
→ typecheck…
→ pruebas de interfaz…
✓ typecheck y pruebas en verde.
```

Es el freno de seguridad. Si sale en rojo, **el código no subió** — ve a
[🌙 Lo dejé a medias](#-lo-dejé-a-medias-y-no-compila).

**4 · La confirmación que de verdad importa**

```bash
git status
```

Tiene que decir exactamente esto:

```
On branch main
Your branch is up to date with 'origin/main'.
nothing to commit, working tree clean
```

`up to date` + `clean` = **ya puedes cerrar la laptop**. Todo está en la mochila.

---

## 🟢 LLEGO — abro la otra máquina

**1 · Entrar a la carpeta**

```bash
cd ~/Proyectos/cayla-dynamic
```

**2 · Sacar de la mochila lo que traje**

```bash
git pull
```

**3 · Levantar todo y a trabajar**

```bash
npx pnpm install && npx pnpm dev
```

El `pnpm install` es por si en la otra máquina agregaste una librería nueva.
Si no cambió nada tarda 2 segundos, así que no cuesta correrlo siempre.

> ⚠️ **Hazlo ANTES de escribir la primera línea de código.** El `git pull`
> primero y el código después. Al revés es cuando aparecen los conflictos.

---

## 🌿 ¿Trabajo en `main` o me hago una rama?

La pregunta que decide es una sola:

> **¿Voy a terminar esto antes de cerrar la laptop hoy?**

| Respuesta | Qué hacer |
|---|---|
| **Sí** — es chico, lo empiezo y lo acabo hoy | Directo en `main`. Los 3 comandos de arriba y ya. |
| **No** — cruza días, ciudades, o toca plata | Rama. |

**Ejemplos de "sí, en `main`":** corregir un texto de una pantalla, cambiar un
color, arreglar un cálculo de una línea, actualizar `docs/estado.md`.

**Ejemplos de "no, rama":** una pantalla nueva, una migración de planilla, tocar
provisiones o CTS, cualquier cosa que quieras probar unos días antes de dejarla
fija. En corto: **si un error ahí sale en la plata de alguien, va en rama.**

### Cómo se usa una rama

**Al empezar el trabajo** (una sola vez, en la máquina donde arrancas):

```bash
git switch -c bono-puntualidad
```

El nombre en minúsculas y con guiones, describiendo el trabajo. Desde ese
momento tus commits van ahí y `main` no se toca.

**Al cerrar cada día** — igual que siempre, pero la primera vez agrega `-u`:

```bash
git add -A && git commit -m "avance del bono" && git push -u origin bono-puntualidad
```

De la segunda vez en adelante basta `git push`.

**Al llegar a la otra máquina:**

```bash
git fetch origin && git switch bono-puntualidad
```

**Cuando el trabajo está terminado y probado**, lo fusionas a `main`:

```bash
git switch main && git pull && git merge bono-puntualidad && git push
```

**Y borras la rama**, que ya cumplió:

```bash
git branch -d bono-puntualidad && git push origin --delete bono-puntualidad
```

---

## 🌙 Lo dejé a medias y no compila

Son las 10 p.m., el vuelo sale temprano, el código está a medio hacer y el freno
del `push` no te deja subir. **No lo dejes en la máquina.** Lo mandas como
borrador en su propia rama:

```bash
git switch -c borrador-donde-me-quede
```

```bash
git add -A && git commit -m "borrador: hasta acá llegué"
```

```bash
git push -u origin borrador-donde-me-quede --no-verify
```

`--no-verify` salta el freno a propósito. Es seguro **porque va en una rama
aparte**: `main` sigue verde y sano, y lo que despliegas nunca es esto.

**Al llegar a la otra máquina:**

```bash
git fetch origin && git switch borrador-donde-me-quede
```

Terminas el trabajo, y cuando ya compila lo fusionas a `main` como cualquier
rama normal (arriba está cómo).

> Nunca uses `--no-verify` en `main`. Ahí el freno es lo único que impide que
> suba a producción código que no compila.

---

## 🆘 Se rompió algo

### `git push` dice `rejected` / `non-fast-forward`

Alguien —tú, desde la otra máquina— subió algo que tú no tienes.

```bash
git pull
```

```bash
git push
```

### `git pull` dice `local changes would be overwritten`

Tienes cambios sin guardar que chocan con lo que viene. Guárdalos primero:

```bash
git add -A && git commit -m "cambios de esta máquina"
```

```bash
git pull
```

### `git pull` dice `CONFLICT`

Editaste el mismo archivo en las dos máquinas. Git no adivina cuál gana, así que
te deja los dos textos marcados así dentro del archivo:

```
<<<<<<< HEAD
lo que dice esta máquina
=======
lo que viene de la otra
>>>>>>> origin/main
```

Abre el archivo, deja el texto como debe quedar, borra las tres líneas de
marcas, y luego:

```bash
git add -A && git commit -m "resuelto el conflicto"
```

```bash
git push
```

Si es un conflicto grande o toca plata, **para y pregúntame** — no lo resuelvas
a la carrera.

### Me olvidé del `push` y ya estoy en la otra ciudad

No hay magia: ese trabajo está en el disco de la máquina que dejaste. Dos
salidas, ninguna cómoda:

1. Entrar por Compartir Pantalla a la otra Mac y hacer el `push` desde allá.
2. Rehacerlo acá — y al volver, `git checkout .` en la máquina olvidada para
   descartar lo viejo.

Por eso el paso 4 del cierre es `git status`. Diez segundos que evitan esto.

### Quiero ver qué me traje

```bash
git log --oneline -10
```

---

## 🧰 Máquina nueva — instalación (una sola vez)

Solo la primera vez en una Mac que nunca ha tenido el proyecto.

**Requisitos:** Node 26 y Docker Desktop instalados.

**1 · Entrar a tu cuenta de GitHub y clonar**

```bash
gh auth login && gh repo clone felipea92p-ux/cayla-dynamic ~/Proyectos/cayla-dynamic
```

**2 · Activar el freno de seguridad e instalar todo**

```bash
cd ~/Proyectos/cayla-dynamic && git config core.hooksPath scripts/hooks && npx pnpm install
```

Ese `git config` es fácil de olvidar y sin él el freno del `push` no existe.

**3 · Levantar la base de datos local**

```bash
npx supabase start
```

Cuando termina imprime un `anon key`. **Cópialo**, lo necesitas en el paso 4.

**4 · Armar el archivo de configuración** (este no viaja por git, es de cada máquina)

```bash
printf 'NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321\nNEXT_PUBLIC_SUPABASE_ANON_KEY=PEGA_AQUI_EL_ANON_KEY\n' > apps/web/.env.local
```

**5 · Entrar a Vercel** (solo si vas a desplegar desde esta máquina)

```bash
npx vercel login
```

**6 · Probar que todo quedó bien**

```bash
npx pnpm dev
```

---

## 🗄️ Las migraciones SQL cuando cambias de máquina

Ojo con esto, porque es el punto donde es fácil confundirse:

| Qué | ¿Viaja por git? |
|---|---|
| El **archivo** `supabase/migrations/00NN_*.sql` | ✅ Sí, es texto |
| Los **datos** de tu base local (personas, marcajes de prueba) | ❌ No, viven en el Docker de cada Mac |
| La base de **producción** | 🔵 Ni una cosa ni la otra — está en la nube |

Entonces: si escribiste una migración en la MacBook y llegas a la Mac mini, el
archivo está ahí, pero esa base local no lo ha aplicado nunca. Ponla al día:

```bash
npx supabase db reset
```

Ese comando **borra la base local y la reconstruye desde cero** aplicando todas
las migraciones en orden. Es lo que quieres, y de paso es la mejor prueba de que
la migración nueva no está rota — si tiene un error de sintaxis, revienta ahí y
no en producción. Solo recuerda que los datos de prueba que hayas metido a mano
en esa máquina se van.

Y verifica que las pruebas de base de datos sigan en verde:

```bash
npx supabase test db
```

> ⚠️ En el resumen, `Bad plan. You planned N tests but ran M` **no** es un
> descuadre de conteo: es un archivo que abortó a media ejecución. Las pruebas
> que faltaron nunca verificaron nada.

**El SQL a producción no cambia con esto:** lo sigues pegando tú a mano en el
SQL Editor de Supabase, desde el navegador, desde la máquina que sea. Para eso
no necesitas el repo clonado.

---

## 🚀 Desplegar desde la máquina que sea

Da igual si estás en la MacBook o en la Mac mini. Lo único que cambia es que en
una máquina nueva necesitas `npx vercel login` una vez.

**Vista previa** (dirección temporal, para revisar antes de publicar):

```bash
./scripts/desplegar.sh
```

**Producción** (te pide escribir `publicar` para confirmar):

```bash
./scripts/desplegar.sh prod
```

El script revisa antes de publicar que no haya cambios sin guardar, que GitHub
esté al día y que las pruebas de ese commit hayan pasado — incluidas las de base
de datos. Si algo de eso falla, no publica.

**Producción se avisa siempre.** Lo que ves en pantalla es lo que el equipo usa
para marcar mañana a las 9 a.m.

---

## 📋 Chuleta

Pégala donde la veas.

```
🔴  ME VOY
    git add -A && git commit -m "qué hice"
    git push
    git status        → "up to date" + "clean" = puedo cerrar

🟢  LLEGO
    cd ~/Proyectos/cayla-dynamic
    git pull
    npx pnpm install && npx pnpm dev

🌿  ¿Lo termino hoy?   Sí → main     No → git switch -c nombre-del-trabajo

🌙  A MEDIAS Y NO COMPILA
    git switch -c borrador-algo
    git add -A && git commit -m "borrador"
    git push -u origin borrador-algo --no-verify

🗄️  ¿TRAJE UNA MIGRACIÓN NUEVA?
    npx supabase db reset

🆘  push rechazado  → git pull && git push
    CONFLICT        → arreglar el archivo, git add -A && git commit
```
