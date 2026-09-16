# ADR 0003 — La Bandeja se ordena por urgencia y por dónde se resuelve

Fecha: 2026-09-15. Estado: **implementado en la pantalla**. La decisión 8 (el
contador de Educación) y la 5 (plazo y papel de Educación) quedaron **resueltas y
reemplazadas por la migración 0450** —ver al final de cada una—: no escribir otra
migración para `fn_educacion_por_atender`, revertiría la 0450.
Reemplaza las decisiones 3 («Por aprobar / Para saber») y 7 (filtro de sede) del
[ADR 0002](0002-rediseno-bandeja.md). Las demás del 0002 siguen en pie.

Código: `apps/web/app/(admin)/admin/bandeja/page.tsx`,
`apps/web/lib/admin/bandeja-urgencia.ts` (+ `tests/bandeja-urgencia.test.ts`).

## Lo que encontró la auditoría (medido, no supuesto)

1. **El número de Educación del menú y la Bandeja cuentan cosas distintas.**
   `fn_educacion_por_atender` (0290) cuenta toda asignación con
   `vigente_hasta <= hoy + 30`, y eso incluye para siempre a las ya vencidas con
   los papeles completos. La Bandeja no las cuenta. En producción el
   2026-09-15: menú 17, Bandeja 12.
2. **Una etiqueta de Educación escondía el motivo.** «vencida» solo aparecía si
   además faltaba un papel, pero no lo decía; «vence en 0 días» era el último
   día con pago; «1 mes sin papel» no es un vencimiento.
3. **Las sedes del filtro no estaban escritas a mano**: salían de lo que trajo la
   carga. Una sede sin pendientes (LIM ese día) desaparecía y parecía un olvido.
4. **Pendientes que pueden quedar viejos.** El cese no cierra las asignaciones de
   Educación (0415 solo cierra el salario) y 6 de las 9 RPC no filtran por
   persona activa.
5. **El número del menú no bajaba al resolver** algo dentro de la Bandeja: se
   recalculaba solo al navegar.
6. **Enlaces a la portada**: Documentación ignoraba `?persona=`; Contratos y
   Educación no aceptaban parámetros.

## DECIDÍ

### 1. Pestañas por dónde se resuelve, grupos por urgencia dentro

**DECIDÍ:** «Resolver aquí» (las 3 revisiones, solicitudes de vacaciones y de
perfil) y «En otra pantalla» (Educación, récord de vacaciones, sin horario).
Cada pestaña muestra cuántos vencidos tiene. Dentro: Vencido / Hoy / Próximos /
Sin plazo. Elegida por Felipe sobre una maqueta de cuatro opciones.

**DESCARTÉ:** una sola lista agrupada por urgencia (la recomendación), porque
Felipe prefirió que cada pestaña sea homogénea en su tipo de acción. El costo
—lo vencido de la otra pestaña no se ve— se paga con el conteo en la pestaña.

**SE ROMPE SI:** alguien trabaja solo «Resolver aquí» durante semanas. El conteo
de vencidos en la otra pestaña es la única defensa; no debe quitarse por estética.

### 2. Tres clases de urgencia, y la excepción de las vacaciones

**DECIDÍ:** con fecha límite (Educación, récord), esperando respuesta (vencido
desde el día 8, el umbral del ADR 0002), riesgo corriendo (sin horario →
vencido). Una **solicitud de vacaciones** se mide por su **fecha de inicio**, no
por lo que lleva esperando.

**DESCARTÉ:** medir todas las aprobaciones por antigüedad — una pedida ayer que
empieza hoy quedaba debajo de una que empieza en noviembre.

**SE ROMPE SI:** aparece un tipo nuevo que no encaja en ninguna de las tres; se
agrega su función en `bandeja-urgencia.ts`, no un `if` en la pantalla.

### 3. Sedes desde la tabla, en un desplegable

**DECIDÍ:** las activas de `sedes`, más cualquier sede que tenga pendientes aunque
esté inactiva, con su conteo. Solo para quien ve todas las sedes
(`puedeVerTodasLasSedes`); la encargada no ve filtro.

**DESCARTÉ:** chips (no escalan) y «como hoy» (la sede sin pendientes desaparece).

**SE ROMPE SI:** una RPC devuelve la sede por nombre y no por código: el filtro no
la encontraría. Hoy las nueve devuelven `codigo`.

### 4. Acción según el tipo

**DECIDÍ:** lo que se resuelve aquí se despliega en la fila; lo de afuera lleva un
verbo concreto («Subir papel», «Asignar horario») al lugar más exacto disponible.

### 5. Educación: plazo y papel por separado

**DECIDÍ:** el plazo va en su insignia («Venció hace 6 días», «Vence hoy») y el
papel en la descripción («Falta el papel de 2 meses ya pagados»). Lejos de
vencer, con papel faltante, es «Documento pendiente» en Sin plazo.

**REEMPLAZADA POR LA 0450 (mismo día).** Educación dejó de tener «papeles por
mes»: cada pago a la institución tiene su constancia, que la integrante sube y DO
revisa. En la Bandeja: cada constancia por revisar es un pendiente propio con
enlace a esa entrega (se mide por lo que espera), y el estudio entra por su
constancia vencida (Vencido, desde su plazo), por un pago a la institución en los
próximos días (Hoy / Próximos) o por no tener calendario (Sin plazo). La vigencia
del beneficio ya no genera pendiente: «vence en 0 días» era casi siempre una
renovación normal. Ver `urgenciaEducacion` en `lib/admin/bandeja-urgencia.ts`.

### 6. Quien cesó sigue visible

**DECIDÍ:** insignia «Cesó el …» y baja a Sin plazo. No se esconde una deuda de
papeles; deja de competir con lo urgente.

**SE ROMPE SI:** `fn_personas_funciones` falla: nadie se marca como cesado. Es el
lado seguro (nada baja de urgencia por error), pero conviene saberlo.

### 7. Enlaces por persona y menú que se actualiza

**DECIDÍ:** Educación, Documentación y Contratos leen `?persona=`. Documentación
y Contratos lo escriben en su buscador (visible, se borra con «Limpiar
filtros»); Educación muestra una franja «Mostrando solo…» con «Ver todas». Al
resolver, la Bandeja emite `dynamic:bandeja-cambio` y `nav.tsx` vuelve a contar
Bandeja e Incidencias con las mismas consultas.

### 8. El contador de Educación cuenta lo mismo que la Bandeja (resuelta en la 0450)

**DECIDÍ:** una migración aparte que deja `fn_educacion_por_atender` con el criterio
de la Bandeja. Se escribe **después** de pedir el md5 de producción, y se pega
antes de fusionar.

**HECHO EN LA 0450** (`la_constancia_de_estudios_se_entrega_y_se_revisa`), con el
md5 de producción pedido el 2026-09-15. El contador cuenta constancias por
revisar + constancias vencidas + estudios vigentes sin calendario + avisos de
«ya no voy a pagar». La Bandeja cuenta eso mismo **más** los pagos a la
institución de los próximos días (avisan, pero todavía no piden nada): esa es la
única diferencia, y es a propósito. El criterio compartido vive en
`esEducacionParaSaber` (`lib/admin/bandeja-equipo.ts`) y la prueba 355 compara el
contador contra las listas.

## Rediseño 2 (mismo día): categorías por módulo y cinco fuentes nuevas

Con los datos de producción del 2026-09-15 la Bandeja solo mostraba Educación
(medido en el SQL Editor: 10 de 12 fuentes en cero). No estaba rota: juntaba
pocas fuentes y no decía qué revisaba, así que «Contratos está al día» y
«Contratos no se mira aquí» se veían igual. Felipe eligió sobre una maqueta.

### 9. Una tarjeta por módulo, también en cero

**DECIDÍ:** arriba, una tarjeta por cada módulo que la persona puede ver (el
permiso de la pantalla de ese módulo), con su conteo; en cero dice «Al día».
Un clic filtra. Si una consulta del módulo falló, la tarjeta dice «No se pudo
cargar» y no «Al día». Se quitan las pestañas de la decisión 1: cada fila dice
«se resuelve aquí».

**DESCARTÉ:** lista agrupada por módulo — lo urgente de un módulo quedaba
debajo de lo que no urge de otro.

**SE ROMPE SI:** una fuente nueva se agrega a la lista sin su entrada en
`MODULOS_BANDEJA`: sus filas se pintan, pero no tiene tarjeta ni «Al día».

### 10. Una sola lista para la pantalla, el menú y Equipo

**DECIDÍ:** `lib/admin/bandeja-fuentes.ts` (`traerFuentesBandeja` +
`armarPendientes`). El número del menú y el de Equipo cuentan esa lista.

**DESCARTÉ:** mantener tres copias — ya se habían separado dos veces: el menú
no sumaba liquidaciones vencidas y Equipo contaba Educación con la consulta de
antes de la 0450.

**SE ROMPE SI:** alguien vuelve a pedir una RPC de la Bandeja directo desde una
pantalla o desde `nav.tsx`, en vez de agregarla a `traerFuentesBandeja`.

### 11. Fuentes nuevas y su criterio

Cada una usa el criterio de SU pantalla, con tres excepciones escritas:

| Fuente | Entra | Plazo | Queda fuera, y por qué |
|---|---|---|---|
| Contratos (`fn_contratos_tablero`) | desnaturalizado, vencido, por vencer, sin contrato, sin firmar, trámite pendiente | fin del contrato; trámite pendiente = copia (inicio + 5) — desde la 0469 el MTPE ya no es trámite de nadie (D. Leg. 1246) | `sin_vencimiento`: la pantalla lo cuenta como pendiente y como vigente a la vez |
| Correcciones (`fn_dias_por_revisar`, `fn_marcas_apartadas`) | días con marcas por revisar, marcas apartadas | cierre del periodo que lo paga (`periodos_planilla`) | — (se pide con tope 1000: la RPC corta antes de devolver) |
| Documentación (`fn_documentos_tablero`) | ruta sin firmar o desfasada; bono de este mes o ya pasado | bono: fin de mes | `se_nego` (ya resuelta); bono `sin_fecha` (la pantalla lo deja en «nada que hacer») |
| Feriados (`fn_feriados_laborados`, 120 días atrás) | descanso acordado sin otorgar; descanso que no compensa | feriado + 30 días | feriado trabajado sin descanso registrado: por ley se paga la sobretasa y no pide nada |
| Disciplina (`expediente_disciplinario`) | lo que `etapaDelBorrador` y `pendientesDeEntregado` dicen que falta | descargo: su vencimiento; lo demás, lo que lleva esperando | anulado y cerrado sin entrega |

**SE ROMPE SI:** Disciplina tiene documentos entregados hace años sin cargo
subido: todos entran, porque su propia pantalla también los tiene en «Entregar».
Si eso inunda la Bandeja, la respuesta es subir o anular esos cargos, no
esconderlos aquí.

## Evaluado y descartado sin pregunta

- **Acciones masivas:** ningún caso real; aprobar o rechazar exige motivo por persona.
- **Canales de notificación nuevos:** el despacho de correos ya cubre contratos,
  vacaciones y auto-cierres.
- **Historial de resueltos en la Bandeja:** cada módulo ya guarda quién atendió y cuándo.
