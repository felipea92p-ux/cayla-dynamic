-- ============================================================================
-- 0179 — La pantalla de Equipo dice cuándo y por qué se fue cada persona
-- ----------------------------------------------------------------------------
-- PROMETE:
--   1. Que `fn_personas_funciones` devuelva también `fecha_cese` y
--      `motivo_cese`, para que la pantalla de Equipo pueda mostrar por qué una
--      persona ya no está en vez de solo decir «inactivo».
--   2. Que el MOTIVO solo lo vea quien administra: admin y líder de Desarrollo
--      Organizacional. La FECHA sí la ve también la encargada de sede.
-- ASUME: la 0119, que es la última que definió esta función (comprobado con
--   `./scripts/donde-vive.sh fn_personas_funciones` — tiene 5 definiciones
--   repartidas y la vigente es la 0119, no la 0020 que la creó).
--
-- POR QUÉ POR AQUÍ Y NO CON UN `select` DIRECTO. La pantalla lee `personas` por
-- REST, pero el schema cache de PostgREST no expone todas sus columnas: por eso
-- existe esta función desde la 0020, que se llamó literalmente
-- «rpc_bypass_cache». Si `fecha_cese` se agregara al `select` de la pantalla y
-- PostgREST no la conociera, no fallaría ese campo: fallaría la consulta
-- ENTERA y la pantalla de Equipo se quedaría sin equipo. Se sigue el camino que
-- el sistema ya tiene resuelto en vez de abrir uno nuevo al lado.
--
-- POR QUÉ EL MOTIVO NO LO VE TODO EL MUNDO. «Despido» es un dato sensible de una
-- persona concreta. Hoy una encargada de sede ve a su equipo en esta pantalla,
-- incluido quién está inactivo; eso es operativo y está bien. Pero saber que a
-- alguien lo despidieron —frente a que renunció— no le hace falta para operar su
-- tienda, y una vez que se muestra ya no se puede des-mostrar. Se entrega el
-- mínimo: la fecha para todos los que ya veían la fila, el motivo solo para
-- quien lleva los expedientes. Si mañana hace falta ampliarlo, se amplía; al
-- revés cuesta mucho más.
--
-- No cambia ni una fila de datos, ni un cálculo, ni un permiso de escritura:
-- solo agrega dos campos a lo que esta función ya devolvía.
--
-- REVERTIR: correr el bloque `create or replace function fn_personas_funciones`
-- tal como está en `supabase/migrations/0119_el_tipo_de_vinculo_se_puede_elegir.sql`
-- y borrar la fila 179 de `migraciones_aplicadas`. La pantalla degrada sola: si
-- los campos no llegan, no pinta la línea.
-- ============================================================================

create or replace function fn_personas_funciones()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', p.id, 'funcion', p.funcion, 'con_hijos', p.con_hijos,
           'es_encargada_piso', p.es_encargada_piso,
           'visible_todas_sedes', p.visible_todas_sedes,
           'tipo_vinculo', p.tipo_vinculo,
           'en_planilla', p.en_planilla,
           -- CAMBIO 0179 · cuándo se fue: lo ve quien ya veía la fila.
           'fecha_cese', p.fecha_cese,
           -- CAMBIO 0179 · por qué se fue: solo administración. `is not true`
           -- y no `not (...)`, por el estándar del repo: un null no pasa como
           -- autorizado.
           'motivo_cese', case when fn_es_admin_o_lider() is not true
                               then null else p.motivo_cese end)), '[]'::jsonb)
  from personas p
  where
    fn_es_admin_o_lider()
    or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona())
    or p.auth_user_id = auth.uid()
    or (p.estado = 'activo'
        and fn_sede_actual_terminal() is not null
        and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true));
$$;

grant  execute on function fn_personas_funciones() to authenticated;
revoke execute on function fn_personas_funciones() from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (179, 'la_pantalla_de_equipo_dice_cuando_y_por_que_se_fue')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_falta text[];
begin
  -- Que los campos que la 0119 ya entregaba sigan estando: esta función la leen
  -- la pantalla de Equipo y el terminal, y perder uno en silencio dejaría a todo
  -- el equipo en el área por defecto.
  select array_agg(c) into v_falta from unnest(array[
    'persona_id','funcion','con_hijos','es_encargada_piso','visible_todas_sedes',
    'tipo_vinculo','en_planilla','fecha_cese','motivo_cese']) as c
   where position(c in pg_get_functiondef('fn_personas_funciones()'::regprocedure)) = 0;
  if v_falta is not null then
    raise exception '0179 · a fn_personas_funciones le faltan campos: %', array_to_string(v_falta, ', ');
  end if;
  raise notice '0179 · fn_personas_funciones entrega sus 7 campos de siempre + fecha_cese y motivo_cese.';
  raise notice '0179 · el motivo solo viaja para admin y lider DO; no cambia ningun dato ni calculo.';
end $mig$;
