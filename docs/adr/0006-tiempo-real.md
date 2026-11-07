# ADR 0006 — Las pantallas se enteran al instante: aviso por la base, lectura por las funciones

**Fecha:** 2026-11-07 · **Estado:** aceptado; lote 1 de 5 publicado el 2026-11-07 (0604 pegada, #703 fusionado) · **Decide:** Felipe

## Lo que se pidió

Que todo Dynamic se actualice en tiempo real, «de una manera similar a como hicimos en turnos y cobertura», usando
websocket, e investigar a fondo si hay otra forma segura, rápida y precisa.

## Lo que había

Nada usaba websocket. Turnos (2026-11-02) se ponía al día con un aviso entre pestañas del mismo navegador y una
relectura cada minuto (`lib/admin/turnos-al-dia.ts`), y su comentario decía que Realtime era «el paso siguiente». El
terminal decía «no hay Realtime a propósito: el terminal lee una VISTA». En total había nueve relojes que preguntaban
por su cuenta: el tablero cada 30 s, el terminal y el menú cada minuto, la Bandeja cada 5 min, entre otros. La
publicación `supabase_realtime` estaba vacía.

## La decisión

**DECIDÍ:** la base avisa por el canal privado de Realtime (Broadcast desde la base) que cambió un *tema*
—`asistencia`, `horarios`, `personas`…—, sin ningún dato. La pantalla vuelve a leer por las funciones de siempre, que
son las que revisan permisos. Si el aviso se pierde, relee al reconectar, al volver a la pestaña y cada 5 min.

**DESCARTÉ:** *Postgres Changes*, la forma fácil, en la que la fila viaja por el websocket. Pondría sueldos y DNI a
viajar por un segundo canal con su propio control de permisos, no ve la vista del terminal, no respeta los filtros en
los borrados, y Supabase misma recomienda Broadcast «por escalabilidad y seguridad». También descarté **SSE desde
Vercel** (no sostiene conexiones largas: haría falta un servidor más), **Ably o Pusher** (otro proveedor y otro lugar
con permisos, para 30 personas) y los **motores de sincronización** (PowerSync, Electric, Zero): habría que reescribir
las 69 pantallas y duplicar las reglas de acceso fuera de la base. Y la **relectura más corta**: con 10–15 s de
demora, de 4 a 6 veces más lecturas.

**SE ROMPE SI:** alguien crea una tabla que una pantalla muestra y no le pone su aviso. Esa pantalla vuelve en silencio
a ponerse al día cada 5 min. Lo cierra la prueba 491, que falla si una tabla de `public` no está vigilada, pendiente de
un lote o excluida con su motivo.

## Cómo funciona (migración 0604, `lib/tiempo-real.ts`)

| Pieza | Qué hace |
|---|---|
| `fn_tiempo_real_avisar()` | Trigger **por sentencia**: un aviso por tema y por transacción, ninguno si la sentencia no tocó filas. Lo revertido no avisa. Atrapa cualquier error: nunca frena un guardado. |
| `fn_tiempo_real_enviar(tema)` | Llama a `realtime.send` con `{tema}` y nada más. Si la base no tiene Realtime (CI, banco local), no hace nada. |
| `fn_tiempo_real_vigilar(tabla, tema)` | Pone los tres triggers de una tabla. Postgres no permite uno solo de tres eventos con tablas de transición. |
| `fn_tiempo_real_puede_escuchar(topic)` | La única respuesta a «¿esta sesión puede escuchar este canal?». La política de `realtime.messages` solo la llama. Hoy: panel (admin, DO, líderes de equipo) y terminales activos. Un tema desconocido queda cerrado. |
| `useAlDia(temas, ponerseAlDia)` | Relee en silencio: al aviso, al (re)conectar, al volver a la pestaña y cada 5 min. No lee encima de quien escribe, ni con la pestaña oculta, ni más de una vez por segundo. Un canal por tema, compartido entre pantallas. Devuelve el estado del canal, para que «en vivo» no mienta. |

## Medido

- **En la pila local con Realtime v2.124.2:** un aviso cada 1.5 s, 20 de 20, mediana 38 ms. Una ráfaga de 50
  transacciones en 121 ms, 50 de 50, mediana 45 ms y máximo 64 ms. Costo por escritura: +0.04 ms.
- **De punta a punta en el entorno local, con las cuentas inventadas:** del guardado a la relectura en pantalla, ~300 ms
  en Turnos, el tablero y el terminal. Una integrante no puede escuchar.
- **Tablero en reposo:** 0 consultas en 62 s, contra dos lecturas completas por minuto antes.
- **Corte de Realtime:** la etiqueta pasó a «se pone al día cada 5 min». Un marcaje hecho durante el corte apareció
  solo al volver la conexión.
- **Candados:** la migración se pega de una vez tomando los candados sin esperar. El control ingenuo (esperar en el
  orden contrario) cerró un deadlock y la víctima fue el marcaje. La 0604, no.
- **Pruebas:** la pgTAP 491 da 33/33 con Realtime y sin él. Suite A/B: 395/395 en verde con la 0604. Siete roturas a
  propósito, siete rojos. Vitest 3 650 en verde.

## Lo que sigue (lotes)

1. **Asistencia, horarios y personas:** tablero, Turnos, Horarios, terminal, Incidencias y Bandeja del menú. *Publicado el 2026-11-07 (#703).*
2. **Solicitudes:** Bandeja, Ausencias, cambios de turno, Correcciones, reportes.
3. **Personas y documentos:** fichas, contratos, documentación, educación, seguros, catálogos.
4. **Plata y disciplina:** planilla, liquidaciones, boletas, memos. **Con aviso «Hubo cambios · Actualizar», no
   refresco solo.** Que un número se mueva mientras alguien lo revisa para pagarlo es un error de diseño.
5. **Lo mío:** un tema por persona (`persona:<id>`), que solo escucha esa persona.

La lista de tablas por lote vive en `supabase/tests/491_*.test.sql`.

## Lo que esto no resuelve

El tiempo real hace que la pantalla esté al día, pero **no evita que dos personas se pisen**. Si dos líderes de equipo
tienen abierto el mismo horario y guardan, la última borra a la primera sin aviso. Eso pide que cada guardado compruebe
que nadie cambió el horario desde que se abrió. Queda como trabajo aparte.
