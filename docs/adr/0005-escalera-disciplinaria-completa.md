# ADR 0005 — La escalera disciplinaria llega hasta arriba

**Fecha:** 2026-10-29 · **Estado:** aceptado · **Decide:** Felipe

## Lo que se pidió

Que cada líder de equipo pueda emitir memorándums «para así escalar medida
disciplinaria de despido de ser necesario».

## Lo que ya existía, y por eso esto no es un sistema nuevo

La líder de equipo **ya emite memorándums** desde el 2026-10-06. Las
migraciones 0510 a 0516 construyeron:

| Pieza | Dónde vive |
|---|---|
| Catálogo inmutable de las 20 faltas del RIT v4.0 (7 leves del 53.1, 13 significativas del 53.2) | `faltas_catalogo` (0510) |
| La líder registra una falta de conducta de su sede, citando el literal exacto | `fn_expediente_crear_conducta` (0510) |
| Quién actúa: la líder, solo en planilla, solo su sede, nunca sobre sí misma ni sobre otra líder | `fn_expediente_puede_actuar` (0510) |
| Quién firma: nadie que no esté en planilla; el despido solo Gerencia General | `fn_expediente_firmante_motivo` (0510), `fn_expediente_puede_suscribir` (0214) |
| DO toma el caso de una líder y se lo devuelve, con motivo e historial | `fn_expediente_tomar_caso` / `_devolver_caso` (0511) |
| DO se entera de cada conducta registrada | 0515 |
| La persona deja constancia de haber leído su memo | 0516, 0408, 0486 |
| El mismo hecho no se registra dos veces (52.5, non bis in idem) | índice único parcial (0510) |

La escalera de **tardanzas** e **inasistencias** (arts. 19 y 21) corre sola y
completa desde mucho antes.

## El problema real

La escalera del RIT art. 54.1 tiene tres peldaños: amonestación escrita →
suspensión sin goce → despido. Para la causal **conducta**, el sistema solo
construyó el primero. Y encima, lo que construyó no cuenta como peldaño:

1. **El descargo previo está apagado.** `configuracion.disciplina_descargo_previo
   = false` (0267). El art. 55.2 del RIT que CAYLA firmó dice que «la omisión del
   descargo previo invalida la sanción, que no puede computarse como antecedente
   ni servir de escalón para los efectos del literal h) del artículo 25 de la
   LPCL». Hoy cada memo se firma al instante: documenta el hecho, pero no es
   peldaño de nada. **Construir los peldaños de arriba sobre esta base es
   construir una escalera que el art. 25 h) no reconoce.**
2. **No existe la suspensión por conducta.** La 0510 lo dejó escrito en su
   «QUÉ NO HACE». La cadena de la líder termina en amonestación.
3. **Las faltas graves del 53.3 no están en el catálogo.** Son las únicas que
   habilitan un despido (art. 25 LPCL). La imputación del art. 57 se escribe a
   mano, sin citar literal — y el 57.7 exige congruencia entre la causa de la
   imputación y la de la carta de despido.
4. **La notificación de un despido admite un acta interna.** El art. 57.8 dice
   que, tratándose de imputación o despido, el acta interna de negativa a firmar
   **no sustituye** la vía notarial. `fn_expediente_entregar` (0303) bloquea el
   correo en esos dos niveles pero acepta `acta_negativa`.

## Las decisiones

### 1 · El descargo previo se enciende, para todas las causales

**DECIDÍ:** poner `disciplina_descargo_previo = true`. Antes de firmar cualquier
amonestación o suspensión se comunican cargos y se esperan 2 días hábiles.

**DESCARTÉ:** encenderlo solo para conducta, porque dejaría la mitad del legajo
—tardanzas e inasistencias, que es de donde sale el despido del 53.3 e)— sin
servir de escalón, y el 57.10 exige justamente «historial disciplinario
documentado que acredite el cumplimiento de la gradación de los artículos 19 y
21». Media escalera válida no sostiene un despido por reiteración.

**SE ROMPE SI:** hay borradores abiertos sin cargos comunicados el día del
encendido — `fn_expediente_firmar` los rechazará hasta que se comuniquen. Salida
ya construida: `fn_expediente_declarar_cargos_comunicados` (0266) declara una
comunicación ya ocurrida. Se mide cuántos son antes de pegar.

**Medido al construirlo (prueba 456, control A/B):** encender la política no
agrega un paso antes de firmar, agrega **tres** — comunicar cargos, esperar el
plazo y **valorar el descargo por escrito**, incluso cuando la persona no
presentó ninguno (hay que dejar constancia de que no lo presentó). La tercera no
estaba escrita en ninguna parte y es la que se leería como una avería. La
pantalla ya las dibuja desde la 0267 (`etapaDelBorrador`: `comunicar → esperando
→ valorar → firmar`), así que no hay interfaz que cambiar: estaba construida
esperando la decisión.

La maquinaria entera ya la construyó la 0267: esta migración cambia **una fila**
y no reescribe ninguna función.

### 2 · La líder propone la suspensión; DO la impone

**DECIDÍ:** la líder marca «propongo suspensión» con su motivo sobre el
documento de conducta que ya registra. DO fija los días, comprueba el antecedente
y firma. Dos columnas nuevas escritas por una función guardián, más un trigger que
rechaza el UPDATE directo — el molde que el repo ya repitió tres veces
(`fn_cambiar_regimen_pension`, `fn_set_rol`, `fn_set_sede_base`).

**DESCARTÉ:** que la líder redacte la suspensión y DO solo firme. El 54.4 d) deja
sin efecto alguno la sanción impuesta por quien no es competente, y graduar los
días es parte de imponerla. También descarté que DO la cree de cero: la líder que
vio el hecho dejaría de constar como quien pidió más, y el 54.7 exige que la
decisión de subir un peldaño conste motivada por escrito.

**SE ROMPE SI:** dos líderes de la misma sede proponen sobre el mismo documento
en el mismo segundo. La función toma la fila con `for update`, como la 0511.

Los topes (3 días por falta significativa, 15 en 12 meses) y los días hábiles no
se reescriben: ya viven en `fn_expediente_set_suspension` (0294).

### 3 · Las faltas graves del 53.3 entran al catálogo, y solo DO o Gerencia las citan

**DECIDÍ:** sumar los 6 literales del 53.3 como filas `gravedad = 'grave'` de la
v4.0, y una función de imputación por conducta que cite el literal y fije el plazo
del 57.2 (6 días naturales para defenderse, 30 para demostrar capacidad). El
vínculo `doc_previo_id` —que el esquema tiene desde la 0056 para «la cadena:
amonestación → suspensión → imputación → despido»— ata la carta de despido a su
imputación, y la base comprueba que citan el mismo literal: eso es la congruencia
del 57.7, hecha imposible de romper en vez de recordada.

**DESCARTÉ:** seguir escribiendo la imputación a mano. Ya costó una vez: al
renumerarse el RIT de la v3 a la v4, el memo citó el «artículo 7» —que en la v4 es
el periodo de prueba— durante siete semanas.

**SE ROMPE SI:** el RIT v4.0 no está «expedido y puesto en conocimiento conforme
al artículo 60». El propio 53.3 a) condiciona a eso toda la rama de faltas graves
por inobservancia del Reglamento. La 0228 ya se niega a sancionar con un
reglamento que no se entregó, así que el sistema frena solo; pero el pendiente 78
de `docs/reglamento-pendientes-de-construir.md` sigue abierto y es de Gerencia, no
del sistema.

El CHECK `chk_gravedad_del_numeral` de la 0510 —`(numeral = '53.1') = (gravedad =
'leve')`— admite el 53.3 sin tocarlo. Solo se amplía el CHECK de `gravedad`.

**Al construirla (0568), tres cosas salieron distintas de lo escrito arriba.**

**La congruencia no se comprueba: se hereda.** Este ADR decía «la base comprueba
que citan el mismo literal». Comprobar es un `if`, y un `if` existe porque el dato
pudo llegar mal. `fn_expediente_crear_despido` no tiene parámetro de causa: recibe
su imputación y de ahí saca la causa, el tipo de causal, el periodo y la persona.
No puede divergir porque no hay nada que divergir. El candado del molde de la casa
(cuarta instancia, tras 0261, 0295 y 0342) cierra la otra puerta: un UPDATE
directo a `falta_literal` o a `doc_previo_id` de una carta de despido se rechaza.

**Dos restricciones de la 0510 guardaban la premisa que esta migración cambia**, y
las dos habrían hecho imposible justo lo que viene a construir:

- `chk_conducta_completa` obliga a que una imputación o un despido por conducta
  tengan los tres campos de la falta en NULL, con el comentario «nunca un literal
  del catálogo […] se fundan en una falta GRAVE del 53.3, que cita el artículo 25
  de la LPCL y no un literal del catálogo». Era cierto: el 53.3 no estaba en el
  catálogo. Ahora admite las dos formas, y es un superconjunto de la vieja
  —ninguna fila que pasaba deja de pasar, incluida la de la prueba 170—; si cita
  literal, el numeral tiene que ser 53.3, que es el 53.4 hecho imposible de
  contradecir desde la base y no solo desde una función.
- `uq_conducta_un_hecho_un_documento` (52.5, «el mismo hecho no se documenta dos
  veces») nunca había alcanzado a esos dos niveles, y no por decisión: en un
  índice único dos NULL no chocan. Al citar el literal, la carta choca con su
  propia imputación. Se resolvió diciendo a qué se refiere el 52.5 en vez de
  relajarlo: protege de SANCIONAR dos veces, y la escala del 54.1 son tres
  peldaños —verbal, amonestación, suspensión—. La imputación es el preaviso del
  art. 31 y el despido es la extinción del vínculo, no sanciones de esa escala.
  El índice deja fuera solo `despido`, así que sigue garantizando un hecho/una
  sanción y un hecho/una sola imputación.

Las dos las cazó la prueba 458 antes de pegar nada. Ninguna estaba mal escrita:
las dos eran premisas correctas que caducaron, y es la razón por la que una
restricción lleva su porqué al lado.

**Y apareció un freno que faltaba: el numeral 60.5 en la rama del despido.**
`fn_expediente_comunicar_cargos` y `fn_expediente_declarar_cargos_comunicados` ya
comprueban que conste la entrega del Reglamento, y las dos rechazan la imputación
—«La imputación y el despido siguen el procedimiento del artículo 57»—, que no
estaba escrito en ninguna función. Así que la rama que más cuesta si se equivoca
era la única sin ese freno. La 0568 llama a `fn_reglamento_no_acusado` al imputar,
y pesa especialmente acá porque el propio 53.3 a) condiciona la falta grave a un
Reglamento «expedido y puesto en conocimiento conforme al artículo 60».

### 4 · El acta interna en imputación y despido avisa, no bloquea

**DECIDÍ (Felipe):** se sigue admitiendo `acta_negativa` en imputación y despido,
y el sistema deja constancia de la advertencia en el propio expediente y en
pantalla — el mismo molde con que la 0267 anota un memo firmado sin descargo.

**DESCARTÉ:** bloquearlo, que era mi recomendación. El trade-off, dicho una vez:
un aviso se aprende a ignorar, y lo que está en juego es que un despido por una
falta real se caiga por defecto de notificación. Queda escrito aquí para que
quien lo lea dentro de un año sepa que fue una decisión y no un descuido.

**SE ROMPE SI:** nadie lee la advertencia. Por eso va en el expediente —donde la
lee quien revisa el caso— y no solo en un cartel de pantalla que se cierra.

### 5 · La líder ve solo los antecedentes de conducta de los últimos 12 meses

**DECIDÍ:** `fn_conducta_antecedentes` le muestra lo que agrava según el 56.5
—conducta, misma causa, entregado, dentro de 12 meses— más un contador «tiene N
documentos de otras causales» sin poder abrirlos.

**DESCARTÉ:** abrirle el expediente vigente completo. Las tardanzas no le sirven
de escalón para una conducta (56.5) y leería el detalle de faltas que no instruye
ella. Y descarté el legajo completo: el 56.7 prohíbe invocar lo cancelado, y
tenerlo a la vista invita a usarlo y a que la sanción se caiga por eso.

**SE ROMPE SI:** la líder necesita el detalle para decidir y el contador no le
basta. Entonces consulta a DO, que es quien instruye (54.4 c).

### 6 · Las cuatro migraciones van seguidas, en este orden

0566 el descargo previo · 0567 la propuesta de suspensión · 0568 las faltas graves
y la imputación · 0569 la advertencia de notificación.

El orden no es arbitrario: la 0566 es la que decide si los peldaños de arriba
apoyan en algo. Si se pegara al final, las suspensiones emitidas en el medio
tampoco contarían como escalón.

## Qué no hace este ADR

- No cambia la escalera de tardanzas ni la de inasistencias (arts. 19 y 21), que
  ya corren completas.
- No toca `fn_expediente_firmar`. Tiene ocho versiones y es la función más cara de
  revertir por accidente (el de la 0261). El descargo previo ya lo lee de la
  configuración desde la 0267.
- No mete la escalera disciplinaria en `/admin/parametros`. Es del RIT y solo se
  mueve atada a una versión del RIT: aplicar una escalera distinta a la que la
  persona recibió firmada vuelve impugnable la sanción.
- No decide el pendiente 78 (presentar el v4.0 ante la Autoridad Administrativa de
  Trabajo). Es de Gerencia.
- No arregla `fn_expediente_resolver`, donde la 0568 midió un defecto real:
  resolver no comprueba que el plazo de descargo haya vencido, así que hoy se
  puede archivar —o decidir el despido— el mismo día de la entrega, sin haber
  escuchado. `fn_expediente_crear_despido` pone esa puerta por su lado, que es
  donde se vuelve irreversible. Arreglar resolver es su propia entrega: pide su
  md5 de producción, y reescribirlo de paso es el accidente de la 0276.
