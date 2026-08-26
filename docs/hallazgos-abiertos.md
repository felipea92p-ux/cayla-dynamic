# Hallazgos abiertos

Catálogo vivo de lo que está mal y aún no se ha arreglado. **Se tacha y se borra
según se cierra** — cuando quede vacío, se borra el archivo. El estado general y
el orden de trabajo viven en [`estado.md`](estado.md).

Salió de una auditoría por áreas con verificación adversaria: diez revisores
independientes sobre el sistema, y cada hallazgo grave pasado por otro agente
cuyo único trabajo era demostrar que era falso. De 42 candidatos sobrevivieron
34; los 8 refutados están al final, con el motivo, para no volver a levantarlos.

Cada uno lleva su evidencia. Antes de arreglar, **reproduce**: si el caso no se
reproduce hoy, táchalo y anota por qué.

---

## Auditoría del 2026-08-19 · 22 agentes contra la ley peruana

Doce frentes legales —uno por cuerpo normativo—, cinco de cálculo y **cinco
escépticos** cuyo único trabajo era tumbar lo que los otros levantaran. Salieron
**93 hallazgos**; los escépticos tumbaron **46 por no tener población en CAYLA**,
9 por ser decisiones ya tomadas, 3 por no reproducirse y 3 por estar arreglados.

**La regla que se les impuso, y que hizo casi todo el trabajo:** ningún hallazgo
vale sin una consulta que diga a quién de CAYLA le pasa. Un hallazgo sin
población es una hipótesis. El día anterior, cinco «hallazgos» se deshicieron al
medirlos contra producción, y cada uno costó tiempo del cierre.

**La consulta que responde eso vive en
[`scripts/sql-manual/a_quien_le_pega.sql`](../scripts/sql-manual/a_quien_le_pega.sql)** —
nueve preguntas, un solo `select`. Se corre antes del 28. Mientras no se corra,
lo de abajo es mecanismo confirmado con población desconocida, que no es lo
mismo que plata perdida.

### Cerrado el mismo día

- **0275 · las vacaciones dejan de pagarse en cero.** Quien pasaba el periodo
  entero de vacaciones cobraba S/0.00 por el 0/0 de `hh.pago / dias_marcados`.
  La 0254 ya lo había resuelto para el descanso médico y la 0262 para la
  maternidad; vacaciones era la última y la más probable de las tres.
- **`va_a_poder_cerrarse.sql` conocía solo uno de los dos frenos del cierre.**
  Daba «✓ TODOS CUADRAN» y `fn_planilla_congelar` abortaba igual por el freno de
  la 0243/0244.
- **La boleta se contradecía sobre la AFP** y no identificaba al empleador.

### Confirmado y pendiente · mueve plata en el pago mensual

| Qué | Cuánto | Dónde |
|---|---|---|
| **No existe la sobretasa del 100 % por trabajar el día de descanso semanal** (art. 3 D. Leg. 713) | S/44–58 por episodio | `fn_planilla_calcular` no lee `turnos` ni una vez |
| Un **feriado dentro de unas vacaciones se paga dos veces** | S/51.99 por feriado | `vacd` no lo excluye y `fer` sí lo paga |
| La **remuneración vacacional no entra a la base de EsSalud ni de pensión** | S/94 + S/43 por persona y periodo | va a `pago_base` pero no a `pb.basica` |
| Se pagan **ausencias posteriores al cese** | S/193.55 medidos | `vacd`, `dmd` y `mat` no miran `fecha_cese` |
| **Sueldo fijo cobra el mes íntegro** aunque entre o cese a mitad | S/1,306.45 medidos | la rama `sf` no prorratea |
| **Quien cesa sin marcas desaparece** de la planilla y cobra S/0 del mes | S/1,509.64 medidos | |
| **Sin régimen de pensión → aporte cero**, y ninguna pantalla de Planilla lo dice | ~S/208/mes por persona | `coalesce(tpen.tasa, …)` |
| El **sobretiempo pierde el exceso** del ciclo que cruza el día 29 | S/14–19 | `ot_dias` lee desde `p_ini - 7` |
| La **pantalla de Feriados y la planilla dividen por bases distintas** | 3.33 % de cada sobretasa | mes calendario vs periodo 29→28 |

### Confirmado y pendiente · muerde el día que alguien cese

- **Los récords vacacionales ya ganados y no gozados no se pagan nunca.**
  `fn_vacaciones_truncas` arranca en el último aniversario. S/2,243 medidos en un
  caso de tres años. Emparentado con [V1](#v1--la-trunca-de-vacaciones-cobra-dos-veces-los-mismos-días).
- **La CTS de un semestre cerrado y no depositado desaparece al cesar.**
  S/406.25 por semestre perdido. Población determinista: quien cese entre el 1 y
  el 15 de mayo o de noviembre.
- **`fn_remuneracion_computable` mete descuentos y la propia gratificación** al
  promedio de «conceptos variables»: filtra `where mp.monto > 0` sin mirar
  `mp.tipo`. Infla las tres truncas (+S/220.83 de base medidos).
- **Las truncas se calculan sobre el sueldo de la escala**, no sobre lo percibido.
- **El promedio de variables se toma del semestre de la gratificación** (ene-jun /
  jul-dic) también para la CTS, cuyo periodo es nov-abr / may-oct.
- **`fn_avisos_vinculo` filtra `estado = 'activo'`**: la red de seguridad que la
  0169 escribió para avisar de quien está en `'prueba'` se apaga justo en el
  cese, que es cuando esa etiqueta cuesta dinero.
- **No existe el concepto de vacaciones vencidas** ni la indemnización del art. 23.
- **El plazo de 48 h de la liquidación se calcula bien pero nadie lo empuja:** no
  hay contador en el menú ni fila en Incidencias.

### Confirmado y pendiente · gratificación

- **El 9 % de la Ley 30334 no entra en el monto que propone la pantalla.**
  `fn_grati_cts_periodo` devuelve solo `grati`, no `be`. ~S/59.40 por persona y
  semestre. Atenuante fuerte: la cabecera de la 0134 dice que lo calcula el
  contador. La próxima ocasión es el 15/12/2026.
- **La grati de Navidad se calcula sobre un semestre cortado el 28/12**, porque
  el periodo que contiene el 15/12 termina ahí. S/10.64 por persona.
- **La provisión de gratificación de la boleta incluye el feriado y
  `fn_provisiones` —de donde sale lo que se paga— no.**
- **El panel de Provisiones muestra tres columnas contra un total que incluye una
  cuarta** (la bonificación extraordinaria), y `provision_total` difiere en
  S/0.01 de la suma de sus cuatro celdas.

### Confirmado y pendiente · el papel

- **La retención previsional se imprime como «va a tu fondo»** cuando de cada
  S/100 solo van ~S/77. ✅ *corregido el 2026-08-19*.
- **Ni la boleta ni el detalle de servicios identifican al empleador.**
  ✅ *corregido el 2026-08-19; quedan siete documentos con el RUC escrito a mano.*
- **El deslinde legal nombra «Rendimiento Extraordinario» e «Incentivo Variable
  por Metas»**, conceptos retirados de la tabla a propósito.
- **El pie promete grati, CTS y vacaciones sin consultar `fn_devenga`.**
- **El CSV que se le pasa al contador no exporta cuatro de las once partidas** que
  componen el `total` que sí exporta: movilidad, educación, sobretiempo y
  descuento de pensión. La fila no cuadra.
- **El CSV de Exportar saca una columna `horas_extra` que NO es sobretiempo:** es
  `horas_extra_detectadas`, lo que se trabajó por encima del horario de ESE día.
  Toca sobre todo a LIM, cuyo horario programado es de 9 h.
- **La política salarial publicada cita el art. 8** para la sobretasa del feriado,
  que es del art. 9, y el **inciso d)** para el bono de cumpleaños, que es el g).
  Una línea cada uno más republicar.

### Confirmado y pendiente · disciplina

- **Un día que la colaboradora impugnó por escrito** (`revisiones_pedidas`, el
  botón de `/mio`) **sigue contando para el umbral y sale impreso en el memo.**
  Es el canal que se le dio para reclamar, y no lo escucha nadie.
- **La escalera de inasistencias salta de la primera suspensión a la imputación
  de cargos** con una sola falta nueva, sin causal del art. 21.5.
- **La suspensión por faltas se fija en `fn_hoy_lima() + 1`** sin comprobar que
  sea día laborable, y deja `suspension_fechas` en NULL. La rama de tardanzas sí
  lo hace bien desde la 0235.
- **El umbral mensual de tardanzas se borra el 1 de cada mes** y no hay forma de
  emitir el documento después.
- **`fn_cargo_de_rol` imprime «Líder de Equipo» para el rol `lider_do`.**
- **REGRESIÓN de la 0238:** `fn_otorgar_descanso_sustitutorio` volvió a exigir
  horas marcadas para el estado PENDIENTE, perdiendo el arreglo que la 0072 hizo
  a propósito. Deja sin registrar el acuerdo previo del feriado — y el próximo es
  el **30/08/2026**, domingo, que es el día que TRU sí trabaja.

### Latentes confirmados · hoy no cuestan nada

Mecanismo real, población cero hoy. Se anotan para que el día que se enciendan
no haya que descubrirlos otra vez.

- Al **personal de dirección se le miden tardanzas** y se le puede armar memo.
- La **tabla `feriados` es global y no tiene sede**: un día no laborable regional
  se pagaría a las cuatro.
- El **tope de 90 remuneraciones diarias de CTS** del régimen MYPE no está en el
  código. No muerde hasta enero de 2031.
- **`fn_cts_trunca` puede devolver un monto negativo** y `fn_liquidacion` lo suma.
- **`fn_liquidacion_pagar` no escribe en `desembolsos_beneficios`:** una
  reincorporación vuelve a devengar CTS y vacaciones enteras.
- **`v_planilla_pagada` elige la versión máxima POR PERIODO** y no por persona: un
  pago congelado desaparece si el periodo se repaga.
- **`fn_remuneracion_computable` lee la asignación familiar sin versionar**
  mientras planilla y provisiones la leen de `parametros_laborales`. Se dispara
  con el decreto de la RMV.
- **`fn_grati_trunca_bruta` tiene el 9 % clavado** mientras las otras dos vías lo
  leen versionado.
- **`motivo_cese = 'fin_periodo_prueba'` se acepta en cualquier fecha**, sin medir
  los tres meses del art. 10 de la LPCL.
- **El certificado de trabajo y la constancia de cese no existen** en ninguna
  parte del sistema. La constancia es la llave con la que la persona retira su
  CTS del banco.

---

## Dónde está esto hoy (reverificado el 2026-08-08, uno por uno)

**Quedan 15 problemas distintos.** No es una estimación: cada entrada se
comprobó contra el esquema y el código de hoy, y abajo está la línea exacta que
lo demuestra. De las 22 que el archivo daba por abiertas, **cuatro ya estaban
arregladas sin tacharse** (C5, C8, C13 y A18), **dos se cerraron el mismo día**
(A7 con la 0184, C3 con la 0189) y **una está medio cerrada** (A11). Dos pares
describen el mismo defecto: C13≡A18 y C12≡A16.

**Y apareció uno que no estaba en la lista, más grave que varios de los que sí:**
el sistema le medía tardanza y salida anticipada a las tres personas que cobran
por honorarios, que por ley no están sujetas a horario. Un registro de tardanzas
es **control de jornada** — el indicio más directo de subordinación que existe, y
lo fabricaba CAYLA sobre sí misma. Cerrado el mismo día por la
[`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql).
Salió de una frase de Felipe, no de ninguna auditoría: **«era RXH, ellos no están
sujetos a horarios, solo lo puse como referencia»**. Ninguna de las diez
revisiones independientes lo vio, porque para verlo hay que saber qué es cada
persona — y eso no está en el código.

**Y una advertencia que esta pasada dejó cara:** antes de creerse cualquiera de
los 16, **mirar qué hay una capa más abajo**. Tres hallazgos que parecían graves
se cayeron el 2026-08-08 porque un candado posterior ya los tapaba —el índice
`periodos_etiqueta_unica`, el constraint `periodos_sin_solape` y el candado que
la 0138 le puso a `fn_recalcular_jornada`—. Varios de estos 16 se escribieron
antes que las migraciones que los protegen.

### Vivos, en orden de consecuencia

| # | Qué | La prueba de que sigue |
|---|---|---|
| **V1** | 🔴 **La trunca de vacaciones cobra dos veces los mismos días** — quien gozó en este récord las vacaciones que ganó en el ANTERIOR se queda en S/0.00. **Tres personas hoy, S/905.38.** Ver su entrada completa abajo | medido en producción el 2026-08-14: Janis 9.2 días en pantalla → 0 al liquidar · Sandra 8.1 → 0 · Melany 6.3 → 0 |
| **C12 · A16** | 🟡 `fn_registrar_marcaje` — **medido el 2026-08-10: NO cambia el pago**, el candado de la 0138 aguanta. Lo que hacía era entrar muda; lo sella la 0207 | reproducido con `BEGIN … ROLLBACK`: horas 8.00 antes y 8.00 después |
| **A16-b** | 🔴 `fn_auto_cierre` sigue sin el candado — es la otra puerta que corre sin nadie delante | la 0207 no la toca a propósito: su arreglo es saltarse la candidata y alertar, no sellar |
| ~~**A3**~~ | 🟡 el cron de auto-cierre — **medido el 2026-08-10: NO reescribe lo pagado.** Es cierto que no nombra `periodos_planilla`, pero solo escribe en `marcajes` y en `alertas`, nunca en `jornadas` directo: pasa por el mismo trigger que el candado de la 0138 detiene. Misma forma y mismo desenlace que C12·A16 | `insert into` en su cuerpo vigente: `marcajes` y `alertas`, y nada más. Lo que sí hacía —entrar mudo— lo sella la 0207 |
| ~~**C3**~~ | ✅ **cerrado el 2026-08-08** por la 0189 — y eran dos líneas, no una | aplicada y confirmada en producción |
| **C13** | reactivar a quien se cesó por error le paga S/0 | `fn_reactivar_persona` no menciona `asignaciones_salario`: no reabre el tramo que el cese cerró |
| **C14** | corregir un auto-cierre deja DOS salidas finales | `fn_agregar_marcaje` no nombra `auto_cierre`: inserta sin reconciliar |
| **A1** | el bono de puntualidad se paga con el denominador del día en que se pulsó | `v_dias_periodo := least(v_fin, (now() at time zone 'America/Lima')::date) - v_ini + 1` |
| **A6** | el guard del terminal cae abierto si `auth_user_id` es null | sigue el `and … is not null` en vez de `is distinct from`, y en `terminales` solo hay FK y UNIQUE — **no** el check de activo-vinculado |
| **A19** | una tardanza perdonada sigue contando en tres pantallas | `tardanzas_justificadas` aparece **cero** veces en Horas, Reporte-sede y `/api/espejo` |
| ~~**A4**~~ | ✅ **cerrado el 2026-08-18 SIN corregir nada, y medido.** El detector encontró dos jornadas en toda la historia y **ninguna es un falso positivo**: la de Janis Revilla (28/07, 53 min) es una tardanza REAL —ese día TRU abrió con dos turnos, ella entró 14:38 y su hora del martes era 13:45, la resta da 53— y la de Rufina Salvatierra son 2 min de alguien que ya cesó. Medir puntualidad en un feriado es lo CORRECTO cuando la tienda abre con sus horarios normales. Y la señal que se pensó usar para excluir no sirve: **22 de 25 feriados trabajados no tienen ni un turno registrado**, así que «feriado sin turno» significa «nadie registró turnos», no «no era su día». Excluirlos taparía tardanzas reales | Lo pilló Felipe: «si tenía horario en feriado y llegó tarde sí es tardanza». Queda pendiente solo lo preventivo: vacaciones aprobadas, descanso sustitutorio y suspensión, sin ningún caso hoy |
| ~~**A7**~~ | ✅ **cerrado el 2026-08-08** por la 0184: `fn_set_horario` y `fn_quitar_horario` ya no existen | confirmado en producción: `puertas_que_quedan: 0` |
| ~~**A9**~~ | ✅ **cerrado el 2026-08-13** por la [0238](../supabase/migrations/0238_un_dia_compensatorio_que_no_compensa_deja_de_entrar.sql). Era más ancho de lo que decía esta línea: además de vacaciones y feriados, se podía poner el día libre ANTES del feriado y —la peor— sobre un día que la persona ya había trabajado. El motivo vive ahora en una sola función que consultan el candado y la pantalla, así que un día compensatorio futuro **se delata solo** cuando llega la fecha y hay horas marcadas | prueba [`179`](../supabase/tests/179_un_dia_compensatorio_tiene_que_compensar.test.sql), 10 comprobaciones. Aplicada en producción |
| ~~**C4**~~ | ✅ **cerrado el 2026-08-13** por la [0240](../supabase/migrations/0240_la_salida_pasada_la_medianoche_por_fin_se_puede_marcar.sql). Y no «partía el día en dos»: **RECHAZABA la salida**. Medido: 30.5 h registradas donde hubo 9.5 —el día anterior cerrado por el cron con la hora programada, más un día fantasma de 22.5 h—. Las horas van ahora al día en que entró, con tope de 16 h | prueba [`181`](../supabase/tests/181_la_salida_de_madrugada_encuentra_su_jornada.test.sql). SQL aplicado; **falta desplegar el frontend** para que el terminal ofrezca «Salir» a las 00:30 |

### El caso que cerró A9 · Taller LIM, Fiestas Patrias 2026

Los siete descansos sustitutorios del acta «2026-07-28 Taller LIM» son el caso
real que hizo mirar A9, y conviene dejar escrito qué pasó — porque los cuatro del
30 de julio **van a seguir saliendo en rojo en Feriados**, y quien los vea va a
reabrir esta investigación.

**Lo que se acordó el 28 de julio**, y estuvo bien hecho: el taller trabajaba los
dos feriados (28 y 29) a cambio de librar el 30 y el 31. El acta se firmó ese
mismo día, que es cuando se firma un acuerdo.

**Lo que pasó después, y nadie podía preverlo:**

| Día | Qué ocurrió de verdad |
|---|---|
| 28 (feriado) | **trabajaron** |
| 29 (feriado) | **la galería no abrió** — no vinieron, así que no hay nada que compensar |
| 30 (laborable) | **trabajaron** — el día libre del acta no se llegó a tomar |
| 31 (laborable) | **no vinieron** — este fue, de hecho, el único día que descansaron |

**Nadie perdió dinero, y no hay faltas.** Los siete quedaron en `PENDIENTE`, y
`fn_planilla_calcular` solo anula la sobretasa cuando el estado es `OTORGADO`:
se les pagó la sobretasa del 28 completa. Y `fn_faltas` acepta `PENDIENTE` en su
lateral de descanso sustitutorio, así que el 31 tampoco cuenta como falta para
nadie. Comprobado contra la base, las dos cosas.

**Decisión (Felipe, 2026-08-13): no se corrige el pago.** Marcar el descanso como
otorgado le quitaría ~S/102 a cada una por una compensación que el propio papel
atribuye al 29 —un día que no trabajaron—, y exigiría reabrir una planilla ya
depositada. El fundamento sería débil y el costo en confianza mayor que los
S/400.

**EL HUECO QUE ESTE CASO DESTAPA, Y QUE SIGUE ABIERTO.** El sistema tiene el
estado `NO_OTORGADO` —«el descanso no se dio»— desde la 0069, y **no hay forma de
llegar a él**: el estado se elige en el formulario de ALTA, cuando el descanso
todavía no ha ocurrido, y en la lista el único botón es «Quitar». Para decir
«esto se acordó y las condiciones cambiaron» hay que volver a registrar el mismo
par, cosa que no adivina nadie.

Por eso los siete se quedaron en `PENDIENTE`: no por descuido, sino porque el
sistema deja escribir el plan y no deja actualizarlo cuando la realidad cambia.
Falta un botón en la lista para confirmar o descartar un descanso ya registrado,
y un aviso de los que siguen sin decidir antes de cerrar el periodo.

| **A15** | la marca se encola DESPUÉS de intentar enviarla, y el envío no tiene tope de tiempo | `if (error) await encolarMarcaje(entry)` en `:307`, y ni un `AbortSignal` en todo el archivo |
| **A14** | sin service worker, un reinicio sin internet deja la sede sin marcar | no hay `sw.js` ni manifest en `public/`, ni dependencia de PWA |
| **A12** | la Hoja de sede se imprime en ceros si una consulta falla | una sola aparición de `error` en las ocho consultas |
| ~~**A5**~~ | ✅ **cerrado el 2026-08-10.** La 0075 **sí** estaba en producción —medido, este documento decía lo contrario— y la pantalla ya la llama (0200) | `fn_dias_suspension`, `fn_expediente_set_suspension` y la columna: las tres presentes en prod |
| **A20** | ✅ **cerrado el 2026-08-10** por la 0200 — el semáforo pedía 3 tardanzas a quien por escala ya le tocaba 1 | la escala vive en `fn_tardanza_escalon`; prueba [`155`](../supabase/tests/155_el_semaforo_conoce_el_escalon.test.sql) |
| ~~**A21**~~ | ❌ **REFUTADO el 2026-08-10, y era mío.** El sistema ya es coherente: a quien cobra fijo no se le arma memo por ningún camino | `fn_expediente_crear_borrador` —un nivel por debajo del generador— lleva `or v_p.sueldo_fijo = true then` y aborta. Miré el generador y no bajé un nivel más |
| **A11** | 🟡 el borrador ya dice «BORRADOR», pero sigue firmado por Gerencia General | ver su entrada |

### Los cuatro registros en rojo del Taller LIM (28/07/2026) — revisado y CERRADO

En cuanto la 0238 entró en producción, Feriados empezó a mostrar **cuatro
descansos sustitutorios en rojo** con el motivo «ese día trabajó». Se revisaron
uno por uno con Felipe el 2026-08-13. **No hay nada que corregir en el pago**, y
se deja escrito para que quien los vea no vuelva a abrir la investigación.

**QUÉ PASÓ DE VERDAD** (confirmado por Felipe; el papel no manda y el equipo está
de acuerdo):

  · El **28 de julio** fue el ÚNICO feriado trabajado.
  · El **31 de julio** fue su día sustitutorio, y lo tomaron **tres**: Judith,
    Raquel y Joselyn. **Carmen no.**
  · El 29 no se trabajó —la galería no abrió— y el 30 sí, como día normal.

Las actas se habían firmado por adelantado y quedaron cruzadas: hay papeles que
dicen «se compensa el 29 con el 31» y «se compensa el 28 con el 30», y ninguna de
esas dos cosas ocurrió. El par real era **28 → 31**.

**EL DINERO, Y POR QUÉ NO SE TOCA.** Los siete registros quedaron en `PENDIENTE`,
y `fn_planilla_calcular` solo anula la sobretasa cuando el estado es `OTORGADO`.
Resultado:

| | trabajó el 28 | descansó el 31 | resultado |
|---|---|---|---|
| Judith, Raquel, Joselyn | sí → cobraron sobretasa | sí | recibieron **las dos cosas**. Devuelto con un descuento el 2026-08-14 |
| **Carmen** | **NO vino** → sin sobretasa | no | **correcto**, nada que ajustar |

Lo de Carmen se comprobó día por día contra sus marcajes: el 28 y el 29 no tiene
ni una marca —ni siquiera anuladas— y el 30 sí trabajó, 9.50 h desde el terminal.

⚠ **Y ahí queda un cabo suelto**: su registro «trabajó el 28 · libre el 30» NO
debería haberse podido crear. `fn_otorgar_descanso_sustitutorio` exige desde la
0069 que el feriado esté laborado y rechaza con «el feriado no fue laborado». O
ese registro entró por una vía que esquiva esa comprobación, o sus marcas del 28
se borraron DESPUÉS de crearlo —lo segundo dejaría rastro en
`correcciones_auditoria`—. Sin resolver al 2026-08-13.

**RESUELTO EL 2026-08-14 CON UN DESCUENTO, no reabriendo julio.** La planilla de
julio no se toca: se registró un descuento en el periodo ABIERTO (29-jul → 28-ago),
una línea por persona con su concepto, por el importe exacto de la sobretasa que
cobraron:

| | régimen | descuento | por qué ese importe |
|---|---|---|---|
| Joselyn Gavilan | PROFUTURO | S/ 61.77 | bruto — su retención de julio está en su cuenta AFP |
| Judith Pillaca | JUBILADA | S/ 67.86 | bruto — en julio aún tenía AFP (la 0190 rige desde el periodo del 28/08) |
| Raquel Ticona | ONP | S/ 59.10 | **neto** — el 13 % de ONP se fue al Estado y no vuelve |
| **total** | | **S/ 188.73** | |

**El régimen decide el importe, y esa es toda la regla.** A las tres se les
descontó primero el bruto. Después se midió qué les había llegado de verdad: la
sobretasa entró a la base de pensión en julio, así que sobre ella se retuvo
aporte. Con AFP esa retención está en su cuenta individual —cambió de sitio, no
se perdió— y recuperar el bruto deja el valor total parejo. Con ONP no hay
cuenta: el Sistema Nacional de Pensiones es de reparto y esa plata se fue a una
bolsa común del Estado. Cobrarle el bruto a Raquel le quitaba S/8.83 que nunca
vio, por un papeleo que hizo mal CAYLA. Se le devolvieron.

Carmen queda fuera, y no por una lista escrita a mano: el script mira quién tiene
horas el 28 y ella no vino. El importe sale de `fn_feriados_laborados`, la misma
función que pinta ese número en la pantalla de Feriados — no se calculó aparte.

Se deshace con `fn_quitar_movimiento` si hiciera falta.

⚠ **Cifra corregida:** durante la conversación se manejó «~S/102 cada una,
~S/306 en total». Era una estimación sacada del ejemplo de OTRA persona. El
importe real es el de la tabla.

Y aunque se quisiera, **no se podría**: la 0093 bloquea cualquier cambio sobre un
periodo pagado, y quitar una fila es un cambio. Los siete se quedan, y los cuatro
seguirán saliendo en rojo. **El motivo es cierto** — ese día trabajaron.

Tampoco hay faltas: `fn_faltas` acepta `PENDIENTE` para justificar el día
—comprobado en su cuerpo vigente, `and d.estado in ('PENDIENTE', 'OTORGADO')`—
así que el 31 no cuenta como falta para ninguna.

**NINGUNA TIENE FALTA**, y se comprobó preguntándole a `fn_faltas` —la misma
función que alimenta el semáforo disciplinario— por las cuatro entre el 25 de
julio y el 10 de agosto: **cero filas**, ni justificadas ni injustificadas. Se
sospechó que Carmen podía tener una el 31 (su registro apunta al 30, no al 31, y
ese día no vino); la sospecha era infundada.

**LO QUE SÍ SE HACE, HACIA ADELANTE.** El 6 de agosto (Batalla de Junín) también
se trabajó, y ese feriado cae en el periodo 29-jul → 28-ago, que sigue ABIERTO.
Ahí sí se compensa bien: se registra el par con estado `OTORGADO` antes de que el
periodo cierre, y el sistema deja de pagar la sobretasa solo. Será la primera vez
que la compensación se aplique de verdad.

Y no se cruzan los feriados: lo del 6 de agosto **no sirve para recuperar julio**.
Cada feriado se compensa con un día libre suyo. No pagar la sobretasa del 6 sin
dar día libre por el 6 sería quitarles algo que sí les corresponde.

**LO QUE ESTE CASO DESTAPÓ Y SIGUE ABIERTO:** el estado se elige en el formulario
de ALTA, cuando el descanso todavía no ha ocurrido, y no hay ningún botón en la
lista para confirmarlo después. Por eso los siete se quedaron en `PENDIENTE` — y
por eso la compensación, en la práctica, **nunca ha llegado a descontar una
sobretasa**. La función existe, está probada y no se usa. Falta un «se cumplió»
en la lista, y que los pendientes se vean antes de cerrar el periodo.

---

**Lo que hoy cambió el terreno:** varios de estos hallazgos se apoyan en la frase
«todas sus hermanas sí llevan el candado». El 2026-08-08 se descubrió que **en
producción seis de esas hermanas no lo llevaban** desde julio; la 0180 lo repuso.
La premisa vuelve a ser cierta, pero conviene recordar que era falsa mientras
estos hallazgos se escribían.


El catálogo había quedado congelado: entre medias entraron las migraciones 0089
a 0131 y los pgTAP 92 a 99, que cerraron **siete hallazgos sin tacharlos** (C2,
C6, C9, C10, A2, A8, A20) y uno que dejó de ser cierto solo (A17, la red de
seguridad, que hoy sí existe). Un catálogo con entradas mentirosas es peor que
no tenerlo: hace desconfiar de las que sí siguen vivas. Si arreglas algo de acá,
táchalo en el mismo commit.

**Lo verificado como VIVO al 2026-08-04**, por orden de consecuencia:

| # | Hallazgo | Evidencia de que sigue |
|---|---|---|
| C12 · A16 | `fn_registrar_marcaje` sin candado de periodo pagado | su última definición (0082) no menciona `pagado` ni una vez |
| C3 | Tardanza de más de 180 min se guarda como NULL y paga el bono | `0081:174` sigue con `if v_minutos_tarde > 180 then v_minutos_tarde := null` |
| A11 | El memo en borrador se imprime firmado por Gerencia General | el estado inicial sigue siendo `EMPRESA.firmante`, y el aviso de borrador sigue con `no-print` |

**Los 17 «Menores, sin verificar» del final siguen sin verificar** — nunca
pasaron por el refutador y esta pasada no los tocó. Trátalos como candidatos, no
como hechos: cuatro de ellos describen el mismo `fn_periodo_pagado(id, false)`
que el Alto 20 ya dio por cerrado.

**Los huecos de numeración ya no van aquí.** Son cinco (0031, 0033, 0108, 0133,
0139), están investigados uno por uno en
[`scripts/hooks/huecos-conocidos.txt`](../scripts/hooks/huecos-conocidos.txt), y el
hook de pre-push avisa solo de los que **no** estén en esa lista. Un dato que un
guardián vigila solo no necesita estar escrito en dos sitios.


---

## V1 · La trunca de vacaciones cobra dos veces los mismos días

`liquidacion` · 💰 dinero · arreglo de **días** (necesita un dato que no existe)

**Dónde:** `fn_vacaciones_truncas`, definición vigente en la
`0196_tres_puertas_en_vez_de_una_para_los_beneficios.sql`
(md5 en la base `0d411bdbc3edd858264f80d7a929ddc9`).

**MEDIDO EN PRODUCCIÓN el 2026-08-14**, comparando lo que muestra la pantalla de
Vacaciones (`fn_vacaciones_resumen`) contra lo que pagaría la liquidación
(`fn_vacaciones_truncas`) para las 25 personas:

| | ya gozó | la pantalla dice | la liquidación pagaría | pierde |
|---|---|---|---|---|
| **Janis Revilla** | 15 días | 9.2 días · S/387.86 | **0 días · S/0.00** | **S/387.86** |
| **Sandra Ramirez** | 15 días | 8.1 días · S/269.17 | **0 días · S/0.00** | **S/269.17** |
| **Melany Enrriquez** | 15 días | 6.3 días · S/248.35 | **0 días · S/0.00** | **S/248.35** |

**S/905.38 entre las tres.** Quien NO ha gozado nada sale con los dos números
casi idénticos, lo que confirma que el disparador es haber tomado vacaciones.

**QUÉ PASA.** La función cuenta los días gozados por la FECHA en que se tomaron,
no por el récord al que pertenecen:

```sql
v_aniv    := (fecha_ingreso …)                     -- el último aniversario
v_ganados := 15 * meses/12 + 15 * dias/360         -- lo devengado en ESTE récord
select sum(… greatest(v.fecha_inicio, v_aniv) …) into v_tomados
  from vacaciones v
 where v.fecha_fin >= v_aniv                       -- ⚠ TODO lo tomado desde el aniversario
v_pend := greatest(0, v_ganados - v_tomados);      -- nunca negativo → 0
```

**Y en Perú lo normal es ganar las vacaciones en un récord y gozarlas en el
siguiente.** Confirmado por Felipe el 2026-08-14: *«las 3 tienen acumuladas pero
ya se les había dado del año anterior»*. Esos 15 días saldaban un récord ya
cerrado; la función los ve caer después del aniversario y se los descuenta del
récord NUEVO. Pagan dos veces por los mismos días: una al gozarlos, y otra
borrándoles lo devengado.

**Penaliza al revés de lo que debería:** quien se tomó sus vacaciones a tiempo
cobra menos trunca que quien nunca las tomó.

**POR QUÉ NO ES UN ARREGLO DE UNA LÍNEA.** `vacaciones` guarda `fecha_inicio`,
`fecha_fin`, `observacion` y nada más. **No existe ningún campo que diga a qué
récord pertenece cada periodo**, así que el sistema no puede distinguir:

- días del récord ANTERIOR gozados ahora → **no deben descontarse**
- días del récord ACTUAL gozados por adelantado → **sí deben descontarse**

Los ve idénticos. Cualquier arreglo pasa por **añadir ese dato y migrar lo que ya
está cargado**, o por cambiar la regla de conteo asumiendo un criterio — y las
dos cosas se deciden con calma, no sobre una función que reparte dinero.

**CHIARA FLORES ES EL CASO QUE FALTA ENTENDER.** También gozó 15 días y sí le
quedan 3.79 por pagar (S/149.71). La diferencia estará en cuándo cae su
aniversario respecto de cuándo tomó los días. **Hasta saber por qué, no se puede
escribir el arreglo**: es la condición exacta que separa el descuento legítimo
del que no lo es.

**QUÉ HACER MIENTRAS TANTO.** Ninguna de las tres está cesando y esto solo se
paga en una liquidación, así que no tiene fecha. **El día que alguna cese hay que
revisar a mano antes de pagar**, con estas cifras delante.

**UN SEGUNDO HALLAZGO, EN DIRECCIÓN CONTRARIA Y MENOR.** A Felipe, Danitza y
Keyla la pantalla les muestra MENOS de lo que la liquidación pagaría (a Felipe
S/78.43 contra S/279.00). No es plata perdida: es que el estimado de la pantalla
usa un «factor de ritmo de trabajo» que la trunca no aplica. Informa bajo, no
paga mal.

La consulta que produce esta tabla vive en
[`vacaciones_pantalla_vs_liquidacion.sql`](../scripts/sql-manual/vacaciones_pantalla_vs_liquidacion.sql)
y se puede volver a correr cuando se quiera.

---

## Critica — 14

### 1. ~~El sueldo fijo paga el mes completo aunque la persona solo estuviera 6 días — y S/0 si cesó sin marcar~~

> ❌ **DESCARTADO** (Felipe, 27-07). El único caso con sueldo fijo e «ingreso» a mitad de mes es Catherine, que es **socia desde el inicio**: su fecha en la base viene de la carga inicial del sistema, no de una incorporación real. No es un caso que vaya a repetirse.
>
> Queda en pie una parte, para cuando se construya la liquidación por cese: quien tiene sueldo fijo y cesa sin marcar **no aparece en la planilla** — ni una fila, ni un aviso. Acordado que aparezca siempre.
>
> Y sigue abierta la discrepancia de fondo: `fn_provisiones` prorratea día a día y `fn_planilla_calcular` no. Dos funciones que reparten el mismo dinero con criterios distintos.

`planilla-dinero` · 💰 dinero · arreglo de **horas**

**Dónde:** supabase/migrations/0047_sueldo_fijo.sql:148 (y su redefinición vigente en 0069_feriado_descanso_sustitutorio.sql:355) — rama `case when pe.sueldo_fijo then coalesce(sf.salario, 0)` de fn_planilla_calcular

**Qué pasa:** Para quien tiene `sueldo_fijo` el pago base es el salario mensual íntegro, sin prorratear por los días que la persona realmente estuvo vinculada dentro del periodo. Quien ingresa el día 25 de un periodo de 30 cobra el mes entero; quien cesa el día 3 cobra el mes entero. Y el espejo: si cesó y no tiene ninguna jornada en el periodo (lo normal en dirección y socios, que no marcan), el CTE `pers` la deja fuera —no está activa, no tiene jornadas, no tiene movimientos— y su último mes no se paga en absoluto, sin fila y sin aviso. Peor: fn_provisiones SÍ prorratea la misma situación día a día (0048:81-94, `generate_series(fecha_ingreso, as_of)` con salario/días del mes). Las dos funciones que reparten el mismo dinero discrepan entre sí, y como sueldo fijo lo tienen los salarios más altos del sistema, un solo evento vale miles de soles.

**Arreglo:** Prorratear la rama de sueldo fijo por los días del periodo en que la persona estuvo efectivamente vinculada: `sf.salario * (días vinculados dentro del periodo) / v_dias`, tomando el inicio como `greatest(p_ini, pe.fecha_ingreso)` y el fin como `least(p_fin, fecha_cese)` (la 0086 ya trae `fecha_cese`; mientras no esté en producción, usar `fecha_estado_cambio` cuando el estado sea inactivo). Y ampliar el CTE `pers` para incluir a las personas con sueldo fijo y salario vigente que se solapen con el periodo aunque no tengan jornadas, para que el mes de cese aparezca. Alinear el criterio con el que fn_provisiones ya usa: si las dos funciones no comparten la misma definición de «días vinculados», vuelven a divergir.

### 2. ~~Otorgar un descanso sustitutorio cambia el total de un periodo YA PAGADO, sin lanzar error~~

> ✅ **CERRADO** por la migración 0093, con prueba en `supabase/tests/94_descanso_sustitutorio_no_toca_lo_pagado.test.sql`. Es el mismo hallazgo que el Crítico 10 y el Alto 8 vistos desde tres áreas distintas.

`planilla-dinero` · 💰 dinero · arreglo de **minutos**

**Dónde:** supabase/migrations/0072_descanso_sustitutorio_acuerdo_previo.sql:29 — fn_otorgar_descanso_sustitutorio (y fn_quitar_descanso_sustitutorio); consumido por fn_planilla_calcular en 0069:160-190

**Qué pasa:** fn_planilla_calcular lee `feriados_descanso_sustitutorio` en vivo: cuando el estado es OTORGADO anula la sobretasa del feriado. fn_otorgar_descanso_sustitutorio no consulta `periodos_planilla` en ninguna línea, así que se puede otorgar un descanso por un feriado que cae dentro de un periodo cerrado y pagado. El recálculo baja el total y la boleta reimpresa (que también sale de fn_proyeccion_periodo, en vivo) ya no coincide con lo que se transfirió. Es la única puerta de esta familia que quedó sin candado: fn_agregar_marcaje, fn_anular_marcaje, fn_corregir_marca, fn_eliminar_marcaje, fn_reactivar_marcaje, fn_set_vacaciones, fn_set_feriado, fn_quitar_feriado, fn_set_salario, fn_set_fecha_ingreso y fn_set_objetivos todas la tienen, con el mismo mensaje «Reabre el periodo primero».

**Arreglo:** Añadir a fn_otorgar_descanso_sustitutorio y a fn_quitar_descanso_sustitutorio el mismo guard que ya usan las otras once funciones, evaluado sobre `p_fecha_feriado`: `if exists (select 1 from periodos_planilla where estado='pagado' and p_fecha_feriado between fecha_ini and fecha_fin) then raise exception 'Ese feriado cae en un periodo ya PAGADO...' end if;`. Es la misma forma que la 0069 aplicó a fn_set_feriado — copiar textual mantiene el mensaje consistente.

### 3. ~~Llegar 3 horas tarde no cuenta como tardanza y encima paga el bono de puntualidad~~

> ✅ **CERRADO el 2026-08-08** por la
> [`0189`](../supabase/migrations/0189_una_tardanza_de_tres_horas_deja_de_desaparecer.sql),
> aplicada y confirmada. El número real se guarda siempre; quién puede sancionar
> con él lo decide `fn_tardanza_es_medible`, en un solo sitio. La pantalla de
> Disciplina muestra los días dudosos como **«sin medir»**, aparte del contador
> legal, y el botón «Generar borrador» se deshabilita para quien solo tenga esos.
> Prueba [`147`](../supabase/tests/147_una_tardanza_de_tres_horas_no_desaparece.test.sql).
>
> **Eran DOS líneas, no una.** La misma destrucción existía para la salida
> temprana desde la 0017; el hallazgo solo nombraba la de la entrada.
>
> **Y la mitad del bono era falsa:** `bono_puntualidad` está en `monto: 0` desde
> la 0121, así que no pagaba nada. Se comprobó antes de escribir la migración.
>
> **En producción quedaron 21 días con el número ya destruido.** No se pueden
> distinguir retroactivamente, pero SÍ reconstruir desde `marcajes` —que es la
> fuente de verdad y es append-only— con
> [`los_21_dias_que_nadie_vio.sql`](../scripts/sql-manual/los_21_dias_que_nadie_vio.sql).
> De los 21, cinco resultaron medibles: cuatro eran turnos rotativos mal
> coordinados de julio y uno un sábado con el horario mal cargado. **Ninguno era
> impuntualidad.**

`asistencia-jornadas` · ⚖️ decisión injusta · arreglo de **horas**

**Dónde:** supabase/migrations/0081_marcas_se_anulan_no_se_borran.sql:174 (fn_recalcular_jornada) · consumidores: 0053_levantar_tardanza.sql:121-122 (fn_calcular_bono_puntualidad), 0067_tardanzas_faltas_as_of.sql:52 (fn_tardanzas_resumen), 0059_generar_tardanza.sql:66 (fn_expediente_generar_tardanza)

**Qué pasa:** fn_recalcular_jornada borra la tardanza (la deja en NULL) cuando pasa de 180 minutos, con el comentario "implausible: turno distinto, no medible". Los tres consumidores filtran por `minutos_tarde is not null`, así que un NULL no significa "revisar" sino "no hubo tardanza": el día desaparece del semáforo, desaparece del expediente disciplinario y —lo peor— sale del denominador Y del numerador del bono de puntualidad, que exige `tarde_total = 0`. Resultado: cuanto más tarde llega una persona, menos la registra el sistema. El día tampoco entra a faltas (sí marcó), así que no queda rastro en ninguna parte.

**Arreglo:** Dejar de destruir el dato. En fn_recalcular_jornada guardar siempre `minutos_tarde` real y, cuando pase de 180 min, sellar el día como "por revisar" (el mecanismo de estado_revision que ya existe desde la 0068/0084) en vez de poner NULL — así el caso "turno distinto" que motivó el cap se resuelve pidiendo revisión humana, no borrando. Mientras tanto, mínimo: en fn_calcular_bono_puntualidad un día con `minutos_tarde is null` y `horas_trabajadas > 0` debe descalificar el bono en lugar de ignorarse, y fn_tardanzas_resumen debe listar esos días como "sin medir" para que alguien los mire.

### 4. Una salida después de medianoche crea una jornada de 21.67 horas y borra las horas reales del día anterior

`asistencia-jornadas` · 💰 dinero · arreglo de **dias**

**Dónde:** supabase/migrations/0068_marcajes_fuera_de_orden.sql:161 (fn_registrar_marcaje: v_fecha = fecha calendario de la marca) · supabase/migrations/0081_marcas_se_anulan_no_se_borran.sql:108,118 (fn_recalcular_jornada agrupa por fecha calendario) · apps/web/lib/terminal/estado-dia.ts:10-25 (el terminal so…

**Qué pasa:** Todo se agrupa por la fecha calendario de cada marca. Quien cierra tienda o taller pasada la medianoche: (a) su `salida_final` real es RECHAZADA por fn_registrar_marcaje —"tipo salida_final no válido en el estado actual (se esperaba entrada)"— porque el día nuevo no tiene marcas; (b) el terminal, que también decide con las marcas de hoy, le ofrece "entrada", y esa entrada de madrugada queda como el inicio de un día nuevo; (c) el auto-cierre cierra ese día nuevo a la hora programada de salida, produciendo una jornada de 21.67 h; (d) el día anterior queda sin salida y el auto-cierre lo cierra a la hora programada, perdiendo las horas reales; (e) cuando esa persona llega a su turno real esa tarde, su entrada verdadera también se rechaza porque el sistema la cree adentro desde las 00:20.

**Arreglo:** Que la jornada, no el calendario, sea la unidad. En fn_registrar_marcaje: si la persona tiene una jornada abierta del día anterior y la marca entrante es una salida/retorno dentro de una ventana razonable (p.ej. ≤ 8 h desde la última marca), atribuirla a la fecha de esa jornada abierta en vez de a la fecha calendario — y espejar la misma regla en `determinarSiguienteAccion` (packages/shared) y en estado-dia.ts, que hoy solo consulta desde las 00:00. Parche inmediato mientras tanto (minutos): un check en fn_recalcular_jornada que selle como "por revisar" toda jornada de más de 16 h en vez de dejarla pasar al pago.

### 5. ~~El generador del memo cuenta como falta los días de una suspensión ya cumplida y los días de descanso sustitutorio~~

> ✅ **CERRADO.** Verificado el 2026-08-08 contra el esquema vigente:
> `fn_falta_contadores` ya nombra `fn_dia_suspendido` **y** el descanso
> sustitutorio, que eran justo las dos ramas que le faltaban.

`disciplina-legal` · ⚖️ decisión injusta · arreglo de **horas**

**Dónde:** supabase/migrations/0060_generar_falta.sql:18-63 (fn_falta_contadores), rama sched líneas 40-54

**Qué pasa:** La 0070 enseñó a las faltas que el descanso sustitutorio no es inasistencia, y la 0079 hizo lo mismo con los días de suspensión. Las dos corrigieron fn_faltas (el detalle) y fn_faltas_resumen (el semáforo), pero NINGUNA tocó fn_falta_contadores, que es la función que fn_expediente_generar_falta usa para armar los hechos del documento. Resultado: la pantalla dice 'justificado — suspensión' y el papel que se imprime y se entrega lista ese mismo día como inasistencia injustificada. Es exactamente el non bis in idem que el encabezado de la 0079 describe ('la sanción que ya se cumplió se convierte en la prueba para la siguiente'), sobreviviendo justo donde más duele: en el documento.

**Arreglo:** Borrar fn_falta_contadores y hacer que fn_expediente_generar_falta consuma la MISMA definición de falta que el semáforo (fn_faltas_resumen / fn_faltas), parametrizada por persona y fecha desde. Mientras eso se hace: copiar a fn_falta_contadores las dos ramas que le faltan — fn_dia_suspendido(p_persona_id, ev.fecha) y feriados_descanso_sustitutorio en estado PENDIENTE/OTORGADO — dentro del CASE de `sched`. Dos definiciones de 'falta' en el mismo sistema es la causa raíz: mientras existan, la próxima corrección volverá a aplicarse solo a la mitad. Revisar además los documentos ya firmados cuyos hechos incluyan días cubiertos por una suspensión o un descanso sustitutorio.

### 6. ~~La rama del art. 25-h emite imputaciones ilimitadas sobre exactamente los mismos hechos~~

> ✅ **CERRADO** por la migración 0092: el candado de «ya hay una imputación vigente» subió a gobernar las dos ramas. Prueba en `93_una_falta_no_se_sanciona_dos_veces.test.sql`.

`disciplina-legal` · ⚖️ decisión injusta · arreglo de **minutos**

**Dónde:** supabase/migrations/0060_generar_falta.sql:94-101 (rama art. 25-h) vs. línea 108-110 (el candado, que solo vive en la rama else)

**Qué pasa:** fn_expediente_generar_falta tiene dos caminos. En el de escalación sí verifica 'Ya hay una imputación vigente' antes de generar. En el de los umbrales del art. 25-h (4 consecutivas / 6 en 30 d / 16 en 180 d) no verifica nada: toma todas las faltas de los últimos 180 días 'hayan sido o no sancionadas' y crea una imputación. Como esas faltas siguen dentro de la ventana de 180 días después de firmar, cada nueva llamada al botón 'Generar borrador' produce otra imputación idéntica. El único freno es el chequeo de borrador pendiente, que se levanta en cuanto se firma el anterior.

**Arreglo:** Subir el chequeo de imputación vigente a antes del if de la línea 97, para que gobierne las dos ramas. Y en la rama del art. 25-h exigir que exista al menos un hecho posterior al periodo_hasta de la última imputación firmada: si no lo hay, no hay nada nuevo que imputar. La ley permite mirar el historial completo para probar el umbral; no permite volver a imputar el mismo hecho.

### 7. ~~Cualquier sesión con login —incluida la del terminal de tienda— lee la planilla completa con todos los sueldos~~

> ✅ **CERRADO** por la migración 0090.

`seguridad-permisos` · 🔓 datos expuestos · arreglo de **minutos**

**Dónde:** supabase/migrations/0076_cerrar_ejecucion_anonima.sql:79 (bucle de grant masivo) · función fn_planilla_calcular(date,date,uuid), última definición en supabase/migrations/0069_feriado_descanso_sustitutorio.sql:235

**Qué pasa:** fn_planilla_calcular es SECURITY DEFINER y no tiene ninguna comprobación de permiso adentro. Sus tres hermanas sí la tienen (fn_provisiones, fn_proyeccion_planilla y fn_simular_planilla lanzan 'Solo un administrador o líder…'); fn_simular_planilla es exactamente un envoltorio que valida y después llama a fn_planilla_calcular. El guard se puso en el envoltorio, no en el núcleo. Las migraciones 0025, 0026 y 0027 lo compensaban con 'revoke execute … from public, anon, authenticated'. El bucle de la 0076 recorre TODAS las funciones de public y ejecuta 'grant execute … to authenticated' sin excepciones: deshizo ese revoke. El comentario de la 0076 (línea 41) dice 'Esto NO cambia lo que puede hacer un usuario con sesión' — es cierto para las funciones que estaban abiertas por el EXECUTE de PUBLIC, y falso para las dos que estaban revocadas a propósito (fn_planilla_calcular y fn_objetivos_sync_mes, revocada en 0032:129). La 0076 está aplicada en producción desde el 26-07-2026 según docs/estado.md. Devuelve por persona: nombre, sede, rango, salario_ref, pago_base, bonos, descuentos, total y las tres provisiones.

**Arreglo:** Dos cosas, no una. (a) Meter el guard DENTRO de fn_planilla_calcular: 'if fn_es_admin_o_lider() is not true then raise exception …' — el revoke solo no basta, porque el próximo grant masivo lo vuelve a abrir; el guard adentro es el que no se puede deshacer por accidente. Ojo: fn_simular_planilla la llama y también fn_periodos/fn_proyeccion_periodo, así que hay que confirmar que todos los que la invocan pasan el guard (todos son de admin). (b) Revocar de authenticated fn_planilla_calcular y fn_objetivos_sync_mes, y añadir a la 0076 una lista negra explícita para que un futuro bucle nunca vuelva a otorgarlas. Verificación en el SQL Editor de producción: select has_function_privilege('authenticated','fn_planilla_calcular(date,date,uuid)','EXECUTE');

### 8. ~~Las vacaciones no se pagan: la planilla no sabe que existen, y la pantalla promete lo contrario~~

> ✅ **CERRADO** por la
> [`0177`](../supabase/migrations/0177_las_vacaciones_se_pagan_como_dias_trabajados.sql).
> Verificado el 2026-08-08: `fn_planilla_calcular` lee la tabla `vacaciones` y
> devuelve `dias_vacaciones` y `monto_vacaciones` como componentes separados —
> exactamente los dos campos auditables que el arreglo pedía.

`vacaciones-feriados` · 💰 dinero · arreglo de **dias**

**Dónde:** supabase/migrations/0069_feriado_descanso_sustitutorio.sql (fn_planilla_calcular, definición vigente) + apps/web/app/(admin)/admin/vacaciones/page.tsx:170-172

**Qué pasa:** fn_planilla_calcular paga solo horas marcadas y no consulta la tabla `vacaciones` en ninguna línea (no hay ni una referencia en su código ni una clave de vacaciones en el JSON que devuelve). Quien se va de vacaciones no marca, así que esos días valen S/0. Peor: como el feriado se acredita con `7.5 × horas_mes / base_horas`, estar de vacaciones también le recorta el pago del feriado del mes. Registrar las vacaciones en el sistema no cambia ni un centavo del cálculo; el único camino es que alguien recuerde agregar a mano un movimiento con categoría 'vacaciones' (0044), y nada en la pantalla de Planilla avisa que en ese periodo hubo vacaciones. La 0042 lo dejó anotado como 'se conecta después' y nunca se conectó, pero la pantalla ya le dice a quien opera que sí está resuelto: «Marcar aquí las vacaciones evita dos problemas: que la persona figure como falta todos esos días, y que se le pague de menos (las vacaciones son descanso remunerado)».

**Arreglo:** Dos pasos, en este orden. (1) Inmediato, minutos: corregir el texto de la pantalla para que diga la verdad — registrar vacaciones evita la falta, y el pago de esos días se agrega como movimiento categoría 'vacaciones'. Mentirle a quien opera es peor que no decir nada. (2) De fondo: que fn_planilla_calcular acredite los días de vacaciones dentro del periodo con la remuneración vacacional (un treintavo del sueldo por día, como ya hace fn_vacaciones_truncas en la 0087, no la base de 6.5 h), y que devuelva `dias_vacaciones` y `monto_vacaciones` como componentes separados y auditables. Mientras eso no exista, agregar en la pantalla de Planilla un aviso por persona con días de vacaciones en el periodo y monto sugerido, para que el paso manual no dependa de la memoria.

### 9. ~~La ficha personal se borra entera si su consulta falló y alguien pulsa Guardar~~

> ✅ **CERRADO** por las migraciones 0125/0126 y el guard en pantalla: `datos-personales/page.tsx` ahora destructura el error de las tres consultas, avisa («No se guarda: las fichas no llegaron a cargar y guardar ahora borraría los datos que ya existen») y bloquea el guardado.

`frontend-admin` · 💰 dinero · arreglo de **horas**

**Dónde:** apps/web/app/(admin)/admin/datos-personales/page.tsx:52-60 (carga sin verificar error) y :83-105 (guardar)

**Qué pasa:** `cargar()` no mira el error de ninguna de sus tres consultas. Si la de `datos_personales` falla (red, RLS, caché de PostgREST), `fichas` queda como un Map vacío: la lista marca a TODAS las personas con el sello ámbar «sin ficha», el contador dice «N sin ficha» y al elegir a alguien el formulario se llena con VACIO. Nada avisa de que hubo un fallo. Quien esté frente a la pantalla concluye lo razonable — «a esta le falta la ficha» — teclea lo que tiene a mano y pulsa «Guardar ficha». `fn_set_datos_personales` sobrescribe las 12 columnas con lo enviado, y lo que va en null se limpia (la propia migración lo dice en un comentario). Se pierden número de cuenta, banco, nombre del DNI, dirección, celular y los tres enlaces de documentos. La tabla no guarda historial: solo `actualizado_por`/`actualizado_at`. No hay forma de recuperarlo desde la app. La misma pantalla de Equipo sí se protege de esto («si la carga falló, escribirlo pisaría el área real» — equipo/page.tsx:269-285); Datos personales no.

**Arreglo:** Dos cambios en `cargar()`: (a) destructurar `error` de las tres consultas y, si la de `datos_personales` falló, poner un estado `fichasOk = false`, mostrar el aviso rojo y NO pintar el sello «sin ficha» (que hoy es una afirmación que no se puede sostener); (b) deshabilitar el botón «Guardar ficha» mientras `fichasOk` sea false, con el mismo texto que usa Equipo («no se pudo cargar la ficha actual — deshabilitado para no pisarla»). Aparte, y con más valor a largo plazo: que el guardado envíe solo los campos que cambiaron, o que el RPC distinga «vacío» de «no enviado» — hoy un formulario en blanco es indistinguible de un borrado intencional.

### 10. ~~Otorgar un descanso sustitutorio cambia el monto de un periodo YA PAGADO~~

> ✅ **CERRADO** por la migración 0093. Mismo hallazgo que el Crítico 2 y el Alto 8.

`esquema-integridad` · 💰 dinero · arreglo de **horas**

**Dónde:** supabase/migrations/0072_descanso_sustitutorio_acuerdo_previo.sql:29 (fn_otorgar_descanso_sustitutorio) y 0069_feriado_descanso_sustitutorio.sql:1 (tabla feriados_descanso_sustitutorio); pantalla apps/web/app/(admin)/admin/feriados/page.tsx:251 y :282

**Qué pasa:** El esquema permite que exista una fila de feriados_descanso_sustitutorio cuya fecha_feriado cae dentro de un periodos_planilla con estado='pagado'. fn_planilla_calcular no guarda ningún monto: recalcula todo en vivo desde jornadas, feriados y descansos sustitutorios cada vez que se abre la pantalla. Por eso 12 funciones (fn_set_feriado, fn_set_salario, fn_set_turno, fn_corregir_marcaje, fn_anular_marcaje, fn_set_vacaciones…) llevan el candado de 'periodo pagado' desde la 0037. fn_otorgar_descanso_sustitutorio y fn_quitar_descanso_sustitutorio no lo llevan, y son las dos que más mueven la aguja: OTORGADO anula la sobretasa del feriado laborado, quitarlo la devuelve. Es un botón normal de la pantalla Feriados, con carga por lote y fecha de feriado libre — nadie tiene que forzar nada.

**Arreglo:** Dejar de defender la regla función por función y ponerla en la tabla. Un trigger BEFORE INSERT/UPDATE/DELETE sobre feriados_descanso_sustitutorio que rechace cualquier fila cuya fecha_feriado o fecha_descanso_sustitutorio caiga en un periodo 'pagado' cierra el hueco hoy; lo que de verdad corresponde es el mismo trigger sobre todas las tablas que fn_planilla_calcular lee (jornadas, marcajes, feriados, vacaciones, asignaciones_salario, movimientos_planilla, feriados_descanso_sustitutorio), para que el candado sea una propiedad del dato y no de quien lo escribe. Mientras tanto, agregar el `if exists (… estado='pagado' …) then raise` a las dos funciones.

### 11. ~~El semáforo disciplinario cuenta HOY como falta después de las 7pm y salta a ROJO~~

> ✅ **CERRADO** por la migración 0091.

`esquema-integridad` · ⚖️ decisión injusta · arreglo de **minutos**

**Dónde:** supabase/migrations/0079_suspension_no_es_falta.sql:163 (fn_faltas_resumen, `coalesce(p_as_of, current_date) - 1 as fin`) contra 0079:84 (fn_faltas, que sí usa `(now() at time zone 'America/Lima')::date - 1`); llamada sin p_as_of desde admin/disciplina/page.tsx:84, admin/dashboard/page.tsx:128 y adm…

**Qué pasa:** El servidor de Supabase corre en UTC — el propio repo lo documenta en 0034:82 y 0035:1. `current_date` desnudo resuelve en UTC, así que entre las 19:00 y las 24:00 hora de Lima el servidor ya cree que es mañana. fn_faltas_resumen define su ventana como 'hasta ayer' (`current_date - 1`) justamente para no acusar a nadie por el día en curso; con la hora de UTC ese 'ayer' es HOY. La misma migración 0079 arregló fn_faltas (el detalle) con la hora de Lima y dejó fn_faltas_resumen (los contadores) con current_date. Resultado: cada tarde, la pantalla Disciplina se contradice consigo misma y los contadores que disparan el umbral legal del D.S. 003-97-TR (4 consecutivas / 6 en 30 d / 16 en 180 d) cuentan un día que todavía no terminó y cuya justificación probablemente se cargue mañana.

**Arreglo:** Reemplazar los dos `current_date` de fn_faltas_resumen por `(now() at time zone 'America/Lima')::date`, igual que ya hace fn_faltas doce líneas más arriba en el mismo archivo. Y para que no vuelva a pasar una cuarta vez: prohibir `current_date` en el esquema con una prueba pgTAP que recorra pg_proc y falle si alguna función del sistema lo usa desnudo — es la tercera vez que este mismo bug entra (0034, 0035, y ahora 0079).

### 12. fn_registrar_marcaje no tiene ni una prueba, y por ahí la cola offline reescribe una planilla ya pagada

`pruebas-y-ci` · 💰 dinero · arreglo de **horas**

**Dónde:** supabase/tests/ (falta el archivo) · fn_registrar_marcaje, definida por última vez en supabase/migrations/0068_marcajes_fuera_de_orden.sql

**Qué pasa:** Los 15 archivos de prueba insertan marcajes con INSERT directo a la tabla; ninguno llama a fn_registrar_marcaje. Es la única función que el terminal usa de verdad, la que CLAUDE.md declara puerta única de escritura, y la única de la familia (anular, corregir, confirmar, reactivar, agregar todas lo tienen) que NO comprueba si la fecha cae en un periodo ya pagado. Una Mac mini que estuvo sin internet vacía su cola con marcas de días ya pagados, entran sin resistencia, el trigger recalcula la jornada, y la planilla de un periodo cerrado cambia de número en silencio. La regla 'nada puede alterar un periodo de planilla ya pagado' está blindada en cinco puertas y abierta en la sexta, que es la que más se usa.

**Arreglo:** Archivo nuevo supabase/tests/91_registrar_marcaje.test.sql con, como mínimo: (1) throws_like(fn_registrar_marcaje con fecha dentro de un periodo 'pagado', '%PAGADO%') — hoy falla, y es la prueba que obliga a poner el candado en fn_registrar_marcaje igual que en las otras cinco; (2) idempotencia: dos llamadas con el mismo client_uuid devuelven el mismo marcaje y dejan una sola fila; (3) reconciliación: una salida_final real que llega después de un auto_cierre del mismo día reemplaza la sintética, no la duplica; (4) marca atrasada de la cola offline que encaja bien en la secuencia NO sella el día. Luego agregar el bloque de periodo pagado a fn_registrar_marcaje en una migración.

### 13. Cesar y reactivar a una persona (mig 0086, ya en main) sin ninguna prueba: al reactivarla la planilla le paga S/0.00

`pruebas-y-ci` · 💰 dinero · arreglo de **horas**

**Dónde:** supabase/migrations/0086_fecha_de_cese.sql:145-147 y :168-182 · supabase/tests/ (no existe 86_*.test.sql)

**Qué pasa:** fn_cesar_persona cierra los tramos abiertos: `update asignaciones_salario set vigente_hasta = p_fecha_cese` y lo mismo en horarios_asignados. fn_reactivar_persona devuelve estado='activo' y limpia fecha_cese, pero NO vuelve a abrir esos dos tramos. Un cese registrado por error — el caso exacto para el que la propia migración dice que se conserva reactivar, 'porque a veces la baja fue un error' — deja a la colaboradora activa, marcando todos los días, y sin salario vigente ni horario vigente: fn_planilla_calcular le paga cero, y como tampoco tiene horario el motor de faltas y tardanzas deja de verla. La migración se commiteó a main sin un solo archivo de prueba (no hay 84, 85, 86 ni 87 en supabase/tests/).

**Arreglo:** Archivo nuevo supabase/tests/86_cese_y_reactivacion.test.sql con: (1) tras cesar, salario y horario quedan cerrados en la fecha de cese; (2) tras reactivar, is(vigente_hasta, null) en ambos — esta aserción falla hoy y es la que fuerza el arreglo; (3) tras reactivar y trabajar el mes siguiente, is(pago_base, sueldo íntegro); (4) throws_like al intentar cesar dentro de un periodo pagado; (5) throws_like al registrar una marca posterior al cese (fn_marcaje_no_posterior_al_cese, hoy también sin prueba). El arreglo en fn_reactivar_persona es reabrir los tramos que el cese cerró en esa misma fecha.

### 14. Corregir un auto-cierre desde Correcciones deja DOS salidas finales y paga horas que no existieron

`consistencia-deuda` · 💰 dinero · arreglo de **horas**

**Dónde:** supabase/migrations/0037_candado_periodo_pagado.sql:74 (fn_agregar_marcaje, definición viva) · apps/web/app/(admin)/admin/correcciones/page.tsx:324

**Qué pasa:** Hay dos caminos para meter una salida final: fn_registrar_marcaje (terminal) y fn_agregar_marcaje (botón «Agregar marcaje» de Correcciones). El primero RECONCILIA: si el cron nocturno ya inventó una salida sintética ese día, la reemplaza. El segundo simplemente inserta. Resultado: la encargada arregla el día de alguien que olvidó marcar salida, escribe la hora real, la pantalla dice «Corrección guardada y registrada en la auditoría» — y el día se queda con la salida real Y la del auto-cierre. El recálculo se queda con la más tardía, que es la inventada.

**Arreglo:** Mover el bloque de reconciliación de fn_registrar_marcaje (el que reemplaza la salida_final de origen 'auto_cierre' del mismo día) a fn_agregar_marcaje, o mejor: que fn_agregar_marcaje delegue en fn_registrar_marcaje con p_origen='admin_correccion' en vez de tener su propio INSERT. Segunda opción preferible: elimina la copia en vez de sincronizarla. Añadir prueba pgTAP que compare las dos vías con el mismo caso y falle si las horas difieren.


---

## Alta — 20

### 1. El bono de puntualidad se mide contra los días transcurridos, pero se escribe como dinero real

`planilla-dinero` · 💰 dinero · arreglo de **minutos**

**Dónde:** supabase/migrations/0034_bono_puntualidad.sql:85 (redefinida en 0053_levantar_tardanza.sql:97) — `v_dias_periodo := least(v_fin, hoy) - v_ini + 1`; el insert a movimientos_planilla en 0053:~130; texto del diálogo en apps/web/app/(admin)/admin/planilla/page.tsx:783

**Qué pasa:** El umbral de asistencia del 51 % se divide entre los días ya transcurridos del periodo, no entre los días del periodo. Eso está comentado como intencional para que el número «se vea» mientras el mes corre — pero la función no calcula una vista previa: hace INSERT en `movimientos_planilla`, que es la tabla que suma al total y que fn_periodo_pagado congela tal como esté. Nada obliga a recalcular antes de pagar. Si alguien pulsa el botón el día 3 para curiosear y no vuelve a pulsarlo, los S/60 quedan puestos y se pagan. Encima el diálogo de confirmación de la pantalla dice literalmente «Esto calcula el bono de puntualidad de todo el periodo», que es lo contrario de lo que hace: quien lo lee no tiene forma de saber que el resultado depende del día en que pulsó.

**Arreglo:** Separar las dos cosas que hoy están enredadas: el vistazo y el pago. Que fn_calcular_bono_puntualidad reciba un parámetro `p_solo_simular boolean default true` y con `true` devuelva el JSON sin tocar movimientos_planilla; que el INSERT solo ocurra con `false` y únicamente cuando `v_fin <= hoy` (periodo terminado), usando entonces el denominador completo `v_fin - v_ini + 1`. Mientras eso llega, el arreglo de minutos es que fn_periodo_pagado recalcule el bono antes de congelar. Y corregir el texto del diálogo: hoy promete «todo el periodo» y entrega «lo que va del periodo».

### 2. ~~El auto-cierre produce horas NEGATIVAS y le descuentan sueldo a quien sí trabajó~~

> ✅ **CERRADO** por la migración 0095: entró el `greatest(...)` en fn_auto_cierre y el `check (horas_trabajadas is null or horas_trabajadas >= 0)` en `jornadas` — el estado imposible ahora lo impide el esquema, no el código. Prueba en `96_ni_horas_negativas_ni_reabrir_sin_motivo.test.sql`.

`asistencia-jornadas` · 💰 dinero · arreglo de **minutos**

**Dónde:** supabase/migrations/0089_lo_que_encontro_la_auditoria_del_26.sql:83-84 (fn_auto_cierre) · supabase/migrations/0081_marcas_se_anulan_no_se_borran.sql:179 (fn_recalcular_jornada)

**Qué pasa:** fn_auto_cierre estampa la salida sintética en `fecha + hora_salida programada` sin compararla con las marcas reales del día. Si la persona entró DESPUÉS de su hora programada de salida (turno equivocado, entró en la tarde para un evento nocturno o un cierre de inventario) y olvidó marcar su salida, el auto-cierre pone la salida ANTES de la entrada. fn_recalcular_jornada resta sin ningún piso: `salida − entrada` da negativo y se guarda. No hay constraint en `jornadas` que lo impida, y fn_planilla_calcular hace `coalesce(horas_trabajadas, 0)` y las suma tal cual: el día trabajado RESTA horas del mes.

**Arreglo:** Dos líneas. En fn_auto_cierre: `v_ts_cierre := greatest((fecha + hora_salida) at time zone 'America/Lima', (select max(timestamp_marca) ...))` — la salida inventada nunca puede ser anterior a una marca real. Y un constraint en `jornadas`: `check (horas_trabajadas is null or horas_trabajadas >= 0)`, porque un número negativo de horas es un estado que no debe poder existir, no algo que se valide en el código.

### 3. El cron de auto-cierre reescribe periodos de planilla YA PAGADOS

`asistencia-jornadas` · 💰 dinero · arreglo de **horas**

**Dónde:** supabase/migrations/0089_lo_que_encontro_la_auditoria_del_26.sql:31-129 (fn_auto_cierre, sin ninguna mención a periodos_planilla) · supabase/migrations/0068_marcajes_fuera_de_orden.sql:94 (fn_registrar_marcaje, ídem) · fn_periodo_pagado (marca pagado sin verificar nada)

**Qué pasa:** fn_set_turno, fn_set_descanso, fn_quitar_turno, fn_set_horario_semanal, fn_agregar_marcaje, fn_anular_marcaje, fn_corregir_marcaje, fn_reactivar_marcaje, fn_eliminar_marcaje y fn_confirmar_auto_cierre todas verifican `periodos_planilla.estado = 'pagado'` antes de escribir. Las dos únicas que NO lo hacen son las dos que corren sin una persona delante: fn_registrar_marcaje (cola offline del terminal) y fn_auto_cierre (cron cada 15 min, migración 0007:118). Una marca rezagada de la cola offline con fecha dentro de un periodo pagado se acepta, deja la jornada 'abierta', y el siguiente barrido del cron le inventa una salida final — todo dentro del periodo pagado. Como los montos pagados no se congelan en ninguna tabla (fn_planilla_calcular recalcula desde `jornadas` cada vez), el número de una planilla ya pagada cambia solo.

**Arreglo:** Mismo candado que ya tienen las otras diez funciones, en los dos caminos automáticos. En fn_auto_cierre: dentro del loop, `continue` si la fecha de la candidata cae en un periodo 'pagado', dejando en su lugar una fila en `alertas` para que alguien lo vea (avisar, no romper el cron). En fn_registrar_marcaje: aceptar igual la marca —jamás perder una marca real, ese es el criterio de la 0068— pero sellarla `pendiente_revision` y alertar, en vez de dejar que recalcule en silencio. Y en fn_periodo_pagado, negarse a marcar PAGADO si quedan jornadas 'abierta'/'en_pausa'/'auto_cerrada_pendiente' en el rango: es el candado que estado.md ya tiene anotado como acordado y sin construir.

### 4. Trabajar un feriado genera tardanzas que empujan hacia la amonestación

`asistencia-jornadas` · ⚖️ decisión injusta · arreglo de **horas**

**Dónde:** supabase/migrations/0067_tardanzas_faltas_as_of.sql:25-52 (fn_tardanzas_resumen) · supabase/migrations/0059_generar_tardanza.sql:66 (fn_expediente_generar_tardanza) · comparar con fn_faltas, que sí excluye feriados

**Qué pasa:** fn_recalcular_jornada no conoce los feriados: en un feriado el horario_por_dia sigue vigente, así que mide la tardanza contra la hora normal de entrada. Y fn_tardanzas_resumen —el semáforo que decide 'aviso' o 'amonestacion'— solo excluye personas inactivas, sueldo_fijo, fuera de planilla y días con justificación previa; no excluye feriados ni vacaciones. fn_faltas sí los excluye explícitamente. Las dos mitades del mismo motor disciplinario aplican reglas distintas: la persona que vino voluntariamente un feriado (y a la que se le paga la sobretasa) acumula tardanzas por llegar tarde a un día en el que no tenía obligación de venir. Es exactamente el falso positivo que el proyecto define como el peor error, y alimenta un expediente que la ley (D.S. 003-97-TR art. 25) exige que sea sólido.

**Arreglo:** Copiar la exclusión que fn_faltas ya tiene, a las tres funciones que cuentan tardanzas (fn_tardanzas_resumen, fn_expediente_generar_tardanza, fn_calcular_bono_puntualidad): no contar un día que sea feriado sin turno explícito asignado, ni un día de vacaciones o descanso sustitutorio. Si el feriado tiene turno explícito asignado (se le programó trabajar), la tardanza sí es medible — igual criterio que faltas, para que las dos mitades del motor digan lo mismo.

### 5. ~~La suspensión se calcula en días de calendario: una 'suspensión de 3 días' desde el viernes es 1 día real~~

> ✅ **CERRADO el 2026-08-10**, y **dos de sus tres afirmaciones eran falsas.**
> Medido contra producción con
> [`revisar_expediente_de_tardanzas.sql`](../scripts/sql-manual/revisar_expediente_de_tardanzas.sql),
> no razonado.
>
> **1 · «La 0075 no está aplicada en producción» — FALSO.** Están las dos
> funciones y la columna. El encabezado de la propia 0075 lo decía desde julio
> («aplicada en producción DESPUÉS de la 0071-0073 de main») y este documento
> afirmaba lo contrario sin medirlo. Ganó el encabezado.
>
> **2 · «El memo de Mateo imprime 3 día(s), del 24 al 26 de julio» — FALSO hoy.**
> El registro de producción del T-02/0002-2026-CAYLA dice **1 día, fechas
> exactas: 2026-07-27**, que fue **lunes**, y ese día no tiene marcas: la sanción
> se cumplió. `suspension_fechas` solo la escribe `fn_expediente_set_suspension`,
> así que ese memo se corrigió por esa vía el mismo día en que se detectó el
> defecto — el 25/07/2026, que fue sábado, la fecha que la 0075 lleva en su
> encabezado. El daño se reparó entonces; este documento se quedó describiendo el
> minuto anterior a la reparación.
>
> **3 · «Ningún archivo de apps/web la llama» — era cierto, y ya no.** Es lo único
> que quedaba en pie, y lo cierra la
> [`0200`](../supabase/migrations/0200_el_semaforo_sabe_en_que_escalon_esta_cada_quien.sql):
> `guardarDias` llama a `fn_expediente_set_suspension`, muestra las fechas
> concretas y avisa cuando se salta un descanso; el memo las imprime una por una
> en vez de un rango. Hasta hoy la corrección solo existía si alguien la aplicaba
> a mano desde el SQL Editor, como pasó con este memo.
>
> **La lección de método:** un hallazgo escrito sobre una base local de auditoría
> describió como roto en producción algo que llevaba dos semanas arreglado, y
> señaló a una persona concreta. Medir contra la base antes de proponer —la regla
> que CLAUDE.md ya tenía escrita— habría costado un `select`.

`disciplina-legal` · ⚖️ decisión injusta · arreglo de **horas**

**Dónde:** apps/web/app/(admin)/admin/disciplina/page.tsx:169-179 (guardarDias → addDias(desde, dias - 1)) · supabase/migrations/0059_generar_tardanza.sql:82-84 (default current_date + 1)

**Qué pasa:** El panel fija suspension_hasta sumando días de calendario y el generador propone por defecto 'mañana', sin preguntar si a esa persona le tocaba trabajar. Una suspensión sin goce de haber que cae en el día de descanso no es una sanción: la persona no deja de trabajar nada ni deja de cobrar nada. La 0075 se escribió justo para esto (documenta el caso real de Mateo, 25/07/2026, a quien le tocó un sábado que no trabaja) y aporta fn_dias_suspension / fn_es_dia_laborable — pero no está aplicada en producción y, aunque lo estuviera, ningún archivo de apps/web la llama. El memo entonces imprime 'SUSPENSIÓN SIN GOCE DE HABER por 3 día(s), del 24 al 26 de julio' cuando el efecto real fue un solo día.

**Arreglo:** Aplicar la 0075 y hacer que guardarDias llame a fn_dias_suspension(persona, desde, dias) en vez de addDias: la función devuelve las fechas laborables concretas y el panel muestra el salto ('del jueves al lunes, se salta el descanso'). Mientras tanto, la pantalla debe al menos advertir cuando el rango propuesto incluye un día no laborable, porque hoy la encargada no tiene forma de darse cuenta.

### 6. El guard del terminal en fn_registrar_marcaje cae abierto si el terminal no tiene auth_user_id: cualquiera fabrica marcas ajenas

`seguridad-permisos` · 💰 dinero · arreglo de **minutos**

**Dónde:** supabase/migrations/0082_todo_el_sistema_conoce_las_anuladas.sql:315 (definición vigente de fn_registrar_marcaje) · columna terminales.auth_user_id, nullable

**Qué pasa:** El único candado que impide que una sesión cualquiera se haga pasar por un terminal es 'if auth.uid() is not null and v_terminal_auth is not null and auth.uid() <> v_terminal_auth then raise'. Son tres condiciones unidas por AND: si terminales.auth_user_id es null, la segunda es falsa y no se lanza nada — la sesión pasa. Es la misma familia del 'if not X' que la 0078 vino a corregir, pero escrita al revés: aquí el null no viene del rol sino de una columna nullable. Y terminales.auth_user_id ES nullable, sin constraint que lo ate a activo. No hay pantalla de administración que cree terminales (no existe ningún .from("terminales") de escritura en apps/web): las filas se insertan a mano en el SQL Editor, y la vinculación (apps/web/app/(terminal)/terminal/vincular/page.tsx) solo hace signInWithPassword — no escribe auth_user_id. O sea: entre que Felipe da de alta un terminal y alguien le asocia su usuario, la fila vive con auth_user_id null y activo=true. Con la marca forjada entra una jornada completa que la planilla paga.

**Arreglo:** Cambiar la condición a que exija identidad en vez de tolerar su ausencia: 'if v_terminal_auth is distinct from auth.uid() then raise exception …' (así el null del terminal también rebota), y cerrar el estado imposible en el esquema — 'alter table terminales add constraint terminal_activo_vinculado check (not activo or auth_user_id is not null)'. Un terminal activo sin dueño no debería poder existir. Antes de aplicar el check, correr en producción: select id, nombre_dispositivo, sede_id from terminales where activo and auth_user_id is null;

### 7. ~~Una encargada puede borrar el horario de su equipo sin dejar rastro~~

> ✅ **CERRADO el 2026-08-08** por la
> [`0184`](../supabase/migrations/0184_las_dos_puertas_de_horario_que_nadie_usa_se_cierran.sql):
> `fn_set_horario` y `fn_quitar_horario` dejaron de existir. Aplicada y
> confirmada en producción — `puertas_que_quedan: 0`.
>
> Se borraron en vez de parchearlas: copiarles el candado habría dejado dos
> copias de una regla que ya vive en `fn_set_horario_semanal`, y la próxima
> corrección se habría aplicado a una sola. Se comprobó por tres caminos que
> nadie las usaba —pantallas, cuerpos de otras funciones, triggers— y la
> auditoría en `BEGIN … ROLLBACK` verificó que `fn_set_horario_semanal`
> sobrevive: su nombre empieza igual, y un `drop` mal escrito se la llevaba.
>
> **Nota de método, que vale más que el arreglo.** El título original decía
> «…y reescribe las tardanzas de un mes YA PAGADO». Medido antes de creerlo, esa
> mitad era falsa: `fn_recalcular_jornada` lleva su propio candado desde la 0138,
> que entró unas horas después de escribirse este hallazgo. Lo que sí se
> reprodujo —y fue el motivo real del borrado— es que en el periodo ABIERTO la
> llamada deja la tardanza en NULL sin auditoría, y que sin horario la persona
> desaparece de `fn_faltas` y `fn_faltas_resumen`, que lo exigen.

<details><summary>El diagnóstico original, para el registro</summary>

> ⚠️ **LA MITAD CARA DE ESTE HALLAZGO NO ERA CIERTA.** Medido el 2026-08-08
> reproduciendo el caso entero: junio pagado, una persona con 45 minutos de
> tardanza el 16, y la llamada hecha por una **encargada de sede** (no una
> administradora). `fn_quitar_horario` **pasa** —no tiene candado, eso sigue
> siendo verdad— pero **la tardanza se queda en 45**. El daño lo frena un piso
> más abajo: `fn_recalcular_jornada` lleva su propio candado desde la
> [`0138`](../supabase/migrations/0138_un_periodo_pagado_no_cambia_de_horas.sql),
> que entró el 04/08 a las 17:40 — el mismo día en que se curó este catálogo, así
> que la curación no la vio.
>
> **Lo que SÍ se reprodujo, con junio abierto:** la misma llamada deja la
> tardanza en **nada** (de 45 a NULL) y `correcciones_auditoria` sigue en cero.
> Y quedarse sin horario no es cosmético: `fn_faltas` y `fn_faltas_resumen`
> exigen horario, así que esa persona **desaparece del motor de faltas**. En el
> periodo abierto —el que se paga el 28— eso sí pasa.
>
> **Sigue valiendo la pena borrarlas**, pero por lo que son: superficie RPC
> muerta. No por lo que este título decía.

`seguridad-permisos` · 💰 dinero · arreglo de **minutos**

**Dónde:** fn_set_horario (supabase/migrations/0015_horario_base_dias_refrigerio.sql:14) y fn_quitar_horario (supabase/migrations/0011_editor_horarios.sql:48)

**Qué pasa:** Las dos recalculan todas las jornadas desde la fecha de vigencia hacia adelante, y ninguna comprueba si esas fechas caen en un periodo pagado. Su gemela fn_set_horario_semanal sí lo comprueba y lanza 'Ese horario tocaría un periodo ya PAGADO'. Es el caso 2 de Brooks: dos funciones que hacen lo mismo, una con candado y otra sin. Además el permiso lo da fn_verificar_corrector, que autoriza a supervisor_sede sobre cualquier persona de su sede — así que no hace falta ser admin. Y ninguna escribe en correcciones_auditoria. Lo que se altera no es cosmético: minutos_tarde alimenta el bono de puntualidad (dinero de un mes ya cerrado) y el expediente disciplinario (D.S. 003-97-TR). Detalle que decide el arreglo: ninguna pantalla las llama — el panel solo usa fn_set_horario_semanal (turnos/page.tsx:336 y :684, horarios/page.tsx:186). Son superficie RPC muerta que sigue con grant a authenticated.

**Arreglo:** Borrar antes que parchear: como ninguna pantalla las usa, lo más limpio es 'drop function fn_set_horario(...)' y 'drop function fn_quitar_horario(...)' — código que no existe no se puede llamar por RPC. Si se prefiere conservarlas, copiarles literalmente el bloque de candado de fn_set_horario_semanal ('if exists (select 1 from periodos_planilla where estado = ''pagado'' and fecha_fin >= p_vigente_desde) then raise …') y hacer que registren en correcciones_auditoria como el resto de las correcciones.

</details>

### 8. ~~El descanso sustitutorio cambia el monto de un periodo de planilla YA PAGADO, sin candado y sin rastro~~

> ✅ **CERRADO** por la migración 0093. Mismo hallazgo que el Crítico 2 y el Crítico 10.

`vacaciones-feriados` · 💰 dinero · arreglo de **minutos**

**Dónde:** supabase/migrations/0072_descanso_sustitutorio_acuerdo_previo.sql:36-90 (fn_otorgar_descanso_sustitutorio) y :92-101 (fn_quitar_descanso_sustitutorio)

**Qué pasa:** Marcar un feriado como OTORGADO anula la sobretasa; borrar el registro la devuelve. Ambas funciones mueven el monto del feriado, y ninguna de las dos verifica si la fecha del feriado cae en un periodo `pagado`. Todas sus hermanas sí lo hacen: fn_set_feriado, fn_quitar_feriado, fn_set_vacaciones, fn_quitar_vacaciones, fn_set_descanso y fn_agregar_movimiento levantan la misma excepción. Como `periodos_planilla` no guarda foto de los montos y fn_proyeccion_periodo recalcula desde cero cada vez que se abre la pantalla, lo que la Planilla y la boleta muestran de un mes pagado deja de coincidir con lo que se depositó — y no queda fila en `reversas_pago`, que es el mecanismo de auditoría diseñado justo para esto (0066).

**Arreglo:** Copiar el candado que ya usan fn_set_feriado y fn_quitar_feriado en ambas funciones, comparando contra `fecha_feriado` (y también contra `fecha_descanso_sustitutorio`, porque el día compensatorio no marcado afecta el pago del mes en que cae): si toca un periodo `pagado`, exigir que se reabra primero con fn_revertir_pago, que sí pide motivo y deja rastro.

### 9. El día compensatorio puede caer sobre vacaciones, sobre otro feriado o antes del feriado que compensa

`vacaciones-feriados` · 💰 dinero · arreglo de **horas**

**Dónde:** supabase/migrations/0069_feriado_descanso_sustitutorio.sql:91-158 (fn_dcs_validar_dia_laborable) y :97-155 del trigger trg_dcs_validar_dia

**Qué pasa:** El trigger fue escrito con una intención explícita en su propio comentario: «Un día libre sobre un día que ya era libre no compensa nada: sería regalar la sobretasa a cambio de nada». Pero solo mira el descanso semanal (turno puntual → horario_por_dia → dias_laborables). No consulta la tabla `vacaciones`, no consulta la tabla `feriados`, y no compara la fecha del descanso contra la del feriado. Resultado: se puede compensar un feriado laborado con un día en que la persona ya estaba de vacaciones pagadas, con otro feriado, o incluso con un día seis meses ANTERIOR al feriado que dice compensar. En los tres casos la persona entrega la sobretasa y no recibe descanso alguno, y la compensación es nula ante fiscalización (el D.S. 012-92-TR exige el descanso sustitutorio dentro de la semana siguiente, y por definición después del feriado trabajado).

**Arreglo:** Extender fn_dcs_validar_dia_laborable con las tres verificaciones que faltan, con el mismo mensaje en lenguaje de negocio que ya usa: (a) rechazar si `new.fecha_descanso_sustitutorio` cae dentro de un periodo de `vacaciones` de esa persona; (b) rechazar si esa fecha existe en `feriados`; (c) rechazar si es anterior o igual a `new.fecha_feriado`. Vale la pena además avisar (no bloquear) cuando pasa de una semana del feriado, que es el plazo del D.S. 012-92-TR. Al ser un trigger, protege por igual a la pantalla y a cualquier carga por lotes.

### 10. ~~El CSV de asistencia y el resumen de horas se cortan en 1000 filas sin avisar~~

> ✅ **CERRADO el 2026-08-04.** Nuevo helper `apps/web/lib/admin/traer-todo.ts`: trae por lotes de 1000 hasta agotar, y si algo falla devuelve error en vez de una lista corta. Aplicado a las cuatro consultas del hallazgo — Exportar, Horas, Reporte-sede e Incidencias (las dos). A Horas y a Reporte-sede hubo que **añadirles orden** (`fecha` + `persona_id`): paginar sin un orden estable repite filas y pierde otras, que es peor que no paginar. Seis pruebas en `tests/traer-todo.test.ts`, incluida la del múltiplo exacto de 1000.
>
> Las otras consultas a `jornadas` (Dashboard, Correcciones, Perfil) se revisaron y **no** necesitan lotes: están acotadas a un solo día o a una sola persona.

`frontend-admin` · 💰 dinero · arreglo de **horas**

**Dónde:** apps/web/app/(admin)/admin/exportar/page.tsx:24-31 · apps/web/app/(admin)/admin/horas/page.tsx:62 · también reporte-sede/page.tsx:92 e incidencias/page.tsx:130-134

**Qué pasa:** Las cuatro consultas piden `jornadas` por rango de fechas sin `.range()`, sin `.limit()` y sin pedir `count`. PostgREST corta la respuesta en `max_rows` y devuelve 200 OK con las primeras N filas: supabase-js no reporta nada, `error` es null. En Exportar la consulta va `.order("fecha")` ascendente, así que lo que se pierde son los días MÁS RECIENTES — el CSV se descarga entero, se abre bien en Excel y simplemente termina antes, sin ninguna marca. Ese archivo es el que va al contador. En Horas no hay `order`, así que las filas que se caen son arbitrarias: el total de horas de gente al azar sale corto, y el botón «Todo el año» es el camino directo al problema. Con ~28 personas que marcan y ~26 días laborables, un mes son ~730 filas: el tope se cruza al pedir dos meses. Hoy hay poco más de un mes de datos en producción, así que esto empieza a fallar en agosto.

**Arreglo:** Paginar: pedir con `.range(desde, desde+999)` en bucle hasta que un lote venga con menos de 1000 filas, o mejor, mover la agregación a un RPC (`fn_horas_resumen(p_desde, p_hasta)`) que devuelva una fila por persona en vez de una por jornada — el resumen de horas ya suma en el cliente algo que Postgres agrega mejor, y una fila por persona nunca se acerca al tope. Como red de seguridad inmediata mientras tanto: pedir `{ count: 'exact' }` y, si `count > filas.length`, bloquear la descarga con un aviso explícito en vez de entregar un archivo incompleto.

### 11. El memo en borrador sigue imprimiéndose «De: Felipe Alvarez · Gerencia General» — 🟡 medio cerrado

> 🟡 **MITAD CERRADA, mitad viva.** Verificado el 2026-08-08, línea por línea.
> **Ya no miente sobre el número:** el papel imprime «BORRADOR — sin numerar»
> donde iría el correlativo (`:218`), así que un borrador impreso se distingue.
> **Sigue mintiendo sobre quién lo suscribe:** `firmante` arranca en
> `EMPRESA.firmante` (`:51`) y solo se reemplaza dentro de `if (doc.firmante_id)`
> (`:95`), que en un borrador es null — de modo que `:227` imprime
> «De: Alvarez Pereyra Felipe Miguel · Gerencia General» en un documento que
> nadie ha firmado. El botón «Imprimir» (`:190`) sigue sin `disabled`, y el
> aviso de borrador sigue con `no-print` (`:207`).
> **Lo que queda por hacer son dos líneas:** no caer al firmante por defecto
> cuando `firmante_id` es null, y quitarle el `no-print` al aviso.

`frontend-admin` · ⚖️ decisión injusta · arreglo de **minutos**

**Dónde:** apps/web/app/(admin)/admin/disciplina/memo/[id]/page.tsx:49,55,93,208,243-244

**Qué pasa:** `firmante` y `cargoFirmante` arrancan con los valores fijos de la constante EMPRESA («Alvarez Pereyra Felipe Miguel» / «Gerencia General»). Solo se reemplazan si `doc.firmante_id` existe y además la fila de esa persona vuelve en la consulta a `personas`. Un borrador tiene `firmante_id` en null por definición, así que ninguna de las dos condiciones se cumple: el documento se pinta con «De: Alvarez Pereyra Felipe Miguel · Gerencia General» en la cabecera y con el mismo nombre y cargo bajo la línea de firma. Y el botón «Imprimir / Guardar PDF» está activo (se muestra siempre que `doc && !err`), al que se llega con un clic desde el botón «Ver memo» de cada borrador en Disciplina. El aviso de «borrador sin numerar» lleva la clase `no-print`: desaparece justo en el papel. Resultado: se puede imprimir y entregar un acta o amonestación que dice que la suscribió Gerencia General cuando nadie la ha firmado. El comentario de las líneas 50-54 explica que este archivo se cambió precisamente para que el memo no mintiera sobre quién lo suscribió; el valor por defecto sigue mintiendo. La misma ruta se activa cuando la consulta a `personas` falla o cuando RLS no devuelve al firmante (`personas_select_supervisor` solo expone la sede propia): ahí `ps` no se comprueba y `p` queda en null, así que el memo sale además dirigido a «—» con «DNI —» y se sigue pudiendo imprimir.

**Arreglo:** Cuando `doc.firmante_id` sea null, no inventar firmante: dejar la línea «De:» y el bloque de firma en blanco (o «pendiente de firma») y deshabilitar el botón de imprimir con el motivo escrito al lado. Cuando `firmante_id` exista pero su fila no se pueda leer, mostrar el error en pantalla en vez de caer al default. Y quitar `no-print` del aviso de borrador: si de verdad hace falta imprimir un borrador para revisarlo, el papel tiene que decir que es un borrador. Mismo tratamiento para `persona`: sin destinatario no hay documento que imprimir.

### 12. La Hoja de sede no revisa el error de ninguna de sus 8 consultas y se imprime en ceros

`frontend-admin` · ⚖️ decisión injusta · arreglo de **horas**

**Dónde:** apps/web/app/(admin)/admin/reporte-sede/page.tsx:80-143

**Qué pasa:** Ninguna de las ocho consultas de `cargar()` destructura `error` (solo `areasRaw` lo hace, y para pasárselo a `parseAreas`). Si la de `jornadas` falla, `jorPorPersona` queda vacío y `filasCalc` se construye igual: todo el equipo con Días 0, Horas «0h 00m», Tardanzas «—», Sal. antic. «—». `setCargado(true)` se ejecuta pase lo que pase, así que el botón «Descargar PDF» se habilita y la hoja sale a papel diciendo que en esa sede nadie trabajó en el mes. Si la que falla es `fn_tardanzas_resumen` o `fn_faltas_resumen`, la sección «Necesita atención» imprime «Nada pendiente en disciplina. Buena señal.» — un falso negativo justo en el bloque que existe para no dejar pasar nada. Aparte hay una inconsistencia numérica propia: la línea 122 calcula `reales` para excluir los agregados históricos de 2025 (filas con más de 24 h), pero solo la usa para `dias` (:131); `horas`, `tardanzas` y `minTarde` (:132-134) siguen sumando sobre `js`, que los incluye. Al elegir un mes de 2025 la misma persona sale con los días de las jornadas reales y las horas de las jornadas reales MÁS el agregado.

**Arreglo:** Aplicar el mismo patrón que ya usan Horas e Incidencias: destructurar `error` de `personas` y `jornadas`, y si alguna falló, `setError(...)` + `return` sin tocar `filas` ni `setCargado(true)` — así el botón de PDF queda deshabilitado. Para las RPC de disciplina, distinguir «sin alertas» de «no se pudo consultar»: si fallan, la sección debe decirlo, no felicitar. Y usar `reales` (o `js`) de forma consistente en las cuatro métricas: hoy la misma fila cuenta para las horas y no para los días.

### 13. ~~fn_siguiente_tipo_esperado no filtra las anuladas en su última consulta — deja a la persona atrapada sin poder cerrar su día~~

> ✅ **CERRADO.** Verificado el 2026-08-08 contando sobre el cuerpo vigente:
> `anulada_at is null` aparece **tres** veces, una por cada consulta. La tercera
> —la que busca la última marca del día— ya lo lleva. Mismo hallazgo que el
> Alto 18.

`terminal-offline` · 💰 dinero · arreglo de **minutos**

**Dónde:** supabase/migrations/0082_todo_el_sistema_conoce_las_anuladas.sql:83-88

**Qué pasa:** La 0082 promete en su encabezado que 'ninguna función del sistema siga contando una marca anulada como si estuviera viva', y añade 'and anulada_at is null' a las dos primeras consultas de fn_siguiente_tipo_esperado (¿tiene entrada? ¿tiene salida final?). La tercera —la que busca la ÚLTIMA marca del día para decidir qué retorno toca— se quedó sin el filtro. Consecuencia: si la marca anulada es la última del día (el caso literal que la 0081 pone como ejemplo: una salida_almuerzo marcada por error), la función sigue devolviendo 'retorno_almuerzo' y fn_registrar_marcaje RECHAZA cualquier otra cosa. La persona no puede marcar su salida final. Como el terminal ve lo mismo (hallazgo anterior), su única opción en pantalla es marcar un retorno de un refrigerio que nunca ocurrió, que deja el día sellado como incoherente. Se anuló una marca para arreglar el día y el resultado es un día que no se puede cerrar.

**Arreglo:** Migración 0088 de una línea: añadir 'and anulada_at is null' al select de v_ultimo en fn_siguiente_tipo_esperado. Vale la pena acompañarla con una prueba pgTAP del caso 'última marca del día anulada → la persona puede elegir salida', porque es el único de los seis puntos de la 0082 que no quedó cubierto.

### 14. No hay service worker: sin internet el terminal no arranca, y toda la arquitectura offline supone que la pestaña nunca se recarga

`terminal-offline` · 🚫 operación bloqueada · arreglo de **dias**

**Dónde:** apps/web/next.config.ts (sin PWA) · apps/web/public/ (sin manifest ni sw.js) · apps/web/package.json (sin serwist/workbox/next-pwa)

**Qué pasa:** El terminal guarda roster e IndexedDB para trabajar sin conexión, y le dice a la gente 'se sincronizará cuando vuelva la conexión'. Pero la app se sirve desde Vercel sin service worker: el HTML y los chunks de JS se piden a la red en cada carga. Mientras la pestaña siga abierta, todo funciona; en cuanto la Mac mini se reinicia (corte de luz, actualización de macOS, alguien cierra Safari) durante una caída de internet, la pantalla que ve el equipo es el error del navegador y la sede se queda SIN forma de marcar. Peor: las marcas que ya estaban en la cola quedan encerradas en ese IndexedDB hasta que alguien logre volver a cargar la página, y sincronizarPendientes() solo corre mientras /terminal/marcar está montada.

**Arreglo:** Añadir un service worker mínimo que cachee el app shell del terminal (documento, chunks, css, tipografías) con estrategia cache-first y un manifest para abrirlo en modo standalone. No hace falta una PWA completa: basta con que /terminal/marcar levante sin red. Mientras tanto, dejar escrito en docs/terminales-mac-mini.md que la pestaña no se debe cerrar y que un reinicio durante un corte deja la sede sin marcaje.

### 15. La marca se encola DESPUÉS de intentar enviarla y el fetch no tiene tope de tiempo: con 'wifi conectado, internet caído' se pierde sin dejar rastro

`terminal-offline` · 💰 dinero · arreglo de **horas**

**Dónde:** apps/web/app/(terminal)/terminal/marcar/page.tsx:299-315 · packages/database/src/client.ts:17-23 (createClient sin fetch propio ni timeout)

**Qué pasa:** El flujo es 'intento enviar; si falla, encolo'. Todo el rato entre el toque de la persona y la respuesta del servidor la marca no existe en ninguna parte persistente. navigator.onLine solo dice si hay interfaz de red levantada, no si hay internet: el modo de falla habitual de una tienda (router encendido, ISP caído, o el enlace a medio morir) da onLine=true, así que se toma la rama en línea y el fetch se queda colgado hasta el timeout por defecto del navegador (decenas de segundos en Safari). Durante todo ese rato la pantalla se queda en 'Confirmando en 0s…' sin ningún indicio de que está esperando, con confirmandoRef bloqueado, y nadie más puede marcar. Si alguien pierde la paciencia y recarga o apaga —que es exactamente lo que hará alguien sin contexto técnico frente a una pantalla congelada— la promesa muere y encolarMarcaje NUNCA se ejecuta: la marca no queda ni en el servidor ni en la cola.

**Arreglo:** Invertir el orden: encolar SIEMPRE primero (await encolarMarcaje), recién después intentar el envío y borrar de la cola al confirmar el servidor —que es como ya funciona sync.ts—. Y ponerle tope al envío en vivo (AbortSignal.timeout de 8-10 s): pasado eso se da por 'quedó en cola' y la pantalla avanza. Con eso el corte de luz a mitad de un marcaje deja de perder la marca y la pantalla deja de poder congelarse.

### 16. fn_registrar_marcaje — la única puerta de escritura de marcajes — no tiene el candado de periodo pagado

`esquema-integridad` · 💰 dinero · arreglo de **horas**

**Dónde:** supabase/migrations/0068_marcajes_fuera_de_orden.sql:94 (última definición de fn_registrar_marcaje)

**Qué pasa:** Desde la 0037 llevan candado de periodo pagado fn_corregir_marcaje, fn_agregar_marcaje, fn_eliminar_marcaje, fn_anular_marcaje, fn_reactivar_marcaje, fn_set_turno, fn_set_descanso, fn_set_salario, fn_set_horario_semanal, fn_set_fecha_ingreso, fn_confirmar_auto_cierre y fn_agregar_movimiento. La que no lo lleva es fn_registrar_marcaje, que es precisamente la que el proyecto define como el único camino legítimo para escribir una marca. El timestamp lo pone el cliente (p_timestamp_cliente, el reloj de la Mac mini, que hoy no se verifica), así que una marca de la cola offline que se reenvía tarde, o una Mac con el reloj corrido, inserta la marca dentro del periodo pagado y el trigger recalcula la jornada sin decir nada. Ni siquiera queda en correcciones_auditoria, porque no es una corrección.

**Arreglo:** Un trigger BEFORE INSERT OR UPDATE OR DELETE en marcajes que rechace cualquier fila cuya fecha (en hora de Lima) caiga en un periodo 'pagado'. Es el mismo trigger del hallazgo 1 y resuelve los dos de una vez: el candado deja de ser una línea que hay que acordarse de copiar en cada función nueva y pasa a ser una propiedad de la tabla. Para el caso legítimo de la cola offline que llega tarde, el trigger debe dar un mensaje que le diga a la encargada qué hacer ('esa marca es del 15/06, un mes ya pagado — avisa a DO para reabrir el periodo'), no un error de Postgres crudo.

### 17. ~~La red de seguridad que describe CLAUDE.md no existe: ni el hook de pre-push ni desplegar.sh, y core.hooksPath apunta a un directorio inexistente~~

> ✅ **CERRADO.** Comprobado el 2026-08-04: `scripts/hooks/pre-push` y `scripts/desplegar.sh` existen, y `git config core.hooksPath` devuelve `scripts/hooks`. Además las pgTAP ya corren en esta Mac (`npx supabase test db`), que era el supuesto sobre el que se escribió el hallazgo.

`pruebas-y-ci` · 🧱 deuda · arreglo de **horas**

**Dónde:** CLAUDE.md sección 'La red de seguridad (jul-2026)' · scripts/hooks/ (no existe) · scripts/desplegar.sh (no existe) · .github/workflows/tests.yml

**Qué pasa:** CLAUDE.md documenta dos guardianes: scripts/hooks/pre-push (typecheck + vitest antes de subir) y scripts/desplegar.sh (verifica que las pruebas de GitHub de ese commit hayan pasado, incluidas las pgTAP que no corren en esta Mac porque no hay Docker, y recién ahí publica). Ninguno de los dos existe en el árbol ni en toda la historia de git. Peor: `git config core.hooksPath` está en 'scripts/hooks', un directorio que no existe, y git ante eso no protesta — simplemente no corre ningún hook, en silencio. Resultado: el único sitio donde corre pgTAP es GitHub Actions, nada obliga a mirarlo, y nada lo consulta antes de `npx vercel --prod`. Además el workflow no corre typecheck en ningún job (el pre-push inexistente era el único que lo hacía).

**Arreglo:** Crear scripts/hooks/pre-push (typecheck + pnpm test, y un chequeo de numeración duplicada en supabase/migrations — `ls supabase/migrations | cut -c1-4 | sort | uniq -d` habría atajado esto en un segundo) y scripts/desplegar.sh tal como los describe CLAUDE.md, commitearlos, y documentar `git config core.hooksPath scripts/hooks`. Añadir un job de typecheck al workflow. Mientras no existan, corregir CLAUDE.md: hoy describe protecciones que nadie tiene.

### 18. ~~Anular una salida temporal deja a la persona sin poder marcar su salida final~~

> ✅ **CERRADO.** Mismo hallazgo que el Crítico 13, y misma comprobación del
> 2026-08-08: las tres consultas de `fn_siguiente_tipo_esperado` filtran las
> anuladas. **Queda viva la mitad estructural**, que es de otro orden: la regla
> «qué toca marcar ahora» sigue escrita en dos idiomas —SQL y navegador— sin
> nada que compare las dos respuestas. Eso vive en `estado.md` como el punto 1
> de «Atender primero», no aquí.

`consistencia-deuda` · 🚫 operación bloqueada · arreglo de **minutos**

**Dónde:** supabase/migrations/0082_todo_el_sistema_conoce_las_anuladas.sql:82-87 (fn_siguiente_tipo_esperado)

> ✅ **CERRADO, y este documento no se había enterado.** Lo arregló la
> [`0129`](../supabase/migrations/0129_tres_agujeros_de_permiso_cerrados.sql),
> que lleva el filtro marcado con «⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩» y el defecto descrito
> en su encabezado. Medido el 2026-08-10 contra el esquema reconstruido:
> `anulada_at is null` aparece **3 veces** en el cuerpo vivo de
> `fn_siguiente_tipo_esperado` — las tres consultas, no dos.
>
> Y de paso: este hallazgo acusaba a `docs/estado.md` de mentir al decir que
> se había arreglado. **estado.md tenía razón y el hallazgo no.** Es la
> tercera entrada de este documento que en un solo día describe como roto
> algo que ya estaba arreglado — las otras dos fueron la A5 y la C12.
>
> **Confirmar en producción** antes de darlo por bueno del todo:
> `select md5(prosrc) from pg_proc where proname = 'fn_siguiente_tipo_esperado';`
> debe dar `eb19e1a5549190fc3f167adc7f2195da`.

**Qué pasaba (antes de la 0129):** La 0082 prometió que ninguna función siguiera contando una marca anulada. Dentro de fn_siguiente_tipo_esperado hay tres consultas: las dos primeras filtran anulada_at is null, la tercera —la que mira cuál fue la última marca del día— no. Si se anula una salida a almuerzo (o cualquier salida temporal), el servidor sigue creyendo que la persona está fuera y solo acepta su «regreso». El navegador, en cambio, SÍ filtra las anuladas (apps/web/lib/terminal/estado-dia.ts:24), así que el terminal le muestra el botón de salida y el servidor lo rechaza. Sumado al borde ya conocido de «marca rechazada que se anuncia como Listo», la persona cree que marcó y no marcó: el día se cierra solo y se le pagan las horas del auto-cierre. docs/estado.md afirma hoy que «se arregló que las dos ignoren las marcas anuladas» — no es cierto.

**Arreglo:** Añadir `and anulada_at is null` a la tercera consulta de fn_siguiente_tipo_esperado (la del `select tipo, timestamp_marca into v_ultimo`). Es una línea. Y como el defecto de raíz es que la regla vive en dos idiomas, añadir la prueba que docs/estado.md ya pide: comparar fn_siguiente_tipo_esperado contra determinarSiguienteAccion con el mismo juego de marcas, incluidas anuladas.

### 19. Una tardanza perdonada sigue apareciendo como tardanza en Horas, Reporte por sede y el espejo a Google Sheets

`consistencia-deuda` · ⚖️ decisión injusta · arreglo de **horas**

**Dónde:** apps/web/app/(admin)/admin/horas/page.tsx:86 · apps/web/app/(admin)/admin/reporte-sede/page.tsx:133-134 · apps/web/app/api/espejo/route.ts:59

**Qué pasa:** «Levantar una tardanza» (0053) se decidió como perdón TOTAL: no cuenta para el patrón disciplinario ni para el bono. El lado SQL lo respeta en todas partes (fn_tardanzas_resumen y fn_calcular_bono_puntualidad excluyen tardanzas_justificadas). Tres pantallas del panel cuentan por su cuenta desde jornadas.minutos_tarde, que nunca se toca al levantar, y por eso siguen mostrando la tardanza perdonada. Reporte por sede es el caso más grave: en la MISMA pantalla convive su columna «Tardanzas» (cuenta cruda) con la alerta que viene de fn_tardanzas_resumen (cuenta perdonada). Dos números distintos de lo mismo, lado a lado, y son las pantallas donde la encargada decide con quién conversar. El perfil de la persona (personas/[id]/page.tsx:160) y la pantalla de Incidencias sí excluyen: cuatro consumidores, dos respuestas.

**Arreglo:** Que las tres superficies dejen de contar por su cuenta. Lo más barato y consistente: exponer una vista o RPC única —`fn_tardanzas_por_persona(desde, hasta)`— que ya aplique el descuento de tardanzas_justificadas, y que Horas, Reporte por sede y /api/espejo la consuman. Alternativa mínima si urge: cargar tardanzas_justificadas del rango y filtrar en las tres, como ya hace incidencias/page.tsx:216-221 — pero eso deja cuatro copias de la regla en vez de una.

### 20. ~~Un periodo de planilla ya pagado se puede reabrir sin motivo y sin dejar rastro~~

> ✅ **CERRADO** por la migración 0095: fn_periodo_pagado con `p_pagado = false` ahora lanza «Para reabrir un pago usa Revertir pago…». La firma no cambió, para no romper la llamada de la pantalla. Prueba en `96_ni_horas_negativas_ni_reabrir_sin_motivo.test.sql`.

`consistencia-deuda` · 💰 dinero · arreglo de **minutos**

**Dónde:** supabase/migrations/0025_planilla_periodos.sql:176 (fn_periodo_pagado) frente a supabase/migrations/0066_reversas_pago.sql:28 (fn_revertir_pago)

**Qué pasa:** La 0066 se escribió justo para esto: «Reabrir toca DINERO: debe quedar QUIÉN lo reabrió, CUÁNDO y POR QUÉ». Creó fn_revertir_pago, que exige motivo y escribe en reversas_pago. Pero dejó la puerta vieja abierta: fn_periodo_pagado(id, false) sigue concedida a `authenticated`, sigue reabriendo el periodo y no pide motivo ni escribe una sola fila de auditoría. La pantalla usa la puerta buena, pero PostgREST expone la otra a cualquier sesión de admin o líder. Y reabrir no es cosmético: es lo que levanta todos los candados que impiden anular, corregir o agregar marcajes de ese periodo. Se puede reabrir, mover marcas, volver a pagar, y no quedar rastro de la reapertura.

**Arreglo:** Cambiar la firma a fn_periodo_pagado(p_periodo_id uuid) que solo MARQUE pagado, y que la única forma de reabrir sea fn_revertir_pago. Si se prefiere no tocar la firma: que fn_periodo_pagado lance excepción cuando p_pagado es false, con el mensaje «Para reabrir un pago usa Revertir pago: la ley del sistema es que quede el motivo». Actualizar la llamada de planilla/page.tsx:760 (que ya pasa true).

### 21. ~~El semáforo de tardanzas pide 3 a todo el mundo, incluso a quien por escala ya le corresponde 1~~

> ✅ **CERRADO el 2026-08-10** por la
> [`0200`](../supabase/migrations/0200_el_semaforo_sabe_en_que_escalon_esta_cada_quien.sql).
> La escala del RIT art. 7 vive ahora en `fn_tardanza_escalon` y la consumen las
> DOS funciones. Prueba
> [`155`](../supabase/tests/155_el_semaforo_conoce_el_escalon.test.sql), que
> falla contra la versión anterior en sus casos 4-7 y pasa los 1-3 —el caso sin
> antecedente no se movió, y eso también se mide—.

`disciplina-legal` · ⚖️ decisión injusta · arreglo de **horas**

**Dónde:** supabase/migrations/0189_una_tardanza_de_tres_horas_deja_de_desaparecer.sql:444 (`fn_tardanzas_resumen`, `where c.n >= 2`) frente a :363-374 (`fn_expediente_generar_tardanza`, la escala) · consumidores: `admin/disciplina/page.tsx`, `admin/dashboard/page.tsx:334`, `admin/reporte-sede/page.tsx:153`

**Qué pasa:** las dos mitades del motor de tardanzas respondían preguntas distintas creyendo responder la misma. El semáforo listaba a quien llevaba 2+ en el mes y rotulaba «amonestación» a las 3, sin mirar antecedentes. El generador escalaba: 3 sin antecedente, 2 tras una amonestación, **1 tras una suspensión**, y se niega con una imputación vigente. Para quien arrastra una suspensión vigente el umbral real es una sola tardanza, y la pantalla seguía pidiendo tres — así que el expediente ya se podía generar mientras Disciplina decía «Nadie con tardanzas relevantes este mes». Es el falso NEGATIVO simétrico del que persigue este repositorio: el sistema no acusa de más, deja de avisar, y justamente sobre la gente por la que hay que actuar antes. Los otros dos consumidores agravaban lo mismo por su cuenta: comparaban `umbral === "amonestacion"` para pintar el rojo, así que a quien le tocaba una suspensión o una imputación lo anunciaban con el nombre del escalón equivocado o no lo anunciaban.

**Arreglo (aplicado):** extraer la escala a `fn_tardanza_escalon(persona)` —qué documento toca, cuántas tardanzas exige, desde qué fecha se cuenta y si está bloqueado— y que las dos funciones la consuman. Copiarla a la segunda habría creado la segunda copia de una regla, que es literalmente la causa de este hallazgo. `umbral` pasa a nombrar el escalón alcanzado y los tres consumidores comparan contra `'aviso'`.

### 22. ~~El semáforo excluye a quien tiene sueldo fijo y el generador no~~

> ❌ **REFUTADO el 2026-08-10, y el hallazgo era mío — escrito ese mismo día.**
>
> Miré `fn_expediente_generar_tardanza`, vi que no nombra `sueldo_fijo`, y
> concluí que podía imputar a quien el semáforo esconde. **No bajé un nivel
> más.** El generador no crea nada: delega en `fn_expediente_crear_borrador`,
> que abre con
>
> ```sql
> if v_p.estado <> 'activo' or v_p.en_planilla = false or v_p.sueldo_fijo = true then
> ```
>
> y aborta. Las dos mitades coinciden: a quien cobra fijo no se le arma memo por
> ningún camino.
>
> **La lección, y es la del día entero:** «esta función no nombra la columna» no
> prueba que la regla no se aplique. Las reglas de este sistema viven repartidas
> en cadenas de funciones, y medir una sola es medir un eslabón. La pregunta
> correcta no era *¿nombra la columna?* sino *¿qué pasa si lo intento?* — y eso
> se responde intentándolo contra la base, que es lo que costó un minuto hacer
> después.


---

## Menores, sin verificar — 17

No pasaron por el refutador: son de gravedad media o baja y se dejaron para revisar al abordarlos.

- **fn_periodo_pagado(id, false) reabre un pago sin motivo y sin dejar rastro, esquivando fn_revertir_pago** — `planilla-dinero` · media · minutos  
  La 0066 se escribió precisamente para que reabrir un pago exija un motivo y quede registrado en `reversas_pago` (quién, cuándo, por qué, y el pagado_at previo). Pero la función vieja siguió expuesta a `authenticated` con su parámetro booleano intacto: llamarla con `p_pagado=false` devuelve el periodo a 'abierto', borra…
- **Los umbrales de reincidencia por tardanza (RIT art. 7 c y d) se borran cada 1 de mes** — `disciplina-legal` · media · horas  
  El umbral b) del RIT sí es mensual ('tres o más tardanzas en un mismo mes calendario'), pero los umbrales c) y d) son de reincidencia: 2 tardanzas nuevas tras la amonestación, 1 tras la suspensión. El código aplica la ventana mensual a los tres. Consecuencia: las tardanzas cometidas después de una amonestación pero ant…
- **El terminal de tienda descarga DNI, correo y hash de PIN de toda la sede, y los guarda en el disco de la Mac mini** — `seguridad-permisos` · media · horas  
  La política da al terminal SELECT sobre las filas de personas de su sede — pero sobre todas las columnas, y personas incluye documento (el DNI), email, fecha_ingreso y pin_hash. El terminal solo necesita nombre y sede para dibujar la grilla. Peor: roster.ts pide pin_hash explícitamente y guardarRoster() lo persiste en …
- **El monto estimado de vacaciones se cae a S/0 el día del aniversario y da un salto del 16 % al día siguiente** — `vacaciones-feriados` · media · horas  
  El factor de ritmo de trabajo divide las horas marcadas entre `base_horas = 45 × (días desde el último aniversario − días de vacaciones) / 7`. El día exacto del aniversario esa resta vale 0, `base_horas` es 0, el `case` cae en el `else 0` y el factor pasa a 0 — con él, el monto estimado de TODO el saldo acumulado. Los …
- **«Quitar» unas vacaciones no pide confirmación y convierte esos días en faltas** — `frontend-admin` · media · minutos  
  El botón «Quitar» de cada periodo llama a `quitar(v)` directo, sin `window.confirm`. `fn_quitar_vacaciones` hace `delete from vacaciones where id = p_id` — no hay borrado lógico ni tabla de auditoría, así que no queda rastro de quién lo quitó ni forma de deshacerlo desde la app. Las consecuencias las describe la propia…
- **En Disciplina la fecha etiquetada «Firmado» es en realidad la de creación del borrador** — `frontend-admin` · media · minutos  
  La lista «Firmados — por entregar» imprime `Firmado {selloLima(d.creado_at)}`. `creado_at` es cuándo el sistema generó el borrador; la fecha real de la firma vive en `firmado_at`, una columna que el select de la línea 86 ni siquiera pide y que la interfaz `Doc` no declara. Entre generar el borrador y firmarlo pueden pa…
- **Una respuesta vacía pero exitosa BORRA la caché offline del roster y deja la sede sin poder marcar** — `terminal-offline` · media · minutos  
  cargarRoster solo cae a la caché cuando hay error. Si la consulta responde bien pero con cero filas, entra al camino feliz y llama guardarRoster([]), que empieza con tx.store.clear(): se borra el roster guardado. Y eso pasa sin ningún error de por medio cuando la política personas_select_terminal_roster deja de aplicar…
- **acta_ref no tiene llave foránea: un descanso OTORGADO puede citar un acta que no existe** — `esquema-integridad` · media · horas  
  feriados_descanso_sustitutorio.acta_ref es texto libre que apunta a actas_descanso_sustitutorio.referencia, que sí es UNIQUE — pero no hay FK entre las dos. La única defensa es chk_dcs_acta, que solo exige que el texto tenga 3 caracteres o más cuando el estado es OTORGADO. Y el estado OTORGADO no es cosmético: quita la…
- **fn_periodo_pagado(id, false) reabre un periodo pagado sin motivo y sin dejar rastro en reversas_pago** — `esquema-integridad` · media · minutos  
  La 0066 creó fn_revertir_pago con todo lo que corresponde: exige motivo de 4 caracteres, verifica que el periodo esté pagado y escribe una fila en reversas_pago con quién, cuándo y el pagado_at previo. Pero fn_periodo_pagado siguió existiendo con su segundo parámetro booleano intacto, y con p_pagado=false hace exactame…
- **fn_provisiones perdió en la 0048 el arreglo de zona horaria que la 0035 le había puesto** — `esquema-integridad` · media · minutos  
  La 0035 existe únicamente para arreglar este `current_date` desnudo en fn_provisiones; su encabezado explica el daño con nombre y apellido: 'después de las 7pm hora Lima el servidor ya cree que es el día siguiente — el próximo desembolso podía mostrar la fecha equivocada la noche misma del día de pago (15-jul, 15-dic) …
- **Siete aserciones throws_ok(sql, null, null, ...) pasan con CUALQUIER excepción — incluida la que blinda el arreglo que promete la 0089** — `pruebas-y-ci` · media · horas  
  throws_ok(sql, null, null, desc) en pgTAP solo comprueba que algo lanzó excepción, sin mirar cuál. Cinco de las siete son candados de dinero (periodo pagado, mover una marca de día) y una es el permiso de anular. El caso peor es 89:92: la 0089 promete en su cabecera 'Que la autorización se compruebe ANTES que el estado…
- **fn_eliminar_marcaje sigue BORRANDO marcas de verdad, contra el principio append-only de la 0081** — `consistencia-deuda` · media · minutos  
  La 0081 decidió el 26/07 que una marca se anula y no se borra, y su propio encabezado dice que fn_eliminar_marcaje «se mantiene por compatibilidad pero la pantalla deja de usarla». Nadie la llama desde el panel, pero sigue concedida a `authenticated` y por tanto expuesta como RPC. Además arrastra todo lo que se arregló…
- **El registro de migraciones —el mecanismo creado para saber qué hay en producción— dice tres cosas falsas, y el script que lo repara le dice a Felipe que no hace falta** — `consistencia-deuda` · media · horas  
  La 0077 existe para que «un SELECT diga la verdad de prod». Hoy no la dice: (a) las 74 y 75 no están registradas —el bloque semilla salta de la 73 a la 76 y ninguna de las dos se auto-registra, porque son anteriores a la 0077—; (b) el número 85 está ocupado por 'grati_en_periodos_que_cruzan_el_ano', que en el repo es l…
- **La lista de documentos firmados muestra la fecha de creación rotulada como 'Firmado'** — `disciplina-legal` · baja · minutos  
  En el bloque 'Firmados — por entregar' se imprime creado_at con la etiqueta 'Firmado'. La consulta ni siquiera pide firmado_at. Entre que se genera el borrador y se firma pueden pasar días: de la fecha de firma cuelgan los 12 meses de vigencia del antecedente (RIT art. 14.4) y el orden de la cadena, y es el dato que la…
- **fn_set_vacaciones y fn_quitar_vacaciones usan el guard prohibido 'if not', no 'if ... is not true'** — `vacaciones-feriados` · baja · minutos  
  Las dos únicas funciones de escritura de vacaciones son las últimas que quedan con la forma que el proyecto prohíbe explícitamente: `if not fn_es_admin_o_lider() then raise`. Hoy no es explotable porque desde la 0078 fn_es_admin_o_lider devuelve `coalesce(..., false)` y nunca es null, así que el hallazgo es latente, no…
- **Cuentas muestra una tabla vacía cuando la llamada al servidor falla** — `frontend-admin` · baja · minutos  
  `listar()` no mira `res.ok` ni `data.error`: hace `setCuentas(data.cuentas ?? [])` y `setPromovibles(data.promovibles ?? [])`. Si la ruta responde 401 (sesión vencida), 403 (la fila en `personas` de quien llama ya no es admin) o 500 («servidor sin configurar», que es lo que devuelve si falta `SUPABASE_SERVICE_ROLE_KEY`…
- **El selector de sede se queda pegado: quien viene detrás no encuentra su nombre y no marca** — `terminal-offline` · baja · minutos  
  Quien tiene visible_todas_sedes=true (el caso del founder, base TRU que marca en LIM y AQP, según la 0008) aparece en el roster de todos los terminales pero agrupado bajo SU sede base, no bajo la del terminal. Para encontrarlo hay que tocar la pestaña de la otra sede. volverALista limpia pantalla, persona, PIN, salidaC…

---

## Refutados — 9

Parecían defectos y no lo son. Anotados para no volver a investigarlos.

- **La base imponible de quien tiene `sueldo_fijo` sale del DEFAULT 1130 de
  `personas.sueldo_base_legal`, así que se le retiene sobre un número que no
  tiene relación con lo que cobra (S/221.60 de horquilla mensual)** — **FALSO
  PARA CAYLA, medido en producción el 2026-08-14.** El mecanismo existe en el
  código y la auditoría lo reprodujo, pero lo montó con una persona **en
  planilla** con sueldo fijo, y ese caso aquí no existe.

  Las dos únicas personas con `sueldo_fijo` son **Catherine Pereyra y Dante
  Ramal**, y las dos son `rxh` con `en_planilla = false`. Medido sobre el
  periodo 29/07–28/08:

  | | tipo | sueldo_base_legal | base_essalud | essalud | pensión |
  |---|---|---|---|---|---|
  | Catherine | rxh | 1800.00 | 1130.00 | **0.00** | **0.00** |
  | Dante | rxh | 652.17 | 1130.00 | **0.00** | **0.00** |

  Tres cosas que el hallazgo daba por ciertas y no lo son: **(1)** sus
  `sueldo_base_legal` NO están en el default —son 1800 y 652.17, cargados a
  mano—; **(2)** no se les retiene nada, porque la **0242** les quitó la base
  imponible al ser locadores, que es exactamente lo que esa migración vino a
  hacer; **(3)** el `base_essalud = 1130` que queda en el JSON **no lo lee
  nadie**: la fila de EsSalud de la boleta está dentro de
  `{aporteEssalud > 0 && (…)}` (`planilla/boleta/page.tsx:858`), así que con
  aporte cero no se pinta, y no sale ni en el espejo ni en ninguna exportación.

  ⚠️ **La lección de método vale más que el hallazgo.** Se levantó desde una
  medición de laboratorio sin comprobar A QUIÉN le aplicaba en producción, y la
  primera consulta de verificación lo dio por vivo porque su veredicto metía un
  campo informativo (`base_essalud`) en la misma condición que el dinero
  (`essalud`, `pension`). **Un hallazgo de laboratorio no es un hallazgo hasta
  que se sabe qué persona real cae en él.**

- **Un UPDATE directo a personas.con_hijos o a configuracion.asignacion_familiar reescribe el total de periodos ya pagados** — La mecánica se reproduce, pero el hallazgo es falso en su diagnóstico y su vector principal ya es una decisión documentada. (1) DECISIÓN YA TOMADA. La migración 0037_candado_periodo_pagado.sql, líneas 24-28, registra la decisión de Felipe del 2026-07-16: «"Con hijos" (asignación familiar): a propósito SIN candado — es una bandera sin fecha; bloquearla mientras exista cualquier periodo pagado la co…
- **La gratificación y la CTS de quien cesa desaparecen del cálculo en vez de salir en cero** — El síntoma se reproduce, pero el hallazgo se equivoca en las tres cosas que lo harían accionable: el sitio, el arreglo y el número. 1) EL ARREGLO QUE PROPONE ES INERTE. Apliqué literalmente lo que pide el hallazgo —quitar `where p.estado = 'activo'` de fn_provisiones (0048:144)— sobre una copia del estado real del repo. fn_grati_cts_periodo vuelve a traer a la persona, y la pantalla de planilla si…
- **Las migraciones 0074 y 0075 no están aplicadas: el memo imprime 'Gerencia General' aunque lo firme una encargada** — El hallazgo confunde el estado de la base LOCAL de auditoría con el de producción. Es cierto que en `cayla_85` faltan los objetos de la 0074/0075 — eso lo reproduje — pero la causa es una limitación del entorno local, no un hueco en producción, y el repo documenta en cuatro lugares independientes que ambas migraciones sí corrieron en prod. 1) POR QUÉ FALTAN EN LOCAL. La 0074 no puede aplicarse en …
- **Se puede firmar y entregar una carta de despido con el legajo vacío: la cadena no está restringida en ningún lado** — La secuencia SQL del hallazgo se reproduce tal cual, pero lo que demuestra no es un defecto del sistema: es que un admin puede llamar a mano una función interna que ninguna pantalla usa. Tres refutaciones concretas: 1) NO HAY RUTA DE PRODUCTO. `fn_expediente_crear_borrador` no se invoca desde ninguna parte del front-end (`grep -rn "crear_borrador" apps/ packages/` → cero resultados). Las únicas do…
- **fn_auto_cierre() está concedida a authenticated sin ningún guard: cualquier sesión cierra la jornada de todo el equipo** — El mecanismo que describe es cierto (el grant existe, la función es SECURITY DEFINER y no tiene guard, y una sesión `authenticated` sin fila en `personas` sí la ejecuta), pero la CONSECUENCIA que le atribuye es falsa, y es la consecuencia lo que convertiría esto en hallazgo. 1) NO "fabrica la salida de quien todavía está trabajando". El WHERE de fn_auto_cierre es puramente temporal: `now() >= (fec…
- **El terminal lee marcas ANULADAS como si estuvieran vivas: ofrece la acción equivocada y la marca real se pierde en silencio** — El hallazgo describe un bug REAL pero YA CORREGIDO: es una lectura de código anterior al commit b7d624b ("El terminal, el espejo y reabrir-dia tampoco cuentan las marcas anuladas"), que está en HEAD. La premisa central — "estado-dia.ts:16-25 (select sin filtro de anulada_at)" — es falsa contra el código actual. Esas líneas exactas SON el filtro: `/Users/ArchiCaylo/Developer/cayla-dynamic/apps/web/…
- **/api/reabrir-dia hace dos escrituras sin transacción: si la segunda no corre, un día cerrado de 10 h queda con horas = NULL** — El MECANISMO es cierto (dos escrituras HTTP separadas vía PostgREST, sin transacción, y el trigger `trg_marcajes_recalcular_jornada` recalcula ya en el UPDATE), y el estado intermedio se reproduce tal cual: horas NULL / en_pausa. Pero las dos afirmaciones que convierten eso en daño son FALSAS, y sin ellas no queda ni un número equivocado ni un flujo bloqueado. (1) "Desde el terminal el día ya no e…
- **/api/reabrir-dia parte la operación en tres transacciones y puede dejar la jornada con horas NULL** — El mecanismo intermedio se reproduce, pero las dos afirmaciones que le dan peso al hallazgo son falsas: (1) el escenario que dispara el estado roto es imposible tal como se describe, y (2) el estado roto no persiste ni llega a planilla — se cura solo por dos caminos independientes. 1) "La Mac mini pierde red justo ahí, que es exactamente el escenario de la cola offline" — FALSO. Los tres pasos (up…

---

## ~~El régimen de pensión no tiene historia~~ — CERRADO con la 0261

> **RESUELTO el 2026-08-15.** Migración **0261**, aplicada y verificada en
> producción: `marcas_0261 = 1`, `lee_el_historial = true`, y las marcas de la
> 0254 y la 0245 intactas en 7 y 6 — la garantía de que reescribir una función
> de 76.000 caracteres no revirtió nada. 23 personas quedaron con historial.
> Prueba **202**, comprobada por los dos lados: sin el arreglo fallan las dos
> centrales.
>
> **Queda un dato, no un defecto:** en qué AFP estaba Judith antes de jubilarse.
> Ver «El hueco que se dejó a propósito», al final.

**Nunca hubo un sol mal pagado por esto, y julio siguió pagado y congelado.** Lo
que había era que **la boleta de julio de Judith y lo que el sistema calculaba
para julio ya no decían lo mismo**.

Salió el 2026-08-15 al revisar por qué Judith figuraba como JUBILADA.

**CORRECCIÓN de cómo se contó primero:** se dijo que «nada avisa de la
diferencia», y era falso. `fn_planilla_foto_diferencias` compara la foto del
pago contra el recálculo y la pantalla del periodo lo pinta en ámbar. Lo que
falla no es el aviso: es su **diagnóstico**. Dice «Alguien corrigió algo de
estas fechas después del pago» —y nadie corrigió nada de julio— y ofrece el
botón **«repagar»**, que en este caso sobrescribiría la foto correcta de julio
con un 0 % que jamás se pagó. La red existía y apuntaba al lado contrario.

### Qué pasa

`fn_planilla_calcular` busca la tasa así (0242, el join `tpen`):

```sql
where t.regimen = pe.regimen_pension       -- ← el régimen de HOY
  and t.vigente_desde <= p_fin             -- ← la tasa, sí, versionada por fecha
```

**La TASA está versionada por fecha. La PERTENENCIA de la persona a un régimen,
no.** `personas.regimen_pension` es un solo valor actual; no hay tabla de
historia (comprobado: el nombre `regimen` solo aparece en `personas` y en
`tasas_pension`).

Así que al calcular un periodo pasado se mezcla el régimen de hoy con la tasa de
entonces. Medido contra la base local:

| se pregunta la tasa de `jubilada` al cierre… | encuentra |
|---|---|
| 2026-07-28 (julio) | ninguna → cae a `configuracion.tasa_afp` = **0** |
| 2026-08-28 (agosto) | 0.00000 |

Julio recalculado le da **0 % de pensión** a Judith. Su boleta de julio real le
cobró su AFP, porque la 0190 rige «desde el periodo que se paga el 28/08/2026».

### Y no es un caso de jubilación

Es la forma general: **cualquier cambio de régimen reescribe el pasado.** Si
alguien pasa de ONP a Integra, todos sus periodos anteriores se recalculan con
Integra. Judith solo lo hizo visible porque `jubilada` no tiene tasa antes del
29/07 y la caída a la tasa global es del 0 %, que salta a la vista.

### Por qué hoy no duele y cuándo dolería

La 0190 fue explícita —«ningún periodo pagado se toca»— y la 0203 congela los
periodos pagados. Pero eso es una decisión escrita, no un mecanismo: el número
distinto aparece en cuanto alguien **mira** la planilla de un periodo viejo, sin
reabrir nada. Dolería de verdad al cuadrar una PLAME pasada o cualquier reporte
anual construido sobre `fn_planilla_calcular`.

### El arreglo, tal como se hizo (0261)

Versionar la pertenencia como ya se versionaba la tasa. Tres piezas:

1. **`asignaciones_regimen_pension`**, con la forma EXACTA de
   `asignaciones_salario`: el mismo `EXCLUDE USING gist` contra solapes, la
   misma unicidad de una sola fila abierta, la misma RLS. Copiar la forma no es
   pereza: quien sabe leer una sabe leer la otra, y el día que haya que tocar
   las dos no habrá dos maneras.
2. **`fn_cambiar_regimen_pension`**, para que nadie vuelva a cambiarlo con un
   `update` a secas — que es lo que borraba la historia. Se niega si la fecha
   cae en un periodo pagado, reutilizando el freno de la 0203.
3. **Una sola expresión distinta en `fn_planilla_calcular`.** Como abajo se lee
   `from pers pe`, los DOS consumidores —el régimen que sale en la boleta y la
   tasa que se aplica— heredan el valor histórico sin tocarlos.

El cuerpo no se copió a mano: se extrajo con `pg_get_functiondef()` y se
verificó que las otras dos lecturas quedaban intactas.

**No movió un céntimo al pegarse.** El relleno escribe el régimen que cada
quien ya tenía —lo que la función venía suponiendo, ahora con fecha— y el
`coalesce` de respaldo deja igual a quien no tenga fila. Auditado: las 1235
pruebas pgTAP pasan, incluidas todas las de planilla que afirman importes
exactos.

### El hueco que se dejó a propósito

A quien figura 'jubilada' NO se le escribió una fila desde su fecha de ingreso:
sería afirmar que llevaba jubilada desde que entró, y eso no lo sabe nadie. Se
le escribió desde el **2026-07-29**, lo único que la 0190 dejó dicho, y el tramo
anterior quedó **vacío**. Una tabla que se llama «historial» no puede mentir
para quedar completa.

Producción lo confirma: `con_hueco_antes_de_su_primera_fila = 1`.

**Lo que falta es un dato, y lo tiene Felipe: en qué AFP estaba Judith antes de
jubilarse.** Con él, su julio recalcula igual que su boleta. Se registra con un
`insert` deliberado y justificado —no por `fn_cambiar_regimen_pension`, que se
niega a fechar nada dentro de un periodo pagado, y hace bien.

#### Y ese dato probablemente no haya que preguntárselo a nadie

Felipe no lo recuerda (2026-08-15), pero la base lo sabe. La aritmética:

- La foto del pago de julio guarda `descuento_pension` — lo que se le retuvo.
- **La base imponible NO depende del régimen**: es básica + asignación familiar
  + feriados + recargo de sobretiempo. Así que recalcular julio hoy la da bien,
  aunque el régimen salga mal.
- `descuento_pension / base` = la tasa exacta que se le aplicó.

Y las tasas son distintas entre sí: Habitat 12.84 · Integra 12.92 · Prima 12.97
· ONP 13.00 · Profuturo 13.06. Un cociente de tres decimales las separa.

Antes de usarlo hay que comprobar que la división cae limpia sobre una de las
cinco y no entre dos: con montos de S/80 a S/150 la diferencia entre AFP vecinas
es de céntimos, y el redondeo de la boleta podría no distinguirlas. Si queda
ambiguo, se pregunta y punto — pero conviene medirlo antes de dar por perdido
un dato que la base todavía tiene.

---

## El séptimo día que además es feriado cobra DOS sobretasas — decidido, no es un defecto

**Decisión de Felipe, 2026-08-25: se pagan las dos.** Queda escrito aquí para que
la próxima sesión que lo encuentre no lo trate como un error y lo «arregle».

### El caso, medido contra producción

La 0280 paga el 100 % del art. 3 del D. Leg. 713 a quien trabaja su séptimo día
seguido. Cuando ese día es **además feriado**, se suma el 100 % del art. 9. El
día queda pagado tres veces: sus horas, que ya están en `pago_base` porque las
marcó, más las dos sobretasas.

En el periodo 29/07–28/08, dos de tres casos se solapan — los tres en Trujillo:

| | séptimo día | feriado | de más |
|---|---|---|---|
| Melany Enrriquez | 06/08 | Batalla de Junín | S/ 66.63 |
| Nicole Blas | 29/07 | Fiestas Patrias | ~S/ 29.02 |
| Janis Revilla | 19/08 | — | no se solapa |

El 06/08 de Melany, pieza por pieza: **11.33 h** marcadas, sueldo S/1 185, base
6.5 × 31 = 201.5, hora a S/5.8809. Cada pieza vale 11.33 × 5.8809 = **S/66.63**,
y el día completo **S/199.89**. Con una sola sobretasa serían S/133.26.

Conviene no leer mal ese número: es alto porque **el día fue de 11 h 20**, no
porque la regla sea generosa. Su día normal ronda las 8.7 h.

### Por qué se pagan las dos

Perdió **dos cosas distintas** ese día: el feriado, que la ley da libre a todo el
mundo, y su descanso semanal, que llevaba siete días sin tomar. Que las dos
pérdidas caigan en la misma fecha no las convierte en una.

Y el riesgo es asimétrico: pagar de más no expone a nada en una inspección;
pagar de menos, sí.

### Lo que queda medido y en contra, para que la decisión sea informada

Son **~S/95 al mes solo en TRU**, y se repite cada mes que alguien encadene siete
días — la propia 0280 midió seis rachas en un periodo, no es un caso raro.

### Y una capa más que aún no se ha medido

Melany tiene además **S/21.38 de sobretiempo** en el periodo. Con 11.33 h en el
séptimo día seguido, es probable que parte de ese recargo sea **de este mismo
día**: entonces el 06/08 no llevaría dos sobretasas sino **tres** —feriado,
descanso semanal y exceso de 48 h semanales—. Cada una tiene su artículo, pero
nadie ha decidido que se acumulen las tres. **Pendiente de medir.**
