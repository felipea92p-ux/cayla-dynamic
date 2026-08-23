-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 216_el_descanso_semanal_trabajado_se_paga.test.sql
-- ============================================================================
-- EL FRENO QUE PIDE LA 0279. Su promesa se puede romper de cuatro maneras y
-- ninguna da error: pagando de más, pagando de menos, pagando a quien no le
-- toca, o tumbando el cierre del mes entero.
--
-- POR QUÉ CADA ASERCIÓN ESTÁ AQUÍ:
--
--   · 7 días pagan UNA y 8 días pagan UNA TAMBIÉN. Es lo primero que alguien
--     «arreglaría» al leer el código sin la norma delante: parece que el
--     octavo día también debería pagar. No — el ciclo se corta a los siete y
--     el octavo abre uno nuevo que todavía no se ha cerrado sin descanso.
--
--   · 14 días pagan DOS. La otra mitad de lo mismo: si alguien cambiara los
--     ciclos por una ventana móvil, catorce días pagarían ocho veces. Es el
--     error que la 0185 ya evitó en el sobretiempo, y se ancla acá para que no
--     lo reintroduzca quien toque una de las dos.
--
--   · 6 días NO pagan. Sin esto, un fallo de contorno convertiría cualquier
--     semana normal en una sobretasa.
--
--   · Locador y sueldo fijo quedan fuera; PERSONAL DE DIRECCIÓN NO. Esta
--     última es la que más fácil se «corrige» de vuelta, porque el sobretiempo
--     sí lo excluye (0187, art. 5 del D.S. 007-2002-TR). Son normas distintas:
--     aquélla es de jornada máxima y ésta es de descanso semanal. Decisión de
--     Felipe el 2026-08-20 sobre su propio pago.
--
--   · La VIGENCIA manda. La sobretasa es una fila de `parametros_laborales`, y
--     un día anterior a su `vigente_desde` no paga nada. Es lo que sostiene
--     «rige desde ahora y no hacia atrás» sin que dependa de una fecha escrita
--     en el código.
--
--   · Y EL CIERRE NO SE CAE. `fn_planilla_congelar` inserta las ~30 filas en
--     UNA sentencia: si `chk_foto_cuadra` rechaza una, no se congela NINGUNA.
--     Un concepto nuevo en el total sin su columna tumba el mes entero para
--     todos. Es exactamente lo que la 0201 tuvo que arreglar cuando la 0185
--     empezó a pagar sobretiempo, y por eso se prueba el cierre y no solo el
--     cálculo.
-- ============================================================================
begin;
select plan(11);

-- ── El laboratorio ──────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre)
values ('11111111-1111-1111-1111-111111111111', 'TST', 'Sede de prueba 216')
on conflict do nothing;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values ('aaaaaaaa-2160-0000-0000-00000000aaaa', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'admin216@ejemplo.test', 'x', now(), now())
on conflict (id) do nothing;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('22222222-2160-0000-0000-000000000001', date '2026-07-29', date '2026-08-28', 'abierto'),
       -- Un periodo anterior a la vigencia de la sobretasa, para la aserción 8.
       ('22222222-2160-0000-0000-000000000002', date '2026-06-29', date '2026-07-28', 'abierto');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, estado, tipo_vinculo,
                      sueldo_fijo, personal_direccion, fecha_ingreso, rol, auth_user_id)
values
 ('d0216000-0000-0000-0000-000000000001','Siete','Dias',   '11111111-1111-1111-1111-111111111111','x','activo','planilla',false,false,date '2025-01-01','integrante',null),
 ('d0216000-0000-0000-0000-000000000002','Ocho','Dias',    '11111111-1111-1111-1111-111111111111','x','activo','planilla',false,false,date '2025-01-01','integrante',null),
 ('d0216000-0000-0000-0000-000000000003','Seis','Dias',    '11111111-1111-1111-1111-111111111111','x','activo','planilla',false,false,date '2025-01-01','integrante',null),
 ('d0216000-0000-0000-0000-000000000004','Catorce','Dias', '11111111-1111-1111-1111-111111111111','x','activo','planilla',false,false,date '2025-01-01','integrante',null),
 ('d0216000-0000-0000-0000-000000000005','Locadora','RxH', '11111111-1111-1111-1111-111111111111','x','activo','rxh',     false,false,date '2025-01-01','integrante',null),
 ('d0216000-0000-0000-0000-000000000006','Fijo','Sueldo',  '11111111-1111-1111-1111-111111111111','x','activo','planilla',true, false,date '2025-01-01','integrante',null),
 ('d0216000-0000-0000-0000-000000000007','Direccion','Jefa','11111111-1111-1111-1111-111111111111','x','activo','planilla',false,true, date '2025-01-01','integrante',null),
 ('d0216000-0000-0000-0000-000000000008','Antes','DeQueRija','11111111-1111-1111-1111-111111111111','x','activo','planilla',false,false,date '2025-01-01','integrante',null),
 ('d0216000-0000-0000-0000-0000000000aa','Admin','216',    '11111111-1111-1111-1111-111111111111','x','activo','planilla',false,false,date '2025-01-01','admin','aaaaaaaa-2160-0000-0000-00000000aaaa');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1130, date '2025-01-01' from personas where id::text like 'd0216000%';

-- Rachas. 8 h por día para que el monto sea comprobable a mano:
--   8 × 1130 / (6.5 × 31) = 8 × 5.60794… = 44.86
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0216000-0000-0000-0000-000000000001', date '2026-08-01' + g, 8 from generate_series(0,6) g;
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0216000-0000-0000-0000-000000000002', date '2026-08-01' + g, 8 from generate_series(0,7) g;
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0216000-0000-0000-0000-000000000003', date '2026-08-01' + g, 8 from generate_series(0,5) g;
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0216000-0000-0000-0000-000000000004', date '2026-08-01' + g, 8 from generate_series(0,13) g;
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0216000-0000-0000-0000-000000000005', date '2026-08-01' + g, 8 from generate_series(0,6) g;
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0216000-0000-0000-0000-000000000006', date '2026-08-01' + g, 8 from generate_series(0,6) g;
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0216000-0000-0000-0000-000000000007', date '2026-08-01' + g, 8 from generate_series(0,6) g;
-- Racha entera dentro del periodo ANTERIOR a la vigencia.
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0216000-0000-0000-0000-000000000008', date '2026-07-10' + g, 8 from generate_series(0,6) g;

select set_config('request.jwt.claim.sub', 'aaaaaaaa-2160-0000-0000-00000000aaaa', true);

create temporary table calc_216 on commit drop as
select f->>'nombre'                              as quien,
       (f->>'descanso_semanal_dias')::int        as dias,
       (f->>'monto_descanso_semanal')::numeric   as monto
  from jsonb_array_elements(
         (fn_planilla_calcular(date '2026-07-29', date '2026-08-28',
                               '22222222-2160-0000-0000-000000000001')->'filas')) f;

-- ── 1-3 · El corte del ciclo, que es donde está toda la norma ───────────────
select is((select dias from calc_216 where quien = 'Siete Dias'), 1,
  'siete dias seguidos pagan UNA sobretasa: el septimo se trabajo en vez de descansar');

select is((select dias from calc_216 where quien = 'Ocho Dias'), 1,
  'ocho dias pagan UNA TAMBIEN, no dos: el octavo abre un ciclo que aun no se cerro sin descanso');

select is((select dias from calc_216 where quien = 'Catorce Dias'), 2,
  'catorce dias pagan DOS: dos ciclos completos, y los ciclos no se solapan');

-- ── 4 · El contorno ────────────────────────────────────────────────────────
select is((select dias from calc_216 where quien = 'Seis Dias'), 0,
  'seis dias no pagan nada: la semana normal no genera sobretasa');

-- ── 5 · El monto, comprobable a mano ───────────────────────────────────────
select is((select monto from calc_216 where quien = 'Siete Dias'), 44.86,
  'la sobretasa es el RECARGO de las horas de ese dia: 8 x 1130 / (6.5 x 31) = 44.86');

-- ── 6-7 · Quien queda fuera, y quien NO ────────────────────────────────────
select is((select monto from calc_216 where quien = 'Locadora RxH'), 0.00,
  'un locador no tiene descanso remunerado que respetarle (mismo criterio que la 0199)');

select is((select monto from calc_216 where quien = 'Fijo Sueldo'), 0.00,
  'sueldo fijo no cobra recargo por horas: su pago no depende de horas');

select is((select monto from calc_216 where quien = 'Direccion Jefa'), 44.86,
  'al personal de direccion SI se le paga: el art. 5 lo excluye de la jornada maxima, no del descanso semanal');

-- ── 8 · La vigencia manda ──────────────────────────────────────────────────
select is(
  (select (f->>'monto_descanso_semanal')::numeric
     from jsonb_array_elements(
            (fn_planilla_calcular(date '2026-06-29', date '2026-07-28',
                                  '22222222-2160-0000-0000-000000000002')->'filas')) f
    where f->>'nombre' = 'Antes DeQueRija'),
  0.00,
  'antes del vigente_desde del parametro no se paga nada: rige desde ahora, no hacia atras');

-- ── 9-10 · Y el cierre no se cae ───────────────────────────────────────────
select lives_ok(
  $$select fn_planilla_congelar('22222222-2160-0000-0000-000000000001', 'pago',
                                'd0216000-0000-0000-0000-0000000000aa')$$,
  'el cierre congela con el concepto nuevo: chk_foto_cuadra lo conoce y no tumba el mes entero');

select is(
  (select sum(monto_descanso_semanal) from planilla_pagada_detalle
    where periodo_id = '22222222-2160-0000-0000-000000000001'),
  224.31,
  'la foto guarda la sobretasa: 44.86 x 3 + 89.73 de la racha de catorce');

select * from finish();
rollback;
