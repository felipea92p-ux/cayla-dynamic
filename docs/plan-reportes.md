# Reportes — plan de la funcionalidad

Diseño acordado el 2026-09-26 para un espacio nuevo, **«Reportes»**, en el que
cada integrante puede reportar algo sobre una compañera o compañero, sobre la
empresa o sobre una clienta, o proponer una mejora. La líder de equipo actúa
primero, Desarrollo Organizacional (DO) es dueña de los plazos, y más adelante
una IA ayuda a ver patrones. **Todavía no hay código.**

Este documento tuvo dos rondas el mismo día:

1. **Investigación y cuestionario** (primer commit): buenas prácticas, las 10
   decisiones de Felipe y lo que ya dice el Reglamento, con dos choques abiertos.
2. **Elaboración** (este commit): los choques resueltos con Felipe, lo que el
   repositorio ya tiene y se reusa, y el diseño de la Fase 1 al nivel de tablas,
   funciones, RLS, pantallas y pruebas.

> Si retomas esto desde otra cuenta: las decisiones están en la **sección 5**,
> la regla de quién ve qué en la **sección 7**, y lo que falta en la **15**.
> Nada de lo de abajo se construye sin pasar antes por
> `./scripts/siguiente-numero.sh` y `./scripts/donde-vive.sh`.

---

## 1 · De dónde sale la idea

La idea de Felipe:

- toda integrante tiene un apartado «Reportes» en su espacio;
- elige a qué área va su reporte;
- admin y líderes ven estadísticas: dónde hay problemas y entre qué personas
  hay más conflictos;
- una IA lee lo cargado y detecta problemas chicos y grandes, qué puede
  escalar a futuro y cómo mejorar la relación entre el equipo y la empresa.

---

## 2 · Lo que ya existe en Dynamic (medido el 2026-09-26)

| Qué | Dónde | Cómo lo usa Reportes |
|---|---|---|
| Espacio de la colaboradora | `/mio` (`apps/web/app/(mio)/mio/page.tsx`), arreglo `SECCIONES` | «Reportes» entra como sección, con subrutas `/mio/reportes/…` |
| Roles | `packages/shared/src/enums.ts`: `integrante`, `supervisor_sede` (en pantalla, **líder de equipo**), `lider_do`, `admin` | Son los cuatro escalones de la cadena (sección 7) |
| El cargo que corresponde a cada rol | `fn_cargo_de_rol` (0074): `admin` → «Gerencia General» | **No sirve para Reportes.** Medido en producción el 2026-09-26: hay **5 admins activos** y la Gerencia General es **una sola persona**. Hace falta una marca propia (sección 7) |
| Cuántas personas hay en DO | Medido en producción el 2026-09-26: **1 persona activa con `lider_do`**, que no es la Gerencia General | Hay quien reciba un reporte sobre la Gerencia General. Si esa persona se va, el camino del 48.2-bis se queda sin receptora (sección 15) |
| Permisos | `packages/shared/src/permisos.ts` para la pantalla; RLS para la seguridad real (`fn_es_admin_o_lider`, `fn_rol_actual`, `fn_persona_actual_id`) | Una función nueva `puedeVerReportes` y la RLS propia de la sección 8 |
| **Días hábiles** | **`fn_sumar_dias_habiles(desde, n)` (0212)**: salta sábados, domingos y `feriados`, y vence a las 23:59 de Lima | Todos los plazos del Reglamento se calculan con ella. **No se escribe otra** |
| Mensaje libre a la líder | **`mensajes_encargada` (0435)**, con `fn_enviar_mensaje_encargada` y `fn_responder_mensaje_encargada`. **Sin pantalla**: ningún archivo de `apps/` la llama | Se solapa con Reportes: ver la decisión pendiente 15.4 |
| Expediente disciplinario | `expediente_disciplinario` (0056), `fn_expediente_puede_actuar` | El puente de la sección 11: un reporte **no** es una falta |
| Adjuntos privados | Bucket `expedientes` (0074), con políticas que llaman a una función de permiso | Mismo molde para el bucket `reportes` |
| Contestar a la persona | `/mio/bandeja` (reglas en `lib/bandeja-mia.ts`) | Las respuestas de un reporte aparecen ahí como una fuente más |
| Novedades | `apps/web/lib/novedades.ts` | La entrada «ya puedes enviar un reporte» va en el mismo PR |

Lo que **no** existe:

- No hay IA en el código: ninguna referencia a Anthropic ni a OpenAI en
  `apps/` ni en `packages/`.
- No hay un «jefe directo» en `personas`. Quién es la líder de una sede se
  resuelve como en la 0435: `rol = 'supervisor_sede' and sede_base_id = X`.
- No hay registro de quién es la Delegada contra el Hostigamiento de cada sede.
  La resolución transitoria (`docs/resolucion-designacion-hostigamiento.md`)
  tiene el nombre en blanco, y la elección figura como pendiente en
  `docs/reglamento-pendientes-de-construir.md` (entrada 16).
- `/admin/incidencias` son anomalías de asistencia, no reportes entre personas.
  El «buzón» de la 0225 guarda fotos de producto.

---

## 3 · Cómo lo hacen las mejores empresas (investigación)

1. **Separan lo grave de lo cotidiano.** Una sugerencia o una fricción del día
   a día no siguen el mismo camino que un acoso o un fraude.
2. **Usan «confidencial» más que «anónimo».** Culture Amp prefiere esa palabra
   a propósito: el nombre existe, pero solo lo ve quien gestiona. El anonimato
   total dificulta investigar y da pie a reportes maliciosos. El Reglamento dice
   lo mismo en el 48.11: *la reserva no es anonimato*.
3. **Nadie investiga su propio caso** (ISO 37002: imparcialidad y conflicto de
   interés).
4. **Quien reporta recibe respuesta:** acuse, un estado que puede seguir y un
   cierre con lo que se hizo.
5. **No muestran estadísticas de grupos chicos.** El piso aceptado es de 5
   personas; por debajo se adivina quién fue. Con 4 sedes pequeñas, esto pesa
   mucho en CAYLA.
6. **Protegen contra represalias.** La persona reportada no sabe quién la
   reportó, y la represalia es falta.
7. **Usan formularios estructurados:** qué pasó, cuándo, dónde, quiénes
   estuvieron, testigos, evidencia y qué espera quien reporta.
8. **La IA detecta temas, riesgos y tendencias, pero no juzga personas**, con
   supervisión humana. Es el mismo principio de Dynamic: **avisa, nunca
   sanciona sola.**

Fuentes:

- [ISO 37002 – PECB](https://pecb.com/en/whitepaper/iso-370022021-whistleblowing-management-systems)
- [ISO 37002 – Whispli](https://www.whispli.com/blog/implementing-iso37002-compliant-whistleblowing-program)
- [Directiva UE, plazos – Bird & Bird](https://www.twobirds.com/en/trending-topics/the-eu-whistleblowing-directive/implementation-status/timescales)
- [Ley 27942 – Buk](https://www.buk.pe/blog/ley-27942-prevencion-sancion-hostigamiento-sexual)
- [Ley 27942 – GeoVictoria](https://www.geovictoria.com/es-pe/blog/-ley-27942)
- [Umbral de anonimato – CultureMonkey](https://www.culturemonkey.io/employee-engagement/anonymity-thresholds-in-employee-surveys/)
- [Culture Amp: confidencial vs. anónimo](https://www.cultureamp.com/blog/anonymous-feedback-importance)
- [IA y supervisión humana – Forsta](https://www.forsta.com/resources/blog/ai-customer-feedback-analysis/)
- [Software de gestión de casos – HR Acuity](https://www.hracuity.com/blog/best-hr-case-management-software-2026/)
- [Software de relaciones laborales – AllVoices](https://www.allvoices.co/blog/best-hr-case-management-software)
- [Formulario de registro – DianaHR](https://www.getdianahr.com/blog/employee-relations-playbook-intake-triage-resolution)

---

## 4 · Lo que ya dice el Reglamento Interno (no se reinventa)

Revisado en `docs/reglamento-interno-de-trabajo.md` (v4.0) y
`docs/politica-prevencion-hostigamiento-sexual.md`. **Reportes no crea un
procedimiento nuevo: es el canal digital y el registro de tres procedimientos
que ya existen.**

| Vía | Artículo | Quién recibe | Plazos |
|---|---|---|---|
| **Reclamo** — consultas, reclamos y sugerencias | **43-B** | La encargada de sede, la líder o DO (43-B.1) | DO responde por escrito en **10 días hábiles**, o avisa en ese plazo cuándo lo hará (43-B.2) |
| **Convivencia** — acoso laboral o maltrato sin connotación sexual | **43-A** | DO. Contra la titular de DO, la **Gerencia General**. Contra la Gerencia General, por analogía el **48.2-bis** (43-A.5) | Acuse en **1 día hábil**; resolución escrita en **15 días hábiles** (43-A.6) |
| **Título X** — hostigamiento sexual o hechos de connotación sexual o sexista | Arts. 47–51 | DO recibe y decide (48.1). Investiga la **Delegada** de la sede o, mientras no haya, quien designe la Gerencia General (48.3) | Nueve plazos, los del 49.4 (sección 10) |

Lo que el Reglamento ya fija y el diseño respeta:

- **43-B.4:** *«DO lleva un registro de las consultas y reclamos recibidos, de
  su fecha y de su resultado, que emplea para identificar problemas recurrentes
  y corregirlos.»* Las estadísticas y el informe de la IA son la forma de
  cumplir ese artículo.
- **Represalias** prohibidas en los 43-A.7, 43-B.5 y 51, y agravadas en el
  48.2-bis d): mientras un caso contra la Gerencia General está en trámite,
  nadie puede tocar el turno, la sede, la renovación ni el régimen disciplinario
  de la afectada, de quien reportó ni de las testigos, salvo DO con motivo
  escrito.
- **Reserva del Título X** (44.7, 48.10, 48.12): solo acceden quienes
  intervienen en el procedimiento. **No revictimización (48.14): prohibidos los
  careos y las confrontaciones.** Por eso en el Título X nadie media.
- **Deber de comunicar (49.3):** la Gerencia General, DO, las encargadas de
  sede y las líderes que se enteren de un posible hostigamiento sexual deben
  comunicarlo a DO **en 1 día hábil**. No hacerlo es falta.
- **El formato no condiciona la queja (48.8):** ningún campo obligatorio del
  formulario puede impedir presentar una queja del Título X.

### Lo que el Título IX no cubre todavía

- **Finalidades (44.4).** Enumera nueve finalidades y prohíbe cualquier otra.
  «Gestionar reportes entre personas» y «analizar el clima con IA» no están. La
  Fase 1 se apoya en los 43-A, 43-B y el 44.4 d), que incluye el riesgo
  psicosocial del 43-A.8. El análisis y el mapa, en cambio, necesitan la
  reforma (sección 14).
- **Conservación (44.12).** Prohíbe conservar datos indefinidamente y no tiene
  un plazo para los reportes.
- **Encargados del tratamiento (44.8).** Un proveedor de IA recibe datos por
  encargo, así que CAYLA tiene que trasladarle por escrito las obligaciones del
  Título IX **antes** de enviarle cualquier dato.

---

## 5 · Las decisiones de Felipe

### Primera ronda (cuestionario del 2026-09-26)

| # | Pregunta | Respuesta |
|---|---|---|
| 1 | Tipos de reporte | Compañera/o del equipo · La empresa · Una clienta · Idea de mejora |
| 2 | Identidad de quien reporta | **Confidencial**: el nombre queda guardado y solo lo ve quien gestiona |
| 3 | Quién recibe y gestiona | Admin, líder DO y las líderes de equipo de su sede, salvo los reportes que las mencionan *(precisado en la segunda ronda)* |
| 4 | Reportes sobre alguien del panel | «Solo a Felipe» *(reemplazado en la segunda ronda)* |
| 5 | Qué ve la persona reportada | **Nada hasta que DO decida conversar.** Nunca ve quién la reportó |
| 6 | Hostigamiento sexual y casos graves | **Camino propio con plazos** (Título X) |
| 7 | Estadística sobre personas | **Mapa de conflictos completo**, con los resguardos de la sección 12 |
| 8 | Qué recibe quien reporta | **Estados y respuesta final**; puede responder preguntas de DO |
| 9 | Papel de la IA | Informe mensual · Ordena al llegar · Sugiere cómo manejar un caso · Ayuda a redactar · y pidió investigar más funciones (sección 13) |
| 10 | Datos del reporte | Fecha y sede del hecho · Fotos o archivos · Testigos · Qué espera que pase · y pidió ver qué piden otras empresas (sección 6) |

### Segunda ronda (misma fecha): los dos choques, resueltos

| # | Tema | Decisión |
|---|---|---|
| 11 | **La cadena** | **Colaboradora → líder de equipo → DO → admin** (el último escalón es la Gerencia General, no cualquier admin: decisión 18). Un reporte lo gestiona el escalón que está por encima de la persona reportada. Nunca le llega a quien es mencionada |
| 12 | **Reporte sobre la Gerencia General** (Felipe) | Se sigue el **48.2-bis**: la Gerencia General queda apartada; **recibe y decide DO** (líder DO); investiga la Delegada o, si depende directamente del admin, una persona externa. No va a alguien «de rango parecido»: una socia o directora también puede ser denunciada por la misma regla |
| 13 | **La líder de equipo en reclamos y convivencia** | **Ve todo lo de su sede**, incluidos los conflictos entre compañeras y el acoso laboral, **para mediar y resolver primero**. DO recibe el aviso de todo, sin urgencia, y entra si el caso escala. **Si el reporte es sobre la líder, va directo a DO** |
| 14 | **Acoso laboral (43-A)** | **La líder actúa y DO es dueña del plazo.** El sistema acusa recibo a nombre de DO y el cierre escrito de los 15 hábiles lo firma DO, que puede recoger lo que hizo la líder. Cumple el 43-A sin reformarlo |
| 15 | **Título X en Dynamic** | **Orienta y también recibe la queja completa**, con acceso exclusivo |
| 16 | **La líder y el Título X** | **No ve el contenido.** Apoya cuando DO se lo pide: recibe solo la instrucción de una medida de protección, como cambiar un turno, y la ejecuta. Felipe había propuesto que mediara; se descartó porque el 48.14 prohíbe la confrontación |
| 17 | **Finalidad de datos (44.4)** | **La Fase 1 sale ya.** Antes de la IA y el mapa, una **v4.1 del Reglamento** agrega la finalidad, el plazo de conservación y la proveedora de IA |

### Tercera ronda (misma fecha): con los números de producción

Felipe corrió la consulta de la sección 15 en el SQL Editor: **5 admins
activos y 1 `lider_do`**. Con eso, la ecuación «admin = Gerencia General» de
la segunda ronda no se sostiene.

| # | Tema | Decisión |
|---|---|---|
| 18 | **Quién es la Gerencia General** | **Solo Felipe.** Los otros cuatro admins tienen el rol por temas operativos |
| 19 | **Quién ve los reportes de las sedes** | **La líder de la sede, DO y la Gerencia General.** Los demás admins **no** ven reportes. Es el círculo más chico que cumple el Reglamento |

---

## 6 · Lado colaboradora: «Reportes» en `/mio`

### Nuevo reporte

**Paso 0, arriba y siempre visible:** *«¿Es acoso sexual, un comentario o
contacto de tipo sexual, o hay un riesgo para alguien ahora?»*

- **Sí, es de tipo sexual:** pasa al **camino del Título X**. La pantalla
  explica en dos líneas quién lo va a leer (DO y quien investiga en su sede; su
  líder **no**), muestra el canal en papel y los canales externos del 48.9, y
  ofrece el formulario. **Ningún campo es obligatorio salvo el relato** (48.8).
- **Riesgo ahora** (violencia, amenaza): el reporte entra como **urgente** por
  la vía de convivencia, y DO recibe el aviso al instante, no en el resumen.
  La pantalla muestra además los teléfonos de emergencia.

**Paso 1 · ¿Sobre qué?**

| Opción | Vía que abre | Nota |
|---|---|---|
| Una persona del equipo | **Convivencia** (43-A) si marca *«es maltrato o acoso»*; si no, **reclamo** (43-B) | La líder o DO pueden reclasificarlo, y queda en la línea de tiempo |
| La empresa (proceso, herramienta, sede, turnos, condiciones) | Reclamo (43-B) | |
| Una clienta | Reclamo (43-B) | Si el hecho es de tipo sexual, pasa al Título X, que también alcanza a clientas (47.7) |
| Una idea de mejora | Reclamo (43-B), como sugerencia | |

**Paso 2 · Qué pasó.** Texto libre. En la Fase 2, la IA ayuda a contar hechos
(qué, cuándo, dónde) sin juicios.

**Paso 3 · Detalles:**

- **fecha del hecho:** arranca en **hoy**, visible y editable (regla quinta de
  `CLAUDE.md`: una fecha que bloquea el envío no puede arrancar vacía);
- **sede del hecho:** arranca en su sede base;
- personas involucradas (varias, del padrón) y testigos (del padrón);
- fotos o archivos, en el bucket privado `reportes`;
- «¿es la primera vez?» y «¿ya lo conversaste con alguien?»;
- si es sobre una clienta: fecha, sede y, si quiere, un número de ticket. **No
  se piden datos personales de la clienta.**

**Paso 4 · Qué esperas que pase:** que se sepa · conversar · que cambie algo ·
que se actúe.

**Antes de enviar, «quién lo va a leer».** Una línea con los **cargos** que
van a ver el reporte (nunca nombres), calculada por la base con
`fn_reporte_quien_lo_leera` para que la pantalla no repita la regla. Recuerda
además que la persona reportada no sabrá quién fue y que las represalias están
prohibidas (43-A.7, 43-B.5, 51).

### Mis reportes

- Estado visible: **Recibido → En revisión → Cerrado**.
- Un hilo con quien gestiona, con preguntas y respuestas. Las respuestas nuevas
  aparecen también en `/mio/bandeja`.
- El **plazo** que corre, en palabras: «DO te responde a más tardar el
  jueves 8».
- Al cerrar, el **mensaje de cierre**, que es la respuesta escrita que exigen
  el 43-A.6 y el 43-B.2.
- Quien reporta **no ve** las notas internas, la reclasificación ni quién más
  participa.

---

## 7 · La regla de quién ve qué

Es el corazón del diseño y vive **una sola vez**, en `fn_reporte_puede_ver`
(sección 8). Todo lo demás la llama: la RLS, el bucket, la bandeja y
`fn_reporte_quien_lo_leera`.

### Los escalones

| Nivel | Quién | En pantalla |
|---|---|---|
| 0 | rol `integrante` | colaboradora |
| 1 | rol `supervisor_sede` | líder de equipo |
| 2 | rol `lider_do`, **y los admins que no son la Gerencia General** | DO · panel |
| 3 | **la Gerencia General**: la persona marcada, no el rol (ver abajo) | Gerencia General |

**La Gerencia General es una marca, no un rol.** En producción hay 5 admins
y una sola Gerencia General (decisión 18). Si Reportes tomara `admin` como
Gerencia General, un reporte sobre cualquier admin pasaría por el 48.2-bis, y
los cinco verían todos los reportes. La marca vive en `configuracion`, con la
clave `gerencia_general` y el valor `{"persona_id": …}`. Es una sola fila y no
una columna de `personas`, porque hay una sola persona y la pregunta es «quién
es», no «¿esta persona lo es?». La cambia solo una función guardián,
`fn_set_gerencia_general`, que deja rastro en `reporte_eventos` y avisa a DO.
Como el nivel y la ruta de cada reporte se guardan al crearlo, **cambiar la
marca no abre los reportes que ya existen**: quien se quita la marca no gana
acceso a lo que se dijo de ella.

Los admins que no son la Gerencia General quedan en el nivel 2: un reporte
sobre ellos lo gestiona la Gerencia General, igual que uno sobre DO. **Por
tener el rol no ven reportes** (decisión 19).

El **nivel del reporte** es el nivel más alto entre las personas
**involucradas**. Las testigos no lo suben. Se guarda al crear el reporte, como
la sede en la 0435: si alguien cambia de rol después, el reporte no se vuelve
visible para quien antes no podía verlo.

### Reclamo (43-B) y convivencia (43-A)

| Nivel del reporte | Líder de equipo de la sede del hecho | DO (`lider_do`) | Gerencia General | Otros admins |
|---|---|---|---|---|
| Sin personas (empresa, clienta, idea) | ✅ gestiona | ✅ recibe aviso | ✅ | ❌ |
| 0 · sobre una colaboradora | ✅ **gestiona y media** | ✅ recibe aviso; entra si escala | ✅ | ❌ |
| 1 · sobre una líder de equipo | ❌ | ✅ **gestiona** | ✅ | ❌ |
| 2 · sobre DO o sobre otro admin | ❌ | ❌ si es sobre DO; ✅ si es sobre otro admin | ✅ **gestiona** (43-A.5) | ❌ |
| 3 · sobre la Gerencia General | ❌ | ✅ **recibe y decide** (48.2-bis) | ❌ **apartada** | ❌ |

Y siempre, para cualquier fila:

- **Quien está mencionada**, como involucrada o como testigo, **no ve el
  reporte**, sea cual sea su rol.
- **Quien reporta** ve su reporte, sin las notas internas.
- La líder que ve un reporte es la de **la sede del hecho**, no la de quien
  reporta. Si la sede tiene dos líderes, lo ven las dos.

### Título X

| Quién | Ve |
|---|---|
| Quien presenta la queja | La suya, con estado, plazos e hilo |
| DO (`lider_do`) no mencionada | ✅ recibe y decide (48.1) |
| La **investigadora** de la sede (Delegada titular; si está impedida, la suplente; mientras no haya, la designada) | ✅, salvo que esté mencionada (48.3) |
| Gerencia General | Solo si la queja es contra DO (48.2). **Nunca** si es contra ella (48.2-bis a) |
| Otros admins | ❌ |
| Líder de equipo | ❌ **Nunca el contenido.** Solo la **instrucción** de una medida de protección que DO le encargue, sin los hechos |
| Persona externa del 48.2-bis b) | Trabaja fuera de Dynamic; DO registra sus actuaciones |

### Lo que la RLS no puede prometer

La RLS protege contra **el panel**, no contra **quien administra la base**.
Quien tiene el SQL Editor de Supabase puede leer cualquier tabla, y hoy ese es
Felipe. Para un reporte **sobre Felipe**, eso significa que la reserva del
48.2-bis a) no está garantizada técnicamente. Mitigaciones:

1. La pantalla lo dice, sin rodeos, cuando la persona elige a alguien del
   panel como involucrado, y ofrece las otras vías: el sobre cerrado del 48.7 y
   los canales externos del 48.9.
2. Toda lectura de un reporte desde el panel queda registrada (sección 8), así
   que abrirlo por pantalla deja rastro.
3. *(A futuro, si se pide)* cifrar el relato con una clave que custodia DO.
   Hoy es desproporcionado para el tamaño de CAYLA, y queda anotado como
   límite, no como descuido.

---

## 8 · El modelo de datos (Fase 1)

Números de migración: se piden con `./scripts/siguiente-numero.sh` **al
empezar**, no se fijan aquí. Nombres en español, como el resto del esquema.

### Tablas

**`reportes`**, la cabecera del caso:

| Columna | Tipo | Nota |
|---|---|---|
| `id` | uuid | |
| `codigo` | text único | Legible, del tipo `R-2026-0007`, para hablar del caso sin nombrar a nadie |
| `autor_id` | uuid → personas | Confidencial: solo lo ven quienes gestionan |
| `sede_id` | uuid → sedes | **Del hecho**, no del autor |
| `tipo` | text check | `persona` · `empresa` · `clienta` · `idea` |
| `via` | text check | `reclamo` (43-B) · `convivencia` (43-A) · `titulo_x` |
| `urgente` | bool | Riesgo ahora |
| `nivel` | smallint 0–3 | Nivel del reporte (sección 7). Se guarda al crear y se recalcula solo si se agrega una involucrada |
| `fecha_hecho` | date not null | |
| `relato` | text not null | |
| `espera` | text check | `que_se_sepa` · `conversar` · `que_cambie` · `que_se_actue` |
| `primera_vez`, `ya_conversado` | bool / text, opcionales | |
| `ticket` | text opcional | Solo en reportes sobre una clienta |
| `estado` | text check | `recibido` · `en_revision` · `cerrado` |
| `gestiona` | text check | `lider` · `do` · `admin`. Quién lleva el caso ahora; `escalar` lo sube |
| `creado_at`, `acuse_at`, `cerrado_at` | timestamptz | |
| `vence_acuse_at`, `vence_respuesta_at` | timestamptz | De `fn_sumar_dias_habiles` al crear; se recalculan si cambia la vía |
| `cierre_texto` | text | La respuesta escrita. Obligatoria para cerrar |
| `cierre_resultado` | text check | `resuelto` · `confirmado` · `no_confirmado` · `derivado_disciplinario` · `sin_accion` |
| `expediente_id` | uuid → expediente_disciplinario, opcional | El puente de la sección 11 |

**`reporte_personas`:** `reporte_id`, `persona_id` y `papel` (`involucrada` ·
`testigo`). Única por (reporte, persona).

**`reporte_mensajes`**, el hilo: `autor_id`, `texto`, `interno` (bool; las
notas internas no las ve quien reporta) y `creado_at`. Es append-only: no se
edita ni se borra.

**`reporte_eventos`**, la línea de tiempo y el rastro: `tipo` (`creado`,
`acuse`, `estado`, `reclasificado`, `escalado`, `medida`,
`derivado_expediente`, `cerrado`, `lectura`), `por`, `at` y `detalle jsonb`.
Es la trazabilidad que exige el 44.13, y registra también **cada vez que
alguien del panel abre la ficha** (`lectura`). No se usa
`correcciones_auditoria`, porque esa tabla está hecha para marcajes: exige
`persona_id` y `campo_modificado` y no tiene dónde guardar «quién leyó».

**`reporte_medidas`**, la instrucción que ve la líder en el Título X:
`reporte_id`, `para_persona_id` (la líder que la ejecuta), `instruccion` (texto
**sin los hechos**), `vigente_hasta`, `cumplida_at`. La líder ve esta fila y
nada más del reporte.

**`organos_titulo_x`:** quién investiga en cada sede. `sede_id`, `persona_id`,
`papel` (`delegada` · `suplente` · `designada`), `desde`, `hasta`. La gestiona
DO desde una pantalla, porque su verdad está en un acta, no en el código.

### Funciones

Todas `SECURITY DEFINER`, con guardas null-safe (`is not true`), mensajes en
español y `grant` solo a `authenticated`.

| Función | Hace |
|---|---|
| `fn_gerencia_general_id()` | La persona marcada en `configuracion.gerencia_general`, o `null` si falta. Si falta, los reportes de nivel 2 y 3 no tienen quién los gestione, y la bandeja de DO lo avisa |
| `fn_set_gerencia_general(persona, motivo)` | Cambia la marca. Solo la puede llamar un admin; deja rastro y avisa a DO. No toca los reportes ya creados |
| `fn_reporte_nivel_persona(persona)` | Del 0 al 3 según la tabla de escalones: el 3 es solo para quien devuelve `fn_gerencia_general_id()`, y el resto sale del rol **actual y activo** (`personas.estado = 'activo'`, como `fn_rol_actual` desde la 0374) |
| **`fn_reporte_puede_ver(reporte)`** | **La regla de la sección 7.** Devuelve boolean, nunca `null` |
| `fn_reporte_quien_lo_leera(via, sede, personas[])` | Lo que el paso final de la pantalla muestra: cargos, sin nombres |
| `fn_reporte_crear(…)` | Valida, calcula `nivel`, `gestiona` y los plazos, guarda y **acusa recibo** (evento `acuse` a nombre de DO) |
| `fn_reporte_mensaje(reporte, texto, interno)` | Agrega al hilo. Solo quien gestiona puede escribir `interno = true` |
| `fn_reporte_estado(reporte, estado, motivo)` | `recibido → en_revision`; nunca retrocede desde `cerrado` |
| `fn_reporte_reclasificar(reporte, via, motivo)` | Por ejemplo, la líder detecta que es de tipo sexual: pasa a `titulo_x` y **la líder pierde el acceso en el acto**. Eso cumple por sí solo el deber del 49.3 |
| `fn_reporte_escalar(reporte, motivo)` | La líder sube el caso a DO (`gestiona = 'do'`) |
| `fn_reporte_cerrar(reporte, resultado, texto)` | Exige el texto. En convivencia y Título X, **solo cierra DO** (decisiones 14 y 12) |
| `fn_reporte_derivar(reporte, expediente)` | Enlaza con un expediente que ya existe. **No lo crea ni sanciona** |
| `fn_reporte_medida(reporte, lider, instruccion, hasta)` | Solo DO. Crea la fila de `reporte_medidas` |
| `fn_reportes_bandeja()` / `fn_reportes_mios()` | Listados para cada pantalla, con el plazo que corre y su semáforo |

**El molde de campo sensible de `CLAUDE.md`:** RLS encendida en las seis
tablas, con **políticas de `select`** que llaman a `fn_reporte_puede_ver` y
**sin políticas de `insert`, `update` ni `delete`**. Toda escritura pasa por
las funciones, y un trigger `before update` en `reportes` rechaza cambios que
no vengan de ellas (`current_user <> 'postgres'`). Es la cuarta instancia del
molde, después de la 0261, las 0295/0296 y la 0342.

**Bucket `reportes`**, privado: ruta `<reporte_id>/<uuid>.<ext>`. Las
políticas de lectura y escritura llaman a `fn_reporte_puede_ver`, con el mismo
molde que el bucket `expedientes` de la 0074. Formatos: imagen (con HEIC,
como la 0170) y PDF.

---

## 9 · Lado panel: «Reportes» en `/admin`

### Bandeja

- Lo que la persona puede ver según la sección 7, **lo urgente primero** y
  después por vencimiento.
- Un semáforo por plazo: verde, por vencer (queda 1 día hábil) y vencido.
- El filtro por defecto de la líder es «lo que gestiono»; el de DO, «todo»,
  con la marca «lo lleva la líder».
- El menú muestra un contador de nuevos. **El aviso nunca lleva el contenido**:
  ni en el contador ni en ningún correo.

### Ficha del caso

- lo reportado y la evidencia;
- el hilo con quien reportó y las **notas internas**;
- la línea de tiempo: conversación, mediación, reclasificación, escalamiento,
  medida, derivación;
- los plazos y quién es dueña de cada uno;
- el cierre escrito;
- *(Fase 2)* la sugerencia de la IA, marcada como sugerencia.

### Lo que hace la líder, y lo que no

- **Puede:** leer, conversar con quien reportó, anotar, registrar una
  mediación, cambiar a «en revisión», reclasificar y escalar. En reclamos
  (43-B), también cerrar.
- **No puede:** cerrar un caso de convivencia (lo cierra DO, decisión 14), ver
  nada del Título X más allá de su instrucción, ni abrir un expediente
  disciplinario desde aquí.
- La pantalla le recuerda el 43-A.3: una observación hecha con respeto no es
  acoso.

### Pantalla de órganos del Título X

Una lista corta dentro de `/admin/reportes` para registrar quién investiga en
cada sede, con la fecha del acta. Mientras esté vacía, los reportes del Título X
de esa sede **muestran una alerta a DO**: nadie puede investigar, y el 49.4 b)
da 1 día hábil para correr traslado.

---

## 10 · Los plazos, calculados

Todos con `fn_sumar_dias_habiles`, salvo los días calendario, que son una suma
directa. El plazo se muestra junto con **quién es su dueña**.

| Vía | Plazo | Desde | Dueña |
|---|---|---|---|
| Reclamo | Respuesta escrita, o aviso de cuándo: **10 hábiles** | Recepción | DO (aunque lo lleve la líder) |
| Convivencia | Acuse: **1 hábil** | Recepción | DO. Lo da el sistema al crear |
| Convivencia | Resolución escrita: **15 hábiles** | Recepción | DO |
| Título X | a) Atención en salud: 1 hábil · b) Traslado a quien investiga y aviso a la denunciada: 1 hábil · c) Medidas de protección: 3 hábiles · d) Aviso al MTPE: 6 hábiles | Recepción | DO |
| Título X | e) Informe: **15 calendario** · f) Traslado a DO: 1 hábil desde el informe · g) Decisión: **10 calendario** desde el informe · h) Aviso de la decisión al MTPE: 6 hábiles | Según cada literal | Quien investiga / DO |
| Título X | i) Indicios de delito: **24 horas** | Conocimiento | DO |

Los plazos del Título X que dependen de un hecho anterior (el informe, la
decisión) se calculan cuando ese hecho se registra como evento.

---

## 11 · Puente con disciplina

**Un reporte no es una falta.** Si DO decide actuar, abre el expediente del
Título XI por el camino que ya existe (arts. 55 y 57), y en el reporte solo
queda el enlace (`fn_reporte_derivar`). Nada se sanciona desde Reportes, y el
expediente no hereda el nombre de quien reportó.

La suspensión temporal como medida de protección se paga (50.6), así que una
medida de ese tipo **no** se registra solo en Reportes: se carga como ausencia
justificada pagada por el camino de siempre, para que la planilla la vea.

---

## 12 · El mapa de conflictos y sus resguardos (Fase 3)

Felipe eligió la opción más potente, que también es la más delicada:

- **Lo ven solo la Gerencia General y DO.** Ni los otros admins ni las líderes, porque en una sede de 4 personas
  «quién reporta a quién» deja de ser confidencial al instante. *(Pendiente de
  confirmar.)*
- **Los casos del Título X y los que suben por la cadena** (reportes sobre
  gente del panel) **no aparecen en el mapa de nadie.**
- **Cada relación muestra en qué terminaron sus casos:** confirmado, no
  confirmado o resuelto. Que te reporten muchas veces no prueba nada; los
  falsos positivos son el peor error del sistema.
- **Aviso fijo:** *«un reporte no es una falta»*.
- **Registro de consultas:** abrir el mapa es un evento `lectura`.
- **Alerta de represalia:** avisa si quien reportó, o una testigo, empieza a
  recibir reportes, cambios de turno, de sede o documentos disciplinarios poco
  después (43-A.7, 48.2-bis d). Esta sí conviene adelantarla: se puede
  construir sin IA en cuanto exista `reporte_personas`.
- Requiere la **v4.1** (sección 14) antes de encenderse.

---

## 13 · La IA (Fase 2)

| Función | Qué hace |
|---|---|
| Ayuda a redactar | Convierte «me trata mal» en hechos concretos y sugiere qué dato falta |
| Ordena al llegar | Sugiere tema y gravedad, y detecta si se parece a otro caso abierto |
| Sugiere cómo manejarlo | Propone pasos y un borrador del cierre escrito |
| Informe mensual | Qué se repite, qué crece, qué puede escalar y qué mejorar (43-B.4) |
| Alertas tempranas | Una misma persona, sede o tema que junta reportes de fuentes distintas en poco tiempo |
| Cruce con datos de Dynamic | Reportes contra tardanzas, rotación, cambios de turno y riesgo psicosocial de la sede (43-A.8) |
| Pulso de ideas | Agrupa las ideas de mejora y muestra cuáles se piden más |

**Reglas:**

- Nunca decide ni califica a una persona. Todo lo que produce queda marcado
  como sugerencia, y una persona lo confirma.
- **No participa en el Título X.**
- Antes de mandar texto a la IA se reemplazan los nombres por códigos.
- Requiere la **v4.1** (finalidad y encargada del tratamiento) y el traslado
  escrito de obligaciones a la proveedora (44.8).
- Infraestructura nueva: una ruta en `apps/web/app/api/` y una clave como
  variable de entorno en Vercel. Modelo por defecto: el Claude vigente más
  capaz. Se decide al empezar la Fase 2.

---

## 14 · Qué lleva la v4.1 del Reglamento

Es un borrador para revisar con el asesor. Entra en vigencia con su entrega
con cargo (60.6), y la pantalla Normas ya sabe registrar ese acuse (60.3 c).

1. **44.4, nuevo literal j):** *tramitar las consultas, reclamos, sugerencias,
   comunicaciones de convivencia y quejas de los artículos 43-A, 43-B y 47 a 51,
   llevar su registro y analizarlo, incluso con herramientas automatizadas bajo
   supervisión humana, para identificar problemas recurrentes y prevenirlos.*
2. **44.12, nuevo literal f):** plazo de conservación de los reportes. La
   propuesta es **4 años desde el cierre**, el mismo criterio del literal c)
   (prescripción de la Ley 27321). Después se borran el relato, los mensajes y
   los adjuntos, y quedan el tipo, la sede, el mes y el resultado, sin nadie
   vinculado, para la estadística.
3. **44.8:** nombrar entre los destinatarios a la proveedora de IA como
   encargada del tratamiento.
4. **43-A.6, una frase:** *DO puede encargar a la líder de equipo la
   conversación y la mediación, sin que ello altere sus plazos ni su
   responsabilidad.* La decisión 14 ya cumple sin esta frase; con ella, lo que
   hace la líder queda escrito donde se lee.

---

## 15 · Lo que falta decidir o averiguar

1. ~~**¿Quién tiene hoy el rol `lider_do`?**~~ **Respondido el 2026-09-26:** 1
   `lider_do` y 5 admins activos. De ahí salen las decisiones 18 y 19 y la
   marca de Gerencia General de la sección 7. **Lo que queda es un riesgo, no
   una pregunta:** el camino del 48.2-bis depende de **una sola persona**. Si
   la única `lider_do` se va o se ausenta, un reporte sobre la Gerencia General
   no tiene quién lo reciba dentro de Dynamic. En ese caso, la pantalla debe
   mandar al sobre cerrado (48.7) y al canal externo (48.9), y avisarlo al
   crear el reporte, no después. La prueba pgTAP cubre este caso con la
   `lider_do` inactiva.
2. **¿Quién investiga el Título X en cada sede hoy?** La resolución transitoria
   tiene el nombre en blanco, y las elecciones de Delegada vencían el
   9 de septiembre de 2026. Sin ese dato, `organos_titulo_x` arranca vacía y
   todo reporte del Título X nace con alerta.
3. **Mapa de conflictos:** ¿se confirma que solo lo ven la Gerencia General y DO? (La sección 12 decía «admin y DO»; con la decisión 19, los otros admins quedan fuera.)
4. **¿Qué pasa con la 0435 (`mensajes_encargada`)?** Ya existe en la base, sin
   pantalla. Un mensaje a la líder **es** una consulta del 43-B, así que le
   corre el mismo plazo de 10 hábiles; si viven separados, uno de los dos
   caminos no cuenta el plazo. **Recomendación:** Reportes absorbe ese caso
   como un quinto tipo, «Consulta a mi líder», y la 0435 no recibe pantalla.
   Antes, confirmar en producción que no tiene filas.
5. **Retención:** ¿4 años desde el cierre, como propone la sección 14?
6. **Proveedora de IA:** se decide en la Fase 2.

---

## 16 · Fases y orden de construcción

**Fase 1, sin IA.** Cada paso es un PR, y la migración se pega **antes** de
fusionar, porque fusionar a `main` es publicar:

1. **Tablas, `fn_reporte_puede_ver`, RLS y bucket**, con pgTAP que recorre
   **cada celda de las dos tablas de la sección 7**: cada rol contra cada nivel,
   quien está mencionada, quien reporta, la investigadora, la Gerencia General apartada, los otros admins sin acceso y la `lider_do` inactiva.
   Es la prueba que más vale de toda la funcionalidad. Incluye el control: la
   misma consulta hecha por un `authenticated` sin función guardián no
   devuelve nada.
2. **Funciones guardián y plazos**, con pgTAP de cada transición, del trigger
   que bloquea el `UPDATE` directo, de la reclasificación que quita el acceso a
   la líder y de los vencimientos con un feriado en medio.
3. **`/mio/reportes`**: formulario, «Mis reportes» y la fuente en la Bandeja.
   Incluye la entrada en `novedades.ts`, sin montos, nombres ni nada
   disciplinario.
4. **`/admin/reportes`**: bandeja, ficha, pantalla de órganos y
   `puedeVerReportes` en `permisos.ts` y en `nav-items.ts`.
5. **Estadísticas básicas** por tipo, sede y mes, con tiempo de respuesta y
   cumplimiento de plazos. A la líder, solo las de su sede y sin nada por
   persona.
6. **Alerta de represalia sin IA** (sección 12), si da el tiempo.

**Fase 2 (con la v4.1 entregada):** IA para redactar, ordenar, sugerir e
informar.

**Fase 3:** mapa de conflictos, alertas tempranas y cruce con asistencia.

Recordatorios del repo para cuando se construya:

- `./scripts/siguiente-numero.sh` antes de crear cada migración y cada prueba;
- `./scripts/donde-vive.sh` antes de **crear** cada función, no solo al
  reescribirla (la 0297/0299);
- `git log --all` y `git grep` de `fn_reporte` en todas las ramas antes de
  empezar;
- registro con `on conflict (numero) do update`;
- solo colores `--color-*`;
- toda fecha que bloquee el envío arranca con un valor (el del hecho = hoy);
- en pantalla, **«líder de equipo»**, nunca «encargada». Solo se dice
  «encargada de sede» al citar el Reglamento textual.
