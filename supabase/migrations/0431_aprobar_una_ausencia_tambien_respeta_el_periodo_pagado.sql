-- ============================================================================
-- 0431 — Aprobar una ausencia también respeta el periodo pagado
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE
--   `fn_aprobar_ausencia` deja de poder aprobar (y por tanto devengar) una
--   ausencia cuyas fechas caen en un periodo de planilla ya pagado — mismo
--   candado que ya llevan sus dos hermanas, `fn_registrar_ausencia` y
--   `fn_anular_ausencia` (0327), copiado literal para que las tres respondan
--   igual a la misma pregunta.
--
-- QUÉ ASUME
--   md5 de partida de `fn_aprobar_ausencia` (0101, sin cambios desde
--   entonces): e10c71925cd60498dcc45a4add2d61be — confirmado en el Postgres
--   local antes de escribir esta migración con
--     select md5(prosrc) from pg_proc where proname = 'fn_aprobar_ausencia';
--   Se pide a PRODUCCIÓN otra vez antes de pegar (ver CLAUDE.md).
--
-- POR QUÉ SE ELIGIÓ ASÍ
--   `fn_planilla_calcular` solo paga descanso médico/maternidad/licencia con
--   goce cuando `aprobada_at is not null` (regla de la 0306). El escenario
--   real: se registra la ausencia a mitad de periodo (fn_registrar_ausencia
--   SÍ la deja pasar, porque en ese momento el periodo está abierto), el
--   periodo se congela antes de que Desarrollo Organizacional la apruebe, y
--   DO aprueba días o semanas después — sin ningún aviso ni bloqueo. La
--   persona queda cobrando S/0.00 por un beneficio de ley (Ley 26790, D. Leg.
--   713 art. 14) hasta que alguien note la discrepancia a mano y corra
--   `fn_repagar_periodo`. Documentado en la auditoría de arquitectura del
--   2026-09-03 (ver docs/hallazgos-abiertos.md), confirmado sin cambios el
--   2026-09-12: `fn_registrar_ausencia` y `fn_anular_ausencia` sí llevan el
--   candado desde la 0327 (adaptado al modelo de `periodo_grupo_pago` de la
--   0323); `fn_aprobar_ausencia` seguía en el cuerpo de la 0101, sin él.
--
--   El candado se copia literal del cuerpo vigente de `fn_registrar_ausencia`
--   (0327) y no se reescribe: son la misma pregunta —¿estas fechas caen en un
--   periodo ya pagado, del grupo de esta persona?— y una tercera redacción
--   sería la tercera copia de una regla que ya se aprendió a no duplicar.
--
-- CÓMO SE REVIERTE
--   `create or replace function fn_aprobar_ausencia` con el cuerpo de la
--   0101 (sin el bloque `-- CAMBIO 0431`).
-- ============================================================================

create or replace function fn_aprobar_ausencia(p_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_a ausencias%rowtype;
begin
  -- La aprobación es de DO, no de la sede: es lo único que convierte días en
  -- plata, y por eso no la puede dar quien la registró desde la tienda.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede aprobar una ausencia remunerada.';
  end if;

  select * into v_a from ausencias where id = p_id;
  if not found then raise exception 'Esa ausencia ya no existe.'; end if;
  if v_a.anulada_at is not null then raise exception 'Esa ausencia está anulada.'; end if;
  if v_a.aprobada_at is not null then raise exception 'Esa ausencia ya estaba aprobada.'; end if;

  -- CAMBIO 0431 · copiado literal de `fn_registrar_ausencia` (0327): aprobar
  -- es la tercera puerta que convierte esta ausencia en dinero, y era la
  -- única de las tres sin este candado.
  if exists (
    select 1 from periodos_planilla pp
    where daterange(pp.fecha_ini, pp.fecha_fin, '[]') && daterange(v_a.fecha_inicio, v_a.fecha_fin, '[]')
      and (
        -- Compatibilidad: un periodo con estado='pagado' pero SIN ninguna fila
        -- en periodo_grupo_pago es de antes de la 0323 (el bucket único de
        -- siempre) — se sigue leyendo por el agregado.
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
        -- El caso normal desde la 0323: el GRUPO de esta persona, no el
        -- periodo entero.
        exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = v_a.persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
    for share
  ) then
    raise exception 'Esas fechas caen en un periodo de planilla ya PAGADO. Reabre el periodo primero.';
  end if;

  update ausencias set aprobada_por = fn_persona_actual_id(), aprobada_at = now() where id = p_id;
end;
$fn$;

insert into migraciones_aplicadas (numero, nombre)
values (431, 'aprobar_una_ausencia_tambien_respeta_el_periodo_pagado')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
