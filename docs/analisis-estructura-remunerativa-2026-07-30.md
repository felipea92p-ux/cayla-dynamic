> ℹ️ **Informe fechado, no estado vigente.** Rescatado el 2026-08-05 de la rama
> `rescate-31jul` antes de borrarla. Es el sustento del diseño remunerativo que
> se decidió después — sirve para explicarle el porqué al contador. Los montos y
> el avance de hoy están en [`estado.md`](estado.md).

# Estructura remunerativa de CAYLA — análisis a fondo

**30 de julio de 2026.** Escrito para Felipe, para revisar con el contador.

---

## Resumen en cinco líneas

1. **CAYLA está en régimen MYPE pequeña empresa.** Lo confirma tu propio código.
2. **Tu factura de EsSalud ya está en el mínimo legal posible.** No hay nada que ahorrar.
3. **Cambiar «rendimiento extraordinario» por «movilidad» no te ahorra ni un sol.** Es solo defensa.
4. **La exposición real, si te reclasifican, es únicamente el 9% de EsSalud:** ~S/355/mes, ~S/25,500 con multa a 4 años. No hay deuda de CTS ni gratificación porque ya las pagas sobre el rango completo.
5. **La única vía que de verdad reduce lo que pagas es microempresa + SIS**, y solo aplica a contrataciones nuevas.

---

## 1. Dónde estás parado hoy

No lo asumí: lo leí en tu base de datos.

`supabase/migrations/0029_provisiones_acumuladas.sql:15` dice, con tus palabras:

> «Ventanas / fechas de pago (regimen MYPE pequena empresa)»

Y los factores de provisión lo confirman aritméticamente:

| Beneficio | Tu factor | × 12 meses | Equivale a | Régimen |
|---|---|---|---|---|
| Gratificación | 8.333% | 100% | media remuneración × 2 al año | **pequeña empresa** |
| CTS | 4.167% | 50% | 15 días al año | **pequeña empresa** |
| Vacaciones | 4.167% | 50% | 15 días al año | **pequeña empresa** |

En régimen general los factores serían 16.67%, 8.33% y 8.33%. Los tuyos son exactamente la mitad. **Estás en pequeña empresa MYPE**, no en el régimen general. Eso importa para todo lo que sigue.

Consecuencia inmediata: tus obligaciones de CTS y gratificación **ya son la mitad** de lo que serían en régimen general. Y encima las pagas sobre el rango (1,650) y no sobre lo declarado (1,130). Es decir: en CTS y gratificación estás pagando bastante más de lo que la ley te exige.

---

## 2. La conclusión incómoda: tu objetivo ya está cumplido

Me pediste dejar de pagar más al Estado, específicamente el 9% de EsSalud. Aquí está el problema con eso:

**El 9% se paga sobre la remuneración declarada. Tú declaras S/1,130, que es la RMV. Es el piso legal. No existe forma legal de declarar menos.**

S/101.70 por persona al mes es el mínimo absoluto que cualquier empleador formal del Perú puede pagar de EsSalud. Ya estás ahí. Llevas meses optimizando algo que ya estaba en su mínimo.

### Y esto es lo que la migración 0108 no hace

Compara los dos escenarios, con Sandra (rango 1,650):

| | Hoy | Con movilidad 0108 |
|---|---|---|
| Remuneración declarada | 1,130 | 1,130 |
| Movilidad (no remunerativa) | — | 288 |
| Bono no remunerativo | 520 | 232 |
| **EsSalud 9%** | **101.70** | **101.70** |

**Idéntico.** El bono de 520 ya lo declaras como no remunerativo, así que ya no pagas EsSalud sobre él. Renombrar una parte a «movilidad» no mueve un centavo.

La 0108 vale, pero por otra razón: convierte una parte de un bono sin nombre legal en un concepto que **sí** existe en el Art. 19 inciso e) del D.S. 001-97-TR, y cuyo devengo lo prueban tus marcaciones. Es blindaje, no ahorro. Vale la pena tenerlo claro antes de aplicarla.

---

## 3. Cuál es la exposición real (y es menor de lo que parecía)

Aquí hay una buena noticia que no habíamos calculado.

Si SUNAT o SUNAFIL reclasifican el bono como remuneración, lo normal sería que te cobren atrasos de gratificación, CTS, vacaciones **y** EsSalud. Pero:

> **Ya provisionas gratificación, CTS y vacaciones sobre el rango completo (1,650), no sobre lo declarado (1,130).**

Si te reclasifican los 520, la base pasaría a ser 1,130 + 520 = 1,650. **Que es exactamente sobre lo que ya provisionas.** Atrasos de esos tres beneficios: **cero**.

Queda solo el 9%:

| Rango | Valor | Personas | Brecha | 9%/mes | 4 años |
|---|---|---|---|---|---|
| Colibrí | 1,320 | 2 | 190 | 34.20 | 1,642 |
| Cayla | 1,450 | 2 | 320 | 57.60 | 2,765 |
| Support | 1,650 | 2 | 520 | 93.60 | 4,493 |
| Aurora | 1,890 | 1 | 760 | 68.40 | 3,283 |
| Oráculo | 2,250 | 1 | 1,120 | 100.80 | 4,838 |
| **Total 8 personas** | | | | **S/354.60/mes** | **S/17,021** |

Más la multa tributaria del 50% del tributo omitido (Código Tributario Art. 178 num. 1) más intereses: **~S/25,500** en el peor escenario a 4 años de prescripción.

Es dinero, pero no es la ruina. Y es la cifra correcta con la que decidir, en vez de decidir con miedo difuso.

*(Ajusta la tabla con tu composición real de equipo; usé 8 personas con una distribución plausible.)*

---

## 4. El número que más te delata

Ninguno de los conceptos del Art. 19 se evalúa solo por su nombre. Se evalúa también por su **peso** dentro del paquete. El criterio que usan es que sean *«complementarios y residuales»* respecto del sueldo.

Mira qué porcentaje de cada paquete es no remunerativo hoy:

| Rango | No remunerativo | % del paquete |
|---|---|---|
| Colibrí | 190 | 14% |
| Cayla | 320 | 22% |
| Support | 520 | 32% |
| Aurora | 760 | 40% |
| **Oráculo** | **1,120** | **50%** |

Para Oráculo, **la mitad del paquete es no remunerativo.** Ese número, solo, es la señal que hace que un fiscalizador mire con lupa — sin importar qué tan bien redactado esté el convenio de movilidad. Nadie tiene un commute que cuesta la mitad de su sueldo.

Y aquí está el techo estructural del enfoque de conceptos:

> **No se puede hacer que el 40–50% de un paquete sea no remunerativo con conceptos legítimos. Los conceptos del Art. 19 están diseñados para ser marginales.**

- Movilidad (inciso e): tope realista S/288–360. Ya lo estiramos.
- Refrigerio (inciso j): tiene que no ser alimentación principal. Montos chicos.
- Asignación por educación (inciso f): solo para quien estudia, contra comprobantes.
- Gratificación extraordinaria (inciso a): **tiene que ser extraordinaria**. Pagada todos los meses deja de serlo por regularidad (Art. 16) y se vuelve remuneración. No sirve de tapa-hueco mensual.

La brecha no se cierra con conceptos porque **la brecha existe por declarar a todos en el mínimo.** El problema es autoinfligido, y la solución también está en tus manos.

---

## 5. Lo que SUNAT está mirando ahora mismo

Esto es lo más importante que encontré hoy, y es reciente.

SUNAT está enviando **cartas inductivas** sobre clasificación de conceptos remunerativos. Los dos conceptos que están cuestionando, textualmente:

> «inconsistencias en las declaraciones de conceptos como el **bono de productividad** y la **movilidad condicionada a la asistencia**, que algunas empresas presentan como no afectos a aportes.»

Son exactamente los dos conceptos que diseñamos. No es mala suerte: son los dos que todo el mundo usa para esto, y por eso están en la lista.

Lo que piden como sustento: *«políticas de personal claras y estructuradas que incluyan una definición y cálculo de cada concepto remunerativo y no remunerativo»*. Si no entregas la información, sanción bajo el Art. 177 del Código Tributario.

Además, el Tribunal Fiscal (RTF 09197-3-2007) ha establecido que **no reconoce la movilidad como no remunerativa si la empresa no ejerce control sobre ella, incluso cuando el monto es razonable.**

**Aquí sí tienes una ventaja real y poco común:** tu sistema de marcaciones en el terminal es exactamente el control que exigen. El devengo sale de `h.dias`, que cuenta días con horas > 0. No es una declaración tuya: es un registro biométrico por día. La mayoría de empresas que pierden estos casos pierden por no poder probar el devengo diario. Tú puedes probarlo por persona y por día, y es auditable.

Y también: el cruce automático SUNAFIL–SUNAT de 2026 prioriza **empresas medianas y grandes, no MYPEs**. Con menos de 10 personas no estás en la primera fila.

---

## 6. La única vía que de verdad reduce lo que pagas: microempresa + SIS

Esto es lo que llevábamos sin explorar y es la respuesta literal a tu pregunta.

En el régimen **microempresa** de REMYPE, el empleador puede afiliar a los trabajadores al **SIS** en vez de EsSalud:

| | Pequeña empresa (hoy) | Microempresa + SIS |
|---|---|---|
| Salud, costo empleador | 9% = **S/101.70**/mes | **S/15**/mes (el Estado subsidia el otro 50% de S/30) |
| Ahorro por persona | — | **S/86.70/mes = S/1,040/año** |

Y lo más importante: **el SIS es un monto fijo, no un porcentaje.** Con SIS podrías declarar el sueldo completo —los 1,650, los 2,250— y pagar S/15. Toda la ingeniería de conceptos se vuelve innecesaria. Declararías todo, en limpio, y pagarías menos que hoy.

Requisitos de microempresa: **hasta 10 trabajadores** (los cumples) y **ventas anuales hasta 150 UIT** = S/825,000 con la UIT 2026. Esto último hay que verificarlo: son tres tiendas.

### Los tres frenos, sin adornos

**Freno 1 — no aplica a tu equipo actual.** Los trabajadores contratados antes del acogimiento mantienen los derechos del régimen que tenían. El Tribunal de Fiscalización Laboral de SUNAFIL ya lo resolvió: si el contrato dice régimen general o pequeña empresa, esos derechos prevalecen sobre el régimen de microempresa. Y despedir para recontratar tiene una regla explícita: el trabajador debe estar fuera de la planilla **al menos 1 año**. No es una vía; es una trampa. **No la tomes.**

**Freno 2 — el SIS cubre menos que EsSalud.** Esto le pega a tu gente, no a ti. Tú has dicho que la CTS y la gratificación son plata de tu equipo y no las tocas. La cobertura de salud es del mismo tipo. Si algún día contratas bajo microempresa, es una conversación honesta que tener de frente, no una letra chica.

**Freno 3 — microempresa no debe CTS ni gratificación.** Tú las querrías seguir pagando, y puedes hacerlo voluntariamente. Pero deja de ser un derecho de ellos y pasa a ser una decisión tuya. Y si la pagas con regularidad varios años, se vuelve derecho adquirido de todos modos — lo cual está bien, si es lo que quieres.

**Dónde sí sirve:** para las contrataciones nuevas, si CAYLA califica como microempresa. Y encaja con lo que estabas pensando sobre cómo atraer talento: podrías ofrecer un sueldo declarado íntegro y más alto, sin conceptos raros, y pagar S/15 de salud. Es una propuesta más limpia y más atractiva que la actual.

**Verificar con el contador:** (a) ¿está CAYLA inscrita en REMYPE y en qué categoría? (b) ¿ventas anuales vs. 150 UIT? (c) ¿qué régimen dice cada contrato vigente?

---

## 7. La asignación por educación — verificada, y sí sirve

Verifiqué el texto porque en esta conversación ya me equivoqué dos veces citando incisos de memoria.

**Art. 19 inciso f), D.S. 001-97-TR:**

> «la asignación o bonificación por educación, siempre que sea por un monto razonable y se encuentre debidamente sustentada»

**Alcance (Art. 20 y reglamento):** comprende los estudios **del trabajador o de sus hijos** — preescolares, escolares, superiores, técnicos o universitarios — e incluye todos los gastos que requieran los estudios: uniformes, útiles educativos y similares. Confirmado también en la lista de conceptos no afectos a EsSalud de SUNAT.

Es amplio. Cubre desde una carrera universitaria hasta los útiles escolares de un hijo.

### Los dos requisitos, y lo que significan de verdad

**«Monto razonable»** — el criterio es razonable *en relación con los ingresos remunerativos que el trabajador percibe mensualmente*, porque el beneficio debe ser **complementario y residual**. Traducción: una asignación de S/400 sobre un sueldo declarado de S/1,130 (35%) no es residual. Sobre un sueldo de S/1,800 (22%) empieza a serlo.

**«Debidamente sustentada»** — y este es el que define cómo se usa. Sustentar significa comprobante: recibo de pensión, boleta de matrícula, factura del instituto, comprobante de útiles. **Si la persona no estudia, no hay nada que sustentar.** Pagarle «asignación por educación» a quien no estudia es exactamente el tipo de cosa que la primacía de la realidad desarma en una inspección, y contamina los demás conceptos de paso.

### Por eso no es un tapa-hueco, pero sí es una jugada

Dijiste que varias estudian, sobre todo las 6 que más ganan. Eso encaja bien:

- Son las que tienen la brecha más grande (Support 520, Aurora 760, Oráculo 1,120).
- Son las que efectivamente tienen gastos educativos que sustentar.
- Y son las de mayor sueldo declarado, así que el monto es más fácilmente «residual».

Lo que **no** puedes es fijar un monto igual para todas y llamarlo educación. Tiene que ir contra el gasto real de cada una. Lo cual significa: montos distintos por persona, que cambian por ciclo o semestre, y una carpeta con comprobantes.

Y aquí está lo bueno: **eso es lo que ya haces con Domestika.** Compras cursos. La diferencia es formalizarlo — política escrita, solicitud, comprobante, y el monto en boleta como concepto no remunerativo en vez de un gasto suelto de la empresa.

### El giro estratégico, que creo que es lo más valioso de todo esto

Dijiste que lo de los estudios te hace pensar incluso en cambiar tu forma de atraer talento. Estoy de acuerdo, y creo que es el hallazgo más importante de la semana — más que cualquier concepto.

«CAYLA te paga los estudios» es:

- **Legalmente sólido.** Concepto con nombre propio en la ley, no una construcción.
- **No remunerativo de verdad.** No es una interpretación forzada: es su propósito literal.
- **Sustentable por diseño.** El comprobante existe porque el gasto existe.
- **Diferenciador real.** Ningún retail de tu tamaño en Trujillo o Arequipa lo ofrece.
- **Alineado con lo que ya crees.** Ya compras cursos porque quieres gente mejor, no para ahorrar. Eso es justamente lo que lo hace defendible: es verdad.

La diferencia entre esto y la movilidad es que la movilidad la estamos usando para tapar una brecha, y la educación la usarías porque la quieres. Los conceptos que se sostienen en una inspección son los que son ciertos.

---

## 8. Las tres opciones, con precio

### Opción A — Movilidad y nada más (PR #12, ya construido)
- **Costo: S/0.** No ahorra nada.
- Convierte S/288–360 del bono en un concepto con nombre legal y devengo probado por marcación.
- El resto del bono sigue sin sustento: S/1,974/mes en el equipo.
- El ratio no remunerativo sigue en 23–53%.
- **Es mejor que hoy, pero deja el problema principal intacto.**

### Opción B — Bandas reales en PLAME + movilidad (recomendada)
- **Costo: +S/257/mes = S/3,089/año** de EsSalud, en 8 personas.
- El bono sin sustento desaparece: **S/0**.
- El ratio baja a 14–24%: una estructura que se ve normal.
- Se paga con **8.3 años** de la contingencia que evita.

Las bandas que cierran exacto con movilidad a S/15/día (24 días = S/360):

| Rango | Valor | PLAME | Movilidad | AFP que absorbes | Recibe | Diferencia | % no remun. |
|---|---|---|---|---|---|---|---|
| Colibrí | 1,320 | **1,150** | 360 | 149.50 | 1,360.50 | +40.50 | 24% |
| Cayla / Caylo | 1,450 | **1,300** | 360 | 169.00 | 1,491.00 | +41.00 | 22% |
| Support | 1,650 | **1,500** | 360 | 195.00 | 1,665.00 | +15.00 | 19% |
| Aurora | 1,890 | **1,800** | 360 | 234.00 | 1,926.00 | +36.00 | 17% |
| Oráculo | 2,250 | **2,200** | 360 | 286.00 | 2,274.00 | +24.00 | 14% |

**Tu intuición de 1,500 estaba bien:** es exactamente la banda que cierra Support (1,650) con movilidad a 15. Le atinaste.

**Corrección a tu plan, importante:** el AFP de S/146.90 solo es cierto mientras declares 1,130. Al subir la base, el AFP que absorbes sube también — S/195 en 1,500, S/286 en 2,200. La tabla ya lo tiene incorporado. No es un problema, pero cambia la aritmética que tenías en la cabeza.

### Opción C — Microempresa para contrataciones nuevas
- **Ahorra S/1,040/año por cada persona nueva.**
- No aplica al equipo actual. No hay atajo para eso.
- Requiere verificar ventas < 150 UIT.
- Degrada la cobertura de salud del nuevo ingresante.

**A y B no son excluyentes con C.** Lo razonable es B para el equipo actual y evaluar C para el crecimiento.

---

## 9. Lo que sigue sin resolver, y no lo voy a dejar pasar

**El bono que compensa el AFP, declarado como no remunerativo.** Sigue siendo el punto más débil de toda la estructura, y no lo arregla ninguna de las tres opciones. Un pago mensual, regular, de monto predecible, que existe para compensar un descuento de la remuneración, es remuneración por donde se lo mire (Art. 6 D.S. 003-97-TR: «cualquiera sea la forma o denominación»). Si algo se cae en una inspección, es esto primero.

En la Opción B se diluye bastante, porque al subir la base declarada el bono compensatorio se vuelve una fracción mucho menor del paquete. Pero no desaparece.

**Lo que sí lo resolvería** es lo que rechazaste, y entiendo por qué: declarar el bruto e incluir el AFP dentro. Lo dejo anotado sin insistir. Si algún día cambias de opinión, es una línea de código y un convenio.

**Pendiente menor pero real:** el divisor `6.5 × días calendario` hace que una base de 1,130 se declare por debajo de la RMV en meses de 31 días. Eso es una inconsistencia que un cruce automático detecta sin esfuerzo, y es puramente técnica — no es una decisión tuya, es un bug. Vale arreglarlo antes que cualquier otra cosa de esta lista.

---

## 10. Qué hacer esta semana

1. **Preguntar al contador tres cosas:** ¿REMYPE, qué categoría? ¿ventas vs. 150 UIT? ¿qué régimen dice cada contrato? Los porcentajes reales de AFP/ONP que ya te va a pasar completan el cuadro.
2. **Decidir entre A y B.** B cuesta S/3,089/año y quita el problema. A cuesta S/0 y lo reduce a la mitad. Es tu llamada, y ahora tienes el número exacto de las dos.
3. **Mergear PR #12 y #13** — sirven en cualquiera de los dos escenarios.
4. **Arreglar el divisor** — es un bug, no una decisión.
5. **Formalizar lo de educación** para las que estudian: política escrita, solicitud, comprobantes. Es lo único de toda la lista que es puramente ganancia, sin contrapartida.

---

## Fuentes

- [D.S. 001-97-TR — TUO Ley de CTS (texto oficial, MTPE)](https://www.trabajo.gob.pe/archivos/file/SNIL/normas/1997-03-01_001-97-TR_8108.pdf)
- [SUNAT — Conceptos no afectos al aporte a EsSalud](https://orientacion.sunat.gob.pe/10-conceptos-no-afectos-essalud)
- [SUNAT está remitiendo cartas inductivas sobre conceptos remunerativos y no remunerativos — Estudio Ribeiro](https://www.ribeiroymdl.pe/sunat-esta-remitiendo-cartas-inductivas-sobre-conceptos-remunerativos-y-no-remunerativos/)
- [Criterios de la asignación por educación — Gestión](https://gestion.pe/opinion/criterios-debe-entregarse-asignacion-educacion-227622-noticia/)
- [Fiscalización SUNAFIL 2026: el cruce automático de datos — JGA](https://www.jga.pe/fiscalizacion-sunafil-2026-la-era-del-cruce-automatico-de-datos/)
- [SIS Microempresas — S/15/mes empleador vs EsSalud 9%](https://tramitesperu.com/sis/sis-microempresas/)
- [Régimen Remype laboral — LP Derecho](https://lpderecho.pe/regimen-remype-laboral/)
- [Derechos adquiridos prevalecen aun cuando el empleador sea microempresa (TFL SUNAFIL) — Contadores y Empresas](https://www.contadoresyempresas.com.pe/aseguran-prevalencia-de-derechos-laborales-adquiridos-en-mypes/)
- [Régimen laboral MYPE — Juris.pe](https://juris.pe/blog/mype-regimen-laboral-microempresa-pequena-empresa-actualizado/)
- Tribunal Fiscal RTF 09197-3-2007 (movilidad sin control ⇒ remunerativa); RTF 8729-5-2001, 09222-1-2001, 8653-4-2001 (condiciones de trabajo)
- Tu propio código: `supabase/migrations/0029_provisiones_acumuladas.sql:15`
