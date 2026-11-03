-- ============================================================================
-- 0586 · LA SEMANA SUGERIDA SE PUBLICA DE UNA VEZ
-- ============================================================================
--
-- QUÉ PROMETE
--   `fn_publicar_semana(sede, lunes, turnos, motivo)` guarda de una sola vez
--   los turnos de una semana que la líder revisó en Turnos (la propuesta de
--   `sugerencia-turnos.ts`): todos o ninguno. Cada día que cambia deja su
--   rastro en Correcciones, igual que un turno cambiado a mano, y su jornada se
--   recalcula.
--
--   Y una regla nueva, decidida por Felipe el 2026-11-03: **la líder de equipo
--   puede publicarse su propio turno**, «con tal que cumpla su horario y
--   horas». Hasta hoy no podía tocar el suyo (`fn_verificar_corrector`, 0010).
--   Aquí puede, con tres condiciones que la base comprueba:
--     1. DO le fijó su jornada (`personas.jornada_semanal_horas`, 0584). Sin
--        jornada no hay contra qué medir, y se niega.
--     2. Manda su semana COMPLETA (los siete días), y suma exactamente su
--        jornada: horas de entrada a salida, menos su refrigerio de cada día
--        trabajado (el de su horario vigente), con un margen de 15 minutos.
--     3. Solo días que todavía no llegan (después de hoy): nadie se ajusta el
--        turno de un día que ya está marcando.
--   Fuera de esto, la regla de siempre: `fn_set_turno` y `fn_set_descanso`
--   con su `fn_verificar_corrector` (una líder no toca a admin ni a Líder DO).
--
-- QUÉ ASUME
--   · La 0584 pegada (`personas.jornada_semanal_horas`) — la guardia lo exige.
--   · `fn_set_turno` y `fn_set_descanso` vigentes en la 0327; `fn_turno_texto`
--     y `fn_recalcular_jornada` como allí.
--   · El refrigerio del día es el `almuerzo_min_minutos` del horario vigente de
--     la persona esa fecha (0 si no tiene). Es el mismo que descuenta Turnos en
--     pantalla (jornada-esperada.ts) salvo un horario por día con refrigerio
--     propio; para eso está el margen de 15 minutos.
--
-- POR QUÉ ASÍ
--   · Todo o nada: una semana a medias publicada (la mitad de los días con el
--     plan nuevo y la otra mitad con el viejo) deja el piso peor que cualquiera
--     de las dos. Por eso una sola función, en una transacción, y no 70 llamadas
--     desde el navegador.
--   · Los turnos de las demás pasan por `fn_set_turno`/`fn_set_descanso` tal
--     cual: su permiso, su candado de periodo pagado y su rastro no se copian,
--     se usan. Solo el turno PROPIO de la líder se escribe aquí, porque esas dos
--     funciones lo rechazan a propósito; se escribe con las mismas columnas y el
--     mismo rastro, y el motivo dice que fue suyo y dentro de su jornada.
--   · El margen de 15 minutos es un cuarto de hora: el paso de la grilla.
--
-- ESTADOS QUE NUNCA
--   · Nunca una semana publicada a medias (una transacción).
--   · Nunca un turno propio de la líder que no sume su jornada, o de un día que
--     ya llegó.
--   · Nunca un turno de otra sede, de una persona inactiva, o fuera de la semana.
--
-- SE ROMPE SI
--   · `fn_set_turno` o `fn_set_descanso` cambian de firma: esta las llama.
--   · Se cambia cómo se escribe un turno (columnas de `turnos`, el rastro): el
--     turno propio de la líder se escribe aquí con la forma de la 0327 y hay que
--     cambiarlo en los dos sitios.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_publicar_semana(uuid, date, jsonb, text);
--   (los turnos publicados quedan: se cambian uno por uno como siempre)
--
-- CÓMO SE COMPRUEBA
--   La consulta del final: la función, su permiso y el registro.
-- ============================================================================

-- ── 0 · Guardia ─────────────────────────────────────────────────────────────
do $guardia$
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'personas' and column_name = 'jornada_semanal_horas') then
    raise exception 'Falta la 0584 (la jornada que fija DO): esta migración no entra sin ella.';
  end if;
  if to_regprocedure('fn_set_turno(uuid,date,time,time)') is null
     or to_regprocedure('fn_set_descanso(uuid,date)') is null then
    raise exception 'Faltan fn_set_turno o fn_set_descanso (0327).';
  end if;
end
$guardia$;

-- ── 1 · Publicar la semana ──────────────────────────────────────────────────
-- p_turnos: [{ "persona_id": uuid, "fecha": "2026-11-09", "entrada": "09:00", "salida": "17:00" }, …]
--           entrada y salida vacías = ese día descansa.
create or replace function fn_publicar_semana(
  p_sede_id uuid,
  p_lunes   date,
  p_turnos  jsonb,
  p_motivo  text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_editor   personas;
  r          record;
  v_obj      personas;
  v_n        integer := 0;
  v_jornada  numeric;
  v_min      numeric;
  v_dias     integer;
  v_antes    turnos;
  v_txt_antes text;
  v_txt_ahora text;
begin
  perform pg_advisory_xact_lock(hashtext('publicar_semana|' || p_sede_id::text || '|' || p_lunes::text));

  select * into v_editor from personas where auth_user_id = auth.uid() and estado = 'activo';
  if v_editor.id is null then
    raise exception 'No autorizado.';
  end if;
  if (v_editor.rol in ('admin', 'lider_do')
      or (v_editor.rol = 'supervisor_sede' and v_editor.sede_base_id = p_sede_id)) is not true then
    raise exception 'Solo la líder de equipo de esta sede, DO o un administrador publican su semana.';
  end if;

  if p_lunes is null or extract(isodow from p_lunes) <> 1 then
    raise exception 'La semana se publica desde su lunes.';
  end if;
  if p_turnos is null or jsonb_typeof(p_turnos) <> 'array' or jsonb_array_length(p_turnos) = 0 then
    raise exception 'No hay turnos para publicar.';
  end if;

  -- Cada fila: de la semana, de un día que todavía no llega, de alguien activo de esta sede, una sola vez.
  for r in
    select (x->>'persona_id')::uuid as persona_id, (x->>'fecha')::date as fecha,
           nullif(x->>'entrada', '')::time as entrada, nullif(x->>'salida', '')::time as salida
      from jsonb_array_elements(p_turnos) x
  loop
    if r.persona_id is null or r.fecha is null then
      raise exception 'Cada turno lleva persona y fecha.';
    end if;
    if r.fecha < p_lunes or r.fecha > p_lunes + 6 then
      raise exception 'El turno del % no es de la semana que empieza el %.', to_char(r.fecha, 'DD/MM'), to_char(p_lunes, 'DD/MM');
    end if;
    if r.fecha <= fn_hoy_lima() then
      raise exception 'Se publican solo días que todavía no llegan (el % ya llegó).', to_char(r.fecha, 'DD/MM');
    end if;
    if (r.entrada is null) <> (r.salida is null) or (r.entrada is not null and r.salida <= r.entrada) then
      raise exception 'Un turno lleva entrada y salida, y la salida va después de la entrada.';
    end if;
    select * into v_obj from personas where id = r.persona_id;
    if v_obj.id is null or v_obj.estado <> 'activo' or v_obj.sede_base_id is distinct from p_sede_id then
      raise exception 'Uno de los turnos es de alguien que no está activo en esta sede.';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(p_turnos) x)
     <> (select count(distinct (x->>'persona_id') || '|' || (x->>'fecha')) from jsonb_array_elements(p_turnos) x) then
    raise exception 'Hay un día repetido para la misma persona.';
  end if;

  -- El turno PROPIO de una líder de equipo: su semana entera y su jornada exacta.
  if v_editor.rol = 'supervisor_sede'
     and exists (select 1 from jsonb_array_elements(p_turnos) x where (x->>'persona_id')::uuid = v_editor.id) then
    v_jornada := v_editor.jornada_semanal_horas;
    if v_jornada is null then
      raise exception 'Tu jornada no está fijada: pídele a DO que la fije para publicar tu propio turno.';
    end if;
    select count(*) into v_dias from jsonb_array_elements(p_turnos) x where (x->>'persona_id')::uuid = v_editor.id;
    if v_dias <> 7 then
      raise exception 'Para publicar tu propio turno, manda tu semana completa (los siete días).';
    end if;
    select coalesce(sum(
             extract(epoch from (nullif(x->>'salida', '')::time - nullif(x->>'entrada', '')::time)) / 60
             - coalesce((select h.almuerzo_min_minutos from horarios_asignados h
                          where h.persona_id = v_editor.id
                            and h.vigente_desde <= (x->>'fecha')::date
                            and (h.vigente_hasta is null or h.vigente_hasta >= (x->>'fecha')::date)
                          order by h.vigente_desde desc, h.id desc limit 1), 0)
           ), 0)
      into v_min
      from jsonb_array_elements(p_turnos) x
     where (x->>'persona_id')::uuid = v_editor.id and nullif(x->>'entrada', '') is not null;
    if abs(v_min - v_jornada * 60) > 15 then
      raise exception 'Tu semana suma % h y tu jornada es de % h: tu propio turno tiene que cumplir tus horas.',
        trim(to_char(v_min / 60, 'FM990D99')), trim(to_char(v_jornada, 'FM990D99'));
    end if;
  end if;

  -- ── Escribir ──
  for r in
    select (x->>'persona_id')::uuid as persona_id, (x->>'fecha')::date as fecha,
           nullif(x->>'entrada', '')::time as entrada, nullif(x->>'salida', '')::time as salida
      from jsonb_array_elements(p_turnos) x
     order by 2, 1
  loop
    if v_editor.rol = 'supervisor_sede' and r.persona_id = v_editor.id then
      -- Su propio turno: la forma de la 0327 (fn_set_turno / fn_set_descanso), sin su guardia, que lo rechaza.
      if fn_fecha_en_periodo_pagado(r.fecha, r.persona_id) then
        raise exception 'El % cae en un periodo ya pagado.', to_char(r.fecha, 'DD/MM');
      end if;
      select * into v_antes from turnos where persona_id = r.persona_id and fecha = r.fecha;
      insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen, created_at, creado_por)
      values (r.persona_id, r.fecha, r.entrada, r.salida, r.entrada is null, 'panel', now(), v_editor.id)
      on conflict (persona_id, fecha) do update set
        hora_entrada = excluded.hora_entrada, hora_salida = excluded.hora_salida,
        es_descanso = excluded.es_descanso, origen = 'panel', created_at = now(), creado_por = v_editor.id;
      v_txt_antes := case when v_antes.persona_id is null then '(sin turno)'
                          else fn_turno_texto(v_antes.es_descanso, v_antes.hora_entrada, v_antes.hora_salida) end;
      v_txt_ahora := fn_turno_texto(r.entrada is null, r.entrada, r.salida);
      if v_txt_antes is distinct from v_txt_ahora then
        insert into correcciones_auditoria
          (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
        values (null, r.persona_id, 'turnos.horario', v_txt_antes, v_txt_ahora, v_editor.id,
                -- Empieza con «Turno del DD/MM/YYYY», como fn_set_turno: el historial de horario saca el día de ahí
                -- (diaDelMotivo, apps/web/lib/historial-horario.ts).
                'Turno del ' || to_char(r.fecha, 'DD/MM/YYYY')
                || ' (su propio turno), publicado con la semana de su sede dentro de su jornada de '
                || trim(to_char(v_editor.jornada_semanal_horas, 'FM990D99')) || ' h.'
                || coalesce(' ' || nullif(btrim(p_motivo), ''), ''));
      end if;
      perform fn_recalcular_jornada(r.persona_id, r.fecha);
    elsif r.entrada is null then
      perform fn_set_descanso(r.persona_id, r.fecha);
    else
      perform fn_set_turno(r.persona_id, r.fecha, r.entrada, r.salida);
    end if;
    v_n := v_n + 1;
  end loop;

  return v_n;
end
$fn$;

comment on function fn_publicar_semana(uuid, date, jsonb, text) is
  'Publica de una vez (todo o nada) los turnos de una semana de una sede, desde su lunes, solo días que todavía no llegan. Las demás pasan por fn_set_turno/fn_set_descanso; la líder de equipo puede publicarse su propio turno si manda su semana completa y suma su jornada (personas.jornada_semanal_horas, ±15 min). 0586.';

revoke all on function fn_publicar_semana(uuid, date, jsonb, text) from public, anon;
grant execute on function fn_publicar_semana(uuid, date, jsonb, text) to authenticated;

-- ── 2 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (586, 'la_semana_sugerida_se_publica_de_una_vez')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regprocedure('fn_publicar_semana(uuid,date,jsonb,text)') is not null                         as la_funcion_existe,
  has_function_privilege('authenticated', 'fn_publicar_semana(uuid,date,jsonb,text)', 'EXECUTE') as la_llama_el_panel,
  not has_function_privilege('anon', 'fn_publicar_semana(uuid,date,jsonb,text)', 'EXECUTE')      as anon_no,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 586)                as registro;
