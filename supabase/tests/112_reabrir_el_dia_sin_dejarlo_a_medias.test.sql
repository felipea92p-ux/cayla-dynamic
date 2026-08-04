-- ============================================================================
-- 112_reabrir_el_dia_sin_dejarlo_a_medias.test.sql
-- ============================================================================
-- Lo que defiende esta prueba, y por qué existe:
--
--   Una colaboradora marca su salida final a las 18:00 y a los diez minutos se
--   da cuenta de que le falta cerrar algo. Vuelve, y en la terminal pide reabrir
--   su día. Eso son cuatro escrituras: anular la salida final, emitir la salida
--   temporal en su mismo instante, emitir el retorno, y dejar el rastro en
--   auditoría.
--
--   La versión que hoy corre —`apps/web/app/api/reabrir-dia/route.ts`— hace las
--   primeras dos sueltas, sin transacción. Si la segunda falla, la salida final
--   YA se convirtió en salida temporal y no hay retorno: la persona figura
--   adentro indefinidamente y sus horas dejan de cerrar. Nadie se entera hasta
--   que alguien mira la planilla.
--
--   La 0137 lo baja a una función, donde el estado intermedio no existe. Las
--   dos mitades que este archivo vigila:
--
--     · cuando la operación se rechaza, NO queda nada escrito;
--     · cuando pasa, la marca original sigue legible tal como la persona la
--       hizo — anulada, nunca borrada (0081).
--
--   Y de paso los tres guardias que la ruta no tenía: solo desde una terminal
--   activa, solo la sede donde se marcó, y nunca dentro de un periodo pagado.
--
-- OJO SI ESTO FALLA POR LA FECHA: la función opera sobre `fn_hoy_lima()` a
-- propósito (reabrir es una acción del día en curso, no un arreglo retroactivo),
-- así que la semilla se construye desde `fn_hoy_lima()` y no desde fechas fijas.
-- Una fecha literal haría que la prueba pasara hoy y fallara mañana.
-- ============================================================================
begin;
select plan(15);

-- ── Semilla: dos sedes, dos terminales, tres personas ───────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-00000000ae00', 'ZZREA', 'Sede de laboratorio A', true),
  ('00000000-0000-0000-0000-00000000ae10', 'ZZREB', 'Sede de laboratorio B', true);

-- session_replication_role = replica para saltar la FK contra auth.users: las
-- terminales de laboratorio no tienen usuario real detrás.
set session_replication_role = replica;
insert into terminales (id, sede_id, nombre_dispositivo, auth_user_id, activo) values
  ('00000000-0000-0000-0000-00000000ae0e', '00000000-0000-0000-0000-00000000ae00',
   'Mac mini de la sede A', '00000000-0000-0000-0000-00000000ae09', true),
  ('00000000-0000-0000-0000-00000000ae1e', '00000000-0000-0000-0000-00000000ae10',
   'Mac mini de la sede B', '00000000-0000-0000-0000-00000000ae19', true);
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-00000000ae02', 'ReaFeliz',  'Laboratorio', '00000000-0000-0000-0000-00000000ae00', 'test-hash'),
  ('00000000-0000-0000-0000-00000000ae03', 'ReaOtraSede','Laboratorio', '00000000-0000-0000-0000-00000000ae00', 'test-hash'),
  ('00000000-0000-0000-0000-00000000ae04', 'ReaPagada', 'Laboratorio', '00000000-0000-0000-0000-00000000ae00', 'test-hash');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select p, '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6], 48,
       '{"0":{"e":"09:00","s":"18:00","r":60},"1":{"e":"09:00","s":"18:00","r":60},
         "2":{"e":"09:00","s":"18:00","r":60},"3":{"e":"09:00","s":"18:00","r":60},
         "4":{"e":"09:00","s":"18:00","r":60},"5":{"e":"09:00","s":"18:00","r":60},
         "6":{"e":"09:00","s":"18:00","r":60}}'::jsonb
from unnest(array['00000000-0000-0000-0000-00000000ae02'::uuid,
                  '00000000-0000-0000-0000-00000000ae03'::uuid,
                  '00000000-0000-0000-0000-00000000ae04'::uuid]) p;

-- Las tres entraron a las 09:00 de HOY y cerraron a las 18:00, en la sede A.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen)
select gen_random_uuid(), p, '00000000-0000-0000-0000-00000000ae00', t,
       (fn_hoy_lima()::text || h)::timestamptz, 'terminal'
from unnest(array['00000000-0000-0000-0000-00000000ae02'::uuid,
                  '00000000-0000-0000-0000-00000000ae03'::uuid,
                  '00000000-0000-0000-0000-00000000ae04'::uuid]) p,
     unnest(array['entrada'::tipo_marca, 'salida_final'::tipo_marca],
            array['T09:00:00-05:00',     'T18:00:00-05:00']) as m(t, h);


-- ── CATÁLOGO · la función está, y con los permisos que necesita ─────────────
-- Si alguien la borra o le cambia la firma, la terminal falla en la sede y no
-- acá; por eso el catálogo se comprueba antes que el comportamiento.

select is(
  (select count(*)::int from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_reabrir_dia'
     and pg_get_function_identity_arguments(p.oid) = 'p_persona_id uuid, p_motivo text'),
  1,
  'CATÁLOGO · fn_reabrir_dia(uuid, text) existe con esa firma exacta');

select ok(
  (select prosecdef from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_reabrir_dia'),
  'CATÁLOGO · es SECURITY DEFINER: la terminal no necesita permisos sobre marcajes');

-- La 0076 quitó el EXECUTE que PUBLIC tenía por defecto. Sin el grant explícito
-- la función existe y la terminal igual no puede llamarla.
select ok(
  has_function_privilege('authenticated', 'fn_reabrir_dia(uuid, text)', 'EXECUTE'),
  'CATÁLOGO · authenticated tiene EXECUTE: el grant de la 0076 no la dejó fuera');


-- ── 1 · Solo desde una terminal activa ──────────────────────────────────────
-- La terminal NO se recibe por parámetro: se deriva de la sesión. Un id que
-- viaja en el cuerpo de la petición lo elige quien llama.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000aeff', true);

select throws_ok(
  $$ select fn_reabrir_dia('00000000-0000-0000-0000-00000000ae02', 'me falto cerrar caja') $$,
  null, null,
  'SIN TERMINAL · una sesión que no es de una terminal activa no reabre nada');


-- ── 2 · El motivo es obligatorio ────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ae09', true);

select throws_ok(
  $$ select fn_reabrir_dia('00000000-0000-0000-0000-00000000ae02', '  x ') $$,
  null, null,
  'MOTIVO · un motivo en blanco o de menos de 3 letras se rechaza');


-- ── 3 · Cada sede reabre lo suyo ────────────────────────────────────────────
-- Se compara contra la sede DEL MARCAJE, no contra la sede base de la persona:
-- quien viaja entre sedes marcó donde estaba, y ahí se corrige.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ae19', true);

select throws_ok(
  $$ select fn_reabrir_dia('00000000-0000-0000-0000-00000000ae03', 'vine a devolver la llave') $$,
  null, null,
  'OTRA SEDE · la terminal de la sede B no reabre una marca hecha en la sede A');


-- ── 4 · El camino que sí funciona ───────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ae09', true);

select is(
  (select fn_reabrir_dia('00000000-0000-0000-0000-00000000ae02',
                         'volvi a cerrar la caja')->>'ok'),
  'true',
  'FELIZ · la terminal de la sede A sí reabre el día de su gente');

-- Append-only (0081): la marca que la persona hizo de verdad sigue ahí. La ruta
-- vieja hacía `update marcajes set tipo = ...` encima de ella, que es justo lo
-- que la 0081 prohibió.
select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000ae02'
      and tipo = 'salida_final' and anulada_at is not null),
  1,
  'FELIZ · la salida final quedó ANULADA, no borrada ni reescrita');

select ok(
  (select anulada_motivo like '%volvi a cerrar la caja%' from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000ae02' and tipo = 'salida_final'),
  'FELIZ · y dice por qué se anuló, con el motivo que escribió la persona');

-- El instante importa: la salida temporal se emite cuando la persona SE FUE, no
-- cuando el sistema se enteró. Emitirla en now() le regala los minutos que tardó
-- en volver a la terminal.
select is(
  (select timestamp_marca from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000ae02'
      and tipo = 'salida_otro' and anulada_at is null),
  (fn_hoy_lima()::text || 'T18:00:00-05:00')::timestamptz,
  'FELIZ · la salida temporal queda en el MISMO instante que la salida final original');

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000ae02'
      and tipo = 'retorno_otro' and anulada_at is null),
  1,
  'FELIZ · y el retorno queda registrado: el día vuelve a estar abierto');

-- Toda edición manual deja rastro con motivo obligatorio. La ruta vieja mutaba
-- el marcaje sin escribir una sola línea de auditoría.
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-00000000ae02'
      and campo_modificado = 'dia_reabierto_desde_terminal'
      and motivo = 'volvi a cerrar la caja'),
  1,
  'FELIZ · quedó el rastro en correcciones_auditoria, con el motivo textual');


-- ── 5 · El candado de periodo pagado, y el todo-o-nada ──────────────────────
-- Va al final porque el candado mira la fecha, no la persona: en cuanto existe
-- un periodo pagado sobre hoy, nadie reabre.
-- El periodo abarca hoy con holgura: `periodos_planilla_check` exige entre 20 y
-- 46 días, así que uno de un solo día no entra.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000000aeaa',
        fn_hoy_lima() - 10, fn_hoy_lima() + 15, 'pagado');

select throws_ok(
  $$ select fn_reabrir_dia('00000000-0000-0000-0000-00000000ae04', 'quiero volver a entrar') $$,
  null, null,
  'PAGADO · reabrir un día que cae en un periodo ya pagado se rechaza');

-- Estas dos son el corazón del archivo. Con la ruta vieja, un fallo después de
-- la primera escritura dejaba a la persona con su salida final convertida en
-- salida temporal y sin retorno: adentro para siempre.
select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000ae04'
      and tipo = 'salida_final' and anulada_at is null),
  1,
  'TODO-O-NADA · tras el rechazo la salida final sigue viva y sin anular');

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000ae04'
      and tipo in ('salida_otro', 'retorno_otro')),
  0,
  'TODO-O-NADA · y no quedó ni una marca a medias de la operación que falló');

select * from finish();
rollback;
