-- ============================================================================
-- 0552 · LOS PARÁMETROS TIENEN PUERTA, CATÁLOGO Y RASTRO
-- ============================================================================
--
-- QUÉ PROMETE (el contrato, en cinco líneas)
--   1. Un CATÁLOGO (`parametros_catalogo`) dice qué números del sistema se
--      pueden mirar y cambiar desde la pantalla «Parámetros»: nombre en
--      español, unidad, mínimo y máximo, y de qué CLASE es cada uno
--      (operativo · plata · normativo).
--   2. Cambiar uno pasa por UNA puerta, `fn_parametro_cambiar`, que exige
--      motivo, respeta el mínimo y el máximo del catálogo y deja una fila en
--      `parametros_historial`: valor anterior, valor nuevo, quién, cuándo y
--      por qué. Nada se borra: volver atrás es otro cambio con el valor viejo.
--   3. El mismo rastro se escribe cuando alguien cambia el valor A MANO en el
--      SQL Editor. Hoy eso no deja nada; el historial lo marca con origen
--      «base» y sin autor, para que se vea que el cambio no pasó por la pantalla.
--   4. Un UPDATE/DELETE directo desde el navegador (PostgREST) sobre una clave
--      con parámetros queda rechazado. Hasta hoy `configuracion` aceptaba
--      cualquier escritura de admin o líder de DO, sin rastro (Apariencia la
--      usa así y no se toca: no está en el catálogo).
--   5. «Cuántos días de prueba» deja de estar escrito en una función: vive en
--      `configuracion.prueba_dias` (valor de partida 3, el de hoy) y
--      `fn_prueba_dias_plazo()` lo lee. Todas las pantallas ya recibían ese
--      número como columna (`dias_plazo`, `prueba_plazo`), así que ninguna se
--      entera.
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-26)
--   «Un apartado de configuración para que nadie tenga que programar; solo DO y
--   superiores; con historial de quién, a qué hora y qué cambió; y que diga a
--   quién le afecta antes de confirmar.» Las tres respuestas que cerraron el
--   diseño: (a) el líder de DO opera lo operativo y lo de plata, y solo la
--   dirección (admin) toca lo normativo; (b) la escalera disciplinaria NO es
--   editable en esta entrega —es del RIT— y entra después atada a una versión
--   del RIT; (c) se construye por rebanadas: esta es la primera, con tres
--   parámetros operativos y uno normativo de solo lectura.
--
-- EL CENSO (medido leyendo el repo; no es exhaustivo)
--   Hoy los números que mandan viven en cuatro sitios, sin rastro de quién los
--   movió y sin pantalla (salvo Apariencia y Educación):
--     · `configuracion` (0007): clave + jsonb, sin autor, fecha ni vigencia.
--     · `parametros_laborales` (0116): versionada, con sustento, «se escribe por
--       migración»; guarda RMV, EsSalud, movilidad, asignación familiar,
--       bonificación extraordinaria y bono de cumpleaños. Rebanada 2.
--     · Constantes dentro de funciones: la prueba de 3 días (esta migración), la
--       escalera de tardanzas 3→2→1 y sus 12 meses (`fn_tardanza_escalon_al`),
--       los umbrales de faltas, los recargos 25 %/35 % y las 48 h. Las
--       disciplinarias son del RIT; las de recargos y jornada, de la ley.
--     · Constantes en TypeScript: las bandas de `rangos.ts` (6 rangos, y la RMV
--       obliga a mover cuatro sitios a la vez).
--   `descanso_medico_aviso_dias` guarda DOS números en una clave:
--   `avisar_desde` (15, operativo) y `umbral_essalud` (20, el tope del RIT
--   art. 31 f; ver 0254). Por eso el catálogo apunta a un campo (`ruta`) y no a
--   la clave entera: así se edita el primero y el segundo se muestra fijo.
--
-- QUÉ ASUME
--   · La 0536 pegada: existe `fn_prueba_dias_plazo()` y devuelve 3. Esta
--     migración se NIEGA a entrar si no (ver el bloque de guardia).
--   · `configuracion` conserva su forma (clave text, valor jsonb, descripcion).
--     El valor de un parámetro es SIEMPRE un número: escalar (`3`) o un campo
--     numérico dentro de un objeto (`{"avisar_desde": 15, …}`).
--   · Nadie más escribe las tres claves del catálogo con un rol distinto de
--     `postgres`. Medido en el repo: ningún código ni migración lo hace. La
--     consulta de «ANTES DE PEGAR» lo comprueba en PRODUCCIÓN, donde puede haber
--     funciones pegadas a mano fuera del repo.
--
-- POR QUÉ ASÍ
--   · EL CANDADO ES UN TRIGGER SOBRE `configuracion`, no un grant. Mismo molde de
--     `fn_bloquear_rol_directo` (0296), `fn_bloquear_sede_directa` (0342) y
--     `fn_bloquear_alertas_directo` (0550): `current_user <> 'postgres'`
--     distingue «lo hizo una función interna» de «lo hizo un cliente». Y es
--     por CLAVE DEL CATÁLOGO: una clave que no está en el catálogo se escribe
--     como siempre. Apariencia, Educación y la firma de la empresa no se tocan.
--   · EL TRIGGER NO ES `SECURITY DEFINER`, y no debe serlo: con definer
--     `current_user` valdría siempre `postgres` y no frenaría nada, sin dar
--     error. Por eso el catálogo es legible por cualquier sesión con login (no
--     tiene nada sensible: nombres y límites); un trigger de invocador tiene
--     que poder leerlo.
--   · EL HISTORIAL LO ESCRIBE EL TRIGGER Y NO LA FUNCIÓN. Así hay UN solo sitio
--     que registra, por cualquier camino: la pantalla (con su motivo y su autor,
--     que la función deja en dos variables de la transacción) o el SQL Editor
--     (sin autor, con origen «base»). Si lo escribiera la función, el camino
--     manual —el de la 0110: «se activan con dos UPDATE cuando Felipe
--     decida»— seguiría siendo un hueco.
--   · LOS LÍMITES VALEN POR CUALQUIER CAMINO. El mínimo, el máximo y «entero»
--     los exige el trigger, no solo la función. Un 30 en vez de 3 por un dedo
--     de más se rechaza también en el SQL Editor. El historial dice quién la
--     cagó después; el límite la evita antes.
--   · LA HORA DEL CAMBIO ES `clock_timestamp()`, no `now()`. Con `now()` dos cambios
--     de una misma transacción empatan al microsegundo y «el último cambio» lo
--     decidiría el orden de un uuid al azar: el empate sin desempatar que ya pasó
--     con `fn_contratos_tablero` (0386). En producción cada cambio es su propia
--     transacción y no se nota; en una prueba, que es una sola, sí.
--   · EL HISTORIAL NO SE EDITA NI SE BORRA, ni siquiera como `postgres`
--     (trigger propio). Volver atrás es un cambio nuevo.
--   · `parametros_historial.cambiado_por` apunta a `personas`, no a
--     `correcciones_auditoria`: esa tabla exige `persona_id not null` porque
--     habla de una persona, y un parámetro global no es de nadie.
--   · LA FUNCIÓN DEL CATÁLOGO NO TOCA LA PLANILLA. `fn_planilla_calcular` lee
--     `descanso_medico_aviso_dias` y `auto_cierre_horas` de `configuracion` con
--     la misma forma de siempre; esta migración solo les pone puerta. Por eso
--     no hay md5 de la planilla en esta migración.
--
-- LOS LÍMITES SON UNA PROPUESTA, NO UNA NORMA
--   Mínimos y máximos del catálogo (prueba 1–15 días, auto-cierre 1–12 h, aviso
--   de descanso médico 1–20 días) son topes para atajar errores de tecla, los
--   fijó quien escribió esto y los puede mover Felipe con una migración.
--
-- QUÉ NO HACE (cada cosa es la siguiente rebanada, no un olvido)
--   · No versiona nada por fecha: estos tres parámetros rigen desde que se
--     cambian. Los de plata necesitan vigencia (desde cuándo) y vista previa de
--     a quién le cambia; viven en `parametros_laborales` y llegan después.
--   · No hace editable la escalera disciplinaria ni ningún valor del RIT.
--   · No mueve ninguna provisión: viven en `configuracion` SIN fecha y
--     cambiarlas reescribiría el historial; antes necesitan vigencia, y eso
--     reescribe `fn_planilla_calcular` (con su protocolo de md5).
--   · No cambia lo que se paga hoy: los tres valores arrancan en los que ya
--     tenían (3 días · 3 h · 15 días).
--
-- ANTES DE PEGAR (tres consultas de SOLO LECTURA, en el SQL Editor de producción)
--   (1) La función que se reescribe. Debe dar 2645ded8d962eebe8104370a3d5ac219,
--       11 caracteres, 'i' (immutable) y false. El cuerpo no tiene saltos de
--       línea, así que ni el CRLF de Windows lo cambia. La guardia de abajo es
--       por contenido (sin espacios) y PARA ante cualquier otra versión:
--
--         select md5(prosrc), length(prosrc), provolatile, prosecdef
--           from pg_proc
--          where proname = 'fn_prueba_dias_plazo' and pronamespace = 'public'::regnamespace;
--
--   (2) Que nadie escriba esas claves con un rol distinto de postgres. Debe dar
--       SIN FILAS de funciones que no sean SECURITY DEFINER (las definer corren
--       como su dueño y el candado las deja pasar):
--
--         select proname, prosecdef from pg_proc
--          where pronamespace = 'public'::regnamespace
--            and prosrc ~* '(update|insert[[:space:]]+into|delete[[:space:]]+from)[[:space:]]+(public\.)?configuracion([^a-z_]|$)'
--            and prosrc ~* '(prueba_dias|auto_cierre_horas|descanso_medico_aviso_dias)'
--          order by 1;
--
--   (3) Los valores de partida en producción (deben ser 3 · 15 y 20):
--
--         select clave, valor from configuracion
--          where clave in ('prueba_dias','auto_cierre_horas','descanso_medico_aviso_dias');
--
--       `auto_cierre_horas` debe dar un entero entre 1 y 12 y
--       `descanso_medico_aviso_dias` un `avisar_desde` entre 1 y 20: el
--       trigger exige esos límites cuando alguien cambie el valor, y un valor
--       de producción fuera de rango se vería recién al cambiarlo.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_parametros_guardar_cambio on configuracion;
--   drop trigger if exists trg_parametros_historial_inmutable on parametros_historial;
--   drop function if exists fn_parametros_historial(text, integer);
--   drop function if exists fn_parametros_listar();
--   drop function if exists fn_parametro_cambiar(text, numeric, text);
--   drop function if exists fn_parametros_guardar_cambio();
--   drop function if exists fn_parametros_historial_inmutable();
--   drop function if exists fn_parametro_numero_en(jsonb, text[]);
--   drop table if exists parametros_historial;   -- pierde el rastro: copiarlo antes
--   drop table if exists parametros_catalogo;
--   -- y restaurar fn_prueba_dias_plazo() desde la 0536 (`select 3;`, immutable).
--   La fila `configuracion.prueba_dias` puede quedarse: nadie la lee.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final: 4 en el catálogo, el candado puesto y activo, la
--   función leyendo la tabla (3), el trigger sin SECURITY DEFINER y el registro
--   `551 · los_parametros_tienen_puerta_y_dejan_rastro`.
-- ============================================================================

-- ── 0 · Guardia ─────────────────────────────────────────────────────────────
-- Se niega a entrar sobre una base que no sea la que esta migración espera. La
-- comparación del cuerpo ignora los espacios y los saltos de línea; y acepta
-- también la versión ya reescrita (la que nombra `prueba_dias`: un marcador de
-- contenido y no de número, para que renumerar la migración no la desarme).
do $guardia$
declare
  v_src text;
begin
  if to_regclass('public.configuracion') is null
     or to_regclass('public.personas') is null
     or to_regclass('public.migraciones_aplicadas') is null
     or to_regprocedure('public.fn_es_admin_o_lider()') is null
     or to_regprocedure('public.fn_rol_actual()') is null
     or to_regprocedure('public.fn_persona_actual_id()') is null then
    raise exception 'Falta una pieza base (configuracion, personas, migraciones_aplicadas o las funciones de rol). Esta migración no se pega sobre una base incompleta.';
  end if;

  select prosrc into v_src
    from pg_proc
   where proname = 'fn_prueba_dias_plazo' and pronamespace = 'public'::regnamespace;

  if v_src is null then
    raise exception 'Falta la 0536: fn_prueba_dias_plazo() no existe. Pega primero la 0536 y vuelve a pegar esta.';
  end if;

  if v_src !~ 'prueba_dias' and regexp_replace(v_src, '\s', '', 'g') <> 'select3;' then
    raise exception 'fn_prueba_dias_plazo() de esta base no es la de la 0536 (la que devuelve 3): otra versión la cambió. NO se pega: reescribirla desde acá revertiría ese cambio. Mide con la consulta (1) de ANTES DE PEGAR.';
  end if;
end
$guardia$;

-- ── 1 · El catálogo ─────────────────────────────────────────────────────────
-- Qué se puede mirar y cambiar, con sus límites. La verdad de los VALORES sigue
-- viviendo donde ya vivía (`configuracion`); esto solo dice dónde, cómo se
-- llama y cuánto vale como mínimo y como máximo.
create table if not exists parametros_catalogo (
  parametro      text primary key check (parametro ~ '^[a-z][a-z0-9_]{2,59}$'),
  nombre         text not null check (btrim(nombre) <> ''),
  descripcion    text not null check (btrim(descripcion) <> ''),
  unidad         text not null check (btrim(unidad) <> ''),
  clase          text not null check (clase in ('operativo', 'plata', 'normativo')),
  tipo_valor     text not null check (tipo_valor in ('entero', 'decimal')),
  valor_min      numeric,
  valor_max      numeric,
  valor_defecto  numeric not null,
  -- Dónde vive el valor. Hoy solo `configuracion`; `parametros_laborales`
  -- (versionada) entra en la rebanada 2 ampliando este check.
  almacen        text not null default 'configuracion' check (almacen in ('configuracion')),
  almacen_clave  text not null check (btrim(almacen_clave) <> ''),
  -- null = el valor ES el número; {avisar_desde} = un campo dentro del jsonb.
  ruta           text[],
  -- false = se muestra pero lo fija una norma: ni la dirección lo cambia acá.
  editable       boolean not null default true,
  base           text,
  orden          integer not null default 100,
  check (valor_min is null or valor_max is null or valor_min <= valor_max),
  -- Un parámetro editable sin tope no se acepta: sin él no hay nada que ataje un 30 por 3.
  check (editable is false or (valor_min is not null and valor_max is not null)),
  check ((valor_min is null or valor_defecto >= valor_min) and (valor_max is null or valor_defecto <= valor_max)),
  check (tipo_valor = 'decimal' or valor_defecto = trunc(valor_defecto))
);

comment on table parametros_catalogo is
  'Los números del sistema que se pueden mirar (y, si editable, cambiar) desde /admin/parametros, con su unidad, sus límites y su clase. La verdad del valor vive en almacen/almacen_clave (hoy configuracion); esto lo nombra y lo acota. 0552.';
comment on column parametros_catalogo.clase is
  'operativo = decide DO; plata = mueve un pago, exige vigencia y vista previa (rebanada 2); normativo = ley o RIT, solo la dirección y solo si editable.';
comment on column parametros_catalogo.ruta is
  'null = el valor de la clave es el número; {campo} = un campo numérico dentro del jsonb de la clave.';

-- Una sola entrada por lugar donde vive el valor.
create unique index if not exists idx_parametros_catalogo_lugar
  on parametros_catalogo (almacen, almacen_clave, coalesce(ruta, '{}'::text[]));

alter table parametros_catalogo enable row level security;
revoke all on parametros_catalogo from public, anon, authenticated;
grant select on parametros_catalogo to authenticated;

drop policy if exists parametros_catalogo_lectura on parametros_catalogo;
create policy parametros_catalogo_lectura on parametros_catalogo
  for select to authenticated using (true);

-- ── 2 · El historial ────────────────────────────────────────────────────────
create table if not exists parametros_historial (
  id              uuid primary key default gen_random_uuid(),
  parametro       text not null references parametros_catalogo(parametro),
  valor_anterior  numeric not null,
  valor_nuevo     numeric not null,
  motivo          text not null check (length(btrim(motivo)) >= 3),
  -- Null = alguien escribió en la base sin pasar por la pantalla.
  cambiado_por    uuid references personas(id),
  origen          text not null check (origen in ('pantalla', 'base')),
  -- `clock_timestamp()` y no `now()`: la hora REAL de escritura. `now()` vale lo mismo en toda
  -- la transacción, y dos cambios en una misma transacción empatarían (la familia de falsos rojos
  -- que CLAUDE.md documenta). En producción cada cambio va en su propia transacción: no se nota.
  cambiado_at     timestamptz not null default clock_timestamp(),
  check (valor_anterior is distinct from valor_nuevo),
  check ((origen = 'pantalla') = (cambiado_por is not null))
);

comment on table parametros_historial is
  'Quién cambió qué parámetro, cuándo, de qué valor a cuál y por qué. Se escribe solo por trigger (trg_parametros_guardar_cambio) y no se edita ni se borra. origen = base: se cambió a mano en la base de datos, sin pasar por la pantalla. 0552.';

create index if not exists idx_parametros_historial_parametro
  on parametros_historial (parametro, cambiado_at desc, id desc);

-- Solo se lee por fn_parametros_historial (guardia de DO): ninguna política.
alter table parametros_historial enable row level security;
revoke all on parametros_historial from public, anon, authenticated;

create or replace function fn_parametros_historial_inmutable()
returns trigger
language plpgsql as $fn$
begin
  raise exception 'El historial de parámetros no se edita ni se borra: volver atrás es un cambio nuevo con el valor anterior.';
end;
$fn$;

drop trigger if exists trg_parametros_historial_inmutable on parametros_historial;
create trigger trg_parametros_historial_inmutable
  before update or delete on parametros_historial
  for each row execute function fn_parametros_historial_inmutable();

-- ── 3 · Leer un número dentro de un jsonb, sin romperse ─────────────────────
-- `null` si no está o no es un número (un valor tocado a mano no tumba el
-- trigger: se lee como «el de partida»).
create or replace function fn_parametro_numero_en(p_valor jsonb, p_ruta text[])
returns numeric
language sql
immutable
as $fn$
  select case when t ~ '^-?[0-9]+(\.[0-9]+)?$' then t::numeric end
    from (select case when p_ruta is null then p_valor #>> '{}' else p_valor #>> p_ruta end as t) x;
$fn$;

revoke all on function fn_parametro_numero_en(jsonb, text[]) from public, anon;
grant execute on function fn_parametro_numero_en(jsonb, text[]) to authenticated;

-- ── 4 · El candado y el rastro, sobre `configuracion` ───────────────────────
-- OJO: NO es `security definer` y no debe serlo (ver «POR QUÉ ASÍ»).
create or replace function fn_parametros_guardar_cambio()
returns trigger
language plpgsql as $fn$
declare
  v_clave  text := coalesce(new.clave, old.clave);
  v_actor  uuid;
  v_motivo text;
  c        record;
  v_ant    numeric;
  v_nue    numeric;
begin
  -- Una clave que ningún parámetro usa se escribe como siempre.
  if not exists (select 1 from parametros_catalogo where almacen_clave = v_clave) then
    return coalesce(new, old);
  end if;

  if current_user <> 'postgres' then
    raise exception 'Este valor se cambia desde Parámetros, no con una escritura directa a la tabla.';
  end if;

  -- Quién y por qué los deja fn_parametro_cambiar para esta transacción; si no
  -- hay nadie, alguien escribió a mano en la base.
  v_actor  := nullif(current_setting('cayla.parametro_actor', true), '')::uuid;
  v_motivo := nullif(btrim(coalesce(current_setting('cayla.parametro_motivo', true), '')), '');

  for c in
    select * from parametros_catalogo where almacen_clave = v_clave order by orden, parametro
  loop
    v_ant := coalesce(case when tg_op = 'INSERT' then null else fn_parametro_numero_en(old.valor, c.ruta) end, c.valor_defecto);
    v_nue := coalesce(case when tg_op = 'DELETE' then null else fn_parametro_numero_en(new.valor, c.ruta) end, c.valor_defecto);
    continue when v_ant = v_nue;

    -- Los límites valen por cualquier camino, también el SQL Editor.
    if c.tipo_valor = 'entero' and v_nue <> trunc(v_nue) then
      raise exception '«%» tiene que ser un número entero (llegó %).', c.nombre, v_nue;
    end if;
    if (c.valor_min is not null and v_nue < c.valor_min) or (c.valor_max is not null and v_nue > c.valor_max) then
      raise exception '«%» va de % a % % (llegó %).', c.nombre, c.valor_min, c.valor_max, c.unidad, v_nue;
    end if;

    insert into parametros_historial (parametro, valor_anterior, valor_nuevo, motivo, cambiado_por, origen)
    values (c.parametro, v_ant, v_nue,
            coalesce(v_motivo, 'Cambio hecho directamente en la base de datos, sin motivo escrito.'),
            v_actor,
            case when v_actor is null then 'base' else 'pantalla' end);
  end loop;

  return coalesce(new, old);
end;
$fn$;

drop trigger if exists trg_parametros_guardar_cambio on configuracion;
-- Se crea DESPUÉS de sembrar la fila de abajo: la siembra no es un cambio.

-- ── 5 · Los cuatro parámetros de la primera rebanada ────────────────────────
-- La fila de la prueba. `do nothing`: si ya existe (repegar, o un valor ya
-- elegido) no se pisa.
insert into configuracion (clave, valor, descripcion)
values ('prueba_dias', '3'::jsonb,
        'Días trabajados (con jornada cerrada) que cumple quien está de prueba antes de hacerle el contrato. 0552.')
on conflict (clave) do nothing;

insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto,
   almacen_clave, ruta, editable, base, orden)
values
  ('prueba_dias',
   'Días de prueba antes del contrato',
   'Días trabajados, con la jornada cerrada, que cumple quien está de prueba antes de que se le haga el contrato. Si pasa el plazo sin que nadie decida, DO recibe la alerta. Más días es más tiempo trabajando sin contrato firmado.',
   'días', 'operativo', 'entero', 1, 15, 3,
   'prueba_dias', null, true,
   'Decisión de CAYLA (2026-10-19, migración 0536)', 10),
  ('auto_cierre_horas',
   'Horas de espera antes del auto-cierre de una jornada',
   'Si alguien olvida marcar su salida, la jornada se cierra sola cuando pasan estas horas desde su hora de salida programada y queda pendiente de revisión.',
   'horas', 'operativo', 'entero', 1, 12, 3,
   'auto_cierre_horas', null, true,
   'Regla del plan original (migración 0007)', 20),
  ('descanso_medico_avisar_desde',
   'Días de descanso médico desde los que se avisa',
   'Desde cuántos días de descanso médico acumulados en el año se avisa a DO que la persona se acerca al tope que paga CAYLA. Solo avisa: no cambia ningún pago.',
   'días', 'operativo', 'entero', 1, 20, 15,
   'descanso_medico_aviso_dias', array['avisar_desde'], true,
   'Migración 0197', 30),
  ('descanso_medico_tope_essalud',
   'Días de descanso médico a cargo de CAYLA en el año',
   'Los primeros días de incapacidad de cada año calendario los paga CAYLA; del siguiente en adelante subsidia EsSalud. Mueve el pago, por eso solo se muestra: lo fija una norma.',
   'días', 'normativo', 'entero', 1, 365, 20,
   'descanso_medico_aviso_dias', array['umbral_essalud'], false,
   'RIT art. 31 f) (migración 0254)', 40)
on conflict (parametro) do update
   set nombre = excluded.nombre, descripcion = excluded.descripcion, unidad = excluded.unidad,
       clase = excluded.clase, tipo_valor = excluded.tipo_valor,
       valor_min = excluded.valor_min, valor_max = excluded.valor_max, valor_defecto = excluded.valor_defecto,
       almacen_clave = excluded.almacen_clave, ruta = excluded.ruta,
       editable = excluded.editable, base = excluded.base, orden = excluded.orden;

-- Ahora sí, el candado.
create trigger trg_parametros_guardar_cambio
  before insert or update or delete on configuracion
  for each row execute function fn_parametros_guardar_cambio();

comment on trigger trg_parametros_guardar_cambio on configuracion is
  'Para las claves que usa algún parámetro del catálogo: rechaza escrituras directas (current_user <> postgres), exige mínimo, máximo y entero por cualquier camino y escribe parametros_historial. Las demás claves pasan sin tocarse. 0552.';

-- ── 6 · La puerta ───────────────────────────────────────────────────────────
create or replace function fn_parametro_cambiar(p_parametro text, p_valor numeric, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  c         parametros_catalogo%rowtype;
  v_quien   uuid;
  v_motivo  text := btrim(coalesce(p_motivo, ''));
  v_actual  numeric;
  v_json    jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo la dirección o Desarrollo Organizacional puede cambiar parámetros.';
  end if;

  select * into c from parametros_catalogo where parametro = p_parametro;
  if not found then
    raise exception 'No existe el parámetro «%».', p_parametro;
  end if;

  if c.editable is not true then
    raise exception '«%» lo fija una norma. Base: %. No se cambia desde Parámetros.', c.nombre, coalesce(c.base, 'sin base escrita');
  end if;

  -- Lo normativo es solo de la dirección. DO opera lo operativo y lo de plata.
  if c.clase = 'normativo' and fn_rol_actual() is distinct from 'admin' then
    raise exception 'Solo la dirección puede cambiar un parámetro normativo.';
  end if;

  if p_valor is null then
    raise exception 'Falta el valor nuevo.';
  end if;
  if length(v_motivo) < 3 then
    raise exception 'Escribe el motivo del cambio: es lo que explica el número dentro de un año.';
  end if;
  if c.tipo_valor = 'entero' and p_valor <> trunc(p_valor) then
    raise exception '«%» tiene que ser un número entero.', c.nombre;
  end if;
  if (c.valor_min is not null and p_valor < c.valor_min) or (c.valor_max is not null and p_valor > c.valor_max) then
    raise exception '«%» va de % a % %.', c.nombre, c.valor_min, c.valor_max, c.unidad;
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo dejarlo escrito. Inicia sesión con tu usuario.';
  end if;

  select coalesce(fn_parametro_numero_en(cfg.valor, c.ruta), c.valor_defecto)
    into v_actual
    from (select 1) x left join configuracion cfg on cfg.clave = c.almacen_clave;
  if v_actual = p_valor then
    return;  -- no cambia nada: tampoco se llena el historial de ruido
  end if;

  v_json := case when c.tipo_valor = 'entero' then to_jsonb(p_valor::integer) else to_jsonb(p_valor) end;

  -- Quién y por qué, para el trigger que escribe el historial. Solo esta transacción.
  perform set_config('cayla.parametro_actor', v_quien::text, true);
  perform set_config('cayla.parametro_motivo', v_motivo, true);

  update configuracion
     set valor = case when c.ruta is null then v_json else jsonb_set(valor, c.ruta, v_json, true) end
   where clave = c.almacen_clave;
  if not found then
    insert into configuracion (clave, valor, descripcion)
    values (c.almacen_clave,
            case when c.ruta is null then v_json else jsonb_set('{}'::jsonb, c.ruta, v_json, true) end,
            c.nombre);
  end if;

  -- Que lo que sigue en esta misma transacción no herede el autor.
  perform set_config('cayla.parametro_actor', '', true);
  perform set_config('cayla.parametro_motivo', '', true);
end;
$fn$;

comment on function fn_parametro_cambiar(text, numeric, text) is
  'Cambia un parámetro del catálogo. Solo admin o líder de DO (lo normativo, solo admin); exige motivo y respeta los límites del catálogo; el historial lo escribe trg_parametros_guardar_cambio. Si el valor no cambia, no hace nada. 0552.';

revoke all on function fn_parametro_cambiar(text, numeric, text) from public, anon;
grant execute on function fn_parametro_cambiar(text, numeric, text) to authenticated;

-- ── 7 · Leer: la lista con su valor de hoy y su último cambio ───────────────
create or replace function fn_parametros_listar()
returns table (
  parametro          text,
  nombre             text,
  descripcion        text,
  unidad             text,
  clase              text,
  tipo_valor         text,
  valor_min          numeric,
  valor_max          numeric,
  valor_defecto      numeric,
  editable           boolean,
  base               text,
  valor_actual       numeric,
  es_defecto         boolean,
  ultimo_cambio_at   timestamptz,
  ultimo_cambio_por  text,
  ultimo_motivo      text,
  ultimo_origen      text
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
#variable_conflict use_column
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo la dirección o Desarrollo Organizacional puede ver los parámetros.';
  end if;

  return query
  select c.parametro, c.nombre, c.descripcion, c.unidad, c.clase, c.tipo_valor,
         c.valor_min, c.valor_max, c.valor_defecto, c.editable, c.base,
         coalesce(v.n, c.valor_defecto),
         v.n is null,
         h.cambiado_at, h.por, h.motivo, h.origen
    from parametros_catalogo c
    left join configuracion cfg on cfg.clave = c.almacen_clave
    cross join lateral (select fn_parametro_numero_en(cfg.valor, c.ruta) as n) v
    left join lateral (
      select hh.cambiado_at, hh.motivo, hh.origen,
             nullif(btrim(coalesce(p.nombres, '') || ' ' || coalesce(p.apellidos, '')), '') as por
        from parametros_historial hh
        left join personas p on p.id = hh.cambiado_por
       where hh.parametro = c.parametro
       order by hh.cambiado_at desc, hh.id desc
       limit 1
    ) h on true
   order by (c.clase = 'normativo'), c.orden, c.parametro;
end;
$fn$;

comment on function fn_parametros_listar() is
  'El catálogo de parámetros con el valor de hoy y el último cambio de cada uno. Solo admin o líder de DO. 0552.';

revoke all on function fn_parametros_listar() from public, anon;
grant execute on function fn_parametros_listar() to authenticated;

-- ── 8 · Leer: el historial ──────────────────────────────────────────────────
create or replace function fn_parametros_historial(p_parametro text default null, p_limite integer default 50)
returns table (
  id              uuid,
  parametro       text,
  nombre          text,
  unidad          text,
  editable        boolean,
  valor_anterior  numeric,
  valor_nuevo     numeric,
  motivo          text,
  origen          text,
  cambiado_por    text,
  cambiado_at     timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
#variable_conflict use_column
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo la dirección o Desarrollo Organizacional puede ver el historial de parámetros.';
  end if;

  return query
  select h.id, h.parametro, c.nombre, c.unidad, c.editable,
         h.valor_anterior, h.valor_nuevo, h.motivo, h.origen,
         nullif(btrim(coalesce(p.nombres, '') || ' ' || coalesce(p.apellidos, '')), ''),
         h.cambiado_at
    from parametros_historial h
    join parametros_catalogo c on c.parametro = h.parametro
    left join personas p on p.id = h.cambiado_por
   where p_parametro is null or h.parametro = p_parametro
   order by h.cambiado_at desc, h.id desc
   limit least(greatest(coalesce(p_limite, 50), 1), 200);
end;
$fn$;

comment on function fn_parametros_historial(text, integer) is
  'Los últimos cambios de parámetros (todos, o los de uno), del más nuevo al más viejo. Solo admin o líder de DO. 0552.';

revoke all on function fn_parametros_historial(text, integer) from public, anon;
grant execute on function fn_parametros_historial(text, integer) to authenticated;

-- ── 9 · Los días de prueba se leen, ya no están clavados ────────────────────
-- Reescribe la de la 0536 (`select 3;`, immutable). `stable` y `security definer`
-- porque ahora lee una tabla; ninguna otra cosa cambia: mismo nombre, mismos
-- argumentos, mismo tipo. `create or replace` conserva los permisos.
create or replace function fn_prueba_dias_plazo()
returns integer
language sql
stable
security definer
set search_path = public
as $fn$
  -- CAMBIO 0552 · el 3 de siempre deja de estar clavado: sale de
  -- configuracion.prueba_dias (se cambia desde Parámetros). El 3 del final es el
  -- que tenía antes de esta migración y el que el catálogo dice como valor de
  -- partida; la prueba 444 comprueba que coincidan.
  select coalesce(
    (select fn_parametro_numero_en(c.valor, null)::integer from configuracion c where c.clave = 'prueba_dias'),
    3);
$fn$;

revoke execute on function fn_prueba_dias_plazo() from public, anon;
grant  execute on function fn_prueba_dias_plazo() to authenticated;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (552, 'los_parametros_tienen_puerta_y_dejan_rastro')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe dar: 4 · true · true · 3 · true · true · «551 · los_parametros_…»
select
  (select count(*) from parametros_catalogo)                                  as parametros_en_el_catalogo,
  (select count(*) = 1 from pg_trigger
    where tgname = 'trg_parametros_guardar_cambio'
      and tgrelid = 'configuracion'::regclass and tgenabled = 'O')            as el_candado_esta_puesto,
  (select not prosecdef from pg_proc
    where proname = 'fn_parametros_guardar_cambio'
      and pronamespace = 'public'::regnamespace)                              as el_candado_corre_con_quien_escribe,
  fn_prueba_dias_plazo()                                                      as dias_de_prueba_hoy,
  (select prosrc ~ 'configuracion' from pg_proc
    where proname = 'fn_prueba_dias_plazo'
      and pronamespace = 'public'::regnamespace)                              as la_funcion_lee_la_tabla,
  (select count(*) = 1 from configuracion where clave = 'prueba_dias')        as la_fila_existe,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 552) as registro;
