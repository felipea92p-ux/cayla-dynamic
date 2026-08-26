-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 241_el_candado_del_mes_pagado_mide_la_jornada.test.sql — 0307
-- ============================================================================
-- El periodo va del 29 al 28. Un turno del 28 que cierra a las 00:30 del 29 deja
-- una salida cuyo reloj cae en el periodo SIGUIENTE mientras su `fecha_jornada`
-- dice 28, que es el mes que ya se pagó. Antes de la 0307 las seis puertas del
-- candado miraban el reloj, así que a esa marca se le dejaba anular, corregir y
-- —con `delete` duro— eliminar, con el mes ya cobrado.
--
-- Las aserciones 1 a 6 son las que mueren sin la 0307: contra los cuerpos de la
-- 0102 y la 0188 se ponen rojas las seis. Las 7 a 11 son lo contrario, y son
-- igual de importantes: vigilan que el arreglo no empiece a frenar lo que
-- siempre estuvo bien. Un falso positivo aquí le impide a una encargada
-- corregir un día legítimo, y en esta casa eso cuesta más que la falta.
--
-- La 10 es LA TRAMPA de esta migración, y por eso está escrita: `fn_corregir_
-- marca` tiene un guard que dice «aquí solo se corrige la hora dentro de su
-- mismo día», comparando contra el día del RELOJ. Si alguien "termina el
-- trabajo" moviendo también ese guard a la fecha de jornada, saltaría siempre
-- para una marca de madrugada y esa marca quedaría imposible de corregir. La 10
-- se pone roja el día que eso pase.
-- ============================================================================
begin;
select plan(11);

-- ── El laboratorio ──────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre)
values ('aaaaaaaa-0307-0000-0000-000000000001','T07','Sede de la prueba 241');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('bbbbbbbb-0307-0000-0000-000000000001','00000000-0000-0000-0000-000000000000',
        'authenticated','authenticated','prueba241@cayla.local','x', now(), now(), now());

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id) values
 ('cccccccc-0307-0000-0000-00000000000a','Ada','Admin',
  'aaaaaaaa-0307-0000-0000-000000000001','x','admin','bbbbbbbb-0307-0000-0000-000000000001'),
 ('cccccccc-0307-0000-0000-00000000000b','Rosa','Trujillo',
  'aaaaaaaa-0307-0000-0000-000000000001','x','integrante', null);

-- El de agosto ya se pagó; el de septiembre sigue abierto.
insert into periodos_planilla (fecha_ini, fecha_fin, estado) values
 ('2026-07-29','2026-08-28','pagado'),
 ('2026-08-29','2026-09-28','abierto');

set local request.jwt.claims = '{"sub":"bbbbbbbb-0307-0000-0000-000000000001","role":"authenticated"}';

-- Crea una marca y devuelve su id. `p_fj` es la fecha_jornada: null es el caso
-- normal —el día lo pone el reloj— y con valor es la marca de madrugada.
create or replace function _m241(p_ts timestamptz, p_fj date, p_anulada bool default false)
returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca,
                        fecha_jornada, anulada_at, anulada_motivo, anulada_por)
  values (gen_random_uuid(),'cccccccc-0307-0000-0000-00000000000b',
          'aaaaaaaa-0307-0000-0000-000000000001','salida_final', p_ts, p_fj,
          case when p_anulada then now() end,
          case when p_anulada then 'anulada para la prueba' end,
          case when p_anulada then 'cccccccc-0307-0000-0000-00000000000a'::uuid end)
  returning id into v;
  return v;
end $f$;

-- ── § 1 · Lo que la 0307 cierra: la madrugada del mes ya pagado ─────────────
select throws_ok(
  format('select fn_anular_marcaje(%L, ''prueba 241'')', _m241('2026-08-29 00:30-05','2026-08-28')),
  null,
  'anular una marca de madrugada cuya JORNADA cae en el mes pagado se frena');

select throws_ok(
  format('select fn_reactivar_marcaje(%L, ''prueba 241'')', _m241('2026-08-29 00:30-05','2026-08-28', true)),
  null,
  'reactivarla se frena');

select throws_ok(
  format('select fn_corregir_marca(%L, null, %L, ''prueba 241'')',
         _m241('2026-08-29 00:30-05','2026-08-28'), '2026-08-29 00:45-05'),
  null,
  'corregirle la hora se frena');

select throws_ok(
  format('select fn_corregir_marcaje(%L, %L, ''prueba 241'')',
         _m241('2026-08-29 00:30-05','2026-08-28'), '2026-08-29 00:45-05'),
  null,
  'moverle el timestamp se frena');

select throws_ok(
  format('select fn_eliminar_marcaje(%L, ''prueba 241'')', _m241('2026-08-29 00:30-05','2026-08-28')),
  null,
  'eliminarla se frena — y esta es la que hacía `delete` duro');

-- El auto-cierre necesita su propia marca: `fn_confirmar_auto_cierre` rechaza
-- de entrada cualquiera cuyo `origen` no sea 'auto_cierre', y ese rechazo NO
-- es el candado. La primera versión de esta prueba usaba una marca normal y se
-- ponía verde por el motivo equivocado — habría seguido verde sin la 0307.
create or replace function _m241_auto(p_ts timestamptz, p_fj date)
returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca,
                        fecha_jornada, origen, estado_revision)
  values (gen_random_uuid(),'cccccccc-0307-0000-0000-00000000000b',
          'aaaaaaaa-0307-0000-0000-000000000001','salida_final', p_ts, p_fj,
          'auto_cierre','pendiente_revision')
  returning id into v;
  return v;
end $f$;

select throws_ok(
  format('select fn_confirmar_auto_cierre(%L, ''prueba 241'')',
         _m241_auto('2026-08-29 00:30-05','2026-08-28')),
  null,
  'confirmar su auto-cierre se frena');

-- ── § 2 · Lo que NO puede empezar a frenar ─────────────────────────────────
select lives_ok(
  format('select fn_eliminar_marcaje(%L, ''prueba 241'')', _m241('2026-09-15 10:00-05', null)),
  'un día corriente de un periodo abierto se sigue pudiendo tocar');

select lives_ok(
  format('select fn_anular_marcaje(%L, ''prueba 241'')', _m241('2026-08-30 00:30-05','2026-08-29')),
  'una marca de madrugada cuya jornada cae en un periodo ABIERTO se sigue pudiendo anular');

select lives_ok(
  format('select fn_eliminar_marcaje(%L, ''prueba 241'')', _m241('2026-08-29 00:30-05', null)),
  'sin fecha_jornada manda el reloj, igual que antes de la 0240');

select lives_ok(
  format('select fn_corregir_marca(%L, null, %L, ''prueba 241'')',
         _m241('2026-08-30 00:30-05','2026-08-29'), '2026-08-30 00:45-05'),
  'LA TRAMPA: a una marca de madrugada se le sigue pudiendo corregir la hora dentro de su día de reloj');

-- ── § 3 · La regla, dicha una sola vez ─────────────────────────────────────
select is(
  array[ fn_fecha_de_jornada('2026-08-29 00:30-05', '2026-08-28'),
         fn_fecha_de_jornada('2026-08-29 00:30-05', null) ],
  array[ '2026-08-28'::date, '2026-08-29'::date ],
  'fn_fecha_de_jornada prefiere la jornada y cae al reloj de Lima cuando no la hay');

select * from finish();
rollback;
