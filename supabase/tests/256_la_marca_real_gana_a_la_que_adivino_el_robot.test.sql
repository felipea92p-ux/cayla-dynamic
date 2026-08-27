-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 256_la_marca_real_gana_a_la_que_adivino_el_robot.test.sql
-- ============================================================================
-- LO QUE CUIDA (0320): que quien cierra tienda pasada la medianoche pueda
-- marcar su salida REAL aunque el auto-cierre haya llegado antes.
--
-- Es la promesa nº 1 de la 0240, que hasta hoy solo se cumplía durante 3 horas:
-- `fn_auto_cierre` corre cada 15 minutos y cierra la jornada pasadas
-- `auto_cierre_horas` desde la hora PROGRAMADA. A partir de ahí, la rama de la
-- 0240 no encontraba jornada abierta y la salida real se rechazaba con el mismo
-- error que esa migración cita como lo que resuelve.
--
-- Medido: trabajó 11,50 h y le quedaban 8,00 h puestas por el robot.
--
-- ── LA COMPROBACIÓN 6 ES LA QUE IMPIDE QUE ESTO SE PASE DE LA RAYA ─────────
--
-- El arreglo ANULA una marca, y eso en un sistema append-only hay que acotarlo.
-- Si alguien de DO ya confirmó el auto-cierre —`estado_revision = 'revisada'`—
-- esa es una decisión humana y manda sobre el automatismo. La comprobación 6
-- fija ese límite: un arreglo que anulara «cualquier salida_final del robot»
-- pasaría las cinco primeras y pisaría el criterio de una persona.
--
-- ── POR QUÉ LAS FECHAS SON RELATIVAS A HOY ─────────────────────────────────
--
-- `fn_auto_cierre` compara contra `now()`. Con fechas fijas no dispararía, y la
-- prueba mediría el caso que no es.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-0000000ba0b0', 'ZZROB', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000ba0ad', 'RobAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000ba0b0', 'admin', 'x',
        '00000000-0000-0000-0000-0000000baf0a', '2024-01-01');
insert into terminales (id, sede_id, nombre_dispositivo, auth_user_id, activo)
values ('00000000-0000-0000-0000-0000000ba0e1', '00000000-0000-0000-0000-0000000ba0b0',
        'Mac mini de laboratorio', '00000000-0000-0000-0000-0000000baf7e', true);
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000ba001', 'RobAna', 'Lab', '00000000-0000-0000-0000-0000000ba0b0', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ba002', 'RobBea', 'Lab', '00000000-0000-0000-0000-0000000ba0b0', 'x', '2024-01-01', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950, '2024-01-01' from personas where apellidos = 'Lab' and nombres like 'Rob%' and nombres <> 'RobAdmin';
-- Horario de tienda 13:00–21:00: el auto-cierre dispara a las 21:00 + 3 h.
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '13:00', '21:00', array[0,1,2,3,4,5,6]
from personas where apellidos = 'Lab' and nombres like 'Rob%' and nombres <> 'RobAdmin';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000baf7e', true);

-- Las dos entran ayer a las 13:00 y NO marcan su salida antes de que pase el cron.
select fn_registrar_marcaje(p.id, 'entrada',
       ((fn_hoy_lima() - 1)::timestamp + time '13:00') at time zone 'America/Lima',
       gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000ba0e1',
       '00000000-0000-0000-0000-0000000ba0b0', null)
from personas p where p.apellidos = 'Lab' and p.nombres like 'Rob%' and p.nombres <> 'RobAdmin';

select fn_auto_cierre();

-- ── 1 · El robot hizo lo suyo: cerró con la hora PROGRAMADA ────────────────
select is(
  (select horas_trabajadas from jornadas
    where persona_id = '00000000-0000-0000-0000-0000000ba001' and fecha = fn_hoy_lima() - 1),
  8.00::numeric,
  'el auto-cierre dejó 8,00 h: las programadas, no las trabajadas'
);

-- A BEA se le confirma el auto-cierre. Es una decisión humana, y tiene que mandar.
update marcajes set estado_revision = 'revisada'
where persona_id = '00000000-0000-0000-0000-0000000ba002' and origen = 'auto_cierre';

-- ── 2, 3, 4 y 5 · ANA marca su salida real de las 00:30 ────────────────────
select lives_ok(
  $rob$ select fn_registrar_marcaje('00000000-0000-0000-0000-0000000ba001', 'salida_final',
          ((fn_hoy_lima())::timestamp + time '00:30') at time zone 'America/Lima',
          gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000ba0e1',
          '00000000-0000-0000-0000-0000000ba0b0', null) $rob$,
  'su salida real de las 00:30 SE ACEPTA, aunque el robot llegara primero'
);

select is(
  (select horas_trabajadas from jornadas
    where persona_id = '00000000-0000-0000-0000-0000000ba001' and fecha = fn_hoy_lima() - 1),
  11.50::numeric,
  'y su jornada pasa a tener las horas que trabajo de verdad'
);

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-0000000ba001'
      and origen = 'auto_cierre' and anulada_at is not null),
  1,
  'la marca del robot queda ANULADA, no borrada: sigue siendo append-only'
);

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-0000000ba001'
      and campo_modificado = 'auto_cierre_reemplazado'),
  1,
  'y deja su rastro, como cualquier otra correccion'
);

-- ── 6 · EL LIMITE: lo que DO ya confirmo no se toca ────────────────────────
-- Un arreglo que anulara «cualquier salida_final del robot» pasaria las cinco
-- de arriba y pisaria el criterio de una persona.
select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-0000000ba002'
      and origen = 'auto_cierre' and anulada_at is not null),
  0,
  'si DO ya confirmo el auto-cierre, esa marca NO se anula: manda la persona'
);

select * from finish();
rollback;
