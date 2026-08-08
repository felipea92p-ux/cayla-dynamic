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
| ¿Qué está aplicado en producción? | `scripts/sql-manual/comparar_funciones.sql` — y `migraciones_aplicadas` para el registro |
| ¿Falta anotar alguna migración? | la prueba `122_toda_migracion_deja_su_rastro`, en CI, en cada push |
| ¿Hay números duplicados o huecos nuevos? | `scripts/hooks/numeracion.sh`, antes de cada push |
| ¿Qué se hizo y cuándo? | `git log` |

Ninguna de esas seis puede envejecer sin que alguien se entere. Las de abajo sí,
y por eso están escritas.

**Regla para quien edite este archivo:** si lo que vas a agregar es un número que
un comando puede calcular, no va acá — va el comando. Y si es una lista de
nombres que hay que revisar, tampoco: va la consulta que los encuentra sola.

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
| **Registrar la póliza en el MTPE** | 30 días desde que se firma | No registrarla es la misma infracción que no tenerla |
| ~~**Pegar la [`0176`](../supabase/migrations/0176_quien_ya_se_fue_deja_de_tener_sueldo_vigente.sql)**~~ | ✅ **pegada el 2026-08-06** | Las seis de julio dejaron de tener sueldo vigente. No movió plata: su liquidación es S/ 0.00 antes y después (RxH, de 0 a 3 días). Comprobado con cuatro ceros: sin tramos abiertos, sin tramos pasados de largo, sin tramos posteriores al cese, sin motivos por revisar |
| **Pegar la [`0179`](../supabase/migrations/0179_la_pantalla_de_equipo_dice_cuando_y_por_que_se_fue.sql)** — la pantalla dirá cuándo y por qué se fue cada quien | cuando quieras: **no mueve plata** | Solo agrega `fecha_cese` y `motivo_cese` a lo que `fn_personas_funciones` ya devolvía. El motivo viaja solo a admin y líder DO. Listo en `scripts/sql-manual/aplicar_0179.sql`. **Nació como 0177 y se renumeró**: si llegaste a pegar la versión vieja, ese archivo trae arriba el `delete` que corrige el apunte antes de pegar la 0177 de verdad |

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
| **Carlos Espejo** | CCO | **Admin** | Desarrollo org. | Aurora · S/1,800 | fijo mensual |
| **Catherine Pereyra** | CCO | **Líder de equipo (encargada)** | Comercial | Oráculo · S/1,800 | fijo mensual |
| **Claudia Pereyra** | LIM | **Líder de equipo (encargada)** | Comercial | Aurora · S/1,800 | fijo mensual |

Cargo de mando, área, sede, un rango de la escala salarial y un monto idéntico
todos los meses. Esos cinco juntos son los indicios clásicos de
**subordinación**, que es lo que convierte una locación de servicios en un
contrato de trabajo. El riesgo no es una multa: es la **desnaturalización** del
vínculo, con CTS, gratificaciones, vacaciones y EsSalud retroactivos desde el
inicio — y multiplicado por tres.

**Lo que ya está bien:** el cuadro de categorías que se publica al equipo bajo la
Ley 30709 **no los cuenta ni los incluye en las bandas** desde la 0145: filtra
por `tipo_vinculo = 'planilla'`. El documento legal no dice que estén dentro de
la escala. El retrato queda en las pantallas internas.

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

**Lo que YA se verificó, y no hace falta volver a mirar** (2026-08-07): el
dinero está bien. A un `rxh` no se le calcula movilidad ni EsSalud (0117), ni
educación (0120), ni gratificación, CTS, vacaciones o el 9% de la Ley 30334
(0160, con la prueba `127`). Lo único que recibe es su pago base, que es lo que
se le transfiere. **No hay provisiones indebidas ni plata de más.**

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

**El hueco de numeración 0108, sin decidir.** No es algo aplicado a escondidas:
vive en la rama `origin/movilidad-supeditada-a-asistencia`
(`0108_movilidad_supeditada_a_asistencia.sql`), **sin fusionar**. Falta decidir si
entra o si su contenido ya lo cubre la 0118. Los otros huecos ya están explicados
en `scripts/hooks/huecos-conocidos.txt`.

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
| `comparar_funciones.sql` | Qué está aplicado de verdad en producción, función por función |

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

**Un bug que vale recordar:** `jsonb_build_object` admite **máximo 100
argumentos**. El objeto de la boleta estaba cerca del techo y cuatro campos
nuevos lo pasaron — compilaba y fallaba al ejecutarse. Ahora está partido en dos
unidos con `||`, y el generador cuenta los argumentos y falla si alguno se acerca
al tope.

---

## 🔴 Atender primero

1. **El terminal decide en dos sitios a la vez.** «Qué toca marcar ahora» vive en
   SQL (`fn_siguiente_tipo_esperado`) y en el navegador
   (`determinarSiguienteAccion`, `packages/shared`). Las dos ignoran ya las
   marcas anuladas, pero **arreglar una dejaba la otra rota** y nada avisa de la
   divergencia. Unificar, o al menos una prueba que compare las dos respuestas
   con los mismos datos y falle si difieren.

2. **Terminal, 4 bordes graves:** marca rechazada que se anuncia como «Listo» y
   desaparece · cola offline que se reenvía en orden de UUID y no cronológico ·
   reloj de la Mac sin verificación de desfase · persona que marca en dos sedes
   el mismo día y pierde una marca.

3. **Seguridad pendiente** (de `revision-2026-07-15/`):
   - Contraseña mínima 6 sin complejidad, sin cambio forzado en primer login —
     y son cuentas que ven salarios. **Abierto.**
   - Las rutas de API devuelven el mensaje crudo de Postgres → envolver.
     **Abierto:** `api/admin/cuentas/route.ts` líneas 113, 126 y 143, y
     `api/espejo/route.ts:32` lo relanza.

4. **Partir `planilla/page.tsx`.** Maneja dinero, y es la pantalla más grande del
   sistema por lejos (`wc -l` lo dice; la segunda es `turnos`). Los tests SQL que
   fijan la matemática ya existen (`supabase/tests/10` y `20`); falta el refactor
   antes de seguir tocándolo.

5. **Queda un `"America/Lima"` suelto** fuera de `fecha-lima.ts`, en
   `politica-salarial/page.tsx`. La regla del `CLAUDE.md` es que no exista
   ninguno: el corte del día decide a qué fecha se le paga un marcaje.

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
- **A Carlos Espejo no se le toca el tipo de vínculo.** Sigue `planilla` aunque
  facture por honorarios, a propósito: el tipo de vínculo es un sí/no para los
  tres conceptos a la vez, así que marcarlo `rxh` le pondría gratificación y CTS
  en cero — lo contrario de lo decidido. Se revisa el día que exista la excepción
  por persona.
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
