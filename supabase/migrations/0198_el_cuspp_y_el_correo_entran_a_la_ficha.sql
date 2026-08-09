-- ============================================================================
-- 0198 — El CUSPP y el correo entran a la ficha
-- ============================================================================
--
-- QUÉ PROMETE
--   Que los dos datos que hoy obligan a salir del sistema se puedan guardar
--   desde la ficha de la persona: el CUSPP, que no existía en ninguna tabla, y
--   el correo, que existe en `personas` pero no se podía editar desde ahí.
--
-- QUÉ ASUME
--   Que `fn_set_datos_personales` no la tocó nadie más hoy. El cuerpo se extrajo
--   con pg_get_functiondef, no se copió de un archivo, y lo único que cambia es
--   un parámetro más al final y su columna. Los 18 parámetros anteriores quedan
--   en el mismo orden a propósito: van por nombre desde el cliente, pero quien
--   los llame por posición no debe romperse.
--
-- ── POR QUÉ EL CUSPP IMPORTA, Y POR QUÉ NO ES PARA TODOS ────────────────────
--
-- El CUSPP es el código con el que la AFP identifica la cuenta individual de
-- cada persona. Sin él, el aporte se declara pero puede no llegar a la cuenta
-- correcta. En el T-Registro es obligatorio para quien está afiliado a una AFP.
--
-- NO aplica a ONP ni a quien ya se jubiló: ahí no hay cuenta individual que
-- identificar. Medido el 2026-08-08: 18 de 21 personas en planilla están en AFP
-- (9 Profuturo, 8 Integra, 1 Prima) y las otras 3 no tienen ni pueden tener
-- CUSPP. Por eso la pantalla solo se lo pide a quien está en AFP — pedirle un
-- código inexistente a Raquel es el tipo de aviso que enseña a ignorar avisos.
--
-- Esa regla vive en la PANTALLA y no acá a propósito: la base guarda el dato si
-- se lo dan, sin opinar. El día que alguien cambie de ONP a AFP, su CUSPP no
-- tiene por qué borrarse ni bloquearse.
--
-- ── EL CORREO: POR QUÉ UNA FUNCIÓN APARTE Y CON CANDADO ─────────────────────
--
-- `personas.email` no es un dato de contacto cualquiera: es el USUARIO con el
-- que la persona entra al sistema. Cambiarlo en `personas` NO cambia su cuenta
-- de Supabase Auth, así que quedaría con un correo en la ficha y otro en su
-- login — y nadie se enteraría hasta que intente entrar.
--
-- Se decidió (Felipe, 2026-08-08) hacer ese estado IMPOSIBLE en vez de
-- advertirlo: la función RECHAZA el cambio si la persona ya tiene cuenta. Miente
-- menos un error claro que un aviso que se puede ignorar. Mientras no tenga
-- acceso creado, el correo se corrige libremente desde la ficha, que es cuando
-- de verdad hace falta — es el caso de Paola, que hoy no tiene correo cargado.
--
-- Para cambiarle el correo a alguien que YA entra al sistema hay que pasar por
-- /admin/cuentas, que es donde vive el acceso y donde se puede reinvitar.
--
-- El permiso es el mismo que el del DNI (`fn_es_admin_o_lider`) y no el de la
-- ficha completa: la encargada de sede edita celular y dirección de su equipo,
-- pero no la identidad ni la puerta de entrada al sistema.
--
-- CÓMO SE REVIERTE
--   drop function fn_set_email(uuid, text);
--   Restaurar fn_set_datos_personales desde su versión anterior. La columna
--   `cuspp` puede quedarse: sin nadie que la lea no hace nada, y borrarla
--   perdería los códigos ya cargados.
-- ============================================================================

alter table datos_personales
  add column if not exists cuspp text;

comment on column datos_personales.cuspp is
  'Código Único de Identificación del SPP: identifica la cuenta individual de la persona '
  'en su AFP y es obligatorio en el T-Registro para afiliados al sistema privado. NO aplica '
  'a ONP ni a jubilados — ahí no hay cuenta individual. Quién debe tenerlo lo decide la '
  'pantalla según regimen_pension; esta columna guarda lo que le den.';

-- ── 1 · La ficha, con un campo más ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_set_datos_personales(p_persona_id uuid, p_nombre_dni text DEFAULT NULL::text, p_fecha_nacimiento date DEFAULT NULL::date, p_estado_civil text DEFAULT NULL::text, p_direccion text DEFAULT NULL::text, p_celular text DEFAULT NULL::text, p_entidad_bancaria text DEFAULT NULL::text, p_numero_cuenta text DEFAULT NULL::text, p_grado_instruccion text DEFAULT NULL::text, p_hijos_menores boolean DEFAULT NULL::boolean, p_foto_dni_url text DEFAULT NULL::text, p_foto_personal_url text DEFAULT NULL::text, p_foto_profesional_url text DEFAULT NULL::text, p_emergencia_nombre text DEFAULT NULL::text, p_emergencia_vinculo text DEFAULT NULL::text, p_emergencia_telefono text DEFAULT NULL::text, p_discapacidad boolean DEFAULT NULL::boolean, p_discapacidad_conadis text DEFAULT NULL::text, p_cuspp text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    cuspp,                                            -- CAMBIO 0198
    actualizado_por, actualizado_at)
  values (
    p_persona_id, p_nombre_dni, p_fecha_nacimiento, p_estado_civil, p_direccion, p_celular,
    p_entidad_bancaria, p_numero_cuenta, p_grado_instruccion, p_hijos_menores,
    p_foto_dni_url, p_foto_personal_url, p_foto_profesional_url,
    p_emergencia_nombre, p_emergencia_vinculo, p_emergencia_telefono,
    p_discapacidad, p_discapacidad_conadis,
    nullif(upper(trim(p_cuspp)), ''),                 -- CAMBIO 0198
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
    cuspp = excluded.cuspp,                           -- CAMBIO 0198
    actualizado_por = fn_persona_actual_id(), actualizado_at = now();
end;
$function$;

-- ── 2 · El correo, con el candado del login ─────────────────────────────────
create or replace function public.fn_set_email(p_persona_id uuid, p_email text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_auth uuid; v_email text; v_nuevo text;
begin
  -- Mismo permiso que el DNI, no el de la ficha completa: la encargada de sede
  -- corrige el celular de su equipo, pero no la puerta de entrada al sistema.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede cambiar el correo.';
  end if;

  select auth_user_id, email into v_auth, v_email from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe.';
  end if;

  -- Se normaliza ANTES de comparar: el login no distingue mayúsculas, así que
  -- «Ana@X.pe» y «ana@x.pe» son el mismo correo y no un cambio.
  v_nuevo := nullif(lower(trim(p_email)), '');

  -- Si no cambió, no se escribe. No es una micro-optimización: el formulario
  -- manda todos los campos juntos cada vez que se guarda, así que sin esto
  -- guardar la dirección de alguien movería su `updated_at` y —en la práctica—
  -- reescribiría una fila que no hacía falta tocar.
  if v_nuevo is not distinct from v_email then
    return;
  end if;

  -- EL CANDADO. `personas.email` es el usuario con el que se entra, y cambiarlo
  -- acá NO cambia la cuenta de Supabase Auth: quedaría un correo en la ficha y
  -- otro en el login, sin que nadie se entere hasta que intente entrar.
  -- Se rechaza en vez de advertir. El error dice a dónde ir.
  if v_auth is not null then
    raise exception 'Esta persona ya tiene cuenta creada con "%". Cambiar el correo acá no cambiaría su acceso: hazlo desde Cuentas.', coalesce(v_email, '—');
  end if;

  update personas set email = v_nuevo, updated_at = now() where id = p_persona_id;
end;
$function$;

comment on function public.fn_set_email(uuid, text) is
  'Cambia el correo de una persona SOLO si todavía no tiene cuenta de acceso. Con cuenta '
  'creada, el correo es su usuario y se cambia desde /admin/cuentas — acá se rechaza para '
  'que no quede un correo en la ficha y otro en el login.';

grant  execute on function public.fn_set_email(uuid, text) to authenticated;
revoke execute on function public.fn_set_email(uuid, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (198, 'el_cuspp_y_el_correo_entran_a_la_ficha')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
