-- ============================================================================
-- 0196_tres_puertas_en_vez_de_una_para_los_beneficios.sql
-- ============================================================================
-- QUÉ PROMETE
--   Poder decidir, POR PERSONA y POR BENEFICIO, quién devenga gratificación,
--   quién CTS y quién vacaciones. Hasta hoy era un solo sí/no para los tres.
--
--   **No mueve un céntimo al aplicarse.** Las tres banderas nacen en blanco, y
--   en blanco significa «decide el tipo de vínculo», que es exactamente lo de
--   hoy. Nadie cambia hasta que alguien le ponga una bandera a alguien.
--
-- QUÉ ASUME
--   Que `fn_devenga_beneficios(tipo)` sigue siendo el defecto correcto por tipo
--   de vínculo. No se toca: un locador sigue sin devengar nada por defecto.
--
-- ── POR QUÉ ─────────────────────────────────────────────────────────────────
--
-- La decisión de Felipe sobre Carlos Espejo era «gratificación y CTS sí,
-- vacaciones no», y hasta hoy no cabía en el sistema: `fn_devenga_beneficios`
-- devuelve UN booleano que gobierna los tres a la vez. Para que Carlos
-- conservara grati y CTS había que dejarlo como `planilla`, y eso le daba
-- también las vacaciones. Estaba provisionando vacaciones desde julio.
--
-- `docs/estado.md` lo tenía anotado desde entonces con esa misma frase: «se
-- revisa el día que exista la excepción por persona». Este es ese día.
--
-- Y hay una segunda mitad, medida el 2026-08-08: el interruptor por persona que
-- ya existía —`personas.devenga_beneficios`, de la 0194— **no lo leía nadie**.
-- Se escribía, se auditaba, y ninguna función lo consultaba. La pantalla decía
-- que funcionaba y no hacía nada. Esta migración lo conecta, partido en tres.
--
-- ── CÓMO ESTÁ HECHO, Y POR QUÉ ASÍ ──────────────────────────────────────────
--
-- LA REGLA VIVE EN UN SITIO. `fn_devenga(persona, beneficio)` responde la única
-- pregunta que importa: ¿esta persona devenga esto? Y responde con la bandera si
-- la hay, o con el defecto del tipo de vínculo si no. Los cuatro consumidores
-- preguntan; ninguno decide.
--
-- Y RECHAZA UN BENEFICIO DESCONOCIDO en vez de devolver el defecto. Si alguien
-- escribe 'vacacion' en singular tiene que enterarse en el momento, no descubrir
-- dentro de un año que esa llamada nunca filtró nada.
--
-- EL FACTOR SE APAGA EN ORIGEN, no en cada uso. Dentro de `fn_provisiones` los
-- tres factores se usan QUINCE veces: cada ventana, cada total, el gran total.
-- Poner un `case when devenga…` en las quince es pedir un olvido, y el olvido no
-- daría error: daría un número. Acá el factor de quien no devenga vale CERO y
-- las quince expresiones dan cero solas. Se sustituyeron 28 líneas de forma
-- mecánica, no a mano.
--
-- ── LO QUE SE MIDIÓ ANTES DE DARLO POR BUENO ────────────────────────────────
--
-- LA PRUEBA DE INERCIA: sin ninguna bandera puesta, el JSON entero de
-- `fn_provisiones` se comparó campo por campo contra el de antes, para tres
-- personas —planilla, honorarios y periodo de prueba—.
--
-- CAMBIÓ UN SOLO CAMPO, y no es dinero: `vac_dias`. A quien no devenga
-- vacaciones le mostraba los días acumulados igual —8.9 a un locador— mientras
-- su monto salía en 0. Ahora muestra 0 los dos. Es un cambio buscado y está
-- arriba explicado; se deja escrito acá porque la primera versión de este
-- encabezado prometía identidad absoluta y eso era falso. Ningún campo de
-- dinero se movió para nadie.
--
-- LA PRUEBA DE COMPORTAMIENTO: apagando solo las vacaciones de una persona de
-- planilla, cambian exactamente tres campos suyos —`vac` a 0.00, `vac_dias` a 0
-- y `gran_total` bajando 336.17, que es justo el `vac` que tenía— y NADA más.
-- Gratificación y CTS intactas, que es la decisión que había que poder expresar.
-- Las dos pruebas viven en la 151.
--
-- ── CÓMO SE USA, DESPUÉS DE PEGARLA ─────────────────────────────────────────
--   select fn_set_devenga_beneficio('<uuid de la persona>', 'vacaciones', false);
--   Y para volver al defecto del vínculo, `null` en vez de false.
--
-- CÓMO SE REVIERTE
--   Restaurar las cuatro funciones desde la 0195 y la 0160, y poner las tres
--   columnas en null. Revertir devuelve el problema: un solo sí/no para tres
--   beneficios distintos.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final: 3 columnas, 4 consumidores preguntando por su
--   beneficio, y 0 llamadas viejas.
-- ============================================================================

-- ── Las tres banderas ───────────────────────────────────────────────────────
-- Nullable a propósito: `null` es «decide el tipo de vínculo». Un `not null` con
-- defecto obligaría a decidir por las 30 personas hoy, y la decisión correcta
-- para 29 de ellas es «lo de siempre».
alter table personas add column if not exists devenga_grati      boolean;
alter table personas add column if not exists devenga_cts        boolean;
alter table personas add column if not exists devenga_vacaciones boolean;

comment on column personas.devenga_grati      is 'Excepción por persona. NULL = decide el tipo de vínculo. Ver la 0196.';
comment on column personas.devenga_cts        is 'Excepción por persona. NULL = decide el tipo de vínculo. Ver la 0196.';
comment on column personas.devenga_vacaciones is 'Excepción por persona. NULL = decide el tipo de vínculo. Ver la 0196.';

-- Lo que ya había en el interruptor viejo se reparte en los tres, para que nadie
-- pierda una decisión que alguien tomó. `devenga_beneficios` se queda como está
-- —no se borra un dato en la misma migración que lo reemplaza— y su comentario
-- avisa de que ya no lo lee nadie.
update personas
   set devenga_grati      = coalesce(devenga_grati, devenga_beneficios),
       devenga_cts        = coalesce(devenga_cts, devenga_beneficios),
       devenga_vacaciones = coalesce(devenga_vacaciones, devenga_beneficios)
 where devenga_beneficios is not null;

comment on column personas.devenga_beneficios is
  'OBSOLETA desde la 0196: la reemplazan devenga_grati, devenga_cts y '
  'devenga_vacaciones. Se conserva por su historial; ninguna función la lee.';

-- ── La regla, en un solo sitio ───────────────────────────────────────────────
-- `fn_devenga_beneficios(tipo)` se queda: sigue siendo el DEFECTO por tipo de
-- vínculo, y sigue siendo verdad que un locador no devenga nada. Lo que se
-- agrega encima es la excepción por persona y por beneficio.
--
-- En blanco (null) = «decide el tipo de vínculo», que es el comportamiento de
-- siempre. Por eso esta migración no mueve un céntimo de nadie: nadie tiene
-- banderas puestas hasta que alguien se las ponga.
create or replace function public.fn_devenga(p_persona_id uuid, p_beneficio text)
returns boolean
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare v_p personas%rowtype; v_flag boolean;
begin
  -- Se rechaza un beneficio desconocido en vez de devolver el defecto. Si
  -- alguien escribe 'vacacion' en singular, tiene que enterarse en el momento y
  -- no descubrir dentro de un año que esa llamada nunca filtró nada.
  if p_beneficio not in ('grati', 'cts', 'vacaciones') then
    raise exception 'Beneficio desconocido: %. Son grati, cts o vacaciones.', p_beneficio;
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then return false; end if;

  v_flag := case p_beneficio
              when 'grati'      then v_p.devenga_grati
              when 'cts'        then v_p.devenga_cts
              when 'vacaciones' then v_p.devenga_vacaciones
            end;

  return coalesce(v_flag, fn_devenga_beneficios(v_p.tipo_vinculo));
end;
$function$;

-- ¿Devenga ALGUNO de los tres? Es lo que decide si la persona entra siquiera al
-- cálculo de provisiones. Antes bastaba una pregunta porque los tres iban
-- juntos; ahora alguien puede devengar dos de tres y tiene que seguir entrando.
create or replace function public.fn_devenga_algo(p_persona_id uuid)
returns boolean
language sql stable security definer
set search_path to 'public'
as $function$
  select fn_devenga(p_persona_id, 'grati')
      or fn_devenga(p_persona_id, 'cts')
      or fn_devenga(p_persona_id, 'vacaciones');
$function$;

-- ── fn_grati_trunca_bruta · pregunta por SU beneficio, no por los tres ──────────
CREATE OR REPLACE FUNCTION public.fn_grati_trunca_bruta(p_persona_id uuid, p_fecha_cese date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  if not fn_devenga(p_persona_id, 'grati') then
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
$function$;

-- ── fn_cts_trunca · pregunta por SU beneficio, no por los tres ──────────
CREATE OR REPLACE FUNCTION public.fn_cts_trunca(p_persona_id uuid, p_fecha_cese date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_p personas%rowtype; v_rc jsonb; v_base numeric; v_sexto numeric;
  v_per_ini date; v_desde date; v_m int; v_d int; v_cts numeric; v_anio int;
  v_ventana text; v_anio_pago int; v_ya numeric;   -- CAMBIO 0163
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  if not fn_devenga(p_persona_id, 'cts') then
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

  -- ⇩⇩⇩ CAMBIO 0163 ⇩⇩⇩ Qué ventana es esta, con el nombre que usa el libro.
  -- Una ventana que arranca el 1 de noviembre se deposita el 15 de mayo del año
  -- SIGUIENTE; una que arranca el 1 de mayo, el 15 de noviembre del mismo año.
  if extract(month from v_per_ini)::int = 11 then
    v_ventana := 'cts_may'; v_anio_pago := extract(year from v_per_ini)::int + 1;
  else
    v_ventana := 'cts_nov'; v_anio_pago := extract(year from v_per_ini)::int;
  end if;
  v_ya := fn_beneficio_ya_depositado(p_persona_id, v_ventana, v_anio_pago);

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
    -- ⇩ CAMBIO 0163 ⇩ Lo devengado se conserva aparte para que la hoja de
    -- liquidación pueda mostrar la resta y no un número que nadie puede cuadrar.
    'devengado', v_cts,
    'ventana', v_ventana,
    'anio_ventana', v_anio_pago,
    'ya_depositado', v_ya,
    'monto', round(v_cts - v_ya, 2)
  );
end;
$function$;

-- ── fn_vacaciones_truncas · pregunta por SU beneficio, no por los tres ──────────
CREATE OR REPLACE FUNCTION public.fn_vacaciones_truncas(p_persona_id uuid, p_fecha_cese date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  if not fn_devenga(p_persona_id, 'vacaciones') then
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
$function$;

-- ── fn_provisiones · un factor por persona y por beneficio ──────────────────
CREATE OR REPLACE FUNCTION public.fn_provisiones(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_as_of date; v_y int;
  v_prov jsonb; v_f_grati numeric; v_f_cts numeric; v_f_vac numeric;
  v_f_be numeric;   -- CAMBIO 0134
  v_sexto_cts numeric;   -- CAMBIO 0112
  v_asig numeric;        -- CAMBIO 0113
  g1_ini date; g1_fin date; g1_pago date;
  g2_ini date; g2_fin date; g2_pago date;
  c1_ini date; c1_fin date; c1_pago date;
  c2_ini date; c2_fin date; c2_pago date;
  v_prox_fecha date; v_prox_tipo text; v_prox_ref text;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver las provisiones.';
  end if;
  v_as_of := coalesce(p_as_of, fn_hoy_lima());
  v_y := extract(year from v_as_of)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion":0.08333,"cts":0.04167,"vacaciones":0.04167,"sexto_cts":0}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts   := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vac   := coalesce((v_prov->>'vacaciones')::numeric, 0);

  -- CAMBIO 0134 — la bonificacion extraordinaria (Ley 30334), versionada.
  select pl.valor into v_f_be
  from parametros_laborales pl
  where pl.clave = 'bonificacion_extraordinaria'
    and pl.vigente_desde <= v_as_of
    and (pl.vigente_hasta is null or pl.vigente_hasta >= v_as_of)
  order by pl.vigente_desde desc
  limit 1;
  if v_f_be is null then v_f_be := 0.09; end if;
  -- ⇩⇩⇩ CAMBIO 0112 ⇩⇩⇩ EL SEXTO DE LA GRATIFICACIÓN EN LA BASE DE LA CTS.
  --
  -- El Art. 16 del D.S. 001-97-TR manda que la remuneración computable de la CTS
  -- incluya «un sexto de lo percibido» por gratificación en el semestre. Hasta
  -- ahora la CTS se calculaba solo sobre el sueldo, así que faltaba ese sexto.
  --
  -- En pequeña empresa la gratificación es MEDIA remuneración, así que el sexto
  -- vale (0.5 / 6) = 0.083333 del sueldo, y la base correcta es sueldo × 13/12.
  -- Comprobado: 1,130 × 13/12 × 15/30 = S/612.08 al año, contra los S/565 de hoy.
  -- Faltaban S/47.08 al año por persona.
  --
  -- ARRANCA EN CERO: si la clave no está en configuracion, el multiplicador es 1
  -- y la CTS sale exactamente como hoy. Se activa con un UPDATE:
  --
  --   update configuracion
  --      set valor = valor || '{"sexto_cts": 0.083333}'::jsonb
  --    where clave = 'planilla_provisiones';
  --
  -- POR QUÉ ES UN MULTIPLICADOR Y NO UN FACTOR NUEVO. Subir el factor de la CTS
  -- de 4.167% a 4.514% daría el mismo número HOY, pero se rompería en cuanto la
  -- base incluya otro concepto remunerativo (la asignación familiar, por ejemplo),
  -- porque el sexto tiene que salir de la gratificación real y no del sueldo pelado.
  -- Multiplicando la base, el sexto sigue siendo un sexto de lo que sea.
  --
  -- SI CAYLA PASARA AL RÉGIMEN GENERAL, donde la gratificación es una remuneración
  -- completa, el valor correcto sería (1 / 6) = 0.166667 y la base sueldo × 7/6.
  v_sexto_cts := coalesce((v_prov->>'sexto_cts')::numeric, 0);

  -- ⇩⇩⇩ CAMBIO 0113 ⇩⇩⇩ LA ASIGNACIÓN FAMILIAR ENTRA EN LA BASE.
  -- Los S/113 de la Ley 25129 SON remuneración, así que integran la remuneración
  -- computable de gratificación, CTS y vacaciones. Hasta ahora fn_provisiones no
  -- sabía que existían: se pagaban como línea aparte en la boleta y quedaban fuera
  -- de la base. El monto sale de la misma clave que usa la planilla.
  -- ⇩ CAMBIO 0122 ⇩ Esta lectura queda solo como RESPALDO. El valor que de verdad
  -- se usa se busca DÍA POR DÍA más abajo, en la rama de la 0113: esta función
  -- acumula sobre años de historia, y aplicar el monto de hoy a un periodo de 2025
  -- reescribiría lo que ya se pagó. Ver el comentario de esa rama.
  select coalesce((valor->>'monto')::numeric, 113.00) into v_asig
  from configuracion where clave = 'asignacion_familiar';
  if v_asig is null then v_asig := 113.00; end if;

  -- Ventanas del ano (periodos legales)
  g1_ini := make_date(v_y,1,1);    g1_fin := make_date(v_y,6,30);  g1_pago := make_date(v_y,7,15);
  g2_ini := make_date(v_y,7,1);    g2_fin := make_date(v_y,12,31); g2_pago := make_date(v_y,12,15);
  c1_ini := make_date(v_y-1,11,1); c1_fin := make_date(v_y,4,30);  c1_pago := make_date(v_y,5,15);
  c2_ini := make_date(v_y,5,1);    c2_fin := make_date(v_y,10,31); c2_pago := make_date(v_y,11,15);

  -- Proximo desembolso: la fecha de pago mas cercana que aun no pasa.
  -- Incluye tambien las ventanas del ANO SIGUIENTE: entre el 16 y el 31 de dic,
  -- tras el ultimo pago del ano (grati_s2, 15-dic), el proximo desembolso cae en
  -- el ano v_y+1 (CTS may). Sin estas filas, 'proximo' quedaria NULL esas dos
  -- semanas de cada diciembre.
  select fecha, tipo, ref into v_prox_fecha, v_prox_tipo, v_prox_ref
  from (values
    (c1_pago, 'CTS',           'cts_may'),
    (g1_pago, 'Gratificacion', 'grati_s1'),
    (c2_pago, 'CTS',           'cts_nov'),
    (g2_pago, 'Gratificacion', 'grati_s2'),
    (make_date(v_y+1, 5,15), 'CTS',           'cts_may'),
    (make_date(v_y+1, 7,15), 'Gratificacion', 'grati_s1'),
    (make_date(v_y+1,11,15), 'CTS',           'cts_nov'),
    (make_date(v_y+1,12,15), 'Gratificacion', 'grati_s2')
  ) t(fecha, tipo, ref)
  where fecha >= v_as_of
  order by fecha
  limit 1;

  with base as (
    -- 1) Sueldo regular ganado por HORAS (base mensual correcta). Excluye a quien
    --    cobra sueldo fijo: ese va por la rama 2, para no contar dos veces.
    select j.persona_id, j.fecha,
           j.horas_trabajadas * tt.salario
             / (6.5 * extract(day from (date_trunc('month', j.fecha) + interval '1 month - 1 day'))::numeric) as pago_dia
    from jornadas j
    -- ⇩ CAMBIO 0160 ⇩ Quien no devenga beneficios no aporta días a la base.
    join personas pp on pp.id = j.persona_id and not pp.sueldo_fijo
                    and fn_devenga_algo(pp.id)   -- CAMBIO 0196
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = j.persona_id
        and j.fecha >= a.vigente_desde
        and (a.vigente_hasta is null or j.fecha <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    where j.horas_trabajadas is not null and j.horas_trabajadas > 0

    union all

    -- ⇩⇩⇩ CAMBIO 0113 ⇩⇩⇩ 3) ASIGNACIÓN FAMILIAR de quien tiene hijos.
    --
    -- Es remuneración (Ley 25129), así que entra en la base de gratificación, CTS
    -- y vacaciones. La doctrina lo dice con este mismo ejemplo: «si ganas S/1,130
    -- + S/113, tu gratificación será S/1,243, no S/1,130».
    --
    -- Va por día de CALENDARIO y no por jornada marcada, igual que el sueldo fijo:
    -- la asignación se paga completa cada mes, no se recorta por asistencia. Al
    -- sumar un mes entero da los S/113 exactos, y en los bordes del periodo (mes
    -- de ingreso, primer mes de la ventana) prorratea por días, que es el mismo
    -- criterio que ya usaba la rama 2.
    --
    -- Aplica a TODOS los que tienen hijos, con sueldo fijo o por horas: la rama 1
    -- excluye a los de sueldo fijo para no contarlos dos veces, pero la asignación
    -- les corresponde igual, y esta rama no los excluye a propósito.
    -- ⇩⇩⇩ CAMBIO 0122 ⇩⇩⇩ EL MONTO SE BUSCA POR DÍA, no una vez para toda la
    -- historia. La asignación es el 10% de la RMV y sube cuando sube la RMV: si
    -- se aplicara el monto de hoy a los días de 2025, la provisión de un periodo
    -- ya pagado cambiaría al publicarse el decreto. Con la búsqueda por día, cada
    -- día aporta el monto que estaba vigente ESE día y el pasado queda fijo.
    --
    -- Es una subconsulta correlacionada por día y sí cuesta más que leer un
    -- escalar. Se acepta a propósito: la función es 'stable' y se llama a demanda,
    -- y la alternativa es un cálculo que se mueve solo. Si el volumen molesta, el
    -- arreglo es un lateral contra un rango de fechas, no volver al escalar.
    select p.id as persona_id, gs::date as fecha,
           coalesce(
             (select pl.valor
                from parametros_laborales pl
               where pl.clave = 'asignacion_familiar'
                 and pl.vigente_desde <= gs::date
                 and (pl.vigente_hasta is null or pl.vigente_hasta >= gs::date)
               order by pl.vigente_desde desc
               limit 1),
             v_asig)
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from personas p
    cross join lateral generate_series(p.fecha_ingreso::timestamp, v_as_of::timestamp, interval '1 day') gs
    where p.con_hijos

    union all

    -- ⇩⇩⇩ CAMBIO 0135 ⇩⇩⇩ 4) LOS DÍAS QUE LA LEY MANDA CONTAR AUNQUE NADIE MARQUE.
    --
    -- EL PROBLEMA QUE ARREGLA. La rama 1 exige `horas_trabajadas > 0`. Quien está
    -- de vacaciones no marca, así que esos días aportaban CERO a su gratificación:
    -- tomarse las vacaciones le bajaba la gratificación del semestre. Un mes entero
    -- de vacaciones costaba un sexto de la gratificación, a quien ejerció un derecho.
    --
    -- LO QUE MANDA LA NORMA. El D.S. 005-2002-TR art. 2 considera tiempo
    -- efectivamente laborado, para efectos de la gratificación:
    --   a) el descanso vacacional
    --   b) la licencia con goce de remuneraciones
    --   c) los descansos o licencias de la seguridad social que originan subsidio
    --      (descanso médico, maternidad)
    --   d) el descanso por accidente de trabajo remunerado o subsidiado
    --
    -- POR QUÉ `ta.paga` Y NO UNA LISTA DE CÓDIGOS ESCRITA A MANO. El catálogo
    -- `tipos_ausencia` ya distingue cuáles pagan (columna `paga`), y ese es
    -- exactamente el criterio de la norma. Con una lista escrita acá, el día que
    -- Felipe agregue un tipo pagado desde la pantalla habría que acordarse de
    -- tocar esta función — y nadie se va a acordar. Hoy `paga` es true para
    -- vacaciones, descanso_medico y maternidad, y false para duelo, permiso
    -- personal, estudios, cumpleaños, salud-sin-documento y otro. Esos seis NO
    -- deben sumar, y no suman.
    --
    -- POR QUÉ NO EXIGE APROBACIÓN. Una ausencia registrada y no anulada es un
    -- hecho. Exigir `aprobada_at` haría que un descanso médico pendiente de firma
    -- le baje la gratificación a la persona, y la regla de la casa es clara: el
    -- error que más cuesta es el que va contra quien no debía. Si la ausencia
    -- resulta falsa, se anula y deja de contar sola.
    --
    -- CUÁNTO APORTA UN DÍA. Lo mismo que aporta un día de sueldo fijo:
    -- salario / días del mes. Es el día estándar de esa persona a su salario
    -- vigente ESE día, no un promedio — mismo criterio que ya usa la rama 2.
    --
    -- SOLO PARA QUIEN COBRA POR HORAS. Quien tiene sueldo fijo ya devenga todos
    -- los días de calendario por la rama 2; sumarlo acá lo contaría dos veces.
    select p.id as persona_id, gs::date as fecha,
           tt.salario
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from ausencias au
    join tipos_ausencia ta on ta.codigo = au.tipo and ta.paga
    -- ⇩ CAMBIO 0160 ⇩
    join personas p on p.id = au.persona_id and not p.sueldo_fijo
                   and fn_devenga_algo(p.id)   -- CAMBIO 0196
    cross join lateral generate_series(
      greatest(au.fecha_inicio, p.fecha_ingreso)::timestamp,
      least(au.fecha_fin, v_as_of)::timestamp,
      interval '1 day') gs
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        and gs::date >= a.vigente_desde
        and (a.vigente_hasta is null or gs::date <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    where au.anulada_at is null
      -- Si ese día SÍ marcó, la rama 1 ya lo contó. Puede pasar: media jornada
      -- trabajada y media de permiso, o una ausencia registrada tarde sobre un
      -- día que ya tenía marcas.
      and not exists (
        select 1 from jornadas j
        where j.persona_id = p.id and j.fecha = gs::date
          and j.horas_trabajadas is not null and j.horas_trabajadas > 0
      )

    union all

    -- 2) SUELDO FIJO: provisiona su salario completo cada mes, marque o no. Se
    --    genera un aporte diario = salario / días del mes para cada día de
    --    calendario desde su ingreso; al sumar un mes entero da el salario, y en
    --    los bordes prorratea por días. Mismo criterio que ya usa planilla.
    select p.id as persona_id, gs::date as fecha,
           sal.salario
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from personas p
    cross join lateral generate_series(p.fecha_ingreso::timestamp, v_as_of::timestamp, interval '1 day') gs
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        and gs::date >= a.vigente_desde
        and (a.vigente_hasta is null or gs::date <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) sal on true
    -- ⇩ CAMBIO 0160 ⇩ También el sueldo fijo: un socio con sueldo fijo que no
    -- está en planilla tampoco devenga CTS, gratificación ni vacaciones.
    where p.sueldo_fijo and fn_devenga_algo(p.id)   -- CAMBIO 0196
  )
  select coalesce(jsonb_agg(sub.fila order by sub.nombre), '[]'::jsonb) into v_out
  from (
    select (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id', p.id,
        'nombre', p.nombres || ' ' || p.apellidos,
        'sede', s.codigo,
        'fecha_ingreso', p.fecha_ingreso,
        -- ⇩ CAMBIO 0123 ⇩ Una ventana ya desembolsada vale 0: seguir sumándola
        -- contaba dos veces la misma plata. El monto original viaja aparte para
        -- que la pantalla pueda escribir «pagado el 15/07» en vez de un cero mudo.
        'grati_s1', case when pag.g1 then 0 else round(dev.f_grati * coalesce(g1.pago,0), 2) end,
        'grati_s1_pagada', pag.g1,
        'grati_s1_monto_pagado', case when pag.g1 then round(dev.f_grati * coalesce(g1.pago,0), 2) end,
        'grati_s2', case when pag.g2 then 0 else round(dev.f_grati * coalesce(g2.pago,0), 2) end,
        'grati_s2_pagada', pag.g2,
        'grati_s2_monto_pagado', case when pag.g2 then round(dev.f_grati * coalesce(g2.pago,0), 2) end,
        'grati_total', round(
            (case when pag.g1 then 0 else dev.f_grati * coalesce(g1.pago,0) end)
          + (case when pag.g2 then 0 else dev.f_grati * coalesce(g2.pago,0) end), 2),
        -- ⇩ CAMBIO 0134 ⇩ La bonificacion extraordinaria sale del MISMO numero
        -- que la gratificacion y se apaga con la misma bandera: si la ventana ya
        -- se desembolso, la bonificacion se fue con ella.
        'be_s1', case when pag.g1 then 0 else round(dev.f_grati * coalesce(g1.pago,0) * v_f_be, 2) end,
        'be_s2', case when pag.g2 then 0 else round(dev.f_grati * coalesce(g2.pago,0) * v_f_be, 2) end,
        'be_total', round(
            ((case when pag.g1 then 0 else dev.f_grati * coalesce(g1.pago,0) end)
           + (case when pag.g2 then 0 else dev.f_grati * coalesce(g2.pago,0) end)) * v_f_be, 2),
        'tasa_be', v_f_be,
        -- ⇩ CAMBIO 0158 ⇩ Lo que FALTA, no un sí/no. Ver la cabecera.
        'cts_may', round(dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0)
                         - greatest(case when pag.cm then dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end,
                                    lib.cts_may), 2),
        'cts_may_pagada', (greatest(case when pag.cm then dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end,
                                    lib.cts_may) > 0),
        'cts_may_monto_pagado', nullif(round(greatest(case when pag.cm then dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end,
                                    lib.cts_may), 2), 0),
        'cts_nov', round(dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0)
                         - greatest(case when pag.cn then dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end,
                                    lib.cts_nov), 2),
        'cts_nov_pagada', (greatest(case when pag.cn then dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end,
                                    lib.cts_nov) > 0),
        'cts_nov_monto_pagado', nullif(round(greatest(case when pag.cn then dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end,
                                    lib.cts_nov), 2), 0),
        'cts_total', round(
            (case when pag.cm then 0 else dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) end)
          + (case when pag.cn then 0 else dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) end), 2),
        -- para que la pantalla pueda mostrar qué multiplicador se usó
        'sexto_cts', v_sexto_cts,
        'vac', round(dev.f_vac * coalesce(vv.pago,0), 2),
        -- Los días también, no solo el monto: mostrarle «12.4 días acumulados» a
        -- quien no devenga vacaciones es prometer por escrito algo que no
        -- existe, y esa pantalla la lee una persona.
        'vac_dias', case when dev.hay_vac
                         then round(15.0 * (v_as_of - va.aniv_ini)::numeric / 365.0, 1)
                         else 0 end,
        'proximo_aniversario', va.aniv_next,
        'gran_total', round(
            (case when pag.g1 then 0 else dev.f_grati * coalesce(g1.pago,0) * (1 + v_f_be) end)   -- CAMBIO 0134
          + (case when pag.g2 then 0 else dev.f_grati * coalesce(g2.pago,0) * (1 + v_f_be) end)   -- CAMBIO 0134
          + (dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0)
             - greatest(case when pag.cm then dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end, lib.cts_may))
          + (dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0)
             - greatest(case when pag.cn then dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end, lib.cts_nov))
          + dev.f_vac * coalesce(vv.pago,0), 2)
      ) as fila
    from personas p
    join sedes s on s.id = p.sede_base_id
    -- ⇩⇩⇩ CAMBIO 0196 ⇩⇩⇩ EL FACTOR SE APAGA EN ORIGEN.
    --
    -- Los tres factores se leen una vez arriba y se usan QUINCE veces en el
    -- bloque de la fila: en cada ventana, en cada total y en el gran total.
    -- Poner un `case when devenga…` en cada una de las quince es pedir un
    -- olvido — y el olvido no daría error: daría un número.
    --
    -- Acá el factor de quien no devenga ese beneficio vale CERO, y las quince
    -- expresiones dan cero solas. Una regla, un sitio, nada que sincronizar.
    cross join lateral (
      select case when fn_devenga(p.id, 'grati')      then v_f_grati else 0 end as f_grati,
             case when fn_devenga(p.id, 'cts')        then v_f_cts   else 0 end as f_cts,
             case when fn_devenga(p.id, 'vacaciones') then v_f_vac   else 0 end as f_vac,
             fn_devenga(p.id, 'vacaciones')                                     as hay_vac
    ) dev
    cross join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) va
    -- ⇩ CAMBIO 0158 ⇩ Lo que dice el LIBRO de desembolsos.
    -- La 0123 pregunta si hubo movimiento de planilla; eso solo ve lo que pasó
    -- POR la planilla. La CTS de mayo 2026 salió por PLAME —al banco, a la
    -- cuenta CTS de cada persona— y de eso la planilla no sabe nada.
    cross join lateral (
      select
        coalesce(sum(d.monto) filter (where d.ventana = 'cts_may' and d.anio = v_y), 0) as cts_may,
        coalesce(sum(d.monto) filter (where d.ventana = 'cts_nov' and d.anio = v_y), 0) as cts_nov
      from desembolsos_beneficios d
      where d.persona_id = p.id
    ) lib
    -- ⇩ CAMBIO 0123 ⇩ ¿Ya se desembolsó cada ventana?
    cross join lateral (
      select
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'gratificacion'
                   and g1_pago between pp.fecha_ini and pp.fecha_fin) as g1,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'gratificacion'
                   and g2_pago between pp.fecha_ini and pp.fecha_fin) as g2,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'cts'
                   and c1_pago between pp.fecha_ini and pp.fecha_fin) as cm,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'cts'
                   and c2_pago between pp.fecha_ini and pp.fecha_fin) as cn
    ) pag
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g1_ini,p.fecha_ingreso) and least(v_as_of,g1_fin)) g1 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g2_ini,p.fecha_ingreso) and least(v_as_of,g2_fin)) g2 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c1_ini,p.fecha_ingreso) and least(v_as_of,c1_fin)) cm on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c2_ini,p.fecha_ingreso) and least(v_as_of,c2_fin)) cn on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between va.aniv_ini and v_as_of) vv on true
    where p.estado = 'activo'
  ) sub;

  return jsonb_build_object(
    'as_of', v_as_of,
    'factores', v_prov,
    'proximo', jsonb_build_object('fecha', v_prox_fecha, 'tipo', v_prox_tipo, 'ref', v_prox_ref),
    'grati_s1_pago', g1_pago, 'grati_s2_pago', g2_pago,
    'cts_may_pago', c1_pago, 'cts_nov_pago', c2_pago,
    'grati_s1_periodo', 'ene-jun', 'grati_s2_periodo', 'jul-dic',
    'cts_may_periodo', 'nov-abr', 'cts_nov_periodo', 'may-oct',
    'personas', v_out
  );
end;



$function$;

-- ── Poner una bandera, con rastro ───────────────────────────────────────────
-- Una función y no un UPDATE suelto, por lo mismo que fn_set_devenga_beneficios
-- de la 0194: esto decide plata, así que tiene que quedar quién lo cambió.
create or replace function public.fn_set_devenga_beneficio(
  p_persona_id uuid, p_beneficio text, p_devenga boolean)
returns void
language plpgsql security definer
set search_path to 'public'
as $function$
declare v_antes boolean; v_yo uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el devengo de beneficios.';
  end if;
  if p_beneficio not in ('grati', 'cts', 'vacaciones') then
    raise exception 'Beneficio desconocido: %. Son grati, cts o vacaciones.', p_beneficio;
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Inicia sesión con tu usuario.';
  end if;

  select case p_beneficio
           when 'grati'      then devenga_grati
           when 'cts'        then devenga_cts
           when 'vacaciones' then devenga_vacaciones
         end
    into v_antes
  from personas where id = p_persona_id;
  if not found then raise exception 'No existe esa persona.'; end if;

  update personas
     set devenga_grati      = case when p_beneficio = 'grati'      then p_devenga else devenga_grati end,
         devenga_cts        = case when p_beneficio = 'cts'        then p_devenga else devenga_cts end,
         devenga_vacaciones = case when p_beneficio = 'vacaciones' then p_devenga else devenga_vacaciones end
   where id = p_persona_id;

  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.devenga_' || p_beneficio,
          coalesce(v_antes::text, 'defecto del vínculo'),
          coalesce(p_devenga::text, 'defecto del vínculo'),
          'Cambio del devengo de ' || p_beneficio || ' por persona',
          v_yo);
end;
$function$;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (196, 'tres_puertas_en_vez_de_una_para_los_beneficios')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Debe decir 3 · 4 · 0. El cero es el que importa: ninguna función sigue
-- preguntando por el sí/no viejo que gobernaba los tres a la vez.
select
  (select count(*) from pg_attribute a join pg_class c on c.oid = a.attrelid
    where c.relname = 'personas'
      and a.attname in ('devenga_grati','devenga_cts','devenga_vacaciones')) as banderas,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosrc ~ 'fn_devenga\(|fn_devenga_algo\('
      and p.proname not in ('fn_devenga','fn_devenga_algo','fn_set_devenga_beneficio')) as consumidores_al_dia,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosrc ~ 'fn_devenga_beneficios\('
      and p.proname not in ('fn_devenga')) as llamadas_viejas;
