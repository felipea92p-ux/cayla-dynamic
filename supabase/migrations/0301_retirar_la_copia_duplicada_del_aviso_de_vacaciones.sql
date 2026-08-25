-- ============================================================================
-- 0301_retirar_la_copia_duplicada_del_aviso_de_vacaciones.sql
-- ============================================================================
-- QUÉ PROMETE
--   Dejar UNA sola `fn_vacaciones_por_vencer`. Hoy hay dos, y por eso la
--   pantalla de Ausencias no puede llamarla.
--
-- ── QUÉ PASÓ, SIN ADORNOS ───────────────────────────────────────────────────
--
-- La 0299 creó `fn_vacaciones_por_vencer(p_dias_aviso int)`. Dos días antes, la
-- **0297** ya había creado `fn_vacaciones_por_vencer(p_dias int, p_as_of date)`
-- desde otra rama, con su prueba, su banda en Ausencias, su entrada en el menú
-- y en «Lo mío», y sus tipos regenerados.
--
-- O sea: se construyó dos veces la misma función, y la segunda no miró si ya
-- existía. La 0299 se escribió partiendo de `fn_vacaciones_resumen` sin buscar
-- antes si alguien ya había resuelto la pregunta — que es exactamente lo que
-- `./scripts/donde-vive.sh` existe para evitar, y no se corrió.
--
-- ── Y NO ES SOLO REDUNDANCIA: ROMPE LA LLAMADA ──────────────────────────────
--
-- Las dos tienen todos sus argumentos con valor por defecto, así que una
-- llamada sin argumentos —o con un solo entero— encaja en las DOS y Postgres se
-- niega:
--
--     ERROR: function fn_vacaciones_por_vencer() is not unique
--
-- Reproducido en la base. Es el mismo accidente que la 0278 documentó al
-- agregar un parámetro con `create or replace`: no falla al aplicar la
-- migración, falla al ABRIR LA PANTALLA. Con las dos vivas, el aviso de
-- vacaciones no se puede mostrar.
--
-- ── POR QUÉ SOBREVIVE LA DE LA 0297 Y NO LA MÍA ─────────────────────────────
--
-- No es por antigüedad: es que la suya es mejor, y en un punto concreto que la
-- mía tenía MAL.
--
--   1 · VE MÁS GENTE. La suya deja mirar a admin y líder, a cada persona sus
--       propios días, y a una encargada los de su sede. La 0299 era solo para
--       admin y líder.
--   2 · DEVUELVE LA SEDE, que en cuatro sedes no es un adorno.
--   3 · Y SOBRE TODO, tiene esta condición que la 0299 no tenía:
--
--           and ( dias_para_vencer <= p_dias or records_vencidos > 0 )
--
--       con este comentario suyo, que vale la pena copiar entero:
--
--           «El `or` no es un adorno: quien YA tiene un récord vencido puede
--            tener el siguiente a un año de distancia, y con solo el filtro de
--            los 60 días desaparecía de la lista justo la persona más urgente.
--            Se vio en el panel con datos de prueba, no razonándolo.»
--
--       La 0299 filtraba solo por la ventana, así que tenía ese defecto: a
--       quien más urge avisarle, no le avisaba. Lo encontraron ellos mirando la
--       pantalla; yo no lo vi razonando sobre el código.
--
-- ── LO QUE SE HACE ──────────────────────────────────────────────────────────
--
-- Se suelta la firma de la 0299 y se queda la de la 0297. No se toca ninguna
-- otra función. La 0299 permanece en el repositorio con su cabecera: el
-- historial de lo que se aplicó no se reescribe, y su encabezado ya no describe
-- nada vivo — este archivo es su nota al pie.
--
-- QUÉ ASUME
--   Que en producción están las DOS, que es como quedó tras pegar la 0299:
--     fn_vacaciones_por_vencer(p_dias_aviso integer)         132abf3a…  1 850
--     fn_vacaciones_por_vencer(p_dias int, p_as_of date)     0f4ea1c9…  1 605
--   Si solo está la segunda, este `drop` no hace nada y no pasa nada: es
--   idempotente a propósito.
--
-- CÓMO SE REVIERTE
--   No se revierte. Volver a crear la firma de la 0299 devuelve la ambigüedad y
--   la pantalla deja de funcionar otra vez.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   select proname, pg_get_function_identity_arguments(oid)
--     from pg_proc where proname = 'fn_vacaciones_por_vencer';
--   Tiene que devolver UNA fila, con «p_dias integer, p_as_of date».
-- ============================================================================

drop function if exists fn_vacaciones_por_vencer(int);

do $$
declare v_n int;
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_vacaciones_por_vencer';

  if v_n = 1 then
    raise notice '0301 · OK · queda una sola fn_vacaciones_por_vencer. La pantalla puede llamarla.';
  else
    raise notice '0301 · ATENCION · quedan % funciones con ese nombre. Con mas de una, la llamada sin argumentos es ambigua y el aviso de vacaciones no se muestra.', v_n;
  end if;
end $$;

insert into migraciones_aplicadas (numero, nombre)
values (301, 'retirar_la_copia_duplicada_del_aviso_de_vacaciones')
on conflict (numero) do nothing;
