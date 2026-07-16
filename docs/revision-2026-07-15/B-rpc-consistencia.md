# B — Auditoría de consistencia entre funciones `fn_*` (2026-07-15)

Revisión de las ~85 definiciones `create or replace function fn_*` en
`supabase/migrations/*.sql` (0001 a 0034), quedándome solo con la ÚLTIMA
versión vigente de cada nombre. Foco: permisos, validación de inputs,
redondeo de montos, y consistencia entre `fn_planilla_calcular`,
`fn_provisiones`, `fn_calcular_bono_puntualidad` y `fn_recalcular_jornada`
(que evolucionaron por separado durante 34 migraciones). Solo lectura — no
se modificó ningún archivo salvo este reporte. No se ejecutó SQL.

Prioridad: 🔴 afecta dinero/datos hoy · 🟡 hueco real pero de impacto acotado
· 🟢 mantenibilidad / cosmético.

Mapa de "última versión" usado (por si alguien lo re-verifica): con
`grep -n "create or replace function fn_"` en todas las migraciones y
quedándome con el número de migración más alto por nombre. El caso
interesante es `fn_recalcular_jornada`: aparece en 0002, 0009, 0013, 0014,
0016 y 0017 — la vigente es **0017_salida_temprana_extra.sql:14**, no 0014
(quedó claro en el enunciado pero lo confirmo: 0016 > 0014 en orden, y 0017
> 0016).

---

## 🔴 Candado de periodo PAGADO: falta en la mitad de las funciones que deberían tenerlo

Confirmado con `fn_es_admin_o_lider()` y el patrón de bloqueo. El equipo
mismo documentó en `0026_parche_planilla_v2.sql:4-11` que "Editar feriados
alteraba los montos de planillas ya PAGADAS" y lo parchó ahí. El mismo
razonamiento aplica a **todo** lo que alimenta `fn_planilla_calcular`, pero
solo una parte de las funciones de escritura lo implementan.

**SÍ tienen el candado** (verifican `periodos_planilla.estado = 'pagado'` o
`fn_mes_planilla_pagado()` antes de escribir):
`fn_agregar_movimiento` / `fn_quitar_movimiento` (0025_planilla_periodos.sql:240-244,283-285),
`fn_set_objetivos` v3 (0032_objetivos_checklist.sql:362-364),
`fn_objetivo_agregar/marcar/editar/eliminar` (0032, líneas 216-218, 259-261, 288-290, 317-319),
`fn_set_feriado` / `fn_quitar_feriado` (0026_parche_planilla_v2.sql:112-117,134-139),
`fn_crear_periodo` / `fn_eliminar_periodo` (0026_parche_planilla_v2.sql, vía `estado='pagado'` directo).

**NO tienen el candado** (pueden escribir libremente sobre fechas que caen
dentro de un periodo ya pagado, sin aviso ni bloqueo):
- `fn_corregir_marcaje`, `fn_agregar_marcaje`, `fn_eliminar_marcaje` —
  `supabase/migrations/0010_correccion_supervisor.sql:55-125`. Solo llaman a
  `fn_verificar_corrector` (permiso), sin tocar `periodos_planilla`.
- `fn_set_turno`, `fn_set_descanso`, `fn_quitar_turno` —
  `supabase/migrations/0014_turnos_cobertura.sql:46-102`.
- `fn_set_horario` / `fn_quitar_horario` —
  `supabase/migrations/0011_editor_horarios.sql:8-62` (fn_set_horario tiene
  versión más nueva en 0015, mismo problema).
- `fn_set_horario_semanal` — `supabase/migrations/0016_horario_por_dia.sql:36-91`.
- `fn_set_salario` — `supabase/migrations/0019_salarios.sql:53-106`.
- `fn_set_fecha_ingreso` — `supabase/migrations/0027_feriado_por_ingreso.sql:41-54`.
- `fn_set_con_hijos` — `supabase/migrations/0025_planilla_periodos.sql:76-87`.

**Escenario concreto:** el periodo de junio ya está marcado `pagado`. Una
encargada de sede corrige un marcaje de un integrante (p.ej. cambia una
hora de entrada del 15 de junio con `fn_corregir_marcaje`, motivo "typo").
El trigger `trg_marcajes_recalcular_jornada` recalcula esa `jornada`
inmediatamente — cambia `horas_trabajadas` y/o `minutos_tarde` para una
fecha que ya se pagó. Si alguien vuelve a abrir la boleta de esa persona
(`fn_proyeccion_periodo`) o corre `fn_calcular_bono_puntualidad` de nuevo
sobre ese periodo, el número YA NO coincide con lo que se pagó — sin que
nadie haya tocado `periodos_planilla.estado`. Mismo problema con
`fn_set_salario` con `p_vigente_desde` retroactivo (cambia `pago_base` de
un periodo pagado) o `fn_set_fecha_ingreso` (cambia qué feriados
corresponden, justo el bug que 0027 existe para resolver — pero sin
candado de periodo, se puede reintroducir retroactivamente).

**Fix sugerido:** el patrón ya existe y está probado (`fn_agregar_movimiento`,
`fn_set_objetivos`) — extenderlo a estas 7 funciones. Para las que tocan
`marcajes`/`turnos`/`horarios_asignados` (fechas, no periodos), se puede
resolver la fecha a `periodo_id` con
`select 1 from periodos_planilla where estado='pagado' and p_fecha between fecha_ini and fecha_fin`
igual que ya hace `fn_set_feriado`. Para `fn_set_salario`/`fn_set_con_hijos`
(no reciben fecha explícita, aplican "desde hoy" o versionado), evaluar si
el candado debe ser sobre `p_vigente_desde` o sobre "cualquier periodo
pagado posterior a hoy" — es una decisión de producto, no solo técnica.

---

## 🔴 `fn_provisiones` tiene el MISMO bug de zona horaria que ya se corrigió en el bono

`supabase/migrations/0030_provisiones_anual.sql:35`:
```
v_as_of := coalesce(p_as_of, current_date);
```
Es exactamente el bug que el propio `0034_bono_puntualidad.sql` documenta
haber corregido (líneas 82-85 de ese archivo): `current_date` en Supabase
corre en UTC, no en hora Lima (UTC-5). Desde las 7pm hora Lima en adelante,
`current_date` ya "cree" que es el día siguiente.

**Dónde pega en `fn_provisiones` (0030):**
- **`v_prox_fecha`** (líneas 57-70): el "próximo desembolso" se elige con
  `where fecha >= v_as_of`. Si hoy es 15-jul (día de pago de grati_s1) y son
  las 8pm hora Lima, `v_as_of` ya vale 16-jul → la fila `(g1_pago='15-jul', ...)`
  queda excluida por `fecha >= v_as_of` siendo falsa, y la pantalla de
  provisiones muestra como "próximo" el SIGUIENTE desembolso en vez del que
  se paga hoy mismo — justo la noche del día de pago.
- **`vac_dias` / `aniv_ini` / `aniv_next`** (líneas 103,113-114): usan
  `age(v_as_of, p.fecha_ingreso)` para calcular el aniversario. Si el
  aniversario de alguien es el 15-jul y son las 8pm del 14-jul hora Lima
  (ya 15-jul en UTC), el sistema cree que el aniversario YA pasó un día
  antes de tiempo, corriendo la ventana de vacaciones un día.
- **Las ventanas `g1/g2/cm/cn/vv`** (líneas 116-120) usan `least(v_as_of, ...)`
  como tope — con `v_as_of` adelantado, el tope de acumulación es un día
  más tarde de lo real (normalmente inofensivo porque no hay `jornada` para
  un día que aún no ocurrió en Lima, pero sí afecta el borde exacto descrito
  arriba).

**Fix sugerido:** mismo que en 0034 —
`v_as_of := coalesce(p_as_of, (now() at time zone 'America/Lima')::date);`

---

## 🔴 `fn_auto_cierre` quedó desactualizado: ignora `turnos` y `horario_por_dia`

`supabase/migrations/0007_auto_cierre.sql:61-70` resuelve la hora de salida
programada así:
```sql
left join lateral (
  select hora_salida
  from horarios_asignados
  where persona_id = j.persona_id
    and vigente_desde <= j.fecha
    and (vigente_hasta is null or vigente_hasta >= j.fecha)
  order by vigente_desde desc limit 1
) h on true
```
Esto es el modelo de horario de **antes de 0013** (un solo horario fijo por
persona). Pero `fn_recalcular_jornada` evolucionó desde entonces con
prioridad `turno del día → horario_por_dia (jsonb, por día de semana) →
hora única legacy` (ver `0017_salida_temprana_extra.sql:80-104`).
`fn_auto_cierre` **nunca se actualizó** — sigue leyendo directo
`horarios_asignados.hora_salida`, que desde 0016 es solo una columna
"resumen" (`max(...)` de las horas de salida de cada día, ver
`0016_horario_por_dia.sql:66`), y no consulta la tabla `turnos` en absoluto.

**Escenario concreto:** una persona con horario base de día (16:00 de
salida) tiene un `turno` especial hoy con salida a las 22:00 (cubre un
cierre nocturno). `fn_auto_cierre` corre cada 15 min (`0007:118`, cron), ve
que su jornada sigue `abierta`, calcula el corte contra `horarios_asignados.hora_salida`
= 16:00 (o el máximo semanal, que puede no ser 22:00 tampoco) + 3h de
margen ⇒ cierra automáticamente su jornada ~19:00, en pleno turno, genera
un `marcaje` sintético `salida_final`/`auto_cierre`, dispara el trigger de
recálculo con una `salida_final_ts` falsa, y `horas_trabajadas` sale corto.
Igual de mal si el `horario_por_dia` de esa persona varía por día de semana
sin usar `turnos` — el resumen `hora_salida` (max de la semana) puede no
coincidir con el día real.

**Fix sugerido:** replicar en `fn_auto_cierre` el mismo lookup en cascada
que usa `fn_recalcular_jornada` (turno del día → `horario_por_dia[dow]` →
legacy), en vez de ir directo a la columna resumen. Es lógica que ya existe
y está probada — el riesgo es justamente que vive copy-pasteada (ver
sección de duplicación más abajo) y una de las copias no se actualizó.

---

## 🟡 `fn_set_meta_cobertura`: guard de permiso null-inseguro + sin revoke de PUBLIC/anon

`supabase/migrations/0014_turnos_cobertura.sql:105-119`:
```sql
create or replace function fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana int, p_meta int)
...
begin
  if fn_rol_actual() not in ('admin', 'lider_do') then
    raise exception 'Solo un administrador puede definir la meta de cobertura.';
  end if;
  ...
```
Todo el resto del código usa a propósito el patrón `x is not true` o
`x is null or x not in (...)` precisamente porque `fn_rol_actual()` devuelve
`NULL` para cualquier identidad autenticada sin fila en `personas` (un
terminal) — y en SQL, `NULL NOT IN (...)` da `NULL`, no `true`, así que
`if NULL then raise` **no lanza la excepción**. Los comentarios en
`0019_salarios.sql:66-67`, `0020_rpc_bypass_cache.sql:82-83` y
`0032_objetivos_checklist.sql:19-20` documentan exactamente este patrón
como algo a evitar ("`is not true`: nunca `if not f()`"). `fn_set_meta_cobertura`
es la única función de todo el repo que usa la forma insegura —
confirmado con grep, es la única ocurrencia de `not in (...)` sin el
`is null or` delante.

Además, `grant execute on function fn_set_meta_cobertura(uuid, int, int) to authenticated`
(línea 124) nunca tiene su contraparte `revoke execute ... from public, anon`
— y por defecto Postgres otorga `EXECUTE` a `PUBLIC` en toda función nueva.
El propio equipo descubrió y documentó este problema en
`0023_parche_areas.sql:6-10` ("el rol anon podía invocar las RPC") y
parchó una lista de funciones — pero `fn_set_meta_cobertura` (y las de
marcajes/turnos/horarios, ver abajo) quedaron fuera de ese parche.

**Efecto combinado:** cualquier request no autenticado (`anon`), o una
sesión de terminal autenticada (que tampoco tiene fila en `personas`),
puede llamar a este RPC y sobrescribir la meta de cobertura de cualquier
sede — el guard nunca lanza porque `fn_rol_actual()` es `NULL` en ambos
casos.

**Fix sugerido:** cambiar a
`if fn_es_admin_o_lider() is not true then raise exception ...` (reusa el
helper ya existente en vez de reimplementar el check) y agregar
`revoke execute on function fn_set_meta_cobertura(uuid, int, int) from public, anon;`.

---

## 🟡 Funciones sin `revoke ... from public, anon` explícito (posible ejecución anónima)

Comparé cada `grant execute ... to authenticated` contra su
`revoke execute ... from public, anon` correspondiente en todas las
migraciones. Estas quedan otorgadas a `authenticated` pero **nunca**
revocadas de `public`/`anon` en ningún archivo:

`fn_registrar_marcaje`, `fn_siguiente_tipo_esperado` (0002),
`fn_corregir_marcaje`, `fn_agregar_marcaje`, `fn_eliminar_marcaje` (0010),
`fn_set_turno`, `fn_set_descanso`, `fn_quitar_turno`, `fn_set_meta_cobertura`
(0014), `fn_set_horario`, `fn_quitar_horario` (0011/0015),
`fn_set_horario_semanal` (0016).

Para la mayoría de estas el impacto real es bajo porque internamente usan
`fn_verificar_corrector()` o consultan `personas where auth_user_id = auth.uid()`
— para `anon`, `auth.uid()` es `NULL`, no matchea ninguna fila, y el guard
sí lanza correctamente ("No autorizado."). Pero hay una excepción real:

**`fn_registrar_marcaje` (`supabase/migrations/0002_functions.sql:194-307`)**
— el camino `p_origen = 'terminal'` (el default, y el único que usa el
front hoy: ver `apps/web/lib/terminal/sync.ts:23`) valida la identidad del
terminal así (línea 233):
```sql
if auth.uid() is not null and v_terminal_auth is not null and auth.uid() <> v_terminal_auth then
  raise exception 'el terminal autenticado no coincide con p_terminal_id';
end if;
```
Si `auth.uid()` es `NULL` (llamada sin sesión, rol `anon`), la condición
completa es `false` por el primer operando — el chequeo de identidad se
**salta por completo**, no falla. Combinado con que `EXECUTE` nunca se
revocó de `anon` para esta función: un caller sin ninguna sesión, que
conoce un `p_terminal_id` válido (no es secreto — viaja en cada llamada
desde el propio cliente del terminal, ver `sync.ts:23`), puede invocar el
RPC directo y registrar marcajes arbitrarios (`p_persona_id`, `p_tipo`,
`p_timestamp_cliente` los elige el caller) sin PIN, sin sesión, sin pasar
por la UI. El PIN (`terminales.requiere_pin`, `0012_terminal_requiere_pin.sql`)
es una confirmación de la app — `fn_registrar_marcaje` no recibe ni valida
ningún PIN, así que llamar al RPC directo lo evita enteramente.

**Fix sugerido:** (a) agregar
`revoke execute on function fn_registrar_marcaje from public, anon;` como
mínimo — obliga a tener sesión `authenticated`, cerrando el vector más
fácil. (b) revisar si el modelo de terminales realmente requiere que
`anon` pueda llamar esto alguna vez (kiosco sin login) — si sí, el chequeo
de identidad debería ser al revés: exigir que SIEMPRE haya coincidencia
cuando el terminal tiene `auth_user_id` configurado, no solo "si ambos
lados están presented". (c) para el resto de la lista (turnos/horarios/
marcajes de corrección), agregar el revoke por higiene aunque el guard
interno ya los cubra — defensa en profundidad, mismo criterio que ya
aplicó 0023.

---

## 🟡 Redondeo: `fn_provisiones.gran_total` puede no cuadrar con la suma de sus partes mostradas

`supabase/migrations/0030_provisiones_anual.sql:96-108`:
```sql
'grati_total', round(v_f_grati * (coalesce(g1.pago,0) + coalesce(g2.pago,0)), 2),
'cts_total',   round(v_f_cts   * (coalesce(cm.pago,0) + coalesce(cn.pago,0)), 2),
'vac',         round(v_f_vac   * coalesce(vv.pago,0), 2),
...
'gran_total', round(
  v_f_grati * (coalesce(g1.pago,0) + coalesce(g2.pago,0))
  + v_f_cts * (coalesce(cm.pago,0) + coalesce(cn.pago,0))
  + v_f_vac * coalesce(vv.pago,0), 2)
```
`gran_total` redondea la SUMA de los tres componentes SIN redondear cada
uno primero; `grati_total`, `cts_total` y `vac` (los que se muestran en
pantalla) se redondean cada uno por separado. `round(a,2) + round(b,2) +
round(c,2)` no siempre es igual a `round(a+b+c,2)` — con montos reales
puede diferir en ±S/0.01. Quien mira la fila va a sumar mentalmente
`grati_total + cts_total + vac` y ocasionalmente no le va a cuadrar con
`gran_total`.

Contraste: `fn_planilla_calcular` (0027, línea 215) resuelve esto a
propósito sumando las partes YA redondeadas
(`round(pb.pago_base,2) + round(fer.monto,2) + ...`), con el comentario
explícito "el desglose siempre cuadra al céntimo" (0026:444/0027 mismo
patrón). `fn_provisiones` no sigue el mismo criterio.

**Fix sugerido:** construir `gran_total` sumando los tres campos ya
redondeados (`round(grati_parte,2) + round(cts_parte,2) + round(vac_parte,2)`),
igual que hace `fn_planilla_calcular`.

---

## 🟡 `fn_provisiones` no avisa cuando una persona no tiene `asignaciones_salario`

`fn_planilla_calcular` expone `horas_sin_salario` y `feriados_sin_salario`
(0027, líneas 195,205,227-228,248-249) precisamente para que el admin vea
cuando alguien tiene horas trabajadas pero ningún tramo de salario vigente
— en vez de mostrar plata en 0 sin explicación.

`fn_provisiones` no tiene ese aviso. Su CTE `base`
(`0030_provisiones_anual.sql:72-87`) usa:
```sql
from jornadas j
join lateral (
  select a.salario_mensual_soles as salario
  from asignaciones_salario a
  where a.persona_id = j.persona_id and j.fecha >= a.vigente_desde
    and (a.vigente_hasta is null or j.fecha <= a.vigente_hasta)
  order by a.vigente_desde desc limit 1
) tt on true
```
Es un `join lateral` normal (no `left join lateral`): si una persona no
tiene ningún tramo de `asignaciones_salario` que cubra esa fecha, esos días
simplemente NO entran a `base` — ni error, ni flag, ni fila. El resultado
final para esa persona es `grati_total`/`cts_total`/`vac` = 0, indistinguible
de "no acumuló nada legítimamente" (p.ej. recién ingresó y aún no le toca).

**Escenario:** a alguien se le olvida asignar salario con `fn_set_salario`
(recordar: tampoco tiene candado de periodo pagado, ver arriba) — en
Planilla se ve claramente como "horas sin salario" en rojo; en Provisiones
esa misma persona aparece con S/0.00 en todo, con cara de que está en
regla.

**Fix sugerido:** cambiar el `join lateral` a `left join lateral` y agregar
un contador de "días sin tramo de salario" al jsonb de salida, igual que
`fn_planilla_calcular`.

---

## 🟡 "Tramo de salario vigente en fecha X" está reimplementado por separado en 2 funciones

La misma lógica — "de `asignaciones_salario`, el tramo cuyo rango
`[vigente_desde, vigente_hasta]` cubre la fecha, más reciente primero" —
aparece escrita dos veces, de forma independiente:

- `fn_planilla_calcular`, CTE `tramos` + 3 usos vía lateral (`pb`, `ref`,
  `fer`) — `supabase/migrations/0027_feriado_por_ingreso.sql:161-168,226-264`.
- `fn_provisiones`, CTE `base`, lateral `tt` —
  `supabase/migrations/0030_provisiones_anual.sql:78-85`.

Hoy dan el mismo resultado, pero son dos SQL distintos manteniendo la misma
regla de negocio. Si mañana aparece un caso borde (dos tramos con la misma
`vigente_desde`, o hay que preferir el tramo por `created_at` en vez de
`vigente_desde` en un empate) alguien lo va a arreglar en el que esté
mirando y el otro va a quedar con el bug viejo sin que nadie se dé cuenta
— exactamente lo que ya pasó con `fn_auto_cierre` vs `fn_recalcular_jornada`
(ver arriba). No es un bug hoy, es un riesgo de mantenimiento.

**Fix sugerido:** no es urgente re-factorizar ahora (algo funcional > algo
elegante en producción real), pero si se toca alguna de las dos por otro
motivo, vale la pena extraer una función auxiliar
`fn_tramo_salario_vigente(persona_id, fecha) returns asignaciones_salario`
y que ambas la usen.

---

## 🟢 `fn_exigir_admin` es código muerto

`supabase/migrations/0009_correcciones.sql:158-170`. Sus 3 únicos call
sites originales (`fn_corregir_marcaje`, `fn_agregar_marcaje`,
`fn_eliminar_marcaje`) fueron reemplazados en 0010 para usar
`fn_verificar_corrector` en su lugar (soporta supervisor_sede, no solo
admin). Confirmado con grep: `fn_exigir_admin` no aparece invocada en
ninguna migración posterior a 0009. Sigue desplegada, sin usar.

**Fix sugerido:** `drop function if exists fn_exigir_admin()` en una
migración de limpieza, sin apuro.

---

## Comparación directa pedida: "días del periodo" y casos sin datos

| | `fn_planilla_calcular` (0027) | `fn_provisiones` (0030) | `fn_calcular_bono_puntualidad` (0034) |
|---|---|---|---|
| "días del periodo" | `(p_fin - p_ini) + 1`, fijo, NO se recorta a "hoy" aunque el periodo siga abierto | No tiene un solo "días del periodo": usa ventanas del año (`g1/g2/c1/c2`) recortadas con `least(v_as_of, ...)` | `least(v_fin, hoy_lima) - v_ini + 1` — SÍ se recorta a "hoy" mientras el periodo corre |
| "hoy" en zona horaria | No usa `current_date`/`now()` en ningún punto — todo lo pasa el caller | `current_date` (🔴 bug UTC, ver arriba) | `(now() at time zone 'America/Lima')::date` (correcto, ya parchado) |
| Persona sin `asignaciones_salario` | Aparece con `pago_base=0` + flag `horas_sin_salario`/`feriados_sin_salario` visible | Aparece con todo en 0, sin flag (🟡 ver arriba) | No aplica (el bono no depende del salario) |
| Persona sin `horarios_asignados`/`turnos` para un día | No afecta — `horas_trabajadas` no depende del horario, solo de marcajes entrada/salida | Igual, no depende del horario | El día se IGNORA (no cuenta ni suma ni resta) porque `minutos_tarde` queda `NULL` — comportamiento correcto y documentado en 0034 |
| Persona SIN NINGÚN horario nunca | Sigue apareciendo si tiene `jornadas` u horas | Sigue apareciendo si tiene `jornadas` con salario asignado | Queda excluida naturalmente: 0 días medidos / días del periodo nunca llega al 51% (documentado a propósito en 0034, líneas 16-18) |

La fila que manda revisar dos veces: `fn_planilla_calcular` NO recorta
"días" a "hoy" cuando el periodo está `abierto` y aún no llegó a
`fecha_fin` — el denominador (`v_base = 6.5 * v_dias`) es el del periodo
COMPLETO desde el primer día que se mira. Esto es intencional (la UI lo
usa como "cuánto va acumulado del total", ver
`docs/checklist-pendientes.md` → "Proyección de planilla del mes en curso"
en Fase 2) y no es un bug, pero vale la pena que quede escrito: si alguien
espera que `fn_proyeccion_periodo` de un periodo abierto muestre "el pago
correspondiente a las horas ya trabajadas" 1:1, en realidad muestra
horas-trabajadas ÷ horas-objetivo-DEL-PERIODO-COMPLETO × salario — que
solo coincide con el salario completo el último día del periodo.

---

## Resumen para Felipe

- 🔴 3 hallazgos con impacto en dinero/datos reales: el candado de periodo
  pagado falta en 7 funciones (marcajes, turnos, horarios, salario, fecha
  de ingreso, asignación familiar); `fn_provisiones` tiene el mismo bug de
  zona horaria que ya se corrigió en el bono; `fn_auto_cierre` cierra
  jornadas a la hora equivocada para cualquiera con turno especial u
  horario por día (corre cada 15 min, cron activo en producción HOY).
- 🟡 5 hallazgos de huecos de permisos/redondeo/visibilidad reales pero de
  impacto más acotado — el más serio es que `fn_registrar_marcaje` podría
  aceptar marcajes sin sesión si alguien llama al RPC directo con un
  `terminal_id` (no es secreto).
- 🟢 1 limpieza cosmética (función muerta).

Ninguno de estos requiere tocar la UI — todos son cambios dentro de las
funciones SQL. El de `fn_auto_cierre` y el del candado de periodo pagado
son los que yo priorizaría primero: uno corre solo cada 15 min sin que
nadie lo mire, el otro puede corromper silenciosamente una planilla que
Felipe ya cree cerrada.
