-- ============================================================================
-- 0432 · EL CESE TAMBIÉN SE CAMBIA POR UNA PUERTA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `personas.estado`, `fecha_cese`, `motivo_cese` y `tipo_vinculo` —los
--   cuatro campos que decide un cese o un cambio de vínculo, y de los que
--   cuelga la liquidación, la causa justa y qué le corresponde devengar
--   (fn_devenga_beneficios, 0129)— no se puedan cambiar con un `UPDATE`
--   directo, saltándose `fn_cesar_persona` / `fn_reactivar_persona` (0327,
--   redefinidas con auditoría en la 0415) y `fn_set_tipo_vinculo` (0324): sus
--   candados de "no reescribas un mes ya pagado", sus reglas de negocio (un
--   cese a la vez por persona, 0174; cerrar tramos de salario y horario) y su
--   fila en `correcciones_auditoria`.
--
-- EL DEFECTO
--   `personas` tiene `grant update` de TABLA completa a `authenticated` (0004)
--   y la policy `personas_update_admin_lider` (0003) es de FILA, no de
--   columna — el mismo hueco que ya se cerró tres veces: `rol` (0296),
--   `sede_base_id` (0342) y `regimen_pension` (0410). Cualquier sesión
--   admin/líder puede hacer
--     PATCH /rest/v1/personas?id=eq.<uuid>   {"estado":"inactivo","fecha_cese":"2026-01-01"}
--   y cesar a alguien sin pasar por ninguna de las comprobaciones de
--   `fn_cesar_persona` ni dejar rastro de quién lo hizo ni por qué.
--
--   Señalado en la auditoría de arquitectura del 2026-09-03
--   (docs/hallazgos-abiertos.md, sección "Alta"): "La policy de UPDATE de
--   `personas` filtra filas, no columnas — `estado`/`fecha_cese`/
--   `motivo_cese`/`tipo_vinculo` no tienen el mismo trigger que ya protege a
--   `rol` y `sede_base_id`." La 0415 cerró la mitad de este hallazgo (la
--   auditoría, dentro de la función) dando por hecho que la otra mitad —el
--   candado contra el UPDATE directo— ya existía ("el cese... siempre fue una
--   función y nunca un UPDATE directo desde el navegador"). Verificado hoy
--   con `grep -rn "^create trigger" supabase/migrations/*.sql`: los cuatro
--   triggers que existen sobre `personas` son timestamp (0001), rol (0296),
--   sede (0342), `pin_hash` (0364) y régimen de pensión (0410) — ninguno
--   menciona `estado`, `fecha_cese`, `motivo_cese` ni `tipo_vinculo`. El
--   supuesto de la 0415 era una suposición, no una medición.
--
-- QUÉ ASUME
--   Que hoy tres funciones SECURITY DEFINER escriben estas columnas —
--   `fn_cesar_persona` y `fn_reactivar_persona` (`estado`, `fecha_cese`,
--   `motivo_cese`; vigentes en la 0415) y `fn_set_tipo_vinculo` (`tipo_
--   vinculo`; vigente en la 0324)— confirmado con `donde-vive.sh` y
--   `select prosecdef from pg_proc` (las tres, `true`). Las tres corren con
--   `current_user = 'postgres'`, así que el trigger de abajo no las alcanza.
--
--   Verificado además que ninguna pantalla hace un `.from("personas").update()`
--   directo sobre estas cuatro columnas (`grep -rn '\.from\("personas"\)'
--   apps/web`): los únicos `.update()` directos tocan `auth_user_id`, `email`,
--   `nombres`/`apellidos` — ninguno de los cuatro campos que este trigger
--   cierra. Cerrar la puerta no rompe ningún camino que la app use hoy.
--
-- POR QUÉ LAS CUATRO EN UN SOLO TRIGGER, Y NO CUATRO
--   Son una sola decisión de negocio compartiendo destino, no cuatro
--   independientes: no hay un mundo donde `estado` cambie a 'inactivo' sin que
--   cambien `fecha_cese` y `motivo_cese` a la vez (o los tres vuelvan a null al
--   reactivar), y `tipo_vinculo` viaja con ellas porque `fn_set_tipo_vinculo`
--   es la misma familia de "campo que decide qué le corresponde devengar".
--   Mismo criterio de agrupación que ya usó la 0415 para auditar las tres
--   columnas del cese en una sola fila.
--
-- POR QUÉ UN TRIGGER APARTE Y NO REESCRIBIR NINGUNA DE LAS TRES FUNCIONES
--   Mismo criterio que ya usaron la 0342 y la 0410: un trigger nuevo y angosto
--   por grupo de columnas protegidas, no tocar funciones que ya están vivas y
--   no hace falta cambiar — mantiene acotado el blast radius sobre la tabla
--   más usada del sistema.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_personas_cese_solo_por_rpc on personas;
--   drop function if exists fn_bloquear_cese_directo();
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El select del final: `el_trigger_existe` tiene que dar 1.
-- ============================================================================

create or replace function fn_bloquear_cese_directo()
returns trigger
language plpgsql as $function$
begin
  if (
    new.estado is distinct from old.estado
    or new.fecha_cese is distinct from old.fecha_cese
    or new.motivo_cese is distinct from old.motivo_cese
    or new.tipo_vinculo is distinct from old.tipo_vinculo
  ) and current_user <> 'postgres' then
    raise exception 'El cese y el tipo de vínculo se cambian con fn_cesar_persona / fn_reactivar_persona / fn_set_tipo_vinculo, no con un update directo.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_personas_cese_solo_por_rpc on personas;
create trigger trg_personas_cese_solo_por_rpc
  before update on personas
  for each row
  execute function fn_bloquear_cese_directo();

insert into migraciones_aplicadas (numero, nombre)
values (432, 'el_cese_tambien_se_cambia_por_una_puerta')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select
  (select count(*) from pg_trigger where tgname = 'trg_personas_cese_solo_por_rpc'
     and tgrelid = 'personas'::regclass) as el_trigger_existe;
