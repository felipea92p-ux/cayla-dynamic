-- ============================================================================
-- 0469_la_colision_de_la_0465_se_limpia.sql
-- ============================================================================
--
-- QUÉ PROMETE
--   Deja producción consistente con LO QUE EL REPOSITORIO DICE que es la 0465
--   (`el_practicante_devenga_su_descanso_y_su_subvencion_semestral`), después
--   de que dos sesiones distintas reclamaran ese mismo número el mismo día,
--   sin saber una de la otra, para la MISMA idea de negocio (Ley 28518:
--   descanso de 15 días + subvención semestral de un practicante).
--
-- EL DEFECTO, MEDIDO CONTRA PRODUCCIÓN (2026-09-15, proyecto
-- vovjyyiafkxteijimpuy)
--   Felipe no estaba seguro de qué había llegado a pegar de la otra rama
--   (`claude/practicantes-subvencion-semestral`, renumerada después a 0466 y
--   luego a 0467 al toparse con la misma colisión). Esta consulta lo reveló:
--
--     select
--       (select nombre from migraciones_aplicadas where numero = 465),
--       (select pg_get_constraintdef(oid) from pg_constraint
--          where conname = 'desembolsos_beneficios_ventana_check'),
--       exists(select 1 from pg_proc where proname = 'fn_subvenciones_practicante'),
--       exists(select 1 from pg_proc where proname = 'fn_practicante_ya_depositado');
--
--   → nombre_465 = 'el_practicante_devenga_su_descanso_y_su_subvencion_semestral' (la mía)
--   → check_actual = ventana IN (grati_s1, grati_s2, cts_may, cts_nov, vacaciones,
--                                 subvencion_semestral, descanso_practicante)  (la SUYA)
--   → existe fn_subvenciones_practicante = true   (la SUYA)
--   → existe fn_practicante_ya_depositado = true  (la mía)
--
--   Es decir: se pegaron pedazos de las DOS migraciones, en algún orden que ya
--   no se puede reconstruir con certeza. `fn_provisiones` quedó con MI cuerpo
--   (la otra rama declaró explícitamente que no la toca — ver su propio
--   encabezado, "POR QUÉ UNA FUNCIÓN NUEVA Y NO UNA COLUMNA EN fn_provisiones"),
--   así que ese lado está bien. Lo que quedó mal:
--
--     1. El CHECK de `desembolsos_beneficios.ventana` perdió mi valor
--        `subvencion_practicante` — lo pisó el `drop constraint` + `add
--        constraint` de la otra migración, que declara `subvencion_semestral`
--        en su lugar. Hoy, un `insert` con `ventana = 'subvencion_practicante'`
--        (lo que hace mi `fn_practicante_ya_depositado` al LEER, y lo que
--        alguien tendría que anotar para registrar un pago real) fallaría el
--        CHECK — no porque el dato esté mal, sino porque el candado no lo
--        conoce ya.
--     2. `fn_subvenciones_practicante` quedó viva y sin usar: es la otra
--        forma de calcular EL MISMO devengo (día a día en vez de por
--        semestre-mes, y con nombres de campo distintos), sin nada que la
--        llame. Dejarla es la MISMA ambigüedad que causó el accidente de la
--        0297/0299 — dos puertas para la misma pregunta, esperando a que
--        alguien la abra sin saber que hay otra.
--
-- QUÉ ASUME
--   Decidido con Felipe el 2026-09-15: se conserva la implementación de la
--   0465 (dentro de `fn_provisiones`, ya viva, ya auditada con 34 pruebas
--   pgTAP) y se retira la de la otra rama. El PR #408
--   (`claude/practicantes-subvencion-semestral`) se cierra sin fusionar; su
--   código de pantalla nunca llegó a desplegarse (no se fusionó a `main`), así
--   que no hay nada de frontend que limpiar — solo estos dos residuos de SQL.
--
-- POR QUÉ EL CHECK SE ENSANCHA EN VEZ DE ACHICARSE
--   `subvencion_semestral` se deja en el CHECK, no se retira. Nadie puede
--   confirmar con certeza que ninguna fila real se haya anotado ya con ese
--   nombre en el rato en que las dos convivieron (aunque no se conoce ninguna
--   a esta hora), y restringir un CHECK sin haber comprobado eso primero es
--   exactamente el error que este archivo de reglas pide no cometer. El
--   candado queda con los OCHO valores — los cinco de siempre, más los TRES
--   nombres de modalidad formativa que las dos ramas llegaron a declarar
--   (`descanso_practicante`, que coincide en las dos; `subvencion_practicante`,
--   el mío; `subvencion_semestral`, el de la otra, que queda en desuso pero no
--   se cierra la puerta).
--
-- QUÉ COMPROBAR ANTES DE PEGAR
--   select count(*) from desembolsos_beneficios
--    where ventana in ('subvencion_semestral','descanso_practicante','subvencion_practicante');
--   → si da 0 (lo esperado: nadie ha registrado un pago de ninguno de los dos
--   beneficios todavía), sigue. Si da más de 0, PARA y revisa esas filas antes
--   de continuar — no las toca esta migración, pero conviene saber qué hay.
--
-- CÓMO SE REVIERTE
--   No hay vuelta atrás limpia para `fn_subvenciones_practicante`: si hiciera
--   falta, su cuerpo vive en la rama `claude/practicantes-subvencion-semestral`
--   (archivo `0467_la_practicante_devenga_su_media_subvencion.sql` a esta
--   fecha). El CHECK se puede volver a los cinco valores originales con
--   `drop constraint` + `add constraint` — pero solo si antes se confirmó,
--   con la consulta de arriba, que ninguna fila usa los tres nuevos.
-- ============================================================================

-- ── 1 · El CHECK vuelve a admitir mi ventana, sin cerrarle la puerta a la otra
alter table desembolsos_beneficios
  drop constraint if exists desembolsos_beneficios_ventana_check;

alter table desembolsos_beneficios
  add constraint desembolsos_beneficios_ventana_check
  check (ventana = any (array[
    'grati_s1', 'grati_s2', 'cts_may', 'cts_nov', 'vacaciones',
    -- CAMBIO 0469 · los tres nombres que las dos migraciones paralelas de la
    -- 0465 llegaron a declarar (ver encabezado). 'subvencion_semestral' no lo
    -- usa ningún código vigente hoy; se deja por si ya hay una fila con ese
    -- nombre en el libro, no por decisión de mantenerlo activo.
    'descanso_practicante', 'subvencion_practicante', 'subvencion_semestral'
  ]));

comment on column desembolsos_beneficios.ventana is
  'Las cinco ventanas del año laboral peruano (grati_s1/s2, cts_may/nov, vacaciones) '
  'mas los dos beneficios propios de un practicante bajo la Ley 28518 (0465): '
  'descanso_practicante y subvencion_practicante. "subvencion_semestral" queda '
  'admitida por una colision de numeracion con otra rama (0469) pero no la usa '
  'ningun codigo vigente: no anotar pagos nuevos con ese nombre.';

-- ── 2 · La función huérfana del PR que no se fusiona ────────────────────────
-- No calcula nada que `fn_provisiones` (0465) no calcule ya, y nada la llama:
-- dejarla es la ambigüedad que costó la 0297/0299 (dos funciones para la
-- misma pregunta, ninguna sabe de la otra). El `if exists` la vuelve
-- inofensiva si esta migración se pega en una base donde nunca existió.
drop function if exists fn_subvenciones_practicante(date);

insert into migraciones_aplicadas (numero, nombre) values
  (469, 'la_colision_de_la_0465_se_limpia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select pg_get_constraintdef(oid) as check_final
  from pg_constraint where conname = 'desembolsos_beneficios_ventana_check';

select
  (select count(*) from pg_proc where proname = 'fn_subvenciones_practicante') as debe_ser_cero,
  (select count(*) from pg_proc where proname = 'fn_practicante_ya_depositado') as debe_ser_uno,
  (select nombre from migraciones_aplicadas where numero = 465) as nombre_465_sigue_siendo_la_mia;
