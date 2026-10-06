-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 412_la_persona_ve_como_va_con_sus_tardanzas.test.sql
-- ============================================================================
-- La 0517 repite la cuenta del mes de `fn_tardanzas_resumen` para que una
-- integrante pueda ver la suya. Esta prueba es el FRENO de esa duplicación:
-- compara las dos en los casos donde una regla se puede olvidar, con fechas
-- fijas (julio de 2026, como la 50) para no depender del día en que corra.
--
--   · Lo que Disciplina cuenta y lo que la persona ve es EL MISMO número:
--     justificadas, de más de tres horas, ya citadas en un documento y las de
--     antes del corte no suman en ninguno de los dos.
--   · El mes anterior no se cuela.
--   · A quien no se le mide —sueldo fijo, por honorarios— no se le muestra nada.
--   · Con una imputación abierta tampoco: lo decide DO, no un contador.
--   · Una persona solo ve la suya.
-- ============================================================================
begin;
select plan(17);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000c1701', 'ZZCV1', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo, sueldo_fijo, fecha_cese) values
  ('00000000-0000-0000-0000-0000000c1711', 'Gerencia', 'Lab', '00000000-0000-0000-0000-0000000c1701', 'admin',      'x', '00000000-0000-0000-0000-0000000c17a1', '2020-01-01', 'activo', 'planilla', false, null),
  ('00000000-0000-0000-0000-0000000c1712', 'MezclaA',  'Lab', '00000000-0000-0000-0000-0000000c1701', 'integrante', 'x', '00000000-0000-0000-0000-0000000c17a2', '2023-01-01', 'activo', 'planilla', false, null),
  ('00000000-0000-0000-0000-0000000c1713', 'ConCorte', 'Lab', '00000000-0000-0000-0000-0000000c1701', 'integrante', 'x', '00000000-0000-0000-0000-0000000c17a3', '2023-01-01', 'activo', 'planilla', false, null),
  ('00000000-0000-0000-0000-0000000c1714', 'SueldoFijo','Lab','00000000-0000-0000-0000-0000000c1701', 'integrante', 'x', '00000000-0000-0000-0000-0000000c17a4', '2023-01-01', 'activo', 'planilla', true, null),
  ('00000000-0000-0000-0000-0000000c1715', 'PorHonorarios','Lab','00000000-0000-0000-0000-0000000c1701','integrante','x', '00000000-0000-0000-0000-0000000c17a5', '2023-01-01', 'activo', 'rxh', false, null),
  ('00000000-0000-0000-0000-0000000c1716', 'ConImputacion','Lab','00000000-0000-0000-0000-0000000c1701','integrante','x','00000000-0000-0000-0000-0000000c17a6', '2023-01-01', 'activo', 'planilla', false, null),
  ('00000000-0000-0000-0000-0000000c1717', 'UnaSola',  'Lab', '00000000-0000-0000-0000-0000000c1701', 'integrante', 'x', '00000000-0000-0000-0000-0000000c17a7', '2023-01-01', 'activo', 'planilla', false, null),
  ('00000000-0000-0000-0000-0000000c1718', 'Inactiva', 'Lab', '00000000-0000-0000-0000-0000000c1701', 'integrante', 'x', '00000000-0000-0000-0000-0000000c17a8', '2023-01-01', 'inactivo', 'planilla', false, '2026-06-30');
set session_replication_role = origin;

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true);
$$;

-- ── MEZCLA A: seis días con tardanza, de los cuales solo TRES cuentan ───────
--   01/07 cuenta · 02/07 cuenta · 03/07 cuenta
--   06/07 justificada · 07/07 de más de tres horas · 08/07 ya citada en un documento
--   30/06 es del mes anterior
insert into jornadas (persona_id, fecha, minutos_tarde) values
  ('00000000-0000-0000-0000-0000000c1712', '2026-06-30', 10),
  ('00000000-0000-0000-0000-0000000c1712', '2026-07-01', 10),
  ('00000000-0000-0000-0000-0000000c1712', '2026-07-02', 10),
  ('00000000-0000-0000-0000-0000000c1712', '2026-07-03', 10),
  ('00000000-0000-0000-0000-0000000c1712', '2026-07-06', 10),
  ('00000000-0000-0000-0000-0000000c1712', '2026-07-07', 400),
  ('00000000-0000-0000-0000-0000000c1712', '2026-07-08', 10);
insert into tardanzas_justificadas (persona_id, fecha, motivo, creado_por) values
  ('00000000-0000-0000-0000-0000000c1712', '2026-07-06', 'salud', '00000000-0000-0000-0000-0000000c1711');
-- Un documento FIRMADO (no entregado) que ya cita el 08/07: el día no vuelve a contarse (52.5).
insert into expediente_disciplinario (persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
  firmante_id, firmado_at, correlativo, creado_por) values
  ('00000000-0000-0000-0000-0000000c1712', 'tardanza', 'amonestacion', 'firmado', '2026-07-08', '2026-07-08',
   '[{"fecha":"2026-07-08","minutos":10}]'::jsonb,
   '00000000-0000-0000-0000-0000000c1711', now(), 'LAB/CV-1', '00000000-0000-0000-0000-0000000c1711');

-- ── CON CORTE: una amonestación ENTREGADA que cubre hasta el 02/07 ──────────
--   01/07 y 02/07 ya se sancionaron: no cuentan. 03/07 y 04/07 sí.
insert into jornadas (persona_id, fecha, minutos_tarde) values
  ('00000000-0000-0000-0000-0000000c1713', '2026-07-01', 10),
  ('00000000-0000-0000-0000-0000000c1713', '2026-07-02', 10),
  ('00000000-0000-0000-0000-0000000c1713', '2026-07-03', 10),
  ('00000000-0000-0000-0000-0000000c1713', '2026-07-04', 10);
insert into expediente_disciplinario (persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
  firmante_id, firmado_at, correlativo, medio_entrega, entregado_at, creado_por) values
  ('00000000-0000-0000-0000-0000000c1713', 'tardanza', 'amonestacion', 'entregado', '2026-06-10', '2026-07-02', '[]'::jsonb,
   '00000000-0000-0000-0000-0000000c1711', '2026-07-03 12:00-05', 'LAB/CV-2', 'fisico', '2026-07-03 15:00-05', '00000000-0000-0000-0000-0000000c1711');

-- ── A QUIEN NO SE LE MIDE ───────────────────────────────────────────────────
insert into jornadas (persona_id, fecha, minutos_tarde)
select p, d, 10 from (values
    ('00000000-0000-0000-0000-0000000c1714'::uuid), ('00000000-0000-0000-0000-0000000c1715'::uuid),
    ('00000000-0000-0000-0000-0000000c1718'::uuid)) v(p),
  (values ('2026-07-01'::date), ('2026-07-02'::date), ('2026-07-03'::date)) f(d);

-- ── CON IMPUTACIÓN ABIERTA ──────────────────────────────────────────────────
insert into jornadas (persona_id, fecha, minutos_tarde) values
  ('00000000-0000-0000-0000-0000000c1716', '2026-07-10', 10);
insert into expediente_disciplinario (persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
  firmante_id, firmado_at, correlativo, medio_entrega, entregado_at, creado_por) values
  ('00000000-0000-0000-0000-0000000c1716', 'tardanza', 'imputacion', 'entregado', '2026-06-01', '2026-06-30', '[]'::jsonb,
   '00000000-0000-0000-0000-0000000c1711', '2026-07-01 12:00-05', 'LAB/CV-3', 'fisico', '2026-07-02 12:00-05', '00000000-0000-0000-0000-0000000c1711');

-- ── UNA SOLA TARDANZA ───────────────────────────────────────────────────────
insert into jornadas (persona_id, fecha, minutos_tarde) values ('00000000-0000-0000-0000-0000000c1717', '2026-07-05', 10);

-- La cuenta de Disciplina, con sesión de admin y fecha fija.
select pg_temp.como('00000000-0000-0000-0000-0000000c17a1');
create temp table _d as select * from fn_tardanzas_resumen('2026-07-23'::date);

-- ═══ MEZCLA A ═══════════════════════════════════════════════════════════════
select pg_temp.como('00000000-0000-0000-0000-0000000c17a2');
create temp table _a as select fn_mi_cuenta_de_tardanzas('2026-07-23') as c;
select is((select (c->>'tardanzas_mes')::int from _a), 3,
  'MEZCLA · suma 3: ni la justificada, ni la de más de tres horas, ni la ya citada, ni la del mes anterior');
select is((select (c->>'tardanzas_mes')::int from _a),
          (select tardanzas_mes from _d where persona_id = '00000000-0000-0000-0000-0000000c1712'),
  'LA MISMA CUENTA · lo que ve la persona es lo que ve DO: si una regla cambia en un lado y no en el otro, esta cae');
select is((select (c->>'minimo')::int from _a),
          (select minimo from _d where persona_id = '00000000-0000-0000-0000-0000000c1712'),
  'LA MISMA CUENTA · y el mínimo para el siguiente paso también');
select is((select c->>'nivel_siguiente' from _a),
          (select nivel_siguiente from _d where persona_id = '00000000-0000-0000-0000-0000000c1712'),
  'LA MISMA CUENTA · y el nombre de ese paso');
select is((select c->>'nivel_siguiente' from _a), 'amonestacion',
  'EL PASO · sin antecedentes, el siguiente es una amonestación (RIT 19.2 b)');
select is((select c->>'mes' from _a), '2026-07-01', 'EL MES · dice de qué mes es la cuenta');

-- ═══ CON CORTE ══════════════════════════════════════════════════════════════
select pg_temp.como('00000000-0000-0000-0000-0000000c17a3');
create temp table _b as select fn_mi_cuenta_de_tardanzas('2026-07-23') as c;
select is((select (c->>'tardanzas_mes')::int from _b), 2,
  'CORTE · lo ya sancionado hasta el 02/07 no vuelve a contarse (52.5): quedan el 03 y el 04');
select is((select (c->>'tardanzas_mes')::int from _b),
          (select tardanzas_mes from _d where persona_id = '00000000-0000-0000-0000-0000000c1713'),
  'LA MISMA CUENTA · también con corte');
select is((select c->>'nivel_siguiente' from _b), 'suspension',
  'EL PASO · con una amonestación vigente, el siguiente es una suspensión (RIT 19.2 c)');
select is((select (c->>'minimo')::int from _b), 2,
  'EL PASO · y con ella vigente bastan dos tardanzas en el mes: es el texto que cambia el recuadro');

-- ═══ A QUIEN NO SE LE MIDE ══════════════════════════════════════════════════
select pg_temp.como('00000000-0000-0000-0000-0000000c17a4');
select is(fn_mi_cuenta_de_tardanzas('2026-07-23'), null, 'NO SE MIDE · con sueldo fijo no hay cuenta que mostrar');
select pg_temp.como('00000000-0000-0000-0000-0000000c17a5');
select is(fn_mi_cuenta_de_tardanzas('2026-07-23'), null, 'NO SE MIDE · por honorarios, tampoco');
select pg_temp.como('00000000-0000-0000-0000-0000000c17a8');
select is(fn_mi_cuenta_de_tardanzas('2026-07-23'), null, 'NO SE MIDE · y quien ya no está activa, menos');

-- ═══ CON IMPUTACIÓN ABIERTA ═════════════════════════════════════════════════
select pg_temp.como('00000000-0000-0000-0000-0000000c17a6');
select is(fn_mi_cuenta_de_tardanzas('2026-07-23'), null,
  'IMPUTACIÓN · con un procedimiento abierto no se muestra un número: lo decide DO');

-- ═══ UNA SOLA TARDANZA: a ella sí se le dice que va bien ════════════════════
select pg_temp.como('00000000-0000-0000-0000-0000000c17a7');
select is((fn_mi_cuenta_de_tardanzas('2026-07-23')->>'tardanzas_mes')::int, 1,
  'UNA SOLA · lleva 1: Disciplina no la lista por estar lejos del umbral, pero ella sí lo ve');
select is((select count(*)::int from _d where persona_id = '00000000-0000-0000-0000-0000000c1717'), 0,
  'UNA SOLA · y confirma que Disciplina no la lista: por eso no se podía usar fn_tardanzas_resumen para esto');

-- ═══ SOLO LA SUYA ═══════════════════════════════════════════════════════════
-- Sin sesión no hay persona: no devuelve nada, no falla.
select set_config('request.jwt.claim.sub', '', true);
select is(fn_mi_cuenta_de_tardanzas('2026-07-23'), null, 'SIN SESIÓN · no hay persona, no hay cuenta');

select * from finish();
rollback;
