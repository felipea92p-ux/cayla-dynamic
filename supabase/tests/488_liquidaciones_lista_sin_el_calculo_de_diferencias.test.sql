-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA (pgTAP, solo en el Postgres local): `npx supabase test db`.
-- ============================================================================
-- 488 — fn_liquidaciones_lista (0598)
-- ============================================================================
-- Defiende que la lista de /admin/liquidaciones sigue diciendo lo mismo que
-- fn_liquidaciones_pendientes en las columnas que comparten —total, pagada,
-- vencido, orden— sin calcular diferencias, y que no se abre a quien no es
-- admin ni líder.
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000fb00', 'ZZLST', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000fb01', 'AdminLista', 'Laboratorio',
        '00000000-0000-0000-0000-00000000fb00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000fb09', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fb09', true);

delete from feriados where fecha between '2026-06-01' and '2026-06-30';

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000fba1', 'ListaAna', 'Laboratorio',
        '00000000-0000-0000-0000-00000000fb00', 'test-hash', '2024-01-02', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000fba1', 'cayla', 1500.00, '2024-01-02');
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000000fbaa', '2026-06-01', '2026-06-30', 'abierto');
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000fba1', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-15'::date, interval '1 day') d;
update personas set estado = 'inactivo', fecha_cese = '2026-06-15'
 where id = '00000000-0000-0000-0000-00000000fba1';

select is(
  (select count(*)::int from fn_liquidaciones_lista()
    where persona_id = '00000000-0000-0000-0000-00000000fba1' and not pagada and vencido),
  1, 'PENDIENTE · una cesada sin pagar aparece, vencida');

select is(
  (select total from fn_liquidaciones_lista() where persona_id = '00000000-0000-0000-0000-00000000fba1'),
  (select total from fn_liquidaciones_pendientes() where persona_id = '00000000-0000-0000-0000-00000000fba1'),
  'IGUAL · el total pendiente es el mismo que el de la función de siempre');

create temp table _antes as
  select (fn_liquidacion('00000000-0000-0000-0000-00000000fba1', '2026-06-15')->>'total')::numeric as total;
select fn_liquidacion_pagar('00000000-0000-0000-0000-00000000fba1', 'transferencia');

select ok(
  (select pagada and not vencido from fn_liquidaciones_lista()
    where persona_id = '00000000-0000-0000-0000-00000000fba1'),
  'PAGADA · tras congelar sale pagada y ya no vencida');

select is(
  (select total from fn_liquidaciones_lista() where persona_id = '00000000-0000-0000-0000-00000000fba1'),
  (select round(total, 2) from _antes),
  'PAGADA · el total es el de la foto congelada');

-- Cambia el cálculo por debajo: la foto manda, la lista no se mueve.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
values ('00000000-0000-0000-0000-00000000fba1', 'cts_nov', 2026, 150.00, '2026-06-01', 'plame');
select is(
  (select total from fn_liquidaciones_lista() where persona_id = '00000000-0000-0000-0000-00000000fba1'),
  (select round(total, 2) from _antes),
  'FOTO · aunque el cálculo cambie, la lista dice lo que se pagó');

select is(
  (select count(*)::int from pg_proc p, unnest(p.proargnames) n
    where p.proname = 'fn_liquidaciones_lista' and n like 'descuadra%'),
  0, 'LIVIANA · no devuelve descuadra ni descuadra_real: es lo que costaba el tiempo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
select is((select count(*)::int from fn_liquidaciones_lista()), 0,
  'PERMISO · quien no es admin ni líder recibe cero filas');

select * from finish();
rollback;
