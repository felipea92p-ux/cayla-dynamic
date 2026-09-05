-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 205_la_politica_del_descargo_previo_manda_y_deja_rastro.test.sql
-- ============================================================================
-- La 0268 mueve el descargo previo del código a una fila de `configuracion`.
-- Es la migración que más lejos llega en este módulo: con la política en false,
-- una suspensión sin goce se firma el mismo día y sin plazo.
--
-- Por eso esta prueba fija las tres cosas de las que depende que siga siendo
-- una decisión y no un agujero:
--
--   · con la política en TRUE, la función frena exactamente como la 0228;
--   · con la política en FALSE, firma — y el expediente QUEDA DICIÉNDOLO;
--   · si la clave falta o trae basura, se EXIGE. Una configuración perdida no
--     puede relajar una garantía en silencio.
--
-- Y una cuarta que no depende de la política: el numeral 60.5 sigue frenando.
-- Los hechos van con fechas de 2025 para que ese guard no se meta en medio.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000008c1', 'ZZPO', 'Sede de laboratorio PO', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values ('ee000000-0000-0000-0000-0000000008ff',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'admin.po@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-0000000008c2', 'PoAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000008c1', 'admin', 'x',
        'ee000000-0000-0000-0000-0000000008ff', '2024-01-01', 'activo'),
       ('00000000-0000-0000-0000-0000000008c3', 'PoTarde', 'Lab',
        '00000000-0000-0000-0000-0000000008c1', 'integrante', 'x', null, '2024-01-01', 'activo');

-- Cuatro borradores iguales, ninguno con cargos comunicados.
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, creado_por)
select v.id, '00000000-0000-0000-0000-0000000008c3', 'tardanza', 'amonestacion', 'borrador',
       date '2025-01-05', date '2025-01-10',
       '[{"fecha":"2025-01-07","minutos":14}]'::jsonb, '00000000-0000-0000-0000-0000000008c2'
from (values
  ('00000000-0000-0000-0000-0000000008d1'::uuid),
  ('00000000-0000-0000-0000-0000000008d2'::uuid),
  ('00000000-0000-0000-0000-0000000008d3'::uuid),
  ('00000000-0000-0000-0000-0000000008d4'::uuid)) as v(id);
set session_replication_role = origin;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ee000000-0000-0000-0000-0000000008ff","role":"authenticated"}';

-- ── 1 · Con la política en TRUE, todo sigue como en la 0228 ─────────────────
update configuracion set valor = 'true'::jsonb where clave = 'disciplina_descargo_previo';

select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000008d1') $$,
  '%comunicar los cargos%',
  'con la política activa, sin cargos comunicados no se firma');

-- ── 2 · Sin la clave, TAMBIÉN se exige ──────────────────────────────────────
-- Es el caso que más importa: una configuración borrada por accidente no puede
-- abrir la firma sin que nadie lo haya decidido.
delete from configuracion where clave = 'disciplina_descargo_previo';

select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000008d1') $$,
  '%comunicar los cargos%',
  'sin la clave de configuración se exige igual');

-- ── 3 · Y con un valor que nadie esperaba, también ──────────────────────────
insert into configuracion (clave, valor, descripcion)
values ('disciplina_descargo_previo', '"quizas"'::jsonb, 'valor inesperado, a propósito');

select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000008d1') $$,
  '%comunicar los cargos%',
  'un valor raro no releva del trámite');

-- ── 4 · Con la política en FALSE, se firma sin nada de eso ──────────────────
update configuracion set valor = 'false'::jsonb where clave = 'disciplina_descargo_previo';

select lives_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000008d1') $$,
  'con la política en false, la amonestación se firma sin descargo previo');

select is(
  (select estado from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000008d1'),
  'firmado',
  'y queda firmada de verdad, con su estado');

-- ── 5 · Pero el documento dice bajo qué política se firmó ───────────────────
-- Si esto deja de cumplirse, la política se vuelve indistinguible de un olvido.
select ok(
  (select observacion like '%sin descargo previo registrado%'
      and observacion like '%disciplina_descargo_previo = false%'
     from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000008d1'),
  'el expediente deja escrito que se firmó bajo la política de descargo verbal');

-- ── 6 · El que SÍ tuvo su descargo no explica nada ──────────────────────────
-- El trámite se siembra con el rol postgres: bajo `authenticated`, la RLS
-- descarta el UPDATE sin decir nada —cero filas, cero errores— y el documento
-- llegaría a la firma sin descargo, que es justo lo contrario de lo que aquí
-- se quiere probar.
set local role postgres;
update expediente_disciplinario
   set cargos_comunicados_at = now() - interval '5 days',
       descargo_vence_at     = now() - interval '2 days',
       descargo_acogido      = 'sin_descargo'
 where id = '00000000-0000-0000-0000-0000000008d2';
set local role authenticated;

select lives_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000008d2') $$,
  'un documento con su trámite completo se firma igual');

select ok(
  (select observacion is null from expediente_disciplinario
    where id = '00000000-0000-0000-0000-0000000008d2'),
  'y no se le agrega ninguna nota de política: no le hace falta');

-- ── 7 · El numeral 60.5 no depende de la política ───────────────────────────
-- Se publica un Reglamento vigente desde antes de los hechos y sin acuse: la
-- firma tiene que frenar aunque el descargo previo esté relevado.
set local role postgres;
insert into documentos_institucionales (tipo, version, titulo, documento, vigente_desde, publicado_por)
values ('rit', 99, 'RIT de laboratorio', 'documento de prueba', date '2024-12-01',
        '00000000-0000-0000-0000-0000000008c2');
set local role authenticated;

select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000008d3') $$,
  '%entrega del Reglamento%',
  'sin constancia del Reglamento no se firma, tenga la política el valor que tenga');

select * from finish();
rollback;
