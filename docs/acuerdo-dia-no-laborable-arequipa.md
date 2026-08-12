# Acuerdo de descanso sustitutorio — día no laborable de Arequipa

**Plantilla.** Se imprime una por persona de la sede AQP, se firma **antes o el
mismo 15/08**, nunca después: un pacto fechado después del día trabajado no
sustenta lo que dice sustentar, y encima lo deja por escrito.

---

## Por qué existe este papel

El **15 de agosto** es *día cívico no laborable* en la provincia de Arequipa por
el **artículo 8 de la Ley 24875**, aplicado conforme al **artículo 7 del
D. Leg. 713**. No es un feriado nacional: **no genera pago triple**.

Para el sector privado la norma no impone una salida única. Si la persona
trabaja ese día, lo que corresponde es acordar con ella un día de descanso. Ese
acuerdo es este papel — y sin él, lo único que queda registrado es que se trabajó
un día no laborable sin compensación pactada.

CAYLA además decide **pagar** ese día de descanso, cosa que la norma no exige.
Conviene que el documento lo diga con esas palabras: es una mejora voluntaria, no
el cumplimiento de una obligación, y así no se convierte en precedente exigible
por sí sola.

---

## El texto

> **ACUERDO DE DESCANSO SUSTITUTORIO**
>
> En la ciudad de Arequipa, a los ____ días del mes de agosto de 2026, entre:
>
> **CAYLA** (en adelante, la empresa), con RUC ____________, debidamente
> representada por ____________________, identificado con DNI ____________; y
>
> **____________________________________**, identificada con DNI
> ____________, quien presta servicios en la sede Tienda Arequipa (en adelante,
> la colaboradora);
>
> se acuerda lo siguiente:
>
> **PRIMERO — El día.** El sábado **15 de agosto de 2026** es día cívico no
> laborable en la provincia de Arequipa, conforme al artículo 8 de la Ley 24875,
> aplicado según el artículo 7 del Decreto Legislativo 713. Ambas partes dejan
> constancia de que **no se trata de un feriado nacional**.
>
> **SEGUNDO — Lo que se acuerda.** La colaboradora prestará servicios el 15 de
> agosto de 2026 dentro de su jornada habitual, y en compensación gozará de
> descanso el **lunes 31 de agosto de 2026**, día que le correspondería laborar.
>
> **TERCERO — El pago.** El día de descanso del 31 de agosto será **remunerado**.
> Su importe se calcula en proporción a las horas efectivamente trabajadas por la
> colaboradora en el periodo, conforme a la fórmula de cálculo que la empresa
> aplica a la jornada diaria, y se abonará identificado como tal en su boleta.
>
> Las partes dejan constancia de que **este pago constituye una mejora voluntaria
> otorgada por la empresa**, y no el cumplimiento de una obligación derivada del
> régimen de días no laborables, que no exige remuneración del descanso
> sustitutorio.
>
> **CUARTO — Alcance.** Este acuerdo se refiere única y exclusivamente al 15 de
> agosto de 2026 y no genera derecho adquirido respecto de días no laborables
> futuros, cuyo tratamiento se acordará en su oportunidad.
>
> **QUINTO — Libre voluntad.** La colaboradora declara que suscribe el presente
> acuerdo de manera libre e informada, habiendo comprendido su contenido, y que
> ha tenido la posibilidad de no aceptarlo.
>
> En señal de conformidad, ambas partes firman por duplicado.
>
> &nbsp;
>
> ______________________________  ______________________________
> **Por CAYLA**                    **La colaboradora**
> Nombre:                          Nombre:
> DNI:                             DNI:
>
> &nbsp;
>
> Arequipa, ____ de agosto de 2026.

---

## Lo que hay que cuidar al usarlo

**Una por persona, firmada por duplicado.** Un acta colectiva con varias firmas
sirve menos: si una sola persona discute su caso, arrastra al resto del papel.

**La fecha de firma manda.** Antes o el mismo 15. Un acuerdo firmado el 20 de
agosto sobre un día trabajado el 15 es un documento que la propia empresa emite
en su contra.

**Guarda el ejemplar firmado.** Hoy Dynamic no tiene dónde archivarlo — los
buckets existentes son para memos disciplinarios, declaraciones de ruta y actas
de descanso—. Va en la carpeta física o en el Drive, y conviene anotarlo donde
lleves los papeles del equipo.

**Si alguien no quiere firmar.** Está en su derecho, y ahí el descanso
sustitutorio no queda pactado: entonces se le paga el 15 como día trabajado
normal y no se le da el 31, o se busca otro acuerdo. Lo que no se puede es
darle el descanso y no tener el papel.

---

## Cómo se paga, en concreto

El monto sale de la consulta
[`cuanto_vale_el_dia_sustitutorio_de_arequipa.sql`](../scripts/sql-manual/cuanto_vale_el_dia_sustitutorio_de_arequipa.sql),
que usa la misma fórmula que el sistema aplica al día de feriado prorrateado:

```
7.5 × horas_mes / base × salario / base        con base = 6.5 × días del periodo
```

Comprobado el 2026-08-12: con jornada completa (195 h) da **S/40.70**; con media
jornada (97.50 h) da **S/20.35**, la mitad exacta. Escala con las horas reales,
así que no hace falta clasificar a nadie como completa o media.

**Cuándo:** después del cierre del periodo de septiembre (29/08–28/09), cuando
las horas estén completas. Corrida antes, la consulta devuelve un monto corto.

**Cómo:** en la pantalla de Planilla, con el botón `±` de cada fila de AQP, como
**bono**, con este concepto:

> `Día sustitutorio 31/08 por el 15/08 no laborable (Ley 24875) — trabajado`

⚠️ **Esto no es automático y nadie lo va a recordar por ti.** El sistema no sabe
que el 15 de agosto existe: el cálculo lo hace la consulta, pero la entrada es a
mano, y si nadie la hace, esas personas descansan el 31 y no cobran ese día.
