-- ############################################################################
-- ####  ANTES (Y DESPUÉS) DE PEGAR LA 0501 — SOLO LEE, NO ESCRIBE NADA    ####
-- ############################################################################
--
-- Para qué. La 0501 sube la RMV a S/ 1,230, la base de colibrí y cayla, y la
-- asignación familiar a S/ 123 desde el 2026-10-01. Antes de pegarla hay que ver
-- QUIÉN cae en cada caso; después de pegarla, comprobar que quedó como se
-- prometió. Este mismo script sirve para las dos cosas: cada fila dice qué se
-- espera ANTES y qué se espera DESPUÉS.
--
-- Cómo se usa. Es UNA sola consulta a propósito: el SQL Editor solo muestra el
-- último resultado, y una consulta por comprobación se pierde. Se pega entera y
-- da una tabla de comprobaciones (orden · qué · resultado). NO lleva nombres ni
-- sueldos de nadie escritos acá; los nombres salen solo en el resultado.
--
-- Va contra las TABLAS, no contra funciones de diagnóstico: varias devuelven cero
-- filas en el Editor por el guard de admin, y cero filas se lee igual que
-- «no hay nada».
--
-- Los montos de la primera línea (param) son los de la 0501. Si Felipe decide
-- otra escala (p. ej. cayla en 1,230), se cambian acá, en la 0501 y en rangos.ts.
-- ############################################################################

with
param as (
  select date '2026-10-01'  as desde,
         1130::numeric      as rmv_vieja,
         1230::numeric      as rmv_nueva,
         1230.00::numeric   as monto_colibri,
         1245.00::numeric   as monto_cayla,
         123::numeric       as asignacion_nueva
),
-- Quién está en planilla, activo y con tramo abierto (lo que decide fn_fijar_base_declarada).
alc as (
  select p.id, a.rango,
         a.salario_mensual_soles as sal,
         p.sueldo_base_legal     as base,
         a.base_provision        as bp,
         p.sueldo_fijo           as sfijo,
         coalesce(p.cuenta_de_servicio, false) as cs,
         p.con_hijos,
         p.apellidos || ', ' || p.nombres as quien,
         exists (select 1 from asignaciones_salario f
                  where f.persona_id = p.id
                    and f.vigente_desde > (select desde from param)) as futuro,
         case a.rango when 'colibri' then (select monto_colibri from param)
                      when 'cayla'   then (select monto_cayla   from param) end as monto
    from personas p
    join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
   where p.estado = 'activo' and p.en_planilla is true
),
-- Clasificación: encima = ya cobra por sobre el monto (NO baja); por_tocar = sube.
cls as (
  select alc.*,
         (monto is not null and (sal > monto or coalesce(base, 0) > monto)) as encima,
         (monto is not null and not cs
            and not (sal > monto or coalesce(base, 0) > monto)
            and (sal is distinct from monto or base is distinct from monto)) as por_tocar,
         (monto is not null
            and ((sal > monto and coalesce(base, monto) < monto)
              or (coalesce(base, 0) > monto and sal < monto))) as mixto
    from alc
),
-- Practicantes: la 0501 NO los toca (no están en planilla). Piso de la Ley 28518
-- art. 45: la RMV completa, o RMV × horas / 30 si es preprofesional con menos de 30 h
-- pactadas (la misma cuenta del generador de convenios).
conv as (
  select distinct on (c.persona_id)
         c.persona_id, c.remuneracion_mensual as impresa, c.horas_semanales,
         (c.storage_path is not null) as firmado
    from contratos_generados c
   where c.tipo = 'convenio_practicas' and c.anulado_at is null
   order by c.persona_id, c.fecha_inicio desc, c.generado_at desc, c.id desc
),
prac as (
  select p.apellidos || ', ' || p.nombres as quien,
         coalesce(p.practicante_modalidad, '(sin modalidad)') as modalidad,
         cv.horas_semanales as horas, a.salario_mensual_soles as paga, cv.impresa,
         coalesce(cv.firmado, false) as firmado,
         case when p.practicante_modalidad = 'preprofesional' and cv.horas_semanales is not null
              then round((select rmv_vieja from param) * least(cv.horas_semanales, 30) / 30, 2)
              else (select rmv_vieja from param) end as piso_viejo,
         case when p.practicante_modalidad = 'preprofesional' and cv.horas_semanales is not null
              then round((select rmv_nueva from param) * least(cv.horas_semanales, 30) / 30, 2)
              else (select rmv_nueva from param) end as piso_nuevo
    from personas p
    left join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
    left join conv cv on cv.persona_id = p.id
   where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
     and coalesce(p.cuenta_de_servicio, false) = false
),
-- La RMV y la asignación tal como las lee la planilla el último día del periodo.
lee as (
  select
    (select pl.valor from parametros_laborales pl where pl.clave = 'rmv' and pl.sede_codigo is null
        and pl.vigente_desde <= date '2026-10-28'
        and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-28')
      order by pl.vigente_desde desc limit 1) as rmv_28oct,
    (select pl.valor from parametros_laborales pl where pl.clave = 'rmv' and pl.sede_codigo is null
        and pl.vigente_desde <= date '2026-09-28'
        and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-28')
      order by pl.vigente_desde desc limit 1) as rmv_28sep,
    (select pl.valor from parametros_laborales pl where pl.clave = 'asignacion_familiar' and pl.sede_codigo is null
        and pl.vigente_desde <= date '2026-10-28'
        and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-28')
      order by pl.vigente_desde desc limit 1) as asig_28oct,
    (select pl.valor from parametros_laborales pl where pl.clave = 'asignacion_familiar' and pl.sede_codigo is null
        and pl.vigente_desde <= date '2026-09-28'
        and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-28')
      order by pl.vigente_desde desc limit 1) as asig_28sep,
    (select (valor ->> 'monto')::numeric from configuracion where clave = 'asignacion_familiar') as asig_config
),
filas(orden, que, resultado) as (

  select 1, '(i) Activos en planilla por rango — sueldo y base declarada',
         (select string_agg(x.rango || ': ' || x.n || ' persona(s) · sueldo ' || x.smin || ' a ' || x.smax
                            || ' · base ' || coalesce(x.bmin::text, 'sin confirmar') || ' a '
                            || coalesce(x.bmax::text, 'sin confirmar'),
                            E'\n' order by x.rango)
            from (select rango, count(*) n, min(sal) smin, max(sal) smax, min(base) bmin, max(base) bmax
                    from alc group by rango) x)

  union all select 2, '(i) A quiénes SUBE la 0501 (colibrí y cayla, por debajo de su monto)',
         (select count(*)::text || ' persona(s)' from cls where por_tocar)

  union all select 3, '(i) Casos que DETIENEN la migración — esperado: todo en 0',
         (select 'base sin confirmar: '        || count(*) filter (where por_tocar and base is null)
              || ' · base_provision propia: '  || count(*) filter (where por_tocar and bp is not null)
              || ' · sueldo fijo: '            || count(*) filter (where por_tocar and sfijo is true)
              || ' · tramo ya programado: '    || count(*) filter (where por_tocar and futuro)
              || ' · un campo arriba y otro abajo: ' || count(*) filter (where mixto)
            from cls)

  union all select 4, '(i) Quién cobra POR ENCIMA de su monto y por eso NO se toca (nunca baja)',
         (select coalesce(string_agg(quien || ' (' || rango || ')', ' · ' order by quien), 'nadie')
            from cls where encima)

  union all select 5, '(i) Quién queda BAJO S/ 1,230 (sueldo o base) tras el reajuste — esperado: nadie',
         (select coalesce(string_agg(quien || ' (' || rango || ')', ' · ' order by quien), 'nadie')
            from cls
           where (sal < (select rmv_nueva from param) or coalesce(base, 1e9) < (select rmv_nueva from param))
             and not por_tocar and not encima)

  union all select 6, '(ii) Practicantes: ' || quien || ' · ' || modalidad
                      || ' · horas ' || coalesce(horas::text, 'completas')
                      || ' · paga ' || coalesce(paga::text, 'SIN SUBVENCIÓN CARGADA')
                      || ' · piso hasta el 30-sep ' || piso_viejo || ' → desde el 1-oct ' || piso_nuevo
                      || case when firmado then ' · convenio firmado' else ' · sin convenio firmado' end,
         case when paga is null then 'FALTA cargar su subvención'
              when paga < piso_viejo then 'YA ESTABA BAJO EL PISO VIEJO (le faltan ' || (piso_nuevo - paga) || ' para el nuevo)'
              when paga < piso_nuevo then 'QUEDA BAJO EL PISO EL 1-OCT (le faltan ' || (piso_nuevo - paga) || ')'
              else 'sin problema' end
         from prac

  union all select 7, '(ii) Practicantes activos', (select count(*)::text from prac)

  union all select 8, '(iii) RMV que lee el sistema — 2026-09-28 / 2026-10-28 (esperado DESPUÉS: 1130 / 1230)',
         (select coalesce(rmv_28sep::text, 'sin fila') || ' / ' || coalesce(rmv_28oct::text, 'sin fila') from lee)

  union all select 9, '(iii) Asignación familiar — 2026-09-28 / 2026-10-28 / configuracion (esperado DESPUÉS: 113 / 123 / 123)',
         (select coalesce(asig_28sep::text, 'sin fila') || ' / ' || coalesce(asig_28oct::text, 'sin fila')
                 || ' / ' || coalesce(asig_config::text, 'sin fila') from lee)

  union all select 10, '(iv) Quién tiene la casilla «tiene hijos» y cuánto suma la asignación de 123',
         (select count(*) filter (where con_hijos)::text || ' persona(s) · +S/ '
                 || (count(*) filter (where con_hijos) * ((select asignacion_nueva from param) - 113))
                 || ' al mes de asignación · ≈ S/ '
                 || round(count(*) filter (where con_hijos) * ((select asignacion_nueva from param) - 113) * 1.2567, 2)
                 || ' al mes con EsSalud, gratificación, CTS y vacaciones'
            from alc where not cs)

  union all select 11, '(v) Periodos de planilla ABIERTOS y su fecha_fin real (esperado: fecha_fin 2026-10-28; el 1-oct se midió 2026-09-28 → 2026-10-28)',
         (select coalesce(string_agg(fecha_ini || ' → ' || fecha_fin, ' · ' order by fecha_ini), 'ninguno abierto')
            from periodos_planilla where estado = 'abierto')

  union all select 12, '(v) Último periodo cerrado o pagado',
         (select coalesce((select fecha_ini || ' → ' || fecha_fin || ' (' || estado || ')'
                             from periodos_planilla where estado <> 'abierto'
                            order by fecha_fin desc limit 1), 'ninguno'))

  union all select 13, '(vi) migraciones_aplicadas 0499–0501, con número Y nombre (0500 es de la rama paralela)',
         (select coalesce(string_agg(numero || ' ' || nombre, E'\n' order by numero), '(ninguna de las tres está)')
            from migraciones_aplicadas where numero between 499 and 501)

  union all select 14, '(vii) Admin que firmará el rastro de los tramos (activo más antiguo con usuario)',
         (select coalesce(p.apellidos || ', ' || p.nombres || ' · ingreso ' || coalesce(p.fecha_ingreso::text, '?'),
                          'NINGUNO: la migración se detendría')
            from (select 1) u
            left join lateral (select * from personas
                                where rol = 'admin' and estado = 'activo' and auth_user_id is not null
                                order by fecha_ingreso nulls last, id limit 1) p on true)

  union all select 15, '(vii) Alcanzados con un mes PAGADO de rendimiento < 100 (frenaría la base legal) — esperado: 0',
         (select count(distinct c.id)::text from cls c
            join rendimiento_mensual r on r.persona_id = c.id
           where c.por_tocar and r.porcentaje < 100
             and exists (select 1 from periodos_planilla pp
                          where pp.estado = 'pagado'
                            and extract(year from pp.fecha_fin)::int = r.anio
                            and extract(month from pp.fecha_fin)::int = r.mes))

  union all select 16, '(viii) Política salarial: versión vigente y constancias ya dejadas',
         (select coalesce(ps.version::text || ' · publicada ' || ps.publicada_at::date || ' · '
                          || (select count(*) from politica_salarial_acuses a where a.version = ps.version)
                          || ' constancia(s)', 'ninguna versión publicada')
            from (select 1) u
            left join lateral (select * from politica_salarial order by version desc limit 1) ps on true)

  union all select 17, '(viii) Escala que publicará la Política (categorias_laborales) — esperado DESPUÉS: 1230 · 1245 · 1260 · 1360 · 1440 · 1500',
         (select string_agg(salario_declarado::text, ' · ' order by orden) from categorias_laborales)
)
select orden, que, resultado from filas order by orden, que, resultado;
