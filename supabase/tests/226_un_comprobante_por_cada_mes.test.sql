-- ============================================================================
-- 226_un_comprobante_por_cada_mes.test.sql
-- ============================================================================
-- Lo que promete la 0290: que una asignación por educación pueda tener un papel
-- por cada mes que paga, que el sistema diga cuáles faltan, y que la columna
-- `comprobante_url` —de la que depende la planilla para saber si algo devenga—
-- siga diciendo la verdad sin que nadie la escriba a mano.
--
-- Las fechas son de 2026 y están en el pasado a propósito: el aviso solo cuenta
-- los meses que YA llegaron, así que con fechas futuras no habría nada que
-- contar y la prueba no probaría nada.
-- ============================================================================
begin;
select plan(20);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000c0', 'ZZCOM', 'Sede de laboratorio 290', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000c1', 'ComDO', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000c0', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-0000000000c9', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000c2', 'ComAna', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000c0', 'test-hash', '2025-01-02');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000c2', 'aurora', 2000, '2025-01-02');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c9', true);


-- ── 1 · El borde del 28 y el 29, que es de donde sale todo lo demás ─────────
select is(fn_educacion_mes_del_periodo('2026-08-28'::date), '2026-08-01'::date,
  'MES · el 28 todavía es el periodo de agosto');

select is(fn_educacion_mes_del_periodo('2026-08-29'::date), '2026-09-01'::date,
  'MES · el 29 ya es el de septiembre, que es como corta la planilla');

select is(
  (select count(*)::int from fn_educacion_meses_del_tramo('2026-06-01'::date, '2026-08-28'::date)),
  3,
  'TRAMO · del 01/06 al 28/08 se cobran tres periodos: junio, julio y agosto');


-- ── 2 · El alta deja su papel en la tabla, y el espejo lo refleja ───────────
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-0000000000c2'::uuid, 'Instituto de laboratorio', 200::numeric,
    'trabajador', '2026-06-01'::date, '2026-08-28'::date,
    null, 'educacion/c2/junio.pdf', null, null, null) $$,
  'ALTA · se registra con su comprobante');

select is(
  (select count(*)::int from educacion_comprobantes c
     join asignaciones_educacion a on a.id = c.asignacion_id
    where a.persona_id = '00000000-0000-0000-0000-0000000000c2'),
  1,
  'ALTA · el papel quedó en educacion_comprobantes, no en la columna');

select is(
  (select c.mes_cubierto from educacion_comprobantes c
     join asignaciones_educacion a on a.id = c.asignacion_id
    where a.persona_id = '00000000-0000-0000-0000-0000000000c2'),
  '2026-06-01'::date,
  'ALTA · y respalda el mes del periodo en que empieza la vigencia');

select is(
  (select comprobante_url from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'educacion/c2/junio.pdf',
  'ESPEJO · la columna que lee la planilla apunta sola al papel, sin que nadie la escriba');

select is(
  (select meses_sin_papel from fn_educacion_listar()
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  2,
  'FALTAN · con un papel de tres meses ya cobrados, faltan dos');


-- ── 3 · Adjuntar los que faltan ────────────────────────────────────────────
select lives_ok($$
  select fn_educacion_adjuntar_comprobante(
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'),
    'educacion/c2/julio.pdf', '2026-07-01'::date, null) $$,
  'ADJUNTAR · un segundo papel entra sin tocar la asignación');

select is(
  (select meses_sin_papel from fn_educacion_listar()
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  1,
  'FALTAN · ahora falta uno solo');

select throws_like($$
  select fn_educacion_adjuntar_comprobante(
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'),
    'educacion/c2/enero27.pdf', '2027-01-01'::date, null) $$,
  '%no paga el mes%',
  'ADJUNTAR · un recibo de un mes que esa vigencia no cobra se rechaza: no sostiene nada');


-- ── 4 · Quitar exige motivo, y el espejo se entera ─────────────────────────
select throws_like($$
  select fn_educacion_quitar_comprobante(
    (select c.id from educacion_comprobantes c
       join asignaciones_educacion a on a.id = c.asignacion_id
      where a.persona_id = '00000000-0000-0000-0000-0000000000c2' and c.mes_cubierto = '2026-07-01'),
    null) $$,
  '%por qué se quita%',
  'QUITAR · sin motivo no se quita: esa fila deja de tener con qué defenderse');

select lives_ok($$
  select fn_educacion_quitar_comprobante(
    (select c.id from educacion_comprobantes c
       join asignaciones_educacion a on a.id = c.asignacion_id
      where a.persona_id = '00000000-0000-0000-0000-0000000000c2' and c.mes_cubierto = '2026-07-01'),
    'se subió el recibo equivocado') $$,
  'QUITAR · con motivo sí');

select is(
  (select comprobante_url from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'educacion/c2/junio.pdf',
  'ESPEJO · al quitar el más reciente, la columna vuelve sola al que queda');


-- ── 5 · Y sin ningún papel, no devenga: la regla de siempre sigue viva ─────
select lives_ok($$
  select fn_educacion_quitar_comprobante(
    (select c.id from educacion_comprobantes c
       join asignaciones_educacion a on a.id = c.asignacion_id
      where a.persona_id = '00000000-0000-0000-0000-0000000000c2'),
    'prueba de que la columna se vacía sola') $$,
  'ESPEJO · se quita el último papel');

select is(
  (select paga from fn_educacion_listar()
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  false,
  'DEVENGO · sin ningún comprobante la asignación deja de pagar, como antes de la 0290');

-- ── 6 · Corregir no puede llevarse los papeles por delante ────────────────
-- Es el caso que la 0290 tuvo que resolver a mano: la tabla cuelga de la
-- asignación con `on delete cascade`, y una corrección que mueve plata cierra la
-- vigencia vieja y abre una nueva. Sin copiar los papeles, la nueva nacería sin
-- sustento — y sin sustento no devenga. Arreglar una errata habría dejado a
-- alguien sin cobrar, en silencio.
select fn_educacion_adjuntar_comprobante(
  (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'educacion/c2/junio.pdf', '2026-06-01'::date, null);
select fn_educacion_adjuntar_comprobante(
  (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'educacion/c2/agosto.pdf', '2026-08-01'::date, null);

select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-0000000000c2'::uuid, 'Instituto de laboratorio', 240::numeric,
    'trabajador', '2026-06-01'::date, '2026-08-28'::date,
    null, null, null,
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'),
    'el comprobante decía 240 y se registró 200') $$,
  'CORREGIR · el costo cambia y se abre una vigencia nueva');

select is(
  (select count(*)::int from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  2,
  'CORREGIR · quedan dos vigencias: la cerrada y la que rige');

select is(
  (select count(*)::int from educacion_comprobantes c
     join asignaciones_educacion a on a.id = c.asignacion_id
    where a.persona_id = '00000000-0000-0000-0000-0000000000c2'
      and a.vigente_desde > '2026-06-01'),
  1,
  'CORREGIR · la vigencia nueva se quedó con el papel del mes que sí paga, y solo ese');

select isnt(
  (select comprobante_url from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-0000000000c2'
      and vigente_desde > '2026-06-01'),
  null,
  'CORREGIR · y por eso sigue devengando: el espejo de la vigencia nueva no quedó vacío');

select * from finish();
rollback;
