-- ============================================================================
-- 0087 — Lo que se le debe a quien se va: grati, CTS y vacaciones truncas
-- ----------------------------------------------------------------------------
-- PROMETE: calcular los tres beneficios proporcionales que corresponden al
--   cesar, con las fórmulas del RÉGIMEN MYPE PEQUEÑA EMPRESA, devolviendo
--   TODAS las cifras intermedias para que un contador pueda auditar cada línea
--   sin abrir el código.
-- ASUME: la 0085 (tipo_vinculo) y la 0086 (fecha_cese).
--
-- ⚠ LO MÁS IMPORTANTE DE ESTE ARCHIVO: pequeña empresa paga LA MITAD que el
-- régimen general en los tres conceptos. Copiar las fórmulas del régimen
-- general —que es lo que sale en la primera página de cualquier búsqueda—
-- pagaría exactamente el doble. Cada función dice abajo su norma.
--
--   gratificación  media remuneración por semestre  (general: una completa)
--   CTS            15 remuneraciones diarias al año (general: 30, ~un sueldo)
--   vacaciones     15 días al año                   (general: 30)
--
-- CÓMO SE VERIFICARON. Cinco agentes investigaron la norma y un contador
-- escéptico intentó refutar cada fórmula (26/07/2026). Encontró un error real
-- en la gratificación: la primera versión contaba los meses "del semestre del
-- cese", y lo correcto es "del periodo semestral AÚN NO PAGADO". Con casos de
-- CAYLA la diferencia iba en las dos direcciones — un cese el 5 de julio con
-- la grati sin pagar daba S/0 cuando correspondían S/790, y un cese el 20 de
-- diciembre con la grati ya cobrada el 14 daba S/658 que no correspondían.
--
-- QUÉ NO HACEN ESTAS FUNCIONES: no escriben nada, no pagan nada y no deciden
-- nada. Solo calculan. La liquidación se arma y se congela en la migración
-- siguiente.
--
-- Reversible: soltar las cinco funciones.
-- ============================================================================


-- ── Meses calendario completos y días sueltos entre dos fechas ──────────────
-- Un "mes completo" va del 1 al último día. Ingreso el 10/07 → julio no cuenta.
-- Cese el 20/09 → septiembre no cuenta como mes, sus 20 días van aparte.
-- Se extrae porque las tres fórmulas cuentan igual: si divergieran, tres
-- liquidaciones del mismo cese darían tres antigüedades distintas.
create or replace function fn_meses_y_dias(p_desde date, p_hasta date)
returns table (meses int, dias int)
language plpgsql immutable as $$
declare v_ini date; v_meses int; v_cursor date;
begin
  if p_hasta < p_desde then
    meses := 0; dias := 0; return next; return;
  end if;
  -- Primer día del primer mes COMPLETO dentro del rango.
  v_ini := case when extract(day from p_desde) = 1
                then p_desde
                else (date_trunc('month', p_desde) + interval '1 month')::date end;
  v_meses := 0;
  v_cursor := v_ini;
  while (v_cursor + interval '1 month' - interval '1 day')::date <= p_hasta loop
    v_meses := v_meses + 1;
    v_cursor := (v_cursor + interval '1 month')::date;
  end loop;
  meses := v_meses;
  -- Días sueltos: los del arranque parcial más los de la cola.
  dias := greatest(0, (v_ini - p_desde)) + greatest(0, (p_hasta - v_cursor) + 1);
  return next;
end;
$$;
grant  execute on function fn_meses_y_dias(date, date) to authenticated;
revoke execute on function fn_meses_y_dias(date, date) from public, anon;


-- ── La remuneración computable ──────────────────────────────────────────────
-- Es la base sobre la que se calcula todo. Lleva el sueldo CONTRACTUAL vigente
-- (no lo que se le pagó ese mes por horas, que varía) más la asignación
-- familiar si le corresponde.
--
-- LOS CONCEPTOS VARIABLES (bonos, plus) entran solo si la persona los percibió
-- en 3 o más meses del semestre, y entran como promedio dividido entre 6
-- (art. 16 del D.L. 650 y art. 3.2 del D.S. 005-2002-TR). Eso lo gobierna la
-- clave `liquidacion_incluye_variables` en `configuracion`: viene en true
-- porque es lo que manda la ley, y la prueba de los 3 meses hace que para
-- quien cobró el bono pocas veces no sume nada, que es el caso más común en
-- CAYLA. Se apaga cambiando un valor, sin tocar código.
insert into configuracion (clave, valor, descripcion) values (
  'liquidacion_incluye_variables', 'true'::jsonb,
  'Si los conceptos variables (bonos, plus) entran a la remuneracion computable de grati, CTS y vacaciones truncas cuando se percibieron en 3+ meses del semestre, como manda el art. 16 del D.L. 650. Apagarlo se aparta de la norma.'
) on conflict (clave) do nothing;

create or replace function fn_remuneracion_computable(p_persona_id uuid, p_fecha_ref date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p personas%rowtype;
  v_sueldo numeric; v_asig numeric := 0; v_asig_cfg numeric;
  v_sem_ini date; v_sem_fin date;
  v_meses_var int := 0; v_total_var numeric := 0; v_prom_var numeric := 0;
  v_incluir boolean;
begin
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  -- Sueldo del tramo vigente en la fecha de referencia (el mes ANTERIOR al
  -- cese, art. 5.3 del D.S. 005-2002-TR).
  select a.salario_mensual_soles into v_sueldo
    from asignaciones_salario a
   where a.persona_id = p_persona_id
     and a.vigente_desde <= p_fecha_ref
     and (a.vigente_hasta is null or a.vigente_hasta >= p_fecha_ref)
   order by a.vigente_desde desc limit 1;

  if v_sueldo is null then
    return jsonb_build_object('error', 'Sin salario asignado vigente al ' || to_char(p_fecha_ref, 'DD/MM/YYYY'));
  end if;

  -- Se lee EXACTAMENTE como la lee el motor de planilla (0069): el valor vive
  -- como {"monto": 113.00}, no como número suelto. Si las dos formas de leerlo
  -- divergieran, la boleta del mes y la liquidación darían asignaciones
  -- distintas para la misma persona.
  select coalesce((valor->>'monto')::numeric, 113.00) into v_asig_cfg
    from configuracion where clave = 'asignacion_familiar';
  if v_p.con_hijos then v_asig := coalesce(v_asig_cfg, 113.00); end if;

  -- Semestre que contiene la fecha de referencia.
  v_sem_ini := case when extract(month from p_fecha_ref) <= 6
                    then make_date(extract(year from p_fecha_ref)::int, 1, 1)
                    else make_date(extract(year from p_fecha_ref)::int, 7, 1) end;
  v_sem_fin := (v_sem_ini + interval '6 months' - interval '1 day')::date;

  select coalesce((valor #>> '{}')::boolean, true) into v_incluir
    from configuracion where clave = 'liquidacion_incluye_variables';
  v_incluir := coalesce(v_incluir, true);

  if v_incluir then
    -- En cuántos MESES DISTINTOS del semestre percibió conceptos variables, y
    -- cuánto suman. Se leen de movimientos_planilla (bonos y plus), que es
    -- donde viven los conceptos que no son el sueldo base.
    select count(distinct date_trunc('month', pp.fecha_fin)), coalesce(sum(mp.monto), 0)
      into v_meses_var, v_total_var
      from movimientos_planilla mp
      join periodos_planilla pp on pp.id = mp.periodo_id
     where mp.persona_id = p_persona_id
       and mp.monto > 0
       and pp.fecha_fin between v_sem_ini and v_sem_fin;

    -- La prueba de regularidad: menos de 3 meses, no suma nada.
    if v_meses_var >= 3 then
      v_prom_var := round(v_total_var / 6.0, 2);
    end if;
  end if;

  return jsonb_build_object(
    'sueldo_basico',       round(v_sueldo, 2),
    'asignacion_familiar', round(v_asig, 2),
    'variables_meses',     v_meses_var,
    'variables_total',     round(v_total_var, 2),
    'variables_promedio',  v_prom_var,
    'variables_entran',    (v_meses_var >= 3 and v_incluir),
    'semestre_desde',      v_sem_ini,
    'semestre_hasta',      v_sem_fin,
    'total',               round(v_sueldo + v_asig + v_prom_var, 2)
  );
end;
$$;
grant  execute on function fn_remuneracion_computable(uuid, date) to authenticated;
revoke execute on function fn_remuneracion_computable(uuid, date) from public, anon;


-- ── Gratificación trunca ────────────────────────────────────────────────────
-- MYPE pequeña empresa: MEDIA remuneración por semestre.
--   GT = (RC / 2) / 6 × M     [equivalente: RC × M / 12]
--   BE = GT × 9 %             (bonificación extraordinaria, Ley 30334)
-- M = meses calendario completos del periodo semestral AÚN NO PAGADO.
-- Mínimo: un mes íntegro de servicios (art. 5.1 del D.S. 005-2002-TR).
-- Base legal del monto: TUO Ley MYPE, D.S. 013-2013-PRODUCE art. 51.
create or replace function fn_grati_trunca(p_persona_id uuid, p_fecha_cese date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p personas%rowtype; v_rc jsonb; v_base numeric;
  v_sem_ini date; v_desde date; v_m int; v_d int;
  v_gt numeric; v_be numeric; v_fecha_ref date;
  v_sem date; v_m_sem int; v_d_sem int; v_semestres text[] := '{}';
  v_pago_ini date; v_pago_fin date;
begin
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  if not fn_devenga_beneficios(v_p.tipo_vinculo) then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'No corresponde: su vinculo es ' || v_p.tipo_vinculo || '.');
  end if;

  -- Mínimo de un mes íntegro de servicios.
  if p_fecha_cese < (v_p.fecha_ingreso + interval '1 month')::date then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'Menos de un mes integro de servicios (art. 5.1 D.S. 005-2002-TR).');
  end if;

  -- ⚠ EL PUNTO DONDE ESTO SE EQUIVOCA SI SE ESCRIBE RÁPIDO.
  -- Lo que se paga NO es "el semestre del cese": es TODO SEMESTRE AÚN NO
  -- COBRADO. Son dos cosas distintas y fallan en direcciones opuestas:
  --   · cese el 05/07 con la grati de enero–junio todavía sin pagar → si se
  --     mira solo el semestre del cese (jul–dic) da S/0, cuando corresponden
  --     seis meses completos. Se paga DE MENOS.
  --   · cese el 20/12 con la grati de julio–diciembre ya cobrada el 14 → si se
  --     mira el semestre del cese da seis meses otra vez. Se paga DOS VECES.
  -- Por eso se recorren los DOS semestres candidatos y de cada uno se cuenta
  -- solo si no hay ya un movimiento de gratificación cobrado que lo cubra.
  v_sem_ini := case when extract(month from p_fecha_cese) <= 6
                    then make_date(extract(year from p_fecha_cese)::int, 1, 1)
                    else make_date(extract(year from p_fecha_cese)::int, 7, 1) end;

  v_m := 0; v_d := 0;
  foreach v_sem in array array[
      (v_sem_ini - interval '6 months')::date,   -- el semestre anterior
      v_sem_ini                                   -- y el del cese
  ] loop
    -- ¿Ya cobró la gratificación que cubre este semestre?
    --
    -- OJO CON LA VENTANA, que es donde esto se equivoca: la grati NO se paga
    -- dentro del semestre que cubre. La de enero–junio se paga en JULIO (fuera
    -- del semestre) y la de julio–diciembre se paga en DICIEMBRE (dentro). Por
    -- eso cada semestre tiene su propia ventana de pago, y no una regla común:
    -- una ventana única haría que un pago de julio marcara como cobrados los
    -- dos semestres a la vez.
    if extract(month from v_sem) = 1 then
      v_pago_ini := (v_sem + interval '6 months')::date;   -- 1 jul
      v_pago_fin := (v_sem + interval '8 months')::date;   -- 1 sep
    else
      v_pago_ini := (v_sem + interval '5 months')::date;   -- 1 dic
      v_pago_fin := (v_sem + interval '7 months')::date;   -- 1 feb
    end if;

    if not exists (
      select 1 from movimientos_planilla mp
      join periodos_planilla pp on pp.id = mp.periodo_id
      where mp.persona_id = p_persona_id
        and mp.categoria = 'gratificacion'
        and pp.estado = 'pagado'
        and pp.fecha_fin >= v_pago_ini
        and pp.fecha_fin <  v_pago_fin
        -- Y sobre todo: pagado ANTES del cese. Sin esta línea, un cese de
        -- septiembre daría por cobrada la gratificación de diciembre —que
        -- todavía no existe— y no pagaría nada de julio ni agosto.
        and pp.fecha_fin <= p_fecha_cese
    ) then
      -- No cobrada: sus meses completos cuentan.
      v_desde := greatest(v_sem, v_p.fecha_ingreso);
      select meses, dias into v_m_sem, v_d_sem
        from fn_meses_y_dias(v_desde, least(p_fecha_cese, (v_sem + interval '6 months' - interval '1 day')::date));
      v_m := v_m + v_m_sem;
      v_d := v_d + v_d_sem;
      v_semestres := v_semestres || to_char(v_sem, 'MM/YYYY');
    end if;
  end loop;

  v_desde := greatest(v_sem_ini, v_p.fecha_ingreso);

  -- La remuneración se toma del mes ANTERIOR al del cese (art. 5.3).
  v_fecha_ref := (date_trunc('month', p_fecha_cese) - interval '1 day')::date;
  if v_fecha_ref < v_p.fecha_ingreso then v_fecha_ref := p_fecha_cese; end if;
  v_rc := fn_remuneracion_computable(p_persona_id, v_fecha_ref);
  if v_rc ? 'error' then return jsonb_build_object('aplica', false, 'monto', 0, 'motivo', v_rc->>'error'); end if;

  v_base := (v_rc->>'total')::numeric;
  v_gt := round((v_base / 2.0) / 6.0 * v_m, 2);   -- MEDIA remuneración: pequeña empresa
  v_be := round(v_gt * 0.09, 2);                  -- Ley 30334 (6.75 % si está en EPS)

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequena empresa: media remuneracion por semestre',
    'semestres_no_cobrados', v_semestres,
    'semestre_del_cese', v_sem_ini, 'hasta', p_fecha_cese,
    'meses_completos', v_m, 'dias_sueltos_no_pagados', v_d,
    'remuneracion_computable', v_rc,
    'formula', '(RC / 2) / 6 x meses_completos',
    'gratificacion', v_gt,
    'bonificacion_extraordinaria_9pct', v_be,
    'monto', round(v_gt + v_be, 2)
  );
end;
$$;
grant  execute on function fn_grati_trunca(uuid, date) to authenticated;
revoke execute on function fn_grati_trunca(uuid, date) from public, anon;


-- ── CTS trunca ──────────────────────────────────────────────────────────────
-- MYPE pequeña empresa: 15 remuneraciones diarias por año (tope 90).
--   CTS = RC/24 × meses_completos + RC/720 × dias_sueltos
-- Periodos: nov–abr (depósito de mayo) y may–oct (depósito de noviembre).
-- La RC de CTS suma además un SEXTO de la gratificación percibida en el
-- semestre; en pequeña empresa esa grati es media remuneración, así que el
-- sexto es sueldo/12 y no sueldo/6 — usar el del régimen general pagaría de más.
create or replace function fn_cts_trunca(p_persona_id uuid, p_fecha_cese date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p personas%rowtype; v_rc jsonb; v_base numeric; v_sexto numeric;
  v_per_ini date; v_desde date; v_m int; v_d int; v_cts numeric; v_anio int;
begin
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  if not fn_devenga_beneficios(v_p.tipo_vinculo) then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'No corresponde: su vinculo es ' || v_p.tipo_vinculo || '.');
  end if;
  if p_fecha_cese < (v_p.fecha_ingreso + interval '1 month')::date then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'Menos de un mes de servicios.');
  end if;

  -- Periodo de CTS en curso al cesar.
  v_anio := extract(year from p_fecha_cese)::int;
  v_per_ini := case
    when p_fecha_cese >= make_date(v_anio, 11, 1) then make_date(v_anio, 11, 1)
    when p_fecha_cese >= make_date(v_anio,  5, 1) then make_date(v_anio,  5, 1)
    else make_date(v_anio - 1, 11, 1) end;
  v_desde := greatest(v_per_ini, v_p.fecha_ingreso);

  select meses, dias into v_m, v_d from fn_meses_y_dias(v_desde, p_fecha_cese);

  v_rc := fn_remuneracion_computable(p_persona_id, p_fecha_cese);
  if v_rc ? 'error' then return jsonb_build_object('aplica', false, 'monto', 0, 'motivo', v_rc->>'error'); end if;

  -- El sexto de la gratificación de MEDIA remuneración = sueldo / 12.
  v_sexto := round(((v_rc->>'sueldo_basico')::numeric / 2.0) / 6.0, 2);
  v_base  := (v_rc->>'total')::numeric + v_sexto;

  -- 15 remuneraciones diarias al año → RC/24 por mes, RC/720 por día.
  v_cts := round(v_base / 24.0 * v_m + v_base / 720.0 * v_d, 2);

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequena empresa: 15 remuneraciones diarias por anio',
    'periodo_desde', v_per_ini, 'contado_desde', v_desde, 'hasta', p_fecha_cese,
    'meses_completos', v_m, 'dias_sueltos', v_d,
    'remuneracion_computable', v_rc,
    'sexto_de_gratificacion', v_sexto,
    'base_de_calculo', round(v_base, 2),
    'formula', 'base/24 x meses + base/720 x dias',
    'monto', v_cts
  );
end;
$$;
grant  execute on function fn_cts_trunca(uuid, date) to authenticated;
revoke execute on function fn_cts_trunca(uuid, date) from public, anon;


-- ── Vacaciones truncas ──────────────────────────────────────────────────────
-- MYPE pequeña empresa: 15 días al año.
--   VT = (RC / 2) × meses/12 + (RC / 2) × dias/360
-- Se descuentan los días ya gozados dentro del periodo, con PISO EN CERO: si
-- se adelantaron más días de los devengados, el criterio del MTPE es que la
-- persona no devuelve nada.
-- El día de vacaciones vale un treintavo del sueldo mensual (D.S. 012-92-TR
-- art. 16), NO la base horaria de 6.5 h que CAYLA usa para el pago mensual:
-- la remuneración vacacional es la que hubiera percibido de seguir trabajando.
create or replace function fn_vacaciones_truncas(p_persona_id uuid, p_fecha_cese date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p personas%rowtype; v_rc jsonb; v_base numeric;
  v_aniv date; v_m int; v_d int;
  v_ganados numeric; v_tomados numeric; v_pend numeric; v_monto numeric;
begin
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  if not fn_devenga_beneficios(v_p.tipo_vinculo) then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'No corresponde: su vinculo es ' || v_p.tipo_vinculo || '.');
  end if;
  if p_fecha_cese < (v_p.fecha_ingreso + interval '1 month')::date then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'Menos de un mes de servicios (art. 23 D.S. 012-92-TR).');
  end if;

  -- Último aniversario de ingreso antes del cese: ahí arranca el récord trunco.
  v_aniv := (v_p.fecha_ingreso
             + (make_interval(years => (extract(year from age(p_fecha_cese, v_p.fecha_ingreso))::int))))::date;
  select meses, dias into v_m, v_d from fn_meses_y_dias(v_aniv, p_fecha_cese);

  v_rc := fn_remuneracion_computable(p_persona_id, p_fecha_cese);
  if v_rc ? 'error' then return jsonb_build_object('aplica', false, 'monto', 0, 'motivo', v_rc->>'error'); end if;
  v_base := (v_rc->>'total')::numeric;

  v_ganados := round(15.0 * v_m / 12.0 + 15.0 * v_d / 360.0, 2);

  select coalesce(sum(least(v.fecha_fin, p_fecha_cese) - greatest(v.fecha_inicio, v_aniv) + 1), 0)
    into v_tomados
    from vacaciones v
   where v.persona_id = p_persona_id
     and v.fecha_fin >= v_aniv and v.fecha_inicio <= p_fecha_cese;

  v_pend  := greatest(0, v_ganados - v_tomados);   -- nunca negativo
  v_monto := round((v_base / 2.0) * v_pend / 15.0, 2);

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequena empresa: 15 dias por anio',
    'aniversario', v_aniv, 'hasta', p_fecha_cese,
    'meses_completos', v_m, 'dias_sueltos', v_d,
    'remuneracion_computable', v_rc,
    'dias_ganados', v_ganados, 'dias_gozados', v_tomados, 'dias_pendientes', v_pend,
    'valor_dia', round(v_base / 30.0, 2),
    'formula', '(RC / 2) x dias_pendientes / 15',
    'monto', v_monto
  );
end;
$$;
grant  execute on function fn_vacaciones_truncas(uuid, date) to authenticated;
revoke execute on function fn_vacaciones_truncas(uuid, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (87, 'truncas_al_cesar')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
