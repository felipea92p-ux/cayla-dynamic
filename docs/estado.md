# Dynamic — Estado y pendientes

**Este es el único archivo de estado.** Se sobrescribe al avanzar; no se crean
copias con fecha. Lo ya cerrado vive en [`historico.md`](historico.md). Cómo se
trabaja: ver [`CLAUDE.md`](../CLAUDE.md) en la raíz.

## Qué va acá y qué no

Este archivo guarda **solo lo que ninguna herramienta puede responder sola**:
las decisiones tomadas, los pendientes con fecha, lo que depende de una persona,
y lo que se descartó para no volver a investigarlo.

| Pregunta | Quién la responde de verdad |
|---|---|
| ¿Cuántas migraciones hay, hasta cuál? | `ls supabase/migrations \| tail -1` |
| ¿Cuántas pruebas, y pasan? | `npx supabase db reset && npx supabase test db` · `npx pnpm typecheck && npx pnpm test` |
| ¿Producción dice lo mismo que el repositorio? | `scripts/sql-manual/huella_del_esquema.sql` — una fila, dos segundos. Si difieren las funciones con el mismo conteo, `que_funcion_cambio.sql` dice cuál |
| ¿Falta pegar alguna migración? | `./scripts/que-falta-pegar.sh` genera la consulta; `migraciones_aplicadas` guarda el registro |
| ¿Falta anotar alguna migración? | la prueba `122_toda_migracion_deja_su_rastro`, en CI, en cada push |
| ¿Hay números duplicados o huecos nuevos? | `scripts/hooks/numeracion.sh`, antes de cada push |
| ¿Qué se hizo y cuándo? | `git log` |

Ninguna de esas siete puede envejecer sin que alguien se entere. Las de abajo sí,
y por eso están escritas.

⚠️ **Y la tercera fila es la que más caro salió aprender.** Hasta el 2026-08-08
esa pregunta la respondía un comparador que llevaba las huellas del repositorio
escritas dentro, así que caducaba en horas: acusó a 25 funciones que estaban
bien, y mientras tanto seis funciones de producción llevaban semanas dejando
cambiar una planilla ya pagada sin que nadie lo viera. **Un dato de referencia
nunca viaja guardado** — ni en un archivo, ni en un mensaje. Las dos mitades se
calculan en el mismo minuto o no se calculan.

**Regla para quien edite este archivo:** si lo que vas a agregar es un número que
un comando puede calcular, no va acá — va el comando. Y si es una lista de
nombres que hay que revisar, tampoco: va la consulta que los encuentra sola.

---

## 2026-08-14 — el barrido del pago del 28, y cuatro alarmas que no eran

**El cierre del 28/08 NO está bloqueado.** Comprobado contra producción, no
deducido: las **29 personas cuadran** contra `chk_foto_cuadra`, y el periodo
suma **S/ 15,917.11**.

Salió de una auditoría de 13 agentes en dos fases —nueve recalculando cada
concepto desde la norma sin mirar el código, cuatro intentando refutar lo que
los primeros encontraran—. 53 hallazgos, 45 reproducidos con cifras. Y de ahí,
lo que sobrevivió al contraste con los datos reales cabe en media página.

### Lo que se arregló y ya está en producción

| | |
|---|---|
| **0248** | La foto del pago aprende la retención de 4ta. La 0245 le restó un término al total sin ampliar `chk_foto_cuadra`: el día que se configurara una retención, `fn_planilla_congelar` abortaba y **no se congelaba nadie**. Estaba armado y sin estallar — cero personas la tenían configurada |
| **0244** | Los cuatro defectos de la 0243, que llevaba desde el 14/08 corriendo con ellos. El peor atascaba el cierre con un solo cese a mitad de periodo |
| **0209** | La versión corregida reemplazó al borrador: el cese del mismo día que dejaba a la persona en S/0.00, y el sueldo fijo que cobraba el periodo completo |

⚠️ **La 0248 es la TERCERA vez que pasa lo mismo** — 0127 con movilidad,
educación y pensión; 0201 con el sobretiempo; esta con la retención. El término
del total y la columna de la foto viven en dos sitios y nada obliga a tocarlos
juntos. Por eso la prueba **189** no vigila la retención sino **el patrón**:
falla si aparece cualquier columna `monto_*` fuera del candado, en el `db reset`
y no un 28 por la noche.

### Lo que queda, y son datos, no código

- ~~**Dante Ramal** — cobraría el mes completo por 16 de 31 días~~ — ✅ **no era
  un problema, y la aclaración de Felipe lo invirtió entero.** El sistema decía
  `fecha_ingreso = 13/08` con un tramo de salario que arrancaba el **29/07**, y
  yo propuse corregir el tramo. Estaba al revés: **Dante ya trabajaba desde
  antes; el 13/08 es el día en que Felipe lo dio de alta en el sistema.** El dato
  malo era la fecha de ingreso.

  Con `fecha_ingreso = 2026-07-29` —ya corregida en Equipo— estuvo el periodo
  completo, así que **el mes completo es lo correcto y los ~S/315 no existen**.
  Verificado además: no tiene horario asignado, así que el motor de faltas no le
  cuenta ni un día ausente pese a no marcar nunca. Es `rxh` con `sueldo_fijo`.

  ⚠️ **DECISIÓN DE FELIPE, PARA QUE NADIE LA «ARREGLE» DESPUÉS:** a Dante se le
  pagó por fuera antes de entrar al sistema, y **eso no se carga — se cuenta
  desde ahora**. El sistema es nuevo y no vale la pena complicarlo hacia atrás.
  De `fecha_ingreso` cuelga el reloj de su CTS, su gratificación y sus
  vacaciones: quien mire su devengado dentro de unos meses va a ver una
  antigüedad más corta de la real y va a querer corregirla. **No es un dato mal
  cargado: es una decisión.**

  Y una nota para cuando se revise el vínculo de los locadores con el contador:
  **Dante es locador con monto fijo mensual**, que es exactamente el indicio de
  laboralidad que ya está señalado para Carlos, Catherine y Claudia. Entra en esa
  misma lista; no se quedó fuera por haberse dado de alta después.
- **Kerin Guevara** — ingresó el 12/08 sin **régimen de pensión** (no se le
  retiene nada, y CAYLA es agente de retención) y **sin horario vigente** (no se
  le miden faltas ni tardanzas). Las dos se cargan desde las pantallas.

### ⚠️ UN CABO SUELTO QUE HAY QUE VOLVER A MEDIR EL 28

**Felipe apareció con un descuadre de +S/110.00 —exactamente 11 días × S/10 de
movilidad— en dos consultas consecutivas, y desapareció solo minutos después**
sin que nadie tocara nada conocido. Tiene `cobra_movilidad = false` por la 0166,
y la tarifa general de producción vale **S/10** (en el repositorio vale 0.00).

No hay explicación: `fn_planilla_calcular` aplica `cobra_movilidad` **en los dos
sitios**, el concepto (línea 376) y el total (línea 514). Se verificó leyendo el
cuerpo vivo.

**Instrucción concreta: correr `va_a_poder_cerrarse.sql` el 28, justo antes de
congelar.** Es una sola sentencia y responde en dos segundos. Si el descuadre va
y viene, ese es el único momento en que importa — una vez congelado, la foto se
queda con lo que hubiera.

### Dos scripts nuevos, para volver a usarlos cada mes

| Ruta | Qué responde |
|---|---|
| [`antes_de_cerrar_el_mes.sql`](../scripts/sql-manual/antes_de_cerrar_el_mes.sql) | Once chequeos en una tabla: si existe el periodo, si faltan feriados, jornadas mudas, movilidad excluida, quién no tiene pensión, ausencias pagables en cero, entradas y ceses, salarios y horarios vigentes |
| [`va_a_poder_cerrarse.sql`](../scripts/sql-manual/va_a_poder_cerrarse.sql) | Si el cierre va a poder completarse. **Una sola sentencia que SIEMPRE devuelve una fila**, porque cero filas se lee igual que «todo bien» |

**Ninguno de los dos llama a una función de diagnóstico, y es deliberado.**
`fn_liquidaciones_pendientes`, `fn_contratos_desnaturalizados`,
`fn_dias_por_revisar`, `fn_ausencias_subsidio` y `fn_contratos_por_vencer`
llevan dentro `fn_es_admin_o_lider()`, y en el SQL Editor la sesión es
`postgres`, que no tiene fila en `personas`. **Devuelven cero filas, no un
error.** Van contra las tablas para no poder caer en eso.

### Las cuatro alarmas que no eran, y qué enseñan

Ninguna llegó a aplicarse porque todas se intentaron reproducir antes. Quedan
escritas para no volver a levantarlas:

| Se dijo | La verdad |
|---|---|
| «Diez ausencias se pagarán en S/0.00» | Todas de tipos con `paga = false` —permiso personal, salud sin documento, otro— más unas vacaciones de un locador, que no las cobra desde la 0186. **S/0.00 es su resultado correcto** |
| «Diez jornadas mudas pagarán cero» | Eran todas **del día en curso**: gente trabajando con su jornada abierta. Al volver a correrlo un rato después el número bajaba solo, mientras la gente se iba a casa |
| «La movilidad excluida atasca el cierre» | El código **sí** aplica `cobra_movilidad` en los dos sitios. Reproducido: el cierre pasa |
| «Veinte personas descuadran» | La consulta buscaba `descuento_pension` —el nombre de la COLUMNA— cuando la clave del JSON es **`descuento_afp`**. Restaba cero, y descuadraba todo el que tuviera AFP, en ~10 % |

**El patrón de las cuatro es el mismo: afirmar por la forma en vez de medir.** Y
las cuatro se cazaron igual — intentando reproducirlas. La regla que ya estaba
escrita en este archivo, otra vez: *medir contra la base antes de proponer*.

Y una que vale por sí sola: **la fórmula de un candado no se escribe de memoria,
se copia del sitio donde es verdad.** La de `chk_foto_cuadra` se saca del
`insert` de `fn_planilla_congelar`, que es quien mapea cada clave del JSON a su
columna. Ahí se ve que `descuento_pension` se llena con `descuento_afp`.

---

## 2026-08-14 — la retención de cuarta categoría, y diez locadores donde había tres

### El sistema ya calcula el 8 % de un recibo por honorarios ([`0245`](../supabase/migrations/0245_la_retencion_de_cuarta_deja_de_hacerse_a_mano.sql))

Hasta hoy no existía: la única forma de reflejarla era escribir un movimiento de
tipo `descuento` a mano cada mes, con el 8 % calculado fuera del sistema.

Dos columnas en `personas` —`retencion_4ta` y `constancia_4ta_hasta`—, los dos
parámetros en `parametros_laborales` con su sustento, el cálculo dentro de
`fn_planilla_calcular`, la línea en la boleta, el aviso en la pantalla de
planilla y las dos columnas en el CSV que usa el contador. Se escribe por
`fn_set_retencion_4ta`, que valida el vínculo y audita.

**Las tres puertas, y por qué no alcanzaba un booleano.** El caso que lo pidió
—el recibo del contador externo— es de S/652.17, o sea POR DEBAJO del tope de
S/1,500: CAYLA no estaba obligada a retener. Retiene porque **el prestador lo
marcó «Sí» al emitir**, que es una casilla que decide el emisor y no el pagador,
y la marca porque factura a muchas empresas, se pasa del límite anual de la
suspensión y prefiere adelantar el 8 %.

- `NULL` → no se retiene. Es como nace todo el mundo, y por eso pegar la 0245 no
  movió un céntimo de nadie.
- `automatica` → la regla del art. 74 de la LIR: 8 % solo si el pago del mes
  **supera** el tope. En S/1,500.00 exactos no se retiene; en S/1,500.01 sí.
- `siempre` → 8 % sea cual sea el monto.
- La constancia del F.V. 1609 manda sobre las tres mientras esté vigente. Dura el
  año calendario: cuando vence, el modo vuelve a mandar.

**Y lo que CAYLA paga de más no es la retención.** El honorario cargado es el
BRUTO (652.17): de ahí 600 van a la persona y 52.17 a SUNAT a su nombre. Lo que
la empresa absorbe por haber pactado un neto es el *gross-up* —S/52.17 al mes,
S/626 al año— y ya está dentro de esa cifra. Bajar el honorario para esquivar la
retención pierde más de lo que ahorra: la retención se le acredita a la persona
contra su impuesto anual, el honorario recortado no vuelve.

### Un locador con monto fijo cobraba S/0.00, y la boleta lo llamaba «por horas»

Dos cosas distintas que salieron al configurar el primer caso real:

1. **Quien cobra un monto fijo y no marca nunca sale en S/0.00.** Su pago se
   calcula por horas registradas. La pieza que faltaba no era la retención sino
   `sueldo_fijo`, que **no se puede marcar desde ninguna pantalla** — va por SQL,
   igual que `en_planilla`.
2. **Y entonces la boleta decía «Honorarios por las horas prestadas (0 h) ……
   S/ 652.17».** Los números bien, la etiqueta mal, en un papel que se le entrega
   a alguien externo y que además describe el acuerdo al revés. La
   [`0250`](../supabase/migrations/0250_la_boleta_no_le_dice_por_horas_a_un_monto_fijo.sql)
   hace que `sueldo_fijo` viaje en el JSON para poder distinguirlos. No mueve un
   céntimo.

### ⚠️ Son DIEZ los que cobran por honorarios, y este archivo decía tres

La sección [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado)
nombra a tres, confirmados el 2026-08-07. La consulta devuelve diez. No se sabe
cuántos están activos ni cuántos pasan el tope sin mirar los datos, así que la
lista no va acá — va la consulta que los encuentra sola:

```sql
select p.apellidos || ', ' || p.nombres as quien, p.estado, case when p.sueldo_fijo then 'monto fijo' else 'por horas' end as como_cobra, s.salario_mensual_soles as honorario, t.valor as tope, case when p.estado <> 'activo' then 'cesado — no configurar' when s.salario_mensual_soles is null then 'sin honorario asignado' when p.sueldo_fijo and s.salario_mensual_soles > t.valor then 'PASA EL TOPE todos los meses' when p.sueldo_fijo then 'no llega al tope' else 'varia mes a mes: Automatica' end as que_hacer from personas p left join lateral (select a.salario_mensual_soles from asignaciones_salario a where a.persona_id = p.id and a.vigente_desde <= fn_hoy_lima() and (a.vigente_hasta is null or a.vigente_hasta >= fn_hoy_lima()) order by a.vigente_desde desc limit 1) s on true cross join lateral (select pl.valor from parametros_laborales pl where pl.clave = 'retencion_4ta_tope' and pl.vigente_desde <= fn_hoy_lima() and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima()) order by pl.vigente_desde desc limit 1) t where p.tipo_vinculo = 'rxh' order by p.estado, p.apellidos;
```

**PENDIENTE · decidido el 2026-08-14: no se configura a nadie más por ahora.**
Solo está puesto el contador externo (`siempre`). El resto queda en NULL y la
pantalla de planilla marca en ámbar a quien pase el tope sin configurar — que es
lo que va a poner los nombres reales sobre la mesa. **Lo que hay que preguntarle
al contador antes de tocar a nadie: quiénes tienen constancia de suspensión
vigente.** Con S/1,800 al mes nadie llega al límite 2026 de S/48,125 anuales, así
que la mayoría calificaría — y con la constancia cargada el sistema deja de
retener solo, sin que nadie pierda plata.

### El agujero que dejó la 0245, cerrado el mismo día por otra sesión ([`0248`](../supabase/migrations/0248_la_foto_del_pago_aprende_la_retencion_de_cuarta.sql))

La 0245 le restó un término nuevo al total y no amplió `chk_foto_cuadra`, que
exige que el total sea la suma exacta de once columnas conocidas. **En cuanto
alguien tuviera retención configurada, «Marcar como PAGADO» habría fallado para
las treinta personas del periodo**, no solo para el locador retenido: el cierre
del mes se atasca entero. Estuvo abierto media hora y el periodo sigue
provisional, así que no llegó a morder. Vale como recordatorio de que una prueba
del cálculo no es una prueba del cierre.

---

## 2026-08-14 — una marca que la base rechazaba, y las que quedaron presas

### El aviso «2 sin registrar» del terminal tenía razón, y no era grave

Salió mirando el terminal: un aviso rojo que aparecía «con frecuencia». Lo pinta
el contador de marcas **apartadas** — las que el servidor rechazó seis veces y
la cola dejó de reintentar, guardadas en el IndexedDB de ese navegador.

**Las dos eran de Felipe, del 13-ago a las 22:02 y 22:22, las dos
`salida_final`.** La salida entró bien a las 22:35:42 y la jornada quedó cerrada
en 9.81 h, así que **no se perdió nada y no hubo efecto en planilla**. Y de paso
quedó comprobada la fórmula contra producción: 12-ago 11.32 − 1.23 = 10.10 ✅ y
13-ago 13.06 − 3.25 = 9.81 ✅.

**Por qué fue negativo a las 22:02 no se puede reconstruir, y no hace falta
intentarlo otra vez:** tres marcas de esos dos días son `admin_correccion`,
puestas después. El estado que lo produjo ya no existe — con los datos de hoy esa
misma salida daría +9.25 h. Casi seguro fue un estado transitorio de las pruebas
de la 0240 esa noche.

### Lo que sí era un defecto: el CHECK tumbaba el marcaje, no la jornada ([`0249`](../supabase/migrations/0249_una_salida_real_siempre_se_puede_registrar.sql))

`chk_horas_no_negativas` (0095) frenaba el `insert` en `jornadas` — bien —, pero
ese insert cuelga del trigger de `marcajes`, así que la excepción subía y
**reventaba el insert del marcaje**. El efecto real no era «esta jornada no se
guarda», era **«esta persona no puede marcar su salida»**: el terminal se la
seguía ofreciendo toda la noche y cada intento acababa apartado. Basta una
corrección con la hora mal tecleada para llegar ahí.

Ahora el negativo se guarda como `null` —«no se sabe cuánto», no «trabajó
cero»— y el día queda sellado en `pendiente_revision`. **El sello no es un
extra:** la planilla lee `coalesce(horas_trabajadas, 0)`, así que sin él el
arreglo habría cambiado una marca perdida a gritos por un descuento en silencio.
El CHECK no se toca.

**⚠️ Y el md5 de partida de esa función NO SE TOMÓ.** Se pegó antes de pedirlo a
producción, y `create or replace` ya había reescrito el cuerpo cuando se fue a
buscar. El de llegada (`c50fa2ed…`, idéntico al local) **no lo sustituye**: sale
igual partas de donde partas, así que no prueba de qué versión se partió. Lo que
sostiene que producción estaba en la 0240 es indicio, no garantía — el error que
rechazaba las salidas era exactamente su comportamiento. La cabecera de la
migración lo dice con todas sus letras.

### PENDIENTE · una marca apartada no la puede ver nadie

Esto sigue abierto y es la mitad que falta:

- **El aviso no se apaga nunca.** Nada borra ni recupera una apartada. Las dos
  del 13-ago van a seguir contando en ese Safari para siempre. Un aviso
  permanente en la pantalla que mira todo el equipo deja de leerse en tres días.
- **Dice «avisa a tu encargada» y la encargada no tiene dónde mirar.**
  `obtenerDescartadas()` solo se usa para contar; no hay pantalla que diga de
  quién es la marca, de qué hora ni qué error dio.
- **Viven en un solo navegador.** Desde el panel no se ven. El día que esto le
  pase a alguien en una sede, nadie se entera hasta que alguien mire la Mac mini.

La 0249 impide que el caso se repita por esta causa; no recoge las que ya
cayeron, ni las que caigan por otra.

### El cierre del 28 estaba bloqueado, y por una línea ([`0252`](../supabase/migrations/0252_el_cierre_deja_de_caerse_por_quien_no_cobra_movilidad.sql))

El término de movilidad del `total` no aplicaba `cobra_movilidad`; el concepto
`monto_movilidad` sí, desde la 0166. La boleta imprimía S/0.00 y el pago la
cobraba igual. Medido: **descuadre de 16.00** con tarifa de S/8 y dos días.

Y no era «una boleta descuadrada». `fn_planilla_congelar` inserta las ~30 filas
en UNA sentencia, así que la que rebota tumba la sentencia entera: **una persona
bastaba para que el 28 no cerrara para nadie**, con un error de CHECK que no la
nombra. Aplicada y confirmada en producción.

Es el tercer caso idéntico en una semana —0242 asignación familiar, 0245
retención de cuarta, 0252 movilidad— y el patrón ya no admite duda: **un
concepto vive en DOS sitios del JSON, el suyo y el término del `total`, y tocar
uno solo deja la boleta diciendo una cosa y el pago haciendo otra.** Antes de
tocar cualquier concepto, buscar sus dos apariciones.

### El descanso médico se pagaba en cero ([`0254`](../supabase/migrations/0254_el_descanso_medico_deja_de_pagarse_en_cero.sql))

**`fn_planilla_calcular` no leía la tabla `ausencias`.** Ni una vez. Las
vacaciones que sí se pagan (0177) salen de una tabla distinta, `vacaciones`. De
los cuatro tipos que `tipos_ausencia` declara pagables, la planilla pagaba uno.

La 0254 conecta **solo `descanso_medico`**, con el tope de 20 días del RIT
art. 31 f). Tres decisiones que se rompen fácil y ahora tienen prueba (195):

- el **tope** se cuenta en días CALENDARIO (así los cuenta EsSalud) y lo que se
  **paga** son días LABORABLES (pagar un domingo sería pagar de más);
- un día vale el promedio de lo pagado por día trabajado, **con respaldo**: sin
  días marcados el promedio sería 0/0 y quien pasó el mes entero enfermo cobraría
  cero — el mismo defecto con otra cara y en el caso más grave;
- **un día que ya paga por otra vía no se paga dos veces**. Salió solo: el
  descanso empezaba en Fiestas Patrias.

Va DENTRO de `pago_base`, como las vacaciones, y por eso NO toca
`chk_foto_cuadra` ni `fn_planilla_congelar`.

**PENDIENTE · `licencia_con_goce` y `maternidad` siguen pagando cero.** Es
decisión, no descuido: la maternidad tiene reglas propias —98 días, subsidio de
EsSalud desde el día uno— que hay que decidir antes de escribirlas. La prueba 187
lo fija por escrito.

### PENDIENTE · Chiara: seis días que dependen de un papel, no del código

Su `descanso_medico` del 29/07→03/08 (dengue, **con certificado**) ya lo paga la
0254: cuatro días, ~S/122.

Lo que queda es **`salud` 04/08→09/08, vigente y SIN documento**. El sistema paga
cero y **eso es correcto** — no hay defecto que arreglar. Pero el bloque anulado
que ocupaba esas fechas decía «en reposo médico» y el certificado del dengue
termina el 03/08, justo el día antes. **Falta mirar hasta qué fecha llega el
certificado ya subido**: si cubre hasta el 09, la ausencia está mal clasificada y
son otros ~S/122 suyos; si solo llega al 03, se queda como está y no se vuelve a
levantar.

### Dos avisos del cierre que gritaban por lo normal

El chequeo devolvió `💸 14 día(s) que pagarán CERO` un jueves a las tres de la
tarde: **eran trece personas en su puesto**. Contaba las jornadas abiertas de
HOY. Se comprobó de la forma más elocuente — al recorrerlo un rato después el
número había bajado a 10 solo, mientras la gente se iba a casa. Ninguna era de
un día pasado.

Y el de movilidad se disparaba con solo existir alguien con
`cobra_movilidad = false`: con la 0252 puesta esa persona sigue existiendo y ya
no hay riesgo, así que **el 🚫 habría quedado encendido para siempre**. Ahora
mide el defecto —que el filtro aparezca dos veces en la función— y no su proxy.

**La regla que sale de las dos:** un semáforo que no se apaga nunca no es un
semáforo, y un aviso que grita por lo normal se desactiva a la semana. Las
exclusiones se aplican ANTES de contar.

---

## 2026-08-13 — el expediente de Mateo, y la 0213 que ya no se puede pegar

**LO ÚNICO CON FECHA.** Hay una imputación de cargos **entregada y abierta**
(T-03/0001-2026-CAYLA, entregada el 10-ago). Su plazo de descargo vence el
**domingo 16**; se pidió al laboralista respuesta para el **lunes 17**.

Se emitió **saltándose el escalón d) del art. 19.2 del RIT** — la segunda
suspensión. El defecto era del generador, que tenía tres peldaños en vez de
cuatro; lo corrigió la 0232 y ya está en producción, pero el papel entregado
salió con la versión anterior.

Y leyendo el Reglamento apareció algo mayor: el **art. 19.3** exige dos días
hábiles de descargo **antes** de imponer la medida, con el documento retenido en
borrador — y advierte que su omisión «invalida la medida, que en tal caso no se
computa como antecedente ni sirve de peldaño». Si el orden importa, no afecta
solo al último escalón.

Las dos preguntas están escritas para enviarse en
[`disciplina-tardanzas-faltas/10-consulta-al-laboralista.md`](disciplina-tardanzas-faltas/10-consulta-al-laboralista.md),
y lo que hay que mirar cuando llegue el descargo, en el
[`09`](disciplina-tardanzas-faltas/09-evaluar-un-descargo.md).

**Lo investigado, para no repetirlo:** la ley (art. 25 h) usa el plural
«amonestaciones escritas y suspensiones» pero **no fija un número**. Lo que
obliga a dos es el RIT propio, que es más estricto a propósito — y el empleador
queda obligado por el reglamento que aprobó.

**⚠️ LA 0213 NO SE PUEDE PEGAR, NUNCA MÁS.** Comprobado ejecutándola: su
`fn_tardanza_escalon` devuelve cinco columnas y la viva devuelve seis, así que
Postgres aborta con «cannot change return type of existing function» y no entra
nada. Su mitad útil —`fn_expediente_generar_falta`— entró por la **0237**. El
número 213 sigue sin anotar en `migraciones_aplicadas` **a propósito**: no se
aplicó y el registro tiene que seguir diciéndolo.

**El reloj de las Mac mini ya no es un punto ciego** (0230). Medido en
producción: **4 segundos** de desfase máximo en siete días, latencia de red
incluida. El umbral de aviso está en 120 s, treinta veces por encima. Es seguro,
no reparación.

**Y una regla de método que costó tres errores en una sola sesión:** grepear una
cadena en el cuerpo de una función NO mide la regla. `suspension_previa_dias`
vive en el `returns table(...)`, que no forma parte de `prosrc`; `sueldo_fijo` se
comprueba un nivel más abajo, en `fn_expediente_crear_borrador`; y
`fn_auto_cierre` mira el periodo pagado a través de un helper. Las tres veces la
respuesta correcta salió de preguntarle a la base qué hace —`pg_get_function_result`,
llamar la función, reproducir el caso— y no de buscar un texto.

### El panel ya puede volver a invitar a quien nunca entró

`/admin/cuentas` daba por resuelta a una persona en cuanto GoTrue aceptaba el
envío: `invitar` enlaza el `auth_user_id` ahí mismo, y con eso desaparecía de la
lista de invitables **aunque el correo se hubiera perdido en spam y ella no
hubiera hecho nada**. No había forma de reenviarle nada desde la pantalla.

Ahora hay una sección **«Volver a invitar — todavía no han entrado»**, con envío
de a una o en tanda. Quién sale ahí se lee de `auth.users.last_sign_in_at`: en
null significa exactamente «no abrió el correo», porque aceptar la invitación
**es** iniciar sesión — el enlace la deja adentro para que ponga su clave.

**Y son dos correos distintos, medido contra el GoTrue local:**

| A quién | Qué se le manda | Por qué |
|---|---|---|
| Invitada que no aceptó (sin confirmar) | la invitación otra vez | GoTrue reinvita sin problema: mismo usuario, `invited_at` renovado |
| Cuenta creada a mano (confirmada) | el enlace de «recuperar acceso» | la invitación responde **422 `email_exists`**; ese camino está cerrado |

La tanda va con una pausa entre correos y **se corta sola** al llegar al tope por
hora del proyecto, diciendo quiénes quedaron pendientes. Mandarlos todos de golpe
no llega antes y convierte un tope en veinte errores.

⚠️ **Lo que hay que comprobar en el panel de Supabase antes de disparar:** que
`https://cayla-dynamic.vercel.app/**` esté en *Authentication → URL
Configuration → Redirect URLs*. Si no está, el enlace **no falla** — cae en el
Site URL, o sea en la raíz, y la persona termina en el login sin clave y sin
nada que le diga qué hacer. Se lee igual que un correo que no funcionó. En local
pasaba exactamente eso hasta que se agregó a `additional_redirect_urls` en
`supabase/config.toml`.

*(Y un aviso para quien corra las pruebas: `scripts/seed-dev.mjs` deja
`100_una_tienda_no_es_una_oficina` fallando en sus pruebas 8 y 9. Con
`npx supabase db reset` antes, las 953 pasan.)*


---

## 2026-08-10 — un terminal sin dueño, y un diseño de plata que se cayó al medirlo

### El terminal ya no puede quedarse sin dueño ([`0202`](../supabase/migrations/0202_un_terminal_activo_sin_dueno_deja_de_poder_existir.sql))

El guard que impide que una sesión se haga pasar por un terminal son **tres
condiciones unidas por AND** dentro de `fn_registrar_marcaje`. Con
`terminales.auth_user_id` en null la segunda es falsa, el AND entero es falso y
**no se lanza nada**: cualquier sesión con login podía registrar marcas a nombre
de otra persona, en cualquier sede, y la planilla las paga. Medido:
`anon` no puede ejecutar la función, `authenticated` sí — o sea que no hacía
falta ser admin ni encargada.

**El esquema fabricaba ese estado por su cuenta, y por dos caminos:**

- `activo` tiene **default `true`**, así que el insert natural —
  `insert into terminales (sede_id, nombre_dispositivo)` — nacía activo y sin
  dueño. El camino cómodo era el peligroso.
- La FK es **`ON DELETE SET NULL`**. Borrar en Auth la cuenta de un terminal no
  lo desactivaba: le ponía el dueño en null y lo dejaba activo. La puerta se
  abría sola, sin que nadie tocara nada. Esto no estaba en el catálogo.

El candado va en la TABLA, no en la función — la lección de la 0180. Y cierra el
hueco entero: cuando la función llega al guard, la fila ya se buscó
`where id = p_terminal_id and activo`, así que con el CHECK `auth_user_id` no
puede ser null ahí. **Aplicada y confirmada**; los tres terminales de producción
tenían dueño, así que esto no tapó un agujero abierto: **impide el próximo, que
es el terminal de Central el día que se cargue.**

**NO se reescribió `fn_registrar_marcaje`** para dejar el guard como
`is distinct from`, que es la forma correcta por doctrina. Son 129 líneas y es la
única puerta de escritura del sistema; el 08-08 se vio que 22 funciones de
producción no coincidían con el repositorio. Queda pendiente, y va después de
pedir el cuerpo de producción.

⚠️ **Y dejó una lección de método:** un CHECK nuevo **rompe los montajes de
cualquier prueba que fabrique el estado que prohíbe**. Rompió tres (110, 147,
149) y CI salió en rojo. El hook de pre-push corre `typecheck` y las pruebas de
interfaz, **no las pgTAP** — esas solo corren en CI. Antes de empujar un CHECK,
un `grep` de treinta segundos por `supabase/tests`.

### Dos hallazgos del catálogo son FALSOS desde la 0138

`hallazgos-abiertos.md` lista **C12·A16** (`fn_registrar_marcaje` sin candado de
periodo pagado) y **A3** (`fn_auto_cierre` reescribe periodos pagados) como los
dos más graves que quedan vivos. **Medidos contra el esquema de hoy, los dos son
falsos**, y el daño estaba tapado una capa más abajo:

- `fn_recalcular_jornada` **sí** lleva el candado desde la 0138, y se **sale en
  silencio en vez de lanzar**, a propósito: lanzar abortaría el INSERT y el
  terminal acabaría descartando una marca REAL tras seis reintentos.
- `fn_auto_cierre` solo escribe en `marcajes` y `alertas` — nunca en `jornadas`
  directo—, así que pasa por el mismo trigger y queda igual de tapado.

Lo que sí quedaba era el residuo: la marca entraba y la jornada no se
recalculaba, **sin que nadie se enterara**. Eso lo cerró la
[`0207`](../supabase/migrations/0207_una_marca_que_cae_en_un_periodo_pagado_deja_de_entrar_muda.sql).

**Falta tacharlos en `hallazgos-abiertos.md`**, y con ellos otras dos entradas
que también envejecieron: dice que no existen las pruebas 84 y 85 (existen, de
otros temas) y que «los montos pagados no se congelan en ninguna tabla» (la foto
del pago existe desde la 0096). El propio archivo avisa de por qué importa: un
catálogo con entradas mentirosas hace desconfiar de las que sí siguen vivas.

### El borrador de un memo dejó de imprimirse firmado por Gerencia General

`firmante` y `cargoFirmante` arrancaban en la constante `EMPRESA` y solo se
reemplazaban dentro de `if (doc.firmante_id)`, que en un borrador es null por
definición. El papel salía diciendo **«De: Alvarez Pereyra Felipe Miguel ·
Gerencia General»** en un documento que no había firmado nadie. Y el aviso de
borrador llevaba `no-print`: se veía en pantalla y **desaparecía justo en el
papel**.

Ahora arrancan en null y sin firmante se imprime «Pendiente de firma»; el aviso
sí se imprime y dice que no tiene validez como documento entregado. **En vista
previa, pendiente de mirar y subir a producción.**

Lo que el catálogo tenía mal: cuando el memo SÍ está firmado pero su ficha no se
puede leer —una encargada imprimiendo un memo suyo suscrito por gerencia, flujo
legítimo y a propósito— caer al representante legal no es inventar nada. Ese
caso avisa en pantalla, no en el papel.

### La 0209 está escrita y SIN TERMINAR — y su primer diseño se descartó midiéndolo

El defecto es real y está reproducido dos veces: `fn_cesar_persona` cierra los
tramos de salario y horario, `fn_reactivar_persona` no los devuelve, y quien se
reactiva queda **activa, marcando, cobrando S/0.00** (S/2,254.64 contra S/0.00
con jornadas idénticas) e **invisible para el motor de faltas** (5 contra 0).

**El primer diseño era simétrico y habría metido un defecto peor que el que
arregla.** Reabrir el tramo viejo con `vigente_hasta = null` no lo deja vigente
«desde que volvió»: lo deja vigente **desde su `vigente_desde` hasta el
infinito**, cubriendo hacia atrás todo el hueco. Medido en `BEGIN … ROLLBACK`:

| Qué | Cuánto |
|---|---|
| Reescribe planillas YA PAGADAS | S/2,420.63 en un periodo · **S/3,390.00** en tres |
| Sobrepaga el periodo EN CURSO | S/1,130.00 del mes entero, sin trabajar un día |
| Devenga grati, CTS y vacaciones del hueco | **+S/719.52**, y `fn_grati_cts_periodo` lo desembolsa |
| Fabrica faltas | **89** no justificadas, alimentando el expediente disciplinario |

Y pasa **mudo**: no hay ni un trigger sobre `asignaciones_salario` ni sobre
`horarios_asignados`, y el candado de periodo pagado vive DENTRO de
`fn_set_salario`, así que un update desde otra función lo esquiva.

**El diseño que queda:** no se reabre el tramo viejo, se **crea uno nuevo desde
el día de la reactivación**. El hueco queda sin salario y sin horario, que es la
verdad —esa persona no trabajó—, y ninguno de los cuatro daños puede ocurrir.

**El candado es ESTRECHO, y se decidió con datos.** Volver a `activo` mueve por
sí solo el total de las planillas pagadas de quien tiene hijos —S/98.31 por
periodo, porque la asignación familiar no mira tramos ni jornadas—. Pero de las
**8 personas inactivas de producción, seis tienen un periodo pagado posterior** y
para las seis el daño es CERO (RxH, sin hijos, sin sueldo fijo). Un candado sobre
«hay un periodo pagado» rechazaría seis reactivaciones legítimas de ocho: no
protegería, prohibiría. Se pone solo donde el daño está medido — `con_hijos` con
un periodo pagado detrás—, y **eso es una lista que hay que revisar** el día que
aparezca otro concepto que se pague sin mirar tramos.

**Lo que falta antes de pegarla:** la prueba pgTAP, medir la promesa central
contra un periodo pagado de verdad, y los tres bordes reproducidos (volver
teniendo ya un tramo abierto, un tramo cerrado con fecha futura, y el caso de
cero filas). **No urge:** medido en producción, nadie está hoy en ese estado.

**Y hay dos cosas que la medición destapó y que NO causa la 0209:**

- Una **liquidación ya pagada se vuelve a devengar entera** al reactivar:
  S/852.19 sobre ventanas ya liquidadas por S/1,380.81. `fn_liquidacion_pagar`
  escribe en `liquidacion_pagada` y en `correcciones_auditoria`, pero **no** en
  `desembolsos_beneficios` ni en `movimientos_planilla`, que son las dos únicas
  cosas que miran los guards de `fn_provisiones`.
- La cabecera de la **0176 tiene una errata**: dice que «`fn_set_salario`
  comprueba que la persona esté activa». **Es falso** en la versión vigente — ni
  esa ni `fn_set_horario_semanal` miran `personas.estado`. Es justo la frase que
  haría no poner un freno creyéndolo puesto.

## ~~2026-08-10 — regenerar `types.ts` ya no es solo reordenar~~ ✅ HECHO el 2026-08-14

**Cerrado.** Se hizo, y la causa era más simple —y peor— de lo que decía esta
sección: el generador declara los parámetros de cada función como NO anulables, y
`fn_set_fin_contrato(p_fecha)` acepta null a propósito. Correr el comando dejaba
**63 errores en diez pantallas**. `scripts/tipos-args-nullables.mjs` le agrega
`| null` a los 491 parámetros y va encadenado al script de `gen-types`, así que
el comando documentado ahora termina en verde. Se conserva lo de abajo por el
registro de cómo se midió.



**Medido, no supuesto.** El repositorio venía diciendo que regenerar
`packages/database/src/types.ts` «reordena las 4.400 líneas del archivo entero»
y por eso se aplazaba, resolviendo cada función nueva con un doble casteo. Se
probó de verdad al añadir `fn_expediente_resolver` (0206):

- Genera **4.217 líneas** contra las 2.535 de hoy.
- **Gana 65 nombres** y suelta exactamente dos: `fn_set_horario` y
  `fn_quitar_horario`, que la 0184 borró. Hasta ahí, estrictamente correcto.
- **Pero cambia la convención de los argumentos opcionales**, de
  `string | null` a `string | undefined`. Eso rompe de golpe Ausencias,
  Correcciones y Datos personales, que pasan `null` a propósito.

O sea: **no es un reordenamiento, es una migración de tipos.** Aplazarla sigue
siendo razonable, pero por un motivo distinto al que estaba escrito, y el coste
de aplazarla crece — ya son tres las funciones que el archivo no conoce
(`fn_expediente_resolver`, `fn_tardanza_escalon`, y las columnas nuevas de
`fn_tardanzas_resumen`).

Cuando se haga, va sola en su propia rama y con las tres pantallas revisadas.

---

## 2026-08-10 — un `drop function` se llevó el permiso y la pantalla se calló

**Dos pantallas llevaban días caídas en producción y ninguna lo dijo.** Se
levantaron con la [`0204`](../supabase/migrations/0204_un_drop_se_lleva_el_permiso_y_la_pantalla_se_calla.sql),
que son dos `grant` y nada más. Verificado en producción: las tres filas en
`true`, y Disciplina volvió a listar a las dos personas que le tocaban.

**LA CAUSA, y es de clase, no de caso:** un `drop function` se lleva por delante
los `GRANT`. La [`0189`](../supabase/migrations/0189_una_tardanza_de_tres_horas_deja_de_desaparecer.sql)
hace ese drop sobre `fn_tardanzas_resumen` —obligada, porque devuelve `TABLE` y
Postgres no deja añadirle una columna con `create or replace`— y no vuelve a
otorgar. El último `grant execute` de esa función era de la **0067**. Como este
proyecto revoca el `EXECUTE` que Postgres da a PUBLIC por defecto, no hubo red.

**POR QUÉ NADIE LO VIO EN DOS DÍAS:** `authenticated` no podía ejecutarla,
PostgREST devolvía error, y `admin/disciplina/page.tsx` **no miraba el error de
esa llamada**. Imprimía «Nadie con tardanzas relevantes este mes» — la misma
frase exacta que cuando de verdad no hay nadie. El Dashboard y la Hoja de sede
leen la misma función y estaban igual de ciegos. Un falso negativo mudo en las
tres pantallas que existen para no dejar pasar a nadie.

**LA SEGUNDA, encontrada barriendo las 122 funciones que el panel llama por
`rpc()`:** la 0198 añadió `p_cuspp` a `fn_set_datos_personales` con un
`create or replace`. **Un parámetro nuevo no reemplaza: crea otra función.**
Quedaron dos sobrecargas —18 argumentos con permiso, 19 sin él— y el panel manda
`p_cuspp`, así que PostgREST elegía justo la que no podía ejecutar. Guardar una
ficha fallaba desde entonces. La sobrecarga huérfana de 18 sigue viva, muerta
pero inofensiva; **soltarla queda pendiente**.

**LAS DOS REGLAS QUE DEJA:**

1. **Toda migración que haga `drop function` vuelve a poner su `grant`.** No es
   opcional y no lo cubre nada: el `create or replace` conserva permisos, el
   `drop` + `create` no. La 0200 ya lo lleva por esto.
2. **Añadir un parámetro a una función es crear una función nueva.** Hay que
   otorgarle permiso, y decidir qué se hace con la vieja — dejarla viva es una
   ambigüedad esperando a que alguien la pise.

**Cómo se vuelve a comprobar**, sin fiarse de ninguna lista guardada:
[`quien_puede_ejecutar_el_semaforo.sql`](../scripts/sql-manual/quien_puede_ejecutar_el_semaforo.sql).

**Lo que sigue abierto de aquí:** ninguna prueba habría cazado esto. Las pgTAP
corren como `postgres`, que puede ejecutar todo; el defecto solo existe para
`authenticated`. Una prueba que compruebe los permisos del rol real es el
guardián que falta.

---

## 2026-08-08 — el papel que se le entrega a un locador dejó de llamarlo trabajador

La 0199 le quitó a un locador las cifras que no le tocaban —feriados,
gratificación, CTS, vacaciones— y el papel quedó correcto en los números y falso
en las palabras: seguía titulándose «Boleta interna de pago», llamaba
«Remuneración Básica» a sus honorarios, cerraba con «Total a recibir este mes»,
le contaba los días que «le tocaba venir» y lo mandaba a «consultar con tu líder
de equipo».

**Eso no es redacción, es lo que el documento declara.** En una inspección, el
papel que la empresa emite todos los meses pesa más que el contrato firmado: la
subordinación se prueba con indicios, y aquí CAYLA los estaba imprimiendo ella
misma, en el único ejemplar que esa persona se lleva a casa.

Ahora la pantalla imprime **dos documentos distintos**, no uno con filas de
menos. Quien presta servicios recibe un «Detalle de servicios prestados»: dice
qué relación es (locación del Código Civil), quién organiza el tiempo, que el
documento oficial es **su** recibo por honorarios y —recién al final, como
consecuencia y no como recorte— por qué no hay beneficios. Cierra con «emite tu
recibo por este importe».

**El interruptor es uno solo y vive en `packages/shared/src/vinculo.ts`**, no en
la pantalla. Son nueve las que van a hacer la misma pregunta, y este repositorio
ya juntó 35 copias de la misma condición de permiso antes de aprenderlo.

Ahí está también la regla que más importa: se pregunta `en_planilla === false`,
nunca `!en_planilla`. El frontend se despliega por Vercel mientras el SQL lo pega
Felipe a mano, así que hay ventanas en las que la pantalla nueva corre contra una
base que todavía no manda el campo. Con `!en_planilla`, ese `undefined`
convertiría a **todo el mundo** en locador de golpe: treinta personas recibirían
un papel que les niega gratificación, CTS y vacaciones, y saldría bonito. Las
cuatro pruebas de `tests/vinculo.test.ts` existen para eso.

### Lo que solo se vio mirando la hoja renderizada

La boleta le imprimía **«Colibrí»** — un peldaño de la escala de trabajadores.
La 0182 ya había decidido esconderlo, con este argumento: decir que alguien ocupa
una categoría de la escala es parte de lo que desnaturaliza una locación. Pero se
aplicó solo en la tabla de Planilla. En el código las dos pantallas no se parecen
en nada y ningún `grep` las conecta; se cazó abriendo el documento.

### Lo que queda de este hilo

- **«Honorarios pactados (mes completo) · S/ 1,130.00»** sigue impreso, y el
  número sale de `personas.sueldo_base_legal`. Carlos y Claudia **cobran por
  hora**: un importe mensual fijo impreso cada mes es, él solo, un indicio de
  laboralidad. Quitar esa línea para locadores es un `if` de una línea, y está
  pendiente de que Felipe decida.
- **Faltan las otras ocho pantallas** con el mismo problema: Planilla (135
  conceptos laborales), Provisiones, Liquidaciones, Feriados, Vacaciones, Costos,
  Ausencias y Disciplina.
- **Claudia** es el mismo caso que Carlos y aún no se movió. **Catherine** es
  otro distinto —socia, monto fijo— y se dejó para después a propósito.

---

## 2026-08-08 — el sobretiempo se paga solo, y todo lo que se cobra se declara

Empezó con una pregunta de Felipe —por qué el sistema no dejaba dar el sábado
como descanso por un feriado trabajado— y terminó en cinco migraciones. Lo que
va acá es lo que ninguna consulta puede responder: **por qué se decidió así**.

### Cómo se mide el sobretiempo, y las tres trampas

**Contra 48 h SEMANALES, nunca contra 8 h diarias.** El art. 25 de la
Constitución dice «ocho horas diarias O cuarenta y ocho semanales» y CAYLA pactó
la semanal, en contratos y RIT. Medido por día, el taller de Lima —5 días de
9 h = 45 h— generaría sobretiempo todas las semanas del año haciendo tres horas
MENOS que el máximo legal.

**«Semana» es un ciclo de siete días, no lunes a domingo.** Criterio vinculante
del Informe 027-2021-MTPE/14. El ciclo empieza tras un descanso y se corta a los
7 días; sin ese corte, doce días seguidos de 8 h darían 48 h de exceso en vez
de 8 — un tope semanal convertido en tope por racha, que no existe en la norma.

**Los ciclos no se solapan, y por eso el pago NO usa la ventana móvil** que sí
usa la alerta de Incidencias. Ahí el objetivo es no perderse ningún tramo
cargado; acá, una ventana móvil pagaría la misma hora siete veces.

Y se suma **el recargo** (25 % / 35 %), no la hora completa: las horas ya están
en `pago_base`. Es el mismo error que la 0173 corrigió con el feriado del sueldo
fijo.

### Tres exclusiones distintas que NO se pueden fundir en un campo

| Quién | Por qué | Dónde vive |
|---|---|---|
| RxH | Un locador no tiene jornada; pagarle horas extras es indicio de laboralidad | `tipo_vinculo` |
| Personal de dirección | Art. 5 del D.S. 007-2002-TR: fuera de la jornada máxima | `personas.personal_direccion` (0187) |
| Sueldo fijo | Su pago no depende de horas: un recargo sobre monto fijo no dice nada | `sueldo_fijo` |

**`personal_direccion` tiene columna propia y no se deduce del rol.** `admin` es
un permiso informático: el día que se le dé admin a alguien de DO para
administrar pantallas, se le quitaría sin querer su derecho a horas extras. Y no
es lo mismo que `sueldo_fijo`, que es una condición de pago — hay dirección que
cobra por horas. Hoy está marcado Felipe, y solo él.

### Qué entra a la base de EsSalud y pensión, y qué no

Entran el **feriado** y el **sobretiempo** (0193). No admiten discusión: el
art. 19 del D.S. 001-97-TR no los lista como no remunerativos y SUNAT les da
código propio en la tabla 22 de la PLAME — **0105** (sobretiempo 25 %), **0106**
(35 %) y **0107** (feriado o día de descanso).

**No entran, y no es un olvido:** el complemento variable y el plus por
objetivos, que tienen defensa legal real y están dentro de una estructura
decidida con el contador (ver
[`analisis-estructura-remunerativa-2026-07-30.md`](analisis-estructura-remunerativa-2026-07-30.md));
y la movilidad y la educación, no remunerativas por el art. 19 incisos e) y f).

⚠️ **Las sobretasas COMPLETAN una base declarada; no crean una donde no la hay.**
La primera versión le inventaba S/41.39 de pensión a un RxH y S/46.45 a alguien
con sueldo fijo — los dos tienen la básica en 0 a propósito. Ninguna prueba
existente cayó: eran montos de personas que antes no aparecían en ningún cálculo
de pensión. Lo fija ahora la `150_la_base_de_aportes_no_se_inventa`.

### La vía para reducir el costo en origen NO es dejar de declarar

Son dos, y las dos son legales:

- **Descanso sustitutorio** por feriado trabajado (art. 9, D. Leg. 713). Con él
  la sobretasa del 100 % no se genera. Medido en un caso real: el feriado de esa
  persona baja de S/206.83 a S/104.89.
- **Compensar el sobretiempo con descanso equivalente** (art. 10 del TUO), con
  acuerdo por escrito, dentro del mes calendario siguiente, sin tocar el descanso
  semanal ni caer en feriado.

**No aplicar la 0193 no era una vía.** La obligación existe con o sin migración:
lo único que cambiaba era si el sistema la mostraba.

### El retroactivo, y por qué no fue «por fuera»

S/100.03 en 8 personas por el sobretiempo de 28-jun → 28-jul, registrado como
movimiento en la planilla de agosto con el concepto nombrado. Felipe propuso
pagarlo en efectivo y se descartó: el sobretiempo **es remuneración**, así que
pagarlo fuera de planilla sería remuneración no declarada — una infracción nueva
y formal para tapar una vieja e informal. Misma plata, un renglón de diferencia.

### La política salarial, versión 4

Publicada el 2026-08-08 20:20. Dice el sobretiempo (25 % / 35 %), que la base de
aportes incluye feriados y sobretiempo, y **avisa que el neto baja antes de que
llegue la boleta** — entre S/9 y S/50 por persona, íntegro a su fondo.

⚠️ **Y lleva un blindaje que hay que conservar.** Al reforzar «45 horas cuando la
ley permite 48», Felipe levantó el riesgo: si alguien llegara a sostener que la
jornada pactada son 45, las horas 46 a 48 pasarían a ser sobretiempo con recargo
para todo el equipo, todas las semanas. El documento dice ahora, en el mismo
párrafo, que **el sobretiempo se cuenta desde la hora 49 y no desde la 46**, y
cinco pruebas de `politica-salarial.test.ts` no dejan que se caiga — incluida una
que verifica que nunca aparezca la frase «jornada de 45 horas».

**La versión 3 se quemó** por caché del navegador: se publicó un documento byte
por byte idéntico al anterior y el sistema no dijo nada. Quien la haya acusado
tiene que volver a hacerlo sobre la 4.

---

## 2026-08-08 — seis puertas dejaban cambiar una planilla ya pagada

**El repositorio y producción llevaban semanas diciendo cosas distintas, y no
había manera de enterarse.** Se compararon los dos esquemas enteros —199
funciones, 261 candados, 467 columnas— y el resultado ordena todo lo de abajo:

| | |
|---|---|
| **candados** | idénticos, byte a byte. Es lo que volvió inofensivo casi todo lo demás |
| **columnas** | idénticas, salvo dos que solo existen en producción |
| **funciones** | **22 distintas** |

### Lo único que era grave

Seis funciones de producción no tenían el candado de periodo pagado que el
repositorio les puso en julio con la 0026 y la 0037: `fn_set_feriado`,
`fn_quitar_feriado`, `fn_set_turno`, `fn_quitar_turno`, `fn_set_horario_semanal`
y `fn_set_descanso`.

Reproducido en local el estado exacto de producción y llamadas las seis sobre una
fecha de un mes ya pagado, **las seis dejaron pasar el cambio y una borró un
feriado de un mes pagado sin decir una palabra.** El daño no se ve: la jornada se
recalcula sola con el trigger, las horas del mes cambian, y la planilla
depositada deja de cuadrar con lo que el sistema dice hoy. Se descubre cuando
alguien reclama.

La [`0180`](../supabase/migrations/0180_el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron.sql)
lo repone —aplicada y confirmada, 6 de 6— y la prueba
[`141`](../supabase/tests/141_las_seis_puertas_a_una_planilla_pagada.test.sql)
exige **las dos mitades**: que dentro de lo pagado lancen, y que fuera de lo
pagado sigan funcionando. Un candado que cierra siempre lo quita cualquiera en la
primera urgencia.

Antes de sobrescribirlas se pidieron sus cuerpos y se compararon línea a línea:
producción era el repositorio **menos** el bloque, ni una línea de más. Mirar
antes de escribir no era ceremonia — siete funciones de las 22 tienen código que
el repositorio no conoce (ver abajo).

### El resto era texto roto

Seis funciones decían `l√≠der` donde debía decir `líder`: UTF-8 leído como **Mac
OS Roman**, que parte cada acento en dos. Se confirmó simulando esa conversión
sobre el cuerpo del repositorio — los md5 salen exactos, así que se identificaron
sin gastar consultas. Lo arreglan la **0181** (cuatro) y la **0183** (las dos que
la comprobación de la 0181 destapó, que además corrían la versión de julio de
`fn_crear_periodo` y `fn_eliminar_periodo`). Las dos aplicadas y confirmadas.

⚠️ **Y ese mismo día se demostró que el daño SIGUE ENTRANDO.** Horas después de
limpiar las seis, la consulta «qué falta pegar» devolvió `⚠ md5 SIN CATALOGAR`
para `fn_planilla_calcular` — la función que decide lo que cobra cada persona.
Medido: era el cuerpo de la **0185 pasado por Mac OS Roman**, y la 0185 se había
pegado ese mismo día.

O sea que el razonamiento de arriba —«si el canal fuera el culpable estarían
rotas las 199»— **era falso**: el daño no entra de una vez, entra **por pegada**.

✅ **Y la causa se encontró el mismo día: era `pbcopy` con el locale en `C`**
dentro del propio `dame-el-sql.sh`. Con `LC_CTYPE=C` el portapapeles interpreta
el UTF-8 como MacRoman y cada acento se parte en dos. O sea que la ruta culpable
no era «otra vía»: era la nuestra, en las sesiones cuyo entorno tenía ese locale
—por eso cuatro migraciones del mismo día salieron limpias y una no—. Ya está
arreglado: el script compara el portapapeles byte por byte contra el archivo y se
niega si no coinciden. Ver la regla en `CLAUDE.md`.

**Quedan dos detectores permanentes, y ninguno depende de una lista a mano:** la
fila **ACENTOS** de `que_falta_pegar.sql`, que barre el esquema entero buscando
el signo «√», y la columna `tiene_acentos_rotos` de
`en_que_version_esta_la_planilla.sql`. El catálogo de md5 de esa consulta
**también se calcula solo** desde las migraciones, con `iconv -f MAC` para
generar la variante rota de cada versión: llegó a mentir tres veces en un día
mientras se escribía a mano.

### El agujero que casi se anuncia y no existía

La 0026 le añadió a `fn_crear_periodo` un candado contra dos periodos que cierren
el mismo mes, con su motivo escrito en julio: «el plus de objetivos se pagaría
doble». Producción no lo tenía. La conclusión saltaba sola.

**Se probó antes de afirmarlo y es falsa.** El segundo periodo falla igual: lo
frena el índice único `periodos_etiqueta_unica` sobre (año, mes) de la fecha de
cierre. Y los 261 candados de producción son idénticos a los del repositorio.
Igual con el `advisory lock` que falta: `periodos_sin_solape` impide el solape de
todos modos.

**Aquí lo que protege el dinero es el candado de la BASE, no el de la función.**
Las seis puertas eran un agujero real porque detrás no había ningún constraint;
esta no lo era porque sí lo hay. Misma forma, conclusiones opuestas, y solo
medirlo las distingue.

### La lección de método, que costó medio día

**Un dato de referencia nunca viaja guardado — ni en un archivo ni en un
mensaje.** El comparador viejo llevaba las huellas del repositorio dentro y
acusó a 25 funciones que estaban bien. Se sacaron del archivo… y entonces
caducaron en el mensaje que las transportaba: se calcularon a las 10:28, entraron
cinco migraciones a las 10:55 y 11:14, y la comparación de las 11:30 ya no valía.

`huella_del_esquema.sql` calcula las dos mitades en el mismo minuto y trae
`hasta_migracion`, para que comparar dos generaciones distintas se delate en vez
de asustar. Los tres comparadores que mentían —`comparar_funciones.sql`,
`comparar_solo_funciones.sql`, `huellas_produccion.sql`— quedan **vaciados, no
borrados**: su contenido está en git y su ruta sigue avisando por qué no usarlos.

**Y una comprobación que barre gana a una que pregunta por una lista.** La de la
0181 no preguntaba por sus cuatro funciones: buscaba el signo «√» en el esquema
entero. Devolvió dos que nadie había señalado.

---

## 2026-08-06 — ningún papel firmado se podía subir, y nunca se pudo

**Lo que parecía un módulo terminado desde julio no funcionaba ni una vez.** El
cargo firmado de un memo disciplinario no se podía archivar desde que existe el
módulo (0074). Los tres memos entregados de producción llevaban semanas con «sin
el papel archivado» al lado y no era descuido de nadie: la base los rechazaba.

**La causa, que no se veía leyendo el código.** Supabase Storage no escribe el
objeto con un `INSERT`. Escribe `INSERT … ON CONFLICT DO UPDATE … RETURNING *`, y
esa forma necesita **tres** permisos, no uno: INSERT por la fila, SELECT por el
`RETURNING`, y UPDATE por el `ON CONFLICT`. Ningún bucket tenía política de
UPDATE. Y la de SELECT de `expedientes` exigía que el adjunto ya estuviera
registrado en `expediente_adjuntos`… registro que se crea DESPUÉS de subir el
archivo. Un círculo cerrado: no se podía escribir sin poder leer, ni leer sin
haber registrado, ni registrar sin haber escrito.

Lo que más costó: `fn_expediente_puede_adjuntar` devolvía **`true`** mientras la
fila se rechazaba, así que el fallo se leía como un problema de permisos de la
persona. El mensaje de Postgres nombra la tabla pero **no dice cuál de las
políticas faltó**. Se resolvió leyendo el log del contenedor de storage.

| # | Qué |
|---|---|
| **0170** | El acta de descanso acepta **HEIC/HEIF** — el formato en que un iPhone guarda sus fotos. Sin esto salían en gris en el diálogo de archivos: no se podían ni seleccionar, y la pantalla no daba ningún error |
| **0172** | Las políticas que faltaban en los tres buckets. Abre exactamente el hueco medido y nada más: quien subió un archivo puede leer **lo suyo** mientras lo registra (`owner_id = auth.uid()`), y quien puede crearlo puede reemplazarlo |
| **0175** | El acta de descanso **deja de guardarse como texto en una columna** y pasa al almacén, con los mismos 50 MB que los demás papeles. Los 3 MB de antes no eran una decisión sobre las actas: eran el precio de dónde vivían |

**Tres fallos más de pantalla, cada uno con causa distinta:** el formulario para
subir el cargo estaba escrito **solo** en «Firmados — por entregar», y los tres
memos de producción están entregados · Chrome **no reconoce el `.HEIC`** y
entrega la foto sin tipo, que el almacén rechaza con `415` (el tipo se deduce
ahora de la extensión, en `lib/tipos-archivo.ts`) · «Ver acta» abría un
`<iframe src="data:…">` que Chrome **bloquea**, dejando la pestaña en blanco.

**Por qué ninguna prueba lo cazó.** No había una sola que tocara
`storage.objects`, y un `INSERT` simple pasaba mientras el sistema no
funcionaba. La prueba **136** ejecuta ahora la sentencia real de Storage,
copiada de su log; la **137** cubre las dos ubicaciones posibles del acta.

---

# 📌 QUÉ FALTA — repartido por quién lo hace

## A · Lo que depende de Felipe

### A.1 · Con fecha límite — **en curso** (confirmado 2026-08-06)

| Qué | Cuándo | Si no |
|---|---|---|
| **Los convenios individuales de movilidad, firmados y cargados** | **antes del 28/08/2026** — es cuando se paga el periodo | Se habrá pagado movilidad sin el papel que la sostiene. La **RTF 05449-4-2007** desconoció la de 14 de 21 trabajadores por eso exacto |
| **La política de movilidad de empresa, firmada** | con fecha **anterior al 29/07/2026** | Es cuando empezó a pagarse movilidad. Un documento posterior a los pagos que justifica **no los justifica, y encima lo deja por escrito**. El tablero lo avisa solo, en rojo, con las dos fechas |
| **Contratar el Seguro Vida Ley** | cuanto antes | ~S/1,560/año. Sin póliza, CAYLA responde con su patrimonio: 16 remuneraciones por muerte natural (~S/18,000) o 32 por accidente o invalidez total (~S/36,000). Obligatorio desde el primer día (D.Leg. 688, mod. **Ley 31408**) |
| **Pagar el día sustitutorio de Arequipa** | **el 29/09/2026**, con el periodo 29/08–28/09 ya cerrado | El equipo de AQP habrá descansado el 31/08 sin cobrarlo, y el acuerdo que firmaron dice que sí les tocaba. **No es automático**: el sistema no sabe que el 15/08 existe. Ver la sección propia más abajo |
| **Registrar la póliza en el MTPE** | 30 días desde que se firma | No registrarla es la misma infracción que no tenerla |
| ~~**Pegar la [`0176`](../supabase/migrations/0176_quien_ya_se_fue_deja_de_tener_sueldo_vigente.sql)**~~ | ✅ **pegada el 2026-08-06** | Las seis de julio dejaron de tener sueldo vigente. No movió plata: su liquidación es S/ 0.00 antes y después (RxH, de 0 a 3 días). Comprobado con cuatro ceros: sin tramos abiertos, sin tramos pasados de largo, sin tramos posteriores al cese, sin motivos por revisar |
| ~~**Pegar la [`0179`](../supabase/migrations/0179_la_pantalla_de_equipo_dice_cuando_y_por_que_se_fue.sql)**~~ | ✅ **pegada** — figura en `migraciones_aplicadas` de producción | La pantalla de Equipo ya dice cuándo y por qué se fue cada quien. El motivo viaja solo a admin y líder DO |
| ~~**Pegar la 0180, la 0181 y la 0183**~~ | ✅ **pegadas el 2026-08-08** | Ver la sección del 08-08 arriba. Confirmadas por lo que devolvió el SQL Editor: `las_seis_con_candado: 6` y `funciones_con_texto_roto: 0` |
| ~~**Pegar la [`0201`](../supabase/migrations/0201_la_foto_del_pago_aprende_el_sobretiempo.sql)**~~ | ✅ **pegada el 2026-08-10** | Sin ella, «Marcar como PAGADO» fallaba **para todo el periodo** —no solo para quien hiciera sobretiempo— en cuanto alguien pasara de 48 h en un ciclo de siete días. El candado de la foto era de julio (0127) y no conocía el sobretiempo que la 0185 empezó a pagar en agosto. Confirmada con cinco comprobaciones en verde, incluida la que recorre las 96 fotos ya guardadas con la fórmula nueva: ninguna se rompió |

**Del Seguro de Vida Ley:** cotizado en **La Positiva, S/170/mes por 19
personas**, sin comisión de corredor —Dante confirmó que el reglamento no la
contempla— y con factura. **El 19 hay que cruzarlo antes de firmar**: el diseño
remunerativo asume 26. Quien esté en planilla y fuera de la póliza queda sin
cobertura, y ese capital lo paga CAYLA de su patrimonio. La consulta que arma la
lista real está en
[`quienes_van_al_seguro_de_vida_ley.sql`](../scripts/sql-manual/quienes_van_al_seguro_de_vida_ley.sql).

### A.2 · Lo que bloquea del contador — la marca de afectación

El código no es el problema: el problema es **con qué marca de afectación**
quedan el 0909 (movilidad), el 0202 (educación) y el 0203 (cumpleaños) en el
PDT — EsSalud, ONP/AFP y quinta categoría. Si alguno queda declarado afecto, no
solo se pagan aportes que la ley no exige: **CAYLA declara por escrito y mes a
mes que el concepto es remunerativo**, y eso destruye el sustento del artículo 19
con nuestra propia firma.

Es lo único que tiene que responderse **antes de declarar el primer periodo** con
los tres conceptos. La repregunta está redactada y lista para enviar en
[`movilidad-y-codigos-plame-para-el-contador.md`](movilidad-y-codigos-plame-para-el-contador.md).

*(Dante escribe los códigos sin el cero inicial —dijo «909» por 0909—, así que
son **0202** y **0203**. Falta su confirmación de una línea.)*

### A.2.b · Los tres locadores están retratados como personal subordinado

**Para consultar con el contador. No hay nada roto en el cálculo** — eso se
verificó y se descarta abajo. Lo que hay es un riesgo de cómo el sistema los
retrata.

**Son tres, confirmado por Felipe el 2026-08-07:** Carlos Espejo, Catherine
Pereyra y Claudia Pereyra. Los tres cobran por honorarios y los tres aparecen
así:

| | Sede | Rol en el sistema | Área | Rango de la escala | Pago |
|---|---|---|---|---|---|
| **Carlos Espejo** | CCO | **Admin** | Desarrollo org. | Aurora · S/1,800 | **por hora trabajada** |
| **Catherine Pereyra** | CCO | **Líder de equipo (encargada)** | Comercial | Oráculo · S/1,800 | por confirmar |
| **Claudia Pereyra** | LIM | **Líder de equipo (encargada)** | Comercial | Aurora · S/1,800 | por confirmar |

⚠️ **La columna «Pago» decía «fijo mensual» para los tres y era falsa, al menos
para Carlos** (Felipe, 2026-08-08). Cobra **por hora**: marca cuando decide
trabajar y se le paga lo que marcó. No es un detalle contable — «monto fijo,
igual mes a mes» es uno de los indicios de laboralidad que miran SUNAFIL y los
jueces, y este cuadro lo daba por cierto sin haberlo comprobado. **De Catherine y
Claudia sigue sin confirmarse.**

Cargo de mando, área, sede y un rango de la escala salarial. Son indicios de
**subordinación**, que es lo que convierte una locación de servicios en un
contrato de trabajo.

**Lo que el caso de Carlos tiene A FAVOR, y este documento no decía:** es
cuadripléjico, trabaja desde su casa, **no está sujeto a horario** y **cobra por
hora**: marca cuando él decide trabajar. Ninguno de los indicios de subordinación
que lista la doctrina —horario fijo, instrucciones directas, equipos de la
empresa, monto idéntico cada mes— aplica a esa descripción. Su marcaje no es
control de asistencia sino la medida de lo que factura, y desde la
[`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql)
el sistema ya no lo trata como asistencia: no le mide tardanza ni salida
anticipada, solo sus horas.

Lo que queda en su contra es el RETRATO —el rol `admin`, el área, el rango de la
escala—, no los hechos. Y el retrato se arregla; los hechos no habría cómo. El riesgo no es una multa: es la **desnaturalización** del
vínculo, con CTS, gratificaciones, vacaciones y EsSalud retroactivos desde el
inicio — y multiplicado por tres.

**Lo que ya está bien:** el cuadro de categorías que se publica al equipo bajo la
Ley 30709 **no los cuenta ni los incluye en las bandas** desde la 0145: filtra
por `tipo_vinculo = 'planilla'`. El documento legal no dice que estén dentro de
la escala. El retrato queda en las pantallas internas.

**✅ Y el indicio más caro de todos quedó cerrado el 2026-08-08.** El sistema les
medía **tardanza y salida anticipada**, y las guardaba: 524 jornadas de personas
no sujetas a horario. Un registro de tardanzas no es un dato de más — es
**control de jornada**, el indicio más directo de subordinación que existe, y lo
fabricaba CAYLA sobre sí misma día a día. La
[`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql)
lo cierra en la raíz —`fn_recalcular_jornada` deja de medir a quien no está
`en_planilla`, y con eso los seis consumidores quedan correctos sin tocarlos— y
limpia lo ya guardado. Confirmado en producción: `mediciones_que_sobran: 0`. Sus
**horas sí se siguen calculando**: de ellas depende lo que cobran (prueba 149).

Salió de una frase de Felipe y de ninguna auditoría: «era RXH, ellos no están
sujetos a horarios, solo lo puse como referencia». Ninguna de las diez revisiones
independientes lo vio, porque para verlo hay que saber **qué es cada persona**, y
eso no está escrito en el código.

**Y uno de los tres es un frente aparte: Carlos tiene rol `admin`.** Eso le da
todas las sedes, todos los datos personales del equipo —**cuentas bancarias y
DNI incluidos**— y la capacidad de firmar despidos.

**Lo que hace falta NO es quitarle el acceso.** Se evaluó el 2026-08-07 y se
descartó por dos razones: su área es Desarrollo Organizacional, que necesita esos
datos para trabajar; y `admin` y `lider_do` están en el mismo grupo de permisos
—los dos pasan por `puedeVerIdentidad`—, así que bajarlo de rol **no reduciría
nada**. No existe un nivel intermedio. Felipe confirmó además que es de absoluta
confianza, y eso no está en discusión.

**Lo que falta es el papel.** La Ley 29733 no pregunta si la persona es
confiable: pregunta si CAYLA puede demostrar quién accede a los datos personales
y bajo qué obligación. Un trabajador en planilla está sujeto al deber de reserva
por su contrato y por el RIT. **Un locador solo lo está si su contrato de
locación lleva la cláusula de confidencialidad y tratamiento de datos.**

Es una cláusula, no un cambio de sistema — y aplica a los tres, no solo a Carlos.
Vale preguntársela al mismo abogado o contador que revise el vínculo.

Y el agravante: **el expediente lo arma el propio sistema.** La pantalla de
Equipo los nombra encargados, les asigna un área y les pone un rango de la
escala salarial. Es prueba escrita, generada por CAYLA.

**Si son socios, cobrar por honorarios es correcto y común.** El problema no es
el vínculo: es que la ficha los describe como encargados de equipo, cargo que no
les agrega autoridad —si son socios ya la tienen— y en cambio construye la
prueba de lo contrario. Este archivo ya lo había anotado antes como un problema
de permisos («el rol de Catherine está al revés de su papel»); es más que eso, y
son tres.

**Lo que hay que decidir:** qué son para CAYLA —socios, dirección, asesores
externos— y alinear rol, área y rango con esa respuesta. Son tres campos por
persona, editables desde Equipo; ninguno cambia lo que cobran.

**✅ Decidido el 2026-08-07 y con pieza construida:** Catherine es **socia**;
Carlos y Claudia, **asesores**. La
[`0182`](../supabase/migrations/0182_el_cargo_dice_que_eres_el_rol_dice_que_abres.sql)
agrega un campo `cargo` para escribir **qué es** una persona sin tocar lo que
puede abrir — se descartó a propósito meter «socio» y «asesor» en el enum `rol`,
porque `rol` no es un cargo sino una llave de permisos. Con el cargo escrito, la
pantalla deja de llamarlos encargados y el sistema deja de armar el expediente
en contra. **Comprueba si ya está pegada** con `./scripts/que-falta-pegar.sh`.

**Lo que YA se verificó, y no hace falta volver a mirar** (2026-08-07): el
dinero está bien. A un `rxh` no se le calcula movilidad ni EsSalud (0117), ni
educación (0120), ni gratificación, CTS, vacaciones o el 9% de la Ley 30334
(0160, con la prueba `127`). Lo único que recibe es su pago base, que es lo que
se le transfiere. **No hay provisiones indebidas ni plata de más.**

### A.2.b.bis · A quien cesa se le paga dos veces el mismo mes, y de más

⚠️ **LA CAUSA YA ESTÁ CERRADA — lo que sigue abierto es dinero ya pagado.** Los
dos arreglos de código que esta sección pedía están en producción desde el
2026-08-13 (ver «Lo que ya está hecho», más abajo). Lo que queda no lo arregla
ninguna migración: es una decisión por persona. Quien lea esto en una sesión
nueva no tiene que volver a investigar el divisor.

**Medido en producción el 2026-08-10, con las dos consultas que quedan en
`scripts/sql-manual/`.** Son dos defectos distintos que se dan la mano, y
conviene no mezclarlos.

#### 1 · El divisor: la liquidación paga inflado — **S/1,097.67 en 7 personas**

`fn_planilla_calcular` reparte el sueldo mensual entre los días **del rango que
se le pida**:

```
v_dias := (p_fin - p_ini) + 1;   v_base := 6.5 * v_dias;   pago := horas * salario / v_base
```

`fn_liquidacion` (0164:103) es **la única en todo el sistema que pide un rango
parcial** — del inicio del periodo a la fecha de cese, «ni un día más». Con menos
días el divisor se encoge y el mismo trabajo se paga más. Quien cesa el día 10 de
un periodo de 31 cobra ~3× lo suyo.

El encabezado de la 0164 lo justifica con una premisa **falsa**: dice que un
rango parcial se calcula bien porque «es lo que usa la pantalla de planilla con
el periodo en curso». No lo es — la pantalla usa `fn_proyeccion_periodo`
(0105:493), que pasa el periodo **entero**; lo parcial viene de que aún no hay
marcajes, no del rango.

**Seis de siete casos cuadran al segundo decimal** con la proporción que predice
el divisor. La séptima, **Ytamar Cueva**, no: 1.53× pagado contra 1.11× que
justifica el rango. Unos S/45 vienen de otra cosa y hay que mirarla aparte.

⚠️ **La prueba 130 no puede cazarlo**: compara la liquidación contra
`fn_planilla_calcular` con el **mismo** rango parcial. Se compara consigo misma.

#### 2 · El doble registro: **S/1,145.87 en 6 personas**, periodo 28/06–28/07

`liquidacion_pagada` aparece en **un solo archivo de todo el repositorio** (la
0167). Ni `fn_planilla_calcular`, ni `fn_planilla_congelar`, ni la pantalla de
Planilla la leen jamás. La etiqueta «ya no está» es puramente visual.

Las seis dicen **«primero el periodo, después la liquidación»**: el 28/07 se
cerró el periodo con ellas dentro —habían cesado entre el 16 y el 25— y después
se pagaron sus liquidaciones, que volvían a incluir ese mismo mes.

**Si el dinero salió dos veces solo lo dice el extracto bancario.** El sistema lo
tiene registrado dos veces; eso es lo que se puede afirmar.

#### Lo que ya está hecho

Las dos cosas que esta sección esperaba **están aplicadas en producción el
2026-08-13**, comprobadas pidiéndole el `md5` a producción y no por la fecha del
commit:

- **El cartel** — la [`0210`](../supabase/migrations/0210_la_planilla_ve_la_liquidacion_que_ya_se_pago.sql)
  hace que la pantalla de Planilla diga, junto a quien cesó a mitad de mes, que
  ya cobró su liquidación: cuándo y cuánto. Sigue siendo un cartel y no una
  exclusión automática, a propósito.
- **El divisor** — salió como la
  [`0239`](../supabase/migrations/0239_la_hora_vale_lo_que_vale_el_mes_no_lo_que_dura_la_consulta.sql),
  no como la «0211» que esta tabla esperaba. `fn_planilla_calcular` ya no saca el
  divisor del rango que se le pasa: **el rango decide QUÉ entra —marcas,
  feriados— y el periodo cuánto vale la hora**. Los siete llamadores que pasan el
  periodo entero no se movieron ni un céntimo; la única llamada cuyo resultado
  cambia es la de `fn_liquidacion`.

Y el 2026-08-14 se cerró también el mecanismo, que era lo que quedaba vivo:

- **La liquidación deja de cobrar dos veces el mes** — la
  [`0243`](../supabase/migrations/0243_la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago.sql)
  le resta al sueldo del periodo lo que la foto del pago ya registra para esa
  persona. Si el periodo no está congelado no hay nada que restar y el resultado
  es idéntico al de antes, al céntimo.
- **Y la 0243 deja de pagar de menos y de atascar el cierre** — la
  [`0244`](../supabase/migrations/0244_la_0243_deja_de_pagar_de_menos_y_de_atascar_el_cierre.sql),
  seis bordes que la anterior dejó abiertos. El grave: restaba también la foto de
  un periodo **revertido**, donde el dinero nunca salió (S/1,393.27 donde tocaban
  S/2,143.27). Los otros: una foto negativa inflaba, `congelar_pendientes()`
  abortaba sobre un mes histórico, y el freno de congelar no se levantaba al
  aplicar el descuento — podía dejar el cierre del mes sin salida.

Las dos verificadas pidiendo el `md5` a producción antes y después de pegar.

El botón **«💸 Ya le pagué aparte»** (`planilla/page.tsx:1268`) sigue siendo la
vía para el periodo en curso: registra el descuento y deja el total en cero. Y
ahora la cifra que descuenta ya es de fiar, que era la objeción para no usarlo.

⚠️ **Y una trampa que costó un rechazo en producción, para quien pegue SQL acá:**
un comentario NO es inerte. El editor de Supabase trocea el script antes de
mandarlo y su troceador no ignora los comentarios, así que un delimitador de
dólar citado dentro de un `--` —escribir `do $mig$` al explicar otra migración—
parte el script por donde no es y falla con un error que apunta a otro sitio
(`relation "v_src" does not exist`). Ninguna prueba local lo caza: psql sí lee
comentarios.

#### Lo que queda por hacer

| Qué | Cuándo |
|---|---|
| **Anular la liquidación de Rufina Salvatierra**, que figura pagada y nunca se transfirió (ver abajo) | cuando esté la migración. **No hace falta antes del 28/08**: su fila ya está en S/0.00 y el cierre pasa limpio |
| **Revisar el extracto** de finales de julio para las seis, y el de agosto para ella | esta semana. Es lo único que distingue «registrado» de «pagado» |
| **Decidir persona por persona** qué se hace con lo que sí haya salido de más | después del extracto: sin él, no se sabe qué hay que decidir |

⚠️ **CUIDADO CON ESTA SECCIÓN: sus cifras son de lo REGISTRADO, no de lo
transferido.** El 2026-08-14 se descubrió cómo se rompe esa suposición.

**El caso de Rufina, que es el patrón.** Su liquidación figura pagada el 10/08
por S/1,106.82 y **ese dinero nunca salió del banco**: estaba en periodo de
prueba, no llegó a entrar a planilla, y lo único que se le pagó fue un adelanto
de S/358.73 el 06/08, fuera de planilla. Alguien apretó «Liquidación pagada» y el
sistema congeló una foto de algo que no ocurrió.

Y el importe estaba mal por partida doble: se congeló **tres días antes** de que
la [`0239`](../supabase/migrations/0239_la_hora_vale_lo_que_vale_el_mes_no_lo_que_dura_la_consulta.sql)
llegara a producción, así que salió con el divisor viejo — inflado unas 3.1
veces. Lo que de verdad ganó del 29/07 al 07/08 son **S/298.73**, leído en la
pantalla ya corregida. O sea que con el adelanto cobró S/60 de más, no mil.

**Nadie cobró de menos.** Y de lo que parece cobrado de más, el sistema solo
puede afirmar lo que tiene registrado: **si el dinero salió, lo dice el extracto
bancario y nada más**. Esa frase ya estaba escrita más arriba desde el 10-08; el
caso de Rufina demuestra que no era una cautela retórica.

### A.2.c · Los CUSPP ya están cargados — quedan dos, y dos falsos positivos

**Resuelto el 2026-08-13.** La columna estaba vacía de punta a punta el
2026-08-10; hoy tiene **15 códigos**, cargados desde la hoja del contador
(«072026 Planilla CAYLA Felipe.xlsx») con
`scripts/sql-manual/ficha_cuspp_2026-08-13.sql` — fuera de git, lleva DNI.

**Por qué importaba.** El CUSPP es el identificador de la persona dentro del
sistema privado de pensiones: es lo que permite que el aporte declarado llegue a
**su** cuenta individual y no se quede sin atribuir.

**Se emparejó por DNI y no por nombre**, y no es un detalle de implementación: en
el equipo hay **dos Ramírez Gomez**, y la hoja trae el código de Sandra Melissa.
Por nombre se le habría escrito a Lizzelott Estefany — el aporte de una a la
cuenta individual de la otra.

**Lo que falta, y es corto:** el CUSPP de **Carmen Sanándres** (LIM, Profuturo) y
de **Lizzelott Estefany Ramírez Gomez** (CCO, Integra), que no venían en la hoja.
Se piden al contador. Aparte, **Kerin Guevara** (TRU) no tiene régimen de pensión
cargado: primero eso, y si sale ONP no lleva CUSPP.

**Los dos falsos positivos de la pantalla ya están corregidos y desplegados**
(2026-08-14).
`/admin/datos-personales` le pedía «falta CUSPP» a **Catherine Pereyra** y
**Claudia Pereyra**, que cobran por **recibo por honorarios** (ver
[A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado)). Un
locador no entra al T-Registro como trabajador: ese aviso no lo podía completar
nadie, nunca — y un aviso permanente e imposible es lo que enseña a ignorar los
avisos que sí importan.

La condición vive ahora en `leCorrespondeCuspp` (`packages/shared/src/vinculo.ts`)
y no suelta en la pantalla, porque son **dos** las que preguntan lo mismo: el
aviso de ficha incompleta y la exportación del padrón al contador, que también
lleva la columna CUSPP. Escrita dos veces, la exportación habría seguido pidiendo
lo que la pantalla ya dejó de pedir. Y usa `esPrestadorDeServicios`, no un
`!en_planilla`: si el campo no viaja en el JSON, el defecto seguro es **seguir**
pidiendo el CUSPP a las veinte que lo necesitan, no dejar de pedírselo en
silencio. Ese caso está en `tests/vinculo.test.ts`.

Por el mismo motivo dejó de pedírsele a una locadora el **régimen de pensión**:
CAYLA no le retiene aporte, así que ese dato no es de la empresa.

De paso: que las dos locadoras **tengan un régimen de AFP asignado** es en sí un
indicio más de los que describe A.2.b. **Decisión de Felipe (2026-08-13): se
queda.** Después de la 0242 ese dato no alimenta ningún cálculo, y saber en qué
AFP están es información útil. No volver a proponer borrarlo.

**Sobre el CHECK que se había descartado por falta de datos:** ahora hay 16
códigos reales y los 16 tienen la misma forma —6 dígitos · 5 letras · 1 dígito—
y las 5 letras se derivan del nombre (inicial del nombre, inicial de cada
apellido, 4ª letra de cada apellido). El script lo comprueba fila por fila, y es
lo que da confianza de que ninguna se corrió al copiar la hoja. Pero **sigue sin
ponerse un CHECK**, y ahora por una razón medida y no por falta de datos: 16
casos no prueban que un CUSPP antiguo, o el de alguien con un solo apellido,
tenga esa forma. La validación vive en el script que carga, donde un rechazo se
revisa a mano; en la columna, rechazaría en silencio un código legítimo.

### A.2.c.bis · La guarda que impide retenerle AFP a un locador no está escrita

> **HOY NO CUESTA NADA.** Felipe confirmó el 2026-08-13 que a los tres locadores
> **nunca se les ha retenido AFP**, y es coherente con lo medido: su base es 0
> porque nadie les llenó `sueldo_base_legal`. Esto **no es plata mal pagada y no
> hay nada que devolver.** Es un riesgo latente, y el valor de anotarlo es que la
> protección que hoy funciona **no está escrita en ninguna parte**: funciona por
> casualidad.
>
> **✅ CERRADO. La 0242 está aplicada en producción** (2026-08-13). El md5 de
> partida se confirmó en el SQL Editor antes de pegarla, y las cinco
> comprobaciones salieron en verde: las 4 marcas nuevas puestas, la guarda de la
> base presente, y la 0239, la 0236 y la 0233 intactas. Con prueba propia
> (`supabase/tests/183_un_locador_no_tiene_base_imponible.test.sql`).

**Qué es exactamente el riesgo.** El descuento previsional es
`base imponible × tasa`, y hoy da cero para un locador porque su base es cero. Pero
la base es cero **por un dato en blanco, no porque el sistema sepa que es locador**.
El día que alguien abra su ficha en `/admin/equipo` y confirme su base legal —una
acción normal, con buena intención, en un campo que el panel pide— empieza a
retenérsele AFP en silencio. Nadie relacionaría las dos cosas.

Y hay un segundo camino, más corto: marcarle **`con_hijos`** a una locadora le paga
S/113 de asignación familiar y además le abre base para el descuento, incluso con
`sueldo_base_legal` en blanco.

**Medido el 2026-08-13** contra la función vigente (`fn_planilla_calcular`, md5
`7d67ff3c1d769ebffc3de0af20ab83fe` = 0239), con cuatro locadoras idénticas salvo
esas dos columnas. Salió de preguntarse qué hace el sistema con la AFP después de
cargar los CUSPP. Los montos de abajo son **lo que pasaría**, no lo que pasó:

A un locador no se le retiene AFP: la locación de servicios no genera retención
previsional del pagador. El encabezado de la 0193 dice que eso ya está a salvo
porque «su básica es 0». **Es cierto solo si alguien le puso `sueldo_base_legal`
en NULL a mano** — y esa columna tiene `DEFAULT 1130.00` (el RMV, 0103).

| `sueldo_base_legal` | `con_hijos` | básica | asig. familiar | **AFP retenida** |
|---|---|---|---|---|
| 1130 (el DEFAULT) | sí | 1192.09 | 113.00 | **168.62** |
| 1130 (el DEFAULT) | no | 1192.09 | 0.00 | **154.02** |
| NULL | sí | — | 113.00 | **14.60** |
| NULL | no | — | 0.00 | 0.00 |

**Son dos defectos y no se mezclan:**

1. **La básica.** El descuento de pensión es `bri.base × tasa` y es **el único
   concepto sin guarda de vínculo**. Todos los demás la llevan escrita: EsSalud y
   movilidad (0117), educación (0120), sobretasas (0193). Este descansa en que la
   base sea 0 — y lo decide el default de una columna. Que hoy funcione o no es
   una coincidencia, no un diseño.
2. **La asignación familiar.** Entra al pago **y** a la base sin condición de
   vínculo, y es la única vía que inventa base incluso con `sueldo_base_legal` en
   NULL. Aparte del descuento, cobrarla ya está mal: la Ley 25129 es para
   trabajadores del régimen laboral privado. Y es el argumento exacto de la 0117
   con la movilidad — **el concepto que protege a una trabajadora de planilla es
   el que incrimina en un RxH**. Un locador que cobra asignación familiar es un
   indicio de laboralidad más para
   [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).

**Lo que EsSalud sí hace bien:** cero en las cuatro filas. La guarda de la 0117
sigue en pie, y eso acota el problema — es previsional, no de aportes de la
empresa.

**Cómo lo arregla la 0242.** Guarda la base imponible COMPLETA —
`case when pe.en_planilla is not true then 0 else …` — y no cada término suyo, para
que un concepto que se agregue mañana quede excluido sin que nadie tenga que
acordarse; y le pone la condición de vínculo a la asignación familiar en **los dos
sitios** donde vive (el concepto del JSON y el término del `total`): arreglar solo
uno dejaría la boleta mostrando 0 mientras el total lo sigue cobrando.

Medido después de aplicarla en local: las cuatro locadoras quedan idénticas entre
sí y su total es exactamente su pago por horas — ya no depende de
`sueldo_base_legal` ni de `con_hijos`. Y **el testigo de planilla no se movió ni un
céntimo** (AFP 195.73 · asignación 113.00 · EsSalud 136.34 · provisiones 276.71,
iguales antes y después). Eso es la mitad del valor de la prueba `183`: apagarle el
descuento a un locador y de paso romperle la retención a quien sí aporta habría
sido mucho peor que el defecto original, y ninguna pantalla lo mostraría.

**Lo que sigue igual, y es deliberado:** el pago por horas de un locador. Es el
razonamiento de la 0085 que la 0117 repitió — medir horas para saber cuánto pagar
es medir un RESULTADO; fiscalizar una CONDUCTA es la prueba de subordinación.

**Para volver a medirlo en dos segundos cuando haga falta:**
[`que_pasa_con_la_afp.sql`](../scripts/sql-manual/que_pasa_con_la_afp.sql). Su
BLOQUE 2 no rehace la aritmética, le pregunta a `fn_planilla_calcular` por el
periodo vigente y devuelve una fila por cada locador con retención. Lo esperado
—y lo que Felipe ya confirmó por su lado— es **cero filas**. Queda escrito con la
consulta al lado por la misma razón que A.2.d: un riesgo latente sin forma de
volver a medirlo es una frase que envejece sola.

### A.2.d · Dos campos para «¿tiene hijos menores?» — uno paga y el otro declara

**Medido el 2026-08-10: hoy no cuesta nada.** De las 21 personas activas en
planilla, las 21 concuerdan. Cero desacuerdos, cero fichas sin el dato. Esto
queda escrito como riesgo latente, no como pendiente urgente — y con la consulta
que lo vuelve a medir en dos segundos:
[`los_dos_campos_de_hijos_no_se_hablan.sql`](../scripts/sql-manual/los_dos_campos_de_hijos_no_se_hablan.sql).

| Campo | Quién lo escribe | Qué hace |
|---|---|---|
| `personas.con_hijos` (0025) | pantalla de **Equipo**, con `fn_set_con_hijos` | **decide el pago** de los S/113 en `fn_planilla_calcular` |
| `datos_personales.hijos_menores` (0061) | pantalla de **Datos personales** | **es lo que sale en el padrón** al contador |

**Nada los mantiene de acuerdo.** Ninguna migración menciona los dos a la vez;
ninguna pantalla escribe los dos. Comprobado con `grep` sobre
`supabase/migrations` y sobre `apps/web`. Que hoy concuerden es mérito de quien
los ha ido llenando a mano, no del sistema.

Lo que puede pasar el día que se despisten: marcar «sí tiene hijos» en la ficha,
que el padrón se lo declare al contador, **y que la planilla abone S/0** porque
`con_hijos` se quedó en su `false` por defecto. O al revés — cobrar los S/113
mientras el papel que emite la empresa dice que no corresponden.

⚠️ **Y ojo con el arreglo fácil.** Fusionarlos en un solo campo toca el cálculo
de planilla, así que va con auditoría empírica contra el Postgres local en
`BEGIN … ROLLBACK`, como manda el `CLAUDE.md`. Lo barato y sin riesgo mientras
tanto sería que la pantalla de Datos personales **avise** cuando los dos
difieran: ya tiene dos comprobaciones cruzadas de esa forma exacta —cobra
asignación sin hijos registrados, y su inversa— y ninguna mira `con_hijos`.

*(De aquí salió también el arreglo del padrón que ya está hecho: imprimía «NO»
donde la verdad era «no se sabe». Ver `siNoSinDato` en
`packages/shared/src/labels.ts`.)*

### A.3 · Datos que hacen falta para seguir

**0) Nadie tiene contacto de emergencia — las 25, sin una sola excepción.**
Medido el 2026-08-07 con
[`que_falta_en_las_fichas.sql`](../scripts/sql-manual/que_falta_en_las_fichas.sql).
Si alguien se corta con una máquina en el taller de Lima o se descompensa en
tienda, **no hay a quién llamar**, y ese es el único momento en que el dato
sirve. Felipe los carga desde `/admin/personas`. En la misma pasada faltan **13
celulares** (decisión suya: van después) y la **fecha de nacimiento de Janis
Revilla**, sin la cual su bono de onomástico no se dispara nunca — la única del
equipo a la que le falta.

Las 20 de planilla están completas en lo que toca a plata: banco, cuenta,
documento y nombre legal. Lo que falta es todo del lado de **poder contactarlas**.
Corre la consulta para ver cómo va; ordena por quién tiene más huecos.

**0-bis) Tres correos hay que corregir a mano** (medidos el 2026-08-10 con
[`mediciones_antes_de_validar.sql`](../scripts/sql-manual/mediciones_antes_de_validar.sql)).
Quiénes son lo dice
[`quien_tiene_el_correo_mal.sql`](../scripts/sql-manual/quien_tiene_el_correo_mal.sql),
que además dice **dónde** se corrige cada uno — con cuenta creada el correo es
el usuario de acceso y la ficha no lo puede tocar, así que va por
`/admin/cuentas`.

- **Uno no tiene forma de correo.** Esa persona figura como ficha completa, sale
  así en el padrón que va al contador, y al intentar invitarla el sistema
  responde «no tiene correo registrado» — que es falso: lo tiene, mal escrito.
  Son dos estados distintos y la pantalla los confundía.
- **Dos están guardados con mayúsculas.** La pantalla ya no falla por eso (se
  comparaba en minúsculas contra el valor crudo, así que daba «cambió» para
  siempre y cada guardado terminaba en un error rojo y falso), pero el dato
  sigue en mayúsculas. Bajarlo va en migración, no en un `update` pegado a mano:
  un correo que es un login tiene consecuencias que hay que dejar escritas.

**Y lo que la misma medición descartó, para no volver a mirarlo:** ni un
documento sin dígitos, ni uno fuera del patrón que ya exige la 0125, ni una
cuenta bancaria con letras, ni un valor de `estado_civil` o
`grado_instruccion` fuera de `enums.ts`, ni una sede huérfana en
`parametros_laborales`. Los agujeros de validación que quedan son **teóricos
hoy**; valen por lo que impiden mañana, no por lo que haya guardado.

**a) Quiénes estudian y cuánto cuesta su curso** (del tipo `aurora 1 →
universidad S/520`). Con el nombre y el monto alcanza; se cargan de a uno en
`/admin/educacion` o con
`cargar_educacion_v2.sql`, que pide el nombre y no un UUID. **Es la única de las
tres compensaciones que se puede destrabar hoy sin escribir una línea de
código** — `asignaciones_educacion` sigue vacía.

**b) La fecha de acreditación de CAYLA en el REMYPE.** Decide si queda algún
frente abierto de asignación familiar: quien haya ingresado antes de esa fecha se
rige por el régimen general, donde sí es exigible. La persona más antigua ingresó
el **2025-01-02**, así que si la acreditación es anterior, el frente es **cero**.

**c) El refrigerio real**, que deja el sustento de la movilidad atado a tus datos:

```sql
with dia as (
  select m.persona_id, (m.timestamp_marca at time zone 'America/Lima')::date as f,
         min(case when m.tipo = 'salida_almuerzo'  then m.timestamp_marca end) as sale,
         min(case when m.tipo = 'retorno_almuerzo' then m.timestamp_marca end) as vuelve
  from marcajes m
  where m.anulada_at is null and m.timestamp_marca >= now() - interval '90 days'
  group by 1, 2
)
select count(*) as dias_con_marcas,
       count(*) filter (where sale is not null and vuelve is not null) as dias_con_4_traslados,
       round(avg(extract(epoch from (vuelve - sale)) / 60) filter (where vuelve > sale)) as refrigerio_min,
       count(*) filter (where extract(epoch from (vuelve - sale)) / 60 >= 60) as dias_1h_o_mas
from dia;
```

### A.4 · Las dos comprobaciones de datos, que ahora se responden solas

*Acá había cuatro nombres escritos a mano. Tres cerraron y uno resultó ser una
decisión (ver [`historico.md`](historico.md)). Lo que queda son las dos preguntas
de fondo, convertidas en consultas: una lista de nombres envejece, una consulta
no.*

**¿Alguien inactivo conserva salario vigente?** Es plata que puede pagarse a
quien ya no trabaja. Debe devolver **cero filas**:

```sql
select p.nombres || ' ' || p.apellidos as persona, p.estado,
       a.salario_mensual_soles as salario_vigente, a.vigente_desde
from personas p
join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
where p.estado <> 'activo'
order by p.apellidos;
```

**¿Alguien en planilla lleva un mes sin marcar?** Puede ser vacaciones, permiso,
o que no esté marcando y nadie lo haya visto:

```sql
select p.nombres || ' ' || p.apellidos as persona, s.codigo as sede,
       max(j.fecha) as ultimo_dia_marcado
from personas p
join sedes s on s.id = p.sede_base_id
left join jornadas j on j.persona_id = p.id and j.entrada_ts is not null
where p.estado = 'activo' and p.en_planilla and not p.sueldo_fijo
group by 1, 2
having max(j.fecha) is null or max(j.fecha) < current_date - 30
order by 3 nulls first;
```

**~~El hueco de numeración 0108~~ — ✅ cerrado.** Los cinco huecos (0031, 0033,
0108, 0133, 0139) están investigados y explicados uno por uno en
[`scripts/hooks/huecos-conocidos.txt`](../scripts/hooks/huecos-conocidos.txt), y el
hook solo avisa de los que **no** estén ahí. La 0108 se descartó: su contenido lo
cubren la 0111, 0117, 0118, 0122, 0142 y 0150, y lo único exclusivo que tenía era
un `fn_planilla_calcular` del 29/07 con tarifa única de S/6 — fusionarlo habría
revertido ocho migraciones de planilla. Se recupera con
`git checkout 1b54c02 -- supabase/migrations/0108_*.sql` si algún día hace falta.

**~~El rango `caylo` pagaba educación sin techo~~ — ✅ cerrado el 2026-08-06.**
La 0140 lo retiró del catálogo por un solo lado: le borró el techo y lo dejó
fuera de `categorias_laborales`, pero los CHECK de dos tablas lo seguían
aceptando y el desplegable de Equipo lo seguía ofreciendo. Como
`fn_educacion_respeta_el_tope` «falla abierto a propósito» cuando no encuentra
techo, en vez de bloquear **pagaba**: con el comprobante de S/727, S/545.25 en
vez de S/180. La [`0178`](../supabase/migrations/0178_caylo_deja_de_poder_asignarse.sql)
lo sacó de los dos CHECK y reasigna a `cayla` a quien lo tenga (mismo nivel,
misma base, **no cambia lo que cobra**). Felipe la pegó y verificó los dos CHECK.
La pantalla ya está en producción: el desplegable ofrece seis rangos, sin `caylo`.

*Queda un SELECT por correr, y no urge:* si alguien **estaba** en `caylo`, la
0178 lo pasó a `cayla` en silencio y conviene decírselo — cobra igual, pero su
nivel se llama distinto en la boleta. La consulta está en la cabecera de
`aplicar_0178.sql`; busca el rastro en `correcciones_auditoria`.

**Lo que esto dejó como lección, y vale más que el arreglo:** el agujero no fue
que `caylo` existiera, fue que existiera **sin techo cargado**. La prueba
[`139`](../supabase/tests/139_caylo_deja_de_poder_asignarse.test.sql) no vigila
`caylo`: compara el CHECK contra `categorias_laborales` y exige que ninguna
categoría se quede sin techo. **Pero solo en CI.** `fn_educacion_respeta_el_tope`
sigue fallando abierto en producción, así que una categoría nueva cargada sin su
techo repite esto exacto. Está sin decidir si esa función debe pasar a bloquear.

---

## B · Lo que falta construir

| Qué | Bloqueado por |
|---|---|
| **Las bases declaradas** de los cuatro rangos altos — y hay que bajar **los dos campos**, `sueldo_base_legal` **y** `salario_mensual_soles` | confirmar los montos finales |
| **Cargar las declaraciones de ruta firmadas** | **de Felipe. Plazo: 28/08/2026.** El sitio donde subirlas ya existe |
| **Indicador del umbral de 20 trabajadores** — promedio corrido del ejercicio, con aviso al acercarse | nada. **Acordado: se construye después de cerrar el Seguro de Vida Ley** |
| **Versionar la RMV a S/1,300** cuando se publique el decreto | que salga la norma |
| **Generador de contratos** — los tres conceptos tienen que estar en el contrato de trabajo | nada, pero no existe la pieza |

### La 0128 sigue escrita y sin llamar

`fn_fijar_base_declarada(rango, monto, vigencia, omitir[])` baja **los dos**
campos que intervienen en el pago al mismo monto, versionando el salario vía
`fn_set_salario`. La migración **crea la función y no la llama**: crearla no mueve
ningún pago, llamarla sí.

**Las bases acordadas:** colibrí y cayla/caylo 1,130 · support 1,290 · aurora
1,500 · oráculo 1,810 · archicaylo 2,670. Dos excepciones nominales viven en
`scripts/sql-manual/aplicar_0128.sql` (ignorado en git por PII).

**Por qué no se ha llamado.** La baja de salario la compensan movilidad +
educación + bono, y van **1 de 3**: movilidad ✅ encendida · educación 🟡 la
pantalla está, falta el dato · bono ❌ decidido en S/180, sin implementar.

Medido contra Postgres local: bajar cayla de 1,450 a 1,130 le quita **S/367.37**
en el periodo 29/07–28/08. Y como la educación es **por persona y contra
comprobante**, a quien no estudia bajarle la base le recorta el sueldo sin nada
que lo reponga — para esa persona se usa `p_omitir`, o una base propia más alta.

### El indicador del umbral de 20, y por qué vale construirlo

Dante zanjó las utilidades para 2025 y 2026, pero con una foto: 5 y 13 de
promedio. Ese 13 es un accidente del año de crecimiento —de enero a junio hubo
entre 5 y 8 personas, y recién desde julio hay 19—. **Si CAYLA mantiene 19 los
doce meses de 2027, el promedio de 2027 es 19.** A una contratación del umbral.

Y la persona número 21 no cuesta su sueldo: cuesta su sueldo **más el 8% de la
renta imponible de todo el ejercicio** repartida entre todos (D.L. 892,
comercio). Sobre los S/63,655 de 2025 serían ~S/5,092 al año que hoy no se ven en
el momento de decidir la contratación. El sistema tiene todos los datos para
calcularlo solo y mostrarlo **antes** de que se firme el contrato.

### Sobre la RMV

El alza se anunció el 28/07/2026 y **el decreto no está publicado**. Cuando
salga, son dos sentencias por cada clave —`rmv` y `asignacion_familiar`— escritas
en las cabeceras de la 0116 y la 0122. Los periodos ya pagados quedan intactos.

⚠️ **Ojo con el plazo, porque Dante lo describió mal.** Dijo que hay que esperar
al Congreso y a la promulgación. La RMV **no se fija por ley**: se fija por
**Decreto Supremo del Ejecutivo**, previa consulta al Consejo Nacional de
Trabajo, conforme al art. 24 de la Constitución (la subida a S/1,130 fue el
**D.S. 006-2024-TR**). Puede publicarse de un día para
otro y regir desde el 1° del mes siguiente. **La vigilancia se mide en semanas,
no en meses.** Donde sí puede tener razón es en el bono compensatorio para MYPE:
eso es gasto público y probablemente sí necesita norma con rango de ley.

### La fila general de movilidad vale S/ 10.00 — decisión tomada, se queda

No es un descuido pendiente sino una **red deliberada** (Felipe, 2026-08-06):
quien esté en una sede sin tarifa propia cobra S/ 10.00 en vez de cero. Conviene
saber de dónde sale ese 10: es la **tarifa original de Trujillo** —su sustento lo
dice, «colectivo urbano de Trujillo a S/2.50 por tramo»—, que quedó sin
`vigente_hasta` cuando la 0142 abrió las filas por sede.

**El escenario que la activa: abrir una sede nueva.** Esa gente cobra S/ 10.00
desde el primer día sin que nadie haya mirado el pasaje de esa ciudad, y sin
aviso. Si algún día se prefiere que un dato faltante se note en vez de
rellenarse, se cierra con `vigente_hasta` y pasan a S/ 0.00 — hoy eso no movería
la plata de nadie.

---

## C · Lo que se descartó y no vuelve

Cinco cosas que sonaron graves y se cayeron al verificarlas. Quedan acá para que
no vuelvan a costar tiempo.

| Se dijo | La verdad |
|---|---|
| El límite del RER de 10 trabajadores por turno | **CAYLA está en Régimen MYPE Tributario** desde 2023 (ficha RUC). El RER no aplica. **No hay que mover ningún horario** |
| «Sobre 25% de conceptos no remunerativos se activa la presunción de salariedad» | **No existe ese umbral en la ley.** Era una regla de dedo mía |
| La asignación familiar se debe a todos los que tengan hijos | El régimen de **pequeña empresa NO la incluye** — las palabras aparecen cero veces en el TUO de la Ley MYPE y en la Ley 32353, leído en texto primario. **Pero a quien ya la cobra no se le puede quitar**: sería reducción unilateral de remuneración (art. 30.b) |
| Un pacto colectivo blinda la movilidad | Solo es requisito del inciso g) para festividades. Art. 9 TUO CTS: la denominación es irrelevante. **La firma no blinda, incrimina** |
| El SCTR es obligatorio por el taller | **No.** Se revisaron las 270 actividades del Anexo 5: la confección de prendas (CIIU 141x) no está. Evita S/1,600–2,500/año de un seguro que nadie exige |

**Y el techo que ordena todas las multas:** todas las de una misma inspección de
SUNAFIL topan en el **1% de los ingresos netos del año anterior** (art. 48.1-A del
Reglamento de Inspección). Con ~S/900,000 de facturación el techo es **~S/8,000**,
no las seis cifras que suman los hallazgos por separado. **Pero no se aplica
solo**: exige presentar la constancia de REMYPE y sustentar los ingresos netos.
Sin esos dos papeles se cobra el nominal.

---

## D · Consultas útiles que ya existen

| Archivo | Para qué |
|---|---|
| `revision_completa.sql` | 15 comprobaciones de las migraciones 0115–0122 |
| `encender_movilidad.sql` | Encender la tarifa, en transacción y con verificación |
| `cargar_educacion_v2.sql` | Cargar una asignación por nombre, sin copiar UUID |
| `huella_del_esquema.sql` | **¿Producción dice lo mismo que el repositorio?** Una fila: funciones, candados, columnas, y si queda texto con acentos rotos. Empieza siempre por aquí |
| `que_funcion_cambio.sql` | Solo si la anterior dice que las funciones difieren **con el mismo conteo**: manda las 199 huellas y señala cuál |
| `rescatar_lo_que_solo_vive_en_produccion.sql` | ⚠️ **Léelo antes de tocar cualquiera de las nueve que lista.** Trae su código para traerlo al repositorio |

**Y el prólogo que hace falta seguido:** `fn_planilla_calcular`, `fn_provisiones`
y `fn_set_tipo_vinculo` exigen sesión de admin, y el SQL Editor no la tiene. Dos
líneas al inicio lo resuelven:

```sql
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and nombres ilike '%Felipe%' and auth_user_id is not null limit 1),
  true);
```

---

## El diseño remunerativo — lo que la auditoría empírica fijó

Contra Postgres local con datos reales, en `BEGIN … ROLLBACK` como manda el
`CLAUDE.md`. **Sigue siendo la base del diseño, no es historia.**

**`pago_base` se calcula sobre `asignaciones_salario.salario_mensual_soles` —el
rango completo— y NO sobre `personas.sueldo_base_legal`:**

```
pago_base = horas × salario_mensual_soles / v_base
basica    = horas × least(sueldo_base_legal, salario) / v_base
```

**Declarar menos NO reduce lo que se paga.** Sumar movilidad, educación y bono
encima del rango completo sobrepagaría por el monto entero de esos conceptos —
del orden de **S/4,900 al mes** entre las 26 personas. Por eso al fijar las bases
declaradas hay que bajar **los dos campos** al mismo monto.

Con esa corrección, en un mes **sin feriados**:

| Rango | declarado → base | + movilidad | − pensión | = total | objetivo | necesita educ. + bono |
|---|---|---|---|---|---|---|
| colibrí | 1,129.55 | +270.00 | −147.52 | 1,252.03 | 1,320 | **67.97** |
| cayla | 1,129.55 | +270.00 | −160.54 | 1,352.01\* | 1,450 | **97.99** |
| support | 1,289.49 | +270.00 | −167.25 | 1,392.24 | 1,650 | **257.76** |
| aurora | 1,499.40 | +270.00 | −194.92 | 1,574.48 | 1,890 | **315.52** |
| oráculo | 1,809.28 | +270.00 | −232.31 | 1,846.97 | 2,250 | **403.03** |
| archicaylo | 2,668.94 | +270.00 | −348.56 | 2,590.38 | 3,000 | **409.62** |

*\*La fila de cayla del fixture tiene hijos, así que incluye S/113 de asignación
familiar; sin hijos necesitaría ~S/198.*

**Los días son 27, no 26.** En un periodo de 31 días con domingos libres hay 27
laborables, así que la movilidad a S/10 da **270**, no 260.

**Los feriados oscilan el total entre S/90 y S/196 por mes.** Por eso el diseño
**no puede cerrar exacto todos los meses**, y forzarlo con educación o bono sería
el reverse-engineering que hunde los conceptos (caso Albis). Cada concepto se fija
por su propio mérito y el total aterriza cerca del rango.

### Las decisiones del diseño (2026-07-31)

**En la boleta:** lo que CAYLA paga además —el EsSalud y las tres provisiones— va
en un bloque aparte, fuera de la tabla del pago, con la leyenda «no se descuenta
de tu sueldo». **Sin total y sin porcentaje**, por decisión tomada.

| Concepto | Decisión | Amparo |
|---|---|---|
| **Movilidad** | S/10.00 por día marcado en AQP y TRU, **S/12.00 en LIM** (0142) · 4 traslados · refrigerio de 1h15 habilita almorzar en casa. **Techo: ninguna tarifa diaria pasa del 4% de la RMV** (hoy **S/45.20**), con candado en la 0152 y prueba 119 | Art. 19 e) · PLAME **0909** ✅ confirmado |
| **Educación** | 75% del comprobante, tope por rango · vale para el trabajador **y/o sus hijos**, sin tope de edad | Art. 19 f) · PLAME **0202** ⚠️ falta confirmar el cero |
| **Bono cumpleaños** | **S/180**, igual para los 26, en el mes del onomástico, sin condición de antigüedad | Art. 19 g) · PLAME **0203** ⚠️ mismo caso |
| **Pensión** | Tasa real por persona (12.84%–13.06% u ONP 13%), desde el periodo abierto | — |
| **EsSalud** | 9% con piso de la RMV, visible como aporte de la empresa | Ley 26790 art. 6 |
| **Base de beneficios** | Igual al monto declarado de cada persona | decisión de Felipe |
| **Fuera de la estructura** | Felipe y Catherine | decisión de Felipe |

**La cláusula del bono, textual.** No usar la que decía «gratificación
extraordinaria a título de liberalidad»: invocaba el inciso a), que exige que el
pago sea *ocasional*, y hacía el gasto **no deducible** (art. 44 d) LIR).

> *Asignación por cumpleaños, otorgada con ocasión del onomástico del trabajador,
> conforme al literal g) del artículo 19 del D.S. 001-97-TR. No constituye
> remuneración computable para ningún efecto legal.*

**Sobre los convenios:** la **RTF 05449-4-2007** desconoció la movilidad de 14 de
21 trabajadores por falta de convenio exhibido. El inciso e) nombra el «pacto
individual» como la vía del monto fijo. La sentencia para encender la tarifa, con
su memoria de cálculo completa, está en la cabecera de la 0118.

**El candado de la declaración NO está encendido.** Cuando el tablero esté
completo:

```sql
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('movilidad_exige_declaracion', 1, '<fecha>', '<por qué>');
```

---

## Correcciones a información que yo di mal

Quedan anotadas porque se tomaron decisiones sobre ellas.

| Lo que dije | Lo correcto |
|---|---|
| «El límite del RER de 10 trabajadores por turno es tu problema más caro» | **CAYLA está en Régimen MYPE Tributario desde 2023** (ficha RUC). El RER no aplica |
| «Sobre 25% de conceptos no remunerativos se activa la presunción de salariedad» | **Era mi regla de dedo, no una norma.** No existe porcentaje en la ley peruana |
| La cláusula del bono con «liberalidad» y «a discreción» | Invocaba el inciso a), que exige ocasionalidad, y hacía el gasto no deducible |
| «Ninguna función respeta `en_planilla`» | **Las de liquidación sí:** `fn_cts_trunca`, `fn_grati_trunca` y `fn_vacaciones_truncas` vía `fn_devenga_beneficios` |
| «Un pacto colectivo blinda la movilidad» | Solo es requisito del inciso g) para festividades. **La firma no blinda, incrimina** |
| «CAYLA es un instituto de idiomas» *(en un prompt de verificación)* | Es **CIIU 4641 — venta al por mayor de textiles**. Se descartó todo el análisis de IGV educativo que salió de ahí |
| «El problema de subir el cargo es que la URL firmada no lleva la identidad» | **Falso.** Era que Storage usa `ON CONFLICT … RETURNING` y faltaban dos políticas. Afirmado con más seguridad de la que había; lo destapó el log del contenedor, no el código |

---

## Notas del entorno

**Las pgTAP corren en esta Mac.** La clave es `db reset`, no `start`:

```bash
npx supabase db reset    # reconstruye desde cero y aplica TODAS las migraciones
npx supabase test db
```

Es la mejor verificación de una migración nueva —construye el esquema entero
desde cero— y la única forma de detectar una colisión de números: es lo que
destapó las dos `0158`, abortando con `duplicate key value violates unique
constraint "schema_migrations_pkey"`.

**`db reset` y no `db start`:** `db start` no reaplica nada si la base ya está
levantada, así que una migración nueva parece aplicar y en realidad no se probó.

**`supabase start` (el stack completo: Auth, Storage, Realtime) también
funciona** — comprobado el 2026-08-06. Hace falta para probar una subida de
archivos de punta a punta; sin él, Storage no responde y solo se puede simular
contra Postgres.

**Si las pruebas fallan todas a la vez con «relation "sedes" does not exist»**,
no es el código: el contenedor de Postgres se reinició vacío. Se arregla con `db
reset`. La base local es un laboratorio: no guarda nada que no se pueda
reconstruir.

⚠️ **Casi siempre hay varias sesiones trabajando en paralelo** — el 2026-08-06
había cinco además de la propia. Unas desde `.claude/worktrees/*`, y otras
**desde este mismo árbol**: comparten Postgres local, directorio de trabajo e
índice de git. Eso produce pruebas en rojo que no son tuyas, `estado.md`
reescrito a media edición, y un `git status` que dice `[ahead 2, behind 5]` y un
minuto después otra cosa.

```bash
./scripts/sesiones.sh
```

Dice cuáles están vivas, desde qué worktree, **cuál es la tuya**, si alguien
escribió en los últimos 10 minutos y el estado de la rama. Córrelo **antes** de
`supabase db reset`, de editar este archivo, o de fiarte de un `git status`.

No uses la lista de sesiones de la app: su campo `isRunning` dice `false` aunque
estén corriendo. El script mira los procesos del sistema, que no mienten.

Dos hábitos que se ganaron el 2026-08-06:

- **Commitea con `git commit -o <ruta>`.** El índice de git es compartido en este
  árbol: un `git add` + `commit` corriente puede llevarse dentro lo que otra
  sesión acabe de preparar.
- **No empujes si la rama lleva commits que no son tuyos.** Viajarán cuando su
  autor los empuje; publicarlos tú es publicar trabajo a medio hacer.

**Los dos guardianes que fallaban por esto ya están arreglados** (2026-08-06), y
los dos por la misma confusión — preguntaban por *el directorio de trabajo*
cuando debían preguntar por *lo que sale de esta máquina*:

| Guardián | Qué hacía mal |
|---|---|
| `scripts/hooks/numeracion.sh` | Listaba las migraciones con `ls`, así que los archivos sin commitear de otra sesión contaban como tuyos: te decía «renumera lo tuyo» por un choque que tu push ni llevaba. Ahora mira lo que agregan tus commits sobre `origin/main`. La comprobación de duplicados **sigue** mirando el árbol entero a propósito: dos archivos con el mismo número revientan tu `db reset` venga de donde venga el segundo |
| `scripts/desplegar.sh` | Frenaba por cualquier cosa sin commitear, incluidos `.sql` que el `.vercelignore` excluye — Vercel ni los sube, y el mensaje «subiría código que no está en git» era literalmente falso. Ahora lee el `.vercelignore` para decidir qué cuenta. Sigue frenando en seco si lo sin commitear es `apps/web` |

Vale la pena mirar con esa lente cualquier verificación nueva antes de
escribirla: **¿esto pregunta por lo que hay en el disco, o por lo que va a
salir?** Casi siempre es lo segundo.

**Queda un tercero con el mismo vicio, y por ahora se aguanta.** El `typecheck`
del pre-push compila el **directorio de trabajo**, no lo que subes: el 2026-08-08
frenó un push por un archivo `.tsx` que otra sesión tenía a medio editar, y al
minuto siguiente pasó sin tocar nada. Es falsa alarma, no error — se reintenta y
ya. Arreglarlo de verdad exigiría compilar contra un árbol aislado, que cuesta
más de lo que ahorra; lo que no se puede es olvidar por qué pasa y empezar a
empujar con `--no-verify`.

**El de `que_falta_pegar.sql` sí es de los buenos, y frenó dos veces el mismo
día:** el repo tenía migraciones que la consulta no listaba, así que le habría
dicho a Felipe «todo al día» ocultando justo las nuevas. Se arregla corriendo
`./scripts/que-falta-pegar.sh` y volviendo a empujar.

**Un bug que vale recordar:** `jsonb_build_object` admite **máximo 100
argumentos**. El objeto de la boleta estaba cerca del techo y cuatro campos
nuevos lo pasaron — compilaba y fallaba al ejecutarse. Ahora está partido en dos
unidos con `||`, y el generador cuenta los argumentos y falla si alguno se acerca
al tope.

---

## 🔴 Atender primero

0. **El freno del SQL a producción se puede saltar sin querer, y ya pasó dos
   veces.** El 2026-08-14 la **0243** —que cambia una liquidación por cese— quedó
   aplicada en producción con sus tres archivos **sin commitear**: el mismo estado
   exacto en el que se encontró la **0177** el 2026-08-07. Se rescató el mismo día.

   **`dame-el-sql.sh` no lo evitó, y no puede:** solo protege a quien lo usa. Si
   la migración se copia del editor —lo natural cuando la tienes abierta delante—
   el script no participa, y ni el hook de numeración ni `que-falta-pegar.sh` ven
   nada, porque los dos miran git. El agujero no está en el script: está en que
   **el camino cómodo no pasa por él**.

   **✅ La mitad barata ya está hecha** (2026-08-14):
   `scripts/hooks/migracion-sin-guardar.sh` avisa en cada push si hay una
   migración sin commitear, y distingue la recién escrita de la que **ya
   sobrevivió a un commit** — esa segunda no es trabajo en curso, es trabajo
   olvidado. No bloquea, por la regla que el propio hook ya tenía escrita para
   `types.ts`: lo que sale de la máquina se bloquea, lo que solo está en el disco
   se avisa. Con varias sesiones en paralelo, una migración a medio escribir es un
   caso legítimo constante, y frenar ahí repetiría los dos errores ya pagados
   (`desplegar.sh` el 2026-08-06 y `que-falta-pegar --check`, cuatro pushes en un
   día). Cinco casos probados, incluido el que cazó un `git add` con las rutas
   pegadas sin espacio — justo la línea que existe para copiarse.

   **Queda la mitad cara, y es la que de verdad cierra el agujero:** que
   `que_falta_pegar.sql` compare lo que `migraciones_aplicadas` dice **en
   producción** contra lo que hay **en GitHub** —no en el disco—, de modo que una
   migración aplicada y no subida salga como hallazgo desde el lado autoritativo.
   El aviso del hook depende de que alguien empuje; esto no dependería de nada.

1. **Julio: nadie tuvo descuento de pensión.** Medido el 2026-08-08 sobre el
   periodo 28-jun → 28-jul: `pension_descontada` = **S/0.00 para las 23
   personas**, y `con_tasa_de_pension` = 0. En agosto ya son 20 de 22, así que
   las tasas por régimen se cargaron entre un periodo y otro.

   **Es del contador, no del código, y hay que preguntárselo:** si él descontó
   por su lado, no pasa nada; si no, es un mes de aporte previsional sin hacer
   para todo el equipo. Pesa más que cualquier otra cosa abierta hoy — y CAYLA
   es agente de retención, así que una retención no hecha la termina pagando la
   empresa de su bolsillo.

2. **Veinte de los veintiún contratos vencen el 31 de diciembre de 2026.** Solo
   el de Paola termina antes. En una misma semana hay que decidir, redactar y
   firmar veinte renovaciones, y si una se pasa de fecha con la persona todavía
   trabajando, **el contrato se desnaturaliza a indefinido por el art. 77 del
   D.S. 003-97-TR** — no por decisión de nadie.

   El dato ya está en `personas.fecha_fin_contrato`; falta que Incidencias avise
   con antelación. Es una alerta chica, del mismo tipo que las de jornada.

3. **El terminal decide en dos sitios a la vez.** «Qué toca marcar ahora» vive en
   SQL (`fn_siguiente_tipo_esperado`) y en el navegador
   (`determinarSiguienteAccion`, `packages/shared`). Las dos ignoran ya las
   marcas anuladas, pero **arreglar una dejaba la otra rota** y nada avisa de la
   divergencia. Unificar, o al menos una prueba que compare las dos respuestas
   con los mismos datos y falle si difieren.

4. **Terminal, los «4 bordes graves» — reproducidos uno por uno el 2026-08-10.
   Tres de los cuatro no eran lo que decían.**

   | Borde | Veredicto medido |
   |---|---|
   | Marca rechazada anunciada como «Listo» | ✅ **era real a medias, y se arregló.** La cola ya guardaba la marca antes de enviar; lo que seguía mal era el CARTEL: la pantalla leía solo `ok` y tiraba `llego`, así que un rechazo del servidor se anunciaba igual que estar sin internet — «se sincronizará cuando vuelva la conexión», siendo mentira. |
   | Cola offline reenviada por UUID | ❌ **refutado.** `offline-db.ts:85` ordena por `timestampCliente`. |
   | Reloj de la Mac sin verificar desfase | ✅ **REAL Y ABIERTO.** Cero menciones de desfase en todo el terminal: el `timestamp_marca` que decide a qué día se paga sale del reloj de la Mac sin comprobar nada. Necesita decidir qué se hace cuando está corrido. |
   | Marca en dos sedes el mismo día «pierde una marca» | ⚠️ **exagerado.** No se pierde ninguna —`marcajes` es append-only— pero `fn_recalcular_jornada` hace `coalesce(v_sede_id, …)` y le atribuye el día entero a la sede donde marcó PRIMERO. Lo que sale mal es el Reporte por sede, no el pago. |

   Y el quinto que se miró de paso, `fn_auto_cierre` sin candado de periodo
   pagado: ❌ **refutado**, lo cerró la 0203 el mismo día.

5. ~~**Tardanza de más de 180 min invisible**~~ · ~~**el sistema mide la jornada
   de quien no está sujeto a horario**~~ — ✅ **los dos cerrados el 2026-08-08**
   por la [`0189`](../supabase/migrations/0189_una_tardanza_de_tres_horas_deja_de_desaparecer.sql)
   y la [`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql),
   aplicadas y confirmadas. Ver el apartado [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado)
   para lo que significaba el segundo.

6. ~~**Nueve funciones y dos columnas corren SOLO en producción**~~ — ✅ **cerrado
   el 2026-08-08.** La 0188 rescató cuatro; la
   [`0194`](../supabase/migrations/0194_el_interruptor_de_beneficios_por_persona_entra_al_repositorio.sql)
   y la [`0195`](../supabase/migrations/0195_las_cuatro_funciones_que_el_repositorio_no_conocia.sql)
   las cinco restantes. Aplicadas y confirmadas. Verificado con un `db reset`
   completo: reconstruida la base solo desde los archivos, todo sigue ahí.

   **Y lo que apareció al rescatarlas vale más que el rescate.** Lo que esas
   cuatro funciones tenían «de más» era **el candado de planilla pagada** que el
   repositorio no tenía: `fn_set_rendimiento` y `fn_quitar_rendimiento` se niegan
   a puntuar o despuntuar un mes ya pagado, y `fn_set_sueldo_base_legal` a
   cambiar la básica de quien tenga meses pagados con puntuación menor a 100.
   Cualquier migración que hubiera copiado del repositorio los habría borrado en
   silencio — lo mismo que la 0180 tuvo que reponer el mismo día.

   ⚠️ **EL INTERRUPTOR DE BENEFICIOS POR PERSONA NO ESTÁ CONECTADO.** Medido en
   producción, no deducido: `funciones_que_lo_leen: 0`.
   `fn_devenga_beneficios(p_tipo)` tiene como cuerpo entero
   `select p_tipo = 'planilla'` — mira el **tipo de vínculo**, no la columna — y
   sus cuatro consumidores la llaman con el tipo. La pantalla de Equipo dice que
   el interruptor funciona y **no hace nada**. Quien lo haya apagado para alguien
   verá a esa persona seguir acumulando CTS, gratificación y vacaciones.
   Compruébalo con
   [`quien_uso_el_interruptor.sql`](../scripts/sql-manual/quien_uso_el_interruptor.sql).

   **Conectarlo es decisión de Felipe: es dinero.** Y antes hay un problema de
   forma: `devenga_beneficios` es **un solo booleano** para los tres beneficios a
   la vez, y la decisión sobre Carlos Espejo —«grati y CTS sí, vacaciones no»— no
   cabe ahí. O se parte en tres banderas, o va por otro camino.

5. **Seguridad pendiente** (de `revision-2026-07-15/`):
   - Contraseña mínima 6 sin complejidad, sin cambio forzado en primer login —
     y son cuentas que ven salarios. **Abierto.**
   - ~~Las rutas de API devuelven el mensaje crudo de Postgres~~ — ✅ **cerrado el
     2026-08-06.** Las cuatro pasan por `mensajeDeError`, que deja pasar entero
     lo que escribimos nosotros (código `P0001`) y traduce lo demás; el detalle
     va a Sentry. `api/espejo` es máquina a máquina y devuelve un genérico a
     propósito. Lo blindan 15 pruebas en `tests/mensaje-error.test.ts`, una de
     ellas con una palabra de la lista negra que **solo** la rama `P0001` puede
     dejar pasar — las otras catorce seguían en verde con la rama desactivada.

6. **Partir `planilla/page.tsx`.** Maneja dinero, y es la pantalla más grande del
   sistema por lejos (`wc -l` lo dice; la segunda es `turnos`). Los tests SQL que
   fijan la matemática ya existen (`supabase/tests/10` y `20`); falta el refactor
   antes de seguir tocándolo.

7. **Quedan tres `"America/Lima"` sueltos** fuera de `fecha-lima.ts`, todos en
   `politica-salarial/page.tsx` (líneas 66, 77 y 236). La regla del `CLAUDE.md`
   es que no exista ninguno: el corte del día decide a qué fecha se le paga un
   marcaje. Aquí son fechas de publicación de un documento, no de pago — pero la
   regla vale igual, porque la próxima copia de esas líneas puede no serlo.

**El catálogo completo está en
[`hallazgos-abiertos.md`](hallazgos-abiertos.md)**: hallazgos vivos de una
auditoría por áreas con verificación adversaria, cada uno con su evidencia y su
arreglo.

**El patrón que se repite, y que conviene mirar antes que los síntomas:** la
misma regla escrita en dos sitios, y una corrección que arregla solo uno. Pasó
con «qué toca marcar» (SQL y navegador), con «qué es una falta» (pantalla y
documento), con «quién puede leer la planilla» (un revoke y ningún guard) y el
2026-08-06 con el formulario del cargo (escrito en una sección y no en la otra).
En todos, nadie se enteró hasta que alguien miró.

### Lo que la foto del pago sí cierra, y lo que no

**Sí:** un periodo pagado ya no puede cambiar de total en silencio. Si algo se
mueve, `fn_planilla_foto_diferencias` lo nombra persona por persona.

**No:** los periodos pagados antes de la 0096 tienen la foto *reconstruida* — es
el número del día de la migración, no el del día del pago. La pantalla de Costos
lo avisa arriba.

**Y una decisión pendiente que la 0096 hace visible:** cuando la foto y el
cálculo en vivo difieren, el sistema hoy solo lo *dice*. Nadie decidió todavía
qué pasa entonces — si se reabre el periodo, si se ajusta en el siguiente, o si
se deja constancia y ya. **Es una decisión de negocio, no técnica.**

## 🟡 Valioso pronto

- **Publicar la política salarial no tiene ningún freno.** Dos agujeros que se
  vieron el 2026-08-08 al quemar la versión 3: el aviso de «desactualizada»
  compara `md5(fn_cuadro_categorias())`, o sea **solo los datos** — cambiar la
  redacción no lo dispara y el botón sigue diciendo «Volver a publicar». Y nada
  compara el documento nuevo contra el vigente, así que el sistema aceptó
  congelar una versión **byte por byte idéntica** a la anterior, sin decir nada,
  reiniciando las constancias. Dos frenos chicos en una migración: guardar la
  huella del TEXTO y rechazar publicar una versión igual a la vigente.
- **Seis fichas incompletas** al 2026-08-08, con lo que falta a cada una visible
  en `/admin/datos-personales`. Dos casos no son campos vacíos sino datos que se
  contradicen: **Carmen Sanándres** tiene fecha de nacimiento en 2026 (su correo
  sugiere 1960), y **Angie Chávez** cobra asignación familiar teniendo cero
  familiares registrados — S/113 al mes sin respaldo, o al revés, falta cargar al
  hijo. Sin esas fichas Dante no puede cerrar el T-Registro.
- **Dos datos del T-Registro que el sistema no guarda:** sexo y nacionalidad. Se
  llenan a mano en la hoja del contador. El tercero era el CUSPP, que ya tiene
  campo (0198) y ya está cargado — ver
  [A.2.c](#a2c--los-cuspp-ya-están-cargados--quedan-dos-y-dos-falsos-positivos).
- **Pedirle al contador el CUSPP de Carmen Sanándres (LIM, Profuturo) y de
  Lizzelott Estefany Ramírez Gomez (CCO, Integra).** Son las dos únicas que
  faltan; no venían en la hoja de julio. Ver
  [A.2.c](#a2c--los-cuspp-ya-están-cargados--quedan-dos-y-dos-falsos-positivos).
- **Cargarle el régimen de pensión a Kerin Guevara** (TRU). Hoy cae a la tasa
  genérica de `configuracion.tasa_afp`, que es una aproximación: un dato faltante
  acá no se ve como un cero, se ve como un número plausible. Si sale ONP, no lleva
  CUSPP.
- **La ficha de Dante Ramal** (CCO) no existe: sin DNI no se le puede declarar.
  Va antes que cualquier dato previsional.
- **Los campos de presentación de un locador siguen mintiendo.**
  `basica_legal_prop`, `complemento_variable` y `base_essalud` muestran números
  (1192.09, 73.84 y 1305.09 en la medición) para alguien que no tiene
  remuneración básica. No mueven ni un sol —el aporte de EsSalud ya es 0— y se
  dejaron fuera de la 0242 para que fuera auditable en una pasada. Merecen su
  propia migración con su prueba.
- **El candado del periodo que quedó a medias.** Se acordó el 26-07: no dejar
  cerrar un periodo con días sin resolver. Ahora que la incidencia del almuerzo
  ya se puede cerrar desde la pantalla, el candado no bloquearía a nadie.
- **Blindar con pruebas lo que aún mueve dinero sin ninguna:** descanso
  sustitutorio, bono de puntualidad, provisiones, feriado triple.
- **Versionar 0031 y 0033**: existen solo como `scripts/sql-manual/aplicar_*.sql`
  (fuera de git por PII). Crear versiones con los datos personales parametrizados.
- **Grati/CTS — regla legal de regularidad**: la sobretasa de feriado entra solo
  si se percibió en ≥3 meses del semestre (promedio entre 6). Felipe pidió ver
  primero el impacto con
  [`consulta_impacto_regularidad_feriados.sql`](../scripts/sql-manual/consulta_impacto_regularidad_feriados.sql).
- **Colibrí en cargas**: ~22 pantallas y ~49 estados vacíos sin marca.
- **Integración Dynamic ↔ retail**: Fase 0 (reconciliación, solo lectura) lista
  para arrancar — `docs/integracion-retail/`.
- **Objetivos: botón «copiar del mes anterior»**.
- **Espejo a Google Sheets legible** (encabezados fijos, una fila por persona).

## 🟢 Dependen de Felipe / redondeo

- Datos personales: 5 fichas faltantes + celular/instrucción/estado civil (~13).
  Import SIN commitear PII.
- Validar factores de provisiones con el contador (MYPE: 8.33/4.17/4.17).
- **El rol de Catherine.** Tiene `supervisor_sede` en CCO, así que el sistema le
  da lo de una encargada de tienda —ver a la gente de CCO, firmar amonestaciones
  de CCO— y le niega lo que querría una accionista: ver las tres tiendas. Está al
  revés de su papel. ⚠️ **No es solo de permisos:** siendo locadora por
  honorarios, ese cargo la retrata como subordinada. Ver [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).
- **Cuatro personas con rol admin** (Carlos, Estefany, Felipe, Janis). Un admin ve
  todas las sedes, todos los datos personales —cuentas bancarias y DNI incluidos—
  y puede firmar despidos. Cuatro accesos totales en un equipo de 23.
  ⚠️ **Y uno de los cuatro, Carlos, no es trabajador de la empresa:** cobra por
  honorarios. Su acceso está justificado —trabaja en Desarrollo Organizacional— y
  no hay rol intermedio que lo reduzca; lo que falta es la cláusula de
  confidencialidad en su contrato de locación. Ver
  [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).
- Cuenta de Estefany (falta su correo) · revisar áreas reales de cada quien ·
  checkbox «encargada de piso» en Equipo · split mañana/tarde por sede.

---

## Decisiones tomadas (no reabrir)

- **Planilla**: régimen MYPE pequeña empresa, base 6.5 h, pago = salario × horas/(6.5 × días).
- **La CTS incluye el sexto de la gratificación** — encendido en producción el
  2026-08-05. La base pasa de sueldo pelado a sueldo × 13/12 (Art. 16 del
  D.S. 001-97-TR; en pequeña empresa la grati es media remuneración, así que el
  sexto vale sueldo/12). Sobre S/1,130 la CTS del año sube de 565.00 a 612.08.
  **Ninguna autoridad zanjó este punto para el régimen MYPE**: es derivación del
  TUO de la Ley de CTS y del documento del MTPE. Se eligió la lectura prudente
  —provisionar de más no es infracción, de menos sí—. Se apaga con una línea, y
  la prueba `126` blinda que el sexto no se cuele en la gratificación ni en las
  vacaciones. **Falta contárselo al contador antes del depósito de mayo**: si él
  calcula sobre el sueldo pelado, la discrepancia aparece el día del depósito.
- ~~**A Carlos Espejo no se le toca el tipo de vínculo**~~ — **REVISADA Y
  REVERTIDA el 2026-08-08.** La decisión decía «se revisa el día que exista la
  excepción por persona»: ese día llegó con la 0196, que parte el sí/no en tres
  banderas. Carlos pasó a `rxh`, que es lo que es.

  **Qué cambió, medido:** deja de cobrar feriados (S/286.57 en un periodo
  completo), deja de generar EsSalud (S/134.81 que pagaba CAYLA) y deja de
  provisionar gratificación, CTS y vacaciones. **Su pago por horas no se movió un
  céntimo** — de eso vive, y es lo único que le corresponde a un locador.

  **Por qué se revirtió:** los hechos, dichos por Felipe el mismo día, no
  encajaban con el retrato. Cobra POR HORA, es cuadripléjico, trabaja desde su
  casa, no está sujeto a horario y marca cuando decide trabajar. Ninguno de los
  indicios de subordinación que lista la doctrina —horario fijo, instrucciones
  directas, equipos de la empresa, monto igual cada mes— aplica. Dejarlo como
  `planilla` era construir por escrito la prueba de una relación laboral que no
  existe. Ver [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).

  ⚠️ **Y quedó una pregunta abierta que solo puede cerrar el contador:** el
  sistema venía calculando S/134.81 mensuales de EsSalud por él. Si eso se
  declaró de verdad en la PLAME, Carlos está registrado como TRABAJADOR ante
  SUNAT y EsSalud, y entonces toda la discusión sobre indicios sobra — formalmente
  ya lo es. Si solo salía en pantalla y nadie lo declaró, no pasa nada. **No es lo
  mismo y hay que averiguarlo.**
- **El terminal marca sin PIN**, a propósito. No se puede usar una marca como
  prueba individual en un procedimiento disciplinario sin otro respaldo.
- **Fecha de ingreso = decisión de negocio, no cálculo.** Se edita persona por
  persona en Equipo; el botón masivo se eliminó (0041).
- **Disciplina**: Dynamic avisa y documenta, nunca sanciona solo (D.S. 003-97-TR
  art. 25: umbrales 4 consecutivas / 6 en 30 d / 16 en 180 d).
- **Una marca se anula, nunca se borra** (0081). El botón «Eliminar» no vuelve:
  para el cálculo y para el pago anular hace lo mismo, pero deja quién la quitó y
  por qué, y se puede deshacer.
- **Cuando falta el retorno del almuerzo, el sistema no inventa una hora.** Avisa
  y decide una persona. Las tres realidades posibles (se fue, volvió sin marcar,
  no tomó refrigerio) son indistinguibles para el sistema.
- **Corregir el tipo de una marca puede dejar el día roto a mitad de camino, y no
  se bloquea**: ese estado intermedio es el primer paso del flujo de arreglo. Se
  sella para revisión y el sello se levanta solo cuando el día cuadra.
- **Las actas de descanso ya subidas no se migran al almacén** (0175). Se leen
  donde están. Mover archivos con un script es lo que puede salir a medias.
- **Meta operativas TRU = 8** · **Melany y Catherine como encargadas** · **Janis
  admin + encargada de piso** · **Keyla/Raquel/Felipe: ingresos quedan 2026**.
