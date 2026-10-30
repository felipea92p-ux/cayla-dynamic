-- ============================================================================
-- 439_correcciones_distingue_un_grupo_pagado_con_el_periodo_abierto.test.sql
-- ============================================================================
-- LO QUE DEFIENDE (migración 0547):
--
--   `fn_dias_por_revisar` clasifica por qué cada día está sellado. Hasta la 0547
--   solo tenía tres respuestas, y la tercera —'sello_sin_levantar'— era un cajón
--   de sastre: «el día cuadra y nadie levantó el sello». Mezclaba dos cosas muy
--   distintas:
--
--     (a) un sello viejo de un día que ya cuadra → de verdad no hay nada que hacer;
--     (b) la marca de alguien cuyo GRUPO ya se pagó, con el periodo todavía
--         abierto → el candado está frenando sus horas y sellando cada marca nueva.
--
--   El 2026-10-21 el grupo «planilla» se marcó pagado por error a mitad de periodo
--   y Correcciones lo mostró como (a): «ya cuadra · no hay nada que corregir». Era
--   lo único que se veía de un pago que bloqueaba las horas de 10 personas.
--
--   La 0547 da a (b) su propio motivo, 'grupo_pagado_periodo_abierto', y dos
--   columnas nuevas con el grupo y el momento del pago, para poder decirlo con
--   todas sus letras en pantalla.
--
--   Lo que NO cambia, y también se defiende: el MISMO conjunto de días (nada se
--   esconde ni se agrega), un sello común sigue siendo 'sello_sin_levantar', un
--   día roto de verdad sigue mandando como 'secuencia_imposible', y un periodo
--   pagado ENTERO sigue marcado `periodo_pagado` (la pantalla lo oculta a
--   propósito: no hay nada que corregir sin reabrir).
-- ============================================================================
begin;
select plan(13);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000043900', 'ZZ439', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000043901', 'CuatroTresNueveAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000043900', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000043909', '2024-01-01');
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000004390e', '00000000-0000-0000-0000-000000043900',
        'Mac mini de laboratorio', true, '00000000-0000-0000-0000-00000004390a');
set session_replication_role = origin;

-- A: planilla, su marca entra sellada porque el grupo ya se pagó.
-- B: planilla, un día roto de verdad.  F: planilla, en un periodo pagado ENTERO.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000043902', 'NueveA', 'Laboratorio', '00000000-0000-0000-0000-000000043900', 'test-hash', '2024-01-01'),
       ('00000000-0000-0000-0000-000000043903', 'NueveB', 'Laboratorio', '00000000-0000-0000-0000-000000043900', 'test-hash', '2024-01-01'),
       ('00000000-0000-0000-0000-000000043905', 'NueveF', 'Laboratorio', '00000000-0000-0000-0000-000000043900', 'test-hash', '2024-01-01');
-- R: rxh, un sello común en un día que cuadra; su grupo NO está pagado.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000043904', 'NueveRxh', 'Laboratorio', '00000000-0000-0000-0000-000000043900', 'test-hash', '2024-01-01', 'rxh');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, date '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6,7], 45
  from personas where id in ('00000000-0000-0000-0000-000000043902', '00000000-0000-0000-0000-000000043903', '00000000-0000-0000-0000-000000043905');

-- Octubre: ABIERTO (planilla se pagará sola). Septiembre: pagado ENTERO.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000439aa', '2026-09-28', '2026-10-28', 'abierto');
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at)
values ('00000000-0000-0000-0000-0000000439bb', '2026-08-29', '2026-09-27', 'pagado', now());
-- Y con su fila por grupo, que es como queda un periodo pagado desde la 0323: sin
-- ella el control de abajo no distinguiría «el periodo entero está pagado» de «no
-- hay ningún grupo pagado».
insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at)
values ('00000000-0000-0000-0000-0000000439bb', 'planilla', 'pagado', now());

-- ── Antes del pago ──────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004390a', true);
select fn_registrar_marcaje('00000000-0000-0000-0000-000000043902', 'entrada'::tipo_marca, timestamptz '2026-10-21 09:00-05',
  '00000000-0000-0000-0000-000000043a91', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004390e');

-- ── Se paga SOLO planilla, a mitad del periodo ──────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000043909', true);
select fn_periodo_pagado('00000000-0000-0000-0000-0000000439aa', true, 'planilla');

-- ── Con el grupo pagado: A marca su salida y entra sellada ──────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004390a', true);
select fn_registrar_marcaje('00000000-0000-0000-0000-000000043902', 'salida_final'::tipo_marca, timestamptz '2026-10-21 18:00-05',
  '00000000-0000-0000-0000-000000043a92', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004390e');

-- B: salida sin entrada, sellada (el día está roto de verdad).
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen, estado_revision)
values ('00000000-0000-0000-0000-000000043a93', '00000000-0000-0000-0000-000000043903',
        '00000000-0000-0000-0000-000000043900', '00000000-0000-0000-0000-00000004390e',
        'salida_final', timestamptz '2026-10-21 18:05-05', 'terminal', 'pendiente_revision');

-- R: un día que CUADRA con una marca sellada de más (sello común, ya sin motivo).
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen, estado_revision)
values ('00000000-0000-0000-0000-000000043a94', '00000000-0000-0000-0000-000000043904',
        '00000000-0000-0000-0000-000000043900', '00000000-0000-0000-0000-00000004390e',
        'entrada', timestamptz '2026-10-21 09:00-05', 'terminal', 'pendiente_revision'),
       ('00000000-0000-0000-0000-000000043a95', '00000000-0000-0000-0000-000000043904',
        '00000000-0000-0000-0000-000000043900', '00000000-0000-0000-0000-00000004390e',
        'salida_final', timestamptz '2026-10-21 18:00-05', 'terminal', 'normal');

-- F: lo mismo pero en septiembre, cuyo periodo está pagado ENTERO.
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen, estado_revision)
values ('00000000-0000-0000-0000-000000043a96', '00000000-0000-0000-0000-000000043905',
        '00000000-0000-0000-0000-000000043900', '00000000-0000-0000-0000-00000004390e',
        'entrada', timestamptz '2026-09-10 09:00-05', 'terminal', 'pendiente_revision'),
       ('00000000-0000-0000-0000-000000043a97', '00000000-0000-0000-0000-000000043905',
        '00000000-0000-0000-0000-000000043900', '00000000-0000-0000-0000-00000004390e',
        'salida_final', timestamptz '2026-09-10 18:00-05', 'terminal', 'normal');

-- Quien pregunta es el admin.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000043909', true);


-- ── 1 · El escenario ────────────────────────────────────────────────────────
select ok(
  (select estado = 'abierto' from periodos_planilla where id = '00000000-0000-0000-0000-0000000439aa')
  and (select estado = 'pagado' from periodo_grupo_pago
        where periodo_id = '00000000-0000-0000-0000-0000000439aa' and grupo = 'planilla'),
  'ESCENARIO · octubre sigue abierto pero el grupo planilla está pagado');

-- ── 2-5 · El día de A: motivo propio, y dice qué grupo y cuándo ─────────────
select is(
  (select motivo from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043902' and fecha = date '2026-10-21'),
  'grupo_pagado_periodo_abierto',
  'MOTIVO PROPIO · el día de A ya no se llama «sello sin levantar»: su grupo se pagó con el periodo abierto');

select is(
  (select periodo_pagado from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043902' and fecha = date '2026-10-21'),
  false,
  'SIGUE VISIBLE · el periodo entero NO está pagado, así que la pantalla lo muestra (no entra en la lista oculta)');

select is(
  (select grupo_pagado from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043902' and fecha = date '2026-10-21'),
  'planilla',
  'DICE EL GRUPO · para poder escribir «el grupo planilla se pagó el…»');

select is(
  (select grupo_pagado_at from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043902' and fecha = date '2026-10-21'),
  (select pagado_at from periodo_grupo_pago
    where periodo_id = '00000000-0000-0000-0000-0000000439aa' and grupo = 'planilla'),
  'DICE CUÁNDO · es el instante real del pago, el mismo que guarda periodo_grupo_pago');

-- ── 6 · Un día roto de verdad sigue mandando ───────────────────────────────
select is(
  (select motivo from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043903' and fecha = date '2026-10-21'),
  'secuencia_imposible',
  'PRIORIDAD · el día de B está roto de verdad y eso manda sobre el pago del grupo');

-- ── 7-8 · Un sello común no cambia ─────────────────────────────────────────
select is(
  (select motivo from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043904' and fecha = date '2026-10-21'),
  'sello_sin_levantar',
  'SIN CAMBIO · un sello viejo en un día que cuadra, de un grupo NO pagado, sigue siendo «sello sin levantar»');

select ok(
  (select grupo_pagado is null and grupo_pagado_at is null from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043904' and fecha = date '2026-10-21'),
  'SIN CAMBIO · y no inventa un grupo pagado donde no lo hay (rxh no se pagó)');

-- ── 9-11 · Un periodo pagado ENTERO sigue igual ────────────────────────────
select is(
  (select periodo_pagado from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043905' and fecha = date '2026-09-10'),
  true,
  'SIN CAMBIO · en un periodo pagado entero, periodo_pagado sigue en true (la pantalla lo oculta a propósito)');

select is(
  (select motivo from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043905' and fecha = date '2026-09-10'),
  'sello_sin_levantar',
  'SIN CAMBIO · y su motivo no se mezcla con el del grupo pagado con periodo abierto');

select ok(
  (select grupo_pagado is null from fn_dias_por_revisar(50)
    where persona_id = '00000000-0000-0000-0000-000000043905' and fecha = date '2026-09-10'),
  'SIN CAMBIO · «grupo pagado» solo se dice cuando el periodo sigue abierto');

-- ── 12 · Nada se esconde, nada se agrega ───────────────────────────────────
select is(
  (select count(*)::int from fn_dias_por_revisar(50)),
  4,
  'MISMO CONJUNTO · siguen saliendo exactamente los 4 días sellados (A, B, R y F): la 0547 solo etiqueta');

-- ── 13 · El tipo de la columna nueva ───────────────────────────────────────
select is(
  (select pg_typeof(grupo_pagado_at)::text from fn_dias_por_revisar(50) limit 1),
  'timestamp with time zone',
  'TIPO · grupo_pagado_at es un instante con zona horaria, igual que pagado_at');

select * from finish();
rollback;
