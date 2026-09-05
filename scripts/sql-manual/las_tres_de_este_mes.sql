-- ############################################################################
-- ####  LAS TRES QUE SALIERON REALES — SOLO LEE, NO ESCRIBE NADA          ####
-- ############################################################################
--
-- `a_quien_le_pega.sql` corrido contra producción el 2026-08-19 dejó tres cosas
-- con población y seis con nadie. Esta consulta baja al detalle de las tres,
-- que es lo que hace falta para decidir antes del cierre del 28.
--
--   A · ¿EL CIERRE VA A PODER COMPLETARSE? Camila Baca cesó el 29/07, DENTRO
--       del periodo. Ése es exactamente el caso del freno de la 0243/0244: si
--       ya cobró su liquidación con `monto_periodo > 0` y no tiene registrado
--       el descuento, `fn_planilla_congelar` aborta y no congela a NADIE.
--
--   B · CAMILA. Cesó el primer día del periodo y no tiene ninguna marca, así
--       que desaparece entera de la pantalla de Planilla. La pregunta no es
--       cuánto se le paga —puede ser poco o nada— sino si alguien la va a VER.
--
--   C · LAS RACHAS DE 7+ DÍAS. Cinco personas. Lo que importa no es la racha:
--       es qué día de ella debió ser descanso, si ese día cae en ESTE periodo,
--       y cuánto valdría su sobretasa del 100 % (art. 3 del D. Leg. 713).
--
-- OJO CON LO QUE ESTA CONSULTA NO PUEDE RESPONDER, y es la mitad del asunto:
-- una racha de 7 días puede ser LEGÍTIMA si el descanso se movió de día
-- (sustitución, art. 3). Con descanso rotativo —el régimen de TRU— rotar el
-- descanso de un lunes a un domingo encadena 7 días sin que nadie haga nada
-- mal. La consulta dice qué días son candidatos y cuánto costarían; si hubo
-- sustitución o no lo sabe DO, y hoy el sistema no tiene dónde anotarlo.
--
-- ES UN SOLO SELECT: el SQL Editor ejecuta solo la última sentencia.
-- ############################################################################

with sesion as (
  select set_config('request.jwt.claim.sub',
           (select auth_user_id::text from personas
             where rol = 'admin' and auth_user_id is not null
             order by (nombres ilike '%Felipe%') desc limit 1), true) as jwt
),
per as (
  select p.id, p.fecha_ini, p.fecha_fin, (p.fecha_fin - p.fecha_ini + 1) as dias
  from periodos_planilla p, sesion
  where (now() at time zone 'America/Lima')::date between p.fecha_ini and p.fecha_fin
  order by p.fecha_ini desc limit 1
),
filas as (
  select f from per, lateral jsonb_array_elements(
    fn_planilla_calcular(per.fecha_ini, per.fecha_fin, per.id) -> 'filas') f
),

-- ── A · ¿ABORTA EL CIERRE? ──────────────────────────────────────────────────
a_cuadra as (
  select count(*) as malas from filas
  where round(coalesce((f->>'total')::numeric,0) - round(
          coalesce((f->>'pago_base')::numeric,0)      + coalesce((f->>'monto_feriados')::numeric,0)
        + coalesce((f->>'monto_plus')::numeric,0)     + coalesce((f->>'asignacion_familiar')::numeric,0)
        + coalesce((f->>'monto_movilidad')::numeric,0)+ coalesce((f->>'monto_educacion')::numeric,0)
        - coalesce((f->>'descuento_afp')::numeric,0)  + coalesce((f->>'monto_sobretiempo')::numeric,0)
        -- ⇩ CAMBIO 2026-08-26 ⇩ Faltaba, y daba un descuadre FALSO a quien
        -- trabajó su séptimo día: la 0280 metió esta partida dentro de
        -- `chk_foto_cuadra` el 22/08 y las dos copias de esta suma —ésta y la
        -- de `va_a_poder_cerrarse.sql`— se quedaron en once. Medido: S/251.61
        -- de descuadre inventado sobre un total de S/2472.58. La lista sale del
        -- CHECK vivo, no de memoria:
        --   select pg_get_constraintdef(oid) from pg_constraint
        --    where conname = 'chk_foto_cuadra';
        + coalesce((f->>'monto_descanso_semanal')::numeric,0)
        + coalesce((f->>'bonos')::numeric,0)          - coalesce((f->>'descuentos')::numeric,0)
        - coalesce((f->>'retencion_4ta')::numeric,0), 2), 2) <> 0
),
a_freno as (
  select string_agg(lq.persona || ': liquidación con S/'
         || to_char(lq.monto_periodo,'FM999999990.00') || ' de este periodo, descuento puesto S/'
         || to_char(coalesce((f->>'descuentos')::numeric,0),'FM999999990.00'), ' · ') as txt
  from filas cross join per
  join lateral (
    select distinct on (lp.persona_id) lp.* from liquidacion_pagada lp
    where lp.persona_id = (f->>'persona_id')::uuid order by lp.persona_id, lp.version desc
  ) lq on true
  where lq.fecha_cese between per.fecha_ini and per.fecha_fin
    and lq.monto_periodo > 0
    and coalesce((f->>'total')::numeric,0) > 0
    and coalesce((f->>'descuentos')::numeric,0) < lq.monto_periodo
),

-- ── B · CAMILA ──────────────────────────────────────────────────────────────
b_camila as (
  select p.apellidos || ', ' || p.nombres as quien,
         p.fecha_cese, p.sueldo_fijo, p.tipo_vinculo, p.en_planilla,
         (select count(*) from jornadas j, per
           where j.persona_id = p.id and j.fecha between per.fecha_ini and per.fecha_fin
             and coalesce(j.horas_trabajadas,0) > 0) as dias_marcados,
         (select count(*) from filas where (f->>'persona_id')::uuid = p.id) as sale_en_planilla,
         (select count(*) from liquidacion_pagada l where l.persona_id = p.id) as tiene_liquidacion,
         (select count(*) from movimientos_planilla m, per
           where m.persona_id = p.id and m.periodo_id = per.id) as tiene_movimientos
  from personas p, per
  where p.fecha_cese between per.fecha_ini and per.fecha_fin
),

-- ── C · LAS RACHAS, Y EL DÍA QUE DEBIÓ SER DESCANSO ─────────────────────────
dias_m as (
  select j.persona_id, j.fecha, coalesce(j.horas_trabajadas,0) as h,
         j.fecha - (row_number() over (partition by j.persona_id order by j.fecha))::int as isla
  from jornadas j, per
  where j.fecha between per.fecha_ini - 40 and per.fecha_fin
    and coalesce(j.horas_trabajadas,0) > 0
),
enum as (
  select d.*, row_number() over (partition by d.persona_id, d.isla order by d.fecha) as n,
         count(*)  over (partition by d.persona_id, d.isla) as largo,
         min(d.fecha) over (partition by d.persona_id, d.isla) as desde,
         max(d.fecha) over (partition by d.persona_id, d.isla) as hasta
  from dias_m d
),
-- El día 7 de cada ciclo de siete es el que debió ser descanso: el ciclo
-- arranca tras un descanso y se corta a los 7 días (Informe 027-2021-MTPE/14).
candidatos as (
  select e.*, (e.n % 7 = 0) as es_el_septimo from enum e where e.largo >= 7
),
salario as (
  select a.persona_id, max(a.salario_mensual_soles) as s
  from asignaciones_salario a, per
  where a.vigente_desde <= per.fecha_fin
    and (a.vigente_hasta is null or a.vigente_hasta >= per.fecha_ini)
  group by a.persona_id
),
c_rachas as (
  select p.apellidos || ', ' || p.nombres as quien,
         coalesce(sd.codigo,'?') as sede,
         c.largo, c.desde, c.hasta, c.fecha as dia_de_descanso_trabajado, c.h as horas,
         (c.fecha between per.fecha_ini and per.fecha_fin) as en_este_periodo,
         (f.fecha is not null) as ese_dia_era_feriado,
         p.personal_direccion, p.sueldo_fijo,
         round(c.h * coalesce(s.s,0) / (6.5 * per.dias), 2) as sobretasa_100
  from candidatos c
  join personas p on p.id = c.persona_id
  left join sedes sd on sd.id = p.sede_base_id
  left join salario s on s.persona_id = c.persona_id
  left join feriados f on f.fecha = c.fecha
  cross join per
  where c.es_el_septimo and p.en_planilla is true
)

select * from (
  select 1 as ord, 'A · CIERRE' as bloque,
         case when (select malas from a_cuadra) > 0
                then '🚫 ' || (select malas from a_cuadra)::text || ' fila(s) no cuadran (chk_foto_cuadra)'
              when (select txt from a_freno) is not null
                then '🚫 el freno de la 0243/0244 va a abortar el cierre'
              else '✓ el cierre puede completarse' end as dato,
         coalesce((select txt from a_freno), '—') as detalle
  union all
  select 2, 'B · ' || b.quien,
         case when b.sale_en_planilla = 0 then '🚫 NO sale en la pantalla de Planilla'
              else '✓ sí sale en Planilla' end,
         'cesó ' || to_char(b.fecha_cese,'DD/MM') || ' · marcas en el periodo: ' || b.dias_marcados
           || ' · sueldo fijo: ' || coalesce(b.sueldo_fijo::text,'no')
           || ' · vínculo: ' || coalesce(b.tipo_vinculo,'?')
           || ' · liquidaciones: ' || b.tiene_liquidacion
           || ' · movimientos del periodo: ' || b.tiene_movimientos
  from b_camila b
  union all
  select 3, 'C · ' || r.quien || ' (' || r.sede || ')',
         case when r.en_este_periodo then '🚫 cae en ESTE periodo' else '· periodo anterior, ya pagado' end,
         'racha de ' || r.largo || ' días (' || to_char(r.desde,'DD/MM') || '→' || to_char(r.hasta,'DD/MM')
           || ') · el 7.º día fue el ' || to_char(r.dia_de_descanso_trabajado,'DD/MM')
           || ' con ' || round(r.horas,2) || ' h'
           || case when r.ese_dia_era_feriado then ' · OJO: ese día era FERIADO, ya lleva su propia sobretasa' else '' end
           || case when r.personal_direccion then ' · personal de dirección' else '' end
           || case when r.sueldo_fijo then ' · sueldo fijo' else '' end
           || ' → sobretasa del 100 %: S/' || to_char(r.sobretasa_100,'FM999999990.00')
  from c_rachas r
) z order by z.ord, z.detalle;
