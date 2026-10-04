-- ============================================================================
-- 0507 · EL ALTA DE UNA PERSONA SOLO ENTRA POR fn_crear_persona
-- ============================================================================
--
-- QUÉ PROMETE
--   Que dar de alta a alguien sea imposible por cualquier camino que no sea
--   `fn_crear_persona`: ni un POST armado a mano contra /rest/v1/personas, ni
--   un insert por la vista `retail.personas`. Lo garantiza la base; deja de
--   depender de que ninguna pantalla se acuerde de usar la función.
--
-- EL DEFECTO, EN UNA LÍNEA
--   La 0003 dejó en `personas` una política de INSERT (`with check
--   (fn_es_admin_o_lider())`) y la 0004 le dio a `authenticated` el privilegio
--   de INSERT sobre toda la tabla. Juntas dejan que un admin o un líder DO
--   inserte filas directo, saltándose TODO lo que `fn_crear_persona` valida:
--   el escalafón de la 0300 («no creas a alguien igual o por encima de ti»),
--   el aviso de personas parecidas de la 0506, el catálogo de áreas, el PIN.
--   La 0300 decía en su cabecera que `fn_crear_persona` es «la única puerta
--   de alta del sistema». Lo era de la APP; de la base, no.
--
-- LO QUE SE MIDIÓ (2026-10-04, Postgres desechable con las 483 migraciones de
-- `main`, todo dentro de `begin … rollback`, jwt de un lider_do)
--   1. `fn_crear_persona(…, 'admin', …)` → «No puedes crear una persona con un
--      rol igual o superior al tuyo.»  La puerta oficial frena.
--   2. `insert into personas (…, rol) values (…, 'admin')` con la MISMA sesión
--      → PASA, con `current_user = authenticated`. La de atrás no frena.
--   3. La cadena entera: ese insert directo ata el admin nuevo a OTRA cuenta de
--      acceso (`auth_user_id`; es único, no puede ser la propia); cuando esa
--      cuenta inicia sesión, `fn_rol_actual()` = 'admin', y como admin de
--      verdad pasa `fn_set_rol` y sube de rol a quien quiera. O sea: la 0295,
--      la 0296 y la 0300 cerraron el escalafón por tres puertas y quedó una
--      cuarta —la de la tabla— que valía por las tres.
--   4. Los triggers de rol, sede, pensión, PIN y cese son todos BEFORE UPDATE,
--      así que el INSERT no los dispara. El único trigger de INSERT sobre
--      `personas` es el de la 0490, y solo mira la columna `cuenta_de_servicio`
--      (la prueba 388 ya daba por hecho que el insert directo era una puerta
--      abierta y la cerró columna por columna, solo para esa).
--   5. La vista `retail.personas` (0218) también es insertable y `authenticated`
--      tiene INSERT sobre ella —por los privilegios por defecto de la 0217, no
--      por decisión—. Hoy NO sirve para dar de alta (`nombre` es una columna
--      calculada y `nombres` es NOT NULL), pero es la misma tabla por otro
--      mango, y solo se salva porque la 0218 la creó con
--      `security_invoker = true`: si alguien la recrea sin esa opción, entraría
--      a `personas` como su dueño y se saltaría hasta el revoke de abajo.
--
-- QUIÉN INSERTA HOY EN `personas` CON SESIÓN DE USUARIO (medido; si alguno
-- existiera, esta migración NO se escribe así)
--   · apps/web y packages/: nadie. La única alta es `supabase.rpc(
--     'fn_crear_persona', …)` en admin/equipo/page.tsx.
--   · scripts/: setup-personas-prod.mjs y seed-dev.mjs insertan, pero con la
--     llave de servicio (`createClient(URL, SERVICE_ROLE_KEY)`), que no pasa
--     por RLS. El privilegio de INSERT de `service_role` NO se toca.
--   · cayla-retail: sus `insert into personas` son seeds (corren como postgres)
--     y un fixture efímero propio de un script de pruebas. Ningún código con
--     sesión de usuario; las estaciones entran por `retail.terminales` desde el
--     ADR-0162 y ya no usan su fila de `personas`.
--   · SQL: en todas las migraciones, los únicos `insert into personas` son las
--     cuatro versiones de `fn_crear_persona`, todas SECURITY DEFINER y dueñas
--     de `postgres`: su insert corre como su dueño y no necesita ni la política
--     ni el privilegio que aquí se quitan. Ninguna otra función de ningún
--     esquema inserta en `personas`.
--   · Pruebas: de 308 archivos, uno (la 388) inserta en `personas` como
--     `authenticated`, y es precisamente para comprobar que NO se puede.
--
-- DECIDÍ:    cerrar la puerta en vez de vigilarla. Se borra la política de
--            INSERT y se revoca el privilegio de INSERT a `authenticated`
--            (y a `anon` y `public`, por si producción difiere del repo) sobre
--            `personas`, y el de INSERT sobre `retail.personas`. La única
--            entrada que queda es la función guardián que ya existe.
-- DESCARTÉ:  un trigger BEFORE INSERT con `current_user <> 'postgres'`, que
--            es el molde de la 0296, la 0342 y la 0490. Ese molde existe
--            porque en UPDATE el privilegio NO se puede revocar sin dejar a
--            todo el mundo sin poder escribir las demás columnas (la 0296 lo
--            midió y lo descartó). En INSERT esa razón no existe: nadie
--            legítimo inserta directo, y lo que se puede borrar se borra —
--            sin privilegio la sentencia muere antes de que corra una línea
--            nuestra, mientras que un trigger deja entrar la fila hasta la
--            puerta y la rechaza ahí. Además, un trigger «todo lo que no sea
--            postgres» frenaría también a `service_role` (los scripts de alta
--            de arriba), y dejarlo pasar es un `if` para un caso especial.
--            También descarté no hacer nada y confiar en que ninguna pantalla
--            lo use: es el razonamiento de la cabecera de la 0296 y es
--            exactamente lo que dejó esta puerta abierta desde la 0003.
-- SE ROMPE SI:
--   1. Una migración futura «arregla» un `permission denied` en `personas`
--      devolviendo el INSERT a `authenticated` Y creando una política de
--      INSERT o ALL. Hacen falta las dos cosas (sin política, RLS niega aunque
--      haya privilegio), y la prueba 401 falla en `db-tests` antes de fusionar.
--   2. Existe en producción una función SECURITY INVOKER, pegada a mano y por
--      tanto fuera del repo, que inserta en `personas` con sesión de usuario:
--      dejaría de funcionar con «permission denied for table personas». La
--      consulta 2 de abajo lo dice ANTES de pegar.
--   3. Se recrea `retail.personas` con drop+create: los privilegios por defecto
--      del esquema retail (0217) le devuelven INSERT a `authenticated`, y si
--      además pierde `security_invoker = true`, entra a `personas` como su
--      dueño. Lo caza la prueba 401 si la vista se recrea desde este repo;
--      una recreación hecha desde cayla-retail no pasa por este CI.
--   4. Alguien monta una carga masiva por PostgREST con una sesión de usuario
--      (un importador de planilla, por ejemplo). Hoy no hay ninguna: las
--      cargas históricas usan `service_role`.
--
-- LO QUE NO TOCA
--   · `fn_crear_persona` NO se reescribe: no hay md5 de partida porque no hay
--     función que reemplazar. Tampoco choca con la 0506 (que la reescribe y le
--     cambia la firma): esa migración no toca políticas ni privilegios, y esta
--     no toca la función, así que se pegan en cualquier orden.
--   · El UPDATE y el DELETE de `personas`. El UPDATE sigue protegido columna
--     por columna por sus triggers; el DELETE no tiene política, así que RLS lo
--     niega (las personas no se borran, se marcan inactivas).
--   · UPDATE y DELETE de la vista `retail.personas`: un UPDATE por la vista
--     pasa por los mismos triggers de la tabla (medido: el cambio de sede por
--     la vista da «La sede se cambia con fn_set_sede_base…»). Si retail
--     quisiera dejarla de solo lectura, es otra decisión y de otro repo.
--   · El trigger de INSERT de la 0490 (`trg_personas_cuenta_de_servicio_solo_por_rpc`):
--     para `authenticated` queda inalcanzable, pero sigue frenando a
--     `service_role`, que conserva el INSERT. Se deja.
--
-- ANTES DE PEGAR — TRES CONSULTAS DE SOLO LECTURA A PRODUCCIÓN (SQL Editor).
-- Ninguna modifica nada. Confirman que producción se parece al repo en lo que
-- esta migración da por cierto; si alguna no cuadra, parar y avisar.
--
--   -- 1) Esperado: UNA política de INSERT (personas_insert_admin_lider, 'a') y
--   --    `authenticated` entre quienes tienen INSERT. Si hay otra política de
--   --    INSERT o ALL que no está en el repo, hay que conocerla antes.
--   select polname, polcmd, pg_get_expr(polwithcheck, polrelid) as con_check
--     from pg_policy where polrelid = 'public.personas'::regclass order by 1;
--   select grantee from information_schema.role_table_grants
--    where table_schema = 'public' and table_name = 'personas'
--      and privilege_type = 'INSERT' order by 1;
--
--   -- 2) Esperado: UNA fila, fn_crear_persona, prosecdef = t. Cualquier otra
--   --    fila (sobre todo con prosecdef = f) es algo que esta migración rompe.
--   select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as firma, p.prosecdef
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname not in ('pg_catalog', 'information_schema')
--      and p.prosrc ~* 'insert\s+into\s+(public\.)?"?personas"?\M';
--
--   -- 3) Esperado: {security_invoker=true}. Si sale NULL o {security_invoker=false}
--   --    la vista entra como su dueño; la parte de la vista de esta migración la
--   --    cierra igual, pero hay que saberlo.
--   select reloptions, has_table_privilege('authenticated', oid, 'INSERT') as authenticated_inserta
--     from pg_class where oid = to_regclass('retail.personas');
--
-- CÓMO SE REVIERTE (si algo legítimo apareciera)
--   create policy personas_insert_admin_lider on personas
--     for insert to authenticated with check (fn_es_admin_o_lider());
--   grant insert on personas to authenticated;
--   grant insert on retail.personas to authenticated;
--   Y se retira la prueba 401. Reabrirlo es reabrir el hueco de arriba: antes
--   de hacerlo, mejor un trigger BEFORE INSERT que rechace a todo el que no
--   sea `postgres` ni `service_role`.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final: todas las columnas deben dar `true`.
-- ============================================================================

-- 1 · La política que dejaba entrar a cualquier admin o líder DO.
drop policy if exists personas_insert_admin_lider on personas;

-- 2 · El privilegio. `public` y `anon` no lo tenían en el repo; se revocan por si
--     producción difiere (revocar lo que no se concedió es un no-op, no un error).
revoke insert on personas from public, anon, authenticated;

-- 3 · La misma puerta por la vista. Va dentro de un `do` porque, si la vista no
--     existiera en algún entorno, un `revoke` suelto abortaría la migración.
do $$
begin
  if to_regclass('retail.personas') is not null then
    execute 'revoke insert on retail.personas from public, anon, authenticated';
  end if;
end;
$$;

insert into migraciones_aplicadas (numero, nombre)
values (507, '0507_el_alta_de_una_persona_solo_entra_por_fn_crear_persona')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACION ────────────────────────────────────────────────────────────
-- Todas deben dar `true`. La última es la que explica por qué el revoke es
-- seguro: la función que da de alta corre como su dueño, no como quien llama.
select
  not has_table_privilege('authenticated', 'public.personas', 'INSERT')
    as authenticated_no_inserta_en_personas,
  not has_table_privilege('anon', 'public.personas', 'INSERT')
    as anon_no_inserta_en_personas,
  (select count(*) = 0 from pg_policies
    where schemaname = 'public' and tablename = 'personas' and cmd in ('INSERT', 'ALL'))
    as no_queda_politica_de_insert,
  coalesce(not has_table_privilege('authenticated', to_regclass('retail.personas'), 'INSERT'), true)
    as la_vista_tampoco_inserta,
  has_table_privilege('service_role', 'public.personas', 'INSERT')
    as service_role_conserva_su_insert,
  coalesce((select bool_and(prosecdef) from pg_proc
             where proname = 'fn_crear_persona' and pronamespace = 'public'::regnamespace), false)
    as fn_crear_persona_corre_como_su_dueno;
