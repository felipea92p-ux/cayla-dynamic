-- ============================================================================
-- PARA PEGAR EN EL SQL EDITOR — la liquidación por cese, completa
-- ============================================================================
-- Cuatro migraciones en el orden en que tienen que aplicarse:
--
--   0163 · las truncas descuentan lo que ya se depositó (arregla un doble pago)
--   0164 · fn_liquidacion — el cálculo completo, con el reloj de las 48 horas
--   0167 · la foto: lo pagado se congela y avisa si deja de cuadrar
--   0169 · aviso cuando alguien lleva más de un mes en el vínculo «prueba»
--
-- EL ORDEN IMPORTA. La 0164 llama a las truncas que arregla la 0163; la 0167
-- congela lo que calcula la 0164. Pegarlas al revés deja fotos de un cálculo
-- que todavía paga doble.
--
-- QUÉ MUEVE AL PEGARLO
--   Un pago sí cambia, y es el punto: **la CTS y la gratificación truncas dejan
--   de pagar lo que ya salió del banco.** Si el libro `desembolsos_beneficios`
--   está vacío no cambia nada — pero entonces conviene llenarlo antes de liquidar
--   a alguien, porque el descuento no puede saber de un depósito que nadie anotó.
--
--   El resto no mueve nada: la 0164 y la 0167 son cálculo y registro nuevos, y la
--   0169 solo avisa. Ninguna toca la planilla mensual.
--
-- Es idempotente: pegarlo dos veces no hace nada distinto. Comprobado.
--
-- DESPUÉS DE PEGARLO, mira los avisos del final. Van a decirte cuántos depósitos
-- hay anotados en el libro y quién sigue en el vínculo «prueba».
-- ============================================================================


-- ── Preámbulo: que pegarlo dos veces no falle ───────────────────────────────
-- La 0164 crea `fn_liquidaciones_pendientes` con diez columnas y la 0167 la
-- amplía a doce. En una base donde esto ya se aplicó, la 0164 aborta con
-- «cannot change return type of existing function» — `create or replace` no
-- puede cambiar el tipo de retorno de una función que ya existe.
--
-- Comprobado pegándolo dos veces seguidas. Se borra antes; las migraciones la
-- vuelven a crear en orden y la última versión gana, que es la correcta.
-- Esto no toca datos: son definiciones de función.
drop function if exists fn_liquidaciones_pendientes();

-- ══════════════════════════════════════════════════════════════════════════
-- 0163 · las_truncas_descuentan_lo_ya_depositado
-- ══════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════
-- 0164 · la_liquidacion_por_cese_en_una_sola_cuenta
-- ══════════════════════════════════════════════════════════════════════════
-- ============================================================================
-- 0164 — La liquidación por cese, en una sola cuenta
-- ============================================================================
--
-- QUÉ PROMETE
--   Responder «¿cuánto se le debe a esta persona que se va?» con UNA llamada, y
--   que la respuesta se pueda leer línea por línea: de dónde sale cada cifra.
--   La ley da **48 horas** desde el cese para pagar (art. 4 del D.S. 001-97-TR),
--   así que ese cálculo no puede depender de que alguien lo arme a mano un
--   viernes por la tarde.
--
-- QUÉ ASUME
--   · La 0163: las truncas ya descuentan lo que salió del banco. Sin ella, esta
--     función suma un doble pago con más presentación.
--   · `fn_planilla_calcular(ini, fin, periodo_id)` calcula un rango PARCIAL
--     correctamente. Lo hace desde siempre: es lo que usa la pantalla de planilla
--     con el periodo en curso.
--
-- POR QUÉ SE APOYA EN LA PLANILLA EN VEZ DE CALCULAR LO SUYO
--   El sueldo pendiente de quien cesa a mitad de periodo es exactamente lo que la
--   planilla ya sabe calcular: horas × salario / (6.5 × días), más feriados, más
--   movilidad por días marcados, más educación, más asignación familiar, menos
--   pensión, menos descuentos del periodo. Reescribir eso acá daría DOS respuestas
--   a la misma pregunta — y el día que una cambie, la liquidación y la planilla
--   dirían cosas distintas sobre la misma persona y el mismo mes.
--
--   Así que la liquidación llama a la planilla con el rango que va del inicio del
--   periodo a la fecha de cese, y le suma lo que la planilla no calcula porque no
--   es de un periodo: las tres truncas.
--
--   Efecto secundario que vale la pena nombrar: el **día de prueba pagado por
--   horas** sale gratis. Quien entró a prueba y no siguió tiene `tipo_vinculo =
--   'prueba'`, así que `fn_devenga_beneficios` da false y las truncas devuelven
--   cero — pero su `pago_base` por horas lo calcula la planilla igual que a
--   cualquiera. No hizo falta un caso especial.
--
-- QUÉ INCLUYE, Y DE DÓNDE SALE CADA COSA
--   sueldo pendiente, feriados, movilidad, educación, asignación familiar,
--   bonos y descuentos del periodo, descuento de pensión   → fn_planilla_calcular
--   vacaciones truncas                                     → fn_vacaciones_truncas
--   gratificación trunca (neta de lo depositado)           → fn_grati_trunca
--   CTS trunca (neta de lo depositado)                     → fn_cts_trunca
--
-- LO QUE NO HACE
--   No congela nada ni marca nada como pagado: es una consulta. La foto del pago
--   va en la 0165, con el mismo mecanismo que la 0096 le dio a la planilla.
--
-- CÓMO SE REVIERTE
--   drop function fn_liquidacion(uuid, date), fn_liquidaciones_pendientes();
--   No hay cambio de esquema ni de datos.
-- ============================================================================


create or replace function fn_liquidacion(
  p_persona_id uuid,
  p_fecha_cese date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_p        personas%rowtype;
  v_cese     date;
  v_per      periodos_planilla%rowtype;
  v_fila     jsonb;
  v_vac      jsonb;
  v_grati    jsonb;
  v_cts      jsonb;
  v_periodo  numeric := 0;
  v_total    numeric;
begin
  -- El guard va DENTRO, como en las otras cuatro funciones de liquidación: un
  -- revoke se deshace la próxima vez que alguien conceda en masa (0076), y un
  -- guard no. La forma `is not true` es obligatoria: un null no pasa.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  v_cese := coalesce(p_fecha_cese, v_p.fecha_cese);
  if v_cese is null then
    raise exception 'Esa persona no tiene fecha de cese. Regístrala en Equipo antes de liquidar.';
  end if;

  -- El periodo que CONTIENE el cese. Si no hay ninguno —el cese cae fuera de todo
  -- periodo cargado— no se inventa uno: se dice, porque un sueldo pendiente
  -- calculado sobre un rango imaginario es peor que no calcularlo.
  select * into v_per
  from periodos_planilla
  where v_cese between fecha_ini and fecha_fin
  order by fecha_ini desc
  limit 1;

  if found then
    -- Del inicio del periodo a la fecha de cese: ni un día más.
    select value into v_fila
    from jsonb_array_elements(
           fn_planilla_calcular(v_per.fecha_ini, v_cese, v_per.id) -> 'filas'
         ) as t(value)
    where (value->>'persona_id')::uuid = p_persona_id;

    v_periodo := coalesce((v_fila->>'total')::numeric, 0);
  end if;

  v_vac   := fn_vacaciones_truncas(p_persona_id, v_cese);
  v_grati := fn_grati_trunca(p_persona_id, v_cese);
  v_cts   := fn_cts_trunca(p_persona_id, v_cese);

  v_total := v_periodo
           + coalesce((v_vac->>'monto')::numeric, 0)
           + coalesce((v_grati->>'monto')::numeric, 0)
           + coalesce((v_cts->>'monto')::numeric, 0);

  return jsonb_build_object(
    'persona_id',   p_persona_id,
    'persona',      v_p.nombres || ' ' || v_p.apellidos,
    'fecha_ingreso', v_p.fecha_ingreso,
    'fecha_cese',   v_cese,
    'tipo_vinculo', v_p.tipo_vinculo,

    -- El plazo legal, calculado y no recordado. 48 horas desde el cese.
    'vence_el',     (v_cese + 2),
    'dias_restantes', (v_cese + 2 - fn_hoy_lima()),
    'vencido',      (fn_hoy_lima() > v_cese + 2),

    -- El periodo en curso, entero, para que la hoja pueda desglosarlo. Si el cese
    -- cayó fuera de todo periodo cargado, `periodo` viene nulo y el aviso lo dice:
    -- es un dato que falta, no un cero.
    'periodo',      case when v_per.id is null then null else jsonb_build_object(
                      'id', v_per.id, 'desde', v_per.fecha_ini, 'hasta', v_cese,
                      'estado', v_per.estado, 'detalle', v_fila,
                      'monto', round(v_periodo, 2)) end,
    'aviso_periodo', case when v_per.id is null
                       then 'El cese no cae dentro de ningún periodo de planilla cargado: el sueldo pendiente no se pudo calcular y hay que cargarlo.'
                       else null end,

    'vacaciones_truncas',   v_vac,
    'gratificacion_trunca', v_grati,
    'cts_trunca',           v_cts,

    'total', round(v_total, 2)
  );
end;
$$;

grant execute on function fn_liquidacion(uuid, date) to authenticated;


-- ── Quién está esperando su liquidación, y cuánto le queda al plazo ─────────
-- Se arma de quien tiene fecha de cese, no de una lista que alguien mantiene:
-- así aparece sola en cuanto se registra el cese, que es cuando el reloj arranca.
create or replace function fn_liquidaciones_pendientes()
returns table (
  persona_id     uuid,
  persona        text,
  sede           text,
  fecha_ingreso  date,
  fecha_cese     date,
  vence_el       date,
  dias_restantes int,
  vencido        boolean,
  total          numeric,
  pagada         boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_ingreso,
    p.fecha_cese,
    (p.fecha_cese + 2),
    (p.fecha_cese + 2 - fn_hoy_lima())::int,
    (fn_hoy_lima() > p.fecha_cese + 2),
    -- El total se calcula al vuelo. Cuando la 0165 traiga la foto, esta columna
    -- pasará a leerla si existe: lo que se pagó no puede cambiar de cifra sola.
    round(coalesce((fn_liquidacion(p.id, p.fecha_cese)->>'total')::numeric, 0), 2),
    false
  from personas p
  left join sedes s on s.id = p.sede_base_id
  where p.estado = 'inactivo'
    and p.fecha_cese is not null
    and fn_es_admin_o_lider() is true
  order by p.fecha_cese desc;
$$;

grant execute on function fn_liquidaciones_pendientes() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (164, 'la_liquidacion_por_cese_en_una_sola_cuenta')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_n int; v_vencidas int;
begin
  select count(*), count(*) filter (where fn_hoy_lima() > fecha_cese + 2)
    into v_n, v_vencidas
  from personas where estado = 'inactivo' and fecha_cese is not null;

  raise notice '0164 · personas cesadas en el sistema: %', v_n;
  if v_vencidas > 0 then
    raise warning '0164 · % de ellas ya pasaron las 48 horas del art. 4 D.S. 001-97-TR.', v_vencidas;
    raise warning '0164 · Si ya se les pago, no hay nada que hacer: el aviso es sobre el registro, no sobre el pago.';
  end if;
end $mig$;

-- ══════════════════════════════════════════════════════════════════════════
-- 0167 · la_liquidacion_pagada_se_congela
-- ══════════════════════════════════════════════════════════════════════════
-- ============================================================================
-- 0167 — La liquidación pagada se congela, y avisa si deja de cuadrar
-- ============================================================================
--
-- QUÉ PROMETE
--   Que lo que se le pagó a una persona que ya se fue no pueda cambiar de cifra
--   por su cuenta. Al marcar PAGADA se guarda copia intacta de cada concepto; si
--   un recálculo posterior da distinto, el sistema lo DICE en vez de cambiar el
--   número.
--
-- QUÉ ASUME
--   La 0164: `fn_liquidacion` devuelve el cálculo completo con su desglose.
--
-- POR QUÉ ESTO IMPORTA MÁS ACÁ QUE EN LA PLANILLA
--   Un error en la planilla lo reclama quien lo cobra: son 22 personas mirando
--   su boleta todos los meses. Un error en una liquidación no lo reclama nadie —
--   la persona ya no está, no tiene cuenta, y en muchos casos ni sabe cómo se
--   calculó. El único control posible es que la cifra no se mueva sola.
--
--   Y se mueve con facilidad: basta que alguien corrija un marcaje viejo, cargue
--   una vacación con retraso, anote un depósito de CTS que faltaba —o CORRIJA LA
--   FECHA DE CESE, que es el más frecuente de los cuatro— y el mismo
--   `fn_liquidacion` devuelve otra cosa un mes después. Sin foto, no habría forma
--   de saber cuál de las dos cifras se transfirió.
--
--   Ese cuarto motivo faltaba en esta lista, y por faltar acá también se escapó
--   del código: la comparación recalculaba con la fecha CONGELADA, así que era
--   ciega justo al caso más común. Corregido antes de aplicar esta migración —ver
--   el comentario largo dentro de `fn_liquidacion_diferencias`— y fijado por la
--   prueba 133.
--
-- POR QUÉ SE VERSIONA EN VEZ DE SOBRESCRIBIR
--   Mismo criterio que `planilla_pagada_detalle` (0096): si hubo que rehacer un
--   pago, la versión anterior queda como histórico en vez de desaparecer. Dos
--   filas con la fecha en que se congeló cada una explican qué pasó; una fila
--   reescrita no explica nada.
--
-- POR QUÉ LA FOTO GUARDA EL JSONB ENTERO Y ADEMÁS LAS COLUMNAS
--   Las columnas son para consultar y sumar. El `detalle` es para poder REIMPRIMIR
--   la hoja exactamente como se entregó, aunque mañana cambie la plantilla o la
--   fórmula. El papel que la persona firmó tiene que poder reconstruirse tal cual.
--
-- LO QUE NO DECIDE
--   Qué hacer cuando la foto y el cálculo difieren. El sistema lo NOMBRA, persona
--   por persona y concepto por concepto; si se paga la diferencia, se ajusta o se
--   deja constancia, es una decisión de negocio. Misma postura que la 0096 tomó
--   con la planilla, y sigue sin reabrirse acá.
--
-- CÓMO SE REVIERTE
--   drop table liquidacion_pagada;  (se pierden las fotos: no hay vuelta atrás
--   para eso, que es justamente el punto de una foto)
--   drop function fn_liquidacion_pagar(uuid, text), fn_liquidacion_diferencias(uuid);
-- ============================================================================


create table if not exists liquidacion_pagada (
  persona_id     uuid not null references personas(id) on delete restrict,
  version        int  not null,

  congelada_at   timestamptz not null default now(),
  congelada_por  uuid not null references personas(id),
  nota           text,

  -- Los datos de quién y cuándo, copiados: si mañana se corrige la fecha de cese
  -- de esa persona, la foto tiene que seguir diciendo con qué fecha se pagó.
  persona        text not null,
  fecha_ingreso  date,
  fecha_cese     date not null,

  -- Las cuatro líneas, para poder sumar y comparar sin abrir el jsonb.
  monto_periodo  numeric(12,2) not null default 0,
  monto_vacaciones numeric(12,2) not null default 0,
  monto_grati    numeric(12,2) not null default 0,
  monto_cts      numeric(12,2) not null default 0,
  total          numeric(12,2) not null,

  -- El cálculo completo tal como se entregó. Reimprimir la hoja de un pago de
  -- hace un año no puede depender de que la fórmula de hoy dé lo mismo.
  detalle        jsonb not null,

  primary key (persona_id, version)
);

comment on table liquidacion_pagada is
  'Copia intacta de la liquidación con la que se pagó a cada persona que cesó. No '
  'se edita ni se borra: si un recálculo posterior ya no coincide, el sistema lo '
  'dice (fn_liquidacion_diferencias) y la cifra pagada no se mueve. Un error acá '
  'no lo reclama nadie — la persona ya no está.';

alter table liquidacion_pagada enable row level security;

drop policy if exists liquidacion_pagada_lectura on liquidacion_pagada;
create policy liquidacion_pagada_lectura on liquidacion_pagada
  for select to authenticated
  using (fn_es_admin_o_lider() is true or persona_id = fn_persona_actual_id());

-- La escritura no se concede: pasa por función, como marcajes, expedientes y
-- salarios. Y una vez escrita, ni el propio DO la toca.
create or replace function fn_trg_liquidacion_es_inmutable()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'La liquidación con la que se pagó no se modifica ni se borra. Si el cálculo '
    'estaba mal, vuelve a marcarla como pagada: se guarda una versión nueva y esta '
    'queda como histórico, con la fecha en que se congeló cada una.';
end;
$$;

drop trigger if exists trg_liquidacion_pagada_inmutable on liquidacion_pagada;
create trigger trg_liquidacion_pagada_inmutable
  before update or delete on liquidacion_pagada
  for each row execute function fn_trg_liquidacion_es_inmutable();


-- ── Congelar ───────────────────────────────────────────────────────────────
create or replace function fn_liquidacion_pagar(p_persona_id uuid, p_nota text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_l   jsonb;
  v_ver int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder marca una liquidación como pagada.';
  end if;

  -- Se congela lo que la función calcula AHORA, no un número que venga de la
  -- pantalla: si el monto viajara desde el navegador, la foto podría guardar algo
  -- que el sistema nunca calculó — y sería indistinguible de un cálculo real.
  v_l := fn_liquidacion(p_persona_id, null);

  select coalesce(max(version), 0) + 1 into v_ver
  from liquidacion_pagada where persona_id = p_persona_id;

  insert into liquidacion_pagada (
    persona_id, version, congelada_por, nota,
    persona, fecha_ingreso, fecha_cese,
    monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle
  ) values (
    p_persona_id, v_ver, fn_persona_actual_id(), nullif(trim(coalesce(p_nota, '')), ''),
    v_l->>'persona',
    (v_l->>'fecha_ingreso')::date,
    (v_l->>'fecha_cese')::date,
    coalesce((v_l->'periodo'->>'monto')::numeric, 0),
    coalesce((v_l->'vacaciones_truncas'->>'monto')::numeric, 0),
    coalesce((v_l->'gratificacion_trunca'->>'monto')::numeric, 0),
    coalesce((v_l->'cts_trunca'->>'monto')::numeric, 0),
    (v_l->>'total')::numeric,
    v_l
  );

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'liquidacion_pagada', null,
     'S/' || to_char((v_l->>'total')::numeric, 'FM999999.00') || ' · version ' || v_ver,
     fn_persona_actual_id(),
     coalesce(nullif(trim(coalesce(p_nota, '')), ''), 'Liquidación marcada como pagada'));

  return jsonb_build_object('version', v_ver, 'total', (v_l->>'total')::numeric);
end;
$$;

grant execute on function fn_liquidacion_pagar(uuid, text) to authenticated;


-- ── ¿Sigue cuadrando? ──────────────────────────────────────────────────────
-- Nombra la diferencia concepto por concepto. Un «no cuadra» sin decir dónde
-- obliga a rehacer la cuenta entera a mano, que es lo que esto viene a evitar.
create or replace function fn_liquidacion_diferencias(p_persona_id uuid)
returns table (
  concepto  text,
  pagado    numeric,
  ahora     numeric,
  diferencia numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_f       liquidacion_pagada%rowtype;
  v_l       jsonb;
  v_cese_hoy date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede comparar una liquidación.';
  end if;

  select * into v_f from liquidacion_pagada
   where persona_id = p_persona_id
   order by version desc limit 1;
  if not found then return; end if;   -- sin foto no hay nada que comparar

  -- ⇩⇩⇩ SE RECALCULA CON LA FECHA DE CESE DE HOY, NO CON LA CONGELADA.
  --
  -- Acá decía `fn_liquidacion(p_persona_id, v_f.fecha_cese)`, o sea que volvía a
  -- calcular con la MISMA fecha con la que se pagó. Con eso la comparación no
  -- podía ver el caso más frecuente de todos: que alguien corrija el último día
  -- que la persona trabajó.
  --
  -- Medido contra el Postgres local el 2026-08-06, con una persona real de
  -- laboratorio: se paga con cese el 15/06 → S/ 3,444.31. Se descubre que trabajó
  -- hasta el 20/06 y se corrige la fecha. Le corresponden S/ 3,465.60, o sea
  -- S/ 21.29 más. `fn_liquidacion_diferencias` devolvía CERO filas y la pantalla
  -- mostraba `descuadra = false`: la fila quedaba diciendo «cesó el 20/06 ·
  -- S/ 3,444.31 · cuadra», y esas tres cosas no pueden ser ciertas a la vez.
  --
  -- La cabecera de esta migración enumera tres motivos por los que un recálculo
  -- puede dar distinto —un marcaje corregido, una vacación cargada tarde, un
  -- depósito de CTS anotado después— y la fecha de cese no estaba en la lista.
  -- Se quedó fuera por olvido, no por decisión.
  --
  -- LA FOTO NO SE TOCA: sigue guardando la fecha con la que se pagó, que es lo
  -- que hay que poder reimprimir. Lo que cambia es contra qué se compara, y para
  -- responder «¿cuánto le debemos HOY?» la fecha buena es la de hoy.
  --
  -- El `coalesce` es para quien fue reactivada: al volver a estado activo el
  -- esquema le exige `fecha_cese` en null (constraint `personas_cese_coherente`),
  -- y sin este respaldo `fn_liquidacion` abortaría con «no tiene fecha de cese».
  -- Un error ahí dejaría la lista de pendientes sin cargar entera por una sola
  -- persona.
  select p.fecha_cese into v_cese_hoy from personas p where p.id = p_persona_id;
  v_l := fn_liquidacion(p_persona_id, coalesce(v_cese_hoy, v_f.fecha_cese));

  -- La diferencia se calcula acá y no en la pantalla: es la cifra que alguien va
  -- a mirar para decidir si paga un ajuste, y no debería depender de una resta
  -- hecha en el navegador.
  return query
  select t.concepto, t.pagado, t.ahora, round(t.ahora - t.pagado, 2)
  from (values
    ('Sueldo del periodo', v_f.monto_periodo,    coalesce((v_l->'periodo'->>'monto')::numeric, 0)),
    ('Vacaciones truncas', v_f.monto_vacaciones, coalesce((v_l->'vacaciones_truncas'->>'monto')::numeric, 0)),
    ('Gratificación trunca', v_f.monto_grati,    coalesce((v_l->'gratificacion_trunca'->>'monto')::numeric, 0)),
    ('CTS trunca',         v_f.monto_cts,        coalesce((v_l->'cts_trunca'->>'monto')::numeric, 0)),
    ('TOTAL',              v_f.total,            coalesce((v_l->>'total')::numeric, 0))
  ) as t(concepto, pagado, ahora)
  where round(t.pagado, 2) <> round(t.ahora, 2);
end;
$$;

grant execute on function fn_liquidacion_diferencias(uuid) to authenticated;


-- ── La lista pendiente ahora sabe qué se pagó ──────────────────────────────
-- Si hay foto, el total que se muestra es el CONGELADO, no el recalculado: lo
-- que se transfirió no puede cambiar de cifra en pantalla.
--
-- El drop es obligatorio: se le agregan dos columnas al retorno, y `create or
-- replace` no puede cambiar el tipo de retorno de una función que ya existe
-- («cannot change return type of existing function»). Sin esto, pegar la
-- migración en una base que ya tiene la 0164 aborta.
drop function if exists fn_liquidaciones_pendientes();

create or replace function fn_liquidaciones_pendientes()
returns table (
  persona_id     uuid,
  persona        text,
  sede           text,
  fecha_ingreso  date,
  fecha_cese     date,
  vence_el       date,
  dias_restantes int,
  vencido        boolean,
  total          numeric,
  pagada         boolean,
  descuadra      boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_ingreso,
    p.fecha_cese,
    (p.fecha_cese + 2),
    (p.fecha_cese + 2 - fn_hoy_lima())::int,
    (fn_hoy_lima() > p.fecha_cese + 2 and f.persona_id is null),
    round(coalesce(f.total, (fn_liquidacion(p.id, p.fecha_cese)->>'total')::numeric, 0), 2),
    (f.persona_id is not null),
    (f.persona_id is not null
      and exists (select 1 from fn_liquidacion_diferencias(p.id)))
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select lp.* from liquidacion_pagada lp
    where lp.persona_id = p.id order by lp.version desc limit 1
  ) f on true
  where p.estado = 'inactivo'
    and p.fecha_cese is not null
    and fn_es_admin_o_lider() is true
  order by (f.persona_id is not null), p.fecha_cese desc;
$$;

grant execute on function fn_liquidaciones_pendientes() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (167, 'la_liquidacion_pagada_se_congela')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_n int;
begin
  select count(*) into v_n from liquidacion_pagada;
  raise notice '0167 · liquidaciones congeladas: % (la tabla nace vacia)', v_n;
  raise notice '0167 · esta migracion no cambia ningun calculo: solo permite guardar el que se pago.';
end $mig$;

-- ══════════════════════════════════════════════════════════════════════════
-- 0169 · un_mes_en_prueba_deja_de_ser_gratis
-- ══════════════════════════════════════════════════════════════════════════
-- ============================================================================
-- 0169 — Un mes en «prueba» deja de ser gratis, y el sistema lo dice
-- ============================================================================
--
-- QUÉ PROMETE
--   Que nadie se quede en el vínculo `prueba` más de un mes sin que alguien se
--   entere. Pasado ese mes, la etiqueta empieza a costar dinero real y hoy no
--   hay nada que lo señale.
--
-- QUÉ ASUME
--   La decisión de Felipe del 2026-07-26, registrada en la cabecera de la 0085:
--   `prueba` NO devenga beneficios. Esta migración **no la revierte** — la hace
--   visible cuando deja de ser inocua.
--
-- POR QUÉ HACE FALTA, Y POR QUÉ RECIÉN AHORA
--   La 0085 dejó escrito el argumento legal completo: en la ley peruana el
--   periodo de prueba no es un vínculo distinto, es un contrato de trabajo
--   común, y quien presta servicios va a planilla desde el primer día. Se le
--   informó a Felipe y decidió que `prueba` no devengara, con este razonamiento
--   textual: «que por los mínimos legales casi siempre daría cero de todas
--   formas».
--
--   Ese «casi siempre» es la clave, y tiene una fecha de caducidad exacta. Las
--   tres funciones de truncas —CTS, gratificación y vacaciones— exigen **un mes
--   de servicios** por su cuenta: por debajo de eso devuelven cero devengue o no
--   devengue el vínculo. O sea que la decisión no costaba nada mientras «prueba»
--   significara unos días.
--
--   El 2026-08-05 se vio el caso que rompe el supuesto: una persona llevaba diez
--   días como `prueba` y seguía trabajando. Al cumplir el mes, el sistema
--   empezaría a decir que no devenga algo que legalmente sí devenga — y nadie se
--   enteraría hasta que cesara y su liquidación saliera en cero.
--
-- POR QUÉ UN AVISO Y NO UN CAMBIO DE REGLA
--   Cambiar `fn_devenga_beneficios` es una línea, pero revierte una decisión que
--   Felipe tomó informado y con su fecha. El sistema no revierte decisiones de
--   negocio por su cuenta: las hace visibles cuando cambian los hechos que las
--   sostenían. La decisión de qué hacer —pasar a planilla, cesar y recontratar, o
--   cambiar la regla— sigue siendo suya, y ahora la toma a tiempo.
--
-- POR QUÉ MIDE DESDE `fecha_ingreso` Y NO DESDE EL PRIMER MARCAJE
--   La antigüedad corre con el contrato, no con la asistencia: alguien ausente
--   con permiso sigue acumulando. Medirlo por marcajes diría que el reloj se
--   detiene cuando alguien falta, y no se detiene.
--
-- CÓMO SE REVIERTE
--   drop function fn_avisos_vinculo();  No hay cambio de esquema ni de datos, y
--   ninguna otra función depende de ella.
-- ============================================================================


create or replace function fn_avisos_vinculo()
returns table (
  persona_id    uuid,
  persona       text,
  sede          text,
  tipo_vinculo  text,
  fecha_ingreso date,
  dias          int,
  cumple_el_mes date,
  ya_devenga    boolean,
  aviso         text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.tipo_vinculo,
    p.fecha_ingreso,
    (fn_hoy_lima() - p.fecha_ingreso)::int,
    (p.fecha_ingreso + interval '1 month')::date,
    (fn_hoy_lima() >= (p.fecha_ingreso + interval '1 month')::date),
    case
      when fn_hoy_lima() >= (p.fecha_ingreso + interval '1 month')::date then
        'Lleva más de un mes como «prueba». Desde el '
        || to_char((p.fecha_ingreso + interval '1 month')::date, 'DD/MM/YYYY')
        || ' devenga CTS, gratificación y vacaciones que el sistema NO está calculando, '
        || 'porque el vínculo «prueba» no devenga (decisión del 26/07/2026). '
        || 'Pásala a «planilla» en Equipo, o revisa si corresponde registrar su cese.'
      else
        'Cumple un mes el '
        || to_char((p.fecha_ingreso + interval '1 month')::date, 'DD/MM/YYYY')
        || '. Hasta entonces la etiqueta «prueba» no le quita nada: las truncas '
        || 'exigen un mes de servicios de todas formas.'
    end
  from personas p
  left join sedes s on s.id = p.sede_base_id
  where p.estado = 'activo'
    and p.tipo_vinculo = 'prueba'
    and fn_es_admin_o_lider() is true
  order by p.fecha_ingreso;
$$;

comment on function fn_avisos_vinculo() is
  'Quién sigue en el vínculo «prueba» y desde cuándo. La decisión de que «prueba» '
  'no devengue beneficios (0085, 26/07/2026) se tomó porque por debajo de un mes '
  'las truncas dan cero igual. Pasado el mes deja de ser cierto, y esto lo dice.';

grant execute on function fn_avisos_vinculo() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (169, 'un_mes_en_prueba_deja_de_ser_gratis')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare r record;
begin
  for r in select * from fn_avisos_vinculo() loop
    if r.ya_devenga then
      raise warning '0169 · % lleva % dias como prueba: YA devenga beneficios que no se calculan.', r.persona, r.dias;
    else
      raise notice '0169 · % lleva % dias como prueba (cumple el mes el %).', r.persona, r.dias, r.cumple_el_mes;
    end if;
  end loop;
end $mig$;
