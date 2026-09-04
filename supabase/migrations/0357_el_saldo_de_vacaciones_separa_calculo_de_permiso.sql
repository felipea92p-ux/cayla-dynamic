-- ============================================================================
-- 0357_el_saldo_de_vacaciones_separa_calculo_de_permiso.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que exista `fn_vacaciones_saldo_interno` — el MISMO cálculo que ya hace
--   `fn_vacaciones_saldo`, sin su guardia de "¿puedes ver el saldo de esta
--   persona?" — y que `fn_generar_alertas_vencimiento` (0356) la use para
--   encolar también avisos de vacaciones por vencer, con el mismo criterio
--   inclusivo que ya usa la pantalla de Ausencias: alerta si falta poco O si
--   ya hay récords vencidos.
--
-- QUÉ ASUME
--   Que `fn_vacaciones_saldo` sigue devolviendo EXACTO lo mismo para EXACTA
--   la misma pregunta — mismo resultado, mismos errores, mismos mensajes.
--   No cambia una coma de su contrato externo. Las pruebas que ya existen
--   sobre ella (263, 270, etc.) son la prueba de que esto es cierto: pasan
--   sin tocarlas.
--
-- ── POR QUÉ SEPARAR, Y NO LLAMAR fn_vacaciones_saldo DESDE EL CRON ──────────
--
-- La 0356 encoló contratos por vencer pero dejó fuera vacaciones, porque
-- `fn_vacaciones_saldo` exige `fn_es_admin_o_lider() is true` y desde
-- pg_cron eso es siempre `false` — no hay sesión. La función tiene DOS
-- responsabilidades entrelazadas: calcular el saldo, y decidir si quien
-- pregunta puede verlo. Un cron no es "alguien preguntando": es el sistema
-- generando su propia cola, con la misma autoridad que ya tiene
-- `fn_auto_cierre` para tocar jornadas directo. Separar las dos preguntas dentro
-- de la misma función deja cada una donde corresponde: `fn_vacaciones_saldo`
-- sigue siendo la única puerta para una pantalla, y `fn_vacaciones_saldo_interno`
-- es la única fuente del cálculo — para la pantalla y para el cron.
--
-- Ninguna de las dos alternativas era aceptable: copiar el cálculo aquí
-- hubiera sido la regla 2 de `packages/shared` con otro nombre (dos lugares
-- respondiendo la misma pregunta, uno que se desactualiza el día que el
-- cálculo cambie); fingir una sesión de un admin cualquiera para pasar la
-- guardia habría dejado auditoría mintiendo — un correo que salió porque
-- corrió el cron a las 8 am se vería como si Felipe hubiera abierto el
-- saldo de otra persona esa madrugada.
--
-- ── POR QUÉ EL CRITERIO INCLUYE "YA VENCIDO", A DIFERENCIA DE CONTRATOS ─────
--
-- La 0356 excluyó a propósito los contratos ya vencidos ("por vencer" no es
-- "ya venció"). Acá no: `fn_vacaciones_por_vencer` (0297) ya decidió, con un
-- caso real de producción documentado en su propio comentario, que un
-- récord YA vencido tiene que seguir avisando — "alguien con dos récords
-- vencidos no salía por ningún lado". El art. 23 del D. Leg. 713 castiga un
-- récord vencido con una remuneración ENTERA de indemnización: es más
-- urgente que uno por vencer, no menos, y silenciarlo sería peor que el
-- problema que esta migración resuelve.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   -- Vuelve fn_generar_alertas_vencimiento a la versión de la 0356 (solo
--   -- contratos) pegando de nuevo su cuerpo desde ahí, y:
--   drop function if exists fn_vacaciones_saldo_interno(uuid, date);
--   Revertir NO afecta a fn_vacaciones_saldo: su contrato externo no cambió.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

-- ── 1 · El cálculo, sin guardia — mismo cuerpo que fn_vacaciones_saldo, ─────
--        menos su bloque de permiso.
create or replace function fn_vacaciones_saldo_interno(p_persona_id uuid, p_as_of date default null)
returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  v_p        personas%rowtype;
  v_as_of    date;
  v_anios    int;
  v_m int; v_d int;
  v_trunco   numeric;
  v_ganados  numeric;
  v_tomados  numeric;
  v_pend     numeric;
  v_k        int;
  v_vencidos int;
  v_vence    date;
begin
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  v_as_of := coalesce(p_as_of, fn_hoy_lima());

  if not fn_devenga(p_persona_id, 'vacaciones') then
    return jsonb_build_object('aplica', false,
      'motivo', 'No devenga vacaciones: su vínculo es ' || v_p.tipo_vinculo || '.');
  end if;

  if v_as_of < v_p.fecha_ingreso then
    return jsonb_build_object('aplica', false, 'motivo', 'Todavía no había ingresado.');
  end if;

  v_anios := floor(extract(year from age(v_as_of, v_p.fecha_ingreso)))::int;
  select meses, dias into v_m, v_d
    from fn_meses_y_dias((v_p.fecha_ingreso + make_interval(years => v_anios))::date, v_as_of);
  v_trunco  := round(15.0 * v_m / 12.0 + 15.0 * v_d / 360.0, 2);
  v_ganados := round(15.0 * v_anios + v_trunco, 2);

  select coalesce(sum(least(v.fecha_fin, v_as_of) - greatest(v.fecha_inicio, v_p.fecha_ingreso) + 1), 0)
    into v_tomados
    from vacaciones v
   where v.persona_id = p_persona_id
     and v.fecha_fin >= v_p.fecha_ingreso and v.fecha_inicio <= v_as_of;

  v_pend := greatest(0, v_ganados - v_tomados);

  v_k        := floor(v_pend / 15.0)::int;
  v_vencidos := greatest(v_k - 1, 0);

  if v_k > 0 then
    v_vence := (v_p.fecha_ingreso + make_interval(years => v_anios + 1))::date;
  end if;

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequeña empresa: 15 días por año',
    'as_of', v_as_of,
    'fecha_ingreso', v_p.fecha_ingreso,
    'anios_completos', v_anios,
    'dias_ganados', v_ganados,
    'dias_gozados', v_tomados,
    'dias_pendientes', v_pend,
    'records_sin_gozar', v_k,
    'records_vencidos', v_vencidos,
    'vence_el', v_vence,
    'dias_para_vencer', case when v_vence is null then null else (v_vence - v_as_of) end
  );
end;
$fn$;
-- Sin grant: nadie de `authenticated` la necesita directo. La pantalla sigue
-- entrando por `fn_vacaciones_saldo`, que es quien decide si puede.

-- ── 2 · fn_vacaciones_saldo pasa a ser guardia + una llamada ───────────────
create or replace function fn_vacaciones_saldo(p_persona_id uuid, p_as_of date default null)
returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  v_p personas%rowtype;
begin
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  if fn_es_admin_o_lider() is not true
     and p_persona_id <> coalesce(fn_persona_actual_id(), '00000000-0000-0000-0000-000000000000'::uuid)
     and not (fn_rol_actual() = 'supervisor_sede'::rol_usuario
              and v_p.sede_base_id = fn_sede_actual_persona()) then
    raise exception 'No puedes ver el saldo de vacaciones de otra persona.';
  end if;

  return fn_vacaciones_saldo_interno(p_persona_id, p_as_of);
end;
$fn$;
grant execute on function fn_vacaciones_saldo(uuid, date) to authenticated;
revoke execute on function fn_vacaciones_saldo(uuid, date) from public, anon;

-- ── 3 · fn_generar_alertas_vencimiento aprende a mirar vacaciones también ──
create or replace function fn_generar_alertas_vencimiento()
returns int
language plpgsql security definer set search_path = public
as $fn$
declare
  v_generadas int := 0;
  v_parcial int;
begin
  insert into alertas (persona_id, tipo, canal, payload)
  select do_.id, 'contrato_por_vencer', 'email',
    jsonb_build_object(
      'evento', p.id::text || '|' || p.fecha_fin_contrato::text,
      'persona_id', p.id,
      'persona', p.nombres || ' ' || p.apellidos,
      'sede', coalesce(s.codigo, '—'),
      'fecha_fin_contrato', p.fecha_fin_contrato,
      'dias_restantes', (p.fecha_fin_contrato - fn_hoy_lima())::int
    )
  from personas p
  left join sedes s on s.id = p.sede_base_id
  cross join (
    select id from personas where rol in ('admin', 'lider_do') and estado = 'activo' and email is not null
  ) do_
  where p.estado = 'activo'
    and p.fecha_fin_contrato is not null
    and p.fecha_fin_contrato >= fn_hoy_lima()
    and p.fecha_fin_contrato <= fn_hoy_lima() + 30
    and not exists (
      select 1 from alertas a
      where a.tipo = 'contrato_por_vencer'
        and a.payload ->> 'evento' = p.id::text || '|' || p.fecha_fin_contrato::text
    );
  get diagnostics v_parcial = row_count;
  v_generadas := v_generadas + v_parcial;

  -- Mismo criterio que fn_vacaciones_por_vencer (0297): por vencer en 60 días
  -- O ya con algún récord vencido — un récord vencido es MÁS urgente, no
  -- menos, y silenciarlo repetiría el bug real que la 0301 tuvo que arreglar.
  insert into alertas (persona_id, tipo, canal, payload)
  select do_.id, 'vacaciones_por_vencer', 'email',
    jsonb_build_object(
      'evento', p.id::text || '|' || (x.r ->> 'vence_el'),
      'persona_id', p.id,
      'persona', p.nombres || ' ' || p.apellidos,
      'sede', coalesce(s.codigo, '—'),
      'dias_pendientes', (x.r ->> 'dias_pendientes')::numeric,
      'records_vencidos', (x.r ->> 'records_vencidos')::int,
      'vence_el', (x.r ->> 'vence_el')::date,
      'dias_para_vencer', (x.r ->> 'dias_para_vencer')::int
    )
  from personas p
  left join sedes s on s.id = p.sede_base_id
  cross join lateral (select fn_vacaciones_saldo_interno(p.id, fn_hoy_lima()) as r) x
  cross join (
    select id from personas where rol in ('admin', 'lider_do') and estado = 'activo' and email is not null
  ) do_
  where p.estado = 'activo'
    and (x.r ->> 'aplica')::boolean is true
    and (x.r ->> 'records_sin_gozar')::int > 0
    and ( (x.r ->> 'dias_para_vencer')::int <= 60 or (x.r ->> 'records_vencidos')::int > 0 )
    and not exists (
      select 1 from alertas a
      where a.tipo = 'vacaciones_por_vencer'
        and a.payload ->> 'evento' = p.id::text || '|' || (x.r ->> 'vence_el')
    );
  get diagnostics v_parcial = row_count;
  v_generadas := v_generadas + v_parcial;

  return v_generadas;
end;
$fn$;

insert into migraciones_aplicadas (numero, nombre)
values (357, 'el_saldo_de_vacaciones_separa_calculo_de_permiso')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_vacaciones_saldo_interno') as fn_interno_creada,
  (select count(*) from pg_proc where proname = 'fn_vacaciones_saldo') as fn_publica_sigue,
  (select pg_get_functiondef('fn_vacaciones_saldo'::regproc)) like '%raise exception%' as fn_publica_sigue_con_guardia;
