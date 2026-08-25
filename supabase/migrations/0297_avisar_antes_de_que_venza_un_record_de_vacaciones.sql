-- ============================================================================
-- 0297 — Avisar ANTES de que venza un récord de vacaciones.
-- ============================================================================
--
-- QUÉ PROMETE
--
--   1 · Que se sepa a quién se le está por vencer un récord de vacaciones, con
--       60 días de anticipación, en la pantalla donde se programan y en el menú.
--   2 · Que «cuántos récords están vencidos» se calcule bien. Hoy se cuenta de
--       más, y la hoja de liquidación lo dice.
--   3 · Que esa cuenta viva en UN solo sitio, porque esta es exactamente la
--       cuenta que ya divergió una vez y costó S/905,38 medidos.
--
-- ── EL DEFECTO QUE SE ARREGLA, MEDIDO ───────────────────────────────────────
--
--   `fn_vacaciones_truncas` (0283) avisa «N récord(s) sin gozar · el art. 23
--   manda una indemnización por cada uno». Cuenta `floor(saldo / 15)`, que son
--   los récords COMPLETOS SIN GOZAR — no los vencidos. Medido contra el Postgres
--   local con alguien que ingresó el 01/01/2024 y nunca tomó vacaciones:
--
--     fecha        saldo    decía    de verdad
--     20/12/2024   14,58      0        0
--     15/01/2025   15,63      1        0   ← cerró hace 14 días, vence 01/01/2026
--     01/04/2025   18,79      1        0
--     20/12/2025   29,58      1        0   ← le quedan 12 días para gozarlo
--     15/01/2026   30,63      2        1   ← solo venció el primero
--
--   O sea: catorce días después de cerrar su primer récord, la hoja de cese de
--   esa persona ya decía que podía deberle una remuneración entera de
--   indemnización. No la debe: el art. 23 del D. Leg. 713 indemniza el descanso
--   no gozado DENTRO DEL AÑO SIGUIENTE, y ese año no había empezado a correr.
--
--   La regla correcta sale de la misma cuenta. Con `k` récords completos sin
--   gozar y `A` años cumplidos, los sin gozar son los récords A−k+1 … A, y cada
--   récord j vence en el aniversario j+1. Como hoy estamos dentro del año A,
--   han vencido los que cumplen j+1 ≤ A, o sea j ≤ A−1:
--
--       vencidos = k − 1            (nunca menos de 0)
--       el próximo en vencer es SIEMPRE el récord A, el último cerrado,
--       y vence en  fecha_ingreso + (A + 1) años.
--
--   Comprobado contra las cinco fechas de la tabla.
--
-- ── POR QUÉ UNA SOLA CUENTA, Y NO UNA TERCERA ───────────────────────────────
--
--   `fn_vacaciones_resumen` y `fn_vacaciones_truncas` calculaban el saldo por
--   caminos distintos y divergieron: medido en producción el 2026-08-14, tres
--   personas que SÍ se habían tomado sus vacaciones perdían S/905,38 entre las
--   tres porque la liquidación contaba los goces por la fecha en que se tomaron
--   y no por el récord al que pertenecen. Lo arregló la 0283.
--
--   Escribir acá una tercera copia para el aviso sería repetir ese accidente con
--   otra cara. Así que el saldo se extrae a `fn_vacaciones_saldo` y
--   `fn_vacaciones_truncas` pasa a preguntárselo. La plata la sigue calculando
--   la liquidación; el saldo lo dice una sola función.
--
-- ── POR QUÉ 60 DÍAS ─────────────────────────────────────────────────────────
--
--   Decidido por Felipe el 2026-08-25. Dos meses alcanzan para acomodar el
--   calendario de una sede sin dejarla corta de gente. Antes de eso el aviso
--   estaría encendido casi todo el año y dejaría de leerse — que es el mismo
--   criterio con que este repositorio descartó otros guardianes ruidosos.
--
-- ── QUIÉN LO VE ─────────────────────────────────────────────────────────────
--
--   Los tres, y cada uno lo suyo (decisión de Felipe): DO y administración ven a
--   todo el equipo; la encargada, solo su sede —es quien arma el calendario y
--   sabe qué semana puede prescindir de alguien—; y cada persona, solo la suya.
--   El guard lo hace el cuerpo de la función y no un `revoke`, por lo aprendido
--   en la 0129: un revoke se deshace la próxima vez que alguien conceda en masa.
--
-- QUÉ ASUME
--
--   · `fn_vacaciones_truncas` en su versión de la 0283 — de la que se copia el
--     cuerpo— y que el régimen es MYPE pequeña empresa: 15 días por año.
--   · La vista `vacaciones` sobre `ausencias` (las anuladas ya quedan fuera por
--     su definición), `fn_devenga`, `fn_hoy_lima()`, `fn_persona_actual_id()`.
--   · Que el historial de goces está completo. Si alguien se tomó vacaciones sin
--     registrarlas, esta cuenta cree que no las gozó — y el aviso saldría de
--     más. Comprobado el 2026-08-22: las cuatro personas con un año cumplido
--     tienen saldo cero y las otras 16 no han cumplido el año.
--
-- QUÉ MUEVE AL PEGARSE
--
--   Ningún pago. `fn_vacaciones_truncas` devuelve exactamente el mismo `monto`;
--   lo único que cambia es `records_vencidos` y el texto del aviso, que hoy
--   sobran. Con los datos de hoy nadie sale en la lista: nadie tiene saldo.
--
-- CÓMO SE REVIERTE
--   drop function fn_vacaciones_por_atender();
--   drop function fn_vacaciones_por_vencer(int, date);
--   drop function fn_vacaciones_saldo(uuid, date);
--   -- y volver a pegar fn_vacaciones_truncas desde la 0283, tal cual.
-- ============================================================================


-- ── A · El saldo, en un solo sitio ──────────────────────────────────────────
-- Lo que antes vivía dentro de la liquidación. Devuelve días y fechas, nunca
-- plata: quien paga es la liquidación, y así esta se puede abrir a la encargada
-- y a cada persona sin exponer un sueldo.
create or replace function fn_vacaciones_saldo(
  p_persona_id uuid,
  p_as_of      date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_p        personas%rowtype;
  v_as_of    date;
  v_anios    int;
  v_m int; v_d int;
  v_trunco   numeric;
  v_ganados  numeric;
  v_tomados  numeric;
  v_pend     numeric;
  v_k        int;
  v_vencidos int;
  v_vence    date;
begin
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  -- Cada quien lo suyo. `is not true` en el primero por la forma de la casa: un
  -- null no debe pasar como autorizado.
  if fn_es_admin_o_lider() is not true
     and p_persona_id <> coalesce(fn_persona_actual_id(), '00000000-0000-0000-0000-000000000000'::uuid)
     and not (fn_rol_actual() = 'supervisor_sede'::rol_usuario
              and v_p.sede_base_id = fn_sede_actual_persona()) then
    raise exception 'No puedes ver el saldo de vacaciones de otra persona.';
  end if;

  v_as_of := coalesce(p_as_of, fn_hoy_lima());

  if not fn_devenga(p_persona_id, 'vacaciones') then
    return jsonb_build_object('aplica', false,
      'motivo', 'No devenga vacaciones: su vínculo es ' || v_p.tipo_vinculo || '.');
  end if;

  if v_as_of < v_p.fecha_ingreso then
    return jsonb_build_object('aplica', false, 'motivo', 'Todavía no había ingresado.');
  end if;

  -- Mismo cálculo que la 0283, y por eso vive acá: se cuenta TODA SU VIDA, no
  -- el récord en curso. Cada día que se tomó se resta UNA vez del total que
  -- ganó; no hay ventana donde un día pueda caer fuera ni contarse dos veces.
  v_anios := floor(extract(year from age(v_as_of, v_p.fecha_ingreso)))::int;
  select meses, dias into v_m, v_d
    from fn_meses_y_dias((v_p.fecha_ingreso + make_interval(years => v_anios))::date, v_as_of);
  v_trunco  := round(15.0 * v_m / 12.0 + 15.0 * v_d / 360.0, 2);
  v_ganados := round(15.0 * v_anios + v_trunco, 2);

  select coalesce(sum(least(v.fecha_fin, v_as_of) - greatest(v.fecha_inicio, v_p.fecha_ingreso) + 1), 0)
    into v_tomados
    from vacaciones v
   where v.persona_id = p_persona_id
     and v.fecha_fin >= v_p.fecha_ingreso and v.fecha_inicio <= v_as_of;

  v_pend := greatest(0, v_ganados - v_tomados);

  -- Récords COMPLETOS sin gozar, y cuántos de ellos ya vencieron. La resta de 1
  -- es toda la corrección: el último récord cerrado tiene un año por delante.
  v_k        := floor(v_pend / 15.0)::int;
  v_vencidos := greatest(v_k - 1, 0);

  -- El próximo en vencer es siempre el último récord cerrado, el A: los
  -- anteriores o se gozaron o ya vencieron.
  if v_k > 0 then
    v_vence := (v_p.fecha_ingreso + make_interval(years => v_anios + 1))::date;
  end if;

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequeña empresa: 15 días por año',
    'as_of', v_as_of,
    'fecha_ingreso', v_p.fecha_ingreso,
    'anios_completos', v_anios,
    'dias_ganados', v_ganados,
    'dias_gozados', v_tomados,
    'dias_pendientes', v_pend,
    'records_sin_gozar', v_k,
    'records_vencidos', v_vencidos,
    'vence_el', v_vence,
    'dias_para_vencer', case when v_vence is null then null else (v_vence - v_as_of) end
  );
end;
$$;

grant execute on function fn_vacaciones_saldo(uuid, date) to authenticated;

comment on function fn_vacaciones_saldo(uuid, date) is
  'Días de vacaciones ganados, gozados y pendientes de una persona, y cuándo vence '
  'su récord más próximo. Es la ÚNICA cuenta del saldo: la liquidación se la pregunta. '
  'Nunca devuelve plata, para poder abrirse a la encargada y a cada persona.';


-- ── B · A quién se le está por vencer ───────────────────────────────────────
-- El `with … as materialized` no es adorno: filtra PRIMERO a quien puede ver
-- quien pregunta, y recién entonces calcula. Sin eso, la función del saldo se
-- llamaría también sobre las personas ajenas y su guard reventaría la consulta
-- entera en vez de devolver una lista más corta.
create or replace function fn_vacaciones_por_vencer(
  p_dias  int  default 60,
  p_as_of date default null
)
returns table (
  persona_id        uuid,
  persona           text,
  sede              text,
  fecha_ingreso     date,
  dias_pendientes   numeric,
  records_sin_gozar int,
  records_vencidos  int,
  vence_el          date,
  dias_para_vencer  int
)
language sql
stable
security definer
set search_path = public
as $$
  with visibles as materialized (
    select p.id, p.nombres, p.apellidos, p.sede_base_id, p.fecha_ingreso
      from personas p
     where p.estado = 'activo'
       and ( fn_es_admin_o_lider() is true
          or p.id = fn_persona_actual_id()
          or ( fn_rol_actual() = 'supervisor_sede'::rol_usuario
               and p.sede_base_id = fn_sede_actual_persona() ) )
  )
  select v.id,
         v.nombres || ' ' || v.apellidos,
         coalesce(s.codigo, '?'),
         v.fecha_ingreso,
         (x.r->>'dias_pendientes')::numeric,
         (x.r->>'records_sin_gozar')::int,
         (x.r->>'records_vencidos')::int,
         (x.r->>'vence_el')::date,
         (x.r->>'dias_para_vencer')::int
    from visibles v
    left join sedes s on s.id = v.sede_base_id
    cross join lateral (select fn_vacaciones_saldo(v.id, coalesce(p_as_of, fn_hoy_lima())) as r) x
   where (x.r->>'aplica')::boolean is true
     and (x.r->>'records_sin_gozar')::int > 0
     -- El `or` no es un adorno: quien YA tiene un récord vencido puede tener el
     -- siguiente a un año de distancia, y con solo el filtro de los 60 días
     -- desaparecía de la lista justo la persona más urgente. Se vio en el panel
     -- con datos de prueba, no razonándolo: alguien con dos récords vencidos no
     -- salía por ningún lado.
     and ( (x.r->>'dias_para_vencer')::int <= p_dias
        or (x.r->>'records_vencidos')::int > 0 )
   -- Los vencidos primero, y entre ellos el que lleva más tiempo vencido.
   order by (x.r->>'records_vencidos')::int desc,
            (x.r->>'dias_para_vencer')::int, v.apellidos, v.nombres;
$$;

grant execute on function fn_vacaciones_por_vencer(int, date) to authenticated;

comment on function fn_vacaciones_por_vencer(int, date) is
  'A quién se le vence un récord de vacaciones dentro de p_dias — y a quién ya se le '
  'venció, que sale con los días en negativo. Cada rol ve lo que le toca: DO todo, la '
  'encargada su sede, cada persona la suya.';


-- ── C · El contador del menú ────────────────────────────────────────────────
-- 60 días, el mismo umbral que la pantalla, y por eso lo pregunta a la misma
-- función: un contador que diga 3 mientras la lista muestra 5 es peor que no
-- tener contador.
create or replace function fn_vacaciones_por_atender()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from fn_vacaciones_por_vencer(60, null);
$$;

grant execute on function fn_vacaciones_por_atender() to authenticated;


-- ── D · La liquidación pregunta el saldo y deja de contar de más ────────────
-- Cuerpo de la 0283 con dos cambios: el saldo se le pregunta a la función de
-- arriba en vez de recalcularlo, y `records_vencidos` cuenta vencidos de verdad.
-- El `monto` no se toca: devuelve exactamente lo mismo que hoy.
--
-- Se va también `v_venc_desde`, que la 0283 calculaba y no usaba en ninguna
-- parte — iba a ser «desde cuándo venció» y nunca llegó a la salida.
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
    'formula', '(RC / 2) x dias_pendientes / 15, menos lo ya pagado del libro',
    'monto', v_monto
  );
end;
$function$;

grant  execute on function fn_vacaciones_truncas(uuid, date) to authenticated;
revoke execute on function fn_vacaciones_truncas(uuid, date) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (297, 'avisar_antes_de_que_venza_un_record_de_vacaciones')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $fin$
begin
  raise notice '0297 · el aviso llega 60 dias antes, y los vencidos se cuentan bien.';
end $fin$;
