# Dynamic — Checklist de pendientes y mejoras (2026-07-14)

Fuente de verdad de lo que falta. Marcar con `[x]` al completar.
Prioridad: 🔴 afecta al equipo hoy · 🟡 valioso pronto · 🟢 cuando haya tiempo.

## 🔴 Detectado revisando el aplicativo (nuevo)

- [x] **Menú no funciona en celular** — ✅ EN PRODUCCIÓN 2026-07-14: menú
  hamburguesa en pantallas chicas (enlaces apilados, se cierra solo al navegar)
  y wrap en escritorio. Verificado en navegador móvil + HTML de prod.
- [x] **"¿Olvidaste tu clave?" no existe** — ✅ EN PRODUCCIÓN 2026-07-15: link
  en el login → correo con enlace de recuperación (Supabase Auth), probado de
  punta a punta (Felipe cambió su clave temporal con el flujo). El correo por
  defecto de Supabase no es 100% confiable (falló una vez sin dar error);
  pendiente evaluar SMTP propio si vuelve a pasar seguido.
- [ ] **Dashboard sin cobertura en vivo** — muestra la asistencia de hoy pero no
  dice "hay 3 presentes en TRU y la meta es 4". El dato ya existe; falta la fila
  de cobertura por sede.

## 🔴 Acordados pendientes (con spec lista)

- [x] **Módulo disciplinario de tardanzas** — ✅ HECHO 2026-07-17: Incidencias
  ahora avisa "Patrón de tardanzas (N en 30 días)" cuando alguien acumula 3+
  tardanzas en los últimos 30 días (ventana fija desde hoy, no depende del
  filtro Desde/Hasta de la página). Investigado el marco legal peruano antes
  de construirlo (D.S. 003-97-TR art. 25 + jurisprudencia): la ley no fija un
  número, exige reiteración + sanciones progresivas DOCUMENTADAS antes de
  poder despedir por esto — por eso Dynamic solo avisa, no sanciona ni decide
  nada solo. No se usaron las tablas `alertas`/`push_tokens` (necesitan una
  app móvil con push que no existe todavía) — se implementó reutilizando la
  página Incidencias que el equipo ya mira a diario.
- [x] **Bono de puntualidad auto-calculable** — construido 2026-07-15, pendiente
  aplicar migración 0034 y desplegar. Regla: cero tardanzas en el periodo = S/60
  fijo por persona (no depende de cuántos más lo logren; ajustable después sin
  deploy). Botón "🎯 Calcular bono de puntualidad" en Planilla.
- [ ] **Incidencia "trabajó sin refrigerio"** — Incidencias ya detecta 4 tipos
  (auto-cerrada, sin salida, sin retorno de pausa, salida anticipada); falta
  este quinto: día largo sin pausa marcada.

## 🟡 Mejoras de uso diario (detectadas revisando)

- [ ] **Objetivos: botón "copiar del mes anterior"** — cuando arranque agosto,
  la encargada va a tener que reescribir los objetivos de cada persona a mano.
- [x] **Boleta individual de pago** — ✅ EN PRODUCCIÓN 2026-07-14. Botón
  "🧾 Ver boleta" en cada fila de Planilla, imprimible (Ctrl+P → PDF), con el
  bloque de valor acordado (EsSalud/AFP/asignación familiar los cubre CAYLA;
  grati/CTS/vacaciones se acumulan).
- [ ] **Espejo a Google Sheets más legible** — encabezados fijos, una fila por
  persona (pendiente de antes).

## 🟢 Dependen de datos/decisiones de Felipe

- [ ] **Cuenta de Estefany** — falta su correo para crearle acceso.
- [ ] **Metas de cobertura por sede/día** — criterio de servicio de Felipe
  (habilita la cobertura en vivo del dashboard y las franjas horarias).
  Parcialmente hecho 2026-07-17: Turnos ahora se ve como línea de tiempo +
  mapa de calor de cobertura por hora, y hay una meta mínima de
  **encargadas** (supervisor_sede) editable por sede/día que avisa en
  Incidencias si no se llega. Falta la cobertura en vivo del Dashboard.
- [ ] **Revisar áreas reales de cada quien** — Carlos/Sandra eran "Ejecutivo",
  Joselyn "Diseño & Producción" en 2025.
- [ ] **Validar provisiones con el contador** — factores MYPE (grati 8.33% +
  CTS 4.17% + vacaciones 4.17%) están configurables; falta el visto legal.
- [x] **Subir el código a GitHub** — ✅ HECHO 2026-07-17: repo privado en
  `github.com/felipea92p-ux/cayla-dynamic`, al día. Antes de subir se limpió
  la PII que había en 6 scripts (ver `docs/revision-2026-07-15/`).

## 🟢 Fase 2 (más adelante)

- [ ] **Franjas horarias (mañana/tarde)** para cobertura más fina en Turnos.
- [ ] **Proyección de planilla del mes en curso** (cuánto va acumulado hoy).

---
Hecho hoy (2026-07-14): objetivos SMART en prod · fechas de ingreso reales 2025
(0033) · vacaciones completas de Danitza/Joselyn · código commiteado en git.
