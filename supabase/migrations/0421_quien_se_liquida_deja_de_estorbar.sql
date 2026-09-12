-- ============================================================================
-- 0421 · Quien cesa deja de estorbar, pero no antes de liquidarse
-- ============================================================================
-- QUÉ PROMETE
--
--   `fn_persona_liquidada(persona_id)` devuelve `true` solo cuando esa persona
--   tiene una liquidación por cese ya pagada y NO anulada (`liquidacion_pagada`,
--   ver 0167 y 0251). Devuelve `false` para quien sigue activo, para quien
--   cesó y todavía no se le liquida, y para quien no existe.
--
--   Y `fn_personas_funciones()` (0020, vigente en 0324) suma esa misma
--   respuesta a lo que ya entrega por persona, bajo la clave `liquidada`. Es
--   el primer consumidor: Ausencias, Educación y Correcciones van a dejar de
--   mostrar sin filtro a quien ya se liquidó, y las tres necesitan la misma
--   respuesta a la misma pregunta.
--
-- QUÉ ASUME
--
--   Que "liquidada" vive enteramente en `liquidacion_pagada.anulada = false`
--   de la versión más reciente por persona — el mismo criterio que ya usa
--   `fn_liquidaciones_pendientes` (0251) para su columna `pagada`. No mira
--   `personas.estado`: el llamador decide si cruza los dos (activo, o cesado
--   pero aún sin liquidar → sigue visible; cesado Y liquidado → deja de
--   estorbar).
--
-- POR QUÉ SE ELIGIÓ ASÍ
--
--   `liquidacion_pagada` tiene RLS que solo deja leer a admin/líder o a la
--   propia persona (0167). Ausencias, Educación y Correcciones también las usa
--   la encargada de sede para su propio equipo, y ella no puede leer esa tabla
--   directo. Esta función expone solo un booleano —nada de montos, nada de
--   fecha— con SECURITY DEFINER, para no tener que abrirle la tabla entera.
--
--   Se sumó a `fn_personas_funciones()` en vez de a `fn_ausencias` y a
--   `fn_educacion_listar` por separado: las tres pantallas preguntan lo mismo,
--   y esta función ya es el lugar donde vive un hecho por persona que cruza
--   una RLS más estricta que la del que pregunta (`fecha_cese`/`motivo_cese`
--   ya viven acá desde la 0179). Copiarlo en cada RPC hubiera sido la misma
--   pregunta contestada tres veces — el error que este repositorio ya pagó con
--   `rol === "admin"` y con `"America/Lima"` sueltos por 35 y 32 pantallas.
--
-- CÓMO SE REVIERTE
--
--   drop function fn_persona_liquidada(uuid);
--   Y volver a pegar el cuerpo de `fn_personas_funciones` tal como quedó en la
--   0324 (sin la clave `liquidada`).
-- ============================================================================

create or replace function fn_persona_liquidada(p_persona_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $fn$
  select exists (
    select 1 from liquidacion_pagada lp
    where lp.persona_id = p_persona_id and lp.anulada is not true
  );
$fn$;

grant execute on function fn_persona_liquidada(uuid) to authenticated;
revoke execute on function fn_persona_liquidada(uuid) from public, anon;

create or replace function fn_personas_funciones()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', p.id, 'funcion', p.funcion, 'con_hijos', p.con_hijos,
           'es_encargada_piso', p.es_encargada_piso,
           'visible_todas_sedes', p.visible_todas_sedes,
           'tipo_vinculo', p.tipo_vinculo,
           'en_planilla', p.en_planilla,
           'practicante_modalidad', p.practicante_modalidad,
           'cargo', p.cargo,
           'fecha_cese', p.fecha_cese,
           'motivo_cese', case when fn_es_admin_o_lider() is not true
                               then null else p.motivo_cese end,
           -- CAMBIO 0421 · true solo si ya se le pagó la liquidación (y no está
           -- anulada). Para quien sigue activo, o cesó y aún no se liquida,
           -- da false — a propósito: todavía puede tener trabajo pendiente
           -- (una ausencia por registrar, un marcaje por corregir).
           'liquidada', (p.fecha_cese is not null and fn_persona_liquidada(p.id))
         )), '[]'::jsonb)
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

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (421, 'quien_se_liquida_deja_de_estorbar')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

do $$
begin
  raise notice '0421 · fn_persona_liquidada existe; fn_personas_funciones ya dice "liquidada" por persona.';
end $$;
