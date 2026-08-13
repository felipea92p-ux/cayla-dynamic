-- ============================================================================
-- 155_el_semaforo_conoce_el_escalon.test.sql
-- ============================================================================
-- El defecto que cierra (0200): la pantalla de Disciplina y el generador del
-- memo respondían dos preguntas distintas creyendo responder la misma.
--
--   fn_tardanzas_resumen            listaba a quien llevaba 2+ este mes
--   fn_expediente_generar_tardanza  escalaba: 3 sin antecedente · 2 tras
--                                   amonestación · 1 tras suspensión
--
-- Con una suspensión vigente el umbral real es UNA tardanza. Medido antes de la
-- 0200 sobre este mismo escenario: el expediente ya se podía generar y el
-- semáforo decía «Nadie con tardanzas relevantes este mes». Un falso NEGATIVO
-- en la pantalla que existe para no dejar pasar nada.
--
-- LA INVARIANTE QUE DEFIENDE, y es la única que importa de verdad:
--
--   Si el generador acepta, el semáforo lo mostró.
--
-- Quien vuelva a escribir un umbral suelto en cualquiera de las dos funciones
-- rompe esa invariante y esta prueba se cae. La escala vive en
-- `fn_tardanza_escalon` y en ningún otro sitio.
--
-- POR QUÉ LAS FECHAS SE CUELGAN DEL INICIO DE MES Y NO DE `hoy - N`
--   El conteo es por mes calendario. Una prueba escrita con `fn_hoy_lima() - 2`
--   cuenta tres días distintos el día 25 y uno solo el día 1: pasaría once
--   meses al año y fallaría el primero. Las jornadas se anclan al inicio de mes
--   y el semáforo se consulta con `p_as_of`, que es justo para esto.
--   El generador no acepta `p_as_of`, así que las dos pruebas que lo llaman
--   usan una sola tardanza en el inicio de mes — que siempre es <= hoy.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000e200', 'ZZESC', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000e201', 'EscAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000e200', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000e209');
set session_replication_role = origin;

-- Seis situaciones, una persona cada una.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000e2a1', 'EscSinAntecedente', 'Laboratorio', '00000000-0000-0000-0000-00000000e200', 'test-hash', 'planilla'),
  ('00000000-0000-0000-0000-00000000e2a2', 'EscTrasAmonestacion', 'Laboratorio', '00000000-0000-0000-0000-00000000e200', 'test-hash', 'planilla'),
  ('00000000-0000-0000-0000-00000000e2a3', 'EscTrasSuspension', 'Laboratorio', '00000000-0000-0000-0000-00000000e200', 'test-hash', 'planilla'),
  ('00000000-0000-0000-0000-00000000e2a4', 'EscConImputacion', 'Laboratorio', '00000000-0000-0000-0000-00000000e200', 'test-hash', 'planilla'),
  ('00000000-0000-0000-0000-00000000e2a5', 'EscAntecedenteViejo', 'Laboratorio', '00000000-0000-0000-0000-00000000e200', 'test-hash', 'planilla'),
  ('00000000-0000-0000-0000-00000000e2a6', 'EscYaSancionado', 'Laboratorio', '00000000-0000-0000-0000-00000000e200', 'test-hash', 'planilla');

-- ── Los antecedentes ────────────────────────────────────────────────────────
-- Todos ENTREGADOS. Antes decían «firmado» con la nota «a la escala le da
-- igual», y eso dejó de ser cierto con la 0213: el artículo 56 del Reglamento
-- dice que un documento firmado y no entregado «no está vigente, no agrava, no
-- habilita el escalón siguiente». La edad del antecedente la marca ahora
-- `entregado_at`, no `firmado_at`.
insert into expediente_disciplinario
  (correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta,
   suspension_dias, suspension_desde, suspension_hasta, firmante_id, firmado_at,
   medio_entrega, entregado_at, creado_por)
values
  -- amonestación vigente (hace un mes)
  ('T-ZZ/0001', '00000000-0000-0000-0000-00000000e2a2', 'tardanza', 'amonestacion', 'entregado',
   fn_hoy_lima() - 40, fn_hoy_lima() - 35, null, null, null,
   '00000000-0000-0000-0000-00000000e201', now() - interval '1 month',
   'fisico', now() - interval '1 month',
   '00000000-0000-0000-0000-00000000e201'),
  -- suspensión vigente — el caso que motivó la 0200
  ('T-ZZ/0002', '00000000-0000-0000-0000-00000000e2a3', 'tardanza', 'suspension', 'entregado',
   fn_hoy_lima() - 40, fn_hoy_lima() - 35, 1, fn_hoy_lima() - 34, fn_hoy_lima() - 34,
   '00000000-0000-0000-0000-00000000e201', now() - interval '1 month',
   'fisico', now() - interval '1 month',
   '00000000-0000-0000-0000-00000000e201'),
  -- imputación vigente: decide Gerencia, el sistema no
  ('T-ZZ/0003', '00000000-0000-0000-0000-00000000e2a4', 'tardanza', 'imputacion', 'entregado',
   fn_hoy_lima() - 40, fn_hoy_lima() - 35, null, null, null,
   '00000000-0000-0000-0000-00000000e201', now() - interval '1 month',
   'fisico', now() - interval '1 month',
   '00000000-0000-0000-0000-00000000e201'),
  -- amonestación de hace 13 meses: caducada, no escala
  ('T-ZZ/0004', '00000000-0000-0000-0000-00000000e2a5', 'tardanza', 'amonestacion', 'entregado',
   fn_hoy_lima() - 400, fn_hoy_lima() - 395, null, null, null,
   '00000000-0000-0000-0000-00000000e201', now() - interval '13 months',
   'fisico', now() - interval '13 months',
   '00000000-0000-0000-0000-00000000e201'),
  -- suspensión vigente cuyo periodo LLEGA hasta el inicio de este mes: la
  -- tardanza de ese día ya se sancionó y no se vuelve a contar (non bis in idem)
  ('T-ZZ/0005', '00000000-0000-0000-0000-00000000e2a6', 'tardanza', 'suspension', 'entregado',
   date_trunc('month', fn_hoy_lima())::date - 5, date_trunc('month', fn_hoy_lima())::date,
   1, date_trunc('month', fn_hoy_lima())::date + 1, date_trunc('month', fn_hoy_lima())::date + 1,
   '00000000-0000-0000-0000-00000000e201', now() - interval '3 days',
   'fisico', now() - interval '3 days',
   '00000000-0000-0000-0000-00000000e201');

-- ── Las tardanzas, ancladas al inicio de mes ────────────────────────────────
insert into jornadas (persona_id, fecha, sede_id, minutos_tarde, horas_trabajadas, estado)
select p, date_trunc('month', fn_hoy_lima())::date + d, '00000000-0000-0000-0000-00000000e200',
       12, 8.0, 'cerrada'
from (values
  ('00000000-0000-0000-0000-00000000e2a1'::uuid, 0), ('00000000-0000-0000-0000-00000000e2a1', 1), ('00000000-0000-0000-0000-00000000e2a1', 2),
  ('00000000-0000-0000-0000-00000000e2a2', 0), ('00000000-0000-0000-0000-00000000e2a2', 1),
  ('00000000-0000-0000-0000-00000000e2a3', 0),
  ('00000000-0000-0000-0000-00000000e2a4', 0),
  ('00000000-0000-0000-0000-00000000e2a5', 0), ('00000000-0000-0000-0000-00000000e2a5', 1), ('00000000-0000-0000-0000-00000000e2a5', 2),
  ('00000000-0000-0000-0000-00000000e2a6', 0)
) as v(p, d);

-- Horario para quien va a recibir una suspensión.
--
-- Hace falta desde la 0235: la suspensión se fija en DÍAS LABORABLES —el 54.5
-- prohíbe ponerla sobre descansos— y sin horario no se sabe cuáles son. En
-- producción no puede faltar, porque «sin horario» es una de las exclusiones
-- que se aplican ANTES de contar tardanzas: quien no lo tiene no llega nunca a
-- una suspensión. Era la semilla la que no era realista.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-00000000e2a3', '2020-01-01', '09:00', '18:00', 60, 60,
        array[1,2,3,4,5,6], 45,
        '{"1":{"e":"09:00","s":"18:00","r":60},"2":{"e":"09:00","s":"18:00","r":60},
          "3":{"e":"09:00","s":"18:00","r":60},"4":{"e":"09:00","s":"18:00","r":60},
          "5":{"e":"09:00","s":"18:00","r":60},"6":{"e":"09:00","s":"18:00","r":60}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e209', true);

-- Atajo: el `umbral` que devuelve el semáforo para una persona en una fecha de
-- corte, o null si no aparece en la lista.
create or replace function pg_temp.umbral_de(p uuid, as_of date)
returns text language sql as $$
  select r.umbral from fn_tardanzas_resumen(as_of) r where r.persona_id = p;
$$;

-- ── 1-3 · Sin antecedente: NO cambia nada. Es casi todo el equipo ───────────
select is(pg_temp.umbral_de('00000000-0000-0000-0000-00000000e2a1', date_trunc('month', fn_hoy_lima())::date),
          null,
          'Sin antecedente y con 1 tardanza no aparece — igual que antes de la 0200');

select is(pg_temp.umbral_de('00000000-0000-0000-0000-00000000e2a1', date_trunc('month', fn_hoy_lima())::date + 1),
          'aviso',
          'Sin antecedente y con 2 aparece como aviso — igual que antes de la 0200');

select is(pg_temp.umbral_de('00000000-0000-0000-0000-00000000e2a1', date_trunc('month', fn_hoy_lima())::date + 2),
          'amonestacion',
          'Sin antecedente y con 3 corresponde amonestación — igual que antes de la 0200');

-- ── 4-5 · Tras una amonestación vigente el umbral baja a 2 ─────────────────
select is(pg_temp.umbral_de('00000000-0000-0000-0000-00000000e2a2', date_trunc('month', fn_hoy_lima())::date),
          'aviso',
          'Tras amonestación, con 1 tardanza YA se asoma al semáforo (antes hacían falta 2)');

select is(pg_temp.umbral_de('00000000-0000-0000-0000-00000000e2a2', date_trunc('month', fn_hoy_lima())::date + 1),
          'suspension',
          'Tras amonestación, con 2 corresponde suspensión — y el semáforo lo dice');

-- ── 6 · EL CASO. Tras UNA suspensión toca la SEGUNDA, no la imputación ─────
--
-- Esta prueba decía «corresponde imputación», y era el defecto escrito como si
-- fuera la regla. El artículo 19.2 del Reglamento tiene CUATRO escalones y el
-- literal d) es una segunda suspensión, de mayor duración que la primera.
--
-- No es un matiz de forma: el literal h) del artículo 25 de la LPCL exige
-- «amonestaciones escritas y SUSPENSIONES» en plural para despedir por
-- impuntualidad reiterada. Con una sola suspensión en el legajo, la imputación
-- que este semáforo proponía no tenía con qué sostenerse. Corregido en la 0232.
select is(pg_temp.umbral_de('00000000-0000-0000-0000-00000000e2a3', date_trunc('month', fn_hoy_lima())::date),
          'suspension',
          'Tras UNA suspensión, una tardanza corresponde la SEGUNDA suspensión (19.2 d)');

-- ── 7 · Con imputación vigente el sistema se aparta ────────────────────────
select is(pg_temp.umbral_de('00000000-0000-0000-0000-00000000e2a4', date_trunc('month', fn_hoy_lima())::date),
          'bloqueado',
          'Con imputación vigente el semáforo lo rotula bloqueado: decide Gerencia');

-- ── 8 · Un antecedente de más de 12 meses no escala ───────────────────────
select is(pg_temp.umbral_de('00000000-0000-0000-0000-00000000e2a5', date_trunc('month', fn_hoy_lima())::date + 2),
          'amonestacion',
          'Una amonestación de hace 13 meses caducó: vuelven a hacer falta 3');

-- ── 9 · Non bis in idem: lo ya sancionado no vuelve a contar ──────────────
select is(pg_temp.umbral_de('00000000-0000-0000-0000-00000000e2a6', date_trunc('month', fn_hoy_lima())::date),
          null,
          'Una tardanza anterior al corte del último memo no se vuelve a contar');

-- ── 10-11 · La invariante: si el generador acepta, el semáforo lo mostró ───
-- Con suspensión vigente y una sola tardanza en el inicio de mes —que siempre
-- es <= hoy— el generador debe crear una imputación, no negarse.
-- La llamada va a una tabla temporal y NO dentro del `select … where id = fn_…`:
-- ahí Postgres puede evaluar la función una vez por fila explorada, y la segunda
-- vuelta choca contra el candado de «ya hay un borrador pendiente». Costó un
-- «Bad plan: planned 11, ran 9» — que no es un descuido de conteo, es el archivo
-- abortando a media ejecución.
create temp table _generado as
  select fn_expediente_generar_tardanza('00000000-0000-0000-0000-00000000e2a3') as id;

select is(
  (select nivel from expediente_disciplinario where id = (select id from _generado)),
  'suspension',
  'El generador crea la SEGUNDA suspensión, no una imputación (19.2 d)');

-- Y la crea MÁS LARGA que la primera. El generador ponía un día a toda
-- suspensión, escrito literal, así que una segunda habría incumplido el
-- numeral 19.2 d) en el documento que lo invoca.
select ok(
  (select suspension_dias from expediente_disciplinario where id = (select id from _generado))
    > (select suspension_dias from expediente_disciplinario
        where persona_id = '00000000-0000-0000-0000-00000000e2a3'
          and nivel = 'suspension' and estado = 'entregado'),
  'La segunda suspensión dura más que la primera (19.2 d), dentro del tope de tres del 54.5');

select throws_ok(
  $$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-00000000e2a4') $$,
  'Ya hay una imputación de cargos vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).',
  'Con imputación vigente el generador se niega, con el mismo mensaje de siempre');

select * from finish();
rollback;
