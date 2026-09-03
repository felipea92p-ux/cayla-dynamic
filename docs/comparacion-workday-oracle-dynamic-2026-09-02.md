> ℹ️ **Informe de arquitectura, no estado vigente.** Rehecho el 2026-09-02
> porque la primera versión (referenciada en el PR #106, "informe de
> arquitectura Workday → Dynamic") nunca se guardó como archivo — vivió solo
> en una conversación y se perdió. Esta vez queda escrita. El avance de hoy
> sigue estando en [`estado.md`](estado.md); esto es contexto de diseño, no
> una lista de tareas.

# Workday / Oracle HCM vs. lo que Dynamic ya resuelve

**2 de septiembre de 2026.** Comparación anclada en dos fuentes verificadas,
no en impresión general de "cómo son los ERP grandes":

- **Lado Dynamic:** inventario del esquema real (`supabase/migrations/0001`
  a `0339`, 318 archivos) y del código en `packages/shared/` y
  `apps/web/`, hecho por un agente de exploración sobre este repo — no sobre
  lo que `CLAUDE.md` dice que existe.
- **Lado Workday/Oracle:** documentación pública de arquitectura de ambos
  productos (datasheets, guías de administración, foros técnicos) — ver
  fuentes al pie.

## Objeción al encuadre, antes de empezar

Pedir "comparar contra Workday/Oracle" invita a leer la comparación como una
lista de compras: "les falta X, hay que agregarlo". Eso sería el error.
Workday y Oracle son sistemas diseñados para organizaciones de miles de
empleados con cientos de procesos de negocio distintos y equipos de
implementación dedicados. CAYLA tiene 30 personas y 4 sedes. La mayoría de
la maquinaria de esos sistemas (motor de workflow genérico, jerarquía
organizacional de posiciones, flexfields con UI de configuración) sería
**complejidad que Dynamic no necesita pagar** — exactamente lo que
`CLAUDE.md` ya advierte con el principio de "núcleo mínimo".

Lo que sí vale la pena mirar no son las *features* de esos sistemas, sino
sus **primitivos** — las reglas estructurales de las que esas features son
consecuencia. Y ahí sí hay algo real: en varios sitios, Dynamic ya
**redescubrió** esos primitivos a pulso, después de un bug caro en
producción, pero los aplicó caso por caso en vez de una vez como regla. Esa
es la comparación que importa.

---

## 1. Vigencia temporal (*effective dating*)

**Workday/Oracle:** el primitivo central de ambos sistemas. Cada objeto de
negocio (compensación, puesto, régimen, centro de costo) es *effective-dated*
por diseño — un cambio nunca sobrescribe el valor anterior, abre un tramo
nuevo. El sistema puede reconstruir el estado exacto en cualquier fecha
pasada sin lógica especial, porque **todo** el modelo obedece la misma regla.

**Dynamic:** tiene el patrón — y es idéntico en forma al de Workday:
`vigente_desde/vigente_hasta` + índice único parcial (`WHERE vigente_hasta
IS NULL`) + `EXCLUDE USING gist` anti-solape. Pero solo lo aplica a **cinco
tablas**: `horarios_asignados`, `tarifas_hora`, `asignaciones_salario`,
`asignaciones_educacion`, `asignaciones_regimen_pension`.

Y esa quinta tabla es la prueba de que el patrón no se adoptó por diseño
sino por dolor: **`asignaciones_regimen_pension` se creó en agosto de 2026
(migración 0261) porque `personas.regimen_pension` era un valor sin
historia**, y recalcular un mes viejo leía el régimen de HOY — el mismo
defecto de fondo que ya había costado la 0277 (cambiar el régimen no movía
el descuento). El repo ha ido cazando esta misma clase de bug campo por
campo, no como regla general.

**Lo que sigue mutable sin historia, pese a mover dinero o afectar cálculos
legales:** `personas.sede_base_id`, `sede_fisica_id`, `rol`, `funcion`,
`cargo`, `con_hijos`, `devenga_*` (parcial — tiene `devenga_hasta` pero no
tramo completo), `retencion_4ta`.

De esas, **`sede_base_id` ya no es una hipótesis — es el mismo defecto que
la 0277, confirmado en el código, solo que todavía no reventó (o no se
sabe si reventó).** Tres hechos, verificados leyendo el código real:

1. **`fn_planilla_calcular` computa la movilidad como
   `días_trabajados × tarifa_de_UNA_sola_sede`** (`0261...sql:656`:
   `monto_movilidad = h.dias * tar.tarifa`), y esa sede es
   `coalesce(sf.codigo, s.codigo)` — la sede **actual** de la persona en el
   momento en que se calcula, no la sede en la que trabajó cada día. Dato
   curioso: `jornadas` sí guarda `sede_id` por día (la verdad exacta de
   dónde se marcó cada jornada), pero el cálculo de movilidad no lo usa —
   usa un solo valor a nivel de persona para todo el periodo.
2. **Ese valor se puede cambiar desde el navegador con un `UPDATE` directo
   y sin ningún rastro.** `apps/web/app/(admin)/admin/equipo/page.tsx`,
   función `guardarEdicion()`: `supabase.from("personas").update({...,
   sede_base_id: form.sedeId, ...})` — sin RPC, sin función de compuerta,
   sin escritura a `correcciones_auditoria`. No hay ningún trigger
   genérico de auditoría sobre `personas` (el único trigger de la tabla es
   `trg_personas_updated_at`, que solo toca la marca de tiempo). Es,
   textualmente, el mismo hueco que tenía `fn_set_regimen_pension` antes de
   la 0261 ("no dejaba rastro en `correcciones_auditoria`") — con el
   agravante de que aquí ni siquiera hay una función dedicada de por
   medio: es un `UPDATE` de tabla suelto.
3. **El congelado sí se protege, pero solo hacia adelante.** El comentario
   de `planilla_pagada_detalle.sede_codigo` (`0096_la_foto_del_pago.sql:90`)
   dice, literal: *"Dónde estaba la persona ESE mes. Si la trasladan
   después, el costo del periodo no se muda con ella"* — la foto ya
   congelada no se mueve si la sede cambia más tarde. Pero eso no protege
   el cálculo que **produce** esa foto: si la persona ya fue transferida
   ANTES de que el periodo se congele (o antes de un `fn_repagar_periodo`),
   el cálculo usa la sede nueva para el periodo entero, incluyendo los
   días trabajados en la sede vieja.

**Lo único que falta para confirmarlo como incidente real (no solo como
defecto de diseño) es dato de producción**, y ese dato no se puede
reconstruir retroactivamente porque nada quedó auditado. Lo que sí se
puede medir: comparar `monto_movilidad` entre `version = 1` y la versión
más reciente de `planilla_pagada_detalle` para la misma persona y periodo
—si difieren sin que la tarifa de esa sede haya cambiado en
`parametros_laborales` para esa fecha, es la huella del defecto ya
disparado.

## 2. Motor de procesos de negocio (*Business Process Framework*)

**Workday:** cada cambio sensible (contratar, cesar, cambiar compensación,
un retroactivo) pasa por el mismo motor configurable de pasos y
aprobaciones — construido en el núcleo, no añadido después. Aprobar el
primer eslabón de una cadena la hace subir hasta el tope de la jerarquía o
hasta que se cumpla una condición de salida.

**Dynamic:** no tiene un motor genérico — y **está bien que no lo tenga**
a esta escala. Lo que sí tiene es la misma idea reimplementada, sin
generalizar, **tres veces por separado**: `fn_cambiar_regimen_pension()`
(0261), la puerta única para cambiar `rol` (0295/0296), y la máquina de
estados de `expediente_disciplinario` (`borrador → firmado → entregado`,
con `doc_previo_id` encadenando la escalera). Los tres hacen lo mismo en
espíritu — validar, escribir con guardas, dejar rastro en
`correcciones_auditoria` — con su propia función a medida cada vez.

**Sin objeción a no construir el motor genérico.** Construir un BPF de
verdad para 4 roles y 30 personas sería resolver un problema que CAYLA no
tiene — el propio Rich Hickey del criterio de este proyecto lo llamaría
"fácil, no simple": parecería más flexible y en realidad entrelazaría tres
dominios que hoy están sanamente separados. Lo que sí vale la pena es
**nombrar el patrón como convención escrita** (algo como "un cambio a un
campo sensible pasa por `fn_cambiar_X()`, nunca por `UPDATE` directo" —
mismo espíritu que la regla ya existente de `permisos.ts`), para que la
próxima vez no se reinvente sin darse cuenta de que ya es la tercera vez.

## 3. Modelo organizacional (Supervisory Org / Position Management)

**Workday/Oracle:** organización jerárquica de primera clase, desacoplada
del modelo de dotación (por posición o por puesto), con centros de costo,
líneas de reporte y sub-organizaciones ilimitadas.

**Dynamic:** plano a propósito — sede + rol, sin jerarquía de reporte
(`jefe_directo`/`reporta_a` no existen en ningún lado del esquema). "Quién
es la encargada de una sede" ni siquiera es una columna: se resuelve
implícitamente (`rol = 'supervisor_sede' AND sede_base_id = X`).

**Sin objeción — esto es correcto, no un hueco.** Y hay una señal de que
el instinto correcto ya está aplicado donde hacía falta: `es_encargada_piso`
(0040) es un booleano deliberadamente **separado** del rol, creado porque
el rol "hacía dos trabajos a la vez" (permiso del sistema vs. cobertura
operativa de Turnos). Eso es, en miniatura y a la escala correcta, la misma
separación que Workday encierra en "organización vs. modelo de dotación" —
Dynamic la aplicó donde realmente dolía, sin construir la jerarquía entera
alrededor. Copiar la organización jerárquica de Workday aquí sería
"núcleo mínimo" al revés: meter estructura al core que el negocio no pidió.

## 4. Tiempo y ausencias (*Time & Labor* / *Absence Management*)

**Oracle:** repositorio de tiempo + periodos repetibles, integrado con un
módulo de ausencias separado pero con un contrato de integración definido.

**Dynamic:** el mismo espíritu — `marcajes` (log append-only) →
`jornadas` (resumen derivado vía trigger) es exactamente el patrón
evento-crudo + vista materializada que `CLAUDE.md` ya declara como
principio ("los marcajes son la fuente de verdad, append-only"). Las
pantallas `ausencias`/`vacaciones` existen como superficies separadas, con
integración real hacia planilla (las reglas de pago de vacaciones —0173,
0275— dependen de ellas). **No alcancé a verificar el mecanismo exacto de
esa integración** en este pase — si hace falta profundizar aquí, es la
siguiente pregunta a medir, no algo que deba darse por sentado.

## 5. Cambios retroactivos (*retro pay*)

**Workday:** si un cambio tiene fecha efectiva pasada, el sistema
**calcula solo la diferencia** entre lo pagado y lo que debió pagarse, y la
empuja por el mismo motor de aprobación — con rastro completo de quién
corrigió qué y por qué.

**Dynamic:** tiene el concepto, pero **invertido en filosofía**. En vez de
calcular una diferencia automática, `fn_planilla_congelar` se **niega** a
tocar un periodo ya pagado — `fn_fecha_en_periodo_pagado` bloquea, por
ejemplo, cambiar el régimen de pensión con fecha dentro de un periodo
cerrado. Para reabrir, existe `fn_repagar_periodo` (0098), que no calcula
un delta: recalcula **todo** el periodo y lo guarda como una nueva versión
(`planilla_pagada_detalle.version = max(version)+1`), dejando la anterior
intacta.

**Sin objeción — y aquí Dynamic probablemente le gana a Workday para su
propio tamaño.** El modelo de "delta automático" de Workday exige un motor
de cálculo en el que confiar ciegamente para computar diferencias
correctas sin efectos secundarios. `fn_planilla_calcular` es una función de
~1600 líneas con 47 versiones acumuladas — no es, hoy, ese motor de
confianza ciega. Bloquear y forzar una repetición explícita y versionada
(en vez de un delta silencioso) es más lento pero es exactamente lo que
`CLAUDE.md` pide en su principio de transacción todo-o-nada: nunca un
estado a medias. No copiar el automatismo de Workday aquí es la decisión
correcta, no una carencia.

## 6. Seguridad (Domain Policies / Security Groups / SoD)

**Workday:** tres capas separadas — dominios de datos (qué se puede ver o
escribir), grupos de seguridad (quién pertenece a qué grupo), y seguridad
por proceso de negocio (quién puede iniciar/aprobar/corregir/rescindir cada
proceso) — con segregación de funciones explícita.

**Dynamic:** ya separa más de lo que un vistazo rápido sugeriría.
`permisos.ts` (capa de UI, documentada como no autoritativa — "la base
gana") separa **permiso** de **alcance** (rol vs. sede); `escalafon.ts`
añade una tercera dimensión que Workday no tiene tan explícita: **rango
relativo** (`puedeActuarSobre`, admin=3 > lider_do=2 > supervisor_sede=1 >
integrante=0) para decidir quién puede actuar sobre la cuenta de quién — no
es un simple check de rol, es jerarquía numérica. La autoridad real vive en
RLS + funciones `SECURITY DEFINER` null-safe (`fn_es_admin_o_lider()` con
`coalesce(..., false)` desde la 0078, tras el defecto de que `NULL` pasaba
como autorizado).

**Hueco real, pero pequeño:** Workday separa "quién ve el dato" de "quién
puede iniciar/aprobar/corregir un proceso concreto" como tabla declarada.
Dynamic mezcla esa segunda dimensión dentro del cuerpo de cada función
(`fn_cambiar_regimen_pension`, las guardas de `expediente_disciplinario`)
en vez de una tabla explícita de "verbo × proceso × rol". A 4 roles, esto
no amerita una tabla nueva — pero si el número de "procesos con guardas a
medida" sigue creciendo (van al menos tres: régimen de pensión, rol,
disciplina), en algún momento sí vale la pena una tabla chica en vez de la
cuarta función a medida.

## 7. Extensibilidad (*flexfields*)

**Oracle:** DFF/EFF — agregar atributos personalizados a objetos estándar
desde una UI de configuración, sin tocar código ni desplegar.

**Dynamic:** tiene el equivalente real en catálogos versionados en BD
(`parametros_laborales` con `vigente_desde/vigente_hasta`, `tasas_pension`,
`categorias_laborales` + `factores_categoria`) — mismo espíritu que un
flexfield: el dato vive en tabla, no en código, y se puede corregir sin
deploy (aunque sin UI de administración — se pega por SQL Editor, según la
regla de este repo).

**Hallazgo concreto y accionable:** `topes_educacion_rango` (0132) es, por
comentario propio del SQL, "espejo de `RANGOS.topeEducacion` en
`apps/web/lib/rangos.ts`" — **el mismo dato vive en la tabla Y en un
archivo TypeScript hardcodeado a la vez**. Es exactamente el
anti-patrón que la regla #3 de `packages/shared` en `CLAUDE.md` ya prohíbe
("nunca una lista escrita a mano de algo que vive en una tabla"). Es una
corrección barata y de bajo riesgo — no un hallazgo especulativo.

---

## LO QUE NO PIDIÓ — el hallazgo que pesa más que toda la lista

**La vigencia temporal (sección 1) no es un ítem más de la lista: es la
única pieza donde Dynamic ya demostró, con dinero real, que el patrón
importa — y `sede_base_id` es la 0277 esperando a que alguien se
transfiera de sede.**

`asignaciones_regimen_pension` no es una feature que se copió de Workday:
es una tabla que nació de un bug ya pagado (0277) y de una corrección cara
(0261). El patrón "un valor sin fecha reescribe el pasado al cambiarlo" es,
según los propios comentarios del repo, algo que se ha venido cazando
**campo por campo** — nunca se declaró como regla general.

Verificado línea por línea (no es hipótesis): `fn_planilla_calcular`
calcula la movilidad de todo el periodo con la sede **actual** de la
persona (`días_trabajados × tarifa`, `0261...sql:656`), esa sede se
edita desde el navegador con un `UPDATE` directo sin auditoría
(`equipo/page.tsx`, función `guardarEdicion()`), y no existe ningún
trigger que la capture. Es el mismo hueco que tenía
`fn_set_regimen_pension` antes de la 0261, palabra por palabra — pero sin
siquiera la función dedicada que ese caso sí tenía.

## Recomendación concreta

DECIDÍ: separar esto en dos movimientos de tamaño y riesgo muy distinto,
y no tratarlos como un solo paquete.

**Movimiento 1 — medir, hoy, sin escribir código.** Pedirle a Felipe que
corra en el SQL Editor una consulta de solo lectura:

```sql
select periodo_id, persona_id, version, sede_codigo, monto_movilidad,
       congelada_at, origen
from planilla_pagada_detalle
where persona_id in (
  select persona_id from planilla_pagada_detalle
  group by persona_id, periodo_id having count(distinct version) > 1
)
order by persona_id, periodo_id, version;
```

Si para algún `persona_id`+`periodo_id` el `monto_movilidad` cambia entre
versiones sin que la tarifa de esa sede haya cambiado en
`parametros_laborales` para esas fechas, el defecto ya disparó y hay que
reparar a esa persona — igual que se hizo con la 0277.

**Movimiento 2 — recién si el Movimiento 1 encuentra algo, o como
prevención de bajo costo si no encuentra nada:** cerrar el hueco de
auditoría en `equipo/page.tsx` (que `sede_base_id` deje de viajar en el
`UPDATE` directo, igual que ya se excluyó `rol` del mismo bloque por la
misma razón) es barato y de riesgo casi cero. Construir el tramo completo
(`asignaciones_sede`, al estilo `asignaciones_regimen_pension`) es lo
correcto a mediano plazo, pero es una migración que toca el cálculo de
planilla — no se escribe sin la auditoría empírica contra `BEGIN … ROLLBACK`
que `CLAUDE.md` exige para todo lo que toca plata, y no antes de tener el
resultado del Movimiento 1.

DESCARTÉ: escribir ya mismo la migración del tramo sin medir primero. El
costo de una migración mal dirigida sobre una columna con 76
`ALTER TABLE` encima es alto, y el propio método de este repo —medir antes
de proponer— existe para evitar exactamente ese tipo de trabajo rehecho.

SE ROMPE SI: alguien se transfiere de sede y su periodo se congela o se
repaga (`fn_repagar_periodo`) después de la transferencia — ahí la
movilidad de todo el periodo, incluidos los días trabajados en la sede
vieja, se calcula con la sede nueva, en silencio.

---

## Fuentes consultadas (Workday / Oracle)

- [Mastering Effective Dating in Workday HCM](https://www.linkedin.com/pulse/mastering-effective-dating-workday-hcm-kalyani-ghule-sxafc)
- [Workday Business Object Extraction Architecture — Databasin](https://www.databasin.ai/tech/workday/)
- [Workday Business Process Framework (datasheet)](https://www.workday.com/content/dam/web/en-us/documents/datasheets/workday-business-process-framework.pdf)
- [Business Process Framework — Workday docs](https://doc.workday.com/workday-education/en-us/course-manuals/hcm-core-for-administrators/business-process-framework.html)
- [Workday Position Management vs. Job Management — CloudApper](https://www.cloudapper.ai/workday-help/workday-position-management-vs-job-management/)
- [Organization management in Workday (datasheet)](https://www.workday.com/content/dam/web/en-us/documents/datasheets/organization-management-in-workday-datasheet-en-us.pdf)
- [Oracle Fusion Cloud Absence Management — What's New](https://docs.oracle.com/en/cloud/saas/readiness/hcm/25c/amg-25c/25C-absence-mgmt-wn-t65777.htm)
- [Time and Labour in Oracle Fusion HCM](https://unogeeks.com/time-and-labour-in-oracle-fusion-hcm/)
- [Workday Security Model: Groups, Policies & Domains](https://peopletechguide.com/workday-security-model-groups-policies-domains/)
- [Security Policy Configuration and Activation — Workday docs](https://doc.workday.com/workday-education/en-us/course-manuals/security-for-administrators/security-policy-configuration-and-activation.html)
- [Using Flexfields for Custom Attributes — Oracle docs](https://docs.oracle.com/cd/E29505_01/fusionapps.1111/e16691/ext_ff.htm)
- [Extensible Flexfields in Oracle Fusion HCM](https://dataterrain.com/extensible-flex-fields-in-oracle-hcm-fusion-application)
- [Retro Pay and Off-Cycle Correction Workflows in Workday](https://www.cloudapper.ai/workday-help/retro-pay-off-cycle-payroll-correction-workflows-workday/)
