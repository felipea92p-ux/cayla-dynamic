# Política salarial en el teléfono: auditoría y recorrido · 2026-11-05

> Informe fechado (ver `criterio-auditoria-pantallas.md`, pregunta 8: «Mobile
> primero»). Tiene tres partes: lo que ya se midió, la guía para recorrer cada
> vista en un teléfono real y el registro de lo que aparezca. El registro lo
> llena la sesión que guía el recorrido.

**Módulos cubiertos:** las cinco vistas de Política salarial y el camino por el
que una integrante llega a ellas desde «Lo mío». El mismo método sirve después
para el resto del panel.

---

## 1 · Cómo se midió y qué no cubre

El panel corrió en esta Mac contra un simulador de la API, a 375 px y a 320 px de
ancho. El cuadro y el documento son los que salen de aplicar 573 migraciones a un
Postgres desechable (la 0597 falló por una columna de `auth.users` que ese banco
no tiene; no toca la política). Las personas son inventadas y producción no se
tocó, así que un texto editado allá puede medir distinto.

**Esto no es un teléfono.** La medición usa Chromium con un ancho impuesto:
sirve para medir desbordes, columnas y tamaños, pero no para el zoom de Safari,
el teclado, los selectores nativos, la impresión ni el pulgar. Por eso hace falta
el recorrido de la parte 3. El simulador de iOS tampoco sirve hoy: esta Mac tiene
Xcode, pero ningún sistema iOS instalado.

---

## 2 · Lo que ya se sabe

### Corregido en la rama (sin publicar)

| # | Antes | Ahora, medido |
|---|---|---|
| H1 | Columna de 141 px (86 a 320). La página se salía 115 px (171 a 320). 52.6 pantallas con todo abierto. | Columna de 343 px (288 a 320). La página no se sale. 21.7 pantallas (31.7 a 320). |
| H2 | Campo de x=235 a x=491. | Campo y botón de x=33 a x=342 (a x=287 en 320). |
| H3 | «Al 04 de noviembre de 2026». | «Al 05 de noviembre de 2026». Normas usa la misma función, con prueba. |
| H4 | Dos cajas sin nombre. | «Tu categoría: Cayla» y «Siguiente: Support» en cada caja; en escritorio, encabezan la columna. |
| H5 | El enlace salía a todo el equipo y llevaba a un error. | Solo lo ve quien puede abrir la hoja. |
| H12 | La sección se detenía a 24 px, debajo de la barra de 64. | Se detiene a 80 px. El índice de escritorio tenía el mismo defecto y también pasó de 24 a 80. |
| H13 | Cinco selectores de 14 px. | 16 px en el celular y 14 desde `sm`. |

Comprobado también en escritorio (1280 px): índice a la izquierda, constancia en
una sola fila y sin desborde. Pruebas: 3 220 en verde, con las nuevas de
`fechaLargaLima`, y typecheck en verde.

**Un hallazgo más al corregir H1:** el PDF tenía el mismo defecto. Una hoja A4 mide
unos 688 px, menos que `lg`, así que el selector salía al lado del documento. Con
las reglas de impresión activadas en pantalla, la columna pasa de 504 a 688 px y el
selector desaparece. Es una simulación: el papel real se mira en P30.

**Sin comprobar:** nada de esto se ha visto en un teléfono real ni en un PDF real.

### Lo que sigue abierto

Las tablas de abajo conservan los siete corregidos como referencia de qué se midió
antes del arreglo. Orden: primero lo que deja a alguien sin hacer algo o lo lleva a
entender otra cosa. «Medido» salió del navegador a 375 px salvo que se indique otro
ancho; «leído» salió solo del código y falta verlo funcionar.

### Bloquea

| # | Vista | Qué pasa | Evidencia | Dónde |
|---|---|---|---|---|
| H1 | Documento vigente | El selector «Ir a una sección…» ocupa una columna al lado del documento en vez de ir encima. El documento queda en una tira angosta y toda la página se arrastra de lado. Pasa desde el rediseño del 2026-09-15. | Medido. Columna de 141 de 375 px (86 de 320). La página se sale 115 px (171 a 320). Con todo abierto mide 52.6 pantallas. | `politica-salarial/page.tsx:534` |
| H2 | Documento vigente | El campo para dejar constancia se sale de la pantalla. Es el acto que la ley pide acreditar y una integrante lo hace desde el celular. Es consecuencia de H1 más el ancho mínimo fijo del campo. | Medido. El campo va de x=235 a x=491 en una pantalla de 375. Apilando la columna, va de 33 a 289. | `page.tsx:616` |

Medido al apilar la columna solo en el navegador: la columna sube de 141 a 343 px,
el desborde baja de 115 a 0 y el largo baja de 52.6 a 21.4 pantallas. De las 8
tablas o franjas con desplazamiento lateral quedan 3. Un solo defecto explica la
mayor parte de lo que se ve fatal en esta vista.

### Confunde o dice algo falso

| # | Vista | Qué pasa | Evidencia | Dónde |
|---|---|---|---|---|
| H3 | Constancias | **La hoja dice la fecha de corte con un día de atraso.** Hoy, jueves 5, imprime «Al 04 de noviembre de 2026». Una constancia dejada hoy aparece en un papel fechado ayer. Está así desde que existe la hoja (2026-08-18). La hoja hermana de Normas lo hace bien. | Medido en pantalla y reproducido con el mismo cálculo. | `constancias/page.tsx:114` y `:391`; correcta en `normas/[id]/constancias/page.tsx:111` |
| H4 | Documento vigente | «Ver diferencias» y «Comparar dos categorías» apilan dos cajas sin decir cuál es de qué categoría. En escritorio tampoco hay rótulo, pero la columna lo sugiere; en el teléfono no queda ninguna pista. Quien mira puede creer que el nivel de la categoría siguiente es el suyo. | Medido. | `page.tsx:215` y `:322` |
| H5 | Documento vigente | «ver constancias» se le muestra a todo el mundo, pero solo funciona para administración y Líder DO. La integrante y la líder de equipo llegan a «Solo un administrador o lider puede ver quien acuso la politica.», sin tildes. | Medido con el simulador, que copia el permiso de la 0551. | `page.tsx:487` |
| H6 | Documento vigente, Versiones, Categorías | Un error al guardar se pinta arriba de la página. Con el botón muy abajo, o con una ventana abierta encima, la persona aprieta y no ve nada. Si dejar constancia falla sin señal en una tienda, parece que no pasó nada. | Leído. | `page.tsx:512`, `versiones/page.tsx:165` y `:209`, `categorias/page.tsx:111` y `:139` |
| H7 | Constancias, Documento vigente, Versión | El mismo acto, `window.print()`, tiene tres nombres: «Imprimir», «Imprimir / Guardar como PDF» y «Descargar PDF». Y Constancias dice «elige “Guardar como PDF” en el destino de impresión», una opción que puede no existir en un teléfono. | Leído. Falta verlo en teléfono: parada P33. | `constancias/page.tsx:350`, `page.tsx:478`, `versiones/[version]/page.tsx:89` |

### Estorba

| # | Vista | Qué pasa | Evidencia | Dónde |
|---|---|---|---|---|
| H8 | Documento vigente, Versión | La tabla de 7 columnas mide 804 px y se ven 299: el 63 % queda oculto. Al deslizarla se pierde el nombre del criterio, y al bajar se pierde el de la categoría. | Medido. | `page.tsx:177`, `_documento-vista.tsx:23` |
| H9 | Constancias | La tabla no tiene contención, así que empuja toda la página: 2 px a 375, 56 px a 320. Hay columnas de 19, 56 y 65 px y filas de hasta 136 px. | Medido. | `constancias/page.tsx:407` y `:313` |
| H10 | Versiones | Historial mide 548 px y se ven 341. «Ver», la única acción de cada fila, queda fuera de vista y nada lo anuncia. La fecha ocupa tres líneas. | Medido. | `versiones/page.tsx:253` y `:264` |
| H11 | Todas las de DO | Las pestañas miden 573 px en una pantalla de 375, con la barra oculta. «Categorías» y «Constancias» no se ven, y al entrar a Constancias la pestaña activa queda fuera de vista. | Medido. | `_subnav.tsx:17`, `components/ui/pestanas.tsx:38` (compartida con otras pantallas) |
| H12 | Documento vigente | Al saltar a una sección, el título queda tapado: se detiene a 24 px del borde y la barra superior mide 64. | Medido. | `page.tsx:131` |
| H13 | Documento vigente, Versiones, Constancias | Cinco selectores tienen letra de 14 px; `Campo` ya resuelve este caso con 16 px. Safari agranda la página al tocar un control con letra menor a 16 px y no la devuelve sola. | Medido el tamaño. El zoom falta verlo: paradas P18, P32 y P42. | `page.tsx:205` y `:209`, `versiones/page.tsx:278` y `:282`, `constancias/page.tsx:319` |
| H14 | Varias | Áreas de toque por debajo del mínimo de 24 px: «ver constancias» 20, «Ver diferencias» 20, «Ver» 19. Los chips de «Las categorías» son `py-1 text-xs`. | Medido, salvo los chips. | `page.tsx:487`, `:311` y `:263`, `versiones/page.tsx:264` |
| H15 | Categorías | La ventana de edición mide 1 044 px y se ven 731. «Guardar» y «Cancelar» quedan al final, no hay botón de cerrar, y un toque en el margen de 16 px cierra y pierde lo escrito sin avisar. | Medido el tamaño. La pérdida está leída: parada P50. | `components/ui/modal.tsx:111`, `categorias/page.tsx:163` |

### Se ve mal

| # | Vista | Qué pasa | Evidencia | Dónde |
|---|---|---|---|---|
| H16 | Constancias | Usa `p-6` fijo cuando el resto usa `p-4 pt-6 sm:p-6`. Por eso la línea de las pestañas queda corta a los dos lados y la vista tiene menos ancho útil. | Medido. | `constancias/page.tsx:313` |
| H17 | Versión | El documento congelado usa otros títulos que el vigente, sin serif, y `p-6` fijo. Mide 23.7 pantallas sin índice. | Medido. Que no tenga widgets es decisión escrita; que no tenga índice en el teléfono hay que discutirlo. | `_documento-vista.tsx:36` |

### Estados que no hace falta forzar en producción

Medidos con el simulador: cuadro desactualizado y escala fuera de orden, los dos a
la vez, y la ventana de publicar. Los avisos miden 134 y 154 px y no agregan
desborde propio. La ventana cabe entera (302 px, botones dentro). Con los dos
avisos, DO recorre una pantalla entera antes de llegar al documento.

**Sin medir:** «todavía no hay versión publicada» y «una sola versión». Tampoco se
comprobó si alguno de los dos ocurre hoy en producción.

---

## 3 · El recorrido

### Decisión

```
DECIDÍ:     recorrer en el teléfono después de corregir el lote de raíz (H1 a H5,
            H12 y H13), sobre una vista previa de esa rama.
DESCARTÉ:   recorrer producción tal como está, porque 21 de las 55 paradas
            reportarían H1 y taparían lo que hay debajo. Tampoco un banco local
            con datos inventados en el teléfono: necesita abrir la Mac a la red,
            el permiso automático bloqueó ese paso y quedó sin comprobar. Abrirlo
            es decisión de Felipe.
SE ROMPE SI: la vista previa pide iniciar sesión en Vercel en el teléfono, o si
            alguien confunde su botón «Publicar» con uno de ensayo. Vercel tiene
            variables de Supabase propias para Preview y su listado no dice a qué
            base apuntan: se trata como producción hasta confirmarlo.
```

### Qué se arregla antes y qué después

- **Antes del recorrido:** H1 a H5, H12 y H13. Cada uno es un cambio chico y su
  solución no depende de cómo se sienta en la mano.
- **Después, con lo que diga el teléfono:** H8, H9, H10 y H11. Tablas y pestañas
  piden elegir una forma (deslizar con columna fija, tarjetas, nombres más cortos),
  y esa elección se hace mejor habiéndolas usado. H11 además toca un componente
  compartido con otras pantallas.
- **H3 también se revisa hacia atrás:** toda hoja impresa desde el 2026-08-18 lleva
  la fecha de corte un día antes de la fecha en que se imprimió.

### Antes de arrancar: dos minutos en producción

Abrir Documento vigente en el teléfono y confirmar que se ve la tira angosta de
H1. Sirve para validar que la medición emulada coincide con el teléfono real.

### Dónde se recorre

Vista previa de la rama, generada el 2026-11-05:
<https://cayla-dynamic-5rritdbx4-cayla.vercel.app/admin/politica-salarial>

- **Pide dos inicios de sesión la primera vez.** Primero Vercel: la dirección
  responde con una redirección a `vercel.com/sso-api`. Después Dynamic, porque la
  sesión no se comparte con producción.
- **A qué base apunta sigue sin confirmar.** La protección impide leer sus archivos
  desde aquí, y `vercel curl` no se usó porque promete saltarse la protección
  automáticamente, sin decir qué cambia en el proyecto. Se contesta en P01 y, hasta
  entonces, se trata como producción.
- **Si la rama cambia, la dirección cambia.** La sesión da la nueva.

### Cómo funciona

- **Guía la sesión.** Da una parada a la vez: adónde ir, qué hacer y qué mirar.
- **Se contesta corto.** `ok`, o lo que se vio, con captura si ayuda.
- **Nada se arregla a mitad de un tramo**, salvo que algo impida seguir.
- **Lo que aparezca fuera del guion también vale.** Se anota en la parada más
  cercana.
- **Se puede parar al final de cualquier tramo.** El registro dice dónde se quedó.
- **Tiempo:** unos 50 minutos en total. Cada tramo toma entre 2 y 15.

### Botones que no se aprietan

| Botón | Vista | Qué haría en la base real |
|---|---|---|
| «Publicar versión nueva», «Confirmar de todas formas» | Versiones | Si el contenido cambió, crea una versión y vuelve a pedir la constancia a toda la población obligada. Abrir la ventana no escribe nada: se mira y se aprieta **Cancelar**. |
| «Guardar» | Categorías | Cambia el cuadro real. Si el contenido cambió, la política aparece «Desactualizada» para todo el equipo. Se mira y se aprieta **Cancelar**. |
| «Dejar constancia» | Documento vigente | Registra un acuse legal a nombre de quien aprieta. Solo si de verdad corresponde dejarla. |

«Imprimir» es seguro: se cancela o se guarda el PDF en el teléfono.

### Datos personales

- Constancias muestra DNI y nombres completos.
- Categorías muestra «Sueldos reales hoy», y con una sola persona en la categoría
  ese rango es su sueldo.
- De esas dos vistas, las capturas van recortadas o se describe lo que se ve.
- En este archivo no entran nombres, DNI ni sueldos: se commitea.

### Severidad

| Nivel | Criterio |
|---|---|
| Bloquea | No se puede terminar o no se puede leer. |
| Confunde | Se puede, pero lleva a entender otra cosa. |
| Estorba | Se puede, con esfuerzo. |
| Se ve mal | Funciona; le falta cuidado. |

### Quién mira

`criterio-auditoria-pantallas.md` pide dos pasadas: con la cuenta de rango más
bajo y con la más alta. El sistema no tiene «ver como», y **no se crea una cuenta
de prueba en producción**: una persona de planilla inventada entra al total de la
hoja de constancias y aparece como pendiente.

El tramo 1 se hace con una integrante real que todavía no haya dejado constancia,
mirando cómo lo resuelve sin explicarle nada. Si la deja, es un acto válido que
de todas formas le corresponde. Si no hay nadie disponible, ese tramo queda
cubierto solo por la medición emulada, y se anota así.

Y una advertencia: un solo teléfono no es la población. Conviene repetir los
tramos 1 y 4 en el teléfono más barato y más angosto que use alguien de sede.

---

## 4 · Las paradas

Las marcadas con `H` traen un defecto ya medido: ahí se comprueba si sigue, no se
descubre. Las marcadas con ☎ solo se pueden contestar en un teléfono real.

### Tramo 0 · Preparar (2 min)

| # | Qué hacer | Qué mirar |
|---|---|---|
| P00 | Decir modelo, sistema y navegador. | De ahí sale el ancho real de la pantalla. |
| P01 | Entrar a la vista previa con la cuenta de siempre. | Rol de la cuenta y tema (claro u oscuro). ¿La versión y las constancias son las reales? Eso dice a qué base apunta. |

### Tramo 1 · El camino de la integrante (5 min, con una integrante real)

| # | Qué hacer | Qué mirar |
|---|---|---|
| P02 | Entrar a «Lo mío» y tocar el aviso de constancia pendiente. ☎ | ¿Se entiende adónde lleva? ¿Hay forma de volver? |
| P03 | Leer «Tu categoría» y tocar «Ver diferencias». H4 | ¿Sabe cuál caja es la suya? |
| P04 | Bajar hasta la constancia sin ayuda. H2 ☎ | ¿La encuentra? ¿Cuánto tuvo que bajar? ¿Se ve el campo entero? |
| P05 | Escribir su nombre y dejar constancia. ☎ | ¿El teclado tapa el campo o el botón? ¿Queda claro que se registró? ¿Y si falla? H6 |
| P06 | Tocar «ver constancias». H5 | ¿Qué entiende con ese mensaje? |

### Tramo 2 · Documento vigente, la parte de arriba (5 min)

| # | Qué hacer | Qué mirar |
|---|---|---|
| P07 | Mirar la cabecera. | Título, descripción y botón de imprimir: ¿cabe y se lee? |
| P08 | Mirar las pestañas sin tocarlas. H11 ☎ | ¿Se nota que hay cuatro? |
| P09 | Mirar la línea de versión. H14 | ¿Se entiende? ¿«ver constancias» se toca al primer intento? |
| P10 | Buscar «movilidad» y tocar un resultado. H12 ☎ | ¿El teclado estorba? ¿Se abre la sección? ¿Su título se ve? |
| P11 | Usar «Ir a una sección…». H1 H12 ☎ | ¿El selector nativo muestra los títulos largos? ¿Dónde aterriza? |
| P12 | Mirar la cabecera del documento. H1 | ¿Título y RUC se leen a buen ancho? |
| P13 | Mirar «Tu categoría», si la cuenta tiene una. H4 | Igual que P03. |

### Tramo 3 · Documento vigente, sección por sección (15 min)

Se abre cada sección, se lee lo primero y se mira cada tabla entera.

| # | Sección | Qué mirar |
|---|---|---|
| P14 | Para qué sirve este documento | Ancho de lectura y tamaño de letra. |
| P15 | Los seis criterios | Tabla de 2 columnas: ¿se lee sin deslizar? |
| P16 | Cómo se aplica: tarjetas | ¿Caben los nombres y montos? |
| P17 | Cómo se aplica: tabla. H8 ☎ | ¿Se nota que sigue a la derecha? ¿Deslizar choca con el gesto de volver atrás? ¿Se sabe qué fila es? |
| P18 | Cómo se aplica: comparador. H4 H13 ☎ | ¿La página se agranda al tocar el selector? ¿Se sabe qué caja es de cuál? |
| P19 | Las categorías. H14 ☎ | ¿Los chips se aciertan con el pulgar? Abrir los tres. |
| P20 | Las áreas | Lectura. |
| P21 | Cómo se cambia de categoría | Lectura. |
| P22 | Cómo se evalúa el desempeño | Tabla de 2 columnas. |
| P23 | Igualdad de remuneración | Lectura. |
| P24 | La jornada y cómo se calcula | Tabla de 2 columnas. |
| P25 | Lo que se recibe además | Tablas de 3 y 2 columnas. |
| P26 | Cuánto significa esto al mes. H8 ☎ | Tabla de 5 columnas: ¿se puede comparar monto con categoría? |
| P27 | Lo que CAYLA se compromete a sostener | Lectura. |
| P28 | Vigencia y actualización | Lectura. |
| P29 | Firma y constancia, sin apretar | ¿Qué estado muestra? ¿La firma se ve bien? |
| P30 | «Imprimir / Guardar como PDF». H7 ☎ | ¿Se abre algo? ¿El PDF trae todas las secciones? ¿La tabla de 7 columnas sale entera? |

### Tramo 4 · Constancias (7 min) — capturas recortadas

| # | Qué hacer | Qué mirar |
|---|---|---|
| P31 | Tocar la pestaña Constancias. H11 | ¿Se ve cuál está activa al llegar? |
| P32 | Cambiar de versión y volver. H13 ☎ | ¿Se agranda la página? ¿Se entiende que es histórica? |
| P33 | Leer la instrucción del PDF. H7 ☎ | ¿Existe esa opción en este teléfono? |
| P34 | Leer el resumen. **H3** | ¿La fecha es la de hoy? |
| P35 | Mirar la tabla. H9 ☎ | ¿La página se arrastra de lado? ¿Se leen los nombres? |
| P36 | Buscar a quién falta. | ¿Cuánto hay que bajar? ¿Se entiende el motivo de cada pendiente? |
| P37 | «También dejaron constancia» y la firma de DO. | ¿Se distingue de la lista oficial? |
| P38 | Imprimir. ☎ | **Este papel es la prueba.** ¿Sale la tabla entera, con buena letra y sin lo que es solo de pantalla? |

### Tramo 5 · Versiones y publicación (5 min)

| # | Qué hacer | Qué mirar |
|---|---|---|
| P39 | Mirar la tarjeta «Publicar». | ¿Se entiende qué pasaría? |
| P40 | Abrir la ventana y apretar **Cancelar**. ☎ | ¿Cabe? ¿Se entiende la consecuencia? |
| P41 | Abrir una versión desde Historial. H10 H14 ☎ | ¿Se descubre «Ver» sin saber que existe? ¿Se acierta? |
| P42 | Comparar dos versiones. H13 ☎ | ¿Se agranda la página? ¿Se lee el resultado? |

### Tramo 6 · Una versión (4 min)

| # | Qué hacer | Qué mirar |
|---|---|---|
| P43 | Abrir la vigente. | Cabecera y botones: ¿caben juntos? |
| P44 | Abrir una histórica. | ¿Se entiende que no es la vigente? ¿Se leen las notas? |
| P45 | Recorrer el documento. H8 H17 ☎ | ¿Se puede llegar a una sección sin índice? |
| P46 | «Descargar PDF». H7 ☎ | ¿Hace lo que su nombre dice? |

### Tramo 7 · Categorías (5 min) — capturas recortadas

| # | Qué hacer | Qué mirar |
|---|---|---|
| P47 | Mirar la lista. | ¿Texto y botón «Editar» conviven bien? |
| P48 | Abrir «Editar» y tocar el monto. ☎ | ¿Teclado numérico? ¿Se ve lo que se escribe? |
| P49 | Bajar por los campos con el teclado abierto. H15 ☎ | ¿Se ve el campo activo? ¿Se llega a «Cancelar»? |
| P50 | Escribir algo y tocar el margen. H15 ☎ | ¿Se cierra y se pierde sin avisar? Reabrir y **Cancelar**. |

### Tramo 8 · Condiciones (5 min)

Se repite solo en Documento vigente, Constancias y Categorías.

| # | Condición | Qué mirar |
|---|---|---|
| P51 | Modo oscuro ☎ | Contraste, o un parche que se quede claro. |
| P52 | Teléfono en horizontal ☎ | Barra superior, tablas y ventanas. |
| P53 | Letra más grande del navegador ☎ | ¿Algo se corta o se monta? |
| P54 | Un Android, si hay uno a mano ☎ | Lo que falló en los tramos 1 y 4. |

---

## 5 · Registro

**Estado:** sin empezar. El lote de raíz ya está en la rama; se recorre sobre su
vista previa.

| Tramo | Paradas | Hechas | Fuera de lo previsto |
|---|---|---|---|
| 0 · Preparar | 2 | 0 | — |
| 1 · Integrante | 5 | 0 | — |
| 2 · Arriba | 7 | 0 | — |
| 3 · Secciones | 17 | 0 | — |
| 4 · Constancias | 8 | 0 | — |
| 5 · Versiones | 4 | 0 | — |
| 6 · Una versión | 4 | 0 | — |
| 7 · Categorías | 4 | 0 | — |
| 8 · Condiciones | 4 | 0 | — |

**Teléfono usado:** iPhone en tema claro; faltan el modelo, el sistema y el navegador
(P00).

**Control en producción:** hecho. El defecto de H1 se reproduce en el teléfono real,
así que la medición en el navegador sirve de guía. La captura no muestra la dirección:
se da por producción porque ahí se pidió abrirla y la columna sigue angosta.

### Lo que se encontró

Solo entra lo que no fue `ok`. Sin nombres, DNI ni sueldos.

| Parada | Severidad | Qué se vio | Hallazgo | Estado |
|---|---|---|---|---|
| Control | Bloquea | El título del documento sale casi palabra por palabra, el RUC se corta y la página se corre de lado hasta dejar fuera el botón del menú. El selector se ve más ancho que en Chromium, así que la columna parece más angosta que los 141 px medidos (estimado por la captura). | H1 | Corregido en la rama; falta verlo en la vista previa |
