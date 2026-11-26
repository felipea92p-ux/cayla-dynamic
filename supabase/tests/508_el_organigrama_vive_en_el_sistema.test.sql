-- ============================================================================
-- 508 — El organigrama vive en el sistema (0623)
-- ============================================================================
-- Prueba lo que no puede fallar:
--   · sin publicar, solo DO lo ve; publicado, todo el equipo con sesión;
--   · solo DO escribe; sin sesión no se ejecuta nada;
--   · quien sale (inactivo) y las cuentas de servicio no se dibujan;
--   · asesoría y externos nunca llevan línea de equipo, entre en el orden que entre;
--   · una casilla, una persona; un par, una línea.
-- Todo con datos inventados, dentro de begin … rollback.
-- ============================================================================
begin;
select plan(28);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000050801', 'ZZORG', 'Sede de laboratorio ORG', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, estado, cuenta_de_servicio) values
  ('00000000-0000-0000-0000-000000050811', 'OrgDo',      'Lab', '00000000-0000-0000-0000-000000050801', 'lider_do',        'x', '00000000-0000-0000-0000-000000050911', '2024-01-15', 'planilla', 'activo', false),
  ('00000000-0000-0000-0000-000000050812', 'OrgLider',   'Lab', '00000000-0000-0000-0000-000000050801', 'supervisor_sede', 'x', '00000000-0000-0000-0000-000000050912', '2024-01-15', 'planilla', 'activo', false),
  ('00000000-0000-0000-0000-000000050813', 'OrgInt',     'Lab', '00000000-0000-0000-0000-000000050801', 'integrante',      'x', '00000000-0000-0000-0000-000000050913', '2024-01-15', 'planilla', 'activo', false),
  ('00000000-0000-0000-0000-000000050814', 'OrgAsesor',  'Lab', '00000000-0000-0000-0000-000000050801', 'integrante',      'x', null,                                   '2024-01-15', 'planilla', 'activo', false),
  ('00000000-0000-0000-0000-000000050815', 'OrgSalio',   'Lab', '00000000-0000-0000-0000-000000050801', 'integrante',      'x', null,                                   '2024-01-15', 'planilla', 'activo', false),
  ('00000000-0000-0000-0000-000000050816', 'OrgEstacion','Lab', '00000000-0000-0000-0000-000000050801', 'integrante',      'x', null,                                   '2024-01-15', 'planilla', 'activo', true);
set session_replication_role = origin;

create function pg_temp.soy(p_sub text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true),
         set_config('request.jwt.claim.sub', p_sub, true);
$$;
create function pg_temp.nombres() returns text language sql as $$
  select coalesce(string_agg(x->>'nombres', ',' order by x->>'nombres'), '')
    from jsonb_array_elements(fn_organigrama()->'personas') x
   where x->>'nombres' like 'Org%';
$$;
grant execute on function pg_temp.soy(text) to authenticated;
grant execute on function pg_temp.nombres() to authenticated;

-- ── Permisos de ejecución ────────────────────────────────────────────────────
select ok(not has_function_privilege('anon', 'fn_organigrama()', 'execute'), 'sin sesión no se lee');
select ok(not has_function_privilege('anon', 'fn_organigrama_guardar(uuid,text,int,text,text,text,boolean,int,int)', 'execute'), 'sin sesión no se escribe');
select ok(not has_function_privilege('anon', 'fn_organigrama_publicar(boolean)', 'execute'), 'sin sesión no se publica');
select is((select publicado from organigrama_publicacion), false, 'nace sin publicar');
select is((select count(*)::int from organigrama_bloques), 6, 'nace con sus seis equipos');

set local role authenticated;

-- ── Solo DO escribe ──────────────────────────────────────────────────────────
select pg_temp.soy('00000000-0000-0000-0000-000000050912');
select throws_ok(
  $$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050813', 'trujillo', 1, 'Atención al cliente') $$,
  'P0001', 'Solo Desarrollo Organizacional puede cambiar el organigrama.', 'la líder de equipo no ordena');
select throws_ok($$ select fn_organigrama_publicar(true) $$,
  'P0001', 'Solo Desarrollo Organizacional puede publicar el organigrama.', 'la líder de equipo no publica');

select pg_temp.soy('00000000-0000-0000-0000-000000050911');
select lives_ok($$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050812', 'arequipa', 1, 'Líder de equipo', null, 'azul', false, 1) $$, 'DO ubica con color y columna');
select lives_ok($$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050813', 'arequipa', 2, 'Atención al cliente') $$, 'DO ubica sin color');
select lives_ok($$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050814', 'do', 1, 'Asesoría', 'asesoria', 'azul', false, 1) $$, 'quien asesora puede llevar color');
select lives_ok($$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050815', 'lima', 1, 'Costura') $$, 'DO ubica a quien luego sale');
select throws_ok($$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050816', 'lima', 2, 'Estación') $$,
  'P0001', 'Solo se ubica a integrantes activos.', 'una cuenta de servicio no se ubica');
select throws_ok($$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050813', 'arequipa', 1, 'Otra', null, null, false, 1) $$,
  'P0001', 'Esa casilla ya está ocupada: elige otro nivel o columna.', 'una casilla, una persona');
select throws_ok($$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050813', 'lima', 1, 'Otra', null, null, false, 2) $$,
  'P0001', 'Ese equipo no tiene la columna 2.', 'no hay columna donde el equipo no es cuadrícula');
select throws_ok($$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050813', 'lima', 1, 'Otra', null, 'rosado') $$,
  'P0001', 'Color desconocido.', 'solo los colores de la casa');

-- ── Líneas: asesoría sin mando ───────────────────────────────────────────────
select lives_ok($$ select fn_organigrama_linea('00000000-0000-0000-0000-000000050813', '00000000-0000-0000-0000-000000050812', 'equipo') $$, 'línea de equipo entre dos del equipo');
select lives_ok($$ select fn_organigrama_linea('00000000-0000-0000-0000-000000050812', '00000000-0000-0000-0000-000000050813', 'asesoria') $$, 'el mismo par al revés reemplaza la línea');
select is(jsonb_array_length(fn_organigrama()->'lineas'), 1, 'un par, una sola línea');
select throws_ok($$ select fn_organigrama_linea('00000000-0000-0000-0000-000000050814', '00000000-0000-0000-0000-000000050813', 'equipo') $$,
  '23514', 'Quien asesora o es externo no lleva línea de equipo: únelo con línea de asesoría.', 'línea de equipo con asesoría: rechazada');
select fn_organigrama_linea('00000000-0000-0000-0000-000000050813', '00000000-0000-0000-0000-000000050812', 'equipo');
select throws_ok($$ select fn_organigrama_guardar('00000000-0000-0000-0000-000000050813', 'arequipa', 2, 'Atención', 'externo') $$,
  '23514', 'Quien asesora o es externo no lleva línea de equipo: únelo con línea de asesoría.', 'volver externo a quien ya tiene línea de equipo: rechazado');

-- ── Quién ve qué ─────────────────────────────────────────────────────────────
select is(pg_temp.nombres(), 'OrgAsesor,OrgInt,OrgLider,OrgSalio', 'DO ve el borrador');
select ok((fn_organigrama()->'sin_ubicar') @> '[{"nombres":"OrgDo"}]'::jsonb, 'DO ve a quién le falta sitio');
select ok(not (fn_organigrama()->'sin_ubicar') @> '[{"nombres":"OrgEstacion"}]'::jsonb, 'la cuenta de servicio no figura como pendiente');

select pg_temp.soy('00000000-0000-0000-0000-000000050913');
select is(jsonb_array_length(fn_organigrama()->'personas'), 0, 'sin publicar, una integrante no ve a nadie');

select pg_temp.soy('00000000-0000-0000-0000-000000050911');
select fn_organigrama_publicar(true);
reset role;
update personas set estado = 'inactivo', fecha_cese = '2026-11-20', motivo_cese = 'renuncia'
 where id = '00000000-0000-0000-0000-000000050815';
set local role authenticated;

select pg_temp.soy('00000000-0000-0000-0000-000000050913');
select is(pg_temp.nombres(), 'OrgAsesor,OrgInt,OrgLider', 'publicado: el equipo lo ve, sin quien ya salió');
select is(jsonb_array_length(fn_organigrama()->'sin_ubicar'), 0, 'la lista de pendientes no es para el equipo');
select ok(not (fn_organigrama()->'personas'->0) ?| array['documento', 'rol', 'email', 'cargo', 'sueldo_base_legal'],
  'el dibujo no entrega datos de la ficha');

-- ── Quitar ───────────────────────────────────────────────────────────────────
select pg_temp.soy('00000000-0000-0000-0000-000000050911');
select fn_organigrama_quitar('00000000-0000-0000-0000-000000050813');
select is(jsonb_array_length(fn_organigrama()->'lineas'), 0, 'quitar a alguien se lleva sus líneas');

select * from finish();
rollback;
