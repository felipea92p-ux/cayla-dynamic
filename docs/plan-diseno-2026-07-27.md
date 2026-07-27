# Plan de trabajo de diseño — Dynamic

*Auditoría del 27-07-2026: 15 agentes sobre ocho dimensiones (color y contraste,
botones, navegación, formularios, responsive, accesibilidad, consistencia y
funcionalidad), con un escéptico por cada hallazgo grave. De seis hallazgos
marcados como graves, **cuatro se descartaron** tras revisarlos en contexto —
están al final de la sección 2 con el porqué.*
*27 de julio de 2026 · auditoría completa de las 24 pantallas de admin y el terminal*

Antes de empezar, una traducción que se usa en todo el documento: cuando digo **"contraste 3.39:1"** hablo de cuánto se despega un texto de su fondo. La medida internacional dice que un texto normal necesita al menos **4.5 a 1** para leerse sin esfuerzo; por debajo de eso, con reflejo o de reojo, el ojo lo saltea. No es una regla de manual: es exactamente lo que pasa cuando entra sol por la vitrina de la tienda.

---

## 1. EL DIAGNÓSTICO EN CINCO FRASES

1. **La columna vertebral del sistema visual está bien y hay que defenderla:** tinta sobre crema da 15.36:1, el rojo de la marca sobre crema da 4.83:1, no hay una sola sombra en toda la app y la identidad es reconocible en cualquier pantalla. Eso no se toca.
2. **Todo el problema está en el segundo escalón, que es donde vive la información que explica:** el taupe (#a47865) da 3.39:1 y se usa 448 veces; el ámbar sobre su propio fondo da 2.65:1. Dicho en simple: **el texto que solo etiqueta se lee, y el texto que explica por qué una cifra es la que es, no.**
3. **Por dentro la app está mejor construida de lo que su tamaño haría esperar:** los formularios grandes bloquean su botón mientras guardan, casi todas las cargas manejan el error, y Datos personales se niega a guardar si la carga falló. Hay criterio en el código.
4. **Lo que falla es un patrón único y repetido: todo lo que ocurre fuera de un formulario grande, ocurre en silencio.** Un checkbox, un campo que se guarda al salir, un enlace chico dentro de una tabla: no avisan que están trabajando, no confirman al terminar y en varios casos no dicen cuando fallan.
5. **No existe ninguna pieza compartida:** 186 botones escritos a mano uno por uno, el aviso de "guardado" copiado 12 veces, cero componentes de botón. La consecuencia no es estética: es que **cada pantalla vuelve a decidir sola, y de vez en cuando decide mal.**

---

## 2. LO QUE HAY QUE ARREGLAR YA

### 1. Oscurecer el taupe — una sola variable arregla 448 sitios
**Qué le pasa hoy a una persona:** los encabezados de columna de la planilla, las etiquetas **Tipo / Concepto / Monto (S/)** del formulario que agrega dinero a una boleta (`apps/web/app/(admin)/admin/planilla/page.tsx:517`, `:535`, `:546`) y los 24 nombres del menú (`apps/web/app/(admin)/admin/nav.tsx:93` y `:135`) están todos en taupe, casi siempre a 12px. Con luz de tienda no se leen. Quien revisa una planilla deja de leer los encabezados y **confía en la posición de la columna**: ahí es donde alguien lee un descuento creyendo que es un bono. Peor todavía: el desplegable que elige entre *Bono* y *Descuento* — lo que decide si el dinero suma o resta — tiene su etiqueta en el tono más lavado de la pantalla.

**El arreglo:** cambiar `--color-taupe` en `apps/web/app/globals.css:13` de `#a47865` a **`#805c4c`**. Mismo tono cálido, misma familia; pasa a 5.21:1 sobre crema, 5.58:1 sobre papel y 4.50:1 sobre el beige de los encabezados de tabla. Los 448 usos se corrigen solos. (Si se prefiere algo más suave, `#8c6453` da 4.56 / 4.88 / 3.94 — alcanza en todos lados menos sobre los encabezados de tabla, que es justo donde está la planilla; por eso recomiendo el primero.)
**Objeción anticipada, y respondida:** "el taupe es tenue a propósito, para que el dato principal mande". Cierto, y sigue mandando: la tinta da 15.36:1, así que subir el taupe a 5.21:1 todavía deja **tres veces** de distancia entre el dato y su etiqueta. La jerarquía no se pierde.
**Cuesta:** minutos el cambio, media hora revisar a ojo tres o cuatro pantallas — el taupe también dibuja bordes en 15 sitios y ahí se notará algo más marcado.

### 2. Oscurecer el ámbar y sacarlo de su propio fondo — son las advertencias de plata
**Qué le pasa hoy a una persona:** el ámbar sobre fondo ámbar da **2.65:1**, menos de la mitad de lo mínimo. Y ese par no es decoración: es el estilo de los avisos que explican el dinero. `planilla/page.tsx:1470` dice *"Este periodo ya está pagado, pero su desglose dejó de coincidir con los datos de hoy"*; `costos/page.tsx:295` avisa que un periodo tiene el desglose reconstruido; `planilla:1641` avisa de personas fuera del equipo que igual cobran; `provisiones/page.tsx:249` anuncia el próximo desembolso. **La frase que evita pagar mal es la menos legible de la pantalla.** Y el caso peor está en el terminal: `apps/web/app/(terminal)/terminal/marcar/page.tsx:354` muestra "⟳ N sin enviar" con ese mismo par — ese aviso significa *hay marcajes que no llegaron al servidor*, y si nadie lo ve, hay horas que no se pagan.

**El arreglo:** dos movimientos juntos, porque uno solo no alcanza. (a) Oscurecer `--color-ambar` en `globals.css:16` de `#b0812f` a **`#8d6726`**; con eso el ámbar sobre crema pasa de 3.07:1 a 4.51:1. (b) Cambiar el fondo de esos avisos y badges de `bg-ambar/15` a `bg-sand`, y dejar el ámbar solo para el texto — porque el fondo ámbar acerca el fondo al color de la letra y come el contraste que acabamos de ganar. Subir la opacidad del fondo **empeora** las cosas; es la trampa obvia. De paso, mismo criterio con `--color-verde`: `#5b754f` lo lleva a 4.51:1.
**Cuesta:** minutos las dos variables, una hora cambiar el fondo de los 19 badges y avisos.

### 3. Cuando una corrección de marcaje falla, el error se pinta detrás de la ventana
**Qué le pasa hoy a una persona:** en Correcciones, la encargada abre la ventana para corregir una marca, escribe el motivo y pulsa guardar. Si la base rechaza la operación, el código **sí** genera el mensaje de error (`correcciones/page.tsx:348`), pero lo pinta en un recuadro que vive arriba de la página (`:443`) — es decir, **debajo del velo oscuro de la ventana que sigue abierta** (`:695` y `:725` son overlays a pantalla completa). Lo que ella ve es: pulsé, no pasó nada. Vuelve a pulsar. **Una corrección de marcaje fallida se ve exactamente igual que una exitosa**, y las horas de esa persona quedan mal. Lo mismo en Horarios, Incidencias y Turnos.
**El arreglo:** que el mensaje se dibuje **dentro** de la ventana, junto al botón que se pulsó. Regla que queda escrita: *el mensaje va donde está la mano, no donde está el título*. Aplica también a Planilla, donde el error de una fila aparece a treinta filas de distancia.
**Cuesta:** una a dos horas las cuatro ventanas.

### 4. El silencio: lo que ocurre fuera de un formulario no avisa, no bloquea y a veces no falla en voz alta
**Qué le pasa hoy a una persona:** son cuatro casos con la misma forma y consecuencia distinta.
- **Objetivos** (`objetivos/page.tsx:324`): el checkbox que decide el plus de planilla —hasta 21% del salario— no cambia de aspecto ni se bloquea mientras viaja a la base. El gesto natural, volver a hacer clic porque "no pasó nada", **lo deja al revés de lo que la persona quiso**. Es el caso más caro de toda la app.
- **Turnos** (`turnos/page.tsx:342`): una llamada para quitar un turno descarta su error, así que la pantalla anuncia "Horario base actualizado" mientras el turno puntual sigue mandando.
- **Cuentas**: si la llamada al servidor falla, se muestra una tabla vacía. Parece que no hay cuentas.
- **Disciplina**: los días de suspensión se guardan al salir del campo, sin aviso y sin tope real — el `max={15}` no impide escribir 30, y la función de base tampoco valida.
**El arreglo:** el mismo en los cuatro: bloquear el control mientras viaja, confirmar al terminar, y mostrar el error cuando lo hay (Equipo ya tiene el bloque rojo con "Reintentar" que sirve de modelo).
**Cuesta:** una tarde los cuatro.

### 5. Las acciones que devuelven plata al cálculo no preguntan nada
**Qué le pasa hoy a una persona:** cuatro enlaces pequeños dentro de tablas ejecutan al primer clic, sin preguntar y sin avisar después: **"Quitar"** un descanso sustitutorio (ese feriado vuelve a pagar sobretasa), **"quitar justif."** (esa falta vuelve a contar para el expediente disciplinario), **"quitar"** el levantamiento de una tardanza (vuelve a contar y deja de sumar al bono de puntualidad) y **"Nuevo PIN"** (el PIN anterior deja de funcionar en ese instante, y el nuevo se muestra una sola vez). Ninguna es catastrófica por sí sola; todas cambian plata o un expediente con un clic accidental, y ninguna deja saber que ocurrió.
**El arreglo:** el `window.confirm` que Planilla ya usa en `:981`, con la consecuencia dicha en la frase — *"esta tardanza vuelve a contar y deja de sumar al bono de puntualidad"* — más el aviso verde al terminar. Simetría: si "Justificar" pregunta, "quitar justif." también.
**Cuesta:** minutos cada una.

*Sexto, de regalo porque cuesta una línea:* **Exportar CSV calcula "hoy" en horario de Londres, no de Lima** (`exportar/page.tsx:8`). Después de las 7 de la tarde el archivo sale vacío y se descarga mudo, sin decir que no encontró nada. Ya existe el ayudante de Lima que usan las otras cinco pantallas.

### Lo que se descartó, y por qué

- **«Sin marcar» es casi invisible en el dashboard** → **Descartado.** Es cierto que se dibuja a 1.78:1, pero *"Sin marcar" no es una alerta: es el valor por defecto* (`dashboard/page.tsx:210`). A las 8 de la mañana toda la tabla está así, incluida la gente de vacaciones o de descanso, porque la consulta no cruza horario ni feriados. Pintarlo de ámbar como se proponía llenaría la pantalla de falsas alarmas cada mañana y señalaría a quien está de vacaciones — exactamente el error que este sistema declara como el peor. Lo que **sí** vale: subir el tono de cuatro o cinco textos que son palabras con significado, no adornos — "sin medir" y el denominador en `horas/page.tsx:214` y `:216`, "sin horario" en `horarios/page.tsx:256`, y la propia etiqueta "Sin marcar". Los otros 69 casos son guiones que significan "cero"; un guion tiene el trabajo de callarse.
- **En Disciplina, el color es lo único que separa grave de leve** → **Descartado como urgente.** El badge sí repite el mismo texto en rojo y en ámbar, y hay que arreglarlo. Pero nadie va a sancionar mal por eso: los tres números están impresos, el umbral legal está escrito doce líneas arriba en la misma tarjeta (`disciplina/page.tsx:263`), los casos rojos salen siempre primero por el orden de la consulta, y sobre todo **el nivel del documento lo calcula la base de datos, no la pantalla**. Pulsar "Generar borrador" en una fila ámbar no puede producir una imputación. Es coherencia visual, no riesgo. Va a la lista de minutos.
- **Los botones secundarios no tienen borde visible (29 botones)** → **Descartado como urgente.** El borde beige efectivamente casi no se ve, pero no es un olvido: es la convención declarada en `globals.css:25` ("la línea fina es el único elemento decorativo: por defecto, Sand") y hay 126 botones que la escriben a propósito. Cambiar solo los 24 que la heredan **crearía** la inconsistencia que decía resolver. Se arregla bien dentro del componente de botón (punto 4 del trabajo de fondo), no antes.
- **«Reabrir periodo» se pinta igual que «+ Nuevo periodo»** → **Descartado como urgente.** Los dos botones **nunca aparecen a la vez** (`planilla:1509` los pone en ramas opuestas), están a 180 líneas de distancia, y "Reabrir" tiene arriba la insignia "PAGADO 🔒" y el texto *"el desglose quedó congelado; es la cifra que va a Costos"*. La escena de "tres botones iguales en la misma fila" no ocurre. Igual merece el mismo rojo que "Eliminar": son 30 segundos, va a la lista de minutos.

---

## 3. LO QUE MEJORA MUCHO POR MUY POCO ESFUERZO

Todo esto son minutos cada uno y se nota el mismo día:

- **Marcar dónde está el teclado.** Hoy ningún botón muestra dónde estás parada al navegar con Tab, y en diez campos —incluidos los dos del inicio de sesión— se borró la marca del navegador. Una sola regla en `globals.css` (`button:focus-visible { outline: 2px solid var(--color-rojo); outline-offset: 2px; }`) cubre los 186 botones y usa el acento de la casa.
- **Que el calendario no ofrezca lo imposible.** Ocho pantallas con rango de fechas dejan poner "hasta" antes de "desde". Poner `min` y `max` en los dos campos hace que el propio calendario lo impida — sin un solo mensaje de error.
- **Las dos tablas que corren la pantalla entera.** Hay 21 tablas y 19 están envueltas para que se deslicen solas; dos no, y al mirarlas se corre toda la página, encabezado incluido. Envolverlas igual que las otras.
- **El botón "×" que borra un bono no dice qué borra.** Para quien usa lector de pantalla es un aspa sin contexto en una boleta de pago. Un `aria-label` con el concepto y el monto.
- **El punto "En vivo" del dashboard late sin parar** y no respeta la preferencia de "menos movimiento" del sistema. Una línea en `globals.css` cubre esa y cualquier animación futura.
- **La palabra en el badge de faltas:** agregar "· umbral" / "· aviso", igual que ya hace el badge de tardanzas doce líneas arriba, en el mismo archivo.
- **"Reabrir periodo" en rojo,** como "Eliminar".
- **"Cuentas" promete gestionar accesos del equipo y abre "Mi cuenta".** Etiqueta según el rol, o mejor: sacarla de la barra y ponerla bajo el nombre de la persona, que hoy es texto muerto.
- **Dos pantallas dejan el menú sin nada marcado** (la boleta y el memo): marcar el activo por comienzo de dirección lo resuelve solo, hoy y en cualquier pantalla futura.
- **La lista de "días por revisar" promete "toca uno para cargarlo" y no lo carga.** El mecanismo ya existe doce líneas más arriba en el mismo archivo.
- **Que el gestor de contraseñas pueda llenar el inicio de sesión:** falta el atributo en ocho campos. Y el teclado numérico en celular para número de cuenta y celular.
- **En el terminal, "Continuar" se queda gris sin decir por qué.** Poner el cursor en el campo automáticamente y una línea debajo: "escribe al menos 3 letras". Un botón apagado sin motivo es un callejón sin salida frente a alguien que está de pie esperando marcar.
- **Siete lugares usan un amarillo de librería ajeno a la paleta,** justo al lado del ámbar propio. Reemplazarlo por el de la casa.

---

## 4. EL TRABAJO DE FONDO

Esto pide varias horas cada uno. El orden de abajo no es casual: los dos primeros **vuelven triviales** buena parte de los demás.

**1. Un componente de botón (`apps/web/components/boton.tsx`), tres variantes: primario, secundario, peligroso.**
Hoy hay 186 botones sin ningún componente detrás: conté 24 geometrías distintas de "primario" y tres colores de primario en conflicto. Por qué vale: el lenguaje de lo peligroso está roto **en las dos direcciones** — "Reabrir periodo" (descongela plata pagada) se pinta como una acción cualquiera, mientras que "Editar salario" se pinta de rojo, y con 30 personas en la tabla de Equipo eso son unos 60 rojos en una sola vista, contra la regla declarada de "máximo un rojo por vista". Cuando el rojo está en todas partes, deja de significar "cuidado". Además, 51 botones no tienen ningún relleno vertical: son texto puro, incluido el "×" que borra un bono de una boleta (unos 8 por 16 píxeles) y el "Cancelar" del terminal, **que se usa tocando la pantalla con el dedo**.

**2. Un componente de aviso (`components/aviso.tsx`).**
El aviso de "guardado" está copiado literalmente 12 veces, y el de éxito se pinta del mismo beige que un encabezado de tabla: el "se guardó" y el "esto es un dato informativo" son visualmente el mismo recuadro. Además, de 24 sitios donde la app confirma o falla, **ninguno lo anuncia** para quien no está mirando ese punto exacto de la pantalla. La versión buena ya existe (el verde de `personas/[id]:436` y el `Cargando` que se unificó hoy): hay que moverla, no inventarla. Empezar por las tres que tocan plata.

**3. Un solo lugar para los formatos (`apps/web/lib/formato.ts`).**
Este es el que más consecuencia tiene y el que menos parece de diseño: **las horas trabajadas —el número que multiplica el sueldo— se muestran en tres formatos con tres redondeos distintos** (142.75 h, 142.8, 142h 45m). Resumen de horas y Planilla parecen contradecirse para la misma persona en el mismo periodo, y quien revisa no sabe cuál creer. Al mismo archivo van: "hoy en Lima", hoy reescrito 15 veces con 4 nombres (y dos documentos que se imprimen fechados con la zona del navegador, no con la de Lima), el formato de soles que Feriados se perdió, y las tres funciones distintas que se llaman igual y hacen cosas diferentes.

**4. Enter que envía y Escape que cancela.**
Solo 4 de unos 30 formularios son un formulario de verdad. En Equipo, Ausencias, Sedes, Áreas, Datos personales y "Cambiar mi contraseña", pulsar Enter no hace nada — y ninguna ventana cierra con Escape. La pantalla Objetivos ya resolvió el patrón y nadie lo copió. En el mismo movimiento: nada protege lo tecleado — las ventanas se cierran al hacer clic fuera, y en Datos personales cambiar de persona en la lista de al lado **borra en silencio los 13 campos** (DNI, dirección, celular, cuenta bancaria) que se estaban escribiendo.

**5. Sacar el menú de las 24 pantallas y ponerlo una sola vez.**
Hoy el menú vive dentro de cada página, así que en cada clic se desarma, vuelve a preguntar quién eres y **durante ese viaje muestra 5 enlaces de 20 antes de saltar a 20**: el encabezado crece y empuja el contenido justo cuando la persona ya está apuntando el siguiente clic. Además ya existe un panel vertical agrupado, escrito y funcionando, que solo se usa en pantallas angostas: usarlo en todos los anchos deja el encabezado en una sola fila siempre y hace visibles los grupos que hoy existen pero no se ven.

**6. Que se pueda seguir la fila con el dedo en Planilla y Turnos.**
Ninguna tabla tiene la columna del nombre fija: al deslizarse hasta la columna "Total", **el nombre de la persona ya salió de la pantalla**. En una tabla de pagos, eso es leer una cifra sin saber de quién es. En Turnos, en celular se ven 327 de 700 píxeles y ningún nombre.

**7. Las tablas y las ventanas, para quien no usa el ratón.**
Ninguna de las 20 tablas marca cuál es su encabezado, y en Planilla las 12 columnas de dinero no tienen forma de asociarse a la persona de la fila. Las seis ventanas de la app son recuadros superpuestos sin identidad de ventana: con Tab te sales hacia la tabla de atrás y nada se cierra.

**8. Reemplazar las ventanitas del navegador que piden dinero.**
Quedan 16 diálogos del navegador, y dos de ellos piden **un monto en soles y una fecha escritos a mano en texto libre**, en la pantalla que alimenta el pago. Un formulario propio con campo de número y calendario, y el resumen "se le descontarán S/ X con fecha DD/MM/AAAA" antes de confirmar.

---

## 5. LO QUE NO HAY QUE TOCAR

Esto está bien decidido. Lo nombro para que nadie lo "mejore" dentro de seis meses:

- **El terminal marca sin PIN.** Es una decisión tomada, con su razón escrita: marcar tiene que ser instantáneo y el control real es que la Mac mini está a la vista de todo el equipo. No se reabre.
- **La confirmación del terminal a los 3 segundos no se elimina.** Se puede subir a 6-8 y hacer que se pause al tocar la pantalla, pero la idea de que confirme sola y siga es correcta.
- **Tinta sobre crema, y el rojo como acento.** 15.36:1 y 4.83:1: ya pasan de sobra. Ningún ajuste de contraste debe tocarlos.
- **"La línea fina es el único elemento decorativo", sin sombras y sin gradientes.** Es lo que hace que esta app no parezca un panel genérico. Si alguien propone sombras para "separar las tarjetas", la respuesta es papel sobre crema, que es como el sistema declara que se eleva.
- **Que los formularios grandes bloqueen su botón mientras guardan** (Planilla, Equipo, Ausencias, Horarios, Feriados, Incidencias, Datos personales). Es la parte sana del código.
- **Que Datos personales se niegue a guardar si la carga falló** — tiene un comentario que explica el borrado real que eso causó antes. No optimizar eso.
- **El guardado por tramos de salario** y **los textos de ayuda por campo**: de lo mejor que hay en la app.
- **Que el nivel de un documento disciplinario lo decida la base de datos y no la pantalla.** Es lo que sostiene la promesa de "avisar, nunca sancionar solo". Ninguna mejora de interfaz debe mover esa decisión al navegador.
- **Que el zoom no esté bloqueado en celular.** Está bien y es raro; no lo bloquee nadie "para que se vea más como app".
- **Lo que se hizo hoy:** el componente de carga único, los estados vacíos con pista, los errores traducidos y los desplegables con nombre de sede. No rehacerlos al pasar.

---

## 6. EL ORDEN QUE RECOMIENDO

**1. Las dos variables de color: taupe y ámbar** (más el verde de yapa). *Primero porque es media hora de trabajo que cambia unos 500 sitios a la vez, y porque todo lo que se haga después se va a mirar sobre esa base — no tiene sentido pulir botones sobre un texto que no se lee.*

**2. Sacar el ámbar de su propio fondo** en los avisos de planilla, costos, provisiones y en el badge "sin enviar" del terminal. *Va inmediatamente después porque el paso 1 solo no alcanza para esos casos, y son las frases que evitan pagar mal.*

**3. Revisar a ojo cuatro pantallas: Planilla, Dashboard, el terminal y Disciplina.** *Porque el taupe también dibuja bordes en 15 sitios y ahí se va a ver más marcado. Es la verificación, no un extra.*

**4. Los silencios y las confirmaciones que faltan:** el error detrás de la ventana, el checkbox de Objetivos, Turnos, Cuentas, las cuatro acciones que devuelven plata sin preguntar, y la línea del Exportar en hora de Lima. *Antes que cualquier refactor, porque son los únicos de esta lista que hoy pueden hacer que alguien cobre mal.*

**5. La tanda completa de minutos** (sección 3). *Junta, en una sola sesión: son diecisiete cosas de dos minutos cada una y se sienten como una app distinta.*

**6. `lib/formato.ts` — un solo formato de horas, un solo "hoy en Lima", un solo formato de soles.** *Va antes que los componentes porque es el que hoy produce una contradicción visible entre dos pantallas, y porque todo lo demás va a querer llamarlo.*

**7. `boton.tsx` y `aviso.tsx`.** *Este es el momento de cambiar el terreno: primero se vuelve fácil el cambio, después se cambia. Con el componente de botón hecho, el borde invisible del secundario, los 60 rojos de Equipo, las áreas de toque diminutas y las 24 geometrías se arreglan en un solo lugar en vez de en 186.*

**8. Los formularios de verdad, las ventanas con Escape y la protección de lo tecleado.**

**9. El menú al layout y el panel agrupado en todos los anchos.**

**10. La columna de nombre fija en Planilla y Turnos, y las tablas con encabezado declarado.** *Al final porque son las que más código tocan y las que menos gente sufre a diario.*

---

## OBJECIÓN AL ENCARGO

La lista de hallazgos mezcla dos problemas de naturaleza distinta y eso hace daño al orden de trabajo: **el contraste se arregla con dos variables y media hora**, mientras que **el silencio funcional se arregla pantalla por pantalla, a mano, durante una semana**. Tratarlos como una sola cola ordenada "por gravedad" haría que lo barato quede detrás de lo caro y que durante días no se note nada. Por eso el orden de arriba pone las dos variables primero aunque el checkbox de Objetivos sea, tomado uno contra uno, el hallazgo más caro de todos.

## LO QUE NADIE PIDIÓ Y ES LO QUE MÁS IMPORTA

**Nada impide que esto vuelva a pasar.** Hoy no hay ninguna comprobación automática que detenga un color nuevo por debajo de 4.5:1, ni un botón nuevo que no avise cuando falla. El sistema visual está escrito en un comentario dentro de `globals.css` — y un comentario no detiene a nadie. Ya existe la red de seguridad correcta: el enganche que corre antes de subir a GitHub, que hoy verifica tipos y pruebas de interfaz en unos 10 segundos. **Agregarle una prueba que calcule el contraste de los pares declarados en la paleta cuesta media hora y cierra esta puerta para siempre.** Sin eso, esta auditoría hay que volver a pagarla dentro de un año.