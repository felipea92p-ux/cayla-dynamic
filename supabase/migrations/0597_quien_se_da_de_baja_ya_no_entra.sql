-- ============================================================================
-- 0597 · QUIEN SE DA DE BAJA YA NO ENTRA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que en el mismo instante en que una persona pasa a `estado = 'inactivo'`
--   —por cualquier camino: «Dar de baja» en Equipo, el cierre de una prueba, un
--   fin de contrato registrado o una corrección en el SQL Editor— su cuenta
--   deje de poder iniciar sesión y se le cierren las sesiones abiertas. Y que al
--   reactivarla vuelva a entrar con su misma clave, sin que nadie toque nada más.
--
-- QUÉ HALLAZGO CIERRA
--   La 0374 le quitó a quien cesa el poder sobre datos AJENOS, y dejó el login
--   tal cual a propósito. Su cuenta seguía entrando: veía «Lo mío» y, si tenía
--   rol de panel, un panel vacío (la propia 0374 lo dejó anotado como pendiente).
--   Felipe (2026-11-05): «cada que se da de baja a un miembro de equipo ya no
--   debe poder acceder a su login».
--
-- POR QUÉ UN TRIGGER SOBRE `personas`
--   Porque las puertas son varias y van a ser más: `fn_cese_aplicar` (a la que
--   llegan `fn_cesar_persona` y `fn_prueba_cerrar`), `fn_reactivar_persona` y el
--   SQL Editor. El dato que dice «ya no trabaja aquí» es uno solo, y el trigger
--   vive pegado a él. Además va en la misma transacción que el cese: no hay un
--   cese hecho con el acceso a medio cortar.
--
--   La alternativa —que la pantalla llame a la Admin API después del RPC— es la
--   que la 0374 ya descartó: una pieza más que puede no dispararse justo cuando
--   importa (se cierra la pestaña, se cae la red) y que no cubre las otras
--   puertas. Si esta escritura falla, el cese falla entero y se ve: se prefirió
--   eso a un cese «exitoso» que deja la cuenta abierta.
--
-- CÓMO SE CORTA, MEDIDO CONTRA EL GOTRUE LOCAL (2026-11-05)
--     `banned_until` a futuro + borrar sesiones y refresh tokens:
--       · iniciar sesión          → 400 user_banned
--       · refrescar un token      → 400 refresh_token_not_found
--       · /auth/v1/user           → 403 session_not_found
--       · enlace de recuperación  → 403 user_banned
--       · quitar el ban           → vuelve a entrar con la misma clave
--   ⚠️ `banned_until = 'infinity'` NO sirve: GoTrue no sabe leerlo y responde
--   500 «Database error querying schema» en cada login. Por eso 100 años, que
--   es lo mismo que hace la Admin API con un `ban_duration` largo.
--
-- QUÉ NO CORTA, Y HAY QUE SABERLO
--   El JWT ya emitido sigue siendo válido para PostgREST hasta que venza (una
--   hora con la configuración por defecto): la firma no se puede revocar. En ese
--   rato solo alcanza SUS datos (sin rol desde la 0374), y el marco de la app
--   (`GuardaDeAcceso`) cierra la sesión en cuanto abre o vuelve a la pestaña.
--
-- QUÉ ASUME
--   · Que el dueño de la función (`postgres`) puede escribir en `auth.users`,
--     `auth.sessions` y `auth.refresh_tokens`. La comprobación previa de la
--     entrega lo pregunta a producción.
--   · Que `personas.auth_user_id` es único (0001): una cuenta es de una persona.
--
-- QUÉ DEJA FUERA, A PROPÓSITO
--   · Las cuentas de servicio (0490): las estaciones de retail no son personas y
--     su `estado` no dice nada de que una persona se haya ido.
--   · Una cuenta que además sea la de un terminal: cortarla dejaría a una sede
--     sin marcar. No debería existir ninguna; si existe, se resuelve a mano.
--   · El vencimiento de un contrato que nadie registró: `fecha_fin_contrato` es
--     un plan, no un cese (0143/0144). Quien sigue trabajando con la renovación
--     atrasada no puede quedarse sin entrar por una fecha. Corta cuando se
--     registra la baja, con el motivo que sea.
--
-- QUÉ CAMBIA CON LOS QUE YA SE FUERON
--   El final de esta migración aplica el corte a quienes ya están inactivos.
--   Sin eso, la promesa valdría solo desde hoy y las cuentas de los que ya se
--   fueron seguirían abiertas. Es repetible y no toca a nadie activo.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_personas_acceso_sigue_al_estado on personas;
--   drop function if exists fn_personas_acceso_sigue_al_estado();
--   drop function if exists fn_cortar_acceso_de_cuenta(uuid);
--   update auth.users u set banned_until = null
--     from personas p
--    where p.auth_user_id = u.id and p.estado = 'inactivo'
--      and p.cuenta_de_servicio is not true;
--   Las sesiones cerradas no vuelven: cada quien inicia sesión de nuevo.
-- ============================================================================

-- El corte en sí, en un solo sitio: lo usan el trigger y el repaso del final.
-- `search_path` sin nada que resolver en `auth`: las tablas van con su esquema.
create or replace function fn_cortar_acceso_de_cuenta(p_auth_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  -- Se conserva un ban que ya estaba puesto: repetir el repaso no lo mueve.
  update auth.users
     set banned_until = now() + interval '100 years'
   where id = p_auth_user_id
     and (banned_until is null or banned_until < now());

  -- El borrado de la sesión arrastra sus refresh tokens (FK en cascada). El
  -- segundo `delete` es para los tokens antiguos sin `session_id`.
  delete from auth.sessions where user_id = p_auth_user_id;
  delete from auth.refresh_tokens where user_id = p_auth_user_id::text;
end;
$function$;

revoke execute on function fn_cortar_acceso_de_cuenta(uuid) from public, anon, authenticated;

comment on function fn_cortar_acceso_de_cuenta(uuid) is
  'Deja una cuenta sin poder iniciar sesión y le cierra las sesiones (0597). Interna: una sesión del '
  'navegador que pudiera llamarla dejaría fuera a quien quisiera.';


create or replace function fn_personas_acceso_sigue_al_estado()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.cuenta_de_servicio is true
     or exists (select 1 from terminales t where t.auth_user_id = new.auth_user_id) then
    return null;
  end if;

  if new.estado <> 'activo' then
    -- Se dio de baja, o se le enlazó una cuenta estando ya de baja.
    perform fn_cortar_acceso_de_cuenta(new.auth_user_id);
  elsif old.estado <> 'activo' then
    -- Volvió. Solo aquí se quita el ban: enlazar una cuenta a alguien activo no
    -- es una razón para tocarlo.
    update auth.users set banned_until = null
     where id = new.auth_user_id and banned_until is not null;
  end if;
  return null;
end;
$function$;

revoke execute on function fn_personas_acceso_sigue_al_estado() from public, anon, authenticated;

comment on function fn_personas_acceso_sigue_al_estado() is
  'Hace que el acceso siga a `personas.estado` por cualquier camino: inactiva no entra, reactivada vuelve '
  'a entrar (0597). Deja fuera cuentas de servicio y cuentas de terminal.';

drop trigger if exists trg_personas_acceso_sigue_al_estado on personas;
create trigger trg_personas_acceso_sigue_al_estado
  after update of estado, auth_user_id on personas
  for each row
  when (new.auth_user_id is not null
        and (old.estado is distinct from new.estado
             or old.auth_user_id is distinct from new.auth_user_id))
  execute function fn_personas_acceso_sigue_al_estado();


-- ── Los que ya se fueron ────────────────────────────────────────────────────
do $$
declare r record;
begin
  for r in
    select p.auth_user_id
      from personas p
     where p.estado <> 'activo'
       and p.auth_user_id is not null
       and p.cuenta_de_servicio is not true
       and not exists (select 1 from terminales t where t.auth_user_id = p.auth_user_id)
  loop
    perform fn_cortar_acceso_de_cuenta(r.auth_user_id);
  end loop;
end;
$$;


insert into migraciones_aplicadas (numero, nombre) values (597, 'quien_se_da_de_baja_ya_no_entra')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Cómo se comprueba que entró ──────────────────────────────────────────────
select
  (select count(*) from pg_trigger
    where tgname = 'trg_personas_acceso_sigue_al_estado' and tgrelid = 'personas'::regclass) as trigger_1,
  (select count(*) from personas p join auth.users u on u.id = p.auth_user_id
    where p.estado <> 'activo' and p.cuenta_de_servicio is not true
      and not exists (select 1 from terminales t where t.auth_user_id = p.auth_user_id)
      and (u.banned_until is null or u.banned_until < now())) as de_baja_con_acceso_0,
  (select count(*) from personas p join auth.users u on u.id = p.auth_user_id
    where p.estado = 'activo' and u.banned_until > now()) as activos_sin_acceso_0,
  (select nombre from migraciones_aplicadas where numero = 597) as registro;
