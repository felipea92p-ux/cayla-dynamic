-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 491_las_pantallas_se_enteran_al_instante.test.sql  (migración 0604)
-- ============================================================================
-- Tres cosas, en este orden de importancia:
--
--   1. EL GUARDIÁN. Toda tabla de `public` tiene una decisión de tiempo real:
--      vigilada (avisa a un tema), pendiente de un lote, o excluida con su
--      motivo. Una tabla NUEVA sin decisión hace fallar esta prueba. Si te
--      frenó a ti, no es un error de tu migración: decide qué pasa con tu
--      tabla y anótala en la lista de abajo. Si una pantalla la muestra y otra
--      persona la cambia, vigílala:
--          select fn_tiempo_real_vigilar('public.tu_tabla', 'tema');
--      en tu migración, y súmala a `vigiladas`. Si nadie la ve cambiar en vivo
--      (un registro interno, una cola), súmala a `excluidas` con el porqué.
--      Sin esta prueba, una tabla nueva quedaría sin aviso y su pantalla
--      volvería en silencio a ponerse al día cada 5 min.
--   2. LO QUE DECIDE EL TRIGGER: un aviso por sentencia, uno por tema y por
--      transacción, ninguno si no tocó filas, y nunca frena un guardado.
--   3. QUIÉN ESCUCHA: panel y terminal sí; integrantes, terminales dados de
--      baja y temas desconocidos, no. Y nadie manda avisos desde la API.
--
-- En CI no hay Realtime (`supabase db start` deja el esquema `realtime`
-- vacío), así que las dos aserciones que lo necesitan pasan diciendo «no
-- aplica». Contra una base con Realtime (la pila completa) sí se comprueban.
-- ============================================================================
begin;
select plan(33);

-- ── Las decisiones: cada tabla de public, una sola vez ──────────────────────
create temp table decision (tabla text primary key, estado text not null, tema text);
insert into decision (tabla, estado, tema) values
  -- VIGILADAS (lote 1, 0604). Asistencia: lo que pasó en el piso.
  ('marcajes', 'vigilada', 'asistencia'),
  ('jornadas', 'vigilada', 'asistencia'),
  ('cambios_ubicacion', 'vigilada', 'asistencia'),
  ('marcas_apartadas', 'vigilada', 'asistencia'),
  ('ausencias', 'vigilada', 'asistencia'),
  ('tardanzas_justificadas', 'vigilada', 'asistencia'),
  ('incidencias_aceptadas', 'vigilada', 'asistencia'),
  ('revisiones_pedidas', 'vigilada', 'asistencia'),
  -- Horarios: lo que se planificó.
  ('turnos', 'vigilada', 'horarios'),
  ('horarios_asignados', 'vigilada', 'horarios'),
  ('turnos_borradores', 'vigilada', 'horarios'),
  ('turnos_borrador_dias', 'vigilada', 'horarios'),
  ('turnos_borrador_notas', 'vigilada', 'horarios'),
  ('metas_cobertura', 'vigilada', 'horarios'),
  ('metas_cobertura_periodos', 'vigilada', 'horarios'),
  ('metas_cobertura_rangos', 'vigilada', 'horarios'),
  ('puestos_base', 'vigilada', 'horarios'),
  ('puestos_planificados', 'vigilada', 'horarios'),
  ('disponibilidades', 'vigilada', 'horarios'),
  ('disponibilidad_bloques', 'vigilada', 'horarios'),
  ('feriados', 'vigilada', 'horarios'),
  -- Personas.
  ('personas', 'vigilada', 'personas'),

  -- PENDIENTES DEL LOTE 2: solicitudes, Bandeja, Correcciones, reportes.
  ('solicitudes_vacaciones', 'lote 2', null), ('solicitudes_cambio_perfil', 'lote 2', null),
  ('turno_cambios', 'lote 2', null), ('turno_pedidos', 'lote 2', null),
  ('reportes', 'lote 2', null), ('reporte_adjuntos', 'lote 2', null), ('reporte_eventos', 'lote 2', null),
  ('reporte_medidas', 'lote 2', null), ('reporte_mensajes', 'lote 2', null), ('reporte_personas', 'lote 2', null),
  ('reporte_plazos', 'lote 2', null), ('alertas', 'lote 2', null), ('mensajes_encargada', 'lote 2', null),
  ('actas_descanso_sustitutorio', 'lote 2', null), ('feriados_descanso_sustitutorio', 'lote 2', null),
  ('movilidad_revisiones_pedidas', 'lote 2', null), ('bandeja_vistos', 'lote 2', null),

  -- PENDIENTES DEL LOTE 3: personas, documentos, educación, seguros y catálogos.
  ('datos_personales', 'lote 3', null), ('derechohabientes', 'lote 3', null),
  ('contratos_generados', 'lote 3', null), ('confirmaciones_firma_contrato', 'lote 3', null),
  ('contrato_revisiones_pedidas', 'lote 3', null), ('documentos_acuses', 'lote 3', null),
  ('documentos_firmados', 'lote 3', null), ('documentos_institucionales', 'lote 3', null),
  ('documentos_tipos', 'lote 3', null), ('firmas_escaneadas', 'lote 3', null),
  ('consentimientos_datos_personales', 'lote 3', null), ('aceptaciones_terminos', 'lote 3', null),
  ('invitaciones_cuenta', 'lote 3', null), ('pruebas', 'lote 3', null), ('terminales', 'lote 3', null),
  ('catalogo_campos_perfil', 'lote 3', null), ('anuncios', 'lote 3', null), ('anuncios_leidos', 'lote 3', null),
  ('archivo_empresa', 'lote 3', null), ('novedades_vistas', 'lote 3', null),
  ('objetivos_items', 'lote 3', null), ('objetivos_mensuales', 'lote 3', null), ('rendimiento_mensual', 'lote 3', null),
  ('educacion_avisos_fin', 'lote 3', null), ('educacion_comprobantes', 'lote 3', null),
  ('educacion_entrega_archivos', 'lote 3', null), ('educacion_entrega_meses', 'lote 3', null),
  ('educacion_entregas', 'lote 3', null), ('educacion_solicitudes', 'lote 3', null),
  ('asignaciones_educacion', 'lote 3', null), ('topes_educacion_rango', 'lote 3', null),
  ('seguros_asignaciones', 'lote 3', null), ('seguros_cambios', 'lote 3', null), ('seguros_tipos', 'lote 3', null),
  ('polizas_seguro', 'lote 3', null), ('polizas_seguro_archivos', 'lote 3', null), ('polizas_seguro_eventos', 'lote 3', null),
  ('sedes', 'lote 3', null), ('areas', 'lote 3', null), ('tipos_ausencia', 'lote 3', null),

  -- PENDIENTES DEL LOTE 4: plata y disciplina (con aviso en pantalla, no refresco solo).
  ('boletas', 'lote 4', null), ('boletas_acuses', 'lote 4', null), ('boletas_anulaciones', 'lote 4', null),
  ('boletas_partes', 'lote 4', null), ('boletas_versiones', 'lote 4', null),
  ('planilla_pagada_detalle', 'lote 4', null), ('planilla_pago_persona_eventos', 'lote 4', null),
  ('periodos_planilla', 'lote 4', null), ('periodo_grupo_pago', 'lote 4', null), ('periodos_eliminados', 'lote 4', null),
  ('movimientos_planilla', 'lote 4', null), ('liquidacion_constancias', 'lote 4', null), ('liquidacion_pagada', 'lote 4', null),
  ('desembolsos_beneficios', 'lote 4', null), ('reversas_pago', 'lote 4', null),
  ('asignaciones_salario', 'lote 4', null), ('asignaciones_regimen_pension', 'lote 4', null),
  ('tarifas_hora', 'lote 4', null), ('tasas_pension', 'lote 4', null), ('bonos_umbral_permitido', 'lote 4', null),
  ('etiquetas_complemento', 'lote 4', null), ('factores_categoria', 'lote 4', null), ('categorias_laborales', 'lote 4', null),
  ('politica_salarial', 'lote 4', null), ('politica_salarial_acuses', 'lote 4', null),
  ('seguimiento_planilla_por_solicitud', 'lote 4', null), ('parametros_catalogo', 'lote 4', null),
  ('parametros_laborales', 'lote 4', null), ('parametros_vigencias', 'lote 4', null), ('configuracion', 'lote 4', null),
  ('expediente_disciplinario', 'lote 4', null), ('expediente_adjuntos', 'lote 4', null), ('expediente_traspasos', 'lote 4', null),
  ('descargos_presentados', 'lote 4', null), ('cargos_recomunicados', 'lote 4', null), ('recepciones_cargos', 'lote 4', null),
  ('lecturas_memo', 'lote 4', null), ('faltas_catalogo', 'lote 4', null), ('faltas_rotulos', 'lote 4', null),
  ('organos_titulo_x', 'lote 4', null),

  -- EXCLUIDAS: nadie las ve cambiar en vivo, o su cambio ya avisa por otra tabla.
  ('migraciones_aplicadas', 'excluida', null),            -- el registro de lo que se pegó
  ('google_sheets_sync_queue', 'excluida', null),         -- la cola interna del espejo a Sheets
  ('funciones_nunca_para_authenticated', 'excluida', null), -- lista de control de permisos que lee una prueba
  ('expediente_correlativo_seq', 'excluida', null),       -- el contador interno de correlativos
  ('push_tokens', 'excluida', null),                      -- tokens de dispositivo; no se muestran
  ('correcciones_auditoria', 'excluida', null),           -- se escribe junto con la corrección, que ya avisa
  ('parametros_historial', 'excluida', null);             -- se escribe junto con el cambio de `configuracion`

-- ── 1–4. Las cuatro funciones ───────────────────────────────────────────────
select ok(to_regprocedure('fn_tiempo_real_enviar(text)') is not null, 'existe fn_tiempo_real_enviar(text)');
select ok(to_regprocedure('fn_tiempo_real_avisar()') is not null, 'existe fn_tiempo_real_avisar()');
select ok(to_regprocedure('fn_tiempo_real_vigilar(regclass,text)') is not null, 'existe fn_tiempo_real_vigilar(regclass, text)');
select ok(to_regprocedure('fn_tiempo_real_puede_escuchar(text)') is not null, 'existe fn_tiempo_real_puede_escuchar(text)');

-- ── 5–8. El guardián ─────────────────────────────────────────────────────────
create temp view vigiladas_en_la_base as
  select c.relname::text as tabla, max(replace(encode(t.tgargs, 'escape'), '\000', '')) as tema
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and t.tgname in ('tiempo_real_al_insertar', 'tiempo_real_al_actualizar', 'tiempo_real_al_borrar')
   group by c.relname
  having count(*) = 3 and count(distinct t.tgargs) = 1;

select set_eq(
  $$ select tabla, tema from vigiladas_en_la_base $$,
  $$ select tabla, tema from decision where estado = 'vigilada' $$,
  'GUARDIÁN · cada tabla vigilada tiene sus tres triggers y su tema, y no hay otras');

select is_empty(
  $$ select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
        and c.relname::text not in (select tabla from decision) $$,
  'GUARDIÁN · toda tabla de public tiene decisión de tiempo real (si sale tu tabla, léete el encabezado de este archivo)');

select is_empty(
  $$ select c.relname::text from pg_trigger t join pg_class c on c.oid = t.tgrelid
      where t.tgname like 'tiempo_real_al_%'
        and c.relname::text not in (select tabla from decision where estado = 'vigilada') $$,
  'GUARDIÁN · ninguna tabla fuera de la lista lleva triggers de tiempo real a medias');

select is_empty(
  $$ select tabla from decision where to_regclass('public.' || tabla) is null $$,
  'GUARDIÁN · la lista no nombra tablas que ya no existen');

-- ── 9–10. Con Realtime de verdad (en CI, «no aplica») ───────────────────────
create function pg_temp.con_realtime(p_sql text, p_desc text) returns text language plpgsql as $$
declare v boolean;
begin
  if to_regclass('realtime.messages') is null or to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    return pass(p_desc || ' — esta base no tiene Realtime: no aplica');
  end if;
  execute p_sql into v;
  return ok(v, p_desc);
end $$;

select pg_temp.con_realtime(
  $$ select exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages'
                      and policyname = 'tiempo_real_escuchar' and cmd = 'SELECT') $$,
  'REALTIME · existe la política de lectura tiempo_real_escuchar');

select pg_temp.con_realtime(
  $$ with env as (select fn_tiempo_real_enviar('asistencia'))
     select (select count(*) from env) = 1
        and exists (select 1 from realtime.messages m
                     where m.topic = 'dynamic:asistencia' and m.private and m.extension = 'broadcast'
                       and m.event = 'cambio' and m.inserted_at >= now()
                       and (select array_agg(k order by k) from jsonb_object_keys(m.payload) k) = array['id', 'tema']
                       and m.payload->>'tema' = 'asistencia') $$,
  'REALTIME · el aviso es privado y lleva SOLO el tema (y el id que pone Supabase): ningún dato de nadie');

-- ── Personas de prueba ───────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000049101', 'ZZRT1', 'Sede de laboratorio RT', true),
  ('00000000-0000-0000-0000-000000049102', 'ZZRT2', 'Sede de laboratorio RT 2', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000049111', 'RtAdmin',    'Lab', '00000000-0000-0000-0000-000000049101', 'admin',           'x', '00000000-0000-0000-0000-000000049211', '2024-01-15', 'planilla'),
  ('00000000-0000-0000-0000-000000049112', 'RtDo',       'Lab', '00000000-0000-0000-0000-000000049101', 'lider_do',        'x', '00000000-0000-0000-0000-000000049212', '2024-01-15', 'planilla'),
  ('00000000-0000-0000-0000-000000049113', 'RtLider',    'Lab', '00000000-0000-0000-0000-000000049101', 'supervisor_sede', 'x', '00000000-0000-0000-0000-000000049213', '2024-01-15', 'planilla'),
  ('00000000-0000-0000-0000-000000049114', 'RtIntegra',  'Lab', '00000000-0000-0000-0000-000000049101', 'integrante',      'x', '00000000-0000-0000-0000-000000049214', '2024-01-15', 'planilla'),
  -- Sin cuenta, como las que hay de verdad: es la única que se ACTUALIZA abajo. Una
  -- fila insertada en esta misma transacción con los triggers apagados vuelve a
  -- comprobar su llave foránea al actualizarse, aunque la llave no cambie; con
  -- `auth_user_id` nulo no hay nada que comprobar contra auth.users.
  ('00000000-0000-0000-0000-000000049115', 'RtSinCuenta','Lab', '00000000-0000-0000-0000-000000049101', 'integrante',      'x', null,                                   '2024-01-15', 'planilla');
insert into terminales (id, sede_id, nombre_dispositivo, auth_user_id, activo) values
  ('00000000-0000-0000-0000-000000049121', '00000000-0000-0000-0000-000000049101', 'Mac mini RT',          '00000000-0000-0000-0000-000000049221', true),
  ('00000000-0000-0000-0000-000000049122', '00000000-0000-0000-0000-000000049102', 'Mac mini RT de baja',  '00000000-0000-0000-0000-000000049222', false);
set session_replication_role = origin;

-- ── 11–19. Lo que decide el trigger ──────────────────────────────────────────
-- Se cambia el envío por un registro para ver CUÁNTAS veces y A QUÉ TEMA
-- avisaría, sin depender de Realtime. Se deshace con el rollback del final.
create table _avisos_491 (n serial primary key, tema text not null);
create or replace function fn_tiempo_real_enviar(p_tema text) returns void
  language sql security definer set search_path = public, pg_temp
  as $$ insert into _avisos_491 (tema) values (p_tema) $$;

-- Una transacción nueva, a ojos del trigger: se borra la marca de «ya avisé».
create function pg_temp.nueva_transaccion() returns void language sql as $$
  select set_config('dynamic.tiempo_real_asistencia', '', true),
         set_config('dynamic.tiempo_real_horarios', '', true),
         set_config('dynamic.tiempo_real_personas', '', true);
  delete from _avisos_491;
$$;

select pg_temp.nueva_transaccion();
update personas set nombres = nombres where id = '00000000-0000-0000-0000-000000049115';
select is((select count(*)::int from _avisos_491 where tema = 'personas'), 1,
  'TRIGGER · cambiar una persona avisa una vez al tema personas');

update personas set apellidos = apellidos where id = '00000000-0000-0000-0000-000000049115';
select is((select count(*)::int from _avisos_491 where tema = 'personas'), 1,
  'TRIGGER · un segundo cambio en la MISMA transacción no vuelve a avisar');

select pg_temp.nueva_transaccion();
update personas set nombres = nombres where false;
delete from feriados where fecha = '2099-12-31';
select is((select count(*)::int from _avisos_491), 0,
  'TRIGGER · una sentencia que no tocó ninguna fila no avisa (el cierre automático cada 15 min)');

select pg_temp.nueva_transaccion();
insert into feriados (fecha, nombre) values ('2099-12-31', 'Feriado de laboratorio RT');
select is((select count(*)::int from _avisos_491 where tema = 'horarios'), 1,
  'TRIGGER · insertar avisa (feriados → horarios)');

select pg_temp.nueva_transaccion();
delete from feriados where fecha = '2099-12-31';
select is((select count(*)::int from _avisos_491 where tema = 'horarios'), 1,
  'TRIGGER · borrar avisa (feriados → horarios)');

select pg_temp.nueva_transaccion();
insert into feriados (fecha, nombre)
  select date '2090-01-01' + g, 'Feriado masivo RT ' || g from generate_series(0, 499) g;
select is((select count(*)::int from _avisos_491 where tema = 'horarios'), 1,
  'TRIGGER · 500 filas en una sola sentencia son UN aviso, no 500');

select pg_temp.nueva_transaccion();
update personas set nombres = nombres where id = '00000000-0000-0000-0000-000000049115';
update feriados set nombre = nombre where fecha = date '2090-01-01';
select is((select string_agg(tema, ',' order by tema) from (select distinct tema from _avisos_491) t), 'horarios,personas',
  'TRIGGER · dos temas en una transacción: un aviso a cada uno');

-- Si Realtime revienta, el guardado NO se cae.
create or replace function fn_tiempo_real_enviar(p_tema text) returns void
  language plpgsql security definer set search_path = public, pg_temp
  as $$ begin raise exception 'Realtime caído (simulado)'; end $$;
select pg_temp.nueva_transaccion();
select lives_ok(
  $$ update personas set nombres = 'RtSinCuentaCambiada' where id = '00000000-0000-0000-0000-000000049115' $$,
  'TRIGGER · si el aviso falla, el cambio se guarda igual');
select is((select nombres from personas where id = '00000000-0000-0000-0000-000000049115'), 'RtSinCuentaCambiada',
  'TRIGGER · … y el cambio quedó de verdad');

-- ── 20–28. Quién puede escuchar ──────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049211', true);
select is(fn_tiempo_real_puede_escuchar('dynamic:asistencia'), true, 'ESCUCHA · administración escucha asistencia');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049212', true);
select is(fn_tiempo_real_puede_escuchar('dynamic:horarios'), true, 'ESCUCHA · Líder DO escucha horarios');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049213', true);
select is(fn_tiempo_real_puede_escuchar('dynamic:personas'), true,
  'ESCUCHA · la líder de equipo escucha personas (fn_es_admin_o_lider la habría dejado afuera)');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049221', true);
select is(fn_tiempo_real_puede_escuchar('dynamic:asistencia'), true, 'ESCUCHA · la Mac mini activa de una sede escucha asistencia');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049214', true);
select is(fn_tiempo_real_puede_escuchar('dynamic:asistencia'), false, 'ESCUCHA · una integrante NO (lo suyo es el lote 5)');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049222', true);
select is(fn_tiempo_real_puede_escuchar('dynamic:asistencia'), false, 'ESCUCHA · un terminal dado de baja NO');
select set_config('request.jwt.claim.sub', '', true);
select is(fn_tiempo_real_puede_escuchar('dynamic:asistencia'), false, 'ESCUCHA · sin sesión NO');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049211', true);
select is(fn_tiempo_real_puede_escuchar('dynamic:planilla'), false,
  'ESCUCHA · un tema que la función no conoce queda cerrado, aun para administración');
select is(fn_tiempo_real_puede_escuchar(null), false, 'ESCUCHA · sin tema, NO (false, no null)');

-- ── 29–33. Nadie manda avisos desde la API ───────────────────────────────────
select is(has_function_privilege('authenticated', 'fn_tiempo_real_enviar(text)', 'execute'), false,
  'PERMISOS · una sesión no puede mandar avisos (haría releer a todas las pantallas sin parar)');
select is(has_function_privilege('authenticated', 'fn_tiempo_real_vigilar(regclass,text)', 'execute'), false,
  'PERMISOS · una sesión no puede poner triggers');
select is(has_function_privilege('anon', 'fn_tiempo_real_puede_escuchar(text)', 'execute'), false,
  'PERMISOS · sin cuenta no se pregunta quién escucha');
select is(has_function_privilege('authenticated', 'fn_tiempo_real_puede_escuchar(text)', 'execute'), true,
  'PERMISOS · una sesión sí puede (Realtime evalúa la política con su rol)');
select throws_ok(
  $$ select fn_tiempo_real_vigilar('public.feriados', 'Horarios De Hoy') $$,
  null, null, 'VIGILAR · un tema con mayúsculas o espacios se rechaza');

select * from finish();
rollback;
