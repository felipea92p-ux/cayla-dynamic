-- ============================================================================
-- 0345 — El comentario de `topes_educacion_rango` deja de mentir
-- ============================================================================
--
-- QUÉ PROMETE
--   Corregir el comentario de la tabla `topes_educacion_rango` (0132), que
--   describe una duplicación que ya no existe. No toca ninguna columna, ningún
--   dato ni ningún cálculo — solo el texto que Postgres guarda como
--   documentación de la tabla.
--
-- QUÉ ASUME
--   Que `apps/web/lib/rangos.ts` no tiene, y no debe volver a tener, ningún
--   campo de tope de educación. Así es hoy: el campo `topeEducacion` que la
--   0132 describía como «espejo» se borró el 2026-08-06 junto con el arreglo
--   de la 0178 («caylo» ya no podía asignarse), precisamente porque esa copia
--   había quedado desactualizada y pagó de más. `rangos.ts` documenta esa
--   decisión en su propio comentario («POR QUÉ ACÁ NO ESTÁ EL TECHO DE
--   EDUCACIÓN») desde entonces.
--
-- EL DEFECTO, ENCONTRADO AL ESTUDIAR OTROS ERP
--   La comparación de arquitectura contra Workday/Oracle
--   (`docs/comparacion-workday-oracle-dynamic-2026-09-02.md`, sección 7) reportó
--   como hallazgo que «el mismo dato vive en la tabla Y en un archivo
--   TypeScript hardcodeado a la vez» — citando textualmente este comentario
--   («Espejo de RANGOS.topeEducacion en apps/web/lib/rangos.ts»). Es un falso
--   positivo: el campo que el comentario nombra no existe desde hace un mes.
--   El comentario no describe el código — describe un estado de hace un mes
--   que el código ya dejó atrás, y ya indujo a error a quien lo leyó sin mirar
--   `rangos.ts`. Se corrige para que no vuelva a pasar.
--
-- POR QUÉ UN COMENTARIO Y NO SE IGNORA
--   Este repo declara explícitamente que las migraciones son documentación del
--   negocio (`CLAUDE.md`), y ese estándar incluye los comentarios que quedan
--   grabados en el propio esquema — se leen en el SQL Editor y en cualquier
--   inventario del esquema, con o sin este repo delante.
--
-- SE PUEDE PEGAR SIN MOVER NINGÚN PAGO. Solo reemplaza un `comment on table`;
-- no crea, altera ni borra ninguna columna, fila, función ni trigger.
--
-- IDEMPOTENTE. `comment on table` fija el comentario al valor dado; pegarla
-- dos veces deja el mismo texto.
--
-- CÓMO SE REVIERTE
--   comment on table topes_educacion_rango is
--     'Techo mensual de la asignación por educación de cada rango. NO es un monto a pagar: '
--     'cada persona cobra el 75% de lo que sostiene su comprobante (0120) y nunca más que '
--     'este techo. Espejo de RANGOS.topeEducacion en apps/web/lib/rangos.ts.';
--   delete from migraciones_aplicadas where numero = 345;
-- ============================================================================

comment on table topes_educacion_rango is
  'Techo mensual de la asignación por educación de cada rango. NO es un monto a pagar: '
  'cada persona cobra el 75% de lo que sostiene su comprobante (0120) y nunca más que '
  'este techo. Única fuente: no hay copia en el código. `apps/web/lib/rangos.ts` no '
  'declara ningún tope de educación a propósito desde 2026-08-06 (ver la 0178) — '
  'ese campo pagó de más por quedar desactualizado, y se borró en vez de sincronizarse.';

insert into migraciones_aplicadas (numero, nombre)
values (345, '0345_el_comentario_del_techo_de_educacion_deja_de_mentir')
on conflict (numero) do nothing;
