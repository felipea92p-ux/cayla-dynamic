-- ============================================================================
-- 0541 — Levantar (o quitar) una tardanza deja rastro en el historial
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que perdonar una tardanza, y dejar de perdonarla, quede escrito
-- en `correcciones_auditoria` con quién lo hizo, cuándo, de qué día y por qué
-- motivo. Es lo que lee el «Historial de correcciones» de la pantalla de
-- Correcciones y el «Mis cambios» de la persona.
--
-- EL DEFECTO. `fn_levantar_tardanza` y `fn_quitar_levantamiento` (0053, 0438)
-- solo tocaban `tardanzas_justificadas`. Ninguna escribía en el libro de
-- correcciones, así que un levantamiento NUNCA aparecía en el historial: se
-- veía en el día (la hora tachada), pero no en el rastro. Lo descubrió quien
-- levantó su propia tardanza y no la encontró en el historial, mientras que
-- la salida que le corrigió a otro colaborador sí aparecía. Y peor: quitar un
-- levantamiento hace `delete`, sin dejar ni la fila — no quedaba ninguna prueba
-- de que alguna vez se hubiera perdonado.
-- Importa porque un levantamiento decide si una tardanza cuenta para la
-- escalera disciplinaria y para el umbral del mes (D.S. 003-97-TR art. 25: la
-- sanción progresiva exige que el rastro se pueda reconstruir).
--
-- QUÉ ESCRIBE (dos campos nuevos; los clasifica packages/shared/src/auditoria.ts):
--   · tardanza_levantada            valor_anterior = día perdonado (AAAA-MM-DD)
--                                   valor_nuevo    = motivo (fuerza_mayor, …)
--   · tardanza_levantamiento_quitado valor_anterior = día (AAAA-MM-DD)
--                                   valor_nuevo    = motivo que tenía el perdón
-- `motivo` (obligatorio, ≥ 3) lleva la observación de quien lo hizo; si no hay,
-- una frase con el motivo, para que el historial nunca diga «“”».
--
-- QUÉ ASUME: fn_verificar_corrector (0010) y fn_dia_con_expediente_formal
-- (0437) existen y no se tocan. `correcciones_auditoria` solo se escribe desde
-- funciones SECURITY DEFINER (0508): ambas lo son.
--
-- QUÉ NO CAMBIA: las firmas, los candados de la 0438 (motivo válido, «otro»
-- exige observación, expediente formal), el `on conflict … do update` de
-- levantar, y que quitar un levantamiento que no existe es un no-hacer-nada
-- (ahora tampoco deja rastro, porque no pasó nada). Todo ocurre en UNA
-- transacción: o queda el cambio y su rastro, o ninguno.
--
-- MD5 DE PARTIDA (pedido a PRODUCCIÓN el 2026-10-20, antes de escribir):
--   fn_levantar_tardanza    a358f877ceef2a45258e343ba482a232  (1218 car.)
--   fn_quitar_levantamiento 6a03674ab1f775af3ee1739e2d2c82e0  (592 car.)
-- Coinciden con 0438_levantar_una_tardanza_no_pisa_un_expediente_ya_formal.sql.
--
-- RELLENO. Los levantamientos que ya existen se copian al libro con su fecha de
-- creación y su autor (`creado_at`, `creado_por`), una sola vez (idempotente).
-- Los que alguien ya quitó con `delete` no dejaron nada y NO se pueden
-- reconstruir: el historial empieza a contarlos desde hoy.
--
-- SE REVIERTE: `create or replace` de las dos funciones con el cuerpo de la 0438
-- (y, si se quiere, `delete from correcciones_auditoria where campo_modificado
-- in ('tardanza_levantada','tardanza_levantamiento_quitado')`).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_levantar_tardanza(
  p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text default null)
returns void language plpgsql security definer set search_path = public as $L$
declare
  v_editor uuid;
  v_obs text;
  v_previo text;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if p_motivo is null or p_motivo not in ('fuerza_mayor','salud','transporte','otro') then
    raise exception 'Motivo inválido.';
  end if;
  if p_motivo = 'otro' and (p_observacion is null or length(trim(p_observacion)) < 3) then
    raise exception 'Para el motivo "otro" la observación es obligatoria.';
  end if;

  -- NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL (0438).
  if fn_dia_con_expediente_formal(p_persona_id, p_fecha) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado que cuenta esta tardanza entre sus hechos: perdonarla ahora dejaría al expediente sancionando algo que el sistema acaba de excusar. Resuelve o anula el expediente en Disciplina antes de levantar esta tardanza.';
  end if;

  v_obs := nullif(trim(coalesce(p_observacion,'')),'');
  -- ⇩⇩⇩ CAMBIO 0541 ⇩⇩⇩ si ya estaba perdonada, el rastro lo dice.
  select motivo into v_previo from tardanzas_justificadas
   where persona_id = p_persona_id and fecha = p_fecha;

  insert into tardanzas_justificadas (persona_id, fecha, motivo, observacion, creado_por)
  values (p_persona_id, p_fecha, p_motivo, v_obs, v_editor)
  on conflict (persona_id, fecha)
  do update set motivo = excluded.motivo, observacion = excluded.observacion,
                creado_por = excluded.creado_por, creado_at = now();

  -- ⇩⇩⇩ CAMBIO 0541 ⇩⇩⇩ el rastro, en la misma transacción.
  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (
    p_persona_id, 'tardanza_levantada', p_fecha::text, p_motivo, v_editor,
    case when v_previo is not null then 'Cambió el motivo del perdón (antes: ' || replace(v_previo, '_', ' ') || '). ' else '' end
    || coalesce(v_obs, 'Tardanza levantada por ' || replace(p_motivo, '_', ' '))
  );
end;
$L$;

CREATE OR REPLACE FUNCTION public.fn_quitar_levantamiento(p_persona_id uuid, p_fecha date)
returns void language plpgsql security definer set search_path = public as $L$
declare
  v_editor uuid;
  v_previo record;
begin
  v_editor := fn_verificar_corrector(p_persona_id);

  -- NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL (0438).
  if fn_dia_con_expediente_formal(p_persona_id, p_fecha) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado: quitar el perdón volvería a contar una tardanza sobre la que ya hay una decisión formal tomada sabiendo que estaba perdonada. Resuelve o anula el expediente en Disciplina antes de quitar este levantamiento.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0541 ⇩⇩⇩ borrar y dejar rastro en una sola unidad.
  delete from tardanzas_justificadas where persona_id = p_persona_id and fecha = p_fecha
  returning motivo, observacion into v_previo;

  if found then
    insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (
      p_persona_id, 'tardanza_levantamiento_quitado', p_fecha::text, v_previo.motivo, v_editor,
      'Se quitó el perdón de la tardanza (tenía: ' || replace(v_previo.motivo, '_', ' ')
      || coalesce(' — ' || v_previo.observacion, '') || ')'
    );
  end if;
end;
$L$;

-- Los perdones que ya existen entran al libro, una sola vez.
insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, corregido_at, motivo)
select t.persona_id, 'tardanza_levantada', t.fecha::text, t.motivo, t.creado_por, t.creado_at,
       coalesce(nullif(trim(coalesce(t.observacion,'')),''), 'Tardanza levantada por ' || replace(t.motivo, '_', ' '))
  from tardanzas_justificadas t
 where not exists (
   select 1 from correcciones_auditoria a
    where a.persona_id = t.persona_id
      and a.campo_modificado = 'tardanza_levantada'
      and a.valor_anterior = t.fecha::text
 );

insert into migraciones_aplicadas (numero, nombre) values (541, 'levantar_una_tardanza_deja_rastro_en_el_historial')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
