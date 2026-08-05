-- ============================================================================
-- 0151 — El tope de educación deja de estar al alcance de cualquiera
-- ============================================================================
--
-- QUÉ PROMETE
--   `topes_educacion_rango` solo la lee admin o líder de DO, y nadie la escribe
--   desde la aplicación. Y el candado que la usa la sigue viendo siempre, pase
--   quien pase por él.
--
-- QUÉ ASUME
--   · Los topes se cambian por migración o desde el SQL Editor, como el resto de
--     los parámetros que mueven plata. No hay pantalla que los edite.
--   · `fn_es_admin_o_lider()` no devuelve null desde la 0078.
--
-- POR QUÉ ASÍ, Y NO DE OTRA FORMA
--
--   1 · EL AGUJERO. `topes_educacion_rango` era la ÚNICA tabla del esquema sin
--   RLS, y además tenía INSERT, UPDATE y DELETE concedidos a `authenticated` —
--   el rol de cualquier sesión con login, incluida la cuenta del terminal de la
--   tienda, esa Mac mini encendida todo el día a la vista de todos.
--
--   Medido contra el Postgres local el 2026-08-05, en BEGIN … ROLLBACK:
--
--     · con el tope de S/200 puesto, una asignación de S/500 se RECHAZA;
--     · una sesión `authenticated` corre `delete from topes_educacion_rango`
--       y funciona;
--     · la misma asignación de S/500 se ACEPTA, sin una sola advertencia.
--
--   No hace falta poder escribir la asignación para hacer daño: basta con quitar
--   el techo y esperar a que alguien registre de buena fe un monto que la
--   política no permitía. El sistema ya no objeta, porque el criterio que servía
--   para objetar desapareció. Es el mismo agujero que cerró la 0090 —«cualquier
--   sesión con login, el terminal incluido»— reabierto por la 0132 al crear una
--   tabla nueva sin candado.
--
--   2 · POR QUÉ EL TRIGGER TAMBIÉN CAMBIA, Y POR QUÉ NO SE PUEDE HACER SOLO UNO.
--   `fn_educacion_respeta_el_tope` NO era security definer: leía la tabla con
--   los permisos de quien estuviera escribiendo. Y su primera regla es «si no
--   encuentro tope para este rango, dejo pasar» (falla abierto, a propósito,
--   para rangos sin techo cargado).
--
--   Activar RLS sin tocar el trigger habría hecho que el trigger dejara de VER
--   el tope y lo leyera como «no hay tope». El candado se habría apagado solo,
--   en silencio, el día de la migración de seguridad. Pasando a security definer,
--   «no hay tope configurado» y «no tengo permiso para verlo» dejan de ser el
--   mismo síntoma: el segundo ya no puede ocurrir.
--
-- CÓMO SE REVIERTE
--   alter table topes_educacion_rango disable row level security;
--   grant select, insert, update, delete on topes_educacion_rango to authenticated;
--   drop policy if exists topes_educacion_lectura_admin on topes_educacion_rango;
--   y volver a crear fn_educacion_respeta_el_tope sin `security definer`
--   (su cuerpo no cambia en esta migración, solo esa cláusula).
--
-- NOTA DE NUMERACIÓN
--   Es la 0151 y no la 0149 porque la 0149 y la 0150 ya están tomadas por la
--   rama que trae la educación con todas sus reglas (commit 4aa2d12), aplicadas
--   en el Postgres local pero todavía sin fusionar a `main`.
-- ============================================================================

-- ── 1 · La tabla bajo llave ─────────────────────────────────────────────────
-- Misma forma que la 0115 usó con `tasas_pension`, que era la anterior única
-- tabla sin proteger. Dos partes distintas del sistema resolviendo el mismo
-- problema de dos maneras es una de las dos mal.
alter table topes_educacion_rango enable row level security;

revoke all on topes_educacion_rango from authenticated, anon;

drop policy if exists topes_educacion_lectura_admin on topes_educacion_rango;
create policy topes_educacion_lectura_admin on topes_educacion_rango
  for select using (fn_es_admin_o_lider());

grant select on topes_educacion_rango to authenticated;

comment on table topes_educacion_rango is
  'Techo mensual de la asignación por educación, por rango. Solo lectura para admin '
  'o líder de DO (0151); la escritura va por migración o SQL Editor. Antes de la 0151 '
  'era la única tabla sin RLS y con permiso de escritura para cualquier sesión con '
  'login: borrar una fila apagaba el techo de ese rango sin dejar rastro, porque '
  'fn_educacion_respeta_el_tope lee «sin tope» como «sin límite».';

-- ── 2 · Y el candado deja de depender de quién escribe ──────────────────────
-- Mismo cuerpo que dejó la 0149. Lo único que cambia es `security definer`: sin
-- eso, el RLS de arriba dejaría al trigger sin ver la tabla, y un candado que no
-- ve su límite no es un candado.
create or replace function public.fn_educacion_respeta_el_tope()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rango text;
  v_tope  numeric;
  v_suma  numeric;
begin
  select a.rango into v_rango
    from asignaciones_salario a
   where a.persona_id = new.persona_id
     and a.vigente_hasta is null
   order by a.vigente_desde desc
   limit 1;

  if v_rango is null then
    return new;  -- sin rango vigente no hay techo que aplicar
  end if;

  select t.tope_mensual into v_tope
    from topes_educacion_rango t
   where t.rango = v_rango;

  if v_tope is null then
    return new;  -- rango sin techo cargado: falla abierto a propósito
  end if;

  -- La suma, no la fila. Se cuentan las asignaciones de esa persona cuya
  -- vigencia SE SOLAPA con la de la fila que entra: dos cursos en meses
  -- distintos no compiten por el mismo techo, dos cursos en el mismo mes sí.
  -- Se excluye la propia fila para que corregir no se sume a sí misma.
  select coalesce(sum(a.monto), 0) into v_suma
    from asignaciones_educacion a
   where a.persona_id   = new.persona_id
     and a.id          <> new.id
     and a.vigente_desde <= new.vigente_hasta
     and a.vigente_hasta >= new.vigente_desde;

  if v_suma + new.monto > v_tope then
    raise exception
      'La suma de las asignaciones por educación de esta persona (S/%) supera el tope '
      'del rango % (S/%). Ya tiene S/% vigente en esas fechas. Cierra la otra asignación, '
      'ajusta el monto, o sube el tope en topes_educacion_rango si la política cambió.',
      to_char(v_suma + new.monto, 'FM999999.00'), v_rango,
      to_char(v_tope, 'FM999999.00'), to_char(v_suma, 'FM999999.00');
  end if;

  return new;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (151, 'el_tope_de_educacion_bajo_llave')
on conflict (numero) do nothing;
