-- ============================================================================
-- 0595 · LA FECHA DE INGRESO POR DEFECTO ES LA DE LIMA, NO LA DE UTC
-- ============================================================================
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--   Que una persona dada de alta sin fecha de ingreso (`fn_crear_persona` no la
--   recibe) queda con la fecha de HOY EN LIMA, a cualquier hora del día.
--
-- ── EL PROBLEMA ─────────────────────────────────────────────────────────────
--   `personas.fecha_ingreso` nació con `default current_date` (0001). La base
--   corre en UTC, así que entre las 19:00 y las 23:59 de Lima `current_date` ya
--   es MAÑANA. Antes de la 0594 eso no se notaba. Desde la 0594 una fecha de
--   ingreso futura impide marcar y saca a la persona del terminal: quien se da
--   de alta de noche quedaría sin poder marcar hasta el día siguiente.
--   Lo delató el CI: las pruebas pgTAP de `db-tests` empezaron a fallar en main
--   a las 19:13 de Lima con «esa persona ingresa el 05/11/2026» (hoy en Lima
--   era el 04) y ahora fallan cada noche en esa franja.
--
-- ── QUÉ CAMBIA ──────────────────────────────────────────────────────────────
--   El default pasa a `fn_hoy_lima()` (la regla única del corte del día, 0091).
--   Nada más: no toca funciones, ni triggers, ni filas existentes.
--
-- ── QUÉ NO CAMBIA, Y HAY QUE MIRAR ──────────────────────────────────────────
--   Las filas ya creadas de noche con fecha de mañana no se corrigen aquí: la
--   fecha es dato de plata (vacaciones, CTS, grati) y la decide una persona.
--   Para ver si hay alguna, se corre la consulta de abajo (solo lectura).
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   alter table personas alter column fecha_ingreso set default current_date;
--
-- ── COMPROBACIÓN (solo lectura) ─────────────────────────────────────────────
--   select count(*) as con_ingreso_futuro
--     from personas where fecha_ingreso > fn_hoy_lima();
--   -- Las que salgan y no sean ingresos programados a propósito se revisan a mano.
-- ============================================================================

set local lock_timeout = '3s';

alter table personas alter column fecha_ingreso set default fn_hoy_lima();

insert into migraciones_aplicadas (numero, nombre)
values (595, 'la_fecha_de_ingreso_por_defecto_es_la_de_lima')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
