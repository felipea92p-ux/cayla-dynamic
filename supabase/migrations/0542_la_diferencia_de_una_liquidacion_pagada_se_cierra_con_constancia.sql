-- ============================================================================
-- 0542 — La diferencia real de una liquidación ya pagada se puede cerrar con
--        una constancia, y reaparece sola si el cálculo cambia otra vez
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una diferencia REAL entre lo que se pagó al cesar (`liquidacion_pagada`)
--   y lo que el cálculo de hoy daría —la que `fn_liquidacion_diferencias` marca
--   con `origen = 'real'`— tenga por fin una forma de cerrarse que deje rastro:
--   QUIÉN la miró, CUÁNDO, QUÉ decidió, POR QUÉ, y en qué se apoya. Y que ese
--   cierre valga solo mientras el cálculo siga siendo el que esa persona vio:
--   si cambia, el aviso vuelve solo, sin job ni caducidad por fecha.
--
--   Agrega, SIN tocar ninguna función existente ni el contenido ni los permisos de
--   ninguna tabla existente (una tabla y cuatro funciones, la del trigger incluida):
--     · `liquidacion_constancias`            el libro de constancias (solo se agrega, nunca se edita)
--     · `fn_liquidacion_huella(jsonb)`       la «huella» del cálculo que se vio (una sola definición)
--     · `fn_liquidacion_constancia_estado`   lo que la pantalla necesita para decidir, de UN solo instante
--     · `fn_liquidacion_constatar`           la única puerta de escritura (la función guardián)
--     · `fn_trg_constancia_es_inmutable`     el mensaje del trigger que no deja editar, borrar ni vaciar
--   Un efecto lateral que NO es de datos: la FK hacia `liquidacion_pagada` hace que
--   `truncate liquidacion_pagada` ya no corra sin `cascade` (y con `cascade` el trigger
--   de las constancias también lo frena). Nadie vacía esa tabla a propósito.
--
-- QUÉ ASUME
--   `liquidacion_pagada` (0167, 0251): PK (persona_id, version), inmutable por
--   trigger, la anulación es una versión nueva con `anulada = true`.
--   `fn_liquidacion_diferencias` (0454): devuelve (concepto, pagado, ahora,
--   diferencia, origen) de la ÚLTIMA versión contra el cálculo de hoy, y nada si
--   no hay pago o la última versión está anulada. NO se modifica: la guardia de
--   abajo para si no tiene la columna `origen`.
--   `fn_persona_liquidada` (0499): «liquidada» = la última versión no anulada
--   describe el cese ACTUAL de la persona. Se reutiliza tal cual; no se inventa
--   otra definición de «liquidada». La guardia de abajo para si en esta base
--   sigue la versión anterior (0421), que solo mira que exista alguna no anulada.
--   `fn_es_admin_o_lider()` (0078) = admin o líder DO; `fn_persona_actual_id()`.
--
-- ── EL DEFECTO ───────────────────────────────────────────────────────────────
--   La pantalla de Liquidaciones decía «pagarla, compensarla o dejar constancia»,
--   y «dejar constancia» nunca existió. Una diferencia real en una liquidación
--   pagada no se podía cerrar de ninguna manera: el aviso «N con diferencias» no
--   bajaba jamás y acabó leyéndose como ruido (se quitó de la lista el
--   2026-10-21). Y una causa posible de esa diferencia no es un hecho de la
--   persona: que el sistema cambió DESPUÉS del pago (0341, 0343, 0278…), porque
--   `fn_liquidacion_diferencias` siempre calcula con las reglas de hoy. No se midió
--   con qué frecuencia pasa; basta con que pueda pasar para que «cerrarla» necesite
--   un «en qué te apoyas».
--
-- ── QUÉ SE PUEDE DECIDIR, Y QUÉ NO ───────────────────────────────────────────
--   El servidor calcula el SENTIDO de la diferencia —no lo elige quien decide—:
--   diferencia = ahora − pagado. Positiva: hoy se le daría MÁS a la persona (a
--   favor de la persona). Negativa: se le pagó de más (a favor de CAYLA). Y la
--   decisión depende del sentido:
--     a favor de la persona → «pagado_es_correcto»  (Lo pagado era lo correcto),
--                             con un APOYO obligatorio:
--                               regla_cambio_despues · la regla o un parámetro cambió después del pago
--                               dato_de_hoy_mal_cargado · un dato de hoy está mal cargado
--                               confirmado_por_contador_o_laboralista
--     a favor de CAYLA      → «no_se_reclama» o «devolucion_acordada»
--                             (Reglamento 29.6: se comunica por escrito y se acuerda)
--     cualquiera            → «retirada», que reabre el aviso (constancia puesta por error)
--   Lo que esta migración NO ofrece, a propósito:
--     · «ya se pagó por fuera»: pagar una diferencia ya tiene su instrumento,
--       «Volver a marcarla como pagada» (`fn_liquidacion_pagar`), que guarda la
--       fecha real de pago. Duplicarlo con menos datos sería dos fuentes para el
--       mismo hecho.
--     · «compensada»: no tiene instrumento y choca con 29.6 (no procede el
--       descuento íntegro sin conformidad escrita).
--     · «se debe y falta pagar»: no cierra el aviso, y el aviso rojo YA es ese
--       estado. Cerrarlo sería mentir.
--   Una persona con diferencias de sentido OPUESTO (un concepto a favor de ella
--   y otro a favor de CAYLA) no se puede constatar: la función se niega y el
--   aviso queda rojo. Falla del lado seguro mientras no se mida si ese caso
--   existe. (Para disciplina el peor error es el falso positivo; aquí es al
--   revés porque la plata es de alguien que ya no está y nadie reclama, 0167: el
--   error caro es CERRAR un aviso real, no dejarlo abierto.)
--
-- ── LA «HUELLA» ──────────────────────────────────────────────────────────────
--   Es un resumen (md5) de lo que quien constata VIO: solo las filas de
--   CONCEPTO con origen 'real' —Sueldo del periodo, Vacaciones, Gratificación,
--   CTS—, cada una como (concepto, diferencia en CENTAVOS enteros), ordenadas por
--   el texto del concepto en collation "C".
--     · SIN la fila TOTAL: su `ahora` incluye el sueldo del periodo que Planilla
--       mueve al registrar el descuento del cierre (0244, 0454), así que con
--       TOTAL dentro la constancia caducaría en cada cierre de mes aunque la
--       diferencia real no se hubiera movido.
--     · En centavos enteros, no en texto de numeric: '0' y '0.00' son el mismo
--       valor y no pueden dar huellas distintas (falso positivo).
--     · Orden por texto en "C", no por collation de la base: restaurar un
--       respaldo en otro locale no puede reordenar y caducar todo a la vez.
--     · `huella_formula` (columna, hoy 1): las constancias son inmutables y su
--       huella se guarda. Si algún día cambia la fórmula (otro separador, un campo
--       más, un bug), una migración NUEVA sube la versión en DOS sitios —el default
--       de la columna y el filtro de `fn_liquidacion_constancia_estado`— y las
--       constancias viejas quedan inertes (reabren) en vez de reabrir todas por
--       accidente con cifras que no cambiaron.
--   Si el cálculo cambia, la huella cambia y la constancia deja de coincidir: el
--   aviso vuelve solo, y el desglose puede mostrar la última que valió con otras
--   cifras (`anterior`). Si el cálculo VUELVE a lo que era, la constancia vuelve a
--   valer: es la misma situación que esa persona ya miró.
--   Si la huella que trae la pantalla ya no es la de hoy, el error NO nombra el
--   concepto que cambió (con un md5 en la mano el guardián no puede): la pantalla
--   vuelve a leer y muestra las cifras de ahora. Decisión consciente.
--
-- ── LA FILA DEL SUELDO CON UN DESCUENTO DE CIERRE ───────────────────────────
--   Medido en la prueba 435 y señalado por los revisores (la primera versión de esto
--   lo daba por benigno y no lo era). Si el periodo ya trae un descuento registrado,
--   la diferencia de «Sueldo del periodo» deja de ser la real: 0454 la deja 'real'
--   con Δ − D, que puede cambiar de SIGNO (+11.54 a favor de la persona pasa a
--   −488.46 «a favor de CAYLA», una cifra que nunca existió). Por eso, mientras el
--   periodo tenga un descuento registrado y «Sueldo del periodo» esté entre las
--   filas reales, NO se puede constatar: el estado dice por qué. Al cerrar el mes
--   esa fila pasa a 'esperada_por_cierre' y el aviso desaparece solo (la planilla ya
--   paga esa diferencia como devengado). Una constancia puesta ANTES del descuento
--   deja de coincidir (la huella cambió) y queda como historial. Cuesta una
--   llamada más a `fn_liquidacion` (~30 ms) y solo cuando esa fila aparece.
--
-- ── ESTADOS QUE NO PUEDEN EXISTIR (los hace imposibles el esquema, no el código)
--   1. Constancia sin motivo, o con menos de 10 caracteres que no sean espacio,
--      tabulador ni salto de línea.                                      CHECK
--   2. Constancia sin quién la hizo.                                      NOT NULL + FK
--   3. Constancia sobre una versión de liquidación que no existe.        FK compuesta
--   4. Decisión fuera del catálogo, o contraria al sentido.               CHECK
--   5. «Lo pagado era lo correcto» sin apoyo, o un apoyo donde no toca.   CHECK
--   6. Dos constancias VIGENTES de la misma diferencia (doble clic, dos
--      revisores a la vez): cada una se reemplaza como mucho una vez y hay
--      una sola raíz por (persona, versión, huella, fórmula).             2 índices únicos
--   7. Una cadena de reemplazos que mezcle personas, versiones o huellas. FK compuesta autorreferida
--   8. Una retirada que no reemplaza a nada.                              CHECK
--   9. Editar, borrar o vaciar una constancia.                            trigger (fila y TRUNCATE) + revoke
--  10. Escribir una constancia a nombre de otro, con otra fecha, o saltándose
--      las reglas de la función: ninguna sesión de usuario tiene INSERT, ni
--      puede mover la secuencia de `orden`.                               revoke
--  No expresados como restricción (viven en la función guardián y están
--  probados): que la versión sea la última y no esté anulada, que la liquidación
--  sea del cese actual, que la diferencia no sea mixta ni dependa de un descuento
--  de cierre, que el sentido coincida con el signo de las cifras guardadas, que
--  una retirada no reemplace a otra retirada, y que lo que se guarda sea lo que
--  el servidor recalcula ahora y lo que vio quien constató.
--
-- ── POR QUÉ UNA CADENA Y NO «LA ÚLTIMA MANDA» ───────────────────────────────
--   Ordenar por `constatada_at` no sirve: `now()` es el inicio de la
--   transacción (dos filas de una misma prueba empatan) y desempatar por un uuid
--   aleatorio convertiría el empate en una moneda — la familia de 0312, 0386 y
--   0388, con la diferencia de que aquí el desempate SERÍA la regla. Corregir una
--   constancia = escribir otra que la reemplaza (`reemplaza_id`). La vigente es la
--   que nadie reemplaza, y la base impide que haya dos. El guardián recibe la que
--   la pantalla vio (`p_reemplaza_id`): si otra persona se adelantó, se rechaza
--   con un mensaje en vez de pisarla en silencio (compare-and-swap).
--
-- ── EL CIERRE DE LA TABLA (molde 0480 / 0508) ───────────────────────────────
--   Supabase concede por defecto select, insert, update, delete —y truncate— a
--   `authenticated` en toda tabla nueva (0004, medido en 0508). «No se concede
--   escribir» es falso mientras no se revoque. Acá se quita todo y se devuelve
--   solo leer, en ESE orden (al revés el revoke se llevaría el select). Lo mismo
--   con la secuencia de `orden`: sin revocarla, cualquier sesión podría moverla.
--   Sin trigger de INSERT, igual que la 0508: las reglas del momento de escribir
--   viven en la función guardián. Los triggers que sí hay bloquean UPDATE y DELETE
--   (por fila) y TRUNCATE (por sentencia) con un mensaje propio de las constancias:
--   el TRUNCATE lo frena aunque lo intente el dueño.
--   `service_role` conserva sus permisos por defecto, igual que en la 0508.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--   · No toca `fn_liquidacion_diferencias`, `fn_liquidaciones_pendientes`
--     (0475), `fn_liquidacion_pagar` ni `fn_liquidacion_anular`: por eso no
--     lleva md5 de partida. Las cuatro siguen exactamente como estaban.
--   · No cambia ninguna cifra ni ninguna fórmula de pago. Nada de lo que escribe
--     mueve un sol: una constancia es un registro, no un pago.
--   · No hace volver la pastilla «N con diferencias» a la lista: eso exigiría
--     reescribir `fn_liquidaciones_pendientes` y se decide aparte, con tiempos
--     medidos en producción.
--   · No cierra los privilegios de `liquidacion_pagada` (la tabla a la que apunta
--     la FK): se trata en su propia migración.
--
-- ── IDEMPOTENTE ─────────────────────────────────────────────────────────────
--   `create table if not exists`, `create unique index if not exists`,
--   `drop policy/trigger if exists` + create, y `create or replace` en las
--   funciones. Se puede pegar dos veces. Las cuatro funciones nuevas no tienen
--   versiones anteriores, así que no puede quedar una sobrecarga fantasma.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_liquidacion_constatar(uuid, int, text, text, text, text, uuid);
--   drop function if exists fn_liquidacion_constancia_estado(uuid);
--   drop function if exists fn_liquidacion_huella(jsonb);
--   drop table    if exists liquidacion_constancias;   -- se pierden las constancias; liquidacion_pagada no se toca
--   drop function if exists fn_trg_constancia_es_inmutable();
--   delete from migraciones_aplicadas where numero = 542;
--   notify pgrst, 'reload schema';
--   Lo que NO se borra, a propósito: las filas de `correcciones_auditoria` con
--   campo 'liquidacion_diferencia_constatada' (es rastro). La pantalla, si ya está
--   publicada, no se rompe: sin poder leer el estado no dibuja el botón y se
--   comporta como antes.
--
-- ── SE ROMPE SI ─────────────────────────────────────────────────────────────
--   · Alguien le da `insert` a `authenticated` sobre la tabla (o uso de su
--     secuencia): la prueba 435 lo caza, con un control que reabre el hueco a propósito.
--   · `fn_liquidacion_diferencias` cambia el nombre de un concepto o la fórmula de
--     la huella cambia sin subir `huella_formula`: todas las constancias reabren
--     una vez. Es lo que se quiere con el nombre; con la fórmula, por eso existe
--     la columna.
--   · Una carrera con «Volver a marcarla como pagada» (versión nueva) entre que
--     se mira y que se guarda: la constancia queda atada a la versión vieja y es
--     inerte, porque todo lector resuelve por la ÚLTIMA versión. No afecta nada.
--   · Una persona se reactiva (sin fecha de cese) con una constancia vigente: las
--     cifras no cambian, la constancia sigue valiendo, pero no se puede registrar
--     otra; sí se puede retirar.
-- ============================================================================


-- ── 0 · La guardia ──────────────────────────────────────────────────────────
-- Esta migración LLAMA a funciones que no escribe. Si alguna no está, o no es la
-- versión que se asume, no se aplica nada.
do $guardia$
begin
  if to_regclass('public.liquidacion_pagada') is null then
    raise exception '0542 · PARA. No existe liquidacion_pagada. No se aplicó nada.';
  end if;
  if to_regprocedure('public.fn_liquidacion_diferencias(uuid)') is null then
    raise exception '0542 · PARA. No existe fn_liquidacion_diferencias(uuid). No se aplicó nada.';
  end if;
  if pg_get_function_result(to_regprocedure('public.fn_liquidacion_diferencias(uuid)')) not like '%origen text%' then
    raise exception '0542 · PARA. fn_liquidacion_diferencias no devuelve la columna origen (es anterior a la 0454). No se aplicó nada.';
  end if;
  if to_regprocedure('public.fn_persona_liquidada(uuid)') is null then
    raise exception '0542 · PARA. No existe fn_persona_liquidada(uuid). No se aplicó nada.';
  end if;
  -- La 0499 compara la fecha de cese de la liquidación con la de HOY; la 0421 solo
  -- mira que exista alguna versión no anulada, y con ella una constancia podría
  -- cerrar el aviso de un cese que ya no es el de la persona.
  if (select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.fn_persona_liquidada(uuid)'))
       not like '%lp.fecha_cese = p.fecha_cese%' then
    raise exception '0542 · PARA. fn_persona_liquidada es anterior a la 0499 (no compara la fecha de cese): pega primero la 0499. No se aplicó nada.';
  end if;
  if to_regprocedure('public.fn_es_admin_o_lider()') is null
     or to_regprocedure('public.fn_persona_actual_id()') is null then
    raise exception '0542 · PARA. Faltan fn_es_admin_o_lider() o fn_persona_actual_id(). No se aplicó nada.';
  end if;
end
$guardia$;


-- ── 1 · El libro de constancias ─────────────────────────────────────────────
create table if not exists liquidacion_constancias (
  -- Orden estable dentro de la base (identity: monótono aunque dos filas
  -- compartan `now()`). No es la clave; sirve solo para elegir «la más reciente»
  -- donde hace falta, sin depender de un reloj.
  orden          bigint generated always as identity,
  id             uuid not null default gen_random_uuid(),

  persona_id     uuid not null,
  version        int  not null,

  huella         text not null check (huella ~ '^[0-9a-f]{32}$'),
  -- Con qué fórmula se calculó la huella (ver «La huella»).
  huella_formula smallint not null default 1,

  -- Lo calcula el servidor al escribir; nadie lo elige.
  sentido        text not null check (sentido in ('a_favor_persona', 'a_favor_cayla')),

  decision       text not null check (decision in
                   ('pagado_es_correcto', 'no_se_reclama', 'devolucion_acordada', 'retirada')),
  apoyo          text check (apoyo in
                   ('regla_cambio_despues', 'dato_de_hoy_mal_cargado', 'confirmado_por_contador_o_laboralista')),
  -- El mínimo cuenta caracteres de verdad: espacios, tabuladores y saltos de
  -- línea no suman (btrim a secas solo quitaría los espacios).
  motivo         text not null check (char_length(btrim(motivo, E' \t\r\n')) >= 10),

  -- Lo que vio quien constató: las filas reales, tal como el servidor las
  -- recalculó en ese instante (nunca lo que mande el navegador).
  diferencias    jsonb not null check (jsonb_typeof(diferencias) = 'array' and jsonb_array_length(diferencias) > 0),

  reemplaza_id   uuid,

  constatada_por uuid not null references personas(id),
  constatada_at  timestamptz not null default now(),

  primary key (id),
  unique (orden),
  -- Para que la cadena de reemplazos solo pueda apuntar a una constancia de la
  -- MISMA persona, versión y huella.
  unique (id, persona_id, version, huella),

  constraint constancia_version_existe
    foreign key (persona_id, version) references liquidacion_pagada (persona_id, version)
    on delete restrict,
  constraint constancia_cadena
    foreign key (reemplaza_id, persona_id, version, huella)
    references liquidacion_constancias (id, persona_id, version, huella)
    on delete restrict,

  -- Decisión, sentido y apoyo van juntos o no van.
  constraint constancia_decision_coherente check (
       (decision = 'pagado_es_correcto' and sentido = 'a_favor_persona' and apoyo is not null)
    or (decision in ('no_se_reclama', 'devolucion_acordada') and sentido = 'a_favor_cayla' and apoyo is null)
    or (decision = 'retirada' and apoyo is null)
  ),
  -- Una retirada reemplaza a algo: sin nada que reemplazar no hay nada que retirar.
  constraint constancia_retirada_reemplaza check (decision <> 'retirada' or reemplaza_id is not null)
);

comment on table liquidacion_constancias is
  'Constancias sobre una diferencia REAL entre una liquidación pagada y el cálculo de hoy: quién, cuándo, qué decidió, por qué y en qué se apoya. Solo se agrega (corregir = escribir otra que reemplaza a la anterior); la vigente es la que nadie reemplaza. Vale solo mientras la huella del cálculo coincida: si el cálculo cambia, el aviso vuelve solo. Escritura únicamente por fn_liquidacion_constatar. Ver 0542.';
comment on column liquidacion_constancias.huella is
  'md5 de las filas de concepto con origen real (concepto, diferencia en centavos), sin la fila TOTAL. Ver fn_liquidacion_huella.';
comment on column liquidacion_constancias.huella_formula is
  'Versión de la fórmula de la huella con que se calculó. Cambiar la fórmula exige subirla (default de esta columna y filtro de fn_liquidacion_constancia_estado) en una migración nueva: las constancias de otra versión quedan inertes.';
comment on column liquidacion_constancias.sentido is
  'Lo calcula el servidor: a_favor_persona si hoy se le daría más (ahora > pagado), a_favor_cayla si se le pagó de más.';

-- Cada constancia se reemplaza como mucho una vez, y hay una sola raíz por
-- (persona, versión, huella, fórmula): la cadena es lineal y su cabeza es única.
-- La fórmula entra en la raíz porque el mismo md5 con otra fórmula NO es la misma
-- situación (ver «La huella»).
create unique index if not exists ux_constancia_un_solo_reemplazo
  on liquidacion_constancias (reemplaza_id) where reemplaza_id is not null;
create unique index if not exists ux_constancia_una_sola_raiz
  on liquidacion_constancias (persona_id, version, huella, huella_formula) where reemplaza_id is null;
create index if not exists idx_constancia_persona_version
  on liquidacion_constancias (persona_id, version);

-- Ni el propio DO la edita, la borra ni la vacía.
create or replace function fn_trg_constancia_es_inmutable()
returns trigger
language plpgsql
as $fn$
begin
  raise exception
    'Una constancia no se modifica, no se borra ni se vacía. Si estaba mal, retírala o deja otra encima: la anterior queda como historial.';
end;
$fn$;

drop trigger if exists trg_constancia_inmutable on liquidacion_constancias;
create trigger trg_constancia_inmutable
  before update or delete on liquidacion_constancias
  for each row execute function fn_trg_constancia_es_inmutable();

drop trigger if exists trg_constancia_no_vaciar on liquidacion_constancias;
create trigger trg_constancia_no_vaciar
  before truncate on liquidacion_constancias
  for each statement execute function fn_trg_constancia_es_inmutable();

-- Lectura: quien ya puede ver las liquidaciones.
alter table liquidacion_constancias enable row level security;

drop policy if exists liquidacion_constancias_lectura on liquidacion_constancias;
create policy liquidacion_constancias_lectura on liquidacion_constancias
  for select to authenticated
  using (fn_es_admin_o_lider() is true);

-- Escritura: ninguna. Primero se quita TODO (lo que Supabase concede por
-- defecto incluye escribir y `truncate`) y después se devuelve solo leer. El
-- orden importa: al revés, el revoke se llevaría también el select. Y la
-- secuencia de `orden`, que si no cualquier sesión podría mover.
revoke all on liquidacion_constancias from anon, authenticated, public;
grant select on liquidacion_constancias to authenticated;
revoke all on sequence liquidacion_constancias_orden_seq from anon, authenticated, public;


-- ── 2 · La huella ───────────────────────────────────────────────────────────
-- Entrada: un arreglo jsonb de {concepto, centavos}. Una sola definición de la
-- fórmula, usada por la lectura y por el guardián para que nunca diverjan.
-- STABLE y no IMMUTABLE a propósito: ordena con collation "C" explícita, pero no
-- vale la pena prometerle al planificador una pureza que nadie necesita.
-- CAMBIAR ESTA FÓRMULA exige subir `huella_formula` (ver «La huella»).
create or replace function fn_liquidacion_huella(p_real jsonb)
returns text
language sql
stable
set search_path = public
as $fn$
  select md5(coalesce(
    string_agg(coalesce(e->>'concepto', '?') || '=' || coalesce(e->>'centavos', '?'), '|'
               order by coalesce(e->>'concepto', '?') collate "C"),
    ''))
  from jsonb_array_elements(coalesce(p_real, '[]'::jsonb)) e;
$fn$;

comment on function fn_liquidacion_huella(jsonb) is
  'md5 de [{concepto, centavos}] ordenado por concepto en collation C. Define cuándo una constancia sigue valiendo; cambiarla exige subir huella_formula. Ver 0542.';

revoke execute on function fn_liquidacion_huella(jsonb) from public, anon, authenticated;


-- ── 3 · Lo que la pantalla necesita, de UN solo instante ───────────────────
-- Una fila: la versión de la liquidación, si hay diferencia real, de qué sentido,
-- las filas reales, su huella, si se puede constatar (y por qué no, en palabras),
-- la cabeza de la cadena para esa huella, la constancia que cierra el aviso hoy
-- y, si no hay ninguna vigente, la última que valió con otras cifras. Sin fila:
-- la persona no tiene liquidación pagada vigente (nunca se pagó, o la última
-- versión está anulada).
--
-- La pantalla pinta EXACTAMENTE `filas` en el modal, y el guardián recalcula
-- desde aquí: así «lo que vio quien constató» es cierto, y no sale de dos
-- llamadas que pudieron ver instantes distintos.
create or replace function fn_liquidacion_constancia_estado(p_persona_id uuid)
returns table (
  version         int,
  hay_real        boolean,
  sentido         text,    -- 'a_favor_persona' | 'a_favor_cayla' | 'mixto' | null
  filas           jsonb,   -- [{concepto, pagado, ahora, diferencia, centavos}]
  huella          text,
  puede_constatar boolean,
  motivo_no       text,
  cabeza_id       uuid,    -- la constancia que hay que mandar como p_reemplaza_id
  vigente         jsonb,   -- la que cierra el aviso ahora (null si no hay o se retiró)
  anterior        jsonb    -- si no hay vigente: la última que valió con OTRAS cifras (el cálculo cambió desde entonces)
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
#variable_conflict use_column
declare
  v_f      liquidacion_pagada%rowtype;
  v_cese   date;
  v_filas  jsonb;
  v_pos    int;
  v_neg    int;
  v_hay    boolean;
  v_sent   text;
  v_huella text;
  v_cab    liquidacion_constancias%rowtype;
  v_ant    liquidacion_constancias%rowtype;
  v_desc   numeric;
  v_puede  boolean := false;
  v_no     text;
  v_vig    jsonb;
  v_antj   jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la constancia de una liquidación.';
  end if;

  select lp.* into v_f from liquidacion_pagada lp
   where lp.persona_id = p_persona_id
   order by lp.version desc limit 1;
  if not found or v_f.anulada is true then return; end if;

  select p.fecha_cese into v_cese from personas p where p.id = p_persona_id;

  -- Solo conceptos con origen 'real'; sin TOTAL (ver la cabecera, «La huella»).
  select coalesce(jsonb_agg(jsonb_build_object(
           'concepto', d.concepto, 'pagado', d.pagado, 'ahora', d.ahora,
           'diferencia', d.diferencia, 'centavos', round(d.diferencia * 100)::bigint)
           order by d.concepto collate "C"), '[]'::jsonb),
         count(*) filter (where d.diferencia > 0),
         count(*) filter (where d.diferencia < 0)
    into v_filas, v_pos, v_neg
    from fn_liquidacion_diferencias(p_persona_id) d
   where d.origen = 'real' and d.concepto <> 'TOTAL';

  v_hay := jsonb_array_length(v_filas) > 0;

  if v_hay then
    v_huella := fn_liquidacion_huella(v_filas);
    v_sent := case
      when v_pos > 0 and v_neg = 0 then 'a_favor_persona'
      when v_neg > 0 and v_pos = 0 then 'a_favor_cayla'
      else 'mixto'
    end;

    -- Primero el cese: si la liquidación ya no describe el cese actual, lo demás
    -- (incluido el sentido de una diferencia calculada contra OTRA fecha) no
    -- tiene sentido discutirlo.
    if fn_persona_liquidada(p_persona_id) is not true then
      v_no := case
        when v_cese is null then
          'Esta persona ya no figura como cesada (se reactivó): no hay una liquidación que describa su cese actual.'
        else
          'Esta liquidación ya no describe el cese actual de la persona (su fecha de cese cambió): se corrige anulándola y liquidando de nuevo, no con un registro.'
      end;
    else
      -- La fila del sueldo con un descuento de cierre ya registrado no mide la
      -- diferencia real (ver la cabecera). Solo se mira si esa fila está entre
      -- las reales: es la única forma en que el descuento la contamina.
      if exists (select 1 from jsonb_array_elements(v_filas) e where e->>'concepto' = 'Sueldo del periodo') then
        v_desc := coalesce(
          (fn_liquidacion(p_persona_id, coalesce(v_cese, v_f.fecha_cese))->'periodo'->'detalle'->>'descuentos')::numeric, 0);
      end if;

      if coalesce(v_desc, 0) <> 0 then
        v_no := 'El sueldo del periodo ya tiene un descuento de cierre registrado, y con él esa diferencia todavía no refleja lo que de verdad cambió. Cierra el mes y vuelve a mirar; si sigue abierta, resuélvela a mano.';
      elsif v_sent = 'mixto' then
        v_no := 'Las diferencias van en sentidos opuestos (una a favor de la persona y otra a favor de CAYLA): hoy no se puede registrar qué pasó, hay que resolverla a mano.';
      else
        v_puede := true;
      end if;
    end if;

    -- La cabeza de la cadena para ESTA huella: la constancia que nadie reemplazó.
    select c.* into v_cab from liquidacion_constancias c
     where c.persona_id = p_persona_id and c.version = v_f.version and c.huella = v_huella
       and c.huella_formula = 1
       and not exists (select 1 from liquidacion_constancias r where r.reemplaza_id = c.id)
     order by c.orden desc limit 1;

    if found and v_cab.decision <> 'retirada' then
      v_vig := jsonb_build_object(
        'id', v_cab.id, 'decision', v_cab.decision, 'apoyo', v_cab.apoyo, 'motivo', v_cab.motivo,
        'por', (select p.nombres || ' ' || p.apellidos from personas p where p.id = v_cab.constatada_por),
        'cuando', v_cab.constatada_at, 'diferencias', v_cab.diferencias);
    end if;

    -- Sin vigente: la última constancia que valió con otras cifras (si el cálculo
    -- cambió desde entonces), para mostrar las dos lado a lado. Una retirada no
    -- cuenta. Con una vigente no se devuelve ninguna: «anterior» podría ser más
    -- nueva que ella (A → B → A) y las dos se contradirían en pantalla.
    if v_vig is null then
      select c.* into v_ant from liquidacion_constancias c
       where c.persona_id = p_persona_id and c.version = v_f.version
         and c.huella <> v_huella
         and c.huella_formula = 1
         and c.decision <> 'retirada'
         and not exists (select 1 from liquidacion_constancias r where r.reemplaza_id = c.id)
       order by c.orden desc limit 1;

      if found then
        v_antj := jsonb_build_object(
          'id', v_ant.id, 'decision', v_ant.decision, 'apoyo', v_ant.apoyo, 'motivo', v_ant.motivo,
          'por', (select p.nombres || ' ' || p.apellidos from personas p where p.id = v_ant.constatada_por),
          'cuando', v_ant.constatada_at, 'diferencias', v_ant.diferencias);
      end if;
    end if;
  else
    v_no := 'No hay una diferencia real que constatar.';
  end if;

  return query select v_f.version, v_hay, v_sent, v_filas, v_huella, v_puede, v_no, v_cab.id, v_vig, v_antj;
end;
$fn$;

comment on function fn_liquidacion_constancia_estado(uuid) is
  'Estado de la constancia de la diferencia real de una liquidación pagada, de un solo instante: filas reales, huella, si se puede constatar, cabeza de la cadena, constancia vigente y, sin vigente, la última que valió con otras cifras. Sin fila: no hay liquidación pagada vigente. Ver 0542.';

revoke execute on function fn_liquidacion_constancia_estado(uuid) from public, anon;
grant  execute on function fn_liquidacion_constancia_estado(uuid) to authenticated;


-- ── 4 · La única puerta de escritura ────────────────────────────────────────
-- Recalcula TODO en el servidor y lo compara con lo que la pantalla vio. Nada de
-- lo que cuenta —quién, cuándo, sentido, filas— viaja desde el navegador.
create or replace function fn_liquidacion_constatar(
  p_persona_id   uuid,
  p_version      int,
  p_huella       text,
  p_decision     text,
  p_apoyo        text,
  p_motivo       text,
  p_reemplaza_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
#variable_conflict use_column
declare
  v_quien  uuid := fn_persona_actual_id();
  v_est    record;
  v_motivo text;
  v_apoyo  text;
  v_id     uuid;
  v_cuando timestamptz;
  v_antes  text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede dejar constancia de una diferencia en una liquidación.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  if p_decision is null or p_decision not in
       ('pagado_es_correcto', 'no_se_reclama', 'devolucion_acordada', 'retirada') then
    raise exception 'La decisión no es válida.';
  end if;

  v_motivo := btrim(coalesce(p_motivo, ''), E' \t\r\n');
  if char_length(v_motivo) < 10 then
    raise exception 'Cuéntalo en al menos 10 caracteres: dentro de un año este texto es lo único que explica por qué se cerró el aviso.';
  end if;

  if p_decision = 'pagado_es_correcto' then
    if p_apoyo is null or p_apoyo not in
         ('regla_cambio_despues', 'dato_de_hoy_mal_cargado', 'confirmado_por_contador_o_laboralista') then
      raise exception 'Elige en qué te apoyas para decir que lo pagado era lo correcto.';
    end if;
    v_apoyo := p_apoyo;
  else
    v_apoyo := null;
  end if;

  -- Dos personas constatando a la misma persona a la vez se turnan: la segunda
  -- ve lo que dejó la primera y el compare-and-swap de abajo la rechaza.
  perform pg_advisory_xact_lock(hashtextextended('liquidacion_constancia:' || p_persona_id::text, 0));

  select * into v_est from fn_liquidacion_constancia_estado(p_persona_id);
  if not found then
    raise exception 'Esa persona no tiene una liquidación pagada vigente: no hay nada que constatar.';
  end if;

  -- Una versión que no se manda (null) tampoco es la que se vio.
  if p_version is null or v_est.version is distinct from p_version then
    raise exception 'La liquidación cambió mientras mirabas (hay una versión nueva). Ábrela de nuevo.';
  end if;
  if not v_est.hay_real then
    raise exception 'Ya no hay una diferencia real que constatar: el cálculo cambió mientras mirabas. Ábrela de nuevo.';
  end if;
  -- Retirar lo ya registrado no depende de que hoy se pueda registrar algo nuevo
  -- (por ejemplo, la persona se reactivó): quien se equivocó tiene que poder
  -- reabrir el aviso.
  if p_decision <> 'retirada' and v_est.puede_constatar is not true then
    raise exception '%', v_est.motivo_no;
  end if;
  if v_est.huella is distinct from p_huella then
    raise exception 'El cálculo cambió mientras mirabas, así que lo que viste ya no es lo que daría hoy. Ábrela de nuevo y revisa las cifras nuevas.';
  end if;

  if p_decision = 'pagado_es_correcto' and v_est.sentido <> 'a_favor_persona' then
    raise exception 'Esta diferencia es a favor de CAYLA (se pagó de más): «Lo pagado era lo correcto» no corresponde.';
  end if;
  if p_decision in ('no_se_reclama', 'devolucion_acordada') and v_est.sentido <> 'a_favor_cayla' then
    raise exception 'Esta diferencia es a favor de la persona: no se puede cerrar con una decisión de «no se reclama» o «devolución». Si falta pagarla, sigue abierta.';
  end if;

  if p_decision = 'retirada' and v_est.vigente is null then
    raise exception 'No hay una constancia vigente que retirar.';
  end if;

  -- Compare-and-swap: lo que la pantalla creía que era la última tiene que
  -- seguir siéndolo.
  if v_est.cabeza_id is distinct from p_reemplaza_id then
    raise exception 'Otra persona ya registró algo sobre esta diferencia. Ábrela de nuevo para verlo.';
  end if;

  select c.decision into v_antes from liquidacion_constancias c where c.id = p_reemplaza_id;

  begin
    insert into liquidacion_constancias
      (persona_id, version, huella, huella_formula, sentido, decision, apoyo, motivo, diferencias, reemplaza_id, constatada_por)
    values
      (p_persona_id, v_est.version, v_est.huella, 1, v_est.sentido, p_decision, v_apoyo, v_motivo,
       v_est.filas, p_reemplaza_id, v_quien)
    returning id, constatada_at into v_id, v_cuando;
  exception when unique_violation then
    raise exception 'Otra persona ya registró algo sobre esta diferencia. Ábrela de nuevo para verlo.';
  end;

  -- El mismo rastro que deja fn_liquidacion_pagar. El texto libre NO va aquí: el
  -- historial de la ficha lo muestra, y el motivo ya vive en la tabla, con la
  -- lectura limitada a admin y líder DO.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'liquidacion_diferencia_constatada', v_antes,
     p_decision || ' · versión ' || v_est.version || ' · huella ' || left(v_est.huella, 8),
     v_quien, 'Constancia sobre una diferencia de la liquidación pagada');

  return jsonb_build_object('id', v_id, 'decision', p_decision, 'version', v_est.version,
                            'constatada_at', v_cuando);
end;
$fn$;

comment on function fn_liquidacion_constatar(uuid, int, text, text, text, text, uuid) is
  'Única puerta de escritura de liquidacion_constancias. Recalcula la diferencia en el servidor, exige que coincida con lo que la pantalla vio (versión y huella), que sea de un solo sentido, que la liquidación sea del cese actual, y que nadie se haya adelantado (p_reemplaza_id). Ver 0542.';

revoke execute on function fn_liquidacion_constatar(uuid, int, text, text, text, text, uuid) from public, anon;
grant  execute on function fn_liquidacion_constatar(uuid, int, text, text, text, text, uuid) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (542, 'la_diferencia_de_una_liquidacion_pagada_se_cierra_con_constancia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación ─────────────────────────────────────────────────────────────
-- Va la última porque el SQL Editor solo muestra el resultado de la última
-- sentencia. Tiene que dar: la tabla con RLS, ningún privilegio de escritura
-- para authenticated (ni sobre la secuencia), leer sí, los dos triggers, las cuatro
-- funciones, y el registro con SU nombre.
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'liquidacion_constancias')                    as tabla,
  (select relrowsecurity from pg_class where oid = 'public.liquidacion_constancias'::regclass)   as rls_activa,
  has_table_privilege('authenticated', 'public.liquidacion_constancias', 'select')               as leer_si,
  has_table_privilege('authenticated', 'public.liquidacion_constancias', 'insert')               as insert_debe_ser_false,
  has_table_privilege('authenticated', 'public.liquidacion_constancias', 'update')               as update_debe_ser_false,
  has_table_privilege('authenticated', 'public.liquidacion_constancias', 'delete')               as delete_debe_ser_false,
  has_table_privilege('authenticated', 'public.liquidacion_constancias', 'truncate')             as truncate_debe_ser_false,
  has_sequence_privilege('authenticated', 'public.liquidacion_constancias_orden_seq', 'usage')   as secuencia_debe_ser_false,
  (select count(*) from pg_trigger
    where tgrelid = 'public.liquidacion_constancias'::regclass and not tgisinternal)             as triggers_deben_ser_2,
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('fn_liquidacion_huella', 'fn_liquidacion_constancia_estado',
                      'fn_liquidacion_constatar', 'fn_trg_constancia_es_inmutable'))             as funciones_deben_ser_4,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 542)               as registro;
