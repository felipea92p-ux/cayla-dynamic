-- ============================================================================
-- 0454 — Liquidaciones: fecha real de pago, y separar la diferencia del cierre
--        de una diferencia de verdad
-- ============================================================================
--
-- QUÉ PROMETE
--   Dos cosas de solo lectura y un dato nuevo, ninguna toca una fórmula:
--
--   1. `liquidacion_pagada` guarda además CUÁNDO salió el dinero de verdad
--      (`fecha_pago`), no solo cuándo alguien apretó el botón (`congelada_at`
--      ya existía y no cambia de sentido). Nace opcional: las filas de antes
--      de esta migración, y las anulaciones (que no son un pago), se quedan
--      en null — no se inventa una fecha que nadie registró.
--
--   2. `fn_liquidacion_diferencias` dice, por cada concepto que no coincide,
--      si la diferencia es la que YA EXPLICA el descuento que el cierre de
--      Planilla obliga a registrar (0244) —eso no es una avería, es el curso
--      normal de cesar antes de que cierre el mes— o si es una diferencia de
--      verdad. `fn_liquidaciones_pendientes` expone el resumen como
--      `descuadra_real`, sin tocar la columna `descuadra` que ya existe y que
--      las pruebas 133 y 194 comprueban tal cual.
--
-- QUÉ ASUME
--   La 0167: `liquidacion_pagada` versiona por persona y es inmutable por
--   trigger; todos sus lectores toman la ÚLTIMA versión.
--   La 0244: `fn_liquidacion` ya devuelve `periodo.ya_pagado_en_planilla` —el
--   importe exacto que el freno del cierre obligó a descontar— dentro de la
--   MISMA persona y el MISMO periodo que contiene su cese.
--   La 0255: `fn_liquidacion_pagar` es la única definición vigente, comprobada
--   con `./scripts/donde-vive.sh`.
--   La 0251: `fn_liquidacion_diferencias` y `fn_liquidaciones_pendientes` son
--   las únicas definiciones vigentes, comprobado igual.
--
-- ── POR QUÉ "ESPERADA POR EL CIERRE" Y NO SOLO "SUELDO DEL PERIODO" ─────────
--
--   La 0244 dejó escrito en su propia cabecera que, en cuanto el freno del
--   cierre obliga a registrar el descuento de una cesada normal, su cálculo de
--   hoy baja solo y ella sale marcada con «el cálculo ya no coincide» — y que
--   eso "pasa a ser el estado corriente de toda cesada, razón de más para
--   retocar ese texto". Nadie lo había retocado todavía.
--
--   El criterio no es "cambió el sueldo del periodo": es que la diferencia de
--   ESE concepto sea EXACTAMENTE la suma de los descuentos que hoy tiene
--   registrados esa persona en ese periodo (`periodo.detalle.descuentos`, el
--   mismo campo que ya usa el freno del cierre en la 0244). Medido contra el
--   Postgres local: `periodo.ya_pagado_en_planilla` NO sirve para esto, porque
--   `fn_planilla_calcular` ya neteaba los descuentos registrados dentro de su
--   propio `total` —sin mirar el rango de fechas que se le pasa—, así que
--   cuando el descuento cubre el periodo entero `v_devengado` llega a
--   `fn_liquidacion` ya en cero y `ya_pagado_en_planilla` se queda en 0.00 sin
--   que eso signifique que no hubo descuento.
--
--   Comparar contra la suma de descuentos SÍ es correcto en general: si nada
--   más cambió, «pagado − ahora» de "Sueldo del periodo" es exactamente esa
--   suma, sin importar si el descuento vino del freno del cierre o de otra
--   cosa (un adelanto real, por ejemplo). Si además cambió algo real —una
--   fecha de cese corregida, un feriado que entró después, un marcaje
--   corregido— la resta deja de coincidir con la suma de descuentos, y ahí sí
--   es una diferencia real. Las otras tres truncas (vacaciones, gratificación,
--   CTS) nunca las toca ningún descuento de planilla, así que una diferencia
--   ahí es SIEMPRE real.
--
-- ── POR QUÉ UNA COLUMNA NUEVA (`descuadra_real`) Y NO CAMBIAR `descuadra` ───
--
--   Porque `descuadra` ya es una promesa cumplida: las pruebas 133 y 194 la
--   comprueban con valores exactos, y `donde-vive.sh` la lista como parte del
--   contrato vigente de `fn_liquidaciones_pendientes`. Cambiar su significado
--   sería romper esas dos pruebas para arreglar un tercer problema. La
--   pantalla deja de usar `descuadra` para la alarma roja y pasa a usar
--   `descuadra_real`; `descuadra` se queda como está, por si algún día hace
--   falta "cualquier diferencia, sea cual sea la causa".
--
-- ── POR QUÉ `fecha_pago` ES NULLABLE Y NO TIENE DEFAULT ─────────────────────
--
--   Dos razones. Primero, las liquidaciones ya pagadas antes de esta migración
--   no tienen ese dato en ningún lado — un default de `congelada_at::date`
--   sería inventar una fecha con apariencia de dato real, cuando lo único
--   cierto es cuándo alguien apretó el botón, no cuándo salió el dinero.
--   Segundo, una anulación (0251) no es un pago: su fila se queda en null a
--   propósito, y por eso `fn_liquidacion_anular` no se toca en esta migración
--   — su lista de columnas ya no incluye `fecha_pago`, así que la deja en null
--   sin que haga falta cambiar una línea de esa función.
--
--   Lo que SÍ hace `fn_liquidacion_pagar`: si la pantalla no manda una fecha,
--   asume HOY — no dos comportamientos posibles (con fecha y sin ella), sino
--   uno solo con un valor por defecto, igual que ya hacía `congelada_at`. Y
--   valida lo mínimo indiscutible: ni antes del cese, ni en el futuro.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
--   · No cambia `fn_liquidacion` ni ninguna fórmula: `fn_liquidacion_pagar`
--     sigue congelando exactamente lo que esa función calcula, palabra por
--     palabra igual que en la 0255.
--   · No recalcula ni ajusta ninguna liquidación ya pagada. Las fotos de antes
--     de esta migración se quedan con `fecha_pago` en null para siempre: no
--     hay forma honesta de rellenarlo después.
--   · No decide qué hacer con una diferencia real. Eso lo sigue nombrando la
--     función, no lo resuelve — como ya decía la 0167.
--
-- ── IDEMPOTENTE ─────────────────────────────────────────────────────────────
--   `add column if not exists`, el CHECK guardado por `pg_constraint`, y
--   `create or replace` / `drop function if exists` + `create` en las
--   funciones. Se puede pegar dos veces.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   alter table liquidacion_pagada drop column if exists fecha_pago;
--   Y volver a pegar fn_liquidacion_pagar de la 0255, fn_liquidacion_diferencias
--   y fn_liquidaciones_pendientes de la 0251, tal como están hoy en el repo.
-- ============================================================================


-- ── 1 · La fecha real de pago ───────────────────────────────────────────────
alter table liquidacion_pagada
  add column if not exists fecha_pago date;

comment on column liquidacion_pagada.fecha_pago is
  'Cuándo salió el dinero de verdad, según quien lo registró — no cuándo se '
  'apretó el botón (eso ya lo dice congelada_at). Null en las filas de antes '
  'de la 0454 y en toda anulación (0251): una anulación no es un pago. Ver 0454.';

do $mig$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'liquidacion_pagada'::regclass
      and conname  = 'liquidacion_pago_no_antes_del_cese'
  ) then
    alter table liquidacion_pagada
      add constraint liquidacion_pago_no_antes_del_cese
      check (fecha_pago is null or fecha_pago >= fecha_cese);
  end if;
end
$mig$;


-- ── 2 · Marcar como pagada acepta la fecha real, y la valida ───────────────
-- Cuerpo de la 0255 —su única definición vigente— con la fecha nueva. El
-- guard, el cálculo, la foto y el motivo compuesto quedan palabra por palabra
-- iguales; lo único que cambia está marcado «CAMBIO 0454».
--
-- DROP obligatorio: se agrega un tercer parámetro, así que el nombre pasa a
-- identificar una función distinta para Postgres (uuid,text) → (uuid,text,date).
-- Sin el drop, la 2-argumentos vieja se queda viva al lado de la nueva —
-- exactamente el defecto de sobrecarga que la 0297/0299 dejó documentado— y
-- una llamada por nombre con argumentos con nombre («p_persona_id», «p_nota»)
-- deja de saber cuál de las dos usar.
drop function if exists fn_liquidacion_pagar(uuid, text);

create or replace function fn_liquidacion_pagar(
  p_persona_id uuid,
  p_nota text default null,
  p_fecha_pago date default null   -- CAMBIO 0454
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_l    jsonb;
  v_ver  int;
  v_nota text := nullif(trim(coalesce(p_nota, '')), '');
  v_fecha_pago date;   -- CAMBIO 0454
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder marca una liquidación como pagada.';
  end if;

  -- Se congela lo que la función calcula AHORA, no un número que venga de la
  -- pantalla: si el monto viajara desde el navegador, la foto podría guardar algo
  -- que el sistema nunca calculó — y sería indistinguible de un cálculo real.
  v_l := fn_liquidacion(p_persona_id, null);

  -- ── CAMBIO 0454 · la fecha real de pago, con su propia validación ────────
  -- Sin fecha, HOY — el mismo valor que hasta ahora se leía de `congelada_at`.
  -- Con fecha, ni antes del cese (no se puede pagar algo que aún no se debía)
  -- ni en el futuro (no se puede certificar un pago que no ha ocurrido).
  v_fecha_pago := coalesce(p_fecha_pago, fn_hoy_lima());
  if v_fecha_pago < (v_l->>'fecha_cese')::date then
    raise exception 'La fecha de pago (%) no puede ser anterior al cese (%).',
      to_char(v_fecha_pago, 'DD/MM/YYYY'), to_char((v_l->>'fecha_cese')::date, 'DD/MM/YYYY');
  end if;
  if v_fecha_pago > fn_hoy_lima() then
    raise exception 'La fecha de pago (%) no puede ser futura.', to_char(v_fecha_pago, 'DD/MM/YYYY');
  end if;
  -- ── fin CAMBIO 0454 ───────────────────────────────────────────────────────

  select coalesce(max(version), 0) + 1 into v_ver
  from liquidacion_pagada where persona_id = p_persona_id;

  insert into liquidacion_pagada (
    persona_id, version, congelada_por, nota, fecha_pago,
    persona, fecha_ingreso, fecha_cese,
    monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle
  ) values (
    p_persona_id, v_ver, fn_persona_actual_id(), v_nota, v_fecha_pago,
    v_l->>'persona',
    (v_l->>'fecha_ingreso')::date,
    (v_l->>'fecha_cese')::date,
    coalesce((v_l->'periodo'->>'monto')::numeric, 0),
    coalesce((v_l->'vacaciones_truncas'->>'monto')::numeric, 0),
    coalesce((v_l->'gratificacion_trunca'->>'monto')::numeric, 0),
    coalesce((v_l->'cts_trunca'->>'monto')::numeric, 0),
    (v_l->>'total')::numeric,
    v_l
  );

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'liquidacion_pagada', null,
     'S/' || to_char((v_l->>'total')::numeric, 'FM999999990.00') || ' · version ' || v_ver
          || ' · pagada el ' || to_char(v_fecha_pago, 'DD/MM/YYYY'),   -- CAMBIO 0454
     fn_persona_actual_id(),
     case
       when v_nota is null        then 'Liquidación marcada como pagada'
       when length(v_nota) >= 3   then v_nota
       else 'Liquidación marcada como pagada · nota: ' || v_nota
     end);

  return jsonb_build_object('version', v_ver, 'total', (v_l->>'total')::numeric, 'fecha_pago', v_fecha_pago);
end;
$fn$;

comment on function fn_liquidacion_pagar(uuid, text, date) is
  'Congela la liquidación de una persona cesada tal como se calcula ahora, con '
  'la fecha real de pago (hoy si no se indica otra). Ver 0255 y 0454.';

revoke execute on function fn_liquidacion_pagar(uuid, text, date) from public, anon;
grant  execute on function fn_liquidacion_pagar(uuid, text, date) to authenticated;


-- ── 3 · La diferencia dice si el cierre ya la explica ───────────────────────
-- Cuerpo de la 0251 —su única definición vigente— con una columna más y el
-- cálculo que la llena, marcados «CAMBIO 0454». La comparación en sí —qué
-- concepto cambió y en cuánto, contra la fecha de cese de HOY— queda igual.
--
-- DROP obligatorio: se agrega la columna `origen` al retorno, y `create or
-- replace` no puede cambiar el tipo de retorno de una función que ya existe.
drop function if exists fn_liquidacion_diferencias(uuid);

create or replace function fn_liquidacion_diferencias(p_persona_id uuid)
returns table (
  concepto   text,
  pagado     numeric,
  ahora      numeric,
  diferencia numeric,
  origen     text   -- CAMBIO 0454 · 'esperada_por_cierre' | 'real'
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
  v_ya_planilla numeric;   -- CAMBIO 0454
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede comparar una liquidación.';
  end if;

  select * into v_f from liquidacion_pagada
   where persona_id = p_persona_id
   order by version desc limit 1;
  if not found then return; end if;

  if v_f.anulada is true then return; end if;

  select p.fecha_cese into v_cese_hoy from personas p where p.id = p_persona_id;
  v_l := fn_liquidacion(p_persona_id, coalesce(v_cese_hoy, v_f.fecha_cese));

  -- ── CAMBIO 0454 ────────────────────────────────────────────────────────
  -- La suma de los descuentos que HOY tiene registrados esa persona en ese
  -- periodo — el mismo campo (`detalle.descuentos`) que ya usa el freno del
  -- cierre en la 0244 para decidir si deja cerrar el mes. No se usa
  -- `periodo.ya_pagado_en_planilla`: ese campo puede quedarse en 0.00 aunque
  -- el descuento exista, porque `fn_planilla_calcular` ya lo neteó dentro de
  -- su propio `total` antes de que `fn_liquidacion` reste nada — medido
  -- contra el Postgres local, ver la cabecera de esta migración.
  v_ya_planilla := coalesce((v_l->'periodo'->'detalle'->>'descuentos')::numeric, 0);
  -- ── fin CAMBIO 0454 ──────────────────────────────────────────────────────

  -- ── CAMBIO 0454 · TOTAL no se clasifica solo: hereda de sus conceptos ────
  -- Un `case` fila por fila clasificaría "TOTAL" como 'real' SIEMPRE —nunca es
  -- literalmente "Sueldo del periodo"—, aunque la única diferencia debajo sea
  -- la esperada. TOTAL es 'real' si CUALQUIERA de los cuatro conceptos que lo
  -- componen es real; si el único que difiere es "Sueldo del periodo" y esa
  -- diferencia coincide con los descuentos del periodo, TOTAL hereda
  -- 'esperada_por_cierre'.
  return query
  with conceptos as (
    select t.concepto, t.pagado, t.ahora, round(t.ahora - t.pagado, 2) as diferencia,
           case
             when t.concepto = 'Sueldo del periodo'
                  and round(t.ahora - t.pagado, 2) = round(-1 * v_ya_planilla, 2)
               then 'esperada_por_cierre'
             else 'real'
           end as origen
    from (values
      ('Sueldo del periodo', v_f.monto_periodo,    coalesce((v_l->'periodo'->>'monto')::numeric, 0)),
      ('Vacaciones truncas', v_f.monto_vacaciones, coalesce((v_l->'vacaciones_truncas'->>'monto')::numeric, 0)),
      ('Gratificación trunca', v_f.monto_grati,    coalesce((v_l->'gratificacion_trunca'->>'monto')::numeric, 0)),
      ('CTS trunca',         v_f.monto_cts,        coalesce((v_l->'cts_trunca'->>'monto')::numeric, 0))
    ) as t(concepto, pagado, ahora)
    where round(t.pagado, 2) <> round(t.ahora, 2)
  )
  select c.concepto, c.pagado, c.ahora, c.diferencia, c.origen from conceptos c
  union all
  select 'TOTAL', v_f.total, coalesce((v_l->>'total')::numeric, 0),
         round(coalesce((v_l->>'total')::numeric, 0) - v_f.total, 2),
         case when exists (select 1 from conceptos c2 where c2.origen = 'real')
              then 'real' else 'esperada_por_cierre' end
  where round(v_f.total, 2) <> round(coalesce((v_l->>'total')::numeric, 0), 2);
end;
$fn$;

comment on function fn_liquidacion_diferencias(uuid) is
  'Qué concepto de una liquidación pagada ya no coincide con el cálculo de '
  'hoy, y si esa diferencia es la que el cierre de Planilla ya explica '
  '(origen = esperada_por_cierre) o una diferencia de verdad (origen = real). '
  'Ver 0251 y 0454.';

grant execute on function fn_liquidacion_diferencias(uuid) to authenticated;


-- ── 4 · La lista de pendientes distingue una alarma real de una esperada ───
-- Cuerpo de la 0251 —su única definición vigente— con una columna más al
-- final. DROP obligatorio: cambia el número de columnas del retorno.
drop function if exists fn_liquidaciones_pendientes();

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
  descuadra      boolean,
  descuadra_real boolean   -- CAMBIO 0454
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
      and exists (select 1 from fn_liquidacion_diferencias(p.id))),
    (f.persona_id is not null                                                    -- CAMBIO 0454
      and exists (select 1 from fn_liquidacion_diferencias(p.id) d where d.origen = 'real'))
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select lp.* from liquidacion_pagada lp
    where lp.persona_id = p.id order by lp.version desc limit 1
  ) f on f.anulada is not true
  where p.estado = 'inactivo'
    and p.fecha_cese is not null
    and fn_es_admin_o_lider() is true
  order by (f.persona_id is not null), p.fecha_cese desc;
$fn$;

comment on function fn_liquidaciones_pendientes() is
  'Quién cesó y qué le falta cobrar. descuadra: cualquier diferencia contra lo '
  'pagado. descuadra_real: solo la que NO explica el cierre de Planilla — la '
  'que de verdad hay que revisar. Ver 0251 y 0454.';

grant execute on function fn_liquidaciones_pendientes() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (454, 'liquidaciones_fecha_de_pago_y_diferencia_por_cierre')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación posterior ──────────────────────────────────────────────────
do $mig$
declare v_falta text;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'liquidacion_pagada' and column_name = 'fecha_pago'
  ) then
    raise exception '0454 · falta la columna fecha_pago.';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'liquidacion_pagada'::regclass and conname = 'liquidacion_pago_no_antes_del_cese'
  ) then
    raise exception '0454 · falta el CHECK liquidacion_pago_no_antes_del_cese.';
  end if;

  select string_agg(c, ', ') into v_falta
  from unnest(array['fn_liquidacion_pagar', 'fn_liquidacion_diferencias', 'fn_liquidaciones_pendientes']) c
  where not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = c
  );
  if v_falta is not null then
    raise exception '0454 · faltan funciones: %', v_falta;
  end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_liquidacion_pagar'
      and pg_get_function_identity_arguments(p.oid) = 'p_persona_id uuid, p_nota text'
  ) then
    raise exception '0454 · quedó viva la versión de 2 argumentos de fn_liquidacion_pagar: la sobrecarga hará que una llamada por nombre no sepa cuál usar.';
  end if;

  if has_function_privilege('anon', 'fn_liquidacion_pagar(uuid, text, date)', 'execute') then
    raise exception '0454 · anon puede marcar liquidaciones como pagadas, y no debe.';
  end if;

  raise notice '0454 · listo. fecha_pago nace en null para lo ya pagado; desde ahora fn_liquidacion_pagar la exige (o asume hoy). descuadra_real distingue una diferencia real de la que ya explica el cierre de Planilla.';
end
$mig$;
