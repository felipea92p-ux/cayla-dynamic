-- ============================================================================
-- 0545 · Reabrir un grupo pagado por error deja SUS HORAS al día
-- ============================================================================
--
-- QUÉ PROMETE
--   `fn_reparar_dias_tras_reabrir(grupo, desde, hasta)` recalcula la jornada de
--   cada día con marcas de ese grupo en el rango y vuelve a evaluar el sello de
--   «día por revisar». Devuelve cuántos días recalculó. Es idempotente: correrla
--   dos veces deja lo mismo. Nunca toca marcas — solo lo que se deriva de ellas.
--   Y se niega (sin cambiar nada) si algún día del rango sigue pagado para ese
--   grupo, porque recalcular ahí no haría NADA y lo haría sin avisar.
--
--   La propia migración la usa una vez, para el incidente de abajo.
--
-- EL INCIDENTE (visto en producción el 2026-10-22, medido con tres consultas)
--   El 2026-10-21 a las 15:27:50 (Lima) el grupo «planilla» del periodo
--   28-sep → 28-oct se marcó «pagado y congelado» por error, siete días antes de
--   que el periodo terminara. Desde ese instante:
--
--     · las 12 marcas de gente de planilla quedaron selladas una por una
--       (0207: `if v_en_pagado`), mientras las de practicante, prueba y rxh
--       seguían normales — por eso el corte era por GRUPO y no por hora;
--     · `fn_recalcular_jornada` salió en su primera línea útil (0446, línea 106)
--       y las 10 jornadas del 21 se quedaron «abierta» / «en_pausa», sin
--       salida y sin horas, aunque la persona ya había marcado su salida;
--     · Correcciones decía «1 día quedó marcado y ya cuadra · No hay nada que
--       corregir» — verdad sobre la secuencia, falsa sobre el pago.
--
--   Quien lo marcó lo revirtió desde Planilla con `fn_revertir_pago`. Eso reabre
--   el grupo, pero NO repara nada: ver el siguiente punto.
--
-- POR QUÉ HACE FALTA, Y POR QUÉ NO BASTA CON `fn_revertir_pago`
--   `fn_revertir_pago` (0323) solo recalcula las jornadas si
--   `periodos_planilla.estado` estaba en 'pagado' ANTES de reabrir. Con un solo
--   grupo pagado el periodo se queda 'abierto' (los demás grupos con gente aún
--   no se pagan), así que no recalcula. Esa condición es de cuando el candado de
--   horas era uno solo para el periodo entero; la 0327 lo hizo por grupo y no
--   volvió sobre esa condición. Esta migración NO la cambia —es otra pieza y
--   otro riesgo—: da la herramienta que repara el daño y deja la prueba que
--   documenta el hueco (supabase/tests/437).
--
-- QUÉ ASUME
--   · Que el grupo YA se reabrió (`fn_revertir_pago`). Si no, la función se
--     niega y dice cuál día y qué persona.
--   · `fn_recalcular_jornada` (0446) y `fn_resellar_dia` (0188) son las
--     vigentes. No se reescribe ninguna: esta migración solo las llama. No hay,
--     por tanto, md5 de partida que declarar.
--
-- POR QUÉ `fn_resellar_dia` Y NO `fn_levantar_sello_si_el_dia_cuadra`
--   Las dos quitan el sello cuando el día cuadra; difieren en a qué estado
--   dejan la marca. `fn_levantar_*` la deja 'revisada' (alguien la revisó);
--   `fn_resellar_dia` la deja 'normal'. Aquí nadie revisó nada: el sello nunca
--   debió ponerse, así que 'normal' es la verdad. Además `fn_resellar_dia`
--   funciona en los dos sentidos: un día que SÍ está roto sigue sellado.
--
-- POR QUÉ LA FUNCIÓN NO SE EXPONE AL CLIENTE
--   Es una herramienta de reparación, no una pantalla: se revoca de `anon`,
--   `authenticated` y `public`. La corre quien pega SQL en el editor, que es
--   `postgres`. Sin SECURITY DEFINER no hay guardia que escribir (y la
--   exigencia de `is not true` no aplica a algo que nadie puede llamar).
--
-- QUÉ NO CIERRA, Y POR QUÉ NO
--   · Que `fn_periodo_pagado` deja pagar un grupo cuyo periodo no terminó. Hay
--     excepciones legítimas (una liquidación, un practicante que se va); decidir
--     cuáles es de Felipe, no de esta migración.
--   · Que `fn_revertir_pago` no recalcule en este caso.
--   · Que Correcciones muestre «ya cuadra» cuando el sello viene de un grupo
--     pagado: `fn_dias_por_revisar` mira solo `periodos_planilla.estado`.
--   Los tres quedan como trabajo propio.
--
-- CÓMO SE REVIERTE
--   `drop function fn_reparar_dias_tras_reabrir(text, date, date);` — la función
--   no guarda nada. Lo que ya recalculó no se «des-recalcula»: las jornadas son
--   derivadas y volver a calcularlas con los mismos marcajes da lo mismo.
-- ============================================================================

create or replace function fn_reparar_dias_tras_reabrir(p_grupo text, p_desde date, p_hasta date)
returns integer
language plpgsql
set search_path to 'public'
as $fn$
declare
  v_dia record;
  v_n   integer := 0;
begin
  if p_grupo not in ('planilla','prueba','rxh','no_trabajador','practicante') then
    raise exception 'Grupo inválido: %. Los válidos son planilla, prueba, rxh, no_trabajador, practicante.', p_grupo;
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'El rango de fechas no es válido (desde %, hasta %).', p_desde, p_hasta;
  end if;

  -- ── 1 · ¿Sigue pagado para alguien? Entonces no se hace NADA ─────────────────
  -- `fn_recalcular_jornada` sale en silencio por su candado: el bucle de abajo
  -- «funcionaría» sin cambiar una sola jornada, con toda la pinta de estar bien.
  -- Es la misma trampa que `fn_revertir_pago` documenta sobre su propio orden.
  select d.persona_id, d.fecha into v_dia
  from (
    select distinct m.persona_id,
           coalesce(m.fecha_jornada, (m.timestamp_marca at time zone 'America/Lima')::date) as fecha
    from marcajes m
    join personas p on p.id = m.persona_id
    where p.tipo_vinculo = p_grupo
      and coalesce(m.fecha_jornada, (m.timestamp_marca at time zone 'America/Lima')::date)
          between p_desde and p_hasta
  ) d
  where fn_fecha_en_periodo_pagado(d.fecha, d.persona_id)
  order by d.fecha, d.persona_id
  limit 1;

  if found then
    raise exception 'El grupo % sigue pagado el %: reabre el pago (Planilla → Revertir pago) antes de reparar. No se cambió nada.', p_grupo, v_dia.fecha;
  end if;

  -- ── 2 · Recalcular y re-evaluar el sello, día por día ───────────────────────
  -- Sin filtrar por `anulada_at`, igual que fn_revertir_pago: un día cuyas marcas
  -- se anularon todas SÍ tuvo marcas y su jornada, derivada, le toca desaparecer.
  -- Solo días CON marcas: un día sin ninguna es historia cargada a mano y
  -- recalcularlo la borraría.
  for v_dia in
    select distinct m.persona_id,
           coalesce(m.fecha_jornada, (m.timestamp_marca at time zone 'America/Lima')::date) as fecha
    from marcajes m
    join personas p on p.id = m.persona_id
    where p.tipo_vinculo = p_grupo
      and coalesce(m.fecha_jornada, (m.timestamp_marca at time zone 'America/Lima')::date)
          between p_desde and p_hasta
    order by 2, 1
  loop
    perform fn_recalcular_jornada(v_dia.persona_id, v_dia.fecha);
    perform fn_resellar_dia(v_dia.persona_id, v_dia.fecha);
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$fn$;

revoke execute on function fn_reparar_dias_tras_reabrir(text, date, date) from public, anon, authenticated;

comment on function fn_reparar_dias_tras_reabrir(text, date, date) is
  '0545 — Recalcula la jornada y re-evalúa el sello de cada día con marcas de un grupo en un rango. Para después de reabrir un pago, porque fn_revertir_pago (0323) no recalcula cuando el periodo entero seguía abierto. Se niega si algún día sigue pagado. Solo para quien pega SQL: no se expone al cliente.';

-- ── El incidente del 2026-10-21 ───────────────────────────────────────────────
-- Si el grupo aún no se reabrió, esto falla con un mensaje que dice qué hacer y
-- NO deja nada a medias (ni siquiera la función de arriba, si se pega todo junto).
select fn_reparar_dias_tras_reabrir(
  'planilla', date '2026-10-21', (now() at time zone 'America/Lima')::date
) as dias_recalculados;

insert into migraciones_aplicadas (numero, nombre)
values (545, 'reabrir_un_grupo_pagado_repara_sus_horas')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación (las dos tienen que dar 0) ──────────────────────────────────
-- 1 · jornadas de planilla desde el 21-oct que siguen abiertas teniendo una
--     salida real marcada: el síntoma exacto del incidente.
-- 2 · marcas selladas de planilla desde el 21-oct cuyo día SÍ cuadra: el sello
--     que nunca debió ponerse. (Un día realmente roto puede seguir sellado, y
--     eso es correcto: no se cuenta aquí.)
select
  (select count(*)
     from jornadas j
     join personas p on p.id = j.persona_id
    where p.tipo_vinculo = 'planilla'
      and j.fecha >= date '2026-10-21'
      and j.estado in ('abierta', 'en_pausa')
      and exists (select 1 from marcajes m
                   where m.persona_id = j.persona_id and m.tipo = 'salida_final'
                     and m.anulada_at is null
                     and (m.timestamp_marca at time zone 'America/Lima')::date = j.fecha)
  ) as jornadas_abiertas_con_salida_real,
  (select count(*)
     from marcajes m
     join personas p on p.id = m.persona_id
    where p.tipo_vinculo = 'planilla'
      and (m.timestamp_marca at time zone 'America/Lima')::date >= date '2026-10-21'
      and m.estado_revision = 'pendiente_revision'
      and m.anulada_at is null
      and m.origen <> 'auto_cierre'
      and not fn_dia_incoherente(m.persona_id, (m.timestamp_marca at time zone 'America/Lima')::date)
  ) as sellos_en_dias_que_cuadran;
