-- ============================================================================
-- 0526 — La constancia de un apoyo MENSUAL se pide desde el día 1 del mes
-- ============================================================================
--
-- QUÉ PROMETE
--   Que a un apoyo educativo de frecuencia MENSUAL se le pida la constancia de
--   este mes desde el día 1, y no desde el día en que la institución cobra.
--   Hasta hoy el pedido se abría el día del pago (`proxima_fecha_pago`): una
--   integrante cuyo pago cae el 15 no veía nada hasta el 15, y le quedaban ocho
--   días para el plazo (el 23). Desde esta migración lo ve el día 1.
--
-- LO QUE DECIDIÓ FELIPE (2026-10-17)
--   · El día 1 se ABRE el pedido de la constancia del mes y se avisa: no es un
--     recordatorio, `estado_constancia` cambia. Eso es lo que leen la pantalla
--     de la integrante, la de DO y la Bandeja, así que el aviso llega solo.
--   · El PLAZO sigue siendo el de hoy: `fn_educacion_plazo` (5 días antes del
--     cierre del periodo de planilla, ≈ el día 23). No se toca.
--   · Vale SOLO para frecuencia 'mensual'. Los de 'ciclo', 'unico' y 'otra'
--     siguen con su calendario por institución, tal cual.
--   · SOLO ALERTA, igual que desde la 0450. Aprobar o rechazar no cambia lo que
--     cobra nadie: la planilla sigue mirando `comprobante_url`. Esta migración
--     solo reescribe una función de LECTURA (`stable`, sin un solo insert/update):
--     no toca `fn_planilla_calcular`, ni el espejo, ni la 0524, ni la 0525.
--
-- QUÉ CUENTA COMO «LA CONSTANCIA DE ESTE MES», Y A QUIÉN SE LE PIDE
--   Mes = mes CALENDARIO de Lima, que es lo que ya usa la cuadrícula de
--   Educación («el mes de una constancia es el de su fecha de pago»; un mes sin
--   constancia es un guion, nunca una falta).
--
--   Un estudio MENSUAL pide su constancia desde el día 1 cuando se cumple TODO:
--     1. frecuencia_pago = 'mensual';
--     2. su próximo pago declarado cae en ESTE mes y todavía no llega
--        (> hoy y < día 1 del mes siguiente);
--     3. ese pago cae dentro de la vigencia (<= vigente_hasta);
--     4. el estudio ya empezó (el más antiguo `vigente_desde` de la familia es
--        <= hoy; uno programado no pide nada);
--     5. este mes NO tiene una constancia APROBADA (fecha de pago dentro del mes).
--
--   Una PENDIENTE no necesita mirarse acá: sale primero como
--   'pendiente_revision'. Una RECHAZADA tampoco: sale como 'rechazada'. Una
--   RETIRADA no cuenta (se retiró). Una aprobada de otro mes no cubre este.
--
--   Cuando se cumple, el estado sale por la misma escalera de siempre, con
--   `fecha_pago_constancia` = el pago declarado y `plazo` = fn_educacion_plazo
--   de esa fecha: 'falta_enviar' y, en la última semana antes del plazo,
--   'por_vencer'. Nunca 'vencida': el plazo de un pago por venir nunca es
--   anterior a ese pago.
--
-- POR QUÉ NO «DÍA 1 DEL MES» A SECAS (las cuatro cosas que se midieron)
--   Se evaluó pedir la constancia del mes a todo estudio mensual el día 1, con
--   plazo `fn_educacion_plazo(día 1)`. Daba falsos positivos, que es el peor
--   error de este sistema:
--     a) PAGOS TARDÍOS. fn_educacion_plazo corre el plazo al periodo siguiente
--        cuando el pago cae después de «cierre − 5 días»: un pago del 27 tiene
--        plazo el 23 del mes que viene. Con plazo del día 1, esa integrante
--        figuraría 'vencida' el 24 sin haber podido pagar todavía.
--     b) ESTUDIO NUEVO. Uno que empieza el 20 con su primer pago el 5 del mes
--        siguiente figuraría 'vencida' el 24, a los cuatro días de empezar.
--     c) SIN MÁS PAGOS. Quien declaró «último pago» (próxima fecha en blanco) no
--        tiene calendario: sigue 'sin_calendario', no se le pide nada.
--     d) VIGENCIA. Un estudio que termina antes de su próximo pago no pide nada.
--   Por eso la regla cuelga del pago declarado de ESTE mes: se adelanta la
--   apertura al día 1, y todo lo demás —el plazo, las exclusiones, las otras
--   frecuencias— queda como estaba.
--
-- LO QUE NO ARREGLA (visto al medir, no es de esta migración)
--   Pagar ANTES de la fecha declarada no corre el calendario:
--   `fn_educacion_avanzar_calendario` solo avanza si la fecha de pago de la
--   constancia aprobada es >= la próxima fecha vigente. Quien declara el 15 y
--   paga el 3 deja el calendario en el 15: ese día, y hasta que suba la del mes
--   siguiente, el sistema vuelve a pedirle un pago que ya sustentó. Pasa con
--   todas las frecuencias desde la 0450, esta migración no lo empeora (mientras
--   el mes está aprobado sigue 'al_dia'), y arreglarlo toca OTRA función. Se
--   dejó anotado en el resumen de entrega.
--
-- QUÉ CAMBIA, MEDIDO
--   Contra el Postgres local, en BEGIN … ROLLBACK, con el reloj de
--   `fn_hoy_lima()` fijado en una fecha de 2031 y periodos 29→28 sembrados. La
--   misma fixture con la función de la 0450 (control) y con esta migración:
--
--@@TABLA@@
--
--   Todo lo que no es «mensual con el pago de este mes por venir» da EXACTAMENTE
--   lo mismo que antes (estado, fecha y plazo): las demás frecuencias, el pago
--   del mes siguiente, el vencido de siempre, lo pendiente, lo rechazado.
--
-- QUÉ ASUME
--   · La 0450 (`fn_educacion_situacion`, `fn_educacion_plazo`, las entregas y la
--     familia), `fn_hoy_lima` (0091) y `periodos_planilla`.
--   · Misma firma y mismas columnas que la 0450: `create or replace` conserva los
--     permisos y quien la llama (`fn_educacion_por_atender`, la Bandeja) no se
--     entera. No hay `drop function`.
--   · `fn_educacion_por_atender` (el número rojo del menú de DO) cuenta
--     'vencida' y 'sin_calendario', no 'falta_enviar': abrir el mes el día 1 NO
--     infla ese número. Tampoco la Bandeja de DO, que mira 'vencida', 'sin
--     calendario' y el aviso de pago próximo.
--
-- DE QUÉ VERSIÓN PARTE
--   De la 0450, extraída del archivo y parcheada con un script, no retipeada a
--   mano. Los tres bloques cambiados llevan el marcador «CAMBIO 0526» y el resto
--   es byte por byte lo que ya estaba.
--
--   md5 de partida del repositorio (la 0450, Postgres local, 4 006 caracteres):
--     tal_cual            f0ddaf5bdd6a9b998a75a1fcdcaa2ab6
--   md5 de partida en PRODUCCIÓN: ►►► PENDIENTE ◄◄◄ — la pide Felipe con la
--   consulta del mensaje de entrega, que se corre ANTES de pegar y se vuelve a
--   pedir al entregar (un md5 es una foto, no una garantía).
--
--   md5 de llegada, medido en el Postgres local aplicando este archivo dentro de
--   BEGIN … ROLLBACK, con el número ya definitivo:
--     @@LLEGADA@@
--   Si producción da otro con la misma longitud, mira
--   `position('CAMBIO 0526' in prosrc)`; si la diferencia es el número de líneas,
--   es el `\r` de pegar desde Windows y no hay nada roto (ver CLAUDE.md).
--
-- CÓMO SE VERIFICA DESPUÉS DE PEGAR
--   select length(prosrc), md5(prosrc), position('CAMBIO 0526' in prosrc)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'fn_educacion_situacion';
--   y que `migraciones_aplicadas` traiga numero 526 con su nombre.
--
-- CÓMO SE REVIERTE
--   Volver a pegar `fn_educacion_situacion` tal como la dejó la 0450 (líneas
--   1014–1141 de esa migración, ya sin el `drop function` si la función existe
--   con la misma firma). No hay cambio de esquema ni de datos.
-- ============================================================================

create or replace function fn_educacion_situacion()
returns table (
  familia_id           uuid,
  asignacion_id        uuid,
  persona_id           uuid,
  persona              text,
  sede                 text,
  rango                text,
  institucion          text,
  beneficiario         text,
  beneficiario_nombre  text,
  monto                numeric,
  vigente_desde        date,
  vigente_hasta        date,
  vigencia             text,
  paga                 boolean,
  frecuencia_pago      text,
  proxima_fecha_pago   date,
  dias_para_pago       int,
  pago_proximo         boolean,
  estado_constancia    text,
  fecha_pago_constancia date,
  plazo                date,
  dias_para_plazo      int,
  entrega_id           uuid,
  entrega_estado       text,
  entrega_enviada_at   timestamptz,
  entrega_archivos     int,
  motivo_categoria     text,
  motivo_comentario    text,
  aprobadas            int,
  aviso_fin_id         uuid,
  aviso_fin_motivo     text
)
language sql
stable
security definer
set search_path = public
as $$
  with par as (
    select h.hoy,
           -- ⇩ CAMBIO 0526 ⇩ El día 1 de este mes y el día 1 del siguiente, en Lima.
           -- Aritmética de fechas pura: nada de date_trunc, que devuelve un instante
           -- y mete el huso del servidor (UTC) en una cuenta que ya está en Lima.
           h.hoy - (extract(day from h.hoy)::int - 1)                              as ini_mes,
           (h.hoy - (extract(day from h.hoy)::int - 1) + interval '1 month')::date as sig_mes,
           fn_educacion_parametro('educacion_dias_aviso_colaboradora', 7) as av_col,
           fn_educacion_parametro('educacion_dias_aviso_do', 7)           as av_do
      from (select fn_hoy_lima() as hoy) h
  ),
  fam as (
    select distinct on (a.familia_id)
           a.*, min(a.vigente_desde) over (partition by a.familia_id) as desde_familia
      from asignaciones_educacion a
     where fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id()
     order by a.familia_id, a.vigente_desde desc, a.id desc
  )
  select
    f.familia_id, f.id, f.persona_id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    f.institucion, f.beneficiario, f.beneficiario_nombre, f.monto,
    f.desde_familia, f.vigente_hasta,
    case when f.desde_familia > par.hoy          then 'futura'
         when f.vigente_hasta < par.hoy          then 'terminada'
         when f.vigente_hasta <= par.hoy + 30    then 'por_terminar'
         else 'vigente' end,
    (f.comprobante_url is not null and f.vigente_hasta >= par.hoy),
    f.frecuencia_pago, f.proxima_fecha_pago,
    (f.proxima_fecha_pago - par.hoy)::int,
    coalesce(f.proxima_fecha_pago between par.hoy and par.hoy + par.av_do
             and f.proxima_fecha_pago <= f.vigente_hasta, false),
    est.estado,
    est.fecha,
    fn_educacion_plazo(est.fecha),
    (fn_educacion_plazo(est.fecha) - par.hoy)::int,
    ul.id, ul.estado, ul.enviada_at, ul.archivos, ul.motivo_categoria, ul.motivo_comentario,
    apr.n,
    av.id, av.motivo
  from fam f
  cross join par
  join personas p on p.id = f.persona_id
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select x.rango from asignaciones_salario x
     where x.persona_id = f.persona_id and x.vigente_hasta is null
     order by x.vigente_desde desc, x.id desc limit 1
  ) sal on true
  left join lateral (
    select e.id, e.fecha_pago
      from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
     where x.familia_id = f.familia_id and e.estado = 'pendiente'
     order by e.enviada_at desc, e.id desc limit 1
  ) pe on true
  left join lateral (
    select e.id, e.estado, e.fecha_pago, e.enviada_at, e.motivo_categoria, e.motivo_comentario,
           (select count(*)::int from educacion_entrega_archivos ar where ar.entrega_id = e.id) as archivos
      from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
     where x.familia_id = f.familia_id and e.estado <> 'retirada'
     order by e.fecha_pago desc, e.enviada_at desc, e.id desc limit 1
  ) ul on true
  left join lateral (
    select count(*)::int as n
      from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
     where x.familia_id = f.familia_id and e.estado = 'aprobada'
  ) apr on true
  left join lateral (
    select v.id, v.motivo
      from educacion_avisos_fin v join asignaciones_educacion x on x.id = v.asignacion_id
     where x.familia_id = f.familia_id and v.atendido_at is null
     order by v.creado_at desc, v.id desc limit 1
  ) av on true
  -- ⇩ CAMBIO 0526 ⇩ ¿Este estudio MENSUAL ya tiene que pedir la constancia de este
  -- mes aunque el pago todavía no haya llegado? Sí, si TODO esto es cierto:
  --   · es mensual (los de ciclo, pago único y otra siguen con su calendario);
  --   · hay un próximo pago declarado y cae en ESTE mes, todavía por venir (si cae
  --     más adelante, la institución no cobra este mes y no hay nada que pedir;
  --     si ya llegó, la regla de siempre ya lo pide);
  --   · ese pago cae dentro de la vigencia (si cae después, no quedan pagos);
  --   · el estudio ya empezó (uno programado no pide nada);
  --   · este mes todavía no tiene una constancia APROBADA. Una pendiente no llega
  --     hasta acá —sale arriba como «pendiente_revision»— y una rechazada tampoco
  --     —sale como «rechazada»—.
  -- coalesce: `frecuencia_pago` puede ser null, y un null en este `and` dejaría
  -- el `case` de abajo sin decidir `al_dia`: se caería a «falta_enviar».
  cross join lateral (
    select coalesce(
             f.frecuencia_pago = 'mensual'
             and f.proxima_fecha_pago > par.hoy
             and f.proxima_fecha_pago < par.sig_mes
             and f.proxima_fecha_pago <= f.vigente_hasta
             and f.desde_familia <= par.hoy
             and not exists (
               select 1
                 from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
                where x.familia_id = f.familia_id and e.estado = 'aprobada'
                  and e.fecha_pago >= par.ini_mes and e.fecha_pago < par.sig_mes),
             false) as abierto
  ) mes
  cross join lateral (
    select
      case
        when pe.id is not null                                   then 'pendiente_revision'
        when ul.estado = 'rechazada'                             then 'rechazada'
        when f.proxima_fecha_pago is null                        then 'sin_calendario'
        when (f.proxima_fecha_pago > par.hoy and not mes.abierto)  -- CAMBIO 0526
          or f.proxima_fecha_pago > f.vigente_hasta              then 'al_dia'
        when fn_educacion_plazo(f.proxima_fecha_pago) < par.hoy  then 'vencida'
        when fn_educacion_plazo(f.proxima_fecha_pago) - par.hoy <= par.av_col then 'por_vencer'
        else 'falta_enviar'
      end as estado,
      case
        when pe.id is not null        then pe.fecha_pago
        when ul.estado = 'rechazada'  then ul.fecha_pago
        else f.proxima_fecha_pago
      end as fecha
  ) est
  order by p.apellidos, p.nombres, f.institucion, f.familia_id;
$$;


-- Misma firma que la 0450: `create or replace` conserva el permiso; se repite
-- porque pegar a mano no debe depender de lo que haya quedado de antes.
grant execute on function fn_educacion_situacion() to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (526, 'la_constancia_mensual_se_pide_desde_el_dia_1')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
