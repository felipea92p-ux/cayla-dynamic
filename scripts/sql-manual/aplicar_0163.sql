-- ============================================================================
-- PARA PEGAR EN EL SQL EDITOR — las truncas descuentan lo que ya se depositó
-- ============================================================================
-- QUÉ MUEVE AL PEGARLO: **corrige un doble pago**, y no de poco. Hasta ahora una
-- liquidación por cese volvía a pagar la CTS y la gratificación que YA habían
-- salido del banco — la ventana entera, dos veces.
--
--   · `fn_cts_trunca` no miraba el libro de desembolsos. Cero menciones.
--     Siempre pagaba la ventana completa.
--   · `fn_grati_trunca` detectaba una grati pagada POR PLANILLA, pero no una
--     depositada fuera de ella (por PLAME, por ejemplo).
--
-- Nadie lo había visto porque la pantalla de liquidación no existía: la función
-- se probó con 19 casos, todos sobre una base sin depósitos previos.
--
-- NO cambia ninguna boleta ni ningún periodo de planilla. Solo cambia lo que
-- responde el cálculo de liquidación de quien cesa.
--
-- Requiere la 0155 aplicada (el libro `desembolsos_beneficios`).
-- Va ANTES de la 0164: esa se apoya en estas truncas ya corregidas.
--
-- DEBE SALIR:
--   NOTICE:  0163 · depositos anotados en el libro: N por S/X
--
-- ⚠️ SI SALE ADEMÁS ESTE AVISO, PARA Y ANOTA LOS DEPÓSITOS PRIMERO:
--   WARNING: 0163 · el libro esta VACIO: si hubo depositos y no estan anotados,
--            las truncas siguen inflandose.
--
-- El candado no puede descontar un depósito que nadie anotó. Con el libro vacío
-- la migración se aplica igual y no rompe nada, pero no protege de nada: la
-- primera liquidación seguiría pagando dos veces lo que ya se depositó.
-- ============================================================================
--
-- ============================================================================
-- 0163 — Las truncas descuentan lo que ya se depositó
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una liquidación por cese no vuelva a pagar una CTS o una gratificación
--   que ya salió del banco. Hasta hoy sí lo hacía, y no de más un poco: **dos
--   veces la ventana entera.**
--
-- QUÉ ASUME
--   · `desembolsos_beneficios` (0155) está al día. Si el libro está incompleto,
--     la trunca de quien falte seguirá inflada — el candado no puede saber de un
--     depósito que nadie anotó.
--   · Las cuatro ventanas y sus nombres, tal como los fija `fn_provisiones`.
--
-- EL AGUJERO, Y POR QUÉ NADIE LO HABÍA VISTO
--   La 0158 arregló esto del lado de las PROVISIONES: el 15 de mayo se
--   depositaron S/1.155,62 de CTS por PLAME y tres meses después las provisiones
--   seguían acumulando por esa misma ventana. Lo que esa migración no tocó es el
--   otro lado del mismo dato: la liquidación.
--
--   Medido leyendo el cuerpo de las funciones el 2026-08-05:
--     · `fn_grati_trunca` mira `movimientos_planilla` (categoría gratificacion),
--       así que detecta una grati pagada POR PLANILLA — pero no una depositada
--       fuera de ella.
--     · `fn_cts_trunca` no mira NADA. Cero menciones. Siempre paga la ventana
--       completa.
--
--   No se vio antes porque la pantalla de liquidación no existe: la función se
--   probó con sus 19 casos, todos sobre una base sin depósitos previos.
--
-- LA TRAMPA DEL NOMBRE DE LA VENTANA, que es donde esto se paga doble por adivinar
--   `ventana` se llama por el mes del DEPÓSITO, no por el inicio del devengo:
--
--     grati_s1 · devenga ene–jun (Y)        · se paga el 15 jul (Y)
--     grati_s2 · devenga jul–dic (Y)        · se paga el 15 dic (Y)
--     cts_may  · devenga nov (Y-1) – abr (Y) · se paga el 15 may (Y)
--     cts_nov  · devenga may (Y) – oct (Y)   · se paga el 15 nov (Y)
--
--   Así que la ventana que `fn_cts_trunca` calcula para un cese en agosto
--   —inicio el 1 de mayo— es la que se deposita en NOVIEMBRE: `cts_nov`, del
--   mismo año. Y una que empieza el 1 de noviembre es `cts_may` del año
--   SIGUIENTE. Cruzarlas descuenta el depósito equivocado.
--
-- LAS CUATRO DECISIONES QUE HEREDA DE LA 0158 (Felipe, 2026-08-05)
--   Se aplican igual acá, porque son el mismo dato mirado desde otro lado y dos
--   reglas distintas para el mismo hecho es lo que un inspector llama arbitrario:
--     1. Se RESTA el monto, no se marca un sí/no.
--     2. Se suman los depósitos de esa ventana, no se toma solo el último.
--     3. El negativo SE MUESTRA. Si se depositó de más, sale en negativo en vez
--        de esconderse en un cero — y en una liquidación eso significa que hay
--        algo que descontar, así que esconderlo sería pagar de más otra vez.
--     4. No hay arrastre entre ventanas.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar `fn_cts_trunca` y `fn_grati_trunca` tal como las dejó la
--   0129. No hay cambio de esquema ni de datos.
-- ============================================================================


-- ── A · Una sola forma de preguntar «¿cuánto se depositó ya de esta ventana?» ─
-- Escrita una vez porque la van a hacer las dos truncas y, mañana, la pantalla
-- de liquidación. Tres copias de esta consulta es como empiezan a discrepar.
create or replace function fn_beneficio_ya_depositado(
  p_persona_id uuid,
  p_ventana    text,
  p_anio       int
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(d.monto), 0)
  from desembolsos_beneficios d
  where d.persona_id = p_persona_id
    and d.ventana    = p_ventana
    and d.anio       = p_anio;
$$;

comment on function fn_beneficio_ya_depositado(uuid, text, int) is
  'Cuánto salió ya del banco por una ventana de beneficio. OJO: la ventana se '
  'nombra por el mes del DEPÓSITO, no por el inicio del devengo — cts_may cubre '
  'noviembre a abril. Cruzarlas descuenta el depósito equivocado.';

grant execute on function fn_beneficio_ya_depositado(uuid, text, int) to authenticated;


-- ── B · La CTS trunca, que no miraba nada ──────────────────────────────────
create or replace function fn_cts_trunca(p_persona_id uuid, p_fecha_cese date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
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
$$;


-- ── C · La gratificación trunca, que solo miraba la planilla ────────────────
-- Primero se conserva su cuerpo actual con otro nombre. Es la lógica de «todo
-- semestre aún no cobrado», con sus 19 casos probados: no hay ninguna razón para
-- reescribirla, y sí una para no hacerlo.
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
$function$;


-- Se envuelve en vez de reescribirse entera: su lógica de «todo semestre aún no
-- cobrado» son 19 casos probados y no hay razón para tocarla. Lo único que le
-- falta es restar lo que salió por fuera de la planilla.
create or replace function fn_grati_trunca(p_persona_id uuid, p_fecha_cese date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_r    jsonb;
  v_sem  text;
  v_ya   numeric := 0;
  v_anio int;
begin
  -- El guard va TAMBIÉN acá, aunque la función base lo tenga. Lo exige la prueba
  -- 108, y con razón: delegar el guard a una función interna es exactamente cómo
  -- se pierde: el día que alguien reescriba el envoltorio, o llame a la base por
  -- otro camino, el permiso desaparece sin que nada avise. La regla del repo es
  -- que el guard vive DENTRO de cada función que entrega montos, no cerca.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

  v_r := fn_grati_trunca_bruta(p_persona_id, p_fecha_cese);
  if coalesce((v_r->>'aplica')::boolean, false) is not true then
    return v_r;
  end if;

  -- ⇩⇩⇩ CAMBIO 0163 ⇩⇩⇩ Restar lo depositado FUERA de la planilla.
  -- La función base ya descarta los semestres cobrados por planilla —así detectó
  -- la grati de Chiara, S/706,54— pero un pago por transferencia no pasa por
  -- ahí. Se recorre cada semestre que quedó por pagar y se le resta su depósito.
  -- El texto de cada semestre es 'MM/YYYY' con el mes de INICIO: '01/2026' es el
  -- primer semestre y '07/2026' el segundo. Comprobado leyendo el `to_char` de la
  -- función base, no supuesto — cruzar los nombres descuenta el depósito ajeno.
  for v_sem in
    select jsonb_array_elements_text(coalesce(v_r->'semestres_no_cobrados', '[]'::jsonb))
  loop
    v_anio := split_part(v_sem, '/', 2)::int;
    v_ya := v_ya + fn_beneficio_ya_depositado(
      p_persona_id,
      case when split_part(v_sem, '/', 1) = '01' then 'grati_s1' else 'grati_s2' end,
      v_anio);
  end loop;

  return v_r
       || jsonb_build_object(
            'devengado',     (v_r->>'monto')::numeric,
            'ya_depositado', v_ya,
            'monto',         round((v_r->>'monto')::numeric - v_ya, 2));
end;
$$;

-- La base NO se concede a authenticated: se llega a ella solo por el envoltorio.
-- El revoke es explícito y no confía en el privilegio por defecto, por lo que ya
-- pasó en la 0076: un barrido de permisos deshizo un revoke deliberado.
revoke all on function fn_grati_trunca_bruta(uuid, date) from public, anon, authenticated;

grant execute on function fn_cts_trunca(uuid, date)   to authenticated;
grant execute on function fn_grati_trunca(uuid, date) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (163, 'las_truncas_descuentan_lo_ya_depositado')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_n int; v_total numeric;
begin
  select count(*), coalesce(sum(monto), 0) into v_n, v_total from desembolsos_beneficios;
  raise notice '0163 · depositos anotados en el libro: % por S/%', v_n, round(v_total, 2);
  if v_n = 0 then
    raise warning '0163 · el libro esta VACIO: si hubo depositos y no estan anotados, las truncas siguen inflandose.';
  end if;
end $mig$;
