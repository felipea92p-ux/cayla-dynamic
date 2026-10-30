-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 309_el_motor_de_faltas_desempata_como_el_de_tardanzas.test.sql — 0390
-- ============================================================================
-- `fn_expediente_generar_falta` busca «el documento anterior» así:
--
--     order by entregado_at desc limit 1
--
-- Sin desempate. Y acá el empate NO necesita una transacción para ocurrir: la
-- pantalla marca una entrega con fecha pasada usando `instanteEntrega`, que fija
-- el MEDIODÍA DE LIMA de ese día (`apps/web/lib/admin/instante-entrega.ts`). Dos
-- documentos que se marcan entregados el mismo día pasado quedan con el mismo
-- `entregado_at` al microsegundo, en transacciones distintas. Es el caso normal
-- cuando Desarrollo Organizacional se pone al día con papeles atrasados.
--
-- De esa fila salen TRES cosas: el escalón anterior (`nivel`), el corte de non
-- bis in idem (`periodo_hasta`) y la referencia al documento previo (`id`).
-- Elegir la equivocada mueve a alguien de peldaño en la escalera disciplinaria.
--
-- El criterio no se inventa acá: es el que `fn_tardanza_escalon_al` (0311) ya
-- usa para responder esta misma pregunta en el motor de TARDANZAS —
-- `entregado_at desc, periodo_hasta desc, id desc`. Las dos mitades del mismo
-- sistema con reglas distintas es exactamente lo que la 0237 vino a cerrar.
--
-- Las dos personas de abajo tienen el MISMO expediente. Lo único que cambia es
-- el orden en que se guardaron sus dos documentos.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000308000', 'ZZ308', 'Sede de laboratorio 308', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000308aa0', 'Jefa', 'Lab308',
        '00000000-0000-0000-0000-000000308000', 'admin', 'h',
        '00000000-0000-0000-0000-000000308aff', '2025-01-02');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000308001', 'Hilda', 'PrimeroLaLeve308',
        '00000000-0000-0000-0000-000000308000', 'h', '2026-01-05'),
       ('00000000-0000-0000-0000-000000308002', 'Irma', 'PrimeroLaGrave308',
        '00000000-0000-0000-0000-000000308000', 'h', '2026-01-05');

-- Dos tramos de horario por persona. En ese calendario caen CUATRO faltas, y
-- cada una está ahí por algo:
--
--   · hoy-8 … hoy-7 — la falta «vieja» (hoy-8) y un día justificado (hoy-7).
--     La falta vieja cae ENTRE el corte de la amonestación (hoy-20) y el de la
--     suspensión (hoy-5), así que solo la cuenta quien use el corte equivocado.
--     Sin ella la aserción 5 no discriminaba: el horario arrancaba en hoy-3 y
--     el borrador salía en hoy-3 con cualquiera de los dos cortes (medido el
--     2026-10-11: con el `order by` de la 0237 la 5 seguía pasando).
--   · desde hoy-3 — las tres faltas «nuevas», las únicas posteriores al corte
--     de la suspensión. Entre hoy-6 y hoy-4 no hay horario: no son laborables.
--
-- El día justificado NO es adorno. `consecutivas` (art. 25-h, umbral 4) se
-- cuenta sobre los días en que le TOCABA trabajar, no sobre el calendario: los
-- días sin horario no cortan la racha. Sin la justificación de hoy-7 las cuatro
-- faltas (hoy-8, hoy-3, hoy-2, hoy-1) serían «consecutivas», el generador
-- alcanzaría el umbral y se iría por la rama de imputación directa, que arranca
-- en la falta MÁS antigua sin mirar ningún corte. Medido: la aserción 5 fallaba
-- con el código correcto (hoy-8 en vez de hoy-3), y la 2 y la 3 daban
-- «imputación» por cualquiera de los dos caminos, o sea que dejaban de probar
-- la escalera. Con el día justificado quedan 3 consecutivas, 4 en 30 días y 4
-- en 180: ningún umbral (4, 6 y 16), y la última aserción lo comprueba.
--
-- Todo eso solo vale si ninguno de esos días es feriado: `fn_falta_contadores`
-- no cuenta falta en un feriado sin turno (y hace bien, un falso positivo
-- cuesta más que dejar pasar una falta), y un feriado en hoy-7 sacaría el día
-- justificado del cómputo y juntaría la racha igual. La tabla `feriados` es el
-- calendario REAL, sembrado hasta 2032, así que esta prueba cambiaba de
-- resultado según la fecha en que se corriera: cuando `hoy - 3` caía en un
-- feriado el borrador arrancaba al día siguiente y la aserción 5 fallaba. Le
-- tocaba a cada feriado el día `feriado + 3` —el 2026-10-11 fue por el jueves
-- 8, Combate de Angamos—, sea cual sea el día de la semana en que cayera.
--
-- Por eso se vacía la ventana, dentro de la transacción (el `rollback` del
-- final la devuelve). Es el molde de las pruebas 10, 115, 125 o 130, solo que
-- con la ventana relativa a `fn_hoy_lima()` y no a un mes fijo, porque acá lo
-- que se mueve es el «hoy». Cubre hoy-8 … hoy-1 de corrido: los tres días del
-- medio no son laborables y vaciarlos no cambia nada, pero así es una línea y
-- no tres.
delete from feriados where fecha between fn_hoy_lima() - 8 and fn_hoy_lima() - 1;

insert into horarios_asignados
  (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables,
   horas_semana_objetivo, horario_por_dia)
select p, t.desde, t.hasta, '09:00', '18:00', 60, 60,
       array[0,1,2,3,4,5,6], 45,
       '{"0":{"e":"09:00","s":"18:00","r":60},"1":{"e":"09:00","s":"18:00","r":60},
         "2":{"e":"09:00","s":"18:00","r":60},"3":{"e":"09:00","s":"18:00","r":60},
         "4":{"e":"09:00","s":"18:00","r":60},"5":{"e":"09:00","s":"18:00","r":60},
         "6":{"e":"09:00","s":"18:00","r":60}}'::jsonb
from unnest(array['00000000-0000-0000-0000-000000308001'::uuid,
                  '00000000-0000-0000-0000-000000308002'::uuid]) p
cross join (values (fn_hoy_lima() - 8, fn_hoy_lima() - 7),
                   (fn_hoy_lima() - 3, null::date)) t(desde, hasta);

do $sesion$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000308aff', true);
end $sesion$;

-- El día que corta la racha: laborable y justificado, o sea que ni es falta ni
-- deja pasar la cuenta de consecutivas. La vista `justificaciones_asistencia`
-- acepta el insert directo (0101) y la fila acaba en `ausencias`, igual que en
-- la prueba 60. Va DESPUÉS de fijar la sesión: el trigger exige que quien
-- registra una ausencia ajena sea administrador o líder.
insert into justificaciones_asistencia (persona_id, fecha, motivo, creado_por)
select p, fn_hoy_lima() - 7, 'permiso_concedido', '00000000-0000-0000-0000-000000308aa0'
from unnest(array['00000000-0000-0000-0000-000000308001'::uuid,
                  '00000000-0000-0000-0000-000000308002'::uuid]) p;

-- Los cuatro documentos se entregan EL MISMO DÍA PASADO, al mediodía de Lima —
-- que es literalmente lo que manda la pantalla. Las dos filas de cada insert
-- comparten la expresión, así que su `entregado_at` es idéntico al microsegundo,
-- igual que en producción.
--
-- Hilda: primero la amonestación, después la suspensión.
insert into expediente_disciplinario
  (id, correlativo, persona_id, tipo_causal, nivel, estado,
   periodo_desde, periodo_hasta, hechos, firmante_id, firmado_at,
   medio_entrega, entregado_at, creado_por,
   suspension_dias, suspension_desde, suspension_hasta)
values
  ('00000000-0000-0000-0000-0000003080a1', 'AM-2026-3081',
   '00000000-0000-0000-0000-000000308001', 'falta', 'amonestacion', 'entregado',
   fn_hoy_lima() - 40, fn_hoy_lima() - 20,
   '[{"fecha":"2026-07-01"}]'::jsonb,
   '00000000-0000-0000-0000-000000308aa0', (fn_hoy_lima() - 12)::timestamptz + interval '12 hours',
   'fisico', (fn_hoy_lima() - 10)::timestamptz + interval '12 hours',
   '00000000-0000-0000-0000-000000308aa0', null, null, null),
  ('00000000-0000-0000-0000-0000003080a2', 'SU-2026-3082',
   '00000000-0000-0000-0000-000000308001', 'falta', 'suspension', 'entregado',
   fn_hoy_lima() - 19, fn_hoy_lima() - 5,
   '[{"fecha":"2026-08-15"}]'::jsonb,
   '00000000-0000-0000-0000-000000308aa0', (fn_hoy_lima() - 12)::timestamptz + interval '12 hours',
   'fisico', (fn_hoy_lima() - 10)::timestamptz + interval '12 hours',
   '00000000-0000-0000-0000-000000308aa0', 1, fn_hoy_lima() - 18, fn_hoy_lima() - 18);

-- Irma: al revés — primero la suspensión, después la amonestación.
insert into expediente_disciplinario
  (id, correlativo, persona_id, tipo_causal, nivel, estado,
   periodo_desde, periodo_hasta, hechos, firmante_id, firmado_at,
   medio_entrega, entregado_at, creado_por,
   suspension_dias, suspension_desde, suspension_hasta)
values
  ('00000000-0000-0000-0000-0000003080b2', 'SU-2026-3084',
   '00000000-0000-0000-0000-000000308002', 'falta', 'suspension', 'entregado',
   fn_hoy_lima() - 19, fn_hoy_lima() - 5,
   '[{"fecha":"2026-08-15"}]'::jsonb,
   '00000000-0000-0000-0000-000000308aa0', (fn_hoy_lima() - 12)::timestamptz + interval '12 hours',
   'fisico', (fn_hoy_lima() - 10)::timestamptz + interval '12 hours',
   '00000000-0000-0000-0000-000000308aa0', 1, fn_hoy_lima() - 18, fn_hoy_lima() - 18),
  ('00000000-0000-0000-0000-0000003080b1', 'AM-2026-3083',
   '00000000-0000-0000-0000-000000308002', 'falta', 'amonestacion', 'entregado',
   fn_hoy_lima() - 40, fn_hoy_lima() - 20,
   '[{"fecha":"2026-07-01"}]'::jsonb,
   '00000000-0000-0000-0000-000000308aa0', (fn_hoy_lima() - 12)::timestamptz + interval '12 hours',
   'fisico', (fn_hoy_lima() - 10)::timestamptz + interval '12 hours',
   '00000000-0000-0000-0000-000000308aa0', null, null, null);

-- ── 0 · El empate es real, no un artificio de la prueba ───────────────────
select is(
  (select count(distinct entregado_at)::int from expediente_disciplinario
    where persona_id = '00000000-0000-0000-0000-000000308001'),
  1,
  'DE PARTIDA · los dos documentos comparten `entregado_at` al microsegundo, como los entrega la pantalla con fecha pasada');

-- ── 1 y 2 · La escalera no la decide el orden físico de la tabla ───────────
-- El anterior que manda es la SUSPENSIÓN (cubre hasta más tarde), así que la
-- reincidencia sube a imputación. Si ganara la amonestación, saldría suspensión:
-- un peldaño menos, sobre la misma persona y el mismo expediente.
--
-- El generador se llama UNA vez por persona y se guarda el id. Llamarlo dentro
-- de un `where` lo ejecutaría una vez por fila escaneada, y la segunda ya choca
-- con su propio candado de «ya hay un borrador pendiente».
create temp table borradores_308 (persona_id uuid, doc_id uuid) on commit drop;
do $generar$ begin
  insert into borradores_308 values
    ('00000000-0000-0000-0000-000000308001',
     fn_expediente_generar_falta('00000000-0000-0000-0000-000000308001')),
    ('00000000-0000-0000-0000-000000308002',
     fn_expediente_generar_falta('00000000-0000-0000-0000-000000308002'));
end $generar$;

select is(
  (select e.nivel from borradores_308 b join expediente_disciplinario e on e.id = b.doc_id
    where b.persona_id = '00000000-0000-0000-0000-000000308001'),
  'imputacion',
  'manda el documento que cubre hasta más tarde: la reincidencia sobre la suspensión sube a imputación');

select is(
  (select e.nivel from borradores_308 b join expediente_disciplinario e on e.id = b.doc_id
    where b.persona_id = '00000000-0000-0000-0000-000000308002'),
  'imputacion',
  'y la persona con el mismo expediente guardado al revés recibe el mismo escalón, no uno distinto');

-- ── 3 · Y el documento previo que se cita es el mismo ──────────────────────
select is(
  (select e.doc_previo_id from borradores_308 b join expediente_disciplinario e on e.id = b.doc_id
    where b.persona_id = '00000000-0000-0000-0000-000000308001'),
  '00000000-0000-0000-0000-0000003080a2'::uuid,
  'el borrador cita como antecedente la suspensión, no la amonestación');

-- ── 4 · El corte de non bis in idem sale del mismo documento ───────────────
-- La suspensión cubre hasta `hoy - 5`; la amonestación, hasta `hoy - 20`. Si
-- ganara la amonestación, el corte retrocedería quince días y el borrador
-- volvería a reprochar hechos ya cubiertos — lo que el art. 52.5 prohíbe.
--
-- Y para que esta aserción pueda ver esa diferencia, el fixture tiene una falta
-- en `hoy - 8`: cae dentro de lo que la suspensión ya cubre pero fuera de lo que
-- cubre la amonestación. Con el corte correcto el borrador arranca en `hoy - 3`;
-- con el equivocado, en `hoy - 8`.
select is(
  (select e.periodo_desde from borradores_308 b join expediente_disciplinario e on e.id = b.doc_id
    where b.persona_id = '00000000-0000-0000-0000-000000308001'),
  fn_hoy_lima() - 3,
  'los hechos imputados arrancan después del corte de la suspensión, no del de la amonestación');

-- ── 5 · El fixture sigue yendo por la escalera ────────────────────────────
-- Todo lo de arriba solo prueba lo que dice si el generador NO se fue por la
-- rama de imputación directa del art. 25-h (4 consecutivas, 6 en 30 días o 16
-- en 180): esa rama también contesta «imputación» y toma como inicio la falta
-- más antigua, sin mirar ningún corte. Es lo que pasaría si alguien le quita a
-- las dos personas el día justificado de hoy-7, o si un feriado cae donde no
-- debe. Se comprueba en vez de suponerse — y se comprueba al final porque es lo
-- que explica el resto cuando algo falla.
select is(
  (select count(*)::int
     from unnest(array['00000000-0000-0000-0000-000000308001'::uuid,
                       '00000000-0000-0000-0000-000000308002'::uuid]) p
    cross join lateral fn_falta_contadores(p, fn_hoy_lima() - 180) c
    where c.consecutivas >= 4 or c.en_30 >= 6 or c.en_180 >= 16),
  0,
  'el fixture no alcanza ningún umbral del art. 25-h: el generador va por la escalera, no por la imputación directa');

select * from finish();
rollback;
