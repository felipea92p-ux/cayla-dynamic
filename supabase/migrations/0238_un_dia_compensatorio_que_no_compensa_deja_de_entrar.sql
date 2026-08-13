-- ============================================================================
-- 0238_un_dia_compensatorio_que_no_compensa_deja_de_entrar.sql
-- ============================================================================
-- QUÉ PROMETE
--
--   1. Que no se pueda registrar como día compensatorio de un feriado un día en
--      que la persona ya iba a estar libre —o en que ya trabajó—, porque un día
--      así no compensa nada.
--   2. Que el motivo por el que un día NO compensa se diga UNA sola vez, y que
--      lo consulten tanto el candado que bloquea como la pantalla que explica.
--   3. Que un día compensatorio a más de 30 días del feriado se pueda registrar,
--      pero solo escribiendo por qué.
--
-- QUÉ ASUME
--   · La 0069 (tabla, trigger y RPC del descanso sustitutorio) y la 0093, que ya
--     le puso a esas RPC el candado de periodo pagado — mirando LAS DOS fechas,
--     porque el feriado y el día libre pueden caer en periodos distintos. Eso no
--     se toca y sigue vigente (comprobado contra la base antes de escribir esto).
--   · La 0101, que hizo de `ausencias` el único sitio donde vive una vacación.
--
-- POR QUÉ EXISTE
--
--   El descanso sustitutorio es la alternativa a pagar la sobretasa del 100 % de
--   un feriado trabajado: con el estado en OTORGADO, `fn_planilla_calcular` la
--   anula. Medido en un caso real de producción, el feriado de una persona baja
--   de S/206.83 a S/104.89.
--
--   O sea que marcar un día compensatorio vale unos cien soles. Si ese día no
--   compensa de verdad, la persona pierde la sobretasa Y no descansa: pierde por
--   los dos lados, y el papel dice que se le dio.
--
--   La 0069 ya defendía lo importante —que el feriado existiera y estuviera
--   laborado, la relación 1:1, el acta, y que el día libre no fuera su descanso
--   semanal—. Lo que faltaba era ALCANCE. Se podía poner el día compensatorio:
--
--     · sobre sus vacaciones o cualquier ausencia aprobada,
--     · sobre otro feriado,
--     · ANTES del feriado que dice compensar,
--     · y, la peor, sobre un día ya pasado en que esa persona TRABAJÓ.
--
-- LA IDEA QUE ORDENA ESTA MIGRACIÓN
--
--   El trigger de la 0069 preguntaba «¿ese día estaba PROGRAMADO como
--   laborable?» — una pregunta sobre el calendario. Para una fecha que ya pasó,
--   el sistema puede preguntar algo mucho mejor: «¿de verdad DESCANSÓ?». Y ya lo
--   sabe, porque tiene sus marcajes. Es la regla de la casa —los marcajes son la
--   fuente de verdad— aplicada a una comprobación que se conformaba con el
--   horario.
--
--   Y de ahí sale, gratis, lo que hacía falta para los días compensatorios
--   FUTUROS. Hoy se registra uno para dentro de un mes, se marca OTORGADO, se le
--   quita la sobretasa… y esa persona puede acabar trabajando ese día sin que
--   nadie se entere. Como el motivo se calcula AL LEER y no al escribir, cuando
--   ese día llega y hay horas marcadas, la fila empieza a decir «ese día
--   trabajó» ella sola. Sin cron, sin alertas nuevas, sin una segunda pieza que
--   mantener: la misma pregunta, hecha más tarde.
--
--   Por eso el motivo vive en `fn_dcs_por_que_no_compensa` y no repartido en el
--   trigger: si el candado y la pantalla tuvieran cada uno su copia de la regla,
--   el día que una cambie dirán cosas distintas sobre la misma fila.
--
-- QUÉ NO TOCA, Y ES IMPORTANTE
--   Ni una línea del cálculo. Ni el prorrateo del feriado, ni la base de 6.5, ni
--   a qué periodo pertenece un feriado que cae fuera del tramo. Esto valida QUÉ
--   DÍA se puede elegir; lo que se paga se sigue pagando igual.
--
-- CÓMO SE REVIERTE
--   Restaurar `fn_dcs_validar_dia_laborable` y `fn_feriados_laborados` desde la
--   0069 y la 0072, y soltar `fn_dcs_por_que_no_compensa` y la columna
--   `motivo_fuera_de_plazo`. Los registros ya escritos no se tocan.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final devuelve una fila con cuatro `true`.
-- ============================================================================

-- ── 1 · El motivo por escrito cuando se pasa de 30 días ────────────────────
-- No bloquea: avisa y obliga a decir por qué. Hay casos legítimos que un candado
-- duro rompería —estuvo con descanso médico, o de vacaciones justo después del
-- feriado— y un candado que cierra sobre un caso legítimo se acaba resolviendo
-- por fuera del sistema, que es donde no queda registro de nada.
alter table feriados_descanso_sustitutorio
  add column if not exists motivo_fuera_de_plazo text;

comment on column feriados_descanso_sustitutorio.motivo_fuera_de_plazo is
  'Por qué el día compensatorio cae a más de 30 días del feriado. Obligatorio en ese caso desde la 0238; null cuando está dentro del plazo.';


-- ── 2 · La pregunta, dicha una sola vez ────────────────────────────────────
-- Devuelve null si el día compensa de verdad, o la razón en castellano llano si
-- no. La escriben para que la lea una persona: sale tal cual en el error del
-- candado y en la pantalla de Feriados.
--
-- STABLE y no IMMUTABLE a propósito: la respuesta depende de lo que haya en la
-- base HOY. Es justo lo que la hace servir para el caso del día futuro.
create or replace function fn_dcs_por_que_no_compensa(
  p_persona_id     uuid,
  p_fecha_feriado  date,
  p_fecha_descanso date
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_dow      text;
  v_es_desc  boolean;
  v_hpd      jsonb;
  v_dias     int[];
begin
  if p_persona_id is null or p_fecha_feriado is null or p_fecha_descanso is null then
    return null;  -- nada que juzgar; los not-null de la tabla ya lo impiden
  end if;

  -- ── a · El orden en el tiempo ──────────────────────────────────────────
  -- No se descansa por adelantado algo que todavía no ocurrió. Y como la 0069
  -- exige que el feriado ya esté LABORADO para poder registrarlo, un día
  -- anterior es además un día que ya se gastó.
  if p_fecha_descanso <= p_fecha_feriado then
    return 'el día libre es anterior al feriado que dice compensar';
  end if;

  -- ── b · Otro feriado ───────────────────────────────────────────────────
  if exists (select 1 from feriados where fecha = p_fecha_descanso) then
    return 'ese día ya era feriado: no compensa nada';
  end if;

  -- ── c · Vacaciones o cualquier ausencia aprobada ───────────────────────
  -- Desde la 0101 las vacaciones son un tipo de ausencia, así que hay un solo
  -- sitio donde mirar. Las anuladas no cuentan: dejaron de existir.
  if exists (
    select 1 from ausencias a
    where a.persona_id = p_persona_id
      and a.anulada_at is null
      and a.aprobada_at is not null
      and p_fecha_descanso between a.fecha_inicio and a.fecha_fin
  ) then
    return 'ese día ya estaba libre por una ausencia aprobada';
  end if;

  -- ── d · Su descanso semanal ────────────────────────────────────────────
  -- Esta regla ya existía dentro del trigger de la 0069; se muda aquí para que
  -- la pantalla pueda explicarla con las mismas palabras con que se bloquea.
  v_dow := extract(dow from p_fecha_descanso)::int::text;  -- 0=domingo … 6=sábado

  select t.es_descanso into v_es_desc
  from turnos t
  where t.persona_id = p_persona_id and t.fecha = p_fecha_descanso;

  if found then
    if v_es_desc then
      return 'ese día ya era su descanso programado';
    end if;
  else
    select h.horario_por_dia, h.dias_laborables into v_hpd, v_dias
    from horarios_asignados h
    where h.persona_id = p_persona_id
      and h.vigente_desde <= p_fecha_descanso
      and (h.vigente_hasta is null or h.vigente_hasta >= p_fecha_descanso)
    order by h.vigente_desde desc
    limit 1;

    if not found then
      return 'no hay horario vigente esa fecha: no se puede saber si era día laborable';
    end if;

    -- Día AUSENTE del jsonb = descanso (convención de la 0016).
    if v_hpd is not null then
      if (v_hpd -> v_dow) is null then
        return 'ese día cae en su descanso semanal';
      end if;
    elsif v_dias is not null and not (v_dow::int = any(v_dias)) then
      return 'ese día cae en su descanso semanal';
    end if;
  end if;

  -- ── e · El hecho, no el programa ───────────────────────────────────────
  -- La comprobación que faltaba, y la única que mira lo que PASÓ en vez de lo
  -- que estaba previsto. Para una fecha futura no hay jornada y no dice nada;
  -- cuando esa fecha llega, empieza a hablar sola.
  if exists (
    select 1 from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha = p_fecha_descanso
      and coalesce(j.horas_trabajadas, 0) > 0
  ) then
    return 'ese día trabajó: no llegó a descansarlo';
  end if;

  return null;
end;
$$;

comment on function fn_dcs_por_que_no_compensa(uuid, date, date) is
  'Por qué un día NO compensa el feriado que dice compensar, en castellano llano, o null si compensa bien. La consultan el candado que bloquea y la pantalla que explica: una sola respuesta para las dos.';

grant execute on function fn_dcs_por_que_no_compensa(uuid, date, date) to authenticated;
revoke execute on function fn_dcs_por_que_no_compensa(uuid, date, date) from public, anon;


-- ── 3 · El candado, que ahora solo consulta ────────────────────────────────
-- Sustituye al cuerpo de la 0069. Mantiene el nombre y el trigger que ya lo
-- llama: lo que cambia es que la regla ya no vive aquí.
create or replace function fn_dcs_validar_dia_laborable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_motivo text;
begin
  v_motivo := fn_dcs_por_que_no_compensa(
    new.persona_id, new.fecha_feriado, new.fecha_descanso_sustitutorio);

  if v_motivo is not null then
    raise exception 'Ese día no compensa el feriado del %: %.',
      to_char(new.fecha_feriado, 'DD/MM/YYYY'), v_motivo;
  end if;

  -- El plazo AVISA, no bloquea: se puede pasar de 30 días escribiendo por qué.
  if new.fecha_descanso_sustitutorio > new.fecha_feriado + 30
     and coalesce(trim(new.motivo_fuera_de_plazo), '') = '' then
    raise exception 'El día libre cae a % días del feriado (más de 30): escribe por qué se compensa tan tarde.',
      (new.fecha_descanso_sustitutorio - new.fecha_feriado);
  end if;

  new.updated_at := now();
  return new;
end;
$$;


-- ── 4 · La pantalla recibe el motivo, no lo calcula ────────────────────────
-- `fn_feriados_laborados` devuelve TABLE, y a una función así no se le puede
-- agregar una columna con `create or replace`: hay que soltarla y crearla. Es el
-- mismo movimiento que hizo la 0161 con fn_documentos_tablero.
--
-- El cuerpo es el de la 0072 —la vigente— con dos columnas más al final. No se
-- toca ni una línea de su cálculo de sobretasa.
drop function if exists fn_feriados_laborados(date, date);

create function fn_feriados_laborados(p_desde date, p_hasta date)
returns table (
  persona_id uuid, nombre text, sede text,
  fecha_feriado date, feriado_nombre text, horas numeric, sobretasa numeric,
  dcs_id uuid, fecha_descanso date, estado text, acta_ref text,
  -- Nuevas (0238). `no_compensa_porque` es null cuando el día compensa bien.
  no_compensa_porque text,
  motivo_fuera_de_plazo text
)
language sql stable security definer set search_path = public
as $$
  with base as (
    select greatest(date_trunc('month', p_desde)::date, p_desde) as ini, p_hasta as fin
  ),
  -- La tarifa por hora sale de la misma base que usa la planilla: 6.5 h por día
  -- del periodo. Se calcula sobre el mes del feriado para que el número mostrado
  -- coincida con el que verá en Planilla.
  f as (
    select fe.fecha, fe.nombre,
           (6.5 * (extract(day from (date_trunc('month', fe.fecha) + interval '1 month - 1 day'))::numeric)) as base_horas
    from feriados fe, base b
    where fe.fecha between b.ini and b.fin
  )
  select
    pe.id, pe.nombres || ' ' || pe.apellidos, s.codigo,
    f.fecha, f.nombre,
    round(j.horas_trabajadas, 2),
    round(j.horas_trabajadas * a.salario_mensual_soles / nullif(f.base_horas, 0), 2),
    d.id, d.fecha_descanso_sustitutorio, d.estado, d.acta_ref,
    fn_dcs_por_que_no_compensa(pe.id, f.fecha, d.fecha_descanso_sustitutorio),
    d.motivo_fuera_de_plazo
  from f
  join jornadas j on j.fecha = f.fecha and coalesce(j.horas_trabajadas, 0) > 0
  join personas pe on pe.id = j.persona_id and pe.en_planilla = true and pe.sueldo_fijo = false
  join sedes s on s.id = pe.sede_base_id
  left join asignaciones_salario a
    on a.persona_id = pe.id and a.vigente_desde <= f.fecha
   and (a.vigente_hasta is null or a.vigente_hasta >= f.fecha)
  left join feriados_descanso_sustitutorio d
    on d.persona_id = pe.id and d.fecha_feriado = f.fecha
  where fn_es_admin_o_lider()
  order by f.fecha desc, s.codigo, pe.nombres;
$$;

grant execute on function fn_feriados_laborados(date, date) to authenticated;
revoke execute on function fn_feriados_laborados(date, date) from public, anon;


-- ── 5 · Y la RPC acepta el motivo del plazo ────────────────────────────────
-- Se añade un parámetro AL FINAL y con default: así ninguna llamada existente
-- se rompe. El resto del cuerpo es el de la 0093 —la vigente, con su candado de
-- periodo pagado— sin tocar.
--
-- ⚠ Y SE SUELTA LA DE CINCO PARÁMETROS PRIMERO. Un `create or replace` con un
-- parámetro de más NO reemplaza: crea una función NUEVA, y quedan las dos. Con
-- las dos vivas, una llamada de tres argumentos deja de resolverse —«function is
-- not unique»— y la pantalla entera deja de poder otorgar un descanso. Medido:
-- así fallaron siete de las diez comprobaciones de la prueba 179.
drop function if exists fn_otorgar_descanso_sustitutorio(uuid, date, date, text, text);

create or replace function fn_otorgar_descanso_sustitutorio(
  p_persona_id uuid,
  p_fecha_feriado date,
  p_fecha_descanso date,
  p_estado text default 'PENDIENTE',
  p_acta_ref text default null,
  p_motivo_fuera_de_plazo text default null
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

  -- El candado de la 0093, intacto: se miran LAS DOS fechas, porque el feriado y
  -- el día libre pueden caer en periodos distintos y basta con que uno esté
  -- cerrado para no tocar nada.
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha_feriado between fecha_ini and fecha_fin
  ) then
    raise exception 'El feriado del % cae en un periodo ya PAGADO: otorgar un descanso ahí cambiaría una planilla pagada. Reabre el periodo primero.',
      to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha_descanso between fecha_ini and fecha_fin
  ) then
    raise exception 'El día compensatorio del % cae en un periodo ya PAGADO: reabre el periodo primero.',
      to_char(p_fecha_descanso, 'DD/MM/YYYY');
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
    persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado, acta_ref,
    otorgado_por, motivo_fuera_de_plazo
  )
  values (
    p_persona_id, p_fecha_feriado, p_fecha_descanso, p_estado,
    nullif(trim(p_acta_ref), ''), fn_persona_actual_id(),
    nullif(trim(p_motivo_fuera_de_plazo), '')
  )
  on conflict (persona_id, fecha_feriado) do update set
    fecha_descanso_sustitutorio = excluded.fecha_descanso_sustitutorio,
    estado = excluded.estado,
    acta_ref = excluded.acta_ref,
    otorgado_por = excluded.otorgado_por,
    motivo_fuera_de_plazo = excluded.motivo_fuera_de_plazo,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function fn_otorgar_descanso_sustitutorio(uuid, date, date, text, text, text) to authenticated;
revoke execute on function fn_otorgar_descanso_sustitutorio(uuid, date, date, text, text, text) from public, anon;

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (238, 'un_dia_compensatorio_que_no_compensa_deja_de_entrar')
on conflict (numero) do nothing;


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Cuatro `true`. Y la última es la que de verdad importa: que los registros que
-- YA existen y no compensan se puedan ver — es lo que pintará la pantalla.
select
  (select count(*) from pg_proc where proname = 'fn_dcs_por_que_no_compensa') = 1
    as existe_la_pregunta,
  (select prosrc like '%fn_dcs_por_que_no_compensa%'
     from pg_proc where proname = 'fn_dcs_validar_dia_laborable')
    as el_candado_la_consulta,
  exists (select 1 from information_schema.columns
           where table_name = 'feriados_descanso_sustitutorio'
             and column_name = 'motivo_fuera_de_plazo')
    as existe_el_motivo_del_plazo,
  (select count(*) from feriados_descanso_sustitutorio d
    where fn_dcs_por_que_no_compensa(d.persona_id, d.fecha_feriado, d.fecha_descanso_sustitutorio) is not null)
    as registros_que_hoy_no_compensan;
