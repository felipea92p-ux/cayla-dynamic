-- ============================================================================
-- 0404 · EL RÉGIMEN DE PENSIÓN TAMBIÉN SE CAMBIA POR UNA PUERTA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `personas.regimen_pension` —la columna que `fn_planilla_calcular_nucleo`
--   sigue leyendo como respaldo cuando la persona no tiene ningún tramo en
--   `asignaciones_regimen_pension` (0261/0397)— no se pueda cambiar con un
--   `UPDATE` directo, saltándose `fn_cambiar_regimen_pension` (0332): su freno
--   de "no reescribas un mes ya pagado" (0203/0277/0332), su fila en
--   `correcciones_auditoria`, y su tramo del pasado (0332).
--
-- EL DEFECTO, ENCONTRADO EN UNA AUDITORÍA DEDICADA A AFP (2026-09-08)
--   `rol` (0296) y `sede_base_id` (0342) tienen exactamente este candado desde
--   hace semanas. `regimen_pension` no lo tenía — pese a que CLAUDE.md y
--   docs/estado.md (cierre del 2026-09-03) dan por hecho que las TRES columnas
--   ya comparten el mismo molde ("función guardián + trigger que compara
--   `current_user`"). No es así: se escribió la función guardián (0261) y
--   nunca se cerró la puerta de al lado.
--
--   Confirmado leyendo los cuatro triggers que hoy existen sobre `personas`
--   (`grep -rn "^create trigger" supabase/migrations/*.sql`): timestamp (0001),
--   rol (0296), sede (0342) y `pin_hash` (0364). Ninguno menciona
--   `regimen_pension`.
--
--   `personas` tiene `grant update` de TABLA completa a `authenticated` (0004)
--   y la policy `personas_update_admin_lider` (0003) es de FILA, no de columna
--   — el mismo hueco que ya documentó la 0296 para `rol`. Cualquier sesión
--   admin/líder puede hacer
--     PATCH /rest/v1/personas?id=eq.<uuid>   {"regimen_pension":"onp"}
--   y, para quien no tenga tramo abierto (población real, no vacía — la 0332
--   la cuenta como `personas_sin_tramo_con_regimen`, y una consulta en
--   producción el 2026-09-08 confirmó al menos una persona sin ningún régimen
--   asignado hoy), mueve de inmediato la tasa de CUALQUIER periodo ya pagado,
--   porque la cascada de `fn_planilla_calcular_nucleo` cae a esta columna sin
--   mirar ninguna fecha.
--
-- QUÉ ASUME
--   Que hoy solo tres caminos escriben esta columna: `fn_cambiar_regimen_
--   pension` (SECURITY DEFINER, vigente en la 0332), la migración de datos
--   0331 (SQL pegado a mano en el SQL Editor) y la siembra puntual de la
--   0114/0190 (también SQL Editor). Los tres corren con `current_user =
--   'postgres'` — el primero por ser SECURITY DEFINER, los otros dos porque el
--   SQL Editor de Supabase conecta como `postgres` — así que el trigger de
--   abajo no los alcanza.
--
--   Verificado además que `fn_set_regimen_pension` (0125), el antecesor de
--   `fn_cambiar_regimen_pension`, sigue existiendo en el esquema pero tiene el
--   `execute` revocado de `authenticated` desde la 0277 (`revoke all ... from
--   authenticated`): no es un camino vivo, nadie puede llamarlo desde la app.
--
-- POR QUÉ UN TRIGGER APARTE Y NO REESCRIBIR `fn_bloquear_rol_directo` (0296)
--   Mismo criterio que ya usó la 0342 para no tocar la 0296: un trigger nuevo
--   y angosto por columna protegida, no una función genérica — mantiene
--   acotado el blast radius sobre la tabla más usada del sistema, y no exige
--   pedir el md5 de producción de una función que ya está viva y no hace
--   falta tocar.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_personas_regimen_pension_solo_por_rpc on personas;
--   drop function if exists fn_bloquear_regimen_pension_directo();
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El select del final: `el_trigger_existe` tiene que dar 1.
-- ============================================================================

create or replace function fn_bloquear_regimen_pension_directo()
returns trigger
language plpgsql as $function$
begin
  if new.regimen_pension is distinct from old.regimen_pension and current_user <> 'postgres' then
    raise exception 'El régimen de pensión se cambia con fn_cambiar_regimen_pension, no con un update directo.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_personas_regimen_pension_solo_por_rpc on personas;
create trigger trg_personas_regimen_pension_solo_por_rpc
  before update on personas
  for each row
  execute function fn_bloquear_regimen_pension_directo();

insert into migraciones_aplicadas (numero, nombre)
values (404, '0404_el_regimen_de_pension_tambien_se_cambia_por_una_puerta')
on conflict (numero) do nothing;

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select
  (select count(*) from pg_trigger where tgname = 'trg_personas_regimen_pension_solo_por_rpc'
     and tgrelid = 'personas'::regclass) as el_trigger_existe;
