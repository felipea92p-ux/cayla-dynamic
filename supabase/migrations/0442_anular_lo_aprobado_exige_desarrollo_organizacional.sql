-- ============================================================================
-- 0442_anular_lo_aprobado_exige_desarrollo_organizacional.sql
-- ============================================================================
-- QUÉ PROMETE
--   fn_anular_ausencia deja de anular, sin más, una ausencia de un tipo que
--   YA fue aprobado por Desarrollo Organizacional (aprobada_at is not null en
--   un tipo con requiere_aprobacion). Anularla ahora exige el mismo permiso
--   que aprobarla: admin o líder de DO — la encargada de sede, que hoy puede
--   anular cualquier ausencia de su sede con solo escribir un motivo, deja de
--   poder deshacer sola una decisión que DO ya tomó.
--
-- QUÉ ASUME
--   Que "aprobada_at is not null" en un tipo con requiere_aprobacion = true
--   significa que hubo una decisión real de DO (fn_aprobar_ausencia, 0101).
--   OJO CON VACACIONES: `vacaciones` tiene paga = true pero
--   requiere_aprobacion = false — nace aprobada automáticamente al
--   registrarse (fn_registrar_ausencia, CASE sobre requiere_aprobacion), sin
--   que DO haya decidido nada. Por eso el candado nuevo mira
--   requiere_aprobacion, no solo aprobada_at: si mirara solo aprobada_at,
--   CUALQUIER vacación —la más rutinaria de las ausencias que se anulan—
--   quedaría bloqueada para la encargada de sede, exactamente el caso que NO
--   se quiso tocar. Comprobado contra el catálogo local antes de escribir
--   esto: hoy solo descanso_medico, maternidad, licencia_con_goce y
--   duelo_familiar_directo tienen requiere_aprobacion = true.
--
-- POR QUÉ ESTE CANDADO Y NO OTRO
--   Se descartó una segunda confirmación de DO (la anulación queda
--   "pendiente" hasta que DO la ratifique): duplicaría el mismo flujo de dos
--   pasos que ya existe para aprobar, y acá es al revés — deshacer, no
--   autorizar— y no necesita la misma ceremonia. Un rechazo directo, con un
--   mensaje que dice a quién pedírselo, es más simple y ya sigue el patrón
--   null-safe de este repo (`fn_es_admin_o_lider() is not true`, nunca
--   `not fn_es_admin_o_lider()`).
--
-- SE ROMPE SI
--   Una encargada de sede necesita corregir HOY un error propio (registró el
--   tipo equivocado) en algo que DO ya aprobó, y DO no está disponible ese
--   mismo día. Con este candado, esa corrección pasa a depender de que un
--   admin o líder de DO la anule — antes lo hacía ella sola. Es el costo
--   aceptado a cambio de que nadie fuera de DO pueda revertir sin que DO se
--   entere una decisión que movió a alguien hacia planilla.
--
-- CÓMO SE REVIERTE
--   Repegar el cuerpo de fn_anular_ausencia tal como está en la 0327 (sin el
--   bloque marcado CAMBIO 0442 más abajo).
--
-- MD5 DE PARTIDA (Postgres LOCAL, no producción — pedir el de producción con
-- donde-vive.sh justo antes de pegar esto, no antes de escribirlo):
--   6bc3d81bc38794a206a3b6249ffc61bd
-- ============================================================================

create or replace function fn_anular_ausencia(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_a ausencias%rowtype; v_editor uuid;
begin
  select * into v_a from ausencias where id = p_id;
  if not found then raise exception 'Esa ausencia ya no existe.'; end if;
  v_editor := fn_verificar_corrector(v_a.persona_id);

  if v_a.anulada_at is not null then raise exception 'Esa ausencia ya estaba anulada.'; end if;

  -- ⇩⇩⇩ CAMBIO 0442 ⇩⇩⇩ Deshacer una aprobación de DO exige el mismo permiso
  -- que darla. Solo mira tipos con requiere_aprobacion: vacaciones paga pero
  -- nunca pasó por una decisión de DO, así que se queda fuera de este candado
  -- (ver "QUÉ ASUME" en el encabezado).
  if v_a.aprobada_at is not null
     and exists (
       select 1 from tipos_ausencia t
       where t.codigo = v_a.tipo and t.requiere_aprobacion
     )
     and fn_es_admin_o_lider() is not true
  then
    raise exception 'Esta ausencia ya fue aprobada por Desarrollo Organizacional — solo un administrador o líder de DO puede anularla. Pídeselo a DO.';
  end if;
  -- ⇧⇧⇧ CAMBIO 0442 ⇧⇧⇧

  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'El motivo de la anulación es obligatorio (mínimo 4 caracteres).';
  end if;

  if exists (
    select 1
    from periodos_planilla pp
    where daterange(pp.fecha_ini, pp.fecha_fin, '[]') && daterange(v_a.fecha_inicio, v_a.fecha_fin, '[]')
      and (
        -- Compatibilidad: un periodo con estado='pagado' pero SIN ninguna fila
        -- en periodo_grupo_pago es de antes de la 0323 (el bucket único de
        -- siempre) — se sigue leyendo por el agregado.
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
        -- El caso normal desde la 0323: el GRUPO de esta persona, no el
        -- periodo entero.
        exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = v_a.persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
    for share
  ) then
    raise exception 'Esas fechas caen en un periodo de planilla ya PAGADO. Reabre el periodo primero.';
  end if;

  update ausencias
     set anulada_at = now(), anulada_por = v_editor, anulada_motivo = trim(p_motivo)
   where id = p_id;
end;
$fn$;
grant execute on function fn_anular_ausencia(uuid, text) to authenticated;
revoke execute on function fn_anular_ausencia(uuid, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (442, 'anular_lo_aprobado_exige_desarrollo_organizacional')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select prosrc like '%CAMBIO 0442%' as candado_presente
  from pg_proc where proname = 'fn_anular_ausencia';
