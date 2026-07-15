# Dynamic — Checklist de pendientes y mejoras (2026-07-14)

Fuente de verdad de lo que falta. Marcar con `[x]` al completar.
Prioridad: 🔴 afecta al equipo hoy · 🟡 valioso pronto · 🟢 cuando haya tiempo.

## 🔴 Detectado revisando el aplicativo (nuevo)

- [ ] **Menú no funciona en celular** — la barra de navegación no colapsa: en
  pantallas angostas se corta y hay que hacer scroll horizontal (las encargadas
  seguramente entran desde el teléfono). Falta menú hamburguesa/responsive.
- [ ] **"¿Olvidaste tu clave?" no existe** — si alguien olvida su clave, hoy no
  hay forma de recuperarla sola; depende de Felipe. (Incluye cambiar la clave
  temporal de Felipe.)
- [ ] **Dashboard sin cobertura en vivo** — muestra la asistencia de hoy pero no
  dice "hay 3 presentes en TRU y la meta es 4". El dato ya existe; falta la fila
  de cobertura por sede.

## 🔴 Acordados pendientes (con spec lista)

- [ ] **Módulo disciplinario de tardanzas** — alertas por patrón en ventana de
  30 días + historial; Dynamic alerta, el admin decide, nada automático. Las
  tablas `alertas` y `push_tokens` ya existen en la base y hoy nadie las usa:
  son la base natural de este módulo.
- [ ] **Bono de puntualidad auto-calculable** — Dynamic ya mide tardanzas por
  minuto; falta la regla y mostrarlo en Planilla junto a los 8 bonos manuales.
- [ ] **Incidencia "trabajó sin refrigerio"** — Incidencias ya detecta 4 tipos
  (auto-cerrada, sin salida, sin retorno de pausa, salida anticipada); falta
  este quinto: día largo sin pausa marcada.

## 🟡 Mejoras de uso diario (detectadas revisando)

- [ ] **Objetivos: botón "copiar del mes anterior"** — cuando arranque agosto,
  la encargada va a tener que reescribir los objetivos de cada persona a mano.
- [ ] **Boleta individual de pago** — la planilla exporta CSV general, pero no
  hay un resumen por persona (imprimible/PDF) para entregar con el pago.
- [ ] **Espejo a Google Sheets más legible** — encabezados fijos, una fila por
  persona (pendiente de antes).

## 🟢 Dependen de datos/decisiones de Felipe

- [ ] **Cuenta de Estefany** — falta su correo para crearle acceso.
- [ ] **Metas de cobertura por sede/día** — criterio de servicio de Felipe
  (habilita la cobertura en vivo del dashboard y las franjas horarias).
- [ ] **Revisar áreas reales de cada quien** — Carlos/Sandra eran "Ejecutivo",
  Joselyn "Diseño & Producción" en 2025.
- [ ] **Validar provisiones con el contador** — factores MYPE (grati 8.33% +
  CTS 4.17% + vacaciones 4.17%) están configurables; falta el visto legal.
- [ ] **Subir el código a GitHub** — los commits están solo en la Mac de
  Felipe; decir "sube" cuando quiera el respaldo en la nube.

## 🟢 Fase 2 (más adelante)

- [ ] **Franjas horarias (mañana/tarde)** para cobertura más fina en Turnos.
- [ ] **Proyección de planilla del mes en curso** (cuánto va acumulado hoy).

---
Hecho hoy (2026-07-14): objetivos SMART en prod · fechas de ingreso reales 2025
(0033) · vacaciones completas de Danitza/Joselyn · código commiteado en git.
