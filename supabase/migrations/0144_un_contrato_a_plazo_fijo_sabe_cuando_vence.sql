-- ============================================================================
-- 0144 · Un contrato a plazo fijo sabe cuándo vence
-- ============================================================================
--
-- QUÉ PROMETE. Que el sistema pueda saber que un contrato termina el día X
-- ANTES de que ese día llegue, y avisarlo solo. Agrega
-- `personas.fecha_fin_contrato` y `fn_set_fin_contrato` para escribirla.
--
-- QUÉ ASUME. Que la 0086 está aplicada (creó `fecha_cese` y `motivo_cese`) y la
-- 0138 también (agregó el motivo `fin_contrato`).
--
-- POR QUÉ SE ELIGIÓ ASÍ.
--
-- Son DOS fechas distintas y hasta ahora solo existía una:
--
--   fecha_fin_contrato → lo PREVISTO. Cuándo vence el plazo pactado. Se sabe el
--                        día que se firma el contrato, o el día que se entrega
--                        la carta de no renovación. Es un plan.
--   fecha_cese         → lo CONSUMADO. El último día efectivamente trabajado.
--                        Es un hecho, y por eso fn_cesar_persona se niega a
--                        aceptarla en el futuro (0086:126).
--
-- Meterlas en la misma columna obligaría a elegir entre dos males: o el sistema
-- acepta ceses futuros —y entonces alguien figura cesado mientras sigue
-- viniendo a trabajar, con su salario cerrado y su horario cerrado—, o no se
-- puede anotar nada hasta que el día llegue, que es donde estábamos: el
-- 2026-08-04 se entregó una carta de no renovación por un contrato que vence el
-- 31/08 y el sistema no tenía dónde registrarlo. La persona figuraba activa y
-- sin término, la proyección de planilla la contaba como si continuara, y el
-- único lugar donde vivía la fecha era la memoria de quien la entregó.
--
-- Anotar la fecha prevista NO cesa a nadie ni mueve un sol: la persona sigue
-- activa, sigue marcando y sigue cobrando hasta su último día. Lo único que
-- cambia es que el sistema deja de depender de que alguien se acuerde.
--
-- LO QUE ESTA MIGRACIÓN NO HACE, A PROPÓSITO. No cesa automáticamente al llegar
-- la fecha. Un vencimiento puede renovarse, adelantarse o moverse, y el cese
-- cierra el salario y el horario de una persona: eso lo decide alguien, no un
-- cron. La fecha sirve para AVISAR, que es el criterio de todo este sistema
-- («Dynamic avisa, nunca sanciona solo»).
--
-- CÓMO SE REVIERTE.
--   drop function if exists fn_set_fin_contrato(uuid, date, text);
--   alter table personas drop constraint if exists personas_fin_contrato_coherente;
--   alter table personas drop column if exists fecha_fin_contrato;
-- ============================================================================

alter table personas add column if not exists fecha_fin_contrato date;

comment on column personas.fecha_fin_contrato is
  'Fecha PREVISTA de termino del contrato a plazo fijo. Es un plan, no un hecho: la persona sigue activa y cobrando hasta ese dia. NO confundir con fecha_cese, que es el ultimo dia EFECTIVAMENTE trabajado y solo se escribe cuando ya ocurrio. Null = contrato sin fecha de termino conocida.';

-- Estado imposible: un contrato no puede vencer antes de empezar.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'personas_fin_contrato_coherente') then
    alter table personas add constraint personas_fin_contrato_coherente
      check (fecha_fin_contrato is null or fecha_fin_contrato >= fecha_ingreso);
  end if;
end $$;

-- ── Escribirla ──────────────────────────────────────────────────────────────
create or replace function fn_set_fin_contrato(
  p_persona_id uuid,
  p_fecha      date,          -- null = se borra (el contrato se renovó)
  p_motivo     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  date;
  v_estado text;
  v_nombre text;
  v_quien  uuid;
begin
  -- Guard null-safe: un null no pasa como autorizado.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede fijar la fecha de término de un contrato.';
  end if;

  select fecha_fin_contrato, estado, nombres || ' ' || apellidos
    into v_antes, v_estado, v_nombre
    from personas where id = p_persona_id;

  if not found then raise exception 'Persona inválida.'; end if;

  if v_estado <> 'activo' then
    raise exception 'Esa persona ya está inactiva: su contrato ya terminó, no hay término que prever.';
  end if;

  if v_antes is not distinct from p_fecha then
    return;   -- nada que hacer, y así no se ensucia la auditoría
  end if;

  update personas set fecha_fin_contrato = p_fecha where id = p_persona_id;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Inicia sesión con tu usuario.';
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.fecha_fin_contrato',
          to_char(v_antes, 'YYYY-MM-DD'), to_char(p_fecha, 'YYYY-MM-DD'),
          coalesce(nullif(trim(p_motivo), ''),
                   case when p_fecha is null
                        then 'Se quita la fecha de término: el contrato continúa.'
                        else 'Se fija la fecha de término prevista del contrato.' end),
          v_quien);
end;
$$;

comment on function fn_set_fin_contrato(uuid, date, text) is
  'Fija (o borra, con null) la fecha PREVISTA de termino del contrato. Solo admin o lider. '
  'No cesa a nadie ni toca pagos: la persona sigue activa hasta su ultimo dia. Deja rastro en correcciones_auditoria.';

revoke execute on function fn_set_fin_contrato(uuid, date, text) from public, anon;
grant  execute on function fn_set_fin_contrato(uuid, date, text) to authenticated;

-- ── Quién está por vencer ───────────────────────────────────────────────────
-- Para que la pantalla no tenga que saber la regla. Devuelve a quien tiene una
-- fecha de término dentro de los próximos p_dias, y a quien ya la pasó sin que
-- nadie registrara el cese — ese segundo grupo es el que de verdad duele:
-- alguien que ya no viene pero sigue figurando activo, con salario vigente.
create or replace function fn_contratos_por_vencer(p_dias int default 30)
returns table (
  persona_id uuid, nombre text, sede text,
  fecha_fin_contrato date, dias_restantes int, ya_vencio boolean
)
language sql stable security definer set search_path = public as $$
  select p.id,
         p.nombres || ' ' || p.apellidos,
         coalesce(s.codigo, '—'),
         p.fecha_fin_contrato,
         (p.fecha_fin_contrato - (now() at time zone 'America/Lima')::date)::int,
         p.fecha_fin_contrato < (now() at time zone 'America/Lima')::date
    from personas p
    left join sedes s on s.id = p.sede_base_id
   where p.estado = 'activo'
     and p.fecha_fin_contrato is not null
     and p.fecha_fin_contrato <= (now() at time zone 'America/Lima')::date + p_dias
     and fn_es_admin_o_lider() is true
   order by p.fecha_fin_contrato;
$$;

comment on function fn_contratos_por_vencer(int) is
  'Contratos que vencen dentro de p_dias, y los ya vencidos sin cese registrado (dias_restantes negativo). Vacio para quien no es admin ni lider.';

revoke execute on function fn_contratos_por_vencer(int) from public, anon;
grant  execute on function fn_contratos_por_vencer(int) to authenticated;

insert into migraciones_aplicadas (numero, nombre) values (144, 'un_contrato_a_plazo_fijo_sabe_cuando_vence')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $$
begin
  raise notice '0144 · personas.fecha_fin_contrato lista. Escribir con fn_set_fin_contrato(persona, fecha, motivo). Ver pendientes con: select * from fn_contratos_por_vencer(30);';
end $$;
