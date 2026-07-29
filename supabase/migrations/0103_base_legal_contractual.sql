-- ============================================================================
-- 0103 — Base legal contractual: separar el sueldo fijo garantizado del
--        potencial del rango.
--
-- Hasta ahora la boleta interna mostraba un solo número —el salario del rango,
-- que vive en asignaciones_salario (ver 0019)— etiquetado «S/ X/mes». Ese
-- número mezcla dos cosas que legalmente NO son la misma:
--
--   · La remuneración básica ordinaria: fija, garantizada, la que se declara
--     en PLAME y sobre la que se calculan CTS, gratificaciones y vacaciones.
--   · El potencial del rango: lo que la persona alcanza según rendimiento.
--
-- Esta migración agrega la primera. La segunda ya existía (salario_ref).
--
-- ── POR QUÉ ESTA COLUMNA NO HACE BACKFILL ───────────────────────────────────
-- Se agrega SIN default y solo después se le pone el default. Así las filas que
-- ya existen quedan en NULL, en vez de heredar 1,130. Es deliberado:
--
--   · A quien ya trabaja aquí no se le puede reescribir la base con un default.
--     Si su PLAME dice 1,450 y esta columna dijera 1,130, la boleta interna
--     contradiría al documento oficial — que es peor que no decir nada.
--   · Quien entre desde ahora recibe 1,130 automáticamente.
--   · Mientras esté en NULL, la boleta NO imprime la línea «Base Legal
--     Contractual». No afirmamos una base que nadie confirmó.
--
-- Para el equipo actual el valor hay que fijarlo a mano, persona por persona, e
-- igual al que figura en su PLAME. Todavía no existe pantalla para eso: hoy
-- solo se puede por SQL.
--
-- ── OJO CON LA RMV ──────────────────────────────────────────────────────────
-- 1,130 es el default porque es la RMV que se tomó como referencia al escribir
-- esto (2026-07-28), sin verificar contra la norma vigente. La columna NO se
-- valida contra la RMV: si la RMV sube, este default queda por debajo del
-- mínimo legal y hay que actualizarlo a mano. Si eso importa, el candado tiene
-- que ser una migración nueva, no un comentario.
--
-- Decidido con Felipe el 2026-07-28.
-- ============================================================================

alter table personas
  add column if not exists sueldo_base_legal numeric(10,2);

-- El default va aparte, DESPUÉS de crear la columna: si fuera en el mismo
-- add column, Postgres rellenaría con 1,130 todas las filas existentes, que es
-- exactamente lo que no queremos.
alter table personas
  alter column sueldo_base_legal set default 1130.00;

-- Idempotente: esta migración debe poder pegarse dos veces sin romperse.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'personas_sueldo_base_legal_positivo'
  ) then
    alter table personas
      add constraint personas_sueldo_base_legal_positivo
      check (sueldo_base_legal is null or sueldo_base_legal > 0);
  end if;
end $$;

comment on column personas.sueldo_base_legal is $$Remuneración básica ordinaria fija pactada: la que se declara en PLAME y sirve de base a CTS, gratificaciones y vacaciones. NULL = no confirmada todavía, y la boleta interna omite la línea en ese caso. Distinta de asignaciones_salario, que guarda el potencial del rango.$$;

insert into migraciones_aplicadas (numero, nombre)
values (103, 'base_legal_contractual')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
