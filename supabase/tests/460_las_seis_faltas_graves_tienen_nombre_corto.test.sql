-- 460 · Las seis faltas graves del 53.3 tienen nombre corto (migración 0570)
--
-- Por qué existe esta prueba y no basta la 408: la 408 defiende la invariante
-- —«ninguna falta del catálogo queda sin nombre corto»— y la 0568 la rompió sin
-- que ninguna de sus propias pruebas lo viera. Esta fija los seis nombres uno
-- por uno, para que el día que alguien agregue un numeral nuevo al catálogo
-- sepa que el rótulo va en el mismo lote, y para que cambiarle el nombre a una
-- falta grave sea una decisión y no un descuido.
--
-- Control: sin la 0570, las aserciones 1 a 7 fallan.

begin;
select plan(10);

-- ── LOS SEIS NOMBRES ────────────────────────────────────────────────────────
select is((select count(*)::int from faltas_rotulos where rit_version = 4.0 and numeral = '53.3'), 6,
  'GRAVES · los seis literales del 53.3 tienen nombre corto');

select is((select rotulo from faltas_rotulos where rit_version = 4.0 and numeral = '53.3' and literal = 'a'),
  'Marcó por otra o falseó datos', 'GRAVES · el 53.3 a) no se confunde con «Olvidó marcar» del 53.1 a)');
select is((select rotulo from faltas_rotulos where rit_version = 4.0 and numeral = '53.3' and literal = 'b'),
  'Apropiación de bienes o dinero', 'GRAVES · el 53.3 b) no se confunde con «Caja o inventario» del 53.2 g)');
select is((select rotulo from faltas_rotulos where rit_version = 4.0 and numeral = '53.3' and literal = 'c'),
  'Entregó información reservada', 'GRAVES · el 53.3 c) no se confunde con «Divulgó información» del 53.2 i)');
select is((select rotulo from faltas_rotulos where rit_version = 4.0 and numeral = '53.3' and literal = 'd'),
  'Agresión o grave indisciplina', 'GRAVES · el 53.3 d) no se confunde con «Trato descortés» del 53.2 h)');
select is((select rotulo from faltas_rotulos where rit_version = 4.0 and numeral = '53.3' and literal = 'e'),
  'Abandono, ausencias o tardanzas', 'GRAVES · el 53.3 e) nombra las tres conductas del literal');
select is((select rotulo from faltas_rotulos where rit_version = 4.0 and numeral = '53.3' and literal = 'f'),
  'Hostigamiento sexual', 'GRAVES · el 53.3 f) se nombra igual, aunque no vaya por un memo');

-- ── LA INVARIANTE, QUE ES LO QUE DE VERDAD SE PROTEGE ───────────────────────
-- La misma que la 408. Se repite acá porque es la que la 0568 rompió: si una
-- migración futura agrega un numeral al catálogo y se olvida del rótulo, esto
-- se pone en rojo con el numeral nuevo en el mensaje.
select is((select count(*)::int from faltas_catalogo c
            where not exists (select 1 from faltas_rotulos r
                               where (r.rit_version, r.numeral, r.literal) = (c.rit_version, c.numeral, c.literal))), 0,
  'INVARIANTE · ninguna falta del catálogo queda sin nombre corto, los tres numerales incluidos');

-- ── Y QUE LOS SEIS RESPETEN LO QUE LA 0514 LES EXIGE ────────────────────────
select is((select count(*)::int from faltas_rotulos
            where rit_version = 4.0 and numeral = '53.3'
              and length(btrim(rotulo)) between 3 and 40), 6,
  'FORMATO · los seis caben en el CHECK de 3 a 40 caracteres');
select throws_ok($$ update faltas_rotulos set rotulo = 'Trato descortés' where rit_version = 4.0 and numeral = '53.3' and literal = 'd' $$,
  '23505', null, 'FORMATO · una falta grave tampoco puede tomar el nombre de una significativa');

select * from finish();
rollback;
