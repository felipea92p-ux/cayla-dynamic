-- ============================================================================
-- 0202_un_terminal_activo_sin_dueno_deja_de_poder_existir.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que no pueda existir un terminal ACTIVO sin cuenta vinculada. Ese es el
--   único estado en que el guard de `fn_registrar_marcaje` cae abierto y una
--   sesión cualquiera puede fabricar marcas a nombre de otra persona, en
--   cualquier sede — marcas que la planilla después paga.
--
-- QUÉ ASUME
--   Nada nuevo. Ni una función, ni una pantalla, ni un permiso cambian. Es un
--   CHECK sobre una tabla de 7 columnas.
--
-- ── EL PROBLEMA, MEDIDO ─────────────────────────────────────────────────────
--
-- El único candado que impide que una sesión se haga pasar por un terminal son
-- estas tres condiciones unidas por AND, dentro de `fn_registrar_marcaje`:
--
--     if auth.uid() is not null
--        and v_terminal_auth is not null
--        and auth.uid() <> v_terminal_auth then
--       raise exception 'el terminal autenticado no coincide con p_terminal_id';
--
-- Si `v_terminal_auth` es null la segunda condición es falsa, el AND entero es
-- falso y NO se lanza nada: la sesión pasa. Es la misma familia del `if not X`
-- que la 0078 vino a corregir, escrita al revés — aquí el null no viene del
-- rol, viene de una columna nullable.
--
-- Y el esquema, medido, fabrica ese estado por su cuenta:
--
--     activo        boolean not null DEFAULT TRUE
--     auth_user_id  uuid    NULL, unique, fk → auth.users ON DELETE SET NULL
--
--   · No hay ninguna pantalla que cree terminales: las filas se insertan a mano
--     en el SQL Editor. Un `insert into terminales (sede_id, nombre_dispositivo)`
--     —lo natural— deja la fila ACTIVA y SIN DUEÑO por defecto. La vinculación
--     (`/terminal/vincular`) solo hace signInWithPassword: no escribe esta
--     columna. Entre el alta y la vinculación, la puerta está abierta.
--
--   · Y hay una segunda vía, automática, que el catálogo de hallazgos no
--     nombraba: **ON DELETE SET NULL**. Borrar en Supabase Auth la cuenta de un
--     terminal no desactiva el terminal — le pone el dueño en null y lo deja
--     activo. Nadie se entera, y el guard queda abierto desde ese momento.
--
-- QUIÉN PUEDE APROVECHARLO, medido con has_function_privilege:
--     anon          → NO puede ejecutar la función  (la 0076 se sostiene)
--     authenticated → sí
--     service_role  → sí
--   O sea: cualquier sesión con login. No hace falta ser admin ni encargada.
--
-- ── POR QUÉ EL CANDADO VA EN LA TABLA Y NO EN LA FUNCIÓN ────────────────────
--
-- Es la lección de la 0180, del 2026-08-08: lo que protegió el dinero fue el
-- candado de la BASE, no el de la función. Donde había constraint el agujero no
-- existía; donde solo había una línea dentro de una función, seis funciones de
-- producción la habían perdido sin que nadie lo viera.
--
-- Y aquí cierra el hueco ENTERO, no una parte. Se midió sobre el cuerpo vigente
-- de `fn_registrar_marcaje`: la fila se busca con
--
--     select sede_id, auth_user_id into v_sede_id, v_terminal_auth
--     from terminales where id = p_terminal_id and activo;
--     ...
--       raise exception 'terminal % no encontrado o inactivo', p_terminal_id;
--
-- así que cuando se llega al guard, la fila EXISTE y está ACTIVA. Con este
-- CHECK, para esa fila `auth_user_id` no puede ser null: la segunda condición
-- pasa a ser siempre verdadera y el AND vuelve a decidir por lo que importa,
-- que es si quien llama es el dueño del terminal.
--
-- ── LO QUE NO SE HACE, Y ES DELIBERADO ──────────────────────────────────────
--
-- NO se reescribe `fn_registrar_marcaje` para dejar el guard como
-- `if v_terminal_auth is distinct from auth.uid() then` — que es la forma
-- correcta y la que este repositorio exige por doctrina. Va aparte, y después,
-- por dos razones medidas:
--
--   1. Son 129 líneas, y es la ÚNICA puerta de escritura de marcajes del
--      sistema. El 2026-08-08 se descubrió que 22 funciones de producción no
--      coincidían con el repositorio y que siete tenían código que el
--      repositorio no conoce. Sobrescribirla copiando de la 0082 sin haber
--      pedido antes el cuerpo de producción es exactamente como la 0180 tuvo
--      que reponer lo que otra migración habría borrado en silencio.
--
--   2. Lo que ese cambio agrega, medido, es cubrir el caso `auth.uid() is null`
--      — y con `anon` sin permiso de ejecución, eso hoy solo lo alcanza
--      `service_role`, que es nuestro propio código de servidor. No es la
--      puerta por la que entra un extraño. Este CHECK sí lo es.
--
-- Vale hacerlo igual, como defensa en profundidad, el día que se pida el cuerpo
-- de producción. No vale retrasar por eso el candado que cierra hoy.
--
-- ── UN EFECTO LATERAL QUE SE ELIGIÓ A PROPÓSITO ─────────────────────────────
--
-- Con este CHECK, borrar en Auth la cuenta de un terminal ACTIVO deja de ser
-- silencioso: el ON DELETE SET NULL intentará poner null, el CHECK lo rechazará
-- y el borrado fallará. Hay que desactivar el terminal primero. Es lo correcto
-- —un terminal sin dueño no debería seguir aceptando marcas— y falla ruidoso en
-- vez de abrir la puerta sin avisar.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--     alter table public.terminales drop constraint if exists terminal_activo_con_dueno;
-- ============================================================================

-- ── Antes de poner el candado: ¿hay alguna fila que ya lo incumpla? ─────────
-- Se comprueba y se NIEGA con nombres, en vez de dejar que el ALTER falle con
-- un 23514 que no dice cuál. Y no se desactiva ningún terminal por su cuenta:
-- desactivar uno que esté en uso deja a una sede sin poder marcar, y eso lo
-- decide una persona, no una migración.
do $mig$
declare
  v_lista text;
begin
  select string_agg(t.nombre_dispositivo || ' (sede ' || coalesce(s.codigo, '?') || ')', ', '
                    order by t.nombre_dispositivo)
    into v_lista
  from terminales t
  left join sedes s on s.id = t.sede_id
  where t.activo and t.auth_user_id is null;

  if v_lista is not null then
    raise exception
      'No se puede poner el candado todavía: estos terminales están activos y sin cuenta vinculada → %. '
      'Vincúlales su usuario, o desactívalos si ya no se usan, y vuelve a pegar esta migración. '
      'Mientras estén así, cualquier sesión con login puede marcar a nombre de otra persona en esa sede.',
      v_lista;
  end if;
end
$mig$;

-- ── El candado ──────────────────────────────────────────────────────────────
-- Idempotente: se pega a mano, y una mano se equivoca.
alter table public.terminales
  drop constraint if exists terminal_activo_con_dueno;

alter table public.terminales
  add constraint terminal_activo_con_dueno
  check (not activo or auth_user_id is not null);

comment on constraint terminal_activo_con_dueno on public.terminales is
  'Un terminal activo tiene que tener cuenta vinculada. Con auth_user_id en null, el guard de '
  'fn_registrar_marcaje cae abierto (tres condiciones en AND) y cualquier sesión con login puede '
  'registrar marcas a nombre de otra persona. Para dar de alta un terminal sin vincularlo todavía, '
  'créalo con activo = false.';

insert into migraciones_aplicadas (numero, nombre)
values (202, 'un_terminal_activo_sin_dueno_deja_de_poder_existir')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
