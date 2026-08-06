-- ============================================================================
-- 132_el_bono_no_se_reclama_hacia_atras.test.sql
-- ============================================================================
-- El 2026-08-05, el día que la columna del bono se estrenó en producción, el
-- tablero acusó a SEIS personas de no tener un papel que nunca les tocó firmar:
-- «cumplió en mayo y no hay cargo», «cumplió en marzo y no hay cargo». Cuando
-- esas seis cumplieron años, el bono no existía. No se les dejó de entregar
-- nada.
--
-- Lo que este archivo vigila es que la columna no vuelva a reclamar hacia atrás.
-- Seis acusaciones falsas de golpe en una pantalla recién estrenada es la forma
-- más rápida de que nadie vuelva a creerle — y entonces deja de servir también
-- el día que tiene razón.
--
-- Las pruebas están escritas contra un arranque de política FIJO (29/07/2026) y
-- meses relativos a él, no a hoy, porque lo que se mide es el corte: qué queda a
-- cada lado de la fecha en que la política empezó a existir.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000d2f00', 'ZZBN2', 'Sede de laboratorio bono 2', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000d2f99', 'Bono2DO', 'Laboratorio',
        '00000000-0000-0000-0000-0000000d2f00', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-0000000d2f98', '2020-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d2f98', true);


-- ── La fecha de arranque está donde se puede cambiar sin tocar código ──────
select is(
  (select min(vigente_desde) from parametros_laborales where clave = 'bono_onomastico'),
  '2026-07-29'::date,
  'ARRANQUE · la política del bono rige desde el 29/07/2026, y vive en parametros_laborales');

select is(
  (select min(valor) from parametros_laborales where clave = 'bono_onomastico'),
  180::numeric,
  'ARRANQUE · el monto vive en la misma fila, no escrito a mano en la pantalla');


-- ── El corte: mismo mes de nacimiento, dos lados de la fecha ───────────────
-- Las tres nacen en un mes ANTERIOR al arranque de la política. La única
-- diferencia entre ellas es el año en el que estamos parados, así que se
-- construyen contra el arranque y no contra hoy.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values
  ('00000000-0000-0000-0000-0000000d2f01', 'BonoAntes',  'Laboratorio',
   '00000000-0000-0000-0000-0000000d2f00', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000d2f02', 'BonoDespues', 'Laboratorio',
   '00000000-0000-0000-0000-0000000d2f00', 'test-hash', '2020-01-01', 'planilla');

-- Nace en marzo: su onomástico de 2026 cayó CUATRO MESES antes de que el bono
-- existiera. Es el caso exacto de las seis personas del 2026-08-05.
insert into datos_personales (persona_id, fecha_nacimiento)
values ('00000000-0000-0000-0000-0000000d2f01', make_date(1995, 3, 15));

-- Nace en diciembre: su onomástico de 2026 cae DESPUÉS del arranque, así que
-- este año sí le corresponde.
insert into datos_personales (persona_id, fecha_nacimiento)
values ('00000000-0000-0000-0000-0000000d2f02', make_date(1995, 12, 15));

select isnt(
  (select bono_estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d2f01'),
  'vencido',
  'HACIA ATRÁS · quien cumplió antes del arranque NO sale acusada de nada');

select is(
  (select bono_estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d2f01'),
  'no_aplica',
  'HACIA ATRÁS · sale como «no le tocaba», el mismo estado que quien entró después de su onomástico');

select isnt(
  (select bono_estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d2f02'),
  'no_aplica',
  'HACIA ADELANTE · a quien cumple después del arranque SÍ le corresponde este año');


-- ── Sin el parámetro, el aviso no se apaga solo ────────────────────────────
-- Un valor que falta no puede decidir por su cuenta que nadie debe nada. Si la
-- fila desaparece, el tablero vuelve a comportarse como antes de la 0165 en vez
-- de dejar a todo el mundo en gris — que sería un silencio que nadie pidió.
delete from parametros_laborales where clave = 'bono_onomastico';

select is(
  (select bono_estado from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d2f01'),
  case when extract(month from fn_hoy_lima())::int > 3 then 'vencido'
       when extract(month from fn_hoy_lima())::int = 3 then 'este_mes'
       else 'proximo' end,
  'SIN PARÁMETRO · sin la fila, el corte no se aplica y el tablero vuelve a lo de antes');

select is(
  (select count(*)::int from fn_documentos_tablero()
    where persona_id::text like '00000000-0000-0000-0000-0000000d2f0%'),
  2,
  'SIN PARÁMETRO · y nadie desaparece del tablero por un parámetro ausente');

select * from finish();
rollback;
