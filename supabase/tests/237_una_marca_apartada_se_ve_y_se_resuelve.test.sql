-- ============================================================================
-- 237_una_marca_apartada_se_ve_y_se_resuelve.test.sql
-- ============================================================================
-- La 0304. Cuando el terminal no logra enviar una marca seis veces, la aparta —y
-- hasta ahora se quedaba en el navegador de esa Mac mini, con un aviso rojo que
-- nada apagaba y que nadie podía atender.
--
-- Lo que esta prueba fija es que reponerla conserva LA HORA ORIGINAL. Si se
-- registrara con la hora en que alguien la repone, el día de esa persona
-- cambiaría de forma: otra entrada, otras horas trabajadas, otra tardanza — y
-- nadie lo notaría, porque el marcaje existiría igual.
-- ============================================================================
begin;
select plan(14);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000e0', 'ZZAP1', 'Sede apartadas 1', true),
  ('00000000-0000-0000-0000-0000000000e5', 'ZZAP2', 'Sede apartadas 2', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000000e1', 'ApDO', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000e0', 'lider_do', 'x',
   '00000000-0000-0000-0000-0000000000e9', '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000e4', 'ApOtraSede', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000e5', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000000e7', '2021-01-01'),
  ('00000000-0000-0000-0000-0000000000e2', 'ApAna', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000e0', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000000e6', '2025-01-02');
set session_replication_role = origin;

-- Sin sesión: es el terminal quien reporta, y el terminal no es una persona.
select set_config('request.jwt.claim.sub', '', true);

-- ── 1 · El terminal reporta, y reportar dos veces no duplica ───────────────
select isnt(
  fn_marca_apartada_reportar(
    '00000000-0000-0000-0000-00000000ab01'::uuid,
    '00000000-0000-0000-0000-0000000000e2'::uuid,
    'entrada'::tipo_marca, '2026-08-13 08:57:00-05'::timestamptz,
    null, 'rechazada seis veces'),
  null, 'REPORTA · el terminal deja constancia de la marca que no pudo enviar');

select lives_ok($$
  select fn_marca_apartada_reportar(
    '00000000-0000-0000-0000-00000000ab01'::uuid,
    '00000000-0000-0000-0000-0000000000e2'::uuid,
    'entrada'::tipo_marca, '2026-08-13 08:57:00-05'::timestamptz,
    null, 'rechazada seis veces') $$,
  'REPORTA · reportarla otra vez no falla');

select is(
  (select count(*)::int from marcas_apartadas
    where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
  1, 'REPORTA · y no la duplica: el terminal la sube en cada arranque');


-- ── 2 · Se ve desde el panel, y solo quien debe ────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e9', true);

select is(
  (select count(*)::int from fn_marcas_apartadas()
    where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
  1, 'VER · DO la ve en Correcciones');

select is(
  (select persona from fn_marcas_apartadas()
    where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
  'ApAna Laboratorio', 'VER · con el nombre de quién es, que era lo que faltaba');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e7', true);

select is(
  (select count(*)::int from fn_marcas_apartadas()
    where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
  0, 'VER · una encargada de OTRA sede no la ve');

select throws_like($$
  select fn_marca_apartada_resolver(
    (select id from marcas_apartadas where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
    'repuesta', 'no debería poder') $$,
  '%otra sede%',
  'VER · ni la puede resolver');


-- ── 3 · Resolver exige decir por qué ───────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e9', true);

select throws_like($$
  select fn_marca_apartada_resolver(
    (select id from marcas_apartadas where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
    'repuesta', '') $$,
  '%Escribe por qué%',
  'MOTIVO · sin motivo no se resuelve: esto decide si un día queda registrado');

select throws_like($$
  select fn_marca_apartada_resolver(
    (select id from marcas_apartadas where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
    'perdonada', 'motivo cualquiera') $$,
  '%repuesta%',
  'MOTIVO · y la resolución solo puede ser una de las dos');


-- ── 4 · Reponerla conserva LA HORA ORIGINAL ────────────────────────────────
-- El corazón de la prueba. Si entrara con la hora de hoy, el día de esa persona
-- cambiaría de forma y nadie lo notaría.
select lives_ok($$
  select fn_marca_apartada_resolver(
    (select id from marcas_apartadas where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
    'repuesta', 'la marcó a las 8:57 y el terminal no pudo enviarla') $$,
  'REPONER · se repone');

select is(
  (select timestamp_marca from marcajes
    where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
  '2026-08-13 08:57:00-05'::timestamptz,
  'REPONER · con la hora en que la persona marcó, no con la de hoy');

select is(
  (select resolucion from marcas_apartadas
    where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
  'repuesta', 'REPONER · y la apartada queda resuelta, con su motivo y su autor');

select throws_like($$
  select fn_marca_apartada_resolver(
    (select id from marcas_apartadas where client_uuid = '00000000-0000-0000-0000-00000000ab01'),
    'improcedente', 'segundo intento') $$,
  '%ya se resolvió%',
  'REPONER · y no se puede resolver dos veces');


-- ── 5 · Lo que apaga el aviso del terminal ─────────────────────────────────
select is(
  (select count(*)::int from fn_marcas_apartadas_resueltas(
     array['00000000-0000-0000-0000-00000000ab01']::uuid[])),
  1,
  'AVISO · el terminal pregunta por las suyas y esta ya está resuelta: la borra y el aviso baja');

select * from finish();
rollback;
