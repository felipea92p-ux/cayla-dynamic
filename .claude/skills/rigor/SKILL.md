---
name: rigor
description: Aplica rigor matemático explícito (conjuntos y álgebra relacional, complejidad algorítmica, agregación, estadística con poca muestra, resiliencia) a una decisión de esquema, RLS, función SQL, algoritmo o cifra de planilla. Úsala al diseñar una tabla, una política o una RPC, al elegir una estructura de datos o un índice, al promediar o rankear con pocas filas, o al tocar una integración externa.
---

> Adaptada de `rigor` de `cayla-retail` (2026-11-06). Lo que cambió: el esquema es `public`, el dinero es planilla, y los ejemplos son de
> Dynamic. No sustituye a `docs/planilla-anexo-tecnico.md`: se lee antes de tocar un cálculo de pago.

Aplica sobre: $ARGUMENTS

Antes de proponer el diseño, revisa cuál de estas cinco lentes cambia la decisión. Puede ser más de una, o ninguna. No es un ritual: si nombrarla no cambia nada, no la menciones.

1. **Conjuntos y álgebra relacional.** Antes de escribir un `WHERE` con varios `OR` o `NOT IN` anidados, o una política RLS nueva, pregunta si es una intersección o diferencia que Postgres resuelve mejor con `INTERSECT`, `EXCEPT` o un `JOIN` más selectivo. ¿La RLS ya filtra la mitad? `fn_es_admin_o_lider()` y compañía son el conjunto de verdad: no repitas ese filtro arriba. Una regla que debe valer siempre va en una restricción (`CHECK`, `EXCLUDE`, índice único), no en un `if`: los periodos, las ausencias y los sueldos ya son `EXCLUDE USING gist`, y por eso no pueden solaparse.

2. **Complejidad algorítmica.** Antes de un `.find()` o `.filter()` dentro de otro `.map()` o `for`, cuenta las filas reales: unas 30 personas, cuatro sedes, un periodo del 29 al 28, cientos de marcas al mes. Un `Map` o `Set` construido una vez casi siempre reemplaza el O(n²) sin cambiar el resultado. Con estos volúmenes, la complejidad importa por lo que acumula en una pantalla o en `fn_planilla_calcular`, no por una sola vuelta. Nómbralo en una frase: «cambié el `.find()` anidado por un `Map` porque son N personas × N días».

3. **Agregación.** Si el cálculo procesa series (horas de un periodo, ciclos de 7 días, provisiones), prefiere una sola pasada agregada, en SQL o en un solo `reduce`, sobre bucles que recalculan lo mismo fila por fila. Cuidado con lo que parece una ventana y no lo es: **los ciclos de sobretiempo no se solapan**, y una ventana móvil pagaría la misma hora siete veces.

4. **Estadística y dinero.** Con 2 a 12 personas por sede, una cifra sola es ruido. Antes de rankear, promediar o proyectar algo con pocas filas (una sede con dos personas, una semana con tres faltas), pregunta si ese número dice algo o si necesita más periodos. Un promedio que mezcla regímenes no significa nada: la jornada son 45 h/semana contra un máximo de 48, repartidas en 6 días en TRU y 5 en LIM y AQP.
   Para dinero, mantén `numeric` en Postgres. El riesgo está en TypeScript: si un `number` acumula redondeos en un bucle, redondea una sola vez al final. Y **ninguna cifra se da por buena a ojo**: un cálculo de planilla, provisiones, bonos o CTS se audita contra el Postgres local, dentro de `BEGIN … ROLLBACK`, con casos reales.

5. **Resiliencia.** Cuando el código depende de Resend, de Google Sheets o de una red de sede que se cae, modela la ausencia de respuesta como un valor que quien llama está obligado a mirar (`{ ok: false, motivo }`), no como una excepción que tumba la pantalla. Sin la frase escrita «se degrada así y no pierde este dato», la integración no está terminada. El modelo es el terminal: `lib/terminal/sync.ts` y `offline-db.ts` guardan el marcaje y lo reconcilian después.

**Regla de salida.** Si una lente cambió el diseño de forma no obvia, dilo en una frase. No la conviertas en un comentario nuevo salvo que explique un porqué. Si la decisión es de Felipe, el fundamento va como razón dentro de las opciones de `/decide`, no como sección aparte.

La señal de que una lente aplicó: cambiaste el diseño después de pensarla, no solo la nombraste para parecer riguroso.
