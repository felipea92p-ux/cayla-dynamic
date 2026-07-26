-- ============================================================================
-- 0078 — Que un permiso que no se sabe responder sea "no", nunca "quizá"
-- ----------------------------------------------------------------------------
-- PROMETE: que ningún guard de permiso del sistema deje pasar una operación
--   porque la respuesta fue NULL en vez de false.
-- ASUME: la 0076 ya corrigió fn_expediente_puede_actuar (sus 7 usos quedan
--   cubiertos por ella). Esta cierra los que quedaron.
--
-- EL DEFECTO, EN CRIOLLO. Los permisos se preguntan así:
--
--     if not fn_es_admin_o_lider() then raise exception 'Sin permiso'; end if;
--
-- fn_es_admin_o_lider() es `fn_rol_actual() in ('admin','lider_do')`. Cuando
-- quien pregunta NO TIENE FILA en `personas`, fn_rol_actual() devuelve NULL, y
-- `NULL in (...)` es NULL — no es false, es "no sé". Y `not NULL` también es
-- NULL. Un `if` con condición NULL NO ENTRA: el `raise exception` nunca se
-- dispara y la operación continúa como si el permiso estuviera concedido.
--
-- QUIÉN ES ESA IDENTIDAD SIN FILA EN personas: la TERMINAL de cada sede. Se
-- autentica con su propio usuario y clave (no es una colaboradora), así que
-- tiene sesión válida y no tiene fila. Es decir, no es un caso hipotético: hay
-- tres de esas identidades encendidas todo el día en TRU, LIM y AQP.
--
-- REPRODUCIDO EL 26/07/2026 contra un Postgres limpio con las 77 migraciones:
-- con la sesión de un terminal, `fn_set_datos_personales` sobrescribió la
-- cuenta bancaria y el número de cuenta de una colaboradora sin error alguno.
--
-- POR QUÉ SE ARREGLA EN LA RAÍZ Y NO GUARD POR GUARD. Se podría envolver cada
-- `if` en un `coalesce`. Pero entonces el próximo guard que alguien escriba
-- vuelve a nacer roto: la forma natural de escribirlo es la insegura. Se
-- corrige la FUENTE — que fn_es_admin_o_lider nunca conteste NULL — y con eso
-- los cuatro sitios que la usan quedan sanos sin tocarlos, incluidos los que
-- se escriban mañana. Solo queda un guard compuesto (datos personales) que
-- mezcla tres preguntas distintas; ese sí se reescribe a mano, con la forma
-- `is not true` que manda CLAUDE.md.
--
-- Reversible: volver a las definiciones de 0003 / 0061 / 0074.
-- ============================================================================

-- ── La raíz: un booleano de permiso jamás contesta "no sé" ──────────────────
-- Ojo: fn_rol_actual() SÍ debe poder devolver NULL — "esta identidad no tiene
-- rol" es un hecho verdadero y otras consultas lo usan. Lo que no puede seguir
-- pasando es que esa incertidumbre se propague a una PREGUNTA DE PERMISO.
create or replace function fn_es_admin_o_lider()
returns boolean
language sql stable
as $$
  select coalesce(fn_rol_actual() in ('admin', 'lider_do'), false);
$$;

-- ── Adjuntar al expediente: hereda el NULL de puede_actuar ──────────────────
-- La 0076 ya hizo que fn_expediente_puede_actuar conteste false. Se blinda
-- igual aquí para que esta función sea correcta por sí sola y no dependa del
-- orden en que se apliquen las migraciones.
create or replace function fn_expediente_puede_adjuntar(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_carpeta text; v_doc expediente_disciplinario%rowtype;
begin
  v_carpeta := split_part(p_path, '/', 1);
  if v_carpeta !~ '^[0-9a-fA-F-]{36}$' then return false; end if;
  select * into v_doc from expediente_disciplinario where id = v_carpeta::uuid;
  if not found then return false; end if;
  -- Solo se adjunta el cargo de un documento ya firmado: antes de firmar no
  -- hay nada que la persona haya podido recibir.
  if v_doc.estado not in ('firmado', 'entregado') then return false; end if;
  return coalesce(fn_expediente_puede_actuar(v_doc.persona_id, v_doc.nivel), false);
end;
$$;

-- ── El guard compuesto de datos personales ──────────────────────────────────
-- Aquí el coalesce de la raíz no alcanza: las otras dos ramas comparan UUIDs
-- (`p_persona_id = fn_persona_actual_id()`), y comparar contra NULL da NULL.
-- `false or NULL or NULL` sigue siendo NULL. Por eso la condición entera se
-- evalúa con `is not true`: la única respuesta que abre la puerta es un TRUE
-- explícito.
--
-- Se conserva el resto del cuerpo tal cual estaba en la 0061.
create or replace function fn_set_datos_personales(
  p_persona_id uuid,
  p_nombre_dni text default null, p_fecha_nacimiento date default null, p_estado_civil text default null,
  p_direccion text default null, p_celular text default null,
  p_entidad_bancaria text default null, p_numero_cuenta text default null,
  p_grado_instruccion text default null, p_hijos_menores boolean default null,
  p_foto_dni_url text default null, p_foto_personal_url text default null, p_foto_profesional_url text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if (fn_es_admin_o_lider()
      or p_persona_id = fn_persona_actual_id()
      or (fn_rol_actual() = 'supervisor_sede'
          and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona())
     ) is not true then
    raise exception 'Sin permiso para editar los datos personales de esta persona.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;
  insert into datos_personales as dp (
    persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular,
    entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores,
    foto_dni_url, foto_personal_url, foto_profesional_url, actualizado_por, actualizado_at)
  values (
    p_persona_id, p_nombre_dni, p_fecha_nacimiento, p_estado_civil, p_direccion, p_celular,
    p_entidad_bancaria, p_numero_cuenta, p_grado_instruccion, p_hijos_menores,
    p_foto_dni_url, p_foto_personal_url, p_foto_profesional_url, fn_persona_actual_id(), now())
  -- Cuerpo IDÉNTICO al de la 0061: esta migración cambia el permiso, nada más.
  -- (Un campo enviado en null se limpia a propósito — así estaba y así queda;
  -- cambiarlo a "null preserva" sería otra decisión y va en otra migración.)
  on conflict (persona_id) do update set
    nombre_dni = excluded.nombre_dni, fecha_nacimiento = excluded.fecha_nacimiento,
    estado_civil = excluded.estado_civil, direccion = excluded.direccion, celular = excluded.celular,
    entidad_bancaria = excluded.entidad_bancaria, numero_cuenta = excluded.numero_cuenta,
    grado_instruccion = excluded.grado_instruccion, hijos_menores = excluded.hijos_menores,
    foto_dni_url = excluded.foto_dni_url, foto_personal_url = excluded.foto_personal_url,
    foto_profesional_url = excluded.foto_profesional_url,
    actualizado_por = fn_persona_actual_id(), actualizado_at = now();
end;
$$;

revoke execute on function fn_set_datos_personales(uuid, text, date, text, text, text, text, text, text, boolean, text, text, text) from public, anon;
grant  execute on function fn_set_datos_personales(uuid, text, date, text, text, text, text, text, text, boolean, text, text, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre) values (78, 'guards_no_fallan_abiertos')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
