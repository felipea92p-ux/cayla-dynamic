# Lo que Dynamic tiene que seguir — Reglamento Interno de Trabajo v4.0

Trabajo de código pendiente para que el sistema haga lo que el Reglamento firmado
promete. Tres niveles, y el nivel es lo que ordena la lectura:

- **INVALIDA UN DOCUMENTO** — si no se hace, una sanción o un memo se cae. Con la
  inspección de SUNAFIL abierta en Arequipa y un expediente de hostigamiento en
  trámite, esta sección va primero.
- **TOCA EL PAGO** — cambia lo que alguien cobra. **Ninguna de estas se toca sin
  auditarla antes contra el Postgres local, dentro de `BEGIN … ROLLBACK` y con
  casos reales.** Es plata de personas reales.
- **MEJORA** — el sistema cumple, pero mal o a medias.

Dentro de cada sección manda la consecuencia, no el número de artículo.

Las referencias a funciones dicen la migración **vigente** de cada una, no la que
la creó. Antes de copiar el cuerpo de cualquiera: `./scripts/donde-vive.sh <fn>`.

---

## INVALIDA UN DOCUMENTO

### 1. Los doce meses del antecedente corren desde la ENTREGA, no desde la firma

> ✅ **Hecho — migración 0213.** `fn_tardanza_escalon` y
> `fn_expediente_generar_falta` exigen ya `estado = 'entregado'` y miden desde
> `entregado_at`. Tres pruebas existentes daban por bueno lo contrario; una de
> ellas lo decía en un comentario: «Todos FIRMADOS (no entregados): a la escala
> le da igual». Se corrigieron.
>
> Queda pendiente **solo la parte de pantalla**: Disciplina sigue imprimiendo
> `selloLima(d.firmado_at ?? d.creado_at)` bajo la etiqueta «Firmado», así que
> cuando no hay firma muestra la fecha de creación con el rótulo equivocado.
> Faltan las tres fechas por separado: emisión, firma, entrega.

**Artículos 56.1, 56.2, 56.3, 19.1 c) y 61.4.**

**Hoy:** `fn_tardanza_escalon` (vigente en la **0206**, md5
`4fa1ce620779c44402090cc87779abe4`) elige el antecedente con
`estado in ('firmado','entregado')` y mide su vigencia con
`firmado_at >= now() - interval '12 months'`. La pantalla de Disciplina imprime
`selloLima(d.firmado_at ?? d.creado_at)` bajo la etiqueta «Firmado»
(`apps/web/app/(admin)/admin/disciplina/page.tsx:926`): cuando no hay firma,
muestra la fecha de creación con el rótulo equivocado.

**Debe:** exigir `estado = 'entregado'` y contar desde `entregado_at`, que ya
existe en el esquema (**0056**, y lo escribe `fn_expediente_entregar` de la
**0058**). Un documento firmado y no entregado no agrava. Los antecedentes sin
cargo firmado ni acta de negativa quedan marcados como **no agravantes** y no se
cuentan en ninguna escalera. La pantalla muestra las tres fechas por separado:
emisión, firma, entrega.

**Por qué va primera:** mientras no se haga, el semáforo propone todos los días
suspensiones que el Reglamento no autoriza, y el propio RIT entregado con acuse
es la mejor prueba contra cada una de ellas.

**Código:** `fn_tardanza_escalon` (0206) · `fn_expediente_generar_tardanza`
(0200, md5 `9b82122a03b9284ef3dda3e5b5278bb8`, que consume el escalón) ·
`apps/web/app/(admin)/admin/disciplina/page.tsx`.

---

### 2. Un marcaje posterior al vencimiento del contrato es desnaturalización, y el sistema es el único que puede verlo el mismo día

**Artículos 8.3, 8.6, 8.8 a) y 8.9.**

**Hoy:** `personas.fecha_fin_contrato` existe desde la **0144** (con
`fn_set_fin_contrato`) y dos pantallas la leen para imprimirla
(`/admin/equipo`, `/admin/documentacion`). Nadie la cruza con el marcaje ni avisa
de su vencimiento. Con ~20 contratos venciendo el 31-12-2026 y la inspección
abierta, esto es lo que un inspector encuentra sin esfuerzo.

**Debe:**
- alerta anticipada de vencimiento (mismo motor de avisos por fecha que ya se
  usa para los 20 días de descanso médico de la **0197**);
- **alerta el mismo día** cuando alguien marca después de su
  `fecha_fin_contrato` sin renovación registrada — los marcajes son append-only
  y la fecha está: es un `join`;
- registro de la presentación ante la AAT dentro de los quince (15) días
  naturales;
- bloqueo de la renovación que cruce el tope conjunto de **cinco (5) años**
  del 8.4, sumando todas las modalidades sucesivas y no contrato por contrato;
- impedir recontratar bajo modalidad a quien cesó como personal permanente antes
  de un año desde su cese (el dato está: fecha de cese + tipo de vínculo).

**Código:** `personas.fecha_fin_contrato` / `fn_set_fin_contrato` (0144) ·
`marcajes` · `personas.fecha_cese` (0086) · `tipo_vinculo` (0085).

---

### 3. Ninguna sanción a quien no tiene acuse del RIT vigente a la fecha de los hechos

**Artículos 60.3, 60.5 y 61.4.**

**Hoy:** la **0208** ya dejó la infraestructura completa —
`documentos_institucionales` (texto congelado, versionado),
`documentos_acuses` (persona, versión, vía `sistema`/`papel`, fecha de acuse y
escaneo del cargo), `fn_publicar_documento`, `fn_acusar_documento`,
`fn_registrar_acuse_papel`, `fn_documentos_vigentes`, `fn_acuses_documento` y la
pantalla `/admin/normas`. Lo que **no** existe es el uso de ese dato: Dynamic
emite amonestaciones y suspensiones sin mirar si esa persona acusó el RIT.

**Debe:**
- **guard** en `fn_expediente_comunicar_cargos` y en `fn_expediente_firmar`: sin
  acuse de la versión vigente a la fecha de los hechos, no se emite. Bloqueo, o
  como mínimo advertencia dura que quede registrada;
- **el reloj del 60.3**: cinco días hábiles sin respuesta → reenvío único; otros
  cinco → entrega física con cargo dentro de los cinco siguientes. Cada día de
  retraso es un día de inaplicabilidad del régimen sancionador para esa persona.
  `fn_sumar_dias_habiles` ya existe (**0212**);
- **el 60.4 necesita dónde publicar**: texto vigente del RIT, identidad y
  contacto de la Responsable de hostigamiento sexual y contacto de DO,
  actualizables sin reeditar el reglamento. `documentos_tipos` admite un tipo
  nuevo sin migración — está hecho para esto.

**Código:** tablas y funciones de la 0208 · `fn_expediente_firmar` /
`fn_expediente_comunicar_cargos` (0212) · `/admin/normas`.

---

### 4. La carta de despido está reservada a la Gerencia General

**Artículo 54.4.**

**Hoy:** `fn_expediente_puede_actuar` (**0076**) devuelve verdadero para
**cualquier nivel, despido incluido**, a quien tenga rol `admin` o `lider_do`
(vía `fn_es_admin_o_lider`, 0078). La otra mitad del artículo sí está: la
encargada de sede queda limitada a `verbal`/`amonestacion` y a su propia sede.

**Debe:** tres niveles de competencia distintos, no dos. `despido` —y la
imputación de cargos que lo precede— solo para Gerencia General. Hoy `lider_do`
puede firmar un despido.

**Código:** `fn_expediente_puede_actuar` (0076) · `permisos.ts` en
`packages/shared` (la comparación de rol **nunca** fuera de ahí).

---

### 5. La escalera de tardanzas tiene cuatro escalones y el sistema tiene tres

**Artículos 19.2, 53.3 e) y 57.10.**

**Hoy:** `fn_tardanza_escalon` (0206) resuelve
amonestación → suspensión → imputación.

**Debe:** amonestación (3 tardanzas en el periodo mensual) → **primera**
suspensión de 1 a 3 días (2 o más tardanzas con amonestación vigente) →
**segunda** suspensión de 2 a 6 días **y de mayor duración que la primera** (1 o
más tardanzas con suspensión vigente) → imputación de cargos.

Y el supuesto nuevo del **19.2 e) ii**: cinco (5) o más tardanzas en treinta (30)
días **corridos** contando con suspensión previa vigente por la misma causa.
Gerencia decidió mantenerlo. Es la **única ventana móvil** del artículo — se
cuenta hacia atrás desde la última tardanza computada y convive con la ventana
mensual de los demás escalones.

Mientras falten, el 53.3 e) exige «amonestaciones escritas y suspensiones» en
plural (art. 25 h de la LPCL) y el sistema solo puede acreditar una suspensión:
el expediente de despido por tardanzas no se sostiene.

**Código:** `fn_tardanza_escalon` (0206) · `fn_expediente_generar_tardanza`
(0200) — el default de `suspension_dias` sale de ahí.

---

### 6. El corte mensual y el corte por antecedente se combinan; no se sustituyen

**Artículos 19.2 c), 19.2 d) y 19.4.**

**Hoy:** `fn_expediente_generar_tardanza` (0200) filtra con
`j.fecha >= greatest(date_trunc('month', fn_hoy_lima())::date, v_cutoff + 1)`.
Dos consecuencias: (a) el `greatest` hace que el corte por antecedente sustituya
al mensual en vez de sumarse; (b) **el día 1 de cada mes las tardanzas del mes
anterior desaparecen** para el generador, y el 19.4 promete expresamente que el
cierre del mes no impide emitir el documento por hechos de un mes concluido.

**Debe:** contar, **dentro del periodo mensual calendario que corresponda**
—que puede ser uno ya cerrado—, solo las tardanzas nuevas posteriores a la
última fecha cubierta por el documento anterior. Dos o más para c), una o más
para d). El generador necesita recibir el mes sobre el que emite.

**Código:** `fn_expediente_generar_tardanza` (0200) · `fn_tardanzas_resumen`
(0200, mismo `date_trunc`).

---

### 7. La negativa a firmar, con dos testigos, surte los mismos efectos que la firma

**Artículo 38 l).**

**Hoy:** `expediente_disciplinario` (0056) admite `entregado` con
`medio_entrega` y `entregado_at`, pero el reloj del antecedente se mide desde
`firmado_at` y el flujo asume que hubo firma.

**Debe:** un medio de entrega «entregado con negativa a firmar», con los **dos
testigos registrados en el propio documento**, que arranque el mismo reloj de
doce meses que la entrega con firma. Sin esto, la primera amonestación que
alguien rechace firmar desaparece del antecedente y la escalera del art. 19 se
cae en su primer escalón.

**Código:** `expediente_disciplinario.medio_entrega` (0056) ·
`fn_expediente_entregar` (0058) · se resuelve junto con la entrada 1.

---

### 8. Un turno cargado o modificado después del inicio del día no funda una tardanza

**Artículo 10.5.**

**Hoy:** la tabla `turnos` (**0013**/**0014**) no tiene `created_at` ni
`updated_at` ni auditoría de cambios. No hay forma de saber cuándo se cargó una
celda de la grilla, así que la regla no se puede aplicar desde el sistema y toda
tardanza cuyo turno se discuta depende de una constancia en papel de la
encargada.

**Debe:** sellos de tiempo y rastro de cambios en `turnos`, y que el cómputo de
tardanzas descarte el turno cuya carga o modificación sea posterior al inicio del
día que regula. Es exactamente el falso positivo que este proyecto define como su
peor error.

**Código:** `turnos` (0013, 0014) · `fn_recalcular_jornada` (vigente en la
**0191**) · `correcciones_auditoria` como modelo de rastro.

---

### 9. Días que no deben computar ni generar documento

**Artículos 17.5, 19.5 y 16.3.**

**Hoy:** la mitad ya está: `fn_tardanza_es_medible` (**0189**) saca del cómputo
del generador y del semáforo los días con diferencia mayor a 180 minutos, y los
muestra aparte como `sin_medir`.

**Falta:** la **tardanza controvertida**. Cuando la colaboradora discute su
autoría o su hora, ese día no computa mientras no se corrobore conforme al 16.3.
No existe marca que lo saque del cómputo — y con el terminal sin PIN, la
controversia de autoría no es hipotética.

**Debe:** una marca por (persona, fecha) de «controvertida / pendiente de
corroboración», con la misma forma que `tardanzas_justificadas` ya tiene en el
generador, y su resolución con motivo.

**Código:** `fn_tardanza_es_medible` (0189) · `tardanzas_justificadas` (leída en
`fn_expediente_generar_tardanza`, 0200).

---

### 10. Una medida de protección no es una sanción y no cuenta como antecedente

**Artículos 51.3 y 50.8.**

**Hoy:** si la suspensión del 50.4 b) se registra como suspensión disciplinaria,
`fn_tardanza_escalon` la lee como antecedente vigente y **agrava la siguiente
sanción de la persona a la que se estaba protegiendo**.

**Debe:** tipo de registro distinto, excluido del cómputo de reincidencia de los
doce meses y de toda escalera.

**Código:** `expediente_disciplinario.nivel` / `tipo_causal` (0056) ·
`fn_tardanza_escalon` (0206).

---

### 11. El expediente de hostigamiento se conserva separado

**Artículo 48.12.**

**Hoy:** todos los documentos disciplinarios viven en un único tablero, con el
control de acceso de `fn_es_admin_o_lider`.

**Debe:** expediente aparte del legajo de personal y del expediente disciplinario
general, con acceso restringido a quienes intervienen, conforme al art. 44.
Hay un expediente en trámite: esto no es preventivo.

**Código:** `expediente_disciplinario` y sus políticas RLS ·
`fn_documentos_tablero` (0161) · `/admin/disciplina`.

---

### 12. Los nueve plazos del procedimiento de hostigamiento son improrrogables y nadie los cuenta

**Artículo 49.4.**

**Hoy:** no hay reloj. Los plazos mezclan días hábiles y calendario, y dos de
ellos —las comunicaciones al MTPE de los literales d) y h)— no dejan rastro
interno, así que nadie los echa de menos hasta que ya vencieron.

**Debe:** el reloj del procedimiento con sus avisos, sobre el expediente
separado de la entrada 11. `fn_sumar_dias_habiles` (0212) ya resuelve la
aritmética.

---

### 13. La reconsideración interna no existe en el sistema

**Artículo 55.5.**

**Hoy:** la anulación de un documento existe; la vía que la origina, no.

**Debe:** registrar la solicitud, el plazo de diez (10) días hábiles, la
resolución, y la anulación **con pérdida del efecto agravante desde ese
momento** — que es distinto de borrar el documento.

**Código:** funciones de expediente de la 0206/0212.

---

### 14. Falta la fecha en que la Empresa tomó conocimiento del hecho

**Artículo 52.6.**

**Hoy:** no hay campo. El expediente solo sabe cuándo se creó el documento.

**Debe:** una fecha de conocimiento, obligatoria al abrir el expediente. Es la
que sostiene la inmediatez y la única defensa frente a una alegación de
condonación tácita.

**Código:** `expediente_disciplinario` (0056) · `fn_expediente_crear_borrador`.

---

### 15. «Archivado» no distingue si hubo sanción menor

**Artículo 57.6.**

**Hoy:** `chk_resuelto_completo` y `fn_expediente_resolver` (**0206**) solo
aceptan `archivado` o `despido`.

**Debe:** distinguir «archivado sin sanción» de «archivado con sanción menor»
(que se documenta aparte). Si no, el legajo no dice lo que se decidió.

**Código:** `fn_expediente_resolver` y `chk_resuelto_completo` (0206).

---

### 16. La amonestación verbal tiene enum y plantilla, y ninguna pantalla que la emita

**Artículo 54.2.**

**Hoy:** `nivel` admite `verbal` desde la 0056 y hay plantilla; no hay pantalla.
El artículo dice que el acta se emite **desde Dynamic** y prohíbe dejar
constancia por otros medios.

**Debe:** la pantalla. Es la sanción más frecuente y hoy es la única que no deja
rastro en el sistema.

**Código:** `expediente_disciplinario.nivel` (0056) ·
`/admin/disciplina/memo/[id]`.

---

### 17. Ningún documento pasa a sanción vigente sin firmante identificado y sin constancia de entrega

**Artículo 46.6.**

**Debe:** verificar que no exista ningún camino —pantalla, RPC o corrección
manual— que marque un documento como impuesto por el solo hecho de haberse
generado. La pantalla `/admin/disciplina/memo/[id]` redacta el documento; no
puede darlo por adoptado.

**Código:** `/admin/disciplina/memo/[id]/page.tsx` · `fn_expediente_firmar` y
`fn_expediente_entregar`.

---

## TOCA EL PAGO

> Antes de tocar cualquiera de estas: auditoría empírica contra el Postgres
> local, `BEGIN … ROLLBACK`, con casos reales. Y leer
> `docs/planilla-anexo-tecnico.md` — tiene cinco defectos que parecen reales y no
> lo son.

### 18. Cuatro clases de tiempo sin marca que hay que pagar como laborado

**Artículos 23.4, 30.8, 31.3 a), 33.5, 33.6, 34.4, 35.2 c), 36.9, 37.2, 50.6 y
50.10.** Es la entrada más cara de la lista.

**Hoy:** el pago se calcula sobre horas marcadas. `fn_planilla_calcular` (vigente
en la **0199**, md5 `3ca25dd82de07418c9b9c77abffc8dec`) acredita **solo
vacaciones** como tiempo laborado, y eso se ganó con la **0177**. Todo lo demás
que no deja marca en el terminal vale S/0.

**Debe:** un concepto de **tiempo reconocido sin marca**, con motivo tipificado,
rastro en `correcciones_auditoria`, y que entre al cálculo del periodo igual que
una hora marcada. Los supuestos, todos con artículo propio:

| Supuesto | Artículo |
|---|---|
| Licencias y permisos con goce | 23.4 c), 31.3 a) |
| Hora diaria de lactancia | 23.4 d), 33.5, 33.6 |
| Incapacidad temporal acreditada | 23.4 e) |
| Interrupción por peligro inminente | 36.9 |
| Atención y traslado por accidente de trabajo | 37.2 |
| Licencia de 30 días naturales de la Supervisora de SST | 34.4 |
| Tiempo de capacitación en SST | 35.2 c) |
| Suspensión imperfecta por medida de protección | 50.6 |
| Facilidades de la persona afectada (salud, denuncia, diligencias) | 50.10 |

Dos piezas que no son obvias:

- **El 36.9 obliga a reconstruir el tiempo cuando no hay constancia.** Si la
  encargada no levanta el acta —porque no estaba, porque discrepa de que hubiera
  peligro, o porque la interrupción cuestiona una decisión suya—, el tiempo se
  computa igual, reconstruido con lo que declare la colaboradora y con el
  registro de asistencia. Hoy no hay forma de meter ese tiempo sin acta.
- **La suspensión por medida de protección (50.6) es imperfecta**: la persona no
  marca y la fórmula devuelve cero, así que en los hechos se vuelve perfecta. Hay
  que computar las horas de su **horario programado**.

Si el motor no las sabe registrar, estas cláusulas quedan incumplidas por diseño
el día que se firme el reglamento, y el castigo económico recae siempre sobre
quien ejerció un derecho. En maternidad y lactancia eso es discriminación
indirecta por sexo; en el 50.10 el propio 51.6 lo califica como represalia
indirecta.

**Código:** `fn_planilla_calcular` (0199) — bloque de `pago_base` y el prorrateo
del feriado, los dos sitios que la 0177 tuvo que tocar a la vez ·
`tipos_ausencia.paga` (0101), que hoy marca «paga» sin que el motor lo lea ·
`ausencias` (0101).

---

### 19. Inasistencia es NO CONCURRIR, no «ausencia de marca»

**Artículos 3.2 ñ) y 20.**

**Hoy:** `fn_faltas` (vigente en la **0079**) declara la falta con
`presente.persona_id is null` — literalmente, «no marcó = ausente». Un olvido de
marcaje, una caída de red o un marcaje offline reconciliado tarde produce una
inasistencia contra quien trabajó el día entero, con descuento del día y de la
parte proporcional del descanso semanal. Con el terminal **sin PIN** y sin marca
de refrigerio obligatoria, es el falso positivo más caro del sistema.

**Debe:** separar dos hechos distintos —«no vino» y «vino y no registró»— y que
solo el primero descuente. El segundo es un día incoherente que se revisa antes
del cierre del periodo (art. 16), no una falta.

Y las exclusiones que faltan, aplicadas **antes** de contar, como ya se hace con
vacaciones, feriados y descanso sustitutorio: hora de lactancia (33.5), ausencia
por hechos de violencia de la Ley 30364 (22.4), interrupción por peligro
inminente (36.9 — «no constituye inasistencia ni retiro sin autorización para
ningún efecto») y atención o traslado por accidente (37.2). El 3.2 n) añade que
la **salida anticipada** tampoco se configura en los dos primeros supuestos.

**Código:** `fn_faltas` y `fn_faltas_resumen` (0079) ·
`fn_expediente_generar_falta` y `fn_falta_contadores` (0060) ·
`fn_recalcular_jornada` (0191) para la salida anticipada.

---

### 20. El refrigerio: o se marca o se descuenta, pero el sistema y el Reglamento tienen que decir lo mismo

**Artículos 11.1, 11.3, 3.2 l) y 14.1.**

**Hoy:** `horarios_asignados` guarda `almuerzo_min_minutos` y
`almuerzo_max_minutos` **por persona** (`fn_set_horario`, **0015**). El
Reglamento dice dos cosas que el sistema no cumple: que la duración se establece
**por sede** y se exhibe por sede (11.1, 11.5), y que el día con refrigerio
incompleto se computa **descontando la duración de refrigerio de su sede**
(11.3).

Si el terminal no captura salida y retorno de refrigerio, entre entrada y salida
queda incluido el refrigerio y el sistema lo paga: el articulado afirma una
exclusión que no ocurre, y además el umbral de la hora 49 se corre todos los días
a favor del sobretiempo.

**Debe:** decidir —capturar las dos marcas o descontar un bloque fijo— y que el
Reglamento y el sistema digan lo mismo. Duración de refrigerio configurada por
sede, y el cálculo usándola. La **0129** cerró el agujero del almuerzo abierto;
el 11.3 ahora fija el criterio exacto.

**Código:** `horarios_asignados` / `fn_set_horario` (0015) ·
`fn_recalcular_jornada` (0191) · `fn_planilla_calcular` (0199) · terminal.

---

### 21. El Día del Trabajo no se prorratea

**Artículo 13.3 a).**

**Hoy:** el sistema prorratea **todos** los feriados por igual al tiempo
trabajado del periodo.

**Debe:** el 1 de mayo se percibe **sin condición alguna y por el íntegro de una
jornada ordinaria**. Es la única corrección del título que mueve plata en contra
de la integrante, y hay que hacerla en el cálculo, no solo en el papel.

**Código:** `fn_planilla_calcular` (0199), bloque del feriado · `feriados`.

---

### 22. Piso de remuneración mínima vital

**Artículo 23.6.**

**Hoy:** el cálculo no compara el importe del periodo contra la RMV vigente ni
genera el abono de la diferencia. La **0105** ya dejó anotado que la básica puede
quedar por debajo de la RMV en un mes con ausencias y que estaba «sin verificar
si la RMV es un piso mensual».

**Debe:**
- detectar a quien **cumplió íntegramente su horario programado** y aun así quedó
  por debajo del mínimo, y abonar la diferencia **en la misma liquidación**, no
  en la siguiente;
- el horario programado de 45 h es horario cumplido para este efecto: las tres
  horas no programadas no reducen el pago;
- distinguir la **jornada a tiempo parcial** (promedio menor a 4 h diarias,
  pactada por escrito) del horario de 45 h. Solo la primera habilita el mínimo
  proporcional. Prorratear el mínimo por 45/48 h sería exactamente lo que el
  artículo prohíbe;
- los conceptos adicionales del art. 28 no computan para alcanzar el mínimo.

**Código:** `fn_planilla_calcular` (0199) · `configuracion` (donde vive la RMV de
referencia, 0025 y 0103).

---

### 23. La remuneración vacacional se paga antes del inicio del descanso

**Artículos 24.5 a) y 30.9.**

**Hoy:** la **0177** acredita los días de vacaciones **dentro** del cálculo del
periodo 29→28, es decir se cobran al cierre, siempre después del descanso. El
art. 16 del D. Leg. 713 exige el pago antes, y su incumplimiento es infracción
grave.

**Debe:** un adelanto por los días programados, con regularización en la
liquidación del periodo. Es un cambio de sistema, no de redacción.

**Código:** `fn_planilla_calcular` (0199) · `ausencias` tipo `vacaciones` (0101)
· `movimientos_planilla`.

---

### 24. La calificación de personal de dirección exige tres actos, y el sistema tiene uno

**Artículos 2.8, 7.6, 15.2, 19.7 y 21.7.**

**Hoy:** solo existe la marca `personal_direccion` (**0187**), que es una casilla
sin respaldo documental. De ella cuelgan la exclusión del sobretiempo y el tope
de un año de periodo de prueba.

**Debe:** el art. 59 del D.S. 001-96-TR exige contrato, **comunicación escrita
individual** y consignación en planilla y boleta. Hace falta guardar —y exigir
antes de permitir la marca— la constancia de esa comunicación **con su fecha**,
porque desde ella corre el plazo de treinta días naturales del art. 61. Sin
fecha, el plazo no empieza a correr nunca; y una exclusión de la jornada máxima
que no conste por escrito y de manera individual **queda sin efecto frente a la
persona, que pasa a tener derecho al sobretiempo**.

El cálculo no debe excluir a nadie sin esa constancia. Y la exclusión se lee
**siempre de la marca por persona**, nunca del rol del sistema: deducirla del rol
le quitaría el derecho a quien recibe admin para otra cosa.

**Código:** `personas.personal_direccion` (0187) · el bloque de sobretiempo de
`fn_planilla_calcular` (0199, lógica de la 0185).

---

### 25. El acuerdo de compensación de sobretiempo con descanso, y su equivalencia

**Artículos 14.7 y 13.2.**

**Hoy:** no consta que el sistema guarde esos acuerdos. El sobretiempo se paga
siempre (0185), que es lo correcto **a falta de acuerdo escrito**.

**Debe:**
- registrar el acuerdo escrito antes del goce, con las horas que compensa y la
  duración del descanso, dentro del mes calendario siguiente;
- aplicar la equivalencia: el descanso equivale a las horas **incrementadas en el
  mismo porcentaje de la sobretasa** (25 % o 35 %), de modo que la compensación
  nunca resulte inferior al pago que sustituye;
- y al publicar el rol, que conste si un feriado programado **se compensa con
  descanso sustitutorio o se paga con la sobretasa** (13.2). El registro del
  descanso sustitutorio ya existe (`feriados_descanso_sustitutorio`); lo que
  falta es la comunicación al publicar y el aviso de que un día libre sobre el
  descanso semanal **no sustituye nada** (13.4).

**Código:** `fn_planilla_calcular` (0199, bloque de sobretiempo) ·
`feriados_descanso_sustitutorio` (0069/0070) · `/admin/turnos`.

---

### 26. Reintegro con intereses legales

**Artículo 23.8.**

**Hoy:** no existe el concepto.

**Debe:** verificada una diferencia en contra de la colaboradora, el sistema
produce el reintegro en la liquidación del periodo siguiente **con los intereses
legales**. Hoy la corrección se hace a mano y sin intereses.

**Código:** `movimientos_planilla` · `fn_planilla_calcular` (0199).

---

### 27. El record vacacional está desdoblado por régimen, y los días son 15 salvo pre-REMYPE

**Artículos 30.1, 30.2 y 30.11.**

**Hoy:** un solo umbral para todas las sedes.

**Debe:**
- **260 días** para el régimen de seis días a la semana (Trujillo) y **210** para
  el de cinco (Taller Lima, Tienda Arequipa); tope de 10 inasistencias
  injustificadas para los regímenes de 3 o 4 días. Un umbral único da falsos
  positivos o falsos negativos según la sede;
- **15 días** de descanso, salvo quien ingresó antes de la acreditación en el
  REMYPE, que conserva **30 días calendario** — y esa persona no puede ser una
  excepción manual cada año.

**Código:** `fn_vacaciones_resumen` · `ausencias` tipo `vacaciones` (0101) ·
`horarios_asignados.dias_laborables` (0015) como fuente del régimen.

---

### 28. El tramo de vacaciones: mínimo siete días, y en días calendario

**Artículos 30.5 y 30.10.**

**Hoy:** se puede registrar un tramo de un día.

**Debe:**
- no permitir tramos inferiores a **siete días calendario** (fraccionamiento
  7 + 8). Un tramo de un día es descanso no gozado y arrastra la indemnización
  del art. 23 del D. Leg. 713;
- el descanso se mide en **días calendario**: el domingo de Trujillo y el feriado
  que caen dentro del tramo forman parte de él y no lo prolongan. El cálculo no
  puede sumarlos aparte.

**Código:** `fn_registrar_ausencia` / vista `vacaciones` (0101) ·
`fn_planilla_calcular` (0199, el bloque de la 0177 que solo cuenta días
laborables — correcto para el **pago**, y hay que no confundirlo con el conteo
de días **gozados**).

---

### 29. Vacaciones truncas por dozavos y treintavos

**Artículos 30.12 y 59.**

**Debe:** dozavos y treintavos sobre **quince** días, desde el mes de servicios,
dentro de la liquidación del art. 59.

**Código:** `fn_liquidacion_*` (0087, 0163) · la **0186** ya excluyó a las
locadoras de este cálculo.

---

### 30. Un día de suspensión no se paga y tampoco se descuenta dos veces

**Artículos 29.5 y 23.5.**

**Hoy:** la **0079** ya resolvió que el día de suspensión no es falta
(`fn_dia_suspendido` dentro de `fn_faltas`). Falta el otro lado.

**Debe:** los días de suspensión disciplinaria no generan pago de horas y **no
admiten además un descuento**. Impedir la doble liquidación del mismo hecho. Y el
23.5 lo generaliza: sobre el tiempo no laborado no se aplica descuento adicional
alguno, ni sobre el descanso semanal ni sobre ningún otro concepto.

**Código:** `fn_dia_suspendido` (0079) · `fn_planilla_calcular` (0199).

---

### 31. Cierre del periodo a la fecha de cese, y el saldo del periodo abierto

**Artículos 59.3, 59.4 y 59.5.**

**Hoy:** el periodo del 29 al 28 se cierra completo. No hay cierre parcial a
fecha de cese, no hay hoja de liquidación, y no existe la figura de dos pagos con
dos fechas distintas para una misma persona cesada.

**Debe:**
- cierre parcial del periodo a la fecha de cese;
- **hoja de liquidación** que muestre horas consideradas, remuneración
  computable, periodos promediados y descuentos. Sin ella, el 59.4 y el 59.5 son
  promesas de papel;
- si al cese el periodo no cerró, ese saldo se paga **con el periodo** y se
  detalla en la hoja, y **el resto de la liquidación no se retiene**.

**Código:** `periodos_planilla` · `fn_planilla_calcular` (0199) · la **0210** ya
enseñó a la planilla a ver la liquidación ya pagada: es el punto de enganche.

---

### 32. Dos licencias que el catálogo no sabe distinguir

**Artículos 31.4 y 32.5.**

**Hoy:** `tipos_ausencia` (**0101**) es un catálogo editable con `paga`,
`requiere_documento`, `requiere_aprobacion` y `descuenta_vacaciones`. Nueve
tipos cargados. Esas cuatro banderas no alcanzan.

**Debe:**
- **31.4 — nueve supuestos que no se pagan ni se computan igual:** con goce puro;
  a cuenta del descanso vacacional pendiente (días 8 a 37 de la Ley 30012);
  compensable con horas de trabajo posteriores; no compensable (fallecimiento,
  Ley 31561); subsidiado por EsSalud desde el día 21; y la licencia de la
  Supervisora de SST computada como efectivamente laborada;
- **32.5 — la licencia sin goce tiene dos efectos opuestos en el mismo
  registro:** cuenta como día de labor efectiva para el **record vacacional**
  (art. 12 g del D. Leg. 713) y **no** cuenta como tiempo laborado para el pago
  del art. 23. Un solo interruptor para las dos cosas garantiza que una de las
  dos salga mal.

**Código:** `tipos_ausencia` (0101) — se resuelve agregando columnas al catálogo,
no `if` en el código · `fn_planilla_calcular` (0199) ·
`fn_vacaciones_resumen`.

---

### 33. La boleta: lo que debe decir y lo que nunca puede decir

**Artículos 25.3 y 23.5.**

**Debe:**
- identificar por separado el **salario de referencia** y el **tiempo computado**
  del periodo;
- mostrar el sobretiempo y las sobretasas de feriado y de descanso semanal
  **solo cuando se hayan devengado**. Una línea en cero permanente contradice el
  artículo tanto como su ausencia cuando sí se devengó;
- **ningún concepto llamado «descuento por tardanza» ni «por inasistencia»**, en
  ninguna plantilla ni exportación. Si alguna lo emite, el documento contradice
  el Reglamento en la primera boleta.

**Código:** `/admin/planilla` y `/admin/exportar` · `fn_planilla_calcular` (0199,
desglose de la 0104 y 0201).

---

## MEJORA

### 34. La pantalla y el generador no miran a la misma gente

**Artículos 19.7 y 21.7.**

**Hoy:** `fn_tardanzas_resumen` (0200) filtra
`pe.en_planilla = true and pe.sueldo_fijo = false`; `fn_faltas` (0079) hace lo
mismo. `fn_expediente_generar_tardanza` (0200) **no aplica ese filtro**:
comprueba el permiso y cuenta jornadas. Resultado: quien tiene sueldo fijo es
invisible en pantalla y sancionable desde la base.

**Debe:** un solo criterio, y que la exclusión del personal de dirección y del no
sujeto a fiscalización inmediata se lea de la marca por persona
(`personal_direccion`, 0187), nunca del rol.

---

### 35. El registro debe exhibir la permanencia fuera de la jornada, y la colaboradora tiene derecho a su copia

**Artículos 16.2, 14.8, 25.4 y 46.4.**

**Hoy:** no hay pantalla ni exportación pensada para esto, y `/admin/perfil` no
muestra marcajes.

**Debe:** el registro tiene que poder exhibir **horas y minutos de permanencia
fuera de la jornada** — es contenido mínimo del art. 2 del D.S. 004-2006-TR, y
tener el registro sin esa información es infracción muy grave igual que no
tenerlo. Y DO o la encargada deben poder emitir ese documento por persona y por
periodo (29→28) sin ayuda técnica, con el control de acceso del art. 46.

**Código:** `/admin/perfil` · `/admin/exportar` · `jornadas`.

---

### 36. La cola de revisión del cierre automático

**Artículo 16.5.**

**Hoy:** el estado existe: un marcaje de `origen = 'auto_cierre'` queda con
`revision = 'pendiente_revision'` (0002, y lo respeta `fn_recalcular_jornada` en
la 0191). Lo que no existe es la **cola**.

**Debe:** que esa cola se agote antes del cierre del periodo de pago, y que la
falta de revisión nunca perjudique a la colaboradora — hoy un cierre automático
sin revisar entra al cálculo tal cual.

---

### 37. La traza del cálculo, no solo el resultado

**Artículos 46.6 y 23.8.**

**Debe:** la colaboradora puede pedir que se le explique cómo se contaron sus
tardanzas y sus horas. Dynamic debería poder mostrar marcajes considerados,
horario aplicado, tolerancia y exclusiones. Hoy solo muestra el número.

---

### 38. El periodo de prueba: aviso y topes

**Artículos 7.1, 7.4 y 7.7.**

**Hoy:** el sistema conoce `fecha_ingreso` y no avisa de nada.

**Debe:** alerta a los tres meses de prestación efectiva; no admitir un periodo
superior a **seis meses** para personal calificado o de confianza ni a **un año**
para personal de dirección, contados **en conjunto** con los tres iniciales —el
v3.0 leía esos topes como topes de la ampliación (9 y 15 meses), y hoy nada lo
impide; y en el reingreso, **sumar los periodos ya laborados** en vez de
reiniciar, salvo puesto notoria y cualitativamente distinto o reingreso a los
tres años del cese. Las personas nunca se borran, así que el reingreso es
detectable.

**Código:** `personas.fecha_ingreso`, `fecha_cese` (0086), `tipo_vinculo` (0085).

---

### 39. Tres relojes de SST que el sistema puede llevar solo

**Artículos 34.2, 34.3, 34.4 y 34.5.**

- **El umbral de veinte trabajadores** se cuenta **por empleador**: suma de las
  cuatro sedes de las personas del art. 2, **sin locadoras**. Al cruzarlo se
  disparan dos obligaciones con plazo —Comité paritario en treinta días y
  elaboración del RISST— y cambia la representación. Hoy ese número se lleva a
  mano y ya figura como pendiente en `docs/estado.md`; el sistema tiene el dato
  (`personas.estado`, `sede_base_id`, `en_planilla`/`tipo_vinculo`).
- **El mandato de la Supervisora** dura mínimo uno y máximo dos años. Un cargo
  que vence sin que nadie lo note deja sin destinatario los numerales 37.1, 37.3
  y 37.4, y obliga a que la Gerencia ejerza las funciones con constancia escrita.
- **La protección reforzada** corre desde la convocatoria a elecciones hasta seis
  meses después de terminada la función. Ese periodo tiene que verse en la ficha
  de la persona igual que un antecedente vigente, para que nadie dispare un
  procedimiento sin verlo.

---

### 40. Contacto de emergencia obligatorio

**Artículo 38 j).**

**Hoy:** los campos existen —`datos_personales.emergencia_nombre`,
`emergencia_vinculo`, `emergencia_telefono` (**0125**)— y, medido contra
producción el 2026-08-07, **ninguna de las 25 personas los tiene cargados**.

**Debe:** marcarlos obligatorios en la ficha y avisar a DO de quien no los tiene.
El artículo fija además cinco días hábiles para comunicar toda variación. Un
deber escrito con acuse y un campo vacío el día del accidente es lo peor de los
dos mundos.

---

### 41. El motivo de una ausencia por violencia no puede quedar escrito ni visible

**Artículos 22.4, 22.5 y 44.7.**

**Hoy:** `ausencias.motivo` (**0101**) es texto libre, y la política
`ausencias_select_supervisor` deja que `supervisor_sede` lea **todas** las
columnas de las ausencias de su sede, motivo incluido.

**Debe:** en esos registros el día figura **solo como ausencia justificada**, y
sus días no computan para ningún umbral de los arts. 19 y 21 ni para las
causales del 21.5. Mientras la columna siga como está, la regla se cumple por
disciplina de captura; la garantía técnica es restringir la columna o separarla
en una tabla con RLS propia, visible solo para admin y DO.

---

### 42. Todos los caminos de escritura, no solo el marcaje

**Artículo 44.13.**

**Debe:** el texto promete trazabilidad de correcciones, anulaciones y
modificaciones, con motivo, identidad y fecha. Hay que verificar que **todos** los
caminos la cumplan: anulación de ausencias, edición de horarios, cambios de
sueldo, corrección de jornada, carga y modificación de turnos (ver entrada 8). Un
camino sin motivo obligatorio incumple un artículo entregado con acuse.

**Código:** `correcciones_auditoria` es el modelo que ya funciona.

---

### 43. Quién puede leer qué

**Artículos 41 y 46.3.**

- La líder de equipo y la encargada solo deben ver el marcaje de **su propio
  equipo**: verificar que las políticas RLS de `marcajes` y `jornadas` filtren
  por equipo y no solo por sede.
- La reserva sobre planilla y remuneraciones alcanza **solo a lo que se conoce
  por razón del puesto**: quien no liquida planilla no debería poder ver la
  remuneración de otra persona, porque el artículo ya no puede usarse para
  sancionar a quien la conoce por otra vía.

Nota de diseño: el 45.5 permite contrastar marcajes con videovigilancia **solo**
dentro de un procedimiento ya iniciado y sobre un momento concreto. Integrar
vídeo con el marcaje sería contrario al artículo.

---

### 44. Conservación: cinco años, y luego no

**Artículos 44.12 y 46.2.**

**Hoy:** no hay proceso de supresión ni de anonimización al vencimiento.

**Debe:** al menos un inventario de qué se guarda y desde cuándo, y el plazo de
cinco años para el registro de asistencia. La prohibición de conservación
indefinida es del artículo, no una recomendación.

---

### 45. El registro de las locadoras no es un registro de control de asistencia

**Artículo 2.5.**

**Hoy:** la **0191** ya dejó de medirles tardanza y la **0186** y la **0199** las
sacaron de vacaciones, feriados y provisiones.

**Falta:** que el registro quede **identificado como tal** y que ninguna pantalla
ni reporte lo presente junto al marcaje del personal en planilla. Presentados
juntos son prueba en contra en una demanda de desnaturalización.

---

### 46. Supervisión con acta, y un canal que no se supervisa

**Artículo 40.**

- Toda supervisión de uso de herramientas y sistemas deja acta. Si Dynamic guarda
  registros de acceso consultables por administración, **esa consulta es
  supervisión** y debería quedar auditada con motivo, igual que las correcciones
  de marcaje.
- El canal de quejas por hostigamiento del art. 48 queda **excluido de toda
  supervisión**: las cuentas de correo de acceso exclusivo de DO y de Gerencia
  General no pueden aparecer en ningún tablero, reporte ni exportación.

---

### 47. Dónde se registra un conflicto de intereses

**Artículo 43.**

**Debe:** la comunicación se hace por escrito a DO y hoy no hay dónde
registrarla. Si se decide que viva en Dynamic, basta un asiento con fecha, texto
y la decisión escrita de DO. No hace falta formato ni revisión periódica: el
Reglamento a propósito no los promete.

---

### 48. La política salarial: cuándo se vuelve a acusar y qué no puede omitir

**Artículos 5.4, 6.6 g), 23.3 y 26.3.**

**Hoy:** la **0141** pide el acuse **por versión** (`/admin/politica-salarial`), y
`fn_publicar_politica_salarial` acepta cualquier texto no vacío.

**Debe:**
- volver a pedir acuse cada vez que la colaboradora **cambia de categoría**,
  aunque la versión del documento no haya cambiado. Hoy ese caso no dispara nada;
- ninguna versión puede omitir **la forma de calcular el pago del periodo**: la
  publicación tiene que exigirlo, o dejar constancia verificable de que la
  versión publicada lo contiene;
- la excepción de **monto fijo mensual** existe en `personas.sueldo_fijo`, pero
  debe constar en el contrato individual y en la política salarial, y **no se
  deduce del cargo, del área ni del rol**. El sistema no debe inferirla nunca.

---

### 49. Un primer marcaje sin contrato registrado debería ser una alerta

**Artículos 6.3 y 6.4.**

**Debe:** verificar que exista contrato suscrito antes del primer marcaje y que
el alta en planilla electrónica se haya hecho a más tardar ese mismo día. Hoy un
primer marcaje de alguien sin contrato registrado es un dato más.

---

### 50. La asignación o el traslado de sede se comunica por escrito antes de empezar

**Artículos 2.2 y 32-A.**

**Debe:** de la sede dependen el horario, el descanso semanal y el terminal en el
que se marca. Hoy no consta que exista ese acto ni su registro. `sede_fisica_id`
ya distingue dónde trabaja alguien de su sede base (0166): falta el documento.

---

### 51. Nadie programada más de seis días seguidos

**Artículo 12.4.**

**Debe:** la grilla de turnos no comprueba al guardar que nadie quede programada
más de seis días consecutivos sin descanso semanal. Es una validación de
guardado, y en Trujillo —donde se trabaja domingo— es donde va a saltar.

**Código:** `/admin/turnos` · `turnos` (0013, 0014).

---

### 52. La hora de lactancia ajusta el horario programado

**Artículo 33.5.**

**Debe:** cuando la hora se ejerce al inicio o al término de la jornada, el
horario programado de esa persona se ajusta para que **no se genere tardanza ni
salida anticipada**. Verificar que `fn_set_horario` (0015) permita ese ajuste por
persona y por periodo; el pago de esa hora va en la entrada 18.

---

### 53. El plazo de justificación corre desde la reincorporación

**Artículos 38 k) y 20.4.**

**Debe:** si Dynamic controla ese plazo en algún punto, tiene que contarlo desde
la **reincorporación efectiva** —no desde el hecho ni desde la emisión del
documento— y aceptar la ampliación cuando el documento depende de un tercero.

---

### 54. Al cese: los accesos y el reloj del certificado de rentas

**Artículos 58.11 y 59.6 d).**

- Marcar inactiva ya lo hace, y bien: las personas nunca se borran. Lo que **no**
  es automático es **desactivar accesos y credenciales**, y el reglamento lo
  afirma.
- El certificado de rentas y retenciones tiene un plazo **a demanda**: cinco días
  hábiles desde que la persona lo solicita. Es el único documento del cese que no
  corre con el reloj de las 48 horas y necesita su propio contador.

---

### 55. Dos registros que SUNAFIL mide con nombre propio

**Artículos 47.10 y 48.5.**

- **Registro de asistencia a la capacitación de ingreso**, con firma y
  conservación. Es la única obligación preventiva en materia de hostigamiento que
  se verifica documento contra documento.
- **Recuento de trabajadoras por centro de trabajo** al 1 de enero y en cada
  incorporación, con constancia escrita: es lo que decide si corresponde Delegada
  o Comité, y hoy no se mide. El dato está en `personas` por sede.
