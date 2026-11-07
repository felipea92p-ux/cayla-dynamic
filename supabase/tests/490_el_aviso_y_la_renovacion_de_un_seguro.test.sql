-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- ============================================================================
-- 490_el_aviso_y_la_renovacion_de_un_seguro.test.sql — la 0602 y la 0603
-- ============================================================================
-- Lo que hay que proteger:
-- (a) cada persona lee solo lo suyo, sin factura, sin archivo retirado y sin póliza anulada;
-- (b) una póliza colectiva da UN correo por destinatario de DO, no uno por asegurada;
-- (c) lo que ya tiene renovación no avisa, y repetir el cron no duplica;
-- (d) el correo le llega a DO y no a la líder de equipo de cada asegurada;
-- (e) registrar la renovación apaga el aviso que todavía no salió, y los dos tramos son dos avisos.
-- ============================================================================
begin;
select plan(25);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000006000001', 'ZZ600', 'Sede seguros 600', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo, practicante_modalidad, estado, cuenta_de_servicio, fecha_cese, email) values
  ('00000000-0000-0000-0000-00000600a001', 'AdmSeg', 'Lab', '00000000-0000-0000-0000-000006000001', 'admin',           'x', '00000000-0000-0000-0000-00000600b001', '2024-01-01', 'planilla',    'Admin', null, 'activo', false, null, 'adm600@prueba.local'),
  ('00000000-0000-0000-0000-00000600a002', 'Ana',    'Seg', '00000000-0000-0000-0000-000006000001', 'integrante',      'x', '00000000-0000-0000-0000-00000600b002', '2024-01-01', 'planilla',    'Asesora', null, 'activo', false, null, null),
  ('00000000-0000-0000-0000-00000600a003', 'Beto',   'Seg', '00000000-0000-0000-0000-000006000001', 'integrante',      'x', '00000000-0000-0000-0000-00000600b003', '2024-01-01', 'planilla',    'Asesor', null, 'activo', false, null, null),
  ('00000000-0000-0000-0000-00000600a004', 'Lidia',  'Seg', '00000000-0000-0000-0000-000006000001', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000600b004', '2024-01-01', 'planilla',    'Líder', null, 'activo', false, null, 'lider600@prueba.local'),
  ('00000000-0000-0000-0000-00000600a005', 'Caro',   'Seg', '00000000-0000-0000-0000-000006000001', 'integrante',      'x', '00000000-0000-0000-0000-00000600b005', '2024-01-01', 'practicante', 'Practicante', 'profesional', 'activo', false, null, null);
-- Lo que ya tenga la base no cuenta aquí: ni otro DO con correo, ni otras pólizas.
update personas set email = null where rol in ('admin', 'lider_do') and id <> '00000000-0000-0000-0000-00000600a001';
delete from polizas_seguro_eventos;
delete from polizas_seguro;
set session_replication_role = origin;

insert into storage.objects (bucket_id, name, metadata) values
  ('polizas-seguro', '6b000000-0000-0000-0000-0000000000a1.pdf', '{"size": 1000, "mimetype": "application/pdf"}'),
  ('polizas-seguro', '6b000000-0000-0000-0000-0000000000a2.pdf', '{"size": 1000, "mimetype": "application/pdf"}');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000600b001', true);

-- Una Vida Ley colectiva de dos personas, por vencer en 30 días.
create temp table _colectiva as select * from fn_seguro_registrar_varias(
  array['00000000-0000-0000-0000-00000600a002', '00000000-0000-0000-0000-00000600a003']::uuid[], 'vida_ley', 'Pacífico Seguros', 'VL-600',
  fn_hoy_lima() - 60, fn_hoy_lima() + 30, 14.5, null, null, null, null, null, null);
-- FOLA de Caro: por vencer en 10 días, pero con renovación que empalma. No debe avisar.
select fn_seguro_registrar('00000000-0000-0000-0000-00000600a005', 'salud_practicantes', 'Pacífico Seguros', 'FOLA-600A',
  fn_hoy_lima() - 80, fn_hoy_lima() + 10, 179.97, null, null, null, null, null, null);
select fn_seguro_registrar('00000000-0000-0000-0000-00000600a005', 'salud_practicantes', 'Pacífico Seguros', 'FOLA-600B',
  fn_hoy_lima() + 10, fn_hoy_lima() + 100, 179.97, null, null, null, null, null, null);

select set_config('t.ana', (select poliza_id::text from _colectiva where persona_id = '00000000-0000-0000-0000-00000600a002'), true);
select set_config('t.pdf', fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'poliza', '6b000000-0000-0000-0000-0000000000a1.pdf', 'poliza.pdf')::text, true);
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'factura', '6b000000-0000-0000-0000-0000000000a2.pdf', 'factura.pdf');

-- ── A · Lo que lee cada persona (0602) ──────────────────────────────────────
select is(
  (select pg_get_function_result(p.oid) from pg_proc p where p.proname = 'fn_mis_polizas_avisos'),
  'TABLE(poliza_id uuid, producto_nombre text, creada_at timestamp with time zone, archivo_id uuid, archivo_subido_at timestamp with time zone)',
  'fn_mis_polizas_avisos devuelve estas cinco columnas y ninguna más: ni prima, ni nombre de archivo');
select ok(not has_function_privilege('anon', 'fn_mis_polizas_avisos()', 'execute'), 'quien no inició sesión no la llama');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000600b002', true);
select is((select count(*)::int from fn_mis_polizas_avisos()), 1, 'Ana ve su póliza y ninguna de otra persona');
select is((select archivo_id::text from fn_mis_polizas_avisos()), current_setting('t.pdf'), 'su último archivo visible es la póliza: la factura, aunque sea más nueva, no');
select lives_ok($q$ select fn_bandeja_marcar_visto('poliza_mia', current_setting('t.pdf')::uuid) $q$, 'la Bandeja acepta el tipo nuevo');
select is((select count(*)::int from bandeja_vistos where tipo_item = 'poliza_mia' and persona_id = '00000000-0000-0000-0000-00000600a002'), 1, 'y lo guarda a su nombre');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000600b003', true);
select ok((select archivo_id is null from fn_mis_polizas_avisos()), 'Beto todavía no tiene PDF: su fila avisa de la póliza');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000600b001', true);
select fn_seguro_anular((select poliza_id from _colectiva where persona_id = '00000000-0000-0000-0000-00000600a003'), 'Se registró con otra persona');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000600b003', true);
select is((select count(*)::int from fn_mis_polizas_avisos()), 0, 'una póliza anulada deja de avisar sola');

-- Beto vuelve a la colectiva para lo que sigue.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000600b001', true);
select fn_seguro_registrar('00000000-0000-0000-0000-00000600a003', 'vida_ley', 'Pacífico Seguros', 'VL-600',
  fn_hoy_lima() - 60, fn_hoy_lima() + 30, 14.5, null, null, null, null, null, null);

-- ── B · Quién tiene que renovar (0603) ──────────────────────────────────────
select is(fn_generar_alertas_seguros(), 1, 'dos personas en la misma póliza dan un aviso, y la que tiene renovación ninguno');
select is((select payload ->> 'persona' from alertas where tipo = 'seguro_por_renovar'), '2 personas', 'la colectiva no lleva nombres');
select is((select (payload ->> 'tramo')::int from alertas where tipo = 'seguro_por_renovar'), 45, 'a 30 días es el tramo de 45');
select is(fn_generar_alertas_seguros(), 0, 'repetir el cron no duplica');

create temp table _pendientes as select * from fn_alertas_email_pendientes() where tipo = 'seguro_por_renovar';
select is((select destinatarios from _pendientes), array['adm600@prueba.local'], 'le llega a DO, no a la líder de equipo');

-- ── C · El segundo toque, y cuándo deja de hacer falta ──────────────────────
update polizas_seguro set vigente_hasta = fn_hoy_lima() + 10 where numero_poliza = 'VL-600';
select is(fn_generar_alertas_seguros(), 1, 'con otra fecha de fin es otro hecho');
select is((select count(*)::int from alertas where tipo = 'seguro_por_renovar' and payload ->> 'tramo' = '15'), 1, 'y dentro de 15 días es el tramo de 15');

select ok(fn_alerta_sigue_vigente('seguro_por_renovar', null,
  (select payload from alertas where tipo = 'seguro_por_renovar' and payload ->> 'tramo' = '15')), 'sin renovación, el aviso sigue vigente');

select fn_seguro_registrar(x, 'vida_ley', 'Pacífico Seguros', 'VL-601', fn_hoy_lima() + 10, fn_hoy_lima() + 375, 14.5, null, null, null, null, null, null)
  from unnest(array['00000000-0000-0000-0000-00000600a002', '00000000-0000-0000-0000-00000600a003']::uuid[]) x;
select ok(not fn_alerta_sigue_vigente('seguro_por_renovar', null,
  (select payload from alertas where tipo = 'seguro_por_renovar' and payload ->> 'tramo' = '15')), 'con la renovación registrada, el aviso ya no es cierto');
-- En el camino de verdad, no en la función suelta: esta es la línea que tiene que ponerse en rojo sin el filtro de la cola.
select is((select count(*)::int from fn_alertas_email_pendientes() where tipo = 'seguro_por_renovar'), 0, 'y la cola ya no lo entrega');
select is(fn_generar_alertas_seguros(), 0, 'y no se genera uno nuevo');
select is((select count(*)::int from alertas where tipo = 'seguro_por_renovar' and estado = 'pendiente'), 0, 'el cron cierra lo que quedó esperando');

-- ── D · Quien cambió de seguro no renueva el que dejó ───────────────────────
select is((select fn_seguro_sin_renovar('00000000-0000-0000-0000-00000600a005', 'salud_practicantes', fn_hoy_lima() + 100)), true, 'FOLA de quien es practicante pide renovarse');
set session_replication_role = replica;
update personas set tipo_vinculo = 'planilla', practicante_modalidad = null where id = '00000000-0000-0000-0000-00000600a005';
set session_replication_role = origin;
select is((select fn_seguro_sin_renovar('00000000-0000-0000-0000-00000600a005', 'salud_practicantes', fn_hoy_lima() + 100)), false, 'y ya no, si hoy está en planilla: la pantalla tampoco se lo pide');

-- ── E · Dos aseguradoras con el mismo número son dos pólizas ────────────────
select fn_seguro_tipo_crear('Otro seguro 603', 'Prueba', false, true, 'Alta', 'Baja');
select set_config('t.otro', (select clave from seguros_tipos where nombre = 'Otro seguro 603'), true);
select fn_seguro_registrar('00000000-0000-0000-0000-00000600a002', current_setting('t.otro'), 'Pacífico Seguros', 'NUM-603', fn_hoy_lima() - 5, fn_hoy_lima() + 20, 10, null, null, null, null, null, null);
select fn_seguro_registrar('00000000-0000-0000-0000-00000600a003', current_setting('t.otro'), 'Rímac Seguros', 'NUM-603', fn_hoy_lima() - 5, fn_hoy_lima() + 20, 10, null, null, null, null, null, null);
select is(fn_generar_alertas_seguros(), 2, 'el mismo número en dos aseguradoras son dos avisos');

-- ── F · Un correo que falló se puede reencolar ──────────────────────────────
update alertas set estado = 'fallido', intentos = 3, created_at = now() - interval '8 days'
 where tipo = 'seguro_por_renovar' and payload ->> 'aseguradora' = 'Rímac Seguros';
select is((fn_alertas_resolver_fallidas(true) -> 'reencolar' ->> 'total')::int, 1, 'vigente y fuera de ventana: vuelve a la cola, no se pierde el último aviso');

select ok(not has_function_privilege('authenticated', 'fn_generar_alertas_seguros()', 'execute'), 'nadie la llama con su sesión: la corre el cron');

select * from finish();
rollback;
