-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 214_la_base_de_la_liquidacion_solo_admite_bonos.test.sql
-- ============================================================================
-- EL FRENO QUE PIDE LA 0277. Su promesa tiene DOS mitades y las dos pueden
-- romperse, cada una hacia un lado distinto:
--
--   · hacia arriba, que vuelva a entrar a la base algo que no es un bono —un
--     adelanto que la persona debe, o la gratificación y la CTS que el propio
--     sistema depositó—;
--   · hacia abajo, que alguien «arregle» el defecto apagando el interruptor
--     `liquidacion_incluye_variables` y deje de pagar el bono regular que el
--     art. 16 del D.S. 001-97-TR manda incorporar.
--
-- Las aserciones 1 a 8 defienden la primera mitad; la 9 y la 10 defienden la
-- segunda. La 12 defiende la lista blanca: si mañana alguien agrega una quinta
-- categoría a `movimientos_planilla` sin decidir si entra o no a la
-- liquidación, esta prueba se pone roja antes de que el silencio pague nada.
--
-- POR QUÉ SE MIDEN MONTOS Y NO SEÑALES DE VIDA. Este camino no tiene campo
-- editable: `fn_liquidacion` recalcula, `fn_liquidacion_pagar` congela y se
-- paga. Una aserción que solo comprobara que la función «responde algo» dejaría
-- pasar exactamente el defecto que la 0277 cierra.
--
-- LA CIFRA DE CONTROL ES S/1.867,40, la liquidación de quien no percibió más
-- que su sueldo. Los seis casos del laboratorio se diferencian ÚNICAMENTE en
-- los movimientos de planilla que tienen encima.
-- ============================================================================
begin;
select plan(19);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000277000', 'ZZ277', 'Sede de laboratorio 277', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000002770ad', 'SieteAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000277000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000002770a9', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002770a9', true);

-- Seis personas idénticas: S/1.950, ingreso 01/01/2024, sin hijos.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000027700a','SieteA','Laboratorio','00000000-0000-0000-0000-000000277000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-00000027700b','SieteB','Laboratorio','00000000-0000-0000-0000-000000277000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-00000027700c','SieteC','Laboratorio','00000000-0000-0000-0000-000000277000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-00000027700d','SieteD','Laboratorio','00000000-0000-0000-0000-000000277000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-00000027700e','SieteE','Laboratorio','00000000-0000-0000-0000-000000277000','test-hash','2024-01-01','planilla'),
  ('00000000-0000-0000-0000-00000027700f','SieteF','Laboratorio','00000000-0000-0000-0000-000000277000','test-hash','2024-01-01','planilla'),
  -- G · la del candado: dos meses con bono y ninguna autorizacion. El tercero
  -- es el que tiene que rebotar.
  ('00000000-0000-0000-0000-0000002770aa','SieteG','Laboratorio','00000000-0000-0000-0000-000000277000','test-hash','2024-01-01','planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000027700a','colibri',1950.00,'2024-01-01'),
  ('00000000-0000-0000-0000-00000027700b','colibri',1950.00,'2024-01-01'),
  ('00000000-0000-0000-0000-00000027700c','colibri',1950.00,'2024-01-01'),
  ('00000000-0000-0000-0000-00000027700d','colibri',1950.00,'2024-01-01'),
  ('00000000-0000-0000-0000-00000027700e','colibri',1950.00,'2024-01-01'),
  ('00000000-0000-0000-0000-00000027700f','colibri',1950.00,'2024-01-01'),
  ('00000000-0000-0000-0000-0000002770aa','colibri',1950.00,'2024-01-01');

-- Cinco periodos del 29 al 28, como los de CAYLA, dentro del semestre jul-dic.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000277071','2026-06-29','2026-07-28','pagado'),
  ('00000000-0000-0000-0000-000000277081','2026-07-29','2026-08-28','pagado'),
  ('00000000-0000-0000-0000-000000277091','2026-08-29','2026-09-28','pagado'),
  ('00000000-0000-0000-0000-000000277101','2026-09-29','2026-10-28','pagado'),
  ('00000000-0000-0000-0000-000000277111','2026-10-29','2026-11-28','pagado');

-- A, B, C y D reciben lo que el sistema deposita SOLO, sin que nadie lo pida:
-- la gratificación del 15/07 y la CTS del 15/11. Las dos son `tipo = 'bono'`
-- por decisión de la 0049, y ahí está el defecto: aportaban dos de los tres
-- meses que la regla de regularidad exige.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria)
select '00000000-0000-0000-0000-000000277071', p.id, 'bono', 'Gratificacion Jul 2026', 1950.00, 'gratificacion'
  from personas p where p.id in ('00000000-0000-0000-0000-00000027700a','00000000-0000-0000-0000-00000027700b',
                                 '00000000-0000-0000-0000-00000027700c','00000000-0000-0000-0000-00000027700d');
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria)
select '00000000-0000-0000-0000-000000277111', p.id, 'bono', 'CTS Nov 2026', 1137.50, 'cts'
  from personas p where p.id in ('00000000-0000-0000-0000-00000027700a','00000000-0000-0000-0000-00000027700b',
                                 '00000000-0000-0000-0000-00000027700c','00000000-0000-0000-0000-00000027700d');

-- B · el tercer mes lo pone un bono de S/50, uno solo. No es regular.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria)
values ('00000000-0000-0000-0000-000000277091','00000000-0000-0000-0000-00000027700b','bono','Reconocimiento del mes',50.00,null);

-- C · el tercer mes lo pone un ADELANTO. Es una deuda, no un ingreso.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria)
values ('00000000-0000-0000-0000-000000277091','00000000-0000-0000-0000-00000027700c','descuento','Adelanto quincenal',500.00,null);

-- D · un bono GENUINO y REGULAR: S/200 en tres meses distintos. Este SÍ entra.
--
-- ⇩ Y AQUÍ SE CRUZA CON EL CANDADO, a propósito. El tercero es exactamente el
-- movimiento que el candado de esta migración rechaza, así que para ponerlo hay
-- que pasar por la puerta autorizada — que es la que se probará en las
-- aserciones 13 a 16. Si el candado dejara de existir, estas dos líneas de
-- autorización sobrarían y nadie se enteraría; por eso la 13 comprueba lo
-- contrario: que SIN autorización el insert revienta.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria) values
  ('00000000-0000-0000-0000-000000277081','00000000-0000-0000-0000-00000027700d','bono','Comision de venta',200.00,null),
  ('00000000-0000-0000-0000-000000277091','00000000-0000-0000-0000-00000027700d','bono','Comision de venta',200.00,null);

select fn_permitir_bono_regular('00000000-0000-0000-0000-00000027700d',
  'Comision de venta pactada en contrato: es remuneracion regular y debe entrar en la base');

insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria) values
  ('00000000-0000-0000-0000-000000277101','00000000-0000-0000-0000-00000027700d','bono','Comision de venta',200.00,null);

-- E · SOLO adelantos, sin grati ni CTS de por medio. El caso puro del signo.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria) values
  ('00000000-0000-0000-0000-000000277081','00000000-0000-0000-0000-00000027700e','descuento','Adelanto quincenal',500.00,null),
  ('00000000-0000-0000-0000-000000277091','00000000-0000-0000-0000-00000027700e','descuento','Adelanto quincenal',500.00,null),
  ('00000000-0000-0000-0000-000000277101','00000000-0000-0000-0000-00000027700e','descuento','Adelanto quincenal',500.00,null);

-- F · SOLO vacaciones pagadas. Son los mismos soles del sueldo (art. 15 del
--     D. Leg. 713), y `sueldo_basico` ya los cuenta una vez.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria) values
  ('00000000-0000-0000-0000-000000277081','00000000-0000-0000-0000-00000027700f','bono','Vacaciones ago 2026',650.00,'vacaciones'),
  ('00000000-0000-0000-0000-000000277091','00000000-0000-0000-0000-00000027700f','bono','Vacaciones set 2026',650.00,'vacaciones'),
  ('00000000-0000-0000-0000-000000277101','00000000-0000-0000-0000-00000027700f','bono','Vacaciones oct 2026',650.00,'vacaciones');


-- ── 1 y 2 · La gratificación y la CTS que deposita el sistema no cuentan ─────
-- Antes de la 0277 daban 2 meses y S/3.087,50. Dos meses no disparaban solos,
-- pero dejaban la puerta a un centímetro: cualquier tercer movimiento entraba.
select is(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700a','2026-10-31')->>'variables_meses')::int,
  0,
  'La grati y la CTS que el sistema deposita no cuentan ni un mes de regularidad'
);
select is(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700a','2026-10-31')->>'variables_total')::numeric,
  0.00::numeric,
  'La grati y la CTS que el sistema deposita no suman ni un sol a la base'
);

-- ── 3 y 4 · Un adelanto no es un ingreso ────────────────────────────────────
select is(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700e','2026-10-31')->>'variables_meses')::int,
  0,
  'Tres adelantos en tres meses no cuentan como tres meses de bono'
);
select is(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700e','2026-10-31')->>'variables_total')::numeric,
  0.00::numeric,
  'Un adelanto, que es plata que la persona debe, no suma a la base'
);

-- ── 5 · Las vacaciones ya cobradas no se cuentan dos veces ──────────────────
select is(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700f','2026-10-31')->>'variables_meses')::int,
  0,
  'Las vacaciones pagadas no cuentan meses: ya viajan dentro del sueldo basico'
);

-- ── 6 · Un bono solitario no llega a la regla de los tres meses ─────────────
select is(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700b','2026-10-31')->>'variables_promedio')::numeric,
  0.00::numeric,
  'Un unico bono de S/50 en un solo mes no entra a la base'
);
select is(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700b','2026-10-31')->>'variables_entran')::boolean,
  false,
  'Con un solo mes de bono, variables_entran dice false'
);

-- ── 7 · Y el monto que se paga ──────────────────────────────────────────────
-- Cuatro casos distintos que tienen que dar la MISMA cifra de control, porque
-- ninguno de los cuatro percibió nada por encima de su sueldo.
select results_eq(
  $$ select round((fn_liquidacion(p.id, '2026-11-30')->>'total')::numeric, 2)
       from personas p
      where p.id in ('00000000-0000-0000-0000-00000027700a',
                     '00000000-0000-0000-0000-00000027700b',
                     '00000000-0000-0000-0000-00000027700c')
      order by p.nombres $$,
  $$ values (1867.40::numeric), (1867.40::numeric), (1867.40::numeric) $$,
  'Sin bono real, la liquidacion es S/1.867,40 con o sin grati, CTS o adelanto encima'
);

-- ── 8 · El caso E y el F, que no tienen grati ni CTS descontada ─────────────
select is(
  round((fn_liquidacion('00000000-0000-0000-0000-00000027700e','2026-11-30')->>'total')::numeric, 2),
  round((fn_liquidacion('00000000-0000-0000-0000-00000027700f','2026-11-30')->>'total')::numeric, 2),
  'Tres adelantos y tres pagos de vacaciones dan la misma liquidacion: ninguno mueve la base'
);

-- ── 9 y 10 · LA OTRA MITAD: el bono genuino SIGUE entrando ──────────────────
-- Esto es lo que separa este arreglo de apagar el interruptor. Con
-- `liquidacion_incluye_variables = false` estas dos aserciones caen, y caer
-- aqui significa pagar S/95,42 por DEBAJO de lo que manda el art. 16 del
-- D.S. 001-97-TR. Es una infraccion laboral, no un ahorro.
select is(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700d','2026-10-31')->>'variables_promedio')::numeric,
  100.00::numeric,
  'Un bono regular de S/200 en tres meses entra como S/100,00 (suma / 6, art. 16)'
);
-- ⇩ EL NUMERO BAJO S/4,17 AL PONER LAS VENTANAS BIEN, Y ESO ES CORRECTO.
--
-- La primera version de esta prueba esperaba S/1.962,82, medido cuando los tres
-- beneficios compartian la ventana enero-junio / julio-diciembre. Con la CTS
-- mirando su propio periodo —noviembre a abril— sus bonos de agosto, setiembre
-- y octubre ya no cuentan ahi: pertenecen al periodo mayo-octubre, que se
-- deposito el 15 de noviembre. Contarlos otra vez en el periodo siguiente era
-- cobrarlos dos veces.
--
-- La gratificacion y las vacaciones NO se movieron: sus S/95,42 - S/4,17 siguen
-- llegando. Si alguien vuelve a juntar las tres ventanas, este numero sube y
-- esta aserción se pone roja.
select is(
  round((fn_liquidacion('00000000-0000-0000-0000-00000027700d','2026-11-30')->>'total')::numeric, 2),
  1958.65::numeric,
  'Y llega al monto que se paga: S/1.958,65, S/91,25 mas que sin el bono'
);

-- ── 11 · La lista blanca sigue cubriendo todas las categorias que existen ───
-- Si alguien agrega una quinta categoria a `movimientos_categoria_valida` sin
-- decidir si entra o no a la liquidacion, esta aserción se pone roja. El
-- silencio no puede ser la respuesta: la de arriba paga de mas y la de abajo
-- paga de menos.
select is(
  (select array_agg(c order by c)
     from (select unnest(regexp_matches(pg_get_constraintdef(oid), '''([a-z]+)''::text', 'g')) as c
             from pg_constraint
            where conrelid = 'movimientos_planilla'::regclass
              and conname = 'movimientos_categoria_valida') t),
  array['cts','gratificacion','otros','vacaciones'],
  'La lista blanca de la 0277 conoce todas las categorias que el check admite'
);

insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto) values
  ('00000000-0000-0000-0000-000000277081','00000000-0000-0000-0000-0000002770aa','bono','Bono agosto',50.00),
  ('00000000-0000-0000-0000-000000277091','00000000-0000-0000-0000-0000002770aa','bono','Bono setiembre',50.00);

-- ── 13 a 16 · EL CANDADO ────────────────────────────────────────────────────
--
-- Decisión de Felipe del 2026-08-22: que la base RECHACE el bono que cruzaría
-- el umbral, no que avise. Estas cuatro aserciones son el freno del freno.
--
-- La 13 es la que de verdad importa: si alguien quita el trigger, el resto de
-- este archivo sigue pasando en verde —los cálculos no dependen de él— y solo
-- ésta se pone roja.
select throws_ok(
  $$ insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto)
     values ('00000000-0000-0000-0000-000000277101','00000000-0000-0000-0000-0000002770aa','bono','Tercer mes',50) $$,
  'P0001', null,
  'CANDADO · el bono que seria el tercer mes de la ventana se rechaza');

-- El motivo no es un trámite: es lo único que quedará escrito el día que
-- alguien pregunte por qué se autorizó.
select throws_ok(
  $$ select fn_permitir_bono_regular('00000000-0000-0000-0000-0000002770aa','corto') $$,
  'P0001', null,
  'CANDADO · autorizar sin un motivo de verdad no se puede');

-- Y el permiso es de UN SOLO USO. Si se quedara abierto, la primera
-- autorización valdría para siempre y el candado sería decorativo.
select lives_ok(
  $$ select fn_permitir_bono_regular('00000000-0000-0000-0000-0000002770aa',
       'Bono por cierre de tienda nueva, acordado en acta del 20/10/2026');
     insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto)
     values ('00000000-0000-0000-0000-000000277101','00000000-0000-0000-0000-0000002770aa','bono','Autorizado',50) $$,
  'CANDADO · con motivo escrito, el bono entra');

select throws_ok(
  $$ insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto)
     values ('00000000-0000-0000-0000-000000277101','00000000-0000-0000-0000-0000002770aa','bono','Sin permiso ya',50) $$,
  'P0001', null,
  'CANDADO · y el permiso se gasta: el siguiente vuelve a rechazarse');

-- ── 17 · La ventana de la CTS no es la de la gratificación ──────────────────
-- El defecto que nadie había visto: `fn_remuneracion_computable` usaba una sola
-- ventana —ene-jun / jul-dic— para los tres beneficios. La de la CTS va de
-- noviembre a abril y de mayo a octubre. Mirado al 30/11, la de la grati
-- empieza el 01/07 y la de la CTS el 01/11: si las dos dieran lo mismo, es que
-- el parámetro no está llegando.
select isnt(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700d','2026-11-30','grati')->>'semestre_desde'),
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700d','2026-11-30','cts')->>'semestre_desde'),
  'VENTANAS · la CTS mira su propio periodo, no el de la gratificacion');

select is(
  (fn_remuneracion_computable('00000000-0000-0000-0000-00000027700d','2026-11-30','cts')->>'semestre_desde'),
  '2026-11-01',
  'VENTANAS · y ese periodo empieza el 1 de noviembre, no el 1 de julio');

-- Un beneficio mal escrito revienta en vez de caer al defecto, igual que hace
-- `fn_devenga` desde la 0196.
select throws_ok(
  $$ select fn_remuneracion_computable('00000000-0000-0000-0000-00000027700d'::uuid,'2026-11-30'::date,'ctss') $$,
  'P0001', null,
  'VENTANAS · un beneficio desconocido lanza en vez de adivinar');

select * from finish();
rollback;
