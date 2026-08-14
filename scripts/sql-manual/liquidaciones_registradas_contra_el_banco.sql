-- ============================================================================
-- TODA LIQUIDACIÓN REGISTRADA COMO PAGADA — para cotejarla con el extracto.
-- Solo LEE. No escribe, no anula, no corrige nada.
-- ============================================================================
--
-- ⚠️ El resultado lleva nombres y montos de personas reales. Míralo y decide;
--    no lo pegues entero en ningún sitio, ni lo guardes en git.
--
-- ── LO ÚNICO QUE ESTA CONSULTA SABE ─────────────────────────────────────────
--
-- QUÉ SE REGISTRÓ. Nada más.
--
-- «Liquidación pagada» en este sistema significa que alguien apretó un botón y
-- el sistema congeló una copia del cálculo. NO significa que el dinero saliera
-- del banco. Son dos hechos distintos y solo uno de ellos vive acá.
--
-- SI EL DINERO SALIÓ O NO, LO DICE EL EXTRACTO BANCARIO Y NADA MÁS. Ninguna
-- tabla de este repositorio lo sabe, y esta consulta no lo va a adivinar por
-- ti: la primera columna sale a propósito con un interrogante para que la
-- rellenes tú, al lado, mirando la cuenta. Una columna vacía que pide que la
-- llenes es más honesta que una columna llena de una suposición.
--
-- ── POR QUÉ ESTO EXISTE ─────────────────────────────────────────────────────
--
-- Medido el 2026-08-14. Una persona en periodo de prueba, que nunca entró a
-- planilla, cesó el 07/08. Se le pagó un adelanto fuera de planilla. El 10/08
-- alguien apretó «Liquidación pagada» y el sistema congeló S/1,106.82 que NUNCA
-- SALIERON DEL BANCO.
--
-- Ese registro no solo mentía: bloqueaba el cierre del mes por el freno de la
-- 0244 y anunciaba en la pantalla de Planilla un cobro que no hubo. Y no había
-- forma de deshacerlo hasta la 0251.
--
-- Si pasó una vez pudo pasar más veces, y la única manera de saberlo es esta:
-- poner la lista al lado del extracto y marcar una por una.
--
-- ── LA COLUMNA DEL DIVISOR ──────────────────────────────────────────────────
--
-- Hay una segunda forma de que uno de estos importes esté mal, y no depende de
-- si el dinero salió: la 0239 arregló el divisor con el que se calcula el pago
-- de un rango parcial, y la liquidación es la única del sistema que pide un
-- rango parcial. Antes de ese arreglo, el importe salía inflado entre 1.1× y
-- 3.1× según lo temprano que se cesara dentro del periodo.
--
-- La 0239 llegó a producción el 2026-08-13, así que toda foto congelada ANTES
-- de esa fecha arrastra el defecto. La columna `arrastra_el_divisor_malo` lo
-- dice fila por fila. Ojo: dice que el IMPORTE CONGELADO es sospechoso, no que
-- se pagara de más — para saber eso hace falta, otra vez, el extracto.
--
-- ── CÓMO LEER LAS VERSIONES ─────────────────────────────────────────────────
--
-- `liquidacion_pagada` versiona por persona y nunca se edita ni se borra: una
-- corrección es siempre una versión MÁS. Por eso salen todas, y `estado_registro`
-- dice de un vistazo cuál manda:
--
--   ➜ VIGENTE          la última, y es un pago: es la que cuenta hoy
--   🚫 ANULADA         se marcó por error y ya no cuenta (queda como histórico)
--   ⛔ ANULACIÓN       la fila que anula a otra; está en cero por diseño
--   ·  reemplazada     se volvió a congelar después, con otro importe
--
-- Solo las ➜ VIGENTE suman. Las demás están para explicar qué pasó.
--
-- ── QUÉ HACER CON UNA FILA QUE NO CUADRA ────────────────────────────────────
--
-- Si el extracto dice que ese dinero nunca salió, se anula — no se borra:
--
--   select set_config('request.jwt.claim.sub', 'TU-AUTH-USER-ID', true);
--   select fn_liquidacion_anular('EL-PERSONA-ID-DE-LA-FILA',
--            'Motivo: qué se marcó por error y cómo se sabe.');
--
-- Después de anular, la persona vuelve a aparecer en /admin/liquidaciones con
-- su botón «Marcar como pagada», para congelar el importe correcto si de verdad
-- se le debe algo.
--
-- ── REQUISITO ───────────────────────────────────────────────────────────────
-- Necesita la 0251 aplicada (es la que agrega la columna `anulada`). Si falla
-- con «column anulada does not exist», pega antes esa migración.
-- ============================================================================

with v as (
  select
    lp.*,
    max(lp.version) over (partition by lp.persona_id) as ultima_version
  from liquidacion_pagada lp
)
select
  -- ⇩ PRIMERA COLUMNA A PROPÓSITO. Es la que el sistema no puede contestar.
  --   Cópiala a una hoja y complétala mirando el extracto, fila por fila.
  '¿?  → mirar el extracto'                        as salio_del_banco,

  v.persona,
  v.fecha_cese,
  v.version,

  case
    when v.anulada
      then '⛔ ANULACIÓN de la v' || coalesce(v.anula_version::text, '?')
    when an.version is not null
      then '🚫 ANULADA por la v' || an.version || ' — no cuenta'
    when v.version = v.ultima_version
      then '➜ VIGENTE — es la que cuenta hoy'
    else '·  reemplazada por la v' || v.ultima_version
  end                                              as estado_registro,

  (v.congelada_at at time zone 'America/Lima')::date as congelada_el,

  -- El sueldo del mes que esta liquidación registró. Es la cifra que se solapa
  -- con la planilla del periodo; el resto son truncas.
  v.monto_periodo                                  as del_mes_registro,
  v.total                                          as total_registrado,

  case
    when v.anulada then '—  (está en cero)'
    when (v.congelada_at at time zone 'America/Lima')::date < date '2026-08-13'
      then '⚠ SÍ — congelada antes de la 0239: el importe viene inflado'
    else 'no — ya con el divisor arreglado'
  end                                              as arrastra_el_divisor_malo,

  -- Para poder anularla sin buscar el id en otra consulta.
  v.persona_id,

  coalesce(v.motivo_anulacion, v.nota, '—')        as motivo_o_nota,
  quien.nombres || ' ' || quien.apellidos          as lo_registro

from v
left join personas quien
       on quien.id = v.congelada_por
-- ¿Alguien anuló ESTA versión? Es una fila posterior que la señala.
left join lateral (
  select min(a.version) as version
  from liquidacion_pagada a
  where a.persona_id = v.persona_id
    and a.anula_version = v.version
    and a.anulada
) an on true

order by
  -- Lo ya resuelto se va abajo: quien tiene su anulación puesta ya no hay que
  -- cotejarlo con el extracto. Arriba queda lo que sigue contando como pagado,
  -- que es lo único que hay que ir a mirar a la cuenta. Las versiones de una
  -- misma persona salen juntas, para poder leer su historia de un tirón.
  case when v.anulada or an.version is not null then 1 else 0 end,
  v.fecha_cese desc,
  v.persona,
  v.version desc;
