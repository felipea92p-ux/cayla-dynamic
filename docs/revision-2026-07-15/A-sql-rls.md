# Auditoría profunda — supabase/migrations/*.sql (2026-07-15)

Revisión nocturna de los ~34 archivos de `supabase/migrations/` (schema, RLS,
funciones `security definer`, patrones de bug conocidos). Sin modificar código,
sin ejecutar SQL. Prioridad: 🔴 dinero/acceso comprometido hoy · 🟡 riesgo real
pero acotado · 🟢 cuando haya tiempo.

Motivación (contexto para quien lea esto sin el hilo original): hoy se
encontraron y corrigieron dos bugs reales en `fn_calcular_bono_puntualidad`
(`0034_bono_puntualidad.sql`): (1) `current_date` desnudo resuelve en UTC, no
en hora de Lima — después de las 7pm Lima cuenta un día de más; (2)
`coalesce(minutos_tarde, 0)` trataba "no medido" como "cero tardanza",
premiando a quien el sistema nunca pudo medir. Esta auditoría busca ese mismo
tipo de bug (y otros) en el resto de las migraciones.

## 🔴 Crítico — acceso/dinero comprometido

- [ ] **`fn_registrar_marcaje` se puede llamar sin iniciar sesión (rol `anon`)
  y marcar asistencia de cualquier persona** — `supabase/migrations/0002_functions.sql:233`
  (`grant execute ... to authenticated` en la línea 309, nunca revocado de
  `public`/`anon` en ninguna migración posterior — confirmado por grep en las
  34 migraciones). Postgres otorga `EXECUTE` a `PUBLIC` por defecto al crear
  una función; el propio equipo lo redescubrió en `0023_parche_areas.sql`
  ("Postgres da EXECUTE a PUBLIC por defecto... el rol anon podía invocar las
  RPC") y desde entonces cada función nueva agrega `revoke execute ...  from
  public, anon` — pero esa limpieza nunca se aplicó retroactivamente a las
  funciones de Sprint 0 (`fn_registrar_marcaje`, `fn_corregir_marcaje`,
  `fn_agregar_marcaje`, `fn_eliminar_marcaje`, `fn_set_horario`,
  `fn_quitar_horario`, `fn_set_turno`, `fn_set_descanso`, `fn_quitar_turno`,
  `fn_set_meta_cobertura`, `fn_siguiente_tipo_esperado`).
  Para la mayoría de esas funciones no importa: usan `fn_verificar_corrector`
  o `fn_exigir_admin`, que buscan `personas where auth_user_id = auth.uid()`
  — con `auth.uid()` NULL (caller anónimo) no encuentran fila, `v_rol` queda
  NULL, y explícitamente relanzan excepción. **Pero `fn_registrar_marcaje` no
  tiene ese candado para `p_origen = 'terminal'`** (el valor por defecto del
  parámetro): la única verificación de identidad es
  `if auth.uid() is not null and v_terminal_auth is not null and auth.uid() <> v_terminal_auth then raise exception ...`
  — si `auth.uid()` es NULL (caller sin sesión, solo con la anon key pública
  que viaja en cualquier bundle de cliente), la condición completa es `false`
  y el chequeo se salta enteramente. El resto de la función confía
  ciegamente en `p_persona_id` (parámetro, no derivado de la sesión).
  **Escenario concreto**: cualquiera con la anon key de Supabase (pública,
  no es secreta) puede llamar
  `fn_registrar_marcaje(persona_id_de_otro, 'entrada', '08:00 hoy', uuid_random(), 'terminal', id_de_un_terminal_real)`
  sin haber iniciado sesión como nadie, e insertar una marca de asistencia
  falsa para cualquier persona — a favor (fabricar puntualidad para el bono
  de `0034`, o para el cálculo de horas de planilla) o en contra (marcar una
  `salida_final` temprana de un compañero para perjudicarlo). `terminal_id`
  y `persona_id` son UUIDs no triviales de adivinar a ciegas, pero cualquiera
  con acceso de lectura al panel (cualquier `integrante` autenticado, o
  quien inspeccione el tráfico de red del kiosco) los puede leer y reusar.
  Esto afecta directamente planilla, provisiones y el bono de puntualidad de
  `0034` — es dinero real. **Fix sugerido**: revocar `execute` de
  `public`/`anon` en las 11 funciones listadas (igual que se hizo en 0023
  para la familia de áreas/salarios), y además exigir `auth.uid() is not
  null` explícitamente antes de confiar en cualquier terminal (hoy el check
  de coincidencia solo corre "si ambos lados no son null", lo cual es un
  candado que se autodesactiva justo cuando más se necesita: sin sesión).
  Verificar también en vivo (`information_schema.routine_privileges` o
  `\df+` en `psql`, no vía migración) que ninguna otra función quedó con
  `PUBLIC` implícito — esta auditoría solo pudo confirmarlo por texto de
  migración, no contra el estado real de la base.

- [ ] **`fn_set_meta_cobertura` usa el patrón `not in` en vez de `is not
  true` y falla ABIERTO para cualquier caller sin fila en `personas`** —
  `supabase/migrations/0014_turnos_cobertura.sql:110`.
  El código es `if fn_rol_actual() not in ('admin', 'lider_do') then raise
  exception ...`. El propio equipo identificó y documentó este patrón como
  peligroso más tarde (`0019_salarios.sql:66-67`, `0020_rpc_bypass_cache.sql:82-83`,
  `0032_objetivos_checklist.sql:20`: *"is not true (nunca if not f())"* —
  porque `fn_es_admin_o_lider()`/`fn_rol_actual()` devuelven NULL para
  cualquier identidad autenticada sin fila en `personas` (terminales, o aquí
  también un caller `anon`), y `NULL NOT IN (...)` es NULL, y `if NULL then`
  en PL/pgSQL se comporta como `false` — **no lanza la excepción** y la
  función sigue de largo hasta el `insert ... on conflict ... do update`.
  Esta función es exactamente el tipo de caso que la regla "is not true" fue
  creada para prevenir, pero quedó escrita ANTES de que la regla existiera
  (0014, antes de 0019/0020) y nadie la volvió a tocar. Sumado al hallazgo
  anterior (grant nunca revocado de `public`/`anon`), un caller sin sesión
  puede llamar `fn_set_meta_cobertura(cualquier_sede, 0-6, cualquier_meta)`
  y sobrescribir la meta de cobertura de cualquier sede/día sin ser admin ni
  estar autenticado. Impacto acotado (solo afecta el número de "meta" que se
  muestra en el dashboard de cobertura, no dinero ni PII), pero es el mismo
  patrón de fondo que el hallazgo anterior y confirma que no es un caso
  aislado. **Fix sugerido**: cambiar a
  `if fn_rol_actual() is distinct from 'admin' and fn_rol_actual() is distinct from 'lider_do' then raise exception`
  o mejor, reusar `fn_es_admin_o_lider() is not true`; y agregar el `revoke
  ... from public, anon` que le falta.

## 🔴 Zona horaria (mismo patrón que el bug ya corregido en 0034)

- [ ] **`fn_provisiones` usa `current_date` desnudo cuando no se pasa
  `p_as_of`** — `supabase/migrations/0029_provisiones_acumuladas.sql:38` y
  repetido en la versión que la reemplaza,
  `supabase/migrations/0030_provisiones_anual.sql:35`
  (`v_as_of := coalesce(p_as_of, current_date);`). Esta es exactamente la
  pregunta que se pidió verificar: **sí es un bug vivo**, no está resuelto en
  otro lado. `v_as_of` se usa para decidir en qué ventana semestral de
  gratificación/CTS cae "hoy" (comparaciones contra `make_date(v_y,7,15)`,
  `make_date(v_y,5,15)`, etc.) y como tope superior (`least(v_as_of,
  v_grati_fin)`) al sumar `pago_dia` acumulado de `jornadas` para grati/CTS/
  vacaciones. Cuando el frontend llama `fn_provisiones()` sin fecha explícita
  (el caso normal — "provisiones a hoy"), después de las 7pm hora Lima el
  servidor (UTC) ya cree que es el día siguiente: (a) puede incluir un día
  de más de horas trabajadas en el acumulado si esa jornada ya cerró
  temprano ese día, sobreestimando ligeramente grati/CTS/vacaciones
  acumuladas; y (b) en las fechas límite exactas (14-15 jul, 14-15 dic,
  14-15 may, 14-15 nov — justo los días de pago) puede hacer que la
  ventana activa cambie un día antes de lo debido, o que "próximo
  desembolso" (`0030`, `v_prox_fecha`) muestre la fecha equivocada esa
  noche. Es una vista informativa (no dispara un pago por sí sola como
  hace `fn_calcular_bono_puntualidad`), pero es la cifra que Felipe mira
  para decidir cuánto provisionar — mismo patrón, mismo archivo de
  referencia que ya se corrigió hoy. **Fix sugerido**: igual que en 0034,
  `coalesce(p_as_of, (now() at time zone 'America/Lima')::date)`.

- [ ] **`personas.fecha_ingreso` usa `default current_date` (UTC) y
  `fn_crear_persona` nunca lo sobrescribe** —
  `supabase/migrations/0001_init.sql:70` define la columna con
  `default current_date`; las tres versiones de `fn_crear_persona`
  (`0020_rpc_bypass_cache.sql:139-143`, `0021_areas.sql:176-181`,
  `0022_areas_catalogo.sql:176-181`) insertan personas nuevas SIN incluir
  `fecha_ingreso` en la lista de columnas, así que siempre cae en el
  default de la tabla — en UTC, no en hora de Lima. **Escenario**: una
  persona dada de alta desde el panel entre las 7pm y medianoche hora Lima
  recibe `fecha_ingreso` = mañana (fecha Lima) en vez de hoy. Esa fecha
  alimenta directamente el gate de feriados por ingreso
  (`0027_feriado_por_ingreso.sql`: *"un feriado se paga solo si feriado.fecha
  >= persona.fecha_ingreso"*) y las ventanas de provisiones
  (`greatest(v_grati_ini, p.fecha_ingreso)` en 0029/0030) — un ingreso
  corrido un día hacia adelante puede excluir a la persona de un feriado
  que sí le correspondía, o recortarle un día de provisión acumulada. Se
  autocorrige si alguien corre `fn_sembrar_ingresos` (que sí usa `at time
  zone 'America/Lima'` correctamente, ver `0028_ingreso_primera_marca.sql:23,49`)
  después de que la persona tenga marcajes reales, pero hasta ese momento
  (o para alguien sin marcajes aún) el dato queda silenciosamente mal.
  **Fix sugerido**: cambiar el `default` de la columna a
  `(now() at time zone 'America/Lima')::date`, o pasar `fecha_ingreso`
  explícito desde `fn_crear_persona`.

## 🟡 Riesgo real, impacto acotado

- [ ] **`fn_registrar_marcaje` no valida que `p_persona_id` pertenezca a la
  sede del terminal** — `supabase/migrations/0002_functions.sql:224-253`.
  Independiente del hallazgo 🔴 de arriba (caller sin sesión): incluso con
  un terminal legítimamente autenticado, la función nunca comprueba que la
  persona que se está marcando (`p_persona_id`) tenga `sede_base_id` igual
  a la sede del terminal (o `visible_todas_sedes`). El roster que el panel
  del kiosco muestra sí está filtrado por sede (`personas_select_terminal_roster`,
  `0008_visible_todas_sedes.sql`), pero eso es solo una restricción de UI —
  la RPC en sí acepta cualquier `persona_id` válido. Un terminal comprometido
  (o una sesión de terminal reusada/copiada) podría marcar asistencia de
  personal de OTRA sede. Menor severidad que el hallazgo de arriba porque
  requiere que el terminal ya esté autenticado. **Fix sugerido**: agregar
  `and exists (select 1 from personas where id = p_persona_id and (sede_base_id = v_sede_id or visible_todas_sedes))`
  al branch `p_origen = 'terminal'`.

- [ ] **`horas_trabajadas` se trata como 0 en la planilla cuando la jornada
  sigue abierta (aún sin marcar salida)** — patrón repetido en
  `0024_planilla.sql:245`, `0025_planilla_periodos.sql:387`,
  `0026_parche_planilla_v2.sql:193`, `0027_feriado_por_ingreso.sql:156`
  (`coalesce(j.horas_trabajadas, 0) as h`). `horas_trabajadas` es NULL en
  dos casos bien distintos: jornada en curso (persona todavía trabajando,
  sin `salida_final` — legítimamente "aún no se sabe") y falta de datos.
  Tratar ambos como "0 horas ese día" es razonable para un periodo ya
  cerrado (todo terminó), pero si `fn_simular_planilla` o
  `fn_proyeccion_periodo` se corren para un rango que incluye HOY con
  gente todavía trabajando, esas horas del día en curso desaparecen del
  cálculo en vez de mostrarse como "pendiente de cierre" — a diferencia de
  los días `auto_cerrada_pendiente`, que sí se cuentan y además se
  reportan aparte (`dias_pendientes`). No es el mismo bug que el de
  `minutos_tarde` (aquí 0 es una aproximación defendible, no una
  confusión conceptual), pero vale la pena que quien lea el número de
  planilla de un periodo aún abierto sepa que el día de hoy en curso no
  está reflejado. **Fix sugerido**: ninguno urgente; considerar exponer
  `dias_en_curso` igual que `dias_pendientes` para que la UI lo aclare.

- [ ] **`0004_grants.sql` otorga INSERT/UPDATE/DELETE a `authenticated` en
  TODAS las tablas de `public`, incluidas las futuras** —
  `supabase/migrations/0004_grants.sql:12,16`
  (`grant select, insert, update, delete on all tables in schema public to
  authenticated;` + `alter default privileges ... grant ... to
  authenticated`). Verificado: hoy las 21 tablas creadas por las
  migraciones SÍ tienen `enable row level security` (confirmado por grep
  cruzado entre cada `create table` y su `alter table ... enable row level
  security` correspondiente — no hay ninguna tabla huérfana). Pero esto
  significa que RLS es la ÚNICA barrera: si una migración futura crea una
  tabla y olvida el `enable row level security` (un simple lapsus, no un
  error de sintaxis que falle el deploy), esa tabla queda de inmediato
  legible y escribible por CUALQUIER identidad autenticada — cualquier
  `integrante`, o cualquier terminal — sin que nada lo señale. No es un bug
  hoy, pero es una trampa estructural para 0035 en adelante. **Fix
  sugerido**: ninguna acción sobre código ya escrito; agregar a la
  checklist de "nueva migración con tabla nueva": SIEMPRE `enable row
  level security` + al menos una policy, en el mismo commit que el
  `create table`.

## 🟢 Bajo impacto / informativo

- [ ] **`fn_set_fecha_ingreso` valida "no futuro" con `current_date`
  desnudo** — `supabase/migrations/0027_feriado_por_ingreso.sql:50`
  (`if p_fecha > current_date then raise exception 'La fecha de ingreso no
  puede ser futura.'`). Entre las 7pm y medianoche hora Lima, `current_date`
  (UTC) ya es "mañana" respecto a Lima, así que el guardia se vuelve un día
  más permisivo de lo debido (deja pasar un `p_fecha` que en Lima todavía
  es futuro). Solo lo usa un admin a mano, con feedback visual inmediato —
  impacto real muy bajo. **Fix sugerido**: mismo patrón,
  `(now() at time zone 'America/Lima')::date`.

- [ ] **Backfill de una sola vez en `0017_salida_temprana_extra.sql:187`
  usa `current_date - 60`** dentro de un bloque `do $$ ... $$` que corre
  UNA vez al aplicar la migración (no es una función que se re-ejecute).
  Mismo patrón UTC-vs-Lima, pero el efecto es, en el peor caso, recalcular
  un día menos o más de los 60 días de backfill — ya se ejecutó, no hay
  nada que corregir retroactivamente; se anota solo para que quien lea
  migraciones futuras del mismo estilo (backfills acotados) no repita el
  hábito de `current_date` desnudo.

- [ ] **`fn_calcular_bono_puntualidad` puede dividir por cero si se calcula
  para un periodo que aún no empezó** — `supabase/migrations/0034_bono_puntualidad.sql:85,112,140`
  (`v_dias_periodo := least(v_fin, hoy_lima) - v_ini + 1`, luego
  `dias_medidos::numeric / v_dias_periodo`). Si `v_ini` (inicio del
  periodo) es una fecha futura respecto a hoy Lima —por ejemplo si un
  admin crea un periodo con `fecha_ini` en el futuro y luego intenta
  calcular el bono antes de que arranque— `v_dias_periodo` puede quedar en
  0 o negativo, y la división lanzaría un error de Postgres (no un
  resultado silenciosamente incorrecto: es un `raise` visible, no una
  cifra mal calculada sin avisar). Baja severidad porque es ruidoso, no
  silencioso, y el flujo normal de creación de periodos (`fn_crear_periodo`)
  encadena `fecha_ini` al día siguiente del cierre anterior, así que un
  periodo "futuro completo" sin haber empezado es un caso de uso atípico.
  **Fix sugerido**: `if v_dias_periodo <= 0 then raise exception 'El
  periodo todavía no empieza.'; end if;` antes de dividir, para un mensaje
  más claro que el error genérico de Postgres.

## Confirmaciones positivas (no son bugs, quedan documentadas para no reabrir la duda)

- **`minutos_tarde` YA está bien manejado en todo el resto del código**:
  cada versión de `fn_recalcular_jornada` (0002 → 0017) deja `minutos_tarde
  = null` explícitamente cuando no hay hora esperada con qué comparar (sin
  turno/horario vigente, día de descanso, o diferencia > 180 min = "turno
  distinto, no medible"), y nunca se le aplica `coalesce(..., 0)` antes de
  0034 en ningún cálculo de dinero. El bug que se corrigió hoy en 0034 era
  nuevo en 0034, no una repetición de un patrón preexistente en otro lado.
- **La familia `asignaciones_salario` tuvo exactamente este tipo de
  hallazgo, y ya se corrigió dentro de las migraciones**: 0019 la creó con
  policy `for all` (escritura directa por REST), y
  `0024_planilla.sql:73-93` la reemplazó por una policy `for select` con
  el comentario explícito *"un admin podía escribir tramos directo por REST
  saltándose fn_set_salario"*. Confirmado que la versión vigente (0025) es
  solo lectura + escritura exclusiva vía `fn_set_salario`. Es la prueba de
  que el equipo ya hace este tipo de auditoría adversarial sobre sí mismo
  (ver también `0026_parche_planilla_v2.sql` y `0027_feriado_por_ingreso.sql`,
  ambos títulados "hallazgos de la auditoría/revisión").
- **Todas las 21 tablas creadas por las migraciones tienen RLS habilitado**
  y las que documentan "escritura solo vía RPC" (`turnos`, `metas_cobertura`,
  `areas`, `feriados`, `objetivos_mensuales`, `periodos_planilla`,
  `movimientos_planilla`, `objetivos_items`, `asignaciones_salario`) SÍ
  tienen su RPC `security definer` correspondiente y SÍ tiene un chequeo de
  permiso (con las dos excepciones ya listadas en 🔴/🟡 arriba:
  `fn_set_meta_cobertura` y el hueco de `fn_registrar_marcaje`).
- **El patrón `is not true` (en vez de `if not f()`) se aplica de forma
  consistente** en 39 de 40 chequeos de permiso encontrados — la única
  excepción es `fn_set_meta_cobertura` (🔴 arriba), que es anterior a que
  el patrón se adoptara como regla.
- **El patrón `grant execute ... to authenticated` + `revoke execute ...
  from public, anon` se aplica sin excepciones desde 0023 en adelante**
  (verificado programáticamente: cada función otorgada a `authenticated`
  en 0024-0034 tiene su revoke correspondiente en el mismo archivo). El
  hueco está exclusivamente en las funciones creadas ANTES de 0023 que
  nunca se revisitaron (ver 🔴 arriba).

## Numeración de migraciones

- [ ] **Confirmado: faltan 0031 y 0033 en `supabase/migrations/`** (no solo
  0031, como se sospechaba — también falta 0033). Ambos números SÍ existen,
  pero como scripts sueltos en `scripts/sql-manual/`:
  `aplicar_0031_historico_2025.sql` y `aplicar_0033_ingresos_2025.sql`,
  aplicados a mano contra producción (no vía el flujo de migraciones
  versionadas). Contenido verificado: ambos son *datos*, no schema — 0031
  inserta tramos de salario histórico nov-dic 2025 y jornadas de esos
  meses para 7 personas (para completar CTS-mayo), y mueve `fecha_ingreso`
  hacia atrás; 0033 corrige `fecha_ingreso` a la primera marca real del CSV
  2025 y agrega horas sep-oct de Danitza/Joselyn. No hay huecos de
  numeración adicionales ni números duplicados en `supabase/migrations/`
  (`0001` a `0030`, `0032`, `0034` — verificado con `ls | sort -V` y un
  chequeo de duplicados por prefijo numérico, sin coincidencias).
  **Riesgo concreto**: si alguna vez se reconstruye la base desde cero
  corriendo solo `supabase/migrations/*.sql` (nuevo entorno, disaster
  recovery, o un colaborador nuevo clonando el repo), estos dos pasos de
  datos NO se replican — las 7 personas afectadas quedarían con
  `fecha_ingreso` mal (la del alta original, no la real de 2025) y sin las
  jornadas/tramos de salario histórico de nov-2025 a oct-2025, lo que
  subestimaría silenciosamente su CTS/gratificación/vacaciones acumuladas
  en cualquier entorno reconstruido. Ambos scripts están escritos para ser
  idempotentes (usan `on conflict` / `not exists`), así que si se
  detecta el hueco, re-correrlos manualmente es seguro — el riesgo es
  NO darse cuenta de que faltan. **Fix sugerido**: mover (o copiar) ambos
  scripts a `supabase/migrations/` con sus números correspondientes (aunque
  sean scripts de datos, no de schema — Supabase no distingue y así quedan
  en el historial versionado y se re-aplican automáticamente en cualquier
  entorno nuevo), o como mínimo dejar una nota en
  `supabase/migrations/README` (si existe) o en este mismo repo señalando
  que 0031/0033 son pasos manuales obligatorios post-clonado.

---
Alcance: los 34 archivos de `supabase/migrations/` (0001-0030, 0032, 0034) +
los dos scripts de `scripts/sql-manual/` que llenan el hueco 0031/0033.
No se modificó ningún archivo ni se ejecutó SQL contra ninguna base.
