-- ============================================================================
-- 133_la_liquidacion_pagada_no_cambia_sola.test.sql
-- ============================================================================
-- Por qué esto importa más acá que en la planilla:
--
--   Un error en la planilla lo reclama quien lo cobra — son 22 personas mirando
--   su boleta cada mes. Un error en una liquidación no lo reclama nadie: la
--   persona ya no está, no tiene cuenta, y en muchos casos ni sabe cómo se
--   calculó. El único control posible es que la cifra no se mueva sola.
--
--   Y se mueve con facilidad. Basta que alguien anote, dos semanas después, un
--   depósito de CTS que faltaba en el libro: el mismo `fn_liquidacion` devuelve
--   otra cosa. Sin foto no habría forma de saber cuál de las dos se transfirió.
--
-- Este archivo fija las tres mitades:
--   · congelar guarda EXACTAMENTE lo que la función calculaba en ese momento;
--   · después, aunque el cálculo cambie, la foto no se mueve;
--   · y la diferencia se NOMBRA, concepto por concepto, en vez de esconderse.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000fa00', 'ZZFOT', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000fa01', 'AdminFoto', 'Laboratorio',
        '00000000-0000-0000-0000-00000000fa00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000fa09', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fa09', true);

delete from feriados where fecha between '2026-06-01' and '2026-06-30';

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000faa1', 'FotoAna', 'Laboratorio',
        '00000000-0000-0000-0000-00000000fa00', 'test-hash', '2024-01-02', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000faa1', 'cayla', 1500.00, '2024-01-02');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000000faaa', '2026-06-01', '2026-06-30', 'abierto');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000faa1', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-15'::date, interval '1 day') d;

update personas set estado = 'inactivo', fecha_cese = '2026-06-15'
 where id = '00000000-0000-0000-0000-00000000faa1';


-- ── Antes de congelar ──────────────────────────────────────────────────────
select is(
  (select count(*)::int from fn_liquidaciones_pendientes()
    where persona_id = '00000000-0000-0000-0000-00000000faa1' and not pagada),
  1,
  'PENDIENTE · aparece en la lista sin que nadie la agregue: sale de su fecha de cese');

select is(
  (select count(*)::int from fn_liquidacion_diferencias('00000000-0000-0000-0000-00000000faa1')),
  0,
  'SIN FOTO · comparar sin haber congelado no devuelve nada, en vez de reventar');


-- ── Congelar ───────────────────────────────────────────────────────────────
create temp table _antes as
  select (fn_liquidacion('00000000-0000-0000-0000-00000000faa1', '2026-06-15')->>'total')::numeric as total;

select is(
  (fn_liquidacion_pagar('00000000-0000-0000-0000-00000000faa1', 'transferencia BCP')->>'version')::int,
  1,
  'CONGELAR · la primera foto es la versión 1');

select is(
  (select total from liquidacion_pagada where persona_id = '00000000-0000-0000-0000-00000000faa1'),
  (select total from _antes),
  'CONGELAR · guarda EXACTAMENTE lo que la función calculaba en ese momento');

select ok(
  (select detalle ? 'cts_trunca' and detalle ? 'periodo'
     from liquidacion_pagada where persona_id = '00000000-0000-0000-0000-00000000faa1'),
  'CONGELAR · y guarda el desglose entero, para poder reimprimir la hoja tal cual');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-00000000faa1'
      and campo_modificado = 'liquidacion_pagada'),
  1,
  'CONGELAR · queda rastro de quién la marcó como pagada y con qué nota');


-- ── La foto no se toca ─────────────────────────────────────────────────────
select throws_like(
  $$ update liquidacion_pagada set total = 1 where persona_id = '00000000-0000-0000-0000-00000000faa1' $$,
  '%no se modifica ni se borra%',
  'INMUTABLE · ni el propio DO puede editar la cifra con la que se pagó');

select throws_like(
  $$ delete from liquidacion_pagada where persona_id = '00000000-0000-0000-0000-00000000faa1' $$,
  '%no se modifica ni se borra%',
  'INMUTABLE · ni borrarla');


-- ── Y cuando el cálculo cambia por debajo ──────────────────────────────────
-- El caso real: dos semanas después alguien anota en el libro un depósito de CTS
-- que faltaba. La liquidación recalculada baja; la que se transfirió, no.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
values ('00000000-0000-0000-0000-00000000faa1', 'cts_nov', 2026, 150.00, '2026-06-01', 'plame');

select is(
  (select total from liquidacion_pagada where persona_id = '00000000-0000-0000-0000-00000000faa1'),
  (select total from _antes),
  'DESPUÉS · el cálculo cambió, pero la foto sigue diciendo lo que se pagó');

select is(
  (select diferencia from fn_liquidacion_diferencias('00000000-0000-0000-0000-00000000faa1')
    where concepto = 'CTS trunca'),
  -150.00::numeric,
  'DESPUÉS · y la diferencia se NOMBRA: S/150 menos en la CTS, no un «no cuadra» a secas');

select ok(
  (select descuadra from fn_liquidaciones_pendientes()
    where persona_id = '00000000-0000-0000-0000-00000000faa1'),
  'DESPUÉS · la lista lo marca, para que nadie tenga que ir a buscarlo');

select * from finish();
rollback;
