# Auditoría CAYLA Dynamic — agosto 2026

Emitida el **2026-08-17**. Sistema **en producción**, pagando a ~30 personas en cuatro sedes.

> **Nota del 2026-08-18.** Este informe se regeneró tras perderse el original: quedó sin commitear en un árbol compartido por cuatro sesiones y otra sesión movió el árbol. Los datos de los 116 agentes sobrevivieron intactos y el contenido es el mismo. Las referencias a migraciones concretas son del estado del **17 de agosto** (`main` en `696e74d`, última migración aplicada 267); entre el 17 y el 18 entraron la 0269 a la 0273, así que antes de actuar sobre un hallazgo de planilla hay que volver a preguntar con `./scripts/donde-vive.sh` cuál es la función vigente.

**Cómo se hizo.** 116 agentes en dos tandas. Cada hallazgo pasó por un verificador independiente cuyo encargo era **refutarlo**, no confirmarlo, con instrucción de caerse ante la duda y de comprobar primero si el `CLAUDE.md` ya lo tenía decidido o si estaba entre los cinco defectos aparentes que `docs/planilla-anexo-tecnico.md` ya midió y descartó. **De 99 hallazgos propuestos, 19 murieron ahí.** Lo que sigue son los 80 que sobrevivieron.

**Criterio.** Las «doce exigencias» que el encargo cita viven en `~/.claude/CLAUDE.md`, y ese archivo **no existe** en el disco (comprobado: en `~/.claude/` solo hay `settings.json` y `settings.local.json`). Por decisión de Felipe, cada hallazgo se ancla al `CLAUDE.md` **de este repositorio**, que sí tiene criterio escrito y ganado a golpes.

**Límites respetados.** Ni una escritura contra ninguna base: las mediciones van dentro de `BEGIN … ROLLBACK` contra el Postgres local. Cero migraciones. Cero commits. Comprobado al terminar: `git status` vacío, `origin/main…HEAD` en 0/0, base local en 0 filas.

**Qué quedó fuera, y por qué.** El encargo pedía auditar stock e inventario, multi-tenant (`tenant_id`), y las integraciones Culqi, Nubefact/SUNAT y Shopify. **Nada de eso existe en este repositorio** — medido: 0 columnas `tenant_id`, 0 tablas de stock, y las únicas dependencias externas son Supabase y Sentry. Felipe confirmó que eran referencias de otro proyecto. También pedía formato de migración `YYYYMMDD_HHMMSS`: aquí la convención es `00NN_descripcion.sql`, con un hook que verifica la numeración en cada push.

---

## 1 · Veredicto por eje

| Eje | Ubicación | Lo que le falta para el siguiente escalón |
|---|---|---|
| **Integridad arquitectónica** | camino a clase mundial | Que las reglas que el `CLAUDE.md` ya declaró se cumplan solas. Hoy se cumplen por memoria: «qué le tocaba trabajar ese día» está escrito **cuatro** veces cuando el documento dice que hay dos y prohíbe una tercera, y hay **diez** comparaciones de rol contra literal fuera de `permisos.ts`, la regla que nació de juntar 35 copias. Falta que el CI las verifique. |
| **Performance y escala a 3 años** | clase mundial | Nada que objetar y hay que decirlo: los índices que importan existen, el cierre es O(personas), y la auditoría **refutó** dos hallazgos de escala midiendo (el índice de `turnos` sí existe: 2 536 kB, byte por byte). A 10× del negocio actual esto no se despeina. |
| **Seguridad** | **por debajo del mínimo** | Es el eje que hunde el veredicto global. Datos personales de diez personas **publicados en GitHub**; el kiosco de marcaje puede leer DNI, correo y remuneración de toda su sede; once funciones `SECURITY DEFINER` entregan datos de cualquier persona a cualquier sesión; y quien lleva DO puede ascenderse a Admin sola. Cuatro P0 y ninguno es teórico. |
| **Corrección de negocio** | profesional sólido | El núcleo del cálculo está bien y resistió el ataque: sin dinero en coma flotante, el cierre es idempotente, el candado de periodo pagado funciona, la trazabilidad monto→marcaje **existe** (hallazgo refutado con evidencia). Le falta cerrar dos huecos que ya pagan mal: el descanso médico paga sin aprobación, y el motor de tardanzas cuenta feriados y vacaciones como tardanzas. |
| **Diseño, estética y flujo** | profesional sólido | Le falta un sistema de diseño declarado: el código cita «el manual v3.0» que no está en el repositorio, y los estados de error están resueltos pantalla por pantalla en vez de por un componente común. Ver §10. |

**Veredicto global: profesional sólido, con un eje por debajo del mínimo.** El sistema calcula bien y se defiende de sus propios errores mejor que la mayoría de lo que se ve en producción — la red de seguridad, las migraciones documentadas y los cinco defectos ya medidos y descartados son trabajo de primera. Lo que no está a esa altura es **quién puede ver qué**. No es que falte una capa: es que la que hay se declaró y no se volvió a probar.

---

## 2 · Contradicciones — el mismo problema resuelto de dos formas

Va primero y completo aunque sus items sean P2, porque el encargo lo pide y porque es donde se ve la salud del criterio. **23 confirmadas, 11 refutadas.**

| Sev | Contradicción | Dónde |
|---|---|---|
| P1 | El rol se cambia por dos caminos y el de la pantalla no pasa por el escalafón: una lider_do se asciende a admi… | `apps/web/app/(admin)/admin/equipo/page.tsx:422-431 (camino A)` |
| P2 | Cuatro tablas de configuración de plata aceptan escritura directa desde el navegador y nadie usa esa puerta | `supabase — policies configuracion_write_admin_lider, tarifas_admin_lider, rendim…` |
| P2 | El espejo a Google Sheets pagina `jornadas` sin `order`, que es justo lo que `traer-todo.ts` declara no negoci… | `apps/web/app/api/espejo/route.ts:26-45 (la función `pageAll` y sus cuatro llamad…` |
| P2 | La pantalla de Exportar responde «hoy» en UTC — el mismo defecto que Documentación ya corrigió con doce líneas… | `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/exportar/pa…` |
| P2 | «Qué le tocaba trabajar ese día» está escrito cinco veces; CLAUDE.md dice que ya no se escriba una tercera | `apps/web/lib/admin/jornada-esperada.ts (la buena)` |
| P2 | El catálogo de áreas está escrito a mano tres veces y las tres copias ya no dicen lo mismo | `apps/web/lib/areas.ts:19-26 (AREAS_FALLBACK)` |
| P2 | Dos paginadores para el mismo problema, y el que corre todos los meses es el que no cumple la regla que el otr… | `apps/web/app/api/espejo/route.ts:26-37 (copia inline)` |
| P2 | La ficha personal en PDF imprime «Sin salario asignado» y «Sin ficha cargada» cuando lo que pasó es que la con… | `apps/web/app/(admin)/admin/personas/[id]/page.tsx:90-106 (las cuatro consultas),…` |
| P2 | «Encargada» se define de dos formas: la alerta de cobertura no cuenta a la encargada de piso | `apps/web/app/(admin)/admin/incidencias/page.tsx:214 y :480-517` |
| P3 | Las columnas de plata de personas se pueden escribir sin pasar por los fn_set_* que las protegen — incluida la… | `supabase — policy personas_update_admin_lider sobre las 38 columnas de personas;…` |
| P3 | El archivo que el CLAUDE.md designa como fuente única de «qué le tocaba ese día» declara en su encabezado una … | `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/lib/admin/jornada-esperada.ts…` |
| P3 | La pantalla de Política Salarial escribe «America/Lima» a mano tres veces, y es la que imprime el documento qu… | `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/politica-sa…` |
| P3 | Dos pantallas vuelven a declarar quién es DO en vez de preguntárselo a `permisos.ts` | `apps/web/app/(admin)/admin/normas/page.tsx:38 y :147` |
| P3 | Diez comparaciones de rol contra literal fuera de `permisos.ts`, para dos preguntas que el módulo no nombra | `apps/web/app/(admin)/admin/turnos/page.tsx:630` |
| P3 | El rol se compara contra un literal en once sitios fuera de permisos.ts, y el mismo predicado tiene dos nombre… | `apps/web/app/(admin)/admin/horarios/page.tsx:113` |
| P3 | Un `useMemo` de Incidencias documenta una salvaguarda por sede que sus dos ramas no aplican | `apps/web/app/(admin)/admin/incidencias/page.tsx:616-624` |
| P3 | El área base se llama «al cliente» mientras todo el resto del sistema dice «clienta» | `supabase/migrations/0022_areas_catalogo.sql:22 (dato vivo en la tabla `areas`)` |
| P3 | La política salarial publicada con acuse de recibo dice «jefatura», dos veces | `apps/web/lib/politica-salarial.ts:426` |
| P3 | La pantalla de Turnos imprime el identificador de la base junto al nombre de pantalla | `apps/web/app/(admin)/admin/turnos/page.tsx:785` |
| P3 | La imputación de falta grave deja de nombrar las sanciones previas —y dice que «constan en el legajo»— cuando … | `apps/web/app/(admin)/admin/disciplina/memo/[id]/page.tsx:178-186 (la consulta), …` |
| P3 | Exportar asistencia arranca con la fecha de UTC: desde las 7 de la tarde de Lima el CSV para el contador sale … | `apps/web/app/(admin)/admin/exportar/page.tsx:9-11 y :14-15` |
| P3 | El memo disciplinario que se imprime y se entrega en mano dice «el colaborador» | `apps/web/app/(admin)/admin/disciplina/memo/[id]/page.tsx:456` |
| P3 | `puedeVerIdentidad` promete que la cuenta bancaria es solo de DO; las tres capas se la dan a la encargada | `packages/shared/src/permisos.ts:49-55` |

---

## 3 · P0 — ya rompió o rompe hoy

**4 hallazgos.**

### [P0] El motor de tardanzas no excluye nada del calendario: cuenta un feriado, un descanso médico y unas vacaciones como tardanzas, y las imprime en el memo

> **Severidad elevada desde P1.** Escala del encargo: «produjo datos incorrectos en producción». Imprime tardanzas falsas en un memo disciplinario que se entrega a una persona, desde el 2026-07-21. Y contradice la regla que este repo puso primera: los falsos positivos son el peor error.

**DÓNDE** · `/Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0200_el_semaforo_sabe_en_que_escalon_esta_cada_quien.sql:285-305 (fn_tardanzas_resumen, CTE `conteo`) y /Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0235_la_segunda_suspension_cae_en_dias_habiles_y_no_se_pasa_del_tope.sql:228-243 (fn_expediente_generar_tardanza). Tercera superficie con el mismo hueco: /Users/archicaylo/…`

**EJE** · negocio  ·  **ORIGEN** · eje · faltas

**REGLA QUE INCUMPLE** · CLAUDE.md — «Los falsos positivos son el peor error. Acusar de falta a quien no debía cuesta más que dejar pasar una falta real. Por eso las exclusiones (en_planilla, sueldo_fijo, vacaciones, feriados, sin horario) se aplican antes de contar, no después.» Y «Dynamic avisa, nunca sanciona solo… El sistema arma el expediente».

**QUÉ PASA**

fn_faltas decide si un día era día de trabajo suyo con seis exclusiones (vacaciones, ausencia registrada, descanso sustitutorio, suspensión, feriado sin turno, sin horario). El motor de tardanzas hace la pregunta contraria sobre los mismos días y no aplica NINGUNA de ellas: filtra por persona (activa, en planilla, sin sueldo fijo), por el corte del non bis in idem y por tardanzas_justificadas, y nada más. Todo día con jornadas.minutos_tarde > 0 cuenta, aunque el propio sistema tenga registrado que ese día era feriado, descanso médico, maternidad, licencia con goce, vacaciones, descanso sustitutorio o suspensión. Y minutos_tarde SÍ se calcula esos días: fn_recalcular_jornada solo pone la hora esperada en null cuando hay un turno explícito con es_descanso; en un feriado sin turno mide contra el horario ordinario, que no es el horario con que abre la tienda un feriado. Las fechas pasan enteras a los `hechos` del borrador, que es lo que se imprime, se firma y se entrega.

**EVIDENCIA**

```
En 0200 el único where del conteo es: `and (m.corte is null or j.fecha > m.corte) and j.minutos_tarde is not null and j.minutos_tarde > 0 and not exists (select 1 from tardanzas_justificadas tj where tj.persona_id = m.id and tj.fecha = j.fecha)`. En 0235 el where que arma el memo es el mismo: `and j.fecha >= greatest(date_trunc('month', fn_hoy_lima())::date, v_cutoff + 1) and j.fecha <= fn_hoy_lima() and fn_tardanza_es_medible(j.minutos_tarde) and j.minutos_tarde > 0 and not exists (select 1 from tardanzas_justificadas tj …)`. Ni «feriados», ni «vacaciones», ni «justificaciones_asistencia», ni «fn_dia_suspendido» aparecen en ninguna de las dos. Comparar con 0256:101-120, donde fn_faltas las tiene las seis.
```

**SE ROMPE ASÍ**

Medido contra el Postgres local dentro de BEGIN … ROLLBACK (el ROLLBACK se ejecutó y aparece en la salida). Persona en planilla, sueldo_fijo=false, horario 08:00-16:00 domingo a viernes. Tres jornadas con minutos_tarde=60: 2026-08-06 (Batalla de Junín, presente en la tabla feriados), 2026-08-10 (dentro de una ausencia tipo descanso_medico del 10 al 12) y 2026-08-13 (dentro de unas vacaciones del 13 al 14). Resultado 1 — fn_faltas('2026-08-05','2026-08-16') no lista el 06-ago en absoluto y marca el 11, 12 y 14 como justificada=true con motivo descanso_medico / vacaciones: el motor de faltas sabe que esos días no eran suyos. Resultado 2 — fn_tardanzas_resumen('2026-08-17') devuelve tardanzas_mes = 3, umbral = 'amonestacion' (el mínimo del primer escalón es 3). Resultado 3 — fn_expediente_generar_tardanza() crea un borrador nivel 'amonestacion', periodo 2026-08-06 a 2026-08-13, con estos tres hechos: 2026-08-06 · 60 min, 2026-08-10 · 60 min, 2026-08-13 · 60 min. Cero tardanzas legítimas, una amonestación escrita lista para firmar y entregar, con un feriado nacional y un descanso médico citados como hechos imputados.

**YA OCURRIÓ** · No puedo comprobarlo: no toco producción y el Postgres local está vacío (0 personas, 0 jornadas, 0 ausencias). Lo que sí es verificable desde afuera es que el disparador es rutinario, no exótico: CAYLA trabaja feriados —para eso existen feriados_descanso_sustitutorio, la sobretasa del 100 % del art. 9 y toda la maquinaria de la 0173— y en un feriado la tienda no abre a la hora del horario ordinario, que es contra la que se mide. La consulta que lo mide en producción: `select p.nombres, j.fecha, j.minutos_tarde from jornadas j join personas p on p.id=j.persona_id where j.minutos_tarde > 0 and (exists (select 1 from feriados f where f.fecha=j.fecha) or exists (select 1 from justificaciones_asistencia ju where ju.persona_id=j.persona_id and ju.fecha=j.fecha) or exists (select 1 from vacaciones v where v.persona_id=j.persona_id and j.fecha between v.fecha_inicio and v.fecha_fin)) order by j.fecha desc;`

**ARREGLO**

Que las dos consultas hagan la misma pregunta que fn_faltas antes de contar. En el where de 0200:285-305 y en el de 0235:228-243, añadir las mismas negaciones que ya existen textualmente en 0256:101-120: `and not exists (select 1 from feriados f where f.fecha = j.fecha and not exists (select 1 from turnos t where t.persona_id = j.persona_id and t.fecha = j.fecha)) and not exists (select 1 from vacaciones v where v.persona_id = j.persona_id and j.fecha between v.fecha_inicio and v.fecha_fin) and not exists (select 1 from justificaciones_asistencia ju where ju.persona_id = j.persona_id and ju.fecha = j.fecha) and not fn_dia_suspendido(j.persona_id, j.fecha)`. Mejor todavía: extraer eso a una `fn_dia_medible(persona_id, fecha)` y llamarla desde las tres —fn_faltas, fn_tardanzas_resumen y fn_expediente_generar_tardanza— para que la regla se escriba una sola vez, como manda el CLAUDE.md con «qué le tocaba trabajar ese día». La pantalla de Incidencias (page.tsx:201-210) tendría que leer la misma respuesta en vez de filtrar jornadas por su cuenta.

**COSTO** · Una migración que reescribe dos funciones; las dos admiten `create or replace`. Con la función compartida son ~40 líneas de SQL más la prueba pgTAP del caso feriado/ausencia/vacaciones. Hay que pedir el md5 de partida a PRODUCCIÓN para las dos (en local: fn_tardanzas_resumen 16f4991abc454d9ddbc400be5d15defc, fn_expediente_generar_tardanza d16b349dfa9b0c3dccdb882c5eaf09dc). Medio día.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

Comprobado por mi cuenta, no confirmado de oido. (1) VIGENCIA: donde-vive.sh confirma que 0200 es la ultima de 7 versiones de fn_tardanzas_resumen y 0235 la ultima de 6 de fn_expediente_generar_tardanza. No es el error de copiar una version vieja. (2) LAS LINEAS DICEN LO QUE AFIRMA: lei los dos cuerpos en supabase/migrations/0200_el_semaforo_sabe_en_que_escalon_esta_cada_quien.sql y 0235_la_segunda_suspension_cae_en_dias_habiles_y_no_se_pasa_del_tope.sql; el where del conteo y el del generador son literalmente los citados y en ninguno aparece feriados, vacaciones, ausencias, justificaciones_asistencia ni fn_dia_suspendido. fn_faltas (0256, vigente) si trae las seis exclusiones. (3) EL MECANISMO SE SOSTIENE: lei fn_recalcular_jornada vigente (0249) desde pg_proc; minutos_tarde se calcula siempre que haya entrada y hora_entrada_prog, y la hora esperada solo se anula bajo `elsif v_es_descanso`, es decir con un turno explicito. Un feriado sin turno se mide contra el horario ordinario. (4) NO HAY CAPA MAS ABAJO: no hay triggers sobre jornadas ni sobre tardanzas_justificadas; esa tabla solo se llena a mano con fn_levantar_tardanza (0053). No hay auto-justificacion por feriado ni por ausencia. (5) MEDIDO CONTRA EL POSTGRES LOCAL DENTRO DE BEGIN...ROLLBACK, con el ROLLBACK ejecutado y visible en la salida de cada corrida. Use 2026-08-06, que YA ESTA en la tabla feriados como Batalla de Junin (dato del repo, no sembrado por mi). Persona en planilla, sueldo_fijo=false, horario 08:00-16:00, sin turno explicito, tres marcajes de entrada a las 09:00. Resultados: (A) jornadas con minutos_tarde=60 en el feriado, en un dia de descanso_medico y en un dia de vacaciones; (B) fn_faltas('2026-08-05','2026-08-16') no lista el 06-ago en absoluto y devuelve justificada=t con motivo descanso_medico/vacaciones para el 11, 12 y 14 — o sea el sistema SI sabe que esos dias no eran suyos; (C) fn_tardanzas_resumen('2026-08-17') devuelve tardanzas_mes=3, umbral='amonestacion', minimo=3; (D) fn_expediente_generar_tardanza crea un borrador nivel 'amonestacion', periodo 2026-08-06 a 2026-08-13, con los tres hechos exactos: 06-ago 60min, 10-ago 60min, 13-ago 60min. Cero tardanzas legitimas. (6) LL…

</details>

---

### [P0] Once funciones SECURITY DEFINER entregan datos de OTRA persona a cualquiera que tenga sesión

> **Severidad elevada desde P1.** Escala del encargo: «expone datos entre sedes». Cualquier sesión autenticada obtiene datos disciplinarios y de beneficios de cualquier otra persona pasando su id.

**DÓNDE** · `supabase/migrations/0094_el_memo_no_acusa_por_dias_ya_justificados.sql (fn_falta_contadores, la vigente según donde-vive.sh) · supabase/migrations/0246_una_imputacion_prematura_no_tapa_el_escalon_que_falta.sql:149 (grant de fn_tardanza_escalon) · supabase/migrations/0149_la_educacion_con_todas_sus_reglas.sql:243 (grant de fn_educacion_monto) · supabase/migrations/0060_generar_falta.sql:133 (grant …`

**EJE** · seguridad  ·  **ORIGEN** · eje · rls

**REGLA QUE INCUMPLE** · CLAUDE.md: «La seguridad de verdad vive en Postgres (RLS + los guards SECURITY DEFINER)». permisos.ts: «Plata: sueldos, planilla, boletas. Solo DO. Una encargada de sede no ve lo que gana su equipo». Guards SECURITY DEFINER null-safe.

**QUÉ PASA**

Nueve funciones son SECURITY DEFINER (corren como postgres, o sea sin RLS), reciben un p_persona_id que manda quien llama, y no preguntan quién llama: fn_falta_contadores, fn_tardanza_escalon, fn_dia_suspendido, fn_dias_suspension, fn_beneficio_ya_depositado, fn_educacion_monto, fn_es_dia_laborable, fn_reglamento_no_acusado y fn_dcs_por_que_no_compensa. Las nueve tienen `grant execute … to authenticated`, y el esquema public está expuesto en la Data API (supabase/config.toml: schemas = ["public", "graphql_public"]), así que se llaman con un POST a /rest/v1/rpc/<nombre> usando la llave anon pública más la sesión propia. Ninguna la llama el panel por rpc(): en apps/web solo aparecen dentro de comentarios. Son auxiliares que otras funciones SQL usan por dentro.

**EVIDENCIA**

```
Medido en el Postgres local dentro de BEGIN … ROLLBACK, con `set role authenticated` y set_config sobre request.jwt.claim.sub. Sujeto: una integrante de LIM, sin rol, la credencial más baja del sistema. Objetivo: una persona de TRU.

Lectura directa (RLS activa):
  expediente_disciplinario → 0 filas
  desembolsos_beneficios   → 0 filas
  asignaciones_salario     → 0 filas

La misma información por RPC, en la misma transacción:
  fn_tardanza_escalon(ajena)        → nivel_siguiente=suspension · suspension_previa_dias=3 · doc_previo=cccccccc-…-0001
  fn_beneficio_ya_depositado(ajena) → 1234.56
  fn_dia_suspendido(ajena, fecha)   → t
  fn_educacion_monto(ajena, 999999) → 360.00

Ese 360.00 no es un monto de educación: es el `tope_mensual` del rango de esa persona. La tabla tiene seis valores (colibri 90 · cayla 180 · support 270 · aurora 360 · oraculo 420 · archicaylo 480), así que traduce 1 a 1 a su banda salarial.

Y con la encargada de TRU preguntando por una persona de LIM, el contraste más limpio: fn_faltas_resumen —la función con guard que la pantalla sí usa— devolvió 0 filas de LIM, mientras fn_falta_contadores devolvió consecutivas=0, en_30=22, en_180=118 y el array completo con las 118 fechas ({2026-02-18,2026-02-19,…,2026-08-13}). El mismo hecho, preguntado por dos caminos: uno dice «no es tuyo», el otro imprime 118 fechas.
```

**SE ROMPE ASÍ**

Cualquiera de las ~30 personas con cuenta (basta /mio) abre la consola del navegador y hace fetch a /rest/v1/rpc/fn_educacion_monto con {p_persona_id: <id de una compañera>, p_costo: 999999}. Los ids de personas no son secretos: salen en el roster del terminal y en cualquier pantalla del panel. Con eso sabe en qué banda salarial está cada quien. Con fn_tardanza_escalon sabe quién tiene una suspensión encima y cuál es el siguiente escalón que le toca; con fn_falta_contadores, las fechas exactas de sus inasistencias.

**YA OCURRIÓ** · No tengo evidencia de que se haya explotado, y no puedo tenerla: no hay registro de llamadas RPC. Lo que sí está medido es que hoy funciona. El grant más viejo de este grupo es de la 0060 (fn_falta_contadores), así que la vía lleva abierta desde entonces.

**ARREGLO**

`revoke execute on function … from authenticated` en las nueve. Lo medí: revoqué fn_falta_contadores dentro de la transacción y la vía directa pasó a «permission denied for function fn_falta_contadores», mientras fn_expediente_generar_falta —el envoltorio con guard que la usa por dentro— siguió corriendo hasta su error de negocio normal («No corresponde: sin faltas injustificadas nuevas»), o sea que la llamada anidada funcionó igual. Una función SECURITY DEFINER llama a otra como su dueño (postgres), no como authenticated. El arreglo no cambia ninguna pantalla.

Y para que no vuelva: la red que debía cazarlo ya existe pero mira para un solo lado. `funciones_nunca_para_authenticated` tiene tres filas, y el encabezado de supabase/tests/159_el_panel_puede_ejecutar_lo_que_llama.test.sql descartó el barrido por «catorce falsos positivos, contados» — pero el barrido que hace falta no es «todo prosecdef», es el que usé acá: prosecdef + concedida a authenticated + recibe p_persona_id + su cuerpo no menciona ningún guard. Ese predicado devuelve trece nombres, y once son este hallazgo.

**COSTO** · Una migración de revokes, sin cambios de aplicación. Medio día contando la prueba pgTAP que fije el predicado.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

Comprobado con mis propios comandos, no pude refutarlo. (1) Vigencia: donde-vive.sh confirma que los archivos citados SON los vigentes (fn_falta_contadores→0094, fn_tardanza_escalon→0246, fn_educacion_monto→0149) y el md5 local coincide. (2) Las tres líneas de grant citadas dicen literalmente lo que el hallazgo afirma (0246:149, 0149:243, 0060:133). (3) En pg_proc las nueve son prosecdef=t, owner postgres con rolbypassrls=t, has_function_privilege('authenticated')=t y anon=f; ninguna menciona fn_es_admin_o_lider / fn_persona_actual_id / fn_rol_actual / auth.uid (el falso positivo de fn_dias_suspension es solo un raise de validación de p_dias). (4) La capa de abajo NO protege: expediente_disciplinario, desembolsos_beneficios y asignaciones_salario tienen relrowsecurity=t con policies SELECT fn_es_admin_o_lider() / persona_id = fn_persona_actual_id(); SECURITY DEFINER como postgres las salta. (5) Lo MEDÍ en BEGIN … ROLLBACK contra el Postgres local (rollback verificado: 0 personas, 0 expediente, 0 auth.users al terminar), con sujeto rol='integrante' de LIM y objetivo de TRU: lectura directa 0/0/0 filas, y en la misma transacción fn_educacion_monto(objetivo,999999)=360.00, fn_beneficio_ya_depositado=1234.56, fn_dia_suspendido=t, fn_tardanza_escalon=(suspension, 1, 2026-06-28, cccccccc-…-0001, f, 3). (6) El 360.00 traduce 1 a 1 a la banda: topes_educacion_rango tiene 6 filas y count(distinct tope_mensual)=6 (90/180/270/360/420/480), y el cuerpo es least(75% del costo, tope del rango vigente). (7) La vía HTTP es real: PostgREST enruta la RPC — con llave anon devuelve 42501 'permission denied for function' HTTP 401 (ruta existente, solo la separa el grant), y con un JWT role=authenticated firmado con el secreto LOCAL, POST /rest/v1/rpc/fn_educacion_monto y /rpc/fn_falta_contadores devuelven HTTP 200. Ninguna pantalla las llama: los únicos hits en apps/ son comentarios (educacion/page.tsx:144, feriados/page.tsx:104). (8) No está decidido ni ya documentado: docs/revision-2026-07-15/E-seguridad.md:215 cerró «sin hallazgos» el scoping de SECURITY DEFINER pero sobre las ~30 primeras migraciones, y estas nacen en 0060–0246; el hallazgo 7 de docs/hallazgos-abiertos.md es est…

</details>

---

### [P0] DNI, correos y celulares reales de diez personas commiteados en supabase/migrations y ya en GitHub

> **Severidad elevada desde P1.** Escala del encargo: «expone datos… credenciales expuestas». Está PUBLICADO en GitHub y es irreversible sin reescribir el historial. Ley 29733 de Protección de Datos Personales.

**DÓNDE** · `/Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0130_los_datos_del_tregistro.sql:73-82 · /Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0114_tasa_de_pension_exacta.sql:127-151 · /Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0125_la_ficha_personal_completa.sql:9,73`

**EJE** · seguridad  ·  **ORIGEN** · eje · pii

**REGLA QUE INCUMPLE** · CLAUDE.md, «Datos personales fuera de git»: «Correos, DNI, sueldos por persona y fechas de ingreso reales no se commitean. Hay dos scripts explícitamente ignorados en .gitignore por eso (aplicar_0031, aplicar_0033). Antes de subir cualquier script nuevo, revisar que no lleve PII.»

**QUÉ PASA**

La 0130 lleva un array JSON con diez registros de cuatro campos cada uno — DNI, fecha de nacimiento, correo personal (todos de dominios públicos) y celular — transcritos de las constancias del T-Registro. Su encabezado además narra hechos personales con nombre y apellido: quién tiene un hijo inscrito como derechohabiente, quién figura como conviviente frente al «SOLTERO» de la constancia, quién está estudiando hoy. La 0114 ata trece DNI reales a su AFP u ONP, uno por línea. La 0125 nombra a dos personas con su DNI en el comentario de cabecera. Nada de esto está redactado ni tokenizado: son los valores tal cual.

**EVIDENCIA**

```
grep -oE '\{"dni"' sobre la 0130 devuelve 10 registros entre las líneas 73 y 82, con las claves "dni" "nac" "correo" "cel"; el conteo de correos de dominio personal en ese archivo es 10 y el de cadenas de 8 dígitos es 10. En la 0114, `grep -nE "documento = '[0-9]{8}'"` da 13 líneas, de la 127 a la 151. `git cat-file -e origin/main:supabase/migrations/0130_los_datos_del_tregistro.sql` responde sin error: los dos archivos están en origin/main. `gh repo view` confirma que felipea92p-ux/cayla-dynamic es PRIVATE — eso acota el daño, no lo elimina.
```

**SE ROMPE ASÍ**

La regla se implementó como entradas de .gitignore, y todas apuntan a scripts/: scripts/datos-privados/, aplicar_0031, aplicar_0033, aplicar_0128, y los patrones ficha_*.sql y cese_*.sql. Ese mecanismo no puede aplicarse a supabase/migrations/, porque el resto del sistema exige justo lo contrario: scripts/hooks/numeracion.sh frena el push si el número no cuadra, y dame-el-sql.sh se niega a entregar una migración que no esté en git y en GitHub byte por byte. O sea que el único camino soportado para cargar datos a producción es el que obliga a commitearlos. La carga de la 0130 no se saltó ningún freno: usó el que había.

**YA OCURRIÓ** · Sí, ya ocurrió y no es reversible por descuido: los datos están en la historia de git (821 commits), en origin/main en GitHub, en cada clon —el CLAUDE.md documenta que se trabaja en MacBook y Mac mini— y en los siete worktrees que hay hoy bajo .claude/worktrees/ en esta misma Mac. El atenuante real, y hay que decirlo en la primera línea de cualquier informe: el repositorio es PRIVADO, así que esto no está en internet abierto. Lo que sí pasó es que diez personas del equipo tienen su DNI, su correo y su celular en un repositorio de código, en un servicio de terceros, indexado y buscable por cualquiera que tenga acceso al repo hoy o mañana.

**ARREGLO**

Tres pasos, y solo el tercero es caro. (1) Separar el DDL de los datos: la migración deja la estructura y la carga de valores personales se hace con un script tipo scripts/actualizar-correos-prod.mjs, que ya lee de scripts/datos-privados/ y ya está ignorado. El molde existe y funciona; solo no se usó aquí. (2) Añadir a scripts/hooks/pre-push un chequeo de PII sobre supabase/migrations/ —ocho dígitos entre comillas, correos de dominio personal, celulares de nueve dígitos— que frene el push como ya frena por numeración duplicada. Es el hueco que dejó el diseño: el guardián mira números, no contenido. (3) Decidir con Felipe qué hacer con lo ya commiteado. Reescribir la historia es posible pero peligroso en este árbol: varias sesiones comparten directorio e índice y el CLAUDE.md ya prohíbe hasta git commit --amend por eso. La alternativa honesta es dejarlo, dejar constancia de que ocurrió, y cerrar el camino para que no se repita.

**COSTO** · Bajo para (1) y (2): el script de carga y el hook son un rato de trabajo cada uno. Alto y con riesgo para (3), y por eso es una decisión de Felipe, no una tarea.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

CONFIRMADO en lo esencial, con mis propios comandos. 0130 lineas 73-82: exactamente 10 objetos JSON con las claves "dni" "nac" "correo" "cel" (10 de cada una), 10 cadenas de 8 digitos y 10 direcciones @gmail.com. Su encabezado ademas narra hechos personales con nombre propio (lineas 39, 42-43 y 140: quien estudia hoy, el desacuerdo conviviente/SOLTERO, un hijo inscrito como derechohabiente). 0114: grep -cE "documento = '[0-9]{8}'" devuelve 13, en las lineas 127-151. 0125: lineas 9 y 73 nombran a dos personas con su documento de 8 digitos en comentarios. Los tres archivos resuelven en HEAD y en origin/main (git cat-file -e sin error). El repo es PRIVATE y gh api .../collaborators devuelve un solo login, el del dueno. Entraron a git el 2026-07-31, 08-01 y 08-02; hay 814 commits encima.

REFUTACIONES INTENTADAS Y FALLIDAS. (1) No es cosa decidida: CLAUDE.md:109-112 lo prohibe de forma explicita ("Correos, DNI, sueldos por persona y fechas de ingreso reales no se commitean"), asi que es incumplimiento de la regla escrita del propio repo, no una decision. (2) No es ninguno de los cinco defectos aparentes de planilla; no es un calculo. (3) No hay capa debajo que lo proteja: ningun hook mira PII (scripts/hooks/ solo tiene numeracion.sh, migracion-sin-guardar.sh, pre-push y dos ficheros de datos) y GitHub devuelve secret_scanning: null y push_protection: null. El unico mecanismo es .gitignore, y todas sus entradas de PII apuntan a scripts/, nunca a supabase/migrations/. (4) No aplica lo de "la funcion citada no es la vigente": son migraciones de carga de datos, no definiciones de funcion. (5) Las lineas citadas dicen lo que el hallazgo afirma.

LO QUE SI REFUTO: el apartado "SE ROMPERIA ASI" es incorrecto. Afirma que el unico camino soportado obliga a commitear los datos y que "la carga de la 0130 no se salto ningun freno: uso el que habia". Es falso y se demuestra dos migraciones antes: 0128_la_base_declarada_por_rango.sql tiene CERO coincidencias de DNI o correo personal (grep -c = 0) mientras su gemela con datos, scripts/sql-manual/aplicar_0128.sql, esta en .gitignore. El patron migracion-parametrizada + script-de-aplicacion-ignorado ya estaba en uso; docs/estado.md:…

</details>

---

### [P0] El kiosco de marcaje puede leer el DNI, el correo y la remuneración básica legal de todo su equipo

> **Severidad elevada desde P1.** Escala del encargo: «expone datos entre sedes». El token vive en una Mac mini a la vista de todo el equipo, y alcanza DNI, correo y remuneración de todas las personas de la sede.

**DÓNDE** · `Policy personas_select_terminal_roster (supabase/migrations) · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/lib/terminal/roster.ts:20 · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(terminal)/terminal/vincular/page.tsx:22`

**EJE** · seguridad  ·  **ORIGEN** · eje · pii

**REGLA QUE INCUMPLE** · CLAUDE.md: «El terminal marca SIN PIN, y es a propósito… el control real es que la Mac mini está a la vista de todo el equipo». Ese control cubre quién marca; no cubre qué puede leer el token del kiosco. Y el propio código promete la separación contraria para los sueldos.

**QUÉ PASA**

La policy personas_select_terminal_roster deja al usuario del terminal seleccionar filas completas de `personas` para toda su sede (estado='activo', más quien tenga visible_todas_sedes). La RLS es por FILA, no por columna: roster.ts pide cuatro campos (id, nombres, apellidos, pin_hash), pero el token permite pedir cualquiera. Entre ellos van documento (DNI), email, sueldo_base_legal, fecha_cese, motivo_cese, regimen_pension, retencion_4ta y con_hijos. El terminal es una sesión de Supabase persistente en localStorage de una Mac mini de tienda que se vincula una sola vez («Esto solo se hace una vez por dispositivo») y queda a pantalla completa, deliberadamente desatendida y a la vista de todo el mundo — que es justo lo que hace trivial abrir el inspector y pedir el resto de las columnas, o llevarse el token.

**EVIDENCIA**

```
Medido contra el Postgres local dentro de BEGIN … ROLLBACK, autenticado como el usuario de un terminal: «TERMINAL ve personas: 3», y la consulta de columnas devolvió las tres filas con documento, sueldo_base_legal y email de cada una. En el mismo bloque, «TERMINAL ve datos_personales: 0» y «TERMINAL ve asignaciones_salario: 0» — o sea que la contención existe para esas dos tablas y no para `personas`. La transacción terminó en ROLLBACK. Que sueldo_base_legal es un sueldo por persona lo fija la 0106: fn_set_sueldo_base_legal exige admin o líder para escribirlo y su mensaje de error habla de «la remuneración básica legal».
```

**SE ROMPE ASÍ**

El sistema separa con cuidado los datos de plata: asignaciones_salario y movimientos_planilla están cerradas a admin y líder, y el comentario de apps/web/app/api/admin/cuentas/route.ts:146 lo declara como garantía —«no ven sueldos de nadie, ni el suyo en planilla»—. Pero la remuneración básica legal no vive ahí: la 0103 la puso como una columna de `personas`, que es la tabla con la RLS más ancha del esquema porque tiene que alimentar el roster del kiosco. La garantía se escribió mirando dos tablas y el dato se guardó en una tercera.

**YA OCURRIÓ** · No consta ningún acceso indebido; es capacidad latente y hoy no cuesta nada. Lo que la hace P1 es que no requiere ninguna credencial: basta estar delante de un terminal que está encendido a propósito, sin clave a propósito, en horario de tienda.

**ARREGLO**

Que el terminal no lea `personas` directamente. Crear una vista con security_invoker=true que exponga solo id, nombres, apellidos, pin_hash y sede, darle SELECT a authenticated, mover a ella la condición de personas_select_terminal_roster y quitar esa policy de la tabla. roster.ts cambia de nombre de tabla y nada más. Alternativa de fondo, más cara: mudar documento y sueldo_base_legal a datos_personales, que ya tiene la RLS estrecha correcta — pero eso toca las consultas de planilla que leen sueldo_base_legal desde `personas`.

**COSTO** · La vista es una migración corta y una línea en roster.ts. La mudanza de columnas es varias migraciones y auditoría de la planilla.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

Comprobado con mis propios comandos, no repitiendo la evidencia ajena. (1) La policy vigente en la base local —que está en la 0267, al día con el repo— es literalmente la de la 0008: «(estado = 'activo') AND (fn_sede_actual_terminal() IS NOT NULL) AND ((sede_base_id = fn_sede_actual_terminal()) OR (visible_todas_sedes = true))». Ninguna migración posterior la estrecha. (2) No hay capa más abajo: information_schema.column_privileges da a `authenticated` SELECT sobre las 38 columnas de personas, incluidas documento, email y sueldo_base_legal; no hay ni un `revoke` sobre columnas de personas en las 267 migraciones; config.toml expone el esquema public entero sin restricción de PostgREST; y roster.ts consulta la tabla `personas` directa, no una vista. (3) Medí yo mismo dentro de BEGIN … ROLLBACK contra el Postgres LOCAL (que estaba vacío: 0 personas, 0 terminales — la fixture es mía y con datos inventados), con identidad de terminal: auth.uid() resuelto, fn_sede_actual_terminal devolvió la sede TRU, fn_es_admin_o_lider=false, «FILAS VISIBLES=3» (las 3 de TRU; la persona de LIM queda fuera, o sea la RLS sí acota por sede) y «con documento=3 con email=3 con sueldo_base_legal=3», con «suma sueldos legibles=7035.00» = 1234+2345+3456, lo que prueba que lee los valores por persona y no nulos. En el mismo bloque «datos_personales visibles=0» y «asignaciones_salario visibles=0», coherente con sus policies (dp_select_admin_lider y salario_admin_lider exigen fn_es_admin_o_lider(), que para el terminal es false). La transacción terminó en ROLLBACK. (4) Las citas dicen lo que el hallazgo afirma: personas/[id]/page.tsx:374 renderiza «DNI {persona.documento}», así que documento es el DNI; el comentario de api/admin/cuentas/route.ts:146 dice literalmente que las RLS de asignaciones_salario y movimientos_planilla «siguen cerradas... no ven sueldos de nadie», garantía escrita mirando dos tablas mientras la 0103 puso sueldo_base_legal como columna de una tercera; client.ts:28 confirma sesión persistente en localStorage bajo la clave cayla-auth-terminal con la llave anónima, y la copia de vincular dice «Esto solo se hace una vez por dispositivo». Rutas de refutación probadas y descart…

</details>

---

## 4 · P1 — rompe bajo condiciones previsibles

**8 hallazgos.**

### [P1] El candado de mes pagado se mide con el reloj, no con la jornada: la salida pasada la medianoche del día 28 queda fuera

**DÓNDE** · `supabase/migrations/0102_poner_al_dia_lo_que_el_registro_decia.sql (fn_anular_marcaje, fn_corregir_marca), y el mismo patrón en fn_eliminar_marcaje, fn_agregar_marcaje, fn_reactivar_marcaje, fn_confirmar_auto_cierre, fn_corregir_marcaje, fn_reabrir_dia, fn_resellar_dia, fn_levantar_sello_si_el_dia_cuadra, fn_dias_por_revisar y fn_trg_marcajes_delete_recalcular`

**EJE** · arquitectura  ·  **ORIGEN** · eje · trazabilidad

**REGLA QUE INCUMPLE** · CLAUDE.md — «Los marcajes son la fuente de verdad, y son append-only. jornadas es un resumen derivado». Y el candado que la 0138/0191/0203 pusieron para que un mes pagado no se mueva. La 0240 introdujo `marcajes.fecha_jornada` («La jornada manda, no el calendario») pero solo la mitad del sistema se enteró.

**QUÉ PASA**

Todas esas funciones deciden a qué día pertenece una marca con `(timestamp_marca at time zone 'America/Lima')::date`, ignorando `fecha_jornada`. La marca que cierra una jornada que cruzó la medianoche pertenece —para la planilla— al día anterior, pero para el candado pertenece al día del reloj. Si el turno del 28 (último día del periodo) termina a las 00:30 del 29, esa salida cae, según el candado, en el periodo siguiente, que está abierto. Se puede anular, corregir o eliminar con el mes ya pagado. fn_registrar_marcaje (0240) y fn_trg_marcajes_recalcular_jornada sí usan `coalesce(fecha_jornada, …)`: la expresión correcta ya existe en el repo, y estas funciones no la usan.

**EVIDENCIA**

```
Medido contra el Postgres local dentro de BEGIN … ROLLBACK (rollback ejecutado). Montaje: persona de TRU, entrada 2026-07-28 16:00 Lima, salida por fn_registrar_marcaje a las 2026-07-29 00:30 Lima → la marca entra con `fecha_jornada = 2026-07-28`; jornada 2026-07-28 «cerrada», 8.50 h; periodo 2026-06-29→2026-07-28 marcado pagado con fn_periodo_pagado; foto congelada: horas_mes 8.50, pago_base 85.00, total 179.81.

INTENTO 1 · anular la ENTRADA (28-jul) →
  ERROR: «Esa marca cae en un periodo ya PAGADO: anularla alteraría una planilla ya pagada. Reabre el periodo primero.»
INTENTO 2 · anular la SALIDA (reloj 29-jul, fecha_jornada 28-jul) →
  pasó. La fila devuelta trae `anulada_motivo = 'prueba de candado'`, `fecha_jornada = 2026-07-28`.

Estado después: entrada viva, salida_final anulada; jornada 2026-07-28 sigue diciendo 8.50 h. El código de fn_anular_marcaje: `v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;` y a continuación `where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin`.
```

**SE ROMPE ASÍ**

La cifra pagada no se mueve —el candado de fn_recalcular_jornada sí lee la fecha de la jornada y sale en silencio—, y eso es justo lo que lo vuelve peligroso: el pago se queda en 8.50 h y la evidencia que lo sostiene desaparece sin que nada avise. El día que una integrante pregunte «¿por qué me pagaron 8.5 h el 28?», o venga SUNAFIL a pedir el registro de control de asistencia (D.S. 004-2006-TR), el registro muestra una entrada a las 16:00 y ninguna salida. La jornada afirma un número que sus propias marcas ya no dicen.

**YA OCURRIÓ** · No consta que se haya ejercido. Pero el caso que lo habilita sí ocurrió y está documentado: la 0240 existe porque «Quien cierra tienda a las 00:30 no podía marcar su salida», y su cabecera cuenta una noche con «30.5 h registradas donde hubo 9.5». TRU trabaja domingo y cierra tarde; es la sede donde más se produce.

**ARREGLO**

Sustituir en las once funciones `(x.timestamp_marca at time zone 'America/Lima')::date` por `coalesce(x.fecha_jornada, (x.timestamp_marca at time zone 'America/Lima')::date)`. La expresión ya está escrita en fn_trg_marcajes_recalcular_jornada; lo correcto es sacarla a una función `fn_fecha_de_la_jornada(marcajes)` y llamarla desde todas, para que no haya una duodécima copia. Prueba pgTAP: anular la salida cruzada de un periodo pagado debe fallar con el mismo mensaje que la entrada.

**COSTO** · Una migración mediana: once cuerpos de función que hay que reescribir con `donde-vive.sh` delante para copiar de la versión vigente de cada una, más una función auxiliar y una prueba pgTAP. Medio día, sin riesgo de cambiar ningún monto.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

CONFIRMADO con mis propios comandos, y el defecto es MAS ancho de lo que el hallazgo dice.

1) LA FUNCION CITADA ES LA VIGENTE. `./scripts/donde-vive.sh fn_anular_marcaje` → 0102 es la última de 5 versiones, md5 fca64b89294b950ad0e2d2c782a144fc, y ese es exactamente el md5 de `pg_proc` en el Postgres local. Igual para `fn_eliminar_marcaje` → 0188, md5 94eda7b8b1cb750d6a3a50aaab78ab98.

2) LA LINEA DICE LO QUE EL HALLAZGO AFIRMA. Extraído de `pg_proc` (no del archivo): fn_anular_marcaje, fn_corregir_marca, fn_eliminar_marcaje, fn_reactivar_marcaje, fn_confirmar_auto_cierre, fn_agregar_marcaje y fn_corregir_marcaje derivan la fecha con `(… at time zone 'America/Lima')::date` y la comparan contra `estado='pagado' and v_fecha between fecha_ini and fecha_fin`. En cambio `fn_recalcular_jornada` (líneas 66, 81, 258) y `fn_trg_marcajes_recalcular_jornada` (líneas 10 y 13) sí usan `coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date)`. La expresión correcta ya existe en la base; los candados no la usan.

3) MEDICION PROPIA (BEGIN … ROLLBACK, Postgres local). Montaje: persona TRU, entrada 2026-07-28 16:00 Lima + salida_final 2026-07-29 00:30 Lima por `fn_registrar_marcaje` → la salida entra con `fecha_jornada = 2026-07-28`; jornada 2026-07-28 cerrada, 8.50 h. Periodo 2026-06-29→2026-07-28 pagado con `fn_periodo_pagado`.
 · INTENTO 1 anular la ENTRADA → ERROR «Esa marca cae en un periodo ya PAGADO…» (el candado funciona).
 · INTENTO 2 anular la SALIDA → PASÓ. Devuelve `anulada_motivo='prueba de candado'`, `fecha_jornada=2026-07-28`. Jornada 28-jul sigue en 8.50 h.
 · INTENTO 3 `fn_eliminar_marcaje` sobre la salida → PASÓ, y es `delete from marcajes` DURO. Queda solo la entrada; la jornada 28-jul sigue «cerrada, 8.50 h» con `salida_final_ts = 2026-07-29 05:30+00` apuntando a una fila que ya no existe; la auditoría queda con `marcaje_id = NULL`.
 · INTENTO 4 `fn_corregir_marca` cambiando la salida de 00:30 a 03:00 → PASÓ. El registro pasa a decir 16:00→03:00 (11 h) mientras la planilla pagada sigue en 8.50 h. Esto es peor que lo reportado: el registro de control de asistencia (D.S. 004-2006-TR) queda contradiciendo el monto pagado, con la corrección f…

</details>

---

### [P1] fn_dia_incoherente y fn_siguiente_tipo_esperado no conocen fecha_jornada: el día siguiente nace sellado y el retorno del refrigerio se rechaza

**DÓNDE** · `fn_dia_incoherente (0082, vigente) · fn_siguiente_tipo_esperado (0129, vigente) · fn_registrar_marcaje (0240, vigente), el bloque de sellado del final`

**EJE** · arquitectura  ·  **ORIGEN** · eje · terminal

**REGLA QUE INCUMPLE** · CLAUDE.md: «Los falsos positivos son el peor error» y «perder el registro de alguien que sí estuvo es peor que un día pagado que no cuadra» (0068/0207). Y la regla de este repo de que una respuesta de negocio tiene UNA sola versión.

**QUÉ PASA**

La 0240 introdujo `fecha_jornada` y actualizó `fn_recalcular_jornada` y el trigger, pero dejó fuera a las dos funciones que deciden si una marca se acepta y si el día está roto. Las dos acotan por `(timestamp_marca at time zone 'America/Lima')::date`. Consecuencia: para el día siguiente del cruce, la salida de las 00:30 cuenta como primera marca del día — y un día que empieza por una salida es incoherente. `fn_registrar_marcaje` entonces sella `pendiente_revision` todas las marcas de ese día, incluida la salida REAL de anoche que acababa de guardar bien. Y `fn_siguiente_tipo_esperado` ve un `salida_final` vivo ese día y devuelve null, así que el `retorno_almuerzo` de esa tarde cae en la rama que exige elegir una salida y se rechaza en la puerta. El sello no se levanta solo: `fn_levantar_sello_si_el_dia_cuadra` solo la llaman las correcciones manuales (0089).

**EVIDENCIA**

```
Censo medido sobre pg_proc: 22 funciones acotan marcajes por `(timestamp_marca at time zone 'America/Lima')::date`; solo 3 mencionan `fecha_jornada` (fn_registrar_marcaje, fn_recalcular_jornada, fn_trg_marcajes_recalcular_jornada) y las otras 19 no — entre ellas fn_dia_incoherente, fn_siguiente_tipo_esperado, fn_auto_cierre, fn_reabrir_dia, fn_dias_por_revisar, fn_resellar_dia, fn_anular_marcaje y fn_corregir_marca. MEDIDO en BEGIN…ROLLBACK: tras entrada martes 15:00 + salida_final miércoles 00:30, `fn_dia_incoherente(persona,'2026-08-05')` devuelve `t` ANTES de que la persona marque nada. Tras la entrada del miércoles a las 08:00, la tabla queda: `salida_final 2026-08-05 00:30 | fecha_jornada 2026-08-04 | pendiente_revision` y `entrada 2026-08-05 08:00 | - | pendiente_revision`. Y en la segunda corrida, tras entrada 08:00 y salida_almuerzo 13:00: `ERROR: tipo retorno_almuerzo no válido: la jornada ya está cerrada o requiere elegir un tipo de salida`. ROLLBACK.
```

**SE ROMPE ASÍ**

La misma integrante del hallazgo anterior. Su salida real de las 00:30 —que la 0240 acababa de guardar correctamente con sus 9.50 h— queda marcada como sospechosa por una marca que ella hizo doce horas después. Y si el terminal llegara a dejarla marcar su refrigerio, su retorno se rechaza: esa marca va a la cola, la cola la reintenta seis veces contra un servidor que va a decir que no las seis, y se aparta. Su hora de refrigerio nunca se descuenta y el día queda pagado con una hora que no trabajó, o —si nadie cierra el día— con lo que invente el auto-cierre.

**YA OCURRIÓ** · No medido contra producción. La consulta del hallazgo anterior (`marcas_selladas_ese_dia`) responde exactamente esto: si hay marcas con `fecha_jornada is not null`, los días de calendario siguientes tienen marcas selladas que nadie pidió.

**ARREGLO**

Cambiar el predicado de día en fn_dia_incoherente y fn_siguiente_tipo_esperado a `coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date)`, que es literalmente lo que la 0240 ya escribió dos veces en fn_recalcular_jornada. Y revisar el censo de las 19 restantes en la misma pasada: al menos fn_auto_cierre (que calcula la hora de cierre y comprueba si ya hay salida final por fecha de calendario) y fn_dias_por_revisar tienen el mismo defecto. Antes de tocarlas, `./scripts/donde-vive.sh` de cada una y el md5 de partida pedido a producción.

**COSTO** · Mediano. Son dos funciones pequeñas de cambio trivial, pero tocan la puerta por la que pasa todo el marcaje: hay que auditarlas contra el Postgres local con las pgTAP completas y ampliar la 181 con la mañana siguiente.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

REAL. Intenté refutarlo por las cinco vías del prompt y ninguna lo tumba.

VIGENCIA (donde-vive.sh + pg_proc con las 249 aplicadas): fn_dia_incoherente vigente en 0082, fn_siguiente_tipo_esperado en 0129, fn_registrar_marcaje en 0240. Ninguna migración 0241-0249 redefine las dos primeras — la 0249 solo toca fn_recalcular_jornada. El prosrc vivo de las dos acota por `(timestamp_marca at time zone 'America/Lima')::date = p_fecha` y no menciona fecha_jornada. La línea citada dice lo que el hallazgo afirma.

CENSO: 21 funciones acotan marcajes por fecha de calendario, 3 conocen fecha_jornada (fn_registrar_marcaje, fn_recalcular_jornada, fn_trg_marcajes_recalcular_jornada). El hallazgo dijo 22/3 y 19 ciegas; son 21/3 y 18. Discrepancia de una, inmaterial: TODAS las funciones que nombra (fn_dia_incoherente, fn_siguiente_tipo_esperado, fn_auto_cierre, fn_reabrir_dia, fn_dias_por_revisar, fn_resellar_dia, fn_anular_marcaje, fn_corregir_marca) salen ciegas en mi censo.

MEDIDO POR MÍ en BEGIN…ROLLBACK contra el Postgres local (persona/sede/terminal creados dentro de la transacción, ROLLBACK ejecutado en las tres corridas):
· entrada mar 2026-08-04 15:00 + salida_final mié 00:30 → la 0240 funciona: marca con fecha_jornada=2026-08-04, jornada del martes cerrada en 9.50 h. Correcto.
· fn_dia_incoherente(persona,'2026-08-05') = t ANTES de que la persona marque nada el miércoles. fn_dia_incoherente('2026-08-04') = f.
· Tras la entrada del miércoles 08:00, la tabla queda literal: `salida_final 2026-08-05 00:30 | fecha_jornada 2026-08-04 | pendiente_revision` y `entrada 2026-08-05 08:00 | - | pendiente_revision`. Sella la salida REAL de anoche que acababa de guardar bien.
· Tras salida_almuerzo 13:00, fn_siguiente_tipo_esperado('2026-08-05') = null y el retorno revienta con el texto exacto: `ERROR: tipo retorno_almuerzo no válido: la jornada ya está cerrada o requiere elegir un tipo de salida`.

NO HAY CAPA DE ABAJO QUE LO PROTEJA — bajé el nivel y encontré lo contrario, dos cosas PEORES que las que reclama:
1) fn_levantar_sello_si_el_dia_cuadra(persona,'2026-08-05') devuelve 0. Tiene la misma ceguera de calendario, así que el sello NO SE PUEDE LEVANTAR ni por la corrección man…

</details>

---

### [P1] El régimen de pensión se cambia por la única puerta sin candado, y la puerta con candado no la llama ninguna pantalla

**DÓNDE** · `supabase/migrations/0125_la_ficha_personal_completa.sql:153-194 (fn_set_regimen_pension, vigente según donde-vive.sh) · supabase/migrations/0261_el_regimen_de_pension_recuerda_desde_cuando.sql:170-196 (fn_cambiar_regimen_pension, la que sí tiene candado) · apps/web/app/(admin)/admin/datos-personales/page.tsx:295 y :311`

**EJE** · negocio  ·  **ORIGEN** · eje · retroceso

**REGLA QUE INCUMPLE** · CLAUDE.md · «nada puede alterar un periodo de planilla ya pagado» (candado de la 0037, helper de la 0203) y «nunca una regla escrita dos veces». La 0261 dice literal por qué nace fn_cambiar_regimen_pension: «para que nadie vuelva a cambiar el régimen con un update a secas: eso es justo lo que borraba la historia».

**QUÉ PASA**

Hay dos funciones que cambian el mismo hecho —a qué régimen de pensión pertenece una persona—. fn_cambiar_regimen_pension lo versiona por fecha y lleva `if fn_fecha_en_periodo_pagado(p_desde) is true then raise`. fn_set_regimen_pension hace `update personas set regimen_pension = v_nuevo` a secas: sin fecha, sin fila en asignaciones_regimen_pension y sin candado. fn_planilla_calcular lee `coalesce((select h.regimen from asignaciones_regimen_pension ...), p.regimen_pension)`, así que para quien no tiene fila versionada —el relleno de la 0261 solo escribió a quien ya tenía `regimen_pension is not null`— el valor plano de personas gobierna TODOS los periodos, incluidos los pagados. Y la que la pantalla llama es la insegura: `grep -rn cambiar_regimen_pension apps/ --exclude-dir=.next` no devuelve nada. La 0261 construyó la puerta buena y dejó cableada la mala.

**EVIDENCIA**

```
BEGIN … ROLLBACK contra el Postgres local (scratchpad/m2.sql). Periodo 2026-06-29→2026-07-28, persona en planilla, régimen 'onp', congelado con fn_periodo_pagado. Foto de planilla_pagada_detalle: total 978.88 · descuento_pension 112.25.
  · fn_cambiar_regimen_pension(persona,'jubilada','2026-07-01') → «FRENO: El 01/07/2026 cae dentro de un periodo YA PAGADO. Un cambio con esa fecha movería lo que ese mes calcula.»
  · fn_set_regimen_pension(persona,'jubilada') → pasa sin decir nada; personas.regimen_pension = 'jubilada'.
  · fn_proyeccion_periodo(periodo_pagado) → total 1091.13 · descuento_pension 0.00.
Foto congelada: 978.88 / 112.25. Diferencia S/112.25 en un mes ya transferido. ROLLBACK ejecutado.
Y el mensaje de la pantalla (datos-personales/page.tsx:311) promete lo contrario de lo que pasa: «El nuevo régimen se aplica desde el próximo cálculo de planilla».
```

**SE ROMPE ASÍ**

DO abre /admin/datos-personales de alguien cuyo régimen todavía estaba vacío —o corrige un régimen mal cargado— y guarda la ficha. La ficha se guarda, el aviso dice «se aplica desde el próximo cálculo», y desde ese segundo la boleta de todos sus meses ya pagados sale con otra pensión. apps/web/app/(admin)/admin/planilla/boleta/page.tsx:154 imprime con fn_proyeccion_periodo, que recalcula en vivo y no lee la foto de la 0096 —su propio comentario lo dice—, pero el sello de la hoja igual pone «Pagada el DD/MM/AAAA». Es una boleta que se declara pagada con cifras que nunca se pagaron. La red que sí funciona es el desvío de fn_planilla_foto_diferencias, pero compara únicamente `total` y solo salta si alguien abre la pantalla de Planilla y selecciona ese periodo.

**YA OCURRIÓ** · No lo puedo afirmar: el panel apunta al Supabase local y ahí no hay datos. La forma exacta ya apareció en el repo — docs/hallazgos-abiertos.md:161 registra a una integrante que pasó a JUBILADA y anota «en julio aún tenía AFP (la 0190 rige desde el periodo del 28/08)», que es justo el caso que necesita fecha. Para saberlo, un solo select en el SQL Editor de producción: select p.id, p.regimen_pension, (select count(*) from asignaciones_regimen_pension a where a.persona_id = p.id) as tramos from personas p where p.estado = 'activo' order by tramos, 2; — toda fila con tramos = 0 y régimen no nulo está hoy gobernada por el valor plano y sin candado.

**ARREGLO**

Una migración que reescriba fn_set_regimen_pension para que sea un envoltorio de fn_cambiar_regimen_pension: recibe la fecha desde cuándo rige (por defecto, el primer día del periodo abierto, que es lo que la pantalla ya promete), escribe el tramo en asignaciones_regimen_pension y hereda su candado. Y en datos-personales/page.tsx pasar esa fecha. Si se prefiere no tocar la firma hoy, el parche mínimo de una línea es meterle a fn_set_regimen_pension el mismo guard sobre la primera fecha del periodo abierto y hacer que además inserte el tramo. Lo que no sirve es solo revocar el grant: la pantalla dejaría de poder cargar el régimen de quien todavía no lo tiene.

**COSTO** · chico — una migración de ~40 líneas (envoltorio + grant) y un cambio de tres líneas en la pantalla. La prueba pgTAP es la que ya existe de forma para 0261: throws_like sobre una fecha dentro de un periodo pagado.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

CONFIRMADO con mis propios comandos. Intenté refutarlo por las cinco vías y ninguna aguanta.

VIGENCIA (donde-vive.sh, no grep): fn_set_regimen_pension → 1 sola definición, 0125, VIGENTE (md5 base da460442…). fn_cambiar_regimen_pension → 1 sola, 0261, VIGENTE (eddb3200…). Ninguna está obsoleta.

LAS LÍNEAS DICEN LO QUE EL HALLAZGO AFIRMA: 0125 hace `update personas set regimen_pension = v_nuevo where id = p_persona_id;` — sin fecha, sin fila en asignaciones_regimen_pension, sin llamar a fn_fecha_en_periodo_pagado. 0261 sí lleva `if fn_fecha_en_periodo_pagado(p_desde) is true then raise`. En prosrc vivo de fn_planilla_calcular (vigente 0263) está el `coalesce((select h.regimen from asignaciones_regimen_pension …), p.regimen_pension)`.

CABLEADO: datos-personales/page.tsx:295 llama fn_set_regimen_pension. Grep de todo el repo: fn_cambiar_regimen_pension NO tiene ni un llamador — solo aparece en types.ts generado (main + 4 worktrees). Ambas con execute a `authenticated`. La puerta buena es código muerto.

NO HAY CAPA DEBAJO (lo comprobé, es la refutación obligatoria): triggers en personas = solo updated_at y educacion_cerrar_al_cesar; ninguno escribe historial. Sin constraint ni RLS que ayude (la RPC es SECURITY DEFINER). fn_proyeccion_periodo NO se niega sobre un periodo 'pagado': recalcula en vivo y devuelve pagado_at, y boleta/page.tsx:154 recalcula mientras la línea 368 estampa «Pagada el …». fn_planilla_foto_diferencias compara SOLO `total`, como dice el hallazgo.

NO ES DEFECTO APARENTE: docs/planilla-anexo-tecnico.md no menciona «régimen» ni «pensión» ni una vez. Ninguno de los cinco.

MI MEDICIÓN (BEGIN … ROLLBACK local, ROLLBACK ejecutado en cada corrida; la base local tenía 0 personas, así que armé el escenario). Periodo 29-mar→28-abr en estado 'pagado', dos personas en ONP, S/1500:
· fn_cambiar_regimen_pension(…,'integra','2026-04-01') → FRENA: «El 01/04/2026 cae dentro de un periodo YA PAGADO…»
· fn_set_regimen_pension(…,'integra') → PASA sin decir nada, en las dos, y crea CERO filas de historial.
· SIN fila de historial: el periodo YA PAGADO pasó de onp/0.13000/desc 16.70/total 135.66 → integra/0.12920/desc 16.60/total 135.76. El pasado pagado se movió…

</details>

---

### [P1] Un descanso médico paga sin que Desarrollo Organizacional lo apruebe, y la encargada de sede puede registrarlo

**DÓNDE** · `supabase/migrations/0263_los_veinte_dias_de_descanso_medico_entran_a_la_base.sql:1050-1054 (lateral `dmd` de fn_planilla_calcular, la vigente según donde-vive.sh) y :1124-1127 (lateral `mat`) · supabase/migrations/0101_ausencias_un_solo_lugar.sql:345-352 y :397-412`

**EJE** · negocio  ·  **ORIGEN** · eje · retroceso

**REGLA QUE INCUMPLE** · El propio cuerpo de fn_registrar_ausencia lo dice: «Como ningún permiso paga por sí solo (los que pagan exigen aprobación de DO más abajo), que la encargada registre no mueve dinero». Y fn_aprobar_ausencia: «La aprobación es de DO, no de la sede: es lo único que convierte días en plata». tipos_ausencia.requiere_aprobacion existe para eso desde la 0101.

**QUÉ PASA**

Los dos laterales que pagan ausencias filtran `a.anulada_at is null` y nada más: nunca miran `a.aprobada_at`. Los dos tipos que pagan —descanso_medico y maternidad— son exactamente los que el catálogo marca `requiere_aprobacion = true`, así que nacen con aprobada_at NULL. La afirmación del código era cierta cuando se escribió: la 0247 midió el 2026-08-13 que fn_planilla_calcular no leía `ausencias` en absoluto. La 0254 (descanso médico) y la 0262 (maternidad) la hicieron leerla y pagarla, y ninguna de las dos menciona la aprobación ni una vez (grep -in aprob sobre 0254, 0262 y 0263 devuelve vacío). El control quedó como un botón que no gobierna nada. Y quien registra no necesita ser admin: fn_registrar_ausencia entra por fn_verificar_corrector, que autoriza a supervisor_sede sobre cualquier persona de su sede.

**EVIDENCIA**

```
BEGIN … ROLLBACK contra el Postgres local (scratchpad/m4.sql). Con la identidad de una persona rol supervisor_sede:
  fn_registrar_ausencia(persona,'descanso_medico','2026-07-06','2026-07-10','gripe','Dr. Inventado','12345','2026-07-06')
  → ausencia creada, sin_aprobar = t, registrada_por = la encargada.
Cambiando a identidad admin solo para poder calcular:
  fn_planilla_calcular('2026-06-29','2026-07-28', periodo)
  → total 340.91 · monto_descanso_medico 340.91 · dias_descanso_medico_pagados 5
Antes de registrar la ausencia esa persona no tenía ninguna jornada y su fila valía 0. ROLLBACK ejecutado.
Y en la base: select codigo, paga, requiere_aprobacion from tipos_ausencia → descanso_medico|t|t · maternidad|t|t.
```

**SE ROMPE ASÍ**

Una encargada abre la pantalla de ausencias, elige a alguien de su sede, tipo «Descanso médico (con documento)», escribe cualquier nombre de profesional y cualquier número de colegiatura —fn_registrar_ausencia solo exige que los tres campos no vengan vacíos, no valida nada— y guarda. El sistema no pide aprobación para pagar: al cerrar el periodo esos días ya están dentro de pago_base. Nadie de DO tuvo que tocar la ausencia. Y el mismo agujero corre por el otro lado: si DO no aprueba a tiempo, igual se paga, así que el pendiente de aprobación tampoco es una señal de nada.

**YA OCURRIÓ** · No lo puedo afirmar desde local. El select para el SQL Editor de producción: select a.id, a.persona_id, a.tipo, a.fecha_inicio, a.fecha_fin, a.registrada_por, a.aprobada_at from ausencias a join tipos_ausencia t on t.codigo = a.tipo where t.paga and t.requiere_aprobacion and a.anulada_at is null and a.aprobada_at is null and a.fecha_inicio >= date '2026-07-01' order by a.fecha_inicio; — cada fila es un tramo que se pagó (o se va a pagar) sin la aprobación que el sistema dice exigir.

**ARREGLO**

Añadir `and a.aprobada_at is not null` a los dos laterales de fn_planilla_calcular (`dmd` y `mat`) en la próxima migración que ya tenga que reescribirla, y —esto no se puede omitir— que los días que quedan fuera por falta de aprobación viajen al JSON como `dias_descanso_medico_sin_aprobar`, para que la pantalla los grite antes de cerrar el mes. Un filtro mudo convertiría el defecto de «paga sin control» en «deja de pagar en silencio», que por el criterio de la casa es peor. Es exactamente la forma que la 0254 ya usó con `dias_sin_monto` en el subsidio de maternidad.

**COSTO** · chico en SQL (dos líneas más el campo informativo dentro de una migración de fn_planilla_calcular, que hay que auditar con BEGIN … ROLLBACK igual), mediano en pantalla: hay que decidir y construir el aviso de «hay días registrados sin aprobar» en el cierre del periodo.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

CONFIRMADO con medicion propia. donde-vive.sh: 0263 es la vigente de fn_planilla_calcular (md5 f6b4f2649f4132dd2db5711b391b1f54) y 0101 la unica de fn_registrar_ausencia; las lineas citadas son exactas (0263:1054 en `dmd`, 0263:1125 en `mat`). El prosrc vivo tiene tres `anulada_at is null` y CERO ocurrencias de `aprobad*`. Reproducido en BEGIN...ROLLBACK contra el Postgres local (ROLLBACK ejecutado, personas_restantes=0): con identidad supervisor_sede, fn_registrar_ausencia crea un descanso_medico con doc_profesional y colegiatura inventados; queda sin_aprobar=t, registrada_por=la encargada; y fn_planilla_calcular devuelve monto_descanso_medico 191.13 sobre 5 dias, con pago_base 305.81 contra 114.68 del control (114.68+191.13=305.81 exacto). En la base, descanso_medico y maternidad son paga=t y requiere_aprobacion=t. Refutaciones descartadas una por una: (a) NO esta entre los cinco defectos aparentes de docs/planilla-anexo-tecnico.md (factor 6.5, efecto calendario, RMV, prorrateo del feriado, promedio de dias); (b) NO hay capa mas abajo: sin trigger que exija aprobacion (trg_ausencia_solo_planilla solo mira en_planilla), sin constraint (chk_ausencia_aprobacion solo exige coherencia at/por), sin policy de INSERT/UPDATE, y ni fn_planilla_congelar ni fn_planilla_congelar_pendientes mencionan ausenc/aprob; (c) la funcion citada SI es la vigente; (d) las lineas dicen lo que el hallazgo afirma. El contra-precedente mas fuerte —fn_provisiones documenta expresamente «POR QUE NO EXIGE APROBACION» en 0135:260, repetido en 0158/0160/0196— no se traslada: alli exigir aprobacion BAJARIA la gratificacion de la persona, aqui DESEMBOLSA; y el repo escribe esa decision cuando la toma, mientras que grep -in aprob sobre 0254, 0262 y 0263 devuelve vacio. Lo que lo vuelve defecto de autorizacion y no solo check faltante: 0101:304 justifica el permiso de la encargada con «Como ningun permiso paga por si solo (los que pagan exigen aprobacion de DO mas abajo), que la encargada registre no mueve dinero» —premisa hoy falsa— y lo mismo afirman apps/web/app/(admin)/admin/ausencias/page.tsx:417 («lo aprueba Desarrollo Organizacional antes de entrar en planilla»), el confirm de aprobar() («a…

</details>

---

### [P1] El botón «Sí, volví a entrar» borra la salida real de quien cerró tienda pasada la medianoche

**DÓNDE** · `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/lib/terminal/estado-dia.ts:49-91 · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/lib/terminal/jornada-en-curso.ts:32 · /Users/archicaylo/Proyectos/cayla-dynamic/packages/shared/src/attendance-state-machine.ts:46-49 · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(terminal)/terminal/marcar/page.tsx:258-263,309-344 · fn_reabrir_dia (01…`

**EJE** · negocio  ·  **ORIGEN** · eje · terminal

**REGLA QUE INCUMPLE** · CLAUDE.md: «Los marcajes son la fuente de verdad, y son append-only. Nunca se corrige una jornada por debajo». Y el encabezado de la 0240: las horas van al día en que entró, y no se inventa ninguna marca.

**QUÉ PASA**

La 0240 guarda la salida de madrugada con `fecha_jornada = <el día en que entró>`. El terminal NUNCA lee esa columna: `cargarMarcajesHoyPorPersona` pide solo `persona_id, tipo, timestamp_marca` y reparte las marcas con `fechaLima(m.timestamp_marca)`, así que la salida de las 00:30 cae en el cubo de HOY. `marcasDeLaJornadaEnCurso` devuelve ese cubo porque no está vacío, y en cuanto la persona marca su entrada de la mañana `determinarSiguienteAccion` ve un `salida_final` en la lista y responde `cerrado`. El terminal le muestra PantallaCerrado —«Ya cerraste tu día. ¿Volviste a entrar?»— y el único botón hacia adelante llama a `/api/reabrir-dia` → `fn_reabrir_dia`, que busca la salida final por fecha de CALENDARIO (`fn_hoy_lima()`), encuentra la de las 00:30 —que es la salida REAL de anoche— y la anula.

**EVIDENCIA**

```
estado-dia.ts:57-67 `.select("persona_id, tipo, timestamp_marca")` — fecha_jornada no aparece. estado-dia.ts:80 `const destino = fechaLima(m.timestamp_marca) === hoyStr ? porPersonaHoy : porPersonaAyer;`. jornada-en-curso.ts:32 `if (deHoy.length > 0) return deHoy;`. attendance-state-machine.ts:46-49 `const tieneSalidaFinal = ordenados.some((m) => m.tipo === "salida_final"); if (tieneSalidaFinal) return { modo: "cerrado", … }`. fn_reabrir_dia: `where … m.tipo='salida_final' and m.anulada_at is null and (m.timestamp_marca at time zone 'America/Lima')::date = v_hoy`. MEDIDO contra el Postgres local en BEGIN…ROLLBACK (entrada ayer 15:00, salida_final hoy 00:30): A) lo real → 1 jornada 2026-08-16 'cerrada' 9.50 h. B) tras fn_reabrir_dia → 2026-08-16 'abierta' horas NULL y una jornada fantasma 2026-08-17 'abierta'; la salida_final real quedó `anulada=t`. C) fn_auto_cierre() cerró 1 jornada. D) final → 2026-08-16 'auto_cerrada_pendiente' 8.00 h. E) horas registradas: 8.00 donde hubo 9.50. ROLLBACK.
```

**SE ROMPE ASÍ**

Una integrante entra a las 15:00 del domingo y cierra tienda a las 00:30. Marca su salida y el sistema la guarda bien: 9.50 h. El lunes llega a las 08:00, el terminal le ofrece «Entrada» y la acepta. A la hora del refrigerio vuelve a tocar su nombre y el terminal le dice «Ya cerraste tu día. ¿Volviste a entrar?» — con dos botones: «Sí, volví a entrar» y «No, ya me voy». Ninguno es lo que quiere hacer. Si toca «Sí», su salida real del domingo se anula, el domingo pierde sus 9.50 h y el auto-cierre lo vuelve a cerrar con las 8.00 h programadas: exactamente las «8.00 inventadas» que la 0240 se escribió para evitar. Y el día reabierto queda sin entrada —la entrada está en el día anterior del calendario—, así que si esa tarde marca su salida final, ese día se paga en cero.

**YA OCURRIÓ** · No lo sé: el Postgres local está vacío (0 personas, 0 marcajes) y no puedo consultar producción. La condición que lo dispara es el mismo caso C4 que la 0240 documenta como real y medido, así que cada vez que alguien cruza la medianoche esto ya está pasando. Para saberlo, en el SQL Editor: `select m.persona_id, m.fecha_jornada as jornada_del_turno, (m.timestamp_marca at time zone 'America/Lima')::date as dia_calendario, (select count(*) from marcajes x where x.persona_id = m.persona_id and (x.timestamp_marca at time zone 'America/Lima')::date = (m.timestamp_marca at time zone 'America/Lima')::date and x.estado_revision = 'pendiente_revision') as marcas_selladas_ese_dia, (select count(*) from marcajes y where y.persona_id = m.persona_id and y.anulada_motivo like 'Día reabierto desde terminal%') as veces_reabierto from marcajes m where m.fecha_jornada is not null order by 3 desc;`

**ARREGLO**

Dos líneas en el terminal y una en la base. (1) `estado-dia.ts`: agregar `fecha_jornada` al select y repartir por `coalesce(fecha_jornada, fechaLima(timestamp_marca))` en vez de por el timestamp a secas — con eso la salida de las 00:30 vuelve al cubo de ayer, `marcasDeLaJornadaEnCurso` hace su trabajo y la pantalla «cerrado» deja de aparecer. (2) `fn_reabrir_dia`: acotar por `coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date) = v_hoy`, para que nunca pueda alcanzar una salida que pertenece a la jornada de otro día. Las dos son el mismo cambio que la 0240 ya hizo en `fn_recalcular_jornada` y en el trigger; solo faltaron estos dos sitios. Y una prueba: la 181 cubre la noche del cruce pero no la mañana siguiente.

**COSTO** · Chico. Una migración que reescribe fn_reabrir_dia y un cambio de ~6 líneas en estado-dia.ts, más un caso nuevo en la prueba 181. Lo caro es no hacerlo: cada cruce de medianoche deja un día que hay que reconstruir a mano.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

REPRODUCIDO ENTERO por mi cuenta contra el Postgres local, dentro de BEGIN … ROLLBACK (semilla creada dentro de la misma transaccion: auth.users, terminal, persona, horario 15:00-23:00, set_config de request.jwt.claim.sub al auth_user_id del terminal). Medicion literal: A) entrada 2026-08-16 15:00 Lima + salida_final 2026-08-17 00:30 Lima -> jornada 2026-08-16 'cerrada' 9.50 h, con la salida guardada con fecha_jornada=2026-08-16 (la 0240 funciona). Entrada del lunes 08:00 ACEPTADA (ok=t) -> nace 2026-08-17 'abierta'. B) fn_reabrir_dia(...,'Mi turno aun no termina') -> 2026-08-16 pasa a 'abierta' con horas NULL y la salida_final REAL queda anulada=t. C) fn_auto_cierre() -> 1 jornada cerrada. D) final: 2026-08-16 'auto_cerrada_pendiente' 8.00 h donde hubo 9.50. ROLLBACK. En una segunda corrida medi el dia reabierto: si esa tarde marca su salida_final, 2026-08-17 cierra con horas_trabajadas NULL (la 0249 convierte el negativo en null) y las seis marcas quedan pendiente_revision.

CADENA VERIFICADA. ./scripts/donde-vive.sh fn_reabrir_dia -> UNA sola definicion, la 0137, VIGENTE (md5 base 8730c7a1a53a239e9d983449ad4eafa1). Su encabezado dice «nadie la llama todavia», pero eso ya es texto viejo: apps/web/app/api/reabrir-dia/route.ts:47 hace sb.rpc("fn_reabrir_dia", …) con el token de la terminal, y apps/web/app/(terminal)/terminal/marcar/page.tsx:317 le pega a esa ruta desde MotivoReentrada. El camino son DOS toques sin teclear nada: components.tsx:307 «Si, volvi a entrar» -> components.tsx:319 tres motivos preescritos.

EL FILTRO NO MIRA fecha_jornada. 0137_reabrir_el_dia_sin_dejarlo_a_medias.sql:128 -> `and (m.timestamp_marca at time zone 'America/Lima')::date = v_hoy`. Y volque de la base fn_siguiente_tipo_esperado (vigente 0129): tambien agrupa por fecha de calendario, lo que explica por que la entrada de la manana SI se acepta y el escenario llega a existir. Las lineas de codigo citadas dicen lo que el hallazgo afirma: estado-dia.ts:58 `.select("persona_id, tipo, timestamp_marca")` (sin fecha_jornada), estado-dia.ts:80 el reparto por fechaLima(timestamp), jornada-en-curso.ts:32 `if (deHoy.length > 0) return deHoy;`, attendance-state-machine.ts:46-49 el `cerrado` …

</details>

---

### [P1] Cuando el auto-cierre llega primero, la salida de madrugada se sigue rechazando: la 0240 solo cubre 3 horas

**DÓNDE** · `fn_registrar_marcaje (0240, vigente), la rama del cruce de medianoche · fn_auto_cierre (vigente) · cron.job 1 (`*/15 * * * *`) · configuracion.auto_cierre_horas`

**EJE** · negocio  ·  **ORIGEN** · eje · terminal

**REGLA QUE INCUMPLE** · CLAUDE.md: «Los marcajes son la fuente de verdad, y son append-only». Y la promesa nº1 de la 0240: «Que quien cierra tienda pasada la medianoche PUEDA marcar su salida».

**QUÉ PASA**

La rama de la 0240 solo adopta la salida de madrugada si encuentra una jornada del día anterior `en ('abierta','en_pausa')`. Pero fn_auto_cierre corre cada 15 minutos y cierra cualquier jornada abierta pasadas `auto_cierre_horas` (medido: 3) desde la hora de salida programada. Si la persona cierra tienda después de esa ventana, la jornada ya está cerrada, la rama no encuentra nada, `v_fecha` se queda en el día nuevo y la salida se rechaza con el mismo error que la migración dice haber arreglado. La prueba 181 no lo ve porque su horario de laboratorio termina a las 23:00, o sea que le deja margen hasta las 02:00.

**EVIDENCIA**

```
fn_registrar_marcaje (0240): `where … and j.estado in ('abierta','en_pausa') and j.entrada_ts is not null and p_timestamp_cliente <= j.entrada_ts + interval '16 hours'`. fn_auto_cierre: `and ( h.hora_salida is not null and now() >= ((j.fecha + h.hora_salida) at time zone 'America/Lima') + make_interval(hours => v_horas) …)`. `select clave, valor from configuracion where clave like '%auto%'` → `auto_cierre_horas = 3`. `select schedule, command from cron.job` → `*/15 * * * * | select fn_auto_cierre()`. MEDIDO en BEGIN…ROLLBACK con hora_salida 21:00: entrada ayer 13:00 → `fn_auto_cierre()` cerró 1 jornada (auto_cerrada_pendiente, 8.00 h) → la salida real de hoy 00:30 devuelve `ERROR: tipo salida_final no válido en el estado actual (se esperaba entrada)`. Es literalmente el error que la 0240 cita en su encabezado como el problema que resuelve. ROLLBACK.
```

**SE ROMPE ASÍ**

Una tienda con salida programada a las 21:00 hace un inventario y cierra a las 00:30. A las 00:00 el cron ya inventó su salida de las 21:00. Cuando la persona marca la suya, el servidor la rechaza; la marca se va a la cola, se reintenta seis veces, se aparta, y el terminal le muestra el cartel rojo de «no quedó registrada». El día se paga con las 8 h programadas en vez de las 11.5 trabajadas, y el descuadre solo aparece al cerrar el mes.

**YA OCURRIÓ** · No medido contra producción: no puedo leer los horarios reales desde acá. La ventana efectiva de la 0240 es `hora_salida + 3 h`. Consulta para el SQL Editor: `select distinct s.codigo as sede, d.v->>'s' as hora_salida_programada, ((d.v->>'s')::time + interval '3 hours') as desde_aqui_el_auto_cierre_gana from horarios_asignados ha join personas p on p.id = ha.persona_id join sedes s on s.id = p.sede_base_id cross join lateral jsonb_each(coalesce(ha.horario_por_dia,'{}'::jsonb)) d(k,v) where ha.vigente_hasta is null and d.v->>'s' is not null order by 2;`

**ARREGLO**

Dos caminos, y conviene decidirlo con Felipe. El barato: que la rama de la 0240 acepte también una jornada `auto_cerrada_pendiente` del día anterior cuya salida final sea de origen `auto_cierre` y siga sin revisar — ahí ya existe la reconciliación que reemplaza la marca sintética por la real, solo que hoy está cinco líneas más abajo del RAISE que la mata. El de fondo: que fn_auto_cierre no cierre una jornada mientras la sede pueda seguir abierta, subiendo `auto_cierre_horas` o leyéndolo por sede. El primero no cambia ningún número de nadie; el segundo cambia cuándo aparecen las alertas.

**COSTO** · Mediano. Una migración sobre fn_registrar_marcaje —la función más delicada del sistema, 5 versiones y toda escritura de marcaje pasa por ella— con auditoría empírica y prueba nueva.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

CONFIRMADO, y el hallazgo se queda corto. Lo reproduje entero contra el Postgres local en BEGIN…ROLLBACK.

VIGENCIA (la primera ruta de refutación, descartada). `./scripts/donde-vive.sh fn_registrar_marcaje` → vigente 0240, md5 995c976dfa9622fdef4e68171dbb93ab; `fn_auto_cierre` → vigente 0203, md5 bb26b6e431973704a557f1afec6a903a. Los dos md5 del Postgres local coinciden. No cité el archivo: leí el prosrc vivo. La rama 0240 dice literal `and j.estado in ('abierta', 'en_pausa')`; fn_auto_cierre dice literal `now() >= ((j.fecha + h.hora_salida) at time zone 'America/Lima') + make_interval(hours => v_horas)`. `configuracion.auto_cierre_horas` = 3, `cron.job` = 1 fila, `*/15 * * * *`, activa.

MEDICIÓN. Persona con horario 13:00–21:00, entrada 2026-08-16 13:00 Lima. `fn_auto_cierre()` → 1 jornada cerrada, `auto_cerrada_pendiente`, 8.00 h. La salida real de 2026-08-17 00:30 → `ERROR: tipo salida_final no válido en el estado actual (se esperaba entrada)`. Es palabra por palabra el error que la 0240 cita en su encabezado como lo que resuelve. CONTROL, mismo montaje sin correr el cron: la salida SÍ se adopta, una sola jornada, `cerrada`, 11.50 h. O sea que la variable es exactamente el auto-cierre. ROLLBACK en las dos.

DOS CORRECCIONES AL HALLAZGO, LAS DOS AGRAVANTES.

1) El desenlace no es «cartel rojo». Bajé el nivel al terminal, que resulta no ser un freno sino el camino del daño: `apps/web/lib/terminal/jornada-en-curso.ts:35` hace `ayerSigueAbierta = !deAyer.some(m => m.tipo === "salida_final")` — y la salida_final sintética del cron ya está ahí, así que devuelve `[]`, y `determinarSiguienteAccion([])` (packages/shared/src/attendance-state-machine.ts:42) devuelve `{modo:"unico", tipo:"entrada"}`. El terminal le ofrece ENTRADA. Medido: esa entrada de 00:30 se ACEPTA y renace el día fantasma. Con el cron de la noche siguiente: 2026-08-14 → 8.00 h `auto_cerrada_pendiente`, 2026-08-15 → 20.50 h `auto_cerrada_pendiente`. 28.50 h registradas donde se trabajaron 11.50. Es el C4 completo, no una salida perdida.

2) «Solo cubre 3 horas» es más grave dicho con exactitud: la rama 0240 solo puede dispararse en el intervalo (00:00, hora_salida + auto_cierre_horas), y ese interv…

</details>

---

### [P1] El rol se cambia por dos caminos y el de la pantalla no pasa por el escalafón: una lider_do se asciende a admin sola

> **Severidad elevada desde P2.** Escalada de privilegios: quien lleva Desarrollo Organizacional alcanza el techo del sistema —todos los sueldos y el padrón— sin autorización y sin rastro.

**DÓNDE** · `apps/web/app/(admin)/admin/equipo/page.tsx:422-431 (camino A) contra apps/web/app/api/admin/cuentas/route.ts:323-337 (camino B); policy en supabase, tabla personas`

**EJE** · seguridad  ·  **ORIGEN** · contradicción · datos

**REGLA QUE INCUMPLE** · Falta un criterio. CLAUDE.md fija la regla solo para un dato («Toda escritura de marcaje pasa por fn_registrar_marcaje. Nunca un insert directo desde el cliente») y no la extiende a personas. El criterio que sí existe está escrito dentro de escalafon.ts y lo contradice la pantalla.

**QUÉ PASA**

Quien lleva Desarrollo Organizacional puede darse a sí misma el rol de Admin desde el formulario de Equipo, en tres clics, sin que nadie lo autorice y sin dejar rastro. Admin es el techo del sistema: ve sueldos de todo el equipo, el padrón con DNI y cuentas bancarias, y puede reabrir un periodo ya pagado.

**EVIDENCIA**

```
Camino A — equipo/page.tsx:422-431, escritura cruda desde el navegador:
      .from("personas")
      .update({ nombres: …, apellidos: …, sede_base_id: form.sedeId, rol: form.rol, email: … })
      .eq("id", editandoId);
y el desplegable que lo alimenta ofrece el techo (equipo/page.tsx:18-23):
  const ROLES_OPCIONES = [ …, { valor: "admin", label: "Admin" } ] as const;

Camino B — cuentas/route.ts:326-337, la misma operación por servidor:
      if (!puedeActuarSobre(yo.rol, p.rol)) return NextResponse.json({ error: "no puedes cambiar el rol de esa persona" }, { status: 403 });
      if (p.rol !== "integrante") return NextResponse.json({ error: "solo se promueve a un integrante" }, { status: 409 });
      const { error } = await admin.from("personas").update({ rol: "supervisor_sede" }).eq("id", personaId);

La base no arbitra: solo hay una policy de fila, sin distinción de columna.
$ docker exec supabase_db_cayla-dynamic psql -U postgres -d postgres -At -c "select policyname||' | '||cmd||' | qual='||coalesce(qual,'-')||' | check='||coalesce(with_check,'-') from pg_policies where tablename='personas' and cmd='UPDATE'"
personas_update_admin_lider | UPDATE | qual=fn_es_admin_o_lider() | check=fn_es_admin_o_lider()

$ … -c "select prosrc from pg_proc where proname='fn_es_admin_o_lider'"
  select coalesce(fn_rol_actual() in ('admin', 'lider_do'), false);

$ … -c "select grantee||' | '||column_name from information_schema.column_privileges where table_name='personas' and privilege_type='UPDATE' and grantee='authenticated' and column_name='rol'"
authenticated | rol

Y el propio escalafon.ts:15-18 dice para qué se escribió:
  «la ruta comprobaba solo que quien llamara fuera admin o lider_do, y NADA sobre el objetivo. Con eso un líder DO podía resetear la clave del admin y recibirla en la respuesta.»
  export function puedeActuarSobre(rolQuienLlama, rolObjetivo) { … if (yo === RANGO.admin) return true; return yo > otro; }
con RANGO = { admin: 3, lider_do: 2, … }: lider_do → admin devuelve false. La pantalla no la llama.
```

**SE ROMPE ASÍ**

Una lider_do entra a /admin/equipo, aprieta editar sobre su propia ficha, abre el desplegable «Rol», elige «Admin» y guarda. PostgREST manda PATCH /rest/v1/personas?id=eq.<suyo> con {"rol":"admin"}; la RLS pregunta fn_es_admin_o_lider(), que para ella devuelve true, y escribe. Al recargar es admin: /admin/planilla, /admin/costos y la exportación del padrón (puedeExportarPadron, solo admin) se le abren. La misma persona, pidiendo lo mismo por /api/admin/cuentas con accion "promover", recibe 403. No hace falta ninguna petición fabricada: el botón está en la pantalla.

**YA OCURRIÓ** · Indeterminado, y esa es la mitad del problema: no hay rastro. personas no tiene tabla de auditoría ni trigger que registre cambios de rol — los únicos triggers son de mantenimiento:
$ … -c "select tgname||' -> '||p.proname from pg_trigger t join pg_proc p on p.oid=t.tgfoid where tgrelid='public.personas'::regclass and not tgisinternal"
trg_personas_updated_at -> fn_set_updated_at
trg_educacion_cerrar_al_cesar -> fn_educacion_cerrar_al_cesar
Lo máximo que se puede preguntar hoy a producción, y solo delata un cambio reciente:
  select nombres, apellidos, rol, created_at, updated_at from personas where rol in ('admin','lider_do') order by updated_at desc;
Si alguna fila con rol admin/lider_do tiene updated_at muy posterior a created_at y no coincide con un alta, hay que preguntarle a Felipe si ese cambio lo hizo él.

**ARREGLO**

DECIDÍ el camino B: el rol se cambia por una RPC SECURITY DEFINER (fn_set_rol) que reimplemente el escalafón dentro de la base, y la pantalla deja de escribir la columna. Es el correcto porque el escalafón ya está escrito, probado y con su historia documentada, y porque una regla en la base la cumplen los dos caminos — mientras que una regla en la ruta HTTP solo la cumple quien pasa por la ruta. Además cierra la columna al navegador: revoke update (rol) on personas from authenticated. DESCARTÉ mover la comprobación al cliente (un if en equipo/page.tsx que oculte «Admin»): la RLS seguiría aceptando el PATCH, así que arreglaría el botón y no el agujero. DESCARTÉ enrutar la pantalla por /api/admin/cuentas: esa ruta corre con llave de servicio y solo sabe promover integrante→encargada; ampliarla a los cuatro roles mete más superficie con llave de servicio en vez de menos. SE ROMPE SI la RPC no replica el «solo se promueve a un integrante» de la ruta: hoy esa es la única puerta que impide degradar a un admin, y el comentario de cuentas/route.ts:331-334 dice que ya se coló una vez.

**COSTO** · Media jornada. Una migración (fn_set_rol con el escalafón en SQL + revoke update(rol)), cambiar una llamada en equipo/page.tsx, y una pgTAP que verifique que lider_do→admin lanza excepción. Auditar antes en producción qué roles hay hoy, porque el revoke no revierte un ascenso ya hecho.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

MECANISMO CONFIRMADO con mis propios comandos; la BASE NO ARBITRA.

· equipo/page.tsx:423-432 escribe `rol: form.rol` en un update crudo de PostgREST (leído; el `.eq` cae en 432, no en 431 — irrelevante). ROLES_OPCIONES:22 ofrece «Admin». El `select` de Rol (817-824) y el botón «Editar» (1500) NO tienen ninguna condición de rol; `(admin)/layout.tsx` no guarda nada y nav.tsx:50 muestra /admin/equipo a `SEDE = ROLES_CON_PANEL`, que incluye lider_do.
· `createAdminSupabaseClient` (packages/database/src/client.ts:33) usa la llave ANÓNIMA + sesión → rol `authenticated`, o sea RLS sí aplica.
· Única policy de UPDATE en personas: `personas_update_admin_lider`, PERMISSIVE, qual y check ambos `fn_es_admin_o_lider()` = `rol in ('admin','lider_do')`. `authenticated` tiene UPDATE a nivel de COLUMNA sobre `rol` (information_schema.column_privileges).
· Triggers en personas: solo `trg_personas_updated_at` y `trg_educacion_cerrar_al_cesar`. Ningún CHECK toca `rol`. `grep old.rol|new.rol supabase/migrations/*.sql` → 0 aciertos. No hay rastro: solo se bumpea `updated_at`.
· `puedeActuarSobre` (escalafon.ts:39-45) da false para lider_do(2)→admin(3), y `grep -rln puedeActuarSobre` sobre el fuente devuelve SOLO index.ts, escalafon.ts y api/admin/cuentas/route.ts. La pantalla no la llama.
· Local está en 0267 = última migración del repo, así que ninguna migración posterior lo cierra. No figura como decidido en CLAUDE.md, docs/hallazgos-abiertos.md ni docs/revision-2026-07-15/.

LO QUE REFUTO DEL HALLAZGO (dos de tres consecuencias son falsas):
1. «ve sueldos… el padrón con DNI y cuentas bancarias» — una lider_do YA los ve: en permisos.ts `puedeVerPlanilla` y `puedeVerIdentidad` resuelven a `DO = ["admin","lider_do"]`. Lo único que separa admin de lider_do en el frontend es `puedeExportarPadron` (`SOLO_DIRECCION = ["admin"]`), o sea el CSV, no el dato en pantalla.
2. «puede reabrir un periodo ya pagado» — FALSO. `periodos_planilla` no tiene NINGUNA policy de UPDATE (solo dos de SELECT) y no existe `fn_reabrir_periodo`. Nadie reabre un periodo desde el panel, sea admin o no.
3. En Postgres admin y lider_do son indistinguibles: la única función que los separa, `fn_exigir_admin` (0009),…

</details>

---

### [P1] Una incidencia de quien marca fuera de su sede base sale sin nombre, cuenta como tardanza aunque esté perdonada, y no se puede sacar de la lista

**DÓNDE** · `Las políticas RLS de jornadas / personas / tardanzas_justificadas / incidencias_aceptadas; apps/web/app/(admin)/admin/incidencias/page.tsx:317,334,338,563; supabase/migrations/0008_visible_todas_sedes.sql:1-4`

**EJE** · seguridad  ·  **ORIGEN** · mecánica

**REGLA QUE INCUMPLE** · «Los falsos positivos son el peor error. Acusar de falta a quien no debía cuesta más que dejar pasar una falta real.» Y de permisos.ts: «el alcance por sede es otra regla, y va aparte en cada pantalla (sede_base_id === yo.sede)» — pero jornadas no usa esa regla.

**QUÉ PASA**

Cuando alguien con base en una sede marca en otra —el caso que la migración 0008 creó a propósito— su día aparece en la pantalla de Incidencias de la encargada de la sede visitada como una fila SIN NOMBRE («» y sede «?»). Si ese día llegó tarde y la tardanza ya fue levantada, la encargada no puede ver el levantamiento, así que la fila cuenta igual hacia «Patrón de tardanzas (3 en 30 días)». Y cuando aprieta Aceptar para sacarla, la base la rechaza. La fila fantasma se queda ahí para siempre, con una acusación de reiteración sobre una persona a la que la pantalla ni siquiera puede nombrar.

**EVIDENCIA**

```
$ docker exec supabase_db_cayla-dynamic psql -U postgres -d postgres -At -c "select policyname||' :: '||coalesce(qual,'-') from pg_policies where tablename in ('jornadas','personas','tardanzas_justificadas')"
  jornadas_select_supervisor :: ((fn_rol_actual() = 'supervisor_sede') AND (sede_id = fn_sede_actual_persona()))
  personas_select_supervisor :: ((fn_rol_actual() = 'supervisor_sede') AND (sede_base_id = fn_sede_actual_persona()))
  tardj_select_supervisor    :: ((fn_rol_actual() = 'supervisor_sede') AND (persona_id IN (SELECT personas.id FROM personas WHERE (personas.sede_base_id = fn_sede_actual_persona()))))

jornadas filtra por sede_id (DONDE MARCÓ); las otras dos por sede_base_id (SU SEDE). Y sede_id sale del marcaje, no de la ficha:
  $ psql -At -c "select prosrc from pg_proc where proname='fn_recalcular_jornada'" | grep sede_id
  85:    v_sede_id := coalesce(v_sede_id, v_marcaje.sede_id);

El escenario está documentado como diseño en supabase/migrations/0008_visible_todas_sedes.sql:1
  «Personas que viajan entre sedes (ej. el founder, con base TRU pero que marca
   también en LIM y AQP). … El marcaje sigue registrando la sede del terminal
   donde efectivamente marcan (marcajes.sede_id viene del terminal).»

La fila queda sin nombre porque el embed de PostgREST devuelve null (incidencias/page.tsx:317):
  nombre: `${j.personas?.nombres ?? ""} ${j.personas?.apellidos ?? ""}`.trim(),
  sede: j.personas?.sedes?.codigo ?? "?",

Y Aceptar no puede cerrarla:
  $ psql -At -c "select prosrc from pg_proc where proname='fn_verificar_corrector'"
    if v_obj_sede is distinct from v_corr_sede then
      raise exception 'Solo puedes corregir marcajes de tu propia sede.';

La encargada sí llega a esa pantalla: nav.tsx:40 usa roles: SEDE, y permisos.ts:118 ROLES_CON_PANEL = DO_Y_ENCARGADA = [admin, lider_do, supervisor_sede].
```

**SE ROMPE ASÍ**

Felipe (base TRU, visible_todas_sedes) pasa un martes por el Taller LIM y marca ahí a las 08:12, doce minutos tarde. Un admin le levanta esa tardanza. La encargada de LIM abre Incidencias el viernes: ve una fila «  ·  sede ?  ·  08:12  ·  Tardanza», la del martes, la del jueves anterior y la de otro día — «Patrón de tardanzas (3 en 30 días)» sobre una persona sin nombre. Aprieta Aceptar y la pantalla le contesta «No se pudo aceptar: Solo puedes corregir marcajes de tu propia sede.». La fila sigue ahí el lunes, y el lunes siguiente.

**YA OCURRIÓ** · Indeterminado — la base local de esta Mac tiene 0 jornadas (solo catálogos), así que no se puede medir aquí. Si ocurrió, ocurre desde que alguien tiene visible_todas_sedes = true, columna creada en la migración 0008. Para saberlo en producción, un solo select en el SQL Editor:

select p.nombres||' '||p.apellidos as persona, sb.codigo as sede_base, sm.codigo as sede_donde_marco, count(*) as dias, min(j.fecha) as desde, max(j.fecha) as hasta, count(*) filter (where coalesce(j.minutos_tarde,0) > 0) as dias_con_tardanza from jornadas j join personas p on p.id = j.persona_id join sedes sb on sb.id = p.sede_base_id join sedes sm on sm.id = j.sede_id where j.sede_id is distinct from p.sede_base_id group by 1,2,3 order by dias desc;

Si devuelve cero filas, hoy no cuesta nada y queda como riesgo latente: se enciende el día que alguien vuelva a viajar entre sedes.

**ARREGLO**

DECIDÍ: alinear el alcance de jornadas con el de personas — que jornadas_select_supervisor mire la sede base de la persona además de la sede del marcaje, o que las otras tres políticas acepten también «esta persona marcó en mi sede». Las cuatro tablas tienen que responder a la MISMA pregunta; hoy dos responden «dónde marcó» y dos «de quién es». Cuál de las dos definiciones gana es decisión de Felipe, no mía: la de «dónde marcó» le da a la encargada de LIM datos de gente de TRU, y la de «sede base» le esconde un día que sí ocurrió en su piso.
DESCARTÉ filtrar en la pantalla (descartar en JS las filas sin nombre): tapa el síntoma, deja el hueco en la base y hace que un día real desaparezca sin que nadie sepa por qué.
DESCARTÉ tocar fn_verificar_corrector sola: dejar aceptar sin dejar ver sería peor.
SE ROMPE SI: se abre jornadas por sede base sin pensar en el terminal — la política jornadas_select_terminal (sede_id = fn_sede_actual_terminal()) depende de sede_id y no se puede cambiar de significado.

**COSTO** · El diagnóstico ya está hecho. La corrección es una migración que reescribe entre una y cuatro políticas RLS, más una prueba pgTAP con una persona de base TRU marcando en LIM. Media jornada, la mayor parte en decidir cuál de las dos definiciones de alcance gana — eso se pregunta antes de escribir nada.

<details><summary>Qué dijo el verificador al intentar refutarlo</summary>

(evidencia mecánica: comando y salida literal)

</details>

---

## 5 · P2 — deuda estructural

**29 hallazgos.**

### [P2] Cuatro tablas de configuración de plata aceptan escritura directa desde el navegador y nadie usa esa puerta

**DÓNDE** · `supabase — policies configuracion_write_admin_lider, tarifas_admin_lider, rendimiento_mensual_write, horarios_write_admin_lider`

**EJE** · arquitectura  ·  **ORIGEN** · contradicción · datos

**REGLA QUE INCUMPLE** · Falta un criterio. El repo tiene una convención de hecho —40 de 47 tablas escribibles tienen pol_write=0 y solo se tocan por RPC— pero no está escrita en CLAUDE.md, así que las excepciones no se leen como excepciones.

**QUÉ PASA**

HOY NO CUESTA NADA Y QUITARLO TAMPOCO: ninguna pantalla, ninguna ruta y ninguna función SQL necesita estas cuatro policies. Son puertas abiertas sin nadie del otro lado. Pero `configuracion` guarda planilla_provisiones, tasa_afp, asignacion_familiar, bono_puntualidad y movilidad_diaria — los parámetros que multiplican el pago de las ~30 personas — y la policy es de tipo ALL, o sea que incluye DELETE.

**SE ROMPE ASÍ**

Una sesión futura necesita ajustar el bono de puntualidad, ve que la pantalla no lo permite, prueba un .from("configuracion").update({valor: …}) desde el navegador, funciona a la primera y se queda. A partir de ahí un parámetro que multiplica el pago de todo el equipo se cambia sin versionado, sin acuse de recibo y sin quedar en ninguna migración — al revés de lo que se hizo con la política salarial, que la 0141 puso versionada y con acuse justamente porque un número que decide cuánto cobra la g…

**YA OCURRIÓ** · No. Verificado por los dos lados: el grep de arriba muestra que ningún .insert/.update/.upsert/.delete del árbol toca estas cuatro tablas, y la consulta de pg_proc muestra que ninguna función SQL las escribe. Para confirmarlo en producción y de paso ver si algún valor se movió fuera de una migración…

**ARREGLO**

DECIDÍ quitar las cuatro policies (drop policy, sin sustituto). Es el correcto porque los escritores legítimos son SECURITY DEFINER con owner postgres y bypassrls=true — no consultan la RLS, así que dejarlas sin policy no rompe nada y devuelve estas tablas al mismo patrón que las otras cuarenta. DESCARTÉ escribir una RPC fn_set_configuracion antes de quitar la policy: hoy nadie edita esos valores desde una pantalla, y agregar la RPC sin pantalla es código que nadie llama. Se hará el día que exista la pantalla, que es cuando se sabrá qué validar. DESCARTÉ dejarlas y documentarlas: son la clase …

**COSTO** · Una hora. Una migración con cuatro drop policy y encabezado que explique por qué sobran (los escritores son DEFINER). Antes: correr la consulta de updated_at en producción y que Felipe confirme que ningún script externo escribe esas tablas.

---

### [P2] El espejo a Google Sheets pagina `jornadas` sin `order`, que es justo lo que `traer-todo.ts` declara no negociable

**DÓNDE** · `apps/web/app/api/espejo/route.ts:26-45 (la función `pageAll` y sus cuatro llamadas), contra apps/web/lib/admin/traer-todo.ts:1-60`

**EJE** · arquitectura  ·  **ORIGEN** · contradicción · errores

**REGLA QUE INCUMPLE** · apps/web/lib/admin/traer-todo.ts, comentario de cabecera: «EL ORDEN NO ES DECORATIVO. Paginar con `.range()` sobre una consulta sin `order` estable es peor que no paginar… Toda consulta que pase por acá debe ordenar por algo único (en `jornadas`, `fecha` + `persona_id`)». El espejo resuelve el mismo problema —el corte de PostgREST en 1000 filas— con una segunda implementación que no cumple esa condición.

**QUÉ PASA**

Hay dos paginadores para el mismo problema. El del panel (`traerTodo`) devuelve `{data, error}` y exige orden único; el del espejo (`pageAll`) lanza excepción y no exige nada. De las cuatro consultas que pagina el espejo, `jornadas` no lleva `order` ninguno y `personas` tampoco. Mientras esas tablas quepan en un lote no pasa nada; el día que crucen las 1000 filas, Postgres puede devolver un orden distinto entre dos llamadas y la hoja del mes puede repetir una jornada y perder otra — y una jornada perdida sale en la hoja como día en blanco, es decir, como si esa persona no hubiera trabajado.

**SE ROMPE ASÍ**

HOY ESTO NO CUESTA NADA: con ~30 personas, `jornadas` de un mes ronda las 900 filas y `pageAll` la trae en un solo lote, donde el orden es irrelevante. El riesgo es latente y se dispara solo al cruzar las 1000: basta con que entren cuatro o cinco personas más, o con que el mes tenga 31 días y haya jornadas de inactivas en el rango. A partir de ahí, cada vez que el Apps Script refresca la hoja, la segunda página puede traer filas que ya venían en la primera y saltarse otras. En la matriz persona …

**YA OCURRIÓ** · no, todavía no: hace falta cruzar las 1000 filas en una sola consulta para que la paginación se active. No se puede medir en local (la base local está vacía: `select count(*) from jornadas` devuelve 0). SELECT para el SQL Editor de producción, que dice a qué distancia está el disparo:

select to_cha…

**ARREGLO**

DECIDI: la correcta es `traerTodo`. Es la que tiene el porqué escrito, la que tiene pruebas (tests/traer-todo.test.ts), la que exige el orden estable y la que además pone tope de lotes (`MAX_LOTES = 200`, que `pageAll` no tiene). El arreglo mínimo y seguro es agregarle a las cuatro consultas del espejo el `order` único que les falta —`jornadas` por `fecha` y `persona_id`, `personas` y `sedes` por `id`, `marcajes` por `timestamp_marca` y `persona_id`—; el arreglo de fondo es borrar `pageAll` y llamar a `traerTodo`, adaptando el `throw` al `{data, error}` que ya envuelve el `try/catch` de la rut…

**COSTO** · Muy bajo si se hace el mínimo: cuatro `.order(...)` en un archivo, sin migración, quince minutos. Unificar en `traerTodo` es media hora más porque hay que convertir el protocolo de error de excepción a `{data, error}` y comprobar que el 500 del espejo sigue saliendo.

---

### [P2] La pantalla de Exportar responde «hoy» en UTC — el mismo defecto que Documentación ya corrigió con doce líneas de comentario explicando por qué

**DÓNDE** · `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/exportar/page.tsx:9-15`

**EJE** · arquitectura  ·  **ORIGEN** · contradicción · tiempo

**REGLA QUE INCUMPLE** · CLAUDE.md · «Nunca escribir "America/Lima" fuera de fecha-lima.ts. El corte del día decide a qué fecha se le paga un marcaje; no puede tener dos versiones.» La regla se ganó juntando 32 copias del huso repartidas por el código.

**QUÉ PASA**

El rango de fechas del exportador viene precargado con «hoy», pero ese «hoy» se calcula en UTC y no en Lima. Desde las 7 de la noche hora de Perú, UTC ya cree que es el día siguiente, así que la pantalla abre con mañana en las dos casillas y el archivo sale vacío. Quien exporta de noche —que es cuando se cierra el día— descarga un CSV sin filas y no tiene forma de saber si es que nadie marcó o es que preguntó por el día equivocado.

**SE ROMPE ASÍ**

Son las 8 de la noche del 28, día de cierre de planilla. Alguien de Desarrollo Organizacional abre Exportar para bajar la asistencia del día antes de cerrar. La pantalla muestra 29/08–29/08 (mañana en Lima, hoy en UTC) y el CSV baja con cero filas de jornada. O peor: cambia a mano solo la casilla «desde» al inicio del periodo y deja «hasta» como vino, con lo que el rango se estira un día más allá del periodo — y el periodo va del 29 al 28, así que ese día de más es el primer día del periodo SIGU…

**YA OCURRIÓ** · SÍ en el sentido de que el defecto está vivo en el árbol y se dispara solo con la hora del reloj, sin necesidad de ningún dato raro: entre las 19:00 y las 23:59 de Lima la pantalla abre con el día equivocado, todos los días. Lo que no puedo determinar es si alguien exportó en esa franja y con qué co…

**ARREGLO**

DECIDÍ borrar fechaHoyISO() y usar hoyLima() de @cayla-dynamic/shared, que es literalmente lo que hizo Documentación cuando encontró la misma línea. Es un cambio de dos líneas —un import y el reemplazo de la función— y deja el archivo con cero respuestas propias a «qué día es hoy». Aprovecho el mismo commit para las dos de datos-personales:404 y :531, que son la misma línea y no cuestan nada. DESCARTÉ escribir un formateador con timeZone: "America/Lima" ahí mismo: funcionaría, y es exactamente la forma en que se llegó a las 32 copias que la regla vino a matar. SE ROMPE SI: nada que yo pueda ve…

**COSTO** · Minutos. Un import y tres reemplazos, sin migración y sin tocar la base. Lo cubre el typecheck del hook de pre-push.

---

### [P2] «Qué le tocaba trabajar ese día» está escrito cinco veces; CLAUDE.md dice que ya no se escriba una tercera

**DÓNDE** · `apps/web/lib/admin/jornada-esperada.ts (la buena) · apps/web/app/(admin)/admin/correcciones/page.tsx:49 (la copia que CLAUDE.md admite) · apps/web/app/(admin)/admin/incidencias/page.tsx:491-501 · apps/web/app/(admin)/admin/turnos/page.tsx:588-607`

**EJE** · arquitectura  ·  **ORIGEN** · contradicción · permisos

**REGLA QUE INCUMPLE** · Regla 12 de CLAUDE.md, literal: «"qué le tocaba trabajar ese día" se pregunta a `apps/web/lib/admin/jornada-esperada.ts`, no se vuelve a escribir. […] Queda una copia más vieja y parcial —solo la hora de entrada— en `admin/correcciones/page.tsx` (`calcularEsperado`): unificarlas está pendiente, y mientras tanto no se escribe una tercera. Esa regla decide si a alguien se le cuenta una falta.»

**QUÉ PASA**

CLAUDE.md dice que hay dos implementaciones y prohíbe una tercera. Hay cuatro. Además de la copia declarada en `correcciones`, `incidencias` y `turnos` reescriben la cascada completa turno del día → `horario_por_dia` → `dias_laborables`. Solo `/mio` y `/admin/horas` importan la del módulo. La cascada de Incidencias es la que decide si una sede aparece con déficit de encargadas, y la de Turnos la que pinta la cobertura.

**SE ROMPE ASÍ**

Cinco lugares deciden si a alguien le tocaba trabajar, y esa decisión es la que convierte un día sin marca en una falta. Hoy las cuatro de TypeScript coinciden entre sí y con `fn_faltas` —las leí en paralelo—. El día que cambie la cascada (el caso realista: un horario con semana alterna, o que un turno de descanso deje de anular el horario base) hay que acordarse de cinco archivos, y el que se olvide no fallará: dará otro número. Incidencias dirá que la sede está descubierta y Turnos que está cu…

**YA OCURRIÓ** · Sí, en el sentido de que la regla ya se incumplió: CLAUDE.md declara dos copias y hay cuatro, así que al menos dos se escribieron después de que la prohibición estuviera escrita. No ha producido todavía un número distinto: comparé las cuatro contra el CTE `tocaba` de `fn_faltas` y las cuatro respeta…

**ARREGLO**

DECIDÍ: la correcta es `apps/web/lib/admin/jornada-esperada.ts` — lo dice CLAUDE.md, tiene pruebas propias (`tests/jornada-esperada.test.ts`) y es la que declara espejar `fn_recalcular_jornada`. `incidencias.trabajaEseDia` y `turnos.celda` se reemplazan por llamadas a `esperadoDelDia()`, que ya devuelve todo lo que las dos necesitan (si trabaja, entrada, salida y refrigerio). `correcciones.calcularEsperado` es la unificación que CLAUDE.md ya tenía pendiente y entra en el mismo cambio.
DESCARTÉ porque: dejarlo y anotar en CLAUDE.md que ahora son cinco copias sería documentar la deuda en vez de …

**COSTO** · Medio. Tres archivos grandes tocados en su parte más leída, sin migración y sin tocar la base, pero con riesgo de regresión visual en Turnos. Un día, y hay que dejarlo cubierto por pruebas: las de `tests/jornada-esperada.test.ts` ya existen y habría que añadir los casos que hoy solo viven implícitos en cada copia (turno de descanso, `horario_por_dia` sin ese día, tramo legacy con `dias_laborables`, y un domingo de TRU).

---

### [P2] El catálogo de áreas está escrito a mano tres veces y las tres copias ya no dicen lo mismo

**DÓNDE** · `apps/web/lib/areas.ts:19-26 (AREAS_FALLBACK) · apps/web/lib/politica-salarial.ts:109-117 (AREAS_DOC) · tabla `areas`, sembrada en supabase/migrations/0022_areas_catalogo.sql:22-28`

**EJE** · arquitectura  ·  **ORIGEN** · contradicción · vocabulario

**REGLA QUE INCUMPLE** · CLAUDE.md, regla 3 de packages/shared: «Nunca una lista escrita a mano de algo que vive en una tabla». El propio areas.ts se declara «catálogo DINÁMICO (tabla `areas`, migración 0022)» y aun así lo escribe entero.

**QUÉ PASA**

Las seis áreas viven en una tabla que Felipe edita desde /admin/areas, y además están copiadas a mano en dos archivos de TypeScript. Una de esas copias —AREAS_DOC— es la que se imprime en el documento de política salarial que el equipo firma, y no lee la tabla: es una lista de strings congelada en el código. Las tres copias ya divergen en el nombre del área base.

**SE ROMPE ASÍ**

Felipe abre /admin/areas y renombra un área, o crea la séptima (el catálogo existe justamente para eso). Las siete pantallas del panel la muestran con el nombre nuevo al instante. El documento de política salarial —el que está publicado, versionado y con acuse de recibo del equipo, y que es la prueba que se presenta en una inspección— sigue listando las seis áreas viejas con sus nombres viejos. Nadie se entera, porque el documento se ve bien: simplemente describe una empresa que ya no existe. Y …

**YA OCURRIÓ** · Sí, la divergencia ya está: «&» en la tabla y en areas.ts, «y» en politica-salarial.ts. Es cosmética hoy y por eso nadie la vio. Detecta el resto: SELECT nombre FROM areas ORDER BY orden; y comparar a mano contra AREAS_DOC — no hay prueba que lo haga.

**ARREGLO**

DECIDÍ: que AREAS_DOC desaparezca y que construirDocumento reciba las áreas del mismo `Cuadro` que ya recibe las categorías (la RPC del cuadro ya va a la base; agregarle las áreas es una columna más en el jsonb). DESCARTÉ importar AREAS_FALLBACK desde politica-salarial.ts —que uniría las dos copias de TS en una— porque dejaría el documento publicado colgando de un respaldo de emergencia en vez de del catálogo real. AREAS_FALLBACK sí se queda: su razón de ser está escrita y es legítima (que la cobertura de turnos no se caiga si la RPC falla). SE ROMPE SI la publicación pasa a leer las áreas en …

**COSTO** · Medio. Una columna más en la RPC del cuadro + un cambio en construirDocumento + borrar AREAS_DOC. Y una republicación con acuse, que es la parte cara: la firma el equipo entero.

---

### [P2] `pnpm lint` está en rojo con 119 errores y nada en la red de seguridad lo mira

**DÓNDE** · `package.json:7 ("lint": "turbo run lint") · .github/workflows/tests.yml (no invoca lint) · scripts/hooks/ (no invoca lint)`

**EJE** · arquitectura  ·  **ORIGEN** · mecánica

**REGLA QUE INCUMPLE** · falta un criterio — CLAUDE.md describe la red de seguridad (pre-push: numeración + typecheck + pruebas de interfaz; tests.yml: pgTAP + typecheck + vitest) y `lint` no aparece en ninguna de las dos, pese a existir como script

**QUÉ PASA**

Hay un guardián instalado que nadie enciende. Corre en rojo permanente, así que la primera vez que alguien lo mire va a encontrar 119 errores viejos y va a aprender que sus avisos son trámite — exactamente lo que CLAUDE.md ya diagnosticó con el hook que paraba a pedir un comando de una línea.

**SE ROMPE ASÍ**

Alguien agrega una pantalla de planilla con un `useMemo` de dependencias incompletas. El lint lo detecta —ya detecta uno hoy, datos-personales/page.tsx:481, «useMemo has a missing dependency: 'FALTANTES'»— pero el aviso se pierde entre 119 errores preexistentes que nadie lee, y la pantalla muestra un total congelado del periodo anterior.

**YA OCURRIÓ** · sí, en cuanto a la deuda: los 119 errores ya están en el árbol. En cuanto a un cálculo mal mostrado, indeterminado — no lo detecta un SELECT, es estado de React en el navegador.

**ARREGLO**

DECIDÍ: separar las dos mitades, como ya se hizo con numeración. Primero bajar el ruido (los 17 no-unused-vars y los 3 no-img-element son mecánicos), y recién con lint en verde agregarlo a ui-tests en tests.yml. DESCARTÉ meterlo al CI hoy: dejaría todos los pushes en rojo y el primer reflejo sería --no-verify. DESCARTÉ apagar reglas: no-explicit-any en 49 sitios es deuda de tipos real, no ruido de configuración. SE ROMPE SI: se corrigen los `any` a las apuradas con casts que mienten — el `any` de apps/web/lib/terminal/roster.ts:46 toca datos de marcaje.

**COSTO** · Medio. Los 20 errores mecánicos, una tarde; los 49 `any`, varias sesiones. El paso al CI es de cinco minutos y va al final.

---

### [P2] Nadie corre el linter: 140 avisos invisibles, 119 de ellos errores, y dos comentarios en el código que creen que alguien mira

**DÓNDE** · `scripts/hooks/pre-push:21-111 · .github/workflows/tests.yml:22-45 · scripts/desplegar.sh · package.json:8 ("lint": "turbo run lint") · turbo.json (tarea lint declarada)`

**EJE** · arquitectura  ·  **ORIGEN** · mecánica

**REGLA QUE INCUMPLE** · La regla escrita en la cabecera del propio hook (scripts/hooks/pre-push:6): «Un freno que no frena es peor que no tener freno, porque uno confía en él.»

**QUÉ PASA**

El repositorio tiene ESLint instalado, configurado, con tarea de turbo y con script en el package.json. No lo ejecuta nadie: ni el hook de pre-push, ni GitHub Actions, ni desplegar.sh. La consecuencia no es «hay avisos pendientes»: es que dos personas escribieron `eslint-disable-next-line` para callar una regla que nunca iba a hablar, y eso es la prueba de que se cree que el linter está mirando.

**SE ROMPE ASÍ**

Alguien escribe una pantalla nueva de asistencia y le pone `(j: any)` a las jornadas para salir del paso, igual que las doce que ya hay en Incidencias. El campo se llama `minutos_tarde` y ella escribe `j.minutosTarde`. TypeScript no dice nada porque es any. Los tests no la tocan porque es una pantalla. El typecheck pasa, el push pasa, CI pasa, se despliega. La pantalla muestra 0 tardanzas para todo el equipo y se lee como una buena semana.

**YA OCURRIÓ** · Sí. Se comprueba en esta Mac sin tocar nada: `cd apps/web && npx eslint .` devuelve hoy 140 problemas. No hace falta SQL. Desde cuándo: los dos `eslint-disable` están commiteados, así que al menos desde que se escribieron esas dos pantallas.

**ARREGLO**

DECIDÍ: NO agregar `pnpm lint` al hook hoy. Con 119 errores en pie, un freno nuevo bloquearía el primer push que lo encuentre por deuda ajena, y este repositorio ya escribió tres veces por qué eso termina en `--no-verify` (pre-push:36-40, y el episodio de los cuatro pushes del 2026-08-08). El orden que respeta esa lección es: primero bajar a cero —empezando por incidencias y espejo, que es donde el any decide si alguien tuvo una falta y qué ve el contador—, y recién con el marcador limpio encender el freno.
DESCARTÉ encenderlo con `--max-warnings` alto o con reglas apagadas: es un freno que ch…

**COSTO** · Encender el freno: cinco minutos (una línea en pre-push y otra en tests.yml). Llegar a cero: los 49 any son el grueso, y los 23 de incidencias + espejo valen por sí solos aunque no se toque nada más — un día. Los 50 de set-state-in-effect son reglas nuevas de React 19 y pueden quedar en warning sin bloquear.

---

### [P2] Diez comparaciones de rol contra un literal fuera de permisos.ts, y una de ellas es un filtro por sede que no filtra nada

**DÓNDE** · `apps/web/app/(admin)/admin/incidencias/page.tsx:616-624 · correcciones/page.tsx:366 · horarios/page.tsx:113 · dashboard/page.tsx:276 · objetivos/page.tsx:94,95,321 · reporte-sede/page.tsx:183 · turnos/page.tsx:630 · app/api/admin/cuentas/route.ts:334`

**EJE** · arquitectura  ·  **ORIGEN** · mecánica

**REGLA QUE INCUMPLE** · CLAUDE.md: «Nunca comparar rol contra un string literal fuera de permisos.ts. … Un rol === "admin" suelto en una pantalla es un permiso que nadie va a encontrar el día que haya que cambiarlo.» La regla se escribió tras juntar 35 copias de la misma condición.

**QUÉ PASA**

Volvieron diez de las condiciones que la regla existe para evitar. Y una de ellas no solo está fuera de sitio: no hace nada. En Incidencias hay un bloque titulado «Encargada: solo su sede» cuyas dos ramas devuelven exactamente la misma lista sin filtrar, con un comentario que afirma que filtra.

**SE ROMPE ASÍ**

Felipe crea un rol nuevo —«encargada de piso» con cuenta propia, digamos— y lo agrega a DO_Y_ENCARGADA en permisos.ts, que es el sitio donde el CLAUDE.md dice que se agrega. Le funciona la navegación, le funcionan las siete pantallas que preguntan con puedeOperarEquipo. Y le falla en diez sitios que preguntan por el string: en Objetivos se le queda en solo lectura, en Correcciones no le sale el aviso de alcance, en el Dashboard no aparece marcada como encargada. Va a encontrar los diez de uno en…

**YA OCURRIÓ** · Sí, están en el árbol hoy: el grep de arriba corre en esta Mac y devuelve las diez líneas. Ninguna produce hoy un permiso incorrecto —los cuatro roles actuales son los mismos que había cuando se escribieron—, así que hoy no cuesta plata: es una bomba de mantenimiento, y se activa el día que cambie l…

**ARREGLO**

DECIDÍ: separar dos cosas que se están mezclando. (a) Las nueve comparaciones que preguntan «¿es encargada?» piden una función en permisos.ts —`esEncargadaDeSede(rol)`— y se reemplazan de una. (b) El bloque de incidencias/page.tsx:616-624 se BORRA, no se arregla: no filtra, y su comentario afirma una garantía que la base no da. Dejarlo «mejorado» sería seguir diciendo que hay una salvaguarda donde no la hay.
DESCARTÉ hacer que ese bloque sí filtre por sede en memoria: taparía el hallazgo P1 en una sola pantalla y dejaría el hueco de RLS abierto para todo lo demás. El alcance se arregla en la b…

**COSTO** · Una tarde. Una función nueva en permisos.ts con su prueba en tests/permisos.test.ts (que ya tiene 16 casos), nueve reemplazos mecánicos y un bloque de nueve líneas borrado.

---

### [P2] «Qué le tocaba trabajar ese día» está escrita cuatro veces, y la copia que decide el aviso de cobertura no dice lo mismo que la original

**DÓNDE** · `apps/web/lib/admin/jornada-esperada.ts:90-127 (la buena) · apps/web/app/(admin)/admin/correcciones/page.tsx:49 (la conocida) · apps/web/app/(admin)/admin/incidencias/page.tsx:492-503 (tercera, no documentada) · apps/web/app/(admin)/admin/turnos/page.tsx:228-235 y :602-603 (cuarta, no documentada)`

**EJE** · diseno  ·  **ORIGEN** · mecánica

**REGLA QUE INCUMPLE** · CLAUDE.md, textual: «qué le tocaba trabajar ese día» se pregunta a apps/web/lib/admin/jornada-esperada.ts, no se vuelve a escribir. … Queda una copia más vieja y parcial … en admin/correcciones/page.tsx (calcularEsperado): unificarlas está pendiente, y mientras tanto NO SE ESCRIBE UNA TERCERA.

**QUÉ PASA**

La cascada turno del día → horario_por_dia → dias_laborables está reimplementada en Incidencias y en Turnos, dos sitios que el CLAUDE.md no menciona. La de Incidencias además responde distinto que la original en un caso concreto: un día presente en el jsonb pero sin hora de entrada. La original dice «descanso»; la copia dice «trabaja». Sobre esa respuesta se arma el aviso de «Déficit de encargadas».

**SE ROMPE ASÍ**

A una encargada de AQP se le guarda el domingo en su horario_por_dia con hora de salida y sin hora de entrada — un guardado a medias desde la pantalla de Horarios, o un tramo migrado a mano. Incidencias la cuenta como cubierta ese domingo, así que el aviso «Déficit de encargadas (1/2)» nunca sale y nadie se entera de que la tienda abre el domingo con una sola encargada. La pantalla de Horas, que sí usa la regla buena, la pinta como descanso ese mismo día. Las dos pantallas se contradicen y ningu…

**YA OCURRIÓ** · Indeterminado — horarios_asignados tiene 0 filas en la base local, así que no hay nada que medir aquí. Para saberlo en producción, un solo select que busca días del jsonb sin hora de entrada:

select p.nombres||' '||p.apellidos as persona, s.codigo as sede, h.vigente_desde, d.key as dia_semana, d.va…

**ARREGLO**

DECIDÍ: que trabajaEseDia() de Incidencias llame a esperadoDelDia() y devuelva su campo .trabaja. Los datos que necesita ya están cargados en esa misma función (turnoPorClave y horariosPorPersona traen los mismos campos que pide HorarioTramo, salvo almuerzo_min_minutos, que para esta pregunta no se usa). Es un cambio de doce líneas y borra una copia entera.
DESCARTÉ arreglar el `Boolean(...)` en su sitio: deja la copia en pie y con ella el modo de fallo, que es que la próxima corrección vaya a un solo archivo de los cuatro.
DESCARTÉ tocar Turnos en el mismo cambio: ahí la cascada devuelve hora…

**COSTO** · El de Incidencias: un par de horas con su prueba. El de Turnos y el de correcciones: medio día cada uno, y ninguno urgente. Lo barato y lo que evita el próximo caso es dejar escrito en el CLAUDE.md que las copias son cuatro y cuáles son — hoy dice dos, y quien lea eso creerá que ya las conoce todas.

---

### [P2] Ninguna pantalla lee `fecha_jornada`: el día que se pagó muestra la entrada y esconde la salida que lo cierra

**DÓNDE** · `apps/web/app/(admin)/admin/correcciones/page.tsx:196-203 · apps/web/app/api/espejo/route.ts:45 · apps/web/lib/terminal/estado-dia.ts:57-67 · fn_dias_por_revisar`

**EJE** · diseno  ·  **ORIGEN** · eje · trazabilidad

**REGLA QUE INCUMPLE** · CLAUDE.md — «Los marcajes son la fuente de verdad». Toda pantalla que audita un día tiene que enseñar las marcas que produjeron sus horas; si no, la cadena monto → jornada → marcaje se corta en la capa donde una persona la mira.

**QUÉ PASA**

`fecha_jornada` aparece solo en packages/database/src/types.ts (columna generada) y en ningún otro archivo de apps/web ni de packages. La pantalla de Correcciones —la única donde se audita cómo se armó un día— trae las marcas con una ventana de reloj: `const inicio = `${fecha}T00:00:00-05:00`; const fin = `${fecha}T23:59:59-05:00`;` … `.gte("timestamp_marca", inicio).lte("timestamp_marca", fin)`, mientras la jornada se trae con `.eq("fecha", fecha)`. Las dos consultas del mismo día responden por criterios distintos.

**SE ROMPE ASÍ**

Quien tiene que defender el pago abre Correcciones del 28, ve 8.50 h contra una entrada sin salida y concluye que el día está roto —cuando está bien y la marca existe en la base—. Al día siguiente ve una salida sin entrada y concluye que sobra. El camino cómodo desde ahí es «corregir» a mano lo que no estaba mal: anular la salida huérfana o agregar una entrada inventada. Y el espejo a Google Sheets, que es la copia que se mira fuera del sistema, guarda esa misma marca en el día equivocado.

**YA OCURRIÓ** · No consta. Lo que sí consta es que la pantalla ya tiene un caso conocido de mostrar un día que no se entiende («21 de 10 días», visto en producción el 2026-07-28, comentado en boleta/page.tsx), así que el modo de fallo «la pantalla cuenta algo que no cuadra y alguien lo arregla a mano» no es hipotét…

**ARREGLO**

Traer las marcas del día por jornada y no por reloj: `.or(`fecha_jornada.eq.${fecha},and(fecha_jornada.is.null,timestamp_marca.gte.${inicio},timestamp_marca.lte.${fin})`)`. Lo mismo en el espejo y en fn_dias_por_revisar, que agrupa por `(m.timestamp_marca at time zone 'America/Lima')::date`. Y marcar en la fila que esa salida es de la noche anterior, para que quien la lea no crea que se equivocó de día.

**COSTO** · Tres consultas y una función SQL. Un par de horas. Depende de nada: se puede hacer antes o después del hallazgo del candado.

---

### [P2] Una marca apartada deja un aviso rojo que nadie puede quitar, y la encargada no tiene dónde verla

**DÓNDE** · `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/lib/terminal/offline-db.ts:94-109 · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/lib/terminal/sync.ts:45-47 · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(terminal)/terminal/marcar/page.tsx:181-192,499-503`

**EJE** · diseno  ·  **ORIGEN** · eje · terminal

**REGLA QUE INCUMPLE** · CLAUDE.md: «Un guardián que te para para pedirte algo que él mismo puede hacer enseña que sus avisos son trámite; el día que frene de verdad, ya le habrá enseñado a quien lo lee a ignorarlo». Y la promesa escrita en sync.ts: «una marca que una persona hizo de verdad jamás se destruye».

**QUÉ PASA**

`marcarComoDescartada` pone `descartada = true` y deja la fila en IndexedDB. `eliminarDeOutbox` solo se llama cuando el servidor confirma, o sea nunca para una apartada. No hay ninguna otra ruta que la borre, ni ninguna que la reponga, y `obtenerDescartadas` solo la lee el contador de la cabecera del propio terminal. El resultado es una insignia roja permanente —«⚠ N sin registrar — avisa a tu encargada»— cuyo número solo puede subir, en una pantalla que está encendida todo el día delante de todo el equipo. Y el aviso pide una acción que no se puede completar: la encargada no tiene ninguna pantalla que diga de quién era esa marca, de qué tipo ni de qué hora; el dato vive únicamente en el Ind…

**SE ROMPE ASÍ**

El día que el servidor rechace una marca por lo que sea —el retorno del hallazgo 2, la salida de madrugada del hallazgo 3, o un rechazo legítimo— esa marca se aparta y el aviso rojo se queda encendido para siempre. A la semana siguiente nadie lo mira: es parte del decorado del terminal. El día que se aparte una marca de verdad importante, el aviso ya no comunica nada. Y aunque alguien lo mire el primer día, la encargada no tiene forma de averiguar qué marca fue: el mensaje la nombra como la pers…

**YA OCURRIÓ** · No medido: las apartadas viven en el IndexedDB de cada Mac mini y no hay forma de consultarlas desde la base. Se ve mirando la cabecera del terminal de cada sede: si hay una insignia roja, ya ocurrió, y lleva ahí desde el día en que apareció.

**ARREGLO**

Dos mitades, y ninguna sirve sola. (1) Que la apartada llegue a alguien: una ruta de servidor que reciba las entradas apartadas y las deje en una tabla —`marcajes_apartados`, sin tocar `marcajes`— con persona, tipo, hora, terminal y el último error; el panel de Correcciones ya es el sitio donde una persona decide qué hacer con un día. (2) Que el aviso se pueda apagar: una vez repuesta o descartada explícitamente por una persona, el terminal deja de contarla. Mientras la mitad (1) no exista, el aviso está pidiendo algo imposible.

**COSTO** · Mediano. Una migración con tabla nueva y su policy, una ruta de servidor, un envío desde sync.ts y una tarjeta en Correcciones. Se puede hacer por partes: subir el dato primero, la pantalla después.

---

### [P2] El error de guardar se pinta DEBAJO del velo del modal: en Horarios y Correcciones, fallar se ve igual que no pulsar

**DÓNDE** · `apps/web/app/(admin)/admin/horarios/page.tsx:178,181,182,189 (aviso en :223, modal en :275) · apps/web/app/(admin)/admin/correcciones/page.tsx:345-350 (aviso en :441, modales en :693 y :723)`

**EJE** · diseno  ·  **ORIGEN** · eje · diseno

**REGLA QUE INCUMPLE** · docs/plan-diseno-2026-07-27.md seccion 2 punto 3 ya escribio la regla — «el mensaje va donde esta la mano, no donde esta el titulo». Sigue sin aplicarse 3 semanas despues. Y CLAUDE.md: «Los marcajes son la fuente de verdad» — una correccion que la encargada cree hecha y no lo esta deja mal las horas que se pagan.

**QUÉ PASA**

En los dos archivos el camino de exito cierra el modal ANTES de avisar, y el camino de error avisa SIN cerrarlo. El aviso se dibuja en el flujo normal de la pagina; el modal es un `fixed inset-0 z-10 ... bg-black/40` a pantalla completa. Resultado: el «guardado» se ve y el «no se guardo» queda debajo del velo oscuro y ademas fuera del alto visible, porque el modal se centra en la ventana mientras el aviso vive arriba del documento. En Horarios ni siquiera hace falta que falle la base: los tres frenos de validacion mas frecuentes —«Marca al menos un dia de trabajo», «Falta la hora de entrada de algun dia», «Falta la hora de salida de algun dia»— salen por esa misma puerta muda.

**SE ROMPE ASÍ**

La encargada de AQP abre el horario de una integrante, marca los dias pero se salta la hora de salida de uno, pulsa «Guardar». No pasa nada visible. Vuelve a pulsar. Nada. Cierra el modal creyendo que se guardo. El horario viejo sigue vigente, y `fn_recalcular_jornada` sigue midiendo tardanzas y faltas contra la jornada equivocada.

**YA OCURRIÓ** · El sintoma es indistinguible de «no pulse bien», asi que no deja rastro que se pueda contar desde aca. Lo verificable hoy: el codigo esta en produccion con esa forma, y la auditoria de julio ya lo habia descrito con nombre y linea (`correcciones/page.tsx:348` entonces, `:346` ahora) sin que se corri…

**ARREGLO**

Dos lineas por pantalla: mover el bloque `{mensaje && ...}` DENTRO del recuadro del modal, junto al boton que se pulso, y dejar el aviso de pagina solo para lo que ocurre fuera de un modal. El modelo bueno ya existe en el repo: `horas/page.tsx:1091` es un `<aside role="dialog" aria-label=...>` con su cierre por Escape en :799. No hay que inventar el patron, hay que copiarlo.

**COSTO** · Una a dos horas las cuatro pantallas (horarios, correcciones x2, incidencias:808, turnos:1173 y :1236).

---

### [P2] La fecha legal de la comunicacion de cargos se teclea a mano en un window.prompt, no se valida, y si sale mal la fila queda congelada para siempre

**DÓNDE** · `apps/web/app/(admin)/admin/disciplina/page.tsx:440-466 · apps/web/lib/admin/instante-entrega.ts:30`

**EJE** · diseno  ·  **ORIGEN** · eje · diseno

**REGLA QUE INCUMPLE** · CLAUDE.md: «Dynamic avisa, nunca sanciona solo… el sistema arma el expediente». De esa fecha cuelgan los dos dias habiles de descargo del art. 55.2 del RIT, y docs/estado.md del 2026-08-17 documenta que omitir ese plazo es acto de hostilidad (Res. 810-2022-SUNAFIL/TFL, tope ~S/ 42,075). Ademas la app ya tiene 41 `type="date"`: el patron existe y aqui no se uso.

**QUÉ PASA**

`declararCargos` pide el dia con `window.prompt("¿Que dia se le comunicaron los cargos? (AAAA-MM-DD)")` y lo pasa tal cual a `instanteEntrega(dia, null)`. No hay ninguna validacion de formato en la pantalla. `instanteEntrega` hace `new Date(dia + "T12:00:00-05:00")` y termina en `t.toISOString()`, que ante una fecha mal escrita LANZA. Como el `onClick` es `() => void declararCargos(d)`, el throw se convierte en un rechazo de promesa que nadie atrapa: `setOcupado(d.id)` (linea 456) ya corrio y `setOcupado(null)` (linea 463) no llega nunca. Toda la fila queda deshabilitada —Comunicar cargos (:992), el selector de firmante (:1011), Firmar (:1029), Adjuntar descargo (:1041), Anular (:1048) todos…

**SE ROMPE ASÍ**

DO abre Disciplina para regularizar los memos que quedaron atrapados, pulsa «Declarar cargos ya comunicados» y escribe 11/08/2026 como escribe cualquier fecha en Peru. La ventana se cierra, no aparece error, y todos los botones de ese memo se apagan. Ese expediente no se puede firmar, ni anular, ni adjuntarle el descargo hasta recargar — y quien lo mira concluye que el sistema «no la deja» por una regla legal, no por una fecha mal tecleada.

**YA OCURRIÓ** · Latente hasta donde se puede ver desde aqui: no hay forma de saber desde el codigo si alguien ya lo tecleo mal. Lo que si esta: el codigo se escribio ayer (migracion 0266, docs/estado.md 2026-08-17) y sirve precisamente para desatascar tres memos parados, o sea que su momento de uso es AHORA y lo va…

**ARREGLO**

Cambiar los dos `window.prompt` por un formulario propio con `<input type="date" max={hoyLima()}>` —sin valor por defecto, o con ayer— y un `<textarea>` para la constancia, los dos en la misma ventana para que un fallo de validacion no borre lo ya escrito (hoy el segundo prompt tira el primero: :452 exige 15 caracteres y al fallar hay que reteclear ambos). Y envolver el cuerpo en try/catch con `setOcupado(null)` en el `finally`, que es lo que impide el congelamiento aunque el resto quede igual.

**COSTO** · El try/finally: cinco minutos, y solo eso ya quita el callejon sin salida. El formulario propio: dos a tres horas, y de paso sirve para los otros nueve `window.prompt` de la app.

---

### [P2] Las opacidades deshacen el arreglo de contraste de julio: el aviso «sin enviar» del terminal esta en 3.74:1 y los denominadores de Horas en 2.43:1

**DÓNDE** · `apps/web/app/globals.css:16 (el token, ya corregido) · apps/web/app/(terminal)/terminal/marcar/page.tsx:491 y :514 · apps/web/app/(admin)/admin/horas/page.tsx:462, :980, :985, :991`

**EJE** · diseno  ·  **ORIGEN** · eje · diseno

**REGLA QUE INCUMPLE** · docs/plan-diseno-2026-07-27.md seccion 2 punto 2 pidio DOS movimientos y solo se hizo el primero: «(a) Oscurecer --color-ambar… (b) Cambiar el fondo de esos avisos y badges de bg-ambar/15 a bg-sand… porque el fondo ambar acerca el fondo al color de la letra y come el contraste que acabamos de ganar.» El minimo internacional para texto es 4.5:1.

**QUÉ PASA**

El token se oscurecio como se pidio: `--color-ambar` esta hoy en `#8d6726` y da 4.51:1 sobre crema — pasa. Pero 27 sitios lo siguen pintando sobre `bg-ambar/15`, que al mezclarse con la crema da #e5dbcb y baja el par a 3.74:1. El mas caro es el badge del terminal: «⟳ N sin enviar» significa que hay marcajes que no llegaron al servidor. Lo mismo pasa con el taupe: se oscurecio a `#805c4c` (5.21:1) y despues 67 usos lo diluyen con `text-taupe/60` (2.43:1), `/50` (2.05:1) y `/40` (1.71:1). En la mayoria eso es correcto —son los guiones «—» que significan cero, y la propia auditoria de julio dijo que un guion tiene el trabajo de callarse—, pero cuatro de ellos en Horas son palabras con significa…

**SE ROMPE ASÍ**

En el terminal con luz de vitrina, el badge ambar sobre ambar a 12px no se lee de reojo, y nadie avisa de que hay marcas sin enviar. En Horas, quien revisa lee «22» sin ver el «/ 24» que esta al lado: cree que la persona cumplio sus dias.

**YA OCURRIÓ** · Hoy no cuesta nada mientras alguien mire de cerca — es riesgo de legibilidad, no de calculo. Lo verificable: la mitad del arreglo de julio esta aplicada (las tres variables) y la otra mitad no, y las cifras de arriba estan medidas contra el codigo de hoy, no contra el de entonces.

**ARREGLO**

Anadir tres fondos SOLIDOS al `@theme` (`--color-ambar-fondo`, `--color-verde-fondo`, `--color-rojo-fondo`, del orden de #f1e9d9) y sustituir con ellos los 27 `bg-ambar/15` y sus primos: asi el texto se pinta sobre un fondo que no es su propio color. Subir los cuatro de Horas de `text-taupe/60` a `text-taupe`. Y la regla que lo cierra: la opacidad no se usa nunca sobre texto que sean palabras — solo sobre guiones, bordes y fondos.

**COSTO** · Una hora los fondos, cinco minutos los cuatro de Horas. Y media hora la prueba de contraste en `scripts/hooks/pre-push` que julio pidio bajo el titulo «lo que nadie pidio y es lo que mas importa», y que sigue sin existir.

---

### [P2] Cinco acciones que devuelven plata o reabren un expediente se ejecutan al primer clic, sin preguntar y sin confirmar despues

**DÓNDE** · `apps/web/app/(admin)/admin/correcciones/page.tsx:285-290 (quitar levantamiento) · apps/web/app/(admin)/admin/incidencias/page.tsx:608-614 y :779-784 (quitar justif.) · apps/web/app/(admin)/admin/feriados/page.tsx:362-371 (quitar descanso sustitutorio) · apps/web/app/(admin)/admin/equipo/page.tsx:1501 (Nuevo PIN, ya descrito aparte)`

**EJE** · diseno  ·  **ORIGEN** · eje · diseno

**REGLA QUE INCUMPLE** · docs/plan-diseno-2026-07-27.md seccion 2 punto 5 pidio exactamente esto («Simetria: si Justificar pregunta, quitar justif. tambien») y no se hizo. CLAUDE.md: «Los falsos positivos son el peor error» — quitar una justificacion devuelve una falta al expediente disciplinario de alguien.

**QUÉ PASA**

`quitarLevantamiento()` llama a `fn_quitar_levantamiento` y, si sale bien, solo hace `await cargarDia()`: no pregunta antes ni dice nada despues. `quitarJustificacion()` igual — `fn_quitar_justificacion` y `await cargar()`. Las dos devuelven una tardanza o una falta a la cuenta que alimenta el expediente disciplinario, y la primera ademas la saca del bono de puntualidad. La unica advertencia que existe vive en un atributo `title`, que solo aparece tras un segundo de raton encima y no existe en pantalla tactil. `quitar()` en Feriados no pregunta tampoco, pero al menos si confirma («Ese feriado vuelve a pagar sobretasa») — o sea que la mitad buena del patron ya esta escrita en el repo.

**SE ROMPE ASÍ**

La encargada repasa Incidencias en el celular, roza «quitar justif.» —12px, pegado al enlace «Corregir ›»— y la falta de esa integrante vuelve a contar. No hay confirmacion, no hay mensaje, la fila simplemente cambia. Cuando esa falta empuje el conteo por encima del umbral, el sistema va a proponer un borrador de amonestacion y nadie va a recordar por que.

**YA OCURRIÓ** · Latente en cuanto a clics accidentales — no hay forma de contarlos desde el codigo. Lo verificable hoy: las tres acciones no piden confirmacion, dos de las tres tampoco confirman al terminar, y el patron correcto ya existe en el mismo repo (planilla:1242, feriados:370).

**ARREGLO**

El `window.confirm` de Planilla, con la consecuencia dicha en la frase — «esta tardanza vuelve a contar y deja de sumar al bono de puntualidad», «esta falta vuelve a contar para el expediente» — mas el `avisar("ok", ...)` al terminar. Y sacar la consecuencia del `title` al texto visible.

**COSTO** · Minutos cada una; una hora las cinco juntas.

---

### [P2] Dos paginadores para el mismo problema, y el que corre todos los meses es el que no cumple la regla que el otro documenta

**DÓNDE** · `apps/web/app/api/espejo/route.ts:26-37 (copia inline) contra apps/web/lib/admin/traer-todo.ts:22-60 (el que tiene la regla)`

**EJE** · escala  ·  **ORIGEN** · contradicción · datos

**REGLA QUE INCUMPLE** · La regla está escrita dentro del propio repo, en apps/web/lib/admin/traer-todo.ts:16-20: «EL ORDEN NO ES DECORATIVO. Paginar con .range() sobre una consulta sin order estable es peor que no paginar (…) Toda consulta que pase por acá debe ordenar por algo único».

**QUÉ PASA**

HOY NO CUESTA NADA: las tres consultas sin orden del espejo caben todas en un solo lote, así que la paginación ni se activa para ellas. Lo que hay es una segunda implementación del mismo problema que no lleva el invariante ni el tope, y el margen de la más grande es de un 25 %: cuando `jornadas` de un mes pase de 1000 filas, la hoja de Google empieza a repetir y perder días sin decir nada.

**SE ROMPE ASÍ**

CAYLA contrata seis personas más, o abre una sede. El mes siguiente `jornadas` pasa de 1000 filas y pageAll pide el segundo lote con .range(1000, 1999) sobre una consulta sin ORDER BY. Postgres no promete el mismo orden entre dos ejecuciones del mismo plan, así que el segundo lote puede repetir filas que ya vinieron y saltarse otras. La hoja de Google —que es la matriz persona × día del mes con el total de horas y el conteo de tardanzas— sale con días en blanco para gente que sí trabajó y con ho…

**YA OCURRIÓ** · No, para las tres consultas sin orden: por volumen no llegan al segundo lote (~730 de 1000 en jornadas; 30 en personas y 4 en sedes). La cuarta, marcajes, sí pagina hoy —dos marcas mínimas × 26 días × ~28 activas ≈ 1450 filas— pero ordena por timestamp_marca, que es timestamptz con precisión de micr…

**ARREGLO**

DECIDÍ traer-todo.ts: borrar pageAll y usar traerTodo desde la ruta, agregando a cada consulta un orden único (jornadas por fecha + persona_id, personas y sedes por id, marcajes por timestamp_marca + id). Es el correcto porque lleva el invariante escrito, tiene el tope de 200 lotes que convierte una consulta desbocada en un mensaje en vez de un navegador colgado, y ya lo usan las cuatro pantallas del panel: unificar deja una sola definición de «traer todo» en el sistema. DESCARTÉ solo agregar .order() a las tres consultas del espejo: arregla las cuatro de hoy y deja el paginador duplicado, así…

**COSTO** · Una hora. Borrar doce líneas de espejo/route.ts, importar traerTodo, agregar el order a las cuatro consultas. Se verifica bajando el lote a 3 en una prueba local con datos sembrados y comprobando que la suma de filas coincide con el count(*) directo.

---

### [P2] En /admin/horas los turnos NO se paginan, y tienen la misma cardinalidad exacta que las jornadas que sí se paginan

**DÓNDE** · `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/horas/page.tsx:554 (jornadas, paginada) frente a :570 (turnos, sin paginar) y :563 (tardanzas_justificadas, sin paginar). El consumo, en :642.`

**EJE** · escala  ·  **ORIGEN** · eje · escala

**REGLA QUE INCUMPLE** · «Los falsos positivos son el peor error. Acusar de falta a quien no debía cuesta más que dejar pasar una falta real.» Y la regla de `traer-todo.ts`: «devuelve la lista completa, o un error. Nunca un subconjunto silencioso.»

**QUÉ PASA**

Las seis consultas del mismo `Promise.all` cargan el rango que elige quien mira. La de `jornadas` va envuelta en `traerTodo`, con un comentario que explica por qué: «PostgREST corta en 1000 filas y devuelve 200 OK sin avisar». La de `turnos` —dos líneas más abajo, mismo rango, misma cardinalidad— va suelta, sin `.range()`, sin `.order()` y sin tope. `turnos` tiene `unique(persona_id, fecha)`, igual que `jornadas`: por construcción devuelven el mismo número de filas para el mismo rango.

**SE ROMPE ASÍ**

Falta un turno en el mapa → `esperadoDelDia` (línea 642) cae al escalón siguiente de la cascada: `horario_por_dia` o `dias_laborables`. Un día que la encargada había marcado como `es_descanso: true` pasa de `{trabaja:false, origen:'turno'}` a `{trabaja:true, origen:'horario'}`. En el acumulado de la línea 683 eso suma `diasEsperados++` y `horasEsperadas += esperado.horas` sobre un día de descanso: baja el % de asistencia y aparece deuda de horas contra alguien que libraba. El cuadrito deja de pi…

**YA OCURRIÓ** · Sí, en su forma gemela y está documentado en este repo. `apps/web/lib/admin/traer-todo.ts:10-14` cuenta que «el CSV de asistencia se descargaba entero, abría bien en Excel y simplemente terminaba antes — sin ninguna marca. Ese archivo es el que va al contador». Y `reporte-sede/page.tsx:119-120`: «si…

**ARREGLO**

Envolver las consultas de `turnos` y `tardanzas_justificadas` en `traerTodo`, con el mismo orden estable que ya usa la de jornadas: `.order("fecha").order("persona_id").range(ini, fin)`. Son las dos únicas del `Promise.all` cuyo número de filas crece con personas × días; `horarios_asignados` crece solo con personas × tramos.

**COSTO** · bajo

---

### [P2] La ficha personal en PDF imprime «Sin salario asignado» y «Sin ficha cargada» cuando lo que pasó es que la consulta no contestó

**DÓNDE** · `apps/web/app/(admin)/admin/personas/[id]/page.tsx:90-106 (las cuatro consultas), :393-408 y :412-428 (lo que se pinta con ellas), :330 (botón «Descargar PDF», siempre habilitado)`

**EJE** · negocio  ·  **ORIGEN** · contradicción · errores

**REGLA QUE INCUMPLE** · CLAUDE.md, sobre `lo-que-no-se-pudo.ts`: «un cero no es la ausencia de un dato: es una afirmación». Y la regla de método de `tests/si-no-sin-dato.test.ts`: «Lo desconocido se dice con todas sus letras» — ahí se prohíbe explícitamente confundir el «no» declarado con el «no se sabe», porque el documento sale de CAYLA hacia terceros.

**QUÉ PASA**

La ficha de una persona se carga con cuatro consultas de las que no se lee ni un solo `error`. Si la del salario falla, la sección Compensación imprime «Sin salario asignado». Si falla la de datos personales, imprime «Sin ficha cargada. Completar». Las dos frases son afirmaciones sobre una persona real, salen en un PDF que se archiva, y el botón de descargarlo está habilitado igual. El propio archivo distingue bien el caso de la persona (:88, corta y avisa si `personas` falla) y luego deja de mirar en la línea siguiente.

**SE ROMPE ASÍ**

Una encargada abre la ficha de una integrante de su sede para archivarla en el legajo. `fn_historial_salario` es SECURITY DEFINER y bloquea por rol; si un día cambia su GRANT o se reescribe la función (ya pasó con `fn_tardanzas_resumen` en la 0204, documentado en dashboard/page.tsx:130-134), la RPC devuelve error. La pantalla no dice nada, la sección Compensación dice «Sin salario asignado», y el PDF que se archiva en el legajo de esa persona afirma por escrito que no tiene sueldo asignado. El m…

**YA OCURRIÓ** · indeterminado, y no es reconstruible: el PDF se guarda fuera del sistema y el fallo de la consulta no deja rastro. Lo que sí se puede comprobar en producción es cuántas personas caerían en «Sin salario asignado» de verdad (y por tanto cuánto ruido tapa el caso legítimo). SELECT para el SQL Editor:

…

**ARREGLO**

DECIDI: recoger los cuatro `error` y aplicar el patrón de `reporte-sede`: `loQueNoSePudo([{ error: eSal, que: "el sueldo vigente" }, { error: eDp, que: "los datos personales" }, { error: eDd, que: "el expediente" }, { error: eS, que: "la sede" }])`, un aviso arriba que SÍ se imprima, y `disabled={!sePuedeEntregar(cargado, noSePudo)}` en «Descargar PDF». Y —esto es lo que evita el daño aunque alguien fuerce ⌘P— cambiar los dos textos de vacío: solo se dice «Sin salario asignado» / «Sin ficha cargada» cuando la consulta contestó y vino vacía; si falló, la sección dice «No se pudo leer», que es l…

**COSTO** · Bajo. Un archivo, ~20 líneas, sin migración. Las piezas (`loQueNoSePudo`, `sePuedeEntregar`) ya existen y tienen pruebas. Una hora.

---

### [P2] «Encargada» se define de dos formas: la alerta de cobertura no cuenta a la encargada de piso

**DÓNDE** · `apps/web/app/(admin)/admin/incidencias/page.tsx:214 y :480-517 · apps/web/app/(admin)/admin/turnos/page.tsx:628-630 · apps/web/app/(admin)/admin/dashboard/page.tsx:276 · apps/web/app/(admin)/admin/reporte-sede/page.tsx:183`

**EJE** · negocio  ·  **ORIGEN** · contradicción · permisos

**REGLA QUE INCUMPLE** · «Los falsos positivos son el peor error» (CLAUDE.md, Principios del sistema) y regla 4 (nunca comparar `rol` contra un literal fuera de `permisos.ts`).

**QUÉ PASA**

Turnos —la pantalla donde se configura el mínimo de encargadas por sede y día— cuenta como encargada a quien tiene el rol `supervisor_sede` O la marca `es_encargada_piso`. Incidencias, que es la que EMITE la alerta «Déficit de encargadas», solo cuenta el rol. Una sede que está cubierta por una encargada de piso sale en rojo como descubierta, y el panel pide mover un turno que ya estaba bien. Dashboard y Hoja de sede usan la definición ancha: tres pantallas dicen una cosa y la que avisa dice otra.

**SE ROMPE ASÍ**

Una sede —digamos CCO— tiene `meta_encargadas = 1` para el martes. Ese martes quien cubre el piso es la persona marcada `es_encargada_piso` (el caso real que el comentario de Turnos nombra: un admin de confianza que además está en el piso). En Turnos la fila de cobertura del martes sale completa. En Incidencias, el mismo martes, aparece «Déficit de encargadas (0/1) · Sede CCO». Quien mira el panel de avisos —que es la encargada o DO al empezar el día— reprograma un turno para tapar un hueco que …

**YA OCURRIÓ** · Indeterminado, y hay que confirmarlo antes de correr: el Postgres local está vacío (0 personas activas, 0 filas en `metas_cobertura`), así que aquí no se puede medir. Si hoy nadie activo tiene `es_encargada_piso = true` en una sede con meta > 0, la contradicción no cuesta nada todavía y es solo una …

**ARREGLO**

DECIDÍ: la correcta es la de Turnos (`rol === supervisor_sede || es_encargada_piso`), porque `es_encargada_piso` es una columna de `personas` que existe precisamente para decir «esta persona cuenta en la cobertura», tiene su propia función de escritura con permiso de DO, y es la pantalla donde se define la meta contra la que se compara. La de Incidencias no es una decisión distinta: es la misma decisión tomada sin enterarse de que la columna existe. El arreglo es una función `esEncargada(rol, esEncargadaPiso)` en `packages/shared/src/permisos.ts` —el módulo hoy no nombra esta pregunta, y por e…

**COSTO** · Bajo. Una función nueva de tres líneas en `permisos.ts` con su prueba en vitest, cuatro llamadas y un select ampliado en Incidencias. Sin migración, sin tocar la base. Media hora, más el select de verificación en producción que Felipe tiene que correr ANTES para saber si esto ya está emitiendo alertas falsas.

---

### [P2] El sustento de la movilidad se lee de la base, se guarda en memoria y nunca se imprime en el documento que la gente firma

**DÓNDE** · `apps/web/app/(admin)/admin/documentacion/page.tsx:312 (estado), :678 (se pide a la base), :853-856 (se guarda), y ningún sitio más en toda la app`

**EJE** · negocio  ·  **ORIGEN** · mecánica

**REGLA QUE INCUMPLE** · El propio encabezado del archivo: «Un concepto no remunerativo sin su documento de respaldo no es un concepto: es un monto que alguien decidió. … El sustento no puede vivir en la cabeza de Felipe ni en un Word suelto. Vive aquí, sale con los datos de la persona y con fecha, y se archiva firmado.» Y del CLAUDE.md: «la movilidad y la educación son no remunerativas por el art. 19 e) y f)».

**QUÉ PASA**

La política de movilidad que se imprime y se firma dice cuánto se paga por sede, pero no dice POR QUÉ ese monto. El texto que lo justifica —el desglose de pasajes que hace que la cifra sea razonable— está en la base, se descarga con la tarifa, se guarda en un useState… y no se pinta en ninguna parte. El papel que sostiene la no remuneratividad de la movilidad sale sin el único párrafo que la sostiene.

**SE ROMPE ASÍ**

SUNAT o un inspector de SUNAFIL pide el respaldo de la movilidad de LIM (S/ 12.00 diarios, vigente desde el 2026-07-29). CAYLA presenta la política firmada por el equipo. El papel dice el monto y dice que se devenga solo por día asistido, pero no dice de dónde sale el 12. El criterio objetivo existe y está escrito —«pasaje urbano entre S/ 1.50 y S/ 3.20 según ruta y operador, cuatro tramos»— pero vive en una tabla que el inspector no ve, no en el documento que se le entrega. Es exactamente la fi…

**YA OCURRIÓ** · Sí, desde que existe la pantalla: no hay ninguna versión del código en la que la variable se haya llegado a pintar. Las tarifas por sede rigen desde el 2026-07-29 (vigente_desde en parametros_laborales), así que cualquier política emitida desde esa fecha salió sin sustento. Qué se está pagando hoy s…

**ARREGLO**

DECIDÍ: imprimir el sustento de CADA sede dentro de la tabla por sede que el documento ya pinta (una columna o un pie de tabla), leyéndolo de `tarifas`, que es de donde ya salen los montos. No de `general`.
DESCARTÉ arreglar solo la línea 856 (que tome la fila de la sede en vez de la general): sigue guardando UN sustento cuando el documento afirma TRES montos, y volvería a mentir el día que las tres sedes difieran — que es hoy.
DESCARTÉ escribir el sustento en el JSX: es justo lo que el comentario de la línea 853 prohíbe, y la razón está escrita ahí — el papel tiene que decir lo que dice la fi…

**COSTO** · Un cambio de render en un archivo, más borrar el useState de la línea 312 que queda sin dueño. Una o dos horas. Lo que hay que decidir antes —y es de Felipe— es si las políticas ya firmadas se reemiten con su sustento o se dejan como están y solo cambian las próximas.

---

### [P2] La asignación familiar tiene dos verdades: una con fecha para la boleta, una sin fecha para la liquidación

**DÓNDE** · `supabase/migrations/0129_tres_agujeros_de_permiso_cerrados.sql:177 (fn_remuneracion_computable, la vigente según ./scripts/donde-vive.sh). Contra supabase/migrations/0263_los_veinte_dias_de_descanso_medico_entran_a_la_base.sql (fn_planilla_calcular, líneas 93-106 del cuerpo) y supabase/migrations/0196_tres_puertas_en_vez_de_una_para_los_beneficios.sql:521 (fn_provisiones).`

**EJE** · negocio  ·  **ORIGEN** · eje · tasas

**REGLA QUE INCUMPLE** · CLAUDE.md: «Nunca una lista escrita a mano de algo que vive en una tabla» y el criterio de la 0122/0116/0118: una tasa legal se lee de una tabla versionada por fecha, porque recalcular un mes viejo con el valor de hoy da un resultado que no es ninguno de los dos.

**QUÉ PASA**

La 0122 movió la asignación familiar de `configuracion` (escalar sin fecha) a `parametros_laborales` (versionada) para la boleta y para las provisiones. A `fn_remuneracion_computable` se le pasó. Y esa función es la base de las TRES truncas: fn_cts_trunca, fn_grati_trunca_bruta y fn_vacaciones_truncas la llaman para armar la remuneración computable del cese. O sea: la boleta del mes lee la tabla con vigencia y la liquidación lee un escalar que nadie fecha.

**SE ROMPE ASÍ**

Medido contra el Postgres local dentro de BEGIN … ROLLBACK (persona con hijos, salario S/1,500, ingreso 2020-01-01; el ROLLBACK se ejecutó y se verificó después: configuracion sigue en 113.00, personas = 0).

DIRECCIÓN A — se registra el alza donde la 0122 puso la vigencia (cerrar la fila y abrir `asignacion_familiar` = 130.00 desde 2026-09-01):
  parametros_laborales dice, para un cese 2026-09-30 ....... 130.00000
  lo que usa la liquidación ................................ 113.00
  grati trunc…

**YA OCURRIÓ** · No. Hoy las dos fuentes dicen 113.00 y nadie está cobrando de menos ni de más — esto no cuesta un sol todavía. Lo que existe hoy es la divergencia estructural: dos funciones que ya no están de acuerdo sobre dónde vive la verdad. El disparador tiene nombre y fecha: el propio cuerpo de fn_planilla_cal…

**ARREGLO**

Una migración que reemplace en fn_remuneracion_computable la lectura de `configuracion` por la de `parametros_laborales` filtrando por `p_fecha_ref` (no por hoy: la remuneración computable es la del mes anterior al cese, art. 5.3 D.S. 005-2002-TR, y esa fecha es el criterio correcto de vigencia), conservando la lectura de configuracion como respaldo igual que hicieron la 0118 y la 0122. Copiar el cuerpo de 0129, que es la vigente. De paso, corregir el comentario que cita la 0069.

**COSTO** · Bajo. Una migración de una sola función, ~8 líneas cambiadas. La función ya tiene su guard y no cambia de firma. Verificable con el mismo BEGIN…ROLLBACK de arriba: con la fila de 130 vigente desde 2026-09-01, un cese de 2026-09-30 tiene que dar 130 y uno de 2025 tiene que seguir dando 113.

---

### [P2] Cambiar el tipo de vínculo reescribe lo que calcula un mes ya pagado, y la función ya sabe por qué eso está mal

**DÓNDE** · `supabase/migrations/0119_el_tipo_de_vinculo_se_puede_elegir.sql (fn_set_tipo_vinculo, única definición, vigente según donde-vive.sh) · apps/web/app/(admin)/admin/equipo/page.tsx:521`

**EJE** · negocio  ·  **ORIGEN** · eje · retroceso

**REGLA QUE INCUMPLE** · El candado de periodo pagado (0037, 0203). Y la coherencia con la propia función: fn_set_tipo_vinculo ya se niega a cambiar el vínculo de alguien cesado «porque su liquidación se calculó con el vínculo anterior», que es el mismo argumento, aplicado a un solo pago en vez de a todos.

**QUÉ PASA**

personas.tipo_vinculo no tiene fecha y la función no consulta periodos_planilla. La columna generada `en_planilla = tipo_vinculo in ('planilla','prueba')` gobierna en fn_planilla_calcular la pensión, EsSalud, la movilidad, la asignación por educación y las provisiones, y se lee en vivo para cualquier periodo. Pasar a alguien de 'planilla' a 'rxh' —el caso real es corregir una clasificación mal puesta— reescribe el cálculo de todos sus meses pagados. La función ya identificó el riesgo para la liquidación y levanta esa excepción; para la planilla pagada, que es el mismo hecho repetido cada mes, no hay nada.

**SE ROMPE ASÍ**

En /admin/equipo alguien corrige el vínculo de una persona mal clasificada (de 'planilla' a 'rxh', o de 'prueba' a 'planilla'). El cambio es correcto de aquí en adelante y no hay ninguna forma de decirle «desde cuándo». Al aplicarse hacia atrás, la boleta reimpresa de cualquier mes pagado de esa persona sale con otra cifra, y las bases de gratificación, CTS y vacaciones que se recalculen desde ahí salen del vínculo de hoy.

**YA OCURRIÓ** · No lo puedo afirmar desde local. Deja rastro propio, así que el select existe: select ca.persona_id, ca.valor_anterior, ca.valor_nuevo, ca.created_at from correcciones_auditoria ca where ca.campo_modificado = 'personas.tipo_vinculo' order by ca.created_at desc; — cruzar cada fecha contra periodos_pl…

**ARREGLO**

El arreglo de fondo es el mismo que la 0261 hizo con el régimen de pensión: darle fecha al vínculo (una tabla asignaciones_vinculo versionada, leída con el mismo `coalesce(tramo vigente al cierre, columna plana)` y con `fn_fecha_en_periodo_pagado` en el guard). El parche de hoy, si eso no entra ahora, es que fn_set_tipo_vinculo lance la misma excepción que ya lanza para la persona cesada cuando esa persona tenga jornadas o filas de planilla_pagada_detalle en un periodo pagado — acotado a la persona, exactamente como hizo la 0037 con fn_set_fecha_ingreso para no congelar el campo para todo el e…

**COSTO** · parche acotado: chico (un `if exists` de seis líneas, con su prueba). Versionar el vínculo: mediano, y arrastra a fn_planilla_calcular, a las cuatro funciones de provisiones y a la pantalla de Equipo.

---

### [P2] La boleta que se entrega no lee la foto del pago: la recalcula en vivo y puede imprimir otro número

**DÓNDE** · `apps/web/app/(admin)/admin/planilla/boleta/page.tsx:154 · enlazada desde apps/web/app/(admin)/admin/planilla/page.tsx:559 · supabase/migrations/0105_complemento_por_productividad.sql (fn_proyeccion_periodo)`

**EJE** · negocio  ·  **ORIGEN** · eje · trazabilidad

**REGLA QUE INCUMPLE** · CLAUDE.md — «Lo que registra este sistema alimenta el pago. Un error acá no es un bug de pantalla: es plata mal pagada a una persona real». La foto congelada de la 0096 existe precisamente para que lo pagado quede fijo; el documento que se entrega debería salir de ella.

**QUÉ PASA**

La boleta se carga con `supabase.rpc("fn_proyeccion_periodo", { p_periodo_id: periodoId })`, y esa función hace `v_out := fn_planilla_calcular(v_p.fecha_ini, v_p.fecha_fin, v_p.id);` — cálculo en vivo. Nunca consulta `planilla_pagada_detalle`. El sello que imprime dice `Pagada el DD/MM/AAAA`, que es un hecho cierto sobre la fecha y una promesa falsa sobre el monto. El propio archivo lo tiene escrito en un comentario (líneas 357-362): «fn_proyeccion_periodo recalcula en vivo y no lee la foto congelada de la 0096».

**SE ROMPE ASÍ**

Una integrante pide su boleta del mes pasado en agosto; se la imprimen y dice S/1 949.62 con el sello «Pagada el 28/07/2026». A su cuenta entraron S/1 836.62. Ahora hay un documento firmado por CAYLA que dice que le debían S/113 más, y la única prueba de lo contrario es una tabla que ella no ve. Ante SUNAFIL el papel es el que pesa: la empresa está aportando la prueba de su propio incumplimiento. Y al revés vale igual — el número puede salir más bajo y esconder plata que sí se pagó.

**YA OCURRIÓ** · El mecanismo está vivo hoy y no depende de ningún descuido: basta reimprimir una boleta después de cualquier edición retroactiva. No consta que se haya reimpreso una boleta desfasada. Vale la pena decirlo en la primera línea: hoy no ha costado nada, y sigue costando nada hasta el día que alguien rei…

**ARREGLO**

Para un periodo con estado 'pagado', la boleta debe leer la última versión de `planilla_pagada_detalle` —la columna `fila` guarda el jsonb completo, con `movimientos` y `feriados_detalle`, así que la pantalla no necesita cambiar de forma— y no fn_proyeccion_periodo. Añadir una RPC `fn_boleta_pagada(p_periodo_id, p_persona_id)` que devuelva `fila` de la versión vigente. Dejar el cálculo en vivo solo para los periodos abiertos, con el sello «Provisional» que ya existe. Y, si además existe una foto anterior distinta, imprimir la versión y la fecha del repago.

**COSTO** · Una migración pequeña (una RPC de lectura) y un cambio de origen de datos en boleta/page.tsx. Un día. Se puede probar contra la foto que ya existe en producción sin tocar ningún cálculo.

---

### [P2] Si IndexedDB falla y no hay red, la marca se pierde y la pantalla dice «Listo»

**DÓNDE** · `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(terminal)/terminal/marcar/page.tsx:409-416,431-435,450-460`

**EJE** · negocio  ·  **ORIGEN** · eje · terminal

**REGLA QUE INCUMPLE** · La regla que este mismo archivo se escribió a sí mismo (page.tsx:366-371): «Es la única forma en que este sistema pierde una marca… Callarse es lo peor que se puede hacer acá». Hay una segunda forma y esa sí se calla.

**QUÉ PASA**

`encolarMarcaje` está envuelto en un try/catch que solo pone `encolada = false` y sigue. El comentario dice que el envío se intenta igual — pero el envío está dentro de `if (navigator.onLine)`. Si el navegador se sabe sin conexión Y el almacén local falló, no se manda nada, no se guarda nada, y el mensaje que se compone no mira `encolada` en ningún momento: como no hubo rechazo del servidor, sale el texto verde «Listo — Entrada de X (se sincronizará cuando vuelva la conexión)». No hay ninguna conexión que la vaya a sincronizar porque la marca no existe en ninguna parte.

**SE ROMPE ASÍ**

La Mac mini de una sede se queda sin espacio en disco, o el navegador entra en un modo donde IndexedDB rechaza escrituras. Ese día la sede está además con el internet caído —que es cuando la cola importa—. Cada persona marca, ve «Listo», y se va. Al final del turno no hay ni una marca: ni en la base ni en la cola. Nadie se enteró, porque la pantalla dijo exactamente lo mismo que dice un día bueno.

**YA OCURRIÓ** · No se puede saber desde acá ni desde la base: por definición estas marcas no dejan rastro en ningún sitio. La forma de detectarlo hacia adelante es el arreglo.

**ARREGLO**

Que el mensaje mire `encolada`. Si la marca no se guardó ni se envió, tiene que salir el cartel rojo de alerta con el mismo tono que el rechazo del servidor —«tu marca NO quedó registrada, avisa a tu encargada ahora»—, que ya existe tres líneas más arriba para el caso de la ficha del terminal. Es un `||` en la condición de `rechazadaPorElServidor` (o mejor, una tercera variable que distinga los tres finales: guardada, rechazada, perdida). Y de paso, intentar el envío aunque `navigator.onLine` sea false cuando no se pudo encolar: `onLine` miente a menudo y ahí no hay nada que perder.

**COSTO** · Chico. Cuatro o cinco líneas en confirmarMarcaje, sin migración y sin tocar la base.

---

### [P2] Un contrato a plazo fijo que venció y no se renovó produce faltas injustificadas todos los días hasta que alguien registre el cese

**DÓNDE** · `/Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0256_una_persona_puede_ver_sus_propias_faltas.sql:60-70 (CTE `medibles` de fn_faltas), y los `medibles` equivalentes de fn_faltas_resumen y fn_falta_contadores.`

**EJE** · negocio  ·  **ORIGEN** · eje · faltas

**REGLA QUE INCUMPLE** · CLAUDE.md — «Los falsos positivos son el peor error». Y el encabezado de la propia 0231, que reconoce fecha_fin_contrato como el hecho con consecuencia legal: art. 77 de la LPCL, «si la colaboradora continúa laborando después de la fecha de vencimiento del plazo estipulado». Si no continúa, la relación terminó ese día y no debe asistencia.

**QUÉ PASA**

El filtro de personas medibles es `pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false` y la ventana arranca en `greatest(p_desde, m.fecha_ingreso)`. Nadie mira fecha_fin_contrato: `select proname from pg_proc where prosrc ilike '%fecha_fin_contrato%'` devuelve exactamente cuatro nombres —fn_contratos_desnaturalizados, fn_contratos_por_vencer, fn_documentos_tablero, fn_set_fin_contrato— y ninguno pertenece al motor de faltas. Como fn_cesar_persona prohíbe una fecha de cese futura (`if p_fecha_cese > v_hoy then raise exception`), siempre existe un tramo entre el último día de contrato y el día en que alguien registra la baja. En ese tramo la persona ya no viene —cumplió …

**SE ROMPE ASÍ**

Medido en local dentro de BEGIN … ROLLBACK (ROLLBACK ejecutado). Persona con fecha_ingreso 2026-08-01, fecha_fin_contrato 2026-08-07, horario lunes a viernes, jornadas completas y puntuales hasta el 07-ago inclusive, sin marcajes después. Al 17-ago: fn_faltas('2026-08-08','2026-08-17') devuelve cinco inasistencias injustificadas (10, 11, 12, 13 y 14 de agosto). fn_faltas_resumen('2026-08-17') la deja en consecutivas=5, en_30=5, en_180=5, nivel = ROJO. Y fn_expediente_generar_falta() no rebota: g…

**YA OCURRIÓ** · Hoy no cuesta nada y no puedo comprobar si ya pasó: no consulto producción. Es un riesgo latente, no plata perdida. Se cierra solo en cuanto alguien registra el cese, porque entonces estado pasa a 'inactivo' y la persona desaparece de las tres funciones; el daño solo se materializa si alguien actúa …

**ARREGLO**

Cortar la ventana de días en fecha_fin_contrato cuando no hay ningún marcaje posterior — que es la misma pregunta que ya responde fn_contratos_desnaturalizados. En el generate_series de fn_faltas (y en los de fn_faltas_resumen y fn_falta_contadores), sustituir `least(p_hasta, hoy-1)` por `least(p_hasta, hoy-1, coalesce(case when exists (select 1 from marcajes m where m.persona_id = m2.id and m.anulada_at is null and coalesce(m.fecha_jornada,(m.timestamp_marca at time zone 'America/Lima')::date) > m2.fecha_fin_contrato) then null else m2.fecha_fin_contrato end, 'infinity'::date))`. Si siguió vi…

**COSTO** · Una migración que toca tres funciones con la misma expresión. Eso es lo caro: fn_faltas_resumen y fn_falta_contadores repiten la cascada de días entera, así que hay que editarlas las tres o —mejor— unificar antes la ventana. Con pruebas pgTAP del caso «venció y no volvió» frente a «venció y siguió viniendo», medio día.

---

### [P2] Next.js 16.2.10 en producción con 17 advisories high; el parche es 16.2.11

**DÓNDE** · `apps/web/package.json (dependencies.next = "16.2.10")`

**EJE** · seguridad  ·  **ORIGEN** · mecánica

**REGLA QUE INCUMPLE** · falta un criterio — CLAUDE.md no fija una política de parcheo de dependencias, y la red de seguridad (pre-push + tests.yml) no mira `pnpm audit`

**QUÉ PASA**

El panel donde se ven sueldos, DNI y cuentas bancarias corre sobre una versión de Next con fallas ya publicadas y ya corregidas. Entre ellas, «Cache confusion of response bodies»: una respuesta puede quedar cacheada y servirse a quien no le tocaba — en este panel eso es la boleta de otra persona.

**SE ROMPE ASÍ**

Una encargada de AQP abre /admin/equipo; una respuesta cacheada de una pantalla de DO se le sirve a ella. No hace falta un atacante: basta la CDN. Las tres SSRF y el bypass de middleware NO aplican acá (no existe apps/web/middleware.ts y el despliegue es Vercel, no un servidor propio) — la que aplica sin condiciones es la de caché.

**YA OCURRIÓ** · indeterminado. No hay forma de detectarlo desde la base: es un efecto de la capa de caché de Vercel, no deja rastro en Postgres. Latente desde que se subió 16.2.10.

**ARREGLO**

DECIDÍ: subir `next` de 16.2.10 a 16.2.11 en apps/web/package.json — es un parche, mismo minor, sin cambios de API. DESCARTÉ actualizar todo el árbol de dependencias porque los otros highs no son alcanzables (ver el hallazgo de xlsx, y postcss/brace-expansion/nanoid solo corren en build). SE ROMPE SI: @sentry/nextjs ^10.68.0 fija un rango de next incompatible — hay que correr `pnpm build` después, que hoy pasa en 15.8 s y sirve de control.

**COSTO** · Bajo. Un cambio de una línea, `pnpm install`, `pnpm build`, y el despliegue normal por ./scripts/desplegar.sh prod.

---

### [P2] Cualquiera con sesión puede borrar el único aviso de que un mes pagado dejó de cuadrar, y no queda rastro

**DÓNDE** · `supabase/migrations/0188_el_resellado_del_dia_entra_al_repositorio.sql (fn_resellar_dia) · supabase/migrations/0084_el_sello_se_levanta_cuando_el_dia_cuadra.sql (fn_levantar_sello_si_el_dia_cuadra)`

**EJE** · seguridad  ·  **ORIGEN** · eje · trazabilidad

**REGLA QUE INCUMPLE** · CLAUDE.md — «Toda edición manual deja rastro en correcciones_auditoria con motivo obligatorio» y «Guards SECURITY DEFINER null-safe: siempre `if fn_es_admin_o_lider() is not true`». Estas dos funciones son SECURITY DEFINER y no tienen guard de ninguna clase.

**QUÉ PASA**

Las dos son `security definer`, escriben `update marcajes set estado_revision = …`, no comprueban quién llama y tienen EXECUTE concedido a `authenticated`. Ese sello es el mecanismo entero de la 0207: cuando una marca llega tarde a un mes ya pagado, la marca entra (append-only, correcto) y se sella `pendiente_revision` para que el día salga en fn_dias_por_revisar y alguien mire. Es el ÚNICO aviso de que el número pagado ya no coincide con sus marcas. Se borra con una llamada.

**SE ROMPE ASÍ**

La persona a la que le conviene que el día no se revise es exactamente la que tiene sesión y conoce su propio persona_id (`fn_persona_actual_id()`). Un mes pagado con una hora de almuerzo que llegó tarde vale S/12 y desaparece de la cola sin dejar una sola fila de auditoría. No hace falta mala fe: basta una integración o un script que llame a la función «para limpiar» y la cola de Correcciones se vacía sola.

**YA OCURRIÓ** · No consta ningún uso. El riesgo es latente y hoy no ha costado nada. Pero la exposición es permanente y no depende de que alguien se equivoque: es un permiso concedido.

**ARREGLO**

Añadir a las dos el guard estándar del repo, `if fn_es_admin_o_lider() is not true then raise exception …`, o —mejor— revocarles el EXECUTE a `authenticated` e inscribirlas en `funciones_nunca_para_authenticated` con su motivo, como ya se hizo con fn_planilla_congelar: hoy solo las llaman otras funciones SECURITY DEFINER (fn_agregar_marcaje, fn_corregir_marca, fn_anular_marcaje, fn_corregir_marcaje), que no necesitan el permiso del cliente. Y, aparte: que levantar un sello puesto por la 0207 —el de un mes ya pagado— deje fila en correcciones_auditoria, porque ese sello no es ruido operativo, e…

**COSTO** · Una migración de veinte líneas: REVOKE, insert en funciones_nunca_para_authenticated y una prueba pgTAP que llame como 'authenticated'. Una hora. Ningún riesgo de cambiar un monto.

---

### [P2] Una integrante escribe en marcajes de otra sede: fn_resellar_dia no pregunta quién llama

**DÓNDE** · `supabase/migrations/0188_el_resellado_del_dia_entra_al_repositorio.sql (fn_resellar_dia, la vigente según donde-vive.sh; md5 en base ba93483fe205b7dfa41e1bb86933f236) y fn_levantar_sello_si_el_dia_cuadra`

**EJE** · seguridad  ·  **ORIGEN** · eje · rls

**REGLA QUE INCUMPLE** · CLAUDE.md: «Los marcajes son la fuente de verdad, y son append-only» · «Toda edición manual deja rastro en correcciones_auditoria con motivo obligatorio» · «Nunca se corrige una jornada por debajo».

**QUÉ PASA**

Las dos son SECURITY DEFINER, están concedidas a authenticated y hacen `update marcajes set estado_revision = …` filtrando por el p_persona_id y la p_fecha que manda quien llama. No llaman a fn_verificar_corrector, ni a fn_es_admin_o_lider, ni miran auth.uid(). Tampoco escriben en correcciones_auditoria. Es lo contrario del resto del módulo: fn_agregar_marcaje, fn_anular_marcaje, fn_corregir_marcaje, fn_set_turno y fn_registrar_ausencia sí empiezan por fn_verificar_corrector, y ese guard hace justo lo que hay que hacer (admin y lider_do a cualquiera; supervisor_sede solo a su sede, ni a sí misma, ni a un admin).

**SE ROMPE ASÍ**

`pendiente_revision` es lo que pone un día en la cola de «días por revisar» de Correcciones (fn_dias_por_revisar). Quien quiera que un día suyo deje de aparecerle a su encargada llama a fn_resellar_dia sobre su propio id y esa fecha; si el día ya cuadra por dentro, el sello se levanta y el día desaparece de la cola sin que nadie lo haya revisado. Al revés también: llamándola sobre días de terceros se puede llenar la cola de la encargada de otra sede con días que nadie tocó. En los dos casos no q…

**YA OCURRIÓ** · No tengo evidencia de que haya pasado. No puedo descartarlo tampoco, y esa es parte del problema: como estas dos funciones no escriben auditoría, no hay dónde mirarlo. La 0188 es de agosto de 2026.

**ARREGLO**

El mismo revoke que el hallazgo anterior: ninguna de las dos se llama desde el cliente (en apps/web solo aparecen citadas en un comentario de lib/terminal/offline-db.ts, «y a esa solo la llaman las correcciones manuales» — que es exactamente el diseño esperado). Si algún día alguna tuviera que llamarse desde una pantalla, entonces la primera línea del cuerpo es `perform fn_verificar_corrector(p_persona_id);`, igual que sus vecinas.

**COSTO** · Dos líneas en la misma migración de revokes del hallazgo anterior.

---

### [P2] La encargada de sede puede reescribir la cuenta bancaria de su equipo y no queda ningún historial

**DÓNDE** · `/Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0061_datos_personales.sql:61-89 (guard y upsert de fn_set_datos_personales) · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/datos-personales/page.tsx:274`

**EJE** · seguridad  ·  **ORIGEN** · eje · pii

**REGLA QUE INCUMPLE** · CLAUDE.md: «Toda edición manual deja rastro en correcciones_auditoria con motivo obligatorio» y «Lo que registra este sistema alimenta el pago. Un error acá no es un bug de pantalla: es plata mal pagada a una persona real.»

**QUÉ PASA**

El guard de fn_set_datos_personales autoriza a admin, a líder DO, a la persona sobre sí misma y —tercera rama— a la encargada de la sede de esa persona. La escritura es un `insert … on conflict do update` que pisa entidad_bancaria y numero_cuenta con lo que venga, y lo único que deja es actualizado_por y actualizado_at, dos columnas que se sobrescriben en la misma operación. El valor anterior no se guarda en ninguna parte. No hay motivo obligatorio, no hay fila en correcciones_auditoria, no hay tabla de historial.

**SE ROMPE ASÍ**

El encabezado de la 0061 documenta la decisión de Felipe sobre la LECTURA —«admin/líder DO ven todo; la encargada de sede ve la ficha de SU sede»— y hasta señala el número de cuenta como el campo más sensible, con un plan por si algún día se le quiere ocultar a la encargada. Pero es un párrafo sobre quién VE. La escritura entró por la puerta de al lado: fn_set_datos_personales trata los diecinueve campos de la ficha como un bloque único, así que el permiso que se pensó para que la encargada comp…

**YA OCURRIÓ** · No consta que haya pasado, y hoy no cuesta nada: es una capacidad abierta, no un daño hecho. Lo que la hace P1 es que si pasara no habría cómo demostrarlo — no queda el valor anterior, así que ni siquiera se podría distinguir un fraude de un tipeo. La forma de enterarse sería que alguien reclame que…

**ARREGLO**

Sacar el par entidad_bancaria/numero_cuenta de fn_set_datos_personales y darle función propia con guard de admin/líder (el mismo criterio con el que fn_set_salario y fn_set_sueldo_base_legal ya están cerrados), o mantener el permiso y agregar una tabla de historial con motivo obligatorio, al estilo de correcciones_auditoria. Si se elige lo segundo conviene que el historial cubra la ficha entera, no solo el banco: la dirección y el celular también son el canal por el que se notifica un procedimiento disciplinario.

**COSTO** · Una migración corta y un ajuste en datos-personales/page.tsx. La versión con historial es una tabla más y un insert dentro de la misma función.

---

## 6 · P3 — ergonomía y forma

**39 hallazgos**, agrupados y al final. Ninguno cambia un número ni expone un dato.

| # | Hallazgo | Dónde |
|---|---|---|
| 1 | Las columnas de plata de personas se pueden escribir sin pasar por los fn_set_* que las protegen — incluida la que bloquea tocar u… | `supabase — policy personas_update_admin_lider sobre las 38 columnas de personas; los guard…` |
| 2 | El archivo que el CLAUDE.md designa como fuente única de «qué le tocaba ese día» declara en su encabezado una cascada que el backe… | `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/lib/admin/jornada-esperada.ts:9-14 y :1…` |
| 3 | La pantalla de Política Salarial escribe «America/Lima» a mano tres veces, y es la que imprime el documento que el equipo firma | `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/politica-salarial/pag…` |
| 4 | Dos pantallas vuelven a declarar quién es DO en vez de preguntárselo a `permisos.ts` | `apps/web/app/(admin)/admin/normas/page.tsx:38 y :147` |
| 5 | Diez comparaciones de rol contra literal fuera de `permisos.ts`, para dos preguntas que el módulo no nombra | `apps/web/app/(admin)/admin/turnos/page.tsx:630` |
| 6 | El rol se compara contra un literal en once sitios fuera de permisos.ts, y el mismo predicado tiene dos nombres | `apps/web/app/(admin)/admin/horarios/page.tsx:113` |
| 7 | Diez comparaciones de `rol` contra literales fuera de permisos.ts, y la función que falta es la de encargada | `apps/web/app/(admin)/admin/horarios/page.tsx:113` |
| 8 | «America/Lima» escrito a mano tres veces en la pantalla de política salarial | `apps/web/app/(admin)/admin/politica-salarial/page.tsx:66, 77 y 242` |
| 9 | Tres «America/Lima» escritos a mano en la pantalla de la política salarial oficial | `apps/web/app/(admin)/admin/politica-salarial/page.tsx:66, :77, :242` |
| 10 | El recargo del sobretiempo tiene dos versiones, y la que parece la autoritativa no la usa nadie | `packages/shared/src/jornada.ts:40-45 (RECARGO_SOBRETIEMPO) contra supabase/migrations/0263…` |
| 11 | Quedó viva la versión vieja de fn_educacion_cerrar, sin candado de periodo pagado, y vuelve ambigua toda llamada de dos argumentos | `supabase/migrations/0136_la_pantalla_de_educacion_con_su_comprobante.sql:197-220 (la de 2 …` |
| 12 | El envío del tap y la cola periódica pueden mandar el MISMO client_uuid a la vez, y la persona ve en rojo que no quedó registrada … | `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(terminal)/terminal/marcar/page.tsx…` |
| 13 | Un día con marcajes reales dentro de un periodo ya pagado no genera fila en jornadas, y fn_faltas lo cuenta como inasistencia inju… | `/Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0256_una_persona_puede_ver_s…` |
| 14 | Un `useMemo` de Incidencias documenta una salvaguarda por sede que sus dos ramas no aplican | `apps/web/app/(admin)/admin/incidencias/page.tsx:616-624` |
| 15 | El área base se llama «al cliente» mientras todo el resto del sistema dice «clienta» | `supabase/migrations/0022_areas_catalogo.sql:22 (dato vivo en la tabla `areas`)` |
| 16 | La política salarial publicada con acuse de recibo dice «jefatura», dos veces | `apps/web/lib/politica-salarial.ts:426` |
| 17 | La pantalla de Turnos imprime el identificador de la base junto al nombre de pantalla | `apps/web/app/(admin)/admin/turnos/page.tsx:785` |
| 18 | El selector de sede se queda pegado: tras atender a quien viene de otra sede, el terminal deja de mostrar a su propio equipo | `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(terminal)/terminal/marcar/page.tsx…` |
| 19 | «Nuevo PIN» mata el PIN anterior al primer clic, sin preguntar, y muestra el reemplazo fuera de la pantalla | `apps/web/app/(admin)/admin/equipo/page.tsx:1501 (el boton), :660-670 (la funcion), :1304 (…` |
| 20 | En el terminal —que se toca con el dedo— los controles que deciden el TIPO de salida son texto de 14px sin area tactil | `apps/web/app/(terminal)/terminal/marcar/components.tsx:186 (Otra salida), :128, :191, :338…` |
| 21 | Politica salarial —la pantalla que TODO el equipo firma— esta pintada fuera de la marca: 70 clases de la paleta de Tailwind en un … | `apps/web/app/(admin)/admin/politica-salarial/page.tsx (70 usos fuera de paleta)` |
| 22 | Accesibilidad minima: 222 encabezados de tabla sin `scope`, seis de ocho ventanas sin identidad de ventana ni salida por Escape, y… | `apps/web/app/globals.css (no hay ninguna regla `:focus-visible` en las 121 lineas)` |
| 23 | El espejo a Google Sheets pagina sin orden estable — es la copia de traerTodo a la que se le cayó la única protección por la que t… | `apps/web/app/api/espejo/route.ts:26-45 (pageAll y sus cuatro llamadas), frente a apps/web/…` |
| 24 | El freno del doble pago no comparte cerrojo con la liquidación: dos operaciones simultáneas se lo saltan | `supabase/migrations/0255_marcar_una_liquidacion_pagada_no_revienta_por_una_nota_corta.sql …` |
| 25 | fn_provisiones es cuadrática en el número de personas: cinco laterales reescanean el CTE completo una vez por cada una | ``public.fn_provisiones(p_as_of date)` — la versión vigente en la base local. Los cinco lat…` |
| 26 | Tres índices duplican byte por byte a un unique que ya existe sobre las mismas columnas | ``public.turnos` → `idx_turnos_persona_fecha` duplica `turnos_persona_id_fecha_key`. `publi…` |
| 27 | La imputación de falta grave deja de nombrar las sanciones previas —y dice que «constan en el legajo»— cuando la consulta que las … | `apps/web/app/(admin)/admin/disciplina/memo/[id]/page.tsx:178-186 (la consulta), :304-323 y…` |
| 28 | Exportar asistencia arranca con la fecha de UTC: desde las 7 de la tarde de Lima el CSV para el contador sale vacío y se descarga … | `apps/web/app/(admin)/admin/exportar/page.tsx:9-11 y :14-15` |
| 29 | El memo disciplinario que se imprime y se entrega en mano dice «el colaborador» | `apps/web/app/(admin)/admin/disciplina/memo/[id]/page.tsx:456` |
| 30 | La bonificación extraordinaria de la Ley 30334 está clavada al 9 % dentro de la gratificación trunca | `supabase/migrations/0196_tres_puertas_en_vez_de_una_para_los_beneficios.sql:270 y :281 (fn…` |
| 31 | La RMV está versionada, pero el guardián que impide que la escala salarial caiga bajo el mínimo compara contra su propia copia a m… | `apps/web/lib/rangos.ts:95` |
| 32 | El candado de mes pagado está en unas RPC de plata y falta en otras, sin criterio escrito | `Todas las que escriben tablas que fn_planilla_calcular lee. CON candado: fn_set_salario, f…` |
| 33 | `puedeVerIdentidad` promete que la cuenta bancaria es solo de DO; las tres capas se la dan a la encargada | `packages/shared/src/permisos.ts:49-55` |
| 34 | Trece funciones SECURITY DEFINER vivas usan la forma `if not fn_…()` que CLAUDE.md prohíbe | `En la base local (que coincide con el esquema de las migraciones): fn_expediente_adjuntar,…` |
| 35 | La ruta de ejemplo de Sentry, que lanza un error a propósito, está desplegada en producción | `apps/web/app/api/sentry-example-api/route.ts` |
| 36 | fn_auto_cierre no comprueba quién la llama y `authenticated` puede ejecutarla | `supabase/migrations/0203_lo_que_se_congela_al_pagar_se_descongela_al_reabrir.sql (fn_auto_…` |
| 37 | TRUNCATE está concedido a anon y a authenticated sobre todas las tablas, y la RLS no cubre TRUNCATE | `Concesiones a nivel de esquema en supabase/migrations (patrón `grant all on all tables in …` |
| 38 | La foto del DNI no vive en ningún bucket: es un enlace de Drive escrito a mano en un campo de texto | `/Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0061_datos_personales.sql:29…` |
| 39 | El script del espejo a Sheets que está en el repo sigue pidiendo que se pegue la llave de servicio en Google Apps Script | `/Users/archicaylo/Proyectos/cayla-dynamic/scripts/espejo-sheets.gs:1-45` |

<details><summary>Ficha de cada P3</summary>

**Las columnas de plata de personas se pueden escribir sin pasar por los fn_set_* que las protegen — incluida la que bloquea tocar un periodo ya pagado**  
`supabase — policy personas_update_admin_lider sobre las 38 columnas de personas; los guardianes que quedan salteables viven en fn_set_fecha_ingreso, fn_set_sueldo_base_legal, fn_set_salario; el camino abierto está en apps/web/app/(admin)/admin/equipo/page.tsx:422-431 y :664`  
HOY NO CUESTA NADA: ninguna pantalla escribe esas columnas por el camino corto — solo se usan cinco (nombres, apellidos, sede_base_id, rol, email, pin_hash) y ninguna toca el cálculo del pago. Lo que está abierto es la puerta: la fecha de ingreso, el sueldo base legal, en_planilla, sueldo_fijo, personal_direccion y los devenga_* se pueden escribir desde el navegador sin que corra ninguna de las validaciones que se escribieron justamente para ellas.  
_Arreglo:_ DECIDÍ el camino de las RPC: reducir personas_update_admin_lider a las columnas que hoy de verdad se escriben desde la pantalla, con grants por columna (revoke update on personas from authenticated; grant update (nombres, apellidos, sede_base_id, email) on personas to authenticated) y mover pin_hash y rol a RPC (rol ya va en el hallazgo anterior). Es el correcto porque las validaciones ya están es…

**El archivo que el CLAUDE.md designa como fuente única de «qué le tocaba ese día» declara en su encabezado una cascada que el backend no tiene**  
`/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/lib/admin/jornada-esperada.ts:9-14 y :119-120, contra fn_recalcular_jornada; tercera copia en /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/correcciones/page.tsx:49-64 y :216`  
El encabezado de jornada-esperada.ts afirma que espeja fn_recalcular_jornada y que el tercer escalón de la cascada es dias_laborables. fn_recalcular_jornada no tiene ese tercer escalón: en la rama legacy toma hora_entrada a secas. O sea que el espejo y el original discrepan, y el que está bien es el espejo — pero quien lea el encabezado creerá que el backend ya filtra por dias_laborables y no lo va a comprobar, que es justo lo que el archivo promete evitar. Aparte, la tercera copia (calcularEsperado, en la pantalla de Correcciones) tampoco filtra, y ni siquiera puede: su consulta no trae la co…  
_Arreglo:_ DECIDÍ separar las dos mitades. La barata y sin riesgo, ya: corregir el encabezado de jornada-esperada.ts para que describa el backend real —decir que fn_faltas filtra por dias_laborables y que fn_recalcular_jornada y fn_auto_cierre NO, y que esa diferencia es un defecto abierto, no el diseño—. Un comentario que miente sobre el backend es peor que no tener comentario, porque ahorra la comprobación…

**La pantalla de Política Salarial escribe «America/Lima» a mano tres veces, y es la que imprime el documento que el equipo firma**  
`/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/politica-salarial/page.tsx:66, :77 y :242`  
Hoy no está pagando de más ni de menos a nadie: las tres copias dicen la zona correcta, así que las fechas que imprime son las de Lima. Es un riesgo latente, no una pérdida en curso. Lo que rompe es la garantía: son las únicas tres apariciones del literal fuera de fecha-lima.ts en todo el panel, y una de ellas fecha el documento de política salarial —el que se publica versionado y con acuse de recibo del equipo—. El día que algo del huso tenga que cambiar, estas tres no se van a enterar, y la que fecha un documento firmado es la peor candidata a quedarse atrás.  
_Arreglo:_ DECIDÍ importar TZ_LIMA en las tres, que es lo que ya hacen reloj.tsx y personas/[id]/page.tsx. Y como esta clase de deriva se repone sola —el CLAUDE.md cuenta que llegaron a ser 32 copias—, lo que de verdad la cierra es una comprobación en scripts/hooks/pre-push que falle si el literal aparece en un archivo que no sea packages/shared/src/fecha-lima.ts ni su prueba: hoy el hook cuida numeración, t…

**Dos pantallas vuelven a declarar quién es DO en vez de preguntárselo a `permisos.ts`**  
`apps/web/app/(admin)/admin/normas/page.tsx:38 y :147 · apps/web/app/(admin)/admin/politica-salarial/page.tsx:39, :179 y :220 (contra apps/web/app/(admin)/admin/nav.tsx:20-22)`  
Hay tres archivos que responden «¿quién es Desarrollo Organizacional?». El menú lo consulta; las dos pantallas del Reglamento Interno y de la política salarial lo vuelven a declarar a mano. Son las dos pantallas con obligación legal detrás —la Ley 30709 obliga a informar la política salarial y a poder probarlo; el Reglamento hay que entregarlo y guardar el acuse—, y son justo las que quedaron fuera del módulo.  
_Arreglo:_ DECIDÍ: la correcta es `nav.tsx`. No solo porque cumple la regla, sino porque escribió el motivo en un comentario de una línea que es la política entera del repo: «el menú no vuelve a decidir quién es DO, solo lo consulta». En `normas/page.tsx` y `politica-salarial/page.tsx` se borra la constante local y se importa. Y como la pregunta que las dos hacen es «¿puedo publicar y ver los acuses?», lo co…

**Diez comparaciones de rol contra literal fuera de `permisos.ts`, para dos preguntas que el módulo no nombra**  
`apps/web/app/(admin)/admin/turnos/page.tsx:630 · incidencias/page.tsx:214, :618 · objetivos/page.tsx:94, :95, :321 · dashboard/page.tsx:276 · horarios/page.tsx:113 · reporte-sede/page.tsx:183 · correcciones/page.tsx:366 · apps/web/app/api/admin/cuentas/route.ts:129, :150, :334`  
El módulo `permisos.ts` cubre bien seis preguntas y las pantallas de plata las usan sin excepción. Pero hay dos preguntas frecuentes que no nombra —«¿esta persona cuenta como encargada?» y «¿sobre quién puede actuar una encargada?»— y por eso diez sitios las contestan escribiendo `"supervisor_sede"` a mano. No es un problema de estilo: es la causa raíz del hallazgo P1 de esta lista, donde dos de esas respuestas a mano salieron distintas.  
_Arreglo:_ DECIDÍ: agregar a `packages/shared/src/permisos.ts` las dos funciones que faltan —`esEncargada(rol, esEncargadaPiso)` y `puedeCorregirA(rolQuienLlama, idQuienLlama, rolObjetivo, idObjetivo)`, esta última espejando `fn_verificar_corrector` igual que `escalafon.ts` espeja el escalafón de cuentas— con sus pruebas en vitest, y reemplazar las diez comparaciones. Las tres de `/api/admin/cuentas` (`.eq("…

**El rol se compara contra un literal en once sitios fuera de permisos.ts, y el mismo predicado tiene dos nombres**  
`apps/web/app/(admin)/admin/horarios/page.tsx:113 · correcciones/page.tsx:366 · turnos/page.tsx:630 · dashboard/page.tsx:276 · reporte-sede/page.tsx:183 · incidencias/page.tsx:618 · objetivos/page.tsx:94-95 · politica-salarial/page.tsx:39 · normas/page.tsx:38 · app/api/admin/cuentas/route.ts:334`  
La pregunta «¿esta persona es una encargada, o sea alcance limitado a su sede?» está escrita a mano en nueve pantallas, y la pregunta «¿esta persona es de Desarrollo Organizacional?» está escrita a mano en dos más como una lista de roles copiada. permisos.ts existe justamente para esto y ya exporta las dos respuestas —puedeOperarEquipo, puedeVerTodasLasSedes, ROLES_DO— pero ninguna de las once las usa. Y el mismo predicado se llama esSupervisor en dos pantallas y esEncargada en tres: dos nombres para lo mismo, uno de ellos con la palabra que el CLAUDE.md prohíbe.  
_Arreglo:_ DECIDÍ: agregar a permisos.ts una función de ALCANCE con el nombre del vocabulario —esAlcanceDeSuSede(rol), que es puedeOperarEquipo(rol) && !puedeVerTodasLasSedes(rol)— y reemplazar los nueve literales; los dos `const DO` se cambian por el ROLES_DO que ya se exporta. DESCARTÉ llamarla esEncargada porque permisos.ts declara en su encabezado que sus funciones se nombran por lo que autorizan y no po…

**Diez comparaciones de `rol` contra literales fuera de permisos.ts, y la función que falta es la de encargada**  
`apps/web/app/(admin)/admin/horarios/page.tsx:113 · correcciones/page.tsx:366 · incidencias/page.tsx:618 · objetivos/page.tsx:94,95,321 · turnos/page.tsx:630 · reporte-sede/page.tsx:183 · dashboard/page.tsx:276 · apps/web/app/api/admin/cuentas/route.ts:334`  
El día que ese rol se renombre en la base —CLAUDE.md ya deja escrito que `supervisor_sede` es un nombre heredado que en pantalla siempre es «encargada»— hay que acordarse de diez archivos. El que se olvide no falla ruidoso: deja de reconocer a la encargada y su filtro por sede se comporta como si no fuera nadie.  
_Arreglo:_ DECIDÍ: agregar a permisos.ts una función de ALCANCE con el nombre de lo que autoriza —`soloVeSuSede(rol)`, complemento explícito de `puedeVerTodasLasSedes`— y reemplazar los 10 sitios. El propio permisos.ts ya distingue permiso de alcance en su comentario, así que es el hueco que quedó. DESCARTÉ exportar una constante ROL_ENCARGADA: mueve el literal de sitio, no lo elimina, y permisos.ts dice exp…

**«America/Lima» escrito a mano tres veces en la pantalla de política salarial**  
`apps/web/app/(admin)/admin/politica-salarial/page.tsx:66, 77 y 242`  
La pantalla que publica la política salarial —la que lleva acuse de recibo del equipo— fecha sus documentos con una copia propia del huso horario en vez de la del sistema. Hoy dice lo mismo; el problema es que ya no hay una sola versión.  
_Arreglo:_ DECIDÍ: importar TZ_LIMA en politica-salarial/page.tsx y usarlo en las tres llamadas, exactamente como ya lo hace apps/web/components/reloj.tsx. DESCARTÉ agregar una regla de ESLint que prohíba el literal: sería lo correcto a futuro, pero el lint del repo está en rojo (ver el hallazgo anterior) y una regla nueva ahí no la vería nadie — primero se enciende el guardián, después se le agrega trabajo.…

**Tres «America/Lima» escritos a mano en la pantalla de la política salarial oficial**  
`apps/web/app/(admin)/admin/politica-salarial/page.tsx:66, :77, :242`  
La pantalla que publica la política salarial oficial —la versionada, la que el equipo firma con acuse de recibo— arma sus tres formatos de fecha con la zona horaria escrita a mano en vez de pedirle TZ_LIMA a packages/shared. Hoy los cuatro valores coinciden, así que no cambia ninguna fecha impresa. Lo que se pierde es la garantía de que sigan coincidiendo.  
_Arreglo:_ DECIDÍ: importar TZ_LIMA de @cayla-dynamic/shared y reemplazar los tres literales. Tres líneas y un import.
DESCARTÉ mover fechaLarga() y fechaHora() a packages/shared: son formatos de presentación de UNA pantalla, y el CLAUDE.md es explícito sobre qué va en shared —«lo que dos pantallas podrían necesitar responder igual»—. Lo que tiene que estar en un solo sitio es la zona, no el formato.
SE ROMP…

**El recargo del sobretiempo tiene dos versiones, y la que parece la autoritativa no la usa nadie**  
`packages/shared/src/jornada.ts:40-45 (RECARGO_SOBRETIEMPO) contra supabase/migrations/0263_los_veinte_dias_de_descanso_medico_entran_a_la_base.sql:465 (fn_planilla_calcular, la que paga).`  
Los tres números del recargo (2 h de corte, 25 %, 35 %) y el tope de 48 h existen dos veces: como constante exportada en el módulo compartido y como literal dentro del SQL. La que decide la plata es la del SQL. La del módulo no la importa ninguna pantalla ni ninguna función — solo su propio test. Quien vaya a cambiar el recargo va a encontrar primero el módulo que dice ser la única fuente, lo va a cambiar ahí, va a ver el test verde, y no habrá movido un sol.  
_Arreglo:_ O bien un comentario de una línea en jornada.ts diciendo que RECARGO_SOBRETIEMPO es informativo y que la copia que paga es el literal de fn_planilla_calcular (que hay que cambiar a la vez) — como ya hace rangos.ts con «este archivo hay que actualizarlo a mano»; o bien una prueba pgTAP que compare el literal del prosrc contra los valores del módulo, que es lo que evita que se separen de verdad. Lo …

**Quedó viva la versión vieja de fn_educacion_cerrar, sin candado de periodo pagado, y vuelve ambigua toda llamada de dos argumentos**  
`supabase/migrations/0136_la_pantalla_de_educacion_con_su_comprobante.sql:197-220 (la de 2 argumentos, sin candado, con grant a authenticated) · supabase/migrations/0149_la_educacion_con_todas_sus_reglas.sql:429-465 (la de 3 argumentos, con candado)`  
La 0149 creó fn_educacion_cerrar(uuid, date, text default null) con el guard `if fn_educacion_fecha_pagada(p_hasta) is true then raise` y con su rastro en correcciones_auditoria, pero nunca hizo el drop de la de 0136. Las dos siguen en el catálogo de la base, las dos con execute a authenticated, y la vieja no comprueba nada: `update asignaciones_educacion set vigente_hasta = p_hasta` y punto. Acortar ahí la vigencia cambia monto_educacion de un mes ya pagado.  
_Arreglo:_ Una línea en la próxima migración: drop function if exists fn_educacion_cerrar(uuid, date); — que es literalmente lo que la propia 0136 dejó escrito en su bloque de «cómo se revierte», línea 40. Conviene el mismo barrido para el resto de sobrecargas que el catálogo arrastra (fn_set_datos_personales sin p_cuspp, fn_set_meta_cobertura con p_meta), aunque esas dos no tocan el candado de periodo pagad…

**El envío del tap y la cola periódica pueden mandar el MISMO client_uuid a la vez, y la persona ve en rojo que no quedó registrada una marca que sí quedó**  
`/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(terminal)/terminal/marcar/page.tsx:156,409-435,450-460 · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/lib/terminal/sync.ts:10-14,58-64 · fn_registrar_marcaje (0240), el bloque de idempotencia`  
El camino del tap guarda la marca en la cola y SOLO DESPUÉS la envía. Entre esas dos cosas, la sincronización periódica —que arranca en el montaje y corre cada 15 s, más el evento `online`— puede leer esa misma entrada de la cola y enviarla también. Las dos llamadas llevan el mismo client_uuid. La idempotencia de fn_registrar_marcaje es un `select … if found then return` sin `for update` ni `on conflict`, así que las dos ven «no existe» y las dos insertan; `marcajes_client_uuid_key` es UNIQUE, de modo que la segunda recibe un 23505. La función no tiene manejador de excepciones, así que el erro…  
_Arreglo:_ Lo más barato y que además cierra el agujero de raíz: cambiar el `select … if found` por un `insert … on conflict (client_uuid) do nothing returning *`, y si no devuelve fila, leer la existente y retornarla. Con eso las dos llamadas concurrentes devuelven la misma marca y ninguna de las dos falla. Alternativa en el cliente, complementaria: no enviar desde el tap y dejar que la cola sea el único ca…

**Un día con marcajes reales dentro de un periodo ya pagado no genera fila en jornadas, y fn_faltas lo cuenta como inasistencia injustificada**  
`/Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0256_una_persona_puede_ver_sus_propias_faltas.sql:96-99 y :119 (el lateral `presente` de fn_faltas), contra el candado de periodo pagado al inicio de fn_recalcular_jornada.`  
fn_faltas decide «no vino» preguntándole a `jornadas`, que es el resumen derivado, no a `marcajes`, que es la fuente de verdad. Y fn_recalcular_jornada tiene un `return` incondicional en su primera línea ejecutable cuando la fecha cae dentro de un periodo con estado 'pagado'. Es una decisión correcta y bien argumentada para el pago —la marca entra, el número ya pagado no se mueve— pero deja un hueco que no estaba previsto: si ese día no tenía todavía fila en jornadas y las marcas llegan después (cola offline de la Mac mini, o una corrección registrada desde Correcciones), la fila nunca se crea…  
_Arreglo:_ No tocar el candado del pago — está bien puesto y bien argumentado. Cerrar el hueco por el lado de la pregunta: que el lateral `presente` de fn_faltas (y sus copias en fn_faltas_resumen y fn_falta_contadores) acepte también la fuente de verdad. `left join lateral (select 1 as persona_id from jornadas j where j.persona_id = tb.persona_id and j.fecha = tb.fecha and j.entrada_ts is not null union all…

**Un `useMemo` de Incidencias documenta una salvaguarda por sede que sus dos ramas no aplican**  
`apps/web/app/(admin)/admin/incidencias/page.tsx:616-624`  
El bloque se llama `visibles`, se titula «Encargada: solo su sede», compara el rol contra `"supervisor_sede"` y explica por qué el filtro es mínimo. Las dos ramas devuelven `filas` sin tocar. Es una comprobación de permiso que no comprueba nada, escrita como si comprobara.  
_Arreglo:_ DECIDÍ: borrar el `useMemo` y usar `filas` directamente, dejando en su lugar un comentario de una línea que diga la verdad —que el filtro por sede lo hacen la RLS y el filtro interno de las funciones `SECURITY DEFINER`, y que cualquier fuente nueva tiene que traerlo puesto—. La afirmación es correcta y vale la pena escribirla; lo que sobra es el código que finge aplicarla.
DESCARTÉ porque: impleme…

**El área base se llama «al cliente» mientras todo el resto del sistema dice «clienta»**  
`supabase/migrations/0022_areas_catalogo.sql:22 (dato vivo en la tabla `areas`) · apps/web/lib/areas.ts:20 · apps/web/lib/politica-salarial.ts:110 · apps/web/app/(admin)/admin/objetivos/page.tsx:410`  
El área en la que está la gente de tienda —la que atiende— se llama en pantalla «Calidad & servicio al cliente». Ese nombre sale en siete pantallas del panel, en el memo disciplinario que se imprime y se entrega en mano, y en el documento de política salarial que el equipo firma. En el mismo sistema, la pantalla de Sedes dice «Atiende clientas», el cuadro de categorías dice «Atiende a la clienta de principio a fin» y el Reglamento dedica un artículo a explicar por qué se dice «clienta». El sistema se contradice a sí mismo en la palabra que describe a quien compra.  
_Arreglo:_ DECIDÍ: renombrar el área desde /admin/areas (es un dato gestionado, no una migración) a «Calidad y servicio a la clienta», y corregir las dos copias en TS. DESCARTÉ una migración con UPDATE porque el nombre del área es justamente un dato que Felipe administra desde pantalla — meter un UPDATE por migración enseñaría que la pantalla no es la fuente. SE ROMPE SI se renombra solo en la pantalla y se …

**La política salarial publicada con acuse de recibo dice «jefatura», dos veces**  
`apps/web/lib/politica-salarial.ts:426 · supabase/migrations/0140_el_cuadro_de_categorias.sql:181, hoy vivo en categorias_laborales.funciones del rango `support``  
El documento «Cuadro de categorías y política salarial» —el que está publicado en el sistema, versionado, y del que se guarda quién lo leyó y cuándo— usa dos veces la palabra que el CLAUDE.md prohíbe: describe el ascenso diciendo que «lo propone la jefatura directa», y define al Support como «el puente entre su equipo y la jefatura de su área». En ese mismo documento la escala se llama Colibrí, Cayla, Support y Aurora, y Aurora se define como quien «dirige un área completa». O sea: el documento inventa un cargo —«la jefatura»— que no existe en ninguna otra parte del sistema y que además compit…  
_Arreglo:_ DECIDÍ: «la Aurora de su área» en la función del Support (es el cargo que el propio cuadro define un renglón más abajo) y «lo propone su líder de equipo y lo confirma la Gerencia» en el texto del ascenso. DESCARTÉ dejarlo con el argumento de que es lenguaje formal de documento laboral: el CLAUDE.md prohíbe la palabra precisamente en pantalla y en prosa, y este texto es las dos cosas. SE ROMPE SI s…

**La pantalla de Turnos imprime el identificador de la base junto al nombre de pantalla**  
`apps/web/app/(admin)/admin/turnos/page.tsx:785`  
El título de la segunda tabla de cobertura dice «Encargadas (supervisor_sede)». El paréntesis es el nombre técnico del rol, y aparece en una pantalla que usa la encargada de cada sede todas las semanas para armar turnos. Es la única filtración del identificador a una superficie visible que encontré.  
_Arreglo:_ DECIDÍ: dejar el título en «Encargadas» a secas. DESCARTÉ moverlo a un comentario del código («// = supervisor_sede») porque el filtro de esa línea ya se llama esEncargada y su definición tres líneas más arriba ya explica de dónde sale; repetirlo sería la tercera copia de la misma aclaración. SE ROMPE SI se aprovecha para renombrar también el filtro: esEncargada cubre además esEncargadaPiso, que n…

**El selector de sede se queda pegado: tras atender a quien viene de otra sede, el terminal deja de mostrar a su propio equipo**  
`/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(terminal)/terminal/marcar/page.tsx:147-152,211-220,463-480,533-537`  
Una persona con `visible_todas_sedes = true` aparece en el roster de cualquier terminal (lo permite la policy personas_select_terminal_roster), y el terminal sí puede leer sus marcas de la otra sede, así que la máquina de estados funciona bien para ella. Pero `rosterFiltrado` filtra la cuadrícula por `p.sedeCodigo === sedeSeleccionada`, y `sedeSeleccionada` arranca en la sede del terminal: quien viene de visita NO está en la cuadrícula hasta que alguien toca el selector. Y una vez tocado, `volverALista()` —que sí resetea pantalla, persona, PIN, configuración de salida y acción pendiente— no lo…  
_Arreglo:_ Devolver el selector a la sede del terminal en `volverALista()`: la sede activa es un estado de una persona concreta que está marcando, no del kiosco. Con `setSedeSeleccionada(terminal?.sedeCodigo ?? null)` ahí dentro, el terminal vuelve solo a su equipo después de cada marcaje y quien viene de fuera solo necesita un toque más. El `?sede=` de la URL debería seguir mandando si está puesto, porque a…

**«Nuevo PIN» mata el PIN anterior al primer clic, sin preguntar, y muestra el reemplazo fuera de la pantalla**  
`apps/web/app/(admin)/admin/equipo/page.tsx:1501 (el boton), :660-670 (la funcion), :1304 (donde se pinta el aviso)`  
`<button onClick={() => regenerarPin(p)} ...>Nuevo PIN</button>` ejecuta directo: genera el PIN, lo hashea, hace `update` sobre `personas` y avisa. No hay confirmacion. El PIN nuevo aparece UNA vez en el aviso de pagina, y ese aviso vive en la linea 1304 — entre las dos tablas — mientras el boton vive dentro de la segunda tabla, que va de la 1391 a la 1515. Con ~30 personas en la lista, pulsar «Nuevo PIN» en una fila de abajo pinta el unico ejemplar del PIN a un scroll completo de distancia, arriba. El boton ademas es vecino inmediato de «Registrar salida» (:1502-1506) en la misma celda.  
_Arreglo:_ Un `window.confirm` con la consecuencia dicha («el PIN actual de {nombre} deja de funcionar ahora mismo; el nuevo se muestra una sola vez») —es la misma linea que Planilla ya escribe en :1242 y :1507— y pintar el PIN nuevo en la propia fila, o en un recuadro que no se pueda perder de vista, no en el aviso comun de pagina.

**En el terminal —que se toca con el dedo— los controles que deciden el TIPO de salida son texto de 14px sin area tactil**  
`apps/web/app/(terminal)/terminal/marcar/components.tsx:186 (Otra salida), :128, :191, :338 (los tres Cancelar)`  
El resto del terminal esta bien dimensionado a proposito: las fichas de nombre son `px-4 py-6 font-serif text-xl` (:61), el teclado numerico es `h-16 w-16` (:121), el boton principal `py-5 text-xl` (:161). Pero los controles que cambian el SIGNIFICADO de la marca son enlaces de texto sin relleno. «Otra salida (personal, medico, tramite…)» es la unica puerta a las salidas por motivo —las que deciden si ese tramo se justifica o no— y esta escrito `className="mt-1 text-sm text-taupe underline"`: 14px de letra, ~20px de alto tocable, y en taupe, que es el tono mas apagado de la superficie. Los tre…  
_Arreglo:_ Darles el mismo relleno que ya tienen sus vecinos: `px-5 py-3` como minimo (~44px de alto). «Otra salida» ademas merece ser una ficha `TILE` como las de :168 y :179, no un enlace — es una eleccion, no una fuga. Y subir su color de taupe a tinta: es una opcion valida, no una nota al pie.

**Politica salarial —la pantalla que TODO el equipo firma— esta pintada fuera de la marca: 70 clases de la paleta de Tailwind en un solo archivo**  
`apps/web/app/(admin)/admin/politica-salarial/page.tsx (70 usos fuera de paleta) · el resto de la deriva en datos-personales/page.tsx (10), equipo (3), personas/[id] (2), disciplina (2), disciplina/memo/[id] (2), app/page.tsx (1)`  
Esa pantalla no usa ni un solo token de CAYLA para su superficie: usa `bg-white`, `border-slate-300`, `text-slate-900`, `bg-slate-900` para los botones primarios, y los pares `amber-50/amber-900`, `red-50/red-800`, `emerald-50/emerald-300` para sus avisos — es decir, reimplemento el sistema de estados con la paleta de la libreria justo al lado de los tres colores propios que existen para eso. Es el unico documento del producto que cada integrante lee y firma con acuse de recibo, y es el que menos se parece al producto.  
_Arreglo:_ Sustitucion mecanica: `bg-white`->`bg-papel`, `border-slate-300`->`border-sand`, `text-slate-900`->`text-tinta`, `text-slate-600/700`->`text-taupe`, `bg-slate-900`->`bg-tinta`, y los tres pares de aviso por los fondos solidos del hallazgo anterior. Es buscar y reemplazar, no rediseno.

**Accesibilidad minima: 222 encabezados de tabla sin `scope`, seis de ocho ventanas sin identidad de ventana ni salida por Escape, y ningun estilo de foco propio**  
`apps/web/app/globals.css (no hay ninguna regla `:focus-visible` en las 121 lineas) · los 8 overlays: turnos/page.tsx:1173 y :1236, incidencias:808, horarios:275, correcciones:693 y :723, horas:1091, components/acuses-pendientes.tsx:117`  
Tres cosas medibles. (1) La app tiene 222 elementos `<th>` y cero `scope="col"` o `scope="row"`: en Planilla, con doce columnas de dinero, un lector de pantalla no puede asociar una cifra con la persona de esa fila. (2) De los 8 overlays a pantalla completa, solo 2 archivos declaran `role="dialog"`/`aria-modal` y solo 1 cierra con Escape — los otros seis son recuadros superpuestos sin identidad de ventana: con Tab te sales hacia la tabla de atras y nada se cierra, y como todos cierran al hacer clic en el fondo, un clic fuera de sitio borra sin aviso lo que se estaba tecleando. (3) No existe ni…  
_Arreglo:_ Tres movimientos independientes. (a) Una regla en globals.css: `:where(button, a, input, select, textarea):focus-visible { outline: 2px solid var(--color-rojo); outline-offset: 2px; }` — cubre los 288 de una vez. (b) `scope="col"` en los 222 `<th>`: es un reemplazo mecanico. (c) Un componente `<Modal>` con `role="dialog"`, `aria-modal`, cierre por Escape y foco atrapado, copiado de `horas/page.tsx…

**El espejo a Google Sheets pagina sin orden estable — es la copia de traerTodo a la que se le cayó la única protección por la que traerTodo existe**  
`apps/web/app/api/espejo/route.ts:26-45 (pageAll y sus cuatro llamadas), frente a apps/web/lib/admin/traer-todo.ts:16-20`  
El endpoint que llena la hoja de Google que mira el contador tiene su propia paginación de mil en mil, escrita a mano, y ninguna de sus consultas de jornadas ordena por nada. Mientras el mes quepa en un lote no pasa nada. El día que pase de mil filas, la segunda página sale de un orden que Postgres no garantiza: puede repetir filas y saltarse otras, y la hoja no lo dice.  
_Arreglo:_ DECIDÍ: borrar pageAll y usar traerTodo, agregando el order que cada consulta necesita — en jornadas, `fecha` + `persona_id`, que es el par único que la propia cabecera de traer-todo.ts nombra. traerTodo es lógica pura sin dependencias de navegador, así que un route handler la puede importar igual que una pantalla.
DESCARTÉ solo agregar `.order()` a pageAll: arregla este caso y deja en pie la segu…

**El freno del doble pago no comparte cerrojo con la liquidación: dos operaciones simultáneas se lo saltan**  
`supabase/migrations/0255_marcar_una_liquidacion_pagada_no_revienta_por_una_nota_corta.sql (fn_liquidacion_pagar, vigente) frente a supabase/migrations/0244_la_0243_deja_de_pagar_de_menos_y_de_atascar_el_cierre.sql (fn_planilla_congelar, vigente)`  
HOY NO CUESTA NADA Y NO CONSTA QUE HAYA COSTADO NUNCA: hace falta que dos personas con permiso ejecuten las dos operaciones dentro de la misma fracción de segundo, y si ocurriera la pantalla lo seguiría marcando en ámbar después. Dicho eso, es el único punto por donde el freno de la 0243/0244 no muerde. El cierre toma `for update` sobre la fila del periodo, pero lee `liquidacion_pagada` con un select liso; y `fn_liquidacion_pagar` lee `planilla_pagada_detalle` con un select liso y no toca en ningún momento la fila del periodo. Las dos funciones se protegen contra su propio doble clic y contra …  
_Arreglo:_ Que fn_liquidacion_pagar tome el MISMO cerrojo que el cierre, sobre el periodo que contiene la fecha de cese, antes de calcular: `perform 1 from periodos_planilla where daterange(fecha_ini, fecha_fin, '[]') @> (v_l->>'fecha_cese')::date for update;`. El EXCLUDE `periodos_sin_solape` garantiza que a lo sumo hay una fila, así que no puede bloquear de más, y con eso las dos operaciones pasan a serial…

**fn_provisiones es cuadrática en el número de personas: cinco laterales reescanean el CTE completo una vez por cada una**  
``public.fn_provisiones(p_as_of date)` — la versión vigente en la base local. Los cinco laterales están al final del cuerpo (alias `g1`, `g2`, `cm`, `cn`, `vv`). La consume `/Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/provisiones/page.tsx:159`.`  
El CTE `base` produce una fila por persona y día devengado (jornadas con horas > 0, más los días de calendario desde el ingreso para quien tiene hijos o sueldo fijo). Después, la consulta final hace cinco `left join lateral (select sum(b.pago_dia) from base b where b.persona_id = p.id and b.fecha between …)` — uno por ventana de gratificación, CTS y vacaciones. Un CTE no tiene índice: cada lateral vuelve a leer `base` entera para quedarse con las filas de una persona. Como |base| ≈ personas × días, el trabajo total es 5 × personas² × días.  
_Arreglo:_ Sustituir los cinco laterales por una sola pasada agregada: `select persona_id, sum(pago_dia) filter (where fecha between …) as g1, sum(...) filter (...) as g2, … from base group by persona_id`, y unir ese resultado a `personas` por `persona_id`. Un `group by` recorre `base` una vez en vez de cinco veces por persona, y devuelve exactamente los mismos cinco números. La alternativa que sugiere el co…

**Tres índices duplican byte por byte a un unique que ya existe sobre las mismas columnas**  
``public.turnos` → `idx_turnos_persona_fecha` duplica `turnos_persona_id_fecha_key`. `public.tardanzas_justificadas` → `idx_tardanza_justif` duplica `tardanzas_justificadas_persona_id_fecha_key`. `public.feriados_descanso_sustitutorio` → `idx_dcs_persona_feriado` duplica `uq_dcs_feriado`.`  
Cada par tiene las mismas columnas, en el mismo orden, sin cláusula `WHERE` que los diferencie. El único es obligatorio (sostiene una restricción de negocio); el otro no aporta nada que el único no dé ya.  
_Arreglo:_ `drop index concurrently public.idx_turnos_persona_fecha;` y equivalentes para los otros dos. Antes de darlo, confirmarlo en producción con un SELECT a `pg_indexes` (el local podría no reflejar prod), y comprobar en `pg_stat_user_indexes` de producción que el `idx_scan` del duplicado no sea el único con tráfico — aunque incluso en ese caso el único cubre la misma consulta y el planificador migrará…

**La imputación de falta grave deja de nombrar las sanciones previas —y dice que «constan en el legajo»— cuando la consulta que las trae falla**  
`apps/web/app/(admin)/admin/disciplina/memo/[id]/page.tsx:178-186 (la consulta), :304-323 y :324 (el texto legal que cambia según el resultado)`  
El memo de imputación enumera, con número de correlativo y fecha de entrega, las sanciones previas de la misma causal. Esa lista se trae con una consulta cuyo `error` no se lee: si falla, `previas` queda vacía, el párrafo que las nombra desaparece del documento y el párrafo siguiente cambia solo de «precedidos de las sanciones disciplinarias antes detalladas» a «que constan en su legajo». El papel se imprime sin ninguna marca de que faltó algo, y nadie que lo lea puede distinguir «no tiene antecedentes» de «no se pudieron leer sus antecedentes».  
_Arreglo:_ DECIDI: destructurar `error: ePrev` y, cuando venga con error, NO imprimir. El memo es el único documento del sistema con consecuencia legal directa, y este archivo ya eligió esa política dos veces para casos menores — «Sin firmante NO se inventa uno» (:135) y el cargo que se deja en blanco antes que decir uno falso (:193-198). Lo coherente es un tercer freno del mismo tipo: si `ePrev` no es null,…

**Exportar asistencia arranca con la fecha de UTC: desde las 7 de la tarde de Lima el CSV para el contador sale vacío y se descarga sin decir nada**  
`apps/web/app/(admin)/admin/exportar/page.tsx:9-11 y :14-15`  
La pantalla de Exportar propone por defecto «desde hoy hasta hoy», pero calcula ese «hoy» en UTC en vez de en Lima. A partir de las 19:00 de Perú eso es mañana. Quien abra la pantalla a esa hora y pulse «Descargar CSV» sin cambiar las fechas recibe un archivo con la fila de encabezados y nada más — sin error, sin aviso, y con el nombre correcto. Es el mismo archivo que va al contador.  
_Arreglo:_ DECIDI: `import { hoyLima } from "@cayla-dynamic/shared"` y borrar `fechaHoyISO()`. Es literalmente el arreglo que ya se aplicó en documentacion/page.tsx, con su porqué escrito. Y de paso: el rango por defecto de un solo día no sirve para lo que se usa esta pantalla; `primeroDeMesLima()` a `hoyLima()` —las dos ya en `fecha-lima.ts`— evita además el archivo de una fila. DESCARTE porque: (a) restarl…

**El memo disciplinario que se imprime y se entrega en mano dice «el colaborador»**  
`apps/web/app/(admin)/admin/disciplina/memo/[id]/page.tsx:456`  
En el pie del memo, la constancia de negativa a recibir —la línea que se rellena delante de dos testigos cuando alguien se niega a firmar— está redactada en masculino. Es la única frase en masculino de toda la superficie de pantalla del panel: verifiqué el resto y está todo en femenino, incluidos labels.ts, la política salarial y el terminal.  
_Arreglo:_ DECIDÍ: «la colaboradora se negó a recibir el presente documento». DESCARTÉ «la persona» —que sería neutro y también correcto— porque el art. 3.1 del RIT no pide neutralidad, pide femenino genérico y lo declara aplicable a toda persona sin distinción; usar «la persona» abriría un tercer registro donde ya hay dos. SE ROMPE SI se toca solo esta línea creyendo que cierra el tema: las plantillas de do…

**La bonificación extraordinaria de la Ley 30334 está clavada al 9 % dentro de la gratificación trunca**  
`supabase/migrations/0196_tres_puertas_en_vez_de_una_para_los_beneficios.sql:270 y :281 (fn_grati_trunca_bruta, la vigente).`  
La 0134 versionó la bonificación extraordinaria en `parametros_laborales` clave `bonificacion_extraordinaria`, y así la leen fn_planilla_calcular y fn_provisiones. fn_grati_trunca_bruta —la que calcula la gratificación trunca de un cese— no la lee: la tiene escrita como literal. El nombre de la clave de salida repite la tasa, así que si algún día cambia, la etiqueta del JSON queda mintiendo además del monto.  
_Arreglo:_ En fn_grati_trunca_bruta, leer la tasa de parametros_laborales filtrando por `p_fecha_cese` —igual que las otras dos funciones—, con `if v_f_be is null then v_f_be := 0.09; end if;` como respaldo. Y renombrar la clave de salida a `bonificacion_extraordinaria` a secas, o agregar `bonificacion_extraordinaria_tasa` al JSON como ya hace fn_planilla_calcular con `essalud_tasa` y `tasa_afp`. Ojo: la cla…

**La RMV está versionada, pero el guardián que impide que la escala salarial caiga bajo el mínimo compara contra su propia copia a mano**  
`apps/web/lib/rangos.ts:95 · tests/reglas-negocio.test.ts:96 · supabase/migrations/0103_base_legal_contractual.sql:47 (DEFAULT de personas.sueldo_base_legal, confirmado en la base: column_default = 1130.00). Contra parametros_laborales clave 'rmv' = 1130.00 vigente desde 2025-01-01, que es la que lee…`  
Hay CUATRO copias del número 1130 y solo una tiene fecha. La versionada (0116) manda en el piso de EsSalud y en el techo de la movilidad. Las otras tres —la base declarada de colibrí, el DEFAULT de la columna y la constante del test— son literales. El test existe precisamente para avisar cuando la escala quede bajo el mínimo, y no puede: sostiene su propia copia de la RMV, así que actualizar la fuente versionada no lo pone rojo.  
_Arreglo:_ Que el test lea la RMV de la misma fuente que el sistema, no de una constante: en las pruebas de negocio ya hay acceso al esquema por pgTAP. Lo más barato es una prueba pgTAP nueva en supabase/tests/ que compare `categorias_laborales.base_declarada` (que es donde vive la verdad del catálogo, según el propio rangos.ts) contra `parametros_laborales` clave 'rmv' vigente hoy — así el rojo lo produce l…

**El candado de mes pagado está en unas RPC de plata y falta en otras, sin criterio escrito**  
`Todas las que escriben tablas que fn_planilla_calcular lee. CON candado: fn_set_salario, fn_set_horario_semanal, fn_registrar_ausencia, fn_anular_ausencia, fn_set_feriado, fn_quitar_feriado, fn_otorgar_descanso_sustitutorio, fn_quitar_descanso_sustitutorio, fn_agregar_movimiento, fn_quitar_movimient…`  
Trece funciones frenan cuando la fecha cae en un periodo pagado; doce que también mueven el total no lo hacen. No hay comentario en ninguna que explique por qué el criterio se corta ahí. Ejemplos concretos: `fn_set_con_hijos` es literalmente `update personas set con_hijos = coalesce(p_con_hijos, false) where id = p_persona_id;` tras el guard de rol, y con_hijos vale S/113 de asignación familiar en cada periodo. `fn_set_tipo_vinculo` solo se niega si la persona ya está cesada; con una persona activa, pasar 'planilla' → 'rxh' apaga `en_planilla`, que en fn_planilla_calcular gobierna feriados (CA…  
_Arreglo:_ Decidir el criterio y escribirlo: qué campos de persona son un HECHO con fecha (con_hijos, régimen de pensión, tipo de vínculo, retención de 4ta) y por tanto necesitan vigencia —como ya la tienen el salario y el horario, y como la 0261 se la dio al régimen de pensión— y qué campos son una corrección de dato. Para los primeros, tramos con `vigente_desde`; para los segundos, el mismo `if exists (sel…

**`puedeVerIdentidad` promete que la cuenta bancaria es solo de DO; las tres capas se la dan a la encargada**  
`packages/shared/src/permisos.ts:49-55 · apps/web/app/(admin)/admin/datos-personales/page.tsx:74, 80, 537, 863, 1002-1003 · supabase/migrations/0061_datos_personales.sql:43-47 · supabase/migrations/0125_la_ficha_personal_completa.sql:294-295`  
`puedeVerIdentidad` se documenta como «DNI, cuenta bancaria, dirección, derechohabientes. Solo DO — es el dato con el que se abre una cuenta a nombre de otra persona». De esos cuatro, solo el DNI lo es. La pantalla entra con `puedeOperarEquipo` (que incluye a la encargada) y renderiza número de cuenta, entidad bancaria y dirección como campos editables normales; la RLS se los devuelve; y la función de escritura los acepta. `puedeVerIdentidad` gobierna únicamente el DNI y el régimen de pensión. Quien lea `permisos.ts` para responder «¿la encargada de AQP ve el número de cuenta de su equipo?» ob…  
_Arreglo:_ DECIDÍ: la correcta es la base. La 0061 tomó la decisión con nombre y apellido («decisión de Felipe»), la escribió en el encabezado y hasta dejó anotada la salida si algún día se cambia de opinión. El texto de `permisos.ts` es el que está mal, y el arreglo es reescribir su docstring para que diga lo que la función hace de verdad: gobierna el DNI y el régimen de pensión, que son los dos campos que …

**Trece funciones SECURITY DEFINER vivas usan la forma `if not fn_…()` que CLAUDE.md prohíbe**  
`En la base local (que coincide con el esquema de las migraciones): fn_expediente_adjuntar, fn_expediente_anular, fn_expediente_crear_borrador, fn_expediente_editar_borrador, fn_expediente_entregar, fn_expediente_firmar, fn_expediente_generar_falta, fn_expediente_generar_tardanza, fn_expediente_reabr…`  
Son las puertas del expediente disciplinario y de las liquidaciones por cese: las dos cosas que producen un papel legal y un pago final. Hoy ninguna deja pasar un null —lo verifiqué— pero lo hacen por accidente del esquema, no por la forma del guard. La regla existe justamente porque esa protección se pierde sin que nadie edite el guard.  
_Arreglo:_ DECIDÍ: en la próxima migración que ya toque cada una de esas funciones, reescribir el guard a la forma obligatoria — `if fn_expediente_puede_actuar(…) is not true then` y `if fn_devenga_beneficios(v_p.tipo_vinculo) is not true then`. Cambio semánticamente idéntico mientras no haya nulos, y correcto cuando los haya. DESCARTÉ una migración dedicada que reescriba las 13 de una vez: son funciones de …

**La ruta de ejemplo de Sentry, que lanza un error a propósito, está desplegada en producción**  
`apps/web/app/api/sentry-example-api/route.ts · apps/web/app/sentry-example-page/page.tsx`  
Un endpoint público y sin autenticación cuya única función es reventar. Cada visita genera un evento en Sentry, así que ensucia el sitio donde se miran los errores de verdad — el mismo Sentry al que /api/espejo manda sus fallos para poder diagnosticarlos.  
_Arreglo:_ DECIDÍ: borrar los dos archivos — la verificación que justificaban ya se hizo (Sentry está integrado y en uso en tres rutas de producción), y el propio comentario autoriza el borrado. DESCARTÉ dejarlos detrás de un guard de admin: no aportan nada a nadie con sesión, y mantener código que solo sirve para fallar es mantener una explicación que hay que repetir. SE ROMPE SI: alguien quiere volver a ve…

**fn_auto_cierre no comprueba quién la llama y `authenticated` puede ejecutarla**  
`supabase/migrations/0203_lo_que_se_congela_al_pagar_se_descongela_al_reabrir.sql (fn_auto_cierre)`  
La función es del cron (pg_cron). Su cuerpo empieza en `select (valor #>> '{}')::int into v_horas from configuracion where clave = 'auto_cierre_horas';` — no hay `fn_es_admin_o_lider()`, ni `auth.uid()`, ni nada. Y `has_function_privilege('authenticated', …, 'EXECUTE')` devuelve true. Cualquier sesión autenticada, incluida la del terminal de una tienda —que es un Mac mini a la vista de todo el equipo con la clave anónima cargada— puede dispararla. La marca que inserta lleva `origen = 'auto_cierre'`, idéntica a la del cron, sin autor y sin fila en correcciones_auditoria.  
_Arreglo:_ Revocar el EXECUTE a `authenticated` (el cron corre como postgres y no lo necesita) e inscribirla en `funciones_nunca_para_authenticated` con su motivo, siguiendo el patrón que ya existe para fn_planilla_congelar. Si algún día hace falta dispararla a mano, que sea con `if fn_es_admin_o_lider() is not true then raise exception` y dejando fila en correcciones_auditoria. Aparte, dar a la marca sintét…

**TRUNCATE está concedido a anon y a authenticated sobre todas las tablas, y la RLS no cubre TRUNCATE**  
`Concesiones a nivel de esquema en supabase/migrations (patrón `grant all on all tables in schema public`), visibles en information_schema.role_table_grants para los grantees anon y authenticated`  
HOY ESTO NO CUESTA NADA Y NO HAY NADA QUE APAGAR DE URGENCIA: ni anon ni authenticated pueden abrir una conexión (rolcanlogin = f en las dos), PostgREST nunca emite TRUNCATE, y busqué SQL dinámico —`execute format(…)` o concatenación— en las funciones del esquema public y no hay ninguna. O sea que hoy no existe camino para dispararlo. Lo anoto como deuda, no como puerta abierta.

El detalle es que TRUNCATE, en PostgreSQL, no pasa por la RLS: el único control es el privilegio. Y ese privilegio está dado. `authenticated` tiene DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE y UPDATE en 50 …  
_Arreglo:_ `revoke truncate, references, trigger on all tables in schema public from anon, authenticated;` y volver a conceder solo lo que cada superficie usa. Ninguna pantalla trunca nada. Conviene hacerlo antes que después: cuanto más crece el esquema, más tablas hereda el grant por defecto.

**La foto del DNI no vive en ningún bucket: es un enlace de Drive escrito a mano en un campo de texto**  
`/Users/archicaylo/Proyectos/cayla-dynamic/supabase/migrations/0061_datos_personales.sql:29-31 · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/datos-personales/page.tsx:598-606 · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/(admin)/admin/personas/[id]/page.tsx:404`  
foto_dni_url, foto_personal_url y foto_profesional_url son columnas de texto libre y el formulario las pinta como un input con placeholder «Enlace de Drive». El sistema guarda una cadena, no el archivo. Quien tiene acceso de lectura a la ficha (admin, líder DO, la encargada de la sede y la propia persona) ve el enlace y lo abre; a partir de ahí el control de acceso a la imagen del documento de identidad es el de Drive, que este sistema no fija, no revisa y no puede revocar. Si un enlace quedó como «cualquiera con el enlace», la foto del DNI está fuera de todo perímetro y no hay nada en la base…  
_Arreglo:_ Un bucket `fichas` privado con el mismo molde que los otros seis (policy de SELECT por fn_es_admin_o_lider o dueño de la ficha), guardar la ruta del objeto en vez de la URL, y subir con subirArchivoConProgreso, que ya existe y ya lleva identidad. Migrar los enlaces viejos es manual, una vez, y se puede hacer en tandas mientras el campo acepta las dos formas.

**El script del espejo a Sheets que está en el repo sigue pidiendo que se pegue la llave de servicio en Google Apps Script**  
`/Users/archicaylo/Proyectos/cayla-dynamic/scripts/espejo-sheets.gs:1-45 · /Users/archicaylo/Proyectos/cayla-dynamic/apps/web/app/api/espejo/route.ts · /Users/archicaylo/Proyectos/cayla-dynamic/docs/revision-2026-07-15/D-terminal-api.md:143`  
Existen dos versiones del espejo y solo una está terminada. En el servidor está /api/espejo, que corre con la llave de servicio del lado de Vercel y se protege con un ESPEJO_TOKEN propio — el diseño correcto, el que propuso la auditoría de julio. Pero el único Apps Script que hay en el repo es el anterior: sus instrucciones de cabecera dicen que en Propiedades del script se ponga «SUPABASE_KEY = (tu llave sb_secret_… de Supabase)», y el cuerpo llama a /rest/v1/personas, /rest/v1/jornadas y /rest/v1/marcajes directamente contra PostgREST con esa llave como apikey y como Bearer. Quien tenga que …  
_Arreglo:_ Reescribir scripts/espejo-sheets.gs para que llame a /api/espejo con el ESPEJO_TOKEN en la cabecera Authorization y vuelque las dos matrices que la ruta ya devuelve ya armadas (resumen y marcajes) — el trabajo de agregación ya está hecho del lado del servidor, así que el .gs queda mucho más corto. Y cerrar entonces las dos casillas de la auditoría de julio, que es lo que mantiene viva esa carpeta.

</details>

---

## 7 · Verificación retroactiva — ¿ya se ejecutó?

El sistema ya corrió. Un defecto encontrado hoy no es un bug futuro: son pagos y documentos ya emitidos que siguen en la base.

**Advertencia sobre las cifras: el Postgres de esta Mac está VACÍO** (0 personas, 0 marcajes, 0 jornadas — medido). Los detectores se probaron ahí para saber que son sintácticamente válidos, pero **el número real solo sale de correrlos en el SQL Editor de producción**.

| Hallazgo | ¿Ya ocurrió? | Desde | ¿Arreglar el código repara los datos? |
|---|---|---|---|
| El régimen de pensión se cambia por la única puerta sin candado, y la puerta con candado no la … | **indeterminado** | POR QUÉ «INDETERMINADO» Y NO «SÍ»: el camino defectuoso está… | no. Arreglar el código detiene el daño nuevo y no repara ni una fila del daño viejo.

QUÉ … |
| Un descanso médico paga sin que Desarrollo Organizacional lo apruebe, y la encargada de sede pu… | **si** | **2026-08-14**, con la 0254 (commit `0a92182`, "El descanso … | **No, y hay algo peor: arreglar solo el código abre un defecto nuevo en la dirección que e… |
| El candado de mes pagado se mide con el reloj, no con la jornada: la salida pasada la medianoch… | **indeterminado** | 2026-08-13. La expresion de reloj es mas vieja (0009_correcc… | NO. Arreglar el codigo detiene el dano nuevo y no toca ni una fila de las ya torcidas. Hac… |
| El botón «Sí, volví a entrar» borra la salida real de quien cerró tienda pasada la medianoche | **indeterminado** | 2026-08-13. El camino defectuoso nace con la 0240 (commit 29… | NO. Ninguna de las dos mitades del arreglo toca una sola fila de las ya escritas, y hace f… |
| fn_dia_incoherente y fn_siguiente_tipo_esperado no conocen fecha_jornada: el día siguiente nace… | **indeterminado** | **2026-08-13.** El defecto nace con `marcajes.fecha_jornada`… | **No.** Arreglar el código detiene el daño nuevo y no repara ni una sola fila de las que y… |
| Cuando el auto-cierre llega primero, la salida de madrugada se sigue rechazando: la 0240 solo c… | **si** | 2026-07-10 — el mismo dia que nacio el sistema.

`git log --… | NO. Hace falta una correccion aparte, y ademas hace falta preguntarle a la persona: el dat… |
| El motor de tardanzas no excluye nada del calendario: cuenta un feriado, un descanso médico y u… | **si** | 2026-07-21 — commit a3b16f4 «Disciplina: semáforo, legajo y … | NO. Repara la mitad, y la mitad que queda es la de papel.

QUÉ SE ARREGLA SOLO al tocar el… |
| Once funciones SECURITY DEFINER entregan datos de OTRA persona a cualquiera que tenga sesión | **si** | **2026-07-21** — hace 27 días. El primer `grant` de la serie… | **No — pero no porque falte una corrección de datos: porque no hay datos torcidos.** Esto … |
| DNI, correos y celulares reales de diez personas commiteados en supabase/migrations y ya en Git… | **si** | Acá "ejecutarse" es "publicarse", y ya ocurrió tres veces. `… | **No, y por dos razones opuestas que conviene no mezclar.**

**En la base no hay nada que … |
| El kiosco de marcaje puede leer el DNI, el correo y la remuneración básica legal de todo su equ… | **si** | Desde el 2026-07-10, y ampliado el 2026-07-11. No es un ries… | No. Y aquí «reparar los datos» no significa lo de siempre.

Ninguna fila está torcida: los… |

### Los detectores, listos para pegar en el SQL Editor

Todos son `SELECT` de solo lectura.

<details><summary><b>El régimen de pensión se cambia por la única puerta sin candado, y la puerta con candado no la llama ninguna p…</b> — indeterminado</summary>

_Desde:_ POR QUÉ «INDETERMINADO» Y NO «SÍ»: el camino defectuoso está desplegado en producción y es el ÚNICO que la pantalla ofrece — pero si alguien llegó a pulsar ese botón no lo puedo verificar sin acceso a prod, y este repo no admite «parece que». Hoy puede no haber costado un céntimo. Lo que lo resuelve en 10 segundos es la clase C del SELECT, que cuenta el rastro que la propia función deja en `correcciones_auditoria`. Cero filas = camino abierto, daño cero.

LO QUE SÍ ESTÁ VERIFICADO, con dos fechas, porque el defecto cambió de forma en el camino.

**2026-08-01 — nace el camino sin candado.** `git log --diff-filter=A -- supabase/migrations/0125_la_ficha_personal_completa.sql` → `9424d4c 2026-08…

_Alcance:_ NO SE PUEDE CONTAR EN LOCAL, y esa es la primera medición honesta: el Postgres de esta Mac está vacío de datos.

    select count(*) from personas;                     →  0
    select count(*) from periodos_planilla;            →  0
    select count(*) from planilla_pagada_detalle;      →  0
    select count(*) from asignaciones_regimen_pension; →  0

Es un esquema reconstruido desde las migraciones (250 filas en `migraciones_aplicadas`, la 261 incluida), sin gente. Cualquier cifra de personas que saliera de aquí sería inventada. Por eso el detector se probó SEMBRANDO el daño dentro de `BEGIN … ROLLBACK`, verificando que lo caza y —lo que más importa acá— que no toca a quien está sana:

    clase                                       | persona           | sede | ficha   | planilla  | descuento
    A · SIN HISTORIAL                           | SinFila, PersonaB | LIM  | integra | (ninguno…

```sql
-- ════════════════════════════════════════════════════════════════════════════
-- DETECTOR · El régimen de pensión cambiado por la puerta sin candado
-- SOLO LECTURA. Un solo statement (el SQL Editor corre únicamente el último).
-- Requiere que la 0261 esté pegada; si no lo está, asignaciones_regimen_pension
-- no existe y esto avisa con un error claro en vez de mentir.
--
-- Cuatro clases, de peor a menos peor:
--   A · la persona no tiene fila de historial → su valor plano gobierna TODOS
--       los periodos, incluidos los pagados.
--   B · la ficha y el historial abierto NO coinciden → la pantalla dice una
--       cosa y fn_planilla_calcular descuenta otra, y seguirá haciéndolo.
--   C · rastro de cada ejecución real de fn_set_regimen_pension, con el
--       periodo en el que cayó y si ese periodo ya estaba pagado.
--   D · boleta ya congelada cuyo régimen NO es el que un recálculo daría hoy.
--       Es la prueba de plata: trae el descuento_pension que se pagó.
-- Cero filas = nadie afectado.
-- ════════════════════════════════════════════════════════════════════════════
with abierta as (
  select a.persona_id, a.regimen, a.vigente_desde
  from asignaciones_regimen_pension a
  where a.vigente_hasta is null
),
sospechosas as (
  select
    case when ab.regimen is null
      then 'A · SIN HISTORIAL — el valor plano gobierna TODOS los periodos, pagados incluidos'
      else 'B · DIVERGENCIA — la ficha dice una cosa y la planilla descuenta otra'
    end                                          as clase,
    p.apellidos || ', ' || p.nombres             as persona,
    s.codigo                                     as sede,
    p.estado,
    p.tipo_vinculo,
    p.regimen_pension                            as la_ficha_dice,
    ab.regimen                                   as la_planilla_usa,
    coalesce(ab.vigente_desde, p.fecha_ingreso)  as desde,
    null::numeric                                as descuento_congelado,
    null::text                                   as periodo
  from personas p
  join sedes s on s.id = p.sede_base_id
  left join abierta ab on ab.persona_id = p.id
  where p.regimen_pension is not null
    and (ab.regimen is null or ab.regimen is distinct from p.regimen_pension)
),
rastro as (
  select
    'C · YA SE EJECUTÓ — cambio sin fecha (' || coalesce(c.valor_anterior,'?')
      || ' → ' || coalesce(c.valor_nuevo,'?') || ')',
    p.apellidos || ', ' || p.nombres,
    s.codigo,
    p.estado,
    p.tipo_vinculo,
    c.valor_nuevo,
    c.valor_anterior,
    (c.corregido_at at time zone 'America/Lima')::date,
    null::numeric,
    (select to_char(pp.fecha_ini,'DD/MM') || '–' || to_char(pp.fecha_fin,'DD/MM/YYYY')
            || ' (' || pp.estado || ')'
       from periodos_planilla pp
      where (c.corregido_at at time zone 'America/Lima')::date
            between pp.fecha_ini and pp.fecha_fin)
  from correcciones_auditoria c
  join personas p on p.id = c.persona_id
  join sedes   s on s.id = p.sede_base_id
  where c.campo_m…
```

_¿Repara solo?_ no. Arreglar el código detiene el daño nuevo y no repara ni una fila del daño viejo.

QUÉ HACE FALTA EN EL CÓDIGO (y lo obvio no alcanza):

- Apuntar `page.tsx:295` a `fn_cambiar_regimen_pension` no basta por sí solo: esa función exige un `p_desde` que el formulario hoy no tiene. Hace falta el campo «desde cuándo», y cambiar el mensaje de `page.tsx:312`, que hoy promete algo falso.
- Hay que CERRAR `fn_set_regimen_pension`, no solo dejar de llamarla. La 0125 le da `grant execute … to authenticated` (línea 226), así que queda expuesta por PostgREST a cualquier sesión con login aunque la pantalla cambie. O delega en la versionada, o se revoca. Es el mismo razonamiento por el que la 0090 metió el guard DENTRO de la función en vez de confiar en un `revoke`.
- Y queda un tercer camino: la 0190 documenta como procedimiento un `update personas set regimen_pension = '<su afp>' where id = '<uuid>'` a mano (línea 59). Mientras esa columna sea escribible sin dejar fila, la próxima migración que diga «corre este update» reabre el hueco. El cierre real es un trigger sobre la columna, o que la columna deje de ser la fuente y pase a derivarse del historial.
- Falta la prueba que lo habría cazado:…
</details>

<details><summary><b>Un descanso médico paga sin que Desarrollo Organizacional lo apruebe, y la encargada de sede puede registrarlo</b> — si</summary>

_Desde:_ **2026-08-14**, con la 0254 (commit `0a92182`, "El descanso médico deja de pagarse en cero"). Es la mitad de descanso médico; la mitad de maternidad todavía NO está en producción.

Evidencia de que la 0254 SÍ está pegada, no supuesta: el commit `51d14dd` (2026-08-15) registra que Felipe corrió la consulta de md5 en el SQL Editor y produccion devolvió `19eb593a757e0b7480b6a1dc99d7f8c9`, 75 882 caracteres — "EXACTAMENTE el de la 0254". Y `docs/estado.md:624` documenta un caso real ya calculado con ella ("su descanso médico pasó de 1 día pagado a 4 (~S/30 → ~S/122)", aplicado y comprobado el 2026-08-14).

`git log --follow` sobre las tres rutas:
- `supabase/migrations/0254_el_descanso_medico_de…

_Alcance:_ **No se puede contar en local: el Postgres local está VACÍO** — `select count(*) from personas` devuelve **0**. El número real solo sale de correr el detector en el SQL Editor. Lo que sí se puede medir es el tamaño del agujero y quién cabe por él, y eso se midió.

**Quién puede abrirlo — medido, no deducido.** Dentro de `BEGIN … ROLLBACK`, poniendo como identidad a una `supervisor_sede`:
- `fn_registrar_ausencia(...,'descanso_medico',...)` **funcionó** y devolvió el uuid. La ausencia quedó con `aprobada_at = null` y `registrada_por` = la encargada.
- `fn_aprobar_ausencia(...)` sobre esa misma fila **falló**: «Solo un administrador o líder de Desarrollo Organizacional puede aprobar una ausencia remunerada.»

O sea: el guard de aprobación funciona perfectamente y no gobierna nada. Alcanza a las **encargadas de las cuatro sedes** sobre cualquier persona `en_planilla` de su propia sede (`fn_…

```sql
-- ============================================================================
-- SOLO LECTURA. Ausencias que la planilla YA PAGA sin la aprobacion de DO.
-- Un solo SELECT: el SQL Editor de Supabase corre nada mas el ultimo bloque.
-- ----------------------------------------------------------------------------
-- Reproduce LITERALMENTE las condiciones de los laterales `dmd` y `mat` de
-- fn_planilla_calcular (0263 / la 0254 en produccion), MENOS el filtro que
-- falta: no exige `aprobada_at`. Por eso lo que devuelve son exactamente los
-- dias que la funcion esta pagando sin que nadie de DO los haya firmado.
--
-- Como se leen las columnas:
--   estado_periodo = 'pagado'   -> la plata YA SALIO (mirar la foto congelada)
--   estado_periodo = 'abierto'  -> todavia se puede arreglar antes del cierre
--   'sin periodo'               -> ni siquiera hay periodo creado aun
-- Las filas de tipo 'maternidad' son PREVENTIVAS mientras la 0262/0263 no
-- esten pegadas: hoy no pagan, el dia que se peguen pagaran.
-- ============================================================================
with tope as (
  select coalesce(
           (select (valor->>'umbral_essalud')::int
              from configuracion
             where clave = 'descanso_medico_aviso_dias'), 20) as dias
),
-- Numeracion PARTIDA POR ANO de los dias de descanso medico, contando todos
-- los no anulados (aprobados o no), igual que el lateral `dmd`.
dm as (
  select a.id as ausencia_id, a.persona_id, d::date as dia,
         row_number() over (partition by a.persona_id, extract(year from d)
                            order by d) as n
  from ausencias a
  cross join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') d
  where a.tipo = 'descanso_medico'
    and a.anulada_at is null
),
-- Los dias que de verdad se pagan: dentro del tope, dia laborable suyo, ni
-- feriado ni vacaciones. Copia de las condiciones del lateral `dmd`.
dm_pagados as (
  select dm.ausencia_id, dm.dia
  from dm
  join personas pe on pe.id = dm.persona_id and pe.en_planilla
  cross join tope
  join lateral (
    select ha.dias_laborables, ha.horario_por_dia
    from horarios_asignados ha
    where ha.persona_id = dm.persona_id and ha.vigente_desde <= dm.dia
    order by ha.vigente_desde desc
    limit 1
  ) hv on true
  where dm.n <= tope.dias
    and not exists (select 1 from feriados f where f.fecha = dm.dia)
    and not exists (select 1 from vacaciones v
                     where v.persona_id = dm.persona_id
                       and dm.dia between v.fecha_inicio and v.fecha_fin)
    and case
          when hv.horario_por_dia is not null
            then hv.horario_por_dia ? (extract(dow from dm.dia)::int::text)
          else extract(dow from dm.dia)::int = any(hv.dias_laborables)
        end
),
-- El lateral `mat`: dias CALENDARIO, solo si tiene subsidio_diario entrado.
mat_pagados as (
  select a.id as ausencia_id, d::date as dia
  from ausencias a
  join personas pe on pe.id = a.persona_i…
```

_¿Repara solo?_ **No, y hay algo peor: arreglar solo el código abre un defecto nuevo en la dirección que este repo considera la cara.**

**1 · Lo que el arreglo sí repara solo.** El periodo 29/07–28/08 está ABIERTO. `fn_planilla_calcular` se recalcula en vivo, así que agregar el filtro antes del 28 hace que esos días dejen de aparecer sin tocar un solo dato. Hoy la plata todavía no salió.

**2 · Lo que NO repara, y no puede.** Cualquier periodo ya cerrado. La foto es inmutable por diseño — `trg_foto_es_inmutable` en `planilla_pagada_detalle` levanta excepción ante cualquier UPDATE o DELETE: «La foto de una planilla pagada no se modifica ni se borra… reabre el periodo con Revertir pago». Eso es `reversas_pago` + congelar una versión 2, operación aparte, con motivo, y con el dinero ya en la cuenta de la persona. **Si el detector devuelve una sola fila con `estado_periodo = 'pagado'`, el código no la alcanza.**

**3 · El arreglo ingenuo hace daño.** Poner `and a.aprobada_at is not null` a secas y nada más deja a un descanso médico **legítimo, con certificado, pendiente de firma** cobrando S/0.00 el día 28, en silencio. Es literal el argumento que la 0196:638-642 escribió para no exigir aprobación en …
</details>

<details><summary><b>El candado de mes pagado se mide con el reloj, no con la jornada: la salida pasada la medianoche del día 28 qu…</b> — indeterminado</summary>

_Desde:_ 2026-08-13. La expresion de reloj es mas vieja (0009_correcciones.sql, fa22403, 2026-07-11 para el trigger de delete; 0102, 48f08fe, 2026-07-27 para anular/corregir_marca/reactivar/confirmar_auto_cierre; 0188, c5d1621, 2026-08-08 para eliminar/agregar/corregir_marcaje/resellar), pero hasta el 2026-08-13 era CORRECTA: sin la columna fecha_jornada el dia de reloj de una marca era su dia de jornada, y el encabezado de la 0240 documenta que una salida pasada la medianoche se rechazaba en la puerta. La divergencia nace con 0240_la_salida_pasada_la_medianoche_por_fin_se_puede_marcar.sql (commit 290f722, 2026-08-13), aplicada a produccion ese mismo dia; la 0249 (81ba49c, 2026-08-14) confirma por es…

_Alcance:_ NO SE PUEDE MEDIR EL NUMERO REAL DESDE AQUI, y conviene decirlo antes que cualquier cifra: el Postgres local no tiene datos de produccion. Medido: 0 personas, 0 jornadas, 0 marcajes, 0 periodos_planilla. Lo unico que trae de fabrica son las 3 sedes semilla (TRU, LIM, AQP; Central no esta en la semilla). Asi que las cifras de abajo son cotas y una medicion sintetica, no un recuento.

LO MEDIDO EN LOCAL (BEGIN … ROLLBACK, con las funciones reales de la base):
· 1 cruce de medianoche + 1 eliminacion desde Correcciones = 9.50 horas fantasma en la jornada del 10/08, con la marca ya borrada de marcajes. El recalculo forzado del dia correcto las deja en NULL. Por la equivalencia que la propia 0240 publica en su encabezado (9.50 h con salario S/1500), son del orden de S/70 por episodio.
· 1 cruce la noche del 28 al 29 con el periodo del 28 en 'pagado' = el candado deja anular esa salida, mientra…

```sql
-- ============================================================================
-- DETECTOR (SOLO LECTURA) — la medianoche y el candado del mes pagado
-- Pegar tal cual en el SQL Editor de Supabase. Es UN SOLO select: no lee ni
-- escribe nada mas. Si el bloque D no devuelve ninguna fila, nadie ha cruzado
-- la medianoche desde la 0240 y no hay nada expuesto.
--
--   A  el candado del mes pagado mira el dia equivocado (la mitad latente)
--   B  la jornada paga horas sin marca viva detras       (la mitad que ya cobra)
--   C  dia fantasma: salida sin entrada, dia anterior abierto
--   D  universo expuesto: todo cruce de medianoche registrado
-- ============================================================================
with cruces as (
  select m.id, m.persona_id, m.tipo::text as tipo, m.timestamp_marca,
         m.fecha_jornada,
         (m.timestamp_marca at time zone 'America/Lima')::date as fecha_reloj,
         m.anulada_at, m.estado_revision::text as estado_revision
  from marcajes m
  where m.fecha_jornada is not null
),
bloque_a as (
  select 'A · el candado del mes pagado mira el dia equivocado'::text as sintoma,
         c.persona_id,
         c.fecha_jornada as fecha_de_la_jornada,
         c.fecha_reloj   as fecha_del_reloj,
         ('marca ' || c.tipo || ' del ' || to_char(c.timestamp_marca at time zone 'America/Lima','DD/MM/YYYY HH24:MI')
          || ' · su jornada esta en un periodo ' || coalesce(pj.estado,'(sin periodo)')
          || ' y su reloj en uno ' || coalesce(pr.estado,'(sin periodo)'))::text as detalle,
         null::numeric as horas_en_juego
  from cruces c
  left join periodos_planilla pj on c.fecha_jornada between pj.fecha_ini and pj.fecha_fin
  left join periodos_planilla pr on c.fecha_reloj   between pr.fecha_ini and pr.fecha_fin
  where coalesce(pj.estado,'(sin periodo)') is distinct from coalesce(pr.estado,'(sin periodo)')
),
bloque_b as (
  select 'B · la jornada paga horas sin marca viva que las sostenga'::text,
         j.persona_id, j.fecha, null::date,
         ('salida_final_ts = ' || to_char(j.salida_final_ts at time zone 'America/Lima','DD/MM/YYYY HH24:MI')
          || ' y no queda ninguna marca viva en esa jornada con esa hora')::text,
         j.horas_trabajadas
  from jornadas j
  where j.salida_final_ts is not null
    and not exists (
      select 1 from marcajes m
      where m.persona_id = j.persona_id
        and m.anulada_at is null
        and m.tipo = 'salida_final'
        and m.timestamp_marca = j.salida_final_ts
        and coalesce(m.fecha_jornada, (m.timestamp_marca at time zone 'America/Lima')::date) = j.fecha
    )
),
bloque_c as (
  select 'C · dia fantasma: salida sin entrada y el dia anterior abierto'::text,
         j.persona_id, j.fecha, null::date,
         ('la jornada del ' || (j.fecha - 1)::text || ' quedo abierta sin salida')::text,
         j.horas_trabajadas
  from jornadas j
  where j.entrada_ts is null and j.salida_final_ts is not null
    and exists (select 1 from jorna…
```

_¿Repara solo?_ NO. Arreglar el codigo detiene el dano nuevo y no toca ni una fila de las ya torcidas. Hacen falta tres cosas mas, y dos de ellas no son un script sino una decision de Felipe.

1) EL ARREGLO DE CODIGO (una migracion). Las 12 funciones pasan de
   (timestamp_marca at time zone 'America/Lima')::date
   a
   coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date)
   La expresion correcta ya existe en el repo (0240) y sus dos usuarios estan probados: no hay que inventar nada, hay que copiarla. Ojo con dos que no son un reemplazo mecanico: fn_agregar_marcaje ademas tiene que ESCRIBIR fecha_jornada cuando la marca cierra una jornada abierta del dia anterior (hoy la pone null y recrea el dia fantasma del C4 por el panel), y fn_corregir_marcaje compara dos fechas (v_fecha_ant y v_fecha_nueva), asi que las dos tienen que pasar por el coalesce. Y antes de copiar cada cuerpo, ./scripts/donde-vive.sh, que aqui hay funciones con 5 versiones repartidas.

2) LA REPARACION DE DATOS (aparte, y no es idempotente ni automatica). Para cada fila que devuelva el bloque B del detector hay que volver a correr fn_recalcular_jornada(persona_id, fecha) con el dia BUENO. Dos frenos:
   · …
</details>

<details><summary><b>El botón «Sí, volví a entrar» borra la salida real de quien cerró tienda pasada la medianoche</b> — indeterminado</summary>

_Desde:_ 2026-08-13. El camino defectuoso nace con la 0240 (commit 290f722, `git log --follow` sobre `supabase/migrations/0240_la_salida_pasada_la_medianoche_por_fin_se_puede_marcar.sql`): antes de ella una `salida_final` de 00:30 se rechazaba en la puerta y no existía la fila. La 0240 la deja entrar con `fecha_jornada` puesta, y esa es la fila que el botón después borra.

Que la 0240 está EN PRODUCCIÓN desde esa misma noche lo dice el propio repo: la cabecera de la 0249 y `docs/estado.md:535,556` («Casi seguro fue un estado transitorio de las pruebas de la 0240 esa noche», «lo que sostiene que producción estaba en la 0240 es indicio, no garantía — el error que rechazaba las salidas era exactamente s…

_Alcance:_ MEDIDO EN LOCAL: 0 filas. El Postgres local tiene 0 personas y 0 marcajes (`select count(*) from personas` → 0), asi que solo sirve para dos cosas, y las dos las hice: probar que el SELECT es valido y devuelve vacio sin error, y reproducir el caso completo dentro de BEGIN … ROLLBACK para ver que lo caza (1 fila, DANADO).

EL DAÑO POR INCIDENTE, MEDIDO — y es MAYOR que lo que decia el hallazgo: no se estropea un dia, se estropean DOS.

Fixture: TRU, horario 15:00–23:00, entra el 16-ago 15:00 y cierra tienda el 17-ago 00:30; a la manana siguiente entra 08:00, pulsa el boton y cierra normal a las 20:00.

  antes del boton    16-ago  cerrada                  9.50 h   <- la 0240 funciona
  despues del boton  16-ago  abierta                  null     <- pierde su salida
  y tras el cron     16-ago  auto_cerrada_pendiente   8.00 h   <- el cron invento las 23:00
                     17-ago  cerr…

```sql
select
  p.nombres || ' ' || p.apellidos                                 as persona,
  s.codigo                                                        as sede,
  m.fecha_jornada                                                 as noche_a_la_que_pertenece,
  (m.timestamp_marca at time zone 'America/Lima')::date            as dia_de_calendario,
  to_char(m.timestamp_marca at time zone 'America/Lima','HH24:MI') as hora_salida_real,
  case
    when m.anulada_at is null then 'SANO - la salida sigue viva'
    when m.anulada_motivo like '%reabierto desde terminal%'
         then 'DANADO - el boton borro la salida real de esa noche'
    else 'REVISAR - anulada por otra via'
  end                                                             as diagnostico,
  m.anulada_at,
  m.anulada_motivo,
  jn.estado             as estado_jornada_de_la_noche,
  jn.horas_trabajadas   as horas_de_la_noche,
  jc.estado             as estado_dia_de_calendario,
  jc.horas_trabajadas   as horas_dia_de_calendario,
  pn.estado             as periodo_de_la_noche,
  pc.estado             as periodo_del_dia_de_calendario
from marcajes m
join personas p                on p.id = m.persona_id
left join sedes s              on s.id = m.sede_id
left join jornadas jn          on jn.persona_id = m.persona_id
                              and jn.fecha = m.fecha_jornada
left join jornadas jc          on jc.persona_id = m.persona_id
                              and jc.fecha = (m.timestamp_marca at time zone 'America/Lima')::date
left join periodos_planilla pn on m.fecha_jornada between pn.fecha_ini and pn.fecha_fin
left join periodos_planilla pc on (m.timestamp_marca at time zone 'America/Lima')::date
                                  between pc.fecha_ini and pc.fecha_fin
where m.tipo = 'salida_final'
  and m.fecha_jornada is not null
order by m.anulada_at desc nulls last, m.timestamp_marca desc;

-- Es UN SOLO select (el SQL Editor corre solo el ultimo) y es de solo lectura.
-- Sin acentos en el LIKE a proposito: el motivo se escribe «Día reabierto desde
-- terminal: …» y un portapapeles con el locale roto lo parte. Se busca por
-- «reabierto desde terminal», que es ASCII puro.
--
-- COMO SE LEE:
--   · Devuelve TODA la poblacion expuesta: una fila por cada noche en que
--     alguien cerro tienda pasada la medianoche desde el 13-ago.
--   · diagnostico = 'DANADO ...'  -> el boton ya se pulso, esa noche perdio su
--     salida real. Son las filas a corregir.
--   · diagnostico = 'SANO ...'    -> la marca sigue viva; esa persona SI paso
--     por la pantalla «Ya cerraste tu dia» a la manana siguiente, pero no pulso
--     el boton (o aun no llego a hacerlo). Es la lista de quien esta en riesgo.
--   · periodo_de_la_noche = 'pagado' -> el recalculo esta bloqueado por el
--     candado de la 0191; corregir esa fila exige fn_revertir_pago primero.
--
-- Probado contra el Postgres local: valido y 0 filas con la base vacia; con el
-- caso reproducido dentro de BEGIN … ROLLBACK devuelve exactame…
```

_¿Repara solo?_ NO. Ninguna de las dos mitades del arreglo toca una sola fila de las ya escritas, y hace falta una correccion de datos aparte, fila por fila.

POR QUE EL CODIGO NO REPARA NADA. `fn_recalcular_jornada` solo lee marcas con `anulada_at is null`. La salida real ya esta anulada, y el par `salida_otro`/`retorno_otro` ya existe con `fecha_jornada = NULL`. Se puede desplegar el arreglo, correr el recalculo de esos dos dias las veces que se quiera, y el 16 seguira en 8.00 h y el 17 en null: no hay nada en el arreglo que vuelva a mirar una fila anulada ni que le ponga `fecha_jornada` a una fila que ya se escribio sin ella.

LO QUE HAY QUE ARREGLAR EN EL CODIGO — son TRES sitios, no uno, y los tres son el mismo error (fecha de calendario donde tocaba jornada):

 1. `apps/web/lib/terminal/estado-dia.ts:58` — el select pide `persona_id, tipo, timestamp_marca`. Tiene que pedir tambien `fecha_jornada`, y el reparto de la linea 80 tiene que usar `coalesce(fecha_jornada, fechaLima(m.timestamp_marca))`. Hoy `fecha_jornada` no aparece en NI UNA linea de `apps/web/app`, `apps/web/lib` ni `packages/shared/src` — verificado con grep, 0 resultados. La columna existe en la base y en los tipos generados de…
</details>

<details><summary><b>fn_dia_incoherente y fn_siguiente_tipo_esperado no conocen fecha_jornada: el día siguiente nace sellado y el r…</b> — indeterminado</summary>

_Desde:_ **2026-08-13.** El defecto nace con `marcajes.fecha_jornada`, que es de la 0240 — commit `290f722`, `2026-08-13 14:25:06 -0500`, `git log --follow -- supabase/migrations/0240_la_salida_pasada_la_medianoche_por_fin_se_puede_marcar.sql`. Las dos funciones señaladas son mucho más viejas (`fn_dia_incoherente` de la 0082, 2026-07-26; `fn_siguiente_tipo_esperado` de la 0129, 2026-08-02) y hasta ese día no tenían nada malo: acotar por `(timestamp_marca at time zone 'America/Lima')::date` era la única definición de «día» que existía. Se volvieron falsas el día que la 0240 introdujo una segunda.

En producción el SQL entró el mismo día: `docs/hallazgos-abiertos.md:61` dice «SQL aplicado; **falta desp…

_Alcance:_ **No se puede medir en local: la base local está vacía** — `personas = 0`, `marcajes = 0`, `jornadas = 0`. El detector corrido ahí devuelve 0 filas. La cifra real solo sale de producción, y no tengo lectura. Lo que sí se puede acotar con precisión:

**Techo temporal: 5 días.** `fecha_jornada` no existía antes del 2026-08-13. Ninguna fila anterior puede estar tocada — la columna es `null` en todo lo demás, y el filtro `fecha_jornada is not null` no la alcanza. Del 13 al 17 de agosto.

**Quiénes.** Solo quien cumple las dos condiciones a la vez:
1. marcó una `salida_*` o `retorno_*` después de la medianoche con su jornada del día anterior todavía abierta y dentro del tope de 16 h de su entrada — o sea, **quien cierra tienda o taller tarde**; y
2. **volvió a marcar algo el día calendario siguiente**. Si al día siguiente descansaba, no hay daño en planilla.

Por sede: cualquiera de las tres …

```sql
```sql
-- SOLO LECTURA. Quién ya quedó tocado por el defecto de fecha_jornada (0240).
-- Un solo SELECT: se pega tal cual en el SQL Editor de Supabase.
with cruce as (
  select m.id                                                  as marca_cruce_id,
         m.persona_id,
         m.tipo                                                as marca_que_cruzo,
         m.timestamp_marca,
         m.fecha_jornada                                       as jornada_real_de_la_marca,
         (m.timestamp_marca at time zone 'America/Lima')::date  as dia_contaminado
  from marcajes m
  where m.fecha_jornada is not null
    and m.anulada_at is null
    and m.fecha_jornada <> (m.timestamp_marca at time zone 'America/Lima')::date
),
dia as (
  select c.*,
         (select count(*) from marcajes o
           where o.persona_id = c.persona_id and o.anulada_at is null
             and (o.timestamp_marca at time zone 'America/Lima')::date = c.dia_contaminado
             and o.id <> c.marca_cruce_id)                      as otras_marcas_ese_dia,
         (select count(*) from marcajes o
           where o.persona_id = c.persona_id and o.anulada_at is null
             and (o.timestamp_marca at time zone 'America/Lima')::date = c.dia_contaminado
             and o.estado_revision = 'pendiente_revision')      as marcas_selladas_en_falso
  from cruce c
)
select count(*) over ()                                          as total_dias_afectados,
       p.nombres || ' ' || p.apellidos                           as persona,
       s.codigo                                                  as sede,
       d.jornada_real_de_la_marca,
       d.dia_contaminado,
       d.marca_que_cruzo,
       to_char(d.timestamp_marca at time zone 'America/Lima','HH24:MI') as hora_del_cruce,
       d.otras_marcas_ese_dia,
       d.marcas_selladas_en_falso,
       fn_dia_incoherente(d.persona_id, d.dia_contaminado)       as el_dia_figura_roto,
       coalesce(j.estado::text, '(sin jornada)')                 as estado_jornada,
       j.horas_trabajadas                                        as horas_que_paga_ese_dia,
       j.tiene_salida_no_retornada                               as pausa_sin_retorno,
       coalesce(pp.estado, '(sin periodo)')                      as periodo,
       trim(both ' | ' from
            case when d.otras_marcas_ese_dia > 0
                      and (j.id is null
                           or (j.estado in ('abierta','en_pausa') and j.salida_final_ts is null))
                 then 'DIA SIN CERRAR: fn_auto_cierre lo salta y la planilla lo paga como 0 h | ' else '' end
         || case when d.marcas_selladas_en_falso > 0
                 then 'sellado en falso: sale en Correcciones y fn_levantar_sello no lo puede quitar | ' else '' end
         || case when coalesce(j.tiene_salida_no_retornada, false)
                 then 'pausa sin retorno: el retorno pudo ser rechazado en la puerta | ' else '' end
         || case when d.otras_marcas_ese_dia = 0
                 then …
```

_¿Repara solo?_ **No.** Arreglar el código detiene el daño nuevo y no repara ni una sola fila de las que ya están. Hacen falta tres cosas más, y en este orden.

**Qué hay que arreglar en el código (cuatro funciones + el terminal, no dos).** La regla es una sola: donde hoy se escribe `(timestamp_marca at time zone 'America/Lima')::date` para decidir «de qué día es esta marca», tiene que ir `coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date)` — que es exactamente lo que la 0240 ya hizo en `fn_recalcular_jornada` y en el trigger, y se dejó a medias.

1. `fn_dia_incoherente` (0082) — su `where`.
2. `fn_siguiente_tipo_esperado` (0129) — sus tres consultas.
3. `fn_auto_cierre` — el `exists` de «ya hay una `salida_final` ese día» y el `max(timestamp_marca)` del piso. **Esta es la que cuesta plata y no estaba en el hallazgo.**
4. `fn_levantar_sello_si_el_dia_cuadra` (0084) — su `update`, o el sello seguirá sin poderse quitar aunque el día ya cuadre.
5. Y en el terminal, `apps/web/lib/terminal/estado-dia.ts`: hoy reparte ayer/hoy con `fechaLima(m.timestamp_marca)` y la consulta ni siquiera trae `fecha_jornada` en el `select`. Sin esto, el frontend seguirá diciéndole «Ya registrast…
</details>

<details><summary><b>Cuando el auto-cierre llega primero, la salida de madrugada se sigue rechazando: la 0240 solo cubre 3 horas</b> — si</summary>

_Desde:_ 2026-07-10 — el mismo dia que nacio el sistema.

`git log --follow -- supabase/migrations/0007_auto_cierre.sql` → `05ecc19 2026-07-10 Auto-cierre de jornadas olvidadas + guia de Mac mini`. Ese archivo trae, en el mismo commit, las DOS piezas que producen el defecto:
  linea 18:  ('auto_cierre_horas', '3', ...)
  linea 118: select cron.schedule('auto-cierre-jornadas', '*/15 * * * *', $$select fn_auto_cierre()$$);
Y `fn_registrar_marcaje` (0002) es del mismo dia: `2960343 2026-07-10`. Medido en la base local: `cron.job` 1 = `*/15 * * * *` activo, y `configuracion.auto_cierre_horas` = 3.

Dos fases, no una:
· 2026-07-10 → 2026-08-13 — TOTAL. Ninguna salida de madrugada se podia registrar. No es…

_Alcance:_ NO SE PUEDE MEDIR EN LOCAL, y hay que decirlo asi en vez de inventar un numero. El Postgres local esta vacio de datos: medido, `personas` 0, `horarios_asignados` 0, `jornadas` 0, `marcajes` 0, `marcajes origen='auto_cierre'` 0 — solo las 3 sedes del seed (LIM, TRU, AQP; ojo, ni siquiera Central). `supabase db reset` levanta el esquema, no la historia. El conteo real solo sale corriendo el detector en el SQL Editor de produccion, y ahi no tengo acceso.

LO QUE SI MEDI, que es que el detector no miente en ninguna de las dos direcciones. Escenario controlado con 5 personas dentro de BEGIN … ROLLBACK, cron ejecutado de verdad (`fn_auto_cierre()` devolvio 4 y luego 3):

  A_Victima | 2026-08-04 | auto_cerrada_pendiente |  7.00
  A_Victima | 2026-08-05 | auto_cerrada_pendiente | 20.48
  B_Cruza   | 2026-08-04 | cerrada                |  9.50
  C_Turno   | 2026-08-04 | auto_cerrada_pendiente | …

```sql
-- ============================================================================
-- Salidas de madrugada que el auto-cierre alcanzo primero.
-- SOLO LECTURA. Un unico SELECT (el SQL Editor corre solo el ultimo).
-- Lee `auto_cierre_horas` de `configuracion`, no lo asume.
-- Bloque A = confirmado y cuantificado. Bloque B = lista para preguntar, NO es
-- una acusacion: los falsos positivos cuestan mas que una falta que se escapa.
-- ============================================================================
with cfg as (
  select coalesce((select (valor #>> '{}')::int
                     from configuracion where clave = 'auto_cierre_horas'), 3) as horas
),
prog as (
  -- misma cascada turno del dia -> horario_por_dia -> legacy que usa fn_auto_cierre
  select j.id, j.persona_id, j.fecha, j.sede_id, j.estado,
         j.entrada_ts, j.salida_final_ts, j.horas_trabajadas,
         c.hora_entrada, c.hora_salida
  from jornadas j
  left join lateral (
    select
      case when t.fecha is not null and t.es_descanso then null
           when t.fecha is not null then t.hora_entrada
           when ha.horario_por_dia is not null
             then (ha.horario_por_dia -> extract(dow from j.fecha)::int::text ->> 'e')::time
           else ha.hora_entrada end as hora_entrada,
      case when t.fecha is not null and t.es_descanso then null
           when t.fecha is not null then t.hora_salida
           when ha.horario_por_dia is not null
             then (ha.horario_por_dia -> extract(dow from j.fecha)::int::text ->> 's')::time
           else ha.hora_salida end as hora_salida
    from (select 1) uno
    left join turnos t on t.persona_id = j.persona_id and t.fecha = j.fecha
    left join lateral (
      select horario_por_dia, hora_entrada, hora_salida
      from horarios_asignados
      where persona_id = j.persona_id
        and vigente_desde <= j.fecha
        and (vigente_hasta is null or vigente_hasta >= j.fecha)
      order by vigente_desde desc limit 1
    ) ha on true
  ) c on true
),
autocerrada as (
  select p.*, m.timestamp_marca as ts_autocierre
  from prog p
  join marcajes m
    on  m.persona_id = p.persona_id
    and m.tipo       = 'salida_final'
    and m.origen     = 'auto_cierre'
    and m.anulada_at is null
    and coalesce(m.fecha_jornada,(m.timestamp_marca at time zone 'America/Lima')::date) = p.fecha
)
select
  'A · DIA FANTASMA CONFIRMADO'                                       as clase,
  pe.nombres || ' ' || pe.apellidos                                   as persona,
  se.codigo                                                           as sede,
  a.fecha                                                             as dia_real,
  (a.entrada_ts at time zone 'America/Lima')::time                    as entro,
  a.hora_salida                                                       as salida_programada,
  ((a.fecha + a.hora_salida) at time zone 'America/Lima'
     + make_interval(hours => (select horas from cfg)))
     at time zone 'America/Li…
```

_¿Repara solo?_ NO. Hace falta una correccion aparte, y ademas hace falta preguntarle a la persona: el dato que falta no esta en ningun sitio de la base.

1. LA MARCA RECHAZADA NUNCA SE ESCRIBIO. Medido: tras el rechazo solo quedan dos filas — la `entrada` real y la `salida_final` sintetica de `origen='auto_cierre'`. La salida verdadera vive unicamente en la cola IndexedDB de esa Mac mini, y segun `apps/web/lib/terminal/enviar-marcaje.ts` la cola deja de reintentar tras seis fallos y la aparta. Ningun codigo de servidor recupera una fila que jamas se inserto. Un `fn_registrar_marcaje` arreglado solo evita las noches SIGUIENTES.

2. LAS FILAS QUE SI EXISTEN NO SE RECALCULAN SOLAS. El dia truncado y el dia fantasma son historia append-only; `fn_recalcular_jornada` solo corre cuando cambia una fila de `marcajes`. Cada dia hay que corregirlo por Correcciones — anular la `salida_final` sintetica y registrar la real con motivo — que es lo que deja rastro en `correcciones_auditoria`. Dynamic avisa, nunca corrige solo lo que toca plata.

3. LOS PERIODOS PAGADOS ESTAN CERRADOS CON DOS CANDADOS. `fn_recalcular_jornada` sale en silencio si la fecha cae en un periodo `pagado`, y `fn_auto_cierre` ya ni entra (…
</details>

<details><summary><b>El motor de tardanzas no excluye nada del calendario: cuenta un feriado, un descanso médico y unas vacaciones …</b> — si</summary>

_Desde:_ 2026-07-21 — commit a3b16f4 «Disciplina: semáforo, legajo y memos automáticos (tardanzas + faltas)», que trae `0057_tardanzas_resumen.sql` y `0059_generar_tardanza.sql`. El hueco nace con la primera versión: el encabezado de la 0057 dice literalmente «Excluye, igual que fn_faltas: inactivos, no-planilla y sueldo_fijo» — copió las tres exclusiones de PERSONA de fn_faltas y ninguna de las seis de CALENDARIO. Las seis versiones posteriores (0062, 0064, 0067, 0091, 0189, 0200 / 0091, 0189, 0200, 0232, 0235) tocaron el corte non-bis-in-idem, el escalón y la medibilidad de los 180 min, y ninguna añadió el calendario. La tercera superficie es aún anterior: el «Patrón de tardanzas» de `apps/web/app/…

_Alcance:_ NO SE PUEDE CONTAR EN LOCAL, Y HAY QUE DECIRLO ASÍ: el Postgres local tiene 0 personas y 0 jornadas (`select count(*) from personas` → 0, `from jornadas` → 0). Solo trae la semilla del esquema: 112 feriados y 3 sedes (ni siquiera CCO). El número real de filas lo da el detector corrido en el SQL Editor; abajo va lo que sí se midió y lo que se puede acotar.

LO MEDIDO EMPÍRICAMENTE (BEGIN … ROLLBACK contra local, con el ROLLBACK ejecutado). Una integrante de LIM, horario 09:00–18:00 lunes a viernes, seis días con marca de entrada en agosto de 2026:

  fecha       min  qué era ese día realmente
  2026-08-03   10  martes normal  ← LA ÚNICA TARDANZA REAL
  2026-08-04   15  descanso médico registrado
  2026-08-05   40  descanso sustitutorio por el feriado del 28-jul
  2026-08-06   30  feriado Batalla de Junín, sin turno cargado
  2026-08-08   60  sábado, no está en sus dias_laborables
  2026-0…

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- DETECTOR · tardanzas contadas en días que NO eran día de trabajo suyo
-- SOLO LECTURA. Un único SELECT (el SQL Editor corre solo el último).
--
-- Aplica sobre el motor de tardanzas las MISMAS exclusiones de calendario que
-- fn_faltas ya aplica: suspensión cumplida, ausencia registrada (vacaciones,
-- descanso médico, maternidad, licencia…), descanso sustitutorio, feriado sin
-- turno explícito, y día que no está en el horario de esa persona.
--
-- Devuelve DOS capas:
--   A · la jornada que el semáforo está contando (o contó) como tardanza
--   B · el DOCUMENTO DISCIPLINARIO YA EMITIDO que imprime esa fecha en `hechos`
-- La capa B es la urgente: es papel firmado y entregado, y alimenta el escalón
-- (fn_tardanza_escalon) que decide si lo siguiente es suspensión o imputación.
-- ═══════════════════════════════════════════════════════════════════════════
with tarde as (
  select j.persona_id, j.fecha, j.minutos_tarde
  from jornadas j
  where coalesce(j.minutos_tarde, 0) > 0
),
marcada as (
  select t.persona_id, t.fecha, t.minutos_tarde,
    exists (select 1 from turnos tu
             where tu.persona_id = t.persona_id and tu.fecha = t.fecha) as hay_turno,
    exists (select 1 from feriados f where f.fecha = t.fecha) as hay_feriado,
    (select a.tipo from ausencias a
      where a.persona_id = t.persona_id and a.anulada_at is null
        and t.fecha between a.fecha_inicio and a.fecha_fin
      order by a.fecha_inicio limit 1) as ausencia,
    exists (select 1 from feriados_descanso_sustitutorio d
             where d.persona_id = t.persona_id
               and d.fecha_descanso_sustitutorio = t.fecha
               and d.estado in ('PENDIENTE','OTORGADO')) as sustitutorio,
    -- mismo cuerpo que fn_dia_suspendido, inlineado para no depender del guard
    exists (select 1 from expediente_disciplinario e
             where e.persona_id = t.persona_id
               and e.estado in ('firmado','entregado')
               and e.suspension_desde is not null
               and t.fecha between e.suspension_desde and e.suspension_hasta) as suspendida,
    -- fuga del horario LEGACY: sin `horario_por_dia`, fn_recalcular_jornada usa
    -- la hora única de `horarios_asignados` cualquier día de la semana, también
    -- los que no están en `dias_laborables`
    (select h.horario_por_dia is null
            and not (extract(dow from t.fecha)::int = any(h.dias_laborables))
       from horarios_asignados h
      where h.persona_id = t.persona_id and h.vigente_desde <= t.fecha
        and (h.vigente_hasta is null or h.vigente_hasta >= t.fecha)
      order by h.vigente_desde desc limit 1) as dia_no_suyo
  from tarde t
),
contaminada as (
  select m.persona_id, m.fecha, m.minutos_tarde,
    case when m.suspendida                       then 'suspension'
         when m.ausencia is not null             then m.ausencia
         when m.sustitutorio                     then 'descans…
```

_¿Repara solo?_ NO. Repara la mitad, y la mitad que queda es la de papel.

QUÉ SE ARREGLA SOLO al tocar el código: `fn_tardanzas_resumen` y `fn_expediente_generar_tardanza` son funciones de lectura pura sobre `jornadas` — en cuanto lleven las exclusiones de calendario, el semáforo deja de contar mal en la siguiente carga de la pantalla y ningún borrador nuevo nace contaminado. Cero migración de datos para eso. Lo mismo vale para la tercera superficie, `apps/web/app/(admin)/admin/incidencias/page.tsx:201-210`, que lee `.gt("minutos_tarde", 0)` directo contra la tabla: mientras no filtre igual, esa pantalla sigue mostrando el patrón falso aunque el semáforo ya esté sano.

QUÉ NO SE ARREGLA Y NECESITA CORRECCIÓN APARTE:

1. `expediente_disciplinario.hechos` es jsonb CONGELADO en el momento de generar. Los documentos ya en 'firmado' o 'entregado' seguirán imprimiendo el feriado, la vacación y el descanso médico como si fueran tardanzas, porque `admin/disciplina/memo/[id]/page.tsx:428` pinta `doc.hechos` tal cual. Ningún cambio en las funciones los toca.

2. Y esos documentos no son solo papel viejo: `fn_tardanza_escalon` los lee como `doc_previo` para decidir el escalón siguiente. Una amonestación con…
</details>

<details><summary><b>Once funciones SECURITY DEFINER entregan datos de OTRA persona a cualquiera que tenga sesión</b> — si</summary>

_Desde:_ **2026-07-21** — hace 27 días. El primer `grant` de la serie es `supabase/migrations/0060_generar_falta.sql:133` (`grant execute on function fn_falta_contadores(uuid, date) to authenticated;`), commit `a3b16f4` «Disciplina: semáforo, legajo y memos automáticos (tardanzas + faltas)».

Las otras ocho se fueron sumando: 0075 (`fn_es_dia_laborable:66`, `fn_dias_suspension:104`) el 26-07 · 0079 (`fn_dia_suspendido:61`) el 25-07 · 0149 (`fn_educacion_monto:243`) el 04-08 · 0163 (`fn_beneficio_ya_depositado:87`) el 05-08 · 0200 (`fn_tardanza_escalon:176`, re-otorgada en 0232/0235/0246) el 10-08 · 0228 (`fn_reglamento_no_acusado:131`) el 12-08 · 0238 (`fn_dcs_por_que_no_compensa:198`) el 13-08.

Y h…

_Alcance:_ **Todas. No hay a quién dejar fuera: ninguna de las nueve filtra por sede ni por persona** — el `where` es `persona_id = p_persona_id` y nada más. El alcance es el 100 % de las cuatro sedes (CCO, LIM, AQP, TRU) y de las ~30 personas activas e inactivas.

MEDIDO EN LOCAL — y aquí está el límite honesto: la base local está recién reseteada, con **0 personas y 0 expedientes**, así que los conteos de las secciones C y D del detector dan cero. Lo que sí se pudo medir en local es lo que importa más: **que la fuga funciona**. Con datos sintéticos dentro de `BEGIN … ROLLBACK`:

Caso 1 — sesión de una `integrante` de LIM (`fn_rol_actual()` = integrante, `fn_es_admin_o_lider()` = false), preguntando por una persona de **otra sede**:
- `select … from expediente_disciplinario where persona_id = <víctima>` → **0 filas** (el RLS hace su trabajo)
- `fn_tardanza_escalon(<víctima>)` → `suspension | 1 | 2…

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- QUÉ PUERTAS ESTÁN ABIERTAS  ·  SOLO LECTURA  ·  un solo SELECT
--
-- OJO CON QUÉ ES ESTO. No hay «filas mal calculadas» que encontrar: esto no
-- escribe nada torcido, deja leer lo que no toca. Así que el detector mide la
-- PUERTA y lo que hay detrás, no el daño — el daño no deja huella en la base.
--
-- No imprime ni un nombre, ni un DNI, ni un sueldo: solo conteos y códigos de
-- sede. Se puede pegar y leer sin exponer a nadie.
--
--   A · funciones SECURITY DEFINER (corren como postgres, o sea SIN RLS) que
--       reciben por parámetro A QUIÉN mirar, son ejecutables por `authenticated`
--       y NO preguntan quién llama.
--   B · funciones sin argumentos que entregan la lista de personas: son las que
--       proveen los UUID que la sección A necesita.
--   C · cuántas sesiones pueden llamarlas.
--   D · cuánto dato queda detrás.
--
-- Las filas de A marcadas [ESCRIBE] además MODIFICAN. Dos de ellas
-- (fn_justificar_falta, fn_set_justificacion) delegan su guarda un nivel más
-- abajo en fn_verificar_corrector y son FALSO POSITIVO: hay que leerlas a mano.
-- ═══════════════════════════════════════════════════════════════════════════
with sd as (
  select p.oid, p.proname,
         pg_get_function_identity_arguments(p.oid) as firma,
         p.prosrc,
         (p.provolatile = 'v')                     as escribe,
         coalesce(p.proargnames, '{}'::text[])     as argn
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind  = 'f'
    and p.prosecdef                                             -- corre sin RLS
    and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and p.prosrc !~* '(fn_es_admin|fn_es_lider|fn_es_supervisor|fn_verificar|fn_puede|_puede_|fn_exigir|fn_rol_actual|fn_persona_actual_id|fn_sede_actual|auth\.uid|request\.jwt)'
),
a_lee_de_otro as (
  select * from sd
  where exists (select 1 from unnest(argn) x where x ~* 'persona_id$')
),
b_enumera as (
  select * from sd
  where coalesce(array_length(argn, 1), 0) = 0
    and prosrc ~* '\mpersonas\M'
),
c_sesiones as (
  select coalesce(pe.rol::text, '(sin rol)') as rol, count(*) as n
  from personas pe
  where pe.auth_user_id is not null and pe.estado = 'activo'
  group by 1
),
d_alcance as (
  select coalesce(s.codigo, '(sin sede)')        as sede,
         count(distinct pe.id)                    as personas,
         count(distinct ed.id)                    as expedientes,
         count(distinct asg.persona_id)           as con_rango_salarial
  from personas pe
  left join sedes s                     on s.id           = pe.sede_base_id
  left join expediente_disciplinario ed on ed.persona_id  = pe.id
  left join asignaciones_salario asg    on asg.persona_id = pe.id
                                       and asg.vigente_hasta is null
  group by 1
)
select * from (
  select 1 as orden,
         'A · ENTREGA DATOS DE OTRA PERSO…
```

_¿Repara solo?_ **No — pero no porque falte una corrección de datos: porque no hay datos torcidos.** Esto es una fuga, no un cálculo. No hay filas mal escritas que recalcular, ni un pago que reemitir. Lo que hay es una puerta abierta 27 días; cerrarla vale hacia adelante y no des-lee lo que se haya leído.

EL ARREGLO, Y LA PRUEBA DE QUE NO ROMPE NADA. Es `revoke execute … from authenticated` sobre las nueve. Medido en local dentro de `BEGIN … ROLLBACK`:
- llamada directa después del revoke → `permission denied for function fn_tardanza_escalon` ✅ cerrada
- `fn_expediente_generar_falta` —que es la que el sistema sí usa y llama a `fn_falta_contadores` por dentro— **siguió corriendo y devolvió su uuid** ✅ intacta

Funciona porque los únicos que las llaman son otras funciones `SECURITY DEFINER`: comprobado en el catálogo, las nueve tienen entre 1 y 4 llamadores y **todos** son `prosecdef = true`, ninguno es `SECURITY INVOKER`. Corren como `postgres`, así que el permiso de `authenticated` les da igual. Tampoco las usa ninguna policy ni ninguna vista. El `grant` sobra por completo.

LO QUE HACE FALTA APARTE — y esto es el trabajo que el revoke no hace:

1. **Cerrar también `fn_poblacion_obligada`** (`026…
</details>

<details><summary><b>DNI, correos y celulares reales de diez personas commiteados en supabase/migrations y ya en GitHub</b> — si</summary>

_Desde:_ Acá "ejecutarse" es "publicarse", y ya ocurrió tres veces. `git log --follow`:

- 0114_tasa_de_pension_exacta.sql — commit 93d9d98, **2026-07-31 17:34:24 -05** ("La CTS, la asignación familiar y la tasa de pensión, como manda la ley"). Trae 13 DNI reales, uno por línea, cada uno con su AFP/ONP, y 20 personas nombradas con nombre y apellido.
- 0125_la_ficha_personal_completa.sql — commit 6e8d5a3, **2026-08-01 21:54:45 -05**. Dos personas nombradas con su DNI en el comentario de cabecera (incluido el número equivocado que estuvo un mes).
- 0130_los_datos_del_tregistro.sql — commit f12a9a6, **2026-08-02 20:58:59 -05**. El array JSON con 10 registros de DNI + fecha de nacimiento + correo (los 10…

_Alcance:_ Medido sobre los archivos (que es donde está el daño), porque el Postgres LOCAL tiene **0 filas en `personas` y 0 en `datos_personales`** — es un esquema limpio reconstruido desde las migraciones, sin siembra de gente. Verificado: `select count(*) from personas` → 0. Por eso el reparto por sede solo lo puede dar el detector corriendo en producción.

**15 números de documento distintos publicados**, repartidos así:
- 0130: 10 DNI. Cada uno con el **paquete completo**: fecha de nacimiento, correo personal (los 10 en `gmail.com` — cuentas privadas, no corporativas) y celular de 9 dígitos.
- 0114: 13 DNI, cada uno pegado a su régimen pensionario (Profuturo / Integra / ONP), con el nombre y apellidos completos en el comentario de la línea de arriba.
- 0125: 3 números en el comentario de cabecera.
- Solapamiento medido: 9 DNI están tanto en 0130 como en 0114; la unión de esas dos es 14; la 012…

```sql
-- ============================================================================
-- DETECTOR — quiénes tienen datos personales publicados en el repositorio.
-- SOLO LECTURA. Un único SELECT (el SQL Editor corre solo el último statement).
--
-- POR QUÉ HASHES Y NO LOS DNI: escribir aquí los números repetiría exactamente
-- la falla que se está midiendo. Las listas son el md5() de cada valor tal
-- como está escrito en las migraciones, así que el cruce es exacto — ni un
-- falso positivo ni un falso negativo — y esta consulta se puede pegar,
-- guardar o mandar sin volver a mover un dato personal.
-- Se regeneran desde el repo con:
--   grep -oE '"dni":"[0-9]+"' supabase/migrations/0130_*.sql | ... | md5
--
-- Tres arms de cruce, y el tercero es el que evita el falso negativo: la 0114
-- publicó el DNI EQUIVOCADO de una persona (venía del Excel del contador) y ese
-- número fue corregido después vía fn_set_documento. Cruzar solo contra
-- personas.documento la dejaría fuera; por eso se cruza también contra el
-- rastro de correcciones_auditoria.
-- ============================================================================
with publicado (h_doc, en_0130, en_0114, en_0125) as (values
  ('e274cb52179781ece3e9fc2ecea2d5ee','no','no','si'),
  ('83ee4726754e29a434750fc13facbe44','no','si','no'),
  ('58c212df1580c2a8aa52a573e3be34c7','si','si','no'),
  ('561356c8d23345f6e9d419e7fb70cefe','no','si','no'),
  ('6fabb609ef6edff828c4032087d27d7e','si','si','no'),
  ('0825a1ad3797f5f8add535390731ef3b','si','si','no'),
  ('6afe64d9239ba2a1e865144a8d7e551a','si','si','no'),
  ('2752c7fff207d2135b7fa39c63aa0432','si','si','no'),
  ('5236033cc48e3dcb1bdd2e4e41b35071','si','si','no'),
  ('2fae270ac4da7a1b832e1e42c3165864','no','si','no'),
  ('5e2379907c321f23d55606ddd9f197f3','si','si','no'),
  ('128c5930a903ce1b42179bcf1ba8b31b','no','si','si'),
  ('309e088f3eb65e6d3acb5479fd71fc7f','si','no','si'),
  ('b087cce39e6d4fad1aff525a5c352f96','si','si','no'),
  ('7c3927035a48cfa5d2f4ff57d5dff65b','si','si','no')
),
correo_pub (h) as (values
  ('d59f403458a8d535bbb8bdc14f20c9b1'),('54a5368e040927585b631e94e157e04a'),
  ('effa441deeee22c59151fac50fb87d0f'),('b14bb9c9d523b395c1c233ecaa2fcd5c'),
  ('c861ec1b0172b7b452861a2c67b6599b'),('d4beac47452b2e76b95e75b1a8211dcd'),
  ('9b259dd72fbed1d3a2e5e27e8514da31'),('8482ecc6050e33d71738dac3052d024a'),
  ('55ec90fd7e192d1c47daba800be31d2c'),('cd5346b360e026f4c77219afec4a0d75')
),
cel_pub (h) as (values
  ('c9bc072bbc971bbd08566f55629625b1'),('c576e88aa46277d82abd38d50c3313c3'),
  ('ab354693903920097c93d14a3c309a36'),('7c371bf3c33dbdb8c1a9e3c82b243e50'),
  ('8241c650cc6e2929528f07721319ab2e'),('6fa207fe80d53eb83ffa6c119541ed17'),
  ('293b696a9f70894fc358590f269084e2'),('baaf84ee5d429ec12ed3cf6ff5e4a1c9'),
  ('5ce8e4dec2342f599ec7c46a01241383'),('992d5437978200275951d8805d5e54b3')
),
doc_hist as (
  select persona_id, md5(btrim(valor_anterior)) as h
    from correcciones_auditoria
   where campo_modificado = 'personas.documento' an…
```

_¿Repara solo?_ **No, y por dos razones opuestas que conviene no mezclar.**

**En la base no hay nada que reparar.** Esto no es corrupción: los DNI, correos y celulares están en `personas` y `datos_personales` porque tienen que estar, y son correctos. Ningún `update` arregla esto. El daño es de **divulgación**, no de dato torcido. El detector no sirve para corregir filas — sirve para saber **a quién hay que avisarle**.

**En git, editar los archivos no borra nada.** Un commit que reemplace los valores por marcadores los saca de HEAD y de nada más: siguen literales en el commit f12a9a6 (0130), 93d9d98 (0114) y 6e8d5a3 (0125), y esos commits están en `origin/main` **y en otras 9 ramas remotas**. Hace falta, aparte:

1. Reescritura de historia (`git filter-repo` o BFG) sobre las tres rutas, force-push a las 10 ramas, y **pedir a GitHub que purgue las vistas cacheadas** de los commits viejos — sin eso, las URL `/commit/<sha>` siguen sirviendo el contenido aunque el objeto ya no esté referenciado.
2. Que **todos los clones se rehagan**. Esto choca de frente con la realidad del repo descrita en CLAUDE.md: varias sesiones a la vez compartiendo árbol, más worktrees en `.claude/worktrees/`. Cada uno conser…
</details>

<details><summary><b>El kiosco de marcaje puede leer el DNI, el correo y la remuneración básica legal de todo su equipo</b> — si</summary>

_Desde:_ Desde el 2026-07-10, y ampliado el 2026-07-11. No es un riesgo latente: es una superficie de lectura que lleva ~5 semanas abierta en producción.

git log --follow:
- supabase/migrations/0003_rls.sql → 2960343, 2026-07-10, «Sprint 0+1: terminal de marcaje, esquema Supabase y export CSV». Ahí nace la policy: `create policy personas_select_terminal_roster on personas for select to authenticated using (estado = 'activo' and sede_base_id = fn_sede_actual_terminal());`
- supabase/migrations/0008_visible_todas_sedes.sql → aca67d0, 2026-07-11, «Flag visible_todas_sedes». La redefine y la AMPLÍA: `... or visible_todas_sedes = true`. Su propio comentario dice para quién es el flag: «ej. el founder».
-…

_Alcance:_ Medido, no supuesto — pero medido sobre un fixture sintético: el Postgres local tiene 0 personas y 0 terminales (`select count(*) from personas` → 0), así que la cifra exacta de producción sale de correr el detector allá.

LO QUE SÍ ESTÁ MEDIDO (BEGIN … ROLLBACK, identidad del TERMINAL, no de un admin: set_config('request.jwt.claim.sub', <auth_user_id del terminal>) + set local role authenticated):

1) Lo que roster.ts:20 PIDE — `select id, nombres, apellidos, pin_hash, sedes:sede_base_id(...)` → 2 filas.
2) Lo que el MISMO token puede pedir cambiando una línea en el inspector → las MISMAS 2 filas, con estas columnas devueltas de verdad:
      nombres | apellidos | documento | email | sueldo_base_legal | regimen_pension | retencion_4ta | con_hijos
      ANA     | LIM ACTIVA| 00000001  | a@…   | 1500.00           | integra         | automatica    | t
      CARLA   | TRU VIAJERA| 00000003 …

```sql
-- ============================================================================
-- Qué lee HOY cada token de terminal en producción, y a quién.
-- SOLO LECTURA. Un único select (el SQL Editor corre solo el último).
-- No imprime ni un DNI ni un sueldo: solo dice si esa columna tiene valor.
-- Ojo: NO es un registro de accesos —PostgREST no deja rastro en la base—,
-- es el INVENTARIO de lo que cada credencial puede pedir. `ultimo_visto_at`
-- es lo que prueba que esa credencial estuvo viva.
-- ============================================================================
select
  s.codigo                                        as sede_del_terminal,
  t.nombre_dispositivo                            as terminal,
  t.activo                                        as terminal_activo_hoy,
  t.ultimo_visto_at,
  count(*) over (partition by t.id)               as personas_que_ese_token_lee,
  p.nombres || ' ' || p.apellidos                 as persona,
  case when p.sede_base_id = t.sede_id
       then 'misma sede'
       else 'visible_todas_sedes' end             as por_que_la_ve,
  case when p.estado = 'activo' then 'vigente'
       else 'histórica (cesó ' || p.fecha_cese || ')' end as exposicion,
  (p.documento          is not null)              as expone_dni,
  (p.email              is not null)              as expone_correo,
  (p.sueldo_base_legal  is not null)              as expone_sueldo,
  (p.regimen_pension    is not null)              as expone_regimen_pension,
  (p.retencion_4ta      is not null)              as expone_retencion_4ta,
  p.con_hijos                                     as expone_con_hijos
from terminales t
join sedes    s on s.id = t.sede_id
join personas p
  on (p.sede_base_id = t.sede_id or p.visible_todas_sedes = true)
 and (p.estado = 'activo' or p.fecha_cese >= date '2026-07-10')
order by s.codigo, t.nombre_dispositivo, (p.estado <> 'activo'), p.apellidos, p.nombres;

-- Probado contra el Postgres LOCAL dentro de BEGIN … ROLLBACK con un fixture
-- sintético (dos terminales, cuatro personas inventadas, cero PII real).
-- Devolvió 5 filas y terminó en ROLLBACK. Salida literal:
--   LIM | Mac mini LIM | 3 | ANA LIM ACTIVA    | misma sede          | vigente
--   LIM | Mac mini LIM | 3 | CARLA TRU VIAJERA | visible_todas_sedes | vigente
--   LIM | Mac mini LIM | 3 | DORA LIM CESADA   | misma sede          | histórica (cesó 2026-08-08)
--   TRU | Mac mini TRU | 2 | BEA TRU ACTIVA    | misma sede          | vigente
--   TRU | Mac mini TRU | 2 | CARLA TRU VIAJERA | misma sede          | vigente
-- La rama `estado='activo'` reproduce la policy EXACTA. La rama de fecha_cese
-- añade a quien ya cesó pero estuvo expuesta mientras estaba activa; ese tramo
-- se estima por la sede de HOY, así que subestima a quien cambió de sede.
```

_¿Repara solo?_ No. Y aquí «reparar los datos» no significa lo de siempre.

Ninguna fila está torcida: los DNI, los correos y los sueldos de `personas` son correctos. Lo que ya ocurrió no es una escritura mala, es una LECTURA posible durante cinco semanas. Un UPDATE no deshace eso; no hay nada que recalcular.

Lo que hace falta aparte del arreglo de código:

1. ROTAR LA CONTRASEÑA DE LAS TRES CUENTAS DE TERMINAL EN AUTH, Y REVOCAR SUS SESIONES. Es el paso que de verdad cierra la puerta y el que el arreglo de la policy NO hace. packages/database/src/client.ts guarda la sesión del terminal en localStorage bajo la clave `cayla-auth-terminal`, con autorrefresco: un refresh token copiado de una Mac mini sigue sirviendo desde cualquier máquina aunque mañana la policy sea perfecta. Y vincular/page.tsx:47 dice «Esto solo se hace una vez por dispositivo», así que ese token lleva ahí desde julio. Cambiar la policy sin rotar deja el arreglo a medias.

2. Decidir si esto se comunica al equipo. Es dato personal de personas reales —DNI y remuneración— y la Ley 29733 de protección de datos personales existe; no me corresponde a mí concluir si hay deber de notificar, pero es una decisión que hay que tomar a propó…
</details>

---

## 8 · Sin objeción — lo que se miró y está bien

Importa tanto como lo roto, y el encargo lo pide expresamente.

**cierre** — **La idempotencia del cierre: sin objeción, y medida.** Segunda llamada a `fn_periodo_pagado` sobre el mismo periodo (fixture en `BEGIN … ROLLBACK`, local): `ERROR: Ese periodo ya está pagado. Su desglose quedó congelado; para cambiarlo hay que reabrirlo con Revertir pago.` La foto se quedó en `version 1 | 2 filas | 130.49`. No hay segundo congelamiento posible.

**La transacción: sin objeción.** Las cinco funciones son `prokind='f'` (funciones, no procedimientos), así que ninguna puede hacer `COMMIT` por dentro: el cierre entero —congelar + marcar pagado— es una sola transacción de PostgREST. No puede quedar a medias. Medido con savepoint: cuando el freno de la 0243/0244 salta, `periodos_planilla.estado` sigue en `abierto`, `pagado_at` en null y `planilla_pagada_detalle` en 0 filas. La frase de la pantalla («El periodo sigue ABIERTO: no se congeló nada») es literal, no una promesa.

**Qué tablas ESCRIBE el cierre: exactamente dos.** `pg_locks` durante la ejecución solo muestra `RowExclusiveLock` sobre `periodos_planilla` y `planilla_pagada_detalle`. Todo lo demás que lee `fn_planilla_calcular` entra con `AccessShareLock`.

**Dos cierres del MISMO periodo en el mismo segundo: sin objeción.** `fn_periodo_pagado` hace `select estado … for update` antes de congelar, y `fn_planilla_congelar` repite el `for update` sobre la misma fila. El segundo bloquea, y al liberarse relee (READ …

**tasas** — Miré y encontré correcto, con la medición o la lectura que lo respalda:

**EsSalud (9 %) y la RMV.** `parametros_laborales`, versionadas, leídas con `vigente_desde <= p_fin and (vigente_hasta is null or vigente_hasta >= p_fin)`. No hay ninguna otra copia del 0.09 de EsSalud en el árbol: el único 0.09 que aparece dos veces es el de la Ley 30334, que sí reporto. El comentario de la 0116 justifica además por qué la lectura va al FIN del periodo y no a hoy («el piso se congela con la RMV vigente al último día calendario del período declarado»), que es lo que manda la norma.

**Las tasas de pensión.** `tasas_pension` no solo está versionada por fecha: la LECTURA también lo está. El lateral de fn_planilla_calcular filtra por `p_fin`, así que un periodo de mayo se calcula con la comisión de mayo aunque la AFP la haya cambiado en junio — que es el error que este frente busca y acá no está. ONP 13.000 %, y las cuatro AFP con aporte + comisión + prima separados (Profuturo 13.06, Prima 12.97, Integra 12.92, Habitat 12.84). Y `grava_subsidio` vive como columna de esa tabla y no como lista escrita en el cuerpo, con el comentario de la 0262 diciendo exactamente por qué: «el dia que cambie el criterio es un UPDATE, no una migracion».

**La retención de cuarta categoría (0245).** Tasa 8 % y tope S/1,500 en `parametros_laborales`, versionados. Y el respaldo está pensado en la dirección correcta…

**retroceso** — MEDICIÓN DE LAS TRES QUE PEDÍA EL FRENTE (BEGIN … ROLLBACK contra el Postgres local, scratchpad/m1.sql, ROLLBACK ejecutado). Periodo 2026-06-29→2026-07-28, jornada del 10-jul con 9.00 h.
 (a) Con el periodo en 'pagado' entra una salida_final de las 21:00 del 10-jul: la marca se guarda (3 marcas ese día) y la jornada sigue en 9.00 h. No se movió.
 (b) fn_revertir_pago('Medicion de auditoria') → NOTICE «Periodo reabierto: 2 jornadas recalculadas» y la jornada pasa de 9.00 a 12.00 h. Sí se descongela.
 (c) fn_auto_cierre() con el periodo pagado devuelve 0 y no inserta ninguna marca; con el mismo periodo ya reabierto devuelve 1 y cierra el día que le tocaba. Salta lo pagado sin dejar de funcionar donde debe.

LO DEMÁS QUE MIRÉ Y ESTÁ BIEN:
· jornadas tiene UN solo escritor. Barrido del catálogo local buscando insert/update/delete sobre jornadas: solo fn_recalcular_jornada, y lleva el candado en la primera línea del cuerpo, saliendo en silencio (correcto: lanzar abortaría el INSERT del marcaje y la terminal perdería una marca real). Ninguna policy de escritura sobre jornadas ni sobre marcajes.
· El trigger fn_trg_marcajes_recalcular_jornada pasa `coalesce(new.fecha_jornada, (timestamp at tz)::date)` en los tres caminos (insert, update y el día que abandona), coherente con la 0240. Comprobé también el borde del cruce de medianoche contra el bucle de fn_revertir_pago —que filtra por f…

**trazabilidad** — La foto del pago está bien construida y es lo que sostiene todo lo demás: `planilla_pagada_detalle` tiene `trg_foto_es_inmutable` (BEFORE DELETE OR UPDATE), versión por periodo, `congelada_por` y `congelada_at`, y `chk_foto_cuadra` obliga a que el desglose sume exactamente el total — probé a leerla y no hay forma de editarla. `liquidacion_pagada` lleva el mismo diseño, con una anulación que exige motivo y versión que anula. Toda reapertura y todo repago dejan fila en `reversas_pago` con motivo obligatorio, autor y el `pagado_at` anterior.

Los caminos de corrección de marcaje están bien hechos, uno por uno: fn_corregir_marca, fn_corregir_marcaje, fn_anular_marcaje, fn_reactivar_marcaje, fn_agregar_marcaje, fn_eliminar_marcaje, fn_confirmar_auto_cierre y fn_reabrir_dia exigen motivo de al menos 3 caracteres y escriben en `correcciones_auditoria` con valor anterior y valor nuevo; fn_verificar_corrector comprueba sede, prohíbe corregirse a una misma y prohíbe corregir a un admin. `marcajes` y `jornadas` tienen RLS activo con políticas solo de SELECT: ningún cliente escribe directo, todo pasa por funciones. Comprobé que anular no borra (0081) y que reactivar deja su propia fila.

El candado del mes pagado dentro de fn_recalcular_jornada funciona: medido, tras anular la salida de un día pagado la jornada siguió diciendo 8.50 h. fn_registrar_marcaje resuelve bien el caso de la median…

**terminal** — Miré y encontré correcto, con medición: (1) `marcajes` no tiene NINGUNA policy de INSERT/UPDATE/DELETE —solo cuatro de SELECT—, así que la regla «toda escritura de marcaje pasa por fn_registrar_marcaje» está sostenida por el esquema, no por convención; medido con pg_policies. (2) Salida sin entrada se rechaza («tipo salida_final no válido en el estado actual (se esperaba entrada)») y una segunda entrada en vivo también («la jornada ya está cerrada o requiere elegir un tipo de salida») — los dos medidos. (3) La idempotencia por client_uuid funciona en secuencia: dos llamadas con el mismo UUID devuelven la misma fila y `marcajes` queda con una sola; medido. (4) El doble toque está cubierto dos veces: `yaConfirmoRef` en ConfirmacionToast (components.tsx:246-251) corta el clic y el temporizador a la vez, y `confirmandoRef` (page.tsx:104,382) corta la re-entrada de la pantalla. (5) El terminal nunca deja elegir entrada o salida: `determinarSiguienteAccion` decide, y el servidor lo vuelve a decidir por su cuenta; las dos copias de la regla coinciden salvo en el caso de medianoche que reporto. (6) Offline SÍ encola: `encolarMarcaje` corre ANTES del envío (page.tsx:411) y no dentro del `if (error)`, y la cola sale ordenada por `timestampCliente` y no por el UUID del keyPath (offline-db.ts:80-86) — sin ese orden una salida adelantándose a su entrada sellaría el día entero. (7) `tope-de-…

**faltas** — fn_faltas (0256) aplica las exclusiones ANTES de contar, y lo medí día por día con una persona sin ningún marcaje entre el 20-jul y el 17-ago. en_planilla y sueldo_fijo: `where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false`. fecha_ingreso: `greatest(p_desde, m.fecha_ingreso)` en el generate_series — ningún día de julio salió. Turno explícito de descanso: `case when e.hay_turno then not e.turno_descanso` — el 04-ago no salió. Feriado sin turno (0256:120): `and not (fer.es is not null and not tb.hay_turno)` — el 06-ago (Batalla de Junín) no salió. Sin horario vigente: el `else false` de la cascada — el 15 y 16-ago no salieron tras cerrar el horario el 14. Descanso médico y maternidad (0256:104, vía la vista justificaciones_asistencia sobre ausencias): 10, 11 y 12-ago salieron con justificada=true, motivo descanso_medico. Vacaciones (0256:101): 13 y 14-ago con motivo vacaciones. Suspensión (0256:113, fn_dia_suspendido) y descanso sustitutorio (0256:106) están cableados en el mismo where.

TRU domingo: no existe ninguna lista lunes-a-sábado en el motor de faltas; la pregunta se hace con `extract(dow from fecha)` contra horario_por_dia/dias_laborables, y el domingo 02-ago SÍ se contó como falta con un horario {0,1,2,3,4,5}, que es lo correcto para TRU.

El día del cese: el CHECK personas_cese_coherente obliga a que estado='inactivo' y fecha_cese vayan jun…

**rls** — Aislamiento por sede y por persona, medido, no leído. Con la encargada de TRU: personas, marcajes, jornadas, asignaciones_salario, datos_personales, movimientos_planilla y liquidacion_pagada devolvieron 0 filas de LIM en las siete. Con una integrante de LIM: 1 fila propia y 0 ajenas en esas mismas siete. Es exactamente lo que prometen las policies *_select_propia y la 0256.

Marcajes append-only, verificado con las tres escrituras: UPDATE 0 filas, DELETE 0 filas, INSERT rechazado con «new row violates row-level security policy». No hay ninguna policy de UPDATE ni de DELETE sobre marcajes, que es la forma correcta de decir «esto no se corrige por debajo».

Tablas sin RLS: ninguna. Las 55 de public tienen relrowsecurity = t. Cinco no tienen policies (expediente_correlativo_seq, firmas_escaneadas, funciones_nunca_para_authenticated, google_sheets_sync_queue, migraciones_aplicadas), que es negación total y está bien.

Las tres vistas (vacaciones, justificaciones_asistencia, v_planilla_pagada) llevan security_invoker=true. Sin eso una vista propiedad de postgres se salta la RLS de sus tablas, y es el agujero clásico.

Los RPC que el panel sí usa aguantan el aislamiento por sede. Le pregunté a la encargada de TRU por una persona de LIM con datos sembrados (tardanza, marcaje incoherente, ausencia, revisión pedida, contrato por vencer) y devolvieron 0 filas las ocho: fn_personas_funcio…

**pii** — Credenciales: escaneé el árbol y los 821 commits de toda la historia (`git rev-list --all`) con seis familias de patrones — JWT (`eyJ….eyJ`), `sb_secret_`, `sb_publishable_`, `sbp_`, `ghp_`, `sk-`, `AKIA`, `xox[baprs]-`, `-----BEGIN … PRIVATE KEY`. Cero coincidencias. Ninguna llave literal entró nunca.

Frontera cliente/servidor: `SUPABASE_SERVICE_ROLE_KEY` NO lleva prefijo `NEXT_PUBLIC_`, y `createServiceRoleClient()` (packages/database/src/client.ts:70) solo se importa desde `app/api/espejo/route.ts` y `app/api/admin/cuentas/route.ts`. `ESPEJO_TOKEN` tampoco es público. `/api/reabrir-dia` usa a propósito la llave anónima con el token de la terminal, para que `auth.uid()` identifique al kiosco — el comentario lo explica y la medición lo confirma. Las cuatro rutas son las que dice el CLAUDE.md, ni una más.

Storage: los seis buckets (`actas`, `acuses`, `certificados`, `comprobantes`, `documentos`, `expedientes`) están con `public=f` y toda policy exige identidad (`fn_es_admin_o_lider() is not true`, `fn_expediente_puede_adjuntar`, `fn_documento_puede_ver`). Ninguna URL pública.

Superficie anónima: `anon` no tiene SELECT sobre ninguna tabla de `public` (0 filas en `role_table_grants`). Las 192 funciones que `anon` puede ejecutar son todas internas de `btree_gist` (`gbt_*`, `gbtreekey*`) y funciones de trigger, no invocables por PostgREST. La 0076 cerró lo que tenía que cerrar. …

**escala** — **fn_planilla_calcular escala bien y es O(personas), no O(personas × marcajes).** Medido con EXPLAIN ANALYZE sobre el periodo completo: 30 personas → 37 ms; 60 → 153 ms; 120 → 157 ms; 240 → 375 ms. La profundidad del histórico casi no influye (con 30 personas fijas: 400 días de jornadas → 41 ms, 1.100 días → 34 ms, 2.200 días → 48 ms), porque los CTE `horas` y `ot_dias` filtran por rango de fecha y no barren la tabla. Es una sola sentencia con ~40 laterales por persona, no un bucle PL/pgSQL. A 3 años con 60 personas: ~150 ms. Sin objeción.

**Los dos índices que importan existen.** `idx_marcajes_persona_dia (persona_id, timestamp_marca)`, su gemelo parcial `idx_marcajes_vivas … WHERE anulada_at IS NULL`, `idx_marcajes_sede (sede_id, timestamp_marca)`, `idx_marcajes_fecha_jornada (persona_id, fecha_jornada)`, `jornadas_persona_id_fecha_key (persona_id, fecha)`, `idx_jornadas_fecha`, `idx_jornadas_sede (sede_id, fecha)`. La pregunta del frente sobre `marcajes(persona_id, timestamp_marca)` y `jornadas(persona_id, fecha)` está respondida: están.

**El terminal —el camino más caliente del sistema, que corre en cada refresco de la Mac mini— resuelve en 0,86 ms con 225.120 marcajes.** `apps/web/lib/terminal/estado-dia.ts:56-68` pide una ventana de 48 h sin filtro de persona; el planificador entra por `idx_marcajes_sede`, 370 buffers, `Index Scan`. Sin objeción.

**El volumen a 3 años …

**diseno** — Mire y encontre bien hecho, y lo digo porque importa tanto como lo roto:

EL TERMINAL EN SUS CAMINOS DE FALLO ES EJEMPLAR. `marcar/page.tsx:358-380` distingue «este equipo no termino de configurarse y tu marca NO quedo registrada» de un exito, y lo dice con esas palabras; `:418-460` separa «el servidor la rechazo» de «no llegue a preguntarle», que son dos frases distintas porque son dos verdades distintas; `:401-416` guarda en IndexedDB ANTES de intentar el envio, con el comentario que explica el fallo real que eso corrigio. Y `components.tsx:345-365` documenta por que un rechazo se pinta en rojo con simbolo y mas segundos que un «Listo»: «en una pantalla que se limpia sola, lo que distingue una buena noticia de una mala es sobre todo el color». Los badges de cola pendiente, marcas apartadas y desfase de reloj estan jerarquizados a proposito y cada uno dice que hacer. Eso es diseno de estados, no decoracion.

LA PALETA ESTA MEDIDA Y LOS TRES COLORES SAGRADOS PASAN. tinta/crema 15.36:1, rojo/crema 4.83:1, taupe/crema 5.21:1, ambar y verde 4.51:1 — verificados con la formula de luminancia sobre los valores de globals.css de hoy. La decision de no usar sombras ni gradientes, y de elevar con papel sobre crema, es lo que impide que esto parezca un panel generico. No lo tocaria nadie.

LAS CONFIRMACIONES DE PLANILLA SON EL MODELO A COPIAR. `planilla/page.tsx:1109-1114` explica que ma…

---

## 9 · Lo que se cayó al verificarlo

**19 hallazgos murieron en verificación.** Van aquí con nombre porque un informe que solo enseña lo que sobrevivió no deja comprobar su propio criterio — y porque cada uno es una alarma que NO vas a recibir.

- **En la pantalla de Normas, crear un tipo de documento escribe la tabla directo mientras las otras cinco operaciones de es…** — No se sostiene en ninguno de sus tres pilares.

(1) EL CONTEO ES FALSO. La pantalla no es «seis por RPC y una que escribe la tabla». Tiene 5 `rpc()` y 4 `.from()`: apps/web/app/(admin)/admin/normas/page.tsx:298 (select documentos_tipos), :386 (insert), :390 (select), :452 (select documentos_acuses). El acceso directo a tabla es el idioma normal de esa pantalla, no una excepción solitaria.

(2) ES UNA DECISIÓN ESCRITA…
- **Un quinto cliente de Supabase armado a mano en /api/reabrir-dia, y el comentario que explica por qué existen las fábrica…** — Refutado en sus dos afirmaciones, con git.

(a) EL COMENTARIO NO ESTA DESACTUALIZADO. `git blame -L 55,75 packages/database/src/client.ts` sitúa las líneas 60-64 en el commit 4f0764d (2026-08-04). El diff de ESE MISMO commit migra espejo y cuentas de `createClient` a mano a las fábricas. O sea: la frase «las tres rutas armaban su propio cliente a mano» se escribió en el commit que dejó de ser cierto, a propósito y en…
- **La liquidación por cese se imprime «sin diferencias» cuando la consulta que las busca falló** — El mecanismo citado es literalmente cierto —`dif.error` nunca se mira en page.tsx:133, solo `liq.error`— pero la consecuencia que sostiene el hallazgo («la pantalla no lo dice», «la diferencia no la ve nadie») queda refutada por tres comprobaciones propias.

(1) UNA CAPA MAS ABAJO YA LO PROTEGE, y no se puede esquivar. `fn_liquidaciones_pendientes` calcula `descuadra` en el servidor con la MISMA funcion. Verificado c…
- **Cuatro maneras distintas de contestar «esta consulta no respondió», y la buena vive en una sola pantalla del panel** — Las citas son literalmente exactas, pero la tesis causal —«la buena vive en una sola pantalla porque nadie la adoptó»— la refuta git. `apps/web/lib/admin/lo-que-no-se-pudo.ts` nació el 2026-08-10 en el commit 79fc6ec, que tocó CUATRO archivos: el helper, sus pruebas, reporte-sede y dashboard. El diff muestra que `discNoRespondio` —el ejemplo estrella del «booleano ad hoc reinventado»— se agregó EN ESE MISMO COMMIT, p…
- **`mensajeDeError` traduce el error de Postgres en 19 archivos y otros 14 lo pintan crudo, incluida la pantalla de la cola…** — El inventario es exacto, pero el mecanismo de daño es empiricamente falso y en la pantalla que el hallazgo llama "la peor" el arreglo propuesto es un no-op.

LO QUE SI COMPROBE (a favor del hallazgo): mensaje-error.ts existe tal como se describe; `grep -rl` da 19 archivos que lo importan y 13 que usan `.message` crudo sin importarlo (12 pantallas + api/espejo, que es maquina a maquina y devuelve generico a proposito,…
- **«¿Le tocaba trabajar ese día?» tiene dos respuestas en SQL, y la que llega a la tardanza ignora dias_laborables** — La asimetría de código es cierta y la comprobé: en supabase/migrations/0249_una_salida_real_siempre_se_puede_registrar.sql:223-226 la rama legacy hace `v_hora_entrada_prog := v_hora_entrada_legacy;` sin mirar dias_laborables, y las líneas 236-239 escriben minutos_tarde con eso; fn_tardanza_es_medible instalada es solo `select p_minutos is not null and p_minutos <= 180`; fn_tardanzas_resumen cuenta `j.minutos_tarde > …
- **Desempeño (`/admin/horas`) escribe justificaciones sin ninguna comprobación de rol en la pantalla** — Los hechos literales del archivo son ciertos (0 referencias a permisos.ts, solo getSession en :531-533, escrituras en :818-820, nav.tsx:47 con roles: SEDE), pero el hallazgo se cae por cuatro comprobaciones propias. (1) La capa de abajo lo cierra entero: dumpeé pg_get_functiondef y fn_levantar_tardanza abre con v_editor := fn_verificar_corrector(p_persona_id), y fn_set_justificacion delega en fn_registrar_ausencia, q…
- **`/admin/exportar` es el único enlace del menú sin `roles` ni motivo escrito, y la pantalla tampoco comprueba nada** — Refutado con lectura directa de los tres archivos. (1) El daño que alega —«el archivo no dice en ninguna parte que está recortado por permisos»— lo desmiente el propio archivo que el hallazgo leyó: apps/web/app/(admin)/admin/exportar/page.tsx:121-124 dice en pantalla, justo bajo el botón, «Incluye a todas las personas y sedes visibles para tu rol.» El hallazgo citó las líneas 24-26 y 29-38 de ese mismo archivo de 128…
- **El mismo rol tiene tres etiquetas distintas en pantalla, y dos roles con permisos muy distintos se llaman los dos «Líder…** — Las citas son literales y las verifiqué una por una, pero el mecanismo del hallazgo queda refutado por cuatro comprobaciones propias. (1) La evidencia del propio hallazgo lo contradice: ROL_LABEL en cuentas/page.tsx:44-47 pinta supervisor_sede como «Encargada» y lider_do como «Líder DO» — dos textos inconfundibles, así que releer Cuentas SÍ delata el error, al revés de lo que afirma el escenario. (2) La pantalla del …
- **Las plantillas de disciplina y el borrador de RIT v3.2 están en masculino y usan «jefatura», contra el art. 3.1 del RIT …** — Las citas literales son exactas, pero el mecanismo de daño del hallazgo está refutado por los propios archivos.

(1) El RIT vigente es la **v4.0** del 10-ago-2026 (`reglamento-interno-de-trabajo.md:2519`), que «deroga y sustituye íntegramente al RIT versión 3.0 (junio de 2026) y a cualquier versión anterior» (`:2525`). El contenido entero del 08 YA ESTÁ absorbido en ella y reescrito en femenino: art. 9 (JORNADA ORDIN…
- **«Supervisor» sobrevive en la prosa de seis migraciones y de la auditoría de julio, y el CLAUDE.md no dice qué hacer con …** — No sobrevive. Cuatro comprobaciones independientes lo tumban.

1) EL TITULO ES FALSO. CLAUDE.md SI dice que hacer con la prosa: linea 124 (tabla: «lider de equipo, encargada de sede | jefe, supervisor») y lineas 129-130 («El codigo tiene el rol supervisor_sede en la base por historia; en pantalla y en PROSA siempre es encargada»). Y tambien fija el metodo para prosa vieja en documentos congelados: CLAUDE.md:7-9 («Ojo…
- **Los factores de provisión son la única tasa que decide plata y sigue sin fecha — y el propio código dicta el UPDATE que …** — REFUTADO por la capa de abajo, medido por mí en BEGIN … ROLLBACK contra el Postgres local (ROLLBACK verificado: planilla_provisiones intacto, personas/movimientos/desembolsos = 0).

Lo que el hallazgo acierta: fn_provisiones de la 0196 es la vigente (donde-vive.sh lo confirma), fn_grati_cts_periodo (0088) sí es un envoltorio que devuelve cts_may/grati_s1 tal cual, configuracion no tiene columna de vigencia (clave|val…
- **La foto del pago no guarda de qué días salieron las horas ni de qué tramo salió el sueldo** — REFUTADO. Las observaciones son ciertas; el daño que afirma, no.

1) LA PREMISA CENTRAL ES FALSA. El hallazgo dice que la reconstrucción va "contra `jornadas`, que es una tabla derivada, sin versión y sin historia" y que la v1 se pierde porque "sus horas dependen de unas jornadas que entretanto se recalcularon". El vigente `fn_recalcular_jornada` (donde-vive.sh → 0249; md5 local c50fa2ed18d61ef7ad304fd554fba4cc) llev…
- **Tres rastros que dicen menos de lo que parecen: un autor que no se puede sostener, una hora que cambia sin fila y unas c…** — Comprobé las tres partes contra el cuerpo VIGENTE en el Postgres local (donde-vive.sh: fn_reabrir_dia→0137 md5 8730c7a1…, fn_registrar_marcaje→0240 md5 995c976d… coincide con la base, fn_eliminar_marcaje→0188). Los tres hechos de código son literalmente ciertos. Las tres consecuencias no sobreviven.

(a) REFUTADA — está documentada y decidida. El encabezado de la 0137 lo dice con esas palabras al justificar el rastro…
- **No hay auditoría de lectura en ninguna parte, y el padrón con DNI, direcciones y cuentas se descarga sin dejar rastro** — Los hechos técnicos son ciertos y los comprobé yo mismo: la única tabla de auditoría en `public` es `correcciones_auditoria` (consulta sobre pg_tables con los patrones auditor/bitacor/log/historial/evento/acceso/descarg/export); `datos_personales`, `derechohabientes` y `asignaciones_salario` no tienen ningún trigger no interno y `personas` solo tiene `trg_personas_updated_at` y `trg_educacion_cerrar_al_cesar`; las co…
- **fn_set_datos_personales tiene dos sobrecargas vivas, las dos ejecutables por cualquier sesión autenticada** — Los DATOS del hallazgo son ciertos, pero su MECANISMO DE DAÑO es falso, medido, y el hecho ya está escrito en el repo con nombre y apellido.

QUÉ CONFIRMÉ (y no discuto)
- Existen las dos sobrecargas en el Postgres local: oid 20006 con 18 argumentos y oid 20420 con 19 (…p_discapacidad_conadis text, p_cuspp text). Las dos `prosecdef=t` y las dos con el mismo ACL: `postgres=X/postgres | service_role=X/postgres | authen…
- **turnos no tiene índice por fecha sola, y las tres pantallas que lo consultan por rango filtran solo por fecha** — REFUTADO por medicion propia (BEGIN...ROLLBACK contra Postgres local, rollback verificado: turnos queda en 0 filas y con sus 3 indices originales).

LO QUE SI ES CIERTO: turnos tiene solo turnos_pkey, turnos_persona_id_fecha_key e idx_turnos_persona_fecha, los tres encabezados por persona_id (supabase/migrations/0013_turnos_por_dia.sql:17). Los tres call sites citados existen y filtran solo por fecha: apps/web/app/(a…
- **Si el tablero de Documentacion no carga, la pantalla afirma «nada pendiente» — no distingue «esta todo firmado» de «no p…** — Refutado en la propia línea que cita. Las dos frases que el hallazgo presenta como «lo que se pinta» —`:1727` «nada pendiente» y `:1790` «Nadie tiene el cargo pendiente»— están anidadas DENTRO de `{tablero.length > 0 && (` en `apps/web/app/(admin)/admin/documentacion/page.tsx:1619`, cerrado en `:1801`. Verificado por indentación: 1619 abre a 10 espacios, 1620 `<div>` a 12, 1723 `<details>` a 14, 1787 a 22, 1800 `</di…
- **No hay documento de identidad de marca en el repo: el codigo cita «el manual v3.0» que no existe aqui, y el unico docume…** — Los hechos literales se confirman (marca.tsx:2 y globals.css:52 citan un manual ausente; plan-diseno-2026-07-27.md no está en la tabla), pero el hallazgo se cae en sus tres pilares. (1) «La definición del sistema visual son 22 líneas de comentario dentro de @theme (globals.css:4-21)» es falso: ese rango son 18 líneas con 11 declaraciones --color-*/--font-* y solo 5 líneas de comentario. Esas variables son código que …

---

## 10 · Eje diseño, estética y flujo

No hay sistema de diseño del producto, así que aquí no se audita contra un estándar: se audita su
ausencia. Y el código lo dice él mismo — `marca.tsx:2` y `globals.css:52` citan «el manual v3.0»,
que **no está en el repositorio**.

**El número es el diagnóstico.** Contado sobre el código, no opinado:

| Qué | Cuántos hay | Cuántos debería haber |
|---|---:|---:|
| Tamaños de texto | **15** (5 en píxeles a mano, 71 usos) | 6 |
| Valores de color distintos | **84** sobre 9 tokens declarados, más 64 usos de familias ajenas a la marca | 9 + 4 |
| Radios | 8 | 3 |
| Pasos de espaciado | 17 | 6 |
| Sombras | 2, y contradicen la regla escrita en `globals.css:6` | 0 |
| Botones escritos a mano | **288** | 1 componente |
| Copias del bloque de aviso | **33** | 1 componente |

Ninguno de los 6 componentes que existen es un botón ni un aviso.

**El veredicto del eje: el sistema visual está bien pensado y mal defendido.** Vive en 22 líneas
de comentario dentro de `@theme` y cita un manual ausente. Ya hubo una auditoría de diseño en
julio de 2026 en este mismo repositorio: **se aplicaron sus tres variables de color y sus puntos
3, 4 y 5 siguen intactos**, y el guardián que ella misma pidió nunca se construyó. Es el mismo
patrón que en el eje de arquitectura: el criterio se escribe, no se verifica, y vuelve.

### Lo que aquí puede costar plata no es el color: son cuatro silencios de flujo

1. **El error de guardar se pinta debajo del velo del modal**, en Horarios y en Correcciones. La
   encargada cambia un horario, algo falla, el aviso aparece tapado: ella cree que guardó.
2. **La fecha legal de la comunicación de cargos se teclea libre en un `window.prompt`**, y si
   sale mal congela la fila. Es una fecha con consecuencias legales entrada por el peor control
   que existe.
3. **Documentación afirma «nada pendiente» cuando en realidad no pudo preguntar.** Es el mismo
   defecto que la Hoja de sede ya tuvo y que `lo-que-no-se-pudo.ts` corrigió — aquí no se aplicó.
4. **«Nuevo PIN» mata el PIN al primer clic y muestra el reemplazo fuera de la pantalla.** Sin
   confirmación y sin deshacer: la persona se queda sin poder marcar y nadie ve el número nuevo.

Los cuatro son hallazgos **del diseño**, nunca de «falta capacitación».

### Propuesta de sistema en tokens

Derivada de lo que el repositorio **ya usa**, no de una plantilla. Es propuesta, no implementación.

**Tipografía** — se quedan las dos familias declaradas (DM Sans / EB Garamond). Seis pasos en vez
de quince: `dato` 2rem serif · `titulo` 1.25rem serif · `cuerpo` 0.9375rem (593 usos, sube de 14 a
15 px) · `apoyo` 0.8125rem (498 usos, sube de 12 a 13 y absorbe los `text-[12px]` y `text-[13px]`)
· `etiqueta` 0.7rem con `tracking .16em` (la clase ya existe en `globals.css:53`). **Nada por
debajo de 12 px**: se retiran `text-[9px]`, `[10px]` y `[11px]` — 65 usos.

**Espaciado** — seis pasos: 2 / 4 / 6 / 8 / 12 / 16 px. Las escalas que ya concentran 3 100 de los
3 200 usos. Se retiran 10, 12, 16, 20 y 24.

**Color** — los 9 tokens actuales se quedan: sus contrastes están medidos y pasan (tinta 15.36 ·
rojo 4.83 · taupe 5.21 · ámbar 4.51 · verde 4.51 sobre crema). Se **agregan tres fondos sólidos**
—`ambar-fondo`, `verde-fondo`, `rojo-fondo`— porque pintar el ámbar sobre `bg-ambar/15` lo
devuelve a **3.74 y deja de cumplir**. Más un `taupe-tenue` explícito para guiones y bordes. Dos
reglas: **la opacidad no se usa nunca sobre palabras**, y las familias de Tailwind (slate, amber,
red, emerald, neutral), el blanco puro y el negro absoluto quedan prohibidos — `globals.css:6` ya
lo dice y el código lo incumple 64 + 25 veces.

**Radio** — tres: 3 px badges, 8 px por defecto (437 usos), 16 px paneles (81). `rounded-full`
solo para el pill del selector de sede.

**Elevación** — ninguna. Es la decisión correcta y ya está tomada: papel sobre crema y línea Sand.
Los 2 `shadow-xl` se van.

**Estados** — cada superficie que carga declara los cinco, y los cinco ya existen sueltos en el
repositorio: cargando (`<Cargando/>`, 27 pantallas) · vacío con pista de qué hacer · **no cargó,
distinto de vacío** (el patrón está en `correcciones/page.tsx:138` y falta en Documentación) · sin
permiso (17 pantallas) · sin conexión (solo el terminal, y está bien que sea así).

**Componentes base, en este orden** — `<Boton>` con tres variantes y **altura mínima de 44 px en
el terminal**, que se toca con el dedo · `<Aviso>` con `role="status"`/`"alert"` que se dibuja
**donde está la mano**, dentro del modal si el modal está abierto · `<Modal>` con `role="dialog"`,
Escape y foco atrapado, copiado de `horas/page.tsx:1091` que ya lo resolvió · `<CampoFecha>` que
jubila los `window.prompt`.

---

## 11 · Antes de escribir «listo» — las tres preguntas

**1 · Concurrencia: ¿qué pasa si dos escrituras llegan al mismo registro en el mismo milisegundo?**

Medido con dos sesiones concurrentes reales contra el Postgres local, ambas con `ROLLBACK`
verificado. El cierre de planilla **sí** toma `for update` sobre la fila del periodo, así que dos
cierres simultáneos se serializan y **no paga dos veces** — la pregunta que sola justifica la
auditoría tiene respuesta buena. El único punto donde las dos mitades no se tocan es entre
`fn_liquidacion_pagar` y `fn_planilla_congelar`: se protegen cada una de su propio doble clic y de
nada más (`RowShareLock` y `RowExclusiveLock` no chocan; medido en `pg_locks`). Está reportado como
P3 y no como algo peor por una razón concreta: **el dinero saldría mal, pero no saldría callado** —
la pantalla de Planilla seguiría pintando el aviso en ámbar.

**2 · Caída externa: ¿qué pasa si la dependencia externa no responde hoy?**

Solo hay dos, Supabase y Sentry. El terminal es el caso que importa y **está resuelto por diseño**:
`enviar-marcaje.ts` tiene tope de 8 segundos, nunca lanza, y distingue «no llegó» de «llegó y
falló» — un tiempo agotado **no** cuenta contra el tope de descartes. La marca se encola antes de
intentar enviarla. Si Supabase no responde, la sede sigue marcando. Sin objeción. Lo que **no**
está resuelto es el arranque en frío sin internet: no hay service worker ni manifest en `public/`,
así que un reinicio de la Mac mini sin red deja la sede sin poder marcar (hallazgo A14, abierto).

**3 · Persona sin contexto: ¿alguien sin formación técnica completa el flujo sin que le expliquen?**

**Marcar entrada: sí** — es el flujo mejor diseñado del sistema y no deja elegir «entrada» o
«salida», así que no hay nada que equivocar. **Corregir un marcaje: no** — si el guardado falla, el
aviso se pinta debajo del velo del modal y la encargada se va creyendo que guardó. **Cerrar
planilla: no del todo** — el aviso de quien cesó a mitad de mes existe y funciona, pero exige saber
leer un ámbar que no dice qué apretar.

---

## 12 · El cierre

### EL TRABAJO

Se auditó el monorepo completo: `apps/web` (35 pantallas de administración, el terminal, `/mio`, 4
rutas de API), `packages/shared`, `packages/database`, las 248 migraciones y los 131 archivos de
pruebas pgTAP. 116 agentes en dos tandas, cada hallazgo con un verificador adversarial detrás. Todo
medido contra el Postgres local dentro de `BEGIN … ROLLBACK`; cero escrituras.

**Quedó fuera** lo que no existe en este repositorio y el encargo daba por hecho: stock e
inventario, multi-tenant, y las integraciones Culqi, Nubefact/SUNAT y Shopify. Y quedó fuera
**producción**: esta máquina no tiene acceso, así que ninguna cifra de alcance de la §7 es un
número de producción. Los detectores están escritos y probados; hay que correrlos allá.

### LA OBJECIÓN

**El sistema usa RLS como si filtrara columnas, y RLS filtra filas.**

No es un fallo de implementación: es la concepción. La tabla `personas` guarda en la misma fila la
identidad operativa —nombre, apellido, sede, rol— y los datos sensibles: DNI, correo, celular,
`sueldo_base_legal`, régimen de pensión. Cualquier política que deje ver la fila para mostrar un
nombre entrega también el sueldo.

El kiosco de marcaje es el caso extremo y el más visible —pide cuatro campos y el token alcanza
todos—, pero no es una excepción: es lo que va a volver a pasar. Cada pantalla nueva que necesite un
nombre y una sede abrirá otra vez el DNI y la remuneración, y la única defensa será que alguien se
acuerde de acotar las columnas en el cliente. Eso no es una defensa: es una costumbre.

El trade-off, nombrado: separar `personas` en identidad operativa y datos sensibles cuesta una
migración grande y toca muchas consultas; a cambio, se deja de tener que acertar en cada política
nueva, y el error deja de ser posible en vez de ser improbable. Es exactamente el movimiento que
este repositorio ya sabe hacer y tiene escrito en su propio criterio: *«qué `if` de caso borde
desaparecería con un cambio de estructura de datos»*.

### LO QUE NO PIDIÓ

**La red de seguridad de este repositorio verifica la numeración de las migraciones, los tipos y
las pruebas. No verifica ni una sola de las reglas de criterio que el propio `CLAUDE.md` declara.**

Ese es el hallazgo de mayor consecuencia, y no está en ninguna lista porque no es un defecto: es el
mecanismo por el que todos los demás vuelven. Las diez comparaciones de rol contra literal existen
**a pesar** de que la regla está escrita, y la regla se escribió tras juntar 35 copias. «Qué le
tocaba trabajar ese día» está escrito cuatro veces **a pesar** de que el documento dice que hay dos
y prohíbe expresamente una tercera. La auditoría de diseño de julio pidió un guardián y el guardián
nunca se construyó, y por eso hay 84 colores sobre 9 tokens.

El `CLAUDE.md` de este repositorio es de lo mejor que se puede leer en un proyecto de este tamaño.
Y hoy funciona como **memoria**, no como **guardián** — y la memoria de un equipo con cuatro
sesiones trabajando en paralelo dura lo que dura una tarde con prisa.

Un `grep` en el hook de pre-push que falle si aparece `rol ===` fuera de `permisos.ts`, o
`"America/Lima"` fuera de `fecha-lima.ts`, cuesta veinte líneas y convierte tres páginas de prosa
excelente en algo que se cumple solo. Es el lote de mayor retorno del plan, y el único que evita
volver a escribir este informe dentro de seis meses.

*(Y una nota que este informe se ganó a pulso: se perdió entero el 2026-08-18 por quedar sin
commitear en un árbol compartido. La regla que faltaba no era de código.)*
