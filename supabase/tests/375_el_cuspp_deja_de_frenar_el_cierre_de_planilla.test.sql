-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 375_el_cuspp_deja_de_frenar_el_cierre_de_planilla.test.sql — 0476
-- ============================================================================
-- Regresión directa del freno que la 0476 retira: producción tenía, dentro de
-- `fn_planilla_congelar`, un cuarto freno (etiquetado "CAMBIO 0397" en su
-- comentario, pero SIN migración propia — se pegó directo en el SQL Editor,
-- ver docs/estado.md A.2.c.ter) que abortaba el cierre de «Planilla» entera
-- si a CUALQUIER persona afiliada a una AFP le faltaba el CUSPP.
--
-- Esta prueba no reconstruye ese freno para comprobar que ya no está: arma la
-- condición exacta que antes lo disparaba —una persona `planilla`, con
-- régimen de AFP, y sin ninguna fila en `datos_personales` (o sea, sin
-- CUSPP)— y confirma que `fn_planilla_congelar` la congela con normalidad.
-- Si alguien reintroduce ese freno, o algo parecido, esta prueba es la que
-- lo va a cazar.
--
-- `sueldo_fijo = true` evita tener que montar horario y marcajes: su pago no
-- depende de horas, así que aparece en `v_calc->'filas'` sin ese fixture —
-- mismo atajo que usa PenRxh en la prueba 259 para el mismo propósito.
-- ============================================================================
begin;
select plan(3);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000037500', 'ZZCUS', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000037501', 'CusAdmin', 'Lab',
        '00000000-0000-0000-0000-000000037500', 'admin', 'x',
        '00000000-0000-0000-0000-0000000375ff', '2024-01-01', 'planilla');
set session_replication_role = origin;

-- La persona cuyo CUSPP falta: afiliada a una AFP real (no 'onp', no
-- 'jubilada' — las dos que el freno viejo sí exceptuaba), y sin fila en
-- `datos_personales`, así que no hay ningún CUSPP que leer.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo, regimen_pension)
values ('00000000-0000-0000-0000-000000037502', 'CusSinFicha', 'Lab',
        '00000000-0000-0000-0000-000000037500', 'x', '2024-01-01', 'taller_produccion', 'planilla', true, 'integra_mixta');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000037502', 'colibri', 1500, '2024-01-01');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000003750a1', '2026-04-29', '2026-05-28', 'abierto');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000375ff', true);

-- Control previo: sin fila en `datos_personales`, el CUSPP es NULL — la misma
-- condición exacta que antes disparaba "Falta el CUSPP de: CusSinFicha".
select is(
  (select cuspp from datos_personales where persona_id = '00000000-0000-0000-0000-000000037502'),
  null,
  'CusSinFicha no tiene ficha, así que su CUSPP es NULL — la condición que antes frenaba');

select lives_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000003750a1', 'pago', null) $$,
  'Congelar Planilla ya no exige el CUSPP de quien está afiliado a una AFP');

select is(
  (select count(*)::int from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-0000003750a1'
      and persona_id = '00000000-0000-0000-0000-000000037502'),
  1,
  'Y de verdad la congela: queda su fila en la foto, no se saltó en silencio');

select * from finish();
rollback;
