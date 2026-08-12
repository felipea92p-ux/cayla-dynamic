-- ============================================================================
-- 0230_el_terminal_puede_preguntar_la_hora.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el terminal pueda preguntarle la hora al servidor, para comparar con la
--   suya y darse cuenta de que el reloj de la Mac se corrió.
--
-- QUÉ ASUME
--   Nada. Una función de una línea, sin argumentos, que no lee ni una tabla.
--
-- ── POR QUÉ HACE FALTA ──────────────────────────────────────────────────────
--
-- `marcajes.timestamp_marca` —el dato del que cuelga TODO: a qué día se paga,
-- si hubo tardanza, cuántas horas se trabajaron— lo pone el navegador de la Mac
-- mini con su propio reloj, y hasta hoy nadie lo verificaba. Cero menciones de
-- «desfase» en todo el terminal, medido el 2026-08-12.
--
-- Una Mac con el reloj adelantado media hora convierte una entrada puntual en
-- una tardanza de treinta minutos. Con el reloj corrido varias horas, un
-- marcaje de la noche puede caer en el día siguiente y pagarse en otra jornada.
-- Ninguno de los dos casos deja rastro: el número entra perfecto, solo que es
-- de otro momento.
--
-- ── POR QUÉ UNA FUNCIÓN Y NO LA CABECERA `Date` DE HTTP ─────────────────────
--
-- Se consideró leer la cabecera `Date` de cualquier respuesta, que es gratis y
-- no necesita esta migración. Se descartó: supabase-js no la expone de forma
-- estable, la resolución es de un segundo, y —lo que decide— una cabecera no se
-- puede probar con pgTAP. Esto sí.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
-- No corrige ninguna hora, y no bloquea ningún marcaje. Es deliberado y es la
-- decisión de Felipe (2026-08-12): **medir y avisar, sin bloquear**. Un terminal
-- que se niega a registrar porque su reloj está corrido deja a una sede entera
-- sin poder fichar, y perder una marca real sigue siendo peor que tener una con
-- la hora movida — la hora se corrige después con rastro; la marca que no
-- existe no se recupera.
--
-- Tampoco sella nada en la base. Lo que el terminal haga con el desfase —
-- avisarlo en pantalla— vive en el navegador, porque es donde está el reloj
-- sospechoso.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   drop function if exists public.fn_ahora_servidor();
--   Revertir significa que el reloj de la Mac vuelva a ser incuestionable.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final.
-- ============================================================================

-- `stable` y no `immutable`: devuelve un valor distinto en cada transacción.
-- Y `now()` y no `clock_timestamp()`: el instante de la transacción es lo que
-- usa el resto del sistema —`server_received_at` entre otros—, así que el
-- desfase se mide contra el mismo reloj con el que se sellan las marcas.
create or replace function public.fn_ahora_servidor()
returns timestamptz
language sql
stable
as $function$
  select now();
$function$;

comment on function public.fn_ahora_servidor() is
  'La hora del servidor, para que el terminal compare con la suya y detecte que el reloj de la Mac se corrió. No lee ninguna tabla y no revela nada: por eso puede concederse al rol del terminal sin más.';

-- El terminal se autentica como `authenticated` (su propio usuario de
-- dispositivo), así que ahí va el grant. `anon` no: no hay razón para que algo
-- sin sesión pregunte la hora, y la regla de la casa desde la 0076 es que nada
-- nace abierto.
grant execute on function public.fn_ahora_servidor() to authenticated;
revoke execute on function public.fn_ahora_servidor() from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (230, 'el_terminal_puede_preguntar_la_hora')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
select
  fn_ahora_servidor() is not null                                   as responde,
  has_function_privilege('authenticated',
    'public.fn_ahora_servidor()'::regprocedure, 'EXECUTE')          as terminal_puede_preguntar,
  not has_function_privilege('anon',
    'public.fn_ahora_servidor()'::regprocedure, 'EXECUTE')          as anon_no_puede,
  -- Cuánto se desvían HOY las marcas ya registradas: la diferencia entre la
  -- hora que puso la Mac y la que el servidor anotó al recibirlas. Solo mira
  -- las de los últimos siete días y las que llegaron en menos de un minuto,
  -- para no contar como desfase el retraso legítimo de la cola offline.
  (select round(max(abs(extract(epoch from (m.server_received_at - m.timestamp_marca)))))
     from marcajes m
    where m.server_received_at > now() - interval '7 days'
      and abs(extract(epoch from (m.server_received_at - m.timestamp_marca))) < 60)
                                                                    as peor_desfase_seg_7d;
