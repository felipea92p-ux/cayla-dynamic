# Parche propuesto 05 — datos reales del equipo fuera del patrón de gitignore

## ✅ Actualización 2026-07-16 — aplicado, con una corrección importante al diagnóstico

**El supuesto de este documento ("el repo todavía no se subió a GitHub") era
incorrecto.** Al hacer la limpieza se encontró que el repo ya tiene un
remoto configurado (`github.com/felipea92p-ux/cayla-dynamic`) y que
`origin/main` ya tenía estos archivos, incluido el commit original que los
agregó (10-jul) — la rama local estaba 26 commits adelante sin subir.
Confirmado en vivo con Felipe (captura de GitHub): el repo es **privado**,
un solo colaborador — el riesgo real es bajo, no es una fuga pública, pero
el historial ya subido sigue teniendo los datos (ver "Pendiente" abajo).

Además del `git grep` de esta noche, una segunda pasada encontró **2
archivos más** con nombres reales hardcodeados que no se habían detectado:
`scripts/setup-horarios-prod.mjs` (horarios por persona) y
`scripts/migracion-historica/aplicar-config.mjs` (ajustes puntuales de
sede/horario). Se limpiaron con el mismo patrón.

**Aplicado (solo en el working tree local, sin commit ni push):**
- Los 4 archivos originales + los 2 nuevos ahora leen los datos reales desde
  JSON en `scripts/datos-privados/` (gitignorado) en vez de tenerlos
  hardcodeados.
- `roster-actual.json` se movió físicamente a `datos-privados/` y se sacó
  del tracking con `git rm --cached`.
- Verificado con `git grep` que ningún archivo trackeado fuera de `docs/`
  contiene ya los nombres reales del equipo.

**Pendiente — requiere tu decisión, sin apuro dado que el repo es
privado:** los commits viejos en `origin/main` (ya en GitHub) siguen
teniendo los datos reales en su historial, aunque las versiones nuevas de
los archivos ya no. Ver "Paso 3" más abajo para las dos opciones. Tampoco se
hizo ningún `git add`/commit/push de esta limpieza — eso queda para cuando
tú lo revises y decidas.

---

Hallazgo original (reporte E), verificado con `git ls-files` — estos 4
archivos SÍ estaban comiteados (no solo presentes en disco):

```
scripts/setup-personas-prod.mjs        (roster completo + correo personal de Felipe, línea 23)
scripts/migracion-historica/roster-actual.json
scripts/migracion-historica/importar-turnos-tru.mjs
scripts/migracion-historica/reimportar-lim-aqp.mjs
```

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
