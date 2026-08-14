-- ============================================================================
-- 0251 — Una liquidación marcada por error se puede anular, sin borrar nada
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una liquidación marcada como pagada POR ERROR deje de contar —en la
--   pantalla de Liquidaciones, en la de Planilla, en el freno del cierre y en la
--   hoja de la persona— sin que desaparezca de ningún sitio. La versión errónea
--   se queda entera y legible; encima suya se guarda una versión de anulación,
--   en cero, con motivo obligatorio y con firma de quién la anuló.
--
-- QUÉ ASUME
--   La 0167: `liquidacion_pagada` versiona por persona, es inmutable por trigger
--   (BEFORE UPDATE OR DELETE) y todos sus lectores toman la ÚLTIMA versión.
--   La 0210: `fn_liquidaciones_del_periodo` avisa en la pantalla de Planilla.
--   La 0244: el freno del cierre y el aviso de la hoja leen esa misma tabla.
--
-- ── EL CASO REAL QUE LO PIDE ────────────────────────────────────────────────
--
-- Medido en producción el 2026-08-14, y confirmado contra el banco por Felipe.
--
-- Una persona EN PERIODO DE PRUEBA, que nunca entró a planilla, cesó el
-- 07/08/2026. Se le pagó un adelanto de S/358.73 el 06/08, fuera de planilla,
-- registrado como descuento del periodo. El 10/08 alguien apretó «Liquidación
-- pagada» y el sistema congeló una liquidación de S/1,106.82.
--
-- ESE DINERO NUNCA SALIÓ DEL BANCO. Solo salieron los S/358.73.
--
-- Y el importe congelado está mal por partida doble: se congeló el 10/08, TRES
-- DÍAS ANTES de que la 0239 —el arreglo del divisor— llegara a producción, así
-- que salió inflado unas 3.1 veces. Lo que de verdad ganó del 29/07 al 07/08 son
-- S/298.73 (pago base 249.22 + feriado 49.51), leído en la pantalla ya
-- corregida.
--
-- Hoy ese registro no solo miente: ESTORBA.
--   · Planilla dice «Ya cobró su liquidación el 10 ago · S/1,106.82 — ya está
--     descontado aquí», y no está descontado nada porque no se pagó nada.
--   · El freno del cierre (0244) la nombra y puede impedir cerrar el mes.
--   · Cualquier recuento de liquidaciones pagadas suma S/1,106.82 que no salieron.
--
-- Y NO HABÍA FORMA DE DESHACERLO. `fn_liquidacion_pagar` (0167) solo sabe
-- INSERTAR una versión nueva calculando `fn_liquidacion` AHORA; no existía nada
-- que anulara ni corrigiera una liquidación mal marcada. El trigger de
-- inmutabilidad bloquea el update y el delete, que es exactamente como tiene que
-- ser: versionar es la única vía.
--
-- ── POR QUÉ UNA VERSIÓN EN CERO Y NO OTRA COSA ──────────────────────────────
--
-- Porque es la única forma que respeta las dos reglas de esta tabla a la vez:
-- nada se borra, y los ocho lectores toman la última versión. Se comprobó
-- lector por lector antes de escribir esto —sacando la lista de `pg_proc` y de
-- `information_schema.views`, no de un grep— y NINGUNO suma versiones. La idea
-- de partida servía para los números.
--
-- ── PERO DOS LECTORES NO MIRAN EL MONTO: MIRAN SI HAY FILA ──────────────────
--
-- Medido: con una v2 en ceros, `fn_liquidaciones_pendientes.pagada` seguía en
-- `true`, porque es literalmente `(f.persona_id is not null)`. Consecuencias en
-- `apps/web/app/(admin)/admin/liquidaciones/page.tsx`:
--
--   · la fila se queda en el bloque «Pagadas» para siempre (page.tsx:168);
--   · `total` muestra S/0.00 en vez de lo que de verdad se le debe, porque
--     `coalesce(f.total, …)` corta en un 0.00 que no es nulo (0167:289);
--   · y el botón «Marcar como pagada» DESAPARECE (page.tsx:409, la condición es
--     `!pagada`). O sea: anulada la liquidación, ya no había forma en la interfaz
--     de congelar la correcta. Eso es un bloqueo duro, no una molestia estética,
--     y para el caso de arriba importa: quedan S/298.73 realmente ganados.
--
-- Y `fn_liquidaciones_del_periodo` (0210) mete a la persona en el objeto por su
-- última versión sin mirar montos, así que el cartel de Planilla seguía
-- pintándose: «Ya cobró su liquidación el 14 ago · S/0.00» — la misma frase
-- falsa, con otro número igual de falso y encima refechada.
--
-- Por eso esta migración no es solo una función nueva. Sin tocar esos dos
-- lectores, anular cambiaría una cifra falsa por un cero absurdo y crearía un
-- problema nuevo.
--
-- ── POR QUÉ UNA COLUMNA Y NO «total = 0» COMO SEÑAL ─────────────────────────
--
-- Porque una liquidación legítima de S/0.00 EXISTE y se puede congelar: se probó
-- contra el Postgres local con una persona sin salario asignado, y
-- `fn_liquidacion_pagar` no comprueba que el total sea mayor que cero. Deducir
-- «anulada» de un cero confundiría los dos casos para siempre.
--
-- Tampoco vale escribirlo en `nota`: la 0244 ya dejó por escrito por qué un
-- freno atado a un texto literal deja de morder el día que alguien reescribe el
-- botón.
--
-- ── LA INVARIANTE QUE EVITA TOCAR LA 0244 ───────────────────────────────────
--
-- Los otros dos lectores que sí deciden por monto —el freno de
-- `fn_planilla_congelar` (`and lq.monto_periodo > 0`) y el aviso de
-- `fn_liquidacion` (`if coalesce(v_liq, 0) > 0`)— se apagan solos con los ceros.
-- Para que eso siga siendo cierto el día que nadie recuerde esta migración, la
-- regla no se deja en la costumbre de una función: se ATA AL ESQUEMA con un
-- CHECK. Una fila anulada TIENE que tener sus cinco montos en cero.
--
-- Así, cualquier lector que filtre por monto queda correcto por construcción, y
-- la 0244 —una función de 500 líneas que ya está en producción— no se toca. No
-- reescribir lo que ya funciona es también una decisión de seguridad: copiar mal
-- el cuerpo de una función grande revierte en silencio lo que arregló.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
--   · No anula ninguna liquidación. Es genérica y no lleva dentro el id de nadie:
--     los datos personales no se commitean. Anular es una llamada, y va abajo.
--   · No pone el botón en la pantalla. Hoy el único camino a esta función es el
--     SQL Editor, y eso es una deuda dicha en voz alta: la 0243 dejó escrito que
--     el agujero no está en el script, está en que el camino cómodo no pasa por
--     él. El sitio natural del botón es page.tsx:420-424 —la rama donde hoy solo
--     hay un texto— con un campo de motivo OBLIGATORIO al lado.
--   · No decide si el dinero salió del banco. Eso no lo sabe ninguna tabla de
--     este sistema: lo dice el extracto. Ver
--     scripts/sql-manual/liquidaciones_registradas_contra_el_banco.sql.
--
-- ── CÓMO SE USA (desde el SQL Editor, que hoy es el único camino) ───────────
--
--   select set_config('request.jwt.claim.sub', 'AQUI-EL-AUTH-USER-ID', true);
--   select fn_liquidacion_anular(
--            'AQUI-EL-PERSONA-ID',
--            'Marcada por error el 10/08. El dinero nunca salio del banco: solo se
--             pago un adelanto de S/358.73 el 06/08, ya registrado como descuento.
--             Ademas el importe venia inflado por el divisor de antes de la 0239.');
--
--   El `set_config` hace falta porque `congelada_por` es NOT NULL y sale de
--   `fn_persona_actual_id()`. Sin sesión, la función se niega y lo dice.
--
--   Después de anular, la fila vuelve sola a «Dentro del plazo» o «Pasadas de
--   plazo» y reaparece el botón «Marcar como pagada» para congelar la correcta.
--
-- ── IDEMPOTENTE ─────────────────────────────────────────────────────────────
--   `add column if not exists`, los CHECK guardados por `pg_constraint`, y
--   `create or replace` en las cuatro funciones. Se puede pegar dos veces.
--   Y anular dos veces a la misma persona tampoco escribe dos filas: la segunda
--   llamada no hace nada y devuelve lo que ya había.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   drop function if exists fn_liquidacion_anular(uuid, text);
--   alter table liquidacion_pagada drop column if exists anulada,
--                                  drop column if exists motivo_anulacion,
--                                  drop column if exists anula_version;
--   y volver a pegar de 0167 (fn_liquidaciones_pendientes, fn_liquidacion_diferencias)
--   y de 0210 (fn_liquidaciones_del_periodo).
--
--   OJO: las filas de anulación NO se borran, son el rastro. Quitando la columna
--   quedarían como versiones en cero sin nada que las explique, así que revertir
--   de verdad exige listar antes qué filas tienen `anulada = true` y anotarlo
--   fuera del sistema.
-- ============================================================================


-- ── 1 · La marca ────────────────────────────────────────────────────────────
-- Explícita y no deducida. `default false` sobre una tabla que hoy solo tiene
-- pagos de verdad: ninguna fila existente cambia de significado.
alter table liquidacion_pagada
  add column if not exists anulada          boolean not null default false;

alter table liquidacion_pagada
  add column if not exists motivo_anulacion text;

alter table liquidacion_pagada
  add column if not exists anula_version    int;

comment on column liquidacion_pagada.anulada is
  'Esta versión NO es un pago: es la anulación de la versión anterior, que se '
  'marcó como pagada por error. Sus cinco montos están en cero por CHECK. La '
  'versión anulada sigue guardada entera. Ver 0251.';

comment on column liquidacion_pagada.motivo_anulacion is
  'Por qué se anuló, escrito a mano y obligatorio. Dentro de un año, una fila en '
  'cero sin motivo no se puede leer.';

comment on column liquidacion_pagada.anula_version is
  'Qué versión anula esta fila. Siempre la inmediatamente anterior; se guarda '
  'igual para que la fila se explique sola sin abrir el jsonb.';


-- ── 2 · La invariante, atada al esquema ─────────────────────────────────────
-- Esto es lo que permite NO tocar la 0244. El freno del cierre filtra por
-- `monto_periodo > 0` y el aviso de la hoja por `coalesce(v_liq, 0) > 0`: los
-- dos se apagan solos mientras una fila anulada esté en cero. Que siga estándolo
-- no puede depender de que quien escriba la próxima función se acuerde.
do $mig$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'liquidacion_pagada'::regclass
      and conname  = 'liquidacion_anulada_en_cero'
  ) then
    alter table liquidacion_pagada
      add constraint liquidacion_anulada_en_cero
      check (
        anulada is not true
        or (monto_periodo = 0 and monto_vacaciones = 0
            and monto_grati = 0 and monto_cts = 0 and total = 0)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'liquidacion_pagada'::regclass
      and conname  = 'liquidacion_anulada_se_explica'
  ) then
    alter table liquidacion_pagada
      add constraint liquidacion_anulada_se_explica
      check (
        anulada is not true
        or (length(trim(coalesce(motivo_anulacion, ''))) >= 3
            and anula_version is not null)
      );
  end if;
end
$mig$;


-- ── 3 · Anular ──────────────────────────────────────────────────────────────
-- Escribe una versión más, nunca corrige la anterior: el trigger de
-- inmutabilidad de la 0167 bloquea update y delete, y está bien que lo haga.
create or replace function fn_liquidacion_anular(p_persona_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_f      liquidacion_pagada%rowtype;
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
  v_yo     uuid;
  v_ver    int;
begin
  -- `is not true` y no `not (…)`: un null no pasa como autorizado. Estándar del
  -- repo desde la 0078.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder anula una liquidación marcada por error.';
  end if;

  -- El motivo se exige ANTES de tocar nada. `correcciones_auditoria` tiene un
  -- CHECK de tres caracteres, así que sin esta comprobación el usuario vería un
  -- error crudo de Postgres en vez de una frase en español.
  if v_motivo is null or length(v_motivo) < 3 then
    raise exception 'Anular una liquidación exige un motivo escrito: qué se marcó por error y cómo se sabe. Sin eso, dentro de un año la fila en cero no se puede leer.';
  end if;

  -- `congelada_por` es NOT NULL con FK a personas. Pegado en el SQL Editor sin
  -- sesión esto reventaría con un NOT NULL a secas, y el error no diría qué
  -- falta. Se dice acá.
  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No hay sesión: la anulación tiene que quedar firmada. Desde el SQL Editor, ejecuta antes select set_config(''request.jwt.claim.sub'', ''TU-AUTH-USER-ID'', true);';
  end if;

  select * into v_f from liquidacion_pagada
   where persona_id = p_persona_id
   order by version desc limit 1;

  if not found then
    raise exception 'Esa persona no tiene ninguna liquidación registrada como pagada: no hay nada que anular.';
  end if;

  -- ANULAR DOS VECES NO ESCRIBE DOS VECES. La PK es (persona_id, version) y la
  -- versión sale de max+1, así que sin esta salida la segunda llamada insertaría
  -- una v4 en cero anulando una v3 que ya estaba en cero: ruido que un año
  -- después se lee como si hubiera pasado algo dos veces. No es un error, así
  -- que no se levanta excepción: se devuelve lo que ya había.
  if v_f.anulada is true then
    return jsonb_build_object(
      'ya_estaba_anulada', true,
      'version',           v_f.version,
      'anula_version',     v_f.anula_version,
      'motivo',            v_f.motivo_anulacion,
      'anulada_el',        (v_f.congelada_at at time zone 'America/Lima')::date
    );
  end if;

  -- `v_f.version + 1` y no `max(version) + 1`: v_f ES la última versión, que es
  -- lo que acaba de leer el select de arriba. Pedir el max otra vez sería la
  -- misma cuenta hecha dos veces.
  v_ver := v_f.version + 1;

  -- LOS DATOS DE QUIÉN Y CUÁNDO SE COPIAN DE LA VERSIÓN ANULADA, NO SE
  -- RECALCULAN. Llamar a `fn_liquidacion` para rellenarlos abortaría con «esa
  -- persona no tiene fecha de cese» si fue reactivada —el CHECK
  -- `personas_cese_coherente` le vacía `fecha_cese` al volver a activo—, y
  -- entonces no se podría anular justamente a quien más falta hace. Es el mismo
  -- motivo del coalesce que la 0167 documenta en fn_liquidacion_diferencias.
  insert into liquidacion_pagada (
    persona_id, version, congelada_por, nota,
    persona, fecha_ingreso, fecha_cese,
    monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle,
    anulada, motivo_anulacion, anula_version
  ) values (
    p_persona_id, v_ver, v_yo,
    'ANULACIÓN de la versión ' || v_f.version,
    v_f.persona, v_f.fecha_ingreso, v_f.fecha_cese,
    0, 0, 0, 0, 0,
    -- `detalle` es NOT NULL y su promesa en la 0167 es poder REIMPRIMIR la hoja
    -- tal como se entregó. De una anulación no hay hoja que reimprimir, así que
    -- lo que se guarda es la explicación: qué se anuló y qué decía. Con esto la
    -- fila se cuenta sola, sin cruzarla con la anterior.
    jsonb_build_object(
      'anulada',       true,
      'anula_version', v_f.version,
      'motivo',        v_motivo,
      'anulada_at',    now(),
      'que_significa', 'Esta versión no es un pago de S/0.00: es la anulación de una liquidación que se marcó como pagada por error. La versión anulada sigue guardada, con su detalle intacto.',
      'lo_que_decia_la_version_anulada', jsonb_build_object(
        'total',            v_f.total,
        'monto_periodo',    v_f.monto_periodo,
        'monto_vacaciones', v_f.monto_vacaciones,
        'monto_grati',      v_f.monto_grati,
        'monto_cts',        v_f.monto_cts,
        'congelada_at',     v_f.congelada_at,
        'congelada_por',    v_f.congelada_por,
        'nota',             v_f.nota,
        'detalle',          v_f.detalle
      )
    ),
    true, v_motivo, v_f.version
  );

  -- El rastro, igual que hace fn_liquidacion_pagar (0167:157-163). Con una
  -- diferencia: acá `valor_anterior` SÍ se llena. La fila de auditoría de una
  -- anulación tiene que decir sola de cuánto a cuánto, sin ir a buscar nada.
  -- La máscara es `FM999999990.00` y no `FM999999.00`: sin el cero delante,
  -- `to_char(0, 'FM999999.00')` devuelve «.00» — medido.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'liquidacion_pagada',
     'S/' || to_char(v_f.total, 'FM999999990.00') || ' · version ' || v_f.version,
     'ANULADA · S/0.00 · version ' || v_ver,
     v_yo, v_motivo);

  return jsonb_build_object(
    'anulada',       true,
    'version',       v_ver,
    'anula_version', v_f.version,
    'total_anulado', v_f.total,
    'motivo',        v_motivo
  );
end;
$fn$;

comment on function fn_liquidacion_anular(uuid, text) is
  'Anula una liquidación marcada como pagada por error: escribe una versión más '
  'en cero, con motivo obligatorio, y deja la anterior visible. No borra nada. '
  'Ver 0251.';

revoke execute on function fn_liquidacion_anular(uuid, text) from public, anon;
grant  execute on function fn_liquidacion_anular(uuid, text) to authenticated;


-- ── 4 · La comparación deja de comparar contra una anulación ────────────────
-- Copiada de la 0167 —la única definición que existe, comprobado con
-- ./scripts/donde-vive.sh— con UN cambio, marcado abajo. Sin él, abrir el
-- desglose de una liquidación anulada pinta el recuadro rojo diciendo «se pagó
-- S/0.00, hoy daría S/298.73» en las cinco líneas: cinco diferencias contra una
-- cifra que nunca se pagó, al lado de una fila que ya dice que no está pagada.
create or replace function fn_liquidacion_diferencias(p_persona_id uuid)
returns table (
  concepto  text,
  pagado    numeric,
  ahora     numeric,
  diferencia numeric
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_f       liquidacion_pagada%rowtype;
  v_l       jsonb;
  v_cese_hoy date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede comparar una liquidación.';
  end if;

  select * into v_f from liquidacion_pagada
   where persona_id = p_persona_id
   order by version desc limit 1;
  if not found then return; end if;   -- sin foto no hay nada que comparar

  -- ── CAMBIO 0251 ──────────────────────────────────────────────────────────
  -- Y con la última versión anulada tampoco: no hay cifra pagada contra la que
  -- descuadrar. Esto además apaga solo el badge «el cálculo ya no coincide» de
  -- fn_liquidaciones_pendientes, que se construye con un `exists` sobre esta
  -- función.
  if v_f.anulada is true then return; end if;
  -- ── fin CAMBIO 0251 ──────────────────────────────────────────────────────

  -- SE RECALCULA CON LA FECHA DE CESE DE HOY, NO CON LA CONGELADA. El motivo
  -- largo está en la 0167 y no se repite acá: el caso más frecuente por el que
  -- una liquidación deja de cuadrar es que alguien corrija el último día
  -- trabajado, y comparar con la fecha congelada era ciego justo a ese.
  --
  -- El `coalesce` es para quien fue reactivada: al volver a activo el esquema le
  -- exige `fecha_cese` en null (constraint `personas_cese_coherente`), y sin este
  -- respaldo `fn_liquidacion` abortaría y dejaría la lista de pendientes sin
  -- cargar entera por una sola persona.
  select p.fecha_cese into v_cese_hoy from personas p where p.id = p_persona_id;
  v_l := fn_liquidacion(p_persona_id, coalesce(v_cese_hoy, v_f.fecha_cese));

  -- La diferencia se calcula acá y no en la pantalla: es la cifra que alguien va
  -- a mirar para decidir si paga un ajuste, y no debería depender de una resta
  -- hecha en el navegador.
  return query
  select t.concepto, t.pagado, t.ahora, round(t.ahora - t.pagado, 2)
  from (values
    ('Sueldo del periodo', v_f.monto_periodo,    coalesce((v_l->'periodo'->>'monto')::numeric, 0)),
    ('Vacaciones truncas', v_f.monto_vacaciones, coalesce((v_l->'vacaciones_truncas'->>'monto')::numeric, 0)),
    ('Gratificación trunca', v_f.monto_grati,    coalesce((v_l->'gratificacion_trunca'->>'monto')::numeric, 0)),
    ('CTS trunca',         v_f.monto_cts,        coalesce((v_l->'cts_trunca'->>'monto')::numeric, 0)),
    ('TOTAL',              v_f.total,            coalesce((v_l->>'total')::numeric, 0))
  ) as t(concepto, pagado, ahora)
  where round(t.pagado, 2) <> round(t.ahora, 2);
end;
$fn$;

grant execute on function fn_liquidacion_diferencias(uuid) to authenticated;


-- ── 5 · La lista de pendientes vuelve a ver a quien no cobró ────────────────
-- Copiada de la 0167 —su única definición vigente— con UN cambio: el `on` del
-- lateral. No hace falta más, y ese es el punto.
--
-- El lateral sigue tomando la ÚLTIMA versión (si no, una anulación quedaría
-- tapada por la v1 que anula y no serviría de nada); lo que cambia es que si esa
-- última versión está anulada, el join no la casa y `f` viene en nulos. Con eso
-- las CUATRO expresiones de abajo que preguntan `f.persona_id is not null`
-- vuelven a ser ciertas sin tocarlas: `vencido`, `total`, `pagada` y `descuadra`.
-- Escribir la condición en las cuatro habría sido decir cuatro veces lo mismo —el
-- defecto que la 0192 vino a corregir en otra función.
--
-- Y `total` importa especialmente: `coalesce(f.total, …)` se queda con el 0.00 de
-- la anulación porque un cero no es un nulo, así que sin este cambio la pantalla
-- mostraría S/0.00 justo donde tiene que decir lo que aún se le debe.
--
-- No hace falta `drop function`: el tipo de retorno no cambia ni una columna, así
-- que `create or replace` basta.
create or replace function fn_liquidaciones_pendientes()
returns table (
  persona_id     uuid,
  persona        text,
  sede           text,
  fecha_ingreso  date,
  fecha_cese     date,
  vence_el       date,
  dias_restantes int,
  vencido        boolean,
  total          numeric,
  pagada         boolean,
  descuadra      boolean
)
language sql
stable
security definer
set search_path = public
as $fn$
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_ingreso,
    p.fecha_cese,
    (p.fecha_cese + 2),
    (p.fecha_cese + 2 - fn_hoy_lima())::int,
    (fn_hoy_lima() > p.fecha_cese + 2 and f.persona_id is null),
    round(coalesce(f.total, (fn_liquidacion(p.id, p.fecha_cese)->>'total')::numeric, 0), 2),
    (f.persona_id is not null),
    (f.persona_id is not null
      and exists (select 1 from fn_liquidacion_diferencias(p.id)))
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select lp.* from liquidacion_pagada lp
    where lp.persona_id = p.id order by lp.version desc limit 1
  ) f on f.anulada is not true            -- CAMBIO 0251
  where p.estado = 'inactivo'
    and p.fecha_cese is not null
    and fn_es_admin_o_lider() is true
  order by (f.persona_id is not null), p.fecha_cese desc;
$fn$;

grant execute on function fn_liquidaciones_pendientes() to authenticated;


-- ── 6 · Y la pantalla de Planilla deja de anunciar un cobro que no hubo ─────
-- Copiada de la 0210 —su única definición— con UN cambio: el filtro por
-- `anulada` va DESPUÉS del `distinct on`, no dentro.
--
-- Ponerlo en el `where` de adentro sería el error silencioso de esta migración:
-- el `distinct on` se resuelve después del `where`, así que filtrar ahí haría que
-- se eligiera la última versión NO anulada —o sea, exactamente la v1 errónea que
-- la anulación viene a apagar— y el cartel seguiría diciendo S/1,106.82. Medido.
--
-- Se EXCLUYE a la persona del objeto en vez de devolverla en ceros porque la
-- pantalla decide con `if (!liq) return null` (planilla/page.tsx:478): devolver
-- ceros dejaría el cartel pintado, solo que con otro número falso.
create or replace function fn_liquidaciones_del_periodo(p_periodo_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    jsonb_object_agg(
      x.persona_id::text,
      jsonb_build_object(
        -- Lo que esa liquidación ya pagó POR ESTE MES. Es la cifra que se
        -- solapa con la planilla; el resto de la liquidación son truncas.
        'cobro_del_periodo', x.monto_periodo,
        'total_liquidacion', x.total,
        'pagada_el',         (x.congelada_at at time zone 'America/Lima')::date,
        'fecha_cese',        x.fecha_cese
      )
    ),
    '{}'::jsonb
  )
  from (
    select u.*
    from (
      -- Una liquidación puede tener varias versiones; manda la última, igual que
      -- en la pantalla de Liquidaciones.
      select distinct on (lp.persona_id)
             lp.persona_id, lp.monto_periodo, lp.total, lp.congelada_at,
             lp.fecha_cese, lp.anulada
      from liquidacion_pagada lp
      join periodos_planilla per on per.id = p_periodo_id
      where lp.fecha_cese between per.fecha_ini and per.fecha_fin
      order by lp.persona_id, lp.version desc
    ) u
    where u.anulada is not true          -- CAMBIO 0251 · después del distinct on
  ) x
  -- `is true` y no `not (...)`: un null no pasa como autorizado. Estándar del
  -- repo desde la 0078.
  where fn_es_admin_o_lider() is true;
$fn$;

comment on function fn_liquidaciones_del_periodo(uuid) is
  'Quién de este periodo ya cobró su liquidación, con cuándo y cuánto. Solo lee; '
  'la pantalla de Planilla lo usa para avisar antes de cerrar el mes. No cuenta '
  'las anuladas (0251). Ver 0210.';

revoke execute on function fn_liquidaciones_del_periodo(uuid) from public, anon;
grant  execute on function fn_liquidaciones_del_periodo(uuid) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (251, 'una_liquidacion_marcada_por_error_se_puede_anular')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── Comprobación posterior ──────────────────────────────────────────────────
-- Que la migración diga en voz alta que quedó como prometió. Se pega a mano, y
-- una mano se equivoca.
do $mig$
declare
  v_n_total   int;
  v_n_anul    int;
  v_falta     text;
begin
  -- Las tres columnas.
  select string_agg(c, ', ') into v_falta
  from unnest(array['anulada', 'motivo_anulacion', 'anula_version']) c
  where not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'liquidacion_pagada'
      and column_name = c
  );
  if v_falta is not null then
    raise exception '0251 · faltan columnas en liquidacion_pagada: %', v_falta;
  end if;

  -- Los dos CHECK. Son la razón de que la 0244 no se toque: sin ellos, una fila
  -- anulada con montos podría volver a activar el freno del cierre.
  select string_agg(c, ', ') into v_falta
  from unnest(array['liquidacion_anulada_en_cero', 'liquidacion_anulada_se_explica']) c
  where not exists (
    select 1 from pg_constraint
    where conrelid = 'liquidacion_pagada'::regclass and conname = c
  );
  if v_falta is not null then
    raise exception '0251 · faltan constraints: %', v_falta;
  end if;

  -- Las cuatro funciones.
  select string_agg(c, ', ') into v_falta
  from unnest(array['fn_liquidacion_anular', 'fn_liquidacion_diferencias',
                    'fn_liquidaciones_pendientes', 'fn_liquidaciones_del_periodo']) c
  where not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = c
  );
  if v_falta is not null then
    raise exception '0251 · faltan funciones: %', v_falta;
  end if;

  -- Quién puede llamarla. Devuelve y mueve el registro de un pago: no es de
  -- cualquiera, y el día que alguien conceda en masa —ya pasó, 0076— esto avisa.
  if has_function_privilege('anon', 'fn_liquidacion_anular(uuid, text)', 'execute') then
    raise exception '0251 · anon puede anular liquidaciones, y no debe.';
  end if;
  if not has_function_privilege('authenticated', 'fn_liquidacion_anular(uuid, text)', 'execute') then
    raise exception '0251 · authenticated NO puede anular, y la pantalla lo necesitará.';
  end if;

  -- Y que esta migración no haya marcado nada sola. No anula ninguna liquidación:
  -- eso es una llamada aparte, con nombre y motivo.
  select count(*), count(*) filter (where anulada) into v_n_total, v_n_anul
  from liquidacion_pagada;
  if v_n_anul > 0 then
    raise notice '0251 · OJO: ya hay % anulacion(es) registrada(s) de % filas. Si acabas de pegar esto por primera vez, deberia decir 0.', v_n_anul, v_n_total;
  else
    raise notice '0251 · listo. % liquidaciones registradas, 0 anuladas: esta migracion no anula nada sola.', v_n_total;
  end if;
  raise notice '0251 · para anular una, mira el bloque COMO SE USA de la cabecera. Y antes, la lista de scripts/sql-manual/liquidaciones_registradas_contra_el_banco.sql';
end
$mig$;
