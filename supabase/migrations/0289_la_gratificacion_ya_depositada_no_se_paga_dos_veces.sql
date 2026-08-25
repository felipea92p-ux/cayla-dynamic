-- ============================================================================
-- 0289_la_gratificacion_ya_depositada_no_se_paga_dos_veces.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que quien cesa DESPUÉS de haber cobrado su gratificación no la cobre otra
--   vez en la liquidación. Hay trece días en julio y trece en diciembre en que
--   hoy la cobra dos veces.
--
-- ── EL DEFECTO, MEDIDO ──────────────────────────────────────────────────────
--
-- La gratificación de enero-junio se deposita el 15 de julio. El periodo de
-- planilla que la contiene no cierra hasta el 28. Entre esos dos días la hoja
-- de liquidación la vuelve a pagar entera.
--
-- Medido con sueldo S/1.950 y la grati de julio ya registrada:
--
--     cese el 12/07 ...... S/1.062,75   correcto: aún no se la habían pagado
--     cese el 20/07 ...... S/1.062,75   ← DUPLICADO. Ya la cobró el día 15
--     cese el 05/08 ...... S/  177,13   correcto: solo el trunco de julio
--
-- Son S/1.062,75 —la gratificación entera más su 9 % de la Ley 30334— y salen
-- por el camino que NO tiene campo editable: la liquidación recalcula, congela
-- y paga.
--
-- ── POR QUÉ LA COMPROBACIÓN FALLABA ─────────────────────────────────────────
--
-- Preguntaba dos cosas, y el 20 de julio fallan LAS DOS a la vez:
--
--     and pp.estado = 'pagado'           el periodo sigue ABIERTO hasta el 28
--     and pp.fecha_fin <= p_fecha_cese   termina el 28, después del cese
--
-- La primera es un desajuste estructural: `estado = 'pagado'` se pone al CERRAR
-- el mes, y la gratificación se deposita a mitad. Pedirlo significa no
-- reconocer nunca un pago hasta trece días después de haberlo hecho.
--
-- ── LA SEGUNDA LÍNEA NO ERA UN DESCUIDO, Y ESO ES LO IMPORTANTE ─────────────
--
-- Traía su comentario explicando para qué estaba: sin ella, un cese de
-- septiembre daría por cobrada la gratificación de DICIEMBRE —que todavía no
-- existe— y no pagaría nada de julio ni agosto. Borrarla a lo bruto crea el
-- error contrario, y ese va CONTRA LA PERSONA, que es el caro en esta casa.
--
-- Por eso no se quita: se le cambia el ancla. La pregunta pasa de «¿cerró el
-- periodo antes del cese?» a «¿YA LLEGÓ LA FECHA EN QUE LA LEY MANDA PAGAR
-- esta gratificación?» — el 15 de julio o el 15 de diciembre.
--
-- Los cuatro casos, medidos con el arreglo puesto:
--
--     cese el 12/07 ...... S/1.062,75   aún no tocaba pagar → se la paga
--     cese el 20/07 ...... S/    0,00   ya tocaba, y hay pago → no repite
--     cese el 05/08 ...... S/  177,13   solo el trunco de julio
--     cese el 20/09 ...... S/  354,25   NO da por cobrada la de diciembre
--
-- El último es exactamente lo que la línea vieja protegía, y sigue protegido.
--
-- ── LO QUE SE PIERDE, DICHO PARA QUE NADIE LO DESCUBRA SOLO ─────────────────
--
-- Al dejar de exigir `estado = 'pagado'`: si alguien REGISTRA el movimiento
-- antes de transferir el dinero y la persona cesa después del 15, la hoja lo
-- dará por cobrado sin que el dinero haya salido. Es más raro que el caso que
-- se arregla —hay que anotar el pago antes de hacerlo— pero va contra la
-- persona. Si aparece alguna vez, el arreglo es exigir además el libro de
-- desembolsos, NO volver a `estado = 'pagado'`.
--
-- ── LO QUE SE PUEDE HACER SIN ESTA MIGRACIÓN ────────────────────────────────
--
-- Anotar en el libro de desembolsos las gratificaciones que se depositan. El
-- libro se consulta sin ninguna de las dos condiciones, así que baja el
-- duplicado de S/1.062,75 a S/87,75. Ese residuo es el 9 % de la Ley 30334: el
-- libro anota los S/975 de la gratificación y no el 9 % que se paga con ella.
-- Queda anotado como pendiente propio; es de otro tamaño y de otra función.
--
-- QUÉ ASUME
--   · md5 DE PARTIDA, pedido a producción ANTES de escribir esto y coincidente
--     con el local al byte:
--
--       fn_grati_trunca_bruta   78cb6ac19121bb40f76d62f23f58dfd4   5 938 chars
--
--     El cuerpo se extrajo de la base con `pg_get_functiondef`, no de un
--     archivo, y cambian tres bloques: la declaración de `v_pago_legal`, su
--     cálculo en las dos ramas de la ventana, y la condición.
--
--   · md5 DE LLEGADA, para comprobar que se pegó entero:
--
--       fn_grati_trunca_bruta   8a4d089c3bf1bc78ef0563191c942a2f   8 595 chars
--
--     ⚠ Y ESTE NÚMERO SE TOMÓ DESPUÉS DE RENUMERAR, que es la única forma de
--     que sirva. La primera versión decía `0065baff…` —medido cuando esto se
--     llamaba 0288, antes de que el hook obligara a renumerar— y contra
--     producción daba la firma que ya cazó a la 0286 el día anterior: MISMA
--     LONGITUD, DISTINTO HASH. Los marcadores «CAMBIO 0288» del cuerpo pasan a
--     «CAMBIO 0289» y los dos ocupan cuatro caracteres.
--
--     La 0286 dejó escrito CÓMO reconocer ese síntoma. No dejó escrito CUÁNDO
--     medir, y por eso se repitió al día siguiente. La regla es esta:
--
--         el md5 DE LLEGADA se mide DESPUÉS del renumerado, nunca antes.
--
--     Y si aparece la firma igual: `position('CAMBIO 00NN' in prosrc)` sobre el
--     cuerpo de producción dice en un vistazo qué número tiene dentro.
--
--   · LO QUE SE MIDIÓ. Verde tras `db reset`: 148 archivos, 1.475 pruebas. Y el
--     freno frena: revirtiendo la función se ponen rojas las aserciones 2 y 5
--     de la prueba 225 —la del duplicado y la del techo— y ninguna otra en todo
--     el repositorio. Las aserciones 1, 3 y 4 siguen verdes con la función
--     vieja a propósito: son las que vigilan que el arreglo no se pase al otro
--     lado, y con la vieja ya se cumplían.
--
-- CÓMO SE REVIERTE
--   Restaurar `fn_grati_trunca_bruta` desde la 0163. No toca tablas, ni datos,
--   ni permisos. Revertir devuelve los trece días de julio y los de diciembre.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La prueba 225 monta los cuatro ceses de arriba. Y en producción: que nadie
--   con fecha de cese entre el 15 y el 28 de julio o de diciembre tenga la
--   gratificación de ese semestre en su liquidación.
-- ============================================================================

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
        and pp.fecha_fin >= v_pago_ini
        and pp.fecha_fin <  v_pago_fin
        -- ⇩⇩⇩ CAMBIO 0289 ⇩⇩⇩ EL ANCLA ES CUÁNDO TOCABA PAGAR, NO CUÁNDO
        -- CERRÓ EL PERIODO.
        --
        -- Acá decía `pp.estado = 'pagado' and pp.fecha_fin <= p_fecha_cese`, y
        -- las dos mitades fallan a la vez en la única ventana que importa: la
        -- grati se deposita el 15 y el periodo que la contiene no cierra hasta
        -- el 28. Entre esos dos dias el periodo sigue ABIERTO —asi que no es
        -- 'pagado'— y termina DESPUES del cese —asi que no cumple lo segundo—.
        -- Resultado: la hoja concluia «no la ha cobrado» y la pagaba OTRA VEZ.
        -- Medido: S/1.062,75 duplicados con sueldo S/1.950, que es la grati
        -- entera mas su 9% de la Ley 30334. Trece dias en julio y trece en
        -- diciembre: 26 al anio.
        --
        -- LA SEGUNDA CONDICION NO ERA UN DESCUIDO Y NO SE PODIA BORRAR. Su
        -- comentario lo decia: sin ella, un cese de septiembre daria por
        -- cobrada la gratificacion de DICIEMBRE —que todavia no existe— y no
        -- pagaria nada de julio ni agosto. Quitarla a lo bruto crea el error
        -- contrario, y ese va contra la persona.
        --
        -- Por eso no se quita: se le cambia el ancla. La pregunta pasa de
        -- «¿cerró el periodo antes del cese?» a «¿ya llegó la fecha en que la
        -- ley manda pagar esta gratificacion?» — el 15 de julio o el 15 de
        -- diciembre. Con ese ancla los tres casos salen bien:
        --   cese el 12/07 → aun no tocaba pagar   → se la paga la liquidacion
        --   cese el 20/07 → ya tocaba, y hay pago → no se la paga otra vez
        --   cese en septiembre → la de diciembre no tiene fecha pasada → no se
        --                        da por cobrada, que es lo que la linea vieja
        --                        protegia
        --
        -- Y SE DEJA DE EXIGIR `estado = 'pagado'`, a proposito. Ese estado se
        -- pone al CERRAR el mes, y la grati se deposita a mitad: pedirlo
        -- significa no reconocer nunca un pago hasta trece dias despues de
        -- hacerlo. La evidencia de que se pago es el movimiento registrado mas
        -- la fecha legal cumplida.
        --
        -- LO QUE SE PIERDE CON ESO, dicho para que nadie lo descubra solo: si
        -- alguien registra el movimiento ANTES de transferir y la persona cesa
        -- despues del 15, la hoja lo dara por cobrado sin que el dinero haya
        -- salido. Es un caso mas raro que el que se arregla —hay que anotar el
        -- pago antes de hacerlo— y va contra la persona, asi que si aparece
        -- alguna vez, el arreglo es exigir tambien el libro de desembolsos, no
        -- volver a `estado = 'pagado'`.
        and p_fecha_cese >= v_pago_legal
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
insert into migraciones_aplicadas (numero, nombre)
values (289, 'la_gratificacion_ya_depositada_no_se_paga_dos_veces')
on conflict (numero) do nothing;
