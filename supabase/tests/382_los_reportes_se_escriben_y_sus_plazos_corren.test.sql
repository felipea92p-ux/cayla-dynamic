-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 382_los_reportes_se_escriben_y_sus_plazos_corren.test.sql
-- ============================================================================
-- Cubre la migración 0484: cómo se escribe un reporte y cómo corren sus
-- plazos. Lo que hay que blindar:
--   (a) crear: validaciones, a quién le toca, y el rechazo cuando nadie puede
--       recibirlo (no queda un reporte huérfano);
--   (b) los plazos de cada vía, contados en días hábiles con un feriado en
--       medio, calculados aquí por un camino independiente de la 0212;
--   (c) el hilo: quién escribe, las notas internas, el aviso de fecha del
--       43-B.2 y el paso a «en revisión»;
--   (d) la líder media y escala, pero no cierra convivencia; en el Título X
--       nadie media (48.14);
--   (e) reclasificar al Título X le quita el caso a la líder en el acto;
--   (f) el Título X completo: sin informe no se decide, el informe lo escribe
--       quien investiga (o DO si investiga una persona externa), las medidas,
--       los indicios de delito y el aviso al MTPE tras la decisión;
--   (g) disciplina: solo se enlaza un expediente de una involucrada;
--   (h) adjuntos, aperturas registradas y las dos listas;
--   (i) los nombramientos del Título X y sus guardianes;
--   (j) guardas null-safe: quien no tiene acceso no pasa por un `null`.
-- Sesiones con set_config('request.jwt.claim.sub', ...), como la 344. Todo
-- dentro de begin/rollback.
-- ============================================================================
begin;
select plan(134);

-- ── Semilla ──────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000e5001', 'ZZW01', 'Sede escritura 1', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000e5002', 'ZZW02', 'Sede escritura 2', true, 'tienda');

set session_replication_role = replica;
update personas set rol = 'integrante' where rol in ('supervisor_sede', 'lider_do', 'admin');
delete from configuracion where clave = 'gerencia_general';
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-0000000e0001', 'Ana',   'Esc', '00000000-0000-0000-0000-0000000e5001', 'integrante',      'x', '00000000-0000-0000-0000-0000000f0001', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000e0002', 'Bea',   'Esc', '00000000-0000-0000-0000-0000000e5001', 'integrante',      'x', '00000000-0000-0000-0000-0000000f0002', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000e0003', 'Lia',   'Esc', '00000000-0000-0000-0000-0000000e5001', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000f0003', '2023-01-01', 'planilla', 'Líder de equipo'),
  ('00000000-0000-0000-0000-0000000e0004', 'Lea',   'Esc', '00000000-0000-0000-0000-0000000e5002', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000f0004', '2023-01-01', 'planilla', 'Líder de equipo'),
  ('00000000-0000-0000-0000-0000000e0005', 'Dora',  'Esc', '00000000-0000-0000-0000-0000000e5001', 'lider_do',        'x', '00000000-0000-0000-0000-0000000f0005', '2023-01-01', 'planilla', 'DO'),
  ('00000000-0000-0000-0000-0000000e0006', 'Gabi',  'Esc', '00000000-0000-0000-0000-0000000e5001', 'admin',           'x', '00000000-0000-0000-0000-0000000f0006', '2023-01-01', 'planilla', 'Gerencia General'),
  ('00000000-0000-0000-0000-0000000e0007', 'Otto',  'Esc', '00000000-0000-0000-0000-0000000e5001', 'admin',           'x', '00000000-0000-0000-0000-0000000f0007', '2023-01-01', 'planilla', 'Administración'),
  ('00000000-0000-0000-0000-0000000e0008', 'Dele',  'Esc', '00000000-0000-0000-0000-0000000e5001', 'integrante',      'x', '00000000-0000-0000-0000-0000000f0008', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000e0010', 'Carla', 'Esc', '00000000-0000-0000-0000-0000000e5001', 'integrante',      'x', '00000000-0000-0000-0000-0000000f0010', '2023-01-01', 'planilla', 'Vendedora');
set session_replication_role = origin;

insert into configuracion (clave, valor, descripcion)
values ('gerencia_general', jsonb_build_object('persona_id', '00000000-0000-0000-0000-0000000e0006'::uuid), 'prueba');
insert into organos_titulo_x (sede_id, persona_id, papel, desde, acta) values
  ('00000000-0000-0000-0000-0000000e5001', '00000000-0000-0000-0000-0000000e0008', 'delegada', '2026-01-01', 'Acta de elección de prueba');

-- Un feriado en el PRIMER día hábil después de hoy: los plazos tienen que
-- saltarlo. Se elige mirando el calendario, no suponiendo el día de la semana.
insert into feriados (fecha, nombre)
select min(d)::date, 'Feriado de prueba 382'
  from generate_series(fn_hoy_lima() + 1, fn_hoy_lima() + 7, interval '1 day') d
 where extract(dow from d) not in (0, 6)
   and not exists (select 1 from feriados f where f.fecha = d::date)
on conflict (fecha) do nothing;

-- El n-ésimo día hábil después de hoy, contado aquí SIN usar la 0212: si los
-- dos caminos coinciden, el plazo está bien calculado.
create function pg_temp.habil(n int) returns timestamptz language sql as $$
  select ((d::date + time '23:59:59') at time zone 'America/Lima')
    from generate_series(fn_hoy_lima() + 1, fn_hoy_lima() + 60, interval '1 day') d
   where extract(dow from d) not in (0, 6)
     and not exists (select 1 from feriados f where f.fecha = d::date)
   order by d offset n - 1 limit 1;
$$;
create function pg_temp.id_de(p_relato text) returns uuid language sql as $$
  select id from reportes where relato = p_relato;
$$;
create function pg_temp.plazo(p_relato text, p_clave text) returns reporte_plazos language sql as $$
  select p.* from reporte_plazos p join reportes r on r.id = p.reporte_id
   where r.relato = p_relato and p.clave = p_clave and p.anulado_at is null;
$$;


-- ── (a) Crear ───────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0001', true);

select lives_ok($$ select fn_reporte_crear('persona', 'convivencia', '00000000-0000-0000-0000-0000000e5001',
                     fn_hoy_lima(), 'C1 Bea me grita delante de clientas',
                     array['00000000-0000-0000-0000-0000000e0002']::uuid[], '{}', 'conversar') $$,
  'Ana reporta a Bea por convivencia');
select is((select gestiona from reportes where relato = 'C1 Bea me grita delante de clientas'), 'lider',
  'un reporte sobre una colaboradora lo lleva la líder de la sede');
select is((select autor_id from reportes where relato = 'C1 Bea me grita delante de clientas'),
  '00000000-0000-0000-0000-0000000e0001'::uuid, 'la autora es quien tiene la sesión, no un parámetro');
select is((select nivel from reportes where relato = 'C1 Bea me grita delante de clientas'), 0::smallint,
  'el nivel sale de la foto de la involucrada');

select lives_ok($$ select fn_reporte_crear('empresa', 'reclamo', '00000000-0000-0000-0000-0000000e5001',
                     fn_hoy_lima(), 'R1 El aire acondicionado no funciona') $$,
  'Ana reclama sobre la empresa');
select lives_ok($$ select fn_reporte_crear('persona', 'titulo_x', '00000000-0000-0000-0000-0000000e5001',
                     fn_hoy_lima(), 'X1 Queja de hostigamiento',
                     array['00000000-0000-0000-0000-0000000e0002']::uuid[]) $$,
  'Ana presenta una queja del Título X');
select is((select gestiona from reportes where relato = 'X1 Queja de hostigamiento'), 'do',
  'el Título X lo recibe DO');

-- La consulta a la líder (absorbe la 0435): va a la líder, con el plazo del 43-B.2.
select lives_ok($$ select fn_reporte_crear('consulta', 'reclamo', '00000000-0000-0000-0000-0000000e5001',
                     fn_hoy_lima(), 'Q1 ¿Cuándo sale el rol de la próxima semana?') $$,
  'Ana le escribe una consulta a su líder');
select is((select gestiona from reportes where relato = 'Q1 ¿Cuándo sale el rol de la próxima semana?'), 'lider',
  'la consulta la lleva la líder de la sede');
select is((pg_temp.plazo('Q1 ¿Cuándo sale el rol de la próxima semana?', 'respuesta')).vence_at, pg_temp.habil(10),
  'y tiene el plazo de 10 días hábiles que la 0435 no contaba');
select throws_like($$ select fn_reporte_crear('consulta', 'convivencia', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(), 'x') $$,
  '%persona del equipo%', 'una consulta no va por convivencia');
select throws_like($$ select fn_reporte_crear('consulta', 'reclamo', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(), 'x',
                        array['00000000-0000-0000-0000-0000000e0002']::uuid[]) $$,
  '%no nombra%', 'ni nombra a personas');
select throws_like($$ select fn_reporte_crear('empresa', 'convivencia', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(), 'x') $$,
  '%persona del equipo%', 'convivencia es entre personas');
select throws_like($$ select fn_reporte_crear('persona', 'reclamo', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(), 'x') $$,
  '%Elige a la persona%', 'un reporte sobre una persona nombra a la persona');
select throws_like($$ select fn_reporte_crear('persona', 'reclamo', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(), 'x',
                        array['00000000-0000-0000-0000-0000000e0001']::uuid[]) $$,
  '%ti misma%', 'nadie se reporta a sí misma');
select throws_like($$ select fn_reporte_crear('persona', 'reclamo', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(), 'x',
                        array['00000000-0000-0000-0000-0000000e0002']::uuid[], array['00000000-0000-0000-0000-0000000e0002']::uuid[]) $$,
  '%involucrada y testigo%', 'una persona no es involucrada y testigo a la vez');
select throws_like($$ select fn_reporte_crear('idea', 'reclamo', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(), 'x',
                        array['00000000-0000-0000-0000-0000000e0002']::uuid[]) $$,
  '%no nombra%', 'una idea no nombra a personas involucradas');
select throws_like($$ select fn_reporte_crear('empresa', 'reclamo', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima() + 1, 'x') $$,
  '%futura%', 'la fecha del hecho no puede ser futura');
select throws_like($$ select fn_reporte_crear('empresa', 'reclamo', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(), '   ') $$,
  '%qué pasó%', 'sin relato no hay reporte');

-- Sin DO activa, un reporte sobre la Gerencia General no tiene quién lo reciba.
set session_replication_role = replica;
update personas set estado = 'inactivo', fecha_cese = '2026-09-25' where id = '00000000-0000-0000-0000-0000000e0005';
set session_replication_role = origin;
select throws_like($$ select fn_reporte_crear('persona', 'convivencia', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(),
                        'H1 sobre la Gerencia General', array['00000000-0000-0000-0000-0000000e0006']::uuid[]) $$,
  '%sobre cerrado%', 'sin nadie que lo reciba, se rechaza y se orienta al sobre cerrado y los canales externos');
select is((select count(*)::int from reportes where relato = 'H1 sobre la Gerencia General'), 0,
  'y no queda un reporte huérfano');
set session_replication_role = replica;
update personas set estado = 'activo', fecha_cese = null where id = '00000000-0000-0000-0000-0000000e0005';
set session_replication_role = origin;


-- ── (b) Los plazos de cada vía ──────────────────────────────────────────────
select is((select count(*)::int from reporte_plazos where reporte_id = pg_temp.id_de('C1 Bea me grita delante de clientas')), 2,
  'convivencia nace con dos plazos: acuse y resolución');
select ok((pg_temp.plazo('C1 Bea me grita delante de clientas', 'acuse')).cumplido_at is not null,
  'el acuse lo da el sistema en el acto (43-A.6)');
select is((select count(*)::int from reporte_eventos
            where reporte_id = pg_temp.id_de('C1 Bea me grita delante de clientas') and tipo = 'acuse' and por is null), 1,
  'y queda como evento del sistema, a nombre de DO');
select is((pg_temp.plazo('C1 Bea me grita delante de clientas', 'resolucion')).vence_at, pg_temp.habil(15),
  'la resolución vence a los 15 días hábiles, saltando el feriado');
select is((pg_temp.plazo('R1 El aire acondicionado no funciona', 'respuesta')).vence_at, pg_temp.habil(10),
  'el reclamo se responde en 10 días hábiles (43-B.2)');
select is((select string_agg(clave, ',' order by clave) from reporte_plazos
            where reporte_id = pg_temp.id_de('X1 Queja de hostigamiento')),
  'aviso_mtpe,informe,medidas,salud,traslado', 'el Título X nace con los cinco plazos que corren desde la recepción');
select is((pg_temp.plazo('X1 Queja de hostigamiento', 'medidas')).vence_at, pg_temp.habil(3),
  'medidas de protección: 3 días hábiles (49.4 c)');
select is((pg_temp.plazo('X1 Queja de hostigamiento', 'informe')).vence_at,
  ((fn_hoy_lima() + 15 + time '23:59:59') at time zone 'America/Lima'),
  'el informe: 15 días CALENDARIO, no hábiles (49.4 e)');
select is((pg_temp.plazo('X1 Queja de hostigamiento', 'informe')).duena, 'investigadora',
  'y es de quien investiga');


-- ── (c) El hilo ─────────────────────────────────────────────────────────────
select lives_ok($$ select fn_reporte_mensaje(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'Pasó dos veces esta semana.') $$,
  'Ana escribe en su reporte');
select throws_like($$ select fn_reporte_mensaje(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'x', true) $$,
  '%notas internas%', 'Ana no deja notas internas');
select is((select estado from reportes where relato = 'C1 Bea me grita delante de clientas'), 'recibido',
  'lo que escribe la autora no cambia el estado');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0002', true);
select throws_like($$ select fn_reporte_mensaje(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'Eso no es cierto') $$,
  '%No puedes escribir%', 'Bea, la reportada, no escribe en el reporte sobre ella');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0003', true);
select lives_ok($$ select fn_reporte_mensaje(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'Gracias, Ana. ¿Hubo alguien más presente?') $$,
  'Lia, la líder, responde');
select is((select estado from reportes where relato = 'C1 Bea me grita delante de clientas'), 'en_revision',
  'la primera palabra de quien gestiona pone el caso en revisión');
select is((select count(*)::int from reporte_eventos
            where reporte_id = pg_temp.id_de('C1 Bea me grita delante de clientas') and tipo = 'estado'), 1,
  'y el cambio de estado queda en la línea de tiempo');

-- El aviso de fecha del 43-B.2.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0005', true);
select throws_like($$ select fn_reporte_mensaje(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'x', false, fn_hoy_lima() + 20) $$,
  '%43-B.2%', 'el aviso de fecha es solo de reclamos');
select lives_ok($$ select fn_reporte_mensaje(pg_temp.id_de('R1 El aire acondicionado no funciona'),
                     'Hay que pedir presupuesto al técnico; te respondemos el día indicado.', false, fn_hoy_lima() + 20) $$,
  'DO avisa la fecha en que responderá');
select ok((pg_temp.plazo('R1 El aire acondicionado no funciona', 'respuesta')).cumplido_at is not null,
  'el aviso cumple el plazo de 10 días');
select is((pg_temp.plazo('R1 El aire acondicionado no funciona', 'respuesta_prometida')).vence_at,
  ((fn_hoy_lima() + 20 + time '23:59:59') at time zone 'America/Lima'),
  'y abre uno nuevo que vence el día avisado');
select throws_like($$ select fn_reporte_mensaje(pg_temp.id_de('R1 El aire acondicionado no funciona'), 'otra', false, fn_hoy_lima() + 30) $$,
  '%pendiente%', 'la fecha se avisa una vez: no se corre sola');


-- ── (d) La líder media y escala, pero no cierra convivencia ─────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0003', true);
select lives_ok($$ select fn_reporte_anotar_accion(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'mediacion',
                     'Conversé con las dos por separado y luego juntas.') $$,
  'la líder registra una mediación');
select throws_like($$ select fn_reporte_cerrar(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'resuelto', 'Se conversó y quedó resuelto.') $$,
  '%lo cierra Desarrollo Organizacional%', 'pero no cierra un caso de convivencia (decisión 14)');
select lives_ok($$ select fn_reporte_escalar(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'Se repitió después de la mediación.') $$,
  'la líder lo escala');
select is((select gestiona from reportes where relato = 'C1 Bea me grita delante de clientas'), 'do',
  'y pasa a DO');
select ok(fn_reporte_puede_gestionar(pg_temp.id_de('C1 Bea me grita delante de clientas')),
  'la líder sigue viéndolo después de escalar');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0005', true);
select lives_ok($$ select fn_reporte_escalar(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'Pasa a la Gerencia General.') $$,
  'DO puede escalarlo a la Gerencia');
select throws_like($$ select fn_reporte_escalar(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'otra vez') $$,
  '%último escalón%', 'y de ahí no sube más');
select throws_like($$ select fn_reporte_anotar_accion(pg_temp.id_de('X1 Queja de hostigamiento'), 'mediacion', 'Reunión con las dos partes') $$,
  '%48.14%', 'en el Título X nadie media ni reúne a las partes');
select lives_ok($$ select fn_reporte_anotar_accion(pg_temp.id_de('X1 Queja de hostigamiento'), 'otra', 'Se pidió la grabación del día.') $$,
  'pero sí se registran otras actuaciones');

-- La líder cierra un RECLAMO.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0001', true);
select lives_ok($$ select fn_reporte_crear('idea', 'reclamo', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(), 'I1 Un perchero en la trastienda') $$,
  'Ana propone una idea');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0003', true);
select throws_like($$ select fn_reporte_cerrar(pg_temp.id_de('I1 Un perchero en la trastienda'), 'resuelto', 'corto') $$,
  '%respuesta escrita%', 'no se cierra sin una respuesta escrita de verdad');
select lives_ok($$ select fn_reporte_cerrar(pg_temp.id_de('I1 Un perchero en la trastienda'), 'resuelto',
                     'Buena idea: el perchero llega el lunes.') $$,
  'la líder cierra un reclamo o una idea de su sede');
select ok((pg_temp.plazo('I1 Un perchero en la trastienda', 'respuesta')).cumplido_at is not null,
  'y el cierre cumple el plazo de respuesta');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0001', true);
select throws_like($$ select fn_reporte_mensaje(pg_temp.id_de('I1 Un perchero en la trastienda'), '¿y el color?') $$,
  '%ya se cerró%', 'la autora ya no escribe en un reporte cerrado');


-- ── (e) Reclasificar al Título X le quita el caso a la líder ────────────────
select lives_ok($$ select fn_reporte_crear('persona', 'convivencia', '00000000-0000-0000-0000-0000000e5001', fn_hoy_lima(),
                     'C2 Bea me hizo comentarios', array['00000000-0000-0000-0000-0000000e0002']::uuid[]) $$,
  'Ana reporta otra cosa sobre Bea');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0003', true);
select lives_ok($$ select fn_reporte_reclasificar(pg_temp.id_de('C2 Bea me hizo comentarios'), 'titulo_x',
                     'Los comentarios son de connotación sexual.') $$,
  'la líder detecta que es de connotación sexual y lo reclasifica');
select is(fn_reporte_puede_ver(pg_temp.id_de('C2 Bea me hizo comentarios')), false,
  'y en el acto deja de verlo: eso cumple por sí solo el deber de comunicar a DO (49.3)');
select is((select count(*)::int from reporte_plazos
            where reporte_id = pg_temp.id_de('C2 Bea me hizo comentarios') and anulado_at is not null), 1,
  'la resolución de convivencia que estaba pendiente queda anulada, no borrada');
select is((select count(*)::int from reporte_plazos
            where reporte_id = pg_temp.id_de('C2 Bea me hizo comentarios') and anulado_at is null and cumplido_at is null), 5,
  'y corren los cinco del Título X, desde la misma recepción');
select is((select gestiona from reportes where relato = 'C2 Bea me hizo comentarios'), 'do',
  'y pasa a DO');
select throws_like($$ select fn_reporte_reclasificar(pg_temp.id_de('C2 Bea me hizo comentarios'), 'reclamo', 'me equivoqué') $$,
  '%No gestionas%', 'la líder ya no puede tocarlo');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0008', true);
select throws_like($$ select fn_reporte_reclasificar(pg_temp.id_de('C2 Bea me hizo comentarios'), 'convivencia', 'no es sexual') $$,
  '%Solo Desarrollo Organizacional saca%', 'ni quien investiga lo saca del Título X');


-- ── (f) El Título X completo ────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0005', true);
select throws_like($$ select fn_reporte_cerrar(pg_temp.id_de('X1 Queja de hostigamiento'), 'confirmado', 'Se confirmaron los hechos.') $$,
  '%informe%', 'DO no decide sin el informe de quien investiga');
select throws_like($$ select fn_reporte_plazo_cumplir(pg_temp.id_de('X1 Queja de hostigamiento'), 'informe', 'Lo escribo yo') $$,
  '%quien decide no escribe el informe%', 'ni escribe el informe ella misma cuando hay investigadora');
select lives_ok($$ select fn_reporte_plazo_cumplir(pg_temp.id_de('X1 Queja de hostigamiento'), 'salud',
                     'Se ofreció atención psicológica; aceptó por escrito.') $$,
  'DO cumple la atención en salud');
select throws_like($$ select fn_reporte_plazo_cumplir(pg_temp.id_de('X1 Queja de hostigamiento'), 'resolucion', 'x x x') $$,
  '%al responder o al cerrar%', 'la resolución no se marca a mano');

select throws_like($$ select fn_reporte_medida(pg_temp.id_de('X1 Queja de hostigamiento'), '00000000-0000-0000-0000-0000000e0010', 'Cambiar turno') $$,
  '%líder de equipo activa%', 'la instrucción va a una líder, no a cualquiera');
select lives_ok($$ select fn_reporte_medida(pg_temp.id_de('X1 Queja de hostigamiento'), '00000000-0000-0000-0000-0000000e0003',
                     'Desde mañana Bea pasa al turno tarde hasta nuevo aviso.', fn_hoy_lima() + 30) $$,
  'DO dicta una medida y se la encarga a la líder');
select ok((pg_temp.plazo('X1 Queja de hostigamiento', 'medidas')).cumplido_at is not null,
  'y eso cumple el plazo de medidas (49.4 c)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0003', true);
select is(fn_reporte_puede_ver(pg_temp.id_de('X1 Queja de hostigamiento')), false,
  'la líder sigue sin ver el caso');
select lives_ok($$ select fn_reporte_medida_cumplida((select id from reporte_medidas
                     where para_persona_id = '00000000-0000-0000-0000-0000000e0003' limit 1)) $$,
  'pero marca la medida como cumplida');
select throws_like($$ select fn_reporte_medida_cumplida((select id from reporte_medidas
                        where para_persona_id = '00000000-0000-0000-0000-0000000e0003' limit 1)) $$,
  '%ya la marcaste%', 'una sola vez');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0008', true);
select lives_ok($$ select fn_reporte_plazo_cumplir(pg_temp.id_de('X1 Queja de hostigamiento'), 'informe',
                     'Informe: se valoraron dos testimonios y la grabación; se propone amonestación.') $$,
  'la Delegada registra su informe');
select ok((pg_temp.plazo('X1 Queja de hostigamiento', 'traslado_informe')).cumplido_at is not null,
  'registrarlo en Dynamic ES trasladarlo a DO (49.4 f)');
select is((pg_temp.plazo('X1 Queja de hostigamiento', 'decision')).vence_at,
  ((fn_hoy_lima() + 10 + time '23:59:59') at time zone 'America/Lima'),
  'y DO tiene 10 días calendario para decidir (49.4 g)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0005', true);
select lives_ok($$ select fn_reporte_indicios_delito(pg_temp.id_de('X1 Queja de hostigamiento'), 'Hubo un tocamiento sin consentimiento.') $$,
  'DO registra indicios de delito');
select ok((pg_temp.plazo('X1 Queja de hostigamiento', 'delito')).vence_at <= now() + interval '24 hours',
  'y el plazo es de 24 horas (49.4 i)');
select throws_like($$ select fn_reporte_indicios_delito(pg_temp.id_de('X1 Queja de hostigamiento'), 'otra vez') $$,
  '%ya están registrados%', 'una sola vez');
select lives_ok($$ select fn_reporte_cerrar(pg_temp.id_de('X1 Queja de hostigamiento'), 'confirmado',
                     'Se confirmaron los hechos. Se abrió el procedimiento que corresponde y se mantienen las medidas.') $$,
  'con el informe, DO decide');
select ok((pg_temp.plazo('X1 Queja de hostigamiento', 'decision')).cumplido_at is not null,
  'la decisión cumple su plazo');
select is((pg_temp.plazo('X1 Queja de hostigamiento', 'aviso_decision')).vence_at, pg_temp.habil(6),
  'y abre el aviso al MTPE en 6 días hábiles (49.4 h)');

-- Sin investigadora en Dynamic (la persona externa del 48.2-bis), DO registra el informe.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0001', true);
select lives_ok($$ select fn_reporte_crear('persona', 'titulo_x', '00000000-0000-0000-0000-0000000e5002', fn_hoy_lima(),
                     'X2 Queja en la sede 2', array['00000000-0000-0000-0000-0000000e0004']::uuid[]) $$,
  'una queja del Título X en una sede sin Delegada registrada');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0005', true);
select lives_ok($$ select fn_reporte_plazo_cumplir(pg_temp.id_de('X2 Queja en la sede 2'), 'informe',
                     'Informe de la investigadora externa contratada para este caso, entregado en PDF.') $$,
  'DO registra el informe de la persona externa, que no tiene cuenta');


-- ── (g) Disciplina ──────────────────────────────────────────────────────────
insert into expediente_disciplinario (id, persona_id, tipo_causal, nivel, creado_por) values
  ('00000000-0000-0000-0000-0000000e9001', '00000000-0000-0000-0000-0000000e0002', 'conducta', 'amonestacion', '00000000-0000-0000-0000-0000000e0005'),
  ('00000000-0000-0000-0000-0000000e9002', '00000000-0000-0000-0000-0000000e0010', 'conducta', 'amonestacion', '00000000-0000-0000-0000-0000000e0005');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0006', true);
select throws_like($$ select fn_reporte_cerrar(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'derivado_disciplinario', 'Se derivó a disciplina.') $$,
  '%primero enlaza%', 'no se cierra como derivado sin el expediente');
select throws_like($$ select fn_reporte_derivar(pg_temp.id_de('C1 Bea me grita delante de clientas'), '00000000-0000-0000-0000-0000000e9002') $$,
  '%no está involucrada%', 'no se enlaza el expediente de alguien que no está en el reporte');
select lives_ok($$ select fn_reporte_derivar(pg_temp.id_de('C1 Bea me grita delante de clientas'), '00000000-0000-0000-0000-0000000e9001') $$,
  'la Gerencia enlaza el expediente de Bea');
select throws_like($$ select fn_reporte_derivar(pg_temp.id_de('C1 Bea me grita delante de clientas'), '00000000-0000-0000-0000-0000000e9001') $$,
  '%ya está enlazado%', 'una sola vez');
select lives_ok($$ select fn_reporte_cerrar(pg_temp.id_de('C1 Bea me grita delante de clientas'), 'derivado_disciplinario',
                     'Se abrió el procedimiento disciplinario que corresponde.') $$,
  'y lo cierra como derivado');


-- ── (h) Adjuntos, aperturas y listas ────────────────────────────────────────
select set_config('t.adj', pg_temp.id_de('R1 El aire acondicionado no funciona')::text || '/f0000000-0000-0000-0000-0000000000b1.jpg', true);
insert into storage.objects (bucket_id, name, metadata)
values ('reportes', current_setting('t.adj'), '{"size": 4321, "mimetype": "image/jpeg"}');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0001', true);
select throws_like($$ select fn_reporte_adjuntar(pg_temp.id_de('R1 El aire acondicionado no funciona'), current_setting('t.adj'), true) $$,
  '%internos%', 'la autora no adjunta archivos internos');
select throws_like($$ select fn_reporte_adjuntar(pg_temp.id_de('I1 Un perchero en la trastienda'), current_setting('t.adj')) $$,
  '%cerró%', 'ni adjunta a un reporte cerrado');
select throws_like($$ select fn_reporte_adjuntar(pg_temp.id_de('R1 El aire acondicionado no funciona'),
                        pg_temp.id_de('R1 El aire acondicionado no funciona')::text || '/f0000000-0000-0000-0000-0000000000ff.jpg') $$,
  '%no llegó%', 'un archivo que no está en el bucket no se registra');
select lives_ok($$ select fn_reporte_adjuntar(pg_temp.id_de('R1 El aire acondicionado no funciona'), current_setting('t.adj')) $$,
  'la autora registra su foto');
select is((select bytes from reporte_adjuntos where storage_path = current_setting('t.adj')), 4321::bigint,
  'el peso sale del almacenamiento, no de lo que diga el navegador');

select is((select sin_leer from fn_reportes_mios() where id = pg_temp.id_de('R1 El aire acondicionado no funciona')), 1,
  'el aviso de fecha de DO le figura a Ana como una respuesta sin leer');
select is(fn_reporte_abrir(pg_temp.id_de('R1 El aire acondicionado no funciona')), 'autora',
  'la autora abre su reporte');
select is((select sin_leer from fn_reportes_mios() where id = pg_temp.id_de('R1 El aire acondicionado no funciona')), 0,
  'y al abrirlo deja de estar sin leer');
select is((select mi_papel from fn_reporte_detalle(pg_temp.id_de('R1 El aire acondicionado no funciona'))), 'autora',
  'el detalle le dice a la pantalla que ella es la autora');
select is((select count(*)::int from fn_reporte_adjuntos(pg_temp.id_de('R1 El aire acondicionado no funciona')) where es_mio), 1,
  'y le lista su foto');
select is((select string_agg(quien, ',' order by quien) from fn_reporte_hilo(pg_temp.id_de('C1 Bea me grita delante de clientas'))),
  'Tú,Tu líder de equipo', 'en el hilo, quien respondió se nombra por su cargo en el caso, no por su nombre');
select ok(not exists (select 1 from fn_reporte_padron() where id = '00000000-0000-0000-0000-0000000e0001'),
  'el padrón no la incluye a ella misma');
select ok(exists (select 1 from fn_reporte_padron() where id = '00000000-0000-0000-0000-0000000e0002'),
  'y sí a sus compañeras, aunque la RLS de personas no se las deje leer');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0005', true);
select is(fn_reporte_abrir(pg_temp.id_de('R1 El aire acondicionado no funciona')), 'do',
  'DO lo abre');
-- Se ordena por el motivo y no por `at`: dentro de la transacción de la prueba
-- las dos aperturas empatan en now() (ver CLAUDE.md, «un orden que depende del
-- orden físico no es un orden»).
select is((select string_agg(detalle ->> 'motivo', ',' order by detalle ->> 'motivo') from reporte_eventos
            where reporte_id = pg_temp.id_de('R1 El aire acondicionado no funciona') and tipo = 'lectura'), 'autora,do',
  'cada apertura deja rastro, con quién abrió (44.13)');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0007', true);
select throws_like($$ select fn_reporte_abrir(pg_temp.id_de('R1 El aire acondicionado no funciona')) $$,
  '%No tienes acceso%', 'Otto, admin, no lo abre');
select throws_like($$ select * from fn_reporte_detalle(pg_temp.id_de('R1 El aire acondicionado no funciona')) $$,
  '%No tienes acceso%', 'ni lee su detalle');
select throws_like($$ select * from fn_reporte_hilo(pg_temp.id_de('R1 El aire acondicionado no funciona')) $$,
  '%No tienes acceso%', 'ni su hilo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0003', true);
select is((select string_agg(left(r.relato, 2), ',' order by r.relato) from fn_reportes_bandeja() b join reportes r on r.id = b.id),
  'Q1,R1', 'la bandeja de la líder: lo abierto de su sede sobre nadie o sobre colaboradoras');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0005', true);
select is((select string_agg(left(r.relato, 2), ',' order by r.relato) from fn_reportes_bandeja() b join reportes r on r.id = b.id),
  'C2,Q1,R1,X1,X2', 'la bandeja de DO: lo abierto, y el X1 cerrado porque le queda el aviso al MTPE');
select is((select semaforo from fn_reportes_bandeja() where codigo = (select codigo from reportes where relato = 'X1 Queja de hostigamiento')),
  'por_vencer', 'con su semáforo: el traslado vence en un día hábil');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0001', true);
select is((select count(*)::int from fn_reportes_mios()), 7,
  'Ana ve sus siete reportes en «Mis reportes»');
select is((select mensajes from fn_reportes_mios() where id = pg_temp.id_de('C1 Bea me grita delante de clientas')), 2,
  'con los mensajes que le tocan, sin notas internas');
select is((select cierre_texto from fn_reportes_mios() where id = pg_temp.id_de('I1 Un perchero en la trastienda')),
  'Buena idea: el perchero llega el lunes.', 'y la respuesta escrita del cierre');


-- ── (i) Los nombramientos del Título X ──────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0003', true);
select throws_like($$ select fn_organo_titulo_x_guardar('00000000-0000-0000-0000-0000000e5002', '00000000-0000-0000-0000-0000000e0010', 'designada', fn_hoy_lima(), 'Acta 1') $$,
  '%Solo Desarrollo Organizacional%', 'la líder no nombra a quien investiga');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0007', true);
select throws_like($$ select fn_organo_titulo_x_guardar('00000000-0000-0000-0000-0000000e5002', '00000000-0000-0000-0000-0000000e0010', 'designada', fn_hoy_lima(), 'Acta 1') $$,
  '%Solo Desarrollo Organizacional%', 'ni un admin que no es la Gerencia General');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0006', true);
select throws_like($$ select fn_organo_titulo_x_guardar('00000000-0000-0000-0000-0000000e5002', '00000000-0000-0000-0000-0000000e0005', 'designada', fn_hoy_lima(), 'Acta 1') $$,
  '%48.3%', 'quien decide (DO) no puede ser quien investiga');
select throws_like($$ select fn_organo_titulo_x_guardar('00000000-0000-0000-0000-0000000e5002', '00000000-0000-0000-0000-0000000e0010', 'designada', fn_hoy_lima(), '') $$,
  '%acta%', 'sin acta no se registra');
select lives_ok($$ select fn_organo_titulo_x_guardar('00000000-0000-0000-0000-0000000e5002', '00000000-0000-0000-0000-0000000e0010',
                     'designada', fn_hoy_lima(), 'Resolución de designación transitoria, 2026-09-26') $$,
  'la Gerencia General designa a Carla en la sede 2');
select is((select count(*)::int from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-0000000e0010' and campo_modificado = 'organos_titulo_x'), 1,
  'y queda en la auditoría');
select lives_ok($$ select fn_organo_titulo_x_cerrar((select id from organos_titulo_x where persona_id = '00000000-0000-0000-0000-0000000e0010'),
                     fn_hoy_lima(), 'Asumió la Delegada elegida') $$,
  'y cierra el nombramiento');
select throws_like($$ select fn_organo_titulo_x_cerrar((select id from organos_titulo_x where persona_id = '00000000-0000-0000-0000-0000000e0010'),
                        fn_hoy_lima(), 'otra vez') $$,
  '%ya está cerrado%', 'una sola vez');


-- ── (j) Guardianes y guardas null-safe ──────────────────────────────────────
select throws_like($$ update reporte_plazos set vence_at = vence_at + interval '1 day' $$,
  '%no se corre%', 'un plazo no se corre');
select throws_like($$ delete from reporte_plazos $$,
  '%no se borra%', 'ni se borra');
select throws_like($$ update reporte_plazos set nota = 'otra' where cumplido_at is not null $$,
  '%no cambia%', 'ni se reescribe la nota de uno cumplido');
select throws_like($$ update reporte_medidas set instruccion = 'otra' $$,
  '%no se reescribe%', 'una medida no se reescribe');
select throws_like($$ delete from organos_titulo_x $$,
  '%no se borra%', 'un nombramiento no se borra');

-- Carla no tiene acceso a nada. Con `not in` desnudo, un motivo null pasaría.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0010', true);
select throws_like($$ select fn_reporte_medida(pg_temp.id_de('C2 Bea me hizo comentarios'), '00000000-0000-0000-0000-0000000e0003', 'Cambiar turno') $$,
  '%Solo Desarrollo Organizacional%', 'quien no tiene acceso no dicta una medida');
select throws_like($$ select fn_reporte_derivar(pg_temp.id_de('C2 Bea me hizo comentarios'), '00000000-0000-0000-0000-0000000e9001') $$,
  '%Solo Desarrollo Organizacional%', 'ni enlaza un expediente');
select throws_like($$ select fn_reporte_indicios_delito(pg_temp.id_de('C2 Bea me hizo comentarios'), 'x x x') $$,
  '%Solo Desarrollo Organizacional%', 'ni registra indicios de delito');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
select throws_like($$ select fn_organo_titulo_x_guardar('00000000-0000-0000-0000-0000000e5002', '00000000-0000-0000-0000-0000000e0010', 'designada', fn_hoy_lima(), 'Acta 1') $$,
  '%Solo Desarrollo Organizacional%', 'una sesión sin ficha no nombra a nadie');

-- El id se guarda ANTES de cambiar de rol: `authenticated` no puede ejecutar
-- una función de pg_temp, y el 42501 saldría por eso y no por lo que se prueba.
select set_config('t.c2', pg_temp.id_de('C2 Bea me hizo comentarios')::text, true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000f0005', true);
set local role authenticated;
select throws_ok($$ insert into reporte_plazos (reporte_id, clave, norma, descripcion, duena, desde, vence_at)
                    values (current_setting('t.c2')::uuid, 'delito', 'x', 'x', 'do', now(), now()) $$,
  '42501', null, 'nadie abre un plazo a mano, ni DO');
select throws_ok($$ select fn_reporte_plazo_abrir(current_setting('t.c2')::uuid, 'delito', now()) $$,
  '42501', null, 'ni llama a la pieza interna que los abre');
select ok(fn_reporte_puede_gestionar(current_setting('t.c2')::uuid),
  'control: DO sí tiene acceso a ese reporte, así que el 42501 es por el permiso y no por la regla');
reset role;

select * from finish();
rollback;
