# Dynamic — Estado y pendientes

**Este es el único archivo de estado.** Se sobrescribe al avanzar; no se crean
copias con fecha. Lo ya cerrado vive en [`historico.md`](historico.md). Cómo se
trabaja: ver [`CLAUDE.md`](../CLAUDE.md) en la raíz.

---

## 2026-10-31 — El practicante se paga sobre 30 h, y los parámetros de pago dicen quién los cambia y desde cuándo · migraciones 0571 (fusionada en [#626](https://github.com/felipea92p-ux/cayla-dynamic/pull/626)) · **0573 PEGADA** · **0575 PEGADA** · **0576 SIN PEGAR (por hora con tope semanal)** · 0574 SIN PEGAR · PRs [#629](https://github.com/felipea92p-ux/cayla-dynamic/pull/629) y [#630](https://github.com/felipea92p-ux/cayla-dynamic/pull/630) · rama `claude/amazing-albattani-kjo4f3`

**De dónde sale.** Felipe (2026-10-31): el pago de los practicantes no calzaba con sus horas. Tras simular base 45 y base 30
(`scripts/sql-manual/simular_el_tope_de_horas_de_los_practicantes.sql` y `horarios_y_horas_marcadas_de_los_practicantes.sql`,
solo lectura) decidió: **«el cambio es solo para el tipo de vínculo practicante, mantiene todos sus beneficios, solo la fórmula de su
sueldo cambia, que es en base de 30 horas»**, y que los números que pueden cambiar con el tiempo vayan a Parámetros, **solo admin**.

**0573 · la fórmula (la que mueve plata).** Para `tipo_vinculo = 'practicante'` (las dos modalidades): hora = subvención pactada ÷
(horas pactadas × días ÷ 7), con horas pactadas = 30, o las de su convenio **firmado** si pactó menos (la menor si hay varios); lo
marcado por encima no se paga (tope por sus días activos). Planilla, RxH y todo lo demás, igual al céntimo. Medido en un periodo de
28 días con S/ 1 230: 17 h/sem → 697.00 (antes 459.56); 25.5 h/sem → 1 045.50 (antes 689.34); 30 h o más → 1 230.00. Con convenio
firmado de 17 h por S/ 697: cumplirlo → 697.00. Por qué «subvención pactada» y no «1 230 × h ÷ 30»: el convenio promete por escrito
la subvención cargada; multiplicar otra vez por h ÷ 30 pagaría la proporción dos veces (S/ 395 en vez de 697). **md5 de partida
pedido a producción ANTES de escribir** (`aad8a0f0…`, 121 868 car., = 0555). Dos guardias: otra versión de la función, o un
practicante con subvención bajo la RMV sin convenio firmado → **PARA**. Prueba 463 (19); dos mutaciones la ponen en rojo.

**Lo que hay que saber ANTES de pegar la 0573.** Rige con los horarios que haya ese día, y con base 30 cada hora vale 1.5 veces lo
que valía. Un horario de 25.5 h/sem pasa de ≈ S/ 689 a S/ 1 045.50; uno de 17 h (11:20–18:00 con 1 h de almuerzo, 3 días) paga
S/ 697; uno de 45 h/sem llega al tope. **Conviene ajustar los horarios ANTES de pegarla**, o el primer periodo sale más caro. Abierto para el laboralista: el feriado del practicante (art. 42.4) y si pagar por
horas marcadas cumple el art. 45. Y Felipe pausó la sesión de la tarjeta vieja «Migración: pago fijo proporcional del preprofesional»
(diseño anterior, valores fijos en la función): no debe retomarse.

**0571 y 0574 · Parámetros (no mueven plata).** 0571: `roles_cambia` por parámetro (los de hoy conservan su comportamiento; uno nuevo
nace `{admin}`). 0574: la clase plata guarda su valor **por fechas** (`parametros_vigencias`, `fn_parametro_valor_en`), se cambia con
`fn_parametro_cambiar_vigencia` (se niega a una fecha dentro de un periodo pagado para su grupo) y tiene vista previa. Todavía no
existe ningún parámetro de plata y la planilla no lee ninguno: conectar la base de 30 h a un parámetro es el paso siguiente.
md5 de partida de la 0571 contrastado con producción. Pruebas 461 (16) y 464 (21).

**Cómo se midió.** Sin Docker: un Postgres 16 con stubs de Supabase y las 570 migraciones. Suite pgTAP completa contra un **control**
(la misma base sin 0573 ni 0574): ninguna prueba que pasaba dejó de pasar; las 40 que fallan en las dos son del entorno (stubs de
storage/auth/cron), y la única que toca planilla (217) pasa con la 0573 una vez completado el stub. `db-tests` de GitHub es la señal fiable.

**Lo que pasó con los números (2026-10-31).** El PR #626 se fusionó a las 16:44 con la cuenta de Felipe llevando **solo la 0571**
(y los scripts de simulación); minutos después la PR #627 tomó la **0572** y la prueba **462** («la invitación a la cuenta sale sola»).
La migración de parámetros con fechas, escrita como 0572, pasó a **0574** (prueba 464) sin haberse pegado nunca con el número viejo, y
la rama se rehízo desde `main`. La pantalla de Parámetros publicada con el #626 funciona sin la 0571 pegada (cae a la regla por clase).

**0573 PEGADA por Felipe el 2026-10-31.** Antes de pegar, el md5 de producción se volvió a pedir en el mismo mensaje de la entrega y
coincidió con la 0555 (`aad8a0f0…` / `2f73c7e9…`, 121 868). La fila final devolvió exactamente la esperada: `t · t · t · 1 · 125171 ·
8480448f341d0d6d424c4b31816878b2 · 0 · 3 · «573 · el_practicante_se_paga_sobre_una_base_de_30_horas»` (mismo md5 que el Postgres local:
se pegó sin `\r`). Rige desde ese momento sobre el periodo abierto (29-oct → 28-nov), con los horarios que haya.

**La 0573 salió mal en dos cosas, medidas en producción el mismo día, y la 0575 las corrige.** Felipe corrió la consulta del
periodo abierto y vio a los cuatro practicantes en base 30: **«lo que debe tener valor es la modalidad … lo que son pre profesional
cobran en base 30 y los egresados en base 45. Su tipo de vínculo de ambos es practicante»**, y **«que esto funcione desde este
periodo»**. La 0573 había tomado «el vínculo practicante» como las dos modalidades. Y su tope, prorrateado por días activos, a
quien tenía un solo día en el rango le pagaba 4.29 de 7.45 h. La **0575** (prueba 465): preprofesional → 30 h, egresado (modalidad
`profesional`) → 45 h, sin modalidad → como antes; tope del periodo entero; y **solo para periodos que empiezan el 2026-10-29 o
después** (el anterior, aunque se recalcule en vivo, sigue con la fórmula de antes). Parte de la 0573 tal como quedó en producción
(md5 `8480448f…`, devuelto por su propia comprobación); al pegarla debe dar `40748ba949e32789c06c48c8eac9fca8` (127 407).
Medido contra un control: ninguna prueba que pasaba dejó de pasar; cuatro mutaciones (sin modalidad, egresado en 30, tope por
días activos, sin fecha de inicio) ponen la 465 en rojo.

**0575 PEGADA por Felipe el 2026-10-31**, antes de fusionar el #630. Fila final exacta: `t · t · t · 1 · 127407 ·
40748ba949e32789c06c48c8eac9fca8 · 1 · 2 · 0 · «575 · la_base_del_practicante_la_decide_su_modalidad»` (1 preprofesional y 2
egresados activos, ninguno sin modalidad). La consulta de modalidades de ese momento confirma la regla persona por persona, y explica
el corte que se vio con la 0573: la practicante inactiva cesó el 2026-10-29, primer día del periodo, así que tenía un solo día activo.

**0576 (sin pegar): por hora sobre el sueldo mínimo, con tope SEMANAL.** Felipe (2026-10-31): base 30 por el sueldo mínimo, el
cálculo por hora, que dependa de los horarios que él pone; tope semanal 30 h para el preprofesional y 48 h para el egresado (base
45). Las horas del convenio ya no cambian la base, y la subvención se queda en el mínimo (la guardia se niega si alguna está por
debajo de la RMV). El tope por semana (lunes a domingo) reemplaza al del periodo, que recortaba a quien cumplía su jornada exacta
(≈ −S/ 175 al año, revisión de la 0573). Parte de la 0575 en producción (`40748ba9…`); al pegarla debe dar `7f9a8a8e…` (127 441).
Prueba 466 (13); la 463 y la 465 ajustan lo que cambia a propósito. Suite completa contra control: sin regresiones.

**Falta pegar:** la 0574 (se niega sin la 0571; antes, confirmar que la 0571 está). Para ver la fórmula en el periodo abierto, solo lectura:
`fn_planilla_calcular_nucleo(fecha_ini, fecha_fin, id)` del periodo de hoy, filtrando `base_horas_semana is not null` (la consulta va en
el mensaje del 2026-10-31).

## 2026-10-30 — Cinco migraciones que existían solo en ramas sin fusionar vuelven al repo · migraciones 0523 · 0545 (ya estaban pegadas) · **0546 PEGADA (2026-10-30)** · 0547 entregada · PR #620 · rama `claude/vigilant-hopper-d48cdd`

**De dónde sale.** El checkout principal llevaba 943 commits congelado desde el 27 de septiembre y `core.hooksPath` apunta a SUS
hooks: durante cinco semanas todo push de cualquier worktree corrió los guardianes del 27-sep. Al ponerlo al día (`78179af3` →
`32c67f8b`), el primer push con `numeracion.sh` vigente destapó cinco huecos que nadie había visto: **0523, 0526, 0545, 0546 y 0547**.
Los cinco tenían archivo, pero solo en ramas que nunca se fusionaron. Es el agujero de la 0177 otra vez, y por el mismo camino: el
freno estaba bien y el camino cómodo no pasaba por él.

**Lo primero que se midió, porque era lo urgente: ¿la 0545 sola dejó producción a medias?**
Las tres (0545/0546/0547) son una sola pieza del 2026-10-22 — la reparación del incidente del 21-oct, cuando pagar el grupo «planilla»
a mitad de periodo selló 12 marcas en masa, dejó 10 jornadas sin salida ni horas, y revertir el pago no recalculó nada. En la corrida
de producción del 30-oct **la 0545 salió huérfana (o sea pegada) y la 0546 y la 0547 no salieron**: la reparación estaba aplicada a un
tercio. **Medido: la 0545 sola NO dejó producción peor, y pegar la 0546 después no revierte nada.** Tres razones, cada una comprobada:

- **La 0545 es puramente aditiva.** Crea `fn_reparar_dias_tras_reabrir(text,date,date)` y **no reescribe ninguna función**: solo llama
  a `fn_recalcular_jornada` (0446) y `fn_resellar_dia` (0188). Por eso su encabezado dice, con razón, que no hay md5 de partida que
  declarar. No hay riesgo del tipo 0261 al pegar la 0546 encima.
- **Tampoco puede repetir el «function is not unique» de la 0297/0299:** ese nombre no aparece en ninguna otra migración del repo, así
  que no hay sobrecarga posible. Y está revocada de `public`, `anon` y `authenticated`: la app no la puede llamar, solo quien pega SQL.
- **El contexto de partida sigue intacto ocho días después.** Las cinco funciones en juego siguen en la versión que las migraciones
  asumen: `fn_recalcular_jornada` 0446, `fn_resellar_dia` 0188, `fn_fecha_en_periodo_pagado` 0327, `fn_revertir_pago` **0323** (de la
  que parte la 0546) y `fn_dias_por_revisar` **0422** (de la que parte la 0547). Las tres migraciones posteriores que tocan este
  terreno no estorban: la **0562** dice tres veces que no toca `periodo_grupo_pago`, y la 0563 y la 0565 solo *llaman* a
  `fn_fecha_en_periodo_pagado`.

**Lo que el estado intermedio SÍ dejó, y es lo que falta cerrar.** El incidente del 21-oct está curado —la 0545 ejecutó la reparación
una vez al pegarse—, pero **el defecto de fondo sigue abierto**: si se vuelve a pagar un grupo a mitad de periodo y se revierte,
`fn_revertir_pago` sigue sin reparar las horas (falta la 0546) y Correcciones sigue diciendo «ya cuadra» sobre un día bloqueado por un
pago (falta la 0547). Y hasta hoy había una función corriendo en producción cuyo único ejemplar era un commit en una rama sin fusionar.

**Qué le tocó a cada número, con la evidencia.**

| nº | destino | por qué |
|---|---|---|
| **0523** | archivo recuperado · **ya pegada**, nada que pegar | Producción devolvió hoy `fn_educacion_registrar` = 12 865 caracteres, md5 `c42ed2a9…`, y **el archivo recuperado da exactamente eso** (comprobado byte por byte). La 0564 lo confirma: pidió ese md5 a producción el 30-oct y dice «= el cuerpo de la 0523 byte por byte (`migraciones_aplicadas` trae 450, 523, 524 y 529)». La 0564 ya la incorpora (lleva dos veces el marcador «CAMBIO 0523»), así que **repegar la 0523 ahora revertiría la 0564**. |
| **0526** | **NO se recupera** · línea en `huecos-conocidos.txt` | Borrador sin pegar. Reescribe `fn_educacion_situacion` partiendo de la 0450, **igual que la 0549, que sí está en main**; la propia 0549 dedica un párrafo a este choque: «EL ORDEN PELIGROSO es 0549 y luego la 0526 TAL COMO ESTÁ: la 0526 no PARA» —su md5 es solo un comentario, no una guardia ejecutable—. Un archivo dentro de `supabase/migrations` es algo que se pega: `que_falta_pegar.sql` lo listaría y `dame-el-sql.sh` lo entregaría sin objetar. Está además sin terminar (`@@TABLA@@`, `@@LLEGADA@@`, md5 de producción «PENDIENTE»). |
| **0545** | archivo recuperado · **ya pegada** | Salió huérfana en la corrida del 30-oct. Aditiva, ver arriba. |
| **0546** | archivo recuperado · **PENDIENTE DE PEGAR** | Parte de la 0323, que sigue siendo la vigente. |
| **0547** | archivo recuperado · **PENDIENTE DE PEGAR** | Parte de la 0422, que sigue siendo la vigente. |

Con eso `scripts/hooks/numeracion.sh` dice «numeración sin novedad»: los cinco dejaron de ser huecos sin explicar.

**Las dos que faltan traen su propia guardia, y eso es lo que las hace seguras de pegar.** La 0546 y la 0547 **comprueban el md5 de
producción dentro del propio SQL** —tal cual, sin comentarios y con `\r\n` de Windows, las tres formas que documenta `CLAUDE.md`— y
`raise exception` sin aplicar nada si no reconocen el cuerpo. La 0546 además PARA si falta la 0545. Se verificaron las nueve cifras
contra el cuerpo que el repo tiene hoy: **las nueve coinciden**.

- `fn_revertir_pago` partida (0323): 4 472 car · `ac66bb05…` / sin comentarios `8a28101c…` / CRLF `be0b00a5…`
- `fn_dias_por_revisar` partida (0422): 1 710 car · `cdd73993…` / sin comentarios `347b9698…` / CRLF `261afa11…`
- Llegada esperada: `fn_revertir_pago` 5 370 car · `0e9f58be…` · `fn_dias_por_revisar` 2 900 car · `ddf5c2cf…`

**Auditado en un Postgres desechable propio** (contenedor y puerto aparte: el Postgres local es uno solo para los ~10 worktrees y
`db reset` le destruye el estado a todo el mundo). Lo que quedó probado:

- **Las tres aplican sin error de sintaxis ni dependencia rota**, y los md5 de llegada que mide Postgres coinciden con los del archivo:
  `fn_revertir_pago` 5 370 car · `0e9f58be…`, `fn_dias_por_revisar` 2 900 car · `ddf5c2cf…`, `fn_reparar_dias_tras_reabrir` 2 396 car ·
  `77e815f3…`.
- **Las guardias aceptan el cuerpo de partida correcto** (el de la 0323 y el de la 0422) y la migración entra.
- **Y bloquean el que no lo es**, que es la mitad que de verdad hay que probar: repegadas sobre un cuerpo distinto, las dos cortan con
  `0546 · PARA` / `0547 · PARA`, diciendo el md5 y el largo que encontraron, **sin aplicar nada**.
- **Lo que NO se pudo medir en local, y por qué:** las pruebas 437/438/439. El banco improvisado no reproduce el bootstrap de Supabase
  (`storage`, `auth`), y de ahí se encadenaron 76 migraciones fallidas; las tres pruebas caen por **deriva del banco**, no por su
  contenido — primero por `personas.cuenta_de_servicio` (0490) y después por `documentos_firmados` (0157), las dos de migraciones que
  cayeron en esa cascada. Es el falso rojo que ya costó media hora con la prueba 274. Seguir parcheando el esquema a mano daría un verde
  que no prueba nada: **la señal fiable es `db-tests` de GitHub Actions**, sobre una base construida desde cero, y es la que el ruleset
  exige para fusionar. `typecheck` en verde.

**Confirmado contra producción el 2026-10-30.** `migraciones_aplicadas` trae **523** (`acortar_el_hasta_de_educacion_deja_de_fallar`,
17-oct 02:37 UTC) y **545** (`reabrir_un_grupo_pagado_repara_sus_horas`, 22-oct 07:13 UTC), y **ninguna fila para 526, 546 ni 547**. Se
pidió `numero` Y `nombre`, no un `array_agg(numero)`: eso es lo que distingue «está la mía» de «está otra con mi número», y es el paso
que dejó pasar las colisiones de la 0405 y la 0409. Las tres conclusiones de arriba quedan así medidas, no inferidas.

**Y `db-tests` cerró lo que el banco local no pudo:** los 4 checks del PR #620 en verde, sobre una base construida desde cero — o sea
que las pruebas **437, 438 y 439** pasan. Era la señal que faltaba, y es la que CLAUDE.md llama fiable.

**La 0546 se pegó en producción el 2026-10-30** (confirmado por Felipe; guardia superada). La 0547 se entregó a continuación con
`dame-el-sql.sh`, comprobada byte por byte contra el archivo y con sus acentos contados desde fuera del script —110 y 110—, porque la
verificación interna corre bajo el mismo locale y puede declararse conforme sobre texto corrupto.

**Un detalle que conviene saber antes de pegar: estas dos NO son repegables.** Su guardia acepta solo el cuerpo de partida, no el
propio (la 0549 sí se incluye en su lista blanca; estas no). Si se pega la 0546 y por cualquier duda se repega, **para** — y el mensaje
dice «Producción tiene otra versión», que se lee como alarma cuando en realidad es la señal de que ya está aplicada. Lo que distingue
los dos casos es el md5 que imprime: si es el de llegada (`0e9f58be…` / `ddf5c2cf…`), ya estaba puesta y no hay nada que hacer.

**Qué le toca a Felipe.** Pegar la **0546 y después la 0547** (en ese orden; ninguna de las dos reescribe lo que la otra toca, pero la
0546 necesita la 0545, que ya está). Las dos paran solas si producción tiene otra versión. Y de paso, dos comprobaciones de un minuto
que cierran lo que esta sesión no pudo ver desde aquí: que `fn_reparar_dias_tras_reabrir` en producción dé **2 396 caracteres, md5
`77e815f3…`** (confirma que lo que se pegó el 22-oct es este archivo y no otro borrador), y que `migraciones_aplicadas` **no** tenga
fila con `numero = 526`.

**⚠️ Y el hallazgo que cambió el orden de entrega: pegar la 0547 con la pantalla de hoy habría hecho DESAPARECER esos días de
Correcciones.** Se vio al comprobar quién consume la función, ya con el SQL entregado y antes de que se pegara.

`admin/correcciones/page.tsx` repartía los días en tres bandas por igualdad literal con los tres motivos que conocía:

```ts
const rotos    = accionables.filter((d) => d.motivo === "secuencia_imposible" || d.motivo == null);
const cerrados = accionables.filter((d) => d.motivo === "auto_cierre_sin_confirmar");
const sellados = accionables.filter((d) => d.motivo === "sello_sin_levantar");   // ← tercera igualdad
```

Un día con el motivo nuevo `grupo_pagado_periodo_abierto` no entra en ninguna de las tres, y la pantalla solo pinta esas: **el día se
cae de la única vista donde se corrige, sin que nada falle**. Y es exactamente el daño contra el que la propia 0547 advierte en su
encabezado («los días de este incidente PASARÍAN A ESTAR OCULTOS y el aviso desaparecería justo cuando hacía falta») — evitado con
cuidado en el SQL y reintroducido por la puerta de atrás, porque quien lo consume no conocía el motivo. Hoy esos días caen en
«sellados» con un texto equivocado; eso se lee mal, pero se lee.

**Arreglado aquí, y como resto en vez de como tercera igualdad**, que es lo que impide que vuelva a pasar con el próximo motivo: dos
igualdades y todo lo demás a la tercera banda. Más la etiqueta en la Bandeja («Su grupo ya se pagó: las horas están bloqueadas»), que
es lo que la 0547 dejó listo al devolver `grupo_pagado` y `grupo_pagado_at`. `typecheck` en verde, 2 948 pruebas de interfaz en verde.
**No verificado:** la pantalla no se miró en el navegador (este clon no tiene `apps/web/.env.local` con las claves de Supabase).

**Y de ahí sale un orden de entrega invertido, a propósito.** La regla de la casa es pegar la migración ANTES de fusionar, y existe para
que el frontend no llame a una función que no existe. Aquí el riesgo va al revés: el frontend arreglado **funciona igual con la 0422 y
con la 0547** (si el motivo nuevo no llega, la tercera banda se comporta como antes), mientras el frontend VIEJO con la 0547 pierde
días. Así que lo seguro es **fusionar primero y pegar la 0547 después**, y queda escrito que esta vez la regla se invirtió midiendo, no
por descuido. Mientras no haya ningún grupo pagado con su periodo abierto, ningún día trae ese motivo y la ventana no afecta a nadie:

```sql
select pp.id, pp.fecha_ini, pp.fecha_fin, g.grupo, g.pagado_at
  from periodos_planilla pp join periodo_grupo_pago g on g.periodo_id = pp.id
 where g.estado = 'pagado' and pp.estado <> 'pagado';
```

**Dos hallazgos de paso.**

- **Hay un sexto hueco que ningún freno avisa: la prueba `supabase/tests/420`.** Era la de la 0526 (45 aserciones) y vive en el commit
  `a23658f8`. `numeracion.sh` solo mira los huecos de `supabase/migrations`, así que un número saltado en `supabase/tests` no dispara
  nada. Queda escrito acá porque no hay quien lo diga. (El hueco de la prueba 417, de la 0523, sí se llenó: su archivo se recuperó.)
- **El commit de la 0526 que se venía citando es el borrador.** `355f6f2d` se llama «0526 (SIN PEGAR, **BORRADOR**)»; la versión buena
  es `a23658f8`, seis minutos después, que es la que trae la prueba 420. Si esa mejora se retoma, se parte de ahí — y con número nuevo.

---

## 2026-10-30 — El repo principal al día, y cada worktree corre SUS guardianes · sin SQL · PR #621 ABIERTO, SIN FUSIONAR · rama `claude/memorandum-disciplinario-sistema-fb3bd6`

**Lo que pasaba.** `core.hooksPath` apunta a
`/Users/ArchiCaylo/Developer/cayla-dynamic/scripts/hooks` —el repo PRINCIPAL, no
el worktree desde el que empujas—. Y ese checkout estaba en `78179af3`, del
**2026-09-27**: **943 commits detrás de `origin/main`**. O sea que durante cinco
semanas, todo push de cualquier worktree corrió los hooks del 27 de septiembre.

**Medido, no supuesto.** El `pre-push` que de verdad corría invocaba **ocho**
guardianes; el de una rama al día invoca **diez**. Faltaban estos dos:

| guardián | desde | qué dejó de vigilar |
|---|---|---|
| `receta-suelta.sh` | 2026-10-17 | el paso 2 del [ADR 0004](adr/0004-diseno-unificado.md): que un push no vuelva a escribir a mano una pieza que ya tiene componente. **No frenó un solo push en cinco semanas.** Se midió contra 150 merges, se probó con 36 casos, y se instaló donde nada lo ejecutaba. |
| `estado-que-miente.sh` | — | que este archivo no mienta. La ironía no fue menor: ese día se corrigió a mano una línea de `estado.md` que había causado un incidente en producción, y el guardián que existe para eso llevaba semanas sin correr. |

Una primera versión de esta entrada dijo «diez contra trece» y listó tres
guardianes, con `probar-receta-suelta.sh` entre ellos. Era falso por el método:
se contaron los nombres que APARECEN en el `pre-push`, y ahí también están los
que solo se mencionan en comentarios (`desplegar.sh`, `donde-vive.sh`) y
`probar-receta-suelta.sh`, que es la prueba de `receta-suelta.sh` y se corre a
mano, no en el push. Lo que se cuenta son las líneas que lo INVOCAN:
`grep -cE '^"\$\(dirname "\$0"\)' scripts/hooks/pre-push`. La sustancia no
cambia —dos guardianes apagados cinco semanas—; los números sí, y en este
archivo un número equivocado es justo lo que `estado-que-miente.sh` existe para
cazar.

**Y un cuarto que no faltaba: corría, pero era el de septiembre.**
`que-falta-pegar.sh --arregla` regenera `scripts/sql-manual/que_falta_pegar.sql`
en cada push y lo commitea. Como el script que corría era el del 27-sep,
**revertía en cada push** el arreglo del 28-sep (commit `9b8f821f`, «La 0393 deja
de gritar MIRA ARRIBA»). Regenerar el artefacto a mano no servía: el siguiente
push lo volvía a pisar.

Eso se vio en producción, con la consulta corrida de verdad, y dio **dos
respuestas equivocadas**:

- **La 0393 salió como «⚠️ SOBRA LA FILA»** cuando está explicada desde el
  2026-09-28 en `huecos-conocidos.txt`, con su marca `[sobra la fila: …]` y la
  orden expresa de NO recuperar el archivo. El resumen dijo «⚠️ MIRA ARRIBA» por
  una alarma ya resuelta — que es cómo se enseña a ignorar las alarmas.
- **La 0519 salió como «❌ FALTA PEGAR»** cuando está en `no-se-pegan.txt`. El
  generador viejo no lee ese archivo, así que la marcaba `false`.

**Por qué nadie lo vio.** Los hooks no fallaron: corrieron, imprimieron sus diez
pasos en verde y dejaron pasar el push. Un guardián ausente no deja hueco visible
—la salida del push se ve exactamente igual de sana con diez pasos que con
trece—. Es la misma forma que ya está escrita en CLAUDE.md para el linter: «un
guardián instalado y apagado».

### Qué se hizo (2026-10-30, con el OK de Felipe)

- **El checkout principal avanzó `78179af3` → `32c67f8b`**, los 943 commits, en
  avance limpio: no tenía ningún commit propio que no estuviera arriba.
- **Los dos archivos sin commitear eran trabajo ya superado**, no trabajo
  perdido: subían `next` de 16.2.12 a 16.3.3 con fecha del 21-sep, y `main` ya
  trae **16.4.1**. El parche se guardó fuera del repo antes de descartarlo.
- **Su `pre-push` ya es byte por byte el mismo** que el de una rama al día: los
  trece guardianes, `receta-suelta.sh` incluido.
- **`que_falta_pegar.sql` se regeneró y se commiteó** (`36f4c98f`). El arreglo
  del generador estaba commiteado desde `6b6bf575`; lo que seguía siendo de
  septiembre era el **archivo generado** en HEAD. Son dos cosas distintas y
  conviene no confundirlas: arreglar el generador no arregla el artefacto.

### La causa de fondo: resuelta hoy, pero se degrada sola

Poner el principal al día apagaba el incendio y no cerraba el agujero. Lo que se
midió al cerrarlo es peor de lo que decía la primera versión de esta entrada: no
es que un hook escrito en un worktree «corra tarde». **No corre, y git no dice
nada que se distinga de que todo esté bien.**

```
$ git hook run pre-auto-gc            # un hook que solo existe en el worktree
error: cannot find a hook named pre-auto-gc

$ git -c core.hooksPath=scripts/hooks hook run pre-auto-gc
    corrió el hook del worktree: scripts/hooks/pre-auto-gc
```

Con la ruta **relativa** —la que CLAUDE.md ya prescribía— git la resuelve contra
la raíz de CADA worktree, y se comprobó que lo hace también empujando desde un
subdirectorio (`apps/web`, `supabase/migrations`): git se mueve al tope del árbol
antes de correr los hooks, así que no hay un caso en que la relativa apague todo.

**Felipe decidió relativo el 2026-10-30, y se ejecutó así.** No era una línea en
un sitio: **`extensions.worktreeConfig` está activo**, y los once worktrees
tenían cada uno su propio `config.worktree` con la ruta absoluta, que gana sobre
el `.git/config` compartido. Se puso el compartido en `scripts/hooks` y se
quitaron los once overrides, para que haya **una sola fuente**. Respaldo de los
doce archivos de antes, fuera del repo, por si hay que volver.

**Lo que costó, nombrado:** ayer los doce corrían los guardianes de `main`; hoy
cada uno corre los suyos. Medido justo después del cambio: cuatro worktrees
invocan 8, cuatro invocan 9 y cuatro invocan 10. Los ocho primeros corren uno o
dos guardianes menos que ayer **hasta que traigan `main` a su rama**, que es algo
que necesitan hacer igual antes de fusionar. Ninguno se quedó sin `pre-push`, y
los doce lo tienen ejecutable —si no lo fuera, git lo saltaría en silencio, y eso
se comprobó uno por uno.

**Y aquí está lo que hay que saber, porque el arreglo se degrada solo: la app
escribe la ruta absoluta en el `config.worktree` de cada worktree NUEVO.** Se
midió en `vigilant-hopper-d48cdd`, creado ese mismo día: nació con
`hooksPath = /Users/ArchiCaylo/Developer/cayla-dynamic/scripts/hooks`. Así que
cada sesión nueva vuelve a empezar apuntando al principal, y si el principal se
congela otra vez, esa sesión hereda el problema entero. No es memoria de nadie:
es la app, y volverá a pasar.

Se comprueba en una línea, y lo que tiene que decir es `scripts/hooks`:

```bash
git config --show-origin --get core.hooksPath
```

Si dice una ruta absoluta y viene de un `config.worktree`, se arregla con
`git config --worktree --unset core.hooksPath` en ese worktree. Mirarlo para los
doce de golpe: recorrer `git worktree list --porcelain` preguntándole eso a cada
uno. **Ojo al escribir ese bucle: la shell de esta Mac es zsh, y ahí `$VAR` sin
comillas no se parte en palabras como en bash.** Dos mediciones de ese día
salieron con todo marcado como «falta» por eso, y el síntoma —una columna
uniformemente mal— se lee como un dato, no como un error de shell.

### El pre-push deja de tirar la evidencia

Lo último del día salió de haber pagado el costo. Las pruebas frenaron dos
pushes seguidos y pasaron en verde las tres veces que se corrieron a mano: el
fallo era intermitente —contención en esta Mac, con diez worktrees, un SSD
externo y la sesión nueva instalando dependencias justo entonces—, y el
`pre-push` mandaba la salida a `/dev/null`, así que lo único que quedaba era
«corre `npx pnpm test` para ver cuál». Para cuando lo corres, el motivo ya no
está. Se resolvió parcheando el hook a mano para ver la salida, o sea haciendo
lo que el hook debería dar; costó tres pushes y un rato de suposiciones falsas
—se descartaron `GIT_DIR`, el stdin sin consumir y el typecheck previo, todas
reproducidas y todas en verde—.

Ahora los dos pasos guardan su salida en
`$(git rev-parse --git-path salida-del-ultimo-push)` y al bloquear imprimen las
últimas 25 líneas más la ruta del archivo entero. Ese destino está dentro del
directorio de git **del worktree**: sobrevive al push, no se pisa con los otros
diez y no aparece en `git status` —comprobado escribiendo un archivo ahí—.

Probado con los tres casos, que es el estándar de la casa para un freno:

| caso | qué debe pasar | qué pasó |
|---|---|---|
| una prueba que falla a propósito | frena **y** muestra el motivo | frenó, e imprimió la aserción, el archivo, la línea, el código y el recuento (1 falló / 2951 pasaron) |
| todo en verde | pasa, sin ruido | pasó |
| no se puede escribir el directorio | **corre igual**: un freno no puede frenar por su propia plomería | cae a `/dev/null` y al mensaje de antes |

El tercero no es adorno: la primera versión ponía `DIR=/dev/null` y luego
`"$DIR/pruebas.log"`, que es una ruta inexistente — el redirect habría fallado y
el hook habría bloqueado **todos** los pushes sin que nada estuviera mal. Está
dicho en un comentario junto al código, porque es el error que invita a repetir.

**Lo que queda abierto.** Este cambio vive en la rama; mientras no se fusione a
`main`, los otros worktrees siguen con el `pre-push` que tira la salida. Y no se
midió qué se coló en las cinco semanas en que `receta-suelta.sh` no corrió —las recetas escritas a mano que habría frenado— ni
cuántas veces `estado-que-miente.sh` habría avisado. Se puede contar sin tocar
nada, corriendo los dos guardianes sobre los merges de ese periodo.

---

## 2026-10-30 — Barrido: qué se puede pegar fuera de orden o a medias sin que nada avise · sin SQL · rama `claude/memorandum-disciplinario-sistema-fb3bd6`

**Por qué se hizo.** Al pegar la 0569 saltó su propio freno («falta la columna de
la 0568»), y eso abrió una pregunta más grande que el caso: la 0569 escondía su
dependencia dentro de un cuerpo plpgsql, **que Postgres no analiza al crear la
función**. Se pega sin una queja y revienta al ejecutarla. Eso no es un caso: es
una clase. Cinco lecturas independientes del camino del SQL a producción, con dos
refutadores por hallazgo. 14 hallazgos, **4 sobrevivieron**, 10 refutados.

**1 · La línea roja de esta misma página empujaba a repegar dos migraciones que
revierten cosas vivas.** Ver la entrada del 2026-09-15 (buscar «Siguen sin
pegar»), ya corregida ahí con la tabla de las siete. En corto: **la 0428 revierte
`fn_provisiones` 63 migraciones atrás —es planilla— y la 0436 devuelve
`fn_bandeja_marcar_visto` de once tipos a cinco**, matando el acuse de los avisos
de educación, de cambio de turno y de conducta. Las otras cinco son inocuas. Y lo
de la 0436 **ya pasó el 2026-09-15**: está el postmortem en el encabezado de la
0453, `dame-el-sql.sh` lo avisó en rojo, y se pegó igual.

**2 · El aviso de la 0495 dice lo contrario de lo que el archivo hace.**
`supabase/migrations/0495_*.sql:100-103` hace
`raise notice '0495: ya tiene el filtro (md5 %). No se toca nada.'; return;`
dentro de un bloque `do $freno$`. El `return` termina el BLOQUE, no el archivo: el
`create or replace function fn_planilla_calcular_nucleo` de la línea 111 está
fuera y corre siempre. Y la rama que imprime ese aviso es la que se cumple hoy de
forma garantizada, porque todas las versiones desde la 0495 llevan dentro la
cadena `cuenta_de_servicio`.

Lo grave no es el `return` —la 0491 tiene la misma forma y su aviso es honesto:
dice «no se comprueban los md5 de partida», que es exactamente lo que se salta—.
Lo grave es que el mensaje de la 0495 **afirma que no toca nada justo antes de
reescribir el núcleo de la planilla**, y llega desde el SQL Editor, que CLAUDE.md
nombra como «la única confirmación». Repegarla revertiría la 0504 (practicantes a
FOLA), la 0524, la 0537 y la 0555.

**3 · Ningún freno de la casa mira el orden de pegado HACIA ATRÁS.**
`dame-el-sql.sh` sí mira hacia adelante —su paso 4 avisa cuando pegas algo que una
migración posterior ya superó— pero la pregunta inversa, «esta migración depende de
una ANTERIOR que todavía no está pegada», no la hace nadie, y el script no podría:
en sus 291 líneas no hay un solo `psql`, porque la clave de servicio está rotada a
propósito. `que_falta_pegar.sql` ordena por número, lo que da el orden correcto por
convención, pero no declara ninguna dependencia: dice «faltan la 566…569», no «la
569 lee una columna de la 568». Hoy lo único que lo caza es el bloque que la propia
0569 se escribió, y eso es memoria.

**4 · La 0562 es la única del rango 0500–0569 que no se puede repegar.** Su
`create index idx_pago_persona_eventos_estado` (línea 108) va sin `if not exists` y
sin un `drop index if exists` delante. Falla RUIDOSO, así que nadie la daría por
aplicada; pero repegar es el movimiento natural cuando una pegada a mano se corta,
y detrás de esa línea quedan el RLS, el `revoke` a `anon`, el trigger candado y las
tres funciones que son la única puerta de escritura de esa tabla.

**Lo que se arregló hoy:** la línea roja de la entrada del 2026-09-15, con la
comprobación que pedía ya corrida. **Lo que NO se tocó:** nada de los puntos 2, 3
y 4 — el 2 y el 4 están en migraciones ya pegadas (el archivo documenta lo que se
pegó y no se reescribe), y el 3 es una decisión de Felipe, porque
`scripts/dame-el-sql.sh:182-184` dice «Solo AVISA, no bloquea» a propósito.

**Lo que falta preguntar a producción:** si `migraciones_aplicadas` tiene las filas
428 y 436. Si no las tiene, `que_falta_pegar.sql` las está pidiendo activamente
—su columna `nunca` es `false` para las siete, y de todo el archivo solo una fila
la tiene en `true`—, o sea que la herramienta canónica también empuja al
accidente, no solo aquella línea.

---

## 2026-10-30 — La escalera disciplinaria llega hasta el despido · migraciones 0566 a 0569 · **LAS CUATRO PEGADAS (2026-10-30)** · **+ la 0570 SIN PEGAR** · PR #621 ABIERTO, SIN FUSIONAR · rama `claude/memorandum-disciplinario-sistema-fb3bd6`

### La 0568 dejó seis faltas graves sin nombre, y lo cazó el CI (migración 0570)

`db-tests` del PR #621 se puso en rojo con **cinco aserciones en tres pruebas que
ya existían**, y `main` llevaba cinco corridas seguidas en verde: no era deuda
vieja, lo rompieron estas cuatro migraciones. Cuatro de las cinco eran pruebas
que quedaron obsoletas a propósito. **Una era un defecto real, y está en
producción desde hoy.**

| aserción | veredicto | por qué |
|---|---|---|
| 404 · «los 20 literales» | prueba vieja | filtraba por `rit_version` cuando su título habla de dos numerales. Hasta la 0568 daba lo mismo; el 53.3 rompió esa equivalencia. Ahora filtra por numeral, que es lo que siempre prometió. |
| 404 · «17 se registran a mano» | prueba vieja | lo mismo: 7 del 53.1 + 10 del 53.2 siguen siendo 17; los 4 nuevos del 53.3 los cuenta la 458. |
| 404 · «NIVEL · verbal y amonestación» | prueba vieja | la 0568 abrió el nivel a `imputacion` y reescribió el mensaje. El comportamiento no cambió: `suspension` se sigue rechazando, ahora porque **se eleva**, no porque «la decide DO». |
| 405 · «CANDADO · ni lo firma» | prueba vieja | el descargo previo de la 0566 se interpone ANTES del candado que esa aserción medía, así que `fn_expediente_firmar` cortaba 50 líneas antes de llegar al trigger de la 0511. Se sembró el trámite del art. 55.2 primero, como ya hace la 205. **No** se relajó el patrón a `'%'`: eso habría convertido una aserción sobre ese candado en una aserción sobre cualquier error. |
| 408 · «ninguna falta queda sin nombre corto» | **defecto real** | la 0568 metió seis filas a `faltas_catalogo` **sin su insert hermano en `faltas_rotulos`**. Lo arregla la **0570**. |

**Por qué el defecto pasó inadvertido, que es la parte que enseña.** Ni la 0568,
ni su prueba 458, ni el ADR mencionan la palabra «rótulo» una sola vez: no fue
una decisión, fue un olvido. La decisión de que se nombran TODAS las faltas
—incluso las que nadie elige a mano, «para cuando aparecen en el panel de un
caso»— vive en la 0514, y la aserción que la defiende vive en **otra prueba**, la
408. Una migración se revisa con sus propias pruebas; la invariante que rompió
estaba en el archivo de al lado.

Y **nada revienta ni sale en blanco**: los tres lectores degradan solos, que es
justo lo que lo hizo invisible. Lo que se pierde es el nombre de la acusación en
la cabecera del documento (`panel-caso.tsx`) y en la bandeja de DO
(`bandeja-fuentes.ts`) — o sea en el papel más grave que existe, la imputación de
cargos. Quien revisa la bandeja lee «53.3 a)» y ya no sabe de qué se acusa a
alguien sin abrir el caso.

**Y un hueco aparte, que la 0570 NO arregla porque es código:**
`faltasElegibles` (`apps/web/lib/admin/conducta.ts`) reparte el catálogo en dos
cubos, `leve` y `significativa`, y `registrar-falta.tsx` solo dibuja esos dos.
Una falta con `gravedad = 'grave'` se cae de los dos y no se dibuja ningún chip.
Como esa pantalla es la única que llama a `fn_expediente_crear_conducta`, **el
nivel `imputacion` que la 0568 habilitó en la base no tiene puerta en la
interfaz**. Va con las pantallas que faltan, y ninguna pgTAP lo cubre.

**Qué es.** Felipe pidió «que cada líder pueda emitir memorándums para así escalar medida disciplinaria de despido de ser necesario».
Al investigarlo salió que la mitad de abajo ya estaba construida: desde el 6 de octubre (0510–0516) la líder emite memos, cita el literal
exacto del art. 53 del RIT, firma y entrega. Lo que faltaba era la mitad de ARRIBA de la escala del art. 54.1 —suspensión y despido— y dos
defectos que la invalidaban. El diseño, con las seis decisiones en formato DECIDÍ / DESCARTÉ / SE ROMPE SI, está en
[`docs/adr/0005-escalera-disciplinaria-completa.md`](adr/0005-escalera-disciplinaria-completa.md).

**Lo que había que arreglar antes de construir nada.** `configuracion.disciplina_descargo_previo` estaba en `false` desde el 17-08-2026
(0267). El art. 55.2 del RIT que CAYLA entregó firmado dice que sin descargo previo la sanción «no puede computarse como antecedente ni
servir de escalón para los efectos del literal h) del artículo 25 de la LPCL»: cada memo documentaba el hecho y no era peldaño de nada.
Construir la suspensión y el despido encima era construir una escalera que el art. 25 h) no reconoce. Por eso la **0566** va primera.
Medido antes de pegarla: **0 borradores** quedaban a la espera, así que no hubo transición que gestionar.

**Las cuatro piezas.**
- **0566** enciende el descargo previo. No reescribe ninguna función. *Hallazgo:* encenderlo no agrega un paso antes de firmar, agrega
  **tres** —comunicar cargos, esperar el plazo, y **valorar el descargo por escrito aunque no se presente ninguno**—. La pantalla ya
  dibujaba las cuatro etapas desde la 0267 (`etapaDelBorrador`), así que no hubo interfaz que cambiar.
- **0567** — la líder PROPONE la suspensión (`fn_conducta_proponer_suspension`, con su candado) y DO la IMPONE
  (`fn_expediente_elevar_a_suspension`). El mismo documento sube de nivel en vez de crearse otro: la suspensión no castiga otra vez el
  hecho ya amonestado (non bis in idem, 52.5), castiga el hecho NUEVO que sube de peldaño por el antecedente (56.4). No reescribe ninguna
  función: llama a `fn_expediente_puede_actuar` (competencia 54.4 c), `fn_expediente_set_suspension` (tope de 3 días, 54.5) y
  `fn_conducta_antecedentes`. `fn_expediente_firmar` queda intacta.
- **0568** — la falta grave llega hasta el despido. *Hallazgo grande:* **hoy no existe ninguna forma de emitir una carta de despido.**
  Los dos motores llegan a la imputación y paran con un mensaje que lo dice —«el despido se genera tras evaluar los descargos (paso manual
  de Gerencia)»—, y ese paso manual era el final del camino: el expediente se armaba completo y la decisión salía fuera del sistema, sin
  que la causa de la carta quedara atada a la de la imputación. Cinco piezas: los 6 literales del 53.3 al catálogo (con e) asistencia y
  f) hostigamiento sexual marcados como no registrables a mano, cada uno por su razón); `fn_expediente_crear_conducta` admite el nivel
  `imputacion`, cita el literal, exige los 6 días NATURALES del art. 57.2 y comprueba el 60.5 —freno que en esta rama no tenía nadie—;
  `fn_expediente_crear_despido` arma la carta A PARTIR de su imputación, sin recibir causa (la hereda, así que el 57.7 no se puede
  romper); un trigger impide cambiarla por UPDATE directo (cuarta instancia del molde de la casa, tras 0261, 0295 y 0342); y dos
  restricciones de la 0510 que guardaban la premisa «el 53.3 no está en el catálogo» se ponen al día.
- **0569** — la entrega arranca el plazo del art. 31 (que corre desde la RECEPCIÓN) y anota en el expediente que un acta interna no
  sustituye la notificación notarial del art. 57.8. Decisión de Felipe: **avisar, no bloquear** (mi recomendación había sido bloquear; el
  costo queda escrito en el ADR). El aviso llega también ANTES del clic, en el formulario: ahí había un texto FALSO desde meses, que
  afirmaba que el acta «produce los mismos efectos que el cargo firmado (num. 55.4)» también en imputación y despido.

**Lo que cazaron las pruebas antes de pegar nada.** `chk_conducta_completa` obligaba a que una imputación por conducta tuviera la falta en
NULL, y el índice único del 52.5 hacía chocar la carta de despido con su propia imputación (hereda persona, falta y fecha a propósito).
Ninguna estaba mal escrita: las dos eran premisas correctas que caducaron el día que el 53.3 entró al catálogo. El índice se resolvió
diciendo a qué se refiere el 52.5 —protege de SANCIONAR dos veces, y la escala del 54.1 son tres peldaños— en vez de relajarlo.

**Y un defecto de mi propia 0569, medido:** pegarla antes de la 0568 NO falla. Postgres no analiza el cuerpo de una función plpgsql al
crearla, así que se pega sin una queja y revienta la primera vez que alguien ENTREGA un documento firmado, con la persona delante. La
migración abre ahora con un bloque que comprueba la columna y aborta; el encabezado afirmaba lo contrario antes de medirlo.

**Probado.** Banco de Postgres nativo desechable con el esquema real de `main` (565 migraciones) y control A/B en las cuatro:
**456** 5/5 (4 de 5 en rojo sin la 0566) · **457** 9/9 (9/9 en rojo sin la 0567) · **458** 17/17, 11 de ellas casos que DEBEN bloquear
(0/17 sin la 0568) · **459** 9/9, y el control deja en rojo las 4 del comportamiento nuevo y en VERDE las 5 que vigilan que no se rompió
lo anterior —entre ellas la que más importa: que la imputación de los motores de asistencia, que no trae plazo concedido, se entregue
igual que siempre sin reloj inventado—. Vitest 2 951 de 2 951 y typecheck en verde.
De paso se arregló un defecto del banco que llevaba semanas dando falsos rojos: su `auth.uid()` leía `request.jwt.claim.sub` mientras las
pruebas del repo ponen `request.jwt.claims` como JSON. La prueba 205 pasó de 0/9 a 9/9.

**md5 pedidos a producción el 2026-10-30, los tres idénticos al repositorio y sin un solo `\r`:** `fn_expediente_crear_conducta`
3359 / `a7cdf75a…`, `fn_expediente_entregar` 1693 / `75367baa…`, `fn_conducta_antecedentes` 3021 / `d7e5a98c…`.

**Estado del pegado. LAS CUATRO PEGADAS el 2026-10-30.** La 0566 y la 0567 primero (registradas con su nombre correcto y sin número
robado; `disciplina_descargo_previo` quedó en `true`), y después la 0568 y la 0569 en ese orden. La 0569 se intentó pegar antes que la
0568 y **su propio bloque de precondición la paró** —«Falta la columna expediente_disciplinario.plazo_descargo_dias, que agrega la
migración 0568»—, que es exactamente para lo que se escribió; al segundo intento, con la 0568 ya puesta, entró con «Success. No rows
returned». El texto de las dos se verificó byte por byte contra el repositorio (`dame-el-sql.sh` + `diff <(pbpaste) …` → idéntico), así
que los acentos están intactos. **Pendiente de Felipe:** correr la consulta de comprobación (se espera 6 · 4 · 1 · 6781 · 1 · 1 · 1 ·
4172 · true · true). `versiones_crear_conducta` = 1 es la que más importa: un 2 significa que la firma vieja de siete argumentos
sobrevivió al `drop` y la pantalla de registrar una falta contestará «function is not unique».
Nada fusionado y **no hay PR**.

**Pendiente.** Las pantallas: el botón de «pedir suspensión» para la líder, la acción de elevar para DO, y el panel de antecedentes
acotado a conducta/12 meses. Van con la regeneración de `types.ts`, que todavía no tiene las cuatro funciones nuevas. Y dos defectos
medidos que esta entrega esquiva y no arregla, cada uno con su propia entrega: `fn_expediente_resolver` no comprueba que el plazo de
descargo haya vencido (hoy se puede archivar o decidir el despido el mismo día de la entrega, sin haber escuchado), y las imputaciones
de los dos motores de asistencia —casi todas las que existen— se entregan sin que corra el plazo del art. 31; ponerles reloj exige
tocar los motores y el plazo no se adivina, se concede por escrito (art. 57.2).

---

## 2026-10-29 — Liquidaciones lista lo que se debe de periodos anteriores · migración 0565 · **SQL PEGADO EN PRODUCCIÓN (2026-10-29)** · FUSIONADO (PR #618) · rama `claude/liquidacion-periodos-sin-pagar`

**Qué es.** Emily Rico y Milagritos Zarate cesaron el 29/10, que ya es el periodo NUEVO: su liquidación calculaba un día y el sueldo de
28/09–28/10 —planilla todavía abierta, que sí las incluye— no aparecía en ningún lado de la pantalla. Nada se dejaba de pagar, pero
quien mira Liquidaciones veía S/ 145 y podía creer que era todo. Felipe pidió ver «todo lo que no se pagó, desglosado por periodo».

**Qué hace.** `fn_liquidacion_periodos_anteriores(persona, fecha_cese)` (0565, **solo lectura**, función nueva: no hay md5 de partida)
lista los periodos COMPLETOS anteriores al del cese en los que trabajó y su grupo aún no cobró (`fn_fecha_en_periodo_pagado`), con el
monto que calcula `fn_planilla_calcular`. La pantalla los pinta debajo del desglose, con el total entre planilla y liquidación.
**NO se suman al total de la liquidación**: ese dinero sale por la planilla, y la planilla no sabe descontar lo que una liquidación pagó
de un periodo anterior al del cese (la 0243/0244 solo lo hace con el del cese). Felipe eligió esto (opción A) el 2026-10-29 sobre
«que la liquidación pague todo», que habría exigido reescribir `fn_planilla_calcular_nucleo`.

**Medido en producción (solo lectura).** Entre las cesadas con liquidación sin pagar, el criterio lista exactamente dos filas —Emily
y Milagritos, 28/09–28/10, abierto— y ninguna otra. **Probado.** Clon del Postgres local con todo hasta la 0565 (salvo la 0551, ajena):
prueba 455, 16/16; con la condición de «pagado» quitada falla la 9, y con el periodo del cese incluido falla la 1. Vitest 2 942 de 2 942
y typecheck en verde. **No verificado:** la pantalla no se miró en el navegador (sin pila local ni sesión de administrador).
Si la 0565 no está pegada, el desglose avisa «no se pudo comprobar» en vez de callar.

**PEGADA en producción el 2026-10-29**, ya fusionado el PR (se fusionó SIN la migración pegada y por unos minutos la pantalla nueva dijo
«no se pudo comprobar»; el aviso funcionó como estaba diseñado y no se rompió nada). Guardia superada, comprobación `1 · true · false · 1`,
cuerpo idéntico al de `main` (1 619 caracteres, md5 `bfe63f7f…`). Renumerada de 0564 a 0565 porque el PR #617 reclamó la 0564 primero.
**Pendiente de Felipe:** mirar la pantalla con las dos personas del caso: debe verse el recuadro «También se le debe de periodos anteriores».

## 2026-10-29 — La baja tras una reactivación ni se bloquea ni pierde su último día · migración 0563 · **SQL PEGADO EN PRODUCCIÓN (2026-10-29)** · FUSIONADO (PR #615) · rama `claude/baja-prueba-liquidacion-6c5f3e`

**Qué pasó.** Robert Cabrera y Emily Rico (preselección) se dieron de baja, se reactivaron a las 23:01 y se repitió la baja. A Robert
(ingreso 19/10, última jornada 28/10) le quedó cese el 19/10 y su liquidación pagaba un solo día (S/ 63.72); a los dos la baja se
negaba por el horario que dejó la reactivación. Se arreglaron a mano en producción esa noche (tramos retirados, cese de Robert a 28/10,
con rastro en `correcciones_auditoria`). La 0563 es el arreglo general.

**Dos causas, dos funciones.**
- `fn_prueba_cerrar` (0536) buscaba el último día trabajado desde el inicio de la prueba ABIERTA; al reactivar, el trigger abre otra con
  inicio HOY y las jornadas anteriores dejaban de verse, así que caía al día de ingreso. Ahora busca desde el ingreso.
- `fn_cese_aplicar` (0535) se negaba a cesar con un tramo de salario u horario posterior al último día, que es justo el que deja
  `fn_reactivar_persona` (0327, que no se toca: devolver el sueldo desde mañana es a propósito, 0209). Ahora retira SOLO los tramos
  que esa reactivación creó (los reconoce su constancia en `correcciones_auditoria`), si nadie marcó desde ese día y no caen en un periodo
  pagado; los deja escritos, y lleva el tramo que continuaban al nuevo último día. Un salario futuro cargado a propósito sigue frenando.

**Probado.** Clon del Postgres local con todas las migraciones hasta la 0562 (salvo la 0551, ajena): prueba 453, 26/26. Control con las
funciones viejas: fallan 13 de 26, los dos casos reales. Repegable. **md5 de producción medido el 2026-10-29** (coinciden con 0535/0536):
`fn_prueba_cerrar` 3 284 · `b8161af7…`, `fn_cese_aplicar` 3 993 · `442ac680…`; la guardia de la migración se niega sobre otra versión.
**PEGADA en producción el 2026-10-29** (guardia superada; comprobación `true · true · 1`; permisos intactos). md5 de llegada, medido en
producción y igual al del archivo: `fn_prueba_cerrar` 3 306 · `24f3740b…`, `fn_cese_aplicar` 7 878 · `23251c75…`. Robert y Emily ya se
habían arreglado a mano esa noche; esto evita que vuelva a pasar. No hay código que fusionar: solo SQL, prueba y este archivo.

## 2026-10-29 — Liquidaciones avisa cuando falta el periodo del cese · sin SQL · rama `claude/liquidacion-sin-periodo`

**Qué pasó.** Emily Rico y Milagritos Zárate cesaron el 29/10 con el periodo 28/09–28/10 todavía abierto: ningún periodo contenía el 29/10.
`fn_liquidacion` (0164) busca el periodo QUE CONTIENE el cese y, si no hay, no inventa uno: el sueldo del periodo sale en 0. La lista de
pendientes solo mira el total, así que las dos aparecían en «Sin nada que cobrar» —donde se podía marcar pagada con S/ 0.00— teniendo un día
trabajado por pagar. Lo que arregla el dato es crear el periodo siguiente en Planilla («+ Nuevo periodo»).

**Qué cambia.** La pantalla lee `fn_periodos` y, a quien no pagó y cesó en un día sin periodo, lo saca de «Sin nada que cobrar» y lo nombra en un
aviso rojo arriba, con el enlace a Planilla. Si no se pueden leer los periodos, no avisa (nada de falsa alarma). La regla es
`apps/web/lib/admin/liquidacion-periodo.ts`, con `tests/liquidacion-periodo.test.ts` (6 casos, incluido el real). **No toca SQL ni cálculo de pago.**
**No verificado:** la pantalla no se miró en el navegador (hace falta sesión de administrador).

## 2026-10-27 — «Prueba» vuelve como vínculo y se llama «preselección» · migraciones 0558 a 0561 · las cuatro PEGADAS 2026-10-27 · FUSIONADO (PR #608)

**Qué es.** Felipe lo decidió el 2026-10-27, un día después de la reforma de abajo: «volvamos a ponerlo como prueba; de momento
mantengámoslo así como era antes, toda la función. Antes, para los nuevos colaboradores, se ponía de prueba y no se les pagaba EsSalud:
volvamos a eso. Todo el apartado de prueba se llamará preselección.» Y después: la preselección es **solo sueldo y movilidad asistida**
—sin seguro, sin beneficios— y **en Seguros no tiene nada, ni póliza ni nada**. Esto **deshace** lo de las dos secciones de abajo (0553,
0556, 0557 y las pantallas de esos PR) y deja el vínculo `prueba` como estaba el 25/10, con otro nombre en pantalla.

- **El nombre.** En pantalla es **«preselección»** (una palabra, sin tilde de más): etiqueta «Preselección · 2 de 3», selector de
  vínculo de Equipo, pestaña de Planilla, módulo de la Bandeja, cinta del terminal, avisos de Turnos y de Liquidaciones, Contratos,
  Parámetros, ayuda de Seguros, novedades nuevas y la constancia de consentimiento del DNI. **El valor interno sigue siendo `prueba`**
  (CHECK de la 0322, columna, RPC, `pruebas`, `fn_pruebas_*`): se renombra lo que se ve, no lo que se guarda — el mismo trato que
  `supervisor_sede` («líder de equipo»). **No se renombra** el periodo de prueba legal que va dentro de un contrato (art. 10 del
  D.S. 003-97-TR; la cláusula TERCERA del contrato) ni el motivo de cese `fin_periodo_prueba` («No pasó el periodo de prueba»).
- **El código** vuelve a su estado previo a la 0553 (selector con «Preselección», aviso de feriado por vínculo + días trabajados,
  «Días de preselección» en Parámetros, cláusula del contrato sin plazo pactado, etiqueta sin fecha de corte). Dos retoques que NO son
  «como antes», a propósito: los textos de «se retiró» (Bandeja, panel de la preselección, Contratos, Equipo) dicen que **sí se paga
  lo trabajado** —desde la 0555 la planilla lo paga, y un cartel que dijera lo contrario mandaría a decidir con un dato falso—; y la
  novedad nueva explica el cambio en vez de borrar las del 26/10 (una novedad publicada no se edita).
- **0558 · PEGADA por Felipe el 2026-10-27; no movió a nadie.** Buscaba a quien la 0554 pasó a planilla; Robert Cabrera y Emily Rico
  **ya no estaban en planilla sino en `rxh`** (medido en producción), así que no los reconoció. Quedó registrada y es inofensiva.
  **Producción cambia sola:** Felipe los pasó a mano por practicante → RxH → practicante el 26 y 27/10 (último cambio 18:30), y tienen una
  asignación manual de FOLA en Seguros. Por eso la 0561 **tampoco los movió**: busca en `planilla` y `rxh`.
- **0561 · PEGADA el 2026-10-27 (`{planilla} · null · 0 · 561`); hoy solo cambió Seguros. MUEVE PLATA cuando alguien coincide.** Lo que la 0558 quiso hacer, buscando en `planilla` **y** en `rxh`: activas, no cuenta de servicio, prueba
  cerrada `contratada` el 26/10 y **sin contrato firmado**, a lo sumo dos (si hay más, se niega). Vuelven a `prueba` con su
  preselección abierta desde su ingreso. **Y en Seguros** quita `prueba` de `seguros_tipos.essalud.aplica_a_vinculos`: la preselección
  queda «Sin seguro (no aplica)» como los honorarios, sin póliza ni «confirmar el alta en EsSalud». Va primero Seguros y después las
  personas, para que RxH → preselección no deje un «alta en EsSalud» pendiente.
  **La plata, medida con las mismas horas en un clon (RxH → preselección):** lo trabajado no cambia; **se SUMA la movilidad asistida**
  —S/ 10 por día asistido en provincia, S/ 12 en Lima (`parametros_laborales`, 0142), el día que no asistió no cuenta— y **se
  descuenta pensión** (13 % con ONP); EsSalud y asignación familiar siguen en cero. Con 6 días de 6,5 h y S/ 10: S/ 246,00 → S/ 274,02.
  Quien siempre fue planilla cobra exactamente igual. Sin la declaración de ruta firmada (0159, si se exige) la movilidad no se suma.
  **El periodo 29/09–28/10 cierra mañana: conviene pegarla antes del cierre.**
- **0559 · PEGADA el 2026-10-27 (`true · 0 · true · 5 · 559`; el plazo vigente es 5 días, no 3). Sin plata.** Vuelve la fila `prueba_dias` («Días de preselección antes del contrato»), se retiran las filas de Parámetros que
  agregaron la 0553 y la 0557 (se borran si nadie las cambió; si tienen historial quedan fijas y «(retirado)») y se sueltan
  `fn_feriado_aviso_dias()` y `fn_prueba_etiqueta_desde()`. **No** se suelta `personas.prueba_pactada_dias` (0556): guarda datos y nada la
  usa; queda inerte.
- **0560 · PEGADA el 2026-10-27 (`true · true · 560`). Sin plata.** Reescribe `fn_avisos_vinculo()` (0169) solo en sus textos: «preselección» en vez de «prueba». Tiene guardia de
  md5 (1 223 caracteres, `036e01d3…`, o su variante CRLF): si producción tiene otra versión, se NIEGA y hay que pedirle el md5.
- **Probado.** `tsc` limpio; vitest 2 924 de 2 924. En un Postgres clon con todas las migraciones hasta la 0560 más la 0561: pgTAP
  **450 → 18/18**, **451 → 10/10**, **452 → 24/24**, **444 → 55/55** (restaurada a como estaba antes de la 0553, con el nombre nuevo),
  **422 → 312/312** y **423 → 116/116** (Seguros, adaptadas: «prueba» ya no cae en EsSalud), y sin cambios 429, 430, 432, 446, 447, 448,
  134, 221, 297, 302. Puestas en rojo a propósito (450 sin la condición del contrato y sin el tope de dos; 451 con una función sin
  soltar; 452 sin el tope de dos y buscando solo en planilla). Se borraron las pruebas 445 y 449: probaban justo lo que la 0559 retira.
  Las migraciones se ensayaron en `begin … rollback` y se repegaron dos veces: no hacen nada la segunda vez.
- **No verificado:** las pantallas no se miraron en el navegador (sin pila local ni sesión de administrador en esta sesión). El texto
  más largo de «Preselección · 2 de 3» puede apretar la píldora del terminal en una tarjeta angosta: mirarlo en la Mac mini.

**Pendiente de Felipe.**
0. **Pasar a Robert y Emily a «Preselección»** (Equipo → Tipo de vínculo) y, en Seguros, «Volver al automático» para quitarles la asignación
   manual de FOLA. Por Equipo la preselección cuenta desde HOY, no desde su ingreso (19 y 21/10); si quiere desde el ingreso, va en SQL.
   Hoy no tienen régimen de pensión cargado: como preselección cobrarían movilidad (S/ 10 provincia, S/ 12 Lima, por día asistido) y no se
   les descontaría pensión hasta cargarlo.
1. Decidir si «se retiró en preselección» sigue pagándose (0555, que **no** se tocó): Mariel Sarmiento y Noelia Ibarcena entran en
   la planilla de este periodo. Revertirlo es otra migración que reescribe `fn_planilla_calcular_nucleo` y exige el md5 de producción.
2. Quien se dio de alta como Planilla **después** del 26/10 (por el alta nueva) sigue en Planilla: si debían entrar por preselección,
   se cambia desde Equipo («Tipo de vínculo»). Ojo: cambiar planilla → preselección saca a esa persona de EsSalud en Seguros y deja el
   pendiente «baja de EsSalud» para el contador.
3. Los textos que escribe la base y esta rama NO cambia: los errores de `fn_prueba_cerrar` y `fn_prueba_cargar_dni` («No puedes decidir
   sobre la prueba…») y la frase «al registrar la prueba» de la constancia de DNI ya guardada. Reescribirlas toca funciones largas.
4. `personas.en_planilla` (columna generada: planilla **y** prueba) sigue igual porque la planilla la necesita: el atajo «las de
   planilla» del formulario de una póliza colectiva y la consulta `quienes_van_al_seguro_de_vida_ley.sql` todavía incluyen a la
   preselección; quien registre una póliza la ve en la lista y la desmarca.

---

## 2026-10-26 — El periodo de prueba se pacta por persona y la etiqueta tiene fecha de corte (segunda rebanada) · migraciones 0556 y 0557 · las dos PEGADAS 2026-10-26 · FUSIONADA (PR #607) · ⚠ **REVERTIDA el 2026-10-27**: ver arriba (0559 retira la fecha de corte; el pacto por persona queda inerte)

**Qué es.** Tres cosas que Felipe pidió el 2026-10-26, después de la primera rebanada:
1. **Se puede dar un periodo de prueba menor que los 3 meses** (tres meses es el periodo ordinario de la ley, no un mínimo; ampliarlo
   a 6 o 12 es otra cosa y no entra). Opciones al dar de alta o editar a alguien en planilla: **la ley (3 meses, por defecto)**,
   **uno menor (1–89 días calendario)** o **ninguno**. Lo menor o ninguno pide motivo y queda en `correcciones_auditoria`.
2. **El alta pide la fecha de ingreso** (arranca en hoy, visible y editable) y el periodo de prueba **debajo del vínculo**. Los
   practicantes y las prácticas **no tienen periodo de prueba** (se rigen por su convenio; se les paga subvención): el selector avisa que
   debe haber póliza o EsSalud vigente desde el primer día.
3. **La etiqueta «En periodo de prueba» tiene fecha de corte**, editable en Parámetros, **por defecto el día en que se activa**: quien ya
   estaba no la lleva, quien ingresa desde ahí sí, mientras dure su periodo. Llevar la fecha atrás rotula también a quien ya trabaja
   y lleva menos de tres meses; Parámetros muestra **a quién se la pone o se la quita antes de confirmar**.

**⚠️ La etiqueta NO es el periodo legal.** El periodo de prueba legal es una cláusula del contrato de **cada** persona (art. 10, D.S.
003-97-TR) y corre desde su ingreso exista o no la etiqueta. La fecha de corte solo decide a quién le pone el rótulo la pantalla; no toca
la planilla, ni los avisos de feriado (que miran la antigüedad), ni el texto del contrato. Efecto concreto de que el defecto sea «hoy»:
**Robert Cabrera y Emily Rico** (pasados a planilla por la 0554), y cualquiera que haya ingresado antes de hoy, **dejan de llevar la
etiqueta** aunque su periodo legal siga corriendo. Si Felipe prefiere verla en toda la gente reciente, se cambia la fecha en Parámetros.

**0556 · SQL PEGADO (2026-10-26) · no toca planilla.** Columna `personas.prueba_pactada_dias` (null = la ley, 0 = sin prueba, 1–89 = menor, con
`check`), función guardián `fn_set_prueba_pactada(persona, dias, motivo)` (solo admin/DO, motivo ≥ 3, solo planilla, no sobre cesados,
no-op si no cambia) y trigger `trg_personas_prueba_solo_por_rpc` que rechaza el `UPDATE` directo y el `INSERT` con pacto — el molde de
`fn_set_sede_base` (0342). No reescribe ninguna función: **no hay md5 que pedir**. Prueba **448 → 23/23**, puesta en rojo a propósito de
tres maneras (sin trigger, `check` ensanchado, sin la condición de planilla).

**0557 · SQL PEGADO (2026-10-26) · no toca planilla.** Parámetro operativo `prueba_etiqueta_desde` (unidad «fecha», tope 2026-01-01 a 2030-12-31) y
`fn_prueba_etiqueta_desde()`. **Se guarda como entero AAAAMMDD** porque el catálogo de Parámetros (0552) solo guarda números y abrirlo a
otro tipo tocaba la puerta que protege los de plata; la pantalla lo dibuja y lo pide como fecha, y la función valida que sea un día real
(20261340 o 20260230 caen en la fecha de partida, no se corren al mes siguiente). La siembra pone **el día en que se pega**, con
`do nothing`: repegar no mueve una fecha ya elegida. Prueba **449 → 13/13**, puesta en rojo quitando el respaldo de la función (2 fallas).
Honestidad sobre la prueba: la comparación `to_char(...) <> v_n` de la función es redundante con el `exception` (Postgres ya rechaza
20261340); se deja como cinturón.

**Cambios en pantalla.** Equipo: fecha de ingreso en el alta (la base pone su `current_date` al crear, que de noche —hora de Lima— ya es
«mañana» en UTC; por eso el alta siempre escribe la elegida), bloque «Periodo de prueba» en alta y edición, etiqueta con corte y pacto.
Contratos: la cláusula TERCERA dice el plazo **pactado** —«cuarenta y cinco (45) días calendario», «sin período de prueba»— y se cuenta
desde el ingreso (una renovación no lo reinicia); un valor raro se imprime como la ley. Parámetros: una fila de unidad «fecha» se dibuja
y se edita como fecha, con vista previa de a quién le cambia (`impactoEtiquetaPrueba`, la misma función que usa Equipo).

**Pegado el 2026-10-26.** Felipe devolvió las comprobaciones: 0556 → `true · 0 · true · true · 556`; 0557 → `true · true · 2026-10-26 · true · 557` (la etiqueta alcanza desde el 26/10). Nadie tiene todavía un periodo pactado. **Si el código llegara antes que el SQL no se rompería nada:** las lecturas de `prueba_pactada_dias` y de `fn_prueba_etiqueta_desde` son
aparte y tolerantes; sin la 0556 el selector queda apagado y dice qué falta, y sin la 0557 la etiqueta no tiene corte (se ve como hasta
ahora).

**Regla que queda dicha, «así en adelante».** Quien ya estaba con contrato no lleva etiqueta; quien ingresa desde la fecha de corte la lleva
hasta que termina su periodo, sin que nadie la ponga ni la quite a mano. El periodo legal se pacta en el alta; el contrato lo imprime.

**Probado.** `tsc` limpio; vitest verde (nuevas: `periodo-de-prueba` 31, `prueba-pactada` 6, `parametros` 43, `contrato-texto` 53).

**Pendiente (siguiente rebanada).** Alerta a DO a los 30 días (evaluación interna) y de decisión a los 60/75/85, con atajo «No continúa»;
aviso del costo de EsSalud al dar de alta; limpieza del legado «prueba» (tabla `pruebas`, `fn_prueba_cerrar`, Bandeja, terminal 0539 y 27
pruebas pgTAP). **Felipe, antes del cierre del 28/10:** asignar sueldo a Noelia Ibarcena (desde 19/10) y Liliana Ocas (desde 25/10) y volver
a correr la consulta de «horas sin salario» hasta que salga vacía.

---

## 2026-10-26 — «De prueba» deja de ser un vínculo: es el periodo de prueba del contrato (primera rebanada) · migraciones 0553, 0554 y 0555 (las tres PEGADAS 2026-10-26) · FUSIONADO (PR #606) · ⚠ **REVERTIDA el 2026-10-27** (0558–0560, ver arriba); la **0555 NO**: quien se retira en preselección sigue cobrando lo trabajado

**Qué es.** Felipe lo dijo así (2026-10-26): tener a alguien «de prueba», o que empiece a trabajar, sin contrato y sin alta es
prácticamente ilegal. «Prueba» (tres días trabajados sin contrato, y «si pasa, recién ahí se hace el contrato») no existe en la ley
peruana: el periodo de prueba es una cláusula **dentro** de un contrato (art. 10, D.S. 003-97-TR), tres meses sin protección contra el
despido arbitrario. Quien trabaja se registra desde el primer día y se le paga lo trabajado. Cinco decisiones suyas: (a) deja de existir
el paso «a los N días recién se hace el contrato»; (b) sí se etiqueta como «en periodo de prueba»; (c) «Días de prueba» sale de
Parámetros y solo se **muestra** (como el tope de 20 días de descanso médico); (d) quien está de prueba **no lleva fecha de cese
obligatoria** (el contrato indefinido ya existía, 0347); (e) **se deroga «quien se retira no cobra»** (0537) y los **días calendario
desde el ingreso** son el criterio del aviso de feriado.

**Lo que cambia para quien usa el panel.**
- **Equipo.** El selector de vínculo ya no ofrece «Prueba» (solo la ve quien aún la trae, como «Prueba (antiguo)»). Planilla dice que se
  registra desde el primer minuto y que sus 3 meses de prueba corren desde el ingreso. La lista muestra «En periodo de prueba · hasta
  dd/mm/aaaa». La fecha se **deriva** del ingreso (`periodoDePrueba`, `packages/shared`), no se guarda; es la misma cuenta que imprime
  el contrato (`finDelPeriodoDePrueba` ahora delega allí).
- **Parámetros (0553).** «Periodo de prueba · 3 meses» aparece como fila normativa fija, con el art. 10 como base; la base rechaza por
  cualquier camino un valor distinto de 3. «Días de prueba antes del contrato» sale del catálogo (si ya tenía historial se queda fija y
  marcada «retirado»). Nuevo parámetro operativo **«Días desde el ingreso en que se avisa un feriado trabajado»** (1–30, hoy 15), con su
  vista previa de a quién le cambia.
- **Turnos.** El aviso de feriado ya no mira el vínculo «prueba»: mira **menos de N días calendario desde el ingreso, a la fecha del
  feriado**. Tres caminos en el texto: descanso (recomendado; el feriado se paga igual), descanso sustitutorio (se registra en Feriados) o
  confirmar y pagar la sobretasa. Si la base aún no tiene la 0553, rige el 15.
- **Cobertura.** Quien está en periodo de prueba (planilla) **suma desde su primer día**; antes «prueba» no sumaba.

**Lo que mueve plata: la 0554 (SQL aparte, a propósito).** Pasa a «planilla» a toda persona **activa** con vínculo «prueba» (no toca
inactivas ni cuentas de servicio). **No toca ninguna función de pago**: cambia un dato que la planilla ya lee, así que **no hay md5 que
pedir**. Auditado en el Postgres local con las 552 migraciones, dentro de `BEGIN … ROLLBACK`, con tres días de 6,5 h en el periodo
29/09–28/10 y sueldo de S/ 1 230:

| | horas (pago_base) | asignación familiar | EsSalud | pensión |
|---|---|---|---|---|
| Con hijos, 3 días | 123,00 → 123,00 | 0 → 123,00 | 0 → 110,70 | 15,99 → 31,98 (ONP) |
| Sin hijos, 2 días | 82,00 → 82,00 | 0 → 0 | 0 → 110,70 | 10,66 → 10,66 |
| Testigo (ya en planilla) | igual | igual | igual | igual |

**⚠️ La decisión que hay que tomar CON ESTE NÚMERO: el piso de EsSalud.** Registrar a quien trabaja **dos días** cuesta S/ 110,70 de
EsSalud —más que lo que se le paga por sus horas (S/ 82)—, porque el piso es la RMV entera, sin prorratear por días
(`docs/planilla-anexo-tecnico.md`; D.S. 009-97-SA). Era justo lo que la 0484 evitaba para «prueba», con un riesgo legal que Felipe aceptó
el 2026-09-27 (subdeclarar frente a SUNAT). Pasar a planilla cierra ese riesgo y cuesta eso por cada persona que no se queda. **La
defensa de verdad es no dejar trabajar a nadie que no se vaya a quedar**: la evaluación de selección (hasta 3 horas, tarea simulada,
sin clientas reales ni valor comercial, sin vínculo) es la siguiente rebanada y no existe todavía.

**⚠️ Lo que la 0554 NO arregla.** Quien ya quedó cerrado como «se retiró» (0537) sigue inactiva y **sigue excluida de la planilla** de su
periodo: si ese periodo no está pagado, hoy no cobra lo que trabajó. Quitar esa exclusión exige reescribir `fn_planilla_calcular_nucleo`
(122 157 caracteres) y su **md5 se pide a PRODUCCIÓN justo antes de escribirlo**. La consulta (2) del encabezado de la 0554 los lista:
**correrla ANTES de pegar y devolver lo que salga.**

**Pegado el 2026-10-26** (Felipe devolvió las filas de comprobación). La 0553 dio `true · true · true · 15 · true · 553`. La 0554 movió a
**2 personas** (Robert Cabrera y Emily Rico, sede OTRU, sin hijos) y dejó `0 · 0 · 554`: ninguna activa sigue de prueba y ninguna prueba
abierta. **Lo medido antes de pegar la 0554 y que sigue abierto:** dos personas cerradas como «se retiró» —**Mariel Sarmiento** (prueba
16/10 → 21/10) y **Noelia Ibarcena** (19/10)— con el periodo 28/09–28/10 todavía **abierto**: la exclusión de la 0537 las deja fuera de la
planilla, o sea que **no se les paga lo que trabajaron** y el periodo cierra el 28/10. Se arregla con la 0555 (reescribe
`fn_planilla_calcular_nucleo` quitando el bloque «CAMBIO 0537»), que exige el **md5 de PRODUCCIÓN justo antes de escribirla**.

**0555 · quien se retiró en prueba cobra lo que trabajó · SQL PEGADO (2026-10-26) · MUEVE PLATA.** Felipe devolvió la comprobación:
`true · true · true · true · false · 1 · 121868 · aad8a0f00628539f27a4d789a4c1ac04 · 555` — la función de producción es exactamente la que se
probó y ya no lee si alguien se retiró. **Falta mirar** que Mariel Sarmiento y Noelia Ibarcena aparezcan en la planilla del periodo abierto
antes de cerrar el 28/10. Producción medida el 2026-10-26: 122 157
caracteres, 0 retornos de carro, una versión, con «CAMBIO 0537», md5 `4e25d9fd99e5e6a4e8f82952207c0652` — idéntico al cuerpo del archivo
de la 0537. La 0555 parte de ese cuerpo y **solo quita el bloque de la exclusión** (26 líneas de diferencia, todas dentro de él; el cuerpo
nuevo queda en 121 868 caracteres, md5 de la función `aad8a0f00628539f27a4d789a4c1ac04`); su guardia se niega a pegar sobre cualquier otra
versión y acepta las variantes CRLF y sin comentarios. La función **ya no lee `pruebas`**. Quien se retiró se paga **como quien no fue apto**:
lo que trabajó, **sin asignación familiar y sin EsSalud** (su vínculo sigue siendo «prueba», 0484/0537) — comprobado campo por campo contra
un control «no apto» con las mismas horas. **Pregunta para el contador:** las personas que se fueron en prueba (estas dos y las anteriores)
no generaron EsSalud; la 0555 no lo decide. Pruebas: **447 → 14/14** (puesta en rojo devolviendo la función de producción: 8 fallas),
430 (21/21) y 446 (17/17) actualizadas porque afirmaban justo la conducta derogada; **suite completa 348 de 352**, los mismos 4 que fallan
igual en la 0552. Hasta que esté pegada, la salida de emergencia es pagarles aparte, fuera del cierre, y dejarlo anotado.

**Orden para pegar.** (1) 0553 (no mueve plata). (2) Correr las consultas (1) y (2) del encabezado de la 0554 y devolverlas. (3) 0554,
solo con OK explícito a las cifras de arriba. (4) Recién entonces fusionar el PR: **fusionar ES publicar**. Si el código llega antes que
la 0553, Turnos usa el 15 y Parámetros sigue mostrando «días de prueba»; nada se rompe.

**Probado.** `tsc` limpio; vitest verde (nuevas: `periodo-de-prueba` 19, `feriado-recien-ingresado` 20; `parametros` 34; en total 2 953). En un Postgres
16 propio con las 552 migraciones, pgTAP y pg_cron: **444 → 54/54** (adaptada al parámetro nuevo), **445 → 19/19** y **446 → 17/17**, las
dos nuevas puestas en rojo a propósito de tres maneras cada una. **Suite completa: 347 de 351 archivos**; los 4 que fallan (122, 136, 301,
386) fallan **igual** en una base con solo hasta la 0552 (límites de mi imitación de Supabase y un defecto previo de la 386).

**Quedó pendiente (cada cosa es la siguiente rebanada).** (a) Limpiar el legado: tabla `pruebas`, `fn_prueba_cerrar`, `fn_pruebas_abiertas`,
Bandeja, terminal (0539), panel de Contratos y 27 pruebas pgTAP que aún crean personas «prueba»; la base **todavía acepta asignar «prueba»
por `fn_set_tipo_vinculo`** (ninguna pantalla lo ofrece). (b) Alertas de decisión en los días 60/75/85 con margen. (c) Baja express y
liquidación corta con reloj de 48 horas y entrega guardada. (d) Módulo Selección (evaluación breve sin vínculo). (e) Periodo de prueba
ampliado a 6/12 meses por pacto escrito. (f) Ficha de alta/baja para T-Registro. **Citas legales sin verificar contra el texto oficial:**
escala vigente de multas (art. 48 RLGIT), el numeral y el plazo de las 48 horas, el art. 168 del Código Penal; las valida el área legal.

---

## 2026-10-26 — Aviso «hay una versión nueva» que baja desde arriba (panel y «Lo mío») · sin SQL · EN PR (borrador) · rama `claude/amazing-clarke-7bi1ly`

**Qué es.** Felipe pidió que, cuando se publica una mejora y alguien tiene Dynamic abierto, baje desde el borde de arriba una barra
como la de retail: «Hay una versión nueva de Dynamic». Botones **Actualizar ahora** y una X (**Más tarde**). **No recarga sola**:
quien tiene la pantalla abierta puede estar escribiendo algo sin guardar.

**Cómo funciona.** `next.config.ts` hornea `VERCEL_DEPLOYMENT_ID` en el navegador al construir; `/api/version` devuelve el del
despliegue que atiende. Cada 3 minutos con la pestaña a la vista —y al volver a ella— la página compara; si difieren, baja la barra
(`components/aviso-version-nueva.tsx`, montado en los layouts de `(admin)` y `(mio)`). «Más tarde» la descarta hasta que llegue OTRA
versión. Sin id (dev, `next start`) el aviso se apaga entero. Lógica pura y su prueba: `lib/version-despliegue.ts`,
`tests/version-despliegue.test.ts`. Hay novedad en `novedades.ts` (audiencia «todos»).

**Medido.** En navegador real (Playwright, servidor de desarrollo con el id simulado) la barra sale con versión distinta, **no** sale
con la misma ni con una respuesta vacía, «Más tarde» la quita y no vuelve en la siguiente consulta, y otra versión distinta sí la
vuelve a sacar. Se ve bien en claro, oscuro y a 390 px. `tsc`, ESLint y las pruebas de novedades en verde.

**⚠️ Sin comprobar contra Vercel de verdad — se comprueba una vez, tras publicar.** Si el proyecto tiene **Skew Protection**, una
pestaña vieja queda fijada a SU despliegue y la consulta a `/api/version` podría contestar la versión vieja: el aviso **nunca saltaría**
(falla hacia el lado seguro: no avisa, jamás avisa de más). Prueba: con una pestaña del panel abierta, publicar cualquier cambio y
esperar ≤3 min; si no baja la barra, es esto y el arreglo es pedirle a Vercel la versión sin fijar. Quien lo mida: anotarlo aquí.

**Fuera, a propósito.** El **terminal** (la Mac mini de la sede): lo toca cualquiera para marcar, tiene su propio service worker y su
cola sin conexión, y recargarlo por un aviso es una decisión aparte. Si el terminal necesita enterarse de las versiones nuevas, es otra
rebanada con su propio criterio.

**Publicar.** No hay migración. Fusionar el PR ES publicar (`main` se publica sola): pedir OK a Felipe.

---

## 2026-10-26 — «Parámetros»: los números del sistema se cambian desde una pantalla, con puerta y con historial · migración 0552 · SQL PEGADO (2026-10-26) · FUSIONADO Y PUBLICADO (PR #602, 2026-10-26) · rama `claude/stoic-archimedes-8h71yn`

**Qué es.** Felipe pidió un módulo donde DO cambie sin código los números que mueven el sistema (días de prueba, escalera
disciplinaria, porcentajes, sueldo base, provisiones), con historial de quién y cuándo, y con la lista de a quién le afecta antes
de confirmar. Se acordó construirlo **por rebanadas**; esta es la primera. Tres decisiones suyas (2026-10-26): (a) el líder de DO
opera lo operativo y lo de plata, y **solo la dirección (admin) toca lo normativo**; (b) **la escalera disciplinaria no es editable**
en esta entrega —es del RIT— y entra después atada a una versión del RIT; (c) nombre «Parámetros», dentro de Configuración.

**El censo (medido leyendo el repo; no exhaustivo).** Los números que mandan viven en cuatro sitios y ninguno deja rastro de quién
los movió: `configuracion` (jsonb sin autor, fecha ni vigencia; la RLS deja escribir a admin/líder de DO directo desde el navegador),
`parametros_laborales` (versionada, «se escribe por migración»: RMV, EsSalud, movilidad, asignación familiar, bonificación
extraordinaria, bono de cumpleaños), constantes dentro de funciones (la prueba de 3 días, la escalera 3→2→1 de tardanzas y sus 12
meses, recargos 25 %/35 %, 48 h) y constantes en TypeScript (`rangos.ts`; subir la RMV obliga a mover **cuatro** sitios a la vez).
`descanso_medico_aviso_dias` guarda **dos** números en una clave: `avisar_desde` (15, operativo) y `umbral_essalud` (20, el tope del
RIT art. 31 f, que usa la planilla): el catálogo apunta a un campo y no a la clave entera.

**Lo que cambia para quien la usa.**
- **Pantalla `/admin/parametros`** (solo DO y admin). Tres parámetros se pueden cambiar: días de prueba antes del contrato (1–15,
  hoy 3), horas de espera del auto-cierre (1–12, hoy 3) y desde cuántos días de descanso médico se avisa a DO (1–20, hoy 15). El
  tope de 20 días del RIT se muestra aparte y sin botón. Cambiar pide un motivo y pasa por dos pasos: valor → **a quién afecta**
  (las personas de prueba cuya situación cambia; las personas a las que se empezaría o dejaría de avisar) → confirmar.
- **Historial** con quién, cuándo, de qué a qué y por qué, y un «Volver a este valor» que es un cambio nuevo, no un borrado.
- **«Días de prueba» ya no está clavado**: `fn_prueba_dias_plazo()` lee `configuracion.prueba_dias` (parte en 3, el de siempre). Las
  pantallas ya recibían el número como columna (`dias_plazo`), así que ninguna cambia.
- **Un cambio hecho a mano en el SQL Editor también deja rastro**, marcado «A mano en la base» y sin autor; antes no dejaba nada.
- **Un UPDATE/DELETE directo desde el navegador** sobre una de esas claves ya se rechaza. Apariencia, Educación y la firma de la empresa
  no están en el catálogo y se escriben como siempre.

**Antes de pegar (en el mismo mensaje en que se entrega el SQL; un md5 es una foto y caduca).** La 0552 reescribe UNA función,
`fn_prueba_dias_plazo()` (la de la 0536, `select 3;`). Su cuerpo no tiene saltos de línea, así que ni el CRLF de Windows lo cambia.
**md5 de PRODUCCIÓN pendiente**: la consulta (1) del encabezado debe dar `2645ded8d962eebe8104370a3d5ac219`, 11 caracteres, `i` y
`false`; la guardia de la migración compara el cuerpo sin espacios y **PARA** ante cualquier otra versión (y acepta la ya
reescrita, así que repegar no falla). La consulta (2) debe volver sin funciones **no** `SECURITY DEFINER` que escriban esas claves
(esas dejarían de poder); la (3) trae los valores de partida: `auto_cierre_horas` entre 1 y 12 y `avisar_desde` entre 1 y 20, porque
el trigger exige esos límites cuando alguien cambie el valor. **No toca la planilla**: `fn_planilla_calcular` lee las mismas claves con
la misma forma de siempre; por eso no hay md5 de la planilla.

**Pegado el 2026-10-26** (Felipe devolvió las filas de comprobación, después de fusionar: el frontend salió antes que el SQL, como
estaba previsto, y mientras tanto la pantalla decía «Falta pegar la migración 0552»). El `select` final dio lo esperado:
`parametros_en_el_catalogo` = 4, `el_candado_esta_puesto` y `el_candado_corre_con_quien_escribe` en `true`, `dias_de_prueba_hoy` = 3,
`la_funcion_lee_la_tabla` y `la_fila_existe` en `true`, `registro` = `552 · los_parametros_tienen_puerta_y_dejan_rastro`. La guardia
de la migración dejó pasar la función de partida, o sea que la de producción era la de la 0536 (`select 3;`) tal como se esperaba.
**No se vieron** las consultas (1)–(3) de «ANTES DE PEGAR» —se corrió directo la migración, que tiene su propia guardia—; la (2) sigue
siendo útil: si alguna función de producción pegada a mano fuera del repo escribe esas claves sin ser `SECURITY DEFINER`, dejaría de
poder hacerlo. Queda pendiente la primera prueba real de la pantalla en producción (ver una fila, y mejor un cambio reversible).

**Si el código llega antes que el SQL.** `main` se publica sola. La pantalla lo detecta (PGRST202, la función no existe) y dice «Falta
pegar la migración 0552» en vez de romperse; nada más depende de la 0552 hasta que se pegue. El renglón «Parámetros» y la novedad
(solo para DO) sí aparecen.

**Probado.** Typecheck limpio en los tres paquetes; **2 907 pruebas vitest verdes** (32 nuevas en `tests/parametros.test.ts`, más el
contador y el permiso del menú); ESLint limpio sobre lo nuevo. En un **Postgres 16 propio con las 524 migraciones de `main`** (solo
fallaron `pg_cron` y una columna de storage de mi imitación de Supabase; ninguna toca esto): la **prueba 444 da 55 de 55, seis veces
seguidas**, y rompiendo la migración a propósito de **15 maneras** (sin trigger, trigger `SECURITY DEFINER`, sin límites, sin gate
normativo, autor pegado a la transacción, historial editable, tabla legible directo, días de prueba clavados, la hora vuelta a
`now()`…) **se pone roja las 15 veces**. «Revertir» (el del encabezado) se probó tal cual, y repegar la migración deja todo igual.
En TypeScript, 6 mutaciones atrapadas, una de ellas (el borde de `>=` en el aviso) solo después de agregar el caso que la dejaba pasar.
**En navegador** (Chromium con la API de Supabase simulada, interceptando las llamadas): el flujo completo —abrir, validar (el 30 se
rechaza con «Va de 1 a 15 días»), ver «Le cambia a 2 personas», confirmar con la llamada correcta a `fn_parametro_cambiar` y «Volver a
este valor»—, en 1440 y 390 px, claro y oscuro, más los dos estados de borde («Falta pegar la migración» y una integrante sin acceso):
sin errores de consola ni desborde horizontal. La primera pasada encontró un defecto real y está corregido: en celular el botón
«Cambiar» quedaba fuera de pantalla (última columna de una tabla que se desplaza); ahora sube junto al valor.

**Dos hallazgos de la prueba, ya corregidos.** (1) *El empate de `now()`*: la hora del historial era `now()`, que vale lo mismo en toda
la transacción, y dos aserciones pasaban o fallaban según el orden de un uuid al azar (la familia de falsos rojos que este archivo ya
documenta). Ahora es `clock_timestamp()`: la hora real de escritura, y la prueba ya no depende del azar. (2) *La guardia* comparaba un
marcador con el **número** de la migración y se negó a repegar tras renumerar (0551→0552, ver abajo); ahora compara un marcador de
**contenido** (`prueba_dias`).

**Renumerada de 0551 a 0552 (prueba 443→444).** Mientras se construía, el PR #601 tomó el 0551. Se trajo `main` a esta rama (merge),
se renumeraron solo estos archivos y se probó con **las dos migraciones aplicadas en orden** (0551 de Normas y luego esta). Las dos son
independientes: no tocan las mismas funciones.

**No probado.** pgTAP real ni el CI `db-tests` (el banco local usa un sustituto mínimo: lo fiable es `db-tests` de GitHub); la
pantalla contra una API y unas RLS reales (la simulé: lo que devuelve la base lo dicen las pruebas SQL, no esta); nada
contra producción (la consulta (1)–(3) la corre Felipe); los grants reales de Supabase (la migración revoca y concede explícito para no
depender de los de por defecto); y los límites 1–15 / 1–12 / 1–20 son una **propuesta** para atajar errores de tecla, no una norma:
Felipe los puede mover con una migración.

**Siguiente.** Rebanada 2: plata ya versionada (`parametros_laborales`: RMV, asignación, movilidad, tasas, bonos) y sueldo base por
rango envolviendo `fn_fijar_base_declarada`, con **vigencia y vista previa de a quién le cambia**. Rebanada 3: provisiones, que viven en
`configuracion` **sin fecha** (cambiarlas reescribiría el historial) y necesitan vigencia antes de ser editables: eso reescribe
`fn_planilla_calcular`, con su protocolo de md5. Rebanada 4: la escalera disciplinaria, atada a una versión del RIT.

## 2026-10-26 — Normas cuenta a los practicantes (con cuenta, invitados y sin cuenta) · migración 0551 · ESCRITA Y PROBADA EN BANCO · **SQL PEGADO EN PRODUCCIÓN (2026-10-26)** · FUSIONADA (PR #601) · rama `claude/epic-ramanujan-rr0p0u`

**Qué es.** Felipe, con la captura de Normas → Constancias: «en normas también deberían aparecerme los practicantes, deben
aparecer todos incluyendo los que cuenten con su correo dentro del sistema y los que fueron invitados». Medido, no supuesto:
la lista sale de `fn_poblacion_obligada()` (activo y `tipo_vinculo = 'planilla'`) y el practicante, que es un vínculo propio desde la
0322, quedaba fuera. Pero fuera **solo de la lista**: `fn_acusar_documento` no mira la población y el aviso «te falta el RIT» de «Lo
mío» tampoco, así que un practicante con cuenta recibía el aviso, firmaba, y su constancia se guardaba **sin contarse en ningún
sitio** (la prueba 443, sin la migración, cuenta 0 constancias en el numerador aunque la de la practicante ya está guardada). Y quien no tenía cuenta no tenía por dónde
recibir su cargo en papel: «registrar en papel» vive en la fila de esa lista.

**Lo que cambia.** Un solo cambio, en la única fuente: `fn_poblacion_obligada()` pasa a `planilla` **+ `practicante`** (activos y
sin cuentas de servicio). De ahí cuelgan, sin tocarlas, la lista y el «N/M» de Normas, la insignia roja de Constancias, la
Bandeja, la hoja imprimible y la alerta de Disciplina (60.5). Los tres estados de acceso entran: con cuenta que ya entró, invitado
que no abrió el correo (`invitar` enlaza `auth_user_id` al aceptar GoTrue, así que sale como «con cuenta») y sin cuenta.
En pantalla solo cambia una frase: la hoja imprimible decía «personal activo y en planilla» y con practicantes habría sido falso
en un papel que se enseña a un inspector; ahora dice «con contrato de trabajo o convenio de prácticas».

**El contrapeso.** `fn_acuses_politica_salarial(int)` también cuelga de esa función y habría arrastrado a los practicantes a la
hoja de Política salarial, de la que están fuera **a propósito** (Ley 30709 no les alcanza, 2026-08-31; la pantalla ya los muestra
aparte en «También dejaron constancia»). Se reescribe con una condición más, `p.tipo_vinculo = 'planilla'`, y devuelve la misma
lista de antes. Es la única función reescrita además de la de población; ninguna de las tres que cambian de resultado se copió.

**Qué NO cambia.** `prueba` (días de selección, 2026-08-18), `rxh`, `no_trabajador`, inactivos y cuentas de servicio siguen fuera.
Ninguna constancia ya registrada se toca. `fn_reglamento_no_acusado` (el freno por persona) ya cubría a un practicante.

**Antes de pegar.**
1. **La 0551 reescribe dos funciones y NO se pidió su md5 a producción** (esta sesión no corre SQL contra producción). Lo comprueba
   la guardia del bloque 0 al pegar: acepta el cuerpo de partida —tal cual, sin comentarios, con o sin `\r`— y el de llegada, y
   **PARA sin tocar nada** ante cualquier otro. Se probó con 7 casos (cuerpo ajeno, versión previa a la 0491, política alterada: paran;
   CRLF, sin comentarios, repegado: pasan). Partida medida sobre el repositorio: `fn_poblacion_obligada` 195 car. `1b69c217…`;
   `fn_acuses_politica_salarial` 1 309 car. `e7e56114…`. Si el hook renumera, hay que volver a medir los md5 de llegada (los
   marcadores `CAMBIO 0551` cambian con el número).
2. **Pegarla ANTES de fusionar el PR** (fusionar es publicar). **Pero el orden no se va a cumplir:** Felipe pidió el automerge
   (2026-10-26) y la sesión no puede pegar el SQL —el conector de Supabase de la sesión solo ve los proyectos Fructus, FastFruit y
   vonatur, no el de CAYLA—, así que el PR se fusiona solo cuando `db-tests` y `ui-tests` den verde y **el frontend sale antes que el
   SQL**. Es seguro: no llama a nada nuevo; solo se adelantan la frase del papel imprimible y la novedad (que dice «ya aparecen» y
   hasta pegar no es cierto). El orden no se cumplió, como se avisó; la 0551 se pegó después (ver «Pegado el 2026-10-26»).
3. Para ver de antemano cuánto va a subir el contador (solo lectura, en el SQL Editor):
   `select count(*) filter (where auth_user_id is not null) as con_cuenta, count(*) filter (where auth_user_id is null) as sin_cuenta
   from personas where tipo_vinculo = 'practicante' and estado = 'activo' and not cuenta_de_servicio;`
4. Después de pegar, el `select` del final de la migración: `practicantes_activos` = `practicantes_contados` y
   `politica_sin_practicantes = true`.

**Pegado el 2026-10-26** (Felipe devolvió las filas). Antes de pegar, su consulta de solo lectura dio **4 practicantes activos, los 4
con cuenta y ninguno sin cuenta**. **El primer intento no se aplicó, y fue un error de la sesión:** el bloque que se le dio por el chat
traía el `select` final corrupto (`where tipo_tipo_vinculo_placeholder`, una línea inventada al recortar la cabecera) y el editor
revirtió todo el texto —se reprodujo en un banco: un error en la última sentencia deja `sin 551 | incluye practicante: false`—. El
segundo intento, con las líneas 128–279 del archivo de `main` sin retocar, pasó la guardia y devolvió: `registrada` = `551
los_practicantes_tambien_reciben_las_normas`, `poblacion_incluye_practicantes` = `true`, `practicantes_activos` =
`practicantes_contados` = **4**, `politica_sin_practicantes` = `true`, `equipo_obligado` = **22**. **Lección de método:** el SQL que se
entrega por el chat se saca del archivo con `sed -n`, nunca se reescribe a mano, y un aviso sobre un bloque va ANTES del bloque.
El `md5` de partida de producción sigue sin medirse a mano: la guardia lo comprobó y pasó (acepta el de la 0491 y el de la 0458).
**«La oficina Trujillo» es la sede `OTRU` («Oficina TRU», tipo central, donde están los practicantes en áreas de oficina):** no salía
en Constancias porque nadie de esa sede estaba en la población; su chip y su opción en el filtro «Sede» se arman con las filas que
llegan, así que aparece sola.

**Lo que se verá.** El «N de M» de cada documento y «constancias pendientes» suben en practicantes × documentos que piden
constancia, hasta que cada uno la deje o DO registre su cargo en papel: es gente que faltaba contar, no un retroceso (la novedad
`2026-10-26-normas-cuenta-a-los-practicantes-en-sus-constancias` lo dice así). En Disciplina, un practicante sin constancia del
Reglamento vigente pasa a salir en la alerta previa.

**Decisiones que quedaron tomadas por defecto (Felipe las puede revertir).** (a) La hoja imprimible incluye a los practicantes,
porque sale de la misma función que la pantalla: un «19 de 21» en el papel y otro número en pantalla es el defecto que cerró la
0265. Si se prefiere un papel solo con quien tiene contrato de trabajo —como hace Política salarial—, es un cambio aparte.
(b) Disciplina los incluye (coherente con Normas). (c) Política salarial sigue sin ellos. (d) No se agregó una etiqueta
«Practicante» a la fila: pediría una columna más, o sea `drop` + `create` de `fn_acuses_documento`, y no se pidió.

**Probado.** Banco propio: Postgres 16 nativo con un shim de Supabase (roles, `auth`, `storage`, `cron`, mini-pgTAP) y las 550
migraciones. **Prueba nueva 443: 20/20 con la 0551 y 12 en rojo sin ella** (las 8 verdes sin ella son las que deben quedarse
quietas). 3 mutaciones de la migración ponen en rojo justo las aserciones que las custodian. **Suite entera (347 archivos) con y sin
la 0551: la única diferencia es la 443**, aserción por aserción; las 5 rojas que quedan están igual en los dos lados (ruido del
mini-pgTAP). Control previo en verde: 163, 170, 171, 203, 208 y 388. Typecheck limpio y 2 873 vitest verdes.
**No probado:** pgTAP real ni el `db-tests` de GitHub (señal fiable), nada contra producción, el md5 real de producción (lo mide la
guardia al pegar) y la pantalla en un navegador (el panel no levanta aquí sin `.env.local` ni Supabase): el único cambio visible es
una frase del papel imprimible.

---

## 2026-10-25 — La Bandeja cuenta 33 y no 96 · los 61 correos tienen salida · un pago único ya sustentado no pide calendario · migraciones 0548 y 0549 · SQL PEGADO (2026-10-25) · SIN FUSIONAR (PR #597, borrador) · rama `claude/notifications-calendar-errors-2e8886`

**Qué es.** Felipe preguntó tres cosas con tres capturas: «si es pago único, ¿para qué me pide calendario?», «la mayoría
de las notificaciones son ruido» y «¿61 fallaron?». Medido, no opinado: la insignia del menú decía **96 = 31 filas + 61
correos fallidos (un solo problema contado 61 veces) + 4 de Normas**; el chip «Todo» decía 31 y el Dashboard habría dicho 92
(tres cuentas para una pregunta). De las 31 filas casi todas son plazo legal, dinero o una persona esperando: **no se
construyó un botón «descartar» general** (ver «Decisión abierta»). Los 61 fallan por un 403 de Resend, «el dominio cayla.pe no
está verificado», y por «sin líder de equipo con correo»: la primera es configuración externa que solo Felipe arregla.

**Lo que cambia para quien la usa.**
- **Una sola cuenta** (`cuentaDeLaBandeja`): filas + 1 si hay correos que no salieron + 1 si hay constancias de Normas. Menú y
  Dashboard dan el mismo número (33 con los datos de la captura). Las «atascadas» se reintentan solas y ya no cuentan.
- **Tarjeta «Sistema»** plegada a una línea (52 px, antes 228) con la causa en palabras y, al abrir, qué hacer. Botón
  «Revisar y resolver estos avisos» (solo DO): primero una vista previa, y solo al confirmar reencola lo que aún es cierto y da
  por cerrado lo que ya no. **Antes de pulsarlo hay que arreglar Resend**, o lo reencolado vuelve a fallar.
- **Ruta de correo** (`/api/alertas-encargadas`): ante una avería del canal corta el lote en vez de gastar el intento de todas
  las filas (así 3 días de 403 mataron 61); clasifica el fallo por su causa (un mismo 403 ya no sale dos veces); los días de
  «vence en N» se calculan al enviar y no al generar; si el correo sale tarde, lo dice.
- **Educación:** un pago único con una constancia aprobada ya no cae en «sin calendario»; el campo se llama «Fecha del pago»
  y, si ya está sustentado, no se muestra. Mensual, ciclo y otra quedan idénticos.

**Antes de pegar (en el mismo mensaje en que se entrega el SQL; un md5 es una foto y caduca).**
1. **0548 — no reescribe ninguna función, no hay md5 de partida.** Corre las tres consultas de SOLO LECTURA del encabezado
   (la que cuenta los 61 por destino y causa, el `pg_get_constraintdef` de `alertas_estado_check` y los estados presentes) y
   manda las filas. La fila «2 · REENCOLAR CON VENTANA RENOVADA» dice cuántos contratos y vacaciones vigentes se salvan.
2. **0549 — SÍ reescribe `fn_educacion_situacion`.** md5 de PRODUCCIÓN pendiente: la consulta está en su encabezado; se
   espera 4 006 caracteres y `f0ddaf5b…` con 0 marcadores (4 094 con 88 retornos si se pegó desde Windows). Su guardia por md5
   **PARA** ante cualquier otro cuerpo. Corre también las consultas de impacto y de residuo del encabezado.
3. **ORDEN CON LA 0526** (borrador sin pegar, rama `agitated-nightingale-7e118e`, reescribe la misma función): pegar la 0549
   primero; la 0526 se rehace después sobre su cuerpo y con su propia guardia (la fusión de tres vías dio 0 conflictos). Pegada
   en el orden contrario, la 0526 **revierte en silencio** la 0549.
4. Las dos se pegan **antes** de fusionar el PR. Si el frontend llega antes: nada se rompe (la tarjeta sin botón, los textos de
   pago único con constancia dicen la verdad), pero el número rojo de Educación no baja hasta pegar la 0549.

**Pegado el 2026-10-25** (Felipe devolvió las filas de comprobación). Antes de pegar, `fn_educacion_situacion` en producción medía
4 006 caracteres, md5 `f0ddaf5b…`, 0 retornos y 0 marcadores: la 0450 sin retoques, así que la 0526 no estaba pegada y la guardia de
la 0549 pasó. **0548:** las nueve columnas de la comprobación en lo esperado y `sin_salida_hoy = 61`, igual a los 61 de la tarjeta.
**0549:** `registradas` = 548 · 549 · 550 y la función en 4 959 caracteres, md5 `faba3345…`, el de llegada declarado en su encabezado.
Con las dos pegadas, el PR se puede fusionar **solo con OK de Felipe**; mientras no se fusione, el botón no existe en pantalla.

**Pendiente de Felipe (a mano, no lo hace el código).** Verificar el dominio de envío en resend.com/domains con `RESEND_FROM`
exactamente en ese dominio y comprobar `RESEND_API_KEY` y el redeploy; cargar en Equipo el correo de las líderes de las sedes
que salgan en la consulta de causas. Sandra Ramírez (Pop in colors): si su frecuencia está en blanco, un clic —elegir «Pago
único» y guardar con la fecha vacía— la deja al día; **no guardar «Pago único» + 25/10 antes de pegar la 0549**: la pasaría a
«falta enviar».

**Decisiones abiertas de Felipe.** (a) Pago único con fecha futura y constancia aprobada queda callado para siempre: ¿el
comprobante inicial prueba el pago o puede ser una proforma? (b) Mensual/ciclo/otra con «último pago» siguen en «sin
calendario»: hace falta una columna `es_ultimo_pago`. (c) ¿Botón «descartar» general? Se recomienda que no: casi todos los
tipos de fila son plazo legal, dinero o una persona esperando respuesta, y el único candidato real (`educacion` sin calendario) se arregló en la fuente.
(d) «Normas» dice «N constancias pendientes» (la suma es de pares persona-documento) y pesa 1 en el menú. (e) ¿El proyecto de
Vercel tiene fluid compute? Decide si `maxDuration` sube de 60 a 300 s.

**Probado.** Typecheck limpio y 2 851 pruebas vitest verdes. **440: 94/94 y 441: 29/29** en un Postgres 17 nativo con las
migraciones 0001–0544 (el Docker de esta Mac estaba colgado); sin sus migraciones se ponen rojas, con 18 mutaciones de la
0548 y 54 de la ruta en rojo; las 18 pruebas que tocan `alertas` y las 355/226/421/365 dan lo mismo con y sin ellas; el
caso de Sandra y el de un contrato con aviso de hace 10 días se reprodujeron de punta a punta con las funciones reales; el
barrido de 1 080 estudios solo cambia los pagos únicos con constancia aprobada. La pantalla se midió en el navegador con un
simulador de la API (1440 y 390 px; el modo oscuro solo antes de plegar la tarjeta). **No probado:** pgTAP real ni el CI `db-tests` de GitHub, los grants
reales de Supabase, Resend vivo, y nada contra datos de producción. La 440 original abortaba contra el esquema real
(fixtures); lo cazó un revisor y quedó corregido.

**Hueco preexistente, cerrado aparte.** La política `alertas_marcar_leida_propia` (0003) dejaba a la dueña de una fila
cambiar `estado` e `intentos` por PostgREST. Lo cierra la 0550 (entrada de abajo, PR #598, ya fusionado y con el SQL
pegado): un trigger que solo deja cambiar `leido_at`. Las funciones de la 0548 son `SECURITY DEFINER` y corren como
`postgres`, así que el trigger no las toca; el CI de este PR lo comprueba con la 0550 ya en main.

## 2026-10-25 — Una alerta solo se marca leída: se cierra el hueco de la política de `alertas` · migración 0550 · SQL PEGADO (2026-10-25) · SIN FUSIONAR (PR #598, borrador) · rama `claude/sad-chandrasekhar-10f114`

**Qué es.** El revisor de la 0548 midió un hueco que viene de la 0003: la política `alertas_marcar_leida_propia` deja a la
dueña de una fila hacer UPDATE, y una política filtra filas, no columnas. Medido otra vez contra el esquema real
(`authenticated`, sesión de una integrante): `update alertas set estado = 'enviado', intentos = 0, … where persona_id =
<la suya>` da UPDATE 1 y deja **once columnas** reescritas —no las cinco del hallazgo; entran `tipo`, `canal`, `payload`,
`created_at`, `ultimo_intento_at` e `id`—. El `payload` pesa: `/api/alertas-encargadas` arma el correo con él, así que una
integrante podía fabricar un aviso con el texto que quisiera y el despacho lo mandaba a su encargada o a DO desde el
remitente verificado de Dynamic. La brecha creció sola con cada `add column` (0354: `nota_fallo`; 0362: tres más). La
0550 pone un trigger BEFORE UPDATE con **lista permitida** —solo `leido_at` puede cambiar— que aborta si `current_user <>
'postgres'`, el molde de `fn_bloquear_rol_directo` (0296) y `fn_bloquear_sede_directa` (0342). Una columna que se agregue
mañana nace cerrada.

**Lo que cambia para quien la usa.** Nada visible: ninguna pantalla ni ruta escribe `alertas` directo (el despacho usa la
llave de servicio solo para llamar a las funciones por `rpc`), y `leido_at` no lo escribe nadie hoy. Lo que sí cambia: un
`PATCH /rest/v1/alertas` armado a mano deja de poder mover cualquier cosa que no sea `leido_at`.

**Antes de pegar.** Dos consultas, escritas en el encabezado de la migración (sección «ANTES DE PEGAR»). La primera debe
volver SIN FILAS: nombra cualquier función de producción, pegada a mano y fuera del repo, que haga `update alertas` sin ser
`SECURITY DEFINER` de `postgres` — esa dejaría de poder escribir. La segunda trae `registro_550` en `null` y los triggers
que ya tiene `alertas` (hoy ninguno). **No depende de la 0548** y se puede pegar antes o después; no reescribe ninguna
función, así que no hay md5 de partida. Como toda migración: se pega ANTES de fusionar, aunque aquí no hay código nuevo que
dependa de ella. **Pegada el 2026-10-25** (Felipe devolvió la fila de comprobación): el freno está puesto y activo, no es
`SECURITY DEFINER`, ningún escritor de `alertas` queda fuera (`escritores_que_el_freno_dejaria_fuera = 0`) y el registro dice
`550 · una_alerta_solo_se_marca_leida`. Con eso la consulta previa ya no hace falta: la tercera columna decía lo mismo.
Con la migración ya pegada, el PR se puede fusionar **solo con OK de Felipe** (fusionar es publicar) y con el comentario
`<!-- cayla:fusion-sesion -->` que pide el hook.

**Una decisión que quedó escrita y es de Felipe.** El freno rechaza también a `service_role` escribiendo DIRECTO
(`.from("alertas").update(…)` con la llave de servicio): solo pasan las funciones `SECURITY DEFINER`. Hoy nadie lo hace.
Si algún día se quiere dejar pasar a `service_role`, es cambiar una condición en `fn_bloquear_alertas_directo`, y la
prueba 442 tiene una aserción que lo fija hoy.

**Probado.** En un Postgres 17 nativo (sin Docker; Docker Desktop sigue colgado) con las 544 migraciones de `main`: la
prueba nueva **442, 33 de 33 con la migración y 22 en rojo sin ella** (las 11 que siguen verdes sin ella son los caminos
permitidos y los que ya cerraba RLS, que deben darse igual en los dos mundos). Suite entera (345 archivos) con y sin la 0550:
**la única diferencia es la 442**, aserción por aserción; los 39 archivos que fallan en ese banco fallan igual en los dos
estados (mini-pgTAP y `auth.users` incompleto). Las ocho pruebas que escriben `alertas` (179, 281–285, 288, 294) pasan
completas. Con la 0548 de `claude/notifications-calendar-errors-2e8886` dentro: su prueba 440 da 94 de 94 con y sin la
0550, y la 442 da 33 de 33. Concurrencia medida con dos sesiones: el despacho reserva y retiene la fila 4 s; la dueña marca
leída al mismo tiempo, espera, no falla y no le pisa `estado` ni `intentos`.

**No probado.** Contra producción (nada se aplicó); con pgTAP real (el banco usa un sustituto que difiere en `throws_ok`;
`db-tests` de GitHub es la señal fiable); por PostgREST de verdad (se simula con `set role authenticated` y
`request.jwt.claim.sub`, como las demás pruebas de la casa).

**Visto de paso, sin tocar.** `authenticated` conserva `TRUNCATE` sobre `alertas` por los grants por defecto, pero PostgREST
no lo expone. Y `grant select, insert, update, delete on all tables in schema public to authenticated` (0004) es la
línea que reabriría cualquier cierre hecho con grants: por eso esta migración no depende de ellos.

---

## 2026-10-21 — Una estación de retail deja de figurar en planilla · migración 0544 · SQL PEGADO (2026-10-22) · FUSIONADO (PR #578, 2026-10-22) · rama `claude/intelligent-elbakyan-cafd3f`

**Qué es.** Al cruzar el Seguro de Vida Ley contra quién está en planilla, «ESTACIÓN — Producción» salió como una
persona a asegurar (21 «a cubrir» cuando eran 20). Nació con los defaults de la tabla —vínculo `planilla`, en planilla,
S/ 1230— y solo después se marcó como cuenta de servicio; las seis anteriores estaban en «Sin vínculo laboral» porque
alguien las cambió a mano. La 0544 hace que `fn_set_cuenta_de_servicio`, al marcar, deje el vínculo en «Sin vínculo
laboral» (por `fn_set_tipo_vinculo`, con su rastro). Las dos entradas pasan por esa puerta: el alta de Equipo y el
interruptor de la ficha. Elegida por Felipe el 2026-10-21 entre tres (solo el alta · la puerta · la puerta + candado).

**Lo que cambia para quien la usa.** Desmarcar ya NO devuelve a la planilla: el vínculo se decide en Equipo, y la
ficha lo dice en el aviso. Una ficha cesada con otro vínculo ya no se puede marcar. Las consultas del Seguro de Vida
Ley ya filtran `cuenta_de_servicio` (las cuatro), pero eso llegó por el PR #579 (`main`), no por este.

**Antes de pegar.** md5 de producción medido el 2026-10-21 (Felipe devolvió las filas): `fn_set_cuenta_de_servicio`
da `2ef42078…` con 2571 caracteres y 59 `\r` — es la 0490 pegada desde Windows (el cuerpo del archivo con `\r\n` da
exactamente ese md5; `b9b3eb85…` es el del archivo con `\n`). Mismo código, nada roto. `fn_set_tipo_vinculo` y
`fn_crear_persona` coinciden byte a byte con el repositorio; la 490, la 504 y la 513 están registradas. El freno de la
0544 pasa contra esa variante. **Pegada el 2026-10-22** (Felipe devolvió la fila de comprobación): una sola versión nueva de la función, `anon` no
puede marcar, registro `544 · una_cuenta_de_servicio_no_queda_en_planilla`, y md5 de llegada `50c00bbd…` —el esperado,
pegada con saltos de línea normales—. La única estación en planilla seguía siendo «ESTACIÓN — Producción Lima», como se
esperaba. Con la migración ya pegada, el PR se puede fusionar **solo con OK de Felipe** (fusionar es publicar).

**Pendiente de Felipe (a mano, no lo hace la migración).** «ESTACIÓN — Producción» sigue en `planilla` hasta que la
pase a «Sin vínculo laboral» desde Equipo. La comprobación final de la 0544 la nombra mientras siga así. El candado
en la tabla (`check (not cuenta_de_servicio or tipo_vinculo = 'no_trabajador')`) queda para después, cuando esa fila
ya esté bien.

**Probado.** En un Postgres desechable con las 520 migraciones de `main`: la prueba nueva 436, 23 de 23; **sin la
migración 12 de sus aserciones se ponen en rojo**. Toda la suite (344 archivos), con y sin la 0544: la ÚNICA
diferencia es la 436 (los 19 archivos que fallan en ese banco fallan igual en los dos estados). Repegar la 0544 no
cambia nada; el freno se detiene ante una versión posterior, dos firmas o sin `fn_set_tipo_vinculo`. **No probado:**
la ficha en el navegador (solo cambiaron dos textos) ni contra la base real.

## 2026-10-21 — Seguro de Vida Ley: la póliza existe (Pacífico, Nº 143720), cuesta S/70 al mes y dos personas siguen sin certificado en mano · sin SQL nuevo · FUSIONADO Y PUBLICADO (PR #579, 2026-10-21) · corregido con las liquidaciones de prima en un PR nuevo, SIN FUSIONAR · rama `claude/vida-ley-liquidaciones`

**Qué cambió respecto de lo que decía este archivo.** Hasta hoy `estado.md` y el Reglamento decían «cotizado en La
Positiva, sin firmar». Felipe pasó quince certificados individuales y el seguro **está contratado con Pacífico
Seguros**: póliza colectiva **Nº 143720** (código SBS VI2007310027), contratante CAYLA S.A.C. La cotización de La
Positiva (S/170 al mes por 19 personas) ya no es la referencia. Este repo no dice por qué se eligió Pacífico; la
prima real y el inicio de la póliza salen de tres liquidaciones de prima (sección que sigue a los certificados).

**Lo que dicen los certificados** (leídos con `pdftotext`; sin nombres ni DNI aquí):
- 16 remuneraciones por muerte natural y 32 por muerte accidental o invalidez total y permanente por accidente, sin
  exclusiones (D. Leg. 688).
- **La cobertura de cada persona empieza a las cero horas del día 1 del mes en que Pacífico la declara por primera
  vez**, y dura mientras siga en la declaración de planilla y la prima esté pagada. Sin declaración no hay
  certificado ni cobertura: declarar tarde es un hueco sin seguro, y no se recupera.
- Si la prima no se paga y pasan 90 días desde la fecha fijada en las condiciones particulares, la póliza se
  extingue y terminan las coberturas de **todos**.
- Cada persona debe entregar a CAYLA una declaración jurada con firma legalizada que nombre a sus beneficiarios;
  sin ella se paga a los herederos tras una sucesión intestada. Al cesar, puede pedir continuar el seguro dentro de
  los 60 días siguientes (numeral 59.6 del Reglamento).
- **No traen** la fecha de inicio de la póliza, la prima, las condiciones particulares ni si se contrató la
  cláusula de «Cobertura Adicional a la Remuneración Máxima Asegurable». El inicio y la prima sí salen de las
  liquidaciones, abajo.

**Lo que dicen las liquidaciones de prima** (tres PDF que Felipe pasó el 2026-10-21; también sin nombres):
- Póliza 143720, plan «Vida Ley Empleados (D.L. 688)», **sin intermediación** (sin corredor, como confirmó Dante),
  pago al contado, una liquidación por mes. **Inicio de la póliza: 01/08/2026.** El fin no consta en ningún papel;
  el certificado dice «anual renovable».
- **Prima: S/70.00 al mes** (59.32 + 10.68 de IGV), **la misma en septiembre y en octubre** aunque la masa declarada
  subió de S/20,160 a S/22,420: entre esas dos liquidaciones no subió con la planilla. Es menos de la mitad de los
  S/170 de La Positiva (0.31 % de la masa de octubre). Más **S/5.00** (4.24 + 0.76) por una inclusión en octubre.

  | Documento | Cubre | Se emitió | Vence |
  |---|---|---|---|
  | Liquidación 3210083 | 01/09 al 01/10 | 31/08 | 30/09 |
  | Liquidación 3242885 | 01/10 al 01/11 | 06/10 | 31/10 |
  | Ajuste 3244429 (una inclusión) | 01/10 al 31/10 | 12/10 | 31/10 |

- **«La cobertura, por la vigencia indicada, se inicia con el pago de la prima.»** En ningún papel consta que se
  hayan pagado.
- Traen totales de remuneraciones y **no nombres**: no dicen a quién se declaró cada mes.

**El cruce (2026-10-21, consultas de Felipe en producción).**
- **Quince certificados en mano; los números son correlativos y la serie tiene dieciocho.** Faltan tres. No se sabe a
  quién corresponden.
- **Probablemente Pacífico declaró a 18 personas en octubre.** Los S/22,420 de esa liquidación entre 18 dan unos
  S/1,245 por persona, que cuadra con un sueldo base de S/1,230, y la serie tiene 18 números. **Es deducción, no un
  papel:** los tres certificados que faltan podrían ser de las dos personas de abajo.
- En planilla hoy, con vínculo `planilla`: **17 personas, masa de base legal S/21,400**. Quince tienen certificado
  en mano y **dos no**: una de TRU (ingresó el 2026-09-03) y una de AQP (ingresó el 2026-10-02), las dos con la
  ficha completa. Los nombres viven en la salida de la consulta, no en git.
- **La de TRU puede tener un hueco.** Su ingreso es posterior a la liquidación de septiembre (emitida el 31/08): si
  Pacífico la declaró por primera vez en octubre, la cobertura empieza el 1 de octubre y del 3 al 30 de septiembre
  estuvo sin seguro. Solo se salva si hubo una inclusión de septiembre, y ese papel no lo tenemos. La de AQP no
  tiene hueco si entró en la declaración de octubre.
- Nadie con certificado quedó fuera de planilla: los quince siguen en planilla.

**Decidido por Felipe (2026-10-21): el seguro se cuenta solo sobre `tipo_vinculo = 'planilla'`.** Quedan fuera
las personas de prueba (la prueba de tres días, 0536) y las estaciones. **Objeción registrada:** la consulta las
incluía a propósito porque la obligación nace con el trabajo efectivo y no con el contrato; mientras dura la
prueba esas personas no tienen seguro de vida (ni EsSalud, 0484). El riesgo es corto y chico, no cero. Cuando
alguien de prueba pase a contrato hay que declararla a Pacífico **ese mismo mes**, y nada en el sistema lo avisa.

**Lo que se corrigió en las cifras.** La consulta 4 dio «21 a cubrir» y S/26,320 de masa. Eran 20 personas más una
estación de retail (Lima, Producción): marcada `cuenta_de_servicio` —por eso la planilla (0491) no le paga—, pero
con vínculo `planilla`, en planilla y S/1,230, a diferencia de las otras seis estaciones (`no_trabajador`, S/1,130).
La causa es que el alta de una estación en Equipo (`fn_crear_persona`, 0513) inserta con los valores por defecto de
la tabla y la marca después. El 0.646 % que daba la consulta era S/170 de La Positiva sobre esa masa: **no es el
costo de Pacífico y no sirve para decidir**. La prima real es S/70 al mes (liquidaciones), 0.31 % de los S/22,420
declarados en octubre.

**Pendiente, en este orden.**
1. **Confirmar que se pagaron las liquidaciones (Felipe).** La cobertura «se inicia con el pago de la prima»:
   septiembre (S/70, venció el 30/09), octubre (S/70) y la inclusión (S/5); las dos últimas **vencen el 31/10**. En
   ningún papel consta el pago. Con 90 días de mora la póliza se extingue para todos.
2. **Pacífico o la corredora (Felipe):** pedir por su número los tres certificados que faltan y confirmar si son de
   las dos personas sin certificado; si no, declararlas en octubre (cubre desde el día 1 si se declara dentro del
   mes: preguntar hasta qué día). Preguntar también si la de TRU entró en una inclusión de septiembre, a quién
   corresponde la inclusión de octubre, cuándo termina la póliza y las condiciones particulares.
3. **Registrar la póliza en el MTPE** dentro de los 30 días de firmada. No consta en este repo que se haya hecho.
4. **Las declaraciones juradas de beneficiarios**, una por persona, con firma legalizada. No consta que se hayan pedido.
5. **Cambiar el vínculo de la estación de Producción** a «Sin vínculo laboral», desde Equipo (Felipe). Se hace por
   `fn_set_tipo_vinculo`; desde el SQL Editor esa función se niega porque no sabe quién la llama. No se verificó que
   Equipo deje cambiarlo desde el bloque de estaciones. La causa de fondo —el alta de una estación no fija el
   vínculo— está en otra sesión, rama `claude/intelligent-elbakyan-cafd3f` (PR #578, migración 0544, «Estaciones de
   retail nacen como "Sin vínculo laboral"»); su estado vive en su propia sección.
6. **Cargar la póliza en el módulo Seguros**, cuando se decida la prima y esté el fin de la póliza. El selector ya
   muestra «Vida Ley (va además del principal)» (captura de Felipe, 2026-10-22), así que el tipo existe. Datos: número
   143720, Pacífico Seguros, **inicio 01/08/2026**; el fin no consta (anual renovable) y **la prima es mensual y de
   grupo (S/70, S/75 con la inclusión)**, mientras el formulario la pide por persona y por todo el periodo: cómo
   anotarla es una decisión abierta de Felipe y DO. **No usar el atajo «Las de planilla»**: marcaría a las 17,
   también a quien aún no tiene certificado, y la lista de asegurados la daría por cubierta. **El lector de PDF no
   entiende estos certificados** (probado con `leerPolizas` el 2026-10-21: lee 0 pólizas de los quince): no traen
   vigencia ni prima ni el formato «Asegurado: nombre documento» que espera, así que todo se teclea y cada PDF se
   sube a la póliza de su persona, con la casilla de copiar a las demás sin marcar.
7. **Reglamento:** los tres puntos que esto bloqueaba (27.1 d, 59.6 y el anuncio al ingreso) dejan de depender de que
   exista la póliza. Revisarlos cuando se confirme que todas las personas de planilla están declaradas (ver
   `reglamento-pendientes-de-construir.md`, punto 26).
8. **El indicador del umbral de 20 trabajadores** sigue acordado para después de cerrar Vida Ley (tabla de «lo que
   no bloquea», más abajo). El conteo correcto hoy es 20 personas: 17 de planilla y 3 de prueba, sin estaciones.

**Qué se tocó en el repo.** Solo documentos y la consulta [`quienes_van_al_seguro_de_vida_ley.sql`](../scripts/sql-manual/quienes_van_al_seguro_de_vida_ley.sql):
ahora excluye las cuentas de servicio, cuenta solo `planilla`, ya no calcula el porcentaje contra los S/170 de La
Positiva y suma una consulta 5 (cruce contra los certificados, con una fila de ejemplo en vez de DNI reales).
**No probado:** nada se pegó ni se corrió en producción desde esta sesión; las cifras salen de lo que Felipe pegó del
SQL Editor. La consulta nueva se comprobó solo de sintaxis, contra una copia temporal de `personas`.

**Corrección con las liquidaciones (PR nuevo, solo documentos).** La primera versión de esta sección decía «dos por
declarar» y «no consta la prima»: con las liquidaciones, la prima es S/70 al mes, la póliza empezó el 01/08/2026 y
lo más probable es que Pacífico ya haya declarado a 18 personas, de modo que las dos sin certificado en mano pueden
estar declaradas (deducción, sin confirmar). Se agregó además lo que no estaba a la vista: la cobertura depende del
pago de cada liquidación. El comentario de la consulta de Vida Ley que decía que la prima no estaba en el repo se
actualizó. **No probado:** que las liquidaciones estén pagadas, y a quién corresponden los tres números de la serie.

## 2026-10-21 — Vida Ley entra a los tipos de seguro como seguro del sistema · migración 0543 · SQL SIN PEGAR · SIN FUSIONAR · rama `claude/seguro-vida-ley-tipo-9df9ee`

**Qué es.** Felipe vio «Tipos de seguro» con solo EsSalud y FOLA y preguntó si se agregaba Vida Ley. La 0528 ya
la daba por hecha como algo que DO agregaría con «+ Agregar un seguro»; ahora viene sembrada: una fila en
`seguros_tipos` con clave `vida_ley`, **complementaria** (va además del principal), con póliza, sin vínculos
automáticos y **del sistema** (no se archiva ni cambia de nombre por un clic). Con ella ya se puede registrar la póliza
colectiva a todas de una vez, leer el PDF y bajar la lista de asegurados. La descripción lleva lo que el
repositorio ya decía (D. Leg. 688 modificado por el D.U. 044-2019 y la Ley 31408; 16 y 32 remuneraciones; MTPE
en 30 días) y se puede editar desde la pantalla si el contador corrige algo.

**Por qué sembrada y no «que la agregue DO».** La clave. El día que se construya el aviso «persona en planilla
sin Vida Ley» tiene que apuntar a un tipo que existe con un nombre estable; agregada a mano habría podido
salir `seguro_de_vida` y habría que adivinar cuál es la buena.

**Lo que NO se hizo, y sigue decidido así.** No hay aviso de quién está en planilla y fuera de la póliza: Felipe
decidió el 2026-10-19 que espera la respuesta del contador (y qué vínculos obligan, ¿entra quien está de prueba?).
Para un complementario, «estar en él» sigue siendo tener su póliza vigente. Tampoco se registró ninguna póliza:
la de La Positiva no está firmada. **[Corregido el 2026-10-21, en la sección de arriba: lo contratado es Pacífico,
póliza Nº 143720, con quince certificados emitidos. Y sobre «¿entra quien está de prueba?»: Felipe decidió ese mismo
día que el seguro se cuenta solo sobre `planilla`.]**

**Antes de pegar.** La consulta de solo lectura está en la cabecera de la 0543 (esperado: tipos de hoy = FOLA y
EsSalud, cero pólizas de `vida_ley`). Si DO ya la agregó a mano con esa clave, la migración solo la marca «del
sistema» sin tocar su descripción; si la dejó como principal por error, no la toca y la comprobación final lo
muestra. **El PR no se fusiona hasta que esté pegada** (CLAUDE.md: la migración va antes).

**Probado.** En un Postgres desechable con las 519 migraciones de `main`: la prueba 422 pasó de 308 a 312
aserciones, 312 verdes (había que editarla: creaba «Vida Ley» ella misma y ahora chocaría); la 423, 116 de 116;
repegar la 0543 no duplica nada; su propio bloque de revertir la quita; **sin la migración las aserciones nuevas
se ponen en rojo** (37, 39, 40, 41, 42), con ella en verde. Probados los dos estados previos que podría tener
producción (ya agregada bien, o agregada como principal). **No probado:** la pantalla con la fila nueva (no
cambió código de pantalla) ni contra la base real: el estado actual de `seguros_tipos` en producción solo lo
ve Felipe.

## 2026-10-21 — Una oficina mide su meta en integrantes en la sede · SIN SQL · PR #576 ABIERTO, SIN FUSIONAR · rama `claude/problema-con-el-5-ca9a30`

**Qué es.** Oficina TRU (sede de tipo `central`) salía en ámbar «5 trabajando ahora · meta por revisar» todos
los días: su meta de 4 se medía contra personal de áreas operativas, y en una oficina no hay. Decisión de
Felipe: la meta de una central es cuántos integrantes hay en la sede, y con ellos en piso sale verde
(«5 / 4 integrantes · Cobertura correcta»). Sigue al #574, que solo había cambiado el titular de la fila.

**Cómo.** Una sola regla, en `cuentaEnCobertura` (`packages/shared/src/cobertura-equipo.ts`): `cuentaEnMetaOp`
= la persona operativa y, en una central, cualquiera del equipo menos quien está de prueba. `operativa` NO
cambia —sigue diciendo «su área es operativa»— porque la usa el aviso de «marcó sin horario», que en una
oficina sería ruido diario. Dashboard, Turnos y Reporte de sede leen el campo nuevo; la palabra pasa a
«integrantes» solo en una central. Tienda y taller: nada cambia.

**Lo que NO se hizo.** Turnos y Reporte de sede cuentan igual, pero Turnos todavía escribe «operativas» en sus
rótulos aunque la sede sea central. Y la meta de 4 sigue guardada tal cual en Turnos: si Oficina TRU crece,
se sube ahí. La salida de marcar sus áreas como operativas en Áreas (la que dejó escrita el 2026-10-20) ya no
hace falta para una central.

**Probado.** 2 527 pruebas verdes; se rompió la regla a propósito y la prueba nueva se puso en rojo. Visto en
el navegador contra un simulador de la API con datos inventados (oficina central de 6 con 5 en piso y meta 4,
y una tienda de 3 con 2 en piso y meta 3): la oficina sale verde con «5 / 4 integrantes», no aparece en
«Requiere atención», y la tienda sigue en rojo con «2 / 3 operativas». **No probado:** contra datos reales de
producción (esta sesión no los consulta) ni el Reporte de sede ni Turnos en pantalla.

## 2026-10-21 — La diferencia real de una liquidación pagada se cierra con una constancia · migración 0542 · SQL SIN PEGAR · SIN FUSIONAR · rama `claude/remover-pago-duplicado-8c818a`

**Qué es.** La pantalla de Liquidaciones decía «pagarla, compensarla o dejar constancia», y «dejar constancia»
nunca existió: una diferencia real en una liquidación ya pagada no se podía cerrar, así que «3 con
diferencias» no bajaba jamás y acabó leyéndose como ruido. Felipe pidió quitarlo (2026-10-21) y se hizo en dos
pasos, en commits separados:

1. **La lista deja de marcar «Cálculo cambió»** (sin SQL): se fueron la pastilla, la casilla y la insignia por
   fila. El aviso rojo sigue dentro del desglose y la columna «Cálculo cambió» sigue en el CSV.
2. **Registrar qué pasó con la diferencia** (0542 + pantalla): un libro de constancias que solo se agrega, una
   sola puerta de escritura (`fn_liquidacion_constatar`) y una lectura de un solo instante
   (`fn_liquidacion_constancia_estado`). **No toca ninguna función ni tabla existente**, por eso no lleva md5
   de partida. Detalle de diseño en la cabecera de la migración.

**Decidido (Felipe, 2026-10-21): opción 1, la constancia mínima.** El servidor calcula el SENTIDO de la
diferencia (`ahora − pagado`) y la decisión depende de él: a favor de la persona → «lo pagado era lo correcto»
con un apoyo obligatorio; a favor de CAYLA → «no se reclama» o «devolución acordada» (Reglamento 29.6); y
«retirar», que reabre. Una diferencia mixta no se puede constatar: queda abierta. **No hay «ya se pagó por
fuera»** (ese camino es «Volver a marcarla como pagada», que guarda la fecha real de pago) ni «compensada»
(choca con 29.6). Vale mientras la «huella» del cálculo coincida: si cambia, el aviso vuelve solo.

**Pendiente, en este orden.**
1. **Pegar la 0542 ANTES de fusionar** (`./scripts/dame-el-sql.sh 542`). Si el código llega primero no se
   rompe nada: sin poder leer el estado la pantalla se comporta como antes (`queDibujarDeLaConstancia`, con
   su prueba). La consulta del final de la migración tiene que dar: tabla con RLS, `authenticated` sin
   insert/update/delete/truncate, tres funciones y el registro `542 · la_diferencia_de_una_liquidacion_pagada…`.
2. **Las tres diferencias reales de producción** (Felipe las pasa aparte). Con ellas se ve si el catálogo
   alcanza: concepto, signo, y si alguna es mixta. Ninguna sesión pudo leerlas: producción no está a su alcance.
3. **Una pregunta nueva al laboralista**, que no está en ninguna consulta abierta: ¿puede CAYLA dejar sin
   pagar una diferencia a favor de alguien que ya cesó? De la respuesta sale el texto de «lo pagado era lo
   correcto». Una constancia así es un registro con nombre y fecha de que CAYLA vio el número y decidió.
4. **Cerrar `liquidacion_pagada`** (propuesto, NO escrito): ninguna migración ni prueba revoca sus privilegios;
   el trigger frena UPDATE y DELETE pero no TRUNCATE. Se llegaría solo con una conexión directa, no por la API.
   (La 0542 agrega una FK hacia esa tabla, así que `truncate liquidacion_pagada` ya exige `cascade`; eso no la cierra.)
   Primero confirmarlo en producción con `has_table_privilege('authenticated', 'liquidacion_pagada', 'truncate')`.
5. **La pastilla «N con diferencias» NO vuelve a la lista** y no se decidió que vuelva. Exigiría reescribir
   `fn_liquidaciones_pendientes` (0475; otro ritual de md5) y los números que se estimaron («~0.5 s hoy») salían
   del Postgres local; producción ya canceló esa misma consulta por tiempo (0474). Medir primero en el SQL Editor
   —con el claim de un admin puesto, o devuelve cero filas— el tiempo de la lista.
6. **El CSV** sigue diciendo «Cálculo cambió: sí» aunque ya haya un registro, porque la lista no sabe de
   constancias. Decidir si la columna pasa a «abierta / resuelta».

**Lo que encontró la revisión independiente (tres revisores, 2026-10-21) y ya está corregido en la 0542.**
La más seria: si la diferencia real está en «Sueldo del periodo» y el periodo ya tiene registrado el descuento
del cierre, esa fila pasa a ser Δ − D y puede cambiar de SIGNO (+11.54 a favor de la persona se volvía −488.46
«a favor de CAYLA»), y la base dejaba registrar «devolución acordada» sobre una cifra que nunca existió. Esta
sesión lo había dado por benigno; no lo era. Ahora, mientras haya un descuento de cierre registrado y esa fila
esté entre las reales, **no se puede constatar**; al cerrar el mes la fila pasa a «esperada por el cierre» y el
aviso desaparece solo. Además: una versión NULL ya no se salta la comprobación de versión; un motivo de solo
saltos de línea o tabuladores ya no cuenta; **retirar** ya no depende de poder registrar algo nuevo (quien se
equivocó puede reabrir aunque la persona se haya reactivado); «anterior» no se devuelve junto a una vigente;
la guardia de la migración para si `fn_persona_liquidada` es la 0421 (sin la 0499 una constancia podría cerrar
el aviso de un cese que ya no es el de la persona); `huella_formula` (cambiar la fórmula de la huella ya no
reabre todas las constancias por accidente); la secuencia de `orden` y el TRUNCATE quedaron cerrados.

**Probado.** La 0542 aplicada dos veces sobre un Postgres desechable con las 518 migraciones de la rama, y su
guardia comprobada (aborta si `fn_persona_liquidada` es la 0421). Prueba 435 con 118 aserciones en verde, que
incluye 30 que escribió un revisor tras ejecutar 35 mutaciones nuevas (la prueba de entonces cazaba 6 y dejaba
pasar 29). **39 mutaciones de la migración (26 de funciones y 13 de esquema), todas puestas en rojo.** Dos
revisores ejecutaron además dos sesiones concurrentes reales: el candado por persona sí serializa, y la
carrera con «Volver a marcarla como pagada» es inerte. Suite pgTAP completa con y sin la 0542 —quitándola con
su propio bloque «cómo se revierte», que así también quedó probado—: mismas aserciones en los 342 archivos
restantes. Fallan 28 archivos con o sin la 0542, no 20: los 8 de más cuentan filas globales (personas, periodos)
y los alteran los datos de prueba que se dejaron en el banco para ver la pantalla; no tienen que ver con esto.
Pantalla probada en el navegador contra las funciones SQL REALES (no un simulador): registrar, corregir,
retirar y las cuatro situaciones (a favor de la persona, a favor de CAYLA, mixta, la que cuadra). `vitest`
2 525 en verde, typecheck limpio. **No probado:** `db-tests` de GitHub, producción, dos personas pulsando a la
vez desde el navegador (sí desde SQL), la pantalla en móvil, y la ventana «descuento registrado, mes abierto»
en el navegador (sí en SQL, prueba 435).

## 2026-10-19 — Términos primero, guía después, en «Lo mío» · migración 0540 · SQL PEGADO Y VERIFICADO EN PRODUCCIÓN (2026-10-19) · FUSIONADO Y PUBLICADO (PR #561, 2026-10-19) · rama `claude/dynamic-terms-conditions-modules-44a3d3`

**Qué es.** La guía de primera vez (driver.js) arrancaba sola, sin condiciones, y antes o a la vez que
cualquier otra cosa que se le pide a la persona. Ahora una sola función (`capaActiva`, en
`packages/shared`) decide qué le toca a la persona al abrir un módulo —términos de uso, términos del
módulo o guía— y **nunca dos a la vez**. Las dieciséis secciones de «Lo mío» tienen su guía: aro suave,
dos o tres pasos, «Omitir», y «Ver guía de esta pantalla» en la cabecera de Info.

**Lo que ya se ve hoy:** las guías (con su novedad en `novedades.ts`). **Lo que NO se ve todavía, a
propósito:** los términos. Los diecisiete textos de `packages/shared/src/terminos.ts` están en
`borrador`, y un borrador es invisible para la pantalla: no se muestra y no bloquea nada. Para que uno
salga hay que cambiar su `estado` a «aprobado» con quién y cuándo, y pegar su huella en
`tests/terminos.test.ts`.

**Decidido (Felipe, 2026-10-19):** bloquean solo los términos de uso y los módulos con casilla. Cinco
piden casilla (términos de uso, Vacaciones y permisos, Firma, Mis datos, Reportes); cuatro ya tienen su
propia constancia y solo apuntan a ella (Boletas, Mi DNI, Movilidad, Disciplina); el resto es un aviso.

**Pendiente, en este orden.**
1. **DO y el laboralista leen los textos.** Se corrigieron seis que prometían lo que su pantalla no hace
   (Vacaciones y permisos, Disciplina, Movilidad, Educación, Mis datos, Objetivos), pero ninguno lo ha leído
   un humano de DO. Ojo con dos: el de Movilidad ya no dice «carácter no remunerativo conforme al pacto»
   (no se pudo comprobar contra la pantalla) y puede que el laboralista lo quiera de vuelta; y Disciplina no
   menciona un descargo porque la pantalla no tiene dónde presentarlo.
2. ~~**Pegar la 0540**~~ **HECHO el 2026-10-19.** Se pegó DESPUÉS de fusionar el PR —el orden de CLAUDE.md es
   el contrario—, y no pasó nada porque con todos los textos en borrador el código no consulta la base. El SQL
   Editor devolvió «Success», y la consulta de control dio: registro «540 · las_aceptaciones_de_terminos_por_modulo»,
   las tres funciones (`fn_aceptaciones_terminos_inmutable`, `fn_aceptar_terminos`,
   `fn_mis_aceptaciones_terminos`), 1 trigger de inmutabilidad, 2 políticas y 0 filas; `authenticated` no puede
   insertar directo y `anon` no puede ni leer la tabla. El script la copió con el md5 del archivo y GitHub
   coincidentes, y el portapapeles se comparó aparte con el locale UTF-8 (136 acentos intactos).
3. **Aprobar los textos de a uno, empezando por «general».** Hasta entonces nadie ve ni acepta nada.

**Probado.** La 0540 con su prueba 433 (28 aserciones) en un clon desechable, con ocho sesiones aceptando
la misma versión a la vez (una dice true, siete false, una fila); `types.ts` comparado contra los tipos
generados de verdad con la 0540 aplicada. La prueba 433 también dio verde en `db-tests` de GitHub, sobre
una base construida desde cero. **No probado:** el flujo completo de aceptar un texto contra la 0540 en
producción (nadie ha aceptado nada: no hay texto aprobado), «Tus últimos periodos» de Historial, y el panel
de vista previa de la app no dispara `requestAnimationFrame` (las guías se vieron con esa función
sustituida; en un navegador normal debería verse igual).

## 2026-10-17 — Seguros, etapa 2: «Mi seguro» en Lo mío, para TODO el equipo · migración 0530 · SQL PEGADO Y VERIFICADO EN PRODUCCIÓN (2026-10-19) · FUSIONADO Y PUBLICADO (PR #555, 2026-10-19) · rama `claude/seguros-module-analysis-redesign-70bbe4` (rescató `claude/seguros-etapa-2-mi-seguro`, antes `elegant-mayer-3e584e`)

**Qué es.** Cada colaborador ve SU seguro en `/mio` → Documentos → «Mi seguro»: en cuál está hoy;
si lleva póliza, su número, la aseguradora, hasta cuándo es vigente, el plan y el máximo anual **solo
si el corredor ya los confirmó**, y el PDF de su póliza y de su convenio de pago para **abrir o
descargar**. Quien está en EsSalud ve el nombre y que **se paga por planilla y no lleva póliza**;
quien no tiene seguro principal (honorarios) ve que no tiene uno asignado. Se ven las pólizas de
CUALQUIER seguro, también las del que tenía antes de cambiar. El «Cómo usar tu seguro» sale solo
para el seguro que lo tiene (hoy FOLA) y solo mientras su póliza está vigente. Las secciones de Lo
mío pasan a dieciséis.

**Rediseño y guía corregida (2026-10-19, esta rama).** Sin SQL nuevo: la 0530 es la misma.
- **La póliza vigente va primero.** Se midió en 375 px con una practicante de prueba: el número iba en 14 px dentro de
  una frase, el primer botón de PDF quedaba en y=803 de 812 y el resumen repetía la vigencia de la tarjeta. Ahora es
  una tarjeta con el número en 24 px y botón «Copiar», «Abrir» como botón principal (y=630), los teléfonos de la
  aseguradora con su uso, y debajo «Cómo usar». Sin póliza vigente (EsSalud, hueco, sin seguro) queda el resumen de
  siempre. `resumenSoloRepite` (`lib/mi-seguro.ts`) decide cuándo el resumen se omite. La tarjeta con la foto y el
  nombre de «Lo mío» ocupa ~250 px arriba y no se tocó (otra rama reordena `/mio`).
- **La guía de FOLA se cotejó con el PDF de una póliza** y se corrigió: la emergencia va primero con el plazo de
  24 horas para avisar a Pacífico (p.25 del PDF); la atención en la red lleva deducible y coaseguro (ya no dice «basta
  con el DNI»; NO se escriben montos porque no sabemos en qué red está cada clínica); el reembolso es para lo de fuera
  de la red y se liquida por el tarifario; el seguro dura lo que el convenio de prácticas; los dos teléfonos se rotulan.
  La póliza sigue sin decir el plan ni el máximo anual: la pantalla no los muestra.
- **Por confirmar con la corredora:** que «Pacífico Asiste» sea la Central de Emergencias y Asistencia (415-1515); lo
  dedujo la sesión, el resumen de la póliza no trae el número.
- **El texto para quien está en EsSalud** quedó en borrador con la fuente de cada frase (la mayoría de las páginas de
  EsSalud se leyeron por resumen y hay que cotejarlas; `gob.pe` bloquea el lector). **No está en el código**: lo validan
  Felipe y el contador. Además guarda una pregunta para el contador: si todas las personas de planilla y de prueba
  figuran activas en EsSalud.
- **Decidido por Felipe (2026-10-19):** rescatar esta rama en vez de rehacerla; la mora se mantiene neutral (la persona
  no ve «suspendida»); el texto de EsSalud sale de fuentes oficiales y lo valida él con el contador; la alerta de
  Vida Ley / SCTR espera la respuesta del contador.

**FUSIONADO Y PUBLICADO el 2026-10-19 (PR #555).** Felipe pidió fusionar («fusiona») después de que la sesión le preguntara
sí o no. La fusión se hizo a las 12:43 (hora de Lima), commit `cfbd009f`, con `--merge` y sin `--auto`; `db-tests` y
`ui-tests` estaban en verde sobre el último commit (`f6b46ea3`) y `main` no se había movido. Vercel marcó el despliegue
de producción de ese commit como `success` a las 12:44. **No se abrió «Mi seguro» con una cuenta real en producción:**
que `/admin/seguros` y `/mio` respondan 200 no lo prueba, porque ya existían.
- **Por qué se fusionó antes de que DO cargue las pólizas.** DO las sube por el sistema, y con la 0530 pegada la
  pantalla de producción de ese momento decía «solo los ve Desarrollo Organizacional» (ya falso: la póliza y el
  convenio los ve también la persona), dejaba la casilla «guardarlo también en las otras pólizas» marcada por defecto
  y no pedía confirmar. Con un número tecleado dos veces en dos pólizas FOLA, un PDF con DNI se habría copiado a la
  póliza de otra persona. La pantalla de este PR trae los avisos, la casilla sin marcar y la confirmación.
- **Lo que ve el equipo desde ya:** cada practicante lee «Todavía no tienes una póliza registrada» hasta que DO cargue la
  suya (no es una alarma); quien está en EsSalud lee que se paga por planilla y no lleva póliza. El texto «Cómo usar
  EsSalud» NO está publicado.
- **Quién lo ve y lo carga:** solo `admin` y `lider_do` (DO y sus superiores); los líderes de equipo no ven nada de
  seguros. Todo lo que se agrega o se edita pasa por el sistema, no por SQL.

**Su historia, para que nadie la repita.** Se construyó primero acotada a los practicantes, sobre
la primera 0528 (solo FOLA). Cuando Felipe hizo general el módulo, esa versión se descartó entera
—nunca se pegó— y se rehízo sobre la 0528 nueva. Lo que cambió, y por qué importa: la puerta pasó
de «hoy soy practicante» a **«es MI póliza»**. Con «hoy soy practicante», quien pasa de FOLA a
EsSalud perdería el PDF de una póliza que sigue vigente hasta que la aseguradora procese la baja.

**Traída la etapa 1 YA PUBLICADA (2026-10-17, por la tarde).** La rama se rehízo sobre `main` —la 0528
final está pegada en producción y fusionada, PR #551— trayendo la rama de esta etapa encima: tres
conflictos y ninguno de fondo.
- `archivos-poliza.tsx`: se juntan los imports. Y se reconcilian dos textos que se contradecían: la
  etapa 1 dejó una casilla «guardarlo también en las otras pólizas» que decía que el papel es uno y que
  cada persona lo tiene en su ficha, y esta etapa hace que cada persona abra en «Lo mío» la póliza y el
  convenio de SU póliza. **Cruce que importa:** en una póliza colectiva, copiar el PDF a todas las
  pólizas lo pone al alcance de todas las personas aseguradas. Por eso ahora, en una póliza colectiva,
  el aviso dice que cada persona verá lo que se suba como póliza o convenio de pago (todas, si se
  copia a las demás) y que no lleve listas con el DNI o el sueldo de otras personas; y la casilla dice,
  según el tipo, si cada persona lo abrirá o solo DO. «Otro papel» sigue sin copiarse.
- La 422: gana la de `main` (la misma aserción #2, con su descripción al día). La #226, que fallaba en
  esta Mac mientras la base local compartida tuviera los PDF de la demo en el bucket, ya no falla: la
  422 de `main` cuenta solo sus propios archivos, y así se corrió.
- `estado.md`: queda esta entrada arriba y la de la etapa 1 debajo; se quita el párrafo que decía que
  esta etapa vivía en otra rama.
Después se trajo `main` otra vez (PR #554: el freno de la «receta suelta»), que frenó el push por un
«Cargando…» escrito a mano en `mi-seguro.tsx`; ahora usa `<Cargando />`.
**Con la 0528 FINAL, la 0530 y las migraciones nuevas de `main` (0527, 0531, 0532 y 0533) aplicadas
desde cero, en una transacción que se revierte: 422 = 308/308 y 423 = 108/108**, sin errores; `tsc` y
las 2210 pruebas de `vitest` en verde; y los frenos del push, todos. «Mi seguro» se vio otra vez en el
navegador contra la 0528 final (practicante con póliza vigente y una futura, EsSalud sin póliza,
planilla con una póliza FOLA que le quedó; «Descargar» firma y baja `Poliza-FOLA-<número>.pdf`).

**Antes, con la punta de entonces (`112bfcb3`, merge `91d9c583`, también 2026-10-17).** La
revisión independiente de la etapa 1 movió dos cosas que me tocan, y ninguna cambió una firma:
- **El número de una póliza ya no identifica a una persona.** El índice único lleva ahora
  `persona_id`: una póliza colectiva (vida, EPS) puede repetir aseguradora, número y vigencia entre
  personas distintas. `fn_mi_seguro` y `fn_mis_polizas` nunca emparejaron por número —todo es por
  `poliza_id` y `persona_id`—, y ahora la **423 lo prueba** (sección I, 17 aserciones): dos personas
  con la MISMA póliza ven una cada una, con solo su archivo, en las tres lecturas. Tres mutaciones
  que emparejan por número la rompen. (Una renovación que conserva el número también repite
  número dentro de una persona; tampoco se confunde.)
- **La cobertura puede estar «suspendida»** (póliza vigente por fechas, prima sin pagar más de 30
  días). La calcula la pantalla de DO con `estadoPrima`; la base no lo sabe. Por eso la tarjeta de
  «Mi seguro» ya no dice «cubierto» (ver abajo).
- El resto (bloqueos `for no key update`, límites de largo, la política de UPDATE de Storage) no me
  toca. Mi única edición a un archivo de la etapa 1 sigue siendo la aserción #2 de la 422.

**Qué toca.**
- **0530**: `fn_mi_seguro()` (UNA fila: su seguro principal de hoy, llamando a
  `fn_seguro_tipo_principal` de la 0528, sin repetir la regla), `fn_mis_polizas()` (sus pólizas con
  los archivos que puede ver) y `fn_seguro_archivo_es_mio(text)` con UNA política de lectura en
  Storage (`polizas_seguro_select_propia`). Las cuatro políticas de DO y `fn_seguro_archivo_libre` no
  se tocan. No reescribe ninguna función: no hay md5 de partida. Se detiene sola, antes de tocar
  nada, si la 0528 no está pegada. **No devuelve** la descripción del seguro (DO la edita y puede
  llevar notas), ni la prima, ni el papeleo, ni la nota, ni el historial, ni los cambios de seguro,
  ni el nombre con que DO subió cada archivo.
- La pantalla (`app/(mio)/mio/seguro/mi-seguro.tsx`) y su lógica (`lib/mi-seguro.ts`).
- **En la etapa 1:** el panel de archivos de DO decía «solo los ve Desarrollo Organizacional» sobre
  los PDF, y con la 0530 dejó de ser cierto; ahora dice qué ve la persona, avisa al elegir el tipo
  de archivo y pide subir a cada póliza solo el PDF de esa persona. Y una aserción de la 422 (la
  que contaba «todo lo que empieza con `polizas_seguro_`», 4) nombra ahora las cuatro de DO.

**Lo que decidió Felipe (2026-10-17):** los cuatro practicantes tienen cuenta y entran a Lo mío;
pueden **abrir y descargar** su PDF; el módulo es de todo el equipo. **Decide él y está pendiente:**
qué se le dice a quien está en EsSalud (ver abajo).

**Lo que decidí sin preguntar, y es de Felipe cambiar:**
- **Para EsSalud la pantalla dice solo lo que la base sabe:** «Tu seguro es EsSalud. Se paga por
  planilla y no lleva póliza.» No se inventó ninguna explicación de EsSalud. **Texto provisional:
  lo decide Felipe.**
- **La tarjeta habla de la PÓLIZA, no de que la persona «esté cubierta».** Dice «Vigente», «Tu póliza
  va hasta el… a las 12 M» y cierra con «Si la aseguradora te dice otra cosa, avisa a Desarrollo
  Organizacional». Motivo: la cobertura puede estar suspendida por mora (la prima lleva más de 30 días
  sin pagarse; convenio de pago, cláusula quinta) y eso la persona no lo ve —no sale la prima ni el
  papeleo de DO—, ni la base lo sabe (`cubre_hoy` es solo de fechas). Decirle «tu póliza cubre» a
  quien la tiene suspendida es mandarla a una clínica a que se lo nieguen; decirle «suspendida» por un
  pago que DO todavía no marcó sería una falsa alarma sobre su salud. El cierre sirve para los dos
  casos sin acusar a nadie. `tests/mi-seguro.test.ts` fija que DO dice «suspendida» y la persona
  «vigente», y que ningún texto de la tarjeta contiene «cubre», «cubierto» ni «cobertura». **Si
  Felipe prefiere avisarle de la suspensión:** una columna más en `fn_mi_seguro` y repetir en SQL la
  regla de los 30 días, que hoy vive solo en TypeScript (`estadoPrima`); la 423 fija las listas de
  columnas a propósito.
- **El plan y el máximo anual aparecen en cuanto DO los carga** («Corregir datos»); mientras estén
  vacíos no se pinta ni un «pendiente».
- Ve el **convenio de pago** además de la póliza; la factura y «otro papel» son solo de DO.
- **El texto de «Cómo usar tu seguro» salió del resumen que pasó la sesión de la etapa 1, no del
  PDF** (esta sesión no lo tuvo). **Revisarlo contra las páginas 2 a 5 antes de que lo lean:** sobre
  todo la carta de garantía («3 días útiles, salvo emergencia») y el reembolso («dentro de 90 días»,
  sin decir desde cuándo). Va por la clave del seguro (`salud_practicantes`) en `lib/mi-seguro.ts`; el
  día que haga falta una segunda guía, lo sano es una columna en `seguros_tipos`.
- El archivo que se baja se llama `Poliza-FOLA-<número>.pdf` (el nombre del seguro y el número, sin
  el nombre de la persona). En pantalla se rotula por su tipo, no por el nombre con que DO lo subió.

**Pendiente, en este orden (Felipe).**
1. ~~**Pegar la 0530 ANTES de fusionar el PR**~~ **HECHO el 2026-10-19:** Felipe la pegó y el SQL Editor devolvió lo esperado (3 funciones, 1 política de lectura, 5 de Storage, `authenticated` la llama, `anon` no, registro «530 · mi_seguro_cada_colaborador_ve_su_seguro_y_abre_sus_pdf»). Antes se volvió a mirar `main` y la numeración, y el md5 del portapapeles coincidió con el archivo y con GitHub. (La 0528 ya estaba pegada y fusionada, PR #551.)
   `./scripts/dame-el-sql.sh 530` (el número libre y `main` se vuelven a pedir en el mensaje que entrega
   el SQL; la 0530 es el hueco entre la 0529 y la 0531, y la prueba 423 estaba libre). La consulta de
   «ANTES DE PEGAR» de la cabecera espera la 0528 presente y nada de la 0530; **Retail vive en el mismo
   proyecto (esquema `retail`)**, así que cualquier conteo de `pg_proc` por nombre puede traer una fila de más.
2. **DO sube las pólizas por el sistema, un PDF por persona** (la casilla de copiar a las otras pólizas, sin marcar). Si el
   archivo junta varias pólizas, cada persona vería el DNI y la fecha de nacimiento de las otras, y la base no puede
   comprobarlo. **Al terminar, la consulta de control** (la de «ANTES DE PEGAR» de la 0530): la columna
   `pdf_iguales_en_polizas_de_distinto_numero` debe dar 0. Esto sigue pendiente.
3. **El texto de EsSalud** (en borrador, validado por Felipe y el contador; ver arriba). La guía de FOLA ya se revisó contra el PDF; falta que la corredora confirme el nombre «Pacífico Asiste».
4. Con una cuenta real (de preferencia una practicante, ya con su póliza cargada), apretar «Abrir» y «Copiar» en un iPhone y en un navegador de verdad. Tampoco se probó en producción.
5. ~~La novedad lleva fecha 2026-10-19~~ Se fusionó ese mismo día: la fecha es la correcta.
   Otros pendientes que no bloquean: la alerta de Vida Ley / SCTR espera al contador; y los números reales de las cuatro
   pólizas siguen escritos en la cabecera de la 0504, en pruebas y en comentarios (datos de personas con nombre; el repo pide
   dejarlos fuera de git, y no se tocó).
6. La etapa 1 ya no se mueve (está fusionada y publicada): la 0530 se probó contra la 0528 que de
   verdad está en producción. Lo que sí puede moverse es `main`: antes de entregar el SQL, volver a mirar
   `git fetch` y la numeración, como siempre.

**Qué se comprobó.** La 0530 aplicada en una transacción sobre el Postgres local y la prueba **423**
(108 aserciones) en verde dentro de ella: practicante, otra practicante, planilla, honorarios, DO, una
asignación de DO, un seguro complementario, quien ya cambió de seguro (conserva su póliza y su PDF),
la cuenta de servicio y las sesiones sin ficha o sin identidad. Fija las dos listas de columnas,
compara **archivo por archivo** lo que lista `fn_mis_polizas` con lo que Storage deja abrir, y
compara «en qué seguro está», «si lo cubre hoy» y «cubre hoy» de cada póliza con lo que lee DO
(`fn_seguros_equipo`, `fn_seguros_tablero`), y —sección I— que dos personas con la misma póliza
colectiva no se mezclan. Se probó que SABE fallar con veinte mutaciones de la migración, las tres de
emparejar por número incluidas —factura, archivo retirado, archivo de otra persona o póliza anulada visibles; la puerta de
«hoy soy practicante» vuelta a poner en Storage o en `fn_mis_polizas`; todas las pólizas en vez de las
propias; una columna de más en cada función; el convenio antes que la póliza; el último día inclusivo
en las dos; «cubre» de una póliza de otro seguro; la cuenta de servicio con fila; `cubre_hoy` para
EsSalud; el seguro automático escrito a mano en vez de `fn_seguro_tipo_principal`—: las veinte la
rompen. La migración se puede aplicar dos veces. Las pruebas 250, 92 y 108 siguen en verde. (Con la
punta de entonces la **422** tenía 252 aserciones y pasaba con la 0530 aplicada salvo la #226; con la
etapa 1 final, arriba, pasan las 308.) `vitest` (dieciséis mutaciones de `lib/mi-seguro.ts` las
rompen; hoy 2210 pruebas en 95 archivos), `tsc` y `eslint` de lo tocado en verde (`page.tsx` conserva dos
errores `set-state-in-effect` que ya tenía `main`).
Los guardias del push (numeración, reglas de la casa, nombre del PDF, fechas vacías, linter) corridos
a mano sobre lo que esta rama agrega encima de la etapa 1: todos en 0.

**En el navegador** (2026-10-17, contra la base local con la 0530 aplicada y datos «ZZMiSeguro» con
ids `…0000fc…`, que se borraron al terminar junto con la migración; la demo de la sesión madre
quedó intacta):
- *Practicante en FOLA:* «Vigente — Tu póliza está vigente», su póliza con sus dos PDF (no la
  factura), la guía de uso.
- *Dani, de planilla con una póliza FOLA que le quedó:* «Por planilla — Tu seguro es EsSalud», su
  póliza FOLA en «Tus pólizas» con su PDF, y la guía de FOLA porque esa póliza cubre hoy. «Descargar»
  baja `Poliza-FOLA-<número>.pdf`.
- *Practicante sin póliza FOLA pero con una de otro seguro:* «Todavía no tienes una póliza
  registrada», la póliza de vida en «Tus pólizas» y NINGUNA guía de FOLA.
- *Honorarios:* «No tienes un seguro asignado en el sistema».
- *Segunda vuelta, ya con la punta nueva de la etapa 1 y el texto «vigente»:* la misma practicante con
  su póliza a 76 días («Vigente»), a 20 días («Vence en 20 días — Tu póliza va hasta el 06/11/2026…») y
  terminada hace 9 días («Sin póliza vigente — … terminó el 08/10/2026 (hace 9 días)», sin la guía de
  FOLA). `fn_mi_seguro` y `fn_mis_polizas` contestan 200; el servidor, sin errores. En la consola salió
  UN «429 Too Many Requests» de un recurso que no es de esta sección (ni esas dos llamadas ni Storage);
  no se identificó cuál es.
- A 375 px sin desborde horizontal y con botones de 44 px; consola y servidor sin errores.
- *Como DO:* el panel de archivos con el texto nuevo y el aviso que cambia con el tipo.
- *Contra el Storage real, con `curl`:* cada persona firma solo los archivos de SUS pólizas de tipo
  póliza o convenio (200); la factura, lo de otra persona, uno que no existe, y quien no inició
  sesión, 400. Dani, ya en EsSalud, firma su póliza FOLA; quien está en planilla sin pólizas, nada.

**Lo que NO se comprobó.** El botón **«Abrir»**: el navegador integrado de la app bloquea
`window.open` (devuelve `null` con cualquier página), así que ahí sale el aviso de ventanas
emergentes, igual que en las demás pantallas que abren un PDF; lo que sí se vio es que la firma del
archivo propio sale 200. Un iPhone real; `db-tests` de GitHub (la señal fiable de las pgTAP, no esta
Mac); nada contra datos reales de producción; ningún PDF real (los de prueba pesaban ~600 bytes). En
esta Mac la 422 falla en la #226 («DO ve los cuatro») mientras la base local compartida tenga los PDF
de la demo en el mismo bucket; falla igual sin la 0530 (se corrió el control) y en CI el bucket está
vacío.

**Un límite pequeño que se dejó:** una renovación que conserva el número de la póliza (la etapa 1 lo
permite) se baja con el mismo nombre, `Poliza-FOLA-<número>.pdf`, y el navegador le pone «(1)» a la
segunda. No pierde nada; si molesta, el nombre puede llevar el año de inicio de la vigencia.

**Cómo se generaron los tipos.** Igual que en la etapa 1: una base desechable con el esquema `public`
de la local, la 0530 aplicada allí, `supabase gen types --db-url` y pegadas SOLO las tres funciones
nuevas (`fn_mi_seguro`, `fn_mis_polizas`, `fn_seguro_archivo_es_mio`). La base desechable se borró.

---

## 2026-10-19 — La prueba de tres días · base, planilla, pantallas y terminal · migraciones 0535–0539 · SQL PEGADO Y VERIFICADO EN PRODUCCIÓN (2026-10-19) · FUSIONADO Y PUBLICADO (PR #557, 2026-10-19) — con la 0537–0539 pegadas DESPUÉS de fusionar · rama `claude/trial-period-contract-flow-3b095c`

**Qué es.** Quien está de prueba no tiene contrato: trabaja **tres días** (de jornada cerrada, no de
calendario) y recién después se le hace contrato. Durante la prueba se marca **«no apto»** (se le
paga lo trabajado) o **«se retiró»** (no se le paga); si pasan los tres días y nadie decide, alerta a
DO y la persona sigue marcando. Decide DO, administración o la líder de equipo **sola**, sin
confirmación de DO, y solo sobre la gente de su sede. Fecha de baja = el último día trabajado.

**Lo que decidió Felipe (2026-10-19, con preguntas):** reusar el vínculo «Prueba» que ya existe;
«si se retira, no se le paga» (objeción dicha: es una deuda remunerativa reclamable y sin hoja
firmada no hay prueba de que la conocía — se decidió igual); aviso del plazo con alerta a DO y
etiqueta en el terminal, **sin** hoja firmada; el pase a Planilla es al **firmarse el contrato**;
**la asignación familiar solo se paga cuando hay contrato** (objeción dicha: derecho del trabajador
con hijos, Ley 25129); la líder decide en la **Bandeja** (Contratos solo lo abre DO); el pase a
Planilla es una **casilla marcada** al registrar la firma; **Equipo** pide «no apto / se retiró» al
registrar la salida de alguien de prueba; y «DO, líder o los que tienen más cargo pueden subir el DNI».

**Qué hay en esta rama (el refactor va primero a propósito).**
- **0535 — refactor sin cambio de comportamiento.** `fn_cesar_persona` queda como guardia (admin y
  líder DO) y delega en `fn_cese_aplicar`, interna. Hace falta porque `fn_es_admin_o_lider()` solo
  reconoce `admin` y `lider_do`: una líder de equipo siempre rebotaría. La prueba 135 se mudó al núcleo.
- **0536 — la prueba.** Tabla `pruebas` (los días se **derivan**, no se guardan), `fn_prueba_cerrar` (única
  puerta: resultado + motivo + quién + baja, todo o nada; «se retiró» cierra como `renuncia` y «no apto»
  como `fin_periodo_prueba`), `fn_pruebas_abiertas` (días, situación, horas marcadas y si ya tiene el DNI),
  `fn_prueba_puede_actuar` y un trigger sobre `personas` que abre/cierra la prueba al cambiar vínculo o estado.
- **0537 — la planilla.** Reescribe `fn_planilla_calcular_nucleo` (copia de la **0524**, con marcas
  `CAMBIO 0537`): quien se retiró en prueba **no entra a la lista de personas** (solo mientras siga inactiva) y
  la asignación familiar la lee una columna `cobra_asignacion` (`con_hijos` y vínculo distinto de «prueba»).
  Guardia: se niega a pegar si falta la 0536 o si la función de esa base no es la de la 0524 (md5).
- **0538 — el DNI de quien está de prueba.** `fn_prueba_cargar_dni` crea la solicitud `foto_dni` a nombre
  de esa persona (sin cuenta) y la aprueba en el acto con `fn_resolver_solicitud_perfil`; **guarda además la
  constancia de consentimiento (Ley 29733)** a nombre de la persona, diciendo quién la declaró y con qué texto;
  `fn_solicitud_perfil_puede_escribir` (0399) gana una rama para quien puede actuar sobre esa prueba (la lectura
  no se toca); `fn_pruebas_cierres_recientes` (los cierres de las últimas 48 h, para que DO se entere).
- **0539 — el terminal.** `terminal_roster` gana `prueba_dias` y `prueba_plazo` (NULL para el resto) a través
  de `fn_terminal_prueba_dias`, que solo contesta por la gente de la sede de ese terminal (**una vista ejecuta
  las funciones con los permisos de quien consulta**: darle al terminal `fn_prueba_dias_trabajados` le habría
  dejado contar jornadas de cualquiera). Las pruebas 221 y 302 —que fijaban «seis columnas y ni una más»— se
  actualizaron a ocho a propósito; la aserción de «nada sensible» no se tocó.
- **Pantallas.** Bandeja: módulo «Pruebas» (DO y líder) con el panel para decidir y el DNI; el «sin contrato»
  de Contratos se calla para quien está de prueba. Contratos: Nuevo documento muestra la prueba en vez de las
  tarjetas de tipo, el tablero la rotula «Prueba · 2 de 3», y «Subir contrato firmado» trae «Pasar a Planilla»
  marcada. Equipo: etiqueta y «Registrar salida» por el panel. Etiqueta también en Horas, Horarios y Planilla.
  Terminal: «Prueba · 1 de 3» junto al nombre. Novedad en `novedades.ts` (sin reglas de pago).
- **Código compartido:** `puedeDecidirPrueba` (`permisos.ts`), `situacionDePrueba` y `etiquetaDePrueba`
  (`packages/shared/src/pruebas.ts`, las usa también el kiosco), `lib/admin/pruebas.ts`, `components/pruebas/*`.
- **Pruebas:** pgTAP 429 (52), 430 (19), 431 (33), 432 (14); vitest `pruebas`, `bandeja-pruebas`, `roster-prueba`,
  `permisos`. Todas verificadas con roturas provocadas.

**Lo que se midió.** Antes de la 0537, una persona de prueba con hijos y UN día de 6,5 h cobraba S/ 41,00 de
horas + S/ 123,00 de asignación; con tres días, S/ 123,00 + S/ 123,00. Con la 0537, viejo contra nuevo fila por
fila: «no apto» pasa de neto S/ 215,32 a S/ 108,31 y «prueba abierta» de S/ 179,22 a S/ 72,21; quien se retiró
desaparece; planilla, quien pasó a planilla y quien no tiene hijos **no se mueven**; y siete ventanas 29..28 sobre
los datos de la base dan JSON **idéntico**.

**Cómo se pegó — y el orden se rompió (2026-10-19, horas de Lima).**
1. **0524, 0535 y 0536** se pegaron a las 15:07, 15:11 y 15:16 (`migraciones_aplicadas`).
2. **El PR #557 se fusionó a las 15:28 con la 0537, la 0538 y la 0539 SIN pegar**, aunque su descripción
   abría con «⛔ No fusionar todavía». No tiene el comentario `cayla:fusion-sesion`: no pasó por el freno de
   `comentar-antes-de-fusionar.sh`, y no queda dicho quién lo pidió.
3. **Lo que se vio en producción** durante esa ventana: la Bandeja de DO mostraba el aviso rojo «No se pudo
   cargar los cierres de pruebas: El sistema no encontró esta función» y el módulo Pruebas en «No se pudo
   cargar» (`fn_pruebas_cierres_recientes`, 0538, contestaba `PGRST202`). Subir el DNI de quien está de prueba
   también habría fallado (`fn_prueba_cargar_dni`, 0538). **El terminal siguió marcando**: `roster.ts` vuelve a
   pedir la lista sin `prueba_dias`/`prueba_plazo` cuando la vista no las tiene. Y la planilla calculaba **sin**
   la 0537 —quien se retira en prueba habría cobrado—; no se cerró ningún periodo en esa ventana.
4. **Antes de pegar lo que faltaba**, una consulta de Felipe que repite las tres guardias dio todo en verde:
   `fn_planilla_calcular_nucleo` con md5 `11425cad…` (la 0524 tal cual, 119 895 caracteres, una sola versión),
   `fn_solicitud_perfil_puede_escribir` con `f1a28aac…` (la 0399 con `\r\n`), `terminal_roster` con las seis
   columnas de la 0490, `security_invoker = false`, delegando en `fn_persona_marca_en_sede` y excluyendo las
   cuentas de servicio; y la 0536 presente. Ninguna rama redefine esas funciones después de la 0537–0539.
5. **0537, 0538 y 0539 pegadas esa misma tarde, de a una**, cada una con `dame-el-sql.sh` (portapapeles idéntico
   al archivo y a `origin/main`, locale UTF-8). Controles: 0537 → `CAMBIO 0537` presente, 1 versión, registro con
   su nombre; 0538 → `fn_pruebas_cierres_recientes` y `fn_prueba_cargar_dni` existen, `CAMBIO 0538` en el permiso
   del bucket, registro con su nombre, y **el aviso de la Bandeja dejó de salir**; 0539 → `true, true, true`
   (ocho columnas, `authenticated` la lee, `anon` no). `migraciones_aplicadas` tiene de la 535 a la 540 con sus nombres.

**Qué NO está hecho (y por qué).**
- **«Se retiró» y quien ya figura en Planilla:** quien se retira desaparece de la pantalla de Planilla (a propósito:
  sin fila no hay nada que pagar); DO lo ve en la Bandeja 48 h y en el módulo Pruebas. Un aviso fijo en Planilla
  («se retiró · N h no pagadas») queda para después.
- **El pase a Planilla son dos llamadas** (registrar la firma y `fn_set_tipo_vinculo`), no una: si la segunda falla
  la firma queda y se dice claro; no se tocó `fn_contrato_registrar` (13 argumentos). La Bandeja sigue mostrando
  la prueba como «toca decidir», así que no se pierde.
- **Cerrar una prueba con la jornada abierta** (la persona sigue adentro): el cese ocurre igual y la jornada la
  cierra el auto-cierre de siempre; no se agregó una regla nueva.
- **La constancia de consentimiento es una DECLARACIÓN** de quien registra, no la firma de la persona.
- **Hoja de condiciones firmada** (que la persona conozca la regla de retiro): Felipe eligió no tenerla.

**Cómo se probó (y un aviso).** El Postgres local de esta Mac está **18 migraciones atrasado** y el md5 que imprime
`donde-vive.sh` es el de esa base, no el del repo; producción coincide con los ARCHIVOS. No se tocó la base
compartida: se probó en **clones desechables** (`docker run` de la misma imagen, esquema y datos copiados con
`pg_dump` de solo lectura). La suite completa (335 archivos) da las mismas 66 pruebas en rojo con y sin estas
migraciones —artefactos del clon—; las únicas diferencias son las pruebas que se actualizaron o añadieron. Las
pantallas se verificaron en el navegador contra un clon (PostgREST apuntando al clon + sesiones fabricadas), con DO
y con una líder de equipo.

---

## 2026-10-17 — Seguros del equipo: en qué seguro está cada colaborador (FOLA, EsSalud y los que DO agregue) · migración 0528 · SQL PEGADO Y VERIFICADO EN PRODUCCIÓN (2026-10-17) · FUSIONADO Y PUBLICADO (PR #551, 2026-10-17) · rama `claude/fola-dynamic-implementation-252f99`

**Qué es.** La pantalla `/admin/seguros` (grupo Personas, solo DO) y un módulo «Seguros» en la
Bandeja, **para todo el equipo y no solo para los practicantes**. Cada colaborador está en un
seguro: el que le toca por su vínculo (practicante → FOLA; planilla y prueba → EsSalud;
honorarios y sin vínculo laboral → ninguno) o el que DO le asignó. Cuando ese seguro lleva póliza,
la pantalla muestra su vigencia, su prima, los tres pasos del papeleo (prima pagada, póliza y
convenio de pago firmados, factura recibida), los PDF y un historial de quién hizo qué. Lo que
nadie miraba y ahora salta: **quién lleva póliza y hoy no tiene ninguna que cubra** (la 0504 quitó
EsSalud a todos los practicantes de una vez y la póliza FOLA es nominal), a quién se le vence
pronto, y **qué cambios de seguro quedan por cerrar**. **Solo alerta**: no toca la planilla, no
cambia lo que cobra nadie; la prima se paga a la aseguradora y EsSalud sigue como estaba.

**Lo que decidió Felipe (2026-10-17, con preguntas), en el orden en que lo fue diciendo:**
1. Control para DO, vista del practicante, PDF dentro del sistema y avisos en la Bandeja;
   pantalla «Seguros» en Personas; «Mi seguro» en Documentos de Lo mío; entrega por etapas, DO
   primero. **Esta es la etapa 1.**
2. «El seguro es para todos los colaboradores; FOLA es exclusivo de practicantes» y «el seguro
   actual que tienen los empleados déjalos como está». El resumen de la póliza confirma lo primero:
   cubre al asegurado «en su calidad de practicante del contratante» (p. 4).
3. «Deberíamos modificar todo el módulo para que sea de seguro general y por cada colaborador
   que cambie, ahí recién se ve en qué están: los practicantes en FOLA y los otros colaboradores
   pueden estar ubicados en otro lado». **Eso rehízo la migración**: la primera versión era solo de
   FOLA y se descartó entera (nunca se pegó).
4. Qué otros seguros hay: «no se sabe con exactitud, revisar; en caso no haya uno, dejar que DO
   agregue un seguro o tipo». → el catálogo vive en una tabla (`seguros_tipos`) y DO agrega los que
   falten desde «Tipos de seguro». **Hoy trae dos: FOLA y EsSalud.**
5. A quién le toca cada uno: «Automático por vínculo; DO lo cambia por persona».
6. Cuando alguien cambia: «Lo muestra y deja dos pendientes» → la baja del seguro anterior y el
   alta del nuevo.
7. Con la pantalla ya hecha: «¿cómo sé qué colaboradores sí cuentan con seguro, para que el propio
   sistema lo jale y no se tenga que rellenar los datos de nuevo?» A la pregunta de qué jalar solo,
   marcó las cuatro opciones: una póliza para varias personas, la lista de asegurados, leer el PDF
   de la póliza y «dejarlo así». **Las cuatro a la vez se contradicen en la última**; lo que se hizo
   fue construir las tres primeras como ayudas AGREGADAS (el formulario de una póliza por persona
   sigue igual, por si «dejarlo así» era lo que valía). Si en realidad no querías alguna, es quitar
   su botón de la cabecera; ninguna toca lo que ya existía.
8. Preguntado si el CSV de la lista de asegurados lo baja solo la dirección (como el padrón) o también DO,
   eligió: **DO también** (`puedeExportarListaDeAsegurados`). El padrón completo sigue solo para la
   dirección.

**Cómo funciona.**
- **`seguros_tipos`**: el catálogo. Cada seguro es *principal* (uno a la vez: FOLA, EsSalud) o va
  *además* (una póliza adicional), y *lleva póliza* o no (EsSalud: «por planilla», nada que
  registrar). FOLA y EsSalud son «del sistema»: no se archivan ni cambian de nombre. Un seguro que
  agrega DO no le toca a nadie por su vínculo: se asigna persona por persona (si es principal) o se
  le registra su póliza (si va además).
- **El seguro principal de cada persona**: una asignación de DO vigente (`seguros_asignaciones`); si
  no hay, el que cae sobre su vínculo; si tampoco, ninguno. La regla vive en
  `fn_seguro_tipo_principal` y en ninguna otra parte: la pantalla pregunta (`fn_seguros_equipo`
  trae también el que le tocaría por vínculo) y no la repite.
- **El hueco** (quién tiene que tener póliza), escrito una vez en `fn_seguros_equipo`: la persona
  está activa, su seguro principal lleva póliza y no tiene ninguna de ese seguro que cubra hoy.
  EsSalud no lleva póliza: nunca es un hueco. Un seguro adicional no tapa el hueco del principal.
- **Los cambios**: un disparador sobre `personas.tipo_vinculo` deja el cambio escrito cuando
  cambia el seguro que le toca por su vínculo, y `fn_seguro_asignar` / `fn_seguro_volver_al_automatico`
  cuando lo cambia DO. **No reescribe `fn_set_tipo_vinculo` ni `fn_cesar_persona`**: escucha la
  columna, y nunca frena el cambio de vínculo (un error suyo es un aviso, no un fallo: ese cambio
  mueve la planilla de una persona real). No registra nada de quien ya no está activa ni de quien
  tiene una asignación vigente. Los dos pasos **se calculan al leer**: uno queda pendiente solo si la
  persona sigue activa, nadie lo marcó y todavía tiene sentido (la baja, mientras quede una póliza
  vigente del seguro anterior; el alta, mientras no se haya registrado la del nuevo), así que se
  cierran solos cuando la póliza termina o se registra.
- **En la Bandeja**: sin póliza, por vencer, papeleo (UNA fila por póliza, no tres), baja de quien se
  fue y los dos pasos de cada cambio. El alta hacia un seguro con póliza que ya figura como «sin
  póliza» no se repite: se funde en esa fila, que cuenta de dónde viene la persona.
- **Para no teclear lo mismo dos veces** (punto 7). Tres botones en la cabecera, y ninguno guarda nada
  que DO no haya revisado:
  - **Leer PDF de póliza.** Se eligen uno o varios PDF (el corredor manda uno por persona) y pdf.js los
    lee EN EL NAVEGADOR —el documento y la fecha de nacimiento del asegurado no salen de la
    computadora hasta que se registra—. Cada póliza es una tarjeta editable con número, vigencia,
    prima con IGV, cuándo vence el pago y a quién asegura; se registra con `fn_seguro_registrar` (las
    mismas reglas del formulario) y el PDF se guarda en cada póliza. **Lo que dice el papel es una
    PROPUESTA**: una tarjeta solo nace marcada si trae número, vigencia y prima, una persona clara,
    NINGÚN aviso del lector y el documento del papel igual al de la ficha de esa persona. El nombre
    propone (por palabras, sin importar el orden, con umbral de 0.85 y un margen sobre la segunda
    candidata) y el documento comprueba: si no es el de la ficha, la tarjeta no se puede registrar; si
    falta (en el papel, en la ficha, o la consulta falló) nace sin marcar y lo dice, pero DO puede
    marcarla. Se adelantan los rechazos de la base —la persona no está en ese seguro, la póliza se cruza
    con otra, un año mal tecleado—, la que ya existe sale «Ya estaba registrada», y una foto escaneada o
    un PDF ilegible se dicen por su nombre. **La fecha final solo se da por probada cuando el papel dice
    «AL 01/01/2027 … A LAS 12 M» (las condiciones particulares), NO el 31/12 del aviso de cobranza ni
    del convenio**: ese es el último día cubierto y el sistema cuenta el final EXCLUSIVO; se midió sobre
    la póliza real de FOLA. La portada y el resumen del seguro valen solo de respaldo, con un aviso que
    dice de dónde salió la fecha. Una página que nombra dos pólizas no se le presta a ninguna, y solo se
    reconoce a Pacífico (de otra aseguradora se lee con aviso). **Un PDF con las pólizas de varias
    personas no se guarda en ninguna** (llevaría el documento y el nacimiento de las otras): se registran
    y la tarjeta lo dice. Cerrar el diálogo, o elegir otros PDF, con pólizas marcadas sin registrar
    pregunta antes.
  - **Una póliza para varias personas** (`fn_seguro_registrar_varias`). En «Registrar una póliza»,
    «A varias, la misma póliza»: una lista con casillas, el atajo «Las de planilla» (sale de
    `personas.en_planilla`, no de una lista de vínculos en el navegador) y la prima POR PERSONA, con
    «N × prima = total» a la vista. TODO O NADA: si a una no se le puede registrar, no se registra a nadie y
    el mensaje dice con quién falló (hasta 100 por vez; el seguro y lo común a todas —aseguradora,
    fechas, prima— se comprueban ANTES de recorrer la lista, para no culpar a la primera persona de algo que
    es de todas); quien ya tiene una póliza de ese seguro que se cruza se deja fuera con el motivo. El PDF de una póliza colectiva se COPIA dentro del almacén a las pólizas de las demás
    personas (cada fila tiene su propio objeto: un índice lo exige).
  - **Lista de asegurados** (`fn_seguro_asegurados`). Quiénes están en un seguro HOY con documento,
    nacimiento, ingreso, sede y póliza, y quién tiene datos por completar (sin documento o sin fecha de
    nacimiento la aseguradora no emite el certificado). Reemplaza la consulta a mano de Vida Ley
    (`scripts/sql-manual/quienes_van_al_seguro_de_vida_ley.sql`). **El CSV lo bajan DO y la dirección**
    (`puedeExportarListaDeAsegurados`, punto 8); lleva documento y fecha de nacimiento, y la pantalla
    recuerda compartirlo por un canal que se pueda revocar.

**Lo que decidí sin preguntar, y es de Felipe cambiar:**
- **La remuneración asegurable** —la que pide el seguro de vida— solo viaja al descargar el CSV y solo
  si se marca la casilla: ninguna otra pantalla de seguros la lleva al navegador. (Quién baja el CSV
  lo decidió Felipe, punto 8; la cuestión se planteó porque `puedeExportarPadron` ya distingue ver de
  llevarse un dato con documento, y el padrón sigue solo para la dirección.)
- **La prima de una póliza colectiva es la de cada persona** (una fila por persona): copiar el total en
  cada fila haría que cualquier suma de primas contara la póliza diecinueve veces. El formulario muestra
  «N × prima = total» y avisa que, si solo se tiene el total, se divida.
- **No hay alerta de «persona en planilla sin Vida Ley».** El Seguro de Vida Ley es obligatorio para toda
  la planilla desde el primer día (D. Leg. 688), pero `aplica_a_vinculos` solo manda en los seguros
  principales, así que el sistema no sabe quién DEBERÍA tener un seguro que va además. Lo más cerca son
  el atajo «Las de planilla» al registrar la póliza y la lista de asegurados. Convertirlo en un hueco
  es una decisión de producto —¿para qué vínculos es obligatorio cada seguro?—, no de esta migración.
- **Aviso de renovación a 45 días** (`DIAS_AVISO_RENOVACION`, `lib/admin/seguros.ts`). Número
  elegido, no de ley: el corredor necesita días y la prima de contado de la póliza de hoy venció
  17 días después de emitirse.
- **`vigente_hasta` es EXCLUSIVO**: el papel dice «del 01/10/2026 al 01/01/2027, 92 días, a las
  12 M». El 1/1 ya cuenta como sin cubrir (lado cauteloso). Una renovación que empieza ese mismo
  día no se cruza ni deja hueco.
- **El historial vive en su propia tabla** (`polizas_seguro_eventos`) y no en
  `correcciones_auditoria`: esas filas las leen la ficha, Lo mío, Correcciones y el CSV, y las
  cuatro tendrían que aprender a rotular «seguro.pagada_el».
- **«Hasta» nace a 3 meses de «Desde»** (la póliza de hoy) y se puede mover a 6 meses o 1 año.
- **Los avisos de un cambio no inventan un plazo**: el de dar de alta o de baja depende de cada
  aseguradora y del contador. Van a «Sin plazo», con los días que lleva esperando.
- **Quien se fue y ya no tiene una póliza que corra es historia**, aunque `fn_seguros_equipo` la
  traiga: son dos consultas, y a medianoche una póliza puede vencer entre la una y la otra.
- **«Cobertura suspendida» es una situación aparte.** Una póliza vigente por fechas cuya prima lleva
  más de 30 días sin pagarse ya no cubre (convenio de pago, cláusula quinta), pero la base solo sabe de
  fechas: sin esto la pantalla decía «Cubierto» de alguien que no lo está. Lo decide `estadoPrima`, no
  SQL; va arriba de la lista, justo después de quien no tiene póliza.
- **Una vigencia de más de diez años, o que termina a más de diez años de hoy, se rechaza** (y un
  vencimiento de la prima a más de un año de la vigencia): un año mal tecleado (20277 por 2027) dejaba a
  todo un lote «cubierto por siglos» y apagaba el aviso de hueco. El diez es un número elegido, no de ley.
- **El CSV de asegurados escribe las fechas en ISO** (`2026-10-17`), como el padrón y el resto de las
  exportaciones, y no `17/10/2026`: un `05/10/2026` se lee como 10 de mayo en un Excel en inglés, y aquí
  cada fecha decide si alguien está cubierto.
- **Un «otro papel» no se copia a las demás pólizas de una póliza colectiva** (la póliza, el convenio de
  pago y la factura sí): puede ser de una sola persona. Si una copia falla se ofrece repetir solo esas.
- **Las estaciones de Retail no entran a seguros**: `fn_seguro_registrar` y `fn_seguro_asignar` las rechazan.
- **Una póliza colectiva se registra a cada persona con el mismo número** (un seguro de vida o una EPS
  es una póliza de la empresa con un solo número). El índice único lleva `persona_id`: la MISMA póliza
  a la misma persona sigue frenada. Si FOLA repitiera un número entre dos practicantes, la base ya no
  lo frena: se vería en las dos tarjetas.

**Pendiente, en este orden (Felipe).**
1. **HECHO — la 0528 está PEGADA y VERIFICADA en producción (Felipe, 2026-10-17).** Se entregó con
   `./scripts/dame-el-sql.sh 528` (2365 líneas, 119 302 bytes, md5 `8ccbdbfb…`, comparado con el archivo
   de GitHub), después de volver a mirar `main` y la numeración. La consulta de «ANTES DE PEGAR» dio 0 tablas,
   0 funciones, 0 disparadores, 0 buckets y ningún registro 528 (había 525, 527, 529, 531 y 532); y la de
   comprobación con que termina la migración dio **6 tablas, 25 funciones, 1 disparador, 4 políticas de
   Storage, el bucket privado, RLS en las 6, los tipos de sistema `essalud,salud_practicantes` y el registro
   `528 · los_seguros_del_equipo_entran_al_sistema`**. No reescribe ninguna función, así que no hubo md5 de
   partida. Lo único que toca fuera de sus tablas es **un disparador en `personas`** (después de cambiar
   `tipo_vinculo`), y no puede frenar un cambio de vínculo.
   **Un número que no cuadró, y por qué no importa:** `apoyo_de_3` dio 4, no 3. La consulta cuenta `pg_proc`
   por nombre en TODOS los esquemas, y `retail.fn_hoy_lima()` vive en el mismo proyecto de Supabase. Se
   confirmó listando las cuatro: las tres de `public` (sin argumentos) y la de `retail`. Las 25 funciones de
   la 0528 fijan `search_path = public`, así que `fn_hoy_lima()` resuelve siempre a la de `public`. La
   cabecera de la 0528 no se tocó después de pegarla: su consulta de «antes» solo sirve para la primera pegada.
   Lo que falta es el PR (ver abajo) y los pasos 2 a 5.
2. **Averiguar qué seguros tiene el resto del equipo** («revisar», dijo Felipe) y agregar los que
   falten desde «Tipos de seguro». Mientras tanto, planilla y prueba quedan en EsSalud (por
   planilla) y nadie recibe un aviso por ellos.
3. **Registrar las cuatro pólizas FOLA** (N.º 24043264 a 24043267): lo más corto es «Leer PDF de póliza»
   eligiendo los cuatro PDF a la vez (el de 24043267 se leyó entero sin avisos). Cada tarjeta nace marcada
   solo si el documento del papel es el de la ficha de ese practicante: a quien le falte el DNI en su
   ficha se le marca a mano, y a quien tenga otro, la tarjeta no lo deja registrar. Si alguno no se
   entiende, el formulario de siempre. Falta adjuntar el convenio de pago y, cuando lleguen, las
   facturas. Los papeles llevan DNI y fecha de nacimiento: no entran al repo.
4. **Marcar los pasos que ya se hicieron**: la prima está pagada (Felipe, 15/10/2026); falta
   firmar y devolver la póliza y el convenio de pago, y pedir las facturas.
5. **Renovar antes del 01/01/2027.** Desde el 17/11/2026 la Bandeja avisa; la tabla de beneficios
   dice «Renovación automática: Aplica» y esta pantalla guarda `renueva_sola` como «sin
   confirmar» hasta que el corredor conteste.

**Abierto con el corredor, y la pantalla lo deja visible.** Las condiciones particulares traen
VACÍOS el plan y el «Beneficio máximo anual». Por precio, la póliza parece el Plan 1
administrativo (S/ 179.97 ÷ 3 meses = S/ 60 al mes, pp. 21, 36 y 37 del PDF): S/ 16,800 por
enfermedad y S/ 36,000 por accidente, con tope de remuneración de S/ 1,200. **Es una inferencia,
no un dato del papel.** Con la subvención de S/ 1,230, 14 y 30 subvenciones son S/ 17,220 y
S/ 36,900: ese plan se quedaría corto por S/ 420 y S/ 900 frente a lo que el convenio ya
promete. Pedir por escrito el plan y el beneficio máximo, y cargarlos con «Corregir datos».
**Lo que la pantalla NO hace** es comparar el beneficio con 14 y 30 subvenciones: pide la
subvención de cada quien (`asignaciones_salario`) y la 0528 no la lee.

**Qué se comprobó.** La 0528 aplicada **desde cero** por `supabase start` junto con todas las
demás migraciones, sin error, y pegada otra vez encima (idempotente); y la prueba **422**
(308 aserciones: 252 de la lógica de los seguros y 56 de «una póliza para varias personas», la lista
de asegurados y lo que halló la segunda revisión) en verde dentro de una transacción, también partiendo de una base SIN los objetos
de la 0528 (corriendo antes la receta de reversión de su cabecera, que así quedó probada de nuevo).
Se probó que la prueba SABE fallar con veintidós mutaciones; las ocho últimas son de las dos funciones
nuevas (tragarse el error del lote, quitar el `distinct`, el tope de 100, el último día inclusivo en la lista,
la remuneración que sale aunque no se pida, la cuenta de servicio y el estado activo en la lista, y
`en_planilla` en falso): las ocho las rompen. De las catorce primeras, las diez primeras
mutaciones de las reglas (último día inclusivo, EsSalud como hueco, el alta que no se cierra sola,
la baja que no se revierte, el disparador que ignora el estado o una asignación vigente o que deja
escapar su propio error, registrar una póliza sin comprobar el seguro principal, asignar lo que
ya toca por vínculo, y devolver el seguro efectivo como automático) y las cuatro de la revisión
(índice sin `persona_id`, UPDATE de Storage sin la forma del nombre, sin tope de aseguradora, sin
validar los textos de los avisos): las catorce la rompen. La segunda revisión sumó quince mutaciones
más, entre ellas las siete que mostró que sobrevivían: todas las detecta la suite.
`vitest` (2041 pruebas en 90 archivos, antes 1896: las nuevas son el lector de pólizas —con un texto
sintético con la forma de la de Pacífico, de 30 pruebas a 50, con once mutaciones: diez las detecta la suite y
la otra era código muerto—, las reglas de cada tarjeta de PDF y su cotejo de documento, la lista de asegurados y su CSV,
la subida y la copia de archivos, el cruce de fechas y las hermanas de una póliza colectiva y el permiso de
exportar; más las 83 de la lógica de la pantalla y las 33 de la Bandeja, incluida la que cuida que cargar una
consulta no pise el objeto compartido de `FUENTES_VACIAS`), `tsc` y `eslint` en verde, y los frenos del push (numeración, reglas de la casa, nombre del PDF, fechas vacías,
linter) corridos a mano sobre lo que la rama agrega: todos en 0.

**Revisión independiente (dos agentes que no vieron mis conclusiones, uno para el SQL y otro para la
pantalla; 2026-10-17).** Ninguno halló nada de gravedad alta: la lectura y la escritura están cerradas a
quien no es DO (probado con cinco sesiones distintas —líder de equipo, integrante, DO cesada con su cuenta viva, usuario sin ficha y anónimo—, contra las seis tablas, las 23 funciones y el bucket), el disparador sobrevive
a tres fallos inyectados, y un fuzz de 2000 escenarios y dos corridas de 1500 operaciones al azar no
rompieron ninguna invariante. Lo que sí hallaron, y **ya está arreglado**: una póliza colectiva (vida,
EPS) no se podía registrar a más de una persona; el disparador podía esperar por una pantalla de DO
(ahora las funciones de tipos bloquean con `for no key update`) y las funciones de DO bloquean en un
solo orden; la política de UPDATE de Storage dejaba renombrar un huérfano a un nombre con DNI; varios
topes salían como un CHECK crudo; una póliza con la prima suspendida figuraba «Cubierto»; el formulario
de póliza perdía el error del servidor si se cerraba a mitad de guardar; una asignación puesta a alguien
de honorarios no se podía terminar; y unos conteos, un orden y unos textos que no cuadraban.

**Segunda revisión, sobre las tres ayudas (otra vez dos agentes sin mis conclusiones, uno para el SQL y
otro para la pantalla y el lector; 2026-10-17).** Del SQL: sin hallazgos altos (no hay deadlock, lote a
medias, fuga ni pérdida de permisos al repegar). Lo que sí, y ya está arreglado: el año mal tecleado que
dejaba a un lote «cubierto por siglos» (tope de diez años); «Con Ana falló: escribe la aseguradora» culpaba
a la primera del lote de algo que es de todas (se comprueba antes); una estación de Retail aceptaba póliza
y asignación y quedaba invisible; y `fn_seguros_equipo` perdía su permiso con el `drop` (ahora va junto al
`create`). De la pantalla y el lector: la fecha final se daba por buena sin la frase que la prueba («A LAS
12 M»), y «hasta el 31 de enero» pasaba por exclusivo; una página que nombra dos pólizas le prestaba sus
datos a la equivocada; dos expresiones regulares con backtracking cúbico (20 000 saltos de línea tardaban
segundos); un monto con punto de oración («179.97.») leía 17 997 soles; los nombres se comparaban por
palabras sueltas («Rosa Díaz» se tomaba por «Díaz Rosa María»); una tarjeta con avisos nacía marcada y solo
el nombre elegía a la persona (ahora lo comprueba el documento); un PDF con varias pólizas se guardaba en
cada una; cerrar el diálogo perdía lo leído sin preguntar; una copia fallida de un archivo de póliza
colectiva no se podía repetir; la lista de asegurados sin ningún seguro quedaba «Cargando» para siempre, y
el CSV escribía `dd/mm/aaaa`. Todo está corregido y probado.

**Lo que se dejó, a propósito** (cabecera de la 0528, «LÍMITES CONOCIDOS»): los pasos de un cambio
guardan solo el último estado, sin historial de marcas como las pólizas; un cambio y su inverso el mismo
día dejan un alta pendiente en EsSalud que DO marca y ya; y `fn_seguro_archivo_libre` la puede llamar
cualquier sesión autenticada (solo dice si una ruta uuid está en uso). **Hallazgo ajeno, sin tocar:**
`fn_cesar_persona` con un vínculo nuevo falla para un PRACTICANTE (no limpia `practicante_modalidad`,
`personas_practicante_modalidad_coherente`); sin cambiar de vínculo, el cese funciona. La pantalla de
Equipo nunca manda un vínculo nuevo al cesar, así que hoy solo se alcanza llamando a la función a mano:
es un defecto latente, no uno que alguien esté pisando. Arreglarlo es reescribir una función con cinco
versiones (pide `donde-vive.sh` y el md5 de producción antes de escribir): de otra migración y de otra
sesión, y sin urgencia.

**En el navegador** (2026-10-17, contra la base local con la 0528 aplicada y trece personas de
prueba marcadas «ZZ Demo»: practicantes con y sin póliza, planilla, prueba, honorarios, dos que
cambiaron de vínculo —el disparador dejó el cambio solo—, una a la que DO le asignó un seguro que él
mismo agregó, y una que ya no está activa con su póliza vigente): la lista en el orden de atención,
el catálogo de «Tipos de seguro» (agregar un seguro con sus validaciones, archivarlo con motivo),
«Cambiar su seguro» ofreciendo solo lo que corresponde y volviendo al automático sin crear una
asignación, cerrar un paso de un cambio con la fecha de hoy ya puesta, el formulario de póliza
ofreciendo solo los seguros que llevan póliza y, si es el principal, solo a quien lo tiene, el
historial, y la Bandeja con las filas de seguros y su enlace a `/admin/seguros?persona=…`.
Escritorio, teléfono (375 px, sin desborde horizontal) y modo oscuro; las llamadas a la base
contestaron todas 200. **A pedido de Felipe**, después: los números de arriba pasaron de tarjetas a
botones de filtro, y estos a un solo botón «Filtros» junto al buscador (con la cuenta de los puestos)
que abre un panel con las dos listas de opciones —situación y seguro, cada número es el de filas que
deja ver—; lo puesto queda a la vista como chips que se quitan con un toque, y la pantalla abre limpia.
La descripción larga de la cabecera pasó a una línea corta con un ícono ⓘ que abre «Cómo funciona
Seguros», que además es la leyenda de cada filtro. Visto en escritorio, teléfono y oscuro.

**Lo nuevo (las tres ayudas), en el navegador** (2026-10-17, misma base local):
- **Leer PDF de póliza, con el PDF REAL de la póliza FOLA 24043267** (89 páginas, 1.7 MB): pdf.js lo leyó en el
  navegador y la tarjeta salió completa y sin avisos —seguro FOLA propuesto, persona emparejada por su nombre,
  vigencia 01/10/2026 → 01/01/2027 (92 días), prima 179.97, el pago vence el 31/10/2026, Pacífico Seguros,
  nota «Emitida el 14/10/2026»—; se registró y su PDF (1 779 531 bytes) quedó en la póliza. Con cuatro PDF a
  la vez: uno escaneado (sin texto) se dijo por su nombre, el que ya estaba registrado salió «Ya estaba
  registrada» y no se duplicó, una persona que se cruzaba con una póliza vigente quedó en rojo y frenó el
  botón hasta corregirla, y las dos que sí se podían se registraron con su PDF. **Probado con datos de
  una persona real sin tocar el repo**: el texto y el PDF viven solo en el scratchpad de la sesión, y la
  prueba del repo usa un texto sintético con la misma forma.
- **Una póliza para varias personas**: cinco personas de la demo con una sola póliza («Seguro de vida
  (ejemplo)», prima por persona, «5 × S/ 9.50 = S/ 47.50»); el atajo «Las de planilla» marcó las ocho de
  planilla y prueba; quien ya tenía una póliza que se cruzaba salió deshabilitado con el motivo; y el PDF
  subido una vez quedó en las cinco pólizas (cinco objetos distintos en el almacén, copiados dentro).
- **Lista de asegurados**: con la cuenta de dirección, la vista previa, la casilla de remuneración y el
  CSV (documento protegido para Excel, REVISAR con lo que falta, la remuneración solo cuando se marcó);
  y con la cuenta convertida por un momento en líder DO, lo mismo: el botón y la casilla están, y el
  archivo sale completo (13 filas, las 16 columnas). Antes de la decisión 8 esa vista no llevaba botón
  y explicaba por qué; ese texto queda para quien algún día no pueda descargar.
- **Teléfono (375 px) y modo oscuro** de las tres pantallas. Aquí apareció un defecto: con cuatro botones
  en la cabecera, la página se salía del teléfono (680 px de ancho de contenido). Es de `CabeceraPagina`
  (su acción es `shrink-0` y no le daba un ancho contra el cual envolver); se arregló ahí con `max-w-full`
  y se midió de nuevo: 375.

**El botón «Abrir» de un PDF**, comprobado en dos mitades: contra la API de Storage con la sesión
de DO, la URL firmada se genera y baja el PDF (HTTP 200, `application/pdf`), y la misma petición
sin sesión se niega. El clic mismo no se pudo probar en el navegador integrado de la app, que
bloquea las ventanas emergentes (sale el aviso propio de la pantalla: «El navegador bloqueó la
ventana del archivo…»); es el mismo camino que usa «Abrir» en Archivo.

**Lo que NO se comprobó.** Una póliza de otra aseguradora ni de otro seguro que no sea FOLA: el lector se
midió sobre la de Pacífico, y de otra solo se sabe que se lee con aviso. El cotejo de documento, la pregunta
de descartar, el PDF compartido y el reintento de copias se vieron en el navegador con PDF sintéticos (datos
inventados, ya borrados) contra la demo. Un iPhone real, ni la pantalla contra datos reales de producción: la
0528 ya está pegada, pero el código del PR todavía no se publicó, así que nadie ha abierto `/admin/seguros`
con datos de verdad. (`db-tests` de GitHub, la señal fiable de las pgTAP porque construye la base desde cero,
pasó sobre el commit `0a14c028`, igual que `ui-tests`.) El
disparador se probó con las dos funciones que de verdad cambian el vínculo —`fn_set_tipo_vinculo`
y `fn_cesar_persona`, incluido un cese con vínculo nuevo en el mismo acto—: lo que no mueve el
seguro no deja nada, lo que sí lo mueve deja su cambio, y quien ya no está activa no deja cambio.
La numeración deja huecos frente a `main` (0523, 0526 y 0530): ninguno es de esta rama (la 0530 es
la etapa 2) y se llenan cuando las suyas se fusionen. `main` ya se fusionó dentro de la rama el
2026-10-17: la prueba 422 corrió con sus migraciones nuevas (0527, 0531, 0532, 0533) aplicadas antes, y
en `types.ts` ganó la versión de esta rama, porque el de `main` traía una VIEJA (solo FOLA) de las
tablas de Seguros, arrastrada por una regeneración de tipos desde la base local compartida.

**FUSIONADO Y PUBLICADO el 2026-10-17 (PR #551).** Felipe lo pidió con la 0528 ya pegada y sabiendo que
fusionar publica: una sesión sacó el PR de borrador, dejó el comentario `<!-- cayla:fusion-sesion -->` y armó
la fusión con `--merge --auto`; GitHub la hizo a las 18:15 (hora de Lima), commit de fusión `48bedb5a`, justo
cuando terminó `db-tests` (✓ 5 min 22 s, igual que `ui-tests` ✓ 1 min 7 s sobre `5ac6a396`). Vercel publicó a
las 18:16 y `/admin/seguros` existe en producción (200; una ruta inexistente da 404). **Lo que ve DO desde
entonces:** `/admin/seguros` abre sobre las tablas vacías, así que **cada practicante sale como hueco** (su
seguro es FOLA y no tiene póliza registrada) hasta que se registren las pólizas (paso 3 de arriba). Eso es lo
que la pantalla viene a mostrar. Cuando se fusionó, `main` traía 8 commits de interfaz (PR #552, sin SQL) que
la rama no tenía: se probó la mezcla antes (limpia, `tsc` y las 2125 pruebas en verde). Si una de las tres
consultas de Seguros fallara en producción, por cómo está escrito `pedir` en `lib/admin/bandeja-fuentes.ts` la
fuente se marca «fallida» y solo ese módulo se queda sin datos, no la Bandeja entera (leído en el código, no
probado con un fallo real en producción).

**La etapa 2 («Mi seguro»)** está rehecha sobre esta, en la entrada de arriba (0530): cada
colaborador lee SU seguro y SUS pólizas —de cualquier seguro— y, si está en EsSalud, que se paga por
planilla. Felipe confirmó que los cuatro practicantes tienen cuenta y entran a Lo mío.

**Cómo se generaron los tipos.** La base local es compartida y trae migraciones de otras ramas
(la etapa 2 ya aplicó la suya), así que `gen-types` habría arrastrado cambios ajenos. Los 28 bloques de la
primera versión salieron del generador de entonces; los dos de las funciones nuevas
(`fn_seguro_registrar_varias`, `fn_seguro_asegurados`) y la columna `en_planilla` de `fn_seguros_equipo` se
agregaron a mano. **⚠️ Trampa para quien regenere `types.ts`:** el `supabase` que hay hoy (CLI 2.113.0, el que
pide `package.json`) escribe los argumentos de TODAS las funciones sin `| null` (`p_id: string`), y el archivo
del repo los lleva con él (`p_id: string | null`, más de 500 argumentos). Los bloques nuevos siguen el estilo del
archivo, no el del generador de hoy: regenerar el archivo entero cambia cientos de líneas ajenas a esta
rama y conviene hacerlo aparte, en su propio PR. El resto del archivo tampoco coincide con la base (por
ejemplo, claves foráneas de `boletas` que `types.ts` no tiene): deriva que ya traía la rama y no se tocó.

---

## 2026-10-17 — La política de movilidad se firma con la firma del sistema (0531) · SQL PEGADO Y VERIFICADO EN PRODUCCIÓN · FUSIONADO (#542) · rama `claude/politica-firma-del-sistema`

**Qué cambia.** En Documentación, el panel de la política ofrece «Con la firma guardada
de …» (por defecto, si quien firma por CAYLA tiene firma en `firmas_escaneadas`) o
«Subir el papel firmado a mano» (lo de siempre). La firma desde el sistema congela la
hoja tal como se imprime —tarifas, cláusulas, fecha y firma— en
`documentos_firmados.documento_html`, y «Ver documento» la muestra tal cual. La
función `fn_politica_firmar_con_firma_empresa` no recibe ni persona ni imagen: lee la
firma del firmante configurado y exige que sea exactamente la estampada en el HTML.

**Probado.** pgTAP 425 (18/18) dentro de `begin … rollback` con la 0531 y control sin
ella (falla). En el navegador, contra el Postgres local: firmar, ver, reemplazar (la
anterior queda en «Versiones anteriores» con su «Ver»). Los datos de prueba se
borraron; la 0531 quedó aplicada en el Postgres local.

**Pegada.** La 0531 se pegó en producción el 2026-10-17 y su comprobación salió con
las tres columnas en true (`columnas_puestas`, `constraint_puesto`, `funcion_creada`).
No reescribe ninguna función: no hubo md5 de partida. El PR #542 se fusionó el
2026-10-17 a las 15:22 (hora de Lima), con db-tests y ui-tests en verde. Se decidió que
cualquier admin/líder DO puede firmar la política con la firma de quien firma por
CAYLA —igual que hoy puede subir el escaneo—; si eso tiene que quedar solo para el
firmante, es un `if v_yo <> v_firmante` en la función.

---

## 2026-10-17 — Educación: pagar antes de la fecha declarada también corre el calendario (0527) · SQL PEGADO Y VERIFICADO EN PRODUCCIÓN · PR ABIERTO, SIN FUSIONAR · rama `claude/clever-nobel-3cdc5c`

**Solo alerta; no cambia lo que cobra nadie.** Defecto desde la 0450, medido con las
funciones de verdad: un mensual que vence el 15 de mayo, paga el 3 y declara el próximo
el 3 de junio. DO aprueba y el calendario **se queda en el 15**; el 24 de mayo figura
«vencida» por un mes ya aprobado. `fn_educacion_avanzar_calendario` comparaba la fecha
de pago contra la fecha declarada (`e.fecha_pago >= a.proxima_fecha_pago`), así que
pagar antes nunca la alcanzaba. Pasa con todas las frecuencias.

**Decisión de Felipe (2026-10-17): criterio A.** Avanza también cuando el pago cae
desde el día 1 del MES de la fecha vigente y lo declarado es posterior (o es «último
pago», que sigue poniendo null). Para toda frecuencia. Se descartó «solo hacia
adelante» a secas porque pisaría la fecha que DO fijó a mano.
`fn_educacion_fijar_calendario` no se toca. **Residuo conocido:** pagar en un mes
ANTERIOR al de la fecha vigente (vence el 3/nov, paga el 28/oct) sigue sin mover el
calendario; lo fija DO a mano.

**Medido.** pgTAP **421**, 34 aserciones: 34 verdes con la 0527; **15 rojas** en el
control sin ella (justo las de pagar antes y las de la vida real). Cuatro variantes
equivocadas de la regla (solo adelante, sin exigir `N > P`, solo mensual, ventana de
40 días) la rompen cada una por al menos una aserción. md5 de partida en **producción**
`bd2c70bb…` · 354 caracteres, idéntico a la 0450 (medido por Felipe el 2026-10-17;
**se vuelve a pedir justo antes de entregar**). Llegada, local: `51570d94…` · 727.
La sección 0 de la migración frena si la función no es esa versión.

**Pegada y verificada el 2026-10-17.** Felipe la pegó («Success. No rows returned») y la
consulta de comprobación devolvió, en producción: 727 caracteres · md5
`51570d948d13c3fe079ff78e2a6905e2` · marca «CAMBIO 0527» en la posición 376 · 0 retornos de
carro · 1 sola copia de la función · registro `527 · pagar_antes_de_la_fecha_tambien_corre_el_calendario`.
Coincide con el md5 de llegada medido en local. Falta fusionar el PR, que solo trae el
archivo ya pegado, la prueba 421 y este texto: ningún cambio de pantalla, y ya no hay orden
de pegado que respetar. Fusionar es publicar: se pide el OK aparte.

**Medido otra vez con `main` ya movido** (PR #541: 0525 y 0529 pegadas): la prueba 421 da 34
verdes contra el esquema con 0525, 0526 y 0529 puestas, y 15 rojas en el control con la
función de la 0450. La 0529 mueve el calendario de un pago adelantado con su propio trigger y
no reescribe esta función; las dos se llevan bien.

**Pendiente.** (1) ~~Pegar la 0527~~ hecho; es independiente de la 0526 (reescribe otra
función). (2) Felipe corre la consulta del final de la migración para saber cuántos estudios
**ya** quedaron atrasados: esta migración no los repara (solo actúa al aprobar); DO los fija a
mano con `fn_educacion_fijar_calendario`. (3) Con la 0525 ya en producción, revertir la
aprobación de un pago hecho antes de la fecha deja el calendario en la fecha de PAGO y no en
la de vencimiento (un pago del 3 con vencimiento el 15 revierte al 3). Es lo que la 0525 hace
con toda reversión; con la 0527 solo cambia que el pago puede ser anterior al vencimiento, y
lo único que se adelanta es el plazo. Solo alerta; no se tocó. (4) Sin entrada en
`novedades.ts`; decide Felipe.

---

## 2026-10-17 — Las boletas se firman, DO las ve firmadas y puede anular y restablecer en 48 horas · migración 0532 · PEGADA Y VERIFICADA EN PRODUCCIÓN · FUSIONADA Y PUBLICADA (PR #543, 2026-10-17)

**Pegada y verificada el 2026-10-17, DESPUÉS de fusionar.** El PR #543 se fusionó a las 19:59 UTC
(14:59 en Lima) **antes de pegar la 0532**, que es justo el orden que este archivo manda no
seguir. Mientras `main` ya estaba publicada y la migración no, firmar una boleta en producción
respondía «El sistema no encontró esta función», y lo vio una integrante real en «Lo mío». Se
pegó desde otra sesión con `./scripts/dame-el-sql.sh 532` (portapapeles idéntico al archivo de
`main`), el freno de md5 pasó y la comprobación devolvió
`funciones_nuevas_de_4=4 | columna_firma=1 | columna_estado_previo=1 | historial_con_rls=1 |
tablero_nuevo=1 | mis_boletas_nuevo=1 | guardar_version_nuevo=1` y el registro
`532 · las_boletas_se_firman_y_una_anulacion_se_restablece`. Duró de la fusión al pegado; no se
reportó daño más allá de ese error en pantalla. Lo que queda por comprobar en producción es el
recorrido real de punta a punta (una boleta propia de Felipe). No consta quién fusionó: GitHub
muestra la cuenta de Felipe, igual que cuando lo hace una sesión; la sesión que escribió esto
había dicho que no fusionaba y que avisaba antes.

**(Lo que sigue se escribió antes de pegar y fusionar; el «sin pegar» de abajo ya no es cierto.)**

**Hay SQL: la [0532](../supabase/migrations/0532_las_boletas_se_firman_y_una_anulacion_se_restablece.sql).**
**Se pegaba ANTES de fusionar:** el código nuevo llama a `fn_boleta_firmar`, `fn_boleta_restablecer`,
`fn_boleta_constancia` y `fn_boleta_anulaciones`, que no existen en producción hasta pegarla; con el
código primero, «Firmar» y «Anular» devolverían un error.

**Qué pidió Felipe (2026-10-17, tras ver el prototipo `docs/boletas-firma-prototipo-2026-10-17.html`).**
Que las colaboradoras firmen su boleta desde Dynamic cuando DO la sube; que DO vea la boleta con su
firma; y que DO pueda anular una boleta ya aprobada —viendo el nombre, la constancia y los datos para
saber si es la correcta— y restablecerla durante 48 horas. Decidido por él: firma con la guardada en Mi
perfil, **firmar es obligatorio** (la salida es «Entregada en papel»), carga persona por persona.

**Qué hace.**
- **Firmar:** `fn_boleta_firmar` copia en el acuse de esa versión la firma que la persona tiene guardada
  (`firmas_escaneadas`), con fecha y hora. Exige haberla abierto. Dos pasos en pantalla, y si no tiene
  firma la crea ahí mismo con `FirmaEditor`. «Confirmar que la recibí» se **retira**: la función sigue
  existiendo y contesta «recarga y usa Firmar» (así una pantalla vieja no ve «función inexistente»).
- **Recibida exige firma, y lo dice un trigger** (no un CHECK: un CHECK `not valid` se reevalúa cuando
  `fn_boleta_partes` actualiza una fila vieja y rompería a quien ya había confirmado). Quien confirmó
  antes queda «Confirmada», sin firma, y no se le agrega una después.
- **DO ve la firma:** `fn_boleta_constancia`; «Ver boleta firmada» muestra la boleta y la firma copiada.
- **Anular guarda cómo estaba** (`boletas.estado_previo`) y escribe en `boletas_anulaciones` (historial
  que solo se agrega). `fn_boleta_restablecer` devuelve la boleta exacta, con su firma —el acuse cuelga de
  la versión y anular no lo toca—, solo dentro de 48 horas desde `anulada_at` y solo si el grupo sigue
  pagado. Pasado el plazo, solo «Subir boleta nueva».
- **La persona ve «En revisión»** (`fn_mis_boletas` ahora devuelve las anuladas, sin versión ni
  archivos) y **no se le avisa** que se anuló, ni el motivo. Supuestos míos, no decididos por Felipe:
  que restablecer conserve la firma (no firma otra vez) y que no se le avise.
- **El globito de «Boletas» y la Bandeja ahora cuentan lo que espera firma**, no solo lo que no se abrió.

**Reescribe seis funciones y lleva su freno de md5.** `fn_boleta_guardar_version`, `fn_boleta_anular`,
`fn_boleta_confirmar_recibo`, `fn_boletas_acuses_guardian`, `fn_boletas_tablero` (la vigente es la de la
0491, con su `not cuenta_de_servicio`) y `fn_mis_boletas`. El bloque `0 · EL FRENO` aborta sin tocar nada
si alguna no coincide con lo que se copió (probado: se rompió una a propósito y la migración paró). **No se
pidió el md5 a producción antes de escribir**, como manda CLAUDE.md: el freno lo reemplaza al pegar, pero si
el PR #450 (que modifica la propia 0482) se fusiona antes, hay que volver a medir con `donde-vive.sh`.
Los md5 de partida son los de la base local construida de `supabase/migrations`; si producción tiene
comentarios de menos o `\r`, el freno lo acepta (mismos desenlaces que la 0491).

**Cómo se verificó.**
- pgTAP: la nueva **426** (53 aserciones: firma, guardián, constancia, anular, restablecer, plazo de 48 h,
  historial) y la **380** adaptada (87; «confirmar» pasó a «firmar») pasan. Se repegó la migración y es
  idempotente. La suite completa local dio 82 de 330 archivos en rojo, **todos por datos del Postgres local**
  (periodos `dead0c…` que chocan con `periodos_sin_solape` y con una llave foránea; 41 de los errores son
  esa misma colisión); ninguno es de boletas y **no se corrió el control** (la misma suite sin la 0532): la
  señal fiable es `db-tests` en CI.
- vitest completo (1 824, 87 archivos), `tsc` y eslint de lo tocado en verde. Los tipos de `database` se
  regeneraron con `gen-types` (el diff es grande porque el archivo llevaba atraso).
- **En el navegador, contra el Supabase local**, con DO y una integrante de prueba: DO sube una foto, la
  publica; la integrante la abre (el botón «Firmar» estaba apagado hasta entonces), crea su firma, firma en dos
  pasos; DO ve «Firmada» y «Ver boleta firmada» con la firma; DO anula con motivo (el botón se enciende solo
  con motivo y casilla del nombre; «Otro» pide 5 letras); «Ver anulación»; «Restablecer» la devuelve
  firmada; la integrante ve «En revisión» mientras está anulada. Datos de prueba borrados al terminar.

**Lo que NO se comprobó.**
- Un celular real (la pantalla de la persona y los modales se vieron solo en el navegador de escritorio).
- El plazo vencido en pantalla (se prueba a nivel de base y de reglas, no moviendo el reloj en el navegador).
- «Descargar con firma»: el prototipo la mostraba y **no se construyó** (haría falta generar un PDF).
- La entrada «Boletas» en el menú: la trae el PR #535, que la pone en **Pago, debajo de Planilla**; la
  jefa pidió **Personas**. Pendiente de decidir cuál queda.
- La consulta al laboralista y al contador (PR #450, `docs/consulta-boletas-de-pago.md`) sigue sin contestar:
  esto es una constancia de recepción, no firma digital certificada.

---

## 2026-10-16 — Educación: un estudio ya no tapa a otro (0524) · SQL PEGADO EN PRODUCCIÓN (2026-10-19, 15:07) · EN `main` · rama `claude/hungry-mirzakhani-1438df`

**Hoy no cuesta nada.** Medido en producción con la regla nueva contra la de hoy sobre
los tres últimos periodos: a nadie le cambia el pago. Es una regla frágil que se
endereza antes del próximo caso, no una plata mal pagada.

**El defecto.** La regla de la 0233 usaba UN día de referencia por persona. Si el
único estudio vigente el primer día del periodo se acababa ahí, todo lo que empezaba
después quedaba sin pagar (Duolingo hasta 28/09, Pop in colors e Italo desde 10/10:
boleta de S/104.25 donde tocaban S/165). **0524** da a cada estudio su propio día de
referencia. Mismo estudio = misma `familia_id`, o mismo beneficiario (y mismo hijo) con
la misma institución o con ciclos contiguos. El cuerpo vive en
`fn_planilla_calcular_nucleo` (la vigente era la **0504**, no la 0397: el envoltorio de
786 caracteres no paga nada).

**Decisión de negocio que revierte la 0233:** un estudio que empieza a mitad de periodo
cobra el mes completo ese periodo aunque la persona ya tuviera otro. Límite conocido
(documentado en la cabecera): dos ciclos del mismo beneficiario con instituciones
distintas, no contiguos y en un mismo periodo, se cobran los dos; en producción no hay
ninguno hoy.

**Pendiente.** ~~Pegar la 0524~~ **HECHO el 2026-10-19 a las 15:07**, como paso previo de la prueba de tres
días (la 0537 la exige): el 19 por la tarde producción devolvió `11425cad…`, el md5 de la 0524 tal cual. Queda,
aparte, medir en la boleta congelada de septiembre qué se pagó de educación a esa
integrante (Duolingo tenía dos tramos; las filas de hoy no se suman entre sí).
`donde-vive.sh` busca el primer contenedor `supabase_db_*` y con `cayla-retail`
levantado contesta «no existe en el Postgres local»: no es que falte, mira otra base.

---

## 2026-10-17 — Educación rediseñada: pago adelantado, historial y cuadrícula de íconos · 0525 Y 0529 PEGADAS Y VERIFICADAS · PR #541 SIN FUSIONAR · rama `claude/educacion-rediseno`

**0525 pegada y verificada en producción el 2026-10-17.** La comprobación devolvió
`525 · una_aprobacion_de_constancia_se_puede_revertir | 4 | 3 | true | true` (registro con número y nombre,
las 4 columnas, las 3 funciones y la marca «CAMBIO 0525» en las dos funciones reescritas). Su guarda aceptaba
el cuerpo de la 0450 tal cual o pegado desde Windows, y pasó: producción tenía la versión esperada.

**0529 pegada y verificada en producción el 2026-10-17.** La comprobación devolvió
`529 · un_pago_adelantado_cubre_varios_meses_y_el_historial_de_educacion | 7 | true | 2 | 3` (registro con número
y nombre, las 7 funciones, la tabla de meses, las 2 columnas de cobertura y los 3 triggers). Con las dos pegadas,
**ya se puede fusionar el PR #541** —que es publicar—, con OK de Felipe.

**Hay SQL, en este orden y ANTES de fusionar:** (1) la [0525](../supabase/migrations/0525_una_aprobacion_de_constancia_se_puede_revertir.sql)
(revertir una aprobación; ver la entrada de abajo: le falta el md5 de PRODUCCIÓN de dos funciones); (2) la
[0529](../supabase/migrations/0529_un_pago_adelantado_cubre_varios_meses_y_el_historial_de_educacion.sql) (no
reescribe nada: solo comprobar antes que sus nombres no existan; la consulta va al final del archivo). La
0526 (día 1) y la 0527 (calendario) son de otras ramas y no dependen de estas.

**Qué pidió Felipe y qué quedó (2026-10-17).**
- **Pago adelantado.** Quien pagó, p. ej., agosto a diciembre de una vez sube UNA constancia: desde/hasta en meses
  calendario (ambos incluidos), el total o el monto de cada mes; el sistema reparte y ella corrige un mes con
  motivo (≥ 3 letras; el resto del total se reparte entre los demás). DO la aprueba una vez; el calendario salta
  al pago siguiente al último mes cubierto y no se pide constancia de esos meses. En enero se paga como siempre y
  se pide la nueva («solo alerta»). Si el monto de un mes es menor que el costo declarado, el visor de DO avisa;
  si un mes está mal, se rechaza la constancia entera. La constancia sola no crea el apoyo ni enciende el pago.
- **Cuadrícula.** Un ícono por mes (aprobada, por revisar, rechazada, falta) y una raya para el apoyo (pagado
  —de la foto de planilla, `monto_educacion`—, este mes, se pagará). Detalle con la miniatura del comprobante al
  pasar encima; el visor al tocar. Un adelantado es una franja que une sus meses. El mes en curso va sombreado
  («hoy»), y el rótulo de la sede queda fijo al desplazar.
- **Pantalla de DO.** Cuatro pestañas (Constancias · Aprobadas del ciclo · Historial · Cómo funciona), «Para
  atender» en una línea y filtros en dos filas. Se abre en **«Solicitaron»**; **«Todos»** es todo, sin excepción
  (también terminados y personas liquidadas) y suma a quienes no pidieron como filas de su sede en la misma
  cuadrícula. «Estado del apoyo» arranca en «Todos».
- **Historial.** General (filtros por sede, persona, tipo y fechas; CSV), individual dentro de cada estudio, y
  «Tu historial» en Lo mío sin nombres de DO ni sus motivos internos.

**Cómo se verificó.** pgTAP [424](../supabase/tests/424_un_pago_adelantado_cubre_varios_meses.test.sql) (44; el encabezado de la 0529, ya pegada, dice 50 por un conteo mal hecho y no se toca) y
[419](../supabase/tests/419_una_aprobacion_de_constancia_se_puede_revertir.test.sql) (53) en el Postgres local
dentro de `BEGIN … ROLLBACK`; la 424 sin la 0529 falla (control). `tsc`, eslint y las 1 807+ pruebas de vitest en
verde (nuevas: `educacion-adelantado`, `educacion-historial`, `educacion-ciclo`). En el navegador, contra la base
local, como DO y como integrante: enviar el adelantado (reparto y corrección con motivo), revisarlo con el aviso de
monto menor, aprobarlo (el calendario saltó), la cuadrícula, los filtros, el historial con sede y el celular.

**Lo que NO se verificó.** Nada contra producción. La subida real de un archivo desde el celular (el navegador
automático no elige archivos). **Límite conocido:** la fila de un estudio puede decir «Rechazada» aunque un
adelantado aprobado cubra ese mes, porque `fn_educacion_situacion` elige la constancia por fecha de pago; se
arregla al reescribir esa función, que es la que reescribe la 0526 (otra rama).

**Limpieza (solo local).** La base local tiene personas «Demo», periodos y fotos de planilla de prueba, y dos
cuentas de prueba (anotadas en `apps/web/.env.local`, que no va a git).

---

## 2026-10-17 — Educación: una aprobación de constancia se puede revertir, y «Aprobadas en el ciclo de pago» · migración 0525 · SIN PEGAR · SIN FUSIONAR · rama `claude/educacion-revertir-aprobacion-constancia`

**Hay SQL: la [0525](../supabase/migrations/0525_una_aprobacion_de_constancia_se_puede_revertir.sql), SIN PEGAR.
Debe pegarse ANTES de fusionar** (el botón nuevo llama funciones que todavía no existen en producción). Antes de
entregarla hay que pedirle a producción el md5 de las dos funciones que reescribe (consulta abajo) y declararlo en su
encabezado, que hoy dice `__PENDIENTE__`.

**Qué pidió Felipe.** Alguien tenía una constancia aprobada que no debió aprobarse y no había dónde corregirlo (desde la
0450 lo revisado no se toca: un trigger lo impide). Pidió un apartado en Educación para ver a quién se aprobó en el
ciclo de pago, ver su constancia y rechazarla con motivos predeterminados u «otro» (mínimo 3 caracteres, sin máximo), y
que esos rechazos salgan en el historial de Educación. Decidió (2026-10-17): revertir **apaga el pago** si era la única
constancia aprobada del estudio y **se bloquea** si el pago ya salió con ella; el ciclo es el **periodo de planilla**
(29 → 28), no el mes calendario.

**Cómo está hecho.**
- `fn_educacion_revertir_aprobacion(id, categoría, comentario)`: la constancia pasa de aprobada a rechazada y conserva
  en columnas nuevas quién la aprobó y cuándo (`aprobada_*`) y quién la revirtió y cuándo (`aprobacion_revertida_*`);
  deja su fila en `correcciones_auditoria`. Nadie revierte su propia constancia. El pago NO se toca desde ahí: el espejo
  de la 0450 ya deja o quita el `comprobante_url` según haya o no otra constancia aprobada.
- **La única puerta** es esa función: el trigger de la 0450 (`fn_educacion_entrega_inmutable`, reescrito) deja pasar
  aprobada → rechazada solo si vienen juntos `current_user = 'postgres'` y la marca de reversión. Un `UPDATE` directo,
  de quien sea, sigue negado.
- `fn_educacion_revertir_efecto(id)` dice, antes de confirmar, si apagaría el pago y si está bloqueado; la pantalla
  solo lo muestra. **Bloqueado = no queda otra aprobada y el grupo de la persona (`tipo_vinculo`) tiene un periodo
  pagado DESPUÉS de aprobar esa constancia** («Reabre el periodo primero»).
- El calendario retrocede (a la fecha de ese pago) solo si esa aprobación fue la que lo avanzó y no hay otra más
  reciente; si no, no se mueve.
- `fn_educacion_aprobadas_del_periodo(periodo)`: lo aprobado EN el periodo, por el día en que DO aprobó (no por el del
  pago). `fn_educacion_entregas` gana cuatro columnas (aprobada/revertida, con nombre solo para DO).
- Pantalla: sección «Aprobadas en el ciclo de pago» en `/admin/educacion` (plegada, carga al abrirla), con selector de
  ciclo, «Ver constancia» en la misma fila, «Rechazar…» con el aviso del efecto sobre el pago. La constancia revertida
  se ve en la cuadrícula (rechazada), en el visor («Aprobación revertida») y en el historial del estudio. Los campos
  del rechazo se sacaron a `components/educacion/campos-de-rechazo.tsx` y los usan los dos rechazos (una sola copia).
  Novedad de DO en `novedades.ts`.

**Qué se comprobó.** Prueba pgTAP [419](../supabase/tests/419_una_aprobacion_de_constancia_se_puede_revertir.test.sql)
(53 aserciones) contra el Postgres local, dentro de `BEGIN … ROLLBACK`, con la 0525 puesta: 53 verdes; **el control sin
la 0525: rojo** en lo que debe. La migración se pega dos veces sin error (idempotente). `tsc`, eslint y las 1785
pruebas de vitest en verde. En el navegador, con la base local y datos de prueba (Ana con otra aprobada, Bea con una
sola, Carla con el pago ya salido): la sección carga y cambia de ciclo, «Ver constancia» muestra el papel, el botón se
apaga con menos de 3 letras, rechazar a Ana la dejó «Rechazada» con su motivo (tarjeta, cuadrícula, visor y auditoría),
y el caso de Carla muestra el bloqueo en rojo sin campos. También en un celular de 375 px, sin desbordes.

**Qué NO se comprobó.** Nada contra producción ni contra datos reales; el caso «el grupo pagó después de aprobar» está
medido solo con filas de prueba. La Bandeja de la integrante (que el rechazo le llegue y se lo diga bien) no se abrió en
el navegador. No se midió cuántas constancias aprobadas hoy en producción quedarían **bloqueadas** al intentar
revertirlas (todas las de una persona cuyo grupo ya pagó después de aprobarlas y que no tiene otra): conviene medirlo
antes de prometer que «siempre se puede corregir».

**Para Felipe, en este orden.** (1) Pegar en el SQL Editor y mandar el resultado:
`select p.proname, md5(p.prosrc), length(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and
p.proname in ('fn_educacion_entrega_inmutable', 'fn_educacion_entregas');` — locales (= repositorio):
`dc4ba3e1…` · 1045 y `d4c4fe5b…` · 1126. Si producción devuelve otros (comentarios perdidos, o `\r` por Windows), se
declaran los de producción y se agrega a la guarda de la sección 0; si no coincide ninguno, se para. (2) Pegar la 0525.
(3) Fusionar el PR. **La regla «la constancia se pide el día 1 de cada mes»** (mensuales; plazo como hoy) quedó
propuesta como sesión aparte: reescribe `fn_educacion_situacion`; no depende de esta migración.

**Limpieza pendiente (solo local).** Para ver la pantalla se cargaron en el Postgres local de `cayla-dynamic` cuatro
personas «Demo», tres estudios, cuatro constancias, dos periodos y una cuenta de prueba (`do-prueba@cayla.dev`);
borrarlas exige `set session_replication_role = replica` porque las entregas no se borran.

---

## 2026-10-16 — Educación: cuadrícula de constancias por mes, visor sin descargar, sede y filtros · SIN SQL · COMMITEADO, SIN PR TODAVÍA · rama `claude/constancias-filtros-sede-a4201b`

**No hay migración que pegar.** Todo sale de las dos funciones que ya existen
(`fn_educacion_situacion`, `fn_educacion_entregas`). Está commiteado en la rama
(`b1e7378a` y un segundo commit con los arreglos de la revisión de abajo); no se ha
subido ni abierto PR.

**Qué pidió Felipe y qué quedó.** «Ver las constancias sin descargar, los meses
anteriores, el filtro y todo por sede». Decidido por él en 16 preguntas el 2026-10-16:
visor grande sobre la misma pantalla (foto o PDF con todas sus hojas, datos y
Aprobar/Rechazar al lado, ← → entre constancias), cuadrícula persona × mes con seis
meses y «ver más», mes = calendario del pago, **un mes sin constancia es un guion y
nunca una falta**, una fila por persona e institución (el Duolingo registrado dos
veces es una línea), las cinco tarjetas siguen la sede y el mes elegidos, sin
aprobación en lote, CSV de lo que se ve y ZIP del mes. La sede y el diseño los dejó
a criterio de quien construyó. Quién ve la pantalla **no cambió**: solo DO y admin.

**Dónde vive.** Lógica pura en `apps/web/lib/admin/educacion-meses.ts` (con
`tests/educacion-meses.test.ts`) y `zip-constancias.ts`; piezas en
`apps/web/components/educacion/`. El PDF se **dibuja** con pdf.js (`legacy`) y no se
incrusta: Safari de iPhone solo mostraría la primera hoja de un PDF incrustado.
Dependencias nuevas: `pdfjs-dist` y `fflate`. La aprobación/rechazo salió del panel a
`AccionesRevision`, que usan el panel y el visor.

**Los decodificadores de pdf.js viven en `apps/web/public/pdfjs/wasm/`.** Sin ellos,
un PDF escaneado en blanco y negro (JBIG2) o con JPEG 2000 sale EN BLANCO en el visor,
sin error. Se midió el 2026-10-16 con un PDF de prueba JPEG 2000: hoja en blanco antes,
legible después. **Si se sube `pdfjs-dist`, hay que volver a copiarlos** (`cp
apps/web/node_modules/pdfjs-dist/wasm/{jbig2,openjpeg,qcms_bg}.wasm apps/web/public/pdfjs/wasm/`):
`tests/pdfjs-wasm.test.ts` falla en CI si no coinciden byte por byte.

**Revisión independiente (2026-10-16).** Cinco revisores con lentes distintos leyeron el
commit y 78 verificadores intentaron refutar o reproducir cada hallazgo: de 39 candidatos,
35 confirmados, 2 discutidos y 2 descartados. Lo confirmado se arregló. Lo que más pesó:
(1) el PDF escaneado en blanco de arriba; (2) una consulta de constancias que fallaba se
dibujaba y se exportaba como «sin constancia» —ahora se marca «?», no esconde al estudio
de ningún filtro y el CSV/ZIP se niegan hasta reintentar—; (3) el CSV y el ZIP de un mes
omitían en silencio los apoyos terminados y las personas liquidadas —ya no—; (4) una
constancia por revisar de un tramo terminado o de una persona liquidada no se veía en
ninguna tarjeta ni pestaña —ahora **lo que espera revisión no se esconde por un filtro
que nadie eligió**—; (5) dos dibujados a la vez sobre el mismo canvas dejaban la hoja
mal pintada.

**Qué se comprobó.** `tsc`, eslint, las pruebas y `next build` en verde. En el
navegador, con datos simulados y archivos reales en el Storage local (la base local no
tiene la 0450, así que NO se probó contra la base): miniaturas de foto y de PDF, el
visor en escritorio y en celular (las dos hojas del PDF se ven), aprobar desde el
visor con la confirmación encima, Esc que cierra solo la confirmación, el panel de
estudio con su historial, el filtro por sede y por mes y la dirección que los guarda.

**Lo que NO se comprobó.** Un iPhone real; el clic en «Descargar» (CSV y ZIP): se
probaron los nombres de archivo, las extensiones y los repetidos, no la descarga misma;
y los datos reales de producción.

**Deuda a la vista.** Al entrar se hace una consulta por estudio (de a seis): con ~30
personas no se nota; si la lista crece, conviene UNA función SQL que devuelva todo, y
esa sí exigiría pegar antes de fusionar. El panel «Estudio» de una fila con varios
tramos abre el tramo que habla por la fila; las constancias de los otros se ven en la
cuadrícula y en el visor.

---

## 2026-10-15 — Los practicantes pasan de EsSalud al seguro FOLA · migración 0504 · PEGADA Y VERIFICADA EN PRODUCCIÓN · FUSIONADA Y PUBLICADA (PR #532, 2026-10-15)

**Pegada y verificada el 2026-10-15.** El SQL Editor devolvió el registro
`504 · los_practicantes_pasan_de_essalud_a_seguro_privado`, y una consulta aparte,
escrita ANTES con los valores esperados calculados sobre el archivo, dio `true` en
las once filas: `fn_planilla_calcular_nucleo` con md5 `f1781d68…` y 116749
caracteres, `fn_set_tipo_vinculo` con md5 `da6490ac…` y 2624 caracteres, una sola
versión de cada una, 0 retornos de carro, y el marcador «CAMBIO 0504» en la
planilla. Lo que eso garantiza es el texto de las dos funciones; que un practicante
dé EsSalud 0.00 en el cálculo en vivo lo prueba la 398 en CI, y **no se midió contra
una planilla real de producción**. Los periodos ya congelados no se recalculan.

**Fusionado y publicado el 2026-10-15 a las 14:58 (Lima)**, después de pegar la SQL,
como manda el orden. Fusión armada con `--auto --merge` a pedido de Felipe, sin
`--admin`; `db-tests` y `ui-tests` en verde sobre el commit de la fusión
(`2d73c1b0`), y ese commit publicado en producción. Desde entonces el convenio de
prácticas que genera Contratos dice «seguro privado» (14 / 30 subvenciones, alcanza
los accidentes de la práctica).

**Hoy no cuesta nada, y queda abierto.** Felipe decidió fusionar **sin** la
confirmación escrita del corredor, asumiendo el riesgo: el convenio ya promete lo de
arriba, y ni el «Beneficio máximo anual» ni la cobertura de la modalidad
preprofesional están comprobados (ver la tabla). Solo pesa si un practicante se
enferma o se accidenta y la póliza no alcanza lo que el convenio dice: esa diferencia
la debería LA EMPRESA.

**Los cuatro firman el convenio nuevo, no una adenda** (decidido por Felipe el
2026-10-16). Ninguno tiene un convenio firmado que diga EsSalud que haya que
corregir, así que la rama `claude/adenda-convenio-en-info` (2026-10-02, sin PR) no
hace falta para esto.

**Qué es.** La planilla deja de calcular `aporte_essalud` para los practicantes
(una línea de `fn_planilla_calcular_nucleo`), el motivo que `fn_set_tipo_vinculo`
guarda al pasar a alguien a practicante deja de prometer EsSalud, y el convenio de
prácticas dice «seguro privado» (Ley 28518, art. 42.8). Nada más cambia para un
practicante: movilidad y educación siguen igual (0397 no se toca).

**La póliza ya existe.** Cuatro pólizas individuales de «Seguro de Salud
Practicantes» de Pacífico (N.º 24043264 a 24043267), emitidas el 14/10/2026, con
vigencia **01/10/2026 → 01/01/2027** (92 días). Prima S/ 179.97 con IGV por póliza,
unos S/ 60 al mes contra S/ 110.70 de EsSalud. Los papeles no se guardan en el
repo (llevan nombres): viven en el correo de Felipe y con el corredor.

**Lo que Felipe tiene que hacer, y no es el SQL.**

| Qué | Cuándo | Si no |
|---|---|---|
| ~~**Pagar las cuatro primas** (S/ 719.88 en total, contado)~~ | ✅ **pagadas** — lo informó Felipe el 15/10/2026 (vencían el 31/10) | Con 30 días de mora la cobertura se suspende. Queda pedir las facturas, que Pacífico emite al pagar: Dante las va a necesitar |
| ~~**Enviar a cada practicante su póliza**~~ | ✅ **enviadas** — lo informó Felipe el 16/10/2026 | Ese correo es la constancia de entrega: no borrarlo. No hace falta un cargo aparte: el convenio no promete entregar la póliza, y la firma del convenio nuevo prueba que cada uno sabe que tiene seguro |
| **Pedir las facturas de las cuatro primas** | cuanto antes | Dante las va a necesitar |
| **Firmar y devolver póliza y convenio de pago** | cuanto antes | Pacífico los pide firmados; la casilla del asegurado/contratante está en blanco en los cuatro |
| **Que los cuatro firmen el convenio nuevo** | cuanto antes | Se genera desde Contratos; ya dice «seguro privado» |
| **Renovar la póliza** | **antes del 01/01/2027** | Desde ese día los practicantes quedan sin seguro, y la planilla ya no calcula EsSalud al que volver |
| **Confirmar con el corredor el «Beneficio máximo anual»** | **abierto — el convenio ya lo promete** | La casilla está VACÍA en las cuatro pólizas y la Tabla de Beneficios no viene adjunta: el mínimo de 14 / 30 subvenciones que el convenio nuevo promete no se puede comprobar con estos papeles |
| **Preguntarle si la póliza alcanza a la modalidad preprofesional** | **abierto — el convenio ya lo promete** | El resumen dice que cubre a quien esté en un convenio de «Formación Laboral Juvenil o Prácticas Profesionales», y **dos de los cuatro asegurados son preprofesionales** (los otros dos, profesionales). Pedirlo por escrito |

**Antes de pegar la 0504 (en este orden).**
1. ✅ **Hecho el 15/10/2026.** [`antes_de_pegar_la_0504.sql`](../scripts/sql-manual/antes_de_pegar_la_0504.sql)
   corrido en producción: `fn_planilla_calcular_nucleo` md5 `27dda408…`, 116375
   caracteres, 0 retornos de carro (igual a la 0495 del repo); `fn_set_tipo_vinculo`
   md5 `547088d9…`, 2610 caracteres, una sola versión (la 0324). Y los practicantes
   no cesados son exactamente cuatro, las cuatro personas de las pólizas: la
   migración quita el EsSalud a todos de una vez y la póliza es nominal.
2. ✅ **Hecho el 15/10/2026.** Entregada con `./scripts/dame-el-sql.sh 504`,
   mirando `main` en ese mismo mensaje (no se había movido).
3. ✅ **Pegada ANTES de fusionar el PR**, como manda el orden: el PR trae el texto
   nuevo del convenio.

**Un choque que se vio y quedó frenado.** La rama
`claude/youthful-joliot-8dd9cb` (pasar a planilla pregunta desde cuándo empieza el
vínculo laboral, SIN PR) también reescribe `fn_set_tipo_vinculo`, y le cambia la
firma. Si cualquiera de las dos se pega primero y la otra no se rehace, la segunda
pisaría a la primera o dejaría dos versiones con los mismos dos argumentos
(«function is not unique», la forma de la 0297/0299). La 0504 ahora lo comprueba
antes de tocar nada y se detiene si esa función no es la de la 0324; se probó con
funciones de mentira dentro de `begin … rollback`: pasa con la 0324 real y frena
con una de cinco argumentos, con una sobrecarga extra y con una de dos argumentos
sin el marcador. La rama de «pasar a planilla» ya traía su propio freno por md5
de la 0324, así que si la 0504 entra primero ella se detiene en vez de pisar: tendrá
que rehacerse partiendo del cuerpo de la 0504.

**Y la 0504 ya entró primero.** Producción tiene desde el 15/10/2026
`fn_set_tipo_vinculo` con md5 `da6490ac5d12722e38fcba0a2d47dea9` y 2624 caracteres.
Quien retome la 0518 de «pasar a planilla» (`claude/youthful-joliot-8dd9cb`) tiene
que partir de ESE cuerpo —el de la 0504, ya en `main`—, no del de la
0324, y cambiar su md5 de partida (hoy declara `547088d9…`, 2610 caracteres): su
freno se detendrá, que es lo que se quiere. La única diferencia con la 0324 es la
frase del motivo de auditoría que se guarda al pasar a alguien a practicante.

**Lo que no se midió en esta Mac.** El Postgres local está en la migración 338 y
no tiene `fn_planilla_calcular_nucleo`, así que la parte de planilla de la 0504 se
audita con `db-tests` de GitHub Actions (construye la base desde cero y corre la
prueba 398). Auditoría anterior, del 2026-10-02 en un Postgres desechable con
control: 398 daba 6/8 sin la migración y 8/8 con ella, y el resto de la suite era
idéntico con y sin 0504. `fn_planilla_calcular_nucleo` sigue siendo la 0495 en
`main`, o sea que el cuerpo del que parte no cambió.

**Lo que dijo `db-tests` en el primer intento (commit `d675dba8`).** Falló UNA
aserción, la 41 de la prueba **396** (la de la 0502): afirmaba que el practicante
genera S/ 110.70 de EsSalud, que es justo lo que la 0504 quita a propósito. Esa
prueba entró a `main` después de que se escribió la 0504, así que la rama vieja no
podía verla. Se ajustó a 0.00 y se dice por qué en la propia prueba. La **398**
pasó, o sea que la migración entera se aplicó sobre una base armada desde cero,
freno nuevo incluido.

---

## 2026-10-13 — Easter eggs y el colibrí sin internet · SIN SQL · SIN FUSIONAR

**Qué es.** Cinco secretos pasivos y una página para cuando no hay internet,
con el juego del colibrí (tres juegos en uno: 50 % vuelo, 40 % salto, 10 %
flappy). El catálogo y cómo activar cada uno está en
[`easter-eggs.md`](easter-eggs.md); allí se anotan los que vengan.

**No hay migración:** todo es frontend y archivos estáticos. Fusionar el PR ES
publicar, como siempre.

**Lo que conviene saber antes de fusionar.**
- Es el primer service worker con alcance `/` (el del terminal sigue siendo
  `/terminal/`, y este lo ignora a propósito). **No guarda ninguna página del
  panel**: solo tres archivos sin datos. Está probado ejecutándolo (no leyéndolo)
  en `tests/sin-conexion.test.ts`, y se comprobó en un navegador real cortando el
  servidor: el panel muestra el aviso, el terminal NO.
- **Solo funciona en dispositivos que ya abrieron Dynamic una vez con internet**
  después de este despliegue. La primera visita sin red ve el error normal.
- Se registra solo en producción. En `pnpm dev` no hace nada, para no dejar un
  service worker pegado a `localhost:3000`.

**Pendiente.** El toque del **aniversario de CAYLA**: falta el día exacto (en
Retail es una campaña con ventana editable, no un día). Ver el final de
`easter-eggs.md`.

---

## 2026-10-13 — El bono del practicante vuelve a la boleta, y se paga al cierre del periodo · migración 0521 · PEGADA Y VERIFICADA EN PRODUCCIÓN (2026-10-16) · PR #539 PENDIENTE DE FUSIONAR

**Decisión de Felipe, el mismo día, al ver funcionando la 0520:** el pedido de
Daniel Ruiz salió en la Bandeja «S/ 180.00 por transferir» y lo rechazó —«no
transferir a cada rato, sino pagar al fin del periodo»—. Revierte la regla de la
0519/0520 (el practicante nunca va a la boleta). La 0518 y la 0520 siguen
pegadas; esto va ENCIMA de la 0520.

**Antes de escribir, se midió** (planilla vigente, un practicante y un integrante
de planilla en las mismas condiciones, bono de S/ 180 en cada boleta; repetido el
2026-10-16 con la 0504 ya en la base): el total del practicante sube de 714.64 a
894.64, exactamente S/ 180, igual que el de planilla; su EsSalud queda en 0.00
antes y después (la 0504 se lo quitó; antes de ella eran 110.70 y tampoco se
movía) y AFP no cambia; la **retención de 4.ª sigue en 0** (su guarda es `rxh`).
Lo único que se mueve es el campo informativo `retencion_4ta_base`, y se mueve
IGUAL en el de planilla: es un número que se muestra, no un descuento. El temor de la 0520 («la planilla le
arma base de retención de cuarta con el bono dentro») es cierto como campo y no
tiene efecto sobre lo que cobra. Prueba **415**.

**Qué hace la 0521:** `fn_confirmar_mi_bono_cumpleanos` pierde la excepción del
practicante (un bloque, marca `CAMBIO 0521`), y
`fn_bono_pasar_pedidos_de_practicantes_a_boleta()` —no concedida a nadie, la corre
la migración— pasa a la boleta del periodo abierto lo que la 0520 dejó «por
transferir»: solo practicantes activos, sin transferencia ya confirmada, con
periodo no pagado; idempotente. No toca el respaldo legítimo de los de planilla.
No toca `fn_planilla_calcular`.

**Pruebas (cada una en `begin … rollback` sobre el esquema completo):** 415 nueva
(26; sin la 0521 fallan 4), 414 y 413 ajustadas (decían «nunca por la boleta»),
y 335, 377, 378 sin cambios y en verde. Frontend: la pantalla del practicante
(Info, /mio/cumpleanos y la Bandeja mía) vuelve a decir «se suma a tu boleta» y
«tu subvención» donde decía «planilla»;
la constancia de practicante lleva «se abona en la boleta del periodo, como
concepto aparte de la subvención».

**PEGADA el 2026-10-16, ANTES de fusionar el PR** (la regla general). El frontend
del PR promete «se suma a tu boleta» al practicante y trae una novedad que corrige
la anterior; por eso va después de pegar. Con el freno de la propia migración (que
comprobó el md5 de partida y abortaba sin tocar nada si no coincidía), la respuesta
del SQL Editor fue `firma_sin_excepcion = t`, `sin_sobrecarga = t`,
**`practicantes_con_bono_en_boleta = 1`**, `practicantes_aun_por_transferir = 0` y el
registro `521 · el_bono_del_practicante_vuelve_a_la_boleta`.

**Verificada en producción** con una consulta de ocho filas, todas iguales a lo
calculado antes en local: `fn_confirmar_mi_bono_cumpleanos` `b7a826e9…` tal cual /
`e796c2b3…` sin comentarios (el mismo código que la 0479, sin la excepción: solo
cambiaron los comentarios) / 5236 caracteres / 0 retornos; lleva `CAMBIO 0521` y no
tiene `v_practicante`; `authenticated` puede ejecutar la firma y NO la reparación;
`fn_mi_bono_cumpleanos` (`d35c7d75…`, 4726) y `fn_documento_registrar` (`2d78559a…`,
5567) no cambiaron. **Daniel Ruiz tiene su línea «Asignación por cumpleaños» de
S/ 180.00 en la boleta del periodo que cierra el 2026-10-28, atada a su constancia, y
ningún practicante tiene dos líneas en el mismo periodo.**

**NO REPEGAR la 0518 ni la 0520 después de la 0521:** la 0520 recrearía
`fn_confirmar_mi_bono_cumpleanos` con la excepción del practicante y revertiría
esta migración en silencio (su freno salta con el registro 520 y el resto del
archivo corre). El traslado de la 0521 sí se protege solo: corre únicamente la
primera pegada (medido: pegar dos veces, con una línea quitada por DO en el
medio, no la reinserta).

**md5 de partida de producción:** `fn_confirmar_mi_bono_cumpleanos` (0520) era
`4c1ce380…` tal cual / `7d430c38…` sin comentarios, 5440 caracteres. No se pidió antes
de entregar —Felipe pidió el SQL directamente—; lo comprobó el freno de la migración
al pegar, y habría abortado sin tocar nada si no coincidía.

**Límite conocido, HEREDADO de la 0479 y de cualquiera que esté en boleta (revisión
adversarial, 2026-10-16):** anular una constancia de bono desde Documentación solo marca
`anulado_at`; **no retira la línea de la boleta**, y como el índice único por año
excluye las anuladas, quien firmó puede volver a firmar y quedar con DOS líneas de S/ 180
en el mismo periodo. Hoy exige dos pasos deliberados (DO anula una firma digital y la
persona firma otra vez), y la línea duplicada se ve en Planilla antes del cierre. **Hasta
que se arregle en una migración aparte —que `fn_documento_anular` retire la línea cuando
el periodo no esté pagado—, al anular un bono que ya va en boleta, DO tiene que quitar
también la línea desde Planilla.**

**Sigue abierto, y no depende de esto:** las tres preguntas al contador (Ley
28518: ¿puede darse un monto por cumpleaños a un practicante sin que cuente como
subvención?, ¿qué texto y cómo consta?, ¿deducible?). El texto de `TextoBono` para
practicantes es **provisional**. Y el límite de que la constancia se pinta con el
vínculo ACTUAL, no con el de cuando se firmó (necesita una columna).

---

## 2026-10-13 — Info saluda en el mes de cumpleaños, y el bono es para todo el equipo salvo prueba y contratos cortos · 0518 y 0520 PEGADAS EN PRODUCCIÓN (2026-10-13) · 0519 NEUTRALIZADA · SIN FUSIONAR

**El caso.** Daniel Ruiz, practicante, cumple en octubre, y el 13 no tenía nada
en su Info ni en su Bandeja mientras DO lo veía como «Bono de cumpleaños sin
constancia firmada». Reproducido en local con un perfil igual: el tablero decía
`este_mes` y `fn_mi_bono_cumpleanos` decía `no_aplica` — dos funciones
contestando distinto sobre la misma persona (era el pendiente anotado abajo en
la sección de la 0478, ahora cerrado).

**Decidido por Cayla ese día:** todos firman —planilla y practicantes— salvo
quien está en periodo de prueba (`tipo_vinculo = 'prueba'`) o tiene un
contrato de menos de una semana (7 días con los dos extremos incluidos, leído
de `personas.fecha_fin_contrato - fecha_ingreso + 1`; sin fecha de fin es
indefinido y le toca). RxH y `no_trabajador` siguen fuera.

**Lo que hace la 0518.** Una función nueva, `fn_persona_le_corresponde_bono_cumpleanos`,
dice a quién le toca; la leen las TRES puertas, cada una con un `CAMBIO 0518`
marcado sobre su versión vigente: `fn_mi_bono_cumpleanos` (0479 → Info, Bandeja
mía, /mio/cumpleanos y la firma), `fn_documento_registrar` (0448 → el cargo en
papel de DO) y `fn_documentos_tablero` (0492 → lo que DO ve en Documentación y
en su Bandeja). A quien no le toca, el tablero ya no le pide nada.

**Sin SQL, en el frontend:** el saludo de cumpleaños en Info
(`app/(mio)/mio/saludo-cumpleanos.tsx`, mensajes en `lib/saludos-cumpleanos.ts`):
aparece del día 1 al último del mes, arriba de todo —solo el acuse va antes—,
para TODO el mundo, con 16 mensajes que rotan cada 9 s (se paran al pasar el
mouse y con «reducir movimiento»). El botón «Firmar mi bono» solo sale cuando
la base dice que puede (`puedePedirBono`): nunca un botón que va a fallar. La
novedad del equipo va en el mismo PR (`2026-10-13-cumpleanos-en-info`; su
`fecha` se corrige al día de la fusión).

**Auditado.** En `BEGIN … ROLLBACK` con el Postgres local devuelto a su punto
de partida (los tres md5 coincidían con los vigentes): con la 0518 pasan las 12
pruebas que tocan bono o tablero (413 nueva con 19 aserciones, 377, 335, 376,
378, 123, 129, 131, 132, 307, 334, 389); sin ella fallan solo 413, 377 y 335,
las tres que codifican la regla nueva. La planilla de la practicante suma el
bono y EsSalud no se mueve (para practicantes la base es siempre el piso RMV).
Vitest de saludos y novedades en verde, typecheck en verde. Probado en el
navegador con cuentas locales: practicante → saludo + «Firmar mi bono de
cumpleaños · S/ 180.00»; en prueba → saludo sin botón. **La 0518 quedó
aplicada en el Postgres local compartido.**

**Pegada en producción el 2026-10-13**, con la comprobación entera en `true`
y el registro `518 · a_quien_le_toca_el_bono_de_cumpleanos_se_dice_una_vez`.
Antes de pegar se pidieron los tres md5 a producción: `fn_mi_bono_cumpleanos`
y `fn_documento_registrar` coincidieron exactos con la partida, y
`fn_documentos_tablero` **no coincidió con ninguno de los dos** que imprime
`donde-vive.sh` (`56aff7b1…` / `d138aae9…`). Se pegó igual, y DESPUÉS se midió
en el Postgres local con la 0492 dentro de `begin … rollback`:
`md5(replace(prosrc, chr(10), chr(13)||chr(10)))` da `56aff7b1…` y la misma
expresión «sin comentarios» sobre ese texto da `d138aae9…` — al carácter. Era
la 0492 pegada desde Windows (la causa de la 0401, ver CLAUDE.md): **mismo
código, nada revertido**. Lo que hay que aprender: ese desenlace no está entre
los tres que imprime el script, y por eso parece «otra versión»; queda pedido
que `donde-vive.sh` imprima también las dos variantes CRLF.

**La colisión, y la 0520 que la cierra.** Mientras esta rama se construía, otra
sesión (con Felipe) arregló el MISMO caso con la **0519** (PR #524, fusionado
el 2026-10-13 a las 17:30 UTC): practicante sí, pero **nunca a la boleta** (DO
le transfiere; su subvención no es remuneración, Ley 28518 art. 47) y sin
excluir prueba ni contratos cortos. Medido en local con las dos pruebas (413 y
414) en cada orden de pegado: **la 0519 no se puede pegar después de la 0518**
—su freno de md5 la rechaza—, y la foto de producción (`CAMBIO 0518` en las
tres puertas, nada en la firma) confirmó que **solo la 0518 está pegada**. Su
frontend sí se publicó: hoy la pantalla le dice al practicante «DO te lo
transfiere» mientras la base lo manda a la boleta.

Cayla decidió **unir las dos**. La **0520** es esa unión: una sola función
(`fn_persona_le_corresponde_bono`, el nombre de la 0519, el cuerpo de la 0518),
las tres puertas de la 0518 apuntando a ella, la `fn_confirmar` de la 0519 (el
practicante queda «pedido» y DO transfiere), y la función de la 0518 retirada.
Su freno exige exactamente el estado actual de producción. La 0519 queda en
`scripts/hooks/no-se-pegan.txt`; **la 0518 no se vuelve a pegar** (sus
`create or replace` devolverían las puertas a la función vieja).

**La 0520, auditada y pegada.** En `BEGIN … ROLLBACK` sobre el estado real de
producción (la 0518): con la 0520 pasan las 13 pruebas que tocan bono o tablero
(413 con 20 aserciones, 414 de main con 27, 377, 335, 376, 378, 123, 129, 131,
132, 307, 334, 389); sin ella fallan solo la 413 y la 414 (la función unida no
existe). Pegada dos veces: la segunda solo avisa. Sobre una base sin la 0518:
su freno para sin tocar nada. **Pegada en producción el 2026-10-13** con la
comprobación entera en `true` y el registro
`520 · el_bono_de_cumpleanos_una_sola_regla_y_el_practicante_cobra_por_transferencia`.

**La 0519, neutralizada.** Al subir la rama, `db-tests` cayó: una base desde
cero corre 0518 → 0519 → 0520, y el freno de la 0519 abortaba la construcción
entera («PARA. Producción no tiene el cuerpo…») — nadie habría podido levantar
una base local con esto en `main`. La 0519 conserva su encabezado (la decisión
de Felipe) y su fila (la prueba 122 la exige) y ya no ejecuta nada; su código
vive en git y lo que decidía lo trae la 0520. Reproducido en local dentro de una
transacción: 0518 → 0519 → 0520 deja exactamente el estado de producción, y las
pruebas 413, 414, 377, 335, 376 y 378 pasan encima.

**Queda:**
1. `db-tests` y `ui-tests` en verde en el PR #526, y fusionar (fusionar es
   publicar). Sin `--admin`.
2. Correr `scripts/sql-manual/diagnostico_bono_cumpleanos_daniel.sql` (solo
   lee): Daniel en `este_mes`, con firma guardada.
3. Si alguna practicante firmó entre la 0518 y la 0520, su bono está en una
   boleta: `select p.nombres, d.fecha_firma from documentos_firmados d join
   personas p on p.id = d.persona_id where d.tipo = 'bono' and
   p.tipo_vinculo = 'practicante' and d.movimiento_id is not null;` — y DO
   decide si lo deja ahí o lo quita de Planilla (vuelve a «pedido», 0479).

**Pendientes que esto dejó a la vista, sin tocar:**
- Los practicantes no tienen ningún documento con acuse que diga que les
  corresponde el bono: la Política salarial los excluye a propósito (Ley
  30709 no les alcanza, decidido el 2026-08-31) y el convenio de prácticas no
  lo menciona. El bono es una liberalidad y no exige papel, pero hoy la regla
  solo vive en el código. Si Cayla quiere dejarlo escrito, va en una adenda al
  convenio o en Normas, no en una novedad.
- Quien cumple años en prueba y pasa a planilla antes de fin de año queda en
  `vencido` y puede pedirlo entonces (comportamiento de la 0478, no de esta
  migración). Si debe perderse, es otra decisión.
- El tablero no lista a quien termina contrato este mes (0161), así que esa
  persona sigue sin poder pedir el bono desde Info aunque la regla nueva se lo
  dé: lo registra DO en papel, como hasta hoy.

---

> **Nota del mismo día, después:** esta 0519 **NO se pegó y ya no se puede pegar** — su freno de md5 la
> rechaza porque la 0518 llegó antes a producción (medido en local, y confirmado con los marcadores en
> producción). La sustituye la **0520** (sección de arriba), que une las dos decisiones. Está en
> `scripts/hooks/no-se-pegan.txt`. Lo que sigue vigente de esta sección: el frontend (publicado) y las
> preguntas legales abiertas.

---

## 2026-10-06 — El alta pide el documento, y cada documento dice de qué tipo es · migración 0513 · PEGADA Y VERIFICADA EN PRODUCCIÓN · SIN FUSIONAR (PR #508)

**Origen:** el alta no pedía el DNI, así que el índice único de documento (0125), el único freno exacto contra
registrar dos veces a la misma persona, nunca actuaba sobre un alta, y alguien llegó a escribir un DNI en el
apellido (0512). Decidido con Felipe: obligatorio en el alta y exigido por la base; tres tipos —DNI 8 dígitos,
carné de extranjería 9 a 12, pasaporte/PTP 6 a 12—; un documento repetido se niega diciendo quién lo tiene; el
aviso de nombre parecido (0506) se queda como segunda red; quien no tiene documento lo propone desde «Lo mío» y lo
aprueba DO (sin adjunto; si está repetido, no se le dice de quién).

**Hecho (en la rama):** `personas.tipo_documento` + `fn_documento_forma_valida` + candado
`personas_documento_coherente`; `fn_crear_persona` (11 args, `p_es_estacion` marca por `fn_set_cuenta_de_servicio`);
`fn_set_documento` con el tipo OPCIONAL AL FINAL —`fn_aplicar_cambio_perfil` la llama con 3—. Pantallas: Equipo,
Datos personales, «Lo mío › Editar», Bandeja. md5 de partida pedidos a producción: `fn_crear_persona` 50c42522…,
`fn_set_documento` 5f0863e0…, idénticos al repo. Prueba **407** (35) y 235/400/401/221/227/317/322 ajustadas.

**«Lo mío», dentro de la misma 0513:** fila `documento` en `catalogo_campos_perfil` (`solo_do`, sin adjunto),
`fn_crear_solicitud_perfil` (valida tipo y forma; «ya tienes uno» → es de DO; un número que ya es de otra persona se
rechaza SIN nombrarla) y `fn_aplicar_cambio_perfil` (aplica por `fn_set_documento`; si DO ya se lo cargó, la propuesta
quedó vieja y no se aplica). Prueba **410** (16). La 322 pasa de «un solo campo solo-DO» a «exactamente esos dos».
md5 de partida de producción: `fn_aplicar_cambio_perfil` fbcf2ac8… (6553) y `fn_crear_solicitud_perfil` 7a2f1dfe…
(2941) — **con `\r`: 119 y 68 retornos = su número de líneas**, medido que el repo con `\r\n` da ese md5 exacto
(la 0401 se pegó desde Windows). Benigno, pero la 0513 pegada desde la misma máquina los volverá a dejar con `\r`.

**Pegada el 2026-10-06 y verificada** en el SQL Editor. md5 de partida pedidos justo antes de entregar, los cuatro
idénticos a lo esperado (`fn_crear_persona` 50c42522… · `fn_set_documento` 5f0863e0… · `fn_crear_solicitud_perfil`
7a2f1dfe… y `fn_aplicar_cambio_perfil` fbcf2ac8…, estas dos con sus `\r`), 1 versión de cada una, `tipo_documento`
inexistente, 0405 y 0512 registradas. De llegada: las ocho comprobaciones en `true` y `513 · el_alta_pide_el_documento`.
Llegada (con `\r` en las dos de «Lo mío», por pegar desde Windows): `fn_crear_persona` dbabb62a… · `fn_set_documento`
6d70abe6… · `fn_crear_solicitud_perfil` 9d473d27… · `fn_aplicar_cambio_perfil` 4265b073….

**Ojo, hasta fusionar el PR #508:** Equipo ya no puede dar de alta con la pantalla vieja (la base exige el documento y
la pantalla vieja no lo manda): falla sin escribir nada. Fusionar publica; son dos pasos seguidos.

**CI:** `db-tests` falló en las pruebas 316 y 318, que contaban 12 campos en el catálogo y ahora son 13. Las dos pasan
con la 0513 y fallan sin ella. Lección: al sumar una fila a un catálogo, buscar TODAS las pruebas que lo cuentan, no
solo la que uno sabe que lo toca (se había ajustado la 322 y se escapó esto).

**Lo que enseñó medir:** (1) el candado dejaba pasar un tipo sin número: un `null` da «no sé» y un CHECK lo deja
pasar → `coalesce(…, false)`. (2) Quitarle a `authenticated` el permiso de la regla habría roto TODO update directo
a `personas` (el CHECK se evalúa con los permisos de quien escribe; desde la 0076 las funciones nacen cerradas) →
se abre a authenticated y service_role. Los dos los cazaron pruebas antes de pegar. (3) Al medir encadenando
migraciones, la 0501 y la 0502 traen su propio `begin/commit` y anulan el `rollback`: la base local compartida quedó
con datos de prueba y la 0513 aplicada; se limpió y se revirtió a mano.

---

## 2026-10-06 — El DNI no va en el nombre · migración 0512 · PEGADA Y VERIFICADA · FUSIONADO (#503)

**Origen:** una integrante apareció en todas las listas (y en el terminal de su sede) con su DNI pegado al apellido
corto. Ningún código lo pegó: se tecleó a mano en el alta. El alta no tiene campo para el DNI, y desde la 0506 un
nombre parecido pide confirmación; escribir el número es la forma «natural» de diferenciar a alguien. Tampoco servía
para frenar duplicados: el índice único mira `personas.documento`, no el apellido.

**Qué es:** la 0512 quita de `nombres`/`apellidos` toda secuencia de 6+ dígitos (NOTICE con a quién tocó y si tiene
el DNI cargado aparte) y agrega el CHECK `personas_nombre_sin_documento`. Se detiene sin tocar nada si a alguien le
quedaría el nombre vacío. Equipo frena lo mismo antes de escribir (alta y edición) con `avisoDocumentoEnNombre`
(`packages/shared/src/nombres.ts`, misma regla), y el aviso de parecidos dice que no hace falta agregar el DNI.

**Medido:** prueba **406** (8) en verde con la migración; sin ella falla 5 de 8. Siembra con un DNI inventado →
queda «Inventada Apellido»; repegada → 0 filas. Apellido = solo el número → se detiene. `tests/nombres.test.ts` con
los mismos casos.

**Cómo quedó:** el PR se fusionó ANTES de pegar (sin daño: la pantalla frena sola). La primera pegada se detuvo
sola —«le quedaría el apellido vacío»—: el número no iba pegado al apellido, ocupaba el campo entero (el apellido
estaba escrito en el del nombre). Se corrigió a mano en Equipo → Editar y la segunda pegada dio
`true | true | 512 · el_dni_no_va_en_el_nombre`. El freno de «nombre vacío» era justo para este caso: la suposición
de dónde estaba el número era falsa y la migración no la adivinó.

**Abierto:** el alta sigue sin pedir el DNI, que es el único freno determinista contra duplicados.

---

## 2026-10-05 — El filtro del terminal ilumina en vez de ocultar, y la pantalla se vuelve más quieta · SIN SQL · ESCRITO Y PROBADO · SIN COMMITEAR

**Qué cambia (sobre el PR #495, ya publicado).** Viendo el diseño en producción se
pidió algo más limpio: en una sede de 4 personas la leyenda era una fila de seis
botones casi toda en cero.
- La leyenda de botones sobre las tarjetas **se va**; en su lugar, una **píldora
  única** fina bajo el selector de sede (`PildoraDeEstados`). Los estados con cero
  personas no se dibujan.
- Tocar un estado **ilumina** (borde y tono del estado) a quienes lo tienen y
  **atenúa** al resto; ya **no oculta**. Se apaga a los 20 s (`SEGUNDOS_RESALTADO`)
  y al tocar un nombre o cambiar de sede. Al no ocultar, desaparece todo el
  andamiaje de «alto fijo para que el reloj no salte» y la línea «Mostrando N de M».
- Las tarjetas son **todas iguales** (papel, borde fino); el estado vive en el
  círculo de color de la esquina de la foto y en una línea gris con la hora.
- **El ícono de la foto solo informa**: no filtra, y tocarlo marca como tocar
  cualquier parte de la tarjeta (volvió a ser un solo botón). Se probó primero como
  control y se retiró a pedido.
- **Al pasar el mouse** por un ícono —el de la foto o el de la píldora— sale su
  significado (`ConEtiqueta`). Solo con mouse: en una pantalla táctil el toque
  dispara el mismo evento de «entrar» y la etiqueta quedaría pegada.

**Por qué la etiqueta vive en un portal.** Una tarjeta atenuada lleva `opacity-30`
y todo lo que cuelga de ella se atenúa con ella: justo la etiqueta del ícono de
quien NO está iluminado es la que más falta hace leer. Medido en el navegador:
opacidad 1 sobre una tarjeta atenuada.

**Lo que se probó, y lo que NO.** Pruebas nuevas de `contarPresencias` y del orden de
la píldora (`tests/presencia-casilla.test.ts`). En el navegador, con los
componentes reales: la píldora ilumina, tocar el ícono de la foto abre la
confirmación de marcar y no cambia el resaltado, la etiqueta sale con el mouse real
(`pointerType: mouse`) y no queda pegada tras tocar. **No** se probó en una
pantalla táctil real ni en el terminal de verdad (pide sesión de Supabase).

**Deuda anotada.** Los tokens `--color-azul` y `--color-ceniza` siguen en uso (pausa
y turno terminado) — se evaluó quitarlos con una versión «sin color» y se decidió
dejar el color.

---

## 2026-10-05 — El terminal muestra en qué punto del día está cada integrante · SIN SQL · ESCRITO Y PROBADO · FUSIONADO (PR #495) Y PUBLICADO

**Qué es.** En la pantalla de marcar, cada casilla dice si la persona está
*laborando*, *en refrigerio*, *en pausa* (trámite, médico, personal, otro),
con el *turno terminado* o *sin entrada*: ícono sobre la foto, tono de la
casilla y una línea con la hora. Bajo el reloj hay una leyenda con el conteo de
cada estado que también FILTRA (oculta a los demás; se quita sola a los 20 s y
al tocar un nombre). El reloj no se tocó.

**No hay migración.** El estado se DERIVA de los marcajes que el terminal ya
cargaba, y «entra 14:00» / «Libre hoy» salen de los `horarios_asignados` que
`sugerencias.ts` ya traía. Al ser solo frontend, **fusionar = desplegar**
(main se publica sola): no hay nada que pegar antes.

**Dónde vive.**
- `packages/shared/src/attendance-state-machine.ts` → `estadoPresencia()`. Misma
  lógica, rama por rama, que `determinarSiguienteAccion`; la prueba
  `tests/estado-presencia.test.ts` las cruza sobre ~22 000 secuencias de marcas y
  se comprobó que SÍ falla si una diverge (se rompió a propósito).
- `apps/web/lib/terminal/presencia.ts` → `presenciaDeLaCasilla()`: lo que dice la
  línea de cada casilla (función pura, probada en `tests/presencia-casilla.test.ts`).
- `apps/web/app/(terminal)/terminal/marcar/presencia-visual.tsx` → colores,
  íconos y la leyenda; `components.tsx` (casilla) y `page.tsx` (cableado).
- `globals.css`: dos tokens nuevos, `--color-azul` y `--color-ceniza` (ver CLAUDE.md).

**Tres decisiones que importan.**
1. **Sin estado confirmado, no se pinta nada.** Si el terminal no pudo leer las
   marcas de hoy (arranque sin red), un mapa vacío no significa «nadie entró»:
   las casillas se ven como siempre y no hay leyenda. Pintar a todos «sin
   entrada» sería acusar de más.
2. **La casilla dice la hora de la ENTRADA, no la del regreso.** «Desde 13:45»
   tras volver del refrigerio se leía como una llegada tardía. Ahora dice «entró
   08:02» y, aparte, «salió 13:00 · volvió 13:45» (el regreso se empareja con SU
   salida: con varias, la del trámite de la tarde y no la del refrigerio). Lo detectó quien probó el prototipo.
3. **Pasada su hora de entrada, la casilla NO dice «debía entrar».** Dice «aún sin
   entrada», igual que quien no tiene horario: la tardanza se mide en su reporte,
   no en una pantalla que ve todo el equipo.

**Para ver en la tienda.** Que el azul (en pausa) y el gris (turno terminado) se
distingan bien en la pantalla real, y que 20 s de filtro sea el tiempo justo (con
la tienda llena quizá convenga 10-15 s: es la constante `SEGUNDOS_FILTRO` de
`page.tsx`). La pantalla de marcar ya NO tiene ningún texto de instrucción.

---

## 2026-10-04 — El rastro de correcciones solo lo escriben las funciones · migración 0508 · PEGADA EN PRODUCCIÓN (registro 508, sin políticas de INSERT) · PR #491 (BORRADOR) SIN FUSIONAR

**LO QUE HAY QUE SABER PRIMERO (2026-10-04, medido en producción):** la 0508 **ya está pegada en producción**:
`migraciones_aplicadas` trae **508 · `0508_el_rastro_de_correcciones_solo_lo_escriben_las_funciones`** (número Y nombre) y de
la tabla solo quedan las tres políticas de lectura (`auditoria_select_admin_lider`, `_propia`, `_supervisor`); las dos de
INSERT ya no existen. Por eso todo lo medido antes allí sobre esta tabla —`anon` y `authenticated` sin INSERT, UPDATE, DELETE
ni TRUNCATE— es el estado POSTERIOR a la migración, y **no dice si el hueco existió en producción antes**: es desconocido. Dos
versiones de esta entrada lo leyeron como «producción ya venía cerrada, probablemente por un revoke manual»; era una lectura
sin respaldo, la misma trampa que dejó anotada la 0507 (una comprobación sin la fila del registro no distingue «antes» de
«después»), y yo no sabía que se había pegado. Lo mismo vale para `personas` y la 0507. El hueco SÍ existe en el repo y en
toda base construida de él (CI, local) hasta esta migración. Todo lo medido con `set role` más abajo es sobre la base
desechable.

**Origen:** al medir la 0507 (alta de personas solo por `fn_crear_persona`) salió un hueco hermano y más grave:
`correcciones_auditoria` —el rastro de toda edición manual, del que cuelgan el expediente disciplinario y el rastro de
planilla— aceptaba INSERT directo de cualquier admin, líder DO **o líder de equipo** (sobre alguien de su sede), con
`corregido_por` de OTRA persona y `corregido_at` de hace semanas. **Medido** (Postgres desechable con las 483 migraciones
de `main`, `begin … rollback`, `set role authenticated` + jwt): un `lider_do` inserta una fila a nombre de un admin y con
fecha de hace 40 días, y pasa. UPDATE y DELETE dan 0 filas (RLS sin política: única cerradura). Y **TRUNCATE como
`authenticated` vació la tabla entera**: RLS no gobierna TRUNCATE y los privilegios por defecto de Supabase se lo dan a 63
de las 91 tablas de `public` (entre ellas `marcajes`, `jornadas`, `periodos_planilla`). PostgREST no expone TRUNCATE, así
que por la API no se llega: es latente, no explotable hoy.

**Qué es:** `0508_el_rastro_de_correcciones_solo_lo_escriben_las_funciones.sql` borra las dos políticas de INSERT y
revoca INSERT, UPDATE, DELETE y TRUNCATE a `public`/`anon`/`authenticated` sobre la tabla. Solo lectura para toda sesión
de usuario. **No reescribe ninguna función**: no hay md5 de partida y no puede revertir el trabajo de otra sesión.
Idempotente (se repegó encima de sí misma en el desechable, sin error).

**La advertencia que NO se confirmó.** Se dio por cierto que revocar el INSERT rompería el cese de quien tiene educación
vigente, porque `fn_educacion_cerrar_al_cesar` (trigger AFTER UPDATE sobre `personas`) es la única de las 60 funciones que
escriben la auditoría que NO es SECURITY DEFINER. Medido, no rompe nada, por dos razones independientes: (a) el trigger solo
llega a su insert cuando cambian `estado`/`fecha_cese`, y eso solo lo puede hacer `postgres` (`fn_bloquear_cese_directo`,
0432, lo niega a cualquier otro) — los ceses reales pasan por `fn_cesar_persona`, DEFINER, y dentro de ella el trigger
corre como `postgres`; (b) aun con ese guardián apagado, el trigger ya moría antes, en su `update asignaciones_educacion`
(«permission denied»: `authenticated` solo tiene SELECT ahí), con y sin la 0508. Medido de punta a punta con la migración
puesta y la función SIN tocar: la asignación se cierra al cese y queda `educacion_cierre_por_cese`. Convertirla en DEFINER
«por si acaso» le habría dado a su `update` el poder de saltarse RLS, para cubrir un camino que no existe.

**Probado.** Prueba **402** (27 aserciones: estado, ataque desde lider_do / líder de equipo / admin / anon, UPDATE / DELETE /
TRUNCATE, `fn_set_rol` y el cese con educación vigente siguen vivos con `corregido_por` = quien actuó, y un CONTROL que
reabre a propósito). Sin la 0508 caen 14 (las cerraduras y el ataque) y pasan las 7 puertas oficiales; con ella, 27/27.
**Suite pgTAP entera, A/B en el mismo desechable** (control = la 0508 revertida con SU PROPIO bloque «cómo se revierte», y
la ACL y las 5 políticas comprobadas idénticas a `main`): 309 archivos; CON 3 520 ok / 55 not ok / 106 errores, SIN 3 506 /
69 / 106; **0 de 308 archivos difieren aserción por aserción** (el único que cambia es el 402). 19 archivos fallan en los dos
estados (línea base del desechable: `schema_migrations`, jwt/actas/configuración de documentos…); de esos, solo la **353**
toca la auditoría y solo para LEERLA (cuenta filas que escriben `fn_set_horario_semanal` y `fn_corregir_horario_retroactivo`,
ambas DEFINER de `postgres`): se rompe antes por el entorno, así que ese tramo queda cubierto por estructura y no por
medición. En el desechable se añadió `auth.users.email_confirmed_at` y un `storage` mínimo (receta de la memoria).

**Antes de pegar** (histórico: ya se pegó; el orden «pegar antes de fusionar» se cumple): tres consultas de solo lectura a producción,
escritas en el encabezado, con su resultado esperado — (1) las DOS políticas de INSERT y los privilegios de la tabla; (2)
que la ÚNICA función INVOKER que escribe la auditoría sea `fn_educacion_cerrar_al_cesar` y que NINGUNA actualice ni borre;
(3) que `trg_personas_cese_solo_por_rpc` exista y esté activo (`tgenabled = 'O'`) y que `authenticated` NO pueda hacer
UPDATE sobre `asignaciones_educacion`. Si la (2) devuelve algo más, parar: esa función dejaría de funcionar. No depende de
la 0506 (ya en `main`, #489; su `fn_crear_persona` es DEFINER y no toca la auditoría) ni de la 0507 (ya pegada en
producción y fusionada, #490): no toca sus funciones ni sus tablas; se probó sobre `main` + 0507 + 0508 (402, 401 y 388 pasan; suite entera con los mismos 19 archivos
rotos de la línea base). Commiteada y subida (PR #491, borrador). **Como ya está pegada, el PR puede fusionarse cuando Felipe quiera**: no cambia
pantallas (solo SQL, pruebas y notas), pero fusionar es publicar `main`.

**Resultado en producción (2026-10-04) — TODO medido DESPUÉS de pegar la 0508.** Registro: 507 y 508 con sus nombres exactos.
1a: la tabla tiene solo las tres políticas de lectura. B (privilegios autoritativos, con columnas): `anon` y `authenticated`
en falso para INSERT, UPDATE, DELETE, TRUNCATE e INSERT por columna. 3a: `trg_personas_cese_solo_por_rpc` activo
(`tgenabled = 'O'`). 3b: `authenticated` no actualiza `asignaciones_educacion`. 2a: UNA fila, `fn_educacion_cerrar_al_cesar`.
O sea: la migración hizo en producción lo que decía, y las premisas con que se escribió (el cese con educación no depende
del INSERT de `authenticated`) siguen cumpliéndose. **2b: vacía** (producción, 2026-10-04, captura del SQL Editor: «Success. No rows returned»): ninguna función, definer o no,
actualiza, borra ni vacía la auditoría, así que nada dependía de esos privilegios que la 0508 revocó. No se ejercitó un cese
real con educación vigente en producción: la evidencia es el catálogo y la prueba 402, no el uso.

**Lo que ese resultado NO dice, y una divergencia menor.** La primera consulta de privilegios (`authenticated = REFERENCES,
SELECT, TRIGGER`; `anon = REFERENCES, TRIGGER`) y la de «62 de 92 tablas con INSERT y TRUNCATE» se corrieron con la 0508 ya
pegada, así que no dicen cómo estaba antes; la lista de las 62 SÍ trae `marcajes`, `jornadas`, `periodos_planilla`,
`expediente_disciplinario`, `liquidacion_pagada`, `planilla_pagada_detalle`, `movimientos_planilla`, `asignaciones_salario`,
`datos_personales`, `politica_salarial`… y no trae `correcciones_auditoria` (explicado por la 0508) ni `personas` (la 0507
solo revoca INSERT, así que su falta de TRUNCATE no viene de ella: ACL `rwdxtm`, origen no investigado). Lo único que la 0508
no explica es que `anon` tampoco tenga SELECT sobre la tabla (la migración no se lo quita y el repo se lo da): una divergencia
de privilegios por defecto, sin efecto sobre la escritura.

**Abierto — otras tablas con escritura directa (reportado, NO tocado; decide Felipe).** **Las seis tablas de esta lista SÍ
están en la lista de las 62 con TRUNCATE de producción**, o sea con los privilegios por defecto; que tengan también INSERT
para `authenticated` no se verificó tabla por tabla (62 y 62 no prueban que sean las mismas), pero es lo que cabe esperar.
Es la parte de este informe con exposición plausible en producción, y la de más consecuencia.
**Actualización: la 0509 (en `main`, SIN PEGAR, entrada de arriba) midió estas mismas tablas por su lado y cierra
`rendimiento_mensual`, `terminales` y `tarifas_hora`;** `configuracion` queda como decisión de Felipe y `documentos_tipos` se
deja (la pantalla Normas inserta directo: es la puerta oficial); `push_tokens` es solo la fila propia. Lo que sigue es el
análisis original de esta entrada, anterior a la 0509.
- **`rendimiento_mensual`** (el bono por rendimiento): política `for all` a admin/líder, y su guardián
  `fn_set_rendimiento`/`fn_quitar_rendimiento` (0111) se salta. **Medido** con un periodo pagado: la función dice «La planilla
  de ese mes ya está PAGADA» y el upsert directo del `lider_do` PASA sobre ese mismo mes, con `puesto_por` de otra persona.
  Los CHECK de rango y la FK de etiqueta sí valen directo; lo que se salta es el candado del mes pagado y el firmante. La app
  no la escribe directo: es la candidata natural a un tratamiento como el de la 0507.
- **`configuracion`**: política `for all` a admin/líder. La única función que la escribe es `fn_educacion_configurar` (rangos
  0–20 y 0–30 días), y `valor` es jsonb sin constraint: un upsert directo se salta esos rangos. Las claves que mueven plata
  —`planilla_provisiones`, `asignacion_familiar`, `bono_puntualidad`, `movilidad_diaria`, `liquidacion_incluye_variables`— no
  tienen guardián NI rastro (solo 3 triggers: `gerencia_general`, firmante de empresa y `tasa_afp`). Ojo: la app SÍ escribe
  directo `apariencia_tema` (`admin/apariencia/page.tsx:75`), así que no se puede cerrar «a lo 0507» sin antes mover esa clave
  a una función.
- **`tarifas_hora`, `terminales`, `documentos_tipos`, `push_tokens`**: ninguna función las escribe, así que no hay guardián
  que saltar; la decisión es si deben ser solo-RPC. `documentos_tipos` la escribe la app directo (`admin/normas/page.tsx:479`);
  `push_tokens` está acotada a la fila propia.
- **TRUNCATE (e INSERT) a `authenticated` en 62 de las 92 tablas de producción** (63 de 91 en el desechable; herencia de los
  defaults de Supabase). **Medido tabla por tabla en producción (2026-10-04, TRUNCATE):** están `marcajes`, `jornadas`,
  `periodos_planilla`, `expediente_disciplinario`, `liquidacion_pagada`, `planilla_pagada_detalle`, `movimientos_planilla`,
  `asignaciones_salario`, `datos_personales`. No alcanzable por PostgREST: es un privilegio sin cerradura, no un hueco que se
  ataque hoy por la API. Es decisión de Felipe si se revoca en bloque (una migración con un `revoke truncate` sobre las tablas
  append-only) o no se toca.
- **`respaldo_horarios_chiara_20260814` está en producción y no en el repo** (solo en `scripts/sql-manual/restituir_horario_de_chiara.sql:67`,
  `create table … as select`, que no activa RLS ni pone grants propios): es la tabla extra que explica 92 contra 91. Está en
  la lista de las 62, o sea con los privilegios por defecto. **Verificado en producción (2026-10-04): `relrowsecurity = true` y
  `anon` NO la lee — no hay nada que arreglar.** Un `create table … as` no activa RLS, así que alguien se la puso (o el proyecto
  la activa solo en tablas nuevas). Lo que NO se miró son sus políticas: con RLS y sin políticas queda cerrada para
  `authenticated`; una política permisiva la abriría. Borrarla es decisión aparte: es dato. La primera versión de esta entrada
  la daba por posiblemente abierta: era una suposición sin medir, y la medición la desmintió.

**No probado:** nada contra producción (ninguna consulta se corrió allá); el ataque se midió con `set role` + jwt en SQL, no con
una petición HTTP real a PostgREST (es la misma mecánica, pero no se ejecutó); los 19 archivos rotos de la línea base (acotados
a la 353); la pantalla de Correcciones, que solo LEE la tabla (se comprobó por búsqueda en el código, no abriéndola).

---


---

## 2026-10-04 — Tres tablas que solo se escriben por sus funciones · migración 0509 · ESCRITA Y PROBADA · SIN PEGAR · SIN FUSIONAR

**Origen:** al cerrar la puerta de `personas` (0507) se midió que otras cinco tablas admitían INSERT directo de admin o
líder DO, y se pidió medir cuáles tienen un guardián que esa puerta se salte. Esta es la lista, con jwt de un `lider_do`
en el esquema completo de `main` (484 migraciones, `begin … rollback`):

| Tabla | Quién escribe hoy con sesión | Guardián | Veredicto |
|---|---|---|---|
| `rendimiento_mensual` | nadie (ninguna pantalla llama a `fn_set_rendimiento`) | las dos funciones: rol, mes **no pagado**, catálogo | **se cierra (0509)**: el insert directo en un mes pagado PASABA |
| `terminales` | nadie (la app solo la lee; los scripts usan `service_role`) | ninguno | **se cierra (0509)**: un `lider_do` se registró como terminal y marcó la entrada de OTRA persona, sin PIN y sin rastro |
| `tarifas_hora` | nadie; nada la lee; 0 filas | ninguno | **se cierra (0509)**, sin consecuencia hoy |
| `configuracion` | la app, una sola clave (`apariencia_tema`) | 3 claves con trigger (`gerencia_general`, `firmante_empresa`, `tasa_afp`); **11 sin ninguno**, incluidas las de plata | **NO se toca: decisión de Felipe** (abajo) |
| `documentos_tipos` | la pantalla Normas inserta directo | ninguno | se deja: la puerta directa ES la oficial |

**Qué es la 0509:** molde de la 0507 — quita las políticas de escritura y revoca INSERT/UPDATE/DELETE a `authenticated`,
`anon` y `public` en las tres; conserva la lectura como estaba (en `tarifas_hora` la única política era `FOR ALL`, así que
se repone como SELECT **antes** de quitarla). **No reescribe ninguna función → no hay md5 de partida.** Antes de tocar
nada comprueba que ninguna función que no corra como su dueño escriba en ellas, y si la hay se niega a correr y la
nombra (probado en los dos sentidos: se niega ante una `invoker`, deja pasar a una `definer`). La fila de
`rendimiento_mensual` fija el porcentaje del complemento que paga el núcleo de planilla; quitarla SUBE el pago.

**Antes de pegar:** una consulta de solo lectura, ya escrita en la cabecera de la migración (con la fila del registro,
para que «antes» y «después» no se confundan). Esperado: el registro no tiene 509, una política `[*]` por tabla,
ninguna fila en «escriben sin ser definer». Después de pegar: el `select` final da **siete** `t`, y el registro tiene
`509 · 0509_tres_tablas_que_solo_se_escriben_por_sus_funciones`.

**Cómo se ensayó (y qué NO se pudo ver):**
- Prueba **403** (27). Sin la migración cae 15 de 27, y cada caída tiene su causa en el hueco; los 12 que pasan son los
  de «sin romper lo viejo». Con ella, 27/27. Idempotente; el bloque «cómo se revierte» revierte de verdad.
- Suite pgTAP entera, con y sin la 0509: 309 archivos comunes con las **mismas aserciones una a una** (3 511 → 3 538 =
  +27 de la 403). Los mismos 19 archivos de entorno fallan de los dos lados (el desechable no los puede ejecutar bien;
  no son evidencia sobre la 0509). Barrido estático: de 309 archivos, 23 escrituras en estas tablas y todas como
  `postgres`. Ninguna prueba existente llamaba a `fn_set_rendimiento`: ahora tiene cobertura.
- **No se midió producción.** Falta correr la consulta previa allá. Con `personas` coincidió con el repo; con estas tres
  no se sabe.

**`configuracion` — decisión de Felipe, no técnica:** hoy cualquier admin o líder DO puede cambiar las constantes de
planilla (`movilidad_diaria` pasó en la medición; `planilla_provisiones`, `asignacion_familiar` y `bono_puntualidad`
tampoco tienen trigger) sin dejar rastro. Las reglas de planilla se consideran decididas y en los hechos solo cambian por
migración. Si esa es la intención, lo coherente es un trigger por clave como el de `gerencia_general`. No se cierra la
tabla entera porque `apariencia_tema` se escribe legítimamente desde la app.

---

## 2026-10-04 — Un alta que se parece a alguien ya registrado pide confirmación · migración 0506 · PEGADA Y VERIFICADA · SIN FUSIONAR

**Origen:** una persona quedó registrada dos veces en Equipo, el mismo fin de semana, una con el nombre corto y otra con
el completo; las dos activas, con su PIN y visibles en el terminal de su sede. Ni el índice único de documento (0125)
ni el del correo podían verlo: **el alta no captura el DNI**, y dos escrituras distintas de un nombre no chocan contra
ninguna restricción. La causa de que se repitiera el alta, además: el formulario mostraba **Cargo y Tipo de vínculo**
pero `crearPersona` nunca los mandaba, así que la fila nueva salía «Sin cargo» y lo natural era volver a registrarla
(y quien elegía «Practicante» o «Recibo por honorarios» quedaba en «Planilla» sin enterarse).

**Qué es:** `fn_crear_persona` se niega —`raise exception`, hint `persona_parecida`— si el nombre se parece al de alguien
ya registrado, **activo o ya salido**, salvo que quien da de alta pase `p_confirmo_distinta = true`. La regla compara por
palabras (sin tildes, sin partículas; campo por campo sin contradicción, campos cruzados, contención, y un tipeo de una
letra en palabras de 5+): no avisa por compartir solo el nombre de pila ni solo un apellido. `fn_personas_parecidas` deja
a la pantalla preguntar **a quién** se parece antes de escribir nada, y Equipo muestra un aviso con «Ver en la lista».
Un `pg_advisory_xact_lock` pone en fila a dos altas simultáneas. El alta ya no pide Cargo ni Tipo de vínculo.
La firma cambia de 7 a 8 argumentos: **`drop function` de la vieja**, o `create or replace` dejaría dos y la llamada
quedaría ambigua (la 0297/0299 y la 0367).

**Medido:** prueba **400** (29): 66 casos de nombres, el guardián, los permisos y una sola versión de la función; se
comprobó que **falla** con el guardián apagado y con cuatro mutaciones (rama (c), sin NFC, confirmación NULL, sin tope).
Dos altas simultáneas del mismo nombre dejan **1** fila con el candado y **2** sin él (dos sesiones reales). Las pruebas
235, 250 y 159 pasan igual con y sin la migración. Revisión adversarial con verificador escéptico por hallazgo: ninguno
bloquea; se aplicó el tope de 120 caracteres (la comparación es cuadrática), NFC, la exclusión de estaciones de retail y
el aviso que se desplaza hasta la vista.

**Pegada el 2026-10-04 y verificada** en el SQL Editor. md5 de partida (pedido a producción justo antes) `143a698a…`
(2050 caracteres, 0 retornos, **1 versión**: idéntico a la 0300 del repositorio); de llegada: `versiones = 1`, guardián
adentro, `anon` no puede ejecutarla, la regla responde y md5 `50c42522550d7827969efbbdc7472268`, idéntico al medido en el
Postgres local y en una base desechable construida desde cero. **Va ANTES de fusionar el PR de la pantalla**: si el PR
llega a `main` primero, Equipo no puede dar de alta a nadie (falla cerrado, con «falta aplicar una migración»).
Después de pegarla: `scripts/sql-manual/pares_ya_registrados.sql` (solo lectura) para ver qué otras parejas ya están
registradas dos veces; nadie lo había medido. Con la 0507 (la entrada de abajo) no chocan: esa no reescribe la función.

**Abierto:**
- ~~El INSERT directo a `personas` se salta todo esto~~ — **cerrado por la 0507** (entrada de abajo): sin política ni
  privilegio de INSERT para `authenticated`, la única entrada es `fn_crear_persona`.
- `fn_reactivar_persona` no mira si ya hay otra persona activa parecida. Y cambiar el nombre en «Editar» no pasa por
  la regla.
- **El alta no captura el DNI**: es el único freno determinista (el índice único), y la regla de nombres no ve a dos
  registros que no comparten ninguna palabra (~7.5 % de las parejas en la simulación).
- `personas.fecha_ingreso` nace con `current_date` en UTC: quien se da de alta pasadas las 19:00 de Lima queda con ingreso
  al día siguiente.
## 2026-10-04 — Dos nombres, cada uno en su sitio · SIN MIGRACIÓN · FUSIONADO (#492) y visto en producción

**Origen:** a cada integrante se le carga «un nombre y un apellido por practicidad» (`personas.nombres/apellidos`,
lo que se ve en el terminal) y eso confundía: el formulario de Equipo los llamaba «Nombres» y «Apellidos», como si
fueran los del DNI. El nombre completo ya existía (`datos_personales.nombre_dni`) y Contratos, el memo y «Lo mío» ya
lo usaban; la boleta y los papeles de cese seguían imprimiendo el corto.

**Qué es:** nada de esquema. `packages/shared/src/nombres.ts` dice una vez qué nombre va en un papel
(`nombreOficial`: el del DNI, o el corto si falta; un `nombre_dni` de puros espacios cuenta como faltante). Lo usan
la **boleta** (admin y «Lo mío»; también el nombre del PDF), el **certificado de trabajo**, la **constancia de cese** y
la **firma de quien certifica por CAYLA**. En Equipo los campos pasan a «Nombre corto» / «Apellido corto» con la
aclaración de dónde va el nombre completo. **El terminal no cambia** y una prueba (`tests/nombres.test.ts`) vigila
que nunca lea `datos_personales`. Si falta el nombre del DNI, el certificado y la constancia lo avisan en la vista
previa (no se imprimen en silencio: una vez entregados no se corrigen).

**Decidido a propósito — qué NO se tocó:** `fn_planilla_calcular` y `fn_proyeccion_periodo` siguen armando
`'nombre'` como «nombres apellidos» (es la función de pago; la boleta lee el nombre del DNI aparte, como ya leía
`documento`). `fn_papeles_cese` (0400) igual: su campo `nombre_completo` sigue siendo el corto y la pantalla de
Liquidaciones lo reemplaza al cargar. Si algún día se reescribe cualquiera de las dos por otra razón, conviene
arreglarlo en origen.

**Abierto:**
- ~~Las constancias de recepción de **Normas** y de **Política salarial** imprimen «Apellidos, Nombres» del corto.~~
  **Resuelto en el PR siguiente** (rama `claude/constancias-nombre-completo`): la lista sigue ordenada por el
  nombre corto de nómina —`nombre_dni` es texto libre y su orden de palabras varía de una persona a otra— y bajo
  cada nombre figura el completo del DNI. Si falta, la pantalla lo cuenta (solo en pantalla); si la lectura
  falla, se nombra y se apaga «Imprimir».
- Unas diez pantallas escriben a mano `ficha?.nombre_dni || nombre` (contratos, memo, firma, movilidad, cumpleaños…).
  Funcionan; no se migraron al helper en este lote.
- **El dato, no el código:** `nombre_dni` se teclea a mano y nada lo compara con el DNI. Quien no tiene ficha
  todavía (el panel de Datos personales la lista «sin ficha») imprime con el corto. Medido en producción el
  2026-10-04: **1 de 26** activos tiene `nombre_dni` vacío.

---

## 2026-10-04 — El alta de una persona solo entra por fn_crear_persona · migración 0507 · PEGADA Y VERIFICADA · FUSIONADA (PR #490)

**Origen:** dos revisiones independientes señalaron que la política `personas_insert_admin_lider` (0003) y el INSERT que
la 0004 le dio a `authenticated` dejan a un admin o líder DO insertar en `personas` directo por REST, sin pasar por
`fn_crear_persona`. La 0300 decía que esa función es «la única puerta de alta del sistema»: lo era de la app, no de la base.

**Medido, y el hueco es real de punta a punta** (Postgres desechable con las 483 migraciones de `main`, `begin … rollback`,
jwt de un `lider_do`): `fn_crear_persona(…, 'admin', …)` → «No puedes crear una persona con un rol igual o superior al
tuyo»; el mismo admin con un `insert` directo → pasa. Atado a otra cuenta de acceso, esa cuenta entra con
`fn_rol_actual() = admin` y usa `fn_set_rol` como admin legítimo. Los triggers de rol, sede, pensión y PIN son todos
BEFORE UPDATE: el INSERT no los dispara. El único trigger de INSERT sobre `personas` es el de la 0490 y solo mira
`cuenta_de_servicio` — corrige una premisa del encargo («no hay ninguno»), que salía así solo porque la base local no
tenía la 0490.

**Qué es:** la 0507 quita la política, revoca el INSERT de `personas` (a `public`, `anon` y `authenticated`) y el de la
vista `retail.personas`, que es insertable y es la misma tabla por otro mango (hoy no sirve para dar de alta, por
`nombres NOT NULL`; se salva solo por `security_invoker = true`). **No reescribe ninguna función → no hay md5 de partida.**
`fn_crear_persona` sigue insertando porque es `SECURITY DEFINER` y su insert corre como su dueño. Prueba **401** (17); la
**388** cambia de 17 a 18 (el insert directo ahora muere en el privilegio, y la mitad INSERT del trigger de la 0490 pasa
a defenderse con `service_role`, que conserva su INSERT).

**Por qué un revoke y no un trigger** (el molde de la 0296/0342/0490): ese molde existe porque en UPDATE el privilegio no
se puede revocar sin dejar sin escribir las demás columnas. En INSERT nadie legítimo escribe directo, y lo que se puede
borrar se borra. Un trigger «todo lo que no sea postgres» además frenaría a `service_role` (`setup-personas-prod.mjs`,
`seed-dev.mjs`). Quién inserta hoy con sesión de usuario: **nadie** — `apps/web`, `packages/`, `cayla-retail` (seeds como
postgres y un fixture propio) y las migraciones (las cuatro versiones de `fn_crear_persona`, todas definer) se revisaron.

**Pegada el 2026-10-04 y verificada en producción** (SQL Editor). El `select` final de la propia migración dio las seis
columnas en `true`. El registro tiene **507 · `0507_el_alta_de_una_persona_solo_entra_por_fn_crear_persona`** (el nombre
guardado lleva el prefijo `0507_`, como la 0296 y la 0300; las anteriores a la 0505 no). Estado medido después: RLS
activa en `personas`; `authenticated` con SELECT, UPDATE y DELETE pero **sin INSERT** (`authenticated=rwdxtm`);
`anon` sin INSERT; **0** políticas de INSERT o ALL; `service_role` y `postgres` conservan su INSERT; una sola función
inserta en `personas` y es `fn_crear_persona` con `prosecdef = t`. **`retail.personas` NO existe en producción** (el
esquema `retail` sí): la parte de la vista fue un no-op ahí, y la puerta de la vista nunca estuvo abierta en producción.
No hay md5 de partida porque no se reescribió ninguna función.
**Fusionar es publicar `main`, pero este PR no cambia ninguna pantalla:** solo SQL, pruebas y esta nota. Ya no hay
nada que pegar antes. **Dueño de `fn_crear_persona` verificado en producción:** `postgres`, `prosecdef = t`, y su dueño
puede insertar en `personas` — por eso el alta por la función no se ve afectada por el revoke. Lo que NO se ejercitó es
un alta real en producción (no se crea una persona de prueba allá); la evidencia es el catálogo, no el uso.

**Cómo se ensayó (y qué NO se pudo ver):**
- Control: la 401 SIN la migración cae 10 de 17; con ella pasa 17/17. Idempotente (se pegó dos veces) y el bloque «cómo
  se revierte» de la cabecera revierte de verdad (se probó).
- Suite pgTAP entera en el desechable, con y sin la 0507: 308 archivos comunes idénticos (3 427 → 3 445 aserciones =
  +1 de la 388 y +17 de la 401). Fallan los mismos 20 archivos de los dos lados, aserción por aserción; 11 se caen por
  `auth.users.email_confirmed_at`, que la imagen no trae — con la columna añadida corren más y siguen idénticos. Esos 20
  no son evidencia sobre la 0507: son el límite del desechable. Lo acota un barrido estático — de 308 archivos, solo la
  388 inserta en `personas` como `authenticated`.
- Convive con la 0506 (rama sin fusionar) en los **dos** órdenes: 400 (29/29), 235 (5/5), 401 (17/17), 388 (18/18).
- **Antes de pegar no se midió producción:** el hueco se midió en el esquema que construyen las migraciones, no allá, y
  no hay forma de saber ahora si alguna vez estuvo abierto en producción (la primera consulta de comprobación se
  corrió ya con la 0507 pegada, y se leyó mal como «producción ya venía sin el hueco»; el registro con 507 lo aclaró).
  Tampoco se sabe si el registro de cuentas está abierto allá (`enable_signup` es un ajuste del panel de Supabase; en
  el `config.toml` local está en `true`): si lo está, la cadena de arriba no necesita ni una cuenta cómplice previa.
  La lección para la próxima: **una consulta de «antes de pegar» debe incluir la fila de `migraciones_aplicadas`**, o
  su resultado no dice si es «antes» o «después».

**Abierto:**
- **`correcciones_auditoria` admite INSERT directo de admin, líder DO y líder de equipo** (0003:227/231), sin trigger.
  Medido: un `lider_do` inserta una fila con `corregido_por` = un admin y `corregido_at` de hace 40 días, y pasa. Es la
  tabla del rastro de toda edición manual. Ojo antes de revocar: `fn_educacion_cerrar_al_cesar` la escribe sin ser
  `SECURITY DEFINER` (se rompería el cese). Lanzado como tarea aparte; el registro de producción ya muestra la
  **0508** (`el_rastro_de_correcciones_solo_lo_escriben_las_funciones`), de esa otra sesión — su estado lo documenta ella.
- Otras cinco tablas admitían INSERT directo de admin/líder (`configuracion`, `documentos_tipos`, `rendimiento_mensual`,
  `tarifas_hora`, `terminales`; `push_tokens` es solo la fila propia y `horarios_asignados` ya tiene trigger). **Medidas
  el 2026-10-04: ver la entrada de la 0509, arriba.**
- `donde-vive.sh` toma el primer contenedor `supabase_db_*`; con retail y dynamic arriba toma el de retail y avisa
  «la función no existe en el Postgres local» sin que sea cierto. No se tocó.

---

## 2026-10-02 — El feriado posterior al cese no corresponde · migración 0505 · PEGADA Y VERIFICADA · SIN FUSIONAR

**Origen:** Planilla del periodo 29-sep → 28-oct mostraba «1 feriado(s) sin salario ese día: no se pudo calcular ·
Equipo →» a dos personas que cesaron antes del 8-oct (una practicante y una integrante en planilla). Medido en
producción con la propia función: tramos cerrados el día del cese, `sin_salario = true`, `monto = 0`. La plata estaba
bien; el aviso era falso, y su enlace invitaba a reabrir el salario — `fn_set_salario` no mira el cese, y con eso el
feriado SÍ se pagaba (S/ 14.41 medido en la prueba 399).

**Decisión de Felipe (2026-10-02): el feriado posterior al cese NO se paga.** El sistema tenía dos respuestas: S/ 0 con
la baja por el botón (todos los casos reales) y «saldo legítimo» en la 0244 / prueba 185 (cese puesto a mano). Gana la
primera: art. 8 D. Leg. 713 («los trabajadores»), la liquidación ya corta en el cese, y es lo que producción pagaba.

**Qué es:** `fn_feriado_devengado_nucleo` pregunta «¿seguía vinculada ese día?» antes que el salario. Un feriado
posterior al cese pasa a «no corresponde», paga 0 aunque el tramo siga abierto, y deja de contar como «sin salario».
El detalle gana `despues_cese`; la pantalla dice «no corresponde (posterior al cese)». Prueba **399** (15; contra la
0397 caen las 9 previstas). La **185** cambia su montaje de § 11 al «marcaje cerrado tarde» (sigue 51/51). Suite
entera en base desechable: idéntica antes y después en los 306 archivos previos.

**Pegada el 2026-10-02 y verificada** en el SQL Editor: md5 de partida `c2cddb1d…` (9 312) idéntico al repositorio;
de llegada `82178e23…` (10 344), idéntico al de la base desechable; `migraciones_aplicadas` con **505 ·
el_feriado_posterior_al_cese_no_corresponde** (número Y nombre); los dos casos reales pasan a `sin_salario = false`,
`despues_cese = true`, `monto = 0`. Se pegó desde el portapapeles de `dame-el-sql.sh`, idéntico byte por byte a GitHub.
Falta fusionar el PR #486, que es publicar la pantalla («no corresponde (posterior al cese)»).

**Abierto:**
- El candado de `fn_set_salario`: deja asignar salario a quien ya cesó, y con la fecha que propone Equipo (inicio del
  periodo) BORRA los tramos reales que empiezan después. La baja ya se niega a lo inverso (0176). Migración chica.
- **El vínculo no tiene historia.** `fn_reactivar_persona` (0327) pone `fecha_cese = null` y conserva el ingreso
  original: tras un reingreso el sistema cree que la persona nunca se fue. Si alguien cesa el 2-oct y vuelve el 20-oct
  del mismo periodo, el 8-oct vuelve a estar «vinculada» y con el salario cerrado: regresa el aviso falso, y si alguien
  le pone salario, se paga un feriado de cuando no trabajaba. Afecta a la 0505 y a las cinco preguntas iguales del
  núcleo (tope de pago y las cuatro ausencias de la 0418). La solución de fondo es una historia de vínculos (como las
  «medidas» de SAP); tocaría el núcleo de planilla, así que se decide después del cierre de octubre.
- Los comentarios de `fn_periodo_pagado` (0244 y copias) siguen citando el feriado posterior al cese como saldo
  legítimo: desde la 0505 ese ejemplo es falso.

---

## 2026-10-01 — La subvención pactada de los practicantes sigue a la RMV nueva · migración 0502 · PEGADA Y VERIFICADA · PR #480 SIN FUSIONAR

**Estado al 2026-10-01, a mediodía — lo que de verdad pasó en producción:** Felipe pegó la 0502 y la fila final que devolvió coincide columna por columna con lo esperado: `tramos_0502 = 5` · `practicantes_bajo = 0` · `por_suposicion = 5` (ninguno tiene horas cargadas: la jornada completa de su modalidad se SUPUSO) · `con_horas_de_convenio = 0` · `educacion_realineada_hoy = 0` · registro `502 la_subvencion_pactada_de_los_practicantes_sigue_a_la_rmv_de_1230`. **Pendiente de la pegada:** volver a correr la consulta de comprobación y mirar que ningún practicante quede bajo el piso. **Lo que sigue abierto y NO lo resuelve la migración:** la consulta al laboralista de abajo (art. 45 con pago por horas; ningún convenio firmado en el sistema; adenda o renovación). Fusionar este PR no cambia pantallas: solo deja en `main` el archivo ya pegado.

**Origen.** La 0501 —la RMV a S/ 1,230, **pegada y verificada** el 1-oct— no alcanza a los practicantes:
`fn_fijar_base_declarada` exige `en_planilla` y ellos tienen `en_planilla = false`. En producción hay **cinco
practicantes activos** (tres profesionales y dos preprofesionales) cuya subvención pactada es S/ 1,130 y desde el 1-oct
queda **bajo la RMV** (Ley 28518 art. 45: no menos de una RMV a la jornada máxima de su modalidad; proporcional
si pactaron menos). **Lo decidido por Felipe (2026-10-01):** llevar esa subvención pactada a S/ 1,230 desde el 1-oct,
**por regla** y sin nombres ni ids en ningún archivo, con una migración **aparte** de la 0501.

**Qué promete —y qué NO— esta migración.** Promete alinear **lo pactado** (el tramo vigente de `asignaciones_salario`: lo
que Contratos exige y lo que imprime la constancia) a la RMV. **No promete que la boleta pague esa cifra ni que se
cumpla el art. 45**: la planilla paga a un practicante por las horas marcadas, y un preprofesional que cumple sus 30 h
semanales cobra ≈ dos tercios del tramo (ver «Lo que la 0502 NO resuelve»). Por eso el nombre dice «sigue a la RMV» y no
«llega al piso», y la nota permanente de cada tramo no afirma cumplimiento. *(La primera pasada se llamaba «los
practicantes llegan al piso»: prometía de más y se renombró.)*

**Qué hay** (rama `claude/practicantes-piso-0502`; **nada pegado ni fusionado**):

| Archivo | Qué |
|---|---|
| `supabase/migrations/0502_la_subvencion_pactada_de_los_practicantes_sigue_a_la_rmv_de_1230.sql` | La migración. Atómica, solo sube, idempotente, con guardia final y **una sola pegada a la vez** (candado de transacción). No reescribe ninguna función ni deja ningún objeto permanente. **Devuelve al final UNA fila** con los conteos. |
| `supabase/tests/396_la_subvencion_pactada_de_los_practicantes_sigue_a_la_rmv_de_1230.test.sql` | 48 aserciones: la regla sobre una veintena de practicantes de laboratorio (convenios en conflicto incluidos), la acción, la planilla (1,220.32), el tramo que empieza el 1-oct, el candado por grupo. |
| `scripts/sql-manual/antes_de_pegar_la_subvencion_de_los_practicantes_1230.sql` | Solo SELECT. 16 filas; la **fila 6** es una entrada por practicante y es lo que Felipe confirma. |
| `tests/practicantes-subvencion-misma-regla.test.ts` | Compara, palabra por palabra, la regla de la migración, de la prueba y del script. |

### La regla — y por qué no es «por rango»

Se sube a quien cumpla **todo**: practicante **activo**, no cuenta de servicio, con subvención vigente **por debajo de
su referencia**. La referencia es la **RMV vigente el 1-oct, leída de `parametros_laborales`** (no escrita a mano; la
migración se detiene si no es 1,230, o sea si la 0501 no está) y, solo para un **preprofesional con convenio de menos de
30 h**, su proporción: RMV × horas / 30 (la misma cuenta del generador de Contratos). **Nunca por rango:** cada
practicante lleva uno de los seis rangos de `asignaciones_salario` —no existe un rango «practicante»—, así que un
`UPDATE` o un `fn_fijar_base_declarada` por rango habría barrido también a quien pactó menos horas, y subirle de más no
se puede deshacer (sería **bajarle** una subvención).

**Qué convenios cuentan.** Todo convenio de prácticas **no anulado que traiga horas, firmado o en borrador**: equivocarse
hacia «protegerlo» se arregla pegando de nuevo; subir de más no. Si una persona tiene convenios no anulados que **se
contradicen** —horas distintas entre sí, o uno con horas y otro sin ellas— la migración **se DETIENE** con «conflicto de
convenios» y Felipe decide a mano (anular en Contratos el que sobra). La primera pasada tomaba «el más reciente»: con un
convenio **firmado de 20 h** y un borrador posterior sin horas, dejaba a esa persona «asumida» y la **subía a 1,230**
(ensayado contra el borrador commiteado: sube); y al revés, un borrador sin firmar con 20 h la dejaba «no se toca» sin
decirlo. Ahora la fila 6 muestra por persona cuántos convenios hay, sus horas y si están firmados.

Lo que hace: `fn_set_salario` por persona, **con el rango que ya tiene**, desde el **1-oct** (el tramo viejo se cierra
el 30-sep), y sube `personas.sueldo_base_legal` solo si ya tenía un valor menor (nulo se queda nulo) —no mueve el pago
de un practicante, pero la constancia de subvención imprime «Subvención pactada (mes completo)» **leyendo esa
columna**—. El valor anterior queda en `correcciones_auditoria` (`personas.sueldo_base_legal`), que es lo que permite
revertirlo, y el motivo dice **el valor real** al que sube (el proporcional, si pactó menos horas; la primera pasada
decía siempre «sube al piso de la RMV de S/ 1,230»). **Solo sube:** a quien ya cobra su referencia o más (1,230 o 1,300) no
se le abre ni un tramo. La nota permanente de cada tramo dice: *«Subvención pactada alineada a la RMV de S/ X vigente
desde el 2026-10-01 (referencia: Ley 28518, art. 45; si la boleta cumple el artículo es consulta abierta con el
laboralista)…»* y, cuando las horas no salen de un convenio, *«jornada completa de su modalidad (48 h) SUPUESTA»* (30 h
para un preprofesional).

**Se OMITE y se cuenta (sin nombres)** a quien no tiene modalidad, no tiene subvención cargada o **ingresó después del
1-oct sin horas pactadas**. **DETIENE** —sin tocar nada— si hay un conflicto de convenios; si a quien sube le tocaría una
`base_provision` propia (`fn_set_salario` no la copia), sueldo fijo, o **un tramo de sueldo que EMPIEZA el 1-oct o
después**; si hay un cambio de sueldo programado que todavía cubre el 1-oct; si no hay admin activo con usuario; si la
RMV del 1-oct no es 1,230; o si el grupo practicante del periodo ya está **pagado** (candado de `fn_set_salario`, por
grupo desde la 0327).

*El tramo que empieza el 1-oct o después es de la segunda pasada:* `fn_set_salario` **borra** todo tramo con
`vigente_desde >=` la fecha. A quien ingresó **hoy** y cobra menos que su referencia le habría borrado su único tramo
para poner el nuestro, y la receta de reversión —que reabre el tramo cerrado el 30-sep— lo habría dejado con **cero
tramos** (ensayado contra el borrador commiteado: lo hace). Ahora se detiene en voz alta.

Presta la identidad del admin activo más antiguo **solo dentro de la transacción**, igual que la 0501 y la 0462; el guard
de las funciones no se toca. **Una sola pegada a la vez:** lo primero que hace el bloque es tomar un candado de
transacción; una segunda pegada simultánea espera y, al seguir, ya no encuentra a nadie bajo su referencia (sin el
candado, dos pegadas simultáneas duplicaban las filas de auditoría de la base legal: medido, 12 en vez de 6).

### ⚠️ La suposición «jornada completa» — la confirma Felipe leyendo la fila 6

**Ninguno** de los cinco tiene un convenio con horas pactadas cargado en el sistema. El generador solo guarda las horas de
un **preprofesional** (al profesional le deja `null`) y el sistema entero —generador, texto del convenio, el script de
la 0501— lee «sin horas» como **jornada completa** de la modalidad (30 h / 48 h). La 0502 hace lo mismo, **y eso es una
suposición, no un dato**. Está escrita en el encabezado de la migración y en la nota de cada tramo.

**La protección por horas existe SOLO para el preprofesional con un convenio generado CON horas:** el generador guarda
horas únicamente para él, y la regla las ignora si la modalidad no es «preprofesional». **Para los tres profesionales esa
protección es NULA por construcción:** su convenio nunca lleva horas, la regla les aplica la RMV entera y no existe dónde
cargar «este profesional trabaja menos» para que la regla lo lea. **Para un profesional de jornada reducida NO hay
protección, y si Felipe duda de alguno, NO se pega.** *(La primera pasada decía que cargar horas en un convenio bastaba para proteger a cualquiera de los cinco: era falso
para los profesionales.)*

**Felipe NO ha confirmado la jornada de ninguno:** la fila 6 del script de la 0501 mostraba «horas completas» solo porque no hay horas cargadas (es el relleno cuando falta el dato; no comprueba nada). **Lo que la confirma es leer, ahora con las horas SUPUESTAS en número
(30 o 48), lo que marcó cada uno en el último periodo pagado (aprox.), su horario vigente como señal débil y sus convenios
con si están firmados, en la fila 6 del script nuevo ANTES de pegar.** La migración dice a cuántos subió por suposición
**en la fila final que devuelve** (`por_suposicion`, `con_horas_de_convenio`): el SQL Editor **no muestra los
`RAISE NOTICE`**, así que lo que importa no viaja en ellos. **Si no la confirma, no se pega.**

### Lo que cuesta — MEDIDO, con su cota

Con `fn_planilla_calcular` en un Postgres desechable propio (cadena completa de 480 migraciones + la 0502), el periodo
**28-sep → 28-oct (31 días; tres al sueldo viejo)** y **jornadas MODELADAS** —las horas reales de producción no se
pueden leer desde acá—. Por perfil (reproducido en la segunda pasada):

| Jornada modelada | Horas del periodo | Cobra con 1,130 | Cobra con 1,230 | Sube |
|---|---|---|---|---|
| Preprofesional 6 h L–V (30 h/sem) | 138 | 773.90 | 833.45 | **+59.55** |
| Preprofesional 5 h L–S (30 h/sem) | 135 | 757.07 | 816.63 | **+59.56** |
| Profesional 8 h L–V (40 h/sem) | 184 | 1,031.86 | 1,111.27 | **+79.41** |
| Profesional 8 h L–S (48 h/sem) | 216 | 1,211.32 | 1,306.60 | **+95.28** |
| Asistencia completa, 6.5 h × 31 días (el techo) | 201.5 | 1,130.00 | 1,220.32 | **+90.32** |

**Los S/ 384.12 de la primera pasada se retiran:** eran la SUMA de estas cinco jornadas distintas (una de 40 h y una de
6.5 h todos los días), no una medida de los cinco reales, y no se reprodujeron como tal. **El rango medido para los cinco
reales** (2 preprofesionales y 3 profesionales; la jornada máxima de cada modalidad como piso del rango y 6.5 h × 31
días como techo; quien marque menos horas cuesta menos):

- **Primer periodo (28-sep → 28-oct): ≈ S/ 405 a S/ 452** de pago por horas (3 de 31 días al sueldo viejo). Extremos:
  2 × 59.55 + 3 × 95.28 = 404.94 y 5 × 90.32 = 451.60.
- **En régimen: ≈ S/ 490 a S/ 565 al mes** según las horas que marquen (medido con jornadas modeladas: mezcla ≈ S/ 491; los cinco a jornada legal máxima ≈ S/ 520–526; los cinco a 6.5 h × 31 días ≈ S/ 564; quien marque menos cuesta menos) = el pago por horas a periodo completo (subida = horas × S/ 100 / (6.5 × días
  del periodo)) **más el devengo semestral y del descanso, S/ 12.50 por persona**. El **EsSalud +9** ya subió con la 0501 y no
  se cuenta acá.
- **Por practicante: ≈ S/ 78 al mes (preprofesional de 30 h) a ≈ S/ 120 (profesional).**
- **La cifra con las horas REALES la da la fila 8 del script** (horas del último periodo pagado de cada uno).
- La estimación vieja de «≈ S/ 110–125 por practicante al mes» era el TECHO, no un promedio: 100 de pago + 12.50 de lo
  devengado = 112.50, y 121.50 con los 9.00 de EsSalud de la 0501.

- **Lo devengado se revalúa de golpe, una vez, en +8.85 %** (1,230 / 1,130): la media subvención semestral y el descanso de
  15 días (Ley 28518 art. 42) los leen `fn_subvenciones_practicante` (0467; la usa Provisiones) y
  `fn_mis_subvenciones_practicante` (0485; la ve el propio practicante) sobre la subvención **vigente al corte**, sin
  versionar el pasado. Medido (reproducido en la segunda pasada) con ingreso el 2-mar y corte el 15-oct: **5,253.05 → 5,717.90 (+S/ 464.85
  para los cinco)**; de ahí en adelante cada hito de seis meses y el descanso valen **S/ 50 más** por persona. Es costo real, no un
  error: **quien mire Provisiones el día de la pegada va a ver el salto.**
- **Efecto colateral heredado, medido:** cada tramo nuevo dispara `fn_educacion_realinear` (0281), que corrige la asignación
  por educación de quien tenga una que no cuadre con el 75 % de su costo declarado y deja en la auditoría el motivo
  «Cambió el rango» aunque el rango no cambió (pasa con S/ 80.00 sobre un costo de S/ 107: sube a S/ 80.25; no pasa si ya
  cuadra). La **fila 9** del script dice de antemano a cuántos les puede pasar y la **fila final** de la migración cuenta
  cuántos pasó (`educacion_realineada_hoy`).

### Lo que la 0502 NO resuelve — consulta para el laboralista

1. **¿Pagar por horas marcadas cumple el art. 45 de la Ley 28518 si un preprofesional de 30 h cobra ≈ dos tercios del
   tramo?** La planilla paga a un practicante por las horas marcadas (6.5 h por día calendario = la subvención entera):
   un preprofesional que cumple sus 30 h semanales cobra **≈ S/ 773–833** en el periodo (≈ 66 % del tramo), con 1,130 y
   también con 1,230. La 0322 lo dejó escrito como decisión de quien da de alta. La 0502 alinea el TRAMO —lo pactado y lo
   que Contratos exige—, no contesta esta pregunta, y ninguna pantalla la marca. **Si la respuesta es que un
   preprofesional de 30 h debe cobrar la RMV entera, cerrar la brecha cuesta ≈ S/ 388–406 al mes por preprofesional
   (≈ S/ 775 los dos), además de lo de la 0502.**
2. **Ninguno de los cinco tiene convenio firmado en el sistema — y eso es un RIESGO, no solo un hueco de horas.** Toda
   la categoría practicante (sin CTS, gratificación ni vacaciones, sin AFP ni 4.ª) descansa en que exista un convenio de
   modalidad formativa por escrito. Sin convenio firmado y vigente esa modalidad podría no ser oponible y el vínculo
   reclasificarse como laboral (a validar con el laboralista, no se afirma). La 0502 no lo cura ni lo agrava. ¿Qué papel
   existe de cada uno, con qué modalidad y jornada? El sistema no puede probar la jornada pactada de ninguno.
3. **Adenda o renovación para los convenios firmados que dicen 1,130:** pagar más es favorable, pero el papel queda viejo.

**Pendiente que no es consulta:** el **segundo tramo de la RMV (S/ 1,300, primer semestre de 2027)** volverá a dejar la
subvención pactada bajo la RMV: hay que rehacer esta migración con los números de ese día; nada en el sistema avisa
cuando el decreto salga.

### Orden de pegado — fecha límite real: ANTES de pagar el grupo practicante del periodo 28-sep → 28-oct

**La 0502 es solo datos:** no cambia pantallas ni funciones, así que no depende del orden respecto de ningún PR. Pero
`dame-el-sql.sh` se niega a entregarla si no está en GitHub byte por byte, así que **primero se sube** (rama, PR en
borrador). **La fecha límite real no es el 28-oct sino el momento de pagar:** la migración se pega **ANTES de pagar el
grupo practicante del periodo 28-sep → 28-oct** (el periodo cierra el 2026-10-28); desde que ese grupo figure como
pagado, el candado de `fn_set_salario` (por grupo, desde la 0327) la hace abortar entera.

1. `./scripts/que-falta-pegar.sh` y pegar lo que genera: la **0502** figura pendiente y **no** hay filas nuevas de «SOBRA LA FILA».
2. `./scripts/dame-el-sql.sh scripts/sql-manual/antes_de_pegar_la_subvencion_de_los_practicantes_1230.sql` (así los
   acentos no se rompen), pegar y ejecutar: una tabla de 16 filas. **Leer:** fila 1 (cuántos suben: lo esperado es 5),
   fila 2 (`1230 / 1130`), fila 3 (**todo en 0**, incluido «CONFLICTO DE CONVENIOS»), fila 4 (quién firma el rastro),
   fila 5 (a cuántos se les SUPONE la jornada), **fila 6 (una por practicante: ¿es verdad que trabaja esas horas?)**,
   fila 8 (el costo con sus horas reales), fila 9 (educación a realinear), fila 10 (**0**), fila 11 (**ningún periodo
   con practicantes pagados**).
3. **Confirmar la fila 6, persona por persona.** Si alguna dice «DETIENE» o la jornada supuesta no es la real: parar y
   corregir (convenio con las horas reales en Contratos —solo sirve para un preprofesional—, anular el convenio que
   sobra, modalidad en Equipo) y volver a correr el paso 2. **Para un profesional no hay forma de cargar horas que la
   regla lea: si dudas de alguno, NO se pega** (Plan B: los confirmados se suben a mano en Equipo, misma persona y rango, vigencia 2026-10-01; el dudoso espera a DO y al laboralista). **Si aparece «conflicto de convenios», NO anules a ciegas un convenio firmado:** la regla no mira fechas y un convenio vencido también cuenta; anular recalcula el vencimiento del contrato (0312).
4. `./scripts/dame-el-sql.sh 0502` y `diff <(pbpaste) supabase/migrations/0502_*.sql && echo idéntico`. Pegar **entero** y
   ejecutar: es todo o nada; si da error no se tocó nada — copiar el mensaje completo y parar.
5. La fila que devuelve debe decir: `tramos_0502` = los que dijo la fila 1 como «sube» · `practicantes_bajo` = **solo**
   los de jornada reducida o fuera (la fila 6) · `por_suposicion` = lo que dijo la fila 5 y `con_horas_de_convenio` el
   resto (**la suma da `tramos_0502`**) · `educacion_realineada_hoy` = lo que anticipó la fila 9 (si dijo 0, 0) ·
   `502 la_subvencion_pactada_de_los_practicantes_sigue_a_la_rmv_de_1230`.

### Cómo se verifica

Volver a correr el script del paso 2: **fila 12 = 0** (nadie bajo su referencia), **fila 13** = los que subían, con la
división «por suposición / con horas de convenio» de la fila 5, **fila 14** = solo jornada reducida o fuera, **fila
15 = 0**, **fila 16** = las dos migraciones **con número y nombre**. Después: abrir la boleta de un practicante del
periodo 28-sep → 28-oct: «Subvención pactada (mes completo)» dice 1,230.00. Y recordar que Provisiones va a mostrar el
salto de arriba y que **no se puede bajar después de pagar un periodo con ella**.

### Cómo se ensayó (y qué NO se pudo ver)

**Primera pasada:** el borrador pasó una auditoría independiente de tres auditores; esta segunda pasada aplica sus
correcciones. **Segunda pasada**, contra la cadena completa de 480 migraciones (hasta la 0501) en un Postgres desechable
**propio** (contenedor `scratch-0502p2-pg`, puerto 54993; no se tocó ningún `supabase_*`):

- el archivo real pegado sobre una base sin practicantes (pasa, no exige admin, la fila final sale en ceros);
- un escenario de 15 practicantes activos y 3 controles (integrante en planilla, locador, en prueba): sube **7**
  (4 por suposición, 3 con horas de su convenio), la fila final dijo `7 · 7 · 4 · 3 · 0`; la **segunda pegada es
  idempotente** (mismos hashes de tramos, bases y auditoría) y la **receta de reversión** devuelve tramos, bases y conteo
  **exactos**;
- **13 casos que deben detenerla**, todos con el estado **idéntico** después: horas distintas entre sí, firmado de 20 h con
  un borrador posterior sin horas, conflicto en quien ya cumple, conflicto en quien no tiene modalidad, `base_provision`,
  sueldo fijo, tramo programado después del 1-oct, **ingreso el 1-oct con tramo desde el 1-oct**, sin admin, otra RMV el
  1-oct, sin ninguna RMV, grupo practicante ya pagado, cambio programado que cubre el 1-oct; y **5 que deben pasar**
  (conflicto resuelto anulando uno, `base_provision` en quien no sube, ingreso el 1-oct con 1,230, solo el grupo
  «planilla» pagado, sueldo fijo en quien no sube);
- el **borrador commiteado** (el de la primera pasada) contra los dos casos de la auditoría: **sube a 1,230** a quien
  firmó 20 h y **borra el único tramo** de quien ingresó el 1-oct. La versión nueva se detiene en los dos;
- **concurrencia:** dos pegadas simultáneas dejan **6** filas de auditoría de la base legal con el candado y **12** sin
  él (control);
- **siete mutaciones a la migración** que la guardia final cazó (subir a todos a 1,230, no subir la base legal, rango fijo,
  bajar a quien cobra más, mover a un integrante en planilla, saltarse a uno, base legal con otro valor); quitar los dos
  frenos nuevos (conflicto de convenios y tramo desde el 1-oct) deja pasar la migración —o sea que esos frenos son los
  que protegen—;
- la **396** pasa **48/48** y se comprobó que **puede fallar** con **siete mutaciones** a su regla (sin la clasificación de
  conflicto, conflicto solo por horas distintas, el borrador no cuenta, el anulado cuenta, el tramo del 1-oct no cuenta,
  sin tope de 30 h, horas distintas sin detectar). La prueba de vitest se vio fallar al tocar una sola condición del script.
  La **122** pasa (con `schema_migrations` emulada) verificando la fila de la 0502. **Suite pgTAP completa: 306 archivos**;
  fallan los **mismos 20** que en el control de la primera pasada (a `auth.users` le faltan columnas de GoTrue; la 122
  pasa si se emula `schema_migrations`), con **idénticos** conteos de aserciones en todos los demás. *(Trampa del banco de
  pruebas: ocho archivos fallaban de entrada con «permission denied for schema public» porque la base desechable se
  clonó con otro dueño que `postgres`; no era la 0502 —con el permiso puesto pasan—, y solo el control lo distinguió.)*

**No se pudo ver:** el `do $$` de la migración no se puede ejecutar desde pgTAP (por eso la regla vive en una vista que SÍ
se mide, y el bloque se ensayó aparte); y las **horas reales** de los cinco, que solo existen en producción — por eso la
fila 8 del script y la confirmación de la fila 6 son de Felipe. `db-tests` de GitHub es la señal fiable de las pgTAP.

---

## 2026-10-01 — El Archivo de la empresa (Empresa → Archivo) · migración 0503 · PEGADA Y VERIFICADA · SIN FUSIONAR

**Origen:** había que guardar la constancia de inscripción del banco de datos *Videovigilancia* (ANPD,
INS-2026-5135 · PJ-2026-4553, 08-09-2026) y su formulario firmado, para tenerlos a la mano en una auditoría.
Dynamic no tenía dónde: todo lo que se subía colgaba de una persona. Felipe eligió construir un archivo propio
(«A») y ponerlo en un grupo nuevo del menú, **Empresa → Archivo**, que solo ve DO.

**Qué es:** tabla `archivo_empresa`, bucket privado `archivo-empresa`, `fn_archivo_subir` / `fn_archivo_retirar` /
`fn_archivo_empresa`, pantalla `/admin/archivo`. Nada se edita ni se borra: corregir crea una ficha que reemplaza a
la anterior (puede reusar el archivo) y retirar exige motivo. Avisa lo que vence en ≤ 60 días. Prueba pgTAP **397**
(49 aserciones; el control sin índice único, sin trigger y con lectura abierta pone en rojo las 6 que deben caer).

**Pegada el 2026-10-01 y verificada** en el SQL Editor: tabla 1/1, funciones 5/5, políticas de Storage 4/4,
bucket privado, RLS activa, y `migraciones_aplicadas` con **503 · el_archivo_de_la_empresa** (número Y nombre).
Se pegó desde el portapapeles de `dame-el-sql.sh`, comprobado idéntico byte por byte al archivo en GitHub.
Falta fusionar el PR #481, que es publicar la pantalla.

**Después de pegar:** subir los dos PDF de videovigilancia desde la pantalla (viven en Descargas de la MacBook; no
van a git: llevan el DNI del representante). Y el primero que más vale subir es la **constancia de REMYPE**: sin ella
no aplica el tope del 1 % de los ingresos netos a las multas de una inspección (ver «El techo que ordena todas las
multas», más abajo).

**Abierto:** la líder de equipo no ve el archivo; si un inspector llega a una tienda, no puede mostrar la licencia de
su sede. Se resolvería abriéndole la lectura de los papeles de SU sede (`sede_id`), no del archivo entero.

---

## 2026-09-30 — La RMV sube a S/ 1,230 el 1-oct, la escala la sigue y la asignación familiar sube a S/ 123 · migración 0501 · PEGADA y verificada (2026-10-01) · SIN FUSIONAR

**Origen:** el **D.S. 015-2026-TR**, publicado el **2026-09-28** en El Peruano (edición extraordinaria), art. 1,
lleva la RMV a S/ 1,300 **en dos tramos**: el primero (+S/ 100 = **S/ 1,230**) rige el **2026-10-01**; el
segundo (+S/ 70) lo fijará **otro decreto supremo en el primer semestre de 2027** y **NO está construido**.
Verificado contra el texto publicado. El decreto no menciona la asignación familiar.

**Lo decidido por Felipe (2026-09-30)** — la migración **0501** y la prueba **395** lo construyen:

| | antes | desde el **2026-10-01** |
|---|---|---|
| RMV (`parametros_laborales`) | 1,130 | **1,230** |
| Base declarada **colibrí** (10 personas) — sueldo y `sueldo_base_legal` | 1,130 | **1,230** |
| Base declarada **cayla** (4) | 1,185 | **1,245** |
| **support** (1) · aurora · oráculo · archicaylo | 1,260 · 1,360 · 1,440 · 1,500 | **sin cambio** (ni un tramo nuevo) |
| Lo que publica la **Política salarial** (`categorias_laborales.salario_declarado`) | 1,130 · 1,185 · 1,260 | **1,230 · 1,245 · 1,260** |
| **Asignación familiar** | 113 | **123** (10 % de la RMV, Ley 25129 art. 1) |
| `DEFAULT` de `personas.sueldo_base_legal` (altas futuras) | 1,130 | **1,230** |

**Por qué support se queda en 1,260:** ya cumple la RMV. La escala es la **más barata que mantiene el orden**.
La cobertura de estudios llega a S/ 270 al mes y la Política publica una «Referencia mensual» = remuneración +
movilidad (hasta S/ 288) + estudios (colibrí 1,608 · cayla 1,713 · support 1,818 · aurora 2,008): **la
educación no se sube ni se iguala «para compensar»; la base cumple sola.**

**Lo que cuesta** (factor 1.2567 = EsSalud 9 % + grati 8.33 % + CTS 4.17 % + vacaciones 4.17 %; **estimado**, el
número real sale de `fn_simular_planilla`): colibrí +100 × 10 = S/ 1,256.70 · cayla +60 × 4 = S/ 301.61 →
**≈ S/ 1,558.31 al mes** (~S/ 18,700 al año). La asignación suma **≈ S/ 12.57 al mes por cada integrante que la
cobra**: cuántos son lo dice la consulta (iv) del script de abajo. **Alternativas medidas y descartadas por ahora:**
cayla también en 1,230 (el mínimo absoluto de ley) ahorraría S/ 75.40 al mes → S/ 1,482.91 en total, pero deja a
colibrí y cayla con la **misma** base; la escala 1,230 / 1,260 / 1,290 (support también sube) costaría
S/ 1,671.41. Felipe puede pedir la primera: es cambiar **un número** (`v_montos` de la 0501, `param` del script,
`rangos.ts` y la prueba 395).

**⚠️ El primer periodo con el sueldo nuevo paga MENOS de lo que parece.** Los sueldos suben **desde el 2026-10-01**
y la planilla paga **por día con el tramo de cada jornada**: los días de septiembre que caen dentro del
periodo abierto se pagan al **sueldo viejo**. **CORRECCIÓN del 2026-10-01:** el periodo abierto en producción es
**28/09 → 28/10 (31 días)** —lo midió la fila 11 del script de comprobación; el último pagado cerró el 27/09—, no el
29/09 → 28/10 de 30 días que se asumió al escribir esto. Son **tres** días al sueldo viejo (28, 29 y 30), no dos:
un colibrí con asistencia completa cobra **≈ S/ 1,220.32** (3/31 × 1,130 + 28/31 × 1,230) y una cayla
**≈ S/ 1,239.19** (en la prueba 395, con un periodo de 30 días, daba 1,223.33 y 1,241.00) — **no es «menos que la RMV»**:
son tres días de septiembre al sueldo de septiembre; desde el periodo siguiente cobran el sueldo completo.
La cabecera de la 0501 (ya pegada, y por eso intacta: lo pegado tiene que seguir siendo idéntico a lo guardado)
todavía dice «29-sep» y «2 días»; vale esta corrección, no ella. **Hoy hay 9 colibrí, no 10** (fila 1 del script):
el costo mensual de la escala es ≈ S/ 1,433, no ≈ S/ 1,558.
El piso de EsSalud sí usa la RMV **entera** de 1,230 en ese periodo, porque se lee al último día: 9 % × 1,230 =
S/ 110.70 (antes 101.70). Tener esta explicación a mano el día de pago.

### La asignación familiar sube a 123 — irreversible, y por qué se tocó `configuracion`

**Decidido «por ley»**, sabiendo que la nota de la 0122 dice que la pequeña empresa no la tiene entre sus derechos
(la «vía de riesgo cero» de agosto era dejarla en 113). **Una vez que un periodo se calcula y se paga con 123,
bajarla es una reducción unilateral de remuneración** (art. 30 inc. b del D.S. 003-97-TR): la única parte de la
0501 que no se deshace.

La asignación vive en **dos sitios** —medido contra las 480 migraciones—: `parametros_laborales` (versionada; la
leen el núcleo de la planilla y `fn_provisiones`) y `configuracion.asignacion_familiar` (0113, **sin fechas**; es
el respaldo de las dos anteriores y la **única** fuente de `fn_remuneracion_computable`, de la que cuelgan las
liquidaciones por cese). Subir solo la versionada dejaba la boleta en 123 y la liquidación en 113, **en contra de
quien se va**. La 0501 sube las dos. Qué recalcula: solo lo **no pagado** (`liquidacion_pagada` congela el total).
Qué error deja: una liquidación cuya fecha de referencia sea anterior al 1-oct pero se calcule con 123 paga unos
céntimos **de más** (un cese de octubre mira el mes anterior); dejar 113 pagaba de menos a todo cese desde noviembre.

**Deuda que queda:** `fn_remuneracion_computable` sigue leyendo `configuracion` sin fecha; lo correcto es que lea
`parametros_laborales` a `p_fecha_ref` (migración propia, con md5 de producción). Y los `coalesce(…, 113.00)`
escritos **dentro** de las funciones (núcleo, `fn_provisiones`, `fn_remuneracion_computable`) siguen ahí: solo se
usan si faltan las dos tablas, y no faltan. Cuando la RMV suba al segundo tramo, la asignación a **130** hay que
subirla en **los dos** sitios otra vez.

### Los practicantes: la 0501 NO los alcanza — los resuelve la **0502** (entrada «La subvención pactada de los practicantes sigue a la RMV nueva», arriba)

`fn_fijar_base_declarada` exige `en_planilla` y un practicante tiene `en_planilla = false`: la 0501 **no los
alcanza**, y su subvención de S/ 1,130 queda bajo el piso de la Ley 28518 art. 45 (RMV, o su proporción a las horas
pactadas) **sin que el sistema lo marque**. **Decidido el 2026-10-01 por Felipe: la migración 0502** alinea su subvención pactada a la RMV
**por regla** (nunca por rango, que habría barrido a quien pactó menos horas) — ver la entrada de arriba, con la
suposición «jornada completa», el costo medido, lo que NO promete (la boleta paga por horas) y el orden de pegado. Además, desde el 1-oct Contratos **bloquea**
generar un convenio con subvención bajo el piso (por eso el código lee ahora la RMV con la regla de la planilla y no
como «la fila abierta»), su EsSalud sube solo (piso puro, 101.70 → 110.70) y los convenios ya firmados siguen diciendo
1,130 en el papel (pagar más es favorable, pero el papel queda viejo: adenda o próxima renovación, **consulta para el
laboralista**).

### La otra rama: `claude/salary-update-1230-bd7a09` — descartarla o cerrarla

Otra sesión escribió el mismo día (10:00–10:17) una versión **distinta** de este trabajo: una 0500 con la RMV en
1,230 **y la asignación en 123**, un guion que deja **colibrí y cayla ambos en 1,230**, la prueba 394 y su propia
entrada en este archivo (que recomienda «colibrí y cayla iguales»: **superada por la decisión de arriba**). No está
fusionada ni pegada. **No fusionarla:** su 0500 sube la asignación sin tocar `configuracion` (las dos verdades), su
guion afirma que «no baja a nadie» y la función **sí baja** a quien ya cobre más de su rango, y las dos ramas tocan
`estado.md` y `rangos.ts` (habrá conflicto). **Si de todos modos se pegara, la 0501 sigue siendo correcta** en
cualquier orden (`on conflict do nothing`, cierres que no repiten, solo sube). Si se descarta, el número **0500 queda
como hueco** —el hook solo avisa— y conviene dejarlo anotado acá; la 0499 ya está en `main` (PR #476) y la 0501
se ensayó también con ella aplicada.

### Lo que la 0501 detiene, y cómo se ensayó

Todo va en **una transacción** con guardia final: aborta en voz alta —sin tocar nada— si hay alguien con la base
sin confirmar, con `base_provision` propia (`fn_set_salario` no la copia al tramo nuevo y sus provisiones bajarían
en silencio), con sueldo fijo, con un tramo ya programado después del 1-oct, o con un campo por encima y otro por
debajo; si no hay un admin activo con usuario; o si al final el sistema no lee 1,130 / 1,230 y 113 / 123 donde
debe. **Solo sube:** quien ya cobra más de su rango (monto propio) queda como está (`fn_fijar_base_declarada` **no**
protege de bajar; se le pasa `p_omitir` calculado). Presta la identidad del admin activo más antiguo **solo dentro de
la transacción** (mismo patrón que la 0462; el guard de las funciones no se toca) y **corrige la nota** que la
función deja escrita para un alza. Ensayada contra la cadena completa de 480 migraciones en un Postgres
desechable con un escenario tipo producción (10 + 4 + 1 + 1 + 1 y casos de borde): los **nueve** casos que deben
detenerla (base sin confirmar, `base_provision`, sueldo fijo, tramo programado, un campo arriba y otro abajo, sin
admin, periodo ya pagado, otra RMV sembrada el 1-oct, otra asignación sembrada el 1-oct) y el que debe **pasar**
(una cuenta de servicio en colibrí se omite), la base vacía de CI (pasa sin exigir admin), repegarla dos veces
(mismos conteos), quien ya cobra más (1,500 y 1,300: no baja), el pago real por tramos y la suite pgTAP completa
**con control**: 305 archivos antes y 306 después, sin ninguna diferencia salvo la prueba nueva **395 (31
aserciones)**. Los mismos **19 archivos** fallan con y sin la migración, por el entorno (a `auth.users` le faltan
columnas de GoTrue); la 122 falla en el control solo porque no existe `supabase_migrations.schema_migrations` y con esa
tabla emulada **pasa y verifica la fila de la 0501**. Se comprobó que la 395 **puede fallar** con cinco mutaciones a
propósito (configuracion en 113, DEFAULT en 1,130, Política en 1,130, la RMV nueva borrada, y el reajuste sin
`p_omitir`). **No se simuló el reloj de Postgres en
octubre**: las pruebas con fechas relativas a hoy comparan identidades, no montos, pero `db-tests` de GitHub es la
señal fiable.

### Guion de mañana — 2026-10-01

**RMV a S/ 1,230 · escala nueva · asignación familiar S/ 123 · Política salarial nueva** — revisado por un lector sin contexto que lo recorrió paso a paso contra el código.

**Orden que no se altera:** comprobar → pegar la 0501 en producción → fusionar el PR → recargar y comprobar → publicar la Política → avisar. Nada se hace en producción esta noche (30-sep): entre pegar y el 1-oct la pantalla Contratos (con el código viejo) no vería ninguna RMV.

**Nunca, en ningún paso:** pegar la 0500 ni correr scripts/sql-manual/reajuste_bases_rmv_1230.sql (son de la rama claude/salary-update-1230-bd7a09; ese script baja Cayla de 1,245 a 1,230 y reescribe la Política) · npx vercel --prod · supabase db reset · fusionar el PR antes del paso 10 · pulsar «Confirmar de todas formas» en la ventana de publicar.

**A. Preparar** (lo hace Claude, con tu OK, dentro de la carpeta de este trabajo: .claude/worktrees/planilla-seccion-feriado-21d627, rama claude/salary-structure-update-4f2712; solo después de las 00:00 hora de Lima del 1-oct: antes, el pre-push se detiene porque la novedad lleva fecha 2026-10-01 y tests/novedades.test.ts rechaza fechas futuras)
1. **Hecho el 2026-09-30:** se trajo origin/main a la rama (0499, retiro de las 0497/0498, novedad del certificado) y se resolvieron novedades.ts —las tres entradas— y este archivo —las dos secciones—. Pasadas las 00:00 de Lima, Claude vuelve a correr ./scripts/siguiente-numero.sh: si la 0501 ya no está libre, renumera migración, prueba 395, script antes_de_pegar y textos, y lo vuelve a comprobar.
2. **Decidido el 2026-09-30:** la frase de la Política quedó «se reajustan, como mínimo, hasta la nueva mínima» (Cayla queda en 1245, por encima de la mínima); ya va en este PR. También decidido: sueldos desde el 1-oct (no el 29-sep) y el rótulo de la boleta de septiembre se arregla en un PR aparte, después.
3. Commit nuevo (nunca --amend) y git push. Si el hook responde que regeneró la consulta de qué falta pegar y aborta, es normal: repetir git push.
4. Abrir el PR como BORRADOR (draft), con título «NO FUSIONAR ANTES DE PEGAR LA 0501» y este guion pegado en la descripción. Comprobar: gh pr view N --json isDraft,autoMergeRequest debe dar true y null, y Auto-fix apagado. Un borrador no se puede fusionar ni por costumbre ni por fusión automática.
5. Esperar a que db-tests y ui-tests salgan en verde sobre el ÚLTIMO commit. Si alguno sale rojo: no pegar ni fusionar; pasar a Claude el nombre de la prueba.

**B. Comprobar y pegar** (tú; Supabase, proyecto de PRODUCCIÓN —no el local—, SQL Editor; los comandos, en la terminal dentro de la carpeta del trabajo)
6. ./scripts/que-falta-pegar.sh genera scripts/sql-manual/que_falta_pegar.sql (solo lo genera): pega ese archivo en el SQL Editor y ejecútalo. Esperado: la 0501 figura pendiente y no hay ninguna fila nueva de «SOBRA LA FILA»; la 0500 NO debe estar aplicada. Si lo está: parar.
7. ./scripts/dame-el-sql.sh scripts/sql-manual/antes_de_pegar_la_rmv_1230.sql (así los acentos no se rompen), pegar, ejecutar: una sola tabla de 17 filas. Leer:
   - Fila 2: «14 persona(s)» (10 Colibrí + 4 Cayla medidos el 30-sep; si difiere, mira la fila 1 y para).
   - Fila 3 (los cinco casos) y fila 15: TODO en 0. Si no, la migración se detendrá: no seguir. Remedio por causa: *base sin confirmar* → confirmarla en Equipo; *base_provision propia* o *sueldo fijo* → decisión de Felipe, no se resuelve a ciegas; *tramo de sueldo programado después del 1-oct* → revisarlo en Equipo; *un campo arriba y otro abajo* → igualar a mano (consulta (i) del script); *fila 15 (rendimiento < 100 en un mes pagado)* → decisión de Felipe.
   - Fila 4: «nadie» o quien cobra por encima de su monto (esa persona NO se toca, es lo correcto).
   - Fila 5: «nadie». Si sale una estación o cuenta de servicio de rango Colibrí, es lo esperado: la migración la omite a propósito.
   - Filas 6 y 7: practicantes. La 0501 NO los toca: los resuelve la 0502 (entrada «La subvención pactada de los practicantes sigue a la RMV nueva», con su propio script y orden de pegado). Anota quiénes salen «QUEDA BAJO EL PISO EL 1-OCT».
   - Fila 8: antes «1130 / 1130». Fila 9: antes «113 / 113 / 113». Los valores salen con cinco decimales (1130.00000 es 1130).
   - Fila 10: cuántas personas cobran asignación familiar (cada una cuesta ≈ S/ 12.57 más al mes y, pagado un periodo con 123, no se puede bajar).
   - Fila 11: periodo abierto que cierra el 2026-10-28 (el 1-oct se midió 2026-09-28 → 2026-10-28; si la fecha_fin NO es 2026-10-28, para y avisa). Fila 12: último periodo cerrado o pagado.
   - Fila 13: la 499 puede figurar; la 500 y la 501 NO.
   - Fila 14: quién firmará el rastro (el admin activo más antiguo con usuario; no tiene que ser Felipe).
   - Fila 16: cuántas constancias dejó la versión vigente (te dice a cuántas personas llegará el aviso).
   - Fila 17: antes 1130 · 1185 · 1260 · 1360 · 1440 · 1500 (con dos decimales).
8. ./scripts/dame-el-sql.sh 0501 y comprobar los acentos: diff <(pbpaste) supabase/migrations/0501_*.sql && echo idéntico. Pegar ENTERO en el SQL Editor y ejecutar. Es todo o nada: si da error, no se tocó nada; copia el mensaje completo y para. No hay prisa contable: se puede pegar después mientras el periodo 29-sep → 28-oct no esté pagado. Si luego el editor contesta «current transaction is aborted», recarga la pestaña del SQL Editor.
9. Comprobar la fila que devuelve: RMV 15-oct 1230 · RMV 30-sep 1130 · asignación 15-oct 123 · asignación 30-sep 113 · configuración 123 · default 1230.00 · «colibri 1230.00 · cayla 1245.00 · support 1260.00» · «501 la_rmv_sube_a_1230_y_la_escala_la_sigue» (los ceros de más no importan). Volver a ejecutar el paso 7: fila 2 = 0 persona(s); fila 8 = 1130 / 1230; fila 9 = 113 / 123 / 123; fila 17 = 1230 · 1245 · 1260 · 1360 · 1440 · 1500. Desde aquí hasta el paso 14 no pares (unos 15 minutos y, de preferencia, antes de que abran las sedes): desde ahora cualquiera que abra Política salarial ve la escala nueva con la insignia «Desactualizada».

**C. Fusionar y publicar** (tú)
10. En GitHub, en el PR: «Ready for review» → confirmar que el CI sigue en verde → botón verde de fusionar (fusionar ES publicar). Esperar el despliegue de Vercel en «Ready» (~1 minuto; pestaña Deployments de cayla-dynamic o el check de Vercel en el commit de main). Si la fusión cae en un día distinto del 1-oct, antes de fusionar corregir id y fecha de la novedad.
11. Recarga forzada (Cmd+Shift+R) en TODAS las pestañas de Dynamic que tengas abiertas (una pestaña vieja publicaría el texto viejo). Personas → Equipo → botón «•••» de una fila Colibrí → «Editar salario»: base 1,230 y NO debe salir el aviso ámbar «Fuera de la base del rango». Con una Cayla, 1,245. Cierra SIN guardar.
12. Publicaciones → Política salarial: la insignia «Desactualizada» y el aviso ámbar «El cuadro cambió después de publicar» → enlace «Publica una versión nueva» (o la pestaña «Versiones y publicación», /admin/politica-salarial/versiones) → sección «Publicar» → botón «Publicar» → ventana «Publicar política salarial». Debe decir «Esto creará la versión N+1» y «Las X personas obligadas van a tener que dejar constancia de nuevo». Si en cambio dice «No hay cambios de contenido»: pulsa solo «Cancelar»; significa que el navegador no ve el SQL o el código nuevo; recarga forzada y repite. Pulsa «Publicar versión nueva» UNA vez. Mensaje verde esperado: «Se publicó la versión N+1. Las constancias se piden de nuevo.»
13. Comprobar. (a) Versiones y publicación → Historial → «Ver» en la versión nueva: sección «La escala» con Colibrí 1,230 · Cayla 1,245 · Support 1,260 · Aurora 1,360 · Oráculo 1,440 · ArchiCayla 1,500, y la cláusula de la mínima vital con el texto nuevo. (b) Documento vigente: «Versión N+1 · publicada el <hoy> · Vigente · Constancias: 0 / Y». En esa pantalla la escala no se dibuja como tabla: ábrela con el botón «+» de «Cómo se aplica cada criterio a cada categoría» (tarjetas S/ 1230.00 · 1245.00 · 1260.00 · 1360.00 · 1440.00 · 1500.00).
14. Deja tu propia constancia: al abrir Dynamic sale «Te falta dejar una constancia» → «Leer y dejar constancia» → al final, «Constancia de haber recibido este documento» (tu nombre ya viene escrito) → «Dejar constancia» → «Gracias. Tu constancia quedó registrada.»
15. Avisar a todos.
   - La novedad «Hay una versión nueva de la Política salarial para leer y confirmar» ya salió con la fusión, para todos los roles: en Publicaciones → Anuncios (sección de novedades) y en «Lo mío» (tarjeta «Una novedad del sistema», con «Entendido»; 14 días). No lleva montos: así debe ser.
   - Recomendado: un Anuncio de DO justo ahora, para tener el aviso a tu hora. Publicaciones → Anuncios → «Publicar un anuncio»: Título «Hay una versión nueva de la Política salarial para leer y confirmar». Cuerpo: «Desarrollo Organizacional publicó hoy una versión nueva de la Política salarial. Al abrir Dynamic verás un aviso que pide dejar constancia: entra con «Leer y dejar constancia», lee el documento y pulsa «Dejar constancia» al final. Dejar constancia no significa estar de acuerdo: significa que la recibiste y la leíste. Si tienes una duda o una discrepancia, puedes plantearla a la Gerencia y recibirás respuesta por escrito.» A quién: «Todas las sedes» → «Publicar». Sin montos.
   - Quien tenga Dynamic abierto desde antes verá el aviso al recargar; quien no tenga cuenta no lo verá nunca (ver paso 16).

**D. Después**
16. Seguimiento en Publicaciones → Política salarial → «Constancias» (hoja imprimible con pendientes y motivo). Quien no deja constancia: no se bloquea nada, no se le descuenta nada y nadie la firma por ella; queda pendiente y visible. A los 3 días, su líder de equipo o DO la acompaña a abrir su propia cuenta y dejarla ella misma (es la única vía: la hoja dice «no hay vía en papel para este documento»). Si no puede entrar, qué otra prueba de entrega se acepta es consulta al laboralista; no se promete antes. Para dar el documento en papel: Versiones y publicación → «Ver» → «Descargar PDF» (el «Imprimir / Guardar como PDF» del documento vigente omite la sección «La escala»). El «X / Y» de Política y la hoja de Constancias pueden diferir en quien está en días de selección: vale la hoja.
17. Antes del cierre del 28-oct:
   - Practicantes (filas 6-7): **los resuelve la 0502** (entrada «La subvención pactada de los practicantes sigue a la RMV nueva»): se pega después de leer la fila 6 de su script y antes de pagar el grupo practicante del periodo 28-sep → 28-oct. Desde el 1-oct Contratos bloquea generar o renovar un convenio con subvención bajo el piso (RMV, o su proporción a las horas pactadas) —la 0502 lo desbloquea al subir el tramo—; su EsSalud sube solo de 101.70 a 110.70; los convenios firmados siguen diciendo 1,130 (adenda o renovación: consulta al laboralista).
   - Personas → Datos personales: revisar los ⚠ de asignación familiar («se le paga y declara que no tiene hijos menores», etc.). A quien se le pague sin corresponder recibirá S/ 123 desde el 1-oct y no se podrá bajar.
   - Regenerar los borradores de renovaciones creados antes de pegar (llevan la remuneración vieja congelada; un borrador se corrige, no se duplica).
   - Abrir la boleta de una Colibrí y de una Cayla del periodo 28-sep → 28-oct: la línea de remuneración con el mes completo debe dar ≈ 1,220.32 y ≈ 1,239.19 (no es el total de la boleta) y el piso de EsSalud 110.70.
   - Explicación para quien pregunte: «Del 28 de septiembre al 28 de octubre, los días 28, 29 y 30 de septiembre se pagan con el sueldo de septiembre y del 1 al 28 de octubre con el sueldo nuevo; por eso este primer periodo sale por debajo del sueldo nuevo completo. Desde el periodo siguiente cobras el monto completo.»
   - Avisar en persona (DO o su líder de equipo) a las personas de Colibrí y Cayla del ajuste, y a quienes cobran asignación familiar de su nuevo monto: el aviso del sistema no lleva montos. Support, Aurora, Oráculo y ArchiCayla no suben.
18. Limpieza (Claude). **Hecho el 2026-10-01:** los huecos 0472 y 0500 quedaron anotados en scripts/hooks/huecos-conocidos.txt con su razón; la rama de la 0500 se renombró a archivo/0500-no-pegar, sin fusionar y sin subir a GitHub (no se borró: es el único ejemplar de sus commits, y la nota del hueco los cita), y su sesión «Actualización de sueldo a 1230» quedó archivada en el app. Confirmado en el SQL Editor de producción: `select numero, nombre from migraciones_aplicadas where numero in (472, 500);` devolvió cero filas. Vigilancia de Felipe: el segundo tramo de la RMV (S/ 1,300, decreto del primer semestre de 2027) no está construido y nada avisa cuando salga; entonces Colibrí, Cayla y Support vuelven a quedar bajo el piso y la asignación pasa a 130 en parametros_laborales y en configuracion.

**Si algo sale en otro orden**
- Fusionar antes de pegar: Equipo propone bases (1,230 / 1,245) que el sistema aún no paga, Contratos lee la RMV vieja y la novedad avisa de una versión que no existe. Pegar la 0501 y seguir con el paso 12 recarga el estado.
- Publicar la Política antes de pegar el SQL o antes de fusionar (o desde una pestaña vieja): se congela un documento con la escala o la cláusula viejas; hay que publicar otra versión y todo el equipo confirma dos veces.
- Pegar la noche del 30: Contratos sin RMV hasta el 1-oct («[FALTA PUBLICAR LA RMV VIGENTE EN EL SISTEMA]» en el convenio de jornada reducida).
- Pegar después de pagar el periodo 28-sep → 28-oct: el candado de periodo pagado de fn_set_salario rechaza el cambio y la 0501 aborta entera.
- Pegar la 0500 o el reajuste de la rama paralela después de la 0501: baja Cayla a 1,230; detener y avisar.

---

## 2026-09-29/30 — Un cese con reingreso se regulariza (0499 PEGADA · regularización HECHA y verificada) · la licencia sin goce (0497/0498) se RETIRÓ sin haberse pegado

**Estado al 2026-09-30, por la tarde — lo que de verdad pasó en producción:**
- **0499 pegada y verificada** (`funcion_cambiada = true`; `migraciones_aplicadas` tiene la 499 con su nombre).
- **Regularización ejecutada por Felipe (paso 2) y comprobada (paso 3).** La fecha de ingreso de la persona
  pasó de 30/09/2025 a 02/06/2026; se registró la liquidación de la primera etapa (versión 1) **neta en cero,
  saldada por declaración** de Felipe, sin verificar contra comprobantes: sueldo de marzo pagado; gratificación
  de 2025 pagada (se tomó el importe del sistema, S/359.70); los S/317.53 de la planilla de julio atribuidos
  por completo a la primera etapa, con **S/77.73 anotados como «pagado de más» sin compensar**; CTS saldada
  por otro arreglo (S/282.03); vacaciones «pagadas» **sin monto declarado, se asumió que completas (S/317.24)**.
  La fecha de pago quedó vacía a propósito. Resultado medido en producción, igual al del ensayo: vacaciones
  15.04 → 4.96 días, reserva sin líneas negativas (vac S/141.65, CTS S/153.45, gratificación S/211.80), el
  sistema no la da por liquidada, y el rastro tiene sus dos filas. El bloque para deshacerlo quedó probado
  (anula la liquidación y devuelve el ingreso; no despaga lo pagado) y no se necesitó.
- **0497/0498 (licencia sin goce) RETIRADAS el 2026-09-30, sin haberse pegado nunca.** Estaban fusionadas desde
  #474 y no hacían falta para este caso (son para un acuerdo de no venir SIN cese). Se retiraron por tres razones:
  el uso futuro es bajo e incierto (un caso en unas treinta personas, y ese caso no era una licencia); no se podían
  encender hasta que el laboralista respondiera; y mientras estuvieran sin pegar el informe de «qué falta pegar»
  las marcaba ❌ para siempre, que es lo que enseña a no mirarlo. Se retiró también el aviso de la pantalla de
  Ausencias y los tipos. **Siguen en el historial de git** (commits `104a111b`, `b61e6675` y `413e0e5d`, PR #474):
  para reponerlas hacen falta dos cosas —un caso real de acuerdo sin cese y la respuesta del laboralista sobre si
  esos días cuentan como servicio—, y entonces conviene rehacerlas sobre la versión vigente de las cuatro funciones,
  no restaurarlas tal cual. Quedan como hueco documentado en `huecos-conocidos.txt`.
  **Lo que de verdad falta construir es un flujo de reingreso**: el caso real fue un cese con reingreso, y hoy se
  resuelve con SQL a mano; `fn_reactivar_persona` conserva `fecha_ingreso` y no hay historial de ingresos.
- **Accidente de proceso, ya rescatado:** #474 se fusionó a las 09:39 (Lima), ANTES de que se subiera la 0499;
  esos commits quedaron en la rama, fuera de `main`, mientras producción ya tenía la función. Es el mismo
  modo de fallar que #452/#453. Se rescataron en un PR aparte. **Regla: no empujar más commits a una rama cuyo
  PR ya se fusionó; comprobar `gh pr view` antes de cada push.**
- **Sin decidir ni comprobar:** la baja y el alta en el T-Registro de SUNAT (22/03 y 02/06) y las PLAME de abril y
  mayo; el documento firmado del mutuo acuerdo; los comprobantes de los pagos declarados; y si la liquidación de
  quien trabaja a tiempo parcial debe calcularse con el sueldo base completo o con su ritmo real (consulta al
  laboralista, junto con los intereses por la demora).

**Origen:** la pantalla de Provisiones mostraba **15.0 días** de vacaciones para una integrante
que cumple su primer año esta semana, y la pregunta fue cómo los acumuló tan rápido si estudia
y trabaja a tiempo parcial. Los datos de producción (SELECTs de Felipe, sin nombres aquí): ingreso
hace un año, sin cese, sueldo continuo, y **71 días seguidos sin una sola marca** en el medio, sin
ninguna ausencia escrita. El monto reservado estaba bien —sigue las horas marcadas—; lo que no
cuadraba eran los días.

**El defecto no era aritmético, era de modelo.** `fn_vacaciones_saldo_interno` (0357) gana
`15 × años + trunco` por calendario desde `fecha_ingreso` y **no lee `ausencias`**. Da igual que DO
registrara esos 71 días como lo que fueran: el contador seguía en 15.0. Y la liquidación al cesar
paga `días pendientes` desde ese mismo contador, así que el sistema no tenía cómo representar
«estuvo fuera». (La reserva en soles nunca tuvo el problema: un día sin marca no tiene `pago_dia`.)

**[RETIRADAS el 2026-09-30 — esta descripción se conserva solo como referencia del diseño.]**

**Se construyó en dos migraciones, a propósito** (primero se cambia el terreno, después el cambio):

| | qué hace | toca plata | necesita md5 |
|---|---|---|---|
| **0497** | columna `tipos_ausencia.suspende_record` (con dos constraints: no puede convivir con `paga` ni con `descuenta_vacaciones`), el tipo `licencia_sin_goce` y dos funciones internas (`fn_dias_suspendidos`, `fn_fecha_ingreso_efectiva`) | no | no: solo agrega |
| **0498** | `fn_vacaciones_saldo_interno`, `fn_vacaciones_truncas`, `fn_vacaciones_resumen` y `fn_provisiones` leen el ingreso efectivo | sí | sí: guardia dentro de la migración |

**El interruptor nace APAGADO.** Si los días de una licencia sin goce restan del año de servicio es
una regla legal, y no la decide una migración. Con él apagado ambas migraciones son inertes: se
puede pegar y registrar desde hoy sin que se mueva un día ni un sol. Cuando el laboralista confirme:
`update tipos_ausencia set suspende_record = true where codigo = 'licencia_sin_goce';` — sin
migración, y todo lo ya registrado cuenta desde ese momento.

**Restar los días y correr el aniversario son la MISMA cuenta** (se había planteado como dos
opciones para el laboralista): una sola función, `fn_fecha_ingreso_efectiva`, corre `fecha_ingreso`
tantos días como la persona estuvo fuera, y las cuatro la leen. La única pregunta legal que queda
es binaria: ¿cuenta como servicio, sí o no?

**Medido en un Postgres desechable** (fechas inventadas, sueldo S/1,950, 71 días fuera): saldo
14.88 → 11.88 días, liquidación S/967.20 → S/772.20 (= 3 × 1,950 ÷ 2 ÷ 15 = S/195.00), reserva en
soles sin cambio. Con el interruptor apagado las **44 pruebas** que ya tocaban estas funciones
(565 aserciones) dan exactamente lo mismo antes y después. Pruebas nuevas: 391 (23 aserciones) y
392 (24), y se comprobó que pueden fallar rompiendo cada función de a una.

**La guardia de la 0498.** No se pudo pedir el md5 a producción antes de escribirla, así que la
verificación se movió al momento de pegar: la migración compara cada cuerpo contra el que se leyó
(repositorio al 2026-09-29) y **PARA sin aplicar nada** si es otra versión. Acepta tal cual, sin
comentarios y con `\r` por línea. Probada con una versión distinta (aborta, no aplica nada), con
`\r` (pasa) y repegada sobre sí misma (aborta). **Aun así: `donde-vive.sh` de las cuatro y mirar
si otra sesión fusionó algo que las reescriba, antes de pegar.**

**Pendiente, en este orden:**
1. **RESPONDIDO por Felipe el 2026-09-30: la persona se fue, dejó de trabajar y luego regresó.**
   Eso **no es una licencia sin goce**, y la diferencia importa: es un cese seguido de un reingreso
   (o, si nadie lo formalizó, una ausencia de hecho cuya naturaleza legal decide el laboralista).
   **Las 0497/0498 NO resuelven este caso**: cubren un acuerdo de no venir sin cese, que es otra
   cosa. Lo que el sistema tiene hoy para esto:
   · No hay cese registrado (`fecha_cese` nula, sin rastro de cese ni de reactivación en
     `correcciones_auditoria`) y el tramo de sueldo siguió abierto.
   · **No existe un flujo de reingreso.** `fn_reactivar_persona` (0209/0327) existe «porque a veces la
     baja fue un error»: conserva `fecha_ingreso`, así que aunque SÍ se hubiera cesado y reactivado,
     el contador de vacaciones contaría el hueco como servicio. Hay una sola columna de fecha de
     ingreso por persona y ningún historial de ingresos.
   · Si fue un cese real, la liquidación de la primera etapa (vacaciones, CTS y gratificación
     truncas) habría estado vencida desde entonces y hoy no hay cómo saber si se pagó. **Esto hay que
     mirarlo con el laboralista antes que cualquier cambio de código.**
   · La otra persona activa con cero marcas en abril y mayo (las demás tienen entre 22 y 29 por mes)
     es una **accionista, fuera de planilla**: no es el mismo caso. (Aquí se sugirió antes que podía
     serlo; Felipe lo corrigió el 2026-09-30. Quien filtre «activos sin marcas» debe excluir a
     `no_trabajador`, que no tiene jornada que marcar.) Descartado también un hueco global de la
     importación: las demás personas de planilla sí tienen marcas esos dos meses.
2. **DECIDIDO por Felipe el 2026-09-30: opción A — tratarlo como cese y reingreso**, con SQL a mano. El
   camino normal está cerrado por tres frenos que son correctos en general: `fn_cesar_persona`
   no cesa dentro de un periodo ya pagado ni cuando hay un sueldo posterior al cese;
   `fn_set_fecha_ingreso` no cambia el ingreso si hay jornadas en un periodo pagado;
   `fn_registrar_ausencia` no registra nada que cruce un periodo pagado. Se ensayó entero en un
   Postgres desechable (caso con la estructura y las cifras del real):
   · **0499** (en este PR, con la prueba 393): `fn_persona_liquidada` decía «existe alguna fila de
     liquidación no anulada». Quien se liquidaba y volvía a trabajar quedaba «liquidada» para siempre
     y **desaparecía de las colas «días por revisar» y «marcas apartadas»** (las dos la usan para
     ocultar a quien ya cobró). Medido: sin la 0499 su marca apartada dejaba de verse. Y hallazgo de
     paso: anular la liquidación tampoco la deshacía para esa función, porque la anulación es una
     versión nueva y la original queda con `anulada = false`. Ahora cuenta la ÚLTIMA versión y solo
     si es del cese que la persona tiene HOY. 15 pruebas previas (272 aserciones) idénticas.
   · **El guion de regularización** (4 pasos: diagnóstico, cálculo en seco, escritura, comprobación)
     **nombra a una persona y no vive en git**; se entrega por el chat. La escritura es un solo bloque
     todo-o-nada con más de diez guardas (persona única y activa, ingreso esperado —que frena la doble
     corrida—, fechas coherentes, ninguna marca entre el cese y el reingreso, sin liquidación previa,
     0499 pegada, y el total igual al que se revisó y se pagó).
   · Qué hace: registra la liquidación de la primera etapa en `liquidacion_pagada` (la foto inmutable,
     con su ingreso y su cese) y mueve `fecha_ingreso` al reingreso. **No inactiva a la persona ni un
     instante**: `personas_cese_coherente` no deja una persona activa con cese y forzarlo dispara el
     trigger de educación. No toca los tramos de sueldo ni de horario.
   · **Lo que reveló el diagnóstico real (2026-09-30), y cambió el guion:** `periodos_planilla` no
     tiene ningún periodo entre febrero y el 28/06/2026 —todo lo anterior se pagó por Excel—, el libro
     de desembolsos de esa persona está vacío, y la planilla de julio le pagó S/317.53 de gratificación.
     **`fn_liquidacion` no ve nada de lo pagado antes del 28/06**: su paso 1 («el sueldo pendiente no se
     pudo calcular», grati y CTS «ya depositado S/0») es un TOPE, no lo que se debe pagar; pagarlo tal
     cual puede pagar dos veces. Esto vale para CUALQUIER liquidación de alguien que trabajó antes de esa
     fecha, no solo para este caso.
   · **Cómo se descuentan los pagos previos, medido:** anotarlos en el libro de desembolsos NO sirve aquí.
     Con el escenario ilustrativo (gratificación de diciembre y los S/317.53 de julio) la gratificación
     trunca sale NEGATIVA (−S/77.73, y ese negativo entra en el registro de la liquidación) y Provisiones
     muestra −S/250 de «pagado de más» en gratificación. Causa: un pago de julio cubre las DOS etapas y el
     libro no lo puede partir, y al mover el ingreso esas ventanas dejan de contar el trabajo de la primera
     etapa. La vía que funciona: el guion de escritura recibe lo YA PAGADO por concepto y registra en
     `liquidacion_pagada` los importes NETOS, con el cálculo bruto y el ajuste dentro de `detalle`
     (`regularizacion`). Cada concepto se descuenta por separado y nunca baja de cero: un pago de más en uno
     se anota como «pagado de más no compensado» y no le quita a otro. Sin negativos en Provisiones.
   · Efectos medidos: vacaciones vuelven a empezar (15.0 → ~5 días); la reserva de grati y CTS baja
     en lo que la liquidación paga; la cola de marcas sigue mostrándola; **los periodos pagados no
     cambian** (su foto queda igual).
   · **Riesgo conocido:** el cálculo EN VIVO de un periodo pagado de la primera etapa puede bajar
     (en el ensayo, enero: −S/93.35 por el feriado del 1 de enero, que ya no le corresponde con un
     ingreso posterior). Lo pagado no se toca; solo importa si alguien REABRE ese periodo y lo
     vuelve a pagar. `fn_set_fecha_ingreso` se negaba justo por esto.
3. **Consulta al laboralista** (la opción A no la espera, pero conviene): (a) la liquidación de la
   primera etapa debía pagarse a las 48 horas del cese y hoy está vencida: ¿corren intereses? (b) si
   alguien que se fue sin que se formalizara un cese y volvió conserva su antigüedad; (c) para los
   acuerdos de no venir SIN cese, si esos días cuentan como servicio para el récord vacacional
   (eso es lo único que enciende o no el interruptor de la 0497/0498).
4. **Papeles de la primera etapa, que no son SQL:** la hoja de liquidación y el certificado de
   trabajo del primer periodo, y el contrato de la segunda etapa. El sistema guarda el detalle de la
   liquidación (`liquidacion_pagada.detalle`) pero su pantalla de Liquidaciones lista a quien está
   cesado, así que para alguien activa los papeles hay que armarlos de ese detalle.
5. Lo de las 0497/0498 (licencia sin goce) **se retiró** (ver arriba): no hacía falta para esto y queda en el
   historial de git por si aparece un caso real.

**Lo que esto NO arregla, y conviene no atribuirle:**
- **Sueldo fijo:** la planilla no lee `ausencias` (medido en la 0247). Una licencia sin goce baja
  los días de vacaciones de quien tiene sueldo fijo, pero **no** le baja el sueldo; ese descuento
  hay que hacerlo aparte.
- **La reserva de vacaciones vuelve a cero en el aniversario de calendario** aunque los días
  ganados sigan sin gozar (`vv` mide desde `va.aniv_ini`, `fn_provisiones` 0491). Es un defecto
  aparte y anterior: mientras `fn_vacaciones_resumen` dice «te debemos 15 días», Provisiones
  reserva casi cero. Sale de leer el código; se puede confirmar mirando la columna Vacaciones de
  cualquiera el día siguiente a su aniversario. Sin decidir.
- **`fn_personas_sin_horario_vigente` (0385) ya existía** y ya mide a quien marca sin horario. Lo
  que salió de más en esta revisión —marcas de enero a julio sin horario— es en su mayoría
  historia importada de antes del 10 de julio, cuando `horarios_asignados` todavía no existía; no
  es un defecto nuevo. Las dos personas de Central que siguen sin horario hoy son las que la 0385
  ya documenta como a propósito.

## 2026-09-29 — Casos filtraba `p_desde` contra la medianoche de UTC, no la de Lima · migración 0494 · PEGADA Y VERIFICADA · SIN FUSIONAR

**Origen:** CI (db-tests) del PR #472 reventó la prueba 390 con «con p_desde de mañana, ninguno
califica» — dio 3, no 0. No fue flaky: `fn_casos_resumen` (0493) comparaba `r.creado_at >= p_desde`
con `p_desde date`, y ese `>=` convierte `p_desde` con el cast implícito `date → timestamptz`, que
asume medianoche EN EL TIMEZONE DE LA SESIÓN (UTC en el servidor) y no en Lima. Deja una ventana de
5 horas —19:00 a 00:00 en Lima— donde un reporte de "ayer" en Lima ya contaba como "de hoy". El CI
que falló corrió justo en esa ventana (02:46 UTC = 21:46 Lima del día previo); fuera de ella la
prueba pasa siempre, así que se leía como intermitente sin serlo.

**Arreglo:** ancla `p_desde` a la medianoche de Lima con la misma fórmula que ya usa la 0488
(`(fecha + time '00:00:00') at time zone 'America/Lima'`) — el `+ time` fuerza el tipo `timestamp`
antes de `at time zone`, que sin eso resuelve el overload contrario en silencio (medido: sin el
`+ time`, `date at time zone 'America/Lima'` da la conversión Lima→UTC en vez de UTC→Lima, sin
ningún error que avise). Reproducido y verificado en un Postgres desechable con el instante exacto
del CI que falló, y con la misma fórmula en un instante "seguro" del día — las dos veces con el
resultado correcto. El frontend no cambia: ya manda `p_desde` con `hoyLima()` (`fecha-lima.ts`), el
bug era solo del lado del servidor.

**Pegada y comprobada contra producción (2026-09-29 22:01 Lima, dentro de la ventana que rompía el
filtro):** md5 del cuerpo idéntico byte a byte al del repo (570 car., `f3ac...59f4`), `migraciones_
aplicadas` tiene la 494, y la misma fórmula evaluada en vivo con `now()` de producción dio
`mañana → false` / `hoy → true` — en el peor momento del día para este bug.

**De paso, algo que no toca esta migración:** `fn_set_meta_cobertura` tiene DOS versiones en
`public` (medido con la misma consulta). No es el mismo síntoma de la 0393 —esa función no está en
ningún camino de esta sesión—, pero es la misma familia de accidente (0297/0299) y queda para
revisar aparte.

## 2026-09-28 — La 0393 deja de gritar «MIRA ARRIBA»: ya estaba explicada · SIN SQL · SIN FUSIONAR

**Origen:** `que_falta_pegar.sql` en producción dijo «393 · ⚠️ SOBRA LA FILA» y «⚠️ 1 PEGADAS Y NO
GUARDADAS», y la sesión arrancó a decidir si fusionar el generador de firma o retirarlo. **Esa
decisión ya estaba tomada y medida el 2026-09-08** (entrada de abajo, y `huecos-conocidos.txt`):
contenido superado por la 0395/0398, no se recupera. Lo que fallaba era la consulta, que no tenía
forma de saber que un caso ya estaba explicado y gritó igual durante tres semanas — el aviso que
cazó la 0177, la 0243 y la 0381 estaba aprendiendo a leerse como ruido.

**Qué cambia:** una fila de `huecos-conocidos.txt` con la marca `[sobra la fila: <nombre>]` sale en
la consulta como «ya explicada» y no cuenta para el resumen. La excepción exige número **y** nombre:
si otra migración se pega con el 393, el nombre cambia y el aviso vuelve solo. Probado en un
Postgres desechable: la 0393 real calla; el 393 con otro nombre grita; una huérfana nueva grita
aunque la 0393 esté explicada; sin marcas, igual que antes.

**La rama `claude/signature-generator-function-bd2127` se guardó y se borró (decidido con Felipe el
2026-09-28).** Sin PR, fusionarla habría dejado dos `fn_set_mi_firma` y «Quitar firma» habría fallado
con «is not unique» (comprobado en un Postgres desechable). Mismo caso que la 0108
(`movilidad-supeditada-a-asistencia`, abandonada en agosto): su commit ya no existe en el disco de
ninguna Mac de trabajo, solo lo conservaba GitHub sin garantía. Las dos ramas quedaron con una
etiqueta antes de borrarlas — `archivo/0393-generador-de-firma` y
`archivo/0108-movilidad-supeditada-a-asistencia` — para que el SQL exacto que corrió en producción
(o casi corrió, en el caso de la 0108) sobreviva sin depender de que nadie recuerde un hash de
commit. Ver `scripts/hooks/huecos-conocidos.txt`.

**Pendiente:** re-medir en producción que no haya ninguna `fn_set_mi_firma` de más (la foto es del
09-08) — la consulta va en el PR.

## 2026-09-28 — Las estaciones de Retail dejan de ser personas para Dynamic · migraciones 0490 + 0491 · ESCRITAS Y PROBADAS · SIN PEGAR · SIN FUSIONAR

**Origen:** Datos personales mostraba seis «ESTACIÓN — Caja/Almacén … (no es persona)» como fichas
sin completar. Son las terminales compartidas de cayla-retail (ADR-0160 de ese repo): filas de
`personas` porque retail les cuelga ventas (57 FK) y ACTIVAS porque su acceso lo exige
(`fn_rol_actual` 0374 y 67 comparaciones de retail con `estado = 'activo'`). Marcarlas inactivas
les cortaba las tiendas.

**Lo que costaba, medido en local** (`begin … rollback`, estación creada con los defaults de
`personas`): nacen `en_planilla = true`, `planilla`, sueldo 1130, y **`fn_planilla_calcular` les
ponía S/ 101.70 de EsSalud a cada una** (piso de la RMV) — el mismo síntoma que la 0484, por otra
causa. Además salían en el terminal de marcaje, en la población del Reglamento, en los acuses de la
política salarial, en Contratos y en Documentación.

**Decisiones de Felipe (2026-09-28):** columna propia (no leer `retail.colaboradores.terminal`, no
por nombre); fuera de TODO Dynamic; se les niega la entrada a Dynamic; se ven solo en un bloque
plegado al final de Equipo.

- **[`0490`](../supabase/migrations/0490_una_cuenta_de_servicio_no_es_una_persona.sql)** —
  `personas.cuenta_de_servicio`, puerta `fn_set_cuenta_de_servicio` + trigger (update E insert),
  marca por nombre las que ya existen y saca las cuentas del `terminal_roster`. La puerta se niega
  a esconder a quien tiene marcajes/jornadas, a quien cobró dinero en un mes congelado
  (`total > 0`, no «tiene fila»: una estación congelada queda con S/ 0) o a quien no es
  `integrante`. No reescribe funciones: sin md5 de partida.
- **[`0491`](../supabase/migrations/0491_la_planilla_y_las_listas_dejan_fuera_a_las_cuentas_de_servicio.sql)**
  — `not p.cuenta_de_servicio` en nueve funciones: planilla (núcleo), provisiones, vacaciones,
  población obligada, política salarial, Documentación, Contratos, candidatos de educación,
  boletas. Cuerpos de `pg_get_functiondef` sobre la vigente de cada una, con **freno de md5** que
  acepta sin comentarios y con CRLF. Probado: pasa sobre los originales, pasa con CRLF, bloquea
  con otro cuerpo.
- **Pantallas:** 27 consultas filtran la columna; login, marco del panel y un layout nuevo de
  «Lo mío» rechazan a una estación con sesión; ficha con insignia e interruptor (DO,
  `puedeMarcarCuentaDeServicio`); novedad para el panel.

**Verificado:** pgTAP `388` 17/17 (con control: desmarcada vuelve a la planilla); typecheck;
vitest 1227 + permisos; navegador contra Postgres local con 4 estaciones de prueba (login
rechazado, Datos personales/Equipo/Contratos/Documentación/Horarios sin estaciones, marcar y
desmarcar desde la ficha con su rastro). Hecho en Windows: la base local se construyó desde una
copia LF de `supabase/` (con CRLF la 0311 aborta por su propio freno).

**⚠️ Orden al pegar, y por qué urge:**
1. **La 0491 exige la 0484 en producción** (parte de su `fn_planilla_calcular_nucleo`). Si la 0484
   sigue sin pegar, el freno de la 0491 aborta nombrando esa función — no rompe nada. O se pega la
   0484 primero (decisión ya tomada, ver abajo), o se reconstruye la 0491 desde la versión de
   producción.
2. Pegar **0490 → 0491 ANTES de congelar la planilla del periodo** que cierra hoy: si no, las
   estaciones entran congeladas con su EsSalud. (La 0490 igual las marca —su fila es de S/ 0—,
   pero ese periodo habría que reabrirlo y volver a pagarlo, como el caso de la 0484.)
3. Recién después, fusionar: las listas filtran por la columna.
4. Mirar los NOTICE de la 0490: debe decir 6 marcadas. Una estación con marcajes NO se marca.
5. **De aquí en adelante**, cada estación nueva que se cree para Retail se marca desde su ficha
   («•••» → «No es una persona»). Retail sigue sin saber de esta columna.

---

## 2026-09-27 — Un memo se puede entregar por Info, sin papel · migración 0486 · ESCRITA Y PROBADA · SIN PEGAR · SIN FUSIONAR

**Origen: «ella puede firmar desde Info, o vendría bien un botón de notificar?»** Se investigó y
la respuesta corta fue que ninguna de las dos: desde Info solo se firma un memo YA entregado
(0408: `fn_mis_memos` filtra `estado = 'entregado'`), y un botón de notificar no tenía por dónde
avisar —el sistema no tiene correo, WhatsApp ni push— y habría dado la falsa sensación de haber
notificado, cuando el 56.2 dice que un firmado sin entregar no produce efecto. Felipe decidió que
la entrega digital sí se quiere, **«ambas opciones son válidas, pero estando en tres ciudades lo
digital tiene que ayudar»**, y eso es lo que se construyó.

**Cómo funciona.** Quien emite pulsa **«Enviar a su Info»** (botón visible junto a «Subir cargo
firmado»; ninguna es «la normal»). La persona lo abre en `/mio/memo/<id>`, lo lee y confirma con
**«Firmar y recibir»** o **«Recibir sin firmar»**, cada una con una segunda confirmación. Ese clic
ES la entrega: `estado = entregado`, `medio_entrega = 'digital'`, con fecha y hora. Enviar no
entrega ni agrava; abrir tampoco. Se puede **retirar** el envío mientras no lo haya recibido.
Nivel 4 queda fuera (como en la 0408).

**Migración [`0486`](../supabase/migrations/0486_el_memo_se_entrega_por_info.sql).** Solo agrega:
dos columnas (`enviado_a_info_at/por`), el medio `digital`, cinco constraints que hacen imposibles
los estados absurdos (entrega digital sin envío previo, sin respuesta suya, borrador enviado…) y
cinco funciones. **No reescribe ninguna función existente**, así que no hay md5 de partida. Nadie
puede escribir «digital» en nombre de otro: `fn_expediente_entregar` no lo acepta. Requiere la
**0408 ya en producción** —verificarlo con `./scripts/que-falta-pegar.sh` antes de pegar—.

**Verificado sin tocar el Postgres compartido.** El que hay levantado en esta Mac es el de
**cayla-retail**, no el de este repo. Se levantó un contenedor propio y desechable con la misma
imagen (`supabase/postgres:17.6.1.143`, puerto 54990), se aplicaron las 466 migraciones desde
cero (con `storage.buckets` de mentira: el servicio de almacenamiento no corre) y sobre él:
- Prueba nueva **`384_el_memo_se_entrega_por_info`: 49/49**, con **control**: quitando dos
  constraints, las pruebas de esos estados imposibles fallan.
- **Suite pgTAP entera contra esa base: 277 archivos verdes.** Otros 19 fallan **igual sin la
  0486** (columnas de GoTrue que la imagen no trae, `supabase_migrations`…): huecos del banco de
  pruebas, no regresiones. Comparado uno por uno con y sin la migración.
- Pantallas probadas en el navegador contra las funciones REALES (servidor que imita a PostgREST
  pero ejecuta cada RPC en esa base como rol `authenticated`): el camino de firmar, el de recibir
  sin firmar, la carrera «lo retiraron mientras ella lo tenía abierto», y el envío/retiro desde
  Disciplina. 1227 pruebas de interfaz en verde.

**Un hallazgo que justifica la pantalla nueva.** La pantalla del memo del panel, abierta por una
integrante, **imprimiría al representante legal como firmante** cuando lo firmó su líder de equipo
—la RLS le esconde la ficha de quien firma y esa pantalla cae al valor por defecto—. `fn_mi_memo`
nombra a quien firmó del lado del servidor; por eso la persona no lee el memo con la pantalla del
panel. El papel se extrajo a `components/disciplina/memo-documento.tsx` (commit aparte, sin cambio
de comportamiento, verificado línea por línea contra el original) y lo pintan las dos pantallas.

**Lo que falta, en orden:**
1. **Consultar al laboralista** si la firma de «Mi firma» —que puede ser una imagen, un trazo o
   el nombre en una tipografía— sirve como constancia de recibido. La suposición está escrita en
   la cabecera de la 0486. Puede construirse y revisarse antes; **no conviene usarla con una
   sanción real sin esa respuesta.**
2. Pegar la 0486 **ANTES** de fusionar (`./scripts/dame-el-sql.sh 486`, con el número re-pedido
   con `./scripts/siguiente-numero.sh` y `donde-vive.sh` justo antes de entregar). Si el código
   llega primero, `/mio` muestra el aviso rojo «no se pudo traer tus documentos por recibir» a
   todo el equipo.
3. Sin canal de aviso: la persona se entera al abrir Info, o cuando quien lo envió se lo dice.
   Por eso existe «Copiar el aviso para ella» en el menú (texto genérico, sin nombrar de qué es).

## 2026-09-27 — La constancia de una practicante ya muestra su descanso y su subvención semestral · SQL YA PEGADA

**Origen: Felipe adjuntó su propia constancia de subvención (Benjamin Cueva, OTRU) y avisó que
«hay otro tipo de beneficios pero no se están mostrando».** Investigado sin adivinar: se confirmó
con `AskUserQuestion` que se refería al descanso de 15 días y la media subvención semestral de la
Ley 28518 art. 42 — la 0465/0467 (2026-09-15) YA los calcula, pero solo en la pantalla de
Provisiones (que ve DO); el documento que la propia persona se lleva seguía sin decir nada, y su
texto legal del pie afirmaba «este sistema todavía no los calcula», que ya era falso.

**Migración nueva: [`0485`](../supabase/migrations/0485_el_practicante_ve_su_descanso_y_subvencion_semestral.sql),
pegada por Felipe el 2026-09-27 (`migraciones_aplicadas` confirma numero y nombre).**
Crea `fn_mis_subvenciones_practicante()` — la misma fórmula que `fn_subvenciones_practicante`
(0467), copiada para una sola persona (quien llama, vía `fn_persona_actual_id()`), sin exigir
admin/líder. Prueba pgTAP nueva: `383_el_practicante_ve_su_descanso_y_subvencion_semestral`
— corrida aislada contra el Postgres local (`BEGIN … ROLLBACK`, sin tocar la base compartida):
10/10 en verde.

**Por qué una función hermana y no una reescritura:** `fn_subvenciones_practicante` exige
`fn_es_admin_o_lider()` a propósito (es la que usa DO para ver a TODAS las practicantes); tocar su
guard para que una practicante se vea a sí misma es el peor lugar para un error de permisos. Mismo
molde que ya usa este repo dos veces: `fn_planilla_calcular` junto a `fn_planilla_calcular_persona`
(0329), y `fn_bonos_por_transferir` junto a `fn_mi_bono_cumpleanos` (0478).

**Frontend:** [`boleta-hoja.tsx`](../apps/web/components/boleta-hoja.tsx) gana dos filas nuevas
dentro de «Además, CAYLA paga por ti» —solo si hay algo devengado— y corrige el texto legal del
practicante. Las dos pantallas que imprimen este documento (`/mio/boleta` y
`/admin/planilla/boleta`) piden el dato aparte y con el mismo criterio de siempre: si la consulta
falla, la constancia sigue saliendo sin esas dos líneas, no se cae. `typecheck` y los 1219 tests de
vitest, verdes. Novedad agregada (`2026-09-27-constancia-practicante-descanso-y-subvencion`).

**No paga nada solo.** Igual que hasta hoy: Felipe decide cuándo se transfiere: la constancia ahora
lo hace VISIBLE, no lo pone en la planilla.

---

## 2026-09-27 — El período de prueba deja de generar EsSalud · migración 0484 · SIN PEGAR

**Disparado por el cierre «Prueba» del periodo 29/08–27/09/2026** (pagado el
27/09): 6 personas —Ana Huaccha, Angie Vizcarra, Geison Alcantára, María Vera,
María Orbegoso, Steven Cruz—, todas con `fecha_ingreso` Y `fecha_cese` DENTRO
de ese mismo periodo (de 0 a 25 días activo sobre 30), generaron S/101,70 de
EsSalud cada una — S/610,20 en total. Angie ni siquiera marcó una hora:
ingresó y cesó el mismo día.

**Verificado contra producción (`vovjyyiafkxteijimpuy`) antes de escribir
nada:** la foto congelada de ese cierre no tiene ninguna fila duplicada — el
número es exactamente `6 × S/1.130 × 9 %`, el piso de la RMV aplicado
completo y sin prorratear a las 6, por diseño de `fn_planilla_calcular_nucleo`
(el piso solo se prorratea por días de subsidio, 0262 — nunca por
entrada/cese a mitad de periodo, y la 0417 lo dice explícito: «no se tocó»).

**Esto NO es el «riesgo de RMV» ya descartado dos veces** en
`planilla-anexo-tecnico.md`: ese descarte es sobre alguien de planilla que
trabaja el mes COMPLETO con turno reducido. Este caso es alguien cuyo vínculo
entero —ingreso y cese— cupo dentro de un solo periodo de prueba.

**⚠️ Decisión de Felipe (2026-09-27), con el riesgo legal explicado y
aceptado:** `tipo_vinculo = 'prueba'` deja de generar EsSalud, punto — no solo
prorratearlo, no solo excluir a quien no llegó a trabajar. Se le planteó que
la ley (D.S. 009-97-SA) no hace esa excepción para el período de prueba, que
solo protege contra el despido injustificado, y que dejar de declarar es una
subdeclaración real frente a SUNAT. Decidió igual, con las 6 personas del caso
real como alcance. Ver el encabezado de la
[`0484`](../supabase/migrations/0484_el_periodo_de_prueba_deja_de_generar_essalud.sql)
para el detalle completo.

**Auditado contra Postgres local** (`BEGIN … ROLLBACK`, nunca `db reset`):
prueba pgTAP
[`382`](../supabase/tests/382_el_periodo_de_prueba_no_genera_essalud.test.sql),
con control — la misma prueba SIN el cambio falla exactamente en los dos
casos de `'prueba'` (101.70 en vez de 0) y el testigo de planilla no se mueve.

**Pendiente, y es decisión de Felipe, no de esta migración:** el periodo ya
pagado (27/09) NO se corrige solo. `planilla_pagada_detalle` es append-only;
para que esos S/610,20 ya pagados bajen a S/0, hay que **pegar la 0484
primero** y después **reabrir «Prueba» de ese periodo desde Planilla y volver
a pagarlo** — dos pasos, en ese orden.

---

## 2026-09-20 — Un feriado sin turnos ya no grita en rojo: el Dashboard pregunta «¿abre hoy la sede?» · SIN SQL · FUSIONADA (#453 → rescatada por #454)

> **Corregido el 2026-09-25 al fusionar `main` en el PR #449:** decía «SIN
> FUSIONAR». El #453 se fusionó el **21-set 09:36 de Lima**, pero sobre la rama
> del #451 y no sobre `main`: quedó varado hasta que el **#454** lo llevó, siete
> minutos después. O sea que el aviso de abajo —«se fusiona DESPUÉS de #451»— se
> cumplió, y aun así hizo falta un PR de rescate. Está publicado.

**No hay SQL: solo pantalla. Apilado sobre el PR #451** (la entrada de abajo): su rama es la base de
este PR, así que **se fusiona DESPUÉS de #451**. Fusionar es publicar. **El próximo feriado es el
jueves 2026-10-08.**

**Nació de una revisión de código** que señaló que `esperadoDelDia` no sabe de feriados mientras
`fn_faltas` sí. **Verificado: el hallazgo es real, pero el arreglo sugerido —hacer que la cascada
diga `trabaja:false` en feriado— rompe más de lo que arregla, y no se hizo.** Lo que se midió:

- La base solo condiciona a «hay turno explícito» el ACUSAR: `fn_faltas` no cuenta falta un feriado
  sin turno (0051, 0070, vigente en la 0414). Pero `fn_recalcular_jornada` (0446) no nombra los
  feriados: mide tardanza y horas contra el horario base también en feriado —decisión de Felipe del
  2026-08-18, con datos: **22 de 25 feriados trabajados no tenían ni un turno**, o sea que las sedes
  abren con su horario normal (`hallazgos-abiertos.md`, A4)—.
- Si la cascada dijera «feriado ⇒ no trabaja»: quien vino un feriado pasaría de «ok» a «extra» en
  Horas y Mío (probado), y Correcciones diría «ya no hay horario: alguien lo cambió» en cada
  jornada trabajada en feriado (`correcciones/page.tsx:1187`). Y silenciaría la alarma justo cuando
  la sede abre, que es el caso común.

**Lo que se hizo.** Dos preguntas distintas que la base mantiene separadas y la revisión mezclaba:
«¿qué le tocaba?» (`esperadoDelDia`, **intacta**, con una prueba que fija por qué) y «¿se le puede
exigir?» (`esFeriadoSinTurno`, gemela de la cláusula de `fn_faltas`).

- **Dashboard** (decisión de Felipe: aviso ámbar que pregunta). Feriado, sin turnos, nadie marcó y
  ya pasó la hora → en vez del rojo «Sin marcajes» y «Cobertura insuficiente», ámbar
  **«Feriado · ¿abre hoy?»**, y por persona **«Feriado · le tocaba 08:00»** en neutro y sin enlace a
  Correcciones. No cuentan en «sin marcar y ya les tocaba»: el número coincide con lo que acusa la base.
- **Hoja de sede impresa:** la línea de cobertura de HOY se apaga con la palabra «Feriado» y «no se
  sabe si la sede abre hoy». No dice «a nadie le tocaba»: por horario les tocaría, y en un papel que
  se firma sería falso.
- **`diaDeLaSede`** gana una cuarta respuesta, `feriado_sin_confirmar` («no se sabe si abre»).
- **Incidencias NO cambia**, aunque el alcance elegido lo incluía: «Déficit de líderes» es una
  alarma de planeación y en un feriado con horario base contesta «cubierto», la dirección segura.
  Se dejó escrito en su código para que nadie la «complete» por simetría.

**Se conserva el rojo** donde debe: si alguien armó el turno del feriado, o si el dato no se pudo
leer (falla la consulta de feriados, de turnos o de horarios), la alarma es la roja de siempre. Una
duda cae hacia la alarma, no hacia el silencio. Se probó con mutaciones: cada regla nueva rota a
propósito hace caer alguna prueba.

**Límites conocidos, no resueltos:**
- **Demote de una alarma real.** En un feriado en que la sede SÍ abre y la Mac mini no está
  marcando, el aviso es ámbar y no rojo: una falla real tarda más en notarse. Es el precio de no
  gritar en los feriados que cierran, y es lo que se eligió.
- **`feriados` es global, sin sede.** No se puede decir «TRU abre y LIM no». Por eso se pregunta.
  La respuesta que no adivina sería una tabla por sede, con un hábito que los datos dicen que no
  se cumple: se descartó.
- **Con la sede abierta a medias** (alguien marcó, otros no) la meta se mide como cualquier día y
  puede seguir en rojo «faltan N», aunque a los que no llegaron ya no se les acuse individualmente.
- **La discrepancia RIT 17.3 ↔ práctica sigue abierta** (Consulta 5 al laboralista). Si obliga a
  cambiar la práctica, cambia la base y la cascada a la vez.
- **Visto en un navegador (2026-09-21), pero con un backend SIMULADO.** El panel no levanta aquí
  sin Docker ni `.env.local`, y ese Postgres es uno solo para ~10 worktrees, así que se miró con
  un simulador de la API (fuera del repo, con personas inventadas). Se vieron los tres casos en el
  Dashboard —sede sin turnos (ámbar), con turnos armados (rojo conservado), con la líder ya
  marcada (se mide normal)—, el mismo día con el feriado apagado (vuelve al rojo de siempre), con
  la consulta de feriados fallando (vuelve al rojo y la página no se cae) y la Hoja de sede de
  TRU. De ahí salieron dos textos que se corrigieron. **No prueba SQL, RLS ni el flujo real con
  Supabase**, y **falta verlo con datos reales** antes de publicar. 1219 pruebas, con mutaciones.
  Tras fusionar #452 (que reindentó la sección «Hoy» de la Hoja de sede) no se volvió a mirar esa
  pantalla en un navegador: el simulador se perdió con un reinicio de la sesión.
  El simulador no está en el repo: si se quiere repetir, hay que decidir si se guarda en `scripts/`.

---

## 2026-09-20 — Un día en que la sede no tiene turnos ya no se lee como una falla · SIN SQL · FUSIONADA (#451)

> **Corregido el 2026-09-25 al fusionar `main` en el PR #449:** decía «SIN
> FUSIONAR». El #451 se fusionó el **20-set 21:12 de Lima** y su rama NO se
> borró — por eso el #452 y el #453, apilados encima, siguieron apuntando a ella
> y su código no llegó a `main` hasta el #454.

**No hay SQL: solo pantalla.** Fusionar es publicar (`main` se despliega sola). Nació de un
domingo: el Dashboard decía «Sin meta configurada» de tres sedes que no abren, y «Cobertura
insuficiente · falta 1 líder» de Central, donde a nadie le tocaba ir. **La misma falsa alarma
salía en cuatro pantallas**, y las cuatro se corrigieron con UNA pregunta compartida.

- **`diaDeLaSede`** (`lib/admin/jornada-esperada.ts`): «¿a alguien de la sede le toca ese día?».
  Tres respuestas: `trabaja`, `no_trabaja` (a nadie, **con al menos UNA respuesta real de descanso**)
  y `sin_horario` (no se sabe). Solo `no_trabaja` autoriza a callar o bajar una alarma; con todos
  sin horario cargado —un tramo venció, sede nueva— todo sigue como estaba. Una auditoría demostró
  que tratar «sin horario» como «descansa» bajaba un rojo a ámbar con un texto falso.
- **Dashboard.** Sede sin turnos y con meta 0 → gris **«Sin turnos»**, al final de la lista, sin
  recuadros de ceros ni barra vacía. Con meta y sin turnos → ámbar **«Meta sin turnos»** (no cuenta
  en «Sedes bajo la meta»). «Sin meta configurada» pasó a **«Sin meta hoy»**: en Turnos un 0 puesto
  a propósito y uno nunca tocado se ven igual, así que decir «configurada» podía ser falso.
  «Sedes bajo la meta» dice sobre cuántas sedes se mide («de 1 que se mide hoy»).
- **Incidencias:** no emite «Déficit de líderes» un día en que a nadie de la sede le tocaba.
  **Hoja de sede impresa:** la línea de cobertura de HOY se apaga en gris con la misma palabra.
  **Turnos:** con las tres metas del día en 0 y nadie programado dice «Sin turnos» una vez, en vez
  de «sin operativas programadas» y «sin líderes programados». Con meta > 0 y nadie programado
  **Turnos sigue en rojo** (ahí sí alguien olvidó armar los turnos): es la decisión vigente.
- **Palabra elegida por Felipe:** «Sin turnos» (entre «Descanso», «No labora», «Fuera de actividad»,
  «Sin operación»…). Vive en una constante, `SEDE_SIN_TURNOS`.

**Costos conocidos, aceptados y escritos en el código** (`CoberturaSede`, `incidencias.ts`):
1. Una tienda que SÍ debía abrir, con meta y sin turnos armados, baja de rojo a ámbar en el
   Dashboard y **deja de avisar en Incidencias** (incluida la semana siguiente). Solo la ven
   «Requiere atención» y el rojo de Turnos. No existe una hora de apertura por sede con qué escalarla.
2. Quien viene en su día libre y marca deja de contar la sede como «sin turnos»: se mide contra
   su meta (una persona contra meta 2 sale en rojo). Es lo pactado: si alguien trabajó, abrió.

**Pendiente, y no es de código.** **Central tiene meta de 1 líder el domingo** y ese día nadie
tiene turno (Central trabaja lunes a sábado; el domingo es opcional). Hasta que se ponga en 0
sale ámbar «Meta sin turnos». **Se arregla en Turnos → Central → vista Día → domingo → «Líderes» = 0**;
la meta es por día de la semana, así que vale para todos los domingos. Solo la puede editar quien
ve todas las sedes (admin, DO). Con eso pasa sola a gris en las cuatro pantallas.

**Pendiente de código, aparte** (sugerido, sin hacer):
- **Los feriados no entran en «le tocaba trabajar».** El backend decidió (0051/0070) que «feriado
  no cuenta salvo turno explícito» y `fn_faltas` lo aplica; `esperadoDelDia` y el Dashboard no
  saben de feriados. Una tienda que cierra en feriado (horario base «trabaja», sin turno puntual)
  sale con «Sin marcajes desde las 8:15» en rojo crítico. No lo introdujo este cambio.
- ~~**Hoja de sede de un periodo cerrado:** su recuadro «Hoy» se calcula con las jornadas del rango,
  así que en un periodo ya cerrado dice «Nadie está trabajando» y pinta «faltan N» en rojo en un
  papel que se archiva.~~ **Hecho, sin fusionar** —rama `claude/hoja-sede-periodo-cerrado-sin-hoy`,
  un PR apilado sobre este (su base es la rama de este PR; al fusionarse este, GitHub lo reapunta a
  `main`)—. **Decidido por Felipe el 2026-09-20: el recuadro «Hoy» se OCULTA** cuando el rango termina
  antes de hoy, y no se trae «hoy» aparte. Razón: la hoja de un periodo cerrado describe ese periodo
  —«Necesita atención» ya medía con el fin del rango, no con hoy—; traer «hoy» archivaría en la hoja del
  periodo X el estado de un día que no es X, fotografiado a la hora de imprimir. En pantalla queda una
  línea que dice por qué no aparece (no sale en el papel). Lo decide la misma `hojaIncluyeHoy`
  de arriba, para el recuadro y para su línea de cobertura. **No se vio en pantalla con datos reales:**
  falta abrir la hoja de una sede con «Hasta» anterior a hoy y comprobar que no hay recuadro «Hoy»
  ni rojo, y con «Hasta» = hoy que sigue como siempre.

**Cómo se verificó, y qué NO.** Pruebas (1163 en verde, con controles de mutación a mano por cada pieza),
`tsc` y `eslint` sin errores nuevos. **Se vio en pantalla** con un servidor de datos simulado
(no está en el repo): Dashboard un domingo y un martes, claro/oscuro/celular, la caída de horarios,
Turnos, Hoja de sede e Incidencias. **No se probó con datos reales de producción:** falta comprobar
que las personas de CCO, AQP, LIM y OTRU tienen un horario vigente hoy (si una sede no tiene
ninguno, el sistema NO la apaga en gris: dice «Sin meta hoy» o sigue en rojo, y eso sería verdad:
no hay horarios cargados).

---

## 2026-09-19 — Boletas oficiales: los archivos no tenían respaldo, y quedan la consulta y la prueba real escritas · SIN SQL · SIN FUSIONAR

**No hay SQL: solo un script, dos documentos y dos textos.** Sale de revisar la 0482
(boletas oficiales) contra el código, no de una falla en producción.

**El hallazgo que importa.** Los archivos de las boletas viven solo en el bucket
«boletas»; la base guarda quién publicó y cuándo confirmó cada persona, pero no el
documento. La guía de restauración cubre `--schema=public` y deja `storage` fuera a
propósito, y por lo que se sabe de Supabase su respaldo diario de la base tampoco lo
incluye (**confirmarlo en la consola del plan**). Si Storage pierde un archivo, la
constancia queda apuntando a nada y el archivo no se puede regenerar.

- [`scripts/respaldar-boletas.sh`](../scripts/respaldar-boletas.sh) baja el bucket a
  una carpeta fuera del repo, comprueba el conteo contra lo que Storage lista y deja un
  manifiesto sha256. Sección nueva en
  [`prueba-restauracion-backup.md`](prueba-restauracion-backup.md). **Se probó con un
  CLI de mentira (10 casos: copia incompleta, descarga que falla, bucket vacío,
  destino dentro de git, manifiesto que detecta una alteración). NO se corrió contra el
  CLI real ni contra producción:** el formato de `storage ls -r` es lo primero que
  puede no coincidir, y si pasa falla en voz alta. Nadie ha hecho la primera copia
  real, ni probado restaurar un archivo.
- La 0482 decía «si Storage no responde, la persona sigue viendo lo ya publicado»:
  falso, los archivos están en Storage. Corregido el comentario del encabezado (no
  cambia ninguna función; no hay nada que repegar).
- El aviso del editor ofrecía «HEIC» y en Chrome un HEIC falla. Ahora lo dice.
- [`consulta-boletas-de-pago.md`](consulta-boletas-de-pago.md): 8 preguntas al
  laboralista (plazo de entrega, validez de la entrega electrónica, conservación,
  cesados, entrega equivocada…) y 5 al contador. Sin normas citadas de memoria.
- [`probar-las-boletas-oficiales.md`](probar-las-boletas-oficiales.md): recorrido A–H
  con una boleta propia de un periodo ya pagado.

**Lo que se propuso y NO se hizo, y por qué:** el aviso por correo (Resend existe,
pero su código avisa que sin `RESEND_FROM` verificado solo llega al dueño de la
cuenta: comprobar el dominio primero); el cruce con el neto del contador y un canal de
«tengo una observación» (los dos piden SQL nuevo); la carga por lote (depende de cómo
entrega el contador, pregunta A); el aviso en la Bandeja de DO de «sin abrir hace más de
3 días».

**Pendiente, por orden:** (1) la primera prueba real (guía de arriba), sigue siendo lo
primero; (2) la primera copia real con el script; (3) enviar la consulta.

**Aparte, y de planilla:** [`hallazgos-abiertos.md`](hallazgos-abiertos.md) daba por
abiertos cinco defectos 🔴 de la tabla del 05-set que ya tienen migración (0416, 0417,
0418, 0419) y cuatro viñetas más (0283, 0278, 0346, el CSV rehecho el 15-set). Quedan
tachados **como cerrados en el código, no en producción**: lo que falta es confirmar
con la línea PLANILLA de `que_falta_pegar.sql` que producción corre la versión vigente
del núcleo (la 0463 trae la 0416, 0417 y 0418), y aparte que estén la 0419
(`fn_feriados_laborados`), la 0278/0283 (truncas) y la 0346 (`fn_grati_cts_periodo`).
Una lista armada solo con esa tabla se equivocó en casi todo.

---

## 2026-09-19 — Incidencias: el lote pide confirmación y dirección sale del exceso · SIN SQL · FUSIONADA (#447)

> **Corregido el 2026-09-19 19:42:** decía «SIN FUSIONAR». Se fusionó a las
> **23:33** del 19-set —y fusionar es publicar—, así que esto ya está en
> producción. **Sigue sin verse en pantalla:** lo de abajo («conviene mirar la
> confirmación del lote y la columna de casillas a 375 px, también en modo
> oscuro, antes de fusionar») se quedó sin hacer y ahora se hace sobre
> producción, no antes de publicar.

**No hay SQL: solo pantalla.** Fusionar es publicar (`main` se despliega sola). Cierra lo
que la auditoría de `/admin/incidencias` del 2026-09-19 dejó decidido y que `main` aún no
tenía. Los otros siete arreglos de esa auditoría (lecturas que fallan, respuesta vigente,
«hoy» renovable, orden único, déficit con `cuentaEnCobertura`, sede con `etiquetaDeSede`,
rastro en hora de Lima) **ya estaban fusionados** por otra sesión: una primera versión de
esta rama los repetía y se descartó al integrar `main` (queda respaldada en la rama local
`respaldo-incidencias-4b0b826c`, que no se sube).

- **El lote de excesos y rachas se mantiene (decisión de Felipe), con confirmación:** lista
  nombre, sede, fecha y horas o días, dice que es un incumplimiento de la empresa, y que la
  compensación (recargo 0185, sobretasa 0280) se paga en planilla y esta constancia no la
  comprueba. Los textos del visto bueno individual dicen lo mismo.
- **Personal de dirección fuera del aviso de exceso de 48 h** (decisión de Felipe); sigue en
  la racha sin descanso, que es otra norma y sí se le paga.
- **En celular se elige caso por caso** para el lote (antes solo existía «todas»).
- **Si los vistos buenos no se pudieron leer, el lote se apaga:** sin verlos, todo lo revisado
  reaparece como pendiente y el lote lo reemplazaría en silencio.

**Cómo se verificó, y qué NO:** pruebas, `tsc` y `eslint` en verde, y una mutación a
propósito de la exclusión de dirección que la prueba nueva atrapó. **No se vio en pantalla**
(sin `.env.local` ni pila local): conviene mirar la confirmación del lote y la columna de
casillas a 375 px, también en modo oscuro, antes de fusionar.

## 2026-09-19 — Las boletas oficiales se suben y se publican (0482) · MIGRACIÓN PEGADA Y VERIFICADA · FUSIONADA · PANTALLAS SIN PROBAR

**Hay SQL: la [0482](../supabase/migrations/0482_las_boletas_oficiales_se_suben_y_se_publican.sql),
PEGADA Y VERIFICADA en producción el 2026-09-19.** La consulta de comprobación
devolvió `4 | 11 | 4 | 1 | 4 | 482 · las_boletas_oficiales_se_suben_y_se_publi…`
(4 tablas, 11 funciones, 4 políticas de Storage, bucket privado, RLS en las 4) y la
de permisos: en las cuatro tablas `authenticated` solo lee (`true`), no escribe
(`false`) y `anon` no ve nada (`false`) — el `revoke` hizo su trabajo.

**Ojo con el orden en que pasó, porque no fue el que manda CLAUDE.md.** El PR
[#442](https://github.com/felipea92p-ux/cayla-dynamic/pull/442) se **fusionó a las
23:12 UTC (18:12 en Lima), antes de pegar la migración**: `main` desplegó el código
de las boletas con `fn_mis_boletas` todavía inexistente en producción, durante unos
minutos, hasta que se pegó el SQL. Es exactamente lo que la regla «la migración se
pega ANTES de fusionar» evita (la Bandeja de todas las personas pudo mostrar
«Falta tus boletas» en rojo). No se reportó daño: las pantallas eran nuevas y nada
del marcaje ni de la planilla lee estas tablas. CI (`db-tests`, 293 archivos y
3 089 aserciones, incluida la prueba 380) estaba en verde antes de fusionar.

Felipe pidió que DO suba las boletas de pago y que cada persona las vea y las
descargue. **No es la boleta calculada** (`/mio/boleta`, `BoletaHoja`): es la del
contador, en foto o PDF, de una o varias hojas. La calculada no se tocó.

Decisiones de Felipe (2026-09-19): la oficial manda; DO la sube persona por persona
y pulsa «Publicar»; aviso en la Bandeja y globito en el menú; todas las personas
reciben boleta (practicantes incluidos); se guardan la publicación, la primera
apertura y «Confirmar que la recibí»; tope de 500 MB por boleta y 50 MB por archivo,
sin tope de hojas; DO trabaja desde celular y computadora.

- **La forma:** archivo (inmutable) → versión (lista ordenada de hojas, solo se
  agrega) → boleta (una por persona y periodo). `boletas`, `boletas_versiones`,
  `boletas_partes`, `boletas_acuses`. Editar es crear la versión N+1.
- **El acuse cuelga de la versión:** confirmar no cae sobre lo que no se vio, y la
  constancia anterior no se borra cuando cambian el documento. **Confirmar exige
  haberla abierto**, y lo exige la base.
- **Si cambió el contenido de una boleta publicada, avisar es obligatorio** aunque
  DO diga que no; solo se puede omitir cuando únicamente se reordenó. Felipe no
  eligió entre «siempre avisar» y «casilla»: se construyó la **casilla con ese
  guardarraíl** (era la recomendación). La base soporta las dos: cambiar es
  pantalla.
- **Quién ve qué archivo:** DO todo; la persona solo la versión vigente y publicada
  de una boleta suya. Un archivo que una versión usa no se pisa ni se borra.
- **Sin cuenta:** DO anota «entregada en papel». **No hay forma de saber cuántas
  personas activas tienen cuenta** sin correr en producción:
  `select count(*) filter (where auth_user_id is not null), count(*) from personas
  where estado = 'activo' and en_planilla;` — pendiente.

**Cómo se verificó, y lo que NO:**
- Prueba pgTAP [380](../supabase/tests/380_las_boletas_oficiales_se_suben_y_se_publican.test.sql)
  (86 aserciones): **pasa en CI contra una base real de Supabase** (`db-tests`). Antes
  se había corrido solo contra un Postgres temporal de Homebrew con un andamio
  mínimo (Docker Desktop no respondía); esa versión falló en CI por un error de la
  PRUEBA —la persona inactiva sin `fecha_cese`, `personas_cese_coherente` de la
  0086— y no de la migración, que se aplicó bien en esa misma base. Se sabotearon a propósito tres reglas
  (abrir archivos ajenos, ignorar el aviso obligatorio, confirmar sobre una versión
  vieja) y la prueba las detectó. Queda sin saberse si Supabase rechaza un `delete`
  directo sobre `storage.objects` (la prueba no depende de eso).
- 1 027 pruebas de vitest, typecheck y linter: verdes. **Ninguna pantalla se vio en
  un navegador** (no hay `.env.local` ni Supabase local): el responsive, la
  subida real, el giro y la compresión de fotos, el visor y el modal en celular
  están comprobados solo por tipos y lectura. Hay una demo aprobada en un
  artefacto de Claude, no en el repo.
- No se reescribió ninguna función existente: no hay md5 de partida que medir.

**Pendiente, por orden:** (1) **la primera prueba real** —una sola boleta propia de
Felipe, subida, publicada, vista en `/mio` y confirmada—: ninguna pantalla se ha visto
funcionando, y **todo lo que se sube queda para siempre** (archivos y versiones no se
editan ni se borran, solo se anulan con motivo), así que no se prueba con las
boletas del equipo; (2) correr las pantallas con la base local (`.env.local` + `supabase
start`); la novedad para el equipo ya está en `novedades.ts`; cuántos meses hacia
atrás cargar y el plan de almacenamiento de Supabase (≈ 180 MB/año con fotos
reducidas, techo de 500 MB por boleta). «Septiembre» (Planilla) y «setiembre» (el
resto de `/mio`) conviven en estas pantallas: el repo ya estaba dividido.

---

## 2026-09-19 — La Tienda de Lima sabe su ciudad (0481) · PEGADA Y VERIFICADA · FUSIONADA (#439) · ⚠️ AL REVÉS DEL ORDEN

**Esta entrada no existía**; se escribe el 2026-09-19 19:42, al descubrir que la
migración estaba en producción y ningún archivo de este repo lo decía.

La sede `003` («Tienda LIM») tenía `ciudad` en NULL porque nació después de la
0279 y el formulario de /admin/sedes no pide ciudad. Sin ella, `etiquetaDeSede`
dejaba a las dos sedes de Lima con dos formatos. Confirmado en producción:
`ciudad = Lima`, y el registro `481 · la_tienda_de_lima_sabe_su_ciudad`.

**⚠️ Se fusionó ANTES de pegarse, y es el caso real de la regla rota ese día:**
fusionada a las **15:18:00**, pegada a las **17:07:21**. **Una hora y
cuarenta y nueve minutos** con el código en el aire por delante de su base.

No hubo daño y conviene decir por qué, para no aprender la lección equivocada:
`etiquetaDeSede` cae al nombre de la sede cuando no hay ciudad, así que durante
esas dos horas las dos sedes de Lima se rotularon con dos formatos — feo, no
roto. Si la 0481 hubiera tocado plata, esas dos horas no habrían sido cosméticas.
Es la misma ventana que la 0404 y la 0407, con mejor suerte.

Y la sede **sigue inactiva a propósito**: reactivarla es un clic en /admin/sedes
y es decisión de quien la abre, no de una migración.

## 2026-09-19 — Anuncios cuenta qué mejora en el sistema, y «Lo mío» las muestra · MIGRACIÓN 0480 PEGADA Y VERIFICADA · FUSIONADA (#438) · EN EL ORDEN CORRECTO

> **Corregido el 2026-09-19 19:42:** este encabezado decía «SIN FUSIONAR» y era
> falso desde las 09:50. Pegada a las **09:40:58**, fusionada a las **09:50:42**:
> nueve minutos y cuarenta y cuatro segundos, en el orden correcto. Confirmado en
> producción: `480 · las_novedades_del_sistema_se_marcan_como_vistas`.

**Hay SQL: la [0480](../supabase/migrations/0480_las_novedades_del_sistema_se_marcan_como_vistas.sql),
PEGADA Y VERIFICADA en producción el 2026-09-19** (antes de fusionar, como
manda el orden). La consulta de comprobación devolvió
`1 | 1 | true | 480 · las_novedades_del_sistema_se_marcan_como_vistas`, y la de
permisos: `authenticated` solo con `SELECT`, `anon` sin nada, `postgres` y
`service_role` con todo (lo normal) — el `revoke` hizo su trabajo. Es una tabla y
una función nuevas: no reescribe ninguna función existente, así que no hay md5
de partida que medir. **Fusionar es publicar** (`main` se despliega sola), y las
cinco entradas iniciales son texto que leerá el equipo entero: conviene leerlas
antes.

Se pidió que Anuncios «anunciara mensajes preestablecidos y, cada vez que hay
una mejora o actualización, explicara qué mejoró», y después que también
aparecieran en «Lo mío». Se leyó como una sección de novedades del sistema,
aparte de los comunicados de DO, y no como plantillas para que DO publique
(esa lectura queda sin construir).

- **Dónde vive la lista:** `apps/web/lib/novedades.ts`, escrita a mano dentro
  del código, con su encabezado de qué va y qué no. Sale con el mismo despliegue
  que la mejora que cuenta; una fila en `anuncios` exigiría una migración y el
  aviso saldría antes que la mejora.
- **Dónde se ve:** al final de `/admin/anuncios` (todas las de la persona, con
  «Nueva» y «Entendido») y en «Lo mío» tras los comunicados (las tres más
  recientes que le faltan, con su primer párrafo). Marcar en una apaga en la otra.
- **Qué guarda la base:** solo quién entendió cada una (`novedades_vistas`,
  `fn_marcar_novedad_vista`). Tabla propia, no `bandeja_vistos` (su `item_id` es
  `uuid` y su `check`/función se reescriben en cada migración de la Bandeja) ni
  `anuncios_leidos` (llave foránea a `anuncios`). Lectura solo de las propias
  marcas; escritura solo por la función; `do nothing` para no correr la fecha de
  la primera vez.
- **Quién ve qué:** `puedeVerNovedad` en `permisos.ts` (`todos` / `panel` /
  `do`). Una integrante ve 2 de las 5; la líder de equipo y DO ven las 5. Es
  relevancia, no secreto: el texto baja al navegador de todos.
- **«Nueva»:** de los últimos 14 días y sin entender, en un solo sitio
  (`esNovedadPendiente`). Antes era solo por fecha; cambió al pedirse «Lo mío»,
  donde una tarjeta que no se puede descartar se aprende a ignorar.
- **Regla nueva en CLAUDE.md** («Novedades del sistema»): un cambio que se
  nota lleva su entrada en el mismo PR. **Nada la obliga**; si se olvida, la
  sección envejece y le cuenta al equipo que nada mejora.

**Cómo se verificó, y qué NO:**
- **La prueba pgTAP 379 (19 aserciones) no corrió en pgTAP real.** Docker
  Desktop estaba colgado (error 500 del socket) y la base local no respondía.
  Se ejecutó en un Postgres 17 desechable de Homebrew, con un sustituto mínimo
  de pgTAP escrito para esto y **con los permisos por defecto de Supabase
  emulados** (ver la 0315): 19 de 19, la migración pegada tres veces sin error,
  y mutaciones a propósito (volver a marcar corre la fecha, sin `check`, policy
  abierta, **sin el `revoke`**) cayeron cada una en la aserción prevista.
  **La señal fiable sigue siendo `db-tests` de GitHub Actions al abrir el PR.**
- **Lo que la primera versión no vio, y por qué importa:** la base desechable no
  tenía los permisos por defecto de Supabase, que le dan a `authenticated`
  escritura —incluido `truncate`, que no pasa por RLS— sobre toda tabla nueva de
  `public`. Con ellos, dos aserciones habrían puesto el CI en rojo, y sin el
  `revoke` que ahora lleva la 0480 una persona logueada vaciaba la tabla. RLS ya
  bloqueaba insert/update/delete; el hueco era `truncate`, alcanzable solo por
  SQL directo (PostgREST no lo expone). Regla que deja: **una base desechable
  para probar permisos tiene que traer los permisos por defecto del motor real.**
- **`packages/database/src/types.ts` está editado a mano** (tabla y función,
  imitando el formato generado). Cuando Docker vuelva, regenerarlo con
  `gen-types` y comprobar que no cambia nada más que esto.
- 915 pruebas (35 nuevas), typecheck limpio, lint de lo tocado sin errores
  nuevos (los 2 de `mio/page.tsx` ya estaban en `HEAD`).
- **No se vieron las páginas reales**, el panel no levanta sin `.env.local`. Se
  dibujaron las dos piezas en una ruta temporal (ya borrada), en claro, oscuro y
  a 375 px: marcar en «Lo mío» apaga en Anuncios, el modo «no sé» calla una y
  quita los botones de la otra, y una integrante ve solo 2. **Falta ver
  `/admin/anuncios` y `/mio` completas, con la base detrás.**

**Pendiente:** el rediseño de Anuncios del prototipo del 15-sep
(`docs/anuncios-prototipo-2026-09-15.html`, PR #401) sigue sin decidirse: si se
adopta, esta sección se muda con él.

## 2026-09-19 — El bono de cumpleaños firmado entra a la boleta (0479) · PEGADA Y VERIFICADA · FUSIONADA (#437) · EN EL ORDEN CORRECTO

**Está en producción y verificada.** Medido en el SQL Editor el 2026-09-19 19:42:
`documentos_firmados.movimiento_id` existe, `fn_mi_bono_cumpleanos` devuelve `via`
y `periodo_fin`, hay **una sola versión** con ese nombre —no se repitió la
sobrecarga duplicada de la 0297/0299— y el registro dice
`479 · el_bono_de_cumpleanos_firmado_entra_a_la_boleta`.

**Y se pegó ANTES de fusionar, que es lo que manda la regla:** pegada a las
**09:44:06** de Lima, fusionada a las **09:45:24**. Un minuto y dieciocho segundos.
Es la primera de las cuatro de ese día que respetó el orden.

**Lo que este párrafo decía hasta el 2026-09-19 19:42, y por qué se corrige.**
Decía «ESCRITA, NO AUDITADA · NO PEGADA · SIN FUSIONAR», y las tres eran falsas.
Se escribió a las 08:55, cincuenta minutos antes de que la migración se pegara y
se fusionara, y **nadie volvió a tocarlo en diez horas**. Una sesión posterior lo
leyó, lo creyó, y levantó una alarma de plata —«producción le promete a Melany un
bono que su base no sabe pagar»— que costó una consulta a producción para
descartar. El archivo de estado no es documentación de cortesía: es lo primero
que lee quien llega, y mintiendo hace exactamente el daño que existe para evitar.

Lo de «NO AUDITADA» también caducó por otro camino: **`db-tests` pasó en el PR
#437** (3 m 55 s) con la prueba pgTAP 378 dentro, contra una base de Supabase
construida desde cero. Esa es la señal fiable que declara `CLAUDE.md`, no esta
Mac — y llegó después de escrito el párrafo, cuando Docker seguía colgado acá.
El bloque 0 de la migración, además, compara el md5 de las cuatro funciones
contra la 0478 y aborta sin aplicar nada si difiere: que haya entrado prueba por
sí solo que partió de la versión correcta.

Felipe pidió que Melany pudiera firmar su cargo de cumpleaños y que, al hacerlo,
el incentivo apareciera en su boleta. **Lo primero ya existía** desde la 0477/0478
(`/mio/cumpleanos`, «Pedir mi bono», con la firma digital); la captura era la
pantalla del papel de DO, «Subir cargo». **Lo segundo no:** hasta la 0478 firmar
solo creaba un pedido que DO transfería por fuera, sin tocar la planilla.

**Cómo se hizo.** [0479](../supabase/migrations/0479_el_bono_de_cumpleanos_firmado_entra_a_la_boleta.sql):
al firmar, la misma transacción crea una línea `bono` «Asignación por
cumpleaños» en `movimientos_planilla` del último periodo que ya empezó y la ata a
la constancia (`documentos_firmados.movimiento_id`). **No se tocó
`fn_planilla_calcular`:** su bucket de bonos ya suma al total y la boleta ya los
pinta. Verificado leyendo la vigente (0397): `mov.bonos` solo entra al JSON, al
`total` y a la retención de 4.ª (0 para quien está en planilla) — **no** a AFP,
EsSalud ni provisiones. Tampoco al 3-de-6-meses de la 0278: es de una vez al año.

- Si al firmar **no hay periodo, o está pagado para su grupo**, no se escribe en
  ninguna boleta: la firma vale igual y queda `pedido` — el camino de la 0478
  (DO transfiere y confirma). Nunca se bloquea a la persona ni se toca lo pagado.
- **No se paga dos veces, por esquema y no por `if`:** un bono en boleta no puede
  tener `entrega_confirmada_*` (constraint), ni dos constancias la misma línea
  (índice único), y `fn_confirmar_entrega_bono` lo rechaza con su motivo.
- Si DO **quita la línea** desde Planilla, el vínculo se suelta (`on delete set
  null`) y el bono vuelve a «pedido» y a la lista por transferir: no se pierde.
- `fn_mi_bono_cumpleanos()` gana el estado `en_boleta` y las columnas `via` y
  `periodo_fin` (por eso se BORRA y se recrea). Para un bono pagado con la
  planilla la pantalla dice el periodo, no un «pagado el…» inventado.
- El primer bloque de la migración **compara el md5 de las cuatro funciones contra
  la 0478 en la base donde se pega** y se detiene sin aplicar nada si difiere.
  Tolera `\r` (pegada desde Windows). Es la comprobación «md5 de producción antes
  de escribir», ejecutada al pegar; no reemplaza pedirlo antes de entregar.

**Decisión que revierte una de hace tres días, y hay que decirlo:** el 2026-09-16
Felipe eligió que DO confirmara una transferencia aparte. Con la línea en la
boleta el bono se paga con la planilla, y esa transferencia deja de existir salvo
como respaldo. Si Felipe prefería lo contrario, esta migración no debe pegarse.

**Esta era la lista de «antes de pegar». Ya se pegó — qué se cumplió y qué no**
(revisado el 2026-09-19 19:42; se conserva porque dos puntos siguen abiertos):

1. ✅ **La prueba 378 corrió, pero en CI, no acá.** `db-tests` pasó en el PR #437
   (3 m 55 s) contra una base de Supabase desde cero. Es la señal fiable que
   declara `CLAUDE.md`; lo que no se hizo fue compararla contra el control SIN la
   0479, que es lo que distingue «lo rompí yo» de «ya venía así».
2. ⬜ **El audit empírico de dinero NO se hizo** — Docker seguía colgado.
   `fn_planilla_calcular_persona` con y sin la línea (solo pueden cambiar `bonos`
   y `total`) y `fn_liquidacion`, que no debe moverse. **Sigue pendiente**, y es
   el único punto de esta lista que toca plata: la 378 prueba que el total sube
   exactamente el monto, pero no que nada más se haya movido.
3. ✅ **El candado lo hizo solo, y mejor que un comando.** El bloque 0 compara el
   md5 de las cuatro funciones contra la 0478 en la base donde se pega y aborta
   sin aplicar nada si difiere. Entró, luego partió de la versión correcta —eso
   es más fuerte que un `donde-vive.sh`, que mira el worktree.
4. ⬜ **`packages/database/src/types.ts` sigue sin regenerarse con `gen-types`.**
   Se editó a mano (`movimiento_id`, su relación, y las dos columnas de
   `fn_mi_bono_cumpleanos`); el commit de la 0482 lo tocó después, pero nadie
   confirmó que saliera del generador. Cuando Docker vuelva, regenerarlo y
   comprobar que no cambia nada más que eso.
5. ✅ **Se pegó antes de fusionar:** 09:44:06 contra 09:45:24.

**Pendiente, y no es de código:** el código PLAME del cumpleaños (0203) sigue
«por confirmar con el contador» (ver `movilidad-y-codigos-plame-para-el-contador.md`).
Ahora ese S/ 180 sale en la boleta como «Asignación por cumpleaños»: el contador
tiene que saber que es no remunerativo (art. 19 g) del D.S. 001-97-TR) y no entra
a la base de aportes — el sistema ya lo respeta.

**Límite conocido:** sin botón «ponerlo en la boleta» para DO. Un pedido que quedó
sin línea (no había periodo al firmar) solo puede cerrarse con «Ya se lo transferí».
`/mio/boleta` solo muestra el periodo que contiene hoy: en los días entre el 29 y la
creación del siguiente periodo, el bono puede quedar en un periodo que ella ya no
puede abrir — se paga igual, y DO lo ve en Planilla.

## 2026-09-18 — Dashboard: la meta ya no se mide con la sede cerrada, y el «0 en piso» dice por qué · SIN MIGRACIÓN · FUSIONADA (#435)

> **Corregido el 2026-09-19 19:42:** decía «SIN FUSIONAR». Se fusionó el 19-set a
> las **00:06** y está en producción desde entonces (`fueraDeHorarioDeHoy`,
> `desgloseProgramadas` y `coincideConFiltroDeEstado` están en `main`). Sigue en
> pie todo lo que la entrada llama «pendiente, y no es de código»: los datos mal
> puestos de LIM, CCO, el horario que falta en TRU y la jornada de CCO abierta.

**Sin SQL: no hay nada que pegar.** Cambia `asistencia-hoy.ts`, la pantalla del
Dashboard y sus pruebas (115 en `asistencia-hoy.test.ts`; 900 en total). Verificado
con pruebas y typecheck; **no se vio en pantalla** — el panel no levanta sin
`.env.local` y el Postgres local estaba colgado.

**El error.** Una captura tras el cierre de TRU decía «Cobertura insuficiente ·
Faltan 8 · Faltan 2» con sus doce personas ya idas (la última a las 20:23; una
descansaba y otra no tenía horario). La meta «de la tarde» corría de 14:15 a
medianoche, sin fin: el Dashboard no sabía cuándo cierra una tienda, y Turnos sí
(«no se pinta rojo antes de abrir ni después de cerrar»). Dos pantallas, dos
reglas. Se confirmó contra producción con una consulta de solo lectura, no por
suposición: a la hora de la captura AQP seguía abierta (salidas 21:53 y 22:16).

**Lo que cambió** (decidido con quien administra, 2026-09-18):
- `fueraDeHorarioDeHoy`: la sede pasa a gris «Fuera de horario» y `faltanOp`,
  `faltanEnc` y `problema` salen en falso —así se apagan a la vez la tarjeta, el
  orden, «Requiere atención» y «Sedes bajo la meta»— **solo si ya no queda nadie
  en piso ni en pausa** y ya pasó la última salida programada de hoy (o aún no
  llega la primera entrada). El horario sale de los turnos y horarios de HOY, no
  de una hora de cierre escrita a mano. Cada duda cae hacia el rojo: sin hora de
  salida de alguien, sin nadie programado o con un turno que cruza medianoche, no
  declara nada. Pasada la primera entrada con nadie en piso SIGUE rojo (les
  tocaba y no llegaron).
- `desgloseProgramadas`: con 0 en piso, la tarjeta dice «Según el horario de
  hoy: 6 ya salieron · 3 aún no llegan · 1 no llegó y ya le tocaba». Reparte a
  todas las programadas; una prueba recorre cada estado de jornada para que
  ninguna quede sin contar.
- La líder de una tienda cuenta en las dos metas (operativas y líderes), así que
  «2/2 + 1/1» pueden ser solo 2 personas: la pantalla lo dice.

**Segunda tanda, tras «siguen existiendo errores»** (2026-09-19; una revisión del
resumen de arriba, los filtros y «Requiere atención», que la primera no había mirado):
- **Textos.** «Operativas en piso» → «Personal operativo en piso». Con 0 en piso,
  el desglose reemplaza a «Nadie está trabajando en este momento» (repetía el 0 por
  tercera vez). «Ver detalle (12 personas del equipo)».
- **El filtro «Salió» escondía gente.** La tabla dice «Salió (revisada)» y el
  filtro solo buscaba `cerrada`: en OTRU, 3 de las 4 personas que se habían ido no
  aparecían. `coincideConFiltroDeEstado` y `OPCIONES_FILTRO_ESTADO`; una prueba
  comprueba que ningún estado de jornada queda sin una opción que lo encuentre.
- **«Marcó hoy sin horario ni turno asignado».** La integrante de TRU que trabajó
  sin horario ya no pasa desapercibida: la tarjeta dice quién y que se arregla en
  Horarios. Solo personal operativo y líderes, y **se apaga si la consulta de
  turnos u horarios falla** (entonces todas las filas llegan sin horario y el aviso
  acusaría a todos).
- **Meta imposible = ámbar «Meta por revisar», no rojo** (`gravedad`). Lo eligió
  quien administra, **contra la recomendación** de dejar el rojo y arreglar el dato:
  «Sedes bajo la meta» cuenta solo las rojas; las ámbar van en «Requiere atención».
  **Costo conocido:** una tienda que pierde a su ÚNICA líder también sale ámbar
  (equipo 0 contra meta 1 no se distingue de una meta mal cargada sin historia).

**Conocido y aceptado:** entre la última salida programada y la salida real del
último, la tarjeta sigue midiendo (TRU: 20:15→20:23). Es lo que pidió la regla
«solo si ya no queda nadie».

**Pendiente, y no es de código** (datos reales, 2026-09-18 23:45). Con la tanda de
arriba dejan de ser rojo, pero siguen siendo datos mal puestos:
- **LIM tiene meta de 4 operativas y solo 3 personas activas** (2 operativas + 1 RxH
  de estrategia comercial): imposible aunque vinieran todas. ¿Meta mal cargada o
  faltan integrantes? Se corrige en Turnos. Hoy sale ámbar «Meta por revisar».
- **CCO tiene meta de 1 líder y nadie que cuente como líder.** Se apaga poniéndola
  en 0 en Turnos. Hoy sale ámbar «Meta por revisar» (entre semana) y «Meta sin turnos»
  los domingos, hasta que se ponga en 0 (ver la entrada del 2026-09-20).
- **Una integrante de TRU trabajó sin horario vigente** (ni turno): hay que cargarle
  su horario en Horarios; la tarjeta ya lo avisa.
- **Tres practicantes de OTRU** tienen la jornada de hoy «revisada» con la misma
  salida (20:52) y ~12 horas: ¿hora real o corrección en bloque? Sin verificar.
- **Una jornada de CCO seguía abierta a las 23:45** (desde las 08:57, última marca
  18:46) y contaba como «trabajando». Hay un cierre automático cada 15 min (0007);
  no se verificó su regla vigente. Sin horario asignado no hay contra qué medirla:
  no se hizo nada a propósito, un umbral inventado llenaría la pantalla de avisos.

## 2026-09-16 — El bono de cumpleaños se pide desde Info y DO confirma la transferencia (0478) · pegada en producción · fusionada (#424)

**Pegada el 2026-09-16, con la 0477 ya en producción.** Antes de pegar se
midió la 0477 en el SQL Editor: `fn_bono_monto_vigente` (`7bb28ab0…`, 252) y
`fn_confirmar_mi_bono_cumpleanos` (`1f0ee916…`, 2208) idénticas al archivo,
sin `\r`, con su registro 477 — o sea, la 0478 partió de la versión correcta.
La 0478 devolvió sus cinco comprobaciones en verde, con el registro
`478 · el_bono_de_cumpleanos_se_pide_y_do_confirma_la_transferencia`.

Dos cosas del camino que vale la pena saber:
- **El #424 se fusionó ANTES de pegar la 0478**, así que hubo un rato en que
  Info, la Bandeja mía y la de DO llamaban funciones que producción no tenía
  (errores visibles, sin plata en juego). Es la regla de CLAUDE.md —«la
  migración se pega ANTES de fusionar»— fallando otra vez por el mismo camino.
- **Repegar la 0477 falla** con «function … already exists»: usa `create
  function`, no `create or replace`. No está rota; ya estaba aplicada. La
  0478 sí es idempotente.

Felipe pidió que Melany pudiera **pedir** su incentivo de cumpleaños desde su
Info. Se construyó ENCIMA de la 0477 (entrada de abajo, PR #422), no en
paralelo: esta rama la trae entera.

**El hueco que cierra, con el caso concreto.** Con la 0477 sola, Melany firma
su constancia y en ese instante desaparece de la Bandeja de DO la única fila
que recordaba su bono («Bono de cumpleaños sin constancia firmada»): el
tablero ya ve una constancia y dice `ok`. Nadie transfiere, el sistema dice
«al día», y ella tiene firmado «Recibí conforme» por S/ 180 que no cobró.
Ninguna otra pantalla lleva la cuenta de ese pago (no pasa por planilla ni por
el libro de desembolsos). Se le planteó a Felipe con tres opciones y eligió:
**pedir = firmar, y DO confirma la transferencia**.

[0478](../supabase/migrations/0478_el_bono_de_cumpleanos_se_pide_y_do_confirma_la_transferencia.sql):

- `documentos_firmados` gana `entrega_confirmada_el/_por/_at`, con dos
  constraints: las tres juntas o ninguna, y solo en un bono firmado desde el
  sistema (el papel no la necesita: su `fecha_firma` ya es la de entrega).
- `fn_mi_bono_cumpleanos()` — qué le toca a cada quien: `pedido`, `no_aplica`,
  `sin_fecha`, `proximo`, `este_mes`, `vencido`, `entregado`. Compone el
  tablero y le agrega `en_planilla` y la transferencia. La leen Info, la
  Bandeja mía y /mio/cumpleanos, y es la puerta del pedido.
- `fn_confirmar_mi_bono_cumpleanos` (reescribe la de la 0477): solo se pide
  en el mes del cumpleaños o después. La 0477 dejaba firmar cualquier mes.
- `fn_bonos_por_transferir()` y `fn_confirmar_entrega_bono(id, fecha)` — solo
  DO, nadie confirma el suyo, ni futura ni de otro año, `for update` contra
  dos confirmaciones a la vez, con auditoría.

Frontend: tarjeta «Tu bono de cumpleaños» y aviso «Pide tu bono» en Info;
/mio/cumpleanos pasa a «Pedir mi bono» con sus estados; Bandeja mía (pídelo /
lo pediste / te lo transfirieron); Bandeja de DO con la fila «Pidió su bono de
cumpleaños», que se resuelve ahí mismo con fecha (nace en hoy) y «Ya se lo
transferí». Lógica compartida en `apps/web/lib/mi-bono.ts`.

**Auditado:** prueba pgTAP
[377](../supabase/tests/377_el_bono_se_pide_y_do_confirma_la_transferencia.test.sql)
(28 aserciones) en verde con la 0478 dentro de `begin … rollback`, y su
control sin la migración falla. La 376 de la 0477 se ajustó (sus firmantes no
tenían fecha de nacimiento, y desde la 0478 no estarían «en regla»): pasa con
y sin la 0478, y la versión original falla con ella, que es lo esperado.
Vitest 767 en verde, typecheck en verde. **Probado en el navegador de punta a
punta** con dos cuentas locales temporales (borradas al terminar): Info
mostró la tarjeta y el aviso con S/ 180.00 → «Pedir mi bono» → Info pasó a
«Pedido» y la Bandeja de ella bajó de 3 a 2 → la de DO mostró «Pidió su bono
de cumpleaños · S/ 180.00 por transferir», NO desapareció al firmar →
«Ya se lo transferí» la sacó (menú 72 → 71) → ella vio «Transferido el 16 de
setiembre» y la constancia con las dos fechas. La 0478 quedó aplicada en el
Postgres local compartido.

**Antes de pegar, en este orden:**
1. `./scripts/donde-vive.sh` de `fn_mi_bono_cumpleanos`,
   `fn_bonos_por_transferir`, `fn_confirmar_entrega_bono` y
   `fn_confirmar_mi_bono_cumpleanos`, en el mismo mensaje en que se entrega el
   SQL — que ninguna otra rama las haya creado mientras esto esperaba.
2. Pegar la **0477** y después la **0478**. La 0478 no corre sin la 0477.
3. Recién ahí fusionar (este PR incluye el #422; fusionar es publicar).

**Pendientes que esto dejó a la vista, sin tocar:**
- ~~`fn_documentos_tablero` (0424) calcula `bono_estado` también a quien es
  practicante, aunque la base le niega el bono~~ — **cerrado por la 0518**
  (2026-10-13): las tres puertas leen la misma regla, y el bono también es
  para practicantes. Ver la sección de ese día arriba.
- Documentación no sabe **mostrar** una constancia de bono firmada desde el
  sistema (solo abre escaneos, como la ruta antes de `abrirVerFirma`), y su
  «Subir otro» sobre ella falla por el índice único de un bono por año.
- `/mio/movilidad` pide `fn_documentos_listar` sin `p_persona_id`: a alguien
  de DO le pinta como suya la declaración de ruta de otra persona. En
  /mio/cumpleanos ya se corrigió.

---

## 2026-09-16 — El bono de cumpleaños también se firma desde /mio (0477) · pegada en producción · fusionada (#422) · su candado de mes y el aviso a DO llegaron con la 0478

Felipe pidió que la declaración de ruta y el bono de cumpleaños se pudieran
firmar desde el login de cada persona. La ruta ya lo hacía —0423/0429, del
2026-09-12— y esa parte no necesitó código: `/mio/movilidad` ya existe, y en
cuanto alguien entra a su cuenta le aparece sola en su Bandeja. El botón
«Pedir firma» de la Bandeja admin sigue yendo a `admin/documentacion` a
propósito: es la vía de escaneo que Felipe decidió conservar, no un trámite
roto.

El bono de cumpleaños sí era nuevo — la propia 0423 lo había dejado fuera
adrede («solo la declaración de ruta por ahora»).

**Una primera versión de esta migración tuvo un candado que se descartó
completo antes de pegarse en ningún lado**, y vale la pena dejar escrito por
qué: se asumió que el bono se entrega en efectivo en mano —lo que el nombre
de siempre, «constancia de ENTREGA», sugiere— y por eso esa versión exigía
que un admin marcara «entregado» (tabla `bono_entregas_pendientes` +
`fn_bono_marcar_entregado`) antes de que la persona pudiera firmar, para
evitar que alguien confirmara «recibí S/ 180» sin haberlo recibido. Al
preguntarle a Felipe, el bono se paga por **transferencia bancaria**, no en
efectivo — la transferencia ya es su propia prueba de entrega, así que ese
candado resolvía un riesgo que con transferencia no existe. Se tiró entero y
se rehizo mirando la ruta: mismo criterio, sin ningún paso previo de un
admin.

Migración [0477](../supabase/migrations/0477_el_bono_de_cumpleanos_se_firma_desde_el_sistema.sql),
mucho más chica que la primera versión:

- `fn_confirmar_mi_bono_cumpleanos` — nueva, copia estructural de
  `fn_confirmar_mi_declaracion_ruta` (0423/0429) sin nada que declarar: en
  planilla, activa, firma guardada, monto del `bono_onomastico` vigente
  (nunca uno que declare quien firma), y sin una constancia ya vigente este
  año.
- `fn_bono_monto_vigente` — nueva, y no estaba en el plan original: se
  encontró probando en el navegador que `/mio/cumpleanos` mostraba «no hay
  monto vigente» con la fila SÍ presente en `parametros_laborales`, porque
  esa tabla solo la puede leer un admin (`parametros_laborales_lectura_admin`).
  Sin esta función, nadie que no sea admin puede ver ANTES de firmar la cifra
  que está confirmando — se firmaría a ciegas, lo mismo que la 0425 ya evitó
  para la tarifa de movilidad. `fn_confirmar_mi_bono_cumpleanos` la llama en
  vez de repetir el `select`.
- `fn_documento_registrar` y `fn_documentos_tablero`: **sin ningún cambio**
  — el índice único `persona_id, anio` de `documentos_firmados` (0157) ya
  impide, por sí solo, que convivan dos constancias vigentes del mismo año
  sin importar por cuál camino llegue la primera.
- Frontend: pantalla nueva `/mio/cumpleanos` (sin campos que llenar, solo
  leer y firmar) y la Bandeja mía (`lib/bandeja-mia.ts`) avisa cuando
  `bono_estado` es `este_mes` o `vencido`, con link a esa pantalla — mismo
  mecanismo que ya usa la ruta, sin tocar `admin/documentacion` para nada
  (tampoco lo tocó la 0423 para la ruta).

Auditada con `begin … rollback` en el Postgres local (prueba pgTAP
[376](../supabase/tests/376_el_bono_se_firma_desde_el_sistema.test.sql),
10 aserciones: la misma puerta que ya exige `fn_documento_registrar`, que no
se puede firmar dos veces el mismo año, que el monto lo calcula el servidor,
que las dos vías —escaneo y firma digital— no pueden convivir con dos
constancias vigentes del mismo año, y que `fn_bono_monto_vigente` la puede
llamar cualquiera y no solo un admin). Las pruebas 334-336 de la ruta siguen
en verde.

**Y probada en el navegador de punta a punta**, con una cuenta de prueba
(`integrante`, en planilla, cumpleaños en el mes actual — borrada al
terminar): apareció sola en «Necesita que hagas algo» de `/mio/bandeja`,
`/mio/cumpleanos` mostró el papel con el monto real (S/ 180.00) ANTES de
firmar, dibujar y guardar la firma habilitó el botón, firmar dejó la
constancia archivada con su fecha y monto, y el pendiente desapareció de la
Bandeja. Ese recorrido fue lo que encontró el hueco de `fn_bono_monto_vigente`
de arriba — sin probarlo en pantalla, ese hueco quedaba invisible: el SQL y
el TypeScript por separado no lo delatan, porque cada uno hace exactamente lo
que se le pidió.

De paso, al auditar la primera versión se encontró que el Postgres local de
esta Mac le faltaba la 0448 (mismo hueco de `migraciones_aplicadas` que ya
documentaba este archivo para 431-434, 437-438 y 444-448) — se aplicó a mano
para poder auditar contra la base correcta. El md5 de PRODUCCIÓN de
`fn_documento_registrar` (`5909cada98bc2f879fd8f30dffeaffbe`) coincidió
exacto con el archivo 0448 del repositorio: producción está bien, era esta
Mac la atrasada. Como la 0477 final no toca esa función, esto queda solo
como nota — no hay nada que volver a verificar antes de pegar por ese lado.

**Antes de pegar:** repetir `donde-vive.sh` para `fn_confirmar_mi_bono_cumpleanos`
y `fn_bono_monto_vigente` —son funciones nuevas, pero conviene comprobar que
nadie más las haya creado en otra rama mientras esto esperaba revisión (ver
la 0297/0299).

Falta además: fusionar el PR, y pegar la 0477 ANTES de fusionar (regla de la
casa — `main` publica sola).

---

## 2026-09-15 — La tarjeta de Liquidaciones de la Bandeja dejó de fallar por timeout (0474, 0475) · pegada en producción · FUSIONADA

> **Corregido el 2026-09-19 19:42:** decía «SIN FUSIONAR». Los dos archivos están
> en `origin/main`, así que está publicada. Estaba pegada de antes: el orden se
> respetó.

Felipe reportó el recuadro rojo en la Bandeja: «No se pudo cargar
liquidaciones vencidas: canceling statement due to statement timeout».
`fn_liquidaciones_pendientes` (0454) calcula la liquidación completa —motor
de planilla incluido— de cada cesada, y de la que YA COBRÓ la calcula DOS
VECES más (`descuadra` y `descuadra_real` llaman `fn_liquidacion_diferencias`
por separado; Postgres no comparte el resultado entre dos llamadas del mismo
SELECT). Medido en el Postgres local con 17 cesadas: 518 ms — y esa lista
solo crece, porque a nadie se le borra.

Pero el defecto real estaba en quién la llamaba: la Bandeja (todo admin o
líder, en cada carga) pedía esa función completa para descartar
`descuadra`/`descuadra_real` sin usarlos — `esLiquidacionParaBandeja` solo
mira `!pagada && vencido && total>0`. Pagaba el cálculo más caro del sistema
por un dato que tira a la basura.

Dos migraciones, en dos pasos (decidido con Felipe):

- [0474](../supabase/migrations/0474_la_bandeja_deja_de_pagar_por_un_calculo_que_no_usa.sql)
  — `fn_liquidaciones_vencidas_bandeja()`, función nueva y liviana: filtra a
  cesadas sin pagar ANTES de calcular, así que nunca toca a quien ya cobró.
  `bandeja-fuentes.ts` pasa a pedir esta en vez de la pesada.
  `fn_liquidaciones_pendientes` no se toca: sigue siendo la única fuente de
  `/admin/liquidaciones`, que sí necesita `descuadra_real`.
- [0475](../supabase/migrations/0475_liquidaciones_pendientes_deja_de_calcular_dos_veces.sql)
  — esa pantalla deja de pagar el cálculo dos veces: un solo
  `left join lateral` llama `fn_liquidacion_diferencias` una vez, y de ahí
  salen los dos booleanos con `bool_or`. Ni una cifra cambia.

Auditadas contra Postgres local: la 0474 reproducida en vivo en `/admin/bandeja`
(la tarjeta pasó de "—" con el error a "3", con las mismas tres personas que
el filtro de siempre). La 0475 comparada fila por fila contra el
comportamiento anterior —idéntica para las 17 cesadas reales— y con dos
casos armados a mano en `begin…rollback` (una liquidación con diferencia real
→ `descuadra_real=true`; una liquidación que calza exacto → ambos `false`).
Prueba pgTAP 359 (la que defiende `descuadra`/`descuadra_real` desde la 0454)
en verde; 133 también. Typecheck y `pnpm test` (743 pruebas) en verde.

**Antes de pegar:** pedir en el SQL Editor el md5 de `fn_liquidacion_diferencias`
y `fn_liquidaciones_pendientes` contra la 0454 vigente (`donde-vive.sh`) — se
auditó contra el repositorio local, no contra producción. **Pegar las dos
ANTES de fusionar el PR**: en cuanto se fusione, el frontend en producción
llama a `fn_liquidaciones_vencidas_bandeja` de inmediato, y si no existe
todavía en la base, la Bandeja vuelve a fallar para todo el mundo.

Hallazgo aparte, sin tocar: el Postgres local compartido tiene un hueco real
frente a este repositorio —le faltan 415-419, 431-434, 437-438, 444-448, 461,
463-464, 467-468, y tiene aplicadas 469/470 que no están en ningún archivo de
esta rama—. Se rellenó a mano 450-455 (las que esta migración necesitaba para
poder auditarse) porque ya estaban fusionadas a `main`; el resto queda como
está, fuera de este alcance.

---

## 2026-09-15 — El MTPE deja de ser trámite para nadie (0470) · pegada en producción

Felipe leyó que "el trámite del ministerio" no era necesario y pidió
confirmarlo antes de tocar nada. Confirmado con tres fuentes independientes:
el Decreto Legislativo N.° 1246 ("simplificación administrativa", vigente
desde el 2016-11-11) eliminó la comunicación a la Autoridad Administrativa de
Trabajo tanto para contratos sujetos a modalidad (modificó el art. 73, D.S.
003-97-TR) como para convenios de modalidad formativa (derogó el último
párrafo del art. 46, Ley 28518) — para AMBOS, no solo para el indefinido que
la 0347 ya había eximido. Hoy se declara solo con la Planilla Electrónica.

Alcance del arreglo:
1. **`fn_contratos_tablero`** (migración
   [0470](../supabase/migrations/0470_el_mtpe_ya_no_es_tramite_para_nadie.sql)):
   `tramite_pendiente` ya no exige `comunicado_mtpe_at` a ningún tipo — solo
   falta la copia. `comunicado_mtpe_at` se deja sin borrar (puede tener
   fechas históricas anotadas de buena fe).
2. **El texto del contrato** (`apps/web/lib/admin/contrato-texto.ts`): la
   cláusula DÉCIMA OCTAVA de plazo fijo y convenio dejó de prometerle a quien
   firma una comunicación al MTPE que la empresa ya no hace ni tiene dónde
   hacer. Ya no distingue por tipo — es la misma cláusula para todos.
3. **La pantalla** `/admin/contratos`: sin badge "MTPE" pendiente, sin botón
   "Marcar comunicado al MTPE" (quedan dos: solo "Marcar copia entregada").
   `ETIQUETA_CORTA.tramite_pendiente` pasa de "Falta trámite" a "Falta la
   copia" — ya no hay caso especial para el indefinido, todos comparten la
   misma regla.
4. **La Bandeja** (`bandeja-urgencia.ts`, `bandeja-fuentes.ts`): el plazo de
   `tramite_pendiente` es siempre el de la copia (inicio + 5); el texto
   "Falta comunicar el contrato al MTPE" se retira.

Auditado con control: prueba pgTAP nueva
[373](../supabase/tests/373_el_mtpe_ya_no_es_tramite_para_nadie.test.sql) —
un plazo fijo y un convenio de prácticas, firmados y con copia entregada pero
SIN `comunicado_mtpe_at`, llegan a 'ok' con la 0470 puesta y a
'tramite_pendiente' con el cuerpo anterior (0386) — confirma que el cambio es
el que corrige, no una coincidencia. El indefinido (0347) no se movió.
Verificado además en el navegador contra Postgres local: dos personas de
prueba (plazo fijo y convenio) en estado real "Falta la copia", sin botón de
MTPE, y al marcar la copia entregada pasan a "Vigente" sin pedir nada más.
`pnpm typecheck` y `pnpm test` (743/743) en verde.

**Md5 contra producción, hecho bien:** el de partida se pidió a producción
ANTES de pegar y coincidió exacto con el que la migración asumía
(`34df0321b7abfdc7cf030e23d8c8543b`, 4780 caracteres) — producción no se había
movido desde la 0386. Felipe pegó la 0470 y el md5 de llegada volvió a
coincidir con el declarado en el archivo (`85d99e5aafcfdc5737f7f142284e1a8a`,
4288 caracteres). Cerrado: no queda ningún tipo de contrato al que este
sistema le exija comunicar nada al MTPE.

---

## 2026-09-15 — Quien ingresa después ya no se cuela en un periodo anterior (0463) · FUSIONADA · ⚠️ ¿PEGADA? — HAY QUE MIRARLO

> **Corregido el 2026-09-19 19:42:** decía «SIN PEGAR · SIN FUSIONAR». Lo segundo
> es falso —el archivo está en `origin/main`, o sea publicada—. **Lo primero no se
> pudo comprobar desde el repo y es lo que importa:** si de verdad sigue sin
> pegarse, lleva cuatro días fusionada por delante de su base. Se responde con
> `./scripts/que-falta-pegar.sh` en el SQL Editor, mirando la fila 463.

Felipe reportó, mirando `/admin/planilla`: cinco practicantes que ingresaron
en septiembre aparecían con fila propia en los periodos de julio y agosto —
«Sin salario», 0 horas — como si ya hubieran estado en la empresa esos
meses. `fn_planilla_calcular_nucleo` metía a cualquier persona `activo` en
CUALQUIER periodo que se recalculara, sin comprobar `fecha_ingreso` contra
el fin de ese periodo — la 0416 le puso ese freno al CESE (`fecha_cese
between p_ini and p_fin`); nunca hubo uno simétrico para el INGRESO.

Pasa solo cuando el grupo de esa persona nunca se congeló en ese periodo:
`fn_proyeccion_periodo` reemplaza por la foto congelada a quien sí tiene
grupo pagado, pero para «practicante» en julio/agosto no hay foto —la
categoría no existía todavía (0322, 2026-08-07)— así que sigue pidiendo el
cálculo en vivo. No movía plata (salario y horas ya salían en 0), pero
ensuciaba la cuenta de personas de un periodo que se daba por cerrado.

Migración [0463](../supabase/migrations/0463_quien_ingresa_despues_no_se_cuela_en_un_periodo_anterior.sql):
un AND más sobre la rama `p.estado = 'activo'` del CTE `pers`
(`p.fecha_ingreso <= p_fin`). Auditada contra Postgres local —arrancó vacío
en esta Mac (0 tablas), así que `supabase migration up --local` la puso al
día sin destruir estado de nadie— reproduciendo el caso exacto: una
practicante con `fecha_ingreso` en septiembre no trae fila en julio, sigue
trayéndola con normalidad en septiembre, y un control (persona activa desde
2020) no se mueve un milímetro. Prueba pgTAP 367 (4/4); suite completa 279
archivos / 2818 aserciones en verde.

**Antes de pegar:** volver a pedir en el SQL Editor el md5 de
`fn_planilla_calcular_nucleo` (`donde-vive.sh`) contra la 0418 vigente —
esta migración se auditó contra el repositorio local, nunca contra
producción, porque la clave de servicio está rotada a propósito.

---

## 2026-09-15 — Educación: la 0450 ya está pegada; nace la 0461 (colaborador pide su apoyo) · FUSIONADA · ⚠️ ¿PEGADA? — HAY QUE MIRARLO

> **Corregido el 2026-09-19 19:42:** decía «SIN PEGAR · PR #390». La 0461 está en
> `origin/main`, o sea publicada. **Si sigue sin pegarse**, lleva cuatro días
> fusionada por delante de su base — y toca el apoyo educativo, que es plata.
> Se responde con `./scripts/que-falta-pegar.sh`, mirando la fila 461.

**La 0450 quedó PEGADA Y VERIFICADA este mismo día** (esta entrada reemplaza el
aviso «SIN PEGAR · SIN PUSH» de más arriba, que quedó desactualizado apenas se
fusionó a `main`): `select numero, aplicada_at from migraciones_aplicadas where
numero = 450` da fila con `2026-09-15 19:34:41 UTC`, y `fn_educacion_situacion`
y `educacion_entregas` existen en producción. `/admin/educacion` y
`/mio/educacion` funcionan con normalidad.

**Lo que se agregó encima, en `claude/educacion-audit-redesign-2708b4` (PR
[#390](https://github.com/felipea92p-ux/cayla-dynamic/pull/390)):**

1. **"Registrar asignación" pasa a panel lateral** (el mismo `Drawer` de
   "Revisar constancia"), se agregó la tarjeta "Rechazadas" que faltaba en el
   resumen, y el plazo de pago/constancia deja de decir "paga en 0 días" —usa
   `enDias()` de `bandeja-urgencia.ts`, en admin y en el portal. Sin SQL.
2. **Migración nueva:
   [0461](../supabase/migrations/0461_el_colaborador_pide_su_apoyo_educativo.sql)
   — cualquier colaborador pide su propio apoyo educativo.** Hasta ahora solo DO
   podía dar de alta una asignación; con la 0461 la integrante llena el mismo
   formulario (institución, de quién es el estudio, costo, fechas, comprobante
   inicial opcional — **nunca el monto**, eso lo sigue calculando el sistema al
   aprobar) y queda «pendiente». DO la aprueba —nace la asignación real
   llamando a `fn_educacion_registrar`, el mismo cálculo de siempre, sin
   fórmula duplicada— o la rechaza con motivo (≥ 3 caracteres), que la
   integrante lee y puede corregir. Una sola solicitud pendiente por persona;
   mientras está pendiente la puede ver, ver su comprobante y retirarla.
   Cuenta en el mismo "Pendientes de revisión" del contador y de la Bandeja
   (`fn_educacion_por_atender`, `fn_educacion_solicitudes_pendientes`), con su
   propio ítem `solicitud_educacion` en Bandeja (`?solicitud=<id>` abre el
   panel directo, no `?familia=` — todavía no hay ninguna asignación a la que
   colgarlo).

**Qué se probó, y cómo** (la base local compartida sigue en la 449 — nunca se
tocó; todo esto corrió en transacciones que terminan en `ROLLBACK`, o en una
base `temp_edu_0461` aislada creada y borrada en el mismo Postgres del
contenedor, nunca en la compartida):
- pgTAP 365 (34/34, archivo nuevo) — solicitar, única pendiente por persona,
  validaciones, RLS (una integrante no ve ni retira la de otra), retirar y
  volver a pedir, nadie aprueba lo propio, permiso (una integrante no revisa),
  aprobar (verifica que el monto sale del mismo `fn_educacion_monto`, 200 · 75 %
  = 150), rechazar exige motivo, inmutabilidad (trigger, con `reset role` para
  probarlo de verdad y no solo el `GRANT`), contador y Bandeja ven la misma
  pendiente, el almacén congela la ruta al enviar.
- 226 (27/27), 355 (66/66) y 358 (7/7, actualizada: el marcador de canario que
  usa para «versión vigente» pasa de `CAMBIO 0450` a `CAMBIO 0461`, y ahora
  prueba los TRES tipos de ítem de educación en Bandeja, no dos) — cada una
  aislada, sin efecto de la 0461.
- Tipos de TypeScript regenerados desde esa base temporal (mismo método que
  usó la sesión de la 0450: solo entran los bloques de educación, nada de la
  deriva de otras ramas). `typecheck`, `eslint` (los archivos tocados) y
  `vitest` (663/663) en verde.

**Orden para producción — no se fusiona antes del paso 4 (igual que la 0450):**
1. Pedir en el SQL Editor el md5 de `fn_educacion_por_atender` y
   `fn_bandeja_marcar_visto`. Tienen que dar los del encabezado de la 0461
   (medidos contra 0450+0451+0452+0453 aplicadas, no contra producción — la
   base local compartida no llegaba a la 0450 para medirlo ahí). Si no, parar.
2. Push de la rama y pegar la 0461.
3. Confirmar: `select numero, aplicada_at from migraciones_aplicadas where numero = 461;`
   y la línea PLANILLA de `que_falta_pegar.sql` (la 0461 no la toca).
4. Recién ahí fusionar el PR #390 (fusionar = publicar).

**Pendiente, y hay que saberlo antes de pegar:**
- **Sin verificación visual todavía.** Mismo motivo que la 0450:
  `apps/web/.env.local` no existe. Probar en la vista previa de Vercel tras
  pegar: pedir un apoyo sin comprobante y con comprobante, aprobar, rechazar,
  corregir y reenviar, retirar, y el enlace "Revisar →" de la Bandeja.
- **La Bandeja PROPIA de la integrante (`lib/bandeja-mia.ts`) todavía no avisa
  cuando su solicitud se aprueba o se rechaza** — sí lo ve entrando a
  `/mio/educacion`, pero no le llega como notificación aparte, a diferencia de
  lo que ya hace con sus constancias. Se dejó fuera a propósito: ese archivo
  tiene su propia lógica de deduplicado (`PESO_PENDIENTE`, `esNueva`,
  `rechazoReciente`) y tocarla sin entenderla a fondo es como se cuelan los
  empates que este mismo repositorio ya documentó varias veces. Migración
  aparte, más chica y con su propia auditoría.
- `fn_educacion_solicitudes_pendientes` devuelve `comprobante_url` (la ruta
  real), no un booleano — si algo la vuelve a tocar, que no regrese a un
  `tiene_comprobante` sin la ruta, porque el panel de DO la necesita para abrir
  el archivo.

---

## 2026-09-15 — Contrato de Fernanda Espinoza: la 0430 se pegó y quedó verificada

Felipe reportó con capturas: Fernanda confirmó su firma en `/mio/contrato`, y
tanto `/mio` como `admin/contratos` seguían diciendo "Pendiente de firma" /
"Sin firmar". No hacía falta escribir nada — la corrección exacta de este
caso (su propio encabezado cita a Fernanda Espinoza y el 2026-09-12) ya vivía
en la migración [0430](../supabase/migrations/0430_el_contrato_se_firma_completo_de_forma_digital.sql),
fusionada a `main` antes de este reporte y listada como "sin pegar" en la
entrada de más abajo.

Antes de pegar se re-pidió en el SQL Editor el md5 de las cinco funciones que
la 0430 reescribe (`fn_confirmar_mi_firma_contrato`, `fn_contrato_registrar`,
`fn_contrato_editar`, `fn_set_fin_contrato`, `fn_contrato_refrescar_vencimiento`):
las cinco coincidieron con los prefijos que el propio encabezado de la 0430
ya había dejado anotados esa misma mañana — nada se había movido en el medio,
segura de pegar.

Se pegó completa. Su `select` final de comprobación devolvió las 6 columnas en
`true`, incluida `backfill_completo`: las 7 personas que ya habían confirmado
su firma antes de esta migración (Fernanda entre ellas) quedaron con
`fecha_firma` puesta sin tener que volver a firmar nada — exactamente el
criterio que pedía Felipe (a quien ya firmó no se le hace repetir; a quien no
ha firmado, se le sigue pidiendo igual que antes).

**La 0430 sale de la lista de "sin pegar" de la entrada de abajo.**

---

## 2026-09-15 — Producción llevaba DIEZ migraciones sin pegar y ningún freno lo veía

Al verificar el despliegue del historial de horarios (PR #361) se midió, de
paso, el registro entero de `migraciones_aplicadas` contra el repositorio. El
resultado no era el esperado: a producción le faltaban **23 números**, y solo
13 de ellos estaban explicados en `scripts/hooks/huecos-conocidos.txt` o en
`no-se-pegan.txt`. Los otros diez —**0428 y 0430 a 0438**— eran migraciones
reales, commiteadas, fusionadas a `main` desde hacía días, y sencillamente
nunca pegadas.

No es una anécdota de orden. Una de ellas tenía consecuencia inmediata: la
**0437** crea `fn_dia_con_expediente_formal`, la función que impide corregir
un día que ya tiene un expediente disciplinario firmado. Sin ella en la base,
las dos funciones de la 0447 que acababan de pegarse —la vista previa y la
corrección retroactiva de horario— llamaban a algo inexistente.

**Y no falló al pegar la 0447.** PL/pgSQL no resuelve las llamadas internas
hasta que se ejecutan, así que el `create or replace` pasó sin una queja y el
botón «corregir pasado» habría reventado la primera vez que alguien lo usara.
Es el mismo modo de fallo del botón de la 0407 y de la pantalla de la 0297/0299:
**no falla al aplicar la migración, falla al abrir la pantalla.**

### Cómo se encontró, y por qué conviene repetirlo

Con una sola consulta de lectura contra producción, que recorre el cuerpo de
todas las funciones plpgsql y busca llamadas a funciones que no existen:

```sql
with cuerpos as (
  select p.proname as quien, regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
), refs as (
  select distinct m[1] as llamada, c.quien
    from cuerpos c, lateral regexp_matches(c.src, '\m(fn_[a-z0-9_]+)\s*\(', 'g') m
)
select r.llamada as no_existe, string_agg(distinct r.quien, ', ') as la_llaman
  from refs r
 where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname = r.llamada)
 group by r.llamada;
```

Devolvió exactamente una fila, y era la buena. Vale la pena correrla después de
cada tanda que se pegue: es barata, no escribe nada, y contesta la pregunta que
ninguna prueba contesta — *¿lo que hay en la base se sostiene entre sí?*

### Por qué ningún freno lo vio

Los frenos de este repo vigilan **el camino de salida**: `numeracion.sh` mira
que no haya números repetidos ni huecos en `supabase/migrations`, el hook de
`que_falta_pegar.sql` mantiene la consulta al día, `dame-el-sql.sh` protege al
que pide el SQL, y `desplegar.sh` exige CI en verde. Ninguno mira **el estado de
producción**, porque ninguno puede: no hay credenciales contra producción por
diseño, y eso no va a cambiar.

O sea que «una migración fusionada que nunca se pegó» no tiene guardián posible
del lado del repositorio. Lo único que la detecta es mirar producción, y eso
solo lo puede hacer una persona con el SQL Editor. `que_falta_pegar.sql` existe
justo para eso — pero es de consulta voluntaria, y entre el 0428 y el 0438 se
acumularon diez sin que nadie la corriera.

### Y pasó otra vez lo de fusionar antes de pegar

El PR #361 se fusionó a `main` con las 0444-0447 sin pegar. Como `main` publica
sola, durante unos minutos producción sirvió un `/admin/correcciones` que pedía
`jornadas.horario_aplicado` —columna de la 0446, inexistente entonces— y esa
pantalla no abría ningún día: la consulta fallaba y cortaba la carga completa.

Es la **tercera vez en dos días** (0404, 0407, 0440, y ahora esta) y la segunda
documentada en este archivo. La conclusión de la entrada de ayer sigue siendo
la correcta y conviene subrayarla: *el freno que falta no es de código — es que
fusionar sin haber pegado la SQL sigue siendo posible, y lo seguirá siendo
mientras `main` publique sola.*

### Estado al cerrar

Pegadas y verificadas el mismo día: **0437**, **0438** y **0441 a 0447**. Cero
dependencias rotas en toda la base, una sola versión de cada función tocada,
permisos correctos (`authenticated` puede ejecutar las dos RPC nuevas de la
0447 y no puede ejecutar `fn_calcular_metricas_jornada`, que es lo que toca
porque solo la llaman otras funciones por dentro), el trigger
`trg_horarios_solo_por_rpc` de la 0440 intacto, y
`fn_dia_con_expediente_formal` presente con su firma `(uuid, date)`.

Con la 0437 y la 0438 juntas, el candado de «no pisar un expediente ya formal»
vuelve a cubrir las ocho puertas para las que se diseñó, no seis.

🔴 **Figuran sin pegar: 0428, 0431, 0432, 0433, 0434, 0435 y 0436.** (El 0420
también falta, pero ese sí está explicado: es una renumeración limpia, ver
`huecos-conocidos.txt`. La 0430 se pegó y se verificó el 2026-09-15 — ver la
entrada de arriba.)

⚠️ **ESTA LÍNEA YA CAUSÓ UN INCIDENTE Y LA COMPROBACIÓN QUE PEDÍA NO SE HABÍA
CORRIDO. Se corrió el 2026-10-30. NO PEGUES LA 0428 NI LA 0436.**

La comprobación que este párrafo pedía —`./scripts/donde-vive.sh <función>` para
cada función que la migración define, y confirmar que la pendiente ES la
vigente— se corrió para las siete. Resultado:

| | define | la vigente es | pegarla hoy |
|---|---|---|---|
| **0428** | `fn_provisiones` | **la 0491** | ⛔ **revierte 63 migraciones de `fn_provisiones` — es PLANILLA** |
| 0431 | `fn_aprobar_ausencia` | la 0431 | ✅ inocua |
| 0432 | `fn_bloquear_cese_directo` | la 0432 | ✅ inocua |
| 0433 | `fn_set_datos_personales` | la 0433 | ✅ inocua |
| 0434 | `fn_set_con_hijos` | la 0434 | ✅ inocua |
| 0435 | `fn_enviar_mensaje_encargada`, `fn_responder_mensaje_encargada` | la 0435 | ✅ inocua |
| **0436** | `fn_bandeja_marcar_visto` | **la 0515** | ⛔ **la devuelve de 11 tipos a 5: mata el acuse de educación, de cambio de turno y de CONDUCTA** |

**Y la 0436 no está sin pegar: está pegada.** `bandeja_vistos` la crea
únicamente ella (línea 35) y la alteran la 0450, 0453, 0461, 0473 y 0515, todas
pegadas —la 0450 está marcada «PEGADA Y VERIFICADA» en esta misma página—. Una
tabla no se puede alterar si no existe.

**Esto ya pasó una vez, por esta línea.** El encabezado de la
`0453_la_bandeja_vuelve_a_reconocer_educacion.sql` es su postmortem: el
2026-09-15 a las 16:00 se repegó la 0436 «siguiendo una auditoría de migraciones
pendientes que la daba por segura — y que había caducado». `dame-el-sql.sh` lo
avisó en rojo y se pegó igual, porque **solo avisa**. El síntoma es el peor que
hay: `/admin/bandeja` llama con `void supabase.rpc(...)`, así que la excepción se
traga sin avisarle a nadie y lo único que se ve es que no se guarda nada.

Hoy el daño sería mayor que entonces: la 0515 agregó `conducta_registrada` y
`caso_traspasado`, que son los avisos de la escalera disciplinaria.

**Lo que falta saber, y solo producción puede decirlo:** si `migraciones_aplicadas`
tiene las filas 428 y 436. Si NO las tiene, `que_falta_pegar.sql` las está
pidiendo activamente —su columna `nunca` es `false` para las siete, y solo una
fila en todo el archivo la tiene en `true`—, o sea que la herramienta canónica
también empuja hacia el accidente, no solo esta línea.

---

## 2026-09-14 — Horarios caído en producción: la 0440 se fusionó a `main` sin pegarse — mismo patrón que 0404/0407, otra vez

Felipe reportó: al cambiar el horario de cualquier persona, el modal
respondía *"El sistema no encontró esta función. Avisa a Felipe: falta
aplicar una migración."* — el mensaje que el propio sistema arma para
`PGRST202`.

**No era un bug de código.** El PR [#356](https://github.com/felipea92p-ux/cayla-dynamic/pull/356)
("Horarios base: buscador, sección sin horario, badge Programado y motivo
obligatorio") ya estaba fusionado a `main` desde las 18:03 de hoy. Como
`main` se publica sola, el frontend que llama a `fn_set_horario_semanal` con
4 argumentos (`..., p_motivo`) ya estaba en producción — pero la migración
[0440](../supabase/migrations/0440_el_horario_tambien_se_cambia_por_una_puerta.sql),
que crea esa función de 4 argumentos, nunca se pegó en el SQL Editor.
Producción se había quedado con la firma vieja de 3 argumentos, y
PostgREST no encuentra ninguna función que coincida con la llamada nueva.

Verificado en producción, solo lectura, antes de tocar nada:
`fn_set_horario_semanal` con la firma vieja, `migraciones_aplicadas` en
439 (no 440), el trigger `trg_horarios_solo_por_rpc` de la 0440 sin existir.
Contra el Postgres local (que sí tenía la 0440) se probó el flujo completo
— cambiar horario existente, asignar a alguien sin horario, horario que
varía por día, y que un `UPDATE` directo a `horarios_asignados` sin pasar
por la función sea rechazado por el trigger nuevo — todo en verde, y el PR
ya había pasado pgTAP en CI. Con eso alcanzaba: no hacía falta escribir
código ni migración nueva, solo dársela a Felipe. Se pegó la 0440 y se
confirmó de nuevo contra producción: 1 sola versión de la función, firma de
4 argumentos, trigger instalado, `migraciones_aplicadas` en 440 con el
nombre correcto.

**Es exactamente el patrón que `CLAUDE.md` ya documenta con 0404/0407: "la
migración se pega ANTES de fusionar el PR que la usa".** Esta vez el orden
volvió a invertirse y el síntoma fue peor que las dos veces anteriores —no
fue un botón roto o un envío a medias, fue el módulo entero inoperable
mientras nadie miraba. El freno que falta acá no es de código: es que
fusionar sin haber pegado la SQL sigue siendo posible, y lo seguirá siendo
mientras `main` publique sola.

🔴 **Pendiente:** producción sigue sin las migraciones 441, 442 y 443 —
sin relación con este bug, pero la brecha entre `main` y lo pegado sigue
creciendo.

---

## 2026-09-11 — Revisión de pendientes de diseño/UX: casi todo ya estaba fusionado; tres bugs reales cerrados

Se pidió trabajar "todos los pendientes de diseño e interfaz". Antes de tocar
nada se verificó el estado real contra el código, no contra
`plan-apariencia-2026-09-06.md` ni `plan-diseno-2026-07-27.md`: los dos días
del plan, los 25 hallazgos de la Radiografía (PR #232) y los cuatro lotes de
migración de pantallas (PR #273/#276/#278/#280, "lote4 (final)") **ya estaban
fusionados a `main` entre el 2026-09-05 y el 2026-09-08** — este worktree ya
estaba al día (`HEAD` = `origin/main`; el `main` local solo estaba atrasado,
el síntoma habitual de trabajar en varias Mac sin `git fetch`). De la lista
"Pendiente para después" de
`plan-apariencia-2026-09-06.md`, dos ítems resultaron ya resueltos al
verificarlos (el bloque `@media print` ya lleva los once tokens; `/mio` ya
tiene marco desde PR #312/#313) y uno quedó sin evidencia clara de seguir roto
(las "dos gramáticas" de tarjeta KPI en costos/provisiones — costos ya usa
`SeccionTabla`/`bg-papel`/`rounded-superficie` compartidos; no se confirmó una
segunda gramática real, así que no se tocó sin evidencia).

**Tres quedaban abiertos, verificados contra el código vigente, y se
cerraron** (rama `claude/design-interface-pending-75ac4d`):

1. 🔴→✅ **Ninguna integrante de sede podía llegar a cambiar su propia
   contraseña.** `nav-items.ts` gateaba "Cuentas" a `roles: DO` desde el
   2026-09-04, con un comentario que decía que la pantalla "se degrada
   sola... el renglón solo llevaba a una puerta cerrada" para quien no
   gestiona catálogos. Era falso: `admin/cuentas/page.tsx` tiene la rama "Mi
   cuenta" (solo cambiar la propia clave) desde que se creó, el 2026-07-12
   (`4d71fd8`). El comentario de septiembre asumió sin volver a leer el
   código de julio, y dejó a toda encargada de sede sin ningún camino en la
   interfaz —ni menú, ni ⌘K, ni atajos— para cambiar su clave; solo por URL
   directa. Cambiado a `roles: SEDE`; la pantalla ya sabía distinguir DO de
   SEDE, no hizo falta tocar su lógica.
2. ✅ **`esActivo()` no resaltaba 6 sub-rutas** (`planilla/boleta`,
   `disciplina/memo/[id]`, `normas/[id]/imprimir`, `normas/[id]/constancias`,
   `politica-salarial/constancias`, `mio/boleta`) — hallazgo ya escrito en la
   entrada del 2026-09-07 sobre el sidebar nuevo, sin cerrar. En vez de
   enumerar las seis a mano, una sola regla general
   (`pathname.startsWith(href + "/")`) las cubre todas y cualquier sub-ruta
   futura — se verificó que ningún href actual es prefijo de otro, así que no
   hay riesgo de colisión.
3. ✅ **`admin/liquidaciones`, `Hoja()`/`FirmaEmpresa` usaban `border-black`**
   (4 sitios) en vez de un token de la casa — el único hallazgo de la
   auditoría de colores sin excepción documentada. Cambiado a `border-tinta`:
   en impresión es visualmente idéntico (tinta se fuerza a `#1a1a18` en
   `@media print`, el mismo valor que tenía `black`), y en la vista previa en
   pantalla ya sigue el tema en vez de una línea negra fija.

**Verificado:** `pnpm typecheck` limpio, `pnpm test` 534/534 en verde,
`eslint` sobre los dos archivos tocados sin errores nuevos (el único error
que marca —`react-hooks/set-state-in-effect` en
`liquidaciones/page.tsx:200`— es deuda vieja, ninguna línea tocada hoy queda
cerca). **No verificado en el navegador:** el Postgres local compartido tenía
solo el contenedor de base de datos arriba (18 h), sin API/Auth/Kong —
`supabase start` no los levantó y se decidió no forzarlo sin saber si otra de
las ~10 sesiones activas depende de que quede así ahora mismo. Falta mirar a
ojo: el sidebar con una cuenta de encargada de sede, y la vista previa de una
liquidación en modo oscuro.

⚠️→✅ **Los otros 11 ítems `roles: DO` de `nav-items.ts`, revisados uno por
uno el mismo día: ninguno tenía el error de Cuentas.** Se leyó qué hace de
verdad cada pantalla con un rol que no es DO, no solo el nombre del ítem:
`contratos`, `documentacion`, `planilla`, `provisiones`, `costos`,
`liquidaciones`, `educacion`, `areas`, `sedes` y `apariencia` **todas**
declaran su propio `if (!puede) { return <mensaje> }` con un texto explícito
de rechazo ("Solo administradores y líderes pueden...", "Esta pantalla es de
Desarrollo Organizacional") — ninguna ofrece una vista reducida de verdad,
como sí hacía `admin/cuentas`. `feriados` tiene el mismo patrón
("No tienes permiso para gestionar feriados."). En los once, el gate del
menú coincide exactamente con lo que la pantalla ya hace: no hay nada que
cerrar.

**Por qué Cuentas era distinto, y vale la pena que quede escrito:** de los
doce ítems `roles: DO` que existían, es el ÚNICO cuya rama para "no admin" es
una función real (cambiar la propia clave) en vez de un mensaje de rechazo.
El patrón correcto de la casa, confirmado en los once, es: **pantalla
DO-only → mensaje de rechazo explícito para quien no lo es.** Si una pantalla
nueva alguna vez ofrece algo real para SEDE además de la gestión completa
para DO, ese es el caso especial que hay que recordar destrabar en el menú —
como se hizo hoy con Cuentas.

---

## 2026-09-11 — La 0376 (candado de `fn_vacaciones_saldo` / `fn_marca_apartada_resolver`) YA estaba pegada · la entrada del 09-05 mentía · CERRADO

La entrada de abajo, del 2026-09-05, decía «🔴 Falta pegarla en producción».
Ya no es cierto — alguien la pegó entre esa fecha y hoy sin dejarlo escrito
acá, y esta entrada quedó mintiendo seis días.

Se descubrió pidiendo el md5 a producción, tal como la entrada vieja mandaba
hacer antes de pegar: el resultado no coincidió con el «md5 de partida» que
la 0376 declara en su cabecera, y por un momento pareció que producción tenía
otra versión. **No la tenía** — el «md5 de partida» es el de las funciones
ANTES del arreglo (0357/0304), así que nunca iba a coincidir con nada una vez
aplicada la 0376; lo que había que comparar era contra el md5 de LLEGADA. Se
midió contra el Postgres local con la 0376 aplicada (`migraciones_aplicadas`
confirma el 376) y coincidió exacto en las dos funciones, `tal_cual` y
`sin_comentarios` los dos:

| función | md5 (tal_cual) |
|---|---|
| `fn_vacaciones_saldo` | `50c82625a587650afce9c40e12ec8386` |
| `fn_marca_apartada_resolver` | `dd8400ac81f001c27f87718ee1b2f384` |

Nada quedó a medias: el candado que cierra el agujero de la persona cesada
con sesión viva (ver la 0376 para el detalle) está activo en producción hoy.

---

## 2026-09-10 — Se pegó la 0403→0409, y el registro de migraciones resultó estar mintiendo dos veces

Empezó como «a una integrante nueva de Trujillo no le sale el apartado Mi DNI».
Terminó pegando siete migraciones, fusionando tres PR y arreglando a mano dos
filas de `migraciones_aplicadas`. Lo que hay que recordar no son las
migraciones: son las tres cosas de abajo.

### 1 · `on conflict (numero) do nothing` falla EN SILENCIO, y hoy falló dos veces

Todas las migraciones de este repo cierran con

```sql
insert into migraciones_aplicadas (numero, nombre) values (NNN, '…')
on conflict (numero) do nothing;
```

Está ahí para que repegar una migración no reviente. El precio es que **una
colisión de número no se ve**: el DDL se aplica, el registro se queda con la
fila de otra migración, y nada avisa. Hoy pasó dos veces:

- **La 0405** (`la_correccion_de_dni_se_queda_en_do`). A las 20:00:19 ya existía
  una fila 405 con nombre `0405_la_tasa_de_pension_de_respaldo_se_valida_al_escribir`
  — la migración de la AFP con su numeración vieja, que en su rama ya era la
  0411 y que además estaba registrada ahí. Cuando se pegó la 0405 de verdad
  (entre las 20:23:26 y las 20:30:19), su registro no se escribió.
- **La 0409** (`el_terminal_por_fin_puede_leer_horario_y_turno`). Su contenido
  estaba aplicado en producción —las dos policies ya usaban
  `fn_persona_en_roster_terminal(persona_id)`, la corrección que trae esa
  migración— y no tenía fila, porque el número 409 lo ocupaba la migración del
  memo (ver punto 4).

**Cómo se cazaron, y es la lección de método:** consultando el registro por
NOMBRE y no solo por número. La comprobación que se hizo primero fue
`array_agg(numero)` y devolvió `[403,404,405]`, que se leyó como «las tres
entraron». Un array de números no distingue «está la mía» de «está otra con mi
número». **Cuando se comprueba un registro de migraciones, se piden `numero` y
`nombre`.**

**Lo que se propone y NO se hizo todavía:** cambiar la convención de aquí en
adelante a `on conflict (numero) do update set nombre = excluded.nombre,
aplicada_at = now()`. Repegar sigue sin fallar, pero un número ocupado por otra
cosa se ve — la fila cambia de nombre delante de quien pega, en vez de quedarse
mintiendo. No arregla las migraciones ya escritas.

**Ojo con la 0405:** su `aplicada_at` es `2026-09-10 21:09:01`, la hora de la
corrección. La real está acotada entre las **20:23:26** y las **20:30:19** de
ese día, por las filas vecinas.

### 2 · El `\r` de Windows: medido, y el culpable NO es el portapapeles

El `CLAUDE.md` documenta desde el 2026-09-08 que pegar desde Windows mete un
`\r` por línea. Hoy se midió de dónde sale exactamente, y el resultado corrige
la suposición:

- **El portapapeles sale limpio.** `Get-Content -Raw -Encoding utf8 <archivo> |
  Set-Clipboard` deja el portapapeles **byte por byte idéntico** al archivo:
  medido en las seis migraciones de hoy, `CR=0` y los caracteres no-ASCII
  intactos (159 en la 0404, 194 en la 0405, 222 en la 0408).
- **El archivo en disco también.** 0 retornos de carro, `core.autocrlf = false`,
  sin `.gitattributes`. El `\r` no viene de git.
- **Lo mete el editor del SQL Editor de Supabase**, que normaliza los finales de
  línea a la convención del sistema de quien pega. La prueba es el contraste:
  las tres migraciones pegadas el 2026-09-08 a las 20:00 y 21:10 —desde la
  Mac— tienen `cr = 0` en producción, y **todo lo pegado hoy desde Windows
  tiene `cr` = su número de saltos de línea**, exacto.
- **Y no se perdió nada más.** Se calculó el md5 del cuerpo del repositorio
  convertido a CRLF y **coincidió con el de producción en las nueve funciones**.
  Un solo carácter mal —un acento roto, el accidente de la 0185— habría
  cambiado el hash. Así que el `\r` es lo único que pasó.

**Cómo comprobarlo en un vistazo:**

```sql
select proname,
       md5(prosrc)                                           as md5,
       length(prosrc)                                        as length,
       octet_length(prosrc)                                  as octet,
       length(prosrc) - length(replace(prosrc, chr(13), '')) as cr
  from pg_proc where proname = 'fn_lo_que_sea';
```

Si `cr` sale igual al número de saltos del cuerpo y `octet_length` es el del
repositorio más ese mismo número, es esto y no hay nada roto. Si no cuadra
ninguna de las dos, es otra versión y hay que parar.

**Y `dame-el-sql.sh` no protege de esto en Windows.** Su comprobación byte por
byte usa `pbcopy`/`pbpaste`, que son de macOS; en Windows cae al `else` y solo
dice «ábrelo y cópialo». Verifica git y GitHub, **no** lo que llega al
portapapeles. El equivalente que sí verifica, y que se usó hoy:

```powershell
$repo = Get-Content -Raw -Encoding utf8 <archivo>; Set-Clipboard -Value $repo
$clip = Get-Clipboard -Raw
"identico : " + ($clip -eq $repo)
```

### 3 · Los md5 de las funciones tocadas hoy, para que nadie pare en seco

Estas nueve quedaron con `\r` y **su md5 no volverá a coincidir con el del
repositorio**. Estos son los de producción, verificados uno por uno:

| función | migración | md5 | length / octet / cr |
|---|---|---|---|
| `fn_resolver_solicitud_perfil` | 0405 | `e915954d8af0f81509a3e5d0b1d3429e` | 2572 / 2586 / 55 |
| `fn_solicitudes_perfil_pendientes` | 0405 | `193cf79613372cd568b8bd9b83ede410` | 575 / 575 / 12 |
| `fn_confirmar_mi_firma_contrato` | 0406 | `9fd167ef12e77545b4bd2ad6581cfbdf` | 1215 / 1224 / 30 |
| `fn_borrar_dni_de` | 0407 | `2b47112565e76c77f20cf1fee5934d55` | 2333 / 2355 / 54 |
| `fn_mis_memos` | 0408 | `0f02ee97f3187656e085eec4186f1dd7` | 338 / 338 / 7 |
| `fn_firmar_memo_como_sancionado` | 0408 | `35c1a7558746e927ceab66347f6a8448` | 1195 / 1205 / 31 |
| `fn_rechazar_firma_memo` | 0408 | `b03654032d2483ccc9b3593a2fc0a738` | 903 / 907 / 25 |
| `fn_memos_recientes_respuesta_sancionado` | 0408 | `083da5faf9fb8413725eaaddc515bf58` | 718 / 718 / 12 |

`fn_registrar_mi_consentimiento` (0404) se comprobó contra los dos candidatos y
pasó, pero no se anotó cuál: el limpio es
`0b9cf2e88249f965df93a63a65b7b98c` (710/721) y el de CRLF
`4205deaca5788d7b21bba227a445716c` (729/740). `fn_solicitud_perfil_puede_leer`
(0403) no se midió.

Y las tres que **sí** coinciden con el repositorio, porque se pegaron desde la
Mac — sirven de contraste:

| función | md5 | length / octet / cr |
|---|---|---|
| `fn_bloquear_regimen_pension_directo` | `3c35b443adeb571b4c857c8479789dbd` | 247 / 249 / 0 |
| `fn_valida_tasa_afp_respaldo` | `f0bb914b10f147a49eefdcd417feb5a2` | 787 / 800 / 0 |
| `fn_expediente_cerrar_sin_entrega` | `e1940eb0ec92ca397e0ca7ee3dcbaecb` | 1369 / 1377 / 0 |

### 4 · Las cuatro filas huérfanas (409/410/411/412), explicadas y cerradas

Producción tenía cuatro filas que no cuadraban con el repositorio. Ninguna era
el caso de la 0393 —contenido superado, no fusionar—: las tres funciones que
creaban existían **solo** en ramas sin fusionar, así que era el caso (a),
aplicado y sin guardar. Se comprobó midiendo el md5 de cada una contra la rama:
las tres coincidieron byte por byte.

- **410 y 411** venían de [PR #301](https://github.com/felipea92p-ux/cayla-dynamic/pull/301)
  (`auditoria-afp-a1970d`). Habían sido 0404/0405 y se renumeraron bien para no
  chocar con `main`; sus filas coinciden exactamente con lo que declaran los
  archivos, prefijo `0410_`/`0411_` incluido.
- **409** era en realidad la **0412** (`el_memo_firmado_se_cierra_sin_entrega_si_la_persona_cesa`,
  [PR #299](https://github.com/felipea92p-ux/cayla-dynamic/pull/299)): se pegó
  cuando era la 0409 y se renumeró después. Se corrigió la fila con
  `update migraciones_aplicadas set numero = 412 where numero = 409 and nombre = …`
  — con el `and nombre` para que no pudiera tocar otra.
- Al liberar el 409, la **0409 de `main`** pudo por fin registrarse.

Los tres PR (#288, #299, #301) se fusionaron. **`main` tiene ahora la 0399 a la
0412 sin un solo hueco** y `numeracion.sh` dice «sin novedad».

**Hallazgo de la revisión del #301:** no tenía **ni una** corrida de CI. Dos
migraciones vivían en producción sin que ninguna prueba pgTAP las hubiera visto.
Se resolvió empujando a la rama en vez de fusionar directo a `main`, para que
`db-tests` corriera — pasó en 3m56s. Por eso los conflictos se resuelven en la
rama y no en `main`: es lo único que consigue la señal.

### 5 · Y la pregunta con la que empezó todo: «Mi DNI» no aparecía

**No era la base, ni el consentimiento, ni el contrato.** La pestaña se enciende
con una sola condición (`hayCampoDni`, que lee `catalogo_campos_perfil` buscando
`foto_dni`), esa lectura no filtra por persona y su política es
`using (true) to authenticated`. Se verificó contra producción: la fila existe,
el esquema es `public`, la política está, el permiso está, y **leyéndola como
`authenticated` devuelve la fila**. Así que no podía ser de esa integrante: si
no la veía ella, no la veía nadie.

La respuesta fue la más aburrida: **estaba fuera de la vista.** Las ocho
secciones de `/mio` vivían en una tira horizontal con `overflow-x-auto` y la
barra de scroll escondida, y en cualquier pantalla que no fuera ancha había
secciones enteras sin nada que anunciara que seguían a la derecha. Otra sesión
llegó al mismo diagnóstico ese mismo día y lo cambió por el menú lateral
(`components/nav/menu-detalle.tsx`), con el antecedente escrito ahí: ya se había
intentado con scroll horizontal (`688e8e5`) y se revirtió el mismo día
(`21591a7`) por esconder ítems.

**Dos propiedades del código que conviene tener escritas, porque las dos hacen
que un problema global parezca una función que falta:**

1. **Esa lectura falla cerrada y a propósito** (comentario en `mio/page.tsx`):
   cualquier error de la consulta se trata como «el campo no existe», sin
   mensaje en pantalla. Es la decisión correcta —vale más que la sección no
   esté que que falle con las dos fotos ya subidas— pero significa que un 404
   de PostgREST, un permiso o una fila ausente se ven **idénticos**.
2. **`/mio` no tiene corte de render para `!yo`**, solo para `!sesion`. Si la
   fila de `personas` no se puede leer, la pantalla se dibuja **completa** y
   `cargarDni` sale por su `if (!yo?.id)`, así que desaparece **solo** la
   sección condicional. Se investigó como causa y se descartó (no hay ningún
   `auth_user_id` repartido en dos fichas), pero la propiedad es real: un
   problema de identidad se manifiesta como una sección que falta.

### 6 · 🔴 Vercel publica producción sola en cada push a `main`. Fusionar un PR ES publicar

Medido hoy, y no admite otra lectura. El commit `482d2c30` **solo cambia
`docs/estado.md`** —ni una línea de código— y el despliegue de producción pasó
de `dpl_EaBg4eug…` a `dpl_9TUUtjVPJ8jtCRHUchmwztyuinsE` **en menos de un
minuto**, sin que nadie corriera `desplegar.sh`. Antes, en la misma sesión,
había pasado de `dpl_HVp7Wfmx…` a `dpl_EaBg4eug…` al fusionar los tres PR.

La integración de Git de Vercel está conectada a `main` como rama de
producción. Consecuencias, y las tres importan:

- **`./scripts/desplegar.sh prod` vigila un camino por el que producción ya no
  pasa.** Comprueba que no haya cambios sin guardar, que GitHub esté al día y
  que la CI de ese commit esté verde —incluidas las pgTAP— y pide escribir
  `publicar`. Todo eso sigue siendo correcto y **no se aplica a los despliegues
  reales**, que salen de un `git push`. Es la misma forma del agujero que ya
  costó la 0177 y la 0243 con `dame-el-sql.sh`: *el agujero no estaba en el
  script, estaba en que el camino cómodo no pasa por él*.
- **La garantía de «CI verde antes de publicar» hoy NO existe.** Se observó
  directamente: producción ya servía el código de los tres merges mientras
  `db-tests` sobre `c426fe69` seguía corriendo. Estuvo unos veinte minutos
  sirviendo código que ninguna prueba de base de datos había validado todavía.
  No falló nada, y eso es lo peligroso.
- **Y «desplegar a producción se pregunta SIEMPRE» está saltado por la
  configuración, no por descuido de nadie.** Hoy se pidió permiso para
  *fusionar* tres PR; lo que ocurrió fue *publicar*. Quien aprueba un merge en
  este repo está aprobando un despliegue, y hasta hoy eso no estaba escrito en
  ninguna parte.

**Qué hay que decidir** (no se tocó nada): o se acepta y se escribe así en
`CLAUDE.md` —fusionar es publicar, y por tanto un merge se pide con el mismo
cuidado que un despliegue—, o se apaga el despliegue automático de producción
en Vercel para que el único camino sea `desplegar.sh`, o se mueve la puerta a
GitHub exigiendo que `db-tests` pase antes de poder fusionar. Las tres son
defendibles; lo que no lo es es que el repositorio documente una regla y la
configuración haga otra cosa.

### 7 · El molde del trigger NO hace falta siempre: depende de si la tabla tiene política de escritura

Durante esta sesión se dio por hallazgo que a `foto_dni_anverso_ruta` /
`foto_dni_reverso_ruta` les faltaba el trigger del molde
`fn_set_rol`/`fn_bloquear_rol_directo` (0295/0296) y
`fn_set_sede_base`/`fn_bloquear_sede_directa` (0342): que `fn_borrar_dni_de`
(0407) auditaba la cancelación pero un admin podía vaciar las columnas con un
`update` directo por PostgREST. **Es falso, y se descartó midiendo:**

| tabla | RLS | políticas en producción |
|---|---|---|
| `personas` | activa | `select` ×3 + **`personas_update_admin_lider [w]`** + `personas_insert_admin_lider [a]` |
| `datos_personales` | activa | **solo `select` ×3** — ni update, ni insert, ni delete |

Con RLS activa, **una operación sin política se deniega**, y los `grant` de
tabla no cambian nada (`authenticated` los tiene todos por el
`alter default privileges` de Supabase, y da igual). Así que a
`datos_personales` no se le puede escribir por PostgREST: sus únicos escritores
son funciones `security definer` —`fn_aplicar_cambio_perfil` (0399/0401), que
las pone al aprobar, y `fn_borrar_dni_de` (0407), que las vacía—. La puerta ya
está cerrada.

**La regla que queda, y que el `CLAUDE.md` no dice:** el molde del trigger es
obligatorio cuando la tabla **tiene** política de escritura que alcanza al
campo. En `personas` la tiene (`personas_update_admin_lider`), y por eso `rol` y
`sede_base_id` sí necesitaban su trigger — no era ceremonia. En una tabla sin
políticas de escritura, el trigger es un guarda contra algo que no puede pasar.

**Y el error de método, que es lo que hay que recordar:** se dedujo «no hay
trigger → se puede escribir» sin comprobar si había política de escritura.
Preguntarlo cuesta una consulta:

```sql
select relrowsecurity as rls,
       (select array_agg(polname || ' [' || polcmd::text || ']' order by polcmd::text)
          from pg_policy where polrelid = c.oid) as policies
  from pg_class c where c.oid = 'public.la_tabla'::regclass;
```

### Qué queda abierto de esta sesión
- 🟡 **`on conflict … do nothing`** → `do update set nombre = excluded.nombre`
  en la convención de migraciones (punto 1).
- ✅ **El despliegue automático se queda** (punto 6). Decisión de Felipe,
  2026-09-10, sabiendo lo que implica: **fusionar un PR a `main` publica a
  producción**, y `desplegar.sh` con todas sus comprobaciones NO se aplica a
  ese camino. Se descartó apagarlo y se descartó poner la puerta en GitHub. Lo
  que queda a cambio es el cuidado de quien fusiona, y sobre todo el orden:
  **la migración se pega ANTES de fusionar el PR que la usa**, porque después
  de fusionar el frontend ya está en el aire. Hoy eso falló dos veces —la 0404
  y la 0407— y las dos se cazaron a mano.
- 🟢 **El linter del hook no revisó uno de los push de hoy** y lo dijo en voz
  alta («no devolvió nada analizable»). La causa es la que el `CLAUDE.md` ya
  documenta: el commit tocaba `packages/`, y colar una ruta de ahí hace que
  eslint aborte. Se linteó a mano el único archivo de app afectado: 1 error, y
  es deuda vieja —la misma línea existía antes, corrida de la 277 a la 323—.

## 2026-09-08 — Auditoría dedicada a AFP/ONP: dos huecos de permisos cerrados (0410/0411)

10 agentes en paralelo, solo lectura, auditaron el descuento de AFP/ONP de
punta a punta — cálculo, exclusiones por tipo de vínculo, vigencia del
régimen, permisos, pruebas y consistencia contra este mismo documento y
`hallazgos-abiertos.md`. La aritmética central resultó sana: 5 casos
numéricos trazados a mano sobre `fn_planilla_calcular_nucleo` (0397) dieron
los 5 el resultado correcto.

El hallazgo grave no fue de cálculo, fue de permisos, y lo confirmaron dos
agentes por caminos separados: `personas.regimen_pension` **no** tenía el
mismo candado que `rol` (0296) y `sede_base_id` (0342) — contradiciendo
directamente el cierre de arriba, el del 2026-09-03 ("el patrón función
guardián... las tres funciones ya funcionan bien"). No era cierto para la
tercera: cualquier sesión admin/líder podía pisar el régimen de pensión con
un `UPDATE` directo, saltándose `fn_cambiar_regimen_pension` (0332) entero.

**Cerrado hoy, aplicado y verificado en producción (commit `dcef5a3`):**
- **[0410](../supabase/migrations/0410_el_regimen_de_pension_tambien_se_cambia_por_una_puerta.sql)**
  — trigger que bloquea el `UPDATE` directo de `regimen_pension`, mismo
  molde que 0296/0342.
- **[0411](../supabase/migrations/0411_la_tasa_de_pension_de_respaldo_se_valida_al_escribir.sql)**
  — exige que `configuracion.tasa_afp` (el respaldo global que usa la
  planilla cuando falta el régimen de alguien) sea un número entre 0 % y
  20 % al escribirse; no toca el valor ya sembrado.

**Medido en producción de paso:** `configuracion.tasa_afp` sigue exacto en
`{"tasa": 0}`, y hay al menos una persona activa, en planilla, sin ningún
régimen de pensión asignado hoy — aportando S/0 de pensión cada mes hasta
que se le asigne desde `/admin/datos-personales`.

**Quedan abiertos** ~9 hallazgos 🟡: la boleta y `/admin/planilla` quedan
mudos cuando a alguien le falta el régimen (no solo cuando está "jubilada"),
el mismo hueco de "sin régimen → aporte cero" también vive en
`fn_vacaciones_truncas` (liquidación al cesar), `tipo_vinculo` no está
versionado por fecha a diferencia de `regimen_pension`, no existe función
para corregir una liquidación ya pagada con AFP/ONP mal calculado, y tres
huecos de cobertura en las pruebas pgTAP de AFP. Detalle completo, con
evidencia archivo:línea, en [`hallazgos-abiertos.md`](hallazgos-abiertos.md).

## 2026-09-08 — La 0393 no es una huérfana: es un fantasma. Los cuatro huecos, explicados · CERRADO

Medido contra producción el 2026-09-08: `migraciones_aplicadas` llega a la
**400**, y todo lo que `main` tiene desde la 386 está pegado. **No hay atraso de
pegado.** En la otra dirección apareció una fila que sobra, y lo que enseñó vale
más que el hallazgo.

**La 0393 (`cualquiera_guarda_su_propia_firma`) se pegó el 2026-09-07 a las
15:06 desde una rama que nunca se fusionó.** La primera lectura fue «hay que
fusionar ese PR». **Es exactamente al revés**, y comprobarlo costó tres consultas:

- el archivo de esa rama crea `fn_set_mi_firma(p_dataurl text)` — UN argumento;
- producción tiene `fn_set_mi_firma(p_dataurl, p_tipo, p_estilo)` — TRES, creada
  por la **0395** y ajustada por la **0398**, las dos en `main` y las dos pegadas.

O sea: el contenido de la 0393 quedó superado por migraciones posteriores que sí
están guardadas. **No falta nada por rescatar.** Y fusionar aquel PR crearía una
sobrecarga —los tres argumentos tienen valor por defecto, así que una llamada de
uno encajaría en las dos firmas— y repetiría el **«function is not unique»** de
la 0297/0299: el accidente que no falla al pegar la migración, sino al abrir la
pantalla. Ese PR se cierra sin fusionar.

**LA LECCIÓN, que es lo que hay que recordar de esta entrada.** El detector nuevo
(PR #250) marcó la fila correctamente, pero su texto decía «commitéala HOY» — la
instrucción contraria a la correcta. Un detector encuentra la discrepancia; **no
puede decidir qué significa**, porque hay dos casos que se ven idénticos:

  a) la migración existe y no se guardó → commitearla (0177, 0243, 0381);
  b) el número se anotó y su contenido quedó superado → NO commitear nada.

Distinguirlos exige mirar si lo que esa migración creaba sigue vigente en
producción **con la misma firma**. El aviso pasó a decir «revísala», con los dos
caminos escritos al lado.

**Y el estado ya tenía nombre.** `huecos-conocidos.txt` manda desde su primera
versión buscar «SOBRA LA FILA» antes de silenciar un hueco, y ese texto **no
existía en ninguna parte del repo**: el archivo llevaba meses mandando a buscar
una comprobación que nadie había construido. Ahora el estado se llama así.

**Los cuatro huecos quedan documentados**, con razón verificada uno por uno:
0383, 0389 y 0394 son renumeraciones limpias que NUNCA llegaron a producción
(comprobado: no tienen fila en `migraciones_aplicadas`); la 0393 lleva la
explicación larga de arriba. `numeracion.sh` ya dice «sin novedad».

## 2026-09-07 — El freno SQL→producción deja de mirar el disco (la «mitad cara» del 🔴#0) · FUSIONADA (#250)

> **Corregido el 2026-09-19 20:02:** decía «SIN FUSIONAR». El PR #250 se fusionó
> el **2026-09-08 12:10 de Lima** — once días mintiendo. Comprobado en el código,
> no en el mensaje del PR: `que-falta-pegar.sh` ya arma la lista con
> `git ls-tree` de `origin/main` y `HEAD`, y la consulta ya trae la CTE
> `huerfanas`.
>
> **La encontró el hook nuevo, no una persona.** El barrido manual de ese mismo
> día se apoyó en los números de migración del encabezado y esta entrada no
> lleva ninguno: es sobre un script. Vale anotarlo porque es justo el caso que
> un par de ojos pierde y una comprobación mecánica no.

[PR #250](https://github.com/felipea92p-ux/cayla-dynamic/pull/250). El
`estado.md` lo pedía desde el 2026-08-14 y era el único freno del repo que
preguntaba en la dirección fácil.

**El agujero era una línea.** `listar()` hacía `ls supabase/migrations/*.sql`
—el DIRECTORIO DE TRABAJO—. Si una migración se aplicaba en producción desde un
archivo que nunca se commiteó, y ese archivo seguía en el disco de esa Mac, `ls`
lo veía, entraba a la lista `repo` y la consulta la marcaba «✓ aplicada». El
hueco quedaba invisible **justo en la máquina donde había que verlo**.

Pasó tres veces —la 0177 (2026-08-07), la 0243 (2026-08-14) y la 0381
(2026-09-05, un día entera sin que nada avisara)— y a ninguna la cazó una
herramienta: a las tres las encontró alguien mirando a mano.

**Qué cambia.** La lista sale de la UNIÓN de `origin/main` y `HEAD`: lo que está
en GitHub más lo commiteado en esta rama, que son las dos cosas que sobreviven a
que ese disco falle. El directorio de trabajo queda fuera a propósito —un archivo
sin commitear no es un ejemplar, es un borrador, y de eso ya avisa
`migracion-sin-guardar.sh`—. Es la unión y no solo `origin/main` porque si no,
cualquier rama de trabajo vería como huérfanas todas las migraciones de main.

**Y la pregunta que la consulta nunca hacía.** Todo lo que respondía era «¿qué le
falta a producción?». Ahora responde también **«¿qué tiene producción que no está
guardado en ninguna parte?»**: la lista `huerfanas` sale ANTES del resumen y
manda sobre él. Que falte pegar algo es atraso normal; que algo esté pegado y sin
guardar es lo que costó tres sustos.

**Probado en las dos direcciones, contra producción real** —y la segunda importa
tanto como la primera, porque un guardián que chilla siempre se desactiva a la
semana:

| Caso | Resultado |
|---|---|
| Con la 0393 fuera de git (su estado real) | la cazó sola, con fecha y hora |
| Con la 0393 dentro de la lista | «sin huérfanas» — no chilla |
| Un archivo suelto en el directorio de trabajo | ya NO entra a la lista |
| `--check` | estable: el hook no entra en el bucle de pedir un segundo push |
| Sin red | genera igual, contra la última foto de `origin/main` |

## 2026-09-07 — 25 hallazgos de diseño de la auditoría del 2026-09-06/07, cerrados

Rama `claude/stoic-chandrasekhar-5a16c4`, 4 commits. De los 27 hallazgos de
categoría "diseño" con severidad alta o media que dejó la Radiografía Dynamic
(ver la auditoría en el worktree `kaila-dynamic-retail-audit-7d5733`), 25
quedaron resueltos aquí; los otros 2 eran el mismo bug del mapa de calor de
Turnos citado dos veces por lectores distintos.

**Lo tocado:** `globals.css` (paleta de impresión desfasada, radio duplicado,
regla de hover que le ganaba a Boton y alcanzaba al terminal, pizarra/verde
oscuro medidos mal), `Campo`/`CampoSelect` (etiqueta en mayúsculas → caja
normal tras comparar a ojo, zoom de iOS, flecha del select con color cocido),
`Modal` (ancho fijo, título que no se dibujaba), `Insignia` (variante alerta
bajo 4.5:1, variante `contador` nueva), el mapa de calor de Turnos (colores
que ignoraban el tema — commit aparte, el primero de la rama), y ocho
hallazgos sueltos en contratos, equipo, login, correcciones, horarios y el
terminal de marcaje (borde invisible de las casillas de nombre, grilla
dimensionada para teléfono, aviso de marcas apartadas ilegible).

Cada número de contraste se midió tal como el componente lo pinta de verdad
(pill compuesto a su opacidad real, en los dos temas), no contra el color
plano — siguiendo el mismo método que ya usa `globals.css` para verde/ámbar,
que varios de estos hallazgos señalaron que no se había aplicado a pizarra,
rojo ni al verde oscuro. Typecheck atrapó un JSX comment mal ubicado que
rompía la sintaxis en dos archivos antes de llegar a comitear.

✅ **`personas/[id]/page.tsx:645` — resuelto, era una falsa alarma.** El plan
de apariencia lo marcaba como "decisión abierta, no resolverla sin preguntar",
pero esa nota ya estaba vieja: `CLAUDE.md` (commit `06afd11`, 2026-09-05, un
día antes del plan) ya documenta el `bg-white` fijo de esa tarjeta como parte
de la excepción de política salarial. Corregida la nota obsoleta del plan.

**Sin tocar hoy, a propósito:** los 3 hallazgos de esfuerzo "día" y el de
"semana" (el envoltorio de tabla copiado 15 veces, el botón primario copiado
82 veces en 38 archivos, los 36 diálogos del navegador de Planilla) — se
solapan con el "Día 2" ya escrito en `plan-apariencia-2026-09-06.md`, y
migrarlos aquí habría sido reinventar esa secuencia a medio camino.

## Qué va acá y qué no

Este archivo guarda **solo lo que ninguna herramienta puede responder sola**:
las decisiones tomadas, los pendientes con fecha, lo que depende de una persona,
y lo que se descartó para no volver a investigarlo.

| Pregunta | Quién la responde de verdad |
|---|---|
| ¿Cuántas migraciones hay, hasta cuál? | `ls supabase/migrations \| tail -1` |
| ¿Cuántas pruebas, y pasan? | el job `db-tests` del PR (`gh pr checks`) · `npx pnpm typecheck && npx pnpm test`. **No `supabase db reset`**: el Postgres local lo comparten los ~10 worktrees y reiniciarlo le destruye el estado a las demás sesiones — además de dar rojos falsos. Ver CLAUDE.md |
| ¿Producción dice lo mismo que el repositorio? | `scripts/sql-manual/huella_del_esquema.sql` — una fila, dos segundos. Si difieren las funciones con el mismo conteo, `que_funcion_cambio.sql` dice cuál |
| ¿Falta pegar alguna migración? | `./scripts/que-falta-pegar.sh` genera la consulta; `migraciones_aplicadas` guarda el registro |
| ¿Falta anotar alguna migración? | la prueba `122_toda_migracion_deja_su_rastro`, en CI, en cada push |
| ¿Hay números duplicados o huecos nuevos? | `scripts/hooks/numeracion.sh`, antes de cada push |
| ¿Qué se hizo y cuándo? | `git log` |

Ninguna de esas siete puede envejecer sin que alguien se entere. Las de abajo sí,
y por eso están escritas.

⚠️ **Y la tercera fila es la que más caro salió aprender.** Hasta el 2026-08-08
esa pregunta la respondía un comparador que llevaba las huellas del repositorio
escritas dentro, así que caducaba en horas: acusó a 25 funciones que estaban
bien, y mientras tanto seis funciones de producción llevaban semanas dejando
cambiar una planilla ya pagada sin que nadie lo viera. **Un dato de referencia
nunca viaja guardado** — ni en un archivo, ni en un mensaje. Las dos mitades se
calculan en el mismo minuto o no se calculan.

**Regla para quien edite este archivo:** si lo que vas a agregar es un número que
un comando puede calcular, no va acá — va el comando. Y si es una lista de
nombres que hay que revisar, tampoco: va la consulta que los encuentra sola.

---

## 2026-09-07 — Radiografía Dynamic: primer lote de críticos de seguridad/plata, PEGADO Y VERIFICADO EN PRODUCCIÓN

Sale de la Radiografía Dynamic (92 agentes lectores, 731 hallazgos confirmados,
38 críticos — [artifact](https://claude.ai/code/artifact/1bd904f7-cff2-4a01-830b-475badb31ab5)).
Se decidió atender el resto de los críticos de plata/ley/seguridad por lotes
chicos, cada uno verificado empíricamente antes de escribir el siguiente, en
vez de una migración gigante de una sola vez.

✅ **Primer lote (2 "minutos" + 5 de Retail, consolidados en 3 causas raíz)
PEGADO Y VERIFICADO EN PRODUCCIÓN el 2026-09-07.** [PR #238](https://github.com/felipea92p-ux/cayla-dynamic/pull/238),
fusionado a `main`:

- `fn_cuentas` (`app/api/admin/cuentas/route.ts`): una admin/líder **cesada**
  conservaba acceso completo a gestión de cuentas — la ruta usa el cliente
  `service-role`, que se salta RLS y `fn_rol_actual()`. Ahora valida
  `rol` + `estado === 'activo'` con el cliente normal antes de autorizar.
- `admin/documentacion`: el desplegable de "a quién imprimir" ofrecía
  locadores para documentos (movilidad, bonos) que solo debería recibir
  personal en planilla — riesgo de desnaturalización del contrato. Filtrado
  a `en_planilla`.
- **`supabase/migrations/0392`** — `retail.es_lider()`, `retail.es_supervisor()`
  y `retail.puede_operar_sede()` sin `coalesce` devolvían `NULL` (no `FALSE`)
  para una persona cesada; como `if not NULL` nunca se dispara en PL/pgSQL,
  una excolaboradora con sesión de Auth todavía viva podía seguir abriendo
  caja y vendiendo en **cualquier** sede. `abrir_caja`/`cerrar_caja`/
  `registrar_venta` ni siquiera llamaban al guardián. `recalcular_stock()`
  no tenía candado y su `truncate`+`rebuild` borraba `stock_minimo`/
  `contenedor_id` en silencio. Prueba `311` (11 aserciones pgTAP) en verde
  en `db-tests`. Verificado contra producción DESPUÉS de pegar: los siete
  `md5(prosrc)` coinciden exactos con el Postgres local tras el arreglo, y
  `migraciones_aplicadas` registra `numero=392` a las 2026-09-07 22:14:24 UTC.
  **Alcance deliberado, no cerrado:** ~8 sitios más de retail con
  `if not retail.es_lider()` quedan seguros por el `coalesce` sin tocarse
  (mejora de consistencia aparte), y `fn_sede_actual_persona()` —que no
  filtra por estado— queda como riesgo residual anotado, no como algo que
  esta migración debía resolver.

Quedan por atender el resto de los críticos del catálogo priorizado, en
lotes sucesivos con el mismo protocolo.

⚠️ **[PR #232](https://github.com/felipea92p-ux/cayla-dynamic/pull/232) (los
25 hallazgos de diseño, del mapa de calor de Turnos a Modal/Insignia) sigue
ABIERTO, sin fusionar** — pendiente de revisión.

---

## 2026-09-07 — Un practicante puede cobrar movilidad y educación (0397) · PEGADA Y VERIFICADA

Motivado por un caso real: Geison Alcantára —de prácticas, ingresó el 3 de
septiembre— estaba mal registrado como planilla normal y su boleta le
descontaba AFP y le acumulaba gratificación/CTS que no le correspondían.
Se corrigió su `tipo_vinculo` a `practicante` desde `/admin/equipo` (dato, no
código), y de ahí salió la pregunta: ¿puede CAYLA ofrecerle también movilidad
y educación? Legalmente sí (Ley 28518 no lo prohíbe) — pero el sistema no se
las pagaba, porque las dos seguían condicionadas solo a `en_planilla`, que
para un practicante es `false` por definición.

**La 0397** amplía la condición a `pe.en_planilla or pe.tipo_vinculo =
'practicante'` en los 7 sitios exactos de `fn_planilla_calcular_nucleo` donde
se leía `en_planilla` para estos dos conceptos — el mismo patrón quirúrgico
que la 0322 usó para EsSalud. AFP, CTS, gratificación, bonificación
extraordinaria y asignación familiar **no se tocan** y siguen en cero para un
practicante. Sigue siendo una opción: sin tarifa de movilidad cargada para su
sede o sin una asignación de educación con comprobante, un practicante sigue
cobrando S/0 de los dos, igual que hoy.

Auditado contra Postgres local dentro de `BEGIN…ROLLBACK` antes de escribir
([PR #254](https://github.com/felipea92p-ux/cayla-dynamic/pull/254)): monto
correcto, `total` cuadra con `chk_foto_cuadra`, el periodo cierra por el grupo
`practicante` (0323), y las pruebas 115/193 (educación/movilidad existentes)
sin regresión. `db-tests` en verde (3m57s). **Confirmado en producción el
2026-09-07**: la consulta de comprobación del final de la migración devolvió
exactamente lo esperado — las dos funciones núcleo creadas, en la lista negra,
y NO ejecutables directamente por `authenticated`.

**Pendiente que no se arregla solo:** para que esto mueva un sol de verdad hay
que cargarle a la persona una tarifa de movilidad vigente para su sede (si no
la tiene) y/o una asignación de educación con comprobante desde
`/admin/educacion`. Sin eso, nada cambia para nadie.

---

## 2026-09-07 — El mega menú pasa a sidebar lateral colapsable, y los grupos de 5 a 7 · SIN MIGRACIONES, SIN DESPLEGAR

Ejecuta la decisión que [`plan-apariencia-2026-09-06.md`](plan-apariencia-2026-09-06.md)
dejó aplazada por escrito («la decisión de navegación de libertad total —sidebar
colapsable— si el ajuste evolutivo del Día 2 no alcanza»), saltándose el paso
evolutivo. **El Día 2 paso 1 de ese plan —bajar el corte a `lg` y mostrar las
etiquetas de grupo en la barra horizontal— queda sin efecto: ya no hay barra
horizontal que ajustar.** El resto de ese plan sigue en pie.

**Por qué ahora y no otro parche.** Es el tercer intento sobre el mismo
problema. El 5 de septiembre se probó scroll horizontal (`688e8e5`) y se
revirtió el mismo día (`21591a7`) con el criterio «nunca esconde ítems con
scroll». Con treinta renglones la barra envolvía en tres o cuatro filas y se
comía ~145px de alto en las 24 pantallas; por debajo de 1280px —un portátil con
la ventana sin maximizar— desaparecía entera en la hamburguesa. Ahora el
encabezado son 64px fijos.

**Los tres anchos:** ≥1280px sidebar de 256px con títulos de grupo · 768–1279px
rail de 64px solo con iconos · <768px cajón sobre velo. El botón de plegar gana
sobre el ancho y se recuerda en localStorage, como el tema.

**Y cada grupo se contrae desde su título**, con su chevron, también recordado.
Hacía falta: desplegado y con los siete grupos abiertos el menú mide 1303px
contra los ~790 que se ven en un portátil, o sea que Configuración quedaba
debajo del pliegue. Contrayendo cuatro grupos baja a 801px y cabe entero.
**En rail NO se contraen, a propósito:** ahí no hay títulos, así que no habría
dónde volver a pulsar y quien hubiera contraído «Nómina» se quedaría sin
Planilla hasta ensanchar la ventana. Y si la pantalla en la que estás vive en un
grupo contraído, su título se pinta en tinta en vez de taupe — sin eso, cerrar
el grupo en el que estás borra la única señal de dónde estás.

**La reagrupación, que es la parte que hay que discutir si algo se discute:**

- **«Ausencias» sale de Nómina y entra a Asistencia.** Era el único renglón de
  rol SEDE dentro de un grupo entero de rol DO: para una encargada, «Nómina»
  tenía exactamente un ítem.
- **«Publicaciones» es un grupo nuevo** con política salarial, normas y
  anuncios — las tres únicas entradas sin filtro de rol, y no por casualidad
  (Ley 30709 y entrega del RIT). Estaban en tres grupos distintos, así que una
  integrante veía cuatro renglones sueltos sin lógica visible.
- **«Apariencia» baja a Configuración**, con Áreas, Sedes y Cuentas: mismo
  permiso y misma frecuencia.
- **«Feriados» se queda en Nómina** aunque sea discutible: registra el
  compensatorio que quita la sobretasa del feriado trabajado, o sea que existe
  por el pago. Si al usarlo se siente de Asistencia, es un cambio de una línea.

Ninguna URL, ningún permiso y ningún nombre de pantalla cambian.

**Lo que ya no depende de que alguien lo recuerde.** `tests/nav-items.test.ts`
(21 aserciones) vigila que esas tres pantallas de obligación legal sigan sin
`roles`, que no haya rutas repetidas y que los contadores sean tres. Es la
primera prueba del repo sobre la navegación: hasta hoy solo la miraba el
typecheck, y el typecheck no sabe que «Normas» la tiene que ver todo el equipo.

**Deuda que este cambio NO pagó, y que salió al explorar:**

1. 🔴 **Una integrante no puede llegar a cambiar su propia clave.** `Cuentas`
   está restringida a DO en el menú, pero la pantalla sí muestra «Mi cuenta» a
   cualquiera. El renglón que lleva ahí no existe para quien lo necesita.
2. **Seis sub-rutas dejan el menú sin nada resaltado** — `/planilla/boleta`,
   `/disciplina/memo/[id]`, `/normas/[id]/imprimir`, `/normas/[id]/constancias`,
   `/politica-salarial/constancias` y `/mio/boleta`. `esActivo` cubre tres
   casos. No empeoró con este cambio: ya estaba así.
3. **`/mio` no lleva marco** — tiene su propio encabezado a mano y queda fuera
   del sidebar, siendo el destino del primer renglón del menú.
4. **El bloque `@media print` de `globals.css` redefine nueve tokens, no once**
   — le faltan `hueso` y `pizarra`, y usa los valores de `verde` y `ámbar`
   previos al retuneo del 6 de septiembre.

**Tres cosas del entorno, para quien trabaje en Windows** (esta sesión fue la
primera):

1. **Los archivos del árbol están en CRLF en disco y en LF en git.** Editar
   cualquiera y guardarlo tal cual reescribe el archivo ENTERO: `globals.css`
   pasó de un cambio de 49 líneas a uno de 444/395, y los 36 archivos del
   sidebar llegaron a dar 28.000 líneas de diff antes de normalizarlos. No
   rompe nada y por eso es peligroso — se ve como un cambio enorme y se revisa
   como tal. **Convertir a LF antes de commitear** y comprobar con
   `git diff --numstat` que el número cuadra con lo que se tocó de verdad.
2. `npx pnpm install` **falla en silencio y sale con código 0** (npx no
   encuentra el binario), así que hay que llamar a `pnpm` directo.
3. `.claude/launch.json` arranca el servidor con `/bin/zsh`, que en Windows no
   existe — se puede levantar con `pnpm --filter @cayla-dynamic/web dev`, pero
   el panel del navegador necesitaría una entrada propia en ese archivo.

Y una cuarta que no es de Windows: **el hook de pre-push llama a `python3`**
(`fecha-que-bloquea.sh` y `lint-de-lo-nuevo.sh`, los dos con `|| exit 1`), así
que sin Python instalado no se puede empujar desde esa máquina.

## 2026-09-05 — Foto junto al nombre en el terminal, subida por cada quien desde «Lo mío» (0381) · PEGADA Y VERIFICADA EN PRODUCCIÓN

Salió de la comparación contra BambooHR/Rippling/UKG del 2026-09-03 («Las Tres
Referencias de CAYLA»,
[PR #176](https://github.com/felipea92p-ux/cayla-dynamic/pull/176)): «Selector
por nombre + foto en el terminal» era el ítem 02 del bloque BambooHR, y de esa
misma comparación solo se había construido el tablón de anuncios (0351). Quedó
sin hacer hasta hoy, a pedido de Felipe.

**El mecanismo:** cada quien sube su foto desde `/mio` (comprimida a JPEG en
el propio navegador, 480px de lado mayor, antes de subir), enlazada a
`personas.foto_url` por una única función guardián
(`fn_actualizar_foto_perfil`) que exige ser la propia persona o admin/DO. El
terminal la recibe en `terminal_roster` (misma vista de la 0285/0375, una
columna más) y la pinta junto al nombre en la grilla; quien no ha subido
ninguna sigue viendo sus iniciales, nunca un hueco.

**Por qué el bucket `fotos-perfil` es público, a diferencia de `comprobantes`
o `expedientes`.** El terminal tiene que pintar todas las fotos de su sede sin
depender de la red — puede pasar días marcando solo con lo que ya tiene en
IndexedDB — y una URL firmada vence. El dato que protegería esa firma (un
rostro) ya es visible a simple vista en la propia tienda, sin login, en la
misma Mac mini: la misma razón por la que `terminal_roster` expone nombre y
apellido sin sesión individual. Ya había precedente de esta forma en el
repositorio: el buzón `fotos-productos` (0225, importado de cayla-retail)
también es público.

Auditada contra Postgres local dentro de `BEGIN … ROLLBACK` (11 aserciones:
subir, reemplazar, el borde de que nadie sube a la carpeta de otra persona,
que admin/DO sí puede hacerlo por quien nunca entra a «Lo mío», enlazar,
quitar la foto, la defensa en profundidad contra una ruta de otro bucket, y
que el terminal recibe lo enlazado) — prueba 301. Probada además de punta a
punta en el navegador contra el Postgres local: Ana sube su foto desde `/mio`
y aparece junto a su nombre en `/terminal/marcar`; Beto, que no subió
ninguna, sigue mostrando sus iniciales. `npx pnpm typecheck` y `npx pnpm test`
(468 pruebas) en verde.

**Pegada y verificada en producción el 2026-09-05.** La consulta de
comprobación del final de la 0381 devolvió las cinco piezas en `true`: la
columna `personas.foto_url`, el bucket `fotos-perfil` público, las cuatro
políticas de `storage.objects`, la columna nueva en `terminal_roster` y que
esa vista sigue sin exponer nada sensible. Falta el commit/push de este
código de pantalla (la migración ya vive en el repo desde que se escribió;
lo pegado a mano fue solo el SQL).

⚠️ **Repitió el accidente que la propia 0382 documenta — 0370/0375, tercera
vez, y esta vez en las dos direcciones.** El `drop view` + `create view` de
la 0381 partió del cuerpo de la 0375 sin saber que, en paralelo, la 0382 ya
había fusionado a `main` la delegación de la regla de sede a
`fn_persona_marca_en_sede`. Al pegarse la 0381 en producción DESPUÉS, se
llevó esa delegación por delante en silencio — confirmado contra producción
el 2026-09-05: `delega_en_0382 = false`, con las seis columnas (incluida
`foto_url`) presentes.

Y al revés también: la 0382, tal como estaba escrita, declaraba las CINCO
columnas de la 0375 en un `create or replace view` — que no deja quitar ni
reordenar columnas. En cualquier reconstrucción del esquema desde cero (CI,
`supabase db reset`, restaurar un backup) habría fallado en seco al llegarle
el turno, porque `foto_url` ya estaría puesta por la 0381. No era un
problema de producción: era el pipeline de todo el equipo.

**Resuelto corrigiendo el cuerpo de la 0382 antes de que llegara a pegarse
nunca** (decisión de Felipe, 2026-09-05): ahora declara las seis columnas y
conserva la delegación, con el relato completo en su cabecera. Se eligió eso
en vez de una migración de parche encima porque el estado real de producción
—seis columnas, sin delegación— es incompatible con que la 0382 haya corrido
allí alguna vez, así que no hay estado persistente que dependa de su forma
anterior. Auditado en local aplicando la secuencia 0377→0382 sobre el mismo
estado que tiene producción: las pruebas 301 (11), 302 (9, con su aserción
de columnas actualizada), 303 (4, nueva: la foto y el aislamiento de sede
conviven) y 293 (17, el candado de sede completo) en verde.

🔴 **Falta pegar la 0382 en producción** — es lo que repone la delegación.
Antes de pegarla, confirmar que sigue dando `delega_en_0382 = false`: si
otra sesión ya la pegó mientras tanto, su propia guardia lo dice sin daño.

---

## 2026-09-05 — Reverificada la deuda de planilla del 2026-08-19: 1 refutado, 6 confirmados abiertos · SOLO LECTURA, SIN MIGRACIONES

La tabla "mueve plata en el pago mensual" de [`hallazgos-abiertos.md`](hallazgos-abiertos.md#confirmado-y-pendiente--mueve-plata-en-el-pago-mensual)
tenía 8 filas del 2026-08-19, sin revisar contra las +30 migraciones que
tocaron `fn_planilla_calcular` desde entonces (una de ellas, el descanso
semanal, ya estaba cerrada por la 0280 sin que nadie la tachara — corregido
antes en esta misma sesión). Workflow dedicado de 13 agentes (verificar +
refutar adversarialmente, solo lectura, sin tocar ninguna base de datos):

- **Refutado:** "feriado dentro de vacaciones se paga dos veces" — es
  decisión de diseño ya verificada con datos reales en la 0293 y reafirmada
  textualmente en 7 migraciones posteriores. El hallazgo de 2026-08-19 partía
  de una premisa falsa (que el feriado paga "el día completo").
- **Confirmados abiertos, los 6 restantes**, cada uno con el mecanismo
  citado línea por línea contra el código vigente (0349) y sin ninguna
  migración posterior que lo neutralice: ausencias posteriores al cese,
  sueldo fijo sin prorratear (afecta también a `fn_liquidacion`), quien cesa
  sin marcas desaparece de la planilla, sin régimen de pensión el aporte da
  cero (matiz: sí hay aviso, pero en otra pantalla y desde antes del propio
  hallazgo), el sobretiempo pierde el exceso de un ciclo que cruza el borde
  del periodo, y Feriados/Planilla dividen por bases de tiempo distintas.

**Nada de esto se escribió como migración todavía.** Cada hallazgo trae su
recomendación técnica y, donde aplica, qué medir en Postgres local antes de
escribir el SQL — varios de los montos originales (S/193.55, S/1,509.64,
S/14-19) no se remidieron contra datos reales de hoy, solo se confirmó que el
mecanismo sigue existiendo. Antes de tocar cualquiera: `donde-vive.sh` de la
función (por si otra rama ya la tomó) y auditar en `BEGIN … ROLLBACK`, como
manda la casa para todo lo que toca plata.

---

## 2026-09-05 — Crítico 10 («Alertas de Resend sin llegar a nadie») CERRADO — el correo sí llega, y el backlog de julio queda anotado (0377) · PEGADA Y VERIFICADA

Cierra lo que la rama `claude/12-criticos-estado-c33e88` había dejado como
"falta correr en producción" (ver la entrada del 2026-09-05 de esa rama, más
arriba en este archivo).

**Se corrió [`las_alertas_de_resend_llegan.sql`](../scripts/sql-manual/las_alertas_de_resend_llegan.sql)
en producción.** Resultado: `nunca_se_envio_ningun_email = false` — pero la
fórmula solo se activa si hay al menos una fila `canal='email'`, y había
cero (`filas_canal_email = 0`): el sistema nuevo de vencimientos
(contrato/vacaciones por vencer, 0356/0357) todavía no tuvo ningún caso real
que avisar — 20 de los 21 contratos vencen recién en diciembre —, no que esté
roto.

**Se midió el canal que sí tiene tráfico real: `auto_cierre` (dispatch
desde la 0354, que ignora `canal` a propósito y manda por correo cualquier
`pendiente`).** En los últimos 14 días: **12 enviados con éxito**, el más
reciente el mismo 2026-09-05. **El correo funciona.** El crítico 10, tal como
lo temía la auditoría —"nadie recibe nada, en silencio"— no se confirma.

**Lo que sí apareció: 75 alertas de `auto_cierre` en `pendiente` desde el
2026-06-28, con `intentos = 0` — el despacho nunca las tocó.** No es un bug:
es la deuda que la propia 0354 dejó escrita a propósito en su encabezado —
"si esta función devolviera TODAS [las pendientes acumuladas], el primer
despacho mandaría un correo por cada auto-cierre de los últimos meses... Si
de verdad importa saldarlas, es una decisión aparte". `fn_alerta_despachable`
(0362) exige `created_at` de los últimos 7 días, así que estas 75 nunca
vuelven a ser candidatas — quedaron congeladas desde que se prendió el
despacho el 2026-09-03.

**Arreglo (0377):** anota un `nota_fallo` explicativo en esas 75 filas, sin
tocar `estado`. **A propósito no se marcan `'fallido'`** —que es lo que
sugería, sin saberlo, el propio comentario de la 0354—: `fn_alertas_despacho_resumen`
(0362) cuenta como `fallidas_definitivas` cualquier fila `fallido`/`procesando`
con `intentos >= 3`, **sin filtro de fecha**. Marcarlas así habría encendido
en la Bandeja de DO una alarma de "75 fallidas" el mismo día — el mismo falso
positivo permanente que la 0362 ya nombra en su encabezado como "el peor
error de esta casa". Dejarlas `pendiente` las mantiene exactamente tan
invisibles para la Bandeja como hoy (no caen en ninguna de las cuatro
categorías que devuelve esa función), con el porqué ya escrito en la fila
para quien las vuelva a encontrar.

✅ **Aplicada y verificada en producción el 2026-09-05**, con las dos
comprobaciones en verde: `filas_anotadas = 75`, `bandeja_fallidas_no_debe_subir = 0`.
Probada antes en local dentro de `BEGIN … ROLLBACK` (0 filas, esperable — la
base local no tiene el historial real).

⚠️ **Quedó aplicada en producción antes de commitear el archivo** — la
urgencia de cerrar el diagnóstico en vivo llevó a pasar el SQL directo en el
chat, igual que la 0367 (arriba). Commiteada apenas se detectó, siguiendo la
misma regla.

---

## 2026-09-05 — Contratos: la fecha de fin ya no admite ser anterior a la de inicio

Sale de la auditoría del 2026-09-03/04 (importante 40). Elegir un fin anterior
al inicio —fácil, son dos inputs de fecha adyacentes— dejaba "Generar borrador"
habilitado igual, y el error del servidor no decía cuál de las dos fechas
estaba mal.

**Arreglo, en dos capas** (la misma idea que ya usa el resto de la pantalla:
el `min`/`max` del input es una ayuda del navegador, no el candado real):
`min={fechaInicio}` en el `<input type="date">` de fecha de fin, y una entrada
en `bloqueos` (`fechaFin < fechaInicio`, comparación de string ISO) para el
caso en que la fecha de fin ya estaba cargada ANTES de mover la de inicio —el
`min` del input no la borra sola.

Verificado: `pnpm typecheck` limpio, `eslint` sobre el archivo con los mismos
4 errores preexistentes de antes del cambio (deuda vieja de
`react-hooks/set-state-in-effect`, líneas 429/448/460/517 — lejos de esta
edición) y ninguno nuevo. **No verificado en el navegador**: pedía una sesión
de admin y una persona cargada, y sembrar esos datos en el Postgres local
—compartido por todos los worktrees— no pareció justificado para una
comparación de dos strings de fecha.

---

## 2026-09-05 — Despliegue de la 0375 bloqueado por el tope diario de Vercel · SIN RESOLVER

Al intentar `./scripts/desplegar.sh prod` para publicar la 0375 (retiro del
PIN del terminal) con `main` ya en verde, Vercel devolvió: `Resource is
limited - try again in 24 hours (more than 100, code:
"api-deployments-free-per-day")`. No es un freno del repo ni de las pruebas
— el enlace del proyecto (`cayla/cayla-dynamic`) y las variables de entorno
están correctos, verificado con `vercel env ls` antes de intentarlo.

**Por qué hoy:** con ~15 worktrees activos en paralelo, cada PR abre su
propio preview de Vercel además de cualquier `vercel --prod` manual, y el
plan gratuito tope 100 despliegues/día entre TODO eso junto. Un día de
actividad alta como el de hoy (más de 20 PRs fusionados) puede agotarlo antes
de que alguien intente desplegar a producción.

**Qué hacer:** esperar a que el cupo se libere (ventana rolling de 24 h desde
el primer despliegue que lo agotó — no hay una hora exacta de reset
publicada) o que Felipe suba el plan de Vercel. Mientras tanto, la 0375 ya
está fusionada a `main` y no hace falta rehacer nada — el próximo intento de
`desplegar.sh prod` debería pasar sin cambios de código, si `main` sigue
verde.

---

## 2026-09-05 — El guard de `fn_vacaciones_saldo` / `fn_marca_apartada_resolver` ya tiene su migración (0376) · ✅ PEGADA — ver la entrada del 2026-09-11 arriba

Cierra el crítico nuevo de la segunda auditoría (28 agentes, ver más abajo):
la 0374 dejó `fn_rol_actual()` devolviendo `NULL` para cualquier persona
cesada, y dos funciones `SECURITY DEFINER` armaban su guard con un
`and not(...)` suelto en vez de envolver el OR completo en un único
`is not true` — la misma trampa de tres valores que la 0078 y la 0126 ya
corrigieron dos veces. Efecto: una persona cesada con sesión de Auth viva
podía leer el saldo de vacaciones de un excolega activo de su antigua sede
(`fn_vacaciones_saldo`) y resolver su marca apartada, escribiendo un marcaje
real (`fn_marca_apartada_resolver`).

**Esta nota existe porque casi se duplica el arreglo.** La entrada de la
auditoría (más abajo, "Crítico — 1, nacido de un arreglo de ayer") decía
"falta una migración nueva... es lo primero que hay que escribir mañana" —
pero cuando llegó "mañana", la 0376 ya existía en `main`, escrita por otra
sesión, con prueba 298 y CI en verde. `hallazgos-abiertos.md` quedó
corregido con un aviso para no repetir la búsqueda.

🔴 **Falta pegarla en producción.** Antes de pegar, pedir a producción el
md5 de las dos funciones (`donde-vive.sh fn_vacaciones_saldo` y
`donde-vive.sh fn_marca_apartada_resolver` imprimen la consulta lista) —
la propia 0376 declara sus md5 de partida locales
(`fn_vacaciones_saldo` `d466d0d9…`, `fn_marca_apartada_resolver`
`98cc555d…`) pero, como manda la casa, eso no reemplaza pedirlo de nuevo en
el momento de entregar el SQL.

---

## 2026-09-05 — Crítico 7 («El piso legal de grati/CTS no corrige una ventana ya pagada») · CORRIDO EN PRODUCCIÓN — 0 FILAS, LATENTE

Hallazgo de `Auditoria-CAYLA-2026-09-04.pdf` (no vive en el repo), «sobrevivió
2/3» refutadores, con un matiz importante que el propio refutador señaló: no
es un bug inventado, es un efecto colateral de una decisión ya tomada y
probada (0158, «se toma la mayor, nunca la suma», prueba 124).

**El mecanismo, visto en 0338** (lateral `cobrado`, líneas 860-866 de
[`0338_grati_cts_usan_el_sueldo_vigente_al_cierre.sql`](../supabase/migrations/0338_grati_cts_usan_el_sueldo_vigente_al_cierre.sql)):
`pag.g1` solo dice SI existe un movimiento de planilla en la ventana — no
CUÁNTO se pagó. Cuando `pag.g1` es verdadero, `cobrado.g1` se define como el
`devengado.g1` de esa MISMA llamada (día a día o piso, según cuál de las dos
invocaciones sea), así que `devengado - cobrado` da cero apenas existe el
movimiento — el piso nunca llega a compararse contra nada para una ventana ya
cerrada por planilla. Antes de la 0338 (antes del 2026-09-01) ninguna ventana
tuvo la oportunidad de pasar por el piso al pagarse; hoy ya no se puede
recuperar esa comparación desde la función, porque no puede verse a sí misma.

**Por qué no se tocó `fn_provisiones` ni se escribió el arreglo todavía.**
Reimplementar el cálculo día-a-día completo fuera de la función para poder
auditarla es la misma duplicación de ~300 líneas que la propia cabecera de la
0338 rechazó. Antes de correr ese riesgo hace falta la población — la misma
regla de `a_quien_le_pega.sql`: un hallazgo sin población es una hipótesis.

Consulta que la busca:
[`scripts/sql-manual/a_quien_le_pega_el_piso_grati_cts.sql`](../scripts/sql-manual/a_quien_le_pega_el_piso_grati_cts.sql).
Para cada ventana de grati/CTS pagada antes del 2026-09-01 y ya cerrada
(con movimiento en `movimientos_planilla`), busca a quien tuvo un cambio de
`asignaciones_salario` DENTRO de esa ventana — no en el borde—, que es la
única situación en que el día a día puede quedar corto frente al piso.

✅ **Corrida por Felipe en el SQL Editor el 2026-09-05: 0 filas.** Nadie en
CAYLA tuvo un cambio de `asignaciones_salario` DENTRO de una ventana de
grati/CTS ya cerrada antes del 2026-09-01. El mecanismo que el código tiene
—`cobrado` colapsando a `devengado` de la misma llamada— sigue siendo real,
pero hoy no le pega a nadie: no hay nada que ajustar con
`fn_registrar_desembolso` ni motivo para tocar `fn_provisiones`. Queda
anotado como latente en [`hallazgos-abiertos.md`](hallazgos-abiertos.md) para
que, si algún día alguien cesa o se le sube el sueldo a mitad de un semestre
YA CERRADO por planilla, se vuelva a correr
[`a_quien_le_pega_el_piso_grati_cts.sql`](../scripts/sql-manual/a_quien_le_pega_el_piso_grati_cts.sql)
antes de asumir que sigue en cero.

---

## 2026-09-05 — Crítico 10 («Alertas de Resend sin llegar a nadie») · VERIFICADO EN PRODUCCIÓN — SÍ LLEGAN, A GENTE REAL DE TRES SEDES DISTINTAS

Era «sin verificar» porque nadie había mirado producción. El código de
`/api/alertas-encargadas` y la cola con reserva/reintento (0362) ya estaban
—ver la entrada de la auditoría 0360-0366 más abajo—, así que lo que faltaba
no era arreglar nada: era mirar si de verdad está saliendo algún correo.

**Corrido en producción el 2026-09-05:**
[`scripts/sql-manual/las_alertas_de_resend_llegan.sql`](../scripts/sql-manual/las_alertas_de_resend_llegan.sql)
trajo una sorpresa que casi lleva a una falsa alarma: `filas_canal_email = 0`,
porque los avisos de `auto_cierre` (el 100 % de las 87 filas de hoy) se
insertan con `canal = 'push'` desde la 0007 —una columna vieja que la ruta
ignora a propósito— y la consulta filtraba por `canal = 'email'`. **Corregido
antes de sacar conclusiones**: mirando `estado = 'enviado'` sin filtrar por
canal, **8 alertas se enviaron con éxito el mismo día**, y el reintento de la
0362 sí está funcionando: alertas creadas desde el 2026-08-30 que llevaban
días en `'pendiente'` salieron todas juntas en un lote.

**La pregunta que faltaba —¿a la casilla de quién?— la resolvió**
[`scripts/sql-manual/a_quien_le_llegaron_esos_8_correos.sql`](../scripts/sql-manual/a_quien_le_llegaron_esos_8_correos.sql),
reconstruyendo los destinatarios reales de esas 8 filas con el criterio VIGENTE
de `fn_alertas_email_pendientes` (0354 + 0359 + 0362): **los correos van a
personas reales y distintas de TRES sedes** —
`25.chiara.flores@gmail.com`, `gutierrezdanitza07@gmail.com`,
`melanyenrriquez29@gmail.com`, `revillaoyolaj@gmail.com` (TRU, las cuatro con
`es_encargada_piso`), `sandramelisaar@gmail.com` (AQP), y el correo propio de
Carlos Espejo y Felipe Alvarez para sus propios auto-cierres en CCO. Eso
**contradice de raíz** la sospecha del hallazgo: si `RESEND_FROM` siguiera en
el dominio sandbox (`onboarding@resend.dev`), Resend habría rechazado —no
aceptado— cualquier envío a un destinatario que no fuera el dueño de la
cuenta. Que acepte seis direcciones reales distintas en tres sedes es la
prueba end-to-end que pedía la acción de la auditoría, sin necesitar
`npx vercel env ls` ni el panel de Resend.

**Lo único que destapó esto, y no es el hallazgo 10 sino uno adyacente:**
para CCO —que no es tienda, no tiene «encargada de piso»— el único
destinatario de un auto-cierre es la propia persona (0359, «el aviso también
avisa al propio integrante»). Es el comportamiento correcto y a propósito, no
un defecto: se anota acá por si alguna vez alguien lee «destinatarios vacíos
para CCO» en una consulta vieja y lo confunde con una falla.

✅ **No hace falta tocar `RESEND_FROM` ni ningún código.** El crítico 10 queda
cerrado: el mecanismo de envío funciona y entrega a personas reales.

---

## 2026-09-05 — Crítico 12 puede estar construido dos veces sin saberlo

Al revisar el estado de los 12 críticos se encontró que el hallazgo 12
(«practicante sin tope de horas en Incidencias») **ya está resuelto y
commiteado** en la rama `claude/audit-12-critical-issues-7da199`
(`dc64b47`, 2026-09-04: `admin/incidencias/page.tsx` ahora usa
`maximoSemanalPracticante()` en vez de comparar siempre contra 48h) — esa
rama no tiene PR abierto todavía. Y, por separado, hay una sesión en la Mac
con el worktree `dos-tareas-importantes-f65950` con el mismo arreglo hecho y
**sin commitear**.

No se tocó ninguna de las dos ramas desde acá — es exactamente el escenario
que `CLAUDE.md` pide comprobar con `git log --all` antes de empezar algo
("dos sesiones construyeron la misma función el mismo día", 2026-08-25).
**Antes de abrir un PR para el 12, comprobar si `dc64b47` ya es el arreglo
bueno y solo hace falta subirlo**, en vez de que la sesión de
`dos-tareas-importantes-f65950` lo reconstruya por su cuenta.

⚠️ **Actualización posterior el mismo 2026-09-05:** el crítico 12 (y el 11) se
resolvieron por otro camino — ver la entrada de la segunda auditoría, abajo,
sobre los 8 PR que atacaron los mismos hallazgos sin verse entre sí. PR
[#196](https://github.com/felipea92p-ux/cayla-dynamic/pull/196) ya está
fusionado a `main` y cierra los hallazgos 11 y 12 juntos.

---

## 2026-09-05 (noche) — Segunda auditoría (28 agentes): un crítico nuevo, y 8 PRs chocando entre sí · PDF entregado a Felipe

Pedido explícito de Felipe: repetir la auditoría del 2026-09-03/04 con más
profundidad —código nuevo desde entonces, vistazo general al resto,
benchmark contra Gusto/Rippling/BambooHR/Workday/Odoo/Oracle— y entregar un
PDF mejor explicado para la mañana. Detalle completo, con ejemplos y el
benchmark entero: el PDF (no vive en el repo, igual que el de ayer). Catálogo
accionable: [`docs/hallazgos-abiertos.md`](hallazgos-abiertos.md#auditoría-del-2026-09-05--código-nuevo-desde-el-2026-09-04-vistazo-general-benchmark-contra-6-erps--28-agentes).

🔴 **Hallazgo nuevo, crítico, confirmado por 3 refutadores independientes: la
0374 abrió un hueco al cerrar otro.** Reescribió `fn_rol_actual()` para que
una persona cesada no cuente como si tuviera rol — correcto en sí — pero dos
funciones `SECURITY DEFINER` (`fn_vacaciones_saldo` en 0357,
`fn_marca_apartada_resolver` en 0304) arman su guard con un `and not(...)`
suelto en vez de envolver todo el OR en un solo `is not true` (el patrón
correcto, ya usado en la 0126). Efecto: una persona cesada con sesión de Auth
viva puede leer el saldo de vacaciones de un excolega de su misma sede, y
resolver una marca apartada — si fue admin/líder/encargada, eso **escribe un
marcaje real** que alimenta jornada y pago de otra persona. **Falta una
migración nueva** que reescriba ambos guards al patrón de la 0126 — no
existe todavía, es lo primero que hay que escribir mañana.

⚠️ **Y esto no esperó al PDF: se le avisó a Felipe apenas se detectó, antes
de terminar el informe.** Mientras esta auditoría corría, 8 sesiones de
Claude Code abrieron 8 PRs en menos de una hora, todas atacando los mismos
hallazgos críticos de ayer (7, 10, 11, 12), sin verse entre sí — el mismo
patrón que ya costó la duplicación de `fn_vacaciones_por_vencer` (0297/0299).
Dos son duplicados byte a byte (#199/#197, hallazgo 11); dos resuelven la
misma regla con dos funciones distintas (#196/#194, hallazgo 12). Ninguno
fusionado a esta fecha. La comparación completa y qué PR conviene fusionar
en cada caso vive en `docs/hallazgos-abiertos.md`, sección de esta auditoría.

**Lo que ya se cerró desde ayer, verificado leyendo el código vigente (no
solo el mensaje de commit):** hallazgos 8, 13, 14, 15, 16, 17, 18, 21, 23, 25
y 33 resueltos por las migraciones 0360-0372; el 22 parcial (regenerar PIN
resuelto, alta de persona sigue hasheando en el navegador, impacto ya bajo).
El PIN del terminal (hallazgo 1) sigue como se documentó abajo: fusionado a
`main`, sin evidencia de despliegue ni de SQL pegado.

**Nuevo en el repo, para que la próxima auditoría no reinvente el HTML→PDF:**
[`scripts/auditoria-a-pdf.mjs`](../scripts/auditoria-a-pdf.mjs) — misma
técnica sin dependencias que `reglamento-a-pdf.mjs`, generalizada para un
documento que no vive en `docs/`.

31 agentes → 28 agentes esta vez (11 código nuevo, 8 vistazo general, 6
benchmark, 3 verificación adversarial), 0 errores, 4.31M tokens, ~30 minutos.

---

## 2026-09-05 — `db-tests` se ponía roja según la hora de Lima a la que corriera CI (293) · CORREGIDO

No es una migración rota: es la prueba
`supabase/tests/293_un_terminal_no_marca_por_otra_sede.test.sql`. Su aserción
PUERTA 2 fijaba la ENTRADA de Fabi a las 09:00 de Lima a mano. El candado que
defiende (`fn_marcaje_sede_permitida`, 0370) exige `corregido_at >=
timestamp_marca` para dejarla entrar, y `corregido_at` es el `now()` real de
cuando corre el test — así que la aserción solo pasaba si CI arrancaba
DESPUÉS de las 09:00 Lima. Confirmado con el push que fusionó el PR #161 (00:07
Lima, 2026-09-05): `db-tests` se puso roja en `main` sin que ese PR tocara
nada de marcaje, y arrastró consigo a cualquier rama nueva —incluidos los PR
[#197](https://github.com/felipea92p-ux/cayla-dynamic/pull/197),
[#205](https://github.com/felipea92p-ux/cayla-dynamic/pull/205) y este mismo
[#198](https://github.com/felipea92p-ux/cayla-dynamic/pull/198), cuyo
`db-tests` salió rojo por la misma razón — confirmado que **no** es un
defecto de la 0370 en sí, solo de la prueba.

**El mismo defecto lo encontraron y lo arreglaron, el mismo día, cuatro
sesiones distintas** (PR [#195](https://github.com/felipea92p-ux/cayla-dynamic/pull/195),
[#202](https://github.com/felipea92p-ux/cayla-dynamic/pull/202),
[#203](https://github.com/felipea92p-ux/cayla-dynamic/pull/203) y
[#205](https://github.com/felipea92p-ux/cayla-dynamic/pull/205)) — cada una sin
ver a las otras. El #203 fijó `corregido_at` a un instante concreto de «hoy»
(`fn_hoy_lima() + 09:01`); el #205 dejó la ENTRADA en `now() - interval '30
minutes'`. Las dos por separado son correctas. **Fusionadas juntas —el #203
primero, el #205 encima, sin conflicto textual porque tocan líneas
distintas— volvieron a hacer la prueba sensible a la hora real**: pasaba entre
las 00:00 y las 09:31 Lima y volvía a fallar después de esa hora, porque
`now() - 30min` termina cruzando las 09:01 fijas. Se cazó a los pocos minutos
porque el run de `main` en curso (10:22 Lima) iba directo a ese rango. Arreglo
final: las dos puntas de la comparación quedan FIJAS al mismo «hoy» —entrada a
las 09:00, `corregido_at` a las 09:01— sin ningún `now()` de por medio. Los
PR #195 y #202, redundantes, se cerraron sin fusionar.

**La lección, aparte del arreglo:** «GitHub dice CLEAN» solo significa que no
hay conflicto de texto — dos parches que tocan líneas distintas del mismo
predicado pueden combinarse en algo roto sin que git proteste. Antes de
fusionar dos PR que tocan el mismo archivo el mismo día, vale la pena leer el
resultado combinado, no solo cada diff por separado.

---

---

## 2026-09-05 — El PIN del terminal se retira (0375, [PR #188](https://github.com/felipea92p-ux/cayla-dynamic/pull/188)) · CERRADO — PEGADA Y VERIFICADA

Sale de la auditoría del 2026-09-03/04 (crítico 1 — el hash de PIN de toda la
sede viajaba al navegador del kiosco, `bcrypt.compare` corría en el cliente, y
`fn_registrar_marcaje` nunca recibía ningún PIN en sus argumentos). Es el mismo
hallazgo que `docs/revision-2026-07-15/E-seguridad.md` ya tenía anotado desde
julio, sin marcar como resuelto.

**Felipe, 2026-09-04: «el pin no me interesa, quiero agilidad».** Es la misma
decisión que `CLAUDE.md` lleva escrita desde julio —que marcar sea instantáneo
y que el control real sea la Mac mini a la vista del equipo, no una clave—. Lo
que había hasta hoy era esa decisión **apagada**, no retirada:
`terminales.requiere_pin` nació `not null default TRUE` (0012) y los terminales
se dan de alta a mano sin mencionar esa columna, así que caían en `true`; el
respaldo del navegador hacía lo mismo (`data.requiere_pin ?? true`). La próxima
Mac mini vinculada le habría pedido PIN sin que nadie lo hubiera pedido.

**Qué se retira:** la pantalla del teclado de PIN, `lib/terminal/pin.ts`, el
bloqueo a los 5 intentos, el campo `pinHash` del roster y la bandera
`requierePin`. En SQL (0375): el default pasa a `false`, las filas existentes a
`false`, y `terminal_roster` se recrea **sin `pin_hash`** — el kiosco deja de
descargarle a cada Mac mini el hash de toda su sede.

**Lo que NO toca, a propósito:** `personas.pin_hash` (sigue `not null`,
`fn_crear_persona` la exige) ni `fn_regenerar_pin`/su trigger de la 0364. Queda
anotada una deuda cosmética: `/admin/equipo` sigue ofreciendo «Nuevo PIN» por
persona aunque ya ningún terminal lo pida.

**Verificación:** prueba 297 corrida primero SIN la migración (falla 3/8, las
que afirman el cambio) y con ella 8/8. Suite completa 2188 aserciones, typecheck
limpio, 458 vitest.

⚠️ **El conflicto de fusión al traer `main`** (54+ commits de por medio, entre
ellos la 0372) fue solo en `scripts/sql-manual/que_falta_pegar.sql` —el generado
automático—, resuelto regenerándolo con `./scripts/que-falta-pegar.sh`, no a
mano. CI en verde (`db-tests`, `ui-tests`) tras el merge de `main`, y **recién
ahí se fusionó a main**, con el visto bueno de Felipe.

✅ **Paso 1 confirmado el 2026-09-05, sin que nadie lo hubiera anotado.**
Verificado con el CLI de Vercel (`npx vercel env ls` confirmó primero el
proyecto correcto, `cayla/cayla-dynamic`): la producción actual
(`cayla-dynamic.vercel.app`) corre el deploy `dpl_FDKGbke4xrR19WDAnbiieo1LWgzv`,
construido desde el commit `6f24bd7` — que trae tanto esta PR (#188) como la
#185 (items 2-6). El panel sin PIN ya está publicado; esta nota decía
«falta desplegar» y ya no es cierto.

✅ **Los tres pasos, completos el 2026-09-05:**

1. ~~Desplegar `apps/web` (Vercel)~~ — hecho.
2. ~~Comprobar en las cuatro Mac mini que la lista de nombres carga~~ —
   confirmado por Felipe.
3. ~~Pegar la 0375~~ — pegada y verificada. Los seis campos de la comprobación
   final salieron en el valor esperado: `cinco_columnas`, `sin_pin_hash`,
   `es_del_dueno`, `la_puede_leer` y `anon_no_puede` en `true`, y
   `el_default_ahora` en `false` (texto, no booleano — es el valor por defecto
   de la columna, correcto).

**Crítico 1 cerrado.** El terminal ya no pide PIN, y `terminal_roster` ya no
descarga el hash de toda la sede al navegador del kiosco.

---

## 2026-09-05 — Críticos 2-6 ([PR #185](https://github.com/felipea92p-ux/cayla-dynamic/pull/185)) · PANEL DESPLEGADO, 0370 Y 0371 PEGADAS Y VERIFICADAS

Esta PR nunca tuvo su entrada en `estado.md` — se fusionó a `main` sin dejar
nota. Los siete hallazgos que cierra están en el cuerpo de la propia PR:
terminal marcando a otra sede (0370), la mitad de «personas cesadas» ya estaba
cerrada (nada que hacer ahí), un aviso de vencimiento que se saltaba a quien
llegó después (0371), el borde de 16 h entre terminal y navegador, el error de
«Descanso médico» invisible detrás del modal, «Marcar como pagada» sin
confirmación ni reversión, y las contraseñas de 6 caracteres sin complejidad.

✅ **El panel ya está desplegado** — mismo commit `6f24bd7` que la 0375 de
arriba, confirmado con el CLI de Vercel el 2026-09-05.

✅ **0371 pegada y verificada el 2026-09-05.** Sus prerrequisitos (0356, 0357)
ya estaban aplicados desde el 04/09, así que su guardia la dejó pasar sin
avisos. Comprobación final: `firma_intacta=1, arreglo_puesto=2,
canal_en_la_clave=2, cron_programado=1` — los cuatro exactos.

✅ **0370 pegada y verificada el 2026-09-05.** Antes de pegarla se corrió la
consulta «⚠ CÓRRELA ANTES DE PEGAR» de su propio archivo (marcas de terminal
de los últimos 30 días que el candado nuevo rechazaría): **0 filas**, nadie
se queda bloqueado. La comprobación final devolvió los seis `true` esperados
(`existe_la_regla_de_sede`, `existe_el_candado`, `el_candado_del_cese_sigue`,
`el_roster_usa_la_regla`, `la_lectura_usa_la_regla`,
`la_policy_de_lectura_sigue_puesta`).

Con esto, los críticos 2-6 quedan **completos**: código en producción desde
antes, y las dos migraciones que faltaban ya están pegadas.

---

## 2026-09-05 — El 9% de la Ley 30334 dejaba de pedirse solo (0372) · PEGADA Y VERIFICADA — SIN IMPACTO EN LO YA PAGADO

Sale de la auditoría del 2026-09-03/04 (hallazgo 8).

**El defecto.** Desde la 0346 la gratificación y el 9% son dos movimientos
separados —lo pidió el contador—, pero `fn_provisiones` seguía decidiendo si el
9% estaba pagado mirando ÚNICAMENTE si existía un movimiento de gratificación en
esa ventana. El 9% no tenía cuenta propia: se calculaba como el 9 % de la
gratificación PENDIENTE, así que heredaba su resta entera y caía a cero con ella.

Quien registraba solo «Gratificación» —el camino manual, que sigue existiendo
porque el desplegable no obliga a nada— dejaba de ver el 9 % como pendiente, y
ninguna pantalla volvía a mencionarlo. Medido en local, en `BEGIN … ROLLBACK`:
con S/585.51 de gratificación devengada, el 9 % pendiente pasaba de **S/52.70 a
S/0.00** al registrar la gratificación sola.

Antes de la 0346 esa regla era correcta por convención —el 9 % viajaba DENTRO
del monto de «Gratificación», así que gratificación pagada ⇒ 9 % pagado—. La
0346 rompió la convención a propósito y nadie actualizó esta función.

**El arreglo.** El 9 % obtiene devengado propio y cobrado propio. Se da por
saldado si existe su movimiento, **o** si la gratificación de esa ventana se
registró antes del 2026-09-03, cuando el 9 % todavía viajaba dentro y no había
otra forma de pagarlo. Esa segunda condición es la decisión ya tomada al pegar la
0346 —«no se corrige lo ya pagado»—: sin ella, esta migración le habría inventado
al sistema una deuda del 9 % sobre TODO el historial de gratificaciones.

La propiedad que conserva, y que la prueba 295 fija: donde el 9 % ya está
saldado, el número nuevo es EXACTAMENTE el mismo que daba la fórmula anterior.
Solo cambia el caso que nadie miraba.

✅ **Pegada en producción el 2026-09-05, con las ocho comprobaciones en verde**,
incluidas las dos que importaban: `conserva_la_0365` (no revirtió el aviso de
tramo de salario) y `la_pantalla_puede` (no perdió el `grant` que la 0363 había
tenido que reponer). **El `md5_llegada` de producción —`6f33984ae7ce841d9dcbb…`—
coincidió exacto con el medido en local**, así que las dos bases quedaron byte
por byte iguales. Y `la_0346_se_aplico_el` devolvió `2026-09-03`, confirmando que
la constante de corte mira el día correcto.

✅ **Medido antes de pegar: a nadie le apareció una deuda nueva.** La consulta
[`a_quien_le_aparece_el_9_por_ciento.sql`](../scripts/sql-manual/a_quien_le_aparece_el_9_por_ciento.sql)
devolvió **cero filas**: la gratificación de julio se registró antes del corte
—con el 9 % dentro, como correspondía— y desde que existe la opción separada
nadie ha registrado una sin su 9 %. El arreglo llega antes del momento en que
importa, que es el depósito del **15 de diciembre**.

⚠️ **EL CASI-ACCIDENTE, que es lo que conviene leer de esta entrada.** Se
escribió primero como **0362, sobre el cuerpo de la 0338**. En las horas que
tardó en verificarse, otras sesiones fusionaron **54 commits**: alguien tomó el
número 0362 y la prueba 288, y —lo grave— `fn_provisiones` se reescribió DOS
veces (la 0363 le devolvió el `grant execute … to authenticated` que la 0338
nunca concedió; la 0365 le agregó el aviso de tramo de salario en cinco sitios).

Pegar aquella versión habría revertido las dos en silencio, y la pantalla de
Provisiones habría dejado de responderle a `authenticated`. **Lo cazó volver a
correr `donde-vive.sh` en el mensaje en que se entregaba el SQL, no en el que se
empezó a escribirlo.** Es la regla que el CLAUDE.md ya tenía escrita desde la
avería del 2026-08-25, y este es el caso que la justifica por segunda vez.

**Lo que NO hace, a propósito:** no le abre ventana propia al 9 % en el libro de
desembolsos (`desembolsos_beneficios.ventana` solo admite las cinco de siempre),
así que quien pague el 9 % POR FUERA del sistema sigue sin poder anotarlo; y no
toca `fn_grati_trunca_bruta`, que calcula el 9 % al cesar con la tasa CLAVADA en
`0.09` (0343:303) en vez de leerla versionada. Ese es un defecto distinto, de
otro camino, y mezclarlos habría hecho esta migración imposible de auditar de una
pasada.

**Y una deuda de pantalla que queda anotada:** `/admin/provisiones` ahora dice la
verdad, pero nada avisa en el momento del pago. Quien registre «Gratificación»
sin el 9 % no ve ninguna advertencia ahí mismo — se entera al abrir Provisiones
después. El botón «Agregar todo» de la 0355 lo resuelve por el camino feliz; el
manual sigue abierto.

---

## 2026-09-04 — `que-falta-pegar.sh` acusaba en falso a `fn_planilla_calcular` de estar atrasada · PR #190 FUSIONADO

Al pedir las migraciones 0358 y 0359 para pegar, la consulta de qué falta pegar
las marcó "FALTA PEGAR" — pero el cuerpo real de `fn_alertas_email_pendientes`
en producción ya era el de la 0362 (confirmado con `pg_get_functiondef` corrido
en vivo contra producción), varias versiones más adelante. El registro
(`migraciones_aplicadas`) tenía un hueco, no el código: se cerró con un
`insert` puntual para 358 y 359 —y luego para la 353, mismo caso—, sin tocar
ninguna función ni tabla.

Al volver a correr `que-falta-pegar.sh` completo apareció algo más serio: la
fila PLANILLA decía que `fn_planilla_calcular` "se quedó en la 0339 — falta
pegar lo posterior". Era un falso positivo del propio generador, no un atraso
real: desde que la 0339 partió la función en núcleo + envoltorio, el
envoltorio no volvió a cambiar de texto, así que su md5 en la 0339 y en la
0349 (la última que la redefine) es idéntico. El script emitía dos `WHEN` con
ese mismo md5 —uno mal etiquetado antes que el correcto—, y un `CASE` de SQL
se queda con el primero que coincide. Producción nunca estuvo atrasada.

**Arreglado en `scripts/que-falta-pegar.sh`:** el `WHEN` del md5 vigente se
imprime siempre primero, sin importar cuántas migraciones viejas compartan el
mismo texto.

**De paso, se investigó y documentó el hueco de numeración de la 0352**
(`scripts/hooks/huecos-conocidos.txt`): dos sesiones construyeron el mismo día
la misma idea —el aviso de auto-cierre por correo—, una como 0352 y otra como
0354; al fusionar (commit `7809713`) se descartó la 0352 a propósito porque la
0354 resuelve lo mismo sin tocar `fn_auto_cierre`. Nunca se aplicó en
producción.

[PR #190](https://github.com/felipea92p-ux/cayla-dynamic/pull/190), fusionado por Felipe el 2026-09-04.

---

## 2026-09-04 — `fn_registrar_marcaje` quedó con dos sobrecargas en producción (0367) · PEGADA Y VERIFICADA

Felipe reportó en vivo que el terminal (marcando `retorno_almuerzo` y
`salida_almuerzo`) y el botón "Registrarla con su hora" de Correcciones
—sobre una marca apartada— fallaban con «Could not choose the best candidate
function» / «function fn_registrar_marcaje(...) is not unique». Es el mismo
accidente que ya le pasó a `fn_vacaciones_por_vencer` el 2026-08-25.

**Qué pasó.** La 0353 agregó `p_confirmo_sin_refrigerio` a
`fn_registrar_marcaje` (de 8 a 9 argumentos) y, precisamente para evitar este
accidente, su propio texto ya traía el `drop function if exists` de la
sobrecarga vieja antes del `create or replace`. Ese `drop` no llegó a tomar
efecto en producción — el porqué exacto no se pudo determinar sin acceso de
servicio, y no hizo falta para diagnosticarlo: el error en pantalla lista los
dos candidatos completos (8 y 9 argumentos), así que confirma sin ambigüedad
que las dos sobrecargas conviven ahí. Localmente, aplicando la 0353 completa
con `supabase db reset`, el `drop` sí funciona y deja una sola versión — el
problema es específico de cómo quedó producción, no del contenido de la 0353.

Bloqueaba las dos cosas a la vez: marcar normal Y repararlo (`fn_registrar_marcaje`
es la única puerta de escritura de marcajes — ver CLAUDE.md).

**Arreglo (0367):** repite el mismo `drop function if exists` de la 0353, más
`notify pgrst, 'reload schema'` (para que PostgREST no siga sirviendo desde su
caché). No toca la versión de 9 argumentos ni su cuerpo. Auditado local:
`supabase db reset` completo (aplica las 0001–0367 en orden) y `supabase test
db` — 205 archivos, 2036 pruebas, todas en verde.

**SQL entregado a Felipe con `dame-el-sql.sh` una vez fusionado a `main`**
—la urgencia (producción bloqueada en vivo) llevó primero a pasarlo directo
en el chat, y ese mismo mensaje llevó a fusionar el PR ([#181](https://github.com/felipea92p-ux/cayla-dynamic/pull/181))
antes de entregar nada, para que el script pudiera verificarlo contra
GitHub. **Confirmado en producción el 2026-09-04**: el `select` final devolvió
una sola fila —
`fn_registrar_marcaje(uuid,tipo_marca,timestamp with time zone,uuid,origen_marca,uuid,uuid,text,boolean)`,
`pronargs = 9`—, así que la sobrecarga vieja quedó retirada.

---

## 2026-09-04 — A la 0353 le faltaba su columna en producción (0373) · PEGADA Y VERIFICADA

Segunda mitad del mismo accidente que la 0367 (arriba), encontrada en una
sesión distinta que investigaba en paralelo. La 0353 trae TRES partes en un
solo archivo —el `alter table` que agrega `marcajes.confirmo_sin_refrigerio`,
el `drop function` de la sobrecarga vieja, y el `create or replace` de la
función nueva de 9 argumentos— y en producción solo había llegado a aplicarse
la tercera. Con la 0367 ya pegada y la ambigüedad de firmas resuelta, la
función de 9 argumentos empezó a correr sola y chocó más adentro: siempre
escribe en `confirmo_sin_refrigerio` (está en el `insert` y en el `update` de
reconciliación de `salida_final`), y esa columna no existía en la tabla.

**Confirmado en el panel de Incidencias**, con marcas reales rechazadas el
mismo día: Daniel Ruiz (OTRU) y Felipe Alvarez (CCO), `salida_almuerzo` y
`retorno_almuerzo`, con el error tal cual —
`column "confirmo_sin_refrigerio" of relation "marcajes" does not exist`—.
El `retorno_almuerzo` de cada uno fallaba en cadena por la misma causa: al no
insertarse la `salida_almuerzo`, `fn_siguiente_tipo_esperado` ya no
reconocía el tramo y rechazaba el siguiente toque.

**Arreglo (0373):** `alter table marcajes add column if not exists
confirmo_sin_refrigerio boolean` — aditivo, idempotente, no toca ninguna
función. Auditado local: `supabase db reset` completo (0001–0373, incluida la
0367 y la 0366 sobre la misma función) y `supabase test db` — 212 archivos,
2155 pruebas, todas en verde. **Confirmado en producción el 2026-09-04**: la
consulta a `information_schema.columns` devolvió la columna, y la consulta de
`fn_registrar_marcaje` volvió a devolver una sola fila (9 argumentos) después
de pegar ambas migraciones.

**Pendiente que no se arregla solo:** las marcas de Daniel Ruiz y Felipe
Alvarez que rebotaron durante la ventana rota ya agotaron sus 6 reintentos y
quedaron **apartadas** (0304) — hay que resolverlas a mano una por una desde
Correcciones ("Registrarla con su hora"), ahora que la columna ya existe.

---

## 2026-09-04 — Auditoría del 2026-09-04: los importantes 25 a 34 (0368) · PEGADA Y VERIFICADA

Segunda tanda de diez, pedida por Felipe justo después de la primera. Nueve son
solo panel; una lleva SQL.

| Hallazgo | Qué se hizo |
|---|---|
| 25 El terminal decía «Nadie en esta sede todavía» mientras cargaba | Tres estados con tres textos, y botón de reintentar en el fallo |
| 26 «Exportar CSV» lo veía cualquier cuenta | Permiso nuevo en `permisos.ts` con su prueba, filtro en el menú y guardia en la propia pantalla |
| 27 La ficha decía «Sin antecedentes disciplinarios. Buena señal.» si fallaba la consulta | Se captura el error de cada consulta por separado |
| 28 El PIN nuevo duraba 4,5 s en un aviso que se autodestruía | Panel fijo con botón de copiar y cierre explícito |
| 29 Cuentas se veía vacía en vez de mostrar el error | Se revisa `res.ok`/`data.error` como el resto de la pantalla |
| 30 El historial de correcciones no decía de qué día era el marcaje | `describirCambio` deja de tirar la fecha |
| 31 El reporte por sede salía en blanco desde una sede inactiva | No se ofrece «Hoja» para inactivas, y se dice por qué si el código no está |
| 32 Cambiar la clave mandaba siempre al dashboard | Misma resolución de rol que ya hacía login |
| 33 Dos sesiones se pisaban un código de sede en silencio | **Migración 0368** + prueba 292: el alta con código repetido lanza |
| 34 La fecha de Disciplina congelaba la fila | Input de fecha que nace con hoy, con `try/catch` |

Verificado el 2026-09-04: `supabase db reset` limpio, `supabase test db` 212
archivos y 2155 pruebas, typecheck 3/3, vitest 439/439, y cero errores de linter
en líneas nuevas (los 35 que salen son deuda vieja, comprobado cruzando con las
líneas que el push agrega).

**Cuatro hallazgos que bloqueaban, cazados por las revisoras adversariales:**

- El estado de error del terminal era **inalcanzable**: `roster.ts` se tragaba
  cualquier fallo de red y devolvía la caché, así que una Mac mini recién
  reiniciada y sin caché seguía leyendo «Nadie en esta sede todavía» — justo el
  caso del hallazgo. Hubo que sumar `roster.ts` al alcance.
- El arreglo del 30 cubría `marcaje_eliminado`, que **hoy no lo escribe nadie**, y
  dejaba fuera `marcaje_anulado`, `marcaje_reactivado` y
  `auto_cierre_reemplazado`, que son los que produce el propio botón de esa
  pantalla. Se enumeró qué escribe cada función en `correcciones_auditoria` en
  vez de deducirlo por el nombre.
- El «se revierte» de la 0368 afirmaba algo falso sobre PostgREST, y lo afirmaba
  en el procedimiento que alguien lee cuando ya hay algo roto en producción. La
  revisora lo midió acuñando un JWT y lo corrigió.
- El menú filtraba por un permiso que no existía todavía en `permisos.ts`.

**Nació como 0367 y se renumeró a 0368**: `claude/mensajes-molestos-5950e5` tomó
ese número el mismo día para retirar la sobrecarga vieja de
`fn_registrar_marcaje`. Importa más que de costumbre porque
`migraciones_aplicadas` tiene el número como clave: con las dos en 0367, la
segunda que se pegara habría quedado SIN registrar, en silencio, por el
`on conflict (numero) do nothing`.

**Al pegar la 0368** se encontró y corrigió, antes de entregarla, un descuido
propio: la consulta de comprobación del final había quedado preguntando por la
migración 367 (rastro de cuando esta migración nació con ese número), así que
`anotada` habría dado `true` sin importar si el 368 se registraba. Arreglado en
el repo antes de pegar.

**Confirmado en producción el 2026-09-04**, con el md5 de `fn_guardar_sede`
coincidiendo `tal_cual` contra producción antes de pegar, y la comprobación del
final devolviendo todo en verde: una sola versión con la firma nueva de cinco
argumentos, anotada en `migraciones_aplicadas`, `authenticated` puede llamarla
y `anon` no, y el candado único de `codigo` sigue ahí.

**Queda abierto y anotado:** `fn_crear_persona` sigue recibiendo el hash del PIN
desde el navegador — es la otra mitad del hallazgo 22, que la 0364 solo cerró
para `fn_regenerar_pin`. Y el hallazgo 19 (contraseñas temporales que no obligan
a cambiarse) no entró en ninguna de las dos tandas.

---

## 2026-09-04 — Auditoría del 2026-09-04: los importantes 14 a 24 (0360-0366) · PEGADAS EN PRODUCCIÓN

> Felipe las pegó todas el mismo día. La duda que dejó abierta esta nota —si
> `fn_registrar_marcaje` quedó con una sola versión tras la 0366— ya se
> resolvió, pero por otro camino: sí quedaron dos sobrecargas (8 y 9
> parámetros), lo cazó la 0367 de `claude/mensajes-molestos-5950e5` y quedó
> confirmado en producción (ver esa entrada, arriba).

Felipe pidió arreglar «las 10 primeras» de la tabla de importantes de la
auditoría adversarial del 2026-09-03/04 (el PDF `Auditoria-CAYLA-2026-09-04.pdf`,
57 hallazgos; no vive en el repo): 14, 15, 16, 17, 18, 20, 21, 22, 23 y 24.
Rama `claude/primeras-10-correcciones-08ce78`. Los críticos 1-12 (PIN del
terminal, sede del terminal, contraseñas, liquidaciones…) siguen abiertos.

| Hallazgo | Qué se hizo | Migración · prueba |
|---|---|---|
| 14 Horarios: corregir un tramo retroactivo reventaba con `horarios_sin_solape` en inglés | `fn_set_horario_semanal` recorta cualquier tramo que pise la fecha, no solo el abierto; `mensaje-error.ts` traduce el candado | 0360 · 286 |
| 15 Objetivos: «Copiar del mes anterior» duplicaba con doble clic | candado de transacción por persona antes de preguntar si el mes está vacío + `not exists` en el insert; pestillo en la pantalla | 0361 · 287 |
| 16-18 Alertas por correo: doble envío, corte a los 10 s, fallo perdido para siempre | reserva compare-and-set antes de enviar (`fn_alertas_reservar`), `maxDuration = 60`, reintento hasta 3, ventana de 7 días, Sentry por cada fallo, `fn_alertas_despacho_resumen` + tarjeta en la Bandeja para DO | 0362 · 288 (y la 281 ajustada) |
| 20 Cuatro funciones de turnos sin revoke de PUBLIC/anon | **Refutado con medición**: ya las cierra la 0076 (bucle + `alter default privileges`), `anon = false` en las cuatro; anotado en `hallazgos-abiertos.md` con la consulta para producción | — |
| 21 Doble toque en el terminal dejaba dos entradas (y dos salidas finales) | `fn_registrar_marcaje` toma un candado por persona y, solo para el terminal, devuelve la marca del mismo tipo a ±2 min sin otra en medio | 0366 · 289 |
| 22 «Nuevo PIN» hasheaba en el navegador y escribía `pin_hash` por REST | `fn_regenerar_pin` genera y hashea en Postgres (bcrypt `$2a$10$`, comprobado contra la bcryptjs del terminal); trigger que cierra la columna a `authenticated`/`anon` | 0364 · 290 |
| 23 Provisiones: sin tramo de salario salía S/ 0.00 igual que «no le toca» | `fn_provisiones` gana `sin_salario_vigente`, `dias_sin_salario` y `personas_sin_salario`; insignia, aviso y CSV. **El número no cambia** (medido fila por fila) | 0365 · 291 |
| 24 La casilla decía «S/ 113 fijos por periodo» | `montoAsignacionFamiliar` lee `parametros_laborales` (respaldo `configuracion`); la etiqueta muestra el monto real o manda a Configuración | — (solo panel) |

Verificado en esta Mac el 2026-09-04: `supabase db reset` limpio con las seis
migraciones, `supabase test db` 211 archivos / 2139 pruebas, typecheck 3/3,
vitest 434/434, eslint sin errores en líneas nuevas. Cada paquete pasó por dos
revisoras adversariales (corrección/plata y reglas de la casa); las dos cosas
que bloqueaban se corrigieron antes de commitear: el resumen de alertas contaba
como «caducado» el backlog de julio que la 0354 dejó fuera a propósito, y la
0365 tenía que conceder el `execute` que la 0338 olvidó (ver abajo).

**Qué pegar, en este orden, y qué pedir ANTES de cada una** (el md5 de
partida local está en cada encabezado; `donde-vive.sh` imprime la consulta):

1. 0360 — pedir md5 de `fn_set_horario_semanal` (esperado: el de la 0327).
2. 0361 — `fn_objetivos_copiar_mes_anterior` (esperado: el de la 0348).
3. 0362 — `fn_alertas_email_pendientes` (esperado: el de la 0359) y
   `fn_marcar_alerta_resultado` (0354). **Pegarla ANTES de desplegar el panel**:
   la ruta nueva llama a `fn_alertas_reservar` y sin ella el cron responde 500.
4. 0364 — funciones nuevas: confirmar que `fn_regenerar_pin` no existe todavía.
   También antes de desplegar el panel: «Nuevo PIN» la llama.
5. 0365 — `fn_provisiones` (esperado: el de la 0338) **y su `proacl`**.
6. 0366 — `fn_registrar_marcaje` (esperado: el de la 0353). Nació como 0363 y se
   renumeró: `claude/error-investigation-17ac66` había tomado el 0363 veintisiete
   segundos antes —para el grant de `fn_provisiones`, la misma línea que trae la
   0365— y el hook de numeración no alcanzó a verlo en ese push.

⚠️ **Provisiones puede llevar rota en producción desde la 0338 (2026-09-01).**
La 0338 hizo `drop function fn_provisiones(date)` y creó la firma `(date, date)`
sin `grant execute … to authenticated`; con la revocación por defecto de la
0076, en un Postgres construido desde las migraciones `authenticated` recibe
«permission denied» al llamarla — y `/admin/provisiones` la llama así. La 0365
deja el grant escrito. Para saber si producción lo tiene hoy:
`select has_function_privilege('authenticated', 'fn_provisiones(date, date)', 'execute');`
— si dice `false`, la pantalla de Provisiones no abre desde el 1 de septiembre y
la 0365 lo arregla al pegarla. La rama `claude/error-investigation-17ac66` llegó
a lo mismo por otro camino y trae el grant solo, como su 0363: si se pega esa
primero, la línea de la 0365 queda redundante e inofensiva.

**Visto de paso, sin tocar (para su propio lote):**

- La prueba **274** (`el_generador_hace_indefinidos`) se pone en rojo según el
  plan de consulta: registra dos contratos en la misma transacción, los dos
  quedan con el mismo `generado_at`, y el lateral `u` de `fn_contratos_tablero`
  (0347) ordena solo por `generado_at desc` — el empate lo decide Postgres.
  Pasó en la primera corrida de la suite y falló en la segunda y a solas. El
  arreglo es un desempate en la función (`generado_at desc, id desc` o similar)
  y una prueba que no dependa del empate.
- La política `alertas_marcar_leida_propia` (0003) más `grant update on alertas
  to authenticated` dejan que una integrante edite CUALQUIER columna de sus
  propias alertas (estado, intentos…). Preexistente; la 0362 lo amplía un poco.
  **Cerrado por la 0550** (2026-10-25): ver la entrada de arriba.
- `fn_crear_persona` sigue recibiendo el hash del PIN desde el navegador, y el
  terminal sigue comparándolo con bcryptjs en el cliente: es el crítico 1.
- `fn_planilla_calcular` conserva `coalesce(…, 113.00)` como respaldo escrito
  a mano de la asignación familiar (0339): el mismo defecto del 24, en el
  sitio que paga.
- `fn_feriado_devengado`: un feriado que cae dentro de un bloque 29→28 con el
  tramo de salario cerrado a mitad valora horas de días sin tramo (S/ 7,69
  medidos en la 291). No es de la 0365; queda documentado en esa prueba.

---

## 2026-09-04 — `fn_provisiones` se quedó sin permiso de ejecución desde la 0338 (0363) · PEGADA Y VERIFICADA

La 0338 le agregó un parámetro a `fn_provisiones` (de `fn_provisiones(date)` a
`fn_provisiones(date, date)`); como Postgres no reemplaza en el sitio cuando
cambia la firma, esa migración hizo `DROP FUNCTION` + `CREATE OR REPLACE`, y
el nuevo objeto nació sin el `GRANT EXECUTE` para `authenticated` — desde la
0076 esta base no regala EXECUTE por defecto. Cualquier llamada a
`fn_provisiones` desde el panel devolvía «permission denied for function»
antes de que el cuerpo llegara a correr; no era un bug de la pantalla de
Provisiones, la función nunca llegaba a ejecutarse.

**Arreglo (0363):** un `grant execute` de una sola línea, sin tocar el
cuerpo ni el md5 de la función. Llegó a `main` vía [PR #180](https://github.com/felipea92p-ux/cayla-dynamic/pull/180)
desde otra sesión (`claude/error-investigation-17ac66`) mientras esta rama
fusionaba la 0344/0345 — se cruzaron sin chocar en la numeración.

**Confirmado en producción el 2026-09-04**, corriendo la comprobación que
la propia migración deja al final:
`has_function_privilege('authenticated', 'fn_provisiones(date,date)', 'EXECUTE')` → `true`.

---

## 2026-09-03 — El patrón «función guardián» queda escrito como convención (CLAUDE.md) · CERRADO

Hallazgo #2 de la comparación Workday/Oracle, y uno de los 16 de la auditoría
de arquitectura del mismo día: el molde que ya usan `fn_cambiar_regimen_pension`
(0261), la puerta de rol (0295/0296) y `fn_set_sede_base` (0342) —guard +
`update` auditado + trigger que rechaza el `UPDATE` directo comparando
`current_user <> 'postgres'`— se había reinventado tres veces sin declararse
nunca como regla. No había ningún código que arreglar: las tres funciones ya
funcionan bien. Lo que faltaba era que dejara de transmitirse por comentarios
cruzados entre migraciones y quedara escrito una vez.

**Arreglo:** un principio nuevo en [`CLAUDE.md`](../CLAUDE.md), sección
"Principios del sistema", junto a los otros principios de guardas
(`SECURITY DEFINER null-safe`, `fn_registrar_marcaje` como única puerta).
Nombra el mecanismo exacto y las tres instancias, para que la próxima columna
sensible lo siga por regla y no por memoria. Marcado como cerrado en
[`hallazgos-abiertos.md`](hallazgos-abiertos.md).

---

## 2026-09-03 — La misma alerta de auto-cierre, construida dos veces sin saberlo (0354 y la 0352 descartada)

Al abrir el PR de esta rama (severidad en Incidencias, reporte de inspección
en Exportar, confirmación de refrigerio al marcar salida, aviso de
auto-cierre por correo), `main` ya traía **dos** de esas cuatro cosas,
construidas por otra sesión el mismo día: el reporte de inspección en
Exportar (marcajes crudos + auditoría de correcciones — commit `241fd96`) y
el aviso de auto-cierre por correo (`fn_alertas_email_pendientes` +
`/api/alertas-encargadas`, migración 0354). Ninguna de las dos sesiones vio a
la otra: la regla de CLAUDE.md de mirar `git log --all` antes de empezar no
se siguió al comenzar el aviso de correo.

**Se descartó la versión de esta rama en ambos casos**, no por estar mal
sino porque la de `main` llegó primero y, en el caso del correo, es más
segura: la 0354 deliberadamente NO toca `fn_auto_cierre` (7 reescrituras de
historia, cambiarla exige el protocolo de md5 completo) — lee "quién es la
encargada" al momento de despachar, no al escribir. La versión descartada de
esta rama sí reescribía `fn_auto_cierre` para eso. Se prefirió la opción que
no tocaba la función con más historia.

**Lo único que faltaba de verdad en la 0354** era el pedido explícito de
Felipe: que el correo llegue también a la propia persona, no solo a su
encargada. Eso se agregó como una extensión pequeña de
`fn_alertas_email_pendientes` — migración **0359**, prueba 285 — en vez de
reconstruir el sistema. Y la confirmación de refrigerio al marcar salida
(0353) sí era trabajo nuevo sin duplicar — esa se mantiene tal cual.

**RECONCILIADO:** mientras se escribía la 0359, `claude/cola-alertas-vencimiento`
fusionó a `main` su propia 0358 (reenruta `contrato_por_vencer` y
`vacaciones_por_vencer` a DO, y deja `auto_cierre` explícitamente sin
tocar). El primer push de la 0359 lo cazó el hook (`main tiene 3 migración(es)
que esta rama no tiene... TOCÁIS LAS MISMAS FUNCIONES`) antes de que se
pegara nada. La 0359 se reescribió por completo sobre el cuerpo real de la
0358 (el `with combinado as (... union all ...)`, confirmado con
`git show origin/main:...0358...sql`, no el viejo de la 0354) — extiende
solo la Rama 1 (auto_cierre y afines) para agregar a la propia persona; la
Rama 2 (0356/0357, ya directa a `al.persona_id`) queda intacta. Verificado
localmente aplicando 0356→0359 en orden: las cuatro pruebas relacionadas
(282, 283, 284, 285) pasan las 30 aserciones juntas, sin que ninguna
interfiera con la otra.

**La lección de método, otra vez:** `git log --all --oneline -20` antes de
empezar algo cuesta diez segundos. Esta vez costó descartar una migración
completa, un endpoint entero y una dependencia (`nodemailer`, después
cambiada a `resend`) que nunca llegaron a pegarse en producción — caro en
tiempo de sesión, no en riesgo real, porque ninguna de las dos versiones
descartadas se había pegado.

---

## 2026-09-03 — Un clic agrega la gratificación, la bonificación 9% y la CTS pendientes de todo el periodo (0355) · PEGADA Y VERIFICADA

Lo pidió Felipe justo después de probar la 0346 en pantalla: quiere el mismo pedido para Gratificación y CTS, que llevan meses siendo 100% manual (una persona, un clic, repetido para todo el equipo).

**Se descartó la escritura automática al llegar la fecha.** La razón salió de la propia prueba en pantalla: al probar con una integrante real, su bonificación propuesta dio S/0.00 — correcto, porque su gratificación de ese semestre ya estaba pagada — pero un proceso que escribe solo no distingue «correctamente cero» de «algo salió mal»; las dos se ven idénticas. Con una persona confirmando antes de que el número se vuelva plata, ese distingo lo sigue haciendo alguien.

**Lo que sí se construyó:** `fn_grati_cts_agregar_pendientes(periodo_id)` — reutiliza `fn_grati_cts_periodo` para el monto (cero cálculo nuevo) y `fn_agregar_movimiento` (la única puerta de escritura) para cada intento. Cada persona/categoría es su propio `begin … exception` (un SAVEPOINT implícito): si una falla —por ejemplo, su sede sigue con el periodo bloqueado— las demás igual se registran, y la que falló queda listada con el motivo exacto. En Planilla hay un banner nuevo con el total pendiente y un botón «Agregar todo», con confirmación antes de escribir y un resumen de éxitos/fallos después.

Auditado local (`supabase db reset` + 1990 pruebas en verde) y a mano contra Postgres, `BEGIN … ROLLBACK`, cuatro casos: normal (dos personas, S/25.00 grati + S/2.25 bonificación cada una, 9% exacto), «ya pagada» (se salta sin intentarlo, no aparece en agregados ni en fallidos), correr la función DOS VECES seguidas (la segunda no agrega nada) y «periodo bloqueado» (el intento de esa persona falla solo, sin tumbar a las demás).

Fusionada a `main` el 2026-09-03 ([PR #171](https://github.com/felipea92p-ux/cayla-dynamic/pull/171), CI en verde) y **pegada en producción el mismo día**: confirmado con `select count(*) from pg_proc where proname = 'fn_grati_cts_agregar_pendientes'` → `1`. La 0346 (el mismo pedido, solo para la bonificación 9%) también quedó confirmada contra producción el mismo día — ver su propia entrada más abajo. Con las dos pegadas, el flujo completo (Gratificación + Bonificación 9% + CTS, con «Agregar todo») ya está disponible en el panel real.

---

## 2026-09-03 — Anuncios: el tablón de Desarrollo Organizacional (0351) · PEGADA Y VERIFICADA

Salió de comparar CAYLA contra seis sistemas de RRHH de talla mundial
(Workday, SAP SuccessFactors, ADP, UKG/Kronos, Rippling, BambooHR): de
BambooHR se adoptó la idea de un tablón de comunicados dentro del sistema,
en vez de que "cierra la planilla el 28" o "el lunes es feriado" solo exista
en un chat de WhatsApp. [PR #166](https://github.com/felipea92p-ux/cayla-dynamic/pull/166).

Publicar y anular quedan solo para DO (`puedeGestionarAnuncios`, nuevo en
`permisos.ts`), con lectura filtrada por sede vía RLS — no solo por la
función. Deliberadamente NO reusa `documentos_institucionales` (Normas):
"leído" es un marcador liviano, no un acuse legal, así que no le pide a
nadie el trámite de una firma por cada aviso operativo. Pantalla en
`/admin/anuncios`, sin contador en el menú (un anuncio no tiene fecha límite
que cueste plata pasarla — misma vara que ya usa `nav.tsx`), y una tarjeta
en "Lo mío" que solo aparece si hay algo sin leer.

Auditada con `npx supabase test db` (prueba 278, 18 casos: solo DO
publica/anula, filtro por sede a nivel RLS y no solo de RPC, lectura
idempotente) y probada en el navegador contra el panel real antes de
fusionar. Verificada en producción el 2026-09-03: la consulta de
comprobación del final de la 0351 devolvió las seis piezas en 1 (tabla
`anuncios`, tabla `anuncios_leidos`, `fn_publicar_anuncio`, `fn_anular_anuncio`,
`fn_anuncios_vigentes`, `fn_marcar_anuncio_leido`).

---

## 2026-09-03 — Aviso cruzado: `main` va dos migraciones atrás de producción (0344/0345) · RESUELTO (2026-09-04)

Comprobado contra producción a pedido de Felipe (`select numero, nombre, aplicada_at from migraciones_aplicadas where numero in (344, 345)`): la **0345** (corrige el comentario de `topes_educacion_rango`, no toca datos) llegó a `main` el 2026-09-03. Por separado, la rama `claude/error-new-request-f3a806` traía la **0344** (`fn_set_documento` ya no exige motivo de cambio al cargar el DNI por primera vez), aplicada en producción el mismo día 16:41 UTC pero sin fusionar todavía. El hueco de numeración que eso dejaba ya se había investigado y no era una migración perdida: estaba pusheada a origin, solo en tránsito.

**Fusionada el 2026-09-04.** `main` ya trae las dos y vuelve a coincidir con lo que producción corre.

---

## 2026-09-03 — Auditoría de arquitectura: 16 hallazgos nuevos siguiendo la comparación con otros ERP

23 agentes (6 de investigación + 1 escéptico por cada candidato) sobre la
comparación Workday/Oracle del día anterior: primitivos de BambooHR/Gusto/
Rippling, de Odoo HR/Payroll, y cuatro frentes del código real (campos
mutables sin historia, patrones duplicados, huecos de auditoría, integración
ausencias↔planilla). 17 candidatos evaluados, **16 sobrevivieron al
escéptico, 1 refutado**. El catálogo completo, con evidencia y severidad, está
en
[`hallazgos-abiertos.md`](hallazgos-abiertos.md#auditoría-de-arquitectura-del-2026-09-03--comparación-contra-otros-erp-23-agentes).

**Los 7 de severidad alta, en una frase cada uno:**
`fn_aprobar_ausencia` (la única puerta que "convierte días en plata") es la
única sin el candado de periodo pagado · `fn_cesar_persona` no deja rastro en
`correcciones_auditoria` · `con_hijos` decide S/113+provisiones sin auditoría
ni vigencia · cambiar la cuenta bancaria de alguien no deja rastro ·
`configuracion` deja escribir cualquier clave (incluida `tasa_afp`) sin
guardia · la policy de `personas` es por fila, no por columna
(`estado`/`fecha_cese`/`motivo_cese`/`tipo_vinculo` sin puerta) ·
`devenga_grati/cts/vacaciones` sin fecha de corte, con un bypass real vía
`PATCH` directo a la tabla.

**El patrón que se repite:** 6 de los 16 son la misma familia de defecto que
ya costó el régimen de pensión (→0261), el rol (→0295/0296) y la sede
(→0342) — un campo que mueve plata o una obligación legal, mutable sin
auditoría. Ninguno de los 16 se arregló todavía; quedan en
`hallazgos-abiertos.md` para decidir orden de trabajo.

---

## 2026-09-03 — El comentario de `topes_educacion_rango` mentía sobre una copia que ya no existe (0345) · PEGADA Y VERIFICADA

Encontrado siguiendo el hallazgo #7 de la comparación Workday/Oracle
([`docs/comparacion-workday-oracle-dynamic-2026-09-02.md`](comparacion-workday-oracle-dynamic-2026-09-02.md)):
el informe reportó que el tope de educación por rango "vive en la tabla Y en
un archivo TypeScript hardcodeado a la vez", citando el comentario de la
tabla `topes_educacion_rango` (0132), que dice ser "espejo de
`RANGOS.topeEducacion` en `apps/web/lib/rangos.ts`".

**Es un falso positivo, no una duplicación real.** Ese campo se borró el
2026-08-06 (la 0178, por el mismo motivo de fondo: había quedado
desactualizado y le pagó de más a `caylo` — S/545.25 en vez de S/180). El
comentario de la 0132 nunca se actualizó cuando el campo se borró, así que
siguió describiendo una duplicación que ya no existe — y esa frase desactualizada
fue justamente lo que indujo al agente que hizo la comparación a reportar un
hallazgo que no existe en el código actual.

**Arreglo (0345):** reemplaza solo el `comment on table topes_educacion_rango`
por uno que dice la verdad de hoy — que la tabla es la única fuente y que
`rangos.ts` no declara tope de educación a propósito desde la 0178. No toca
ninguna columna, fila, función ni cálculo — no hay pago que auditar.

**Verificado:** `npx supabase db reset` limpio con las 345 migraciones en
orden; `npx supabase test db` — 1938/1938 en verde; `typecheck` limpio.
Confirmado en producción el mismo día 18:42 UTC (ver la nota de "Aviso
cruzado" más arriba) y fusionada a `main` el 2026-09-04.

---

## 2026-09-03 — Objetivos: «copiar del mes anterior» (0348) y gráfico de historial (0350) · PEGADAS Y VERIFICADAS

Pedido pendiente desde el 2026-08-14 (lista de "Valioso pronto"). En
`/admin/objetivos`, cuando el mes elegido no tiene checklist todavía, aparece
un botón que duplica hacia ese mes la descripción, las indicaciones y el orden
de los objetivos del mes calendario anterior de esa misma persona — todos SIN
marcar, porque es un objetivo nuevo que empieza desde cero, no un historial que
se arrastra.

`fn_objetivos_copiar_mes_anterior` (0348) reusa los mismos candados que el
resto de la 0032: `fn_puede_gestionar_objetivos` (admin/líder a cualquiera,
encargada solo a su sede) y `fn_mes_planilla_pagado`. Y agrega dos propios: se
niega si el mes destino ya tiene algún objetivo (mezclar una copia con lo que
ya exista es ambiguo y nadie lo pidió resuelto), y se niega si el mes anterior
no tiene nada que copiar. Auditada con `npx supabase test db` (prueba 276, 9
casos: copia, contenido, candado de mes no vacío, candado de mes sin origen,
candado de mes pagado, permiso por sede en los dos sentidos) — no toca dinero,
así que no hizo falta la auditoría empírica de planilla.

**Y en la misma entrega, un gráfico de tendencia:** la pantalla ahora dibuja
los últimos 12 meses de cumplidos/total de la persona elegida (SVG propio, sin
librería, mismo estilo que `grafico-horas.tsx`). `fn_objetivos_historial`
(0350) solo lee `objetivos_mensuales` —el resumen que ya sincroniza
`fn_objetivos_sync_mes`, no se calcula nada nuevo— y rellena con
`generate_series` los meses sin checklist para que no desaparezcan de la
serie. La distinción que importaba: un mes **sin checklist** (total=0) no es
lo mismo que un mes con **0% cumplido** (total>0, cumplidos=0) — el primero se
dibuja como una marca gris al piso, "sin dato"; el segundo como una barra roja
de altura mínima, un dato real de bajo desempeño. Se encontró y corrigió
verificando en el navegador: la primera versión dibujaba los dos casos
idénticos, porque una barra de 0% de altura real es invisible — nada distinto
del hueco. Prueba 277 (6 casos: ventana sin saltar meses, hueco con total=0,
dato real, tope de `p_meses` a 24, permiso concedido y denegado).

(La 0349 se renumeró a 0350 al fusionar `main`: otra rama fusionada mientras
esta se escribía ya había tomado el 0349 —y el 274 y el 275 de pruebas— para
otra cosa. `siguiente-numero.sh` lo detectó antes de empujar.)

PR [#160](https://github.com/felipea92p-ux/cayla-dynamic/pull/160) fusionado,
0348 y 0350 pegadas en producción por Felipe y confirmadas funcionando (el
gráfico ya mostró datos reales de septiembre en pantalla).

**Encima, el mismo día:** el rango de 12 meses fijo pasó a elegirse (1/2/3/6/
12/24 meses) con un `<select>` "Rango" junto al título del gráfico —
consistente con Persona/Mes/Año, que ya eran `<select>` en la misma pantalla;
un primer intento con tres botones pastilla se descartó porque desentonaba
con el resto de los filtros de la página. `fn_objetivos_historial` ya
aceptaba `p_meses` desde el principio, esto solo lo expuso en pantalla, sin
migración nueva.

El refresco del rango se separó del `cargar()` que trae la lista de
objetivos —dos efectos en vez de uno— para que cambiar de rango no reinicie
toda la pantalla a "Cargando…", solo el gráfico. El estado de "desactualizado"
se DERIVA comparando la selección actual contra la clave del último historial
que llegó (guardada en estado, no en un ref: leer un ref durante el render es
otro lint prohibido, `react-hooks/refs`) en vez de un `setState` al ENTRAR al
efecto — eso dispara `react-hooks/set-state-in-effect`, que el push bloquea.

**Y, a pedido explícito de Felipe ("usa las skills para el diseño"), un
rediseño con la skill `dataviz`:** el gráfico pasó de barras planas sin
interacción a una pieza con tope redondeado (4px, base cuadrada contra el
eje — no un `rx` de las cuatro esquinas, un `<path>` propio), tooltip por
barra (posición en foco de teclado igual que en hover, y se voltea a
DEBAJO de la barra cuando arriba no cabe, en vez de montarse sobre el título
de la tarjeta), leyenda con ícono + etiqueta para los tres estados
(verde/ámbar/rojo NO son categóricos aquí: son una escala de estado —
cumplido/parcial/bajo desempeño, los mismos tres colores que ya usaba la
barra de progreso— y una escala de estado siempre va con ícono+etiqueta,
nunca el color solo), etiqueta directa selectiva en el último mes (el que se
está editando arriba, no un número en cada barra), y el refetch mantiene el
dibujo anterior atenuado en vez de un flash al cambiar de rango. Los tres
colores de estado se validaron por contraste contra la superficie de la
tarjeta (`bg-papel`) en los dos temas — los tres pasan 3:1 largamente (4.28 a
6.17) — y no por el validador categórico de 8 colores, que la skill dice
explícitamente que no le aplica a una escala de estado.

**Y dos arreglos más, del mismo 2026-09-03, YA EN PRODUCCIÓN (el gráfico de
historial se fusionó y desplegó en el PR anterior):**

1. **El gráfico no se acomodaba con pocos meses.** Con 1-3 meses el SVG medía
   poco (ancho fijo de barra, `<=24px` por la especificación de marca) pero
   llevaba `min-w-full`: sin `viewBox`, estirar la CAJA de un SVG por CSS no
   escala el DIBUJO, solo agranda el lienzo — la barra quedaba pegada a la
   izquierda con un hueco vacío enorme a la derecha, dentro de una tarjeta
   ancha. Felipe lo vio en una captura y lo describió bien: "no se acomoda".
   Se sacó `min-w-full` y el SVG (+ el tooltip, que comparte su mismo origen
   de coordenadas) pasó a vivir en un envoltorio `w-fit mx-auto`: los
   márgenes automáticos centran cuando el dibujo es más angosto que la
   tarjeta, y se colapsan a 0 sin romper el scroll cuando desborda (24
   meses) — a diferencia de centrar por flex/grid, que sí rompe el scroll.
   Verificado en vivo para 1/3/12/24 meses, claro y oscuro.

2. **Un crash real, encontrado en esa misma verificación en vivo, no en el
   ancho.** Enfocar o pasar el mouse por una barra en una ventana larga
   (24 meses) y después achicar el rango (a 1 mes, por ejemplo) dejaba
   `activo` — el índice de la barra con el tooltip abierto — apuntando a una
   posición que ya no existe en el arreglo `historial`, más corto. Nada en el
   componente escuchaba el cambio de la prop para resetearlo. El resultado:
   `historial[activo].total` sobre `undefined`, y toda la pantalla de
   Objetivos caía al `ErrorBoundaryHandler` con "Algo salió mal". **Esto
   viajó a producción sin que nadie lo notara** en el PR del rediseño del
   gráfico — ninguna de las verificaciones de ese momento (typecheck, lint,
   vitest, ni una revisión adversarial de tres agentes sobre el diff del
   ancho) lo encontró; lo cazó recién una sesión de navegador real probando
   la secuencia exacta. Se arregló acotando `activo` contra
   `historial.length` antes de indexar, y por si acaso, con un `key` en
   `<GraficoObjetivos>` (la clave del historial cargado) para que la
   selección de hover/foco se reinicie sola cuando cambian los datos, en vez
   de arrastrarse entre renders.

Ambos arreglos: `npx pnpm typecheck`, ESLint y `npx pnpm test` (427, sin
cambios) en verde. La reverificación en vivo del segundo arreglo quedó
pendiente porque Docker Desktop dejó de responder en esta Mac a media
sesión (`request returned 500 Internal Server Error`, ajeno al código) —
se envía igual por la severidad (un crash ya en producción) y la sencillez
del guard; se reverifica en cuanto Docker vuelva.

---

## 2026-09-03 — La boleta desglosa el sobretiempo en 25 % y 35 % (0349) · PEGADA Y VERIFICADA

Lo pidió el contador de CAYLA: la PLAME declara el sobretiempo con dos
códigos separados en su tabla 22 —0105 al 25 %, 0106 al 35 %— y hasta ahora
la boleta solo mostraba el recargo ya sumado. Conciliar contra la PLAME
exigía partir ese monto a mano cada mes.

`fn_planilla_calcular_nucleo` ya calculaba los dos tramos por separado
dentro del CTE `sobret` (25 % de las 2 primeras horas de exceso de cada día,
35 % de las siguientes) y los sumaba antes de devolverlos. La migración deja
de descartar ese desglose: expone `monto_sobretiempo_25`/`_35` y
`horas_sobretiempo_25`/`_35` sin tocar `monto_sobretiempo` (el total, que
sigue siendo la fuente del `total` de la fila). El 35 % se calcula como el
total menos el 25 % ya redondeado, no con su propia fórmula, para que las
dos líneas de la boleta siempre sumen exacto el monto ya impreso — un caso
real (2 h al 25 % + 1 h al 35 %) mostró que sumar dos redondeos
independientes da un centavo menos que el total. `boleta-hoja.tsx` imprime
el desglose cuando la fila lo trae; si no (boleta de un periodo ya
congelado antes de esta migración), sigue mostrando el texto genérico de
siempre — se confirmó en producción viendo ambos casos en la misma tarde.

**Se abrió como 0347 y se renumeró a 0349 ya con el PR abierto**: mientras
seguía en revisión, otra rama fusionó a `main` una migración distinta —el
generador de contratos indefinidos— con ese mismo número. Es el mismo tipo
de colisión que ya documentó la 0297/0299 del 2026-08-25: varias sesiones
tomando números en paralelo, cada una viendo solo su propia rama. Se
renumeró con `siguiente-numero.sh` una vez traído `main`, y se confirmó por
grep que ninguna migración fusionada entre medias tocaba
`fn_planilla_calcular_nucleo` antes de pegar.

Auditado local (`supabase db reset` + 1957 pruebas en verde, incluida la
275 que fija el desglose y el candado `25 % + 35 % = total` con los mismos
casos que ya fijaba la 143) y verificado en producción el mismo día contra
dos boletas reales: una de un periodo ya pagado (sigue mostrando el texto
genérico, como debía) y una de un periodo abierto —Janis Revilla, TRU—
donde apareció «Recargo 25 % (4 h): S/ 5.88 · Recargo 35 % (6 h 13 min):
S/ 12.80», que suma exacto el S/ 18.68 ya mostrado.

**Solo hacia adelante.** No se agregó columna a `planilla_pagada_detalle`:
su `fila` guarda el JSON completo, así que el desglose llega solo en la
próxima planilla que se congele. Boletas de periodos ya pagados antes de
esta migración no lo muestran — no es un error, es lo mismo que le pasa a
cualquier campo agregado después de que un periodo se cerró.

---

## 2026-09-03 — El 9% de la Ley 30334 sale aparte al pagar la gratificación real (0346) · PEGADA Y VERIFICADA

Lo pidió el contador de CAYLA: que el 9% no viaje mezclado a mano dentro del
monto de «Gratificación» al cerrar julio o diciembre.

La provisión mensual (0134), la reserva de Costos y la liquidación por cese
(`fn_grati_trunca_bruta`) ya lo separaban desde antes. El único hueco era el
pago real del ciclo normal: `fn_grati_cts_periodo` —la que autocompleta el
monto al elegir «Gratificación» en Planilla— nunca calculaba el 9%, y el
desplegable no tenía la opción. Quien quisiera pagarlo tenía que sumarlo a
mano dentro del mismo monto de «Gratificación», sin que quedara registrado
como su propio concepto.

Ahora «Bonificación 9% (Ley 30334)» es una opción propia en el desplegable
de Planilla, calculada como 9% de la MISMA gratificación de ese semestre (la
tasa versionada de siempre, `parametros_laborales.bonificacion_extraordinaria`),
y se registra como un movimiento aparte. Tocó tres puertas, no solo el
cálculo: la lista blanca de `movimientos_categoria_valida` y las dos listas
hardcodeadas de `fn_agregar_movimiento` (la validación general y el candado
de una vez por periodo) — sin las tres, la opción nueva reventaba con
«Categoría inválida.» al primer intento de guardar. Confirmado que
`fn_remuneracion_computable` (la base de la liquidación por cese) sigue
excluyendo la categoría nueva sin tocar su cuerpo: su lista blanca es
`categoria is null or categoria = 'otros'`, así que cualquier categoría
nueva queda fuera por default. La prueba 215 (aserción 11) es el centinela
que lo fuerza a decidirse a propósito; quedó actualizada en este mismo commit.

Auditado local (`supabase db reset` + 1938 pruebas en verde, más una prueba
a mano con BEGIN/ROLLBACK: para una gratificación de S/25.00 el sistema
propuso S/2.25, exacto) y **confirmado byte por byte contra producción** el
mismo día: md5 de `fn_grati_cts_periodo` = `029c534ff79b6e60d7a5a760be659053`
y de `fn_agregar_movimiento` = `d3859d7e928aca004dda8b1c032d4899`, idénticos
entre esta Mac y producción tras pegar la 0346.

**Solo hacia adelante, y es la decisión de Felipe, no solo el alcance de la
migración.** No reclasifica movimientos ya pagados: si julio 2026 ya se pagó
con el 9% sumado a mano dentro de «Gratificación», esa fila sigue tal cual.
**Decidido con Felipe el 2026-09-03: no se corrige lo ya pagado — lo que le
importa es que quede separado de acá en adelante.** No hace falta revisar
julio 2026 ni ninguna migración retroactiva.

---

## 2026-09-03 — Un adelanto de beneficio se calculaba dos veces al cesar (0343) · PEGADA Y VERIFICADA

Encontrado reconciliando a mano la liquidación de Paola Cahuana (cese
28/08/2026) contra su boleta PLAME: se le pagó S/129.79 de más, y no por un
solo motivo — dos defectos distintos, cada uno con su arreglo.

**El defecto 1, ya cerrado por la 0341** (ver la entrada de hoy mismo, justo
abajo de esta): `fn_vacaciones_truncas` no descontaba AFP/ONP — S/27.15 de
los S/129.79.

**El defecto 2, el que arregla la 0343:** se le dio a mano un adelanto de su
gratificación truncada (S/102.63, cargado como bono `categoria='otros'`
porque la opción `'gratificacion'` del desplegable solo sirve para el pago
normal de julio/diciembre, con monto autocalculado). Al armar la
liquidación, `fn_grati_trunca_bruta` no tenía forma de verlo — ni en el
libro de desembolsos (`desembolsos_beneficios`, existe desde la 0155 pero
tiene RLS de solo lectura y **ninguna pantalla la usaba**) ni en
`movimientos_planilla` (solo mira la ventana del pago legal, dic/jul, que
para un cese de agosto nunca iba a existir) — y la recalculó entera:
S/102.65. Confirmado contra el PLAME: sus dos líneas (`0406` gratif 94.17 +
`0312` bonif. extraord. 8.48 = 102.65) ya representaban el trunco completo
y correcto por sí solas — el adelanto manual era plata extra, no una pieza
de un cálculo mayor.

**Arreglo ([PR #150](https://github.com/felipea92p-ux/cayla-dynamic/pull/150), 0343):** dos partes.
`fn_registrar_desembolso` es la puerta que le faltaba al libro de
desembolsos — mismo molde que `fn_agregar_movimiento` (guard admin/líder,
una validación por cada CHECK, `registrado_por` desde
`fn_persona_actual_id()`). Botón "🎁 Adelanto de beneficio" en
`/admin/planilla`, junto a "💸 Ya le pagué aparte". Y `fn_grati_trunca_bruta`
ensancha su detección: además del pago normal de dic/jul, reconoce un
adelanto de mitad de semestre cargado en `movimientos_planilla` con
`categoria='gratificacion'` — solo cuando el cese ocurre antes de la fecha
legal de pago (la ventana normal es entonces estructuralmente imposible), y
solo si el periodo del bono EMPIEZA dentro del semestre evaluado —
condición necesaria para no confundirlo con el pago normal del semestre
anterior y reabrir el defecto que la 0289 ya había cerrado (probado contra
ese caso exacto en la prueba 272, aserciones 6–8).

**Verificado:** `npx supabase db reset` limpio con las 343 migraciones en
orden; `npx supabase test db` — **1938/1938 en verde**, incluida la 225
(la del traslape enero-junio / julio-diciembre, sin tocarse) y la nueva 272
(9 aserciones); `typecheck` limpio con los tipos de Supabase regenerados;
md5 de `fn_grati_trunca_bruta` pedido a producción antes de pegar — coincidió
con el "md5 de llegada" que la propia 0289 dejó documentado en su cabecera,
confirmando que nadie había tocado esa función por fuera del repo desde
entonces.

**No se corrigió retroactivamente.** La liquidación de Paola (y las de
Sanándres y Rodríguez Herrera, revisadas la misma sesión: sus boletas PLAME
ya tenían el AFP correcto, sin diferencia) no se tocan — el arreglo es
hacia adelante, para la próxima persona que cese a mitad de semestre.

---

## 2026-09-03 — Las vacaciones truncas se pagaban sin descontar pensión (0341) · PEGADA Y VERIFICADA

Mismo origen que la 0343 (ver arriba): la reconciliación de la liquidación
de Paola Cahuana contra su boleta PLAME.

**El defecto:** de las tres truncas que se pagan al cesar —vacaciones,
gratificación, CTS— dos están correctamente exentas de AFP/ONP
(gratificación por la Ley 29351/30334, CTS por el art. 9 del D.S.
001-97-TR) y una no debía estarlo: las vacaciones truncas sí son
remunerativas para pensión (art. 19 del mismo D.S.), y `fn_vacaciones_truncas`
las pagaba enteras, igual que a las otras dos. Confirmado contra fuente
externa (afpintegra.pe, sbs.gob.pe) antes de tocar el código.

**Arreglo ([PR #148](https://github.com/felipea92p-ux/cayla-dynamic/pull/148), 0341):**
`fn_vacaciones_truncas` le descuenta AFP/ONP al monto, con la misma tasa y
el mismo criterio de vigencia que ya usa `fn_planilla_calcular` (régimen al
cese vía `asignaciones_regimen_pension`, tasa vigente en `tasas_pension`,
respaldo a `configuracion.tasa_afp`). El jsonb gana `monto_bruto` y
`descuento_afp` (aditivo — `monto` sigue existiendo y ahora sale neto);
`fn_liquidacion` no necesitó tocarse. La pantalla de liquidaciones muestra
el desglose del descuento en vez de solo un número más chico sin explicar.

**Verificado:** `npx supabase db reset` + `npx supabase test db` —
**1920/1920 en verde** (incluida la 270 nueva, 8 aserciones: descuenta,
usa la tasa del régimen de cada quien — mixta 11.37 % vs flujo 12.92 %, con
las tasas reales ya sembradas por la 0114/0328, no una tasa de prueba
inventada —, `monto_bruto − descuento_afp = monto` siempre, y quien no
tiene régimen asignado no pierde nada); `typecheck` limpio; md5 de
`fn_vacaciones_truncas` pedido a producción antes de pegar, coincidió
exacto (`530af4af90c1fa90d0f9b9e8c36b1f05`).

**No corrige lo ya pagado.** Las liquidaciones ya congeladas (Paola incluida)
no se tocan — corrige el cálculo hacia adelante, para el próximo cese.

---

## 2026-09-03 — La sede base se cambiaba sin auditoría (0342) · PEGADA Y VERIFICADA — SIN IMPACTO EN LO YA PAGADO

Encontrado al rehacer, esta vez guardándolo, la comparación de arquitectura
Workday/Oracle HCM contra Dynamic
([`docs/comparacion-workday-oracle-dynamic-2026-09-02.md`](comparacion-workday-oracle-dynamic-2026-09-02.md)
— la primera versión de ese informe, referenciada en el PR #106, nunca se
guardó como archivo y se perdió). El hallazgo central: Dynamic ya
redescubrió el primitivo de "vigencia temporal" de esos sistemas por las
malas, campo por campo, tras bugs reales (0277 → 0261 para el régimen de
pensión). `personas.sede_base_id` tenía la misma exposición y seguía sin
corregir.

**El defecto:** `fn_planilla_calcular` computa la movilidad de todo el
periodo como `días_trabajados × tarifa de la sede ACTUAL` (0166/0261) — no
la sede en la que la persona trabajó cada día. Y esa sede se cambiaba desde
`/admin/equipo` con un `UPDATE` directo, sin RPC, sin auditoría y sin
ningún trigger que lo capturara — el mismo hueco que tenía `rol` antes de
la 0296, sin siquiera la función dedicada que ese caso sí tenía.

**Arreglo ([PR #149](https://github.com/felipea92p-ux/cayla-dynamic/pull/149), 0342):**
`fn_set_sede_base` exige admin o líder, valida que la sede destino esté
activa, bloquea el cambio sobre personas cesadas, y audita en
`correcciones_auditoria`. Un trigger (`trg_personas_sede_solo_por_rpc`,
mismo mecanismo que la 0296 para `rol`) rechaza cualquier `UPDATE` directo
a la columna que no pase por esa función.

**Verificado:** `npx supabase db reset` limpio con las 342 migraciones en
orden; `npx supabase test db` — **1929/1929 en verde**, incluida la prueba
nueva (271, 9 casos); `typecheck` y 427 vitest en verde; probado en el
navegador de punta a punta (login real, cambio de sede desde
`/admin/equipo`, fila confirmada en `correcciones_auditoria`).

✅ **Pegada en producción el 2026-09-03**, con la comprobación de la propia
migración: `la_funcion_existe = 1, el_trigger_existe = 1`.

✅ **Medido en producción el 2026-09-03, con Felipe.** Consulta contra
`planilla_pagada_detalle`: entre las personas con algún periodo repagado
(`version` > 1), ninguna tiene `monto_movilidad` distinto entre versiones
para el mismo periodo — **cero filas**. El defecto era real en el código,
pero no hay evidencia de que ya le haya movido el pago a alguien.

⚠️ **Lo que esa consulta NO cubre, y queda sin poder verificarse:** que
alguien haya cambiado de sede ANTES de la primera congelación de su
periodo (nunca hubo una `version 2` con la que comparar). Ese caso no se
puede reconstruir — es justo el dato que no existía porque no había
auditoría. Auditarlo a fondo exigiría cruzar `jornadas.sede_id` (dónde
marcó cada día) contra la sede usada en cada pago ya congelado, persona por
persona — una auditoría cara, y no hay ninguna señal hoy que la justifique.
Cerrado hacia adelante; sin nada más pendiente salvo que aparezca una razón
para esa auditoría más profunda.

---

## 2026-09-02 — `fn_meses_y_dias` inventaba días en un rango corto (0340) · PEGADA Y VERIFICADA — SIN IMPACTO EN LO YA PAGADO

Encontrado por accidente: al correr la suite completa después de la 0339,
apareció en rojo `263_pedir_vacaciones_y_que_do_las_apruebe.test.sql`, que
antes pasaba. La causa no era la 0339 — era `fn_meses_y_dias` (0087, sin
tocar desde entonces), de la que dependen CUATRO fórmulas de plata:
`fn_cts_trunca`, `fn_grati_trunca_bruta`, `fn_vacaciones_truncas` (las tres
para liquidaciones al cesar) y, desde la 0297, `fn_vacaciones_saldo` (el
saldo en vivo que usa "Lo mío").

**El defecto:** con un rango corto que no llega a completar el mes calendario
siguiente, la función contaba la distancia hasta un punto que el rango nunca
toca. `fn_meses_y_dias('2026-09-02','2026-09-02')` daba `(0, 29)` en vez de
`(0, 1)`. Detalle completo, con siete casos medidos y por qué "mismo día" da
1 y no 0 (la convención ya era inclusiva antes de este arreglo), en la
cabecera de la migración 0340.

**Arreglo de una línea**, auditado independientemente (matemática de 16 casos
adversariales, y la garantía de que el rango con al menos un mes completo
nunca cambia, demostrada, no solo probada). `npx supabase test db`:
**1912/1912 en verde** — primera vez en semanas sin ninguna falla, incluida
la 245 (arreglo aparte, mismo día: la prueba nunca le dio horario a la
persona de prueba y `fn_dias_suspension` lo exige).

⚠️ **El alcance real es más ancho de lo que la primera versión de este texto
decía.** `fn_vacaciones_truncas` ya se protegía de "menos de un mes de
servicios" (devuelve 0 directo), así que quien cesó en su primer mes NUNCA
estuvo expuesto por acá. El caso real: **cualquiera, con cualquier
antigüedad, que cesó dentro de ~35 días después de su último aniversario
laboral** — ahí el "récord trunco" (del aniversario al cese) es el rango
corto que dispara el defecto, y esa fórmula alimenta la liquidación real.

✅ **Pegada en producción el 2026-09-02, md5 confirmado exacto contra lo
verificado local** (partida `3ec471defb94971909962762b2f7f3aa` → llegada
`4e345da084cfeacf4b3a9fcb93be71c4`, las dos veces coincidentes byte a byte).

`fn_vacaciones_truncas` exige sesión de admin y el SQL Editor corre como
`postgres` sin JWT — hizo falta agregar un `set_config` que impersona a un
admin antes de llamarla (mismo truco que ya usaba, sin relación, el viejo
`cuanto_inflo_el_rango_corto_las_liquidaciones.sql`). **Y la primera corrida
de `consulta_impacto_meses_y_dias.sql` fue ANTES de pegar la 0340** —
comparó la función buggy contra sí misma y su "vacío" no significaba nada.
Repetida con la 0340 ya pegada (confirmado con la prueba directa
`fn_meses_y_dias('2026-09-02','2026-09-02')` = 29 antes de pegar, 1 después):
**sigue vacía.** Ninguna liquidación ya pagada quedó con este defecto
adentro. Cerrado, sin nada más que decidir.

---

## 2026-09-01 — Gratificación y CTS usan el sueldo vigente al cierre (0338) · PEGADA Y VERIFICADA

[PR #146](https://github.com/felipea92p-ux/cayla-dynamic/pull/146). `fn_provisiones`
y `fn_feriado_devengado` ganan `p_salario_asof`: cuando alguien tuvo un aumento
de sueldo a mitad del semestre de gratificación o CTS, el depósito real deja de
promediar el sueldo día por día y toma el vigente en la fecha de corte —como
exigen D.S. 001-97-TR art. 10/21 y D.S. 013-2013-PRODUCE art. 50—, sin tocar el
comportamiento de ningún llamador que no pase el parámetro nuevo.
`fn_grati_cts_periodo` llama dos veces por ventana y se queda con el mayor:
nunca puede pagar menos que hoy, solo corregir hacia arriba. Auditada en
laboratorio con casos de aumento y de bajada, y contra la reconstrucción
completa del esquema: 1898/1900 pgTAP en verde (las 2 que fallan son de
disciplina, deuda previa sin relación).

**Md5 de producción confirmado el mismo día de pegarla, contra las tres
funciones que toca:** `fn_grati_cts_periodo` ya se había confirmado antes de
escribir (cuerpo de la 0088, idéntico). `fn_provisiones` y `fn_feriado_devengado`
quedaron pendientes en el encabezado de la migración — se cerraron reconstruyendo
a mano el cuerpo de partida (0310 y 0306, el mismo método de `donde-vive.sh`
aplicado a la versión anterior a la propia migración) y comparándolo contra
producción antes de pegar. Después de pegada, producción coincide con esta Mac
**tal cual, sin perder ni un comentario** — 40031 y 9208 caracteres exactos —
en las dos funciones.

✅ **El pendiente que esto dejaba abierto ya se cerró (2026-09-02).** La rama
`claude/buk-cayla-dynamic-analysis-5be9ec` se retomó, se rehízo el corte de
`fn_feriado_devengado_nucleo` sobre el cuerpo real que dejó la 0338 (no sobre
el de la 0306), se renumeró de 0337 a 0339 para no chocar con ella, y se
fusionó a `main` en el [PR #147](https://github.com/felipea92p-ux/cayla-dynamic/pull/147)
— verificado con diff literal (única diferencia: el guard) y con
`npx supabase test db` completo (1907/1909, mismos 2 fallos preexistentes de
disciplina).

**0339 pegada y verificada en producción el 2026-09-02.** Md5 de partida
confirmado antes de pegar contra las tres funciones que toca
(`fn_planilla_calcular`, `fn_feriado_devengado`, `fn_planilla_calcular_persona`)
y la comprobación de llegada de la propia migración salió OK: los dos núcleos
existen, están en `funciones_nunca_para_authenticated`, y `authenticated` no
puede ejecutarlos directo. **Desplegado el mismo día** (`npx vercel --prod`,
saltando a propósito el freno de `desplegar.sh` en el paso de CI — ver
"deuda de CI" abajo) y verificado en `cayla-dynamic.vercel.app`: la home
carga, y `/mio/boleta` sin sesión redirige limpio al login de "Lo mío" en vez
de romperse.

⚠️ **Lo que esto NO verificó:** nadie probó el flujo completo con una persona
real con sesión iniciada viendo su propia boleta del periodo actual — solo se
confirmó que el guard de autoservicio (servidor, no cliente) rechaza a quien
no tiene sesión. Antes de anunciarlo al equipo, alguien con cuenta real debería
entrar a "Lo mío" → boleta y confirmar que los montos coinciden con lo que
`fn_planilla_calcular_nucleo` calcula.

⚠️ **Deuda de CI que esto hizo visible:** `db-tests` lleva rojo en `main` desde
antes de la 0338 (2 pruebas de `245_el_mes_cerrado...`, sobre
`fn_expediente_generar_tardanza` — disciplina, no planilla; deuda preexistente,
no causada por 0338 ni 0339). Mientras siga así, `desplegar.sh prod` se frena
SIEMPRE en el paso 3 y cada despliegue real tiene que saltarlo a mano con
`npx vercel --prod` — el bypass documentado que el propio script ofrece, pero
que ya no protege nada mientras esta deuda no se pague. Vale la pena arreglar
`fn_expediente_generar_tardanza` (pide un horario vigente para fijar los días
de una suspensión) antes de que el hábito de saltar el freno se vuelva
automático y algún día tape un fallo real.

**Pendiente, no bloqueante, de la 0339:** `apps/web/components/boleta-hoja.tsx`
(el componente que usa `/mio/boleta`, ~30 personas) importa de
`apps/web/app/(admin)/admin/planilla/page.tsx` (~1000 líneas) en vez de
`packages/shared`. No medido el impacto real en el bundle de autoservicio.

---

## 2026-08-31 — El tablero avisa el tope de 12 meses del convenio (0336) · VERIFICADO LOCAL

El quinto y último pendiente de Practicantes. `fn_contratos_tablero`
(0287/0333) ya avisaba de contratos por vencer, pero no del tope legal de 12
meses continuos de un convenio de modalidad formativa (Ley 28518, art. 30) —
el riesgo de desnaturalización si se sigue sin sustento del centro de
formación.

**Decidido con Felipe por `AskUserQuestion`: se mide desde `fecha_ingreso`**,
no sumando la duración de cada convenio generado — una practicante no entra
y sale del estatus, es continua desde que ingresó. Más simple, correcto para
el caso real, y sin pantalla nueva: para una practicante, la fecha que
gobierna en el tablero pasa a ser la más temprana entre su convenio
(`fecha_fin_contrato`) y `fecha_ingreso + 12 meses` — lo que llegue primero.
Reutiliza los mismos estados de siempre (`vencido`, `por_vencer`, `ok`…), no
uno nuevo.

Con datos que ya tenía un convenio dentro del tope, el documento sigue
mandando sin que el tope interfiera — solo toma el mando cuando falta
documento o cuando alguien puso una fecha más allá del tope a pesar del
aviso que ya da el generador al crear un convenio de más de 12 meses (0333).

En pantalla, la etiqueta del tablero deja de decir "contrato vencido"/"vence
pronto" para una practicante — dice "superó el tope de 12 meses del
convenio"/"se acerca al tope de 12 meses del convenio", para no confundir un
vencimiento de documento con el tope legal. De paso, se corrigió un "a la
colaboradora" suelto en el trámite de entrega de copia (decía eso también
para un convenio).

Verificado en el navegador: una practicante a 11 meses de ingresar, sin
convenio registrado, aparece "en papel, sin registrar acá · vence
[fecha del tope]"; con un convenio firmado que declara una fecha más allá
del tope, aparece "se acerca al tope de 12 meses del convenio · 30 días" —
la fecha correcta, no la del papel. 189 archivos, 1891 pruebas pgTAP + 427
de Vitest en verde.

Con esto, los cinco pendientes originales de Practicantes quedan cerrados.

---

## 2026-08-31 — El pendiente que dejó la 0294 queda cerrado: auditoría de suspensiones fuera de tope · CERRADO

La PR [#64](https://github.com/felipea92p-ux/cayla-dynamic/pull/64) (migración
0294) dejó escrito que los documentos disciplinarios ya firmados o entregados
"no se revisan solos" — que si alguna suspensión pasada se pasó del tope del
RIT, había que buscarla a mano. Se escribió esa búsqueda:
[`suspensiones_fuera_del_tope.sql`](../scripts/sql-manual/suspensiones_fuera_del_tope.sql)
(PR [#141](https://github.com/felipea92p-ux/cayla-dynamic/pull/141)), verificada
contra el Postgres local con los tres casos reales —el de 10 días de Arequipa y
los dos de la escalera 19.2 c)/d)— dentro de `BEGIN…ROLLBACK` antes de pegarla
en producción.

**Encontró un caso real:** T-02/0004-2026-CAYLA (Mateo Zarate) — su segunda
suspensión por tardanzas salió igual a la primera, 1 día cada una (entregadas
2026-07-25 y 2026-08-17), cuando el numeral 19.2 d) exige que la segunda sea
mayor. Es anterior a la 0294. Las dos ya se cumplieron —sin marcar esos
días— y no hay plata de más ni de menos que ajustar: el defecto es que el
documento se funda en el 19.2 d) y lo incumple en su parte resolutiva, lo que
lo debilita como antecedente graduado.

**Decisión (Felipe, 2026-08-31): no se anula ni se reemite.** Ya se cumplió, y
corregirlo significaría volver a sancionar por días que ya pasaron. Queda
anotado en [`hallazgos-abiertos.md`](hallazgos-abiertos.md) (PR
[#144](https://github.com/felipea92p-ux/cayla-dynamic/pull/144)) para quien
mire su legajo después.

**Y hacia adelante no puede repetirse.** El generador vigente
(`fn_expediente_generar_tardanza`, 0311) ya propone `suspension_previa_dias +
1` para la siguiente suspensión de la misma persona —para Mateo, 2 días— y el
editor (`fn_expediente_set_suspension`, 0294) rechaza cualquier valor que no
sea estrictamente mayor. No depende de que quien llena el campo se acuerde de
la regla.

---

## 2026-08-31 — Texto de apoyo por objetivo del mes (0335) · PEGADA Y VERIFICADA

Felipe pidió poder dejar, en cada objetivo del checklist mensual (0032), unas
indicaciones más completas además de la descripción corta — el detalle que
ayuda a la integrante a entender qué se espera exactamente. Se gestionan en
`/admin/objetivos` (agregar y editar) y se muestran a la propia persona en
`/mio`. No pagan nada, igual que el resto del checklist desde la 0171.

**La auditoría empírica de la migración encontró la misma clase de bug que
rompió el aviso de vacaciones el 2026-08-25 (0297/0299):** `create or replace
function` con un parámetro nuevo por defecto **no reemplaza** la función
vieja — crea una segunda sobrecarga, y la llamada con el número de argumentos
original queda ambigua (`function ... is not unique`). Pasaba con
`fn_objetivo_agregar` y `fn_objetivo_editar`, que ganaron un quinto y tercer
parámetro respectivamente. Se corrigió con `drop function` explícito antes de
recrearlas, con sus grants. Lo cazó correr la migración contra Postgres local
con datos reales — la misma auditoría que este archivo pide siempre antes de
entregar SQL que toca algo que alguien usa.

PR [#137](https://github.com/felipea92p-ux/cayla-dynamic/pull/137) fusionado,
desplegado a producción por el merge automático de Vercel sobre `main`, y
Felipe confirmó que funciona.

---

## 2026-08-31 — La comisión mixta deja de cobrarse como flujo (0328/0331) · PEGADA Y VERIFICADA

El contador encontró que se le retenía a casi todo el equipo la comisión de
AFP **sobre flujo** (12.84%–13.06%) cuando, por afiliarse al SPP desde 2013,
están en **comisión mixta** — 0% sobre el sueldo desde feb-2023 (Ley 29903).
Correspondía 11.37% (10% aporte + 1.37% prima). La 0114 lo había dejado
anotado como no modelado; quedó sin hacer.

**0328** agrega las cuatro tasas `_mixta`. **0331** reasigna a las 19/20
personas que estaban en flujo, con efecto desde el 29/07/2026 — no toca
ningún periodo ya pagado. Las dos, pegadas y verificadas en producción:
`queda_alguien_en_flujo = 0`.

**Lo retenido de más en el único periodo pagado con diferencia (29/07–28/08):
S/304.47, 18 personas — PAGADO EN TOTAL, 2026-08-31.** No se devolvió por
planilla — el contador dijo que "devolución AFP" no tiene concepto en la
PLAME — Felipe lo transfirió directo, por fuera, sede por sede: TRU (9,
S/157.54), AQP (5, S/68.70) y las 4 restantes —Joselyn Gavilan, Lizzelott
Ramírez, Carmen Sanándres y Felipe Alvarez (él mismo)— con su sede inferida
por descarte, sin confirmar por consulta (no llegó a hacer falta: ya están
pagadas). Tema cerrado.

**El hueco de numeración 0329/0330 que avisó el push, ya resuelto.** Las dos
existían — escritas y commiteadas, pero cada una en una rama de otra sesión
concurrente, sin fusionar a `main`:

- **0329** (el estimado de planilla se consulta por persona) ya estaba
  fusionada (PR #129) cuando se miró; nada que hacer.
- **0330** (una persona pide sus vacaciones, DO aprueba o rechaza) vivía
  **solo en este Mac**, sin subir a GitHub — el patrón de la 0177, a tiempo.
  Felipe confirmó que SÍ está aplicada en producción
  (`migraciones_aplicadas` trae la fila 330). Se respaldó la rama, se abrió
  el PR #130 y se fusionó: el repo vuelve a coincidir con lo que corre en
  producción. No se pegó SQL nuevo — ya estaba pegado.

De paso, al revisar la 0331 se encontró y confirmó inofensivo el PR #123:
un caso límite en CI (la base de pruebas arranca sin ningún
`periodos_planilla`, cosa que no pasa en producción). No afecta nada de lo
ya pegado ni de lo ya pagado arriba.

**Nota de la rama Contratos/Practicantes: el hueco 0333/0334 también está
explicado**, mismo patrón — no un pegado sin archivo: 0332 quedó tomado por
otra rama en paralelo y esta rama saltó directo a la 0333
(`el_generador_de_contratos_hace_convenios_de_practicas`), confirmado con
`./scripts/siguiente-numero.sh` antes de escribirla y revisado por otra
sesión (`liquidacion-paola-fin-mes-aab080`) contra todo `main` antes de
fusionar.

---

## 2026-08-31 — El generador de contratos hace convenios de prácticas (0333) · VERIFICADO LOCAL

Cerraba la lista de pendientes de Practicantes: `/admin/contratos` filtraba
`en_planilla = true`, así que una practicante era estructuralmente invisible
—no había ningún documento que entregarle desde el sistema—. La mitad de las
cláusulas del contrato de planilla son directamente falsas para un convenio
de modalidad formativa (causa objetiva D.Leg 728, jornada 48h fija, período
de prueba, régimen disciplinario), así que se construyó `documentoConvenio()`
como una rama aparte del generador —mismo patrón que ya usa `documentoAdendum`—,
grounded en Ley 28518 arts. 15/30/42/44/45/47 y con el mismo tono ya
establecido en la boleta de un practicante (PR #98).

**El único cambio de esquema:** el CHECK de `contratos_generados.tipo` gana
`'convenio_practicas'`, y `fn_contrato_registrar`/`fn_contratos_tablero` lo
admiten — sin columnas nuevas: institución educativa y plan de capacitación
se piden en pantalla y entran ya redactados al `documento_html`, igual que la
causa objetiva de un contrato normal.

Verificado con datos de prueba en el navegador de punta a punta: la
practicante aparece en el tablero, "Tipo" se fija solo en "Convenio de
prácticas", el bloqueo de subvención por debajo de la RMV vigente frena la
generación y se libera al corregir el sueldo, el documento generado no
contiene NINGÚN término de contrato de trabajo, y queda archivado
correctamente como "pendiente de firma". 1853 pruebas pgTAP + 422 de Vitest
en verde.

⚠️ **Igual que el contrato de planilla, no tuvo revisión legal de un
abogado.** Se construyó con la misma seriedad, ni más ni menos — ver el
encabezado de `contrato-texto.ts`.

Con esto, los cinco pendientes originales de Practicantes quedan resueltos:
motivo de cese (0325), jornada 30h/48h (0324), política salarial (no aplica,
más arriba), y ahora Contratos. Queda solo el aviso de vencimiento del
convenio a los 12 meses, sin empezar.

---

## 2026-08-31 — La política salarial NO se extiende a practicantes · DECIDIDO, NO SE REABRE

Tras crear la categoría practicante (0322), quedó en la lista de pendientes
«la 0141 excluye a quien no está en planilla del cuadro de categorías». Se
investigó a fondo y **no es un vacío: es correcto tal como está.**

El documento «Cuadro de categorías y política salarial» (0141) existe
específicamente para cumplir la Ley 30709 / D.S. 002-2018-TR, que obliga a
informar la política salarial **al trabajador** (art. 25.22/25.23 RLGIT). Un
practicante no es trabajador — ni por la Ley 28518 (art. 47, citada en la
0322) ni por el propio Reglamento Interno de esta empresa (numeral 2.6). La
obligación legal que la 0141 cumple sencillamente no le alcanza, igual que ya
no alcanzaba a un locador RxH antes de que existiera la categoría practicante.

**Confirmado con Felipe por `AskUserQuestion` el 2026-08-31: nada que
arreglar.** Se ofrecieron tres caminos —dejarlo así, crear un documento propio
de subvención como práctica voluntaria (no legal), o posponerlo— y eligió el
primero.

Si alguien vuelve a encontrar este "pendiente" en una lista vieja de gaps de
Practicantes: ya se investigó y se cerró. No se abre de nuevo sin una razón
nueva.

---

## 2026-08-29 — Se crea la categoría practicante (0322) · PEGADA Y VERIFICADA

`personas.tipo_vinculo` gana un quinto valor: **`'practicante'`**, para dar de
alta a alguien bajo un convenio de modalidad formativa (Ley N.° 28518 —
prácticas preprofesionales y profesionales). No es relación laboral: cobra sus
horas igual que cualquiera, CAYLA se acoge a EsSalud por decisión propia
(art. 47), pero **no** genera gratificación, CTS, vacaciones ni aporte a
pensión (AFP/ONP), y **no** se le mide disciplina — la misma razón que a un
RxH: fiscalizar conducta es indicio de subordinación (art. 9, D.S. 003-97-TR),
justo lo que un convenio formativo no puede parecer.

**Por qué costó una sola línea de `fn_planilla_calcular`:** `en_planilla` ya es
una columna generada (`tipo_vinculo in ('planilla','prueba')`, 0085), así que
para un practicante ya sale `false` — y eso apaga solas la gratificación, la
CTS, las vacaciones, el AFP, la movilidad, la educación, la asignación
familiar y el conteo de asistencia, sin tocar nada nuevo. Lo único que tenía
su propio interruptor —no dependía de `bri.base`— era el aporte de EsSalud, y
ese es el único término que cambia: `pe.en_planilla or pe.tipo_vinculo =
'practicante'`.

**Auditado contra el Postgres local:** 1784 pruebas pgTAP en verde, más un caso
real dentro de `BEGIN…ROLLBACK` (practicante contra un control de planilla,
mismo sueldo y mismas horas) que confirma `pago_base` idéntico, EsSalud
generándose y AFP en cero.

**PEGADA Y VERIFICADA EN PRODUCCIÓN el 2026-08-29** — PR
[#97](https://github.com/felipea92p-ux/cayla-dynamic/pull/97) fusionado a
`main`, la migración entregada con `dame-el-sql.sh` (idéntica byte por byte
entre `origin/main` y el disco, portapapeles comprobado por fuera del script
con el locale explícito) y la consulta final de la propia 0322 devolvió sus
ocho columnas en `true` en el SQL Editor de producción — incluidas las cuatro
que confirman que la base sobre la que se copió `fn_planilla_calcular` era la
vigente (0317) y no revirtió ni la vacacional, ni el descanso médico, ni la
licencia, ni la maternidad.

⚠️ **No tengo registro de que el md5 de partida se haya comparado contra
producción ANTES de pegar** —el encabezado de la 0322 lo declaraba como
pendiente de confirmar—, solo de que el autochequeo de LLEGADA salió bien
después. En este caso el resultado cuadra igual, pero la próxima migración que
reescriba `fn_planilla_calcular` debería volver a pedirlo ANTES, como manda la
regla de la casa: que haya salido bien esta vez no es garantía la próxima.

**Confirmado aparte, el mismo 2026-08-29, con `donde-vive.sh` y una consulta
directa contra producción** (es una foto de HOY, no reemplaza el chequeo ANTES
que le faltó a esta migración, pero cierra la duda que dejó abierta):
`que_falta_pegar.sql` dice «PLANILLA: fn_planilla_calcular — 0322, al día con
el repositorio», y el md5 pedido directo al SQL Editor de producción salió
**`c86ef4707f51bf57024efac7eea41643`, idéntico al de esta Mac** —107.906
caracteres, comentarios incluidos—. Producción no quedó con una versión
distinta ni con acentos rotos.

**Lo que NO se construyó, a propósito, y sigue pendiente:**

- **El horario máximo de 30h/48h no se hace cumplir solo.** Hoy se arma a mano,
  persona por persona, en `/admin/horarios` (ya se puede — es un horario por
  persona, no por sede, así que no afecta a nadie más de tienda). Pero el aviso
  de exceso de jornada en `admin/incidencias` sigue comparando siempre contra
  48h fijas (`MAXIMO_LEGAL_SEMANAL`): si una practicante preprofesional (tope
  legal 30h) cubre un turno extra y llega a 35h, el sistema no lo señala. Para
  que lo haga falta que el sistema sepa distinguir preprofesional de
  profesional — hoy `tipo_vinculo='practicante'` no dice cuál de las dos es.
- **El aviso de vencimiento del convenio** (12 meses, con el riesgo de
  desnaturalización si se renueva sin contenido formativo real) no existe.
- ~~**El cuerpo del documento de pago seguía en lenguaje de honorarios de
  RxH**~~ — **CERRADO el mismo día.** El título ya decía bien "Constancia de
  subvención" desde la 0322, pero el cuerpo (`admin/planilla/boleta`) heredaba
  la rama de RxH completa: "locación de servicios", "tú organizas tu propio
  tiempo" (falso — el convenio SÍ fija jornada), "emite tu recibo por
  honorarios" (un practicante no emite nada) y ocultaba el aporte de EsSalud
  que la 0322 sí genera para él (el bloque "Además, CAYLA paga por ti" estaba
  condicionado a `!esLocador`, y un practicante entraba en `esLocador=true` por
  tener `en_planilla=false`). Se separó `esPracticante` de `esLocador` y se
  escribió su propia rama de copy, con Ley 28518 en vez de Código Civil 1764.

**Preguntas para Dante, sin responder todavía:** si ya existe un convenio marco
firmado con algún centro educativo; si el monto de subvención va a ser siempre
la RMV exacta o CAYLA paga por encima; y si hay algún caso ya cerca de los 12
meses que obligue a construir el aviso de vencimiento antes que después.

---

## 2026-08-27 — La pregunta que ningún freno hacía (0319) · PEGADA Y VERIFICADA

Todos los frenos del cierre son de **regla**: ¿cuadra?, ¿a quién le toca esta
norma?, ¿va a cobrar dos veces? Buenos los tres, y con el mismo límite: solo
encuentran lo que alguien ya sabía preguntar. No había ninguna pregunta de
**forma** — ¿esto se parece al mes pasado?

Y tres hallazgos ya confirmados en [`hallazgos-abiertos.md`](hallazgos-abiertos.md)
son de forma, no de regla. Se ven sin conocer la norma que los produce: «cobra
S/0 y el mes pasado cobró un sueldo» (S/1.509,64), «cobra el mes íntegro y
trabajó doce días» (S/1.306,45) y «cobra días posteriores a su cese» (S/193,55).
Los tres costaron auditorías de decenas de agentes. Una tabla ordenada por |Δ|
los pone arriba en dos segundos.

**`fn_planilla_variacion(periodo)` + panel «Qué cambió respecto al mes pasado»**
en `/admin/planilla`, encima de la tabla. Solo lee, no bloquea nada, y **no toca
`fn_planilla_calcular` ni una línea** — por eso no entra en el ritual de md5 y no
compite con el cierre del 28.

⚠️ **No arregla ninguno de esos tres hallazgos: los hace visibles.** Siguen
abiertos y siguen costando lo que costaban.

**La decisión de diseño:** los dos lados se le piden a `fn_proyeccion_periodo`,
no a `fn_planilla_calcular`. Esa función ya sabe —desde la 0313— que un mes
pagado se LEE de su foto. Preguntar directo al cálculo habría comparado el
presente contra un pasado que nunca ocurrió, mintiendo justo donde promete
avisar. Verificado: `previo_fuente = 'foto'`.

**Y la segunda:** `avisos` y `explica` son dos listas, no una. Aquí el falso
positivo es el peor error, así que «cesó», «ingresó», «le cambió el sueldo» y
«más ausencias» van al lado del aviso, no en vez de él. La fila que hay que
mirar es la que aparece **sin nada en gris**.

**Lo que la medición cambió antes de entregarla** (auditoría en `BEGIN…ROLLBACK`
con siete escenarios, y cinco intentos de tumbarla):

- Quien pasaba de S/0 a S/1.918 no levantaba ningún aviso: `salto` es ciego con
  el previo en 0 porque no hay porcentaje. Nace `empieza_a_cobrar`.
- `cobra_igual_trabajo_menos` se disparaba con **cualquier ausencia aprobada**.
  Vacaciones, descanso médico y maternidad pagan SIN marcaje: dejan el total
  quieto y las horas en cero — la forma exacta del defecto que persigue. En la
  auditoría, quien pasó el periodo entero de vacaciones se libró por un 4,4 %, o
  sea por suerte. Ahora exige `aus_act <= aus_prev`.
- Una fila de puros ceros ocupaba sitio.

Umbrales en `configuracion.planilla_variacion_umbrales`, no en el cuerpo.

Prueba [`255`](../supabase/tests/255_que_cambio_respecto_al_mes_pasado.test.sql),
14 aserciones, **vista en rojo a propósito**: quitando la guarda de ausencias
falla la 9 y solo la 9. Suite: 177 archivos, 1774 pruebas, PASS con el esquema
reconstruido desde cero. Panel verificado en el navegador.

**PEGADA Y VERIFICADA EN PRODUCCIÓN el 2026-08-27.** Antes de dársela: PR
[#94](https://github.com/felipea92p-ux/cayla-dynamic/pull/94) fusionado a
`main` con sus cuatro comprobaciones en verde —incluidas las de base de
datos—, la migración idéntica byte por byte entre `origin/main` y el disco, y
el portapapeles comprobado FUERA del script, con el locale explícito (155
acentos a cada lado) — la comprobación externa que la casa exige desde que el
guardián se declaró conforme comparando texto corrupto contra texto corrupto.

Las cinco columnas de la comprobación final salieron en `true`: existe sin
sobrecargas, compara contra la foto de `fn_proyeccion_periodo` y no contra el
recálculo, están los umbrales, la pantalla la puede llamar, y quedó el rastro
en `migraciones_aplicadas`.

No hubo md5 que pedir: esta migración no reescribe ninguna función existente,
solo crea `fn_planilla_variacion` — así que ni el ritual de partida ni el de
llegada aplican aquí.

⚠️ **Y sigue en pie la advertencia de arriba: esto no arregla los tres
hallazgos, los hace visibles.** Nada cambió en `hallazgos-abiertos.md`.

---

## 2026-08-26 — La familia de tres, cerrada (0263 · 0316 · 0317)

La planilla paga tres cosas sin que haya marcaje: **descanso médico**, **licencia
con goce y duelo directo**, y **vacaciones**. Las tres son remuneración y las
tres tenían que entrar a `bri.base`. Las tres se cayeron por el mismo sitio, una
detrás de otra: el monto iba a `pago_base` y no a `pb.basica`.

| | lo arregló |
|---|---|
| Descanso médico | 0263 |
| Licencia con goce y duelo directo | **0316**, hoy |
| Vacaciones | **0317**, hoy · **PEGADA Y VERIFICADA** |

**Lo que enseñó la medición**, y costó entender: `pb.basica` —la básica legal, la
parte del sueldo que sí se declara— **se prorratea por HORAS MARCADAS**. Quien
está de vacaciones no marca, así que su base baja aunque cobre igual.

⚠️ **Y una corrección de método, contra mí.** La primera medición se hizo con
`sueldo_base_legal` en su DEFAULT de 1.130, y dio cifras que exageraban el
defecto. En CAYLA se declara el sueldo íntegro —22 de 22 personas al
2026-08-08—, así que hubo que rehacerla con esa configuración. Además, una
segunda medición salió mostrando que «no cambiaba nada»: era un artefacto de
haber reconstruido el Postgres local CON la 0317 ya aplicada, así que el «antes»
no era antes. Se rehízo aplicando la 0316 dentro de la transacción. **Un
resultado de laboratorio solo vale si el fixture espeja producción y si el
«antes» es de verdad el antes.**

**Las cifras buenas**, con la configuración real, sueldo 3.000:

| | base declarada | vs quien trabajó |
|---|---|---|
| Control (trabajó todo) | 3.000,96 | — |
| Descanso médico | 3.000,96 | 0 — ya estaba bien |
| Licencia con goce | 2.964,94 | **−36,02** ← el feriado corto, otro hallazgo |
| **Vacaciones** | **2.517,09** | **−483,87** ← el defecto |

Después de la 0317, **vacaciones y control dan la misma base exacta** (3.000,96)
y el mismo aporte de pensión (390,13 contra los 327,22 de antes). Que es lo
correcto: se devenga igual trabajando que gozando el descanso. Y quien pasa el
mes entero de vacaciones pasa de aportar S/29 de pensión a S/419.

**No mueve ninguna boleta.** Medido en producción: **cero** personas con
vacaciones en el periodo abierto y **cero** periodos ya pagados afectados. Misma
ventana que la 0316.

**PEGADA Y VERIFICADA EN PRODUCCIÓN el 2026-08-26.** md5 de llegada
`6838c789a2f2444166f2dbebfd9faa0d`, 107.341 caracteres, el esperado al byte, y
comprobado que no revirtió nada: siguen en pie la 0262, la 0263, la 0275, la
0314 y la 0316, las cuatro cascadas de días laborables están, y hay **una sola**
`fn_planilla_calcular`. Su revisión adversaria salió con **cero hallazgos**
—cinco propuestos, los cinco refutados con medición—.

md5 de partida `f6ece4f8…` (la 0316). Diff del cuerpo: **cero líneas quitadas**,
3 de código.
Prueba [`253`](../supabase/tests/253_la_remuneracion_vacacional_tambien_se_declara.test.sql),
12 aserciones. Suite: 175 archivos, 1748 pruebas, PASS.

**Y se cierra la divergencia que la prueba 251 había declarado.** Decía «defecto
abierto a propósito… cuando se arregle, esta línea se cae y hay que cambiarla por
su contraria». Se cayó el mismo día.

---

## 2026-08-26 — Lo que la revisión adversaria de la 0314 encontró · ✅ CERRADO (0316 y 0317, arriba)

32 agentes, cinco lentes independientes y dos escépticos por hallazgo. **13
propuestos, 9 refutados con medición, 4 en pie** — y los cuatro son en realidad
**dos**: tres lentes distintas dieron con el mismo defecto.

**El defecto: se paga y no se declara.** El monto de la licencia con goce y del
duelo de familiar directo entra a `pago_base` pero **no a `bri.base`**, que es la
remuneración afecta a EsSalud y a pensión. Es exactamente el mecanismo que la
**0263** ya tuvo que arreglar para el descanso médico, y su comentario lo dice
con estas palabras: *«La 0254 los metió en `pago_base` pero no en `pb.basica`,
así que no llegaban aquí: se pagaban y no se declaraban.»*

**Hoy cuesta S/ 0,00** por la 0314: `duelo_familiar_directo` lo crea esa misma
migración y `licencia_con_goce` tiene cero usos medidos en producción.

**Pero el mismo agujero está abierto para las VACACIONES, y ese sí gotea hoy.**
Ya estaba catalogado en [`hallazgos-abiertos.md`](hallazgos-abiertos.md) desde la
auditoría del 19 de agosto. **Remedido el 2026-08-26 y es peor de lo que decía
esa línea:**

| | cobra | declara a EsSalud |
|---|---|---|
| Mes entero de vacaciones, sueldo 3.000 | **3.000,00** | **1.130,00** ← solo el piso RMV |
| Mes entero trabajado, mismo sueldo | 2.612,90 | 1.372,25 |

Su base cae a cero y únicamente la levanta el piso legal.

**El cuarto hallazgo es una tilde:** el tipo nuevo se llama «conyuge» y el resto
del catálogo sí acentúa («Descanso médico», «Cumpleaños»). Un `update` de una
línea.

**Lo que la revisión NO cubrió**, y conviene saberlo: producción (ningún agente
tuvo acceso) y el feriado prorrateado de quien tuvo licencia, que la cabecera de
la 0314 ya declara fuera a propósito.

**Lo que sí verificó, y salió limpio:** el diff real contra el cuerpo de la 0306
—**cero líneas quitadas o modificadas**, 43 marcadores CAMBIO intactos, firma
idéntica—; que el doble pago es imposible por el EXCLUDE `ausencias_sin_solape`,
con `pago_base` cerrando exacto en siete escenarios incluidos licencia de periodo
entero, licencia a caballo entre dos periodos y día fichado dentro; idempotencia
probada pegando el archivo dos veces; y la coherencia de `chk_foto_cuadra`,
`fn_planilla_congelar`, `fn_provisiones` y la justificación de la falta.

**Decidido el 2026-08-26: partida en dos.**

· **La 0316 — PEGADA Y VERIFICADA EN PRODUCCIÓN el 2026-08-26.** md5 de llegada
  `f6ece4f8e21a8171b0d393ddf47cd1ce`, 104.644 caracteres, el esperado al byte, y
  comprobado que no revirtió nada: siguen en pie la 0263 (descanso médico), la
  0262 (maternidad), la 0314 (catálogo) y la 0275 (vacaciones), las cuatro
  cascadas de días laborables están y hay **una sola** `fn_planilla_calcular`.
  Su revisión adversaria salió con **cero hallazgos** — seis propuestos por
  cuatro lentes independientes, los seis refutados con medición.

  Cierra el caso que NO mueve nada
  hoy: la licencia con goce y el duelo directo entran a `bri.base`, más la tilde
  de «cónyuge». Un término calcado del de la 0263, tres líneas de código.
  Medido con 8 personas: la licencia sube su base +483,87 (el monto exacto) y su
  neto baja S/62,90 de ONP; **descanso médico, vacaciones, maternidad, control,
  sueldo fijo y RxH quedan idénticos al céntimo**. Los dos últimos son los que
  más caro costaría romper: tienen la base en cero a propósito y la regla de la
  casa es que las sobretasas COMPLETAN una base, nunca CREAN una.
  md5 de llegada: `634ef0c497da26a06904e056327cfb60`, 104.327 caracteres.
  Prueba [`251`](../supabase/tests/251_lo_que_se_paga_por_licencia_tambien_se_declara.test.sql),
  14 aserciones. Suite: 174 archivos, 1736 pruebas, PASS.

· **Las vacaciones quedan para después del cierre del 28**, en su propia
  migración y avisando al contador, porque ese término sí cambia el neto de
  quien las tomó. La prueba 251 lo vigila al estilo de la 244: declara el
  defecto como abierto y se caerá el día que alguien lo arregle.

**Cerrado el 2026-08-27 con la 0317** (ver la entrada de arriba, «La familia de
tres, cerrada») — la prueba 251 se cayó ese mismo día, como estaba previsto.

---

## 2026-08-26 — El catálogo decide qué ausencia se paga (0314) · EN PRODUCCIÓN

**PEGADA Y VERIFICADA el 2026-08-26.** md5 de llegada
`c8070bb865e977d2d0e6b1bb4bac58d2`, 102.178 caracteres, el esperado al byte.
Comprobado además que la reescritura **no revirtió nada**: siguen en pie los
cambios de la 0275, la 0286 y la 0306, las cuatro cascadas de «¿le tocaba
trabajar ese día?» están —eran tres, la cuarta la trae el lateral nuevo— y hay
**una sola** `fn_planilla_calcular`, sin la sobrecarga que rompió la pantalla con
la 0297/0299.

**No le costó un sol a nadie: `licencias_total = 0` en producción.** Nadie
registró nunca una licencia con goce, así que ninguna cayó en un periodo pagado
y no hay diferencia que devolver. El defecto era real y la puerta estaba
abierta; simplemente no entró nadie por ella.

**Dos cosas del pegado que vale la pena recordar.** La primera vez no se aplicó
nada —la comprobación salió con el md5 de partida intacto y `quedo_el_rastro =
false`— y no se supo por qué, porque nadie miró lo que devolvió el editor. Lo
que lo dejó ver en dos minutos fue tener escrita de antemano la consulta de
comprobación con los valores esperados. Y el md5 de partida, que se pidió
DESPUÉS de pegar en vez de antes, resultó coincidir exactamente con el declarado
(`4688bf01…`), o sea que no había peligro — pero eso se supo por suerte, no por
método.

`fn_planilla_calcular` conocía DOS tipos de ausencia por su nombre
—`descanso_medico` y `maternidad`— y cualquier otro marcado `paga = true` en el
catálogo se ignoraba **en silencio**. Eso dejaba dos agujeros:

- **`licencia_con_goce`** llevaba meses activa, en el desplegable, con la
  pantalla prometiendo al aprobarla que «esos días entran en su planilla». No
  entraban. La prueba `187` lo tenía escrito desde que se creó el tipo: *«el día
  que alguien registre una licencia y cierre el mes, la persona cobra de menos y
  el sistema se ve correcto en pantalla»*.
- **El duelo no distinguía** al familiar directo del que no lo es. El art. 31.4.a
  del Reglamento Interno y la Ley 31602 obligan a pagar **cinco días** cuando el
  fallecido es cónyuge o conviviente, padres, hijos o hermanos. El otro duelo es
  potestativo y CAYLA decidió no pagarlo.

La 0314 invierte la regla: **paga lo que el catálogo dice que paga**, y excluye
solo los tres que tienen tratamiento propio (descanso médico por su tope de 20
días, maternidad por su subsidio de días calendario, vacaciones por `vacd`). El
tipo nuevo `duelo_familiar_directo` entra con `requiere_aprobacion = true` y sin
exigir documento — un acta de defunción no tiene número de colegiatura.

**Lo que la auditoría empírica midió** (7 escenarios, `BEGIN … ROLLBACK`):

| | antes | después |
|---|---|---|
| Duelo directo, firmado por DO | 1526,81 | **1824,58** ✅ |
| Duelo directo, sin firma | 1526,81 | 1526,81 ✅ |
| Duelo otro familiar | 1526,81 | 1526,81 ✅ |
| Licencia con goce | 1526,81 | **1824,58** ✅ |
| Descanso médico | 1846,74 | 1846,74 **intacto** |
| Vacaciones | 1846,74 | 1846,74 **intacto** |
| Control | 1846,74 | 1846,74 **intacto** |

Las tres últimas son las que importaban: **nadie cobra dos veces**.

**Y una confirmación que no se buscaba.** Al correr la suite, la prueba `244`
—«la boleta y la reserva dicen lo mismo»— se puso roja en la dirección contraria
a la habitual: su escenario `E09LicGoce` estaba declarado como divergencia
conocida, con la nota *«cuando se arregle, esta fila pasa a cuadran»*. Pasó a
cuadrar. O sea que **`fn_provisiones` ya devengaba esos días**; era la boleta la
que no los pagaba. El arreglo no separó el par: lo puso de acuerdo.

**Lo que falta antes de pegarla, y no es opcional:** correr
[`scripts/sql-manual/se_usa_la_licencia_con_goce.sql`](../scripts/sql-manual/se_usa_la_licencia_con_goce.sql)
en el SQL Editor. Solo lee, y responde lo único que esta migración no sabe: si
hay una licencia con goce registrada dentro de un periodo **ya pagado**. Si la
hay, a esa persona se le pagó de menos y hay que devolverle la diferencia — la
0314 evita que vuelva a pasar, pero no devuelve nada.

**Queda abierto, y anotado en [`hallazgos-abiertos.md`](hallazgos-abiertos.md):**
el feriado de quien tuvo licencia con goce se paga corto (~S/2,2 por día de
licencia y por feriado). Es preexistente —se midió con la 0306 vigente y ya daba
corto— y va aparte porque `fn_feriado_devengado` es un punto caliente.

---

## 2026-08-26 — Dos horarios ya no pueden cubrir el mismo día (0309)

**PEGADA EN PRODUCCIÓN el 2026-08-26**, y verificada: candado puesto, cero
solapes, y `fn_set_horario_semanal` sigue viva y ejecutable por `authenticated`
—o sea que la pantalla de Horarios sigue pudiendo asignar—.

`horarios_asignados` solo tenía un índice **parcial** sobre el tramo abierto
(`idx_horario_vigente_unico`, `where vigente_hasta is null`). Dos tramos
cerrados podían pisarse, y cuando dos cubren el mismo día quien decide es un
`order by vigente_desde desc limit 1`: elige uno **en silencio**, y de esa
elección sale qué se esperaba de esa persona ese día — si llegó tarde, si salió
antes, o si faltó. El diagnóstico estaba escrito en la cabecera de la 0209 desde
hacía tiempo y nadie había vuelto a él.

Medido antes de escribir nada, con `hay_horarios_solapados.sql`: **10 pares en 8
personas** sobre 113 tramos. Nueve eran el mismo error de convención —el tramo
anterior cerrando el mismo día en que empieza el siguiente, tomando
`vigente_hasta` como «el día en que arranca el próximo» cuando es inclusivo— y
uno era un solape real de cuatro días.

**Nadie cobró de menos por esto.** El arreglo no le cambió el horario a ninguna
persona ningún día, y no es una deducción: se midió. Gana siempre el de
`vigente_desde` más reciente, así que el que empieza antes ya estaba tapado en
los días del solape.

### Lo que costó dos intentos, y es lo que hay que recordar

La primera versión demostraba esa invarianza con una tabla **temporal**:
guardaba qué tramo mandaba para cada persona y cada día, hacía el arreglo, lo
recalculaba y comparaba. Pasó las 1652 pruebas del CI y **murió al pegarla**:

    ERROR: 42P01: relation "_horario_antes" does not exist

El SQL Editor no le deja ver esa tabla al bloque que la lee. El CI no lo cazó
porque aplica con `psql`, y ahí sí sobrevive. **Un freno que depende del entorno
donde corre no es un freno** — y el entorno donde corre de verdad es el SQL
Editor, no el contenedor de GitHub.

Y había un segundo defecto, independiente del editor: esa versión **cambiaba los
datos y después comprobaba**. Si la comprobación fallaba, el `rollback` la
salvaba; pero pedirle a la red que te salve no es lo mismo que no saltar. La
versión que se pegó comprueba primero, sin tabla temporal: para cada día que un
tramo va a perder pregunta si algún tramo posterior ya lo cubría.

Se supo que se podía reintentar limpio porque se midió, no porque se supusiera:
`scripts/sql-manual/que_paso_con_la_0309.sql` distingue los tres estados
posibles —aplicó entero, quedó a medias, no entró nada— y dijo que producción
estaba intacta. Esa consulta queda en el repo: el mismo accidente le puede pasar
a cualquier migración que toque datos.

La prueba `243` subió a 12 aserciones y ganó lo que le faltaba: **un caso que
DEBE bloquear**. Un tramo largo pisado por uno corto posterior, donde acortar
dejaría a alguien sin horario dieciséis días. Un freno probado solo con casos que
pasan no está probado.

### Y de paso: `dame-el-sql.sh` entregaba la migración equivocada

Se descubrió pidiendo la 0309 con el cero delante. `printf %04d` en `/bin/sh`
lee un número que empieza por cero como **octal**:

| Pides | Te daba |
|---|---|
| `0309` | error «invalid number» — ruidoso, se ve |
| `0173` | la **0123**, sin decir nada |
| `0177` (cómo se pagan las vacaciones) | la **0127** (la foto del pago) |

Los dos archivos equivocados existen, así que el script los encontraba, los
copiaba al portapapeles y decía «✓ Se puede pegar». Su propia ayuda promete «da
igual con ceros o sin ellos». Arreglado en dos capas: se quitan los ceros antes
de formatear, y además el número del archivo encontrado tiene que coincidir con
el pedido o no se entrega nada. La segunda vale más que una prueba — corre en
cada uso.

**Nunca se entregó una migración equivocada por esto:** el hábito de la casa es
escribir el número sin ceros, y así siempre funcionó.

---

## 2026-08-25 — La reserva le pagaba de más a quien estuvo de vacaciones (0302)

**PEGADA EN PRODUCCIÓN el 2026-08-25.** El SQL Editor devolvió `0302 · OK` con
el md5 de llegada declarado, `866c0a1664afde204ae6d685760afb84`, 36 518
caracteres. md5 de partida `93531851f35abcdd295fd8fb4aa77922` (33 892), pedido a
producción antes de escribir.

`fn_provisiones` contaba cada día de **calendario** de una ausencia pagada; la
boleta cuenta los **laborables**. Los sábados y domingos del tramo entraban dos
veces: una dentro del sueldo mensual y otra como día de ausencia.

Se leía sin saber SQL: **la reserva le daba más gratificación a quien estuvo de
vacaciones que a quien trabajó el mes entero.** Y no se quedaba en un informe —
`fn_grati_cts_periodo` autocompleta el depósito desde esa base, así que el
exceso salía del banco el 15/05, el 15/07, el 15/11 y el 15/12.

Medido en local con `BEGIN … ROLLBACK`, marzo 2026, S/1.950, 19 días corridos
de ausencia. Se usó el **mes calendario** como periodo a propósito, para no
arrastrar la divergencia del divisor 29→28 que la 0276 dejó abierta:

| Caso | Antes | Con la 0302 |
|---|---|---|
| Vacaciones | 20,96 | **0,00** |
| Descanso médico | 20,96 | **0,00** |
| Trujillo, 6 días laborables **con domingo** | 15,72 | **0,00** |

Trujillo no es decoración: es la fila que separa este arreglo de «restarle los
domingos a la ausencia». Un arreglo así pasa las otras comprobaciones y falla
ésa.

**Lo que NO se tocó, y es el cuidado de la migración.** La rama existe desde la
0135 porque sin ella tomarse las vacaciones te *bajaba* la gratificación — el
error contrario, y ése sí contra la persona. Sigue contando la ausencia entera;
cambia cuántos días de ella cuentan. Tampoco cambió cuánto vale el día: se
intentó poner `salario / días laborables` en lugar de `salario / días del mes`,
que suena más fino, y **se midió que empeoraba** — la diferencia subía a S/32,16
en vez de bajar a cero, porque así el día de ausencia valdría más que el
trabajado.

Prueba **236**, seis comprobaciones. Con la función de producción fallan cuatro
—las cuatro de «boleta = reserva»— y pasan las dos que vigilan que la rama de la
0135 siga en pie. Ninguna otra de las 159 se apoyaba en el defecto.

### Lo que la 0302 dejó abierto — RESUELTO el 2026-08-26, ver la 0308

Aquí se había anotado que maternidad y licencia con goce no cuadraban contra la
boleta, y que hacía falta averiguar por qué. Ya está medido, y la respuesta
partió en dos:

- **Maternidad firmada: NO es un defecto y no hay nada que arreglar.** La boleta
  marca esos días como `dias_maternidad_sin_monto` — o sea que a propósito no
  les pone sueldo, porque el subsidio lo paga EsSalud y no CAYLA. Y la reserva
  hace bien en devengar, porque el art. 3.2 c) del D.S. 005-2002-TR cuenta como
  tiempo efectivamente laborado «los descansos o licencias establecidos por las
  normas de seguridad social y que originan el pago de subsidios». Los dos
  números miden cosas distintas; forzarlos a coincidir sería el error. La prueba
  242 comprueba que SIGAN divergiendo, para que nadie los iguale sin saberlo.
- **Licencia con goce: sigue abierta, y sin lote.** Está en el catálogo como que
  paga, y `fn_planilla_calcular` no la paga por ningún camino. Es el error
  contrario —alguien deja de cobrar lo que le toca— y necesita su propia
  medición. La 0306 ya la había anotado por su cuenta.

---

## 2026-08-26 — Los cuatro P1 del terminal, medidos uno por uno (0318 y 0320)

**Las dos PEGADAS EN PRODUCCIÓN el 2026-08-26**, con md5 de llegada exacto.

El informe de agosto dejó cuatro P1 «sin reverificar por tiempo». Se
reverificaron midiendo, no leyendo — y esa disciplina ya había pagado dos veces
el mismo día: el pendiente 7 estaba hecho y el 5 estaba exagerado.

### 1 · El botón «¿Volviste a entrar?» borraba la salida de anoche — CERRADO

Era cierto. Medido con el caso exacto del informe: Ana entra el martes 15:00 y
cierra tienda a las 00:30 del miércoles. La 0240 lo guarda **bien**
—`fecha_jornada` = martes, 9,50 h cerradas— y aun así:

| | Antes | Tras pulsar el botón |
|---|---|---|
| Jornada del martes | 9,50 h, cerrada | **sin horas, abierta** |
| Lo que paga la boleta | **S/ 109,62** | **S/ 0,00** |

**Dos mitades, arregladas juntas.** El terminal repartía por fecha de calendario
y nunca leía `fecha_jornada` (PR #90, función pura `jornadaEnCursoPorPersona`,
cinco pruebas); y `fn_reabrir_dia` buscaba la salida igual (**0318**).

Lo que casi sale mal: el arreglo obvio era exigir `fecha_jornada = hoy`. Habría
dejado **sin poder reabrir a todo el mundo** — las marcas normales no llevan esa
columna, solo la que cruza medianoche. El `null` es el caso corriente. La
comprobación 4 de la prueba 254 existe para que ese remedio peor no entre: pasaría
las otras tres.

### 2 · El auto-cierre llegaba primero y la salida se rechazaba — CERRADO (0320)

También cierto, y el más caro. `fn_auto_cierre` corre cada 15 minutos y cierra
la jornada pasadas `auto_cierre_horas` (3) desde la hora **programada**. La rama
de la 0240 solo adoptaba la salida tardía si la jornada seguía `abierta`, así
que **la promesa nº 1 de esa migración solo valía 3 horas**.

Medido, horario 13:00–21:00: trabajó **11,50 h**, le quedaban **8,00 h** puestas
por el robot, y su salida real se rechazaba con *el mismo error que la 0240 cita
como lo que resuelve*. El agravante, también medido: el terminal le ofrecía
ENTRADA, la aceptaba, y nacía el día fantasma.

**Decidido por Felipe:** que la marca real gane a la del robot. Frente a subir
`auto_cierre_horas` —encoge la ventana pero no la cierra— o dejarlo como aviso
manual para DO.

Adoptar no bastaba: la `salida_final` sintética seguía ahí. Se **anula, no se
borra**, con su rastro en `correcciones_auditoria`. Y muy acotado: solo
`origen='auto_cierre'`, solo si DO no la confirmó, solo fuera de un mes pagado,
y dentro del tope de 16 h de la 0240.

**La comprobación 6 de la prueba 256 es la que fija el límite:** si DO ya
confirmó ese auto-cierre, la marca no se toca. Un arreglo que anulara «cualquier
salida del robot» habría pasado las otras cinco y pisado el criterio de una
persona.

### Lo que queda de los cuatro

El P1 de `fn_dia_incoherente` / `fn_siguiente_tipo_esperado` y el de la
incidencia sin nombre **no se han reverificado**. Vienen del informe, no de una
medición de hoy.

### Dos cosas de método que costaron y conviene no reaprender

**El contenedor local dejó de servir.** Otras sesiones lo reconstruían en bucle;
ocho intentos seguidos no dieron una base estable, y la batería de la 0320 la
corrió **el CI**, no esta Mac. Es el instrumento a usar cuando el local no da: la
suya está limpia y aislada.

**Y el md5 de llegada se puede calcular sobre el ARCHIVO** cuando no hay base:
es el texto entre `AS $function$` y el `$function$` final. Antes de fiarse se
validó contra la 0318, cuyo md5 ya había confirmado producción — mismo hash y
misma longitud al carácter. Después producción confirmó también el de la 0320.
El método sirve; validarlo contra un valor conocido, primero.

---

## 2026-08-26 — Una imagen de Supabase abrió 105 funciones, y el CI lo cazó (0315)

**PEGADA EN PRODUCCIÓN el 2026-08-26.** El SQL Editor devolvió `0315 · OK`, 258
funciones revisadas, **0 abiertas a `anon`**, y la regla por defecto de
`postgres` sin `anon` dentro.

### Cómo empezó

`main` se puso rojo a las 20:00 en dos pruebas de permisos, **en un commit que
solo tocaba un `.md`**. Eso solo puede ser el entorno. Comparadas la última
corrida verde y la primera roja, la única diferencia era la imagen:
`supabase/postgres:17.6.1.159` → **`17.6.1.165`**. El workflow instala el CLI de
Supabase con `version: latest`, así que se la trajo sola.

### Lo que destapó, y por qué no era un falso positivo

La protección de esta casa era **una línea** de la 0076:

    alter default privileges revoke execute on functions from public;

Eso quita el permiso que PostgreSQL le da a **PUBLIC** por defecto. La imagen
nueva no usa PUBLIC: trae una regla que le concede EXECUTE a **`anon`
explícitamente**, y *revocar de PUBLIC no quita una concesión explícita a otro
rol*. Son dos cosas distintas.

Así que la 0076 seguía corriendo sin error y ya no protegía. **No falló: dejó de
tener razón.** Es la tercera vez el mismo día que aparece esa forma de avería
—la primera fue la línea de la 0276 que la 0310 retiró— y merece quedar dicha
así: *una línea con la premisa caducada no se rompe, se queda muda.*

### Cómo se midió, que es lo que hizo falta

Se empujó la **prueba 250 solo para medir**, con `diag()` que imprimen el
diagnóstico pase o falle. El CI contestó:

| | Producción y local (`.159`) | CI (`.165`) |
|---|---|---|
| Funciones abiertas a `anon` | **0 de 258** | **105 de 258** |
| Regla por defecto de `postgres` | `{postgres, service_role}` | `{postgres, **anon**, authenticated, service_role}` |
| Dueño de las `fn_*` | postgres, 276 | postgres, 276 |

Esa última fila **descartó la primera hipótesis**, que era mía y era falsa: yo
dije que la imagen cambiaba *quién* crea las funciones. No. Queda escrito para
que nadie la persiga otra vez.

Y explica por qué solo fallaban dos pruebas: son las dos únicas que comprobaban
esto. Las otras **103 funciones expuestas no tenían quien las mirara**.

### El arreglo (0315), y por qué era seguro

**Decidido por Felipe:** el barrido explícito, no fijar la versión del CI.

Dos mitades: revoca `execute` de `anon` y PUBLIC sobre cada `fn_*` existente, y
saca `anon` de los privilegios por defecto para que las próximas nazcan
cerradas. No toca `authenticated` ni `service_role` — los guards de dentro de
cada función siguen decidiendo qué puede hacer alguien **con** sesión.

**No le quitó nada a nadie**, y eso se midió antes de escribirlo: producción ya
tenía cero funciones abiertas a `anon` y todo funcionaba, terminales incluidos.
La migración escribe de forma permanente lo que ya era cierto, para que deje de
depender de una regla que Supabase cambia sin avisar.

**Verificado en dos vueltas.** Primero reproduciendo la condición de la imagen
nueva en local dentro de `BEGIN … ROLLBACK`: con su regla puesta, funciones
abiertas; con la 0315, cero — **incluida una función creada mientras la puerta
estaba abierta**. Después el CI lo confirmó contra la imagen real: verde.

**Solo `fn_*`, y se comprobó por qué:** las otras 188 funciones de `public`
pertenecen todas a la extensión `btree_gist`, ninguna es de la casa. `fn_*` no
es una convención cómoda, es la frontera exacta.

### Lo que queda abierto, sin lote

**El CI instala el CLI con `version: latest`.** Hoy nos hizo un favor —el aviso
era real— pero es una dependencia que se mueve sola bajo los pies de todas las
sesiones, y la próxima vez puede romper por algo que no sea cierto. Se planteó
fijarla y Felipe eligió arreglar la raíz primero. Queda anotado como decisión
pendiente, no como olvido.

---

## 2026-08-26 — El divisor 29→28: medido, decidido y vigilado (prueba 248)

**No hay nada que pegar.** Esto no es una migración: es una medición, una
decisión y una prueba.

Llevaba seis días declarado abierto en la cabecera de la 0276 y sin un solo
número. Ya lo tiene.

### Qué pasa, en una frase

Para el mismo 10 de febrero, **la boleta dice que ese día vale `salario/31`** —los
días que tiene el periodo 29-ene → 28-feb— y **`fn_provisiones` dice
`salario/28`**, los días que tiene febrero. Ninguna de las dos es absurda:
dividir el sueldo entre los días de su mes es lo normal. El problema es solo que
no coinciden.

### Y se compensa solo

| Periodo (S/1.950) | Boleta | Reserva | Diferencia |
|---|---|---|---|
| 29 ene → 28 feb (31 días) | 115,32 | 126,55 | **+11,23** |
| 1 → 28 mar (28 días) | 116,07 | 104,83 | **−11,24** |
| **Los dos juntos** | 231,39 | 231,38 | **−0,01** |

Febrero no tiene 29, así que el periodo siguiente empieza el 1 de marzo y solo
dura 28 días: ahí la boleta divide entre 28 (día caro) y la reserva entre los 31
de marzo (día barato). **Es la misma distorsión, al revés.** El resto del año
alterna ±S/3,50 —meses de 30 contra meses de 31— y también se cancela.

**Neto de los once periodos que caben en un año: S/0,01.** Acumulado al depósito
del 15/07: +S/3,49. Al del 15/12: −S/3,50. Sumando CTS y vacaciones, que salen de
la misma base, multiplica por ~2,1: el peor mes son ±S/23 por persona y el año
sigue siendo un céntimo.

### La decisión

**Felipe, 2026-08-26: no se toca, se vigila.** Las razones, por orden:

1. Mueve S/0,01 al año. No hay plata que recuperar.
2. El arreglo es más peligroso que el defecto: habría que cambiar el divisor en
   tres ramas de `fn_provisiones`, la misma función que ha estado en el centro de
   cinco errores de plata en una semana. Cambiar el corazón del cálculo para
   mover cero es mala apuesta.
3. El único sitio donde no alcanza a compensarse es un **cese a mitad de año**,
   que se lleva la diferencia acumulada de ese momento — hasta unos S/11 de
   gratificación, ~S/23 con CTS y vacaciones, y puede ir para cualquier lado.

**Lo que sí es real y queda sin arreglar:** la pantalla de Provisiones oscila
hasta un ±10 % en febrero y marzo. Se corrige sola al mes siguiente, pero si
miras el número de febrero para planificar, está alto.

### El vigilante (prueba 248)

La 244 **esquiva** esta divergencia usando mes calendario. «La esquivo» no puede
ser el final, así que la 248 corre los **once periodos reales 29→28** y exige que
el año cierre en cero. Tres comprobaciones: que los once se midieron, que el año
cierra dentro de cinco céntimos, y —la que impide la falsa tranquilidad— **que
siga habiendo divergencia mensual**, porque si algún día desaparece significa que
alguien igualó los divisores y esta cabecera pasó a mentir.

**Se comprobó que tiene dientes**, y el primer intento fue inválido: se rompió el
divisor de las ramas 2, 4 y 5 y la 248 ni se inmutó, porque la rama 1 usa
`j.fecha` en vez de `gs` y el reemplazo la esquivó. Rota **la rama 1** —la que
estas once personas ejercitan— el neto del año pasa de −0,01 a **+15,14** y la
comprobación 2 cae. Sin esa segunda vuelta se habría entregado una prueba que
casi no puede fallar, que es peor que no tenerla.

### Por qué once periodos y no doce

El doceavo cruza el 31 de diciembre y `fn_provisiones` reparte en semestres del
**año calendario**: los días de diciembre caen en un semestre que la consulta del
año siguiente no muestra. Sale una diferencia de S/15,73 que parece grave y es
del laboratorio — comprobado moviendo el año entero, el outlier se muda con el
periodo que cruza.

---

## 2026-08-26 — Ya hay un freno para el par boleta/reserva (prueba 244), y encontró la 0310

**Pendiente: pegar la 0310 en producción, DESPUÉS de la 0308**
(`./scripts/dame-el-sql.sh 310`). md5 de partida
`adb0a986b32d26920fb9488a314b4d45`, 38 053 caracteres — que es el md5 de llegada
declarado por la 0308. Si producción devuelve otro, lo más probable es que la
0308 todavía no esté pegada.

### El freno

`fn_planilla_calcular` (la boleta) y `fn_provisiones` (la reserva) responden la
misma pregunta por caminos distintos. **Cinco veces se tocó una mitad sin la
otra** —0276, 0286, 0293, 0302, 0308— y las cinco costaron plata. Siempre la
misma forma: alguien arregla una mitad con buen criterio, sus pruebas pasan, el
CI queda verde, y el par termina diciendo dos cosas distintas sobre la misma
persona el mismo mes. Se encontraban a mano, de casualidad, y siempre después.

La **prueba 244** es una matriz de doce escenarios donde cada uno declara su
veredicto esperado, y comprueba **las dos direcciones**: que no se separe lo que
debe cuadrar, y que no cuadre lo que debe divergir. Esa segunda mitad importa
tanto como la primera: impide que alguien «arregle» sin querer una divergencia
correcta.

**No compara ni un importe** — solo la relación entre los dos lados. Así
sobrevive a cualquier migración que cambie legítimamente cuánto se paga, y solo
se pone roja cuando el par se separa. Una prueba con importes escritos a mano
habría que reescribirla cada vez, y una prueba que se reescribe seguido deja de
leerse.

Dos decisiones de laboratorio que costaron un rato y quedan escritas en la
prueba para no repetirlas: el periodo es el **mes calendario** (con el 29→28
real mediría a la vez la divergencia del divisor, que sigue abierta desde la
0276), y **el sueldo empieza dentro del mes** (`grati_s1` acumula el semestre, y
con el sueldo vigente desde antes la reserva traía meses que la boleta no —
S/324,98 que parecían un defecto grave y eran del laboratorio).

### Lo que encontró la primera vez que se corrió (0310)

Tres de los doce escenarios divergían por **S/5,24** y ninguno estaba en la
lista de divergencias esperadas.

La 0276 puso en la rama de ausencias de `fn_provisiones` una exclusión del
feriado dentro de un descanso médico, con una razón escrita y correcta: «su
lateral `dmd` EXCLUYE el feriado desde la 0254». La **0293** quitó esa exclusión
de `dmd`. La premisa quedó falsa y nadie lo notó, porque **una línea con la
premisa caducada no falla: solo deja de tener razón.**

Resultado: el feriado dentro de un descanso médico **no lo contaba nadie**. Acá
se excluía «porque ya lo cuenta el feriado», y `fn_feriado_devengado` lo excluye
por su cuenta. Es el día sin dueño que la 0262 advirtió y que la 0306 volvió a
advertir — esta vez llegó por el camino contrario: no se quitó de los dos lados,
se quitó de uno y el otro se quedó viejo. Y va **contra la persona**.

| Caso | Antes | Con la 0310 |
|---|---|---|
| Descanso médico 02–20 con feriado dentro | −5,24 | **0,00** |
| Descanso médico 09–13 justo sobre el feriado | −5,24 | **0,00** |
| Ídem en Trujillo, feriado en **domingo** | −5,24 | **0,00** |

**Se comprobó que NO es doble conteo**, que era la duda seria — mi matriz no
puede ver un defecto que esté en los dos lados a la vez. Medido entre gemelas:
la boleta hace exactamente lo mismo (4,10 contra 3,12, idéntico en los dos
lados). Que a quien tuvo parte médico el feriado le prorratee más alto es el
art. 8 del D. Leg. 713: el bloque incluye `horas_descanso_medico`.

### La prueba 213 se reescribió, y por qué

Su aserción 25 defendía la asimetría que la 0293 dejó sin premisa. Se intentó
apuntarla contra la boleta y **no vale**: ahí `grati_s2` acumula el semestre y la
boleta mide un mes, y se separan S/146,78 por el tamaño de la ventana —idéntico
en las dos gemelas, o sea que no es defecto—. Ese laboratorio no está construido
para comparar el par. Pasa a vigilar la otra mitad: que el día no se pierda. El
guardián del par vive en la 244.

### Y una observación que queda anotada, sin lote

Que el feriado prorratee **más alto** para quien estuvo de descanso médico es la
decisión de la 0293 y está pegada. No la reabro acá — pero conviene saber que
existe, porque significa que un parte médico sube ligeramente el feriado de ese
bloque. Está medido y es coherente entre boleta y reserva.

---

## 2026-08-26 — La 0306 arregló media cosa, y la otra media costaba plata (0308)

**Pendiente: pegar la 0308 en producción** (`./scripts/dame-el-sql.sh 308`).
md5 de partida `866c0a1664afde204ae6d685760afb84`, 36 518 caracteres — es lo que
devolvió el SQL Editor al pegar la 0302 el mismo día, así que viene de
producción y es de hoy.

La **0306** (de otra sesión, pegada el 26/08) hizo que `fn_planilla_calcular`
exigiera `aprobada_at` para pagar el descanso médico y la maternidad. El
argumento es correcto y está bien escrito: `fn_aprobar_ausencia` existe justo
para que sea DO quien decide qué convierte días en plata, y no la encargada de
sede.

Pero solo cambió una mitad del par. **`fn_provisiones` no se enteró**, así que
un descanso médico registrado y sin firmar pagaba S/0 de sueldo y reservaba como
si se hubiera pagado el mes entero. Y de ahí sale el depósito:
`fn_grati_cts_periodo` es la **única** función de la base que llama a
`fn_provisiones` — comprobado sobre el `prosrc` de todas ellas.

Medido en local, marzo 2026, S/1.950, 19 días del 02 al 20:

| Caso | Antes | Con la 0308 |
|---|---|---|
| Vacaciones (así entran: **sin firma**) | 0,00 | **0,00** — intacto |
| Descanso médico **sin firmar** | 78,63 | **0,00** |
| Descanso médico firmado | 0,00 | **0,00** |
| Maternidad **sin firmar** | 78,63 | **0,00** |
| Maternidad firmada | 78,63 | 78,63 — correcto, ver arriba |

S/78,63 en gratificación por caso; **S/164,34** sumando CTS, vacaciones y la
bonificación extraordinaria.

**Decidido por Felipe (2026-08-26): que la reserva siga a la boleta.** Las otras
dos opciones eran revertir esa parte de la 0306 —que devolvería a la sede la
decisión de qué convierte días en plata— o dejarlo y solo avisar en pantalla,
que ve el problema pero deja salir la plata igual. Si DO firma tarde, el mes
cerrado no se toca y la diferencia se paga como retroactivo; desde la 0305 ese
movimiento puede decir de qué mes viene.

**La regla se le pregunta al catálogo, no se escribe la lista de tipos** — y eso
no fue elegancia, fue lo que evitó un desastre. Las vacaciones entran a
`ausencias` por un trigger desde su propia tabla y llegan **siempre con
`aprobada_at` en null**. Exigir la firma a ciegas le habría puesto la reserva en
cero a todo el que se toma vacaciones: un defecto mucho peor que el arreglado, y
contra la persona. `tipos_ausencia.requiere_aprobacion` ya dice que las
vacaciones no la necesitan. La comprobación 1 de la prueba 242 existe para que
ese arreglo perezoso no pueda entrar nunca.

**Lo que esto deja anotado como método**, porque es la cuarta vez que pasa
(0276, 0286, 0293, y ahora 0306→0308): **la boleta y la reserva son dos mitades
del mismo par y hay que tocarlas juntas.** Una sesión arregló una mitad con buen
criterio, sus pruebas pasaron, el CI quedó verde, y el par quedó diciendo dos
cosas distintas sobre la misma persona el mismo mes. Ninguna herramienta de la
casa lo vio: se descubrió midiendo boleta contra reserva a mano.

---

## 2026-08-25 — Una suspensión de 10 días que nadie ordenó (0294)

**Aplicada en producción el 2026-08-25** — confirmado con
`que_falta_pegar.sql`. El md5 de partida se había verificado antes contra el
SQL Editor (`96f32dbd2ff1c41da38765ef1ec5bbf6`, 994 caracteres: producción
tenía la 0075 idéntica al repositorio, comentarios incluidos). Al pegarla no se
movió ningún documento ya emitido: solo dejó de aceptar números que el
Reglamento no admite.

**Decidido por Felipe (2026-08-25): el tope se queda en 3.** No se reforma el
RIT. El candado hace cumplir lo que el Reglamento ya dice.

Revisando el caso de Sasha Fernandez (AQP) —segunda suspensión por tardanzas,
que el generador propuso con 2 días— la pantalla mostraba **10 días**: 26, 27,
28, 29 y 31 de agosto, y del 1 al 5 de septiembre.

**Los tecleó Felipe a propósito, para enseñar el defecto**, y conviene que quede
escrito: la primera versión de esta nota supuso que había sido la rueda del
mouse y eso era inventar una causa. El defecto no necesita ninguna: el campo
aceptaba diez días y la base los escribía.

**Los topes estaban escritos en el generador y no en el editor.** La 0235 le
puso a `fn_expediente_generar_tardanza` los tres límites del RIT —54.5 tres días
como techo, 19.2 c) la primera de uno a dos, 19.2 d) la segunda mayor que la
primera— y `fn_expediente_set_suspension` (0075) siguió escribiendo `p_dias` sin
preguntar nada. Cuando la 0075 se escribió, todas las suspensiones salían de un
día y no había qué topar; la 0232 hizo normales los rangos de dos y tres.

**Y el `max={15}` de la pantalla no era una defensa.** El atributo `max` de HTML
no impide escribir ni enviar: solo valida un formulario, y acá hay un `onBlur`
que llama a la RPC. El candado quedó en la base; la pantalla pasa a ser el
letrero, y dice lo que de verdad cabe.

**El campo ya no ofrece un rango fijo, sino el de ESE documento.** Preguntado
por Felipe: no es 1 a 3 siempre. Para quien nunca fue suspendida por tardanzas
son 1 o 2 (19.2 c); para quien ya cumplió una de un día —el caso de Sasha— son
**2 o 3**, porque la segunda tiene que ser mayor. La pantalla calcula ese rango
con la misma cuenta que la base, lo escribe al lado del campo con su motivo, y
pinta en rojo el valor que quede fuera. Un borrador que hoy tenga un número
imposible se ve al abrir la pantalla, no al intentar firmarlo.

Se mantiene además `onWheel` con blur: un `<input type="number">` cambia de
valor con la rueda del mouse cuando el cursor pasa por encima al hacer scroll.
No fue lo que pasó acá, pero mueve días de sueldo sin que nadie lo teclee.

**De paso, un tercero:** «Generar borrador» se ofrecía aunque ya hubiera un
borrador pendiente de esa causal. La base lo rechaza desde siempre, así que el
botón solo podía terminar en error.

⚠️ **El tope de tres días es del RIT de CAYLA, no de la ley.** La LPCL no fija
número —exige proporcionalidad y gradualidad— y la práctica privada peruana
maneja techos informales de ~7 días. Subirlo es decisión de Gerencia, pero se
toma **reformando el RIT y volviéndolo a entregar con acuse**, no aflojando el
candado: un memo que se funda en el Reglamento y lo incumple en su parte
resolutiva no sirve como sanción previa del literal h) del art. 25 el día que
haga falta.

**Lo que queda sin cerrar:** los documentos ya firmados o entregados no se
revisan solos. Si alguna suspensión pasada quedó fuera de los topes, hay que
buscarla a mano — la 0294 solo cuida las que se editen desde ahora.

---

## 2026-08-25 — Revisión nocturna: las nueve cosas más importantes por corregir

**Contexto de esta entrada.** Felipe pidió una revisión de código exhaustiva
mientras dormía. Se lanzaron dos pasadas de auditoría adversarial (Workflow,
46 agentes de búsqueda+verificación, cada hallazgo releído contra el código
real por un escéptico aparte) sobre permisos/RLS, fechas, duplicación de
lógica, cobertura de pruebas SQL, componentes React, seguridad de rutas
`api/` y consistencia de UI. **34 hallazgos sobrevivieron** esa verificación.

**A media noche apareció algo más importante que lo anterior**: el directorio
`auditoria/` —no listado en la tabla de `docs/` de este archivo ni en
CLAUDE.md, por eso ninguna pasada lo leyó— contiene una auditoría previa de
**116 agentes (2026-08-17/18)**, con **80 hallazgos sobrevivientes** (4 P0,
8 P1, 29 P2, 39 P3) y su propio plan de remediación por lotes
(`CAYLA_CORP_OPS_202608_PlanRemediacion.md`). Es sustancialmente más profunda
que lo de esta noche. **Casi todo lo que las dos pasadas de esta noche
encontraron ya estaba ahí catalogado** — incluida, palabra por palabra, la
política RLS del terminal que salió en la primera pasada.

Así que lo de abajo no es "mi lista independiente": es **el estado real,
reverificado esta noche contra el código vivo** (no contra ningún informe) de
lo más grave de esas dos fuentes juntas, más lo genuinamente nuevo que ninguna
de las dos tenía.

**Lo que NO se hizo**: cruzar los 34 hallazgos de esta noche contra los 39 P3
del informe viejo (solo contra P0/P1 y una muestra de P2). Puede haber más
solapamiento del que aquí se descuenta.

---

⚠️ **ESTA LISTA ENVEJECIÓ EN HORAS. Releída y medida el 2026-08-25 por la
tarde:** tres de los nueve ya estaban resueltos por otras sesiones —con su
migración y su prueba— mientras el texto seguía diciendo «sigue abierto». Casi
manda a reescribir la 0292 desde cero.

| # | Estado hoy | Dónde |
|---|---|---|
| 1 · las nueve funciones `SECURITY DEFINER` | ✅ cerrado y **aplicado** en producción | migración 0292 · prueba 228 |
| 2 · ascenderse a Admin | ✅ escrito · **falta pegar**, y no antes de desplegar (ver abajo) | 0295 + 0296 + 0300 · pruebas 232, 235 |
| 3 · el kiosco, el DNI y el sueldo | ✅ cerrado y **aplicado** | migración 0291 · prueba 227 |
| 4 · el candado del mes pagado | ✅ los seis candados cerrados y **aplicados**; quedan 14 usos fuera del candado | migración 0307 · prueba 241 |
| 5 a 9 | siguen abiertos, medidos abajo | — |

**Lo único que falta pegar en todo el repositorio son la 0295 y la 0296**, y eso
se pregunta con `./scripts/que-falta-pegar.sh`, no se lee acá.

⚠️ **La 0296 NO se pega hasta que esté desplegado el arreglo de
`/api/admin/cuentas`.** Su trigger aborta cualquier `update` de `personas.rol`
que no venga de `postgres`, y el botón «promover a encargada» de
`/admin/cuentas` escribía el rol con la llave de SERVICIO, que dentro de la
base es `service_role`. Medido contra el Postgres local con el trigger puesto:
devolvía «El rol se cambia con fn_set_rol, no con un update directo». Pegarla
antes deja el botón muerto.

El arreglo ya está hecho (commit «Promover a encargada deja de escribir el rol
por la puerta de atrás»): la ruta llama a `fn_set_rol` con la sesión de quien
pulsó el botón, vía `createUserClient(token)`. **De paso cerró un agujero que
ninguna de las dos auditorías había visto**: por ese camino el cambio de rol no
dejaba NINGUNA fila en `correcciones_auditoria`, porque la llave de servicio no
es nadie dentro de la base (`auth.uid()` es null) y no había a quién anotar.
Justo lo que la 0295 existe para impedir, evitado por la otra puerta.

**La lección, que es la misma de siempre en este archivo:** una lista de
pendientes escrita a mano compite con varias sesiones trabajando en paralelo, y
pierde. Antes de tomar cualquier hallazgo de aquí, medirlo contra el código
vivo — `ls supabase/migrations`, `donde-vive.sh`, la prueba pgTAP que le
corresponda.

---

### 1 · ~~Nueve funciones `SECURITY DEFINER` entregan datos de cualquier persona a cualquier sesión~~ — ✅ CERRADO (0292, prueba 228, aplicado el 25/08)

**Dónde:** `fn_falta_contadores` (0094) · `fn_tardanza_escalon` (0246) ·
`fn_dia_suspendido` · `fn_dias_suspension` · `fn_beneficio_ya_depositado` ·
`fn_educacion_monto` (0149) · `fn_es_dia_laborable` · `fn_reglamento_no_acusado`
· `fn_dcs_por_que_no_compensa`. Las nueve corren como `postgres` (sin RLS),
reciben un `p_persona_id` que manda quien llama, y `grant execute … to
authenticated`.

**Por qué importa:** cualquiera de las ~30 personas con cuenta hace un POST a
`/rest/v1/rpc/fn_educacion_monto` con el id de una compañera y se entera de su
banda salarial; con `fn_tardanza_escalon`, si tiene una suspensión encima y
cuál es el siguiente escalón; con `fn_falta_contadores`, las fechas exactas de
sus inasistencias. Los ids de personas no son secretos — salen en el roster
del terminal.

**Reverificado esta noche** contra el Postgres local: las nueve siguen dando
`true` en `has_function_privilege('authenticated', oid, 'EXECUTE')`. El
informe de agosto lo midió con HTTP real (JWT firmado con el secreto local,
`POST /rest/v1/rpc/...` → HTTP 200) y con 8 intentos de refutación fallidos.
El arreglo ya está medido y no toca ninguna pantalla: `revoke execute` en las
nueve — una función `SECURITY DEFINER` que llama a otra lo hace como su dueño
(`postgres`), no como `authenticated`, así que los envoltorios con guard que
sí se usan desde el panel siguen funcionando igual.

**Propuesta:** la migración de revokes, con la prueba pgTAP que fija el
predicado correcto (`prosecdef + grant a authenticated + recibe p_persona_id +
sin guard en el cuerpo` — no "todo prosecdef", eso ya se probó y dio 14 falsos
positivos).

### 2 · ~~Una `lider_do` puede ascenderse a Admin sola, en tres clics y sin dejar rastro~~ — ✅ CERRADO (0295 + 0296 + 0300, las tres confirmadas en producción el 2026-08-25)

**Dónde:** `apps/web/app/(admin)/admin/equipo/page.tsx:422-431` escribe `rol`
directo a la tabla `personas` vía `.update()`; el desplegable que lo alimenta
(líneas 18-23) ofrece "Admin". La policy de UPDATE sobre `personas` solo exige
`fn_es_admin_o_lider()` — no compara el rol de quien llama contra el rol
destino. El camino paralelo (`apps/web/app/api/admin/cuentas/route.ts`) SÍ
llama a `puedeActuarSobre()` del escalafón y por eso rechaza a una `lider_do`
que intente promoverse — la pantalla no pasa por ahí.

**Por qué importa:** Admin ve todos los sueldos, el padrón con DNI y cuentas
bancarias, y puede reabrir un periodo ya pagado. `personas` no tiene tabla de
auditoría ni trigger de cambios de rol — ningún rastro de que ocurrió.

**Reverificado esta noche:** `fn_set_rol` no existe; `equipo/page.tsx:429`
sigue escribiendo `rol: form.rol` directo; la columna `rol` sigue con
`UPDATE` abierto a `authenticated`. Sigue exactamente igual que cuando se
encontró.

**Propuesta (ya decidida en el informe de agosto, con sus descartes
explicados):** una RPC `SECURITY DEFINER` (`fn_set_rol`) que reimplemente el
escalafón dentro de la base, y `revoke update (rol) on personas from
authenticated` — así la regla la cumplen los dos caminos, no solo el que la
llama.

### 3 · ~~El kiosco de marcaje sigue exponiendo DNI y sueldo base por REST directo~~ — ✅ CERRADO (0291, prueba 227, aplicado el 25/08)

**Dónde:** `supabase/migrations/0008_visible_todas_sedes.sql:12-17` crea la
policy `personas_select_terminal_roster` sin recortar columnas. La 0285
construyó el reemplazo (vista `terminal_roster`) y el frontend
(`apps/web/lib/terminal/roster.ts`) ya migró a leerla — pero la policy vieja
sobre `personas` nunca se retiró, y su propio comentario en la 0285 dice que
se haría "en una migración posterior, después de desplegar el frontend".

**Por qué importa:** el token del terminal es una sesión `authenticated`
normal en una Mac mini sin PIN, a la vista de todo el equipo (decisión
deliberada de Felipe). Con ese token, un `GET /rest/v1/personas?select=
documento,sueldo_base_legal,...` sigue devolviendo filas completas.

**De las tres que forman el "Lote 3" del plan de agosto, ésta es la más fácil
de cerrar ya:** el paso que faltaba (migrar el frontend) ya está hecho y
confirmado. Solo falta `drop policy personas_select_terminal_roster on
personas;`.

### 4 · El candado del mes pagado se mide con el reloj — ✅ LOS SEIS CANDADOS CERRADOS (0307, prueba 241, aplicada el 26/08) · quedan 14 usos fuera del candado

**Dónde:** once funciones (`fn_anular_marcaje`, `fn_corregir_marca`,
`fn_eliminar_marcaje`, `fn_reactivar_marcaje`, `fn_confirmar_auto_cierre`,
`fn_agregar_marcaje`, `fn_corregir_marcaje`, `fn_reabrir_dia`,
`fn_resellar_dia`, `fn_levantar_sello_si_el_dia_cuadra`,
`fn_dias_por_revisar`) derivan la fecha de una marca con `(timestamp_marca at
time zone 'America/Lima')::date`, ignorando la columna `fecha_jornada` que la
0240 introdujo para esto exacto. `fn_recalcular_jornada` sí la usa.

**Por qué importa:** si el turno del día 28 (último del periodo) cierra a las
00:30 del 29, esa salida pertenece —para la planilla— al día 28, pero el
candado la ve como del día 29, que sigue abierto. Se puede anular, corregir o
**eliminar** (`fn_eliminar_marcaje` hace `delete` duro) con el mes ya pagado.
El monto pagado no se mueve —eso lo protege `fn_recalcular_jornada`— pero **el
registro de control de asistencia que lo sustenta sí puede quedar
contradiciéndolo**, sin aviso. Es exactamente el escenario que la 0240 se
escribió para resolver, y TRU —que trabaja domingo y cierra tarde— es la sede
donde más ocurre.

**Reverificado y cerrado a medias el 2026-08-25/26.** Los once seguían con 19
usos del reloj y cero de `fecha_jornada`. Demostrado contra la base, mismo
periodo pagado, misma jornada del 28: la entrada de las 20:00 del 28 se frenaba
y la salida de las 00:30 del 29 **se borraba, 0 filas**.

La **0307** cambió de vara las SEIS comprobaciones de «periodo ya PAGADO»
—anular, corregir marca, corregir marcaje, eliminar, reactivar y confirmar
auto-cierre— y puso la regla en una sola función, `fn_fecha_de_jornada`. Está
aplicada en producción y su prueba es la 241 (11 aserciones).

**Lo que queda, y va en su propia migración:** los otros 14 usos —el resellado
del día, la búsqueda de la sede del día, `fn_dias_por_revisar` y
`fn_dia_incoherente`, que no estaba en la lista original de once pero está en el
mismo camino—. Se dejaron fuera a propósito para no mover funciones que
sostienen el cierre a tres días de usarlo.

⚠️ **Y antes de escribir esa segunda migración, la trampa:** `fn_corregir_marca`
tiene un guard que dice «aquí solo se corrige la hora dentro de su mismo día»
comparando contra el día del RELOJ. Moverlo a la fecha de jornada haría que
saltara SIEMPRE para una marca de madrugada, dejándola imposible de corregir.
Ahí hacen falta dos variables, no una. La aserción 10 de la prueba 241 se pone
roja el día que alguien lo mueva sin verlo.

**Sin reverificar esta noche por tiempo** — el informe de agosto lo midió con
4 intentos reales en `BEGIN…ROLLBACK`, todos exitosos salvo el primero.

**Propuesta:** sustituir la expresión en las once funciones por
`coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date)`
— la expresión correcta ya vive en `fn_trg_marcajes_recalcular_jornada`, solo
falta extraerla a una función compartida y llamarla desde las once.

### 5 · DNI, correos y celulares reales de diez personas, commiteados — ⚠️ REBAJADO el 2026-08-26: NO es P0

**Dónde:** `supabase/migrations/0130_los_datos_del_tregistro.sql` (commit
`f12a9a6`) y dos migraciones más. Diez líneas con DNI o correo.

**Esto decía «ya está publicado» y era falso.** Medido el 2026-08-26 contra la
API de GitHub:

| | |
|---|---|
| Visibilidad del repositorio | **privado** |
| Forks | **0** |
| Colaboradores | **1 — Felipe** |

O sea que esos datos no están expuestos a nadie: están en un repositorio privado
de una sola persona. Se corrige la entrada porque **un aviso exagerado que lleva
dos días arriba enseña a no leer los avisos**, y este archivo tiene otros que sí
importan.

**Lo que queda de riesgo, dicho en su tamaño real:** GitHub como empresa aloja
esos datos, y la exposición saltaría de golpe el día que el repositorio se
hiciera público o se sumara un colaborador. En Perú caen bajo la Ley 29733; el
argumento para limpiarlos es de cumplimiento y de higiene, no de fuga.

**Sigue siendo decisión de Felipe.** Reescribir el historial con varias sesiones
trabajando en paralelo tiene su propio costo y riesgo, y por eso no se propone
a ciegas. Pero no corre prisa: no hay incendio.

### 6 · ~~El descanso médico sigue pagando sin que DO lo apruebe~~ — ✅ CERRADO (0306 + 0308, pegadas el 2026-08-26)

**Cerrado en dos mitades, y la segunda hizo falta.** La 0306 (otra sesión) hizo
que `fn_planilla_calcular` exigiera `aprobada_at`. Pero `fn_provisiones` no se
enteró, así que un descanso médico sin firmar pagaba S/0 de sueldo **y reservaba
como si se hubiera pagado el mes entero** — S/164,34 por caso, y de ahí sale el
depósito. Lo cerró la **0308**. Prueba 242.

**Dónde:** los laterales de ausencias en `fn_planilla_calcular` filtran
`anulada_at is null` y nunca miran `aprobada_at`. `fn_registrar_ausencia` deja
registrar a la encargada de sede; `fn_aprobar_ausencia` solo a admin/lider —
pero la planilla no espera esa aprobación para pagar.

**Reverificado esta noche:** `grep -c aprobada_at` sobre el cuerpo vivo de
`fn_planilla_calcular` da cero. Sigue exactamente como lo dejó el informe de
agosto (que además ya había medido: hoy, cero soles mal pagados — julio se
congeló antes de que existiera el concepto).

**De paso, un vecino sin lote asignado:** `licencia_con_goce` está marcada en
el catálogo como que paga y requiere aprobación, y `fn_planilla_calcular` no
la paga por ningún lado — el error contrario (alguien deja de cobrar), sin
investigar.

**Propuesta:** ya está diseñada en el plan de agosto — tres líneas dentro del
bloque de feriados (con cuidado: tocar solo dos de las tres rompe el
prorrateo del feriado dentro de una licencia, medido en −S/22.17). Antes de
escribirla: `donde-vive.sh fn_planilla_calcular` y el md5 de producción, igual
que siempre.

### 7 · ~~`guardarDocumento()` muestra "archivado" aunque la segunda mitad haya fallado~~ — ✅ CERRADO por otra sesión (commit `8ace032`, 2026-08-26 11:24)

**Dónde:** `apps/web/app/(admin)/admin/documentacion/page.tsx:642-651`. La
primera llamada a `fn_documento_registrar` (crear el registro) sí chequea
`error`; la segunda (adjuntar el `storage_path` del archivo ya subido al
registro recién creado) no lo chequea, y el flujo sigue hasta mostrar el
aviso de éxito.

**Por qué importa:** un documento puede quedar registrado sin su archivo
adjunto, y la persona que lo subió cree que quedó archivado. Es exactamente
el tipo de silencio que CLAUDE.md señala como el peor error de este sistema,
aplicado a un documento con valor legal (política, movilidad, bono).

**Propuesta:** destructurar `error` de la segunda llamada y, si falla, avisar
en vez de mostrar éxito — mismo patrón que ya usa el primer bloque.

**Cerrado, y mejor de lo propuesto.** Otra sesión lo arregló el mismo día y
encontró que el defecto estaba **tres veces**, no una: «tres guardados que
decían "listo" cuando la segunda mitad había fallado». El aviso que quedó no
dice solo que falló — dice qué quedó a medias y qué hacer: «El registro se
guardó y el archivo subió, pero no se pudo enlazar. El documento queda SIN su
papel: vuelve a subirlo desde su fila».

### 8 · ~~La regla "qué mes de educación falta un comprobante" está escrita 3-5 veces, casi sin prueba~~ — ✅ CERRADO (prueba 226 ampliada, 2026-08-26)

**Dónde:** `supabase/migrations/0290_un_comprobante_por_mes_y_no_uno_por_
asignacion.sql` crea `fn_educacion_papeles` (:328), `fn_educacion_meses_
sin_papel` (:355) y `fn_educacion_por_atender` (:465) — ninguna de las tres
se llama por su nombre desde `supabase/tests/`. `fn_educacion_listar` (:386,
sí probada en el test 226) trae una cuarta copia inline de la misma lógica, y
es esa cuarta copia la que el test termina verificando.

**Por qué importa:** `fn_educacion_por_atender` es el contador que le avisa a
DO qué papeles faltan perseguir. Si alguien corrige una sola de las cinco
copias, el contador del menú puede decir "0 pendientes" mientras la lista
real muestra filas con `meses_sin_papel > 0` — y nadie va detrás del papel
que sustenta un pago ya hecho.

**Cerrado con cuatro comprobaciones nuevas en el test 226**, sobre su mismo
laboratorio. La duplicación NO se tocó —siguen siendo cinco copias— pero ahora
**separarse cuesta rojo**, que era el riesgo real.

Se escribieron comparando **función contra función**, no contra números a mano:
el peligro no es que una dé mal un número, es que dos den números distintos y
nadie se entere. La cuarta es la que importa: `fn_educacion_por_atender()` —el
contador que le avisa a DO qué papeles perseguir— contra
`fn_educacion_listar()`, que es la lista que abre esa misma pantalla.

**Se comprobó que tiene dientes**: rompiendo el contador para que siempre diga
«0 pendientes», la comprobación 14 se pone roja.

**Lo que sigue abierto, y es de otro tamaño:** unificar las cinco copias. Hoy no
duele porque hay quien avise si se separan.

### 9 · ~~Tablas nuevas con datos sensibles, con RLS pero sin ninguna prueba que confirme que protege~~ — ✅ CERRADO (prueba 252, 2026-08-26)

**Dónde:** `contratos_generados` + el bucket "contratos" (0272/0287, sueldos y
PDFs firmados) · `asignaciones_regimen_pension` (0261, régimen de pensión) ·
`educacion_comprobantes` (0290). Las tres tienen policies que restringen a
admin/lider o a la propia persona, y **ningún test cambia de usuario** para
comprobar que alguien sin ese rol quede bloqueado — todos los tests
relacionados corren con una sola sesión admin de principio a fin.

**Por qué importa:** el patrón ya existe en el repo y funciona
(`supabase/tests/198_...` sí cambia de usuario con `set local role
authenticated`). Sin ese segundo usuario en estas tres, un error futuro en
cualquiera de las tres policies no lo detectaría ningún pgTAP — se enteraría
alguien mirando por accidente el sueldo o el contrato de otra persona.

**Propuesta original:** sumar el patrón del test 198 a los tests 223, 214 y 226.

**Cómo se cerró, y en qué se cambió la propuesta.** En vez de repartir las
aserciones por tres archivos, se escribió **una prueba dedicada, la 252**, que
dice el invariante una sola vez y donde agregar una cuarta tabla sensible es
obvio. Repartirlas habría dejado la regla escrita en tres sitios — que es
exactamente la clase de duplicación que este repo paga caro.

Ocho comprobaciones, y no solo las negativas: para cada tabla se comprueba
**también que quien SÍ debe ver, ve**. Una policy que bloquea a todo el mundo
pasaría las negativas y estaría igual de rota.

Lo que se aprendió midiendo, y queda escrito en la prueba:

- **`asignaciones_regimen_pension` no tiene cláusula de «tu propia fila»**: su
  policy dice solo `fn_es_admin_o_lider()`, así que ni la propia persona ve la
  tabla cruda. Se comprueba a propósito, para que si alguien le agrega el «o es
  tuya», la prueba se lo diga.
- La comprobación 1 verifica, como superusuario, que **las tres filas existen**.
  Sin ella, las demás miran `count(*) = 0` y un cero pasa igual si el laboratorio
  no se construyó.

**Se comprobó que tiene dientes**: apagando la RLS de `contratos_generados`, la
comprobación 2 se pone roja. Sin esa vuelta no se sabría si la prueba puede
fallar.

---

**Una corrección de paso.** El informe de agosto decía que `feriados/page.tsx`
"al menos sí confirma" antes de quitar un descanso sustitutorio ya otorgado.
Releído el código esta noche: **no confirma** — `quitar(id)` llama a la RPC en
el primer clic, sin `window.confirm`. El comentario que hay al lado (líneas
714-719) explica por qué debería confirmarse, pero no hay ningún código que lo
haga cumplir. Esto es parte del **P2 "Cinco acciones que devuelven plata... al
primer clic"** del informe de agosto (línea 1079), que también cubre
`quitarJustificacion`/`quitarLevantamiento` en incidencias, horas y
correcciones — las dos pasadas de esta noche redescubrieron ese mismo P2 sin
saber que ya existía.

**Lo que queda fuera de los nueve, y por qué:** cuatro P1 más del informe de
agosto sin reverificar esta noche por tiempo —`fn_dia_incoherente` y
`fn_siguiente_tipo_esperado` no conocen `fecha_jornada` (sella marcas buenas
como "pendiente de revisión" el día después de un cruce de medianoche); el
botón "¿Volviste a entrar?" del terminal puede borrar la salida real de
anoche; el auto-cierre (3 h) llega antes que la ventana de la 0240 y la salida
de madrugada se sigue rechazando; una incidencia de quien marca fuera de su
sede sale sin nombre y no se puede sacar de la lista—, más 29 P2 y 39 P3 que
no se leyeron esta noche. Todo vive en `auditoria/CAYLA_CORP_RPT_202608_
Auditoria.md` y su plan en `auditoria/CAYLA_CORP_OPS_202608_PlanRemediacion.md`.

---

## 2026-08-24 — Un comprobante por cada mes que se paga (0290)

**Aplicada en producción y verificada.** Los 15 comprobantes que había se
mudaron a `educacion_comprobantes` y ninguna asignación perdió el suyo.

**Lo que lo motivó, medido:** de las trece asignaciones vigentes de ese día,
**diez abarcaban dos o tres periodos de planilla con un solo comprobante**. El
pago era correcto —una pensión mensual se repite— pero el sustento no estaba
completo, y no se podía arreglar: la tabla admitía un comprobante y nada más.

Tres decisiones de Felipe:

1. **Cada papel dice qué mes respalda.** Contar no basta: se apagaría el aviso
   subiendo tres veces el recibo de agosto.
2. **El mes es el del PERIODO, no el del calendario.** Un tramo del 29/08 al
   28/09 se paga una vez; pedir dos papeles sería pedir papel de más.
3. **El aviso se ve también en el contador del menú**, no solo al entrar.

Y una que no se pidió pero decide el riesgo: **`comprobante_url` no se borró**.
Pasó a ser un espejo que mantiene un trigger, así que `fn_planilla_calcular` no
se tocó. La regla «sin papel no devenga» sigue viva sin que la planilla se entere
de que ahora hay una tabla detrás.

**Ojo con el contador de Educación:** subió al pegar la migración, y no es que
algo se haya roto — ahora cuenta las asignaciones que ya cobraron un mes sin
papel, que era el caso invisible.

**Pendiente operativo, no de código:** pedirle a DO los comprobantes de los meses
que ya se cobraron. La pantalla dice cuáles son, fila por fila.

---

## 2026-08-24 — Los planes anuales se cargan por tramos

Duolingo y Domestika no son pensiones mensuales: son cargos que se pagan una vez.
Con la vigencia puesta a varios meses, se pagaba cada mes contra un gasto único —
S/810 contra un comprobante de S/499 en el caso de Sandra.

**Se resolvió sin tocar el sistema**, partiendo el comprobante en tramos que
suman el papel exacto: una fila por periodo, con el trozo del gasto que se imputa
a ese mes. Sandra 360 + 139 = 499; Diana 120 + 120 + 34.90 = 274.90. Cada tramo
lleva el mismo comprobante adjunto y una nota que dice de qué plan sale.

**Lo que el sistema sigue sin saber es que un comprobante puede cubrir más de un
mes.** Mientras eso no exista, un plan anual hay que cargarlo a mano así, y nada
avisa si alguien no lo hace.

---

## 2026-08-22 — El techo de educación se reparte, y sigue al rango (0281)

**Decidido por Felipe.** Tres decisiones, y las tres cambian plata:

1. **El segundo comprobante entra por el saldo, no rebota.** El monto pasa a ser
   `min(costo × 75 %, techo − lo que ya usan las asignaciones que SE SOLAPAN)`.
   Antes, con techo de S/180, quien ya cobraba S/150 por su instituto no podía
   registrar el colegio de su hija ni por los S/30 que quedaban: el monto no se
   teclea desde la 0149, así que no había forma de cargar ese papel.
2. **El reparto va por orden de registro**, no a prorrata: la primera conserva su
   monto y la siguiente se queda con el saldo. Un solo criterio, el mismo que
   rige el alta.
3. **El techo sigue al rango, en las dos direcciones.** Al cambiar de rango las
   asignaciones se realinean solas desde el primer periodo no pagado — cerrando
   la vigencia vieja y abriendo una nueva, con rastro en `correcciones_auditoria`.
   La 0132 había dejado ese hueco a propósito («queda por encima del techo nuevo
   hasta que se la toque») y nadie la tocaba nunca.

**Lo que NO se hizo, y es decisión, no olvido:** la política salarial publicada
sigue diciendo «cubre el 75 %… hasta el tope de tu categoría». No es falsa —solo
no menciona el reparto— y publicar una versión nueva obliga a pedir acuse de
recibo a todo el equipo otra vez (0141). Se agrupa con el próximo cambio de
política.

**Pendiente:** pegar la **0281** en producción (`./scripts/dame-el-sql.sh 281`).
Al pegarla no se mueve ningún pago por sí sola: no recorre las filas existentes.
Las que hoy estén por encima de su techo siguen igual hasta que se toque su rango
o se corrija a mano — y eso último, desde la 0281, se puede: el candado dejó de
rechazar también los arreglos hacia abajo.

---

## 2026-08-19 — Auditoría de 22 agentes contra la ley peruana

93 hallazgos. Los cinco escépticos tumbaron **46 por no tener población en
CAYLA**, 9 por decisiones ya tomadas, 3 por no reproducirse, 3 por estar
arreglados. Quedan 47 mecanismos confirmados contra el cuerpo VIVO de las
funciones. El catálogo entero, agrupado por dónde muerde, está en
[`hallazgos-abiertos.md`](hallazgos-abiertos.md#auditoría-del-2026-08-19--22-agentes-contra-la-ley-peruana).

**Lo único que hace falta decidir antes del 28 es esto:** correr
`scripts/sql-manual/a_quien_le_pega.sql` en el SQL Editor. Nueve preguntas, un
solo `select`. Hasta que se corra, esos 47 son mecanismo confirmado con
población DESCONOCIDA — que no es lo mismo que plata perdida, y confundirlos es
exactamente lo que costó cinco falsas alarmas el 2026-08-18.

Cerrado el mismo día:

- **0275** · las vacaciones dejan de pagarse en cero. Quien pasaba el periodo
  entero de vacaciones cobraba S/0.00 por el 0/0 de `hh.pago / dias_marcados`.
  **Aplicada en producción el 2026-08-20**, y comprobada como se comprueban
  estas: el md5 que devolvió el SQL Editor se comparó contra el que da aplicar
  la migración sola en el Postgres local dentro de `BEGIN…ROLLBACK`, en el mismo
  minuto. Coincide, y con la misma longitud — los comentarios llegaron enteros,
  que es lo que se pierde cuando el portapapeles rompe los acentos.
- **`va_a_poder_cerrarse.sql`** conocía solo uno de los dos frenos del cierre:
  daba «✓ TODOS CUADRAN» y `fn_planilla_congelar` abortaba igual por el freno de
  la 0243/0244.
- **La boleta** se contradecía sobre la AFP —«no se descuenta de tu sueldo» en la
  misma hoja que imprime el descuento— y no identificaba al empleador.
- **El RUC y la razón social**, que estaban escritos a mano en ocho documentos,
  se leen de `packages/shared/src/empresa.ts`. Lo que NO se unificó es el
  formato: los ocho escriben el RUC distinto y dos están congelados con firmas
  encima (la política salarial por la 0141, el contrato en `documento_html`).
  `tests/empresa.test.ts` vigila las dos mitades — que no aparezca una novena
  copia, y que ningún documento cambie de forma.

Decidido con Felipe y pendiente de construir: **la sobretasa del 100 % por
trabajar el día de descanso semanal** (art. 3 del D. Leg. 713), que hoy no
existe en el sistema. Se hacen **las dos cosas**: registrar el descanso
sustitutorio cuando lo hubo, y pagar la sobretasa cuando no. Golpea sobre todo a
TRU, que es el régimen de 6 días con descanso rotativo.

**CONSTRUIDA Y EN PRODUCCIÓN: la 0280**, pegada el 2026-08-22 y verificada por
md5 (`0912fcb7…`, 91 394 caracteres, calculado en el mismo minuto). La boleta la
imprime con el día que la dispara, y `chk_foto_cuadra` y `fn_planilla_congelar`
fueron con ella — sin eso el cierre del mes se caía entero, que es lo que la
0201 ya pagó una vez.

Lo que NO hizo falta: registrar el descanso sustitutorio. El art. 3 paga «sin
sustituirlo por otro día en la misma semana», y si se sustituyó ese día libre
CORTA la racha y no hay séptimo día. La racha es la prueba. El feriado sí
necesita actas (0069/0093/0238) porque allí el día compensatorio puede caer
semanas después.

**Y RIGE DESDE AHORA, NO HACIA ATRÁS** (Felipe, 2026-08-20). Se midió lo que
costaría —`cuanto_cuesta_el_descanso_semanal.sql`, S/163.19 del periodo en curso
y S/374.61 del de julio ya pagado— y la decisión es que la política empieza
cuando empieza. **El periodo cerrado no se reabre**, así que esa segunda cifra
no es una deuda: es la medición de por qué conviene construirlo pronto.

**La 0276 también está en producción**, entera y anotada (20/08 21:03). Se
comprobó antes de entregarla y por eso no se entregó: sus tres piezas
—`fn_planilla_calcular`, `fn_provisiones` y la nueva `fn_feriado_devengado`—
devuelven los md5 que produce esa migración, medidos aplicándola sola en local
dentro de `BEGIN…ROLLBACK`.

El susto valió la pena igual: el md5 de `fn_provisiones` no coincidía con el que
la 0276 declara como punto de partida, y el primer impulso fue leerlo como «otra
versión desconocida». Lo que era, medido contra las siete versiones históricas,
es la 0276 **ya aplicada**. Con `migraciones_aplicadas` no habría bastado — es
el registro que el 2026-08-19 dijo que la 0196 estaba puesta mientras el cuerpo
vivo era el de la 0158.

### Tres cosas que se persiguieron el 2026-08-20 y no eran

Se anotan porque las tres son creíbles y las tres cuestan una tarde:

1. **«A veinte personas les bajó el sueldo el 29/07».** Es el rediseño
   remunerativo: la base declarada por rango (0128), compensada con movilidad,
   educación y bono. **Todo el equipo lo aceptó.** Las notas de
   `asignaciones_salario` lo dicen con todas sus letras — se leen antes de
   alarmarse.
2. **«Quien cumple su jornada queda bajo la RMV en meses de 31 días».** No: el
   piso vive en el cálculo. `fn_planilla_calcular` declara
   `greatest(bri.base, piso_essalud)` y ese piso es la RMV entera. Declarar y
   pagar por horas no son lo mismo. Es el quinto defecto de la tabla de
   descartados del anexo, perseguido otra vez.
3. **«Cinco personas marcan mucho menos de 45 h/semana».** Son **turnos
   reducidos**, confirmado por Felipe. El pago por horas es correcto y no se
   reabre.

Pendiente de mirar renderizado, dos minutos: la boleta y el memo.

**Y una pregunta que solo Felipe puede responder: ¿cuál es el domicilio legal?**
Al unificar la identidad de la empresa había dos direcciones distintas en el
código. La que declaran los contratos firmados dice «Urb. San Andrés **V Etapa**,
distrito de Trujillo, provincia de Trujillo, departamento de La Libertad»; la
otra, más corta, no salía de ningún documento y no la usaba nadie. Se tomó la de
los contratos, así que **hoy no hay ningún papel que haya cambiado de texto** —
queda comprobar contra la ficha RUC que esa sea la buena, porque desde ahora la
dice un solo sitio.

---

## 2026-08-25 — El aviso de vacaciones se construyó dos veces, y el duplicado lo rompió

La **0297** creó `fn_vacaciones_por_vencer` desde una rama, con su prueba, su
banda en Ausencias, su entrada en el menú y en «Lo mío», y sus tipos
regenerados. Dos días después la **0299** creó la misma función desde otra rama,
sin comprobar que ya existía.

**No quedó en trabajo perdido.** Las dos tenían todos sus argumentos con valor
por defecto, así que la llamada sin argumentos encajaba en las dos:

    ERROR: function fn_vacaciones_por_vencer() is not unique

Con las dos vivas el aviso NO se mostraba. Es el mismo accidente que la 0278
documentó al agregar un parámetro con `create or replace`: no falla al pegar la
migración, **falla al abrir la pantalla**.

La [`0301`](../supabase/migrations/0301_retirar_la_copia_duplicada_del_aviso_de_vacaciones.sql)
suelta la firma de la 0299. **Está pegada en producción el 2026-08-25** y
confirmada: queda una sola, `p_dias integer, p_as_of date`, md5 `0f4ea1c9…`.

**Sobrevive la de la 0297 y no por antigüedad.** Ve más gente —cada persona sus
propios días, una encargada los de su sede—, devuelve la sede, y sobre todo
tiene una condición que la otra no tenía:

    and ( dias_para_vencer <= p_dias or records_vencidos > 0 )

con este comentario suyo: «quien YA tiene un récord vencido puede tener el
siguiente a un año de distancia, y con solo el filtro de los 60 días desaparecía
de la lista justo la persona más urgente. Se vio en el panel con datos de
prueba, no razonándolo». La otra filtraba solo por la ventana: **a quien más
urge avisarle, no le avisaba**.

**La causa de raíz, y la regla que salió de ahí:** no se corrió
`./scripts/donde-vive.sh` antes de escribir, porque el script se leía como «para
reescribir una función». Ya está en CLAUDE.md que **también se corre antes de
crear**: con varias sesiones a la vez, «esta función no existe» es una
suposición, no un hecho.

**Y lo único que destapó todo esto fue pedir el md5 después de pegar.** Dos
filas donde debía haber una. Sin esa comprobación, el aviso habría quedado roto
en silencio hasta que alguien abriera la pantalla.

---

## 2026-08-25 — Tres arreglos más, y una decisión de la 0254 revertida con la norma en la mano

Tres migraciones pegadas en producción el 2026-08-25, cada una confirmada por
md5 antes y después:

**[`0286`](../supabase/migrations/0286_un_dia_fichado_no_se_paga_tambien_como_ausencia.sql)
· un día fichado no se paga también como ausencia.** Cuatro personas idénticas,
tres con una ausencia registrada: quien fichó estando de vacaciones o con parte
médico cobraba el día DOS veces, S/337,93 por semana solapada. `fn_provisiones`
ya excluía ese día desde la 0135 y la boleta nunca se enteró — era una QUINTA
diferencia entre las dos bases, y la única que salía del banco cada mes.
Hubo que arreglarlo en dos sitios: con la guarda solo en la boleta quedaba un
residuo de S/23,41 que era `fn_feriado_devengado` recalculando por su cuenta.
La boleta gana `dias_solapados`, que avisa aunque ya no cueste plata.

**[`0289`](../supabase/migrations/0289_la_gratificacion_ya_depositada_no_se_paga_dos_veces.sql)
· la gratificación ya depositada no se paga dos veces.** Se deposita el 15 y el
periodo no cierra hasta el 28: quien cesaba en medio la cobraba otra vez entera,
S/1.062,75. Trece días en julio y trece en diciembre. La comprobación pedía que
el periodo estuviera `pagado` Y que hubiera terminado antes del cese, y el día 20
fallan las dos. **La segunda condición no era un descuido** —sin ella un cese de
septiembre daría por cobrada la de diciembre— así que no se quitó: se le cambió
el ancla, de «¿cerró el periodo?» a «¿ya llegó el 15?».

**[`0293`](../supabase/migrations/0293_el_feriado_dentro_de_un_descanso_medico_se_paga.sql)
· el feriado dentro de un descanso médico se paga.** Revierte una decisión de la
0254, que lo excluyó porque «la planilla ya lo paga en su propia línea». Medido,
esa premisa no se sostiene: el feriado es un PRORRATEO, no una línea que pague un
día —quien trabajó el mes entero cobra S/350,26 de feriados y quien faltó una
semana, S/252,24—. No había doble pago; había un día que no pagaba nadie, y solo
a quien estaba enfermo. La norma lo dice al revés en tres artículos: art. 8 del
D. Leg. 713 → art. 4 → art. 3 del D.S. 012-92-TR, que incluye las «enfermedades
debidamente comprobadas» entre los días efectivamente trabajados.

### Lo que se decidió NO tocar, con su medición hecha

**El 1 de mayo sigue prorrateándose.** El art. 8 lo saca de la regla —«salvo el
Día del Trabajo, que se percibirá SIN CONDICIÓN ALGUNA»— así que hoy se paga
corto a quien tuvo un mes flojo: **S/12,50 por persona a jornada completa, una
fecha al año, del orden de S/250 anuales en el equipo**. Decisión de Felipe del
2026-08-25, tomada con la cifra delante. Lo que se elimina el 1 de mayo NO es la
proporción por el tamaño de la jornada —un part-time cobra su propia jornada—
sino la proporción por cuántos días vino ese mes.

**El prorrateo general del feriado tampoco se toca.** Sigue siendo decisión de
Felipe, confirmada en `docs/planilla-anexo-tecnico.md`, y la prueba 229 la
defiende con una aserción propia para que ninguna corrección futura la arrastre.

### La lección de método de estos dos días

**El md5 de llegada se mide DESPUÉS de renumerar.** Pasó con la 0286 el 24, se
documentó, y volvió a pasar con la 0289 el 25 — porque lo escrito decía cómo
reconocer el síntoma («misma longitud, distinto hash») y no cuándo medir. Ya está
en CLAUDE.md como regla.

**Y la duplicación de `fn_feriado_devengado` mordió tres veces**: en la 0276, en
la 0286 y en la 0293. Cada vez el mismo patrón —el arreglo puesto solo en la
boleta deja un residuo de unos pocos soles que no cuadra— y cada vez cuesta una
medición extra encontrarlo. Unificar esas dos copias sigue pendiente.

---

## 2026-08-24 — Tomarse las vacaciones dejó de costar dinero

La [`0283`](../supabase/migrations/0283_las_vacaciones_no_gozadas_se_pagan_al_cesar.sql)
está **pegada en producción el 2026-08-24**: `fn_vacaciones_truncas` pasó de
`9535ed57…` (3 228 chars) a `a005fc69…` (8 117 chars).

**El defecto, medido.** Dos personas idénticas —mismo sueldo, mismo ingreso,
mismo día de cese—. La única diferencia es que una se tomó sus vacaciones:

| | vacaciones que pagaba la hoja |
|---|---|
| Nunca gozó | S/ 812,50 |
| **Gozó sus 15 días cuando la ley manda** | **S/ 0,00** |

La causa era una ventana: la cuenta empezaba en el último aniversario, y los 15
días que se ganan al CERRAR un récord se gozan DESPUÉS del aniversario. Caían
dentro y se restaban del récord nuevo. El mismo descanso se cobraba dos veces, y
solo a quien lo tomó. Por el mismo borde se caían los récords completos sin
gozar: quien llevaba dos años sin vacaciones cobraba el trunco y nada más.

**Por qué la cuenta acumulada no puede pagar doble** —la condición que puso
Felipe antes de aprobarlo—: cada día que la persona se tomó en su vida se resta
UNA vez del total que ganó en su vida; `vacaciones` es una VISTA sobre
`ausencias`, así que un día no puede contarse por dos tablas; y ahora se
descuenta el libro de desembolsos, que esta era la única de las tres truncas en
no mirar.

**Se comprobó el historial antes de escribirlo**, porque el único modo en que
esta cuenta puede equivocarse es que un goce no esté registrado. De las 20
personas activas, las cuatro con un año cumplido se tomaron EXACTAMENTE sus 15
días, y las 16 restantes no han cumplido el año. Nadie tiene saldo pendiente ni
récord vencido: no hizo falta fecha de corte.

**La indemnización del art. 23 se avisa y no se calcula** (decisión de Felipe):
tiene excepciones que el sistema no sabe distinguir. Y lo que de verdad la evita
es avisar ANTES de que el récord venza — pendiente, y es la mejor idea que salió
de esta tanda.

---

## 2026-08-22 — Un bono de S/50 costaba S/318 al cesar, y ya no

La [`0278`](../supabase/migrations/0278_ni_los_descuentos_ni_los_beneficios_inflan_la_liquidacion.sql)
está **pegada en producción el 2026-08-22**, confirmada por sus seis md5.

**El defecto era una línea.** `fn_remuneracion_computable` buscaba los conceptos
variables con `where mp.monto > 0`, y la tabla tiene `CHECK (monto > 0)`: la
condición es siempre verdad. No filtraba nada. Entraban los descuentos —un
adelanto es dinero que la persona DEBE—, la gratificación y la CTS que el propio
sistema deposita.

Y la puerta la abría el sistema solo: hacen falta 3 meses distintos con
movimientos, y el depósito del 15/07 y el del 15/11 ya ponen dos. Medido, sueldo
S/1.950, cese al 30/11:

| | antes | después |
|---|---|---|
| Solo grati + CTS (la correcta) | 1.867,40 | **1.867,40** |
| + un bono de S/50 | 2.185,46 | **1.867,40** |
| + un adelanto de S/500 | 2.257,01 | **1.867,40** |

**Cuatro piezas:** el filtro (solo `tipo='bono'` con categoría nula u «otros»);
la ventana por beneficio (la CTS mira nov-abr, no el semestre de la grati); la
regularidad **por concepto** y no por el saco (art. 16: «siempre que **las** haya
percibido tres meses» — el sujeto es cada remuneración); y el candado, que
RECHAZA el bono que sería el tercer mes del mismo concepto, con salida
autorizada de un solo uso y motivo obligatorio (decisión de Felipe).

**Lo que se cuidó, y es la mitad que nadie pide:** un bono genuinamente regular
SIGUE entrando. Excluirlo sería pagar por debajo del art. 16, que es infracción,
no ahorro. La prueba 215 lo defiende con una aserción propia.

### Tres cosas que solo aparecieron al ejecutarlo

- **`create or replace` con un parámetro nuevo no reemplaza: crea una
  SOBRECARGA.** Convivían la firma de dos argumentos y la de tres, y toda
  llamada existente quedaba ambigua. No falla al aplicar la migración: **falla
  al abrir la hoja de liquidación**. Va con su `drop function`.
- **El aviso de la propia migración gritaba «ATENCIÓN» estando todo bien**,
  porque buscaba en el código una línea que el arreglo cita dentro de un
  comentario. Un aviso que salta cuando todo está bien es peor que no tenerlo.
  Ahora quita los comentarios antes de mirar.
- El `sed` del renumerado (el 0277 lo tenía otra rama) se llevó por delante los
  UUID de la prueba, que llevan «0277» dentro. Cuidado con los reemplazos
  globales sobre archivos con identificadores.

### Lo que la 0278 NO cierra, y va en la dirección contraria

**La hoja de liquidación paga de menos las vacaciones al cesar.** Medido el
2026-08-22 con dos personas idénticas, mismo sueldo, misma antigüedad, cese el
mismo día:

| | vacaciones que paga |
|---|---|
| Nunca gozó | S/812,50 |
| **Gozó sus 15 días cuando la ley manda** | **S/0,00** |

Los días gozados del récord ANTERIOR se restan del récord en curso. Y quien
nunca gozó cobra solo el año en curso: sus récords completos —30 días en el caso
medido— no aparecen en ninguna línea de la hoja.

Va **en contra de la persona**, y cae en el único camino sin campo editable: la
liquidación recalcula, congela y paga. **Sin cifra global verificada**: la que
circuló (S/1.896 sobre una «persona corriente») venía de un laboratorio de un
agente y no se comprobó. Lo que sí está medido es la tabla de arriba.

---

## 2026-08-20 — El feriado entra en la reserva, y una migración que casi revierte un sueldo

La [`0276`](../supabase/migrations/0276_una_sola_base_para_la_reserva.sql) está
**pegada en producción el 2026-08-20**, confirmada por sus tres md5:
`fn_planilla_calcular` `b132c828…` → `2f38e5ce…`, `fn_provisiones` `84aae8bf…` →
`93531851…`, y `fn_feriado_devengado` nueva en `f6bbe9ab…`.

**Qué arregla.** La boleta calculaba las provisiones sobre `pago_base + feriados
+ asignación familiar` y `fn_provisiones` las calculaba **sin el feriado** — la
palabra no aparecía ni una vez en sus 610 líneas. Y esa función es la que
autocompleta el monto del depósito el 15/05, 15/07, 15/11 y 15/12, así que se
depositaba corto: **~S/ 2.400 al año, siempre en contra del equipo**. Ahora el
feriado se calcula en `fn_feriado_devengado` y lo preguntan las dos. De paso
llega a la reserva el factor de la 0111.

**La decisión legal, para no reabrirla.** Las dos mitades del feriado entran en
la base: el día prorrateado (art. 8 del D. Leg. 713, remuneración ordinaria) y
la sobretasa por trabajarlo (art. 9). Sin `if` de regularidad, y medido: las 27
ventanas de pago de 2026 a 2032 tienen feriados en **4 o 5 meses distintos**,
nunca menos de 4, y el umbral del art. 16 del D.S. 001-97-TR son 3. El
calendario peruano no hace fallar ese test.

### Lo que casi sale mal, que es lo que hay que recordar de este día

La primera versión copió el cuerpo de la boleta de la **0269** porque
`donde-vive.sh` decía que esa era la vigente — y **lo era, en esa rama**,
mientras otra sesión ya había fusionado la **0275** a `main` y Felipe la había
pegado. Pegarla habría revertido la 0275 en silencio: **quien pasa el periodo
entero de vacaciones habría vuelto a cobrar S/ 0.00 su mes.** No da error;
devuelve otro número.

No fue descuido de método: se hicieron las dos comprobaciones que este repo
manda, y las dos miran el worktree. `db reset` reconstruyó un esquema entero sin
un solo error, sin la 0275, que no estaba en el árbol. Lo cazó **el md5 de
producción** —90.707 caracteres allá contra 89.527 acá— o sea el último freno de
la cadena, con el trabajo hecho, verificado y commiteado. Lo confirmó la prueba
212, que es de la otra sesión: falló en sus tres aserciones de vacaciones.

Y llevaba la misma trampa enterrada dos veces: `fn_feriado_devengado` copió
también el `horas_vacaciones` de antes del arreglo, mientras el de al lado
—descanso médico— sí tenía su respaldo desde la 0254. Ahora las dos están juntas
y con la misma forma, a propósito.

**De ahí salen las dos defensas nuevas:**
`scripts/hooks/main-tiene-migraciones-que-no-tienes.sh` avisa al empujar cuando
`main` trae migraciones que tu rama no tiene, y **sube el tono si tocan tus
mismas funciones** (probado contra el commit del accidente: detecta la 0275 y el
choque en `fn_planilla_calcular`). Y CLAUDE.md pasa a decir que el md5 de
producción se pide **antes de escribir**, no antes de entregar.

### Lo que la 0276 NO cierra, declarado en su encabezado

1. **El divisor del sueldo** — la boleta divide entre los días del periodo
   (29→28) y las ramas viejas de `fn_provisiones` entre los del mes calendario.
2. **El día de ausencia pagada** — la boleta paga días laborables a tarifa
   promedio; la rama 4 paga días calendario. S/ 178,93 en un mes para quien tuvo
   19 días de vacaciones. Lo único que la 0276 arregla de aquí es el feriado
   duplicado dentro del descanso médico, que rompía ella misma.
3. **El factor de la 0111 en el borde** — por día en la reserva, por último
   tramo en la boleta. Se separan un −6,2 % / +13,1 % si `base_provision` cambia
   a mitad de periodo.
4. **La liquidación por cese usa una TERCERA base**, `fn_remuneracion_computable`
   (0129), a la que el feriado no puede llegar. Para el sueldo fijo cambia el
   signo de la brecha: de S/ −0,04 a S/ +26,52.

### Pendiente medido, para su propia migración

**Un adelanto quincenal le SUBE la liquidación a la persona.**
`fn_remuneracion_computable` suma los `movimientos_planilla` con `monto > 0` sin
filtrar categoría ni tipo, así que la gratificación depositada y **los
descuentos** entran como «variables» en la base de la liquidación siguiente.
Dinero que la persona debe, contado a su favor. Es anterior a todo esto. Felipe
pidió medirlo primero y arreglarlo aparte.

---

## 2026-08-19 — Un archivo suelto revirtió `fn_provisiones`, y el registro no lo vio

La pantalla Provisiones mostraba un «CTS total» que no era la suma de sus dos
ventanas: contaba otra vez la CTS ya depositada al banco por PLAME. En la fila
de Paola Cahuana eran **S/94.17 de más**.

**No tocaba ningún pago**, y eso se verificó antes de alarmar a nadie:
`cts_total` y `gran_total` solo los usa `provisiones/page.tsx`; el camino que
paga (`fn_grati_cts_periodo`) usa `cts_may`/`cts_nov`, que sí descuentan desde
la [`0158`](../supabase/migrations/0158_las_provisiones_descuentan_lo_depositado.sql).
Lo que se ensuciaba era la reserva y su CSV — el número que ve el contador.

### Lo que apareció al pedir el md5 de partida

Producción devolvió `9b6be5fa…` para `fn_provisiones`. **No era la 0196**, que
es la vigente en el repositorio: era, byte por byte, el cuerpo de la 0158 — dos
versiones atrás. Y `migraciones_aplicadas` decía que la 0160 (05/08) y la 0196
(08/08) estaban aplicadas.

Se midió en vez de explicarlo: se aplicó en el Postgres local el cuerpo de
**cada** versión histórica dentro de `BEGIN…ROLLBACK` y se comparó su md5. Solo
la 0158 coincide; ninguna otra se acerca.

Después se midió qué más de la 0196 seguía en pie. Las tres funciones del
cálculo por cese —`fn_grati_trunca_bruta`, `fn_cts_trunca`,
`fn_vacaciones_truncas`— estaban **correctas**, en su versión de la 0196. O sea:
la 0196 corrió entera, y después algo pisó **solo** `fn_provisiones`.

### La causa: `aplicar_0158.sql`, que llevaba la función entera dentro

`scripts/sql-manual/aplicar_0158.sql` contenía `fn_provisiones` con md5
`9b6be5fa…` — exactamente el que se encontró en producción. Pegarlo para rehacer
el libro de desembolsos revertía la función sin un error y sin un aviso, y no
tocaba las de cese, que es justo lo que se observó.

**Es la segunda vez con este mecanismo.** La primera fue `fn_planilla_calcular`
en agosto, y está contada en la cabecera de `dame-el-sql.sh`. Aquel día se
borraron cuatro `aplicar_*.sql` obsoletos; estos dos quedaron. Ya no:
`aplicar_0158.sql` y `aplicar_0160.sql` **se borraron**. Sus migraciones siguen
en `supabase/migrations`, así que no se perdió historia — solo la copia armada.

### Lo que se pegó

La [`0271`](../supabase/migrations/0271_el_total_de_cts_descuenta_lo_mismo_que_sus_ventanas.sql)
hace que `cts_total` reste lo mismo que sus ventanas, y **lleva sus cimientos
dentro** (las tres columnas y `fn_devenga`/`fn_devenga_algo`, idempotentes,
copiadas de la 0196 sin cambiarles un byte). Sin eso, pegar solo la función
sobre una base sin ellas la habría creado sin quejarse y la pantalla habría
reventado **al abrirla, no al pegarla**.

Aplicada y confirmada contra producción el 2026-08-19: las ocho comprobaciones
de md5 en verde. Al aplicarse, producción recibió además lo que la 0160 le hacía
a esta pantalla y no tenía — Catherine Pereyra deja de figurar con ~S/2.841 de
beneficios que no devenga.

### Lo que salió de tirar del hilo, el mismo día

Una auditoría en paralelo de la pantalla y de `fn_provisiones` (tres lentes, cada
hallazgo verificado por refutación) devolvió **nueve defectos confirmados**. Se
arreglaron los de arriba y estos:

- **`fn_provisiones` solo leía DOS de las cinco ventanas del libro.** Una
  gratificación o unas vacaciones pagadas por transferencia se anotaban en
  `desembolsos_beneficios` y no las restaba nadie. Medido: con S/700 anotados en
  `grati_s1`, la provisión no se movía de S/749.97 y seguía diciendo `pagada:
  false`. **Y esto sí llegaba al pago** —`fn_grati_cts_periodo` lee esos campos
  para proponer el bono al cerrar—, a diferencia del defecto de `cts_total`. La
  0158 lo dejó anotado como deuda conocida; la
  [`0273`](../supabase/migrations/0273_el_libro_de_desembolsos_vale_para_los_cinco_beneficios.sql)
  la paga, preguntando con `fn_beneficio_ya_depositado` (la de la 0163) en vez de
  con un `sum` propio.
- **El «Gran total» omitía la bonificación extraordinaria.** Se sumaba en el
  cliente como `grati_total + cts_total + vac`, sin `be_total`. Medido con una
  persona de S/1.500: pantalla S/2.010,12 contra base S/2.095,77. La reserva
  salía **corta**. Ahora la bonificación tiene columna propia y el total se lee
  de `gran_total`.
- **Un importe de exactamente 0 salía del CSV como texto `="0"`.** `SUMA` lo
  ignoraba sin daño, pero `PROMEDIO`, `CONTAR` y el orden numérico saltaban esas
  celdas. Afecta a las cinco pantallas que exportan, incluida la de planilla.
- **El céntimo del redondeo.** `gran_total` redondeaba la suma mientras las
  columnas redondeaban por separado, así que la fila no cuadraba por S/0.01 —
  justo la celda que alguien compara con las de al lado. Ahora el total suma las
  columnas **ya redondeadas**.
- **El hueco de la 0268** queda explicado en `scripts/hooks/huecos-conocidos.txt`:
  número reservado por otra sesión el 18/08 y nunca commiteado.

### Lo que la auditoría encontró y NO se arregló

Cuatro hallazgos confirmados que quedan pendientes, con su medición hecha:

- **Del 16 al 31 de diciembre, «Próximo pago» miente.** Pasado el pago del 15/12,
  el próximo desembolso cae en el año siguiente, pero el campo que la pantalla
  lee (`cts_may`) sigue siendo el de la ventana de ESTE año. Medido: el 20/12
  anuncia «S/325.03 · 15/05» cuando ese monto es de una ventana ya depositada. En
  el caso normal —CTS pagada entera— muestra «S/0.00» para todo el equipo esas
  dos semanas. Son 16 días al año, en pleno cierre de la reserva anual.
- **Sin asignación de salario vigente, la fila entera sale en S/0.00** junto a
  «12.0 días» de vacaciones acumuladas. Se lee igual que alguien a quien no le
  toca nada. Reproducido con tres personas idénticas salvo la fecha de vigencia
  del salario: S/1.686,66 · S/120,63 · S/0,00.
- **En noviembre y diciembre la CTS que se está devengando no aparece.** Las dos
  ventanas del año ya pasaron y la nueva (nov→abr) no tiene celda.
- **`fn_provisiones` ignora `asignaciones_salario.base_provision`,** que
  `fn_planilla_calcular` sí honra. La boleta reserva sobre una base y la
  provisión sobre otra.

### Y esa misma tarde: la tabla dejó de listar a quien no reserva nada

Felipe, mirando la pantalla: las locadoras y la gente en días de prueba no
tenían que estar ahí. La [`0274`](../supabase/migrations/0274_las_provisiones_solo_listan_a_quien_devenga.sql)
las saca. ✅ **Pegada el 2026-08-19**, y vuelta a comprobar contra
`migraciones_aplicadas` el 2026-08-20. El md5 de `fn_provisiones` pasó de
`e057765c…` (el cuerpo de la 0273, verificado ANTES de entregar el SQL) a
`84aae8bf…`, y de **25 personas activas la pantalla pasa a listar 20**.

**Es la vuelta atrás de una decisión que estaba escrita**, con su argumento, en
la prueba 127: «verlo en cero es una respuesta, que falte obliga a preguntarse si
se perdió por error». Lo que la tumbó fue la pantalla real: con media tabla en
cero, el cero dejó de ser una respuesta, y el cero de quien SÍ devenga y aún no
acumuló —alguien que entró esta semana— quedaba indistinguible del de quien no
devengará nunca. La preocupación de entonces se contesta en dos sitios: una línea
en la pantalla que dice a quién lista, y la prueba 211.

**El filtro pregunta por el devengo, no por el tipo de vínculo**, y esa es la
única parte delicada. `tipo_vinculo = 'planilla'` habría sido más corto y habría
borrado a la locadora con la gratificación encendida a mano —el caso que la 0196
existe para poder expresar—, dejando de reservar plata que sí se le debe. Una
fila solo desaparece cuando `fn_devenga_algo` dice que no devenga nada, o sea
cuando sus cinco columnas ya valen cero.

Medido antes de darlo por bueno, en local y dentro de `BEGIN … ROLLBACK`: las
filas que se quedan salieron idénticas campo por campo, la suma de la tabla no se
movió (S/ 2.137,84 antes y después, 16 filas → 13), y las tres que se fueron
valían 0.00 en las cinco columnas.

---

## 2026-08-17 — Disciplina no podía firmar nada, y el descargo previo pasó a ser política

Firmar una amonestación o una suspensión devolvía «Antes de firmar hay que
comunicar los cargos y dar el plazo de descargo (art. 55.2 del RIT)» **sin que
existiera forma de cumplirlo desde ninguna pantalla**. Tres memos parados —
Sasha, Mateo y Paola— con una persona trabajando un día en que debía estar
suspendida.

### La causa: media función sin cablear, seis días en producción

El commit `ae501ca` (11-ago) escribió `comunicarCargos()`, `valorarDescargo()`,
`plazoAbierto()` y `esGradual()` en `admin/disciplina/page.tsx` y **nunca las
llamó desde el JSX**. Su propio mensaje describía la cascada de botones que
nunca llegó a existir. La base empezó a exigir el trámite con la [`0212`](../supabase/migrations/0212_ninguna_sancion_sin_escuchar_antes.sql)
y la pantalla siguió mostrando «Firmar» siempre.

⚠️ **`typecheck` no dice nada de una función que nadie llama.** Cuatro funciones
muertas convivieron seis días con las pruebas en verde. Es el modo de fallo que
este repo no tiene cubierto: no hay pruebas de render, así que una pantalla que
compila puede no hacer nada. Cuando un cambio promete un botón, **hay que abrir
la pantalla y verlo** — se comprobó así, contra el Postgres local, y ahí saltó.

### Lo aplicado en producción hoy

| | |
|---|---|
| [`0266`](../supabase/migrations/0266_una_comunicacion_de_cargos_ya_ocurrida_se_puede_declarar.sql) | Registrar una comunicación de cargos **ya ocurrida** con su fecha real, motivo obligatorio y nombre de quien la declara. No adelanta el plazo: el de esa fecha sigue mandando. |
| [`0267`](../supabase/migrations/0267_el_descargo_previo_pasa_a_ser_una_politica_de_la_empresa.sql) | El descargo previo pasa de estar clavado en el código a `configuracion.disciplina_descargo_previo`. **Aplicada en `false`** por decisión de Gerencia General. |

Los memos: `T-01/0003` (Sasha) y `T-02/0004` (Mateo, suspensión el 18-ago),
firmados y entregados el 17-ago.

### La decisión de la política, y qué se expuso antes de tomarla

Gerencia General decidió firmar sin esperar el plazo, con el descargo recogido
verbalmente. Se expuso por escrito, con fuentes, y se sostuvo:

- **Res. 568-2021-SUNAFIL/TFL** extendió el debido proceso a las sanciones
  distintas del despido — el caso era exactamente una amonestación y una
  suspensión sin plazo de descargo.
- **Res. 810-2022-SUNAFIL/TFL**: sancionar sin plazo de descargos es **acto de
  hostilidad**, infracción muy grave del art. 25.14 del RLGIT. Pequeña empresa,
  tope 2026: 7.65 UIT ≈ **S/ 42,075**.
- El propio RIT (art. 55.2) anuncia que la omisión **invalida** la medida y la
  deja sin contar como antecedente para el inciso h) — el peldaño de un despido
  futuro queda discutible.

Se implementó como política y **no** borrando el candado: la regla sigue
escrita, revertir es `update configuracion set valor = 'true'` sin migración, y
**cada documento firmado así lo dice en su propio expediente**. Con la política
en `true` la función se comporta igual que la [`0228`](../supabase/migrations/0228_no_se_sanciona_con_un_reglamento_que_no_se_entrego.sql).

Lo que **no** cambió: el numeral 60.5 sigue frenando sin constancia del
Reglamento, y los guardas de firmante del art. 54.4 quedan igual. Si la clave de
configuración falta o trae un valor inesperado, **se exige**: una configuración
perdida no puede relajar una garantía en silencio (prueba `205`).

### La suspensión ya elige su día

La pantalla solo dejaba cambiar el **número** de días; la fecha la fijaba el
generador del borrador y no había dónde tocarla — `fn_expediente_set_suspension`
siempre aceptó la fecha, el panel no la exponía. Si la firma se retrasaba, la
sanción caía en días ya trabajados. Es lo que obligó a anular la `T-02/0001` en
julio y volvió a pasar hoy: la de Mateo estaba puesta para el 17, el día que
estaba trabajando. Ahora hay campo de fecha y un aviso en rojo cuando los días
ya empezaron.

### PENDIENTE

- **Paola Cahuana**: su amonestación sigue en borrador porque no consta la
  entrega del Reglamento. Se destraba entregándoselo y registrando la constancia
  en Normas — también vale el cargo en papel escaneado.
- **La comunicación de cargos no se genera sola.** Si algún día la política
  vuelve a `true`, entregarla sigue siendo trabajo a mano. Lo que evitaría el
  papeleo es que el sistema la imprima con los hechos ya medidos.
- **`fn_expediente_declarar_cargos_comunicados` (0266) quedó sin usarse hoy**,
  porque la política la dejó sin caso. Sigue siendo la salida buena si alguna
  vez se vuelve a exigir el plazo y una comunicación ya ocurrió.

### ⚠️ Una sesión paralela borró trabajo sin commitear, mientras se trabajaba en él

Se escribió, probó y verificó una migración `0267` distinta —cerrar el plazo de
un expediente concreto con motivo— y **otra sesión de este mismo worktree la
borró junto con su prueba, y renumeró la siguiente para ocupar su hueco**. No se
perdió nada porque se detectó en el acto, pero el archivo no estaba commiteado y
no había forma de recuperarlo del disco.

Es el riesgo que `CLAUDE.md` ya describe para el índice de git, ahora visto
sobre archivos: **lo que no está commiteado, otra sesión se lo puede llevar**.
La misma sesión reinició la base local dos veces en medio de una verificación.

---

## 2026-08-15 — «Lo mío» deja de ser un marcador, y dos migraciones para que lo sea

La pantalla que ve cada colaboradora pasó de mostrar sus horas a poder usarse:
sus turnos, sus objetivos del mes, sus permisos, lo que le tocaba contra lo que
hizo, y —lo que la cambia— **un botón para decir que un día no cuadra**.

### ⚠️ El aviso de firmas no le llegaba a quien es

`AcusesPendientes` —el banner que pide firmar la política salarial y el RIT— se
pintaba **solo dentro de `AdminNav`**, y el login manda a `/mio` a quien no tiene
panel. O sea que **la integrante, que es exactamente para quien se escribió, no
lo vio nunca.** Su propio comentario dice «una integrante que entra por primera
vez cae en el Dashboard», y eso dejó de ser cierto cuando existió `/mio`.

No es estética: la Ley 30709 obliga a informar la política salarial **y a poder
probarlo**, y el reglamento interno igual. Un acuse que no le llega a su
destinataria no prueba nada. Ya se pinta en `/mio`, lo primero de la pantalla.

### Lo aplicado en producción, con su md5 confirmado

| | |
|---|---|
| **0256** | `fn_faltas` gana la rama `pe.id = fn_persona_actual_id()`. Cada quien ve SUS faltas. Partió de `8887c5d1…` (la 0079) y quedó en **`c6a9ddc9ac8e1e8434c58b19ab71ebda`** |
| **0257** | `revisiones_pedidas` + cuatro funciones: pedir, retirar, atender y leer. Las cuatro con el md5 del repositorio, confirmado |

**Por qué la 0256 importa más de lo que parece:** una integrante se enteraba de
que el sistema le contó una falta cuando ya había una conversación encima — que
es justo cuando el marcaje ya no se puede arreglar. Y buena parte de las faltas
que este sistema detecta **no son faltas**: son días sin turno cargado. La
persona es la única que sabe qué pasó ese día. Dejarla verlo es el canal de
corrección más barato que tiene CAYLA.

Efecto medible el mismo día: un «18 de 23 días que te tocaban» era falso —cuatro
de esos cinco días eran permisos concedidos que `fn_faltas` no le devolvía—, y
con la 0256 el denominador baja a lo que de verdad debía.

### Lo que NO se abrió, y son decisiones

- **El expediente disciplinario.** `exp_select_propia` ya se lo permite, pero esa
  policy **no filtra por estado**: incluiría los BORRADORES. Avisarle a alguien
  de una sanción que nadie decidió entregar es peor que no avisarle de nada. Si
  algún día se abre, va filtrado a `firmado`/`entregado`.
- **El saldo de vacaciones.** Sale de un cálculo que acaba de tener un defecto de
  doble cobro en la trunca. **Lo registrado es un hecho; el saldo es una
  promesa.** Las vacaciones ya registradas sí se ven.
- **Dinero, en ninguna forma.** Se mantiene la decisión del 11-ago. Lo único que
  se añadió es la etiqueta «no remunerado» en un permiso — que es una condición
  que debería haber sabido al pedirlo, no una cifra.

### Un hallazgo que ahorró una migración

**`vacaciones` no es una tabla: es una VISTA** sobre `ausencias` (tipo
`'vacaciones'`, no anuladas) declarada con `security_invoker=true`. La RLS que
manda es la de `ausencias`, y `ausencias_select_propia` ya existía — cada quien
ya podía leer las suyas. Se iba a escribir una policy que no hacía falta.

Y el defecto que eso destapó: **una consulta directa a `ausencias` tiene que
llevar `anulada_at is null`**. La vista lo lleva dentro desde siempre; quien
consulte la tabla y lo olvide le dirá a alguien que su permiso está registrado
cuando ya lo dieron de baja — y es justo en lo que se fiaría para no volver a
presentarlo.

### ⚠️ DOS REGLAS DE MÉTODO, las dos aprendidas hoy y a golpes

**1 · El SQL para pegar NO se transcribe al chat. Nunca.** Se entrega con
`./scripts/dame-el-sql.sh <NNN>` y punto. Hoy, al pasar la 0257 por el chat,
acorté comentarios de cabecera para que cupiera en pantalla — y dos de ellos
vivían **dentro** del cuerpo de una función. Los comentarios dentro de `$$…$$`
**viajan al `prosrc`**: la migración entró, funcionó, y dejó dos md5 de
producción distintos a los del repositorio. Es la misma deriva que el 2026-08-08
dejó 22 funciones sin coincidir. Costó tres rondas cerrarla.

**Y no poner NADA MÁS COPIABLE en el mismo mensaje.** Dos veces seguidas, darle
la migración en el portapapeles y una consulta de verificación en el texto hizo
que copiara la segunda y perdiera la primera: pegó la consulta creyendo pegar la
migración. Para verificar: que vuelva a correr la consulta que ya tiene en el
editor, o mandarla en un mensaje aparte — o dejarla en el portapapeles con
`pbcopy` **cuando ya no haya nada más que pegar**, que fue lo que por fin
funcionó.

**2 · pgTAP corre como `postgres`, que SE SALTA LA RLS.** Una prueba que
consulte una tabla directamente para comprobar una policy no está comprobando
nada: hay que `set local role authenticated` antes y `reset role` después. La
prueba 198 falló por esto y **el fallo era del banco de pruebas, no del código**
— pero podría igual de fácil haber PASADO por el motivo equivocado, que es el
caso peligroso. Está escrito dentro del archivo.

### PENDIENTE de esta tanda

- **Objetivos de septiembre**: la pantalla ya los ofrece cargar con un enlace que
  llega con la persona y el mes puestos, pero **hoy casi nadie tiene checklist**.
  Es lo que Felipe decidió empezar.
- **Que alguien atienda las revisiones.** Salen primero en Incidencias, antes que
  cualquier aviso automático — a propósito: un aviso puede esperar, alguien que
  escribió «ese día sí vine» no. Si se dejan sin responder, la pantalla enseña
  que escribir no sirve, y eso no se recupera.

---

## 2026-08-15 — Desempeño del equipo, y lo que destapó: gente sin horario y turnos sin cargar

`/admin/horas` dejó de llamarse «Horas» y es **Desempeño del equipo**. La ruta no
cambió —hay enlaces vivos y romper una URL para cambiar un nombre no lo vale—
pero la pantalla sí: era una tabla de totales por persona y ahora es una
cuadrícula de **personas × días**, con el desempeño de cada una desplegable
debajo de su fila.

Lo que la motivó, en una frase de Felipe: *«dice Sandra 135 min tarde pero no
puedo ver los días en que pasó esa tardanza»*. Antes, para eso había que ir a
Equipo → persona → ficha → pestaña Desempeño. **Un resumen que no se puede abrir
hasta el día que lo produjo no sirve para conversar con nadie.**

### Las decisiones, para no reabrirlas

- **El día es la unidad, no la persona.** Cada fila termina en una franja de
  cuadritos, uno por día. Los patrones —siempre los lunes, siempre después de un
  descanso— aparecen solos porque los días están alineados en columnas.
- **Todo número lleva su denominador.** «50 h» no es bueno ni malo; «50 de 72 h»
  sí. Lo que le tocaba sale de `horarios_asignados` + `turnos`.
- **Los días con motivo NO entran en el denominador.** Salió midiendo: una
  integrante aparecía con «50.0 / 90.0 h» y cero faltas porque cuatro de sus doce
  días esperados eran ausencias justificadas. Parecía deber cuarenta horas que
  nadie le debe. **Un número que hace quedar mal a quien tenía permiso es el
  falso positivo que este sistema existe para no cometer.**
- **El orden mide gravedad, no cantidad.** Manda la PEOR tardanza del periodo, no
  cuántas: dos de siete minutos no valen lo que una de dos horas y cuarto. Las
  faltas siguen primero.
- **Las dos escrituras van por las RPC de Incidencias** (`fn_levantar_tardanza`,
  `fn_set_justificacion`). No hay una segunda forma de perdonar un día.

⚠️ **REGLA NUEVA: la cascada «qué le tocaba» vive en un solo sitio.**
`apps/web/lib/admin/jornada-esperada.ts` —turno del día → `horario_por_dia` →
`dias_laborables`—, con 26 pruebas en `tests/jornada-esperada.test.ts`. Ya había
una copia parcial y más vieja en `admin/correcciones/page.tsx`
(`calcularEsperado`, solo la hora de entrada); **unificarlas queda pendiente y no
se escribe una tercera.** Es el mismo patrón que produjo 35 copias de una
condición de permiso y 32 del huso horario de Lima.

### ⚠️ LO QUE LA PANTALLA DESTAPÓ, Y SON DATOS, NO CÓDIGO

Ninguna interfaz arregla esto. Son las dos cosas que hay que resolver para que
las cifras de asistencia signifiquen algo:

**1 · Hay gente activa sin horario ni turnos cargados.** En Central, **2 de 3**.
Para ellas el sistema no mide faltas, ni tardanzas, ni horas esperadas: sus horas
suman al total y aportan cero al denominador. El recuadro llegó a decir
«163 h de 90 h que tocaban» —el equipo trabajando el doble de lo debido— porque
el 90 era el horario de una sola. Ya se dice «de 90 h que tocaban a 1 de 3», pero
**eso describe el problema, no lo resuelve**. Quiénes son:

```sql
select s.codigo as sede, p.apellidos || ', ' || p.nombres as quien, p.fecha_ingreso, p.tipo_vinculo from personas p join sedes s on s.id = p.sede_base_id where p.estado = 'activo' and not exists (select 1 from horarios_asignados h where h.persona_id = p.id and h.vigente_desde <= fn_hoy_lima() and (h.vigente_hasta is null or h.vigente_hasta >= fn_hoy_lima())) order by s.codigo, p.apellidos;
```

**2 · Los turnos rotativos no se están cargando, y eso convierte las tardanzas en
ruido.** Los datos de una integrante de AQP en agosto: entró 11:10, 11:02, 16:30,
13:50, 14:15, 14:01, 14:01 y 12:13. El sistema marcó 130 min de salida
anticipada, 174, 49, y 135 de tardanza. **Los cuatro cuadran con un horario base
de 14:00–22:00 y 15 min de tolerancia** — o sea que están bien calculados. Pero
los días que entró 11:02 y 12:13 no son días en que se fue temprano: **son días
en que hizo otro turno, y ese turno no está en `turnos`.**

**Cuando todos los días medidos dan anomalía, lo que está mal no es la persona:
es la referencia.** La pantalla ya lo dice —columna «medido contra», ⚠ en cada
día medido contra el horario base, y un aviso que enlaza a Turnos en la semana de
ese día— pero **no se puede usar una de esas tardanzas en una conversación
disciplinaria hasta que los turnos se carguen.** Los días afectados:

```sql
select s.codigo as sede, p.apellidos || ', ' || p.nombres as quien, j.fecha, to_char(j.entrada_ts at time zone 'America/Lima', 'HH24:MI') as entro, j.minutos_tarde from jornadas j join personas p on p.id = j.persona_id join sedes s on s.id = p.sede_base_id where j.fecha >= '2026-08-01' and j.fecha <= fn_hoy_lima() and coalesce(j.minutos_tarde, 0) > 0 and not exists (select 1 from turnos t where t.persona_id = j.persona_id and t.fecha = j.fecha) order by j.minutos_tarde desc, j.fecha;
```

### PENDIENTE · los objetivos arrancan en septiembre

**Decisión de Felipe el 2026-08-14: empezar a aplicar los objetivos mensuales
desde el próximo mes.** El bloque de objetivos está en el desempeño de cada
persona, de solo lectura, y cuando no hay checklist cargado lo dice y ofrece
cargarlo — una sección ausente no enseña que falta algo. `/admin/objetivos`
aprendió a recibir `?persona=&anio=&mes=` para que el enlace «preparar los de
septiembre» llegue con la persona y el mes ya elegidos.

Hoy casi nadie tiene checklist. Eso es lo esperado, no un defecto.

### Un contador de la ficha que nunca dijo nada

`/admin/personas/[id]` muestra «Salidas anticipadas: **3 de 3 medidos**», y no
puede dar otra cosa: `fn_jornadas_extra` **solo devuelve las filas con minutos >
0**, así que «medidos» y «marcados» son siempre el mismo número. Se ve como una
proporción y es una tautología. **Pendiente de arreglar en la ficha** — la
pantalla nueva no muestra ese denominador falso.

---

## 2026-08-14 — el barrido del pago del 28, y cuatro alarmas que no eran

**El cierre del 28/08 NO está bloqueado.** Comprobado contra producción, no
deducido: las **29 personas cuadran** contra `chk_foto_cuadra`, y el periodo
suma **S/ 15,917.11**.

Salió de una auditoría de 13 agentes en dos fases —nueve recalculando cada
concepto desde la norma sin mirar el código, cuatro intentando refutar lo que
los primeros encontraran—. 53 hallazgos, 45 reproducidos con cifras. Y de ahí,
lo que sobrevivió al contraste con los datos reales cabe en media página.

### Lo que se arregló y ya está en producción

| | |
|---|---|
| **0248** | La foto del pago aprende la retención de 4ta. La 0245 le restó un término al total sin ampliar `chk_foto_cuadra`: el día que se configurara una retención, `fn_planilla_congelar` abortaba y **no se congelaba nadie**. Estaba armado y sin estallar — cero personas la tenían configurada |
| **0244** | Los cuatro defectos de la 0243, que llevaba desde el 14/08 corriendo con ellos. El peor atascaba el cierre con un solo cese a mitad de periodo |
| **0209** | La versión corregida reemplazó al borrador: el cese del mismo día que dejaba a la persona en S/0.00, y el sueldo fijo que cobraba el periodo completo |

⚠️ **La 0248 es la TERCERA vez que pasa lo mismo** — 0127 con movilidad,
educación y pensión; 0201 con el sobretiempo; esta con la retención. El término
del total y la columna de la foto viven en dos sitios y nada obliga a tocarlos
juntos. Por eso la prueba **189** no vigila la retención sino **el patrón**:
falla si aparece cualquier columna `monto_*` fuera del candado, en el `db reset`
y no un 28 por la noche.

### Lo que queda, y son datos, no código

- ~~**Dante Ramal** — cobraría el mes completo por 16 de 31 días~~ — ✅ **no era
  un problema, y la aclaración de Felipe lo invirtió entero.** El sistema decía
  `fecha_ingreso = 13/08` con un tramo de salario que arrancaba el **29/07**, y
  yo propuse corregir el tramo. Estaba al revés: **Dante ya trabajaba desde
  antes; el 13/08 es el día en que Felipe lo dio de alta en el sistema.** El dato
  malo era la fecha de ingreso.

  Con `fecha_ingreso = 2026-07-29` —ya corregida en Equipo— estuvo el periodo
  completo, así que **el mes completo es lo correcto y los ~S/315 no existen**.
  Verificado además: no tiene horario asignado, así que el motor de faltas no le
  cuenta ni un día ausente pese a no marcar nunca. Es `rxh` con `sueldo_fijo`.

  ⚠️ **DECISIÓN DE FELIPE, PARA QUE NADIE LA «ARREGLE» DESPUÉS:** a Dante se le
  pagó por fuera antes de entrar al sistema, y **eso no se carga — se cuenta
  desde ahora**. El sistema es nuevo y no vale la pena complicarlo hacia atrás.
  De `fecha_ingreso` cuelga el reloj de su CTS, su gratificación y sus
  vacaciones: quien mire su devengado dentro de unos meses va a ver una
  antigüedad más corta de la real y va a querer corregirla. **No es un dato mal
  cargado: es una decisión.**

  Y una nota para cuando se revise el vínculo de los locadores con el contador:
  **Dante es locador con monto fijo mensual**, que es exactamente el indicio de
  laboralidad que ya está señalado para Carlos, Catherine y Claudia. Entra en esa
  misma lista; no se quedó fuera por haberse dado de alta después.
- **Kerin Guevara** — ingresó el 12/08 sin **régimen de pensión** (no se le
  retiene nada, y CAYLA es agente de retención) y **sin horario vigente** (no se
  le miden faltas ni tardanzas). Las dos se cargan desde las pantallas.

### ⚠️ UN CABO SUELTO QUE HAY QUE VOLVER A MEDIR EL 28

**Felipe apareció con un descuadre de +S/110.00 —exactamente 11 días × S/10 de
movilidad— en dos consultas consecutivas, y desapareció solo minutos después**
sin que nadie tocara nada conocido. Tiene `cobra_movilidad = false` por la 0166,
y la tarifa general de producción vale **S/10** (en el repositorio vale 0.00).

No hay explicación: `fn_planilla_calcular` aplica `cobra_movilidad` **en los dos
sitios**, el concepto (línea 376) y el total (línea 514). Se verificó leyendo el
cuerpo vivo.

**Instrucción concreta: correr `va_a_poder_cerrarse.sql` el 28, justo antes de
congelar.** Es una sola sentencia y responde en dos segundos. Si el descuadre va
y viene, ese es el único momento en que importa — una vez congelado, la foto se
queda con lo que hubiera.

### Dos scripts nuevos, para volver a usarlos cada mes

| Ruta | Qué responde |
|---|---|
| [`antes_de_cerrar_el_mes.sql`](../scripts/sql-manual/antes_de_cerrar_el_mes.sql) | Once chequeos en una tabla: si existe el periodo, si faltan feriados, jornadas mudas, movilidad excluida, quién no tiene pensión, ausencias pagables en cero, entradas y ceses, salarios y horarios vigentes |
| [`va_a_poder_cerrarse.sql`](../scripts/sql-manual/va_a_poder_cerrarse.sql) | Si el cierre va a poder completarse. **Una sola sentencia que SIEMPRE devuelve una fila**, porque cero filas se lee igual que «todo bien» |

**Ninguno de los dos llama a una función de diagnóstico, y es deliberado.**
`fn_liquidaciones_pendientes`, `fn_contratos_desnaturalizados`,
`fn_dias_por_revisar`, `fn_ausencias_subsidio` y `fn_contratos_por_vencer`
llevan dentro `fn_es_admin_o_lider()`, y en el SQL Editor la sesión es
`postgres`, que no tiene fila en `personas`. **Devuelven cero filas, no un
error.** Van contra las tablas para no poder caer en eso.

### Las cuatro alarmas que no eran, y qué enseñan

Ninguna llegó a aplicarse porque todas se intentaron reproducir antes. Quedan
escritas para no volver a levantarlas:

| Se dijo | La verdad |
|---|---|
| «Diez ausencias se pagarán en S/0.00» | Todas de tipos con `paga = false` —permiso personal, salud sin documento, otro— más unas vacaciones de un locador, que no las cobra desde la 0186. **S/0.00 es su resultado correcto** |
| «Diez jornadas mudas pagarán cero» | Eran todas **del día en curso**: gente trabajando con su jornada abierta. Al volver a correrlo un rato después el número bajaba solo, mientras la gente se iba a casa |
| «La movilidad excluida atasca el cierre» | El código **sí** aplica `cobra_movilidad` en los dos sitios. Reproducido: el cierre pasa |
| «Veinte personas descuadran» | La consulta buscaba `descuento_pension` —el nombre de la COLUMNA— cuando la clave del JSON es **`descuento_afp`**. Restaba cero, y descuadraba todo el que tuviera AFP, en ~10 % |

**El patrón de las cuatro es el mismo: afirmar por la forma en vez de medir.** Y
las cuatro se cazaron igual — intentando reproducirlas. La regla que ya estaba
escrita en este archivo, otra vez: *medir contra la base antes de proponer*.

Y una que vale por sí sola: **la fórmula de un candado no se escribe de memoria,
se copia del sitio donde es verdad.** La de `chk_foto_cuadra` se saca del
`insert` de `fn_planilla_congelar`, que es quien mapea cada clave del JSON a su
columna. Ahí se ve que `descuento_pension` se llena con `descuento_afp`.

---

## 2026-08-14 — la retención de cuarta categoría, y diez locadores donde había tres

### El sistema ya calcula el 8 % de un recibo por honorarios ([`0245`](../supabase/migrations/0245_la_retencion_de_cuarta_deja_de_hacerse_a_mano.sql))

Hasta hoy no existía: la única forma de reflejarla era escribir un movimiento de
tipo `descuento` a mano cada mes, con el 8 % calculado fuera del sistema.

Dos columnas en `personas` —`retencion_4ta` y `constancia_4ta_hasta`—, los dos
parámetros en `parametros_laborales` con su sustento, el cálculo dentro de
`fn_planilla_calcular`, la línea en la boleta, el aviso en la pantalla de
planilla y las dos columnas en el CSV que usa el contador. Se escribe por
`fn_set_retencion_4ta`, que valida el vínculo y audita.

**Las tres puertas, y por qué no alcanzaba un booleano.** El caso que lo pidió
—el recibo del contador externo— es de S/652.17, o sea POR DEBAJO del tope de
S/1,500: CAYLA no estaba obligada a retener. Retiene porque **el prestador lo
marcó «Sí» al emitir**, que es una casilla que decide el emisor y no el pagador,
y la marca porque factura a muchas empresas, se pasa del límite anual de la
suspensión y prefiere adelantar el 8 %.

- `NULL` → no se retiene. Es como nace todo el mundo, y por eso pegar la 0245 no
  movió un céntimo de nadie.
- `automatica` → la regla del art. 74 de la LIR: 8 % solo si el pago del mes
  **supera** el tope. En S/1,500.00 exactos no se retiene; en S/1,500.01 sí.
- `siempre` → 8 % sea cual sea el monto.
- La constancia del F.V. 1609 manda sobre las tres mientras esté vigente. Dura el
  año calendario: cuando vence, el modo vuelve a mandar.

**Y lo que CAYLA paga de más no es la retención.** El honorario cargado es el
BRUTO (652.17): de ahí 600 van a la persona y 52.17 a SUNAT a su nombre. Lo que
la empresa absorbe por haber pactado un neto es el *gross-up* —S/52.17 al mes,
S/626 al año— y ya está dentro de esa cifra. Bajar el honorario para esquivar la
retención pierde más de lo que ahorra: la retención se le acredita a la persona
contra su impuesto anual, el honorario recortado no vuelve.

### Un locador con monto fijo cobraba S/0.00, y la boleta lo llamaba «por horas»

Dos cosas distintas que salieron al configurar el primer caso real:

1. **Quien cobra un monto fijo y no marca nunca sale en S/0.00.** Su pago se
   calcula por horas registradas. La pieza que faltaba no era la retención sino
   `sueldo_fijo`, que **no se puede marcar desde ninguna pantalla** — va por SQL,
   igual que `en_planilla`.
2. **Y entonces la boleta decía «Honorarios por las horas prestadas (0 h) ……
   S/ 652.17».** Los números bien, la etiqueta mal, en un papel que se le entrega
   a alguien externo y que además describe el acuerdo al revés. La
   [`0250`](../supabase/migrations/0250_la_boleta_no_le_dice_por_horas_a_un_monto_fijo.sql)
   hace que `sueldo_fijo` viaje en el JSON para poder distinguirlos. No mueve un
   céntimo.

### ⚠️ Son DIEZ los que cobran por honorarios, y este archivo decía tres

La sección [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado)
nombra a tres, confirmados el 2026-08-07. La consulta devuelve diez. No se sabe
cuántos están activos ni cuántos pasan el tope sin mirar los datos, así que la
lista no va acá — va la consulta que los encuentra sola:

```sql
select p.apellidos || ', ' || p.nombres as quien, p.estado, case when p.sueldo_fijo then 'monto fijo' else 'por horas' end as como_cobra, s.salario_mensual_soles as honorario, t.valor as tope, case when p.estado <> 'activo' then 'cesado — no configurar' when s.salario_mensual_soles is null then 'sin honorario asignado' when p.sueldo_fijo and s.salario_mensual_soles > t.valor then 'PASA EL TOPE todos los meses' when p.sueldo_fijo then 'no llega al tope' else 'varia mes a mes: Automatica' end as que_hacer from personas p left join lateral (select a.salario_mensual_soles from asignaciones_salario a where a.persona_id = p.id and a.vigente_desde <= fn_hoy_lima() and (a.vigente_hasta is null or a.vigente_hasta >= fn_hoy_lima()) order by a.vigente_desde desc limit 1) s on true cross join lateral (select pl.valor from parametros_laborales pl where pl.clave = 'retencion_4ta_tope' and pl.vigente_desde <= fn_hoy_lima() and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima()) order by pl.vigente_desde desc limit 1) t where p.tipo_vinculo = 'rxh' order by p.estado, p.apellidos;
```

**PENDIENTE · decidido el 2026-08-14: no se configura a nadie más por ahora.**
Solo está puesto el contador externo (`siempre`). El resto queda en NULL y la
pantalla de planilla marca en ámbar a quien pase el tope sin configurar — que es
lo que va a poner los nombres reales sobre la mesa. **Lo que hay que preguntarle
al contador antes de tocar a nadie: quiénes tienen constancia de suspensión
vigente.** Con S/1,800 al mes nadie llega al límite 2026 de S/48,125 anuales, así
que la mayoría calificaría — y con la constancia cargada el sistema deja de
retener solo, sin que nadie pierda plata.

### El agujero que dejó la 0245, cerrado el mismo día por otra sesión ([`0248`](../supabase/migrations/0248_la_foto_del_pago_aprende_la_retencion_de_cuarta.sql))

La 0245 le restó un término nuevo al total y no amplió `chk_foto_cuadra`, que
exige que el total sea la suma exacta de once columnas conocidas. **En cuanto
alguien tuviera retención configurada, «Marcar como PAGADO» habría fallado para
las treinta personas del periodo**, no solo para el locador retenido: el cierre
del mes se atasca entero. Estuvo abierto media hora y el periodo sigue
provisional, así que no llegó a morder. Vale como recordatorio de que una prueba
del cálculo no es una prueba del cierre.

---

## 2026-08-14 — una marca que la base rechazaba, y las que quedaron presas

### El aviso «2 sin registrar» del terminal tenía razón, y no era grave

Salió mirando el terminal: un aviso rojo que aparecía «con frecuencia». Lo pinta
el contador de marcas **apartadas** — las que el servidor rechazó seis veces y
la cola dejó de reintentar, guardadas en el IndexedDB de ese navegador.

**Las dos eran de Felipe, del 13-ago a las 22:02 y 22:22, las dos
`salida_final`.** La salida entró bien a las 22:35:42 y la jornada quedó cerrada
en 9.81 h, así que **no se perdió nada y no hubo efecto en planilla**. Y de paso
quedó comprobada la fórmula contra producción: 12-ago 11.32 − 1.23 = 10.10 ✅ y
13-ago 13.06 − 3.25 = 9.81 ✅.

**Por qué fue negativo a las 22:02 no se puede reconstruir, y no hace falta
intentarlo otra vez:** tres marcas de esos dos días son `admin_correccion`,
puestas después. El estado que lo produjo ya no existe — con los datos de hoy esa
misma salida daría +9.25 h. Casi seguro fue un estado transitorio de las pruebas
de la 0240 esa noche.

### Lo que sí era un defecto: el CHECK tumbaba el marcaje, no la jornada ([`0249`](../supabase/migrations/0249_una_salida_real_siempre_se_puede_registrar.sql))

`chk_horas_no_negativas` (0095) frenaba el `insert` en `jornadas` — bien —, pero
ese insert cuelga del trigger de `marcajes`, así que la excepción subía y
**reventaba el insert del marcaje**. El efecto real no era «esta jornada no se
guarda», era **«esta persona no puede marcar su salida»**: el terminal se la
seguía ofreciendo toda la noche y cada intento acababa apartado. Basta una
corrección con la hora mal tecleada para llegar ahí.

Ahora el negativo se guarda como `null` —«no se sabe cuánto», no «trabajó
cero»— y el día queda sellado en `pendiente_revision`. **El sello no es un
extra:** la planilla lee `coalesce(horas_trabajadas, 0)`, así que sin él el
arreglo habría cambiado una marca perdida a gritos por un descuento en silencio.
El CHECK no se toca.

**⚠️ Y el md5 de partida de esa función NO SE TOMÓ.** Se pegó antes de pedirlo a
producción, y `create or replace` ya había reescrito el cuerpo cuando se fue a
buscar. El de llegada (`c50fa2ed…`, idéntico al local) **no lo sustituye**: sale
igual partas de donde partas, así que no prueba de qué versión se partió. Lo que
sostiene que producción estaba en la 0240 es indicio, no garantía — el error que
rechazaba las salidas era exactamente su comportamiento. La cabecera de la
migración lo dice con todas sus letras.

### PENDIENTE · una marca apartada no la puede ver nadie

Esto sigue abierto y es la mitad que falta:

- **El aviso no se apaga nunca.** Nada borra ni recupera una apartada. Las dos
  del 13-ago van a seguir contando en ese Safari para siempre. Un aviso
  permanente en la pantalla que mira todo el equipo deja de leerse en tres días.
- **Dice «avisa a tu encargada» y la encargada no tiene dónde mirar.**
  `obtenerDescartadas()` solo se usa para contar; no hay pantalla que diga de
  quién es la marca, de qué hora ni qué error dio.
- **Viven en un solo navegador.** Desde el panel no se ven. El día que esto le
  pase a alguien en una sede, nadie se entera hasta que alguien mire la Mac mini.

La 0249 impide que el caso se repita por esta causa; no recoge las que ya
cayeron, ni las que caigan por otra.

### El cierre del 28 estaba bloqueado, y por una línea ([`0252`](../supabase/migrations/0252_el_cierre_deja_de_caerse_por_quien_no_cobra_movilidad.sql))

El término de movilidad del `total` no aplicaba `cobra_movilidad`; el concepto
`monto_movilidad` sí, desde la 0166. La boleta imprimía S/0.00 y el pago la
cobraba igual. Medido: **descuadre de 16.00** con tarifa de S/8 y dos días.

Y no era «una boleta descuadrada». `fn_planilla_congelar` inserta las ~30 filas
en UNA sentencia, así que la que rebota tumba la sentencia entera: **una persona
bastaba para que el 28 no cerrara para nadie**, con un error de CHECK que no la
nombra. Aplicada y confirmada en producción.

Es el tercer caso idéntico en una semana —0242 asignación familiar, 0245
retención de cuarta, 0252 movilidad— y el patrón ya no admite duda: **un
concepto vive en DOS sitios del JSON, el suyo y el término del `total`, y tocar
uno solo deja la boleta diciendo una cosa y el pago haciendo otra.** Antes de
tocar cualquier concepto, buscar sus dos apariciones.

### El descanso médico se pagaba en cero ([`0254`](../supabase/migrations/0254_el_descanso_medico_deja_de_pagarse_en_cero.sql))

**`fn_planilla_calcular` no leía la tabla `ausencias`.** Ni una vez. Las
vacaciones que sí se pagan (0177) salen de una tabla distinta, `vacaciones`. De
los cuatro tipos que `tipos_ausencia` declara pagables, la planilla pagaba uno.

La 0254 conecta **solo `descanso_medico`**, con el tope de 20 días del RIT
art. 31 f). Tres decisiones que se rompen fácil y ahora tienen prueba (195):

- el **tope** se cuenta en días CALENDARIO (así los cuenta EsSalud) y lo que se
  **paga** son días LABORABLES (pagar un domingo sería pagar de más);
- un día vale el promedio de lo pagado por día trabajado, **con respaldo**: sin
  días marcados el promedio sería 0/0 y quien pasó el mes entero enfermo cobraría
  cero — el mismo defecto con otra cara y en el caso más grave;
- **un día que ya paga por otra vía no se paga dos veces**. Salió solo: el
  descanso empezaba en Fiestas Patrias.

Va DENTRO de `pago_base`, como las vacaciones, y por eso NO toca
`chk_foto_cuadra` ni `fn_planilla_congelar`.

**`licencia_con_goce` sigue pagando cero, y es decisión** (va por
`movimientos_planilla`, la 0247 lo dice en su cabecera). **La maternidad ya no:**
la conectó la **0262** — escrita y probada el 2026-08-15, **aplicada en
producción el 2026-08-17**. La
prueba 187 fija por escrito que las dos reglas son distintas y no se pueden
igualar: el descanso médico cuenta días laborables porque es sueldo, la
maternidad cuenta días calendario porque es subsidio.

### Le vaciaron el horario por estar enferma, y eso le anuló el pago de la baja

**RESUELTO el 2026-08-14** con
[`restituir_horario_de_chiara.sql`](../scripts/sql-manual/restituir_horario_de_chiara.sql).
Aplicado y comprobado: su descanso médico pasó de **1 día pagado a 4** (~S/30 →
~S/122). Hay respaldo en `respaldo_horarios_chiara_20260814`.

El círculo, que es lo que hay que recordar: se enfermó, **le vaciaron el horario
mientras estaba de baja** (45 h/semana → 28.5 el 26/07 → 6 h, solo sábado, el
27/07), y `fn_planilla_calcular` mira ese horario para saber qué días le tocaba
trabajar. Respondía «solo el sábado». **La ausencia provocó el cambio de horario
y el cambio de horario anuló el pago de la ausencia.**

⚠️ **REGLA: una baja se registra como AUSENCIA, nunca tocando el horario.**
Vaciarlo hace tres cosas a la vez y ninguna se ve — le quita el pago de la baja,
apaga sus faltas y apaga sus tardanzas.

Dos cosas medidas que no son evidentes:

- **La corrección empieza el 29 aunque el vaciado empiece el 26.** Los días 26,
  27 y 28 de julio no tienen ausencia que los justifique y caen en el periodo
  ANTERIOR: devolverle el horario desde el 26 le abriría tres faltas dentro de un
  periodo cerrado.
- **Cerrar un tramo no lo saca del cálculo.** El horario se elige con
  `vigente_desde <= el_dia order by vigente_desde desc limit 1`, e **ignora
  `vigente_hasta`**. Hay que cambiar el contenido del tramo, no cerrarlo. Quien
  lo cierre creyendo que basta va a dar por hecha una corrección que no ocurrió.

**El barrido encontró un segundo caso** —Melany Enrriquez, de 35 h a 6 durante un
permiso personal de un mes— que **no cuesta dinero**, porque el permiso personal
no paga en ningún caso, pero confirma que el hábito no es de una sola persona. La
consulta que los encuentra está en el commit del script.

**PENDIENTE, decidido y sin escribir:** que un día de baja valga la **jornada
pactada** (7.5 h para Chiara, de sus propios datos: 45 h / 6 días) en vez del
promedio de lo que alcanzó a marcar enferma. La llevaría de ~S/122 a ~S/176 y
aplicaría a todos. Y una columna `motivo` en `horarios_asignados`, que hoy no
tiene dónde decir por qué existe un tramo. md5 de partida de
`fn_planilla_calcular` el 14-ago: `19eb593a757e0b7480b6a1dc99d7f8c9`.

### PENDIENTE · Chiara: seis días más que dependen de un papel, no del código

Su `descanso_medico` del 29/07→03/08 (dengue, **con certificado**) ya lo paga la
0254: cuatro días, ~S/122.

Lo que queda es **`salud` 04/08→09/08, vigente y SIN documento**. El sistema paga
cero y **eso es correcto** — no hay defecto que arreglar. Pero el bloque anulado
que ocupaba esas fechas decía «en reposo médico» y el certificado del dengue
termina el 03/08, justo el día antes. **Falta mirar hasta qué fecha llega el
certificado ya subido**: si cubre hasta el 09, la ausencia está mal clasificada y
son otros ~S/122 suyos; si solo llega al 03, se queda como está y no se vuelve a
levantar.

### Dos avisos del cierre que gritaban por lo normal

El chequeo devolvió `💸 14 día(s) que pagarán CERO` un jueves a las tres de la
tarde: **eran trece personas en su puesto**. Contaba las jornadas abiertas de
HOY. Se comprobó de la forma más elocuente — al recorrerlo un rato después el
número había bajado a 10 solo, mientras la gente se iba a casa. Ninguna era de
un día pasado.

Y el de movilidad se disparaba con solo existir alguien con
`cobra_movilidad = false`: con la 0252 puesta esa persona sigue existiendo y ya
no hay riesgo, así que **el 🚫 habría quedado encendido para siempre**. Ahora
mide el defecto —que el filtro aparezca dos veces en la función— y no su proxy.

**La regla que sale de las dos:** un semáforo que no se apaga nunca no es un
semáforo, y un aviso que grita por lo normal se desactiva a la semana. Las
exclusiones se aplican ANTES de contar.

---

## 2026-08-13 — el expediente de Mateo, y la 0213 que ya no se puede pegar

**LO QUE TENÍA FECHA, Y YA PASÓ.** Hubo una imputación de cargos entregada y
abierta (T-03/0001-2026-CAYLA, entregada el 10-ago), con descargo venciendo el
domingo 16 y consulta al laboralista pedida para el lunes 17.

✅ **Las dos preguntas están resueltas y no hay que volver a enviarlas.** Las
contestan dos migraciones, y ahí es donde vive el razonamiento completo:

- el escalón saltado → [`0246`](../supabase/migrations/0246_una_imputacion_prematura_no_tapa_el_escalon_que_falta.sql)
- el descargo previo del art. 19.3 → [`0267`](../supabase/migrations/0267_el_descargo_previo_pasa_a_ser_una_politica_de_la_empresa.sql)

Lo que queda vivo de esta sección es el relato de POR QUÉ pasó, que es lo que
impide repetirlo. El expediente en sí ya no tiene plazo corriendo.

Se emitió **saltándose el escalón d) del art. 19.2 del RIT** — la segunda
suspensión. El defecto era del generador, que tenía tres peldaños en vez de
cuatro; lo corrigió la 0232 y ya está en producción, pero el papel entregado
salió con la versión anterior.

Y leyendo el Reglamento apareció algo mayor: el **art. 19.3** exige dos días
hábiles de descargo **antes** de imponer la medida, con el documento retenido en
borrador — y advierte que su omisión «invalida la medida, que en tal caso no se
computa como antecedente ni sirve de peldaño». Si el orden importa, no afecta
solo al último escalón.

Las dos preguntas están escritas para enviarse en
[`disciplina-tardanzas-faltas/10-consulta-al-laboralista.md`](disciplina-tardanzas-faltas/10-consulta-al-laboralista.md),
y lo que hay que mirar cuando llegue el descargo, en el
[`09`](disciplina-tardanzas-faltas/09-evaluar-un-descargo.md).

**Lo investigado, para no repetirlo:** la ley (art. 25 h) usa el plural
«amonestaciones escritas y suspensiones» pero **no fija un número**. Lo que
obliga a dos es el RIT propio, que es más estricto a propósito — y el empleador
queda obligado por el reglamento que aprobó.

**⚠️ LA 0213 NO SE PUEDE PEGAR, NUNCA MÁS.** Comprobado ejecutándola: su
`fn_tardanza_escalon` devuelve cinco columnas y la viva devuelve seis, así que
Postgres aborta con «cannot change return type of existing function» y no entra
nada. Su mitad útil —`fn_expediente_generar_falta`— entró por la **0237**. El
número 213 sigue sin anotar en `migraciones_aplicadas` **a propósito**: no se
aplicó y el registro tiene que seguir diciéndolo.

**El reloj de las Mac mini ya no es un punto ciego** (0230). Medido en
producción: **4 segundos** de desfase máximo en siete días, latencia de red
incluida. El umbral de aviso está en 120 s, treinta veces por encima. Es seguro,
no reparación.

**Y una regla de método que costó tres errores en una sola sesión:** grepear una
cadena en el cuerpo de una función NO mide la regla. `suspension_previa_dias`
vive en el `returns table(...)`, que no forma parte de `prosrc`; `sueldo_fijo` se
comprueba un nivel más abajo, en `fn_expediente_crear_borrador`; y
`fn_auto_cierre` mira el periodo pagado a través de un helper. Las tres veces la
respuesta correcta salió de preguntarle a la base qué hace —`pg_get_function_result`,
llamar la función, reproducir el caso— y no de buscar un texto.

### El panel ya puede volver a invitar a quien nunca entró

`/admin/cuentas` daba por resuelta a una persona en cuanto GoTrue aceptaba el
envío: `invitar` enlaza el `auth_user_id` ahí mismo, y con eso desaparecía de la
lista de invitables **aunque el correo se hubiera perdido en spam y ella no
hubiera hecho nada**. No había forma de reenviarle nada desde la pantalla.

Ahora hay una sección **«Volver a invitar — todavía no han entrado»**, con envío
de a una o en tanda. Quién sale ahí se lee de `auth.users.last_sign_in_at`: en
null significa exactamente «no abrió el correo», porque aceptar la invitación
**es** iniciar sesión — el enlace la deja adentro para que ponga su clave.

**Y son dos correos distintos, medido contra el GoTrue local:**

| A quién | Qué se le manda | Por qué |
|---|---|---|
| Invitada que no aceptó (sin confirmar) | la invitación otra vez | GoTrue reinvita sin problema: mismo usuario, `invited_at` renovado |
| Cuenta creada a mano (confirmada) | el enlace de «recuperar acceso» | la invitación responde **422 `email_exists`**; ese camino está cerrado |

La tanda va con una pausa entre correos y **se corta sola** al llegar al tope por
hora del proyecto, diciendo quiénes quedaron pendientes. Mandarlos todos de golpe
no llega antes y convierte un tope en veinte errores.

⚠️ **Lo que hay que comprobar en el panel de Supabase antes de disparar:** que
`https://cayla-dynamic.vercel.app/**` esté en *Authentication → URL
Configuration → Redirect URLs*. Si no está, el enlace **no falla** — cae en el
Site URL, o sea en la raíz, y la persona termina en el login sin clave y sin
nada que le diga qué hacer. Se lee igual que un correo que no funcionó. En local
pasaba exactamente eso hasta que se agregó a `additional_redirect_urls` en
`supabase/config.toml`.

*(Y un aviso para quien corra las pruebas: `scripts/seed-dev.mjs` deja
`100_una_tienda_no_es_una_oficina` fallando en sus pruebas 8 y 9. Con
`npx supabase db reset` antes, las 953 pasan.)*


---

## 2026-08-11 — esta base tiene dos sistemas adentro, y el historial ya lo dice

### El ERP de tiendas vive acá, en el schema `retail` ([`0216`](../supabase/migrations/0216_el_tipo_de_cada_sede_que_retail_necesita.sql)–[`0227`](../supabase/migrations/0227_las_once_de_retail_entran_al_registro.sql))

El 2026-07-23 el ERP de tiendas (repositorio `cayla-retail`,
`cayla-retail.vercel.app`) se mudó a **esta** base, en su propio schema, para
dejar de tener las sedes y las personas duplicadas en dos proyectos de Supabase.
La mudanza funcionó y está en uso. Lo que no se hizo fue registrarla acá: los
once scripts vivían solo en el otro repositorio, y este historial —que es el que
describe esta base— no sabía que el cajón existía.

Eso se cerró hoy. Los once archivos entraron como 0216-0226 con su procedencia en
la cabecera, y la 0227 los anota, con el mismo criterio de la
[`0146`](../supabase/migrations/0146_las_tres_migraciones_que_no_se_anotaron.sql):
a una migración ya aplicada no se le cambia el cuerpo. Verificado contra el
Postgres local, dentro de `begin … rollback`: las doce corren en orden sobre una
base que solo tiene dynamic y levantan el schema `retail` entero desde cero, y
las dos consultas de la prueba `122_toda_migracion_deja_su_rastro` devuelven cero
filas.

**Por qué importaba:** hasta hoy, reconstruir esta base desde
`supabase/migrations` daba asistencia y planilla completas y **ningún ERP de
tiendas**. Sin error y sin alarma.

### Lo que dynamic no puede cambiar sin romper el ERP de tiendas

Retail no copia la identidad: la lee de acá. Sus vistas y sus candados cuelgan de
**cuatro cosas de `public`**, y hoy nada avisa si alguna se mueve:

| Lo que retail usa | Dónde lo usa |
|---|---|
| `public.fn_rol_actual()` | los 4 candados de `retail` — toda su RLS cuelga de ahí |
| `public.fn_sede_actual_persona()` | `retail.mi_sede()`, `retail.puede_operar_sede()` |
| `public.sedes` (`id`, `codigo`, `nombre`, `activa`) | la vista `retail.sedes` |
| `public.personas` (`auth_user_id`, `nombres`, `apellidos`, `sede_base_id`, `rol`, `email`) | la vista `retail.personas` |

Renombrar cualquiera de ellas, o cambiarle una columna, deja el ERP de tiendas
respondiendo errores de permisos **en todas sus pantallas a la vez**, y el
síntoma no dice por qué. No es hipotético: es el precio declarado de la
unificación, y está anotado como pendiente en el backlog de `cayla-retail` (una
prueba de humo que mida el contrato). Mientras no exista, esta tabla es la única
defensa.

También: el schema `retail` tiene que estar en **Settings → API → Exposed
schemas**. Es configuración del proyecto, no SQL — ninguna migración de este
historial puede restaurarla.

---

## 2026-08-10 — un terminal sin dueño, y un diseño de plata que se cayó al medirlo

### El terminal ya no puede quedarse sin dueño ([`0202`](../supabase/migrations/0202_un_terminal_activo_sin_dueno_deja_de_poder_existir.sql))

El guard que impide que una sesión se haga pasar por un terminal son **tres
condiciones unidas por AND** dentro de `fn_registrar_marcaje`. Con
`terminales.auth_user_id` en null la segunda es falsa, el AND entero es falso y
**no se lanza nada**: cualquier sesión con login podía registrar marcas a nombre
de otra persona, en cualquier sede, y la planilla las paga. Medido:
`anon` no puede ejecutar la función, `authenticated` sí — o sea que no hacía
falta ser admin ni encargada.

**El esquema fabricaba ese estado por su cuenta, y por dos caminos:**

- `activo` tiene **default `true`**, así que el insert natural —
  `insert into terminales (sede_id, nombre_dispositivo)` — nacía activo y sin
  dueño. El camino cómodo era el peligroso.
- La FK es **`ON DELETE SET NULL`**. Borrar en Auth la cuenta de un terminal no
  lo desactivaba: le ponía el dueño en null y lo dejaba activo. La puerta se
  abría sola, sin que nadie tocara nada. Esto no estaba en el catálogo.

El candado va en la TABLA, no en la función — la lección de la 0180. Y cierra el
hueco entero: cuando la función llega al guard, la fila ya se buscó
`where id = p_terminal_id and activo`, así que con el CHECK `auth_user_id` no
puede ser null ahí. **Aplicada y confirmada**; los tres terminales de producción
tenían dueño, así que esto no tapó un agujero abierto: **impide el próximo, que
es el terminal de Central el día que se cargue.**

**NO se reescribió `fn_registrar_marcaje`** para dejar el guard como
`is distinct from`, que es la forma correcta por doctrina. Son 129 líneas y es la
única puerta de escritura del sistema; el 08-08 se vio que 22 funciones de
producción no coincidían con el repositorio. Queda pendiente, y va después de
pedir el cuerpo de producción.

⚠️ **Y dejó una lección de método:** un CHECK nuevo **rompe los montajes de
cualquier prueba que fabrique el estado que prohíbe**. Rompió tres (110, 147,
149) y CI salió en rojo. El hook de pre-push corre `typecheck` y las pruebas de
interfaz, **no las pgTAP** — esas solo corren en CI. Antes de empujar un CHECK,
un `grep` de treinta segundos por `supabase/tests`.

### Dos hallazgos del catálogo son FALSOS desde la 0138

`hallazgos-abiertos.md` lista **C12·A16** (`fn_registrar_marcaje` sin candado de
periodo pagado) y **A3** (`fn_auto_cierre` reescribe periodos pagados) como los
dos más graves que quedan vivos. **Medidos contra el esquema de hoy, los dos son
falsos**, y el daño estaba tapado una capa más abajo:

- `fn_recalcular_jornada` **sí** lleva el candado desde la 0138, y se **sale en
  silencio en vez de lanzar**, a propósito: lanzar abortaría el INSERT y el
  terminal acabaría descartando una marca REAL tras seis reintentos.
- `fn_auto_cierre` solo escribe en `marcajes` y `alertas` — nunca en `jornadas`
  directo—, así que pasa por el mismo trigger y queda igual de tapado.

Lo que sí quedaba era el residuo: la marca entraba y la jornada no se
recalculaba, **sin que nadie se enterara**. Eso lo cerró la
[`0207`](../supabase/migrations/0207_una_marca_que_cae_en_un_periodo_pagado_deja_de_entrar_muda.sql).

**Falta tacharlos en `hallazgos-abiertos.md`**, y con ellos otras dos entradas
que también envejecieron: dice que no existen las pruebas 84 y 85 (existen, de
otros temas) y que «los montos pagados no se congelan en ninguna tabla» (la foto
del pago existe desde la 0096). El propio archivo avisa de por qué importa: un
catálogo con entradas mentirosas hace desconfiar de las que sí siguen vivas.

### El borrador de un memo dejó de imprimirse firmado por Gerencia General

`firmante` y `cargoFirmante` arrancaban en la constante `EMPRESA` y solo se
reemplazaban dentro de `if (doc.firmante_id)`, que en un borrador es null por
definición. El papel salía diciendo **«De: Alvarez Pereyra Felipe Miguel ·
Gerencia General»** en un documento que no había firmado nadie. Y el aviso de
borrador llevaba `no-print`: se veía en pantalla y **desaparecía justo en el
papel**.

Ahora arrancan en null y sin firmante se imprime «Pendiente de firma»; el aviso
sí se imprime y dice que no tiene validez como documento entregado. **En vista
previa, pendiente de mirar y subir a producción.**

Lo que el catálogo tenía mal: cuando el memo SÍ está firmado pero su ficha no se
puede leer —una encargada imprimiendo un memo suyo suscrito por gerencia, flujo
legítimo y a propósito— caer al representante legal no es inventar nada. Ese
caso avisa en pantalla, no en el papel.

### La 0209 está escrita y SIN TERMINAR — y su primer diseño se descartó midiéndolo

El defecto es real y está reproducido dos veces: `fn_cesar_persona` cierra los
tramos de salario y horario, `fn_reactivar_persona` no los devuelve, y quien se
reactiva queda **activa, marcando, cobrando S/0.00** (S/2,254.64 contra S/0.00
con jornadas idénticas) e **invisible para el motor de faltas** (5 contra 0).

**El primer diseño era simétrico y habría metido un defecto peor que el que
arregla.** Reabrir el tramo viejo con `vigente_hasta = null` no lo deja vigente
«desde que volvió»: lo deja vigente **desde su `vigente_desde` hasta el
infinito**, cubriendo hacia atrás todo el hueco. Medido en `BEGIN … ROLLBACK`:

| Qué | Cuánto |
|---|---|
| Reescribe planillas YA PAGADAS | S/2,420.63 en un periodo · **S/3,390.00** en tres |
| Sobrepaga el periodo EN CURSO | S/1,130.00 del mes entero, sin trabajar un día |
| Devenga grati, CTS y vacaciones del hueco | **+S/719.52**, y `fn_grati_cts_periodo` lo desembolsa |
| Fabrica faltas | **89** no justificadas, alimentando el expediente disciplinario |

Y pasa **mudo**: no hay ni un trigger sobre `asignaciones_salario` ni sobre
`horarios_asignados`, y el candado de periodo pagado vive DENTRO de
`fn_set_salario`, así que un update desde otra función lo esquiva.

**El diseño que queda:** no se reabre el tramo viejo, se **crea uno nuevo desde
el día de la reactivación**. El hueco queda sin salario y sin horario, que es la
verdad —esa persona no trabajó—, y ninguno de los cuatro daños puede ocurrir.

**El candado es ESTRECHO, y se decidió con datos.** Volver a `activo` mueve por
sí solo el total de las planillas pagadas de quien tiene hijos —S/98.31 por
periodo, porque la asignación familiar no mira tramos ni jornadas—. Pero de las
**8 personas inactivas de producción, seis tienen un periodo pagado posterior** y
para las seis el daño es CERO (RxH, sin hijos, sin sueldo fijo). Un candado sobre
«hay un periodo pagado» rechazaría seis reactivaciones legítimas de ocho: no
protegería, prohibiría. Se pone solo donde el daño está medido — `con_hijos` con
un periodo pagado detrás—, y **eso es una lista que hay que revisar** el día que
aparezca otro concepto que se pague sin mirar tramos.

**Lo que falta antes de pegarla:** la prueba pgTAP, medir la promesa central
contra un periodo pagado de verdad, y los tres bordes reproducidos (volver
teniendo ya un tramo abierto, un tramo cerrado con fecha futura, y el caso de
cero filas). **No urge:** medido en producción, nadie está hoy en ese estado.

**Y hay dos cosas que la medición destapó y que NO causa la 0209:**

- Una **liquidación ya pagada se vuelve a devengar entera** al reactivar:
  S/852.19 sobre ventanas ya liquidadas por S/1,380.81. `fn_liquidacion_pagar`
  escribe en `liquidacion_pagada` y en `correcciones_auditoria`, pero **no** en
  `desembolsos_beneficios` ni en `movimientos_planilla`, que son las dos únicas
  cosas que miran los guards de `fn_provisiones`.
- La cabecera de la **0176 tiene una errata**: dice que «`fn_set_salario`
  comprueba que la persona esté activa». **Es falso** en la versión vigente — ni
  esa ni `fn_set_horario_semanal` miran `personas.estado`. Es justo la frase que
  haría no poner un freno creyéndolo puesto.

## ~~2026-08-10 — regenerar `types.ts` ya no es solo reordenar~~ ✅ HECHO el 2026-08-14

**Cerrado.** Se hizo, y la causa era más simple —y peor— de lo que decía esta
sección: el generador declara los parámetros de cada función como NO anulables, y
`fn_set_fin_contrato(p_fecha)` acepta null a propósito. Correr el comando dejaba
**63 errores en diez pantallas**. `scripts/tipos-args-nullables.mjs` le agrega
`| null` a los 491 parámetros y va encadenado al script de `gen-types`, así que
el comando documentado ahora termina en verde. Se conserva lo de abajo por el
registro de cómo se midió.



**Medido, no supuesto.** El repositorio venía diciendo que regenerar
`packages/database/src/types.ts` «reordena las 4.400 líneas del archivo entero»
y por eso se aplazaba, resolviendo cada función nueva con un doble casteo. Se
probó de verdad al añadir `fn_expediente_resolver` (0206):

- Genera **4.217 líneas** contra las 2.535 de hoy.
- **Gana 65 nombres** y suelta exactamente dos: `fn_set_horario` y
  `fn_quitar_horario`, que la 0184 borró. Hasta ahí, estrictamente correcto.
- **Pero cambia la convención de los argumentos opcionales**, de
  `string | null` a `string | undefined`. Eso rompe de golpe Ausencias,
  Correcciones y Datos personales, que pasan `null` a propósito.

O sea: **no es un reordenamiento, es una migración de tipos.** Aplazarla sigue
siendo razonable, pero por un motivo distinto al que estaba escrito, y el coste
de aplazarla crece — ya son tres las funciones que el archivo no conoce
(`fn_expediente_resolver`, `fn_tardanza_escalon`, y las columnas nuevas de
`fn_tardanzas_resumen`).

Cuando se haga, va sola en su propia rama y con las tres pantallas revisadas.

---

## 2026-08-10 — un `drop function` se llevó el permiso y la pantalla se calló

**Dos pantallas llevaban días caídas en producción y ninguna lo dijo.** Se
levantaron con la [`0204`](../supabase/migrations/0204_un_drop_se_lleva_el_permiso_y_la_pantalla_se_calla.sql),
que son dos `grant` y nada más. Verificado en producción: las tres filas en
`true`, y Disciplina volvió a listar a las dos personas que le tocaban.

**LA CAUSA, y es de clase, no de caso:** un `drop function` se lleva por delante
los `GRANT`. La [`0189`](../supabase/migrations/0189_una_tardanza_de_tres_horas_deja_de_desaparecer.sql)
hace ese drop sobre `fn_tardanzas_resumen` —obligada, porque devuelve `TABLE` y
Postgres no deja añadirle una columna con `create or replace`— y no vuelve a
otorgar. El último `grant execute` de esa función era de la **0067**. Como este
proyecto revoca el `EXECUTE` que Postgres da a PUBLIC por defecto, no hubo red.

**POR QUÉ NADIE LO VIO EN DOS DÍAS:** `authenticated` no podía ejecutarla,
PostgREST devolvía error, y `admin/disciplina/page.tsx` **no miraba el error de
esa llamada**. Imprimía «Nadie con tardanzas relevantes este mes» — la misma
frase exacta que cuando de verdad no hay nadie. El Dashboard y la Hoja de sede
leen la misma función y estaban igual de ciegos. Un falso negativo mudo en las
tres pantallas que existen para no dejar pasar a nadie.

**LA SEGUNDA, encontrada barriendo las 122 funciones que el panel llama por
`rpc()`:** la 0198 añadió `p_cuspp` a `fn_set_datos_personales` con un
`create or replace`. **Un parámetro nuevo no reemplaza: crea otra función.**
Quedaron dos sobrecargas —18 argumentos con permiso, 19 sin él— y el panel manda
`p_cuspp`, así que PostgREST elegía justo la que no podía ejecutar. Guardar una
ficha fallaba desde entonces. La sobrecarga huérfana de 18 sigue viva, muerta
pero inofensiva; **soltarla queda pendiente**.

**LAS DOS REGLAS QUE DEJA:**

1. **Toda migración que haga `drop function` vuelve a poner su `grant`.** No es
   opcional y no lo cubre nada: el `create or replace` conserva permisos, el
   `drop` + `create` no. La 0200 ya lo lleva por esto.
2. **Añadir un parámetro a una función es crear una función nueva.** Hay que
   otorgarle permiso, y decidir qué se hace con la vieja — dejarla viva es una
   ambigüedad esperando a que alguien la pise.

**Cómo se vuelve a comprobar**, sin fiarse de ninguna lista guardada:
[`quien_puede_ejecutar_el_semaforo.sql`](../scripts/sql-manual/quien_puede_ejecutar_el_semaforo.sql).

**Lo que sigue abierto de aquí:** ninguna prueba habría cazado esto. Las pgTAP
corren como `postgres`, que puede ejecutar todo; el defecto solo existe para
`authenticated`. Una prueba que compruebe los permisos del rol real es el
guardián que falta.

---

## 2026-08-08 — el papel que se le entrega a un locador dejó de llamarlo trabajador

La 0199 le quitó a un locador las cifras que no le tocaban —feriados,
gratificación, CTS, vacaciones— y el papel quedó correcto en los números y falso
en las palabras: seguía titulándose «Boleta interna de pago», llamaba
«Remuneración Básica» a sus honorarios, cerraba con «Total a recibir este mes»,
le contaba los días que «le tocaba venir» y lo mandaba a «consultar con tu líder
de equipo».

**Eso no es redacción, es lo que el documento declara.** En una inspección, el
papel que la empresa emite todos los meses pesa más que el contrato firmado: la
subordinación se prueba con indicios, y aquí CAYLA los estaba imprimiendo ella
misma, en el único ejemplar que esa persona se lleva a casa.

Ahora la pantalla imprime **dos documentos distintos**, no uno con filas de
menos. Quien presta servicios recibe un «Detalle de servicios prestados»: dice
qué relación es (locación del Código Civil), quién organiza el tiempo, que el
documento oficial es **su** recibo por honorarios y —recién al final, como
consecuencia y no como recorte— por qué no hay beneficios. Cierra con «emite tu
recibo por este importe».

**El interruptor es uno solo y vive en `packages/shared/src/vinculo.ts`**, no en
la pantalla. Son nueve las que van a hacer la misma pregunta, y este repositorio
ya juntó 35 copias de la misma condición de permiso antes de aprenderlo.

Ahí está también la regla que más importa: se pregunta `en_planilla === false`,
nunca `!en_planilla`. El frontend se despliega por Vercel mientras el SQL lo pega
Felipe a mano, así que hay ventanas en las que la pantalla nueva corre contra una
base que todavía no manda el campo. Con `!en_planilla`, ese `undefined`
convertiría a **todo el mundo** en locador de golpe: treinta personas recibirían
un papel que les niega gratificación, CTS y vacaciones, y saldría bonito. Las
cuatro pruebas de `tests/vinculo.test.ts` existen para eso.

### Se dice la tarifa por hora, no un sueldo mensual

Durante unos minutos la hoja de Carlos imprimió **«Honorarios pactados (mes
completo) — S/ 1,800.00»**, y era la única frase que contradecía a las otras
cinco: ellas afirman que no hay contrato de trabajo, y esa afirmaba un monto
mensual fijo. Carlos y Claudia **cobran por hora**. Ahora dice **«Tarifa por
hora — S/ 8.9330»**, que es lo que de verdad se pactó y además afirma lo
contrario de un sueldo.

Dos cosas de esa línea que no son cosmética:

- **Sale de `salario_ref`, no de `sueldo_base_legal`.** Es el dato con el que
  `fn_planilla_calcular` calcula el pago, así que `tarifa × horas` reproduce el
  total de la propia hoja. Un documento que no cuadra consigo mismo es peor que
  uno que no dice nada.
- **Cuatro decimales, y no dos.** A S/ 8.93 la hora, 27 h 30 min dan S/ 245.58 y
  la hoja remata en S/ 245.66. Ocho céntimos bastan para que alguien piense que
  le descontaron algo.

### Lo que solo se vio mirando la hoja renderizada

La boleta le imprimía **«Colibrí»** — un peldaño de la escala de trabajadores.
La 0182 ya había decidido esconderlo, con este argumento: decir que alguien ocupa
una categoría de la escala es parte de lo que desnaturaliza una locación. Pero se
aplicó solo en la tabla de Planilla. En el código las dos pantallas no se parecen
en nada y ningún `grep` las conecta; se cazó abriendo el documento.

Y la primera tarifa por hora salió **S/ 0.2882**: `proy.base_horas` ya son las
horas de todo el periodo (`6.5 × días`), y la fórmula las volvía a multiplicar
por los días. El typecheck no podía verlo —los dos campos son `number` y las dos
fórmulas compilan igual— y ninguna prueba de interfaz lo habría cazado. **La
lección de método: un documento que se imprime se revisa imprimiéndolo.**

### Lo que queda de este hilo

- **Faltan las otras ocho pantallas** con el mismo problema: Planilla (135
  conceptos laborales), Provisiones, Liquidaciones, Feriados, Vacaciones, Costos,
  Ausencias y Disciplina.
- **Claudia** es el mismo caso que Carlos y aún no se movió. **Catherine** es
  otro distinto —socia, monto fijo— y se dejó para después a propósito.

---

## 2026-08-08 — el sobretiempo se paga solo, y todo lo que se cobra se declara

Empezó con una pregunta de Felipe —por qué el sistema no dejaba dar el sábado
como descanso por un feriado trabajado— y terminó en cinco migraciones. Lo que
va acá es lo que ninguna consulta puede responder: **por qué se decidió así**.

### Cómo se mide el sobretiempo, y las tres trampas

**Contra 48 h SEMANALES, nunca contra 8 h diarias.** El art. 25 de la
Constitución dice «ocho horas diarias O cuarenta y ocho semanales» y CAYLA pactó
la semanal, en contratos y RIT. Medido por día, el taller de Lima —5 días de
9 h = 45 h— generaría sobretiempo todas las semanas del año haciendo tres horas
MENOS que el máximo legal.

**«Semana» es un ciclo de siete días, no lunes a domingo.** Criterio vinculante
del Informe 027-2021-MTPE/14. El ciclo empieza tras un descanso y se corta a los
7 días; sin ese corte, doce días seguidos de 8 h darían 48 h de exceso en vez
de 8 — un tope semanal convertido en tope por racha, que no existe en la norma.

**Los ciclos no se solapan, y por eso el pago NO usa la ventana móvil** que sí
usa la alerta de Incidencias. Ahí el objetivo es no perderse ningún tramo
cargado; acá, una ventana móvil pagaría la misma hora siete veces.

Y se suma **el recargo** (25 % / 35 %), no la hora completa: las horas ya están
en `pago_base`. Es el mismo error que la 0173 corrigió con el feriado del sueldo
fijo.

### Tres exclusiones distintas que NO se pueden fundir en un campo

| Quién | Por qué | Dónde vive |
|---|---|---|
| RxH | Un locador no tiene jornada; pagarle horas extras es indicio de laboralidad | `tipo_vinculo` |
| Personal de dirección | Art. 5 del D.S. 007-2002-TR: fuera de la jornada máxima | `personas.personal_direccion` (0187) |
| Sueldo fijo | Su pago no depende de horas: un recargo sobre monto fijo no dice nada | `sueldo_fijo` |

**`personal_direccion` tiene columna propia y no se deduce del rol.** `admin` es
un permiso informático: el día que se le dé admin a alguien de DO para
administrar pantallas, se le quitaría sin querer su derecho a horas extras. Y no
es lo mismo que `sueldo_fijo`, que es una condición de pago — hay dirección que
cobra por horas. Hoy está marcado Felipe, y solo él.

### Qué entra a la base de EsSalud y pensión, y qué no

Entran el **feriado** y el **sobretiempo** (0193). No admiten discusión: el
art. 19 del D.S. 001-97-TR no los lista como no remunerativos y SUNAT les da
código propio en la tabla 22 de la PLAME — **0105** (sobretiempo 25 %), **0106**
(35 %) y **0107** (feriado o día de descanso).

**No entran, y no es un olvido:** el complemento variable y el plus por
objetivos, que tienen defensa legal real y están dentro de una estructura
decidida con el contador (ver
[`analisis-estructura-remunerativa-2026-07-30.md`](analisis-estructura-remunerativa-2026-07-30.md));
y la movilidad y la educación, no remunerativas por el art. 19 incisos e) y f).

⚠️ **Las sobretasas COMPLETAN una base declarada; no crean una donde no la hay.**
La primera versión le inventaba S/41.39 de pensión a un RxH y S/46.45 a alguien
con sueldo fijo — los dos tienen la básica en 0 a propósito. Ninguna prueba
existente cayó: eran montos de personas que antes no aparecían en ningún cálculo
de pensión. Lo fija ahora la `150_la_base_de_aportes_no_se_inventa`.

### La vía para reducir el costo en origen NO es dejar de declarar

Son dos, y las dos son legales:

- **Descanso sustitutorio** por feriado trabajado (art. 9, D. Leg. 713). Con él
  la sobretasa del 100 % no se genera. Medido en un caso real: el feriado de esa
  persona baja de S/206.83 a S/104.89.
- **Compensar el sobretiempo con descanso equivalente** (art. 10 del TUO), con
  acuerdo por escrito, dentro del mes calendario siguiente, sin tocar el descanso
  semanal ni caer en feriado.

**No aplicar la 0193 no era una vía.** La obligación existe con o sin migración:
lo único que cambiaba era si el sistema la mostraba.

### El retroactivo, y por qué no fue «por fuera»

S/100.03 en 8 personas por el sobretiempo de 28-jun → 28-jul, registrado como
movimiento en la planilla de agosto con el concepto nombrado. Felipe propuso
pagarlo en efectivo y se descartó: el sobretiempo **es remuneración**, así que
pagarlo fuera de planilla sería remuneración no declarada — una infracción nueva
y formal para tapar una vieja e informal. Misma plata, un renglón de diferencia.

### La política salarial, versión 4

Publicada el 2026-08-08 20:20. Dice el sobretiempo (25 % / 35 %), que la base de
aportes incluye feriados y sobretiempo, y **avisa que el neto baja antes de que
llegue la boleta** — entre S/9 y S/50 por persona, íntegro a su fondo.

⚠️ **Y lleva un blindaje que hay que conservar.** Al reforzar «45 horas cuando la
ley permite 48», Felipe levantó el riesgo: si alguien llegara a sostener que la
jornada pactada son 45, las horas 46 a 48 pasarían a ser sobretiempo con recargo
para todo el equipo, todas las semanas. El documento dice ahora, en el mismo
párrafo, que **el sobretiempo se cuenta desde la hora 49 y no desde la 46**, y
cinco pruebas de `politica-salarial.test.ts` no dejan que se caiga — incluida una
que verifica que nunca aparezca la frase «jornada de 45 horas».

**La versión 3 se quemó** por caché del navegador: se publicó un documento byte
por byte idéntico al anterior y el sistema no dijo nada. Quien la haya acusado
tiene que volver a hacerlo sobre la 4.

---

## 2026-08-08 — seis puertas dejaban cambiar una planilla ya pagada

**El repositorio y producción llevaban semanas diciendo cosas distintas, y no
había manera de enterarse.** Se compararon los dos esquemas enteros —199
funciones, 261 candados, 467 columnas— y el resultado ordena todo lo de abajo:

| | |
|---|---|
| **candados** | idénticos, byte a byte. Es lo que volvió inofensivo casi todo lo demás |
| **columnas** | idénticas, salvo dos que solo existen en producción |
| **funciones** | **22 distintas** |

### Lo único que era grave

Seis funciones de producción no tenían el candado de periodo pagado que el
repositorio les puso en julio con la 0026 y la 0037: `fn_set_feriado`,
`fn_quitar_feriado`, `fn_set_turno`, `fn_quitar_turno`, `fn_set_horario_semanal`
y `fn_set_descanso`.

Reproducido en local el estado exacto de producción y llamadas las seis sobre una
fecha de un mes ya pagado, **las seis dejaron pasar el cambio y una borró un
feriado de un mes pagado sin decir una palabra.** El daño no se ve: la jornada se
recalcula sola con el trigger, las horas del mes cambian, y la planilla
depositada deja de cuadrar con lo que el sistema dice hoy. Se descubre cuando
alguien reclama.

La [`0180`](../supabase/migrations/0180_el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron.sql)
lo repone —aplicada y confirmada, 6 de 6— y la prueba
[`141`](../supabase/tests/141_las_seis_puertas_a_una_planilla_pagada.test.sql)
exige **las dos mitades**: que dentro de lo pagado lancen, y que fuera de lo
pagado sigan funcionando. Un candado que cierra siempre lo quita cualquiera en la
primera urgencia.

Antes de sobrescribirlas se pidieron sus cuerpos y se compararon línea a línea:
producción era el repositorio **menos** el bloque, ni una línea de más. Mirar
antes de escribir no era ceremonia — siete funciones de las 22 tienen código que
el repositorio no conoce (ver abajo).

### El resto era texto roto

Seis funciones decían `l√≠der` donde debía decir `líder`: UTF-8 leído como **Mac
OS Roman**, que parte cada acento en dos. Se confirmó simulando esa conversión
sobre el cuerpo del repositorio — los md5 salen exactos, así que se identificaron
sin gastar consultas. Lo arreglan la **0181** (cuatro) y la **0183** (las dos que
la comprobación de la 0181 destapó, que además corrían la versión de julio de
`fn_crear_periodo` y `fn_eliminar_periodo`). Las dos aplicadas y confirmadas.

⚠️ **Y ese mismo día se demostró que el daño SIGUE ENTRANDO.** Horas después de
limpiar las seis, la consulta «qué falta pegar» devolvió `⚠ md5 SIN CATALOGAR`
para `fn_planilla_calcular` — la función que decide lo que cobra cada persona.
Medido: era el cuerpo de la **0185 pasado por Mac OS Roman**, y la 0185 se había
pegado ese mismo día.

O sea que el razonamiento de arriba —«si el canal fuera el culpable estarían
rotas las 199»— **era falso**: el daño no entra de una vez, entra **por pegada**.

✅ **Y la causa se encontró el mismo día: era `pbcopy` con el locale en `C`**
dentro del propio `dame-el-sql.sh`. Con `LC_CTYPE=C` el portapapeles interpreta
el UTF-8 como MacRoman y cada acento se parte en dos. O sea que la ruta culpable
no era «otra vía»: era la nuestra, en las sesiones cuyo entorno tenía ese locale
—por eso cuatro migraciones del mismo día salieron limpias y una no—. Ya está
arreglado: el script compara el portapapeles byte por byte contra el archivo y se
niega si no coinciden. Ver la regla en `CLAUDE.md`.

**Quedan dos detectores permanentes, y ninguno depende de una lista a mano:** la
fila **ACENTOS** de `que_falta_pegar.sql`, que barre el esquema entero buscando
el signo «√», y la columna `tiene_acentos_rotos` de
`en_que_version_esta_la_planilla.sql`. El catálogo de md5 de esa consulta
**también se calcula solo** desde las migraciones, con `iconv -f MAC` para
generar la variante rota de cada versión: llegó a mentir tres veces en un día
mientras se escribía a mano.

### El agujero que casi se anuncia y no existía

La 0026 le añadió a `fn_crear_periodo` un candado contra dos periodos que cierren
el mismo mes, con su motivo escrito en julio: «el plus de objetivos se pagaría
doble». Producción no lo tenía. La conclusión saltaba sola.

**Se probó antes de afirmarlo y es falsa.** El segundo periodo falla igual: lo
frena el índice único `periodos_etiqueta_unica` sobre (año, mes) de la fecha de
cierre. Y los 261 candados de producción son idénticos a los del repositorio.
Igual con el `advisory lock` que falta: `periodos_sin_solape` impide el solape de
todos modos.

**Aquí lo que protege el dinero es el candado de la BASE, no el de la función.**
Las seis puertas eran un agujero real porque detrás no había ningún constraint;
esta no lo era porque sí lo hay. Misma forma, conclusiones opuestas, y solo
medirlo las distingue.

### La lección de método, que costó medio día

**Un dato de referencia nunca viaja guardado — ni en un archivo ni en un
mensaje.** El comparador viejo llevaba las huellas del repositorio dentro y
acusó a 25 funciones que estaban bien. Se sacaron del archivo… y entonces
caducaron en el mensaje que las transportaba: se calcularon a las 10:28, entraron
cinco migraciones a las 10:55 y 11:14, y la comparación de las 11:30 ya no valía.

### Y aun así, empieza por la lista de números — medido el 2026-08-19

Los md5 son la herramienta fina, pero **caducan en minutos**, y ese día caducaron
para los dos lados a la vez:

- La huella de producción dijo `hasta_migracion: 287` cuando ya iba por la 301
  — entre una consulta y la siguiente se pegaron migraciones.
- Y la base local de esta Mac saltó de 286 a 301 en mitad de la comparación,
  porque otra sesión corrió `db reset`.

Resultado: tres md5 distintos, +3 funciones y +14 columnas de diferencia, y una
sospecha de código cambiado a mano en producción **que era falsa entera**.

Lo que lo resolvió en un minuto fue esto, que no caduca:

```sql
select string_agg(numero::text, ',' order by numero) as numeros
from migraciones_aplicadas
where numero >= 265;
```

Esa lista se compara contra `ls supabase/migrations/`. O está el 295 o no está —
no hay generación que valga. Ese día la respuesta fue **faltaban dos**, la 0295 y
la 0296, y ni una sola migración en producción que no estuviera en el repositorio.

**La regla:** los números primero. Los md5 solo si los números ya coinciden —
porque solo entonces significan algo.

`huella_del_esquema.sql` calcula las dos mitades en el mismo minuto y trae
`hasta_migracion`, para que comparar dos generaciones distintas se delate en vez
de asustar. Los tres comparadores que mentían —`comparar_funciones.sql`,
`comparar_solo_funciones.sql`, `huellas_produccion.sql`— quedan **vaciados, no
borrados**: su contenido está en git y su ruta sigue avisando por qué no usarlos.

**Y una comprobación que barre gana a una que pregunta por una lista.** La de la
0181 no preguntaba por sus cuatro funciones: buscaba el signo «√» en el esquema
entero. Devolvió dos que nadie había señalado.

---

## 2026-08-06 — ningún papel firmado se podía subir, y nunca se pudo

**Lo que parecía un módulo terminado desde julio no funcionaba ni una vez.** El
cargo firmado de un memo disciplinario no se podía archivar desde que existe el
módulo (0074). Los tres memos entregados de producción llevaban semanas con «sin
el papel archivado» al lado y no era descuido de nadie: la base los rechazaba.

**La causa, que no se veía leyendo el código.** Supabase Storage no escribe el
objeto con un `INSERT`. Escribe `INSERT … ON CONFLICT DO UPDATE … RETURNING *`, y
esa forma necesita **tres** permisos, no uno: INSERT por la fila, SELECT por el
`RETURNING`, y UPDATE por el `ON CONFLICT`. Ningún bucket tenía política de
UPDATE. Y la de SELECT de `expedientes` exigía que el adjunto ya estuviera
registrado en `expediente_adjuntos`… registro que se crea DESPUÉS de subir el
archivo. Un círculo cerrado: no se podía escribir sin poder leer, ni leer sin
haber registrado, ni registrar sin haber escrito.

Lo que más costó: `fn_expediente_puede_adjuntar` devolvía **`true`** mientras la
fila se rechazaba, así que el fallo se leía como un problema de permisos de la
persona. El mensaje de Postgres nombra la tabla pero **no dice cuál de las
políticas faltó**. Se resolvió leyendo el log del contenedor de storage.

| # | Qué |
|---|---|
| **0170** | El acta de descanso acepta **HEIC/HEIF** — el formato en que un iPhone guarda sus fotos. Sin esto salían en gris en el diálogo de archivos: no se podían ni seleccionar, y la pantalla no daba ningún error |
| **0172** | Las políticas que faltaban en los tres buckets. Abre exactamente el hueco medido y nada más: quien subió un archivo puede leer **lo suyo** mientras lo registra (`owner_id = auth.uid()`), y quien puede crearlo puede reemplazarlo |
| **0175** | El acta de descanso **deja de guardarse como texto en una columna** y pasa al almacén, con los mismos 50 MB que los demás papeles. Los 3 MB de antes no eran una decisión sobre las actas: eran el precio de dónde vivían |

**Tres fallos más de pantalla, cada uno con causa distinta:** el formulario para
subir el cargo estaba escrito **solo** en «Firmados — por entregar», y los tres
memos de producción están entregados · Chrome **no reconoce el `.HEIC`** y
entrega la foto sin tipo, que el almacén rechaza con `415` (el tipo se deduce
ahora de la extensión, en `lib/tipos-archivo.ts`) · «Ver acta» abría un
`<iframe src="data:…">` que Chrome **bloquea**, dejando la pestaña en blanco.

**Por qué ninguna prueba lo cazó.** No había una sola que tocara
`storage.objects`, y un `INSERT` simple pasaba mientras el sistema no
funcionaba. La prueba **136** ejecuta ahora la sentencia real de Storage,
copiada de su log; la **137** cubre las dos ubicaciones posibles del acta.

---

# 📌 QUÉ FALTA — repartido por quién lo hace

## A · Lo que depende de Felipe

### A.1 · Con fecha límite — **en curso** (confirmado 2026-08-06)

| Qué | Cuándo | Si no |
|---|---|---|
| **Los convenios individuales de movilidad, firmados y cargados** | **antes del 28/08/2026** — es cuando se paga el periodo | Se habrá pagado movilidad sin el papel que la sostiene. La **RTF 05449-4-2007** desconoció la de 14 de 21 trabajadores por eso exacto |
| **La política de movilidad de empresa, firmada** | con fecha **anterior al 29/07/2026** | Es cuando empezó a pagarse movilidad. Un documento posterior a los pagos que justifica **no los justifica, y encima lo deja por escrito**. El tablero lo avisa solo, en rojo, con las dos fechas |
| ~~**Contratar el Seguro Vida Ley**~~ | ✅ **contratado con Pacífico, póliza Nº 143720** — visto en los certificados el 2026-10-21 | Prima **S/70 al mes**, inicio de la póliza 01/08/2026. **Dos personas sin certificado en mano** (puede que ya estén declaradas: la serie tiene 18 números y se liquidaron S/22,420 en octubre), **no consta el pago de las liquidaciones** (octubre vence el 31/10), ni el registro en el MTPE, ni las declaraciones juradas de beneficiarios: ver la sección del 2026-10-21, arriba. Quien quede sin declarar: CAYLA responde con su patrimonio, ~S/20,000 por muerte natural o ~S/40,000 por accidente o invalidez total (D.Leg. 688, mod. **Ley 31408**) |
| **Pagar el día sustitutorio de Arequipa** | **el 29/09/2026**, con el periodo 29/08–28/09 ya cerrado | El equipo de AQP habrá descansado el 31/08 sin cobrarlo, y el acuerdo que firmaron dice que sí les tocaba. **No es automático**: el sistema no sabe que el 15/08 existe. Ver la sección propia más abajo |
| **Registrar la póliza en el MTPE** | 30 días desde que se firma — **no consta que se haya hecho** (2026-10-21) | No registrarla es la misma infracción que no tenerla |
| ~~**Pegar la [`0176`](../supabase/migrations/0176_quien_ya_se_fue_deja_de_tener_sueldo_vigente.sql)**~~ | ✅ **pegada el 2026-08-06** | Las seis de julio dejaron de tener sueldo vigente. No movió plata: su liquidación es S/ 0.00 antes y después (RxH, de 0 a 3 días). Comprobado con cuatro ceros: sin tramos abiertos, sin tramos pasados de largo, sin tramos posteriores al cese, sin motivos por revisar |
| ~~**Pegar la [`0179`](../supabase/migrations/0179_la_pantalla_de_equipo_dice_cuando_y_por_que_se_fue.sql)**~~ | ✅ **pegada** — figura en `migraciones_aplicadas` de producción | La pantalla de Equipo ya dice cuándo y por qué se fue cada quien. El motivo viaja solo a admin y líder DO |
| ~~**Pegar la 0180, la 0181 y la 0183**~~ | ✅ **pegadas el 2026-08-08** | Ver la sección del 08-08 arriba. Confirmadas por lo que devolvió el SQL Editor: `las_seis_con_candado: 6` y `funciones_con_texto_roto: 0` |
| ~~**Pegar la [`0201`](../supabase/migrations/0201_la_foto_del_pago_aprende_el_sobretiempo.sql)**~~ | ✅ **pegada el 2026-08-10** | Sin ella, «Marcar como PAGADO» fallaba **para todo el periodo** —no solo para quien hiciera sobretiempo— en cuanto alguien pasara de 48 h en un ciclo de siete días. El candado de la foto era de julio (0127) y no conocía el sobretiempo que la 0185 empezó a pagar en agosto. Confirmada con cinco comprobaciones en verde, incluida la que recorre las 96 fotos ya guardadas con la fórmula nueva: ninguna se rompió |

**Del Seguro de Vida Ley (corregido el 2026-10-21):** lo que se cotizó en agosto fue **La Positiva, S/170/mes por 19
personas**, pero lo contratado es **Pacífico, póliza Nº 143720**, a **S/70 al mes** y sin intermediación (las
liquidaciones lo dicen). Dante confirmó que en este seguro el reglamento no contempla comisión de corredor. El cruce
contra planilla ya se hizo (17 en planilla, 15 con certificado en mano, 2 sin él): ver la sección del 2026-10-21, arriba. Quien esté en planilla y
sin declarar a Pacífico queda sin cobertura, y ese capital lo paga CAYLA de su patrimonio. La consulta que arma la
lista y el cruce está en
[`quienes_van_al_seguro_de_vida_ley.sql`](../scripts/sql-manual/quienes_van_al_seguro_de_vida_ley.sql).

### A.2 · Lo que bloquea del contador — la marca de afectación

El código no es el problema: el problema es **con qué marca de afectación**
quedan el 0909 (movilidad), el 0202 (educación) y el 0203 (cumpleaños) en el
PDT — EsSalud, ONP/AFP y quinta categoría. Si alguno queda declarado afecto, no
solo se pagan aportes que la ley no exige: **CAYLA declara por escrito y mes a
mes que el concepto es remunerativo**, y eso destruye el sustento del artículo 19
con nuestra propia firma.

Es lo único que tiene que responderse **antes de declarar el primer periodo** con
los tres conceptos. La repregunta está redactada y lista para enviar en
[`movilidad-y-codigos-plame-para-el-contador.md`](movilidad-y-codigos-plame-para-el-contador.md).

*(Dante escribe los códigos sin el cero inicial —dijo «909» por 0909—, así que
son **0202** y **0203**. Falta su confirmación de una línea.)*

### A.2.a · La maternidad: **construida y aplicada** (0262, en producción el 2026-08-17)

**Nadie ha estado de maternidad todavía, y por eso hubo tiempo de hacerlo bien.**
La duda de si el subsidio va por planilla o por fuera **quedó resuelta por la
norma, no por criterio**: el D.S. 013-2019-TR art. 17.1 obliga al empleador a
pagarlo **en la misma fecha en que pagaría la remuneración**, y el art. 17.2 hace
que el reembolso **exija haber pagado antes**. No es opcional y no va por fuera.

Lo que sí es correcto es que el **sueldo** salga en S/0.00: durante la licencia el
contrato está suspendido (D. Leg. 728, arts. 11 y 12.c). Lo que faltaba no era
sueldo — era el subsidio, que no entraba por ningún lado.

**La 0262 lo conecta**, con la misma forma que la 0254 usó para el descanso
médico: dentro de `pago_base`, así que no toca `chk_foto_cuadra` ni
`fn_planilla_congelar` y no puede atascar un cierre. Medido en local con datos
propios (licencia de 10 días corridos, S/200 diarios, feriado dentro):

| | días | subsidio | pago_base | base EsSalud | retiene pensión | total |
|---|---|---|---|---|---|---|
| AFP (integra) | 10 | 2 000.00 | 2 000.00 | **765.48** | 258.40 | 1 741.60 |
| ONP | 10 | 2 000.00 | 2 000.00 | 765.48 | **0.00** | 2 000.00 |
| sin monto entrado | 0 | 0.00 | 0.00 | 1 130.00 | 0.00 | **avisa: 10 días sin monto** |

Las cinco decisiones que la sostienen:

- **Días calendario, no laborables.** El promedio diario de EsSalud ya viene
  dividido entre días corridos; contarlo por laborables le quitaría dos séptimos
  a quien trabaja cinco días. Es la diferencia de fondo con el descanso médico,
  que sí cuenta laborables porque aquello es sueldo.
- **El feriado de dentro se cuenta, y se le quita a `fer`.** El primer intento
  hacía lo contrario —copiaba el filtro de la 0254— y **medirlo lo tumbó**: quien
  está de licencia todo el mes devenga S/0.00 de feriados, así que excluirlo no
  evitaba una duplicación, le quitaba el día. Diez días le pagaban nueve. La
  duplicación se evita por el otro lado: `fer` deja de devengar los feriados de
  dentro de la licencia. Las dos mitades son una sola decisión.
- **El monto lo entra DO, no lo calcula el sistema.** Los 12 meses del promedio
  pueden incluir **empleadores anteriores a CAYLA**, y esta base solo tiene una
  foto congelada. Y hay una razón más que salió de la investigación: **el divisor
  360 no está en el D.S. 013-2019-TR** — la norma dice «promedio diario» y el 360
  es práctica de EsSalud. Va en `ausencias.subsidio_diario`.
- **No infla EsSalud, y el piso RMV se prorratea.** El art. 33 del D.S. 009-97-SA
  tiene una excepción expresa: para quien percibe subsidios, la base mínima se
  determina «de forma proporcional a los días no subsidiados del mes». Sin eso
  CAYLA declararía la RMV entera por alguien de licencia. No perjudica a nadie:
  es plata de la empresa y una declaración que no corresponde.
- **AFP sí, ONP no** — y ya **no es criterio, es norma expresa**: art. 16 de la
  Ley 26504 («los subsidios de carácter temporal … se encuentran afectos» al SPP)
  y último párrafo del art. 30 del TUO de la Ley del SPP. La ONP la resuelve el
  Informe N.° 049-2014-SUNAT/5D0000. Vive en `tasas_pension.grava_subsidio`.

**EL ACCIDENTE QUE CASI PASA, y por qué el número es 0262.** Esto se escribió
como **0256**, con el cuerpo sacado de la 0254 —la vigente entonces—. Mientras
se escribía, otra sesión fusionó a `main` la **0261**, que reescribe la MISMA
función y que también había partido de la 0254. Dos migraciones sobre la misma
base: **la última en aplicarse borra a la otra en silencio**, y como 0261 > 0256
el orden de pegado habría hecho desaparecer todo esto sin un solo error.

Lo cazó `./scripts/donde-vive.sh` al ir a fusionar. Por eso la migración se
renumeró a 0262 y su cuerpo se volvió a extraer de la 0261. La regla, otra vez:
**el cuerpo se copia de la VIGENTE, y la vigente se pregunta, no se supone** —
y se vuelve a preguntar justo antes de fusionar, porque main se mueve.

**LA CADENA DE md5, para verificar cada pegada:**

| paso | md5 | caracteres |
|---|---|---|
| producción hoy (0254) | `19eb593a757e0b7480b6a1dc99d7f8c9` | 75 882 |
| tras lo pendiente hasta la **0261** | `0d0f5fdd5f53d29fb316be50c794cec6` | 77 493 |
| tras la **0262** | `261329fc2a8045ece063cfb0e5d38eca` | 87 322 |
| tras la **0263** | `f6b4f2649f4132dd2db5711b391b1f54` | 89 134 |

**LO QUE FALTA, en orden:**

1. **Pegar todo lo pendiente hasta la 0261** y comprobar que el md5 quede en
   `0d0f5fdd…`. Si no queda ahí, la 0262 no se pega.
2. **Pegar la 0262 y luego la 0263** — *después del cierre del 28*, no antes.
3. **El formulario todavía no tiene el campo.** `fn_registrar_ausencia` no conoce
   `subsidio_diario`, así que hasta que una migración se lo enseñe el monto se
   pone con `scripts/sql-manual/poner_el_subsidio_de_maternidad.sql`. Mientras
   tanto la planilla **avisa** de los días sin monto en vez de pagar cero
   callando, que era el defecto original.

### A.2.a.bis · Dos hallazgos que salieron de la investigación del 2026-08-15

**1 · Los primeros 20 días de descanso médico estaban SUB-DECLARADOS → 0263.**
Confirmado con norma y con criterio administrativo: lo que CAYLA asume esos 20
días **es remuneración**, afecta a EsSalud y a la base de pensión (D.S. 009-97-SA
art. 15; Informes SUNAT 259-2004 y 003-2007). El código PLAME 0916 es **solo**
para el subsidio de EsSalud, que nace el día 21. La 0254 los metía en `pago_base`
pero **no** en `pb.basica`, así que no llegaban a `bri.base`: se pagaban y no se
declaraban.

**La 0263 lo corrige** — un solo término en `bri.base`, con la misma guarda de
vínculo que el feriado y el sobretiempo. Se pega **después de la 0262**, porque
su cuerpo parte de ella. Medido con una persona con S/870.97 de descanso médico:

| | hoy | con la 0263 |
|---|---|---|
| base EsSalud | 1 130.00 | 1 182.90 |
| aporte de CAYLA | 101.70 | 106.46 |
| **retención de pensión** | 40.30 | **152.83** |

Nadie más se mueve. **Pero esos +S/112.53 salen del sueldo de quien tuvo descanso
médico** — es lo correcto, porque esos días ahora sí le cuentan para su pensión,
y hay que avisarle antes de que le aparezca en la boleta.

La prueba 200 lo fija, y se verificó que **falla sin la 0263**: sin el arreglo,
las bases de la enferma y de la de control salían idénticas.

**2 · La asignación familiar: NO es exigible, y aun así NO se puede quitar.**
Investigado el 2026-08-15 con ocho agentes contra fuentes primarias. Las dos
mitades de la respuesta van juntas o se entiende al revés.

**No es exigible.** El art. 43 de la Ley 28015 (sustituido por el art. 7 del
D. Leg. 1086, hoy art. 50 del TUO D.S. 013-2013-PRODUCE) no la lista entre los
derechos del régimen especial. Lo que convierte esa ausencia en exclusión —y no
en silencio— es el art. 29 del reglamento (D.S. 008-2008-TR): el régimen «está
constituido por los beneficios laborales contemplados en la Ley». Y la técnica
legislativa lo confirma: cuando el legislador quiso que un derecho del régimen
general siguiera corriendo, lo dijo con nombre (utilidades, CTS, derechos
colectivos). Para la asignación familiar no hay remisión. **El Tribunal
Constitucional ya lo dio por sentado**: en la STC Exp. 00021-2014-PI/TC (Pleno,
13/03/2020) su propio cuadro comparativo dice «Asignación familiar — pequeña
empresa: No», y la demanda de inconstitucionalidad se declaró **infundada**. Los
dos refutadores independientes no pudieron tumbarlo.

**Pero no se puede suprimir.** Al venir pagándose, es una mejora del régimen
especial (art. 35 del D.S. 008-2008-TR) incorporada al contrato. Quitarla por
circular es **reducción inmotivada de remuneración = acto de hostilidad
equiparable al despido** (art. 30.b de la LPCL). Solo se puede suprimir hacia el
futuro, por acuerdo escrito, libre y con contraprestación, **persona por
persona**. Y lo ya pagado no se recupera ni se descuenta jamás.

**La vía de riesgo cero es congelarla**: dejar de subirla cuando suba la RMV, sin
tocar lo que hoy cobra nadie.

⚠ **Antes de cualquier cosa hay que verificar dos hechos**, y cualquiera de los
dos invierte el resultado:

1. **¿CAYLA está inscrita y vigente en el REMYPE?** El art. 29 condiciona todo el
   régimen especial a esa inscripción. Sin ella corre el régimen general y la
   asignación familiar **sí** es obligatoria. Revisar también el tope de 1700 UIT
   y las causales de exclusión del art. 31 (grupo económico, vinculación).
2. **Quién entró antes del D. Leg. 1086 o bajo régimen general** — el art. 30 les
   conserva sus derechos.

**Esto no es una decisión de código y no hay migración.** Es para el contador y,
por el tipo de exposición, probablemente para un abogado laboralista. Dato para
esa conversación: se declara en PLAME con el código **0201**, es computable para
gratificaciones, CTS y vacaciones, y afecta base de EsSalud, AFP/ONP y renta de
5ta — o sea que congelarla o quitarla arrastra más de una línea.

Durante la licencia por maternidad se sigue pagando: ninguna norma la condiciona
a labor efectiva.

### A.2.b · Los tres locadores están retratados como personal subordinado

**Para consultar con el contador. No hay nada roto en el cálculo** — eso se
verificó y se descarta abajo. Lo que hay es un riesgo de cómo el sistema los
retrata.

**Son tres, confirmado por Felipe el 2026-08-07:** Carlos Espejo, Catherine
Pereyra y Claudia Pereyra. Los tres cobran por honorarios y los tres aparecen
así:

| | Sede | Rol en el sistema | Área | Rango de la escala | Pago |
|---|---|---|---|---|---|
| **Carlos Espejo** | CCO | **Admin** | Desarrollo org. | Aurora · S/1,800 | **por hora trabajada** |
| **Catherine Pereyra** | CCO | **Líder de equipo (encargada)** | Comercial | Oráculo · S/1,800 | por confirmar |
| **Claudia Pereyra** | LIM | **Líder de equipo (encargada)** | Comercial | Aurora · S/1,800 | por confirmar |

⚠️ **La columna «Pago» decía «fijo mensual» para los tres y era falsa, al menos
para Carlos** (Felipe, 2026-08-08). Cobra **por hora**: marca cuando decide
trabajar y se le paga lo que marcó. No es un detalle contable — «monto fijo,
igual mes a mes» es uno de los indicios de laboralidad que miran SUNAFIL y los
jueces, y este cuadro lo daba por cierto sin haberlo comprobado. **De Catherine y
Claudia sigue sin confirmarse.**

Cargo de mando, área, sede y un rango de la escala salarial. Son indicios de
**subordinación**, que es lo que convierte una locación de servicios en un
contrato de trabajo.

**Lo que el caso de Carlos tiene A FAVOR, y este documento no decía:** es
cuadripléjico, trabaja desde su casa, **no está sujeto a horario** y **cobra por
hora**: marca cuando él decide trabajar. Ninguno de los indicios de subordinación
que lista la doctrina —horario fijo, instrucciones directas, equipos de la
empresa, monto idéntico cada mes— aplica a esa descripción. Su marcaje no es
control de asistencia sino la medida de lo que factura, y desde la
[`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql)
el sistema ya no lo trata como asistencia: no le mide tardanza ni salida
anticipada, solo sus horas.

Lo que queda en su contra es el RETRATO —el rol `admin`, el área, el rango de la
escala—, no los hechos. Y el retrato se arregla; los hechos no habría cómo. El riesgo no es una multa: es la **desnaturalización** del
vínculo, con CTS, gratificaciones, vacaciones y EsSalud retroactivos desde el
inicio — y multiplicado por tres.

**Lo que ya está bien:** el cuadro de categorías que se publica al equipo bajo la
Ley 30709 **no los cuenta ni los incluye en las bandas** desde la 0145: filtra
por `tipo_vinculo = 'planilla'`. El documento legal no dice que estén dentro de
la escala. El retrato queda en las pantallas internas.

**✅ Y el indicio más caro de todos quedó cerrado el 2026-08-08.** El sistema les
medía **tardanza y salida anticipada**, y las guardaba: 524 jornadas de personas
no sujetas a horario. Un registro de tardanzas no es un dato de más — es
**control de jornada**, el indicio más directo de subordinación que existe, y lo
fabricaba CAYLA sobre sí misma día a día. La
[`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql)
lo cierra en la raíz —`fn_recalcular_jornada` deja de medir a quien no está
`en_planilla`, y con eso los seis consumidores quedan correctos sin tocarlos— y
limpia lo ya guardado. Confirmado en producción: `mediciones_que_sobran: 0`. Sus
**horas sí se siguen calculando**: de ellas depende lo que cobran (prueba 149).

Salió de una frase de Felipe y de ninguna auditoría: «era RXH, ellos no están
sujetos a horarios, solo lo puse como referencia». Ninguna de las diez revisiones
independientes lo vio, porque para verlo hay que saber **qué es cada persona**, y
eso no está escrito en el código.

**Y uno de los tres es un frente aparte: Carlos tiene rol `admin`.** Eso le da
todas las sedes, todos los datos personales del equipo —**cuentas bancarias y
DNI incluidos**— y la capacidad de firmar despidos.

**Lo que hace falta NO es quitarle el acceso.** Se evaluó el 2026-08-07 y se
descartó por dos razones: su área es Desarrollo Organizacional, que necesita esos
datos para trabajar; y `admin` y `lider_do` están en el mismo grupo de permisos
—los dos pasan por `puedeVerIdentidad`—, así que bajarlo de rol **no reduciría
nada**. No existe un nivel intermedio. Felipe confirmó además que es de absoluta
confianza, y eso no está en discusión.

**Lo que falta es el papel.** La Ley 29733 no pregunta si la persona es
confiable: pregunta si CAYLA puede demostrar quién accede a los datos personales
y bajo qué obligación. Un trabajador en planilla está sujeto al deber de reserva
por su contrato y por el RIT. **Un locador solo lo está si su contrato de
locación lleva la cláusula de confidencialidad y tratamiento de datos.**

Es una cláusula, no un cambio de sistema — y aplica a los tres, no solo a Carlos.
Vale preguntársela al mismo abogado o contador que revise el vínculo.

Y el agravante: **el expediente lo arma el propio sistema.** La pantalla de
Equipo los nombra encargados, les asigna un área y les pone un rango de la
escala salarial. Es prueba escrita, generada por CAYLA.

**Si son socios, cobrar por honorarios es correcto y común.** El problema no es
el vínculo: es que la ficha los describe como encargados de equipo, cargo que no
les agrega autoridad —si son socios ya la tienen— y en cambio construye la
prueba de lo contrario. Este archivo ya lo había anotado antes como un problema
de permisos («el rol de Catherine está al revés de su papel»); es más que eso, y
son tres.

**Lo que hay que decidir:** qué son para CAYLA —socios, dirección, asesores
externos— y alinear rol, área y rango con esa respuesta. Son tres campos por
persona, editables desde Equipo; ninguno cambia lo que cobran.

**✅ Decidido el 2026-08-07 y con pieza construida:** Catherine es **socia**;
Carlos y Claudia, **asesores**. La
[`0182`](../supabase/migrations/0182_el_cargo_dice_que_eres_el_rol_dice_que_abres.sql)
agrega un campo `cargo` para escribir **qué es** una persona sin tocar lo que
puede abrir — se descartó a propósito meter «socio» y «asesor» en el enum `rol`,
porque `rol` no es un cargo sino una llave de permisos. Con el cargo escrito, la
pantalla deja de llamarlos encargados y el sistema deja de armar el expediente
en contra. **Comprueba si ya está pegada** con `./scripts/que-falta-pegar.sh`.

**Lo que YA se verificó, y no hace falta volver a mirar** (2026-08-07): el
dinero está bien. A un `rxh` no se le calcula movilidad ni EsSalud (0117), ni
educación (0120), ni gratificación, CTS, vacaciones o el 9% de la Ley 30334
(0160, con la prueba `127`). Lo único que recibe es su pago base, que es lo que
se le transfiere. **No hay provisiones indebidas ni plata de más.**

### A.2.b.bis · A quien cesa se le paga dos veces el mismo mes, y de más

⚠️ **LA CAUSA YA ESTÁ CERRADA — lo que sigue abierto es dinero ya pagado.** Los
dos arreglos de código que esta sección pedía están en producción desde el
2026-08-13 (ver «Lo que ya está hecho», más abajo). Lo que queda no lo arregla
ninguna migración: es una decisión por persona. Quien lea esto en una sesión
nueva no tiene que volver a investigar el divisor.

**Medido en producción el 2026-08-10, con las dos consultas que quedan en
`scripts/sql-manual/`.** Son dos defectos distintos que se dan la mano, y
conviene no mezclarlos.

#### 1 · El divisor: la liquidación paga inflado — **S/1,097.67 en 7 personas**

`fn_planilla_calcular` reparte el sueldo mensual entre los días **del rango que
se le pida**:

```
v_dias := (p_fin - p_ini) + 1;   v_base := 6.5 * v_dias;   pago := horas * salario / v_base
```

`fn_liquidacion` (0164:103) es **la única en todo el sistema que pide un rango
parcial** — del inicio del periodo a la fecha de cese, «ni un día más». Con menos
días el divisor se encoge y el mismo trabajo se paga más. Quien cesa el día 10 de
un periodo de 31 cobra ~3× lo suyo.

El encabezado de la 0164 lo justifica con una premisa **falsa**: dice que un
rango parcial se calcula bien porque «es lo que usa la pantalla de planilla con
el periodo en curso». No lo es — la pantalla usa `fn_proyeccion_periodo`
(0105:493), que pasa el periodo **entero**; lo parcial viene de que aún no hay
marcajes, no del rango.

**Seis de siete casos cuadran al segundo decimal** con la proporción que predice
el divisor. La séptima, **Ytamar Cueva**, no: 1.53× pagado contra 1.11× que
justifica el rango. Unos S/45 vienen de otra cosa y hay que mirarla aparte.

⚠️ **La prueba 130 no puede cazarlo**: compara la liquidación contra
`fn_planilla_calcular` con el **mismo** rango parcial. Se compara consigo misma.

#### 2 · El doble registro: **S/1,145.87 en 6 personas**, periodo 28/06–28/07

`liquidacion_pagada` aparece en **un solo archivo de todo el repositorio** (la
0167). Ni `fn_planilla_calcular`, ni `fn_planilla_congelar`, ni la pantalla de
Planilla la leen jamás. La etiqueta «ya no está» es puramente visual.

Las seis dicen **«primero el periodo, después la liquidación»**: el 28/07 se
cerró el periodo con ellas dentro —habían cesado entre el 16 y el 25— y después
se pagaron sus liquidaciones, que volvían a incluir ese mismo mes.

**Si el dinero salió dos veces solo lo dice el extracto bancario.** El sistema lo
tiene registrado dos veces; eso es lo que se puede afirmar.

#### Lo que ya está hecho

Las dos cosas que esta sección esperaba **están aplicadas en producción el
2026-08-13**, comprobadas pidiéndole el `md5` a producción y no por la fecha del
commit:

- **El cartel** — la [`0210`](../supabase/migrations/0210_la_planilla_ve_la_liquidacion_que_ya_se_pago.sql)
  hace que la pantalla de Planilla diga, junto a quien cesó a mitad de mes, que
  ya cobró su liquidación: cuándo y cuánto. Sigue siendo un cartel y no una
  exclusión automática, a propósito.
- **El divisor** — salió como la
  [`0239`](../supabase/migrations/0239_la_hora_vale_lo_que_vale_el_mes_no_lo_que_dura_la_consulta.sql),
  no como la «0211» que esta tabla esperaba. `fn_planilla_calcular` ya no saca el
  divisor del rango que se le pasa: **el rango decide QUÉ entra —marcas,
  feriados— y el periodo cuánto vale la hora**. Los siete llamadores que pasan el
  periodo entero no se movieron ni un céntimo; la única llamada cuyo resultado
  cambia es la de `fn_liquidacion`.

Y el 2026-08-14 se cerró también el mecanismo, que era lo que quedaba vivo:

- **La liquidación deja de cobrar dos veces el mes** — la
  [`0243`](../supabase/migrations/0243_la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago.sql)
  le resta al sueldo del periodo lo que la foto del pago ya registra para esa
  persona. Si el periodo no está congelado no hay nada que restar y el resultado
  es idéntico al de antes, al céntimo.
- **Y la 0243 deja de pagar de menos y de atascar el cierre** — la
  [`0244`](../supabase/migrations/0244_la_0243_deja_de_pagar_de_menos_y_de_atascar_el_cierre.sql),
  seis bordes que la anterior dejó abiertos. El grave: restaba también la foto de
  un periodo **revertido**, donde el dinero nunca salió (S/1,393.27 donde tocaban
  S/2,143.27). Los otros: una foto negativa inflaba, `congelar_pendientes()`
  abortaba sobre un mes histórico, y el freno de congelar no se levantaba al
  aplicar el descuento — podía dejar el cierre del mes sin salida.

Las dos verificadas pidiendo el `md5` a producción antes y después de pegar.

El botón **«💸 Ya le pagué aparte»** (`planilla/page.tsx:1268`) sigue siendo la
vía para el periodo en curso: registra el descuento y deja el total en cero. Y
ahora la cifra que descuenta ya es de fiar, que era la objeción para no usarlo.

⚠️ **Y una trampa que costó un rechazo en producción, para quien pegue SQL acá:**
un comentario NO es inerte. El editor de Supabase trocea el script antes de
mandarlo y su troceador no ignora los comentarios, así que un delimitador de
dólar citado dentro de un `--` —escribir `do $mig$` al explicar otra migración—
parte el script por donde no es y falla con un error que apunta a otro sitio
(`relation "v_src" does not exist`). Ninguna prueba local lo caza: psql sí lee
comentarios.

#### Lo que queda por hacer

| Qué | Cuándo |
|---|---|
| ~~**Anular la liquidación de Rufina Salvatierra**~~ | ✅ **anulada el 2026-08-14**. Versión 2 anulando la 1, con el motivo escrito; la v1 sigue visible. La anulación nombró el descuento de S/358.73 que queda vivo y **se queda**: ese es el adelanto que sí se le pagó, no un descuento dictado por el freno |
| **Revisar el extracto** de finales de julio para las seis, y el de agosto para ella | esta semana. Es lo único que distingue «registrado» de «pagado» |
| **Decidir persona por persona** qué se hace con lo que sí haya salido de más | después del extracto: sin él, no se sabe qué hay que decidir |
| **Decisión pendiente de Felipe:** la rama que falta en el aviso de `fn_liquidacion` | sin fecha. Es donde la frase «quedan descuentos vivos» llegaría a los ojos que deciden, pero son 12.821 caracteres que se pegan a mano para reescribir algo que funciona. Hoy el aviso llega igual, porque el único camino para anular es el SQL Editor |

⚠️ **CUIDADO CON ESTA SECCIÓN: sus cifras son de lo REGISTRADO, no de lo
transferido.** El 2026-08-14 se descubrió cómo se rompe esa suposición.

**El caso de Rufina, que es el patrón.** Su liquidación figura pagada el 10/08
por S/1,106.82 y **ese dinero nunca salió del banco**: estaba en periodo de
prueba, no llegó a entrar a planilla, y lo único que se le pagó fue un adelanto
de S/358.73 el 06/08, fuera de planilla. Alguien apretó «Liquidación pagada» y el
sistema congeló una foto de algo que no ocurrió.

Y el importe estaba mal por partida doble: se congeló **tres días antes** de que
la [`0239`](../supabase/migrations/0239_la_hora_vale_lo_que_vale_el_mes_no_lo_que_dura_la_consulta.sql)
llegara a producción, así que salió con el divisor viejo — inflado unas 3.1
veces. Lo que de verdad ganó del 29/07 al 07/08 son **S/298.73**, leído en la
pantalla ya corregida. O sea que con el adelanto cobró S/60 de más, no mil.

**Nadie cobró de menos.** Y de lo que parece cobrado de más, el sistema solo
puede afirmar lo que tiene registrado: **si el dinero salió, lo dice el extracto
bancario y nada más**. Esa frase ya estaba escrita más arriba desde el 10-08; el
caso de Rufina demuestra que no era una cautela retórica.

### A.2.c · Los CUSPP ya están cargados — quedan dos, y dos falsos positivos

**Resuelto el 2026-08-13.** La columna estaba vacía de punta a punta el
2026-08-10; hoy tiene **15 códigos**, cargados desde la hoja del contador
(«072026 Planilla CAYLA Felipe.xlsx») con
`scripts/sql-manual/ficha_cuspp_2026-08-13.sql` — fuera de git, lleva DNI.

**Por qué importaba.** El CUSPP es el identificador de la persona dentro del
sistema privado de pensiones: es lo que permite que el aporte declarado llegue a
**su** cuenta individual y no se quede sin atribuir.

**Se emparejó por DNI y no por nombre**, y no es un detalle de implementación: en
el equipo hay **dos Ramírez Gomez**, y la hoja trae el código de Sandra Melissa.
Por nombre se le habría escrito a Lizzelott Estefany — el aporte de una a la
cuenta individual de la otra.

**Lo que falta, y es corto:** el CUSPP de **Carmen Sanándres** (LIM, Profuturo) y
de **Lizzelott Estefany Ramírez Gomez** (CCO, Integra), que no venían en la hoja.
Se piden al contador. Aparte, **Kerin Guevara** (TRU) no tiene régimen de pensión
cargado: primero eso, y si sale ONP no lleva CUSPP.

**Los dos falsos positivos de la pantalla ya están corregidos y desplegados**
(2026-08-14).
`/admin/datos-personales` le pedía «falta CUSPP» a **Catherine Pereyra** y
**Claudia Pereyra**, que cobran por **recibo por honorarios** (ver
[A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado)). Un
locador no entra al T-Registro como trabajador: ese aviso no lo podía completar
nadie, nunca — y un aviso permanente e imposible es lo que enseña a ignorar los
avisos que sí importan.

La condición vive ahora en `leCorrespondeCuspp` (`packages/shared/src/vinculo.ts`)
y no suelta en la pantalla, porque son **dos** las que preguntan lo mismo: el
aviso de ficha incompleta y la exportación del padrón al contador, que también
lleva la columna CUSPP. Escrita dos veces, la exportación habría seguido pidiendo
lo que la pantalla ya dejó de pedir. Y usa `esPrestadorDeServicios`, no un
`!en_planilla`: si el campo no viaja en el JSON, el defecto seguro es **seguir**
pidiendo el CUSPP a las veinte que lo necesitan, no dejar de pedírselo en
silencio. Ese caso está en `tests/vinculo.test.ts`.

Por el mismo motivo dejó de pedírsele a una locadora el **régimen de pensión**:
CAYLA no le retiene aporte, así que ese dato no es de la empresa.

De paso: que las dos locadoras **tengan un régimen de AFP asignado** es en sí un
indicio más de los que describe A.2.b. **Decisión de Felipe (2026-08-13): se
queda.** Después de la 0242 ese dato no alimenta ningún cálculo, y saber en qué
AFP están es información útil. No volver a proponer borrarlo.

**Sobre el CHECK que se había descartado por falta de datos:** ahora hay 16
códigos reales y los 16 tienen la misma forma —6 dígitos · 5 letras · 1 dígito—
y las 5 letras se derivan del nombre (inicial del nombre, inicial de cada
apellido, 4ª letra de cada apellido). El script lo comprueba fila por fila, y es
lo que da confianza de que ninguna se corrió al copiar la hoja. Pero **sigue sin
ponerse un CHECK**, y ahora por una razón medida y no por falta de datos: 16
casos no prueban que un CUSPP antiguo, o el de alguien con un solo apellido,
tenga esa forma. La validación vive en el script que carga, donde un rechazo se
revisa a mano; en la columna, rechazaría en silencio un código legítimo.

### A.2.c.bis · La guarda que impide retenerle AFP a un locador no está escrita

> **HOY NO CUESTA NADA.** Felipe confirmó el 2026-08-13 que a los tres locadores
> **nunca se les ha retenido AFP**, y es coherente con lo medido: su base es 0
> porque nadie les llenó `sueldo_base_legal`. Esto **no es plata mal pagada y no
> hay nada que devolver.** Es un riesgo latente, y el valor de anotarlo es que la
> protección que hoy funciona **no está escrita en ninguna parte**: funciona por
> casualidad.
>
> **✅ CERRADO. La 0242 está aplicada en producción** (2026-08-13). El md5 de
> partida se confirmó en el SQL Editor antes de pegarla, y las cinco
> comprobaciones salieron en verde: las 4 marcas nuevas puestas, la guarda de la
> base presente, y la 0239, la 0236 y la 0233 intactas. Con prueba propia
> (`supabase/tests/183_un_locador_no_tiene_base_imponible.test.sql`).

**Qué es exactamente el riesgo.** El descuento previsional es
`base imponible × tasa`, y hoy da cero para un locador porque su base es cero. Pero
la base es cero **por un dato en blanco, no porque el sistema sepa que es locador**.
El día que alguien abra su ficha en `/admin/equipo` y confirme su base legal —una
acción normal, con buena intención, en un campo que el panel pide— empieza a
retenérsele AFP en silencio. Nadie relacionaría las dos cosas.

Y hay un segundo camino, más corto: marcarle **`con_hijos`** a una locadora le paga
S/113 de asignación familiar y además le abre base para el descuento, incluso con
`sueldo_base_legal` en blanco.

**Medido el 2026-08-13** contra la función vigente (`fn_planilla_calcular`, md5
`7d67ff3c1d769ebffc3de0af20ab83fe` = 0239), con cuatro locadoras idénticas salvo
esas dos columnas. Salió de preguntarse qué hace el sistema con la AFP después de
cargar los CUSPP. Los montos de abajo son **lo que pasaría**, no lo que pasó:

A un locador no se le retiene AFP: la locación de servicios no genera retención
previsional del pagador. El encabezado de la 0193 dice que eso ya está a salvo
porque «su básica es 0». **Es cierto solo si alguien le puso `sueldo_base_legal`
en NULL a mano** — y esa columna tiene `DEFAULT 1130.00` (el RMV, 0103).

| `sueldo_base_legal` | `con_hijos` | básica | asig. familiar | **AFP retenida** |
|---|---|---|---|---|
| 1130 (el DEFAULT) | sí | 1192.09 | 113.00 | **168.62** |
| 1130 (el DEFAULT) | no | 1192.09 | 0.00 | **154.02** |
| NULL | sí | — | 113.00 | **14.60** |
| NULL | no | — | 0.00 | 0.00 |

**Son dos defectos y no se mezclan:**

1. **La básica.** El descuento de pensión es `bri.base × tasa` y es **el único
   concepto sin guarda de vínculo**. Todos los demás la llevan escrita: EsSalud y
   movilidad (0117), educación (0120), sobretasas (0193). Este descansa en que la
   base sea 0 — y lo decide el default de una columna. Que hoy funcione o no es
   una coincidencia, no un diseño.
2. **La asignación familiar.** Entra al pago **y** a la base sin condición de
   vínculo, y es la única vía que inventa base incluso con `sueldo_base_legal` en
   NULL. Aparte del descuento, cobrarla ya está mal: la Ley 25129 es para
   trabajadores del régimen laboral privado. Y es el argumento exacto de la 0117
   con la movilidad — **el concepto que protege a una trabajadora de planilla es
   el que incrimina en un RxH**. Un locador que cobra asignación familiar es un
   indicio de laboralidad más para
   [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).

**Lo que EsSalud sí hace bien:** cero en las cuatro filas. La guarda de la 0117
sigue en pie, y eso acota el problema — es previsional, no de aportes de la
empresa.

**Cómo lo arregla la 0242.** Guarda la base imponible COMPLETA —
`case when pe.en_planilla is not true then 0 else …` — y no cada término suyo, para
que un concepto que se agregue mañana quede excluido sin que nadie tenga que
acordarse; y le pone la condición de vínculo a la asignación familiar en **los dos
sitios** donde vive (el concepto del JSON y el término del `total`): arreglar solo
uno dejaría la boleta mostrando 0 mientras el total lo sigue cobrando.

Medido después de aplicarla en local: las cuatro locadoras quedan idénticas entre
sí y su total es exactamente su pago por horas — ya no depende de
`sueldo_base_legal` ni de `con_hijos`. Y **el testigo de planilla no se movió ni un
céntimo** (AFP 195.73 · asignación 113.00 · EsSalud 136.34 · provisiones 276.71,
iguales antes y después). Eso es la mitad del valor de la prueba `183`: apagarle el
descuento a un locador y de paso romperle la retención a quien sí aporta habría
sido mucho peor que el defecto original, y ninguna pantalla lo mostraría.

**Lo que sigue igual, y es deliberado:** el pago por horas de un locador. Es el
razonamiento de la 0085 que la 0117 repitió — medir horas para saber cuánto pagar
es medir un RESULTADO; fiscalizar una CONDUCTA es la prueba de subordinación.

**Para volver a medirlo en dos segundos cuando haga falta:**
[`que_pasa_con_la_afp.sql`](../scripts/sql-manual/que_pasa_con_la_afp.sql). Su
BLOQUE 2 no rehace la aritmética, le pregunta a `fn_planilla_calcular` por el
periodo vigente y devuelve una fila por cada locador con retención. Lo esperado
—y lo que Felipe ya confirmó por su lado— es **cero filas**. Queda escrito con la
consulta al lado por la misma razón que A.2.d: un riesgo latente sin forma de
volver a medirlo es una frase que envejece sola.

### A.2.c.ter · El freno de CUSPP bloqueaba Planilla entera, y nunca pasó por git

**Encontrado y retirado el 2026-09-16** (migración 0476). Producción tenía,
dentro de `fn_planilla_congelar`, un cuarto freno además de los tres que sí
están en este repo (0243/0244, 0284, 0326): si a cualquier persona de
«Planilla» o «Prueba» afiliada a una AFP le faltaba el CUSPP, `raise
exception` — nadie del grupo se congelaba, aunque solo a una le faltara el
dato. Se veía como un toast al intentar «Confirmar pago y congelar», con el
periodo quedando ABIERTO.

**Nunca hubo una migración para eso.** Su propio comentario se etiquetaba
"CAMBIO 0397", pero la 0397 real de este repo es
`la_practicante_cobra_movilidad_y_educacion` — un cambio completamente
distinto. Alguna sesión lo pegó directo en el SQL Editor de producción y
nunca llegó a escribir el archivo: mismo defecto que la 0177 y la 0243
(ver `CLAUDE.md`), solo que acá ni siquiera se perdió un archivo — nunca
existió.

**Por qué se retiró y no se ajustó.** El dato en sí importa —el CUSPP es lo
que le permite a SUNAT/la AFP atribuir el aporte a la cuenta individual de
cada quien—, pero el freno contradecía una decisión ya tomada y medida en
este mismo repo (`scripts/sql-manual/que_pasa_con_la_afp.sql`, agosto 2026:
"el CUSPP no cambia ni un sol", y no tenerlo nunca debía frenar nada) y
bloqueaba a las 21 personas de «Planilla» por un dato que le falta a UNA sola
—Carmen Sanándres, LIM, Profuturo; también Lizzelott Ramírez Gomez, CCO,
Integra— pendiente de pedírselo al contador desde el 2026-08-13 (ver A.2.c
arriba). Exactamente el falso positivo que este proyecto ya identificó como
el peor error posible.

**Lo que se queda igual:** el aviso de ficha incompleta en
`/admin/datos-personales` (`leCorrespondeCuspp`) sigue avisando sin bloquear.
Y los otros tres frenos de `fn_planilla_congelar` no se tocaron.

**Pendiente real, sin freno detrás ahora:** el CUSPP de Carmen y de
Lizzelott se sigue debiendo pedir al contador — ver A.2.c.

### A.2.d · Dos campos para «¿tiene hijos menores?» — uno paga y el otro declara

**Medido el 2026-08-10: hoy no cuesta nada.** De las 21 personas activas en
planilla, las 21 concuerdan. Cero desacuerdos, cero fichas sin el dato. Esto
queda escrito como riesgo latente, no como pendiente urgente — y con la consulta
que lo vuelve a medir en dos segundos:
[`los_dos_campos_de_hijos_no_se_hablan.sql`](../scripts/sql-manual/los_dos_campos_de_hijos_no_se_hablan.sql).

| Campo | Quién lo escribe | Qué hace |
|---|---|---|
| `personas.con_hijos` (0025) | pantalla de **Equipo**, con `fn_set_con_hijos` | **decide el pago** de los S/113 en `fn_planilla_calcular` |
| `datos_personales.hijos_menores` (0061) | pantalla de **Datos personales** | **es lo que sale en el padrón** al contador |

**Nada los mantiene de acuerdo.** Ninguna migración menciona los dos a la vez;
ninguna pantalla escribe los dos. Comprobado con `grep` sobre
`supabase/migrations` y sobre `apps/web`. Que hoy concuerden es mérito de quien
los ha ido llenando a mano, no del sistema.

Lo que puede pasar el día que se despisten: marcar «sí tiene hijos» en la ficha,
que el padrón se lo declare al contador, **y que la planilla abone S/0** porque
`con_hijos` se quedó en su `false` por defecto. O al revés — cobrar los S/113
mientras el papel que emite la empresa dice que no corresponden.

⚠️ **Y ojo con el arreglo fácil.** Fusionarlos en un solo campo toca el cálculo
de planilla, así que va con auditoría empírica contra el Postgres local en
`BEGIN … ROLLBACK`, como manda el `CLAUDE.md`. Lo barato y sin riesgo mientras
tanto sería que la pantalla de Datos personales **avise** cuando los dos
difieran: ya tiene dos comprobaciones cruzadas de esa forma exacta —cobra
asignación sin hijos registrados, y su inversa— y ninguna mira `con_hijos`.

*(De aquí salió también el arreglo del padrón que ya está hecho: imprimía «NO»
donde la verdad era «no se sabe». Ver `siNoSinDato` en
`packages/shared/src/labels.ts`.)*

### A.3 · Datos que hacen falta para seguir

**0) Nadie tiene contacto de emergencia — las 25, sin una sola excepción.**
Medido el 2026-08-07 con
[`que_falta_en_las_fichas.sql`](../scripts/sql-manual/que_falta_en_las_fichas.sql).
Si alguien se corta con una máquina en el taller de Lima o se descompensa en
tienda, **no hay a quién llamar**, y ese es el único momento en que el dato
sirve. Felipe los carga desde `/admin/personas`. En la misma pasada faltan **13
celulares** (decisión suya: van después) y la **fecha de nacimiento de Janis
Revilla**, sin la cual su bono de onomástico no se dispara nunca — la única del
equipo a la que le falta.

Las 20 de planilla están completas en lo que toca a plata: banco, cuenta,
documento y nombre legal. Lo que falta es todo del lado de **poder contactarlas**.
Corre la consulta para ver cómo va; ordena por quién tiene más huecos.

**0-bis) Tres correos hay que corregir a mano** (medidos el 2026-08-10 con
[`mediciones_antes_de_validar.sql`](../scripts/sql-manual/mediciones_antes_de_validar.sql)).
Quiénes son lo dice
[`quien_tiene_el_correo_mal.sql`](../scripts/sql-manual/quien_tiene_el_correo_mal.sql),
que además dice **dónde** se corrige cada uno — con cuenta creada el correo es
el usuario de acceso y la ficha no lo puede tocar, así que va por
`/admin/cuentas`.

- **Uno no tiene forma de correo.** Esa persona figura como ficha completa, sale
  así en el padrón que va al contador, y al intentar invitarla el sistema
  responde «no tiene correo registrado» — que es falso: lo tiene, mal escrito.
  Son dos estados distintos y la pantalla los confundía.
- **Dos están guardados con mayúsculas.** La pantalla ya no falla por eso (se
  comparaba en minúsculas contra el valor crudo, así que daba «cambió» para
  siempre y cada guardado terminaba en un error rojo y falso), pero el dato
  sigue en mayúsculas. Bajarlo va en migración, no en un `update` pegado a mano:
  un correo que es un login tiene consecuencias que hay que dejar escritas.

**Y lo que la misma medición descartó, para no volver a mirarlo:** ni un
documento sin dígitos, ni uno fuera del patrón que ya exige la 0125, ni una
cuenta bancaria con letras, ni un valor de `estado_civil` o
`grado_instruccion` fuera de `enums.ts`, ni una sede huérfana en
`parametros_laborales`. Los agujeros de validación que quedan son **teóricos
hoy**; valen por lo que impiden mañana, no por lo que haya guardado.

**a) Quiénes estudian y cuánto cuesta su curso** (del tipo `aurora 1 →
universidad S/520`). Con el nombre y el monto alcanza; se cargan de a uno en
`/admin/educacion` o con
la pantalla `/admin/educacion`. **Es la única de las
tres compensaciones que se puede destrabar hoy sin escribir una línea de
código** — `asignaciones_educacion` sigue vacía.

**b) La fecha de acreditación de CAYLA en el REMYPE.** Decide si queda algún
frente abierto de asignación familiar: quien haya ingresado antes de esa fecha se
rige por el régimen general, donde sí es exigible. La persona más antigua ingresó
el **2025-01-02**, así que si la acreditación es anterior, el frente es **cero**.

**c) El refrigerio real**, que deja el sustento de la movilidad atado a tus datos:

```sql
with dia as (
  select m.persona_id, (m.timestamp_marca at time zone 'America/Lima')::date as f,
         min(case when m.tipo = 'salida_almuerzo'  then m.timestamp_marca end) as sale,
         min(case when m.tipo = 'retorno_almuerzo' then m.timestamp_marca end) as vuelve
  from marcajes m
  where m.anulada_at is null and m.timestamp_marca >= now() - interval '90 days'
  group by 1, 2
)
select count(*) as dias_con_marcas,
       count(*) filter (where sale is not null and vuelve is not null) as dias_con_4_traslados,
       round(avg(extract(epoch from (vuelve - sale)) / 60) filter (where vuelve > sale)) as refrigerio_min,
       count(*) filter (where extract(epoch from (vuelve - sale)) / 60 >= 60) as dias_1h_o_mas
from dia;
```

### A.4 · Las dos comprobaciones de datos, que ahora se responden solas

*Acá había cuatro nombres escritos a mano. Tres cerraron y uno resultó ser una
decisión (ver [`historico.md`](historico.md)). Lo que queda son las dos preguntas
de fondo, convertidas en consultas: una lista de nombres envejece, una consulta
no.*

**¿Alguien inactivo conserva salario vigente?** Es plata que puede pagarse a
quien ya no trabaja. Debe devolver **cero filas**:

```sql
select p.nombres || ' ' || p.apellidos as persona, p.estado,
       a.salario_mensual_soles as salario_vigente, a.vigente_desde
from personas p
join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
where p.estado <> 'activo'
order by p.apellidos;
```

**¿Alguien en planilla lleva un mes sin marcar?** Puede ser vacaciones, permiso,
o que no esté marcando y nadie lo haya visto:

```sql
select p.nombres || ' ' || p.apellidos as persona, s.codigo as sede,
       max(j.fecha) as ultimo_dia_marcado
from personas p
join sedes s on s.id = p.sede_base_id
left join jornadas j on j.persona_id = p.id and j.entrada_ts is not null
where p.estado = 'activo' and p.en_planilla and not p.sueldo_fijo
group by 1, 2
having max(j.fecha) is null or max(j.fecha) < current_date - 30
order by 3 nulls first;
```

**~~El hueco de numeración 0108~~ — ✅ cerrado.** Los cinco huecos (0031, 0033,
0108, 0133, 0139) están investigados y explicados uno por uno en
[`scripts/hooks/huecos-conocidos.txt`](../scripts/hooks/huecos-conocidos.txt), y el
hook solo avisa de los que **no** estén ahí. La 0108 se descartó: su contenido lo
cubren la 0111, 0117, 0118, 0122, 0142 y 0150, y lo único exclusivo que tenía era
un `fn_planilla_calcular` del 29/07 con tarifa única de S/6 — fusionarlo habría
revertido ocho migraciones de planilla. Se recupera con
`git checkout 1b54c02 -- supabase/migrations/0108_*.sql` si algún día hace falta.

**~~El rango `caylo` pagaba educación sin techo~~ — ✅ cerrado el 2026-08-06.**
La 0140 lo retiró del catálogo por un solo lado: le borró el techo y lo dejó
fuera de `categorias_laborales`, pero los CHECK de dos tablas lo seguían
aceptando y el desplegable de Equipo lo seguía ofreciendo. Como
`fn_educacion_respeta_el_tope` «falla abierto a propósito» cuando no encuentra
techo, en vez de bloquear **pagaba**: con el comprobante de S/727, S/545.25 en
vez de S/180. La [`0178`](../supabase/migrations/0178_caylo_deja_de_poder_asignarse.sql)
lo sacó de los dos CHECK y reasigna a `cayla` a quien lo tenga (mismo nivel,
misma base, **no cambia lo que cobra**). Felipe la pegó y verificó los dos CHECK.
La pantalla ya está en producción: el desplegable ofrece seis rangos, sin `caylo`.

*Queda un SELECT por correr, y no urge:* si alguien **estaba** en `caylo`, la
0178 lo pasó a `cayla` en silencio y conviene decírselo — cobra igual, pero su
nivel se llama distinto en la boleta. La consulta está en la cabecera de
`aplicar_0178.sql`; busca el rastro en `correcciones_auditoria`.

**Lo que esto dejó como lección, y vale más que el arreglo:** el agujero no fue
que `caylo` existiera, fue que existiera **sin techo cargado**. La prueba
[`139`](../supabase/tests/139_caylo_deja_de_poder_asignarse.test.sql) no vigila
`caylo`: compara el CHECK contra `categorias_laborales` y exige que ninguna
categoría se quede sin techo. **Pero solo en CI.** `fn_educacion_respeta_el_tope`
sigue fallando abierto en producción, así que una categoría nueva cargada sin su
techo repite esto exacto. Está sin decidir si esa función debe pasar a bloquear.

---

## B · Lo que falta construir

| Qué | Bloqueado por |
|---|---|
| **Las bases declaradas** de los cuatro rangos altos — y hay que bajar **los dos campos**, `sueldo_base_legal` **y** `salario_mensual_soles` | confirmar los montos finales |
| **Cargar las declaraciones de ruta firmadas** | **de Felipe. Plazo: 28/08/2026.** El sitio donde subirlas ya existe |
| **Indicador del umbral de 20 trabajadores** — promedio corrido del ejercicio, con aviso al acercarse | nada. **Acordado: se construye después de cerrar el Seguro de Vida Ley** |
| **Versionar la RMV a S/1,230 y subir la escala** — [`0501`](../supabase/migrations/0501_la_rmv_sube_a_1230_y_la_escala_la_sigue.sql), prueba 395: **escrita, sin pegar ni fusionar** | pegarla **el 2026-10-01 y antes de fusionar** (ver «Guion de mañana», arriba) |
| **Versionar la RMV a S/1,300 y reajustar de nuevo colibrí, cayla y support** (asignación familiar a S/130) | **el segundo decreto**, «primer semestre de 2027» y sin fecha. Nada en el sistema avisa cuando salga |
| **Imprimir y firmar las ~20 renovaciones** — la pieza ya existe (`/admin/contratos`) y su SQL está al día | **la revisión legal del texto**, que no ha hecho nadie |

### El generador de contratos, tras la auditoría del 2026-08-24

La pieza está construida y auditada. **229 agentes, 74 hallazgos brutos, 18
sobrevivieron** a tres escépticos independientes cada uno. Ocho tocaban el papel
y están arreglados (PR #57); el detalle vive en ese commit, no acá.

**El que enseña algo:** el defecto grave no lo encontró la auditoría — lo
encontró Felipe diciendo al pasar «todo mi personal tiene contrato, solo que aún
no se ha escaneado». La pantalla decía «sin contrato» porque el generador no
tenía filas previas, y de esa confusión salía el TIPO del contrato: las veinte
renovaciones habrían salido como contratos nuevos, con un período de prueba de
tres meses «sin expresión de causa y sin derecho a indemnización» impreso a gente
con años de casa. Se arregló, y horas después la auditoría encontró **la misma
puerta por otro lado**: el tipo tampoco se reponía al cambiar de persona en el
desplegable. Un agujero cerrado en un sitio no está cerrado.

**Lo que falta antes de imprimir:**

1. **La revisión legal del texto.** No la ha hecho nadie. El plan la dejó marcada
   como obligatoria y sigue sin hacerse.
2. ~~Tres arreglos en SQL~~ — **cerrados el 2026-08-26 con la 0312**, ya pegada en
   producción (sus seis comprobaciones en `true`). Eran: la política `UPDATE` que
   le faltaba al bucket `contratos`, firmar un borrador viejo moviendo
   `personas.fecha_fin_contrato` hacia atrás, y anular sin devolverla.

   **Lo que enseñó y conviene no olvidar.** La primera versión de esa migración
   preguntaba «¿es el contrato más reciente sin anular?», calcando el criterio de
   `fn_contratos_tablero`. Sonaba coherente. Una revisión adversarial de 61
   agentes la tumbó: esa pregunta **la gana un borrador sin firmar**, así que
   anular el contrato firmado teniendo una renovación preparada NO devolvía la
   fecha — el defecto que la migración decía arreglar, sin arreglar, y con la
   migración convencida de lo contrario. Se reprodujo contra la base antes de
   aceptarlo.

   La pregunta correcta no era cuál se generó al final sino **de cuál viene la
   fecha**, y una fecha de vencimiento solo puede venir de un papel firmado. De
   ahí `fn_contrato_firmado_vigente_de` y `fn_contrato_refrescar_vencimiento`:
   una sola regla y un solo recálculo, que usan las dos rutas. Ninguna de las dos
   se concede a `authenticated` — sus usos son internos y conceder abriría por
   RPC lo que la 0292 cerró.

**Y una decisión de negocio que el código no puede tomar.** El contrato se emite
siempre bajo el **art. 57** del TUO del D. Leg. 728 —«inicio o incremento de
actividad»—, cuya duración máxima es de **tres años**; el art. 74 pone cinco al
conjunto de contratos sujetos a modalidad. Pasado el tope, el art. 77
desnaturaliza el vínculo a indefinido **por ley, sin que nadie lo decida**. Desde
el 2026-08-24 la pantalla lo **avisa** al fijar la fecha de fin, pero nadie ha
medido a quién le pasa: la respuesta necesita las fechas de ingreso reales, que
solo están en producción. Con casi toda la planilla a plazo fijo, además, la
causa objetiva —«el volumen no puede ser absorbido por el personal permanente»—
es la que hay que poder sostener ante una inspección.

**Descartado a propósito:** archivar en el sistema los contratos de papel
anteriores (decisión de Felipe, 2026-08-24 — las renovaciones los reemplazan).

### La 0128 sigue escrita y sin llamar

> ⚠️ **2026-09-30:** la **0501** la llama por primera vez, para subir colibrí (S/1,230) y cayla (S/1,245) por la
> RMV nueva —solo sube; ver la entrada de arriba—. Y la escala **sí está decidida** desde el 2026-08-04 (`rangos.ts`).
> Lo que sigue describe el estado de agosto y **no** debe leerse como vigente.

`fn_fijar_base_declarada(rango, monto, vigencia, omitir[])` baja **los dos**
campos que intervienen en el pago al mismo monto, versionando el salario vía
`fn_set_salario`. La migración **crea la función y no la llama**: crearla no mueve
ningún pago, llamarla sí.

**Los montos por rango no están decididos.** La cifra que circulaba acá
—colibrí/cayla 1,130 · support 1,290 · aurora 1,500 · oráculo 1,810 · archicaylo
2,670— fue un ejemplo ilustrativo de cuando se diseñó el sistema, no una
decisión de Felipe (aclarado el 2026-08-18); se retira para que nadie la lea
como acordada. Los montos reales, cuando se fijen, y las excepciones nominales
van en `scripts/sql-manual/aplicar_0128.sql` (ignorado en git por PII) — nunca
en este archivo.

**Por qué no se ha llamado — actualizado 2026-08-18, verificado contra el
código vigente (no solo contra este párrafo):** movilidad ✅ encendida ·
educación ✅ implementada y sumándose en `fn_planilla_calcular`
(`monto_educacion`, vigente en la 0263) · bono de onomástico ✅ implementado
(`0165`, S/180 desde el 29/07/2026, entra al pago por el bucket `bonos`). Los
tres conceptos SÍ están en el cálculo de planilla — lo que este documento tenía
mal. Lo que sigue sin confirmarse es si cada persona tiene sus datos cargados
(p. ej. la asignación de educación es por persona y contra comprobante). Y
`fn_fijar_base_declarada` **sigue sin llamarse**: nadie ha bajado ningún sueldo
base todavía, así que hoy la base sigue siendo la de antes.

El método para decidir esto sigue siendo medir contra Postgres local, en
`BEGIN … ROLLBACK`, con casos reales — no se repite acá con una cifra concreta
porque la que había era la misma que se retiró arriba por no ser una decisión.
Y como la educación es **por persona y contra comprobante**, a quien no estudia
bajarle la base le recorta el sueldo sin nada que lo reponga — para esa persona
se usa `p_omitir`, o una base propia más alta.

### El indicador del umbral de 20, y por qué vale construirlo

Dante zanjó las utilidades para 2025 y 2026, pero con una foto: 5 y 13 de
promedio. Ese 13 es un accidente del año de crecimiento —de enero a junio hubo
entre 5 y 8 personas, y recién desde julio hay 19—. **Si CAYLA mantiene 19 los
doce meses de 2027, el promedio de 2027 es 19.** A una contratación del umbral.

Y la persona número 21 no cuesta su sueldo: cuesta su sueldo **más el 8% de la
renta imponible de todo el ejercicio** repartida entre todos (D.L. 892,
comercio). Sobre los S/63,655 de 2025 serían ~S/5,092 al año que hoy no se ven en
el momento de decidir la contratación. El sistema tiene todos los datos para
calcularlo solo y mostrarlo **antes** de que se firme el contrato.

### Sobre la RMV

**Actualizado el 2026-09-30.** El decreto **salió**: **D.S. 015-2026-TR**, publicado el 2026-09-28. Llevó la RMV a
S/1,300 en dos tramos: **S/1,230 desde el 2026-10-01** (construido en la 0501, sin pegar; ver la entrada de arriba)
y **S/1,300** por otro decreto en el primer semestre de 2027 (**sin construir, sin fecha, y nada avisa cuando salga**).
La versión de agosto de esta sección decía que «el decreto no está publicado» y que eran «dos sentencias por cada
clave»: hoy se hace en **una migración** (la RMV, la asignación en sus dos sitios, la escala y lo que publica la
Política), y la asignación familiar **sí** se subió (S/123, irreversible).

⚠️ **Sobre el plazo, que Dante describió mal y aquí se confirmó.** Dijo que había que esperar al Congreso y a la
promulgación. La RMV **no se fija por ley**: se fija por **Decreto Supremo del Ejecutivo**, previa consulta al
Consejo Nacional de Trabajo, conforme al art. 24 de la Constitución (la subida a S/1,130 fue el **D.S. 006-2024-TR**
y ésta el **D.S. 015-2026-TR**, dos meses después del anuncio del 28/07). Se publicó de un día para otro y rige el
1° del mes siguiente. **La vigilancia se mide en semanas, no en meses.** Donde sí puede tener razón es en el bono
compensatorio para MYPE: eso es gasto público y probablemente sí necesita norma con rango de ley.

### La fila general de movilidad vale S/ 10.00 — decisión tomada, se queda

No es un descuido pendiente sino una **red deliberada** (Felipe, 2026-08-06):
quien esté en una sede sin tarifa propia cobra S/ 10.00 en vez de cero. Conviene
saber de dónde sale ese 10: es la **tarifa original de Trujillo** —su sustento lo
dice, «colectivo urbano de Trujillo a S/2.50 por tramo»—, que quedó sin
`vigente_hasta` cuando la 0142 abrió las filas por sede.

**El escenario que la activa: abrir una sede nueva.** Esa gente cobra S/ 10.00
desde el primer día sin que nadie haya mirado el pasaje de esa ciudad, y sin
aviso. Si algún día se prefiere que un dato faltante se note en vez de
rellenarse, se cierra con `vigente_hasta` y pasan a S/ 0.00 — hoy eso no movería
la plata de nadie.

---

## C · Lo que se descartó y no vuelve

Cinco cosas que sonaron graves y se cayeron al verificarlas. Quedan acá para que
no vuelvan a costar tiempo.

| Se dijo | La verdad |
|---|---|
| El límite del RER de 10 trabajadores por turno | **CAYLA está en Régimen MYPE Tributario** desde 2023 (ficha RUC). El RER no aplica. **No hay que mover ningún horario** |
| «Sobre 25% de conceptos no remunerativos se activa la presunción de salariedad» | **No existe ese umbral en la ley.** Era una regla de dedo mía |
| La asignación familiar se debe a todos los que tengan hijos | El régimen de **pequeña empresa NO la incluye** — las palabras aparecen cero veces en el TUO de la Ley MYPE y en la Ley 32353, leído en texto primario. **Pero a quien ya la cobra no se le puede quitar**: sería reducción unilateral de remuneración (art. 30.b) |
| Un pacto colectivo blinda la movilidad | Solo es requisito del inciso g) para festividades. Art. 9 TUO CTS: la denominación es irrelevante. **La firma no blinda, incrimina** |
| El SCTR es obligatorio por el taller | **No.** Se revisaron las 270 actividades del Anexo 5: la confección de prendas (CIIU 141x) no está. Evita S/1,600–2,500/año de un seguro que nadie exige |

**Y el techo que ordena todas las multas:** todas las de una misma inspección de
SUNAFIL topan en el **1% de los ingresos netos del año anterior** (art. 48.1-A del
Reglamento de Inspección). Con ~S/900,000 de facturación el techo es **~S/8,000**,
no las seis cifras que suman los hallazgos por separado. **Pero no se aplica
solo**: exige presentar la constancia de REMYPE y sustentar los ingresos netos.
Sin esos dos papeles se cobra el nominal.

---

## D · Consultas útiles que ya existen

| Archivo | Para qué |
|---|---|
| `huella_del_esquema.sql` | **¿Producción dice lo mismo que el repositorio?** Una fila: funciones, candados, columnas, y si queda texto con acentos rotos. Empieza siempre por aquí |
| `que_funcion_cambio.sql` | Solo si la anterior dice que las funciones difieren **con el mismo conteo**: manda las 199 huellas y señala cuál |
| `rescatar_lo_que_solo_vive_en_produccion.sql` | ⚠️ **Léelo antes de tocar cualquiera de las nueve que lista.** Trae su código para traerlo al repositorio |

**Y el prólogo que hace falta seguido:** `fn_planilla_calcular`, `fn_provisiones`
y `fn_set_tipo_vinculo` exigen sesión de admin, y el SQL Editor no la tiene. Dos
líneas al inicio lo resuelven:

```sql
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and nombres ilike '%Felipe%' and auth_user_id is not null limit 1),
  true);
```

---

## El diseño remunerativo — lo que la auditoría empírica fijó

Contra Postgres local con datos reales, en `BEGIN … ROLLBACK` como manda el
`CLAUDE.md`. **Sigue siendo la base del diseño, no es historia.**

**`pago_base` se calcula sobre `asignaciones_salario.salario_mensual_soles` —el
rango completo— y NO sobre `personas.sueldo_base_legal`:**

```
pago_base = horas × salario_mensual_soles / v_base
basica    = horas × least(sueldo_base_legal, salario) / v_base
```

**Declarar menos NO reduce lo que se paga.** Sumar movilidad, educación y bono
encima del rango completo sobrepagaría por el monto entero de esos conceptos —
del orden de **S/4,900 al mes** entre las 26 personas. Por eso al fijar las bases
declaradas hay que bajar **los dos campos** al mismo monto.

Con esa corrección, en un mes **sin feriados**:

| Rango | declarado → base | + movilidad | − pensión | = total | objetivo | necesita educ. + bono |
|---|---|---|---|---|---|---|
| colibrí | 1,129.55 | +270.00 | −147.52 | 1,252.03 | 1,320 | **67.97** |
| cayla | 1,129.55 | +270.00 | −160.54 | 1,352.01\* | 1,450 | **97.99** |
| support | 1,289.49 | +270.00 | −167.25 | 1,392.24 | 1,650 | **257.76** |
| aurora | 1,499.40 | +270.00 | −194.92 | 1,574.48 | 1,890 | **315.52** |
| oráculo | 1,809.28 | +270.00 | −232.31 | 1,846.97 | 2,250 | **403.03** |
| archicaylo | 2,668.94 | +270.00 | −348.56 | 2,590.38 | 3,000 | **409.62** |

*\*La fila de cayla del fixture tiene hijos, así que incluye S/113 de asignación
familiar; sin hijos necesitaría ~S/198.*

**Los días son 27, no 26.** En un periodo de 31 días con domingos libres hay 27
laborables, así que la movilidad a S/10 da **270**, no 260.

**Los feriados oscilan el total entre S/90 y S/196 por mes.** Por eso el diseño
**no puede cerrar exacto todos los meses**, y forzarlo con educación o bono sería
el reverse-engineering que hunde los conceptos (caso Albis). Cada concepto se fija
por su propio mérito y el total aterriza cerca del rango.

### Las decisiones del diseño (2026-07-31)

**En la boleta:** lo que CAYLA paga además —el EsSalud y las tres provisiones— va
en un bloque aparte, fuera de la tabla del pago, con la leyenda «no se descuenta
de tu sueldo». **Sin total y sin porcentaje**, por decisión tomada.

| Concepto | Decisión | Amparo |
|---|---|---|
| **Movilidad** | S/10.00 por día marcado en AQP y TRU, **S/12.00 en LIM** (0142) · 4 traslados · refrigerio de 1h15 habilita almorzar en casa. **Techo: ninguna tarifa diaria pasa del 4% de la RMV** (**S/45.20** hasta el 30/09/2026 · **S/49.20** desde el 01/10, con la RMV de S/1,230), con candado en la 0152 y prueba 119 | Art. 19 e) · PLAME **0909** ✅ confirmado |
| **Educación** | 75% del comprobante, tope por rango · vale para el trabajador **y/o sus hijos**, sin tope de edad | Art. 19 f) · PLAME **0202** ⚠️ falta confirmar el cero |
| **Bono cumpleaños** | **S/180**, igual para los 26, en el mes del onomástico, sin condición de antigüedad | Art. 19 g) · PLAME **0203** ⚠️ mismo caso |
| **Pensión** | Tasa real por persona (12.84%–13.06% u ONP 13%), desde el periodo abierto | — |
| **EsSalud** | 9% con piso de la RMV, visible como aporte de la empresa | Ley 26790 art. 6 |
| **Base de beneficios** | Igual al monto declarado de cada persona | decisión de Felipe |
| **Fuera de la estructura** | Felipe y Catherine | decisión de Felipe |

**La cláusula del bono, textual.** No usar la que decía «gratificación
extraordinaria a título de liberalidad»: invocaba el inciso a), que exige que el
pago sea *ocasional*, y hacía el gasto **no deducible** (art. 44 d) LIR).

> *Asignación por cumpleaños, otorgada con ocasión del onomástico del trabajador,
> conforme al literal g) del artículo 19 del D.S. 001-97-TR. No constituye
> remuneración computable para ningún efecto legal.*

**Sobre los convenios:** la **RTF 05449-4-2007** desconoció la movilidad de 14 de
21 trabajadores por falta de convenio exhibido. El inciso e) nombra el «pacto
individual» como la vía del monto fijo. La sentencia para encender la tarifa, con
su memoria de cálculo completa, está en la cabecera de la 0118.

**El candado de la declaración NO está encendido.** Cuando el tablero esté
completo:

```sql
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('movilidad_exige_declaracion', 1, '<fecha>', '<por qué>');
```

---

## Correcciones a información que yo di mal

Quedan anotadas porque se tomaron decisiones sobre ellas.

| Lo que dije | Lo correcto |
|---|---|
| «El límite del RER de 10 trabajadores por turno es tu problema más caro» | **CAYLA está en Régimen MYPE Tributario desde 2023** (ficha RUC). El RER no aplica |
| «Sobre 25% de conceptos no remunerativos se activa la presunción de salariedad» | **Era mi regla de dedo, no una norma.** No existe porcentaje en la ley peruana |
| La cláusula del bono con «liberalidad» y «a discreción» | Invocaba el inciso a), que exige ocasionalidad, y hacía el gasto no deducible |
| «Ninguna función respeta `en_planilla`» | **Las de liquidación sí:** `fn_cts_trunca`, `fn_grati_trunca` y `fn_vacaciones_truncas` vía `fn_devenga_beneficios` |
| «Un pacto colectivo blinda la movilidad» | Solo es requisito del inciso g) para festividades. **La firma no blinda, incrimina** |
| «CAYLA es un instituto de idiomas» *(en un prompt de verificación)* | Es **CIIU 4641 — venta al por mayor de textiles**. Se descartó todo el análisis de IGV educativo que salió de ahí |
| «El problema de subir el cargo es que la URL firmada no lleva la identidad» | **Falso.** Era que Storage usa `ON CONFLICT … RETURNING` y faltaban dos políticas. Afirmado con más seguridad de la que había; lo destapó el log del contenedor, no el código |

---

## Notas del entorno

**Las pgTAP corren en esta Mac.** La clave es `db reset`, no `start`:

```bash
npx supabase db reset    # reconstruye desde cero y aplica TODAS las migraciones
npx supabase test db
```

Es la mejor verificación de una migración nueva —construye el esquema entero
desde cero— y la única forma de detectar una colisión de números: es lo que
destapó las dos `0158`, abortando con `duplicate key value violates unique
constraint "schema_migrations_pkey"`.

**`db reset` y no `db start`:** `db start` no reaplica nada si la base ya está
levantada, así que una migración nueva parece aplicar y en realidad no se probó.

**`supabase start` (el stack completo: Auth, Storage, Realtime) también
funciona** — comprobado el 2026-08-06. Hace falta para probar una subida de
archivos de punta a punta; sin él, Storage no responde y solo se puede simular
contra Postgres.

**Si las pruebas fallan todas a la vez con «relation "sedes" does not exist»**,
no es el código: el contenedor de Postgres se reinició vacío. Se arregla con `db
reset`. La base local es un laboratorio: no guarda nada que no se pueda
reconstruir.

⚠️ **Casi siempre hay varias sesiones trabajando en paralelo** — el 2026-08-06
había cinco además de la propia. Unas desde `.claude/worktrees/*`, y otras
**desde este mismo árbol**: comparten Postgres local, directorio de trabajo e
índice de git. Eso produce pruebas en rojo que no son tuyas, `estado.md`
reescrito a media edición, y un `git status` que dice `[ahead 2, behind 5]` y un
minuto después otra cosa.

```bash
./scripts/sesiones.sh
```

Dice cuáles están vivas, desde qué worktree, **cuál es la tuya**, si alguien
escribió en los últimos 10 minutos y el estado de la rama. Córrelo **antes** de
`supabase db reset`, de editar este archivo, o de fiarte de un `git status`.

No uses la lista de sesiones de la app: su campo `isRunning` dice `false` aunque
estén corriendo. El script mira los procesos del sistema, que no mienten.

Dos hábitos que se ganaron el 2026-08-06:

- **Commitea con `git commit -o <ruta>`.** El índice de git es compartido en este
  árbol: un `git add` + `commit` corriente puede llevarse dentro lo que otra
  sesión acabe de preparar.
- **No empujes si la rama lleva commits que no son tuyos.** Viajarán cuando su
  autor los empuje; publicarlos tú es publicar trabajo a medio hacer.

**Los dos guardianes que fallaban por esto ya están arreglados** (2026-08-06), y
los dos por la misma confusión — preguntaban por *el directorio de trabajo*
cuando debían preguntar por *lo que sale de esta máquina*:

| Guardián | Qué hacía mal |
|---|---|
| `scripts/hooks/numeracion.sh` | Listaba las migraciones con `ls`, así que los archivos sin commitear de otra sesión contaban como tuyos: te decía «renumera lo tuyo» por un choque que tu push ni llevaba. Ahora mira lo que agregan tus commits sobre `origin/main`. La comprobación de duplicados **sigue** mirando el árbol entero a propósito: dos archivos con el mismo número revientan tu `db reset` venga de donde venga el segundo |
| `scripts/desplegar.sh` | Frenaba por cualquier cosa sin commitear, incluidos `.sql` que el `.vercelignore` excluye — Vercel ni los sube, y el mensaje «subiría código que no está en git» era literalmente falso. Ahora lee el `.vercelignore` para decidir qué cuenta. Sigue frenando en seco si lo sin commitear es `apps/web` |

Vale la pena mirar con esa lente cualquier verificación nueva antes de
escribirla: **¿esto pregunta por lo que hay en el disco, o por lo que va a
salir?** Casi siempre es lo segundo.

**Queda un tercero con el mismo vicio, y por ahora se aguanta.** El `typecheck`
del pre-push compila el **directorio de trabajo**, no lo que subes: el 2026-08-08
frenó un push por un archivo `.tsx` que otra sesión tenía a medio editar, y al
minuto siguiente pasó sin tocar nada. Es falsa alarma, no error — se reintenta y
ya. Arreglarlo de verdad exigiría compilar contra un árbol aislado, que cuesta
más de lo que ahorra; lo que no se puede es olvidar por qué pasa y empezar a
empujar con `--no-verify`.

**El de `que_falta_pegar.sql` sí es de los buenos, y frenó dos veces el mismo
día:** el repo tenía migraciones que la consulta no listaba, así que le habría
dicho a Felipe «todo al día» ocultando justo las nuevas. Se arregla corriendo
`./scripts/que-falta-pegar.sh` y volviendo a empujar.

**Un bug que vale recordar:** `jsonb_build_object` admite **máximo 100
argumentos**. El objeto de la boleta estaba cerca del techo y cuatro campos
nuevos lo pasaron — compilaba y fallaba al ejecutarse. Ahora está partido en dos
unidos con `||`, y el generador cuenta los argumentos y falla si alguno se acerca
al tope.

---

## 🔴 Atender primero

0. **El freno del SQL a producción se puede saltar sin querer, y ya pasó dos
   veces.** El 2026-08-14 la **0243** —que cambia una liquidación por cese— quedó
   aplicada en producción con sus tres archivos **sin commitear**: el mismo estado
   exacto en el que se encontró la **0177** el 2026-08-07. Se rescató el mismo día.

   **`dame-el-sql.sh` no lo evitó, y no puede:** solo protege a quien lo usa. Si
   la migración se copia del editor —lo natural cuando la tienes abierta delante—
   el script no participa, y ni el hook de numeración ni `que-falta-pegar.sh` ven
   nada, porque los dos miran git. El agujero no está en el script: está en que
   **el camino cómodo no pasa por él**.

   **✅ La mitad barata ya está hecha** (2026-08-14):
   `scripts/hooks/migracion-sin-guardar.sh` avisa en cada push si hay una
   migración sin commitear, y distingue la recién escrita de la que **ya
   sobrevivió a un commit** — esa segunda no es trabajo en curso, es trabajo
   olvidado. No bloquea, por la regla que el propio hook ya tenía escrita para
   `types.ts`: lo que sale de la máquina se bloquea, lo que solo está en el disco
   se avisa. Con varias sesiones en paralelo, una migración a medio escribir es un
   caso legítimo constante, y frenar ahí repetiría los dos errores ya pagados
   (`desplegar.sh` el 2026-08-06 y `que-falta-pegar --check`, cuatro pushes en un
   día). Cinco casos probados, incluido el que cazó un `git add` con las rutas
   pegadas sin espacio — justo la línea que existe para copiarse.

   **La mitad cara ESTÁ CONSTRUIDA y espera fusión** — [PR #250](https://github.com/felipea92p-ux/cayla-dynamic/pull/250),
   2026-09-07. `que-falta-pegar.sh` dejó de leer el directorio de trabajo: la
   lista sale ahora de la unión de `origin/main` y `HEAD`, y la consulta hace
   además la pregunta al revés —qué tiene producción que no está guardado en
   ninguna parte—. Ver la entrada del 2026-09-07 más arriba para las cinco
   comprobaciones. **Este bloque se tacha el día que ese PR se fusione**, no
   antes.

1. **Julio: nadie tuvo descuento de pensión.** Medido el 2026-08-08 sobre el
   periodo 28-jun → 28-jul: `pension_descontada` = **S/0.00 para las 23
   personas**, y `con_tasa_de_pension` = 0. En agosto ya son 20 de 22, así que
   las tasas por régimen se cargaron entre un periodo y otro.

   **Es del contador, no del código, y hay que preguntárselo:** si él descontó
   por su lado, no pasa nada; si no, es un mes de aporte previsional sin hacer
   para todo el equipo. Pesa más que cualquier otra cosa abierta hoy — y CAYLA
   es agente de retención, así que una retención no hecha la termina pagando la
   empresa de su bolsillo.

2. **Veinte de los veintiún contratos vencen el 31 de diciembre de 2026.** Solo
   el de Paola termina antes. En una misma semana hay que decidir, redactar y
   firmar veinte renovaciones, y si una se pasa de fecha con la persona todavía
   trabajando, **el contrato se desnaturaliza a indefinido por el art. 77 del
   D.S. 003-97-TR** — no por decisión de nadie.

   El dato ya está en `personas.fecha_fin_contrato`; falta que Incidencias avise
   con antelación. Es una alerta chica, del mismo tipo que las de jornada.

3. **El terminal decide en dos sitios a la vez.** «Qué toca marcar ahora» vive en
   SQL (`fn_siguiente_tipo_esperado`) y en el navegador
   (`determinarSiguienteAccion`, `packages/shared`). Las dos ignoran ya las
   marcas anuladas, pero **arreglar una dejaba la otra rota** y nada avisa de la
   divergencia. Unificar, o al menos una prueba que compare las dos respuestas
   con los mismos datos y falle si difieren.

4. **Terminal, los «4 bordes graves» — reproducidos uno por uno el 2026-08-10.
   Tres de los cuatro no eran lo que decían.**

   | Borde | Veredicto medido |
   |---|---|
   | Marca rechazada anunciada como «Listo» | ✅ **era real a medias, y se arregló.** La cola ya guardaba la marca antes de enviar; lo que seguía mal era el CARTEL: la pantalla leía solo `ok` y tiraba `llego`, así que un rechazo del servidor se anunciaba igual que estar sin internet — «se sincronizará cuando vuelva la conexión», siendo mentira. |
   | Cola offline reenviada por UUID | ❌ **refutado.** `offline-db.ts:85` ordena por `timestampCliente`. |
   | Reloj de la Mac sin verificar desfase | ✅ **REAL Y ABIERTO.** Cero menciones de desfase en todo el terminal: el `timestamp_marca` que decide a qué día se paga sale del reloj de la Mac sin comprobar nada. Necesita decidir qué se hace cuando está corrido. |
   | Marca en dos sedes el mismo día «pierde una marca» | ⚠️ **exagerado.** No se pierde ninguna —`marcajes` es append-only— pero `fn_recalcular_jornada` hace `coalesce(v_sede_id, …)` y le atribuye el día entero a la sede donde marcó PRIMERO. Lo que sale mal es el Reporte por sede, no el pago. |

   Y el quinto que se miró de paso, `fn_auto_cierre` sin candado de periodo
   pagado: ❌ **refutado**, lo cerró la 0203 el mismo día.

5. ~~**Tardanza de más de 180 min invisible**~~ · ~~**el sistema mide la jornada
   de quien no está sujeto a horario**~~ — ✅ **los dos cerrados el 2026-08-08**
   por la [`0189`](../supabase/migrations/0189_una_tardanza_de_tres_horas_deja_de_desaparecer.sql)
   y la [`0191`](../supabase/migrations/0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql),
   aplicadas y confirmadas. Ver el apartado [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado)
   para lo que significaba el segundo.

6. ~~**Nueve funciones y dos columnas corren SOLO en producción**~~ — ✅ **cerrado
   el 2026-08-08.** La 0188 rescató cuatro; la
   [`0194`](../supabase/migrations/0194_el_interruptor_de_beneficios_por_persona_entra_al_repositorio.sql)
   y la [`0195`](../supabase/migrations/0195_las_cuatro_funciones_que_el_repositorio_no_conocia.sql)
   las cinco restantes. Aplicadas y confirmadas. Verificado con un `db reset`
   completo: reconstruida la base solo desde los archivos, todo sigue ahí.

   **Y lo que apareció al rescatarlas vale más que el rescate.** Lo que esas
   cuatro funciones tenían «de más» era **el candado de planilla pagada** que el
   repositorio no tenía: `fn_set_rendimiento` y `fn_quitar_rendimiento` se niegan
   a puntuar o despuntuar un mes ya pagado, y `fn_set_sueldo_base_legal` a
   cambiar la básica de quien tenga meses pagados con puntuación menor a 100.
   Cualquier migración que hubiera copiado del repositorio los habría borrado en
   silencio — lo mismo que la 0180 tuvo que reponer el mismo día.

   ~~⚠️ **EL INTERRUPTOR DE BENEFICIOS POR PERSONA NO ESTÁ CONECTADO.**~~ ✅
   **CERRADO por la [`0196`](../supabase/migrations/0196_tres_puertas_en_vez_de_una_para_los_beneficios.sql)**,
   el mismo día en que se midió arriba. Partió el booleano único en tres
   banderas (`fn_persona_devenga_beneficio(persona_id, tipo_beneficio)` con
   respaldo a `fn_devenga_beneficios(tipo_vinculo)` cuando no hay excepción
   cargada) — resolviendo también el problema de forma que este párrafo
   señalaba. Reconfirmado por la auditoría adversarial del 2026-09-04: los
   cinco consumidores reales (provisiones, planilla, las tres truncas de
   liquidación) ya leen la excepción por persona.

5. **Seguridad pendiente** (de `revision-2026-07-15/`):
   - Contraseña mínima 6 sin complejidad, sin cambio forzado en primer login —
     y son cuentas que ven salarios. **Abierto.**
   - ~~Las rutas de API devuelven el mensaje crudo de Postgres~~ — ✅ **cerrado el
     2026-08-06.** Las cuatro pasan por `mensajeDeError`, que deja pasar entero
     lo que escribimos nosotros (código `P0001`) y traduce lo demás; el detalle
     va a Sentry. `api/espejo` es máquina a máquina y devuelve un genérico a
     propósito. Lo blindan 15 pruebas en `tests/mensaje-error.test.ts`, una de
     ellas con una palabra de la lista negra que **solo** la rama `P0001` puede
     dejar pasar — las otras catorce seguían en verde con la rama desactivada.

6. **Partir `planilla/page.tsx`.** Maneja dinero, y es la pantalla más grande del
   sistema por lejos (`wc -l` lo dice; la segunda es `turnos`). Los tests SQL que
   fijan la matemática ya existen (`supabase/tests/10` y `20`); falta el refactor
   antes de seguir tocándolo.

7. **Quedan tres `"America/Lima"` sueltos** fuera de `fecha-lima.ts`, todos en
   `politica-salarial/page.tsx` (líneas 66, 77 y 236). La regla del `CLAUDE.md`
   es que no exista ninguno: el corte del día decide a qué fecha se le paga un
   marcaje. Aquí son fechas de publicación de un documento, no de pago — pero la
   regla vale igual, porque la próxima copia de esas líneas puede no serlo.

**El catálogo completo está en
[`hallazgos-abiertos.md`](hallazgos-abiertos.md)**: hallazgos vivos de una
auditoría por áreas con verificación adversaria, cada uno con su evidencia y su
arreglo.

**El patrón que se repite, y que conviene mirar antes que los síntomas:** la
misma regla escrita en dos sitios, y una corrección que arregla solo uno. Pasó
con «qué toca marcar» (SQL y navegador), con «qué es una falta» (pantalla y
documento), con «quién puede leer la planilla» (un revoke y ningún guard) y el
2026-08-06 con el formulario del cargo (escrito en una sección y no en la otra).
En todos, nadie se enteró hasta que alguien miró.

### Lo que la foto del pago sí cierra, y lo que no

**Sí:** un periodo pagado ya no puede cambiar de total en silencio. Si algo se
mueve, `fn_planilla_foto_diferencias` lo nombra persona por persona.

**No:** los periodos pagados antes de la 0096 tienen la foto *reconstruida* — es
el número del día de la migración, no el del día del pago. La pantalla de Costos
lo avisa arriba.

**Y una decisión pendiente que la 0096 hace visible:** cuando la foto y el
cálculo en vivo difieren, el sistema hoy solo lo *dice*. Nadie decidió todavía
qué pasa entonces — si se reabre el periodo, si se ajusta en el siguiente, o si
se deja constancia y ya. **Es una decisión de negocio, no técnica.**

## 🟡 Valioso pronto

- **Publicar la política salarial no tiene ningún freno.** Dos agujeros que se
  vieron el 2026-08-08 al quemar la versión 3: el aviso de «desactualizada»
  compara `md5(fn_cuadro_categorias())`, o sea **solo los datos** — cambiar la
  redacción no lo dispara y el botón sigue diciendo «Volver a publicar». Y nada
  compara el documento nuevo contra el vigente, así que el sistema aceptó
  congelar una versión **byte por byte idéntica** a la anterior, sin decir nada,
  reiniciando las constancias. Dos frenos chicos en una migración: guardar la
  huella del TEXTO y rechazar publicar una versión igual a la vigente.
- **Seis fichas incompletas** al 2026-08-08, con lo que falta a cada una visible
  en `/admin/datos-personales`. Dos casos no son campos vacíos sino datos que se
  contradicen: **Carmen Sanándres** tiene fecha de nacimiento en 2026 (su correo
  sugiere 1960), y **Angie Chávez** cobra asignación familiar teniendo cero
  familiares registrados — S/113 al mes sin respaldo, o al revés, falta cargar al
  hijo. Sin esas fichas Dante no puede cerrar el T-Registro.
- **Dos datos del T-Registro que el sistema no guarda:** sexo y nacionalidad. Se
  llenan a mano en la hoja del contador. El tercero era el CUSPP, que ya tiene
  campo (0198) y ya está cargado — ver
  [A.2.c](#a2c--los-cuspp-ya-están-cargados--quedan-dos-y-dos-falsos-positivos).
- **Pedirle al contador el CUSPP de Carmen Sanándres (LIM, Profuturo) y de
  Lizzelott Estefany Ramírez Gomez (CCO, Integra).** Son las dos únicas que
  faltan; no venían en la hoja de julio. Ver
  [A.2.c](#a2c--los-cuspp-ya-están-cargados--quedan-dos-y-dos-falsos-positivos).
- **Cargarle el régimen de pensión a Kerin Guevara** (TRU). Hoy cae a la tasa
  genérica de `configuracion.tasa_afp`, que es una aproximación: un dato faltante
  acá no se ve como un cero, se ve como un número plausible. Si sale ONP, no lleva
  CUSPP.
- **La ficha de Dante Ramal** (CCO) no existe: sin DNI no se le puede declarar.
  Va antes que cualquier dato previsional.
- **Los campos de presentación de un locador siguen mintiendo.**
  `basica_legal_prop`, `complemento_variable` y `base_essalud` muestran números
  (1192.09, 73.84 y 1305.09 en la medición) para alguien que no tiene
  remuneración básica. No mueven ni un sol —el aporte de EsSalud ya es 0— y se
  dejaron fuera de la 0242 para que fuera auditable en una pasada. Merecen su
  propia migración con su prueba.
- **El candado del periodo que quedó a medias.** Se acordó el 26-07: no dejar
  cerrar un periodo con días sin resolver. Ahora que la incidencia del almuerzo
  ya se puede cerrar desde la pantalla, el candado no bloquearía a nadie.
- **Blindar con pruebas lo que aún mueve dinero sin ninguna:** descanso
  sustitutorio, bono de puntualidad, provisiones, feriado triple.
- **Versionar 0031 y 0033**: existen solo como `scripts/sql-manual/aplicar_*.sql`
  (fuera de git por PII). Crear versiones con los datos personales parametrizados.
- **Grati/CTS — regla legal de regularidad**: la sobretasa de feriado entra solo
  si se percibió en ≥3 meses del semestre (promedio entre 6). Felipe pidió ver
  primero el impacto con
  [`consulta_impacto_regularidad_feriados.sql`](../scripts/sql-manual/consulta_impacto_regularidad_feriados.sql).
- **Colibrí en cargas**: ~22 pantallas y ~49 estados vacíos sin marca.
- **Integración Dynamic ↔ retail**: el puente de identidad **ya está hecho y
  en uso** desde el 2026-07-23 (`retail.personas`/`retail.sedes`, vistas
  `security_invoker` sobre `public.personas`/`public.sedes`, más
  `retail.ventas.usuario_id` con FK directa a `public.personas`) — no por el
  camino que `docs/integracion-retail/00-plan.md` proponía (API de solo
  lectura entre dos proyectos, amarrada por DNI), sino porque retail se mudó
  al mismo Postgres. Ese documento se reescribió el 2026-09-04 para decir
  esto. **Lo único abierto de verdad:** si los DATOS históricos (ventas,
  stock, activos, proveedores) viajaron en la mudanza — hay una señal
  concreta de que no, en LIM (`finanzas/activos` no muestra nada). Diagnóstico
  listo para pegar en `docs/integracion-retail/03-donde-quedaron-los-activos.sql`,
  solo lectura; falta que Felipe lo corra y pegue la salida.
- **Espejo a Google Sheets legible** (encabezados fijos, una fila por persona).

## 🟢 Dependen de Felipe / redondeo

- Datos personales: 5 fichas faltantes + celular/instrucción/estado civil (~13).
  Import SIN commitear PII.
- Validar factores de provisiones con el contador (MYPE: 8.33/4.17/4.17).
- **El rol de Catherine.** Tiene `supervisor_sede` en CCO, así que el sistema le
  da lo de una encargada de tienda —ver a la gente de CCO, firmar amonestaciones
  de CCO— y le niega lo que querría una accionista: ver las tres tiendas. Está al
  revés de su papel. ⚠️ **No es solo de permisos:** siendo locadora por
  honorarios, ese cargo la retrata como subordinada. Ver [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).
- **Cuatro personas con rol admin** (Carlos, Estefany, Felipe, Janis). Un admin ve
  todas las sedes, todos los datos personales —cuentas bancarias y DNI incluidos—
  y puede firmar despidos. Cuatro accesos totales en un equipo de 23.
  ⚠️ **Y uno de los cuatro, Carlos, no es trabajador de la empresa:** cobra por
  honorarios. Su acceso está justificado —trabaja en Desarrollo Organizacional— y
  no hay rol intermedio que lo reduzca; lo que falta es la cláusula de
  confidencialidad en su contrato de locación. Ver
  [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).
- Cuenta de Estefany (falta su correo) · revisar áreas reales de cada quien ·
  checkbox «encargada de piso» en Equipo · split mañana/tarde por sede.

---

## Decisiones tomadas (no reabrir)

- **Planilla**: régimen MYPE pequeña empresa, base 6.5 h, pago = salario × horas/(6.5 × días).
- **A Dante Ramal se le pagó por fuera antes de entrar al sistema, y eso NO se
  carga hacia atrás — se cuenta desde ahora.** Decisión de Felipe: el sistema es
  nuevo y no vale la pena complicarlo con historia previa.

  ⚠️ **Por qué está escrito aquí y no solo donde se investigó:** de
  `fecha_ingreso` cuelga el reloj de su CTS, su gratificación y sus vacaciones.
  Quien mire su devengado dentro de unos meses va a ver una antigüedad más corta
  de la real y va a querer corregirla. **No es un dato mal cargado: es una
  decisión.** El relato completo vive en la sección del 2026-08-14, dentro de un
  bloque que empieza tachado —y por eso esta línea existe: ahí nadie la iba a
  leer.

  Y un cabo que va con el vínculo de los locadores: **Dante es locador con monto
  fijo mensual**, el mismo indicio de laboralidad ya señalado para Carlos,
  Catherine y Claudia. Entra en esa lista; no se quedó fuera por haberse dado de
  alta después.
- **La CTS incluye el sexto de la gratificación** — encendido en producción el
  2026-08-05. La base pasa de sueldo pelado a sueldo × 13/12 (Art. 16 del
  D.S. 001-97-TR; en pequeña empresa la grati es media remuneración, así que el
  sexto vale sueldo/12). Sobre S/1,130 la CTS del año sube de 565.00 a 612.08.
  **Ninguna autoridad zanjó este punto para el régimen MYPE**: es derivación del
  TUO de la Ley de CTS y del documento del MTPE. Se eligió la lectura prudente
  —provisionar de más no es infracción, de menos sí—. Se apaga con una línea, y
  la prueba `126` blinda que el sexto no se cuele en la gratificación ni en las
  vacaciones. **Falta contárselo al contador antes del depósito del 15 de
  NOVIEMBRE de 2026**: si él calcula sobre el sueldo pelado, la discrepancia
  aparece el día del depósito. (Este párrafo decía «antes del depósito de mayo»
  y erraba por seis meses en contra: la CTS se deposita el 15 de mayo y el 15 de
  noviembre, y el sexto se encendió el 05/08, dentro de la ventana mayo–octubre,
  que es la que se deposita en noviembre.)
- ~~**A Carlos Espejo no se le toca el tipo de vínculo**~~ — **REVISADA Y
  REVERTIDA el 2026-08-08.** La decisión decía «se revisa el día que exista la
  excepción por persona»: ese día llegó con la 0196, que parte el sí/no en tres
  banderas. Carlos pasó a `rxh`, que es lo que es.

  **Qué cambió, medido:** deja de cobrar feriados (S/286.57 en un periodo
  completo), deja de generar EsSalud (S/134.81 que pagaba CAYLA) y deja de
  provisionar gratificación, CTS y vacaciones. **Su pago por horas no se movió un
  céntimo** — de eso vive, y es lo único que le corresponde a un locador.

  **Por qué se revirtió:** los hechos, dichos por Felipe el mismo día, no
  encajaban con el retrato. Cobra POR HORA, es cuadripléjico, trabaja desde su
  casa, no está sujeto a horario y marca cuando decide trabajar. Ninguno de los
  indicios de subordinación que lista la doctrina —horario fijo, instrucciones
  directas, equipos de la empresa, monto igual cada mes— aplica. Dejarlo como
  `planilla` era construir por escrito la prueba de una relación laboral que no
  existe. Ver [A.2.b](#a2b--los-tres-locadores-están-retratados-como-personal-subordinado).

  ⚠️ **Y quedó una pregunta abierta que solo puede cerrar el contador:** el
  sistema venía calculando S/134.81 mensuales de EsSalud por él. Si eso se
  declaró de verdad en la PLAME, Carlos está registrado como TRABAJADOR ante
  SUNAT y EsSalud, y entonces toda la discusión sobre indicios sobra — formalmente
  ya lo es. Si solo salía en pantalla y nadie lo declaró, no pasa nada. **No es lo
  mismo y hay que averiguarlo.**
- **El terminal marca sin PIN**, a propósito. No se puede usar una marca como
  prueba individual en un procedimiento disciplinario sin otro respaldo.
- **Fecha de ingreso = decisión de negocio, no cálculo.** Se edita persona por
  persona en Equipo; el botón masivo se eliminó (0041).
- **Disciplina**: Dynamic avisa y documenta, nunca sanciona solo (D.S. 003-97-TR
  art. 25: umbrales 4 consecutivas / 6 en 30 d / 16 en 180 d).
- **Una marca se anula, nunca se borra** (0081). El botón «Eliminar» no vuelve:
  para el cálculo y para el pago anular hace lo mismo, pero deja quién la quitó y
  por qué, y se puede deshacer.
- **Cuando falta el retorno del almuerzo, el sistema no inventa una hora.** Avisa
  y decide una persona. Las tres realidades posibles (se fue, volvió sin marcar,
  no tomó refrigerio) son indistinguibles para el sistema.
- **Corregir el tipo de una marca puede dejar el día roto a mitad de camino, y no
  se bloquea**: ese estado intermedio es el primer paso del flujo de arreglo. Se
  sella para revisión y el sello se levanta solo cuando el día cuadra.
- **Las actas de descanso ya subidas no se migran al almacén** (0175). Se leen
  donde están. Mover archivos con un script es lo que puede salir a medias.
- **Meta operativas TRU = 8** · **Melany y Catherine como encargadas** · **Janis
  admin + encargada de piso** · **Keyla/Raquel/Felipe: ingresos quedan 2026**.
