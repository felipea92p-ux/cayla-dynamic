# Fase 2 — Detección de faltas · Análisis de diseño

**Preparado la noche del 2026-07-20 para decidir y construir el 2026-07-21.**
Esto es **análisis, no código**. Nada aplicado ni desplegado. Las decisiones de la
sección 7 se resuelven mañana con botones (AskUserQuestion) y recién ahí se construye.

---

## 1. Qué pediste

> "Cuando una persona tenía turno y no marca en todo el día, posiblemente ha
> faltado — que salga en Incidencias y que se pueda sancionar, igual que las
> tardanzas."
> Más el desplegable de justificación: **permiso concedido, cumpleaños, estudios,
> descanso médico, otro** (con observación escrita).

Decisiones ya tomadas en sesiones anteriores (no se vuelven a preguntar):
- **Ventana móvil** (últimos 30 / 180 días desde hoy), no calendario.
- **Al llegar al umbral legal: avisar y armar el expediente.** Nunca "despide".
- **Régimen Pequeña Empresa/MYPE.**

---

## 2. Lo que YA existe y se reusa (no se inventa)

El terreno está listo — esto es lo mejor de haber hecho todo lo anterior primero:

| Pieza | Dónde | Para qué en Fase 2 |
|---|---|---|
| `trabajaEseDia(persona, fecha)` | `admin/incidencias/page.tsx` | **La pieza central.** Resuelve turno→horario→descanso: ¿le tocaba trabajar ese día? |
| `calcularEsperado()` | `admin/correcciones/page.tsx` | Hora esperada + origen (turno/horario), ya con la precedencia correcta |
| `en_planilla` (mig. 0046) | `personas` | Accionistas → NUNCA falta |
| `sueldo_fijo` (mig. 0047) | `personas` | Catherine → NUNCA se le mide asistencia → NUNCA falta |
| Tabla `vacaciones` (mig. 0042) | — | Día de vacaciones = ausencia justificada |
| Tabla `feriados` | — | Día no laborable por defecto |
| `jornadas.entrada_ts` | — | Si existe con entrada = presente (aunque llegue tarde) |
| "días medidos" (bono 0034) | `0034` | Principio: solo cuenta un día con horario real; sin horario se ignora |

**Patrón de todo el sistema (clave):** Incidencias **avisa, no sanciona sola.** Las
tardanzas ya se muestran como "patrón 3+ en 30 días" con la nota *"Dynamic solo
avisa, la decisión (conversar, amonestar) es tuya."* Las faltas deben comportarse
igual: **detectar + contar + documentar**, nunca castigar en automático.

**No existe** tabla de justificaciones ni de sanciones/amonestaciones → hay que crearla.

---

## 3. Qué es una FALTA (definición precisa)

Para una persona **P** y una fecha **D**, es **falta injustificada** si se cumplen TODAS:

1. `D >= P.fecha_ingreso` y `D <= ayer` (hoy aún está en curso; no es falta hasta cerrar el día).
2. `P.en_planilla = true` **y** `P.sueldo_fijo = false` (es medible).
3. `trabajaEseDia(P, D) = true` (turno de trabajo, o horario base con entrada ese día de la semana; **no** descanso).
4. **No hay presencia**: no existe jornada de (P, D) con `entrada_ts`. *(Si marcó y se fue temprano, eso es "salida anticipada", otra incidencia — no falta.)*
5. `D` no está cubierto por un periodo de **vacaciones** registrado.
6. `D` no tiene una **justificación** registrada (permiso/cumpleaños/estudios/médico/otro).
7. *(A decidir — sección 7)* `D` no es **feriado**.

Es **falta justificada** (se registra, NO cuenta para sanción) si se cumplen 1–4 pero
hay justificación (6) o vacaciones (5).

Todo lo demás **no es falta** y ni se muestra (descanso, sin horario, no medible,
fuera de fechas).

---

## 4. Marco legal verificado (art. 25-h D.S. 003-97-TR)

Texto literal: *"El abandono de trabajo por **más de tres días consecutivos**, las
ausencias injustificadas por **más de cinco días** en un período de treinta días
calendario o **más de quince días** en un período de ciento ochenta días
calendario; **hayan sido o no sancionadas** disciplinariamente en cada caso…"*

| Supuesto | Se configura desde | Ventana |
|---|---|---|
| Abandono (consecutivas) | **4** días seguidos | — |
| Injustificadas | **6** días | 30 días |
| Injustificadas | **16** días | 180 días |

- **"Hayan sido o no sancionadas":** amonestar una falta NO la borra del conteo.
- **Procedimiento:** llegar al umbral **no es despido automático** — habilita el
  procedimiento: carta de preaviso con **≥6 días** para descargos.
- **El sistema documenta y avisa; NUNCA dice "despide".** (Y yo no soy abogado:
  antes de un despido real se valida con asesor laboral.)

---

## 5. Modelo de datos propuesto

**Tabla nueva `justificaciones_asistencia`** (una fila = un día justificado):
```
id            uuid pk
persona_id    uuid → personas
fecha         date
motivo        text check in ('permiso_concedido','cumpleanos','estudios','descanso_medico','otro')
observacion   text   -- obligatoria si motivo = 'otro'
creado_por    uuid → personas
creado_at     timestamptz
unique (persona_id, fecha)   -- un día se justifica una sola vez
```
- RLS igual a `correcciones_auditoria` (admin/líder todo, encargada su sede, cada quien lo suyo).
- Escritura solo por `fn_set_justificacion` / `fn_quitar_justificacion` (security definer).
- **No afecta pago** (ningún permiso es pagado; el descanso médico solo cuenta para
  el factor de vacaciones, que ya está resuelto aparte). La justificación solo saca
  el día del conteo disciplinario.

**Las faltas NO se materializan** (no se crea una jornada 'falta'). Se **computan**,
igual que el "patrón de tardanzas" hoy, con una función:
```
fn_faltas(p_desde date, p_hasta date) → filas {persona_id, fecha, justificada, motivo}
```
Enumera, por persona, cada día del rango donde aplica la definición de la sección 3.
En SQL: `generate_series` de fechas × personas medibles, con la cascada turno→horario,
excluyendo presencia/vacaciones/justificación/(feriado). Es la parte pesada y la que
hay que escribir con cuidado y probar contra casos reales.

**Contadores** (para el semáforo legal), función `fn_faltas_resumen()`:
por persona → consecutivas actuales, injustificadas en 30 días, en 180 días, y el
nivel (verde / ámbar / rojo-umbral) según los cortes 4 / 6 / 16.

---

## 6. Flujo de usuario propuesto

1. **Incidencias** gana una fila nueva por cada falta injustificada reciente
   (reusa la tabla que ya existe), en rojo, con acción **"Justificar"** y **"Ver"**.
2. **Justificar** abre un mini-panel con el desplegable (permiso/cumpleaños/estudios/
   médico/otro) + observación → guarda en `justificaciones_asistencia`. El día sale
   del conteo y pasa a listarse como justificado.
3. **Semáforo por persona**: cuando alguien cruza un umbral legal (4 consec / 6 en
   30d / 16 en 180d), Incidencias lo marca fuerte: "posible causal — revisar".
4. **Expediente** (botón): genera un documento con qué días faltó, cuáles quedaron
   injustificados, desde cuándo, y el recordatorio del procedimiento (carta de
   preaviso, 6 días de descargo). Imprimible/descargable. **Nunca** dice "despide".
5. *(Opcional/decisión)* Registrar la **amonestación** aplicada (para el requisito
   legal de "sanciones progresivas documentadas").

---

## 7. Decisiones para mañana (van a AskUserQuestion)

1. **Feriados:** ¿un feriado en que no vino cuenta como falta?
   *Recomiendo NO* (feriado = descanso legal por defecto), salvo que tenga un turno
   explícito ese día. → decide si excluir feriados siempre.
2. **¿Desde cuándo detectar?** El terminal arrancó en 2026; 2025 son datos importados.
   La ventana de 180 días ya cae dentro de 2026, así que naturalmente arranca ahí.
   *Recomiendo* limitar la detección a fechas con marcaje diario real (2026+) para no
   inventar faltas del histórico. → confirmar.
3. **Sede/terminal caído:** si un día el terminal no funcionó, TODOS parecerían faltar.
   ¿Queremos una forma de marcar "día no computable por sede"? *Recomiendo* dejarlo
   para después (raro), pero tenerlo presente.
4. **¿Registrar la amonestación** aplicada (tabla de sanciones), o solo el expediente?
   *Recomiendo* empezar solo con detección + justificación + expediente; la sanción
   formal como fase siguiente.
5. **¿Dónde se justifica?** ¿En Incidencias (junto a la falta) o también en
   Correcciones? *Recomiendo* en Incidencias, que es donde aparece.
6. **Observación obligatoria** solo para "otro", o para todos los motivos.
   *Recomiendo* obligatoria solo en "otro" (los demás se explican solos).

---

## 8. Riesgos y casos borde (ya mapeados)

- **Falsos positivos** = el peor error (acusar de falta a quien no debía). Mitigado por
  las 7 condiciones + exclusiones `en_planilla`/`sueldo_fijo`/vacaciones/feriados.
- **Recién contratado**: `D >= fecha_ingreso` lo cubre.
- **Persona sin horario asignado**: `trabajaEseDia` da false → no es medible → no falta.
- **Catherine (sueldo fijo)** y **accionistas**: excluidos por diseño. *(Este fue el
  caso que casi explota: sin las marcas, habría salido con ~200 faltas.)*
- **Marcó pero jornada rara** (auto-cerrada): hay entrada → es presencia, no falta.
- **Turno = descanso** ese día: no le tocaba → no falta.
- **Cambio de horario a mitad de semana**: `trabajaEseDia` usa el tramo vigente por fecha.

## 9. Plan de construcción (cada fase desplegable sola)

1. **Tabla + justificar**: `justificaciones_asistencia` + `fn_set/quitar_justificacion`
   + panel "Justificar" en Incidencias. (Bajo riesgo, no toca plata.)
2. **Detección**: `fn_faltas` + filas de falta en Incidencias. (El corazón; probar
   contra datos reales antes de confiar — mismo "mirar antes de tocar".)
3. **Contadores + expediente**: `fn_faltas_resumen` + semáforo + documento imprimible.

---

**Regla de oro para mañana:** esto decide si alguien figura camino al despido. Se
construye por fases, se prueba cada una contra la realidad, y el sistema **siempre
avisa — nunca sanciona solo.**
