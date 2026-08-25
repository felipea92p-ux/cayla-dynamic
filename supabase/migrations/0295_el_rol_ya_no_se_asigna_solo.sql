-- ============================================================================
-- 0295 · EL ROL YA NO SE ASIGNA SOLO
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cambiar el rol de una persona pase siempre por el escalafón —quien no
--   es admin nunca puede dar un rol igual o superior al suyo—, sea cual sea la
--   pantalla o la ruta que lo pida. Y que quede un rastro: hoy un cambio de
--   rol no deja ninguna huella en ningún lado.
--
-- EL DEFECTO, EN UNA LÍNEA
--   La pantalla de Equipo escribe `rol` directo con un `update` de PostgREST.
--   La política de UPDATE sobre `personas` («personas_update_admin_lider»)
--   solo exige `fn_es_admin_o_lider()` — nada sobre CUÁL rol se está dando ni
--   sobre a QUIÉN. Con eso, cualquiera con acceso a Desarrollo Organizacional
--   puede entrar a su propia ficha, abrir el desplegable de Rol —que ofrece
--   «Admin» igual que ofrece «Integrante»— y guardarse a sí misma como Admin.
--   Sin autorización de nadie más y sin dejar rastro.
--
-- POR QUÉ NO ES SOLO UN BOTÓN MAL PUESTO
--   Ya existe un camino que sí controla esto: `/api/admin/cuentas` con la
--   acción «promover» usa `puedeActuarSobre` de `escalafon.ts`. Pero esa ruta
--   solo cubre UNA transición fija (integrante → supervisor_sede) y su propio
--   comentario cuenta el incidente que la hizo así: «El rol del objetivo se
--   leía y no se usaba, así que "promover" servía igual para DEGRADAR: con el
--   id de un admin lo dejaba como encargada.» El problema de fondo nunca fue
--   «solo se promueve a un integrante» — fue que la acción nunca miraba QUÉ
--   rol nuevo estaba dando. Poner esa misma regla estrecha en la base habría
--   repetido el defecto con otro nombre.
--
-- EL DISEÑO: LA REGLA GENERAL DE ESCALAFON.TS, NO EL PARCHE DE UNA RUTA
--   Dos condiciones, y las dos tienen que cumplirse:
--     (1) Alcanzar al OBJETIVO en su rol de HOY — la misma aritmética de
--         `puedeActuarSobre`: admin alcanza a cualquiera (incluido otro
--         admin, a propósito: si no, dos administradores podrían quedar
--         mutuamente bloqueados el día que uno pierda su clave); cualquier
--         otro rol solo alcanza a quien esté ESTRICTAMENTE por debajo.
--     (2) El rol NUEVO tiene que quedar estrictamente por debajo de quien lo
--         da — salvo que quien lo da sea admin, que puede dar cualquier rol,
--         incluido el suyo propio.
--   La condición (2) es la que faltaba en el incidente de arriba, y es la que
--   hace imposible la autopromoción: nadie puede dar un rol igual o superior
--   al que ya tiene, así que ni siquiera necesita mirar «a quién» — un lider_do
--   que se apunta a sí misma como objetivo choca con la condición (1) igual
--   (2 no es estrictamente mayor que 2), pero aunque no chocara, chocaría con
--   la (2).
--
--   El rango es el MISMO de `packages/shared/src/escalafon.ts` (RANGO):
--   admin=3, lider_do=2, supervisor_sede=1, integrante=0. No se puede
--   importar ese archivo dentro de Postgres, así que esta migración lo copia
--   a propósito — es la misma razón por la que existe `escalafon.ts`: una
--   sola función que las reglas consultan, y ahora hay dos «una sola
--   función», una por cada lado del sistema, y las dos dicen lo mismo.
--
-- EL RASTRO
--   Mismo patrón que `fn_set_tipo_vinculo` (0119): un cambio de rol entra a
--   `correcciones_auditoria` con `campo_modificado = 'personas.rol'`, el
--   valor de antes, el de después y quién lo hizo. Hoy esto es la mitad del
--   hallazgo: «no hay rastro» es tan grave como «cualquiera puede hacerlo».
--
-- QUÉ NO CAMBIA
--   La pantalla de Equipo sigue teniendo el mismo desplegable con los cuatro
--   roles — la sanción de qué transición vale ya no depende de qué pantalla
--   la pida, sino de esta función. `apps/web/app/(admin)/admin/equipo/page.tsx`
--   deja de mandar `rol` en su `update` directo y llama a esta RPC solo si el
--   valor cambió, con el mismo patrón "dirty-check" que ya usan función,
--   cargo, con_hijos, fecha de ingreso, etc. en esa misma pantalla.
--
-- CÓMO SE REVIERTE
--   `drop function fn_set_rol(uuid, rol_usuario);` y devolver `rol` al
--   `update` de `equipo/page.tsx`. La policy de UPDATE no se toca en esta
--   migración —sigue permitiendo escribir la columna directo—, así que
--   revertir esto por sí solo no reabre nada que esta migración no haya
--   cerrado: lo que de verdad cierra el camino directo es la migración
--   siguiente, que revoca el permiso de columna.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final.
-- ============================================================================

create or replace function fn_set_rol(p_persona_id uuid, p_nuevo_rol rol_usuario)
returns void
language plpgsql security definer as $function$
declare
  v_yo_rol       rol_usuario;
  v_yo_rango     int;
  v_objetivo_rol rol_usuario;
  v_objetivo_rango int;
  v_nuevo_rango  int;
  v_quien        uuid;
begin
  -- Guard null-safe, como manda el estándar del repo: un null no pasa como
  -- autorizado. Es la misma puerta de entrada que ya usan las otras `fn_set_*`
  -- de esta pantalla — lo que sigue debajo es lo que AÑADE esta función.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el rol de alguien.';
  end if;

  select rol into v_yo_rol from personas where auth_user_id = auth.uid();
  if v_yo_rol is null then
    raise exception 'No puedo identificar tu rol, así que no puedo autorizar el cambio.';
  end if;

  select rol into v_objetivo_rol from personas where id = p_persona_id;
  if not found then
    raise exception 'Persona inválida.';
  end if;

  if v_objetivo_rol = p_nuevo_rol then
    return;   -- nada que hacer, y así no se ensucia la auditoría
  end if;

  -- El mismo rango de escalafon.ts (RANGO), copiado a propósito: ver la
  -- cabecera de esta migración.
  v_yo_rango := case v_yo_rol
    when 'admin' then 3 when 'lider_do' then 2 when 'supervisor_sede' then 1 else 0 end;
  v_objetivo_rango := case v_objetivo_rol
    when 'admin' then 3 when 'lider_do' then 2 when 'supervisor_sede' then 1 else 0 end;
  v_nuevo_rango := case p_nuevo_rol
    when 'admin' then 3 when 'lider_do' then 2 when 'supervisor_sede' then 1 else 0 end;

  -- (1) Alcanzar al objetivo en su rol de HOY.
  if not (v_yo_rol = 'admin' or v_yo_rango > v_objetivo_rango) then
    raise exception 'No puedes cambiar el rol de esa persona.';
  end if;

  -- (2) El rol nuevo tiene que quedar estrictamente por debajo del tuyo,
  -- salvo que seas admin. Es la condición que faltaba en el incidente que
  -- describe la cabecera, y la que hace imposible la autopromoción.
  if v_yo_rol <> 'admin' and v_nuevo_rango >= v_yo_rango then
    raise exception 'No puedes asignar un rol igual o superior al tuyo.';
  end if;

  update personas set rol = p_nuevo_rol where id = p_persona_id;

  -- Rastro obligatorio. Un cambio que puede llegar a dar acceso a todos los
  -- sueldos y al padrón completo no puede ser invisible — es exactamente lo
  -- que faltaba en el incidente que describe la cabecera.
  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.rol', v_objetivo_rol, p_nuevo_rol,
          'Cambio de rol desde /admin/equipo.', v_quien);
end;
$function$;

grant execute on function fn_set_rol(uuid, rol_usuario) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (295, '0295_el_rol_ya_no_se_asigna_solo')
on conflict (numero) do nothing;

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_set_rol') as la_funcion_existe,
  (select prosecdef from pg_proc where proname = 'fn_set_rol') as es_security_definer,
  has_function_privilege('authenticated', 'fn_set_rol(uuid, rol_usuario)', 'EXECUTE') as ejecutable_por_authenticated;
