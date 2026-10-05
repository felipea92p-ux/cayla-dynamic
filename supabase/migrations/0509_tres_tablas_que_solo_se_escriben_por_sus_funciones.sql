-- ============================================================================
-- 0509 · TRES TABLAS QUE SOLO SE ESCRIBEN POR SUS FUNCIONES
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `rendimiento_mensual`, `terminales` y `tarifas_hora` no se puedan
--   escribir con la sesión de un usuario. Sigue escribiéndolas quien debe:
--   las funciones guardián (SECURITY DEFINER, dueñas de `postgres`), el SQL
--   Editor y la llave de servicio. La LECTURA no cambia en nada.
--
-- EL DEFECTO, EN UNA LÍNEA
--   Las tres tienen una política `FOR ALL … fn_es_admin_o_lider()` (0003 y
--   siguientes) y el INSERT/UPDATE/DELETE que dio la 0004. Mientras tanto, dos
--   de ellas tienen una función guardián que comprueba cosas que la política
--   no mira. Es la misma forma que cerró la 0507 en `personas`: la puerta de
--   la tabla vale más que la puerta con candado.
--
-- LO QUE SE MIDIÓ (2026-10-04, Postgres desechable con las 484 migraciones de
-- `main`, jwt de un lider_do, todo en `begin … rollback`)
--   1. rendimiento_mensual. `fn_set_rendimiento` en un mes PAGADO →
--      «La planilla de ese mes ya está PAGADA: reabre el periodo para
--      corregir.»; el INSERT directo en el mismo mes → PASA. Las restricciones
--      de la tabla ya cubren lo demás (rango 0–100, mes 1–12, etiqueta y
--      persona existentes): lo ÚNICO que una escritura directa se salta es
--      ese candado. Y no es un dato decorativo: la fila fija el porcentaje del
--      complemento de rendimiento que el núcleo de planilla paga
--      (`fn_planilla_calcular_nucleo`, CAMBIO 0105), y sin fila vale 100.
--      Quitar una fila SUBE el pago; ponerla lo baja.
--   2. terminales. `fn_sede_actual_terminal()` autoriza por una fila de esta
--      tabla (`auth_user_id = auth.uid() and activo`), y de ahí cuelgan las
--      políticas de lectura de marcajes, jornadas, horarios_asignados y turnos
--      del terminal. Un lider_do insertó una terminal atada a SU PROPIA cuenta
--      y con ella registró, por `fn_registrar_marcaje`, la entrada de OTRA
--      persona, con origen `terminal` y sin PIN. La marca quedó escrita y es
--      idéntica a la de un kiosco real. Las puertas oficiales para agregar o
--      corregir una marca (`fn_agregar_marcaje`, `fn_corregir_marcaje`,
--      `fn_anular_marcaje`…) dejan rastro en `correcciones_auditoria` con
--      motivo; esta ruta no deja ninguno.
--   3. tarifas_hora. Nada la lee (ni funciones, ni vistas, ni la app) y tiene
--      0 filas: tabla sin uso con la puerta abierta. Sin consecuencia hoy; se
--      cierra por consistencia y para que el día que alguien la use nazca
--      cerrada.
--
-- QUIÉN ESCRIBE HOY CON SESIÓN DE USUARIO (medido; si alguno existiera, esta
-- migración NO se escribe así)
--   · apps/web: ninguna de las tres. `terminales` solo se LEE
--     (lib/terminal/terminal-info.ts, con la política `terminales_select_propio`);
--     `rendimiento_mensual` y `tarifas_hora` no aparecen. Ninguna pantalla llama
--     a `fn_set_rendimiento` ni a `fn_quitar_rendimiento`.
--   · scripts/: setup-terminales-prod.mjs, seed-dev.mjs (terminales y
--     tarifas_hora) escriben con la llave de servicio. El privilegio de
--     `service_role` NO se toca.
--   · cayla-retail: ningún archivo ni sentencia SQL escribe en ninguna de las
--     tres (su `retail.terminales` es otra tabla, de otro esquema).
--   · SQL: las únicas funciones que escriben son `fn_set_rendimiento` y
--     `fn_quitar_rendimiento`, ambas SECURITY DEFINER de `postgres`. Nada
--     escribe en `terminales` ni en `tarifas_hora` salvo la migración 0375
--     (corrió como postgres).
--   · Pruebas: en los 309 archivos hay 23 escrituras en estas tablas y todas
--     corren como `postgres` (montajes). Ninguna lo hace como `authenticated`.
--     Y ninguna prueba existente llama a `fn_set_rendimiento` ni a
--     `fn_quitar_rendimiento`: la puerta oficial de `rendimiento_mensual` no
--     tenía ninguna; la 403 la cubre.
--   · `terminales.ultimo_visto_at` no la escribe nadie: solo existe su columna.
--
-- DECIDÍ:    cerrar las tres con el molde de la 0507. Se quitan las políticas de
--            escritura, se revoca INSERT/UPDATE/DELETE a `authenticated`,
--            `anon` y `public`, y SE CONSERVA la lectura exactamente como
--            estaba. En `tarifas_hora` la política `FOR ALL` era también la
--            única de lectura: se repone como SELECT ANTES de quitarla, para
--            que no haya un instante sin lectura.
-- DESCARTÉ:  un trigger `BEFORE INSERT OR UPDATE OR DELETE` con
--            `current_user <> 'postgres'` (el molde de la 0296/0342/0490).
--            Mismo argumento que en la 0507: ese molde existe porque en UPDATE
--            de `personas` no se puede revocar sin dejar sin escribir otras
--            columnas; aquí NADIE legítimo escribe con sesión, así que lo que se
--            puede borrar se borra, y un trigger además frenaría a
--            `service_role` (los scripts de alta de terminales).
--            También descarté meter el candado de mes pagado dentro de la
--            tabla (un trigger sobre `rendimiento_mensual`): duplicaría en dos
--            sitios la regla que ya vive en `fn_mes_planilla_pagado`, y la
--            función guardián ya la aplica.
-- SE ROMPE SI:
--   1. Una pantalla futura escribe `rendimiento_mensual` o `terminales`
--      directo con la sesión del usuario. Dará «permission denied for table …»:
--      lo correcto es una función `SECURITY DEFINER`, no devolver el privilegio.
--      Si alguien lo devuelve, la prueba 403 falla en `db-tests` antes de
--      fusionar (exige las dos cosas: sin política Y sin privilegio).
--   2. Existe en producción una función SECURITY INVOKER, pegada a mano y por
--      tanto fuera del repo, que escribe en una de las tres. La migración lo
--      comprueba al empezar y SE NEGARÁ a correr diciendo cuál es (ver el
--      bloque «0 · Precondición»). La consulta de abajo lo dice antes de pegar.
--   3. El día que alguien necesite dar de alta un kiosco desde una pantalla:
--      hoy no existe esa pantalla (las terminales se crean con
--      setup-terminales-prod.mjs). Cuando exista, que sea una función con su
--      escalafón y su rastro; esta migración no la impide, la exige.
--
-- LO QUE NO TOCA (y por qué)
--   · `configuracion`. Tiene un escritor legítimo directo (`apariencia_tema`,
--     de admin/apariencia) y 3 claves con trigger; las otras 11, incluidas
--     las de plata, quedan abiertas. Qué claves protegen y quién puede
--     cambiar las constantes de planilla es una decisión de política, no de
--     esta migración.
--   · `documentos_tipos`. La pantalla Normas inserta directo: la puerta directa
--     ES la oficial.
--   · Ninguna función se reescribe → no hay md5 de partida.
--   · `terminales_select_propio` (el kiosco se lee a sí mismo),
--     `terminales_select_admin_lider` y `rendimiento_mensual_select`: intactas.
--   · El SELECT de `anon`: se deja como está (sin política, RLS ya lo niega).
--
-- ANTES DE PEGAR — UNA CONSULTA DE SOLO LECTURA A PRODUCCIÓN (SQL Editor).
-- Trae también la fila del registro (lección de la 0507: sin ella, un resultado
-- «antes» y uno «después» se leen igual). Esperado ANTES de pegar:
--   · el registro NO tiene 509;
--   · cada tabla con UNA política de escritura (`*`) y `authenticated` con
--     INSERT/UPDATE/DELETE;
--   · «escriben sin ser definer»: NINGUNA fila (si sale alguna, parar);
--   · las dos funciones guardián, dueño `postgres`, definer.
--
--   select 'registro 505 a 512' as tema,
--          coalesce(string_agg(numero || ' · ' || nombre, '  |  ' order by numero), '(nada)') as dato
--     from migraciones_aplicadas where numero between 505 and 512
--   union all
--   select 'política de ' || c.relname,
--          p.polname || ' [' || p.polcmd::text || ']'
--     from pg_policy p join pg_class c on c.oid = p.polrelid
--    where c.relnamespace = 'public'::regnamespace
--      and c.relname in ('rendimiento_mensual', 'terminales', 'tarifas_hora')
--   union all
--   select 'authenticated en ' || c.relname,
--          'INSERT=' || has_table_privilege('authenticated', c.oid, 'INSERT')::text
--          || ' UPDATE=' || has_table_privilege('authenticated', c.oid, 'UPDATE')::text
--          || ' DELETE=' || has_table_privilege('authenticated', c.oid, 'DELETE')::text
--          || ' SELECT=' || has_table_privilege('authenticated', c.oid, 'SELECT')::text
--     from pg_class c
--    where c.relnamespace = 'public'::regnamespace
--      and c.relname in ('rendimiento_mensual', 'terminales', 'tarifas_hora')
--   union all
--   select 'escriben sin ser definer', p.proname
--     from pg_proc p
--    where p.pronamespace = 'public'::regnamespace and not p.prosecdef
--      and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?"?(rendimiento_mensual|terminales|tarifas_hora)"?\M'
--   union all
--   select 'dueño de ' || p.proname,
--          pg_get_userbyid(p.proowner) || ' definer=' || p.prosecdef::text
--     from pg_proc p
--    where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('fn_set_rendimiento', 'fn_quitar_rendimiento')
--   order by 1, 2;
--
-- CÓMO SE REVIERTE (si algo legítimo apareciera)
--   create policy rendimiento_mensual_write on rendimiento_mensual
--     for all to authenticated using (fn_es_admin_o_lider()) with check (fn_es_admin_o_lider());
--   create policy terminales_write_admin_lider on terminales
--     for all to authenticated using (fn_es_admin_o_lider()) with check (fn_es_admin_o_lider());
--   create policy tarifas_admin_lider on tarifas_hora
--     for all to authenticated using (fn_es_admin_o_lider()) with check (fn_es_admin_o_lider());
--   grant insert, update, delete on rendimiento_mensual, terminales, tarifas_hora to authenticated;
--   Y se retira la prueba 403. Reabrirlo es reabrir los huecos de arriba.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final: todas las columnas deben dar `true`.
-- ============================================================================

-- 0 · Precondición. Si una función que NO corre como su dueño escribe en alguna
--     de las tres, revocar el privilegio la rompería. En vez de romperla en
--     silencio, la migración se niega a correr y dice cuál es. (Mismo patrón
--     que el guardia de terminal_roster en la 0490.)
do $$
declare
  v_funciones text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into v_funciones
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and not p.prosecdef
     and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?"?(rendimiento_mensual|terminales|tarifas_hora)"?\M';
  if v_funciones is not null then
    raise exception 'PARA. Estas funciones escriben en rendimiento_mensual, terminales o tarifas_hora SIN correr como su dueño y dejarían de funcionar: %. Conviértelas en SECURITY DEFINER antes de cerrar la puerta.', v_funciones;
  end if;
end;
$$;

-- 1 · rendimiento_mensual. La lectura (`rendimiento_mensual_select`) ya existe.
drop policy if exists rendimiento_mensual_write on rendimiento_mensual;
revoke insert, update, delete on rendimiento_mensual from public, anon, authenticated;

-- 2 · terminales. La lectura (`terminales_select_admin_lider` y
--     `terminales_select_propio`, esta última la que usa el kiosco) ya existe.
drop policy if exists terminales_write_admin_lider on terminales;
revoke insert, update, delete on terminales from public, anon, authenticated;

-- 3 · tarifas_hora. Su única política era `FOR ALL`, o sea también la lectura:
--     se repone como SELECT primero, y recién entonces se quita la de escritura.
drop policy if exists tarifas_hora_select_admin_lider on tarifas_hora;
create policy tarifas_hora_select_admin_lider on tarifas_hora
  for select to authenticated
  using (fn_es_admin_o_lider());
drop policy if exists tarifas_admin_lider on tarifas_hora;
revoke insert, update, delete on tarifas_hora from public, anon, authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (509, '0509_tres_tablas_que_solo_se_escriben_por_sus_funciones')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACION ────────────────────────────────────────────────────────────
-- Todas deben dar `true`. Las dos últimas explican por qué es seguro: la lectura
-- sigue y las funciones guardián corren como su dueño.
select
  not (has_table_privilege('authenticated', 'public.rendimiento_mensual', 'INSERT')
    or has_table_privilege('authenticated', 'public.rendimiento_mensual', 'UPDATE')
    or has_table_privilege('authenticated', 'public.rendimiento_mensual', 'DELETE'))
    as rendimiento_sin_escritura,
  not (has_table_privilege('authenticated', 'public.terminales', 'INSERT')
    or has_table_privilege('authenticated', 'public.terminales', 'UPDATE')
    or has_table_privilege('authenticated', 'public.terminales', 'DELETE'))
    as terminales_sin_escritura,
  not (has_table_privilege('authenticated', 'public.tarifas_hora', 'INSERT')
    or has_table_privilege('authenticated', 'public.tarifas_hora', 'UPDATE')
    or has_table_privilege('authenticated', 'public.tarifas_hora', 'DELETE'))
    as tarifas_sin_escritura,
  (select count(*) = 0 from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relnamespace = 'public'::regnamespace
      and c.relname in ('rendimiento_mensual', 'terminales', 'tarifas_hora')
      and p.polcmd in ('a', 'w', 'd', '*'))
    as no_queda_politica_de_escritura,
  (select count(*) filter (where c.relname = 'rendimiento_mensual') >= 1
      and count(*) filter (where c.relname = 'terminales') >= 2
      and count(*) filter (where c.relname = 'tarifas_hora') >= 1
     from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relnamespace = 'public'::regnamespace and p.polcmd = 'r')
    as las_lecturas_siguen,
  has_table_privilege('service_role', 'public.terminales', 'INSERT')
    and has_table_privilege('service_role', 'public.tarifas_hora', 'INSERT')
    and has_table_privilege('service_role', 'public.rendimiento_mensual', 'INSERT')
    as service_role_conserva_su_escritura,
  coalesce((select bool_and(prosecdef) from pg_proc
             where proname in ('fn_set_rendimiento', 'fn_quitar_rendimiento')
               and pronamespace = 'public'::regnamespace), false)
    as las_funciones_guardian_corren_como_su_dueno;
