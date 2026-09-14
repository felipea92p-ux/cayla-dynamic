-- ============================================================================
-- 0438 — Levantar una tardanza no pisa un expediente disciplinario ya formal
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: la hermana de la 0437, en la dirección contraria. Aplica el
-- mismo candado —fn_dia_con_expediente_formal— a fn_levantar_tardanza y a
-- fn_quitar_levantamiento: ninguna de las dos deja tocar el perdón de una
-- tardanza cuando ya existe, para esa fecha, un expediente disciplinario
-- FIRMADO o ENTREGADO.
--
-- La 0437 evitaba que un marcaje se corrigiera después de sancionarlo. Esta
-- evita el error simétrico: perdonar (o dejar de perdonar) una tardanza sobre
-- la que ya hay una decisión disciplinaria formal tomada con la información
-- de ese momento. Perdonarla después deja al expediente sancionando algo que
-- el sistema acaba de excusar; quitarle el perdón después deja contando una
-- tardanza sobre la que ya se decidió, con otra información, que no contaba.
-- Auditoría de la pantalla de Correcciones (2026-09-14): encontrado al revisar
-- el link «quitar» que aparece junto a una tardanza levantada.
--
-- QUÉ ASUME:
--   · fn_dia_con_expediente_formal(persona_id, fecha) ya existe (0437) y ya
--     resuelve exactamente esta pregunta — se reusa tal cual, sin cambiarla.
--   · fn_levantar_tardanza guarda por FECHA (tardanzas_justificadas.fecha),
--     no por jornada: no hay cruce de medianoche que considerar aquí, a
--     diferencia de las cinco funciones de la 0437. Se compara p_fecha
--     directo, sin pasar por fn_fecha_de_jornada.
--   · El candado se aplica a las DOS funciones, no solo a levantar: quitar un
--     levantamiento existente es la misma clase de cambio (altera qué cuenta
--     para disciplina) en la dirección contraria, y el mismo argumento de la
--     0437 aplica igual: un aviso que se puede ignorar no es una garantía,
--     así que se bloquea, no se avisa.
--
-- QUÉ NO CAMBIA: la firma de las dos funciones (mismos argumentos), el resto
-- de su cuerpo —incluido el `on conflict ... do update` de fn_levantar_
-- tardanza, intacto—, y fn_calcular_bono_puntualidad, que no se toca: sigue
-- leyendo tardanzas_justificadas exactamente igual. Cuerpo de partida
-- verificado con donde-vive.sh el 2026-09-14 contra 0053_levantar_
-- tardanza.sql (única definición vigente en las dos).
--
-- SE REVIERTE: `create or replace` de las dos funciones con el cuerpo que
-- trae 0053_levantar_tardanza.sql.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_levantar_tardanza(
  p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text default null)
returns void language plpgsql security definer set search_path = public as $L$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if p_motivo is null or p_motivo not in ('fuerza_mayor','salud','transporte','otro') then
    raise exception 'Motivo inválido.';
  end if;
  if p_motivo = 'otro' and (p_observacion is null or length(trim(p_observacion)) < 3) then
    raise exception 'Para el motivo "otro" la observación es obligatoria.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0438 ⇩⇩⇩ NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL.
  if fn_dia_con_expediente_formal(p_persona_id, p_fecha) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado que cuenta esta tardanza entre sus hechos: perdonarla ahora dejaría al expediente sancionando algo que el sistema acaba de excusar. Resuelve o anula el expediente en Disciplina antes de levantar esta tardanza.';
  end if;

  insert into tardanzas_justificadas (persona_id, fecha, motivo, observacion, creado_por)
  values (p_persona_id, p_fecha, p_motivo, nullif(trim(coalesce(p_observacion,'')),''), v_editor)
  on conflict (persona_id, fecha)
  do update set motivo = excluded.motivo, observacion = excluded.observacion,
                creado_por = excluded.creado_por, creado_at = now();
end;
$L$;

CREATE OR REPLACE FUNCTION public.fn_quitar_levantamiento(p_persona_id uuid, p_fecha date)
returns void language plpgsql security definer set search_path = public as $L$
begin
  perform fn_verificar_corrector(p_persona_id);

  -- ⇩⇩⇩ CAMBIO 0438 ⇩⇩⇩ NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL.
  if fn_dia_con_expediente_formal(p_persona_id, p_fecha) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado: quitar el perdón volvería a contar una tardanza sobre la que ya hay una decisión formal tomada sabiendo que estaba perdonada. Resuelve o anula el expediente en Disciplina antes de quitar este levantamiento.';
  end if;

  delete from tardanzas_justificadas where persona_id = p_persona_id and fecha = p_fecha;
end;
$L$;

insert into migraciones_aplicadas (numero, nombre) values (438, 'levantar_una_tardanza_no_pisa_un_expediente_ya_formal')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  p.proname,
  position('CAMBIO 0438' in p.prosrc) > 0 as tiene_el_candado,
  (select count(*) from pg_proc pp where pp.proname = p.proname) as una_sola_version
from pg_proc p
where p.proname in ('fn_levantar_tardanza', 'fn_quitar_levantamiento')
order by p.proname;
