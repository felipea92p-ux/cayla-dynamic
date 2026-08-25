-- ============================================================================
-- 0296 · EL ROL SOLO CAMBIA POR UNA PUERTA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cerrar la puerta del rol no dependa de que ninguna pantalla se
--   acuerde de usar `fn_set_rol` (0295). Aunque todo el código de este
--   repositorio ya pase por ahí, un `PATCH /rest/v1/personas` con
--   `{"rol":"admin"}` armado a mano seguiría funcionando mientras nada lo
--   impida en la base — la policy de UPDATE de `personas` filtra FILAS, no
--   columnas, así que nunca iba a impedir esto por sí sola.
--
-- POR QUÉ NO ES UN `revoke update (rol)` — Y CASI LO FUE
--   `personas` tiene `grant update on personas to authenticated` a nivel de
--   TABLA completa, de origen (así quedó verificado el 2026-08-25 antes de
--   escribir esta migración: `information_schema.table_privileges` lo
--   confirma). Un `revoke update (rol) …` no lo toca — Postgres sigue
--   permitiendo escribir CUALQUIER columna mientras el grant de tabla siga
--   vivo, y `information_schema.column_privileges` lo refleja igual aunque
--   se revoque la columna sola. Medido: se probó el revoke de columna solo,
--   y la comprobación de la propia migración volvió `false`.
--
--   Reescribir el grant entero de la tabla (revocar todo y regranting columna
--   por columna) habría sido un cambio de blast radius grande sobre la tabla
--   más usada del sistema, por un beneficio angosto. Se descartó.
--
-- EL DISEÑO: UN TRIGGER QUE DISTINGUE QUIÉN ESCRIBE, NO QUÉ COLUMNA SE ABRE
--   `fn_set_rol` y `fn_crear_persona` son `SECURITY DEFINER`: mientras
--   corren, `current_user` es `postgres` —el dueño de la función—, sea quien
--   sea la sesión que las llamó. Un `PATCH` directo de PostgREST corre como
--   `authenticated`. El trigger de abajo aprovecha exactamente esa
--   diferencia: si `rol` cambia y `current_user` no es `postgres`, aborta.
--   No toca ningún grant, así que no hay ninguna otra columna que pueda
--   quedar rota por accidente.
--
--   Verificado antes de escribir esta migración: ninguna otra función escribe
--   `rol` (`select proname from pg_proc where prosrc ~ 'set\s+rol\s*=' and
--   proname not in ('fn_crear_persona','fn_set_rol')` da cero filas), así que
--   el trigger no tiene a quién más dejar pasar.
--
-- POR QUÉ SOLO CUBRE UPDATE
--   La creación de una persona (`fn_crear_persona`) es un INSERT, no un
--   UPDATE: este trigger no lo alcanza y no hace falta que lo alcance —el
--   rol inicial se valida dentro de esa misma función. Que esa validación NO
--   mira el escalafón (cualquier admin o líder puede crear a alguien
--   directamente como Admin) es la MISMA vulnerabilidad por otra puerta, y
--   se corrige aparte: toca `CREATE OR REPLACE` sobre una función existente,
--   y esa clase de cambio pide primero el md5 de PRODUCCIÓN (regla de la
--   casa) — no el de esta migración, que solo cierra la puerta del UPDATE.
--
-- CÓMO SE REVIERTE
--   `drop trigger trg_personas_rol_solo_por_rpc on personas;`
--   `drop function fn_bloquear_rol_directo();`
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final.
-- ============================================================================

create or replace function fn_bloquear_rol_directo()
returns trigger
language plpgsql as $function$
begin
  if new.rol is distinct from old.rol and current_user <> 'postgres' then
    raise exception 'El rol se cambia con fn_set_rol, no con un update directo.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_personas_rol_solo_por_rpc on personas;
create trigger trg_personas_rol_solo_por_rpc
  before update on personas
  for each row
  execute function fn_bloquear_rol_directo();

insert into migraciones_aplicadas (numero, nombre)
values (296, '0296_el_rol_solo_cambia_por_una_puerta')
on conflict (numero) do nothing;

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select
  (select count(*) from pg_trigger where tgname = 'trg_personas_rol_solo_por_rpc'
     and tgrelid = 'personas'::regclass) as el_trigger_existe;
