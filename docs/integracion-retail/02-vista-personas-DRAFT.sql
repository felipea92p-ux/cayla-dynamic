-- ============================================================================
-- FASE 2 — LA "VENTANITA" (BORRADOR — NO APLICAR AÚN)
-- ----------------------------------------------------------------------------
-- Esto es un DRAFT para revisar juntos mañana, NO una migración lista.
-- Por eso vive en docs/ y no en supabase/migrations/. No lo corras todavía.
--
-- Qué es: dos "ventanas" (vistas) de SOLO LECTURA en Dynamic que exponen a
-- retail EXACTAMENTE lo mínimo — DNI, nombre, sede, activo. NADA de sueldo,
-- disciplina ni datos personales. La reja de la ventanita.
-- ============================================================================

-- Ventana de personas: solo lo que retail necesita para atribuir una venta.
create or replace view v_personas_publica as
select
  p.id,
  p.documento                       as dni,
  p.nombres,
  p.apellidos,
  s.codigo                          as sede_codigo,
  s.nombre                          as sede_nombre,
  (p.estado = 'activo')             as activo
from personas p
left join sedes s on s.id = p.sede_base_id;

comment on view v_personas_publica is
  'Ventanita para CAYLA retail: SOLO lectura, SOLO campos seguros (DNI, nombre, sede, activo). No expone sueldo/disciplina/datos_personales. Amarre por DNI.';

-- Ventana de sedes.
create or replace view v_sedes_publica as
select codigo, nombre, activa
from sedes;

comment on view v_sedes_publica is
  'Ventanita para CAYLA retail: lista de sedes (codigo, nombre, activa), solo lectura.';


-- ----------------------------------------------------------------------------
-- ACCESO — DECISIÓN PENDIENTE (ver 00-plan.md, Fase 2). NO resuelto en este draft.
-- ----------------------------------------------------------------------------
-- Falta decidir CÓMO lee retail estas vistas sin abrir el resto de la base:
--
--   Opción A — Rol de solo lectura + key:
--     - crear un rol/clave que SOLO tenga SELECT sobre estas dos vistas.
--     - retail se conecta con esa key a la API de Supabase de Dynamic.
--     - hay que revisar RLS: que la vista sea legible por ese rol pero que
--       NADA más de personas/sedes se filtre.
--
--   Opción B — Edge Function:
--     - una función en Dynamic que devuelve el JSON de estas vistas.
--     - retail la llama por HTTP con un token.
--
-- Recomendación: A si los grants alcanzan; B si se necesita más control.
-- Esto se define mañana; el borrador de arriba solo crea las vistas (inofensivo,
-- reversible con `drop view v_personas_publica;`).
