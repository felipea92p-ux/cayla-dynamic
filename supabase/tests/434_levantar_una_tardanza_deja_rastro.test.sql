-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 434_levantar_una_tardanza_deja_rastro.test.sql — 0541
-- ============================================================================
-- Perdonar una tardanza, cambiar el motivo del perdón y quitarlo deben dejar
-- fila en correcciones_auditoria. Antes (0053/0438) solo tocaban
-- tardanzas_justificadas y el historial de Correcciones no los mostraba.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre)
values ('aaaaaaaa-0541-0000-0000-000000000001','T41','Sede de la prueba 434');
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('bbbbbbbb-0541-0000-0000-000000000001','00000000-0000-0000-0000-000000000000',
        'authenticated','authenticated','prueba434@cayla.local','x', now(), now(), now());
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id) values
 ('cccccccc-0541-0000-0000-00000000000a','Ada','Admin','aaaaaaaa-0541-0000-0000-000000000001','x','admin','bbbbbbbb-0541-0000-0000-000000000001'),
 ('cccccccc-0541-0000-0000-00000000000b','Rosa','Trujillo','aaaaaaaa-0541-0000-0000-000000000001','x','integrante', null);
set local request.jwt.claims = '{"sub":"bbbbbbbb-0541-0000-0000-000000000001","role":"authenticated"}';

select fn_levantar_tardanza('cccccccc-0541-0000-0000-00000000000b', date '2019-03-04', 'salud', null);
select is((select count(*)::int from correcciones_auditoria
            where persona_id = 'cccccccc-0541-0000-0000-00000000000b' and campo_modificado = 'tardanza_levantada'),
          1, 'levantar deja una fila en el historial');
select is((select valor_anterior || ' / ' || valor_nuevo || ' / ' || corregido_por::text from correcciones_auditoria
            where persona_id = 'cccccccc-0541-0000-0000-00000000000b' and campo_modificado = 'tardanza_levantada'),
          '2019-03-04 / salud / cccccccc-0541-0000-0000-00000000000a', 'la fila trae el día, el motivo y quién lo hizo');

select fn_levantar_tardanza('cccccccc-0541-0000-0000-00000000000b', date '2019-03-04', 'otro', 'paro de transporte');
select is((select count(*)::int from correcciones_auditoria
            where persona_id = 'cccccccc-0541-0000-0000-00000000000b' and campo_modificado = 'tardanza_levantada'),
          2, 'cambiar el motivo del perdón también deja fila');
-- La fila del cambio se elige por lo que dice (su motivo nuevo es 'otro'), NO por ser
-- «la última»: las dos filas nacen en esta misma transacción, así que `corregido_at`
-- (default now()) empata, y `id desc` es un uuid al azar — la prueba acertaba la mitad
-- de las veces (falló en main el 2026-10-20 y en el PR #573 sin tocar nada de SQL).
select matches((select motivo from correcciones_auditoria
                 where persona_id = 'cccccccc-0541-0000-0000-00000000000b' and campo_modificado = 'tardanza_levantada'
                   and valor_nuevo = 'otro'),
               'antes: salud', 'la fila del cambio dice cuál era el motivo anterior');

select fn_quitar_levantamiento('cccccccc-0541-0000-0000-00000000000b', date '2019-03-04');
select is((select count(*)::int from correcciones_auditoria
            where persona_id = 'cccccccc-0541-0000-0000-00000000000b' and campo_modificado = 'tardanza_levantamiento_quitado'),
          1, 'quitar el perdón deja fila');
select is((select count(*)::int from tardanzas_justificadas where persona_id = 'cccccccc-0541-0000-0000-00000000000b'),
          0, 'y la tardanza vuelve a contar');

select fn_quitar_levantamiento('cccccccc-0541-0000-0000-00000000000b', date '2019-03-04');
select is((select count(*)::int from correcciones_auditoria
            where persona_id = 'cccccccc-0541-0000-0000-00000000000b' and campo_modificado = 'tardanza_levantamiento_quitado'),
          1, 'quitar lo que no existe no inventa un rastro');

select * from finish();
rollback;
