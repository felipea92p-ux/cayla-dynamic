# Dynamic — Estado y pendientes

**Este es el único archivo de estado.** Se sobrescribe al avanzar; no se crean
copias con fecha. La historia vive en git. Cómo se trabaja: ver
[`CLAUDE.md`](../CLAUDE.md) en la raíz.

*Última consolidación: 2026-07-26 (fusiona los handoffs del 13, 14, 18, 20 y 23
de julio, verificando cada punto contra el código actual). Auditoría completa
del sistema el 26-07 — 18 agentes sobre migraciones, dinero, seguridad, panel,
terminal, tests y deploy.*

---

## ✅ APLICADO EN PRODUCCIÓN el 26-07-2026 — migraciones 0076 a 0080

Comprobación corrida por Felipe en el SQL Editor:

| revisión | resultado |
|---|---|
| Funciones abiertas a `anon` | **1** (eran 51; la que queda es un trigger, que la API no expone) |
| Migraciones registradas | **80** |
| Huecos en la numeración | **ninguno** |
| Permisos null-safe | **corregido** |
| Feriados cargados hasta | **25/12/2032** |

Qué cerró: la ejecución anónima de 51 funciones `SECURITY DEFINER` (registrar
marcas por cualquiera, sobrescribir cuentas bancarias, fabricar y firmar
memos) · el guard que dejaba a una terminal editar los datos bancarios de
cualquier colaboradora · la suspensión que contaba como falta hacia el umbral
legal de despido · el calendario de feriados que se acababa el 31-12-2026.

**La lección, que costó un intento fallido:** el primer pegado no aplicó nada.
El bloque que recorre las funciones abortaba entero al topar con una que no
pertenece al rol `postgres` de Supabase — que **no es superusuario** — y las
~1000 líneas siguientes nunca se ejecutaban, sin dejar rastro de por qué.
Probar como superusuario local no reproduce esa condición. Desde ahora, todo
bloque que recorra objetos en masa lleva manejo de excepción por elemento y
reporta al final lo que no pudo tocar.

---

## Dónde estamos

Producción: **cayla-dynamic.vercel.app** · repo `~/Developer/cayla-dynamic`
(GitHub `felipea92p-ux/cayla-dynamic`, al día). Equipo real usándola a diario.

Sistema vivo y sano: terminal de marcaje en las 4 sedes, panel admin con 24
pantallas (planilla, provisiones, vacaciones, disciplina, turnos con cobertura,
objetivos SMART, boletas, reportes), motor de faltas y tardanzas con expediente
legal, feriados con descanso sustitutorio y actas firmadas. Migraciones hasta la
**0073** commiteadas; suite de tests SQL (smoke, planilla, reversa de pago,
vacaciones, tardanzas, faltas, marcajes fuera de orden) + vitest.

---

## Decidido el 26-07, pendiente de construir (en este orden)

1. **Liquidación por cese + foto del pago.** Pantalla propia: sueldo pendiente +
   vacaciones truncas + grati trunca + CTS trunca, congelado e imprimible. La ley
   da 48 h desde el cese (art. 4 D.S. 001-97-TR), así que **no** se puede prohibir
   el cierre anticipado sin esto. Incluye el pago por horas del día de prueba, con
   recordatorio del T-Registro de 24 h. Al marcar PAGADO se guarda copia intacta
   de los montos y el sistema avisa si un recálculo posterior ya no coincide.
2. **Blindar planilla con pruebas** (descanso sustitutorio, bono de puntualidad,
   provisiones, feriado triple: hoy mueven dinero sin una sola prueba) y partir
   `planilla/page.tsx` (1 587 líneas).
3. **Los 4 scripts de `sql-manual` que divergen** de su migración fuente. El peor,
   `aplicar_0017`, lleva la fórmula vieja de tardanza: pegarlo retrocede el
   cálculo de horas de todo el equipo.
4. **Terminal, 4 bordes graves:** marca rechazada que se anuncia como "Listo" y
   desaparece · cola offline que se reenvía en orden de UUID y no cronológico ·
   reloj de la Mac sin verificación de desfase · persona que marca en dos sedes
   el mismo día y pierde una marca.

**Grati/CTS:** se aplicará la regla legal de regularidad (la sobretasa de feriado
entra solo si se percibió en ≥3 meses del semestre, como promedio entre 6) —
Felipe pidió ver primero el impacto con
[`consulta_impacto_regularidad_feriados.sql`](../scripts/sql-manual/consulta_impacto_regularidad_feriados.sql).

## 🔴 Atender primero

1. **La migración `0076` está escrita pero sin commitear y sin rastro de las
   `0074`/`0075`.** El repo salta de 0073 a 0076: o dos migraciones se aplicaron
   en prod sin quedar en el repo, o la numeración se corrió. Además no existe
   registro de qué migraciones están aplicadas en producción (`scripts/sql-manual/`
   llega hasta la 0034). Resolver: (a) aclarar 0074/0075 con Felipe, (b) commitear
   0076 cuando corresponda, (c) crear la tabla `migraciones_aplicadas` para que
   un SELECT diga la verdad de prod.

2. **Seguridad pendiente** (del audit `revision-2026-07-15/`, sigue abierto —
   verificado en código el 07-26; la 0076 ataca parte de esto y aún no está aplicada):
   - `generarClave()` usa `Math.random()` (`api/admin/cuentas/route.ts:13`) →
     cambiar a `crypto.randomInt`.
   - Terminal: falta la mitad de servidor (validar sesión y sede del terminal);
     misma familia: `api/reabrir-dia` no valida que la persona sea de la sede.
   - Contraseña mínima 6 sin complejidad, sin cambio forzado en primer login
     (cuentas que ven salarios).
   - Las rutas de API devuelven el mensaje crudo de Postgres → envolver.

3. **Partir `planilla/page.tsx` (1 587 líneas).** Maneja dinero. Los tests SQL
   que fijan la matemática ya existen (`supabase/tests/10` y `20`); falta el
   refactor del archivo antes de seguir tocándolo (Kent Beck: primero el terreno).

## 🟡 Valioso pronto

- **Versionar 0031 y 0033**: existen solo como `scripts/sql-manual/aplicar_*.sql`
  (fuera de git por PII). Crear versiones en `supabase/migrations/` con los datos
  personales parametrizados, para poder reconstruir la base.
- **Colibrí en cargas**: ~22 pantallas y ~49 estados vacíos sin marca (chat de diseño).
- **Integración Dynamic ↔ retail**: Fase 0 (reconciliación, solo lectura) lista
  para arrancar — `docs/integracion-retail/`.
- **Incidencia "trabajó sin refrigerio"** (quinto tipo: día largo sin pausa).
- **Objetivos: botón "copiar del mes anterior"** — urge al arrancar agosto.
- **Espejo a Google Sheets legible** (encabezados fijos, una fila por persona).

## 🟢 Dependen de Felipe / redondeo

- Datos personales: 5 fichas faltantes + celular/instrucción/estado civil (~13).
  Import SIN commitear PII.
- Validar factores de provisiones con el contador (MYPE: 8.33/4.17/4.17 — configurables).
- Revisar áreas reales de cada quien (Carlos/Sandra "Ejecutivo", Joselyn "Diseño" en 2025).
- Cuenta de Estefany (falta su correo).
- Checkbox "encargada de piso" en Equipo (hoy solo Janis, vía migración 0040).
- Split mañana/tarde configurable por sede (hoy fijo 14:15).
- Perfil V2 (buscador, "Mi perfil", vacaciones pre-seleccionadas) · limpieza de
  16 `as any` benignos · franjas horarias finas · proyección de planilla del mes.

---

## Decisiones tomadas (no reabrir)

- **Planilla**: régimen MYPE pequeña empresa, base 6.5 h, pago = salario × horas/(6.5 × días).
- **Fecha de ingreso = decisión de negocio, no cálculo.** Se edita persona por
  persona en Equipo; el botón masivo se eliminó (0041) porque ningún guard lo
  salvaba. Estefany (13/07) y Judith (01/07) quedan en julio a propósito.
- **Disciplina**: Dynamic avisa y documenta, nunca sanciona solo (D.S. 003-97-TR
  art. 25: umbrales 4 consecutivas / 6 en 30 d / 16 en 180 d).
- **Meta operativas TRU = 8**: correcta; el rojo del tablero es señal real de
  falta de personal, no error de meta.
- **Melany y Catherine como encargadas**: confirmado, a propósito.
- **Janis**: admin + encargada de piso a la vez (marca `es_encargada_piso`, 0040).
- **Keyla/Raquel/Felipe**: ingresos quedan 2026 (contexto en git: estado 07-14).

## Registro de lo cerrado (para no re-investigar)

Deshacer pago de planilla ✅ (0066 + test 30) · tests de planilla ✅ (suite SQL)
· push a GitHub ✅ · faltas Fase 2 completa ✅ (0051–0060: detección,
justificaciones, expediente, semáforo legal) · cobertura en vivo en Dashboard ✅
(07-18) · bono de puntualidad ✅ (0034 + fixes) · menú móvil ✅ · recuperar
clave ✅ (07-15; si el correo de Supabase vuelve a fallar → SMTP propio) ·
boleta individual ✅ · patrón de tardanzas ✅ · descanso sustitutorio con actas
✅ (0069–0073).
