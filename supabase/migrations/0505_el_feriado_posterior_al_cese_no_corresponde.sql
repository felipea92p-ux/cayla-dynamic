-- ============================================================================
-- 0505 · El feriado posterior al cese no corresponde: ni se paga ni se acusa
--        como «sin salario»
-- ============================================================================
--
-- ---- QUÉ PROMETE ----
--
--   Que `fn_feriado_devengado_nucleo` pregunte primero si la persona seguía
--   vinculada el día del feriado —entre su ingreso y su cese, los dos
--   inclusive— y recién después por su salario. Un feriado posterior al cese:
--
--     · cuenta como «no corresponde», igual que uno anterior al ingreso;
--     · paga S/ 0.00 aunque el tramo de salario siga abierto;
--     · deja de contarse en `sin_tramo`, que es lo que la planilla muestra como
--       «N feriado(s) sin salario ese día: no se pudo calcular».
--
--   Nada más cambia: el feriado de quien SÍ estaba vinculada se calcula
--   exactamente igual que en la 0397.
--
-- ---- EL PROBLEMA, MEDIDO EN PRODUCCIÓN EL 2026-10-02 ----
--
--   Periodo 29-sep → 28-oct, un solo feriado: el 8-oct (Combate de Angamos).
--   Dos personas cesaron antes —una practicante y una integrante en
--   planilla— y las dos salían en Planilla con «1 feriado(s) sin
--   salario ese día: no se pudo calcular · Equipo →». Llamando a esta misma
--   función en el SQL Editor, para las dos: tramos de salario cerrados el día
--   del cese, feriado 2026-10-08, `sin_salario = true`, `monto = 0`.
--
--   La plata estaba bien; el aviso no. `fn_cesar_persona` cierra el salario el
--   día del cese (0415, como debe), y esta función solo excluía los feriados
--   ANTERIORES al ingreso: al llegar a uno posterior al cese buscaba un tramo,
--   no lo encontraba y lo contaba como dato faltante.
--
--   Y el aviso mandaba a hacer algo indebido. Su enlace lleva a Equipo, donde
--   «Asignar salario» se ofrece también a quien ya cesó, y `fn_set_salario`
--   no mira el cese: abre un tramo sin fin para alguien que ya se fue. Con eso
--   el aviso desaparecía y el feriado empezaba a pagarse — medido en la prueba
--   399: S/ 14.41 por un feriado posterior al cese, a S/ 1,500 con ocho días
--   trabajados en el periodo. El aviso se apagaba justo cuando empezaba el
--   error.
--
-- ---- LA REGLA: EL FERIADO POSTERIOR AL CESE NO SE PAGA ----
--
--   Decidido por Felipe el 2026-10-02. Hasta hoy el sistema tenía DOS
--   respuestas para la misma situación, según cómo se registrara la baja:
--
--     · con la baja por el botón (todos los casos reales): S/ 0 — pero por
--       accidente, porque el tramo estaba cerrado, no porque nada lo decidiera;
--     · con el cese puesto a mano, como en la prueba 185: se pagaba, y la 0244
--       lo llamó «el saldo legítimo que sí ganó». No hay ningún documento que
--       lo decida: era el montaje que esa prueba necesitaba para que el
--       periodo calculara más que la liquidación.
--
--   Se elige la primera, y por tres razones independientes:
--     1. El art. 8 del D. Leg. 713 da la remuneración del feriado a «los
--        trabajadores». El día del feriado esa persona ya no lo era.
--     2. La liquidación ya corta en el día del cese («ni un día más», 0244, que
--        llama a la planilla con p_fin = fecha_cese). Así planilla y
--        liquidación dicen lo mismo, y un cese seguido de un feriado no deja un
--        saldito de pocos soles que haya que transferir semanas después a quien
--        ya se fue.
--     3. Es lo que producción ya pagaba. Esta migración no cambia ningún monto
--        de nadie cesado por el botón; solo cierra el camino por el que SÍ se
--        habría pagado (el salario reabierto) y apaga la falsa alarma.
--
-- ---- POR QUÉ ASÍ ----
--
--   DECIDÍ: una sola pregunta «¿seguía vinculada ese día?» (el lateral `vin`),
--   y que el pago, la sobretasa, las horas proporcionales y el aviso cuelguen
--   de ella. Antes la condición `fb.fecha >= pe.fecha_ingreso` estaba escrita
--   cuatro veces; ahora se escribe una.
--
--   DESCARTÉ esconder el aviso en la pantalla (revision.ts), porque la base
--   seguiría diciendo `sin_salario = true` y cualquier otra pantalla que lo
--   lea volvería a acusar; y porque escondería también el caso verdadero
--   —alguien activo con un hueco en sus tramos justo el día del feriado—, que
--   sí hay que ver y que la prueba 399 vigila.
--
--   DESCARTÉ dejar de cerrar el salario al cesar: deshace la 0415 (el salario
--   volvería a figurar «vigente» años después) y haría que el feriado
--   posterior se pagara en silencio.
--
--   SE ROMPE SI alguien registra un cese con una fecha anterior a la real. El
--   feriado que caiga entre la fecha falsa y la verdadera pasa a «no
--   corresponde» sin ningún aviso —hoy al menos saltaba «sin salario»—. La
--   defensa contra eso no está aquí: está en que la baja exige la fecha y deja
--   rastro en correcciones_auditoria (0415).
--
-- ---- QUÉ CAMBIA PARA QUIEN LEE ESTA FUNCIÓN ----
--
--   · `no_corresponde` cuenta ahora los anteriores al ingreso Y los
--     posteriores al cese. `detalle` gana `despues_cese` (boolean) junto a
--     `antes_ingreso`, para que la pantalla diga cuál de los dos es. Las
--     claves que ya existían no cambian de nombre ni de tipo.
--   · `fn_planilla_calcular_nucleo` copia `sin_tramo` y `no_corresponde` a
--     `feriados_sin_salario` y `feriados_no_corresponde`: no se toca, y por
--     eso no choca con la 0504 (otra rama), que la reescribe.
--   · `fn_provisiones` suma el `monto` del detalle: un feriado posterior al
--     cese deja de reservarse. Con la baja por el botón ya reservaba 0 (tramo
--     cerrado); solo cambia donde el tramo quedó abierto, que es justo el
--     caso que no debía pagar.
--
-- ---- QUÉ ASUME ----
--
--   · Que la versión vigente es la de la 0397 (`./scripts/donde-vive.sh
--     fn_feriado_devengado_nucleo`). md5 de partida en el repositorio:
--     c2cddb1df20aa7bd5e662b5b47e1a4b8 (9 312 caracteres).
--     md5 de partida en PRODUCCIÓN, medido en el SQL Editor el 2026-10-02:
--     c2cddb1df20aa7bd5e662b5b47e1a4b8 (9 312) — idéntico al repositorio.
--     md5 de llegada (medido en la base desechable con la 0505 aplicada):
--     82178e2323a2182d7faacb21066a69bc (10 344).
--   · Que `personas.fecha_cese` es el último día trabajado, inclusive: el mismo
--     corte que usan la 0418 para las ausencias y `fn_liquidacion`.
--
-- ---- QUÉ NO HACE ----
--
--   · No pone el candado en `fn_set_salario`. Asignar un salario que empieza
--     después del cese sigue siendo posible; la baja ya se niega a lo inverso
--     (0176). Es el mismo candado en la otra puerta, y va en su propia
--     migración. Con esta, al menos, ya no paga.
--   · No corrige el ejemplo que citan los comentarios de `fn_periodo_pagado`
--     (0244, y sus copias en 0280, 0284, 0323, 0326 y 0476): «un feriado
--     dentro del periodo pero posterior al cese» como saldo legítimo. Desde
--     esta migración ese ejemplo es falso; el que sigue valiendo es «un
--     marcaje cerrado tarde», que es el que monta ahora la prueba 185.
--     Reescribir una función entera para corregir un comentario es lo que la
--     casa no hace.
--   · No junta las otras preguntas «¿seguía vinculada ese día?» que ya existen
--     dentro de `fn_planilla_calcular_nucleo` (el tope del pago y las cuatro
--     ausencias de la 0418). Esta es la sexta. Juntarlas es una decisión
--     aparte.
--
-- ---- CÓMO SE VERIFICÓ ANTES DE ESCRIBIR ESTA LÍNEA ----
--
--   En una base desechable con las 481 migraciones del repositorio (nunca en
--   el Postgres compartido), dentro de BEGIN … ROLLBACK:
--     · la prueba 399 contra la 0397: caen exactamente las 9 que dependen del
--       cambio y pasan las 6 que vigilan lo que no debe cambiar;
--     · la misma prueba con esta migración: 15 de 15;
--     · la suite entera antes y después, archivo por archivo (ver el PR).
--
-- ---- CÓMO SE REVIERTE ----
--
--   Pegar de nuevo el `create or replace` de `fn_feriado_devengado_nucleo` de
--   la 0397. Ningún dato se toca: esta migración solo cambia cómo se lee
--   `personas.fecha_cese`.
--
-- ---- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ----
--
--   La consulta del final. Y en producción, los dos casos que la motivaron
--   tienen que pasar a `sin_salario = false`, `despues_cese = true`,
--   `monto = 0` (segunda consulta del final).
-- ============================================================================

-- ── 1 · El cálculo del feriado, con el corte del cese — sobre el cuerpo de la 0397 ──
CREATE OR REPLACE FUNCTION public.fn_feriado_devengado_nucleo(p_persona uuid, p_desde date, p_hasta date, p_dias integer, p_salario_asof date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tope_dm int;
  v_out jsonb;
begin
  -- Sin guard de rol a proposito: ver la nota de fn_planilla_calcular_nucleo
  -- mas arriba en esta misma migracion, el mismo razonamiento aplica aca.
  -- La proteccion es revoke + funciones_nunca_para_authenticated, no un
  -- chequeo interno.

  select coalesce((valor->>'umbral_essalud')::int, 20) into v_tope_dm
  from configuracion where clave = 'descanso_medico_aviso_dias';
  if v_tope_dm is null then v_tope_dm := 20; end if;

  with pe as (
    select p.id, p.fecha_ingreso, p.fecha_cese, p.sueldo_fijo, p.en_planilla
    from personas p where p.id = p_persona
  ),
  fer_bloque as (
    select f.fecha,
           case when p_dias is not null then p_desde else coalesce(pp.fecha_ini, can.ini) end as b_ini,
           case when p_dias is not null then p_hasta else coalesce(pp.fecha_fin, can.fin) end as b_fin,
           case when p_dias is not null then p_dias
                else coalesce((pp.fecha_fin - pp.fecha_ini) + 1, (can.fin - can.ini) + 1) end as b_dias
    from feriados f
    left join periodos_planilla pp on p_dias is null and f.fecha between pp.fecha_ini and pp.fecha_fin
    cross join lateral (
      select (q.m + make_interval(days =>
                least(29, extract(day from (date_trunc('month', q.m) + interval '1 month - 1 day'))::int) - 1))::date as ini,
             (date_trunc('month', q.m + interval '1 month') + interval '27 days')::date as fin
      from (select case when extract(day from f.fecha) >= 29
                        then date_trunc('month', f.fecha::timestamp)
                        else date_trunc('month', f.fecha::timestamp) - interval '1 month' end as m) q
    ) can
    where f.fecha between p_desde and p_hasta
  ),
  bloque as (
    select distinct b.b_ini, b.b_fin, b.b_dias, 6.5 * b.b_dias as v_base
    from fer_bloque b
  ),
  horas_bloque as (
    select bq.b_ini, bq.b_fin, bq.b_dias, bq.v_base,
           coalesce(hh.horas_totales, 0) as horas_mes,
           case when pe.sueldo_fijo then 0
                else coalesce(hh.horas_totales / nullif(hh.dias_marcados, 0),
                              bq.v_base / nullif(labp.dias, 0),
                              0) * coalesce(vacd.dias, 0) end as horas_vacaciones,
           case when pe.sueldo_fijo then 0
                else coalesce(hh.horas_totales / nullif(hh.dias_marcados, 0),
                              bq.v_base / nullif(labp.dias, 0),
                              0) * coalesce(dmd.dias, 0) end as horas_descanso_medico
    from bloque bq
    cross join pe
    left join lateral (
      select coalesce(sum(coalesce(j.horas_trabajadas, 0)), 0) as horas_totales,
             count(*) filter (where coalesce(j.horas_trabajadas, 0) > 0) as dias_marcados
      from jornadas j
      where j.persona_id = pe.id and j.fecha between bq.b_ini and bq.b_fin
    ) hh on true
    left join lateral (
      select count(*)::int as dias
      from generate_series(bq.b_ini, bq.b_fin, interval '1 day') d
      join lateral (
        select ha.dias_laborables, ha.horario_por_dia
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
        order by ha.vigente_desde desc limit 1
      ) hv on true
      where pe.en_planilla
        and exists (select 1 from vacaciones v
                     where v.persona_id = pe.id
                       and d.d::date between v.fecha_inicio and v.fecha_fin)
        and not exists (
              select 1 from jornadas j
              where j.persona_id = pe.id and j.fecha = d.d::date
                and j.horas_trabajadas is not null and j.horas_trabajadas > 0)
        and case when hv.horario_por_dia is not null
                 then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                 else extract(dow from d.d)::int = any(hv.dias_laborables) end
    ) vacd on true
    left join lateral (
      select count(*)::int as dias
      from (
        select dd.d::date as dia,
               row_number() over (partition by extract(year from dd.d) order by dd.d) as n
        from ausencias a
        join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') as dd(d) on true
        where a.persona_id = pe.id and a.tipo = 'descanso_medico' and a.anulada_at is null
          and a.aprobada_at is not null
      ) dm
      join lateral (
        select ha.dias_laborables, ha.horario_por_dia
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= dm.dia
        order by ha.vigente_desde desc limit 1
      ) hv on true
      where pe.en_planilla
        and dm.n <= v_tope_dm
        and dm.dia between bq.b_ini and bq.b_fin
        and not exists (select 1 from vacaciones v
                         where v.persona_id = pe.id
                           and dm.dia between v.fecha_inicio and v.fecha_fin)
        and not exists (
              select 1 from jornadas j
              where j.persona_id = pe.id and j.fecha = dm.dia
                and j.horas_trabajadas is not null and j.horas_trabajadas > 0)
        and case when hv.horario_por_dia is not null
                 then hv.horario_por_dia ? (extract(dow from dm.dia)::int::text)
                 else extract(dow from dm.dia)::int = any(hv.dias_laborables) end
    ) dmd on true
    left join lateral (
      select count(*)::int as dias
      from generate_series(bq.b_ini, bq.b_fin, interval '1 day') d
      join lateral (
        select ha.dias_laborables, ha.horario_por_dia
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
        order by ha.vigente_desde desc limit 1
      ) hv on true
      where case when hv.horario_por_dia is not null
                 then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                 else extract(dow from d.d)::int = any(hv.dias_laborables) end
    ) labp on true
  ),
  dias as (
    select fb.fecha,
           coalesce(hf.horas_trabajadas, 0) as horas_trabajadas,
           case when pe.en_planilla and tt.salario is not null and vin.vinculado
                then (case when pe.sueldo_fijo then 0
                           else 7.5 * (hb.horas_mes + hb.horas_vacaciones + hb.horas_descanso_medico)
                                / hb.v_base end) * tt.salario / hb.v_base
                else 0 end as prorrateo,
           case when pe.en_planilla and tt.salario is not null and vin.vinculado
                then (case when ds.otorgado then 0 else coalesce(hf.horas_trabajadas, 0) end)
                     * tt.salario / hb.v_base
                else 0 end as sobretasa,
           case when pe.sueldo_fijo then 0
                else 7.5 * (hb.horas_mes + hb.horas_vacaciones + hb.horas_descanso_medico)
                     / hb.v_base end as proporcional_horas,
           (tt.salario is null and vin.vinculado) as sin_salario,
           vin.antes_ingreso,
           vin.despues_cese,
           ds.otorgado as descanso_sustitutorio,
           ds.fecha_descanso,
           pe.en_planilla, vin.vinculado
    from fer_bloque fb
    cross join pe
    -- ⇩⇩⇩ CAMBIO 0505 ⇩⇩⇩ ¿SEGUÍA VINCULADA ESE DÍA? Se pregunta UNA vez, aquí,
    -- y antes que el salario. Hasta la 0397 solo se miraba el ingreso: un
    -- feriado posterior al cese caía en «sin salario» porque la baja (0415)
    -- cierra el tramo ese día, y la planilla lo acusaba como dato que falta.
    -- No falta nada: ese día ya no era parte del equipo, y no se le paga
    -- (decidido por Felipe el 2026-10-02; ver la cabecera). El cese es el
    -- último día trabajado, inclusive — el mismo corte que la 0418 y
    -- fn_liquidacion («ni un día más»).
    cross join lateral (
      select fb.fecha < pe.fecha_ingreso                                as antes_ingreso,
             coalesce(fb.fecha > pe.fecha_cese, false)                  as despues_cese,
             fb.fecha >= pe.fecha_ingreso
               and (pe.fecha_cese is null or fb.fecha <= pe.fecha_cese) as vinculado
    ) vin
    join horas_bloque hb on hb.b_ini = fb.b_ini and hb.b_fin = fb.b_fin
    left join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = pe.id
        -- ⇩⇩⇩ CAMBIO 0338 ⇩⇩⇩ p_salario_asof, si se pasa, congela la fecha
        -- de referencia del sueldo en vez de usar el día del feriado.
        and a.vigente_desde <= coalesce(p_salario_asof, fb.fecha)
        and (a.vigente_hasta is null or a.vigente_hasta >= coalesce(p_salario_asof, fb.fecha))
      order by a.vigente_desde desc limit 1
    ) tt on true
    left join jornadas hf on hf.persona_id = pe.id and hf.fecha = fb.fecha
    left join lateral (
      select true as otorgado, d.fecha_descanso_sustitutorio as fecha_descanso
      from feriados_descanso_sustitutorio d
      where d.persona_id = pe.id and d.fecha_feriado = fb.fecha and d.estado = 'OTORGADO'
      limit 1
    ) ds on true
    where not exists (
      select 1 from ausencias a
      where a.persona_id = pe.id and a.tipo = 'maternidad' and a.anulada_at is null
        and a.subsidio_diario is not null
        and a.aprobada_at is not null
        and fb.fecha between a.fecha_inicio and a.fecha_fin
    )
  )
  select jsonb_build_object(
    'monto',          coalesce(sum(prorrateo + sobretasa), 0),
    'prorrateo',      coalesce(sum(prorrateo), 0),
    'sobretasa',      coalesce(sum(sobretasa), 0),
    'sin_tramo',      count(*) filter (where sin_salario),
    -- CAMBIO 0505 · «no corresponde» es antes del ingreso O después del cese.
    'no_corresponde', count(*) filter (where antes_ingreso or despues_cese),
    'compensados',    count(*) filter (where descanso_sustitutorio),
    'detalle', coalesce(jsonb_agg(jsonb_build_object(
        'fecha', fecha,
        'horas_trabajadas', horas_trabajadas,
        'proporcional_horas', case when en_planilla and vinculado
                                   then round(proporcional_horas, 2) else 0 end,
        'monto', prorrateo + sobretasa,
        'sin_salario', sin_salario,
        'antes_ingreso', antes_ingreso,
        'despues_cese', despues_cese,                    -- CAMBIO 0505
        'descanso_sustitutorio', descanso_sustitutorio,
        'descanso_fecha', fecha_descanso
      ) order by fecha), '[]'::jsonb)
  ) into v_out
  from dias;

  return v_out;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (505, 'el_feriado_posterior_al_cese_no_corresponde')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
select
  position('despues_cese' in prosrc) > 0 as tiene_el_corte_del_cese,
  (select count(*) from pg_proc where proname = 'fn_feriado_devengado_nucleo') as una_sola_version,
  has_function_privilege('authenticated', 'fn_feriado_devengado_nucleo(uuid, date, date, integer, date)', 'execute')
    as navegador_puede_llamarla_debe_ser_false,
  md5(prosrc) as md5_final,
  length(prosrc) as largo_final
from pg_proc where proname = 'fn_feriado_devengado_nucleo';

-- Los dos casos del 2026-10-02 (o quien haya cesado este periodo). Después de
-- pegar: feriado 2026-10-08 con sin_salario = false, despues_cese = true y
-- monto = 0.
select p.fecha_cese, d->>'fecha' as feriado, d->>'sin_salario' as sin_salario,
       d->>'despues_cese' as despues_cese, d->>'monto' as monto
from personas p
cross join lateral jsonb_array_elements(
  fn_feriado_devengado_nucleo(p.id, date '2026-09-29', date '2026-10-28', 30) -> 'detalle') d
where p.fecha_cese between date '2026-09-29' and date '2026-10-28';
