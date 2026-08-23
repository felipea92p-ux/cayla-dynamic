-- ============================================================================
-- 114_la_educacion_con_todas_sus_reglas.test.sql
-- ============================================================================
-- Las nueve reglas que la 0149 bajó a la base, cada una con el caso concreto
-- que la hizo falta:
--
--   · Ana gana rango aurora (techo S/360) y estudia un diplomado de S/200 al
--     mes. Cobra S/150 — el 75% del papel — y no S/360, porque el curso no
--     cuesta más. Si el curso costara S/600, cobraría S/360 y no S/450: manda
--     el techo.
--   · Ana además tiene un hijo en el colegio. Antes de la 0149 esas dos filas
--     podían sumar S/340 bajo un techo de S/180, porque el techo se medía fila
--     por fila. Ahora se mide sobre la suma.
--   · Y si el comprobante es del hijo, tiene que decir de qué hijo: un papel a
--     nombre de un tercero sin vínculo escrito es el que no sostiene nada el
--     día de una fiscalización.
--
-- Todo ocurre en begin/rollback y en fechas de 2027, lejos de cualquier dato
-- real: al terminar no queda nada en la base.
-- ============================================================================
begin;
select plan(22);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ed00', 'ZZEDU', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ed01', 'EduDO', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ed00', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-00000000ed09', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-00000000ed02', 'EduAna',  'Laboratorio', '00000000-0000-0000-0000-00000000ed00', 'test-hash', '2025-01-02'),
  ('00000000-0000-0000-0000-00000000ed03', 'EduCesa', 'Laboratorio', '00000000-0000-0000-0000-00000000ed00', 'test-hash', '2025-01-02');

-- Rango aurora: techo S/360 según la escala de la 0132.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000000ed02', 'aurora', 1500, '2025-01-02'),
  ('00000000-0000-0000-0000-00000000ed03', 'aurora', 1500, '2025-01-02');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ed09', true);


-- ── 1 · El monto sale del papel y del rango, no del teclado ────────────────
-- ⇩ CAMBIO 0281 ⇩ La función pide las fechas del tramo: desde la 0281 el techo
-- se reparte entre las asignaciones que se solapan, y sin fechas no se puede
-- saber cuánto queda libre. Acá Ana todavía no tiene ninguna, así que el saldo
-- es el techo entero y las dos cifras son las mismas de siempre.
select is(fn_educacion_monto('00000000-0000-0000-0000-00000000ed02', 200::numeric,
                             '2027-03-01'::date, '2027-12-31'::date), 150.00::numeric,
  'MONTO · curso de S/200 → S/150 (el 75%, por debajo del techo porque no cuesta más)');

select is(fn_educacion_monto('00000000-0000-0000-0000-00000000ed02', 600::numeric,
                             '2027-03-01'::date, '2027-12-31'::date), 360.00::numeric,
  'MONTO · curso de S/600 → S/360 (el 75% daría 450, pero manda el techo del rango)');


-- ── 2 · Un alta normal ──────────────────────────────────────────────────────
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ed02'::uuid, 'Instituto de laboratorio', 200::numeric,
    'trabajador', '2027-03-01'::date, '2027-12-31'::date,
    null, 'educacion/x/y.pdf', null, null, null) $$,
  'ALTA · se registra con institución, costo, beneficiario y fecha de fin');

select is((select monto from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-00000000ed02'),
  150.00::numeric, 'ALTA · guardó S/150, el monto calculado — nadie lo tecleó');

select is((select cobertura_pct from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-00000000ed02'),
  75::numeric, 'ALTA · la cobertura quedó en 75, que es la única permitida');

select is((select count(*)::int from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-00000000ed02' and campo_modificado = 'educacion_alta'),
  1, 'ALTA · dejó rastro en correcciones_auditoria');


-- ── 3 · La fecha de fin es obligatoria ──────────────────────────────────────
select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ed03'::uuid, 'Instituto de laboratorio', 200::numeric,
    'trabajador', '2027-03-01'::date, null,
    null, null, null, null, null) $$,
  '%hasta cuándo%',
  'VIGENCIA · sin fecha de fin no se registra: una matrícula cubre un ciclo, no la eternidad');


-- ── 4 · Un comprobante de un hijo dice de qué hijo ─────────────────────────
select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ed03'::uuid, 'Colegio de laboratorio', 100::numeric,
    'hijo', '2027-03-01'::date, '2027-12-31'::date,
    null, null, null, null, null) $$,
  '%a nombre de quién%',
  'HIJO · sin el nombre del beneficiario no se registra');

select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ed03'::uuid, 'Colegio de laboratorio', 100::numeric,
    'hijo', '2027-03-01'::date, '2027-12-31'::date,
    'Lucas de Laboratorio', null, null, null, null) $$,
  'HIJO · con el nombre sí entra');


-- ── 5 · El techo se mide sobre la SUMA, y desde la 0281 se REPARTE ─────────
-- Ana ya tiene S/150 vigentes de un techo de S/360. Un segundo curso de S/400
-- daría S/300 más, y 150 + 300 = 450 > 360.
--
-- Las tres épocas de esta línea, que es la historia de esta regla:
--   · antes de la 0149 entraba entero, porque cada fila miraba solo su monto;
--   · entre la 0149 y la 0281 rebotaba entera — y como el monto no se teclea,
--     no había NINGUNA forma de registrar ese comprobante, ni por lo que cabía;
--   · desde la 0281 entra por los S/210 que quedaban libres bajo el techo.
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ed02'::uuid, 'Colegio del hijo', 400::numeric,
    'hijo', '2027-06-01'::date, '2027-12-31'::date,
    'Lucia de Laboratorio', 'educacion/x/z.pdf', null, null, null) $$,
  'TECHO · el segundo comprobante entra por lo que quede del techo');

select is((select monto from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-00000000ed02' and beneficiario = 'hijo'),
  210.00::numeric,
  'TECHO · y entra por S/210: el 75% daría S/300, pero el techo solo dejaba 210');

select is((select sum(monto) from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-00000000ed02'),
  360.00::numeric,
  'TECHO · las dos juntas suman exactamente el techo del rango, ni un céntimo más');

select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ed02'::uuid, 'Tercer instituto', 200::numeric,
    'trabajador', '2027-06-01'::date, '2027-12-31'::date,
    null, null, null, null, null) $$,
  '%No queda techo libre%',
  'TECHO · y cuando ya no queda nada que repartir, se rechaza diciendo por qué');

select is((select count(*)::int from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-00000000ed02'),
  2, 'TECHO · Ana termina con sus dos asignaciones vivas');


-- ── 6 · Corregir exige motivo ───────────────────────────────────────────────
select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ed03'::uuid, 'Colegio corregido', 100::numeric,
    'hijo', '2027-03-01'::date, '2027-12-31'::date, 'Lucas de Laboratorio',
    null, null,
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-00000000ed03'),
    null) $$,
  '%por qué se corrige%',
  'CORREGIR · sin motivo no se corrige: esto mueve lo que cobra una persona');


-- ── 7 · Corregir lo que NO mueve plata se hace en la misma fila ────────────
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ed03'::uuid, 'Colegio con el nombre bien', 100::numeric,
    'hijo', '2027-03-01'::date, '2027-12-31'::date, 'Lucas de Laboratorio',
    null, null,
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-00000000ed03'),
    'estaba mal escrito el nombre del colegio') $$,
  'CORREGIR · arreglar la institución se permite');

select is((select count(*)::int from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-00000000ed03'),
  1, 'CORREGIR · y NO abrió vigencia nueva: no cambió un céntimo');

select is((select count(*)::int from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-00000000ed03'
              and campo_modificado = 'educacion_datos'
              and motivo = 'estaba mal escrito el nombre del colegio'),
  1, 'CORREGIR · con su motivo textual en la auditoría');


-- ── 8 · El candado del periodo pagado ───────────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000000edaa', '2027-01-01', '2027-01-28', 'pagado');

select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ed03'::uuid, 'Instituto tardio', 200::numeric,
    'trabajador', '2027-01-10'::date, '2027-12-31'::date,
    null, null, null, null, null) $$,
  '%ya PAGADO%',
  'PAGADO · no se registra una vigencia que empieza dentro de un periodo pagado');


-- ── 9 · Quien cesa deja de devengar el día que cesa ────────────────────────
select is((select vigente_hasta from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-00000000ed03'),
  '2027-12-31'::date, 'CESE · antes del cese la asignación llega hasta fin de año');

update personas set estado = 'inactivo', fecha_cese = '2027-05-20'
 where id = '00000000-0000-0000-0000-00000000ed03';

select is((select vigente_hasta from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-00000000ed03'),
  '2027-05-20'::date,
  'CESE · al cesar se cierra sola en la fecha de cese, sin que nadie se acuerde');

select is((select count(*)::int from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-00000000ed03'),
  1, 'CESE · y la fila NO se borra: sostiene lo que ya se pagó');

select * from finish();
rollback;
