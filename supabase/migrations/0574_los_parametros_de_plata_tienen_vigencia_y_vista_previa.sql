-- ============================================================================
-- 0574 · LOS PARÁMETROS DE PLATA TIENEN VIGENCIA Y VISTA PREVIA
-- ============================================================================
--
-- NÚMERO: se escribió como 0572 y se renumeró a 0574 el 2026-10-31: la 0572 la
--   tomó «la invitación a la cuenta sale sola» (PR #627), fusionada antes. Nunca
--   se pegó con el número viejo.
--
-- QUÉ PROMETE (Entrega 1b)
--   1. Un parámetro de clase «plata» guarda su valor POR FECHAS
--      (`parametros_vigencias`: valor, desde cuándo, hasta cuándo) y no como un
--      número suelto en `configuracion`. `fn_parametro_valor_en(parametro, fecha)`
--      dice cuánto valía en esa fecha: es lo que leerá la planilla con la fecha
--      del periodo que calcula, para que cambiar un valor NO reescriba lo ya
--      pagado (lo que pasó con `tasa_afp`).
--   2. Se cambia por UNA puerta, `fn_parametro_cambiar_vigencia(parametro, valor,
--      desde, motivo)`: mismos límites, mismo motivo obligatorio y mismos roles
--      (`roles_cambia`, 0571) que `fn_parametro_cambiar`, MÁS una fecha. Se
--      NIEGA si algún periodo que termina en esa fecha o después ya está pagado
--      para el grupo al que toca el parámetro.
--   3. `fn_parametro_vista_previa(parametro, valor, desde)` dice A QUIÉN le
--      cambiaría algo antes de confirmar, con el mismo rechazo por periodo pagado.
--   4. Un parámetro de clase plata SOLO puede vivir en `vigencias` (CHECK): no se
--      puede crear uno de plata sin fecha. `fn_parametro_cambiar` se niega a
--      tocar uno que rige por fechas.
--   5. `fn_parametros_listar` entrega valor de hoy, desde cuándo rige, y el
--      próximo cambio programado.
--
-- LO QUE NO HACE
--   · NO crea ningún parámetro de plata: el primero llega con la Entrega 3. Esta
--     migración no mueve ni un sol y la planilla no lee nada de esto todavía.
--   · La vista previa dice QUIÉN está en el alcance del parámetro, no CUÁNTO
--     cambia su pago: el monto necesita la fórmula, que es la Entrega 3.
--
-- QUÉ ASUME
--   · La 0571 pegada (columna `roles_cambia`; `fn_parametro_cambiar` y
--     `fn_parametros_listar` con la forma de esa migración). Se NIEGA a entrar
--     sin ella. md5 de partida: el de la versión de la 0571 en este árbol; se
--     contrasta con PRODUCCIÓN ya con la 0571 pegada, antes de entregar.
--   · `btree_gist` instalada (ya la usan `periodos_planilla` y otras).
--
-- POR QUÉ ASÍ
--   · Versiones encadenadas: cambiar cierra la versión abierta el día anterior a
--     `desde` y abre la nueva. Un EXCLUDE impide dos versiones que se pisen. La
--     fecha del cambio tiene que ser POSTERIOR a la de la última versión: así no
--     se reescribe una anterior; deshacer es otro cambio con otra fecha.
--   · `parametros_vigencias` no se toca a mano: sin permisos para ningún cliente
--     y un trigger que rechaza borrar y editar todo salvo el cierre de
--     `vigente_hasta` (también desde el SQL Editor, a diferencia de la 0552: aquí
--     el rastro no se puede saltar).
--   · El historial (`parametros_historial`) lleva la fila de siempre, con el
--     motivo precedido de «Rige desde AAAA-MM-DD.»: así se ve en la pantalla de
--     historial que ya existe sin tocar `fn_parametros_historial`.
--   · El alcance (`alcance`) dice a quién toca el parámetro y de ahí salen el
--     grupo de pago a vigilar y la lista de la vista previa.
--
-- CÓMO SE REVIERTE
--   Sin parámetros de plata creados, no hay datos: `drop table parametros_vigencias`,
--   quitar `alcance` y volver el CHECK de `almacen` a `= 'configuracion'`, y pegar
--   de nuevo las dos funciones de la 0571 (`fn_parametros_listar` con `drop
--   function` antes) y las dos de la 0552 que no cambian.
-- ============================================================================

-- ── 0 · Guardia ───────────────────────────────────────────────────────────
do $guardia$
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'parametros_catalogo' and column_name = 'roles_cambia')
     or to_regprocedure('public.fn_parametro_cambiar(text,numeric,text)') is null
     or to_regprocedure('public.fn_parametros_listar()') is null then
    raise exception 'Falta la 0571 (roles por parámetro): esta migración no entra sin ella.';
  end if;
  if (select prosrc !~ 'roles_cambia' from pg_proc
       where proname = 'fn_parametro_cambiar' and pronamespace = 'public'::regnamespace) then
    raise exception 'fn_parametro_cambiar de esta base no es la de la 0571: reescribirla desde acá revertiría ese cambio. Mide su md5.';
  end if;
end
$guardia$;

-- ── 1 · El catálogo: dónde vive el valor y a quién toca ───────────────────
alter table parametros_catalogo drop constraint if exists parametros_catalogo_almacen_check;
alter table parametros_catalogo add constraint parametros_catalogo_almacen_check
  check (almacen in ('configuracion', 'vigencias'));

alter table parametros_catalogo add column if not exists alcance text;

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'parametros_catalogo_alcance_check') then
    alter table parametros_catalogo add constraint parametros_catalogo_alcance_check
      check (alcance is null or alcance in ('practicante_preprofesional', 'practicante_profesional', 'planilla', 'rxh'));
  end if;
  -- Plata solo con fechas, y lo que tiene fechas dice a quién toca.
  if not exists (select 1 from pg_constraint where conname = 'parametros_catalogo_plata_con_vigencia') then
    alter table parametros_catalogo add constraint parametros_catalogo_plata_con_vigencia
      check ((clase = 'plata') = (almacen = 'vigencias') and ((almacen = 'vigencias') = (alcance is not null)));
  end if;
end
$c$;

comment on column parametros_catalogo.alcance is
  'A quién toca un parámetro que rige por fechas: de ahí salen el grupo de pago que se vigila y la lista de la vista previa. Solo si almacen = vigencias. 0574.';

-- ── 2 · Las versiones ─────────────────────────────────────────────────────
create table if not exists parametros_vigencias (
  id             uuid primary key default gen_random_uuid(),
  parametro      text not null references parametros_catalogo(parametro),
  valor          numeric not null,
  vigente_desde  date not null,
  vigente_hasta  date,
  motivo         text not null check (length(btrim(motivo)) >= 3),
  creado_por     uuid not null references personas(id),
  creado_at      timestamptz not null default clock_timestamp(),
  check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  constraint parametros_vigencias_sin_solape
    exclude using gist (parametro with =, daterange(vigente_desde, vigente_hasta, '[]') with &&)
);

comment on table parametros_vigencias is
  'Las versiones de los parámetros de clase plata: qué valor rige desde qué fecha. Se escribe solo por fn_parametro_cambiar_vigencia; no se borra y solo se le cierra vigente_hasta. 0574.';

alter table parametros_vigencias enable row level security;
revoke all on parametros_vigencias from public, anon, authenticated;

create or replace function fn_parametros_vigencias_inmutable()
returns trigger
language plpgsql as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'Las versiones de un parámetro no se borran: volver atrás es un cambio nuevo con otra fecha.';
  end if;
  if new.id is distinct from old.id or new.parametro is distinct from old.parametro
     or new.valor is distinct from old.valor or new.vigente_desde is distinct from old.vigente_desde
     or new.motivo is distinct from old.motivo or new.creado_por is distinct from old.creado_por
     or new.creado_at is distinct from old.creado_at
     or old.vigente_hasta is not null then
    raise exception 'Una versión de un parámetro no se edita: solo se le cierra el vigente_hasta una vez.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_parametros_vigencias_inmutable on parametros_vigencias;
create trigger trg_parametros_vigencias_inmutable
  before update or delete on parametros_vigencias
  for each row execute function fn_parametros_vigencias_inmutable();

-- ── 3 · Cuánto valía en una fecha ─────────────────────────────────────────
-- Antes de la primera versión rige el valor de partida del catálogo.
create or replace function fn_parametro_valor_en(p_parametro text, p_fecha date)
returns numeric
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    (select v.valor
       from parametros_vigencias v
      where v.parametro = p_parametro
        and v.vigente_desde <= p_fecha
        and (v.vigente_hasta is null or v.vigente_hasta >= p_fecha)
      order by v.vigente_desde desc
      limit 1),
    (select c.valor_defecto from parametros_catalogo c where c.parametro = p_parametro));
$fn$;

comment on function fn_parametro_valor_en(text, date) is
  'Cuánto valía un parámetro que rige por fechas en esa fecha; antes de su primera versión, el valor de partida del catálogo. Es lo que debe leer la planilla con la fecha del periodo. 0574.';

revoke all on function fn_parametro_valor_en(text, date) from public, anon;
grant execute on function fn_parametro_valor_en(text, date) to authenticated;

-- ── 4 · ¿Hay un periodo ya pagado que ese cambio reescribiría? ─────────────
-- Devuelve el fin del primer periodo pagado (para el grupo del parámetro) que
-- termina en `p_desde` o después; null si no hay ninguno.
create or replace function fn_parametro_periodo_pagado_desde(p_alcance text, p_desde date)
returns date
language sql
stable
security definer
set search_path = public
as $fn$
  select min(pp.fecha_fin)
    from periodos_planilla pp
   where pp.fecha_fin >= p_desde
     and (pp.estado = 'pagado'
          or exists (select 1 from periodo_grupo_pago g
                      where g.periodo_id = pp.id and g.estado = 'pagado'
                        and g.grupo = case when p_alcance like 'practicante%' then 'practicante'
                                           when p_alcance = 'rxh' then 'rxh'
                                           else 'planilla' end));
$fn$;

revoke all on function fn_parametro_periodo_pagado_desde(text, date) from public, anon;
grant execute on function fn_parametro_periodo_pagado_desde(text, date) to authenticated;

-- ── 5 · La puerta de los que no tienen fecha, ahora se niega a los que sí ──
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
    raise exception 'Solo la dirección o Desarrollo Organizacional puede cambiar parámetros.';  -- la puerta de entrada no cambia: quién cambia CADA uno lo dice roles_cambia
  end if;

  select * into c from parametros_catalogo where parametro = p_parametro;
  if not found then
    raise exception 'No existe el parámetro «%».', p_parametro;
  end if;

  -- CAMBIO 0574 · un parámetro que rige por fechas (clase plata) NO se cambia por
  -- acá: esta puerta escribe en `configuracion` y un valor sin fecha reescribiría
  -- periodos ya pagados. Tiene su propia puerta, con fecha de vigencia.
  if c.almacen = 'vigencias' then
    raise exception '«%» rige por fechas: se cambia con su fecha de vigencia (fn_parametro_cambiar_vigencia), no con esta puerta.', c.nombre;
  end if;

  if c.editable is not true then
    raise exception '«%» lo fija una norma. Base: %. No se cambia desde Parámetros.', c.nombre, coalesce(c.base, 'sin base escrita');
  end if;

  -- CAMBIO 0571 · quién puede cambiarlo lo dice el CATÁLOGO, parámetro por
  -- parámetro (`roles_cambia`), y no la clase. `is not true` y no `not`: un rol
  -- nulo (nadie identificado) no puede pasar como autorizado. Lo normativo sigue
  -- siendo solo de la dirección, ahora también por un CHECK de la tabla.
  if fn_rol_actual()::text = any(c.roles_cambia) is not true then
    if c.clase = 'normativo' then
      raise exception 'Solo la dirección puede cambiar un parámetro normativo.';
    end if;
    raise exception 'Tu rol no puede cambiar «%». Pueden: %.', c.nombre, array_to_string(c.roles_cambia, ', ');
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

revoke all on function fn_parametro_cambiar(text, numeric, text) from public, anon;
grant execute on function fn_parametro_cambiar(text, numeric, text) to authenticated;

-- ── 6 · La puerta de los que tienen fecha ──────────────────────────────────
create or replace function fn_parametro_cambiar_vigencia(p_parametro text, p_valor numeric, p_desde date, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  c         parametros_catalogo%rowtype;
  v_quien   uuid;
  v_motivo  text := btrim(coalesce(p_motivo, ''));
  v_ultima  date;
  v_antes   numeric;
  v_pagado  date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo la dirección o Desarrollo Organizacional puede cambiar parámetros.';
  end if;

  select * into c from parametros_catalogo where parametro = p_parametro;
  if not found then
    raise exception 'No existe el parámetro «%».', p_parametro;
  end if;
  if c.almacen <> 'vigencias' then
    raise exception '«%» no rige por fechas: se cambia con fn_parametro_cambiar.', c.nombre;
  end if;
  if c.editable is not true then
    raise exception '«%» lo fija una norma. Base: %. No se cambia desde Parámetros.', c.nombre, coalesce(c.base, 'sin base escrita');
  end if;
  if fn_rol_actual()::text = any(c.roles_cambia) is not true then
    raise exception 'Tu rol no puede cambiar «%». Pueden: %.', c.nombre, array_to_string(c.roles_cambia, ', ');
  end if;

  if p_valor is null then
    raise exception 'Falta el valor nuevo.';
  end if;
  if p_desde is null then
    raise exception 'Falta la fecha desde la que rige el valor nuevo.';
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

  -- Un solo cambio a la vez por parámetro: dos pegadas simultáneas no se pisan.
  perform pg_advisory_xact_lock(hashtext('parametros_vigencias:' || p_parametro));

  v_pagado := fn_parametro_periodo_pagado_desde(c.alcance, p_desde);
  if v_pagado is not null then
    raise exception 'El periodo que termina el % ya está pagado para este grupo: un valor que rige desde el % reescribiría lo ya pagado. Elige una fecha dentro de un periodo sin pagar.', v_pagado, p_desde;
  end if;

  select max(vigente_desde) into v_ultima from parametros_vigencias where parametro = p_parametro;
  if v_ultima is not null and p_desde <= v_ultima then
    raise exception 'Ya hay una versión de «%» que rige desde el %. La fecha nueva tiene que ser posterior.', c.nombre, v_ultima;
  end if;

  v_antes := fn_parametro_valor_en(p_parametro, p_desde);
  if v_antes = p_valor then
    return;  -- no cambia nada: tampoco se llena el historial de ruido
  end if;

  update parametros_vigencias set vigente_hasta = p_desde - 1
   where parametro = p_parametro and vigente_hasta is null;

  insert into parametros_vigencias (parametro, valor, vigente_desde, motivo, creado_por)
  values (p_parametro, p_valor, p_desde, v_motivo, v_quien);

  insert into parametros_historial (parametro, valor_anterior, valor_nuevo, motivo, cambiado_por, origen)
  values (p_parametro, v_antes, p_valor, 'Rige desde ' || p_desde::text || '. ' || v_motivo, v_quien, 'pantalla');
end;
$fn$;

comment on function fn_parametro_cambiar_vigencia(text, numeric, date, text) is
  'Cambia un parámetro que rige por fechas (clase plata). Mismos límites, motivo y roles que fn_parametro_cambiar, más la fecha: se niega si un periodo ya pagado para su grupo terminaría en esa fecha o después, y la fecha tiene que ser posterior a la última versión. 0574.';

revoke all on function fn_parametro_cambiar_vigencia(text, numeric, date, text) from public, anon;
grant execute on function fn_parametro_cambiar_vigencia(text, numeric, date, text) to authenticated;

-- ── 7 · La vista previa: a quién le toca ──────────────────────────────────
-- Dice QUIÉN está en el alcance del parámetro, no cuánto cambia su pago: el
-- monto necesita la fórmula (Entrega 3). Se niega por periodo pagado igual que
-- la puerta, para que el aviso llegue ANTES de confirmar.
create or replace function fn_parametro_vista_previa(p_parametro text, p_valor numeric, p_desde date)
returns table (persona text, vinculo text, detalle text)
language plpgsql
stable
security definer
set search_path = public
as $fn$
#variable_conflict use_column
declare
  c        parametros_catalogo%rowtype;
  v_pagado date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo la dirección o Desarrollo Organizacional puede ver los parámetros.';
  end if;
  select * into c from parametros_catalogo where parametro = p_parametro;
  if not found or c.almacen <> 'vigencias' then
    raise exception 'No existe un parámetro con fechas llamado «%».', p_parametro;
  end if;
  if p_desde is null then
    raise exception 'Falta la fecha desde la que rige el valor nuevo.';
  end if;
  v_pagado := fn_parametro_periodo_pagado_desde(c.alcance, p_desde);
  if v_pagado is not null then
    raise exception 'El periodo que termina el % ya está pagado para este grupo: un valor que rige desde el % reescribiría lo ya pagado. Elige una fecha dentro de un periodo sin pagar.', v_pagado, p_desde;
  end if;

  return query
  select btrim(coalesce(p.apellidos, '') || ', ' || coalesce(p.nombres, '')),
         case when p.tipo_vinculo = 'practicante' then 'practicante ' || coalesce(p.practicante_modalidad, '(sin modalidad)')
              else p.tipo_vinculo end,
         'Pasa de ' || fn_parametro_valor_en(p_parametro, p_desde)::text || ' ' || c.unidad
           || ' a ' || p_valor::text || ' ' || c.unidad || ' desde el ' || p_desde::text
    from personas p
   where p.estado = 'activo' and coalesce(p.cuenta_de_servicio, false) = false
     and case c.alcance
           when 'practicante_preprofesional' then p.tipo_vinculo = 'practicante' and p.practicante_modalidad = 'preprofesional'
           when 'practicante_profesional'    then p.tipo_vinculo = 'practicante' and p.practicante_modalidad = 'profesional'
           when 'planilla'                   then p.tipo_vinculo = 'planilla'
           when 'rxh'                        then p.tipo_vinculo = 'rxh'
           else false end
   order by 1;
end;
$fn$;

comment on function fn_parametro_vista_previa(text, numeric, date) is
  'A quién le toca un cambio de un parámetro que rige por fechas, antes de confirmar. No calcula montos (eso es la fórmula, Entrega 3). 0574.';

revoke all on function fn_parametro_vista_previa(text, numeric, date) from public, anon;
grant execute on function fn_parametro_vista_previa(text, numeric, date) to authenticated;

-- ── 8 · La lista: valor de hoy, desde cuándo y el próximo cambio ───────────
drop function if exists fn_parametros_listar();
create function fn_parametros_listar()
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
  ultimo_origen      text,
  roles_cambia       text[],
  puede_cambiar      boolean,
  rige_por_fechas    boolean,
  vigente_desde      date,
  proximo_valor      numeric,
  proximo_desde      date
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
         coalesce(case when c.almacen = 'vigencias' then vg.valor else v.n end, c.valor_defecto),
         case when c.almacen = 'vigencias' then vg.valor is null else v.n is null end,
         h.cambiado_at, h.por, h.motivo, h.origen,
         c.roles_cambia,
         (c.editable and fn_rol_actual()::text = any(c.roles_cambia)) is true,
         c.almacen = 'vigencias',
         vg.vigente_desde,
         px.valor,
         px.vigente_desde
    from parametros_catalogo c
    left join configuracion cfg on cfg.clave = c.almacen_clave
    cross join lateral (select fn_parametro_numero_en(cfg.valor, c.ruta) as n) v
    left join lateral (
      select z.valor, z.vigente_desde
        from parametros_vigencias z
       where z.parametro = c.parametro and z.vigente_desde <= fn_hoy_lima()
         and (z.vigente_hasta is null or z.vigente_hasta >= fn_hoy_lima())
       order by z.vigente_desde desc limit 1
    ) vg on true
    left join lateral (
      select z.valor, z.vigente_desde
        from parametros_vigencias z
       where z.parametro = c.parametro and z.vigente_desde > fn_hoy_lima()
       order by z.vigente_desde limit 1
    ) px on true
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
  'El catálogo de parámetros con el valor de hoy, el último cambio, quién puede cambiarlo y, si rige por fechas, desde cuándo y cuál es el próximo cambio. Solo admin o líder de DO. 0552, 0571, 0574.';

revoke all on function fn_parametros_listar() from public, anon;
grant execute on function fn_parametros_listar() to authenticated;

-- ── Registro ──────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (574, 'los_parametros_de_plata_tienen_vigencia_y_vista_previa')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ──────────────────────────────────────────────────────────
-- Debe dar: 0 · true · true · true · true · true · «574 · los_parametros_de_plata_…»
select
  (select count(*) from parametros_vigencias)                                  as versiones_guardadas,
  (select count(*) = 0 from parametros_catalogo where clase = 'plata' and almacen <> 'vigencias') as plata_siempre_con_fechas,
  (select prosrc ~ 'vigencias' from pg_proc
    where proname = 'fn_parametro_cambiar' and pronamespace = 'public'::regnamespace) as la_puerta_vieja_las_rechaza,
  (to_regprocedure('public.fn_parametro_cambiar_vigencia(text,numeric,date,text)') is not null) as existe_la_puerta_nueva,
  (to_regprocedure('public.fn_parametro_vista_previa(text,numeric,date)') is not null) as existe_la_vista_previa,
  (select 'rige_por_fechas' = any(proargnames) from pg_proc
    where proname = 'fn_parametros_listar' and pronamespace = 'public'::regnamespace) as la_lista_dice_las_fechas,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 574) as registro;
