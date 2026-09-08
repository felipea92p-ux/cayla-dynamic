-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/0407_....sql.
-- ============================================================================
-- 324_el_dni_se_puede_cancelar_y_queda_dicho.test.sql
-- ============================================================================
-- Lo que esta prueba vigila:
--
--   1. DO cancela: la ficha queda sin las dos rutas, y la función DEVUELVE las
--      que había — sin eso el cliente no sabría qué archivos borrar y la
--      cancelación se quedaría a medias, con los bytes intactos en el almacén.
--   2. Queda dicho en `correcciones_auditoria`: quién, qué había antes y por
--      qué. Un borrado de un documento de identidad sin eso es indistinguible
--      de un descuido.
--   3. El motivo es obligatorio.
--   4. Quien no es DO no puede — ni la encargada de la propia sede, que sí
--      aprueba otras cosas de su equipo desde la 0403.
--   5. No se puede "cancelar" lo que no existe: dice que no hay nada, en vez de
--      dejar una fila de auditoría que afirma un borrado que no ocurrió.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000ca10', 'ZZCAN', 'Sede laboratorio cancelación', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-00000000ca20', 'CanAdmin', 'Lab', '00000000-0000-0000-0000-00000000ca10', 'admin', 'x', '00000000-0000-0000-0000-00000000caa1', '2024-01-01'),
  ('00000000-0000-0000-0000-00000000ca30', 'CanEncargada', 'Lab', '00000000-0000-0000-0000-00000000ca10', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000caa2', '2024-01-01'),
  ('00000000-0000-0000-0000-00000000ca40', 'CanColab', 'Lab', '00000000-0000-0000-0000-00000000ca10', 'integrante', 'x', '00000000-0000-0000-0000-00000000caa3', '2024-01-01');
set session_replication_role = origin;

insert into datos_personales (persona_id, foto_dni_anverso_ruta, foto_dni_reverso_ruta)
values ('00000000-0000-0000-0000-00000000ca40',
        'solicitud/00000000-0000-0000-0000-00000000ca40/dni-anverso-1.jpg',
        'solicitud/00000000-0000-0000-0000-00000000ca40/dni-reverso-1.jpg');

-- ── 3 · El motivo es obligatorio ────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000caa1', true);

select throws_ok($$ select fn_borrar_dni_de('00000000-0000-0000-0000-00000000ca40', '  ') $$,
  null, null, 'MOTIVO · sin motivo escrito no se cancela nada');

-- ── 4 · Quien no es DO no puede ─────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000caa2', true);
select throws_ok($$ select fn_borrar_dni_de('00000000-0000-0000-0000-00000000ca40', 'lo pidió ella') $$,
  null, null, 'ENCARGADA · no puede cancelar el DNI de su equipo — identidad es de DO');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000caa3', true);
select throws_ok($$ select fn_borrar_dni_de('00000000-0000-0000-0000-00000000ca40', 'quiero borrarlo') $$,
  null, null, 'LA PROPIA PERSONA · tampoco se lo borra sola: lo pide por correo y DO decide');

-- La ficha sigue intacta después de los tres intentos fallidos.
select is((select foto_dni_anverso_ruta from datos_personales
           where persona_id = '00000000-0000-0000-0000-00000000ca40'),
  'solicitud/00000000-0000-0000-0000-00000000ca40/dni-anverso-1.jpg',
  'INTACTO · ninguno de los intentos rechazados tocó la ficha');

-- ── 1 · DO cancela, y devuelve las rutas para borrar los archivos ───────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000caa1', true);

select set_eq(
  $$ select ruta from fn_borrar_dni_de('00000000-0000-0000-0000-00000000ca40',
       'A pedido de la colaboradora por correo del 2026-09-08; ya cesada y fuera del plazo de conservación.') $$,
  $$ values ('solicitud/00000000-0000-0000-0000-00000000ca40/dni-anverso-1.jpg'),
            ('solicitud/00000000-0000-0000-0000-00000000ca40/dni-reverso-1.jpg') $$,
  'CANCELA · devuelve las DOS rutas, que es lo que el cliente necesita para borrar los archivos');

select ok((select foto_dni_anverso_ruta is null and foto_dni_reverso_ruta is null
             from datos_personales where persona_id = '00000000-0000-0000-0000-00000000ca40'),
  'CANCELA · la ficha queda sin ninguna de las dos rutas');

-- ── 2 · Y queda dicho ───────────────────────────────────────────────────────
select is((select count(*)::int from correcciones_auditoria
           where persona_id = '00000000-0000-0000-0000-00000000ca40'
             and campo_modificado = 'datos_personales.foto_dni'),
  1, 'AUDITORÍA · queda una fila de la cancelación');

select ok((select valor_anterior like '%dni-anverso-1.jpg%' and valor_nuevo is null
             and corregido_por = '00000000-0000-0000-0000-00000000ca20'
             and motivo like 'A pedido de la colaboradora%'
             from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-00000000ca40'
              and campo_modificado = 'datos_personales.foto_dni'),
  'AUDITORÍA · dice qué había antes, que ahora no hay nada, quién lo hizo y por qué');

-- ── 5 · No se cancela lo que no existe ──────────────────────────────────────
select throws_ok($$ select fn_borrar_dni_de('00000000-0000-0000-0000-00000000ca40', 'otra vez') $$,
  null, null, 'VACÍO · sobre una ficha ya sin DNI se niega, en vez de auditar un borrado que no pasó');

select * from finish();
rollback;
