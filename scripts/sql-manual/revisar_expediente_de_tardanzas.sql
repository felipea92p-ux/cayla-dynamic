-- ============================================================================
-- revisar_expediente_de_tardanzas.sql
-- ============================================================================
-- QUÉ RESPONDE
--   Si el expediente de tardanzas de una persona se sostiene, día por día.
--   Antes de imputar cargos —y mucho antes de una desvinculación— hay que poder
--   defender CADA hecho citado. Esta consulta busca los que no se defienden.
--
-- QUÉ NO HACE
--   No escribe nada. Solo lee. Se pega tal cual en el SQL Editor de Supabase.
--
-- ── QUÉ BUSCA, Y POR QUÉ CADA COSA ──────────────────────────────────────────
--
--   ⚠ FERIADO          Hallazgo abierto nº4: fn_recalcular_jornada no conoce
--                      los feriados y mide la tardanza contra la hora normal de
--                      entrada. Quien vino voluntariamente un feriado —y cobró
--                      la sobretasa— acumula tardanzas por llegar tarde a un día
--                      en el que no tenía obligación de venir. Un hecho así no
--                      sostiene nada.
--   ⚠ VACACIONES       Mismo defecto, misma consecuencia.
--   ⚠ SIN MEDIR        Más de tres horas: casi siempre el turno cargado era
--                      otro. No se sanciona sobre una medición dudosa (0189).
--   ⚠ PERDONADA        Tardanza levantada. No cuenta para el patrón (0053), y
--                      si aparece citada en un memo firmado, ese memo está mal.
--   ⚠ TRABAJÓ          En un día declarado de suspensión. Si la persona marcó y
--                      trabajó, la suspensión NO se cumplió ese día: el memo
--                      declara un castigo que no ocurrió. Es el caso real del
--                      25/07/2026 —tres días declarados, uno cumplido— que
--                      documenta la migración 0075.
--
-- ── CÓMO SE USA ─────────────────────────────────────────────────────────────
--   Cambia el patrón de la primera línea. Va con % a los lados y no distingue
--   mayúsculas. Sin datos personales dentro: el nombre lo pones al pegar.
-- ============================================================================

with quien as (
  select '%mateo%'::text as patron          -- ⇦ CAMBIA ESTO
),
persona as (
  select pe.id, pe.nombres || ' ' || pe.apellidos as nombre,
         pe.estado, pe.en_planilla, pe.sueldo_fijo, pe.tipo_vinculo,
         coalesce(s.codigo, '—') as sede
  from personas pe
  left join sedes s on s.id = pe.sede_base_id
  cross join quien q
  where lower(pe.nombres || ' ' || pe.apellidos) like lower(q.patron)
),

-- ── A · Los memos, y si la suspensión se cumplió de verdad ──────────────────
memos as (
  select e.id, e.correlativo, e.nivel, e.estado, e.periodo_desde, e.periodo_hasta,
         e.suspension_dias, e.suspension_desde, e.suspension_hasta,
         -- ⚠ `suspension_fechas` la añade la 0075, y si esa migración NO está
         -- pegada la columna no existe: nombrarla derecho mata la consulta
         -- entera con «column does not exist». Justo esta consulta es la que se
         -- corre para AVERIGUAR si la 0075 está, así que no puede depender de
         -- que lo esté. `to_jsonb(e.*)` devuelve las columnas que haya: si la
         -- clave falta, sale null y el bloque cae al rango de calendario, que es
         -- exactamente lo que hay que auditar en ese caso.
         (select array_agg(v::date order by v::date)
            from jsonb_array_elements_text(
              case when jsonb_typeof(to_jsonb(e.*) -> 'suspension_fechas') = 'array'
                   then to_jsonb(e.*) -> 'suspension_fechas'
                   else '[]'::jsonb end) v) as suspension_fechas,
         e.hechos, e.firmado_at, e.entregado_at, p.id as pid, p.nombre
  from expediente_disciplinario e
  join persona p on p.id = e.persona_id
  where e.tipo_causal = 'tardanza' and e.estado in ('firmado', 'entregado')
),
-- Los días que el memo declaró suspendidos: las fechas exactas si la 0075 está
-- aplicada, y si no, el rango de calendario — que es justo lo que puede estar mal.
dias_declarados as (
  select m.id, m.correlativo, m.pid, d::date as fecha
  from memos m
  cross join lateral unnest(
    coalesce(m.suspension_fechas,
             case when m.suspension_desde is not null and m.suspension_hasta is not null
                  then (select array_agg(g::date)
                          from generate_series(m.suspension_desde, m.suspension_hasta, interval '1 day') g)
             end,
             '{}'::date[])) d
  where m.nivel = 'suspension'
),
suspension as (
  select dd.correlativo, dd.fecha,
         coalesce(j.horas_trabajadas, 0) as horas_ese_dia
  from dias_declarados dd
  left join jornadas j on j.persona_id = dd.pid and j.fecha = dd.fecha
),

-- ── B · Cada hecho citado en cada memo, anotado ─────────────────────────────
hechos as (
  select m.correlativo, m.nivel, m.pid,
         (h ->> 'fecha')::date as fecha,
         (h ->> 'minutos')::int as minutos
  from memos m
  cross join lateral jsonb_array_elements(m.hechos) h
  where jsonb_typeof(m.hechos) = 'array'
),

-- ── C · Lo del mes en curso, todavía sin sancionar ─────────────────────────
mes_actual as (
  select p.id as pid, j.fecha, j.minutos_tarde as minutos
  from persona p
  join jornadas j on j.persona_id = p.id
  where j.fecha >= date_trunc('month', (now() at time zone 'America/Lima')::date)::date
    and j.fecha <= (now() at time zone 'America/Lima')::date
    and j.minutos_tarde is not null and j.minutos_tarde > 0
),

-- La anotación, en un solo sitio para que los dos bloques la digan igual.
anotado as (
  select 'hecho citado' as bloque, h.correlativo as doc, h.fecha, h.minutos, h.pid
  from hechos h
  union all
  select 'mes en curso', '—', m.fecha, m.minutos, m.pid
  from mes_actual m
)

select * from (
  -- ── ¿está la 0075 en esta base? ──
  -- Va incluido acá para no tener que pegar una consulta aparte: de esto
  -- depende que las fechas de una suspensión sean días laborables o días de
  -- calendario, y el encabezado de la 0075 y docs/hallazgos-abiertos.md se
  -- contradicen sobre si llegó a producción.
  select 0 as orden, 'MIGRACIÓN 0075' as bloque,
         'suspensión en días laborables' as doc, null::date as fecha, null::int as minutos,
         format('columna suspension_fechas: %s · fn_expediente_set_suspension: %s · fn_dias_suspension: %s',
           case when exists (select 1 from information_schema.columns
                              where table_schema = 'public'
                                and table_name = 'expediente_disciplinario'
                                and column_name = 'suspension_fechas') then 'SÍ' else '⚠ NO' end,
           case when exists (select 1 from pg_proc pr join pg_namespace ns on ns.oid = pr.pronamespace
                              where ns.nspname = 'public'
                                and pr.proname = 'fn_expediente_set_suspension') then 'SÍ' else '⚠ NO' end,
           case when exists (select 1 from pg_proc pr join pg_namespace ns on ns.oid = pr.pronamespace
                              where ns.nspname = 'public'
                                and pr.proname = 'fn_dias_suspension') then 'SÍ' else '⚠ NO' end) as nota

  union all
  -- ── quién es, y si el semáforo puede verlo siquiera ──
  select 1, 'QUIÉN', p.nombre, null::date, null::int,
         format('%s · %s · vínculo %s · en_planilla %s · sueldo_fijo %s',
                p.sede, p.estado, p.tipo_vinculo, p.en_planilla, p.sueldo_fijo)
  from persona p

  union all
  -- ── los memos ya firmados ──
  -- `minutos` va en null a propósito: poner ahí los días de suspensión bajo una
  -- columna que se llama «minutos» se lee como una tardanza de 3 minutos.
  select 2, 'MEMO', coalesce(m.correlativo, '(sin número)'),
         (m.firmado_at at time zone 'America/Lima')::date, null::int,
         format('%s · %s · hechos del %s al %s%s',
                m.nivel, m.estado, m.periodo_desde, m.periodo_hasta,
                case when m.nivel <> 'suspension' then ''
                     when m.suspension_fechas is not null
                       then format(' · %s día(s), fechas exactas: %s',
                                   m.suspension_dias, array_to_string(m.suspension_fechas, ', '))
                     -- Sin fechas exactas hay DOS causas distintas y no da igual
                     -- cuál sea: o la 0075 no está en esta base (mírala en la
                     -- fila 0), o este memo se emitió antes de que la pantalla
                     -- la usara. En los dos casos los días se fijaron por
                     -- CALENDARIO y el bloque de abajo dice si se cumplieron.
                     else format(' · ⚠ %s día(s) por CALENDARIO (%s a %s), sin fechas exactas',
                                 m.suspension_dias, m.suspension_desde, m.suspension_hasta)
                end)
  from memos m

  union all
  -- ── ¿se cumplió la suspensión? ──
  select 3, 'DÍA DE SUSPENSIÓN', s.correlativo, s.fecha, null,
         case when s.horas_ese_dia > 0
              then format('⚠ TRABAJÓ %s h ese día — la suspensión no se cumplió', s.horas_ese_dia)
              else 'sin marcas: la suspensión se cumplió' end
  from suspension s

  union all
  -- ── cada hecho, con lo que lo puede tumbar ──
  select 4, a.bloque, a.doc, a.fecha, a.minutos,
         nullif(concat_ws(' · ',
           case when exists (select 1 from feriados f where f.fecha = a.fecha)
                then '⚠ FERIADO' end,
           case when exists (select 1 from vacaciones v
                              where v.persona_id = a.pid
                                and a.fecha between v.fecha_inicio and v.fecha_fin)
                then '⚠ VACACIONES' end,
           case when exists (select 1 from tardanzas_justificadas tj
                              where tj.persona_id = a.pid and tj.fecha = a.fecha)
                then '⚠ PERDONADA' end,
           case when a.minutos > 180 then '⚠ SIN MEDIR (más de 3 h)' end,
           case when exists (select 1 from feriados_descanso_sustitutorio d
                              where d.persona_id = a.pid and d.fecha_feriado = a.fecha)
                then '⚠ DESCANSO SUSTITUTORIO' end
         ), '')
  from anotado a
) t
order by orden, fecha nulls first, doc;
