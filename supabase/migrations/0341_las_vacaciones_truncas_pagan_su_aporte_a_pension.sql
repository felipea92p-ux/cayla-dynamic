-- ============================================================================
-- 0341 — Las vacaciones truncas pagan su aporte a pensión.
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que `fn_vacaciones_truncas` le descuente AFP/ONP al monto que calcula,
--   con la misma tasa y el mismo criterio de vigencia que ya usa
--   `fn_planilla_calcular` para el sueldo regular. Hoy no descuenta nada.
--
-- EL DEFECTO, MEDIDO CONTRA UN CASO REAL (Paola Cahuana, cese 28/08/2026)
--
--   `fn_liquidacion` suma tres truncas al total: vacaciones, gratificación y
--   CTS. Las tres pasan por `fn_vacaciones_truncas`, `fn_grati_trunca` y
--   `fn_cts_trunca`, y NINGUNA de las tres menciona AFP ni pensión en su
--   cuerpo — comprobado con grep contra las tres funciones vigentes.
--
--   Eso es correcto para dos de las tres: la gratificación está inafecta a
--   aportes por la Ley 29351/30334 (por eso existe el bono extraordinario del
--   9%, que la reemplaza), y la CTS lo está por el art. 9 del D.S. 001-97-TR.
--   Pero las vacaciones truncas NO están exentas — sustituyen el sueldo del
--   descanso que no se llegó a gozar, y el art. 19 del D.S. 001-97-TR no las
--   lista entre los conceptos no remunerativos. Confirmado contra fuente
--   externa (afpintegra.pe, sbs.gob.pe): sí llevan aporte a pensión, igual
--   que cualquier mes trabajado.
--
--   Medido en la liquidación real de Cahuana: sus S/346.91 de vacaciones
--   truncas se pagaron enteras, sin el ~11-13% que le correspondía a su AFP.
--   Sobre esa base y con su tasa (Integra), son ~S/27 de aporte que nunca
--   llegó a su fondo de pensión — se quedaron en su liquidación en efectivo
--   en su lugar. No es una propina: es un aporte previsional que no se hizo.
--
-- QUÉ ASUME
--
--   · `fn_vacaciones_truncas` en su versión de la 0297 — de la que se copia
--     el cuerpo completo, sin tocar nada de la lógica de días/récords/goces
--     que esa migración ya dejó correcta.
--   · La tasa se busca EXACTAMENTE como en `fn_planilla_calcular` (0339,
--     CAMBIO 0114/0261/0262): el régimen vigente en la fecha del CESE (no en
--     el fin de un periodo de planilla, porque una liquidación no tiene
--     periodo) vía `asignaciones_regimen_pension`, con `personas.regimen_pension`
--     como respaldo; y sobre ese régimen, la tasa vigente en esa misma fecha
--     en `tasas_pension` (aporte + comisión + prima), con
--     `configuracion.tasa_afp` como último respaldo si a alguien le falta
--     historial — el mismo respaldo con el que hoy TODOS los test personas sin
--     régimen asignado ya resuelven a 0, así que ninguna prueba existente se
--     mueve por esto.
--   · Se copia la lógica de tasa en vez de extraerla a una función compartida
--     a propósito: `fn_planilla_calcular` es un solo bloque SECURITY DEFINER
--     enorme (0339) y partirle una pieza para acá es más riesgo del que
--     ahorran estas quince líneas repetidas. Si el día de mañana esta misma
--     búsqueda se necesita una tercera vez, ESE es el momento de extraerla.
--
-- QUÉ MUEVE AL PEGARSE
--
--   El monto de vacaciones truncas de CUALQUIER liquidación calculada desde
--   hoy en adelante baja, para quien tenga régimen de pensión asignado y una
--   tasa vigente distinta de cero. Las liquidaciones YA PAGADAS (como la de
--   Cahuana) no se tocan — esto no revierte nada retroactivo, solo corrige el
--   cálculo hacia adelante. `fn_liquidacion` no necesita cambiar: sigue
--   sumando `->>'monto'`, que ahora ya viene neto.
--
--   El desglose se expone, no se esconde: se agregan `monto_bruto`,
--   `descuento_afp` y `tasa_afp` al jsonb de salida —aditivo, nada de lo que
--   la pantalla ya lee cambia de nombre— para que la hoja de liquidación
--   pueda mostrar el descuento en vez de solo un número más chico sin
--   explicación (el mismo criterio de la 0100: «un cero no explica nada»).
--
-- CÓMO SE REVIERTE
--   Volver a pegar fn_vacaciones_truncas desde la 0297, tal cual.
-- ============================================================================

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
  v_anios int; v_trunco numeric; v_ya_pagado numeric := 0; v_a int;
  v_vencidos int := 0; v_saldo jsonb;
  v_regimen_pension text; v_tasa_afp numeric; v_descuento_afp numeric;   -- CAMBIO 0341
  v_monto_bruto numeric;                                                -- CAMBIO 0341
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

  -- ⇩ CAMBIO 0278 ⇩ Pide SU ventana. Antes recibía la de la gratificación
  -- (ene-jun / jul-dic) y la suya va de noviembre a abril y de mayo a octubre.
  v_rc := fn_remuneracion_computable(p_persona_id, p_fecha_cese, 'vacaciones');
  if v_rc ? 'error' then return jsonb_build_object('aplica', false, 'monto', 0, 'motivo', v_rc->>'error'); end if;
  v_base := (v_rc->>'total')::numeric;

  -- ⇩⇩⇩ CAMBIO 0283 ⇩⇩⇩ SE CUENTA TODA SU VIDA, NO SOLO EL RECORD EN CURSO.
  --
  -- Antes esta cuenta empezaba en el ultimo aniversario y miraba solo el
  -- trunco. Dos cosas se caian por ese borde:
  --
  --   1 · LOS RECORDS COMPLETOS SIN GOZAR no aparecian en ninguna linea de la
  --       hoja. Quien tenia dos anios sin tomar vacaciones cobraba el trunco y
  --       nada mas: 30 dias se evaporaban.
  --
  --   2 · Y al reves, el que mas dolia: los dias que gano en el record ANTERIOR
  --       y se tomo DESPUES de su aniversario -que es cuando la ley manda
  --       tomarlos- caian dentro de la ventana y se le restaban del record
  --       NUEVO. Medido el 2026-08-22 con dos personas identicas: la que gozo
  --       sus 15 dias cobraba S/0,00 y la que nunca gozo, S/812,50. Se le
  --       cobraba el mismo descanso dos veces, y solo a quien lo tomo.
  --
  -- LA CUENTA ACUMULADA NO PUEDE PAGAR DOS VECES, y esa es la razon de que sea
  -- esta y no un reparto por records. Cada dia que la persona se tomo en su
  -- vida se resta UNA vez del total que gano en su vida. No hay ventana donde
  -- un dia pueda caer fuera y quedar sin descontar, ni donde pueda caer dos
  -- veces. Es la misma cuenta que la pantalla de Vacaciones usa desde julio de
  -- 2026; lo que faltaba era que la liquidacion preguntara igual.
  --
  -- LO QUE ASUME, Y SE COMPROBO ANTES DE ESCRIBIRLO: que el historial de goces
  -- esta completo. Si alguien se tomo vacaciones y no estan registradas, esta
  -- cuenta se las pagaria como si nunca las hubiera gozado. Medido en
  -- produccion el 2026-08-22: de las 20 personas activas, las cuatro que han
  -- cumplido un anio se tomaron EXACTAMENTE sus 15 dias -15 ganados, 15
  -- gozados, saldo cero las cuatro- y las 16 restantes no han cumplido el
  -- primer anio. Nadie tiene saldo pendiente. El historial cuadra.
  -- ⇩⇩⇩ CAMBIO 0297 ⇩⇩⇩ El saldo se PREGUNTA, no se recalcula acá.
  --
  -- El cuerpo que estaba en estas lineas se mudo entero a fn_vacaciones_saldo,
  -- sin cambiarle una coma: los mismos dias ganados sobre toda la vida, los
  -- mismos gozados contados desde el ingreso sobre la vista `vacaciones`.
  --
  -- Se mudo porque el aviso preventivo necesita exactamente esta cuenta, y una
  -- segunda copia es como nacio el defecto que la 0283 vino a arreglar: la
  -- pantalla y la liquidacion contando distinto, S/905,38 medidos entre tres
  -- personas.
  v_saldo   := fn_vacaciones_saldo(p_persona_id, p_fecha_cese);
  v_anios   := (v_saldo->>'anios_completos')::int;
  v_ganados := (v_saldo->>'dias_ganados')::numeric;
  v_tomados := (v_saldo->>'dias_gozados')::numeric;
  v_pend    := (v_saldo->>'dias_pendientes')::numeric;
  v_trunco  := round(15.0 * v_m / 12.0 + 15.0 * v_d / 360.0, 2);
  v_monto := round((v_base / 2.0) * v_pend / 15.0, 2);

  -- ⇩⇩⇩ CAMBIO 0283 ⇩⇩⇩ LO QUE EL LIBRO DICE QUE YA SE PAGO.
  --
  -- `fn_grati_trunca` y `fn_cts_trunca` descuentan el libro de desembolsos
  -- desde la 0163. Esta no, aunque el libro TIENE ventana 'vacaciones' en su
  -- check desde la 0121. Hoy no cuesta nada -no hay ninguna anotada- pero
  -- dejarlo asi mientras esta migracion empieza a pagar records completos es
  -- abrir la puerta al doble pago justo cuando hay algo que duplicar.
  --
  -- El anio es el del PAGO, mismo criterio que las otras dos. Se recorren los
  -- anios que la persona pudo cobrar vacaciones, desde su ingreso hasta el cese.
  for v_a in extract(year from v_p.fecha_ingreso)::int .. extract(year from p_fecha_cese)::int loop
    v_ya_pagado := v_ya_pagado + fn_beneficio_ya_depositado(p_persona_id, 'vacaciones', v_a);
  end loop;
  v_monto := greatest(0, round(v_monto - v_ya_pagado, 2));

  -- ⇩⇩⇩ CAMBIO 0341 ⇩⇩⇩ LAS VACACIONES TRUNCAS SÍ LLEVAN APORTE A PENSIÓN.
  --
  -- Sustituyen el sueldo del descanso que no se llegó a gozar, y el art. 19
  -- del D.S. 001-97-TR no las lista entre los conceptos no remunerativos: son
  -- remuneración computable para pensión igual que cualquier mes trabajado.
  -- (`fn_grati_trunca` y `fn_cts_trunca` correctamente NO descuentan — la
  -- gratificación está inafecta por la Ley 29351/30334 y la CTS por el art. 9
  -- del mismo D.S. — así que de las tres truncas, esta era la única que sí
  -- debía llevar el descuento y no lo llevaba.)
  --
  -- Se descuenta sobre lo que queda DESPUÉS de restar lo ya pagado por el
  -- libro, no antes: lo ya pagado es una transferencia que ya ocurrió, con
  -- cualquier tratamiento que haya tenido en su momento, y el aporte de HOY
  -- corresponde solo a la plata que se está desembolsando en ESTA liquidación.
  --
  -- La tasa se busca exactamente como en fn_planilla_calcular (0339): régimen
  -- vigente en la fecha (acá, el cese) vía asignaciones_regimen_pension con
  -- personas.regimen_pension de respaldo, y sobre ese régimen, la tasa
  -- vigente en esa misma fecha en tasas_pension, con configuracion.tasa_afp
  -- como último respaldo. Nadie se queda sin descuento por un dato faltante,
  -- y quien no tenga régimen asignado resuelve a la tasa global (hoy 0, por
  -- eso ninguna prueba existente de esta función se mueve con este cambio).
  v_monto_bruto := v_monto;

  select coalesce(
           (select h.regimen
              from asignaciones_regimen_pension h
             where h.persona_id = p_persona_id
               and h.vigente_desde <= p_fecha_cese
               and (h.vigente_hasta is null or h.vigente_hasta >= p_fecha_cese)
             order by h.vigente_desde desc
             limit 1),
           v_p.regimen_pension)
    into v_regimen_pension;

  select tp.aporte + tp.comision + tp.prima
    into v_tasa_afp
  from tasas_pension tp
  where tp.regimen = v_regimen_pension
    and tp.vigente_desde <= p_fecha_cese
    and (tp.vigente_hasta is null or tp.vigente_hasta >= p_fecha_cese)
  order by tp.vigente_desde desc
  limit 1;

  if v_tasa_afp is null then
    select coalesce((valor->>'tasa')::numeric, 0) into v_tasa_afp
    from configuracion where clave = 'tasa_afp';
    if v_tasa_afp is null then v_tasa_afp := 0; end if;
  end if;

  v_descuento_afp := round(v_monto_bruto * v_tasa_afp, 2);
  v_monto := greatest(0, round(v_monto_bruto - v_descuento_afp, 2));
  -- ⇩⇩⇩ fin CAMBIO 0341 ⇩⇩⇩

  -- ⇩⇩⇩ CAMBIO 0283 ⇩⇩⇩ AVISA DE UN RECORD VENCIDO, NO LO INDEMNIZA.
  --
  -- El art. 23 del D. Leg. 713 manda una indemnizacion -otra remuneracion
  -- entera- cuando un record vence sin gozarse. El sistema NO la calcula, por
  -- decision de Felipe del 2026-08-22, y con razon: tiene excepciones que el
  -- sistema no sabe distinguir -el personal de direccion queda fuera- y
  -- calcularla mal cuesta mucho en cualquiera de los dos sentidos.
  --
  -- Lo que hace es DECIRLO, con la norma al lado, para que quien arma la
  -- liquidacion lo vea y decida. Y hay algo mas importante que eso: si esto
  -- aparece el dia del cese, ya es tarde. La forma de que no exista nunca es
  -- avisar ANTES de que el record venza, no en la hoja final.
  --
  -- ⇩⇩⇩ CAMBIO 0297 ⇩⇩⇩ VENCIDOS, no «sin gozar». Contaba de mas.
  --
  -- `floor(saldo / 15)` son los records COMPLETOS SIN GOZAR. El ultimo de ellos
  -- todavia tiene un anio por delante para gozarse, asi que no esta vencido.
  -- Medido: catorce dias despues de cerrar su primer record, esta hoja decia que
  -- la empresa podia deberle una remuneracion entera de indemnizacion. No la
  -- debe. La resta de 1 es toda la correccion, y ahora vive en el saldo.
  v_vencidos := (v_saldo->>'records_vencidos')::int;

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequena empresa: 15 dias por anio',
    'aniversario', v_aniv, 'hasta', p_fecha_cese,
    'meses_completos', v_m, 'dias_sueltos', v_d,
    'remuneracion_computable', v_rc,
    'anios_completos', v_anios, 'dias_del_trunco', v_trunco,
    'dias_ganados', v_ganados, 'dias_gozados', v_tomados, 'dias_pendientes', v_pend,
    'ya_pagado_libro', v_ya_pagado,
    'records_vencidos', v_vencidos,
    'records_sin_gozar', (v_saldo->>'records_sin_gozar')::int,
    'vence_el', (v_saldo->>'vence_el')::date,
    'aviso_vencidos', case when v_vencidos > 0 then
      'ATENCION: ' || v_vencidos || ' record(s) de vacaciones VENCIDOS -cerrados hace mas de un anio '
      || 'sin gozarse-. El art. 23 del D. Leg. 713 manda ademas una indemnizacion de una remuneracion '
      || 'por cada uno, que este sistema NO calcula (tiene excepciones: el personal de direccion queda '
      || 'fuera). Revisalo con el contador.'
      else null end,
    -- Lo que de verdad evita la indemnizacion es esto, y por eso va aun sin
    -- vencidos: el dia del cese ya es tarde para programar unas vacaciones.
    'aviso_por_vencer', case when v_vencidos = 0 and (v_saldo->>'records_sin_gozar')::int > 0 then
      'Tiene un record completo sin gozar que vence el ' || (v_saldo->>'vence_el')
      || '. Todavia no genera indemnizacion; la genera si llega esa fecha sin haberse tomado.'
      else null end,
    'valor_dia', round(v_base / 30.0, 2),
    'formula', '(RC / 2) x dias_pendientes / 15, menos lo ya pagado del libro y el aporte a pension',   -- CAMBIO 0341
    'monto_bruto', v_monto_bruto,       -- CAMBIO 0341
    'descuento_afp', v_descuento_afp,   -- CAMBIO 0341
    'tasa_afp', v_tasa_afp,             -- CAMBIO 0341
    'monto', v_monto
  );
end;
$function$;

grant  execute on function fn_vacaciones_truncas(uuid, date) to authenticated;
revoke execute on function fn_vacaciones_truncas(uuid, date) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (341, 'las_vacaciones_truncas_pagan_su_aporte_a_pension')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $fin$
begin
  raise notice '0341 · las vacaciones truncas ya descuentan AFP/ONP, igual que cualquier mes trabajado.';
end $fin$;
