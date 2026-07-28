-- ============================================================================
-- 0104 — Partir el pago base: cuánto es remuneración básica legal y cuánto es
--        complemento variable por rendimiento.
--
-- El problema que resuelve: la boleta podía ETIQUETAR el pago como «básica +
-- variable», pero el cálculo no separaba nada. fn_planilla_calcular toma un solo
-- salario (el del rango, en asignaciones_salario) y produce un solo pago_base.
-- Un documento que declara una estructura que sus propios números no sostienen
-- es más débil que no declarar nada: los números son la prueba.
--
-- Ahora la separación existe en el dato, no en el rótulo:
--
--   basica_legal_prop    = sueldo_base_legal × (pago_base / salario_ref)
--   complemento_variable = pago_base − basica_legal_prop
--
-- O sea: la básica legal se prorratea por lo efectivamente trabajado, con la
-- MISMA proporción que ya aplicó el cálculo al salario del rango. Ejemplo real
-- (Chiara, julio 2026): pago_base 1,215.70 sobre un rango de 1,450 son 83.84%
-- del mes; el 83.84% de una básica de 1,130 es 947.41, y el resto —268.29— es
-- complemento variable. 947.41 + 268.29 = 1,215.70, el mismo monto de siempre.
-- Esto NO cambia lo que nadie cobra: solo dice de qué está hecho.
--
-- POR QUÉ EL COMPLEMENTO SE RESTA Y NO SE REDONDEA APARTE: si cada parte se
-- redondeara por su cuenta, la suma podría desviarse un céntimo del pago_base y
-- el desglose dejaría de cuadrar. Se redondea la básica y el complemento es la
-- diferencia exacta. La suma siempre da el total.
--
-- POR QUÉ SE TOCA EL ENVOLTORIO Y NO EL NÚCLEO: fn_planilla_calcular son ~320
-- líneas con pruebas encima y es donde vive el dinero. Este desglose no cambia
-- ningún cálculo de pago, así que se añade en fn_proyeccion_periodo, que son 20
-- líneas y solo compone la respuesta. Menos superficie, menos riesgo.
--
-- CUANDO NO HAY DATO: si sueldo_base_legal es NULL (todo el equipo que ya estaba
-- aquí, ver 0103) o salario_ref no es positivo, los dos campos salen NULL y la
-- boleta cae a mostrar el pago base sin partir. No se inventa una básica.
--
-- OJO, LÍMITE CONOCIDO: fn_simular_planilla NO lleva este desglose. Las
-- simulaciones por rango libre no tienen persona a la que consultarle su básica.
-- La boleta siempre nace de un periodo real, así que no le afecta.
--
-- CÓMO SE REVIERTE: restaurar la definición de fn_proyeccion_periodo tal como
-- está en la 0025. Nada más depende de estos dos campos.
-- Decidido con Felipe el 2026-07-28.
-- ============================================================================

create or replace function fn_proyeccion_periodo(p_periodo_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_p record; v_out jsonb; v_filas jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la planilla.';
  end if;
  select * into v_p from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_out := fn_planilla_calcular(v_p.fecha_ini, v_p.fecha_fin, v_p.id);

  select coalesce(
    jsonb_agg(
      t.f || jsonb_build_object(
        'basica_legal_prop', bl.monto,
        'complemento_variable',
          case
            when bl.monto is null then null
            else round(coalesce((t.f->>'pago_base')::numeric, 0), 2) - bl.monto
          end
      )
      order by t.ord
    ),
    '[]'::jsonb
  )
  into v_filas
  from jsonb_array_elements(v_out->'filas') with ordinality as t(f, ord)
  left join personas pe on pe.id = (t.f->>'persona_id')::uuid
  left join lateral (
    -- El guard va DENTRO del lateral: si salario_ref fuera 0 y la división
    -- viviera fuera de este case, la consulta entera reventaría por división
    -- por cero en vez de devolver NULL para esa persona.
    select case
      when pe.sueldo_base_legal is null then null
      when coalesce((t.f->>'salario_ref')::numeric, 0) <= 0 then null
      else round(
        pe.sueldo_base_legal
          * coalesce((t.f->>'pago_base')::numeric, 0)
          / (t.f->>'salario_ref')::numeric,
        2
      )
    end as monto
  ) bl on true;

  return v_out
    || jsonb_build_object('filas', v_filas)
    || jsonb_build_object(
         'periodo_id', v_p.id,
         'estado', v_p.estado,
         'pagado_at', v_p.pagado_at,
         'simulacion', false
       );
end;
$$;

-- create or replace conserva los permisos, pero se repiten para que esta
-- migración sea autosuficiente si alguien la pega sobre una base restaurada.
grant execute on function fn_proyeccion_periodo(uuid) to authenticated;
revoke execute on function fn_proyeccion_periodo(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (104, 'desglose_legal_del_pago_base')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
