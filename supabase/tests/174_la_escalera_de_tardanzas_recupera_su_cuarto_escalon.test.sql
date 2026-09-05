-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 174_la_escalera_de_tardanzas_recupera_su_cuarto_escalon.test.sql
-- ============================================================================
-- El artículo 19.2 del Reglamento tiene CUATRO escalones y el sistema tenía
-- tres: saltaba de la primera suspensión a la imputación de cargos.
--
-- Lo caro no es saltarse un paso. El literal h) del artículo 25 de la LPCL
-- exige, para despedir por impuntualidad reiterada, «sanciones disciplinarias
-- previas de amonestaciones escritas y SUSPENSIONES» — en plural. Con una sola
-- suspensión en el legajo, la imputación que el sistema proponía no tenía con
-- qué sostenerse; y sobre la persona el efecto era el contrario y también malo:
-- se le abría un procedimiento de despido donde correspondía una suspensión.
--
-- Esta prueba recorre la escalera entera, escalón por escalón, sobre la misma
-- persona: amonestación → primera suspensión → SEGUNDA suspensión → imputación.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000e401', 'ZZ4ES', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000e402', 'AdminEscalera', 'Lab',
        '00000000-0000-0000-0000-00000000e401', 'admin', 'x',
        '00000000-0000-0000-0000-000000e40002', '2020-01-01', 'activo', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000e403', 'SubeLaEscalera', 'Lab',
        '00000000-0000-0000-0000-00000000e401', 'x', '2024-01-01', 'activo', 'planilla');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000e40002', true);

-- Un documento entregado del nivel que se quiera, para mover la escalera.
--
-- Las fechas de la suspensión van siempre que haya días: `chk_susp_completa` no
-- admite una suspensión que diga cuánto dura y no cuándo se cumple, y hace
-- bien — es el dato con el que la persona sabe qué días no viene.
create function pg_temp.entregar(p_nivel text, p_dias int, p_hasta date) returns void
language sql as $$
  insert into expediente_disciplinario
    (persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta,
     hechos, suspension_dias, suspension_desde, suspension_hasta,
     firmante_id, firmado_at, medio_entrega, entregado_at,
     correlativo, creado_por)
  values ('00000000-0000-0000-0000-00000000e403', 'tardanza', p_nivel, 'entregado',
          p_hasta, p_hasta, '[]'::jsonb, p_dias,
          case when p_dias is not null then p_hasta + 1 end,
          case when p_dias is not null then p_hasta + p_dias end,
          '00000000-0000-0000-0000-00000000e402', now(), 'fisico', now(),
          'ESC-' || p_nivel || '-' || p_hasta::text,
          '00000000-0000-0000-0000-00000000e402');
$$;

-- ── Escalón 1 · sin antecedentes ────────────────────────────────────────────
select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-00000000e403')),
          'amonestacion', '19.2 b) · sin antecedentes, toca amonestación');
select is((select minimo from fn_tardanza_escalon('00000000-0000-0000-0000-00000000e403')),
          3, '19.2 b) · y exige tres tardanzas en el periodo');

-- ── Escalón 2 · con amonestación vigente ────────────────────────────────────
select pg_temp.entregar('amonestacion', null, '2026-06-30');
select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-00000000e403')),
          'suspension', '19.2 c) · con amonestación vigente, toca la PRIMERA suspensión');
select is((select minimo from fn_tardanza_escalon('00000000-0000-0000-0000-00000000e403')),
          2, '19.2 c) · y exige dos tardanzas nuevas');

-- ── Escalón 3 · con UNA suspensión vigente ──────────────────────────────────
-- Es el escalón que no existía: aquí el sistema saltaba a la imputación.
select pg_temp.entregar('suspension', 1, '2026-07-15');
select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-00000000e403')),
          'suspension', '19.2 d) · con UNA suspensión vigente, toca la SEGUNDA — no la imputación');
select is((select minimo from fn_tardanza_escalon('00000000-0000-0000-0000-00000000e403')),
          1, '19.2 d) · y basta una tardanza nueva');
select is((select suspension_previa_dias from fn_tardanza_escalon('00000000-0000-0000-0000-00000000e403')),
          1, '19.2 d) · el escalón dice cuánto duró la primera, para que la segunda sea mayor');

-- ── Escalón 4 · con DOS suspensiones vigentes ───────────────────────────────
select pg_temp.entregar('suspension', 2, '2026-07-28');
select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-00000000e403')),
          'imputacion',
          '19.2 e) · con DOS suspensiones vigentes, ahí sí toca la imputación (art. 25-h: «suspensiones», en plural)');

-- ── Y los doce meses siguen mandando ────────────────────────────────────────
-- Una suspensión entregada hace más de un año no cuenta para el plural del
-- art. 25-h: el artículo 56 le pone fecha de caducidad al antecedente.
update expediente_disciplinario
   set entregado_at = now() - interval '13 months'
 where persona_id = '00000000-0000-0000-0000-00000000e403';
select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-00000000e403')),
          'amonestacion',
          'ART. 56 · con todo el historial fuera de los doce meses, se vuelve a empezar por abajo');

select * from finish();
rollback;
