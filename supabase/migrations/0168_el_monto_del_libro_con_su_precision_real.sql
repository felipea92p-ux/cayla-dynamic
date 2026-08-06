-- ============================================================================
-- 0168 — El monto del libro de desembolsos, con su precisión real
-- ============================================================================
--
-- QUÉ PROMETE
--   `desembolsos_beneficios.monto` es `numeric(12,2)` en todas las bases, igual
--   que en producción.
--
-- EL ERROR, Y ES MÍO
--   La migración 0155 declaró esa columna como `numeric` a secas. Producción la
--   tiene como `numeric(12,2)`. La 0155 dice en su cabecera «su forma EXACTA,
--   leída de information_schema en producción. Ni un tipo adivinado» — y sin
--   embargo adiviné ese.
--
--   Por qué pasó: la consulta con la que leí la forma de la tabla devolvía
--   `data_type`, que para las dos variantes dice lo mismo: «numeric». La
--   precisión vive en otras dos columnas —`numeric_precision` y `numeric_scale`—
--   que no llegaron a mirarse. Un `numeric` sin precisión y un `numeric(12,2)`
--   se ven idénticos hasta que se comparan sus huellas.
--
--   Lo encontró la tercera parte de `comparar_funciones.sql`, escrita esta misma
--   mañana justamente para ver columnas. Era su primer día de trabajo.
--
-- POR QUÉ IMPORTA
--   `numeric` sin precisión guarda todos los decimales que le den; `numeric(12,2)`
--   redondea a dos. En una tabla que registra plata entregada a personas, eso es
--   la diferencia entre S/141,254 y S/141,25. Hoy no hay daño —producción tiene
--   el tipo correcto y el laboratorio no tiene datos— pero una base reconstruida
--   desde el repositorio se comportaría distinto de la real, y ese es exactamente
--   el desfase que el comparador existe para impedir.
--
-- POR QUÉ UNA MIGRACIÓN NUEVA Y NO CORREGIR LA 0155
--   La 0155 ya está aplicada en producción. Reescribirla dejaría el archivo
--   diciendo una cosa y la base recordando que se aplicó otra, que es peor que el
--   error. Se corrige hacia adelante: en producción este `alter` no cambia nada
--   —ya es ese tipo— y en el laboratorio pone la columna donde debía estar.
--
-- CÓMO SE REVIERTE
--   alter table desembolsos_beneficios alter column monto type numeric;
--   Sin pérdida de datos: se amplía la precisión, no se recorta.
-- ============================================================================

alter table desembolsos_beneficios
  alter column monto type numeric(12,2);

comment on column desembolsos_beneficios.monto is
  'Monto desembolsado. numeric(12,2) para que redondee a céntimos igual que el '
  'resto del sistema. La 0155 lo declaró sin precisión por leer `data_type`, que '
  'no distingue `numeric` de `numeric(12,2)`; corregido en la 0168.';

insert into migraciones_aplicadas (numero, nombre)
values (168, 'el_monto_del_libro_con_su_precision_real')
on conflict (numero) do nothing;
