-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 356_un_visto_bueno_recuerda_lo_que_acepto.test.sql — la 0451
-- ============================================================================
-- Un visto bueno de Incidencias guarda el número que se aceptó, y deshacerlo
-- lo anula con motivo en vez de borrarlo. Lo que se prueba es la trazabilidad:
-- que después de aceptar, reaceptar y deshacer, las tres cosas sigan ahí.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000356a01', 'ZZVB', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000356a02', 'VbAdmin', 'Lab',
        '00000000-0000-0000-0000-000000356a01', 'admin', 'x',
        '00000000-0000-0000-0000-000000356a0a', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000356a03', 'VbSalida', 'Lab',
        '00000000-0000-0000-0000-000000356a01', 'x', '2024-01-01');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000356a0a', true);

-- ── Una sola puerta: sin sobrecargas ────────────────────────────────────────
select is((select count(*)::int from pg_proc where proname = 'fn_aceptar_incidencia'), 1,
          'FIRMA · fn_aceptar_incidencia existe una sola vez (una sobrecarga rompería la llamada sin p_valor)');
select is((select count(*)::int from pg_proc where proname = 'fn_quitar_aceptacion'), 1,
          'FIRMA · fn_quitar_aceptacion existe una sola vez');

-- ── Aceptar guarda el valor ─────────────────────────────────────────────────
select lives_ok(
  $$ select fn_aceptar_incidencia('00000000-0000-0000-0000-000000356a03', '2026-09-04',
       'salida_anticipada', 'avisó que salía por cita médica', 20) $$,
  'ACEPTAR · el visto bueno se guarda con su valor');
select is((select valor from incidencias_aceptadas
            where persona_id = '00000000-0000-0000-0000-000000356a03' and anulada_at is null),
          20::numeric, 'ACEPTAR · el valor guardado es el que se aceptó (20 min)');

-- ── Reaceptar no pisa: anula el anterior ────────────────────────────────────
select lives_ok(
  $$ select fn_aceptar_incidencia('00000000-0000-0000-0000-000000356a03', '2026-09-04',
       'salida_anticipada', 'corregida: sí salió 142 min antes, con permiso', 142) $$,
  'REACEPTAR · un segundo visto bueno sobre la misma incidencia se acepta');
select is((select count(*)::int from incidencias_aceptadas
            where persona_id = '00000000-0000-0000-0000-000000356a03'),
          2, 'REACEPTAR · quedan las DOS filas: el primer visto bueno no se sobrescribió');
select is((select count(*)::int from incidencias_aceptadas
            where persona_id = '00000000-0000-0000-0000-000000356a03' and anulada_at is null),
          1, 'REACEPTAR · y una sola vigente');
select is((select nota from incidencias_aceptadas
            where persona_id = '00000000-0000-0000-0000-000000356a03' and anulada_at is not null),
          'avisó que salía por cita médica',
          'REACEPTAR · la nota del primero sigue intacta, con su motivo de reemplazo');

-- ── Deshacer pide motivo y no borra ─────────────────────────────────────────
select throws_ok(
  $$ select fn_quitar_aceptacion('00000000-0000-0000-0000-000000356a03', '2026-09-04', 'salida_anticipada', '  ') $$,
  'P0001', 'Escribe por qué deshaces este visto bueno (mínimo 4 caracteres): queda en el historial.',
  'DESHACER · sin motivo, no se deshace');
select lives_ok(
  $$ select fn_quitar_aceptacion('00000000-0000-0000-0000-000000356a03', '2026-09-04', 'salida_anticipada',
       'Se aceptó por error: era otra persona') $$,
  'DESHACER · con motivo, se deshace');
select is((select count(*)::int from incidencias_aceptadas
            where persona_id = '00000000-0000-0000-0000-000000356a03'),
          2, 'DESHACER · la fila no se borró: sigue en la historia, anulada');
select throws_ok(
  $$ select fn_quitar_aceptacion('00000000-0000-0000-0000-000000356a03', '2026-09-04', 'salida_anticipada',
       'Segundo clic sobre lo mismo') $$,
  'P0001', 'Ese visto bueno ya no está vigente: alguien lo deshizo o lo reemplazó. Recarga la pantalla.',
  'DESHACER · un segundo intento avisa en vez de fingir que hizo algo');

-- ── Estados imposibles ──────────────────────────────────────────────────────
select throws_ok(
  $$ select fn_aceptar_incidencia('00000000-0000-0000-0000-000000356a03', '2026-09-04', 'lo_que_sea') $$,
  'P0001', 'Tipo de incidencia inválido: «lo_que_sea».',
  'IMPOSIBLE · un tipo que la pantalla no ofrece no se acepta');
select throws_ok(
  $$ insert into incidencias_aceptadas (persona_id, fecha, tipo, aceptado_por, anulada_at, anulada_por)
     values ('00000000-0000-0000-0000-000000356a03', '2026-09-05', 'salida_anticipada',
             '00000000-0000-0000-0000-000000356a02', now(), '00000000-0000-0000-0000-000000356a02') $$,
  '23514', null,
  'IMPOSIBLE · una aceptación anulada sin motivo no puede existir, ni escribiendo la tabla a mano');

select * from finish();
rollback;
