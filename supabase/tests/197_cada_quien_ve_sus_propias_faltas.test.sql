-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 197_cada_quien_ve_sus_propias_faltas.test.sql — la rama nueva de la 0256
-- ============================================================================
-- La 0256 le añade a `fn_faltas` una tercera rama de visibilidad:
-- `pe.id = fn_persona_actual_id()`. Una integrante entra a «Lo mío» y ve si el
-- sistema le contó una falta, en vez de enterarse cuando ya hay una
-- conversación encima — que es justo cuando el marcaje ya no se puede arreglar.
--
-- LO QUE HAY QUE PROBAR NO ES QUE VEA LAS SUYAS. Eso es lo fácil. Lo que hay
-- que probar es que NO vea las de nadie más: la rama se escribió dentro de una
-- cláusula con dos OR y un `security definer`, o sea el sitio exacto donde un
-- paréntesis de menos convierte «cada quien se ve a sí misma» en «todo el mundo
-- se ve todo». Y que las dos ramas viejas —admin y encargada— sigan intactas,
-- porque esta migración reescribe la función entera.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000c9701', 'ZZM01', 'Sede propia', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000c9702', 'ZZM02', 'Sede ajena', true, 'tienda');

-- Admin y encargada llevan `auth_user_id`, así que entran por replica: la RLS de
-- `personas` no deja crear a alguien con cuenta desde una sesión sin permisos.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000ca001', 'MiaAdmin', 'Lab',
   '00000000-0000-0000-0000-0000000c9701', 'admin', 'x',
   '00000000-0000-0000-0000-0000000cb001', '2024-01-01'),
  ('00000000-0000-0000-0000-0000000ca002', 'MiaEncargada', 'Lab',
   '00000000-0000-0000-0000-0000000c9701', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000cb002', '2024-01-01'),
  -- Las dos integrantes que importan: una en la sede de la encargada y otra en
  -- la de al lado. Las dos con cuenta, porque las dos van a preguntar.
  ('00000000-0000-0000-0000-0000000ca003', 'MiaPropia', 'Lab',
   '00000000-0000-0000-0000-0000000c9701', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000cb003', '2024-01-01'),
  ('00000000-0000-0000-0000-0000000ca004', 'MiaAjena', 'Lab',
   '00000000-0000-0000-0000-0000000c9702', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000cb004', '2024-01-01');
set session_replication_role = origin;

-- Las dos con el mismo horario, para que el mismo lunes les toque a las dos y
-- ninguna marque: dos faltas idénticas y simultáneas, que es la situación en la
-- que un fallo de visibilidad se ve.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select p, '2024-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6], 48,
       '{"1":{"e":"09:00","s":"18:00","r":60}}'::jsonb
from unnest(array['00000000-0000-0000-0000-0000000ca003'::uuid,
                  '00000000-0000-0000-0000-0000000ca004'::uuid]) p;

-- ── Ella, mirándose a sí misma ──────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000cb003', true);

select is(
  (select count(*)::int from fn_faltas('2026-07-06', '2026-07-06')
   where persona_id = '00000000-0000-0000-0000-0000000ca003'),
  1,
  'una integrante ve SU falta del lunes 6 de julio'
);

select is(
  (select count(*)::int from fn_faltas('2026-07-06', '2026-07-06')
   where persona_id <> '00000000-0000-0000-0000-0000000ca003'),
  0,
  'y NO ve la de nadie más, ni la de su propia sede'
);

-- El día que sí marcó no le sale como falta: la rama nueva amplía QUIÉN
-- pregunta, no QUÉ se considera una falta.
insert into jornadas (persona_id, fecha, entrada_ts, estado)
values ('00000000-0000-0000-0000-0000000ca003', '2026-07-07',
        '2026-07-07T09:00:00-05:00', 'cerrada');

select is(
  (select count(*)::int from fn_faltas('2026-07-07', '2026-07-07')
   where persona_id = '00000000-0000-0000-0000-0000000ca003'),
  0,
  'el día que sí marcó no le aparece como falta'
);

-- ── La de la otra sede, mirándose a sí misma ────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000cb004', true);

select is(
  (select count(*)::int from fn_faltas('2026-07-06', '2026-07-06')),
  1,
  'la integrante de la otra sede ve exactamente una falta: la suya'
);

-- ── Que las dos ramas viejas sigan enteras ─────────────────────────────────
-- Esta migración reescribe la función completa, así que hay que comprobar que
-- no se llevó por delante lo que ya funcionaba.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000cb002', true);

select is(
  (select count(*)::int from fn_faltas('2026-07-06', '2026-07-06')),
  1,
  'la encargada sigue viendo su sede — y solo su sede'
);

select is(
  (select persona_id from fn_faltas('2026-07-06', '2026-07-06')),
  '00000000-0000-0000-0000-0000000ca003'::uuid,
  'y la que ve es la de SU sede, no la de al lado'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000cb001', true);

select is(
  (select count(*)::int from fn_faltas('2026-07-06', '2026-07-06')),
  2,
  'admin sigue viendo las dos, de las dos sedes'
);

select * from finish();
rollback;
