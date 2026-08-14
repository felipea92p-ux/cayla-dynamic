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

## Dónde está el texto

**En [`acuerdo-dia-no-laborable-arequipa.html`](acuerdo-dia-no-laborable-arequipa.html),
y solo ahí.** Se abre en el navegador y se imprime con ⌘P — o se guarda como PDF
desde el mismo diálogo. Trae ya las dos copias por persona, empresa y
colaboradora, cada una en su página.

Este archivo llevaba las cinco cláusulas escritas otra vez. Estaban idénticas
—comprobado carácter por carácter el 2026-08-12— y ese es justo el momento en
que hay que separarlas: mientras coinciden, nadie nota que son dos. El día que
alguien corrija una coma en el papel que se firma, este archivo seguiría diciendo
lo anterior, y no habría forma de saber cuál de los dos se entregó.

Un documento que se firma tiene UN texto. Acá queda el porqué y el cómo; el qué
vive en el HTML.

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

⚠️ **Esto no es automático.** El sistema no sabe que el 15 de agosto existe: el
cálculo lo hace la consulta, pero la entrada es a mano. Si nadie la hace, esas
personas descansan el 31 y no cobran ese día — y el acuerdo que firmaron dice que
sí les tocaba.

Por eso no depende de que alguien se acuerde. Hay **dos redes**, puestas el
2026-08-12:

- El pendiente está en [`estado.md`](estado.md), en la tabla de los que tienen
  fecha, junto a los convenios de movilidad y el Seguro Vida Ley.
- Hay una **tarea programada para el 29/09/2026 a las 9:00** que lo recuerda con
  la consulta lista. Corre mientras la app esté abierta; si ese día está cerrada,
  salta en cuanto se abra.

**Y se descartó la tercera red, que parecía la buena:** enseñarle a la tabla de
feriados a tener sede, para que la planilla lo calculara sola. Se descartó por
dos razones, y la primera pesa más que la segunda:

1. **Sería el concepto equivocado.** Esto NO es un feriado. Modelarlo como
   «feriado de una sede» haría que el sistema pagara el recargo del 100 % a quien
   trabajara ese día, salvo que alguien se acordara de otorgar además el descanso
   sustitutorio. Se cambiaría el trámite, no la dependencia de la memoria.
2. **Son quince las funciones que leen `feriados`** —contadas el 2026-08-12—,
   entre ellas el cálculo de planilla, la proyección y la detección de faltas.
   Tocar esa última para un caso que ocurre tres o cuatro veces al año arriesga
   marcar ausente a quien sí vino, que es el peor error que este sistema puede
   cometer.
