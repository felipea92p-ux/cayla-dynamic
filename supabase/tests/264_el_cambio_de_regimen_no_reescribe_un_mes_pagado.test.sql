-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 264_el_cambio_de_regimen_no_reescribe_un_mes_pagado.test.sql
-- ============================================================================
-- Hermana de la 202, que probó que un cambio de régimen no mueve el pasado. Lo
-- probó con una persona QUE TENÍA HISTORIAL, y ahí el mecanismo funciona. Esta
-- prueba cubre el caso que aquella no tocó: **quien no tiene ninguna fila en
-- `asignaciones_regimen_pension`**.
--
-- ── EL AGUJERO, MEDIDO ──────────────────────────────────────────────────────
--
-- `fn_planilla_calcular` resuelve el régimen con la cascada de la 0261: el tramo
-- vigente al cierre del periodo, Y SI NO HAY TRAMO, la columna
-- `personas.regimen_pension`. Los dos caminos son necesarios —el respaldo es lo
-- que hizo que la 0261 se pudiera pegar sin mover un céntimo— pero juntos dejan
-- una grieta:
--
--   A quien NO tiene tramo, abrirle uno nuevo desde hoy NO le protege el pasado.
--   El mes ya pagado no encuentra fila que lo cubra, cae a la columna, y la
--   columna ya cambió. Su boleta de un mes cerrado pasa a decir otra cifra.
--
-- Se midió el 2026-08-31 escribiendo la 0331, contra el Postgres local y con un
-- periodo pagado y uno abierto. La primera versión de esa migración hacía los
-- tres pasos que hace `fn_cambiar_regimen_pension` —cerrar el tramo, abrir el
-- nuevo, poner la columna al día— y aun así le cambió marzo a la persona sin
-- historial: de 13.06 % a 11.37 %.
--
-- La 0331 lo cierra escribiendo TAMBIÉN el tramo del pasado con el régimen
-- anterior. Esta prueba fija esa forma, que es la única que protege a los dos
-- tipos de persona a la vez.
--
-- ── Y LA PUERTA DE LA PANTALLA, QUE TENÍA EL MISMO AGUJERO ──────────────────
--
-- `fn_cambiar_regimen_pension` lo tenía igual: cambiarle el régimen desde la
-- pantalla a alguien sin tramo le reescribía los meses pagados por esta misma
-- vía. Su freno de la 0203 comprueba que la FECHA no caiga en un periodo
-- pagado, y en este caso la fecha está bien — lo que alcanzaba al pasado era el
-- `update` de la columna, que no tiene fecha ninguna.
--
-- Lo cerró la **0332**, agregándole a la función la mitad que le faltaba: sin
-- tramo abierto que cerrar, escribe el del PASADO con el régimen anterior. El
-- bloque 2 de abajo ya no describe el defecto — lo impide.
--
-- Queda un borde, y esta prueba NO lo cubre porque sigue vivo: quien no tiene
-- tramo Y tiene la columna en `null`. «Sin régimen» no se puede escribir como
-- tramo (`regimen` es NOT NULL), así que cargarle uno por primera vez todavía
-- le mueve un mes pagado, de la tasa genérica a la del régimen nuevo. Cerrarlo
-- pide un cambio de esquema; está razonado en la cabecera de la 0332.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000005a0', 'ZZ331', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000005a1', 'CasAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000005a0', 'admin', 'x',
        '00000000-0000-0000-0000-0000000ffd01', '2024-01-01');
set session_replication_role = origin;

-- Dos personas iguales salvo en una cosa: si tienen historial de régimen.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, regimen_pension)
values ('00000000-0000-0000-0000-0000000005a2', 'CasConTramo', 'Lab',
        '00000000-0000-0000-0000-0000000005a0', 'x', '2024-01-01', 'taller_produccion', 'integra'),
       ('00000000-0000-0000-0000-0000000005a3', 'CasSinTramo', 'Lab',
        '00000000-0000-0000-0000-0000000005a0', 'x', '2024-01-01', 'taller_produccion', 'profuturo');

insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde, nota)
values ('00000000-0000-0000-0000-0000000005a2', 'integra', '2024-01-01', 'alta de laboratorio');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1500, '2024-01-01' from personas where apellidos = 'Lab' and nombres like 'Cas%Tramo';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39
from personas where apellidos = 'Lab' and nombres like 'Cas%Tramo';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ffd01', true);

-- Marzo se paga; abril queda abierto.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-0000000005a0', v.t::tipo_marca, v.ts
from personas p, (values
  ('entrada'::text,      '2026-03-03T09:00:00-05:00'::timestamptz),
  ('salida_final', '2026-03-03T15:30:00-05:00'),
  ('entrada',      '2026-04-07T09:00:00-05:00'),
  ('salida_final', '2026-04-07T15:30:00-05:00')
) as v(t, ts)
where p.apellidos = 'Lab' and p.nombres like 'Cas%Tramo';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at)
values ('eeeeeeee-0000-0000-0000-0000000005a0', '2026-03-01', '2026-03-31', 'pagado', now()),
       ('eeeeeeee-0000-0000-0000-0000000005a1', '2026-04-01', '2026-04-30', 'abierto', null);


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · La forma que deja la 0331: tramo del pasado + tramo nuevo
-- ════════════════════════════════════════════════════════════════════════════
-- Se reproduce a mano lo que hace la migración, para fijar la FORMA y no el
-- archivo: cualquier otra migración que mueva regímenes tiene que dejar esto.

update asignaciones_regimen_pension
   set vigente_hasta = date '2026-03-31'
 where persona_id = '00000000-0000-0000-0000-0000000005a2' and vigente_hasta is null;

-- ⇩ EL PASO QUE FALTABA ⇩ para quien no tenía ninguna fila.
insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde, vigente_hasta, nota)
values ('00000000-0000-0000-0000-0000000005a3', 'profuturo', '2024-01-01', '2026-03-31',
        'tramo del pasado, como lo escribe la 0331');

insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde, nota)
values ('00000000-0000-0000-0000-0000000005a2', 'integra_mixta',   '2026-04-01', 'pasa a mixta'),
       ('00000000-0000-0000-0000-0000000005a3', 'profuturo_mixta', '2026-04-01', 'pasa a mixta');

update personas set regimen_pension = 'integra_mixta'   where id = '00000000-0000-0000-0000-0000000005a2';
update personas set regimen_pension = 'profuturo_mixta' where id = '00000000-0000-0000-0000-0000000005a3';


-- ── El mes PAGADO conserva su tasa, con historial y sin él ───────────────────
select is(
  (select round((f->>'tasa_afp')::numeric, 5)
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000005a2'),
  0.12920,
  'quien TENÍA historial conserva su 12.92 % en el mes ya pagado'
);

-- ── AQUÍ ESTABA EL DEFECTO ──────────────────────────────────────────────────
-- Sin el tramo del pasado, esta da 0.11370: marzo, ya depositado, cambiaría.
select is(
  (select round((f->>'tasa_afp')::numeric, 5)
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000005a3'),
  0.13060,
  'y quien NO tenía historial también — es el caso que se coló'
);

-- ── Y el mes ABIERTO sí toma la tasa nueva, que es el objetivo ──────────────
select is(
  (select round((f->>'tasa_afp')::numeric, 5)
     from jsonb_array_elements(fn_planilla_calcular('2026-04-01','2026-04-30')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000005a3'),
  0.11370,
  'el mes abierto sí baja a 11.37 %'
);

-- ── Ni hueco ni solape entre los dos tramos ─────────────────────────────────
-- Un hueco de un día caería a la columna sin avisar, que es la misma grieta un
-- día más chica.
select is(
  (select count(*) from asignaciones_regimen_pension a
     join asignaciones_regimen_pension b
       on b.persona_id = a.persona_id and b.vigente_desde = a.vigente_hasta + 1
    where a.persona_id in ('00000000-0000-0000-0000-0000000005a2',
                           '00000000-0000-0000-0000-0000000005a3')
      and a.vigente_hasta is not null),
  2::bigint,
  'los dos tramos se tocan exactamente: sin hueco y sin solape'
);

-- ── La columna y el tramo abierto dicen lo mismo (regla de la 0277) ─────────
select is(
  (select count(*) from personas p
     join asignaciones_regimen_pension h
       on h.persona_id = p.id and h.vigente_hasta is null
    where p.apellidos = 'Lab' and p.nombres like 'Cas%Tramo'
      and p.regimen_pension is distinct from h.regimen),
  0::bigint,
  'la ficha y el tramo vigente no se separan'
);


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · La puerta de la pantalla: fn_cambiar_regimen_pension (cerrado por la 0332)
-- ════════════════════════════════════════════════════════════════════════════
-- Una tercera persona sin historial a la que se le cambia el régimen por la
-- puerta de la pantalla, con una fecha que el freno de la 0203 acepta porque
-- cae en el periodo ABIERTO. Antes de la 0332 esto le movía marzo de 12.92 % a
-- 11.37 %; medido el 2026-08-31 contra el Postgres local.

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, regimen_pension)
values ('00000000-0000-0000-0000-0000000005a4', 'CasPuerta', 'Lab',
        '00000000-0000-0000-0000-0000000005a0', 'x', '2024-01-01', 'taller_produccion', 'integra');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000005a4', 'colibri', 1500, '2024-01-01');
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values ('00000000-0000-0000-0000-0000000005a4', '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39);
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000005a4', '00000000-0000-0000-0000-0000000005a0', 'entrada',      '2026-03-03T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000005a4', '00000000-0000-0000-0000-0000000005a0', 'salida_final', '2026-03-03T15:30:00-05:00');

select is(
  (select round((f->>'tasa_afp')::numeric, 5)
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000005a4'),
  0.12920,
  'antes del cambio, su mes pagado va al 12.92 %'
);

select lives_ok(
  $$select fn_cambiar_regimen_pension(
      '00000000-0000-0000-0000-0000000005a4', 'integra_mixta', '2026-04-01',
      'la pantalla lo acepta: la fecha cae en el periodo abierto')$$,
  'la función acepta el cambio — su freno mira la fecha, y la fecha está bien'
);

-- ── Y AQUÍ ESTABA EL DEFECTO ────────────────────────────────────────────────
-- Esta es la línea que la versión anterior de esta prueba dejó sin escribir, a
-- propósito: mientras el defecto vivía, afirmar 12.92 % habría hecho fallar una
-- prueba en verde. La 0332 lo arregló, así que ahora sí se afirma — y es la
-- línea que impide que el arreglo se pierda en la próxima reescritura de la
-- función. Sin el tramo del pasado, marzo cae a 0.11370.
select is(
  (select round((f->>'tasa_afp')::numeric, 5)
     from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000005a4'),
  0.12920,
  'y su mes pagado SIGUE en 12.92 % después del cambio — la 0332'
);

select * from finish();
rollback;
