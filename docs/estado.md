# Dynamic — Estado y pendientes

**Este es el único archivo de estado.** Se sobrescribe al avanzar; no se crean
copias con fecha. La historia vive en git. Cómo se trabaja: ver
[`CLAUDE.md`](../CLAUDE.md) en la raíz.

*Última consolidación: 2026-07-26 (fusiona los handoffs del 13, 14, 18, 20 y 23
de julio, verificando cada punto contra el código actual). Auditoría completa
del sistema el 26-07 — 18 agentes sobre migraciones, dinero, seguridad, panel,
terminal, tests y deploy.*

---

## ⚠️ PENDIENTE DE FELIPE: pegar `aplicar_0076_a_0079.sql`

El paquete está listo en [`scripts/sql-manual/aplicar_0076_a_0079.sql`](../scripts/sql-manual/aplicar_0076_a_0079.sql).
Probado tres veces seguidas contra una simulación de producción: cero errores,
idempotente, con bloque de comprobación al final.

**Mientras no se pegue, esto está abierto en producción hoy:**
- 51 funciones `SECURITY DEFINER` ejecutables por el rol `anon` — la clave
  pública que viaja en el JavaScript del sitio. Entre ellas: registrar marcas
  por cualquier persona, sobrescribir cuentas bancarias, firmar memos.
- Una terminal de sede puede sobrescribir la cuenta bancaria y el DNI de
  cualquier colaboradora (**reproducido** contra Postgres limpio el 26-07).
- Los días de suspensión sin goce cuentan como faltas injustificadas y empujan
  al umbral legal de despido.

---

## Dónde estamos

Producción: **cayla-dynamic.vercel.app** · repo `~/Developer/cayla-dynamic`
(GitHub `felipea92p-ux/cayla-dynamic`, al día). Equipo real usándola a diario.

Sistema vivo y sano: terminal de marcaje en las 3 sedes, panel admin con 24
pantallas (planilla, provisiones, vacaciones, disciplina, turnos con cobertura,
objetivos SMART, boletas, reportes), motor de faltas y tardanzas con expediente
legal, feriados con descanso sustitutorio y actas firmadas. Migraciones hasta la
**0073** commiteadas; suite de tests SQL (smoke, planilla, reversa de pago,
vacaciones, tardanzas, faltas, marcajes fuera de orden) + vitest.

---

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
