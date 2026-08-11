-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 93_una_falta_no_se_sanciona_dos_veces.test.sql
-- ============================================================================
-- fn_expediente_generar_falta tiene dos caminos, y el candado de non bis in idem
-- solo vivía en uno. La rama del art. 25-h —la que se dispara al superar los
-- umbrales legales— miraba todo el histórico «hayan sido o no sancionadas» y no
-- comprobaba nada: una vez pasado el umbral, cada pulsación de «Generar
-- borrador» producía otra imputación idéntica sobre las mismas faltas, y seguía
-- funcionando indefinidamente porque esas faltas siguen dentro de los 180 días.
--
-- Sobre una persona real, eso son varias cartas de preaviso de despido por los
-- mismos hechos.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000c5', 'ZZNBI', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-0000000000c6', 'NbiAdmin', 'Lab', '00000000-0000-0000-0000-0000000000c5', 'admin', 'x', '00000000-0000-0000-0000-00000000cc06');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000c7', 'NbiFaltona', 'Lab', '00000000-0000-0000-0000-0000000000c5', 'x', '2024-01-01');

-- Horario de lunes a sábado: para que los días sin marca cuenten como falta.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-0000000000c7', '2024-01-01', '09:00', '18:00', 60, 60,
        array[1,2,3,4,5,6], 48,
        '{"1":{"e":"09:00","s":"18:00","r":60},"2":{"e":"09:00","s":"18:00","r":60},
          "3":{"e":"09:00","s":"18:00","r":60},"4":{"e":"09:00","s":"18:00","r":60},
          "5":{"e":"09:00","s":"18:00","r":60},"6":{"e":"09:00","s":"18:00","r":60}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000cc06', true);

-- Una imputación YA FIRMADA que cubre hasta el 10 de julio.
insert into expediente_disciplinario
  (id, correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta,
   hechos, firmante_id, firmado_at, medio_entrega, entregado_at, creado_por)
values ('00000000-0000-0000-0006-000000000001', 'IM-2026-0001',
        '00000000-0000-0000-0000-0000000000c7', 'falta', 'imputacion', 'entregado',
        '2026-06-01', '2026-07-10',
        '[{"fecha":"2026-06-01","tipo":"falta"}]'::jsonb,
        '00000000-0000-0000-0000-0000000000c6', now() - interval '2 days',
        'fisico', now() - interval '2 days',
        '00000000-0000-0000-0000-0000000000c6');

select is((select count(*)::int from expediente_disciplinario
           where persona_id='00000000-0000-0000-0000-0000000000c7'),
          1, 'DE PARTIDA · hay una imputación entregada que cubre hasta el 10 de julio');

-- Sin ninguna falta nueva posterior a esa fecha, no se puede volver a sancionar.
select throws_ok($$ select fn_expediente_generar_falta('00000000-0000-0000-0000-0000000000c7') $$,
                 null, null, 'SIN HECHOS NUEVOS · no se puede generar otro documento por los mismos hechos');

select is((select count(*)::int from expediente_disciplinario
           where persona_id='00000000-0000-0000-0000-0000000000c7'),
          1, 'SIN HECHOS NUEVOS · y no quedó ningún borrador suelto');

-- Repetirlo tampoco cuela: antes, cada pulsación creaba otra imputación.
select throws_ok($$ select fn_expediente_generar_falta('00000000-0000-0000-0000-0000000000c7') $$,
                 null, null, 'SIN HECHOS NUEVOS · insistir tampoco: el botón no fabrica imputaciones en serie');

select is((select count(*)::int from expediente_disciplinario
           where persona_id='00000000-0000-0000-0000-0000000000c7' and nivel='imputacion'),
          1, 'SIN HECHOS NUEVOS · sigue habiendo UNA imputación, no tres');

select * from finish();
rollback;
