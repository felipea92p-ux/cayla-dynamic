# Parche propuesto 05 — datos reales del equipo fuera del patrón de gitignore

Hallazgo (reporte E), verificado esta noche con `git ls-files` — estos 4
archivos SÍ están comiteados (no solo presentes en disco):

```
scripts/setup-personas-prod.mjs        (roster completo + correo personal de Felipe, línea 23)
scripts/migracion-historica/roster-actual.json
scripts/migracion-historica/importar-turnos-tru.mjs
scripts/migracion-historica/reimportar-lim-aqp.mjs
```

**Buena noticia, confirmada:** el repo todavía **no se subió a GitHub** (es
el pendiente "Subir el código a GitHub" que ya tenías anotado) — todo esto
vive solo en tu Mac + iCloud, no en un remoto público/compartido todavía.
Es el mejor momento posible para arreglarlo: antes de subir es un cambio
simple; después de subido, hay que reescribir historia (mucho más delicado,
puede romper cualquier clon existente).

**No apliqué nada de esto** — mover archivos y reescribir historia de git
son cosas que te toca decidir y ejecutar a ti (o pedírmelo explícitamente
mañana con calma, no es algo para hacer de madrugada sin que estés mirando).

## Paso 1 — mover los datos reales a `scripts/datos-privados/` (ya gitignorado)

Mismo patrón que ya usan `actualizar-correos-prod.mjs` /
`crear-cuentas-encargadas.mjs`:

1. Crear `scripts/datos-privados/roster.json` con el array `ROSTER` que hoy
   está hardcodeado en `scripts/setup-personas-prod.mjs` (nombres, sede,
   rol, email).
2. Editar `setup-personas-prod.mjs` para que lea ese JSON
   (`JSON.parse(fs.readFileSync("./scripts/datos-privados/roster.json"))`)
   en vez de tener el array en el código — y borrar el correo personal
   hardcodeado de la línea 23.
3. Mover `scripts/migracion-historica/roster-actual.json` a
   `scripts/datos-privados/roster-actual.json` y actualizar el import/path
   en los scripts que lo usan.
4. Revisar `importar-turnos-tru.mjs` y `reimportar-lim-aqp.mjs` por
   nombres reales hardcodeados y extraerlos al mismo JSON de
   `datos-privados/`.

## Paso 2 — sacarlos del tracking de git (no solo del working tree)

Una vez movidos, hay que decirle a git que los olvide (si no, siguen en el
índice aunque el contenido cambie):
```
git rm --cached scripts/setup-personas-prod.mjs scripts/migracion-historica/roster-actual.json scripts/migracion-historica/importar-turnos-tru.mjs scripts/migracion-historica/reimportar-lim-aqp.mjs
```
(el `--cached` borra del índice de git, NO del disco — los archivos siguen
donde están, solo dejan de trackearse si ya los recreaste sin PII en el
paso 1, o los vuelves a agregar limpios).

## Paso 3 — decidir sobre la HISTORIA ya comiteada

Los commits viejos (por ejemplo el que originalmente agregó
`setup-personas-prod.mjs` con el roster real) siguen teniendo esos datos
adentro aunque hagas los pasos 1-2 — `git log -p` sobre esos archivos
todavía los mostraría. Como el repo nunca se subió a GitHub, tienes dos
caminos razonables, sin apuro porque no hay nadie más con acceso todavía:

- **Opción simple:** dejarlo así (historia local con PII, pero nunca sale
  de tu Mac/iCloud) y solo asegurarte de que las versiones NUEVAS de estos
  archivos, de acá en adelante, no tengan datos reales. Razonable si tu
  plan es que el repo en GitHub sea PRIVADO (solo tú, o tu organización) —
  el riesgo de fondo baja mucho.
- **Opción más limpia:** reescribir la historia local antes del primer push
  (`git filter-repo --path scripts/setup-personas-prod.mjs --path scripts/migracion-historica/roster-actual.json --path scripts/migracion-historica/importar-turnos-tru.mjs --path scripts/migracion-historica/reimportar-lim-aqp.mjs --invert-paths`
  o equivalente), para que ni siquiera la historia local tenga el dato. Más
  laborioso, y **reescribe todos los hashes de commit** — mejor hacerlo
  conmigo presente y con calma un día que no tengas prisa, no es algo para
  correr sin supervisión.

## Recomendación

Antes de que le digas a alguien "sube" (el comando que dispara subir a
GitHub), como mínimo hacer los pasos 1-2 — así el repo que se sube desde
ese momento en adelante ya nace limpio. La decisión de reescribir o no la
historia previa puede esperar a que decidas si el repo en GitHub va a ser
privado o público.
