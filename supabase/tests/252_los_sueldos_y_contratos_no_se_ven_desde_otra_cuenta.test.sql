-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 252_los_sueldos_y_contratos_no_se_ven_desde_otra_cuenta.test.sql
-- ============================================================================
-- TRES TABLAS CON LO MÁS SENSIBLE QUE GUARDA ESTE SISTEMA, Y NADIE COMPROBABA
-- QUE SUS POLICIES PROTEGIERAN DE VERDAD.
--
--     contratos_generados            remuneración y PDF firmado   (0272 / 0287)
--     asignaciones_regimen_pension   a qué AFP aporta cada quien  (0261)
--     educacion_comprobantes         los papeles de un pago hecho (0290)
--
-- Las tres tienen `policies` escritas y bien pensadas. Lo que faltaba es que
-- **algún test cambiara de usuario**: todos los que las tocan corren con una
-- sola sesión admin de principio a fin, así que un error futuro en cualquiera de
-- las tres no lo detectaría nadie — se enteraría alguien mirando por accidente
-- el sueldo o el contrato de otra persona.
--
-- ── POR QUÉ ESTA PRUEBA SE ESCRIBE HOY ─────────────────────────────────────
--
-- El 2026-08-26, una imagen nueva de Supabase abrió 105 de 258 funciones a quien
-- no ha iniciado sesión, y solo lo cazaron DOS aserciones — las dos únicas que
-- comprobaban permisos. Todo lo demás estaba protegido por costumbre, no por
-- medición. Esto es la misma lección aplicada a las tablas.
--
-- ── LAS DOS COSAS QUE HAY QUE CAMBIAR, Y SON DISTINTAS ─────────────────────
--
--   1. QUIÉN ERES  → `set_config('request.jwt.claim.sub', …)`, que es lo que
--      leen `fn_persona_actual_id()` y `fn_es_admin_o_lider()`.
--   2. CON QUÉ ROL PREGUNTAS → `set local role authenticated`.
--
-- La segunda NO es decorativa, y omitirla es la trampa: **pgTAP corre como
-- `postgres`, que es superusuario y se salta la RLS entera**. Sin ella, la
-- consulta devuelve la fila de la otra persona y la prueba pasa —o falla— por el
-- motivo equivocado. Está documentado en la prueba 198, que es de donde sale
-- este patrón.
--
-- ── Y LA COMPROBACIÓN 1 NO ES BUROCRACIA ───────────────────────────────────
--
-- Las demás miran `count(*) = 0`, y un cero pasa igual si el laboratorio no se
-- construyó. La primera comprueba, como superusuario, que las tres filas EXISTEN
-- — si no, todo lo de abajo estaría verde sin haber comprobado nada.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000bbb0000', 'ZZRLS', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-00000bbb00ad', 'RlsAdmin', 'Lab', '00000000-0000-0000-0000-00000bbb0000', 'admin', 'x', '00000000-0000-0000-0000-00000bbbf0ad', '2024-01-01'),
  ('00000000-0000-0000-0000-00000bbb0001', 'RlsAna',   'Lab', '00000000-0000-0000-0000-00000bbb0000', 'integrante', 'x', '00000000-0000-0000-0000-00000bbbf001', '2024-01-01'),
  ('00000000-0000-0000-0000-00000bbb0002', 'RlsBea',   'Lab', '00000000-0000-0000-0000-00000bbb0000', 'integrante', 'x', '00000000-0000-0000-0000-00000bbbf002', '2024-01-01');
set session_replication_role = origin;

-- Todo esto es de ANA. Bea no debería ver nada, y Ana solo lo suyo.
insert into contratos_generados (id, persona_id, tipo, cargo, sede_id, remuneracion_mensual,
                                 fecha_inicio, fecha_fin, documento_html, generado_por)
values ('00000000-0000-0000-0000-00000bbb0c01', '00000000-0000-0000-0000-00000bbb0001',
        'nuevo', 'Asesora', '00000000-0000-0000-0000-00000bbb0000', 1950,
        '2026-01-01', '2026-12-31', '<p>lab</p>', '00000000-0000-0000-0000-00000bbb00ad');

insert into asignaciones_regimen_pension (id, persona_id, regimen, vigente_desde, asignado_por)
values ('00000000-0000-0000-0000-00000bbb0a01', '00000000-0000-0000-0000-00000bbb0001',
        'onp', '2026-01-01', '00000000-0000-0000-0000-00000bbb00ad');

-- El techo del 75 % y el «no excede el comprobante» son de la 0281: con
-- costo_declarado 400 y cobertura 75, el monto no puede pasar de 300.
insert into asignaciones_educacion (id, persona_id, monto, institucion, costo_declarado,
                                    cobertura_pct, beneficiario, vigente_desde, vigente_hasta,
                                    registrado_por)
values ('00000000-0000-0000-0000-00000bbb0e01', '00000000-0000-0000-0000-00000bbb0001',
        200, 'Instituto de laboratorio', 400, 75, 'trabajador',
        '2026-01-01', '2026-12-31', '00000000-0000-0000-0000-00000bbb00ad');

insert into educacion_comprobantes (id, asignacion_id, storage_path, mes_cubierto, subido_por)
values ('00000000-0000-0000-0000-00000bbb0e02', '00000000-0000-0000-0000-00000bbb0e01',
        'lab/comprobante.pdf', '2026-01-01', '00000000-0000-0000-0000-00000bbb00ad');

-- ── 1 · El laboratorio existe ──────────────────────────────────────────────
-- Como `postgres`, o sea saltándose la RLS: las tres filas están puestas.
select is(
  (select (select count(*) from contratos_generados where persona_id = '00000000-0000-0000-0000-00000bbb0001')
        + (select count(*) from asignaciones_regimen_pension where persona_id = '00000000-0000-0000-0000-00000bbb0001')
        + (select count(*) from educacion_comprobantes where asignacion_id = '00000000-0000-0000-0000-00000bbb0e01'))::int,
  3,
  'las tres filas sensibles de Ana existen: lo de abajo mide algo'
);

-- ── 2 y 3 · El contrato: Bea no, Ana sí ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000bbbf002', true);
set local role authenticated;
select is(
  (select count(*)::int from contratos_generados),
  0,
  'una companera NO ve el contrato de Ana, ni su remuneracion'
);
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000bbbf001', true);
set local role authenticated;
select is(
  (select count(*)::int from contratos_generados),
  1,
  'y Ana SI ve el suyo: la policy no bloquea a quien debe pasar'
);
reset role;

-- ── 4, 5 y 6 · El regimen de pension: solo admin o lider ───────────────────
-- Esta policy NO tiene clausula de «tu propia fila»: dice solo
-- `fn_es_admin_o_lider()`. Asi que ni Bea ni la propia Ana ven la tabla cruda.
-- Se comprueban las tres para que la decision quede escrita: si algun dia
-- alguien le agrega el «o es tuya», esta prueba se lo va a decir.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000bbbf002', true);
set local role authenticated;
select is(
  (select count(*)::int from asignaciones_regimen_pension),
  0,
  'una companera NO ve a que AFP aporta Ana'
);
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000bbbf001', true);
set local role authenticated;
select is(
  (select count(*)::int from asignaciones_regimen_pension),
  0,
  'ni la propia Ana ve la tabla cruda: la policy es solo de admin o lider (0261)'
);
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000bbbf0ad', true);
set local role authenticated;
select is(
  (select count(*)::int from asignaciones_regimen_pension),
  1,
  'y el admin SI la ve: la policy no bloquea a quien debe pasar'
);
reset role;

-- ── 7 y 8 · Los comprobantes de educacion ──────────────────────────────────
-- Su policy llega por `asignaciones_educacion`: se ve el comprobante si eres
-- admin o lider, o si la asignacion es tuya.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000bbbf002', true);
set local role authenticated;
select is(
  (select count(*)::int from educacion_comprobantes),
  0,
  'una companera NO ve los papeles de educacion de Ana'
);
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000bbbf001', true);
set local role authenticated;
select is(
  (select count(*)::int from educacion_comprobantes),
  1,
  'y Ana SI ve los suyos'
);
reset role;

select * from finish();
rollback;
