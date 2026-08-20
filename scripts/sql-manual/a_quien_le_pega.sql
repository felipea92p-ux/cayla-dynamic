-- ############################################################################
-- ####  ¿A QUIÉN DE CAYLA LE PEGA?  — SOLO LEE, NO ESCRIBE NADA           ####
-- ############################################################################
--
-- Nace de la auditoría del 2026-08-19: 22 agentes contra la ley peruana, 93
-- hallazgos. La mitad se cayeron al preguntar lo único que importa —¿le pasa a
-- alguien?— y esta consulta es esa pregunta hecha a producción de una vez.
--
-- LA REGLA QUE LA JUSTIFICA: un hallazgo de laboratorio no es un hallazgo hasta
-- que se sabe qué persona real cae en él. El 2026-08-18 cinco «hallazgos» se
-- deshicieron al medirlos contra producción, y cada uno costó tiempo del cierre.
--
-- SE CORRE ANTES DEL 28. Cada fila que devuelva con veredicto distinto de «✓»
-- es plata o papel de este periodo. Las que salgan «✓» quedan como riesgo
-- latente anotado, no como trabajo pendiente.
--
-- ES UN SOLO SELECT A PROPÓSITO. El SQL Editor de Supabase ejecuta únicamente
-- la última sentencia: partirla en bloques perdería todos menos el último, en
-- silencio.
--
-- LA SESIÓN DE ADMIN VA DENTRO, por lo mismo que en `va_a_poder_cerrarse.sql`.
-- ############################################################################

with sesion as (
  select set_config('request.jwt.claim.sub',
           (select auth_user_id::text from personas
             where rol = 'admin' and auth_user_id is not null
             order by (nombres ilike '%Felipe%') desc limit 1), true) as jwt
),
per as (
  select p.id, p.fecha_ini, p.fecha_fin
  from periodos_planilla p, sesion
  where (now() at time zone 'America/Lima')::date between p.fecha_ini and p.fecha_fin
  order by p.fecha_ini desc limit 1
),
gente as (
  select p.*, s.codigo as sede, p.apellidos || ', ' || p.nombres as quien
  from personas p left join sedes s on s.id = p.sede_base_id
  where p.estado = 'activo' or (p.fecha_cese is not null
        and p.fecha_cese between (select fecha_ini from per) and (select fecha_fin from per))
),
-- días con marca dentro del periodo, por persona
marcas as (
  select j.persona_id, count(*) filter (where coalesce(j.horas_trabajadas,0) > 0) as dias_marcados
  from jornadas j, per
  where j.fecha between per.fecha_ini and per.fecha_fin
  group by j.persona_id
),
-- Días de vacaciones dentro del periodo, contados COMO LOS CUENTA EL PAGO.
-- El lateral `vacd` de `fn_planilla_calcular` solo cuenta el día si además le
-- tocaba trabajar (horario_por_dia si existe, dias_laborables si no), y hace un
-- JOIN INTERNO contra `horarios_asignados`: sin fila de horario el día no
-- existe para el pago. Contar días de calendario aquí daría falsos positivos,
-- que es el error que este sistema no puede permitirse.
vac_dias as (
  select v.persona_id,
         d.d::date as dia,
         (hv.persona_id is not null) as tiene_horario,
         case when hv.persona_id is null then false
              when hv.horario_por_dia is not null
                then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
              else extract(dow from d.d)::int = any(hv.dias_laborables)
         end as le_tocaba
  from vacaciones v
  cross join per
  cross join lateral generate_series(greatest(v.fecha_inicio, per.fecha_ini),
                                     least(v.fecha_fin,  per.fecha_fin), interval '1 day') d
  left join lateral (
    select ha.persona_id, ha.dias_laborables, ha.horario_por_dia
    from horarios_asignados ha
    where ha.persona_id = v.persona_id and ha.vigente_desde <= d.d::date
    order by ha.vigente_desde desc limit 1
  ) hv on true
),
vac as (
  select persona_id,
         count(*) filter (where le_tocaba)                as dias_vac,
         count(*) filter (where not tiene_horario)        as dias_sin_horario
  from vac_dias group by persona_id
),

-- 1 · VACACIONES QUE PAGARÍAN S/0.00  (0/0 en el promedio del día)
c1 as (
  select 1 as orden, 'Vacaciones que pagarían S/0.00 (0/0)' as chequeo,
    coalesce(string_agg(g.quien || ' (' || v.dias_vac || ' días, 0 marcas)', ' · '), '') as quienes
  from vac v join gente g on g.id = v.persona_id
  left join marcas m on m.persona_id = v.persona_id
  where g.en_planilla is true and g.sueldo_fijo is not true
    and coalesce(m.dias_marcados, 0) = 0
    and v.dias_vac > 0
),
-- 2 · VACACIONES SIN HORARIO VIGENTE  (el JOIN interno las deja en S/0)
c2 as (
  select 2, 'Vacaciones sin horario asignado vigente (esos días pagan S/0)',
    coalesce(string_agg(g.quien || ' (' || v.dias_sin_horario || ' días sin horario)', ' · '), '')
  from vac v join gente g on g.id = v.persona_id
  where g.en_planilla is true and g.sueldo_fijo is not true
    and v.dias_sin_horario > 0
),
-- 3 · FERIADO DENTRO DE UNAS VACACIONES  (se paga dos veces)
c3 as (
  select 3, 'Feriado caído dentro de unas vacaciones (doble pago)',
    coalesce(string_agg(g.quien || ' → ' || f.nombre || ' ' || to_char(f.fecha,'DD/MM'), ' · '), '')
  from vac_dias vd
  join gente g on g.id = vd.persona_id
  join feriados f on f.fecha = vd.dia
  where g.en_planilla is true and g.sueldo_fijo is not true and vd.le_tocaba
),
-- 4 · AUSENCIAS PAGADAS POSTERIORES AL CESE  (sobrepago)
c4 as (
  select 4, 'Ausencia pagada que sigue DESPUÉS del cese',
    coalesce(string_agg(x.quien || ' (' || x.que || ' hasta ' || to_char(x.hasta,'DD/MM')
             || ', cesó el ' || to_char(x.cese,'DD/MM') || ')', ' · '), '')
  from (
    select g.quien, 'vacaciones' as que, v.fecha_fin as hasta, g.fecha_cese as cese
    from vacaciones v join gente g on g.id = v.persona_id cross join per
    where g.fecha_cese between per.fecha_ini and per.fecha_fin and v.fecha_fin > g.fecha_cese
    union all
    select g.quien, a.tipo, a.fecha_fin, g.fecha_cese
    from ausencias a join gente g on g.id = a.persona_id cross join per
    where g.fecha_cese between per.fecha_ini and per.fecha_fin and a.fecha_fin > g.fecha_cese
      and a.anulada_at is null and a.tipo in ('descanso_medico','maternidad')
  ) x
),
-- 5 · SUELDO FIJO CON INGRESO O CESE DENTRO DEL PERIODO  (cobra el mes entero)
c5 as (
  select 5, 'Sueldo fijo que entra o cesa a mitad (cobra el mes entero)',
    coalesce(string_agg(g.quien || ' (' ||
      case when g.fecha_cese between per.fecha_ini and per.fecha_fin
           then 'cesa el ' || to_char(g.fecha_cese,'DD/MM')
           else 'ingresa el ' || to_char(g.fecha_ingreso,'DD/MM') end || ')', ' · '), '')
  from gente g, per
  where g.sueldo_fijo is true
    -- FALSO POSITIVO CORREGIDO el 2026-08-19, en su primera corrida contra
    -- producción: `between` incluye los bordes, y quien INGRESA el primer día
    -- del periodo —o CESA el último— estuvo vinculada el periodo entero. Ahí
    -- cobrar el mes completo es lo correcto y no hay nada que prorratear.
    -- Marcó a Dante Ramal, que ingresó justo el 29/07. En este sistema un falso
    -- positivo cuesta más que un falso negativo: entrena a ignorar la alerta.
    and (   (g.fecha_cese    >  per.fecha_ini and g.fecha_cese    <  per.fecha_fin)
         or (g.fecha_ingreso >  per.fecha_ini and g.fecha_ingreso <= per.fecha_fin))
),
-- 6 · CESA SIN NINGUNA MARCA  (desaparece de la planilla y cobra S/0 del mes)
c6 as (
  select 6, 'Cesa sin ninguna marca: desaparece de la planilla',
    coalesce(string_agg(g.quien || ' (cesó el ' || to_char(g.fecha_cese,'DD/MM') || ')', ' · '), '')
  from gente g cross join per
  left join marcas m on m.persona_id = g.id
  where g.fecha_cese between per.fecha_ini and per.fecha_fin
    and coalesce(m.dias_marcados, 0) = 0
),
-- 7 · EN PLANILLA SIN RÉGIMEN DE PENSIÓN  (aporte previsional en cero)
c7 as (
  select 7, 'En planilla sin régimen de pensión (aporte S/0)',
    coalesce(string_agg(g.quien, ' · ' order by g.quien), '')
  from gente g
  where g.en_planilla is true and g.estado = 'activo'
    and (g.regimen_pension is null or g.regimen_pension = '')
),
-- 8 · RACHA DE 7+ DÍAS SEGUIDOS CON MARCA  (sin descanso semanal, art. 3)
dias_m as (
  select j.persona_id, j.fecha,
         j.fecha - (row_number() over (partition by j.persona_id order by j.fecha))::int as isla
  from jornadas j, per
  where j.fecha between per.fecha_ini - 10 and per.fecha_fin
    and coalesce(j.horas_trabajadas,0) > 0
),
rachas as (
  select persona_id, isla, count(*) as largo, min(fecha) as desde, max(fecha) as hasta
  from dias_m group by persona_id, isla having count(*) >= 7
),
c8 as (
  select 8, 'Racha de 7+ días seguidos sin descanso (falta sobretasa 100 %)',
    coalesce(string_agg(g.quien || ' (' || r.largo || ' días, ' || to_char(r.desde,'DD/MM')
             || '→' || to_char(r.hasta,'DD/MM') || ', ' || coalesce(g.sede,'?') || ')',
             ' · ' order by r.largo desc), '')
  from rachas r join gente g on g.id = r.persona_id
  where g.en_planilla is true
),
-- 9 · VACACIONES QUE NO ENTRAN A LA BASE DE ESSALUD NI DE PENSIÓN
c9 as (
  select 9, 'Vacaciones fuera de la base de EsSalud y pensión',
    coalesce(string_agg(g.quien || ' (' || v.dias_vac || ' días)', ' · '), '')
  from vac v join gente g on g.id = v.persona_id
  where g.en_planilla is true and g.sueldo_fijo is not true and v.dias_vac > 0
),
todo as (
  select * from c1 union all select * from c2 union all select * from c3
  union all select * from c4 union all select * from c5 union all select * from c6
  union all select * from c7 union all select * from c8 union all select * from c9
)
select t.orden,
       t.chequeo,
       case when (select count(*) from per) = 0 then '⚠  sin periodo abierto'
            when t.quienes = '' then '✓  a nadie'
            else '🚫 LE PEGA A ALGUIEN' end as veredicto,
       case when t.quienes = '' then '—' else t.quienes end as quienes
from todo t
order by (case when t.quienes = '' then 1 else 0 end), t.orden;
