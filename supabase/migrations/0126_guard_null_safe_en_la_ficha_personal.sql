-- ============================================================================
-- 0126 — El guard de la ficha personal vuelve a ser null-safe
--
-- QUÉ ARREGLA. Tres funciones de la 0125 escriben su guard como
-- «if not (A or B or C)» en vez de «if (A or B or C) is not true». Es la sexta
-- vez que esta forma entra al repo, y el CLAUDE.md la prohíbe por escrito.
--
-- POR QUÉ ES UN AGUJERO, en tres pasos:
--   · Para una identidad autenticada SIN fila en personas —que es exactamente lo
--     que es la cuenta de la Mac mini de cada sede— fn_persona_actual_id()
--     devuelve null.
--   · Entonces «p_persona_id = fn_persona_actual_id()» es null, y la rama de
--     supervisor_sede también, así que la expresión completa es
--     «false or null or null» = NULL.
--   · «not null» es null, el IF no entra, y el raise nunca se dispara: la
--     función sigue de largo y escribe.
--
-- REPRODUCIDO contra Postgres local antes de escribir esto: con la sesión de una
-- identidad sin fila en personas se sobrescribió la entidad bancaria y el número
-- de cuenta de otra persona. Y como fn_set_datos_personales es un upsert que
-- REEMPLAZA, una sola llamada con los campos vacíos le borra a alguien el nombre
-- legal, la fecha de nacimiento, la dirección y el celular.
--
-- La 0125 ya está aplicada en producción (verificado el 2026-08-02), así que
-- esto no es una corrección preventiva: cierra algo que está abierto.
--
-- Los pagos de CAYLA son en efectivo —así lo declara el T-Registro—, así que
-- reescribir una cuenta bancaria no desvía dinero. El daño real es la pérdida de
-- datos personales y la posibilidad de alterar la ficha de la que salen los
-- memos y los contratos.
--
-- QUÉ NO CAMBIA. Ni un carácter del cuerpo de las tres funciones, salvo la línea
-- del guard. Los cuerpos de abajo se EXTRAJERON del archivo de la 0125 con un
-- script y se les aplicó un solo reemplazo, para que no haya diferencia por
-- retipear. Nadie pierde ni gana un permiso que tuviera legítimamente: quien ya
-- estaba autorizado sigue igual.
--
-- POR QUÉ LA FORMA «is not true» Y NO ARREGLAR fn_persona_actual_id(). Porque la
-- 0078 ya hizo que los booleanos de permiso no devuelvan null, y esto volvió a
-- pasar igual: cualquier comparación de un UUID contra una función que puede
-- devolver null produce null por su cuenta. La forma del guard es la única
-- defensa que no depende de recordar el detalle.
--
-- CÓMO SE REVIERTE. Restaurar las tres funciones desde la 0125 — pero no se
-- debería: eso reabre el agujero.
-- ============================================================================


-- ── 1 · fn_set_derechohabiente ───────────────────────────────────────────────
create or replace function fn_set_derechohabiente(
  p_id               uuid,          -- null = nuevo
  p_persona_id       uuid,
  p_nombres          text,
  p_apellidos        text,
  p_vinculo          text,
  p_documento        text default null,
  p_fecha_nacimiento date default null,
  p_essalud          boolean default false,
  p_vida_ley         boolean default false,
  p_nota             text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id    uuid;
  v_sede  uuid;
begin
  select sede_base_id into v_sede from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe.';
  end if;

  -- Mismo permiso que fn_set_datos_personales: admin/líder, la encargada de su
  -- sede, o la propia persona. Decisión de Felipe del 2026-08-01.
  if (fn_es_admin_o_lider()
          or p_persona_id = fn_persona_actual_id()
          or (fn_rol_actual() = 'supervisor_sede' and v_sede = fn_sede_actual_persona())) is not true then
    raise exception 'Sin permiso para editar los familiares de esta persona.';
  end if;

  if nullif(btrim(coalesce(p_nombres, '')), '') is null
     or nullif(btrim(coalesce(p_apellidos, '')), '') is null then
    raise exception 'El nombre y el apellido del familiar son obligatorios.';
  end if;

  if p_id is null then
    insert into derechohabientes
      (persona_id, nombres, apellidos, documento, fecha_nacimiento, vinculo,
       essalud, vida_ley, nota, registrado_por)
    values
      (p_persona_id, btrim(p_nombres), btrim(p_apellidos),
       nullif(btrim(coalesce(p_documento, '')), ''), p_fecha_nacimiento, p_vinculo,
       coalesce(p_essalud, false), coalesce(p_vida_ley, false),
       nullif(btrim(coalesce(p_nota, '')), ''), fn_persona_actual_id())
    returning id into v_id;
  else
    update derechohabientes set
      nombres = btrim(p_nombres), apellidos = btrim(p_apellidos),
      documento = nullif(btrim(coalesce(p_documento, '')), ''),
      fecha_nacimiento = p_fecha_nacimiento, vinculo = p_vinculo,
      essalud = coalesce(p_essalud, false), vida_ley = coalesce(p_vida_ley, false),
      nota = nullif(btrim(coalesce(p_nota, '')), '')
    where id = p_id and persona_id = p_persona_id
    returning id into v_id;

    if v_id is null then
      raise exception 'No encontré ese familiar en la ficha de esta persona.';
    end if;
  end if;

  return v_id;
end;
$$;

-- ── 2 · fn_cerrar_derechohabiente ────────────────────────────────────────────
create or replace function fn_cerrar_derechohabiente(p_id uuid, p_hasta date default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_persona uuid; v_sede uuid;
begin
  select d.persona_id, p.sede_base_id into v_persona, v_sede
  from derechohabientes d join personas p on p.id = d.persona_id
  where d.id = p_id;

  if not found then
    raise exception 'Ese familiar no existe.';
  end if;

  if (fn_es_admin_o_lider()
          or v_persona = fn_persona_actual_id()
          or (fn_rol_actual() = 'supervisor_sede' and v_sede = fn_sede_actual_persona())) is not true then
    raise exception 'Sin permiso para editar los familiares de esta persona.';
  end if;

  -- fn_hoy_lima() y NO current_date: el servidor de Supabase corre en UTC, así
  -- que entre las 19:00 y la medianoche de Lima `current_date` ya devuelve
  -- mañana. Cerrar a un familiar de noche le pondría una fecha que todavía no
  -- llegó. La prueba 92 vigila esto porque el mismo error entró cuatro veces.
  update derechohabientes
     set vigente_hasta = coalesce(p_hasta, fn_hoy_lima())
   where id = p_id;
end;
$$;

-- ── 3 · fn_set_datos_personales ──────────────────────────────────────────────
-- OJO: sigue siendo un upsert que REEMPLAZA todas las columnas. Lo que no se
-- pasa queda en null. La pantalla tiene que mandar siempre los dieciocho campos.
create or replace function fn_set_datos_personales(
  p_persona_id uuid,
  p_nombre_dni text default null, p_fecha_nacimiento date default null, p_estado_civil text default null,
  p_direccion text default null, p_celular text default null,
  p_entidad_bancaria text default null, p_numero_cuenta text default null,
  p_grado_instruccion text default null, p_hijos_menores boolean default null,
  p_foto_dni_url text default null, p_foto_personal_url text default null, p_foto_profesional_url text default null,
  -- CAMBIO 0125
  p_emergencia_nombre text default null, p_emergencia_vinculo text default null,
  p_emergencia_telefono text default null,
  p_discapacidad boolean default null, p_discapacidad_conadis text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if (fn_es_admin_o_lider()
          or p_persona_id = fn_persona_actual_id()
          or (fn_rol_actual() = 'supervisor_sede'
              and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona())) is not true then
    raise exception 'Sin permiso para editar los datos personales de esta persona.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;
  insert into datos_personales as dp (
    persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular,
    entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores,
    foto_dni_url, foto_personal_url, foto_profesional_url,
    emergencia_nombre, emergencia_vinculo, emergencia_telefono,
    discapacidad, discapacidad_conadis,
    actualizado_por, actualizado_at)
  values (
    p_persona_id, p_nombre_dni, p_fecha_nacimiento, p_estado_civil, p_direccion, p_celular,
    p_entidad_bancaria, p_numero_cuenta, p_grado_instruccion, p_hijos_menores,
    p_foto_dni_url, p_foto_personal_url, p_foto_profesional_url,
    p_emergencia_nombre, p_emergencia_vinculo, p_emergencia_telefono,
    p_discapacidad, p_discapacidad_conadis,
    fn_persona_actual_id(), now())
  on conflict (persona_id) do update set
    nombre_dni = excluded.nombre_dni, fecha_nacimiento = excluded.fecha_nacimiento,
    estado_civil = excluded.estado_civil, direccion = excluded.direccion, celular = excluded.celular,
    entidad_bancaria = excluded.entidad_bancaria, numero_cuenta = excluded.numero_cuenta,
    grado_instruccion = excluded.grado_instruccion, hijos_menores = excluded.hijos_menores,
    foto_dni_url = excluded.foto_dni_url, foto_personal_url = excluded.foto_personal_url,
    foto_profesional_url = excluded.foto_profesional_url,
    emergencia_nombre = excluded.emergencia_nombre,
    emergencia_vinculo = excluded.emergencia_vinculo,
    emergencia_telefono = excluded.emergencia_telefono,
    discapacidad = excluded.discapacidad,
    discapacidad_conadis = excluded.discapacidad_conadis,
    actualizado_por = fn_persona_actual_id(), actualizado_at = now();
end;
$$;

-- Los grants se repiten porque «create or replace» no los pierde, pero dejarlos
-- escritos hace que este archivo se sostenga solo si alguien lo aplica sobre una
-- base reconstruida desde cero.
revoke all    on function fn_set_derechohabiente(uuid,uuid,text,text,text,text,date,boolean,boolean,text) from public, anon;
grant execute on function fn_set_derechohabiente(uuid,uuid,text,text,text,text,date,boolean,boolean,text) to authenticated;
revoke all    on function fn_cerrar_derechohabiente(uuid, date) from public, anon;
grant execute on function fn_cerrar_derechohabiente(uuid, date) to authenticated;
grant execute on function fn_set_datos_personales(
  uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,
  text,text,text,boolean,text) to authenticated;


-- ── El aviso de cierre ───────────────────────────────────────────────────────
do $mig$
declare v_malos text;
begin
  -- Censo de la forma prohibida en TODO el esquema, no solo en estas tres. Si
  -- quedan otras, mejor saberlo ahora que en la sexta vez.
  select string_agg(p.proname, ', ' order by p.proname) into v_malos
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosrc like '%if not (fn_es_admin_o_lider()%';

  if v_malos is null then
    raise notice '0126 · ningun guard con la forma prohibida queda en el esquema.';
  else
    raise notice '0126 · ATENCION: siguen con la forma prohibida: %', v_malos;
  end if;
end
$mig$;


insert into migraciones_aplicadas (numero, nombre)
values (126, 'guard_null_safe_en_la_ficha_personal')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
