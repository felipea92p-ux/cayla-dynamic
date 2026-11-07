---
name: abrir-pr
description: Abre un PR de Dynamic sin choques escondidos. Antes de `gh pr create` trae main, compara la rama contra main y contra los PR abiertos (mismo número de migración, la misma función SQL reescrita desde dos versiones, los archivos de registro compartidos), corre las pruebas que toca el cambio y abre el PR con los choques probables escritos. Úsala cuando una sesión vaya a abrir un PR y cuando Felipe diga «abre el PR», «sube esto» o «/abrir-pr». No fusiona ni activa la fusión automática.
---

> Adaptada de `abrir-pr` de `cayla-retail` (2026-11-06). Lo que cambió: aquí no hay reservas de número ni parches anclados, y el choque que importa
> es el de la 0261: dos PR que reescriben la misma función desde la misma versión pasan cada uno en verde, y juntos el de número mayor revierte al otro.

Abre el PR de la rama actual: $ARGUMENTS

**Por qué existe.** Git solo marca conflicto si dos cambios tocan las mismas líneas, y dos migraciones que reescriben `fn_planilla_calcular` no se tocan. El ruleset de `main` tiene `strict=false`: cada PR se prueba contra el `main` de ese momento, así que ninguna prueba ve los dos juntos antes de publicar. Esta skill los busca antes de abrir el PR. Avisa y no fusiona nada.

**Antes de empezar:** abrir el PR tiene que haberlo pedido Felipe. Si el cambio es del rediseño de vidrio, además necesita su aprobación en local: un PR abierto para «dejarlo listo» ya es subirlo.

## 1. La rama, limpia y al día

1. `git status --short` vacío: todo commiteado.
2. Trae `main` con `sync_with_base_branch` (en un worktree de la app) y resuelve los conflictos de verdad. Commitea el merge.
3. `git config --show-origin --get core.hooksPath` debe decir `scripts/hooks`. Si devuelve una ruta absoluta, los guardianes que corren son los del checkout principal. Empuja con `git -c core.hooksPath=scripts/hooks push`.

## 2. Los choques

```bash
bash .claude/skills/abrir-pr/choques.sh
```

Léelo entero y actúa según la gravedad:

- **🔴 SEGURO** (sale con código 1): el mismo número de migración que `main` u otro PR, o una función tuya que `main` ya cambió. **No abras el PR así.** Renumera con `./scripts/siguiente-numero.sh`, o reconstruye desde la versión vigente con `./scripts/donde-vive.sh`. Si la migración ya se pegó en producción, para y pregúntale a Felipe.
- **🟠 PROBABLE:** la misma función en otro PR abierto. Mira su migración (`git show origin/<su rama>:<archivo>`). El que se fusione segundo tiene que partir del cuerpo del primero: dilo en la descripción y avísale a Felipe. No reescribas la migración del otro.
- **🟠 PROBABLE, archivo de registro:** dos entradas nuevas en `novedades.ts`, `nav-items.ts` o `que_falta_pegar.sql`. Casi siempre se resuelve solo al fusionar. Revisa que los `id` no choquen.
- **ℹ archivos en común:** solo para saber con quién hablar.

Si `gh` no responde, el script lo dice y sale con código 2: «no pude mirar» no es «no hay choques».

## 3. Las pruebas que toca el cambio

1. `npx pnpm typecheck` y `npx pnpm test`, si el push no los va a correr (el hook sí corre el typecheck y las pruebas de interfaz).
2. Si tocas migraciones o `supabase/tests/`: la prueba pgTAP de lo que cambiaste, aislando la deriva como dice `CLAUDE.md` (`begin … rollback`, nunca `db reset`) y con su control. La señal fiable es `db-tests` en GitHub.
3. Si toca plata: la auditoría empírica ya tiene que estar hecha y dicha en la descripción.

## 4. Abrir el PR

`gh pr create --base main`, con título en español que diga qué cambia, y esta descripción:

```
## Qué cambia
(2 a 5 líneas de negocio, no de código)

## Cómo se verificó
(los comandos y lo que dieron)

## Choques probables
(lo 🟠 del paso 2, con el número del otro PR; o «Ninguno: choques.sh sin choques seguros ni probables»)

## SQL
(«No hay», o qué migración es, si ya se pegó y quién lo confirmó)
```

Termina con la línea de atribución que pida el sistema. Después, `get_status` de las herramientas `ccd_pr` y, si no reporta el PR, `bind_pr`.

## 5. Mientras espera

- **No actives la fusión automática ni fusiones:** fusionar es publicar, y lo pide Felipe para ese PR. Comprueba `gh pr view N --json autoMergeRequest`: tiene que dar `null`.
- Antes de fusionar, una sesión comenta en el PR con la marca `<!-- cayla:fusion-sesion -->`; el hook te frena si falta.
- Si aparece un PR nuevo, corre `choques.sh` otra vez antes de pedirle a Felipe que fusione.
