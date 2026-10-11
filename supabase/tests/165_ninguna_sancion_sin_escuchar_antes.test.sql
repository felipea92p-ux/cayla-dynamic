-- ============================================================================
-- 165_ninguna_sancion_sin_escuchar_antes.test.sql
-- ============================================================================
-- Defiende la 0212, que existe por una razón concreta: el artículo 55.2 del
-- Reglamento dice que la omisión del descargo previo **invalida** la sanción.
-- Una sanción inválida no se nota al firmarla. Se nota el día que alguien la
-- discute, y para entonces el documento ya está en el legajo, ya contó como
-- antecedente y ya sirvió de escalón para la siguiente.
--
-- POR QUÉ EL PLAZO SE PRUEBA EN DÍAS HÁBILES
--   El Reglamento dice «no menor de dos (2) días hábiles». Contarlos corridos
--   le daría a quien recibe los cargos un viernes el sábado y el domingo —dos
--   días en los que no puede reunir nada ni pedir ayuda— y el plazo real sería
--   de cero. Por eso la prueba parte de un viernes: es el caso que distingue
--   una implementación correcta de una que suma días a secas.
--
-- POR QUÉ SE PRUEBA CON EL ROL `authenticated`
--   Misma razón que la 163: las pruebas que corren como dueño de la base no
--   ven un permiso que falta, y ese fallo no da error al aplicar la migración
--   — da una pantalla que no hace nada.
--
-- POR QUÉ SE VACÍA LA SEMANA DE FERIADOS ANTES DE MEDIR
--   Las dos primeras aserciones cuentan días hábiles desde «el viernes de esta
--   semana», y `fn_sumar_dias_habiles` salta los feriados de `feriados`, que es
--   el calendario real sembrado hasta 2032. Con el calendario real puesto, la
--   prueba dependía de qué semana del año la corriera el CI: si el lunes o el
--   martes siguientes eran feriado, el plazo vencía el miércoles o el jueves
--   y la aserción 1 fallaba sin que nada estuviera roto.
--
--   Medido el 2026-10-11 falseando `fn_hoy_lima()` día por día entre
--   2026-01-12 y 2032-12-31 (2 546 fechas): fallaba en 280 (11 %), repartidas
--   en 33 semanas — por ejemplo la del 22-jun-2026 (lunes 29-jun, San Pedro y
--   San Pablo), la del 20-jul (martes 28 y miércoles 29, Fiestas Patrias) y la
--   del 30-nov (martes 8 y miércoles 9 de diciembre). Se repite todos los años.
--   Y no solo la aserción 1: en las semanas con DOS feriados seguidos también
--   fallaba la 2.
--
--   Lo que se prueba aquí es la REGLA —el plazo salta el fin de semana, y
--   salta un feriado que se declara—, no el calendario de Perú, así que la
--   semana que se mide se deja sin feriados y el único que hay es el que la
--   propia prueba inserta. Es el mismo aislamiento que usan las pruebas 10,
--   115, 125 y 130.
-- ============================================================================
begin;
select plan(10);

-- Desde la 0267, exigir el descargo previo es una política de la empresa y su
-- valor de fábrica es `false` (Gerencia General, 17-08-2026). Este archivo fija
-- cómo se comporta la base CON la política activa, así que la declara: si no,
-- todas sus afirmaciones se caerían por el motivo equivocado —la política, no
-- un defecto— y esa distinción es justo la que hay que poder ver.
update configuracion set valor = 'true'::jsonb where clave = 'disciplina_descargo_previo';

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000e300', 'ZZDES', 'Sede de laboratorio', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values ('ee000000-0000-0000-0000-0000000000e1',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'admin.des@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol,
                      auth_user_id, tipo_vinculo, estado)
values ('00000000-0000-0000-0000-00000000e301', 'DesAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000e300', 'x', 'admin',
        'ee000000-0000-0000-0000-0000000000e1', 'planilla', 'activo'),
       ('00000000-0000-0000-0000-00000000e302', 'DesIntegrante', 'Laboratorio',
        '00000000-0000-0000-0000-00000000e300', 'x', 'integrante',
        null, 'planilla', 'activo');
set session_replication_role = origin;

-- ── La semana que se mide, sin feriados ─────────────────────────────────────
-- Del viernes de esta semana al viernes siguiente: todo lo que
-- `fn_sumar_dias_habiles` puede leer al contar dos días hábiles desde ese
-- viernes, incluso con el feriado de laboratorio de abajo. Se borra dentro de
-- la burbuja; el rollback devuelve el calendario real.
delete from feriados
 where fecha between (date_trunc('week', fn_hoy_lima())::date + 4)
                 and (date_trunc('week', fn_hoy_lima())::date + 11);

-- ── 1 · El plazo salta el fin de semana ─────────────────────────────────────
-- Desde un viernes al mediodía de Lima, dos días hábiles caen en MARTES.
select is(
  extract(dow from (fn_sumar_dias_habiles(
    ((date_trunc('week', fn_hoy_lima())::date + 4) + time '12:00') at time zone 'America/Lima', 2)
    at time zone 'America/Lima')::date)::int,
  2,
  'Dos días hábiles desde un viernes vencen el martes, no el domingo');

-- ── 2 · Y salta los feriados ────────────────────────────────────────────────
-- Se declara feriado el lunes siguiente: el plazo debe correrse un día más.
-- Sin `on conflict`: la semana se vació arriba, así que este insert no puede
-- chocar. Si alguien quita ese delete, la prueba revienta aquí; con el
-- `do nothing` de antes, un feriado real en ese lunes hacía que el insert no
-- hiciera nada y la aserción pasara por el feriado real, no por el declarado.
insert into feriados (fecha, nombre)
values ((date_trunc('week', fn_hoy_lima())::date + 7), 'Feriado de laboratorio');

select is(
  extract(dow from (fn_sumar_dias_habiles(
    ((date_trunc('week', fn_hoy_lima())::date + 4) + time '12:00') at time zone 'America/Lima', 2)
    at time zone 'America/Lima')::date)::int,
  3,
  'Si el lunes es feriado, el plazo vence el miércoles');

delete from feriados where nombre = 'Feriado de laboratorio';

-- ── El borrador de amonestación ─────────────────────────────────────────────
set session_replication_role = replica;
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta,
   hechos, creado_por)
values ('00000000-0000-0000-0000-00000000e310',
        '00000000-0000-0000-0000-00000000e302', 'tardanza', 'amonestacion',
        'borrador', fn_hoy_lima() - 10, fn_hoy_lima() - 1, '[]'::jsonb,
        '00000000-0000-0000-0000-00000000e301');
set session_replication_role = origin;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ee000000-0000-0000-0000-0000000000e1","role":"authenticated"}';

-- ── 3 · No se firma sin haber comunicado los cargos ─────────────────────────
select throws_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-00000000e310', null) $$,
  null,
  'Sin comunicar los cargos, la amonestación no se puede firmar');

-- ── 4 · Tampoco se archiva un descargo antes de comunicarlos ────────────────
select is(
  fn_expediente_puede_recibir_descargo('00000000-0000-0000-0000-00000000e310'),
  false,
  'Antes de comunicar los cargos no hay descargo que archivar');

-- ── 5 · Comunicar los cargos abre el plazo ──────────────────────────────────
select isnt(
  fn_expediente_comunicar_cargos('00000000-0000-0000-0000-00000000e310', 2),
  null,
  'Comunicar los cargos devuelve la fecha de vencimiento');

-- ── 6 · Y ahora sí hay dónde archivar el descargo ───────────────────────────
select is(
  fn_expediente_puede_recibir_descargo('00000000-0000-0000-0000-00000000e310'),
  true,
  'Comunicados los cargos, el borrador admite el descargo');

-- ── 7 · No se puede firmar mientras el plazo corre ──────────────────────────
select throws_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-00000000e310', null) $$,
  null,
  'Con el plazo abierto, firmar sigue estando prohibido');

-- ── 8 · Un plazo menor de dos días hábiles se rechaza ───────────────────────
-- `session_replication_role` solo lo puede tocar el dueño de la base, y aquí
-- vamos como `authenticated`. Sin este paréntesis la prueba muere a media
-- ejecución y pgTAP lo reporta como «Bad plan», que se lee como un descuido de
-- conteo y no lo es.
reset role;
set session_replication_role = replica;
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, hechos, creado_por)
values ('00000000-0000-0000-0000-00000000e311',
        '00000000-0000-0000-0000-00000000e302', 'falta', 'amonestacion',
        'borrador', '[]'::jsonb, '00000000-0000-0000-0000-00000000e301');
set session_replication_role = origin;
set local role authenticated;

select throws_ok(
  $$ select fn_expediente_comunicar_cargos('00000000-0000-0000-0000-00000000e311', 1) $$,
  null,
  'Un plazo de un solo día hábil se rechaza: el mínimo son dos');

-- ── 9 · No acoger un descargo exige decir por qué ───────────────────────────
select throws_ok(
  $$ select fn_expediente_valorar_descargo('00000000-0000-0000-0000-00000000e310', 'no', 'nada') $$,
  null,
  'Rechazar un descargo sin motivo escrito se rechaza (art. 19.3)');

-- ── 10 · Vencido el plazo y valorado el descargo, se firma ──────────────────
-- Se retrasan AMBAS fechas para no esperar dos días en una prueba. Mover solo
-- el vencimiento no vale: `chk_descargo_coherente` exige que venza después de
-- comunicarse, y con razón — un plazo que caduca antes de abrirse no es plazo.
-- La restricción cazó este atajo al escribir la prueba.
reset role;
set session_replication_role = replica;
update expediente_disciplinario
   set cargos_comunicados_at = now() - interval '3 days',
       descargo_vence_at     = now() - interval '1 hour'
 where id = '00000000-0000-0000-0000-00000000e310';
set session_replication_role = origin;
set local role authenticated;

select fn_expediente_valorar_descargo(
  '00000000-0000-0000-0000-00000000e310', 'sin_descargo',
  'Vencido el plazo sin que se presentara descargo.');

select lives_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-00000000e310', null) $$,
  'Vencido el plazo y valorado el descargo, la amonestación se firma');

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
