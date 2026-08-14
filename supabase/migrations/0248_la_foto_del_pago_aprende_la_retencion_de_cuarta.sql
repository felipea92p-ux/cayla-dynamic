-- ============================================================================
-- 0248_la_foto_del_pago_aprende_la_retencion_de_cuarta.sql
-- ============================================================================
-- QUÉ DESBLOQUEA
--   Que «Marcar como PAGADO» siga funcionando el día que alguien tenga
--   configurada la retención de cuarta categoría. Hoy no funcionaría: fallaría
--   para las TREINTA personas del periodo, no solo para el locador retenido.
--
-- QUÉ ASUME
--   Que la 0245 está aplicada y que `fn_planilla_calcular` devuelve la clave
--   `retencion_4ta` en el JSON de cada persona. Confirmado en producción el
--   2026-08-14: la 0245 figura en `migraciones_aplicadas`.
--
-- ── POR QUÉ, MEDIDO ─────────────────────────────────────────────────────────
--
-- La 0245 le restó un término nuevo al total —la retención de cuarta, art. 71
-- de la LIR— y no amplió el candado de la foto del pago. `chk_foto_cuadra`
-- exige que el total sea exactamente la suma de once columnas conocidas:
--
--     total = pago_base + monto_feriados + monto_plus + asignacion_familiar
--           + monto_movilidad + monto_educacion - descuento_pension
--           + monto_sobretiempo + bonos - descuentos
--
-- Con una retención de S/80 sobre S/1,000, el total vale 920 y la suma da 1000.
-- Reproducido en BEGIN … ROLLBACK contra el Postgres local:
--
--     ANTES   · RECHAZADA -> el cierre se atasca. El fallo es real.
--     DESPUES · ENTRO. El cierre pasa y la foto guarda la retencion.
--     DESPUES · quien NO tiene retencion cuadra como siempre.
--     guardado en la foto: 80.00
--
-- **Y EL BLOQUEO ES TOTAL, NO DE UNA FILA.** `fn_planilla_congelar` inserta las
-- ~30 filas del periodo en una sola sentencia: si una viola el CHECK, no se
-- congela NINGUNA y el periodo no se puede marcar como pagado. Lo mismo le pasa
-- a `fn_repagar_periodo`.
--
-- Medido en producción el 2026-08-14: la 0245 está pegada, la foto NO conoce la
-- retención, y CERO personas la tienen configurada. O sea: la trampa está
-- armada y no ha saltado. Salta el día que se le configure a Carlos, Claudia o
-- Catherine — que es exactamente para lo que se escribió la 0245.
--
-- ── ES LA TERCERA VEZ, Y ESO ES LO QUE HAY QUE MIRAR ────────────────────────
--
--   0127  la movilidad, la educación y la pensión entraron al total y el
--         candado no las conocía
--   0201  el sobretiempo, otra vez, con estas mismas palabras en su cabecera
--   0248  la retención de cuarta
--
-- No es descuido de nadie: es que el término del total y la columna de la foto
-- viven en dos sitios y nada obliga a tocarlos juntos. **Quien añada un término
-- nuevo al `total` tiene que preguntarse por el candado de la foto**, y hoy no
-- hay nada que se lo recuerde salvo que el cierre reviente en el peor momento.
-- La prueba 188 vigila que no vuelva a pasar sin avisar.
--
-- ── POR QUÉ UNA COLUMNA GENERADA Y NO REESCRIBIR LA FUNCIÓN ─────────────────
--
-- La 0201 resolvió su caso reescribiendo el insert de `fn_planilla_congelar`.
-- Aquí no hace falta, y evitarlo vale mucho: la definición vigente de esa
-- función vive en la 0244, que está a medio reescribir por otra sesión.
-- Copiarla ahora sería copiar un archivo en movimiento.
--
-- La foto ya guarda la boleta entera en `fila` jsonb, y la tabla ya usa este
-- patrón —`costo_total` es una columna generada—. Así que la retención se
-- DERIVA de lo que ya está guardado:
--
--   · no toca ninguna función, así que no puede revertir el trabajo de nadie
--   · no hace falta pedir ningún md5 de partida
--   · las filas viejas la calculan sola en 0.00 (no tienen esa clave), así que
--     el candado nuevo las sigue aceptando igual
--   · y no se puede desincronizar del JSON: es el mismo dato, no una copia
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--     alter table planilla_pagada_detalle drop constraint chk_foto_cuadra;
--     alter table planilla_pagada_detalle add constraint chk_foto_cuadra check (
--       total = pago_base + monto_feriados + monto_plus + asignacion_familiar
--             + monto_movilidad + monto_educacion - descuento_pension
--             + monto_sobretiempo + bonos - descuentos);
--     alter table planilla_pagada_detalle drop column retencion_4ta;
--   Revertir significa volver a dejar el cierre del mes a merced de que nadie
--   configure una retención.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Las tres columnas tienen que decir SÍ.
-- ============================================================================

-- ── 1 · La columna, derivada de lo que la foto ya guarda ────────────────────
-- Idempotente: se pega a mano, y una mano se equivoca.
alter table public.planilla_pagada_detalle
  add column if not exists retencion_4ta numeric(12,2)
  generated always as (round(coalesce((fila->>'retencion_4ta')::numeric, 0), 2)) stored;

comment on column public.planilla_pagada_detalle.retencion_4ta is
  'Retención de 4ta categoría congelada con el pago (art. 71 LIR, migración 0245). Se DERIVA de '
  'fila->>''retencion_4ta'', no se escribe: así no puede desincronizarse del JSON de la boleta ni '
  'obliga a tocar fn_planilla_congelar. Entra en chk_foto_cuadra restando, como descuento_pension.';

-- ── 2 · El candado, que ahora la conoce ─────────────────────────────────────
alter table public.planilla_pagada_detalle
  drop constraint if exists chk_foto_cuadra;

alter table public.planilla_pagada_detalle
  add constraint chk_foto_cuadra check (
    total = pago_base + monto_feriados + monto_plus + asignacion_familiar
          + monto_movilidad + monto_educacion - descuento_pension
          + monto_sobretiempo + bonos - descuentos - retencion_4ta);

comment on constraint chk_foto_cuadra on public.planilla_pagada_detalle is
  'La foto del pago tiene que cuadrar consigo misma. Cada término que se le sume o reste al total '
  'en fn_planilla_calcular tiene que tener aquí su columna: 0127 (movilidad, educación, pensión), '
  '0201 (sobretiempo), 0248 (retención de 4ta). Si no, el cierre del mes aborta para TODO el '
  'periodo, porque fn_planilla_congelar inserta las ~30 filas en una sola sentencia.';

insert into migraciones_aplicadas (numero, nombre)
values (248, 'la_foto_del_pago_aprende_la_retencion_de_cuarta')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'planilla_pagada_detalle'
      and column_name = 'retencion_4ta') = 1
    as la_foto_conoce_la_retencion,
  (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'chk_foto_cuadra'
      and conrelid = 'public.planilla_pagada_detalle'::regclass) like '%retencion_4ta%'
    as el_candado_la_resta,
  -- Y la otra mitad: que el candado NO se haya vuelto un adorno. Sigue exigiendo
  -- que el total cuadre — un candado que acepta cualquier cosa no es un candado.
  (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'chk_foto_cuadra'
      and conrelid = 'public.planilla_pagada_detalle'::regclass) like '%pago_base%'
    as sigue_exigiendo_que_cuadre;
