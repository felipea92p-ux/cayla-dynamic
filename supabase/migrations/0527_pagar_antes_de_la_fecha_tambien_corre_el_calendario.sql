-- ============================================================================
-- 0527 — Pagar ANTES de la fecha declarada también corre el calendario de las
--        constancias de Educación
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cuando una integrante paga su estudio antes del día que había declarado,
--   y DO aprueba esa constancia, el calendario de la familia avance igual a la
--   fecha que ella declaró como próxima — y deje de pedirle un pago que ya
--   sustentó.
--
-- EL DEFECTO, CON EL CASO QUE LO MIDIÓ
--   Desde la 0450, `fn_educacion_avanzar_calendario` solo mueve
--   `proxima_fecha_pago` cuando la FECHA DE PAGO de la constancia aprobada es
--   mayor o igual que la próxima fecha vigente:
--       e.fecha_pago >= a.proxima_fecha_pago
--   Compara el día en que se pagó contra el día en que se DECLARÓ que se pagaría,
--   así que pagar antes nunca la alcanza.
--
--   Medido el 2026-10-17 en el Postgres local con las funciones de verdad
--   (fn_educacion_enviar_entrega por la integrante, fn_educacion_resolver_entrega
--   por DO, reloj fijado en 2031): un estudio mensual con próxima fecha el 15 de
--   mayo; la integrante envía el pago del 3 de mayo declarando el próximo el 3 de
--   junio; DO lo aprueba. El calendario se queda en el 15 de mayo. Resultado:
--       3 mayo   al_dia
--       20 mayo  por_vencer   (plazo 23/05)   ← para un mes ya aprobado
--       24 mayo  vencida                        ← ídem
--       1 junio  vencida
--   Es un falso positivo —el peor error de este sistema— pero SOLO de alerta:
--   no cambia lo que cobra nadie. La planilla sigue mirando `comprobante_url`.
--   Pasa con todas las frecuencias y existe desde la 0450; la 0526 (pedir la
--   constancia mensual desde el día 1) lo vuelve más probable, no lo causa.
--
-- LO QUE DECIDIÓ FELIPE (2026-10-17)
--   Criterio «A»: el calendario avanza también cuando el pago cae en el MES
--   CALENDARIO de la fecha vigente, aunque sea antes del día. Para toda
--   frecuencia (mensual, por ciclo, pago único, otra, sin decir).
--
-- LA REGLA
--   Antes:   avanza si  P es null  O  F >= P
--   Ahora:   avanza si  P es null  O  F >= P
--                       O  ( F >= día 1 del mes de P  Y  ( N es null  O  N > P ) )
--   donde P = la próxima fecha vigente de la familia, F = la fecha de pago de la
--   constancia aprobada y N = la próxima fecha que ella declaró (null = «este fue
--   mi último pago»).
--
--   · Sigue siendo SOLO HACIA ADELANTE. El tercer término exige N > P; la
--     comparación vieja ya lo garantizaba (N > F >= P por la validación de
--     fn_educacion_enviar_entrega).
--   · «Último pago» sigue poniendo null: si N es null y el pago es del mes de P,
--     el calendario queda en null, igual que ya pasaba con F >= P.
--   · El mes es el del CALENDARIO de Lima, el mismo que usa la cuadrícula de
--     Educación y la 0526 para decir «este mes ya tiene constancia» (el mes de
--     una constancia es el de su fecha de pago). Quedan coherentes.
--
-- POR QUÉ ESTE CRITERIO Y NO OTRO (14 casos, medidos antes de escribirlo)
--   Se comparó con «B · solo hacia adelante» (avanzar siempre que N > P, sin mirar
--   F). B arregla el mismo caso pero PISA LA CORRECCIÓN MANUAL DE DO: con el
--   calendario fijado por DO en el 15/oct, la constancia de un pago del 20/sep
--   aprobada tarde declara próximo el 20/oct, y B movería lo que DO fijó. Con A no
--   se mueve, porque ese pago no es del mes de la fecha vigente. Además B no puede
--   decidir el caso «último pago» (null no se compara).
--   `fn_educacion_fijar_calendario` no se toca: DO sigue mandando, en los dos
--   sentidos.
--
-- QUÉ CAMBIA, MEDIDO (A contra la 0450, sobre los 14 casos)
--   Cambian SOLO los que pagan antes dentro del mes de la fecha vigente:
--     paga el 3 con vencimiento el 15 (declara el 3 o el 15 siguiente)   no → avanza
--     lo mismo, pero con «último pago» (próxima en blanco)               no → null
--     lo mismo en un estudio por ciclo o de pago único                   no → avanza
--     paga el día 1 o el 5 con vencimiento el 31                         no → avanza
--   Sin cambio: el pago en la fecha o después, la constancia vieja aprobada
--   tarde (con el calendario ya adelantado o fijado por DO), el pago antes del mes
--   de la fecha vigente, una próxima declarada que no es posterior, el calendario
--   vacío y lo pendiente.
--
-- LO QUE NO ARREGLA
--   · Pagar en un mes ANTERIOR al de la fecha vigente (vence el 3 de noviembre,
--     paga el 28 de octubre) sigue sin mover el calendario. Es el residuo del
--     criterio A; DO lo corrige con `fn_educacion_fijar_calendario`.
--   · No repara los estudios que YA quedaron atrasados antes de pegar esto: la
--     función solo actúa cuando se aprueba una constancia, y nada reaprueba las
--     viejas. Cuántos son en producción: ►►► PENDIENTE ◄◄◄ — lo mide Felipe con la
--     consulta del final de este archivo. DO los corrige a mano con
--     `fn_educacion_fijar_calendario`; esta migración no toca ningún dato.
--   · Revertir una aprobación (la 0525, SIN PEGAR a la fecha de esta migración)
--     devuelve el calendario a la FECHA DE PAGO de la constancia revertida. Para un
--     pago hecho el 3 con vencimiento el 15 eso deja el calendario en el 3, no en
--     el 15: hasta hoy no lo movía porque la aprobación nunca lo había avanzado.
--     Es solo alerta y el plazo casi siempre es el mismo (ambas fechas caen en el
--     mismo periodo de planilla), pero conviene saberlo al fusionar la 0525.
--
-- QUÉ ASUME
--   · La 0450 (`educacion_entregas`, `asignaciones_educacion.familia_id`,
--     `frecuencia_pago` y `proxima_fecha_pago`) y quien llama a esta función:
--     `fn_educacion_enviar_entrega` (cuando DO carga una constancia, nace
--     aprobada) y `fn_educacion_resolver_entrega` (cuando DO aprueba). Ninguna de
--     las dos se toca: preguntan lo mismo de siempre.
--   · Misma firma, mismo `security definer`, mismo `search_path` y el mismo
--     `revoke`: `create or replace` conserva los permisos. No hay `drop function`.
--   · No toca `fn_planilla_calcular`, ni el espejo (`fn_educacion_refrescar_espejo`),
--     ni `fn_educacion_situacion`: es una función de ESCRITURA del calendario que
--     solo alimenta una alerta.
--
-- DE QUÉ VERSIÓN PARTE
--   De la 0450, extraída del archivo; el único bloque cambiado lleva el marcador
--   «CAMBIO 0527» y el resto es byte por byte lo que ya estaba.
--
--   md5 de partida, medido en PRODUCCIÓN el 2026-10-17 (no copiado del local):
--     bd2c70bb41fe7744f0d74f0151e33e63   · 354 caracteres · 0 retornos de carro
--   Coincide con el de la 0450 en el Postgres local, tal cual y sin comentarios.
--   La sección 0 frena si en la base donde se pega no es esa versión. Se volvió a
--   pedir al entregar —ver el mensaje de entrega—, porque un md5 es una foto y
--   caduca.
--
--   md5 de llegada, medido en el Postgres local aplicando este archivo dentro de
--   BEGIN … ROLLBACK, con el número ya definitivo:
--     tal_cual            51570d948d13c3fe079ff78e2a6905e2   · 727 caracteres
--     sin comentarios     6f94cdf935ec3597d0a2fa4d0c1677fd
--     position('CAMBIO 0527' in prosrc) = 376 · 0 retornos de carro
--   Si producción da otro tras pegar, con la misma longitud, mira
--   `position('CAMBIO 0527' in prosrc)`; si la diferencia es el número de líneas,
--   es el `\r` de pegar desde Windows y no hay nada roto (ver CLAUDE.md).
--
-- CÓMO SE VERIFICA DESPUÉS DE PEGAR
--   select length(prosrc), md5(prosrc), position('CAMBIO 0527' in prosrc)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'fn_educacion_avanzar_calendario';
--   y que `migraciones_aplicadas` traiga numero 527 con su nombre.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar la función tal como la dejó la 0450 (el bloque H de
--   0450_la_constancia_de_estudios_se_entrega_y_se_revisa.sql). No hay cambio de
--   esquema ni de datos: los calendarios que esta función ya hubiera avanzado se
--   quedan donde están (DO los puede volver a fijar a mano).
-- ============================================================================


-- ── 0 · Comprobar ANTES de tocar nada ───────────────────────────────────────
-- Mismo patrón que la 0323 y la 0525: si en esta base la función no es la de
-- partida declarada arriba, esta migración no aplica NADA. Reescribir desde un
-- cuerpo que no es el vigente revierte en silencio lo que se arregló entre medias.
do $$
declare v_md5 text; v_len int;
begin
  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_educacion_avanzar_calendario';
  -- Si ya está esta migración puesta, el cuerpo lleva su marca: repegar es seguro.
  if v_md5 is distinct from 'bd2c70bb41fe7744f0d74f0151e33e63'
     and not exists (select 1 from pg_proc p where p.proname = 'fn_educacion_avanzar_calendario'
                        and p.prosrc like '%CAMBIO 0527%') then
    raise exception '0527 · PARA. fn_educacion_avanzar_calendario en esta base es % (% caracteres), se esperaba bd2c70bb41fe7744f0d74f0151e33e63 (354). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_educacion_avanzar_calendario.', v_md5, v_len;
  end if;
end $$;


-- ── A · La función ──────────────────────────────────────────────────────────
-- Avanza el calendario de la familia con una constancia aprobada. Solo hacia
-- adelante: aprobar tarde la constancia de un pago viejo no puede devolver la
-- próxima fecha al pasado.
create or replace function fn_educacion_avanzar_calendario(p_entrega_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update asignaciones_educacion a
     set proxima_fecha_pago = e.proxima_fecha_pago
    from educacion_entregas e
    join asignaciones_educacion x on x.id = e.asignacion_id
   where e.id = p_entrega_id
     and e.estado = 'aprobada'
     and a.familia_id = x.familia_id
     and (a.proxima_fecha_pago is null
          or e.fecha_pago >= a.proxima_fecha_pago
          -- CAMBIO 0527: pagar antes del día declarado, pero dentro del mes de esa
          -- fecha, es pagar ESA cuota. Sigue siendo solo hacia adelante.
          or (e.fecha_pago >= date_trunc('month', a.proxima_fecha_pago::timestamp)::date
              and (e.proxima_fecha_pago is null
                   or e.proxima_fecha_pago > a.proxima_fecha_pago)));
$$;

revoke execute on function fn_educacion_avanzar_calendario(uuid) from public, anon, authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (527, 'pagar_antes_de_la_fecha_tambien_corre_el_calendario')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();


-- ============================================================================
-- CONSULTA DE SOLO LECTURA para el SQL Editor de PRODUCCIÓN — cuántos estudios
-- vigentes tienen HOY el calendario atrasado respecto de su última constancia
-- aprobada (los casos 5 y 6 son los que este defecto dejó atrasados). Se corre
-- ANTES o DESPUÉS de pegar: no depende de esta migración.
-- ============================================================================
--   with fam as (
--     select distinct on (a.familia_id)
--            a.familia_id, a.frecuencia_pago, a.proxima_fecha_pago as calendario, a.vigente_hasta
--       from asignaciones_educacion a
--      order by a.familia_id, a.vigente_desde desc, a.id desc
--   ), ult as (
--     select distinct on (x.familia_id)
--            x.familia_id, e.fecha_pago as f, e.proxima_fecha_pago as declarada
--       from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
--      where e.estado = 'aprobada'
--      order by x.familia_id, e.fecha_pago desc, e.enviada_at desc, e.id desc
--   )
--   select coalesce(f.frecuencia_pago, '(sin decir)') as frecuencia,
--          case
--            when f.calendario is null                                   then '1 sin calendario (último pago o sin cargar)'
--            when u.familia_id is null                                   then '2 sin ninguna constancia aprobada'
--            when u.declarada is not distinct from f.calendario          then '3 al día: el calendario es lo que dijo la última constancia'
--            when u.f >= f.calendario                                    then '4 otro (el calendario no coincide con lo declarado)'
--            when u.f >= date_trunc('month', f.calendario)::date
--                 and (u.declarada is null or u.declarada > f.calendario) then '5 ATRASADO · pagó antes, MISMO mes de la fecha vigente'
--            when u.declarada > f.calendario                              then '6 ATRASADO · pagó antes, MES ANTERIOR a la fecha vigente'
--            else                                                              '7 otro (la última constancia declara algo anterior al calendario)'
--          end as caso,
--          count(*) as estudios
--     from fam f left join ult u using (familia_id)
--    where f.vigente_hasta >= fn_hoy_lima()
--    group by 1, 2
--    order by 2, 1;
