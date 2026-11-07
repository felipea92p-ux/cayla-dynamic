# Prueba ciega — cómo se comprueba la ley 1 («sin manual»)

**Principio:** se observa lo que la persona **hace**, no lo que opina. «¿Te gusta?» no es evidencia: lo que la gente dice y lo que hace difieren
(es la lección de Jobs contra los focus groups, Isaacson). Se mide dónde duda, dónde se equivoca y qué pregunta.

Dos pasadas, en este orden. La primera es barata y repetible; la segunda es la verdad.

## Pasada 1 — agente ciego (Observado)

Se lanza con `Agent` (`general-purpose`) y un prompt que **solo** contiene lo que vería una colaboradora el primer día:

```
Eres <una integrante de una tienda de ropa | una líder de equipo | alguien de Desarrollo Organizacional>. Hoy es tu primer día con este sistema y nadie te lo explicó.
Abre <URL local o la captura>. NO leas archivos del repositorio, ni código, ni documentación, ni busques en la web: solo lo que ves en la pantalla.
Tu tarea: <una frase en lenguaje de tienda, p. ej. «Averigua cuántas horas trabajaste esta semana y si te falta alguna marca»>.

Mientras lo haces, anota SIN que te lo pidan:
 1. A los 5 segundos de abrir: qué crees que es esta pantalla y qué crees que sigue.   (escríbelo antes de tocar nada)
 2. Cada paso que das (qué tocaste y por qué).
 3. Cada vez que dudaste, y sobre qué palabra o elemento.
 4. Cada palabra que no entendiste, y cómo la interpretaste.
 5. Cada cosa que tocaste y no hizo lo que esperabas.
 6. Si terminaste la tarea y cómo sabes que quedó bien.
No opines si te gusta ni sugieras diseños. Solo cuenta qué hiciste y qué entendiste.
```

**Reglas que hacen válida la prueba**
- La tarea se escribe con **palabras de tienda**, nunca con los nombres del código ni de la pantalla.
- El agente **no tiene** el repo: si lo lee, la prueba se anula y se repite. Dilo al lanzarlo y revisa su transcripción.
- Un agente, una tarea, una pantalla: no se le pide opinar de varias cosas a la vez.
- Para el modal o la pantalla con datos, usa `dynamic-local`, con datos inventados; **nunca producción**: tiene DNI, sueldos y firmas.

**Qué se registra (la tabla del informe)**

| Medida | Cómo | Pasa si |
|---|---|---|
| Lectura de 5 s | ¿su frase del punto 1 coincide con la finalidad real? | coincide en lo esencial |
| Primer intento | ¿completó la tarea sin retroceder ni pedir ayuda? | sí |
| Pasos | cuántos toques hasta terminar | no más del mínimo + 1 |
| Dudas | ¿en qué palabra o elemento? | cada una es un hallazgo de ley 3, 4 o 9 |
| Palabras no entendidas | lista | cero |
| Errores evitables | tocó algo que no quería | cero |

## Pasada 2 — persona real (Observado, la que decide)

El agente puede dar **falsa seguridad**: un modelo no es una persona marcando con la fila detrás. Por eso la nota de «sin manual» de una
pantalla nunca llega a 10 sin esta pasada: queda **«ciega: pasa · real: sin probar»**.

- **3 a 5 personas** de distintas sedes (Nielsen y Landauer, 1993: con unas 5 aparece ~85 % de los problemas de uso; **Reportado**, cifra a tomar como orden de magnitud).
- Quien observa **no ayuda ni explica**, aunque la persona se trabe; solo anota. Si pregunta «¿qué es esto?», eso es el hallazgo.
- Misma tarea escrita en lenguaje de tienda; cronómetro simple; hoja con las seis medidas de arriba.
- Se prueba en **el equipo real**: la Mac mini de la sede o el celular de la persona, no el de Felipe.
- Resultado en 10 minutos: no es un estudio, es mirar dónde se atora una persona.

## Aprendido en el piloto de Retail (2026-10-05)
1. **Exige un formato y compruébalo.** Si el informe no trae las seis medidas de la tabla, la prueba no cuenta como Observado y se repite. Prefiere Sonnet u Opus.
2. **El entorno decide qué se prueba.** Antes de lanzar al ciego, verifica que la tarea es alcanzable con los datos de `scripts/local`. Si no, la prueba mide el entorno y no la pantalla.
3. Un dato que parece botón es hallazgo de la ley 1; algo que el ciego solo interpretó como botón sin serlo no es defecto de código. Distínguelos.

## Lo que esta prueba NO hace
No decide gusto ni estética (eso es «oficio visual», que se mide), no valida reglas de negocio y no reemplaza el criterio de Felipe sobre qué hace CAYLA.
