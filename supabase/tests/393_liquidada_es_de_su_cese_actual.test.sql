-- ============================================================================
-- 393_liquidada_es_de_su_cese_actual.test.sql
-- ============================================================================
-- Migración 0499. `fn_persona_liquidada` dice «sí» solo si la ÚLTIMA liquidación
-- no está anulada Y es del cese que la persona tiene hoy.
--
-- Fechas INVENTADAS. Seis personas, una por cada forma de estar (o no estar)
-- liquidada, y lo que se mide en cada una es lo que MUESTRA la cola de marcas
-- apartadas, porque ahí es donde el defecto dolía: `fn_marcas_apartadas` y
-- `fn_dias_por_revisar` ocultan a quien esta función da por liquidada, así que un
-- «sí» de más esconde los marcajes que pueden pagarle de menos a alguien.
--
-- LO QUE DE VERDAD HAY QUE DEFENDER, EN ESTE ORDEN:
--   1 · quien está cesada y liquidada SIGUE oculta (nadie que hoy se oculta aparece);
--   2 · quien volvió a trabajar después de liquidarse DEJA de estar oculta;
--   3 · anular la liquidación la deshace también para esta función;
--   4 · un segundo cese sin liquidar no se da por liquidado con la primera liquidación.
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000004c0', 'ZZ499', 'Sede liquidada', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000004c9', 'CincoAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000004c0', 'admin', 'x',
        '00000000-0000-0000-0000-0000000004cf', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000004cf', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000004c1', 'CincoCesada',    'Laboratorio', '00000000-0000-0000-0000-0000000004c0', 'x', '2025-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000004c2', 'CincoVolvio',    'Laboratorio', '00000000-0000-0000-0000-0000000004c0', 'x', '2025-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000004c3', 'CincoAnulada',   'Laboratorio', '00000000-0000-0000-0000-0000000004c0', 'x', '2025-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000004c4', 'CincoDosCeses',  'Laboratorio', '00000000-0000-0000-0000-0000000004c0', 'x', '2025-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000004c5', 'CincoActiva',    'Laboratorio', '00000000-0000-0000-0000-0000000004c0', 'x', '2025-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000004c6', 'CincoSinPagar',  'Laboratorio', '00000000-0000-0000-0000-0000000004c0', 'x', '2025-01-15', 'planilla');

-- Quién cesó y cuándo. (Como en las pruebas 130/184: se pone a mano porque
-- `fn_cesar_persona` se niega a cesar dentro de un periodo ya pagado.)
update personas set estado = 'inactivo', fecha_cese = '2026-03-10'
 where id in ('00000000-0000-0000-0000-0000000004c1',   -- cesada y liquidada
              '00000000-0000-0000-0000-0000000004c3',   -- cesada, liquidada y anulada
              '00000000-0000-0000-0000-0000000004c6');  -- cesada y SIN liquidar
update personas set estado = 'inactivo', fecha_cese = '2026-08-01'   -- su SEGUNDO cese
 where id = '00000000-0000-0000-0000-0000000004c4';
-- CincoVolvio: fue liquidada del 10/03 y volvió a trabajar → activa, sin cese.

-- Una liquidación pagada por persona (inmutable: solo se inserta). Las dos que
-- cubren un cese del 10/03 más la de CincoVolvio, que volvió, y CincoDosCeses, que
-- se liquidó del PRIMER cese y cesó otra vez.
insert into liquidacion_pagada
  (persona_id, version, congelada_por, persona, fecha_ingreso, fecha_cese, total, detalle, fecha_pago)
select p, 1, '00000000-0000-0000-0000-0000000004c9', 'x', '2025-01-15', '2026-03-10', 0, '{}'::jsonb, '2026-03-12'
  from unnest(array[
    '00000000-0000-0000-0000-0000000004c1'::uuid,
    '00000000-0000-0000-0000-0000000004c2'::uuid,
    '00000000-0000-0000-0000-0000000004c3'::uuid,
    '00000000-0000-0000-0000-0000000004c4'::uuid]) p;

-- CincoAnulada: la liquidación se anula. La anulación es una versión NUEVA en cero y
-- la original queda intacta con `anulada = false` — justo lo que la función vieja no veía.
insert into liquidacion_pagada
  (persona_id, version, congelada_por, persona, fecha_ingreso, fecha_cese, total, detalle,
   anulada, motivo_anulacion, anula_version)
values ('00000000-0000-0000-0000-0000000004c3', 2, '00000000-0000-0000-0000-0000000004c9',
        'x', '2025-01-15', '2026-03-10', 0, '{}'::jsonb,
        true, 'se marcó por error en la prueba', 1);

-- Una marca apartada sin resolver por persona: es lo que la cola muestra u oculta.
insert into marcas_apartadas (client_uuid, persona_id, tipo, timestamp_cliente, ultimo_error)
select gen_random_uuid(), id, 'entrada', now() - interval '2 days', 'prueba'
  from personas where nombres like 'Cinco%' and nombres <> 'CincoAdmin';

create temp table _q on commit drop as
select p.nombres as quien, fn_persona_liquidada(p.id) as liquidada,
       (select count(*) from fn_marcas_apartadas() m where m.persona_id = p.id)::int as en_la_cola
  from personas p where p.nombres like 'Cinco%' and p.nombres <> 'CincoAdmin';

-- ── 1 · Cesada y liquidada: SIGUE siendo «liquidada» y SIGUE oculta ─────────
select is((select liquidada from _q where quien = 'CincoCesada'), true,
  'SIN CAMBIO · cesada el 10/03 y liquidada del 10/03: liquidada');
select is((select en_la_cola from _q where quien = 'CincoCesada'), 0,
  'SIN CAMBIO · y por eso su marca apartada sigue fuera de la cola, como hoy');

-- ── 2 · Volvió a trabajar: deja de estar oculta ─────────────────────────────
select is((select liquidada from _q where quien = 'CincoVolvio'), false,
  'VOLVIÓ · liquidada del 10/03 pero hoy sin cese: ya no está «liquidada»');
select is((select en_la_cola from _q where quien = 'CincoVolvio'), 1,
  'VOLVIÓ · y su marca apartada VUELVE a verse: el error que escondía marcajes');

-- ── 3 · Anulada: la anulación también cuenta ────────────────────────────────
select is((select liquidada from _q where quien = 'CincoAnulada'), false,
  'ANULADA · la última versión es la anulación: ya no está liquidada');
select is((select en_la_cola from _q where quien = 'CincoAnulada'), 1,
  'ANULADA · y vuelve a verse en la cola, igual que en la lista de pendientes');

-- ── 4 · Segundo cese sin liquidar ───────────────────────────────────────────
select is((select liquidada from _q where quien = 'CincoDosCeses'), false,
  'SEGUNDO CESE · la liquidación del primer cese (10/03) no cubre el del 01/08');
select is((select en_la_cola from _q where quien = 'CincoDosCeses'), 1,
  'SEGUNDO CESE · y por eso su marca se sigue viendo hasta que se liquide');

-- Al liquidar el segundo cese, sí.
insert into liquidacion_pagada
  (persona_id, version, congelada_por, persona, fecha_ingreso, fecha_cese, total, detalle, fecha_pago)
values ('00000000-0000-0000-0000-0000000004c4', 2, '00000000-0000-0000-0000-0000000004c9',
        'x', '2025-01-15', '2026-08-01', 0, '{}'::jsonb, '2026-08-03');
select is(fn_persona_liquidada('00000000-0000-0000-0000-0000000004c4'::uuid), true,
  'SEGUNDO CESE · ya liquidado el segundo cese: liquidada');

-- ── 5 · Lo que no tiene liquidación no se da por liquidado ──────────────────
select is((select liquidada from _q where quien = 'CincoActiva'), false,
  'SIN LIQUIDACIÓN · una persona activa nunca está liquidada');
select is((select liquidada from _q where quien = 'CincoSinPagar'), false,
  'SIN LIQUIDACIÓN · cesada pero sin liquidar: no está liquidada');
select is((select en_la_cola from _q where quien = 'CincoSinPagar'), 1,
  'SIN LIQUIDACIÓN · y se sigue viendo («puede tener un marcaje real por corregir antes de calcularla»)');
select is(fn_persona_liquidada(null), false,
  'NULO · sin persona, no hay liquidación');
select is(fn_persona_liquidada('00000000-0000-0000-0000-00000000dead'::uuid), false,
  'INEXISTENTE · una persona que no existe no está liquidada');

-- ── 6 · Los permisos no cambian ─────────────────────────────────────────────
select is(has_function_privilege('authenticated', 'fn_persona_liquidada(uuid)', 'execute'), true,
  'PERMISOS · authenticated sigue pudiendo ejecutarla (la usan las colas)');
select is(has_function_privilege('anon', 'fn_persona_liquidada(uuid)', 'execute'), false,
  'PERMISOS · anon sigue sin poder');

select * from finish();
rollback;
