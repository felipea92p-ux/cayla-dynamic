---
name: skill-evaluacion-observabilidad
description: Audita la observabilidad de Dynamic en un módulo o en todo el sistema: ¿una RPC, un correo de Resend, el espejo de Google Sheets o el terminal sin internet pueden fallar sin que nadie se entere?, ¿hay `catch` que se traga el error, `console.*` sueltos, datos personales en logs o `fetch` sin tope de espera? Úsala al tocar integraciones, rutas de servidor o RPC, antes de optimizar nada, o cuando algo falló en una sede y nadie supo por qué.
---

> Adaptada de `skill-evaluacion-observabilidad` de `cayla-retail` (2026-11-06). El escáner vive en `scripts/rendimiento/`. Lo que cambió: Dynamic ya tiene
> Sentry, y sus integraciones son Resend, Google Sheets y el terminal offline, no SUNAT.

Audita la observabilidad de: $ARGUMENTS   (un archivo, un módulo, una integración como `alertas`, o `todo`)

**Regla madre:** sin evidencia no hay decisión de rendimiento ni de confiabilidad: hay opinión. Esta skill busca *dónde el sistema no sabe decir qué le pasó*. Toda integración externa se diseña asumiendo que ya está caída: la frase «se degrada así y no pierde este dato» tiene que existir, y la falla tiene que quedar registrada con su causa. Solo auditas y propones.

## Qué es y qué NO es observabilidad aquí

- **Auditoría de negocio ≠ observabilidad técnica.** `correcciones_auditoria` y `parametros_historial` dicen *qué hizo la persona*. Observabilidad dice *cuánto tardó, qué falló y por qué*. No marques «sin observabilidad» lo que solo es de auditoría, ni al revés.
- **Lo que ya existe:** Sentry (`instrumentation.ts`, `sentry.*.config.ts`), `app/error.tsx`, `app/global-error.tsx`, y `lib/alertas/causa-del-fallo.ts`, que traduce los fallos de Resend. Míralo antes de proponer otro mecanismo.
- **Datos personales** (DNI, sueldo, correo, nombre, teléfono, firma): nunca a un log ni a Sentry. Se registra el `id`, nunca el valor. El repo es público y el log sale de esta casa.
- **No instalar otra plataforma.** El mínimo sensato es duración y error de cada RPC crítica y de cada llamada externa, un `request_id` y Web Vitals.

## Paso 1 — Medir

```bash
node scripts/rendimiento/observabilidad.mjs            # infraestructura + higiene
node scripts/rendimiento/observabilidad.mjs --json     # hallazgos con archivo:línea
```

**Infraestructura** (sí/no) e **higiene** por AST: `console-suelto` · `catch-mudo` · `rpc-descartada` · `rpc-ignora-error` (`{ data }` sin `error`: una falla se confunde con «no hay datos») · `fetch-sin-tope` · `dato-personal-en-log` · `accion-sin-rastro`. Son pistas: **cada una se confirma leyendo el archivo**.

Medido el 2026-11-06, sin confirmar a mano: 572 llamadas `.rpc(`, 44 `rpc-ignora-error`, 40 `catch-mudo`, 4 `rpc-descartada`, 3 `fetch-sin-tope`. Infraestructura: sin logger estructurado, sin Web Vitals, sin `request_id`, y 3 límites de error para 68 pantallas. La regla de «límites de error» viene de Retail: el `error.tsx` global ya cubre, así que un «NO» ahí no es por sí solo un defecto.

## Paso 2 — Las cuatro preguntas (por módulo o integración)

1. **¿Qué pasa cuando no responde?** Una frase escrita. Si no se puede escribir, no está terminada. El modelo es el terminal: `lib/terminal/sync.ts`, `offline-db.ts` y `tope-de-red.ts`.
2. **¿Quedó registrada la causa?** Una alerta que no salió tiene que distinguirse de una que nunca se intentó, con el error del proveedor.
3. **¿Se puede reconstruir esta petición?** De la pantalla a la RPC con un mismo identificador. Verifica; hoy el escáner dice que no.
4. **¿Hay cifra?** p50 y p95 de las RPC críticas (`fn_registrar_marcaje`, `fn_planilla_calcular`), tasa de error y Web Vitals. Sin cifra, «está lento» es opinión.

Y los trabajos sin pantalla: `pg_cron` y `/api/alertas-encargadas` corren sin nadie mirando. ¿Quién se entera si dejan de correr?

## Paso 3 — Diseño mínimo

Una propuesta que afecta a más de un módulo es estructural: se presenta con `/decide` y espera a Felipe. Debe ser concreta: qué pieza, dónde y qué registra. Antes de proponer un módulo nuevo, mira si un envoltorio ya existente cubre muchas llamadas a la vez.

## Paso 4 — Informe

```
### <módulo o integración> — riesgo <alto|medio|bajo> (qué se pierde si falla en silencio)
- Hallazgo (tipo + archivo:línea) y cómo lo confirmé:
- Qué no sabríamos hoy si falla:
- Cambio mínimo: <diff corto o la pieza que se instrumenta>
- Verificación: <cómo se provoca la falla en local y dónde se ve el registro>
- Dato personal en juego: sí/no
```

Orden de riesgo: (1) lo que decide un pago o un marcaje, (2) lo que tiene plazo legal o una firma, (3) lecturas. Cierra con la objeción y con lo que no pidió.
