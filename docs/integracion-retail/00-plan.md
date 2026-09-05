# Integración Dynamic ↔ CAYLA retail — qué pasó de verdad

**Última revisión: 2026-09-04.** Este documento se escribió el 2026-07-23 como
un plan (el texto original vive en `git show bb6f921:docs/integracion-retail/00-plan.md`
si hiciera falta). Ese mismo día, mientras el plan seguía diciendo
"PLANIFICADO", se ejecutó — pero por un camino distinto y más simple del que
el plan proponía.
Nadie volvió a actualizar el documento, y eso confundió una sesión el
2026-08-31: retomó Fase 0 como si las dos bases siguieran separadas y
persiguió un problema (duplicar personas por DNI) que ya no existe. Este
archivo corrige eso.

## Lo que el plan original asumía, y dejó de ser cierto

El plan partía de "`personas` y `sedes` viven duplicadas en las dos bases
(Dynamic y retail)" y proponía resolverlo con una **API de solo lectura entre
dos proyectos de Supabase distintos**, amarrada por DNI (Fase 2, con dos
opciones: una key de solo lectura o una Edge Function).

Eso describe un problema que el propio 2026-07-23 dejó de existir, por una
ruta distinta a la planeada.

## Lo que en realidad se construyó (2026-07-23, migraciones 0216–0227)

El ERP de tiendas (repositorio `cayla-retail`, desplegado en
`cayla-retail.vercel.app`) **se mudó al mismo proyecto de Supabase que
Dynamic**, a su propio schema (`retail`), aislado por permisos pero en el
mismo Postgres. No hay dos bases: hay dos aplicaciones (`cayla-dynamic` y
`cayla-retail`, dos repos, dos Vercel) hablándole al mismo backend, cada una
pidiendo un schema distinto en el cliente de Supabase.

Con eso, el problema de "mantener sincronizadas dos copias de personas/sedes"
no se resolvió: **dejó de aplicar**. No hay una segunda copia que sincronizar:

- `retail.personas` y `retail.sedes` ([`0218`](../../supabase/migrations/0218_retail_lee_la_identidad_de_dynamic.sql))
  son **vistas** `security_invoker = true` sobre `public.personas` y
  `public.sedes` — la misma fila, no una copia.
- `retail.ventas.usuario_id` ([`0220`](../../supabase/migrations/0220_la_operacion_de_tiendas_entra_al_cajon.sql))
  es una **foreign key directa a `public.personas(id)`** — una venta se
  atribuye por UUID, no por documento.
- Los cuatro candados de RLS de retail (`retail.es_lider()`,
  `retail.es_supervisor()`, `retail.mi_sede()`, `retail.puede_operar_sede()`)
  reusan `public.fn_rol_actual()` y `public.fn_sede_actual_persona()` — una
  sola fuente de identidad, no dos.

**Verificado hoy (2026-09-04) contra Postgres local**, tras fusionar
[`claude/retail-al-historial`](https://github.com/felipea92p-ux/cayla-dynamic/tree/claude/retail-al-historial)
a esta rama:

```
select viewname, reloptions from pg_class ... -- sedes y personas: {security_invoker=true}
select conname, confrelid::regclass from pg_constraint
  where conrelid = 'retail.ventas'::regclass and contype = 'f';
-- ventas_usuario_id_fkey → personas (public.personas)
-- ventas_sede_id_fkey    → sedes    (public.sedes)
```

No hay DNI que amarrar porque no hay nada que amarrar: es la misma fila.

### Por qué esto es mejor que lo que el plan proponía

El plan original quería sincronizar dos copias con una API. Una FK y una
vista `security_invoker` no se pueden desincronizar — no hay copia que se
quede atrás. Es la solución correcta para "dos aplicaciones, una identidad",
y ya está en producción desde julio.

### Lo único fràgil de esta solución (y no tiene arreglo de código)

Retail no copia la identidad — la **lee en vivo** de cuatro cosas de
`public`, y nada avisa si se mueven: `fn_rol_actual()`,
`fn_sede_actual_persona()`, `sedes` (`id`, `codigo`, `nombre`, `activa`) y
`personas` (`auth_user_id`, `nombres`, `apellidos`, `sede_base_id`, `rol`,
`email`). Renombrar cualquiera de esas cuatro cosas revienta las pantallas de
retail sin decir por qué. Ver `docs/estado.md`, sección 2026-08-11. Falta una
prueba de humo que mida ese contrato — está anotada como pendiente ahí, no
acá, para no duplicar el registro.

## Lo que sigue genuinamente abierto: ¿viajaron los DATOS, no el esquema?

Las migraciones 0216-0227 crean el **esquema** de retail — 28 tablas, vacías.
Ninguna copia una fila: no hay `insert into retail.ventas select ...` en
ninguna de las doce. Eso es correcto para lo que esas migraciones prometen
(documentar lo que se pegó), pero deja una pregunta sin responder: cuando el
ERP se mudó el 2026-07-23, **¿el historial de ventas, stock, activos y
proveedores viajó por otro camino (`pg_dump` / `INSERT` manual), o se quedó
atrás?**

Hay una señal concreta de que algo se quedó atrás: Felipe reportó que
`cayla-retail.vercel.app/finanzas/activos` no muestra nada para LIM, aunque
los activos de Lima se habían cargado antes de la mudanza. Puede ser que la
pantalla no los encuentre (la unidad a la que cuelgan cambió de id) o que de
verdad no llegaron. Son dos causas distintas con dos arreglos distintos, y
recargar a mano sin distinguirlas duplica la depreciación.

**`03-donde-quedaron-los-activos.sql`** es el diagnóstico para esto — ver ese
archivo. Es de solo lectura, hecho para correr en el SQL Editor del **mismo**
proyecto de Supabase que usa Dynamic (no hay un "SQL Editor de retail"
distinto: es el mismo Postgres). Trae dos consultas:

1. Busca activos de Lima en cualquier tabla de cualquier schema, por nombre
   de tabla y por contenido (números de serie, marcas de equipo conocidas).
2. Cuenta las filas de las 28 tablas del schema `retail` — si casi todas
   están en cero, no se perdió una pantalla: se perdió la migración de datos
   entera, y eso se atiende antes que cualquier carga nueva.

**Esto todavía no se ha corrido.** Es lo próximo, y solo lo puede correr
Felipe (SQL a producción se pega a mano — ver `CLAUDE.md`). Cuando tenga la
salida, se decide desde ahí si hace falta recuperar de un backup o si el dato
está y solo hay que arreglar la pantalla.

## Qué NO hace falta ya (lo que este plan proponía y ya no aplica)

- ❌ **Fase 0 / Fase 1 del plan original** — reconciliar `personas`/`sedes`
  entre "dos bases" por DNI. No hay dos bases ni DNI que amarrar (ver
  arriba). `01-reconciliacion.sql` se recortó: solo queda el bloque de
  higiene de DNI *dentro* de Dynamic, que sigue siendo útil por sí solo
  (formato, duplicados, gente sin documento) — nada de eso tiene que ver ya
  con retail.
- ❌ **Fase 2 / `02-vista-personas-DRAFT.sql`** — proponía crear
  `v_personas_publica` / `v_sedes_publica` para una API entre proyectos. Ese
  borrador **nunca se aplicó**, y está bien que no se aplicara: medido el
  2026-08-11, nace escribible por cualquier sesión con login (le falta
  `security_invoker`) y expone el DNI de todas a cualquier integrante — el
  archivo se conserva con su advertencia porque es una lección real sobre
  vistas auto-actualizables, no porque haga falta terminarlo. Lo que
  reemplaza a Fase 2 ya está aplicado: `retail.personas` / `retail.sedes`
  (0218), que sí llevan `security_invoker = true`.
- ❌ Las Opciones A/B de acceso ("key de solo lectura" / "Edge Function")
  — no hacían falta: al vivir en el mismo Postgres, el acceso lo resuelven
  RLS + grants de schema, no una API.

  Nota aparte: **las dos sesiones que tocaron esto (2026-07-23 y
  2026-08-11) trabajaron el mismo problema sin verse** — la del 08-11
  escribió la advertencia de seguridad sobre el DRAFT el mismo día que la
  migración 0218 (con la versión ya segura) entraba al historial de este
  repo. Es el caso exacto que `CLAUDE.md` pide evitar mirando
  `git log --all` antes de empezar — no costó nada esta vez porque la
  versión insegura nunca se aplicó, pero es la misma trampa.

## Archivos de esta carpeta

| Archivo | Qué es hoy |
|---|---|
| `00-plan.md` | Este archivo. |
| `01-reconciliacion.sql` | Recortado a higiene de DNI *dentro* de Dynamic. Ya no compara contra retail. |
| `02-vista-personas-DRAFT.sql` | Histórico — nunca se aplicó, y no hace falta. Se conserva por la lección de seguridad (vista sin `security_invoker` = escribible). |
| `03-donde-quedaron-los-activos.sql` | **El diagnóstico pendiente de verdad.** Solo lectura. Falta que Felipe lo corra en el SQL Editor de Supabase y pegue la salida. |

## Cómo seguimos

Dime **"corrí el diagnóstico de activos"** con la salida de
`03-donde-quedaron-los-activos.sql` pegada, y desde ahí se decide si hace
falta recuperar algo de un backup o si el dato está y es la pantalla la que
no lo encuentra.
