-- ============================================================================
-- 0086 — Los cinco cabos sueltos que dejó la auditoría del 26/07
-- ----------------------------------------------------------------------------
-- PROMETE:
--   1. Que corregir una marca no deje un día roto en silencio: si queda con una
--      secuencia imposible, se sella para revisión igual que cuando la rompe el
--      terminal. Se AVISA, no se bloquea.
--   2. Que el auto-cierre nocturno no vuelva a poner una salida final donde ya
--      hay una viva.
--   3. Que el candado de periodo pagado no se pueda saltar cerrando la planilla
--      en paralelo.
--   4. Que la autorización se compruebe ANTES que el estado, y no después.
--   5. Que los días auto-cerrados que ya estaban revisados se midan todos igual,
--      en vez de quedar dos poblaciones según quién los tocó y cuándo.
--
-- ASUME: 0081 a 0085.
--
-- DE DÓNDE SALE. La 0081 pasó por una revisión adversaria (cuatro revisores y un
--   refutador por hallazgo). La 0083 cerró los tres que tocaban el dinero de
--   inmediato. Estos cinco son el resto de lo que sobrevivió.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · El auto-cierre no duplica una salida final viva
-- ════════════════════════════════════════════════════════════════════════════
-- Anular la salida final devuelve la jornada a 'abierta', que es justo lo que el
-- cron nocturno recoge: le inventaba otra salida. Y si después alguien reactivaba
-- la original, el día quedaba con DOS salidas finales; en el recálculo gana la
-- última por hora, y con horas empatadas el desempate es arbitrario.
CREATE OR REPLACE FUNCTION public.fn_auto_cierre()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_horas int;
  v_hoy_lima date := (now() at time zone 'America/Lima')::date;
  v_candidata record;
  v_ts_cierre timestamptz;
  v_cerradas int := 0;
begin
  select (valor #>> '{}')::int into v_horas from configuracion where clave = 'auto_cierre_horas';
  v_horas := coalesce(v_horas, 3);

  for v_candidata in
    select
      j.id as jornada_id,
      j.persona_id,
      j.fecha,
      j.sede_id,
      h.hora_salida
    from jornadas j
    -- cascada turno del día → horario_por_dia → legacy, igual que
    -- fn_recalcular_jornada, en vez de leer horarios_asignados.hora_salida directo
    left join lateral (
      select case
        when t.fecha is not null and t.es_descanso then null
        when t.fecha is not null then t.hora_salida
        when ha.horario_por_dia is not null
          then (ha.horario_por_dia -> extract(dow from j.fecha)::int::text ->> 's')::time
        else ha.hora_salida
      end as hora_salida
      from (select 1) uno
      left join turnos t on t.persona_id = j.persona_id and t.fecha = j.fecha
      left join lateral (
        select horario_por_dia, hora_salida
        from horarios_asignados
        where persona_id = j.persona_id
          and vigente_desde <= j.fecha
          and (vigente_hasta is null or vigente_hasta >= j.fecha)
        order by vigente_desde desc limit 1
      ) ha on true
    ) h on true
    where j.estado in ('abierta', 'en_pausa')
      and (
        (h.hora_salida is not null
          and now() >= ((j.fecha + h.hora_salida) at time zone 'America/Lima') + make_interval(hours => v_horas))
        or (h.hora_salida is null and j.fecha < v_hoy_lima)
      )
  loop
    if v_candidata.hora_salida is not null then
      v_ts_cierre := (v_candidata.fecha + v_candidata.hora_salida) at time zone 'America/Lima';
    else
      select max(timestamp_marca) into v_ts_cierre
      from marcajes
      where persona_id = v_candidata.persona_id
        and (timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha
        and anulada_at is null;
    end if;

    if v_ts_cierre is null then
      continue;
    end if;

    -- Nunca poner una segunda salida final donde ya hay una viva.
    -- El caso: se anula la salida_final de un día y la jornada vuelve a estado
    -- 'abierta', que es justo lo que este bucle recoge — así que por la noche el
    -- cron le inventaba otra. Y si después alguien reactivaba la original, el día
    -- acababa con DOS salidas finales y el recálculo se quedaba con la última por
    -- hora, con desempate arbitrario cuando coinciden.
    if exists (
      select 1 from marcajes
      where persona_id = v_candidata.persona_id
        and tipo = 'salida_final'
        and (timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha
        and anulada_at is null
    ) then
      continue;
    end if;

    insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
    values (gen_random_uuid(), v_candidata.persona_id, v_candidata.sede_id, 'salida_final', v_ts_cierre, 'auto_cierre', 'pendiente_revision');

    insert into alertas (persona_id, tipo, canal, payload)
    values (
      v_candidata.persona_id,
      'auto_cierre',
      'push',
      jsonb_build_object('fecha', v_candidata.fecha, 'jornada_id', v_candidata.jornada_id, 'ts_cierre', v_ts_cierre)
    );

    v_cerradas := v_cerradas + 1;
  end loop;

  return v_cerradas;
end;
$function$;

-- ════════════════════════════════════════════════════════════════════════════
-- 2 · Reactivar no puede crear una segunda salida final
-- ════════════════════════════════════════════════════════════════════════════
-- La otra mitad del mismo problema: si mientras la original estaba anulada el
-- sistema (o una persona) puso otra salida final, reactivarla dejaría dos.
--
-- Aquí también se mueve fn_verificar_corrector al principio (punto 4 del
-- encabezado): la autorización va antes que cualquier mensaje sobre el estado de
-- la marca. Y el candado de periodo pagado pasa a bloquear la fila del periodo
-- con `for share`, no solo mirarla: sin eso, un periodo que pasa a 'pagado'
-- entre la comprobación y el commit dejaba entrar la operación igual.
create or replace function fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la reactivación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  -- Autorización primero: los mensajes de estado de abajo cuentan cosas de una
  -- marca que quien pregunta puede no tener derecho a conocer.
  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is null then
    raise exception 'Esa marca no está anulada.';
  end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: reactivarla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  if v_ant.tipo = 'salida_final' and exists (
    select 1 from marcajes
    where persona_id = v_ant.persona_id
      and tipo = 'salida_final'
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and anulada_at is null
      and id <> p_marcaje_id
  ) then
    raise exception 'Ese día ya tiene otra salida final activa. Anula primero la que sobra: dos salidas finales el mismo día dejan el cálculo al azar.';
  end if;

  update marcajes
     set anulada_at = null, anulada_por = null, anulada_motivo = null
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_reactivado',
          'anulada: ' || coalesce(v_ant.anulada_motivo, ''), v_ant.tipo::text, v_corr, trim(p_motivo));

  perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  return v_nuevo;
end;
$fn$;
grant execute on function fn_reactivar_marcaje(uuid, text) to authenticated;
revoke execute on function fn_reactivar_marcaje(uuid, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · Anular: autorización primero y candado con bloqueo
-- ════════════════════════════════════════════════════════════════════════════
create or replace function fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la anulación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is not null then
    raise exception 'Esa marca ya está anulada.';
  end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: anularla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  update marcajes
     set anulada_at = now(), anulada_por = v_corr, anulada_motivo = trim(p_motivo)
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_anulado',
          v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, 'anulada', v_corr, trim(p_motivo));

  perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  return v_nuevo;
end;
$fn$;
grant execute on function fn_anular_marcaje(uuid, text) to authenticated;
revoke execute on function fn_anular_marcaje(uuid, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 4 · Confirmar: autorización primero y candado con bloqueo
-- ════════════════════════════════════════════════════════════════════════════
create or replace function fn_confirmar_auto_cierre(p_marcaje_id uuid, p_motivo text default null)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.origen <> 'auto_cierre' then
    raise exception 'Solo se confirma una marca puesta por el auto-cierre.';
  end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada.';
  end if;
  if v_ant.estado_revision = 'revisada' then
    raise exception 'Ese auto-cierre ya está confirmado.';
  end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: confirmarla haría que ese día empiece a medir salida anticipada y tiempo adicional, cambiando una planilla ya pagada. Reabre el periodo primero.';
  end if;

  update marcajes set estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'auto_cierre_confirmado',
          'pendiente_revision', 'revisada', v_corr,
          coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Confirmado: esa es su salida final.'));

  return v_nuevo;
end;
$fn$;
grant execute on function fn_confirmar_auto_cierre(uuid, text) to authenticated;
revoke execute on function fn_confirmar_auto_cierre(uuid, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 5 · Corregir: si el día queda roto, se sella. No se bloquea.
-- ════════════════════════════════════════════════════════════════════════════
-- fn_familia_marca deja convertir una "salida a almuerzo" en "salida final"
-- aunque su retorno siga vivo — y eso es DELIBERADO: es el primer paso del flujo
-- acordado para arreglar un día (corregir el tipo, después anular lo que sobra).
-- Bloquearlo haría imposible el segundo paso.
--
-- Lo que faltaba es que el día roto no se quedara callado. Antes: la jornada
-- terminaba en 'cerrada', sin sello, con un retorno huérfano cuya hora de
-- ausencia ya no se descontaba — o sea, pagando de más sin que nada avisara.
-- Ahora se sella igual que cuando lo rompe el terminal, y la 0084 se encarga de
-- levantar ese sello en cuanto el día vuelva a cuadrar.
create or replace function fn_corregir_marca(
  p_marcaje_id uuid,
  p_nuevo_tipo tipo_marca default null,
  p_nuevo_ts   timestamptz default null,
  p_motivo     text default null)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_tipo tipo_marca; v_ts timestamptz; v_fecha date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada: reactívala antes de corregirla.';
  end if;

  v_tipo := coalesce(p_nuevo_tipo, v_ant.tipo);
  v_ts   := coalesce(p_nuevo_ts,   v_ant.timestamp_marca);
  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;

  if v_tipo = v_ant.tipo and v_ts = v_ant.timestamp_marca then
    raise exception 'No hay nada que cambiar en esa marca.';
  end if;

  if fn_familia_marca(v_tipo) is distinct from fn_familia_marca(v_ant.tipo) then
    raise exception 'No se puede convertir % en %: una salida solo puede pasar a ser otra salida, y un retorno a otro retorno.',
      v_ant.tipo, v_tipo;
  end if;

  if (v_ts at time zone 'America/Lima')::date is distinct from v_fecha then
    raise exception 'Esa corrección movería la marca al %, y aquí solo se corrige la hora dentro de su mismo día. Si de verdad pertenece a otro día: anúlala y agrégala en el día correcto.',
      to_char((v_ts at time zone 'America/Lima')::date, 'DD/MM/YYYY');
  end if;

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: corregirla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  update marcajes
     set tipo = v_tipo, timestamp_marca = v_ts, estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  if v_tipo is distinct from v_ant.tipo then
    insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (p_marcaje_id, v_ant.persona_id, 'tipo', v_ant.tipo::text, v_tipo::text, v_corr, trim(p_motivo));
  end if;
  if v_ts is distinct from v_ant.timestamp_marca then
    insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (p_marcaje_id, v_ant.persona_id, 'timestamp_marca', v_ant.timestamp_marca::text, v_ts::text, v_corr, trim(p_motivo));
  end if;

  -- ¿La corrección dejó el día imposible? Se sella, igual que hace el terminal.
  -- Avisa sin impedir: el flujo normal pasa por aquí a mitad de camino.
  if fn_dia_incoherente(v_ant.persona_id, v_fecha) then
    update marcajes
       set estado_revision = 'pendiente_revision'
     where persona_id = v_ant.persona_id
       and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
       and anulada_at is null
       and estado_revision = 'normal';
  else
    perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  end if;

  return v_nuevo;
end;
$fn$;
grant execute on function fn_corregir_marca(uuid, tipo_marca, timestamptz, text) to authenticated;
revoke execute on function fn_corregir_marca(uuid, tipo_marca, timestamptz, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 6 · Que los días auto-cerrados ya revisados se midan todos igual
-- ════════════════════════════════════════════════════════════════════════════
-- La 0081 cambió la regla: un auto-cierre 'revisada' pasa a medir salida
-- anticipada y tiempo adicional. Pero aplicar una migración no recalcula nada, y
-- fn_corregir_marcaje (0009) ya dejaba 'revisada' cada vez que alguien corregía
-- la hora de un auto-cierre. Resultado: dos poblaciones de días idénticos con
-- números distintos — los que nadie volvió a tocar conservan el valor viejo, y
-- los que se recalculen mañana por cualquier motivo cambiarán solos.
--
-- Se decide aplicar la regla a TODOS, y se recalculan aquí para que ninguna cifra
-- cambie después por sorpresa. No altera horas_trabajadas: solo rellena las dos
-- medidas que estaban en blanco.
do $$
declare r record; n int := 0;
begin
  for r in
    select distinct m.persona_id,
           (m.timestamp_marca at time zone 'America/Lima')::date as fecha
    from marcajes m
    where m.origen = 'auto_cierre'
      and m.estado_revision = 'revisada'
      and m.anulada_at is null
      and m.tipo = 'salida_final'
      -- Nunca se toca un periodo ya pagado, ni siquiera para cuadrar cifras.
      and not exists (
        select 1 from periodos_planilla pp
        where pp.estado = 'pagado'
          and (m.timestamp_marca at time zone 'America/Lima')::date between pp.fecha_ini and pp.fecha_fin)
  loop
    perform fn_recalcular_jornada(r.persona_id, r.fecha);
    n := n + 1;
  end loop;
  raise notice 'Días auto-cerrados ya revisados que se recalcularon: %', n;
end $$;


insert into migraciones_aplicadas (numero, nombre)
values (86, 'lo_que_encontro_la_auditoria_del_26')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
