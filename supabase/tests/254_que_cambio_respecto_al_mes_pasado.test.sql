-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 254_que_cambio_respecto_al_mes_pasado.test.sql
-- ============================================================================
-- Fija la 0318: el informe de variación contra el periodo anterior.
--
-- ── LO QUE ESTA PRUEBA CUIDA DE VERDAD ─────────────────────────────────────
--
-- No es que los números salgan. Son dos cosas, y las dos se pueden romper sin
-- que nada falle:
--
--   1. QUE NO SE PIERDA NADIE. Quien cesa y deja de aparecer en la planilla se
--      esfuma también de cualquier informe que recorra el periodo actual. Es
--      justo el hallazgo de S/1 509,64 —«quien cesa sin marcas desaparece y
--      cobra S/0»— y es el que hace falta VER. Por eso el `full outer join`, y
--      por eso hay una aserción que solo comprueba que esa fila existe.
--
--   2. QUE NO GRITE DE MÁS. Las tres ausencias que la planilla paga SIN
--      marcaje —vacaciones, descanso médico, maternidad— dejan el total quieto
--      y las horas en cero. Es exactamente la forma del defecto que persigue
--      `cobra_igual_trabajo_menos`, así que sin la guarda de ausencias el aviso
--      marca a media empresa cada vez que alguien se toma sus vacaciones. Aquí
--      el falso positivo es el peor error: un informe que chilla se ignora al
--      segundo mes, y entonces el día que avise de verdad nadie lo va a leer.
--
--      Esa aserción FUERZA el umbral a 40 % a propósito. Con el umbral normal
--      del 2 % la prueba pasaría por casualidad —el caso se libra por cómo le
--      salieron las cuentas, no por la guarda— y una prueba que pasa por
--      casualidad no fija nada. Se descubrió midiendo: en la auditoría de la
--      0318 el caso de vacaciones se salvó por un 4,4 %.
--
-- ── Y LA TERCERA, QUE ES DE DISEÑO ─────────────────────────────────────────
--
-- Que el lado ya pagado se lea de su FOTO (`previo_fuente = 'foto'`) y no se
-- recalcule con las reglas de hoy. Si alguien «simplifica» esta función para
-- que llame directo a `fn_planilla_calcular`, todo seguirá funcionando y el
-- informe pasará a comparar el presente contra un pasado que nunca ocurrió —
-- mintiendo justo donde promete avisar. Esa aserción es la que lo impide.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000c0001', 'ZZVA', 'Lab variación', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000c0002', 'VaAdmin', 'Vaa',
        '00000000-0000-0000-0000-0000000c0001', 'admin', 'x',
        '00000000-0000-0000-0000-0000000c0fff', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, funcion, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000c0003', 'VaEncargada', 'Vaa',
        '00000000-0000-0000-0000-0000000c0001', 'supervisor_sede', 'x',
        '00000000-0000-0000-0000-0000000c0ffe', '2024-01-01', 'tienda_ventas', 'planilla');
set session_replication_role = origin;

-- El elenco: uno por cada forma de no parecerse al mes pasado.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo) values
  ('00000000-0000-0000-0000-0000000c0004', 'VaControl',    'Vaa', '00000000-0000-0000-0000-0000000c0001', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-0000000c0005', 'VaCesoConAviso','Vaa','00000000-0000-0000-0000-0000000c0001', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-0000000c0006', 'VaCesoSinAviso','Vaa','00000000-0000-0000-0000-0000000c0001', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-0000000c0007', 'VaFijo',       'Vaa', '00000000-0000-0000-0000-0000000c0001', 'x', '2024-01-01', 'taller_produccion', 'planilla', true),
  ('00000000-0000-0000-0000-0000000c0008', 'VaDescMedico', 'Vaa', '00000000-0000-0000-0000-0000000c0001', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-0000000c0009', 'VaRecienEntra','Vaa', '00000000-0000-0000-0000-0000000c0001', 'x', '2026-08-05', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-0000000c000a', 'VaLeSubieron', 'Vaa', '00000000-0000-0000-0000-0000000c0001', 'x', '2024-01-01', 'taller_produccion', 'planilla', false);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 3000, '2024-01-01' from personas
 where apellidos = 'Vaa' and rol not in ('admin','supervisor_sede')
   and id <> '00000000-0000-0000-0000-0000000c000a';

-- A este le suben el sueldo justo entre los dos periodos: su salto tiene
-- explicación, y esa explicación es lo que evita el falso positivo.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-0000000c000a', 'colibri', 3000, '2024-01-01', '2026-07-28');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000c000a', 'colibri', 4200, '2026-07-29');

-- ⚠️ ESPEJA PRODUCCIÓN: en CAYLA se declara el sueldo ÍNTEGRO (22 de 22 medidas
-- el 2026-08-08), no el DEFAULT de la RMV. Un fixture con el default mide otra
-- empresa. El admin y la encargada quedan fuera de este `update` a propósito:
-- tocar sus filas revalida la FK a `auth.users`, que aquí no existe.
update personas set sueldo_base_legal = 3000
 where apellidos = 'Vaa' and rol not in ('admin','supervisor_sede')
   and id <> '00000000-0000-0000-0000-0000000c000a';
update personas set sueldo_base_legal = 4200
 where id = '00000000-0000-0000-0000-0000000c000a';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39
from personas where apellidos = 'Vaa' and rol not in ('admin','supervisor_sede');

insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde)
select id, 'onp', '2024-01-01' from personas
 where apellidos = 'Vaa' and rol not in ('admin','supervisor_sede');

-- Dos periodos del MISMO largo (31 días), para que el control no se mueva por
-- el calendario. Y un tercero más corto, para la marca de distinto largo.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('eeeeeeee-0000-0000-0000-0000000c0001', '2026-06-28', '2026-07-28', 'abierto'),
  ('eeeeeeee-0000-0000-0000-0000000c0002', '2026-07-29', '2026-08-28', 'abierto'),
  ('eeeeeeee-0000-0000-0000-0000000c0003', '2026-08-29', '2026-09-20', 'abierto');

-- Los dos ceses. El primero con su fecha registrada.
update personas set fecha_cese = '2026-07-28', estado = 'inactivo'
 where id = '00000000-0000-0000-0000-0000000c0005';
-- El segundo NO se marca inactivo: `personas_cese_coherente` no deja un
-- inactivo sin fecha de cese, y eso está bien. Su caso es el que de verdad
-- muerde: sigue ACTIVA, sin cese registrado, y simplemente dejó de aparecer.
-- Nadie tiene por qué saber por qué cobra S/0 — y esa es la fila que hay que
-- poder ver.

-- Descanso médico de casi todo el periodo: paga sin marcaje.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at)
values ('00000000-0000-0000-0000-0000000c0008', 'descanso_medico', '2026-08-03', '2026-08-28', 'lab',
        '00000000-0000-0000-0000-0000000c0002', '00000000-0000-0000-0000-0000000c0002', now());

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000c0fff', true);

-- Periodo previo: todos marcan todos sus días laborables.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-0000000c0001', m.tipo,
       (d.d::date::text || m.hora)::timestamptz
from personas p,
     generate_series('2026-06-28'::date, '2026-07-28'::date, '1 day') d,
     (values ('entrada'::tipo_marca, 'T09:00:00-05:00'),
             ('salida_final'::tipo_marca, 'T15:30:00-05:00')) m(tipo, hora)
where p.apellidos = 'Vaa' and p.rol not in ('admin','supervisor_sede')
  and p.fecha_ingreso <= d.d::date
  and extract(dow from d.d)::int between 1 and 6;

-- Periodo actual: los dos cesados no marcan. El de sueldo fijo marca solo la
-- primera semana — cobra igual y trabaja mucho menos.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-0000000c0001', m.tipo,
       (d.d::date::text || m.hora)::timestamptz
from personas p,
     generate_series('2026-07-29'::date, '2026-08-28'::date, '1 day') d,
     (values ('entrada'::tipo_marca, 'T09:00:00-05:00'),
             ('salida_final'::tipo_marca, 'T15:30:00-05:00')) m(tipo, hora)
where p.apellidos = 'Vaa' and p.rol not in ('admin','supervisor_sede')
  and p.id not in ('00000000-0000-0000-0000-0000000c0005',
                   '00000000-0000-0000-0000-0000000c0006')
  and p.fecha_ingreso <= d.d::date
  and extract(dow from d.d)::int between 1 and 6
  and not exists (select 1 from ausencias a
                   where a.persona_id = p.id and a.aprobada_at is not null
                     and d.d::date between a.fecha_inicio and a.fecha_fin)
  and (p.id <> '00000000-0000-0000-0000-0000000c0007' or d.d::date <= '2026-08-04');

-- ── Atajos de lectura ───────────────────────────────────────────────────────

create or replace function pg_temp.inf(p_periodo uuid default 'eeeeeeee-0000-0000-0000-0000000c0002')
returns jsonb language sql as $f$
  select fn_planilla_variacion(p_periodo);
$f$;

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(pg_temp.inf() -> 'filas') x
   where x->>'nombre' like p_nombre || '%';
$f$;

create or replace function pg_temp.tiene_aviso(p_nombre text, p_aviso text)
returns boolean language sql as $f$
  select coalesce(pg_temp.fila(p_nombre) -> 'avisos' ? p_aviso, false);
$f$;

create or replace function pg_temp.explica(p_nombre text, p_motivo text)
returns boolean language sql as $f$
  select coalesce(pg_temp.fila(p_nombre) -> 'explica' ? p_motivo, false);
$f$;


-- ── 1 · QUE NO SE PIERDA NADIE ──────────────────────────────────────────────
-- La aserción más importante del archivo. Quien cesó ya no está en la planilla
-- del periodo actual; si el informe recorriera solo ese lado, su fila no
-- existiría y el hallazgo de S/1 509,64 seguiría siendo invisible.

select isnt(pg_temp.fila('VaCesoConAviso'), null,
  'quien cesó y desapareció de la planilla SÍ tiene fila en el informe');

select ok(pg_temp.tiene_aviso('VaCesoConAviso', 'salio'),
  'y sale marcado como que salió');

select ok(pg_temp.explica('VaCesoConAviso', 'ceso'),
  'con su cese al lado, para que no haya que ir a buscarlo a otra pantalla');

-- El caso feo, y el que justifica todo esto: cobra S/0, nadie registró un cese,
-- y el informe no tiene NADA que ofrecer como explicación. Esa fila desnuda es
-- la que hay que mirar.
select ok(pg_temp.tiene_aviso('VaCesoSinAviso', 'cobra_cero'),
  'quien cobra S/0 sin cese registrado sale marcado');

select is(jsonb_array_length(pg_temp.fila('VaCesoSinAviso') -> 'explica'), 0,
  'y sin ninguna explicación — que es justo lo que la hace digna de mirarse');


-- ── 2 · EL ORDEN ES LA FUNCIÓN ──────────────────────────────────────────────
-- Si esto se rompe, la función sigue devolviendo todo y deja de servir para
-- nada: nadie lee treinta filas cada mes buscando la que se movió.

select ok(
  abs(((pg_temp.inf() -> 'filas' -> 0) ->> 'delta')::numeric)
  >= abs(((pg_temp.inf() -> 'filas' -> 1) ->> 'delta')::numeric),
  'las filas salen ordenadas por magnitud del cambio, de mayor a menor');


-- ── 3 · LOS DOS AVISOS QUE UN PORCENTAJE NO VE ──────────────────────────────

select ok(pg_temp.tiene_aviso('VaFijo', 'cobra_igual_trabajo_menos'),
  'el sueldo fijo que cobra igual habiendo trabajado una cuarta parte sale marcado');

select ok(pg_temp.tiene_aviso('VaRecienEntra', 'empieza_a_cobrar'),
  'quien pasa de S/0 a cobrar sale marcado: con el previo en 0 no hay porcentaje que ver');


-- ── 4 · QUE NO GRITE DE MÁS ─────────────────────────────────────────────────
-- ⚠️ EL UMBRAL SE FUERZA AL 40 % A PROPÓSITO. Con el 2 % de fábrica esta
-- aserción pasaría por casualidad, y una prueba que pasa por casualidad no fija
-- nada: al 40 % lo ÚNICO que separa al descanso médico del sueldo fijo es la
-- guarda `aus_act <= aus_prev`. Quítala y esta línea se pone roja.

update configuracion
   set valor = '{"salto_pct": 25, "salto_soles": 100, "quieto_pct": 40, "horas_caen_pct": 20}'::jsonb
 where clave = 'planilla_variacion_umbrales';

select ok(not pg_temp.tiene_aviso('VaDescMedico', 'cobra_igual_trabajo_menos'),
  'una ausencia aprobada NO dispara «cobra igual y trabajó menos», ni con el umbral forzado');

select ok(pg_temp.explica('VaDescMedico', 'mas_ausencias'),
  'pero su fila sigue ahí y dice por qué: no se esconde, solo no se grita');

update configuracion
   set valor = '{"salto_pct": 25, "salto_soles": 100, "quieto_pct": 2, "horas_caen_pct": 20}'::jsonb
 where clave = 'planilla_variacion_umbrales';

select ok(pg_temp.explica('VaLeSubieron', 'sueldo_cambio'),
  'un salto con subida de sueldo detrás llega con su explicación al lado');

select is(pg_temp.fila('VaAdmin'), null,
  'quien no cobró ni trabajó en ninguno de los dos periodos no gasta una fila');


-- ── 5 · LO QUE MÁS CARO COSTARÍA ROMPER ─────────────────────────────────────
-- El lado ya pagado se LEE de su foto. Si alguien cambia esta función para
-- llamar directo a `fn_planilla_calcular`, nada falla y el informe pasa a
-- comparar contra un pasado que nunca ocurrió.

select fn_periodo_pagado('eeeeeeee-0000-0000-0000-0000000c0001', true);

select is(pg_temp.inf() ->> 'previo_fuente', 'foto',
  'el periodo anterior ya pagado se compara por lo que se PAGÓ, no por lo que se recalcularía hoy');


-- ── 6 · La superficie ───────────────────────────────────────────────────────

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000c0ffe', true);

select throws_ok(
  $$ select fn_planilla_variacion('eeeeeeee-0000-0000-0000-0000000c0002') $$,
  'Solo un administrador o líder puede ver la variación de la planilla.',
  'una encargada de sede no ve la variación de la planilla');

select * from finish();
rollback;
