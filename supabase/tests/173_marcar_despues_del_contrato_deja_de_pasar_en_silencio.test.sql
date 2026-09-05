-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 173_marcar_despues_del_contrato_deja_de_pasar_en_silencio.test.sql
-- ============================================================================
-- Artículo 8.8 a) del Reglamento, que recoge el artículo 77 de la LPCL: el
-- contrato sujeto a modalidad se vuelve de duración indeterminada si la
-- colaboradora sigue laborando después de la fecha de vencimiento.
--
-- No hace falta que nadie firme ni reclame: basta con que venga un día más. Y
-- ese día lo registra el propio sistema.
--
-- Los bordes que fija esta prueba, que es donde se equivoca una consulta así:
--   · Marcar EL MISMO día del vencimiento NO cuenta. Ese campo es «el último
--     día que trabaja», así que venir ese día es cumplir el contrato.
--   · Marcar el día siguiente SÍ cuenta, y desde el primero.
--   · Una marca ANULADA no cuenta: el sistema ya declaró que no ocurrió.
--   · Se cuentan DÍAS, no marcajes. Entrar y salir el mismo día es un día.
--   · Quien no tiene fecha de fin —contrato indefinido— nunca aparece.
--   · Y una marca de la noche del último día NO fabrica un día de más: la
--     fecha se saca en hora de Lima, no en UTC.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000d001', 'ZZDES', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000d002', 'DoDesnat', 'Lab',
        '00000000-0000-0000-0000-00000000d001', 'lider_do', 'x',
        '00000000-0000-0000-0000-000000d00002', '2020-01-01', 'activo', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, tipo_vinculo, fecha_fin_contrato) values
  ('00000000-0000-0000-0000-00000000d003', 'SiguioViniendo', 'Lab', '00000000-0000-0000-0000-00000000d001', 'x', '2024-01-01', 'activo', 'planilla', '2026-07-31'),
  ('00000000-0000-0000-0000-00000000d004', 'ParoAlVencer',   'Lab', '00000000-0000-0000-0000-00000000d001', 'x', '2024-01-01', 'activo', 'planilla', '2026-07-31'),
  ('00000000-0000-0000-0000-00000000d005', 'SoloAnulada',    'Lab', '00000000-0000-0000-0000-00000000d001', 'x', '2024-01-01', 'activo', 'planilla', '2026-07-31'),
  ('00000000-0000-0000-0000-00000000d006', 'Indefinida',     'Lab', '00000000-0000-0000-0000-00000000d001', 'x', '2024-01-01', 'activo', 'planilla', null);

-- ── Los marcajes ────────────────────────────────────────────────────────────
-- Se escriben directo y no por fn_registrar_marcaje: lo que se prueba es la
-- consulta que los lee, y la máquina de estados del marcaje tiene su propia
-- prueba. Aquí interesa el hecho bruto de qué día vino cada quien.
--
-- `client_uuid` es obligatorio y va con `gen_random_uuid()`: es la clave con la
-- que se reconcilian los marcajes que llegan tarde desde un terminal sin red,
-- así que dos marcas nunca comparten el suyo.
set session_replication_role = replica;

-- SiguioViniendo: el último día de contrato (no cuenta) y dos días después
-- (cuentan). El segundo día lleva DOS marcas, entrada y salida: tiene que
-- contarse como UN día.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-00000000d001', 'entrada', '2026-07-31 09:00-05'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-00000000d001', 'entrada', '2026-08-03 09:00-05'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-00000000d001', 'entrada', '2026-08-04 09:00-05'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-00000000d001', 'salida_final',  '2026-08-04 18:00-05');

-- ParoAlVencer: vino su último día, y esa noche a las 8. En UTC eso ya es el
-- 1 de agosto — si la consulta leyera en UTC, le inventaría una
-- desnaturalización a quien cumplió su contrato exactamente.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-00000000d001', 'entrada', '2026-07-31 09:00-05'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-00000000d001', 'salida_final',  '2026-07-31 20:00-05');

-- SoloAnulada: una marca posterior, pero anulada.
--
-- La anulación va COMPLETA —fecha, autor y motivo— porque `chk_anulacion_completa`
-- no admite menos: una marca anulada sin saber quién la anuló no es trazable, y
-- este sistema se apoya en que toda corrección deje rastro.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, anulada_at, anulada_por, anulada_motivo) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d005', '00000000-0000-0000-0000-00000000d001', 'entrada', '2026-08-05 09:00-05',
   now(), '00000000-0000-0000-0000-00000000d002', 'marca de prueba');

-- Indefinida: marca posterior a todo, pero no tiene fecha de fin.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d006', '00000000-0000-0000-0000-00000000d001', 'entrada', '2026-08-06 09:00-05');

set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000d00002', true);

create temp table _des as select * from fn_contratos_desnaturalizados();

-- ── Quién aparece ───────────────────────────────────────────────────────────
select is((select count(*)::int from _des where persona_id = '00000000-0000-0000-0000-00000000d003'),
          1, 'ART. 77 · quien siguió viniendo después del vencimiento aparece');

select is((select count(*)::int from _des where persona_id = '00000000-0000-0000-0000-00000000d004'),
          0, 'EL ÚLTIMO DÍA NO CUENTA · venir el día del vencimiento es cumplir el contrato, no excederlo');

select is((select count(*)::int from _des where persona_id = '00000000-0000-0000-0000-00000000d005'),
          0, 'ANULADA · una marca que el sistema declaró inexistente no funda una desnaturalización');

select is((select count(*)::int from _des where persona_id = '00000000-0000-0000-0000-00000000d006'),
          0, 'INDEFINIDO · sin fecha de fin no hay plazo que exceder');

-- ── Y qué dice de quien sí aparece ──────────────────────────────────────────
select is((select dias_marcados_despues from _des where persona_id = '00000000-0000-0000-0000-00000000d003'),
          2, 'DÍAS, NO MARCAJES · dos días después, aunque uno traiga entrada y salida');

select is((select primer_dia_despues from _des where persona_id = '00000000-0000-0000-0000-00000000d003'),
          '2026-08-03'::date, 'EL PRIMER DÍA · es la fecha en que el contrato se volvió indefinido');

select is((select ultimo_dia_marcado from _des where persona_id = '00000000-0000-0000-0000-00000000d003'),
          '2026-08-04'::date, 'EL ÚLTIMO · dice si sigue viniendo hoy o si ya paró');

-- ── Y no la ve cualquiera ───────────────────────────────────────────────────
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000d007', 'IntegranteDesnat', 'Lab',
        '00000000-0000-0000-0000-00000000d001', 'integrante', 'x',
        '00000000-0000-0000-0000-000000d00007', '2020-01-01', 'activo', 'planilla');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000d00007', true);
select is((select count(*)::int from fn_contratos_desnaturalizados()),
          0, 'RESERVA · una integrante no ve quién tiene el contrato en el aire');

select * from finish();
rollback;
