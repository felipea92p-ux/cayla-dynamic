-- ============================================================================
-- 0571 · CADA PARÁMETRO DICE QUIÉN LO PUEDE CAMBIAR
-- ============================================================================
--
-- QUÉ PROMETE
--   1. `parametros_catalogo` gana `roles_cambia`: la lista de roles que pueden
--      cambiar ESE parámetro. Hasta hoy lo decidía la CLASE (operativo y plata:
--      DO; normativo: la dirección) y estaba escrito en dos sitios, en
--      `puedeCambiarParametro` y en `fn_parametro_cambiar`. Ahora manda la fila.
--   2. `fn_parametro_cambiar` lee esa columna. Un rol que no está en la lista no
--      cambia el parámetro, aunque entre a la pantalla.
--   3. `fn_parametros_listar` entrega `roles_cambia` y `puede_cambiar` (si QUIEN
--      pregunta puede cambiarlo), para que la pantalla muestre quién puede y
--      dibuje el botón solo a quien le toca.
--   4. Un parámetro nuevo nace SOLO PARA LA DIRECCIÓN (`{admin}`). Abrirlo a DO
--      es un cambio de datos, no de código. Decidido con Felipe (2026-10-31): los
--      parámetros de pago, de momento, solo los cambia la dirección.
--
-- LO QUE NO CAMBIA (se midió)
--   Los cuatro parámetros que ya existen se comportan IGUAL: los operativos
--   siguen siendo de admin y líder de DO, el normativo de la dirección. La
--   migración rellena `roles_cambia` según su clase de hoy, y la prueba 444
--   (55 aserciones) sigue en verde.
--
-- LO QUE NO HACE (es la Entrega 1b)
--   No construye la clase «plata» completa: vigencia (desde cuándo rige) y vista
--   previa de a quién le cambia el pago. Esas dos exigen guardar el valor
--   versionado, que hoy `almacen` no permite (solo `configuracion`). Mientras no
--   estén, NO se crea ningún parámetro de plata editable.
--
-- QUÉ ASUME
--   · Los únicos roles que pueden cambiar parámetros son `admin` y `lider_do`:
--     son los que `fn_es_admin_o_lider()` deja entrar a la pantalla. El CHECK
--     rechaza cualquier otro nombre.
--   · La 0552 pegada (existen el catálogo y las dos funciones).
--
-- POR QUÉ ASÍ
--   · Un CHECK dice que lo normativo es solo de la dirección: la regla ya no
--     depende de que `fn_parametro_cambiar` se acuerde.
--   · `fn_parametros_listar` cambia de columnas, y Postgres no deja agregarlas
--     con `create or replace`: se hace `drop function` y `create function`, como
--     la 0161 con `fn_documentos_tablero`. Se vuelven a dar sus permisos.
--   · `fn_rol_actual() = any(...)` con `is not true`: un rol nulo no autoriza.
--
-- md5 DE PARTIDA (de LA VERSIÓN LOCAL, la 0552; falta contrastarlo con PRODUCCIÓN
-- antes de entregar, como pide CLAUDE.md):
--   fn_parametro_cambiar   prosrc 44ee2514fef1c1e4c085429ff176c5a2 (2901 car.)
--   fn_parametros_listar   prosrc c3ba9466a8008dc6002576dfaca3d91d (1091 car.)
--
-- CÓMO SE REVIERTE
--   Pegar de nuevo las dos funciones de la 0552 (`fn_parametros_listar` con
--   `drop function` antes) y `alter table parametros_catalogo drop column
--   roles_cambia`. No se pierde ningún dato de valores ni de historial.
-- ============================================================================

-- ── 0 · Guardia ───────────────────────────────────────────────────────────
do $guardia$
begin
  if to_regclass('public.parametros_catalogo') is null
     or to_regprocedure('public.fn_parametro_cambiar(text,numeric,text)') is null
     or to_regprocedure('public.fn_parametros_listar()') is null
     or to_regprocedure('public.fn_rol_actual()') is null then
    raise exception 'Falta la 0552 (catálogo de parámetros) o fn_rol_actual: esta migración no entra sin ellas.';
  end if;
end
$guardia$;

-- ── 1 · La columna ────────────────────────────────────────────────────────
-- Idempotente: pegarla de nuevo NO pisa los roles que ya se hayan cambiado.
alter table parametros_catalogo add column if not exists roles_cambia text[];

update parametros_catalogo
   set roles_cambia = case when clase = 'normativo' then array['admin']
                           else array['admin', 'lider_do'] end
 where roles_cambia is null;

alter table parametros_catalogo alter column roles_cambia set default array['admin'];
alter table parametros_catalogo alter column roles_cambia set not null;

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'parametros_catalogo_roles_validos') then
    alter table parametros_catalogo add constraint parametros_catalogo_roles_validos
      check (cardinality(roles_cambia) >= 1 and roles_cambia <@ array['admin', 'lider_do']);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'parametros_catalogo_normativo_solo_direccion') then
    alter table parametros_catalogo add constraint parametros_catalogo_normativo_solo_direccion
      check (clase <> 'normativo' or roles_cambia = array['admin']);
  end if;
end
$c$;

comment on column parametros_catalogo.roles_cambia is
  'Los roles que pueden cambiar este parámetro (admin, lider_do). Un parámetro nuevo nace {admin}. Lo normativo es siempre solo {admin}. 0571.';

-- ── 2 · La puerta lee la columna ──────────────────────────────────────────
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


comment on function fn_parametro_cambiar(text, numeric, text) is
  'Cambia un parámetro del catálogo. Entra admin o líder de DO, pero cada parámetro dice en roles_cambia quién puede cambiarlo; exige motivo y respeta los límites del catálogo; el historial lo escribe trg_parametros_guardar_cambio. 0552, 0571.';

revoke all on function fn_parametro_cambiar(text, numeric, text) from public, anon;
grant execute on function fn_parametro_cambiar(text, numeric, text) to authenticated;

-- ── 3 · La lista dice quién puede ─────────────────────────────────────────
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
  puede_cambiar      boolean
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
         h.cambiado_at, h.por, h.motivo, h.origen,
         c.roles_cambia,
         (c.editable and fn_rol_actual()::text = any(c.roles_cambia)) is true
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
  'El catálogo de parámetros con el valor de hoy, el último cambio, los roles que pueden cambiarlo y si QUIEN pregunta puede. Solo admin o líder de DO. 0552, 0571.';

revoke all on function fn_parametros_listar() from public, anon;
grant execute on function fn_parametros_listar() to authenticated;

-- ── Registro ──────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (571, 'cada_parametro_dice_quien_lo_cambia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ──────────────────────────────────────────────────────────
-- Debe dar: 4 · 0 · true · true · «571 · cada_parametro_dice_quien_lo_cambia»
select
  (select count(*) from parametros_catalogo)                                   as parametros_en_el_catalogo,
  (select count(*) from parametros_catalogo
    where clase = 'normativo' and roles_cambia <> array['admin'])               as normativos_abiertos_a_otros,
  (select prosrc ~ 'roles_cambia' from pg_proc
    where proname = 'fn_parametro_cambiar' and pronamespace = 'public'::regnamespace) as la_puerta_lee_la_columna,
  (select 'roles_cambia' = any(proargnames) from pg_proc
    where proname = 'fn_parametros_listar' and pronamespace = 'public'::regnamespace) as la_lista_entrega_roles,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 571) as registro;
