-- ============================================================================
-- 94_descanso_sustitutorio_no_toca_lo_pagado.test.sql
-- ============================================================================
-- fn_planilla_calcular lee el descanso sustitutorio EN VIVO: si está OTORGADO,
-- anula la sobretasa de ese feriado. Y fn_otorgar_descanso_sustitutorio no
-- miraba `periodos_planilla`, así que se podía bajar el total de una planilla ya
-- cerrada y pagada — la boleta reimpresa dejaba de coincidir con lo que se
-- transfirió, y el periodo seguía marcado como pagado.
--
-- Era la única puerta de su familia sin candado: otras doce funciones que mueven
-- dinero ya lo tenían, con el mismo mensaje de «Reabre el periodo primero».
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000b5', 'ZZDSU', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000b6', 'DsuAdmin', 'Lab', '00000000-0000-0000-0000-0000000000b5', 'admin', 'x', '00000000-0000-0000-0000-00000000bb06', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000b7', 'DsuTrabaja', 'Lab', '00000000-0000-0000-0000-0000000000b5', 'x', '2024-01-01');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000b7', 'colibri', 1950, '2024-01-01');

-- Horario de lunes a sábado: la función exige comprobar que el día compensatorio
-- sea laborable, y para eso necesita un horario vigente en esa fecha.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-0000000000b7', '2024-01-01', '09:00', '15:30', 0, 0,
        array[1,2,3,4,5,6], 39,
        '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
          "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
          "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000bb06', true);

-- Un feriado trabajado, con sus horas marcadas (OTORGADO las exige).
insert into feriados (fecha, nombre) values ('2026-06-29', 'Feriado de laboratorio')
on conflict (fecha) do nothing;

insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-0000000000b5', 'entrada',      '2026-06-29T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-0000000000b5', 'salida_final', '2026-06-29T15:30:00-05:00');

-- ── Con el periodo ABIERTO se puede registrar con normalidad ─────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('cccccccc-0000-0000-0000-000000000001', '2026-06-01', '2026-06-30', 'abierto');

select lives_ok($$ select fn_otorgar_descanso_sustitutorio(
    '00000000-0000-0000-0000-0000000000b7', '2026-06-29', '2026-07-06', 'OTORGADO', 'acta-lab') $$,
  'ABIERTO · con el periodo abierto se registra el descanso sin problema');

select is((select count(*)::int from feriados_descanso_sustitutorio
           where persona_id='00000000-0000-0000-0000-0000000000b7'),
          1, 'ABIERTO · y queda registrado');

-- Se quita para dejar el escenario limpio antes de cerrar el periodo.
select fn_quitar_descanso_sustitutorio(
  (select id from feriados_descanso_sustitutorio where persona_id='00000000-0000-0000-0000-0000000000b7' limit 1));

-- ── Con el periodo PAGADO, ninguna de las dos operaciones entra ──────────────
update periodos_planilla set estado = 'pagado' where id = 'cccccccc-0000-0000-0000-000000000001';

select throws_ok($$ select fn_otorgar_descanso_sustitutorio(
    '00000000-0000-0000-0000-0000000000b7', '2026-06-29', '2026-07-06', 'OTORGADO', 'acta-lab') $$,
  null, null, 'PAGADO · otorgar se rechaza: cambiaría el total de una planilla ya pagada');

select is((select count(*)::int from feriados_descanso_sustitutorio
           where persona_id='00000000-0000-0000-0000-0000000000b7'),
          0, 'PAGADO · y no quedó nada registrado a medias');

-- El día compensatorio en un periodo pagado también frena, aunque el feriado no lo esté.
insert into feriados (fecha, nombre) values ('2026-08-30', 'Feriado de agosto lab')
on conflict (fecha) do nothing;
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-0000000000b5', 'entrada',      '2026-08-30T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-0000000000b5', 'salida_final', '2026-08-30T15:30:00-05:00');

select throws_ok($$ select fn_otorgar_descanso_sustitutorio(
    '00000000-0000-0000-0000-0000000000b7', '2026-08-30', '2026-06-15', 'OTORGADO', 'acta-lab-2') $$,
  null, null, 'PAGADO · y también frena si es el día compensatorio el que cae en el periodo cerrado');

-- ── Quitar uno que no existe avisa, en vez de no hacer nada en silencio ──────
select throws_ok($$ select fn_quitar_descanso_sustitutorio('cccccccc-0000-0000-0000-0000000000ff') $$,
  null, null, 'QUITAR · un id que no existe avisa, en vez de decir que todo fue bien');

select * from finish();
rollback;
