-- ============================================================================
-- 0241_el_terminal_ve_el_dia_entero_de_quien_puede_marcar.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que un terminal vea las marcas de HOY de TODA la gente que lista en su
--   pantalla, aunque esas marcas se hayan hecho en otra sede. Hoy solo ve las de
--   su propia sede, y a quien viaja entre sedes eso le hace PERDER marcas.
--
-- QUÉ ASUME
--   Nada nuevo. Ni una función de negocio, ni una pantalla, ni un cálculo
--   cambian. Es una policy de lectura sobre `marcajes`.
--
-- ── EL PROBLEMA, REPRODUCIDO CONTRA EL POSTGRES LOCAL ───────────────────────
--
-- Dos reglas dicen cosas distintas sobre la misma persona:
--
--   personas_select_terminal_roster (0008)
--     ... and (sede_base_id = fn_sede_actual_terminal() or visible_todas_sedes)
--   marcajes_select_terminal (0003)
--     using (sede_id = fn_sede_actual_terminal())
--
-- O sea: el roster incluye a quien viaja entre sedes —el flag `visible_todas_sedes`
-- de la 0008 existe justo para eso—, pero sus MARCAS solo se ven si se hicieron
-- en la sede de ese terminal. Medido, con una persona de TRU con el flag puesto
-- que marcó su entrada en TRU y después se paró frente al terminal de AQP:
--
--     AQP ve en su roster    → 1     (la ofrece para marcar)
--     AQP ve de sus marcas   → 0     (cree que no ha marcado nada hoy)
--     lo que espera el SERVIDOR → null = «elige un tipo de SALIDA»
--
-- El terminal decide qué ofrecer en el navegador (`determinarSiguienteAccion`,
-- packages/shared) con las marcas que puede LEER. Con cero marcas ofrece
-- «Entrada». Y `fn_registrar_marcaje`, que cuenta el día ENTERO sin mirar sede,
-- la rechaza — reproducido literal:
--
--     tipo entrada no válido: la jornada ya está cerrada o requiere elegir un
--     tipo de salida
--
-- Y ahí es donde se pierde el dato. El rechazo es PERMANENTE: la cola offline
-- reintenta seis veces, el servidor contesta lo mismo las seis, y la marca se
-- APARTA (sync.ts). Queda guardada en el IndexedDB de esa Mac, que no lee
-- ninguna pantalla del panel, y el terminal solo puede decir «no quedó
-- registrada, avisa a tu encargada». Es asistencia real de una persona real que
-- no llega nunca a la planilla, y depende de que alguien avise a tiempo.
--
-- Este es el hallazgo nº 3 del estado —«el terminal decide en dos sitios a la
-- vez»— pero por una vía que no estaba escrita: las dos copias de la regla no se
-- contradicen entre ellas, se contradicen porque una de las dos está leyendo
-- MENOS DÍA del que hay.
--
-- ── LA REGLA QUE SE ELIGE, Y POR QUÉ ESA ────────────────────────────────────
--
-- «Un terminal lee las marcas de la gente que puede ofrecer para marcar.» Dicho
-- así, la policy de `marcajes` pasa a apoyarse en la MISMA condición que la de
-- `personas`, en vez de repetirla con otras palabras. Las dos no pueden volver a
-- separarse porque ya no son dos.
--
-- Se descartó el arreglo pequeño —añadir `or visible_todas_sedes`— porque tapa
-- una dirección del desajuste y deja la otra: alguien cuya sede base ES la del
-- terminal, con una marca registrada con otra sede (una corrección manual pasa
-- `p_sede_id` a mano), volvería a producir exactamente este mismo día perdido.
--
-- LO QUE SE ESTRECHA, dicho para no esconderlo: deja de ver las marcas de quien
-- NO está en su roster aunque lleven su sede — una persona inactiva, o alguien a
-- quien le cambiaron la sede base. El terminal no las usa: solo mira las de la
-- gente que pinta en pantalla. Y estrechar lo que puede leer un dispositivo que
-- marca SIN PIN, a la vista del público de una tienda, va en la dirección buena.
--
-- ── EL `IS NOT NULL` NO ES DECORATIVO ───────────────────────────────────────
--
-- Sin él, para una sesión que NO es un terminal `fn_sede_actual_terminal()`
-- devuelve null: la comparación de sede da null (no pasa), pero la condición del
-- roster daría TRUE por su cuenta y esta policy le abriría las marcas de media
-- empresa a cualquier sesión con login. Es la misma familia del `if not X` de la
-- 0078 y del terminal sin dueño de la 0202: el null que se cuela por el hueco.
-- La 0008 ya lo escribió así en la policy de `personas`; aquí se copia el freno.
--
-- QUÉ NO SE TOCA
--   `jornadas_select_terminal` tiene el mismo desajuste de sede, y se deja: el
--   terminal no lee `jornadas` en ninguna parte (mirado archivo por archivo en
--   apps/web/lib/terminal). Tocarla sería cambiar un permiso sin un caso que lo
--   pida. El día que el terminal necesite leerlas, esta misma forma sirve.
--
-- CÓMO SE REVIERTE
--     drop policy if exists marcajes_select_terminal on marcajes;
--     create policy marcajes_select_terminal on marcajes
--       for select to authenticated
--       using (sede_id = fn_sede_actual_terminal());
--     drop function if exists fn_persona_en_roster_terminal(uuid);
--   Reabre la pérdida de marcas de quien viaja entre sedes.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final devuelve una fila con dos `true`.
-- ============================================================================

-- ── 1 · La condición del roster, dicha una sola vez ────────────────────────
-- SECURITY DEFINER a propósito, y es el patrón de este repositorio desde la 0005
-- (`fn_sede_actual_terminal`): una policy sobre `marcajes` que consultara
-- `personas` en crudo arrastraría las policies de `personas` dentro de la
-- evaluación. Acá la respuesta tiene que ser la del roster, no la de quien mira.
--
-- STABLE, no VOLATILE: se evalúa por fila y el planificador necesita poder
-- reutilizarla dentro de la misma consulta.
create or replace function fn_persona_en_roster_terminal(p_persona_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from personas p
    where p.id = p_persona_id
      and p.estado = 'activo'
      and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true)
  );
$$;

comment on function fn_persona_en_roster_terminal(uuid) is
  'Si esta persona aparece en el roster del terminal autenticado. Es la MISMA condición de '
  'personas_select_terminal_roster (0008), dicha una sola vez para que la lectura de marcajes '
  'no pueda volver a decir algo distinto. Desde la 0241.';

revoke execute on function fn_persona_en_roster_terminal(uuid) from public;
grant execute on function fn_persona_en_roster_terminal(uuid) to authenticated, service_role;

-- ── 2 · El terminal ve el día entero de quien puede ofrecer ────────────────
-- Idempotente: se pega a mano, y una mano se equivoca.
drop policy if exists marcajes_select_terminal on marcajes;

create policy marcajes_select_terminal on marcajes
  for select to authenticated
  using (
    -- Primero el freno, y en este orden: es una función sin argumentos y stable,
    -- así que para una sesión que no es terminal se resuelve una vez y corta.
    fn_sede_actual_terminal() is not null
    and fn_persona_en_roster_terminal(persona_id)
  );

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (241, 'el_terminal_ve_el_dia_entero_de_quien_puede_marcar')
on conflict (numero) do nothing;


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) = 1 from pg_proc
    where proname = 'fn_persona_en_roster_terminal')
    as existe_la_funcion,
  (select pg_get_expr(polqual, polrelid) like '%fn_persona_en_roster_terminal%'
     from pg_policy where polname = 'marcajes_select_terminal')
    as la_policy_usa_el_roster;
