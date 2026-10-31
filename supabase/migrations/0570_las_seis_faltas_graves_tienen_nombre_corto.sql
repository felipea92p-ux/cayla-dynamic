-- 0570 · Las seis faltas graves tienen nombre corto
--
-- QUÉ PROMETE
--   Que las seis faltas graves del numeral 53.3 del RIT v4.0 —las que agregó la
--   0568— tengan su nombre corto en `faltas_rotulos`, como ya lo tienen las
--   veinte de los numerales 53.1 y 53.2.
--
-- QUÉ NO HACE
--   No toca `faltas_catalogo`: las seis filas ya están ahí y su texto es el del
--   Reglamento. No cambia ninguna función. No abre el cubo `graves` de
--   `faltasElegibles` en el panel —eso es código, no esquema— así que el nivel
--   `imputacion` que la 0568 habilitó en la base sigue sin puerta en la
--   interfaz. Queda dicho en `docs/estado.md`.
--
-- QUÉ ASUME
--   Que la 0514 creó `faltas_rotulos` con su PK (rit_version, numeral, literal),
--   su FK a `faltas_catalogo` —por eso las filas del catálogo tienen que existir
--   antes, y existen desde la 0568—, su CHECK de 3 a 40 caracteres y su unique
--   `uq_rotulo_por_version`. Los seis nombres se midieron contra las tres: 19 a
--   31 caracteres, distintos entre sí y distintos de los veinte que ya están.
--
-- POR QUÉ ASÍ
--   Porque la 0568 dejó un agujero que ninguna de sus propias pruebas veía: la
--   0514 había decidido que se nombran TODAS las faltas, incluso las que nadie
--   elige a mano —«para cuando aparecen en el panel de un caso»—, y esa decisión
--   vive en una aserción de otra prueba, la 408. La 0568 metió seis filas al
--   catálogo sin su insert hermano en `faltas_rotulos`, así que hoy, EN
--   PRODUCCIÓN, seis faltas graves no tienen nombre. Nada revienta y nada sale
--   en blanco: los tres lectores degradan solos, y eso es justamente lo que lo
--   hizo pasar inadvertido. Lo que se pierde es el nombre de la acusación en la
--   cabecera del documento (`panel-caso.tsx`) y en la bandeja de DO
--   (`bandeja-fuentes.ts`), o sea en el papel más grave que existe: la
--   imputación de cargos. Quien revisa la bandeja ve «53.3 a)» y ya no lee de
--   qué se acusa a alguien sin abrir el caso.
--
--   Los nombres salen del texto del literal, no de una paráfrasis, y cada uno se
--   eligió para NO confundirse con su hermano menos grave, que es el error que
--   de verdad costaría caro en un expediente:
--     a) «Marcó por otra o falseó datos» — no «Olvidó marcar» (53.1 a), que es leve).
--     b) «Apropiación de bienes o dinero» — no «Caja o inventario» (53.2 g): el
--        literal dice expresamente que el faltante SIN apropiación acreditada se
--        queda en el 53.2 g).
--     c) «Entregó información reservada» — no «Divulgó información» (53.2 i).
--     d) «Agresión o grave indisciplina» — no «Trato descortés» (53.2 h).
--     e) «Abandono, ausencias o tardanzas» — nombra las tres conductas del
--        literal (abandono de más de 3 días, ausencias sobre el umbral,
--        impuntualidad reiterada) sin repetir «Inasistencia injustificada»
--        (53.2 c) ni «Tardanzas reiteradas» (53.2 b).
--     f) «Hostigamiento sexual» — se nombra igual aunque no vaya por un memo:
--        tiene procedimiento propio (arts. 47 a 51 de la Ley 27942), y el rótulo
--        sirve para cuando el caso aparece en un panel.
--
--   Va con `do update` y no con `do nothing`, igual que la 0514: un rótulo SÍ se
--   corrige —es un nombre de pantalla, no un hecho del expediente—, mientras el
--   catálogo va con `do nothing` porque su texto es el del Reglamento.
--
-- CÓMO SE REVIERTE
--   delete from faltas_rotulos where rit_version = 4.0 and numeral = '53.3';
--   La pantalla vuelve a mostrar «53.3 a)» en vez del nombre. Nada más se rompe.

insert into faltas_rotulos (rit_version, numeral, literal, rotulo) values
  (4.0, '53.3', 'a', 'Marcó por otra o falseó datos'),
  (4.0, '53.3', 'b', 'Apropiación de bienes o dinero'),
  (4.0, '53.3', 'c', 'Entregó información reservada'),
  (4.0, '53.3', 'd', 'Agresión o grave indisciplina'),
  (4.0, '53.3', 'e', 'Abandono, ausencias o tardanzas'),
  (4.0, '53.3', 'f', 'Hostigamiento sexual')
on conflict (rit_version, numeral, literal) do update set rotulo = excluded.rotulo;

insert into migraciones_aplicadas (numero, nombre) values (570, 'las_seis_faltas_graves_tienen_nombre_corto')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
