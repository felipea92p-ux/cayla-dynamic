# Catálogo de ataques de /chaos

Cada ataque: `id` · capa · si escribe · qué se hace → qué se espera. Con **★** es del núcleo: corre siempre que su ingrediente esté.

## Entradas hostiles (`entrada`)

- **ENT-01★** · navegador · escribe · Monto con coma de miles («1,299.50»), negativo, con letras, cero, enorme → se rechaza o se guarda exacto, nunca truncado.
- **ENT-02★** · navegador · escribe · Texto de 5000 letras, solo espacios, emoji, `<b>`, comillas → se rechaza o se muestra escapado.
- **ENT-03** · navegador · escribe · DNI con 7 u 11 dígitos, con letras → mensaje claro.
- **ENT-04** · navegador · escribe · Foto de 30 MB, un PDF renombrado a `.jpg`, un archivo vacío → se rechaza antes de subir.
- **ENT-05** · navegador · no · Campo obligatorio solo con espacios → no pasa la validación.

## Doble clic (`doble-clic`)

- **DC-01★** · navegador · escribe · Doble clic en el botón que guarda → una sola fila.
- **DC-02★** · navegador · escribe · Ráfaga de 5 clics en el mismo tick (`for … click()`) → una sola fila.
- **DC-03★** · ambas · escribe · En el terminal, dos toques seguidos sobre la misma persona → una sola marca (`client_uuid`); revisa INV-05.
- **DC-04** · navegador · escribe · Enter dos veces en un formulario → una sola fila.
- **DC-05** · navegador · escribe · Doble clic en aprobar, firmar o pagar → una sola transición.

## Navegación torcida (`navegacion`)

- **NAV-01★** · navegador · no · Atrás del navegador después de guardar → no se repite el envío.
- **NAV-02★** · navegador · no · Recargar con un modal abierto o a mitad de un paso → se recupera sin pantalla en blanco.
- **NAV-03** · navegador · no · Abrir directo una URL con `[id]` inexistente → «no encontrado» cuidado.
- **NAV-04** · navegador · no · Un parámetro de periodo o fecha inválido en la URL → valor por defecto o aviso.
- **NAV-05** · navegador · escribe · Cerrar el modal a mitad del guardado → o se guardó todo o nada.

## Concurrencia (`concurrencia`)

- **CON-01★** · base · escribe · Dos sesiones aprueban la misma solicitud a la vez → gana una; la otra recibe un error claro.
- **CON-02★** · base · escribe · Dos sesiones corrigen la misma marca → el rastro queda completo.
- **CON-03** · base · escribe · Registrar un movimiento mientras otra sesión paga el periodo → no entra a una foto ya congelada; revisa INV-06.
- **CON-04** · base · escribe · Marcaje offline que llega tarde mientras se corrige ese día → la jornada se recalcula bien; revisa INV-01.

## Permisos (`permisos`)

Sus hallazgos van solo al chat.

- **PER-01★** · navegador · no · `integrante@dynamic.local` abre una ruta `/admin` → la saca o le niega.
- **PER-02★** · navegador · no · `lider@dynamic.local` abre el detalle de una persona de otra sede → no ve lo ajeno.
- **PER-03★** · base · no · Llamar la RPC con la sesión de una integrante → la función rechaza, no solo la pantalla.
- **PER-04** · navegador · no · Una integrante pide por URL la boleta o el contrato de otra → negado.
- **PER-05** · navegador · no · `de.baja@dynamic.local` intenta entrar → rechazada.

## Red y sesión (`red`)

- **RED-01★** · navegador · no · `fetch` falla al guardar → mensaje humano y lo escrito se conserva.
- **RED-02★** · navegador · escribe · La respuesta se pierde pero el servidor guardó → reintentar no duplica.
- **RED-03** · navegador · no · `fetch` tarda 8 segundos → hay espera visible y el botón no se puede repetir.
- **RED-04** · navegador · no · La sesión vence a mitad del formulario → pide entrar sin perder lo escrito.
- **RED-05** · ambas · escribe · Terminal sin internet: marcar y volver → la marca llega una vez, con su hora real.

## Celular (`celular`)

- **CEL-01★** · navegador · no · 375 px en «Lo mío»: la acción principal al alcance y nada se corta.
- **CEL-02** · navegador · no · Un modal más alto que la pantalla → hay scroll y el botón se alcanza.
- **CEL-03** · navegador · no · Un campo de fecha en Safari → lo que se muestra es lo que se manda.

## Teclado (`teclado`)

- **TEC-01★** · navegador · no · Tab recorre todo en orden y se ve el foco.
- **TEC-02** · navegador · no · Esc cierra el modal y el foco vuelve a quien lo abrió.
- **TEC-03** · navegador · no · ⌘K y `?` no roban lo que se escribe en un campo.

## Fechas (`fechas`)

Propia de Dynamic: el corte del día decide a qué fecha se le paga una marca.

- **FEC-01★** · ambas · escribe · Marca a las 23:59 y a las 00:01 de Lima → cae en la jornada correcta.
- **FEC-02★** · ambas · escribe · El borde del periodo: 28 y 29 del mes → cae en el periodo correcto; el periodo no es el mes calendario.
- **FEC-03** · base · no · Domingo en TRU → no se trata como descanso.
- **FEC-04** · base · no · Feriado que cae en un día de descanso → no genera falta ni pago de más.
- **FEC-05** · navegador · no · Salida pasada la medianoche → se paga al día que empezó.
- **FEC-06** · navegador · no · Un rango con el fin antes del inicio → se rechaza.
