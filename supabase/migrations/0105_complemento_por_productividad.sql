-- ============================================================================
-- 0105 — Complemento por Productividad: que la parte variable de verdad varíe.
--
-- QUÉ PROBLEMA RESUELVE. La 0104 partía el pago base en «básica legal» y
-- «complemento variable», pero ese complemento NO variaba nunca: salía de
-- dividir un sueldo que ya era fijo, así que se pagaba igual con 0% que con 100%
-- de rendimiento. Cualquiera que compare seis boletas lo ve: la etiqueta decía
-- «variable» y el número era el mismo todos los meses. Etiquetar no separa.
--
-- LA ECUACIÓN. Ahora el salario de cada día se compone:
--
--     brecha  = salario del rango − básica legal
--     del día = básica legal + brecha × (puntuación / 100)
--
--   · Al 100% de puntuación: básica + brecha = el salario del rango, exacto.
--     Nadie que rinda al máximo cobra un céntimo menos que hoy.
--   · Al 0%: la básica legal.
--   · Sin puntuación asignada: el salario del rango, IGUAL QUE HOY.
--
-- ESTO ES EL INTERRUPTOR, y es lo más importante de esta migración: mientras
-- nadie tenga fila en rendimiento_mensual, el pago de TODO el equipo sale
-- idéntico al de antes. La migración se puede desplegar sin mover el sueldo de
-- una sola persona. Se activa a mano, alguien a la vez, cuando Felipe decida.
--
-- TRES GUARDAS PARA NO PAGAR DE MENOS POR ERROR:
--   · Sin puntuación o sin sueldo_base_legal (0103) → el salario del tramo.
--   · Si el tramo está por debajo de la básica legal → el tramo, no se sube.
--   · Sueldo fijo (socios, dirección) → intacto, fuera de este mecanismo.
--
-- LA ETIQUETA ES UN DATO, NO CÓDIGO. Cada fila de rendimiento_mensual guarda qué
-- etiqueta se usó ese mes, elegida del catálogo etiquetas_complemento. Así se
-- puede cambiar el nombre del concepto mes a mes sin tocar el programa, y queda
-- el rastro de qué nombre llevaba cada pago. Decidido con Felipe el 2026-07-28.
--
-- ── ADVERTENCIA QUE NO SE PUEDE RESOLVER CON CÓDIGO ─────────────────────────
-- El propósito declarado de esta estructura es que el complemento NO sea
-- remuneración computable, al amparo del Art. 19 del D.S. 001-97-TR. Pero ese
-- artículo excluye pagos OCASIONALES, y este se paga todos los meses. Un pago
-- regular de monto variable, según el entendimiento con el que se escribió esto,
-- entra al cálculo de CTS y gratificaciones PROMEDIADO, no excluido.
--
-- O sea: hacer que el monto varíe no basta para sacarlo del cómputo si se paga
-- todos los meses. Esto NO fue confirmado por un abogado laboralista peruano, y
-- todo el diseño se apoya en ello. Está advertido en la conversación del
-- 2026-07-28 y sigue pendiente de verificar.
--
-- CÓMO SE REVIERTE: restaurar fn_planilla_calcular desde la 0100 y borrar las dos
-- tablas. Nada más depende de ellas. Mientras rendimiento_mensual esté vacía,
-- revertir no cambia ningún pago.
-- ============================================================================

-- ── Catálogo de etiquetas ───────────────────────────────────────────────────
-- «Una base y amplias opciones»: el nombre del concepto se elige de aquí, no se
-- escribe a mano en cada fila, para que dos meses no acaben con dos grafías del
-- mismo nombre en documentos que pueden acabar comparados.
create table if not exists etiquetas_complemento (
  codigo      text primary key,
  etiqueta    text not null,
  nota        text,
  orden       int  not null default 100,
  activa      boolean not null default true,
  created_at  timestamptz not null default now()
);

insert into etiquetas_complemento (codigo, etiqueta, nota, orden) values
  ('complemento_productividad',
   'Complemento por Productividad',
   'Opción por defecto. «Complemento» dice que suma a la básica sin ser parte de ella. Evita «bonificación», que es la palabra que más fácil se argumenta como remuneración cuando el pago es regular.', 1),
  ('rendimiento_extraordinario',
   'Rendimiento Extraordinario Variable',
   'Empuja hacia el lenguaje del Art. 19. Riesgo: si se paga todos los meses, llamarlo extraordinario contradice el hecho, y la contradicción está en el propio documento.', 2),
  ('incentivo_productividad',
   'Incentivo Variable por Productividad',
   'Paralelo al «Incentivo Variable por Metas» del plus de objetivos. Coherente en la boleta, pero los dos se pueden confundir al leer rápido.', 3),
  ('complemento_operativo',
   'Complemento por Rendimiento Operativo',
   'Recoge la expresión que Felipe usa en la cabecera («Potencial Máximo de Rendimiento Operativo»), así el documento habla consigo mismo.', 4),
  ('asignacion_desempeno',
   'Asignación Variable por Desempeño',
   'Neutra y descriptiva. «Asignación» suena a concepto de planilla, lo cual puede jugar en contra si lo que se busca es distanciarlo de la remuneración.', 5)
on conflict (codigo) do nothing;

-- ── Puntuación por persona y mes ────────────────────────────────────────────
create table if not exists rendimiento_mensual (
  persona_id     uuid not null references personas(id) on delete cascade,
  anio           int  not null,
  mes            int  not null check (mes between 1 and 12),
  porcentaje     numeric(5,2) not null check (porcentaje >= 0 and porcentaje <= 100),
  etiqueta_codigo text references etiquetas_complemento(codigo),
  nota           text,
  puesto_por     uuid references personas(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (persona_id, anio, mes)
);

create index if not exists idx_rendimiento_mensual_periodo
  on rendimiento_mensual(anio, mes);

drop trigger if exists trg_rendimiento_mensual_updated_at on rendimiento_mensual;
create trigger trg_rendimiento_mensual_updated_at
  before update on rendimiento_mensual
  for each row execute function fn_set_updated_at();

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- Esta tabla decide cuánto cobra alguien, así que se lee y se escribe con el
-- mismo candado que la planilla (0090): solo admin o líder.
alter table etiquetas_complemento enable row level security;
alter table rendimiento_mensual   enable row level security;

drop policy if exists etiquetas_complemento_select on etiquetas_complemento;
create policy etiquetas_complemento_select on etiquetas_complemento
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists rendimiento_mensual_select on rendimiento_mensual;
create policy rendimiento_mensual_select on rendimiento_mensual
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists rendimiento_mensual_write on rendimiento_mensual;
create policy rendimiento_mensual_write on rendimiento_mensual
  for all to authenticated
  using (fn_es_admin_o_lider()) with check (fn_es_admin_o_lider());

-- ── El cálculo ──────────────────────────────────────────────────────────────
-- Reemitida desde la 0100 con cuatro cambios marcados «CAMBIO 0105». El resto es
-- byte por byte lo que ya estaba: se extrajo de la 0100 y se parcheó con un
-- script, no se retipeó a mano, para que ninguna línea de pago cambie por
-- descuido.

create or replace function fn_planilla_calcular(p_ini date, p_fin date, p_periodo_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_dias int; v_base numeric;
  v_feriados jsonb; v_out jsonb; v_prov jsonb;
  v_f_grati numeric; v_f_cts numeric; v_f_vacas numeric;
  v_asig numeric; v_anio int; v_mes int;
begin
  -- ⚠️ ESTE GUARD ES DE LA 0090 Y NO SE TOCA NUNCA.
  -- La 0076 abrió esta función a cualquier sesión con login —el terminal de
  -- tienda incluido— al conceder permisos en masa, y la 0090 lo cerró poniendo
  -- la comprobación DENTRO de la función, porque un `revoke` se deshace solo la
  -- próxima vez que alguien conceda en masa y un guard no.
  -- Quien copie este cuerpo para otra migración tiene que copiar esto también:
  -- al escribir la 0100 se copió el texto de la 0069, que es anterior, y el
  -- guard desapareció sin que nada fallara salvo la prueba 91.
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
    select p.id, p.nombres, p.apellidos, p.estado, p.con_hijos, p.fecha_ingreso, p.sueldo_fijo,
           p.sueldo_base_legal,   -- CAMBIO 0105
           s.codigo as sede
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
        -- ⇩ CAMBIO 0100 ⇩ por qué esta persona está en cero. Sin esto, «de
        -- vacaciones», «no marcó» y «sin salario» se ven exactamente igual: 0.
        'dias_vacaciones', vac.dias,
        'dias_laborables', lab.dias,
        'horas_sin_salario', round(pb.horas_sin_salario, 2),
        'pago_base', round(pb.pago_base, 2),
        -- CAMBIO 0105 — Desglose legal. Solo sale cuando hay básica legal fijada
        -- Y puntuación del mes: si falta cualquiera de las dos, NULL y la boleta
        -- muestra el pago base sin partir, en vez de inventar una separación.
        -- Los de sueldo fijo (socios, dirección) quedan fuera a propósito.
        'basica_legal_prop',
          case when pe.sueldo_base_legal is null or rmp.porcentaje is null or pe.sueldo_fijo
               then null else round(pb.basica, 2) end,
        'complemento_variable',
          case when pe.sueldo_base_legal is null or rmp.porcentaje is null or pe.sueldo_fijo
               then null else round(pb.pago_base, 2) - round(pb.basica, 2) end,
        'rendimiento_pct', case when pe.sueldo_fijo then null else rmp.porcentaje end,
        'complemento_etiqueta',
          case when rmp.porcentaje is null or pe.sueldo_fijo then null else rmp.etiqueta end,
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
      -- CAMBIO 0105 — Puntuación de productividad del mes. Si no hay fila para
      -- esta persona en este mes, porcentaje sale NULL y TODO el cálculo de abajo
      -- se comporta exactamente como antes de esta migración. Es el interruptor:
      -- sin puntuación asignada, nadie cobra distinto.
      select rm.porcentaje,
             coalesce(ec.etiqueta, 'Complemento por Productividad') as etiqueta
      from rendimiento_mensual rm
      left join etiquetas_complemento ec on ec.codigo = rm.etiqueta_codigo
      where rm.persona_id = pe.id and rm.anio = v_anio and rm.mes = v_mes
      limit 1
    ) rmp on true
    left join lateral (
      -- SUELDO FIJO: quien lo tiene cobra su remuneración completa del periodo,
      -- marque o no (socios, dirección). Para el resto la fórmula es EXACTAMENTE
      -- la de siempre — la rama `else` es idéntica a la anterior, así que ningún
      -- pago existente se mueve.
      select case when pe.sueldo_fijo then coalesce(sf.salario, 0)
                  else coalesce(hh.pago, 0) end as pago_base,
             coalesce(hh.basica, 0) as basica,   -- CAMBIO 0105
             coalesce(hh.sin_sal, 0) as horas_sin_salario
      from (select 1) _sf
      left join lateral (
        -- ⇩ CAMBIO 0105 ⇩ El salario del día deja de ser un bloque único: es la
        -- básica legal más la brecha hasta el rango, multiplicada por la
        -- puntuación del mes. Tres guardas para que nunca pague de menos:
        --   · sin puntuación o sin básica legal → el salario del tramo, como siempre
        --   · si el tramo está por debajo de la básica → el tramo, sin subirlo
        --   · al 100% de puntuación → base + (rango − base) = el rango exacto
        select coalesce(sum(case when tt.salario is not null then x.h * (
                 case
                   when rmp.porcentaje is null or pe.sueldo_base_legal is null then tt.salario
                   when tt.salario <= pe.sueldo_base_legal then tt.salario
                   else pe.sueldo_base_legal
                        + (tt.salario - pe.sueldo_base_legal) * rmp.porcentaje / 100.0
                 end
               ) / v_base end), 0) as pago,
               -- La parte que corresponde a la básica legal NO se escala por la
               -- puntuación: es lo fijo. Se prorratea solo por horas.
               coalesce(sum(case when tt.salario is not null and pe.sueldo_base_legal is not null
                                 then x.h * least(pe.sueldo_base_legal, tt.salario) / v_base end), 0) as basica,
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
    -- ⇩ CAMBIO 0100 ⇩ Días del periodo que caen dentro de un periodo de
    -- vacaciones de esta persona. Solo se LEE: esta función nunca escribe.
    left join lateral (
      select count(*)::int as dias
      from generate_series(p_ini, p_fin, interval '1 day') d
      where exists (
        select 1 from vacaciones v
        where v.persona_id = pe.id
          and d.d::date between v.fecha_inicio and v.fecha_fin
      )
    ) vac on true
    -- Días que esta persona TENÍA que trabajar según su horario vigente. Si son
    -- cero, no marcó porque no le tocaba: no es una ausencia, es un dato que falta.
    left join lateral (
      select count(*)::int as dias
      from generate_series(p_ini, p_fin, interval '1 day') d
      join lateral (
        select ha.dias_laborables
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
        order by ha.vigente_desde desc limit 1
      ) hh on true
      where extract(isodow from d.d)::int = any(hh.dias_laborables)
    ) lab on true
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
$$;

-- El envoltorio vuelve a su forma de la 0025: la 0104 calculaba el desglose ahí
-- con una fórmula que asumía que la básica escalaba con el pago, y eso deja de
-- ser cierto en cuanto la puntuación entra en juego. Ahora el desglose lo calcula
-- el núcleo, que es donde están las horas y el salario de cada día.
create or replace function fn_proyeccion_periodo(p_periodo_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $wrap$
declare
  v_p record; v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la planilla.';
  end if;
  select * into v_p from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_out := fn_planilla_calcular(v_p.fecha_ini, v_p.fecha_fin, v_p.id);
  return v_out || jsonb_build_object(
    'periodo_id', v_p.id,
    'estado', v_p.estado,
    'pagado_at', v_p.pagado_at,
    'simulacion', false
  );
end;
$wrap$;

grant execute on function fn_proyeccion_periodo(uuid) to authenticated;
revoke execute on function fn_proyeccion_periodo(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (105, 'complemento_por_productividad')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
