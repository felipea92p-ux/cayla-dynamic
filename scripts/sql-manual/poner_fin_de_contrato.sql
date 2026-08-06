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
-- ⚠️ YA NO ES LA VÍA NORMAL (2026-08-06). La ficha de la persona en
-- **Equipo → Editar** tiene el campo «Último día que trabaja por contrato», y ahí
-- se pone, se cambia y se borra. Además avisa de la consecuencia antes de
-- guardar, valida contra la fecha de ingreso en español, y deja el motivo en
-- `correcciones_auditoria` — nada de eso pasa cuando se escribe por acá.
--
-- Este archivo se queda para dos casos y ninguno más:
--   · cargar varias fechas de una sentada, sin abrir la pantalla 20 veces;
--   · diagnosticar en producción, que es donde no hay pantalla que valga.
--
-- Si escribes por acá, hazlo con `fn_set_fin_contrato(persona, fecha, motivo)` y
-- no con un `update` a pelo: la función es la que audita quién cambió qué. El
-- `update` de abajo se conserva porque sirve cuando la sesión del SQL Editor no
-- tiene persona asociada y la función se niega —con razón— a escribir sin saber
-- a quién anotarle el cambio.
--
-- POR QUÉ ESTE ARCHIVO EXISTIÓ. Porque la 0144 agregó la columna, la pantalla de
-- Documentación la leía, y NADIE la escribía: durante dos días la única forma de
-- llenarla fue esta. Un dato que depende de que alguien se acuerde de abrir el
-- SQL Editor termina vacío, y por eso el campo se llevó a la ficha.
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
-- Desde el 2026-08-06 el panel de administración avisa solo: lista a quien vence
-- dentro de 30 días y —lo que importa— a quien YA venció y sigue figurando
-- activa. Si alguien aparece ahí, la decisión es renovar o registrar su salida:
-- mientras figure activa sigue acumulando gratificación, CTS y vacaciones.
--
-- Y no le quita la movilidad de los días que todavía va a trabajar. Si sale del
-- tablero sin haber firmado su declaración, esos días quedan pagados sin el
-- pacto individual que los sostiene — y eso se revisa en su liquidación.
