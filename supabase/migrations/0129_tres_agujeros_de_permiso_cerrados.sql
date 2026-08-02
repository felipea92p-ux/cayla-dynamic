-- ============================================================================
-- 0129 — Tres agujeros de permiso que la auditoría encontró, cerrados
--
-- ⚠️ POR QUÉ SALTA DEL 0127 AL 0129. El número 0128 está RESERVADO para
-- `0128_la_base_declarada_por_rango.sql`, que existe escrita en la carpeta de
-- Felipe pero todavía no está en git ni aplicada: toca lo que cobra cada persona
-- y espera que él apruebe los montos contra los netos reales. Esta migración no
-- depende de ella y no la contradice; se numeró 0129 para no ocupar su lugar.
-- Si la 0128 se descarta, hay que documentar el hueco.
--
-- Los tres hallazgos vienen de la auditoría de 24 dimensiones del 2026-08-02, y
-- los tres se REPRODUJERON contra Postgres local antes de escribir una línea.
--
-- ── A · CUALQUIER SESIÓN CON LOGIN PODÍA METER VACACIONES POR OTRA PERSONA ───
--
-- La 0101 dice por escrito que «el INSERT NO se concede a authenticated», y no
-- lo conseguía. Dos razones que se suman:
--   · Las vistas nacen con INSERT/UPDATE/DELETE por el `alter default
--     privileges` de la 0004.
--   · `revoke all … from anon, public` NO quita lo concedido directamente al rol
--     `authenticated`. Hay que nombrarlo, como sí lo hacen la 0115 y la 0120.
--
-- Comprobado: has_table_privilege('authenticated', 'vacaciones', 'INSERT') = true.
--
-- Encima el trigger «instead of insert» es SECURITY DEFINER y no comprobaba nada:
-- recibía persona_id del cliente y lo insertaba. Desde la consola del terminal de
-- una tienda, o desde la sesión de una integrante, se podían meter 15 días de
-- vacaciones para cualquiera: le quemaban el saldo, le blanqueaban faltas, y al
-- cesar le habrían pagado menos días pendientes.
--
-- Se arregla con las DOS cosas: el revoke nombrando al rol, y el guard dentro del
-- trigger. El revoke solo no alcanza porque se deshace la próxima vez que alguien
-- conceda privilegios en masa — que es exactamente lo que pasó acá.
--
-- ── B · LAS CUATRO FUNCIONES DE LIQUIDACIÓN ENTREGABAN EL SUELDO DE UN COLEGA ─
--
-- fn_remuneracion_computable, fn_grati_trunca, fn_cts_trunca y
-- fn_vacaciones_truncas son SECURITY DEFINER, están concedidas a authenticated y
-- su cuerpo solo comprobaba que la persona exista.
--
-- Reproducido: desde una sesión de integrante, fn_remuneracion_computable
-- devolvió el sueldo básico, la asignación familiar y el total de otra persona.
-- El roster del terminal ya entrega los uuid, así que no hacía falta adivinar
-- nada. Sueldos entre colegas en un equipo de 25 personas es un problema laboral
-- real, no un tecnicismo.
--
-- Es el mismo agujero que la 0090 cerró para fn_planilla_calcular; estas cuatro
-- quedaron fuera de la lista y la prueba 91 no las miraba. Ninguna pantalla las
-- llama hoy, así que el guard no rompe nada.
--
-- ── C · ANULAR UNA MARCA ROMPÍA EL CIERRE DEL DÍA ────────────────────────────
--
-- La 0082 puso «and anulada_at is null» en las dos primeras consultas de
-- fn_siguiente_tipo_esperado y se le quedó fuera la tercera, la que decide cuál
-- fue la última marca del día. El navegador sí filtra las anuladas, así que las
-- dos copias de la regla se contradecían justo ahí — y la que manda es la base.
--
-- Con una SALIDA temporal anulada, el terminal ofrecía «Salida final» y el
-- servidor la rechazaba pidiendo el retorno: la persona se iba creyendo que
-- marcó y el auto-cierre le estampaba la hora programada. Con el RETORNO
-- anulado era al revés y peor: el servidor ACEPTABA la salida final con el
-- almuerzo abierto, no descontaba la ausencia, y se pagaba la hora de refrigerio.
--
-- ── CÓMO SE ESCRIBIÓ ────────────────────────────────────────────────────────
-- Las siete funciones se extrajeron de sus archivos originales (0082, 0087, 0101)
-- con un script, y se les insertó únicamente el guard o el filtro. Ni un carácter
-- más cambió, para que no haya diferencia por retipear.
--
-- NO MUEVE NINGÚN PAGO por sí sola. Lo que cambia es quién puede leer y escribir.
-- El arreglo C sí corrige un cálculo, pero en el sentido correcto: deja de pagar
-- una hora de refrigerio que no correspondía.
--
-- CÓMO SE REVIERTE. Restaurar las siete funciones desde sus migraciones de origen
-- y volver a conceder los privilegios. No se debería: reabre los tres agujeros.
-- ============================================================================


-- ── A · Las vistas de ausencias ──────────────────────────────────────────────
-- Nombrando al rol. Esto es lo que la 0101 quiso hacer y no hizo.
revoke insert, update, delete on vacaciones from authenticated;
revoke insert, update, delete on justificaciones_asistencia from authenticated;

-- Y el cinturón, dentro de los triggers.
create or replace function fn_trg_vacaciones_insert()
returns trigger language plpgsql security definer set search_path = public as $t$
begin
  -- ⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩ El cinturón, además del revoke.
  -- Este trigger es SECURITY DEFINER y recibe persona_id del cliente: sin esto,
  -- cualquier sesión con login podía meter una ausencia a nombre de quien
  -- quisiera —quemándole el saldo de vacaciones y blanqueándole faltas—. El
  -- revoke solo no alcanza, porque se deshace la próxima vez que alguien conceda
  -- privilegios en masa; fue exactamente lo que dejó este agujero abierto.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar una ausencia por otra persona.';
  end if;

  insert into ausencias (id, persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, registrada_at)
  values (coalesce(new.id, gen_random_uuid()), new.persona_id, 'vacaciones',
          new.fecha_inicio, new.fecha_fin, new.observacion,
          new.creado_por, coalesce(new.creado_at, now()));
  return new;
end;
$t$;

create or replace function fn_trg_justificaciones_insert()
returns trigger language plpgsql security definer set search_path = public as $t$
begin
  -- ⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩ El cinturón, además del revoke.
  -- Este trigger es SECURITY DEFINER y recibe persona_id del cliente: sin esto,
  -- cualquier sesión con login podía meter una ausencia a nombre de quien
  -- quisiera —quemándole el saldo de vacaciones y blanqueándole faltas—. El
  -- revoke solo no alcanza, porque se deshace la próxima vez que alguien conceda
  -- privilegios en masa; fue exactamente lo que dejó este agujero abierto.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar una ausencia por otra persona.';
  end if;

  insert into ausencias (id, persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, registrada_at)
  values (coalesce(new.id, gen_random_uuid()), new.persona_id,
          case new.motivo when 'permiso_concedido' then 'permiso_personal' else new.motivo end,
          new.fecha, new.fecha, new.observacion,
          new.creado_por, coalesce(new.creado_at, now()));
  return new;
end;
$t$;


-- ── B · Las cuatro funciones de liquidación ──────────────────────────────────
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
  -- ⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩ El guard que faltaba desde la 0087.
  -- Estas cuatro funciones son SECURITY DEFINER y están concedidas a
  -- authenticated, y su cuerpo solo comprobaba que la persona exista. Reproducido
  -- contra Postgres local: desde una sesión de integrante devolvían el sueldo
  -- básico, la asignación familiar y los montos de liquidación de un colega.
  --
  -- Es el mismo agujero que la 0090 cerró para fn_planilla_calcular; estas se
  -- quedaron fuera. El guard va DENTRO y no como un revoke, por lo aprendido
  -- ahí: un revoke se deshace la próxima vez que alguien conceda en masa, y un
  -- guard no.
  --
  -- Si algún día se hace una pantalla «mi liquidación», acá se agrega
  -- «or p_persona_id = fn_persona_actual_id()» — con la forma is not true.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

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
  -- ⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩ El guard que faltaba desde la 0087.
  -- Estas cuatro funciones son SECURITY DEFINER y están concedidas a
  -- authenticated, y su cuerpo solo comprobaba que la persona exista. Reproducido
  -- contra Postgres local: desde una sesión de integrante devolvían el sueldo
  -- básico, la asignación familiar y los montos de liquidación de un colega.
  --
  -- Es el mismo agujero que la 0090 cerró para fn_planilla_calcular; estas se
  -- quedaron fuera. El guard va DENTRO y no como un revoke, por lo aprendido
  -- ahí: un revoke se deshace la próxima vez que alguien conceda en masa, y un
  -- guard no.
  --
  -- Si algún día se hace una pantalla «mi liquidación», acá se agrega
  -- «or p_persona_id = fn_persona_actual_id()» — con la forma is not true.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

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

create or replace function fn_cts_trunca(p_persona_id uuid, p_fecha_cese date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p personas%rowtype; v_rc jsonb; v_base numeric; v_sexto numeric;
  v_per_ini date; v_desde date; v_m int; v_d int; v_cts numeric; v_anio int;
begin
  -- ⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩ El guard que faltaba desde la 0087.
  -- Estas cuatro funciones son SECURITY DEFINER y están concedidas a
  -- authenticated, y su cuerpo solo comprobaba que la persona exista. Reproducido
  -- contra Postgres local: desde una sesión de integrante devolvían el sueldo
  -- básico, la asignación familiar y los montos de liquidación de un colega.
  --
  -- Es el mismo agujero que la 0090 cerró para fn_planilla_calcular; estas se
  -- quedaron fuera. El guard va DENTRO y no como un revoke, por lo aprendido
  -- ahí: un revoke se deshace la próxima vez que alguien conceda en masa, y un
  -- guard no.
  --
  -- Si algún día se hace una pantalla «mi liquidación», acá se agrega
  -- «or p_persona_id = fn_persona_actual_id()» — con la forma is not true.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

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

create or replace function fn_vacaciones_truncas(p_persona_id uuid, p_fecha_cese date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p personas%rowtype; v_rc jsonb; v_base numeric;
  v_aniv date; v_m int; v_d int;
  v_ganados numeric; v_tomados numeric; v_pend numeric; v_monto numeric;
begin
  -- ⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩ El guard que faltaba desde la 0087.
  -- Estas cuatro funciones son SECURITY DEFINER y están concedidas a
  -- authenticated, y su cuerpo solo comprobaba que la persona exista. Reproducido
  -- contra Postgres local: desde una sesión de integrante devolvían el sueldo
  -- básico, la asignación familiar y los montos de liquidación de un colega.
  --
  -- Es el mismo agujero que la 0090 cerró para fn_planilla_calcular; estas se
  -- quedaron fuera. El guard va DENTRO y no como un revoke, por lo aprendido
  -- ahí: un revoke se deshace la próxima vez que alguien conceda en masa, y un
  -- guard no.
  --
  -- Si algún día se hace una pantalla «mi liquidación», acá se agrega
  -- «or p_persona_id = fn_persona_actual_id()» — con la forma is not true.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

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


-- ── C · La última marca del día ignora las anuladas ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_siguiente_tipo_esperado(p_persona_id uuid, p_fecha date)
 RETURNS tipo_marca
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_ultimo record;
  v_tiene_entrada boolean;
  v_tiene_salida_final boolean;
  v_pares jsonb := '{
    "salida_almuerzo": "retorno_almuerzo",
    "salida_personal": "retorno_personal",
    "salida_tramite": "retorno_tramite",
    "salida_medico": "retorno_medico",
    "salida_otro": "retorno_otro"
  }'::jsonb;
begin
  select exists(
    select 1 from marcajes
    where persona_id = p_persona_id
      and tipo = 'entrada'
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
      and anulada_at is null
  ) into v_tiene_entrada;

  if not v_tiene_entrada then
    return 'entrada';
  end if;

  select exists(
    select 1 from marcajes
    where persona_id = p_persona_id
      and tipo = 'salida_final'
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
      and anulada_at is null
  ) into v_tiene_salida_final;

  if v_tiene_salida_final then
    return null; -- jornada cerrada, ninguna acción válida
  end if;

  -- ⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩ El filtro que se le quedó fuera a la 0082.
  -- Las dos consultas de arriba sí filtran las anuladas; esta, que decide cuál
  -- fue la ÚLTIMA marca del día, no. El navegador sí las filtra, así que las dos
  -- copias de la regla se contradecían justo acá — y la que manda es esta.
  --
  -- Con una SALIDA temporal anulada, el terminal ofrecía «Salida final» y el
  -- servidor la rechazaba pidiendo el retorno. Con el RETORNO anulado era peor:
  -- el servidor ACEPTABA la salida final con el almuerzo abierto, no descontaba
  -- la ausencia, y se pagaba la hora de refrigerio.
  select tipo, timestamp_marca into v_ultimo
  from marcajes
  where persona_id = p_persona_id
    and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
    and anulada_at is null
  order by timestamp_marca desc
  limit 1;

  if v_pares ? v_ultimo.tipo::text then
    return (v_pares ->> v_ultimo.tipo::text)::tipo_marca;
  end if;

  return null; -- debe elegir tipo de salida — ambigüedad legítima, no se resuelve aquí
end;
$function$;


-- ── El aviso de cierre ───────────────────────────────────────────────────────
do $mig$
declare v_priv text; v_sin_guard text;
begin
  select string_agg(c.relname || ':' ||
           case when has_table_privilege('authenticated', c.relname::text, 'INSERT')
                then 'INSERT ' else '' end ||
           case when has_table_privilege('authenticated', c.relname::text, 'UPDATE')
                then 'UPDATE ' else '' end ||
           case when has_table_privilege('authenticated', c.relname::text, 'DELETE')
                then 'DELETE' else '' end, ', ')
    into v_priv
  from pg_class c
  where c.relname in ('vacaciones','justificaciones_asistencia')
    and (has_table_privilege('authenticated', c.relname::text, 'INSERT')
      or has_table_privilege('authenticated', c.relname::text, 'UPDATE')
      or has_table_privilege('authenticated', c.relname::text, 'DELETE'));

  if v_priv is null then
    raise notice '0129 · A · authenticated ya no puede escribir en las vistas de ausencias.';
  else
    raise notice '0129 · A · ATENCION: siguen concedidos: %', v_priv;
  end if;

  select string_agg(p.proname, ', ' order by p.proname) into v_sin_guard
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('fn_remuneracion_computable','fn_grati_trunca',
                      'fn_cts_trunca','fn_vacaciones_truncas',
                      'fn_trg_vacaciones_insert','fn_trg_justificaciones_insert')
    and p.prosrc not like '%fn_es_admin_o_lider() is not true%';

  if v_sin_guard is null then
    raise notice '0129 · B · las seis funciones tienen su guard null-safe.';
  else
    raise notice '0129 · B · ATENCION: sin guard: %', v_sin_guard;
  end if;

  if (select prosrc from pg_proc where proname = 'fn_siguiente_tipo_esperado')
       like '%and anulada_at is null%order by timestamp_marca desc%'
  then
    raise notice '0129 · C · la ultima marca del dia ya ignora las anuladas.';
  else
    raise notice '0129 · C · ATENCION: el filtro de anuladas no quedo en la tercera consulta.';
  end if;
end
$mig$;


insert into migraciones_aplicadas (numero, nombre)
values (129, 'tres_agujeros_de_permiso_cerrados')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
