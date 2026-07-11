-- Auto-cierre de jornadas olvidadas (regla del plan: si alguien no marcó su
-- salida final tras N horas después de su hora de salida programada, se cierra
-- automáticamente con origen='auto_cierre' y queda pendiente de revisión).
-- fn_registrar_marcaje ya sabe reemplazar el cierre sintético si el marcaje
-- real llega tarde (kiosco offline que sincroniza después).

-- ============================================================================
-- configuracion — ajustes editables por admin sin tocar código
-- ============================================================================

create table configuracion (
  clave text primary key,
  valor jsonb not null,
  descripcion text
);

insert into configuracion (clave, valor, descripcion) values
  ('auto_cierre_horas', '3', 'Horas después de la hora de salida programada tras las cuales se auto-cierra una jornada abierta');

alter table configuracion enable row level security;

create policy configuracion_select_autenticados on configuracion
  for select to authenticated
  using (true);

create policy configuracion_write_admin_lider on configuracion
  for all to authenticated
  using (fn_es_admin_o_lider())
  with check (fn_es_admin_o_lider());

grant select on configuracion to authenticated;
grant all on configuracion to service_role;

-- ============================================================================
-- fn_auto_cierre — corre por cron; cierra jornadas vencidas
-- ============================================================================

create or replace function fn_auto_cierre()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_horas int;
  v_hoy_lima date := (now() at time zone 'America/Lima')::date;
  v_candidata record;
  v_ts_cierre timestamptz;
  v_cerradas int := 0;
begin
  select (valor #>> '{}')::int into v_horas from configuracion where clave = 'auto_cierre_horas';
  v_horas := coalesce(v_horas, 3);

  for v_candidata in
    select
      j.id as jornada_id,
      j.persona_id,
      j.fecha,
      j.sede_id,
      h.hora_salida
    from jornadas j
    left join lateral (
      select hora_salida
      from horarios_asignados
      where persona_id = j.persona_id
        and vigente_desde <= j.fecha
        and (vigente_hasta is null or vigente_hasta >= j.fecha)
      order by vigente_desde desc
      limit 1
    ) h on true
    where j.estado in ('abierta', 'en_pausa')
      and (
        -- con horario: venció la hora de salida + margen configurable
        (h.hora_salida is not null
          and now() >= ((j.fecha + h.hora_salida) at time zone 'America/Lima') + make_interval(hours => v_horas))
        -- sin horario configurado: cerrar recién al día siguiente
        or (h.hora_salida is null and j.fecha < v_hoy_lima)
      )
  loop
    if v_candidata.hora_salida is not null then
      v_ts_cierre := (v_candidata.fecha + v_candidata.hora_salida) at time zone 'America/Lima';
    else
      -- sin horario: usar la última marca real del día (conservador)
      select max(timestamp_marca) into v_ts_cierre
      from marcajes
      where persona_id = v_candidata.persona_id
        and (timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha;
    end if;

    if v_ts_cierre is null then
      continue;
    end if;

    insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
    values (gen_random_uuid(), v_candidata.persona_id, v_candidata.sede_id, 'salida_final', v_ts_cierre, 'auto_cierre', 'pendiente_revision');

    insert into alertas (persona_id, tipo, canal, payload)
    values (
      v_candidata.persona_id,
      'auto_cierre',
      'push',
      jsonb_build_object('fecha', v_candidata.fecha, 'jornada_id', v_candidata.jornada_id, 'ts_cierre', v_ts_cierre)
    );

    v_cerradas := v_cerradas + 1;
  end loop;

  return v_cerradas;
end;
$$;

-- ============================================================================
-- programación: cada 15 minutos
-- ============================================================================

create extension if not exists pg_cron;

select cron.schedule('auto-cierre-jornadas', '*/15 * * * *', $$select fn_auto_cierre()$$);
