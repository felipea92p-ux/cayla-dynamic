-- ============================================================================
-- el_cuerpo_de_la_0189_contra_los_datos.sql
-- ============================================================================
-- QUÉ RESPONDE
--   Si el cuerpo REAL de fn_tardanzas_resumen —copiado literal de la 0189, que
--   es la versión que md5 confirmó viva en producción— devuelve o no a la
--   persona cuando se corre contra los datos de producción.
--
--   Es la bifurcación que separa dos mundos:
--     · SI devuelve la fila  → el cuerpo está bien y lo que falla es la PUERTA
--                              (permiso de ejecución, gate de rol) o el
--                              transporte (PostgREST). Se mira la parte de abajo.
--     · SI no la devuelve    → el cuerpo no cuadra con los datos, y las tres
--                              columnas de diagnóstico dicen en qué paso se cae.
--
-- QUÉ NO HACE
--   No escribe nada. Solo lee.
--
-- ── QUÉ SE CAMBIÓ RESPECTO AL ORIGINAL, Y NADA MÁS ──────────────────────────
--   La cláusula de permisos
--       and (fn_es_admin_o_lider() or (fn_rol_actual() = 'supervisor_sede' ...))
--   se sustituye por `true`. En el SQL Editor no hay sesión de usuario, así que
--   esa cláusula sería falsa siempre y la consulta devolvería cero filas sin
--   que eso significara nada. Todo lo demás va literal: el mismo corte, el
--   mismo fn_hoy_lima(), el mismo fn_tardanza_es_medible.
--
-- ── POR QUÉ ESTA CONSULTA Y NO OTRA HIPÓTESIS MÁS ───────────────────────────
--   Ya se descartaron por medición: versión vieja de la función (md5 idéntico
--   al de la 0189), sobrecarga ambigua (sobrecargas = 1) y falta de permiso de
--   lectura (los Entregados muestran dos sedes, que solo pasa siendo admin).
--   CLAUDE.md dice medir dónde está la diferencia en vez de proponer
--   explicaciones; esto la mide.
-- ============================================================================

with medibles as (
  select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
    (select e.periodo_hasta
     from expediente_disciplinario e
     where e.persona_id = pe.id and e.tipo_causal = 'tardanza'
       and e.estado in ('firmado', 'entregado')
       and e.firmado_at >= now() - interval '12 months'
     order by e.firmado_at desc
     limit 1) as corte
  from personas pe join sedes s on s.id = pe.sede_base_id
  where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
    and true   -- ⇦ ÚNICO cambio: aquí iba la cláusula de permisos
),
conteo as (
  select m.id as pid,
         count(distinct j.fecha) filter (
           where fn_tardanza_es_medible(j.minutos_tarde)) as n,
         count(distinct j.fecha) filter (
           where not fn_tardanza_es_medible(j.minutos_tarde)) as sm,
         max(j.fecha) filter (
           where fn_tardanza_es_medible(j.minutos_tarde)) as ult
  from medibles m
  join jornadas j on j.persona_id = m.id
    and j.fecha >= date_trunc('month', fn_hoy_lima())::date
    and j.fecha <= fn_hoy_lima()
    and (m.corte is null or j.fecha > m.corte)
    and j.minutos_tarde is not null and j.minutos_tarde > 0
    and not exists (
      select 1 from tardanzas_justificadas tj
      where tj.persona_id = m.id and tj.fecha = j.fecha)
  group by m.id
)
select
  m.nombre,
  m.sede,
  c.n::int              as tardanzas_mes,
  case when c.n >= 3 then 'amonestacion' else 'aviso' end as umbral,
  c.ult                 as ultima_fecha,
  c.sm::int             as sin_medir,
  -- ── diagnóstico: los tres valores de los que depende el conteo ──
  m.corte               as corte_aplicado,
  fn_hoy_lima()         as hoy_segun_la_base,
  date_trunc('month', fn_hoy_lima())::date as desde_que_dia_cuenta
from medibles m join conteo c on c.pid = m.id
where c.n >= 2 or c.sm > 0
order by c.n desc, c.sm desc, m.nombre;
