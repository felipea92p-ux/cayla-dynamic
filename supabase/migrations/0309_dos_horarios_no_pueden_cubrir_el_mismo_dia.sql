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
-- **10 pares en 8 personas**, sobre 112 tramos de 23 personas (esa misma noche
-- ya eran 113 tramos y los mismos 10 pares). Y no son todos lo mismo:
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
-- **Pero no se pide que se confíe en eso.** El paso 1 lo COMPRUEBA sobre los
-- datos reales y aborta antes de tocar nada si no se cumple.
--
-- ── POR QUÉ ESTE ARCHIVO CAMBIÓ DESPUÉS DE FUSIONARSE ───────────────────────
--
-- La primera versión demostraba lo mismo de otra forma: guardaba en una tabla
-- TEMPORAL qué tramo mandaba para cada persona y cada día, hacía el arreglo,
-- lo recalculaba y comparaba. Pasó las 1652 pruebas del CI y murió al pegarla
-- en el SQL Editor de Supabase, el 2026-08-26:
--
--     ERROR: 42P01: relation "_horario_antes" does not exist
--
-- El SQL Editor no le deja ver esa tabla al bloque que la lee. No sé por qué
-- mecanismo exacto —y no hace falta saberlo—, pero sí se midieron las dos cosas
-- que importan, con `scripts/sql-manual/que_paso_con_la_0309.sql`:
--
--   1. La tabla temporal no sobrevive de una sentencia a la siguiente.
--   2. Cuando algo falla, el editor DESHACE todo. Producción quedó intacta:
--      los 10 solapes seguían ahí, sin candado y sin fila en
--      `migraciones_aplicadas`.
--
-- La segunda es la buena noticia: se pudo reintentar limpio. Pero enseña algo
-- que este repo ya sabía y que aquí se pagó — un freno que depende del entorno
-- donde corre no es un freno. Y había otro defecto de fondo, independiente del
-- SQL Editor: la versión vieja **cambiaba los datos y DESPUÉS comprobaba**. Si
-- la comprobación fallaba, el `rollback` la salvaba; pero pedirle a la red que
-- te salve no es lo mismo que no saltar.
--
-- Esta versión comprueba PRIMERO, sin tabla temporal y sin depender de nada del
-- entorno: para cada día que un tramo va a perder, pregunta si algún tramo
-- posterior ya lo cubría. Y esa consulta no es teoría — se corrió contra
-- producción el 2026-08-26 antes de escribir esto, y devolvió **0**.
--
-- Se edita el archivo en vez de escribir una 0311 que la corrija porque la 0309
-- NUNCA se aplicó en ningún sitio: `migraciones_aplicadas` no tiene su fila. No
-- hay nada que corregir hacia atrás, solo un archivo que todavía no sirve.
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


-- ── 1 · La comprobación, ANTES de tocar un solo dato ────────────────────────
--
-- Un tramo A que se pisa con otros va a perder los días que van desde el
-- arranque del más cercano hasta su propio cierre. Para cada uno de esos días
-- se pregunta: ¿hay algún tramo que empiece DESPUÉS de A y que cubra ese día?
--
--   · Si lo hay, A ya estaba tapado ahí. Perder ese día no cambia nada, porque
--     manda el de `vigente_desde` más reciente y no era A.
--   · Si NO lo hay, A era quien mandaba ese día. Acortarlo dejaría a esa
--     persona sin horario ese día — y de ahí sale si se le cuenta falta.
--
-- Basta con mirar los días que se pierden: los demás conservan exactamente la
-- misma cobertura, porque el `update` de abajo solo ACORTA.

do $$
declare v_dias int;
begin
  with por_perder as (
    select a.id, a.persona_id, a.vigente_desde,
           a.vigente_hasta as cierre,
           (select min(b.vigente_desde)
              from horarios_asignados b
             where b.persona_id    = a.persona_id
               and b.vigente_desde > a.vigente_desde) as arranque_del_siguiente
      from horarios_asignados a
     where a.vigente_hasta is not null          -- el abierto no se toca
  )
  select count(*) into v_dias
    from por_perder t
   cross join lateral generate_series(t.arranque_del_siguiente, t.cierre,
                                      interval '1 day') g
   where t.arranque_del_siguiente is not null
     and t.cierre >= t.arranque_del_siguiente   -- solo si de verdad se pisan
     and not exists (
       select 1
         from horarios_asignados c
        where c.persona_id     = t.persona_id
          and c.vigente_desde  > t.vigente_desde
          and c.vigente_desde <= g::date
          and (c.vigente_hasta is null or c.vigente_hasta >= g::date)
     );

  if v_dias > 0 then
    raise exception 'El arreglo le cambiaría el horario efectivo a alguien en % día(s)-persona. NO se aplica nada. Estos datos no son los que se midieron el 2026-08-26: hay un tramo que MANDA en días que perdería, así que acortarlo dejaría a esa persona sin horario esos días — y de ahí sale si se le cuenta falta. Míralo con scripts/sql-manual/que_paso_con_la_0309.sql, que cuenta lo mismo sin escribir nada.', v_dias;
  end if;
end
$$;


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


-- ── 3 · El candado, ahora que se puede ──────────────────────────────────────
--
-- Misma forma que el de `asignaciones_salario` (0024). El rango es inclusivo en
-- los dos extremos —'[]'— porque `vigente_hasta` es el último día vigente, no
-- el primero que ya no lo está. Un tramo abierto llega hasta 'infinity'.
--
-- Si algo se hubiera escapado al paso 1, este `alter` falla y no queda nada a
-- medias: el SQL Editor deshace la pegada entera, comprobado el 2026-08-26.

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


insert into migraciones_aplicadas (numero, nombre)
values (309, 'dos_horarios_no_pueden_cubrir_el_mismo_dia')
on conflict (numero) do nothing;
