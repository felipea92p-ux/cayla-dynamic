-- ============================================================================
-- 0324_la_practicante_dice_su_modalidad.sql
-- ============================================================================
-- QUÉ PROMETE
--
--   Agrega `personas.practicante_modalidad` ('preprofesional' | 'profesional'),
--   porque la Ley 28518 no da el mismo máximo de horas a las dos: 6h/día ·
--   30h/semana a una preprofesional, 8h/día · 48h/semana a una profesional
--   (art. 44). La 0322 creó la categoría 'practicante' pero no distinguía
--   cuál de las dos es — no había contra qué límite avisar.
--
--   Con esto, la pantalla de Horarios (apps/web/app/(admin)/admin/horarios)
--   puede avisar cuando el horario armado supera el máximo legal de ESA
--   persona, en vez de compararla contra la meta genérica de 45h/semana que
--   usa para el resto del equipo.
--
-- QUÉ ASUME
--   · La 0322, que creó `tipo_vinculo = 'practicante'`.
--   · Que el máximo se avisa, no se bloquea — mismo criterio que todo lo
--     demás en este sistema: «Dynamic avisa, nunca sanciona solo».
--
-- QUÉ NO HACE
--   · No fuerza a nadie a fijar la modalidad. Un practicante sin modalidad
--     definida es un estado válido y transitorio (igual que alguien sin
--     salario asignado): la pantalla lo dice, no lo bloquea ni lo adivina.
--   · No mide horas marcadas contra el máximo — eso es un aviso de
--     `fn_planilla_calcular` o de Incidencias, si algún día hace falta.
--     Esto solo avisa sobre el horario ARMADO, antes de que nadie marque.
--   · No toca ninguna función que mueva plata. `fn_planilla_calcular` no se
--     toca en esta migración.
--
-- CÓMO SE REVIERTE
--   Soltar los dos CHECK y la columna `practicante_modalidad`. Restaurar
--   `fn_set_tipo_vinculo` y `fn_personas_funciones` a como quedaron en la
--   0322 y la 0182 respectivamente. Ningún dato histórico se pierde: hoy
--   nadie tiene `tipo_vinculo = 'practicante'` en producción, así que la
--   columna nueva no tiene nada que perder al soltarse.
-- ============================================================================

-- ── 1. La columna, con sus dos CHECK ────────────────────────────────────────
alter table personas add column if not exists practicante_modalidad text;

comment on column personas.practicante_modalidad is
  'preprofesional | profesional | null (0324). Solo tiene sentido para tipo_vinculo=''practicante'' — decide el máximo legal de jornada semanal (30h / 48h, art. 44 Ley 28518) que avisa la pantalla de Horarios.';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'personas_practicante_modalidad_valida') then
    alter table personas add constraint personas_practicante_modalidad_valida
      check (practicante_modalidad is null or practicante_modalidad in ('preprofesional', 'profesional'));
  end if;

  -- Una modalidad solo tiene sentido para quien es practicante. `fn_set_tipo_vinculo`
  -- ya la limpia sola al mover a alguien a otro vínculo (más abajo), así que este
  -- CHECK nunca debería fallar por una escritura normal — es el candado, no el guía.
  if not exists (select 1 from pg_constraint where conname = 'personas_practicante_modalidad_coherente') then
    alter table personas add constraint personas_practicante_modalidad_coherente
      check (practicante_modalidad is null or tipo_vinculo = 'practicante');
  end if;
end $$;

-- ── 2. fn_set_tipo_vinculo limpia la modalidad al salir de 'practicante' ───
-- Copia exacta de la 0322 (la vigente — confirmado con donde-vive.sh), con un
-- solo cambio: el UPDATE ahora también limpia `practicante_modalidad` cuando
-- el nuevo tipo no es 'practicante'. Sin esto, mover a alguien de practicante
-- a planilla dejaría una modalidad colgada y el CHECK de coherencia de arriba
-- rechazaría el cambio.
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
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el tipo de vínculo.';
  end if;

  if p_tipo is null or p_tipo not in ('planilla', 'prueba', 'rxh', 'no_trabajador', 'practicante') then
    raise exception 'Tipo de vínculo inválido: %. Los válidos son planilla, prueba, rxh, no_trabajador y practicante.', p_tipo;
  end if;

  select tipo_vinculo, estado into v_antes, v_estado
  from personas where id = p_persona_id;

  if not found then
    raise exception 'Persona inválida.';
  end if;

  if v_estado = 'inactivo' then
    raise exception 'No se puede cambiar el vínculo de una persona ya cesada: su liquidación se calculó con el vínculo anterior.';
  end if;

  if v_antes = p_tipo then
    return;
  end if;

  -- CAMBIO 0324 ⇩ limpia la modalidad si deja de ser practicante, para que el
  -- CHECK de coherencia nunca la deje colgada de un vínculo que ya no es ese.
  update personas
     set tipo_vinculo = p_tipo,
         practicante_modalidad = case when p_tipo = 'practicante' then practicante_modalidad else null end
   where id = p_persona_id;

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
            when p_tipo = 'practicante'
              then 'Practicante (modalidad formativa, Ley 28518): no es relación laboral. No acumula gratificación, CTS ni vacaciones, ni aporta a pensión. SÍ genera EsSalud (CAYLA se acoge voluntariamente, art. 47) y se le paga por sus horas, pero no se le mide disciplina — igual que a un RxH, es lo que sostiene que no sea un vínculo laboral.'
            else 'No trabajador: ni asistencia ni beneficios.'
          end,
          v_quien);
end;
$$;

comment on function fn_set_tipo_vinculo(uuid, text) is
  'Cambia el tipo de vínculo de una persona. Solo admin o líder. Deja rastro en '
  'correcciones_auditoria porque el cambio apaga o enciende la acumulación de '
  'beneficios, la movilidad y el EsSalud. No se permite sobre personas cesadas. '
  '0322: agrega practicante. 0324: limpia su modalidad al salir de esa categoría.';

revoke all on function fn_set_tipo_vinculo(uuid, text) from public, anon;
grant execute on function fn_set_tipo_vinculo(uuid, text) to authenticated;

-- ── 3. fn_set_practicante_modalidad ─────────────────────────────────────────
-- Mismo molde que fn_set_tipo_vinculo (0119) y fn_set_cargo: RPC porque el
-- schema cache de PostgREST no expone columnas nuevas, guard de rol,
-- dirty-check, y rastro obligatorio en correcciones_auditoria — esto decide
-- contra qué máximo legal se avisa en Horarios, así que un cambio silencioso
-- sería tan grave como uno del tipo de vínculo mismo.
create or replace function fn_set_practicante_modalidad(p_persona_id uuid, p_modalidad text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tipo   text;
  v_antes  text;
  v_estado text;
  v_quien  uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la modalidad de una practicante.';
  end if;

  if p_modalidad is not null and p_modalidad not in ('preprofesional', 'profesional') then
    raise exception 'Modalidad inválida: %. Las válidas son preprofesional y profesional.', p_modalidad;
  end if;

  select tipo_vinculo, practicante_modalidad, estado into v_tipo, v_antes, v_estado
  from personas where id = p_persona_id;

  if not found then
    raise exception 'Persona inválida.';
  end if;

  -- El guard es el mismo espíritu que el de la retención de 4ta (0245): una
  -- modalidad solo tiene sentido para quien de verdad es practicante.
  if v_tipo is distinct from 'practicante' then
    raise exception 'Solo se puede fijar la modalidad a alguien con tipo de vínculo practicante (esta persona es %).', v_tipo;
  end if;

  if v_estado = 'inactivo' then
    raise exception 'No se puede cambiar la modalidad de una persona ya cesada.';
  end if;

  if v_antes is not distinct from p_modalidad then
    return;   -- nada que hacer, y así no se ensucia la auditoría
  end if;

  update personas set practicante_modalidad = p_modalidad where id = p_persona_id;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.practicante_modalidad',
          coalesce(v_antes, '(sin definir)'), coalesce(p_modalidad, '(sin definir)'),
          case
            when p_modalidad = 'preprofesional'
              then 'Practicante preprofesional: jornada máxima 6h/día · 30h/semana (art. 44, Ley 28518).'
            when p_modalidad = 'profesional'
              then 'Practicante profesional: jornada máxima 8h/día · 48h/semana (art. 44, Ley 28518).'
            else 'Modalidad borrada — queda sin definir.'
          end,
          v_quien);
end;
$$;

comment on function fn_set_practicante_modalidad(uuid, text) is
  'Fija si una practicante es preprofesional (30h/semana) o profesional (48h/semana), art. 44 Ley 28518. Solo admin o líder, solo sobre alguien con tipo_vinculo=practicante. Deja rastro en correcciones_auditoria.';

revoke all on function fn_set_practicante_modalidad(uuid, text) from public, anon;
grant execute on function fn_set_practicante_modalidad(uuid, text) to authenticated;

-- ── 4. fn_personas_funciones expone la modalidad ────────────────────────────
-- Copia exacta de la 0182 (la vigente — confirmado con donde-vive.sh), con
-- una sola clave nueva agregada al mismo jsonb_build_object.
create or replace function fn_personas_funciones()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', p.id, 'funcion', p.funcion, 'con_hijos', p.con_hijos,
           'es_encargada_piso', p.es_encargada_piso,
           'visible_todas_sedes', p.visible_todas_sedes,
           'tipo_vinculo', p.tipo_vinculo,
           'en_planilla', p.en_planilla,
           -- CAMBIO 0324 · qué modalidad de practicante es, para poder avisar
           -- contra su máximo legal en la pantalla de Horarios.
           'practicante_modalidad', p.practicante_modalidad,
           'cargo', p.cargo,
           'fecha_cese', p.fecha_cese,
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

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (324, 'la_practicante_dice_su_modalidad')
on conflict (numero) do nothing;

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select pg_get_constraintdef(oid) like '%preprofesional%'
     from pg_constraint where conname = 'personas_practicante_modalidad_valida')
    as el_check_de_valores_existe,

  (select pg_get_constraintdef(oid) like '%tipo_vinculo%'
     from pg_constraint where conname = 'personas_practicante_modalidad_coherente')
    as el_check_de_coherencia_existe,

  (select prosrc like '%practicante_modalidad = case%'
     from pg_proc where proname = 'fn_set_tipo_vinculo')
    as fn_set_tipo_vinculo_limpia_la_modalidad,

  (select count(*) = 1 from pg_proc where proname = 'fn_set_practicante_modalidad')
    as fn_set_practicante_modalidad_existe,

  (select prosrc like '%practicante_modalidad%'
     from pg_proc where proname = 'fn_personas_funciones')
    as fn_personas_funciones_la_expone;
