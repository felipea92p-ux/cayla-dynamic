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
select plan(27);

-- Los tres meses que cubre la asignación de la prueba son relativos a HOY, no
-- 2026-06/07/08 fijos. Una fecha de calendario absoluta caduca el día que el
-- reloj real la alcanza y la pasa —le pasó a esta prueba el 2026-08-29, un día
-- después de escrita, cuando `fn_educacion_registrar` dejó de tener «hoy»
-- dentro de la ventana declarada—. Anclarlo a `fn_hoy_lima()` conserva la
-- misma forma (tres periodos consecutivos, uno con papel de menos) para
-- siempre, sea cual sea el día real en que esto corra.
create temp table _fechas as
select
  fn_educacion_mes_del_periodo(fn_hoy_lima())                                as bucket_0,
  (fn_educacion_mes_del_periodo(fn_hoy_lima()) - interval '1 month')::date   as bucket_1,
  (fn_educacion_mes_del_periodo(fn_hoy_lima()) - interval '2 months')::date  as bucket_2,
  (fn_educacion_mes_del_periodo(fn_hoy_lima()) + 27)                         as fin_bucket_0;

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
    'trabajador', (select bucket_2 from _fechas), (select fin_bucket_0 from _fechas),
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
  (select bucket_2 from _fechas),
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

-- ── LAS TRES SUELTAS, QUE HASTA HOY NO LLAMABA NADIE ───────────────────────
--
-- La 0290 creó `fn_educacion_papeles`, `fn_educacion_meses_sin_papel` y
-- `fn_educacion_por_atender`, y **ninguna prueba las llamaba por su nombre**.
-- `fn_educacion_listar` trae una CUARTA copia inline de la misma lógica, y era
-- esa copia la que estas pruebas verificaban — o sea que las tres podían
-- pudrirse sin que nada se pusiera rojo.
--
-- Se comparan función CONTRA función, no contra números escritos a mano. El
-- riesgo no es que una dé mal un número: es que **dos de ellas den números
-- distintos** y nadie se entere. `fn_educacion_por_atender` es el contador que
-- le avisa a DO qué papeles hay que perseguir; si dice «0 pendientes» mientras
-- la lista muestra filas con `meses_sin_papel > 0`, nadie va detrás del papel
-- que sustenta un pago YA HECHO.
select is(
  (select count(*)::int from fn_educacion_meses_sin_papel(
     (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'))),
  (select meses_sin_papel from fn_educacion_listar() where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'MISMA CUENTA · fn_educacion_meses_sin_papel dice lo mismo que la lista');

select is(
  (select count(*)::int from fn_educacion_papeles(
     (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'))),
  (select papeles from fn_educacion_listar() where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'MISMA CUENTA · fn_educacion_papeles dice lo mismo que la lista');


-- ── 3 · Adjuntar los que faltan ────────────────────────────────────────────
select lives_ok($$
  select fn_educacion_adjuntar_comprobante(
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'),
    'educacion/c2/julio.pdf', (select bucket_1 from _fechas), null) $$,
  'ADJUNTAR · un segundo papel entra sin tocar la asignación');

select is(
  (select meses_sin_papel from fn_educacion_listar()
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  1,
  'FALTAN · ahora falta uno solo');

-- Y siguen coincidiendo DESPUÉS de mover el dato. Una sola foto no prueba nada:
-- dos funciones pueden acertar el mismo número por casualidad en un estado y
-- separarse en el siguiente.
select is(
  (select count(*)::int from fn_educacion_meses_sin_papel(
     (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'))),
  (select meses_sin_papel from fn_educacion_listar() where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'MISMA CUENTA · y siguen coincidiendo tras adjuntar el segundo papel');

-- EL CONTADOR DEL MENÚ contra la lista que abre esa misma pantalla. Es la
-- comprobación que de verdad importa de las cuatro.
select is(
  -- ⇩ CAMBIO 0450 ⇩ El contador del menú dejó de contar meses sin papel: cuenta
  -- lo que le toca a DO (constancias por revisar, plazos vencidos, estudios sin
  -- calendario, avisos de fin). Se compara contra las listas que abre, igual que
  -- antes; la 355 lo prueba con casos de cada tipo.
  fn_educacion_por_atender(),
  (select count(*)::int from fn_educacion_entregas_pendientes())
  + (select count(*)::int from fn_educacion_situacion()
      where estado_constancia = 'vencida'
         or (estado_constancia = 'sin_calendario' and vigencia in ('vigente', 'por_terminar')))
  + (select count(*)::int from fn_educacion_avisos_fin_pendientes()),
  'EL CONTADOR · fn_educacion_por_atender dice lo mismo que las listas que abre');

select throws_like($$
  select fn_educacion_adjuntar_comprobante(
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'),
    'educacion/c2/fuera_de_rango.pdf', (select bucket_0 + interval '6 months' from _fechas)::date, null) $$,
  '%no paga el mes%',
  'ADJUNTAR · un recibo de un mes que esa vigencia no cobra se rechaza: no sostiene nada');


-- ── 4 · ⇩ CAMBIO 0450 ⇩ Un papel aprobado ya no se quita ──────────────────
-- Hasta la 0450 quitar borraba la fila y el espejo retrocedía. Desde entonces
-- cada papel de esta tabla es una entrega APROBADA (mismo id) y lo aprobado es
-- el sustento de lo que ya se pagó: no se borra. Quitar se niega, y lo dice.
select throws_like($$
  select fn_educacion_quitar_comprobante(
    (select c.id from educacion_comprobantes c
       join asignaciones_educacion a on a.id = c.asignacion_id
      where a.persona_id = '00000000-0000-0000-0000-0000000000c2'
        and c.mes_cubierto = (select bucket_1 from _fechas)),
    'se subió el recibo equivocado') $$,
  '%no se quita%',
  'QUITAR · un comprobante aprobado no se quita, aunque venga con motivo');

select is(
  (select comprobante_url from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'educacion/c2/julio.pdf',
  'ESPEJO · la columna sigue apuntando al papel más reciente');

select is(
  (select count(*)::int from educacion_entregas e
     join educacion_comprobantes c on c.id = e.id
     join asignaciones_educacion a on a.id = c.asignacion_id
    where a.persona_id = '00000000-0000-0000-0000-0000000000c2'
      and e.estado = 'aprobada'),
  2,
  'PUERTA · cada papel de esta tabla es una entrega aprobada, con el mismo id');


-- ── 5 · Quitar ya no apaga el pago ─────────────────────────────────────────
select throws_like($$
  select fn_educacion_quitar_comprobante(
    (select c.id from educacion_comprobantes c
       join asignaciones_educacion a on a.id = c.asignacion_id
      where a.persona_id = '00000000-0000-0000-0000-0000000000c2'
        and c.mes_cubierto = (select bucket_2 from _fechas)),
    'prueba de que la columna no se vacía') $$,
  '%no se quita%',
  'QUITAR · tampoco el último');

select is(
  (select paga from fn_educacion_listar()
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  true,
  'DEVENGO · con sus papeles aprobados intactos, la asignación sigue pagando');

-- ── 6 · Corregir no puede llevarse los papeles por delante ────────────────
-- Es el caso que la 0290 tuvo que resolver a mano: la tabla cuelga de la
-- asignación con `on delete cascade`, y una corrección que mueve plata cierra la
-- vigencia vieja y abre una nueva. Sin copiar los papeles, la nueva nacería sin
-- sustento — y sin sustento no devenga. Arreglar una errata habría dejado a
-- alguien sin cobrar, en silencio.
--
-- fn_educacion_registrar ancla `v_desde` de la corrección a HOY (no hay
-- periodos_planilla sembrados en esta prueba, así que cae al respaldo de
-- fn_educacion_desde_cuando_puede_regir()). Por eso la vigencia del alta ya se
-- extendió hasta `fin_bucket_0` —el último día del periodo de hoy—: si
-- terminara antes de hoy, como pasaba con el 28 de agosto fijo, la corrección
-- no tendría ningún periodo abierto donde aterrizar.
-- ⇩ CAMBIO 0450 ⇩ junio y julio siguen puestos (quitar ya no borra): solo falta
-- agosto.
select fn_educacion_adjuntar_comprobante(
  (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'educacion/c2/agosto.pdf', (select bucket_0 from _fechas), null);

select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-0000000000c2'::uuid, 'Instituto de laboratorio', 240::numeric,
    'trabajador', (select bucket_2 from _fechas), (select fin_bucket_0 from _fechas),
    null, null, null,
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000000c2'),
    'el comprobante decía 240 y se registró 200') $$,
  'CORREGIR · el costo cambia y se abre una vigencia nueva');

select is(
  (select count(*)::int from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  2,
  'CORREGIR · quedan dos vigencias: la cerrada y la que rige');

-- ⇩ CAMBIO 0450 ⇩ Los papeles ya no se COPIAN a la vigencia nueva: las dos
-- vigencias son la misma familia y la comparten. Copiar ahora duplicaría
-- entregas aprobadas en el historial.
select is(
  (select count(*)::int from educacion_entregas e
     join asignaciones_educacion a on a.id = e.asignacion_id
    where a.persona_id = '00000000-0000-0000-0000-0000000000c2'),
  3,
  'CORREGIR · la familia conserva sus tres constancias, sin duplicarlas');

select isnt(
  (select comprobante_url from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-0000000000c2'
      and vigente_desde > (select bucket_2 from _fechas)),
  null,
  'CORREGIR · y por eso sigue devengando: el espejo de la vigencia nueva no quedó vacío');

-- ── LA RLS DE ESTA TABLA NO LA COMPROBABA NADIE ────────────────────────────
-- `educacion_comprobantes` guarda los papeles que sustentan un pago de
-- educación. Tiene policy desde la 0290 y hasta hoy ninguna prueba cambiaba de
-- usuario: las veinte de arriba corren enteras como DO, así que si la policy se
-- rompiera no se enteraría ninguna.
--
-- ⚠ `set local role authenticated` NO es decorativo — la misma advertencia del
-- test 198. pgTAP corre como `postgres`, superusuario, y SE SALTA LA RLS: sin
-- esa línea la tercera ve los papeles de Ana y la prueba «pasa» al revés.
set session_replication_role = replica;
update personas set auth_user_id = '00000000-0000-0000-0000-0000000000ca'
 where id = '00000000-0000-0000-0000-0000000000c2';
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000c3', 'ComTercera', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000c0', 'integrante', 'test-hash',
        '00000000-0000-0000-0000-0000000000cb', '2025-01-02');
set session_replication_role = origin;

-- Ana, que es de quien son los papeles.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ca', true);
set local role authenticated;

select ok(
  (select count(*) from educacion_comprobantes) > 0,
  'RLS · cada quien ve los comprobantes de su propia asignación');

-- Una compañera sin nada que ver con esa asignación.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000cb', true);

select is(
  (select count(*)::int from educacion_comprobantes),
  0,
  'RLS · y una compañera no ve ni uno: son el sustento del pago de otra persona');

-- Aquí la 0290 sí hizo `revoke all` y dejó solo el `select`, al revés que
-- `contratos_generados` y `asignaciones_regimen_pension`, donde `authenticated`
-- conserva el INSERT que trae Supabase por defecto. Se prueba igual: lo que
-- importa es que no entre, no por cuál de los dos frenos.
select throws_ok(
  $$ insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto)
     values ((select id from asignaciones_educacion
               where persona_id = '00000000-0000-0000-0000-0000000000c2' limit 1),
             'educacion/inventado.pdf', '2026-08-01') $$,
  '42501', NULL,
  'RLS · ni puede colgarle un papel a la asignación de otra');

reset role;


select * from finish();
rollback;
