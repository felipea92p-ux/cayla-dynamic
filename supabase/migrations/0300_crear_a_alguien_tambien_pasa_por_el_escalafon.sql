-- ============================================================================
-- 0300 · CREAR A ALGUIEN TAMBIÉN PASA POR EL ESCALAFÓN
-- ============================================================================
--
-- QUÉ PROMETE
--   Que dar de alta a una persona nueva respete la misma regla que ya rige
--   cambiar el rol de alguien que ya existe (0295): quien no es admin nunca
--   puede dar un rol igual o superior al suyo.
--
-- EL DEFECTO, EN UNA LÍNEA
--   `fn_crear_persona` exige `fn_es_admin_o_lider()` para crear a alguien, y
--   después acepta CUALQUIERA de los cuatro roles para `p_rol` —incluido
--   'admin'— sin mirar quién los está dando. Es la misma vulnerabilidad que
--   la 0295/0296 cerraron para el ROL DE ALGUIEN QUE YA EXISTE, por la
--   puerta de crear a alguien que no existía: un lider_do podía dar de alta
--   una cuenta nueva directamente como Admin.
--
-- POR QUÉ ES UN CREATE OR REPLACE, Y NO UNA FUNCIÓN NUEVA
--   `fn_crear_persona` es la única puerta de alta del sistema —la llama
--   `apps/web/app/(admin)/admin/equipo/page.tsx` (crearPersona) y ninguna
--   otra pantalla—, así que corregirla in situ no cambia la firma ni obliga
--   a tocar el cliente.
--
-- EL MD5 DE PARTIDA, PEDIDO A PRODUCCIÓN ANTES DE ESCRIBIR ESTA MIGRACIÓN
--   (regla de la casa, costó la 0276 el 2026-08-20): `tal_cual` y
--   `sin_comentarios` idénticos, `b74c3530652abb56c9bc97101e4512d0` —
--   producción tiene exactamente el cuerpo de la 0022 (`0022_areas_catalogo.sql`),
--   comentarios incluidos. Se copia de ahí, sin adivinar.
--
-- EL AGREGADO ES EL MISMO DE fn_set_rol (0295)
--   El mismo rango de `packages/shared/src/escalafon.ts` (RANGO: admin=3,
--   lider_do=2, supervisor_sede=1, integrante=0), copiado a propósito por la
--   misma razón que ya explica la cabecera de la 0295: no se puede importar
--   ese archivo dentro de Postgres. Quien no es admin no puede dar un rol
--   igual o superior al suyo — la misma condición que hace imposible la
--   autopromoción también hace imposible crear un cómplice.
--
-- QUÉ NO CAMBIA
--   Las cinco validaciones que ya existían (guard de admin/líder, nombres y
--   apellidos, sede válida, rol dentro del catálogo, área activa, PIN
--   presente) siguen exactamente iguales, en el mismo orden. Solo se agrega
--   una comprobación más, después de confirmar que el rol pedido es uno de
--   los cuatro válidos y antes del insert.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar el cuerpo de la 0022 tal cual (arriba, en el md5 de
--   partida).
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final.
-- ============================================================================

create or replace function fn_crear_persona(
  p_nombres text,
  p_apellidos text,
  p_sede_base_id uuid,
  p_rol text,
  p_funcion text,
  p_email text,
  p_pin_hash text
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_yo_rol rol_usuario;
  v_yo_rango int;
  v_nuevo_rango int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede crear personas.';
  end if;
  if trim(coalesce(p_nombres, '')) = '' or trim(coalesce(p_apellidos, '')) = '' then
    raise exception 'Nombres y apellidos son obligatorios.';
  end if;
  if not exists (select 1 from sedes where id = p_sede_base_id) then
    raise exception 'Sede inválida.';
  end if;
  if p_rol is null or p_rol not in ('integrante', 'supervisor_sede', 'lider_do', 'admin') then
    raise exception 'Rol inválido: %', coalesce(p_rol, '(vacío)');
  end if;

  -- CAMBIO 0300 · el mismo escalafón que ya rige cambiar el rol de alguien
  -- que ya existe (fn_set_rol, 0295). Sin esto, un lider_do podía crear una
  -- cuenta NUEVA directamente como Admin, sin pasar por ninguna de las dos
  -- puertas que la 0295/0296 ya cerraron para una persona ya existente.
  select rol into v_yo_rol from personas where auth_user_id = auth.uid();
  v_yo_rango := case v_yo_rol
    when 'admin' then 3 when 'lider_do' then 2 when 'supervisor_sede' then 1 else 0 end;
  v_nuevo_rango := case p_rol
    when 'admin' then 3 when 'lider_do' then 2 when 'supervisor_sede' then 1 else 0 end;
  if v_yo_rol <> 'admin' and v_nuevo_rango >= v_yo_rango then
    raise exception 'No puedes crear una persona con un rol igual o superior al tuyo.';
  end if;

  if p_funcion is null or not exists (select 1 from areas where codigo = p_funcion and activa) then
    raise exception 'Área inválida o inactiva: %', coalesce(p_funcion, '(vacía)');
  end if;
  if p_pin_hash is null or p_pin_hash = '' then
    raise exception 'Falta el PIN.';
  end if;

  insert into personas (nombres, apellidos, sede_base_id, rol, funcion, email, pin_hash)
  values (
    trim(p_nombres), trim(p_apellidos), p_sede_base_id,
    p_rol::rol_usuario, p_funcion, nullif(trim(coalesce(p_email, '')), ''), p_pin_hash
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

grant execute on function fn_crear_persona(text, text, uuid, text, text, text, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (300, '0300_crear_a_alguien_tambien_pasa_por_el_escalafon')
on conflict (numero) do nothing;

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select
  (select prosrc like '%CAMBIO 0300%' from pg_proc where proname = 'fn_crear_persona')
    as el_escalafon_ya_esta_adentro,
  (select md5(prosrc) from pg_proc where proname = 'fn_crear_persona')
    as md5_nuevo;
