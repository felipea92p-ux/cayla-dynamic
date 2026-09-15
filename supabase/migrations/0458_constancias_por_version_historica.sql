-- ============================================================================
-- 0458 — La hoja de constancias puede mirar una versión histórica, no solo
-- la vigente
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que `fn_acuses_politica_salarial` pueda recibir un número de versión y
--   devolver quién acusó ESA versión, en vez de solo la vigente.
--
-- QUÉ ASUME
--
--   · `politica_salarial_acuses` guarda una fila por `(persona_id, version)`
--     desde la 0141: el dato histórico ya existe, esta migración no lo crea,
--     solo lo hace consultable.
--   · Sigue siendo admin/lider_do quien puede ver esta hoja — mismo guard que
--     ya tenía la función.
--
-- QUÉ PROBLEMA CIERRA
--
--   Hoy, una vez que se publica la versión 5, no hay ninguna forma de ver
--   quién había acusado recibo de la versión 4: la función solo conocía
--   `order by version desc limit 1`. El dato vive en la base desde el primer
--   día (0141) y era huérfano en la interfaz — auditado el 2026-09-15, junto
--   con que ningún otro módulo de Dynamic (tampoco `/admin/normas`) tiene
--   esto resuelto.
--
-- POR QUÉ EL FILTRO DE POBLACIÓN SIGUE SIENDO EL ACTUAL, NO EL DE ENTONCES
--
--   La función sigue contando "personas activas y en planilla HOY", igual
--   para una versión histórica que para la vigente. Es una simplificación
--   deliberada, no un descuido: registrar quién estaba obligado EN CADA
--   FECHA pasada exigiría una tabla de historial de población que hoy no
--   existe en ningún lugar de Dynamic. Lo que esta consulta responde es "de
--   quienes hoy siguen obligados, quién había acusado la versión N" — útil
--   para una auditoría, pero no equivalente a "quién estaba obligado el día
--   que se publicó la versión N". Alguien que ya cesó no aparece en ninguna
--   hoja histórica por este motivo, igual que hoy no aparece en la vigente.
--
-- QUÉ NO CAMBIA
--
--   Llamar `fn_acuses_politica_salarial()` sin argumentos sigue devolviendo
--   exactamente lo mismo que antes (la vigente): `p_version` tiene
--   `default null` a propósito, para no tocar el único llamador que ya
--   existe (`apps/web/app/(admin)/admin/politica-salarial/constancias`) ni
--   la prueba 208, que la llama así.
--
-- CÓMO SE REVIERTE
--   drop function fn_acuses_politica_salarial(int);
--   Y volver a aplicar el bloque de fn_acuses_politica_salarial de la 0141
--   (sin parámetro).
-- ============================================================================

drop function if exists fn_acuses_politica_salarial();

create or replace function fn_acuses_politica_salarial(p_version int default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare v_version int; v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver quien acuso la politica.';
  end if;

  if p_version is not null then
    select version into v_version from politica_salarial where version = p_version;
    if v_version is null then
      raise exception 'Esa version de la politica salarial no existe.';
    end if;
  else
    select version into v_version from politica_salarial order by version desc limit 1;
  end if;

  if v_version is null then
    return jsonb_build_object('version', null, 'personas', '[]'::jsonb);
  end if;

  select jsonb_build_object(
    'version', v_version,
    'personas', coalesce(jsonb_agg(jsonb_build_object(
      'persona_id', p.id,
      'nombre',     p.nombres || ' ' || p.apellidos,
      'rango',      s.rango,
      'acusado_at', a.acusado_at,
      'nombre_declarado', a.nombre_declarado
    ) order by (a.acusado_at is not null), p.apellidos, p.nombres), '[]'::jsonb)
  ) into v_out
  from personas p
  left join politica_salarial_acuses a
         on a.persona_id = p.id and a.version = v_version
  left join asignaciones_salario s
         on s.persona_id = p.id and s.vigente_hasta is null
  where p.estado = 'activo' and p.en_planilla is true;

  return v_out;
end;
$fn$;

grant  execute on function fn_acuses_politica_salarial(int) to authenticated;
revoke execute on function fn_acuses_politica_salarial(int) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (458, 'constancias_por_version_historica')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

do $mig$
begin
  raise notice '0458 · fn_acuses_politica_salarial(p_version) ya acepta version historica';
  raise notice '0458 · sin argumento sigue devolviendo la vigente, igual que antes';
end $mig$;
