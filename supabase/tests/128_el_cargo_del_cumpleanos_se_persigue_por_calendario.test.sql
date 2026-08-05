-- ============================================================================
-- 128_el_cargo_del_cumpleanos_se_persigue_por_calendario.test.sql
-- ============================================================================
-- La asignación por onomástico se entrega UNA vez al año y en el mes del
-- cumpleaños. Eso la hace distinta de la declaración de ruta: no se olvida por
-- descuido, se olvida por calendario — en diciembre nadie recuerda si alguien
-- firmó en agosto.
--
-- Lo que este archivo vigila es que el tablero sepa a quién perseguir HOY y, más
-- importante, a quién NO. Acusar de un papel faltante a quien todavía no cumple
-- años —o a quien entró después de su onomástico— es el falso positivo que este
-- sistema paga más caro: un aviso que grita sin motivo se ignora a la semana, y
-- entonces deja de avisar también cuando tiene razón.
--
-- Las pruebas de reparto están escritas contra los DOCE meses a la vez y no
-- contra un mes concreto, para que sigan siendo ciertas en enero y en diciembre:
-- si estamos en el mes M, tienen que quedar M-1 vencidos, exactamente 1 de este
-- mes y 12-M próximos. Un test que solo pasa en agosto no prueba una regla,
-- prueba el día en que se escribió.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000d1f00', 'ZZBON', 'Sede de laboratorio bono', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000d1f99', 'BonoDO', 'Laboratorio',
        '00000000-0000-0000-0000-0000000d1f00', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-0000000d1f98', '2020-01-01');
set session_replication_role = origin;

-- Doce personas antiguas, una por cada mes de nacimiento. Ingreso viejo a
-- propósito: así ninguna cae en «entró después de su onomástico» y lo único que
-- decide su estado es el calendario, que es lo que se quiere medir.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
select ('00000000-0000-0000-0000-0000000d1f' || lpad(m::text, 2, '0'))::uuid,
       'BonoMes' || m, 'Laboratorio', '00000000-0000-0000-0000-0000000d1f00',
       'test-hash', '2020-01-01', 'planilla'
from generate_series(1, 12) m;

insert into datos_personales (persona_id, fecha_nacimiento)
select ('00000000-0000-0000-0000-0000000d1f' || lpad(m::text, 2, '0'))::uuid,
       make_date(1995, m, 15)
from generate_series(1, 12) m;

-- Sin fecha de nacimiento cargada en su ficha.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000d1f20', 'BonoSinFecha', 'Laboratorio',
        '00000000-0000-0000-0000-0000000d1f00', 'test-hash', '2020-01-01', 'planilla');

-- Se incorpora en diciembre de este año y cumple en enero: ese onomástico ya
-- había pasado cuando entró, así que no hay ningún papel faltante. Diciembre y
-- enero están elegidos para que la afirmación valga los doce meses del año.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000d1f21', 'BonoRecienEntra', 'Laboratorio',
        '00000000-0000-0000-0000-0000000d1f00', 'test-hash',
        make_date(extract(year from fn_hoy_lima())::int, 12, 1), 'planilla');
insert into datos_personales (persona_id, fecha_nacimiento)
values ('00000000-0000-0000-0000-0000000d1f21', make_date(1995, 1, 15));

-- Ya firmó el cargo de este año. Nacida en enero: sin el documento estaría en
-- rojo once meses del año, así que sirve para comprobar que «ok» gana.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000d1f22', 'BonoYaFirmo', 'Laboratorio',
        '00000000-0000-0000-0000-0000000d1f00', 'test-hash', '2020-01-01', 'planilla');
insert into datos_personales (persona_id, fecha_nacimiento)
values ('00000000-0000-0000-0000-0000000d1f22', make_date(1995, 1, 15));

-- Firmó, pero el cargo es del año pasado. El bono es anual: ese papel no
-- sostiene el pago de este año.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000d1f23', 'BonoDelAnioPasado', 'Laboratorio',
        '00000000-0000-0000-0000-0000000d1f00', 'test-hash', '2020-01-01', 'planilla');
insert into datos_personales (persona_id, fecha_nacimiento)
values ('00000000-0000-0000-0000-0000000d1f23', make_date(1995, 1, 15));

-- Un locador: no es trabajador, así que no recibe beneficios de trabajador.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000d1f24', 'BonoLocador', 'Laboratorio',
        '00000000-0000-0000-0000-0000000d1f00', 'test-hash', '2020-01-01', 'rxh');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d1f98', true);

select fn_documento_registrar('bono', fn_hoy_lima(), '00000000-0000-0000-0000-0000000d1f22',
       null, null, extract(year from fn_hoy_lima())::int);

select fn_documento_registrar('bono', (fn_hoy_lima() - interval '1 year')::date,
       '00000000-0000-0000-0000-0000000d1f23',
       null, null, extract(year from fn_hoy_lima() - interval '1 year')::int);


-- ── El reparto por calendario, cierto los doce meses del año ───────────────
select is(
  (select count(*)::int from fn_documentos_tablero()
    where persona_id::text like '00000000-0000-0000-0000-0000000d1f%'
      and persona_id::text < '00000000-0000-0000-0000-0000000d1f13'
      and bono_estado = 'vencido'),
  extract(month from fn_hoy_lima())::int - 1,
  'CALENDARIO · quedan en rojo exactamente los meses que ya pasaron');

select is(
  (select count(*)::int from fn_documentos_tablero()
    where persona_id::text like '00000000-0000-0000-0000-0000000d1f%'
      and persona_id::text < '00000000-0000-0000-0000-0000000d1f13'
      and bono_estado = 'este_mes'),
  1,
  'CALENDARIO · y exactamente una persona cumple años este mes');

select is(
  (select count(*)::int from fn_documentos_tablero()
    where persona_id::text like '00000000-0000-0000-0000-0000000d1f%'
      and persona_id::text < '00000000-0000-0000-0000-0000000d1f13'
      and bono_estado = 'proximo'),
  12 - extract(month from fn_hoy_lima())::int,
  'CALENDARIO · a quien cumple más adelante NO se le reclama nada todavía');

select is(
  (select bono_mes from fn_documentos_tablero()
    where persona_id::text like '00000000-0000-0000-0000-0000000d1f%'
      and persona_id::text < '00000000-0000-0000-0000-0000000d1f13'
      and bono_estado = 'este_mes'),
  extract(month from fn_hoy_lima())::int,
  'CALENDARIO · el mes que informa el tablero es el mes real de su onomástico');


-- ── Los tres «no le reclames a esta persona» ───────────────────────────────
select is(
  (select bono_estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d1f20'),
  'sin_fecha',
  'FALSO POSITIVO · sin fecha de nacimiento se pide el dato, no se acusa de nada');

select is(
  (select bono_estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d1f21'),
  'no_aplica',
  'FALSO POSITIVO · quien entró después de su onomástico no tiene papel pendiente');

select is(
  (select bono_estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d1f22'),
  'ok',
  'FIRMADO · con el cargo de este año archivado, el aviso se apaga');


-- ── El bono es anual: el papel del año pasado no cubre este año ────────────
select isnt(
  (select bono_estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d1f23'),
  'ok',
  'ANUAL · un cargo del año pasado NO da por firmado el de este año');

select is(
  (select bono_anio from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d1f23'),
  null,
  'ANUAL · y el tablero no lo muestra como si fuera el vigente');


-- ── A un locador no se le pide ningún papel de trabajador ──────────────────
-- Antes de la 0161 esta condición solo miraba la declaración de ruta: el bono
-- de un locador entraba sin protestar. Eran dos reglas del mismo hecho.
select throws_like(
  $$ select fn_documento_registrar('bono', fn_hoy_lima(), '00000000-0000-0000-0000-0000000d1f24',
       null, null, extract(year from fn_hoy_lima())::int) $$,
  '%no está en planilla%',
  'RXH · a un locador no se le entrega asignación por onomástico: se le paga su recibo');

select throws_like(
  $$ select fn_documento_registrar('ruta', fn_hoy_lima(), '00000000-0000-0000-0000-0000000d1f24',
       'x', 10.00) $$,
  '%no está en planilla%',
  'RXH · y la regla de la declaración de ruta (0157) sigue en pie');

select * from finish();
rollback;
