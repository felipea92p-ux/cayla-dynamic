> ℹ️ **Informe fechado, no estado vigente.** Auditoría de la pantalla Disciplina
> hecha el 13 de setiembre de 2026, a pedido de Felipe. El estado de avance del
> proyecto vive en [`estado.md`](estado.md); el catálogo vivo de pendientes
> confirmados vive en [`hallazgos-abiertos.md`](hallazgos-abiertos.md), y los 3
> hallazgos nuevos de aquí ya se agregaron ahí.

# Auditoría — Disciplina (13 de setiembre de 2026)

Alcance acordado con Felipe antes de empezar: la pantalla `/admin/disciplina`
completa, de punta a punta — el componente, las 18 funciones SQL que la
sostienen, el memo impreso, y los 11 documentos legales que fundamentan el
diseño. Prioridad: riesgo legal/laboral. Verificado contra el código y contra
`docs/reglamento-interno-de-trabajo.md` (RIT v4.0), sin levantar el panel en el
navegador. El marco legal en sí se dio por bueno (ya pasó por diseño y consulta
a un laboralista); esta auditoría solo verifica que el código lo cumpla.

---

## Resumen — 5 hallazgos nuevos, 3 reconfirmados del catálogo, 3 refutados

| # | Qué | Severidad | Estado |
|---|---|---|---|
| 1 | La imputación de cargos por faltas se puede generar sin cumplir el art. 21.5 | 🔴 Crítica | Ya estaba en el catálogo — **reconfirmado vigente hoy** |
| 2 | El memo de amonestación cita artículos del RIT que ya no existen | 🔴 Alta | **Nuevo** |
| 3 | Firmar no revalida el rango de la suspensión, sus fechas, ni la fecha de cese | 🟠 Alta | **Nuevo** |
| 4 | La imputación cuenta la vigencia del antecedente desde la firma, no desde la entrega | 🟡 Media | **Nuevo** |
| 5 | El descargo se puede valorar antes de que venza su plazo | 🟡 Media | **Nuevo** |
| 6 | La suspensión por faltas no comprueba día laborable | 🟡 Media | Ya estaba en el catálogo — **reconfirmado vigente hoy** |
| 7 | Al personal de dirección se le sigue midiendo tardanza | 🟢 Latente | Ya estaba en el catálogo — **reconfirmado vigente hoy** |
| — | El catálogo tiene entradas obsoletas (A11 y otras dos) | — | Meta-hallazgo, ver más abajo |

---

## 1 · 🔴 CRÍTICA — La imputación de cargos por faltas se puede generar sin cumplir el art. 21.5

**Dónde:** `supabase/migrations/0390_el_motor_de_faltas_desempata_como_el_de_tardanzas.sql`, función `fn_expediente_generar_falta` (vigente — es la 6.ª y última de sus definiciones).

**Qué se rompe:** el RIT es explícito y lo dice dos veces en el mismo numeral:

> **21.2 c)** «Habilita además el procedimiento de imputación de cargos del
> artículo 57 **únicamente cuando la conducta configure alguna de las causales
> del numeral 21.5**. Fuera de esos supuestos no procede la imputación, por
> mucho que consten sanciones previas [...] **Iniciarlo sin ella expondría a la
> Empresa a un despido sin causa justa.**»

Y el art. 21.5 define exactamente tres causales: abandono (4+ días
consecutivos), 6+ ausencias en 30 días, o 16+ en 180 días. Nada más habilita
una imputación por faltas.

Pero el cuerpo vigente de la función tiene DOS caminos hacia `'imputacion'`:

```sql
if coalesce(v_full.consecutivas,0) >= 4 or coalesce(v_full.en_30,0) >= 6
   or coalesce(v_full.en_180,0) >= 16 then
  ...  -- ✅ esto SÍ es el art. 21.5, correcto
else
  ...
  elsif v_vigente and v_prev.nivel = 'suspension' then
    v_nivel := 'imputacion';   -- ⚠️ "reincidencia sobre suspensión"
```

El segundo camino no comprueba ninguna de las tres causales del 21.5: basta con
tener una suspensión vigente por faltas y cometer **una sola** falta nueva,
aunque esa falta ni siquiera sea consecutiva ni se acerque a los umbrales
legales.

**Se rompe si:** una colaboradora tiene una suspensión por faltas vigente (dentro
de sus 12 meses) y falta injustificadamente **una vez más**, sin llegar a 4
consecutivas, ni a 6 en 30 días, ni a 16 en 180. El sistema genera igual un
borrador de **imputación de cargos** — el acto que abre un procedimiento de
despido — para un hecho que el propio Reglamento dice que no lo habilita. Si
ese borrador se firma y se llega al despido, CAYLA queda expuesta exactamente
a lo que el art. 21.2 c) advierte: indemnización por despido arbitrario.

**Artículo:** RIT 21.2 c) y 21.5.

**Ya estaba anotado** en `docs/hallazgos-abiertos.md` ("La escalera de
inasistencias salta de la primera suspensión a la imputación de cargos con
una sola falta nueva, sin causal del art. 21.5"). Esta auditoría lo verificó
línea por línea contra la versión **vigente hoy** (0390) y confirma que sigue
exactamente igual — no se corrigió entre la fecha en que se anotó y hoy.

**Recomendación:** en la rama `elsif v_vigente and v_prev.nivel = 'suspension'`,
antes de asignar `'imputacion'`, comprobar que se cumple alguna causal del art.
21.5 (usando los mismos contadores de `fn_falta_contadores` que ya calcula la
función). Si no se cumple ninguna, lo que corresponde según el propio RIT es
quedarse en `'suspension'` otra vez (una nueva suspensión, no la imputación) —
el 21.2 c) dice que ese umbral "habilita una segunda suspensión" además de,
opcionalmente, la imputación cuando además se cumple el 21.5.

---

## 2 · 🔴 ALTA — El memo de amonestación cita artículos del RIT que ya no existen

**Dónde:** `apps/web/app/(admin)/admin/disciplina/memo/[id]/page.tsx:320` y `:331`.

**Qué se rompe:** el propio archivo tiene, en sus líneas 145-165, un comentario
extenso que documenta la migración de citas de RIT v3.0 a v4.0 (2026-08-15,
cuando el articulado se renumeró entero) — con una tabla de conversión. La
sección de **suspensión** del mismo archivo (líneas 336-339) ya usa la
numeración correcta (`19.2 c)`, `21.2 b)`). Pero las dos **amonestaciones**
—el primer peldaño de cada escala, el documento que más se emite— se quedaron
con la cita vieja:

- Línea 320 (amonestación por tardanza): *"superando el umbral b) del
  **artículo 7** del Reglamento..."* — el **artículo 7 vigente es "PERIODO DE
  PRUEBA"** (`docs/reglamento-interno-de-trabajo.md:302`), no tiene nada que
  ver con tardanzas. El umbral de 3 tardanzas/mes vive en el **literal b) del
  numeral 19.2** (línea 735 del RIT).
- Línea 331 (amonestación por falta): *"dará lugar a suspensión sin goce de
  haber (**artículo 8.3-b**)"* — el **artículo 8.3 vigente es sobre registro
  de contratos ante el MTPE** (línea 344 del RIT), otra materia por completo.
  El umbral correcto es el **literal b) del numeral 21.2** (línea 845 del RIT).

Verificado contra tres fuentes: la ley vigente (RIT v4.0), las plantillas
originales (`docs/disciplina-tardanzas-faltas/03-plantillas-tardanzas.md` y
`05-plantillas-faltas.md`, que usaban "artículo 7" y "8.3-b" y eran correctas
**en su momento**, antes de la renumeración), y el propio comentario del
código. Conclusión: no es un diseño deliberado — es una corrección que se
hizo a medias el 2026-08-15: arregló la suspensión y se saltó las dos
amonestaciones del mismo archivo.

**Se rompe si:** cualquier colaboradora que reciba una amonestación escrita
(por tardanza o por falta) — o su abogado, en un procedimiento — abre el
artículo que el memo le cita. Encuentra "Periodo de Prueba" o "registro de
contratos ante el MTPE": nada que ver con su sanción. Por el propio
razonamiento que el archivo deja escrito dos líneas arriba: *"un descargo que
abra el Reglamento por donde el memo le dice encuentra otra materia, y a
partir de ahí el documento entero deja de merecer crédito."*

**Artículo:** RIT 19.2 b), 21.2 b).

**Recomendación:** en `Cuerpo()`, línea 320, cambiar `"artículo 7"` por
`"numeral 19.2 b)"`; línea 331, cambiar `"(artículo 8.3-b)"` por `"(numeral
21.2 b) del RIT)"`. Cambio de una línea cada uno; conviene además correr un
grep de `artículo 7\b|8\.3-` sobre el resto del árbol de plantillas impresas
(certificados, constancias) por si el mismo renombre quedó a medias en otro
sitio no cubierto por esta auditoría.

---

## 3 · 🟠 ALTA — Firmar no revalida lo que el borrador ya advierte en rojo

**Dónde:** `fn_expediente_firmar` (vigente en `0267`) + `apps/web/.../disciplina/page.tsx` líneas 1393-1455 y 1382-1392.

**Qué se rompe:** el borrador de una suspensión o un despido ya calcula y
**muestra en rojo**, en la propia pantalla, tres advertencias:

1. Si `d.suspension_dias` queda fuera del rango que le toca a esa persona
   según su escalón (`fuera`, línea 1395).
2. Si las fechas de la suspensión **ya empezaron** ("esos días ya empezaron:
   si firmas hoy, la sanción no tendría efecto real", línea 1448-1452).
3. Si a un despido le **falta la fecha de cese** ("sin fecha, la carta saldría
   incompleta", línea 1388-1390), exigida por el art. 32 de la LPCL.

Ninguna de las tres bloquea el botón **Firmar** — solo el texto se pone rojo.
Y revisando `fn_expediente_firmar` (la función que de verdad transiciona el
documento a `'firmado'`), **ninguna de las tres se revalida ahí tampoco**: la
función comprueba permisos, el descargo previo (si la política lo exige) y
quién puede suscribir — pero no vuelve a mirar si los días de suspensión caen
dentro del rango legal, si las fechas ya pasaron, ni si existe `fecha_cese`
para un despido. El único candado de rango existe en `fn_expediente_set_suspension`
(la función que se llama al **editar** el campo, no al firmar) y en el
`CHECK` de tabla `chk_susp_completa` (que solo exige que los campos no sean
NULL, no que estén dentro del rango del art. 19.2/54.5). Para `fecha_cese` **no
existe ningún constraint** — ni de tabla, ni de función.

**Se rompe si:** entre generar el borrador y pulsar Firmar pasan varios días
(el propio código anticipa este caso: *"entre generar el borrador y firmarlo
pueden pasar días"*, comentario en `guardarDias`). Si nadie corrigió la fecha
de inicio de la suspensión mientras tanto, hoy puede ser posterior a esa
fecha — y el sistema deja firmar igual una sanción que no va a suspender nada
real, dejando un antecedente en el legajo que aparenta más peso disciplinario
del que tuvo. O, más grave: alguien firma una carta de despido sin fecha de
cese porque no reparó en el aviso rojo entre los demás campos del borrador —
el memo impreso queda con el texto literal
`[FALTA LA FECHA DE CESE — el art. 32 la exige...]` **dentro del cuerpo del
documento legal**, y nada en el sistema lo impidió.

**Artículo:** RIT 19.2 c)/d), 54.5; LPCL art. 32.

**Recomendación:** agregar a `fn_expediente_firmar` (o a un trigger `before
update` sobre la transición a `'firmado'`) las tres comprobaciones que hoy
solo son texto en pantalla: `fecha_cese is not null` cuando `nivel =
'despido'` (como ya existe `chk_susp_completa` para suspensión, agregar el
equivalente `chk_despido_completo`), y revalidar a firma-time que
`suspension_desde`/`suspension_fechas` no queden en el pasado. Coincide con la
Exigencia 4 de tu propio criterio (Lamport): un constraint de base vale más
que un texto en rojo que alguien puede no leer.

---

## 4 · 🟡 MEDIA — La imputación cuenta la vigencia del antecedente desde la firma, no desde la entrega

**Dónde:** `apps/web/.../disciplina/memo/[id]/page.tsx:235-243`, la consulta
`previas` que arma la lista de "sanciones disciplinarias previas" citada en
una carta de imputación de cargos.

**Qué se rompe:** el RIT es explícito sobre desde cuándo corre la vigencia de
un antecedente:

> **56.1.** «Un antecedente disciplinario produce efecto agravante durante los
> doce (12) meses siguientes a la fecha en que fue **entregado** a la
> colaboradora con cargo de recepción...»

Pero la consulta filtra así:

```js
.eq("estado", "entregado")
.gte("firmado_at", new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString())
```

Filtra correctamente por `estado = 'entregado'` (acorde al numeral 56.2), pero
la ventana de 12 meses se mide contra `firmado_at`, no contra `entregado_at`
— y la firma siempre ocurre antes (o el mismo día) que la entrega, nunca
después.

**Se rompe si:** una sanción se firma cerca del límite de los 12 meses pero
tarda unos días más en entregarse (el propio módulo tiene una sección entera,
"Firmados — por entregar", para ese estado intermedio, así que la demora no
es hipotética). Ejemplo concreto: una suspensión firmada hace 370 días,
entregada hace 358 — hoy, por el art. 56.1, **sigue vigente** (358 < 365). La
consulta la excluye igual, porque `firmado_at` (370 días) ya no cumple `>=
hoy − 365`. Esa sanción previa desaparece silenciosamente de la lista que la
carta de imputación nombra una por una — exactamente lo que el propio
comentario del código (líneas 140-144) dice que existe para evitar: que el
documento "se defienda solo" nombrando sus antecedentes. Una imputación que
**omite** un antecedente real y vigente puede dejar la causal de despido con
menos sustento del que en verdad tiene.

**Artículo:** RIT 56.1.

**Recomendación:** cambiar `.gte("firmado_at", ...)` por
`.gte("entregado_at", ...)` en esa consulta — un cambio de una palabra.

---

## 5 · 🟡 MEDIA — El descargo se puede valorar antes de que venza su propio plazo

**Dónde:** `fn_expediente_valorar_descargo` (vigente, única definición, `0212`).

**Qué se rompe:** la función exige `cargos_comunicados_at is not null` pero
**no** exige que `descargo_vence_at` ya haya pasado. Se puede declarar
`'sin_descargo'` (o "no acogido") el mismo día en que se comunicaron los
cargos, sin esperar los dos días hábiles que el art. 55.2/19.3 le dan a la
colaboradora.

**Se rompe si:** se comunica el cargo un lunes, y ese mismo lunes —por
apuro, o por costumbre— se marca "sin_descargo". La colaboradora presenta su
descargo el martes, todavía dentro de su plazo legal. Nada en el sistema
fuerza revisar o rehacer la valoración: `fn_expediente_firmar` solo comprueba
que `descargo_acogido is not null` (ya lo está, aunque sea con el valor
equivocado) y que el plazo haya vencido (sí, para el martes ya venció) — así
que el documento se puede firmar diciendo que no hubo descargo cuando sí lo
hubo, presentado en tiempo.

**Artículo:** RIT 19.3, 55.2.

**Recomendación:** agregar a `fn_expediente_valorar_descargo` la misma
comprobación que ya tiene `fn_expediente_firmar`: `if now() < v_doc.descargo_vence_at
then raise exception`. Barato de agregar, y cierra el hueco sin tocar nada
más del flujo.

---

## 6 · 🟡 MEDIA (reconfirmado) — La suspensión por faltas no comprueba día laborable

**Dónde:** `fn_expediente_generar_falta` (vigente, `0390`), rama `v_nivel :=
'suspension'` — a diferencia de `fn_expediente_generar_tardanza`, que sí
envuelve la fecha en `fn_dias_suspension(...)` dentro de un `begin/exception`.

Ya estaba anotado en el catálogo ("La suspensión por faltas se fija en
`fn_hoy_lima() + 1` sin comprobar que sea día laborable, y deja
`suspension_fechas` en NULL. La rama de tardanzas sí lo hace bien desde la
0235"). Verificado contra la versión vigente hoy (0390): **sigue exactamente
así** — la fecha se fija con `fn_hoy_lima() + 1` sin pasar por
`fn_dias_suspension`, así que si ese día es el descanso semanal de la persona,
la suspensión (de un solo día, en la escala de faltas) no le quita nada real.

**Artículo:** RIT 21.2 b) ("no puede fijarse sobre días de descanso semanal").

**Recomendación:** replicar en `fn_expediente_generar_falta` el mismo patrón
que ya usa `fn_expediente_generar_tardanza` (llamar a `fn_dias_suspension` y
guardar el arreglo resultante en `suspension_fechas`).

---

## 7 · 🟢 LATENTE (reconfirmado) — Al personal de dirección se le sigue midiendo tardanza

Ya estaba anotado en el catálogo como "latente, población cero hoy". Verificado
contra `fn_tardanzas_resumen` (vigente, `0311`) y `fn_faltas_resumen` (vigente,
`0396`): ninguna de las dos excluye `personal_direccion` en su CTE de
`medibles` (solo filtran `estado = 'activo'`, `en_planilla = true`,
`sueldo_fijo = false`). Sigue siendo un mecanismo real sin población hoy — no
se sube de severidad, solo se confirma que el código vigente no cambió este
punto. Si algún día alguien con ese atributo entra a planilla ordinaria, el
sistema le armaría un expediente disciplinario que el art. 5 del D.S.
007-2002-TR no le aplica.

---

## Meta-hallazgo — el catálogo de pendientes tiene entradas obsoletas

Comparando `docs/hallazgos-abiertos.md` contra el código que esta auditoría
leyó línea por línea, al menos **tres entradas ya no describen el código
actual**, aunque siguen listadas como abiertas:

- **A11** ("el memo en borrador se imprime firmado por Gerencia General",
  "el aviso de borrador sigue con `no-print`"): el código actual de
  `memo/[id]/page.tsx` arranca `firmante` en `null` (nunca en la constante de
  la empresa) con un comentario extenso explicando por qué, y el aviso de
  "BORRADOR" **no** lleva la clase `print:hidden` — el propio comentario dice
  "SIN `print:hidden`, y es deliberado". **Las dos partes de A11 están
  resueltas.**
- **La lista "Firmados — por entregar" imprime la fecha de creación rotulada
  como "Firmado"** (dos entradas del catálogo describen el mismo síntoma: la
  de "Vivos" y la de "Menores, sin verificar" · `disciplina-legal`): el código
  actual dice `Firmado {selloLima(d.firmado_at ?? d.creado_at)}` — usa
  `firmado_at` con prioridad, y solo cae a `creado_at` si `firmado_at` fuera
  nulo (lo que no debería ocurrir en un documento ya firmado). **Resuelto.**
- **"El umbral mensual de tardanzas se borra el 1 de cada mes y no hay forma de
  emitir el documento después":** el selector de mes de Disciplina
  (`mesesRecientesLima()`) ofrece hasta 12 meses hacia atrás, con avisos
  explícitos sobre el numeral 19.4 y el riesgo de condonación por demora. **Ya
  no aplica tal como está escrito** — sí se puede documentar un mes cerrado,
  dentro de esa ventana de 12 meses (que además coincide con la vigencia legal
  del propio antecedente, así que documentar más atrás sería dudoso de todos
  modos).

Esto no es un hallazgo de Disciplina en sí, pero importa para la disciplina
del propio proceso de auditoría: con varias sesiones trabajando en paralelo,
un catálogo de pendientes que no se actualiza cuando algo se corrige es tan
peligroso como uno que no anota lo nuevo — hace perder tiempo reabriendo lo ya
cerrado, y le resta crédito a las entradas que sí siguen vivas. Vale la pena
que alguien pase por el catálogo completo (no solo la sección de disciplina)
tachando lo que el código ya resolvió.

---

## Hipótesis descartadas (para no repetir el camino)

- **¿El `CHECK` de `expediente_adjuntos.tipo` bloquea subir un descargo?**
  Parecía que sí (la tabla original de la 0074 solo admitía
  `'cargo_firmado'`/`'acta_negativa'`, y `fn_expediente_adjuntar` sí acepta
  `'descargo'` desde la 0212). **Refutado**: la migración 0206 amplía el
  constraint (`drop constraint` + `add constraint ... check (tipo in
  ('cargo_firmado', 'acta_negativa', 'descargo'))`). Subir un descargo
  funciona.
- **¿El numeral 56.6 (orden de emisión: del mes más viejo al más nuevo) es
  solo un aviso de interfaz, sin candado real?** **Refutado**:
  `fn_expediente_generar_tardanza` lo valida server-side (`if v_esc.corte is
  not null and v_esc.corte >= v_fin then raise exception ... numeral 56.6`).
- **¿Existe algún camino para crear un documento de causal `'conducta'`?**
  El enum de la tabla lo admite (`check (tipo_causal in ('tardanza','falta',
  'conducta'))`) y `memo/[id]/page.tsx` sabe redactarlo (`INCISO_ART25` mapea
  `conducta → inciso a)`), pero no se encontró ningún generador ni botón en
  el producto que lo cree — solo `fn_expediente_generar_tardanza` y
  `fn_expediente_generar_falta` existen, ninguna para `'conducta'`. **No se
  resolvió si es intencional** (¿reservado para que Gerencia lo cargue a mano
  por un caso de mala conducta que no encaja en tardanza/falta?) o si es una
  pieza a medio construir. No es urgente — nadie puede generarlo desde la
  pantalla hoy — pero vale una pregunta directa a Felipe antes de decidir si
  hace falta un generador o si se retira del enum.

---

## Comparación con ERPs de referencia (acordado: UX contra BambooHR/Rippling, modelo de datos contra Workday/Oracle)

**Dónde este módulo ya está a la altura, y no vale la pena "mejorarlo":**
las reglas de la escala disciplinaria viven codificadas directamente en
funciones SQL con el número de artículo del RIT en el propio código y en los
mensajes de error — no hay un "motor de reglas" configurable de propósito
general. Un Workday o un SAP SuccessFactors sí traen ese motor, pero está
pensado para clientes con reglamentos que cambian entre países y entre
clientes del mismo producto. CAYLA tiene un solo Reglamento, una sola
jurisdicción, y el propio código de este módulo ya demuestra (con 8-9
versiones de cada función, cada una corrigiendo un caso real encontrado en
producción) que el camino de codificar la regla directamente y corregirla
cuando se descubre un caso es el que de verdad ha sostenido este sistema.
Construir un motor de reglas genérico aquí sería la abstracción prematura que
tu propio criterio (Carmack, Hickey) ya te pide evitar.

**Dónde sí hay una brecha real frente a esos productos:**

1. **Vista centrada en la persona.** BambooHR y Rippling arman, para cada
   colaborador, una única línea de tiempo con todo su historial (tardanzas,
   faltas, amonestaciones, revisiones). Disciplina hoy está organizada por
   TIPO de cosa pendiente (semáforo de tardanzas, semáforo de faltas,
   borradores, firmados, entregados) — la vista "todo lo de esta persona,
   en orden" solo existe implícitamente, armada a mano por la consulta
   `previas` cuando se redacta una imputación. Para una auditoría o una
   conversación con una colaboradora, hoy hay que reconstruir esa vista uno
   por uno. No es urgente, pero es la brecha de UX más citable frente a esos
   productos.
2. **Rastro de auditoría como texto libre, no como tabla.** Cada acto sobre un
   documento (comunicar cargos, declarar una comunicación pasada, firmar sin
   descargo por la política, reabrir, anular) se anota **concatenando texto**
   en la columna `observacion` (`coalesce(observacion || E'\n', '') || '...'`).
   Funciona, pero un documento reabierto y anulado varias veces termina con un
   párrafo cada vez más largo que hay que leer entero para reconstruir la
   secuencia. Un Workday/Oracle guarda esto como filas de un log estructurado
   (quién, cuándo, qué acción, qué valor). Dado que este mismo repositorio ya
   tiene el patrón (marcajes/jornadas: fuente de verdad append-only, resumen
   derivado) sería consistente aplicar el mismo criterio acá — una tabla
   `expediente_eventos` en vez de un blob de texto — el día que el volumen de
   expedientes lo justifique. Con ~30-60 personas en 3 años, hoy no es
   urgente; queda anotado para cuando lo sea.
3. **Autoservicio de la colaboradora.** BambooHR muestra a cada persona su
   propio expediente y sus plazos pendientes. CAYLA decidió explícitamente NO
   abrir esto (`docs/estado.md`, 2026-08-15): `exp_select_propia` no filtra
   por estado, y abrir el autoservicio hoy expondría borradores que nadie
   decidió entregar todavía — sancionaría por algo que aún no es una decisión
   tomada. Esta es la decisión correcta dado cómo está construida la RLS hoy;
   si algún día se abre, debe ir filtrado estrictamente a `firmado`/
   `entregado`, nunca a `borrador`.

---

## Qué no cubrió esta auditoría

- No se levantó el panel en el navegador (Postgres local para este worktree
  no estaba arriba, y el alcance acordado fue código + documentos). Los
  hallazgos de lógica se verificaron leyendo el código exacto, no
  ejecutándolo.
- No se comparó contra producción (`donde-vive.sh` solo confirma cuál es la
  última migración que define cada función, no que producción coincida
  byte a byte). Antes de tocar cualquiera de estas funciones, corresponde el
  chequeo de md5 de producción que ya exige `CLAUDE.md`.
- No se auditaron las pantallas que alimentan los mismos contadores desde
  otro lugar (`/mio`, Incidencias, Correcciones) — el catálogo ya señala que
  un día impugnado por `/mio` sigue contando para el umbral, y esta auditoría
  no verificó ese camino en detalle por estar fuera de la pantalla Disciplina
  en sí.
- El directorio `auditoria/` (116 agentes, 2026-08-17/18) no se abrió — el
  propio `estado.md` dice que ya quedó absorbido en el catálogo vivo, pero no
  se confirmó que ningún hallazgo específico de Disciplina se haya quedado
  solo ahí.

---

## Próximos pasos sugeridos (para que decidas, no para ejecutar solos)

1. **Hallazgo 1 (crítico)** — antes de que se genere la próxima imputación por
   faltas, decidir si se corrige el generador o si, mientras tanto, cualquier
   imputación por faltas se revisa a mano contra el 21.5 antes de firmarla.
2. **Hallazgo 2** — cambio de una línea en cada plantilla; bajo riesgo,
   candidato a resolverse ya.
3. **Hallazgos 3, 4 y 5** — cambios acotados a funciones puntuales; ninguno
   toca dinero ni requiere migrar datos existentes.
4. **Catálogo obsoleto** — pasarlo una vez, marcando lo ya resuelto, para que
   la próxima sesión no reabra lo que ya está cerrado.
