-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 306_el_tablero_desempata_contratos_del_mismo_instante.test.sql — 0386
-- ============================================================================
-- `contratos_generados.generado_at` es `default now()`, y `now()` dentro de
-- una misma transacción vale LO MISMO para todas las filas. Hasta la 0386, el
-- CTE `ultimo` de `fn_contratos_tablero` ordenaba solo por `generado_at desc`:
-- con dos contratos empatados, cuál ganaba lo decidía el orden físico de la
-- tabla, no el negocio.
--
-- Esto no rompía producción —cada contrato entra por su propia llamada RPC, o
-- sea su propia transacción— pero sí volvía FLAKY la prueba 274, que como toda
-- prueba pgTAP corre entera dentro de una transacción: el 2026-09-06 pasó en la
-- suite completa y falló corriéndola sola, sin que la base cambiara.
--
-- Esta prueba fija el criterio, para que el desempate no se pueda quitar sin
-- que algo se ponga rojo: manda el que EMPIEZA después, y la respuesta no
-- depende del orden en que se insertaron las filas.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000306000', 'ZZ306', 'Sede de laboratorio 306', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000306aa0', 'Jefa', 'Lab306',
        '00000000-0000-0000-0000-000000306000', 'admin', 'h',
        '00000000-0000-0000-0000-000000306aff', '2025-01-02');
set session_replication_role = origin;

do $sesion$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000306aff', true);
end $sesion$;

-- Dos personas idénticas salvo en el ORDEN en que se insertan sus dos
-- contratos. Si el desempate funciona, las dos tienen que dar la misma
-- respuesta; si volviera a decidirlo el orden físico, darían distinta.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000306001', 'Ana', 'PrimeroElViejo306',
        '00000000-0000-0000-0000-000000306000', 'h', '2026-01-05'),
       ('00000000-0000-0000-0000-000000306002', 'Bea', 'PrimeroElNuevo306',
        '00000000-0000-0000-0000-000000306000', 'h', '2026-01-05');

-- `generado_at` explícito e IDÉNTICO en los cuatro: es exactamente lo que
-- produce `now()` dentro de una transacción, escrito a la vista para que la
-- prueba diga qué está midiendo.
-- Ana: primero el viejo, después el nuevo.
insert into contratos_generados
  (id, persona_id, tipo, cargo, sede_id, remuneracion_mensual,
   fecha_inicio, fecha_fin, documento_html, generado_por, generado_at,
   fecha_firma, storage_path, registrado_por)
values
  ('00000000-0000-0000-0000-0000003060a1', '00000000-0000-0000-0000-000000306001',
   'nuevo', 'Asesora', '00000000-0000-0000-0000-000000306000', 1130,
   '2026-01-05', '2026-07-05', '<p>viejo de Ana</p>',
   '00000000-0000-0000-0000-000000306aa0', '2026-09-01 10:00:00+00',
   '2026-01-06', 'contratos/00000000-0000-0000-0000-0000003060a1.pdf', '00000000-0000-0000-0000-000000306aa0'),
  ('00000000-0000-0000-0000-0000003060a2', '00000000-0000-0000-0000-000000306001',
   'renovacion', 'Asesora', '00000000-0000-0000-0000-000000306000', 1500,
   '2026-07-06', '2027-07-05', '<p>nuevo de Ana</p>',
   '00000000-0000-0000-0000-000000306aa0', '2026-09-01 10:00:00+00',
   '2026-07-06', 'contratos/00000000-0000-0000-0000-0000003060a2.pdf', '00000000-0000-0000-0000-000000306aa0');

-- Bea: al revés — primero el nuevo, después el viejo.
insert into contratos_generados
  (id, persona_id, tipo, cargo, sede_id, remuneracion_mensual,
   fecha_inicio, fecha_fin, documento_html, generado_por, generado_at,
   fecha_firma, storage_path, registrado_por)
values
  ('00000000-0000-0000-0000-0000003060b2', '00000000-0000-0000-0000-000000306002',
   'renovacion', 'Asesora', '00000000-0000-0000-0000-000000306000', 1500,
   '2026-07-06', '2027-07-05', '<p>nuevo de Bea</p>',
   '00000000-0000-0000-0000-000000306aa0', '2026-09-01 10:00:00+00',
   '2026-07-06', 'contratos/00000000-0000-0000-0000-0000003060b2.pdf', '00000000-0000-0000-0000-000000306aa0'),
  ('00000000-0000-0000-0000-0000003060b1', '00000000-0000-0000-0000-000000306002',
   'nuevo', 'Asesora', '00000000-0000-0000-0000-000000306000', 1130,
   '2026-01-05', '2026-07-05', '<p>viejo de Bea</p>',
   '00000000-0000-0000-0000-000000306aa0', '2026-09-01 10:00:00+00',
   '2026-01-06', 'contratos/00000000-0000-0000-0000-0000003060b1.pdf', '00000000-0000-0000-0000-000000306aa0');

-- ── 1 y 2 · Manda el que empieza después, insertado primero o último ───────
select is(
  (select contrato_id from fn_contratos_tablero()
    where persona_id = '00000000-0000-0000-0000-000000306001'),
  '00000000-0000-0000-0000-0000003060a2'::uuid,
  'empatados en generado_at, manda el que EMPIEZA después — aunque se insertó al final');

select is(
  (select contrato_id from fn_contratos_tablero()
    where persona_id = '00000000-0000-0000-0000-000000306002'),
  '00000000-0000-0000-0000-0000003060b2'::uuid,
  'y la respuesta no cambia si ese mismo contrato se insertó primero: el orden físico no decide');

-- ── 3 · Un indefinido no lo desplaza un plazo fijo que empieza el mismo día ─
-- `fecha_fin desc` con NULL: en Postgres `desc` pone los NULL PRIMERO, así que
-- a igualdad de fecha_inicio gana el indefinido. Es lo correcto — un contrato
-- sin término manda sobre uno a plazo fijo del mismo día.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000306003', 'Cleo', 'MismoDia306',
        '00000000-0000-0000-0000-000000306000', 'h', '2026-01-05');

insert into contratos_generados
  (id, persona_id, tipo, cargo, sede_id, remuneracion_mensual,
   fecha_inicio, fecha_fin, documento_html, generado_por, generado_at,
   fecha_firma, storage_path, registrado_por)
-- El plazo fijo se inserta PRIMERO a propósito: así, sin el desempate, el
-- orden físico le daría el mando a él y esta aserción falla. Una aserción que
-- acierta por casualidad no guarda nada.
values
  ('00000000-0000-0000-0000-0000003060c2', '00000000-0000-0000-0000-000000306003',
   'nuevo', 'Asesora', '00000000-0000-0000-0000-000000306000', 1130,
   '2026-07-06', '2027-07-05', '<p>plazo fijo de Cleo</p>',
   '00000000-0000-0000-0000-000000306aa0', '2026-09-01 10:00:00+00',
   '2026-07-06', 'contratos/00000000-0000-0000-0000-0000003060c2.pdf', '00000000-0000-0000-0000-000000306aa0'),
  ('00000000-0000-0000-0000-0000003060c1', '00000000-0000-0000-0000-000000306003',
   'indefinido', 'Asesora', '00000000-0000-0000-0000-000000306000', 1500,
   '2026-07-06', null, '<p>indefinido de Cleo</p>',
   '00000000-0000-0000-0000-000000306aa0', '2026-09-01 10:00:00+00',
   '2026-07-06', 'contratos/00000000-0000-0000-0000-0000003060c1.pdf', '00000000-0000-0000-0000-000000306aa0');

select is(
  (select tipo from fn_contratos_tablero()
    where persona_id = '00000000-0000-0000-0000-000000306003'),
  'indefinido',
  'a igualdad de fecha de inicio manda el indefinido: `fecha_fin desc` pone los NULL primero');

-- ── 4 · Un contrato anulado sigue sin contar, empate o no ─────────────────
update contratos_generados
   set anulado_at = now(), anulado_por = '00000000-0000-0000-0000-000000306aa0',
       anulado_motivo = 'Prueba 306: anulado a mano para comprobar el filtro'
 where id = '00000000-0000-0000-0000-0000003060a2';

select is(
  (select contrato_id from fn_contratos_tablero()
    where persona_id = '00000000-0000-0000-0000-000000306001'),
  '00000000-0000-0000-0000-0000003060a1'::uuid,
  'anular el que mandaba devuelve el mando al otro — el desempate no se salta el filtro de anulados');

select * from finish();
rollback;
