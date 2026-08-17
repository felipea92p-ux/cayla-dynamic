-- ============================================================================
-- 0266 — Una comunicación de cargos ya ocurrida se puede declarar
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que se pueda registrar una comunicación de cargos que YA OCURRIÓ, con la
-- fecha en que ocurrió, en vez de obligar a repetirla para que el sistema la
-- vea. Si el plazo de descargo que arrancó ese día ya venció, la sanción se
-- puede firmar hoy mismo.
--
-- ── POR QUÉ HACE FALTA ──────────────────────────────────────────────────────
--
-- `fn_expediente_comunicar_cargos` estampa `now()`. Es lo correcto cuando la
-- comunicación se hace en ese momento, y era la única forma posible mientras
-- la pantalla no tuvo botón para hacerlo — cosa que ocurrió entre el 11 y el
-- 17 de agosto de 2026: la base exigía el paso desde la 0212 y el panel nunca
-- lo ofreció.
--
-- El resultado es un expediente que dice «cargos sin comunicar» sobre una
-- persona a la que sí se le comunicaron. Con solo `now()` disponible, la única
-- salida era volver a comunicárselo y esperar dos días hábiles otra vez: dos
-- días de plazo para un descargo que la persona ya tuvo ocasión de dar.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE, Y ES LO QUE LA HACE ACEPTABLE ────────────
--
-- No abre la firma. Los tres candados del art. 55.2 y del 19.3 siguen
-- exactamente donde estaban en `fn_expediente_firmar`:
--
--   · sin cargos comunicados no se firma,
--   · antes de que venza el plazo no se firma,
--   · sin valorar el descargo por escrito no se firma.
--
-- Lo único que cambia es DE DÓNDE SALE LA FECHA: antes solo podía ser el reloj;
-- ahora puede ser una fecha pasada que alguien declara y firma con su nombre.
-- Un plazo declarado que todavía no venció sigue frenando la firma igual.
--
-- Tampoco inventa una constancia. Deja escrito en el expediente quién declaró
-- la comunicación, qué día dice que ocurrió y cómo consta — y ese texto viaja
-- al legajo. Una comunicación verbal declarada así es más débil que un cargo
-- firmado, y el expediente lo va a decir con esas palabras en vez de aparentar
-- un trámite documentado que no existió.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que la fecha declarada no es futura. Se declara lo ocurrido.
--   · Que no es anterior a los hechos imputados: no se pueden haber comunicado
--     unos cargos antes de que existieran los hechos que los sostienen.
--   · Que quien declara escribe CÓMO consta. Se exige texto con sustancia (15
--     caracteres) por lo mismo que el art. 19.3 exige motivar un descargo no
--     acogido: «se le dijo» sin decir quién, dónde ni delante de quién no
--     sirve el día que alguien lo discuta.
--   · Que se declara UNA vez. Si la fecha salió mal, el camino es anular el
--     borrador y generar otro — igual que con `fn_expediente_comunicar_cargos`,
--     donde el plazo tampoco se reabre.
--   · Que el numeral 60.5 sigue mandando: si no consta la entrega del
--     Reglamento, esto no destraba nada, porque la sanción no se va a poder
--     fundar igual.
--
-- ── POR QUÉ UNA FUNCIÓN NUEVA Y NO UN PARÁMETRO MÁS ─────────────────────────
--
-- Porque son dos actos distintos y conviene que se lean distinto en el código
-- y en el expediente: uno comunica hoy, el otro declara lo que pasó antes. Y
-- porque tocar `fn_expediente_comunicar_cargos` obligaría a reescribir una
-- función viva —con su md5 de partida y el riesgo de revertir en silencio el
-- guard que la 0228 le puso encima— para un caso que es la excepción.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   drop function if exists fn_expediente_declarar_cargos_comunicados(
--     uuid, timestamptz, text, integer);
--
-- No toca datos ni ninguna otra función. Lo ya declarado se queda como está,
-- que es lo que se quiere: es un hecho registrado, no una configuración.
-- ============================================================================

create or replace function fn_expediente_declarar_cargos_comunicados(
  p_id         uuid,
  p_fecha      timestamptz,
  p_constancia text,
  p_dias       integer default 2
)
returns timestamptz
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_doc    record;
  v_vence  timestamptz;
  v_falta  text;
  v_quien  text;
begin
  select * into v_doc from expediente_disciplinario where id = p_id;
  if not found then raise exception 'Ese documento no existe.'; end if;

  if fn_expediente_puede_actuar(v_doc.persona_id, v_doc.nivel) is not true then
    raise exception 'Sin permiso para actuar sobre este documento.';
  end if;

  if v_doc.estado <> 'borrador' then
    raise exception 'Los cargos se declaran mientras el documento es borrador; este está %.', v_doc.estado;
  end if;

  if v_doc.nivel not in ('amonestacion', 'suspension') then
    raise exception 'Este acto es para la amonestación y la suspensión. La imputación y el despido siguen el procedimiento del artículo 57.';
  end if;

  if v_doc.cargos_comunicados_at is not null then
    raise exception 'Los cargos ya constan comunicados el %. El plazo no se reabre.',
      to_char(v_doc.cargos_comunicados_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI');
  end if;

  -- NUMERAL 60.5, igual que en fn_expediente_comunicar_cargos: sin constancia
  -- del Reglamento la sanción no se va a poder fundar, así que declarar una
  -- comunicación no destraba nada y el freno tiene que llegar acá.
  v_falta := fn_reglamento_no_acusado(
    v_doc.persona_id, coalesce(v_doc.periodo_hasta, v_doc.periodo_desde, fn_hoy_lima()));
  if v_falta is not null then raise exception '%', v_falta; end if;

  if p_fecha is null then
    raise exception 'Falta el día en que se le comunicaron los cargos.';
  end if;

  -- Se declara lo ocurrido, no lo que va a ocurrir. Sin esto, una fecha futura
  -- adelantaría el vencimiento del plazo y firmaría antes de tiempo.
  if p_fecha > now() then
    raise exception 'Esa fecha todavía no llega. Se declara una comunicación ya ocurrida.';
  end if;

  -- Unos cargos no pueden haberse comunicado antes de que existieran los hechos
  -- que los sostienen.
  if p_fecha::date < coalesce(v_doc.periodo_hasta, v_doc.periodo_desde, p_fecha::date) then
    raise exception 'Los hechos imputados llegan hasta el %, y esa comunicación sería anterior.',
      to_char(coalesce(v_doc.periodo_hasta, v_doc.periodo_desde), 'DD/MM/YYYY');
  end if;

  if p_constancia is null or length(btrim(p_constancia)) < 15 then
    raise exception 'Escribe cómo consta esa comunicación: quién se la hizo, cuándo y delante de quién. Es lo que se lee el día que alguien la discuta.';
  end if;

  -- El Reglamento dice «no menor de dos»: se puede haber dado más, nunca menos.
  if p_dias < 2 then
    raise exception 'El plazo de descargo no puede ser menor de dos (2) días hábiles (art. 55.2 del RIT).';
  end if;

  v_vence := fn_sumar_dias_habiles(p_fecha, p_dias);

  select nombres || ' ' || apellidos into v_quien
  from personas where id = fn_persona_actual_id();

  update expediente_disciplinario
     set cargos_comunicados_at = p_fecha,
         descargo_vence_at     = v_vence,
         observacion = coalesce(observacion || E'\n', '') ||
                       'Comunicación de cargos DECLARADA el ' ||
                       to_char(now() at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI') ||
                       ' por ' || coalesce(v_quien, 'el sistema') ||
                       ': ocurrió el ' ||
                       to_char(p_fecha at time zone 'America/Lima', 'DD/MM/YYYY') ||
                       '. ' || btrim(p_constancia)
   where id = p_id;

  return v_vence;
end;
$fn$;

comment on function fn_expediente_declarar_cargos_comunicados(uuid, timestamptz, text, integer) is
  'Registra una comunicación de cargos ya ocurrida con su fecha real y deja escrito quién la declara y cómo consta (art. 55.2 del RIT). No levanta ninguno de los candados de fn_expediente_firmar.';

grant  execute on function fn_expediente_declarar_cargos_comunicados(uuid, timestamptz, text, integer) to authenticated, service_role;
revoke execute on function fn_expediente_declarar_cargos_comunicados(uuid, timestamptz, text, integer) from public, anon;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (266, 'una_comunicacion_de_cargos_ya_ocurrida_se_puede_declarar')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
--
-- La primera debe decir true. La segunda es un NÚMERO: cuántos borradores de
-- amonestación o suspensión están esperando este paso ahora mismo.
select
  to_regprocedure('public.fn_expediente_declarar_cargos_comunicados(uuid,timestamptz,text,integer)')
    is not null                                                    as la_funcion_existe,
  (select count(*) from expediente_disciplinario
    where estado = 'borrador'
      and nivel in ('amonestacion', 'suspension')
      and cargos_comunicados_at is null)                           as borradores_esperando_este_paso;
