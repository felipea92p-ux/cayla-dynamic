-- ============================================================================
-- 0369 — La ficha guarda el género
-- ============================================================================
--
-- QUÉ PROMETE
--   Un campo "Género" en Datos personales, guardado en `datos_personales` y no
--   inventado en pantalla. Hasta hoy el sistema NO lo guardaba: la columna
--   "Sexo" del padrón para el contador salía en blanco a propósito (ver el
--   comentario que dejó esa decisión, en `admin/datos-personales/page.tsx`),
--   porque el T-Registro la pide y acá no había dónde ponerla.
--
-- QUÉ ASUME
--   Que `fn_set_datos_personales` no la tocó nadie más hoy. El cuerpo se copia
--   de la 0198 (`el_cuspp_y_el_correo_entran_a_la_ficha`), confirmada md5
--   idéntica contra producción — las DOS firmas de abajo, ver el siguiente
--   punto — el 2026-09-04.
--
-- ── DOS FIRMAS SUPERPUESTAS, Y POR QUÉ SE RETIRAN LAS DOS ───────────────────
--
--   `fn_set_datos_personales` vive hoy DUPLICADA en producción, sin que
--   ninguna migración lo dijera: la 0198 le agregó `p_cuspp` con
--   `CREATE OR REPLACE`, pero como el número de parámetros cambió (18 → 19),
--   Postgres no reemplazó nada — CREÓ una segunda función. La de 0125 (18
--   argumentos, sin cuspp) se quedó viva al lado, exactamente el fallo que la
--   0125 ya conocía y por eso dejaba caer su propia firma vieja de 13 (ver su
--   comentario: "si sobrevive, la pantalla podría llamarla por error").
--
--   Confirmado el 2026-09-04, contra el Postgres local (construido desde cero
--   con todas las migraciones de este repo) Y contra producción — los mismos
--   dos md5, byte por byte:
--     fn_set_datos_personales(uuid,text,date,text,text,text,text,text,text,
--       boolean,text,text,text,text,text,text,boolean,text)                 -- 0125, 2160 car.
--     fn_set_datos_personales(uuid,text,date,text,text,text,text,text,text,
--       boolean,text,text,text,text,text,text,boolean,text,text)            -- 0198, 2367 car.
--
--   Las dos se retiran acá, antes de sumar `p_genero`: si no, esto habría
--   dejado TRES firmas en vez de arreglar el problema.
--
-- ── Y POR QUÉ EL GRANT VA EXPLÍCITO, NO ES ADORNO ───────────────────────────
--
--   `drop function` + `create` no es lo mismo que `create or replace`: crea un
--   objeto nuevo, con su ACL en blanco. Desde la 0076
--   (`alter default privileges revoke execute on functions from public`),
--   ninguna función nueva regala EXECUTE por defecto. La 0338 cayó en esto
--   exacto con `fn_provisiones` — mismo patrón, incluso el mismo motivo (sumar
--   un parámetro obligó a un DROP) — y `authenticated` se quedó sin poder
--   llamarla hasta que la 0363 lo corrigió tres migraciones después. Acá el
--   `grant` va en la misma migración que el `drop`, no en una de reparación
--   posterior.
--
-- ── BINARIO, Y GUARDADO EN datos_personales, NO EN personas ─────────────────
--
--   Dos valores porque es lo que pide el T-Registro (columna "Sexo" de la
--   PLAME): un dato para el contador, no una clasificación social. Vive en
--   `datos_personales` y no en `personas` por la misma razón que
--   `estado_civil`: es un dato de la ficha, lo edita quien opera Equipo/DO
--   igual que el resto de la ficha, y no decide nada del acceso al sistema.
--
-- CÓMO SE REVIERTE
--   Restaurar las dos firmas anteriores de `fn_set_datos_personales` (0125 y
--   0198) y sus grants. La columna `genero` puede quedarse: sin nadie que la
--   lea no hace nada, y borrarla perdería los datos ya cargados.
-- ============================================================================

alter table datos_personales
  add column if not exists genero text;

comment on column datos_personales.genero is
  'Género de la persona, como lo pide la columna "Sexo" del T-Registro/PLAME. '
  'Binario a propósito — ver GENEROS en packages/shared/src/enums.ts. Vive acá '
  'y no en personas por la misma razón que estado_civil: es un dato de la '
  'ficha, no de la cuenta.';

-- Retira las dos firmas superpuestas (ver el comentario de arriba) antes de
-- crear la que sigue — si no, quedarían TRES.
drop function if exists fn_set_datos_personales(
  uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,
  text,text,text,boolean,text);
drop function if exists fn_set_datos_personales(
  uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,
  text,text,text,boolean,text,text);

CREATE OR REPLACE FUNCTION public.fn_set_datos_personales(p_persona_id uuid, p_nombre_dni text DEFAULT NULL::text, p_fecha_nacimiento date DEFAULT NULL::date, p_estado_civil text DEFAULT NULL::text, p_direccion text DEFAULT NULL::text, p_celular text DEFAULT NULL::text, p_entidad_bancaria text DEFAULT NULL::text, p_numero_cuenta text DEFAULT NULL::text, p_grado_instruccion text DEFAULT NULL::text, p_hijos_menores boolean DEFAULT NULL::boolean, p_foto_dni_url text DEFAULT NULL::text, p_foto_personal_url text DEFAULT NULL::text, p_foto_profesional_url text DEFAULT NULL::text, p_emergencia_nombre text DEFAULT NULL::text, p_emergencia_vinculo text DEFAULT NULL::text, p_emergencia_telefono text DEFAULT NULL::text, p_discapacidad boolean DEFAULT NULL::boolean, p_discapacidad_conadis text DEFAULT NULL::text, p_cuspp text DEFAULT NULL::text, p_genero text DEFAULT NULL::text)
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
    cuspp,
    genero,                                           -- CAMBIO 0369
    actualizado_por, actualizado_at)
  values (
    p_persona_id, p_nombre_dni, p_fecha_nacimiento, p_estado_civil, p_direccion, p_celular,
    p_entidad_bancaria, p_numero_cuenta, p_grado_instruccion, p_hijos_menores,
    p_foto_dni_url, p_foto_personal_url, p_foto_profesional_url,
    p_emergencia_nombre, p_emergencia_vinculo, p_emergencia_telefono,
    p_discapacidad, p_discapacidad_conadis,
    nullif(upper(trim(p_cuspp)), ''),
    nullif(lower(trim(p_genero)), ''),                 -- CAMBIO 0369
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
    cuspp = excluded.cuspp,
    genero = excluded.genero,                          -- CAMBIO 0369
    actualizado_por = fn_persona_actual_id(), actualizado_at = now();
end;
$function$;

grant execute on function fn_set_datos_personales(
  uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,
  text,text,text,boolean,text,text,text) to authenticated;
revoke execute on function fn_set_datos_personales(
  uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,
  text,text,text,boolean,text,text,text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (369, 'la_ficha_guarda_el_genero')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
