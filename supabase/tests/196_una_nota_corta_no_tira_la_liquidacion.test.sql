-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 196_una_nota_corta_no_tira_la_liquidacion.test.sql — 0255
-- ============================================================================
-- LOS DOS DEFECTOS QUE VIGILA, medidos el 2026-08-14 contra el Postgres local:
--
--   (1) `fn_liquidacion_pagar` (0167) reutiliza la nota —campo LIBRE y OPCIONAL
--       de la pantalla— como `motivo` de la fila de auditoría, y esa tabla exige
--       3 caracteres. Una nota de 1 o 2 caracteres pasaba el `nullif`, llegaba
--       al insert y reventaba con SQLSTATE 23514 nombrando el constraint. Se
--       llega desde la pantalla: liquidaciones/page.tsx:139-141 manda
--       `p_nota: nota.trim() || null`. Escribir «ok» y pulsar «Marcar como
--       pagada» fallaba.
--
--   (2) La máscara `FM999999.00` escribe el cero como «.00». Una liquidación
--       legítima de S/0.00 EXISTE —es la razón de ser de la columna `anulada` de
--       la 0251— y su fila de auditoría quedaba ilegible: «S/.00 · version 1».
--
-- QUÉ DEFIENDE ESTE ARCHIVO
--
--   (A) Que las cuatro franjas de la nota funcionan: nula, 1 carácter, 2
--       caracteres y normal. La franja de 1-2 es la que rompía.
--   (B) Que arreglarlo NO PIERDE la nota. Se compone el motivo en vez de
--       sustituirlo, así que lo que alguien escribió sigue estando en los dos
--       sitios donde se va a buscar.
--   (C) Que NO se tocó lo que ya funcionaba — el control negativo, y pesa
--       igual: una nota normal sigue yendo tal cual a la auditoría, y sin nota
--       el texto por defecto sigue siendo el de siempre, con esas palabras.
--   (D) Que la 0251 sigue entera: el cero legítimo se distingue de una anulada,
--       se puede anular, y sus dos CHECK siguen en pie.
--
-- EL MONTAJE: dos personas cesadas en el mismo periodo.
--   ·196001 Notas Varias  — cuatro llamadas, una por franja de nota
--   ·196002 Cero Legitimo — sin salario y sin jornadas: su liquidación es S/0.00
--                           de verdad, y NO es una anulación
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000196000', 'ZZ196', 'Sede de laboratorio 196', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values
  ('00000000-0000-0000-0000-000000196099', 'Admin196', 'Laboratorio',
   '00000000-0000-0000-0000-000000196000', 'admin', 'test-hash',
   '00000000-0000-0000-0000-000000196098', '2020-01-01'),
  ('00000000-0000-0000-0000-000000196097', 'Curiosa196', 'Laboratorio',
   '00000000-0000-0000-0000-000000196000', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000196096', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000196098', true);

-- Sin feriados de por medio: lo que se mide son textos y un cero, y un feriado
-- dentro del rango solo movería cifras que acá no se comparan.
delete from feriados where fecha between '2026-07-01' and '2026-09-30';

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000196001', 'Notas', 'Varias',   '00000000-0000-0000-0000-000000196000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000196002', 'Cero',  'Legitimo', '00000000-0000-0000-0000-000000196000', 'test-hash', '2026-08-01', 'planilla');

-- Solo Notas Varias cobra. Cero Legitimo se queda SIN asignación de salario y
-- SIN jornadas a propósito: así su liquidación sale en cero de verdad.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000196001', 'cayla', 1500.00, '2024-01-02');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000196101', '2026-07-29', '2026-08-28', 'abierto');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000196001', d::date, 6.5, 'cerrada'
from generate_series('2026-08-01'::date, '2026-08-10'::date, interval '1 day') d;

-- El cese se pone a mano, como en la 185, la 192 y la 194: `fn_cesar_persona` se
-- niega a cesar dentro de un periodo ya pagado (0176:285-291).
update personas set estado='inactivo', fecha_cese='2026-08-10'
where id in ('00000000-0000-0000-0000-000000196001','00000000-0000-0000-0000-000000196002');


-- ── § 1 · LA FRANJA QUE ROMPÍA: notas de 1 y 2 caracteres ───────────────────
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000196001', 'ok') $$,
  '1 · una nota de DOS caracteres ya no tira la operación');

select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000196001', 'o') $$,
  '2 · una nota de UN carácter tampoco');


-- ── § 2 · Y NO SE PIERDE LO QUE SE ESCRIBIÓ ─────────────────────────────────
select is(
  (select nota from liquidacion_pagada
    where persona_id='00000000-0000-0000-0000-000000196001' and version=1),
  'ok',
  '3 · la nota corta sigue guardada ENTERA en liquidacion_pagada.nota');

select matches(
  (select motivo from correcciones_auditoria
    where persona_id='00000000-0000-0000-0000-000000196001'
      and valor_nuevo like '%version 1'),
  'nota: ok$',
  '4 · y el motivo de auditoría la lleva dentro: se compone, no se sustituye');


-- ── § 3 · LA INVARIANTE QUE SE VIOLABA ──────────────────────────────────────
-- El CHECK real de la tabla es `length(trim(motivo)) >= 3`. Esto lo comprueba
-- sobre TODAS las filas que escribió esta prueba, no sobre una.
select ok(
  (select bool_and(length(trim(motivo)) >= 3) from correcciones_auditoria
    where persona_id='00000000-0000-0000-0000-000000196001'),
  '5 · ningún motivo escrito baja de 3 caracteres, que es lo que exige el CHECK');


-- ── § 4 · CONTROL NEGATIVO · lo que ya funcionaba sigue igual ───────────────
-- Pesa lo mismo que lo de arriba: un arreglo que cambiara estos dos textos
-- estaría reescribiendo la auditoría de todas las liquidaciones normales.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000196001', 'transferencia BCP') $$,
  '6 · una nota normal se sigue aceptando');

-- Se busca por el TEXTO y no por el número de versión a propósito: si un día
-- alguien rompe las notas cortas otra vez, las versiones se corren y una
-- aserción atada a «version 3» fallaría de rebote, fingiendo vigilar algo que no
-- vigila. Este control tiene que SOBREVIVIR a ese fallo — es lo que lo hace un
-- control.
select ok(
  exists (select 1 from correcciones_auditoria
           where persona_id='00000000-0000-0000-0000-000000196001'
             and motivo = 'transferencia BCP'),
  '7 · y va TAL CUAL a la auditoría: sin prefijo, sin componer nada');

select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000196001', null) $$,
  '8 · sin nota se sigue pudiendo marcar como pagada');

select ok(
  exists (select 1 from correcciones_auditoria
           where persona_id='00000000-0000-0000-0000-000000196001'
             and motivo = 'Liquidación marcada como pagada'),
  '9 · y el texto por defecto sigue siendo el de siempre, con esas palabras');


-- ── § 5 · EL CERO LEGÍTIMO SE ESCRIBE LEGIBLE ───────────────────────────────
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000196002', 'sin salario ni jornadas') $$,
  '10 · una liquidación legítima de S/0.00 se puede congelar');

select is(
  (select valor_nuevo from correcciones_auditoria
    where persona_id='00000000-0000-0000-0000-000000196002'),
  'S/0.00 · version 1',
  '11 · y la auditoría la escribe «S/0.00», no «S/.00» como con la máscara vieja');


-- ── § 6 · LA 0251 SIGUE ENTERA ──────────────────────────────────────────────
-- El cero legítimo y una anulación son dos filas en 0.00 que solo la columna
-- distingue. Esa es la razón de ser de la 0251 y esta migración no la toca.
select is(
  (select anulada from liquidacion_pagada
    where persona_id='00000000-0000-0000-0000-000000196002' and version=1),
  false,
  '12 · ese cero NO es una anulación: la columna las sigue distinguiendo');

select lives_ok(
  $$ select fn_liquidacion_anular('00000000-0000-0000-0000-000000196002',
       'Marcada por error: nunca hubo nada que pagar.') $$,
  '13 · y sobre ella se puede anular, como antes de esta migración');


-- ── § 7 · EL GUARD NO SE DEBILITÓ ───────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000196096', true);
select throws_like(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000196001', 'ok') $$,
  '%Solo un administrador o líder%',
  '14 · una integrante sigue sin poder marcar una liquidación como pagada');

select * from finish();
rollback;
