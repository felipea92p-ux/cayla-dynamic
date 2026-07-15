# CAYLA Dynamic — Estado y pendientes (handoff 2026-07-14)

App de asistencia + planilla. Prod: **cayla-dynamic.vercel.app**. Repo: `~/Proyectos/cayla-dynamic`.
Equipo real usándola (~23 personas, sedes TRU/LIM/AQP).

## Cómo se trabaja aquí (reglas)
- **SQL a producción:** Felipe lo pega en el **SQL Editor de Supabase** (el secret key está rotado, no se corren scripts contra prod). Cada SQL vive en `scripts/sql-manual/aplicar_00NN.sql` y su fuente en `supabase/migrations/`.
- **Deploy:** `cd ~/Proyectos/cayla-dynamic && npx vercel --prod --yes` (autenticado org "cayla"). **SIEMPRE preguntar antes de prod** (regla de Felipe); preview con `npx vercel --yes`.
- **OJO env:** `apps/web/.env.local` apunta al Supabase **LOCAL** (127.0.0.1). Prod real = `https://vovjyyiafkxteijimpuy.supabase.co`. Para diagnosticar prod, Felipe corre SELECTs en el SQL Editor.
- **Cálculos de plata:** SIEMPRE auditar el SQL empíricamente contra el Postgres local (docker `supabase_db_cayla-dynamic`, BEGIN…ROLLBACK) antes de dar el SQL. Guards SECURITY DEFINER null-safe: `if fn_es_admin_o_lider() is not true`.
- **Lenguaje:** "líder de equipo"/"encargada", nunca jefe/supervisor. Todo en español.

## En PRODUCCIÓN (aplicado y desplegado)
Migraciones 0019–0031 aplicadas + deploys (incl. **Provisiones anual /admin/provisiones**: 2 grati + 2 CTS + sumas + gran total + próximo pago; motor `fn_provisiones` 0030; histórico nov-dic 2025 de las 7 que continúan cargado en 0031 → CTS-mayo completa). Features vivas:
- **Salarios y rangos** por persona, versionados (Equipo). Rangos: colibri 1320 · cayla/caylo 1450 · support 1650 · aurora 1890 · oraculo 2250 · archicaylo 3000.
- **Áreas de CAYLA** (0021/0022): calidad_servicio + taller_produccion = operativas (cuentan cobertura); estrategia_comercial, desarrollo_organizacional, experiencia_marca, crecimiento_expansion. Página /admin/areas editable.
- **Plan B anti-caché** (0020): funcion + minutos_salida_temprana vía RPC jsonb (el caché de PostgREST no expone columnas nuevas).
- **Planilla** /admin/planilla (0024–0027): periodos encadenados + candado PAGADO + simulador + bonos/descuentos + asignación familiar S/113 + feriados por 3 + **feriado gateado por fecha de ingreso**. Motor `fn_planilla_calcular`. Modelo: pago = salario × horas/(6.5×días); ver [[project_dynamic_planilla_modelo]].
- **Fecha de ingreso** = primera marca (0028, sembrada). Estefany/Judith fijadas a jul-2026 (estaban a prueba). Salarios de 5 personas (Raquel/Paola/Dayana/Danixa/Keyla) extendidos a su ingreso.

## PENDIENTE INMEDIATO — ✅ COMPLETADO 2026-07-14
0030 + 0031 aplicados en prod y /admin/provisiones desplegada (HTTP 200). Lo de abajo ya está hecho; se conserva como registro.


1. **Aplicar `scripts/sql-manual/aplicar_0031_historico_2025.sql`** — carga nov-dic 2025 (jornadas + tramo salario 2025 + fecha_ingreso nov-2025) de las 7 que continúan (Sandra, Janis, Melany, Chiara, Carlos, Danitza, Joselyn) para completar la CTS-mayo. Datos de la hoja "Gratificaciones Dic 2025" (Joselyn calculada de sus marcas; usa el salario de 2025, no el actual). **VERIFICADO empíricamente 07-14 (6/6 PASS contra Postgres local): tramo 2025 sin violar el constraint de exclusión, 14 jornadas idempotentes, fecha_ingreso→nov-2025, y Chiara cts_may=111.21 usando salario 2025 (1320) no el actual (1450).** Idempotente. Su aniversario de vacaciones queda en nov-2026 (si Felipe da la fecha real de contrato, editar en Equipo).
2. **Aplicar `aplicar_0030.sql`** (fn_provisiones v2 anual: 2 grati + 2 CTS + sumas + gran total + próximo pago) — puede que ya esté aplicado; verificar. Página /admin/provisiones ya construida (compila) pero **NO desplegada** (Felipe pidió esperar al import 2025).
3. **Desplegar** a prod (preguntar) → estrena /admin/provisiones.
4. Verificar en la página que la CTS-mayo ya incluye nov-dic 2025.

Nota: la CTS-mayo es un depósito YA pagado (15-may); esto es registro histórico. Provisiones = régimen MYPE pequeña empresa (grati 8.33% + CTS 4.17% + vacaciones 4.17% sobre sueldo regular; factores en `configuracion.planilla_provisiones`; validar con contador).

## EN PRODUCCIÓN desde 2026-07-14 (tarde)
- **Checklist de objetivos SMART** (migración 0032 aplicada en prod por Felipe + página /admin/objetivos + vista solo-lectura en Perfil; desplegado, /admin/objetivos responde 200). Objetivos con texto por persona/mes; marcan solo admin/líder DO (todos) y encargada (solo integrantes de SU sede); el plus sale automático del checklist vía sync a `objetivos_mensuales` (motor de planilla intacto); mes pagado bloqueado (corregir = reabrir periodo); el número manual de Planilla queda bloqueado cuando el mes tiene checklist. Verificado: 12/12 tests SQL contra Postgres local + flujo completo en navegador local + preview validado por Felipe.

- **Fechas de ingreso reales 2025 (0033, aplicada en prod 2026-07-14):** las 7 que continúan de 2025 con ingreso = primera marca del CSV "Dynamic Time 2025" (Janis/Carlos 02/01 · Sandra 28/01 · Melany 13/03 · Chiara 15/05 · Danitza 30/09 · Joselyn 11/10) + horas sep-oct 2025 de Danitza (122.61h) y Joselyn (134.08h) con tramo de salario extendido. Verificación en prod: jornadas_sin_salario = 0 en las 7. El SQL vive en scripts/sql-manual/aplicar_0033_ingresos_2025.sql (fuera de git, datos personales). RESUELTO (Felipe 07-14): Keyla se ausentó mucho tiempo → su ingreso queda el de 2026 (los datos 2025 se conservan solo en el CSV); Raquel Pereda del CSV es OTRA persona; Felipe fundó CAYLA pero rara vez marca → queda 2026. No se cambia nada más.

## PENDIENTES DE FONDO (siguientes)
- **Incidencia "trabajó sin refrigerio"** (reportar cuando no marca pausa).
- **Módulo disciplinario de tardanzas** (ver [[project_dynamic_protocolo_disciplinario]]).
- **Bono de puntualidad** (auto-calculable) + otros 8 bonos (manuales).
- **Cambiar clave temporal de Felipe** (está en `TU_NUEVA_CLAVE` / la del panel) + construir "¿Olvidaste tu clave?" en el login.
- Revisar áreas reales de cada quien (Carlos/Sandra eran "Ejecutivo", Joselyn "Diseño&Producción" en 2025).
- **Commitear** todo el código a git (nada commiteado aún).

## Cómo retomar en un chat nuevo
Mi memoria (`MEMORY.md` + archivos) se carga sola. Di algo como:
"Continuemos con Dynamic (CAYLA). Lee docs/estado-y-pendientes.md y seguimos con el import 0031 + deploy de provisiones."
