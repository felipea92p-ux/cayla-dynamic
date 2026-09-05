-- ============================================================================
-- 0343 — Un adelanto de beneficio no se vuelve a calcular solo.
-- ============================================================================
--
-- QUÉ PROMETE
--
--   1 · Una puerta para registrar un adelanto de gratificación, CTS o
--       vacaciones pagado FUERA del ciclo normal —típicamente a alguien que
--       cesa a mitad de semestre— en `desembolsos_beneficios`, la tabla que
--       ya existe para esto desde la 0155 pero que hasta hoy nadie podía
--       escribir: tiene RLS con SOLO lectura, y ninguna pantalla la usa.
--   2 · Que `fn_grati_trunca_bruta` reconozca, además del adelanto anotado en
--       el libro, uno cargado como bono manual en `movimientos_planilla` con
--       categoria='gratificacion' — para quien de todas formas siga usando
--       ese camino en vez de la puerta nueva.
--
-- ── EL CASO QUE LO DISPARÓ ───────────────────────────────────────────────────
--
--   Paola Cahuana cesó el 28/08/2026, a mitad del semestre julio-diciembre.
--   Se le dio a mano un adelanto de su gratificación truncada, S/102.63,
--   cargado como bono con categoria='otros' —porque la única opción
--   'gratificacion' del desplegable calcula el monto SOLA, para el periodo
--   del pago legal de julio o diciembre, y agosto no es ninguno de los dos—.
--   Al armar la liquidación, `fn_grati_trunca_bruta` no tenía forma de saber
--   que ese adelanto existía —ni buscándolo en el libro (nadie podía
--   escribir ahí) ni en movimientos_planilla (solo miraba la ventana del pago
--   legal, dic/jul)— y recalculó la gratificación entera otra vez: S/102.65.
--   Se le pagó dos veces lo mismo.
--
-- ── PARTE 1 · LA PUERTA (`fn_registrar_desembolso`) ─────────────────────────
--
--   `desembolsos_beneficios` (0155) ya tiene todo lo que hace falta: la
--   columna `ventana` distingue grati_s1/grati_s2/cts_may/cts_nov/vacaciones,
--   y `fn_grati_trunca` (el envoltorio, 0163), `fn_cts_trunca` y
--   `fn_vacaciones_truncas` (0341) YA restan de ahí antes de esta migración.
--   El hueco nunca fue el cálculo: fue que nadie podía escribir la fila.
--
--   Se sigue el mismo molde que `fn_agregar_movimiento` (0305): guard de
--   admin/líder DENTRO de la función, una validación explícita por cada CHECK
--   de la tabla con su mensaje en español, y `registrado_por` desde
--   `fn_persona_actual_id()` — nunca un uuid que mande el cliente.
--
-- ── PARTE 2 · LA VENTANA DE `fn_grati_trunca_bruta` SE ENSANCHA ─────────────
--
--   Hoy solo reconoce un pago de gratificación si su periodo cierra DENTRO de
--   la ventana del pago legal (el mes de julio o de diciembre) — diseñado a
--   propósito así en la 0289 para no confundir el pago de un semestre con el
--   del otro. Un adelanto de mitad de semestre, por definición, nunca cae ahí.
--
--   Se agrega una SEGUNDA condición, que solo puede activarse cuando la
--   PRIMERA es estructuralmente imposible — cuando la persona cesa ANTES de
--   que llegue la fecha legal de pago de ese semestre (`p_fecha_cese <
--   v_pago_legal`; si ya llegó, es la ventana normal la que manda, sin tocar
--   nada) —: busca un movimiento categoria='gratificacion' cuyo periodo
--   EMPIECE dentro del semestre que se está evaluando (`pp.fecha_ini >=
--   v_sem`) y cierre antes o el mismo día del cese.
--
--   `pp.fecha_ini >= v_sem`, y no `pp.fecha_fin >= v_sem`, es la línea que
--   evita el accidente que se probó primero y falló: el pago normal de
--   enero-junio se deposita el 15 de julio, dentro de un periodo que
--   EMPIEZA el 29 de junio (antes del semestre julio-diciembre) pero CIERRA
--   el 28 de julio (dentro de él). Sin el `fecha_ini`, ese mismo movimiento
--   se colaba como si fuera también un adelanto de julio-diciembre, y
--   alguien que cesara en agosto dejaba de cobrar su trunco de julio —
--   exactamente el defecto que la 0289 ya había cerrado, reabierto por otra
--   puerta. Con `fecha_ini >= v_sem` ese periodo (29/06) queda afuera del
--   semestre de julio (01/07) y el caso vuelve a pasar.
--
-- QUÉ ASUME
--
--   · `fn_grati_trunca_bruta` en su versión de la 0289 — la vigente real,
--     NO la 0163 que `donde-vive.sh fn_grati_trunca` (el envoltorio, función
--     distinta) hace parecer la última. Confirmado aparte con
--     `donde-vive.sh fn_grati_trunca_bruta`.
--   · Que `desembolsos_beneficios` sigue con RLS `revoke all` desde la 0155:
--     esta migración no le toca la política de RLS ni el grant de tabla —
--     escribe solo por el RPC nuevo, `security definer`, igual que
--     `movimientos_planilla` desde la 0025.
--   · Que ningún otro sitio del repo lee `semestres_no_cobrados` fuera del
--     envoltorio `fn_grati_trunca` (comprobado con grep global antes de
--     escribir) — así que mientras la lista siga siendo strings "MM/AAAA",
--     agregar una segunda vía de detección adentro no rompe nada aguas abajo.
--
-- QUÉ MUEVE AL PEGARSE
--
--   Ningún pago existente cambia: `fn_registrar_desembolso` es una función
--   nueva, sin llamadas todavía, y la condición nueva de
--   `fn_grati_trunca_bruta` solo se activa si YA existe un movimiento
--   categoria='gratificacion' con las fechas exactas — hoy nadie tiene uno
--   así cargado dentro de un semestre en curso (el único caso real, Paola,
--   ya cesó y su bono quedó con categoria='otros', así que ni siquiera a
--   ella la toca esta migración retroactivamente).
--
-- CÓMO SE REVIERTE
--   drop function fn_registrar_desembolso(uuid, text, int, numeric, date, text, text);
--   Y volver a pegar fn_grati_trunca_bruta desde la 0289, tal cual.
-- ============================================================================


-- ── 1 · La puerta ────────────────────────────────────────────────────────────
create or replace function fn_registrar_desembolso(
  p_persona_id uuid,
  p_ventana    text,
  p_anio       int,
  p_monto      numeric,
  p_fecha_pago date,
  p_origen     text,
  p_nota       text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  -- El guard va DENTRO, no como un revoke aparte — mismo criterio que todas
  -- las funciones de liquidación desde la 0129: un revoke se deshace la
  -- próxima vez que alguien conceda permisos en masa, y un guard no.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un desembolso.';
  end if;

  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;

  -- Cada CHECK de la tabla, validado acá con su propio mensaje: un error de
  -- Postgres crudo ("violates check constraint") no le dice a quien lo lee
  -- cuál de las cinco ventanas escribió mal.
  if p_ventana not in ('grati_s1','grati_s2','cts_may','cts_nov','vacaciones') then
    raise exception 'Ventana inválida: tiene que ser grati_s1, grati_s2, cts_may, cts_nov o vacaciones.';
  end if;
  if p_anio < 2020 or p_anio > 2100 then
    raise exception 'El año tiene que estar entre 2020 y 2100.';
  end if;
  if p_monto <= 0 then
    raise exception 'El monto tiene que ser mayor a 0.';
  end if;
  if p_origen not in ('plame','transferencia','otro') then
    raise exception 'Origen inválido: tiene que ser plame, transferencia u otro.';
  end if;

  insert into desembolsos_beneficios
    (persona_id, ventana, anio, monto, fecha_pago, origen, nota, registrado_por)
  values
    (p_persona_id, p_ventana, p_anio, p_monto, p_fecha_pago, p_origen, p_nota, fn_persona_actual_id())
  returning id into v_id;

  return v_id;
end;
$$;

comment on function fn_registrar_desembolso(uuid, text, int, numeric, date, text, text) is
  'Única puerta para escribir en desembolsos_beneficios (0155), que hasta la '
  '0343 solo se podía llenar por SQL directo. Para un adelanto de gratificación, '
  'CTS o vacaciones pagado fuera del ciclo normal de planilla — típicamente a '
  'alguien que cesa a mitad de semestre. fn_grati_trunca, fn_cts_trunca y '
  'fn_vacaciones_truncas ya restan de esta tabla desde antes; el hueco era '
  'que nadie podía escribir la fila (0343).';

grant  execute on function fn_registrar_desembolso(uuid, text, int, numeric, date, text, text) to authenticated;
revoke execute on function fn_registrar_desembolso(uuid, text, int, numeric, date, text, text) from public, anon;


-- ── 2 · fn_grati_trunca_bruta reconoce también el adelanto de mitad de semestre ─
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
  v_pago_legal date;   -- CAMBIO 0289
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
      v_pago_legal := (v_sem + interval '6 months' + interval '14 days')::date;  -- 15 jul
    else
      v_pago_ini := (v_sem + interval '5 months')::date;   -- 1 dic
      v_pago_fin := (v_sem + interval '7 months')::date;   -- 1 feb
      v_pago_legal := (v_sem + interval '5 months' + interval '14 days')::date;  -- 15 dic
    end if;

    if not exists (
      select 1 from movimientos_planilla mp
      join periodos_planilla pp on pp.id = mp.periodo_id
      where mp.persona_id = p_persona_id
        and mp.categoria = 'gratificacion'
        and (
          -- La ventana normal: el pago legal del semestre, sin cambios desde
          -- la 0289 (ver su propio comentario, más abajo intacto).
          (pp.fecha_fin >= v_pago_ini
           and pp.fecha_fin <  v_pago_fin
           and p_fecha_cese >= v_pago_legal)
          -- ⇩⇩⇩ CAMBIO 0343 ⇩⇩⇩ EL ADELANTO DE MITAD DE SEMESTRE.
          --
          -- Solo entra en juego cuando la ventana normal es estructuralmente
          -- imposible: la persona cesó ANTES de que llegara la fecha legal de
          -- pago de ESTE semestre, así que un pago "normal" para comparar
          -- nunca va a existir — se fue antes de que le tocara.
          --
          -- `pp.fecha_ini >= v_sem`, y no `pp.fecha_fin >= v_sem`, es la parte
          -- que no se puede aflojar: el pago normal de enero-junio se
          -- deposita el 15/07, dentro de un periodo que EMPIEZA el 29/06
          -- (antes de este semestre) pero CIERRA el 28/07 (dentro de él). Sin
          -- exigir que el periodo también EMPIECE dentro del semestre, ese
          -- mismo movimiento de julio se cuela como si fuera también un
          -- adelanto de julio-diciembre, y alguien que cesa en agosto deja de
          -- cobrar su trunco de julio — reabriendo el defecto que la 0289 ya
          -- había cerrado, por otra puerta. Probado contra la prueba 225: sin
          -- este `fecha_ini`, su aserción 3 se rompe.
          or (p_fecha_cese < v_pago_legal
              and pp.fecha_ini >= v_sem
              and pp.fecha_fin <= p_fecha_cese)
        )
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

revoke all on function fn_grati_trunca_bruta(uuid, date) from public, anon, authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (343, 'un_adelanto_de_beneficio_no_se_vuelve_a_calcular_solo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $fin$
begin
  raise notice '0343 · el libro de desembolsos ya tiene puerta, y un adelanto de mitad de semestre ya no se duplica.';
end $fin$;
