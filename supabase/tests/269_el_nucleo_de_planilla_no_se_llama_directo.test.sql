-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 269_el_nucleo_de_planilla_no_se_llama_directo.test.sql — la 0339
-- ============================================================================
-- Lo que defiende: que `fn_planilla_calcular_nucleo` —el cuerpo completo de
-- fn_planilla_calcular, SIN su guard de admin/líder— sea imposible de llamar
-- directo desde `authenticated`, sin importar el rol de la persona detrás de
-- la sesión (ni siquiera un admin puede llamarlo directo: solo puede pedirle
-- el cálculo a través de fn_planilla_calcular o fn_planilla_calcular_persona,
-- que SÍ deciden permiso antes de reenviarle la llamada).
--
-- Y por qué esto se prueba con `has_function_privilege`/`set role`, no con un
-- guard interno tipo `current_user <> 'postgres'`: se comprobó (ver el
-- encabezado de la 0339) que ese chequeo NUNCA dispara dentro de una función
-- SECURITY DEFINER, porque `current_user` ya es el dueño se la llame como se
-- la llame. La defensa real es que `authenticated` no tiene EXECUTE — y por
-- eso esta prueba comprueba EXACTAMENTE eso, no un guard que no existe.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000269', 'ZZ269', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000269', 'DosSeisNueveAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000000269', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000000369', '2024-01-01');
set session_replication_role = origin;

-- ── 1-2 · Nadie autenticado tiene EXECUTE, ni siquiera un admin ────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000369', true);

select is(
  has_function_privilege('authenticated', 'fn_planilla_calcular_nucleo(date,date,uuid)', 'execute'),
  false,
  '`authenticated` no tiene EXECUTE sobre fn_planilla_calcular_nucleo — ni con grant en masa se lo daría por error, porque nadie se lo concede a propósito'
);

-- ⚠ `set role` (no solo `set_config`) es necesario para que el chequeo de
-- privilegio real de Postgres entre en juego — mismo motivo que la 91.
set local role authenticated;
select throws_ok(
  $$ select fn_planilla_calcular_nucleo('2026-07-01', '2026-07-31') $$,
  '42501',
  null,
  'ADMIN, llamando DIRECTO como authenticated · igual se lo niega Postgres antes de entrar al cuerpo — ser admin no basta, hay que pasar por un envoltorio'
);
reset role;

-- ── 3 · Está en la lista negra, para que un futuro barrido no la reabra ────
select is(
  (select count(*)::int from funciones_nunca_para_authenticated where funcion = 'fn_planilla_calcular_nucleo'),
  1,
  'fn_planilla_calcular_nucleo queda anotada en la lista negra de la 0090'
);

-- ── 4-5 · Y el mismo admin, por la puerta de siempre, sí puede ─────────────
select lives_ok(
  $$ select fn_planilla_calcular('2026-07-01', '2026-07-31') $$,
  'el MISMO admin, llamando al envoltorio de toda la vida, sí puede — el refactor no le cambió nada'
);

select is(
  (select jsonb_array_length(fn_planilla_calcular('2026-07-01', '2026-07-31') -> 'filas') > 0),
  true,
  'y le devuelve filas de verdad, no una lista vacía — el envoltorio de verdad reenvía al núcleo'
);

select * from finish();
rollback;
