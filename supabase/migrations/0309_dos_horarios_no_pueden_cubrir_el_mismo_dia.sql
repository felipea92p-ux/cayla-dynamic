-- ============================================================================
-- 0309 — Dos horarios no pueden cubrir el mismo día
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una persona no pueda tener dos tramos de horario vigentes el mismo día.
--   Y que arreglar los que hoy se pisan NO le cambie el horario a nadie.
--
-- QUÉ ASUME
--   · Que `horarios_asignados` no tiene ningún trigger — comprobado en
--     `pg_trigger`. Por eso un `update` acá no dispara recálculos de jornada.
--   · Que quien decide, cuando dos tramos cubren el mismo día, es el de
--     `vigente_desde` MÁS RECIENTE. Lo hacen igual las dos implementaciones:
--     `fn_recalcular_jornada` con `order by vigente_desde desc limit 1`, y
--     `horarioVigente` en `apps/web/lib/admin/jornada-esperada.ts:67-75`.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- `horarios_asignados` guarda el horario por tramos de vigencia, pero lo único
-- que impide duplicados es un índice PARCIAL —`idx_horario_vigente_unico`, solo
-- `where vigente_hasta is null`—, o sea que protege el tramo ABIERTO y nada
-- más. Dos tramos cerrados pueden pisarse, y uno cerrado puede solaparse con el
-- abierto.
--
-- Cuando eso pasa, quien decide es un `order by vigente_desde desc limit 1`.
-- Elige uno **sin avisar**, y de esa elección sale qué se esperaba de esa
-- persona ese día: si llegó tarde, si salió antes, o si faltó. El diagnóstico ya
-- estaba escrito en la cabecera de la 0209 y nadie había vuelto a él.
--
-- ── MEDIDO EN PRODUCCIÓN, ANTES DE ESCRIBIR ESTO ────────────────────────────
--
-- Con `scripts/sql-manual/hay_horarios_solapados.sql`, el 2026-08-26:
-- **10 pares en 8 personas**, sobre 112 tramos de 23 personas. Y no son todos
-- lo mismo:
--
--   · NUEVE se pisan UN SOLO DÍA, siempre con el mismo patrón: el tramo
--     anterior cierra el mismo día en que empieza el siguiente. Es una
--     confusión de convención —`vigente_hasta` es inclusivo y se usó como si
--     fuera «el día en que arranca el próximo»—, no dos horarios de verdad.
--   · UNO es real: Chiara Flores, con `27/07 → 01/08` y `29/07 → 01/08`
--     pisándose cuatro días.
--
-- ── POR QUÉ ARREGLARLO NO LE CAMBIA EL HORARIO A NADIE ──────────────────────
--
-- Porque gana siempre el de `vigente_desde` más reciente. O sea que el tramo
-- que empieza antes **ya estaba tapado** en los días del solape: cerrarlo la
-- víspera del siguiente no le quita cobertura a ningún día que hoy esté
-- cubriendo de verdad.
--
-- Se comprobó caso por caso, incluido el de Chiara: hoy el de `29/07` manda del
-- 29 al 01, así que el de `27/07` solo cubre efectivamente el 27 y el 28 — que
-- es exactamente lo que va a cubrir después.
--
-- **Pero no se pide que se confíe en eso.** La migración lo DEMUESTRA sobre los
-- datos reales, abajo: guarda qué tramo manda para cada persona y cada día del
-- historial, hace el arreglo, vuelve a calcularlo, y **aborta si cambió una sola
-- casilla**. Si alguna vez se pega sobre datos distintos a los medidos y el
-- arreglo sí movería algo, no se aplica.
--
-- ── LO QUE NO TOCA, A PROPÓSITO ─────────────────────────────────────────────
--
-- El tramo ABIERTO (`vigente_hasta is null`) no se cierra nunca. Cerrarlo por
-- solaparse con uno posterior le quitaría la cobertura de todo lo que viene
-- DESPUÉS de ese otro, que es justo lo contrario de lo que se busca. Hoy no hay
-- ningún caso así —los diez pares son entre tramos cerrados—, y si algún día lo
-- hubiera, el `EXCLUDE` del final se negará a crearse y habrá que mirarlo a
-- mano. Que falle ahí es correcto: es un solape que sí necesita una decisión.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   `alter table horarios_asignados drop constraint horarios_sin_solape;`
--   Las fechas corregidas se quedan, y deben quedarse: representan lo que el
--   sistema ya venía aplicando. Volver a alargarlas restauraría la ambigüedad.
--
-- ============================================================================


-- ── 1 · Qué tramo manda hoy, día por día ────────────────────────────────────
--
-- El universo son todos los días entre el primer tramo y el último, por persona.
-- Con 112 tramos y 23 personas son unas decenas de miles de casillas: nada.

-- Tabla temporal SIN `on commit drop`, a propósito. El SQL Editor envuelve todo
-- en una transacción y ahí daría igual, pero pegada sentencia a sentencia —o
-- aplicada con `psql -f`, como la corre el CI y como se probó acá— cada una es
-- su propia transacción y la tabla se borraría ANTES de que el bloque de abajo
-- pudiera leerla. Se borra a mano al final.
drop table if exists _horario_antes;
create temporary table _horario_antes as
with span as (
  select min(vigente_desde) as ini,
         greatest(max(coalesce(vigente_hasta, current_date)), current_date) as fin
    from horarios_asignados
),
dias as (
  select p.persona_id, d::date as fecha
    from (select distinct persona_id from horarios_asignados) p
   cross join span s
   cross join lateral generate_series(s.ini, s.fin, interval '1 day') d
)
select d.persona_id, d.fecha,
       (select h.id
          from horarios_asignados h
         where h.persona_id = d.persona_id
           and h.vigente_desde <= d.fecha
           and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
         order by h.vigente_desde desc
         limit 1) as tramo
  from dias d;


-- ── 2 · El arreglo: cerrar la víspera del siguiente ─────────────────────────
--
-- Solo tramos CERRADOS, y solo acortando. `min(...)` porque un tramo puede
-- pisarse con más de uno: el límite lo pone el más cercano.

update horarios_asignados h
   set vigente_hasta = s.limite
  from (
    select a.id, min(b.vigente_desde) - 1 as limite
      from horarios_asignados a
      join horarios_asignados b
        on b.persona_id     = a.persona_id
       and b.vigente_desde  > a.vigente_desde
     where a.vigente_hasta is not null          -- el abierto no se toca
       and a.vigente_hasta >= b.vigente_desde   -- solo si de verdad se pisan
     group by a.id
  ) s
 where h.id = s.id
   and h.vigente_hasta <> s.limite;


-- ── 3 · La prueba: que no se movió una sola casilla ─────────────────────────

do $$
declare v_cambios int;
begin
  with despues as (
    select a.persona_id, a.fecha,
           (select h.id
              from horarios_asignados h
             where h.persona_id = a.persona_id
               and h.vigente_desde <= a.fecha
               and (h.vigente_hasta is null or h.vigente_hasta >= a.fecha)
             order by h.vigente_desde desc
             limit 1) as tramo
      from _horario_antes a
  )
  select count(*) into v_cambios
    from _horario_antes a
    join despues d on d.persona_id = a.persona_id and d.fecha = a.fecha
   where a.tramo is distinct from d.tramo;

  if v_cambios > 0 then
    raise exception 'El arreglo cambiaría el horario efectivo en % día(s)-persona. NO se aplica nada. Estos datos no son los que se midieron el 2026-08-26: hay un solape que sí exige decidir cuál tramo vale, y esa decisión cambia si a alguien se le contó tardanza o falta. Míralo con scripts/sql-manual/hay_horarios_solapados.sql antes de volver a intentarlo.', v_cambios;
  end if;

  raise notice '0309 · horario efectivo idéntico en todas las casillas: el arreglo no le cambió el horario a nadie.';
end
$$;


-- ── 4 · El candado, ahora que se puede ──────────────────────────────────────
--
-- Misma forma que el de `asignaciones_salario` (0024). El rango es inclusivo en
-- los dos extremos —'[]'— porque `vigente_hasta` es el último día vigente, no
-- el primero que ya no lo está. Un tramo abierto llega hasta 'infinity'.

alter table horarios_asignados drop constraint if exists horarios_sin_solape;
alter table horarios_asignados add constraint horarios_sin_solape
  exclude using gist (
    persona_id with =,
    daterange(vigente_desde, coalesce(vigente_hasta, 'infinity'::date), '[]') with &&
  );

comment on constraint horarios_sin_solape on horarios_asignados is
  'Una persona no puede tener dos tramos de horario vigentes el mismo día. Sin '
  'esto, quien decidía era un «order by vigente_desde desc limit 1» que elegía '
  'uno en silencio — y de ahí sale si a alguien se le cuenta tardanza o falta '
  '(0309). El índice parcial idx_horario_vigente_unico solo cuidaba el tramo '
  'abierto.';


drop table if exists _horario_antes;

insert into migraciones_aplicadas (numero, nombre)
values (309, 'dos_horarios_no_pueden_cubrir_el_mismo_dia')
on conflict (numero) do nothing;
