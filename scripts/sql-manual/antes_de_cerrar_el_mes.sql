-- ############################################################################
-- ####  ANTES DE CERRAR EL MES — SOLO LEE, NO ESCRIBE NADA                ####
-- ############################################################################
--
-- Para qué. Se corre ANTES de pulsar «Marcar como PAGADO». Dice, en una sola
-- tabla, qué va a salir mal si se cierra el periodo hoy: qué falta cargar, quién
-- va a cobrar de menos sin que nadie lo note, y qué puede impedir que el cierre
-- se complete.
--
-- Salió de la auditoría del 2026-08-14 (13 agentes, 53 hallazgos, 45
-- reproducidos con cifras). Cada chequeo de aquí abajo corresponde a uno que se
-- midió y costó dinero real en el laboratorio.
--
-- ── POR QUÉ NO LLAMA A NINGUNA FUNCIÓN DE DIAGNÓSTICO ───────────────────────
--
-- Porque mienten en el SQL Editor. `fn_liquidaciones_pendientes`,
-- `fn_contratos_desnaturalizados`, `fn_dias_por_revisar`, `fn_ausencias_subsidio`
-- y `fn_contratos_por_vencer` llevan dentro `fn_es_admin_o_lider()`, y en el
-- Editor la sesión es `postgres`, que no tiene fila en `personas`. El guard da
-- false y devuelven CERO FILAS — no un error. **Cero filas se lee exactamente
-- igual que «no hay nada pendiente».**
--
-- Este archivo va contra las TABLAS, así que no puede caer en eso.
--
-- ── ES UNA SOLA CONSULTA, Y ESO IMPORTA ─────────────────────────────────────
-- El SQL Editor de Supabase muestra únicamente el resultado del ÚLTIMO select.
-- Partido en varios, dos tercios del diagnóstico se ejecutan y no los ve nadie.
--
-- ── CÓMO SE LEE ─────────────────────────────────────────────────────────────
--   🚫 = impide cerrar el periodo · 💸 = plata mal pagada · ⚠ = revisar
--   ✓  = comprobado y está bien
-- ############################################################################

with per as (
  -- El periodo que se está por pagar: el que contiene el día de hoy en Lima.
  -- Si no existe ninguno, todo lo demás sale vacío y el primer chequeo lo grita.
  select id, fecha_ini, fecha_fin, estado
  from periodos_planilla
  where (now() at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  order by fecha_ini desc
  limit 1
),
d as (select coalesce((select fecha_ini from per), date '1900-01-01') as ini,
             coalesce((select fecha_fin from per), date '1900-01-01') as fin),

-- ── 1 · ¿Existe el periodo? ─────────────────────────────────────────────────
c1 as (
  select 1 as orden, 'EL PERIODO' as chequeo,
         case when exists (select 1 from per) then '✓  existe' else '🚫 NO EXISTE' end as resultado,
         coalesce((select fecha_ini::text || ' → ' || fecha_fin::text || '  (' || estado || ')' from per),
                  'Nadie lo crea solo: no hay cron, solo fn_crear_periodo a mano. Sin él no hay cierre, ni foto, ni movimientos.') as detalle
),

-- ── 2 · Los feriados del periodo ────────────────────────────────────────────
-- Un feriado que falte EN MEDIO del calendario es invisible: la cobertura solo
-- mira max(fecha). Medido: cuesta ~S/97 por persona, ~S/2,529 por el equipo.
c2 as (
  select 2, 'FERIADOS CARGADOS',
         case when count(*) = 0 then '⚠  ninguno en el periodo' else '✓  ' || count(*)::text || ' cargado(s)' end,
         coalesce(string_agg(f.fecha::text || ' ' || f.nombre, ' · ' order by f.fecha),
                  'Si de verdad no hay ninguno, bien. Si falta uno, el día no existe para el sistema: no da error, la planilla sale más baja y cuadra consigo misma.')
  from feriados f, d where f.fecha between d.ini and d.fin
),

-- ── 3 · Jornadas que van a pagar CERO sin avisar ────────────────────────────
-- `abierta` y `en_pausa` pagan S/0.00 ese día y NO entran en el contador de
-- «días pendientes», que solo cuenta las auto_cerrada_pendiente. Es el único
-- estado que se lleva plata en silencio. Medido: ~S/51 por día y persona.
--
-- ⚠️ EL DÍA DE HOY NO CUENTA, y eso es el 2026-08-14 aprendido a la mala. Este
-- chequeo contaba TODO el periodo, hoy incluido, y devolvió «💸 14 día(s) que
-- pagarán CERO» a las tres de la tarde de un jueves: eran trece personas EN SU
-- PUESTO, con su jornada abierta porque todavía no habían salido. Se comprobó
-- de la forma más elocuente posible — al volver a correrlo un rato después el
-- número había bajado a 10 solo, mientras la gente se iba a casa.
--
-- Un aviso que grita 💸 por gente trabajando enseña a ignorarlo, y el día que
-- cuente uno de verdad ya nadie lo va a leer. Esa es la regla de CLAUDE.md: los
-- falsos positivos son el peor error, y las exclusiones se aplican ANTES de
-- contar, no después.
c4 as (
  select 4, 'JORNADAS MUDAS (abierta / en_pausa)',
         case when count(*) = 0 then '✓  ninguna de días pasados'
              else '💸 ' || count(*)::text || ' día(s) que pagarán CERO y no avisan' end,
         coalesce(string_agg(distinct p.nombres || ' ' || p.apellidos, ' · '),
                  'Los días ya cerrados están todos con su salida. El día en curso va en la línea de abajo.')
  from jornadas j join personas p on p.id = j.persona_id, d
  where j.fecha between d.ini and d.fin and j.estado in ('abierta','en_pausa')
    and j.fecha < (now() at time zone 'America/Lima')::date
),

-- ── 3b · El día en curso, que NO es un problema… hasta el día que cierras ────
-- Va aparte y sin 💸 a propósito: mientras el periodo siga abierto, una jornada
-- de hoy sin salida es alguien trabajando. Pero el 28, al congelar, deja de
-- serlo — quien no haya marcado su salida en ese momento pierde el día, y ya no
-- se arregla solo. Por eso se informa siempre y se avisa solo cuando toca.
c4b as (
  select 5, 'EL DÍA EN CURSO (informativo)',
         case when count(*) = 0 then '✓  nadie con el día abierto'
              when (now() at time zone 'America/Lima')::date = (select fin from d)
                then '⚠  ' || count(*)::text || ' persona(s) SIN SALIDA — hoy se congela: pierden el día'
              else 'ℹ  ' || count(*)::text || ' persona(s) con el día en curso' end,
         coalesce(string_agg(distinct p.nombres || ' ' || p.apellidos, ' · '),
                  'Nadie tiene el día de hoy abierto.')
  from jornadas j join personas p on p.id = j.persona_id, d
  where j.fecha = (now() at time zone 'America/Lima')::date
    and j.fecha between d.ini and d.fin
    and j.estado in ('abierta','en_pausa')
),
c5 as (
  select 6, 'JORNADAS AUTO-CERRADAS SIN CONFIRMAR',
         -- CAMBIO 0284 — Pasó de ⚠ a 🚫. Antes solo avisaba de que esas horas se
         -- pagaban con la hora que inventó el cron; desde la 0284
         -- `fn_planilla_congelar` se niega a cerrar el periodo mientras quede
         -- alguna. Dejarlo en ⚠ diría que el cierre puede continuar, y no puede.
         case when count(*) = 0 then '✓  ninguna'
              else '🚫 ' || count(*)::text || ' por revisar — el cierre ABORTARÁ (freno 0284)' end,
         'Confírmalas en Correcciones: esa hora la puso el cron y nadie la marcó. Hasta entonces el periodo no cierra.'
  from jornadas j, d
  where j.fecha between d.ini and d.fin and j.estado = 'auto_cerrada_pendiente'
),

-- ── 6 · Lo que puede ATASCAR el cierre ──────────────────────────────────────
-- El total no aplicaba `cobra_movilidad`: pagaba una movilidad que la boleta
-- imprime en S/0.00. Ese descuadre hacía que chk_foto_cuadra rechazara la fila
-- — y como fn_planilla_congelar inserta las ~30 en una sola sentencia, NO SE
-- CONGELABA NINGUNA. Mismo mecanismo que la retención de 4ta de la 0248.
--
-- Lo arregló la 0252, y por eso este chequeo MIDE EL DEFECTO Y NO SU PROXY.
-- Antes se disparaba con solo existir alguien con `cobra_movilidad = false`;
-- con la 0252 puesta esa persona sigue existiendo y ya no hay ningún riesgo, así
-- que el 🚫 habría quedado encendido para siempre. Un semáforo que no se apaga
-- nunca no es un semáforo. Ahora se pregunta a la función: el filtro tiene que
-- aparecer DOS veces —en el concepto `monto_movilidad` y en el término del
-- `total`—, y solo si aparece una vez hay alguien en riesgo de verdad.
c6 as (
  select 7, 'MOVILIDAD EXCLUIDA CON TARIFA VIVA',
         case when count(*) = 0 then '✓  nadie en riesgo'
              when (select (length(prosrc) - length(replace(prosrc, 'pe.cobra_movilidad', '')))
                           / length('pe.cobra_movilidad')
                      from pg_proc pr join pg_namespace ns on ns.oid = pr.pronamespace
                     where ns.nspname = 'public' and pr.proname = 'fn_planilla_calcular') >= 2
                then '✓  ' || count(*)::text || ' persona(s), y la 0252 ya las cubre'
              else '🚫 ' || count(*)::text || ' persona(s) — FALTA LA 0252: el cierre aborta PARA TODOS' end,
         coalesce(string_agg(p.nombres || ' ' || p.apellidos || coalesce(' (' || p.movilidad_motivo || ')', ''), ' · '),
                  'Nadie tiene cobra_movilidad = false con días marcados.')
  from personas p, d
  where p.estado = 'activo' and p.cobra_movilidad is false
    and exists (select 1 from jornadas j where j.persona_id = p.id
                  and j.fecha between d.ini and d.fin and j.horas_trabajadas > 0)
),

-- ── 7 · Retenciones que no se están haciendo ────────────────────────────────
-- Sin régimen de pensión cargado el descuento sale S/0.00 y ninguna pantalla lo
-- dice. Medido: ~S/256/mes por persona. CAYLA es agente de retención: lo que no
-- se retiene lo termina pagando la empresa. Es lo que pasó en julio con 23.
c7 as (
  select 8, 'SIN RÉGIMEN DE PENSIÓN',
         case when count(*) = 0 then '✓  todos lo tienen'
              else '💸 ' || count(*)::text || ' persona(s) sin retención previsional' end,
         coalesce(string_agg(p.nombres || ' ' || p.apellidos, ' · '),
                  'Nadie en planilla se queda sin descuento por falta de régimen.')
  from personas p
  where p.estado = 'activo' and p.en_planilla is true and p.regimen_pension is null
),

-- ── 8 · Ausencias que se van a pagar en CERO ────────────────────────────────
-- fn_planilla_calcular NO lee la tabla `ausencias`: solo `vacaciones`. Un
-- descanso médico, una maternidad o una licencia con goce pagan S/0.00 mientras
-- la pantalla dice cuatro veces «se paga» y las provisiones sí los devengan.
-- El RIT art. 31 f) obliga a CAYLA a asumir los primeros 20 días.
-- ⚠️ SOLO LOS TIPOS QUE EL CATÁLOGO DICE QUE PAGAN, y esto se aprendió caro.
-- La primera versión marcaba TODAS las ausencias del periodo y daba diez falsas
-- alarmas de golpe: cuatro permisos personales, dos descansos por salud sin
-- documento y un «otro» son tipos con `paga = false`, así que S/0.00 es su
-- resultado CORRECTO. Un chequeo que grita por lo normal se desactiva a la
-- semana, y con él se pierde el grito que sí importa.
--
-- Los que pagan son cuatro: descanso_medico, licencia_con_goce, maternidad y
-- vacaciones. Y de esos se descuenta a quien no devenga —un locador no cobra
-- vacaciones desde la 0186— para no volver a inventar una alarma.
c8 as (
  select 9, 'AUSENCIAS QUE PAGARÁN CERO',
         case when count(*) = 0 then '✓  ninguna en el periodo'
              else '💸 ' || count(*)::text || ' ausencia(s) QUE DEBERÍAN PAGARSE y saldrán S/0.00' end,
         coalesce(string_agg(p.nombres || ' ' || p.apellidos || ' · ' || a.tipo
                             || ' ' || a.fecha_inicio::text || '→' || a.fecha_fin::text, ' · '),
                  'Ninguna ausencia de tipo pagable en el periodo. Los permisos personales, el duelo y la salud sin documento NO pagan: S/0.00 es su resultado correcto.')
  from ausencias a
  join personas p on p.id = a.persona_id
  join tipos_ausencia t on t.codigo = a.tipo and t.paga is true, d
  where a.anulada_at is null and a.fecha_inicio <= d.fin and a.fecha_fin >= d.ini
    and p.en_planilla is true
),

-- ── 9 · Quién entró o cesó dentro del periodo ───────────────────────────────
-- Es el caso que más errores produce: prorrateos, truncas, y el sueldo fijo que
-- cobra el mes entero por un solo día (medido: hasta S/915 de más).
c9 as (
  select 10, 'ENTRADAS Y CESES EN EL PERIODO',
         case when count(*) = 0 then '✓  ninguno' else '⚠  ' || count(*)::text || ' movimiento(s)' end,
         coalesce(string_agg(p.nombres || ' ' || p.apellidos
                   || case when p.fecha_ingreso between d.ini and d.fin then ' (entró ' || p.fecha_ingreso::text || ')' else '' end
                   || case when p.fecha_cese between d.ini and d.fin then ' (cesó ' || p.fecha_cese::text || ')' else '' end
                   || case when p.sueldo_fijo then '  ⚠ SUELDO FIJO: cobra el mes completo, no prorratea' else '' end, ' · '),
                  'Nadie entró ni cesó dentro del periodo.')
  from personas p, d
  where p.fecha_ingreso between d.ini and d.fin or p.fecha_cese between d.ini and d.fin
),

-- ── 10 · Activos sin salario o sin horario vigente ──────────────────────────
-- Sin tramo de salario que cubra el periodo se cobra S/0.00. Los RxH sin horario
-- es correcto y deliberado desde la 0191 — por eso se separan.
c10 as (
  select 11, 'ACTIVOS SIN SALARIO VIGENTE',
         case when count(*) = 0 then '✓  todos tienen'
              else '💸 ' || count(*)::text || ' persona(s) cobrarán CERO' end,
         coalesce(string_agg(p.nombres || ' ' || p.apellidos, ' · '), 'Todo el mundo tiene su tramo abierto.')
  from personas p, d
  where p.estado = 'activo'
    and not exists (select 1 from asignaciones_salario a
                     where a.persona_id = p.id and a.vigente_desde <= d.fin
                       and (a.vigente_hasta is null or a.vigente_hasta >= d.ini))
),
c11 as (
  select 12, 'EN PLANILLA SIN HORARIO VIGENTE',
         case when count(*) = 0 then '✓  todos tienen'
              else '⚠  ' || count(*)::text || ' sin horario (no se les mide falta ni tardanza)' end,
         coalesce(string_agg(p.nombres || ' ' || p.apellidos, ' · '), 'Todos los de planilla tienen horario.')
  from personas p, d
  where p.estado = 'activo' and p.en_planilla is true
    and not exists (select 1 from horarios_asignados h
                     where h.persona_id = p.id and h.vigente_desde <= d.fin
                       and (h.vigente_hasta is null or h.vigente_hasta >= d.ini))
),

-- ── 12 · Vacaciones que se solapan con marcaje ──────────────────────────────
-- Un día de vacaciones en el que la persona ADEMÁS marca se paga dos veces.
-- Medido: hasta S/915 de más en un mes.
c12 as (
  select 13, 'VACACIONES CON MARCAJE ENCIMA',
         case when count(*) = 0 then '✓  ninguna'
              else '💸 ' || count(*)::text || ' día(s) que se pagarán DOS veces' end,
         coalesce(string_agg(distinct p.nombres || ' ' || p.apellidos, ' · '),
                  'Nadie marcó durante sus vacaciones.')
  from vacaciones v join personas p on p.id = v.persona_id
  join jornadas j on j.persona_id = v.persona_id
       and j.fecha between v.fecha_inicio and v.fecha_fin and j.horas_trabajadas > 0, d
  where v.fecha_inicio <= d.fin and v.fecha_fin >= d.ini
    and j.fecha between d.ini and d.fin
)

select chequeo, resultado, detalle
from (
  select * from c1  union all select * from c2  union all select * from c4
  union all select * from c4b
  union all select * from c5  union all select * from c6  union all select * from c7
  union all select * from c8  union all select * from c9  union all select * from c10
  union all select * from c11 union all select * from c12
) t
order by orden;
