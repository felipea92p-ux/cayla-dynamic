# Dynamic — Estado y pendientes

**Este es el único archivo de estado.** Se sobrescribe al avanzar; no se crean
copias con fecha. Lo ya cerrado vive en [`historico.md`](historico.md). Cómo se
trabaja: ver [`CLAUDE.md`](../CLAUDE.md) en la raíz.

## Qué va acá y qué no

Este archivo guarda **solo lo que ninguna herramienta puede responder sola**:
las decisiones tomadas, los pendientes con fecha, lo que depende de una persona,
y lo que se descartó para no volver a investigarlo.

| Pregunta | Quién la responde de verdad |
|---|---|
| ¿Cuántas migraciones hay, hasta cuál? | `ls supabase/migrations \| tail -1` |
| ¿Cuántas pruebas, y pasan? | `npx supabase db reset && npx supabase test db` · `npx pnpm typecheck && npx pnpm test` |
| ¿Producción dice lo mismo que el repositorio? | `scripts/sql-manual/huella_del_esquema.sql` — una fila, dos segundos. Si difieren las funciones con el mismo conteo, `que_funcion_cambio.sql` dice cuál |
| ¿Falta pegar alguna migración? | `./scripts/que-falta-pegar.sh` genera la consulta; `migraciones_aplicadas` guarda el registro |
| ¿Falta anotar alguna migración? | la prueba `122_toda_migracion_deja_su_rastro`, en CI, en cada push |
| ¿Hay números duplicados o huecos nuevos? | `scripts/hooks/numeracion.sh`, antes de cada push |
| ¿Qué se hizo y cuándo? | `git log` |

Ninguna de esas siete puede envejecer sin que alguien se entere. Las de abajo sí,
y por eso están escritas.

⚠️ **Y la tercera fila es la que más caro salió aprender.** Hasta el 2026-08-08
esa pregunta la respondía un comparador que llevaba las huellas del repositorio
escritas dentro, así que caducaba en horas: acusó a 25 funciones que estaban
bien, y mientras tanto seis funciones de producción llevaban semanas dejando
cambiar una planilla ya pagada sin que nadie lo viera. **Un dato de referencia
nunca viaja guardado** — ni en un archivo, ni en un mensaje. Las dos mitades se
calculan en el mismo minuto o no se calculan.

**Regla para quien edite este archivo:** si lo que vas a agregar es un número que
un comando puede calcular, no va acá — va el comando. Y si es una lista de
nombres que hay que revisar, tampoco: va la consulta que los encuentra sola.

---

## 2026-08-25 — Una suspensión de 10 días que nadie ordenó (0294)

**Pendiente: pegar la 0294 en producción** (`./scripts/dame-el-sql.sh 294`). El
md5 de partida **ya está confirmado contra el SQL Editor el 2026-08-25**:
`96f32dbd2ff1c41da38765ef1ec5bbf6`, 994 caracteres — producción tiene la 0075
idéntica al repositorio, comentarios incluidos. Al pegarla no se mueve ningún
documento ya emitido: solo deja de aceptar números que el Reglamento no admite.

**Decidido por Felipe (2026-08-25): el tope se queda en 3.** No se reforma el
RIT. El candado hace cumplir lo que el Reglamento ya dice.

Revisando el caso de Sasha Fernandez (AQP) —segunda suspensión por tardanzas,
que el generador propuso con 2 días— la pantalla mostraba **10 días**: 26, 27,
28, 29 y 31 de agosto, y del 1 al 5 de septiembre.

**Los tecleó Felipe a propósito, para enseñar el defecto**, y conviene que quede
escrito: la primera versión de esta nota supuso que había sido la rueda del
mouse y eso era inventar una causa. El defecto no necesita ninguna: el campo
aceptaba diez días y la base los escribía.

**Los topes estaban escritos en el generador y no en el editor.** La 0235 le
puso a `fn_expediente_generar_tardanza` los tres límites del RIT —54.5 tres días
como techo, 19.2 c) la primera de uno a dos, 19.2 d) la segunda mayor que la
primera— y `fn_expediente_set_suspension` (0075) siguió escribiendo `p_dias` sin
preguntar nada. Cuando la 0075 se escribió, todas las suspensiones salían de un
día y no había qué topar; la 0232 hizo normales los rangos de dos y tres.

**Y el `max={15}` de la pantalla no era una defensa.** El atributo `max` de HTML
no impide escribir ni enviar: solo valida un formulario, y acá hay un `onBlur`
que llama a la RPC. El candado quedó en la base; la pantalla pasa a ser el
letrero, y dice lo que de verdad cabe.

**El campo ya no ofrece un rango fijo, sino el de ESE documento.** Preguntado
por Felipe: no es 1 a 3 siempre. Para quien nunca fue suspendida por tardanzas
son 1 o 2 (19.2 c); para quien ya cumplió una de un día —el caso de Sasha— son
**2 o 3**, porque la segunda tiene que ser mayor. La pantalla calcula ese rango
con la misma cuenta que la base, lo escribe al lado del campo con su motivo, y
pinta en rojo el valor que quede fuera. Un borrador que hoy tenga un número
imposible se ve al abrir la pantalla, no al intentar firmarlo.

Se mantiene además `onWheel` con blur: un `<input type="number">` cambia de
valor con la rueda del mouse cuando el cursor pasa por encima al hacer scroll.
No fue lo que pasó acá, pero mueve días de sueldo sin que nadie lo teclee.

**De paso, un tercero:** «Generar borrador» se ofrecía aunque ya hubiera un
borrador pendiente de esa causal. La base lo rechaza desde siempre, así que el
botón solo podía terminar en error.

⚠️ **El tope de tres días es del RIT de CAYLA, no de la ley.** La LPCL no fija
número —exige proporcionalidad y gradualidad— y la práctica privada peruana
maneja techos informales de ~7 días. Subirlo es decisión de Gerencia, pero se
toma **reformando el RIT y volviéndolo a entregar con acuse**, no aflojando el
candado: un memo que se funda en el Reglamento y lo incumple en su parte
resolutiva no sirve como sanción previa del literal h) del art. 25 el día que
haga falta.

**Lo que queda sin cerrar:** los documentos ya firmados o entregados no se
revisan solos. Si alguna suspensión pasada quedó fuera de los topes, hay que
buscarla a mano — la 0294 solo cuida las que se editen desde ahora.

---

## 2026-08-25 — Revisión nocturna: las nueve cosas más importantes por corregir

**Contexto de esta entrada.** Felipe pidió una revisión de código exhaustiva
mientras dormía. Se lanzaron dos pasadas de auditoría adversarial (Workflow,
46 agentes de búsqueda+verificación, cada hallazgo releído contra el código
real por un escéptico aparte) sobre permisos/RLS, fechas, duplicación de
lógica, cobertura de pruebas SQL, componentes React, seguridad de rutas
`api/` y consistencia de UI. **34 hallazgos sobrevivieron** esa verificación.

**A media noche apareció algo más importante que lo anterior**: el directorio
`auditoria/` —no listado en la tabla de `docs/` de este archivo ni en
CLAUDE.md, por eso ninguna pasada lo leyó— contiene una auditoría previa de
**116 agentes (2026-08-17/18)**, con **80 hallazgos sobrevivientes** (4 P0,
8 P1, 29 P2, 39 P3) y su propio plan de remediación por lotes
(`CAYLA_CORP_OPS_202608_PlanRemediacion.md`). Es sustancialmente más profunda
que lo de esta noche. **Casi todo lo que las dos pasadas de esta noche
encontraron ya estaba ahí catalogado** — incluida, palabra por palabra, la
política RLS del terminal que salió en la primera pasada.

Así que lo de abajo no es "mi lista independiente": es **el estado real,
reverificado esta noche contra el código vivo** (no contra ningún informe) de
lo más grave de esas dos fuentes juntas, más lo genuinamente nuevo que ninguna
de las dos tenía.

**Lo que NO se hizo**: cruzar los 34 hallazgos de esta noche contra los 39 P3
del informe viejo (solo contra P0/P1 y una muestra de P2). Puede haber más
solapamiento del que aquí se descuenta.

### 1 · Nueve funciones `SECURITY DEFINER` entregan datos de cualquier persona a cualquier sesión — P0, sigue abierto

**Dónde:** `fn_falta_contadores` (0094) · `fn_tardanza_escalon` (0246) ·
`fn_dia_suspendido` · `fn_dias_suspension` · `fn_beneficio_ya_depositado` ·
`fn_educacion_monto` (0149) · `fn_es_dia_laborable` · `fn_reglamento_no_acusado`
· `fn_dcs_por_que_no_compensa`. Las nueve corren como `postgres` (sin RLS),
reciben un `p_persona_id` que manda quien llama, y `grant execute … to
authenticated`.

**Por qué importa:** cualquiera de las ~30 personas con cuenta hace un POST a
`/rest/v1/rpc/fn_educacion_monto` con el id de una compañera y se entera de su
banda salarial; con `fn_tardanza_escalon`, si tiene una suspensión encima y
cuál es el siguiente escalón; con `fn_falta_contadores`, las fechas exactas de
sus inasistencias. Los ids de personas no son secretos — salen en el roster
del terminal.

**Reverificado esta noche** contra el Postgres local: las nueve siguen dando
`true` en `has_function_privilege('authenticated', oid, 'EXECUTE')`. El
informe de agosto lo midió con HTTP real (JWT firmado con el secreto local,
`POST /rest/v1/rpc/...` → HTTP 200) y con 8 intentos de refutación fallidos.
El arreglo ya está medido y no toca ninguna pantalla: `revoke execute` en las
nueve — una función `SECURITY DEFINER` que llama a otra lo hace como su dueño
(`postgres`), no como `authenticated`, así que los envoltorios con guard que
sí se usan desde el panel siguen funcionando igual.

**Propuesta:** la migración de revokes, con la prueba pgTAP que fija el
predicado correcto (`prosecdef + grant a authenticated + recibe p_persona_id +
sin guard en el cuerpo` — no "todo prosecdef", eso ya se probó y dio 14 falsos
positivos).

### 2 · Una `lider_do` puede ascenderse a Admin sola, en tres clics y sin dejar rastro — P1→ severidad de facto de P0

**Dónde:** `apps/web/app/(admin)/admin/equipo/page.tsx:422-431` escribe `rol`
directo a la tabla `personas` vía `.update()`; el desplegable que lo alimenta
(líneas 18-23) ofrece "Admin". La policy de UPDATE sobre `personas` solo exige
`fn_es_admin_o_lider()` — no compara el rol de quien llama contra el rol
destino. El camino paralelo (`apps/web/app/api/admin/cuentas/route.ts`) SÍ
llama a `puedeActuarSobre()` del escalafón y por eso rechaza a una `lider_do`
que intente promoverse — la pantalla no pasa por ahí.

**Por qué importa:** Admin ve todos los sueldos, el padrón con DNI y cuentas
bancarias, y puede reabrir un periodo ya pagado. `personas` no tiene tabla de
auditoría ni trigger de cambios de rol — ningún rastro de que ocurrió.

**Reverificado esta noche:** `fn_set_rol` no existe; `equipo/page.tsx:429`
sigue escribiendo `rol: form.rol` directo; la columna `rol` sigue con
`UPDATE` abierto a `authenticated`. Sigue exactamente igual que cuando se
encontró.

**Propuesta (ya decidida en el informe de agosto, con sus descartes
explicados):** una RPC `SECURITY DEFINER` (`fn_set_rol`) que reimplemente el
escalafón dentro de la base, y `revoke update (rol) on personas from
authenticated` — así la regla la cumplen los dos caminos, no solo el que la
llama.

### 3 · El kiosco de marcaje sigue exponiendo DNI y sueldo base por REST directo — P0, el más barato de cerrar

**Dónde:** `supabase/migrations/0008_visible_todas_sedes.sql:12-17` crea la
policy `personas_select_terminal_roster` sin recortar columnas. La 0285
construyó el reemplazo (vista `terminal_roster`) y el frontend
(`apps/web/lib/terminal/roster.ts`) ya migró a leerla — pero la policy vieja
sobre `personas` nunca se retiró, y su propio comentario en la 0285 dice que
se haría "en una migración posterior, después de desplegar el frontend".

**Por qué importa:** el token del terminal es una sesión `authenticated`
normal en una Mac mini sin PIN, a la vista de todo el equipo (decisión
deliberada de Felipe). Con ese token, un `GET /rest/v1/personas?select=
documento,sueldo_base_legal,...` sigue devolviendo filas completas.

**De las tres que forman el "Lote 3" del plan de agosto, ésta es la más fácil
de cerrar ya:** el paso que faltaba (migrar el frontend) ya está hecho y
confirmado. Solo falta `drop policy personas_select_terminal_roster on
personas;`.

### 4 · El candado del mes pagado se mide con el reloj, no con la jornada — riesgo directo para el cierre del 28, sobre todo en TRU

**Dónde:** once funciones (`fn_anular_marcaje`, `fn_corregir_marca`,
`fn_eliminar_marcaje`, `fn_reactivar_marcaje`, `fn_confirmar_auto_cierre`,
`fn_agregar_marcaje`, `fn_corregir_marcaje`, `fn_reabrir_dia`,
`fn_resellar_dia`, `fn_levantar_sello_si_el_dia_cuadra`,
`fn_dias_por_revisar`) derivan la fecha de una marca con `(timestamp_marca at
time zone 'America/Lima')::date`, ignorando la columna `fecha_jornada` que la
0240 introdujo para esto exacto. `fn_recalcular_jornada` sí la usa.

**Por qué importa:** si el turno del día 28 (último del periodo) cierra a las
00:30 del 29, esa salida pertenece —para la planilla— al día 28, pero el
candado la ve como del día 29, que sigue abierto. Se puede anular, corregir o
**eliminar** (`fn_eliminar_marcaje` hace `delete` duro) con el mes ya pagado.
El monto pagado no se mueve —eso lo protege `fn_recalcular_jornada`— pero **el
registro de control de asistencia que lo sustenta sí puede quedar
contradiciéndolo**, sin aviso. Es exactamente el escenario que la 0240 se
escribió para resolver, y TRU —que trabaja domingo y cierra tarde— es la sede
donde más ocurre.

**Sin reverificar esta noche por tiempo** — el informe de agosto lo midió con
4 intentos reales en `BEGIN…ROLLBACK`, todos exitosos salvo el primero.

**Propuesta:** sustituir la expresión en las once funciones por
`coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date)`
— la expresión correcta ya vive en `fn_trg_marcajes_recalcular_jornada`, solo
falta extraerla a una función compartida y llamarla desde las once.

### 5 · DNI, correos y celulares reales de diez personas, commiteados y ya en GitHub — P0, no es tarea de código

**Dónde:** `supabase/migrations/0130_los_datos_del_tregistro.sql` y dos
migraciones más.

**Por qué importa:** ya está publicado. Borrarlo del archivo hoy no lo
despublica del historial de GitHub.

**Esto es una decisión de Felipe, no una migración.** Reescribir el historial
de un repo con varias sesiones trabajando en paralelo tiene su propio costo y
riesgo — se anota aquí para que la decisión no se pierda, no para proponerla
a ciegas.

### 6 · El descanso médico sigue pagando sin que DO lo apruebe

**Dónde:** los laterales de ausencias en `fn_planilla_calcular` filtran
`anulada_at is null` y nunca miran `aprobada_at`. `fn_registrar_ausencia` deja
registrar a la encargada de sede; `fn_aprobar_ausencia` solo a admin/lider —
pero la planilla no espera esa aprobación para pagar.

**Reverificado esta noche:** `grep -c aprobada_at` sobre el cuerpo vivo de
`fn_planilla_calcular` da cero. Sigue exactamente como lo dejó el informe de
agosto (que además ya había medido: hoy, cero soles mal pagados — julio se
congeló antes de que existiera el concepto).

**De paso, un vecino sin lote asignado:** `licencia_con_goce` está marcada en
el catálogo como que paga y requiere aprobación, y `fn_planilla_calcular` no
la paga por ningún lado — el error contrario (alguien deja de cobrar), sin
investigar.

**Propuesta:** ya está diseñada en el plan de agosto — tres líneas dentro del
bloque de feriados (con cuidado: tocar solo dos de las tres rompe el
prorrateo del feriado dentro de una licencia, medido en −S/22.17). Antes de
escribirla: `donde-vive.sh fn_planilla_calcular` y el md5 de producción, igual
que siempre.

### 7 · `guardarDocumento()` muestra "archivado" con éxito aunque la segunda mitad del guardado haya fallado — nuevo esta noche

**Dónde:** `apps/web/app/(admin)/admin/documentacion/page.tsx:642-651`. La
primera llamada a `fn_documento_registrar` (crear el registro) sí chequea
`error`; la segunda (adjuntar el `storage_path` del archivo ya subido al
registro recién creado) no lo chequea, y el flujo sigue hasta mostrar el
aviso de éxito.

**Por qué importa:** un documento puede quedar registrado sin su archivo
adjunto, y la persona que lo subió cree que quedó archivado. Es exactamente
el tipo de silencio que CLAUDE.md señala como el peor error de este sistema,
aplicado a un documento con valor legal (política, movilidad, bono).

**Propuesta:** destructurar `error` de la segunda llamada y, si falla, avisar
en vez de mostrar éxito — mismo patrón que ya usa el primer bloque.

### 8 · La regla "qué mes de educación falta un comprobante" está escrita 3-5 veces, casi sin prueba — nuevo esta noche

**Dónde:** `supabase/migrations/0290_un_comprobante_por_mes_y_no_uno_por_
asignacion.sql` crea `fn_educacion_papeles` (:328), `fn_educacion_meses_
sin_papel` (:355) y `fn_educacion_por_atender` (:465) — ninguna de las tres
se llama por su nombre desde `supabase/tests/`. `fn_educacion_listar` (:386,
sí probada en el test 226) trae una cuarta copia inline de la misma lógica, y
es esa cuarta copia la que el test termina verificando.

**Por qué importa:** `fn_educacion_por_atender` es el contador que le avisa a
DO qué papeles faltan perseguir. Si alguien corrige una sola de las cinco
copias, el contador del menú puede decir "0 pendientes" mientras la lista
real muestra filas con `meses_sin_papel > 0` — y nadie va detrás del papel
que sustenta un pago ya hecho.

**Propuesta:** sobre el mismo laboratorio del test 226, sumar 3-4 aserciones
que llamen directo a las tres funciones sueltas y comparen contra la columna
`meses_sin_papel`.

### 9 · Tablas nuevas con datos sensibles, con RLS pero sin ninguna prueba que confirme que protege — patrón, nuevo esta noche

**Dónde:** `contratos_generados` + el bucket "contratos" (0272/0287, sueldos y
PDFs firmados) · `asignaciones_regimen_pension` (0261, régimen de pensión) ·
`educacion_comprobantes` (0290). Las tres tienen policies que restringen a
admin/lider o a la propia persona, y **ningún test cambia de usuario** para
comprobar que alguien sin ese rol quede bloqueado — todos los tests
relacionados corren con una sola sesión admin de principio a fin.

**Por qué importa:** el patrón ya existe en el repo y funciona
(`supabase/tests/198_...` sí cambia de usuario con `set local role
authenticated`). Sin ese segundo usuario en estas tres, un error futuro en
cualquiera de las tres policies no lo detectaría ningún pgTAP — se enteraría
alguien mirando por accidente el sueldo o el contrato de otra persona.

**Propuesta:** sumar el patrón del test 198 a los tests 223 (contratos), 214
(régimen de pensión) y 226 (educación): tras crear el dato como admin, cambiar
a una persona sin ese rol y comprobar `count(*) = 0`.

---

**Una corrección de paso.** El informe de agosto decía que `feriados/page.tsx`
"al menos sí confirma" antes de quitar un descanso sustitutorio ya otorgado.
Releído el código esta noche: **no confirma** — `quitar(id)` llama a la RPC en
el primer clic, sin `window.confirm`. El comentario que hay al lado (líneas
714-719) explica por qué debería confirmarse, pero no hay ningún código que lo
haga cumplir. Esto es parte del **P2 "Cinco acciones que devuelven plata... al
primer clic"** del informe de agosto (línea 1079), que también cubre
`quitarJustificacion`/`quitarLevantamiento` en incidencias, horas y
correcciones — las dos pasadas de esta noche redescubrieron ese mismo P2 sin
saber que ya existía.

**Lo que queda fuera de los nueve, y por qué:** cuatro P1 más del informe de
agosto sin reverificar esta noche por tiempo —`fn_dia_incoherente` y
`fn_siguiente_tipo_esperado` no conocen `fecha_jornada` (sella marcas buenas
como "pendiente de revisión" el día después de un cruce de medianoche); el
botón "¿Volviste a entrar?" del terminal puede borrar la salida real de
anoche; el auto-cierre (3 h) llega antes que la ventana de la 0240 y la salida
de madrugada se sigue rechazando; una incidencia de quien marca fuera de su
sede sale sin nombre y no se puede sacar de la lista—, más 29 P2 y 39 P3 que
no se leyeron esta noche. Todo vive en `auditoria/CAYLA_CORP_RPT_202608_
Auditoria.md` y su plan en `auditoria/CAYLA_CORP_OPS_202608_PlanRemediacion.md`.

---

## 2026-08-24 — Un comprobante por cada mes que se paga (0290)

**Aplicada en producción y verificada.** Los 15 comprobantes que había se
mudaron a `educacion_comprobantes` y ninguna asignación perdió el suyo.

**Lo que lo motivó, medido:** de las trece asignaciones vigentes de ese día,
**diez abarcaban dos o tres periodos de planilla con un solo comprobante**. El
pago era correcto —una pensión mensual se repite— pero el sustento no estaba
completo, y no se podía arreglar: la tabla admitía un comprobante y nada más.

Tres decisiones de Felipe:

1. **Cada papel dice qué mes respalda.** Contar no basta: se apagaría el aviso
   subiendo tres veces el recibo de agosto.
2. **El mes es el del PERIODO, no el del calendario.** Un tramo del 29/08 al
   28/09 se paga una vez; pedir dos papeles sería pedir papel de más.
3. **El aviso se ve también en el contador del menú**, no solo al entrar.

Y una que no se pidió pero decide el riesgo: **`comprobante_url` no se borró**.
Pasó a ser un espejo que mantiene un trigger, así que `fn_planilla_calcular` no
se tocó. La regla «sin papel no devenga» sigue viva sin que la planilla se entere
de que ahora hay una tabla detrás.

**Ojo con el contador de Educación:** subió al pegar la migración, y no es que
algo se haya roto — ahora cuenta las asignaciones que ya cobraron un mes sin
papel, que era el caso invisible.

**Pendiente operativo, no de código:** pedirle a DO los comprobantes de los meses
que ya se cobraron. La pantalla dice cuáles son, fila por fila.

---

## 2026-08-24 — Los planes anuales se cargan por tramos

Duolingo y Domestika no son pensiones mensuales: son cargos que se pagan una vez.
Con la vigencia puesta a varios meses, se pagaba cada mes contra un gasto único —
S/810 contra un comprobante de S/499 en el caso de Sandra.

**Se resolvió sin tocar el sistema**, partiendo el comprobante en tramos que
suman el papel exacto: una fila por periodo, con el trozo del gasto que se imputa
a ese mes. Sandra 360 + 139 = 499; Diana 120 + 120 + 34.90 = 274.90. Cada tramo
lleva el mismo comprobante adjunto y una nota que dice de qué plan sale.

**Lo que el sistema sigue sin saber es que un comprobante puede cubrir más de un
mes.** Mientras eso no exista, un plan anual hay que cargarlo a mano así, y nada
avisa si alguien no lo hace.

---

## 2026-08-22 — El techo de educación se reparte, y sigue al rango (0281)

**Decidido por Felipe.** Tres decisiones, y las tres cambian plata:

1. **El segundo comprobante entra por el saldo, no rebota.** El monto pasa a ser
   `min(costo × 75 %, techo − lo que ya usan las asignaciones que SE SOLAPAN)`.
   Antes, con techo de S/180, quien ya cobraba S/150 por su instituto no podía
   registrar el colegio de su hija ni por los S/30 que quedaban: el monto no se
   teclea desde la 0149, así que no había forma de cargar ese papel.
2. **El reparto va por orden de registro**, no a prorrata: la primera conserva su
   monto y la siguiente se queda con el saldo. Un solo criterio, el mismo que
   rige el alta.
3. **El techo sigue al rango, en las dos direcciones.** Al cambiar de rango las
   asignaciones se realinean solas desde el primer periodo no pagado — cerrando
   la vigencia vieja y abriendo una nueva, con rastro en `correcciones_auditoria`.
   La 0132 había dejado ese hueco a propósito («queda por encima del techo nuevo
   hasta que se la toque») y nadie la tocaba nunca.

**Lo que NO se hizo, y es decisión, no olvido:** la política salarial publicada
sigue diciendo «cubre el 75 %… hasta el tope de tu categoría». No es falsa —solo
no menciona el reparto— y publicar una versión nueva obliga a pedir acuse de
recibo a todo el equipo otra vez (0141). Se agrupa con el próximo cambio de
política.

**Pendiente:** pegar la **0281** en producción (`./scripts/dame-el-sql.sh 281`).
Al pegarla no se mueve ningún pago por sí sola: no recorre las filas existentes.
Las que hoy estén por encima de su techo siguen igual hasta que se toque su rango
o se corrija a mano — y eso último, desde la 0281, se puede: el candado dejó de
rechazar también los arreglos hacia abajo.

---

## 2026-08-19 — Auditoría de 22 agentes contra la ley peruana

93 hallazgos. Los cinco escépticos tumbaron **46 por no tener población en
CAYLA**, 9 por decisiones ya tomadas, 3 por no reproducirse, 3 por estar
arreglados. Quedan 47 mecanismos confirmados contra el cuerpo VIVO de las
funciones. El catálogo entero, agrupado por dónde muerde, está en
[`hallazgos-abiertos.md`](hallazgos-abiertos.md#auditoría-del-2026-08-19--22-agentes-contra-la-ley-peruana).

**Lo único que hace falta decidir antes del 28 es esto:** correr
`scripts/sql-manual/a_quien_le_pega.sql` en el SQL Editor. Nueve preguntas, un
solo `select`. Hasta que se corra, esos 47 son mecanismo confirmado con
población DESCONOCIDA — que no es lo mismo que plata perdida, y confundirlos es
exactamente lo que costó cinco falsas alarmas el 2026-08-18.

Cerrado el mismo día:

- **0275** · las vacaciones dejan de pagarse en cero. Quien pasaba el periodo
  entero de vacaciones cobraba S/0.00 por el 0/0 de `hh.pago / dias_marcados`.
  **Aplicada en producción el 2026-08-20**, y comprobada como se comprueban
  estas: el md5 que devolvió el SQL Editor se comparó contra el que da aplicar
  la migración sola en el Postgres local dentro de `BEGIN…ROLLBACK`, en el mismo
  minuto. Coincide, y con la misma longitud — los comentarios llegaron enteros,
  que es lo que se pierde cuando el portapapeles rompe los acentos.
- **`va_a_poder_cerrarse.sql`** conocía solo uno de los dos frenos del cierre:
  daba «✓ TODOS CUADRAN» y `fn_planilla_congelar` abortaba igual por el freno de
  la 0243/0244.
- **La boleta** se contradecía sobre la AFP —«no se descuenta de tu sueldo» en la
  misma hoja que imprime el descuento— y no identificaba al empleador.
- **El RUC y la razón social**, que estaban escritos a mano en ocho documentos,
  se leen de `packages/shared/src/empresa.ts`. Lo que NO se unificó es el
  formato: los ocho escriben el RUC distinto y dos están congelados con firmas
  encima (la política salarial por la 0141, el contrato en `documento_html`).
  `tests/empresa.test.ts` vigila las dos mitades — que no aparezca una novena
  copia, y que ningún documento cambie de forma.

Decidido con Felipe y pendiente de construir: **la sobretasa del 100 % por
trabajar el día de descanso semanal** (art. 3 del D. Leg. 713), que hoy no
existe en el sistema. Se hacen **las dos cosas**: registrar el descanso
sustitutorio cuando lo hubo, y pagar la sobretasa cuando no. Golpea sobre todo a
TRU, que es el régimen de 6 días con descanso rotativo.

**CONSTRUIDA Y EN PRODUCCIÓN: la 0280**, pegada el 2026-08-22 y verificada por
md5 (`0912fcb7…`, 91 394 caracteres, calculado en el mismo minuto). La boleta la
imprime con el día que la dispara, y `chk_foto_cuadra` y `fn_planilla_congelar`
fueron con ella — sin eso el cierre del mes se caía entero, que es lo que la
0201 ya pagó una vez.

Lo que NO hizo falta: registrar el descanso sustitutorio. El art. 3 paga «sin
sustituirlo por otro día en la misma semana», y si se sustituyó ese día libre
CORTA la racha y no hay séptimo día. La racha es la prueba. El feriado sí
necesita actas (0069/0093/0238) porque allí el día compensatorio puede caer
semanas después.

**Y RIGE DESDE AHORA, NO HACIA ATRÁS** (Felipe, 2026-08-20). Se midió lo que
costaría —`cuanto_cuesta_el_descanso_semanal.sql`, S/163.19 del periodo en curso
y S/374.61 del de julio ya pagado— y la decisión es que la política empieza
cuando empieza. **El periodo cerrado no se reabre**, así que esa segunda cifra
no es una deuda: es la medición de por qué conviene construirlo pronto.

**La 0276 también está en producción**, entera y anotada (20/08 21:03). Se
comprobó antes de entregarla y por eso no se entregó: sus tres piezas
—`fn_planilla_calcular`, `fn_provisiones` y la nueva `fn_feriado_devengado`—
devuelven los md5 que produce esa migración, medidos aplicándola sola en local
dentro de `BEGIN…ROLLBACK`.

El susto valió la pena igual: el md5 de `fn_provisiones` no coincidía con el que
la 0276 declara como punto de partida, y el primer impulso fue leerlo como «otra
versión desconocida». Lo que era, medido contra las siete versiones históricas,
es la 0276 **ya aplicada**. Con `migraciones_aplicadas` no habría bastado — es
el registro que el 2026-08-19 dijo que la 0196 estaba puesta mientras el cuerpo
vivo era el de la 0158.

### Tres cosas que se persiguieron el 2026-08-20 y no eran

Se anotan porque las tres son creíbles y las tres cuestan una tarde:

1. **«A veinte personas les bajó el sueldo el 29/07».** Es el rediseño
   remunerativo: la base declarada por rango (0128), compensada con movilidad,
   educación y bono. **Todo el equipo lo aceptó.** Las notas de
   `asignaciones_salario` lo dicen con todas sus letras — se leen antes de
   alarmarse.
2. **«Quien cumple su jornada queda bajo la RMV en meses de 31 días».** No: el
   piso vive en el cálculo. `fn_planilla_calcular` declara
   `greatest(bri.base, piso_essalud)` y ese piso es la RMV entera. Declarar y
   pagar por horas no son lo mismo. Es el quinto defecto de la tabla de
   descartados del anexo, perseguido otra vez.
3. **«Cinco personas marcan mucho menos de 45 h/semana».** Son **turnos
   reducidos**, confirmado por Felipe. El pago por horas es correcto y no se
   reabre.

Pendiente de mirar renderizado, dos minutos: la boleta y el memo.

**Y una pregunta que solo Felipe puede responder: ¿cuál es el domicilio legal?**
Al unificar la identidad de la empresa había dos direcciones distintas en el
código. La que declaran los contratos firmados dice «Urb. San Andrés **V Etapa**,
distrito de Trujillo, provincia de Trujillo, departamento de La Libertad»; la
otra, más corta, no salía de ningún documento y no la usaba nadie. Se tomó la de
los contratos, así que **hoy no hay ningún papel que haya cambiado de texto** —
queda comprobar contra la ficha RUC que esa sea la buena, porque desde ahora la
dice un solo sitio.

---

## 2026-08-25 — El aviso de vacaciones se construyó dos veces, y el duplicado lo rompió

La **0297** creó `fn_vacaciones_por_vencer` desde una rama, con su prueba, su
banda en Ausencias, su entrada en el menú y en «Lo mío», y sus tipos
regenerados. Dos días después la **0299** creó la misma función desde otra rama,
sin comprobar que ya existía.

**No quedó en trabajo perdido.** Las dos tenían todos sus argumentos con valor
por defecto, así que la llamada sin argumentos encajaba en las dos:

    ERROR: function fn_vacaciones_por_vencer() is not unique

Con las dos vivas el aviso NO se mostraba. Es el mismo accidente que la 0278
documentó al agregar un parámetro con `create or replace`: no falla al pegar la
migración, **falla al abrir la pantalla**.

La [`0301`](../supabase/migrations/0301_retirar_la_copia_duplicada_del_aviso_de_vacaciones.sql)
suelta la firma de la 0299. **Está pegada en producción el 2026-08-25** y
confirmada: queda una sola, `p_dias integer, p_as_of date`, md5 `0f4ea1c9…`.

**Sobrevive la de la 0297 y no por antigüedad.** Ve más gente —cada persona sus
propios días, una encargada los de su sede—, devuelve la sede, y sobre todo
tiene una condición que la otra no tenía:

    and ( dias_para_vencer <= p_dias or records_vencidos > 0 )

con este comentario suyo: «quien YA tiene un récord vencido puede tener el
siguiente a un año de distancia, y con solo el filtro de los 60 días desaparecía
de la lista justo la persona más urgente. Se vio en el panel con datos de
prueba, no razonándolo». La otra filtraba solo por la ventana: **a quien más
urge avisarle, no le avisaba**.

**La causa de raíz, y la regla que salió de ahí:** no se corrió
`./scripts/donde-vive.sh` antes de escribir, porque el script se leía como «para
reescribir una función». Ya está en CLAUDE.md que **también se corre antes de
crear**: con varias sesiones a la vez, «esta función no existe» es una
suposición, no un hecho.

**Y lo único que destapó todo esto fue pedir el md5 después de pegar.** Dos
filas donde debía haber una. Sin esa comprobación, el aviso habría quedado roto
en silencio hasta que alguien abriera la pantalla.

---

## 2026-08-25 — Tres arreglos más, y una decisión de la 0254 revertida con la norma en la mano

Tres migraciones pegadas en producción el 2026-08-25, cada una confirmada por
md5 antes y después:

**[`0286`](../supabase/migrations/0286_un_dia_fichado_no_se_paga_tambien_como_ausencia.sql)
· un día fichado no se paga también como ausencia.** Cuatro personas idénticas,
tres con una ausencia registrada: quien fichó estando de vacaciones o con parte
médico cobraba el día DOS veces, S/337,93 por semana solapada. `fn_provisiones`
ya excluía ese día desde la 0135 y la boleta nunca se enteró — era una QUINTA
diferencia entre las dos bases, y la única que salía del banco cada mes.
Hubo que arreglarlo en dos sitios: con la guarda solo en la boleta quedaba un
residuo de S/23,41 que era `fn_feriado_devengado` recalculando por su cuenta.
La boleta gana `dias_solapados`, que avisa aunque ya no cueste plata.

**[`0289`](../supabase/migrations/0289_la_gratificacion_ya_depositada_no_se_paga_dos_veces.sql)
· la gratificación ya depositada no se paga dos veces.** Se deposita el 15 y el
periodo no cierra hasta el 28: quien cesaba en medio la cobraba otra vez entera,
S/1.062,75. Trece días en julio y trece en diciembre. La comprobación pedía que
el periodo estuviera `pagado` Y que hubiera terminado antes del cese, y el día 20
fallan las dos. **La segunda condición no era un descuido** —sin ella un cese de
septiembre daría por cobrada la de diciembre— así que no se quitó: se le cambió
el ancla, de «¿cerró el periodo?» a «¿ya llegó el 15?».

**[`0293`](../supabase/migrations/0293_el_feriado_dentro_de_un_descanso_medico_se_paga.sql)
· el feriado dentro de un descanso médico se paga.** Revierte una decisión de la
0254, que lo excluyó porque «la planilla ya lo paga en su propia línea». Medido,
esa premisa no se sostiene: el feriado es un PRORRATEO, no una línea que pague un
día —quien trabajó el mes entero cobra S/350,26 de feriados y quien faltó una
semana, S/252,24—. No había doble pago; había un día que no pagaba nadie, y solo
a quien estaba enfermo. La norma lo dice al revés en tres artículos: art. 8 del
D. Leg. 713 → art. 4 → art. 3 del D.S. 012-92-TR, que incluye las «enfermedades
debidamente comprobadas» entre los días efectivamente trabajados.

### Lo que se decidió NO tocar, con su medición hecha

**El 1 de mayo sigue prorrateándose.** El art. 8 lo saca de la regla —«salvo el
Día del Trabajo, que se percibirá SIN CONDICIÓN ALGUNA»— así que hoy se paga
corto a quien tuvo un mes flojo: **S/12,50 por persona a jornada completa, una
fecha al año, del orden de S/250 anuales en el equipo**. Decisión de Felipe del
2026-08-25, tomada con la cifra delante. Lo que se elimina el 1 de mayo NO es la
proporción por el tamaño de la jornada —un part-time cobra su propia jornada—
sino la proporción por cuántos días vino ese mes.

**El prorrateo general del feriado tampoco se toca.** Sigue siendo decisión de
Felipe, confirmada en `docs/planilla-anexo-tecnico.md`, y la prueba 229 la
defiende con una aserción propia para que ninguna corrección futura la arrastre.

### La lección de método de estos dos días

**El md5 de llegada se mide DESPUÉS de renumerar.** Pasó con la 0286 el 24, se
documentó, y volvió a pasar con la 0289 el 25 — porque lo escrito decía cómo
reconocer el síntoma («misma longitud, distinto hash») y no cuándo medir. Ya está
en CLAUDE.md como regla.

**Y la duplicación de `fn_feriado_devengado` mordió tres veces**: en la 0276, en
la 0286 y en la 0293. Cada vez el mismo patrón —el arreglo puesto solo en la
boleta deja un residuo de unos pocos soles que no cuadra— y cada vez cuesta una
medición extra encontrarlo. Unificar esas dos copias sigue pendiente.

---

## 2026-08-24 — Tomarse las vacaciones dejó de costar dinero

La [`0283`](../supabase/migrations/0283_las_vacaciones_no_gozadas_se_pagan_al_cesar.sql)
está **pegada en producción el 2026-08-24**: `fn_vacaciones_truncas` pasó de
`9535ed57…` (3 228 chars) a `a005fc69…` (8 117 chars).

**El defecto, medido.** Dos personas idénticas —mismo sueldo, mismo ingreso,
mismo día de cese—. La única diferencia es que una se tomó sus vacaciones:

| | vacaciones que pagaba la hoja |
|---|---|
| Nunca gozó | S/ 812,50 |
| **Gozó sus 15 días cuando la ley manda** | **S/ 0,00** |

La causa era una ventana: la cuenta empezaba en el último aniversario, y los 15
días que se ganan al CERRAR un récord se gozan DESPUÉS del aniversario. Caían
dentro y se restaban del récord nuevo. El mismo descanso se cobraba dos veces, y
solo a quien lo tomó. Por el mismo borde se caían los récords completos sin
gozar: quien llevaba dos años sin vacaciones cobraba el trunco y nada más.

**Por qué la cuenta acumulada no puede pagar doble** —la condición que puso
Felipe antes de aprobarlo—: cada día que la persona se tomó en su vida se resta
UNA vez del total que ganó en su vida; `vacaciones` es una VISTA sobre
`ausencias`, así que un día no puede contarse por dos tablas; y ahora se
descuenta el libro de desembolsos, que esta era la única de las tres truncas en
no mirar.

**Se comprobó el historial antes de escribirlo**, porque el único modo en que
esta cuenta puede equivocarse es que un goce no esté registrado. De las 20
personas activas, las cuatro con un año cumplido se tomaron EXACTAMENTE sus 15
días, y las 16 restantes no han cumplido el año. Nadie tiene saldo pendiente ni
récord vencido: no hizo falta fecha de corte.

**La indemnización del art. 23 se avisa y no se calcula** (decisión de Felipe):
tiene excepciones que el sistema no sabe distinguir. Y lo que de verdad la evita
es avisar ANTES de que el récord venza — pendiente, y es la mejor idea que salió
de esta tanda.

---

## 2026-08-22 — Un bono de S/50 costaba S/318 al cesar, y ya no

La [`0278`](../supabase/migrations/0278_ni_los_descuentos_ni_los_beneficios_inflan_la_liquidacion.sql)
está **pegada en producción el 2026-08-22**, confirmada por sus seis md5.

**El defecto era una línea.** `fn_remuneracion_computable` buscaba los conceptos
variables con `where mp.monto > 0`, y la tabla tiene `CHECK (monto > 0)`: la
condición es siempre verdad. No filtraba nada. Entraban los descuentos —un
adelanto es dinero que la persona DEBE—, la gratificación y la CTS que el propio
sistema deposita.

Y la puerta la abría el sistema solo: hacen falta 3 meses distintos con
movimientos, y el depósito del 15/07 y el del 15/11 ya ponen dos. Medido, sueldo
S/1.950, cese al 30/11:

| | antes | después |
|---|---|---|
| Solo grati + CTS (la correcta) | 1.867,40 | **1.867,40** |
| + un bono de S/50 | 2.185,46 | **1.867,40** |
| + un adelanto de S/500 | 2.257,01 | **1.867,40** |

**Cuatro piezas:** el filtro (solo `tipo='bono'` con categoría nula u «otros»);
la ventana por beneficio (la CTS mira nov-abr, no el semestre de la grati); la
regularidad **por concepto** y no por el saco (art. 16: «siempre que **las** haya
percibido tres meses» — el sujeto es cada remuneración); y el candado, que
RECHAZA el bono que sería el tercer mes del mismo concepto, con salida
autorizada de un solo uso y motivo obligatorio (decisión de Felipe).

**Lo que se cuidó, y es la mitad que nadie pide:** un bono genuinamente regular
SIGUE entrando. Excluirlo sería pagar por debajo del art. 16, que es infracción,
no ahorro. La prueba 215 lo defiende con una aserción propia.

### Tres cosas que solo aparecieron al ejecutarlo

- **`create or replace` con un parámetro nuevo no reemplaza: crea una
  SOBRECARGA.** Convivían la firma de dos argumentos y la de tres, y toda
  llamada existente quedaba ambigua. No falla al aplicar la migración: **falla
  al abrir la hoja de liquidación**. Va con su `drop function`.
- **El aviso de la propia migración gritaba «ATENCIÓN» estando todo bien**,
  porque buscaba en el código una línea que el arreglo cita dentro de un
  comentario. Un aviso que salta cuando todo está bien es peor que no tenerlo.
  Ahora quita los comentarios antes de mirar.
- El `sed` del renumerado (el 0277 lo tenía otra rama) se llevó por delante los
  UUID de la prueba, que llevan «0277» dentro. Cuidado con los reemplazos
  globales sobre archivos con identificadores.

### Lo que la 0278 NO cierra, y va en la dirección contraria

**La hoja de liquidación paga de menos las vacaciones al cesar.** Medido el
2026-08-22 con dos personas idénticas, mismo sueldo, misma antigüedad, cese el
mismo día:

| | vacaciones que paga |
|---|---|
| Nunca gozó | S/812,50 |
| **Gozó sus 15 días cuando la ley manda** | **S/0,00** |

Los días gozados del récord ANTERIOR se restan del récord en curso. Y quien
nunca gozó cobra solo el año en curso: sus récords completos —30 días en el caso
medido— no aparecen en ninguna línea de la hoja.

Va **en contra de la persona**, y cae en el único camino sin campo editable: la
liquidación recalcula, congela y paga. **Sin cifra global verificada**: la que
circuló (S/1.896 sobre una «persona corriente») venía de un laboratorio de un
agente y no se comprobó. Lo que sí está medido es la tabla de arriba.

---

## 2026-08-20 — El feriado entra en la reserva, y una migración que casi revierte un sueldo

La [`0276`](../supabase/migrations/0276_una_sola_base_para_la_reserva.sql) está
**pegada en producción el 2026-08-20**, confirmada por sus tres md5:
`fn_planilla_calcular` `b132c828…` → `2f38e5ce…`, `fn_provisiones` `84aae8bf…` →
`93531851…`, y `fn_feriado_devengado` nueva en `f6bbe9ab…`.

**Qué arregla.** La boleta calculaba las provisiones sobre `pago_base + feriados
+ asignación familiar` y `fn_provisiones` las calculaba **sin el feriado** — la
palabra no aparecía ni una vez en sus 610 líneas. Y esa función es la que
autocompleta el monto del depósito el 15/05, 15/07, 15/11 y 15/12, así que se
depositaba corto: **~S/ 2.400 al año, siempre en contra del equipo**. Ahora el
feriado se calcula en `fn_feriado_devengado` y lo preguntan las dos. De paso
llega a la reserva el factor de la 0111.

**La decisión legal, para no reabrirla.** Las dos mitades del feriado entran en
la base: el día prorrateado (art. 8 del D. Leg. 713, remuneración ordinaria) y
la sobretasa por trabajarlo (art. 9). Sin `if` de regularidad, y medido: las 27
ventanas de pago de 2026 a 2032 tienen feriados en **4 o 5 meses distintos**,
nunca menos de 4, y el umbral del art. 16 del D.S. 001-97-TR son 3. El
calendario peruano no hace fallar ese test.

### Lo que casi sale mal, que es lo que hay que recordar de este día

La primera versión copió el cuerpo de la boleta de la **0269** porque
`donde-vive.sh` decía que esa era la vigente — y **lo era, en esa rama**,
mientras otra sesión ya había fusionado la **0275** a `main` y Felipe la había
pegado. Pegarla habría revertido la 0275 en silencio: **quien pasa el periodo
entero de vacaciones habría vuelto a cobrar S/ 0.00 su mes.** No da error;
devuelve otro número.

No fue descuido de método: se hicieron las dos comprobaciones que este repo
manda, y las dos miran el worktree. `db reset` reconstruyó un esquema entero sin
un solo error, sin la 0275, que no estaba en el árbol. Lo cazó **el md5 de
producción** —90.707 caracteres allá contra 89.527 acá— o sea el último freno de
la cadena, con el trabajo hecho, verificado y commiteado. Lo confirmó la prueba
212, que es de la otra sesión: falló en sus tres aserciones de vacaciones.

Y llevaba la misma trampa enterrada dos veces: `fn_feriado_devengado` copió
también el `horas_vacaciones` de antes del arreglo, mientras el de al lado
—descanso médico— sí tenía su respaldo desde la 0254. Ahora las dos están juntas
y con la misma forma, a propósito.

**De ahí salen las dos defensas nuevas:**
`scripts/hooks/main-tiene-migraciones-que-no-tienes.sh` avisa al empujar cuando
`main` trae migraciones que tu rama no tiene, y **sube el tono si tocan tus
mismas funciones** (probado contra el commit del accidente: detecta la 0275 y el
choque en `fn_planilla_calcular`). Y CLAUDE.md pasa a decir que el md5 de
producción se pide **antes de escribir**, no antes de entregar.

### Lo que la 0276 NO cierra, declarado en su encabezado

1. **El divisor del sueldo** — la boleta divide entre los días del periodo
   (29→28) y las ramas viejas de `fn_provisiones` entre los del mes calendario.
2. **El día de ausencia pagada** — la boleta paga días laborables a tarifa
   promedio; la rama 4 paga días calendario. S/ 178,93 en un mes para quien tuvo
   19 días de vacaciones. Lo único que la 0276 arregla de aquí es el feriado
   duplicado dentro del descanso médico, que rompía ella misma.
3. **El factor de la 0111 en el borde** — por día en la reserva, por último
   tramo en la boleta. Se separan un −6,2 % / +13,1 % si `base_provision` cambia
   a mitad de periodo.
4. **La liquidación por cese usa una TERCERA base**, `fn_remuneracion_computable`
   (0129), a la que el feriado no puede llegar. Para el sueldo fijo cambia el
   signo de la brecha: de S/ −0,04 a S/ +26,52.

### Pendiente medido, para su propia migración

**Un adelanto quincenal le SUBE la liquidación a la persona.**
`fn_remuneracion_computable` suma los `movimientos_planilla` con `monto > 0` sin
filtrar categoría ni tipo, así que la gratificación depositada y **los
descuentos** entran como «variables» en la base de la liquidación siguiente.
Dinero que la persona debe, contado a su favor. Es anterior a todo esto. Felipe
pidió medirlo primero y arreglarlo aparte.

---

## 2026-08-19 — Un archivo suelto revirtió `fn_provisiones`, y el registro no lo vio

La pantalla Provisiones mostraba un «CTS total» que no era la suma de sus dos
ventanas: contaba otra vez la CTS ya depositada al banco por PLAME. En la fila
de Paola Cahuana eran **S/94.17 de más**.

**No tocaba ningún pago**, y eso se verificó antes de alarmar a nadie:
`cts_total` y `gran_total` solo los usa `provisiones/page.tsx`; el camino que
paga (`fn_grati_cts_periodo`) usa `cts_may`/`cts_nov`, que sí descuentan desde
la [`0158`](../supabase/migrations/0158_las_provisiones_descuentan_lo_depositado.sql).
Lo que se ensuciaba era la reserva y su CSV — el número que ve el contador.

### Lo que apareció al pedir el md5 de partida

Producción devolvió `9b6be5fa…` para `fn_provisiones`. **No era la 0196**, que
es la vigente en el repositorio: era, byte por byte, el cuerpo de la 0158 — dos
versiones atrás. Y `migraciones_aplicadas` decía que la 0160 (05/08) y la 0196
(08/08) estaban aplicadas.

Se midió en vez de explicarlo: se aplicó en el Postgres local el cuerpo de
**cada** versión histórica dentro de `BEGIN…ROLLBACK` y se comparó su md5. Solo
la 0158 coincide; ninguna otra se acerca.

Después se midió qué más de la 0196 seguía en pie. Las tres funciones del
cálculo por cese —`fn_grati_trunca_bruta`, `fn_cts_trunca`,
`fn_vacaciones_truncas`— estaban **correctas**, en su versión de la 0196. O sea:
la 0196 corrió entera, y después algo pisó **solo** `fn_provisiones`.

### La causa: `aplicar_0158.sql`, que llevaba la función entera dentro

`scripts/sql-manual/aplicar_0158.sql` contenía `fn_provisiones` con md5
`9b6be5fa…` — exactamente el que se encontró en producción. Pegarlo para rehacer
el libro de desembolsos revertía la función sin un error y sin un aviso, y no
tocaba las de cese, que es justo lo que se observó.

**Es la segunda vez con este mecanismo.** La primera fue `fn_planilla_calcular`
en agosto, y está contada en la cabecera de `dame-el-sql.sh`. Aquel día se
borraron cuatro `aplicar_*.sql` obsoletos; estos dos quedaron. Ya no:
`aplicar_0158.sql` y `aplicar_0160.sql` **se borraron**. Sus migraciones siguen
en `supabase/migrations`, así que no se perdió historia — solo la copia armada.

### Lo que se pegó

La [`0271`](../supabase/migrations/0271_el_total_de_cts_descuenta_lo_mismo_que_sus_ventanas.sql)
hace que `cts_total` reste lo mismo que sus ventanas, y **lleva sus cimientos
dentro** (las tres columnas y `fn_devenga`/`fn_devenga_algo`, idempotentes,
copiadas de la 0196 sin cambiarles un byte). Sin eso, pegar solo la función
sobre una base sin ellas la habría creado sin quejarse y la pantalla habría
reventado **al abrirla, no al pegarla**.

Aplicada y confirmada contra producción el 2026-08-19: las ocho comprobaciones
de md5 en verde. Al aplicarse, producción recibió además lo que la 0160 le hacía
a esta pantalla y no tenía — Catherine Pereyra deja de figurar con ~S/2.841 de
beneficios que no devenga.

### Lo que salió de tirar del hilo, el mismo día

Una auditoría en paralelo de la pantalla y de `fn_provisiones` (tres lentes, cada
hallazgo verificado por refutación) devolvió **nueve defectos confirmados**. Se
arreglaron los de arriba y estos:

- **`fn_provisiones` solo leía DOS de las cinco ventanas del libro.** Una
  gratificación o unas vacaciones pagadas por transferencia se anotaban en
  `desembolsos_beneficios` y no las restaba nadie. Medido: con S/700 anotados en
  `grati_s1`, la provisión no se movía de S/749.97 y seguía diciendo `pagada:
  false`. **Y esto sí llegaba al pago** —`fn_grati_cts_periodo` lee esos campos
  para proponer el bono al cerrar—, a diferencia del defecto de `cts_total`. La
  0158 lo dejó anotado como deuda conocida; la
  [`0273`](../supabase/migrations/0273_el_libro_de_desembolsos_vale_para_los_cinco_beneficios.sql)
  la paga, preguntando con `fn_beneficio_ya_depositado` (la de la 0163) en vez de
  con un `sum` propio.
- **El «Gran total» omitía la bonificación extraordinaria.** Se sumaba en el
  cliente como `grati_total + cts_total + vac`, sin `be_total`. Medido con una
  persona de S/1.500: pantalla S/2.010,12 contra base S/2.095,77. La reserva
  salía **corta**. Ahora la bonificación tiene columna propia y el total se lee
  de `gran_total`.
- **Un importe de exactamente 0 salía del CSV como texto `="0"`.** `SUMA` lo
  ignoraba sin daño, pero `PROMEDIO`, `CONTAR` y el orden numérico saltaban esas
  celdas. Afecta a las cinco pantallas que exportan, incluida la de planilla.
- **El céntimo del redondeo.** `gran_total` redondeaba la suma mientras las
  columnas redondeaban por separado, así que la fila no cuadraba por S/0.01 —
  justo la celda que alguien compara con las de al lado. Ahora el total suma las
  columnas **ya redondeadas**.
- **El hueco de la 0268** queda explicado en `scripts/hooks/huecos-conocidos.txt`:
  número reservado por otra sesión el 18/08 y nunca commiteado.

### Lo que la auditoría encontró y NO se arregló

Cuatro hallazgos confirmados que quedan pendientes, con su medición hecha:

- **Del 16 al 31 de diciembre, «Próximo pago» miente.** Pasado el pago del 15/12,
  el próximo desembolso cae en el año siguiente, pero el campo que la pantalla
  lee (`cts_may`) sigue siendo el de la ventana de ESTE año. Medido: el 20/12
  anuncia «S/325.03 · 15/05» cuando ese monto es de una ventana ya depositada. En
  el caso normal —CTS pagada entera— muestra «S/0.00» para todo el equipo esas
  dos semanas. Son 16 días al año, en pleno cierre de la reserva anual.
- **Sin asignación de salario vigente, la fila entera sale en S/0.00** junto a
  «12.0 días» de vacaciones acumuladas. Se lee igual que alguien a quien no le
  toca nada. Reproducido con tres personas idénticas salvo la fecha de vigencia
  del salario: S/1.686,66 · S/120,63 · S/0,00.
- **En noviembre y diciembre la CTS que se está devengando no aparece.** Las dos
  ventanas del año ya pasaron y la nueva (nov→abr) no tiene celda.
- **`fn_provisiones` ignora `asignaciones_salario.base_provision`,** que
  `fn_planilla_calcular` sí honra. La boleta reserva sobre una base y la
  provisión sobre otra.

### Y esa misma tarde: la tabla dejó de listar a quien no reserva nada

Felipe, mirando la pantalla: las locadoras y la gente en días de prueba no
tenían que estar ahí. La [`0274`](../supabase/migrations/0274_las_provisiones_solo_listan_a_quien_devenga.sql)
las saca. ✅ **Pegada el 2026-08-19**, y vuelta a comprobar contra
`migraciones_aplicadas` el 2026-08-20. El md5 de `fn_provisiones` pasó de
`e057765c…` (el cuerpo de la 0273, verificado ANTES de entregar el SQL) a
`84aae8bf…`, y de **25 personas activas la pantalla pasa a listar 20**.

**Es la vuelta atrás de una decisión que estaba escrita**, con su argumento, en
la prueba 127: «verlo en cero es una respuesta, que falte obliga a preguntarse si
se perdió por error». Lo que la tumbó fue la pantalla real: con media tabla en
cero, el cero dejó de ser una respuesta, y el cero de quien SÍ devenga y aún no
acumuló —alguien que entró esta semana— quedaba indistinguible del de quien no
devengará nunca. La preocupación de entonces se contesta en dos sitios: una línea
en la pantalla que dice a quién lista, y la prueba 211.

**El filtro pregunta por el devengo, no por el tipo de vínculo**, y esa es la
única parte delicada. `tipo_vinculo = 'planilla'` habría sido más corto y habría
borrado a la locadora con la gratificación encendida a mano —el caso que la 0196
existe para poder expresar—, dejando de reservar plata que sí se le debe. Una
fila solo desaparece cuando `fn_devenga_algo` dice que no devenga nada, o sea
cuando sus cinco columnas ya valen cero.

Medido antes de darlo por bueno, en local y dentro de `BEGIN … ROLLBACK`: las
filas que se quedan salieron idénticas campo por campo, la suma de la tabla no se
movió (S/ 2.137,84 antes y después, 16 filas → 13), y las tres que se fueron
valían 0.00 en las cinco columnas.

---

## 2026-08-17 — Disciplina no podía firmar nada, y el descargo previo pasó a ser política

Firmar una amonestación o una suspensión devolvía «Antes de firmar hay que
comunicar los cargos y dar el plazo de descargo (art. 55.2 del RIT)» **sin que
existiera forma de cumplirlo desde ninguna pantalla**. Tres memos parados —
Sasha, Mateo y Paola— con una persona trabajando un día en que debía estar
suspendida.

### La causa: media función sin cablear, seis días en producción

El commit `ae501ca` (11-ago) escribió `comunicarCargos()`, `valorarDescargo()`,
`plazoAbierto()` y `esGradual()` en `admin/disciplina/page.tsx` y **nunca las
llamó desde el JSX**. Su propio mensaje describía la cascada de botones que
nunca llegó a existir. La base empezó a exigir el trámite con la [`0212`](../supabase/migrations/0212_ninguna_sancion_sin_escuchar_antes.sql)
y la pantalla siguió mostrando «Firmar» siempre.

⚠️ **`typecheck` no dice nada de una función que nadie llama.** Cuatro funciones
muertas convivieron seis días con las pruebas en verde. Es el modo de fallo que
este repo no tiene cubierto: no hay pruebas de render, así que una pantalla que
compila puede no hacer nada. Cuando un cambio promete un botón, **hay que abrir
la pantalla y verlo** — se comprobó así, contra el Postgres local, y ahí saltó.

### Lo aplicado en producción hoy

| | |
|---|---|
| [`0266`](../supabase/migrations/0266_una_comunicacion_de_cargos_ya_ocurrida_se_puede_declarar.sql) | Registrar una comunicación de cargos **ya ocurrida** con su fecha real, motivo obligatorio y nombre de quien la declara. No adelanta el plazo: el de esa fecha sigue mandando. |
| [`0267`](../supabase/migrations/0267_el_descargo_previo_pasa_a_ser_una_politica_de_la_empresa.sql) | El descargo previo pasa de estar clavado en el código a `configuracion.disciplina_descargo_previo`. **Aplicada en `false`** por decisión de Gerencia General. |

Los memos: `T-01/0003` (Sasha) y `T-02/0004` (Mateo, suspensión el 18-ago),
firmados y entregados el 17-ago.

### La decisión de la política, y qué se expuso antes de tomarla

Gerencia General decidió firmar sin esperar el plazo, con el descargo recogido
verbalmente. Se expuso por escrito, con fuentes, y se sostuvo:

- **Res. 568-2021-SUNAFIL/TFL** extendió el debido proceso a las sanciones
  distintas del despido — el caso era exactamente una amonestación y una
  suspensión sin plazo de descargo.
- **Res. 810-2022-SUNAFIL/TFL**: sancionar sin plazo de descargos es **acto de
  hostilidad**, infracción muy grave del art. 25.14 del RLGIT. Pequeña empresa,
  tope 2026: 7.65 UIT ≈ **S/ 42,075**.
- El propio RIT (art. 55.2) anuncia que la omisión **invalida** la medida y la
  deja sin contar como antecedente para el inciso h) — el peldaño de un despido
  futuro queda discutible.

Se implementó como política y **no** borrando el candado: la regla sigue
escrita, revertir es `update configuracion set valor = 'true'` sin migración, y
**cada documento firmado así lo dice en su propio expediente**. Con la política
en `true` la función se comporta igual que la [`0228`](../supabase/migrations/0228_no_se_sanciona_con_un_reglamento_que_no_se_entrego.sql).

Lo que **no** cambió: el numeral 60.5 sigue frenando sin constancia del
Reglamento, y los guardas de firmante del art. 54.4 quedan igual. Si la clave de
configuración falta o trae un valor inesperado, **se exige**: una configuración
perdida no puede relajar una garantía en silencio (prueba `205`).

### La suspensión ya elige su día

La pantalla solo dejaba cambiar el **número** de días; la fecha la fijaba el
generador del borrador y no había dónde tocarla — `fn_expediente_set_suspension`
siempre aceptó la fecha, el panel no la exponía. Si la firma se retrasaba, la
sanción caía en días ya trabajados. Es lo que obligó a anular la `T-02/0001` en
julio y volvió a pasar hoy: la de Mateo estaba puesta para el 17, el día que
estaba trabajando. Ahora hay campo de fecha y un aviso en rojo cuando los días
ya empezaron.

### PENDIENTE

- **Paola Cahuana**: su amonestación sigue en borrador porque no consta la
  entrega del Reglamento. Se destraba entregándoselo y registrando la constancia
  en Normas — también vale el cargo en papel escaneado.
- **La comunicación de cargos no se genera sola.** Si algún día la política
  vuelve a `true`, entregarla sigue siendo trabajo a mano. Lo que evitaría el
  papeleo es que el sistema la imprima con los hechos ya medidos.
- **`fn_expediente_declarar_cargos_comunicados` (0266) quedó sin usarse hoy**,
  porque la política la dejó sin caso. Sigue siendo la salida buena si alguna
  vez se vuelve a exigir el plazo y una comunicación ya ocurrió.

### ⚠️ Una sesión paralela borró trabajo sin commitear, mientras se trabajaba en él

Se escribió, probó y verificó una migración `0267` distinta —cerrar el plazo de
un expediente concreto con motivo— y **otra sesión de este mismo worktree la
borró junto con su prueba, y renumeró la siguiente para ocupar su hueco**. No se
perdió nada porque se detectó en el acto, pero el archivo no estaba commiteado y
no había forma de recuperarlo del disco.

Es el riesgo que `CLAUDE.md` ya describe para el índice de git, ahora visto
sobre archivos: **lo que no está commiteado, otra sesión se lo puede llevar**.
La misma sesión reinició la base local dos veces en medio de una verificación.

---

## 2026-08-15 — «Lo mío» deja de ser un marcador, y dos migraciones para que lo sea

La pantalla que ve cada colaboradora pasó de mostrar sus horas a poder usarse:
sus turnos, sus objetivos del mes, sus permisos, lo que le tocaba contra lo que
hizo, y —lo que la cambia— **un botón para decir que un día no cuadra**.

### ⚠️ El aviso de firmas no le llegaba a quien es

`AcusesPendientes` —el banner que pide firmar la política salarial y el RIT— se
pintaba **solo dentro de `AdminNav`**, y el login manda a `/mio` a quien no tiene
panel. O sea que **la integrante, que es exactamente para quien se escribió, no
lo vio nunca.** Su propio comentario dice «una integrante que entra por primera
vez cae en el Dashboard», y eso dejó de ser cierto cuando existió `/mio`.

No es estética: la Ley 30709 obliga a informar la política salarial **y a poder
probarlo**, y el reglamento interno igual. Un acuse que no le llega a su
destinataria no prueba nada. Ya se pinta en `/mio`, lo primero de la pantalla.

### Lo aplicado en producción, con su md5 confirmado

| | |
|---|---|
| **0256** | `fn_faltas` gana la rama `pe.id = fn_persona_actual_id()`. Cada quien ve SUS faltas. Partió de `8887c5d1…` (la 0079) y quedó en **`c6a9ddc9ac8e1e8434c58b19ab71ebda`** |
| **0257** | `revisiones_pedidas` + cuatro funciones: pedir, retirar, atender y leer. Las cuatro con el md5 del repositorio, confirmado |

**Por qué la 0256 importa más de lo que parece:** una integrante se enteraba de
que el sistema le contó una falta cuando ya había una conversación encima — que
es justo cuando el marcaje ya no se puede arreglar. Y buena parte de las faltas
que este sistema detecta **no son faltas**: son días sin turno cargado. La
persona es la única que sabe qué pasó ese día. Dejarla verlo es el canal de
corrección más barato que tiene CAYLA.

Efecto medible el mismo día: un «18 de 23 días que te tocaban» era falso —cuatro
de esos cinco días eran permisos concedidos que `fn_faltas` no le devolvía—, y
con la 0256 el denominador baja a lo que de verdad debía.

### Lo que NO se abrió, y son decisiones

- **El expediente disciplinario.** `exp_select_propia` ya se lo permite, pero esa
  policy **no filtra por estado**: incluiría los BORRADORES. Avisarle a alguien
  de una sanción que nadie decidió entregar es peor que no avisarle de nada. Si
  algún día se abre, va filtrado a `firmado`/`entregado`.
- **El saldo de vacaciones.** Sale de un cálculo que acaba de tener un defecto de
  doble cobro en la trunca. **Lo registrado es un hecho; el saldo es una
  promesa.** Las vacaciones ya registradas sí se ven.
- **Dinero, en ninguna forma.** Se mantiene la decisión del 11-ago. Lo único que
  se añadió es la etiqueta «no remunerado» en un permiso — que es una condición
  que debería haber sabido al pedirlo, no una cifra.

### Un hallazgo que ahorró una migración

**`vacaciones` no es una tabla: es una VISTA** sobre `ausencias` (tipo
`'vacaciones'`, no anuladas) declarada con `security_invoker=true`. La RLS que
manda es la de `ausencias`, y `ausencias_select_propia` ya existía — cada quien
ya podía leer las suyas. Se iba a escribir una policy que no hacía falta.

Y el defecto que eso destapó: **una consulta directa a `ausencias` tiene que
llevar `anulada_at is null`**. La vista lo lleva dentro desde siempre; quien
consulte la tabla y lo olvide le dirá a alguien que su permiso está registrado
cuando ya lo dieron de baja — y es justo en lo que se fiaría para no volver a
presentarlo.

### ⚠️ DOS REGLAS DE MÉTODO, las dos aprendidas hoy y a golpes

**1 · El SQL para pegar NO se transcribe al chat. Nunca.** Se entrega con
`./scripts/dame-el-sql.sh <NNN>` y punto. Hoy, al pasar la 0257 por el chat,
acorté comentarios de cabecera para que cupiera en pantalla — y dos de ellos
vivían **dentro** del cuerpo de una función. Los comentarios dentro de `$$…$$`
**viajan al `prosrc`**: la migración entró, funcionó, y dejó dos md5 de
producción distintos a los del repositorio. Es la misma deriva que el 2026-08-08
dejó 22 funciones sin coincidir. Costó tres rondas cerrarla.

**Y no poner NADA MÁS COPIABLE en el mismo mensaje.** Dos veces seguidas, darle
la migración en el portapapeles y una consulta de verificación en el texto hizo
que copiara la segunda y perdiera la primera: pegó la consulta creyendo pegar la
migración. Para verificar: que vuelva a correr la consulta que ya tiene en el
editor, o mandarla en un mensaje aparte — o dejarla en el portapapeles con
`pbcopy` **cuando ya no haya nada más que pegar**, que fue lo que por fin
funcionó.

**2 · pgTAP corre como `postgres`, que SE SALTA LA RLS.** Una prueba que
consulte una tabla directamente para comprobar una policy no está comprobando
nada: hay que `set local role authenticated` antes y `reset role` después. La
prueba 198 falló por esto y **el fallo era del banco de pruebas, no del código**
— pero podría igual de fácil haber PASADO por el motivo equivocado, que es el
caso peligroso. Está escrito dentro del archivo.

### PENDIENTE de esta tanda

- **Objetivos de septiembre**: la pantalla ya los ofrece cargar con un enlace que
  llega con la persona y el mes puestos, pero **hoy casi nadie tiene checklist**.
  Es lo que Felipe decidió empezar.
- **Que alguien atienda las revisiones.** Salen primero en Incidencias, antes que
  cualquier aviso automático — a propósito: un aviso puede esperar, alguien que
  escribió «ese día sí vine» no. Si se dejan sin responder, la pantalla enseña
  que escribir no sirve, y eso no se recupera.

---

## 2026-08-15 — Desempeño del equipo, y lo que destapó: gente sin horario y turnos sin cargar

`/admin/horas` dejó de llamarse «Horas» y es **Desempeño del equipo**. La ruta no
cambió —hay enlaces vivos y romper una URL para cambiar un nombre no lo vale—
pero la pantalla sí: era una tabla de totales por persona y ahora es una
cuadrícula de **personas × días**, con el desempeño de cada una desplegable
debajo de su fila.

Lo que la motivó, en una frase de Felipe: *«dice Sandra 135 min tarde pero no
puedo ver los días en que pasó esa tardanza»*. Antes, para eso había que ir a
Equipo → persona → ficha → pestaña Desempeño. **Un resumen que no se puede abrir
hasta el día que lo produjo no sirve para conversar con nadie.**

### Las decisiones, para no reabrirlas

- **El día es la unidad, no la persona.** Cada fila termina en una franja de
  cuadritos, uno por día. Los patrones —siempre los lunes, siempre después de un
  descanso— aparecen solos porque los días están alineados en columnas.
- **Todo número lleva su denominador.** «50 h» no es bueno ni malo; «50 de 72 h»
  sí. Lo que le tocaba sale de `horarios_asignados` + `turnos`.
- **Los días con motivo NO entran en el denominador.** Salió midiendo: una
  integrante aparecía con «50.0 / 90.0 h» y cero faltas porque cuatro de sus doce
  días esperados eran ausencias justificadas. Parecía deber cuarenta horas que
  nadie le debe. **Un número que hace quedar mal a quien tenía permiso es el
  falso positivo que este sistema existe para no cometer.**
- **El orden mide gravedad, no cantidad.** Manda la PEOR tardanza del periodo, no
  cuántas: dos de siete minutos no valen lo que una de dos horas y cuarto. Las
  faltas siguen primero.
- **Las dos escrituras van por las RPC de Incidencias** (`fn_levantar_tardanza`,
  `fn_set_justificacion`). No hay una segunda forma de perdonar un día.

⚠️ **REGLA NUEVA: la cascada «qué le tocaba» vive en un solo sitio.**
`apps/web/lib/admin/jornada-esperada.ts` —turno del día → `horario_por_dia` →
`dias_laborables`—, con 26 pruebas en `tests/jornada-esperada.test.ts`. Ya había
una copia parcial y más vieja en `admin/correcciones/page.tsx`
(`calcularEsperado`, solo la hora de entrada); **unificarlas queda pendiente y no
se escribe una tercera.** Es el mismo patrón que produjo 35 copias de una
condición de permiso y 32 del huso horario de Lima.

### ⚠️ LO QUE LA PANTALLA DESTAPÓ, Y SON DATOS, NO CÓDIGO

Ninguna interfaz arregla esto. Son las dos cosas que hay que resolver para que
las cifras de asistencia signifiquen algo:

**1 · Hay gente activa sin horario ni turnos cargados.** En Central, **2 de 3**.
Para ellas el sistema no mide faltas, ni tardanzas, ni horas esperadas: sus horas
suman al total y aportan cero al denominador. El recuadro llegó a decir
«163 h de 90 h que tocaban» —el equipo trabajando el doble de lo debido— porque
el 90 era el horario de una sola. Ya se dice «de 90 h que tocaban a 1 de 3», pero
**eso describe el problema, no lo resuelve**. Quiénes son:

```sql
select s.codigo as sede, p.apellidos || ', ' || p.nombres as quien, p.fecha_ingreso, p.tipo_vinculo from personas p join sedes s on s.id = p.sede_base_id where p.estado = 'activo' and not exists (select 1 from horarios_asignados h where h.persona_id = p.id and h.vigente_desde <= fn_hoy_lima() and (h.vigente_hasta is null or h.vigente_hasta >= fn_hoy_lima())) order by s.codigo, p.apellidos;
```

**2 · Los turnos rotativos no se están cargando, y eso convierte las tardanzas en
ruido.** Los datos de una integrante de AQP en agosto: entró 11:10, 11:02, 16:30,
13:50, 14:15, 14:01, 14:01 y 12:13. El sistema marcó 130 min de salida
anticipada, 174, 49, y 135 de tardanza. **Los cuatro cuadran con un horario base
de 14:00–22:00 y 15 min de tolerancia** — o sea que están bien calculados. Pero
los días que entró 11:02 y 12:13 no son días en que se fue temprano: **son días
en que hizo otro turno, y ese turno no está en `turnos`.**

**Cuando todos los días medidos dan anomalía, lo que está mal no es la persona:
es la referencia.** La pantalla ya lo dice —columna «medido contra», ⚠ en cada
día medido contra el horario base, y un aviso que enlaza a Turnos en la semana de
ese día— pero **no se puede usar una de esas tardanzas en una conversación
disciplinaria hasta que los turnos se carguen.** Los días afectados:

```sql
select s.codigo as sede, p.apellidos || ', ' || p.nombres as quien, j.fecha, to_char(j.entrada_ts at time zone 'America/Lima', 'HH24:MI') as entro, j.minutos_tarde from jornadas j join personas p on p.id = j.persona_id join sedes s on s.id = p.sede_base_id where j.fecha >= '2026-08-01' and j.fecha <= fn_hoy_lima() and coalesce(j.minutos_tarde, 0) > 0 and not exists (select 1 from turnos t where t.persona_id = j.persona_id and t.fecha = j.fecha) order by j.minutos_tarde desc, j.fecha;
```

### PENDIENTE · los objetivos arrancan en septiembre

**Decisión de Felipe el 2026-08-14: empezar a aplicar los objetivos mensuales
desde el próximo mes.** El bloque de objetivos está en el desempeño de cada
persona, de solo lectura, y cuando no hay checklist cargado lo dice y ofrece
cargarlo — una sección ausente no enseña que falta algo. `/admin/objetivos`
aprendió a recibir `?persona=&anio=&mes=` para que el enlace «preparar los de
septiembre» llegue con la persona y el mes ya elegidos.

Hoy casi nadie tiene checklist. Eso es lo esperado, no un defecto.

### Un contador de la ficha que nunca dijo nada

`/admin/personas/[id]` muestra «Salidas anticipadas: **3 de 3 medidos**», y no
puede dar otra cosa: `fn_jornadas_extra` **solo devuelve las filas con minutos >
0**, así que «medidos» y «marcados» son siempre el mismo número. Se ve como una
proporción y es una tautología. **Pendiente de arreglar en la ficha** — la
pantalla nueva no muestra ese denominador falso.

---

## 2026-08-14 — el barrido del pago del 28, y cuatro alarmas que no eran

**El cierre del 28/08 NO está bloqueado.** Comprobado contra producción, no
deducido: las **29 personas cuadran** contra `chk_foto_cuadra`, y el periodo
suma **S/ 15,917.11**.

Salió de una auditoría de 13 agentes en dos fases —nueve recalculando cada
concepto desde la norma sin mirar el código, cuatro intentando refutar lo que
los primeros encontraran—. 53 hallazgos, 45 reproducidos con cifras. Y de ahí,
lo que sobrevivió al contraste con los datos reales cabe en media página.

### Lo que se arregló y ya está en producción

| | |
|---|---|
| **0248** | La foto del pago aprende la retención de 4ta. La 0245 le restó un término al total sin ampliar `chk_foto_cuadra`: el día que se configurara una retención, `fn_planilla_congelar` abortaba y **no se congelaba nadie**. Estaba armado y sin estallar — cero personas la tenían configurada |
| **0244** | Los cuatro defectos de la 0243, que llevaba desde el 14/08 corriendo con ellos. El peor atascaba el cierre con un solo cese a mitad de periodo |
| **0209** | La versión corregida reemplazó al borrador: el cese del mismo día que dejaba a la persona en S/0.00, y el sueldo fijo que cobraba el periodo completo |

⚠️ **La 0248 es la TERCERA vez que pasa lo mismo** — 0127 con movilidad,
educación y pensión; 0201 con el sobretiempo; esta con la retención. El término
del total y la columna de la foto viven en dos sitios y nada obliga a tocarlos
juntos. Por eso la prueba **189** no vigila la retención sino **el patrón**:
falla si aparece cualquier columna `monto_*` fuera del candado, en el `db reset`
y no un 28 por la noche.

### Lo que queda, y son datos, no código

- ~~**Dante Ramal** — cobraría el mes completo por 16 de 31 días~~ — ✅ **no era
  un problema, y la aclaración de Felipe lo invirtió entero.** El sistema decía
  `fecha_ingreso = 13/08` con un tramo de salario que arrancaba el **29/07**, y
  yo propuse corregir el tramo. Estaba al revés: **Dante ya trabajaba desde
  antes; el 13/08 es el día en que Felipe lo dio de alta en el sistema.** El dato
  malo era la fecha de ingreso.

  Con `fecha_ingreso = 2026-07-29` —ya corregida en Equipo— estuvo el periodo
  completo, así que **el mes completo es lo correcto y los ~S/315 no existen**.
  Verificado además: no tiene horario asignado, así que el motor de faltas no le
  cuenta ni un día ausente pese a no marcar nunca. Es `rxh` con `sueldo_fijo`.

  ⚠️ **DECISIÓN DE FELIPE, PARA QUE NADIE LA «ARREGLE» DESPUÉS:** a Dante se le
  pagó por fuera antes de entrar al sistema, y **eso no se carga — se cuenta
  desde ahora**. El sistema es nuevo y no vale la pena complicarlo hacia atrás.
  De `fecha_ingreso` cuelga el reloj de su CTS, su gratificación y sus
  vacaciones: quien mire su devengado dentro de unos meses va a ver una
  antigüedad más corta de la real y va a querer corregirla. **No es un dato mal
  cargado: es una decisión.**

  Y una nota para cuando se revise el vínculo de los locadores con el contador:
  **Dante es locador con monto fijo mensual**, que es exactamente el indicio de
  laboralidad que ya está señalado para Carlos, Catherine y Claudia. Entra en esa
  misma lista; no se quedó fuera por haberse dado de alta después.
- **Kerin Guevara** — ingresó el 12/08 sin **régimen de pensión** (no se le
  retiene nada, y CAYLA es agente de retención) y **sin horario vigente** (no se
  le miden faltas ni tardanzas). Las dos se cargan desde las pantallas.

### ⚠️ UN CABO SUELTO QUE HAY QUE VOLVER A MEDIR EL 28

**Felipe apareció con un descuadre de +S/110.00 —exactamente 11 días × S/10 de
movilidad— en dos consultas consecutivas, y desapareció solo minutos después**
sin que nadie tocara nada conocido. Tiene `cobra_movilidad = false` por la 0166,
y la tarifa general de producción vale **S/10** (en el repositorio vale 0.00).

No hay explicación: `fn_planilla_calcular` aplica `cobra_movilidad` **en los dos
sitios**, el concepto (línea 376) y el total (línea 514). Se verificó leyendo el
cuerpo vivo.

**Instrucción concreta: correr `va_a_poder_cerrarse.sql` el 28, justo antes de
congelar.** Es una sola sentencia y responde en dos segundos. Si el descuadre va
y viene, ese es el único momento en que importa — una vez congelado, la foto se
queda con lo que hubiera.

### Dos scripts nuevos, para volver a usarlos cada mes

| Ruta | Qué responde |
|---|---|
| [`antes_de_cerrar_el_mes.sql`](../scripts/sql-manual/antes_de_cerrar_el_mes.sql) | Once chequeos en una tabla: si existe el periodo, si faltan feriados, jornadas mudas, movilidad excluida, quién no tiene pensión, ausencias pagables en cero, entradas y ceses, salarios y horarios vigentes |
| [`va_a_poder_cerrarse.sql`](../scripts/sql-manual/va_a_poder_cerrarse.sql) | Si el cierre va a poder completarse. **Una sola sentencia que SIEMPRE devuelve una fila**, porque cero filas se lee igual que «todo bien» |

**Ninguno de los dos llama a una función de diagnóstico, y es deliberado.**
`fn_liquidaciones_pendientes`, `fn_contratos_desnaturalizados`,
`fn_dias_por_revisar`, `fn_ausencias_subsidio` y `fn_contratos_por_vencer`
llevan dentro `fn_es_admin_o_lider()`, y en el SQL Editor la sesión es
`postgres`, que no tiene fila en `personas`. **Devuelven cero filas, no un
error.** Van contra las tablas para no poder caer en eso.

### Las cuatro alarmas que no eran, y qué enseñan

Ninguna llegó a aplicarse porque todas se intentaron reproducir antes. Quedan
escritas para no volver a levantarlas:

| Se dijo | La verdad |
|---|---|
| «Diez ausencias se pagarán en S/0.00» | Todas de tipos con `paga = false` —permiso personal, salud sin documento, otro— más unas vacaciones de un locador, que no las cobra desde la 0186. **S/0.00 es su resultado correcto** |
| «Diez jornadas mudas pagarán cero» | Eran todas **del día en curso**: gente trabajando con su jornada abierta. Al volver a correrlo un rato después el número bajaba solo, mientras la gente se iba a casa |
| «La movilidad excluida atasca el cierre» | El código **sí** aplica `cobra_movilidad` en los dos sitios. Reproducido: el cierre pasa |
| «Veinte personas descuadran» | La consulta buscaba `descuento_pension` —el nombre de la COLUMNA— cuando la clave del JSON es **`descuento_afp`**. Restaba cero, y descuadraba todo el que tuviera AFP, en ~10 % |

**El patrón de las cuatro es el mismo: afirmar por la forma en vez de medir.** Y
las cuatro se cazaron igual — intentando reproducirlas. La regla que ya estaba
escrita en este archivo, otra vez: *medir contra la base antes de proponer*.

Y una que vale por sí sola: **la fórmula de un candado no se escribe de memoria,
se copia del sitio donde es verdad.** La de `chk_foto_cuadra` se saca del
`insert` de `fn_planilla_congelar`, que es quien mapea cada clave del JSON a su
columna. Ahí se ve que `descuento_pension` se llena con `descuento_afp`.

---

## 2026-08-14 — la retención de cuarta categoría, y diez locadores donde había tres

### El sistema ya calcula el 8 % de un recibo por honorarios ([`0245`](../supabase/migrations/0245_la_retencion_de_cuarta_deja_de_hacerse_a_mano.sql))

Hasta hoy no existía: la única forma de reflejarla era escribir un movimiento de
tipo `descuento` a mano cada mes, con el 8 % calculado fuera del sistema.

Dos columnas en `personas` —`retencion_4ta` y `constancia_4ta_hasta`—, los dos
parámetros en `parametros_laborales` con su sustento, el cálculo dentro de
`fn_planilla_calcular`, la línea en la boleta, el aviso en la pantalla de
planilla y las dos columnas en el CSV que usa el contador. Se escribe por
`fn_set_retencion_4ta`, que valida el vínculo y audita.

**Las tres puertas, y por qué no alcanzaba un booleano.** El caso que lo pidió
—el recibo del contador externo— es de S/652.17, o sea POR DEBAJO del tope de
S/1,500: CAYLA no estaba obligada a retener. Retiene porque **el prestador lo
marcó «Sí» al emitir**, que es una casilla que decide el emisor y no el pagador,
y la marca porque factura a muchas empresas, se pasa del límite anual de la
suspensión y prefiere adelantar el 8 %.

- `NULL` → no se retiene. Es como nace todo el mundo, y por eso pegar la 0245 no
  movió un céntimo de nadie.
- `automatica` → la regla del art. 74 de la LIR: 8 % solo si el pago del mes
  **supera** el tope. En S/1,500.00 exactos no se retiene; en S/1,500.01 sí.
- `siempre` → 8 % sea cual sea el monto.
- La constancia del F.V. 1609 manda sobre las tres mientras esté vigente. Dura el
  año calendario: cuando vence, el modo vuelve a mandar.

**Y lo que CAYLA paga de más no es la retención.** El honorario cargado es el
BRUTO (652.17): de ahí 600 van a la persona y 52.17 a SUNAT a su nombre. Lo que
la empresa absorbe por haber pactado un neto es el *gross-up* —S/52.17 al mes,
S/626 al año— y ya está dentro de esa cifra. Bajar el honorario para esquivar la
retención pierde más de lo que ahorra: la retención se le acredita a la persona
contra su impuesto anual, el honorario recortado no vuelve.

### Un locador con monto fijo cobraba S/0.00, y la boleta lo llamaba «por horas»

Dos cosas distintas que salieron al configurar el primer caso real:

1. **Quien cobra un monto fijo y no marca nunca sale en S/0.00.** Su pago se
   calcula por horas registradas. La pieza que faltaba no era la retención sino
   `sueldo_fijo`, que **no se puede marcar desde ninguna pantalla** — va por SQL,
   igual que `en_planilla`.
2. **Y entonces la boleta decía «Honorarios por las horas prestadas (0 h) ……
   S/ 652.17».** Los números bien, la etiqueta mal, en un papel que se le entrega
   a alguien externo y que además describe el acuerdo al revés. La
   [`0250`](../supabase/migrations/0250_la_boleta_no_le_dice_por_horas_a_un_monto_fijo.sql)
   hace que `sueldo_fijo` viaje en el JSON para poder distinguirlos. No mueve un
   céntimo.

### ⚠️ Son DIEZ los que cobran por honorarios, y este archivo decía tres

La sección [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado)
nombra a tres, confirmados el 2026-08-07. La consulta devuelve diez. No se sabe
cuántos están activos ni cuántos pasan el tope sin mirar los datos, así que la
lista no va acá — va la consulta que los encuentra sola:

```sql
select p.apellidos || ', ' || p.nombres as quien, p.estado, case when p.sueldo_fijo then 'monto fijo' else 'por horas' end as como_cobra, s.salario_mensual_soles as honorario, t.valor as tope, case when p.estado <> 'activo' then 'cesado — no configurar' when s.salario_mensual_soles is null then 'sin honorario asignado' when p.sueldo_fijo and s.salario_mensual_soles > t.valor then 'PASA EL TOPE todos los meses' when p.sueldo_fijo then 'no llega al tope' else 'varia mes a mes: Automatica' end as que_hacer from personas p left join lateral (select a.salario_mensual_soles from asignaciones_salario a where a.persona_id = p.id and a.vigente_desde <= fn_hoy_lima() and (a.vigente_hasta is null or a.vigente_hasta >= fn_hoy_lima()) order by a.vigente_desde desc limit 1) s on true cross join lateral (select pl.valor from parametros_laborales pl where pl.clave = 'retencion_4ta_tope' and pl.vigente_desde <= fn_hoy_lima() and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima()) order by pl.vigente_desde desc limit 1) t where p.tipo_vinculo = 'rxh' order by p.estado, p.apellidos;
```

**PENDIENTE · decidido el 2026-08-14: no se configura a nadie más por ahora.**
Solo está puesto el contador externo (`siempre`). El resto queda en NULL y la
pantalla de planilla marca en ámbar a quien pase el tope sin configurar — que es
lo que va a poner los nombres reales sobre la mesa. **Lo que hay que preguntarle
al contador antes de tocar a nadie: quiénes tienen constancia de suspensión
vigente.** Con S/1,800 al mes nadie llega al límite 2026 de S/48,125 anuales, así
que la mayoría calificaría — y con la constancia cargada el sistema deja de
retener solo, sin que nadie pierda plata.

### El agujero que dejó la 0245, cerrado el mismo día por otra sesión ([`0248`](../supabase/migrations/0248_la_foto_del_pago_aprende_la_retencion_de_cuarta.sql))

La 0245 le restó un término nuevo al total y no amplió `chk_foto_cuadra`, que
exige que el total sea la suma exacta de once columnas conocidas. **En cuanto
alguien tuviera retención configurada, «Marcar como PAGADO» habría fallado para
las treinta personas del periodo**, no solo para el locador retenido: el cierre
del mes se atasca entero. Estuvo abierto media hora y el periodo sigue
provisional, así que no llegó a morder. Vale como recordatorio de que una prueba
del cálculo no es una prueba del cierre.

---

## 2026-08-14 — una marca que la base rechazaba, y las que quedaron presas

### El aviso «2 sin registrar» del terminal tenía razón, y no era grave

Salió mirando el terminal: un aviso rojo que aparecía «con frecuencia». Lo pinta
el contador de marcas **apartadas** — las que el servidor rechazó seis veces y
la cola dejó de reintentar, guardadas en el IndexedDB de ese navegador.

**Las dos eran de Felipe, del 13-ago a las 22:02 y 22:22, las dos
`salida_final`.** La salida entró bien a las 22:35:42 y la jornada quedó cerrada
en 9.81 h, así que **no se perdió nada y no hubo efecto en planilla**. Y de paso
quedó comprobada la fórmula contra producción: 12-ago 11.32 − 1.23 = 10.10 ✅ y
13-ago 13.06 − 3.25 = 9.81 ✅.

**Por qué fue negativo a las 22:02 no se puede reconstruir, y no hace falta
intentarlo otra vez:** tres marcas de esos dos días son `admin_correccion`,
puestas después. El estado que lo produjo ya no existe — con los datos de hoy esa
misma salida daría +9.25 h. Casi seguro fue un estado transitorio de las pruebas
de la 0240 esa noche.

### Lo que sí era un defecto: el CHECK tumbaba el marcaje, no la jornada ([`0249`](../supabase/migrations/0249_una_salida_real_siempre_se_puede_registrar.sql))

`chk_horas_no_negativas` (0095) frenaba el `insert` en `jornadas` — bien —, pero
ese insert cuelga del trigger de `marcajes`, así que la excepción subía y
**reventaba el insert del marcaje**. El efecto real no era «esta jornada no se
guarda», era **«esta persona no puede marcar su salida»**: el terminal se la
seguía ofreciendo toda la noche y cada intento acababa apartado. Basta una
corrección con la hora mal tecleada para llegar ahí.

Ahora el negativo se guarda como `null` —«no se sabe cuánto», no «trabajó
cero»— y el día queda sellado en `pendiente_revision`. **El sello no es un
extra:** la planilla lee `coalesce(horas_trabajadas, 0)`, así que sin él el
arreglo habría cambiado una marca perdida a gritos por un descuento en silencio.
El CHECK no se toca.

**⚠️ Y el md5 de partida de esa función NO SE TOMÓ.** Se pegó antes de pedirlo a
producción, y `create or replace` ya había reescrito el cuerpo cuando se fue a
buscar. El de llegada (`c50fa2ed…`, idéntico al local) **no lo sustituye**: sale
igual partas de donde partas, así que no prueba de qué versión se partió. Lo que
sostiene que producción estaba en la 0240 es indicio, no garantía — el error que
rechazaba las salidas era exactamente su comportamiento. La cabecera de la
migración lo dice con todas sus letras.

### PENDIENTE · una marca apartada no la puede ver nadie

Esto sigue abierto y es la mitad que falta:

- **El aviso no se apaga nunca.** Nada borra ni recupera una apartada. Las dos
  del 13-ago van a seguir contando en ese Safari para siempre. Un aviso
  permanente en la pantalla que mira todo el equipo deja de leerse en tres días.
- **Dice «avisa a tu encargada» y la encargada no tiene dónde mirar.**
  `obtenerDescartadas()` solo se usa para contar; no hay pantalla que diga de
  quién es la marca, de qué hora ni qué error dio.
- **Viven en un solo navegador.** Desde el panel no se ven. El día que esto le
  pase a alguien en una sede, nadie se entera hasta que alguien mire la Mac mini.

La 0249 impide que el caso se repita por esta causa; no recoge las que ya
cayeron, ni las que caigan por otra.

### El cierre del 28 estaba bloqueado, y por una línea ([`0252`](../supabase/migrations/0252_el_cierre_deja_de_caerse_por_quien_no_cobra_movilidad.sql))

El término de movilidad del `total` no aplicaba `cobra_movilidad`; el concepto
`monto_movilidad` sí, desde la 0166. La boleta imprimía S/0.00 y el pago la
cobraba igual. Medido: **descuadre de 16.00** con tarifa de S/8 y dos días.

Y no era «una boleta descuadrada». `fn_planilla_congelar` inserta las ~30 filas
en UNA sentencia, así que la que rebota tumba la sentencia entera: **una persona
bastaba para que el 28 no cerrara para nadie**, con un error de CHECK que no la
nombra. Aplicada y confirmada en producción.

Es el tercer caso idéntico en una semana —0242 asignación familiar, 0245
retención de cuarta, 0252 movilidad— y el patrón ya no admite duda: **un
concepto vive en DOS sitios del JSON, el suyo y el término del `total`, y tocar
uno solo deja la boleta diciendo una cosa y el pago haciendo otra.** Antes de
tocar cualquier concepto, buscar sus dos apariciones.

### El descanso médico se pagaba en cero ([`0254`](../supabase/migrations/0254_el_descanso_medico_deja_de_pagarse_en_cero.sql))

**`fn_planilla_calcular` no leía la tabla `ausencias`.** Ni una vez. Las
vacaciones que sí se pagan (0177) salen de una tabla distinta, `vacaciones`. De
los cuatro tipos que `tipos_ausencia` declara pagables, la planilla pagaba uno.

La 0254 conecta **solo `descanso_medico`**, con el tope de 20 días del RIT
art. 31 f). Tres decisiones que se rompen fácil y ahora tienen prueba (195):

- el **tope** se cuenta en días CALENDARIO (así los cuenta EsSalud) y lo que se
  **paga** son días LABORABLES (pagar un domingo sería pagar de más);
- un día vale el promedio de lo pagado por día trabajado, **con respaldo**: sin
  días marcados el promedio sería 0/0 y quien pasó el mes entero enfermo cobraría
  cero — el mismo defecto con otra cara y en el caso más grave;
- **un día que ya paga por otra vía no se paga dos veces**. Salió solo: el
  descanso empezaba en Fiestas Patrias.

Va DENTRO de `pago_base`, como las vacaciones, y por eso NO toca
`chk_foto_cuadra` ni `fn_planilla_congelar`.

**`licencia_con_goce` sigue pagando cero, y es decisión** (va por
`movimientos_planilla`, la 0247 lo dice en su cabecera). **La maternidad ya no:**
la conectó la **0262** — escrita y probada el 2026-08-15, **aplicada en
producción el 2026-08-17**. La
prueba 187 fija por escrito que las dos reglas son distintas y no se pueden
igualar: el descanso médico cuenta días laborables porque es sueldo, la
maternidad cuenta días calendario porque es subsidio.

### Le vaciaron el horario por estar enferma, y eso le anuló el pago de la baja

**RESUELTO el 2026-08-14** con
[`restituir_horario_de_chiara.sql`](../scripts/sql-manual/restituir_horario_de_chiara.sql).
Aplicado y comprobado: su descanso médico pasó de **1 día pagado a 4** (~S/30 →
~S/122). Hay respaldo en `respaldo_horarios_chiara_20260814`.

El círculo, que es lo que hay que recordar: se enfermó, **le vaciaron el horario
mientras estaba de baja** (45 h/semana → 28.5 el 26/07 → 6 h, solo sábado, el
27/07), y `fn_planilla_calcular` mira ese horario para saber qué días le tocaba
trabajar. Respondía «solo el sábado». **La ausencia provocó el cambio de horario
y el cambio de horario anuló el pago de la ausencia.**

⚠️ **REGLA: una baja se registra como AUSENCIA, nunca tocando el horario.**
Vaciarlo hace tres cosas a la vez y ninguna se ve — le quita el pago de la baja,
apaga sus faltas y apaga sus tardanzas.

Dos cosas medidas que no son evidentes:

- **La corrección empieza el 29 aunque el vaciado empiece el 26.** Los días 26,
  27 y 28 de julio no tienen ausencia que los justifique y caen en el periodo
  ANTERIOR: devolverle el horario desde el 26 le abriría tres faltas dentro de un
  periodo cerrado.
- **Cerrar un tramo no lo saca del cálculo.** El horario se elige con
  `vigente_desde <= el_dia order by vigente_desde desc limit 1`, e **ignora
  `vigente_hasta`**. Hay que cambiar el contenido del tramo, no cerrarlo. Quien
  lo cierre creyendo que basta va a dar por hecha una corrección que no ocurrió.

**El barrido encontró un segundo caso** —Melany Enrriquez, de 35 h a 6 durante un
permiso personal de un mes— que **no cuesta dinero**, porque el permiso personal
no paga en ningún caso, pero confirma que el hábito no es de una sola persona. La
consulta que los encuentra está en el commit del script.

**PENDIENTE, decidido y sin escribir:** que un día de baja valga la **jornada
pactada** (7.5 h para Chiara, de sus propios datos: 45 h / 6 días) en vez del
promedio de lo que alcanzó a marcar enferma. La llevaría de ~S/122 a ~S/176 y
aplicaría a todos. Y una columna `motivo` en `horarios_asignados`, que hoy no
tiene dónde decir por qué existe un tramo. md5 de partida de
`fn_planilla_calcular` el 14-ago: `19eb593a757e0b7480b6a1dc99d7f8c9`.

### PENDIENTE · Chiara: seis días más que dependen de un papel, no del código

Su `descanso_medico` del 29/07→03/08 (dengue, **con certificado**) ya lo paga la
0254: cuatro días, ~S/122.

Lo que queda es **`salud` 04/08→09/08, vigente y SIN documento**. El sistema paga
cero y **eso es correcto** — no hay defecto que arreglar. Pero el bloque anulado
que ocupaba esas fechas decía «en reposo médico» y el certificado del dengue
termina el 03/08, justo el día antes. **Falta mirar hasta qué fecha llega el
certificado ya subido**: si cubre hasta el 09, la ausencia está mal clasificada y
son otros ~S/122 suyos; si solo llega al 03, se queda como está y no se vuelve a
levantar.

### Dos avisos del cierre que gritaban por lo normal

El chequeo devolvió `💸 14 día(s) que pagarán CERO` un jueves a las tres de la
tarde: **eran trece personas en su puesto**. Contaba las jornadas abiertas de
HOY. Se comprobó de la forma más elocuente — al recorrerlo un rato después el
número había bajado a 10 solo, mientras la gente se iba a casa. Ninguna era de
un día pasado.

Y el de movilidad se disparaba con solo existir alguien con
`cobra_movilidad = false`: con la 0252 puesta esa persona sigue existiendo y ya
no hay riesgo, así que **el 🚫 habría quedado encendido para siempre**. Ahora
mide el defecto —que el filtro aparezca dos veces en la función— y no su proxy.

**La regla que sale de las dos:** un semáforo que no se apaga nunca no es un
semáforo, y un aviso que grita por lo normal se desactiva a la semana. Las
exclusiones se aplican ANTES de contar.

---

## 2026-08-13 — el expediente de Mateo, y la 0213 que ya no se puede pegar

**LO QUE TENÍA FECHA, Y YA PASÓ.** Hubo una imputación de cargos entregada y
abierta (T-03/0001-2026-CAYLA, entregada el 10-ago), con descargo venciendo el
domingo 16 y consulta al laboralista pedida para el lunes 17.

✅ **Las dos preguntas están resueltas y no hay que volver a enviarlas.** Las
contestan dos migraciones, y ahí es donde vive el razonamiento completo:

- el escalón saltado → [`0246`](../supabase/migrations/0246_una_imputacion_prematura_no_tapa_el_escalon_que_falta.sql)
- el descargo previo del art. 19.3 → [`0267`](../supabase/migrations/0267_el_descargo_previo_pasa_a_ser_una_politica_de_la_empresa.sql)

Lo que queda vivo de esta sección es el relato de POR QUÉ pasó, que es lo que
impide repetirlo. El expediente en sí ya no tiene plazo corriendo.

Se emitió **saltándose el escalón d) del art. 19.2 del RIT** — la segunda
suspensión. El defecto era del generador, que tenía tres peldaños en vez de
cuatro; lo corrigió la 0232 y ya está en producción, pero el papel entregado
salió con la versión anterior.

Y leyendo el Reglamento apareció algo mayor: el **art. 19.3** exige dos días
hábiles de descargo **antes** de imponer la medida, con el documento retenido en
borrador — y advierte que su omisión «invalida la medida, que en tal caso no se
computa como antecedente ni sirve de peldaño». Si el orden importa, no afecta
solo al último escalón.

Las dos preguntas están escritas para enviarse en
[`disciplina-tardanzas-faltas/10-consulta-al-laboralista.md`](disciplina-tardanzas-faltas/10-consulta-al-laboralista.md),
y lo que hay que mirar cuando llegue el descargo, en el
[`09`](disciplina-tardanzas-faltas/09-evaluar-un-descargo.md).

**Lo investigado, para no repetirlo:** la ley (art. 25 h) usa el plural
«amonestaciones escritas y suspensiones» pero **no fija un número**. Lo que
obliga a dos es el RIT propio, que es más estricto a propósito — y el empleador
queda obligado por el reglamento que aprobó.

**⚠️ LA 0213 NO SE PUEDE PEGAR, NUNCA MÁS.** Comprobado ejecutándola: su
`fn_tardanza_escalon` devuelve cinco columnas y la viva devuelve seis, así que
Postgres aborta con «cannot change return type of existing function» y no entra
nada. Su mitad útil —`fn_expediente_generar_falta`— entró por la **0237**. El
número 213 sigue sin anotar en `migraciones_aplicadas` **a propósito**: no se
aplicó y el registro tiene que seguir diciéndolo.

**El reloj de las Mac mini ya no es un punto ciego** (0230). Medido en
producción: **4 segundos** de desfase máximo en siete días, latencia de red
incluida. El umbral de aviso está en 120 s, treinta veces por encima. Es seguro,
no reparación.

**Y una regla de método que costó tres errores en una sola sesión:** grepear una
cadena en el cuerpo de una función NO mide la regla. `suspension_previa_dias`
vive en el `returns table(...)`, que no forma parte de `prosrc`; `sueldo_fijo` se
comprueba un nivel más abajo, en `fn_expediente_crear_borrador`; y
`fn_auto_cierre` mira el periodo pagado a través de un helper. Las tres veces la
respuesta correcta salió de preguntarle a la base qué hace —`pg_get_function_result`,
llamar la función, reproducir el caso— y no de buscar un texto.

### El panel ya puede volver a invitar a quien nunca entró

`/admin/cuentas` daba por resuelta a una persona en cuanto GoTrue aceptaba el
envío: `invitar` enlaza el `auth_user_id` ahí mismo, y con eso desaparecía de la
lista de invitables **aunque el correo se hubiera perdido en spam y ella no
hubiera hecho nada**. No había forma de reenviarle nada desde la pantalla.

Ahora hay una sección **«Volver a invitar — todavía no han entrado»**, con envío
de a una o en tanda. Quién sale ahí se lee de `auth.users.last_sign_in_at`: en
null significa exactamente «no abrió el correo», porque aceptar la invitación
**es** iniciar sesión — el enlace la deja adentro para que ponga su clave.

**Y son dos correos distintos, medido contra el GoTrue local:**

| A quién | Qué se le manda | Por qué |
|---|---|---|
| Invitada que no aceptó (sin confirmar) | la invitación otra vez | GoTrue reinvita sin problema: mismo usuario, `invited_at` renovado |
| Cuenta creada a mano (confirmada) | el enlace de «recuperar acceso» | la invitación responde **422 `email_exists`**; ese camino está cerrado |

La tanda va con una pausa entre correos y **se corta sola** al llegar al tope por
hora del proyecto, diciendo quiénes quedaron pendientes. Mandarlos todos de golpe
no llega antes y convierte un tope en veinte errores.

⚠️ **Lo que hay que comprobar en el panel de Supabase antes de disparar:** que
`https://cayla-dynamic.vercel.app/**` esté en *Authentication → URL
Configuration → Redirect URLs*. Si no está, el enlace **no falla** — cae en el
Site URL, o sea en la raíz, y la persona termina en el login sin clave y sin
nada que le diga qué hacer. Se lee igual que un correo que no funcionó. En local
pasaba exactamente eso hasta que se agregó a `additional_redirect_urls` en
`supabase/config.toml`.

*(Y un aviso para quien corra las pruebas: `scripts/seed-dev.mjs` deja
`100_una_tienda_no_es_una_oficina` fallando en sus pruebas 8 y 9. Con
`npx supabase db reset` antes, las 953 pasan.)*


---

## 2026-08-10 — un terminal sin dueño, y un diseño de plata que se cayó al medirlo

### El terminal ya no puede quedarse sin dueño ([`0202`](../supabase/migrations/0202_un_terminal_activo_sin_dueno_deja_de_poder_existir.sql))

El guard que impide que una sesión se haga pasar por un terminal son **tres
condiciones unidas por AND** dentro de `fn_registrar_marcaje`. Con
`terminales.auth_user_id` en null la segunda es falsa, el AND entero es falso y
**no se lanza nada**: cualquier sesión con login podía registrar marcas a nombre
de otra persona, en cualquier sede, y la planilla las paga. Medido:
`anon` no puede ejecutar la función, `authenticated` sí — o sea que no hacía
falta ser admin ni encargada.

**El esquema fabricaba ese estado por su cuenta, y por dos caminos:**

- `activo` tiene **default `true`**, así que el insert natural —
  `insert into terminales (sede_id, nombre_dispositivo)` — nacía activo y sin
  dueño. El camino cómodo era el peligroso.
- La FK es **`ON DELETE SET NULL`**. Borrar en Auth la cuenta de un terminal no
  lo desactivaba: le ponía el dueño en null y lo dejaba activo. La puerta se
  abría sola, sin que nadie tocara nada. Esto no estaba en el catálogo.

El candado va en la TABLA, no en la función — la lección de la 0180. Y cierra el
hueco entero: cuando la función llega al guard, la fila ya se buscó
`where id = p_terminal_id and activo`, así que con el CHECK `auth_user_id` no
puede ser null ahí. **Aplicada y confirmada**; los tres terminales de producción
tenían dueño, así que esto no tapó un agujero abierto: **impide el próximo, que
es el terminal de Central el día que se cargue.**

**NO se reescribió `fn_registrar_marcaje`** para dejar el guard como
`is distinct from`, que es la forma correcta por doctrina. Son 129 líneas y es la
única puerta de escritura del sistema; el 08-08 se vio que 22 funciones de
producción no coincidían con el repositorio. Queda pendiente, y va después de
pedir el cuerpo de producción.

⚠️ **Y dejó una lección de método:** un CHECK nuevo **rompe los montajes de
cualquier prueba que fabrique el estado que prohíbe**. Rompió tres (110, 147,
149) y CI salió en rojo. El hook de pre-push corre `typecheck` y las pruebas de
interfaz, **no las pgTAP** — esas solo corren en CI. Antes de empujar un CHECK,
un `grep` de treinta segundos por `supabase/tests`.

### Dos hallazgos del catálogo son FALSOS desde la 0138

`hallazgos-abiertos.md` lista **C12·A16** (`fn_registrar_marcaje` sin candado de
periodo pagado) y **A3** (`fn_auto_cierre` reescribe periodos pagados) como los
dos más graves que quedan vivos. **Medidos contra el esquema de hoy, los dos son
falsos**, y el daño estaba tapado una capa más abajo:

- `fn_recalcular_jornada` **sí** lleva el candado desde la 0138, y se **sale en
  silencio en vez de lanzar**, a propósito: lanzar abortaría el INSERT y el
  terminal acabaría descartando una marca REAL tras seis reintentos.
- `fn_auto_cierre` solo escribe en `marcajes` y `alertas` — nunca en `jornadas`
  directo—, así que pasa por el mismo trigger y queda igual de tapado.

Lo que sí quedaba era el residuo: la marca entraba y la jornada no se
recalculaba, **sin que nadie se enterara**. Eso lo cerró la
[`0207`](../supabase/migrations/0207_una_marca_que_cae_en_un_periodo_pagado_deja_de_entrar_muda.sql).

**Falta tacharlos en `hallazgos-abiertos.md`**, y con ellos otras dos entradas
que también envejecieron: dice que no existen las pruebas 84 y 85 (existen, de
otros temas) y que «los montos pagados no se congelan en ninguna tabla» (la foto
del pago existe desde la 0096). El propio archivo avisa de por qué importa: un
catálogo con entradas mentirosas hace desconfiar de las que sí siguen vivas.

### El borrador de un memo dejó de imprimirse firmado por Gerencia General

`firmante` y `cargoFirmante` arrancaban en la constante `EMPRESA` y solo se
reemplazaban dentro de `if (doc.firmante_id)`, que en un borrador es null por
definición. El papel salía diciendo **«De: Alvarez Pereyra Felipe Miguel ·
Gerencia General»** en un documento que no había firmado nadie. Y el aviso de
borrador llevaba `no-print`: se veía en pantalla y **desaparecía justo en el
papel**.

Ahora arrancan en null y sin firmante se imprime «Pendiente de firma»; el aviso
sí se imprime y dice que no tiene validez como documento entregado. **En vista
previa, pendiente de mirar y subir a producción.**

Lo que el catálogo tenía mal: cuando el memo SÍ está firmado pero su ficha no se
puede leer —una encargada imprimiendo un memo suyo suscrito por gerencia, flujo
legítimo y a propósito— caer al representante legal no es inventar nada. Ese
caso avisa en pantalla, no en el papel.

### La 0209 está escrita y SIN TERMINAR — y su primer diseño se descartó midiéndolo

El defecto es real y está reproducido dos veces: `fn_cesar_persona` cierra los
tramos de salario y horario, `fn_reactivar_persona` no los devuelve, y quien se
reactiva queda **activa, marcando, cobrando S/0.00** (S/2,254.64 contra S/0.00
con jornadas idénticas) e **invisible para el motor de faltas** (5 contra 0).

**El primer diseño era simétrico y habría metido un defecto peor que el que
arregla.** Reabrir el tramo viejo con `vigente_hasta = null` no lo deja vigente
«desde que volvió»: lo deja vigente **desde su `vigente_desde` hasta el
infinito**, cubriendo hacia atrás todo el hueco. Medido en `BEGIN … ROLLBACK`:

| Qué | Cuánto |
|---|---|
| Reescribe planillas YA PAGADAS | S/2,420.63 en un periodo · **S/3,390.00** en tres |
| Sobrepaga el periodo EN CURSO | S/1,130.00 del mes entero, sin trabajar un día |
| Devenga grati, CTS y vacaciones del hueco | **+S/719.52**, y `fn_grati_cts_periodo` lo desembolsa |
| Fabrica faltas | **89** no justificadas, alimentando el expediente disciplinario |

Y pasa **mudo**: no hay ni un trigger sobre `asignaciones_salario` ni sobre
`horarios_asignados`, y el candado de periodo pagado vive DENTRO de
`fn_set_salario`, así que un update desde otra función lo esquiva.

**El diseño que queda:** no se reabre el tramo viejo, se **crea uno nuevo desde
el día de la reactivación**. El hueco queda sin salario y sin horario, que es la
verdad —esa persona no trabajó—, y ninguno de los cuatro daños puede ocurrir.

**El candado es ESTRECHO, y se decidió con datos.** Volver a `activo` mueve por
sí solo el total de las planillas pagadas de quien tiene hijos —S/98.31 por
periodo, porque la asignación familiar no mira tramos ni jornadas—. Pero de las
**8 personas inactivas de producción, seis tienen un periodo pagado posterior** y
para las seis el daño es CERO (RxH, sin hijos, sin sueldo fijo). Un candado sobre
«hay un periodo pagado» rechazaría seis reactivaciones legítimas de ocho: no
protegería, prohibiría. Se pone solo donde el daño está medido — `con_hijos` con
un periodo pagado detrás—, y **eso es una lista que hay que revisar** el día que
aparezca otro concepto que se pague sin mirar tramos.

**Lo que falta antes de pegarla:** la prueba pgTAP, medir la promesa central
contra un periodo pagado de verdad, y los tres bordes reproducidos (volver
teniendo ya un tramo abierto, un tramo cerrado con fecha futura, y el caso de
cero filas). **No urge:** medido en producción, nadie está hoy en ese estado.

**Y hay dos cosas que la medición destapó y que NO causa la 0209:**

- Una **liquidación ya pagada se vuelve a devengar entera** al reactivar:
  S/852.19 sobre ventanas ya liquidadas por S/1,380.81. `fn_liquidacion_pagar`
  escribe en `liquidacion_pagada` y en `correcciones_auditoria`, pero **no** en
  `desembolsos_beneficios` ni en `movimientos_planilla`, que son las dos únicas
  cosas que miran los guards de `fn_provisiones`.
- La cabecera de la **0176 tiene una errata**: dice que «`fn_set_salario`
  comprueba que la persona esté activa». **Es falso** en la versión vigente — ni
  esa ni `fn_set_horario_semanal` miran `personas.estado`. Es justo la frase que
  haría no poner un freno creyéndolo puesto.

## ~~2026-08-10 — regenerar `types.ts` ya no es solo reordenar~~ ✅ HECHO el 2026-08-14

**Cerrado.** Se hizo, y la causa era más simple —y peor— de lo que decía esta
sección: el generador declara los parámetros de cada función como NO anulables, y
`fn_set_fin_contrato(p_fecha)` acepta null a propósito. Correr el comando dejaba
**63 errores en diez pantallas**. `scripts/tipos-args-nullables.mjs` le agrega
`| null` a los 491 parámetros y va encadenado al script de `gen-types`, así que
el comando documentado ahora termina en verde. Se conserva lo de abajo por el
registro de cómo se midió.



**Medido, no supuesto.** El repositorio venía diciendo que regenerar
`packages/database/src/types.ts` «reordena las 4.400 líneas del archivo entero»
y por eso se aplazaba, resolviendo cada función nueva con un doble casteo. Se
probó de verdad al añadir `fn_expediente_resolver` (0206):

- Genera **4.217 líneas** contra las 2.535 de hoy.
- **Gana 65 nombres** y suelta exactamente dos: `fn_set_horario` y
  `fn_quitar_horario`, que la 0184 borró. Hasta ahí, estrictamente correcto.
- **Pero cambia la convención de los argumentos opcionales**, de
  `string | null` a `string | undefined`. Eso rompe de golpe Ausencias,
  Correcciones y Datos personales, que pasan `null` a propósito.

O sea: **no es un reordenamiento, es una migración de tipos.** Aplazarla sigue
siendo razonable, pero por un motivo distinto al que estaba escrito, y el coste
de aplazarla crece — ya son tres las funciones que el archivo no conoce
(`fn_expediente_resolver`, `fn_tardanza_escalon`, y las columnas nuevas de
`fn_tardanzas_resumen`).

Cuando se haga, va sola en su propia rama y con las tres pantallas revisadas.

---

## 2026-08-10 — un `drop function` se llevó el permiso y la pantalla se calló

**Dos pantallas llevaban días caídas en producción y ninguna lo dijo.** Se
levantaron con la [`0204`](../supabase/migrations/0204_un_drop_se_lleva_el_permiso_y_la_pantalla_se_calla.sql),
que son dos `grant` y nada más. Verificado en producción: las tres filas en
`true`, y Disciplina volvió a listar a las dos personas que le tocaban.

**LA CAUSA, y es de clase, no de caso:** un `drop function` se lleva por delante
los `GRANT`. La [`0189`](../supabase/migrations/0189_una_tardanza_de_tres_horas_deja_de_desaparecer.sql)
hace ese drop sobre `fn_tardanzas_resumen` —obligada, porque devuelve `TABLE` y
Postgres no deja añadirle una columna con `create or replace`— y no vuelve a
otorgar. El último `grant execute` de esa función era de la **0067**. Como este
proyecto revoca el `EXECUTE` que Postgres da a PUBLIC por defecto, no hubo red.

**POR QUÉ NADIE LO VIO EN DOS DÍAS:** `authenticated` no podía ejecutarla,
PostgREST devolvía error, y `admin/disciplina/page.tsx` **no miraba el error de
esa llamada**. Imprimía «Nadie con tardanzas relevantes este mes» — la misma
frase exacta que cuando de verdad no hay nadie. El Dashboard y la Hoja de sede
leen la misma función y estaban igual de ciegos. Un falso negativo mudo en las
tres pantallas que existen para no dejar pasar a nadie.

**LA SEGUNDA, encontrada barriendo las 122 funciones que el panel llama por
`rpc()`:** la 0198 añadió `p_cuspp` a `fn_set_datos_personales` con un
`create or replace`. **Un parámetro nuevo no reemplaza: crea otra función.**
Quedaron dos sobrecargas —18 argumentos con permiso, 19 sin él— y el panel manda
`p_cuspp`, así que PostgREST elegía justo la que no podía ejecutar. Guardar una
ficha fallaba desde entonces. La sobrecarga huérfana de 18 sigue viva, muerta
pero inofensiva; **soltarla queda pendiente**.

**LAS DOS REGLAS QUE DEJA:**

1. **Toda migración que haga `drop function` vuelve a poner su `grant`.** No es
   opcional y no lo cubre nada: el `create or replace` conserva permisos, el
   `drop` + `create` no. La 0200 ya lo lleva por esto.
2. **Añadir un parámetro a una función es crear una función nueva.** Hay que
   otorgarle permiso, y decidir qué se hace con la vieja — dejarla viva es una
   ambigüedad esperando a que alguien la pise.

**Cómo se vuelve a comprobar**, sin fiarse de ninguna lista guardada:
[`quien_puede_ejecutar_el_semaforo.sql`](../scripts/sql-manual/quien_puede_ejecutar_el_semaforo.sql).

**Lo que sigue abierto de aquí:** ninguna prueba habría cazado esto. Las pgTAP
corren como `postgres`, que puede ejecutar todo; el defecto solo existe para
`authenticated`. Una prueba que compruebe los permisos del rol real es el
guardián que falta.

---

## 2026-08-08 — el papel que se le entrega a un locador dejó de llamarlo trabajador

La 0199 le quitó a un locador las cifras que no le tocaban —feriados,
gratificación, CTS, vacaciones— y el papel quedó correcto en los números y falso
en las palabras: seguía titulándose «Boleta interna de pago», llamaba
«Remuneración Básica» a sus honorarios, cerraba con «Total a recibir este mes»,
le contaba los días que «le tocaba venir» y lo mandaba a «consultar con tu líder
de equipo».

**Eso no es redacción, es lo que el documento declara.** En una inspección, el
papel que la empresa emite todos los meses pesa más que el contrato firmado: la
subordinación se prueba con indicios, y aquí CAYLA los estaba imprimiendo ella
misma, en el único ejemplar que esa persona se lleva a casa.

Ahora la pantalla imprime **dos documentos distintos**, no uno con filas de
menos. Quien presta servicios recibe un «Detalle de servicios prestados»: dice
qué relación es (locación del Código Civil), quién organiza el tiempo, que el
documento oficial es **su** recibo por honorarios y —recién al final, como
consecuencia y no como recorte— por qué no hay beneficios. Cierra con «emite tu
recibo por este importe».

**El interruptor es uno solo y vive en `packages/shared/src/vinculo.ts`**, no en
la pantalla. Son nueve las que van a hacer la misma pregunta, y este repositorio
ya juntó 35 copias de la misma condición de permiso antes de aprenderlo.

Ahí está también la regla que más importa: se pregunta `en_planilla === false`,
nunca `!en_planilla`. El frontend se despliega por Vercel mientras el SQL lo pega
Felipe a mano, así que hay ventanas en las que la pantalla nueva corre contra una
base que todavía no manda el campo. Con `!en_planilla`, ese `undefined`
convertiría a **todo el mundo** en locador de golpe: treinta personas recibirían
un papel que les niega gratificación, CTS y vacaciones, y saldría bonito. Las
cuatro pruebas de `tests/vinculo.test.ts` existen para eso.

### Lo que solo se vio mirando la hoja renderizada

La boleta le imprimía **«Colibrí»** — un peldaño de la escala de trabajadores.
La 0182 ya había decidido esconderlo, con este argumento: decir que alguien ocupa
una categoría de la escala es parte de lo que desnaturaliza una locación. Pero se
aplicó solo en la tabla de Planilla. En el código las dos pantallas no se parecen
en nada y ningún `grep` las conecta; se cazó abriendo el documento.

### Lo que queda de este hilo

- **«Honorarios pactados (mes completo) · S/ 1,130.00»** sigue impreso, y el
  número sale de `personas.sueldo_base_legal`. Carlos y Claudia **cobran por
  hora**: un importe mensual fijo impreso cada mes es, él solo, un indicio de
  laboralidad. Quitar esa línea para locadores es un `if` de una línea, y está
  pendiente de que Felipe decida.
- **Faltan las otras ocho pantallas** con el mismo problema: Planilla (135
  conceptos laborales), Provisiones, Liquidaciones, Feriados, Vacaciones, Costos,
  Ausencias y Disciplina.
- **Claudia** es el mismo caso que Carlos y aún no se movió. **Catherine** es
  otro distinto —socia, monto fijo— y se dejó para después a propósito.

---

## 2026-08-08 — el sobretiempo se paga solo, y todo lo que se cobra se declara

Empezó con una pregunta de Felipe —por qué el sistema no dejaba dar el sábado
como descanso por un feriado trabajado— y terminó en cinco migraciones. Lo que
va acá es lo que ninguna consulta puede responder: **por qué se decidió así**.

### Cómo se mide el sobretiempo, y las tres trampas

**Contra 48 h SEMANALES, nunca contra 8 h diarias.** El art. 25 de la
Constitución dice «ocho horas diarias O cuarenta y ocho semanales» y CAYLA pactó
la semanal, en contratos y RIT. Medido por día, el taller de Lima —5 días de
9 h = 45 h— generaría sobretiempo todas las semanas del año haciendo tres horas
MENOS que el máximo legal.

**«Semana» es un ciclo de siete días, no lunes a domingo.** Criterio vinculante
del Informe 027-2021-MTPE/14. El ciclo empieza tras un descanso y se corta a los
7 días; sin ese corte, doce días seguidos de 8 h darían 48 h de exceso en vez
de 8 — un tope semanal convertido en tope por racha, que no existe en la norma.

**Los ciclos no se solapan, y por eso el pago NO usa la ventana móvil** que sí
usa la alerta de Incidencias. Ahí el objetivo es no perderse ningún tramo
cargado; acá, una ventana móvil pagaría la misma hora siete veces.

Y se suma **el recargo** (25 % / 35 %), no la hora completa: las horas ya están
en `pago_base`. Es el mismo error que la 0173 corrigió con el feriado del sueldo
fijo.

### Tres exclusiones distintas que NO se pueden fundir en un campo

| Quién | Por qué | Dónde vive |
|---|---|---|
| RxH | Un locador no tiene jornada; pagarle horas extras es indicio de laboralidad | `tipo_vinculo` |
| Personal de dirección | Art. 5 del D.S. 007-2002-TR: fuera de la jornada máxima | `personas.personal_direccion` (0187) |
| Sueldo fijo | Su pago no depende de horas: un recargo sobre monto fijo no dice nada | `sueldo_fijo` |

**`personal_direccion` tiene columna propia y no se deduce del rol.** `admin` es
un permiso informático: el día que se le dé admin a alguien de DO para
administrar pantallas, se le quitaría sin querer su derecho a horas extras. Y no
es lo mismo que `sueldo_fijo`, que es una condición de pago — hay dirección que
cobra por horas. Hoy está marcado Felipe, y solo él.

### Qué entra a la base de EsSalud y pensión, y qué no

Entran el **feriado** y el **sobretiempo** (0193). No admiten discusión: el
art. 19 del D.S. 001-97-TR no los lista como no remunerativos y SUNAT les da
código propio en la tabla 22 de la PLAME — **0105** (sobretiempo 25 %), **0106**
(35 %) y **0107** (feriado o día de descanso).

**No entran, y no es un olvido:** el complemento variable y el plus por
objetivos, que tienen defensa legal real y están dentro de una estructura
decidida con el contador (ver
[`analisis-estructura-remunerativa-2026-07-30.md`](analisis-estructura-remunerativa-2026-07-30.md));
y la movilidad y la educación, no remunerativas por el art. 19 incisos e) y f).

⚠️ **Las sobretasas COMPLETAN una base declarada; no crean una donde no la hay.**
La primera versión le inventaba S/41.39 de pensión a un RxH y S/46.45 a alguien
con sueldo fijo — los dos tienen la básica en 0 a propósito. Ninguna prueba
existente cayó: eran montos de personas que antes no aparecían en ningún cálculo
de pensión. Lo fija ahora la `150_la_base_de_aportes_no_se_inventa`.

### La vía para reducir el costo en origen NO es dejar de declarar

Son dos, y las dos son legales:

- **Descanso sustitutorio** por feriado trabajado (art. 9, D. Leg. 713). Con él
  la sobretasa del 100 % no se genera. Medido en un caso real: el feriado de esa
  persona baja de S/206.83 a S/104.89.
- **Compensar el sobretiempo con descanso equivalente** (art. 10 del TUO), con
  acuerdo por escrito, dentro del mes calendario siguiente, sin tocar el descanso
  semanal ni caer en feriado.

**No aplicar la 0193 no era una vía.** La obligación existe con o sin migración:
lo único que cambiaba era si el sistema la mostraba.

### El retroactivo, y por qué no fue «por fuera»

S/100.03 en 8 personas por el sobretiempo de 28-jun → 28-jul, registrado como
movimiento en la planilla de agosto con el concepto nombrado. Felipe propuso
pagarlo en efectivo y se descartó: el sobretiempo **es remuneración**, así que
pagarlo fuera de planilla sería remuneración no declarada — una infracción nueva
y formal para tapar una vieja e informal. Misma plata, un renglón de diferencia.

### La política salarial, versión 4

Publicada el 2026-08-08 20:20. Dice el sobretiempo (25 % / 35 %), que la base de
aportes incluye feriados y sobretiempo, y **avisa que el neto baja antes de que
llegue la boleta** — entre S/9 y S/50 por persona, íntegro a su fondo.

⚠️ **Y lleva un blindaje que hay que conservar.** Al reforzar «45 horas cuando la
ley permite 48», Felipe levantó el riesgo: si alguien llegara a sostener que la
jornada pactada son 45, las horas 46 a 48 pasarían a ser sobretiempo con recargo
para todo el equipo, todas las semanas. El documento dice ahora, en el mismo
párrafo, que **el sobretiempo se cuenta desde la hora 49 y no desde la 46**, y
cinco pruebas de `politica-salarial.test.ts` no dejan que se caiga — incluida una
que verifica que nunca aparezca la frase «jornada de 45 horas».

**La versión 3 se quemó** por caché del navegador: se publicó un documento byte
por byte idéntico al anterior y el sistema no dijo nada. Quien la haya acusado
tiene que volver a hacerlo sobre la 4.

---

## 2026-08-08 — seis puertas dejaban cambiar una planilla ya pagada

**El repositorio y producción llevaban semanas diciendo cosas distintas, y no
había manera de enterarse.** Se compararon los dos esquemas enteros —199
funciones, 261 candados, 467 columnas— y el resultado ordena todo lo de abajo:

| | |
|---|---|
| **candados** | idénticos, byte a byte. Es lo que volvió inofensivo casi todo lo demás |
| **columnas** | idénticas, salvo dos que solo existen en producción |
| **funciones** | **22 distintas** |

### Lo único que era grave

Seis funciones de producción no tenían el candado de periodo pagado que el
repositorio les puso en julio con la 0026 y la 0037: `fn_set_feriado`,
`fn_quitar_feriado`, `fn_set_turno`, `fn_quitar_turno`, `fn_set_horario_semanal`
y `fn_set_descanso`.

Reproducido en local el estado exacto de producción y llamadas las seis sobre una
fecha de un mes ya pagado, **las seis dejaron pasar el cambio y una borró un
feriado de un mes pagado sin decir una palabra.** El daño no se ve: la jornada se
recalcula sola con el trigger, las horas del mes cambian, y la planilla
depositada deja de cuadrar con lo que el sistema dice hoy. Se descubre cuando
alguien reclama.

La [`0180`](../supabase/migrations/0180_el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron.sql)
lo repone —aplicada y confirmada, 6 de 6— y la prueba
[`141`](../supabase/tests/141_las_seis_puertas_a_una_planilla_pagada.test.sql)
exige **las dos mitades**: que dentro de lo pagado lancen, y que fuera de lo
pagado sigan funcionando. Un candado que cierra siempre lo quita cualquiera en la
primera urgencia.

Antes de sobrescribirlas se pidieron sus cuerpos y se compararon línea a línea:
producción era el repositorio **menos** el bloque, ni una línea de más. Mirar
antes de escribir no era ceremonia — siete funciones de las 22 tienen código que
el repositorio no conoce (ver abajo).

### El resto era texto roto

Seis funciones decían `l√≠der` donde debía decir `líder`: UTF-8 leído como **Mac
OS Roman**, que parte cada acento en dos. Se confirmó simulando esa conversión
sobre el cuerpo del repositorio — los md5 salen exactos, así que se identificaron
sin gastar consultas. Lo arreglan la **0181** (cuatro) y la **0183** (las dos que
la comprobación de la 0181 destapó, que además corrían la versión de julio de
`fn_crear_periodo` y `fn_eliminar_periodo`). Las dos aplicadas y confirmadas.

⚠️ **Y ese mismo día se demostró que el daño SIGUE ENTRANDO.** Horas después de
limpiar las seis, la consulta «qué falta pegar» devolvió `⚠ md5 SIN CATALOGAR`
para `fn_planilla_calcular` — la función que decide lo que cobra cada persona.
Medido: era el cuerpo de la **0185 pasado por Mac OS Roman**, y la 0185 se había
pegado ese mismo día.

O sea que el razonamiento de arriba —«si el canal fuera el culpable estarían
rotas las 199»— **era falso**: el daño no entra de una vez, entra **por pegada**.

✅ **Y la causa se encontró el mismo día: era `pbcopy` con el locale en `C`**
dentro del propio `dame-el-sql.sh`. Con `LC_CTYPE=C` el portapapeles interpreta
el UTF-8 como MacRoman y cada acento se parte en dos. O sea que la ruta culpable
no era «otra vía»: era la nuestra, en las sesiones cuyo entorno tenía ese locale
—por eso cuatro migraciones del mismo día salieron limpias y una no—. Ya está
arreglado: el script compara el portapapeles byte por byte contra el archivo y se
niega si no coinciden. Ver la regla en `CLAUDE.md`.

**Quedan dos detectores permanentes, y ninguno depende de una lista a mano:** la
fila **ACENTOS** de `que_falta_pegar.sql`, que barre el esquema entero buscando
el signo «√», y la columna `tiene_acentos_rotos` de
`en_que_version_esta_la_planilla.sql`. El catálogo de md5 de esa consulta
**también se calcula solo** desde las migraciones, con `iconv -f MAC` para
generar la variante rota de cada versión: llegó a mentir tres veces en un día
mientras se escribía a mano.

### El agujero que casi se anuncia y no existía

La 0026 le añadió a `fn_crear_periodo` un candado contra dos periodos que cierren
el mismo mes, con su motivo escrito en julio: «el plus de objetivos se pagaría
doble». Producción no lo tenía. La conclusión saltaba sola.

**Se probó antes de afirmarlo y es falsa.** El segundo periodo falla igual: lo
frena el índice único `periodos_etiqueta_unica` sobre (año, mes) de la fecha de
cierre. Y los 261 candados de producción son idénticos a los del repositorio.
Igual con el `advisory lock` que falta: `periodos_sin_solape` impide el solape de
todos modos.

**Aquí lo que protege el dinero es el candado de la BASE, no el de la función.**
Las seis puertas eran un agujero real porque detrás no había ningún constraint;
esta no lo era porque sí lo hay. Misma forma, conclusiones opuestas, y solo
medirlo las distingue.

### La lección de método, que costó medio día

**Un dato de referencia nunca viaja guardado — ni en un archivo ni en un
mensaje.** El comparador viejo llevaba las huellas del repositorio dentro y
acusó a 25 funciones que estaban bien. Se sacaron del archivo… y entonces
caducaron en el mensaje que las transportaba: se calcularon a las 10:28, entraron
cinco migraciones a las 10:55 y 11:14, y la comparación de las 11:30 ya no valía.

`huella_del_esquema.sql` calcula las dos mitades en el mismo minuto y trae
`hasta_migracion`, para que comparar dos generaciones distintas se delate en vez
de asustar. Los tres comparadores que mentían —`comparar_funciones.sql`,
`comparar_solo_funciones.sql`, `huellas_produccion.sql`— quedan **vaciados, no
borrados**: su contenido está en git y su ruta sigue avisando por qué no usarlos.

**Y una comprobación que barre gana a una que pregunta por una lista.** La de la
0181 no preguntaba por sus cuatro funciones: buscaba el signo «√» en el esquema
entero. Devolvió dos que nadie había señalado.

---

## 2026-08-06 — ningún papel firmado se podía subir, y nunca se pudo

**Lo que parecía un módulo terminado desde julio no funcionaba ni una vez.** El
cargo firmado de un memo disciplinario no se podía archivar desde que existe el
módulo (0074). Los tres memos entregados de producción llevaban semanas con «sin
el papel archivado» al lado y no era descuido de nadie: la base los rechazaba.

**La causa, que no se veía leyendo el código.** Supabase Storage no escribe el
objeto con un `INSERT`. Escribe `INSERT … ON CONFLICT DO UPDATE … RETURNING *`, y
esa forma necesita **tres** permisos, no uno: INSERT por la fila, SELECT por el
`RETURNING`, y UPDATE por el `ON CONFLICT`. Ningún bucket tenía política de
UPDATE. Y la de SELECT de `expedientes` exigía que el adjunto ya estuviera
registrado en `expediente_adjuntos`… registro que se crea DESPUÉS de subir el
archivo. Un círculo cerrado: no se podía escribir sin poder leer, ni leer sin
haber registrado, ni registrar sin haber escrito.

Lo que más costó: `fn_expediente_puede_adjuntar` devolvía **`true`** mientras la
fila se rechazaba, así que el fallo se leía como un problema de permisos de la
persona. El mensaje de Postgres nombra la tabla pero **no dice cuál de las
políticas faltó**. Se resolvió leyendo el log del contenedor de storage.

| # | Qué |
|---|---|
| **0170** | El acta de descanso acepta **HEIC/HEIF** — el formato en que un iPhone guarda sus fotos. Sin esto salían en gris en el diálogo de archivos: no se podían ni seleccionar, y la pantalla no daba ningún error |
| **0172** | Las políticas que faltaban en los tres buckets. Abre exactamente el hueco medido y nada más: quien subió un archivo puede leer **lo suyo** mientras lo registra (`owner_id = auth.uid()`), y quien puede crearlo puede reemplazarlo |
| **0175** | El acta de descanso **deja de guardarse como texto en una columna** y pasa al almacén, con los mismos 50 MB que los demás papeles. Los 3 MB de antes no eran una decisión sobre las actas: eran el precio de dónde vivían |

**Tres fallos más de pantalla, cada uno con causa distinta:** el formulario para
subir el cargo estaba escrito **solo** en «Firmados — por entregar», y los tres
memos de producción están entregados · Chrome **no reconoce el `.HEIC`** y
entrega la foto sin tipo, que el almacén rechaza con `415` (el tipo se deduce
ahora de la extensión, en `lib/tipos-archivo.ts`) · «Ver acta» abría un
`<iframe src="data:…">` que Chrome **bloquea**, dejando la pestaña en blanco.

**Por qué ninguna prueba lo cazó.** No había una sola que tocara
`storage.objects`, y un `INSERT` simple pasaba mientras el sistema no
funcionaba. La prueba **136** ejecuta ahora la sentencia real de Storage,
copiada de su log; la **137** cubre las dos ubicaciones posibles del acta.

---

# 📌 QUÉ FALTA — repartido por quién lo hace

## A · Lo que depende de Felipe

### A.1 · Con fecha límite — **en curso** (confirmado 2026-08-06)

| Qué | Cuándo | Si no |
|---|---|---|
| **Los convenios individuales de movilidad, firmados y cargados** | **antes del 28/08/2026** — es cuando se paga el periodo | Se habrá pagado movilidad sin el papel que la sostiene. La **RTF 05449-4-2007** desconoció la de 14 de 21 trabajadores por eso exacto |
| **La política de movilidad de empresa, firmada** | con fecha **anterior al 29/07/2026** | Es cuando empezó a pagarse movilidad. Un documento posterior a los pagos que justifica **no los justifica, y encima lo deja por escrito**. El tablero lo avisa solo, en rojo, con las dos fechas |
| **Contratar el Seguro Vida Ley** | cuanto antes | ~S/1,560/año. Sin póliza, CAYLA responde con su patrimonio: 16 remuneraciones por muerte natural (~S/18,000) o 32 por accidente o invalidez total (~S/36,000). Obligatorio desde el primer día (D.Leg. 688, mod. **Ley 31408**) |
| **Pagar el día sustitutorio de Arequipa** | **el 29/09/2026**, con el periodo 29/08–28/09 ya cerrado | El equipo de AQP habrá descansado el 31/08 sin cobrarlo, y el acuerdo que firmaron dice que sí les tocaba. **No es automático**: el sistema no sabe que el 15/08 existe. Ver la sección propia más abajo |
| **Registrar la póliza en el MTPE** | 30 días desde que se firma | No registrarla es la misma infracción que no tenerla |
| ~~**Pegar la [`0176`](../supabase/migrations/0176_quien_ya_se_fue_deja_de_tener_sueldo_vigente.sql)**~~ | ✅ **pegada el 2026-08-06** | Las seis de julio dejaron de tener sueldo vigente. No movió plata: su liquidación es S/ 0.00 antes y después (RxH, de 0 a 3 días). Comprobado con cuatro ceros: sin tramos abiertos, sin tramos pasados de largo, sin tramos posteriores al cese, sin motivos por revisar |
| ~~**Pegar la [`0179`](../supabase/migrations/0179_la_pantalla_de_equipo_dice_cuando_y_por_que_se_fue.sql)**~~ | ✅ **pegada** — figura en `migraciones_aplicadas` de producción | La pantalla de Equipo ya dice cuándo y por qué se fue cada quien. El motivo viaja solo a admin y líder DO |
| ~~**Pegar la 0180, la 0181 y la 0183**~~ | ✅ **pegadas el 2026-08-08** | Ver la sección del 08-08 arriba. Confirmadas por lo que devolvió el SQL Editor: `las_seis_con_candado: 6` y `funciones_con_texto_roto: 0` |
| ~~**Pegar la [`0201`](../supabase/migrations/0201_la_foto_del_pago_aprende_el_sobretiempo.sql)**~~ | ✅ **pegada el 2026-08-10** | Sin ella, «Marcar como PAGADO» fallaba **para todo el periodo** —no solo para quien hiciera sobretiempo— en cuanto alguien pasara de 48 h en un ciclo de siete días. El candado de la foto era de julio (0127) y no conocía el sobretiempo que la 0185 empezó a pagar en agosto. Confirmada con cinco comprobaciones en verde, incluida la que recorre las 96 fotos ya guardadas con la fórmula nueva: ninguna se rompió |

**Del Seguro de Vida Ley:** cotizado en **La Positiva, S/170/mes por 19
personas**, sin comisión de corredor —Dante confirmó que el reglamento no la
contempla— y con factura. **El 19 hay que cruzarlo antes de firmar**: el diseño
remunerativo asume 26. Quien esté en planilla y fuera de la póliza queda sin
cobertura, y ese capital lo paga CAYLA de su patrimonio. La consulta que arma la
lista real está en
[`quienes_van_al_seguro_de_vida_ley.sql`](../scripts/sql-manual/quienes_van_al_seguro_de_vida_ley.sql).

### A.2 · Lo que bloquea del contador — la marca de afectación

El código no es el problema: el problema es **con qué marca de afectación**
quedan el 0909 (movilidad), el 0202 (educación) y el 0203 (cumpleaños) en el
PDT — EsSalud, ONP/AFP y quinta categoría. Si alguno queda declarado afecto, no
solo se pagan aportes que la ley no exige: **CAYLA declara por escrito y mes a
mes que el concepto es remunerativo**, y eso destruye el sustento del artículo 19
con nuestra propia firma.

Es lo único que tiene que responderse **antes de declarar el primer periodo** con
los tres conceptos. La repregunta está redactada y lista para enviar en
[`movilidad-y-codigos-plame-para-el-contador.md`](movilidad-y-codigos-plame-para-el-contador.md).

*(Dante escribe los códigos sin el cero inicial —dijo «909» por 0909—, así que
son **0202** y **0203**. Falta su confirmación de una línea.)*

### A.2.a · La maternidad: **construida y aplicada** (0262, en producción el 2026-08-17)

**Nadie ha estado de maternidad todavía, y por eso hubo tiempo de hacerlo bien.**
La duda de si el subsidio va por planilla o por fuera **quedó resuelta por la
norma, no por criterio**: el D.S. 013-2019-TR art. 17.1 obliga al empleador a
pagarlo **en la misma fecha en que pagaría la remuneración**, y el art. 17.2 hace
que el reembolso **exija haber pagado antes**. No es opcional y no va por fuera.

Lo que sí es correcto es que el **sueldo** salga en S/0.00: durante la licencia el
contrato está suspendido (D. Leg. 728, arts. 11 y 12.c). Lo que faltaba no era
sueldo — era el subsidio, que no entraba por ningún lado.

**La 0262 lo conecta**, con la misma forma que la 0254 usó para el descanso
médico: dentro de `pago_base`, así que no toca `chk_foto_cuadra` ni
`fn_planilla_congelar` y no puede atascar un cierre. Medido en local con datos
propios (licencia de 10 días corridos, S/200 diarios, feriado dentro):

| | días | subsidio | pago_base | base EsSalud | retiene pensión | total |
|---|---|---|---|---|---|---|
| AFP (integra) | 10 | 2 000.00 | 2 000.00 | **765.48** | 258.40 | 1 741.60 |
| ONP | 10 | 2 000.00 | 2 000.00 | 765.48 | **0.00** | 2 000.00 |
| sin monto entrado | 0 | 0.00 | 0.00 | 1 130.00 | 0.00 | **avisa: 10 días sin monto** |

Las cinco decisiones que la sostienen:

- **Días calendario, no laborables.** El promedio diario de EsSalud ya viene
  dividido entre días corridos; contarlo por laborables le quitaría dos séptimos
  a quien trabaja cinco días. Es la diferencia de fondo con el descanso médico,
  que sí cuenta laborables porque aquello es sueldo.
- **El feriado de dentro se cuenta, y se le quita a `fer`.** El primer intento
  hacía lo contrario —copiaba el filtro de la 0254— y **medirlo lo tumbó**: quien
  está de licencia todo el mes devenga S/0.00 de feriados, así que excluirlo no
  evitaba una duplicación, le quitaba el día. Diez días le pagaban nueve. La
  duplicación se evita por el otro lado: `fer` deja de devengar los feriados de
  dentro de la licencia. Las dos mitades son una sola decisión.
- **El monto lo entra DO, no lo calcula el sistema.** Los 12 meses del promedio
  pueden incluir **empleadores anteriores a CAYLA**, y esta base solo tiene una
  foto congelada. Y hay una razón más que salió de la investigación: **el divisor
  360 no está en el D.S. 013-2019-TR** — la norma dice «promedio diario» y el 360
  es práctica de EsSalud. Va en `ausencias.subsidio_diario`.
- **No infla EsSalud, y el piso RMV se prorratea.** El art. 33 del D.S. 009-97-SA
  tiene una excepción expresa: para quien percibe subsidios, la base mínima se
  determina «de forma proporcional a los días no subsidiados del mes». Sin eso
  CAYLA declararía la RMV entera por alguien de licencia. No perjudica a nadie:
  es plata de la empresa y una declaración que no corresponde.
- **AFP sí, ONP no** — y ya **no es criterio, es norma expresa**: art. 16 de la
  Ley 26504 («los subsidios de carácter temporal … se encuentran afectos» al SPP)
  y último párrafo del art. 30 del TUO de la Ley del SPP. La ONP la resuelve el
  Informe N.° 049-2014-SUNAT/5D0000. Vive en `tasas_pension.grava_subsidio`.

**EL ACCIDENTE QUE CASI PASA, y por qué el número es 0262.** Esto se escribió
como **0256**, con el cuerpo sacado de la 0254 —la vigente entonces—. Mientras
se escribía, otra sesión fusionó a `main` la **0261**, que reescribe la MISMA
función y que también había partido de la 0254. Dos migraciones sobre la misma
base: **la última en aplicarse borra a la otra en silencio**, y como 0261 > 0256
el orden de pegado habría hecho desaparecer todo esto sin un solo error.

Lo cazó `./scripts/donde-vive.sh` al ir a fusionar. Por eso la migración se
renumeró a 0262 y su cuerpo se volvió a extraer de la 0261. La regla, otra vez:
**el cuerpo se copia de la VIGENTE, y la vigente se pregunta, no se supone** —
y se vuelve a preguntar justo antes de fusionar, porque main se mueve.

**LA CADENA DE md5, para verificar cada pegada:**

| paso | md5 | caracteres |
|---|---|---|
| producción hoy (0254) | `19eb593a757e0b7480b6a1dc99d7f8c9` | 75 882 |
| tras lo pendiente hasta la **0261** | `0d0f5fdd5f53d29fb316be50c794cec6` | 77 493 |
| tras la **0262** | `261329fc2a8045ece063cfb0e5d38eca` | 87 322 |
| tras la **0263** | `f6b4f2649f4132dd2db5711b391b1f54` | 89 134 |

**LO QUE FALTA, en orden:**

1. **Pegar todo lo pendiente hasta la 0261** y comprobar que el md5 quede en
   `0d0f5fdd…`. Si no queda ahí, la 0262 no se pega.
2. **Pegar la 0262 y luego la 0263** — *después del cierre del 28*, no antes.
3. **El formulario todavía no tiene el campo.** `fn_registrar_ausencia` no conoce
   `subsidio_diario`, así que hasta que una migración se lo enseñe el monto se
   pone con `scripts/sql-manual/poner_el_subsidio_de_maternidad.sql`. Mientras
   tanto la planilla **avisa** de los días sin monto en vez de pagar cero
   callando, que era el defecto original.

### A.2.a.bis · Dos hallazgos que salieron de la investigación del 2026-08-15

**1 · Los primeros 20 días de descanso médico estaban SUB-DECLARADOS → 0263.**
Confirmado con norma y con criterio administrativo: lo que CAYLA asume esos 20
días **es remuneración**, afecta a EsSalud y a la base de pensión (D.S. 009-97-SA
art. 15; Informes SUNAT 259-2004 y 003-2007). El código PLAME 0916 es **solo**
para el subsidio de EsSalud, que nace el día 21. La 0254 los metía en `pago_base`
pero **no** en `pb.basica`, así que no llegaban a `bri.base`: se pagaban y no se
declaraban.

**La 0263 lo corrige** — un solo término en `bri.base`, con la misma guarda de
vínculo que el feriado y el sobretiempo. Se pega **después de la 0262**, porque
su cuerpo parte de ella. Medido con una persona con S/870.97 de descanso médico:

| | hoy | con la 0263 |
|---|---|---|
| base EsSalud | 1 130.00 | 1 182.90 |
| aporte de CAYLA | 101.70 | 106.46 |
| **retención de pensión** | 40.30 | **152.83** |

Nadie más se mueve. **Pero esos +S/112.53 salen del sueldo de quien tuvo descanso
médico** — es lo correcto, porque esos días ahora sí le cuentan para su pensión,
y hay que avisarle antes de que le aparezca en la boleta.

La prueba 200 lo fija, y se verificó que **falla sin la 0263**: sin el arreglo,
las bases de la enferma y de la de control salían idénticas.

**2 · La asignación familiar: NO es exigible, y aun así NO se puede quitar.**
Investigado el 2026-08-15 con ocho agentes contra fuentes primarias. Las dos
mitades de la respuesta van juntas o se entiende al revés.

**No es exigible.** El art. 43 de la Ley 28015 (sustituido por el art. 7 del
D. Leg. 1086, hoy art. 50 del TUO D.S. 013-2013-PRODUCE) no la lista entre los
derechos del régimen especial. Lo que convierte esa ausencia en exclusión —y no
en silencio— es el art. 29 del reglamento (D.S. 008-2008-TR): el régimen «está
constituido por los beneficios laborales contemplados en la Ley». Y la técnica
legislativa lo confirma: cuando el legislador quiso que un derecho del régimen
general siguiera corriendo, lo dijo con nombre (utilidades, CTS, derechos
colectivos). Para la asignación familiar no hay remisión. **El Tribunal
Constitucional ya lo dio por sentado**: en la STC Exp. 00021-2014-PI/TC (Pleno,
13/03/2020) su propio cuadro comparativo dice «Asignación familiar — pequeña
empresa: No», y la demanda de inconstitucionalidad se declaró **infundada**. Los
dos refutadores independientes no pudieron tumbarlo.

**Pero no se puede suprimir.** Al venir pagándose, es una mejora del régimen
especial (art. 35 del D.S. 008-2008-TR) incorporada al contrato. Quitarla por
circular es **reducción inmotivada de remuneración = acto de hostilidad
equiparable al despido** (art. 30.b de la LPCL). Solo se puede suprimir hacia el
futuro, por acuerdo escrito, libre y con contraprestación, **persona por
persona**. Y lo ya pagado no se recupera ni se descuenta jamás.

**La vía de riesgo cero es congelarla**: dejar de subirla cuando suba la RMV, sin
tocar lo que hoy cobra nadie.

⚠ **Antes de cualquier cosa hay que verificar dos hechos**, y cualquiera de los
dos invierte el resultado:

1. **¿CAYLA está inscrita y vigente en el REMYPE?** El art. 29 condiciona todo el
   régimen especial a esa inscripción. Sin ella corre el régimen general y la
   asignación familiar **sí** es obligatoria. Revisar también el tope de 1700 UIT
   y las causales de exclusión del art. 31 (grupo económico, vinculación).
2. **Quién entró antes del D. Leg. 1086 o bajo régimen general** — el art. 30 les
   conserva sus derechos.

**Esto no es una decisión de código y no hay migración.** Es para el contador y,
por el tipo de exposición, probablemente para un abogado laboralista. Dato para
esa conversación: se declara en PLAME con el código **0201**, es computable para
gratificaciones, CTS y vacaciones, y afecta base de EsSalud, AFP/ONP y renta de
5ta — o sea que congelarla o quitarla arrastra más de una línea.

Durante la licencia por maternidad se sigue pagando: ninguna norma la condiciona
a labor efectiva.

### A.2.b · Los tres locadores están retratados como personal subordinado

**Para consultar con el contador. No hay nada roto en el cálculo** — eso se
verificó y se descarta abajo. Lo que hay es un riesgo de cómo el sistema los
retrata.

**Son tres, confirmado por Felipe el 2026-08-07:** Carlos Espejo, Catherine
Pereyra y Claudia Pereyra. Los tres cobran por honorarios y los tres aparecen
así:

| | Sede | Rol en el sistema | Área | Rango de la escala | Pago |
|---|---|---|---|---|---|
| **Carlos Espejo** | CCO | **Admin** | Desarrollo org. | Aurora · S/1,800 | **por hora trabajada** |
| **Catherine Pereyra** | CCO | **Líder de equipo (encargada)** | Comercial | Oráculo · S/1,800 | por confirmar |
| **Claudia Pereyra** | LIM | **Líder de equipo (encargada)** | Comercial | Aurora · S/1,800 | por confirmar |

⚠️ **La columna «Pago» decía «fijo mensual» para los tres y era falsa, al menos
para Carlos** (Felipe, 2026-08-08). Cobra **por hora**: marca cuando decide
trabajar y se le paga lo que marcó. No es un detalle contable — «monto fijo,
igual mes a mes» es uno de los indicios de laboralidad que miran SUNAFIL y los
jueces, y este cuadro lo daba por cierto sin haberlo comprobado. **De Catherine y
Claudia sigue sin confirmarse.**

Cargo de mando, área, sede y un rango de la escala salarial. Son indicios de
**subordinación**, que es lo que convierte una locación de servicios en un
contrato de trabajo.

**Lo que el caso de Carlos tiene A FAVOR, y este documento no decía:** es
cuadripléjico, trabaja desde su casa, **no está sujeto a horario** y **cobra por
hora**: marca cuando él decide trabajar. Ninguno de los indicios de subordinación
que lista la doctrina —horario fijo, instrucciones directas, equipos de la
empresa, monto idéntico cada mes— aplica a esa descripción. Su marcaje no es
control de asistencia sino la medida de lo que factura, y desde la
[`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql)
el sistema ya no lo trata como asistencia: no le mide tardanza ni salida
anticipada, solo sus horas.

Lo que queda en su contra es el RETRATO —el rol `admin`, el área, el rango de la
escala—, no los hechos. Y el retrato se arregla; los hechos no habría cómo. El riesgo no es una multa: es la **desnaturalización** del
vínculo, con CTS, gratificaciones, vacaciones y EsSalud retroactivos desde el
inicio — y multiplicado por tres.

**Lo que ya está bien:** el cuadro de categorías que se publica al equipo bajo la
Ley 30709 **no los cuenta ni los incluye en las bandas** desde la 0145: filtra
por `tipo_vinculo = 'planilla'`. El documento legal no dice que estén dentro de
la escala. El retrato queda en las pantallas internas.

**✅ Y el indicio más caro de todos quedó cerrado el 2026-08-08.** El sistema les
medía **tardanza y salida anticipada**, y las guardaba: 524 jornadas de personas
no sujetas a horario. Un registro de tardanzas no es un dato de más — es
**control de jornada**, el indicio más directo de subordinación que existe, y lo
fabricaba CAYLA sobre sí misma día a día. La
[`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql)
lo cierra en la raíz —`fn_recalcular_jornada` deja de medir a quien no está
`en_planilla`, y con eso los seis consumidores quedan correctos sin tocarlos— y
limpia lo ya guardado. Confirmado en producción: `mediciones_que_sobran: 0`. Sus
**horas sí se siguen calculando**: de ellas depende lo que cobran (prueba 149).

Salió de una frase de Felipe y de ninguna auditoría: «era RXH, ellos no están
sujetos a horarios, solo lo puse como referencia». Ninguna de las diez revisiones
independientes lo vio, porque para verlo hay que saber **qué es cada persona**, y
eso no está escrito en el código.

**Y uno de los tres es un frente aparte: Carlos tiene rol `admin`.** Eso le da
todas las sedes, todos los datos personales del equipo —**cuentas bancarias y
DNI incluidos**— y la capacidad de firmar despidos.

**Lo que hace falta NO es quitarle el acceso.** Se evaluó el 2026-08-07 y se
descartó por dos razones: su área es Desarrollo Organizacional, que necesita esos
datos para trabajar; y `admin` y `lider_do` están en el mismo grupo de permisos
—los dos pasan por `puedeVerIdentidad`—, así que bajarlo de rol **no reduciría
nada**. No existe un nivel intermedio. Felipe confirmó además que es de absoluta
confianza, y eso no está en discusión.

**Lo que falta es el papel.** La Ley 29733 no pregunta si la persona es
confiable: pregunta si CAYLA puede demostrar quién accede a los datos personales
y bajo qué obligación. Un trabajador en planilla está sujeto al deber de reserva
por su contrato y por el RIT. **Un locador solo lo está si su contrato de
locación lleva la cláusula de confidencialidad y tratamiento de datos.**

Es una cláusula, no un cambio de sistema — y aplica a los tres, no solo a Carlos.
Vale preguntársela al mismo abogado o contador que revise el vínculo.

Y el agravante: **el expediente lo arma el propio sistema.** La pantalla de
Equipo los nombra encargados, les asigna un área y les pone un rango de la
escala salarial. Es prueba escrita, generada por CAYLA.

**Si son socios, cobrar por honorarios es correcto y común.** El problema no es
el vínculo: es que la ficha los describe como encargados de equipo, cargo que no
les agrega autoridad —si son socios ya la tienen— y en cambio construye la
prueba de lo contrario. Este archivo ya lo había anotado antes como un problema
de permisos («el rol de Catherine está al revés de su papel»); es más que eso, y
son tres.

**Lo que hay que decidir:** qué son para CAYLA —socios, dirección, asesores
externos— y alinear rol, área y rango con esa respuesta. Son tres campos por
persona, editables desde Equipo; ninguno cambia lo que cobran.

**✅ Decidido el 2026-08-07 y con pieza construida:** Catherine es **socia**;
Carlos y Claudia, **asesores**. La
[`0182`](../supabase/migrations/0182_el_cargo_dice_que_eres_el_rol_dice_que_abres.sql)
agrega un campo `cargo` para escribir **qué es** una persona sin tocar lo que
puede abrir — se descartó a propósito meter «socio» y «asesor» en el enum `rol`,
porque `rol` no es un cargo sino una llave de permisos. Con el cargo escrito, la
pantalla deja de llamarlos encargados y el sistema deja de armar el expediente
en contra. **Comprueba si ya está pegada** con `./scripts/que-falta-pegar.sh`.

**Lo que YA se verificó, y no hace falta volver a mirar** (2026-08-07): el
dinero está bien. A un `rxh` no se le calcula movilidad ni EsSalud (0117), ni
educación (0120), ni gratificación, CTS, vacaciones o el 9% de la Ley 30334
(0160, con la prueba `127`). Lo único que recibe es su pago base, que es lo que
se le transfiere. **No hay provisiones indebidas ni plata de más.**

### A.2.b.bis · A quien cesa se le paga dos veces el mismo mes, y de más

⚠️ **LA CAUSA YA ESTÁ CERRADA — lo que sigue abierto es dinero ya pagado.** Los
dos arreglos de código que esta sección pedía están en producción desde el
2026-08-13 (ver «Lo que ya está hecho», más abajo). Lo que queda no lo arregla
ninguna migración: es una decisión por persona. Quien lea esto en una sesión
nueva no tiene que volver a investigar el divisor.

**Medido en producción el 2026-08-10, con las dos consultas que quedan en
`scripts/sql-manual/`.** Son dos defectos distintos que se dan la mano, y
conviene no mezclarlos.

#### 1 · El divisor: la liquidación paga inflado — **S/1,097.67 en 7 personas**

`fn_planilla_calcular` reparte el sueldo mensual entre los días **del rango que
se le pida**:

```
v_dias := (p_fin - p_ini) + 1;   v_base := 6.5 * v_dias;   pago := horas * salario / v_base
```

`fn_liquidacion` (0164:103) es **la única en todo el sistema que pide un rango
parcial** — del inicio del periodo a la fecha de cese, «ni un día más». Con menos
días el divisor se encoge y el mismo trabajo se paga más. Quien cesa el día 10 de
un periodo de 31 cobra ~3× lo suyo.

El encabezado de la 0164 lo justifica con una premisa **falsa**: dice que un
rango parcial se calcula bien porque «es lo que usa la pantalla de planilla con
el periodo en curso». No lo es — la pantalla usa `fn_proyeccion_periodo`
(0105:493), que pasa el periodo **entero**; lo parcial viene de que aún no hay
marcajes, no del rango.

**Seis de siete casos cuadran al segundo decimal** con la proporción que predice
el divisor. La séptima, **Ytamar Cueva**, no: 1.53× pagado contra 1.11× que
justifica el rango. Unos S/45 vienen de otra cosa y hay que mirarla aparte.

⚠️ **La prueba 130 no puede cazarlo**: compara la liquidación contra
`fn_planilla_calcular` con el **mismo** rango parcial. Se compara consigo misma.

#### 2 · El doble registro: **S/1,145.87 en 6 personas**, periodo 28/06–28/07

`liquidacion_pagada` aparece en **un solo archivo de todo el repositorio** (la
0167). Ni `fn_planilla_calcular`, ni `fn_planilla_congelar`, ni la pantalla de
Planilla la leen jamás. La etiqueta «ya no está» es puramente visual.

Las seis dicen **«primero el periodo, después la liquidación»**: el 28/07 se
cerró el periodo con ellas dentro —habían cesado entre el 16 y el 25— y después
se pagaron sus liquidaciones, que volvían a incluir ese mismo mes.

**Si el dinero salió dos veces solo lo dice el extracto bancario.** El sistema lo
tiene registrado dos veces; eso es lo que se puede afirmar.

#### Lo que ya está hecho

Las dos cosas que esta sección esperaba **están aplicadas en producción el
2026-08-13**, comprobadas pidiéndole el `md5` a producción y no por la fecha del
commit:

- **El cartel** — la [`0210`](../supabase/migrations/0210_la_planilla_ve_la_liquidacion_que_ya_se_pago.sql)
  hace que la pantalla de Planilla diga, junto a quien cesó a mitad de mes, que
  ya cobró su liquidación: cuándo y cuánto. Sigue siendo un cartel y no una
  exclusión automática, a propósito.
- **El divisor** — salió como la
  [`0239`](../supabase/migrations/0239_la_hora_vale_lo_que_vale_el_mes_no_lo_que_dura_la_consulta.sql),
  no como la «0211» que esta tabla esperaba. `fn_planilla_calcular` ya no saca el
  divisor del rango que se le pasa: **el rango decide QUÉ entra —marcas,
  feriados— y el periodo cuánto vale la hora**. Los siete llamadores que pasan el
  periodo entero no se movieron ni un céntimo; la única llamada cuyo resultado
  cambia es la de `fn_liquidacion`.

Y el 2026-08-14 se cerró también el mecanismo, que era lo que quedaba vivo:

- **La liquidación deja de cobrar dos veces el mes** — la
  [`0243`](../supabase/migrations/0243_la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago.sql)
  le resta al sueldo del periodo lo que la foto del pago ya registra para esa
  persona. Si el periodo no está congelado no hay nada que restar y el resultado
  es idéntico al de antes, al céntimo.
- **Y la 0243 deja de pagar de menos y de atascar el cierre** — la
  [`0244`](../supabase/migrations/0244_la_0243_deja_de_pagar_de_menos_y_de_atascar_el_cierre.sql),
  seis bordes que la anterior dejó abiertos. El grave: restaba también la foto de
  un periodo **revertido**, donde el dinero nunca salió (S/1,393.27 donde tocaban
  S/2,143.27). Los otros: una foto negativa inflaba, `congelar_pendientes()`
  abortaba sobre un mes histórico, y el freno de congelar no se levantaba al
  aplicar el descuento — podía dejar el cierre del mes sin salida.

Las dos verificadas pidiendo el `md5` a producción antes y después de pegar.

El botón **«💸 Ya le pagué aparte»** (`planilla/page.tsx:1268`) sigue siendo la
vía para el periodo en curso: registra el descuento y deja el total en cero. Y
ahora la cifra que descuenta ya es de fiar, que era la objeción para no usarlo.

⚠️ **Y una trampa que costó un rechazo en producción, para quien pegue SQL acá:**
un comentario NO es inerte. El editor de Supabase trocea el script antes de
mandarlo y su troceador no ignora los comentarios, así que un delimitador de
dólar citado dentro de un `--` —escribir `do $mig$` al explicar otra migración—
parte el script por donde no es y falla con un error que apunta a otro sitio
(`relation "v_src" does not exist`). Ninguna prueba local lo caza: psql sí lee
comentarios.

#### Lo que queda por hacer

| Qué | Cuándo |
|---|---|
| ~~**Anular la liquidación de Rufina Salvatierra**~~ | ✅ **anulada el 2026-08-14**. Versión 2 anulando la 1, con el motivo escrito; la v1 sigue visible. La anulación nombró el descuento de S/358.73 que queda vivo y **se queda**: ese es el adelanto que sí se le pagó, no un descuento dictado por el freno |
| **Revisar el extracto** de finales de julio para las seis, y el de agosto para ella | esta semana. Es lo único que distingue «registrado» de «pagado» |
| **Decidir persona por persona** qué se hace con lo que sí haya salido de más | después del extracto: sin él, no se sabe qué hay que decidir |
| **Decisión pendiente de Felipe:** la rama que falta en el aviso de `fn_liquidacion` | sin fecha. Es donde la frase «quedan descuentos vivos» llegaría a los ojos que deciden, pero son 12.821 caracteres que se pegan a mano para reescribir algo que funciona. Hoy el aviso llega igual, porque el único camino para anular es el SQL Editor |

⚠️ **CUIDADO CON ESTA SECCIÓN: sus cifras son de lo REGISTRADO, no de lo
transferido.** El 2026-08-14 se descubrió cómo se rompe esa suposición.

**El caso de Rufina, que es el patrón.** Su liquidación figura pagada el 10/08
por S/1,106.82 y **ese dinero nunca salió del banco**: estaba en periodo de
prueba, no llegó a entrar a planilla, y lo único que se le pagó fue un adelanto
de S/358.73 el 06/08, fuera de planilla. Alguien apretó «Liquidación pagada» y el
sistema congeló una foto de algo que no ocurrió.

Y el importe estaba mal por partida doble: se congeló **tres días antes** de que
la [`0239`](../supabase/migrations/0239_la_hora_vale_lo_que_vale_el_mes_no_lo_que_dura_la_consulta.sql)
llegara a producción, así que salió con el divisor viejo — inflado unas 3.1
veces. Lo que de verdad ganó del 29/07 al 07/08 son **S/298.73**, leído en la
pantalla ya corregida. O sea que con el adelanto cobró S/60 de más, no mil.

**Nadie cobró de menos.** Y de lo que parece cobrado de más, el sistema solo
puede afirmar lo que tiene registrado: **si el dinero salió, lo dice el extracto
bancario y nada más**. Esa frase ya estaba escrita más arriba desde el 10-08; el
caso de Rufina demuestra que no era una cautela retórica.

### A.2.c · Los CUSPP ya están cargados — quedan dos, y dos falsos positivos

**Resuelto el 2026-08-13.** La columna estaba vacía de punta a punta el
2026-08-10; hoy tiene **15 códigos**, cargados desde la hoja del contador
(«072026 Planilla CAYLA Felipe.xlsx») con
`scripts/sql-manual/ficha_cuspp_2026-08-13.sql` — fuera de git, lleva DNI.

**Por qué importaba.** El CUSPP es el identificador de la persona dentro del
sistema privado de pensiones: es lo que permite que el aporte declarado llegue a
**su** cuenta individual y no se quede sin atribuir.

**Se emparejó por DNI y no por nombre**, y no es un detalle de implementación: en
el equipo hay **dos Ramírez Gomez**, y la hoja trae el código de Sandra Melissa.
Por nombre se le habría escrito a Lizzelott Estefany — el aporte de una a la
cuenta individual de la otra.

**Lo que falta, y es corto:** el CUSPP de **Carmen Sanándres** (LIM, Profuturo) y
de **Lizzelott Estefany Ramírez Gomez** (CCO, Integra), que no venían en la hoja.
Se piden al contador. Aparte, **Kerin Guevara** (TRU) no tiene régimen de pensión
cargado: primero eso, y si sale ONP no lleva CUSPP.

**Los dos falsos positivos de la pantalla ya están corregidos y desplegados**
(2026-08-14).
`/admin/datos-personales` le pedía «falta CUSPP» a **Catherine Pereyra** y
**Claudia Pereyra**, que cobran por **recibo por honorarios** (ver
[A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado)). Un
locador no entra al T-Registro como trabajador: ese aviso no lo podía completar
nadie, nunca — y un aviso permanente e imposible es lo que enseña a ignorar los
avisos que sí importan.

La condición vive ahora en `leCorrespondeCuspp` (`packages/shared/src/vinculo.ts`)
y no suelta en la pantalla, porque son **dos** las que preguntan lo mismo: el
aviso de ficha incompleta y la exportación del padrón al contador, que también
lleva la columna CUSPP. Escrita dos veces, la exportación habría seguido pidiendo
lo que la pantalla ya dejó de pedir. Y usa `esPrestadorDeServicios`, no un
`!en_planilla`: si el campo no viaja en el JSON, el defecto seguro es **seguir**
pidiendo el CUSPP a las veinte que lo necesitan, no dejar de pedírselo en
silencio. Ese caso está en `tests/vinculo.test.ts`.

Por el mismo motivo dejó de pedírsele a una locadora el **régimen de pensión**:
CAYLA no le retiene aporte, así que ese dato no es de la empresa.

De paso: que las dos locadoras **tengan un régimen de AFP asignado** es en sí un
indicio más de los que describe A.2.b. **Decisión de Felipe (2026-08-13): se
queda.** Después de la 0242 ese dato no alimenta ningún cálculo, y saber en qué
AFP están es información útil. No volver a proponer borrarlo.

**Sobre el CHECK que se había descartado por falta de datos:** ahora hay 16
códigos reales y los 16 tienen la misma forma —6 dígitos · 5 letras · 1 dígito—
y las 5 letras se derivan del nombre (inicial del nombre, inicial de cada
apellido, 4ª letra de cada apellido). El script lo comprueba fila por fila, y es
lo que da confianza de que ninguna se corrió al copiar la hoja. Pero **sigue sin
ponerse un CHECK**, y ahora por una razón medida y no por falta de datos: 16
casos no prueban que un CUSPP antiguo, o el de alguien con un solo apellido,
tenga esa forma. La validación vive en el script que carga, donde un rechazo se
revisa a mano; en la columna, rechazaría en silencio un código legítimo.

### A.2.c.bis · La guarda que impide retenerle AFP a un locador no está escrita

> **HOY NO CUESTA NADA.** Felipe confirmó el 2026-08-13 que a los tres locadores
> **nunca se les ha retenido AFP**, y es coherente con lo medido: su base es 0
> porque nadie les llenó `sueldo_base_legal`. Esto **no es plata mal pagada y no
> hay nada que devolver.** Es un riesgo latente, y el valor de anotarlo es que la
> protección que hoy funciona **no está escrita en ninguna parte**: funciona por
> casualidad.
>
> **✅ CERRADO. La 0242 está aplicada en producción** (2026-08-13). El md5 de
> partida se confirmó en el SQL Editor antes de pegarla, y las cinco
> comprobaciones salieron en verde: las 4 marcas nuevas puestas, la guarda de la
> base presente, y la 0239, la 0236 y la 0233 intactas. Con prueba propia
> (`supabase/tests/183_un_locador_no_tiene_base_imponible.test.sql`).

**Qué es exactamente el riesgo.** El descuento previsional es
`base imponible × tasa`, y hoy da cero para un locador porque su base es cero. Pero
la base es cero **por un dato en blanco, no porque el sistema sepa que es locador**.
El día que alguien abra su ficha en `/admin/equipo` y confirme su base legal —una
acción normal, con buena intención, en un campo que el panel pide— empieza a
retenérsele AFP en silencio. Nadie relacionaría las dos cosas.

Y hay un segundo camino, más corto: marcarle **`con_hijos`** a una locadora le paga
S/113 de asignación familiar y además le abre base para el descuento, incluso con
`sueldo_base_legal` en blanco.

**Medido el 2026-08-13** contra la función vigente (`fn_planilla_calcular`, md5
`7d67ff3c1d769ebffc3de0af20ab83fe` = 0239), con cuatro locadoras idénticas salvo
esas dos columnas. Salió de preguntarse qué hace el sistema con la AFP después de
cargar los CUSPP. Los montos de abajo son **lo que pasaría**, no lo que pasó:

A un locador no se le retiene AFP: la locación de servicios no genera retención
previsional del pagador. El encabezado de la 0193 dice que eso ya está a salvo
porque «su básica es 0». **Es cierto solo si alguien le puso `sueldo_base_legal`
en NULL a mano** — y esa columna tiene `DEFAULT 1130.00` (el RMV, 0103).

| `sueldo_base_legal` | `con_hijos` | básica | asig. familiar | **AFP retenida** |
|---|---|---|---|---|
| 1130 (el DEFAULT) | sí | 1192.09 | 113.00 | **168.62** |
| 1130 (el DEFAULT) | no | 1192.09 | 0.00 | **154.02** |
| NULL | sí | — | 113.00 | **14.60** |
| NULL | no | — | 0.00 | 0.00 |

**Son dos defectos y no se mezclan:**

1. **La básica.** El descuento de pensión es `bri.base × tasa` y es **el único
   concepto sin guarda de vínculo**. Todos los demás la llevan escrita: EsSalud y
   movilidad (0117), educación (0120), sobretasas (0193). Este descansa en que la
   base sea 0 — y lo decide el default de una columna. Que hoy funcione o no es
   una coincidencia, no un diseño.
2. **La asignación familiar.** Entra al pago **y** a la base sin condición de
   vínculo, y es la única vía que inventa base incluso con `sueldo_base_legal` en
   NULL. Aparte del descuento, cobrarla ya está mal: la Ley 25129 es para
   trabajadores del régimen laboral privado. Y es el argumento exacto de la 0117
   con la movilidad — **el concepto que protege a una trabajadora de planilla es
   el que incrimina en un RxH**. Un locador que cobra asignación familiar es un
   indicio de laboralidad más para
   [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).

**Lo que EsSalud sí hace bien:** cero en las cuatro filas. La guarda de la 0117
sigue en pie, y eso acota el problema — es previsional, no de aportes de la
empresa.

**Cómo lo arregla la 0242.** Guarda la base imponible COMPLETA —
`case when pe.en_planilla is not true then 0 else …` — y no cada término suyo, para
que un concepto que se agregue mañana quede excluido sin que nadie tenga que
acordarse; y le pone la condición de vínculo a la asignación familiar en **los dos
sitios** donde vive (el concepto del JSON y el término del `total`): arreglar solo
uno dejaría la boleta mostrando 0 mientras el total lo sigue cobrando.

Medido después de aplicarla en local: las cuatro locadoras quedan idénticas entre
sí y su total es exactamente su pago por horas — ya no depende de
`sueldo_base_legal` ni de `con_hijos`. Y **el testigo de planilla no se movió ni un
céntimo** (AFP 195.73 · asignación 113.00 · EsSalud 136.34 · provisiones 276.71,
iguales antes y después). Eso es la mitad del valor de la prueba `183`: apagarle el
descuento a un locador y de paso romperle la retención a quien sí aporta habría
sido mucho peor que el defecto original, y ninguna pantalla lo mostraría.

**Lo que sigue igual, y es deliberado:** el pago por horas de un locador. Es el
razonamiento de la 0085 que la 0117 repitió — medir horas para saber cuánto pagar
es medir un RESULTADO; fiscalizar una CONDUCTA es la prueba de subordinación.

**Para volver a medirlo en dos segundos cuando haga falta:**
[`que_pasa_con_la_afp.sql`](../scripts/sql-manual/que_pasa_con_la_afp.sql). Su
BLOQUE 2 no rehace la aritmética, le pregunta a `fn_planilla_calcular` por el
periodo vigente y devuelve una fila por cada locador con retención. Lo esperado
—y lo que Felipe ya confirmó por su lado— es **cero filas**. Queda escrito con la
consulta al lado por la misma razón que A.2.d: un riesgo latente sin forma de
volver a medirlo es una frase que envejece sola.

### A.2.d · Dos campos para «¿tiene hijos menores?» — uno paga y el otro declara

**Medido el 2026-08-10: hoy no cuesta nada.** De las 21 personas activas en
planilla, las 21 concuerdan. Cero desacuerdos, cero fichas sin el dato. Esto
queda escrito como riesgo latente, no como pendiente urgente — y con la consulta
que lo vuelve a medir en dos segundos:
[`los_dos_campos_de_hijos_no_se_hablan.sql`](../scripts/sql-manual/los_dos_campos_de_hijos_no_se_hablan.sql).

| Campo | Quién lo escribe | Qué hace |
|---|---|---|
| `personas.con_hijos` (0025) | pantalla de **Equipo**, con `fn_set_con_hijos` | **decide el pago** de los S/113 en `fn_planilla_calcular` |
| `datos_personales.hijos_menores` (0061) | pantalla de **Datos personales** | **es lo que sale en el padrón** al contador |

**Nada los mantiene de acuerdo.** Ninguna migración menciona los dos a la vez;
ninguna pantalla escribe los dos. Comprobado con `grep` sobre
`supabase/migrations` y sobre `apps/web`. Que hoy concuerden es mérito de quien
los ha ido llenando a mano, no del sistema.

Lo que puede pasar el día que se despisten: marcar «sí tiene hijos» en la ficha,
que el padrón se lo declare al contador, **y que la planilla abone S/0** porque
`con_hijos` se quedó en su `false` por defecto. O al revés — cobrar los S/113
mientras el papel que emite la empresa dice que no corresponden.

⚠️ **Y ojo con el arreglo fácil.** Fusionarlos en un solo campo toca el cálculo
de planilla, así que va con auditoría empírica contra el Postgres local en
`BEGIN … ROLLBACK`, como manda el `CLAUDE.md`. Lo barato y sin riesgo mientras
tanto sería que la pantalla de Datos personales **avise** cuando los dos
difieran: ya tiene dos comprobaciones cruzadas de esa forma exacta —cobra
asignación sin hijos registrados, y su inversa— y ninguna mira `con_hijos`.

*(De aquí salió también el arreglo del padrón que ya está hecho: imprimía «NO»
donde la verdad era «no se sabe». Ver `siNoSinDato` en
`packages/shared/src/labels.ts`.)*

### A.3 · Datos que hacen falta para seguir

**0) Nadie tiene contacto de emergencia — las 25, sin una sola excepción.**
Medido el 2026-08-07 con
[`que_falta_en_las_fichas.sql`](../scripts/sql-manual/que_falta_en_las_fichas.sql).
Si alguien se corta con una máquina en el taller de Lima o se descompensa en
tienda, **no hay a quién llamar**, y ese es el único momento en que el dato
sirve. Felipe los carga desde `/admin/personas`. En la misma pasada faltan **13
celulares** (decisión suya: van después) y la **fecha de nacimiento de Janis
Revilla**, sin la cual su bono de onomástico no se dispara nunca — la única del
equipo a la que le falta.

Las 20 de planilla están completas en lo que toca a plata: banco, cuenta,
documento y nombre legal. Lo que falta es todo del lado de **poder contactarlas**.
Corre la consulta para ver cómo va; ordena por quién tiene más huecos.

**0-bis) Tres correos hay que corregir a mano** (medidos el 2026-08-10 con
[`mediciones_antes_de_validar.sql`](../scripts/sql-manual/mediciones_antes_de_validar.sql)).
Quiénes son lo dice
[`quien_tiene_el_correo_mal.sql`](../scripts/sql-manual/quien_tiene_el_correo_mal.sql),
que además dice **dónde** se corrige cada uno — con cuenta creada el correo es
el usuario de acceso y la ficha no lo puede tocar, así que va por
`/admin/cuentas`.

- **Uno no tiene forma de correo.** Esa persona figura como ficha completa, sale
  así en el padrón que va al contador, y al intentar invitarla el sistema
  responde «no tiene correo registrado» — que es falso: lo tiene, mal escrito.
  Son dos estados distintos y la pantalla los confundía.
- **Dos están guardados con mayúsculas.** La pantalla ya no falla por eso (se
  comparaba en minúsculas contra el valor crudo, así que daba «cambió» para
  siempre y cada guardado terminaba en un error rojo y falso), pero el dato
  sigue en mayúsculas. Bajarlo va en migración, no en un `update` pegado a mano:
  un correo que es un login tiene consecuencias que hay que dejar escritas.

**Y lo que la misma medición descartó, para no volver a mirarlo:** ni un
documento sin dígitos, ni uno fuera del patrón que ya exige la 0125, ni una
cuenta bancaria con letras, ni un valor de `estado_civil` o
`grado_instruccion` fuera de `enums.ts`, ni una sede huérfana en
`parametros_laborales`. Los agujeros de validación que quedan son **teóricos
hoy**; valen por lo que impiden mañana, no por lo que haya guardado.

**a) Quiénes estudian y cuánto cuesta su curso** (del tipo `aurora 1 →
universidad S/520`). Con el nombre y el monto alcanza; se cargan de a uno en
`/admin/educacion` o con
la pantalla `/admin/educacion`. **Es la única de las
tres compensaciones que se puede destrabar hoy sin escribir una línea de
código** — `asignaciones_educacion` sigue vacía.

**b) La fecha de acreditación de CAYLA en el REMYPE.** Decide si queda algún
frente abierto de asignación familiar: quien haya ingresado antes de esa fecha se
rige por el régimen general, donde sí es exigible. La persona más antigua ingresó
el **2025-01-02**, así que si la acreditación es anterior, el frente es **cero**.

**c) El refrigerio real**, que deja el sustento de la movilidad atado a tus datos:

```sql
with dia as (
  select m.persona_id, (m.timestamp_marca at time zone 'America/Lima')::date as f,
         min(case when m.tipo = 'salida_almuerzo'  then m.timestamp_marca end) as sale,
         min(case when m.tipo = 'retorno_almuerzo' then m.timestamp_marca end) as vuelve
  from marcajes m
  where m.anulada_at is null and m.timestamp_marca >= now() - interval '90 days'
  group by 1, 2
)
select count(*) as dias_con_marcas,
       count(*) filter (where sale is not null and vuelve is not null) as dias_con_4_traslados,
       round(avg(extract(epoch from (vuelve - sale)) / 60) filter (where vuelve > sale)) as refrigerio_min,
       count(*) filter (where extract(epoch from (vuelve - sale)) / 60 >= 60) as dias_1h_o_mas
from dia;
```

### A.4 · Las dos comprobaciones de datos, que ahora se responden solas

*Acá había cuatro nombres escritos a mano. Tres cerraron y uno resultó ser una
decisión (ver [`historico.md`](historico.md)). Lo que queda son las dos preguntas
de fondo, convertidas en consultas: una lista de nombres envejece, una consulta
no.*

**¿Alguien inactivo conserva salario vigente?** Es plata que puede pagarse a
quien ya no trabaja. Debe devolver **cero filas**:

```sql
select p.nombres || ' ' || p.apellidos as persona, p.estado,
       a.salario_mensual_soles as salario_vigente, a.vigente_desde
from personas p
join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
where p.estado <> 'activo'
order by p.apellidos;
```

**¿Alguien en planilla lleva un mes sin marcar?** Puede ser vacaciones, permiso,
o que no esté marcando y nadie lo haya visto:

```sql
select p.nombres || ' ' || p.apellidos as persona, s.codigo as sede,
       max(j.fecha) as ultimo_dia_marcado
from personas p
join sedes s on s.id = p.sede_base_id
left join jornadas j on j.persona_id = p.id and j.entrada_ts is not null
where p.estado = 'activo' and p.en_planilla and not p.sueldo_fijo
group by 1, 2
having max(j.fecha) is null or max(j.fecha) < current_date - 30
order by 3 nulls first;
```

**~~El hueco de numeración 0108~~ — ✅ cerrado.** Los cinco huecos (0031, 0033,
0108, 0133, 0139) están investigados y explicados uno por uno en
[`scripts/hooks/huecos-conocidos.txt`](../scripts/hooks/huecos-conocidos.txt), y el
hook solo avisa de los que **no** estén ahí. La 0108 se descartó: su contenido lo
cubren la 0111, 0117, 0118, 0122, 0142 y 0150, y lo único exclusivo que tenía era
un `fn_planilla_calcular` del 29/07 con tarifa única de S/6 — fusionarlo habría
revertido ocho migraciones de planilla. Se recupera con
`git checkout 1b54c02 -- supabase/migrations/0108_*.sql` si algún día hace falta.

**~~El rango `caylo` pagaba educación sin techo~~ — ✅ cerrado el 2026-08-06.**
La 0140 lo retiró del catálogo por un solo lado: le borró el techo y lo dejó
fuera de `categorias_laborales`, pero los CHECK de dos tablas lo seguían
aceptando y el desplegable de Equipo lo seguía ofreciendo. Como
`fn_educacion_respeta_el_tope` «falla abierto a propósito» cuando no encuentra
techo, en vez de bloquear **pagaba**: con el comprobante de S/727, S/545.25 en
vez de S/180. La [`0178`](../supabase/migrations/0178_caylo_deja_de_poder_asignarse.sql)
lo sacó de los dos CHECK y reasigna a `cayla` a quien lo tenga (mismo nivel,
misma base, **no cambia lo que cobra**). Felipe la pegó y verificó los dos CHECK.
La pantalla ya está en producción: el desplegable ofrece seis rangos, sin `caylo`.

*Queda un SELECT por correr, y no urge:* si alguien **estaba** en `caylo`, la
0178 lo pasó a `cayla` en silencio y conviene decírselo — cobra igual, pero su
nivel se llama distinto en la boleta. La consulta está en la cabecera de
`aplicar_0178.sql`; busca el rastro en `correcciones_auditoria`.

**Lo que esto dejó como lección, y vale más que el arreglo:** el agujero no fue
que `caylo` existiera, fue que existiera **sin techo cargado**. La prueba
[`139`](../supabase/tests/139_caylo_deja_de_poder_asignarse.test.sql) no vigila
`caylo`: compara el CHECK contra `categorias_laborales` y exige que ninguna
categoría se quede sin techo. **Pero solo en CI.** `fn_educacion_respeta_el_tope`
sigue fallando abierto en producción, así que una categoría nueva cargada sin su
techo repite esto exacto. Está sin decidir si esa función debe pasar a bloquear.

---

## B · Lo que falta construir

| Qué | Bloqueado por |
|---|---|
| **Las bases declaradas** de los cuatro rangos altos — y hay que bajar **los dos campos**, `sueldo_base_legal` **y** `salario_mensual_soles` | confirmar los montos finales |
| **Cargar las declaraciones de ruta firmadas** | **de Felipe. Plazo: 28/08/2026.** El sitio donde subirlas ya existe |
| **Indicador del umbral de 20 trabajadores** — promedio corrido del ejercicio, con aviso al acercarse | nada. **Acordado: se construye después de cerrar el Seguro de Vida Ley** |
| **Versionar la RMV a S/1,300** cuando se publique el decreto | que salga la norma |
| **Imprimir y firmar las ~20 renovaciones** — la pieza ya existe (`/admin/contratos`) | **revisión legal del texto**, y tres arreglos de SQL que esperan el md5 de producción |

### El generador de contratos, tras la auditoría del 2026-08-24

La pieza está construida y auditada. **229 agentes, 74 hallazgos brutos, 18
sobrevivieron** a tres escépticos independientes cada uno. Ocho tocaban el papel
y están arreglados (PR #57); el detalle vive en ese commit, no acá.

**El que enseña algo:** el defecto grave no lo encontró la auditoría — lo
encontró Felipe diciendo al pasar «todo mi personal tiene contrato, solo que aún
no se ha escaneado». La pantalla decía «sin contrato» porque el generador no
tenía filas previas, y de esa confusión salía el TIPO del contrato: las veinte
renovaciones habrían salido como contratos nuevos, con un período de prueba de
tres meses «sin expresión de causa y sin derecho a indemnización» impreso a gente
con años de casa. Se arregló, y horas después la auditoría encontró **la misma
puerta por otro lado**: el tipo tampoco se reponía al cambiar de persona en el
desplegable. Un agujero cerrado en un sitio no está cerrado.

**Lo que falta antes de imprimir:**

1. **La revisión legal del texto.** No la ha hecho nadie. El plan la dejó marcada
   como obligatoria y sigue sin hacerse.
2. **Tres arreglos en SQL**, confirmados, que esperan el md5 de `fn_contrato_registrar`
   y `fn_contrato_anular` pedido **a producción**:
   - falta la política `UPDATE` del bucket `contratos` — si el RPC falla después
     de subir el archivo, ese escaneo no se puede volver a subir nunca;
   - firmar un borrador viejo mueve `personas.fecha_fin_contrato` **hacia atrás**
     sin ningún freno;
   - anular un contrato ya firmado no revierte esa fecha: la persona se queda con
     el vencimiento de un documento declarado nulo.

**Y una decisión de negocio que el código no puede tomar.** El contrato se emite
siempre bajo el **art. 57** del TUO del D. Leg. 728 —«inicio o incremento de
actividad»—, cuya duración máxima es de **tres años**; el art. 74 pone cinco al
conjunto de contratos sujetos a modalidad. Pasado el tope, el art. 77
desnaturaliza el vínculo a indefinido **por ley, sin que nadie lo decida**. Desde
el 2026-08-24 la pantalla lo **avisa** al fijar la fecha de fin, pero nadie ha
medido a quién le pasa: la respuesta necesita las fechas de ingreso reales, que
solo están en producción. Con casi toda la planilla a plazo fijo, además, la
causa objetiva —«el volumen no puede ser absorbido por el personal permanente»—
es la que hay que poder sostener ante una inspección.

**Descartado a propósito:** archivar en el sistema los contratos de papel
anteriores (decisión de Felipe, 2026-08-24 — las renovaciones los reemplazan).

### La 0128 sigue escrita y sin llamar

`fn_fijar_base_declarada(rango, monto, vigencia, omitir[])` baja **los dos**
campos que intervienen en el pago al mismo monto, versionando el salario vía
`fn_set_salario`. La migración **crea la función y no la llama**: crearla no mueve
ningún pago, llamarla sí.

**Los montos por rango no están decididos.** La cifra que circulaba acá
—colibrí/cayla 1,130 · support 1,290 · aurora 1,500 · oráculo 1,810 · archicaylo
2,670— fue un ejemplo ilustrativo de cuando se diseñó el sistema, no una
decisión de Felipe (aclarado el 2026-08-18); se retira para que nadie la lea
como acordada. Los montos reales, cuando se fijen, y las excepciones nominales
van en `scripts/sql-manual/aplicar_0128.sql` (ignorado en git por PII) — nunca
en este archivo.

**Por qué no se ha llamado — actualizado 2026-08-18, verificado contra el
código vigente (no solo contra este párrafo):** movilidad ✅ encendida ·
educación ✅ implementada y sumándose en `fn_planilla_calcular`
(`monto_educacion`, vigente en la 0263) · bono de onomástico ✅ implementado
(`0165`, S/180 desde el 29/07/2026, entra al pago por el bucket `bonos`). Los
tres conceptos SÍ están en el cálculo de planilla — lo que este documento tenía
mal. Lo que sigue sin confirmarse es si cada persona tiene sus datos cargados
(p. ej. la asignación de educación es por persona y contra comprobante). Y
`fn_fijar_base_declarada` **sigue sin llamarse**: nadie ha bajado ningún sueldo
base todavía, así que hoy la base sigue siendo la de antes.

El método para decidir esto sigue siendo medir contra Postgres local, en
`BEGIN … ROLLBACK`, con casos reales — no se repite acá con una cifra concreta
porque la que había era la misma que se retiró arriba por no ser una decisión.
Y como la educación es **por persona y contra comprobante**, a quien no estudia
bajarle la base le recorta el sueldo sin nada que lo reponga — para esa persona
se usa `p_omitir`, o una base propia más alta.

### El indicador del umbral de 20, y por qué vale construirlo

Dante zanjó las utilidades para 2025 y 2026, pero con una foto: 5 y 13 de
promedio. Ese 13 es un accidente del año de crecimiento —de enero a junio hubo
entre 5 y 8 personas, y recién desde julio hay 19—. **Si CAYLA mantiene 19 los
doce meses de 2027, el promedio de 2027 es 19.** A una contratación del umbral.

Y la persona número 21 no cuesta su sueldo: cuesta su sueldo **más el 8% de la
renta imponible de todo el ejercicio** repartida entre todos (D.L. 892,
comercio). Sobre los S/63,655 de 2025 serían ~S/5,092 al año que hoy no se ven en
el momento de decidir la contratación. El sistema tiene todos los datos para
calcularlo solo y mostrarlo **antes** de que se firme el contrato.

### Sobre la RMV

El alza se anunció el 28/07/2026 y **el decreto no está publicado**. Cuando
salga, son dos sentencias por cada clave —`rmv` y `asignacion_familiar`— escritas
en las cabeceras de la 0116 y la 0122. Los periodos ya pagados quedan intactos.

⚠️ **Ojo con el plazo, porque Dante lo describió mal.** Dijo que hay que esperar
al Congreso y a la promulgación. La RMV **no se fija por ley**: se fija por
**Decreto Supremo del Ejecutivo**, previa consulta al Consejo Nacional de
Trabajo, conforme al art. 24 de la Constitución (la subida a S/1,130 fue el
**D.S. 006-2024-TR**). Puede publicarse de un día para
otro y regir desde el 1° del mes siguiente. **La vigilancia se mide en semanas,
no en meses.** Donde sí puede tener razón es en el bono compensatorio para MYPE:
eso es gasto público y probablemente sí necesita norma con rango de ley.

### La fila general de movilidad vale S/ 10.00 — decisión tomada, se queda

No es un descuido pendiente sino una **red deliberada** (Felipe, 2026-08-06):
quien esté en una sede sin tarifa propia cobra S/ 10.00 en vez de cero. Conviene
saber de dónde sale ese 10: es la **tarifa original de Trujillo** —su sustento lo
dice, «colectivo urbano de Trujillo a S/2.50 por tramo»—, que quedó sin
`vigente_hasta` cuando la 0142 abrió las filas por sede.

**El escenario que la activa: abrir una sede nueva.** Esa gente cobra S/ 10.00
desde el primer día sin que nadie haya mirado el pasaje de esa ciudad, y sin
aviso. Si algún día se prefiere que un dato faltante se note en vez de
rellenarse, se cierra con `vigente_hasta` y pasan a S/ 0.00 — hoy eso no movería
la plata de nadie.

---

## C · Lo que se descartó y no vuelve

Cinco cosas que sonaron graves y se cayeron al verificarlas. Quedan acá para que
no vuelvan a costar tiempo.

| Se dijo | La verdad |
|---|---|
| El límite del RER de 10 trabajadores por turno | **CAYLA está en Régimen MYPE Tributario** desde 2023 (ficha RUC). El RER no aplica. **No hay que mover ningún horario** |
| «Sobre 25% de conceptos no remunerativos se activa la presunción de salariedad» | **No existe ese umbral en la ley.** Era una regla de dedo mía |
| La asignación familiar se debe a todos los que tengan hijos | El régimen de **pequeña empresa NO la incluye** — las palabras aparecen cero veces en el TUO de la Ley MYPE y en la Ley 32353, leído en texto primario. **Pero a quien ya la cobra no se le puede quitar**: sería reducción unilateral de remuneración (art. 30.b) |
| Un pacto colectivo blinda la movilidad | Solo es requisito del inciso g) para festividades. Art. 9 TUO CTS: la denominación es irrelevante. **La firma no blinda, incrimina** |
| El SCTR es obligatorio por el taller | **No.** Se revisaron las 270 actividades del Anexo 5: la confección de prendas (CIIU 141x) no está. Evita S/1,600–2,500/año de un seguro que nadie exige |

**Y el techo que ordena todas las multas:** todas las de una misma inspección de
SUNAFIL topan en el **1% de los ingresos netos del año anterior** (art. 48.1-A del
Reglamento de Inspección). Con ~S/900,000 de facturación el techo es **~S/8,000**,
no las seis cifras que suman los hallazgos por separado. **Pero no se aplica
solo**: exige presentar la constancia de REMYPE y sustentar los ingresos netos.
Sin esos dos papeles se cobra el nominal.

---

## D · Consultas útiles que ya existen

| Archivo | Para qué |
|---|---|
| `huella_del_esquema.sql` | **¿Producción dice lo mismo que el repositorio?** Una fila: funciones, candados, columnas, y si queda texto con acentos rotos. Empieza siempre por aquí |
| `que_funcion_cambio.sql` | Solo si la anterior dice que las funciones difieren **con el mismo conteo**: manda las 199 huellas y señala cuál |
| `rescatar_lo_que_solo_vive_en_produccion.sql` | ⚠️ **Léelo antes de tocar cualquiera de las nueve que lista.** Trae su código para traerlo al repositorio |

**Y el prólogo que hace falta seguido:** `fn_planilla_calcular`, `fn_provisiones`
y `fn_set_tipo_vinculo` exigen sesión de admin, y el SQL Editor no la tiene. Dos
líneas al inicio lo resuelven:

```sql
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and nombres ilike '%Felipe%' and auth_user_id is not null limit 1),
  true);
```

---

## El diseño remunerativo — lo que la auditoría empírica fijó

Contra Postgres local con datos reales, en `BEGIN … ROLLBACK` como manda el
`CLAUDE.md`. **Sigue siendo la base del diseño, no es historia.**

**`pago_base` se calcula sobre `asignaciones_salario.salario_mensual_soles` —el
rango completo— y NO sobre `personas.sueldo_base_legal`:**

```
pago_base = horas × salario_mensual_soles / v_base
basica    = horas × least(sueldo_base_legal, salario) / v_base
```

**Declarar menos NO reduce lo que se paga.** Sumar movilidad, educación y bono
encima del rango completo sobrepagaría por el monto entero de esos conceptos —
del orden de **S/4,900 al mes** entre las 26 personas. Por eso al fijar las bases
declaradas hay que bajar **los dos campos** al mismo monto.

Con esa corrección, en un mes **sin feriados**:

| Rango | declarado → base | + movilidad | − pensión | = total | objetivo | necesita educ. + bono |
|---|---|---|---|---|---|---|
| colibrí | 1,129.55 | +270.00 | −147.52 | 1,252.03 | 1,320 | **67.97** |
| cayla | 1,129.55 | +270.00 | −160.54 | 1,352.01\* | 1,450 | **97.99** |
| support | 1,289.49 | +270.00 | −167.25 | 1,392.24 | 1,650 | **257.76** |
| aurora | 1,499.40 | +270.00 | −194.92 | 1,574.48 | 1,890 | **315.52** |
| oráculo | 1,809.28 | +270.00 | −232.31 | 1,846.97 | 2,250 | **403.03** |
| archicaylo | 2,668.94 | +270.00 | −348.56 | 2,590.38 | 3,000 | **409.62** |

*\*La fila de cayla del fixture tiene hijos, así que incluye S/113 de asignación
familiar; sin hijos necesitaría ~S/198.*

**Los días son 27, no 26.** En un periodo de 31 días con domingos libres hay 27
laborables, así que la movilidad a S/10 da **270**, no 260.

**Los feriados oscilan el total entre S/90 y S/196 por mes.** Por eso el diseño
**no puede cerrar exacto todos los meses**, y forzarlo con educación o bono sería
el reverse-engineering que hunde los conceptos (caso Albis). Cada concepto se fija
por su propio mérito y el total aterriza cerca del rango.

### Las decisiones del diseño (2026-07-31)

**En la boleta:** lo que CAYLA paga además —el EsSalud y las tres provisiones— va
en un bloque aparte, fuera de la tabla del pago, con la leyenda «no se descuenta
de tu sueldo». **Sin total y sin porcentaje**, por decisión tomada.

| Concepto | Decisión | Amparo |
|---|---|---|
| **Movilidad** | S/10.00 por día marcado en AQP y TRU, **S/12.00 en LIM** (0142) · 4 traslados · refrigerio de 1h15 habilita almorzar en casa. **Techo: ninguna tarifa diaria pasa del 4% de la RMV** (hoy **S/45.20**), con candado en la 0152 y prueba 119 | Art. 19 e) · PLAME **0909** ✅ confirmado |
| **Educación** | 75% del comprobante, tope por rango · vale para el trabajador **y/o sus hijos**, sin tope de edad | Art. 19 f) · PLAME **0202** ⚠️ falta confirmar el cero |
| **Bono cumpleaños** | **S/180**, igual para los 26, en el mes del onomástico, sin condición de antigüedad | Art. 19 g) · PLAME **0203** ⚠️ mismo caso |
| **Pensión** | Tasa real por persona (12.84%–13.06% u ONP 13%), desde el periodo abierto | — |
| **EsSalud** | 9% con piso de la RMV, visible como aporte de la empresa | Ley 26790 art. 6 |
| **Base de beneficios** | Igual al monto declarado de cada persona | decisión de Felipe |
| **Fuera de la estructura** | Felipe y Catherine | decisión de Felipe |

**La cláusula del bono, textual.** No usar la que decía «gratificación
extraordinaria a título de liberalidad»: invocaba el inciso a), que exige que el
pago sea *ocasional*, y hacía el gasto **no deducible** (art. 44 d) LIR).

> *Asignación por cumpleaños, otorgada con ocasión del onomástico del trabajador,
> conforme al literal g) del artículo 19 del D.S. 001-97-TR. No constituye
> remuneración computable para ningún efecto legal.*

**Sobre los convenios:** la **RTF 05449-4-2007** desconoció la movilidad de 14 de
21 trabajadores por falta de convenio exhibido. El inciso e) nombra el «pacto
individual» como la vía del monto fijo. La sentencia para encender la tarifa, con
su memoria de cálculo completa, está en la cabecera de la 0118.

**El candado de la declaración NO está encendido.** Cuando el tablero esté
completo:

```sql
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('movilidad_exige_declaracion', 1, '<fecha>', '<por qué>');
```

---

## Correcciones a información que yo di mal

Quedan anotadas porque se tomaron decisiones sobre ellas.

| Lo que dije | Lo correcto |
|---|---|
| «El límite del RER de 10 trabajadores por turno es tu problema más caro» | **CAYLA está en Régimen MYPE Tributario desde 2023** (ficha RUC). El RER no aplica |
| «Sobre 25% de conceptos no remunerativos se activa la presunción de salariedad» | **Era mi regla de dedo, no una norma.** No existe porcentaje en la ley peruana |
| La cláusula del bono con «liberalidad» y «a discreción» | Invocaba el inciso a), que exige ocasionalidad, y hacía el gasto no deducible |
| «Ninguna función respeta `en_planilla`» | **Las de liquidación sí:** `fn_cts_trunca`, `fn_grati_trunca` y `fn_vacaciones_truncas` vía `fn_devenga_beneficios` |
| «Un pacto colectivo blinda la movilidad» | Solo es requisito del inciso g) para festividades. **La firma no blinda, incrimina** |
| «CAYLA es un instituto de idiomas» *(en un prompt de verificación)* | Es **CIIU 4641 — venta al por mayor de textiles**. Se descartó todo el análisis de IGV educativo que salió de ahí |
| «El problema de subir el cargo es que la URL firmada no lleva la identidad» | **Falso.** Era que Storage usa `ON CONFLICT … RETURNING` y faltaban dos políticas. Afirmado con más seguridad de la que había; lo destapó el log del contenedor, no el código |

---

## Notas del entorno

**Las pgTAP corren en esta Mac.** La clave es `db reset`, no `start`:

```bash
npx supabase db reset    # reconstruye desde cero y aplica TODAS las migraciones
npx supabase test db
```

Es la mejor verificación de una migración nueva —construye el esquema entero
desde cero— y la única forma de detectar una colisión de números: es lo que
destapó las dos `0158`, abortando con `duplicate key value violates unique
constraint "schema_migrations_pkey"`.

**`db reset` y no `db start`:** `db start` no reaplica nada si la base ya está
levantada, así que una migración nueva parece aplicar y en realidad no se probó.

**`supabase start` (el stack completo: Auth, Storage, Realtime) también
funciona** — comprobado el 2026-08-06. Hace falta para probar una subida de
archivos de punta a punta; sin él, Storage no responde y solo se puede simular
contra Postgres.

**Si las pruebas fallan todas a la vez con «relation "sedes" does not exist»**,
no es el código: el contenedor de Postgres se reinició vacío. Se arregla con `db
reset`. La base local es un laboratorio: no guarda nada que no se pueda
reconstruir.

⚠️ **Casi siempre hay varias sesiones trabajando en paralelo** — el 2026-08-06
había cinco además de la propia. Unas desde `.claude/worktrees/*`, y otras
**desde este mismo árbol**: comparten Postgres local, directorio de trabajo e
índice de git. Eso produce pruebas en rojo que no son tuyas, `estado.md`
reescrito a media edición, y un `git status` que dice `[ahead 2, behind 5]` y un
minuto después otra cosa.

```bash
./scripts/sesiones.sh
```

Dice cuáles están vivas, desde qué worktree, **cuál es la tuya**, si alguien
escribió en los últimos 10 minutos y el estado de la rama. Córrelo **antes** de
`supabase db reset`, de editar este archivo, o de fiarte de un `git status`.

No uses la lista de sesiones de la app: su campo `isRunning` dice `false` aunque
estén corriendo. El script mira los procesos del sistema, que no mienten.

Dos hábitos que se ganaron el 2026-08-06:

- **Commitea con `git commit -o <ruta>`.** El índice de git es compartido en este
  árbol: un `git add` + `commit` corriente puede llevarse dentro lo que otra
  sesión acabe de preparar.
- **No empujes si la rama lleva commits que no son tuyos.** Viajarán cuando su
  autor los empuje; publicarlos tú es publicar trabajo a medio hacer.

**Los dos guardianes que fallaban por esto ya están arreglados** (2026-08-06), y
los dos por la misma confusión — preguntaban por *el directorio de trabajo*
cuando debían preguntar por *lo que sale de esta máquina*:

| Guardián | Qué hacía mal |
|---|---|
| `scripts/hooks/numeracion.sh` | Listaba las migraciones con `ls`, así que los archivos sin commitear de otra sesión contaban como tuyos: te decía «renumera lo tuyo» por un choque que tu push ni llevaba. Ahora mira lo que agregan tus commits sobre `origin/main`. La comprobación de duplicados **sigue** mirando el árbol entero a propósito: dos archivos con el mismo número revientan tu `db reset` venga de donde venga el segundo |
| `scripts/desplegar.sh` | Frenaba por cualquier cosa sin commitear, incluidos `.sql` que el `.vercelignore` excluye — Vercel ni los sube, y el mensaje «subiría código que no está en git» era literalmente falso. Ahora lee el `.vercelignore` para decidir qué cuenta. Sigue frenando en seco si lo sin commitear es `apps/web` |

Vale la pena mirar con esa lente cualquier verificación nueva antes de
escribirla: **¿esto pregunta por lo que hay en el disco, o por lo que va a
salir?** Casi siempre es lo segundo.

**Queda un tercero con el mismo vicio, y por ahora se aguanta.** El `typecheck`
del pre-push compila el **directorio de trabajo**, no lo que subes: el 2026-08-08
frenó un push por un archivo `.tsx` que otra sesión tenía a medio editar, y al
minuto siguiente pasó sin tocar nada. Es falsa alarma, no error — se reintenta y
ya. Arreglarlo de verdad exigiría compilar contra un árbol aislado, que cuesta
más de lo que ahorra; lo que no se puede es olvidar por qué pasa y empezar a
empujar con `--no-verify`.

**El de `que_falta_pegar.sql` sí es de los buenos, y frenó dos veces el mismo
día:** el repo tenía migraciones que la consulta no listaba, así que le habría
dicho a Felipe «todo al día» ocultando justo las nuevas. Se arregla corriendo
`./scripts/que-falta-pegar.sh` y volviendo a empujar.

**Un bug que vale recordar:** `jsonb_build_object` admite **máximo 100
argumentos**. El objeto de la boleta estaba cerca del techo y cuatro campos
nuevos lo pasaron — compilaba y fallaba al ejecutarse. Ahora está partido en dos
unidos con `||`, y el generador cuenta los argumentos y falla si alguno se acerca
al tope.

---

## 🔴 Atender primero

0. **El freno del SQL a producción se puede saltar sin querer, y ya pasó dos
   veces.** El 2026-08-14 la **0243** —que cambia una liquidación por cese— quedó
   aplicada en producción con sus tres archivos **sin commitear**: el mismo estado
   exacto en el que se encontró la **0177** el 2026-08-07. Se rescató el mismo día.

   **`dame-el-sql.sh` no lo evitó, y no puede:** solo protege a quien lo usa. Si
   la migración se copia del editor —lo natural cuando la tienes abierta delante—
   el script no participa, y ni el hook de numeración ni `que-falta-pegar.sh` ven
   nada, porque los dos miran git. El agujero no está en el script: está en que
   **el camino cómodo no pasa por él**.

   **✅ La mitad barata ya está hecha** (2026-08-14):
   `scripts/hooks/migracion-sin-guardar.sh` avisa en cada push si hay una
   migración sin commitear, y distingue la recién escrita de la que **ya
   sobrevivió a un commit** — esa segunda no es trabajo en curso, es trabajo
   olvidado. No bloquea, por la regla que el propio hook ya tenía escrita para
   `types.ts`: lo que sale de la máquina se bloquea, lo que solo está en el disco
   se avisa. Con varias sesiones en paralelo, una migración a medio escribir es un
   caso legítimo constante, y frenar ahí repetiría los dos errores ya pagados
   (`desplegar.sh` el 2026-08-06 y `que-falta-pegar --check`, cuatro pushes en un
   día). Cinco casos probados, incluido el que cazó un `git add` con las rutas
   pegadas sin espacio — justo la línea que existe para copiarse.

   **Queda la mitad cara, y es la que de verdad cierra el agujero:** que
   `que_falta_pegar.sql` compare lo que `migraciones_aplicadas` dice **en
   producción** contra lo que hay **en GitHub** —no en el disco—, de modo que una
   migración aplicada y no subida salga como hallazgo desde el lado autoritativo.
   El aviso del hook depende de que alguien empuje; esto no dependería de nada.

1. **Julio: nadie tuvo descuento de pensión.** Medido el 2026-08-08 sobre el
   periodo 28-jun → 28-jul: `pension_descontada` = **S/0.00 para las 23
   personas**, y `con_tasa_de_pension` = 0. En agosto ya son 20 de 22, así que
   las tasas por régimen se cargaron entre un periodo y otro.

   **Es del contador, no del código, y hay que preguntárselo:** si él descontó
   por su lado, no pasa nada; si no, es un mes de aporte previsional sin hacer
   para todo el equipo. Pesa más que cualquier otra cosa abierta hoy — y CAYLA
   es agente de retención, así que una retención no hecha la termina pagando la
   empresa de su bolsillo.

2. **Veinte de los veintiún contratos vencen el 31 de diciembre de 2026.** Solo
   el de Paola termina antes. En una misma semana hay que decidir, redactar y
   firmar veinte renovaciones, y si una se pasa de fecha con la persona todavía
   trabajando, **el contrato se desnaturaliza a indefinido por el art. 77 del
   D.S. 003-97-TR** — no por decisión de nadie.

   El dato ya está en `personas.fecha_fin_contrato`; falta que Incidencias avise
   con antelación. Es una alerta chica, del mismo tipo que las de jornada.

3. **El terminal decide en dos sitios a la vez.** «Qué toca marcar ahora» vive en
   SQL (`fn_siguiente_tipo_esperado`) y en el navegador
   (`determinarSiguienteAccion`, `packages/shared`). Las dos ignoran ya las
   marcas anuladas, pero **arreglar una dejaba la otra rota** y nada avisa de la
   divergencia. Unificar, o al menos una prueba que compare las dos respuestas
   con los mismos datos y falle si difieren.

4. **Terminal, los «4 bordes graves» — reproducidos uno por uno el 2026-08-10.
   Tres de los cuatro no eran lo que decían.**

   | Borde | Veredicto medido |
   |---|---|
   | Marca rechazada anunciada como «Listo» | ✅ **era real a medias, y se arregló.** La cola ya guardaba la marca antes de enviar; lo que seguía mal era el CARTEL: la pantalla leía solo `ok` y tiraba `llego`, así que un rechazo del servidor se anunciaba igual que estar sin internet — «se sincronizará cuando vuelva la conexión», siendo mentira. |
   | Cola offline reenviada por UUID | ❌ **refutado.** `offline-db.ts:85` ordena por `timestampCliente`. |
   | Reloj de la Mac sin verificar desfase | ✅ **REAL Y ABIERTO.** Cero menciones de desfase en todo el terminal: el `timestamp_marca` que decide a qué día se paga sale del reloj de la Mac sin comprobar nada. Necesita decidir qué se hace cuando está corrido. |
   | Marca en dos sedes el mismo día «pierde una marca» | ⚠️ **exagerado.** No se pierde ninguna —`marcajes` es append-only— pero `fn_recalcular_jornada` hace `coalesce(v_sede_id, …)` y le atribuye el día entero a la sede donde marcó PRIMERO. Lo que sale mal es el Reporte por sede, no el pago. |

   Y el quinto que se miró de paso, `fn_auto_cierre` sin candado de periodo
   pagado: ❌ **refutado**, lo cerró la 0203 el mismo día.

5. ~~**Tardanza de más de 180 min invisible**~~ · ~~**el sistema mide la jornada
   de quien no está sujeto a horario**~~ — ✅ **los dos cerrados el 2026-08-08**
   por la [`0189`](../supabase/migrations/0189_una_tardanza_de_tres_horas_deja_de_desaparecer.sql)
   y la [`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql),
   aplicadas y confirmadas. Ver el apartado [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado)
   para lo que significaba el segundo.

6. ~~**Nueve funciones y dos columnas corren SOLO en producción**~~ — ✅ **cerrado
   el 2026-08-08.** La 0188 rescató cuatro; la
   [`0194`](../supabase/migrations/0194_el_interruptor_de_beneficios_por_persona_entra_al_repositorio.sql)
   y la [`0195`](../supabase/migrations/0195_las_cuatro_funciones_que_el_repositorio_no_conocia.sql)
   las cinco restantes. Aplicadas y confirmadas. Verificado con un `db reset`
   completo: reconstruida la base solo desde los archivos, todo sigue ahí.

   **Y lo que apareció al rescatarlas vale más que el rescate.** Lo que esas
   cuatro funciones tenían «de más» era **el candado de planilla pagada** que el
   repositorio no tenía: `fn_set_rendimiento` y `fn_quitar_rendimiento` se niegan
   a puntuar o despuntuar un mes ya pagado, y `fn_set_sueldo_base_legal` a
   cambiar la básica de quien tenga meses pagados con puntuación menor a 100.
   Cualquier migración que hubiera copiado del repositorio los habría borrado en
   silencio — lo mismo que la 0180 tuvo que reponer el mismo día.

   ⚠️ **EL INTERRUPTOR DE BENEFICIOS POR PERSONA NO ESTÁ CONECTADO.** Medido en
   producción, no deducido: `funciones_que_lo_leen: 0`.
   `fn_devenga_beneficios(p_tipo)` tiene como cuerpo entero
   `select p_tipo = 'planilla'` — mira el **tipo de vínculo**, no la columna — y
   sus cuatro consumidores la llaman con el tipo. La pantalla de Equipo dice que
   el interruptor funciona y **no hace nada**. Quien lo haya apagado para alguien
   verá a esa persona seguir acumulando CTS, gratificación y vacaciones.
   Compruébalo con
   [`quien_uso_el_interruptor.sql`](../scripts/sql-manual/quien_uso_el_interruptor.sql).

   **Conectarlo es decisión de Felipe: es dinero.** Y antes hay un problema de
   forma: `devenga_beneficios` es **un solo booleano** para los tres beneficios a
   la vez, y la decisión sobre Carlos Espejo —«grati y CTS sí, vacaciones no»— no
   cabe ahí. O se parte en tres banderas, o va por otro camino.

5. **Seguridad pendiente** (de `revision-2026-07-15/`):
   - Contraseña mínima 6 sin complejidad, sin cambio forzado en primer login —
     y son cuentas que ven salarios. **Abierto.**
   - ~~Las rutas de API devuelven el mensaje crudo de Postgres~~ — ✅ **cerrado el
     2026-08-06.** Las cuatro pasan por `mensajeDeError`, que deja pasar entero
     lo que escribimos nosotros (código `P0001`) y traduce lo demás; el detalle
     va a Sentry. `api/espejo` es máquina a máquina y devuelve un genérico a
     propósito. Lo blindan 15 pruebas en `tests/mensaje-error.test.ts`, una de
     ellas con una palabra de la lista negra que **solo** la rama `P0001` puede
     dejar pasar — las otras catorce seguían en verde con la rama desactivada.

6. **Partir `planilla/page.tsx`.** Maneja dinero, y es la pantalla más grande del
   sistema por lejos (`wc -l` lo dice; la segunda es `turnos`). Los tests SQL que
   fijan la matemática ya existen (`supabase/tests/10` y `20`); falta el refactor
   antes de seguir tocándolo.

7. **Quedan tres `"America/Lima"` sueltos** fuera de `fecha-lima.ts`, todos en
   `politica-salarial/page.tsx` (líneas 66, 77 y 236). La regla del `CLAUDE.md`
   es que no exista ninguno: el corte del día decide a qué fecha se le paga un
   marcaje. Aquí son fechas de publicación de un documento, no de pago — pero la
   regla vale igual, porque la próxima copia de esas líneas puede no serlo.

**El catálogo completo está en
[`hallazgos-abiertos.md`](hallazgos-abiertos.md)**: hallazgos vivos de una
auditoría por áreas con verificación adversaria, cada uno con su evidencia y su
arreglo.

**El patrón que se repite, y que conviene mirar antes que los síntomas:** la
misma regla escrita en dos sitios, y una corrección que arregla solo uno. Pasó
con «qué toca marcar» (SQL y navegador), con «qué es una falta» (pantalla y
documento), con «quién puede leer la planilla» (un revoke y ningún guard) y el
2026-08-06 con el formulario del cargo (escrito en una sección y no en la otra).
En todos, nadie se enteró hasta que alguien miró.

### Lo que la foto del pago sí cierra, y lo que no

**Sí:** un periodo pagado ya no puede cambiar de total en silencio. Si algo se
mueve, `fn_planilla_foto_diferencias` lo nombra persona por persona.

**No:** los periodos pagados antes de la 0096 tienen la foto *reconstruida* — es
el número del día de la migración, no el del día del pago. La pantalla de Costos
lo avisa arriba.

**Y una decisión pendiente que la 0096 hace visible:** cuando la foto y el
cálculo en vivo difieren, el sistema hoy solo lo *dice*. Nadie decidió todavía
qué pasa entonces — si se reabre el periodo, si se ajusta en el siguiente, o si
se deja constancia y ya. **Es una decisión de negocio, no técnica.**

## 🟡 Valioso pronto

- **Publicar la política salarial no tiene ningún freno.** Dos agujeros que se
  vieron el 2026-08-08 al quemar la versión 3: el aviso de «desactualizada»
  compara `md5(fn_cuadro_categorias())`, o sea **solo los datos** — cambiar la
  redacción no lo dispara y el botón sigue diciendo «Volver a publicar». Y nada
  compara el documento nuevo contra el vigente, así que el sistema aceptó
  congelar una versión **byte por byte idéntica** a la anterior, sin decir nada,
  reiniciando las constancias. Dos frenos chicos en una migración: guardar la
  huella del TEXTO y rechazar publicar una versión igual a la vigente.
- **Seis fichas incompletas** al 2026-08-08, con lo que falta a cada una visible
  en `/admin/datos-personales`. Dos casos no son campos vacíos sino datos que se
  contradicen: **Carmen Sanándres** tiene fecha de nacimiento en 2026 (su correo
  sugiere 1960), y **Angie Chávez** cobra asignación familiar teniendo cero
  familiares registrados — S/113 al mes sin respaldo, o al revés, falta cargar al
  hijo. Sin esas fichas Dante no puede cerrar el T-Registro.
- **Dos datos del T-Registro que el sistema no guarda:** sexo y nacionalidad. Se
  llenan a mano en la hoja del contador. El tercero era el CUSPP, que ya tiene
  campo (0198) y ya está cargado — ver
  [A.2.c](#a2c--los-cuspp-ya-están-cargados--quedan-dos-y-dos-falsos-positivos).
- **Pedirle al contador el CUSPP de Carmen Sanándres (LIM, Profuturo) y de
  Lizzelott Estefany Ramírez Gomez (CCO, Integra).** Son las dos únicas que
  faltan; no venían en la hoja de julio. Ver
  [A.2.c](#a2c--los-cuspp-ya-están-cargados--quedan-dos-y-dos-falsos-positivos).
- **Cargarle el régimen de pensión a Kerin Guevara** (TRU). Hoy cae a la tasa
  genérica de `configuracion.tasa_afp`, que es una aproximación: un dato faltante
  acá no se ve como un cero, se ve como un número plausible. Si sale ONP, no lleva
  CUSPP.
- **La ficha de Dante Ramal** (CCO) no existe: sin DNI no se le puede declarar.
  Va antes que cualquier dato previsional.
- **Los campos de presentación de un locador siguen mintiendo.**
  `basica_legal_prop`, `complemento_variable` y `base_essalud` muestran números
  (1192.09, 73.84 y 1305.09 en la medición) para alguien que no tiene
  remuneración básica. No mueven ni un sol —el aporte de EsSalud ya es 0— y se
  dejaron fuera de la 0242 para que fuera auditable en una pasada. Merecen su
  propia migración con su prueba.
- **El candado del periodo que quedó a medias.** Se acordó el 26-07: no dejar
  cerrar un periodo con días sin resolver. Ahora que la incidencia del almuerzo
  ya se puede cerrar desde la pantalla, el candado no bloquearía a nadie.
- **Blindar con pruebas lo que aún mueve dinero sin ninguna:** descanso
  sustitutorio, bono de puntualidad, provisiones, feriado triple.
- **Versionar 0031 y 0033**: existen solo como `scripts/sql-manual/aplicar_*.sql`
  (fuera de git por PII). Crear versiones con los datos personales parametrizados.
- **Grati/CTS — regla legal de regularidad**: la sobretasa de feriado entra solo
  si se percibió en ≥3 meses del semestre (promedio entre 6). Felipe pidió ver
  primero el impacto con
  [`consulta_impacto_regularidad_feriados.sql`](../scripts/sql-manual/consulta_impacto_regularidad_feriados.sql).
- **Colibrí en cargas**: ~22 pantallas y ~49 estados vacíos sin marca.
- **Integración Dynamic ↔ retail**: Fase 0 (reconciliación, solo lectura) lista
  para arrancar — `docs/integracion-retail/`.
- **Objetivos: botón «copiar del mes anterior»**.
- **Espejo a Google Sheets legible** (encabezados fijos, una fila por persona).

## 🟢 Dependen de Felipe / redondeo

- Datos personales: 5 fichas faltantes + celular/instrucción/estado civil (~13).
  Import SIN commitear PII.
- Validar factores de provisiones con el contador (MYPE: 8.33/4.17/4.17).
- **El rol de Catherine.** Tiene `supervisor_sede` en CCO, así que el sistema le
  da lo de una encargada de tienda —ver a la gente de CCO, firmar amonestaciones
  de CCO— y le niega lo que querría una accionista: ver las tres tiendas. Está al
  revés de su papel. ⚠️ **No es solo de permisos:** siendo locadora por
  honorarios, ese cargo la retrata como subordinada. Ver [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).
- **Cuatro personas con rol admin** (Carlos, Estefany, Felipe, Janis). Un admin ve
  todas las sedes, todos los datos personales —cuentas bancarias y DNI incluidos—
  y puede firmar despidos. Cuatro accesos totales en un equipo de 23.
  ⚠️ **Y uno de los cuatro, Carlos, no es trabajador de la empresa:** cobra por
  honorarios. Su acceso está justificado —trabaja en Desarrollo Organizacional— y
  no hay rol intermedio que lo reduzca; lo que falta es la cláusula de
  confidencialidad en su contrato de locación. Ver
  [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).
- Cuenta de Estefany (falta su correo) · revisar áreas reales de cada quien ·
  checkbox «encargada de piso» en Equipo · split mañana/tarde por sede.

---

## Decisiones tomadas (no reabrir)

- **Planilla**: régimen MYPE pequeña empresa, base 6.5 h, pago = salario × horas/(6.5 × días).
- **A Dante Ramal se le pagó por fuera antes de entrar al sistema, y eso NO se
  carga hacia atrás — se cuenta desde ahora.** Decisión de Felipe: el sistema es
  nuevo y no vale la pena complicarlo con historia previa.

  ⚠️ **Por qué está escrito aquí y no solo donde se investigó:** de
  `fecha_ingreso` cuelga el reloj de su CTS, su gratificación y sus vacaciones.
  Quien mire su devengado dentro de unos meses va a ver una antigüedad más corta
  de la real y va a querer corregirla. **No es un dato mal cargado: es una
  decisión.** El relato completo vive en la sección del 2026-08-14, dentro de un
  bloque que empieza tachado —y por eso esta línea existe: ahí nadie la iba a
  leer.

  Y un cabo que va con el vínculo de los locadores: **Dante es locador con monto
  fijo mensual**, el mismo indicio de laboralidad ya señalado para Carlos,
  Catherine y Claudia. Entra en esa lista; no se quedó fuera por haberse dado de
  alta después.
- **La CTS incluye el sexto de la gratificación** — encendido en producción el
  2026-08-05. La base pasa de sueldo pelado a sueldo × 13/12 (Art. 16 del
  D.S. 001-97-TR; en pequeña empresa la grati es media remuneración, así que el
  sexto vale sueldo/12). Sobre S/1,130 la CTS del año sube de 565.00 a 612.08.
  **Ninguna autoridad zanjó este punto para el régimen MYPE**: es derivación del
  TUO de la Ley de CTS y del documento del MTPE. Se eligió la lectura prudente
  —provisionar de más no es infracción, de menos sí—. Se apaga con una línea, y
  la prueba `126` blinda que el sexto no se cuele en la gratificación ni en las
  vacaciones. **Falta contárselo al contador antes del depósito del 15 de
  NOVIEMBRE de 2026**: si él calcula sobre el sueldo pelado, la discrepancia
  aparece el día del depósito. (Este párrafo decía «antes del depósito de mayo»
  y erraba por seis meses en contra: la CTS se deposita el 15 de mayo y el 15 de
  noviembre, y el sexto se encendió el 05/08, dentro de la ventana mayo–octubre,
  que es la que se deposita en noviembre.)
- ~~**A Carlos Espejo no se le toca el tipo de vínculo**~~ — **REVISADA Y
  REVERTIDA el 2026-08-08.** La decisión decía «se revisa el día que exista la
  excepción por persona»: ese día llegó con la 0196, que parte el sí/no en tres
  banderas. Carlos pasó a `rxh`, que es lo que es.

  **Qué cambió, medido:** deja de cobrar feriados (S/286.57 en un periodo
  completo), deja de generar EsSalud (S/134.81 que pagaba CAYLA) y deja de
  provisionar gratificación, CTS y vacaciones. **Su pago por horas no se movió un
  céntimo** — de eso vive, y es lo único que le corresponde a un locador.

  **Por qué se revirtió:** los hechos, dichos por Felipe el mismo día, no
  encajaban con el retrato. Cobra POR HORA, es cuadripléjico, trabaja desde su
  casa, no está sujeto a horario y marca cuando decide trabajar. Ninguno de los
  indicios de subordinación que lista la doctrina —horario fijo, instrucciones
  directas, equipos de la empresa, monto igual cada mes— aplica. Dejarlo como
  `planilla` era construir por escrito la prueba de una relación laboral que no
  existe. Ver [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).

  ⚠️ **Y quedó una pregunta abierta que solo puede cerrar el contador:** el
  sistema venía calculando S/134.81 mensuales de EsSalud por él. Si eso se
  declaró de verdad en la PLAME, Carlos está registrado como TRABAJADOR ante
  SUNAT y EsSalud, y entonces toda la discusión sobre indicios sobra — formalmente
  ya lo es. Si solo salía en pantalla y nadie lo declaró, no pasa nada. **No es lo
  mismo y hay que averiguarlo.**
- **El terminal marca sin PIN**, a propósito. No se puede usar una marca como
  prueba individual en un procedimiento disciplinario sin otro respaldo.
- **Fecha de ingreso = decisión de negocio, no cálculo.** Se edita persona por
  persona en Equipo; el botón masivo se eliminó (0041).
- **Disciplina**: Dynamic avisa y documenta, nunca sanciona solo (D.S. 003-97-TR
  art. 25: umbrales 4 consecutivas / 6 en 30 d / 16 en 180 d).
- **Una marca se anula, nunca se borra** (0081). El botón «Eliminar» no vuelve:
  para el cálculo y para el pago anular hace lo mismo, pero deja quién la quitó y
  por qué, y se puede deshacer.
- **Cuando falta el retorno del almuerzo, el sistema no inventa una hora.** Avisa
  y decide una persona. Las tres realidades posibles (se fue, volvió sin marcar,
  no tomó refrigerio) son indistinguibles para el sistema.
- **Corregir el tipo de una marca puede dejar el día roto a mitad de camino, y no
  se bloquea**: ese estado intermedio es el primer paso del flujo de arreglo. Se
  sella para revisión y el sello se levanta solo cuando el día cuadra.
- **Las actas de descanso ya subidas no se migran al almacén** (0175). Se leen
  donde están. Mover archivos con un script es lo que puede salir a medias.
- **Meta operativas TRU = 8** · **Melany y Catherine como encargadas** · **Janis
  admin + encargada de piso** · **Keyla/Raquel/Felipe: ingresos quedan 2026**.
