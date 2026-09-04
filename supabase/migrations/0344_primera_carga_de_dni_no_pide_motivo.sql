-- ============================================================================
-- 0344 — Cargar el DNI por primera vez no exige motivo de cambio
--
-- QUÉ PROMETE. fn_set_documento ya no exige "motivo del cambio" cuando la
--   persona nunca tuvo un DNI registrado: escribirlo por primera vez no es
--   una corrección, es completar un dato que faltaba. El motivo sigue siendo
--   obligatorio cuando SÍ había un DNI antes y se reemplaza por otro — ahí
--   es donde importa dejar rastro, porque ese número se imprime en memos
--   disciplinarios y en los documentos de respaldo.
--
-- QUÉ ASUME. personas, correcciones_auditoria, fn_es_admin_o_lider(),
--   fn_persona_actual_id(). md5 de partida (producción, verificado en el SQL
--   Editor el 2026-09-03, idéntica a esta migración): 6ed5eeef04c61ee0ad669637ee1400c5.
--
-- POR QUÉ SE ELIGIÓ ASÍ. La pantalla de Datos Personales mostraba «Motivo
--   del cambio de DNI (obligatorio) — de vacío a 74779049» al dar de alta a
--   una persona sin ficha todavía, y bloqueaba el guardado hasta escribir
--   algo. No hay ningún cambio que justificar frente a un valor que nunca
--   existió: exigirlo ahí solo entrena a escribir cualquier texto de relleno
--   para poder guardar, que es peor que no pedir nada. La corrección adelanta
--   la lectura de `v_antes` (antes solo servía para el mensaje de auditoría)
--   para poder condicionar la exigencia del motivo sobre ella.
--
-- CÓMO SE REVIERTE. Volver a exigir el motivo siempre, como en la 0125:
--   mover el chequeo de `p_motivo` de vuelta antes del `select ... into v_antes`
--   y quitarle la condición `v_antes is not null`.
-- ============================================================================

create or replace function fn_set_documento(p_persona_id uuid, p_documento text, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes text;
  v_nuevo text;
  v_quien uuid;
  v_otro  text;
begin
  -- Guard null-safe, como manda el estándar del repo: un null no pasa como
  -- autorizado. Se exige admin o líder: el DNI se imprime en papeles legales, así
  -- que no lo edita la encargada ni la propia persona.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el número de documento.';
  end if;

  v_nuevo := nullif(btrim(coalesce(p_documento, '')), '');

  if v_nuevo is null then
    raise exception 'El número de documento no puede quedar vacío. Si está mal, se corrige; no se borra.';
  end if;

  -- Se acepta DNI peruano (8 dígitos, con el cero adelante que traen los de
  -- generación anterior: Carmen Sanándres es 08817189) y carné de extranjería,
  -- que es alfanumérico. Nada más, para que no entre un nombre por error.
  if v_nuevo !~ '^[0-9A-Za-z]{8,12}$' then
    raise exception 'Documento inválido: «%». Se esperan entre 8 y 12 caracteres sin espacios ni guiones.', v_nuevo;
  end if;

  select documento into v_antes from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe.';
  end if;

  -- CAMBIO 0344 — antes se exigía el motivo siempre, incluso cuando `v_antes`
  -- era null (la persona nunca tuvo DNI). Ahora solo se exige cuando de
  -- verdad reemplaza un valor anterior.
  if v_antes is not null and (p_motivo is null or btrim(p_motivo) = '') then
    raise exception 'El motivo es obligatorio: este número se imprime en memos y contratos.';
  end if;

  if v_antes = v_nuevo then
    return;   -- nada que hacer, y así no se ensucia la auditoría
  end if;

  -- Dos personas con el mismo DNI es un error de dedo, no un caso de negocio.
  select nombres || ' ' || apellidos into v_otro
  from personas where documento = v_nuevo and id <> p_persona_id
  limit 1;
  if v_otro is not null then
    raise exception 'Ese documento ya lo tiene %. Abortado para no dejar dos personas con el mismo DNI.', v_otro;
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  update personas set documento = v_nuevo where id = p_persona_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.documento',
          coalesce(v_antes, '(vacío)'), v_nuevo,
          coalesce(nullif(btrim(p_motivo), ''), '(primera carga, sin DNI previo)'), v_quien);
end;
$$;

comment on function fn_set_documento(uuid, text, text) is
  'Corrige o carga por primera vez el número de documento de una persona. Solo admin o líder; '
  'motivo obligatorio solo cuando reemplaza un DNI que ya existía, con rastro en '
  'correcciones_auditoria siempre — porque el DNI se imprime en memos disciplinarios y en los '
  'documentos de respaldo de los conceptos no remunerativos.';

revoke all    on function fn_set_documento(uuid, text, text) from public, anon;
grant execute on function fn_set_documento(uuid, text, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (344, 'primera_carga_de_dni_no_pide_motivo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $fin$
begin
  raise notice '0344 · cargar el DNI por primera vez ya no pide motivo; corregir uno que ya existía, sí.';
end $fin$;
