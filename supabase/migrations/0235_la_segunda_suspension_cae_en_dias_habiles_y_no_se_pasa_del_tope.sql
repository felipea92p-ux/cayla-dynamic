-- ============================================================================
-- 0235 — La segunda suspensión cae en días laborables y no se pasa del tope
-- ============================================================================
--
-- QUÉ ARREGLA
--
-- Cuatro defectos de la 0232, todos reproducidos de punta a punta contra la
-- base antes de escribir una línea de esto. Dos de ellos emiten documentos que
-- incumplen el Reglamento en su propia parte resolutiva.
--
-- ── 1 · LA SUSPENSIÓN DE VARIOS DÍAS PISABA LOS DESCANSOS ───────────────────
--
-- El generador escribía `suspension_desde = hoy + 1` y `suspension_hasta =
-- hoy + días`: días de CALENDARIO. Y dejaba `suspension_fechas` en nulo, sin
-- pasar por `fn_dias_suspension`, que existe desde la 0075 y sí salta domingos,
-- feriados y descanso vacacional.
--
-- Medido: una suspensión de tres días generada el miércoles 12-08-2026 para
-- alguien de lunes a viernes quedaba del 13 al 15, y el 15 es sábado. El memo
-- imprimía «SUSPENSIÓN por 3 día(s), del 13 al 15»: declaraba tres días de
-- castigo y ejecutaba dos.
--
-- Antes de la 0232 el daño estaba acotado porque toda suspensión salía de UN
-- día: pisar un descanso era uno de cada siete y no había discrepancia entre lo
-- declarado y lo cumplido. La 0232 hizo normales los rangos de dos y tres días,
-- y con ellos el defecto.
--
-- Reglas comunes a los literales c) y d) del artículo 19, repetidas en el 54.5:
-- la suspensión «no puede fijarse sobre días de descanso semanal, feriados ni
-- descanso vacacional», y se comunica «indicando los hechos, los días concretos
-- en que se cumplirá».
--
-- ── 2 · CON LA PRIMERA EN TRES DÍAS, LA SEGUNDA NO PODÍA SER MAYOR ──────────
--
-- La fórmula `greatest(2, least(3, previa + 1))` satura en tres y nunca
-- comprobaba que el resultado superase a la previa. Medido: previa 1 → 2 ✓,
-- previa 2 → 3 ✓, previa 3 → 3 ✗, previa 5 → 3 ✗.
--
-- El numeral 19.2 c) topa la primera suspensión en dos días justamente para que
-- quepa una segunda mayor dentro del tope de tres del 54.5. Pero nada lo impone
-- en la base: el panel ofrece un campo de 1 a 15 y `fn_expediente_set_suspension`
-- lo acepta sin objetar.
--
-- Ahora el generador SE NIEGA en vez de emitir. Un documento que invoca el
-- 19.2 d) incumpliéndolo en su parte resolutiva no sirve como sanción previa
-- del literal h) del artículo 25 de la LPCL: sale peor que no emitirlo.
--
-- ── 3 · LO QUE LA REVISIÓN PIDIÓ Y NO SE HIZO ──────────────────────────────
--
-- Propuso exigirle a la imputación una suspensión vigente, porque el numeral
-- 19.2 e) condiciona sus dos supuestos a que la segunda suspensión lo esté. Con
-- una imputación archivada y una amonestación posterior, decía, corresponde la
-- primera suspensión.
--
-- Se implementó y la prueba 160 lo tumbó: fija que una imputación RESUELTA «no
-- baja de la escalera», y con esa exigencia quien fue imputado y después
-- archivado volvía a empezar por abajo — un hecho nuevo lo mandaba a
-- amonestación en vez de dejarlo donde estaba.
--
-- Se deshizo. Un principio con prueba pesa más que una lectura defendible sin
-- ella, y esta última obligaba además a distinguir el archivo con sanción menor
-- del archivo sin sanción, que es otra discusión.
--
-- ── 4 · EL ACTA DE LLAMADA VERBAL MOVÍA EL CORTE ────────────────────────────
--
-- `corte` sale de `max(periodo_hasta)` sobre los documentos vigentes, y ahí
-- entraban también las actas de llamada de atención verbal. Un acta entregada
-- ayer que cubría hasta el 5 de agosto empujaba el corte y se tragaba las
-- tardanzas anteriores a esa fecha.
--
-- El literal a) del numeral 19.2 no deja lugar a dudas: el acta «no es sanción,
-- no constituye antecedente agravante y no es peldaño previo de los literales
-- b), c), d) ni e); SU EMISIÓN O SU OMISIÓN NO ALTERA NINGÚN CÓMPUTO».
--
-- Así que sale de la cuenta entera, no solo del corte.
--
-- ── 5 · Y LA TERCERA SUSPENSIÓN QUE NO EXISTE ──────────────────────────────
--
-- Con una suspensión caducada y otra vigente, la 0232 proponía otra suspensión:
-- `n_susp` contaba solo vigentes, valía 1, y la rama de la segunda se disparaba
-- otra vez. La escala del artículo 19.2 tiene DOS peldaños de suspensión, no
-- tres, y así la imputación no llegaba nunca mientras las viejas fueran
-- caducando.
--
-- Se decide a propósito, que es lo que faltaba: el ESCALÓN se mide por lo
-- vigente —artículo 56— pero nunca se propone una tercera suspensión si en el
-- legajo constan ya dos notificadas, que es lo que el numeral 19.6 (i) exige
-- acreditar para el despido. Las dos reglas conviven: la vigencia decide si se
-- puede agravar, el legajo decide hasta dónde llega la escalera.
--
-- ── QUÉ NO SE TOCA ──────────────────────────────────────────────────────────
--
-- Los cuatro defectos que la revisión descartó por PREEXISTENTES, y que siguen
-- ahí: las tardanzas de un mes ya cerrado se pierden, la vigencia se mide
-- contra la hora del botón y no contra la fecha del hecho, y
-- `fn_expediente_entregar` acepta una fecha futura. No son de este cambio y
-- meterlos aquí mezclaría dos discusiones.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Restaurando las dos funciones de la 0232. No toca datos.
--
-- md5 de partida (pedirlos a PRODUCCIÓN, no al Postgres local):
--   fn_tardanza_escalon            9d149947922441414b2e863383ecfda0  (0232)
--   fn_expediente_generar_tardanza ba2612705be05463f4593aebbaf85f80  (0232)
-- ============================================================================

create or replace function fn_tardanza_escalon(p_persona_id uuid)
returns table(
  nivel_siguiente        text,
  minimo                 integer,
  corte                  date,
  doc_previo             uuid,
  bloqueado              boolean,
  suspension_previa_dias integer
)
language sql stable security definer set search_path = public as $$
  with docs as (
    select e.id, e.nivel, e.periodo_hasta, e.resuelto_at, e.entregado_at,
           e.suspension_dias,
           (e.entregado_at >= now() - interval '12 months') as vigente
    from expediente_disciplinario e
    where e.persona_id = p_persona_id
      and e.tipo_causal = 'tardanza'
      -- ART. 56: un documento firmado y NO entregado no está vigente, no agrava
      -- y no habilita el escalón siguiente. Los doce meses corren desde la
      -- ENTREGA, no desde la firma.
      and e.estado = 'entregado'
      -- ART. 19.2 a): el acta de llamada de atención verbal «no es sanción, no
      -- constituye antecedente agravante y no es peldaño previo de los literales
      -- b), c), d) ni e); su emisión o su omisión NO ALTERA NINGÚN CÓMPUTO».
      -- Estaba entrando en el corte y se tragaba las tardanzas anteriores a su
      -- periodo.
      and e.nivel <> 'verbal'
  ),
  vig as (select * from docs where vigente),
  cuenta as (
    -- El escalón NO se decide por «cuál fue el último documento» sino por CON
    -- QUÉ CUENTA la persona: es lo que dice el Reglamento y no depende de
    -- ningún orden (dos entregados el mismo día lo echaban a suertes).
    select
      count(*) filter (where nivel = 'imputacion')             as n_imp,
      count(*) filter (where nivel = 'suspension')             as n_susp,
      count(*) filter (where nivel = 'amonestacion')           as n_amon,
      max(suspension_dias) filter (where nivel = 'suspension') as dias_susp,
      bool_or(nivel = 'imputacion' and resuelto_at is null)    as imp_abierta,
      max(periodo_hasta)                                       as corte
    from vig
  ),
  legajo as (
    -- Cuántas suspensiones constan NOTIFICADAS, hayan caducado o no. El numeral
    -- 19.6 (i) las exige «notificadas y obrantes en el legajo» para el despido,
    -- y el legajo no caduca. Sirve solo para no proponer una tercera.
    select count(*) as n_susp from docs where nivel = 'suspension'
  ),
  ultimo as (
    select id from docs order by entregado_at desc, periodo_hasta desc, id desc limit 1
  )
  select
    case
      -- Una imputación vigente mantiene arriba de la escalera, resuelta o no.
      --
      -- La revisión propuso exigirle además una suspensión vigente, porque el
      -- 19.2 e) condiciona la imputación a que la segunda suspensión lo esté.
      -- Se probó y la prueba 160 lo tumbó: fija que una imputación RESUELTA «no
      -- baja de la escalera», y con esa exigencia quien fue imputado y
      -- archivado volvía a empezar por abajo. El principio probado pesa más que
      -- una lectura discutible, así que se queda como estaba.
      when c.n_imp > 0                                  then 'imputacion'
      when c.n_susp >= 2                                then 'imputacion'
      -- Y nunca una TERCERA: con dos ya notificadas en el legajo, la escalera
      -- se acabó y lo que sigue es la imputación.
      when c.n_susp = 1 and l.n_susp >= 2               then 'imputacion'
      when c.n_susp = 1                                 then 'suspension'
      when c.n_amon > 0                                 then 'suspension'
      else                                                   'amonestacion'
    end,
    case
      when c.imp_abierta                                then null::int
      when c.n_susp >= 1 or c.n_imp > 0                 then 1
      when c.n_amon > 0                                 then 2
      else                                                   3
    end,
    c.corte,
    (select id from ultimo),
    coalesce(c.imp_abierta, false),
    c.dias_susp::int
  from cuenta c cross join legajo l;
$$;

comment on function fn_tardanza_escalon(uuid) is
  'Art. 19.2 del RIT: que escalon toca y cuantas tardanzas exige. Cuatro escalones, dos peldanos de suspension como maximo, y el acta verbal no cuenta para nada.';

grant execute on function fn_tardanza_escalon(uuid) to authenticated, service_role;
revoke execute on function fn_tardanza_escalon(uuid) from public;

-- ── El generador ────────────────────────────────────────────────────────────
create or replace function fn_expediente_generar_tardanza(p_persona_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_esc       record;
  v_cutoff    date;
  v_n         int;
  v_hechos    jsonb;
  v_desde     date;
  v_hasta     date;
  v_dias      int;
  v_fechas    date[];
  v_id        uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de tardanza para esta persona.';
  end if;

  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de tardanza pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  select * into v_esc from fn_tardanza_escalon(p_persona_id);

  if v_esc.bloqueado then
    raise exception 'Ya hay una imputación de cargos vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
  end if;

  v_cutoff := coalesce(v_esc.corte, date '2000-01-01');

  -- tardanzas del MES en curso, POSTERIORES al cutoff, no levantadas (non bis in idem)
  select jsonb_agg(jsonb_build_object('fecha', fecha, 'minutos', minutos_tarde) order by fecha),
         count(*), min(fecha), max(fecha)
    into v_hechos, v_n, v_desde, v_hasta
  from (
    select j.fecha, j.minutos_tarde
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha >= greatest(date_trunc('month', fn_hoy_lima())::date, v_cutoff + 1)
      and j.fecha <= fn_hoy_lima()
      -- `fn_tardanza_es_medible` reemplaza al viejo `is not null`: el papel
      -- disciplinario NUNCA se arma con una medición dudosa.
      and fn_tardanza_es_medible(j.minutos_tarde) and j.minutos_tarde > 0
      and not exists (select 1 from tardanzas_justificadas tj
                      where tj.persona_id = p_persona_id and tj.fecha = j.fecha)
  ) t;
  v_n := coalesce(v_n, 0);

  if v_n < v_esc.minimo then
    raise exception '%', case v_esc.nivel_siguiente
      when 'imputacion' then 'No corresponde: no hay tardanzas nuevas tras la segunda suspensión.'
      when 'suspension' then format('Aún no corresponde suspensión: necesita %s tardanza(s) nueva(s) tras el documento anterior (lleva %s).', v_esc.minimo, v_n)
      else format('Aún no corresponde amonestación: necesita %s tardanzas en el mes (lleva %s).', v_esc.minimo, v_n)
    end;
  end if;

  -- ── Los días de la suspensión ─────────────────────────────────────────────
  if v_esc.nivel_siguiente = 'suspension' then
    if v_esc.suspension_previa_dias is null then
      -- Primera suspensión: un día. El numeral 19.2 c) admite hasta dos, y
      -- graduarla es de quien firma; el sistema propone el mínimo.
      v_dias := 1;
    elsif v_esc.suspension_previa_dias >= 3 then
      -- NUMERAL 19.2 d): la segunda es «en todo caso de mayor duración que la
      -- primera», y el 54.5 la topa en tres días. Con la primera ya en tres o
      -- más, las dos condiciones no se pueden cumplir a la vez.
      --
      -- Se para en vez de emitir. Un documento que invoca el 19.2 d) y lo
      -- incumple en su propia parte resolutiva no sirve como sanción previa del
      -- literal h) del artículo 25 de la LPCL: sale peor que no emitirlo.
      raise exception
        'La primera suspensión se registró con % días, y el numeral 19.2 c) la topa en dos. '
        'La segunda tiene que ser mayor y caber en el tope de tres del numeral 54.5, y con esa '
        'primera no hay ningún número que cumpla las dos cosas. Revisa la primera suspensión '
        'antes de seguir con la escalera.',
        v_esc.suspension_previa_dias;
    else
      v_dias := v_esc.suspension_previa_dias + 1;
    end if;
  end if;

  -- Los días CONCRETOS en que se cumple, saltando descanso semanal, feriados y
  -- vacaciones (`fn_dias_suspension`, migración 0075). Antes se escribía un
  -- rango de calendario y `suspension_fechas` quedaba en nulo: el memo declaraba
  -- tres días de castigo y la persona cumplía dos.
  if v_dias is not null then
    -- `fn_dias_suspension` necesita el horario para saber qué días son
    -- laborables, y se niega si no lo encuentra. El mensaje suyo habla de días
    -- laborables y deja al lector sin saber qué hacer, así que se traduce: en
    -- este sistema, quien no tiene horario tampoco debería tener tardanzas
    -- —«sin horario» es una de las exclusiones que se aplican ANTES de contar—,
    -- de modo que llegar aquí significa que falta el horario, no que sobre la
    -- suspensión.
    begin
      select array_agg(fecha order by fecha) into v_fechas
        from fn_dias_suspension(p_persona_id, fn_hoy_lima() + 1, v_dias);
    exception when others then
      raise exception
        'No puedo fijar los días de la suspensión: esta persona no tiene un horario vigente, '
        'y sin él no se sabe qué días son laborables. El numeral 54.5 exige comunicar «los días '
        'concretos en que se cumplirá», y no se pueden poner días de descanso. Asígnale su '
        'horario en Equipo y vuelve a intentarlo.';
    end;
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'tardanza', v_esc.nivel_siguiente, v_hechos, v_desde, v_hasta,
    v_esc.doc_previo,
    v_dias,
    -- Desde y hasta salen de los días reales, no de un rango de calendario.
    case when v_fechas is not null then v_fechas[1] end,
    case when v_fechas is not null then v_fechas[array_length(v_fechas, 1)] end,
    null);

  if v_fechas is not null then
    update expediente_disciplinario set suspension_fechas = v_fechas where id = v_id;
  end if;

  return v_id;
end;
$$;

grant  execute on function fn_expediente_generar_tardanza(uuid) to authenticated;
revoke execute on function fn_expediente_generar_tardanza(uuid) from public, anon;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (235, 'la_segunda_suspension_cae_en_dias_habiles_y_no_se_pasa_del_tope')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las cuatro deben decir true.
select
  (select prosrc ilike '%fn_dias_suspension%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_generar_tardanza')
                                                                as las_fechas_saltan_los_descansos,
  (select prosrc ilike '%suspension_previa_dias >= 3%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_generar_tardanza')
                                                                as se_niega_si_no_puede_ser_mayor,
  (select prosrc ilike '%e.nivel <> ''verbal''%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_tardanza_escalon')
                                                                as el_acta_verbal_no_cuenta,
  (select prosrc ilike '%l.n_susp >= 2%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_tardanza_escalon')
                                                                as nunca_hay_una_tercera_suspension;
