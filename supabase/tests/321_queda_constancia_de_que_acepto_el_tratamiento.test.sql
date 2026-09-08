-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/0404_....sql.
-- ============================================================================
-- 321_queda_constancia_de_que_acepto_el_tratamiento.test.sql
-- ============================================================================
-- Lo que esta prueba vigila:
--
--   1. Queda constancia con el texto exacto que la persona aceptó — no un
--      «aceptó: sí», que no probaría QUÉ aceptó.
--   2. Un texto vacío o de relleno no se guarda: una constancia sin texto no
--      es una constancia.
--   3. Es APPEND-ONLY: aceptar dos veces deja DOS filas, no una actualizada.
--      Es lo que separa una prueba legal de un estado.
--   4. RLS: la ve la propia persona, la ve quien aprueba su solicitud
--      (admin/líder), y NO la ve una compañera cualquiera.
--
-- Ojo con el punto 4: sin `set local role authenticated` la sesión de pgTAP
-- corre como dueña de la tabla y se salta RLS entera — la prueba pasaría sin
-- probar nada. Lo aprendimos en rojo con la 319; mismo patrón que 118/121/136.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000e10a', 'ZZCON', 'Sede de laboratorio consentimiento', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000e20a', 'ConAdmin', 'Lab', '00000000-0000-0000-0000-00000000e10a', 'admin', 'x', '00000000-0000-0000-0000-00000000eaaa', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000e30a', 'ConColab', 'Lab', '00000000-0000-0000-0000-00000000e10a', 'integrante', 'x', '00000000-0000-0000-0000-00000000ebbb', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000e40a', 'ConOtra', 'Lab', '00000000-0000-0000-0000-00000000e10a', 'integrante', 'x', '00000000-0000-0000-0000-00000000eccc', '2024-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ebbb', true);

-- ── 1 · Queda constancia, con su texto ──────────────────────────────────────
select is((select count(*)::int from consentimientos_datos_personales
           where persona_id = '00000000-0000-0000-0000-00000000e30a'),
  0, 'DE PARTIDA · sin aceptar nada, no hay constancia');

select lives_ok($$ select fn_registrar_mi_consentimiento('foto_dni',
    'Declaro que el Documento Nacional de Identidad (DNI) que adjunto corresponde a mi persona y autorizo el tratamiento de mis datos personales.') $$,
  'ACEPTA · deja constancia sin problema');

select is((select texto from consentimientos_datos_personales
           where persona_id = '00000000-0000-0000-0000-00000000e30a'),
  'Declaro que el Documento Nacional de Identidad (DNI) que adjunto corresponde a mi persona y autorizo el tratamiento de mis datos personales.',
  'ACEPTA · se guarda el texto EXACTO que tenía delante, no un booleano');

select is((select finalidad from consentimientos_datos_personales
           where persona_id = '00000000-0000-0000-0000-00000000e30a'),
  'foto_dni', 'ACEPTA · queda anotado para qué se dio');

-- ── 2 · Una constancia vacía no es constancia ───────────────────────────────
select throws_ok($$ select fn_registrar_mi_consentimiento('foto_dni', '') $$,
  null, null, 'VACÍO · un texto vacío se rechaza');

select throws_ok($$ select fn_registrar_mi_consentimiento('', 'Declaro que el DNI que adjunto corresponde a mi persona y autorizo su tratamiento.') $$,
  null, null, 'SIN FINALIDAD · no se guarda sin decir para qué');

-- ── 3 · Append-only: dos aceptaciones son dos filas ─────────────────────────
select fn_registrar_mi_consentimiento('foto_dni',
  'Segunda aceptación, con la redacción de otro día, que también tiene que quedar guardada entera.');

select is((select count(*)::int from consentimientos_datos_personales
           where persona_id = '00000000-0000-0000-0000-00000000e30a'),
  2, 'APPEND-ONLY · aceptar de nuevo agrega una fila, no pisa la anterior');

-- ── 4 · RLS de verdad, con el rol puesto ────────────────────────────────────
set local role authenticated;

select is((select count(*)::int from consentimientos_datos_personales
           where persona_id = '00000000-0000-0000-0000-00000000e30a'),
  2, 'RLS · la propia persona ve sus dos constancias');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000eccc', true);
set local role authenticated;

select is((select count(*)::int from consentimientos_datos_personales
           where persona_id = '00000000-0000-0000-0000-00000000e30a'),
  0, 'RLS · una compañera cualquiera no ve la constancia ajena');

-- Y la otra mitad de la regla, que es la que se olvida: que quien SÍ puede,
-- pueda. Sin esta aserción, borrar la policy de admin dejaría la prueba en
-- verde — el defecto que esta misma revisión encontró en la prueba 319.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000eaaa', true);
set local role authenticated;

select is((select count(*)::int from consentimientos_datos_personales
           where persona_id = '00000000-0000-0000-0000-00000000e30a'),
  2, 'RLS · un administrador sí ve la constancia, que es lo que la hace servir de prueba');

reset role;

select * from finish();
rollback;
