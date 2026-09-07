# Plan de apariencia — 2026-09-06

**Documento fechado, como `plan-2026-07-25.md` o `analisis-estructura-remunerativa-2026-07-30.md`.**
Es el plan de trabajo para modernizar la apariencia del panel admin, escrito para que
**otra sesión de Claude Code lo ejecute** sin releer esta conversación. Sale de un
workflow de 21 agentes: 5 investigaron+revisaron por categoría (botones, tablas,
formularios, navegación, dashboards), 2 auditaron colores sueltos y el terminal, 3
propusieron direcciones visuales, 3 jueces las evaluaron de forma independiente, y 3
redactaron y criticaron el plan. Todo lo citado abajo (rutas, líneas, conteos) viene de
lectura real del código, no de suposición — y varios de los datos más sensibles
(existencia de `.aletea`, hooks activos, `.env.local`) se **re-verificaron a mano**
contra este worktree antes de escribir este documento.

**Qué NO es esto:** no toca cálculo de planilla, horas, tardanzas ni sobretiempo. Es
puramente apariencia — CSS, componentes compartidos, JSX de presentación.

---

## Diagnóstico en una frase

El panel tiene una identidad de marca deliberada y ya buena (9 tokens de color, DM
Sans + EB Garamond, el colibrí) y hasta 5 primitivos compartidos ya escritos
(`Boton`, `Tabla`, `Insignia`, `AreaTexto` en `apps/web/components/ui/`) — pero **casi
nadie los usa**: solo 7-8 de ~40 pantallas los importan, mientras el resto copia a
mano las mismas clases con pequeñas divergencias reales (7 escalas de radio de
esquina conviviendo sin criterio, opacidades de `disabled` distintas, z-index de
modal en `10`/`20`/`40`/`50`, foco de teclado en solo 2-9 de ~40 archivos). El
problema no es "la marca se ve vieja" — es que el sistema de diseño que ya existe
nunca terminó de adoptarse, y esa adopción a medias es lo que se lee como
inconsistencia.

## Las tres direcciones evaluadas (resumen)

Pediste explícitamente un rango entre "evolucionar" y "libertad total", así que se
generaron y evaluaron tres:

| Dirección | Qué propone | Ranking (3 jueces, 4 criterios c/u, máx 40) |
|---|---|---|
| **Evolución cálida** | Cero cambios de rol de color; solo nombra radios/espaciado/tipografía que hoy son ad-hoc, sube verde/ámbar del límite exacto de AA a >6:1, agrega foco de teclado y un estado "cargando" con el colibrí | 32 |
| **Evolución audaz** | Igual que la anterior + 2 tokens nuevos (`hueso` = superficie hundida para inputs, `pizarra` = estado "informativo/en proceso") + elevación real vía borde+tono, sin sombras | 30 |
| **Obsidiana** ("libertad total") | Paleta fría nueva, reemplaza DM Sans por Inter, reintroduce sombras y gradiente, retira EB Garamond de las pantallas de trabajo | 21.7 |

Los tres jueces (marca, funcionalidad, factibilidad) recomendaron **Evolución
audaz**, no la de mayor puntaje bruto: es la única que cierra huecos funcionales
reales medidos (falta de un segundo nivel de elevación más allá del 3-5% de
luminosidad crema/papel; `Insignia` sin variante "informativo") sin romper el
terminal ni la identidad. Obsidiana quedó descartada para esta ejecución — los tres
jueces coinciden en que exige alias de compatibilidad de alto riesgo para no romper
el kiosco (que comparte los mismos tokens de color, en producción real en 4 sedes) y
que una migración a medias, en sus propias palabras, "sería peor que no tocar
nada".

## La dirección final no es "Audaz tal cual" — se verificó y se corrigió

Antes de aceptar los valores hex de Audaz, se auditaron empíricamente contra la
fórmula de contraste relativo WCAG (mismo criterio que este repo exige para
planilla: medir, no asumir). Resultado: **el ámbar y el taupe que proponía Audaz
reprueban** — su `--color-ambar` da 3.94:1 sobre crema (peor que el actual 4.51:1) y
su `taupe` sobre `sand` da 3.60:1 (peor que el 4.50:1 actual). Los de "Evolución
cálida", en cambio, sí pasan (6.13:1 y 6.37:1).

**Dirección final = síntesis, ya verificada:**
- `--color-verde` y `--color-ambar`: se usan los valores de **Evolución cálida**
  (únicos que pasan la verificación).
- `--color-taupe`, `--color-sand`, `--color-papel`, `--color-tinta`, `--color-rojo`,
  `--color-rojo-profundo`: **no se tocan**. Esto además responde de raíz la
  objeción de los tres jueces ("¿se verificó el terminal, que comparte estos
  tokens?"): si no se retunan, el kiosco no puede verse afectado por este cambio,
  salvo verde/ámbar — que sí se revisan a ojo en el paso final.
- `--color-hueso` (nuevo, superficie hundida) y `--color-pizarra` (nuevo, estado
  informativo): se agregan tal como los definió Audaz, con sus valores ya
  verificados (≥4.5:1 en los pares relevantes).

Esto implica editar **una frase de `CLAUDE.md`**: pasa de "nueve" a "once" tokens.
Es un cambio a una convención marcada como no negociable — **el Día 1 tiene un
punto de pausa explícito para esto, no se hace en silencio** (ver paso 3 abajo).

---

## Dos jornadas, no una

El primer borrador de este plan intentaba fundamentos + aplicación en una sola
sesión; el propio agente crítico del workflow lo marcó como no realista (Fase 2 ya
se autolimita a "una jornada completa" para 3-4 pantallas piloto, y dependía de dos
componentes — `Modal` y `CabeceraPagina` — que Fase 1 nunca creaba). Se separan:

- **Día 1 (mañana):** Fase 1 — Fundamentos. Solo toca `globals.css` y
  `apps/web/components/ui/`, más una pantalla piloto para probar el conjunto.
- **Día 2 (después):** Fase 2 — Aplicación a 3 pantallas piloto reales.

---

## Día 1 — Fundamentos

### Paso 0 — Chequeo de colisión

```bash
git log --all --oneline -20
git grep -l "radius-control\|color-hueso\|color-pizarra" $(git for-each-ref --format='%(refname)' refs/heads refs/remotes)
```
Confirmar que ninguna otra rama está tocando `globals.css`, `boton.tsx`, `tabla.tsx`
o `insignia.tsx` en paralelo (cultura del repo: varias sesiones comparten árbol).

### Paso 0.5 — Preparar el entorno local (nuevo, no estaba en el borrador)

`apps/web/.env.local` **hoy no existe en este worktree** (verificado). Sin él,
cualquier pantalla revienta con "supabaseUrl is required" al abrir el navegador, y
el síntoma no se nota como problema de entorno. Antes de depender de
`npx pnpm dev` en los pasos de verificación de abajo:

```bash
npx supabase start        # levanta la pila completa, no solo la base
npx supabase status       # de acá salen las claves
```
Crear `apps/web/.env.local` con `NEXT_PUBLIC_SUPABASE_URL` y
`NEXT_PUBLIC_SUPABASE_ANON_KEY` de esa salida.

### Paso 1 — Criterio (ya resuelto, no hay que redecidir diseño)

Ver sección "La dirección final" arriba. Este paso es solo la nota de por qué los
pasos 2 en adelante usan los valores que usan.

### Paso 2 — `globals.css`: tokens nuevos, retunes verificados, radios y foco

Dentro de `@theme`, cambiar SOLO estas dos líneas existentes y agregar seis nuevas
— **usar `--radius-*` (inglés), no `--radio-*`**: es la convención de Tailwind v4
para que `@theme` genere automáticamente las utilidades `rounded-control`,
`rounded-superficie`, etc. sin colisionar con `rounded-sm/md/lg` nativos:

```css
--color-verde: #48603f;   /* antes #5b754f, 4.51:1 (límite AA) → 6.13:1 verificado */
--color-ambar: #74501a;   /* antes #8d6726, 4.51:1 → 6.37:1 verificado */
--color-hueso: #eae1d2;   /* NUEVO: superficie hundida — inputs, zebra de tabla */
--color-pizarra: #55677a; /* NUEVO: informativo/en proceso — "programado", "borrador", "pendiente de firma" */

--radius-control: 0.625rem;    /* 10px: botones, inputs, selects, badges cuadrados */
--radius-superficie: 1rem;     /* 16px: tarjetas y el contenedor de Tabla (mismo valor que rounded-2xl de hoy, con nombre) */
--radius-flotante: 1.25rem;    /* 20px: modales, dropdowns, popovers, Cmd+K */
--radius-pildora: 999px;       /* insignias, avatares */
```

En **las dos** redefiniciones de modo oscuro (`@media (prefers-color-scheme: dark)
{ :root:not([data-tema="claro"]) {...} }` **y** `:root[data-tema="oscuro"] {...}`
— nunca solo una, o el toggle de tema queda roto en una sola dirección) agregar:

```css
--color-hueso: #15110d;
--color-pizarra: #9db0c2;
```
Verde y ámbar oscuros no cambian (ya dan 6.26:1 y 6.79:1 — sobra margen).

**No tocar** el bloque `@media print` al final del archivo — la boleta/contrato se
imprimen siempre en paleta clara fija, a propósito.

Dentro de `@layer base`, agregar una sola regla de foco de sistema (hoy solo 2-9 de
~40 archivos definen algún foco visible):

```css
:focus-visible {
  outline: 2px solid var(--color-rojo);
  outline-offset: 2px;
}
```

**Verificación:** `npx pnpm typecheck` limpio. Abrir cualquier pantalla en claro y
oscuro y confirmar que Tab muestra un contorno rojo en cada control.

### Paso 3 — PAUSA: `CLAUDE.md`, de nueve a once tokens

`CLAUDE.md` dice literalmente "nueve `--color-*`... toda la pantalla se pinta con
esos nueve". Es una regla marcada como no negociable. **Antes de editar este
archivo, la sesión que ejecute este plan debe decirlo en el chat y esperar un "sí"
explícito de Felipe** — no asumir aprobación tácita por seguir la sesión. (Este es
el punto que el crítico del workflow marcó como el más importante: notificarlo en
el mensaje de commit no es lo mismo que pedir permiso antes.)

Con el OK: editar la frase a "once", agregar una línea explicando qué son `hueso` y
`pizarra` y por qué existen, mismo tono documental que el resto del archivo.

### Paso 4 — `Boton`: radio, foco, transición y estado `cargando`

**Verificado contra el código real:** `.colibri` y `.aletea` **ya existen** en
`globals.css` (líneas 104-127) y ya son la convención de carga de toda la casa —
los usan `Cargando`/`EsqueletoTabla` (`components/cargando.tsx:26`) y
`app/loading.tsx`, y el propio terminal los llama "el estado de carga de toda la
casa" en un comentario. **No hace falta CSS nuevo** — ignorar cualquier propuesta
de un `@keyframes aletea` distinto (una de las direcciones evaluadas proponía uno
con `opacity`/`scaleY` en vez de `translateY`): colisionaría de nombre con el que
ya usa medio sistema y le cambiaría la animación sin querer.

Editar `apps/web/components/ui/boton.tsx`:

```tsx
const CHROME: Record<Variante, string> = {
  primario: "rounded-control bg-tinta text-crema transition-colors duration-150 hover:bg-rojo-profundo active:scale-[0.98]",
  secundario: "rounded-control border transition-colors duration-150 hover:border-taupe/40 hover:bg-sand/50 active:scale-[0.98]",
  peligro: "rounded-control border border-rojo/30 text-rojo transition-colors duration-150 hover:bg-rojo/10 active:scale-[0.98]",
  sutil: "rounded-control border border-sand text-taupe transition-colors duration-150 hover:text-tinta hover:bg-sand/30 active:scale-[0.98]",
  enlace: "underline underline-offset-2 transition-colors duration-150 hover:text-taupe",
};
```

Agregar `cargando?: boolean` que deshabilita el botón y muestra el colibrí:

```tsx
type Props = { variante?: Variante; tamano?: Tamano; cargando?: boolean } & ButtonHTMLAttributes<HTMLButtonElement>;

export function Boton({ variante = "secundario", tamano = "md", cargando = false, disabled, className, children, ...props }: Props) {
  return (
    <button
      disabled={disabled || cargando}
      className={cx(CHROME[variante], variante !== "enlace" && TAMANOS[tamano], "font-medium disabled:opacity-50", className)}
      {...props}
    >
      {cargando && <span className="colibri aletea mr-1.5 inline-block size-3.5 align-[-2px]" aria-hidden />}
      {children}
    </button>
  );
}
```

Unificar `disabled:opacity-50` como único valor (hoy `disciplina/page.tsx` usa
`-40` suelto — se corrige al migrar esa pantalla, en Día 2 o después).

**No usar el prop `cargando` en ningún archivo de `apps/web/app/(terminal)/`** — el
terminal no importa `Boton`. Confirmar con
`grep -rn "from.*ui/boton" "apps/web/app/(terminal)"` (debe salir vacío) antes de
cerrar este paso.

**Verificación:** `npx pnpm typecheck` limpio. Botón con `cargando` (en la
pantalla piloto del paso 10) muestra el colibrí aleteando.

### Paso 5 — `Tabla`: radio con nombre, header pegajoso, fila con zebra

Editar `apps/web/components/ui/tabla.tsx`, tres cambios aditivos:

```tsx
// 1. Tabla: rounded-2xl → rounded-superficie (mismo valor, 16px, ahora con nombre)

// 2. TablaEncabezado: pegajoso
export function TablaEncabezado({ children }: { children: ReactNode }) {
  return (
    <thead className="sticky top-0 z-10 bg-sand/85 text-left text-taupe">
      <tr>{children}</tr>
    </thead>
  );
}

// 3. Nuevo export Fila — no reemplaza los <tr> existentes (eso es Día 2),
//    da un patrón listo para adoptar pantalla por pantalla
export function Fila({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <tr className={cx("border-t border-sand transition-colors duration-150 even:bg-hueso/50 hover:bg-crema/60", className)}>
      {children}
    </tr>
  );
}
```

**Verificación:** header se queda fijo al hacer scroll; radio de 16px sin cambio
visual.

### Paso 6 — `Insignia`: variantes "positivo" e "informativo"

Hoy `Insignia` no distingue "presente" (verde) de "programado/en revisión/borrador"
(se apila en `sand` neutro) — hueco real medido en 3 de las 5 categorías
investigadas. Editar `apps/web/components/ui/insignia.tsx`:

```tsx
type Variante = "neutral" | "alerta" | "advertencia" | "positivo" | "informativo";

const TONOS: Record<Variante, string> = {
  neutral: "bg-sand text-tinta",
  alerta: "bg-rojo/10 text-rojo",
  advertencia: "bg-ambar/15 text-ambar",
  positivo: "bg-verde/15 text-verde",        // NUEVO
  informativo: "bg-pizarra/15 text-pizarra", // NUEVO
};
```
Y agregar un punto de color antes del texto (ayuda a quien no distingue bien verde
de ámbar por matiz) + `rounded-full` → `rounded-pildora`:

```tsx
<span className={cx("inline-flex items-center gap-1.5 whitespace-nowrap rounded-pildora px-2 py-0.5 text-xs", atenuada ? "bg-sand text-taupe" : TONOS[variante], className)}>
  <span className="size-1.5 rounded-full bg-current" aria-hidden />
  {children}
</span>
```

### Paso 7 — `Campo` y `CampoSelect`: el primer input/select compartido

Hoy no existe ninguno — cada pantalla escribe `rounded-lg border px-3 py-2` a mano
(100+ veces medidas en 16+ archivos). Crear
`apps/web/components/ui/campo.tsx` con **ambos** en el mismo archivo (un solo
nombre de componente por tipo de control, para que Día 2 no tenga que adivinar):

```tsx
import type { InputHTMLAttributes, SelectHTMLAttributes, ReactNode } from "react";
import { cx } from "./cx";

type BaseProps = { etiqueta?: string; error?: string };

export function Campo({ etiqueta, error, id, className, ...props }: BaseProps & InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="flex flex-col gap-1.5">
      {etiqueta && <span className="text-xs font-medium uppercase tracking-[0.06em] text-taupe">{etiqueta}</span>}
      <input
        id={id}
        className={cx(
          "rounded-control border border-sand bg-hueso px-3 py-2 text-sm text-tinta transition-colors duration-150 placeholder:text-taupe/60",
          error && "border-rojo",
          className,
        )}
        {...props}
      />
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}

export function CampoSelect({ etiqueta, error, id, className, children, ...props }: BaseProps & SelectHTMLAttributes<HTMLSelectElement> & { children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      {etiqueta && <span className="text-xs font-medium uppercase tracking-[0.06em] text-taupe">{etiqueta}</span>}
      <select
        id={id}
        className={cx(
          "appearance-none rounded-control border border-sand bg-hueso bg-[url('data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 20 20%22 fill=%22%23805c4c%22><path d=%22M5.5 7.5l4.5 4.5 4.5-4.5%22 stroke=%22%23805c4c%22 stroke-width=%221.5%22 fill=%22none%22/></svg>')] bg-[right_0.6rem_center] bg-no-repeat px-3 py-2 pr-8 text-sm text-tinta transition-colors duration-150",
          error && "border-rojo",
          className,
        )}
        {...props}
      >
        {children}
      </select>
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}
```

El foco lo cubre la regla global `:focus-visible` del paso 2. **Si `Campo` se usa
para un `input[type="date"]` cuyo vacío bloquea el envío, la regla de CLAUDE.md
sigue aplicando igual** — nace con un valor, nunca con `value=""` (vigilado por
`scripts/hooks/fecha-que-bloquea.sh`); `Campo` no lo resuelve solo, quien lo use
debe seguir esa regla.

### Paso 8 — `Modal`: componente compartido (nuevo — no estaba en el borrador)

El crítico del workflow marcó que Día 2 exigía un `Modal` compartido que ningún
paso creaba. Hoy hay 5-8 implementaciones manuales de `fixed inset-0 ... bg-black/40`
con z-index inconsistente (`z-10`/`20`/`40`/`50`). Crear
`apps/web/components/ui/modal.tsx`, con un solo z-index y un solo scrim:

```tsx
"use client";
import { useEffect, useRef, type ReactNode } from "react";

export function Modal({ abierto, onCerrar, titulo, children }: {
  abierto: boolean; onCerrar: () => void; titulo?: string; children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!abierto) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onCerrar(); };
    document.addEventListener("keydown", onKey);
    ref.current?.focus();
    return () => document.removeEventListener("keydown", onKey);
  }, [abierto, onCerrar]);

  if (!abierto) return null;
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4" onClick={onCerrar}>
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-label={titulo}
        tabIndex={-1}
        className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-flotante border border-taupe/35 bg-papel p-6 outline-none"
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </div>
    </div>
  );
}
```

`bg-black/40` (no `bg-tinta/NN`, que se aclara mal en modo oscuro) y `z-40` son a
propósito: son el patrón que CLAUDE.md ya documenta como decidido desde agosto
2026 para los scrims. `border-taupe/35` + `rounded-flotante` (20px, más grande que
`rounded-superficie`) son la segunda señal de "esto flota", sin sombra. Esto es un
componente **mínimo funcional** (cierra con Escape, foco en el contenedor,
`role="dialog"`) — un atrapado de foco completo (que el Tab no se escape del
modal) queda como mejora pendiente, no bloquea Día 2.

### Paso 9 — `CabeceraPagina`: componente compartido (nuevo — no estaba en el borrador)

Hoy las 24 pantallas escriben cada una su propio `<h1 className="font-serif
text-2xl">` con márgenes inconsistentes (`mb-1` en la mayoría, sin margen en
otras, `text-3xl` en Dashboard). Crear
`apps/web/components/ui/cabecera-pagina.tsx`:

```tsx
import type { ReactNode } from "react";

export function CabeceraPagina({ titulo, descripcion, accion }: {
  titulo: string; descripcion?: string; accion?: ReactNode;
}) {
  return (
    <div className="mb-8 flex items-start justify-between gap-4">
      <div>
        <h1 className="font-serif text-[1.75rem] font-medium leading-tight tracking-[-0.01em] text-tinta">
          {titulo}
        </h1>
        {descripcion && <p className="mt-1 text-sm text-taupe">{descripcion}</p>}
      </div>
      {accion && <div className="shrink-0">{accion}</div>}
    </div>
  );
}
```
Un solo tamaño fijo para las 24 pantallas (reemplaza `text-2xl`/`text-3xl` mezclados).

### Paso 10 — Pantalla piloto, verificación de contraste final y cierre

Migrar **una sola pantalla real** que ya usa los tres componentes tocados, para
probar el conjunto: `apps/web/app/(admin)/admin/equipo/page.tsx` (ya importa
`Boton`/`Tabla`/`Insignia`, no hace falta tocar imports). No forzar `Campo`,
`Modal` ni `CabeceraPagina` ahí todavía si no calzan naturalmente — el objetivo es
validar que lo tocado hoy no rompió nada, no maximizar cobertura.

Después:
1. Re-correr la verificación de contraste **sobre los valores finales tal como
   quedaron en el archivo** — verde/ámbar claro ≥6:1 sobre crema, pizarra ≥4.5:1
   sobre crema y papel.
2. Abrir `apps/web/app/(terminal)/terminal/marcar/` en el navegador (4 sedes lo
   usan a diario) y confirmar a ojo que verde/ámbar siguen leyéndose bien como
   "presente"/"en pausa" — es un cambio de tono, no de rol, y es el **único**
   punto donde este cambio toca el kiosco (taupe/sand/papel no se tocaron, así
   que el resto del terminal queda intacto por diseño).
3. `npx pnpm typecheck && npx pnpm test`.
4. Commit — mensaje que mencione explícitamente el cambio de `CLAUDE.md` de nueve
   a once tokens (para que quede visible en el historial y Felipe lo vea).
5. **No hacer push a producción ni pedir despliegue** — eso se pregunta siempre y
   no es parte de "Fundamentos".

---

## Día 2 — Aplicación (después, no la misma sesión)

Con Día 1 cerrado, existen ya: `Boton` (con `cargando`), `Tabla` (con `Fila`),
`Insignia` (con `positivo`/`informativo`), `Campo`/`CampoSelect`, `Modal`,
`CabeceraPagina`, y los tokens/radios en `globals.css`. Migrar, en este orden de
impacto (no intentar las 24 pantallas en un día):

1. **`admin/nav.tsx`** — aplicar radio y `focus-visible` a los enlaces/botones de
   ícono; bajar el breakpoint de colapso completo de `xl` (1280px) a `lg` (1024px)
   y, entre `lg` y `xl`, mostrar los 5 grupos con su etiqueta visible en vez de
   solo separadores de 1px (el problema medido: "27 ítems sin jerarquía visible" y
   "la barra completa desaparece por debajo de 1280px", un ancho común en laptop
   de trabajo real). No tocar fetch de contadores, filtrado por rol, buscador ni
   atajos — es apariencia, no lógica. **No** intentar el sidebar colapsable de
   "libertad total" en un día — eso queda para después si el ajuste evolutivo no
   alcanza.
2. **`admin/equipo/page.tsx`** completo — la pantalla con más divergencias
   medidas: `CabeceraPagina`, todos los `<button>` a `Boton` (incluido el prop
   `cargando` reemplazando el `"Guardando…"` de texto), todos los `<label><input>`
   a `Campo`/`CampoSelect`, la tabla y subtabla de jornadas a `Tabla`/`Fila`, los
   pills de estado a `Insignia`, los modales de alta/edición a `Modal`. No tocar
   lógica de alta/edición/generación de PIN.
3. **`admin/horas/page.tsx`** — objetivo acotado (1330 líneas, la tabla más
   compleja del panel): tarjetas KPI, `CabeceraPagina`, botones de acción, el
   modal "cerrar el día" (hoy `bg-black/20`, se unifica a `bg-black/40` vía
   `Modal`). **No** reescribir la tabla "Desempeño" completa hoy — tiene un `Th`
   local no reutilizable y columnas condicionales, es refactor de otro día. **No**
   tocar ningún cálculo de horas/tardanzas/sobretiempo.
4. Solo si alcanza el tiempo: `admin/incidencias/page.tsx` o
   `admin/correcciones/page.tsx` (modales de edición inline, para probar `Modal`
   en un caso de edición real).

**Verificación transversal antes de cualquier push**, en este orden:
- `npx pnpm typecheck` y `npx pnpm test` en verde.
- `npx eslint <archivos tocados>` (el hook de pre-push solo lintea lo que el push
  agrega — mejor verlo antes).
- `rg "(bg|text|border|ring|fill|stroke)-(white|black|slate|gray|grey|zinc|neutral|stone|red|amber|yellow|green|blue|indigo|purple|pink|orange|teal|cyan|sky|violet|fuchsia|rose|lime|emerald)(-[0-9]+)?"`
  sobre cada archivo tocado — vacío salvo los scrims `bg-black/NN` ya documentados.
- Abrir `/admin/personas/[id]` y `/admin/politica-salarial`: **ninguno de los dos
  debe cambiar de aspecto** — no tocarlos sin que Felipe lo pida (ver nota abajo
  sobre `personas/[id]:645`).
- Imprimir una boleta, un contrato y el memo disciplinario — `.hoja` debe seguir
  forzando paleta clara en `@media print`.
- Alternar modo oscuro en las 3 pantallas piloto y en el terminal.
- Commits separados por pantalla piloto, nunca `--amend` — varias sesiones
  comparten árbol. `git push` normal (sin `--no-verify`).

Al cerrar el día, actualizar `docs/estado.md` (se sobrescribe, no se acumula) con
qué se migró y qué sigue — no crear un archivo de estado nuevo con fecha.

---

## Pendiente para después (no es de Día 1 ni Día 2)

- El resto de las ~20 pantallas restantes, priorizadas por cuántas veces repiten
  el botón primario a mano (13+ archivos con la cadena literal exacta).
- `admin/costos/page.tsx` y `admin/provisiones/page.tsx`: dos "gramáticas" de
  tarjeta KPI conviviendo (una `bg-tinta`/`bg-sand` sólida, otra `border-sand`
  sobre `bg-papel`) — generalizar una sola `TarjetaKpi`.
- `admin/dashboard/page.tsx`: es en realidad una vista de asistencia en vivo, no
  un dashboard de KPIs — considerar si el nombre confunde.
- La decisión de navegación de "libertad total" (sidebar colapsable) si el ajuste
  evolutivo del Día 2 no alcanza.
- Formalizar como tokens documentados los scrims `bg-black/NN` (10 de los 14 usos
  sueltos de color medidos en la auditoría son esta excepción ya decidida desde
  agosto 2026, no deuda nueva) — por ejemplo un décimo/decimosegundo token
  `--color-scrim`.
- **Decisión abierta, no resolverla sin preguntar:** `personas/[id]:645` usa
  `bg-white` fijo en la tarjeta de vista previa de firma ("así se verá en el
  memo"). Es probablemente la misma familia de excepción que política salarial
  (mostrar tal cual se ve impreso), pero **no está escrita en ningún lado** como
  tercera excepción — a diferencia de `.hoja` y política salarial. Preguntarle a
  Felipe si se documenta como excepción o se cambia a `bg-papel`; no decidirlo
  por cuenta propia.
- Único hallazgo sin excepción documentada de ningún tipo:
  `admin/liquidaciones/page.tsx`, componente `Hoja()`, usa `border-black` x3 y
  nunca la clase `.hoja` — alinearlo con esa convención cuando se toque esa
  pantalla (no imprime hoy con problema, pero es la única inconsistencia real sin
  justificación).
- Paginación o virtualización real para equipo/horas/incidencias — hoy vuelcan
  el dataset completo al DOM sin límite.

## Reglas que este trabajo no toca (recordatorio, no son nuevas)

- Ningún cálculo de planilla, horas, tardanzas ni sobretiempo.
- `.hoja` y política salarial: excepciones ya decididas, no se "corrigen".
- El terminal: sin PIN a propósito, targets táctiles grandes, texto grande para
  leerse de pie — ningún cambio de componente compartido puede reducir tamaño o
  contraste ahí. `RelojCentral` dibuja SVG con `var(--color-taupe)`/`var(--color-rojo)`
  inline sin type-check que lo proteja — este plan no renombra ningún token, solo
  agrega dos y retunea dos, así que no lo toca.
- `git config core.hooksPath scripts/hooks` — **verificado ya activo en este
  worktree**, los hooks de pre-push van a correr.
