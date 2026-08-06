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
