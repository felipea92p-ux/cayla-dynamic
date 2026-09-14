-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 348_copiar_semana_anterior_por_sede.test.sql
-- ============================================================================
-- fn_copiar_semana_anterior (0439) replica los turnos PUNTUALES de la semana
-- anterior a la semana que se está armando — la única decisión que importa es
-- que NUNCA pise un día que el destino ya tenga editado a mano, y que quede
-- claro en el resultado cuáles se copiaron y cuáles se saltaron por eso.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000034800', 'ZZCSA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000034801', 'ZZCSB', 'Sede de laboratorio B', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values
  ('00000000-0000-0000-0000-000000034810', 'CsaAdmin', 'Lab',
   '00000000-0000-0000-0000-000000034800', 'admin', 'x',
   '00000000-0000-0000-0000-0000000348ff', '2024-01-01'),
  ('00000000-0000-0000-0000-000000034811', 'CsbEncargada', 'Lab',
   '00000000-0000-0000-0000-000000034801', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000348fe', '2024-01-01');
set session_replication_role = origin;

-- Dos personas en la sede A: una con turno puntual la semana pasada, otra
-- con un descanso puntual. Una tercera en la sede B, para comprobar que no
-- se cruzan sedes.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values
  ('00000000-0000-0000-0000-000000034812', 'CsaTurno', 'Lab', '00000000-0000-0000-0000-000000034800', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000034813', 'CsaDescanso', 'Lab', '00000000-0000-0000-0000-000000034800', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000034814', 'CsbOtra', 'Lab', '00000000-0000-0000-0000-000000034801', 'x', '2024-01-01');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000348ff', true);

-- Semana ANTERIOR: lunes 2026-09-07 a domingo 2026-09-13.
-- Semana DESTINO:  lunes 2026-09-14 a domingo 2026-09-20.
select fn_set_turno('00000000-0000-0000-0000-000000034812', '2026-09-08', '09:00', '15:30'); -- martes
select fn_set_descanso('00000000-0000-0000-0000-000000034813', '2026-09-09'); -- miércoles
select fn_set_turno('00000000-0000-0000-0000-000000034814', '2026-09-08', '10:00', '18:00'); -- martes, sede B

-- CsaTurno ya tiene, a mano, un turno propio el martes destino — no debe pisarse.
select fn_set_turno('00000000-0000-0000-0000-000000034812', '2026-09-15', '07:00', '13:00');


-- Se ejecuta UNA sola vez y se guarda: llamarla de nuevo más abajo vería sus
-- propias copias ya puestas y las reportaría como "saltado", no "copiado" —
-- el mismo tipo de trampa que ya documentó 233 para no repetir fn_set_turno
-- entre aserciones.
create temporary table _copia as
select * from fn_copiar_semana_anterior('00000000-0000-0000-0000-000000034800', '2026-09-14');


-- ── 1 y 2 · Copia el turno puntual, con las horas correctas ─────────────────

select is(
  (select resultado from _copia
    where persona_id = '00000000-0000-0000-0000-000000034812' and fecha = '2026-09-15'),
  'saltado: ya tenía turno propio ese día',
  'El martes de CsaTurno ya tenía turno propio: se salta, nunca se pisa');

select is(
  (select hora_entrada::text from turnos
    where persona_id = '00000000-0000-0000-0000-000000034812' and fecha = '2026-09-15'),
  '07:00:00',
  'Y el turno que ya tenía sigue siendo el suyo, intacto — no el de la semana pasada');


-- ── 3 y 4 · El descanso puntual sí se copia, porque el miércoles estaba libre ─

select is(
  (select resultado from _copia
    where persona_id = '00000000-0000-0000-0000-000000034813' and fecha = '2026-09-16'),
  'copiado',
  'El miércoles de CsaDescanso no tenía nada puesto: el descanso puntual sí se copia');

select is(
  (select es_descanso from turnos
    where persona_id = '00000000-0000-0000-0000-000000034813' and fecha = '2026-09-16'),
  true,
  'Y el miércoles destino quedó efectivamente como descanso');


-- ── 5 · Cada copia deja el mismo rastro que una edición manual ──────────────

-- correcciones_auditoria no guarda una columna de fecha propia (0298: solo
-- corregido_at, cuándo se guardó el cambio) — el día que cambió vive dentro
-- del motivo, igual que descubrió la auditoría de Bandeja. Por eso el filtro
-- va por el motivo, no solo por el par antes→después: la 034813 tiene DOS
-- filas iguales de "(sin turno) → descanso" (la del miércoles ORIGEN y la
-- de su copia al miércoles DESTINO), y contarlas juntas daría 2 aunque la
-- copia esté funcionando bien.
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000034813'
      and campo_modificado = 'turnos.horario'
      and valor_anterior = '(sin turno)' and valor_nuevo = 'descanso'
      and motivo like '%16/09/2026%'),
  1,
  'La copia pasa por fn_set_descanso, así que el miércoles DESTINO queda en correcciones_auditoria igual que si se hubiera puesto a mano');


-- ── 6 · No cruza sedes ───────────────────────────────────────────────────────

select is(
  (select count(*)::int from turnos
    where persona_id = '00000000-0000-0000-0000-000000034814' and fecha = '2026-09-15'),
  0,
  'CsbOtra es de la sede B: copiar la sede A no le toca ningún turno');


-- ── 7 · Sin turnos puntuales la semana pasada, no hay nada que copiar ───────
-- (implícito arriba: solo aparecen filas para las 2 personas de la sede A que
--  sí tenían algo puntual — ninguna fila para quien no tenía nada puesto.)

select is(
  (select count(*)::int from _copia
    where persona_id not in ('00000000-0000-0000-0000-000000034812', '00000000-0000-0000-0000-000000034813')),
  0,
  'Solo aparecen en el resultado las personas que SÍ tenían un turno puntual la semana pasada');


-- ── 8 · Permiso: una encargada de otra sede no puede copiar esta ────────────

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000348fe', true);

select throws_ok(
  $$ select * from fn_copiar_semana_anterior('00000000-0000-0000-0000-000000034800', '2026-09-14') $$,
  null, null,
  'La encargada de la sede B no puede copiar turnos de la sede A');

select * from finish();
rollback;
