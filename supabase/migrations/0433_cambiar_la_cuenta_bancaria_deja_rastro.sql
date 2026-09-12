-- ============================================================================
-- 0433 · CAMBIAR LA CUENTA BANCARIA DEJA RASTRO
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cambiar `entidad_bancaria` o `numero_cuenta` desde
--   `fn_set_datos_personales` deje una fila en `correcciones_auditoria` —quién
--   lo hizo, cuándo, y el valor anterior y el nuevo— igual que ya exige
--   cualquier corrección de marcaje o de salario. No cambia ningún permiso ni
--   ninguna otra columna: el resto de la ficha (17 de los 19 parámetros)
--   sigue exactamente igual.
--
-- EL DEFECTO
--   `fn_set_datos_personales` es un upsert que reemplaza toda la fila de
--   `datos_personales` de una vez (`insert ... on conflict do update`), y solo
--   registraba `actualizado_por`/`actualizado_at` — quién y cuándo, nunca qué
--   cambió ni desde qué valor. `correcciones_auditoria` es "el libro
--   transversal" (0298) al que ya están obligados marcajes, salarios y el
--   régimen de pensión (0277) — la cuenta bancaria, el dato que decide a dónde
--   llega el sueldo de cada persona, se quedó fuera de esa lista. Señalado en
--   la auditoría de arquitectura del 2026-09-03 (docs/hallazgos-abiertos.md).
--
--   Y desde la 0399 el alcance de quién puede llamarla creció: ya no es solo
--   admin/líder, también la encargada de la sede de esa persona
--   (`supervisor_sede` sobre su propio equipo) — así que el rastro importa
--   más hoy que cuando se escribió el hallazgo, no menos.
--
-- QUÉ ASUME
--   md5 de partida de `fn_set_datos_personales` (0399, sin cambios desde
--   entonces): 0a766c0210e75308b8a393a6922641a9 — confirmado en el Postgres
--   local antes de escribir esta migración con
--     select md5(prosrc) from pg_proc where proname = 'fn_set_datos_personales';
--   Se pide a PRODUCCIÓN otra vez antes de pegar (ver CLAUDE.md).
--
-- POR QUÉ SOLO ESTAS DOS COLUMNAS, Y NO LAS 17 RESTANTES
--   No es media corrección: es la corrección proporcional al riesgo. Las otras
--   17 (celular, dirección, contacto de emergencia, discapacidad, género…) no
--   mueven dinero ni deciden a quién se le paga. Auditar las 19 de una vez
--   exigiría además decidir qué motivo poner en 17 filas que hoy nadie pide
--   como evento de negocio — la cuenta bancaria sí lo es, con o sin motivo
--   escrito a mano, por la misma razón que ya lo es cambiar la sede o el
--   régimen de pensión.
--
-- POR QUÉ DOS FILAS Y NO UNA
--   Mismo criterio que ya usan `personas.rol` y `personas.sede_base_id`: un
--   `campo_modificado` por columna, no un formato compuesto inventado para la
--   ocasión — quien lea el historial de alguien encuentra "datos_personales.
--   entidad_bancaria" con el mismo patrón que ya conoce, no una excepción.
--
-- CÓMO SE REVIERTE
--   `create or replace function fn_set_datos_personales` con el cuerpo de la
--   0399 (sin el bloque `-- CAMBIO 0433`).
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El select del final: `md5_incluye_auditoria` tiene que dar `true`.
-- ============================================================================

create or replace function public.fn_set_datos_personales(p_persona_id uuid, p_nombre_dni text DEFAULT NULL::text, p_fecha_nacimiento date DEFAULT NULL::date, p_estado_civil text DEFAULT NULL::text, p_direccion text DEFAULT NULL::text, p_celular text DEFAULT NULL::text, p_entidad_bancaria text DEFAULT NULL::text, p_numero_cuenta text DEFAULT NULL::text, p_grado_instruccion text DEFAULT NULL::text, p_hijos_menores boolean DEFAULT NULL::boolean, p_foto_dni_url text DEFAULT NULL::text, p_foto_personal_url text DEFAULT NULL::text, p_foto_profesional_url text DEFAULT NULL::text, p_emergencia_nombre text DEFAULT NULL::text, p_emergencia_vinculo text DEFAULT NULL::text, p_emergencia_telefono text DEFAULT NULL::text, p_discapacidad boolean DEFAULT NULL::boolean, p_discapacidad_conadis text DEFAULT NULL::text, p_cuspp text DEFAULT NULL::text, p_genero text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_entidad_antes text;
  v_cuenta_antes  text;
  v_quien         uuid;
begin
  -- CAMBIO 0399: se quita "or p_persona_id = fn_persona_actual_id()" — la
  -- propia persona ya no edita su ficha directo, pasa por
  -- fn_crear_solicitud_perfil / fn_aplicar_cambio_perfil.
  if (fn_es_admin_o_lider()
          or (fn_rol_actual() = 'supervisor_sede'
              and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona())) is not true then
    raise exception 'Sin permiso para editar los datos personales de esta persona.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;

  -- CAMBIO 0433 · el valor de ANTES, para poder auditar el de después. Se lee
  -- antes del upsert a propósito: después de él ya no hay "antes" que leer.
  select entidad_bancaria, numero_cuenta into v_entidad_antes, v_cuenta_antes
    from datos_personales where persona_id = p_persona_id;

  insert into datos_personales as dp (
    persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular,
    entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores,
    foto_dni_url, foto_personal_url, foto_profesional_url,
    emergencia_nombre, emergencia_vinculo, emergencia_telefono,
    discapacidad, discapacidad_conadis,
    cuspp,
    genero,
    actualizado_por, actualizado_at)
  values (
    p_persona_id, p_nombre_dni, p_fecha_nacimiento, p_estado_civil, p_direccion, p_celular,
    p_entidad_bancaria, p_numero_cuenta, p_grado_instruccion, p_hijos_menores,
    p_foto_dni_url, p_foto_personal_url, p_foto_profesional_url,
    p_emergencia_nombre, p_emergencia_vinculo, p_emergencia_telefono,
    p_discapacidad, p_discapacidad_conadis,
    nullif(upper(trim(p_cuspp)), ''),
    nullif(lower(trim(p_genero)), ''),
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
    genero = excluded.genero,
    actualizado_por = fn_persona_actual_id(), actualizado_at = now();

  -- CAMBIO 0433 · el rastro. `is distinct from` para que null → null (nadie la
  -- tocó) no escriba una fila vacía, y para que null → 'BCP' (se cargó por
  -- primera vez) sí quede anotado como cualquier otro cambio.
  if p_entidad_bancaria is distinct from v_entidad_antes
     or p_numero_cuenta is distinct from v_cuenta_antes then
    v_quien := fn_persona_actual_id();
    if v_quien is null then
      raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
    end if;

    if p_entidad_bancaria is distinct from v_entidad_antes then
      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
      values (p_persona_id, 'datos_personales.entidad_bancaria', v_entidad_antes, p_entidad_bancaria,
              'Cambio de datos personales — decide a dónde se transfiere el sueldo.', v_quien);
    end if;

    if p_numero_cuenta is distinct from v_cuenta_antes then
      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
      values (p_persona_id, 'datos_personales.numero_cuenta', v_cuenta_antes, p_numero_cuenta,
              'Cambio de datos personales — decide a dónde se transfiere el sueldo.', v_quien);
    end if;
  end if;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (433, 'cambiar_la_cuenta_bancaria_deja_rastro')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select (prosrc like '%datos_personales.entidad_bancaria%'
        and prosrc like '%datos_personales.numero_cuenta%') as md5_incluye_auditoria
  from pg_proc where proname = 'fn_set_datos_personales';
