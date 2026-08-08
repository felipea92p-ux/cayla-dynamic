-- ============================================================================
-- 0184_las_dos_puertas_de_horario_que_nadie_usa_se_cierran.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que `fn_set_horario` y `fn_quitar_horario` dejen de existir. Nadie podrá
--   cambiar el horario de una persona por una vía que no deje rastro.
--
-- QUÉ ASUME
--   Que nadie las usa. No es una impresión: se comprobó por tres caminos
--   distintos el 2026-08-08, y los tres tienen que dar cero.
--     · ninguna pantalla ni módulo las llama
--       (`grep -rn "fn_set_horario\b\|fn_quitar_horario" apps/ packages/` solo
--        las encuentra en `packages/database/src/types.ts`, que es generado);
--     · ninguna otra función de la base las invoca en su cuerpo;
--     · ningún trigger las tiene como manejador.
--   La pantalla de Turnos y la de Horarios usan `fn_set_horario_semanal`, que se
--   queda y que sí lleva el candado de periodo pagado.
--
-- ── POR QUÉ SE BORRAN Y NO SE PARCHEAN ──────────────────────────────────────
--
-- Son la versión anterior de un editor de horarios que ya se reemplazó, y que
-- nadie desconectó. Que no tengan botón no significa que no se puedan usar:
-- PostgREST publica cada función de `public` como una dirección propia, así que
-- cualquier sesión válida —una encargada de sede, el usuario del terminal de una
-- tienda— puede llamarlas directamente sin pasar por ninguna pantalla. Las dos
-- siguen con `grant execute … to authenticated`.
--
-- Y no hace falta ser administradora: las dos autorizan con
-- `fn_verificar_corrector`, que le da permiso a una encargada sobre cualquier
-- persona de su sede.
--
-- Parchearlas —copiarles el candado y hacerlas escribir en
-- `correcciones_auditoria`— dejaría dos copias de una regla que ya vive en
-- `fn_set_horario_semanal`. Dos formas de hacer lo mismo es exactamente el
-- defecto que este repositorio persigue: la próxima corrección se aplicaría a
-- una y no a la otra. Código que no existe no se puede llamar, no se mantiene y
-- no se explica.
--
-- ── QUÉ SE ROMPÍA, MEDIDO — Y QUÉ NO, TAMBIÉN MEDIDO ────────────────────────
--
-- El catálogo de hallazgos decía que estas dos «reescriben las tardanzas de un
-- mes YA PAGADO». Se reprodujo el caso entero antes de creerlo, y esa mitad es
-- FALSA hoy: junio pagado, una persona con 45 minutos de tardanza el día 16, la
-- llamada hecha por una encargada. `fn_quitar_horario` pasa —no tiene candado,
-- eso sí es cierto— y la tardanza se queda en 45. Lo frena un piso más abajo:
-- `fn_recalcular_jornada` lleva su propio candado desde la 0138, que entró el
-- 04/08 a las 17:40, unas horas después de que se escribiera el hallazgo.
--
-- Lo que SÍ se reprodujo, con el periodo ABIERTO: la misma llamada deja la
-- tardanza en NULL y `correcciones_auditoria` en cero. Y quedarse sin horario no
-- es cosmético — `fn_faltas` y `fn_faltas_resumen` exigen horario, así que esa
-- persona desaparece del motor de faltas. En el periodo que está por pagarse,
-- eso sí ocurre.
--
-- Ese, y no el otro, es el motivo de esta migración.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Sus cuerpos siguen en git, donde se definieron por última vez:
--     git show HEAD:supabase/migrations/0015_horario_base_dias_refrigerio.sql  → fn_set_horario
--     git show HEAD:supabase/migrations/0011_editor_horarios.sql               → fn_quitar_horario
--   Volver a crearlas es una decisión de negocio, no un copiar y pegar: si algún
--   día hace falta editar un horario por fuera de la pantalla, lo que
--   corresponde es exponer `fn_set_horario_semanal`, que ya lleva candado.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final debe decir 0 y «ninguna».
-- ============================================================================

drop function if exists public.fn_set_horario(
  p_persona_id uuid,
  p_hora_entrada time without time zone,
  p_hora_salida time without time zone,
  p_vigente_desde date,
  p_almuerzo_min integer,
  p_almuerzo_max integer,
  p_dias_laborables integer[]
);

drop function if exists public.fn_quitar_horario(
  p_persona_id uuid,
  p_desde date
);

-- ── El registro, y que la API recargue el esquema ───────────────────────────
-- El `notify` importa más que de costumbre aquí: sin él PostgREST seguiría
-- anunciando en su esquema dos funciones que ya no existen.
insert into migraciones_aplicadas (numero, nombre)
values (184, 'las_dos_puertas_de_horario_que_nadie_usa_se_cierran')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra el resultado de la
-- última consulta. Debe decir 0 y «ninguna».
--
-- Se pregunta por las dos a la vez y por su nombre exacto: `fn_set_horario`
-- lleva el prefijo de `fn_set_horario_semanal`, que se queda y no debe aparecer.
select count(*) as puertas_que_quedan,
       coalesce(string_agg(p.proname, ' ' order by p.proname), 'ninguna') as cuales
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('fn_set_horario', 'fn_quitar_horario');
