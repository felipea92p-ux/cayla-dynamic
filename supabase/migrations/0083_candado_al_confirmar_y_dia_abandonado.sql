-- ============================================================================
-- 0083 — Lo que encontró la revisión adversaria de la 0081
-- ----------------------------------------------------------------------------
-- PROMETE:
--   1. Que confirmar un auto-cierre no pueda tocar una planilla ya pagada.
--   2. Que mover una marca de un día a otro recalcule TAMBIÉN el día que deja
--      atrás, en vez de dejarlo congelado cobrando horas que ya no existen.
--   3. Que dos personas corrigiendo la misma marca a la vez no se pisen.
--
-- ASUME: la 0081 (anular / corregir / confirmar) y la 0082.
--
-- DE DÓNDE SALE. La 0081 se revisó con cuatro revisores independientes y un
--   verificador por hallazgo cuyo trabajo era demostrar que cada uno era falso.
--   Sobrevivieron 17. Esta migración cierra los que tocan las funciones nuevas;
--   el resto queda anotado en docs/estado.md porque son de otras piezas.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · Confirmar un auto-cierre también respeta el periodo pagado
-- ════════════════════════════════════════════════════════════════════════════
-- Era la única de las cuatro funciones nuevas sin ese candado — y justo la que
-- más cambia el número: desde el bloque 2b de la 0081, confirmar es lo que
-- ENCIENDE la medición de salida anticipada y tiempo adicional de ese día.
-- Comprobado en laboratorio: un día dentro de un periodo pagado pasaba de
-- (salida anticipada nula, tiempo adicional 0.00) a (0, 5.50) con un clic,
-- mientras anular y corregir esa misma marca sí quedaban bloqueadas.
--
-- Se añade también `for update` (ver bloque 3).
create or replace function fn_confirmar_auto_cierre(p_marcaje_id uuid, p_motivo text default null)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;
  if v_ant.origen <> 'auto_cierre' then
    raise exception 'Solo se confirma una marca puesta por el auto-cierre.';
  end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada.';
  end if;
  if v_ant.estado_revision = 'revisada' then
    raise exception 'Ese auto-cierre ya está confirmado.';
  end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (v_ant.timestamp_marca at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: confirmarla haría que ese día empiece a medir salida anticipada y tiempo adicional, cambiando una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

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
-- 2 · El día que se deja atrás también se recalcula
-- ════════════════════════════════════════════════════════════════════════════
-- Corregir la hora de una marca puede moverla a otro día (el caso real: la marca
-- del turno noche registrada en la fecha equivocada). El trigger solo recalculaba
-- la fecha NUEVA, así que la jornada del día viejo quedaba congelada apuntando a
-- una marca que ya no está ahí — y la planilla sumaba los dos días.
--
-- Probado: día 20 con entrada 08:00 y salida 16:30 = 8.50 h; se mueve la entrada
-- al día 21; el día 20 seguía diciendo 8.50 h cuando ya no le quedaba ninguna
-- entrada. Ocho horas y media pagadas que no existieron.
--
-- Se arregla en el TRIGGER y no en la función: así queda curado también
-- fn_corregir_marcaje, que arrastra el mismo defecto desde la 0009 y sigue
-- siendo invocable. Un solo sitio en vez de dos que hay que acordarse de tocar.
create or replace function fn_trg_marcajes_recalcular_jornada()
returns trigger language plpgsql as $fn$
declare v_fecha_vieja date; v_fecha_nueva date;
begin
  v_fecha_nueva := (new.timestamp_marca at time zone 'America/Lima')::date;

  if tg_op = 'UPDATE' then
    v_fecha_vieja := (old.timestamp_marca at time zone 'America/Lima')::date;
    -- La marca cambió de día, o cambió de persona: el día que abandona también
    -- tiene que rehacerse, o se queda cobrando horas que ya no le corresponden.
    if v_fecha_vieja is distinct from v_fecha_nueva
       or old.persona_id is distinct from new.persona_id then
      perform fn_recalcular_jornada(old.persona_id, v_fecha_vieja);
    end if;
  end if;

  perform fn_recalcular_jornada(new.persona_id, v_fecha_nueva);
  return new;
end;
$fn$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · Dos personas corrigiendo la misma marca ya no se pisan
-- ════════════════════════════════════════════════════════════════════════════
-- Las cuatro funciones leían la marca sin bloqueo y luego escribían: el patrón
-- "comprueba y luego actúa" clásico. Con dos correcciones simultáneas sobre la
-- misma marca, la segunda revertía la primera — y las dos personas recibían la
-- confirmación de que su cambio se había aplicado. La auditoría quedaba con las
-- dos filas y nada revelaba que una se deshizo.
--
-- `for update` convierte eso en una cola: la segunda espera y trabaja sobre el
-- valor ya actualizado. Una línea por función.
--
-- (fn_confirmar_auto_cierre ya lo lleva en el bloque 1.)

create or replace function fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la anulación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca ya está anulada.';
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (v_ant.timestamp_marca at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: anularla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes
     set anulada_at = now(), anulada_por = v_corr, anulada_motivo = trim(p_motivo)
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_anulado',
          v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, 'anulada', v_corr, trim(p_motivo));

  return v_nuevo;
end;
$fn$;
grant execute on function fn_anular_marcaje(uuid, text) to authenticated;
revoke execute on function fn_anular_marcaje(uuid, text) from public, anon;

create or replace function fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la reactivación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;
  if v_ant.anulada_at is null then
    raise exception 'Esa marca no está anulada.';
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (v_ant.timestamp_marca at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: reactivarla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes
     set anulada_at = null, anulada_por = null, anulada_motivo = null
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_reactivado',
          'anulada: ' || coalesce(v_ant.anulada_motivo, ''), v_ant.tipo::text, v_corr, trim(p_motivo));

  return v_nuevo;
end;
$fn$;
grant execute on function fn_reactivar_marcaje(uuid, text) to authenticated;
revoke execute on function fn_reactivar_marcaje(uuid, text) from public, anon;

create or replace function fn_corregir_marca(
  p_marcaje_id uuid,
  p_nuevo_tipo tipo_marca default null,
  p_nuevo_ts   timestamptz default null,
  p_motivo     text default null)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_tipo tipo_marca; v_ts timestamptz;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada: reactívala antes de corregirla.';
  end if;

  v_tipo := coalesce(p_nuevo_tipo, v_ant.tipo);
  v_ts   := coalesce(p_nuevo_ts,   v_ant.timestamp_marca);

  if v_tipo = v_ant.tipo and v_ts = v_ant.timestamp_marca then
    raise exception 'No hay nada que cambiar en esa marca.';
  end if;

  if fn_familia_marca(v_tipo) is distinct from fn_familia_marca(v_ant.tipo) then
    raise exception 'No se puede convertir % en %: una salida solo puede pasar a ser otra salida, y un retorno a otro retorno.',
      v_ant.tipo, v_tipo;
  end if;

  -- Corregir la hora es arreglar una hora, no mudar la marca de día. Para eso
  -- están anular y agregar, que dejan rastro de las dos operaciones por separado.
  if (v_ts at time zone 'America/Lima')::date
     is distinct from (v_ant.timestamp_marca at time zone 'America/Lima')::date then
    raise exception 'Esa corrección movería la marca al %, y aquí solo se corrige la hora dentro de su mismo día. Si de verdad pertenece a otro día: anúlala y agrégala en el día correcto.',
      to_char((v_ts at time zone 'America/Lima')::date, 'DD/MM/YYYY');
  end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (
        (v_ant.timestamp_marca at time zone 'America/Lima')::date between fecha_ini and fecha_fin
        or (v_ts at time zone 'America/Lima')::date between fecha_ini and fecha_fin
      )
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: corregirla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

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

  return v_nuevo;
end;
$fn$;
grant execute on function fn_corregir_marca(uuid, tipo_marca, timestamptz, text) to authenticated;
revoke execute on function fn_corregir_marca(uuid, tipo_marca, timestamptz, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- NO se bloquea el día incoherente, a propósito
-- ════════════════════════════════════════════════════════════════════════════
-- La revisión propuso que fn_corregir_marca abortara si el día queda con una
-- secuencia imposible (por ejemplo: se convierte una "salida a almuerzo" en
-- "salida final" y su retorno sigue vivo). No se hace, y conviene dejar dicho
-- por qué: ese estado intermedio es EXACTAMENTE el flujo acordado para arreglar
-- un día — primero se corrige el tipo, después se anula el retorno que sobra.
-- Bloquear el primer paso haría imposible el segundo.
--
-- El día incoherente ya se detecta y se muestra: fn_dia_incoherente se evalúa en
-- vivo y la pantalla de Correcciones enseña el aviso de "día sellado para
-- revisión". El sistema avisa; decide la persona. Igual que con todo lo demás.
insert into migraciones_aplicadas (numero, nombre)
values (83, 'candado_al_confirmar_y_dia_abandonado')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
