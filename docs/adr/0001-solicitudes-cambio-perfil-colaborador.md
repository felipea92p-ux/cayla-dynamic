# ADR 0001 — Solicitudes de cambio de perfil del colaborador

Fecha: 2026-09-07. Estado: implementado — migración
`supabase/migrations/0399_el_colaborador_propone_do_aprueba.sql`, prueba
`supabase/tests/316_el_colaborador_propone_do_aprueba.test.sql` (23/23 en
verde contra Postgres local, dentro de `BEGIN…ROLLBACK`, sin dejar rastro en
la base compartida).

⚠️ **Léase primero el addendum al final del documento** ("Correcciones tras
implementar, 2026-09-07"): el diseño original de este ADR asumía dos cosas que
resultaron falsas al escribir la migración real — que "Familiares" no existía
en el esquema, y que "nombre completo" vivía en `personas.nombres/apellidos`.
Ninguna de las dos era cierta. El cuerpo del documento de abajo quedó como se
escribió originalmente (para no reescribir la historia de la decisión), y el
addendum dice qué cambió, por qué, y qué se construyó de verdad.

## Contexto

Hoy, ningún campo del perfil personal (celular, dirección, estado civil,
cuenta bancaria, DNI, etc.) lo edita el propio colaborador. Todo pasa por
`apps/web/app/(admin)/admin/datos-personales/page.tsx`, exclusiva de
Administración/DO (`puedeOperarEquipo`), que escribe directo con
`fn_set_datos_personales` (un upsert de toda la fila) o, para tres columnas
más sensibles, con su propia función guardián (`fn_set_documento` para el DNI,
`fn_cambiar_regimen_pension` para el régimen de pensión, `fn_set_email` para el
correo de acceso).

Esta feature agrega una vía nueva, desde "Lo mío" (`/mio`): el colaborador
**propone** un cambio a su propio perfil, y Administración/DO lo aprueba o
rechaza. El valor real de la ficha no cambia hasta que se aprueba. Para varios
campos, la propuesta exige un documento de sustento.

No reemplaza la vía existente: `/admin/datos-personales` sigue siendo la
edición directa de DO/encargada, sin cambios. Esta feature es una **segunda
puerta**, para cuando quien tiene el dato es el colaborador y no quien opera la
ficha.

## DECIDÍ

### 1. Una tabla de solicitudes, con un catálogo de campos data-driven

`solicitudes_cambio_perfil` — una fila por propuesta, con estado
`pendiente | aprobado | rechazado | reemplazada` (ver más abajo por qué hay un
cuarto estado que el enunciado original no pedía). El campo que se propone
cambiar no es un `enum` fijo en TypeScript: vive en una tabla nueva,
`catalogo_campos_perfil`, con una fila por cada uno de los 11 campos posibles y
si exige documento — regla #3 de este repo ("nunca una lista escrita a mano de
algo que vive en una tabla"). El backend y la pantalla leen esa tabla; nadie
hardcodea la lista de 9 filas del enunciado.

Los 11 `campo` posibles (algunos del enunciado son compuestos — varias
columnas que cambian juntas — y se modelan como un solo `campo`):

| `campo` | Documento | Columnas que toca | Tabla destino |
|---|---|---|---|
| `celular` | No | `celular` | `datos_personales` |
| `direccion` | No | `direccion` | `datos_personales` |
| `contacto_emergencia` | No | `emergencia_nombre`, `emergencia_vinculo`, `emergencia_telefono` | `datos_personales` |
| `estado_civil` | Sí | `estado_civil` | `datos_personales` |
| `hijos_menores` | Sí | `hijos_menores` (boolean) | `datos_personales` |
| `grado_instruccion` | Sí | `grado_instruccion` | `datos_personales` |
| `discapacidad` | Sí | `discapacidad`, `discapacidad_conadis` | `datos_personales` |
| `cuenta_bancaria` | Sí | `entidad_bancaria`, `numero_cuenta` | `datos_personales` |
| `cuspp` | Sí | `cuspp` | `datos_personales` |
| `correccion_identidad` | Sí (siempre) | `documento` (personas) + `nombres`/`apellidos` (personas) + `fecha_nacimiento`/`genero` (datos_personales) — cualquier subconjunto | `personas` + `datos_personales` |
| `familiar_nuevo` | Sí | fila nueva completa | `familiares` (tabla nueva, ver #4) |

**`cuspp` cubre solo el número CUSPP** (`datos_personales.cuspp`), nunca el
régimen de pensión (AFP vs ONP). El régimen ya tiene su propio mecanismo
decidido y auditado (`fn_cambiar_regimen_pension`, 0277/0332, que valida contra
periodos ya pagados) — esta feature no lo toca ni lo reabre. Confirmado con el
usuario 2026-09-07.

**Correo NO está en el catálogo** — se muestra en el perfil pero se edita desde
`/admin/cuentas`, fuera de este flujo (regla ya decidida, no se reabre).

### 2. `correccion_identidad` bundlea DNI + nombre + fecha de nacimiento + género

El enunciado los lista como una sola fila de tabla ("mismo mecanismo,
documento obligatorio siempre") porque en la práctica un error de captura casi
siempre aparece junto: alguien nota que su DNI está mal tecleado y de paso ve
que su fecha de nacimiento también. Modelarlos como 4 campos sueltos obligaría
a subir el mismo DNI 4 veces. Se modelan como un solo `campo =
'correccion_identidad'` cuyo `valor_propuesto` es un `jsonb` con cualquier
subconjunto de `{documento, nombres, apellidos, fecha_nacimiento, genero}` —
la persona edita solo lo que está mal, no los cinco campos a la fuerza.

### 3. `valor_anterior`/`valor_propuesto` son `jsonb`, no columnas de texto

Porque varios `campo` son compuestos (arriba). Guardar `{"celular": "987..."}`
en vez de una columna `valor_anterior text` evita 11 formas distintas de
serializar. `valor_anterior` se captura en el momento de crear la solicitud
(un snapshot, no una referencia) — si alguien más cambia el dato por otra vía
mientras la solicitud está pendiente, el histórico de la solicitud sigue
contando la verdad de cuándo se pidió.

### 4. `familiar_nuevo` no actualiza una columna: agrega una fila

No existe hoy ninguna tabla `familiares`/`derechohabientes` en el esquema —
confirmado por grep contra las 391 migraciones. Se construye completa, en esta
misma entrega (confirmado con el usuario 2026-09-07):

```sql
create table familiares (
  id                     uuid primary key default gen_random_uuid(),
  persona_id             uuid not null references personas(id),
  nombre                 text not null,
  vinculo                text not null check (vinculo in ('conyuge','conviviente','hijo','hija','otro')),
  fecha_nacimiento       date,
  activo                 boolean not null default true,
  creado_por_solicitud_id uuid not null references solicitudes_cambio_perfil(id),
  creado_at              timestamptz not null default now()
);
```

`activo` existe para el día en que un familiar deje de ser derechohabiente
(cumple mayoría de edad, fallece, se divorcia) — se marca `false`, nunca se
borra la fila (regla del repo). Ese flujo de "dar de baja un familiar" **no**
se construye en esta entrega: hoy solo hay alta. Se deja la columna para no
migrar de nuevo cuando se pida.

`familiar_nuevo` es una excepción a la regla "una sola solicitud pendiente por
campo" (#5): agregar dos hijos distintos son dos altas legítimas en paralelo,
no la misma pregunta repetida dos veces. Ver el índice parcial en #5 para cómo
se excluye sin romper el resto.

### 5. Máquina de estados: se agrega `reemplazada` como cuarto estado

El enunciado define tres estados (`pendiente | aprobado | rechazado`) y a la
vez exige dos reglas que, juntas, necesitan un cuarto: "el colaborador vuelve
a editar el mismo campo con una solicitud pendiente → la nueva reemplaza a la
anterior" + la regla de todo el repo, "nunca se borran datos". Si la anterior
no se borra y no se puede seguir contando como `pendiente` (ya no compite por
aprobación) ni como `rechazada` (nadie la rechazó, nadie la evaluó), necesita
su propio nombre: `reemplazada`. Es una etiqueta de auditoría, no una decisión
de nadie — se pone sola cuando llega la siguiente.

```sql
create table solicitudes_cambio_perfil (
  id               uuid primary key default gen_random_uuid(),
  persona_id       uuid not null references personas(id),
  campo            text not null references catalogo_campos_perfil(campo),
  valor_anterior   jsonb not null,
  valor_propuesto  jsonb not null,
  estado           text not null default 'pendiente'
                     check (estado in ('pendiente','aprobado','rechazado','reemplazada')),
  creada_at        timestamptz not null default now(),
  resuelta_at      timestamptz,
  resuelta_por     uuid references personas(id),
  motivo           text,
  constraint chk_solicitud_perfil_resuelta_completa check (
    estado = 'pendiente' or (resuelta_at is not null and resuelta_por is not null)
  ),
  constraint chk_solicitud_perfil_rechazo_con_motivo check (
    estado <> 'rechazado' or coalesce(trim(motivo), '') <> ''
  )
);

-- Como máximo una solicitud PENDIENTE por persona+campo, salvo familiar_nuevo
-- (que admite varias en paralelo, ver #4).
create unique index uq_solicitud_perfil_pendiente
  on solicitudes_cambio_perfil (persona_id, campo)
  where estado = 'pendiente' and campo <> 'familiar_nuevo';
```

`fn_crear_solicitud_perfil` hace, dentro de una sola llamada (atómico por ser
una función): `update ... set estado='reemplazada' where persona_id=X and
campo=Y and estado='pendiente'` seguido del `insert` de la nueva. El índice
único de arriba es la red de seguridad real contra la carrera de dos envíos
casi simultáneos (ver "Concurrencia" en Verificación) — igual que
`solicitudes_vacaciones_pendientes_sin_solape` en la 0330, la regla vive en un
constraint, no en la esperanza de que el código de arriba alcance a correr
antes que el otro.

### 6. El resolver escribe columna por columna — nunca reusa `fn_set_datos_personales`

`fn_set_datos_personales` es un upsert de las ~19 columnas de `datos_personales`
a la vez: si se le llama pasando solo `p_celular` y dejando el resto en su
default `NULL`, el `on conflict do update set x = excluded.x` **pisa con NULL
todo lo demás**. Es exactamente el bug que el commit `55c2849` (hoy mismo, en
este repo) tuvo que parchear para las fotos, reenviando a mano el valor ya
guardado en cada campo que no cambiaba. Reusar esa función desde el resolver
heredaría el mismo riesgo para cada aprobación. En vez de eso,
`fn_aplicar_cambio_perfil` hace un `UPDATE ... SET <esa columna> = <ese valor>
WHERE persona_id = X` de una sola columna (o de las 2-3 que un campo compuesto
declare en `catalogo_campos_perfil.columnas`) — nunca toca las columnas que no
son parte de esa solicitud.

Para `documento` (DNI), el resolver **reusa** `fn_set_documento(persona_id,
documento, motivo)` tal cual existe hoy — no se duplica su lógica de auditoría.
Para `nombres`/`apellidos` se crea `fn_corregir_nombre_persona`, con el mismo
molde "función guardián + trigger que bloquea `UPDATE` directo" que ya usan
`fn_set_rol`/`fn_bloquear_rol_directo` (0295/0296) y
`fn_set_sede_base`/`fn_bloquear_sede_directa` (0342) — es la primera vez que
`personas.nombres`/`apellidos` tienen una vía de corrección después de creada
la persona, así que es exactamente el campo sensible nuevo que ese molde anticipa.

`fecha_nacimiento` y `genero` (en `datos_personales`) se actualizan con un
`UPDATE` directo dentro del resolver, con su propia fila en
`correcciones_auditoria`, pero **sin** trigger-guardián — hoy DO ya los edita
sin ningún guardián vía la ficha normal (0369), así que agregarles un
candado nuevo solo en esta vía crearía una asimetría (protegido por un lado,
abierto por el otro) sin tapar nada real. Endurecer esos dos campos en la
ficha de DO también es una mejora aparte, fuera de esta entrega.

### 7. Toda escritura de resultado queda en `correcciones_auditoria`

Reusa la tabla de auditoría universal del repo (la misma que ya usan cambio de
rol, de sede, de régimen, de vínculo, de DNI) — una fila por columna tocada,
con `valor_anterior`/`valor_nuevo` sacados del `jsonb` de la solicitud y
`motivo = 'Aprobado por solicitud de perfil — ver solicitudes_cambio_perfil.id=<id>'`.
No se crea una tabla de auditoría propia para esta feature.

### 8. Documentos: bucket privado + URL firmada, varios adjuntos por solicitud

Sigue el precedente de `comprobantes`/`expedientes`, no el de `fotos-perfil`:
estos documentos SÍ contienen un dato que nadie ve por su cuenta (copia de
DNI, certificado CONADIS, partida de nacimiento, estado de cuenta bancaria).
Bucket nuevo `solicitudes-perfil`, privado, `file_size_limit` 8 MB,
`allowed_mime_types` `{image/jpeg,image/png,application/pdf}`.

Un documento puede ser más de un archivo (p. ej. anverso y reverso del DNI),
así que en vez de una columna `documento_url` en `solicitudes_cambio_perfil`,
se crea una tabla hija:

```sql
create table solicitud_perfil_adjuntos (
  id            uuid primary key default gen_random_uuid(),
  solicitud_id  uuid not null references solicitudes_cambio_perfil(id),
  ruta          text not null,
  subido_at     timestamptz not null default now()
);
```

Ruta: `perfil/<persona_id>/<solicitud_id>/<epoch_ms>.<ext>` — mismo patrón de
sufijo de tiempo que `fotos-perfil` (0381), para no chocar con caché. La
política de storage (`fn_solicitud_perfil_puede_escribir`) valida que el
segundo segmento sea el uuid de quien sube (o admin/DO), y que el tercer
segmento sea el uuid de una solicitud **suya y todavía `pendiente`** — subir a
una solicitud ya resuelta, o a la de otra persona, se rechaza en la política
misma, no solo en la pantalla.

"El botón de enviar queda deshabilitado hasta adjuntar" es UI. El servidor
**no confía en eso**: `fn_crear_solicitud_perfil` revisa
`catalogo_campos_perfil.requiere_documento` y, si es `true`, exige que ya
exista al menos una fila en `solicitud_perfil_adjuntos` para esa solicitud
antes de dejarla pasar de estado `pendiente` real (ver flujo de creación en
Endpoints — se sube primero, se crea la solicitud después, referenciando los
adjuntos ya subidos).

### 9. Aprueba solo DO — nunca la encargada de sede

`fn_es_admin_o_lider()`, sin excepción para ningún campo, incluidos los tres
que no piden documento (celular/dirección/contacto de emergencia).
Confirmado con el usuario 2026-09-07, aunque el repo tiene precedente de que
lo no-sensible (revisiones de día) lo resuelva también la encargada — se
descartó esa opción a propósito por simplicidad: una sola puerta de
aprobación para las 11, no una matriz de "cuál campo aprueba quién".

### 10. Tarea de seguimiento a planilla: tabla dedicada, no una tabla de tareas genérica

El repo evita explícitamente una tabla `tareas` polimórfica (ver el
razonamiento de la 0330 sobre "dos tipos para la misma pregunta"). Se crea
`seguimiento_planilla_por_solicitud`, dedicada a este único caso:

```sql
create table seguimiento_planilla_por_solicitud (
  id            uuid primary key default gen_random_uuid(),
  solicitud_id  uuid not null unique references solicitudes_cambio_perfil(id),
  persona_id    uuid not null references personas(id),
  campo         text not null,
  descripcion   text not null,
  estado        text not null default 'pendiente' check (estado in ('pendiente','resuelta')),
  creada_at     timestamptz not null default now(),
  resuelta_por  uuid references personas(id),
  resuelta_at   timestamptz,
  nota          text
);
```

`fn_resolver_solicitud_perfil`, al aprobar una solicitud con `campo in
('estado_civil','hijos_menores')`, inserta automáticamente una fila acá con
`descripcion = 'Revisar planilla — ' || nombre_completo || ' — ' || campo`.
Nadie la autocierra: se marca `resuelta` a mano, con `fn_resolver_seguimiento_planilla(id, nota)`,
gated también a `fn_es_admin_o_lider()` — es un trámite externo ante
SUNAT/EsSalud, el sistema no puede confirmarlo solo.

### 11. Notificación: bandeja + correo por el pipeline que ya existe, sin contador nuevo en el nav

**In-app**: nueva sección dentro de `/admin/bandeja` (mismo patrón que ya usa
para vacaciones/revisiones — resolver ahí mismo sin salir de la pantalla, una
RPC con un motivo opcional). **No se agrega un cuarto contador al sidebar**
(`nav.tsx`): el propio comentario de esa pantalla ya deja escrita la regla —
un contador nuevo compite con los tres que ya explican algo con fecha límite y
costo real de pasarla (vacaciones por vencer, contrato por vencer,
comprobante de educación vencido). Una solicitud de perfil pendiente no tiene
ese tipo de plazo — aplicando la propia regla del archivo, no le toca contador
propio. Vive en Bandeja igual que Revisiones, que tampoco lo tiene.

**Correo**: el proyecto ya tiene Resend configurado
(`apps/web/app/api/alertas-encargadas/route.ts`), así que se agrega, no se
difiere. Dos `tipo` nuevos en `alertas` (columna con `check` que hay que
extender, mismo patrón que ya sumó `contrato_por_vencer`/`vacaciones_por_vencer`):

- `solicitud_perfil_creada` — una fila por cada persona con rol DO
  (`admin`/`lider_do`), `persona_id` = esa persona (destinatario ya resuelto,
  igual que `contrato_por_vencer`) — no la encargada de sede, coherente con
  DECIDÍ #9.
- `solicitud_perfil_resuelta` — una fila con `persona_id` = el propio
  colaborador. Se agrega a la Rama 2 de `fn_alertas_email_pendientes` (destino
  directo, sin buscar encargada) — a propósito, para no filtrarle a la
  encargada de sede un dato potencialmente sensible (estado civil,
  discapacidad) solo porque comparte sede con quien lo pidió.

Tocar `fn_alertas_email_pendientes` exige el mismo cuidado que cualquier
función que ya lleva varias reescrituras superpuestas (0358 sobre 0354, 0359
sobre 0358): pedir con `donde-vive.sh` cuál es el cuerpo vigente **antes de
escribir**, no copiarlo de memoria de esta conversación.

### 12. Endpoints — RPC de Postgres, sin capa `app/api/` intermedia

Sigue la convención real del repo: `solicitudes_vacaciones`/`revisiones_pedidas`
no tienen ruta `app/api/`, la página llama `supabase.rpc(...)` directo. Esta
feature hace lo mismo — no se inventa una capa REST que el resto del dominio
no tiene.

| RPC | Quién | Qué hace |
|---|---|---|
| `fn_catalogo_campos_perfil()` | cualquiera autenticado | Lee `catalogo_campos_perfil` — para pintar el formulario sin hardcodear la lista. |
| `fn_crear_solicitud_perfil(p_campo, p_valor_propuesto jsonb)` | el propio colaborador | Snapshotea `valor_anterior` leyendo la fila actual, valida documento si `requiere_documento`, reemplaza la pendiente anterior si existe, inserta. |
| `fn_mis_solicitudes_perfil()` | el propio colaborador | Lista sus solicitudes con estado, para "Mis solicitudes". |
| `fn_solicitudes_perfil_pendientes()` | DO | Lista todas las `pendiente`, para la Bandeja. |
| `fn_resolver_solicitud_perfil(p_id, p_aprobar boolean, p_motivo text default null)` | DO (`fn_es_admin_o_lider`) | Aprueba (llama `fn_aplicar_cambio_perfil` internamente) o rechaza (exige motivo). Encola la alerta de resultado. |
| `fn_resolver_seguimiento_planilla(p_id, p_nota text default null)` | DO | Marca `resuelta` una tarea de seguimiento a planilla. |

Subida de archivo: mismo patrón de `subirArchivoConProgreso` (0381) contra el
bucket `solicitudes-perfil`, **antes** de llamar a `fn_crear_solicitud_perfil`
— la solicitud se crea referenciando adjuntos que ya existen, nunca al revés
(ver Verificación → "si falla la subida a medio camino").

### 13. Pantallas

**`/mio` — nueva sección "Mis solicitudes"** (dentro de la página que ya
existe, como una pestaña más, igual que hace hoy con vacaciones): formulario
por campo (leyendo `fn_catalogo_campos_perfil` para saber si pide documento),
subida de adjunto si aplica, botón deshabilitado hasta adjuntar cuando
corresponde, lista de solicitudes propias con su estado y, si fue rechazo, el
motivo. Para `correccion_identidad`, el formulario rotula explícitamente
"Corrección de un dato mal capturado", no "Actualizar mis datos" — el
enunciado lo pide así a propósito para no confundirlo con un cambio de
identidad legal real (matrimonio, cambio de género legal, etc., que si son
reales van por `estado_civil`/`genero` como cambio, no como corrección).

**`/admin/bandeja` — nueva sección "Solicitudes de perfil"**: mismo patrón
visual que Vacaciones/Revisiones ahí mismo — lista con Aprobar/Rechazar
inline, motivo obligatorio solo si rechaza, sin salir de la pantalla.

## DESCARTÉ

- **Un enum de TypeScript para los campos** — vive en la tabla
  `catalogo_campos_perfil` (DECIDÍ #1).
- **Reabrir el régimen de pensión (AFP/ONP) dentro de esta feature** — tiene
  su propio mecanismo auditado; `cuspp` en este flujo es solo el número.
- **Una tabla `tareas` polimórfica genérica** — el repo ya evitó ese camino a
  propósito (0330); se crea una tabla dedicada y angosta.
- **Que la encargada de sede también pueda aprobar** los 3 campos sin
  documento — se simplificó a "DO para las 11", a pedido explícito.
- **Reusar `fn_set_datos_personales`** desde el resolver — el riesgo de pisar
  con NULL las columnas que no cambian (ver DECIDÍ #6) lo descarta.
- **Un cuarto contador en el sidebar de `/admin`** — la propia regla escrita
  en `nav.tsx` lo descarta (sin fecha límite ni costo de plata por demorar).
- **DO creando una solicitud en nombre de otra persona** — el enunciado dice
  "el colaborador propone"; esta entrega es autoservicio puro. DO sigue
  editando directo desde `/admin/datos-personales` cuando es DO quien detecta
  el error, sin pasar por esta cola.
- **Trigger-guardián sobre `fecha_nacimiento`/`genero`** en `datos_personales`
  — asimetría innecesaria frente al resto de la ficha, que hoy tampoco lo
  tiene (DECIDÍ #6).
- **Borrar o desactivar un familiar** en esta entrega — solo alta. La columna
  `activo` queda lista para cuando se pida la baja.

## SE ROMPE SI

- **Alguien reintroduce un `UPDATE` directo a `personas.nombres`/`apellidos`**
  sin pasar por `fn_corregir_nombre_persona` — el trigger guardián
  (`fn_bloquear_nombre_directo`) existe exactamente para que esto falle ruidoso
  en vez de silencioso.
- **Alguien llama a `fn_aplicar_cambio_perfil` fuera del flujo de aprobación**
  (por ejemplo, para "corregir rápido" sin pasar por la solicitud) — está
  `security definer` pero su única entrada real es
  `fn_resolver_solicitud_perfil`; no tiene guard propio contra invocación
  directa porque ya exige una solicitud `pendiente` con ese id — llamarla con
  un id inexistente o ya resuelto no hace nada (falla el `if not found`).
- **Se borra `catalogo_campos_perfil` sin actualizar el frontend** — el
  formulario de "Mis solicitudes" dejaría de saber qué campos existen; no hay
  fallback hardcodeado a propósito (DECIDÍ #1), así que un catálogo vacío
  vacía la pantalla entera, no la rompe silenciosamente con datos viejos.
- **Se sube un archivo sin haber creado antes una solicitud en la que
  referenciarlo, o a una solicitud ya resuelta** — la política de storage lo
  rechaza en el momento de subir (valida que la solicitud del tercer segmento
  del path exista y siga `pendiente`), no después.
- **Dos solicitudes sobre el mismo campo llegan casi al mismo tiempo** — ver
  Verificación abajo.

## Verificación explícita (paso 6 del pedido original)

**Concurrencia — dos solicitudes casi simultáneas sobre el mismo campo.**
`fn_crear_solicitud_perfil` hace, dentro de una sola invocación (una
transacción implícita): `UPDATE ... SET estado='reemplazada' WHERE ... AND
estado='pendiente'` y luego `INSERT`. Si dos llamadas concurrentes de la misma
persona sobre el mismo campo llegan casi a la vez, Postgres serializa el
`UPDATE` sobre la fila existente (row lock), y el índice único parcial
`uq_solicitud_perfil_pendiente` (DECIDÍ #5) garantiza que, pase lo que pase con
el orden de ejecución, jamás sobreviven dos filas `pendiente` del mismo
`(persona_id, campo)` — la segunda que intente insertar sin haber visto la
primera reemplazada choca contra el índice y su transacción aborta con un
error claro ("ya tienes una solicitud pendiente sobre ese campo"), en vez de
crear un duplicado silencioso. Mismo mecanismo que ya usa
`solicitudes_vacaciones_pendientes_sin_solape` (0330) para el caso análogo.

**Falla la subida del documento a medio camino.** El orden es subida-primero,
solicitud-después (DECIDÍ #8/#12): si la subida a Supabase Storage falla o se
corta, no existe ninguna fila en `solicitudes_cambio_perfil` todavía —no hay
estado a medias que limpiar. Si la subida tuvo éxito pero la llamada a
`fn_crear_solicitud_perfil` que sigue falla o el navegador se cierra antes de
hacerla, el archivo queda huérfano en un bucket privado, sin ninguna fila que
lo referencie — invisible y sin costo real (mismo razonamiento que ya acepta
0381 para archivos huérfanos de reemplazo: tamaño y frecuencia insignificantes
para ~30 personas). La persona simplemente reintenta: adjunta de nuevo (o
reintenta enviar) y una segunda solicitud se crea con normalidad. Nunca queda
una solicitud a medias en la tabla, porque la fila se crea en un solo `INSERT`
con todos sus datos ya resueltos, no en pasos.

**¿Alguien sin esta conversación entendería el ADR?** Cada decisión cita el
archivo/migración real de donde sale el precedente (0330, 0381, 0295/0296,
0342, 55c2849, `nav.tsx`) en vez de decir "como ya vimos" — se puede verificar
cada afirmación abriendo esos archivos sin haber estado en esta sesión. Los
nombres de tabla/función describen qué hacen, no de qué conversación salieron.

## Pendiente para cuando se escriba la migración real

- Confirmar número de migración con `./scripts/siguiente-numero.sh` **en el
  momento de escribirla**, no usar el que se consultó durante este diseño
  (0395 al 2026-09-07 — puede haber cambiado).
- Pedir el md5 de `fn_alertas_email_pendientes` contra producción con
  `donde-vive.sh` antes de tocarla (DECIDÍ #11) — ya lleva dos reescrituras
  superpuestas (0358/0359).
- Auditar contra Postgres local, dentro de `BEGIN … ROLLBACK`, el cálculo de
  `fn_resolver_solicitud_perfil` con casos reales antes de darlo por bueno —
  toca planilla indirectamente vía la tarea de seguimiento (regla no
  negociable de este repo para todo lo que toca plata).

---

## Correcciones tras implementar (2026-09-07)

Al escribir la migración real, dos supuestos de este ADR resultaron falsos —
ninguno se pudo saber sin bajar a mirar el esquema vivo, y los dos cambian el
diseño de forma sustancial. Se documentan acá en vez de reescribir el cuerpo
de arriba, para que quede el rastro de qué se creyó primero y por qué se
corrigió.

### Hallazgo 1 (independiente de esta feature) — `derechohabientes` existe y no tiene migración

**"Familiares" ya estaba construido.** `apps/web/app/(admin)/admin/datos-personales/page.tsx`
(committeado en esta rama desde antes de esta sesión) ya tiene una sección
completa de alta/edición/baja de familiares — `fn_set_derechohabiente`,
`fn_cerrar_derechohabiente`, la tabla `derechohabientes`, el catálogo
`VINCULOS_DERECHOHABIENTE` en `packages/shared`, y hasta
`desacuerdoAsignacionFamiliar()` reconciliando contra planilla. No es un
borrador: está en producción de hecho (el frontend que depende de esto ya está
en `main`).

**Y esa tabla no tiene ninguna migración que la cree — en ningún branch,
local ni remoto.** Se buscó con `git grep` contra las ~90 branches locales y
remotas: cero coincidencias en `supabase/migrations/`. La tabla y las tres
funciones existen en el Postgres local compartido (confirmado por
introspección directa), pero no hay ningún archivo `.sql` versionado que las
origine. Es el mismo patrón que el incidente de la migración 0177 que este
mismo CLAUDE.md documenta — con el agravante de que acá ni siquiera queda un
archivo sin commitear que rescatar: no hay ningún artefacto.

**Esto es un hallazgo aparte de esta feature, no una tarea de esta feature.**
Se reportó al usuario, que decidió explícitamente: no reconstruir la
migración faltante ahora, solo dejarlo dicho para que se resuelva por su
cuenta con Felipe. Nadie sabe todavía si producción tiene esta tabla o no —
esta sesión no tiene acceso a producción para comprobarlo.

**Consecuencia para esta feature:** `familiar_nuevo` (DECIDÍ #4 arriba) **no
construye una tabla `familiares` nueva.** Al aprobarse, llama a
`fn_set_derechohabiente` (la función existente) sobre `derechohabientes` (la
tabla existente) — cero tablas nuevas para este campo. El catálogo de
vínculos válidos tampoco se inventó: es el mismo que ya impone
`derechohabientes_vinculo_check` (`conyuge, conviviente, hijo, madre, padre,
hermano, otro`) y `derechohabientes_check` (un `hijo` siempre exige fecha de
nacimiento) — `fn_validar_valor_propuesto` los repite para dar un mensaje de
error legible antes de que Postgres los rechace con el texto crudo del
constraint.

### Hallazgo 2 — "nombre completo" no es `personas.nombres`/`apellidos`

El diseño original (DECIDÍ #2/#6) asumía que corregir el "nombre completo"
del enunciado significaba `personas.nombres`/`apellidos` — el nombre de
sistema, usado en todas partes— y por eso proponía una función guardián nueva
(`fn_corregir_nombre_persona`) con su propio trigger-candado, siguiendo el
molde de `fn_set_rol`/`fn_set_sede_base`.

Existe un campo completamente distinto, ya en la ficha, para esto:
`datos_personales.nombre_dni` — el nombre "como aparece en el DNI", que
alimenta el T-Registro, editado hoy sin ningún candado especial vía
`fn_set_datos_personales`. `personas.nombres`/`apellidos` es el nombre de
sistema (login, roster del terminal, reportes) y esta feature **nunca lo
toca** — no había ninguna razón de negocio para tocarlo, y el enunciado
original tampoco lo pedía; solo se llegó a esa lectura por no haber mirado
antes la ficha completa.

**Consecuencia:** no existe `fn_corregir_nombre_persona` ni ningún trigger
sobre `personas.nombres`/`apellidos` — se descartó por innecesario, no por
riesgoso. `correccion_identidad` toca 4 columnas, no 5:
`personas.documento` (vía `fn_set_documento`, reusada tal cual) +
`datos_personales.nombre_dni`, `fecha_nacimiento`, `genero` (upsert directo +
auditoría, igual que el resto de la ficha).

### Hallazgo 3 — el auto-escrito directo ya estaba abierto (y se cerró)

Verificado contra el Postgres local: tanto `fn_set_datos_personales` como
`fn_set_derechohabiente` (y, por el mismo molde, `fn_cerrar_derechohabiente`)
**ya permitían que la propia persona escribiera directo** —
`p_persona_id = fn_persona_actual_id()` era una rama válida de su propio
guard interno. `authenticated` ya tenía `EXECUTE` sobre las tres. Ninguna
pantalla del repo ejercía esa rama (ningún `/mio` las llama hoy), así que era
una puerta sin tráfico — pero abierta: un colaborador con sesión podía llamar
`supabase.rpc('fn_set_datos_personales', {...})` desde la consola del
navegador y cambiar su celular, estado civil o cuenta bancaria al instante,
sin aprobación ni documento.

Confirmado con el usuario 2026-09-07: se cierra. Las tres funciones se
reescriben en la migración 0399 quitando esa rama — DO y la encargada de sede
mantienen su edición directa intacta; solo se retira la autoedición. Como son
funciones **existentes** que se reescriben, la migración declara el md5 de
partida contra Postgres LOCAL (no hay una migración anterior contra la cual
compararlo, por el Hallazgo 1) y dice explícitamente que hace falta
confirmarlo contra producción antes de pegar — regla no negociable de este
repo.

### Hallazgo 4 (accidente de esta sesión, sin consecuencia) — DDL en autocommit

Al verificar la migración contra Postgres local, el primer intento concatenó
el archivo de la migración directamente antes de un script de humo que sí
tenía su propio `BEGIN…ROLLBACK` — pero la migración en sí no lo tenía, así
que sus `CREATE TABLE`/`CREATE FUNCTION` corrieron en autocommit y quedaron
aplicados de verdad en la base local COMPARTIDA (con las tres funciones ya
sin la rama de autoescritura, afectando a cualquier otra sesión que compartiera
esa base). Se detectó de inmediato comprobando `migraciones_aplicadas`, y se
revirtió: las tres funciones se restauraron a su cuerpo original (con la rama
de autoescritura), y las tablas/funciones nuevas se borraron. La verificación
posterior (Hallazgo 3 en adelante) se corrió correctamente, con un `BEGIN`
envolviendo migración + prueba desde la primera línea, confirmando al final
que la base quedó exactamente como antes. No llegó a tocar ningún archivo
commiteado ni producción — el radio de daño fue exclusivamente el Postgres
local compartido, y por minutos.

### Modelo de datos final (difiere del original arriba)

- **Sin tabla `familiares`** ni `solicitud_perfil_adjuntos`. Los documentos
  viven en `solicitudes_cambio_perfil.rutas_adjuntas text[]` (rutas dentro del
  bucket `solicitudes-perfil`, sin id de solicitud en el path — se sube antes
  de que la solicitud exista, así que el path es solo `solicitud/<persona_id>/<archivo>`,
  igual de simple que `fotos-perfil`).
- **11 campos siguen siendo 11**, pero `familiar_nuevo` apunta a
  `derechohabientes` (existente) en vez de una tabla nueva, y
  `correccion_identidad` tiene 4 columnas, no 5 (sin `personas.nombres`/`apellidos`).
- Tres funciones existentes (`fn_set_datos_personales`, `fn_set_derechohabiente`,
  `fn_cerrar_derechohabiente`) se reescriben para cerrar la autoescritura —
  no solo se agregan tablas nuevas.
- `seguimiento_planilla_por_solicitud` y el resto del diseño (estados,
  aprobador único DO, sin contador nuevo en el nav, notificación por correo
  diferida) se mantienen tal cual se decidieron arriba.

## Corrección tras implementar (2026-09-08) — DECIDÍ #9 se revierte

**DECIDÍ #9 ("aprueba solo DO — nunca la encargada de sede") se revierte al
día siguiente de confirmarse.** Al construir `/mio/editar` — la pantalla que
por fin le da un lugar visible a esta feature, antes escondida en una pestaña
— se pidió explícitamente que la encargada de sede también pudiera resolver
las solicitudes de su propio equipo, con el mismo alcance que ya tiene para
editar la ficha directa desde `/admin/datos-personales`
(`fn_set_datos_personales`). Se le mostró al usuario que esto contradecía
DECIDÍ #9 y la alternativa ya descartada en DESCARTÉ ("que la encargada
también pueda aprobar los 3 campos sin documento — se simplificó a 'DO para
las 11', a pedido explícito"); confirmó que sí, quiere revertirlo — ahora para
los 7 campos que el colaborador puede pedir desde `/mio/editar`, no solo los 3
sin documento que se había planteado la vez anterior.

Lo que cambia, en la migración 0403:

- `fn_resolver_solicitud_perfil` y `fn_solicitudes_perfil_pendientes` aceptan
  también `fn_rol_actual() = 'supervisor_sede' and` la sede de quien pidió el
  cambio `= fn_sede_actual_persona()` — mismo guard que ya usan
  `fn_set_datos_personales` / `fn_set_derechohabiente` / `fn_cerrar_derechohabiente`
  desde esta misma migración (0399), copiado, no reinventado.
- Nueva `fn_solicitud_perfil_puede_leer`, aparte de
  `fn_solicitud_perfil_puede_escribir`: la encargada necesita ABRIR el
  documento adjunto para poder aprobar con criterio, pero sigue sin poder
  subir, reemplazar ni borrar el de nadie — esa función no se tocó.
- `apps/web/app/(admin)/admin/bandeja/page.tsx`: `puedeResolverPerfil` pasa de
  `puedeVerPlanilla` (DO) a `puedeOperarEquipo` (DO + encargada), para que la
  sección de la Bandeja se le muestre.

**Lo que la razón original de DECIDÍ #9 advertía sigue siendo cierto, y ahora
es una consecuencia aceptada a propósito, no un descuido:** la encargada va a
ver datos de su equipo que hoy están reservados a DO en el resto del sistema
—estado civil, discapacidad si alguna vez se permitiera, cuenta bancaria—
cada vez que alguien de su sede pida cambiarlos. La nota de privacidad de
DECIDÍ #11 (no avisar a la encargada por correo cuando se crea o resuelve una
solicitud, "para no filtrarle un dato potencialmente sensible... solo porque
comparte sede") **no se revirtió**: sigue sin haber correo a la encargada:
solo lo ve si entra a la Bandeja a resolverlo. Aviso explícito, decisión
del usuario con la contradicción a la vista, ver conversación del 2026-09-08.
