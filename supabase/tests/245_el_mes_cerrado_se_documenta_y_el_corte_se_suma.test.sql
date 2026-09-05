-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 245_el_mes_cerrado_se_documenta_y_el_corte_se_suma.test.sql
-- ============================================================================
-- El numeral 19.4 del Reglamento dice que el cierre del mes «no impide emitir
-- el documento» por hechos de un mes concluido. El sistema lo impedía: el día 1
-- de cada mes el contador de todos volvía a cero y el mes que acababa de cerrar
-- se volvía indocumentable para siempre. Doce veces al año, sin ningún aviso.
--
-- Y el filtro fundía DOS reglas en una sola fecha:
--
--     j.fecha >= greatest(date_trunc('month', fn_hoy_lima())::date, v_cutoff + 1)
--
-- `greatest` se queda con UNA, así que la otra dejaba de trabajar: el corte por
-- antecedente SUSTITUÍA al corte mensual en vez de sumarse.
--
-- Estas seis pruebas fijan lo que hasta hoy no verificaba nada: qué ESCRIBE el
-- generador —periodo y hechos, no solo que no reviente— y qué días cuenta.
--
-- Todas las fechas van relativas a `fn_hoy_lima()`: el mes pasado está cerrado
-- cualquier día que se corra la prueba, y ese es el caso que importa.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000e4501', 'ZZ45M', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000e4502', 'AdminMes', 'Lab',
        '00000000-0000-0000-0000-0000000e4501', 'admin', 'x',
        '00000000-0000-0000-0000-00000e450002', '2020-01-01', 'activo', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000e4503', 'LlegaTarde', 'Lab',
        '00000000-0000-0000-0000-0000000e4501', 'x', '2020-01-01', 'activo', 'planilla');

-- Horario de los siete días, igual que en la 230: el CASO B escala a
-- suspensión (segunda vez tras una amonestación), y `fn_dias_suspension`
-- (0075) se niega si la persona no tiene horario vigente — sin él no sabe qué
-- días son laborables. Los siete días evitan que el resultado dependa del día
-- de la semana en que se corra la prueba.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values
  ('00000000-0000-0000-0000-0000000e4503', '2020-01-01', '09:00', '18:00', 60, 60,
   array[0,1,2,3,4,5,6], 45);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000e450002', true);

-- ── Atajos de fechas ────────────────────────────────────────────────────────
create function pg_temp.mes_ant() returns date language sql stable as $$
  select (date_trunc('month', fn_hoy_lima()) - interval '1 month')::date;
$$;
create function pg_temp.mes_ant2() returns date language sql stable as $$
  select (date_trunc('month', fn_hoy_lima()) - interval '2 months')::date;
$$;

-- Una tardanza medible y no justificada el día que se le diga.
create function pg_temp.tarde(p_fecha date) returns void language sql as $$
  insert into jornadas (persona_id, fecha, sede_id, minutos_tarde, horas_trabajadas, estado)
  values ('00000000-0000-0000-0000-0000000e4503', p_fecha,
          '00000000-0000-0000-0000-0000000e4501', 12, 8.0, 'cerrada');
$$;

-- Un documento entregado que cubre hasta `p_hasta` y cita los días de `p_dias`.
-- `p_entregado` permite fabricar el caso del documento CADUCADO.
create function pg_temp.entregado(p_desde date, p_hasta date, p_dias date[], p_entregado timestamptz)
returns void language sql as $$
  insert into expediente_disciplinario
    (persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
     firmante_id, firmado_at, medio_entrega, entregado_at, correlativo, creado_por)
  values ('00000000-0000-0000-0000-0000000e4503', 'tardanza', 'amonestacion', 'entregado',
          p_desde, p_hasta,
          coalesce((select jsonb_agg(jsonb_build_object('fecha', d, 'minutos', 12))
                      from unnest(p_dias) d), '[]'::jsonb),
          '00000000-0000-0000-0000-0000000e4502', p_entregado, 'fisico', p_entregado,
          'M45-' || coalesce(p_hasta::text, 'sin') || '-' || p_entregado::text,
          '00000000-0000-0000-0000-0000000e4502');
$$;

-- Entre caso y caso: el generador se niega si ya hay un borrador pendiente.
create function pg_temp.limpiar() returns void language sql as $$
  delete from expediente_disciplinario
   where persona_id = '00000000-0000-0000-0000-0000000e4503' and estado = 'borrador';
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- CASO A · El mes cerrado se puede documentar (numeral 19.4)
-- ════════════════════════════════════════════════════════════════════════════
-- Tres tardanzas en el mes pasado y ninguna en el mes en curso. Es exactamente
-- lo que ve Desarrollo Organizacional el día 1: la persona llegó tarde tres
-- veces y el sistema decía «lleva 0».
select pg_temp.tarde(pg_temp.mes_ant() + 4);
select pg_temp.tarde(pg_temp.mes_ant() + 9);
select pg_temp.tarde(pg_temp.mes_ant() + 14);

select throws_ok(
  $$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e4503') $$,
  null,
  'ART. 19.1 a) · sin decir el mes se mira el mes EN CURSO, donde no hay nada que reprochar');

select lives_ok(
  format($$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e4503', %L) $$,
         pg_temp.mes_ant()),
  'ART. 19.4 · el cierre del mes NO impide emitir el documento del mes anterior');

select is(
  (select periodo_desde from expediente_disciplinario
    where persona_id = '00000000-0000-0000-0000-0000000e4503' and estado = 'borrador'),
  pg_temp.mes_ant() + 4,
  'ART. 19.4 · y el documento cubre el MES DOCUMENTADO, no el mes en curso');

select is(
  (select jsonb_array_length(hechos) from expediente_disciplinario
    where persona_id = '00000000-0000-0000-0000-0000000e4503' and estado = 'borrador'),
  3,
  'ART. 19.2 b) · con las tres tardanzas de ese mes citadas una por una');

select pg_temp.limpiar();

-- ════════════════════════════════════════════════════════════════════════════
-- CASO B · El corte SE SUMA al mes; no lo sustituye
-- ════════════════════════════════════════════════════════════════════════════
-- Un documento anterior cubre hasta el día 10 del mes pasado. Hay tardanzas
-- antes de ese corte (ya reprochadas), después (nuevas) y en el mes de antes
-- (fuera de la ventana). Solo las dos nuevas del mes documentado deben contar.
select pg_temp.tarde(pg_temp.mes_ant2() + 19);            -- otro mes: fuera
select pg_temp.tarde(pg_temp.mes_ant() + 19);             -- nueva
select pg_temp.tarde(pg_temp.mes_ant() + 24);             -- nueva
select pg_temp.tarde(pg_temp.mes_ant() + 27);             -- nueva
-- Cubre hasta el día 15 y cita los tres días del caso A: así el corte tapa
-- exactamente lo ya reprochado y lo único nuevo son las dos tardanzas de abajo.
select pg_temp.entregado(pg_temp.mes_ant(), pg_temp.mes_ant() + 14,
                         array[pg_temp.mes_ant() + 4, pg_temp.mes_ant() + 9,
                               pg_temp.mes_ant() + 14], now() - interval '1 day');

-- El documento anterior se entregó AYER, o sea después del mes que se está
-- documentando. Por el numeral 19.1 c) no agrava —cuando ocurrieron los hechos
-- de ese mes, la persona no lo tenía encima— y por eso el escalón sigue siendo
-- la amonestación de tres. Pero su CORTE sí protege: son dos reglas distintas y
-- esta prueba las separa a propósito.
select lives_ok(
  format($$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e4503', %L) $$,
         pg_temp.mes_ant()),
  'ART. 19.1 b) · con tres tardanzas nuevas tras el documento anterior, sí corresponde');

select is(
  (select hechos from expediente_disciplinario
    where persona_id = '00000000-0000-0000-0000-0000000e4503' and estado = 'borrador'),
  jsonb_build_array(
    jsonb_build_object('fecha', to_jsonb(pg_temp.mes_ant() + 19), 'minutos', 12),
    jsonb_build_object('fecha', to_jsonb(pg_temp.mes_ant() + 24), 'minutos', 12),
    jsonb_build_object('fecha', to_jsonb(pg_temp.mes_ant() + 27), 'minutos', 12)),
  'ART. 19.1 a) + 56.6 · las DOS condiciones se suman: ni lo de otro mes ni lo ya reprochado');

select pg_temp.limpiar();

-- ════════════════════════════════════════════════════════════════════════════
-- CASO C · Los meses se emiten del más viejo al más nuevo (numeral 56.6)
-- ════════════════════════════════════════════════════════════════════════════
select throws_ok(
  format($$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e4503', %L) $$,
         pg_temp.mes_ant2()),
  null,
  'NUM. 56.6 · entregado un documento, un mes ANTERIOR ya no se puede documentar');

-- ════════════════════════════════════════════════════════════════════════════
-- CASO D · El corte NO caduca (numeral 52.5)
-- ════════════════════════════════════════════════════════════════════════════
-- El agravante de los doce meses caduca; el non bis in idem no. Un documento
-- entregado hace trece meses ya no agrava, pero sus días siguen sin poder
-- volver a contarse. Antes el corte salía solo de los documentos VIGENTES, así
-- que al caducar uno, sus días volvían al conteo.
delete from expediente_disciplinario where persona_id = '00000000-0000-0000-0000-0000000e4503';
delete from jornadas where persona_id = '00000000-0000-0000-0000-0000000e4503';

select pg_temp.tarde(pg_temp.mes_ant() + 4);
select pg_temp.tarde(pg_temp.mes_ant() + 9);
select pg_temp.tarde(pg_temp.mes_ant() + 14);
select pg_temp.entregado(pg_temp.mes_ant(), pg_temp.mes_ant() + 20,
                         array[pg_temp.mes_ant() + 4, pg_temp.mes_ant() + 9, pg_temp.mes_ant() + 14],
                         now() - interval '13 months');

select throws_ok(
  format($$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e4503', %L) $$,
         pg_temp.mes_ant()),
  null,
  'NUM. 52.5 · un documento caducado como antecedente sigue impidiendo recontar sus días');

-- ════════════════════════════════════════════════════════════════════════════
-- CASO E · La guardia nominal, cuando el corte no puede proteger
-- ════════════════════════════════════════════════════════════════════════════
-- `periodo_hasta` es NULLABLE y `fn_expediente_crear_borrador` lo deja en null.
-- Con un documento así el corte vale null y no protege NADA: lo único que queda
-- en pie es la lista nominal de días citados en `hechos`.
delete from expediente_disciplinario where persona_id = '00000000-0000-0000-0000-0000000e4503';

select pg_temp.entregado(null, null,
                         array[pg_temp.mes_ant() + 4, pg_temp.mes_ant() + 9, pg_temp.mes_ant() + 14],
                         now() - interval '1 day');

select throws_ok(
  format($$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e4503', %L) $$,
         pg_temp.mes_ant()),
  null,
  'ART. 52.5 · sin periodo declarado, los días citados en el documento igual no se recuentan');

select is(
  (select fn_tardanza_ya_documentada('00000000-0000-0000-0000-0000000e4503', pg_temp.mes_ant() + 4)),
  true,
  'ART. 52.5 · y la guardia lo dice por su cuenta, día por día');

-- ════════════════════════════════════════════════════════════════════════════
-- CASO F · No se documenta un mes que no ha empezado
-- ════════════════════════════════════════════════════════════════════════════
select throws_ok(
  format($$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e4503', %L) $$,
         (date_trunc('month', fn_hoy_lima()) + interval '1 month')::date),
  null,
  'Un mes que todavía no ha empezado no se puede documentar');

select * from finish();
rollback;
