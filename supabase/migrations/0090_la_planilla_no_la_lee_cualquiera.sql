-- ============================================================================
-- 0090 — La planilla no la lee cualquiera (arregla un daño de la 0076)
-- ----------------------------------------------------------------------------
-- PROMETE: que calcular la planilla exija ser administrador o líder, y que ese
--   permiso viva DENTRO de la función, donde ningún grant futuro pueda quitarlo.
--
-- ASUME: 0076 (que causó esto) y el resto hasta la 0089.
--
-- QUÉ PASÓ. La 0076 cerró la ejecución anónima recorriendo todas las funciones
--   de `public` con un `grant execute ... to authenticated` seguido de un
--   `revoke ... from public`. El grant era necesario: los helpers de RLS nunca
--   tuvieron permiso explícito y revocar primero habría tumbado el sistema.
--
--   Pero el bucle no tenía excepciones, y DOS funciones estaban revocadas de
--   `authenticated` a propósito desde las migraciones 0025/0026/0027 y 0032:
--
--     fn_planilla_calcular   devuelve, por persona: nombre, sede, rango,
--                            salario de referencia, pago base, bonos,
--                            descuentos, total y las tres provisiones.
--     fn_objetivos_sync_mes  escribe los objetivos del mes de todo el equipo.
--
--   El bucle las volvió a abrir. Comprobado en laboratorio: con la sesión de una
--   integrante —que por RLS no puede leer ni una fila de asignaciones_salario—
--   fn_planilla_calcular devolvía los cuatro sueldos del equipo. Y con la sesión
--   del terminal de tienda, que no es ni siquiera una persona, lo mismo.
--
--   El comentario que escribí en la 0076 decía «esto NO cambia lo que puede
--   hacer un usuario con sesión». Era cierto para las funciones abiertas por el
--   EXECUTE que Postgres da a PUBLIC, y falso justo para las dos que alguien
--   había cerrado a mano. Un barrido sin lista negra no distingue una cosa de
--   la otra.
--
-- POR QUÉ EL GUARD VA DENTRO Y NO EN UN REVOKE. Porque un revoke ya falló una
--   vez, exactamente así. Las tres funciones hermanas de esta
--   (fn_provisiones, fn_proyeccion_planilla, fn_simular_planilla) sí comprueban
--   el permiso en su cuerpo; fn_simular_planilla es literalmente un envoltorio
--   que valida y luego llama a fn_planilla_calcular. El guard estaba en el
--   envoltorio y faltaba en el núcleo.
--
-- QUIÉN LA LLAMA (comprobado: todos pasan el guard sin problema):
--   fn_simular_planilla, fn_proyeccion_periodo y fn_periodos — las tres son de
--   admin y ya validan antes.
--
-- CÓMO SE REVIERTE: restaurar la definición desde la 0069 y volver a conceder.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_planilla_calcular(p_ini date, p_fin date, p_periodo_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_dias int; v_base numeric;
  v_feriados jsonb; v_out jsonb; v_prov jsonb;
  v_f_grati numeric; v_f_cts numeric; v_f_vacas numeric;
  v_asig numeric; v_anio int; v_mes int;
begin
  -- El guard va DENTRO, no en un revoke. Esta función estaba protegida solo por
  -- un `revoke ... from authenticated` (0025/0026/0027), y el bucle de grants de
  -- la 0076 lo deshizo sin que nada avisara: durante unas horas cualquier sesión
  -- con login —incluida la del terminal de tienda, que no es ni una persona—
  -- podía leer nombre, sede, rango, salario, bonos, descuentos y total de todo
  -- el equipo. Un revoke se puede deshacer por accidente; esto no.
  --
  -- Sus tres hermanas (fn_provisiones, fn_proyeccion_planilla, fn_simular_planilla)
  -- ya lo tenían: el guard estaba en el envoltorio y faltaba en el núcleo.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede calcular la planilla.';
  end if;

  v_dias := (p_fin - p_ini) + 1;
  v_base := 6.5 * v_dias;
  v_anio := extract(year from p_fin)::int;
  v_mes := extract(month from p_fin)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion": 0.08333, "cts": 0.04167, "vacaciones": 0.04167}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vacas := coalesce((v_prov->>'vacaciones')::numeric, 0);

  select coalesce((valor->>'monto')::numeric, 113.00) into v_asig
  from configuracion where clave = 'asignacion_familiar';
  if v_asig is null then v_asig := 113.00; end if;

  select coalesce(jsonb_agg(jsonb_build_object('fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
    into v_feriados
  from feriados f
  where f.fecha between p_ini and p_fin;

  with pers as (
    select p.id, p.nombres, p.apellidos, p.estado, p.con_hijos, p.fecha_ingreso, p.sueldo_fijo, s.codigo as sede
    from personas p
    join sedes s on s.id = p.sede_base_id
    where p.estado = 'activo'
       or exists (select 1 from jornadas j where j.persona_id = p.id and j.fecha between p_ini and p_fin)
       or (p_periodo_id is not null and exists (
             select 1 from movimientos_planilla m
             where m.persona_id = p.id and m.periodo_id = p_periodo_id))
  ),
  horas as (
    select j.persona_id, j.fecha,
           coalesce(j.horas_trabajadas, 0) as h,
           (j.estado = 'auto_cerrada_pendiente') as pendiente
    from jornadas j
    where j.fecha between p_ini and p_fin
  ),
  tramos as (
    select a.persona_id, a.rango, a.salario_mensual_soles as salario,
           greatest(a.vigente_desde, p_ini) as t_ini,
           least(coalesce(a.vigente_hasta, p_fin), p_fin) as t_fin
    from asignaciones_salario a
    where a.vigente_desde <= p_fin
      and (a.vigente_hasta is null or a.vigente_hasta >= p_ini)
  )
  select jsonb_build_object(
    'fecha_ini', p_ini,
    'fecha_fin', p_fin,
    'anio_etiqueta', v_anio,
    'mes_etiqueta', v_mes,
    'dias', v_dias,
    'base_horas', v_base,
    'feriados', v_feriados,
    'factores_provision', v_prov,
    'asignacion_monto', v_asig,
    'filas', coalesce(jsonb_agg(sub.fila order by sub.orden_nombre), '[]'::jsonb)
  )
  into v_out
  from (
    select (pe.nombres || ' ' || pe.apellidos) as orden_nombre,
      jsonb_build_object(
        'persona_id', pe.id,
        'nombre', pe.nombres || ' ' || pe.apellidos,
        'sede', pe.sede,
        'estado', pe.estado,
        'fecha_ingreso', pe.fecha_ingreso,
        'rango', ref.rango,
        'salario_ref', ref.salario,
        'horas_mes', round(h.horas_mes, 2),
        'dias_trabajados', h.dias,
        'dias_pendientes', h.pendientes,
        'horas_sin_salario', round(pb.horas_sin_salario, 2),
        'pago_base', round(pb.pago_base, 2),
        'feriados_detalle', fer.detalle,
        'monto_feriados', round(fer.monto, 2),
        'feriados_no_corresponde', fer.no_corresponde,
        'feriados_compensados', fer.compensados,
        'objetivos_cumplidos', obj.cumplidos,
        'objetivos_total', obj.total,
        'monto_plus', round(obj.monto, 2),
        'bajo_desempeno', (obj.cumplidos is not null and obj.total > 0
                           and obj.cumplidos::numeric / obj.total < 0.3),
        'feriados_sin_salario', fer.sin_tramo,
        'con_hijos', pe.con_hijos,
        'asignacion_familiar', case when pe.con_hijos then round(v_asig, 2) else 0 end,
        'bonos', round(mov.bonos, 2),
        'descuentos', round(mov.descuentos, 2),
        'movimientos', mov.detalle,
        'provision_gratificacion', round((pb.pago_base + fer.monto) * v_f_grati, 2),
        'provision_cts', round((pb.pago_base + fer.monto) * v_f_cts, 2),
        'provision_vacaciones', round((pb.pago_base + fer.monto) * v_f_vacas, 2),
        'provision_total', round((pb.pago_base + fer.monto) * (v_f_grati + v_f_cts + v_f_vacas), 2),
        'total', round(pb.pago_base, 2) + round(fer.monto, 2) + round(obj.monto, 2)
                 + (case when pe.con_hijos then round(v_asig, 2) else 0 end)
                 + round(mov.bonos, 2) - round(mov.descuentos, 2)
      ) as fila
    from pers pe
    left join lateral (
      select coalesce(sum(x.h), 0) as horas_mes,
             count(*) filter (where x.h > 0) as dias,
             count(*) filter (where x.pendiente) as pendientes
      from horas x where x.persona_id = pe.id
    ) h on true
    left join lateral (
      -- SUELDO FIJO: quien lo tiene cobra su remuneración completa del periodo,
      -- marque o no (socios, dirección). Para el resto la fórmula es EXACTAMENTE
      -- la de siempre — la rama `else` es idéntica a la anterior, así que ningún
      -- pago existente se mueve.
      select case when pe.sueldo_fijo then coalesce(sf.salario, 0)
                  else coalesce(hh.pago, 0) end as pago_base,
             coalesce(hh.sin_sal, 0) as horas_sin_salario
      from (select 1) _sf
      left join lateral (
        select coalesce(sum(case when tt.salario is not null then x.h * tt.salario / v_base end), 0) as pago,
               coalesce(sum(case when tt.salario is null then x.h end), 0) as sin_sal
        from horas x
        left join lateral (
          select t.salario from tramos t
          where t.persona_id = x.persona_id and x.fecha between t.t_ini and t.t_fin
          order by t.t_ini desc limit 1
        ) tt on true
        where x.persona_id = pe.id
      ) hh on true
      left join lateral (
        select t.salario from tramos t
        where t.persona_id = pe.id
        order by t.t_fin desc, t.t_ini desc limit 1
      ) sf on true
    ) pb on true
    left join lateral (
      select t.rango, t.salario
      from tramos t
      where t.persona_id = pe.id
      order by t.t_fin desc, t.t_ini desc
      limit 1
    ) ref on true
    -- feriados: solo cuentan los que caen EN o DESPUÉS del ingreso de la persona
    left join lateral (
      -- ⇩⇩⇩ CAMBIO 0069 ⇩⇩⇩
      -- `ds.otorgado` = ese feriado se compensó con día libre (acta firmada).
      -- Cuando es true se anula el pago EXTRA de las horas laboradas (la
      -- sobretasa) y queda solo el día de feriado prorrateado — el feriado vale
      -- lo mismo que si no se hubiera trabajado. Las horas siguen pagadas en
      -- `pago_base`. Para volver a la lectura literal "adicional = 0",
      -- reemplazar todo el paréntesis por `0`.
      select coalesce(sum(case when tt.salario is not null and f.fecha >= pe.fecha_ingreso
               then ((case when ds.otorgado then 0 else coalesce(hf.h, 0) end)
                     + 7.5 * h.horas_mes / v_base) * tt.salario / v_base end), 0) as monto,
             count(*) filter (where tt.salario is null and f.fecha >= pe.fecha_ingreso) as sin_tramo,
             count(*) filter (where f.fecha < pe.fecha_ingreso) as no_corresponde,
             count(*) filter (where ds.otorgado) as compensados,
             coalesce(jsonb_agg(jsonb_build_object(
               'fecha', f.fecha,
               'horas_trabajadas', coalesce(hf.h, 0),
               'proporcional_horas', case when f.fecha >= pe.fecha_ingreso
                                          then round(7.5 * h.horas_mes / v_base, 2) else 0 end,
               'sin_salario', (tt.salario is null and f.fecha >= pe.fecha_ingreso),
               'antes_ingreso', (f.fecha < pe.fecha_ingreso),
               'descanso_sustitutorio', ds.otorgado,
               'descanso_fecha', ds.fecha_descanso
             ) order by f.fecha), '[]'::jsonb) as detalle
      from feriados f
      left join lateral (
        select t.salario from tramos t
        where t.persona_id = pe.id and f.fecha between t.t_ini and t.t_fin
        order by t.t_ini desc limit 1
      ) tt on true
      left join horas hf on hf.persona_id = pe.id and hf.fecha = f.fecha
      left join lateral (
        -- Solo OTORGADO anula la sobretasa. PENDIENTE y NO_OTORGADO pagan
        -- normal — VALIDACIÓN 3: NO_OTORGADO revierte solo, sin tocar nada.
        select true as otorgado, d.fecha_descanso_sustitutorio as fecha_descanso
        from feriados_descanso_sustitutorio d
        where d.persona_id = pe.id and d.fecha_feriado = f.fecha and d.estado = 'OTORGADO'
        limit 1
      ) ds on true
      where f.fecha between p_ini and p_fin
      -- ⇧⇧⇧ CAMBIO 0069 ⇧⇧⇧
    ) fer on true
    left join lateral (
      select om.cumplidos, om.total,
             case
               when om.cumplidos is null or ref.salario is null then 0
               when om.cumplidos::numeric / om.total >= 1 then 0.21 * ref.salario
               when om.cumplidos::numeric / om.total >= 0.6 then 0.126 * ref.salario
               else 0
             end as monto
      from (select 1) uno
      left join objetivos_mensuales om
        on om.persona_id = pe.id and om.anio = v_anio and om.mes = v_mes
    ) obj on true
    left join lateral (
      select coalesce(sum(m.monto) filter (where m.tipo = 'bono'), 0) as bonos,
             coalesce(sum(m.monto) filter (where m.tipo = 'descuento'), 0) as descuentos,
             coalesce(jsonb_agg(jsonb_build_object(
               'id', m.id, 'tipo', m.tipo, 'concepto', m.concepto, 'monto', m.monto
             ) order by m.created_at) filter (where m.id is not null), '[]'::jsonb) as detalle
      from movimientos_planilla m
      where p_periodo_id is not null
        and m.periodo_id = p_periodo_id
        and m.persona_id = pe.id
    ) mov on true
  ) sub;

  return v_out;
end;
$function$;

-- ── El revoke, además del guard ──────────────────────────────────────────────
-- No sustituye al guard: lo acompaña. Si un futuro barrido vuelve a conceder,
-- el guard sigue negando.
revoke execute on function fn_planilla_calcular(date, date, uuid) from authenticated, anon, public;
revoke execute on function fn_objetivos_sync_mes(uuid, int, int) from authenticated, anon, public;

-- ── Y la lista negra, para que ningún barrido futuro las toque ───────────────
-- La 0076 recorrió todas las funciones sin excepciones. Esta tabla existe para
-- que el próximo bucle (habrá uno) sepa qué no debe conceder nunca.
create table if not exists funciones_nunca_para_authenticated (
  funcion text primary key,
  motivo  text not null,
  desde   date not null default current_date
);
comment on table funciones_nunca_para_authenticated is
  'Funciones que NO deben concederse a authenticated. Todo barrido de permisos debe saltarlas. Nacida de la 0090: la 0076 abrió la planilla entera a cualquier sesión al conceder en masa.';

insert into funciones_nunca_para_authenticated (funcion, motivo) values
  ('fn_planilla_calcular',  'Devuelve el sueldo, los bonos y el total de todas las personas.'),
  ('fn_objetivos_sync_mes', 'Escribe los objetivos del mes de todo el equipo.')
on conflict (funcion) do nothing;

alter table funciones_nunca_para_authenticated enable row level security;
revoke all on funciones_nunca_para_authenticated from authenticated, anon;

insert into migraciones_aplicadas (numero, nombre)
values (90, 'la_planilla_no_la_lee_cualquiera')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
