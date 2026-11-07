-- ============================================================================
-- 0604 — Las pantallas se enteran al instante: la base avisa cuando cambia la
--        asistencia, los horarios o una persona (tiempo real, lote 1)
-- ============================================================================
--
-- QUÉ PROMETE
--   Cada vez que se CONFIRMA un cambio en una de las 22 tablas de abajo, la
--   base manda un aviso por el canal de tiempo real de Supabase (websocket) al
--   tema que le toca: «asistencia», «horarios» o «personas». Las pantallas
--   suscritas vuelven a leer por sus funciones de siempre en unos 50 ms, en vez
--   de esperar a su reloj de 30 s o 1 min.
--
--   El aviso NO lleva datos: su contenido es `{"tema": "asistencia"}` y nada
--   más (Supabase le agrega un `id`). Ni un nombre, ni un DNI, ni un sueldo, ni
--   la fila que cambió. Lo que la pantalla muestra sale SIEMPRE de la relectura,
--   que pasa por los mismos permisos que ya tiene cada función. El aviso solo
--   dice CUÁNDO leer; QUÉ se lee lo sigue decidiendo la pantalla.
--
-- QUÉ ASUME
--   * Que la base tiene el Realtime de Supabase: `realtime.send` y
--     `realtime.messages`. En producción los crea el servicio de Realtime.
--     En la base de CI (`supabase db start`) y en los bancos locales sin
--     Docker NO existen —el esquema `realtime` está vacío o no está—, así que
--     esta migración se instala igual y los avisos quedan mudos: no falla nada,
--     solo no sale ningún aviso. El SELECT del final dice cuál de los dos
--     casos es. Medido el 2026-11-07 con la imagen supabase/postgres:17.6.1.158.
--   * No reescribe ninguna función: las cuatro son nuevas. Comprobado con
--     `./scripts/donde-vive.sh` el 2026-11-07 en las cuatro: no existían en
--     ninguna migración ni rama. Por eso no hay «md5 de partida».
--
-- ── POR QUÉ ASÍ ──────────────────────────────────────────────────────────────
--   1. AVISO SIN DATOS, Y NO LA FILA POR EL SOCKET («Postgres Changes»). Mandar
--      la fila pondría los sueldos y los DNI a viajar por un segundo canal, con
--      su propio control de permisos, distinto del de las funciones. Además
--      Postgres Changes no ve vistas —el terminal lee `terminal_roster`— y el
--      propio Supabase recomienda Broadcast «por escalabilidad y seguridad».
--   2. UN AVISO POR SENTENCIA, NO POR FILA. Cerrar un periodo que toca 500
--      jornadas da UN aviso, no 500. Medido en local: 500 filas → 1 aviso.
--   3. UN AVISO POR TEMA Y POR TRANSACCIÓN. Un marcaje escribe `marcajes` y su
--      trigger reescribe `jornadas`: es un solo hecho y sale un solo aviso.
--      La marca es `dynamic.tiempo_real_<tema>`, local a la transacción.
--   4. UNA SENTENCIA QUE NO TOCÓ NINGUNA FILA NO AVISA. El cierre automático
--      corre cada 15 min y casi nunca cierra a nadie; sin este filtro, cada
--      pantalla abierta releería cada 15 min por nada. Se mira la tabla de
--      transición (`nuevas` / `viejas`). Postgres no permite un trigger de tres
--      eventos con tablas de transición —«transition tables cannot be specified
--      for triggers with more than one event», medido—, así que van tres
--      triggers por tabla, que crea `fn_tiempo_real_vigilar`.
--   5. LO REVERTIDO NO AVISA. El aviso es una fila en `realtime.messages`: si la
--      transacción se revierte, la fila también, y Realtime nunca la ve.
--   6. CANALES PRIVADOS, Y QUIÉN ESCUCHA LO DICE UNA SOLA FUNCIÓN.
--      `fn_tiempo_real_puede_escuchar(tema)` responde por cada tema; la política
--      de `realtime.messages` solo la llama. Los lotes siguientes (planilla
--      solo para administración y DO, «Lo mío» solo para cada persona)
--      cambian esa función y no tocan la política. Un tema que la función no
--      conoce queda cerrado para todo el mundo.
--      Hoy escuchan los tres temas: administración, Líder DO, líderes de
--      equipo (`supervisor_sede`) y un terminal activo. NO las integrantes: lo
--      suyo es el lote 5. Ojo: `fn_es_admin_o_lider()` es solo admin y Líder
--      DO, NO incluye a las líderes de equipo; por eso no se usa aquí.
--      Las líderes de equipo reciben también los avisos de las otras sedes, a
--      propósito: el aviso no dice de qué sede es ni qué cambió, así que no
--      revela nada, y separar por sede triplicaría los temas sin ganar
--      privacidad.
--   7. NADIE PUEDE MANDAR AVISOS DESDE EL NAVEGADOR. No se crea política de
--      INSERT en `realtime.messages`, y las funciones que envían no se pueden
--      ejecutar desde la API. Si alguien pudiera mandar avisos, podría hacer
--      que todas las pantallas releyeran sin parar.
--
-- ── SI REALTIME FALLA ────────────────────────────────────────────────────────
--   Un marcaje nunca se cae por esto. `realtime.send` atrapa sus propios
--   errores (RAISE WARNING, leído en su código el 2026-11-07), y
--   `fn_tiempo_real_avisar` además atrapa cualquier otro. Con Realtime caído
--   las pantallas se ponen al día al reconectar, al volver a la pestaña y con
--   una relectura de respaldo cada 5 min. Se pierde frescura, nunca un dato.
--
-- ── UNA SOLA PEGADA, CON LOS CANDADOS TOMADOS SIN ESPERA ─────────────────────
--   La convención dice que una migración que altera varias tablas en uso se
--   pega en partes, una tabla por parte, por el deadlock de la 0591. Aquí van
--   22 tablas, y Felipe aprobó el 2026-11-07 una sola pegada que cierra la
--   misma puerta por otro lado: el deadlock necesita a alguien que espera un
--   candado TENIENDO ya otro. El bloque 1b toma los 23 candados con
--   `NOWAIT`. Si uno solo está ocupado, el intento entero se deshace —y con él
--   los candados que ya tenía— y se reintenta a los 0.2 s, hasta 10 s. Esta
--   migración nunca espera con un candado en la mano, así que no puede cerrar
--   un ciclo. El modo es SHARE ROW EXCLUSIVE, que no choca con las lecturas;
--   las escrituras esperan los milisegundos que tarda en crear los triggers.
--   (`realtime.messages` va en ACCESS EXCLUSIVE porque `create policy` lo pide.)
--
-- ── MEDIDO ANTES DE ENTREGARLA (2026-11-07, pila local con Realtime v2.124.2) ─
--   Un aviso cada 1.5 s: 20/20, mediana 38 ms, p95 58 ms. Ráfaga de 50
--   transacciones en 121 ms: 50/50, mediana 45 ms, máximo 64 ms. Costo por
--   escritura: +0.04 ms en la mediana. Canal sin permiso: «Unauthorized».
--
-- ── IDEMPOTENTE · CÓMO SE REVIERTE ───────────────────────────────────────────
--   Se puede volver a pegar: `create or replace` en las funciones,
--   `create or replace trigger` en los triggers y `drop policy if exists`
--   antes de la política. Se revierte con:
--     do $$ declare r record; begin
--       for r in select tgrelid::regclass as t, tgname from pg_trigger
--                where tgname like 'tiempo_real_al_%' loop
--         execute format('drop trigger %I on %s', r.tgname, r.t);
--       end loop; end $$;
--     drop policy if exists tiempo_real_escuchar on realtime.messages;
--     drop function if exists fn_tiempo_real_vigilar(regclass, text);
--     drop function if exists fn_tiempo_real_avisar();
--     drop function if exists fn_tiempo_real_enviar(text);
--     drop function if exists fn_tiempo_real_puede_escuchar(text);
--   Las pantallas siguen funcionando sin avisos: vuelven a su respaldo de 5 min.
-- ============================================================================

set local lock_timeout = '3s';

-- ── 1. Las 22 tablas, en un solo lugar ───────────────────────────────────────
-- El candado, la instalación y la comprobación leen esta misma lista. El cast a
-- `regclass` falla aquí mismo si una tabla no existe, antes de tomar candados.
create temp table tiempo_real_lote1 (tabla regclass primary key, tema text not null) on commit drop;
insert into tiempo_real_lote1 (tabla, tema) values
  -- Asistencia: lo que pasó en el piso, y lo que explica una falta o un reclamo.
  ('public.marcajes', 'asistencia'),
  ('public.jornadas', 'asistencia'),
  ('public.cambios_ubicacion', 'asistencia'),
  ('public.marcas_apartadas', 'asistencia'),
  ('public.ausencias', 'asistencia'),
  ('public.tardanzas_justificadas', 'asistencia'),
  ('public.incidencias_aceptadas', 'asistencia'),
  ('public.revisiones_pedidas', 'asistencia'),
  -- Horarios: lo que se planificó.
  ('public.turnos', 'horarios'),
  ('public.horarios_asignados', 'horarios'),
  ('public.turnos_borradores', 'horarios'),
  ('public.turnos_borrador_dias', 'horarios'),
  ('public.turnos_borrador_notas', 'horarios'),
  ('public.metas_cobertura', 'horarios'),
  ('public.metas_cobertura_periodos', 'horarios'),
  ('public.metas_cobertura_rangos', 'horarios'),
  ('public.puestos_base', 'horarios'),
  ('public.puestos_planificados', 'horarios'),
  ('public.disponibilidades', 'horarios'),
  ('public.disponibilidad_bloques', 'horarios'),
  ('public.feriados', 'horarios'),
  -- Personas: quién está en el equipo (el terminal muestra la lista de su sede).
  ('public.personas', 'personas');

-- ── 1b. Los candados, sin esperar con ninguno en la mano ─────────────────────
do $$
declare
  v_intentos int := 0;
  v_tablas text := (select string_agg(tabla::text, ', ' order by tabla::text) from tiempo_real_lote1);
  v_con_realtime boolean := to_regclass('realtime.messages') is not null;
begin
  loop
    begin
      execute format('lock table %s in share row exclusive mode nowait', v_tablas);
      if v_con_realtime then
        execute 'lock table realtime.messages in access exclusive mode nowait';
      end if;
      exit;
    exception when lock_not_available then
      v_intentos := v_intentos + 1;
      if v_intentos >= 50 then
        raise exception 'No se pudieron tomar los candados en 10 s: hay mucho movimiento en este momento. No se aplicó nada; vuelve a pegarla en un rato.';
      end if;
      perform pg_sleep(0.2);
    end;
  end loop;
end $$;

-- ── 2. Mandar el aviso ───────────────────────────────────────────────────────
-- Solo esta función conoce `realtime.send`. Si no existe (CI, banco local sin
-- Docker), no hace nada: el resto del sistema no tiene por qué saberlo.
create or replace function fn_tiempo_real_enviar(p_tema text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    return;
  end if;
  -- El contenido es SOLO el tema. Nunca la fila: ver el encabezado de la 0604.
  perform realtime.send(jsonb_build_object('tema', p_tema), 'cambio', 'dynamic:' || p_tema, true);
end $$;

comment on function fn_tiempo_real_enviar(text) is
  'Manda el aviso de tiempo real del tema (sin datos) si la base tiene Realtime. Solo la llama fn_tiempo_real_avisar. 0604.';

-- ── 3. El trigger: decide si avisar y cuántas veces ─────────────────────────
-- SECURITY DEFINER porque quien escribe suele ser `authenticated` (una pantalla
-- por la API), que no puede escribir en `realtime.messages` ni ejecutar
-- `fn_tiempo_real_enviar`. No mira `current_user`, así que no cambia lo que
-- ven los guardianes que sí lo miran (0261, 0296, 0342).
create or replace function fn_tiempo_real_avisar()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tema text := tg_argv[0];
  v_hubo boolean;
begin
  -- Una sentencia que no tocó ninguna fila no avisa (el cierre automático cada
  -- 15 min). SQL dinámico porque la misma función sirve a 22 tablas con tablas
  -- de transición distintas, y así no se guarda un plan que mire la de otra.
  if tg_op = 'DELETE' then
    execute 'select exists (select 1 from viejas)' into v_hubo;
  else
    execute 'select exists (select 1 from nuevas)' into v_hubo;
  end if;
  if not v_hubo then
    return null;
  end if;

  -- Un aviso por tema y por transacción: el marcaje que reescribe su jornada
  -- es un solo hecho.
  if current_setting('dynamic.tiempo_real_' || v_tema, true) = '1' then
    return null;
  end if;
  perform set_config('dynamic.tiempo_real_' || v_tema, '1', true);

  perform fn_tiempo_real_enviar(v_tema);
  return null;
exception when others then
  -- Nada de esto puede frenar un marcaje ni un guardado.
  raise warning 'fn_tiempo_real_avisar(%): %', v_tema, sqlerrm;
  return null;
end $$;

comment on function fn_tiempo_real_avisar() is
  'Trigger por sentencia: avisa por tiempo real que cambió el tema de tg_argv[0], una vez por transacción y solo si tocó filas. 0604.';

-- ── 4. Poner a vigilar una tabla ─────────────────────────────────────────────
create or replace function fn_tiempo_real_vigilar(p_tabla regclass, p_tema text)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if p_tema is null or p_tema !~ '^[a-z_]+$' then
    raise exception 'El tema de tiempo real tiene que ser minúsculas y guion bajo: «%»', p_tema;
  end if;
  execute format(
    'create or replace trigger tiempo_real_al_insertar after insert on %s
       referencing new table as nuevas for each statement execute function fn_tiempo_real_avisar(%L)',
    p_tabla, p_tema);
  execute format(
    'create or replace trigger tiempo_real_al_actualizar after update on %s
       referencing new table as nuevas for each statement execute function fn_tiempo_real_avisar(%L)',
    p_tabla, p_tema);
  execute format(
    'create or replace trigger tiempo_real_al_borrar after delete on %s
       referencing old table as viejas for each statement execute function fn_tiempo_real_avisar(%L)',
    p_tabla, p_tema);
end $$;

comment on function fn_tiempo_real_vigilar(regclass, text) is
  'Crea los tres triggers de tiempo real de una tabla (insertar, actualizar, borrar) con su tema. Toda tabla nueva se vigila o se excluye en supabase/tests/491. 0604.';

-- ── 5. Quién puede escuchar cada tema ───────────────────────────────────────
-- La ÚNICA respuesta a «¿esta sesión puede escuchar este canal?». La política
-- de abajo solo la llama. Un tema que no está aquí queda cerrado para todos.
create or replace function fn_tiempo_real_puede_escuchar(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when p_topic in ('dynamic:asistencia', 'dynamic:horarios', 'dynamic:personas') then
      -- Los mismos roles que entran al panel (ROLES_CON_PANEL en
      -- packages/shared/src/permisos.ts) y la Mac mini de una sede.
      coalesce(fn_rol_actual() in ('admin', 'lider_do', 'supervisor_sede'), false)
      or fn_sede_actual_terminal() is not null
    else false
  end;
$$;

comment on function fn_tiempo_real_puede_escuchar(text) is
  'Si la sesión actual puede escuchar el canal de tiempo real p_topic. La usa la política tiempo_real_escuchar de realtime.messages. 0604.';

-- ── 6. Permisos ──────────────────────────────────────────────────────────────
-- Nadie manda avisos desde la API: enviar y vigilar solo se usan por dentro.
revoke execute on function fn_tiempo_real_enviar(text) from public, anon, authenticated;
revoke execute on function fn_tiempo_real_avisar() from public, anon, authenticated;
revoke execute on function fn_tiempo_real_vigilar(regclass, text) from public, anon, authenticated;
-- Escuchar sí: Realtime evalúa la política con el rol de quien se conecta.
revoke execute on function fn_tiempo_real_puede_escuchar(text) from public, anon;
grant execute on function fn_tiempo_real_puede_escuchar(text) to authenticated;

-- ── 7. La política de `realtime.messages` (solo si la base tiene Realtime) ───
-- Realtime la evalúa una vez, al unirse al canal, y la guarda mientras dure la
-- conexión. Sin política de INSERT: ver «POR QUÉ ASÍ», punto 7.
do $$
begin
  if to_regclass('realtime.messages') is null then
    return;
  end if;
  execute 'drop policy if exists tiempo_real_escuchar on realtime.messages';
  execute $p$
    create policy tiempo_real_escuchar on realtime.messages
      for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and public.fn_tiempo_real_puede_escuchar(realtime.topic())
      )
  $p$;
end $$;

-- ── 8. Poner a vigilar las 22 ──────────────────────────────────────────────
select fn_tiempo_real_vigilar(tabla, tema) from tiempo_real_lote1 order by tabla::text;

-- ── 9. Comprobación: cada una con sus tres triggers y su tema ───────────────
do $$
declare
  v_faltan text;
begin
  select string_agg(l.tabla::text, ', ') into v_faltan
    from tiempo_real_lote1 l
   where (select count(*) from pg_trigger t
           where t.tgrelid = l.tabla
             and t.tgname in ('tiempo_real_al_insertar', 'tiempo_real_al_actualizar', 'tiempo_real_al_borrar')
             and encode(t.tgargs, 'escape') = l.tema || '\000') <> 3;
  if v_faltan is not null then
    raise exception 'Estas tablas no quedaron con sus tres triggers de tiempo real: %. No se aplicó nada.', v_faltan;
  end if;
end $$;

insert into migraciones_aplicadas (numero, nombre)
values (604, 'las_pantallas_se_enteran_al_instante')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- Lo que se ve en el SQL Editor al terminar.
select case
  when to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null
    or to_regclass('realtime.messages') is null
  then 'ATENCIÓN: instalada, pero esta base no tiene el Realtime de Supabase (falta realtime.send o realtime.messages). No saldrá ningún aviso: las pantallas se pondrán al día cada 5 min.'
  else 'Lista: 22 tablas avisan al instante a asistencia, horarios y personas.'
end as resultado;
