-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 248_el_catalogo_decide_que_ausencia_paga.test.sql
-- ============================================================================
-- Fija la 0314. `fn_planilla_calcular` conocía DOS tipos de ausencia por su
-- nombre —`descanso_medico` y `maternidad`— y cualquier otro marcado
-- `paga = true` en el catálogo se ignoraba en silencio. `licencia_con_goce`
-- llevaba meses activa, en el desplegable, con la pantalla prometiendo al
-- aprobarla que «esos días entran en su planilla». No entraban.
--
-- La 0314 lo invierte: paga lo que el CATÁLOGO dice que paga, y excluye solo
-- los tres que tienen tratamiento propio (descanso médico por su tope de 20
-- días, maternidad por su subsidio de días calendario, vacaciones por `vacd`).
--
-- Lo que esta prueba vigila, en orden de lo que más cara costaría romper:
--
--   · que el duelo de familiar DIRECTO se pague (Ley 31602, art. 31.4.a del
--     Reglamento Interno: cinco días no compensables) y el otro duelo no;
--   · que sin la firma de DO no se pague nada — la regla de la 0306, que el
--     lateral nuevo lleva desde el primer día;
--   · y las tres que evitan pagar DOS VECES el mismo día: descanso médico y
--     vacaciones no se mueven ni un céntimo, y un día FICHADO dentro de una
--     licencia no se paga además como ausencia (la regla de la 0286).
--
-- Se hereda además la 0302: una ausencia pagada se devenga por días
-- LABORABLES, no de calendario. Por eso el domingo de dentro no se paga.
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000c01', 'ZZDU', 'Sede de laboratorio duelo', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000c02', 'DuAdmin', 'Duelo',
        '00000000-0000-0000-0000-000000000c01', 'admin', 'x',
        '00000000-0000-0000-0000-000000000cff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000000c03', 'DueloFirmado',  'Duelo', '00000000-0000-0000-0000-000000000c01', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000c04', 'DueloSinFirma', 'Duelo', '00000000-0000-0000-0000-000000000c01', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000c05', 'DueloOtro',     'Duelo', '00000000-0000-0000-0000-000000000c01', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000c06', 'LicGoce',       'Duelo', '00000000-0000-0000-0000-000000000c01', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000c07', 'LicGoceFichada','Duelo', '00000000-0000-0000-0000-000000000c01', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000c08', 'LicGoceDomingo','Duelo', '00000000-0000-0000-0000-000000000c01', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000c09', 'DmControl',     'Duelo', '00000000-0000-0000-0000-000000000c01', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000c0a', 'VacControl',    'Duelo', '00000000-0000-0000-0000-000000000c01', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000c0b', 'DuControl',     'Duelo', '00000000-0000-0000-0000-000000000c01', 'x', '2024-01-01', 'taller_produccion', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1300, '2024-01-01' from personas where apellidos = 'Duelo' and rol is distinct from 'admin';

-- Lunes a sábado. El domingo NO es laborable: es lo que hace medible la 0302.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39
from personas where apellidos = 'Duelo' and rol is distinct from 'admin';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-000000000c01', '2026-07-29', '2026-08-28', 'abierto');

-- Del lunes 10 al viernes 14 de agosto: cinco días, los cinco laborables.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-000000000c03', 'duelo_familiar_directo', '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000c02'),
  ('00000000-0000-0000-0000-000000000c04', 'duelo_familiar_directo', '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000c02'),
  ('00000000-0000-0000-0000-000000000c05', 'duelo',                  '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000c02'),
  ('00000000-0000-0000-0000-000000000c06', 'licencia_con_goce',      '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000c02'),
  ('00000000-0000-0000-0000-000000000c07', 'licencia_con_goce',      '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000c02'),
  -- Lunes 10 a domingo 16: SIETE días de calendario, SEIS laborables.
  ('00000000-0000-0000-0000-000000000c08', 'licencia_con_goce',      '2026-08-10', '2026-08-16', 'lab', '00000000-0000-0000-0000-000000000c02'),
  ('00000000-0000-0000-0000-000000000c09', 'descanso_medico',        '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-000000000c02');

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at)
values ('00000000-0000-0000-0000-000000000c0a', 'vacaciones', '2026-08-10', '2026-08-14', 'lab',
        '00000000-0000-0000-0000-000000000c02', '00000000-0000-0000-0000-000000000c02', now());

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000cff', true);

-- Todas firman DO menos DueloSinFirma, que es justamente el caso.
select fn_aprobar_ausencia(a.id) from ausencias a
 where a.persona_id in ('00000000-0000-0000-0000-000000000c03',
                        '00000000-0000-0000-0000-000000000c05',
                        '00000000-0000-0000-0000-000000000c06',
                        '00000000-0000-0000-0000-000000000c07',
                        '00000000-0000-0000-0000-000000000c08',
                        '00000000-0000-0000-0000-000000000c09');

-- Las nueve marcan los mismos tres días de la semana SIGUIENTE a la ausencia,
-- para que todas lleguen al cálculo con la misma base de horas.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-000000000c01', m.tipo, m.ts
from personas p,
     (values ('entrada'::tipo_marca,      timestamptz '2026-08-17T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-17T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-18T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-18T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-19T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-19T15:30:00-05:00')) m(tipo, ts)
where p.apellidos = 'Duelo' and p.rol is distinct from 'admin';

-- Y LicGoceFichada además FICHA el miércoles 12, DENTRO de su licencia.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000c07', '00000000-0000-0000-0000-000000000c01', 'entrada',      '2026-08-12T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000c07', '00000000-0000-0000-0000-000000000c01', 'salida_final', '2026-08-12T15:30:00-05:00');

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;

-- ── El catálogo, que es de donde sale todo lo demás ─────────────────────────

select is((select paga from tipos_ausencia where codigo = 'duelo_familiar_directo'), true,
  'el duelo de familiar directo existe en el catálogo y paga');
select is((select requiere_aprobacion from tipos_ausencia where codigo = 'duelo_familiar_directo'), true,
  'y exige la firma de DO, que es la que convierte días en plata');
select is((select paga from tipos_ausencia where codigo = 'duelo'), false,
  'el duelo por cualquier otro familiar sigue sin pagar — es potestativo');
select isnt((select nombre from tipos_ausencia where codigo = 'duelo'), 'Duelo',
  'y su nombre dice cuál es, para que la elección no dependa de recordar la ley');

-- ── Lo que la 0314 viene a arreglar ─────────────────────────────────────────

select is((pg_temp.fila('DueloFirmado Duelo')->>'dias_licencia_con_goce')::int, 5,
  'el duelo de familiar directo aprobado cuenta sus cinco días (Ley 31602)');
select cmp_ok((pg_temp.fila('DueloFirmado Duelo')->>'monto_licencia_con_goce')::numeric, '>', 0::numeric,
  'y se paga — que es lo que la ley obliga y el sistema no hacía');
select is((pg_temp.fila('LicGoce Duelo')->>'dias_licencia_con_goce')::int, 5,
  'la licencia con goce también: llevaba meses en el desplegable sin pagar');

-- ── Sin la firma de DO no se paga. La regla de la 0306, desde el primer día ──

select is((pg_temp.fila('DueloSinFirma Duelo')->>'dias_licencia_con_goce')::int, 0,
  'sin aprobar, el duelo directo no cuenta ni un día — el registro solo no basta');
select is((pg_temp.fila('DueloSinFirma Duelo')->>'monto_licencia_con_goce')::numeric, 0.00,
  'sin aprobar, tampoco paga');

-- ── Y lo que el catálogo dice que NO paga, no paga ──────────────────────────

select is((pg_temp.fila('DueloOtro Duelo')->>'dias_licencia_con_goce')::int, 0,
  'el otro duelo, aun aprobado, no paga: el catálogo manda');
select is((pg_temp.fila('DueloOtro Duelo')->>'pago_base')::numeric,
          (pg_temp.fila('DuControl Duelo')->>'pago_base')::numeric - 0,
  'y su pago_base es el de quien faltó sin más — no se le regala nada');

-- ── LAS TRES QUE EVITAN PAGAR DOS VECES EL MISMO DÍA ────────────────────────

-- Es lo que más caro costaría romper: los tres tipos con regla propia quedan
-- fuera del lateral nuevo. Si uno se colara, su mes se pagaría dos veces.
select is((pg_temp.fila('DmControl Duelo')->>'dias_licencia_con_goce')::int, 0,
  'el descanso médico NO entra por la puerta nueva: ya lo paga `dmd`');
select cmp_ok((pg_temp.fila('DmControl Duelo')->>'monto_descanso_medico')::numeric, '>', 0::numeric,
  'y lo sigue pagando por la suya, intacto');
select is((pg_temp.fila('VacControl Duelo')->>'dias_licencia_con_goce')::int, 0,
  'las vacaciones tampoco: las paga `vacd`, y `vacaciones` es una vista sobre esta misma tabla');

-- El día FICHADO dentro de la licencia. La regla de la 0286, que costó
-- S/337,93 por semana solapada la vez que faltó.
select is((pg_temp.fila('LicGoceFichada Duelo')->>'dias_licencia_con_goce')::int, 4,
  'el día que fichó dentro de su licencia no se paga ADEMÁS como ausencia');

-- El domingo de dentro. La regla de la 0302: por días laborables, no calendario.
select is((pg_temp.fila('LicGoceDomingo Duelo')->>'dias_licencia_con_goce')::int, 6,
  'de siete días de calendario se pagan los seis que eran suyos: el domingo no');

select * from finish();
rollback;
