-- ============================================================================
-- 95_el_memo_no_acusa_por_dias_justificados.test.sql
-- ============================================================================
-- «Qué es una falta» estaba escrito dos veces: en fn_faltas (lo que ve la
-- pantalla) y en fn_falta_contadores (lo que arma el documento). La 0070 y la
-- 0079 corrigieron la primera y ninguna tocó la segunda, así que la pantalla
-- decía «justificado — suspensión» y el papel que se imprime y se ENTREGA
-- listaba ese mismo día como inasistencia injustificada.
--
-- Un día de suspensión ya cumplida convertido en prueba para la siguiente
-- sanción es justo el non bis in idem que la 0079 vino a impedir.
--
-- Esta prueba compara las dos definiciones sobre el MISMO día: si vuelven a
-- separarse, falla.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000a5', 'ZZMEM', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-0000000000a6', 'MemoAdmin', 'Lab', '00000000-0000-0000-0000-0000000000a5', 'admin', 'x', '00000000-0000-0000-0000-00000000aa06');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000a7', 'MemoSancionada', 'Lab', '00000000-0000-0000-0000-0000000000a5', 'x', '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-0000000000a7', '2024-01-01', '09:00', '18:00', 60, 60,
        array[1,2,3,4,5,6], 48,
        '{"1":{"e":"09:00","s":"18:00","r":60},"2":{"e":"09:00","s":"18:00","r":60},
          "3":{"e":"09:00","s":"18:00","r":60},"4":{"e":"09:00","s":"18:00","r":60},
          "5":{"e":"09:00","s":"18:00","r":60},"6":{"e":"09:00","s":"18:00","r":60}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000aa06', true);

-- Una suspensión de tres días ya firmada y cumplida: 7, 8 y 9 de julio de 2026
-- (martes, miércoles y jueves — días laborables, así que sin esto contarían).
insert into expediente_disciplinario
  (id, correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta,
   hechos, suspension_dias, suspension_desde, suspension_hasta,
   firmante_id, firmado_at, creado_por)
values ('00000000-0000-0000-0007-000000000001', 'SU-2026-0001',
        '00000000-0000-0000-0000-0000000000a7', 'falta', 'suspension', 'firmado',
        '2026-06-01', '2026-06-30', '[{"fecha":"2026-06-15","tipo":"falta"}]'::jsonb,
        3, '2026-07-07', '2026-07-09',
        '00000000-0000-0000-0000-0000000000a6', now() - interval '20 days',
        '00000000-0000-0000-0000-0000000000a6');

select is((select fn_dia_suspendido('00000000-0000-0000-0000-0000000000a7', '2026-07-08')),
          true, 'DE PARTIDA · el 8 de julio es un día de suspensión cumplida');

-- La definición del DOCUMENTO no debe contarlo como falta.
-- Se comprueba que los días de la suspensión NO estén entre los hechos, no que
-- la lista esté vacía: la función cuenta desde esa fecha hasta hoy, y el resto de
-- días sin marcar sí son faltas de verdad.
select is((select count(*)::int
           from fn_falta_contadores('00000000-0000-0000-0000-0000000000a7', '2026-07-07') c,
                unnest(c.fechas) as f
           where f in ('2026-07-07'::date, '2026-07-08'::date, '2026-07-09'::date)),
          0, 'MEMO · los días de la suspensión ya cumplida no entran en los hechos del documento');

-- Y un día de descanso sustitutorio pactado, tampoco.
insert into feriados (fecha, nombre) values ('2026-07-28', 'Fiestas Patrias lab')
on conflict (fecha) do nothing;
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-0000000000a5', 'entrada',      '2026-07-28T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-0000000000a5', 'salida_final', '2026-07-28T18:00:00-05:00');
insert into feriados_descanso_sustitutorio
  (persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado, acta_ref, otorgado_por)
values ('00000000-0000-0000-0000-0000000000a7', '2026-07-28', '2026-07-30', 'OTORGADO', 'acta-lab-95',
        '00000000-0000-0000-0000-0000000000a6');

select is((select count(*)::int
           from fn_falta_contadores('00000000-0000-0000-0000-0000000000a7', '2026-07-30') c,
                unnest(c.fechas) as f
           where f = '2026-07-30'::date),
          0, 'MEMO · el día de descanso sustitutorio pactado tampoco es una falta en el documento');

-- Y las dos definiciones tienen que coincidir: es lo que se separó.
-- El espejo: sobre los MISMOS tres días, el documento y la pantalla tienen que
-- contar lo mismo. Es lo que se separó cuando la 0079 arregló solo una de las dos.
select is((select count(*)::int
           from fn_falta_contadores('00000000-0000-0000-0000-0000000000a7', '2026-07-07') c,
                unnest(c.fechas) as f
           where f between '2026-07-07'::date and '2026-07-09'::date),
          (select count(*)::int from fn_faltas('2026-07-07', '2026-07-09') f
            where f.persona_id = '00000000-0000-0000-0000-0000000000a7'
              and f.justificada = false),
          'ESPEJO · el documento y la pantalla cuentan las mismas faltas para los mismos días');

select * from finish();
rollback;
