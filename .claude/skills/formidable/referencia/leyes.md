# Las 9 leyes de Formidable: prueba y cura

Cada ley tiene de dónde sale (nivel de evidencia en `fuentes.md`), su **prueba** (pasa o falla, sin «me parece»), la **falla típica** y la **cura**. Las fallas típicas son formas a buscar, no hallazgos medidos: en Dynamic todavía no hay pantalla piloto. El orden es la prioridad: si dos leyes chocan, gana la de número menor.

---

## 1 · Sin manual
**Fuente:** Nielsen (reconocer en vez de recordar) y Norman (la señal debe decir qué hacer). Verificado.
**Prueba:** un agente ciego y, si se puede, una persona real completan la tarea al primer intento y con **0 preguntas**; a los **5 s** dicen qué es la pantalla y qué sigue.
**Falla típica:** una pestaña o un contador cuyo nombre no dice qué se decide.
**Cura:** el título y el primer renglón dicen qué se decide; el siguiente paso es un botón con verbo.

## 2 · Una pregunta, una respuesta
**Fuente:** «Focus» (Isaacson sobre Jobs) y la deferencia de las guías de Apple.
**Prueba:** la pantalla se resume en **una pregunta escrita en una frase** y tiene **una sola acción primaria** a la vista (`variante="primario"`).
**Falla típica:** cifras, avisos y filtros antes de lo que importa; el título es el nombre del módulo y no la pregunta que resuelve.
**Cura:** nombra la pregunta («¿Quién llegó tarde esta semana?») y deja arriba solo lo que la contesta.

## 3 · Simplicidad profunda
**Fuente:** Isaacson, sobre Jobs e Ive: la simplicidad que vence la complejidad, no la que la esconde. Reportado.
**Prueba:** ninguna cifra compleja aparece cruda: cada una se muestra como un **veredicto**, y el cálculo vive bajo «¿Por qué?» (ley 6).
**Falla típica:** «6.5 × días», un factor de provisión o un saldo en decimales a la vista de una integrante.
**Cura:** traduce a lo que la persona haría o entendería. Si la regla es difícil de traducir, no la simplifiques: eso es de Felipe (candado 3).

## 4 · Lenguaje de la casa
**Fuente:** Nielsen (el idioma de la persona). Verificado. Voz: «tú», español neutro peruano, sin modismos.
**Prueba:** el agente ciego repite cada texto con sus palabras sin equivocarse; ningún término sale de la jerga (estados internos, nombres de columna). Se respeta el vocabulario de `CLAUDE.md`: integrante, líder de equipo, sede, DO, preselección. Frases de 12 palabras o menos como regla práctica (Opinión).
**Falla típica:** un valor interno a la vista, como `sueldo_fijo` o `en_planilla`.
**Cura:** nombra el estado por lo que significa para quien actúa.

## 5 · Contenido primero
**Fuente:** deferencia (Apple HIG). Verificado.
**Protagonista por módulo:** Equipo = la **persona** · Asistencia = la **jornada** · Planilla = el **pago** · «Lo mío» = **lo que me toca hoy** · Terminal = **quién soy y en qué estado estoy**. Un módulo nuevo declara el suyo en el informe.
**Prueba:** el protagonista es el elemento más grande y de mayor contraste de su zona (se mide).
**Falla típica:** las tarjetas de cifras pesan más que la tabla de personas.
**Cura:** el protagonista sube; el marco baja de peso.

## 6 · Lo difícil, a un toque
**Fuente:** divulgación progresiva (Nielsen) y Apple. Verificado.
**Prueba:** el detalle técnico existe, se abre con **un toque** —nunca depende de hover, que no existe en el celular— y **no está a la vista por defecto**. Falla si falta: en Dynamic poder explicar un monto es parte de pagarlo bien.
**Falla típica:** una leyenda larga siempre abierta, o un monto sin forma de saber de dónde sale.
**Cura:** el veredicto arriba; «¿Por qué?» abre el detalle.

## 7 · Perdonar antes que preguntar
**Fuente:** Nielsen (control y libertad) y Apple. Verificado.
**Prueba:** inventario de acciones, cada una **reversible** o **irreversible**. Un «¿Seguro?» en algo reversible falla; una acción irreversible sin resumen previo también. **Irreversible = pagar, cerrar un periodo, firmar, sancionar, borrar.** Lo reversible (filtros, selección, marcar visto) ofrece Deshacer.
**Falla típica:** el «¿seguro?» por costumbre, o ausente donde se paga. Verifica leyendo el código.
**Cura:** reclasifica; confirma lo irreversible con el resumen de qué cambiará.

## 8 · Quitar antes de agregar
**Fuente:** Jobs y Carmack. Reportado o criterio del repo.
**Prueba:** por cada elemento visible: ¿ayuda a contestar la pregunta de la ley 2? Los que no, se proponen para esconder o mover, con el porqué. El informe propone **3 cambios**, no 12. **Nunca borra datos.**
**Falla típica:** una tarea de otra pantalla metida dentro de esta.
**Cura:** una fila, una frase y una acción; el resto bajo «¿Por qué?» o en su pantalla.

## 9 · De punta a punta, hasta el último detalle
**Fuente:** «Take responsibility end to end» (Isaacson sobre Jobs). Reportado.
**Prueba:** recorrer **todos los estados**: vacío, error, cargando (`<Cargando />`), éxito, sin permiso, sin conexión, primer uso y modo oscuro. Para el nombre largo y los vacíos están `nombre.largo@dynamic.local` y `sin.datos@dynamic.local`. Falla si un estado muestra texto de sistema, un código, un hueco o una disculpa.
- **Vacío:** dice qué falta y cómo conseguirlo (`<EstadoVacio>`).
- **Error:** tres líneas: qué pasó, qué se conservó y qué sigue; sin culpar y sin código.
- **Primer uso:** la pantalla se explica sola; cero tours.
**Cura:** un texto cuidado por cada estado, escrito según la ley 4.

---

## Qué no es una ley
Ya lo cubren otras reglas y no se duplica aquí: las piezas (ADR 0004 y `receta-suelta`), el color (los trece tokens), el responsive (`responsive:check`) y el contraste (`tema:auditar`).
