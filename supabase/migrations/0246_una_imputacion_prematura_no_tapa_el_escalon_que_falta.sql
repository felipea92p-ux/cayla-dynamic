-- ============================================================================
-- 0246 — Una imputación prematura no tapa el escalón que falta
-- ============================================================================
--
-- QUÉ ARREGLA
--
-- Que una imputación de cargos deje de mantener a alguien en el cuarto escalón
-- cuando la escalera de abajo está incompleta.
--
-- ── EL CASO REAL QUE LO DESTAPÓ ─────────────────────────────────────────────
--
-- Un expediente de tardanzas de la sede Arequipa, agosto de 2026: amonestación
-- entregada el 22 de julio, PRIMERA suspensión de un día el 30 de julio, e
-- imputación de cargos el 10 de agosto. Falta el literal d) — la segunda
-- suspensión. La emitió el sistema cuando todavía tenía tres escalones, antes
-- de la 0232.
--
-- El criterio recibido es que ese procedimiento debe cerrarse SIN despido y
-- resolverse con la segunda suspensión que falta. Se simuló contra la base, con
-- los tres documentos reales, y el sistema hacía lo contrario:
--
--     antes de resolver   → imputacion (bloqueado)
--     tras archivar        → imputacion            ← el escalón que falta, no
--
-- O sea: quien siguiera el botón emitiría una segunda imputación en vez de la
-- suspensión, perpetuando el defecto. Y el numeral 19.6 (i) exige para la
-- extinción «la amonestación escrita del literal b) y LAS DOS SUSPENSIONES sin
-- goce de haber de los literales c) y d), todas notificadas y obrantes en el
-- legajo»: con una sola, ese expediente no llega nunca a ningún sitio.
--
-- ── LA REGLA, Y POR QUÉ ESTA Y NO OTRA ──────────────────────────────────────
--
-- Una imputación mantiene arriba de la escalera SOLO SI la escalera de abajo
-- está completa. Con menos de dos suspensiones notificadas, lo que toca es la
-- suspensión que falta, haya habido imputación o no.
--
-- No es una lectura propia: es lo que dicen juntos el 19.2 e) —que condiciona
-- sus dos supuestos a que la SEGUNDA suspensión esté vigente— y el 19.6 (i).
--
-- ── POR QUÉ NO SE HIZO EN LA 0235, QUE YA LO TENÍA DELANTE ──────────────────
--
-- La revisión adversarial de la 0232 propuso exactamente esto. Se implementó y
-- la prueba 160 lo tumbó, así que se deshizo — y la marcha atrás fue demasiado
-- gruesa: se restauró «cualquier imputación mantiene arriba», sin condición.
--
-- Al mirar la semilla de esa prueba se ve por qué tumbaba el cambio: tiene una
-- imputación y una amonestación, y NINGUNA suspensión. Es la misma escalera
-- defectuosa del caso de Arequipa. Estaba comprobando el principio «de ahí no
-- se baja» sobre un caso en el que ese principio no debe aplicarse, porque esa
-- persona nunca debió ser imputada.
--
-- El principio se conserva y se prueba donde corresponde: con las dos
-- suspensiones en el legajo, una imputación resuelta NO baja de la escalera.
--
-- ── QUÉ NO CAMBIA ──────────────────────────────────────────────────────────
--
-- `bloqueado` sigue igual: una imputación SIN resolver frena todo y la decisión
-- es de Gerencia. Esto solo afecta a qué se propone DESPUÉS de resolverla.
--
-- Y no toca `fn_expediente_resolver`, que sigue admitiendo únicamente
-- «archivado» o «despido». Cerrar sin despido e imponer la suspensión en el
-- mismo acto es una sola resolución en el papel, pero dos registros en el
-- sistema, y unirlos es una decisión de producto que no toca tomar hoy.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Restaurando `fn_tardanza_escalon` de la 0235. No toca datos.
--
-- md5 de partida (pedirlo a PRODUCCIÓN, no al Postgres local):
--   fn_tardanza_escalon  b98d1c65d5ed1e85d8550c280d10751f  (0235)
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
      -- constituye antecedente agravante y no es peldaño previo»; su emisión o
      -- su omisión NO ALTERA NINGÚN CÓMPUTO.
      and e.nivel <> 'verbal'
  ),
  vig as (select * from docs where vigente),
  cuenta as (
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
    -- Las suspensiones NOTIFICADAS, hayan caducado o no: es lo que el numeral
    -- 19.6 (i) exige acreditar «obrantes en el legajo», y el legajo no caduca.
    select count(*) as n_susp from docs where nivel = 'suspension'
  ),
  ultimo as (
    select id from docs order by entregado_at desc, periodo_hasta desc, id desc limit 1
  )
  select
    case
      -- Dos suspensiones vigentes: la escalera está completa y toca imputar.
      when c.n_susp >= 2                        then 'imputacion'
      -- Ya hubo imputación Y la escalera de abajo está completa: de ahí no se
      -- baja, aunque la imputación se haya archivado.
      when c.n_imp > 0 and l.n_susp >= 2        then 'imputacion'
      -- Una imputación con la escalera INCOMPLETA no tapa el escalón que falta.
      -- Es el caso de Arequipa: se imputó saltándose el literal d), y lo que
      -- corresponde es esa segunda suspensión, no otra imputación.
      when c.n_susp = 1 and l.n_susp >= 2       then 'imputacion'
      when c.n_susp = 1                         then 'suspension'
      when c.n_amon > 0 or c.n_imp > 0          then 'suspension'
      else                                           'amonestacion'
    end,
    case
      when c.imp_abierta                        then null::int
      when c.n_susp >= 1 or c.n_imp > 0         then 1
      when c.n_amon > 0                         then 2
      else                                           3
    end,
    c.corte,
    (select id from ultimo),
    coalesce(c.imp_abierta, false),
    c.dias_susp::int
  from cuenta c cross join legajo l;
$$;

comment on function fn_tardanza_escalon(uuid) is
  'Art. 19.2 del RIT: que escalon toca. Una imputacion solo mantiene arriba si el legajo acredita las DOS suspensiones que exige el numeral 19.6 (i).';

grant execute on function fn_tardanza_escalon(uuid) to authenticated, service_role;
revoke execute on function fn_tardanza_escalon(uuid) from public;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (246, 'una_imputacion_prematura_no_tapa_el_escalon_que_falta')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las dos deben decir true.
select
  (select prosrc ilike '%c.n_imp > 0 and l.n_susp >= 2%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_tardanza_escalon')
                                              as la_imputacion_exige_la_escalera_completa,
  (select prosrc ilike '%c.n_amon > 0 or c.n_imp > 0%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_tardanza_escalon')
                                              as una_imputacion_sin_suspensiones_baja_al_escalon_que_falta;
