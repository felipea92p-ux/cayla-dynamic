# Auditoría de la pantalla Planilla — 2026-09-15

> Informe fechado (ver `criterio-auditoria-pantallas.md`). Solo lectura: no se
> tocó código, SQL ni datos. Todo sale de leer la versión VIGENTE de cada
> función (`donde-vive.sh`) y `apps/web/app/(admin)/admin/planilla/page.tsx`
> (3 272 líneas). Nada se midió contra producción: donde un hallazgo depende de
> datos reales, se dice.

---

## 1 · Qué hay de verdad detrás de la pantalla

### Piezas

| Pieza | Dónde |
|---|---|
| Pantalla (un solo archivo, sin componentes propios salvo `TablaPlanilla`) | `page.tsx` |
| Boleta | `planilla/boleta/page.tsx` |
| Cálculo | `fn_planilla_calcular` (guard, 0397) → `fn_planilla_calcular_nucleo` (vigente 0418) |
| Lo que lee la pantalla | `fn_proyeccion_periodo` (0323:918-1031) |
| Estado por grupo | `fn_periodo_grupos_estado` (0323:1228) |
| Crear / pagar / reabrir / repagar / eliminar | `fn_crear_periodo` (0183) · `fn_periodo_pagado` (0323:599) → `fn_planilla_congelar` (0326) · `fn_revertir_pago` (0323:685) · `fn_repagar_periodo` (0323:789) · `fn_eliminar_periodo` (0327:3364) |
| Comparación | `fn_planilla_variacion` (0319) |
| Desvíos de un pagado | `fn_planilla_foto_diferencias` (0096) |
| Liquidaciones que se solapan | `fn_liquidaciones_del_periodo` (0251) |
| Grati/CTS | `fn_grati_cts_periodo` (0346, no escribe) · `fn_grati_cts_agregar_pendientes` (0355, escribe) |
| Simulación | `fn_simular_planilla` (0181, no escribe, sin movimientos) |
| Tablas | `periodos_planilla`, `periodo_grupo_pago`, `planilla_pagada_detalle` (foto inmutable), `reversas_pago`, `movimientos_planilla`, `desembolsos_beneficios` |

### Estados reales

- `periodos_planilla.estado ∈ {abierto, pagado}` (CHECK). **No existe «cerrado».**
- Desde la 0323 el estado real es **por grupo** (`periodo_grupo_pago`): `planilla`,
  `prueba`, `rxh`, `practicante`, `no_trabajador`. Cada uno se paga, se reabre y
  se repaga por separado.
- El estado del periodo es un **agregado derivado**: «pagado» solo cuando todos
  los grupos con gente lo están. Un periodo con Planilla pagada y Practicantes
  sin pagar dice «abierto».
- «Vencido sin pagar» no es un estado: lo calcula la pantalla (`abierto` y
  `fecha_fin < hoy`, page.tsx:473).

### Ciclo de vida

- **Crear**: siempre encadenado (último cierre + 1), 20–46 días, sin solape, uno
  por mes de cierre. El 29→28 es costumbre, no regla. **No exige que el anterior
  esté pagado** (decisión con Felipe, 0323:97-99): puede haber varios abiertos.
- **Marcar pagado** (por grupo): recalcula y congela en `planilla_pagada_detalle`
  a **todas** las personas cuyo `tipo_vinculo` actual es ese grupo, en una sola
  sentencia (todo o nada). No recibe filtros del cliente. Dos frenos en la base:
  liquidación ya cobrada sin descuento (0243/0244) y días con salida puesta por
  el sistema sin confirmar (0284/0326). Después, ~33 funciones rechazan escrituras
  en fechas de un grupo pagado. Rastro: `pagado_por/at` + `congelada_por/at`; no
  escribe en `correcciones_auditoria`.
- **Reabrir**: motivo ≥ 4 caracteres, registro en `reversas_pago`, la foto queda
  como histórico.
- **Volver a pagar**: congela una versión nueva sin pasar por abierto, con motivo.
- **Eliminar**: solo el último periodo y sin ningún grupo pagado. `delete` directo:
  **se lleva en cascada los movimientos** (incluidos los descuentos «Ya le pagué
  aparte») **y `reversas_pago`. No deja rastro.**
- **Permisos**: pantalla `puedeVerPlanilla` (solo DO); base
  `fn_es_admin_o_lider() is not true` en todas. Coherentes.

### Quién entra en el cálculo (0418:413-426)

Activo, **o** con jornadas en el rango, **o** con movimientos del periodo, **o**
con `fecha_cese` dentro del rango (0416). Todos los vínculos. Quien cesó antes
del periodo y no tiene jornadas ni movimientos, no entra.

### De dónde sale cada cifra (resumen; el detalle está en `planilla-anexo-tecnico.md`)

- **Horas**: solo `jornadas.horas_trabajadas`; Correcciones llega porque recalcula
  la jornada. Los días `auto_cerrada_pendiente` se pagan y se cuentan en
  `dias_pendientes`.
- **Base full-time**: `6.5 × días del periodo` → 28 d = 182 h · 30 d = 195 h · 31 d =
  201,5 h. En un periodo más largo la hora vale menos (se compensa en el año, ver
  prueba 248).
- **Sueldo**: tramo de `asignaciones_salario` vigente cada día (por horas). El sueldo
  fijo usa solo el último tramo.
- **Ausencias pagadas** (vacaciones, descanso médico aprobado por DO, licencias,
  maternidad): dentro de `pago_base`.
- **Feriados**: `fn_feriado_devengado_nucleo`; solo `en_planilla`.
- **Total** = pago_base + feriados + asignación + movilidad + educación + bonos +
  recargo sobretiempo + recargo descanso semanal − pensión − descuentos −
  retención 4ta. EsSalud y provisiones no entran.
- **Practicantes**: horas, movilidad, educación; sin feriados, asignación, AFP,
  sobretiempo ni provisiones.
- **Grati/CTS pendientes**: solo personas activas (los cesados van por liquidación).

---

## 2 · Personas cesadas (fase 2)

| Pregunta | Respuesta medida en el código |
|---|---|
| ¿Por qué están ocultas? | El filtro «Mostrar» arranca en «Solo el equipo actual» y **se guarda en el navegador** (page.tsx:1141, `useFiltroGuardado`). `pasaEstado` compara el `estado` de HOY de la persona (page.tsx:517). |
| ¿Siguen en el total del periodo? | **Sí** en el cálculo del servidor y en la foto. **No** en nada de lo que la pantalla suma: pie de tabla, provisiones y CSV salen de las filas filtradas. |
| ¿«Marcar como pagado» las incluye? | **Sí.** El congelado no recibe filtros: registra como pagadas a personas que la pantalla no mostraba. |
| ¿Pueden quedar sin pagar? | **Sí, con registro de pagado.** Se transfiere lo que se ve y se marca pagado el grupo completo. La foto dice que se les pagó. |
| ¿Cómo se ven al cambiar el filtro? | Aparecen con «ya no está». «Verlas» cambia el filtro pero no la pestaña: si son practicantes y estás en Planilla, sigues sin verlas. |
| El aviso | Solo existe con el filtro en «activos» (page.tsx:2204), respeta la sede, ignora la búsqueda y suma los 5 grupos aunque la tabla muestre uno. |
| «Ya no está» | Es el estado de hoy, no «cesó durante el periodo»: en julio, alguien que cesó en septiembre sale como «ya no está». |
| CTS, vacaciones | Sus provisiones también quedan ocultas. La grati/CTS pendiente las excluye a propósito (va por liquidación). El doble cobro con la liquidación lo frena la 0243/0244. |

**Clasificación: CRÍTICO.** El problema no es solo visual: puede producir una
omisión real con un registro que dice lo contrario.

---

## 3 · Filtros contra cálculos (fase 3)

Los filtros (sede, mostrar, búsqueda y la pestaña) son **solo del navegador**.
Ninguna llamada al servidor los recibe.

| Lo que cambian (sin decirlo) | Lo que NO cambian |
|---|---|
| conteo de las pestañas y **qué pestañas existen** (page.tsx:2166) | el cálculo |
| **si el botón «Marcar como PAGADO» está habilitado** (page.tsx:2890) | quiénes se congelan al pagar |
| el «Total» del pie (page.tsx:1047; solo nombra la sede) | el total de «Qué cambió» (equipo completo) |
| el total de provisiones | |
| el contenido del CSV | |

**No existe un TOTAL OFICIAL DEL PERIODO en la pantalla.** El único total del
equipo completo aparece de pasada dentro de «Qué cambió».

---

## 4 · Periodos (fase 4)

- Varios abiertos: **permitido por diseño** (0323:97-99).
- Dependencias: ninguna de cálculo. Solo `periodo_origen_id` de un retroactivo
  exige que el origen esté pagado. Grati/CTS y provisiones se calculan por fechas,
  no por estado de pago.
- Pagar el actual antes que el anterior: permitido; no rompe acumulados.
- Riesgo real: **un grupo olvidado** (por ejemplo `prueba` o `practicante`) deja el
  periodo «abierto» para siempre, y la pantalla no dice qué grupo falta.
- Hoy: julio (28 jun → 28 jul) **y agosto** (29 jul → 28 ago) figuran abiertos. La
  cabecera y el desplegable solo avisan del más antiguo.

---

## 5 · Comparación (fase 5)

- Una fila por persona (full outer join): total neto actual contra anterior. Los
  periodos pagados se comparan por su foto; los abiertos, en vivo.
- **No normaliza nada.** Solo marca `periodos_de_distinto_largo`.
- Defecto de lectura: **compara un periodo en curso con uno terminado.** El
  15/09, con 15 de 30 días, dice «34 personas con algo que mirar» en rojo y −S/ 9 209.
  Casi todo es que el mes no terminó; el aviso solo menciona 30 contra 31 días.
- Además el anterior (agosto) también está abierto: se compara contra una cifra
  que todavía se mueve.

---

## 6 · Hallazgos

### CRÍTICO

**C1 · Cambiar el tipo de vínculo entre el pago de dos grupos: doble pago u omisión.**
`personas.tipo_vinculo` no tiene historial. `fn_set_tipo_vinculo` (0324) no mira
periodos pagados. `fn_planilla_congelar` (0326) filtra por el vínculo ACTUAL y no
comprueba si la persona ya está en la foto de otro grupo. `fn_proyeccion_periodo`
(0323:990-1001) supone «una persona pertenece a un solo grupo a la vez».
Escenario concreto: termina el periodo de prueba de alguien, se paga «Prueba», se
le cambia a «Planilla» antes de pagar ese grupo, se paga «Planilla» → **el mismo
periodo congelado dos veces**. Al revés (de planilla pagada a un grupo abierto)
sus horas vuelven a ser editables. Verificado en el código; **no medido con datos.**
Es de base de datos: fuera del alcance de un rediseño.

**C2 · Los filtros deciden qué se ve, pero no qué se registra como pagado.**
(Ver secciones 2 y 3.) Pagar con un filtro puesto registra como pagadas a
personas ocultas. Un grupo cuyas personas quedan todas ocultas **pierde su
pestaña**: no se puede pagar y la pantalla dice «No hay nadie de este grupo».
El filtro de sede guardado hace que la pantalla abra así (captura del 15/09:
«Planilla (0)» con sede TRU).

### ALTO

- **A1 · El CSV no es la planilla.** Sigue los filtros, mezcla los 5 grupos sin
  una columna de grupo y le faltan conceptos que sí están en el total (movilidad,
  educación, pensión, sobretiempo, descanso semanal): la columna `total` no
  cuadra con la suma de sus columnas. El nombre del archivo no dice que está
  filtrado.
- **A2 · Confirmar el pago no muestra qué se paga.** El diálogo no dice periodo,
  personas ni total. Solo el freno de días pendientes se revisa antes; el de
  liquidaciones llega como error. Los demás chequeos de cierre viven en consultas
  que se pegan a mano (`antes_de_cerrar_el_mes.sql`, `va_a_poder_cerrarse.sql`,
  `ausencias_sin_firma_antes_de_cerrar.sql`): feriados faltantes, jornadas que
  pagan cero, ausencias sin firma de DO, activos sin salario u horario, retenciones.
- **A3 · Periodos y grupos pendientes, a medias.** Solo se avisa del periodo
  vencido más antiguo; el estado agregado no dice qué grupo falta; el enlace
  «terminó y sigue sin pagar» es texto pequeño en medio de la cabecera.
- **A4 · «Qué cambió» alarma en rojo todos los meses a mitad de periodo.** (Ver 5.)
- **A5 · Eliminar borra dinero registrado sin rastro.** Movimientos (incluidos
  descuentos «Ya le pagué aparte») y reversas en cascada; confirmación genérica;
  botón rojo permanente en la cabecera. Un periodo que alguna vez se pagó y
  reabrió probablemente no se puede borrar (foto inmutable con clave foránea sin
  cascada): error en vez de acción.
- **A6 · La básica legal se escribe al salir del campo.** Dato contractual de la
  persona, editable dentro de la tabla de revisión (incluso con el grupo pagado),
  sin confirmación. Cambia el desglose de boletas pasadas y la pensión de
  cualquier recálculo. Basta pasar con Tab por la tabla con un valor tocado.

### MEDIO

- **M1** · Provisiones suma todos los grupos filtrados; la tabla principal, una
  pestaña: dos poblaciones distintas en la misma pantalla.
- **M2** · «Ya le pagué aparte» aparece en un grupo pagado; la base lo rechaza
  después de llenar el diálogo.
- **M3** · La simulación hereda la pestaña y los filtros de la tabla oficial, y usa
  la misma tabla: se confunde fácil con la oficial (el cartel ámbar ayuda).
- **M4** · «Volver a pagar» actúa solo sobre la pestaña activa, mientras la lista de
  desvíos mezcla grupos; en un periodo pagado a medias lista como desvío a gente
  de grupos que nunca se pagaron.
- **M5** · `fn_revertir_pago` no recalcula jornadas si el periodo estaba pagado solo
  en parte (0323:760): al repagar se podrían usar jornadas viejas. Plausible, no
  medido. SQL.
- **M6** · «Agregar todo» de grati/CTS no tiene restricción única: dos clics
  simultáneos podrían duplicar. SQL.
- **M7** · El pie dice «Proyección referencial», pero esa es la cifra que se congela.
- **M8** · `docs/hallazgos-abiertos.md:68-72` marca como abiertos tres defectos que
  corrigieron la 0416, la 0417 y la 0418.

### BAJO

- **B1** · Código muerto: objetivos y rendimiento (estado, manejadores y props) de
  columnas que salieron con la 0171.
- **B2** · La cabecera mezcla en una línea el periodo, el estado, otro periodo, crear
  y eliminar. «Gestionar feriados» duplica la pantalla Feriados.
- **B3** · Móvil: 11 columnas con campos editables, sin vista por persona.
- **B4** · El rojo se usa para alarmas, descuentos y avisos por igual.
- **B5** · «Base full-time: 195 h» sin explicar qué es ni por qué cambia.

---

## 7 · Decisiones (Felipe, 2026-09-15) y lo implementado

| Tema | Decisión | Dónde quedó |
|---|---|---|
| Cierre | Bloqueo solo de los dos frenos de la base; el resto se marca «revisé estos avisos» | `components/planilla/revision-cierre.tsx` |
| Cesados | Siempre en la tabla, insignia relativa al periodo; el filtro «Mostrar» desaparece | `revision.ts · ceseRespectoDelPeriodo`, `tabla-planilla.tsx` |
| Filtros | Solo la vista; «Subtotal visible · X de Y»; la sede ya no se guarda | `page.tsx` |
| Periodo anterior impago | Aviso de TODOS los terminados sin pagar (con qué grupo falta) + casilla al pagar uno más nuevo | `page.tsx`, `revision-cierre.tsx` |
| Estados | Por grupo, sin estado nuevo; «pagado en parte» es una lectura | `revision.ts · lecturaDelEstado` |
| Comparación | Solo con el periodo terminado; en curso, solo quién entró y salió | `que-cambio.tsx` |
| Grupos | Se mantienen las pestañas, con conteos del periodo completo | `page.tsx` |
| Eliminar | Menú «⋯», detalle de lo que se pierde, confirmación escrita + migración de rastro | `page.tsx`, **0452** (sin pegar) |
| Pagar | Una operación: «Revisar cierre → Confirmar pago y congelar» | `revision-cierre.tsx` |
| Requiere atención | Frenos de la base, datos por persona, periodos y grupos (no los chequeos SQL) | `requiere-atencion.tsx` |
| CSV | Para el contador: completo, con grupo y todas las partidas (probado que `total` cuadra) | `csv-planilla.ts` |
| Reapertura | Consecuencias + historial visible (`reversas_pago`) | `page.tsx` |

Resueltos por el rediseño: **C2**, A1, A2 (CSV), A3, A4, A5 (pantalla), A6 (confirmación y
menú; el rastro llega con la 0452), A7, M1, M2, M3, M4, M7, B1, B2, B3, B4, B5.

Sigue abierto: **C1** (cambio de vínculo entre pagos de grupo — es de base de datos y no se
decidió), M5 y M6 (SQL), M8 (documento desactualizado), y un hallazgo nuevo de la 0452: un
periodo que alguna vez se pagó y se reabrió no se puede borrar (clave foránea), aunque el
mensaje de la base diga «reábrelo primero».

### Fuera del alcance de la pantalla (fórmulas — no se tocan sin decisión)

La asignación familiar no se prorratea con ingreso o cese a mitad de periodo. El
sueldo fijo con cambio a mitad de periodo usa solo el último tramo. Las horas
negativas de una jornada mal cerrada restan pago (sobretiempo sí las filtra). A
validar con el contador; no son de este rediseño.
