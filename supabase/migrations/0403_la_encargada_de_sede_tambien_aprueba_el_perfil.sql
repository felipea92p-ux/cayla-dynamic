-- ============================================================================
-- 0403 — La encargada de sede también aprueba solicitudes de perfil
-- ============================================================================
--
-- QUÉ PROMETE
--   Hasta hoy, solo Desarrollo Organizacional (admin/lider_do, ver
--   fn_es_admin_o_lider en la 0078) podía ver y resolver una solicitud de
--   cambio de perfil (0399). Esta migración abre esa puerta también a la
--   encargada de sede (supervisor_sede) — pero SOLO sobre su propio equipo,
--   el mismo alcance que ya tiene para editar la ficha directa desde
--   /admin/datos-personales (fn_set_datos_personales, también en la 0399).
--   Se pidió al construir /mio/editar: la persona propone el cambio, y quien
--   lo aprueba puede ser el admin o quien está a cargo de su sede — no
--   siempre tiene que subir hasta DO.
--
-- QUÉ ASUME
--   0399 aplicada (catalogo_campos_perfil, solicitudes_cambio_perfil,
--   fn_solicitudes_perfil_pendientes, fn_resolver_solicitud_perfil, el bucket
--   `solicitudes-perfil` y su política de lectura). fn_es_admin_o_lider,
--   fn_rol_actual, fn_sede_actual_persona, fn_persona_actual_id (todas de
--   antes de la 0399).
--
-- QUÉ NO HACE
--   - No le abre a la encargada nada de identidad general (`puedeVerIdentidad`
--     sigue siendo solo DO en el resto del sistema): esto es estrictamente
--     "puede resolver — y por eso, leer — las solicitudes de SU equipo",
--     nunca la ficha completa de alguien de otra sede.
--   - No cambia quién puede CREAR una solicitud (fn_crear_solicitud_perfil):
--     eso sigue siendo cada quien sobre sí misma, sin tocar.
--   - No cambia fn_solicitud_perfil_puede_escribir (subir/actualizar/borrar
--     el documento adjunto): esa función sigue siendo "admin/lider o el dueño
--     de la carpeta". La encargada no sube ni borra documentos ajenos, solo
--     los lee para poder aprobar con criterio — de ahí la función nueva.
--
-- CÓMO SE REVIERTE
--   drop policy if exists solicitud_perfil_select on storage.objects;
--   create policy solicitud_perfil_select on storage.objects
--     for select to authenticated
--     using (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_escribir(name));
--   drop function if exists fn_solicitud_perfil_puede_leer(text);
--   -- y volver a pegar fn_solicitudes_perfil_pendientes / fn_resolver_solicitud_perfil
--   -- tal como quedaron en la 0399 (cuerpos completos ahí).
--
-- md5 de partida — POSTGRES LOCAL, no producción (2026-09-08). Esta sesión no
-- tiene acceso al SQL Editor: antes de pegar, correr donde-vive.sh contra
-- producción y confirmar que coincide (o declarar el de producción si solo
-- difiere en comentarios) — regla no negociable de este repo.
--   fn_solicitudes_perfil_pendientes: 4882a874fcf823e29b977ac51acbee96
--   fn_resolver_solicitud_perfil:     b2f88d3ec735ec1cf5440af59e822c8b
-- ============================================================================


-- ── A · Quién ve la bandeja de pendientes: DO, o la encargada de su sede ───
create or replace function fn_solicitudes_perfil_pendientes()
returns table (
  id uuid, persona_id uuid, nombre text, sede text, campo text, etiqueta text,
  valor_anterior jsonb, valor_propuesto jsonb, rutas_adjuntas text[], creada_at timestamptz
)
language sql stable security definer set search_path = public as $fn$
  select s.id, s.persona_id, pe.nombres || ' ' || pe.apellidos, sd.codigo,
         s.campo, c.etiqueta, s.valor_anterior, s.valor_propuesto, s.rutas_adjuntas, s.creada_at
  from solicitudes_cambio_perfil s
  join personas pe on pe.id = s.persona_id
  join sedes sd on sd.id = pe.sede_base_id
  join catalogo_campos_perfil c on c.campo = s.campo
  where s.estado = 'pendiente'
    and (fn_es_admin_o_lider() is true
         or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  order by s.creada_at asc;
$fn$;
grant execute on function fn_solicitudes_perfil_pendientes() to authenticated;
revoke execute on function fn_solicitudes_perfil_pendientes() from public, anon;


-- ── B · Quién puede aprobar/rechazar: DO, o la encargada de esa sede ───────
create or replace function fn_resolver_solicitud_perfil(
  p_id      uuid,
  p_aprobar boolean,
  p_motivo  text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_s      solicitudes_cambio_perfil%rowtype;
  v_existe boolean;
  v_sede   uuid;
begin
  -- Se lee la solicitud Y la sede de quien la pidió ANTES de decidir el
  -- permiso — para que a quien no tiene permiso el mensaje sea siempre "sin
  -- permiso", nunca "no existe" ni "sí existe": eso dejaría probar ids de
  -- solicitudes ajenas por el mensaje de error. Van en DOS consultas, no una
  -- sola con join: Postgres no deja mezclar una variable `%rowtype` con otro
  -- destino en el mismo `select ... into` (SQLSTATE 42601). `v_existe` guarda
  -- el `found` de la primera antes de que la segunda lo pise.
  select * into v_s from solicitudes_cambio_perfil where id = p_id;
  v_existe := found;

  select sede_base_id into v_sede from personas where id = v_s.persona_id;

  if (fn_es_admin_o_lider() is true
      or (fn_rol_actual() = 'supervisor_sede' and v_sede = fn_sede_actual_persona())) is not true then
    raise exception 'Solo un administrador, líder de Desarrollo Organizacional o la encargada de esa sede puede resolver una solicitud de perfil.';
  end if;

  if not v_existe then
    raise exception 'Esa solicitud ya no existe.';
  end if;
  if v_s.estado <> 'pendiente' then
    raise exception 'Esa solicitud ya fue % — no se puede resolver dos veces.', v_s.estado;
  end if;

  if p_aprobar then
    perform fn_aplicar_cambio_perfil(p_id);
    update solicitudes_cambio_perfil
    set estado = 'aprobado', resuelta_at = now(), resuelta_por = fn_persona_actual_id(),
        motivo = nullif(trim(coalesce(p_motivo, '')), '')
    where id = p_id;
  else
    if coalesce(trim(p_motivo), '') = '' then
      raise exception 'Para rechazar hace falta decir por qué, aunque sea en una línea.';
    end if;
    update solicitudes_cambio_perfil
    set estado = 'rechazado', resuelta_at = now(), resuelta_por = fn_persona_actual_id(),
        motivo = trim(p_motivo)
    where id = p_id;
  end if;
end;
$fn$;
grant execute on function fn_resolver_solicitud_perfil(uuid, boolean, text) to authenticated;
revoke execute on function fn_resolver_solicitud_perfil(uuid, boolean, text) from public, anon;


-- ── C · Leer el documento adjunto para poder aprobar con criterio ─────────
-- Aparte de fn_solicitud_perfil_puede_escribir (que sigue siendo admin/lider
-- o el dueño): la encargada necesita ABRIR el certificado de su equipo para
-- decidir si aprueba, pero no subir, reemplazar ni borrar el de nadie.
create or replace function fn_solicitud_perfil_puede_leer(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_persona text;
begin
  if split_part(p_path, '/', 1) <> 'solicitud' then return false; end if;
  v_persona := split_part(p_path, '/', 2);
  if v_persona !~ '^[0-9a-fA-F-]{36}$' then return false; end if;

  if fn_es_admin_o_lider() is true then return true; end if;
  if v_persona::uuid = fn_persona_actual_id() then return true; end if;

  return fn_rol_actual() = 'supervisor_sede'
     and exists (
       select 1 from personas
       where id = v_persona::uuid and sede_base_id = fn_sede_actual_persona()
     );
end;
$$;

grant execute on function fn_solicitud_perfil_puede_leer(text) to authenticated;

drop policy if exists solicitud_perfil_select on storage.objects;
create policy solicitud_perfil_select on storage.objects
  for select to authenticated
  using (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_leer(name));


insert into migraciones_aplicadas (numero, nombre)
values (403, 'la_encargada_de_sede_tambien_aprueba_el_perfil')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_solicitudes_perfil_pendientes') as fn_pendientes,
  (select count(*) from pg_proc where proname = 'fn_resolver_solicitud_perfil') as fn_resolver,
  (select count(*) from pg_proc where proname = 'fn_solicitud_perfil_puede_leer') as fn_puede_leer,
  (select prosrc like '%supervisor_sede%' from pg_proc where proname = 'fn_resolver_solicitud_perfil') as ya_incluye_encargada;
