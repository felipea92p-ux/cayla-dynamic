-- ============================================================================
-- 148_quien_ya_se_jubilo_no_aporta.test.sql — el régimen «jubilada» (mig 0190)
-- ============================================================================
-- Judith ya percibe su pensión de jubilación y sigue trabajando. Aportar de
-- nuevo sería descontarle de su sueldo para un fondo del que ya está cobrando.
--
-- Lo que se blinda, y por qué cada cosa:
--
--   1 · con régimen «jubilada» el descuento previsional es CERO — es el efecto
--       que se busca, y el único que le sube el líquido;
--   2 · **EsSalud y los beneficios NO se apagan con él.** Es lo que más importa:
--       apagar el aporte previsional y de paso dejarla sin gratificación o sin
--       EsSalud sería un daño mucho mayor que el que se vino a arreglar, y
--       ninguna pantalla lo mostraría;
--   3 · el valor se puede guardar de verdad (el CHECK lo acepta);
--   4 · dejar el régimen VACÍO no es lo mismo: cae a la tasa global, y por eso
--       la decisión se escribe en vez de deducirse de un hueco.
--
-- Un sueldo de 1,200 con 26 días trabajados: números redondos, sin feriados en
-- el rango elegido, para que la aritmética se siga de cabeza.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000bb', 'ZZJUB', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000bb99', 'JubAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000bb', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000bb98');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000bb98', true);

-- Dos personas idénticas salvo el régimen: la comparación entre ellas es la
-- prueba. Una sola no distinguiría «no le descuentan» de «no hay nada que
-- descontar».
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, regimen_pension) values
  ('00000000-0000-0000-0000-00000000bb01', 'JubJubilada', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000bb', 'test-hash', '2025-01-01', 'jubilada'),
  ('00000000-0000-0000-0000-00000000bb02', 'JubAporta', 'Laboratorio',
   '00000000-0000-0000-0000-0000000000bb', 'test-hash', '2025-01-01', 'integra');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000000bb01', 'cayla', 1200, '2025-01-01'),
  ('00000000-0000-0000-0000-00000000bb02', 'cayla', 1200, '2025-01-01');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 8, 'cerrada'
from generate_series('2026-04-01'::date, '2026-04-28'::date, interval '1 day') d
cross join (values ('00000000-0000-0000-0000-00000000bb01'::uuid),
                   ('00000000-0000-0000-0000-00000000bb02'::uuid)) as p(id)
where extract(dow from d) <> 0;

create temp table _calc on commit drop as
select (e->>'persona_id')::uuid                as persona_id,
       (e->>'descuento_afp')::numeric      as descuento,
       (e->>'aporte_essalud')::numeric                as essalud,
       (e->>'total')::numeric                  as total
from jsonb_array_elements(fn_planilla_calcular('2026-04-01','2026-04-28') -> 'filas') e;

-- ── 1 · El descuento previsional se apaga ──────────────────────────────────
select is(
  (select descuento from _calc where persona_id = '00000000-0000-0000-0000-00000000bb01'),
  0::numeric,
  'JUBILADA · no se le descuenta ni un céntimo de pensión');

select cmp_ok(
  (select descuento from _calc where persona_id = '00000000-0000-0000-0000-00000000bb02'),
  '>', 0::numeric,
  'Y a quien sí aporta se le sigue descontando: el cambio no se le contagia');

-- ── 2 · Y por eso recibe MÁS: es todo el punto ─────────────────────────────
-- Mismo sueldo, mismos días. La diferencia entre las dos es exactamente lo que
-- antes se le remitía a la AFP y ahora se queda con ella.
select cmp_ok(
  (select total from _calc where persona_id = '00000000-0000-0000-0000-00000000bb01'),
  '>', (select total from _calc where persona_id = '00000000-0000-0000-0000-00000000bb02'),
  'Con el mismo sueldo y los mismos días, la jubilada recibe más');

-- ── 3 · Lo que NO se apaga ─────────────────────────────────────────────────
-- El daño más caro de este cambio sería que, de paso, la dejara sin EsSalud o
-- sin beneficios. Sigue siendo trabajadora en planilla.
select is(
  (select essalud from _calc where persona_id = '00000000-0000-0000-0000-00000000bb01'),
  (select essalud from _calc where persona_id = '00000000-0000-0000-0000-00000000bb02'),
  'EsSalud NO se apaga: la empresa aporta su 9% igual que por cualquier otra');

select ok(
  fn_devenga_beneficios((select tipo_vinculo from personas
                          where id = '00000000-0000-0000-0000-00000000bb01')),
  'Sigue devengando gratificación, CTS y vacaciones: eso lo decide el vínculo');

-- ── 4 · Vacío NO es lo mismo que jubilada ──────────────────────────────────
-- Sin régimen, el cálculo cae a `configuracion.tasa_afp`. Hoy vale 0 y por eso
-- «funciona», pero es una coincidencia: si esa tasa cambia —para cubrir a quien
-- todavía no está clasificado, que es su motivo— el descuento vuelve. Por eso la
-- decisión se ESCRIBE en la ficha en vez de deducirse de un hueco.
update configuracion set valor = '{"tasa": 0.13}'::jsonb where clave = 'tasa_afp';
update personas set regimen_pension = null where id = '00000000-0000-0000-0000-00000000bb01';

select cmp_ok(
  (select (e->>'descuento_afp')::numeric
     from jsonb_array_elements(fn_planilla_calcular('2026-04-01','2026-04-28') -> 'filas') e
    where (e->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000bb01'),
  '>', 0::numeric,
  'VACÍO no la protege: con la tasa global distinta de 0, volvería el descuento');

select * from finish();
rollback;
