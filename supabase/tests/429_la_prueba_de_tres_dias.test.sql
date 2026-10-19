-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 429_la_prueba_de_tres_dias.test.sql — 0535 y 0536
-- ============================================================================
-- Lo que fija esta prueba, en orden de importancia:
--   · Quién puede cerrar la prueba de quién: DO y administración sobre cualquiera;
--     la líder de equipo SOLO sobre la gente de su sede; el integrante, nadie;
--     y nadie sobre su propia prueba.
--   · Cerrar es todo o nada: si la baja rebota, el resultado no queda escrito.
--   · «Se retiró» y «no apto» dan de baja con motivos de cese distintos
--     (`renuncia` / `fin_periodo_prueba`) y con el último día trabajado como fecha.
--   · Los días se cuentan de jornadas CERRADAS, no de las abiertas.
--   · El navegador no puede escribir `pruebas`, y el núcleo del cese no es suyo.
--   · La puerta general del cese (`fn_cesar_persona`) sigue siendo solo de admin y
--     líder DO — la 0535 la partió en dos sin aflojarla.
-- ============================================================================
begin;
select plan(52);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000429a01', 'ZZPR1', 'Sede de laboratorio 1', true),
  ('00000000-0000-0000-0000-000000429a02', 'ZZPR2', 'Sede de laboratorio 2', true);

-- Con cuenta (la FK a auth.users se salta con `replica`, como en la 404).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000429b01', 'Admin',        'Lab', '00000000-0000-0000-0000-000000429a01', 'admin',           'x', '00000000-0000-0000-0000-000000429c01', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000429b02', 'LiderUno',     'Lab', '00000000-0000-0000-0000-000000429a01', 'supervisor_sede', 'x', '00000000-0000-0000-0000-000000429c02', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000429b03', 'LiderDos',     'Lab', '00000000-0000-0000-0000-000000429a02', 'supervisor_sede', 'x', '00000000-0000-0000-0000-000000429c03', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000429b04', 'Integrante',   'Lab', '00000000-0000-0000-0000-000000429a01', 'integrante',      'x', '00000000-0000-0000-0000-000000429c04', '2024-01-01', 'activo', 'planilla'),
  -- Una líder que además está de prueba (para comprobar que no decide sobre sí misma)
  -- y sin fila en `pruebas`, porque con `replica` el trigger no corre.
  ('00000000-0000-0000-0000-000000429b05', 'LiderPrueba',  'Lab', '00000000-0000-0000-0000-000000429a01', 'supervisor_sede', 'x', '00000000-0000-0000-0000-000000429c05', '2026-10-01', 'activo', 'prueba');
set session_replication_role = origin;

-- Las personas de prueba, SIN cuenta y con el trigger vivo.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000429d01', 'PruebaUno',   'Lab', '00000000-0000-0000-0000-000000429a01', 'integrante', 'x', '2026-10-01', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000429d02', 'PruebaDos',   'Lab', '00000000-0000-0000-0000-000000429a01', 'integrante', 'x', '2026-10-01', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000429d03', 'PruebaTres',  'Lab', '00000000-0000-0000-0000-000000429a01', 'integrante', 'x', '2026-10-01', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000429d04', 'PruebaOtra',  'Lab', '00000000-0000-0000-0000-000000429a02', 'integrante', 'x', '2026-10-01', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000429d05', 'PruebaPasa',  'Lab', '00000000-0000-0000-0000-000000429a01', 'integrante', 'x', '2026-10-01', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000429d06', 'PruebaCesada','Lab', '00000000-0000-0000-0000-000000429a01', 'integrante', 'x', '2026-10-01', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000429d07', 'PruebaSinFila','Lab','00000000-0000-0000-0000-000000429a01', 'integrante', 'x', '2026-10-01', 'activo', 'prueba');

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true);
$$;
create function pg_temp.jornada(p_persona uuid, p_fecha date, p_estado estado_jornada) returns void language sql as $$
  insert into jornadas (persona_id, fecha, sede_id, entrada_ts, salida_final_ts, horas_trabajadas, estado)
  values (p_persona, p_fecha, '00000000-0000-0000-0000-000000429a01',
          (p_fecha || ' 09:00-05')::timestamptz,
          case when p_estado in ('abierta', 'en_pausa') then null else (p_fecha || ' 15:00-05')::timestamptz end,
          case when p_estado in ('abierta', 'en_pausa') then null else 6 end,
          p_estado);
$$;

-- ── 1 · El trigger abre una prueba al crear a la persona ────────────────────
select is(
  (select count(*)::int from pruebas where persona_id = '00000000-0000-0000-0000-000000429d01' and resultado = 'en_curso'),
  1, 'ABRIR · una persona creada en vínculo «prueba» tiene su prueba abierta');
select is(
  (select inicio from pruebas where persona_id = '00000000-0000-0000-0000-000000429d01'),
  '2026-10-01'::date, 'ABRIR · la prueba arranca el día de su ingreso');
select is(
  (select count(*)::int from pruebas where persona_id = '00000000-0000-0000-0000-000000429b02'),
  0, 'ABRIR · quien no está de prueba no tiene fila');

-- ── 2 · El esquema hace imposibles los estados que nunca deben existir ──────
select throws_ok(
  $$ insert into pruebas (persona_id, inicio) values ('00000000-0000-0000-0000-000000429d01', '2026-10-02') $$,
  '23505', null, 'IMPOSIBLE · dos pruebas abiertas de la misma persona');
select throws_ok(
  $$ insert into pruebas (persona_id, inicio, resultado) values ('00000000-0000-0000-0000-000000429b01', '2026-10-02', 'no_apto') $$,
  '23514', null, 'IMPOSIBLE · una prueba cerrada como «no apto» sin quién, cuándo ni motivo');
select throws_ok(
  $$ insert into pruebas (persona_id, inicio, resultado, motivo, cerrada_por, cerrada_at, cerrada_fecha)
     values ('00000000-0000-0000-0000-000000429b01', '2026-10-02', 'retirado', 'ab',
             '00000000-0000-0000-0000-000000429b02', now(), '2026-10-02') $$,
  '23514', null, 'IMPOSIBLE · «se retiró» con un motivo de dos letras');

-- ── 3 · El navegador solo lee ───────────────────────────────────────────────
select ok(has_table_privilege('authenticated', 'pruebas', 'select'),
  'SEGURIDAD · quien inicia sesión puede leer pruebas (por fila)');
select ok(
  not has_table_privilege('authenticated', 'pruebas', 'insert')
  and not has_table_privilege('authenticated', 'pruebas', 'update')
  and not has_table_privilege('authenticated', 'pruebas', 'delete'),
  'SEGURIDAD · ni insertar, ni actualizar, ni borrar: el resultado solo se escribe por fn_prueba_cerrar');
select ok(not has_table_privilege('anon', 'pruebas', 'select'),
  'SEGURIDAD · sin sesión no se lee nada');
select ok(not has_function_privilege('authenticated', 'fn_cese_aplicar(uuid, date, text, text, uuid)', 'execute'),
  'SEGURIDAD · el núcleo del cese no es llamable desde el navegador');
select ok(not has_function_privilege('authenticated', 'fn_prueba_dias_trabajados(uuid, date, date)', 'execute'),
  'SEGURIDAD · contar los días de cualquiera tampoco');

-- ── 4 · Los días se cuentan de jornadas cerradas ────────────────────────────
select pg_temp.jornada('00000000-0000-0000-0000-000000429d01', '2026-10-02', 'cerrada');
select pg_temp.jornada('00000000-0000-0000-0000-000000429d01', '2026-10-03', 'auto_cerrada_pendiente');
select pg_temp.jornada('00000000-0000-0000-0000-000000429d01', '2026-10-05', 'abierta');

select pg_temp.como('00000000-0000-0000-0000-000000429c01');   -- la admin
select is(
  (select dias_trabajados from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000429d01'),
  2, 'DÍAS · cuentan la cerrada y la auto-cerrada; la que sigue abierta no');
select is(
  (select situacion from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000429d01'),
  'en_curso', 'DÍAS · con dos días: en curso');
select is(
  (select dias_plazo from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000429d01'),
  3, 'DÍAS · el plazo sale de una sola función (tres)');

select is(
  (select horas_marcadas from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000429d01'),
  12::numeric, 'DÍAS · y dice cuántas horas lleva marcadas: lo que está en juego al decidir');

select is(
  (select dni_cargado from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000429d01'),
  false, 'DNI · sin las fotos, la fila dice que falta el DNI');
insert into datos_personales (persona_id, foto_dni_anverso_ruta, foto_dni_reverso_ruta)
values ('00000000-0000-0000-0000-000000429d01', 'solicitud/x/a.jpg', 'solicitud/x/b.jpg');
select is(
  (select dni_cargado from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000429d01'),
  true, 'DNI · con las dos caras guardadas, dice que ya está');

select pg_temp.jornada('00000000-0000-0000-0000-000000429d02', '2026-10-02', 'cerrada');
select pg_temp.jornada('00000000-0000-0000-0000-000000429d02', '2026-10-03', 'cerrada');
select pg_temp.jornada('00000000-0000-0000-0000-000000429d02', '2026-10-04', 'cerrada');
select is(
  (select situacion from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000429d02'),
  'cumplida', 'DÍAS · con tres días cerrados: cumplida (toca decidir)');
select pg_temp.jornada('00000000-0000-0000-0000-000000429d02', '2026-10-05', 'revisada');
select is(
  (select situacion from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000429d02'),
  'vencida', 'DÍAS · con un cuarto día y nadie que decidió: vencida');
select is(
  (select persona_id from fn_pruebas_abiertas() where sede_codigo in ('ZZPR1', 'ZZPR2') order by situacion = 'vencida' desc limit 1),
  '00000000-0000-0000-0000-000000429d02'::uuid, 'DÍAS · la vencida sale primero');

-- ── 5 · Quién ve qué ────────────────────────────────────────────────────────
select is(
  (select count(*)::int from fn_pruebas_abiertas() where sede_codigo in ('ZZPR1', 'ZZPR2')),
  8, 'VISTA · la admin ve las de las dos sedes: las siete, la líder que está de prueba, y también la que no tiene fila');

select pg_temp.como('00000000-0000-0000-0000-000000429c02');   -- líder de la sede 1
select is(
  (select count(*)::int from fn_pruebas_abiertas() where sede_codigo = 'ZZPR2'),
  0, 'VISTA · la líder de la sede 1 no ve a nadie de la sede 2');
select ok(
  (select count(*)::int from fn_pruebas_abiertas() where sede_codigo = 'ZZPR1') >= 6,
  'VISTA · pero sí ve a toda su gente');
-- La política de la tabla, de verdad: como `authenticated` (la dueña se salta el RLS).
set local role authenticated;
select is(
  (select count(*)::int from pruebas where persona_id = '00000000-0000-0000-0000-000000429d04'),
  0, 'VISTA · la tabla no le muestra a la líder de la sede 1 la fila de la sede 2 (RLS)');
select is(
  (select count(*)::int from pruebas where persona_id = '00000000-0000-0000-0000-000000429d03'),
  1, 'VISTA · pero sí la de su sede');
reset role;
select ok(fn_prueba_puede_actuar('00000000-0000-0000-0000-000000429d01') is true,
  'PERMISO · la líder actúa sobre alguien de su sede');
select ok(fn_prueba_puede_actuar('00000000-0000-0000-0000-000000429d04') is not true,
  'PERMISO · y no sobre alguien de otra sede');

select pg_temp.como('00000000-0000-0000-0000-000000429c04');   -- un integrante
select ok(fn_prueba_puede_actuar('00000000-0000-0000-0000-000000429d01') is not true,
  'PERMISO · un integrante no actúa sobre nadie');
select is(
  (select count(*)::int from fn_pruebas_abiertas() where sede_codigo in ('ZZPR1', 'ZZPR2')),
  0, 'VISTA · y no ve ninguna prueba');

-- ── 6 · Lo que NO se puede cerrar ───────────────────────────────────────────
select throws_like(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d01', 'no_apto', 'No llegó a la altura del puesto') $$,
  '%No puedes decidir%', 'CERRAR · un integrante no puede');

select pg_temp.como('00000000-0000-0000-0000-000000429c02');   -- líder de la sede 1
select throws_like(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d04', 'no_apto', 'No llegó a la altura del puesto') $$,
  '%No puedes decidir%', 'CERRAR · la líder de otra sede no puede');
select pg_temp.como('00000000-0000-0000-0000-000000429c05');   -- la líder que está de prueba
select throws_like(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429b05', 'retirado', 'Dijo que se iba') $$,
  '%propia prueba%', 'CERRAR · nadie decide sobre su propia prueba');
select pg_temp.como('00000000-0000-0000-0000-000000429c02');   -- de vuelta a la líder de la sede 1
select throws_like(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d01', 'contratada', 'Pasó la prueba') $$,
  '%no apto%se retiró%', 'CERRAR · por esta puerta solo se cierra como «no apto» o «se retiró»');
select throws_like(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d01', 'no_apto', 'ab') $$,
  '%motivo%', 'CERRAR · sin motivo no se cierra');
select throws_like(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429b04', 'no_apto', 'No está de prueba') $$,
  '%no está de prueba%', 'CERRAR · quien no está de prueba no se cierra por aquí');

-- ── 7 · Cerrar como «no apto»: la líder, sobre su sede ──────────────────────
-- Su último día trabajado con jornada es el 05/10 (la abierta); es la fecha de baja.
select lives_ok(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d01', 'no_apto', 'No llegó a la altura del puesto') $$,
  'NO APTO · la líder de su sede puede cerrarla, sola');
select is(
  (select estado::text || '/' || motivo_cese || '/' || fecha_cese::text from personas where id = '00000000-0000-0000-0000-000000429d01'),
  'inactivo/fin_periodo_prueba/2026-10-05', 'NO APTO · queda dada de baja como fin de periodo de prueba, el último día trabajado');
select is(
  (select resultado || '/' || cerrada_por::text from pruebas where persona_id = '00000000-0000-0000-0000-000000429d01'),
  'no_apto/00000000-0000-0000-0000-000000429b02', 'NO APTO · el resultado queda con quién lo decidió (y el trigger no lo pisa con «cesada»)');
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000429d01' and campo_modificado = 'pruebas.resultado'
      and corregido_por = '00000000-0000-0000-0000-000000429b02' and motivo like '%NO APTO%'),
  1, 'NO APTO · deja su rastro, con el motivo y quién');
select throws_like(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d01', 'retirado', 'Ya estaba cerrada') $$,
  '%ya está inactiva%', 'NO APTO · cerrar dos veces no se puede');

-- ── 8 · Cerrar como «se retiró»: administración, y la fecha no puede ser anterior ──
select pg_temp.como('00000000-0000-0000-0000-000000429c01');   -- la admin
select throws_like(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d02', 'retirado', 'Dijo que no volvía', '2026-10-03') $$,
  '%último día trabajado fue el 05/10/2026%', 'SE RETIRÓ · la baja no puede ser anterior a su último día trabajado');
select lives_ok(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d02', 'retirado', 'Dijo que no volvía') $$,
  'SE RETIRÓ · la administración puede cerrarla');
select is(
  (select motivo_cese || '/' || fecha_cese::text from personas where id = '00000000-0000-0000-0000-000000429d02'),
  'renuncia/2026-10-05', 'SE RETIRÓ · queda como renuncia, no como fin de periodo de prueba');

-- ── 9 · Todo o nada ─────────────────────────────────────────────────────────
-- Una fecha futura hace rebotar el cese; el resultado no puede quedar escrito.
select throws_like(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d03', 'no_apto', 'Prueba de la atomicidad', (fn_hoy_lima() + 10)) $$,
  '%no puede ser futuro%', 'TODO O NADA · si la baja rebota, la función rebota');
select is(
  (select resultado from pruebas where persona_id = '00000000-0000-0000-0000-000000429d03'),
  'en_curso', 'TODO O NADA · y la prueba sigue abierta: ni el resultado ni la baja quedaron a medias');

-- ── 10 · La fila que el trigger no pudo abrir ───────────────────────────────
delete from pruebas where persona_id = '00000000-0000-0000-0000-000000429d07';
select is(
  (select registrada from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000429d07'),
  false, 'SIN FILA · quien está de prueba pero no tiene fila igual aparece, marcada como no registrada');
select lives_ok(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000429d07', 'no_apto', 'Se cerró sin fila previa') $$,
  'SIN FILA · y se puede cerrar: la fila se crea al vuelo');

-- ── 11 · El trigger cierra la prueba cuando el vínculo o el estado cambian ──
select lives_ok(
  $$ select fn_set_tipo_vinculo('00000000-0000-0000-0000-000000429d05', 'planilla') $$,
  'CONTRATADA · se le cambia el vínculo a planilla');
select is(
  (select resultado from pruebas where persona_id = '00000000-0000-0000-0000-000000429d05'),
  'contratada', 'CONTRATADA · la prueba queda cerrada como contratada');
select lives_ok(
  $$ select fn_cesar_persona('00000000-0000-0000-0000-000000429d06', '2026-10-02', 'renuncia') $$,
  'CESADA · la puerta general sigue funcionando para la administración');
select is(
  (select resultado from pruebas where persona_id = '00000000-0000-0000-0000-000000429d06'),
  'cesada', 'CESADA · y la prueba no queda abierta de alguien que ya se fue');

-- ── 12 · La puerta general del cese sigue siendo solo de admin y líder DO ───
select pg_temp.como('00000000-0000-0000-0000-000000429c02');   -- la líder de equipo
select throws_like(
  $$ select fn_cesar_persona('00000000-0000-0000-0000-000000429b04', '2026-10-02', 'renuncia') $$,
  '%Solo un administrador o líder%', '0535 · la líder de equipo sigue sin poder cesar por la puerta general');

select * from finish();
rollback;
