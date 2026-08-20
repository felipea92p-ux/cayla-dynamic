# Política salarial de CAYLA

> Documento **vivo**: se edita, no se acumula ni se fecha en el nombre.
> Verificado empíricamente contra producción el **2026-08-07**.
>
> Su razón de ser: en agosto de 2026 una sesión de trabajo dedicó horas a
> "corregir" el cálculo de planilla —factor, base, feriado, RMV— y al medirlo
> contra datos reales resultó que **no había nada roto**. Todo salía de supuestos
> encadenados que nadie había escrito. Esto es lo que se verificó, para que la
> próxima vez se lea antes de tocar.

---

## La jornada

**45 horas por semana**, cuando el máximo legal son 48 (Constitución art. 25).
No es un descuido: es una decisión de la empresa, y son **3 horas semanales por
persona por encima de lo que la ley exige** — unas 156 horas al año.

Se cumple en tres regímenes distintos según la sede. Los tres suman lo mismo:

| Sede | Días | Horas/día | Horas/semana | Domingo |
|---|---|---|---|---|
| **TRU** (tiendas) | 6, con descanso rotativo | ~7,9 | ~47 | **sí se trabaja** |
| **LIM** (taller) | 5 (L-V) | ~9,0 | ~45 | no |
| **AQP** | 5 | ~7,3-8,5 | ~37-39 | no |

Medido sobre 8 semanas de marcajes reales, no sobre horarios asignados.

**En Trujillo se trabaja domingo.** El descanso semanal de esa gente cae otro
día. Cualquier consulta que asuma "lunes a sábado" da resultados falsos para TRU
— es el error que la migración 0109 ya había corregido en el código y que se
repitió a mano en agosto de 2026.

---

## Cómo se paga

```
pago del periodo = horas marcadas × salario ÷ (6,5 × días del periodo)
```

**El periodo va del 29 de un mes al 28 del siguiente.** No es mes calendario.
Leerlo siempre de `periodos_planilla`, nunca asumirlo.

### De dónde sale el 6,5, y por qué está bien

Es el factor que convierte las horas mensuales objetivo a días de calendario:

```
26 días laborables × 7,5 h = 195 h al mes
195 ÷ 30 días = 6,5
```

**Se verificó contra los marcajes reales y está correctamente calibrado.**
Quien cumple su jornada da un factor implícito de **6,61** (horas semanales ÷ 7),
por encima del 6,50 que usa el sistema. Es decir: el sistema pide algo menos de
lo que trabaja quien cumple, y esa gente cobra 102-105 % de su salario de
referencia.

| persona (ago-2026) | h/día | h/semana | factor implícito |
|---|---|---|---|
| Melany Enriquez | 7,98 | 47,9 | 6,84 |
| Danixa Valverde | 7,85 | 47,1 | 6,73 |
| Janis Revilla | 7,94 | 46,6 | 6,66 |
| Diana Palacios | 7,86 | 45,2 | 6,46 |

---

## Lo que se investigó y se DESCARTÓ

Cinco supuestos que parecían defectos y no lo eran. **Están acá para que no se
vuelvan a perseguir.**

| Supuesto | Por qué es falso |
|---|---|
| *"El feriado debería valer un día de la jornada de cada quien"* | No. Se paga **proporcional al tiempo laborado del mes**: quien vino la mitad cobra la mitad. Decisión de Felipe, confirmada. Que un part-time cobre menos feriado **no es un bug**. |
| *"El factor debería ser 45/7 = 6,4286 en vez de 6,5"* | Asumía 7,5 h/día. Se marcan ~7,9. Cambiarlo subiría la planilla 1,11 % (S/ 228/mes) corrigiendo algo que no está roto. |
| *"Hay un efecto calendario del 9,5 %"* | Artefacto de contar días laborables enteros (25/26/27). La gente trabaja por ritmo semanal, no por cupo mensual de días. |
| *"Quien gana la RMV cae por debajo del mínimo legal"* | No. La escala arranca en S/ 1 320 y el salario mínimo seguro es S/ 1 176. Hay 12 % de colchón. |
| *"El equipo trabaja 4,4 días por semana"* | Promedio contaminado: mezclaba a 6 personas con menos de 8 semanas de antigüedad. Quien lleva tiempo y cumple hace 6 días. |

**La lección de método:** medir antes de proponer. Cada uno de esos cinco salió
de razonar sobre el supuesto anterior en vez de consultar la base. La medición
que zanjó todo —horas por día, por persona, excluyendo ingresos recientes— cabía
en una consulta.

---

## Cómo se paga un feriado

Tres partes, y conviene tenerlas separadas porque se confunden:

| | Qué es | Cuándo |
|---|---|---|
| **1** | Las horas marcadas ese día | solo si vino |
| **2** | Esas mismas horas otra vez (sobretasa del 100 %, **art. 9** D. Leg. 713) | solo si vino |
| **3** | El día de feriado prorrateado: `7,5 × horas_mes ÷ base` — es el **art. 8**, la remuneración ordinaria del feriado no laborable | **siempre**, venga o no |

> Esta tabla citaba el art. 8 para la sobretasa, y era al revés: el **art. 8** es
> el pago del día feriado (la parte 3) y el **art. 9** es la sobretasa del 100 %
> por trabajarlo sin descanso sustitutorio (la parte 2). Corregido y verificado
> contra el texto de la norma el 2026-08-10. `CLAUDE.md` ya lo citaba bien.

Las tres juntas son el "pago triple". La parte 3 es proporcional al mes
trabajado — ver la tabla de descartados.

**Descanso sustitutorio:** compensar un feriado laborado con un día libre solo
vale si ese día **iba a ser de trabajo**. Un día libre puesto sobre el descanso
semanal no compensa nada y la sobretasa se sigue debiendo. La validación de la
0069 lo impide a propósito.

---

## Reglas que no se reabren

- **Régimen MYPE pequeña empresa.**
- **El pago es por horas marcadas.** No es sueldo mensual con descuento: quien
  trabaja menos horas cobra menos, y eso es correcto.
- **Base 6,5 h × días del periodo.** Verificado 2026-08-07.
- **Factores de provisión** (grati 8,33 % · CTS 4,17 % · vacaciones 4,17 %) en
  `configuracion.planilla_provisiones`.
- **Ningún rango por debajo de S/ 1 176**, que es el piso que garantiza no caer
  bajo la RMV en el peor periodo del año. Hoy la escala arranca en 1 320.
  **Revisar esta regla cuando la RMV suba por encima de S/ 1 269.**

---

## El descanso semanal, y las cuatro cosas que ya se midieron

Verificado el **2026-08-19** con catorce agentes: siete buscando la norma por
artículo y siete cuyo único trabajo era refutarles. Se anota aquí porque el
sistema **todavía no paga la sobretasa del descanso semanal**, y quien vaya a
construirla necesita estas cuatro respuestas antes de escribir una línea.

**1 · La sobretasa del 100 % existe y hoy no se paga.** Art. 3 del D. Leg. 713:
trabajar el día de descanso semanal sin sustitución se paga con la retribución
más una sobretasa del 100 %. `fn_planilla_calcular` conoce dos sobretasas —la
del feriado y el recargo del sobretiempo— y **ninguna lectura de `turnos`**.

**2 · Feriado y descanso semanal NO se acumulan.** Si el día es a la vez el
descanso de la persona y un feriado, se paga **una sola** sobretasa del 100 %,
no dos. El día se liquida en triple (remuneración del día + la labor + 100 %);
el 1 de mayo es la excepción, y aun ahí la sobretasa sigue siendo una. Cinco
intentos de refutación fallaron. *Consecuencia práctica: si el 7.º día de una
racha cayó en feriado, esa persona ya cobró lo que le tocaba.*

**3 · El personal de dirección está EXPRESAMENTE excluido, y la norma es del
reglamento — no es interpretación.** Art. 5 del D.S. 012-92-TR:

> «Por excepción, ni el descanso sustitutorio ni el pago por descanso semanal
> obligatorio omitido son exigibles en los casos de trabajo realizado por
> miembros de una misma familia; tampoco en el caso de trabajadores que
> intervengan en labores exclusivamente de dirección o inspección, y en general
> todos aquellos que trabajen sin fiscalización superior inmediata…»

Dos refutadores independientes llegaron al mismo artículo, leyéndolo del PDF del
Congreso. **Cualquier cálculo de esta sobretasa tiene que excluir
`personal_direccion`** — que es la columna propia que la 0187 creó justo para no
deducir la dirección del rol del sistema.

**4 · La sustitución tiene plazo, y es la MISMA SEMANA.** No basta con darle
otro día libre más adelante: si el descanso se mueve dentro de la misma semana,
no se debe sobretasa; si se mueve fuera, sí. Y **una racha de 7 días seguidos no
es por sí sola una infracción** — lo que se infringe es el art. 1 cuando el
ciclo de siete días no contuvo 24 horas continuas de descanso. Con descanso
**rotativo** —el régimen de TRU— rotar el descanso de un lunes a un domingo
encadena siete días sin que nadie haya hecho nada mal.

De ahí que el sistema no pueda decidir esto solo: **una racha es un candidato,
no una deuda**, y quién sustituyó qué día lo sabe DO. Hoy no hay dónde anotarlo
— `feriados_descanso_sustitutorio` está atada a `fecha_feriado`.

## El periodo de prueba SÍ devenga beneficios

Verificado el mismo día, por cuatro frentes y sus cuatro refutadores. La
respuesta es unánime y con alta confianza: **no existe ninguna norma peruana que
diga que durante el periodo de prueba no se devengan CTS, gratificación ni
vacaciones.** El art. 10 de la LPCL agota su efecto en la protección contra el
despido arbitrario.

- **CTS** — art. 2 del TUO D.S. 001-97-TR: se devenga desde el primer mes.
- **Gratificación trunca** — art. 5 del D.S. 005-2002-TR, con el mismo mínimo.
- **Vacaciones truncas** — art. 23 del D.S. 012-92-TR (el 23, no el 22: el 22 es
  la fórmula de dozavos).

**El umbral es UN MES de servicios, y es el que decide.** Menos de un mes da
cero por la norma, no por la etiqueta. Ésa es exactamente la premisa con la que
se tomó la decisión del 26/07/2026 registrada en la cabecera de la
`0085_tipo_de_vinculo.sql` — «por los mínimos legales casi siempre daría cero de
todas formas»—, y es una premisa **medible**, no una opinión:
`scripts/sql-manual/que_cobraron_las_que_se_fueron.sql` la comprueba caso por
caso contra quienes cesaron.

La decisión sigue siendo de Felipe y sigue siendo reversible en una línea, que
es como se dejó escrita. Lo que cambia con esta verificación es que ya no hay
duda sobre qué dice la norma: la duda que queda es aritmética.

---

## Pendientes conocidos

- **`tipo_vinculo = 'prueba'` no devenga beneficios.** `fn_devenga_beneficios`
  devuelve `true` solo para `'planilla'`, así que a quien está en periodo de
  prueba no se le provisiona CTS, gratificación ni vacaciones, y sus truncas
  saldrían en cero. El periodo de prueba (LPCL art. 10) solo afecta la
  protección contra el despido, no los beneficios. **Verificado contra la norma
  el 2026-08-19** (ver arriba): sí devengan, con un mínimo de un mes de
  servicios. La decisión de no devengar es de Felipe, del 26/07/2026, y está
  registrada en la cabecera de la `0085`. **Sin resolver.**
- **Los RxH reciben feriados y provisiones** que no les corresponden.
  `fn_planilla_calcular` no consulta `fn_devenga_beneficios`; `fn_provisiones` sí.
  Dos funciones, dos respuestas a la misma pregunta. **Sin resolver.**
- **Los días programados no coinciden con la realidad.** El sistema cree que a
  algunas personas les tocaban 12 días cuando marcaron 21, porque el cálculo lee
  `horarios_asignados` e ignora `turnos`. No afecta el pago (que sale de horas
  marcadas) **pero sí al motor de faltas**, que usa esa misma pregunta para
  decidir quién no vino cuando debía.
- **Melany Enriquez hace 47,9 h/semana**, a seis minutos del máximo legal de 48.
  No es infracción, pero es un margen que conviene vigilar.
