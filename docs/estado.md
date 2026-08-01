# Dynamic — Estado y pendientes

**Este es el único archivo de estado.** Se sobrescribe al avanzar; no se crean
copias con fecha. La historia vive en git. Cómo se trabaja: ver
[`CLAUDE.md`](../CLAUDE.md) en la raíz.

*Última consolidación: **2026-08-01**. Migraciones **0115 a 0122 aplicadas en
producción**. 29 archivos pgTAP, 270 pruebas.*

---

## ✅ Cerrado el 2026-08-01 — migraciones 0115 a 0122

Todas **aplicadas en producción** y verificadas con la consulta de revisión
(`revision_completa.sql`, 15 comprobaciones, todas en verde).

| # | Qué cerró |
|---|---|
| **0115** | La pensión se descuenta desde el primer periodo abierto — **los periodos pagados quedaron intactos, comprobado** · y `tasas_pension` pasó a tener RLS (era la única de 39 sin protección) |
| **0116** | EsSalud `9% × MAX(remuneración, RMV)` con su piso, en tabla versionada con sustento |
| **0117** | Un locador deja de generar movilidad y EsSalud |
| **0118** | La tarifa de movilidad, versionada y con su memoria de cálculo archivada en la fila |
| **0119** | El tipo de vínculo se puede elegir desde Equipo, con rastro en auditoría |
| **0120** | Asignación por educación por persona, con un CHECK que impide pagar más de lo que sostiene el comprobante |
| **0121** | El bono de puntualidad se apagó |
| **0122** | La asignación familiar, versionada **antes** de que suba la RMV |

**Y en la boleta:** fuera el «Rendimiento Extraordinario» y el «Incentivo Variable
por Metas»; entraron las líneas de movilidad y de descuento de pensión, y el
bloque de lo que CAYLA paga además. **La boleta cuadra al céntimo** — el
descuadre de 76.67 contra 71.84 que Felipe encontró está cerrado.

### Lo que quedó comprobado sobre el equipo

- **22 personas activas**, no 26. Eso mueve el piso de EsSalud a ~S/2,237/mes y el
  bono de cumpleaños a S/3,960/año.
- **La asignación familiar está correcta**: Angie Chávez es la única con hijos y la
  única que la cobra. Cero desajustes en las 22.
- **Catherine, Claudia Pereyra y Claudia Solórzano están inactivas.** No hay nada
  que marcar como `rxh`, y la 0119 se negaría igual: no permite cambiar el vínculo
  de alguien ya cesado.
- **Carlos Espejo** sigue marcado `planilla` y sin régimen de pensión. No se le
  descuenta nada indebido, así que marcarlo como `rxh` puede esperar.
- **Nadie ingresó antes del 2025-01-02**, así que si la acreditación en el REMYPE
  es anterior, el frente de la asignación familiar bajo régimen general es cero.

---

# 📌 QUÉ FALTA — repartido por quién lo hace

## A · Lo que depende de Felipe

### A.1 · Con fecha límite

| Qué | Cuándo | Si no |
|---|---|---|
| **Los 26 convenios individuales de movilidad, firmados** | **antes del 28/08/2026** — es cuando se paga el periodo | Se habrá pagado movilidad sin el papel que la sostiene. La **RTF 05449-4-2007** desconoció la de 14 de 21 trabajadores por eso exacto |
| **Contratar el Seguro Vida Ley** | cuanto antes | ~S/1,560/año. Sin póliza, CAYLA responde con su patrimonio: 16 remuneraciones por muerte natural, 32 por accidente. Obligatorio desde el primer día (D.Leg. 688) |
| **Registrar la póliza en el MTPE** | 30 días desde que se firma | No registrarla es la misma infracción que no tenerla |

### A.2 · Un clic en GitHub

| PR | Qué trae |
|---|---|
| **#21** | Este documento al día **+ la migración 0122**, que está aplicada en producción pero se quedó fuera del repo |
| **#22** | *No es de esta sesión* — dos líneas en la pantalla de Equipo sobre la etiqueta de «prueba». Revisalo antes de fusionar |
| **#13** | **Se puede cerrar**: su pantalla de documentación entró actualizada por el #20 |

### A.3 · Datos que hacen falta para seguir

**a) Quiénes estudian y cuánto cuesta su curso.** Con el nombre y el monto alcanza.
Se cargan de a uno con `cargar_educacion_v2.sql`, que pide el nombre y no un UUID.

**b) La fecha de acreditación de CAYLA en el REMYPE.** Decide si queda algún frente
abierto de asignación familiar: quien haya ingresado antes de esa fecha se rige por
el régimen general, donde sí es exigible. La persona más antigua ingresó el
**2025-01-02**, así que si la acreditación es anterior, el frente es **cero**.

### A.4 · Cuatro cosas para revisar en los datos

| Quién | Qué se vio | Por qué importa |
|---|---|---|
| **Catherine Pereyra** | inactiva, 0 días marcados, **total S/2,250.00** en el periodo abierto | Si es su liquidación, correcto. Si no, es plata que se paga a alguien que ya no trabaja |
| **Sandra Ramirez** | 27 días programados, **0 marcados**, total 0.00 | Puede ser vacaciones, permiso, o que no esté marcando |
| **Rufina Salvatierra** | aparece en el cálculo y **no estaba** en la lista de 22 activos | Tiene jornadas sin estar activa, o se agregó después |
| **Carlos Espejo** | sigue marcado `planilla` | Hoy no cobra movilidad porque no marca. **El día que marque, le va a salir.** Se cambia en Equipo → Tipo de vínculo |

### A.5 · Preguntas para el contador

1. **La casilla de renta neta imponible 2025** del Formulario 710. Es el único dato
   que falta para saber si hay algo que repartir de utilidades — y si es cero, el
   reparto es cero.
2. **¿Ya paga la bonificación extraordinaria del 9%** de la Ley 30334 sobre cada
   gratificación? Puede estar metida dentro del monto de la gratificación sin
   desagregar, lo que cambia el diagnóstico de «no se paga» a «se paga mal
   declarado».
3. **¿Con qué códigos declara en el PLAME** la movilidad, la educación y el bono?
   La movilidad supeditada a asistencia es el **0909**.
4. **¿CAYLA está en el SIRE** (registros de compras y ventas electrónicos)? La ficha
   RUC dice contabilidad MANUAL y el periodo de gracia habría cerrado el 30/06/2026.

---

## B · Lo que falta construir

| Qué | Bloqueado por |
|---|---|
| **Las bases declaradas** de los cuatro rangos altos — y hay que bajar **los dos campos**, `sueldo_base_legal` **y** `salario_mensual_soles` | confirmar los montos finales |
| **Pantalla para subir comprobantes** de educación, con candado: no dejar registrar el pago sin su papel | nada |
| **Bono de cumpleaños** automático con alerta en el mes del onomástico | conectar `datos_personales.fecha_nacimiento` |
| **La bonificación del 9%** de la Ley 30334 en el sistema | la respuesta del contador |
| **Versionar la RMV a S/1,300** cuando se publique el decreto | que salga la norma |

**Sobre la RMV:** el alza se anunció el 28/07/2026 y **el decreto no está
publicado**. Cuando salga, son dos sentencias por cada clave —`rmv` y
`asignacion_familiar`— y están escritas en las cabeceras de la 0116 y la 0122. Los
periodos ya pagados quedan intactos, que es todo el punto de haberlas versionado.

---

## C · Lo que se descartó y no vuelve

Cinco cosas que sonaron graves y se cayeron al verificarlas. Quedan acá para que no
vuelvan a costar tiempo.

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
no las seis cifras que suman los hallazgos por separado. **Pero no se aplica solo**:
exige presentar la constancia de REMYPE y sustentar los ingresos netos. Sin esos dos
papeles se cobra el nominal.

---

## D · Consultas útiles que ya existen

| Archivo | Para qué |
|---|---|
| `revision_completa.sql` | 15 comprobaciones de las migraciones 0115–0122 |
| `encender_movilidad.sql` | Encender la tarifa, en transacción y con verificación |
| `cargar_educacion_v2.sql` | Cargar una asignación por nombre, sin copiar UUID |

**Y el prólogo que hace falta seguido:** `fn_planilla_calcular`, `fn_provisiones` y
`fn_set_tipo_vinculo` exigen sesión de admin, y el SQL Editor no la tiene. Dos líneas
al inicio lo resuelven:

```sql
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and nombres ilike '%Felipe%' and auth_user_id is not null limit 1),
  true);
```

---

## Lo que sigue, sin urgencia

### Tres datos que hacen falta

**a) Quiénes estudian y cuánto cuesta su curso** (`aurora 1 → universidad S/520`).

**b) La lista nominal real:**

```sql
select a.rango::text, p.nombres || ' ' || p.apellidos as persona, p.estado,
       p.tipo_vinculo, a.salario_mensual_soles as salario,
       p.sueldo_base_legal as declarado, p.regimen_pension, p.fecha_ingreso
from personas p
left join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
order by a.salario_mensual_soles desc nulls last, p.apellidos;
```

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

### 4 · Una llamada que no depende de código

**El Seguro Vida Ley no está contratado.** Obligatorio desde el primer día
(D.Leg. 688, mod. Ley 31408). Cuesta **~S/1,560 al año** por los 26. Si falta y
alguien fallece, CAYLA paga de su bolsillo 16 remuneraciones (~S/18,000) por causa
natural o 32 (~S/36,000) por accidente. **Lo mejor del expediente por relación
costo-beneficio.**

---

## 🔴 Lo que la auditoría empírica encontró, y cambia el diseño

Contra Postgres local con datos reales, en `BEGIN … ROLLBACK` como manda el
`CLAUDE.md`. Es el hallazgo más importante de la madrugada.

**`pago_base` se calcula sobre `asignaciones_salario.salario_mensual_soles` —el
rango completo— y NO sobre `personas.sueldo_base_legal`:**

```
pago_base = horas × salario_mensual_soles / v_base
basica    = horas × least(sueldo_base_legal, salario) / v_base
```

**Declarar menos NO reduce lo que se paga.** Sumar movilidad, educación y bono
encima del rango completo sobrepagaría por el monto entero de esos conceptos —
del orden de **S/4,900 al mes** entre las 26 personas.

**La corrección:** al fijar las bases declaradas hay que bajar **los dos campos**
—`sueldo_base_legal` **y** `salario_mensual_soles`— al mismo monto. Es exactamente
lo que Felipe eligió al decir «base = lo declarado»; lo que faltaba era saber que
toca dos campos y no uno.

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

**Los cuatro rangos altos cuadran casi exacto con el diseño acordado** — aurora
+0.52, oráculo −1.97, archicaylo +4.62, support −7.24.

### Dos cosas más que aparecieron

**Los días son 27, no 26.** En un periodo de 31 días con domingos libres hay 27
laborables, así que la movilidad a S/10 da **270**, no 260.

**Los feriados oscilan el total entre S/90 y S/196 por mes.** Por feriado se paga
el día prorrateado por la asistencia del mes **más** las horas efectivamente
trabajadas ese día, salvo compensación con día libre (lógica de la 0069). Agosto
2026 tiene dos: 29 de julio y 6 de agosto.

**Por eso el diseño no puede cerrar exacto todos los meses**, y forzarlo con
educación o bono sería el reverse-engineering que hunde los conceptos (caso Albis).
Cada concepto se fija por su propio mérito y el total aterriza cerca del rango.

---

## 📋 Migraciones 0115 a 0120 — lo que se construyó

| # | Qué hace | Verificación empírica |
|---|---|---|
| **0115** | Mueve la vigencia de `tasas_pension` al primer periodo abierto · RLS a la tabla (era la única de 39 sin protección) | el periodo pagado NO encuentra tasa, el abierto sí |
| **0116** | EsSalud `9% × MAX(remuneración, RMV)`, en tabla versionada con sustento | 1 día trabajado (S/36.96) → **S/101.70**, no S/3.33 |
| **0117** | Movilidad y EsSalud dejan de calcularse para quien no está en planilla | siendo `rxh` → movilidad 0.00, essalud 0.00 |
| **0118** | La tarifa de movilidad deja `configuracion` y pasa a `parametros_laborales`, con su memoria de cálculo archivada en la fila | al encender desde el 29/07: julio pagado **0.00**, agosto **270.00** |
| **0119** | RPC para elegir el vínculo, con guard, validación y rastro en auditoría, más el selector en pantalla | 6 de 6 comportamientos |
| **0120** | Asignación por educación **por persona**, versionada, con un CHECK que impide pagar más de lo que sostiene el comprobante | 6 de 6: el candado rechaza 151 sobre un curso de 200 al 75%; no se prorratea por asistencia; un `rxh` recibe 0; la vigencia cierra bien |

**En la boleta:** fuera el «Rendimiento Extraordinario»; entran las líneas de
movilidad y de descuento de pensión; y un bloque aparte —fuera de la tabla del
pago, con la leyenda «no se descuenta de tu sueldo»— con el EsSalud y las tres
provisiones. Sin total y sin porcentaje, por decisión tomada.

---

## Decisiones del diseño remunerativo (2026-07-31)

| Concepto | Decisión | Amparo |
|---|---|---|
| **Movilidad** | S/10.00 por día marcado · 4 traslados × S/2.50 (colectivo) · refrigerio de 1h15 habilita almorzar en casa | Art. 19 e) · PLAME 0909 |
| **Educación** | 75% del comprobante, tope por rango · vale para el trabajador **y/o sus hijos**, sin tope de edad | Art. 19 f) |
| **Bono cumpleaños** | **S/180**, igual para los 26, en el mes del onomástico, sin condición de antigüedad | Art. 19 g) |
| **Pensión** | Tasa real por persona (12.84%–13.06% u ONP 13%), desde el periodo abierto | — |
| **EsSalud** | 9% con piso de la RMV, visible como aporte de la empresa | Ley 26790 art. 6 |
| **Base de beneficios** | Igual al monto declarado de cada persona | decisión de Felipe |
| **Fuera de la estructura** | Felipe y Catherine | decisión de Felipe |
| **Por honorarios** | Carlos Espejo y Claudia Pereyra — falta marcarlos con la 0119 | — |

**La cláusula del bono, textual.** No usar la que decía «gratificación
extraordinaria a título de liberalidad»: invocaba el inciso a), que exige que el
pago sea *ocasional*, y hacía el gasto **no deducible** (art. 44 d) LIR).

> *Asignación por cumpleaños, otorgada con ocasión del onomástico del trabajador,
> conforme al literal g) del artículo 19 del D.S. 001-97-TR. No constituye
> remuneración computable para ningún efecto legal.*

---

## ⏳ Pendiente de la estructura remunerativa

| Qué | Bloqueado por |
|---|---|
| **0121** bases declaradas (los **dos** campos) | la lista nominal real |
| **0122** bono automático con alerta | conectar `datos_personales.fecha_nacimiento` |
| Cargar las asignaciones de educación en la 0120 | la lista de quién estudia y su comprobante |
| Pantalla de comprobantes con candado en el pago | nada |
| Documentación con las cláusulas (PR #13, 413 líneas escritas) | nada |
| El 9% de la Ley 30334 sobre cada gratificación | confirmar si el contador ya lo paga |
| Los 26 convenios individuales de movilidad firmados | **antes de encender la tarifa** |

**Sobre los convenios:** la **RTF 05449-4-2007** desconoció la movilidad de 14 de
21 trabajadores por falta de convenio exhibido. El inciso e) nombra el «pacto
individual» como la vía del monto fijo. La sentencia para encender la tarifa, con
su memoria de cálculo completa, está en la cabecera de la 0118.

---

## Correcciones a información que yo di mal

Quedan anotadas porque se tomaron decisiones sobre ellas.

| Lo que dije | Lo correcto |
|---|---|
| «El límite del RER de 10 trabajadores por turno es tu problema más caro» | **CAYLA está en Régimen MYPE Tributario desde 2023** (ficha RUC). El RER no aplica. No hay que mover ningún horario |
| «Sobre 25% de conceptos no remunerativos se activa la presunción de salariedad» | **Era mi regla de dedo, no una norma.** No existe porcentaje en la ley peruana |
| La cláusula del bono con «liberalidad» y «a discreción» | Invocaba el inciso a), que exige ocasionalidad, y hacía el gasto no deducible |
| «Ninguna función respeta `en_planilla`» | **Las de liquidación sí:** `fn_cts_trunca`, `fn_grati_trunca` y `fn_vacaciones_truncas` vía `fn_devenga_beneficios` |
| «Un pacto colectivo blinda la movilidad» | Solo es requisito del inciso g) para festividades. Art. 9 TUO CTS: la denominación es irrelevante. **La firma no blinda, incrimina** |
| «CAYLA es un instituto de idiomas» *(en un prompt de verificación)* | Es **CIIU 4641 — venta al por mayor de textiles**. Se descartó todo el análisis de IGV educativo que salió de ahí |

---

## Notas del entorno (MacBook, 2026-08-01)

**`supabase start` no reconstruye la base acá.** Falla aplicando la 0001 con «type
rol_usuario already exists», sin volúmenes ni contenedores previos, con el CLI
2.109.1. Docker sí funciona.

**La alternativa que sí funciona**, y con la que se hizo la auditoría empírica:
levantar la imagen a mano y aplicar las migraciones sobre la base `postgres` (para
que `pg_cron` de la 0007 funcione), con dos andamios previos —`storage.buckets` y
`storage.objects` creados como `supabase_admin`, y una fila en `auth.users`—.

```bash
docker run -d --name cayla_audit -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_HOST_AUTH_METHOD=trust public.ecr.aws/supabase/postgres:17.6.1.141
```

Con eso las **114 migraciones aplican limpio**.

**`packages/database/src/types.ts` está desfasado**: 8 errores de tipos
preexistentes por RPC que no figuran. `supabase gen types` no corre en esta máquina
(«Failed to end the connection on error»). La entrada de `fn_set_tipo_vinculo` se
agregó a mano, marcada con comentario. **CI no corre typecheck**, así que no
bloquea nada.

**Un bug que vale recordar:** `jsonb_build_object` admite **máximo 100
argumentos**. El objeto de la boleta estaba cerca del techo y cuatro campos nuevos
lo pasaron — compilaba y fallaba al ejecutarse. Ahora está partido en dos unidos
con `||`, y el generador cuenta los argumentos y falla si alguno se acerca al tope.

---

## Nota histórica — consolidación del 2026-07-27

Lo que sigue es el estado tal como quedó esa noche, con las migraciones hasta la
0102. Se conserva porque contiene decisiones que no se reabren y aprendizajes que
no conviene volver a pagar. Lo de arriba es lo vigente.

> 🔴 **Advertencia de entonces, todavía válida como criterio:** el repositorio no
> describía fielmente la producción. `migraciones_aplicadas` decía que la 0089
> estaba aplicada y su contenido no estaba en la base. Un registro no es una
> comprobación. Las herramientas para medirlo están en
> `scripts/sql-manual/comparar_funciones.sql`.

---

## ✅ Aplicado en producción el 26-07 — migraciones 0076 a 0089

| # | Qué cerró |
|---|---|
| 0076 | Ejecución sin sesión de 54 funciones · la firma escaneada sale de `personas` a su propia tabla |
| 0077–0080 | Registro de migraciones · guards null-safe · la suspensión deja de contar como falta · feriados hasta 2032 |
| 0081 | Una marca se **anula**, no se borra · corregir el **tipo** de una marca · **confirmar** un auto-cierre |
| 0082 | Las otras seis funciones que leen marcajes ya saben de las anuladas |
| 0083 | Candado de periodo pagado al confirmar · el día que una marca abandona se recalcula |
| 0084 | El sello de "día por revisar" **se levanta** cuando el día vuelve a cuadrar |
| 0085–0087 | Tipo de vínculo · fecha de cese · beneficios truncos al cesar *(de la otra sesión)* |
| 0088 | La gratificación se paga aunque el periodo **cruce el año** |
| 0089 | Los cinco cabos sueltos de la auditoría (auto-cierre duplicado, día roto en silencio, candado con bloqueo, orden de la autorización) |
| 0090 | **La planilla no la lee cualquiera.** El barrido de la 0076 había deshecho un `revoke` deliberado: cualquier sesión con login —el terminal de tienda incluido— podía pedir los sueldos de todo el equipo |
| 0091 | **La hora de Lima en todo el sistema.** `current_date` resuelve en UTC: desde las 19:00 el sistema creía que era mañana. Nueve funciones afectadas, entre ellas el semáforo disciplinario. Cuarta vez que entra el mismo bug; ahora hay una prueba que lo impide |
| 0092 | Una falta no se sanciona dos veces. La rama del art. 25-h no tenía el candado: cada pulsación fabricaba otra carta de preaviso idéntica |
| 0093 | El descanso sustitutorio no toca una planilla pagada (medido: S/65 menos en un periodo cerrado, sin rastro) |
| 0094 | **El memo no acusa por días ya justificados.** La pantalla decía «suspensión cumplida» y el papel entregado decía «inasistencia injustificada» |
| 0095 | Ni horas negativas (el auto-cierre podía poner la salida antes de la entrada) ni reabrir un pago sin motivo |
| 0096 | **La foto del pago.** Al marcar un periodo como pagado se congela el desglose de cada persona. No se edita ni se borra; si un recálculo posterior ya no coincide, el sistema lo dice en vez de cambiar la cifra |
| 0097 | **Costos.** Pantalla nueva en Nómina que suma lo que costó el equipo leyendo solo lo congelado. Separa lo que se transfirió de lo que le cuesta a CAYLA (con provisiones) |
| 0098 | Volver a pagar un periodo sin que pase por «abierto»: los candados de sus marcajes no se levantan ni un instante |
| 0099 | Tipo de sede (central · taller · tienda) y costos comparables por persona y por hora — un total no compara dos sedes de distinto tamaño |
| 0100 | **Un cero no explica nada.** «De vacaciones», «no marcó» y «sin horario» ya no se ven idénticas en la planilla |
| 0101 | **Ausencias: un solo lugar para «por qué no vino».** Absorbe `vacaciones` y `justificaciones_asistencia` convirtiéndolas en vistas. Un permiso concedido deja de contar como falta injustificada — antes el sistema abría expediente disciplinario por los días que la empresa concedía |
| 0102 | **Poner al día lo que el registro decía que ya estaba.** Cinco funciones donde producción tenía una versión anterior, incluido el trigger que dejaba horas fantasma al mover una marca de día |

**Todas aplicadas en producción**, incluidas la 0085, 0086 y 0087 (tipo de
vínculo, fecha de cese y beneficios truncos), que llevaban días escritas sin
pegarse. Con eso el laboratorio y producción tienen por fin el mismo esquema.

**Ojo con lo que ese registro decía.** Se dio por hecho que las 0088 y 0089 se
habían aplicado bajo sus números viejos. La 0089 **no** se había aplicado: se
registró y su contenido nunca llegó. Un registro no es una comprobación.

### Lo que costó aprender hoy

- **Un bloque que recorre objetos en masa aborta entero** al topar con uno que no
  pertenece al rol `postgres` de Supabase, que **no es superusuario**. Probar como
  superusuario local no reproduce esa condición. Todo barrido lleva manejo de
  excepción por elemento y reporta al final lo que no pudo tocar.
- **`alter default privileges ... in schema public revoke execute ... from public`
  no hace nada.** El EXECUTE que PUBLIC tiene por defecto sobre funciones es
  global, no por schema, y una cláusula `IN SCHEMA` solo puede *añadir*. Sin
  `in schema` sí funciona. La sentencia se acepta sin error en las dos formas.
- **Un `revoke` por columna no reduce nada** si el rol tiene `SELECT` sobre la
  tabla entera. Por eso la firma escaneada se mudó de tabla en vez de revocarse.
- **El sello de "día por revisar" era tinta, no una pregunta.** Se ponía cuando el
  día se rompía y nada lo levantaba: cuantas más marcas del día estuvieran bien,
  más fácil era que el día se quedara pegado en la lista para siempre.
- **Numerar migraciones sin volver a mirar el directorio** produjo dos colisiones
  (0085 y 0086) en la misma sesión en que se criticó ese error. Mirar `ls` antes
  de crear el archivo, siempre — otra sesión puede haber avanzado.

---

## 🔴 Atender primero

1. **El terminal decide en dos sitios a la vez.** "Qué toca marcar ahora" vive en
   SQL (`fn_siguiente_tipo_esperado`) y en el navegador
   (`determinarSiguienteAccion`, `packages/shared`). Hoy se arregló que las dos
   ignoren las marcas anuladas, pero **arreglar una dejaba la otra rota** y nada
   avisa de la divergencia. Es el mismo problema de raíz que produjo el fallo:
   unificar, o al menos una prueba que compare las dos respuestas con los mismos
   datos y falle si difieren.

2. **Liquidación por cese + foto del pago.** Pantalla propia: sueldo pendiente +
   vacaciones truncas + grati trunca + CTS trunca, congelado e imprimible. La ley
   da 48 h desde el cese (art. 4 D.S. 001-97-TR), así que **no** se puede prohibir
   el cierre anticipado sin esto. Incluye el pago por horas del día de prueba, con
   recordatorio del T-Registro de 24 h. Al marcar PAGADO se guarda copia intacta
   de los montos y el sistema avisa si un recálculo posterior ya no coincide.
   **Dónde quedó exactamente (27-07, pedido de Felipe: recordárselo):**
   - `0085` tipo de vínculo y `0086` fecha de cese: **probadas**, en el repo, sin
     aplicar en producción.
   - `0087` truncas: **retirada de producción** con
     [`quitar_0087_truncas.sql`](../scripts/sql-manual/quitar_0087_truncas.sql)
     porque se aplicó sin pruebas y fallaba dos de seis casos.
     `fn_grati_trunca` ya está corregida y pasa **6/6**;
     **Ya probadas: 19 casos en la prueba 103**, escritos desde la norma antes
     de correr nada. Falta la pantalla.
   - La trampa que falta cazar en CTS: el sexto de la gratificación es
     `sueldo/12` en MYPE, no `sueldo/6` — usar el del régimen general paga de
     más en cada liquidación.
   - Falta la pantalla.

3. **Los 4 scripts de `sql-manual` que divergen de su migración fuente.** El peor,
   `aplicar_0017`, lleva la fórmula vieja de tardanza: pegarlo retrocede el
   cálculo de horas de todo el equipo. O se regeneran desde la migración, o se
   borran.

4. **Terminal, 4 bordes graves:** marca rechazada que se anuncia como "Listo" y
   desaparece · cola offline que se reenvía en orden de UUID y no cronológico ·
   reloj de la Mac sin verificación de desfase · persona que marca en dos sedes
   el mismo día y pierde una marca.

5. **Seguridad pendiente** (de `revision-2026-07-15/`, verificado el 26-07):
   - `generarClave()` usa `Math.random()` (`api/admin/cuentas/route.ts:13`) →
     `crypto.randomInt`.
   - Contraseña mínima 6 sin complejidad, sin cambio forzado en primer login
     (cuentas que ven salarios).
   - Las rutas de API devuelven el mensaje crudo de Postgres → envolver.

6. **Partir `planilla/page.tsx` (1 587 líneas).** Maneja dinero. Los tests SQL que
   fijan la matemática ya existen (`supabase/tests/10` y `20`); falta el refactor
   antes de seguir tocándolo.

**El catálogo completo de lo que queda está en
[`hallazgos-abiertos.md`](hallazgos-abiertos.md)**: 24 hallazgos vivos de una
auditoría por áreas con verificación adversaria (52 agentes; de 42 candidatos
sobrevivieron 34, y 10 ya se cerraron). Cada uno con su evidencia y su arreglo.

**El patrón que se repite, y que conviene mirar antes que los síntomas:** la
misma regla escrita en dos sitios, y una corrección que arregla solo uno. Pasó
con «qué toca marcar» (SQL y navegador), con «qué es una falta» (pantalla y
documento) y con «quién puede leer la planilla» (un revoke y ningún guard). En
los tres casos nadie se enteró hasta que alguien miró. Cada arreglo lleva ahora
una prueba que compara las dos copias y falla si se separan.

### Lo que la foto del pago sí cierra, y lo que no

**Sí:** un periodo pagado ya no puede cambiar de total en silencio. Si algo se
mueve, `fn_planilla_foto_diferencias` lo nombra persona por persona. Y ahora hay
una cifra de costo que se puede entregar al contador y sumar por sede y por área.

**No:** los periodos que ya estaban pagados antes de la 0096 tienen la foto
*reconstruida* — es el número del día de la migración, no el del día del pago.
La pantalla de Costos lo avisa arriba. No se puede saber cuánto se desvió cada
uno; ese dato no existe en ninguna parte, y por eso la foto se construyó.

**Y una decisión pendiente que la 0096 hace visible:** cuando la foto y el
cálculo en vivo difieren, el sistema hoy solo lo *dice*. Nadie decidió todavía
qué pasa entonces — si se reabre el periodo, si se ajusta en el siguiente, o si
se deja constancia y ya. Es una decisión de negocio, no técnica.

## 🟡 Valioso pronto

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
- **Objetivos: botón "copiar del mes anterior"** — urge al arrancar agosto.
- **Espejo a Google Sheets legible** (encabezados fijos, una fila por persona).

## 🟢 Dependen de Felipe / redondeo

- Datos personales: 5 fichas faltantes + celular/instrucción/estado civil (~13).
  Import SIN commitear PII.
- Validar factores de provisiones con el contador (MYPE: 8.33/4.17/4.17).
- **El rol de Catherine.** Tiene `supervisor_sede` en CCO, así que el sistema le
  da lo de una encargada de tienda —ver a la gente de CCO, firmar amonestaciones
  de CCO— y le niega lo que querría una accionista: ver las tres tiendas. Está al
  revés de su papel.
- **Cuatro personas con rol admin** (Carlos, Estefany, Felipe, Janis). Un admin ve
  todas las sedes, todos los datos personales —cuentas bancarias y DNI incluidos—
  y puede firmar despidos. Cuatro accesos totales en un equipo de 23.
- Cuenta de Estefany (falta su correo) · revisar áreas reales de cada quien ·
  checkbox "encargada de piso" en Equipo · split mañana/tarde por sede.

---

## Decisiones tomadas (no reabrir)

- **Planilla**: régimen MYPE pequeña empresa, base 6.5 h, pago = salario × horas/(6.5 × días).
- **El terminal marca sin PIN**, a propósito. No se puede usar una marca como
  prueba individual en un procedimiento disciplinario sin otro respaldo.
- **Fecha de ingreso = decisión de negocio, no cálculo.** Se edita persona por
  persona en Equipo; el botón masivo se eliminó (0041).
- **Disciplina**: Dynamic avisa y documenta, nunca sanciona solo (D.S. 003-97-TR
  art. 25: umbrales 4 consecutivas / 6 en 30 d / 16 en 180 d).
- **Una marca se anula, nunca se borra** (0081). El botón "Eliminar" no vuelve:
  para el cálculo y para el pago anular hace lo mismo, pero deja quién la quitó y
  por qué, y se puede deshacer.
- **Cuando falta el retorno del almuerzo, el sistema no inventa una hora.** Avisa
  y decide una persona: registrando las marcas reales, o dando el visto bueno si
  de verdad trabajó de corrido. Las tres realidades posibles (se fue, volvió sin
  marcar, no tomó refrigerio) son indistinguibles para el sistema.
- **Corregir el tipo de una marca puede dejar el día roto a mitad de camino, y no
  se bloquea**: ese estado intermedio es el primer paso del flujo de arreglo. Se
  sella para revisión y el sello se levanta solo cuando el día cuadra.
- **Meta operativas TRU = 8** · **Melany y Catherine como encargadas** · **Janis
  admin + encargada de piso** · **Keyla/Raquel/Felipe: ingresos quedan 2026**.

## Registro de lo cerrado (para no re-investigar)

Deshacer pago de planilla ✅ (0066 + test 30) · faltas Fase 2 completa ✅
(0051–0060) · cobertura en vivo ✅ · bono de puntualidad ✅ (0034) · menú móvil ✅
· recuperar clave ✅ · boleta individual ✅ · patrón de tardanzas ✅ · descanso
sustitutorio con actas ✅ (0069–0073) · ejecución anónima cerrada ✅ (0076) ·
firma escaneada fuera de `personas` ✅ (0076) · anular/corregir tipo/confirmar
✅ (0081–0084, 0089) · gratificación en periodos que cruzan el año ✅ (0088) ·
pruebas de `fn_recalcular_jornada` ✅ (60 aserciones, tests 80–89).
