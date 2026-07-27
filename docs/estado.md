# Dynamic — Estado y pendientes

**Este es el único archivo de estado.** Se sobrescribe al avanzar; no se crean
copias con fecha. La historia vive en git. Cómo se trabaja: ver
[`CLAUDE.md`](../CLAUDE.md) en la raíz.

*Última consolidación: 2026-07-27. Migraciones 0081–0089 aplicadas, dos
revisiones adversarias corridas sobre el trabajo del día, y 60 pruebas nuevas
donde por la mañana no había ninguna sobre el cálculo que produce el sueldo.*

---

## Dónde estamos

Producción: **cayla-dynamic.vercel.app** · repo `~/Developer/cayla-dynamic`
(GitHub `felipea92p-ux/cayla-dynamic`, al día). Equipo real usándola a diario.

Migraciones **hasta la 0089**, sin huecos ni números repetidos. La secuencia
completa aplica desde cero sobre una base limpia (que es lo que hace el CI).

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

**Escritas hasta la 0097; aplicadas en producción hasta la 0095.** Faltan pegar
la **0096** (la foto del pago) y la **0097** (costos) — sin ellas la pantalla de
Costos existe pero no tiene de dónde leer. La 0085, 0086 y 0087 (tipo de vínculo, fecha de cese,
beneficios truncos) siguen sin aplicar, sin urgencia: ninguna pantalla las usa
todavía. Son los cimientos de la liquidación por cese.

**Pendiente de correr una vez:** [`scripts/sql-manual/registrar_0088_0089.sql`](../scripts/sql-manual/registrar_0088_0089.sql).
Las 0088 y 0089 se aplicaron cuando aún se llamaban 0085 y 0086, y el registro
usa `on conflict (numero) do nothing`: como esos números ya estaban ocupados, la
base tiene los cambios pero el registro no lo dice. El script solo arregla eso.

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
     **`fn_cts_trunca` y `fn_vacaciones_truncas` siguen SIN probar.**
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
