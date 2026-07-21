# Documentación disciplinaria automática — tardanzas y faltas

> Investigación de normativa peruana vigente + diseño propuesto. **Nada construido aún.**
> Fecha: 2026-07-21. Base para aprobación antes de ejecutar.
> **Vigencia verificada contra fuentes oficiales (gob.pe / MTPE / El Peruano) al 2026.** El marco (D.S. 003-97-TR, arts. 25 y 31) sigue vigente. Existe un *dictamen* de la Comisión de Trabajo del Congreso para incorporar sanciones distintas al despido — es **proyecto, no ley**; se vigila, hoy no aplica.

---

## 1. Lo que dice la ley (y por qué importa para el sistema)

### 1.1 Hay DOS vías paralelas e independientes — no confundirlas

| Vía | Qué es | ¿Es sanción? | ¿Cayla ya lo hace? |
|-----|--------|--------------|--------------------|
| **Contraprestativa** | Descontar el tiempo no laborado (los minutos de tardanza / el día de falta) | **NO** | **SÍ** — la planilla paga por horas marcadas, así que el descuento ya está implícito |
| **Disciplinaria** | Amonestación → suspensión → despido | **SÍ** | **NO** — esto es lo nuevo (el memo) |

Punto legal clave: *"Los descuentos por tardanzas e inasistencias injustificadas no tienen naturaleza sancionadora, por lo que no eximen de la aplicación de las sanciones disciplinarias."* Es decir: descontar el minuto **no** reemplaza al memo, y el memo **no** reemplaza al descuento. Son dos cosas distintas. El sistema de disciplina que vamos a construir es **solo la vía disciplinaria**.

### 1.2 La escala disciplinaria (progresión obligatoria)

La ley exige **proporcionalidad** y **gradualidad**. No se puede saltar al despido. El orden es:

1. **Amonestación verbal** — llamada de atención. Conviene dejar constancia de que ocurrió (fecha), aunque sea verbal.
2. **Amonestación escrita** — el memorándum. Primera sanción documentada.
3. **Suspensión sin goce de haber** — normalmente 1 día, escalable. *No hay tope legal; el "techo" informal de la práctica privada es ~7 días.* Debe ser proporcional.
4. **Despido** — última ratio, y solo tras agotar lo anterior.

### 1.3 Tardanzas: cuándo se vuelven causal de despido (art. 25-h LPCL)

- **No existe un número fijo de tardanzas** en la ley. Se evalúa caso por caso.
- Para que el despido por impuntualidad reiterada sea **válido**, la jurisprudencia de la Corte Suprema exige que **antes hubo sanciones previas** documentadas (amonestación escrita + suspensión). *Sin el expediente de sanciones progresivas, el despido por tardanzas es arbitrario* — aunque las tardanzas existan.
  - Casaciones: **13768-2017-Lambayeque** (exige sanciones previas), **6977-2023-Lima**, **13548-2019-Lima Este**.
- Conclusión para el sistema: el valor real del expediente no es "despedir", es **construir la escalera documentada** que hace que cualquier medida futura se sostenga.

### 1.4 Faltas / inasistencias: umbrales (art. 25-h LPCL) — ya verificados

- **Abandono de trabajo**: más de 3 días consecutivos ⇒ causal **desde el 4.º**.
- **Ausencias injustificadas**: más de 5 en 30 días calendario ⇒ **desde la 6.ª**.
- Más de 15 en 180 días calendario ⇒ **desde la 16.ª**.
- *"Hayan sido o no sancionadas"*: sancionar no borra el conteo.

### 1.5 Principio de inmediatez — el reloj corre (esto justifica el semáforo)

- El empleador debe imputar/sancionar en un **plazo razonable** desde que conoce la falta. No hay número fijo, pero la demora injustificada = **condonación tácita** = sanción/despido **inválido**.
- La **carga de la prueba** de haber actuado con inmediatez es **del empleador**.
- **Implicancia directa para el tablero**: un semáforo que solo dice "roja" no basta; tiene que decir *"esta incidencia es del [fecha], actúa pronto o se entiende condonada"*. Si Felipe reacciona tarde a un pico viejo, la medida se cae por condonación tácita.

### 1.6 Carta de preaviso de despido (art. 31 LPCL)

- Mínimo **6 días naturales** para que la persona presente descargos.
- No se puede decidir el despido antes de vencido ese plazo (derecho de defensa).
- La imputación **no** afirma culpabilidad (presunción de inocencia).
- El sistema **documenta y avisa; nunca dice "despide"**.

### 1.7 Reglamento Interno de Trabajo (RIT) — Cayla NO está obligada, pero…

- El RIT registrado ante el MTPE es obligatorio para empleadores con **más de 100 trabajadores** (D.S. 039-91-TR) — confirmado por fuente **oficial** (MTPE y El Peruano). **Cayla, con ~10 personas, está muy por debajo: NO está obligada.** Nota: la propia norma exige que el RIT contenga "control de asistencia" y "medidas disciplinarias" — es exactamente el contenido que tendría la política interna de Cayla.
- **PERO**: *"no tener la escala disciplinaria definida puede invalidar los despidos por faltas disciplinarias."* La tipificación de faltas y la escala de sanciones **tiene que existir por escrito** (RIT o una política interna firmada), o los memos pierden respaldo.
- **Recomendación**: Cayla debe tener una **política de asistencia escrita y aceptada por el equipo** (tolerancia de 15 min, qué cuenta como tardanza/falta, la escala). El sistema puede citarla en cada memo. Sin esa base, el memo cita solo la LPCL, que es más débil.

---

## 2. Estructura del memorándum (campos que la ley exige)

Un memorándum de amonestación válido lleva:

- **N.º correlativo** de memorándum (para el legajo).
- **De** (la empresa / representante con cargo) **· Para** (la colaboradora, con cargo/sede).
- **Fecha** de emisión.
- **Asunto**: p.ej. "Amonestación escrita por tardanzas reiteradas".
- **Hechos concretos**: las fechas y horas exactas de cada tardanza/falta (el sistema las tiene). Referencia a llamadas de atención previas si las hubo.
- **Tipificación**: la norma infringida (política interna de Cayla + artículo de la LPCL).
- **Exhortación** a corregir + **advertencia** de la sanción siguiente en la escala si reincide.
- **Firma** del representante de la empresa.
- **Cargo de recepción**: espacio para firma y fecha de la colaboradora (o constancia de negativa a firmar).
- **Copia al legajo** personal.

---

## 3. Diseño propuesto: UN legajo, plantillas y medidas POR causal

Reconcilia tu observación ("la documentación y las medidas son diferentes") con la integridad del expediente. Tres capas:

### Capa 1 — El legajo (ÚNICO)

Una sola tabla `expediente_disciplinario`: cada fila = un documento emitido a una persona.

    persona_id · tipo_causal ('tardanza' | 'falta' | ...) · nivel_escala
    ('amonest_verbal' | 'amonest_escrita' | 'suspension' | 'preaviso')
    · fecha_emision · periodo_cubierto (rango de fechas de los hechos)
    · hechos (jsonb: las fechas/horas exactas que motivan el doc)
    · estado ('borrador' | 'firmado' | 'entregado' | 'anulado')
    · firmado_por · entregado_at · observacion

**Por qué único:** el día de una medida grave, la ley mira el **historial completo** de la persona (tardanzas + faltas + sanciones previas, todo junto) para probar reincidencia y proporcionalidad. Dos cajones separados = no puedes presentar el expediente completo de un vistazo y pierdes el argumento.

### Capa 2 — Las plantillas (UNA por causal, diferentes)

Cada `(tipo_causal, nivel_escala)` tiene su propia redacción. El memo de tardanza dice una cosa; la carta de amonestación por faltas, otra; el preaviso, otra. **Diferentes, como tú dices.** Viven como plantillas parametrizadas que el sistema rellena con los hechos.

### Capa 3 — La política de disparo y la medida (UNA por causal, diferentes)

Una tabla de umbrales por causal:

    causal · condicion (ej. "3 tardanzas en el mes calendario") · nivel_sugerido

- **Tardanzas**: la ley no fija número → lo define **tu política / tus documentos**. Propuesta base editable (a confirmar con lo que me adjuntes): 3.ª tardanza del mes ⇒ amonestación escrita; reincidencia el mes siguiente ⇒ suspensión 1 día.
- **Faltas**: los umbrales **ya son legales** (§1.4): 4 consecutivas / 6 en 30d / 16 en 180d.

---

## 4. El flujo: "el sistema arma, el humano firma" (decidido)

1. El motor detecta que alguien cruzó un umbral (tardanza o falta).
2. El sistema **arma el borrador** del documento que corresponde en la escala, con los hechos correctos ya rellenados.
3. El borrador aparece en pantalla marcado como **BORRADOR**. Nada se emite solo.
4. Felipe (o líder DO / encargada de sede según permiso) lo **revisa, ajusta y firma**.
5. Al firmar, pasa a `firmado`; se imprime/exporta para el cargo de recepción; queda en el legajo.

Esto respeta inmediatez (avisa temprano), defensa (la persona firma el cargo), y evita el falso positivo (un humano revisa antes de acusar).

---

## 5. Qué habría que construir (para aprobación)

1. **Migración**: tabla `expediente_disciplinario` + tabla `politica_disciplinaria` (umbrales) + RLS (igual patrón que justificaciones/correcciones).
2. **Motor de detección de tardanzas acumuladas** — análogo a `fn_faltas_resumen` pero sobre `minutos_tarde`. (Faltas ya lo tiene.)
3. **Función que arma el borrador** a partir de una persona + causal + periodo (rellena hechos desde jornadas).
4. **Plantillas** de cada documento (texto legal parametrizado).
5. **Pantalla / sección** "Legajo disciplinario" o dentro de Incidencias: ver umbrales cruzados, generar borrador, revisar, firmar, exportar para imprimir.
6. **Exportación imprimible** — no hay librería de PDF hoy; lo más simple es una vista HTML lista para imprimir (Ctrl+P → PDF), sin dependencia nueva.

---

## 6. Decisiones que necesito antes de ejecutar

- [ ] **Umbral de tardanza**: ¿la política que me vas a adjuntar, o parto de "3.ª del mes ⇒ escrita"?
- [ ] **Base normativa citada**: ¿existe una política de asistencia escrita y firmada por el equipo, o el memo cita solo la LPCL por ahora? (Recomiendo redactar la política — es lo que da respaldo.)
- [ ] **Quién firma**: ¿solo admin/líder DO, o también la encargada de sede sobre su gente?
- [ ] **Alcance de la primera entrega**: ¿empezamos solo por el **legajo + faltas** (que ya está casi listo) y sumamos tardanzas después, o todo junto?

---

## Fuentes

### Oficiales (verificadas, base normativa vigente 2026)
- **[TUO D.Leg. 728 — D.S. 003-97-TR (texto oficial, Congreso)](https://www2.congreso.gob.pe/sicr/cendocbib/con4_uibd.nsf/BE35EA4B0DF56C0A05257E2200538D4C/$FILE/1_DECRETO_SUPREMO_003_27_03_1997.pdf)** — arts. 25 (falta grave) y 31 (preaviso).
- **[Compendio de normas laborales — MTPE (trabajo.gob.pe)](https://www2.trabajo.gob.pe/archivos/dgt/compendio/28122017_Compendio_Normas_2017.pdf)**
- **[MTPE: RIT obligatorio para empresas de más de 100 trabajadores (D.S. 039-91-TR)](https://www.gob.pe/institucion/mtpe/noticias/739390-mtpe-empresas-de-mas-de-100-trabajadores-estan-obligadas-a-tener-reglamento-interno-de-trabajo)** · [El Peruano (mismo)](https://www.elperuano.pe/noticia/209594-mtpe-empresas-con-mas-de-100-empleados-estan-obligadas-a-contar-con-reglamento-interno-de-trabajo)
- **[D.S. 039-91-TR — SUNAFIL](https://www.sunafil.gob.pe/portal/noticias/item/6509-decreto-supremo-n-039-91-tr.html)**
- **[El abandono de trabajo debe acreditarse idóneamente — El Peruano](https://elperuano.pe/noticia/107562-el-abandono-de-trabajo-debe-acreditarse-de-manera-idonea)**
- **[El poder disciplinario del empleador — Boletín MTPE](https://www2.trabajo.gob.pe/archivos/boletin/bvice/Boletin_74.pdf)**
- **[Dictamen: sanciones disciplinarias distintas al despido (Congreso — PROYECTO, no ley)](https://comunicaciones.congreso.gob.pe/noticias/comision-de-trabajo-aprobo-dictamen-para-incorporar-sanciones-disciplinarias-distintas-al-despido/)**

### Doctrina y jurisprudencia (estudios/portales, para interpretación)
- [¿Cuándo se configura el despido por tardanzas? Cas. 13548-2019-Lima Este — LP](https://lpderecho.pe/cuando-se-configura-el-despido-por-tardanzas-del-trabajador-casacion-laboral-13548-2019-lima-este/)
- [Corte Suprema delimita el despido por impuntualidad reiterada — RSM Perú](https://www.rsm.global/peru/es/news/corte-suprema-delimita-los-alcances-del-despido-por-impuntualidad-reiterada)
- [Cas. 13768-2017-Lambayeque: despido por tardanzas procede solo si hubo sanciones previas — LaboraPerú](https://laboraperu.pe/casacion-13768-2016-lambayeque-requito-despido-tardanzas-reiteradas.html/)
- [¿Cómo se sancionan las tardanzas? ¿Se le puede despedir? — LP](https://lpderecho.pe/como-sanciona-tardanza-trabajador/)
- [Tipos de sanciones laborales: amonestación, suspensión y despido — Viera Santti Abogados](https://vsabogados.pe/tipos-de-sanciones-laborales/)
- [Me llegó un memorándum de sanción, ¿qué debo hacer? — Iura Lex](https://il-abogados.pe/blog/me-llego-un-memorandum-de-sancion-que-debo-hacer/)
- [Cómo calcular el descuento por tardanzas — Perú Contable](https://www.perucontable.com/laboral/como-calcular-eldescuento-por-tardanzas-a-los-trabajadores/)
- [El principio de inmediatez en el derecho del trabajo peruano — LP](https://lpderecho.pe/principio-inmediatez-derecho-trabajo-peruano/)
- [Corte Suprema: el despido debe ser inmediato tras la falta grave — EGEPUD](https://www.egepud.edu.pe/noticias/otras-noticias/corte-suprema-despido-debe-ser-inmediato-tras-falta-grave/)
- [Reglamento Interno de Trabajo: ¿cuándo es obligatorio? — Lexy Asesores](https://lexy.pe/reglamento-interno-de-trabajo-cuando-tener-uno/)
- [Límites de la suspensión sin goce de remuneraciones — Conexión ESAN / Gestión](https://gestion.pe/blog/conexion-esan/2026/03/limites-de-la-sancion-disciplinaria-de-suspension-sin-goce-de-remuneraciones.html)
- [Carta de preaviso de despido y procedimiento (art. 31 LPCL) — Enfoque Derecho / LP](https://lpderecho.pe/modelo-descargo-trabajador/)
- [Modelos de carta de sanción por tardanza y apelación — LP](https://lpderecho.pe/modelos-carta-sancion-tardanza-trabajador-apelacion/)
