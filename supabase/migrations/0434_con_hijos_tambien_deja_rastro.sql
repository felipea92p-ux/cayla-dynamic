-- ============================================================================
-- 0434 · CON_HIJOS TAMBIÉN DEJA RASTRO
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cambiar `personas.con_hijos` deje una fila en `correcciones_auditoria`
--   —quién lo hizo, cuándo, y el valor anterior y el nuevo— igual que ya exige
--   cambiar la sede, el rol o el régimen de pensión. No cambia el permiso, la
--   firma ni ningún otro comportamiento de `fn_set_con_hijos`.
--
-- EL DEFECTO
--   `con_hijos` decide la asignación familiar (S/113/mes, Ley 25129) y entra a
--   `base_provision` de gratificación, CTS y vacaciones
--   (`fn_planilla_calcular_nucleo`). Su única puerta de escritura,
--   `fn_set_con_hijos` (0181), es solo un permiso más un `update` — sin una
--   sola fila de auditoría desde que se creó. Señalado en la auditoría de
--   arquitectura del 2026-09-03 (docs/hallazgos-abiertos.md, sección "Alta"),
--   confirmado hoy con `donde-vive.sh`: sigue en el cuerpo de la 0181, sin
--   cambios.
--
-- QUÉ NO CIERRA ESTA MIGRACIÓN, A PROPÓSITO
--   La misma auditoría señala que `con_hijos` tampoco tiene VIGENCIA por
--   fecha —a diferencia del régimen de pensión desde la 0261— así que
--   `fn_repagar_periodo` sobre un mes ya pagado relee el valor de HOY, no el
--   vigente cuando corrió ese periodo. Ese es un cambio de otro tamaño: exige
--   una tabla de historial (`asignaciones_con_hijos`, al estilo de
--   `asignaciones_regimen_pension`) y tocar `fn_planilla_calcular_nucleo` para
--   que lea por fecha — la función más sensible del repositorio, con su propio
--   protocolo de md5 de producción antes de escribir una sola línea. Se deja
--   aparte, anotado, para no mezclar un candado de auditoría (bajo riesgo) con
--   una reescritura del núcleo de planilla (alto riesgo) en el mismo commit.
--
-- QUÉ ASUME
--   md5 de partida de `fn_set_con_hijos` (0181, sin cambios desde entonces):
--   a5a5f35e8bedd9f128b2b92c05d0e1ff — confirmado en el Postgres local antes
--   de escribir esta migración, y coincide con el que la propia 0181 declaró
--   como correcto en su cabecera. Se pide a PRODUCCIÓN otra vez antes de
--   pegar (ver CLAUDE.md).
--
-- CÓMO SE REVIERTE
--   `create or replace function fn_set_con_hijos` con el cuerpo de la 0181
--   (sin el bloque `-- CAMBIO 0434`).
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El select del final: `md5_incluye_auditoria` tiene que dar `true`.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_set_con_hijos(p_persona_id uuid, p_con_hijos boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_antes boolean;
  v_nuevo boolean := coalesce(p_con_hijos, false);
  v_quien uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la asignación familiar.';
  end if;

  select con_hijos into v_antes from personas where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;

  update personas set con_hijos = v_nuevo where id = p_persona_id;

  -- CAMBIO 0434 · el rastro. `is distinct from` porque `con_hijos` no acepta
  -- null en la tabla (default false), así que "sin cambio" solo puede ser
  -- true=true o false=false — cualquier otro caso es un cambio de verdad.
  if v_nuevo is distinct from v_antes then
    v_quien := fn_persona_actual_id();
    if v_quien is null then
      raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
    end if;
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
    values (p_persona_id, 'personas.con_hijos', v_antes::text, v_nuevo::text,
            'Cambio de asignación familiar — mueve S/113/mes y entra a la base de provisión de grati/CTS/vacaciones.',
            v_quien);
  end if;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (434, 'con_hijos_tambien_deja_rastro')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select (prosrc like '%personas.con_hijos%') as md5_incluye_auditoria
  from pg_proc where proname = 'fn_set_con_hijos';
