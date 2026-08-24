-- ============================================================================
-- 0283_las_vacaciones_no_gozadas_se_pagan_al_cesar.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que al cesar se paguen TODOS los días de vacaciones que la persona ganó y
--   no gozó, no solo los del récord en curso. Y que tomarse las vacaciones deje
--   de costarle dinero a quien se las toma.
--
-- ── EL DEFECTO, MEDIDO ──────────────────────────────────────────────────────
--
-- Dos personas idénticas —mismo sueldo, mismo ingreso, mismo día de cese—. La
-- única diferencia entre ellas es que una se tomó sus vacaciones:
--
--     nunca gozó .................................. S/ 812,50
--     gozó sus 15 días cuando la ley manda ........ S/   0,00
--
-- Por ejercer un derecho, cobra cero. Y la que nunca gozó cobra solo el año en
-- curso: sus dos récords completos —30 días— no aparecen en ninguna línea.
--
-- LA CAUSA es una ventana. La cuenta empezaba en el último aniversario:
--
--     ganados   = 15 × meses/12 desde el último aniversario
--     gozados   = días de vacaciones DESDE EL ÚLTIMO ANIVERSARIO   ← acá
--     pendiente = max(0, ganados − gozados)
--
-- Los 15 días que se ganan al cerrar un récord se gozan DESPUÉS del
-- aniversario —es lo normal, y es lo que la ley manda—. Caen dentro de esa
-- ventana, así que se restan del récord NUEVO. El mismo descanso se cobra dos
-- veces, y solo a quien lo tomó.
--
-- ── POR QUÉ LA CUENTA ACUMULADA NO PUEDE PAGAR DOS VECES ────────────────────
--
-- Es la pregunta que hizo Felipe antes de aprobar esto, y la respuesta es la
-- razón de que el arreglo sea éste y no un reparto récord por récord:
--
--   · cada día que la persona se tomó EN SU VIDA se resta UNA vez del total que
--     ganó EN SU VIDA. No hay ventana donde un día pueda caer fuera y quedar
--     sin descontar, ni donde pueda caer dos veces;
--   · `vacaciones` es una VISTA sobre `ausencias` —comprobado— así que un mismo
--     día no puede contarse por dos tablas distintas, y las anuladas ya quedan
--     fuera por la definición de la vista;
--   · y lo que el libro de desembolsos diga que ya se pagó se descuenta, que es
--     lo que esta función era la única de las tres truncas en no hacer.
--
-- QUÉ ASUME, Y SE COMPROBÓ ANTES DE ESCRIBIRLO
--   Que el historial de goces está completo. Si alguien se tomó vacaciones y no
--   están registradas, esta cuenta se las pagaría como si nunca las hubiera
--   gozado — es el único modo en que puede equivocarse.
--
--   Medido contra producción el 2026-08-22, las 20 personas activas: las cuatro
--   que han cumplido un año se tomaron EXACTAMENTE sus 15 días —15 ganados, 15
--   gozados, saldo cero las cuatro— y las 16 restantes no han cumplido el primer
--   año. **Nadie tiene saldo pendiente y nadie tiene un récord vencido.** El
--   historial cuadra, y por eso no hace falta fecha de corte.
--
-- ── A QUIÉN LE CAMBIA ALGO HOY ──────────────────────────────────────────────
--
--   Tres personas, y a ninguna le regala nada: les devuelve su trunco.
--   Se tomaron sus 15 días DESPUÉS de su aniversario, que es lo correcto, y por
--   eso hoy cobrarían S/0,00 si cesaran:
--
--       aniversario 02/01/2026 · goce 15/01/2026
--       aniversario 28/01/2026 · goce 12/02/2026
--       aniversario 13/03/2026 · goce 29/03/2026
--
--   A las 17 restantes no les cambia un céntimo: o no han ganado días todavía,
--   o su goce cayó antes del aniversario y la fórmula vieja acertaba por
--   casualidad.
--
-- ── LA INDEMNIZACIÓN DEL ART. 23: SE AVISA, NO SE CALCULA ───────────────────
--
--   Un récord que vence sin gozarse manda además una indemnización de una
--   remuneración entera. El sistema NO la calcula, por decisión de Felipe del
--   2026-08-22: tiene excepciones que el sistema no sabe distinguir —el personal
--   de dirección queda fuera— y calcularla mal cuesta mucho en los dos sentidos.
--   La hoja lo DICE, con la norma al lado, y decide una persona.
--
--   Y hay algo más importante que calcularla: si eso aparece el día del cese, ya
--   es tarde. La forma de que no exista nunca es avisar ANTES de que el récord
--   venza. Eso no va en esta migración y queda anotado como lo siguiente.
--
-- QUÉ ASUME
--   · Versión de partida de `fn_vacaciones_truncas`: la **0283** de este archivo
--     parte de la que dejó la 0278.
--   · md5 DE PARTIDA, medido en el Postgres local (que reproduce producción):
--
--       fn_vacaciones_truncas   9535ed57eebc317ddbefca0dc8fd409e   3 228 chars
--
--     ⚠ PÍDESELO A PRODUCCIÓN ANTES DE PEGAR. Si devuelve otro, PARAR.
--
--   · md5 DE LLEGADA, para comprobar que se pegó entero (tras `db reset` con
--     esta migración incluida):
--
--       fn_vacaciones_truncas   a005fc6907be6a55d7243bdf6e65aa9d   8 117 chars
--
--   · LO QUE SE MIDIÓ. Verde tras `db reset`: 141 archivos, 1.389 pruebas.
--     Y el freno frena: devolviendo la función a la versión de la 0278 se
--     ponen rojas 10 aserciones —las 3 de vacaciones de la 103, las 2 de la
--     215 que dependen del total, y 5 de las 9 de la 219— y ninguna otra.
--
--     Tres pruebas de este repo tenían escrita la expectativa VIEJA y se
--     actualizaron con su porqué: la 103 esperaba 7,5 días para alguien con dos
--     récords completos sin gozar, que es el defecto escrito como si fuera la
--     regla. Sus números nuevos son aritmética comprobada, no un ajuste para
--     que pasen: +S/1 950,00 en la 215 son exactamente 30 días ×
--     (1 950 / 2) / 15.
--
-- CÓMO SE REVIERTE
--   Restaurar `fn_vacaciones_truncas` desde la 0278, tal cual. No toca tablas,
--   ni datos, ni permisos. Revertir devuelve el S/0,00 a quien gozó sus días.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta comentada del final: para cada persona activa, lo que la hoja
--   le pagaría de vacaciones si cesara hoy. Las tres nombradas arriba tienen que
--   pasar de 0,00 a su trunco; las demás no se mueven.
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
  v_vencidos int := 0; v_venc_desde date;
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
  v_anios  := floor(extract(year from age(p_fecha_cese, v_p.fecha_ingreso)))::int;
  v_trunco := round(15.0 * v_m / 12.0 + 15.0 * v_d / 360.0, 2);
  v_ganados := round(15.0 * v_anios + v_trunco, 2);

  -- Desde el INGRESO, no desde el ultimo aniversario. `vacaciones` es una VISTA
  -- sobre `ausencias` -las anuladas ya quedan fuera por su definicion- asi que
  -- un mismo dia no puede contarse por dos tablas distintas.
  select coalesce(sum(least(v.fecha_fin, p_fecha_cese) - greatest(v.fecha_inicio, v_p.fecha_ingreso) + 1), 0)
    into v_tomados
    from vacaciones v
   where v.persona_id = p_persona_id
     and v.fecha_fin >= v_p.fecha_ingreso and v.fecha_inicio <= p_fecha_cese;

  v_pend  := greatest(0, v_ganados - v_tomados);   -- nunca negativo
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
  -- Un record vence cuando pasa un anio entero desde que se cerro sin haberse
  -- gozado. Se cuenta con el saldo: si le sobran mas de 15 dias, hay al menos
  -- un record completo sin tocar.
  if v_pend > 15 then
    v_vencidos  := floor(v_pend / 15.0)::int;
    v_venc_desde := (v_p.fecha_ingreso + make_interval(years => v_anios - v_vencidos))::date;
  end if;

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
    'aviso_vencidos', case when v_vencidos > 0 then
      'ATENCION: ' || v_vencidos || ' record(s) de vacaciones sin gozar. El art. 23 del D. Leg. 713 '
      || 'manda ademas una indemnizacion de una remuneracion por cada uno, que este sistema NO calcula '
      || '(tiene excepciones: el personal de direccion queda fuera). Revisalo con el contador.'
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
values (283, 'las_vacaciones_no_gozadas_se_pagan_al_cesar')
on conflict (numero) do nothing;

-- ── Comprobación ────────────────────────────────────────────────────────────
-- select p.nombres || ' ' || p.apellidos as persona,
--        (fn_vacaciones_truncas(p.id, current_date)->>'dias_ganados')::numeric   as ganados,
--        (fn_vacaciones_truncas(p.id, current_date)->>'dias_gozados')::numeric   as gozados,
--        (fn_vacaciones_truncas(p.id, current_date)->>'dias_pendientes')::numeric as pendientes,
--        (fn_vacaciones_truncas(p.id, current_date)->>'monto')::numeric          as le_pagaria,
--        (fn_vacaciones_truncas(p.id, current_date)->>'aviso_vencidos')          as aviso
--   from personas p
--  where p.estado = 'activo' and fn_devenga(p.id, 'vacaciones')
--  order by 5 desc;
