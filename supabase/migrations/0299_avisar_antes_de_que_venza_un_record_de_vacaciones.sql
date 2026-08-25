-- ============================================================================
-- 0299_avisar_antes_de_que_venza_un_record_de_vacaciones.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que CAYLA se entere de que a alguien le va a vencer un récord de vacaciones
--   ANTES de que venza, y no el día de su liquidación.
--
-- ── POR QUÉ ─────────────────────────────────────────────────────────────────
--
-- El art. 23 del D. Leg. 713 manda una indemnización —otra remuneración entera—
-- cuando un récord de vacaciones vence sin gozarse. La 0283 dejó que la hoja de
-- liquidación lo AVISE, y esa fue la decisión correcta para la hoja: el sistema
-- no calcula esa indemnización porque tiene excepciones que no sabe distinguir.
--
-- Pero avisarlo en la liquidación llega tarde por definición. Cuando aparece
-- ahí, el récord ya venció y la indemnización ya se debe. La forma de que no
-- exista nunca es verlo con meses de antelación, que es exactamente lo que pidió
-- Felipe el 2026-08-24: «hay que evitar esto».
--
-- ── LA CUENTA NO SE VUELVE A ESCRIBIR ───────────────────────────────────────
--
-- `fn_vacaciones_resumen` ya calcula los días ganados, los tomados y el saldo,
-- con la cuenta acumulada correcta desde julio de 2026. Esta función la LLAMA y
-- solo le añade aritmética de fechas. Si mañana cambia la regla del saldo,
-- cambia en un sitio.
--
-- Y de paso queda dicho algo que se descubrió al construir esto: esa función
-- **no se muestra en ninguna pantalla**. La ruta /admin/vacaciones redirige a
-- Ausencias desde la 0101, y Ausencias no enseña el saldo. La función que sabe
-- lo que se le debe a cada quien no la ve nadie. Esta migración le da su primer
-- consumidor.
--
-- ── CÓMO SE CALCULA LA FECHA DE VENCIMIENTO ─────────────────────────────────
--
-- Un récord k va del aniversario k-1 al k, se GANA al cumplirse el aniversario
-- k, y debe gozarse antes del aniversario k+1. Si no, vence.
--
-- Los días tomados consumen los récords MÁS ANTIGUOS primero, así que los que
-- quedan pendientes son los más nuevos. De ahí:
--
--     dias_de_records_completos = 15 × años cumplidos
--     pendientes_de_esos        = max(0, dias_de_records_completos − tomados)
--     records_pendientes        = ceil(pendientes_de_esos / 15)
--     el más antiguo pendiente  = años_cumplidos − records_pendientes + 1
--     vence el                  = ingreso + (ese índice + 1) años
--
-- Comprobado con dos casos en la prueba 234: quien tomó sus 15 días de un récord
-- de dos, y quien no tomó ninguno —a esa el récord más antiguo ya le venció—.
--
-- SOLO CUENTA LOS RÉCORDS COMPLETOS. El trunco en curso no puede vencer: su año
-- para gozarlo ni siquiera ha empezado.
--
-- ── LO QUE HOY DEVUELVE ─────────────────────────────────────────────────────
--
-- Medido contra producción el 2026-08-24: de las 20 personas activas, las cuatro
-- con un año cumplido se tomaron EXACTAMENTE sus 15 días y las 16 restantes no
-- han cumplido el primer año. **Nadie tiene un récord pendiente.** Esta función
-- devuelve cero filas hoy, y ese es el estado bueno: existe para que siga así.
--
-- QUÉ ASUME
--   · md5 de partida de `fn_vacaciones_resumen`, que NO se toca:
--       9d15efaec6147c3fbd1357ec7e7020d4   5 212 chars
--
-- CÓMO SE REVIERTE
--   `drop function fn_vacaciones_por_vencer(int);` No toca tablas ni datos ni
--   ninguna función existente: solo agrega.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   select * from fn_vacaciones_por_vencer(90);
--   Hoy tiene que devolver cero filas. El día que devuelva una, hay algo que
--   hacer antes de esa fecha.
-- ============================================================================

create or replace function fn_vacaciones_por_vencer(p_dias_aviso int default 90)
returns table(
  persona_id       uuid,
  nombre           text,
  fecha_ingreso    date,
  dias_saldo       numeric,
  records_pendientes int,
  vence_el         date,
  dias_para_vencer int,
  ya_vencido       boolean
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_hoy date;
begin
  -- Mismo guard que `fn_vacaciones_resumen`, que es de donde salen los datos.
  -- Va explícito y no delegado: si mañana aquella se abriera a más roles, esto
  -- no debería abrirse solo.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver los records de vacaciones por vencer.';
  end if;

  v_hoy := fn_hoy_lima();

  return query
  with resumen as (
    -- LA CUENTA VIENE DE AHÍ. No se recalcula: se lee.
    select (e->>'persona_id')::uuid    as pid,
           (e->>'nombre')              as nom,
           (e->>'fecha_ingreso')::date as ingreso,
           (e->>'dias_tomados')::numeric as tomados,
           (e->>'dias_saldo')::numeric   as saldo
    from jsonb_array_elements(fn_vacaciones_resumen(v_hoy)) e
  ),
  cuenta as (
    select r.*,
           floor(extract(year from age(v_hoy, r.ingreso)))::int as anios
    from resumen r
  ),
  vencimiento as (
    select c.*,
           -- Días que vienen de récords COMPLETOS y siguen sin gozarse. El
           -- trunco en curso queda fuera: no puede vencer todavía.
           greatest(0, 15.0 * c.anios - c.tomados) as dias_completos_pend
    from cuenta c
  ),
  calculado as (
    select v.*,
           ceil(v.dias_completos_pend / 15.0)::int as recs_pend
    from vencimiento v
  )
  select
    c.pid,
    c.nom,
    c.ingreso,
    round(c.saldo, 1),
    c.recs_pend,
    (c.ingreso + make_interval(years => (c.anios - c.recs_pend + 2)))::date,
    ((c.ingreso + make_interval(years => (c.anios - c.recs_pend + 2)))::date - v_hoy)::int,
    ((c.ingreso + make_interval(years => (c.anios - c.recs_pend + 2)))::date <= v_hoy)
  from calculado c
  where c.recs_pend > 0
    and ((c.ingreso + make_interval(years => (c.anios - c.recs_pend + 2)))::date - v_hoy)::int <= p_dias_aviso
  order by 6, 2;
end;
$function$;

grant  execute on function fn_vacaciones_por_vencer(int) to authenticated;
revoke execute on function fn_vacaciones_por_vencer(int) from public, anon;

comment on function fn_vacaciones_por_vencer(int) is
  'Quien tiene un record de vacaciones que vence dentro de p_dias_aviso dias, o que ya vencio. La cuenta del saldo NO se recalcula aca: viene de fn_vacaciones_resumen. Existe para que la indemnizacion del art. 23 del D. Leg. 713 nunca llegue a existir, en vez de calcularla bien el dia del cese.';

insert into migraciones_aplicadas (numero, nombre)
values (299, 'avisar_antes_de_que_venza_un_record_de_vacaciones')
on conflict (numero) do nothing;
