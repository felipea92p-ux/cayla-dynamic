# Auditoría — «Info» / pestaña Resumen de `/mio`

**2026-09-13.** Piloto de [`criterio-auditoria-pantallas.md`](criterio-auditoria-pantallas.md).
Fuente: lectura completa de la cabecera y la sección "Resumen" de
[`apps/web/app/(mio)/mio/page.tsx`](../apps/web/app/(mio)/mio/page.tsx) (el
archivo entero documenta en comentarios su propia historia: el error de
filtrado de 2026-08-12, la boleta reabierta el 2026-08-31 solo para el
periodo vigente, el cambio de pestañas del 2026-09-10), más una captura real
de la cuenta de Felipe Alvarez (Gerente General, Central, 5 meses de
antigüedad) provista al empezar esta conversación.

**Limitación honesta:** no se pudo tomar una captura real de una cuenta
`integrante` de sede. El Postgres local está arriba, pero el resto de la
pila (`auth`, `kong`, `rest`) no arrancó — otro proyecto en esta misma Mac
(`cayla-retail`) ya ocupa los puertos por defecto de Supabase, y cambiar
`supabase/config.toml` para liberarlos afectaría a los demás worktrees de
este repo, no solo a esta sesión. Lo de abajo sobre la cuenta `integrante`
sale de leer el código (los cuatro registros de prueba que ya viven en la
base local, todos `estado = inactivo` y sin `auth_user_id`, tampoco servían
para una captura real de alguien activo). Marcado con 🔶 donde el hallazgo es
deducido y no visto.

## Lo que ya funciona bien — no tocar sin razón

- **El mobile-first es real, no discurso.** El cambio del 2026-09-10 (pestañas
  en vez de scroll infinito de 15 secciones) y la grilla de 2 columnas para
  los botones del header (2026-09-11, documentada en el propio JSX) muestran
  que ya se probó en la preview y se corrigió por lo que se vio, no por
  intuición.
- **La degradación es honesta.** `noSePudo` (Vogels) hace que un dato que no
  se pudo traer diga "no se pudo traer", nunca un cero que se leería como "no
  trabajaste". Poco ERP de este tamaño se molesta en distinguir esos dos
  casos.
- **El expediente disciplinario se excluye a propósito**, aunque la política
  de la fila lo permitiría — porque esa policy no filtra `borrador`, y
  avisar de una sanción que nadie decidió entregar es peor que no avisar de
  nada. Es exactamente la pregunta 7 de la rúbrica, ya resuelta antes de que
  existiera la rúbrica.

## Hallazgo 1 — el hueco de comunicación (el que motivó esta revisión)

Las cuatro únicas puertas de esta pantalla hacia la encargada son de un tema
fijo: **Anuncios** (una vía, empresa→persona), **Acuses** (una vía, exige leer
y firmar, no responder), **Pedir vacaciones** (`fn_solicitar_vacaciones`,
solo fechas) y **Pedir revisión de un día** (`fn_pedir_revision`, solo un día
puntual). Nada cubre "tengo un problema con un compañero", "no me generaron
mi horario", o cualquier cosa que no sea una fecha. Hoy eso se resuelve por
WhatsApp — exactamente lo que la pregunta 1 de la rúbrica pide detectar.
Ver la propuesta de contrato en el mensaje de esta conversación.

## Hallazgo 2 — "avísale a tu encargada" no contempla el escalón más alto 🔶→✅ verificado en la captura

Dos tarjetas del Resumen —**Tu próximo turno** y **Tus objetivos**— dan por
sentado que quien lee tiene a alguien por encima a quien avisarle:

> "No hay turnos ni horario cargados para los próximos días. Si eso no es lo
> que esperabas, **avísale a tu encargada**."
>
> "Todavía no tienes objetivos cargados... **Los acuerda contigo tu
> encargada**."

En la captura de Felipe (Gerente General, el techo del escalafón —
`RANGO.admin = 3`, ver `escalafon.ts`) las dos tarjetas salen vacías y las
dos frases se imprimen igual. Felipe no tiene una "encargada" a quien
avisarle: él ES a quien se le avisa. Es la pregunta 7 de la rúbrica en
estado puro — un estado que el código de la copia no imaginó porque quien
lo escribió (con toda razón, es el caso que manda) pensaba en la integrante
de tienda.

**Por qué es un hallazgo y no un detalle cosmético:** son DOS tarjetas
repitiendo la misma suposición rota, lo que según la pregunta 4 de la rúbrica
(integridad conceptual) señala que la suposición vive en dos sitios en vez
de uno — el mismo patrón que este repo ya aprendió a evitar con
`permisos.ts`/`fecha-lima.ts`. Antes de escribir el arreglo hay que decidir
**una** función/constante ("a quién avisar según tu rango"), no parchear las
dos frases por separado.

**Costo de arreglarlo:** bajo. Es una condición sobre `yo.rol` (o mejor,
sobre si `puedeActuarSobre(yo.rol, "integrante")` — si ya está en el techo o
cerca, la frase cambia a algo como "coméntalo con Desarrollo Organizacional"
o se omite la sugerencia entera). No toca base de datos.

## Hallazgo 3 — sin verificar 🔶 (no se pudo tomar captura real)

Deducido, no visto: una integrante recién ingresada, sin horario ni turno
cargado todavía (un caso real de onboarding, no hipotético — los cuatro
registros de prueba de la base local muestran que aquí es común que `cargo`
y otros campos lleguen vacíos al principio), vería la MISMA tarjeta de
"Tu próximo turno" vacía que Felipe — pero para ella el texto SÍ es correcto,
porque ella sí tiene una encargada real. Este caso no es un hallazgo en sí:
es la confirmación de que el Hallazgo 2 es angosto (solo rompe arriba del
escalafón) y no hay que tocar la frase para todo el mundo, solo para quien
está en el techo.

## Pendiente para la siguiente pasada

No se auditaron todavía `AdelantoDePago` ni `HorasDeLaSemana` (componentes
propios, no leídos línea por línea en esta sesión) ni las ocho pestañas
restantes de `/mio`. Quedan para la próxima ronda, ya con la rúbrica escrita.
