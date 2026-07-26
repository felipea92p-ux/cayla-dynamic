# CAYLA Dynamic — cómo se trabaja en este repo

App de asistencia y planilla de CAYLA. Sedes **TRU · LIM · AQP**, ~23 integrantes.
En producción y en uso real todos los días: **cayla-dynamic.vercel.app**.

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

**Antes de dar cualquier SQL que toque plata, se audita empíricamente.**
Contra el Postgres local, dentro de `BEGIN … ROLLBACK`, con casos reales. No se
entrega un cálculo de planilla, provisiones, bonos o CTS "revisado a ojo".

**Desplegar a producción se pregunta SIEMPRE.**
```bash
npx vercel --prod --yes    # solo con OK explícito de Felipe
```
Vista previa sin permiso: `npx vercel --yes`.

**Ojo con el entorno.** `apps/web/.env.local` apunta al Supabase **local**
(127.0.0.1), no a producción. Para diagnosticar prod, Felipe corre SELECTs en el
SQL Editor. Nunca asumir que lo que se ve en local es lo que pasa en prod.

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
packages/shared/     esquemas zod, máquina de estados de asistencia, enums, etiquetas
packages/database/   tipos generados de Supabase + cliente tipado
supabase/migrations/ el esquema, una migración por cambio
scripts/sql-manual/  la versión lista para pegar en el SQL Editor
docs/                referencia (ver abajo)
```

Backend: **Supabase** (Postgres + Auth + RLS + pg_cron). Hosting: **Vercel**.
Monorepo con pnpm + Turborepo.

```bash
npx pnpm install
npx pnpm dev          # levanta todo
npx pnpm typecheck
npx pnpm test         # vitest
```

---

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

---

## Qué hay en `docs/`

| Ruta | Qué es |
|---|---|
| `estado.md` | **Dónde estamos hoy.** Se sobrescribe, no se acumula. |
| `terminales-mac-mini.md` | Manual para dejar la Mac mini de una sede como terminal. |
| `disciplina-tardanzas-faltas/` | Marco legal peruano, plantillas de cartas, RIT. |
| `revision-2026-07-15/` | Auditoría de seguridad. Vive hasta cerrar sus pendientes. |
| `integracion-retail/` | Plan del puente con retail. Aún no arranca. |
| `plan.md` | **Documento histórico** (jul 2026, antes de construir). Buen contexto del porqué; su estructura de carpetas y su roadmap ya no describen el sistema actual. |

**No crear documentos de estado con fecha en el nombre.** Ese hábito produjo cinco
archivos que se contradecían entre sí. Si algo cambió, se edita `estado.md`.

---

## La red de seguridad (jul-2026)

**Antes de subir a GitHub** corre solo un hook (`scripts/hooks/pre-push`) que
verifica `typecheck` y las pruebas de interfaz. Si algo está en rojo, el push no
se hace. Toma unos 10 segundos.

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
pruebas de GitHub de ese commit hayan pasado — **incluidas las de base de datos
(pgTAP), que no corren en esta Mac porque necesitan Docker** — y recién ahí
publica. Para producción pide escribir `publicar` como confirmación.

En una urgencia real ambos se saltan: `git push --no-verify` y `npx vercel --prod`.
Que se pueda saltar a propósito es parte del diseño; que se salte sin querer, no.
