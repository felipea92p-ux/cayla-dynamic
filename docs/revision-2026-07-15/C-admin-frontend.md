# C — Revisión a fondo: páginas admin (2026-07-15)

Revisión de las 19 páginas bajo `apps/web/app/(admin)/admin/*` (Planilla + boleta,
Cuentas, Provisiones, Objetivos, Horas, Horarios, Turnos, Incidencias,
Correcciones, Áreas, Equipo, Dashboard, Login, Olvide-clave, Nueva-clave,
Exportar, `nav.tsx`, `page.tsx` raíz, `layout.tsx`), cruzada contra las RPC y
policies de RLS que las respaldan (`supabase/migrations/*`). Solo lectura —
ningún archivo de código se modificó. No se corrió nada contra la base real.

Prioridad: 🔴 afecta al equipo hoy · 🟡 valioso pronto · 🟢 cuando haya tiempo.

**Contexto importante que confirma el patrón:** el mismo día de esta revisión,
`supabase/migrations/0034_bono_puntualidad.sql` documenta que su propio v1 tenía
exactamente el bug de abajo (`coalesce(minutos_tarde, 0)` trataba "sin medir"
como "0 tardanza" y premiaba a quien el sistema nunca pudo medir) y tuvo que
corregirse a v3 el mismo día. Esa corrección se hizo en el cálculo del bono
(servidor), pero **las dos pantallas que muestran "tardanzas" al admin nunca se
corrigieron** — son el mismo bug, todavía vivo, en la capa de UI.

---

## 🔴 Falsos "cero tardanzas" — mismo bug ya encontrado y corregido en el servidor, vivo en 3 lugares del front

- [ ] **`apps/web/app/(admin)/admin/perfil/page.tsx:112`** — `tardanzas =
  jornadas.filter((j) => (j.minutos_tarde ?? 0) > 0).length`. Confirmado en
  `supabase/migrations/0017_salida_temprana_extra.sql:108-113` (y versiones
  posteriores de `fn_recalcular_jornada`): `minutos_tarde` queda `NULL` —no
  `0`— cuando no hay horario/turno vigente para ese día, o cuando la diferencia
  supera 180 min (anomalía, "turno distinto, no medible"). **Escenario**: una
  persona sin horario cargado (o con un hueco de vigencia) aparece con "Días
  con tardanza: 0" en su Perfil — indistinguible de alguien con asistencia
  perfecta verificada. Un admin decidiendo un bono/reconocimiento por
  puntualidad a partir de esta pantalla premia a ciegas. **Fix**: contar por
  separado `dias_medidos` (días con `minutos_tarde is not null`) y
  `dias_puntuales` (medidos y `= 0`); mostrar "0 de N días medidos" en vez de
  un badge de "0" a secas, igual que ya resolvió `fn_calcular_bono_puntualidad` v3.
- [ ] **`apps/web/app/(admin)/admin/horas/page.tsx:70`** — mismo patrón:
  `if ((j.minutos_tarde ?? 0) > 0) { r.tardanzas++; ... }` en la tabla resumen
  por sede. Mismo escenario y mismo fix que el punto anterior.
- [ ] **`apps/web/app/(admin)/admin/perfil/page.tsx:113`** (nuevo, no reportado
  antes) — `salidasTempranas = jornadas.filter((j) => (j.minutos_salida_temprana
  ?? 0) > 0).length`. Mismo problema exacto pero con salida anticipada:
  `minutos_salida_temprana` es `NULL` (no `0`) cuando no hay horario, cuando la
  salida fue por auto-cierre, o cuando supera 180 min — ver
  `0017_salida_temprana_extra.sql:123-131`. Ojo: ahí mismo, `0` SÍ es un valor
  medido real (línea 129: dentro de 15 min de tolerancia se guarda `0`, no
  `null`), así que `?? 0` mezcla "confirmado a tiempo" con "no se pudo medir".
  **Fix**: mismo patrón que arriba — separar medido/no-medido antes de contar.

## 🟡 Relacionado: mismo NULL-blindness, menor severidad

- [ ] **`apps/web/app/(admin)/admin/perfil/page.tsx:111`** —
  `diasTrabajados = jornadas.filter((j) => (j.horas_trabajadas ?? 0) > 0).length`.
  `horas_trabajadas` es `NULL` mientras el día sigue abierto o no tiene salida
  final marcada (jornada incompleta/pendiente de revisión) — no significa "no
  trabajó". **Escenario**: alguien que marcó entrada pero aún no salida (o cuyo
  día quedó auto-cerrado pendiente de revisar) desaparece del conteo de "Días
  trabajados" de su propio Perfil, subestimando su asistencia real. **Fix**:
  contar por `entrada_ts is not null` en vez de `horas_trabajadas ?? 0 > 0`, o
  mostrar aparte "N días pendientes de cierre" (el dato ya existe: `estado`,
  `incidencia()`).
- [ ] **`apps/web/app/(admin)/admin/perfil/page.tsx:110`** (`totalHoras`) y
  **`apps/web/app/(admin)/admin/horas/page.tsx:71`** / **`perfil/page.tsx:114`**
  (`horas_extra_detectadas ?? 0`) — revisados y son de menor riesgo: sumar
  `null` como `0` en un total agregado es razonable (no "confirma" nada falso,
  solo es conservador), y `horas_extra_detectadas` nunca queda `NULL` en la
  base (`fn_recalcular_jornada` siempre inserta un número, empieza en `0` y
  solo sube) — el `?? 0` ahí es redundante pero inofensivo. No requieren
  acción inmediata, se listan por transparencia (se pidió reportar cada
  instancia del patrón).

---

## 🔴 Fallas de carga silenciosas — `Promise.all` sin revisar `error`

En estas pantallas, si **cualquiera** de las consultas en paralelo falla (red,
RLS, timeout), el código destructura `{ data }` sin mirar `{ error }`; `data`
llega `null`, el `?? []` lo convierte en lista vacía, y la página se pinta
como si el periodo/día estuviera limpio — sin banner de error, sin botón de
reintentar. Contrasta con `provisiones/page.tsx`, `objetivos/page.tsx`,
`areas/page.tsx` y `planilla/page.tsx`, que sí revisan `error` y muestran un
aviso rojo con "Reintentar" — el patrón correcto ya existe en el propio
repo, solo falta aplicarlo parejo.

- [ ] **`apps/web/app/(admin)/admin/dashboard/page.tsx:64-75`** — el más
  delicado: si la consulta de `jornadas` de hoy falla, el Dashboard en vivo
  (la pantalla que Felipe/las encargadas miran para ver "quién está
  trabajando ahora") muestra a todos como "Sin marcar" en vez de avisar que no
  pudo cargar. Fix: capturar y mostrar `error` como ya hace Provisiones.
- [ ] **`apps/web/app/(admin)/admin/correcciones/page.tsx:79-87`** (`cargarDia`)
  — si falla, muestra "No hay marcajes ese día" (mensaje normal de "todo bien")
  en vez de un error — quien va a corregir una incidencia puede concluir que
  no hay nada que corregir cuando en realidad la consulta reventó.
- [ ] **`apps/web/app/(admin)/admin/horas/page.tsx:52-56`** — mismo patrón en
  el resumen mensual de horas.
- [ ] **`apps/web/app/(admin)/admin/incidencias/page.tsx:52-59`** — mismo
  patrón; con el agravante de que si falla, la página literalmente dice
  "🎉 Sin incidencias en el periodo. Todo en orden." (línea 123-126), lo peor
  posible para un fallo silencioso en la página cuyo propósito es alertar.
- [ ] **`apps/web/app/(admin)/admin/perfil/page.tsx:84-96`** (`cargar`) —
  mismo patrón para el historial individual.
- [ ] **`apps/web/app/(admin)/admin/horarios/page.tsx:91-95`** (`cargar`) —
  mismo patrón para personas/horarios/sedes.
- [ ] **`apps/web/app/(admin)/admin/turnos/page.tsx:111-118`** (`cargar`) —
  revisa `fErr`/`arErr` (funciones y áreas) y avisa si fallan (línea 234-239,
  buena práctica), pero **no** revisa el `error` de las 4 consultas restantes
  (`personas`, `horarios_asignados`, `turnos`, `metas_cobertura`) en la misma
  llamada.
- [ ] **`apps/web/app/(admin)/admin/equipo/page.tsx:133-139`** (`cargar`) —
  revisa `personasError`, `funcionesError`, `areasError`, `ingresosError`
  (buena práctica) pero **no** revisa el error de `sedesData`; si falla, el
  selector de sede del formulario de alta queda vacío sin explicación.

---

## 🟡 Permiso verificado solo en la UI (sin equivalente server-side)

Primero lo bueno: se revisaron todas las RPC de escritura sensible
(`fn_set_horario_semanal`, `fn_set_turno`/`fn_set_descanso`/`fn_quitar_turno`,
`fn_set_meta_cobertura`, `fn_guardar_area`/`fn_area_activa`,
`fn_objetivo_agregar/marcar/editar/eliminar`, `fn_crear_persona`,
`fn_set_funcion`, `fn_set_con_hijos`, `fn_set_fecha_ingreso`,
`fn_set_salario`/`fn_salarios_vigentes`/`fn_historial_salario`,
`fn_provisiones`, `fn_periodos`/`fn_proyeccion_periodo`/`fn_crear_periodo`/
`fn_periodo_pagado`/`fn_agregar_movimiento`/`fn_set_objetivos`,
`/api/admin/cuentas`) y **todas** repiten explícitamente `fn_es_admin_o_lider()`
/ `fn_verificar_corrector()` / `fn_puede_gestionar_objetivos()` dentro de la
función `security definer`, con `raise exception` si no corresponde — no
dependen de RLS para bloquear (RLS no se re-aplica dentro de una función
`security definer`, así que si no revisaran el rol adentro, cualquier
autenticado podría llamarlas). Es un patrón sólido y consistente. La única
grieta real encontrada:

- [ ] **`apps/web/app/(admin)/admin/equipo/page.tsx`** — a diferencia de
  Áreas (`puedeGestionar`), Objetivos (`puedeGestionar`), Turnos (`puedeVer`/
  `esAdmin`), Planilla/Provisiones (`puedeVer`) y Cuentas (`esAdmin`), **la
  página Equipo no tiene ningún gate de rol**: ni en `nav.tsx:21` (el enlace
  "Equipo" no tiene `roles: [...]`, a diferencia de Planilla/Provisiones/Áreas
  en las líneas vecinas 19-22) ni en el render — el botón "+ Agregar persona"
  (líneas 653-670) y los botones "Editar" / "Nuevo PIN" / "Desactivar" /
  "Reactivar" de cada fila (líneas 760-770) se muestran a **cualquier rol
  autenticado**, incluida una `integrante` común. En la práctica, los
  intentos de escritura SÍ se bloquean del lado servidor (RLS
  `personas_update_admin_lider` para `cambiarEstado`/`regenerarPin`, que
  escriben directo con `.from("personas").update(...)`; la RPC
  `fn_crear_persona` para el alta) — no es una fuga de datos confirmada. Pero:
  (a) es inconsistente con el resto del panel, que sí oculta estos controles y
  muestra un aviso amable tipo "Solo administradores…"; (b) una integrante que
  entra a `/admin/equipo` ve un formulario "Rol: [Admin ▾]" sobre su propia
  fila y un botón "Guardar cambios" que, si lo intenta, revienta con el
  mensaje crudo de Postgres/RLS en vez de explicarle que no tiene permiso; (c)
  `cambiarEstado`/`regenerarPin` dependen ÚNICAMENTE de RLS (no de una RPC con
  chequeo propio como el resto de escrituras sensibles) — si algún día se
  agrega una policy de UPDATE para `supervisor_sede` en `personas` (como ya
  existe para `marcajes`), este agujero se abre en producción sin que ningún
  chequeo de aplicación lo detenga. **Fix**: agregar el mismo gate
  `puedeGestionar = rol === "admin" || rol === "lider_do"` que usan Áreas/
  Objetivos, ocultar los controles de alta/edición/PIN/estado para el resto, y
  mover `cambiarEstado`/`regenerarPin` a RPC `security definer` con su propio
  chequeo (mismo patrón que `fn_set_con_hijos`), no updates directos por REST.
- [ ] **`apps/web/app/api/admin/cuentas/route.ts:77-84`** (acción `"promover"`)
  — sí verifica que quien llama sea admin/líder, pero no valida que la
  `personaId` recibida tenga `rol = 'integrante'` antes de escribir
  `rol: 'supervisor_sede'`. Hoy el cliente (`cuentas/page.tsx`) solo manda IDs
  que vinieron de `promovibles` (ya filtrados a integrantes), así que no es
  explotable en el flujo normal, pero el endpoint aceptaría degradar a
  cualquier persona (incluido otro admin) si se le pasa su ID por error o por
  un bug futuro en el cliente. Fix: repetir la validación de `rol = 'integrante'`
  server-side antes del update, igual que ya hace el resto de RPCs con sus
  invariantes.

---

## 🟡 Valores fijos que deberían salir de `configuracion`

El propio repo ya sienta el patrón correcto (`bono_puntualidad`,
`asignacion_familiar`, `planilla_provisiones` en la tabla `configuracion`,
editables sin deploy) — estos tres casos no lo siguen:

- [ ] **`apps/web/app/(admin)/admin/equipo/page.tsx:544`** (y comentario en
  línea 86) — el checkbox de asignación familiar dice literalmente
  `"Asignación familiar (tiene hijos) — S/ 113 fijos por periodo"`, un string
  fijo en el componente. El monto real vive en
  `configuracion.asignacion_familiar.monto` (`supabase/migrations/0025_planilla_periodos.sql:70-74`)
  y **ya es editable sin deploy** según su propio comentario ("FIJA... Validar
  aplicabilidad... con el contador" sugiere que puede cambiar). Si Felipe o el
  contador ajustan ese monto vía SQL, este checkbox seguirá diciendo "S/ 113"
  aunque el sistema ya esté pagando otra cifra — a quien decide activar la
  asignación para alguien se le miente sobre cuánto implica. **Fix**: traer el
  monto real (una RPC liviana, o reutilizar el que ya carga Provisiones/Planilla)
  en vez de hardcodearlo en el label.
- [ ] **`apps/web/lib/objetivos.ts:18-31`** (`nivelPlus`) +
  **`apps/web/app/(admin)/admin/objetivos/page.tsx:199-200`** (texto "100%
  cumplidos → 21% del salario · 60% o más → 12.6%") — estos tres umbrales
  (100%→21%, 60%→12.6%, <30%→observación) están **hardcodeados en DOS lugares
  que se pueden desincronizar**: en SQL directo dentro de
  `fn_planilla_calcular` (`0024_planilla.sql:287-291,359-360`,
  repetido igual en `0025_planilla_periodos.sql` y
  `0026_parche_planilla_v2.sql`) y, por separado, reimplementados a mano en
  `lib/objetivos.ts` solo para mostrarlos en Perfil/Objetivos. A diferencia de
  `bono_puntualidad`/`asignacion_familiar`/`planilla_provisiones`, **ni
  siquiera el servidor los lee de `configuracion`** — están soldados en el
  cuerpo de la función SQL. Si alguna vez cambian (p. ej. Felipe decide que el
  plus máximo sea 25%), hay que tocar la migración SQL **y** acordarse de
  actualizar `lib/objetivos.ts` a mano, o el badge "Plus 21%" que ve cada
  persona en su Perfil mentirá sobre lo que realmente le va a pagar la
  planilla. **Fix**: mover los 4 números (`1.0`/`0.21`, `0.6`/`0.126`, `0.3`)
  a `configuracion` (mismo patrón que `bono_puntualidad`) y que
  `lib/objetivos.ts` los lea de ahí en vez de tener su propia copia.
- [ ] **`apps/web/app/(admin)/admin/horarios/page.tsx:9`** (`META_SEMANA = 45`)
  y **`apps/web/app/(admin)/admin/perfil/page.tsx:13`** (`META_DIA = 7.5`) —
  metas de horas hardcodeadas, solo informativas (no afectan el pago), menor
  prioridad pero mismo patrón — 🟢.

---

## 🟢 Accesibilidad / UX — doble-envío y detalles menores

- [ ] **`apps/web/app/(admin)/admin/equipo/page.tsx:763`** (`regenerarPin`,
  botón "Nuevo PIN") — **sin `disabled` mientras está en vuelo** (a
  diferencia de `crearPersona`/`guardarEdicion`/`guardarSalario`, que sí usan
  `guardando`/`guardandoSal`). Es más que cosmético: `regenerarPin` genera un
  PIN aleatorio nuevo, lo hashea (`bcrypt`, con costo perceptible) y recién
  entonces escribe y avisa. Un doble clic dispara **dos llamadas concurrentes
  con dos PINs distintos**; el que se guarda en la base es el que escriba
  último, pero el mensaje verde que el admin copia y entrega es el de
  cualquiera de las dos llamadas que termine de resolver último — no hay
  garantía de que sean la misma. Riesgo real: entregar a un empleado un PIN
  que ya no es el que quedó guardado, y que le falle en el terminal. **Fix**:
  agregar un estado `procesando` por fila (mismo patrón que ya usa
  `cuentas/page.tsx`) y deshabilitar el botón mientras dura la llamada.
- [ ] **`apps/web/app/(admin)/admin/equipo/page.tsx:765,767`** (`cambiarEstado`,
  botones "Desactivar"/"Reactivar") — mismo problema, menor severidad
  (idempotente en la práctica).
- [ ] **`apps/web/app/(admin)/admin/objetivos/page.tsx:321-327`** (checkbox
  `marcar`) y **`:371-376`** (botón `eliminar`) — tampoco deshabilitan
  mientras la llamada está en curso; `eliminar` al menos pasa por
  `window.confirm()` que amortigua el doble clic, `marcar` no tiene ninguna
  protección.
- [ ] **`apps/web/app/(admin)/admin/equipo/page.tsx:657-661`**
  (`sincronizarIngresos`) — mismo patrón, bajo riesgo (la RPC es idempotente).
- [ ] **Zona horaria sin etiquetar** — en toda la app (Horas, Correcciones,
  Horarios, Turnos, Objetivos, Planilla, Exportar, Incidencias) los inputs
  `type="date"`/`type="time"` no dicen en ningún lado "(hora de Perú)". Hoy es
  inofensivo porque todo el equipo opera desde Lima, pero
  `apps/web/app/(admin)/admin/correcciones/page.tsx:20-22`
  (`construirTs`) fuerza el offset `-05:00` sin importar la zona del
  navegador de quien corrige — si alguna vez alguien corrige un marcaje desde
  fuera de Perú pensando en su hora local, el sistema lo registrará como esa
  misma hora pero en Lima, silenciosamente mal. Costaría una etiqueta
  "(hora de Perú)" junto a los campos de hora en Correcciones/Horarios/Turnos.
- [ ] **`apps/web/app/(admin)/admin/turnos/page.tsx:274`** — los botones de
  celda del calendario semanal (uno por persona × día) no tienen `aria-label`
  individual; para lector de pantalla son indistinguibles entre sí más allá
  del texto visible ("+", rango de horas, "descanso").
- [ ] **`apps/web/app/(admin)/admin/objetivos/page.tsx:330`** — el `<input>`
  de edición inline del texto de un objetivo no tiene `<label>` asociado
  (contexto solo visual, dentro del `<li>`).

---

## Investigación: "Vigente desde" se revierte al escribir el día (Horarios)

`apps/web/app/(admin)/admin/horarios/page.tsx` — reportado por Felipe: al
escribir el número de día directamente (no vía el calendario emergente) en
"Vigente desde" (input en línea 272-273), el valor visualmente vuelve al
anterior, reproducible en Chrome.

**Lo que se descartó con certeza (grep exhaustivo del repo):**
- `desde` solo se setea en 2 lugares de todo el archivo: la declaración
  (`useState(fechaHoyLima())`, línea 83) y dentro de `abrirEdicion()`
  (`setDesde(fechaHoyLima())`, línea 120, dispara una sola vez al abrir el
  modal). El único otro sitio es el propio `onChange` del input (línea 273).
  Ningún otro código del archivo ni de sus padres (`AdminNav`, `AdminLayout`)
  toca `desde`.
- **Cero** `setInterval`/polling en este archivo (a diferencia de
  `dashboard/page.tsx`, que sí refresca cada 30s pero es una página distinta).
- **Cero** suscripciones realtime de Supabase en todo `apps/web` (`grep -r
  "\.channel(\|realtime\|\.subscribe("` no devuelve nada) — se descarta
  cualquier re-render disparado por push del servidor.
- **Cero** `addEventListener`/`onKeyDown` a nivel `document`/`window` en este
  archivo o en `AdminNav`/`AdminLayout` que pudiera robar foco o forzar un
  re-render mientras el modal está abierto.
- `React.StrictMode` no está activado explícitamente en `next.config.ts` (usa
  el default de Next), y aunque lo estuviera, el doble-invocado de efectos es
  un artefacto de desarrollo que no se reproduce contra el build de
  producción que Felipe usa a diario en Vercel.

**Diagnóstico más probable:** no parece un bug de este archivo, sino el
comportamiento ya documentado de Chrome con `<input type="date">`
**controlado por React**. El input nativo de fecha tiene 3 segmentos internos
(día/mes/año); Chrome dispara el evento `input`/`change` en cuanto el valor
completo es sintácticamente válido — es decir, apenas se escribe el
**primer** dígito del día (si mes/año ya estaban completos, "1" ya arma una
fecha válida con día "01" provisional). Eso hace que `onChange` (y por lo
tanto `setDesde`) se dispare después de un solo dígito, React re-renderiza, y
vuelve a asignar `value={desde}` al DOM — que es exactamente lo que hace
cualquier input controlado en cada render, incluso reafirmando un valor "ya
correcto". Chrome, al recibir una escritura programática de `.value`, reinicia
el segmento activo/foco interno del campo de fecha al primero — así que justo
cuando la persona teclea el **segundo** dígito (para completar "15"), el foco
ya no está garantizado sobre el segmento del día que estaba editando, y esa
tecla puede aterrizar en otro segmento o el campo "revertir" visualmente lo
que se alcanzó a escribir. Esto reproduce específicamente al **escribir**
(cada tecla va y vuelve por el estado de React) y no al usar el **calendario
emergente** (que confirma la fecha completa en una sola acción nativa, sin
valores intermedios).

Es un problema conocido y reportado en el ecosistema de React (inputs de
fecha controlados + Chrome reiniciando el segmento activo en cada
keystroke), no algo específico de este archivo.

**Por qué puede haberse notado solo en Horarios:** todos los demás campos de
fecha de la app (`Horas`, `Correcciones`, `Exportar`, `Perfil`, `Incidencias`,
`Objetivos`, `Turnos`, `Planilla`) usan exactamente el mismo patrón
`value={x} onChange={(e) => setX(e.target.value)}`, así que en teoría el
mismo glitch debería reproducirse en cualquiera de ellos si se escribe
directamente en vez de usar el calendario — "Vigente desde" en Horarios es
simplemente el campo que Felipe más usa tecleando en vez de hacer clic en el
selector. **Prueba sugerida** (sin necesitar DevTools): pedirle a Felipe que
intente escribir directamente (no hacer clic en el ícono de calendario) en el
campo "Fecha" de Correcciones o en "Desde"/"Hasta" de Exportar — si el mismo
glitch aparece ahí también, confirma que es un problema general de la app y
no algo particular de Horarios.

**Dirección de arreglo sugerida:** desacoplar la escritura en vivo del
`value` controlado — por ejemplo, mantener el input efectivamente
no-controlado mientras tiene foco (un estado/ref local que solo se sincroniza
hacia React `onBlur` o cuando cambia por el calendario), o envolver el input
de forma que solo se le reasigne `value` cuando de verdad difiere de lo que
el DOM ya tiene y el campo no está enfocado. Es el workaround habitual para
este quirk específico de Chrome.

---

## Páginas/patrones revisados sin hallazgos que reportar

Para que quede constancia de que no fue una revisión superficial: `login`,
`olvide-clave`, `nueva-clave` (flujo de auth, bien resuelto — mensajes
genéricos que no revelan si un correo existe, estados de carga/error
correctos); `admin/page.tsx` raíz y `layout.tsx` (triviales, sin lógica);
`exportar/page.tsx` (simple, con degradación explícita si la RPC de salida
temprana falla); `cuentas/page.tsx` + `/api/admin/cuentas` (único endpoint
REST propio del panel — validación de rol server-side correcta); todas las
RPC de escritura de Áreas, Turnos, Objetivos, Horarios, Salarios y Planilla
(chequeo de rol repetido dentro de cada función `security definer`, no
dependen de RLS); `provisiones/page.tsx` (mejor manejo de error/reintento de
todo el panel, buen ejemplo a copiar en las demás páginas).
