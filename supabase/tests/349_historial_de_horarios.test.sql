-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 349_historial_de_horarios.test.sql — 0439, 0440, 0441, 0442
-- ============================================================================
-- § 1 · 0439: fn_set_horario_semanal (camino normal) rechaza una fecha
--   pasada y sigue aceptando hoy.
-- § 2 · 0440/0441: una tardanza se calcula igual que siempre, y la jornada
--   queda con la foto de qué horario se usó (horario_aplicado).
-- § 3 · 0442, la vista previa: para el MISMO horario candidato y el mismo
--   rango, da los mismos números que después confirma la corrección real —
--   la garantía central de esta migración.
-- § 4 · 0442, confirmar: la corrección retroactiva cambia la jornada, deja
--   rastro en correcciones_auditoria, y la jornada queda con la foto nueva.
-- § 5 · 0442 bloquea si el rango toca un expediente disciplinario ya
--   firmado/entregado — mismo criterio que 0437/0438 en las otras puertas.
-- § 6 · 0442 bloquea si el rango toca un periodo ya pagado.
-- § 7 · Ni el preview ni la corrección aceptan una fecha de hoy o futura —
--   para eso está el camino normal (0439), no este.
--
-- Todas las fechas de negocio (tardanza, horario, periodo) se calculan
-- relativas a fn_hoy_lima() en vez de fechas fijas: fn_corregir_horario_
-- retroactivo y fn_horario_retroactivo_preview recorren CADA día entre
-- vigente_desde y ayer (generate_series), así que una fecha fija de hace
-- años (como usa la prueba 346 para sus periodos) haría que ese rango
-- recorriera miles de días. Relativas a hoy, el rango se queda chico.
-- ============================================================================
begin;
select plan(17);

-- ── El laboratorio ──────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre)
values ('aaaaaaaa-0442-0000-0000-000000000001','T42','Sede de la prueba 349');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('bbbbbbbb-0442-0000-0000-000000000001','00000000-0000-0000-0000-000000000000',
        'authenticated','authenticated','prueba349@cayla.local','x', now(), now(), now());

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id) values
 ('cccccccc-0442-0000-0000-00000000000a','Ada','Admin',
  'aaaaaaaa-0442-0000-0000-000000000001','x','admin','bbbbbbbb-0442-0000-0000-000000000001'),
 ('cccccccc-0442-0000-0000-00000000000b','Rosa','DePrueba',
  'aaaaaaaa-0442-0000-0000-000000000001','x','integrante', null);

set local request.jwt.claims = '{"sub":"bbbbbbbb-0442-0000-0000-000000000001","role":"authenticated"}';

-- Fechas relativas a HOY (nunca fijas — ver cabecera) y los dos horarios
-- candidatos, calculados una sola vez para que todas las secciones usen
-- exactamente los mismos valores.
create temporary table _datos as
select
  d.prueba,
  extract(dow from d.prueba)::int::text as dow,
  (fn_hoy_lima() - 60) as horario_desde,
  (fn_hoy_lima() - 15) as retro_desde,
  (fn_hoy_lima() - 20) as pagado_intento_desde,
  (fn_hoy_lima() - 40) as periodo_ini,
  (fn_hoy_lima() - 12) as periodo_fin,
  jsonb_build_object(extract(dow from d.prueba)::int::text, jsonb_build_object('e','08:00','s','17:00','r',60)) as horario_viejo,
  jsonb_build_object(extract(dow from d.prueba)::int::text, jsonb_build_object('e','08:30','s','17:00','r',60)) as horario_nuevo
from (
  -- Diez días atrás, movido un día si cae domingo — así siempre hay un
  -- día de trabajo cerca de "hoy - 10" sin depender de qué día es hoy.
  select case when extract(dow from fn_hoy_lima() - 10) = 0 then fn_hoy_lima() - 11 else fn_hoy_lima() - 10 end as prueba
) d;

-- El horario histórico, sembrado directo (no por la app: es de antes de esta
-- prueba y ya está CERRADO, así que no compite con lo que haga fn_set_
-- horario_semanal más abajo).
insert into horarios_asignados (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
                                almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia)
select 'cccccccc-0442-0000-0000-00000000000b', horario_desde, fn_hoy_lima() - 1,
       '08:00','17:00', 60, 60, array[1,2,3,4,5,6], horario_viejo
from _datos;

-- ── § 1 · 0439: el camino normal ya no acepta una fecha pasada ─────────────
select throws_ok(
  format('select fn_set_horario_semanal(''cccccccc-0442-0000-0000-00000000000b'', %L, %L::jsonb)',
         fn_hoy_lima() - 1, (select horario_nuevo from _datos)),
  null,
  '0439: fn_set_horario_semanal rechaza una fecha ya pasada');

select lives_ok(
  format('select fn_set_horario_semanal(''cccccccc-0442-0000-0000-00000000000b'', %L, %L::jsonb)',
         fn_hoy_lima(), (select horario_nuevo from _datos)),
  '0439: fn_set_horario_semanal sigue aceptando HOY como de costumbre');

-- ── § 2 · 0440/0441: la tardanza se calcula igual, y queda la foto ─────────
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
select gen_random_uuid(), 'cccccccc-0442-0000-0000-00000000000b', 'aaaaaaaa-0442-0000-0000-000000000001',
       'entrada', (prueba::timestamp + time '08:20') at time zone 'America/Lima', 'terminal', 'normal'
from _datos;
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
select gen_random_uuid(), 'cccccccc-0442-0000-0000-00000000000b', 'aaaaaaaa-0442-0000-0000-000000000001',
       'salida_final', (prueba::timestamp + time '17:00') at time zone 'America/Lima', 'terminal', 'normal'
from _datos;

select is(
  (select j.minutos_tarde from jornadas j, _datos d where j.persona_id = 'cccccccc-0442-0000-0000-00000000000b' and j.fecha = d.prueba),
  20,
  '0440: 20 min de tardanza bajo el horario viejo (entrada 08:00, marcó 08:20)');

select is(
  (select j.horario_aplicado->>'fuente' from jornadas j, _datos d where j.persona_id = 'cccccccc-0442-0000-0000-00000000000b' and j.fecha = d.prueba),
  'horarios_asignados',
  '0441: horario_aplicado.fuente dice de dónde salió el horario de ese día');

select is(
  (select (j.horario_aplicado->>'entrada')::time from jornadas j, _datos d where j.persona_id = 'cccccccc-0442-0000-0000-00000000000b' and j.fecha = d.prueba),
  '08:00'::time,
  '0441: horario_aplicado.entrada guarda la hora con la que de verdad se midió');

-- ── § 3 · 0442, la vista previa: mismo número que va a confirmar § 4 ──────
select is(
  (select p.minutos_tarde_actual
     from _datos d, fn_horario_retroactivo_preview('cccccccc-0442-0000-0000-00000000000b', d.horario_nuevo, d.retro_desde) p
    where p.fecha = d.prueba),
  20,
  '0442: el preview dice que HOY tiene 20 min de tardanza — coincide con § 2');

select is(
  (select p.minutos_tarde_nuevo
     from _datos d, fn_horario_retroactivo_preview('cccccccc-0442-0000-0000-00000000000b', d.horario_nuevo, d.retro_desde) p
    where p.fecha = d.prueba),
  0,
  '0442: el preview dice que con el horario candidato (entrada 08:30) ya no llegaría tarde');

select is(
  (select p.tiene_expediente_formal
     from _datos d, fn_horario_retroactivo_preview('cccccccc-0442-0000-0000-00000000000b', d.horario_nuevo, d.retro_desde) p
    where p.fecha = d.prueba),
  false,
  '0442: el preview dice que todavía no hay ningún expediente formal sobre ese día');

-- ── § 4 · 0442, confirmar: la corrección real da EXACTAMENTE lo que el preview prometió ──
select is(
  (select count(*)::int from correcciones_auditoria where persona_id = 'cccccccc-0442-0000-0000-00000000000b'),
  0,
  '0442: todavía no hay ninguna corrección auditada para esta persona (control, antes de confirmar)');

select lives_ok(
  format('select fn_corregir_horario_retroactivo(''cccccccc-0442-0000-0000-00000000000b'', %L::jsonb, %L, ''Prueba 349 — el cambio real fue hace días.'')',
         (select horario_nuevo from _datos), (select retro_desde from _datos)),
  '0442: la corrección retroactiva legítima se aplica sin problema');

select is(
  (select count(*)::int from correcciones_auditoria where persona_id = 'cccccccc-0442-0000-0000-00000000000b' and campo_modificado = 'horarios_asignados.horario_por_dia'),
  1,
  '0442: la corrección deja exactamente una fila en correcciones_auditoria');

select is(
  (select j.minutos_tarde from jornadas j, _datos d where j.persona_id = 'cccccccc-0442-0000-0000-00000000000b' and j.fecha = d.prueba),
  0,
  '0442: tras confirmar, minutos_tarde pasa a 0 — exactamente lo que el preview de § 3 prometió');

select is(
  (select (j.horario_aplicado->>'entrada')::time from jornadas j, _datos d where j.persona_id = 'cccccccc-0442-0000-0000-00000000000b' and j.fecha = d.prueba),
  '08:30'::time,
  '0441: horario_aplicado también se actualiza con la corrección retroactiva');

-- ── § 5 · Bloquea si el día ya tiene un expediente disciplinario formal ────
insert into expediente_disciplinario (persona_id, tipo_causal, nivel, estado, hechos, correlativo, firmante_id, firmado_at, creado_por)
select 'cccccccc-0442-0000-0000-00000000000b', 'tardanza', 'amonestacion', 'firmado',
       jsonb_build_array(jsonb_build_object('fecha', prueba, 'minutos', 0)),
       'T-0442/0001-PRUEBA', 'cccccccc-0442-0000-0000-00000000000a', now(), 'cccccccc-0442-0000-0000-00000000000a'
from _datos;

select throws_ok(
  format('select fn_corregir_horario_retroactivo(''cccccccc-0442-0000-0000-00000000000b'', %L::jsonb, %L, ''Segundo intento, debería bloquear.'')',
         (select horario_viejo from _datos), (select pagado_intento_desde from _datos)),
  null,
  '0442: bloquea la corrección retroactiva cuando el rango toca un expediente ya firmado');

delete from expediente_disciplinario where correlativo = 'T-0442/0001-PRUEBA';

-- ── § 6 · Bloquea si el rango toca un periodo ya pagado ────────────────────
create temporary table _periodo as
with p as (
  insert into periodos_planilla (fecha_ini, fecha_fin, estado)
  select periodo_ini, periodo_fin, 'abierto' from _datos
  returning id
)
select id from p;

insert into periodo_grupo_pago (periodo_id, grupo, estado)
select id, 'planilla', 'pagado' from _periodo;

select throws_ok(
  format('select fn_corregir_horario_retroactivo(''cccccccc-0442-0000-0000-00000000000b'', %L::jsonb, %L, ''Tercer intento, debería bloquear por pagado.'')',
         (select horario_viejo from _datos), (select pagado_intento_desde from _datos)),
  null,
  '0442: bloquea la corrección retroactiva cuando el rango toca un periodo ya pagado');

-- ── § 7 · Ni el preview ni la corrección aceptan hoy/futuro ────────────────
select throws_ok(
  format('select * from fn_horario_retroactivo_preview(''cccccccc-0442-0000-0000-00000000000b'', %L::jsonb, %L)',
         (select horario_viejo from _datos), fn_hoy_lima()),
  null,
  '0442: el preview rechaza vigente_desde = hoy — para eso está el camino normal');

select throws_ok(
  format('select fn_corregir_horario_retroactivo(''cccccccc-0442-0000-0000-00000000000b'', %L::jsonb, %L, ''No debería llegar a aplicarse.'')',
         (select horario_viejo from _datos), fn_hoy_lima()),
  null,
  '0442: la corrección retroactiva rechaza vigente_desde = hoy');

select * from finish();
rollback;
