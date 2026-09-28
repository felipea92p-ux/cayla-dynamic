-- ============================================================================
-- 0490 — Una cuenta de servicio no es una persona
-- ============================================================================
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--
-- Que Dynamic pueda distinguir, en la misma tabla `personas`, a una
-- colaboradora de una CUENTA DE SERVICIO: las «estaciones» que el ERP de
-- tiendas (cayla-retail, ADR-0160 de ese repo) usa como terminal compartida de
-- cada tienda — «ESTACIÓN — Caja Lima (no es persona)», «ESTACIÓN — Almacén
-- Trujillo (no es persona)»…
--
--   1. `personas.cuenta_de_servicio` (boolean, default false).
--   2. `fn_set_cuenta_de_servicio`: la única puerta para cambiarla, con rastro
--      en `correcciones_auditoria`, y un trigger que rechaza el cambio directo
--      — el molde de `fn_set_rol` (0295/0296) y `fn_set_sede_base` (0342).
--   3. Marca las estaciones que ya existen en producción, por su nombre, UNA
--      sola vez (ver «Por qué por el nombre» abajo).
--   4. El roster del terminal de marcaje deja de ofrecerlas.
--
-- La 0491 saca a las cuentas de servicio de la planilla y de las listas que
-- se calculan en la base. Las pantallas las filtran con esta columna.
--
-- ── EL PROBLEMA, MEDIDO ─────────────────────────────────────────────────────
--
-- Retail vive en esta misma base y no copia la identidad: la lee de
-- `personas`. 57 llaves foráneas de retail apuntan a `personas(id)`
-- (`ventas.usuario_id`, `movimientos.usuario_id`…), así que una cuenta que
-- cobra una venta TIENE que ser una fila de `personas`, activa. Y activa la
-- necesita de verdad: `fn_rol_actual` (0374) y 67 comparaciones de retail
-- exigen `estado = 'activo'`. Marcarlas inactivas les cortaría el acceso a
-- las tiendas.
--
-- Pero para Dynamic una fila activa de `personas` es alguien a quien se le
-- paga. Medido contra el Postgres local el 2026-09-28, dentro de
-- `begin … rollback`, con una estación creada como la crea Equipo:
--
--   · nace con `en_planilla = true`, `tipo_vinculo = 'planilla'` y
--     `sueldo_base_legal = 1130` (los defaults de la tabla);
--   · `fn_planilla_calcular` le pone una fila con **S/ 101.70 de EsSalud**
--     (`essalud_es_piso = true`: el piso sobre la RMV). Seis estaciones son
--     S/ 610.20 al mes de un aporte por nadie, y seis «trabajadores» de más en
--     lo que se declara;
--   · el terminal de marcaje de su sede la ofrece para marcar;
--   · aparece en Datos personales como «sin ficha — falta todo», en Equipo,
--     en la población obligada del Reglamento, en los acuses de la política
--     salarial, en el tablero de contratos y en el de documentación.
--
-- ── POR QUÉ UNA COLUMNA Y NO OTRA COSA ──────────────────────────────────────
--
-- · No un estado nuevo (`estado = 'servicio'`): retail compara `estado` con
--   'activo' en 67 sitios y los rompería todos.
-- · No leer `retail.colaboradores.terminal`: la dependencia hoy va en un solo
--   sentido (retail → public), y esa columna no existe en las migraciones de
--   este repo ni en CI. Dynamic se quedaría preguntando por algo que no puede
--   construir.
-- · No detectarlas por el nombre en cada consulta: basta con que alguien
--   escriba «Estacion» sin tilde para que vuelvan a aparecer.
-- · No un rol nuevo en `rol_usuario`: 87 migraciones y los candados de retail
--   leen `rol`. Una columna aparte no rompe nada de lo que funciona — el mismo
--   criterio que usó retail para su `colaboradores.terminal`.
--
-- ── POR QUÉ LA PUERTA ES DESCONFIADA ────────────────────────────────────────
--
-- Marcar a alguien como cuenta de servicio lo SACA DE LA PLANILLA (0491). Si
-- se marca por error a una persona real, deja de cobrar sin que nada falle.
-- Es el peor error posible aquí, así que `fn_set_cuenta_de_servicio` se
-- niega a marcar a quien:
--
--   · tiene un marcaje o una jornada (una estación no marca asistencia);
--   · tiene una fila en `planilla_pagada_detalle` (ya se le pagó un mes);
--   · no tiene rol `integrante` (una cuenta compartida nunca administra — la
--     misma regla que retail escribió en su CHECK).
--
-- Desmarcar no tiene condiciones: devolver a alguien a la planilla nunca
-- esconde nada.
--
-- ── POR QUÉ POR EL NOMBRE, Y SOLO ESTA VEZ ──────────────────────────────────
--
-- Las seis estaciones de producción se crearon antes de que existiera la
-- columna, y lo único que las distingue es que su nombre dice
-- «(no es persona)». Se usa eso para marcarlas una vez; de aquí en adelante
-- se marca desde la ficha de la persona. Si alguna tuviera marcajes, jornadas
-- o un mes pagado, NO se marca y se avisa por NOTICE: esa fila hay que
-- mirarla con alguien antes de esconderla.
--
-- No hay rastro en `correcciones_auditoria` de este marcado inicial:
-- `corregido_por` es NOT NULL y en el SQL Editor no hay persona que firme. El
-- rastro es esta migración.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- · `terminal_roster` es la de la 0382: seis columnas
--   (id, nombres, apellidos, foto_url, sede_codigo, sede_nombre),
--   `security_invoker = false` y delegando la sede en
--   `fn_persona_marca_en_sede`. Se comprueba abajo y aborta si no.
-- · Existen `fn_es_admin_o_lider` y `fn_persona_actual_id`.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   drop trigger if exists trg_personas_cuenta_de_servicio_solo_por_rpc on personas;
--   drop function if exists fn_bloquear_cuenta_de_servicio_directa();
--   drop function if exists fn_set_cuenta_de_servicio(uuid, boolean, text);
--   -- y volver a pegar el bloque `create or replace view terminal_roster`
--   -- de la 0382. La columna se puede dejar: con todo en false no hace nada.
--   -- (Quitarla antes de revertir la 0491 rompería las funciones que la leen.)
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================


-- ── 0 · Comprobar el terreno de la vista ANTES de tocar nada ────────────────
do $guardia$
declare
  v_vista oid := to_regclass('public.terminal_roster');
  v_cols  text;
  v_opts  text;
begin
  if v_vista is null then
    raise exception 'PARA. La vista terminal_roster no existe. Esta migración la reescribe; falta la 0382.';
  end if;

  select string_agg(attname, ',' order by attnum) into v_cols
    from pg_attribute where attrelid = v_vista and attnum > 0 and not attisdropped;
  if v_cols <> 'id,nombres,apellidos,foto_url,sede_codigo,sede_nombre' then
    raise exception using
      message = 'PARA. terminal_roster no tiene las seis columnas de la 0382. Tiene: ' || v_cols || '.',
      hint    = 'Alguien la cambió después. Pegar esto la reemplazaría, y es la que pinta el '
             || 'roster de las Mac mini. Corre ./scripts/donde-vive.sh terminal_roster.';
  end if;

  select array_to_string(reloptions, ',') into v_opts from pg_class where oid = v_vista;
  if coalesce(v_opts, '') not like '%security_invoker=false%' then
    raise exception 'PARA. terminal_roster ya no es security_invoker = false (%). Revísalo antes.',
      coalesce(v_opts, '(ninguna)');
  end if;

  if position('fn_persona_marca_en_sede' in pg_get_viewdef(v_vista, true)) = 0 then
    raise exception 'PARA. terminal_roster ya no delega la sede en fn_persona_marca_en_sede (0382). Revísalo antes.';
  end if;
end
$guardia$;


-- ── 1 · La columna ──────────────────────────────────────────────────────────
alter table personas
  add column if not exists cuenta_de_servicio boolean not null default false;

comment on column personas.cuenta_de_servicio is
  'true = no es una persona: es una cuenta compartida que usa otro sistema (las estaciones de '
  'caja y almacén de cayla-retail, ADR-0160 de ese repo). Existe como fila de personas porque '
  'retail le cuelga ventas y movimientos, y activa porque su acceso lo exige. Dynamic no la '
  'paga, no la ofrece en el terminal ni la cuenta en ninguna lista del equipo. Se cambia solo '
  'con fn_set_cuenta_de_servicio. 0490.';


-- ── 2 · La puerta ───────────────────────────────────────────────────────────
create or replace function fn_set_cuenta_de_servicio(
  p_persona_id uuid,
  p_valor      boolean,
  p_motivo     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  boolean;
  v_rol    text;
  v_quien  uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder DO puede marcar una cuenta de servicio.';
  end if;

  if p_valor is null then
    raise exception 'Hay que decir sí o no.';
  end if;

  select cuenta_de_servicio, rol::text into v_antes, v_rol
    from personas where id = p_persona_id;
  if not found then
    raise exception 'Persona inválida.';
  end if;

  if v_antes = p_valor then
    return;
  end if;

  -- Marcar saca de la planilla (0491). Si esto le pasa a una persona real,
  -- deja de cobrar en silencio: por eso se niega ante cualquier señal de que
  -- ahí trabaja alguien. Desmarcar no tiene condiciones.
  if p_valor then
    if v_rol <> 'integrante' then
      raise exception 'Una cuenta de servicio no puede tener rol de líder ni de administración. Cámbiale el rol a integrante primero.';
    end if;
    if exists (select 1 from marcajes where persona_id = p_persona_id)
       or exists (select 1 from jornadas where persona_id = p_persona_id) then
      raise exception 'Esta ficha tiene marcajes: alguien trabajó con ella. Una cuenta de servicio no marca asistencia, y marcarla así la sacaría de la planilla.';
    end if;
    if exists (select 1 from planilla_pagada_detalle where persona_id = p_persona_id) then
      raise exception 'A esta ficha ya se le pagó al menos un mes. No se puede marcar como cuenta de servicio.';
    end if;
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Inicia sesión con tu usuario.';
  end if;

  update personas set cuenta_de_servicio = p_valor where id = p_persona_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.cuenta_de_servicio', v_antes::text, p_valor::text,
          coalesce(nullif(btrim(p_motivo), ''),
                   case when p_valor
                        then 'Marcada como cuenta de servicio: sale de la planilla y de las listas del equipo.'
                        else 'Deja de ser cuenta de servicio: vuelve a la planilla y a las listas del equipo.' end),
          v_quien);
end;
$$;

comment on function fn_set_cuenta_de_servicio(uuid, boolean, text) is
  'Marca o desmarca una fila de personas como cuenta de servicio (una estación de retail, no '
  'una persona). Solo admin o líder DO. Se niega a marcar a quien tiene marcajes, jornadas o un '
  'mes pagado, o un rol distinto de integrante: marcar saca de la planilla. Deja rastro en '
  'correcciones_auditoria. 0490.';

revoke all on function fn_set_cuenta_de_servicio(uuid, boolean, text) from public, anon;
grant execute on function fn_set_cuenta_de_servicio(uuid, boolean, text) to authenticated;


-- ── 3 · El candado: nada la cambia por fuera de la puerta ───────────────────
-- También en el INSERT: una fila que nace marcada se saltaría todas las
-- comprobaciones de arriba.
create or replace function fn_bloquear_cuenta_de_servicio_directa()
returns trigger
language plpgsql as $function$
begin
  if current_user <> 'postgres' then
    if tg_op = 'INSERT' and new.cuenta_de_servicio then
      raise exception 'Una persona nace como persona. Para marcarla como cuenta de servicio usa fn_set_cuenta_de_servicio.';
    end if;
    if tg_op = 'UPDATE' and new.cuenta_de_servicio is distinct from old.cuenta_de_servicio then
      raise exception 'La cuenta de servicio se cambia con fn_set_cuenta_de_servicio, no con un update directo.';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_personas_cuenta_de_servicio_solo_por_rpc on personas;
create trigger trg_personas_cuenta_de_servicio_solo_por_rpc
  before insert or update on personas
  for each row
  execute function fn_bloquear_cuenta_de_servicio_directa();


-- ── 4 · Las estaciones que ya existen ───────────────────────────────────────
do $marcar$
declare
  r record;
  v_marcadas int := 0;
begin
  for r in
    select p.id, p.nombres || ' ' || p.apellidos as nombre, p.rol::text as rol,
           exists (select 1 from marcajes m where m.persona_id = p.id)
             or exists (select 1 from jornadas j where j.persona_id = p.id)          as marco,
           exists (select 1 from planilla_pagada_detalle d where d.persona_id = p.id) as pagada
      from personas p
     where (p.nombres || ' ' || p.apellidos) ilike '%(no es persona)%'
       and not p.cuenta_de_servicio
  loop
    if r.marco or r.pagada or r.rol <> 'integrante' then
      raise notice 'NO se marcó «%»: %. Revisarla con alguien antes de esconderla.',
        r.nombre,
        concat_ws(', ',
          case when r.marco  then 'tiene marcajes' end,
          case when r.pagada then 'ya tiene un mes pagado' end,
          case when r.rol <> 'integrante' then 'su rol es ' || r.rol end);
    else
      update personas set cuenta_de_servicio = true where id = r.id;
      v_marcadas := v_marcadas + 1;
      raise notice 'Marcada como cuenta de servicio: %', r.nombre;
    end if;
  end loop;
  raise notice '0490: % estación(es) marcada(s) en esta pasada.', v_marcadas;
end
$marcar$;


-- ── 5 · El terminal de marcaje deja de ofrecerlas ───────────────────────────
-- Las mismas seis columnas y el mismo `security_invoker` de la 0382; la
-- delegación de sede sigue en `fn_persona_marca_en_sede`. Lo único nuevo es
-- `not p.cuenta_de_servicio`. `create or replace` y no `drop` + `create`: no
-- cambia la lista de columnas, así que se conservan los permisos (y van igual
-- abajo, redundantes a propósito, como en la 0382).
create or replace view terminal_roster
with (security_invoker = false)
as
select
  p.id,
  p.nombres,
  p.apellidos,
  p.foto_url,
  s.codigo as sede_codigo,
  s.nombre  as sede_nombre
from personas p
join sedes s on s.id = p.sede_base_id
where p.estado = 'activo'
  and not p.cuenta_de_servicio   -- CAMBIO 0490: una estación de retail no marca asistencia
  and fn_sede_actual_terminal() is not null
  and fn_persona_marca_en_sede(p.id, fn_sede_actual_terminal());

comment on view terminal_roster is
  'Lo unico que el kiosco de marcaje necesita ver de una persona: como se llama, su foto (0381) y de '
  'que sede es. Existe porque RLS filtra filas y no columnas, asi que mientras el terminal leyera '
  '`personas` su token alcanzaba el DNI y la remuneracion (0285). Desde la 0375 tampoco lleva '
  '`pin_hash`: el terminal ya no pide PIN. Desde la 0382 su condicion de sede la responde '
  'fn_persona_marca_en_sede, la misma que usan el disparador de escritura y '
  'fn_persona_en_roster_terminal — para que la regla no vuelva a tener dos copias que puedan separarse. '
  'Desde la 0490 no ofrece cuentas de servicio (estaciones de retail).';

revoke all    on terminal_roster from public, anon;
grant  select on terminal_roster to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (490, 'una_cuenta_de_servicio_no_es_una_persona')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación ────────────────────────────────────────────────────────────
-- `marcadas` tiene que ser el número de estaciones (6 el 2026-09-28) y
-- `sin_marcar_con_ese_nombre` cero; si no, lee los NOTICE de arriba.
select
  (select count(*) from personas where cuenta_de_servicio)                         as marcadas,
  (select string_agg(nombres || ' ' || apellidos, ' · ' order by apellidos)
     from personas where cuenta_de_servicio)                                         as cuales,
  (select count(*) from personas
    where (nombres || ' ' || apellidos) ilike '%(no es persona)%'
      and not cuenta_de_servicio)                                                    as sin_marcar_con_ese_nombre,
  position('cuenta_de_servicio' in
           pg_get_viewdef('public.terminal_roster'::regclass, true)) > 0             as roster_las_excluye,
  (select count(*) from pg_trigger
    where tgname = 'trg_personas_cuenta_de_servicio_solo_por_rpc'
      and tgrelid = 'personas'::regclass)                                            as candado,
  (select nombre from migraciones_aplicadas where numero = 490)                      as registro;
