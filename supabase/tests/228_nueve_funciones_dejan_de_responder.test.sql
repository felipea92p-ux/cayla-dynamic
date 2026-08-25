-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 228_nueve_funciones_dejan_de_responder.test.sql
-- ============================================================================
-- Defiende la 0292. Nueve funciones `SECURITY DEFINER` —pensadas para que
-- otras funciones las usaran por dentro— tenían `grant execute … to
-- authenticated`: cualquiera de las ~30 cuentas podía pedirlas directo por
-- RPC con el id de OTRA persona y obtener su banda salarial, su suspensión
-- vigente o sus faltas exactas, sin pasar por ningún guard.
--
-- Medido antes de escribir esta prueba, en el Postgres local: una integrante
-- de LIM, sin rol especial, leía por `fn_beneficio_ya_depositado` un depósito
-- de CTS real de una persona de TRU (S/1,234.56) que nunca podría leer por
-- `select` directo (RLS se lo niega en las tres tablas de abajo).
--
-- LO QUE ESTA PRUEBA FIJA NO ES SOLO «que se bloquee» — eso es la mitad fácil.
-- La mitad que importa es que el camino LEGÍTIMO, un envoltorio con guard que
-- llama a la función por dentro, siga funcionando exactamente igual: una
-- función `SECURITY DEFINER` corre como su dueño, no como quien la originó,
-- así que el `revoke` de la 0292 no le quita nada a nadie que pase por la
-- puerta correcta.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000022800', 'ZZ228', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000022801', 'Atacante', 'Lab', '00000000-0000-0000-0000-000000022800',
   'integrante', 'x', '00000000-0000-0000-0000-0000000228a1', '2024-01-01'),
  ('00000000-0000-0000-0000-000000022802', 'Objetivo', 'Lab', '00000000-0000-0000-0000-000000022800',
   'integrante', 'x', null, '2024-01-01'),
  ('00000000-0000-0000-0000-000000022803', 'Admin', 'Lab', '00000000-0000-0000-0000-000000022800',
   'admin', 'x', '00000000-0000-0000-0000-0000000228a3', '2024-01-01');

insert into desembolsos_beneficios (persona_id, ventana, anio, monto, origen, fecha_pago)
values ('00000000-0000-0000-0000-000000022802', 'cts_may', 2026, 1234.56, 'transferencia', '2026-05-15');
set session_replication_role = origin;

-- ── 1 · La lectura directa (RLS) ya la negaba — eso nunca fue el problema ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000228a1', true);
set role authenticated;

select is(
  (select count(*)::int from desembolsos_beneficios
    where persona_id = '00000000-0000-0000-0000-000000022802'),
  0,
  'RLS · la atacante no puede leer la tabla directo, como siempre');

-- ── 2 · La 0292: la RPC directa queda bloqueada ────────────────────────────
-- (El "antes" —que sin la 0292 esta misma llamada devuelve 1234.56— se
--  midió a mano antes de escribir esta prueba, y queda en el commit: no se
--  reproduce aquí para no dejar en el repo un ejemplo listo de cómo pedir el
--  dato de otra persona, ni siquiera dentro de una prueba con datos falsos.)
select throws_ok(
  $$ select fn_beneficio_ya_depositado('00000000-0000-0000-0000-000000022802', 'cts_may', 2026) $$,
  '42501',
  null,
  'BLOQUEADA · la atacante ya no puede pedir el depósito de otra persona por RPC directo');

reset role;

-- ── 3 · Las nueve, en bloque ─────────────────────────────────────────────
select is_empty(
  $$ select p.proname
       from pg_proc p
      where p.proname in (
        'fn_falta_contadores','fn_tardanza_escalon','fn_dia_suspendido',
        'fn_dias_suspension','fn_beneficio_ya_depositado','fn_educacion_monto',
        'fn_es_dia_laborable','fn_reglamento_no_acusado','fn_dcs_por_que_no_compensa'
      )
      and has_function_privilege('authenticated', p.oid, 'EXECUTE') $$,
  'LAS NUEVE · ninguna sigue siendo ejecutable directo por authenticated');

-- ── 4 · Lo que de verdad importa: el camino legítimo sigue vivo ────────────
-- Un envoltorio SECURITY DEFINER con guard, calcado del patrón real del
-- repositorio (fn_expediente_generar_falta, fn_cts_trunca, etc.), que llama
-- por dentro a una de las nueve.
create function pg_temp.envoltorio_con_guard(p_persona_id uuid) returns numeric
language plpgsql security definer as $$
begin
  if not fn_es_admin_o_lider() is true then
    raise exception 'Solo un administrador o lider puede ver esto.';
  end if;
  return fn_beneficio_ya_depositado(p_persona_id, 'cts_may', 2026);
end $$;
grant execute on function pg_temp.envoltorio_con_guard(uuid) to authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000228a3', true);
set role authenticated;

select is(
  pg_temp.envoltorio_con_guard('00000000-0000-0000-0000-000000022802'),
  1234.56::numeric,
  'SIGUE VIVO · un admin, por un envoltorio con guard, obtiene el mismo dato que antes');

-- ── 5 · Y la atacante, por ese MISMO envoltorio, sigue sin poder ───────────
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000228a1', true);
set role authenticated;

select throws_ok(
  $$ select pg_temp.envoltorio_con_guard('00000000-0000-0000-0000-000000022802') $$,
  'Solo un administrador o lider puede ver esto.',
  'GUARD DE NEGOCIO · la atacante sigue sin poder, pero por la regla, no por un permiso roto');

reset role;
select * from finish();
rollback;
