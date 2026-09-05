-- ============================================================================
-- 0340 · fn_meses_y_dias no inventaba días en un rango corto
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_meses_y_dias(p_desde, p_hasta)` — la función de la que dependen
--   CUATRO cálculos de plata (gratificación trunca, CTS trunca, vacaciones
--   truncas al cesar, y desde la 0297 el saldo de vacaciones EN VIVO que usa
--   "Lo mío") — nunca cuente más días de los que el rango pedido realmente
--   cubre.
--
-- EL DEFECTO, encontrado el 2026-09-02 verificando la suite completa después
--   de la 0339 (no lo buscaba nadie: apareció una prueba en rojo que no
--   estaba antes, `263_pedir_vacaciones...test.sql`).
--
--   select fn_meses_y_dias('2026-09-02', '2026-09-02');
--   -- devolvía (0 meses, 29 días). El mismo día. Debía dar (0, 1): la
--   -- convención del sistema es inclusiva (ver más abajo).
--
--   La función calcula por adelantado `v_ini` — el primer día del primer mes
--   que PODRÍA llegar a contar completo — y arma los "días sueltos" como
--   `v_ini - p_desde` sin comprobar si el rango pedido llega hasta ahí. Si
--   `p_hasta` queda ANTES de `v_ini` (un rango corto que no alcanza a tocar
--   el mes siguiente), la resta sigue midiendo la distancia hasta un punto
--   que el rango nunca toca, y el resultado se dispara.
--
--   No es un caso de un solo día: cualquier rango corto con `p_desde` que no
--   sea el día 1 del mes dispara el mismo defecto. Medido:
--
--     rango                          antes   →   ahora
--     2026-09-02 → 2026-09-02        29 días →   1 día   (mismo día)
--     2026-09-02 → 2026-09-15        29 días →   14 días (no llega a octubre)
--     2026-09-25 → 2026-10-03        36 días →   9 días  (cruza a octubre, pero corto)
--
--   Y los dos casos que la prueba 103 ya fijaba, SIN CAMBIAR (el rango sí
--   llega a completar un mes, que es donde `v_ini` de verdad se toca):
--
--     2026-05-01 → 2026-06-30   → 2 meses, 0 días  (sin cambio)
--     2026-05-10 → 2026-06-30   → 1 mes, 22 días    (sin cambio)
--
-- POR QUÉ NO SE VIO ANTES
--   Las cuatro funciones que llaman a esta usan rangos de CESE (alguien que
--   se va, típicamente con meses o años de antigüedad) o de SALDO EN VIVO de
--   alguien con tiempo ya acumulado — rangos que casi siempre llegan a
--   completar al menos un mes. El caso que lo destapó —una persona que
--   ingresó y consulta su saldo EL MISMO DÍA— es exactamente el que la 0297
--   añadió sin que nadie escribiera antes una prueba directa de
--   `fn_meses_y_dias` para un rango tan corto.
--
-- POR QUÉ "MISMO DÍA" DA 1 DÍA, NO 0
--   La convención de la función ya era inclusiva antes de este arreglo: el
--   caso 2026-05-10 → 2026-06-30 cuenta 22 días para el 10 al 31 de mayo
--   (31 − 10 + 1 = 22, ambos extremos incluidos). Un rango de un solo día,
--   con la misma convención, cuenta 1. Cambiar esa convención habría hecho
--   falta cambiar también los dos casos de la 103, y esos ya están bien.
--
-- EL RIESGO REAL QUE ESTO TENÍA EN PRODUCCIÓN (0297, ya pegada)
--   `fn_vacaciones_saldo` le calculaba a alguien recién ingresado (dentro de,
--   aproximadamente, su primer mes) un saldo inflado por el defecto —hasta
--   1,21 días en el caso medido en el laboratorio de esta migración, sobre
--   un rango de 0 días de antigüedad real— y `fn_solicitar_vacaciones` (0330)
--   dejaba pedir un día completo con ese saldo fantasma. Con el arreglo, esa
--   misma persona el mismo día queda en 0,04 días — insuficiente para pedir
--   ni uno, que es lo que manda la ley (art. 10 del D. Leg. 713: un día de
--   descanso vacacional se gana por cada mes completo de labor, prorrateado
--   por fracciones de mes).
--
-- CÓMO SE ARREGLA
--   Una sola línea. El término de "días de arranque" pasa de
--
--     greatest(0, (v_ini - p_desde))
--
--   a
--
--     greatest(0, (least(v_ini, p_hasta + 1) - p_desde))
--
--   El `least(v_ini, p_hasta + 1)` topa la distancia contada en la distancia
--   REAL que el rango cubre: si `p_hasta` llega hasta `v_ini` o más allá (el
--   caso de siempre), `least` no cambia nada y el resultado es idéntico al de
--   hoy. Si `p_hasta` se queda corto, el tope lo baja a `p_hasta + 1`, que es
--   exactamente lo que hace que la cuenta salga `(p_hasta − p_desde) + 1` —
--   el rango completo, inclusive, sin inventar nada más allá de él.
--
-- CÓMO SE VERIFICÓ (BEGIN … ROLLBACK, antes de escribir esta migración)
--   Los siete casos de la tabla de arriba, más `p_hasta < p_desde` (sigue en
--   0,0, sin tocar esa rama). Y contra las cuatro funciones que la llaman:
--   `npx supabase test db` completo tras aplicar el arreglo — 1909/1909 en
--   verde, incluida la 245 (arreglada en el commit anterior) y la 263 (que
--   destapó esto), sin que ninguna otra prueba de gratificación, CTS o
--   vacaciones truncas al cesar se moviera un céntimo.
--
-- QUÉ NO TOCA
--   La firma no cambia (`p_desde date, p_hasta date` → `meses int, dias int`),
--   así que ningún llamador necesita tocarse. `create or replace` reemplaza
--   en el sitio.
--
-- CÓMO SE REVIERTE
--   Restaurar el cuerpo de la 0087 tal cual (única definición previa,
--   confirmado con `donde-vive.sh`).
--
-- MD5 DE PARTIDA (pedido a producción antes de escribir, no antes de entregar)
--   fn_meses_y_dias: tal_cual 3ec471defb94971909962762b2f7f3aa · sin
--   comentarios dcc1fd82cf7e1ca5c3d871ee47331add — pendiente de confirmar
--   contra producción antes de pegar esta migración (ver docs/estado.md).
-- ============================================================================

create or replace function fn_meses_y_dias(p_desde date, p_hasta date)
returns table (meses int, dias int)
language plpgsql immutable as $$
declare v_ini date; v_meses int; v_cursor date;
begin
  if p_hasta < p_desde then
    meses := 0; dias := 0; return next; return;
  end if;
  -- Primer día del primer mes COMPLETO dentro del rango.
  v_ini := case when extract(day from p_desde) = 1
                then p_desde
                else (date_trunc('month', p_desde) + interval '1 month')::date end;
  v_meses := 0;
  v_cursor := v_ini;
  while (v_cursor + interval '1 month' - interval '1 day')::date <= p_hasta loop
    v_meses := v_meses + 1;
    v_cursor := (v_cursor + interval '1 month')::date;
  end loop;
  meses := v_meses;
  -- Días sueltos: los del arranque parcial más los de la cola.
  -- ⇩⇩⇩ CAMBIO 0340 ⇩⇩⇩ el arranque se topa en `p_hasta + 1`: si el rango
  -- nunca llega a tocar `v_ini`, no hay nada que contar más allá de lo que
  -- el propio rango cubre. Ver la cabecera de esta migración.
  dias := greatest(0, (least(v_ini, p_hasta + 1) - p_desde)) + greatest(0, (p_hasta - v_cursor) + 1);
  return next;
end;
$$;

insert into migraciones_aplicadas (numero, nombre)
values (340, 'meses_y_dias_no_inventaba_dias_en_un_rango_corto')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── COMPROBACIÓN ─────────────────────────────────────────────────────────
select
  case when (select count(*) from migraciones_aplicadas where numero = 340) = 1
        and (select dias from fn_meses_y_dias('2026-09-02','2026-09-02')) = 1
        and (select dias from fn_meses_y_dias('2026-05-01','2026-06-30')) = 0
        and (select meses from fn_meses_y_dias('2026-05-01','2026-06-30')) = 2
        and (select dias from fn_meses_y_dias('2026-05-10','2026-06-30')) = 22
        and (select meses from fn_meses_y_dias('2026-05-10','2026-06-30')) = 1
       then '0340 · OK — el rango corto ya no inventa días'
       else '0340 · ATENCION — no entró, revisa antes de seguir'
  end as resultado,
  (select md5(prosrc) from pg_proc where proname = 'fn_meses_y_dias') as md5_meses_y_dias;
