-- ============================================================================
-- 0119 — El tipo de vínculo se puede elegir desde la pantalla.
--
-- QUÉ DESBLOQUEA. La 0085 creó `personas.tipo_vinculo` con sus cuatro valores
-- ('planilla','prueba','rxh','no_trabajador') y su default 'planilla'. La 0117
-- hizo que la movilidad y el EsSalud dejen de calcularse para quien no está en
-- planilla. Pero el campo NO aparecía en ninguna línea del frontend, así que
-- todos quedaban en el default y las dos migraciones no cambiaban nada para
-- nadie. Esta migración cierra ese hueco.
--
-- POR QUÉ UN RPC Y NO UNA COLUMNA EXPUESTA. Es la convención del repo: `funcion`
-- y `con_hijos` también viajan por fn_set_*, porque el schema cache de PostgREST
-- no expone esas columnas. Se sigue el molde exacto de fn_set_con_hijos.
--
-- ── ESTE CAMBIO MUEVE PLATA, Y HACIA ABAJO ──────────────────────────────────
--
-- Pasar a alguien de 'planilla' a 'rxh' o 'no_trabajador' tiene tres efectos
-- inmediatos, y conviene tenerlos escritos porque no son obvios en la pantalla:
--
--   1. Deja de acumular gratificación, CTS y vacaciones. Lo decide
--      fn_devenga_beneficios, que devuelve `tipo = 'planilla'`, y lo consultan
--      fn_cts_trunca, fn_grati_trunca y fn_vacaciones_truncas.
--   2. Deja de recibir movilidad y de generar EsSalud (0117).
--   3. Sale del conteo de asistencia y disciplina, que es el punto del diseño:
--      registrar horas para pagar es medir un resultado; generar tardanzas y
--      expedientes es fiscalizar una conducta, y eso es prueba de subordinación
--      (art. 9 del D.S. 003-97-TR).
--
-- Por eso la función DEJA RASTRO: cada cambio se anota en correcciones_auditoria
-- con quién lo hizo, el valor anterior y el nuevo. Sin eso, un cambio que apaga
-- la acumulación de beneficios de una persona sería invisible después.
--
-- Y por eso NO se permite cambiar el vínculo de alguien ya cesado: su
-- liquidación se calculó con el vínculo que tenía, y cambiarlo después
-- reescribiría el criterio de un pago hecho.
--
-- ── LO QUE NO HACE ──────────────────────────────────────────────────────────
-- No toca el pago por horas de nadie. Un RxH sigue cobrando sus horas igual, que
-- es la decisión de la 0085 y se respeta.
--
-- CÓMO SE REVIERTE: drop function fn_set_tipo_vinculo, y restaurar
-- fn_personas_funciones sin los dos campos nuevos.
-- ============================================================================

create or replace function fn_set_tipo_vinculo(p_persona_id uuid, p_tipo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  text;
  v_estado text;
  v_quien  uuid;
begin
  -- Guard null-safe, como manda el estándar del repo: un null no pasa como
  -- autorizado.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el tipo de vínculo.';
  end if;

  if p_tipo is null or p_tipo not in ('planilla', 'prueba', 'rxh', 'no_trabajador') then
    raise exception 'Tipo de vínculo inválido: %. Los válidos son planilla, prueba, rxh y no_trabajador.', p_tipo;
  end if;

  select tipo_vinculo, estado into v_antes, v_estado
  from personas where id = p_persona_id;

  if not found then
    raise exception 'Persona inválida.';
  end if;

  -- El vínculo de alguien ya cesado no se toca: su liquidación se calculó con el
  -- vínculo que tenía, y cambiarlo ahora reescribiría el criterio de un pago hecho.
  if v_estado = 'inactivo' then
    raise exception 'No se puede cambiar el vínculo de una persona ya cesada: su liquidación se calculó con el vínculo anterior.';
  end if;

  if v_antes = p_tipo then
    return;   -- nada que hacer, y así no se ensucia la auditoría
  end if;

  update personas set tipo_vinculo = p_tipo where id = p_persona_id;

  -- Rastro obligatorio. Un cambio que apaga la acumulación de beneficios de una
  -- persona no puede ser invisible.
  --
  -- corregido_por es NOT NULL. No debería poder ser nulo acá —el guard de arriba
  -- ya exigió un rol, y el rol se resuelve por la persona ligada a auth.uid()—
  -- pero se comprueba igual: preferimos abortar antes que escribir un cambio de
  -- plata sin dueño.
  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.tipo_vinculo', v_antes, p_tipo,
          case
            when p_tipo = 'planilla'
              then 'Pasa a planilla: vuelve a acumular gratificación, CTS y vacaciones, y a recibir movilidad y EsSalud.'
            when p_tipo = 'prueba'
              then 'Periodo de prueba: se le mide asistencia y se le pagan sus horas, pero no acumula beneficios (decisión de Felipe registrada en la 0085).'
            when p_tipo = 'rxh'
              then 'Recibo por honorarios: deja de acumular beneficios, de recibir movilidad y de generar EsSalud. Tampoco se le mide disciplina.'
            else 'No trabajador: ni asistencia ni beneficios.'
          end,
          v_quien);
end;
$$;

comment on function fn_set_tipo_vinculo(uuid, text) is
  'Cambia el tipo de vínculo de una persona. Solo admin o líder. Deja rastro en '
  'correcciones_auditoria porque el cambio apaga o enciende la acumulación de '
  'beneficios, la movilidad y el EsSalud. No se permite sobre personas cesadas.';

-- ── El lado de lectura: exponer el vínculo a la pantalla ────────────────────
--
-- Se agrega tipo_vinculo y en_planilla al mismo objeto que ya devuelve funcion y
-- con_hijos. El resto de la función queda idéntico, incluida su cláusula where,
-- que es la que decide quién puede ver a quién.

create or replace function fn_personas_funciones()
returns jsonb
language sql
stable security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', p.id, 'funcion', p.funcion, 'con_hijos', p.con_hijos,
           'es_encargada_piso', p.es_encargada_piso,
           'visible_todas_sedes', p.visible_todas_sedes,
           'tipo_vinculo', p.tipo_vinculo,       -- CAMBIO 0119
           'en_planilla', p.en_planilla)), '[]'::jsonb)   -- CAMBIO 0119
  from personas p
  where
    fn_es_admin_o_lider()
    or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona())
    or p.auth_user_id = auth.uid()
    or (p.estado = 'activo'
        and fn_sede_actual_terminal() is not null
        and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true));
$$;

revoke all on function fn_set_tipo_vinculo(uuid, text) from public, anon;
grant execute on function fn_set_tipo_vinculo(uuid, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (119, 'el_tipo_de_vinculo_se_puede_elegir')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
begin
  raise notice '0119 · fn_set_tipo_vinculo lista. Valores: planilla, prueba, rxh, no_trabajador.';
  raise notice '0119 · reparto actual de personas activas:';
  raise notice '  %', (
    select coalesce(string_agg(t.tipo_vinculo || ': ' || t.n, '  ·  ' order by t.tipo_vinculo), '(sin personas)')
    from (select tipo_vinculo, count(*) as n from personas where estado = 'activo' group by tipo_vinculo) t
  );
  raise notice '0119 · OJO: mientras nadie se marque como rxh, la 0117 no cambia nada para nadie.';
end
$mig$;
