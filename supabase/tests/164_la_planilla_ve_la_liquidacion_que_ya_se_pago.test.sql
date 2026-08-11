-- ============================================================================
-- 164_la_planilla_ve_la_liquidacion_que_ya_se_pago.test.sql
-- ============================================================================
-- EL CASO REAL, medido en producción el 2026-08-10:
--
--   Seis personas del periodo 28/06–28/07 tienen el mismo mes registrado DOS
--   veces: S/1,145.87 en la foto del periodo, además de sus liquidaciones. Las
--   seis dicen «primero el periodo, después la liquidación» — el 28/07 se cerró
--   el mes con ellas dentro, porque nada en pantalla avisó de que ya habían
--   cobrado.
--
--   La causa: `liquidacion_pagada` aparecía en UN SOLO archivo de todo el
--   repositorio, el que la creó. Ni fn_planilla_calcular, ni
--   fn_planilla_congelar, ni la pantalla la leían jamás. La 0210 abre esa
--   puerta —solo para mirar— y esta prueba la vigila.
--
-- QUÉ DEFIENDE ESTE ARCHIVO, Y QUÉ NO
--
--   Defiende que la función DIGA lo que hay que decir y CALLE lo que no. Las
--   dos mitades importan igual, y la segunda más de lo que parece: un aviso que
--   salta cuando no toca enseña a ignorarlo, y el día que salte de verdad ya
--   nadie lo lee. Por eso hay tantas pruebas de silencio como de aviso.
--
--   NO defiende contra el doble pago en sí. Esta función no descuenta nada ni
--   excluye a nadie: solo informa. Quien evita el doble pago sigue siendo la
--   persona que aprieta «Ya le pagué aparte». Confundir las dos cosas sería
--   creerse protegido por un cartel.
--
--   Tampoco defiende contra el OTRO defecto de la misma familia: que la
--   liquidación venga inflada porque el pago se divide entre los días del rango
--   parcial. Eso es aritmética de otra función y va en su propia migración.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000016400', 'ZZLIQ', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-000000016401', 'LiqAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000016400', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000016409');

-- Tres personas con historias distintas a propósito.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, estado,
                      fecha_cese, motivo_cese, fecha_estado_cambio)
values
  -- Cesó DENTRO del periodo que se mira: es de la que hay que avisar.
  ('00000000-0000-0000-0000-000000016402', 'LiqDentro', 'Laboratorio',
   '00000000-0000-0000-0000-000000016400', 'test-hash', 'inactivo',
   '2026-08-07', 'renuncia', now()),
  -- Cesó en el periodo ANTERIOR: su mes ya se cerró, avisar sería ruido.
  ('00000000-0000-0000-0000-000000016403', 'LiqAntes', 'Laboratorio',
   '00000000-0000-0000-0000-000000016400', 'test-hash', 'inactivo',
   '2026-07-17', 'renuncia', now()),
  -- Sigue activa: no tiene liquidación ninguna.
  ('00000000-0000-0000-0000-000000016404', 'LiqActiva', 'Laboratorio',
   '00000000-0000-0000-0000-000000016400', 'test-hash', 'activo',
   null, null, null);

-- Alguien que NO es admin ni líder, para la prueba del permiso.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-000000016405', 'LiqCurioso', 'Laboratorio',
        '00000000-0000-0000-0000-000000016400', 'integrante', 'test-hash',
        '00000000-0000-0000-0000-00000001640a');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000016409', true);

-- Dos periodos, porque media prueba consiste en que el de antes NO aparezca.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000164aa', '2026-06-28', '2026-07-28', 'pagado'),
  ('00000000-0000-0000-0000-0000000164bb', '2026-07-29', '2026-08-28', 'abierto');

-- Las liquidaciones congeladas. La de LiqDentro lleva DOS versiones: la segunda
-- es la que manda, y eso también se comprueba.
insert into liquidacion_pagada (persona_id, version, persona, fecha_ingreso, fecha_cese,
                                monto_periodo, monto_vacaciones, monto_grati, monto_cts,
                                total, detalle, congelada_por, congelada_at) values
  ('00000000-0000-0000-0000-000000016402', 1, 'LiqDentro Laboratorio', '2026-07-01',
   '2026-08-07', 999.99, 0, 0, 0, 999.99, '{}'::jsonb,
   '00000000-0000-0000-0000-000000016401', '2026-08-08 10:00-05'),
  ('00000000-0000-0000-0000-000000016402', 2, 'LiqDentro Laboratorio', '2026-07-01',
   '2026-08-07', 1106.82, 0, 0, 0, 1106.82, '{}'::jsonb,
   '00000000-0000-0000-0000-000000016401', '2026-08-09 15:30-05'),
  ('00000000-0000-0000-0000-000000016403', 1, 'LiqAntes Laboratorio', '2026-06-01',
   '2026-07-17', 315.92, 0, 0, 0, 315.92, '{}'::jsonb,
   '00000000-0000-0000-0000-000000016401', '2026-07-19 09:00-05');

-- ── 1 · Dice lo que hay que decir ───────────────────────────────────────────

select ok(
  fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164bb')
    ? '00000000-0000-0000-0000-000000016402',
  'AVISA · quien cesó dentro del periodo aparece');

select is(
  (fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164bb')
     -> '00000000-0000-0000-0000-000000016402' ->> 'cobro_del_periodo')::numeric,
  1106.82::numeric,
  'AVISA · trae lo que esa liquidación ya pagó POR ESTE MES, que es la cifra que se solapa');

select is(
  (fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164bb')
     -> '00000000-0000-0000-0000-000000016402' ->> 'pagada_el'),
  '2026-08-09',
  'AVISA · trae la fecha en que se congeló, en hora de Lima');

select is(
  (fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164bb')
     -> '00000000-0000-0000-0000-000000016402' ->> 'fecha_cese'),
  '2026-08-07',
  'AVISA · trae la fecha de cese, para que el cartel pueda explicarse');

-- La versión 1 decía 999.99 y la 2 dice 1106.82. Si alguien cambia el
-- `distinct on` o el `order by`, esto se pone rojo: mostrar una cifra vieja
-- junto a un botón que mueve plata es peor que no mostrar nada.
select is(
  (fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164bb')
     -> '00000000-0000-0000-0000-000000016402' ->> 'total_liquidacion')::numeric,
  1106.82::numeric,
  'AVISA · con varias versiones manda la última, no la primera');

-- ── 2 · Y calla lo que no ───────────────────────────────────────────────────

select ok(
  not (fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164bb')
         ? '00000000-0000-0000-0000-000000016403'),
  'CALLA · quien cesó en el periodo ANTERIOR no aparece: su mes ya se cerró aparte');

select ok(
  not (fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164bb')
         ? '00000000-0000-0000-0000-000000016404'),
  'CALLA · quien sigue activa no aparece');

-- El periodo de junio sí tiene que ver a LiqAntes: la función no es «el periodo
-- en curso», es «el periodo que me preguntes».
select ok(
  fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164aa')
    ? '00000000-0000-0000-0000-000000016403',
  'AVISA · preguntando por el periodo de junio, sí aparece quien cesó en junio');

select ok(
  not (fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164aa')
         ? '00000000-0000-0000-0000-000000016402'),
  'CALLA · y en junio no aparece quien cesó en agosto');

-- ── 3 · El permiso ──────────────────────────────────────────────────────────
-- Devuelve cuánto cobró cada persona al irse. No es dato de cualquiera.

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000001640a', true);

select is(
  fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164bb'),
  '{}'::jsonb,
  'PERMISO · a quien no es admin ni líder le devuelve vacío, no los montos');

-- Y que el vacío sea `{}` y no null, porque la pantalla lo indexa por clave: un
-- null la haría reventar en vez de no pintar nada.
select isnt(
  fn_liquidaciones_del_periodo('00000000-0000-0000-0000-0000000164bb'),
  null,
  'PERMISO · devuelve {} y no null — la pantalla lo indexa por clave');

select * from finish();
rollback;
