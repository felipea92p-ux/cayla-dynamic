-- ============================================================================
-- 0107 — Los conceptos ya registrados vuelven a llamarse por su nombre legal.
--
-- QUÉ PASABA. El PR de los nombres legales cambió la etiqueta que el programa
-- ESCRIBE al registrar una gratificación o una CTS, pero movimientos_planilla
-- guarda el concepto como TEXTO LIBRE en el momento de crearlo. Así que los
-- movimientos que ya existían se quedaron con el texto viejo:
--
--   Chiara  →  «Gratificación ene-jun 2026»    (registrada después del cambio)
--   Sandra  →  «Bono Gratitud ene-jun 2026»    (registrada antes)
--
-- Dos personas, el mismo concepto, dos nombres distintos en documentos que se
-- entregan. Y el nombre viejo es el problemático: llamar bono a la gratificación
-- disfraza un derecho de ley como una liberalidad.
--
-- QUÉ HACE. Reescribe el texto de los movimientos ya registrados:
--
--   «Bono Gratitud»      →  «Gratificación»
--   «Bono Comprometidos» →  «CTS»
--
-- Solo la parte del nombre. El detalle que escribió la persona se conserva:
-- «Bono Gratitud ene-jun 2026» queda «Gratificación ene-jun 2026».
--
-- POR QUÉ VA COMO MIGRACIÓN Y NO COMO UN UPDATE A MANO. Es un cambio de datos
-- sobre registros de pago: conviene que quede registrado quién lo hizo y cuándo,
-- que sea idempotente, y que no dependa de que alguien pegue bien dos consultas
-- a las 4 de la mañana.
--
-- OJO: CAMBIA EL TEXTO DE BOLETAS DE PERIODOS YA PAGADOS. Si una boleta con el
-- nombre viejo ya se entregó, al reimprimirla dirá «Gratificación». Es lo
-- correcto —el nombre nuevo es el que corresponde por ley— pero conviene saberlo
-- antes de correrlo, no después. La foto del pago (0096) congela los TOTALES, no
-- los textos, así que ningún monto se mueve.
--
-- Usa regexp_replace con 'gi': insensible a mayúsculas, por si alguien escribió
-- «bono gratitud» a mano. Y es idempotente porque después de correrla ya no queda
-- ningún texto que coincida con el patrón.
--
-- LA RAÍZ, QUE ESTO NO ARREGLA: el concepto es texto libre. Si se guardara la
-- CATEGORÍA (gratificacion, cts) y el nombre se decidiera al mostrarlo, cambiar
-- una etiqueta arreglaría el pasado y el futuro sin ninguna migración. Eso es un
-- cambio más grande y queda anotado aquí para cuando toque.
-- Decidido con Felipe el 2026-07-28.
-- ============================================================================

do $$
declare
  v_grati int;
  v_cts   int;
  v_resto int;
begin
  with cambiadas as (
    update movimientos_planilla
       set concepto = regexp_replace(concepto, 'Bono\s+Gratitud', 'Gratificación', 'gi')
     where concepto ~* 'Bono\s+Gratitud'
    returning 1
  )
  select count(*) into v_grati from cambiadas;

  with cambiadas as (
    update movimientos_planilla
       set concepto = regexp_replace(concepto, 'Bono\s+Comprometidos', 'CTS', 'gi')
     where concepto ~* 'Bono\s+Comprometidos'
    returning 1
  )
  select count(*) into v_cts from cambiadas;

  raise notice '0107: % gratificaciones y % CTS renombradas.', v_grati, v_cts;

  -- Si queda algún concepto que empieza por «Bono » y menciona algo que suena a
  -- derecho de ley, se avisa en vez de tocarlo: no se adivina sobre registros de
  -- pago. Que quede escrito en el log para revisarlo a mano.
  select count(*) into v_resto
  from movimientos_planilla
  where concepto ~* '^bono\s+(grati|cts|vacacion|asignaci)';

  if v_resto > 0 then
    raise notice '0107: OJO, quedan % conceptos que empiezan por «Bono» y suenan a derecho de ley. Revísalos a mano.', v_resto;
  end if;
end $$;

insert into migraciones_aplicadas (numero, nombre)
values (107, 'conceptos_con_su_nombre_legal')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
