-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 161_un_terminal_activo_no_se_queda_sin_dueno.test.sql
-- ============================================================================
-- QUÉ DEFIENDE ESTE ARCHIVO
--
--   El guard que impide que una sesión cualquiera se haga pasar por un terminal
--   son tres condiciones unidas por AND, dentro de fn_registrar_marcaje:
--
--       if auth.uid() is not null
--          and v_terminal_auth is not null
--          and auth.uid() <> v_terminal_auth then raise …
--
--   Con `auth_user_id` en null la segunda es falsa, el AND entero es falso y no
--   se lanza nada: la sesión pasa y la marca entra a nombre de otra persona. La
--   0202 no parchea el AND — hace imposible el estado que lo abre.
--
--   Se prueban LAS DOS MITADES. Que el estado peligroso reboten, y que los
--   estados legítimos sigan entrando. Un candado que cierra siempre no es un
--   candado: es una pantalla rota, y alguien lo quita en la primera urgencia.
--
-- POR QUÉ IMPORTA LA MITAD 3 (crear inactivo)
--   No hay pantalla que cree terminales: se insertan a mano en el SQL Editor, y
--   la vinculación es un paso aparte. Si el candado impidiera dar de alta un
--   terminal antes de vincularlo, no habría forma de dar de alta ninguno.
--   El camino queda: se crea con activo = false y se activa al vincularlo.
--
-- POR QUÉ IMPORTA LA MITAD 5 (quitarle el dueño a uno activo)
--   La FK es ON DELETE SET NULL. Borrar en Auth la cuenta de un terminal activo
--   le ponía el dueño en null y lo dejaba activo — la puerta se abría sola, sin
--   que nadie tocara nada. Ahora ese borrado falla y hay que desactivarlo antes.
--
-- POR QUÉ SE PRUEBA EL COMPORTAMIENTO Y NO EL TEXTO
--   Se podría comprobar que pg_constraint contiene el nombre del candado. Es la
--   aserción 1 y por sí sola no vale: un CHECK mal escrito existe igual. Las
--   otras cinco intentan de verdad cada movimiento y exigen el resultado.
--
-- NOTA DE ENTORNO
--   `session_replication_role = replica` salta la FK contra auth.users, que en
--   las pruebas no existe. Los CHECK NO son triggers, así que siguen aplicando:
--   es justo lo que hace falta medir.
-- ============================================================================
begin;
select plan(6);

set local session_replication_role = replica;

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000015600', 'ZZ156', 'Sede de laboratorio 156', true);

-- ── 1 · El candado existe, y con ese nombre ─────────────────────────────────
-- Solo existencia: comparar el texto del CHECK contra una cadena fija es
-- frágil —Postgres lo devuelve normalizado, con sus propios paréntesis— y no
-- añade nada, porque lo que el candado SIGNIFICA lo miden las cuatro de abajo
-- intentando cada movimiento de verdad.
select ok(
  exists (select 1 from pg_constraint
           where conname = 'terminal_activo_con_dueno'
             and conrelid = 'public.terminales'::regclass
             and contype = 'c'),
  'el candado terminal_activo_con_dueno existe sobre terminales');

-- ── 2 · ACTIVO sin dueño: el estado que abría el guard, ahora imposible ─────
-- Ojo al insert: no se pasa `activo`. Es el insert natural, y `activo` tiene
-- default TRUE — o sea que el camino cómodo era justo el peligroso.
select throws_ok($$
  insert into terminales (sede_id, nombre_dispositivo)
  values ('00000000-0000-0000-0000-000000015600', 'mac-sin-dueno')
$$, 23514,
  null,
  'un terminal ACTIVO sin cuenta vinculada no se puede crear (y activo es default true)');

-- ── 3 · INACTIVO sin dueño: tiene que seguir entrando ───────────────────────
select lives_ok($$
  insert into terminales (sede_id, nombre_dispositivo, activo)
  values ('00000000-0000-0000-0000-000000015600', 'mac-por-vincular', false)
$$, 'se puede dar de alta un terminal inactivo y vincularlo después');

-- ── 4 · ACTIVO con dueño: la operación normal no se toca ────────────────────
select lives_ok($$
  insert into terminales (sede_id, nombre_dispositivo, auth_user_id)
  values ('00000000-0000-0000-0000-000000015600', 'mac-tienda',
          '11111111-1111-1111-1111-111111111111')
$$, 'un terminal activo CON cuenta vinculada sigue funcionando');

-- ── 5 · Quitarle el dueño a uno activo: la vía del ON DELETE SET NULL ───────
select throws_ok($$
  update terminales set auth_user_id = null where nombre_dispositivo = 'mac-tienda'
$$, 23514,
  null,
  'no se le puede quitar la cuenta a un terminal activo — hay que desactivarlo primero');

-- ── 6 · Y con el estado ya imposible, el guard decide por lo que importa ────
-- Una sesión que NO es la del terminal se topa con la tercera condición del AND,
-- que es la que de verdad protege. Antes de la 0202 esta llamada podía pasar sin
-- más con solo apuntar a un terminal sin dueño.
-- El set_config va FUERA del bloque: `execute` de PL/pgSQL no admite dos
-- sentencias en la misma cadena, y throws_like ejecuta lo que se le pasa.
-- En un DO, no en un `select`: un select suelto imprime una fila en medio del
-- flujo TAP que pg_prove tiene que ignorar. Mejor no darle nada que ignorar.
do $sesion$ begin
  perform set_config('request.jwt.claim.sub',
                     '99999999-9999-9999-9999-999999999999', true);
end $sesion$;

select throws_like($$
  select fn_registrar_marcaje(
    '00000000-0000-0000-0000-000000015601'::uuid,
    'entrada'::tipo_marca,
    now(),
    gen_random_uuid(),
    'terminal'::origen_marca,
    (select id from terminales where nombre_dispositivo = 'mac-tienda'),
    null,
    null)
$$, '%no coincide%',
  'una sesión que no es la del terminal no puede registrar marcas con él');

select * from finish();
rollback;
