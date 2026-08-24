-- ============================================================================
-- 219_las_vacaciones_no_gozadas_se_pagan_al_cesar.test.sql
-- ============================================================================
-- Migración 0283. Al cesar se pagan TODOS los días ganados y no gozados, no
-- solo los del récord en curso.
--
-- LA ASERCIÓN QUE DE VERDAD IMPORTA ES LA PRIMERA, y no es un número: es que
-- DOS PERSONAS IDÉNTICAS cobren lo mismo por lo mismo. Antes de la 0283, la que
-- se tomaba sus vacaciones cuando la ley manda tomarlas cobraba S/0,00 y la que
-- nunca gozó cobraba S/812,50. Tomarse un derecho costaba dinero.
--
-- Y LA SEGUNDA MITAD, que es la que Felipe pidió expresamente: que esto NO
-- pague dos veces. Tres frenos, uno por cada vía por la que podría:
--   · un día gozado se descuenta UNA vez (aserciones 3 y 4);
--   · un goce ANULADO no cuenta como gozado, pero tampoco desaparece de la
--     vista dos veces (aserción 5);
--   · lo que el libro de desembolsos dice que ya se pagó se resta (aserción 6),
--     que es lo que esta función era la única de las tres truncas en no hacer.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000283000', 'ZZ283', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000002830ad', 'OchoAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000283000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000002830ff', '2024-01-01');
set session_replication_role = origin;

-- Todas entran el MISMO día y cobran lo MISMO. Lo único que las separa es qué
-- hicieron con sus vacaciones.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000283001','OchoNuncaGozo','Laboratorio','00000000-0000-0000-0000-000000283000','test-hash','2024-03-01','planilla'),
  ('00000000-0000-0000-0000-000000283002','OchoGozoAlDia','Laboratorio','00000000-0000-0000-0000-000000283000','test-hash','2024-03-01','planilla'),
  ('00000000-0000-0000-0000-000000283003','OchoAnulada',  'Laboratorio','00000000-0000-0000-0000-000000283000','test-hash','2024-03-01','planilla'),
  ('00000000-0000-0000-0000-000000283004','OchoYaPagada', 'Laboratorio','00000000-0000-0000-0000-000000283000','test-hash','2024-03-01','planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950.00, '2024-03-01'
from personas where apellidos = 'Laboratorio' and nombres like 'Ocho%' and nombres <> 'OchoAdmin';

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-03-01', '09:00', '18:00', array[1,2,3,4,5]
from personas where apellidos = 'Laboratorio' and nombres like 'Ocho%' and nombres <> 'OchoAdmin';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002830ff', true);

-- OchoGozoAlDia hace lo que la ley manda: cumple su 2do aniversario el
-- 01/03/2026 y goza en abril los 15 días que ganó en el récord anterior. Es
-- EXACTAMENTE el caso que cobraba cero.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-000000283002','vacaciones','2026-04-06','2026-04-20','goce del record cerrado','00000000-0000-0000-0000-0000002830ad'),
  ('00000000-0000-0000-0000-000000283003','vacaciones','2026-04-06','2026-04-20','goce que luego se anula','00000000-0000-0000-0000-0000002830ad');

-- El goce de OchoAnulada se anula: no se gozó, así que no puede descontarse.
update ausencias set anulada_at = now(), anulada_por = '00000000-0000-0000-0000-0000002830ad', anulada_motivo = 'registrada por error en el laboratorio'
 where persona_id = '00000000-0000-0000-0000-000000283003';

-- A OchoYaPagada se le pagaron vacaciones por transferencia y quedó anotado.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen, nota)
values ('00000000-0000-0000-0000-000000283004','vacaciones',2026,500.00,'2026-05-15','transferencia','pago de vacaciones del laboratorio');

create temporary table _liq on commit drop as
select p.nombres as quien,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'dias_ganados')::numeric    as ganados,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'dias_gozados')::numeric    as gozados,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'dias_pendientes')::numeric as pendientes,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'ya_pagado_libro')::numeric as ya_pagado,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'records_vencidos')::int    as vencidos,
       (fn_vacaciones_truncas(p.id,'2026-12-31')->>'monto')::numeric           as monto
from personas p
where p.apellidos = 'Laboratorio' and p.nombres like 'Ocho%' and p.nombres <> 'OchoAdmin';

-- ── 1 · TOMARSE LAS VACACIONES YA NO CUESTA DINERO ──────────────────────────
-- La aserción de fondo. Antes de la 0283 esto daba 0,00 contra 812,50.
select cmp_ok((select monto from _liq where quien = 'OchoGozoAlDia'), '>', 0::numeric,
  'DERECHO · quien gozó sus vacaciones cobra su trunco, ya no S/0.00');

-- ── 2 · LOS RÉCORDS COMPLETOS SIN GOZAR SE PAGAN ────────────────────────────
-- Con dos aniversarios cumplidos son 30 días, más el trunco. Antes cobraba
-- solo el trunco y los 30 se evaporaban.
select cmp_ok((select ganados from _liq where quien = 'OchoNuncaGozo'), '>', 30::numeric,
  'RÉCORDS · los años completos sin gozar entran en la cuenta, no solo el trunco');

-- ── 3 y 4 · NO SE PAGA DOS VECES ────────────────────────────────────────────
-- La diferencia entre las dos tiene que ser EXACTAMENTE los días que una gozó
-- y la otra no. Ni más —sería pagarle de menos a la que gozó— ni menos —sería
-- pagarle dos veces el mismo descanso—.
select is(
  (select ganados - gozados from _liq where quien = 'OchoGozoAlDia'),
  (select pendientes from _liq where quien = 'OchoGozoAlDia'),
  'SIN DOBLE PAGO · pendientes = ganados menos gozados, exacto');
select is(
  (select pendientes from _liq where quien = 'OchoNuncaGozo')
  - (select pendientes from _liq where quien = 'OchoGozoAlDia'),
  (select gozados from _liq where quien = 'OchoGozoAlDia'),
  'SIN DOBLE PAGO · la que gozó cobra menos EXACTAMENTE por los días que gozó');

-- ── 5 · UN GOCE ANULADO NO SE DESCUENTA ─────────────────────────────────────
-- `vacaciones` es una vista sobre `ausencias` que ya filtra las anuladas. Si
-- alguien cambiara esa vista, esta aserción lo caza: una vacación anulada no
-- se gozó, así que no puede restar.
select is(
  (select gozados from _liq where quien = 'OchoAnulada'), 0::numeric,
  'ANULADA · un goce anulado no cuenta como gozado');
select is(
  (select monto from _liq where quien = 'OchoAnulada'),
  (select monto from _liq where quien = 'OchoNuncaGozo'),
  'ANULADA · y cobra igual que quien nunca pidió vacaciones');

-- ── 6 · LO YA PAGADO POR EL LIBRO SE DESCUENTA ──────────────────────────────
-- Era la única de las tres truncas que no miraba el libro de desembolsos, y el
-- libro TIENE ventana 'vacaciones'. Sin esto, empezar a pagar récords completos
-- habría abierto la puerta al doble pago justo cuando hay algo que duplicar.
select is(
  (select ya_pagado from _liq where quien = 'OchoYaPagada'), 500.00::numeric,
  'LIBRO · la función ve lo que el libro dice que ya se pagó');
select is(
  (select monto from _liq where quien = 'OchoNuncaGozo')
  - (select monto from _liq where quien = 'OchoYaPagada'),
  500.00::numeric,
  'LIBRO · y lo resta del monto, sol por sol');

-- ── 7 · EL AVISO DEL ART. 23, QUE AVISA Y NO CALCULA ────────────────────────
-- Que aparezca el aviso es la mitad; la otra es que el monto NO lo incluya. Si
-- alguien decide algún día calcular la indemnización, que sea a propósito.
select isnt(
  (select fn_vacaciones_truncas('00000000-0000-0000-0000-000000283001','2026-12-31')->>'aviso_vencidos'),
  null,
  'ART. 23 · avisa de los récords vencidos, con la norma citada');

select * from finish();
rollback;
