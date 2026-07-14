-- ============================================================================
-- Función de cada persona (para la cobertura de tienda)
-- ----------------------------------------------------------------------------
-- No todos en una sede son de atención al cliente. La cobertura de "Programados /
-- meta" debe contar SOLO a los operativos (atención). Ejecutivos y roles de
-- procesos/back-office tienen horario y horas, pero NO cuentan como cobertura.
--   'atencion'  → atención al cliente (operativo, cuenta para cobertura)
--   'ejecutivo' → ejecutivo (no cuenta)
--   'procesos'  → procesos / back-office (no cuenta)
-- Es distinto de `rol` (que es el permiso en el panel).
-- ============================================================================

alter table personas
  add column if not exists funcion text not null default 'atencion';

alter table personas drop constraint if exists personas_funcion_check;
alter table personas add constraint personas_funcion_check
  check (funcion in ('atencion', 'ejecutivo', 'procesos'));
