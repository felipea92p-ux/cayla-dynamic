# Reportes — plan de la funcionalidad

Diseño acordado el 2026-09-26 para un espacio nuevo, **«Reportes»**, en el que
cada integrante puede reportar algo sobre una compañera o compañero, sobre la
empresa o sobre una clienta, o proponer una mejora. DO y las encargadas lo
gestionan, y una IA ayuda a ver patrones. **Todavía no hay código.** Este
documento reúne la investigación, las 10 decisiones que tomó Felipe, lo que ya
dice el Reglamento Interno y lo que falta decidir antes de escribir la primera
migración.

> Si retomas esto desde otra cuenta: lee primero la sección **«Lo que ya dice
> el Reglamento»**. Hay dos decisiones del cuestionario que chocan con él y hay
> que resolverlas antes de construir.

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

- **El espacio de la colaboradora es `/mio`** (`apps/web/app/(mio)/mio/page.tsx`).
  No hay ninguna ruta «info». `/mio` es una sola página con secciones (arreglo
  `SECCIONES`): Resumen, Mis días, Mis turnos, Mi DNI, Tus datos, Vacaciones y
  permisos, Contrato, Movilidad, Educación, Firma, Objetivos, Historial. Además
  tiene subrutas: `/mio/bandeja`, `/mio/boleta`, `/mio/contrato`, etc.
  «Reportes» entra como una sección más, con su subruta `/mio/reportes`.
- **Roles** (`packages/shared/src/enums.ts`): `integrante`, `supervisor_sede`
  (que en pantalla se llama **encargada**), `lider_do` y `admin`. Los permisos
  se escriben como funciones en `packages/shared/src/permisos.ts`, que agrupa
  `ROLES_DO` (admin + lider_do) y DO + encargada. **La seguridad real está en
  RLS** (`fn_es_admin_o_lider`, `fn_rol_actual`; ver la 0078).
- **No existe nada parecido.** `/admin/incidencias` son anomalías de
  asistencia, no reportes entre personas. El «buzón» de la 0225 guarda fotos
  de producto.
- **Hoy no hay IA en el código.** No hay ninguna referencia a Anthropic ni a
  OpenAI en `apps/` ni en `packages/`.
- **Sedes y áreas ya son catálogos:** `sedes` (0001, gestionable desde la
  0063) y `areas` (0022, clave de texto), con `personas.funcion → areas.codigo`.
  El reporte las referencia; no se escribe una lista a mano (regla 3 de
  `CLAUDE.md`).
- **El Reglamento Interno y la política de hostigamiento ya regulan casi todo
  esto** (ver sección 4).

---

## 3 · Cómo lo hacen las mejores empresas (investigación)

1. **Separan lo grave de lo cotidiano.** Una sugerencia o una fricción del día
   a día no siguen el mismo camino que un acoso o un fraude.
2. **Usan «confidencial» más que «anónimo».** Culture Amp prefiere esa palabra
   a propósito: el nombre existe, pero solo lo ve quien gestiona. El anonimato
   total dificulta investigar y da pie a reportes maliciosos.
3. **Nadie investiga su propio caso** (ISO 37002: imparcialidad y conflicto de
   interés). Si el reporte es sobre una encargada, no le llega a ella.
4. **Quien reporta recibe respuesta.** Hay acuse de recibo, un estado que puede
   seguir y un cierre con lo que se hizo. La directiva europea pide acuse en 7
   días y respuesta en 3 meses; **aquí mandan los plazos del Reglamento**, que
   son más cortos (sección 4).
5. **No muestran estadísticas de grupos chicos.** El piso aceptado para
   reportar un grupo es de 5 personas; por debajo se adivina quién fue. Con 4
   sedes pequeñas, esto pesa mucho en CAYLA.
6. **Protegen contra represalias.** La persona reportada no sabe quién la
   reportó, y la represalia es falta.
7. **Usan formularios estructurados:** qué pasó, cuándo, dónde, quiénes
   estuvieron, testigos, evidencia y qué espera quien reporta.
8. **La IA detecta temas, riesgos y tendencias, pero no juzga personas.**
   AllVoices y EQS la usan como alerta temprana y paneles de tendencias; HR
   Acuity, en flujos guiados. La literatura insiste en la supervisión humana:
   la IA amplifica sesgos y no distingue una crítica justa de una injusta. Es
   el mismo principio de Dynamic: **avisa, nunca sanciona sola.**

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

Revisado en `docs/reglamento-interno-de-trabajo.md` y
`docs/politica-prevencion-hostigamiento-sexual.md`. **Reportes no crea un
procedimiento nuevo: es el canal digital y el registro de tres procedimientos
que ya existen.**

| Tipo de hecho | Artículo | Quién recibe | Plazos |
|---|---|---|---|
| Consultas, reclamos y sugerencias sobre la relación de trabajo | **43-B** | La encargada de su sede, su líder o DO | DO responde por escrito en **10 días hábiles** (o avisa en ese plazo cuándo responderá) |
| Acoso laboral o maltrato sin connotación sexual | **43-A** | DO. Si es contra la titular de DO, la **Gerencia General**. Si es contra la Gerencia General, por analogía el 48.2-bis | Acuse en **1 día hábil**; resolución escrita en **15 días hábiles** |
| Hostigamiento sexual o hechos de connotación sexual o sexista | **Título X** (arts. 47–51) | DO. Investiga la **Delegada** de cada sede (todas tienen menos de 20) o quien designe la Gerencia General mientras no haya Delegada. Si es contra la titular de DO, la Gerencia General. Si es contra la Gerencia General, una socia o quien representa a la Empresa, la Delegada o una persona externa | Informe en 15 días calendario; todo en **28 días calendario**; atención en salud en 1 día hábil; indicios de delito, aviso en 24 h |

Tres cosas del Reglamento que cambian el diseño:

- **El 43-B.4 ya exige lo que Felipe pidió:** *«DO lleva un registro de las
  consultas y reclamos recibidos, de su fecha y de su resultado, que emplea
  para identificar problemas recurrentes y corregirlos.»* Las estadísticas y el
  informe de la IA son la forma de cumplir ese artículo.
- **Represalias:** están prohibidas en los arts. 43-A.7, 43-B.5 y 51, y la
  represalia es falta grave. El sistema tiene que ayudar a detectarlas.
- **Canal del Título X:** la política dice que *ninguna cuenta de correo de
  uso general sirve como canal de queja* y que la vía escrita es de **acceso
  exclusivo de DO**. Si Dynamic recibe estas quejas, su acceso tiene que ser
  igual de exclusivo, lo que se garantiza con RLS y no solo con la pantalla.
  Además hay un formato oficial: `docs/formato-queja-hostigamiento-sexual.md`.

### ⚠️ Dos choques entre el cuestionario y el Reglamento

1. **«Reportes sobre alguien del panel van solo a Felipe» (pregunta 4).** El
   Reglamento dice otra cosa: contra la titular de DO decide la **Gerencia
   General**; contra la Gerencia General se aplica el 48.2-bis (Delegada o
   persona externa, y la persona denunciada queda apartada). Si Felipe es la
   Gerencia General, un reporte **contra Felipe** no puede llegarle a Felipe.
   Hay que definir el enrutamiento según el cargo, no por nombre, y siguiendo
   el Reglamento.
2. **«Las encargadas gestionan los reportes de su sede» (pregunta 3).** Encaja
   con el 43-B (reclamos y sugerencias) pero **no** con el 43-A ni con el
   Título X, que van a DO. Propuesta: la encargada ve solo los de tipo
   *empresa*, *clienta* e *idea de mejora* de su sede; los de *persona* van a
   DO.

---

## 5 · Las 10 decisiones de Felipe (cuestionario del 2026-09-26)

| # | Pregunta | Respuesta |
|---|---|---|
| 1 | Tipos de reporte | Compañera/o del equipo · La empresa · Una clienta · Idea de mejora |
| 2 | Identidad de quien reporta | **Confidencial**: el nombre queda guardado y solo lo ve quien gestiona |
| 3 | Quién recibe y gestiona | Admin, líder DO y **las encargadas de su sede**, salvo los reportes que la mencionan a ella *(ver choque 2)* |
| 4 | Reportes sobre una encargada, líder DO o admin | **Solo a Felipe** *(ver choque 1)* |
| 5 | Qué ve la persona reportada | **Nada hasta que DO decida conversar.** Nunca ve quién la reportó |
| 6 | Hostigamiento sexual y casos graves | **Camino propio con plazos** (Título X) |
| 7 | Estadística sobre personas | **Mapa de conflictos completo** (con los resguardos de la sección 8) |
| 8 | Qué recibe quien reporta | **Estados y respuesta final**; puede responder preguntas de DO |
| 9 | Papel de la IA | Informe mensual de temas · Ordena al llegar · Sugiere cómo manejar un caso · Ayuda a redactar · *y pidió investigar más funciones* (sección 7) |
| 10 | Datos del reporte | Fecha y sede del hecho · Fotos o archivos · Testigos · Qué espera que pase · *y pidió ver qué piden otras empresas* (sección 6) |

---

## 6 · Lado colaboradora: «Reportes» en `/mio`

### Nuevo reporte (4 pasos)

0. **Casilla fija arriba:** *«¿Es acoso sexual, violencia o un riesgo para
   alguien ahora?»* Si se marca, el reporte sale del flujo normal y va por el
   Título X o como urgencia; también muestra los canales externos del 48.9.
1. **¿Sobre qué?** Una persona del equipo, la empresa (proceso, herramienta,
   sede, turnos, condiciones), una clienta o una idea de mejora.
2. **Qué pasó.** Texto libre, con la IA ayudando a contar hechos (qué, cuándo,
   dónde) sin juicios.
3. **Detalles:**
   - fecha y sede del hecho;
   - personas involucradas (varias, del padrón);
   - testigos (del padrón);
   - fotos o archivos, en almacenamiento privado;
   - «¿es la primera vez?»;
   - «¿ya lo conversaste con alguien?»;
   - para una clienta: fecha, sede y, si se quiere, un número de ticket, sin
     pedir datos personales de la clienta.
4. **Qué esperas que pase:** que se sepa · conversar · que cambie algo · que
   se actúe.

Antes de enviar, una línea dice **quién lo va a leer**, que la persona
reportada no sabrá quién fue y que las represalias están prohibidas (43-A.7,
43-B.5).

### Mis reportes

- Cada reporte muestra su estado: **Recibido → En revisión → Cerrado**.
- Tiene un hilo con DO: preguntas y respuestas.
- Al cerrar, llega el **mensaje de cierre** con lo que se hizo. Es la
  respuesta escrita que exigen el 43-A.6 y el 43-B.2.

---

## 7 · Lado panel: «Reportes» en `/admin`

### Bandeja
- Los reportes nuevos primero, con el tipo, el tema y la gravedad que sugiere
  la IA; DO confirma o corrige.
- **Cuenta los plazos del Reglamento:** 1 día hábil de acuse y 15 hábiles de
  resolución (43-A); 10 hábiles (43-B); 28 calendario (Título X).
- Los días hábiles salen de la lógica de fechas que ya existe; no se escribe
  otra.

### Ficha del caso
- lo reportado y la evidencia;
- el hilo con quien reportó;
- **notas internas**, que ella no ve;
- una línea de tiempo de acciones: conversación, mediación, cambio de proceso,
  medida de protección, derivación;
- la sugerencia de la IA;
- el cierre escrito.

### Enrutamiento, en la base (RLS)
- Si el reporte menciona a alguien con rol en el panel, no lo ve esa persona:
  sigue la cadena del Reglamento (sección 4).
- La encargada nunca ve un reporte que la menciona.
- Los del Título X solo los ven quien recibe e investiga.
- Un reporte sigue el molde de «campo sensible» de `CLAUDE.md`: se escribe
  con funciones guardián `SECURITY DEFINER` (null-safe, `is not true`),
  nunca con un `UPDATE` directo, y todo cambio de estado deja rastro.

### Puente con disciplina
**Un reporte no es una falta.** Si DO decide actuar, abre el expediente del
Título XI que ya existe (arts. 55 y 57). Nada se sanciona desde Reportes.

### Estadísticas (cumplen el 43-B.4)
- tendencias por tema, sede y mes;
- tiempo de respuesta y cumplimiento de plazos;
- porcentaje de casos resueltos y en qué terminaron;
- mapa de conflictos (sección 8).

---

## 8 · El mapa de conflictos y sus resguardos

Felipe eligió la opción más potente, que también es la más delicada. Estos
resguardos la mantienen útil sin que se vuelva un arma:

- **Lo ven solo admin y líder DO.** Las encargadas no, porque en una sede de 4
  personas «quién reporta a quién» deja de ser confidencial al instante.
  *(Pendiente de confirmar.)*
- **Los casos que van por la cadena especial** (contra personas del panel o
  del Título X) **no aparecen en el mapa de nadie más.**
- **Cada relación muestra en qué terminaron sus casos:** confirmado, no
  confirmado o resuelto. Que te reporten muchas veces no prueba nada. Los
  falsos positivos son el peor error del sistema (ver `CLAUDE.md`).
- **Aviso fijo en la pantalla:** *«un reporte no es una falta»*.
- **Registro de consultas:** queda anotado quién abre el mapa, como ya se hace
  con las correcciones.
- **Alerta de represalia:** avisa si quien reportó empieza a recibir reportes,
  cambios de turno o medidas desfavorables justo después (43-A.7).

---

## 9 · La IA

| Función | Qué hace | Referencia |
|---|---|---|
| Ayuda a redactar | Convierte «me trata mal» en hechos concretos y sugiere qué dato falta | Formularios guiados |
| Ordena al llegar | Sugiere tema y gravedad; detecta si se parece a otro caso abierto | Detección temprana (EQS, AllVoices) |
| Sugiere cómo manejarlo | Propone pasos y un borrador del cierre escrito | Flujos guiados (HR Acuity) |
| Informe mensual | Qué se repite, qué crece, qué puede escalar, y propuestas de mejora | Paneles de tendencias; cumple el 43-B.4 |
| **Extra: alertas tempranas** | Avisa cuando una misma persona, sede o tema junta reportes de fuentes distintas en poco tiempo | Alerta temprana |
| **Extra: cruce con datos de Dynamic** | Relaciona los reportes con tardanzas, rotación, cambios de turno y riesgo psicosocial de la sede (43-A.8) | Esto no lo tiene nadie más: Dynamic ya tiene esos datos |
| **Extra: pulso de ideas** | Agrupa las ideas de mejora y muestra cuáles se piden más | — |
| **Extra: alerta de represalia** | Ver la sección 8 | 43-A.7 |

**Reglas para la IA:**
- Nunca decide ni califica a una persona. Todo lo que produce queda marcado
  como sugerencia, y una persona lo confirma.
- **No participa en casos del Título X.**
- Antes de mandar texto a la IA se reemplazan los nombres por códigos: son
  datos personales (Ley 29733, Título IX del Reglamento). Hay que revisar
  también si la cláusula de datos del Reglamento cubre este tratamiento.
- Hace falta infraestructura nueva: una ruta de servidor en `apps/web/app/api/`
  y una clave de API como variable de entorno en Vercel. Hoy no existe
  ninguna de las dos.

---

## 10 · Fases propuestas

1. **Fase 1, sin IA:**
   - tablas, funciones guardián y RLS con la cadena de enrutamiento del
     Reglamento;
   - el formulario y «Mis reportes» en `/mio`;
   - la bandeja y la ficha en `/admin`, con conteo de plazos;
   - el camino del Título X;
   - estadísticas básicas por tema, sede y mes.
2. **Fase 2, IA:** ayuda a redactar, orden al llegar, informe mensual y
   sugerencias por caso.
3. **Fase 3:** mapa de conflictos con sus resguardos, alertas tempranas y de
   represalia, y cruce con asistencia.

Recordatorios del repo para cuando se construya:
- `./scripts/siguiente-numero.sh` antes de crear cada migración;
- `./scripts/donde-vive.sh` antes de crear cada función;
- la migración se pega **antes** de fusionar el PR, porque fusionar a `main`
  es publicar;
- solo colores `--color-*`;
- toda fecha que bloquee el envío arranca con un valor (el del hecho = hoy).

---

## 11 · Lo que falta decidir

1. **Enrutamiento contra personas del panel** (choque 1): ¿quién es hoy la
   Gerencia General y quién la titular de DO? ¿Se adopta la cadena del
   Reglamento en lugar de «solo a Felipe»?
2. **Qué ve la encargada** (choque 2): ¿solo empresa, clienta e ideas de su
   sede, y los de persona van a DO?
3. **Mapa de conflictos:** ¿se confirma que solo lo ven admin y líder DO?
4. **Título X en Dynamic:** ¿las quejas de hostigamiento se reciben también
   por Dynamic, con acceso exclusivo, o la pantalla solo orienta al canal
   formal (correo exclusivo o sobre cerrado)? ¿Ya hay Delegada elegida en
   cada sede? La política decía que la elección vencía el 9 de septiembre de
   2026.
5. **Retención:** ¿cuánto tiempo se guardan los reportes cerrados y su
   evidencia? Se sugieren 2 años, y hay que alinearlo con el Título IX.
6. **Proveedor de IA y consentimiento:** ¿se usa Claude API? ¿Hace falta
   informar a las integrantes en la cláusula de datos?
