-- 462 · La invitación a la cuenta sale sola una vez (migración 0572)
--
-- Lo que se protege: a cada persona le llega como mucho UNA invitación
-- automática en su vida y UNA manual por correo. La ruta reserva la fila ANTES
-- de mandar el correo, así que si la base deja pasar una segunda reserva, sale
-- un segundo correo. Por eso estas aserciones miran la base y no la ruta: es el
-- único freno que alcanza también a dos pedidos simultáneos.
--
-- Control: sin la 0572 la tabla no existe y el archivo aborta en la primera
-- aserción.

begin;
select plan(15);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000005c1', 'ZZINV', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000005a1', 'InvAdmin', 'Lab', '00000000-0000-0000-0000-0000000005c1', 'admin', 'x', '00000000-0000-0000-0000-0000000005d1'),
  ('00000000-0000-0000-0000-0000000005a3', 'InvConCuenta', 'Lab', '00000000-0000-0000-0000-0000000005c1', 'integrante', 'x', '00000000-0000-0000-0000-0000000005d3');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-0000000005a2', 'InvNueva', 'Lab', '00000000-0000-0000-0000-0000000005c1', 'x');

-- ── LA AUTOMÁTICA: UNA EN LA VIDA ───────────────────────────────────────────
select lives_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo)
                   values ('00000000-0000-0000-0000-0000000005a2', 'nueva@lab.pe', 'automatica', 'invitacion') $$,
  'AUTOMÁTICA · la primera se reserva');
select throws_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo)
                    values ('00000000-0000-0000-0000-0000000005a2', 'nueva@lab.pe', 'automatica', 'invitacion') $$,
  '23505', null, 'AUTOMÁTICA · una segunda reserva simultánea choca y no sale el correo');
select throws_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo)
                    values ('00000000-0000-0000-0000-0000000005a2', 'otro@lab.pe', 'automatica', 'invitacion') $$,
  '23505', null, 'AUTOMÁTICA · tampoco a otro correo: es una por persona, no por correo');

-- Un envío que falló no llegó: no gasta la automática.
update invitaciones_cuenta set estado = 'fallida', detalle = 'tope de correos', resuelta_at = now()
 where persona_id = '00000000-0000-0000-0000-0000000005a2';
select lives_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo)
                   values ('00000000-0000-0000-0000-0000000005a2', 'nueva@lab.pe', 'automatica', 'invitacion') $$,
  'AUTOMÁTICA · si la anterior falló, se puede reintentar');
update invitaciones_cuenta set estado = 'enviada', resuelta_at = now()
 where persona_id = '00000000-0000-0000-0000-0000000005a2' and estado = 'reservada';
select throws_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo)
                    values ('00000000-0000-0000-0000-0000000005a2', 'nueva@lab.pe', 'automatica', 'invitacion') $$,
  '23505', null, 'AUTOMÁTICA · una vez enviada, no hay otra');

-- ── LA MANUAL: UNA POR CORREO ───────────────────────────────────────────────
select lives_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo, enviada_por)
                   values ('00000000-0000-0000-0000-0000000005a3', 'concuenta@lab.pe', 'manual', 'recuperacion', '00000000-0000-0000-0000-0000000005a1') $$,
  'MANUAL · el primer reenvío se reserva');
select throws_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo, enviada_por)
                    values ('00000000-0000-0000-0000-0000000005a3', 'concuenta@lab.pe', 'manual', 'invitacion', '00000000-0000-0000-0000-0000000005a1') $$,
  '23505', null, 'MANUAL · el segundo al mismo correo choca, sea invitación o recuperar acceso');
select lives_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo, enviada_por)
                   values ('00000000-0000-0000-0000-0000000005a3', 'corregido@lab.pe', 'manual', 'recuperacion', '00000000-0000-0000-0000-0000000005a1') $$,
  'MANUAL · corregir el correo abre un envío más, al correo nuevo');

-- ── ESTADOS IMPOSIBLES ──────────────────────────────────────────────────────
select throws_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo, enviada_por)
                    values ('00000000-0000-0000-0000-0000000005a3', 'ConCuenta@lab.pe ', 'manual', 'invitacion', '00000000-0000-0000-0000-0000000005a1') $$,
  '23514', null, 'CORREO · con mayúsculas o espacios no entra: burlaría el «uno por correo»');
select throws_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo, enviada_por)
                    values ('00000000-0000-0000-0000-0000000005a3', 'x@lab.pe', 'automatica', 'invitacion', '00000000-0000-0000-0000-0000000005a1') $$,
  '23514', null, 'AUTOR · una automática no tiene autor');
select throws_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo)
                    values ('00000000-0000-0000-0000-0000000005a3', 'y@lab.pe', 'manual', 'invitacion') $$,
  '23514', null, 'AUTOR · una manual sin autor no entra');
select throws_ok($$ update invitaciones_cuenta set estado = 'fallida', resuelta_at = now()
                     where persona_id = '00000000-0000-0000-0000-0000000005a3' and correo = 'corregido@lab.pe' $$,
  '23514', null, 'CIERRE · un fallo sin motivo no entra');
select throws_ok($$ update invitaciones_cuenta set estado = 'enviada'
                     where persona_id = '00000000-0000-0000-0000-0000000005a3' and correo = 'corregido@lab.pe' $$,
  '23514', null, 'CIERRE · cerrada sin fecha de cierre no entra');

-- ── QUIÉN LEE Y QUIÉN ESCRIBE ───────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000005d3', true);
select is((select count(*)::int from invitaciones_cuenta), 0,
  'LECTURA · una integrante no ve a qué correos se mandó el acceso, ni el suyo');
select throws_ok($$ insert into invitaciones_cuenta (persona_id, correo, origen, tipo, enviada_por)
                    values ('00000000-0000-0000-0000-0000000005a3', 'z@lab.pe', 'manual', 'invitacion', '00000000-0000-0000-0000-0000000005a3') $$,
  '42501', null, 'ESCRITURA · desde el navegador no se escribe: solo la ruta con la llave de servicio');

select * from finish();
rollback;
