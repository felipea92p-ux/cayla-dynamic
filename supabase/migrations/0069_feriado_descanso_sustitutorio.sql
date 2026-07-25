-- ============================================================================
-- 0069 — Feriado laborado con descanso sustitutorio (D. Leg. 713)
-- ----------------------------------------------------------------------------
-- Hasta ahora el sistema asumía UNA sola salida para el feriado laborado: la
-- sobretasa. La norma condiciona esa sobretasa a que NO se otorgue descanso
-- compensatorio. Son dos salidas, y faltaba la segunda.
--
-- CÓMO PAGA HOY fn_planilla_calcular (0047) — importante para entender el cambio.
-- No paga "3 remuneraciones diarias" de forma plana; el pago es por horas:
--
--     monto_feriado = ( horas_marcadas_ese_dia  +  7.5 * horas_mes / base_horas )
--                     * salario / base_horas
--
--   · Las horas marcadas del feriado YA entran en `pago_base` (1 RD).
--   · El primer término las paga OTRA VEZ  → la labor efectuada (1 RD).
--   · El segundo término es el día de feriado prorrateado al ritmo real de
--     trabajo del mes (1 RD).
--   Total = 3 RD, es decir 2 RD ADICIONALES. Coincide con la norma.
--
-- QUÉ CAMBIA CON DESCANSO SUSTITUTORIO OTORGADO:
--   Se elimina SOLO el primer término (el pago extra de la labor). Queda:
--
--     monto_feriado = 7.5 * horas_mes / base_horas * salario / base_horas
--
--   O sea, el feriado pasa a valer exactamente lo que vale un feriado NO
--   laborado: un día de feriado prorrateado. La persona conserva la paga de
--   las horas que trabajó (siguen en `pago_base`) y el día compensatorio es su
--   descanso. Adicional por sobretasa = 0.
--
-- ⚠️ DECISIÓN DE DISEÑO — LEER. El documento de origen dice "adicional = 0".
--   Tomado al pie de la letra sobre ESTE motor (que paga por horas, no un
--   sueldo mensual íntegro) eso borraría también el día de feriado prorrateado,
--   y la persona terminaría cobrando MENOS que si el feriado no se hubiera
--   trabajado: no cobra el feriado y tampoco cobra el día compensatorio (no lo
--   marca). Sería un castigo por trabajar el feriado — lo contrario de la norma.
--   Por eso "adicional = 0" se implementa como "0 de SOBRETASA", conservando el
--   día de feriado. Es además la fórmula que Felipe describió: "solo contaría
--   como un día de feriado y aplicaríamos total de horas laboradas entre total
--   de horas base del mes por el pago por hora".
--   Si la intención era la lectura literal, cambiar el `case` marcado ABAJO.
--
-- Reversible: soltar la tabla, el trigger y las funciones, y restaurar
-- fn_planilla_calcular desde 0047.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Tabla: un registro por feriado laborado que se compensa con día libre.
-- ---------------------------------------------------------------------------
create table if not exists feriados_descanso_sustitutorio (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id) on delete cascade,
  fecha_feriado date not null references feriados(fecha) on delete restrict,
  fecha_descanso_sustitutorio date not null,
  estado text not null default 'PENDIENTE'
    check (estado in ('PENDIENTE', 'OTORGADO', 'NO_OTORGADO')),
  acta_ref text,
  otorgado_por uuid references personas(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- VALIDACIÓN 1 — relación 1:1, por los dos lados:
  --   · un feriado no se compensa dos veces
  constraint uq_dcs_feriado unique (persona_id, fecha_feriado),
  --   · un mismo día libre no compensa dos feriados
  constraint uq_dcs_descanso unique (persona_id, fecha_descanso_sustitutorio),

  -- VALIDACIÓN 4 — sin acta firmada no se puede pasar a OTORGADO.
  -- Ante fiscalización, un descanso sin respaldo no existe.
  constraint chk_dcs_acta check (
    estado <> 'OTORGADO'
    or (acta_ref is not null and length(trim(acta_ref)) >= 3)
  ),

  -- El día compensatorio no puede ser el mismo feriado.
  constraint chk_dcs_dias_distintos check (fecha_descanso_sustitutorio <> fecha_feriado)
);

comment on table feriados_descanso_sustitutorio is
  'Feriados laborados compensados con día libre (D. Leg. 713). Con estado OTORGADO el feriado deja de pagar sobretasa y vale como feriado no laborado.';
comment on column feriados_descanso_sustitutorio.estado is
  'PENDIENTE = acordado, aún sin respaldo/ejecución · OTORGADO = descanso efectivo y con acta (anula la sobretasa) · NO_OTORGADO = no se dio; la planilla vuelve a pagar la sobretasa.';
comment on column feriados_descanso_sustitutorio.acta_ref is
  'Documento firmado que respalda el acuerdo. Obligatorio para OTORGADO.';

create index if not exists idx_dcs_persona_feriado
  on feriados_descanso_sustitutorio(persona_id, fecha_feriado);
create index if not exists idx_dcs_estado
  on feriados_descanso_sustitutorio(estado) where estado = 'OTORGADO';

-- ---------------------------------------------------------------------------
-- VALIDACIÓN 2 — el descanso no puede caer en el día de descanso semanal.
-- Un día libre sobre un día que ya era libre no compensa nada: sería regalar
-- la sobretasa a cambio de nada. Se replica la MISMA prioridad que usa
-- fn_recalcular_jornada (0016) para saber si un día es laborable:
--     turno puntual del día  →  horario_por_dia (jsonb)  →  dias_laborables (legacy)
-- ---------------------------------------------------------------------------
create or replace function fn_dcs_validar_dia_laborable()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_dow text;
  v_es_descanso boolean;
  v_hpd jsonb;
  v_dias int[];
begin
  v_dow := extract(dow from new.fecha_descanso_sustitutorio)::int::text; -- 0=domingo … 6=sábado

  -- Prioridad 1: turno puntual de ese día
  select t.es_descanso into v_es_descanso
  from turnos t
  where t.persona_id = new.persona_id and t.fecha = new.fecha_descanso_sustitutorio;

  if found then
    if v_es_descanso then
      raise exception 'El % ya es descanso programado de esa persona: un descanso sustitutorio en ese día no compensa nada.',
        to_char(new.fecha_descanso_sustitutorio, 'DD/MM/YYYY');
    end if;
    return new;
  end if;

  -- Prioridad 2: horario base vigente a esa fecha
  select h.horario_por_dia, h.dias_laborables into v_hpd, v_dias
  from horarios_asignados h
  where h.persona_id = new.persona_id
    and h.vigente_desde <= new.fecha_descanso_sustitutorio
    and (h.vigente_hasta is null or h.vigente_hasta >= new.fecha_descanso_sustitutorio)
  order by h.vigente_desde desc
  limit 1;

  if not found then
    raise exception 'Esa persona no tiene horario vigente al %: no se puede verificar que el día compensatorio sea laborable.',
      to_char(new.fecha_descanso_sustitutorio, 'DD/MM/YYYY');
  end if;

  if v_hpd is not null then
    -- día AUSENTE en el jsonb = descanso (convención de 0016)
    if (v_hpd -> v_dow) is null then
      raise exception 'El % cae en el día de descanso semanal de esa persona: no compensa el feriado laborado.',
        to_char(new.fecha_descanso_sustitutorio, 'DD/MM/YYYY');
    end if;
  elsif v_dias is not null then
    if not (v_dow::int = any(v_dias)) then
      raise exception 'El % cae en el día de descanso semanal de esa persona: no compensa el feriado laborado.',
        to_char(new.fecha_descanso_sustitutorio, 'DD/MM/YYYY');
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_dcs_validar_dia on feriados_descanso_sustitutorio;
create trigger trg_dcs_validar_dia
  before insert or update of fecha_descanso_sustitutorio, persona_id, estado
  on feriados_descanso_sustitutorio
  for each row execute function fn_dcs_validar_dia_laborable();

-- ---------------------------------------------------------------------------
-- Única vía para crear/cambiar estos registros. Solo admin o líder.
-- Mismo patrón de permisos que fn_revertir_pago (0066).
-- ---------------------------------------------------------------------------
create or replace function fn_otorgar_descanso_sustitutorio(
  p_persona_id uuid,
  p_fecha_feriado date,
  p_fecha_descanso date,
  p_estado text default 'PENDIENTE',
  p_acta_ref text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un descanso sustitutorio.';
  end if;

  if p_estado not in ('PENDIENTE', 'OTORGADO', 'NO_OTORGADO') then
    raise exception 'Estado inválido: %. Debe ser PENDIENTE, OTORGADO o NO_OTORGADO.', p_estado;
  end if;

  if not exists (select 1 from feriados where fecha = p_fecha_feriado) then
    raise exception 'El % no está registrado como feriado.', to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  -- El feriado tiene que haberse LABORADO: si no hay horas marcadas, no hay
  -- sobretasa que compensar y este registro no tiene sentido.
  if not exists (
    select 1 from jornadas j
    where j.persona_id = p_persona_id and j.fecha = p_fecha_feriado
      and coalesce(j.horas_trabajadas, 0) > 0
  ) then
    raise exception 'Esa persona no tiene horas marcadas el % : el feriado no fue laborado.',
      to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  insert into feriados_descanso_sustitutorio (
    persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado, acta_ref, otorgado_por
  )
  values (
    p_persona_id, p_fecha_feriado, p_fecha_descanso, p_estado, nullif(trim(p_acta_ref), ''), fn_persona_actual_id()
  )
  on conflict (persona_id, fecha_feriado) do update set
    fecha_descanso_sustitutorio = excluded.fecha_descanso_sustitutorio,
    estado = excluded.estado,
    acta_ref = excluded.acta_ref,
    otorgado_por = excluded.otorgado_por,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function fn_otorgar_descanso_sustitutorio(uuid, date, date, text, text) to authenticated;
revoke execute on function fn_otorgar_descanso_sustitutorio(uuid, date, date, text, text) from public, anon;

alter table feriados_descanso_sustitutorio enable row level security;
drop policy if exists dcs_select_admin_lider on feriados_descanso_sustitutorio;
create policy dcs_select_admin_lider on feriados_descanso_sustitutorio
  for select using (fn_es_admin_o_lider());

-- ============================================================================
-- fn_planilla_calcular — versión de 0047 con UN cambio quirúrgico.
-- ----------------------------------------------------------------------------
-- Se copió el texto vigente (0047) y se le aplicó un solo cambio, igual que
-- hizo 0047 con 0027: no se reescribió el cálculo a mano, para no introducir
-- errores de transcripción en 180 líneas de dinero. Lo único que cambia es el
-- bloque `fer` (marcado con ⇩ CAMBIO 0069 ⇩). Todo lo demás es idéntico:
-- nadie que no tenga un descanso sustitutorio OTORGADO se mueve un centavo.
-- ============================================================================
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
$$;

notify pgrst, 'reload schema';

-- ============================================================================
-- VALIDACIÓN 5 — el día compensatorio NO descuenta vacaciones: se cumple por
-- diseño, esta migración nunca escribe en `vacaciones`.
--
-- ⚠️ HUECO CONOCIDO, NO CUBIERTO AQUÍ: el módulo de faltas (0051/0060) puede
-- marcar el día compensatorio como inasistencia injustificada, porque no sabe
-- que ese día es un descanso autorizado. Toca otro módulo (disciplina) y se
-- deja señalado a propósito en vez de modificarlo de paso.
-- ============================================================================
