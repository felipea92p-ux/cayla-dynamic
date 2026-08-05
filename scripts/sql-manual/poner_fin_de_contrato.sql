-- ============================================================================
-- PARA PEGAR EN EL SQL EDITOR — anotar cuándo termina el contrato de alguien
-- ============================================================================
-- PARA QUÉ SIRVE. `personas.fecha_fin_contrato` (0144) es lo que el sistema usa
-- para saber que alguien se va. Hoy decide dos cosas:
--
--   · en Documentación, quién viene desmarcado del reparto de la política;
--   · desde la 0162, a quién deja de pedirle su declaración de ruta el tablero
--     —solo cuando el contrato vence este mes o antes, no cuando falta medio año.
--
-- POR QUÉ ESTE ARCHIVO EXISTE. Porque la columna NO SE PUEDE EDITAR DESDE
-- NINGUNA PANTALLA. La 0144 la agregó, la pantalla de Documentación la lee, y
-- nadie la escribe: hoy la única forma de llenarla es esta. Está anotado como
-- pendiente — mientras siga así, el dato depende de que alguien se acuerde de
-- venir acá, y un dato que depende de la memoria de una persona termina vacío.
--
-- NO LLEVA NOMBRES A PROPÓSITO. Este archivo vive en git; los nombres, DNI y
-- fechas del equipo no. Rellena los dos valores de abajo en el SQL Editor y no
-- guardes el resultado en el repositorio.
--
-- CÓMO SE REVIERTE
--   update personas set fecha_fin_contrato = null where id = '<el uuid>';
-- ============================================================================

-- ── 1 · Encontrar a la persona ────────────────────────────────────────────
-- Escribe parte del apellido. Copia el `id` que salga.
select id, nombres, apellidos, estado, tipo_vinculo, fecha_fin_contrato
from personas
where estado = 'activo'
  and (apellidos ilike '%' || 'ESCRIBE_AQUI_EL_APELLIDO' || '%'
    or nombres   ilike '%' || 'ESCRIBE_AQUI_EL_APELLIDO' || '%');


-- ── 2 · Anotar la fecha ───────────────────────────────────────────────────
-- Es el ÚLTIMO DÍA QUE TRABAJA, no el día siguiente. Va dentro de una
-- transacción para poder mirar el resultado antes de confirmarlo.
begin;

update personas
   set fecha_fin_contrato = date 'AAAA-MM-DD'   -- ← el último día que trabaja
 where id = 'PEGA_AQUI_EL_UUID';

-- Comprueba que sea quien crees, y que la fecha sea la que quisiste escribir.
select nombres, apellidos, fecha_ingreso, fecha_fin_contrato
from personas where id = 'PEGA_AQUI_EL_UUID';

-- Si está bien: `commit;`   ·   si no: `rollback;`
-- No dejes la transacción abierta — bloquea la fila para el resto del sistema.
commit;


-- ── 3 · Comprobar que el tablero de Documentación ya no la lista ──────────
-- Solo desaparece si su contrato vence ESTE MES o antes. Con una fecha más
-- lejana sigue apareciendo, y es correcto: hasta ese día cobra movilidad, así
-- que hasta ese día necesita su declaración firmada.
select persona, sede, estado
from fn_documentos_tablero()
order by persona;


-- ── 4 · Ojo con lo que esto NO hace ───────────────────────────────────────
-- No la da de baja. Sigue activa, sigue marcando y sigue cobrando hasta que se
-- registre su cese (`estado = 'inactivo'` + `fecha_cese`), que es otra cosa y va
-- por la pantalla de Equipo.
--
-- Y no le quita la movilidad de los días que todavía va a trabajar. Si sale del
-- tablero sin haber firmado su declaración, esos días quedan pagados sin el
-- pacto individual que los sostiene — y eso se revisa en su liquidación.
