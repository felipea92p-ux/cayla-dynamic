-- ============================================================================
-- 0106 — Poder escribir la básica legal y el rendimiento desde la pantalla.
--
-- La 0103 y la 0105 crearon el dato pero no la forma de ponerlo: hasta ahora
-- fijar la básica legal de alguien o bajarle el rendimiento solo se podía por
-- SQL. Eso significaba que el equipo administrativo no podía usar el sistema, y
-- que cada cambio pasaba por el dueño con una consola abierta. Estas tres
-- funciones cierran ese hueco.
--
-- Siguen el mismo molde que fn_set_objetivos (0025): el guard va DENTRO de la
-- función, no en un revoke, por lo aprendido en la 0090 —un revoke se puede
-- deshacer por accidente con un bucle de grants y nadie se enteraría.
--
-- fn_quitar_rendimiento existe para poder VOLVER AL DEFECTO. Sin ella, poner un
-- 100 a mano y no tener fila se verían igual en el pago pero distinto en el
-- registro, y no habría manera de deshacer una puntuación sin dejar rastro raro.
--
-- OJO, LÍMITE CONOCIDO Y NO RESUELTO: sueldo_base_legal vive en personas, no por
-- periodo. Cambiarlo hoy cambia el desglose de TODAS las boletas pasadas de esa
-- persona, incluidas las de periodos ya pagados. La foto del pago (0096) congela
-- los totales, no este desglose. Si eso importa —y para un documento que se
-- entrega, probablemente importe— hace falta versionar la básica por periodo,
-- como ya se hace con el salario en asignaciones_salario. Queda anotado.
-- Decidido con Felipe el 2026-07-28.
-- ============================================================================

create or replace function fn_set_sueldo_base_legal(p_persona_id uuid, p_monto numeric)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede fijar la remuneración básica legal.';
  end if;
  if p_monto is not null and p_monto <= 0 then
    raise exception 'La remuneración básica legal debe ser mayor que cero.';
  end if;
  update personas set sueldo_base_legal = p_monto where id = p_persona_id;
  if not found then
    raise exception 'No existe esa persona.';
  end if;
end;
$$;

create or replace function fn_set_rendimiento(
  p_persona_id uuid,
  p_anio int,
  p_mes int,
  p_porcentaje numeric,
  p_etiqueta_codigo text default null
)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede puntuar el rendimiento.';
  end if;
  if p_porcentaje is null or p_porcentaje < 0 or p_porcentaje > 100 then
    raise exception 'El rendimiento debe estar entre 0 y 100.';
  end if;
  if p_mes < 1 or p_mes > 12 then
    raise exception 'Mes inválido.';
  end if;
  if p_etiqueta_codigo is not null
     and not exists (select 1 from etiquetas_complemento where codigo = p_etiqueta_codigo) then
    raise exception 'Esa etiqueta no está en el catálogo.';
  end if;

  insert into rendimiento_mensual (persona_id, anio, mes, porcentaje, etiqueta_codigo, puesto_por)
  values (p_persona_id, p_anio, p_mes, p_porcentaje, p_etiqueta_codigo, fn_persona_actual_id())
  on conflict (persona_id, anio, mes) do update
    set porcentaje      = excluded.porcentaje,
        etiqueta_codigo = excluded.etiqueta_codigo,
        puesto_por      = excluded.puesto_por,
        updated_at      = now();
end;
$$;

-- Volver al defecto (100%) borrando la fila, en vez de escribir un 100 a mano.
create or replace function fn_quitar_rendimiento(p_persona_id uuid, p_anio int, p_mes int)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar una puntuación.';
  end if;
  delete from rendimiento_mensual
  where persona_id = p_persona_id and anio = p_anio and mes = p_mes;
end;
$$;

grant execute on function fn_set_sueldo_base_legal(uuid, numeric) to authenticated;
grant execute on function fn_set_rendimiento(uuid, int, int, numeric, text) to authenticated;
grant execute on function fn_quitar_rendimiento(uuid, int, int) to authenticated;

revoke execute on function fn_set_sueldo_base_legal(uuid, numeric) from public, anon;
revoke execute on function fn_set_rendimiento(uuid, int, int, numeric, text) from public, anon;
revoke execute on function fn_quitar_rendimiento(uuid, int, int) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (106, 'editar_base_legal_y_rendimiento')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
