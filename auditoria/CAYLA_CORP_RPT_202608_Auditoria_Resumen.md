# Auditoría CAYLA Dynamic — lo que hay que saber en cinco minutos

**2026-08-17** · 116 agentes, cada hallazgo con un verificador independiente encargado de
refutarlo. **De 99 hallazgos propuestos, 19 murieron ahí.** Quedaron **80: 4 P0, 8 P1, 29 P2, 39 P3** — de los que **uno se corrigió a la baja el
2026-08-18 al leer el código con calma; ver el punto 2**.

---

## El veredicto en una línea

**El sistema calcula bien y protege mal.** El núcleo del pago resistió el ataque —no hay dinero en
coma flotante, el cierre no paga dos veces, el candado de mes pagado funciona, y desde un monto se
puede llegar a los marcajes que lo originaron—. Lo que está por debajo del mínimo es **quién puede
ver qué**.

| Eje | Dónde está |
|---|---|
| Integridad arquitectónica | camino a clase mundial |
| Performance y escala a 3 años | **clase mundial** — a 10× no se despeina |
| Seguridad | **por debajo del mínimo** — los 4 P0 están todos aquí |
| Corrección de negocio | profesional sólido |
| Diseño y flujo | profesional sólido |

---

## Los cinco que importan

**1 · Hay DNI, correos y celulares de diez personas publicados en GitHub.** `P0`
En `0130_los_datos_del_tregistro.sql` y dos migraciones más. Su encabezado además narra hechos
personales con nombre y apellido. El `CLAUDE.md` tiene la regla escrita —«datos personales fuera de
git»— y se incumplió tres veces. Ya está publicado: borrarlo hoy no lo despublica.

**2 · El motor de tardanzas cuenta feriados y vacaciones como tardanzas.** `P2`
`fn_faltas` aplica seis exclusiones antes de contar; `fn_tardanzas_resumen` mira los mismos días
con otro criterio.

→ **CORREGIDO el 2026-08-18, y la corrección es contra mí.** Este informe decía que el motor de
tardanzas «no aplica ninguna» exclusión y lo clasificaba como P0. **Es falso.** Leído el cuerpo
vigente, aplica cuatro: quién es medible (`activo`, `en_planilla`, `not sueldo_fijo`), las
tardanzas de más de tres horas (`fn_tardanza_es_medible`), lo ya sancionado (el corte del no *bis
in idem*), y **lo justificado a mano** (`tardanzas_justificadas`). Lo que le falta son las
exclusiones de calendario.

→ **Y ya estaba catalogado antes de esta auditoría**, como **A4** en
`docs/hallazgos-abiertos.md`, con una descripción más exacta que la de este informe. La 0200 lo
dejó abierto expresamente: *«Tampoco toca los feriados. El hallazgo nº4 sigue abierto… Esta
migración hace que esas tardanzas se vean ANTES, lo que aumenta el valor de cerrar el nº4 — no lo
sustituye.»*

→ **MEDIDO EN PRODUCCIÓN el 2026-08-18: cero memos emitidos, y CERO falsos positivos.**
El detector encontró dos jornadas en toda la historia, y al mirarlas una por una **ninguna de las
dos es un error del sistema**:

- **Janis Revilla**, 28/07, 53 minutos → **tardanza de verdad**. Ese día la tienda de Trujillo
  abrió con dos turnos: cinco personas entraron entre 07:43 y 08:14, y tres por la tarde. Janis
  entró **14:38** y su hora de ese martes era **13:45** — la resta da exactamente 53. El sistema
  no la midió contra su hora de mañana: usó su horario del día, que es lo correcto.
- **Rufina Salvatierra**, 06/08, 2 minutos → ya cesó; no cuenta para nada.

**Conclusión: A4 no se corrige.** El defecto que describe —que el motor mide puntualidad en
feriados— resulta ser el comportamiento CORRECTO cuando la tienda abre en feriado con sus horarios
normales, que es lo que pasa en Trujillo. Excluir los feriados taparía tardanzas reales.

**Y la señal que se pensó usar no sirve**: medido, **22 de 25 feriados trabajados no tienen ni un
turno registrado**. «Feriado sin turno» no significa «no era su día»; significa «nadie registró
turnos», que es casi siempre. Si eso se hubiera usado como criterio de exclusión, habría dejado de
contar tardanzas en prácticamente todos los feriados.

Lo que **sí** queda en pie, y es preventivo porque no tiene ningún caso hoy: que una tardanza no
pueda contarse en un día de vacaciones aprobadas, descanso sustitutorio o suspensión cumplida.

*(Nota de método, contra mí: llegar aquí costó cuatro consultas y dos hipótesis falsas. Una de
ellas —que los datos eran una carga masiva— salió de leer `entrada_ts::time` sin convertir a hora
de Lima, y ver «12:43» donde eran las 07:43. Propuse una explicación sobre un dato mal leído, que
es exactamente lo que el CLAUDE.md prohíbe.)*

**3 · El kiosco de marcaje puede leer el DNI, el correo y la remuneración de todo su equipo.** `P0`
La política deja al terminal seleccionar filas completas de `personas`. RLS filtra **filas, no
columnas**: el código pide cuatro campos, pero el token alcanza todos. Y ese token vive en una Mac
mini a la vista de todo el equipo.

**3-bis · El régimen de pensión se cambiaba por la puerta sin candado.** `P1` — ✅ **YA ARREGLADO**
Lo cerró la **0277**, aplicada en producción el 2026-08-23 por otra sesión. Su cabecera describe el
mismo defecto que este informe: `fn_set_regimen_pension` hacía un `update` y nada más, y
`fn_cambiar_regimen_pension` —la que sí escribe el tramo versionado— no la llamaba nadie.
✅ **Y desde el 2026-08-25 también está en `main`.** Estuvo dos días corriendo en producción sin
estar en el repositorio —el patrón de la 0177— y se cerró fusionando la rama. Verificado por md5
contra producción: `ed01ed0f903bf13800d3cf282919abe8`, idéntico, comentarios incluidos.

**4 · Once funciones `SECURITY DEFINER` entregan datos de cualquier persona a cualquier sesión.**
`P0` · **desde el 2026-07-21**
Reciben un `persona_id` de quien llama y no preguntan quién llama. Alcanzan datos disciplinarios y
de beneficios de las cuatro sedes.

**5 · Un descanso médico paga sin que Desarrollo Organizacional lo apruebe.** `P1`
Los dos laterales que pagan ausencias miran `anulada_at` y nunca `aprobada_at`. Y una encargada de
sede puede registrarlo.
→ **MEDIDO EN PRODUCCIÓN el 2026-08-18: no le costó un sol a nadie.** Los dos únicos registros son
de descanso médico de Paola Cahuana (6 y 7 de julio), los hizo Felipe, y la foto del pago de julio
se congeló **antes** de que existiera el concepto — `la_foto_conoce_el_concepto = false` en las tres
versiones. Pasa de «ya ocurrió» a **puerta abierta por la que no entró nadie**.

---

## Qué hacer el lunes

1. **Correr los tres detectores que faltan** de la §7 del informe en el SQL Editor. Son `SELECT` de
   solo lectura, ya escritos y probados. El cuarto —el del descanso médico— ya se corrió.
2. **Cerrar el hueco del descanso médico** (en curso; ver el plan de remediación).
3. **Decidir qué hacer con los datos ya publicados en GitHub.** No es una tarea de código: es una
   decisión sobre el historial del repositorio.
4. **Tapar las tres fugas de lectura** (terminal, funciones `SECURITY DEFINER`, ascenso a Admin).
5. **Encender el linter** — 119 errores esperando — y **subir Next a 16.2.11**.

---

## Las dos cosas que este informe dice y no están en ninguna lista

**La objeción.** El sistema usa RLS como si filtrara columnas, y RLS filtra filas. `personas` guarda
en la misma fila el nombre y el sueldo. Cada pantalla nueva que necesite un nombre volverá a abrir
el DNI y la remuneración, y la única defensa será que alguien se acuerde de acotar columnas en el
cliente. Eso no es una defensa: es una costumbre.

**Lo que no se pidió.** La red de seguridad verifica numeración, tipos y pruebas. **No verifica ni
una sola de las reglas que el propio `CLAUDE.md` declara.** Por eso volvieron las diez comparaciones
de rol que una regla existe para evitar, por eso «qué le tocaba trabajar ese día» está escrito
cuatro veces cuando el documento prohíbe una tercera, y por eso la auditoría de diseño de julio
pidió un guardián que nunca se construyó.

Ese `CLAUDE.md` es de lo mejor que se puede leer en un proyecto de este tamaño. Hoy funciona como
memoria, no como guardián — y la memoria de un equipo con cuatro sesiones en paralelo dura lo que
dura una tarde con prisa. Veinte líneas en el hook de pre-push convierten tres páginas de prosa
excelente en algo que se cumple solo. Es el lote de mayor retorno, y el único que evita volver a
escribir este informe dentro de seis meses.
