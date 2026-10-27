-- ============================================================================
-- 0556 · EL PERIODO DE PRUEBA SE PACTA POR PERSONA
-- ============================================================================
--
-- QUÉ PROMETE
--   Una columna nueva, `personas.prueba_pactada_dias`, y la única puerta para
--   cambiarla, `fn_set_prueba_pactada(persona, dias, motivo)`:
--     · NULL ........ rige la ley: tres meses desde el ingreso (art. 10, D.S.
--                     003-97-TR). Es lo que tiene TODA persona hoy y el valor de
--                     partida de un alta nueva.
--     · 1 a 89 ...... un periodo MENOR, pactado por escrito, contado en días
--                     calendario desde el ingreso.
--     · 0 ........... sin periodo de prueba (reingreso, o pacto).
--   Cambiarla pide motivo, deja rastro en `correcciones_auditoria` y solo la
--   mueven la dirección o Desarrollo Organizacional. Un UPDATE directo desde el
--   navegador se rechaza: el mismo molde de `fn_set_sede_base` (0342).
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-26)
--   «A pesar del mínimo de 3 meses, yo puedo darle una fecha inferior, ¿verdad?»
--   Sí: tres meses es el periodo ORDINARIO de la ley, no un mínimo. Las partes
--   pueden pactar uno menor; ampliarlo (6 o 12 meses) es otra cosa, con pacto
--   escrito y justificación, y no entra aquí. Hoy el sistema calculaba tres meses
--   para todos, sin excepción posible. Felipe eligió que la regla por defecto
--   siga siendo los tres meses.
--
-- ⚠ LO QUE HAY QUE SABER ANTES DE USAR UN PERIODO MENOR
--   Acortar la prueba es RENUNCIAR a un derecho de CAYLA: pasado el plazo pactado
--   la persona queda protegida contra el despido arbitrario y terminarle el
--   contrato sin causa cuesta indemnización. Y el pacto tiene que constar POR
--   ESCRITO en el contrato: por eso la cláusula TERCERA de los contratos dice el
--   plazo pactado (mismo PR). Esta migración registra el motivo, pero NO
--   comprueba que exista el papel firmado. Que la ley admita acortar lo confirma
--   el área legal; la doctrina lo acepta por ser más favorable a la persona.
--
-- QUÉ ASUME
--   · `personas`, `correcciones_auditoria`, `fn_es_admin_o_lider` y
--     `fn_persona_actual_id` ya existen. Se comprueba abajo.
--
-- QUÉ NO HACE
--   · NO TOCA LA PLANILLA ni ninguna función de pago. Ni una línea de
--     `fn_planilla_calcular*`: no hay md5 de planilla que pedir a producción.
--   · NO CAMBIA A NADIE: la columna nace vacía, o sea «rige la ley» para todos.
--   · NO CAMBIA `fecha_ingreso` ni el vínculo. La prueba solo se pacta para quien
--     está en planilla.
--   · NO PERMITE más de 89 días: de tres meses para arriba la ley ya da ese
--     periodo, y ampliarlo exige una justificación que esta puerta no recoge.
--   · NO CAMBIA a una persona ya cesada: su liquidación se calculó con lo que
--     regía entonces.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_personas_prueba_solo_por_rpc on personas;
--   drop function if exists fn_bloquear_prueba_directa();
--   drop function if exists fn_set_prueba_pactada(uuid, integer, text);
--   -- ⚠ la columna guarda los pactos: antes de soltarla, exportarlos.
--   alter table personas drop column if exists prueba_pactada_dias;
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final, y la prueba pgTAP 448.
-- ============================================================================

-- ── Guardia ─────────────────────────────────────────────────────────────────
do $guardia$
begin
  if to_regclass('public.correcciones_auditoria') is null
     or to_regprocedure('public.fn_es_admin_o_lider()') is null
     or to_regprocedure('public.fn_persona_actual_id()') is null then
    raise exception 'PARA. Falta algo de base: correcciones_auditoria, fn_es_admin_o_lider o fn_persona_actual_id no existen en esta base.';
  end if;
end
$guardia$;

-- ── 1 · La columna ──────────────────────────────────────────────────────────
alter table personas add column if not exists prueba_pactada_dias smallint;

do $check$
begin
  if not exists (select 1 from pg_constraint where conname = 'personas_prueba_pactada_valida') then
    alter table personas add constraint personas_prueba_pactada_valida
      check (prueba_pactada_dias is null or prueba_pactada_dias between 0 and 89);
  end if;
end
$check$;

comment on column personas.prueba_pactada_dias is
  'Periodo de prueba pactado, en días calendario desde el ingreso. NULL = rige la ley (3 meses, art. 10 del D.S. 003-97-TR). 0 = sin periodo de prueba. 1–89 = menor pactado por escrito. Se cambia SOLO con fn_set_prueba_pactada. 0556.';

-- ── 2 · La puerta ───────────────────────────────────────────────────────────
create or replace function fn_set_prueba_pactada(p_persona_id uuid, p_dias integer, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  smallint;
  v_estado text;
  v_tipo   text;
  v_quien  uuid;
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo la dirección o Desarrollo Organizacional puede pactar el periodo de prueba.';
  end if;

  if p_dias is not null and (p_dias < 0 or p_dias > 89) then
    raise exception 'El periodo de prueba pactado va de 0 a 89 días (llegó %). De tres meses para arriba rige la ley.', p_dias;
  end if;

  select prueba_pactada_dias, estado, tipo_vinculo into v_antes, v_estado, v_tipo
    from personas where id = p_persona_id;
  if not found then
    raise exception 'Persona inválida.';
  end if;

  if v_antes is not distinct from p_dias then
    return;  -- no cambia nada: tampoco se llena el rastro de ruido
  end if;

  if length(v_motivo) < 3 then
    raise exception 'Escribe el motivo: es lo que explica un periodo de prueba distinto del de la ley.';
  end if;
  if v_estado = 'inactivo' then
    raise exception 'No se puede cambiar el periodo de prueba de una persona ya cesada: su liquidación se calculó con el anterior.';
  end if;
  if v_tipo is distinct from 'planilla' then
    raise exception 'El periodo de prueba solo se pacta para quien está en planilla: es una cláusula del contrato de trabajo (art. 10, D.S. 003-97-TR).';
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo dejarlo escrito. Inicia sesión con tu usuario.';
  end if;

  update personas set prueba_pactada_dias = p_dias where id = p_persona_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.prueba_pactada_dias',
          case when v_antes is null then 'la ley (3 meses)' else v_antes || ' días' end,
          case when p_dias  is null then 'la ley (3 meses)' else p_dias  || ' días' end,
          v_motivo, v_quien);
end;
$$;

comment on function fn_set_prueba_pactada(uuid, integer, text) is
  'Pacta el periodo de prueba de una persona en planilla: NULL = la ley (3 meses), 0 = sin prueba, 1–89 = menor en días. Solo admin o DO, con motivo y rastro en correcciones_auditoria. No se permite sobre personas cesadas. Acortar la prueba renuncia a un derecho de CAYLA y debe constar por escrito en el contrato. 0556.';

revoke all on function fn_set_prueba_pactada(uuid, integer, text) from public, anon;
grant execute on function fn_set_prueba_pactada(uuid, integer, text) to authenticated;

-- ── 3 · El candado ──────────────────────────────────────────────────────────
-- Mismo mecanismo que `fn_bloquear_sede_directa` (0342): `fn_set_prueba_pactada`
-- corre `security definer`, así que mientras ejecuta `current_user` es el dueño
-- de la función, no la sesión que la llamó. Un cambio directo desde PostgREST
-- corre como `authenticated`, y el trigger distingue exactamente eso. Cubre el
-- alta también: nadie crea una persona con un pacto escrito a mano.
create or replace function fn_bloquear_prueba_directa()
returns trigger
language plpgsql as $function$
begin
  if current_user <> 'postgres'
     and new.prueba_pactada_dias is distinct from (case when tg_op = 'UPDATE' then old.prueba_pactada_dias else null end) then
    raise exception 'El periodo de prueba pactado se cambia con fn_set_prueba_pactada, no con una escritura directa.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_personas_prueba_solo_por_rpc on personas;
create trigger trg_personas_prueba_solo_por_rpc
  before insert or update on personas
  for each row
  execute function fn_bloquear_prueba_directa();

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (556, 'el_periodo_de_prueba_se_pacta_por_persona')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe dar: true · 0 · true · true · «556 · el_periodo_de_prueba_se_pacta_…»
select
  (select count(*) = 1 from information_schema.columns
    where table_name = 'personas' and column_name = 'prueba_pactada_dias')   as la_columna_existe,
  (select count(*) from personas where prueba_pactada_dias is not null)     as personas_con_pacto_hoy,
  (select prosecdef from pg_proc
    where proname = 'fn_set_prueba_pactada'
      and pronamespace = 'public'::regnamespace)                            as la_puerta_es_security_definer,
  (select count(*) = 1 from pg_trigger
    where tgname = 'trg_personas_prueba_solo_por_rpc'
      and tgrelid = 'personas'::regclass and tgenabled = 'O')               as el_candado_esta_puesto,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 556) as registro;
