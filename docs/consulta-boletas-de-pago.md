# Consulta sobre las boletas de pago oficiales — laboralista y contador

> Son **preguntas**, no cambios: ninguna modifica cómo funciona el sistema hasta que
> respondan. Igual que en `disciplina-tardanzas-faltas/10-consulta-al-laboralista.md`,
> **ninguna norma se cita de memoria**: donde hace falta, la pregunta pide **verificar**
> cuál es la norma y qué exige. Las de la primera parte son para el laboralista; las de la
> segunda, para el contador.

## Qué es lo que hicimos (el contexto para ambos)

Desde el 2026-09-19 el sistema entrega la **boleta oficial** —la que emite el contador,
en PDF o en foto— de forma electrónica:

1. Desarrollo Organizacional (DO) sube el archivo de cada persona y periodo, lo revisa y
   pulsa «Publicar». Solo se publica cuando el pago de ese grupo ya está registrado como
   pagado.
2. La persona la ve en su cuenta (entra con usuario y clave), la abre, la guarda y puede
   pulsar «Confirmar que la recibí». Solo puede confirmar después de abrirla.
3. Quedan escritos, por boleta: cuándo se publicó y quién, cuándo la abrió la persona por
   primera vez y cuándo confirmó. La marca de «abierta» prueba que se pidieron los
   archivos, no que se leyeron.
4. Los archivos no se editan ni se borran. Si DO corrige una boleta ya publicada, se crea
   una versión nueva y se avisa a la persona; la constancia de lo que confirmó de la
   versión anterior se conserva.
5. Si una persona no tiene cuenta, DO la marca «entregada en papel» con la fecha.
6. Los archivos están en un almacén privado (Supabase Storage). Ninguna persona ve la
   boleta de otra.
7. **No** es la boleta calculada por el sistema (la que se ve en «Lo mío» para el periodo
   en curso). Esa es un estimado; la oficial es la del contador.

## Primera parte — para el laboralista

**1. ¿Cuál es la norma y qué plazo fija?** Verificar cuál es la norma que regula la
entrega de la boleta de pago y **en cuánto tiempo** hay que entregarla, contado desde
qué fecha (¿la del pago, la del fin del periodo?). Hoy el sistema no compara la fecha de
publicación con la del pago; si hay plazo, quisiéramos mostrarlo a DO en pantalla.

**2. ¿Sirve la entrega electrónica con confirmación?** ¿Es válido entregar la boleta solo
por vía electrónica, con la confirmación de la persona como constancia? ¿Hace falta un
consentimiento previo y por escrito para esa vía? Si hace falta, ¿cómo debe constar?

**3. ¿Qué debe tener la constancia?** Nuestra constancia es: fecha y hora de publicación,
de primera apertura y de confirmación, la versión del documento, y la cuenta de la persona
(usuario y clave). ¿Alcanza como prueba de entrega ante una inspección? ¿Falta algo?

**4. ¿Por cuánto tiempo se conserva, y en qué forma?** Verificar cuántos años debe
conservar la empresa la boleta y su constancia de entrega, y si basta el archivo digital
(sin copia en papel). Y, al vencer ese plazo, ¿qué se hace con esos datos personales
(sueldos, descuentos, aportes)?

**5. Boleta corregida.** Cuando el contador corrige una boleta ya entregada, hoy DO sube
una versión nueva y se avisa a la persona, y la constancia de la versión anterior se
conserva. ¿Es suficiente? ¿Debe entregarse formalmente como «boleta rectificada», y
dentro de qué plazo?

**6. Quien ya cesó.** ¿Hasta cuándo tiene derecho a acceder a sus boletas o a pedir
copias? Hoy su acceso depende de que su cuenta siga activa.

**7. Quien no tiene cuenta.** Para el papel, DO registra «entregada en papel» con la
fecha. ¿Debe firmar la persona un cargo, o basta el registro de DO?

**8. Una entrega equivocada.** Si DO publica por error la boleta de una persona a otra,
el archivo no puede borrarse desde el sistema (solo anularse: la persona deja de verlo).
¿Qué obligación de aviso o de remediación tiene la empresa por datos personales? ¿El
diseño de «no se borra nada» es un problema en ese caso?

## Segunda parte — para el contador

**A. ¿Cómo las entrega?** ¿Un solo PDF con todas las boletas del mes, un PDF por persona,
o desde otro programa? ¿Con qué frecuencia y en qué día respecto del cierre del periodo?
(Hoy DO sube persona por persona; si llega un solo PDF con todas, se puede construir una
carga por lote.)

**B. ¿Cuándo las tiene listas?** Necesitamos saber cuántos días después del pago están
disponibles, para poder entregarlas dentro del plazo legal (pregunta 1).

**C. ¿Puede darnos el neto de cada boleta en una lista?** Un CSV con persona y neto
pagado, aparte de los PDF. Serviría para cruzar automáticamente contra lo que calculó el
sistema y avisar a DO si difiere. Hoy nada compara las dos cosas.

**D. ¿Nos avisa cuando corrige una boleta ya entregada?** Y, si la corrige, ¿cambia el
neto pagado o solo el papel?

**E. ¿Qué datos lleva siempre la boleta?** Para revisar que cada archivo esté completo
antes de publicarlo (empleador, periodo, remuneraciones, descuentos, aportes).

## Qué haremos con las respuestas

- Plazo (1) o conservación (4): se muestra en la pantalla de DO y se añade a la guía de
  respaldo (`docs/prueba-restauracion-backup.md`).
- Entrega electrónica (2) o constancia (3): se ajusta el texto y lo que guarda la
  confirmación.
- Boleta corregida (5): se ajusta el aviso y el rótulo de la versión nueva.
- Cesados (6): se decide qué acceso conservan.
- Entrega equivocada (8): se decide si hace falta un procedimiento de emergencia.
- Contador A y C: se decide si vale la pena la carga por lote y el cruce con el neto.

Hasta que respondan, **no se ha cambiado nada** del funcionamiento.
