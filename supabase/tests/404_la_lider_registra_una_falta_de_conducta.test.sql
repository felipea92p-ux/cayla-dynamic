-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 404_la_lider_registra_una_falta_de_conducta.test.sql
-- ============================================================================
-- La 0510 abre la causal «conducta» y cierra quién puede imponer una sanción.
-- Lo que fija esta prueba, en orden de importancia:
--   · Solo firma quien tiene contrato de trabajo: ni la Socia por honorarios
--     ni la practicante de DO, aunque su rol las deje. Ni nadie sobre sí
--     misma. Ni una líder sobre otra líder. Por la lista Y por la fila.
--   · La líder actúa sobre integrantes de su sede, nunca sobre otra líder ni
--     sobre sí misma, y solo si está en planilla. DO tramita aunque sea
--     practicante: instruir no es imponer.
--   · La conducta se registra citando una falta del catálogo vigente, con su
--     fecha, la fecha en que se supo y un relato; el esquema rechaza la que no
--     lo trae. El mismo hecho no se registra dos veces.
--   · El catálogo no se edita.
--   · El antecedente que agrava es el de la misma falta, entregado y dentro de
--     los doce meses; tres amonestaciones leves hacen significativa la cuarta.
--   · La líder no ve en su pantalla lo que DO le abrió a otra líder.
-- ============================================================================
begin;
select plan(51);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000c0d01', 'ZZCD1', 'Sede de laboratorio', true),
  ('00000000-0000-0000-0000-0000000c0d02', 'ZZCD2', 'Otra sede de laboratorio', true);

-- Con cuenta. `replica` para no chocar con la FK a auth.users, como en la 384.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-0000000c0d11', 'Gerencia',   'Lab', '00000000-0000-0000-0000-0000000c0d01', 'admin',           'x', '00000000-0000-0000-0000-0000000c0da1', '2020-01-01', 'activo', 'planilla',    null),
  ('00000000-0000-0000-0000-0000000c0d12', 'DoPractica', 'Lab', '00000000-0000-0000-0000-0000000c0d01', 'lider_do',        'x', '00000000-0000-0000-0000-0000000c0da2', '2025-01-01', 'activo', 'practicante', 'profesional'),
  ('00000000-0000-0000-0000-0000000c0d13', 'Socia',      'Lab', '00000000-0000-0000-0000-0000000c0d01', 'admin',           'x', '00000000-0000-0000-0000-0000000c0da3', '2020-01-01', 'activo', 'rxh',         null),
  ('00000000-0000-0000-0000-0000000c0d14', 'LiderUno',   'Lab', '00000000-0000-0000-0000-0000000c0d01', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000c0da4', '2021-01-01', 'activo', 'planilla',    null),
  ('00000000-0000-0000-0000-0000000c0d15', 'LiderDos',   'Lab', '00000000-0000-0000-0000-0000000c0d01', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000c0da5', '2021-01-01', 'activo', 'planilla',    null),
  ('00000000-0000-0000-0000-0000000c0d16', 'LiderRxh',   'Lab', '00000000-0000-0000-0000-0000000c0d01', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000c0da6', '2021-01-01', 'activo', 'rxh',         null),
  ('00000000-0000-0000-0000-0000000c0d17', 'Integrante', 'Lab', '00000000-0000-0000-0000-0000000c0d01', 'integrante',      'x', '00000000-0000-0000-0000-0000000c0da7', '2023-01-01', 'activo', 'planilla',    null);
set session_replication_role = origin;

-- Sin cuenta.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, tipo_vinculo, practicante_modalidad, sueldo_fijo) values
  ('00000000-0000-0000-0000-0000000c0d18', 'OtraSede',   'Lab', '00000000-0000-0000-0000-0000000c0d02', 'integrante', 'x', '2023-01-01', 'activo', 'planilla',    null,             false),
  ('00000000-0000-0000-0000-0000000c0d19', 'Practicante','Lab', '00000000-0000-0000-0000-0000000c0d01', 'integrante', 'x', '2025-01-01', 'activo', 'practicante', 'preprofesional', false),
  ('00000000-0000-0000-0000-0000000c0d1a', 'SueldoFijo', 'Lab', '00000000-0000-0000-0000-0000000c0d01', 'integrante', 'x', '2023-01-01', 'activo', 'planilla',    null,             true),
  ('00000000-0000-0000-0000-0000000c0d1b', 'OtraAdmin',  'Lab', '00000000-0000-0000-0000-0000000c0d01', 'admin',      'x', '2020-01-01', 'activo', 'planilla',    null,             false);

-- El descargo previo como hoy en producción (0267), para que la firma real de
-- abajo pruebe lo que esta migración agrega y no otra cosa.
insert into configuracion (clave, valor) values ('disciplina_descargo_previo', 'false'::jsonb)
on conflict (clave) do update set valor = excluded.valor;
-- Y el Reglamento entregado a la integrante, si hay alguno publicado (60.5).
insert into documentos_acuses (documento_id, persona_id, via, nombre_declarado)
select id, '00000000-0000-0000-0000-0000000c0d17', 'sistema', 'Integrante Lab'
  from documentos_institucionales where tipo = 'rit' order by version desc limit 1;

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true);
$$;

-- ── EL CATÁLOGO ─────────────────────────────────────────────────────────────
select is((select count(*)::int from faltas_catalogo where rit_version = 4.0), 20,
  'CATÁLOGO · los 20 literales de los numerales 53.1 y 53.2 del RIT v4.0');
select is((select count(*)::int from faltas_catalogo where rit_version = 4.0 and se_registra_a_mano), 17,
  'CATÁLOGO · 17 se registran a mano; el 53.2 a) lo suma el sistema y el b) y el c) los miden los motores');
select throws_like($$ update faltas_catalogo set texto = 'otra cosa' where numeral = '53.1' and literal = 'd' $$,
  '%no se edita%', 'CATÁLOGO · una fila no se edita: hay documentos que la citan');
select throws_like($$ delete from faltas_catalogo where numeral = '53.1' and literal = 'd' $$,
  '%no se edita ni se borra%', 'CATÁLOGO · ni se borra');
select throws_ok($$ insert into faltas_catalogo values (9.9, '53.1', 'z', 'significativa', 'x', true) $$,
  '23514', null, 'CATÁLOGO · la gravedad la da el numeral: un 53.1 no puede ser significativo');

-- ── QUIÉN ACTÚA ─────────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c0da4');   -- LiderUno
select is(fn_expediente_puede_actuar('00000000-0000-0000-0000-0000000c0d17', 'amonestacion'), true,
  'ACTÚA · la líder amonesta a una integrante de su sede');
select is(fn_expediente_puede_actuar('00000000-0000-0000-0000-0000000c0d17', 'suspension'), false,
  'ACTÚA · pero no la suspende (54.4 c)');
select is(fn_expediente_puede_actuar('00000000-0000-0000-0000-0000000c0d15', 'amonestacion'), false,
  'ACTÚA · a otra líder de su misma sede la amonesta DO, no ella');
select is(fn_expediente_puede_actuar('00000000-0000-0000-0000-0000000c0d14', 'verbal'), false,
  'ACTÚA · ni sobre sí misma, ni siquiera una llamada verbal');
select is(fn_expediente_puede_actuar('00000000-0000-0000-0000-0000000c0d18', 'amonestacion'), false,
  'ACTÚA · ni sobre una integrante de otra sede (54.4 b)');

select pg_temp.como('00000000-0000-0000-0000-0000000c0da6');   -- LiderRxh
select is(fn_expediente_puede_actuar('00000000-0000-0000-0000-0000000c0d17', 'amonestacion'), false,
  'ACTÚA · una líder por honorarios no ejerce poder disciplinario (RIT 2.9)');

select pg_temp.como('00000000-0000-0000-0000-0000000c0da2');   -- DoPractica
select is(fn_expediente_puede_actuar('00000000-0000-0000-0000-0000000c0d17', 'suspension'), true,
  'ACTÚA · DO tramita aunque sea practicante: instruir no es imponer (54.4 c)');

-- ── REGISTRAR LA CONDUCTA ───────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c0da4');   -- LiderUno
select lives_ok($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d17', '53.2', 'h', 'amonestacion',
    fn_hoy_lima() - 3, fn_hoy_lima() - 2, 'Respondió de mala manera a una clienta que pedía un cambio de talla.') $$,
  'REGISTRA · la líder registra una amonestación por trato descortés a una clienta (53.2 h)');

create temp table _h as
  select * from expediente_disciplinario
   where persona_id = '00000000-0000-0000-0000-0000000c0d17' and tipo_causal = 'conducta';

select is((select count(*)::int from _h), 1, 'REGISTRA · queda un documento');
select is((select estado || '·' || nivel || '·' || falta_numeral || ' ' || falta_literal || ')' from _h),
  'borrador·amonestacion·53.2 h)', 'REGISTRA · en borrador, citando la falta exacta');
select is((select conocido_el from _h), fn_hoy_lima() - 2,
  'REGISTRA · guarda cuándo se supo del hecho (52.6), que no es la fecha del hecho');
select is((select hechos->0->>'fecha' from _h), to_char(fn_hoy_lima() - 3, 'YYYY-MM-DD'),
  'REGISTRA · el hecho lleva su fecha en ISO, como los demás hechos del expediente');
select is((select creado_por from _h), '00000000-0000-0000-0000-0000000c0d14'::uuid,
  'REGISTRA · y consta quién lo registró');

select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d17', '53.2', 'h', 'verbal',
    fn_hoy_lima() - 3, fn_hoy_lima() - 2, 'Otra vez el mismo hecho, contado por otra persona.') $$,
  '%ya está registrado%', 'NON BIS IN IDEM · el mismo hecho (persona, falta, día) no se registra dos veces');
select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d17', '53.2', 'b', 'amonestacion',
    fn_hoy_lima() - 3, fn_hoy_lima() - 2, 'Llegó tarde tres veces este mes, según la líder.') $$,
  '%no se registra a mano%', 'REGISTRA · las tardanzas no se registran a mano: las mide su motor');
select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d17', '53.1', 'z', 'amonestacion',
    fn_hoy_lima() - 3, fn_hoy_lima() - 2, 'Una conducta que el Reglamento no describe.') $$,
  '%no está en el catálogo%', 'TIPICIDAD · lo que no está en el artículo 53 no se sanciona (52.3)');
select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d17', '53.1', 'd', 'amonestacion',
    fn_hoy_lima() - 3, fn_hoy_lima() - 4, 'Usó el teléfono mientras atendía a una clienta.') $$,
  '%antes de que ocurra%', 'FECHAS · no se sabe de un hecho antes de que ocurra');
select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d17', '53.1', 'd', 'amonestacion',
    fn_hoy_lima() + 1, fn_hoy_lima() + 1, 'Usó el teléfono mientras atendía a una clienta.') $$,
  '%no puede ser futura%', 'FECHAS · un hecho no puede ser de mañana');
select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d17', '53.1', 'd', 'amonestacion',
    fn_hoy_lima() - 1, fn_hoy_lima(), 'Teléfono.') $$,
  '%Describe qué pasó%', 'RELATO · una palabra no es un hecho (55.3)');
select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d15', '53.1', 'd', 'amonestacion',
    fn_hoy_lima() - 1, fn_hoy_lima(), 'Usó el teléfono mientras atendía a una clienta.') $$,
  '%Sin permiso%', 'REGISTRA · la líder no registra conducta de otra líder');
select lives_ok($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d1a', '53.1', 'c', 'verbal',
    fn_hoy_lima() - 1, fn_hoy_lima(), 'Llegó sin el uniforme de la tienda en día de evento.') $$,
  'ALCANCE · el sueldo fijo no excluye de la conducta: su pago no depende de horas, el trato a una clienta sí');

select pg_temp.como('00000000-0000-0000-0000-0000000c0da6');   -- LiderRxh
select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d17', '53.1', 'd', 'amonestacion',
    fn_hoy_lima() - 1, fn_hoy_lima(), 'Usó el teléfono mientras atendía a una clienta.') $$,
  '%Sin permiso%', 'REGISTRA · una líder por honorarios no registra conducta');

select pg_temp.como('00000000-0000-0000-0000-0000000c0da1');   -- Gerencia
select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d19', '53.1', 'd', 'amonestacion',
    fn_hoy_lima() - 1, fn_hoy_lima(), 'Usó el teléfono mientras atendía a una clienta.') $$,
  '%no le alcanza el régimen disciplinario%', 'ALCANCE · a una practicante no le alcanza el régimen disciplinario (RIT 2.6)');
select throws_like($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d17', '53.2', 'g', 'suspension',
    fn_hoy_lima() - 1, fn_hoy_lima(), 'Cerró la caja sin cuadrar y sin avisar a nadie.') $$,
  '%Una suspensión la decide DO%', 'NIVEL · por conducta, esta entrega registra verbal y amonestación');
-- DO abre un caso sobre una líder: es la vía para ella.
select lives_ok($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d15', '53.2', 'e', 'amonestacion',
    fn_hoy_lima() - 2, fn_hoy_lima() - 1, 'No publicó el rol de turnos de la semana pese a la instrucción expresa.') $$,
  'DO · a una líder la amonesta DO');
select lives_ok($$
  select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0d1b', '53.1', 'e', 'verbal',
    fn_hoy_lima() - 2, fn_hoy_lima() - 1, 'No actualizó su domicilio pese a habérselo pedido dos veces.') $$,
  'DO · y Gerencia puede abrir uno sobre otra persona de administración');

-- ── EL ESQUEMA EXIGE LA FORMA ───────────────────────────────────────────────
select throws_ok($$
  insert into expediente_disciplinario (persona_id, tipo_causal, nivel, hechos, periodo_desde, periodo_hasta, creado_por)
  values ('00000000-0000-0000-0000-0000000c0d17', 'conducta', 'amonestacion',
          '[{"fecha":"2026-09-01","relato":"Un relato suficientemente largo para pasar."}]', '2026-09-01', '2026-09-01',
          '00000000-0000-0000-0000-0000000c0d11') $$,
  '23514', null, 'ESQUEMA · una conducta sin falta citada ni fecha de conocimiento no existe');
select throws_ok($$
  insert into expediente_disciplinario (persona_id, tipo_causal, nivel, hechos, periodo_desde, periodo_hasta, creado_por,
                                        falta_rit_version, falta_numeral, falta_literal, conocido_el)
  values ('00000000-0000-0000-0000-0000000c0d17', 'tardanza', 'amonestacion', '[]', '2026-09-01', '2026-09-30',
          '00000000-0000-0000-0000-0000000c0d11', 4.0, '53.1', 'd', '2026-10-01') $$,
  '23514', null, 'ESQUEMA · una tardanza no cita un literal de conducta: son escaleras distintas (56.5)');
select throws_ok($$
  insert into expediente_disciplinario (persona_id, tipo_causal, nivel, hechos, periodo_desde, periodo_hasta, creado_por,
                                        falta_rit_version, falta_numeral, falta_literal, conocido_el)
  values ('00000000-0000-0000-0000-0000000c0d17', 'conducta', 'amonestacion',
          '{"fecha":"2026-09-01","relato":"Un relato suficientemente largo para pasar."}', '2026-09-01', '2026-09-01',
          '00000000-0000-0000-0000-0000000c0d11', 4.0, '53.1', 'd', '2026-09-02') $$,
  '23514', null, 'ESQUEMA · los hechos son una lista: un objeto suelto se rechaza sin reventar');
select throws_ok($$
  insert into expediente_disciplinario (persona_id, tipo_causal, nivel, hechos, periodo_desde, periodo_hasta, creado_por,
                                        falta_rit_version, falta_numeral, falta_literal, conocido_el)
  values ('00000000-0000-0000-0000-0000000c0d17', 'conducta', 'amonestacion',
          '[{"relato":"Un relato suficientemente largo para pasar."}]', '2026-09-01', '2026-09-01',
          '00000000-0000-0000-0000-0000000c0d11', 4.0, '53.1', 'd', '2026-09-02') $$,
  '23514', null, 'ESQUEMA · un hecho sin fecha se rechaza: el CHECK no deja pasar un NULL');

-- El otro procedimiento queda abierto: una falta GRAVE de conducta (53.3) se
-- imputa por el artículo 57 y cita el artículo 25 de la LPCL, no el catálogo.
select pg_temp.como('00000000-0000-0000-0000-0000000c0da1');   -- Gerencia
select lives_ok($$ select fn_expediente_crear_borrador('00000000-0000-0000-0000-0000000c0d17',
       'conducta', 'imputacion', '[{"fecha":"2026-09-20","tipo":"falta grave"}]'::jsonb, '2026-09-20', '2026-09-20') $$,
  'ESQUEMA · DO sigue preparando una imputación por falta grave de conducta, sin catálogo (art. 57)');
select throws_ok($$ select fn_expediente_crear_borrador('00000000-0000-0000-0000-0000000c0d17',
       'conducta', 'amonestacion', '[{"fecha":"2026-09-21","tipo":"conducta"}]'::jsonb, '2026-09-21', '2026-09-21') $$,
  '23514', null, 'ESQUEMA · pero una amonestación por conducta sin su falta citada no entra ni por la vía genérica');

-- ── QUIÉN FIRMA ─────────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c0da4');   -- LiderUno
select is((select count(*)::int from fn_expediente_firmantes((select id from _h))
            where persona_id in ('00000000-0000-0000-0000-0000000c0d14', '00000000-0000-0000-0000-0000000c0d15', '00000000-0000-0000-0000-0000000c0d11')), 3,
  'LISTA · firman las dos líderes en planilla de la sede y Gerencia');
select is((select count(*)::int from fn_expediente_firmantes((select id from _h))
            where persona_id in ('00000000-0000-0000-0000-0000000c0d13', '00000000-0000-0000-0000-0000000c0d12', '00000000-0000-0000-0000-0000000c0d16')), 0,
  'LISTA · no figuran la Socia por honorarios, la practicante de DO ni la líder por honorarios');

-- Por la vía real: la firma elige a la Socia. Su rol pasa el 54.4; su vínculo no.
select throws_like(format($$ select fn_expediente_firmar(%L, '00000000-0000-0000-0000-0000000c0d13') $$, (select id from _h)),
  '%contrato de trabajo%', 'FIRMA · la Socia por honorarios no impone una sanción aunque su rol lo permita');
select is((select estado from expediente_disciplinario where id = (select id from _h)), 'borrador',
  'FIRMA · y el intento no deja el documento a medias');
select lives_ok(format($$ select fn_expediente_firmar(%L, null) $$, (select id from _h)),
  'FIRMA · la líder en planilla firma la amonestación de su integrante');

-- La red sobre la fila, por cualquier camino.
select throws_like($$
  update expediente_disciplinario
     set estado = 'firmado', firmante_id = '00000000-0000-0000-0000-0000000c0d12', firmado_at = now(), correlativo = 'LAB/CD-1'
   where persona_id = '00000000-0000-0000-0000-0000000c0d15' and tipo_causal = 'conducta' $$,
  '%contrato de trabajo%', 'FILA · la practicante de DO no queda como firmante ni por un UPDATE directo');
select throws_like($$
  update expediente_disciplinario
     set estado = 'firmado', firmante_id = '00000000-0000-0000-0000-0000000c0d14', firmado_at = now(), correlativo = 'LAB/CD-2'
   where persona_id = '00000000-0000-0000-0000-0000000c0d15' and tipo_causal = 'conducta' $$,
  '%la amonesta DO%', 'FILA · una líder no firma la amonestación de otra líder');
select throws_like($$
  update expediente_disciplinario
     set estado = 'firmado', firmante_id = '00000000-0000-0000-0000-0000000c0d1b', firmado_at = now(), correlativo = 'LAB/CD-3'
   where persona_id = '00000000-0000-0000-0000-0000000c0d1b' and tipo_causal = 'conducta' $$,
  '%sobre sí misma%', 'FILA · nadie firma una sanción sobre sí misma');

-- ── LO QUE PESA ANTES DE REGISTRAR ──────────────────────────────────────────
-- Tres amonestaciones leves entregadas (53.1 d) y una vieja de hace 13 meses.
insert into expediente_disciplinario (persona_id, tipo_causal, nivel, estado, hechos, periodo_desde, periodo_hasta,
  falta_rit_version, falta_numeral, falta_literal, conocido_el,
  firmante_id, firmado_at, correlativo, medio_entrega, entregado_at, creado_por)
select '00000000-0000-0000-0000-0000000c0d17', 'conducta', 'amonestacion', 'entregado',
       jsonb_build_array(jsonb_build_object('fecha', to_char(d, 'YYYY-MM-DD'), 'relato', 'Usó el teléfono mientras atendía a una clienta.')),
       d, d, 4.0, '53.1', 'd', d,
       '00000000-0000-0000-0000-0000000c0d11', now(), 'LAB/ANT-' || n, 'fisico', fn_cierre_lima(d) - interval '1 hour',
       '00000000-0000-0000-0000-0000000c0d11'
  from (values (1, fn_hoy_lima() - 300), (2, fn_hoy_lima() - 200), (3, fn_hoy_lima() - 100), (4, fn_hoy_lima() - 400)) v(n, d);

select pg_temp.como('00000000-0000-0000-0000-0000000c0da4');   -- LiderUno
select is((fn_conducta_antecedentes('00000000-0000-0000-0000-0000000c0d17', '53.1', 'd', fn_hoy_lima()))->>'amonestaciones_leves_vigentes', '3',
  '53.2 a) · cuenta las tres leves de los últimos doce meses, no la de hace trece');
select is((fn_conducta_antecedentes('00000000-0000-0000-0000-0000000c0d17', '53.1', 'd', fn_hoy_lima()))->>'significativa_por_acumulacion', 'true',
  '53.2 a) · con tres, la cuarta leve es falta significativa');
select is((fn_conducta_antecedentes('00000000-0000-0000-0000-0000000c0d17', '53.1', 'd', fn_hoy_lima()))->'antecedente_vigente'->>'correlativo', 'LAB/ANT-3',
  '56.4 · el antecedente vigente por la misma falta es el más reciente');
select is((fn_conducta_antecedentes('00000000-0000-0000-0000-0000000c0d17', '53.2', 'h', fn_hoy_lima()))->>'antecedente_vigente', null,
  '56.5 · una amonestación por el teléfono no es escalón para una por trato a una clienta');

-- ── LO QUE VE CADA LÍDER ────────────────────────────────────────────────────
-- La sesión se presta ANTES de bajar de rol: `authenticated` no puede
-- ejecutar la función temporal que la presta.
select pg_temp.como('00000000-0000-0000-0000-0000000c0da4');   -- LiderUno
set local role authenticated;
select is((select count(*)::int from expediente_disciplinario where persona_id = '00000000-0000-0000-0000-0000000c0d15'), 0,
  'VE · la líder no ve en su pantalla el caso que DO le abrió a otra líder');
select ok((select count(*) from expediente_disciplinario where persona_id = '00000000-0000-0000-0000-0000000c0d17') > 0,
  'VE · y sigue viendo los de sus integrantes');
reset role;

select * from finish();
rollback;
