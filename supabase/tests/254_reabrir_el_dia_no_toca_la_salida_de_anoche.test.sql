-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 254_reabrir_el_dia_no_toca_la_salida_de_anoche.test.sql
-- ============================================================================
-- LO QUE CUIDA (0318): que `fn_reabrir_dia` no pueda anular la salida real de
-- quien cerró tienda pasada la medianoche.
--
-- Ana entra el martes a las 15:00 y cierra a las 00:30 del miércoles. La 0240 lo
-- guarda bien —`fecha_jornada` = martes, 9,50 h cerradas— y esta función la
-- anulaba igual, porque buscaba «la salida de hoy» por CALENDARIO. Medido:
-- S/109,62 → S/0,00, y el martes reabierto sin entrada.
--
-- ── LA SEGUNDA COMPROBACIÓN ES LA QUE IMPIDE EL REMEDIO PEOR ───────────────
--
-- Un arreglo perezoso —exigir `fecha_jornada = v_hoy` a secas— haría pasar la
-- primera y dejaría sin poder reabrir a TODO EL MUNDO: las marcas normales no
-- llevan esa columna, solo la lleva la que cruza medianoche. El null es el caso
-- corriente, no el raro.
--
-- ── POR QUÉ LAS FECHAS SON RELATIVAS A HOY ─────────────────────────────────
--
-- `fn_reabrir_dia` compara contra `fn_hoy_lima()`, o sea el reloj de verdad. Un
-- laboratorio con fechas fijas no mediría nada: la función no encontraría ni la
-- buena ni la mala.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000fff0000', 'ZZRAB', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000fff00ad', 'RabAdmin', 'Lab',
        '00000000-0000-0000-0000-00000fff0000', 'admin', 'x',
        '00000000-0000-0000-0000-00000ffff0ad', '2024-01-01');
insert into terminales (id, sede_id, nombre_dispositivo, auth_user_id, activo)
values ('00000000-0000-0000-0000-00000fff07e1', '00000000-0000-0000-0000-00000fff0000',
        'Mac mini de laboratorio', '00000000-0000-0000-0000-00000ffff7e1', true);
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000fff0001', 'RabAna', 'Lab', '00000000-0000-0000-0000-00000fff0000', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000fff0002', 'RabBea', 'Lab', '00000000-0000-0000-0000-00000fff0000', 'x', '2024-01-01', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950, '2024-01-01' from personas where apellidos = 'Lab' and nombres like 'Rab%' and nombres <> 'RabAdmin';
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '15:00', '23:00', array[0,1,2,3,4,5,6]
from personas where apellidos = 'Lab' and nombres like 'Rab%' and nombres <> 'RabAdmin';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000ffff7e1', true);

-- ANA cierra tienda a las 00:30: su salida lleva la fecha_jornada de AYER.
select fn_registrar_marcaje('00000000-0000-0000-0000-00000fff0001', 'entrada',
       ((fn_hoy_lima() - 1)::timestamp + time '15:00') at time zone 'America/Lima',
       gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-00000fff07e1',
       '00000000-0000-0000-0000-00000fff0000', null);
select fn_registrar_marcaje('00000000-0000-0000-0000-00000fff0001', 'salida_final',
       ((fn_hoy_lima())::timestamp + time '00:30') at time zone 'America/Lima',
       gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-00000fff07e1',
       '00000000-0000-0000-0000-00000fff0000', null);

-- BEA hace lo corriente: entra y sale el mismo día.
select fn_registrar_marcaje('00000000-0000-0000-0000-00000fff0002', 'entrada',
       ((fn_hoy_lima())::timestamp + time '15:00') at time zone 'America/Lima',
       gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-00000fff07e1',
       '00000000-0000-0000-0000-00000fff0000', null);
select fn_registrar_marcaje('00000000-0000-0000-0000-00000fff0002', 'salida_final',
       ((fn_hoy_lima())::timestamp + time '22:00') at time zone 'America/Lima',
       gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-00000fff07e1',
       '00000000-0000-0000-0000-00000fff0000', null);

-- ── 0 · El laboratorio es el que creo ──────────────────────────────────────
-- La 0240 tiene que haberle puesto la fecha_jornada de ayer a la salida de Ana.
-- Si esto fallara, las de abajo medirian otra cosa.
select is(
  (select fecha_jornada from marcajes
    where persona_id = '00000000-0000-0000-0000-00000fff0001' and tipo = 'salida_final'),
  fn_hoy_lima() - 1,
  'la salida de las 00:30 quedo con la fecha_jornada de AYER (0240)'
);

-- ── 1 · LA IMPORTANTE ──────────────────────────────────────────────────────
select throws_ok(
  $rab$ select fn_reabrir_dia('00000000-0000-0000-0000-00000fff0001', 'volvi a entrar') $rab$,
  'No hay una salida final de hoy para reabrir.',
  'la salida de anoche NO se puede reabrir: no es de la jornada de hoy'
);

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000fff0001'
      and tipo = 'salida_final' and anulada_at is null),
  1,
  'y sigue viva: sus horas de anoche no se pierden'
);

-- ── 2 · Y EL CASO CORRIENTE NO SE ROMPE ────────────────────────────────────
-- La que impide el remedio peor. Un arreglo que exigiera `fecha_jornada = hoy`
-- pasaria las de arriba y dejaria sin reabrir a todo el mundo: las marcas
-- normales no llevan esa columna.
select lives_ok(
  $rab$ select fn_reabrir_dia('00000000-0000-0000-0000-00000fff0002', 'me faltaba cerrar caja') $rab$,
  'quien cerro su dia hoy SI puede reabrirlo, igual que siempre'
);

select * from finish();
rollback;
