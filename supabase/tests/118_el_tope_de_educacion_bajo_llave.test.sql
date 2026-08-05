-- ============================================================================
-- 118_el_tope_de_educacion_bajo_llave.test.sql
-- ============================================================================
-- Dos cosas que tienen que ser ciertas A LA VEZ, y que se rompen por separado:
--
--   1. Ninguna sesión con login puede tocar los topes. `topes_educacion_rango`
--      era la única tabla del esquema sin RLS, y con INSERT/UPDATE/DELETE para
--      `authenticated` — el rol del terminal de la tienda.
--
--   2. Y el candado tiene que SEGUIR VIENDO el tope. `fn_educacion_respeta_el_tope`
--      lee «no encuentro tope» como «no hay límite», así que activar RLS sin
--      volver el trigger security definer habría apagado el techo en silencio.
--
-- Si alguien arregla una y no la otra, la mitad que quede rota no se nota
-- mirando la pantalla: se nota cuando ya se pagó de más.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ca00', 'ZZTOP', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000ca01', 'TopeAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ca00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ca09');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-00000000ca02', 'TopeColibri', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ca00', 'test-hash');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000ca02', 'colibri', 1130, '2026-01-01');

insert into topes_educacion_rango (rango, tope_mensual)
values ('colibri', 200)
on conflict (rango) do update set tope_mensual = 200;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ca09', true);

-- ── 1 · La tabla está bajo llave ────────────────────────────────────────────
select ok(
  (select relrowsecurity from pg_class where relname = 'topes_educacion_rango'),
  'LLAVE · la tabla tiene RLS activo');

select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_name = 'topes_educacion_rango'
      and grantee = 'authenticated'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'LLAVE · `authenticated` ya no puede escribirla: ni insertar, ni cambiar, ni borrar');

select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_name = 'topes_educacion_rango' and grantee = 'anon'),
  0,
  'LLAVE · y `anon` —sin sesión— no tiene nada sobre ella');

-- ── 2 · El terminal, en carne y hueso ───────────────────────────────────────
-- El caso exacto que se demostró el 2026-08-05: una sesión `authenticated`
-- borraba el techo y la siguiente asignación pasaba sin objeción.
set local role authenticated;
select throws_ok(
  $$ delete from topes_educacion_rango where rango = 'colibri' $$,
  null, null,
  'TERMINAL · una sesión con login ya no puede borrar el techo');
reset role;

select is(
  (select tope_mensual from topes_educacion_rango where rango = 'colibri'),
  200::numeric,
  'TERMINAL · y el techo sigue donde estaba');

-- ── 3 · El candado sigue viendo lo que tiene que ver ────────────────────────
-- La mitad que se rompería si alguien activara RLS y se olvidara del trigger:
-- pasaría de «rechaza» a «acepta» sin que nadie tocara el techo.
select throws_ok(
  $$ insert into asignaciones_educacion
       (persona_id, monto, institucion, costo_declarado, vigente_desde, vigente_hasta)
     values ('00000000-0000-0000-0000-00000000ca02', 500, 'Instituto de laboratorio',
             700, '2026-08-01', '2026-08-31') $$,
  null, null,
  'CANDADO · con RLS puesto, S/500 sobre un techo de S/200 se sigue rechazando');

-- Y la otra mitad: que no se haya vuelto un «rechaza todo». Un monto dentro del
-- techo tiene que entrar igual que siempre.
--
-- Va con OTRA institución y OTRO mes a propósito. Con los mismos datos que la
-- comprobación de arriba, esta dependía de que aquella hubiera rechazado: el día
-- que el techo se rompa, esta fallaría por choque de clave única
-- (`idx_asignaciones_educacion_unica`) y no por lo que de verdad mide. Una
-- comprobación que falla por el motivo equivocado no dice nada.
select lives_ok(
  $$ insert into asignaciones_educacion
       (persona_id, monto, institucion, costo_declarado, vigente_desde, vigente_hasta)
     values ('00000000-0000-0000-0000-00000000ca02', 150, 'Otro instituto de laboratorio',
             200, '2026-09-01', '2026-09-30') $$,
  'CANDADO · y S/150 dentro del techo entra sin problema: no se apagó el circuito');

select * from finish();
rollback;
