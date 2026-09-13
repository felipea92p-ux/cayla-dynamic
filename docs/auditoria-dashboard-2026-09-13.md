# Auditoría — Dashboard (`/admin/dashboard`)

**13 de septiembre de 2026.** Primera pantalla de la auditoría completa al panel.
Alcance acordado con Felipe: funcional + UX + seguridad + performance; código React
+ SQL que consume + contraste en vivo contra producción (solo lecturas); entrega
como reporte estructurado, sin tocar código todavía.

Archivo auditado: `apps/web/app/(admin)/admin/dashboard/page.tsx` (836 líneas).
No hay componentes hijo propios ni API route intermedia — todo el fetch de datos
vive ahí mismo, contra Supabase directo.

---

## Resumen en seis líneas

1. **Hallazgo confirmado por Felipe**: "anticip. 265m" debería decir "4h 25m" — y
   el arreglo correcto no es escribir una función nueva, es dejar de escribir una
   tercera copia de una que ya existe dos veces.
2. **Orden de sedes** decidido: por gente trabajando ahora (desc.), empate
   alfabético — una sola regla cubre los tres casos que Felipe pidió.
3. El link a Google Sheets está hardcodeado en el código; se decide mover a
   configuración.
4. Varias franjas fallan en silencio; se distingue por gravedad cuáles deben
   avisar explícitamente (como ya hace Disciplina) y cuáles no.
5. **Lo que no se preguntó y es lo más importante de esta pantalla**: una
   encargada de sede (hay 8 activas hoy) ve las otras tres sedes como
   "0 trabajando de 0" — no por un error, sino porque el permiso de datos
   (RLS) le oculta esas sedes y el Dashboard no distingue "vacío" de "oculto".
6. RLS está bien puesto en las 10 tablas que esta pantalla toca, y el patrón de
   colores respeta el sistema de modo oscuro — dos cosas que se revisaron y
   están bien, no solo lo que estaba mal.

---

## 1. Bug confirmado: minutos de anticipo sin formatear

`page.tsx:781` y `page.tsx:819`:

```tsx
<Insignia variante="advertencia" tamano="sm">anticip. {f.salidaTemprana}m</Insignia>
```

`f.salidaTemprana` es un entero en minutos (viene de `fn_jornadas_extra` →
`minutos_salida_temprana`). Con 265 minutos, la pantalla dice "anticip. 265m" en
vez de "4h 25m".

El repo ya resolvió exactamente este problema, dos veces, en otras pantallas:

- `apps/web/app/(admin)/admin/horas/page.tsx:138-140` → `fmtMinutos(m)`
- `apps/web/app/(mio)/mio/page.tsx:396-398` → `comoMinutos(min)`

Las dos hacen lo mismo, letra por letra:

```ts
if (m < 60) return `${m} min`;
return `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, "0")}m`;
```

**Propuesta:**

> DECIDÍ: mover este formateador a `packages/shared` (una sola vez) y usarlo en
> Horas, Mío y Dashboard.
> DESCARTÉ: escribir una tercera copia dentro del Dashboard — sería repetir
> exactamente el patrón que tu propio `CLAUDE.md` ya identificó como problema
> (35 copias de un permiso, 32 del huso horario) y que se corrigió moviendo la
> lógica a `packages/shared`/`apps/web/lib`.
> SE ROMPE SI: alguien ajusta el redondeo en una copia y no en las otras dos, y
> "anticipo" empieza a decir números distintos para la misma persona el mismo
> día según qué pantalla se mire.

---

## 2. Orden de sedes

Hoy: alfabético fijo (AQP → CCO → LIM → TRU), por accidente de cómo se ordena
la consulta a `sedes`, no por diseño.

Decidido con Felipe: **primero la sede con más gente trabajando ahora mismo**
(la opción 2 de las que se le presentaron), y cuando hay empate —incluido el
caso "nadie trabajando en ninguna sede"— desempatar alfabéticamente. El caso
"solo una sede tiene actividad" queda cubierto por la misma regla sin necesitar
una excepción aparte.

> DECIDÍ: `sedes.sort((a, b) => activos(b) - activos(a) || a.codigo.localeCompare(b.codigo))`,
> calculado sobre el mismo `activos.length` que ya usa cada sección.
> DESCARTÉ: un orden organizacional fijo (Central primero por ser sede
> administrativa) — no sirve al propósito de esta pantalla, que es mostrar
> primero dónde hay algo que atender.
> SE ROMPE SI: nunca, en realidad — el desempate alfabético es determinista,
> así que no hay un estado de datos que deje el orden ambiguo.

---

## 3. Link "Ver en Google Sheets" hardcodeado

`page.tsx:497`:

```tsx
<a href="https://docs.google.com/spreadsheets/d/19jhc5IN0LpbyG00jEwqt4ZB420Ob_rVcGRAdXR88riA/edit" ...>
```

Decidido con Felipe: corregirlo ya.

> DECIDÍ: moverlo a una variable de entorno (`NEXT_PUBLIC_SHEET_ASISTENCIA_URL`
> o similar). Antes de crear una tabla de configuración nueva para esto, reviso
> si ya existe un patrón de "configuración de un solo valor" en el repo
> (`configuracion.planilla_provisiones` es el precedente más cercano, pero es
> para números de planilla, no para URLs de UI) — si no hay un patrón que
> encaje, una variable de entorno es más simple y no exige una migración por
> un dato que no es de negocio.
> DESCARTÉ: dejarlo en código — cualquier cambio a esa URL hoy exige un PR,
> revisión y deploy para lo que en realidad es un dato, no lógica.
> SE ROMPE SI: el Sheet se reemplaza o reorganiza (nueva hoja, nuevo ID) y no
> hay nadie con acceso al repo disponible para hacer el cambio y desplegarlo —
> justo el escenario que una variable de entorno evita.

---

## 4. Franjas que fallan en silencio — por gravedad

Decidido con Felipe: avisar siempre que algo falle, pero no todas las franjas
merecen el mismo aviso. El criterio que separa una de otra es el mismo que ya
ordena todo este repo: **si toca plata o un plazo legal, avisa explícito, como
ya hace Disciplina; si es puramente informativo, puede seguir desapareciendo
callada.**

| Franja | Hoy | Toca plata/legal | Propuesta |
|---|---|---|---|
| Tardanzas/faltas (Disciplina) | Avisa explícito | Sí (art. 25) | Ya está bien — es el modelo a copiar |
| Memos sin cargo firmado | Avisa explícito | Sí (defensa legal) | Ya está bien |
| **Contratos a plazo fijo** | Desaparece sin aviso | **Sí (art. 77)** | **Avisar explícito** |
| **Alerta roja "sede sin marcar"** | Se apaga sin aviso si fallan `turnos`/`horarios_asignados` | Operativo crítico | **Avisar explícito** |
| Ausencias (badge anti-falso-positivo) | Desaparece sin aviso | Medio (riesgo de falso "sin marcar") | Aviso discreto |
| Quién respondió su memo (0404) | Desaparece sin aviso | No — informativo | Dejar como está |
| Metas de cobertura | Cae a "sin meta" (neutro) | No | Dejar como está |

Los dos casos de "Avisar explícito" tienen el mismo peso que ya justificó el
patrón de Disciplina:

- **Contratos a plazo fijo**: si `fn_contratos_por_vencer` falla, hoy la franja
  entera desaparece. El artículo 77 convierte el contrato en indefinido SOLO
  por seguir trabajando después de la fecha — ese plazo corre igual aunque la
  pantalla no pueda mirarlo.
- **Alerta roja de sede sin marcar**: depende de `turnos` y
  `horarios_asignados` (líneas 355-360, 699-709). Si cualquiera de las dos
  falla, `entradaEsperadaHoy` queda `null` para todos y la alerta simplemente
  nunca se dispara — sin decir que no pudo revisar. Es la única alerta roja de
  toda la pantalla fuera de Disciplina.

> DECIDÍ: agregar el mismo patrón que ya existe para `discNoRespondio` (una
> bandera de "no se pudo consultar" que se muestra en vez de ocultar la
> franja) a Contratos y a la alerta de sede-sin-marcar; degradar el caso de
> Ausencias a un aviso discreto (ej. un ícono con tooltip), no un banner.
> DESCARTÉ: avisar igual de fuerte en las siete franjas sin distinguir — eso
> generaría ruido exactamente donde ya se decidió, correctamente, que el
> silencio es la opción correcta (memos de respuesta, metas).
> SE ROMPE SI: `horarios_asignados` falla un día en que una sede de verdad no
> tiene a nadie marcado — hoy esa combinación no produce ninguna señal, y la
> única forma de enterarse es que alguien llame por teléfono a preguntar por
> qué la tienda está cerrada.

---

## 5. Lo que no se preguntó: la encargada ve sedes "vacías" que en realidad están ocultas

Esto no estaba en el alcance original — apareció al revisar seguridad contra
producción (solo lecturas, sin escribir nada).

**Hechos verificados en producción (`vovjyyiafkxteijimpuy`), hoy:**

- Hay **8 personas activas con rol `supervisor_sede`** (encargada de sede), y
  el rol SÍ tiene acceso al Dashboard (`ROLES_CON_PANEL` = `DO_Y_ENCARGADA`,
  `nav-items.ts:92`).
- RLS en `personas`, `jornadas`, `turnos`, `horarios_asignados` y
  `metas_cobertura` restringe correctamente a `supervisor_sede` a su propia
  sede (`sede_base_id = fn_sede_actual_persona()`) — **eso está bien hecho**.
- Pero `sedes` tiene una sola política: `sedes_select_autenticados … qual: true`
  — **cualquier autenticado ve el catálogo completo de las 4 sedes**, sin
  importar su rol.
- El Dashboard arma sus secciones iterando sobre `sedesActivas` (que viene de
  `sedes`, sin filtrar), y para cada una filtra `filas` por `sedeId`.

**Consecuencia real**: cuando una encargada de AQP abre el Dashboard, ve su
propia sede con datos reales, y ve TRU, CCO y LIM con "0 trabajando de 0",
"Nadie marcado todavía". No es una fuga de datos — RLS le está ocultando
correctamente esas personas. Pero la pantalla no dice "no tienes permiso para
ver esto": dice "aquí no hay nadie", que es una afirmación distinta y falsa.
Es el mismo error de diseño que Don Norman describe: el sistema no distingue
"vacío" de "oculto", y quien lo lee sin saber cómo funciona el permiso por
debajo saca la conclusión equivocada de buena fe.

> DECIDÍ: para `supervisor_sede`, filtrar en el cliente `sedesActivas` a solo
> su propia `sede_base_id` antes de renderizar las secciones (la persona ya
> trae `sede_base_id` en la sesión).
> DESCARTÉ: restringir la tabla `sedes` con RLS también — rompería el catálogo
> completo de sedes que otras ~14 pantallas necesitan mostrar a todos los
> roles (selectores de sede en Turnos, Equipo, etc.).
> SE ROMPE SI: una encargada mira el Dashboard un lunes con poco movimiento,
> ve las otras tres sedes en cero y concluye —de buena fe, sin mala
> intención— que esas tiendas no abrieron hoy.

---

## 6. Números, no opiniones (performance)

`cargar()` dispara 11 consultas en paralelo cada 30 segundos mientras la
pestaña esté abierta (`REFRESCO_MS`, línea 15). Las franjas de Disciplina y
Contratos corren aparte, solo una vez por carga de página.

Con los 13 accesos actuales al panel que pueden abrir esta pantalla (5 `admin`
+ 8 `supervisor_sede`), si cada uno deja la pestaña abierta una jornada de 8
horas: 960 ciclos de refresco × 11 consultas × 13 sesiones ≈ **137,000
consultas/día**, solo de este Dashboard.

A la escala de hoy (~30 personas, Supabase en su plan actual) esto no es un
problema — Postgres resuelve estas consultas en milisegundos. Vale la pena
revisarlo si el equipo crece varias veces su tamaño actual y se agregan más
pantallas con el mismo patrón de refresco de 30s, no antes. No es una decisión
que haya que tomar hoy.

---

## 7. Lo que ya está bien (para no auditar solo lo que falla)

- Las metas de cobertura (`Operativas en piso`, `Encargadas`) vienen de la
  tabla `metas_cobertura`, no están hardcodeadas.
- `sedesActivas` se deriva de la tabla `sedes`, nunca de agrupar `filas` — así
  una sede sin nadie que califique sigue apareciendo con "0 de 0" en vez de
  desaparecer entera sin aviso. Ya está resuelto el mismo bug que casi se
  reintrodujo acá.
- RLS activo con `rowsecurity = true` en las 10 tablas que esta pantalla
  toca, con políticas que sí distinguen `admin`/`líder` de `supervisor_sede`
  de "propia".
- Ningún color de Tailwind por defecto (`bg-white`, `amber-100`, etc.) fuera
  de los tokens `--color-*` — cumple la regla de modo oscuro de todo el panel.
- El patrón `discNoRespondio` / `sinCargoNoRespondio` (Disciplina) ya resuelve
  bien el problema del punto 4 — el trabajo que falta no es inventar un patrón
  nuevo, es copiarlo a las dos franjas que todavía no lo tienen.

---

## Nota operativa: verificación en vivo no completada

Se pidió levantar el panel local para probar casos borde (0 marcados, metas en
0, modo oscuro). El contenedor de Postgres de este proyecto ya estaba arriba
(compartido entre worktrees, 29 horas encendido — probablemente otra sesión
corrió `db start` en vez de `start` completo, tal como ya advierte tu
`CLAUDE.md`), pero `kong`/`auth`/`rest`/`studio` nunca se crearon. Dos intentos
de `npx supabase start` no los levantaron, sin un error claro que explique por
qué. No se ejecutó `supabase stop` para no arriesgar el trabajo de otras
sesiones sobre ese mismo Postgres compartido.

En su lugar, la verificación "en vivo" de esta auditoría se hizo contra
**producción, solo lecturas** (RLS, roles activos) — cubre el hallazgo de
seguridad de la sección 5, pero no reemplaza ver la pantalla renderizada. Si
quieres, en la próxima pantalla puedo intentar de nuevo con más tiempo, o
puedes decirme si sabes por qué ese stack se quedó a medias.

---

## Las 5 propuestas — aplicadas

Felipe pidió aplicarlas directo. Las cinco están en el código
(`apps/web/app/(admin)/admin/dashboard/page.tsx`, `packages/shared/src/duracion.ts`,
y las dos pantallas que ya no duplican el formateador de minutos):

1. ✅ Minutos de anticipo formateados + `formatoMinutos` movido a
   `packages/shared` y reutilizado en Horas, Mío y Dashboard.
2. ✅ Sedes reordenadas por gente activa ahora (desc.), empate alfabético.
3. ✅ Link de Google Sheets movido a `NEXT_PUBLIC_SHEET_ASISTENCIA_URL` (con el
   valor de hoy como respaldo si la variable no está puesta en Vercel todavía
   — **falta agregarla en Vercel** si se quiere que sea editable de verdad sin
   deploy).
4. ✅ Contratos y la alerta de sede-sin-marcar avisan explícito si su consulta
   falla; Ausencias baja a un aviso discreto bajo el encabezado.
5. ✅ `supervisor_sede` (encargada) ahora solo ve su propia sede en el
   Dashboard, usando `usePersonaActual()` + `puedeVerTodasLasSedes()` (el mismo
   primitivo que ya usan Turnos, Objetivos y Ausencias — no uno nuevo).

**Verificación hecha:** `typecheck` (monorepo) limpio, `eslint` limpio en todas
las líneas nuevas (la deuda preexistente del archivo — 3 `any`, 1 patrón
`setState` en efecto — no se tocó), `vitest run` completo: 535 pruebas en
verde. No se pudo verificar visualmente en el navegador: la pila local de
Supabase de este worktree solo tiene el contenedor de Postgres arriba, y tres
intentos de `npx supabase start` (incluido uno tras `pnpm install`) no
levantaron `kong`/`auth`/`rest`/`studio`, sin un error explicable — las
imágenes ya están descargadas localmente, así que no es un problema de red. No
se forzó `supabase stop` por ser un Postgres compartido con otras sesiones.
