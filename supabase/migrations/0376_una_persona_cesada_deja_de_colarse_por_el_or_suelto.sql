-- ============================================================================
-- 0376_una_persona_cesada_deja_de_colarse_por_el_or_suelto.sql
-- ============================================================================
-- QUÉ ARREGLA. Dos funciones SECURITY DEFINER —fn_vacaciones_saldo (0357) y
-- fn_marca_apartada_resolver (0304)— arman su guard como
--   «fn_es_admin_o_lider() is not true and ... and not (fn_rol_actual() = ...)»
-- en vez de envolver TODO el OR en un único «is not true», que es el patrón
-- correcto — usado en 0126 y en la propia 0078, y prohibido de romper por
-- CLAUDE.md. Es la sexta-y-séptima vez que esta forma entra al repo.
--
-- POR QUÉ ES UN AGUJERO NUEVO, ABIERTO POR LA 0374, en tres pasos:
--   · Antes de la 0374, fn_rol_actual() de una persona CESADA seguía
--     devolviendo su rol real (0003/0005 no filtraban por estado). Si esa
--     persona no era supervisor_sede, «fn_rol_actual() = 'supervisor_sede'»
--     daba FALSE — determinista, el guard bloqueaba.
--   · La 0374 reescribió fn_rol_actual() para devolver NULL cuando
--     estado <> 'activo' — correcto para su propio objetivo (que un cesado
--     no cuente como si tuviera rol). Pero para CUALQUIER persona inactiva,
--     ese término ahora es NULL, sin importar qué rol tuvo.
--   · fn_cesar_persona (vigente en 0327, líneas ~2230-2236) nunca borra
--     sede_base_id al cesar. Con sede igual: «null and true» = null;
--     «not(null)» = null; la condición compuesta completa da NULL. Un
--     «if null then raise exception» en PL/pgSQL NO DISPARA — la función
--     sigue de largo, como si la operación estuviera autorizada.
--
-- REPRODUCIDO, sin tocar ninguna tabla, contra el Postgres local: con
-- r := null (fn_rol_actual() de una cesada) y sede_igual := true,
--   select (true and not(r = 'supervisor_sede' and sede_igual));   -- null
--   do $$ begin if (null::boolean) then raise exception 'no debería'; end if; end $$;
-- no lanza excepción — confirma el modo de fallo exacto que la propia 0078
-- documentó para justificar la forma «is not true» en primer lugar.
--
-- EFECTO CONCRETO. Cualquier persona cesada, mientras su sesión de Supabase
-- Auth siga viva (nadie la fuerza a cerrar al cesar — la propia 0374 lo dice:
-- «sin esperar a que alguien le resetee la clave a mano»), puede hoy:
--   (a) leer con fn_vacaciones_saldo el saldo y las fechas de vacaciones de
--       cualquier persona ACTIVA de su antigua sede, y
--   (b) resolver con fn_marca_apartada_resolver una marca apartada de un
--       excolega de su antigua sede — con 'repuesta' esto llama a
--       fn_registrar_marcaje y ESCRIBE un marcaje real que alimenta la
--       jornada y el pago de otra persona.
-- No es un escenario de "identidad rara": es cualquiera que alguna vez
-- trabajó en un sitio y fue cesado, población nada hipotética con rotación
-- real en ~30 personas.
--
-- QUÉ NO CAMBIA. Ni un carácter de ninguna de las dos funciones salvo la
-- forma del guard — misma pregunta, misma respuesta para quien ya estaba
-- autorizado legítimamente. Los cuerpos de abajo son los vigentes de la 0357
-- y la 0304 con un solo reemplazo aplicado.
--
-- MD5 DE PARTIDA — medido en esta Mac (Postgres local), ANTES de escribir
-- este cambio. Como manda la casa, esto NO reemplaza pedirlo a producción:
-- se vuelve a pedir en el mensaje en que se entregue este SQL, no en este.
--
--   fn_vacaciones_saldo         tal_cual = d466d0d950d9978fd8d401eef0fae15d
--   fn_marca_apartada_resolver  tal_cual = 98cc555d1ef6ee873f20e062edd152f6
--                        sin_comentarios = 62b452d393acab060428634376d47b41
--
--   select p.proname, md5(p.prosrc) as tal_cual,
--          md5(array_to_string(array(
--            select regexp_replace(l, '[[:space:]]*--.*$', '')
--            from unnest(string_to_array(p.prosrc, chr(10))) as l
--            where btrim(l) not like '--%'
--          ), chr(10)))                 as sin_comentarios
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname in ('fn_vacaciones_saldo', 'fn_marca_apartada_resolver');
--
-- CÓMO SE REVIERTE. Restaurar las dos funciones desde la 0357 y la 0304 tal
-- cual — pero no se debería: eso reabre el agujero para cualquier persona
-- cesada con sesión viva.
-- ============================================================================

-- ── 1 · fn_vacaciones_saldo ──────────────────────────────────────────────
create or replace function fn_vacaciones_saldo(p_persona_id uuid, p_as_of date default null)
returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  v_p personas%rowtype;
begin
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  -- CAMBIO 0376 — todo el OR envuelto en un único "is not true": si el
  -- término de supervisor_sede da NULL (rol de una persona cesada, desde la
  -- 0374), el OR completo da NULL o FALSE — nunca deja pasar por accidente.
  if (
    fn_es_admin_o_lider()
    or p_persona_id = coalesce(fn_persona_actual_id(), '00000000-0000-0000-0000-000000000000'::uuid)
    or (fn_rol_actual() = 'supervisor_sede'::rol_usuario
        and v_p.sede_base_id = fn_sede_actual_persona())
  ) is not true then
    raise exception 'No puedes ver el saldo de vacaciones de otra persona.';
  end if;

  return fn_vacaciones_saldo_interno(p_persona_id, p_as_of);
end;
$fn$;
grant execute on function fn_vacaciones_saldo(uuid, date) to authenticated;
revoke execute on function fn_vacaciones_saldo(uuid, date) from public, anon;


-- ── 2 · fn_marca_apartada_resolver ───────────────────────────────────────
create or replace function fn_marca_apartada_resolver(
  p_id         uuid,
  p_resolucion text,
  p_motivo     text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m   marcas_apartadas%rowtype;
  v_p   personas%rowtype;
  v_yo  uuid := fn_persona_actual_id();
begin
  select * into v_m from marcas_apartadas where id = p_id;
  if not found then raise exception 'Esa marca apartada no existe.'; end if;

  select * into v_p from personas where id = v_m.persona_id;

  -- CAMBIO 0376 — mismo arreglo que fn_vacaciones_saldo arriba: el OR
  -- completo envuelto en un único "is not true".
  if (
    fn_es_admin_o_lider()
    or (fn_rol_actual() = 'supervisor_sede'::rol_usuario
        and v_p.sede_base_id = fn_sede_actual_persona())
  ) is not true then
    raise exception 'No puedes resolver una marca apartada de otra sede.';
  end if;

  if v_m.resuelta_at is not null then
    raise exception 'Esa marca ya se resolvió el % como «%».',
      to_char(v_m.resuelta_at, 'DD/MM/YYYY'), v_m.resolucion;
  end if;

  if p_resolucion not in ('repuesta', 'improcedente') then
    raise exception 'La resolución es «repuesta» o «improcedente» (llegó «%»).', p_resolucion;
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué. Esto decide si un día de trabajo queda registrado o no.';
  end if;

  if p_resolucion = 'repuesta' then
    perform fn_registrar_marcaje(
      v_m.persona_id, v_m.tipo, v_m.timestamp_cliente, v_m.client_uuid,
      'admin_correccion'::origen_marca, null, v_p.sede_base_id, v_m.motivo_otro);
  end if;

  update marcas_apartadas
     set resuelta_at  = now(),
         resuelta_por = v_yo,
         resolucion   = p_resolucion,
         motivo       = trim(p_motivo)
   where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_m.persona_id, 'marca_apartada',
     v_m.tipo::text || ' del ' || to_char(v_m.timestamp_cliente, 'DD/MM/YYYY HH24:MI')
       || coalesce(' · ' || v_m.ultimo_error, ''),
     p_resolucion, coalesce(v_yo, v_m.persona_id), trim(p_motivo));

  return jsonb_build_object(
    'resolucion', p_resolucion,
    'persona', v_p.nombres || ' ' || v_p.apellidos,
    'marca', to_char(v_m.timestamp_cliente, 'DD/MM/YYYY HH24:MI'));
end;
$$;
grant execute on function fn_marca_apartada_resolver(uuid, text, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (376, '0376_una_persona_cesada_deja_de_colarse_por_el_or_suelto')
on conflict (numero) do nothing;
