-- ============================================================================
-- HISTÓRICO — SUPERADO, NO SE APLICA (actualizado 2026-09-04)
-- ----------------------------------------------------------------------------
-- Este borrador nunca se aplicó, y no hace falta aplicarlo: el 2026-07-23 el
-- problema que resolvía (retail necesita leer personas/sedes de Dynamic) se
-- resolvió por otra vía — el ERP de tiendas se mudó al MISMO Postgres, y
-- `retail.personas` / `retail.sedes` (migración 0218) son vistas
-- `security_invoker = true` sobre estas mismas tablas. No hace falta una API
-- de solo lectura entre dos proyectos porque no hay dos proyectos. Ver
-- `00-plan.md`.
--
-- Se conserva este archivo por la advertencia de abajo, que sigue siendo una
-- lección real sobre vistas auto-actualizables en Postgres — no porque falte
-- terminarlo.
-- ============================================================================
--
-- ============================================================================
-- FASE 2 — LA "VENTANITA" (BORRADOR — NO APLICAR AÚN)
-- ----------------------------------------------------------------------------
-- Esto es un DRAFT para revisar juntos mañana, NO una migración lista.
-- Por eso vive en docs/ y no en supabase/migrations/. No lo corras todavía.
--
-- Qué es: dos "ventanas" (vistas) de SOLO LECTURA en Dynamic que exponen a
-- retail EXACTAMENTE lo mínimo — DNI, nombre, sede, activo. NADA de sueldo,
-- disciplina ni datos personales. La reja de la ventanita.
--
-- ⚠️⚠️ ESTE BORRADOR, TAL CUAL ESTÁ, ABRE DOS AGUJEROS. Medido el 2026-08-11
-- contra el Postgres local, creando estas dos vistas dentro de un BEGIN…ROLLBACK
-- y ejecutando después `set local role authenticated`:
--
--   1. «SOLO LECTURA» no es cierto: `update v_sedes_publica set nombre = …`
--      modificó LAS 3 SEDES, y `delete from v_sedes_publica` también pasó.
--      Una vista de una sola tabla sin agregación es AUTO-ACTUALIZABLE, y la
--      0004 dejó puesto `alter default privileges … grant select, insert,
--      update, delete on tables to authenticated`: nadie escribe un GRANT, la
--      vista nace con permiso de escritura para cualquier sesión con login.
--      La misma prueba contra la TABLA (`update sedes …`) tocó 0 filas — o sea
--      que la RLS de sedes sí protege, y la vista la esquiva.
--
--   2. La vista de personas expone el DNI de TODAS a cualquiera con login. Sin
--      `security_invoker`, una vista corre con los permisos de su dueño
--      (postgres, que se salta la RLS). Hoy una integrante solo puede leerse a
--      sí misma y el roster de su terminal; a través de esta ventana leería el
--      documento de las ~30 personas. Es el dato que la 0125 protege con
--      «solo admin o líder puede cambiarlo porque se imprime en papeles».
--
-- Las dos vistas que ya existen en el repo (0096, 0101) se crean con
-- `with (security_invoker = true)`. Este borrador se escribió sin esa cláusula.
--
-- La versión que se aplique tiene que llevar, sí o sí:
--   · `with (security_invoker = true)`, o `security_barrier` + revocar escritura;
--   · `revoke all on … from public, anon, authenticated;` explícito, DESPUÉS de
--     crear cada vista, porque el default privileges actúa en el `create`;
--   · `grant select` SOLO al rol que lea retail (ver la decisión de acceso).
-- Y con `security_invoker = true` hay que decidir a la vez bajo qué identidad
-- entra retail: la RLS de personas la evaluará con ESE rol, no con postgres.
--
-- (Y es exactamente lo que `retail.personas` / `retail.sedes`, migración
-- 0218, hacen bien: `security_invoker = true` desde el primer `create`.)
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
