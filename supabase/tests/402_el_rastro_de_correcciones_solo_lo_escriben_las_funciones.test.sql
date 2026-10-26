-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 402_el_rastro_de_correcciones_solo_lo_escriben_las_funciones.test.sql
-- ============================================================================
-- Defiende la 0508. Hasta ella, un lider_do —o un líder de equipo sobre alguien
-- de su sede— podía insertar filas directo en `correcciones_auditoria` (políticas
-- `auditoria_insert_*` de la 0003 + privilegio de INSERT de la 0004), con el
-- `corregido_por` de OTRA persona y un `corregido_at` de hace semanas: rastro
-- fabricado, en la tabla de la que cuelga el expediente disciplinario. Y
-- `authenticated` además conservaba TRUNCATE (privilegios por defecto de
-- Supabase), contra el que RLS no hace nada.
--
-- Esta prueba vigila tres cosas, en este orden:
--   1. EL ESTADO: no queda política ni privilegio de escritura, y la única
--      función INVOKER que escribe la auditoría sigue siendo la del trigger de
--      educación (si aparece otra, el revoke la rompe en producción: se caza acá).
--   2. EL COMPORTAMIENTO: ni insertar, ni alterar, ni borrar, ni vaciar.
--   3. LAS PUERTAS OFICIALES SIGUEN VIVAS, empezando por las dos que preocupaban:
--      `fn_set_rol` (escribe auditoría) y el cese de alguien con educación
--      vigente (el trigger INVOKER `fn_educacion_cerrar_al_cesar` escribe
--      auditoría). Se midió que el cese NO se rompe porque ese trigger solo
--      corre como `postgres`; esta prueba es la que lo sigue garantizando.
--
-- La última sección es un CONTROL, no una defensa: devuelve política y
-- privilegios a propósito y comprueba que el hueco vuelve. Sin él, un «todo
-- bloqueado» podría deberse a cualquier otra cosa. Y demuestra la frase de la
-- cabecera de la 0508: son dos cerrojos; el privilegio solo, sin política, lo
-- sigue frenando RLS.
--
-- OJO CON EL `session_replication_role`: el fixture se monta con `= replica` y se
-- devuelve a `origin` ANTES de simular el ataque; si no, se apagarían en silencio
-- todos los triggers de la sesión, incluidos los que esta prueba ejercita.
-- ============================================================================
begin;
select plan(27);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000040200', 'ZZ402', 'Sede de laboratorio 402', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000040201', 'LiderDO',    'Cuatrocientos', '00000000-0000-0000-0000-000000040200',
   'lider_do',        'x', '00000000-0000-0000-0000-00000004021a', '2024-01-01'),
  ('00000000-0000-0000-0000-000000040202', 'Admin',      'Cuatrocientos', '00000000-0000-0000-0000-000000040200',
   'admin',           'x', '00000000-0000-0000-0000-00000004021b', '2024-01-01'),
  ('00000000-0000-0000-0000-000000040203', 'LiderEquipo','Cuatrocientos', '00000000-0000-0000-0000-000000040200',
   'supervisor_sede', 'x', '00000000-0000-0000-0000-00000004021c', '2024-01-01'),
  ('00000000-0000-0000-0000-000000040204', 'IntegranteA','Cuatrocientos', '00000000-0000-0000-0000-000000040200',
   'integrante',      'x', null,                                    '2024-01-01'),
  ('00000000-0000-0000-0000-000000040205', 'IntegranteB','ConEducacion', '00000000-0000-0000-0000-000000040200',
   'integrante',      'x', null,                                    '2024-01-01');

-- B tiene una asignación de educación vigente: el cese tiene que cerrarla.
insert into asignaciones_educacion
  (persona_id, monto, institucion, costo_declarado, cobertura_pct, vigente_desde, vigente_hasta, familia_id)
values
  ('00000000-0000-0000-0000-000000040205', 300, 'Institución 402', 400, 75, '2026-01-01', '2027-12-31', gen_random_uuid());

-- Una fila sembrada, para que UPDATE / DELETE / TRUNCATE tengan algo que dañar.
insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo) values
  ('00000000-0000-0000-0000-000000040204', 'semilla', 'a', 'b', '00000000-0000-0000-0000-000000040202', 'Fila sembrada por la prueba 402');
set session_replication_role = origin;

-- ── 1-9 · EL ESTADO: no queda ni política ni privilegio de escritura ────────
select ok(not has_table_privilege('authenticated', 'public.correcciones_auditoria', 'INSERT'),
  'ESTADO · authenticated no tiene INSERT sobre la auditoría');

select ok(not has_table_privilege('authenticated', 'public.correcciones_auditoria', 'UPDATE'),
  'ESTADO · ni UPDATE: el rastro no se altera');

select ok(not has_table_privilege('authenticated', 'public.correcciones_auditoria', 'DELETE'),
  'ESTADO · ni DELETE: el rastro no se borra');

select ok(not has_table_privilege('authenticated', 'public.correcciones_auditoria', 'TRUNCATE'),
  'ESTADO · ni TRUNCATE: contra el que RLS no hace nada');

select ok(not has_table_privilege('anon', 'public.correcciones_auditoria', 'INSERT'),
  'ESTADO · anon tampoco inserta');

select ok(has_table_privilege('authenticated', 'public.correcciones_auditoria', 'SELECT'),
  'ESTADO · authenticated sigue LEYENDO: las tres políticas de lectura no se tocaron');

select is(
  (select count(*) from pg_policies
    where schemaname = 'public' and tablename = 'correcciones_auditoria'
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')),
  0::bigint,
  'ESTADO · la auditoría no tiene ninguna política de escritura');

select ok(has_table_privilege('service_role', 'public.correcciones_auditoria', 'INSERT'),
  'ESTADO · service_role conserva su INSERT: los scripts con llave de servicio siguen funcionando');

select is(
  (select array_agg(proname order by proname) from pg_proc
    where pronamespace = 'public'::regnamespace and not prosecdef
      and prosrc ~* 'insert\s+into\s+(public\.)?"?correcciones_auditoria"?\M'),
  array['fn_educacion_cerrar_al_cesar']::name[],
  'ESTADO · la ÚNICA función INVOKER que escribe la auditoría es la del trigger de educación; otra más fallaría en producción con «permission denied»');

-- ── 10-16 · EL COMPORTAMIENTO: nadie escribe directo, aunque sea admin ──────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004021a', true);
set role authenticated;

select throws_ok(
  $$ insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, corregido_at, motivo)
     values ('00000000-0000-0000-0000-000000040204', 'hora_entrada', '08:00', '09:30',
             '00000000-0000-0000-0000-000000040202', now() - interval '40 days', 'Rastro de contrabando 402') $$,
  '42501', 'permission denied for table correcciones_auditoria',
  'BLOQUEADO · el ataque: un lider_do ya no fabrica rastro a nombre del admin ni con fecha de hace 40 días');

select throws_ok(
  $$ update correcciones_auditoria set motivo = 'ALTERADO 402' $$,
  '42501', 'permission denied for table correcciones_auditoria',
  'BLOQUEADO · ni alterar el rastro que ya existe (antes: 0 filas afectadas por RLS, sin error)');

select throws_ok(
  $$ delete from correcciones_auditoria $$,
  '42501', 'permission denied for table correcciones_auditoria',
  'BLOQUEADO · ni borrarlo');

select throws_ok(
  $$ truncate correcciones_auditoria $$,
  '42501', 'permission denied for table correcciones_auditoria',
  'BLOQUEADO · ni vaciarlo entero: TRUNCATE no pasa por RLS y era lo único que no tenía cerradura');

reset role;

-- El mismo ataque desde un líder de equipo, sobre alguien de su sede.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004021c', true);
set role authenticated;

select throws_ok(
  $$ insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
     values ('00000000-0000-0000-0000-000000040204', 'hora_salida', '18:00', '17:00',
             '00000000-0000-0000-0000-000000040202', 'Rastro de contrabando 402') $$,
  '42501', 'permission denied for table correcciones_auditoria',
  'BLOQUEADO · tampoco un líder de equipo sobre alguien de su sede: no hace falta ser DO para fabricarlo');

reset role;

-- Ni un admin: hasta ellos pasan por las funciones.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004021b', true);
set role authenticated;

select throws_ok(
  $$ insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
     values ('00000000-0000-0000-0000-000000040204', 'x', 'a', 'b',
             '00000000-0000-0000-0000-000000040202', 'Rastro de contrabando 402') $$,
  '42501', 'permission denied for table correcciones_auditoria',
  'BLOQUEADO · un admin tampoco inserta directo: el rastro lo escribe la función, siempre');

reset role;

-- Y sin sesión (anon): la tabla tenía el privilegio por los defaults de Supabase.
set role anon;

select throws_ok(
  $$ insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
     values ('00000000-0000-0000-0000-000000040204', 'x', 'a', 'b',
             '00000000-0000-0000-0000-000000040202', 'Rastro de contrabando 402') $$,
  '42501', 'permission denied for table correcciones_auditoria',
  'BLOQUEADO · sin sesión, ni se acerca');

reset role;

-- ── 17-23 · LAS PUERTAS OFICIALES SIGUEN VIVAS ─────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004021a', true);
set role authenticated;

select lives_ok(
  $$ select fn_set_rol('00000000-0000-0000-0000-000000040204', 'supervisor_sede') $$,
  'PERMITIDO · un lider_do cambia un rol por fn_set_rol, que escribe auditoría como su dueño');

reset role;

select is(
  (select count(*) from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000040204'
      and campo_modificado = 'personas.rol'
      and valor_anterior = 'integrante' and valor_nuevo = 'supervisor_sede'),
  1::bigint,
  'PERMITIDO · y el rastro del cambio de rol quedó: la función inserta aunque quien la llama no pueda');

select is(
  (select corregido_por from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000040204' and campo_modificado = 'personas.rol'),
  '00000000-0000-0000-0000-000000040201'::uuid,
  'PERMITIDO · y firmado por quien de verdad lo hizo (el lider_do), no por quien uno escoja');

-- El caso que la advertencia daba por roto: el cese de alguien con educación vigente.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004021a', true);
set role authenticated;

select lives_ok(
  $$ select fn_cesar_persona('00000000-0000-0000-0000-000000040205', '2026-10-01', 'renuncia', null) $$,
  'SIN ROMPER EL CESE · un lider_do cesa a alguien con educación vigente: el trigger INVOKER corre como postgres dentro de fn_cesar_persona');

reset role;

select is(
  (select vigente_hasta from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-000000040205'),
  '2026-10-01'::date,
  'SIN ROMPER EL CESE · la asignación de educación se cerró al día del cese');

select is(
  (select count(*) from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000040205' and campo_modificado = 'educacion_cierre_por_cese'),
  1::bigint,
  'SIN ROMPER EL CESE · y quedó el rastro `educacion_cierre_por_cese`, escrito por el trigger de educación');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004021a', true);
set role authenticated;

select ok(
  (select count(*) from correcciones_auditoria) >= 3,
  'LECTURA · un lider_do sigue viendo el rastro (la semilla, el cambio de rol y los del cese)');

reset role;

-- ── 24-27 · EL CONTROL: se reabre a propósito para probar que ESTO era el hueco ──
-- Solo el privilegio, sin política: RLS lo sigue negando. Son dos cerrojos
-- independientes, y por eso reabrir exige deshacer los dos.
grant insert on correcciones_auditoria to authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004021a', true);
set role authenticated;

select throws_ok(
  $$ insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
     values ('00000000-0000-0000-0000-000000040204', 'x', 'a', 'b',
             '00000000-0000-0000-0000-000000040202', 'Rastro de contrabando 402') $$,
  '42501', 'new row violates row-level security policy for table "correcciones_auditoria"',
  'CONTROL · con solo el privilegio devuelto, RLS sigue frenando: son dos cerrojos');

reset role;

-- Privilegio y política devueltos: es el estado de la 0003 + 0004. El `drop` es
-- para que la prueba también corra SIN la 0508 (donde la política ya existe) y
-- falle con claridad en vez de abortar la transacción.
drop policy if exists auditoria_insert_admin_lider on correcciones_auditoria;
create policy auditoria_insert_admin_lider on correcciones_auditoria
  for insert to authenticated with check (fn_es_admin_o_lider());

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004021a', true);
set role authenticated;

select lives_ok(
  $$ insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, corregido_at, motivo)
     values ('00000000-0000-0000-0000-000000040204', 'hora_entrada', '08:00', '09:30',
             '00000000-0000-0000-0000-000000040202', now() - interval '40 days', 'Rastro de contrabando 402') $$,
  'CONTROL · con la política y el privilegio devueltos, el hueco vuelve: lo que lo cierra es la 0508');

reset role;

select is(
  (select count(*) from correcciones_auditoria
    where motivo = 'Rastro de contrabando 402'
      and corregido_por = '00000000-0000-0000-0000-000000040202'
      and corregido_at < now() - interval '39 days'),
  1::bigint,
  'CONTROL · y la fila falsa existe: a nombre del admin y con fecha de hace 40 días');

-- Y el TRUNCATE: el privilegio solo, sin ninguna política, basta para vaciarla.
grant truncate on correcciones_auditoria to authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004021a', true);
set role authenticated;

select lives_ok(
  $$ truncate correcciones_auditoria $$,
  'CONTROL · con TRUNCATE devuelto, un lider_do vacía el rastro entero: RLS nunca estuvo en juego');

reset role;

select * from finish();
rollback;
