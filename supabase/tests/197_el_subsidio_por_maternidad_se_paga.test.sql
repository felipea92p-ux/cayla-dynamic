-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 197_el_subsidio_por_maternidad_se_paga.test.sql
-- ============================================================================
-- Una integrante de licencia por maternidad no marca —no puede—, y hasta la
-- 0256 `pago_base` salía de las horas marcadas: su boleta decía **S/0.00** y se
-- leía exactamente igual que la de alguien que no vino. La 0254 ya lo había
-- dejado anotado en un comentario: «la maternidad sigue sin modelarse».
--
-- Esto fija lo que arregló la 0256, y sobre todo las cuatro decisiones que más
-- fácil se rompen sin que nadie lo note:
--
--   · que cuente días CALENDARIO y no laborables — un domingo dentro de la
--     licencia se paga, al revés que en el descanso médico, porque el promedio
--     diario de EsSalud ya viene dividido entre días calendario;
--   · que el subsidio NO infle la base de EsSalud, porque no es remuneración;
--   · que SÍ entre a la base de AFP y NO a la de ONP, que es la asimetría del
--     sistema peruano y lo único de la 0256 con criterio técnico detrás;
--   · que una licencia sin monto entrado GRITE en vez de pagar cero callando.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000006b1', 'ZZMA', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000006b2', 'MatAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000006b1', 'admin', 'x',
        '00000000-0000-0000-0000-0000000006bf', '2024-01-01');
set session_replication_role = origin;

-- Cuatro personas idénticas salvo en lo que cada prueba mira. Ninguna marca:
-- así `pago_base` queda compuesto SOLO por el subsidio y cualquier peso extra
-- delata una fuga.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, regimen_pension) values
  ('00000000-0000-0000-0000-0000000006b3', 'MatAfp',     'Lab', '00000000-0000-0000-0000-0000000006b1', 'x', '2024-01-01', 'taller_produccion', 'planilla', 'integra'),
  ('00000000-0000-0000-0000-0000000006b4', 'MatOnp',     'Lab', '00000000-0000-0000-0000-0000000006b1', 'x', '2024-01-01', 'taller_produccion', 'planilla', 'onp'),
  ('00000000-0000-0000-0000-0000000006b5', 'MatControl', 'Lab', '00000000-0000-0000-0000-0000000006b1', 'x', '2024-01-01', 'taller_produccion', 'planilla', 'integra'),
  ('00000000-0000-0000-0000-0000000006b6', 'MatSinMonto','Lab', '00000000-0000-0000-0000-0000000006b1', 'x', '2024-01-01', 'taller_produccion', 'planilla', 'integra');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1185, '2024-01-01' from personas where apellidos = 'Lab' and nombres like 'Mat%';

-- Lunes a sábado. El domingo NO es laborable — y ese es justo el punto de la
-- prueba 1: en maternidad se paga igual.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39,
       '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
         "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
         "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb
from personas where apellidos = 'Lab' and nombres like 'Mat%';

-- El feriado que cae DENTRO de la licencia. La planilla ya lo paga en su propia
-- línea, así que el subsidio no debe cobrarlo otra vez.
insert into feriados (fecha, nombre) values ('2026-08-06', 'Batalla de Junín')
on conflict do nothing;

-- Licencia del 01 al 10 de agosto: DIEZ días corridos, con los domingos 02 y 09
-- dentro, y el feriado del 06. Si se contara por días laborables saldrían 7.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, subsidio_diario) values
  ('00000000-0000-0000-0000-0000000006b3', 'maternidad', '2026-08-01', '2026-08-10', 'lab', '00000000-0000-0000-0000-0000000006b2', 200.00),
  ('00000000-0000-0000-0000-0000000006b4', 'maternidad', '2026-08-01', '2026-08-10', 'lab', '00000000-0000-0000-0000-0000000006b2', 200.00),
  -- Sin monto entrado: el caso que tiene que gritar.
  ('00000000-0000-0000-0000-0000000006b6', 'maternidad', '2026-08-01', '2026-08-10', 'lab', '00000000-0000-0000-0000-0000000006b2', null);

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-0000000006e1', '2026-07-29', '2026-08-28', 'abierto');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000006bf', true);

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;

-- 1 · NUEVE días de diez: cae el feriado del 06, y NO caen los domingos. Si
--     alguien copia el filtro de días laborables del lateral `dmd`, salen 7 y
--     esta prueba lo dice.
select is(
  (pg_temp.fila('MatAfp Lab')->>'dias_subsidio_maternidad')::int, 9,
  'el subsidio cuenta días calendario: los domingos entran, el feriado no');

-- 2 · 9 × S/200.00. Antes de la 0256 esto era 0.00.
select is(
  (pg_temp.fila('MatAfp Lab')->>'monto_subsidio_maternidad')::numeric, 1800.00,
  'el subsidio vale días × monto diario, en vez de salir en cero');

-- 3 · Y llega al pago. Va DENTRO de pago_base, como el descanso médico desde la
--     0254: sin esto el concepto se vería en la boleta y el total no lo pagaría.
select is(
  (pg_temp.fila('MatAfp Lab')->>'pago_base')::numeric, 1800.00,
  'el subsidio llega a pago_base, no se queda en un informativo');

-- 4 · NO ES REMUNERACIÓN, y por eso no infla EsSalud. La de control es idéntica
--     salvo por no tener licencia. Si el subsidio se colara en `bri.base`, la de
--     maternidad subiría a 1800 y la de control se quedaría en el piso RMV.
select is(
  (pg_temp.fila('MatAfp Lab')->>'base_essalud')::numeric,
  (pg_temp.fila('MatControl Lab')->>'base_essalud')::numeric,
  'el subsidio no entra a la base de EsSalud: no es remuneración');

-- 5 · PERO SÍ A LA DE AFP. 1800 × (0.10 aporte + 0.0155 comisión + 0.0137 prima).
select is(
  (pg_temp.fila('MatAfp Lab')->>'descuento_afp')::numeric, 232.56,
  'la AFP sí retiene sobre el subsidio');

-- 6 · Y LA ONP NO. Misma licencia, mismo monto, régimen distinto. Es la
--     asimetría del sistema peruano, y vive en `tasas_pension.grava_subsidio`.
select is(
  (pg_temp.fila('MatOnp Lab')->>'descuento_afp')::numeric, 0.00,
  'el sistema nacional no grava el subsidio');

-- 7 · EL CIERRE NO SE CAE. `fn_planilla_congelar` inserta las ~30 filas en UNA
--     sentencia contra `chk_foto_cuadra`: si el total no cuadra con la suma de
--     columnas, no se congela NINGUNA y el mes entero se queda sin cerrar.
select is(
  (pg_temp.fila('MatAfp Lab')->>'total')::numeric,
  round( (pg_temp.fila('MatAfp Lab')->>'pago_base')::numeric
       + (pg_temp.fila('MatAfp Lab')->>'monto_feriados')::numeric
       + (pg_temp.fila('MatAfp Lab')->>'monto_plus')::numeric
       + (pg_temp.fila('MatAfp Lab')->>'asignacion_familiar')::numeric
       + (pg_temp.fila('MatAfp Lab')->>'monto_movilidad')::numeric
       + (pg_temp.fila('MatAfp Lab')->>'monto_educacion')::numeric
       - (pg_temp.fila('MatAfp Lab')->>'descuento_afp')::numeric
       + (pg_temp.fila('MatAfp Lab')->>'monto_sobretiempo')::numeric
       + (pg_temp.fila('MatAfp Lab')->>'bonos')::numeric
       - (pg_temp.fila('MatAfp Lab')->>'descuentos')::numeric
       - (pg_temp.fila('MatAfp Lab')->>'retencion_4ta')::numeric, 2),
  'la fila cuadra con chk_foto_cuadra: el cierre puede completarse');

-- 8 y 9 · LA ALARMA. Una licencia registrada sin monto no se puede pagar —no hay
--     con qué— pero tiene que verse. Un cero mudo aquí es el mismo defecto que
--     la 0254 vino a quitar del descanso médico.
select is(
  (pg_temp.fila('MatSinMonto Lab')->>'dias_maternidad_sin_monto')::int, 9,
  'una licencia sin monto entrado se cuenta y se dice');

select is(
  (pg_temp.fila('MatSinMonto Lab')->>'monto_subsidio_maternidad')::numeric, 0.00,
  'y no se inventa un monto: paga 0 hasta que DO entre el de EsSalud');

-- 10 · El monto solo se puede poner en una maternidad. La licencia por
--      paternidad la paga el empleador como REMUNERACIÓN y viaja por otra vía;
--      el descanso médico desde el día 21 también es subsidio pero la 0256 no lo
--      paga todavía. Dejar que se entre ahí sería prometer un pago que no ocurre.
select throws_ok($$
  insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, subsidio_diario)
  values ('00000000-0000-0000-0000-0000000006b5', 'permiso_personal', '2026-09-01', '2026-09-02',
          'lab', '00000000-0000-0000-0000-0000000006b2', 150.00)
$$, '23514', NULL,
  'no se puede poner subsidio en una ausencia que no es maternidad');

-- 11 · Tope legal: 98 días + 30 por parto múltiple o hijo con discapacidad.
select throws_ok($$
  insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, subsidio_diario)
  values ('00000000-0000-0000-0000-0000000006b5', 'maternidad', '2026-09-01', '2027-03-01',
          'lab', '00000000-0000-0000-0000-0000000006b2', 150.00)
$$, '23514', NULL,
  'una licencia con subsidio no puede pasar de 128 días');

select * from finish();
rollback;
